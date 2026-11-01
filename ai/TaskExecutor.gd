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
	return {}


func _push_task(task: TeamTask) -> Dictionary:
	if task.lane == AiConfig.Lane.JUNGLE:
		return {"lane": task.lane, "state": "push"}
	# 推线任务：只有在“有己方兵线 + 敌方英雄不在附近 + 塔在攻击距离内”时才主动摸塔；
	# 否则交给 LaneStrategy 清兵/靠近，避免团队任务把 AI 直接送进塔。
	var tower: Turret = null
	var best_d := 9999.0
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or int((t as Turret).team) == int(hero.team) or (t as Turret).health <= 0:
			continue
		var d := task.target_pos.distance_to((t as Turret).global_position) if task.target_pos != Vector3.ZERO else 0.0
		if task.target_pos == Vector3.ZERO:
			d = hero.global_position.distance_to((t as Turret).global_position)
		if d < best_d:
			best_d = d
			tower = t as Turret
	var enemy_near := perception.find_nearest_enemy_hero(8.0)
	if tower != null and enemy_near == null and _has_minion_cover(tower):
		var reach := hero.attack_range * AiConfig.ATTACK_RANGE_FACTOR + 3.0
		if hero.global_position.distance_to(tower.global_position) <= reach:
			return {"move_target": Vector3.ZERO, "manual_target": tower, "state": "push"}
	# 没形成安全推塔窗口：继续交给 LaneStrategy 处理兵线
	return {"lane": task.lane, "state": "push"}


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
