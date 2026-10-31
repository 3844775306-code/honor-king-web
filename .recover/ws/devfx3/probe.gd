extends Node

const DM = preload("res://scripts/entities/DecorMesh.gd")

var t := 0
var bm: BattleManager = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _mesh_of(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var m := _mesh_of(c)
		if m != null:
			return m
	return null

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 300:
		var gm: ArrayMesh = DM.grass_mesh()
		var wm: ArrayMesh = DM.wall_mesh()
		print("W grass_tris=", gm.get_faces().size() / 3, " aabb=", gm.get_aabb().size)
		print("W wall_tris=", wm.get_faces().size() / 3, " aabb=", wm.get_aabb().size)
		var bvs: Node3D = DM.bush_visual(7)
		var wvs: Node3D = DM.wall_visual(9)
		var bm_mesh := _mesh_of(bvs)
		var wm_mesh := _mesh_of(wvs)
		print("W bush_tris=", bm_mesh.mesh.get_faces().size() / 3, " aabb=", bm_mesh.mesh.get_aabb().size)
		var f := bm.get_node_or_null("Fountain") if bm != null else null
		print("W fountain=", f != null, " children=", f.get_child_count() if f != null else -1)
		var bushes := get_tree().get_nodes_in_group("bush")
		var walls := get_tree().get_nodes_in_group("walls")
		print("W bushes=", bushes.size(), " walls=", walls.size())
		print("W bush_kids=", bushes[0].get_child_count(), " wall_kids=", walls[0].get_child_count())
		bvs.queue_free()
		wvs.queue_free()
	elif t == 400:
		get_tree().quit()
