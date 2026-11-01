class_name TaskExecutor
extends RefCounted
## 把 TeamTask 翻译成 HeroAI 可执行的走位/目标。
## 生存和换血仍由 HeroAI 的前置分支优先处理；这里是“团队任务”的默认执行层。

var hero: Hero
var perception: AiPerception


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception


func execute(task: TeamTask, now: float) -> Dictionary:
	if task == null or hero == null or not is_instance_valid(hero) or hero.is_dead:
		return {}
	if task.is_expired(now):
		return {}
	match task.type:
		TeamTask.Type.PUSH_LANE:
			return _push_task(task)
		TeamTask.Type.DEFEND_LANE:
			return _defend_task(task)
		TeamTask.Type.OBJECTIVE:
			return _objective_task(task)
		TeamTask.Type.GANK:
			return _gank_task(task)
		TeamTask.Type.PEEL:
			return _peel_task(task)
		TeamTask.Type.RETREAT:
			return {"move_target": task.target_pos, "manual_target": null, "state": "retreat"}
		TeamTask.Type.PUSH_TOWER:
			return _push_tower_task(task)
		TeamTask.Type.INVADE_JUNGLE:
			return _invade_task(task)
		TeamTask.Type.JUNGLE_FARM:
			return _jungle_farm(task.target_pos)
	return {}


func local_lane(lane: int) -> Dictionary:
	return _lane_behavior(lane, Vector3.ZERO)


func local_jungle(target_pos: Vector3) -> Dictionary:
	return _jungle_farm(target_pos)


func _push_tower_task(task: TeamTask) -> Dictionary:
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) == int(hero.team) or (e as Turret).health <= 0:
			continue
		if (e as Node3D).global_position.distance_to(task.target_pos) > 8.0:
			continue
		var reach := hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR + 4.0
		if hero.global_position.distance_to((e as Node3D).global_position) <= reach:
			return {"move_target": Vector3.ZERO, "manual_target": e, "state": "push"}
		return {"move_target": (e as Node3D).global_position, "manual_target": null, "state": "push"}
	return {"move_target": task.target_pos, "manual_target": null, "state": "push"}


func _invade_task(task: TeamTask) -> Dictionary:
	var best = null
	var best_d := 15.0
	for e in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if e is JungleMonster and (e as JungleMonster).health > 0:
			var d := task.target_pos.distance_to((e as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = e
	if best != null:
		if hero.global_position.distance_to((best as Node3D).global_position) <= 10.0:
			return {"move_target": Vector3.ZERO, "manual_target": best, "state": "push"}
		return {"move_target": (best as Node3D).global_position, "manual_target": null, "state": "push"}
	return {"move_target": task.target_pos, "manual_target": null, "state": "push"}


func _push_task(task: TeamTask) -> Dictionary:
	return _lane_behavior(task.lane, task.target_pos)


# 统一本地推线：先补兵，有兵线掩护且塔可摸时再推塔；不再依赖 LaneStrategy。
func _lane_behavior(lane: int, preferred_tower: Vector3) -> Dictionary:
	var best_minion: Minion = null
	var best_hp := INF
	for e in hero.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) == int(hero.team) or (e as Minion).health <= 0:
			continue
		if hero.global_position.distance_to((e as Node3D).global_position) > 12.0:
			continue
		if not TowerCombat.can_attack_under_tower(hero, e):
			continue
		if (e as Minion).health < best_hp:
			best_hp = (e as Minion).health
			best_minion = e as Minion
	if best_minion != null:
		return {"move_target": Vector3.ZERO, "manual_target": best_minion, "state": "push"}
	# 没兵可补时，才考虑附近敌方英雄；塔下目标交给 TowerCombat 评估手长/越塔次数。
	var enemy_hero := perception.find_nearest_enemy_hero(9.0)
	if enemy_hero != null and hero.health > hero.actual_max_health * 0.38 \
			and TowerCombat.can_attack_under_tower(hero, enemy_hero):
		return {"move_target": Vector3.ZERO, "manual_target": enemy_hero, "state": "push"}
	var tower: Turret = null
	if preferred_tower != Vector3.ZERO:
		var best_d := 8.0
		for e in hero.get_tree().get_nodes_in_group("turrets"):
			if e is Turret and int((e as Turret).team) != int(hero.team) and (e as Turret).health > 0:
				var d := preferred_tower.distance_to((e as Node3D).global_position)
				if d < best_d:
					best_d = d
					tower = e as Turret
	else:
		tower = _nearest_enemy_tower_in_lane(lane)
	if tower != null and _friendly_wave_hp_near(tower) > 1000.0 and perception.find_nearest_enemy_hero(8.0) == null:
		var reach := hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR + 3.0
		if hero.global_position.distance_to(tower.global_position) <= reach:
			return {"move_target": Vector3.ZERO, "manual_target": tower, "state": "push"}
		return {"move_target": tower.global_position, "manual_target": null, "state": "push"}
	var goal := preferred_tower if preferred_tower != Vector3.ZERO else _friendly_forward_minion(lane)
	if goal == Vector3.ZERO:
		goal = _lane_default_pos(lane)
	return {"move_target": goal, "manual_target": null, "state": "push"}


func _friendly_forward_minion(lane: int) -> Vector3:
	var own_crystal := Vector3(-53, 0, 53) if int(hero.team) == Config.Team.PLAYER else Vector3(53, 0, -53)
	var best := Vector3.ZERO
	var best_d := -INF
	for e in hero.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) != int(hero.team) or (e as Minion).health <= 0:
			continue
		var d: float = own_crystal.distance_to((e as Node3D).global_position)
		if d > best_d:
			best_d = d
			best = (e as Node3D).global_position
	return best


func _nearest_enemy_tower_in_lane(lane: int) -> Turret:
	var best: Turret = null
	var best_d := INF
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) == int(hero.team) or (e as Turret).health <= 0:
			continue
		var s := (e as Node3D).global_position.x + (e as Node3D).global_position.z
		var ln := AiConfig.Lane.FARM if s > 0.0 else (AiConfig.Lane.CLASH if s < 0.0 else AiConfig.Lane.MID)
		if ln != lane:
			continue
		var d := hero.global_position.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = e as Turret
	return best


func _friendly_wave_hp_near(tower: Turret) -> float:
	var hp := 0.0
	for m in hero.get_tree().get_nodes_in_group("minions"):
		if m is Minion and int((m as Minion).team) == int(hero.team) and (m as Minion).health > 0:
			if tower.global_position.distance_to((m as Node3D).global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				hp += (m as Minion).health
	return hp


func _lane_default_pos(lane: int) -> Vector3:
	match lane:
		AiConfig.Lane.FARM: return Vector3(30, 0, 30)
		AiConfig.Lane.MID: return Vector3(0, 0, 0)
		AiConfig.Lane.CLASH: return Vector3(-30, 0, -30)
	return Vector3.ZERO


func _jungle_farm(target_pos: Vector3) -> Dictionary:
	var best = null
	var best_d := 30.0
	for e in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if e is JungleMonster and (e as JungleMonster).health > 0:
			var d := hero.global_position.distance_to((e as Node3D).global_position)
			if d < best_d and (target_pos == Vector3.ZERO or target_pos.distance_to((e as Node3D).global_position) <= 35.0):
				best_d = d
				best = e
	if best != null:
		if hero.global_position.distance_to((best as Node3D).global_position) <= hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR + 1.0:
			return {"move_target": Vector3.ZERO, "manual_target": best, "state": "push"}
		return {"move_target": (best as Node3D).global_position, "manual_target": null, "state": "push"}
	return {"move_target": target_pos if target_pos != Vector3.ZERO else Vector3(0, 0, 0), "manual_target": null, "state": "push"}


func _defend_task(task: TeamTask) -> Dictionary:
	# 守塔不主动追出塔外；只有自己状态健康、敌人贴近守塔点时才反击。
	var enemy := perception.find_nearest_enemy_hero(7.0)
	if enemy != null and hero.health > hero.actual_max_health * 0.40 \
			and not _dangerously_under_tower(enemy):
		return {"move_target": task.target_pos, "manual_target": enemy, "state": "push"}
	return {"move_target": task.target_pos, "manual_target": null, "state": "push"}


func _objective_task(task: TeamTask) -> Dictionary:
	# 资源任务：先在目标区域找龙/暴君；够得到就开打，否则先集合。
	var best = null
	var best_d := 12.0
	for e in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if e is JungleMonster and (e as JungleMonster).health > 0:
			var d := task.target_pos.distance_to((e as JungleMonster).global_position)
			if d < best_d:
				best_d = d
				best = e
	if best != null and hero.global_position.distance_to((best as Node3D).global_position) <= 10.0:
		return {"move_target": Vector3.ZERO, "manual_target": best, "state": "push"}
	return {"move_target": task.target_pos, "manual_target": null, "state": "push"}


func _gank_task(task: TeamTask) -> Dictionary:
	if task.target_hero != null and is_instance_valid(task.target_hero) and task.target_hero.health > 0.0:
		if hero.global_position.distance_to(task.target_hero.global_position) <= 12.0:
			return {"move_target": Vector3.ZERO, "manual_target": task.target_hero, "state": "push"}
	return {"move_target": task.target_pos, "manual_target": null, "state": "push"}


func _peel_task(task: TeamTask) -> Dictionary:
	var carry = task.target_hero
	if carry == null or not is_instance_valid(carry) or (carry as Hero).health <= 0.0:
		return {"move_target": task.target_pos, "manual_target": null, "state": "push"}
	var best: Hero = null
	var best_d := 6.0
	for e in hero.get_tree().get_nodes_in_group("heroes"):
		if not (e is Hero) or (e as Hero).team == hero.team or (e as Hero).health <= 0.0:
			continue
		var h := e as Hero
		if h.is_untargetable_by_enemies():
			continue
		var d := (carry as Node3D).global_position.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = h
	# 保排也要先保自己：血量过低/敌方越塔时不追，先回到射手身边或安全位置。
	if best != null and hero.health > hero.actual_max_health * 0.42 \
			and not _dangerously_under_tower(best):
		return {"move_target": Vector3.ZERO, "manual_target": best, "state": "push"}
	var follow_pos: Vector3 = (carry as Node3D).global_position
	return {"move_target": follow_pos, "manual_target": null, "state": "push"}


func _has_minion_cover(tower: Turret) -> bool:
	var cover := 0.0
	for m in hero.get_tree().get_nodes_in_group("minions"):
		if m is Minion and int(m.team) == int(hero.team) and (m as Minion).health > 0:
			if tower.global_position.distance_to((m as Minion).global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				cover += (m as Minion).health
	return cover >= 500.0


func _dangerously_under_tower(target: Hero) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or int(t.team) == int(hero.team) or (t as Turret).health <= 0:
			continue
		if target.global_position.distance_to((t as Turret).global_position) > AiConfig.TOWER_ATTACK_RANGE:
			continue
		var cover := 0.0
		for m in hero.get_tree().get_nodes_in_group("minions"):
			if m is Minion and int(m.team) == int(hero.team) and (m as Minion).health > 0:
				if (t as Turret).global_position.distance_to((m as Minion).global_position) <= AiConfig.TOWER_ATTACK_RANGE:
					cover += (m as Minion).health
		if cover < 500.0:
			return true
	return false
