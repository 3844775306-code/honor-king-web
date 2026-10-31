class_name SummonerTactics
extends RefCounted

var hero: Hero
var perception: AiPerception
var state: int
var lane: int


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception


func try_use(p_state: int, p_lane: int) -> bool:
	state = p_state
	lane = p_lane

	if not hero.summoner_skill or hero.summoner_cooldown > 0:
		return false

	var sk: String = hero.summoner_skill.skill_name
	match sk:
		"治疗术": return _try_heal()
		"传送": return _try_teleport()
		"疾跑": return _try_sprint()
		"狂暴": return _try_frenzy()
		"净化": return _try_cleanse()
		"弱化": return _try_weaken()
		"终结": return _try_execute()
		"闪现": return _try_flash()
		"惩击": return _try_smite()
	return false


func _try_heal() -> bool:
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_LOW:
		hero._use_summoner()
		return true
	return false


func _try_teleport() -> bool:
	if hero.health <= hero.actual_max_health * AiConfig.HEALTH_DEFEND:
		return false
	var tp_turret = perception.find_nearest_friendly_turret(AiConfig.TP_TURRET_RANGE)
	if state == HeroAI.State.PUSH and tp_turret:
		var enemy_turret = perception.find_nearest_enemy_turret(AiConfig.ENEMY_TURRET_CHECK)
		if enemy_turret and hero.global_position.distance_to(enemy_turret.global_position) > AiConfig.TP_ENEMY_TURRET_DIST:
			hero._use_summoner()
			return true
	elif hero.health < hero.actual_max_health * AiConfig.HEALTH_DEFEND and tp_turret:
		if perception.count_enemy_heroes_near(AiConfig.ENGAGE_RANGE) >= AiConfig.FLEE_ENEMY_COUNT:
			hero._use_summoner()
			return true
	return false


func _try_sprint() -> bool:
	if state == HeroAI.State.PUSH:
		hero._use_summoner()
		return true
	return false


func _try_frenzy() -> bool:
	if perception.count_enemy_heroes_near(AiConfig.ENGAGE_RANGE) >= AiConfig.FLEE_ENEMY_COUNT:
		hero._use_summoner()
		return true
	return false


func _try_cleanse() -> bool:
	if hero.stun_timer > 0 or hero.slow_timer > AiConfig.SLOW_CLEANSE_THRESHOLD:
		hero._use_summoner()
		return true
	return false


func _try_weaken() -> bool:
	if perception.count_enemy_heroes_near(AiConfig.MELEE_RANGE) >= AiConfig.WEAKEN_ENEMY_COUNT:
		hero._use_summoner()
		return true
	return false


func _try_execute() -> bool:
	var enemy = perception.find_nearest_enemy_hero(AiConfig.MELEE_RANGE)
	if enemy and enemy.health < enemy.actual_max_health * AiConfig.HEALTH_CRITICAL:
		hero._use_summoner()
		return true
	return false


func _try_flash() -> bool:
	# 危险逃离
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_CRITICAL \
			and perception.count_enemy_heroes_near(AiConfig.RETREAT_RANGE) >= AiConfig.FLEE_ENEMY_COUNT:
		var enemy_near = perception.find_nearest_enemy_hero(AiConfig.RETREAT_RANGE)
		var away = (hero.global_position - enemy_near.global_position).normalized() if enemy_near else Vector3.FORWARD
		hero.global_position += away * AiConfig.FLASH_DISTANCE
		hero.summoner_cooldown = hero.summoner_skill.cooldown
		return true
	# 进攻闪现
	if state == HeroAI.State.PUSH \
			and perception.find_nearest_enemy_hero(AiConfig.ENGAGE_RANGE) \
			and hero.health > hero.actual_max_health * (AiConfig.HEALTH_SAFE - 0.1):
		var enemy = perception.find_nearest_enemy_hero(AiConfig.ENGAGE_RANGE)
		if enemy and hero.global_position.distance_to(enemy.global_position) > AiConfig.MELEE_RANGE:
			var toward = (enemy.global_position - hero.global_position).normalized()
			hero.global_position += toward * AiConfig.FLASH_DISTANCE
			hero.summoner_cooldown = hero.summoner_skill.cooldown
			return true
	return false


func _try_smite() -> bool:
	var monster = perception.find_nearest_jungle()
	if monster and monster.health < AiConfig.SMITE_DAMAGE_BASE + hero.level * AiConfig.SMITE_DAMAGE_PER_LEVEL:
		hero._use_summoner()
		return true
	return false
