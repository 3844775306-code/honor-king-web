class_name FarmBehavior
extends AiBehavior


func enter() -> void:
	pass


func execute(_delta: float) -> void:
	var enemy_hero = perception.find_nearest_enemy_hero(AiConfig.PUSH_TARGET_RANGE)
	if enemy_hero is Hero:
		hero.set_manual_target(enemy_hero)
		tactics.use_random_skill(enemy_hero)
		var dist = hero.global_position.distance_to(enemy_hero.global_position)
		if dist > hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR:
			hero.move_target = enemy_hero.global_position
	else:
		var monster = perception.find_nearest_jungle()
		if monster and is_instance_valid(monster):
			var dist = hero.global_position.distance_to(monster.global_position)
			if dist > AiConfig.MONSTER_MOVE_RANGE:
				hero.move_target = monster.global_position
			elif dist <= hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR:
				hero.set_manual_target(monster)
				tactics.use_random_skill(monster)
			else:
				hero.move_target = monster.global_position
		# 无野可打→HeroAI负责重置分路
