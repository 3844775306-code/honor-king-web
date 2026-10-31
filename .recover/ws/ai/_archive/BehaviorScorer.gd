class_name BehaviorScorer
extends RefCounted

# 基于 DecisionContext 的评分式行为选择系统
# 公式: total = survival_coef × reward_coef × urgency_coef + random_jitter(±5%)
# 中断: new_score > current_score + 0.15 → abort and switch

enum Action {
	HOME,           # 回城补给
	CLEAR_WAVE,     # 清兵线
	FARM_JUNGLE,    # 刷野
	TAKE_DRAGON,    # 开龙
	PUSH_TOWER,     # 推塔
	GROUP_UP,       # 抱团
	AMBUSH,         # 蹲草伏击
	CHASE,          # 追击残血
	RETREAT,        # 后撤
	FARM_LANE,      # 线上发育
}

# 当前执行中的行为 + 分数
var current_action: int = Action.FARM_LANE
var current_score: float = 0.0
var action_elapsed: float = 0.0

# 中断阈值
const INTERRUPT_THRESHOLD: float = 0.15

# 冷却: 频繁切换行为的惩罚
var action_cooldowns: Dictionary = {}


# 主入口: 返回最高分行为
func evaluate(ctx: DecisionContext, delta: float) -> int:
	action_elapsed += delta

	# 冷却衰减: 刚切换的行为有短暂CD
	for act in action_cooldowns.keys():
		action_cooldowns[act] = maxf(0.0, action_cooldowns[act] - delta)

	var candidates := _score_all(ctx)
	var best_action := Action.FARM_LANE
	var best_score := -999.0

	for act in candidates:
		var score = candidates[act]
		# 冷却惩罚
		if action_cooldowns.get(act, 0.0) > 0:
			score -= 0.15
		if score > best_score:
			best_score = score
			best_action = act

	# 中断检测
	if best_action != current_action:
		if best_score > current_score + INTERRUPT_THRESHOLD:
			_switch_to(best_action, best_score)
		# 否则维持当前行为（避免抖动）
	else:
		current_score = best_score  # 同行为刷新分数

	return current_action


# 强制切换（外部信号: 塔攻击、龙刷新等）
func force_switch(action: int, ctx: DecisionContext) -> void:
	var score := _score_single(action, ctx)
	_switch_to(action, score)


func get_action_name(act: int) -> String:
	match act:
		Action.HOME: return "HOME"
		Action.CLEAR_WAVE: return "CLEAR_WAVE"
		Action.FARM_JUNGLE: return "FARM_JUNGLE"
		Action.TAKE_DRAGON: return "TAKE_DRAGON"
		Action.PUSH_TOWER: return "PUSH_TOWER"
		Action.GROUP_UP: return "GROUP_UP"
		Action.AMBUSH: return "AMBUSH"
		Action.CHASE: return "CHASE"
		Action.RETREAT: return "RETREAT"
		Action.FARM_LANE: return "FARM_LANE"
	return "UNKNOWN"


# ==================== 评分核心 ====================

func _score_all(ctx: DecisionContext) -> Dictionary:
	var scores := {}
	for act in range(10):
		scores[act] = _score_single(act, ctx)
	return scores


func _score_single(act: int, ctx: DecisionContext) -> float:
	var survival := _calc_survival(act, ctx)
	var reward := _calc_reward(act, ctx)
	var urgency := _calc_urgency(act, ctx)
	var jitter := (randf() - 0.5) * 2.0 * AiConfig.score_jitter()
	return survival * reward * urgency + jitter


# ==================== survival_coef (0~1) ====================
# "执行这个行为有多安全？"

func _calc_survival(act: int, ctx: DecisionContext) -> float:
	match act:
		Action.HOME:
			# 回城: 血越少、附近有塔越安全
			var safety := clampf(1.0 - ctx.hp_ratio + 0.3, 0.0, 1.0)
			if ctx.nearest_friendly_tower_dist < 5.0:
				safety = minf(safety + 0.2, 1.0)
			return safety

		Action.CLEAR_WAVE:
			# 清线: 塔附近安全，深入危险
			var base := 0.7
			base -= ctx.nearest_enemy_threat * 0.4
			if ctx.nearest_friendly_tower_dist < 8.0:
				base += 0.2
			return clampf(base, 0.1, 1.0)

		Action.FARM_JUNGLE:
			# 刷野: 取决于敌方视野
			var s := 0.8
			s -= ctx.visible_enemy_count * 0.1
			if ctx.nearest_enemy_threat > 0.5:
				s -= 0.3
			return clampf(s, 0.1, 1.0)

		Action.TAKE_DRAGON:
			# 开龙: 高风险，需要人数优势
			if ctx.team_power_ratio < 1.2:
				return 0.1
			if ctx.nearest_enemy_dist < 8.0:
				return 0.2
			return clampf(ctx.team_power_ratio * 0.5, 0.1, 0.9)

		Action.PUSH_TOWER:
			# 推塔: 有兵线时安全
			var s2 := 0.5 + ctx.team_power_ratio * 0.2
			if ctx.enemy_tower_under_attack:
				s2 += 0.2
			if ctx.visible_enemy_count >= 3:
				s2 -= 0.3
			return clampf(s2, 0.1, 1.0)

		Action.GROUP_UP:
			# 抱团: 越安全 → 越容易选择抱团
			return clampf(0.5 + ctx.ally_nearby_count * 0.1, 0.2, 1.0)

		Action.AMBUSH:
			# 蹲草: 需要低可见度 + 人数不劣势
			if ctx.visible_enemy_count == 0:
				return 0.6
			if ctx.team_power_ratio >= 1.0 and ctx.nearest_enemy_dist < 10.0:
				return 0.5
			return 0.15

		Action.CHASE:
			# 追击: 敌方残血 + 我方人数优势
			if ctx.nearest_enemy_threat < 0.3 and ctx.team_power_ratio >= 1.5:
				return 0.7
			if ctx.team_power_ratio >= 1.2:
				return 0.4
			return 0.1

		Action.RETREAT:
			# 后撤: 低HP或人数劣势时更安全（做这个行为更合理）
			var r := (1.0 - ctx.hp_ratio) * 0.6
			if ctx.visible_enemy_count > ctx.ally_nearby_count + 1:
				r += 0.3
			return clampf(r, 0.2, 0.9)

		Action.FARM_LANE:
			# 线上发育: 默认安全
			var s3 := 0.7
			s3 -= ctx.nearest_enemy_threat * 0.3
			if ctx.nearest_friendly_tower_dist < 10.0:
				s3 += 0.15
			return clampf(s3, 0.2, 0.9)

	return 0.5


# ==================== reward_coef (0~1) ====================
# "做完这个行为能获得多少收益？"

func _calc_reward(act: int, ctx: DecisionContext) -> float:
	match act:
		Action.HOME:
			# 回城: 血越少收益越高（恢复量）
			return clampf(1.0 - ctx.hp_ratio + 0.1, 0.0, 1.0)

		Action.CLEAR_WAVE:
			# 清线: 附近有兵线 = 有金币
			if ctx.nearest_wave_dist < 8.0:
				return 0.8
			if ctx.nearest_wave_dist < 15.0:
				return 0.5
			return 0.1

		Action.FARM_JUNGLE:
			# 刷野: 附近有野怪 = 有收益
			if ctx.nearest_jungle_dist < 5.0:
				return 0.85
			if ctx.nearest_jungle_dist < 12.0:
				return 0.5
			return 0.1

		Action.TAKE_DRAGON:
			# 开龙: 龙存活时才有效益
			if not ctx.dragon_alive and not ctx.tyrant_alive:
				return 0.0
			if ctx.dragon_soon or ctx.tyrant_soon:
				return 0.9
			return 0.6

		Action.PUSH_TOWER:
			# 推塔: 兵线压在敌方塔下 = 可以推
			if ctx.enemy_tower_under_attack:
				return 0.9
			if ctx.nearest_enemy_tower_dist < 10.0:
				return 0.5
			return 0.15

		Action.GROUP_UP:
			# 抱团: 队友越多效益越高
			return clampf(0.3 + ctx.ally_nearby_count * 0.15, 0.0, 0.9)

		Action.AMBUSH:
			# 蹲草: 有敌人接近时收益高
			if ctx.nearest_enemy_dist < 6.0:
				return 0.8
			if ctx.nearest_enemy_dist < 12.0:
				return 0.4
			return 0.05

		Action.CHASE:
			# 追击: 击杀 = 300g + 经验
			if ctx.nearest_enemy_threat > 0.5:
				return 0.7
			return 0.3

		Action.RETREAT:
			# 后撤: 不死 = 不给对面送钱
			if ctx.hp_ratio < 0.3:
				return 0.9
			if ctx.visible_enemy_count > ctx.ally_nearby_count:
				return 0.6
			return 0.1

		Action.FARM_LANE:
			# 线上发育: 中规中矩
			if ctx.nearest_wave_dist < 10.0:
				return 0.6
			return 0.3

	return 0.3


# ==================== urgency_coef (0~1) ====================
# "现在非做不可吗？"

func _calc_urgency(act: int, ctx: DecisionContext) -> float:
	match act:
		Action.HOME:
			# 血量越低越紧急
			return clampf(1.0 - ctx.hp_ratio + 0.2, 0.0, 1.0)

		Action.CLEAR_WAVE:
			# 兵线压力越大越紧急
			var max_pressure := 0.0
			for p in ctx.lane_pressure:
				max_pressure = maxf(max_pressure, p)
			return clampf(max_pressure + 0.3, 0.0, 1.0)

		Action.FARM_JUNGLE:
			# 野怪近 → 顺手刷
			if ctx.nearest_jungle_dist < 5.0:
				return 0.8
			return 0.4

		Action.TAKE_DRAGON:
			# 龙快刷新时最紧急
			if ctx.dragon_soon or ctx.tyrant_soon:
				return 0.95
			return 0.5

		Action.PUSH_TOWER:
			# 敌方塔下无兵 → 不急
			if ctx.enemy_tower_under_attack:
				return 0.85
			return 0.3

		Action.GROUP_UP:
			# 龙刷新前抱团紧急
			if ctx.dragon_soon or ctx.tyrant_soon:
				return 0.9
			return 0.4

		Action.AMBUSH:
			# 敌方接近时紧急
			if ctx.nearest_enemy_dist < 8.0:
				return 0.7
			return 0.2

		Action.CHASE:
			# 敌方残血 → 抓紧
			if ctx.nearest_enemy_threat > 0.6:
				return 0.8
			return 0.3

		Action.RETREAT:
			# 生死攸关
			if ctx.hp_ratio < AiConfig.HEALTH_CRITICAL:
				return 1.0
			if ctx.hp_ratio < AiConfig.HEALTH_LOW:
				return 0.8
			return 0.3

		Action.FARM_LANE:
			# 经济落后时发育紧急
			if ctx.gold_diff_ratio < -0.2:
				return 0.7
			return 0.3

	return 0.3


# ==================== 辅助 ====================

func _switch_to(action: int, score: float) -> void:
	current_action = action
	current_score = score
	action_elapsed = 0.0
	# 设置 3 秒冷却防止来回跳
	action_cooldowns[action] = 3.0


static func clampf(val: float, lo: float, hi: float) -> float:
	return lo if val < lo else (hi if val > hi else val)


static func maxf(a: float, b: float) -> float:
	return a if a > b else b


static func minf(a: float, b: float) -> float:
	return a if a < b else b
