class_name LanlingBrain
extends HeroBrain


func process_special_actions(state: int) -> void:
	# 4技能隐身: 附近有敌人且推进状态时使用
	if hero.skill_cooldowns.size() <= 3:
		return
	if hero.skill_cooldowns[3] > 0:
		return
	if perception.find_nearest_enemy_hero(AiConfig.LANLING_STEALTH_RANGE) and state == HeroAI.State.PUSH:
		tactics.force_cast(3, hero.global_position)


# 兰陵王偏好: 隐身状态下提高突进技能优先级
func modify_skill_score(skill_index: int, base_score: float) -> float:
	if hero.lanling_stealth_active and skill_index == 0:
		return base_score + 1.5  # 隐身时Q技能破隐一击
	return base_score


# 兰陵王连招
func get_combos(target: GameEntity) -> Array:
	var dist := hero.global_position.distance_to(target.global_position)
	var combos: Array = []

	# 连招1: 4(隐身)→Q(破隐)→W→E — 完美暗杀
	if hero.lanling_stealth_active or hero.skill_cooldowns[3] <= 0:
		combos.append({
			"name": "stealth_assassinate",
			"skills": [3, 0, 1, 2],
			"priority": 0.95,
		})

	# 连招2: Q→W→E — 非隐身交火
	combos.append({
		"name": "direct_engage",
		"skills": [0, 1, 2],
		"priority": 0.7,
	})

	# 连招3: 4→2→1→0 — 大招起手（敌方残血收割）
	if dist < AiConfig.ENGAGE_RANGE and target.health < target.actual_max_health * 0.4:
		combos.append({
			"name": "ult_execute",
			"skills": [3, 2, 1, 0],
			"priority": 0.85,
		})

	return combos
