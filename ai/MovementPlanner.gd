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
	for path in _candidate_paths(start, goal, hero.team):
		if path.is_empty():
			continue
		var cost := _path_cost(hero, path, threat)
		if cost < best_cost:
			best_cost = cost
			best = path
	return best


static func _candidate_paths(start: Vector3, goal: Vector3, team: int) -> Array:
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
	return out


static func _path_cost(hero: Hero, path: Array, threat: ThreatModel) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += (path[i] as Vector3).distance_to(path[i - 1] as Vector3)
	var travel := length / maxf(1.0, hero.actual_move_speed)
	var risk := 0.0
	for p in path:
		if threat != null:
			risk += threat.enemy_threat(RISK_RADIUS, p)
		risk += _tower_risk(hero, p)
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
