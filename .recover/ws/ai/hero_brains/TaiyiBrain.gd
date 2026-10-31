class_name TaiyiBrain
extends HeroBrain


func process_skill_windows() -> void:
	for si in range(min(3, hero.skill_window_timers.size())):
		if hero.skill_window_timers[si] <= 0:
			continue
		# Q窗口: 快结束时引爆
		if si == 0 and hero.skill_window_timers[si] < AiConfig.TAIYI_Q_EXPLODE_WINDOW:
			hero._taiyi_q_explode()


# 太乙偏好: Q技能优先使用（核心机制）
func modify_skill_score(skill_index: int, base_score: float) -> float:
	if skill_index == 0:
		return base_score + 1.0
	return base_score


# 太乙真人连招
func get_combos(target: GameEntity) -> Array:
	var dist := hero.global_position.distance_to(target.global_position)
	var combos: Array = []

	# 连招1: Q(贴炸弹)→W(晕眩)→引爆 — 核心控制链
	combos.append({
		"name": "bomb_stun",
		"skills": [0, 1],
		"priority": 0.85,
	})

	# 连招2: W(先手晕)→Q(贴炸弹) — 确保命中
	if dist < AiConfig.MELEE_RANGE:
		combos.append({
			"name": "stun_bomb",
			"skills": [1, 0],
			"priority": 0.75,
		})

	# 连招3: E(大招复活)→Q→W — 保护队友时
	combos.append({
		"name": "save_ult",
		"skills": [2, 0, 1],
		"priority": 0.9 if hero.health < hero.actual_max_health * 0.3 else 0.2,
	})

	return combos
