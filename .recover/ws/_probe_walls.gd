extends Node

func _ready() -> void:
	await get_tree().process_frame
	var scene = load("res://scenes/battle.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var bm = null
	for n in get_tree().get_nodes_in_group("battle_manager"):
		bm = n
	if bm == null:
		for c in scene.get_children():
			if c is BattleManager:
				bm = c
	bm._generate_lane_edge_walls()
	bm._generate_high_ground_walls()
	bm._generate_outer_walls()
	bm._create_jungle()
	bm._generate_jungle_arc_walls()
	await get_tree().process_frame
	var total := 0
	var cont := 0
	var pill := 0
	var outer := 0
	var pts: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		total += 1
		if w.pillar:
			pill += 1
		elif absf(w.continuous_len) > 0.01:
			cont += 1
			var th: float = w.rotation.y
			var half: float = absf(w.continuous_len) * 0.5
			var dir := Vector3(cos(th), 0.0, -sin(th))
			pts.append([w.global_position - dir * half, w.global_position + dir * half])
		if w.outer:
			outer += 1
	print("WALL_TOTAL=%d CONT=%d PILLAR=%d OUTER=%d" % [total, cont, pill, outer])
	var gaps: Array = []
	for e in pts:
		for ep in e:
			var best := 999.0
			for o in pts:
				if o == e:
					continue
				var d: float = _seg_dist(ep, o[0], o[1])
				if d < best:
					best = d
			if best < 900.0:
				gaps.append(best)
	gaps.sort()
	if gaps.size() > 0:
		var over := 0
		for g in gaps:
			if g > 0.25:
				over += 1
		print("GAP median=%.3f max=%.3f over25cm=%d/%d" % [gaps[gaps.size() / 2], gaps[gaps.size() - 1], over, gaps.size()])
	# 龙坑口：无端柱、有连续开放段
	for pit in bm.epic_pit_centers:
		var mouth_pillars := 0
		var open_segs := 0
		for w in get_tree().get_nodes_in_group("walls"):
			if w.global_position.distance_to(pit) < 9.3:
				if w.pillar:
					mouth_pillars += 1
				elif absf(w.continuous_len) > 0.01 and w.open_end:
					open_segs += 1
		print("PIT %s mouth_pillars=%d open_segs=%d" % [str(pit), mouth_pillars, open_segs])
	# 高地弧墙 / 分路内缘墙数量
	var hg := 0
	var lane_inner := 0
	for w in get_tree().get_nodes_in_group("walls"):
		if absf(w.continuous_len) < 0.01 or w.pillar:
			continue
		var d_blue: float = w.global_position.distance_to(Vector3(-60, 0, 60))
		var d_red: float = w.global_position.distance_to(Vector3(60, 0, -60))
		if (d_blue > 33.0 and d_blue < 37.0) or (d_red > 33.0 and d_red < 37.0):
			hg += 1
		if absf(w.global_position.x) > 46.0 and absf(w.global_position.x) < 48.0 and absf(w.global_position.z) <= 38.0:
			lane_inner += 1
	print("HG_SEGS=%d LANE_INNER_SEGS=%d" % [hg, lane_inner])
	print("PROBE_DONE")
	get_tree().quit()

func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
