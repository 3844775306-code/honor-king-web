class_name SummonerTactics
extends RefCounted

var hero: Hero
var perception: AiPerception
var state: int
var lane: int
var trade_planner: TradePlanner = null
var last_action := ""
var chase_target: Hero = null   # 当前 FINISH_CHASE 目标（HeroAI 注入）


func _init(p_hero: Hero, p_perception: AiPerception, p_trade: TradePlanner = null) -> void:
	hero = p_hero
	perception = p_perception
	trade_planner = p_trade


func try_use(p_state: int, p_lane: int) -> bool:
	state = p_state
	lane = p_lane

	if not hero.summoner_skill or hero.summoner_cooldown > 0:
		return false

	var sk: String = hero.summoner_skill.skill_name
	var ok := false
	match sk:
		"治疗术": ok = _try_heal()
		"传送": ok = _try_teleport()
		"疾跑": ok = _try_sprint()
		"狂暴": ok = _try_frenzy()
		"净化": ok = _try_cleanse()
		"弱化": ok = _try_weaken()
		"终结": ok = _try_execute()
		"闪现": ok = _try_flash()
		"惩击": ok = _try_smite()
	if ok:
		last_action = sk
	return ok


func _try_heal() -> bool:
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_LOW:
		hero._use_summoner()
		return true
	return false


func _try_teleport() -> bool:
	if hero.health <= hero.actual_max_health * AiConfig.HEALTH_DEFEND:
		return false
	var tp_turret = perception.find_nearest_friendly_turret(AiConfig.TP_TURRET_RANGE)
	if state == AIAction.Type.PUSH_LANE and tp_turret:
		var enemy_turret = perception.find_nearest_enemy_turret(AiConfig.ENEMY_TURRET_CHECK)
		if enemy_turret and hero.global_position.distance_to(enemy_turret.global_position) > AiConfig.TP_ENEMY_TURRET_DIST:
			hero._use_summoner()
			return true
	elif hero.health < hero.actual_max_health * AiConfig.HEALTH_DEFEND and tp_turret:
		if perception.count_enemy_heroes_near(AiConfig.ENGAGE_RANGE) >= AiConfig.FLEE_ENEMY_COUNT:
			hero._use_summoner()
			return true
	return false


## 追击残血：只允许 FINISH_CHASE 使用闪现（优先使用 HeroAI 当前追击目标，不再受 8m 交战半径限制）
func set_chase_target(t: Hero) -> void:
	chase_target = t


func _in_chase() -> bool:
	var t := _flash_chase_target()
	if t != null:
		return hero.global_position.distance_to(t.global_position) <= AiConfig.CHASE_START_RANGE
	return state == AIAction.Type.FINISH_CHASE \
		and perception.find_nearest_enemy_hero(AiConfig.CHASE_START_RANGE) != null


## 追击闪现的目标：残血追击目标，或换血中的低血目标
func _flash_chase_target() -> Hero:
	if chase_target != null and is_instance_valid(chase_target) and chase_target.health > 0.0:
		return chase_target
	if trade_planner != null:
		var t := trade_planner.active_target
		if t != null and is_instance_valid(t) and t.health > 0.0 \
				and t.health <= t.actual_max_health * 0.35:
			return t
	return null


## 闪现逃生：血量 <35% 且被近身；1v1 时要求残血/刚被攻击，2 人以上直接交
func _in_flee() -> bool:
	var ratio: float = hero.health / maxf(hero.actual_max_health, 1.0)
	if ratio >= 0.35:
		return false
	var nearest := perception.find_nearest_enemy_hero(8.0)
	if nearest == null:
		return false
	if perception.count_enemy_heroes_near(8.0) >= 2:
		return true
	if ratio < 0.20:
		return true
	# 1v1：只有刚被该敌人攻击且对方还在近处才交闪现
	var atk := hero.last_hero_attacker
	if atk == null or not is_instance_valid(atk) or atk.health <= 0.0:
		return false
	var now := Time.get_ticks_msec() * 0.001
	return now - hero.last_hero_attacker_at <= 2.0 \
		and hero.global_position.distance_to(atk.global_position) <= 8.0


## 换血窗口：TradePlanner 正在主动换血（无 planner 时用近身交战兜底）
func _in_trade() -> bool:
	if trade_planner != null:
		return trade_planner.active_target != null and is_instance_valid(trade_planner.active_target)
	return state == AIAction.Type.PUSH_LANE and perception.find_nearest_enemy_hero(AiConfig.MELEE_RANGE) != null


func _try_sprint() -> bool:
	if _in_chase() or _in_flee():
		hero._use_summoner()
		return true
	return false


func _try_frenzy() -> bool:
	if _in_trade():
		hero._use_summoner()
		return true
	return false


func _try_cleanse() -> bool:
	if hero.stun_timer > 0 or hero.slow_timer > AiConfig.SLOW_CLEANSE_THRESHOLD:
		hero._use_summoner()
		return true
	return false


func _try_weaken() -> bool:
	if _in_trade():
		hero._use_summoner()
		return true
	return false


func _try_execute() -> bool:
	var enemy = perception.find_nearest_enemy_hero(AiConfig.MELEE_RANGE)
	if enemy and enemy.health < enemy.actual_max_health * AiConfig.HEALTH_CRITICAL:
		hero._use_summoner()
		return true
	return false


## 闪现落点：允许穿墙，但落点必须可站立（被墙挡住就落到最近可站点）
func _flash_end(dir: Vector3) -> Vector3:
	var from: Vector3 = hero.global_position
	var end: Vector3 = from + dir * AiConfig.FLASH_DISTANCE
	if not PathFinder.is_walkable_world(end):
		var snapped := PathFinder.nearest_walkable_world(end, dir)
		snapped.y = from.y
		if PathFinder.is_walkable_world(snapped) and from.distance_to(snapped) >= 1.0:
			end = snapped
		else:
			var found := false
			for extra in [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
				var cand: Vector3 = from + dir * (AiConfig.FLASH_DISTANCE + extra)
				var half := Config.MAP_SIZE * 0.5
				cand.x = clampf(cand.x, -half, half)
				cand.z = clampf(cand.z, -half, half)
				if PathFinder.is_walkable_world(cand):
					end = cand
					found = true
					break
			if not found:
				return Vector3.ZERO
	if from.distance_to(end) < 1.0:
		return Vector3.ZERO
	if from.distance_to(end) > AiConfig.FLASH_DISTANCE + 2.0:
		return Vector3.ZERO
	return end


func _do_flash(end: Vector3) -> void:
	hero.global_position = end
	hero._clamp_to_map_edge()
	hero.move_target = Vector3.ZERO
	hero.summoner_cooldown = hero.summoner_skill.cooldown


func _try_flash() -> bool:
	# 逃跑：反向闪
	if _in_flee():
		var enemy = perception.find_nearest_enemy_hero(AiConfig.RETREAT_RANGE)
		if enemy == null:
			enemy = perception.find_nearest_enemy_hero(AiConfig.ENGAGE_RANGE)
		if enemy == null:
			return false
		var away: Vector3 = (hero.global_position - enemy.global_position)
		away.y = 0.0
		if away.length() < 0.1:
			away = Vector3.FORWARD
		var end1 := _flash_end(away.normalized())
		if end1 == Vector3.ZERO:
			return false
		_do_flash(end1)
		return true
	# 追击：向敌人闪（贴脸距离内不浪费）
	if _in_chase():
		var enemy2 = _flash_chase_target()
		if enemy2 == null:
			enemy2 = perception.find_nearest_enemy_hero(AiConfig.CHASE_START_RANGE)
		if enemy2 == null:
			return false
		if hero.global_position.distance_to(enemy2.global_position) <= AiConfig.MELEE_RANGE:
			return false
		var toward: Vector3 = (enemy2.global_position - hero.global_position)
		toward.y = 0.0
		if toward.length() < 0.1:
			return false
		var end2 := _flash_end(toward.normalized())
		if end2 == Vector3.ZERO:
			return false
		_do_flash(end2)
		return true
	return false


func _try_smite() -> bool:
	var monster = perception.find_nearest_jungle()
	if monster and monster.health < AiConfig.SMITE_DAMAGE_BASE + hero.level * AiConfig.SMITE_DAMAGE_PER_LEVEL:
		hero._use_summoner()
		return true
	return false

