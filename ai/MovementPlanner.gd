class_name MovementPlanner
extends RefCounted
## 给 AI 用的路径评分：长度 + 敌方英雄记忆威胁 + 敌塔危险。
## 先走 PathFinder 的 A*；再用中点侧向绕行生成候选，选综合代价最低的一条。

const SIDE_STEPS := [8.0, 12.0]
const RISK_WEIGHT := 0.8
const RISK_RADIUS := 8.0


static func plan(hero: Hero, goal: Vector3, threat: ThreatModel) -> Array:
	if hero == null or not PathFinder.initialized:
		return []
	var start: Vector3 = hero.global_position
	var best: Array = []
	var best_cost := INF
	for path in _candidate_paths(start, goal, hero.team, hero):
		if path.is_empty():
			continue
		var cost := _path_cost(hero, path, threat)
		if cost < best_cost:
			best_cost = cost
			best = path
	return best


static func _candidate_paths(start: Vector3, goal: Vector3, team: int, hero: Hero = null) -> Array:
	var out: Array = []
	var base := PathFinder.find_path(start, goal, Vector3.ZERO, team)
	if not base.is_empty():
		out.append(Array(base))
	var mid := start.lerp(goal, 0.5)
	var dir := goal - start
	dir.y = 0.0
	if dir.length() < 1.0:
		return out
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized()
	for off in SIDE_STEPS:
		for sign in [-1.0, 1.0]:
			var wp: Vector3 = mid + perp * off * sign
			if not PathFinder.is_walkable_world(wp):
				continue
			var a := PathFinder.find_path(start, wp, Vector3.ZERO, team)
			var b := PathFinder.find_path(wp, goal, Vector3.ZERO, team)
			if a.is_empty() or b.is_empty():
				continue
			var combined: Array = Array(a)
			for i in range(1, b.size()):
				combined.append(b[i])
			out.append(combined)
	# 绕开敌方持续地面区域：给每个压在路线上的区域补左右绕行候选
	if hero != null:
		for e in hero.get_tree().get_nodes_in_group("ai_ground_zones"):
			if not (e is Node3D) or not is_instance_valid(e) or not (e as Node3D).is_inside_tree():
				continue
			if int(e.get_meta("zone_team", -1)) == int(team):
				continue
			var zc: Vector3 = (e as Node3D).global_position
			var radius: float = float(e.get_meta("zone_radius", 3.0))
			var ab: Vector3 = goal - start
			ab.y = 0.0
			if ab.length_squared() < 0.01:
				continue
			var t: float = clampf((zc - start).dot(ab) / ab.length_squared(), 0.0, 1.0)
			if (start + ab * t).distance_to(zc) > radius + 2.0:
				continue
			var zperp := Vector3(-ab.z, 0.0, ab.x).normalized()
			for sign in [-1.0, 1.0]:
				var wp2: Vector3 = zc + zperp * (radius + 2.0) * sign
				if not PathFinder.is_walkable_world(wp2):
					continue
				var a2 := PathFinder.find_path(start, wp2, Vector3.ZERO, team)
				var b2 := PathFinder.find_path(wp2, goal, Vector3.ZERO, team)
				if a2.is_empty() or b2.is_empty():
					continue
				var combined2: Array = Array(a2)
				for i in range(1, b2.size()):
					combined2.append(b2[i])
				out.append(combined2)
	return out


static func path_length(path: Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i] as Vector3).distance_to(path[i - 1] as Vector3)
	return total


static func path_risk(hero: Hero, path: Array, threat: ThreatModel) -> float:
	var risk := 0.0
	for p in path:
		if threat != null:
			risk += threat.enemy_threat(RISK_RADIUS, p)
		risk += _tower_risk(hero, p)
		risk += _ground_zone_risk(hero, p)
	return risk


## 持续地面技能危险：路点越靠近敌方危险区中心，代价越高
static func _ground_zone_risk(hero: Hero, p: Vector3) -> float:
	var total := 0.0
	if hero == null or not is_instance_valid(hero):
		return 0.0
	for e in hero.get_tree().get_nodes_in_group("ai_ground_zones"):
		if not (e is Node3D) or not is_instance_valid(e) or not (e as Node3D).is_inside_tree():
			continue
		if int(e.get_meta("zone_team", -1)) == int(hero.team):
			continue
		var radius: float = float(e.get_meta("zone_radius", 3.0))
		var d: float = p.distance_to((e as Node3D).global_position)
		if d < radius + 1.0:
			total += (1.0 - d / maxf(0.1, radius + 1.0)) * 3.0
	return total


static func _path_cost(hero: Hero, path: Array, threat: ThreatModel) -> float:
	var length := path_length(path)
	var travel := length / maxf(1.0, hero.actual_move_speed)
	var risk := path_risk(hero, path, threat)
	return travel + RISK_WEIGHT * (risk / (1.0 + risk))


static func _tower_risk(hero: Hero, p: Vector3) -> float:
	var total := 0.0
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) != int(hero.team) and (e as Turret).health > 0:
			var reach: float = (e as Turret).attack_range * 0.01
			var d: float = p.distance_to((e as Node3D).global_position)
			if d < reach:
				total += 1.0 - d / maxf(0.1, reach)
	return total
