extends Node
const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")

var t := 0
var bm = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _find(n: Node, nm: String):
	if n.name == nm:
		return n
	for c in n.get_children():
		var r = _find(c, nm)
		if r != null:
			return r
	return null

func _mesh_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node3D = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			var box: AABB = n.global_transform * n.get_aabb()
			out = box if not has else out.merge(box)
			has = true
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager")
		bm._start_game_body("亚瑟", "flash")
	elif t % 30 == 0:
		print("L tick=", t)
	elif t == 70:
		for e in get_tree().get_nodes_in_group("entities"):
			if not (e is Hero):
				continue
			var w = _find(e, "Weapon")
			if w == null:
				print("L ", e.display_name, " NO_WEAPON")
				continue
			var vis = e.get_node_or_null("HeroModel")
			var rel: Vector3 = vis.global_transform.affine_inverse() * w.global_position if vis != null else w.global_position - e.global_position
			var box: AABB = _mesh_aabb(w)
			print("L ", e.display_name, " parent=", w.get_parent().name, " grip=", Vector3(snappedf(rel.x, 0.01), snappedf(rel.y, 0.01), snappedf(rel.z, 0.01)), " sc=", snappedf(w.global_transform.basis.get_scale().x, 0.01), " size=", Vector3(snappedf(box.size.x, 0.01), snappedf(box.size.y, 0.01), snappedf(box.size.z, 0.01)))
		var h = null
		for e in get_tree().get_nodes_in_group("entities"):
			if e is Hero and e.team == 0:
				h = e
				break
		var wp = _find(h, "Weapon")
		var p0: Vector3 = wp.global_position
		HeroWeapons.play(h.visual_mesh, "attack")
		await get_tree().create_timer(0.12).timeout
		print("L swing_delta=", (wp.global_position - p0).length(), " peak_rot=", wp.rotation)
		await get_tree().create_timer(0.4).timeout
		print("L back_delta=", (wp.global_position - p0).length())
		get_tree().quit()
