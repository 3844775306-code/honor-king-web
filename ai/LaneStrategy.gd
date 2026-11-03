class_name LaneStrategy
extends RefCounted
# 线上英雄策略（0-4分钟推线/防守/默认位置决策）
# 每秒由 HeroAI 调用一次 decide()

var hero: Hero
var perception: AiPerception
var lane: int
var game_time: float = 0.0
var default_bush_pos: Vector3 = Vector3.ZERO
var mid_switched_lane: int = -1
var mid_switch_timer: float = 0.0
var mid_quiet_timer: float = 0.0
var _bush_resolved: bool = false     # 开局时 AI 先于防御塔创建，草丛默认位需等塔生成后重算一次
var pending_lane: int = -1          # 4分钟后团队分推预分配分路


func _init(p_hero: Hero, p_perception: AiPerception, p_lane: int) -> void:
	hero = p_hero
	perception = p_perception
	lane = p_lane
	default_bush_pos = _find_default_bush()


func update_time(gt: float) -> void:
	game_time = gt


# ==================== 默认位置：最外侧塔附近草丛 ====================

func _find_default_bush() -> Vector3:
	var outer_tower := _get_outermost_tower()
	var tower_pos := outer_tower.global_position if outer_tower else _get_lane_default_pos()
	var candidates: Array[Vector3] = []
	var bushes := hero.get_tree().get_nodes_in_group("bush")
	for b in bushes:
		if not (b is Area3D):
			continue
		var dist := tower_pos.distance_to(b.global_position)
		if dist <= 15.0:
			candidates.append(b.global_position)
	if candidates.size() > 0:
		return candidates[randi() % candidates.size()]
	# 无草丛回退：塔附近随机偏移
	return tower_pos + Vector3(randf() * 4.0 - 2.0, 0, randf() * 4.0 - 2.0)


func _get_outermost_tower() -> Turret:
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best: Turret = null
	var best_dist := 9999.0
	for entity in hero.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != hero.team:
			continue
		var turret := entity as Turret
		if _get_turret_lane(turret) != lane:
			continue
		var dist := turret.global_position.distance_to(enemy_crystal)
		if dist < best_dist:
			best_dist = dist
			best = turret
	return best


func _get_enemy_outermost_tower() -> Turret:
	var enemy_team := Config.Team.ENEMY if hero.team == Config.Team.PLAYER else Config.Team.PLAYER
	var own_crystal := Vector3(-53, 0, 53) if hero.team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var best: Turret = null
	var best_dist := 9999.0
	for entity in hero.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != enemy_team:
			continue
		var turret := entity as Turret
		if turret.display_name == "crystal" or _get_turret_lane(turret) != lane:
			continue
		var dist := turret.global_position.distance_to(own_crystal)
		if dist < best_dist:
			best_dist = dist
			best = turret
	if best == null:
		# 本路外塔/高地塔全清：仅当敌方所有普通塔都推完，推进目标才改为水晶
		var towers_left := false
		for entity in hero.get_tree().get_nodes_in_group("turrets"):
			if entity is Turret and (entity as Turret).health > 0 and (entity as Turret).team == enemy_team and (entity as Turret).display_name != "crystal":
				towers_left = true
				break
		if not towers_left:
			for entity in hero.get_tree().get_nodes_in_group("turrets"):
				if entity is Turret and (entity as Turret).health > 0 and (entity as Turret).team == enemy_team and (entity as Turret).display_name == "crystal":
					return entity as Turret
	return best


func _get_enemy_tower_outside_pos() -> Vector3:
	var tower := _get_enemy_outermost_tower()
	if tower == null:
		return Vector3.ZERO
	var own_crystal := Vector3(-53, 0, 53) if hero.team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var dir := (own_crystal - tower.global_position)
	dir.y = 0.0
	if dir.length() < 0.1:
		return Vector3.ZERO
	return tower.global_position + dir.normalized() * (tower.attack_range * 0.01 + 2.0)


func _get_lane_default_pos() -> Vector3:
	# 分路按几何判定（x+z：>0 发育路 / <0 对抗路 / =0 中路），所以默认点也用同样的几何中点，
	# 不能按阵营镜像——之前发育路/对抗路都落在中路对角线上，AI 开局会一起往中路跑。
	match lane:
		AiConfig.Lane.FARM:
			return Vector3(43, 0, 43)
		AiConfig.Lane.MID:
			return Vector3(0, 0, 0)
		AiConfig.Lane.CLASH:
			return Vector3(-43, 0, -43)
	return Vector3.ZERO


func _get_turret_lane(turret: Turret) -> int:
	var s = turret.global_position.x + turret.global_position.z
	if s > 0:
		return AiConfig.Lane.FARM
	elif s < 0:
		return AiConfig.Lane.CLASH
	else:
		return AiConfig.Lane.MID


# ==================== 安全性判断 ====================

# 实体是否处于敌方塔射程内且无敌方小兵掩护
func _is_under_unsafe_tower(entity: GameEntity) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or t.team == hero.team:
			continue
		var turret := t as Turret
		if entity.global_position.distance_to(turret.global_position) > AiConfig.TOWER_ATTACK_RANGE:
			continue
		# 塔附近有我方小兵掩护？
		var friendly_hp := 0.0
		for m in hero.get_tree().get_nodes_in_group("minions"):
			if not (m is Minion) or m.health <= 0 or m.team != hero.team:
				continue
			if turret.global_position.distance_to(m.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				friendly_hp += (m as Minion).health
		if friendly_hp < AiConfig.UNSAFE_TOWER_MINION_HP:
			return true
	return false


# 实体是否处于己方塔下
func _is_under_own_tower(entity: GameEntity) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or t.team != entity.team:
			continue
		if entity.global_position.distance_to(t.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
			return true
	return false


# ==================== 目标搜索（25m内优先级） ====================

# 优先级: 敌方小兵(安全) > 敌方英雄(不在塔下) > 附近野怪(中路跳过) > 敌方防御塔(4分钟后+安全)
func _find_target() -> GameEntity:
	# 1. 敌方小兵 — 仅攻击不在敌方塔下的
	if hero.last_attacker and hero.last_attacker is Hero and hero.last_attacker.health >0:
		var entity = hero.last_attacker
		if not(_is_under_own_tower(entity) and entity.health > 0.2 * entity.max_health) and not entity.is_untargetable_by_enemies():
			var dist := hero.global_position.distance_to(entity.global_position)
			if dist < 12:
				return hero.last_attacker
	var best_minion: Minion = null
	var best_minion_hp := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > 12:
			continue
		# 无己方小兵掩护的塔下目标不追（避免 AI 追残兵送塔）
		if _is_under_unsafe_tower(entity):
			continue
		var m := entity as Minion
		if m.health < best_minion_hp:
			best_minion_hp = m.health
			best_minion = m
	if best_minion:
		return best_minion
	# 2. 敌方英雄 — 不在其己方塔下
	var best_hero: Hero = null
	var best_hero_hp := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > 12:
			continue
		if _is_under_own_tower(entity) and entity.health > 0.2 * entity.max_health:
			continue
		var h := entity as Hero
		if h.is_untargetable_by_enemies():
			continue
		if h.health < best_hero_hp:
			best_hero_hp = h.health
			best_hero = h
	if best_hero:
		return best_hero
	

	


	# 4. 敌方防御塔（4分钟以后 + 有兵线掩护）
	
	var best_tower: Turret = null
	var best_tower_dist := 9999.0
	for entity in hero.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team == hero.team:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > 15:
			continue
		# 塔下无兵=不安全
		var friendly_hp := 0.0
		for m in hero.get_tree().get_nodes_in_group("minions"):
			if not (m is Minion) or m.health <= 0 or m.team != hero.team:
				continue
			if entity.global_position.distance_to(m.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				friendly_hp += (m as Minion).health
		if friendly_hp < 500:
			continue
		if dist < best_tower_dist:
			best_tower_dist = dist
			best_tower = entity as Turret
	if best_tower:
		return best_tower
		# 3. 附近野怪（中路跳过，仅攻击敌方半区野怪）
	if lane != AiConfig.Lane.MID:
		var own_crystal := Vector3(-53, 0, 53) if hero.team == Config.Team.PLAYER else Vector3(53, 0, -53)
		var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
		var best_jg: JungleMonster = null
		var best_jg_dist := 9999.0
		for entity in hero.get_tree().get_nodes_in_group("jungle_monsters"):
			if not (entity is JungleMonster) or entity.health <= 0:
				continue
			var dist := hero.global_position.distance_to(entity.global_position)
			if dist > AiConfig.LANE_SEARCH_RANGE:
				continue
			# 仅攻击敌方半区野怪（距敌方水晶比距己方水晶更近）
			var jg := entity as JungleMonster
			if jg.global_position.distance_to(enemy_crystal) >= jg.global_position.distance_to(own_crystal):
				continue
			if dist < best_jg_dist:
				best_jg_dist = dist
				best_jg = jg
		if best_jg:
			return best_jg

	return null


# ==================== 防守判断 ====================

# 25m内我方英雄血量总和 < 敌方英雄血量总和 × 0.6
func _is_defensive() -> bool:
	var ally_hp := hero.health
	var enemy_hp := 0.0
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity == hero:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > AiConfig.LANE_SEARCH_RANGE:
			continue
		var h := entity as Hero
		if h.is_untargetable_by_enemies():
			continue
		if h.team == hero.team:
			ally_hp += h.health
		else:
			enemy_hp += h.health
	if enemy_hp <= 0:
		return false
	return ally_hp < enemy_hp * AiConfig.DEFENSIVE_HP_RATIO


# 防守位置：最外侧塔中心 + 朝己方水晶偏移1m
func _get_defensive_position() -> Vector3:
	var tower := _get_outermost_tower()
	if tower:
		var own_crystal := Vector3(-53, 0, 53) if hero.team == Config.Team.PLAYER else Vector3(53, 0, -53)
		var dir := (own_crystal - tower.global_position).normalized()
		return tower.global_position + dir * 1.0
	return _get_lane_default_pos()


# ==================== 中路特殊规则 ====================

# 本路是否有敌方小兵（含视野外）
func _has_enemy_minions_on_lane(ln: int) -> bool:
	for entity in hero.get_tree().get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0:
			continue
		if entity.team == hero.team:
			continue
		var m := entity as Minion
		if m.line == ln:
			return true
	return false


# 中路：无目标且敌方本路无兵线 → 随机换边路（开局保护 + 静默计时，避免开局/兵线间隙就走）
func _try_mid_switch() -> void:
	if lane != AiConfig.Lane.MID:
		return
	if mid_switched_lane >= 0:
		return
	# 开局第一波兵还没交火时中路必然是“空的”，此时换边等于法师永远不走中路
	if game_time < AiConfig.MID_SWITCH_GRACE:
		return
	if _find_target() != null:
		mid_quiet_timer = 0.0
		return
	if _has_enemy_minions_on_lane(AiConfig.Lane.MID):
		mid_quiet_timer = 0.0
		return
	mid_quiet_timer += AiConfig.LANE_THINK_INTERVAL
	if mid_quiet_timer < AiConfig.MID_SWITCH_QUIET:
		return
	mid_quiet_timer = 0.0
	mid_switched_lane = AiConfig.Lane.FARM if randf() < 0.5 else AiConfig.Lane.CLASH
	mid_switch_timer = 0.0
	lane = mid_switched_lane
	default_bush_pos = _find_default_bush()


# 被换边路后：中路塔被攻击 或 无目标>30秒 → 换回中路
func _try_mid_switch_back() -> void:
	if mid_switched_lane < 0:
		return
	mid_switch_timer += 1.0

	var mid_tower_threatened := _is_mid_tower_threatened()
	var idle_too_long := mid_switch_timer > AiConfig.MID_SWITCH_COOLDOWN and _find_target() == null

	if mid_tower_threatened or idle_too_long:
		lane = AiConfig.Lane.MID
		mid_switched_lane = -1
		mid_switch_timer = 0.0
		mid_quiet_timer = 0.0
		default_bush_pos = _find_default_bush()


func _is_mid_tower_threatened() -> bool:
	for entity in hero.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != hero.team:
			continue
		var turret := entity as Turret
		if _get_turret_lane(turret) != AiConfig.Lane.MID:
			continue
		for e in hero.get_tree().get_nodes_in_group("entities"):
			if not (e is GameEntity) or e.health <= 0 or e.team == hero.team:
				continue
			if turret.global_position.distance_to(e.global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				return true
	return false


# ==================== 分路切换 ====================

# 尝试切换到预分配分路（无目标时）
func try_switch_lane() -> void:
	if pending_lane >= 0 and pending_lane != lane:
		if hero.manual_target == null:
			lane = pending_lane
			pending_lane = -1
			mid_switched_lane = -1
			mid_switch_timer = 0.0
			mid_quiet_timer = 0.0
			default_bush_pos = _find_default_bush()


# 查找本路血量>500的己方小兵中最靠前（最接近敌方水晶）的位置
func _get_forward_minion_pos() -> Vector3:
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best_pos := Vector3.ZERO
	var best_dist := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0 or entity.team != hero.team:
			continue
		var m := entity as Minion
		if m.line != lane:
			continue
		if m.health <= 500.0:
			continue
		var dist := m.global_position.distance_to(enemy_crystal)
		if dist < best_dist:
			best_dist = dist
			best_pos = m.global_position
	return best_pos


# ==================== 主决策（每秒） ====================

func _pick_nearer_goal(a: Vector3, b: Vector3) -> Vector3:
	if a == Vector3.ZERO:
		return b
	if b == Vector3.ZERO:
		return a
	return a if hero.global_position.distance_to(a) <= hero.global_position.distance_to(b) else b


func decide(force_push: bool = false) -> void:
	# 开局 AI 先于防御塔创建，默认草丛位当时算不准：塔生成后补算一次
	if not _bush_resolved:
		var turrets := hero.get_tree().get_nodes_in_group("turrets")
		if turrets.size() > 0:
			default_bush_pos = _find_default_bush()
			_bush_resolved = true

	# 尝试执行预分配分路切换
	try_switch_lane()

	# 中路特殊规则
	if lane == AiConfig.Lane.MID:
		_try_mid_switch()
	elif mid_switched_lane >= 0:
		_try_mid_switch_back()

	# 防守判断：团队推线/推塔任务下不由本地防守逻辑接管，避免退回己方最前线塔。
	if not force_push and _is_defensive():
		hero.move_target = _get_defensive_position()
		hero.manual_target = null
		return

	 #追击目标
	
	var target := _find_target()
	if target:
		hero.manual_target=target
		
		return

	# 默认位置：己方兵线 / 敌方塔外兵线，选距离自己更近的一个
	var forward_minion := _get_forward_minion_pos()
	var enemy_line := Vector3.ZERO
	if force_push or game_time >= AiConfig.EARLY_GAME_END:
		enemy_line = _get_enemy_tower_outside_pos()
	var push_goal := _pick_nearer_goal(forward_minion, enemy_line)
	if push_goal != Vector3.ZERO:
		hero.move_target = push_goal
		hero.manual_target = null
	elif force_push:
		# 推线任务两侧都没有兵线：不在本路时先回本路等待，已在路上则原地等下一波。
		var lane_goal := _get_lane_default_pos()
		if lane_goal != Vector3.ZERO and hero.global_position.distance_to(lane_goal) > 12.0:
			hero.move_target = lane_goal
		else:
			hero.move_target = hero.global_position
		hero.manual_target = null
	elif default_bush_pos != Vector3.ZERO:
		hero.move_target = default_bush_pos
		hero.manual_target = null


