extends Node

var t := 0
var bm: BattleManager = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _nearest(p: Vector3, walls: Array, skip_near: Array) -> float:
	var best := 999.0
	for w in walls:
		var n3: Node3D = w
		var d: float = Vector2(n3.position.x - p.x, n3.position.z - p.z).length()
		if d < best:
			best = d
	return best

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 320:
		var walls: Array = get_tree().get_nodes_in_group("walls")
		for p in [Vector3(-63, 0, 57), Vector3(-63, 0, 58), Vector3(-57, 0, 63), Vector3(-58, 0, 63), Vector3(63, 0, -57), Vector3(58, 0, -63)]:
			print("Q seam ", p, " -> ", "%.2f" % _nearest(p, walls, []))
		# 外周连续（跳过泉水鼓包区域，那里边界改由石环承担）
		var fc_b := Vector2(-62, 62)
		var fc_r := Vector2(62, -62)
		var worst := 0.0
		for tv in range(-62, 63, 2):
			if absf(float(tv)) <= 37.0:
				continue
			for p in [Vector3(-63, 0, float(tv)), Vector3(63, 0, float(tv)), Vector3(float(tv), 0, -63), Vector3(float(tv), 0, 63)]:
				var pv := Vector2(p.x, p.z)
				if pv.distance_to(fc_b) < 5.6 or pv.distance_to(fc_r) < 5.6:
					continue
				var d := _nearest(p, walls, [])
				if d > worst:
					worst = d
		print("Q perimeter_max_gap_excl_fountain=", "%.2f" % worst)
	elif t == 360:
		get_tree().quit()
