class_name RecallBehavior
extends AiBehavior

var recall_timer: float = 0.0


func enter() -> void:
	recall_timer = 0.0


func execute(delta: float) -> void:
	# 寻找安全回城点
	var safe_pos = _find_safe_recall_spot()
	if safe_pos != Vector3.ZERO:
		if hero.global_position.distance_to(safe_pos) > 1.0:
			hero.move_target = safe_pos
		else:
			if not hero.is_recalling:
				hero.start_recall()
	else:
		# 无安全点→HeroAI负责切到防御
		return

	# 被攻击中断
	if hero.is_recalling and hero.last_attacker and hero.last_attacker is Hero and hero.last_attacker.team != hero.team:
		hero.cancel_recall()


func _find_safe_recall_spot() -> Vector3:
	var turret = perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR)
	if turret and is_instance_valid(turret):
		var dir = (hero.global_position - turret.global_position).normalized()
		return turret.global_position + dir * 2
	return perception.find_nearest_bush(AiConfig.FRIENDLY_TURRET_FAR)
