class_name LibaiBrain
extends HeroBrain


func process_skill_windows() -> void:
	for si in range(min(3, hero.skill_window_timers.size())):
		if hero.skill_window_timers[si] <= 0 or hero.skill_window_timers[si] >= AiConfig.SKILL_WINDOW_THRESHOLD:
			continue
		# Q窗口: 接近敌人时触发二段；第三段会回原点，不主动交
		if si == 0 and (hero.skill_uses.size() == 0 or int(hero.skill_uses[0]) < 2) \
				and perception.find_nearest_enemy_hero(AiConfig.MELEE_RANGE):
			tactics.force_cast(si, hero.global_position)


# 李白偏好: W技能（不可选中）在危险时优先
func modify_skill_score(skill_index: int, base_score: float) -> float:
	if skill_index == 1 and hero.health < hero.actual_max_health * AiConfig.HEALTH_DEFEND:
		return base_score + 2.0  # 危险时大幅提升W优先级
	return base_score


# 李白连招
func get_combos(target: GameEntity) -> Array:
	var dist := hero.global_position.distance_to(target.global_position)
	var combos: Array = []

	# 连招1: W(不可选中)→Q1→E(大招) — 反打/切入
	combos.append({
		"name": "shadow_dance",
		"skills": [1, 0, 2],
		"priority": 0.9 if hero.health < hero.actual_max_health * 0.5 else 0.5,
	})

	# 连招2: Q1→Q2→W — 近身消耗
	if dist < AiConfig.ENGAGE_RANGE:
		combos.append({
			"name": "poke_close",
			"skills": [0, 1],
			"priority": 0.7,
		})

	# 连招3: 2→1→0 — 大招起手（敌人聚集时）
	combos.append({
		"name": "ult_initiate",
		"skills": [2, 1, 0],
		"priority": 0.6,
	})

	return combos
