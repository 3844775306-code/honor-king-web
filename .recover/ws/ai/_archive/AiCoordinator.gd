class_name AiCoordinator
extends RefCounted

# @deprecated 团队协调器（未使用）
# 当前 AI 系统使用 TeamTactics + LaneStrategy + JungleStrategy 进行团队协调，
# AiCoordinator 是早期原型，HeroAI 中未实例化或调用。
# 保留此文件供参考，如需团队级协调请使用 TeamTactics。

enum Strategy { BALANCED, AGGRESSIVE, DEFENSIVE, GROUP_UP }

var strategy: int = Strategy.BALANCED
var game_time: float = 0.0

# 每条路分配人数: { "farm": N, "mid": N, "clash": N, "jungle": N }
var lane_assignments: Dictionary = {}
# 已分配英雄记录: { hero -> lane }
var hero_lanes: Dictionary = {}


# 每30秒重新评估团队策略
func evaluate_strategy(battle_manager: BattleManager) -> int:
	game_time = battle_manager.game_time

	var gold_gap := battle_manager.team_enemy_gold - battle_manager.team_player_gold
	var kill_gap := battle_manager.team_enemy_kills - battle_manager.team_player_kills

	# 史诗怪物刷新前60秒 → 抱团
	if _epic_monster_soon(game_time):
		strategy = Strategy.GROUP_UP
	elif gold_gap > 5000 or kill_gap > 5:
		strategy = Strategy.DEFENSIVE
	elif gold_gap < -3000 or kill_gap < -3:
		strategy = Strategy.AGGRESSIVE
	else:
		strategy = Strategy.BALANCED

	return strategy


# 根据团队策略决定5人分路
func assign_lanes(heroes: Array[Hero]) -> Dictionary:
	var result := {}
	var lanes_pool := {
		AiConfig.Lane.FARM: 1,      # 发育路默认1人
		AiConfig.Lane.MID: 1,      # 中路默认1人
		AiConfig.Lane.CLASH: 2,      # 对抗路默认2人(射手+辅助)
		AiConfig.Lane.JUNGLE: 1,   # 野区默认1人
	}

	match strategy:
		Strategy.GROUP_UP:
			lanes_pool = {AiConfig.Lane.MID: 4, AiConfig.Lane.JUNGLE: 1}  # 中路集结4人
		Strategy.DEFENSIVE:
			lanes_pool = {AiConfig.Lane.FARM: 1, AiConfig.Lane.MID: 1, AiConfig.Lane.CLASH: 1, AiConfig.Lane.JUNGLE: 2}  # 多守野区
		Strategy.AGGRESSIVE:
			lanes_pool = {AiConfig.Lane.FARM: 1, AiConfig.Lane.MID: 2, AiConfig.Lane.CLASH: 1, AiConfig.Lane.JUNGLE: 1}  # 中野联动

	# 按角色分配
	var assigned := {}
	for hero in heroes:
		var preferred = _preferred_lane(hero)
		if assigned.get(preferred, 0) < lanes_pool.get(preferred, 1):
			result[hero] = preferred
			assigned[preferred] = assigned.get(preferred, 0) + 1
		else:
			# 该路已满 → 分配到人数不足的路
			for ln in [AiConfig.Lane.MID, AiConfig.Lane.CLASH, AiConfig.Lane.FARM, AiConfig.Lane.JUNGLE]:
				if assigned.get(ln, 0) < lanes_pool.get(ln, 1):
					result[hero] = ln
					assigned[ln] = assigned.get(ln, 0) + 1
					break

	hero_lanes = result
	lane_assignments = assigned
	return result


# 判断某个英雄是否应该去抱团
func should_group(hero: Hero) -> bool:
	if strategy != Strategy.GROUP_UP:
		return false
	# 核心输出位必须去
	if hero.role in ["射手", "法师", "刺客"]:
		return true
	# 辅助跟随射手
	if hero.role == "辅助" or hero.role == "坦克":
		return true
	return false


# 撤退信号：是否该英雄应该撤退
func should_retreat(hero: Hero, perception: AiPerception) -> bool:
	# 团队防守策略 + 人数劣势
	if strategy == Strategy.DEFENSIVE:
		var enemies = perception.count_enemy_heroes_near(AiConfig.SIGHT_HERO)
		var allies = perception.count_ally_heroes_near(AiConfig.SIGHT_HERO)
		if enemies > allies:
			return true
	return false


# 获取某英雄在团队中的分路
func get_lane_for(hero: Hero) -> int:
	return hero_lanes.get(hero, AiConfig.Lane.MID)


# ==================== 内部 ====================

func _preferred_lane(hero: Hero) -> int:
	var is_blue := hero.team == Config.Team.PLAYER
	match hero.role:
		"射手": return AiConfig.Lane.FARM
		"法师": return AiConfig.Lane.MID
		"刺客": return AiConfig.Lane.JUNGLE
		"战士": return AiConfig.Lane.CLASH
		"坦克": return AiConfig.Lane.CLASH
		"辅助": return AiConfig.Lane.FARM
	return AiConfig.Lane.MID


func _epic_monster_soon(time: float) -> bool:
	# 暴君/龙王在游戏时间4分钟首次刷新，之后每3分钟
	var since_first := time - 240.0  # 4分钟 = 240秒
	if since_first < 0:
		return false
	var next_spawn = 240.0 + ceil(since_first / 180.0) * 180.0
	return (next_spawn - time) < 60.0 and (next_spawn - time) > 0.0
