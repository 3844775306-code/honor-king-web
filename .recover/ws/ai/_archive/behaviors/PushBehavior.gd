class_name PushBehavior
extends AiBehavior

var lane: int


func enter() -> void:
	pass


func execute(_delta: float) -> void:
	var target: GameEntity = null

	# 优先级: 敌方英雄 > 敌方小兵 > 敌方塔（有己方兵线时）
	var enemy_hero = perception.find_nearest_enemy_hero(AiConfig.PUSH_TARGET_RANGE)
	if enemy_hero:
		target = enemy_hero
	else:
		var enemy_minion = perception.find_nearest_enemy_minion(AiConfig.PUSH_TARGET_RANGE)
		if enemy_minion:
			target = enemy_minion
		else:
			var ally_minions = perception.count_ally_minions_near(hero.global_position, AiConfig.ALLY_MINION_RANGE)
			if ally_minions > 0:
				var enemy_turret = perception.find_nearest_enemy_turret(AiConfig.PUSH_TARGET_RANGE)
				if enemy_turret:
					target = enemy_turret

	if target:
		hero.set_manual_target(target)
		tactics.use_random_skill(target)
		var dist = hero.global_position.distance_to(target.global_position)
		if dist > hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR:
			hero.move_target = target.global_position
	elif lane < 3:
		var ally_minion = perception.find_nearest_ally_minion_on_lane(lane)
		if ally_minion:
			hero.move_target = ally_minion.global_position

	# 塔下无兵→信号转打野
	if target is Turret and target.team != hero.team:
		var minions_near = perception.count_enemy_minions_near(target.global_position, AiConfig.TOWER_MINION_CHECK)
		if minions_near == 0:
			_signal_switch_to_jungle()


func _signal_switch_to_jungle() -> void:
	# 由 HeroAI 检查返回值处理
	pass
