class_name AiPerception
extends RefCounted

var hero: Hero


# ==================== 共享实体快照（0.1s） ====================
# 每个 AI 英雄每帧都遍历一次 "entities" 组，成本随英雄数线性增长；这里按 TTL 缓存组列表，
# 所有 AiPerception 实例共用一份（距离/队伍/类型过滤仍在调用处逐个做），过期或换场景后重建。
const CACHE_TTL: float = 0.1

static var _cache_tree_id: int = 0
static var _cache_nodes: Array = []
static var _cache_time: float = -1e9

# 防御塔单独缓存：Turret 不走 GameEntity.setup()，因此不在 "entities" 组里，只能查 "turrets"
static var _turret_tree_id: int = 0
static var _turret_nodes: Array = []
static var _turret_time: float = -1e9


static func _shared_nodes(tree: SceneTree) -> Array:
	var now: float = Time.get_ticks_msec() * 0.001
	var tid: int = tree.get_instance_id()
	if tid != _cache_tree_id or now - _cache_time > CACHE_TTL:
		_cache_tree_id = tid
		_cache_time = now
		_cache_nodes = tree.get_nodes_in_group("entities")
	return _cache_nodes


# ==================== 初始化 ====================
func _init(p_hero: Hero) -> void:
	hero = p_hero


# ==================== 底层通用查询 ====================

# 获取范围内所有实体，按类型/队伍/自定义条件过滤
func query_in_range(radius: float,
					type_filter: Array = [],          # 空=所有类型
					team_filter: int = -1,            # -1=所有队伍
					exclude_self: bool = true,
					extra_condition: Callable = Callable()) -> Array[GameEntity]:
	var result: Array[GameEntity] = []
	var tree := hero.get_tree()
	if not tree:
		return result
	for entity in _shared_nodes(tree):
		if not _is_valid(entity):
			continue
		if exclude_self and entity == hero:
			continue
		if not type_filter.is_empty() and not _matches_type(entity, type_filter):
			continue
		if team_filter >= 0 and entity.team != team_filter:
			continue
		if hero.global_position.distance_to(entity.global_position) > radius:
			continue
		if extra_condition.is_valid() and not extra_condition.call(entity):
			continue
		result.append(entity as GameEntity)
	return result


# 找最近的实体
func find_nearest_in_range(radius: float,
						   type_filter: Array = [],
						   team_filter: int = -1,
						   exclude_self: bool = true,
						   extra_condition: Callable = Callable()) -> GameEntity:
	var best: GameEntity = null
	var best_dist: float = radius + 1.0
	var tree := hero.get_tree()
	if not tree:
		return null
	for entity in _shared_nodes(tree):
		if not _is_valid(entity):
			continue
		if exclude_self and entity == hero:
			continue
		if not type_filter.is_empty() and not _matches_type(entity, type_filter):
			continue
		if team_filter >= 0 and entity.team != team_filter:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist > radius or dist >= best_dist:
			continue
		if extra_condition.is_valid() and not extra_condition.call(entity):
			continue
		best_dist = dist
		best = entity as GameEntity
	return best


# 计数范围内实体
func count_in_range(radius: float,
					type_filter: Array = [],
					team_filter: int = -1,
					exclude_self: bool = true,
					extra_condition: Callable = Callable()) -> int:
	var count := 0
	var tree := hero.get_tree()
	if not tree:
		return 0
	for entity in _shared_nodes(tree):
		if not _is_valid(entity):
			continue
		if exclude_self and entity == hero:
			continue
		if not type_filter.is_empty() and not _matches_type(entity, type_filter):
			continue
		if team_filter >= 0 and entity.team != team_filter:
			continue
		if hero.global_position.distance_to(entity.global_position) > radius:
			continue
		if extra_condition.is_valid() and not extra_condition.call(entity):
			continue
		count += 1
	return count


# 以任意中心点计数
func count_near_center(center: Vector3, radius: float,
					   type_filter: Array = [],
					   team_filter: int = -1,
					   extra_condition: Callable = Callable()) -> int:
	var count := 0
	var tree := hero.get_tree()
	if not tree:
		return 0
	for entity in _shared_nodes(tree):
		if not _is_valid(entity):
			continue
		if not type_filter.is_empty() and not _matches_type(entity, type_filter):
			continue
		if team_filter >= 0 and entity.team != team_filter:
			continue
		if center.distance_to(entity.global_position) > radius:
			continue
		if extra_condition.is_valid() and not extra_condition.call(entity):
			continue
		count += 1
	return count


# ==================== 便捷查询 ====================

# --- 敌方英雄 ---
func count_enemy_heroes_near(radius: float) -> int:
	return count_in_range(radius, [Hero], _enemy_team(), true, _is_visible_hero)


func find_nearest_enemy_hero(radius: float) -> Hero:
	return find_nearest_in_range(radius, [Hero], _enemy_team(), true, _is_visible_hero) as Hero


# 指定位置附近的可见敌方英雄数量（回城点安全性判断用）
func count_enemy_heroes_near_center(center: Vector3, radius: float) -> int:
	return count_near_center(center, radius, [Hero], _enemy_team(), _is_visible_hero)


# --- 己方英雄 ---
func count_ally_heroes_near(radius: float) -> int:
	return count_in_range(radius, [Hero], hero.team, true)


# --- 敌方小兵 ---
func find_nearest_enemy_minion(radius: float) -> Minion:
	return find_nearest_in_range(radius, [Minion], _enemy_team(), true, _is_collidable) as Minion


func count_enemy_minions_near(center: Vector3, radius: float) -> int:
	return count_near_center(center, radius, [Minion], _enemy_team(), _is_collidable)


# --- 己方小兵 ---
func find_nearest_ally_minion_on_lane(lane: int) -> Minion:
	var best: Minion = null
	var best_dist: float = AiConfig.INFINITE_RANGE
	var tree := hero.get_tree()
	if not tree:
		return null
	for entity in tree.get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.team != hero.team or entity.health <= 0:
			continue
		if entity.line != lane:
			continue
		var dist := hero.global_position.distance_to(entity.global_position)
		if dist < best_dist:
			best_dist = dist
			best = entity as Minion
	return best


func count_ally_minions_near(center: Vector3, radius: float) -> int:
	return count_near_center(center, radius, [Minion], hero.team)


# --- 防御塔 ---
func find_nearest_friendly_turret(radius: float) -> Turret:
	return _nearest_turret(radius, hero.team)


func find_nearest_enemy_turret(radius: float) -> Turret:
	return _nearest_turret(radius, _enemy_team())


static func _shared_turrets(tree: SceneTree) -> Array:
	var now: float = Time.get_ticks_msec() * 0.001
	var tid: int = tree.get_instance_id()
	if tid != _turret_tree_id or now - _turret_time > CACHE_TTL:
		_turret_tree_id = tid
		_turret_time = now
		_turret_nodes = tree.get_nodes_in_group("turrets")
	return _turret_nodes


# 最近的己方/敌方防御塔（含水晶）
func _nearest_turret(radius: float, team: int) -> Turret:
	var tree := hero.get_tree()
	if not tree:
		return null
	var best: Turret = null
	var best_dist := radius + 1.0
	for entity in _shared_turrets(tree):
		# 必须先判有效性：对已释放实例做 `is Turret` 会抛 "Left operand of 'is' is a previously freed instance"
		if not is_instance_valid(entity):
			continue
		if not (entity is Turret):
			continue
		var turret := entity as Turret
		if turret.health <= 0 or turret.team != team:
			continue
		var dist: float = hero.global_position.distance_to(turret.global_position)
		if dist > radius or dist >= best_dist:
			continue
		best_dist = dist
		best = turret
	return best


# --- 野怪 ---
func find_nearest_jungle() -> JungleMonster:
	return find_nearest_in_range(AiConfig.INFINITE_RANGE, [JungleMonster], Config.Team.NEUTRAL, true, _is_collidable) as JungleMonster


# --- 血包 ---
func find_nearest_health_pack() -> HealthPack:
	var best: HealthPack = null
	var best_dist: float = AiConfig.INFINITE_RANGE
	var packs := hero.get_tree().get_nodes_in_group("health_packs")
	for p in packs:
		if not (p is HealthPack):
			continue
		var pack := p as HealthPack
		if not pack.available or pack.team != hero.team:
			continue
		var dist := hero.global_position.distance_to(pack.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pack
	return best

func find_health_pack_on_lane(lane: int) -> HealthPack:
	var best: HealthPack = null
	var best_dist: float = AiConfig.INFINITE_RANGE
	var packs := hero.get_tree().get_nodes_in_group("health_packs")
	for p in packs:
		if not (p is HealthPack):
			continue
		var pack := p as HealthPack
		if not pack.available or pack.team != hero.team:
			continue
		if _get_health_pack_lane(pack.global_position) != lane:
			continue
		var dist := hero.global_position.distance_to(pack.global_position)
		if dist < best_dist:
			best_dist = dist
			best = pack
	return best

func _get_health_pack_lane(pos: Vector3) -> int:
	var s = pos.x + pos.z
	if s > 0:
		return AiConfig.Lane.FARM
	elif s < 0:
		return AiConfig.Lane.CLASH
	else:
		return AiConfig.Lane.MID


# --- 草丛 ---
func find_nearest_bush(radius: float) -> Vector3:
	var best_pos := Vector3.ZERO
	var best_dist: float = radius + 1.0
	var bushes := hero.get_tree().get_nodes_in_group("bush")
	for b in bushes:
		if not (b is Area3D):
			continue
		var dist := hero.global_position.distance_to(b.global_position)
		if dist < best_dist:
			best_dist = dist
			best_pos = b.global_position
	return best_pos


# ==================== 综合感知快照 ====================
# 一次调用获取当前战术全景（供 _decide 使用）
func snapshot() -> Dictionary:
	return {
		"ally_heroes_near": count_ally_heroes_near(AiConfig.SIGHT_HERO),
		"enemy_heroes_near": count_enemy_heroes_near(AiConfig.SIGHT_HERO),
		"nearest_enemy_hero": find_nearest_enemy_hero(AiConfig.ENGAGE_RANGE),
		"nearest_enemy_minion": find_nearest_enemy_minion(AiConfig.PUSH_TARGET_RANGE),
		"nearest_enemy_turret": find_nearest_enemy_turret(AiConfig.PUSH_TARGET_RANGE),
		"nearest_friendly_turret": find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR),
		"nearest_jungle": find_nearest_jungle(),
		"nearest_health_pack": find_nearest_health_pack(),
		"ally_minions_near_turret": 0,  # 按需计算
	}


# ==================== 内部辅助 ====================

func _enemy_team() -> int:
	return Config.Team.ENEMY if hero.team == Config.Team.PLAYER else Config.Team.PLAYER


# 缓存里可能留着上一帧就已被 free 的实体（free 只从组里移除，不会清静态数组），
# 所以参数必须无类型接收 Variant 并先判 is_instance_valid，直接给 Node 形参会抛 Invalid type。
static func _is_valid(entity) -> bool:
	return is_instance_valid(entity) and entity is GameEntity and (entity as GameEntity).health > 0


static func _is_collidable(entity: Node) -> bool:
	return (entity as GameEntity).collision_layer != 0


static func _is_visible_hero(entity: Node) -> bool:
	var h := entity as Hero
	if not h:
		return false
	if h.is_dead:
		return false
	if h.is_untargetable_by_enemies():
		return false
	return true


static func _matches_type(entity: Node, types: Array) -> bool:
	for t in types:
		if is_instance_of(entity, t):
			return true
	return false

# --- 弹道威胁检测 ---
func find_threatening_projectiles(radius: float, margin: float) -> Array:
	var threats: Array = []
	var tree := hero.get_tree()
	if not tree:
		return threats
	var hero_pos_2d := Vector2(hero.global_position.x, hero.global_position.z)
	var hero_r := hero.body_radius + margin
	for proj in tree.get_nodes_in_group("projectiles"):
		if not is_instance_valid(proj) or not (proj is Bullet):
			continue
		var b := proj as Bullet
		if b.team == hero.team or b.team == Config.Team.NEUTRAL:
			continue
		var bpos := Vector2(b.global_position.x, b.global_position.z)
		# 距离太远跳过
		if hero_pos_2d.distance_to(bpos) > radius:
			continue
		# 追踪弹无法躲避，跳过
		if b.target == hero:
			continue
		# 线性弹道：检测轨迹是否会擦过英雄
		if b.linear_dir != Vector3.ZERO:
			var ldir := Vector2(b.linear_dir.x, b.linear_dir.z)
			if ldir.length() < 0.01:
				continue
			ldir = ldir.normalized()
			# 点到射线的最近距离
			var to_hero := hero_pos_2d - bpos
			var t := to_hero.dot(ldir)
			# 弹道已经飞过英雄位置 → 不构成威胁
			var remaining := b.max_distance - b.traveled
			if t < -hero_r or t > remaining + hero_r:
				continue
			var closest = bpos + ldir * clamp(t, 0.0, remaining)
			var min_dist := hero_pos_2d.distance_to(closest)
			if min_dist < hero_r:
				# 威胁方向 = 从弹道最近点指向英雄（用于计算躲避方向）
				var threat_dir = closest.direction_to(hero_pos_2d) if min_dist > 0.01 else -ldir
				threats.append({"bullet": b, "threat_dir": threat_dir, "dist": hero_pos_2d.distance_to(bpos), "closest_dist": min_dist})
		# 定点弹（goal模式）：落点附近有AoE伤害
		elif b.goal != Vector3.ZERO:
			var goal_2d := Vector2(b.goal.x, b.goal.z)
			var goal_dist := hero_pos_2d.distance_to(goal_2d)
			var danger_r := b.damage_range if b.damage_range > 0 else hero_r
			if danger_r <= 0:
				danger_r = hero_r
			if goal_dist < danger_r:
				threats.append({"bullet": b, "threat_dir": goal_2d.direction_to(hero_pos_2d), "dist": goal_dist})
	# 按距离排序，最近的威胁优先
	threats.sort_custom(func(a, b): return a["dist"] < b["dist"])
	return threats
