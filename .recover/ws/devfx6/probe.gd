extends Node

var t := 0
var bm: BattleManager = null

func _ready() -> void:
	for p in ["res://scripts/net/NetSession.gd", "res://scripts/net/NetClientBattle.gd", "res://scripts/net/NetModels.gd", "res://scripts/entities/Wall.gd", "res://scripts/entities/DecorMesh.gd", "res://scripts/core/BattleManager.gd"]:
		print("P load ", p, " -> ", load(p) is GDScript)
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 320:
		var walls: Array = get_tree().get_nodes_in_group("walls")
		var hq_n := 0
		for w in walls:
			if w.get("hq") == true:
				hq_n += 1
		print("P walls=", walls.size(), " hq=", hq_n)
		var lp: Array = bm.lane_plane_nodes.values()[0]
		print("P curb_children=", (lp[0] as Node3D).get_child_count(), " curb_y=", ((lp[0] as Node3D).get_child(0) as Node3D).position.y)
	elif t == 360:
		get_tree().quit()
