class_name DecisionContext
extends RefCounted

# ==================== 自身状态 (归一化 0~1) ====================
var hp_ratio: float = 1.0
var mp_ratio: float = 1.0
var ult_cd_ratio: float = 0.0           # 大招剩余CD / 大招总CD
var is_under_tower: bool = false
var has_summoner: bool = true

# ==================== 敌方视野 ====================
var visible_enemy_count: int = 0         # 15m内可见敌人数
var nearest_enemy_dist: float = 9999.0   # 最近敌方英雄距离
var nearest_enemy_threat: float = 0.0    # 威胁度 (1 - dist/15), 越近越高
var enemy_power_visible: float = 0.0     # 可见敌方总战力估算

# ==================== 友方状态 ====================
var ally_nearby_count: int = 0           # 15m内队友数
var ally_alive_count: int = 5            # 全队存活数
var ally_avg_distance: float = 0.0       # 队友与我的平均距离
var team_power_ratio: float = 1.0        # 我方战力/敌方战力 (>1优势)

# ==================== 地图资源 ====================
var lane_pressure: Array = [0.0, 0.0, 0.0]  # 3条兵线压力 (0=安全, 1=危急)
var nearest_wave_dist: float = 9999.0    # 最近敌方兵线距离
var dragon_soon: bool = false            # 龙 <60s 刷新
var tyrant_soon: bool = false
var dragon_alive: bool = true
var tyrant_alive: bool = true
var nearest_jungle_dist: float = 9999.0  # 最近野怪距离

# ==================== 塔状态 ====================
var tower_diff: int = 0                  # 我方存活塔 - 敌方存活塔
var nearest_enemy_tower_dist: float = 9999.0
var nearest_friendly_tower_dist: float = 9999.0
var enemy_tower_under_attack: bool = false  # 附近敌方塔下有我方兵线

# ==================== 经济 ====================
var gold_ratio: float = 1.0              # 我方总金/敌方总金
var gold_diff_ratio: float = 0.0         # (我方-敌方)/敌方
var level_avg_ally: float = 1.0
var level_avg_enemy: float = 1.0
var level_advantage: float = 0.0         # 我方均级-敌方均级

# ==================== 特殊标记 ====================
var kill_streak: int = 0                 # 连续击杀
var death_streak: int = 0                # 连续死亡
var is_core_carry: bool = false          # 是否是核心输出位(射手/法师)


# 构建完整上下文快照
static func build(hero: Hero, perception: AiPerception, bm: BattleManager) -> DecisionContext:
	var ctx := DecisionContext.new()

	# --- 自身 ---
	ctx.hp_ratio = clampf(hero.health / maxf(hero.actual_max_health, 1.0), 0.0, 1.0)
	ctx.mp_ratio = clampf(hero.mana / maxf(hero.actual_mana_max, 1.0), 0.0, 1.0) if hero.actual_mana_max > 0 else 1.0
	if hero.skills.size() > 2 and hero.skill_cooldowns.size() > 2:
		var ult := hero.skills[2] as Skill
		var ult_cd := hero.skill_cooldowns[2] as float
		ctx.ult_cd_ratio = clampf(ult_cd / maxf(ult.cooldown, 0.1), 0.0, 1.0)
	ctx.is_under_tower = hero.under_tower_attack
	ctx.has_summoner = hero.summoner_skill != null and hero.summoner_cooldown <= 0

	# --- 敌方 ---
	ctx.visible_enemy_count = perception.count_enemy_heroes_near(AiConfig.SIGHT_HERO)
	var nearest_enemy := perception.find_nearest_enemy_hero(AiConfig.SIGHT_HERO)
	if nearest_enemy:
		ctx.nearest_enemy_dist = hero.global_position.distance_to(nearest_enemy.global_position)
		ctx.nearest_enemy_threat = clampf(1.0 - ctx.nearest_enemy_dist / AiConfig.SIGHT_HERO, 0.0, 1.0)

	# --- 友方 ---
	ctx.ally_nearby_count = perception.count_ally_heroes_near(AiConfig.SIGHT_HERO)
	ctx.ally_alive_count = ctx.ally_nearby_count + 1  # +1 = 自己
	# 战力比简化: (附近己方+1)/(附近敌方+1)
	ctx.team_power_ratio = float(ctx.ally_alive_count) / maxf(float(ctx.visible_enemy_count + 1), 1.0)

	# --- 地图 ---
	ctx.lane_pressure = _calc_lane_pressure(hero, perception)
	ctx.nearest_wave_dist = _calc_nearest_wave_dist(hero, perception)
	ctx.nearest_jungle_dist = _calc_nearest_jungle_dist(hero, perception)
	if bm:
		ctx.dragon_soon = _is_epic_soon(bm.game_time, 240.0, 180.0)
		ctx.tyrant_soon = _is_epic_soon(bm.game_time, 240.0, 180.0)

	# --- 塔 ---
	var friendly_turret := perception.find_nearest_friendly_turret(AiConfig.SIGHT_TURRET)
	var enemy_turret := perception.find_nearest_enemy_turret(AiConfig.SIGHT_TURRET)
	ctx.nearest_friendly_tower_dist = hero.global_position.distance_to(friendly_turret.global_position) if friendly_turret else 9999.0
	ctx.nearest_enemy_tower_dist = hero.global_position.distance_to(enemy_turret.global_position) if enemy_turret else 9999.0
	if enemy_turret:
		ctx.enemy_tower_under_attack = perception.count_ally_minions_near(enemy_turret.global_position, AiConfig.TOWER_MINION_CHECK) > 0

	# --- 经济 ---
	if bm:
		ctx.gold_ratio = float(bm.team_player_gold) / maxf(float(bm.team_enemy_gold), 1.0)
		ctx.gold_diff_ratio = float(bm.team_player_gold - bm.team_enemy_gold) / maxf(float(bm.team_enemy_gold), 1.0)
		ctx.level_advantage = 0.0  # 需要队伍等级数据, 暂时占位

	# --- 特殊 ---
	ctx.kill_streak = hero.consecutive_kills if hero.get("consecutive_kills") != null else 0
	ctx.death_streak = hero.continuous_deaths
	ctx.is_core_carry = hero.role in ["射手", "法师"]

	return ctx


# ==================== 内部计算 ====================

static func _calc_lane_pressure(hero: Hero, perception: AiPerception) -> Array:
	# 简化: 对每条兵线计算 (附近敌方小兵数)/(附近己方小兵数+1) 作为压力值 0~1
	var pressure := [0.0, 0.0, 0.0]
	for lane_idx in range(3):
		var enemy_count := 0
		var ally_count := 0
		var tree := hero.get_tree()
		if not tree:
			continue
		for entity in tree.get_nodes_in_group("minions"):
			if not (entity is Minion) or entity.health <= 0:
				continue
			if entity.line != lane_idx:
				continue
			if entity.team == hero.team:
				ally_count += 1
			else:
				enemy_count += 1
		if ally_count + enemy_count > 0:
			pressure[lane_idx] = clampf(float(enemy_count) / float(ally_count + enemy_count), 0.0, 1.0)
	return pressure


static func _calc_nearest_wave_dist(hero: Hero, perception: AiPerception) -> float:
	var minion := perception.find_nearest_enemy_minion(AiConfig.SIGHT_MINION)
	if minion:
		return hero.global_position.distance_to(minion.global_position)
	return 9999.0


static func _calc_nearest_jungle_dist(hero: Hero, perception: AiPerception) -> float:
	var monster := perception.find_nearest_jungle()
	if monster:
		return hero.global_position.distance_to(monster.global_position)
	return 9999.0


static func _is_epic_soon(game_time: float, first_spawn: float, interval: float) -> bool:
	var since_first := game_time - first_spawn
	if since_first < 0:
		return false
	var next_spawn = first_spawn + ceil(since_first / interval) * interval
	return (next_spawn - game_time) < 60.0 and (next_spawn - game_time) > 0.0


static func maxf(a: float, b: float) -> float:
	return a if a > b else b


static func clampf(val: float, lo: float, hi: float) -> float:
	return lo if val < lo else (hi if val > hi else val)
