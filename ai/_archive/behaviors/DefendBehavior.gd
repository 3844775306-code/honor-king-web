class_name DefendBehavior
extends AiBehavior


func enter() -> void:
	pass


func execute(_delta: float) -> void:
	if perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_CLOSE):
		var enemy = perception.find_nearest_enemy_hero(AiConfig.MELEE_RANGE)
		if enemy:
			hero.set_manual_target(enemy)
			tactics.use_random_skill(enemy)
	else:
		var turret = perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR)
		if not turret:
			return  # HeroAI 负责切换到 RECALL_SAFE
		hero.set_manual_target(turret)
