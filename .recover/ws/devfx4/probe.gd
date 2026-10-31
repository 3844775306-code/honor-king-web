extends Node

var t := 0
var bm: BattleManager = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _nearest(p: Vector3, walls: Array) -> float:
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
		print("Y walls_total=", walls.size())
		# 泉水净空
		print("Y fountain_clear_blue=", "%.2f" % _nearest(Vector3(-58, 0, 58), walls), " red=", "%.2f" % _nearest(Vector3(58, 0, -58), walls))
		# 外周覆盖（跳过两个基地角 12 格）
		var worst := 0.0
		var worst_p := Vector3.ZERO
		for tv in range(-62, 63, 2):
			if absf(float(tv)) <= 37.0:
				continue
			for p in [Vector3(-63, 0, float(tv)), Vector3(63, 0, float(tv)), Vector3(float(tv), 0, -63), Vector3(float(tv), 0, 63)]:
				var d := _nearest(p, walls)
				if d > worst:
					worst = d
					worst_p = p
		print("Y max_gap=", "%.2f" % worst, " at ", worst_p)
		# 龙坑：180° 弧覆盖角度
		for pit in [Vector3(24, 0, 26), Vector3(-24, 0, -26)]:
			var n := 0
			for w in walls:
				var n3: Node3D = w
				var dv := Vector3(n3.position.x - pit.x, 0, n3.position.z - pit.z)
				var dl := dv.length()
				if dl > 4.0 and dl < 10.0:
					n += 1
			print("Y pit=", pit, " ring_walls=", n)
	elif t == 360:
		get_tree().quit()
