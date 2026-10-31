extends Node

var t := 0
var bm: BattleManager = null
var tur: Turret = null
var dummy: Minion = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 320:
		tur = bm.turrets[0] as Turret
		dummy = Minion.new()
		dummy.setup({"name": "melee", "team": 1, "max_health": 9999999, "attack": 1})
		dummy.position = tur.position + Vector3(4.0, 0.0, 0.0)
		dummy.can_move = false
		add_child(dummy)
		tur.current_target = dummy
	elif t == 345:
		var beam := tur.get("_lock_beam") as Node3D
		var from: Vector3 = tur.global_position + Vector3(0, 2.0, 0)
		var to: Vector3 = dummy.global_position + Vector3(0, 1.0, 0)
		for nm in ["Core", "Glow"]:
			var mi := beam.get_node_or_null(nm) as MeshInstance3D
			if mi == null:
				print("B ", nm, " missing")
				continue
			var xf: Transform3D = mi.global_transform
			var p0: Vector3 = xf * Vector3(0, -0.5, 0)
			var p1: Vector3 = xf * Vector3(0, 0.5, 0)
			print("B ", nm, " err0=", "%.3f" % p0.distance_to(from), " err1=", "%.3f" % p1.distance_to(to), " len=", "%.3f" % p0.distance_to(p1), " want_len=", "%.3f" % from.distance_to(to))
			var dir_mesh: Vector3 = (p1 - p0).normalized()
			var dir_want: Vector3 = (to - from).normalized()
			print("B ", nm, " dir_dot=", "%.4f" % dir_mesh.dot(dir_want), " axis=", dir_mesh, " want_axis=", dir_want)
		var tip := beam.get_node_or_null("Tip") as MeshInstance3D
		print("B tip_err=", "%.3f" % tip.global_position.distance_to(to))
		get_tree().quit()
