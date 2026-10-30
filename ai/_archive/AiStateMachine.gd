class_name AiStateMachine
extends RefCounted

enum State { PUSH, FARM, RETREAT, RECALL, DEFEND, AVOID, RECALL_SAFE }

var current: int = State.PUSH
var previous: int = State.PUSH
var hero: Hero
var perception: AiPerception
var lane: int
var jungle_kill_count: int

# 状态持续时间追踪
var state_elapsed: float = 0.0


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception


# 评估所有转换条件，返回应切换到的状态（或保持当前）
# 优先级: P0 > P1 > P4(最终裁定) > P3(默认) > P2(软建议)
func evaluate(p_lane: int, p_jungle_kill_count: int, delta: float) -> int:
	lane = p_lane
	jungle_kill_count = p_jungle_kill_count
	state_elapsed += delta

	var next_state := current

	# P0: 塔攻击 → 立即防御（最高优先级，硬中断）
	if hero.under_tower_attack:
		return State.DEFEND

	# P1: 极危血量 → 安全回城（硬中断）
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_RECALL:
		return State.RECALL_SAFE

	# P2: 人数劣势 → 防御（软建议，会被P3覆盖）
	var ally_count = perception.count_ally_heroes_near(AiConfig.SIGHT_HERO)
	var enemy_count = perception.count_enemy_heroes_near(AiConfig.SIGHT_HERO)
	if ally_count < enemy_count:
		next_state = State.DEFEND

	# P3: 基础状态 — 健康时覆盖P2的DEFEND，回到正常分路行为
	if hero.health >= hero.actual_max_health * AiConfig.HEALTH_RECALL:
		if lane == AiConfig.Lane.JUNGLE:
			next_state = State.FARM
		else:
			next_state = State.PUSH

	# P4: 经济落后核心位 → 防御（最终裁定，可覆盖P3的PUSH/FARM）
	var bm = hero.get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm:
		var gap = bm.team_enemy_gold - bm.team_player_gold
		if gap > AiConfig.GOLD_GAP_DEFEND and hero.role in ["射手", "法师"]:
			next_state = State.DEFEND

	return next_state


# 执行状态转换
func transition(to: int) -> void:
	if to == current:
		return
	previous = current
	current = to
	state_elapsed = 0.0


# 当前状态名（调试用）
func current_name() -> String:
	match current:
		State.PUSH: return "PUSH"
		State.FARM: return "FARM"
		State.RETREAT: return "RETREAT"
		State.RECALL: return "RECALL"
		State.DEFEND: return "DEFEND"
		State.AVOID: return "AVOID"
		State.RECALL_SAFE: return "RECALL_SAFE"
	return "UNKNOWN"
