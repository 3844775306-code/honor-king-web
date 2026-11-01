class_name JungleStrategy
extends RefCounted
# 打野路线策略（0-4分钟循环路线）
# 路线: 发育路半区 → 中路 → 对抗路半区 → 发育路/对抗路 → 循环

enum JunglePhase { FARM_HALF,  CLASH_HALF, LANE }

var hero: Hero
var perception: AiPerception
var current_phase: int = JunglePhase.FARM_HALF
var jungle_mode: bool = false
var pending_lane: int = -1              # 4分钟后团队分推预分配分路
var assigned_lane: int = -1             # LANE阶段被分配的具体边路
var _phase_cycle: Array = []       # 阶段循环序列
var _phase_index: int = 0            # 当前阶段在循环中的索引
var game_time: float = 0.0
var _lane_timer: float = 0.0
var _lane_default_bush: Vector3 = Vector3.ZERO


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception
	assigned_lane = AiConfig.Lane.FARM
	# 随机选择路线：FARM→LANE→CLASH→LANE 或 CLASH→LANE→FARM→LANE
	if randf() < 0.5:
		_phase_cycle = [JunglePhase.FARM_HALF, JunglePhase.LANE, JunglePhase.CLASH_HALF, JunglePhase.LANE]
	else:
		_phase_cycle = [JunglePhase.CLASH_HALF, JunglePhase.LANE, JunglePhase.FARM_HALF, JunglePhase.LANE]
	current_phase = _phase_cycle[0]
	_phase_index = 0


func update_time(gt: float) -> void:
	game_time = gt


# ==================== 野区判断 ====================

# 判断位置属于下半片还是上半片野区
# 下半片：距己方水晶 < 距敌方水晶 且 abs(X) < abs(Z)
func _is_bottom_half(pos: Vector3) -> bool:
	var own_crystal := Vector3(-53, 0, 53) if hero.team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var closer_to_own := pos.distance_to(own_crystal) < pos.distance_to(enemy_crystal)
	var x_less_than_z := pos.x + pos.z >0
	return closer_to_own and x_less_than_z


# 野区是否已清空（范围内无存活野怪）
func _is_jungle_clear(center: Vector3, radius: float) -> bool:
	for entity in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		if center.distance_to(entity.global_position) <= radius:
			return false
	return true


# 获取当前阶段野区中心点
func _get_jungle_center() -> Vector3:
	var is_blue := hero.team == Config.Team.PLAYER
	match current_phase:
		JunglePhase.FARM_HALF:
			return Vector3(-20, 0, 40) if is_blue else Vector3(20, 0, -40)
		JunglePhase.CLASH_HALF:
			return Vector3(-40, 0, 20) if is_blue else Vector3(40, 0, -20)
	return Vector3.ZERO


# ==================== 目标搜索 ====================

# 打野模式目标：附近10m内敌方英雄 > 野区内野怪
func _find_jungle_target() -> GameEntity:
	# 1. 10m内敌方英雄
	if hero.last_attacker and hero.last_attacker is Hero and hero.last_attacker.health >0:
		var entity = hero.last_attacker
		if not(_is_under_own_tower(entity) and entity.health > 0.2 * entity.max_health) and not entity.is_untargetable_by_enemies():
			var dist := hero.global_position.distance_to(entity.global_position)
			if dist < 12:
				return hero.last_attacker
	var best_hero: Hero = null
	var best_hp := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > AiConfig.JUNGLE_HERO_SEARCH_RANGE:
			continue
		var h := entity as Hero
		if h.is_untargetable_by_enemies():
			continue
		if h.health < best_hp:
			best_hp = h.health
			best_hero = h
	if best_hero:
		return best_hero

	# 2. 野区内野怪
	var jg_center := _get_jungle_center()
	var best_jg: JungleMonster = null
	var best_dist := 9999.0
	for entity in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		var m := entity as JungleMonster
		if not _is_bottom_half(m.global_position) and current_phase == JunglePhase.FARM_HALF:
			continue
		if _is_bottom_half(m.global_position) and current_phase == JunglePhase.CLASH_HALF:
			continue
		var dist := hero.global_position.distance_to(m.global_position)
		if dist < best_dist:
			best_dist = dist
			best_jg = m
	return best_jg


# 线上模式目标（含塔安全检测）
func _find_lane_target() -> GameEntity:
	# 1. enemy heroes (not under own tower, not stealthed/invincible)
	var best_hero: Hero = null
	var best_hero_hp := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > AiConfig.LANE_SEARCH_RANGE:
			continue
		var h := entity as Hero
		if h.is_untargetable_by_enemies():
			continue
		if _is_under_own_tower(h):
			continue
		if h.health < best_hero_hp:
			best_hero_hp = h.health
			best_hero = h
	if best_hero:
		return best_hero

	# 2. enemy minions (not under unsafe enemy tower)
	var best_minion: Minion = null
	var best_minion_hp := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > AiConfig.LANE_SEARCH_RANGE:
			continue
		if _is_under_unsafe_tower(entity):
			continue
		var m := entity as Minion
		if m.health < best_minion_hp:
			best_minion_hp = m.health
			best_minion = m
	if best_minion:
		return best_minion

	# 3. enemy turrets (after 4min + minion cover)
	if game_time >= AiConfig.EARLY_GAME_END:
		var best_tower: Turret = null
		var best_tower_dist := 9999.0
		for entity in hero.get_tree().get_nodes_in_group("turrets"):
			if not (entity is Turret) or entity.health <= 0 or entity.team == hero.team:
				continue
			var dist := hero.global_position.distance_to(entity.global_position)
			if dist > AiConfig.LANE_SEARCH_RANGE:
				continue
			var friendly_hp := 0.0
			for m in hero.get_tree().get_nodes_in_group("minions"):
				if not (m is Minion) or m.health <= 0 or m.team != hero.team:
					continue
				var td = entity.global_position.distance_to(m.global_position)
				if td <= AiConfig.TOWER_ATTACK_RANGE:
					friendly_hp += (m as Minion).health
			if friendly_hp < AiConfig.UNSAFE_TOWER_MINION_HP:
				continue
			if dist < best_tower_dist:
				best_tower_dist = dist
				best_tower = entity as Turret
		if best_tower:
			return best_tower

	return null
# 实体是否处于敌方塔射程内且无敌方小兵掩护
func _is_under_unsafe_tower(entity: GameEntity) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or t.team == hero.team:
			continue
		var turret := t as Turret
		if entity.global_position.distance_to(turret.global_position) > AiConfig.TOWER_ATTACK_RANGE:
			continue
		var friendly_hp := 0.0
		for m in hero.get_tree().get_nodes_in_group("minions"):
			if not (m is Minion) or m.health <= 0 or m.team != hero.team:
				continue
			if turret.global_position.distance_to(m.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				friendly_hp += (m as Minion).health
		if friendly_hp < AiConfig.UNSAFE_TOWER_MINION_HP:
			return true
	return false

# 实体是否处于己方（该实体阵营的）塔下
func _is_under_own_tower(entity: GameEntity) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or t.team != entity.team:
			continue
		if entity.global_position.distance_to(t.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
			return true
	return false
func _try_enter_jungle_mode() -> bool:
	if jungle_mode:
		return true
	# 检查是否到达当前阶段的野区
	var jg_center := _get_jungle_center()
	var dist := hero.global_position.distance_to(jg_center)
	if dist <= 30.0:  # 接近野区
		if not _is_jungle_clear(jg_center, 50.0):
			jungle_mode = true
			return true
	return false


func _check_jungle_clear() -> bool:
	if not jungle_mode:
		return true
	var jg_center := _get_jungle_center()
	if _is_jungle_clear(jg_center, 50.0):
		jungle_mode = false
		_advance_phase()
		return true
	return false



func _advance_phase() -> void:
	_phase_index = (_phase_index + 1) % _phase_cycle.size()
	current_phase = _phase_cycle[_phase_index]
	jungle_mode = false
	_lane_timer = 0.0
	if current_phase == JunglePhase.LANE:
		assigned_lane = _get_nearest_enemy_lane()
		_lane_default_bush = _get_lane_default_bush()

# ==================== 线上模式辅助 ====================

# 选择敌方小兵离自己最近的分路
func _get_nearest_enemy_lane() -> int:
	var lanes := [AiConfig.Lane.FARM, AiConfig.Lane.CLASH,AiConfig.Lane.MID]
	var best_lane := AiConfig.Lane.FARM
	var best_dist := 99999.0
	for ln in lanes:
		for entity in hero.get_tree().get_nodes_in_group("minions"):
			if not (entity is Minion) or entity.health <= 0 or entity.team == hero.team:
				continue
			var m := entity as Minion
			if m.line != ln:
				continue
			var dist := hero.global_position.distance_to(m.global_position)
			if dist < best_dist:
				best_dist = dist
				best_lane = ln
	return best_lane


	# 查找分配分路上血量>500的己方小兵中最靠前的位置
func _get_lane_forward_minion_pos() -> Vector3:
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best_pos := Vector3.ZERO
	var best_dist := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0 or entity.team != hero.team:
			continue
		var m := entity as Minion
		if m.line != assigned_lane:
			continue
		if m.health <= 500.0:
			continue
		var dist := m.global_position.distance_to(enemy_crystal)
		if dist < best_dist:
			best_dist = dist
			best_pos = m.global_position
	return best_pos

# 获取分配分路默认草丛位置
func _get_lane_default_bush() -> Vector3:
	var outer_tower := _get_lane_outermost_tower()
	var tower_pos := outer_tower.global_position if outer_tower else _get_lane_default_pos()
	var candidates: Array[Vector3] = []
	for b in hero.get_tree().get_nodes_in_group("bush"):
		if not (b is Area3D):
			continue
		var dist := tower_pos.distance_to(b.global_position)
		if dist <= 15.0:
			candidates.append(b.global_position)
	if candidates.size() > 0:
		return candidates[randi() % candidates.size()]
	return tower_pos + Vector3(randf() * 4.0 - 2.0, 0, randf() * 4.0 - 2.0)

# 获取分配分路的最外侧塔
func _get_lane_outermost_tower() -> Turret:
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best: Turret = null
	var best_dist := 9999.0
	for entity in hero.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != hero.team:
			continue
		var turret := entity as Turret
		if _get_turret_lane(turret) != assigned_lane:
			continue
		var dist := turret.global_position.distance_to(enemy_crystal)
		if dist < best_dist:
			best_dist = dist
			best = turret
	return best

# 获取分配分路的默认位置
func _get_lane_default_pos() -> Vector3:
	var is_blue := hero.team == Config.Team.PLAYER
	match assigned_lane:
		AiConfig.Lane.FARM:
			return Vector3(-30, 0, 30) if is_blue else Vector3(30, 0, -30)
		AiConfig.Lane.CLASH:
			return Vector3(30, 0, -30) if is_blue else Vector3(-30, 0, 30)
	return Vector3.ZERO

# 判断塔属于哪条分路
func _get_turret_lane(turret: Turret) -> int:
	var s = turret.global_position.x + turret.global_position.z
	if s > 0:
		return AiConfig.Lane.FARM
	elif s < 0:
		return AiConfig.Lane.CLASH
	else:
		return AiConfig.Lane.MID


# ==================== 分路切换 ====================

func try_switch_lane() -> void:
	if pending_lane >= 0 and pending_lane != AiConfig.Lane.JUNGLE:
		if hero.manual_target == null:
			assigned_lane = pending_lane
			pending_lane = -1
			current_phase = JunglePhase.LANE
			jungle_mode = false
			_lane_timer = 0.0
			_lane_default_bush = _get_lane_default_bush()


# ==================== 主决策（每0.5秒） ====================

func decide() -> void:
	try_switch_lane()

	match current_phase:
		JunglePhase.FARM_HALF, JunglePhase.CLASH_HALF:
			# 尝试进入打野模式
			if not jungle_mode:
				if not _try_enter_jungle_mode():
					# 还没到野区 → 朝野区中心移动
					hero.move_target = _get_jungle_center()
					hero.manual_target = null
					return
			# 检查野区是否已清空
			if _check_jungle_clear():
				_advance_phase()
				return
			# 打野模式：追击目标
			var target := _find_jungle_target()
			if target:
				hero.manual_target = target
			else:
				_advance_phase()

			


		JunglePhase.LANE:
			_lane_timer += 0.5
			# 最多30秒后返回打野
			if _lane_timer >= 30.0:
				_advance_phase()
				return

			# 与分路AI相同：多层优先级搜索目标
			var lane_target := _find_lane_target()
			if lane_target:
				hero.manual_target = lane_target
				return

			# 默认：跟随前方小兵，否则去草丛
			var fwd := _get_lane_forward_minion_pos()
			if fwd != Vector3.ZERO:
				hero.move_target = fwd
				hero.manual_target = null
			elif _lane_default_bush != Vector3.ZERO:
				hero.move_target = _lane_default_bush
				hero.manual_target = null
