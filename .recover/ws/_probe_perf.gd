extends Node
var bm: Node
var f := 0
var done := false

func _ready() -> void:
	add_child(load("res://scenes/battle.tscn").instantiate())
	bm = get_tree().get_first_node_in_group("battle_manager")

func _collect(script_name: String) -> Array:
	var out := []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc = n.get_script()
		if sc != null and sc.resource_path.get_file() == script_name:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

func _t(label: String, nodes: Array, reps: int) -> void:
	if nodes.is_empty():
		print("PROBE|%s: none" % label)
		return
	var t0 := Time.get_ticks_usec()
	for r in range(reps):
		for n in nodes:
			n.call("_process", 1.0 / 60.0)
	var each := float(Time.get_ticks_usec() - t0) / float(reps) / 1000.0
	print("PROBE|%s x%d = %.3f ms" % [label, nodes.size(), each])

func _physics_process(_d: float) -> void:
	f += 1
	if f == 3:
		bm._start_game_body("鲁班七号")
		return
	if f < 200 or done:
		return
	done = true
	await get_tree().process_frame
	_t("HealthBarControl", _collect("HealthBarControl.gd"), 20)
	_t("HeroInfoControl", _collect("HeroInfoControl.gd"), 20)
	_t("HUD", _collect("HUD.gd"), 20)
	_t("Minimap", _collect("Minimap.gd"), 20)
	_t("PostFX", _collect("PostFX.gd"), 20)
	_t("TouchController", _collect("TouchController.gd"), 20)
	_t("SfxManager", _collect("SfxManager.gd"), 20)
	_t("VfxFactory", _collect("VfxFactory.gd"), 20)
	_t("UI_Manager", _collect("UI_Manager.gd"), 10)
	_t("HeroAI", _collect("HeroAI.gd"), 10)
	var ents := get_tree().get_nodes_in_group("entities")
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		CollisionSystem.apply_collision_pushback(ents, 1.0 / 60.0)
	print("PROBE|CollisionSystem = %.3f ms" % (float(Time.get_ticks_usec() - t0) / 20.0 / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in range(10):
		bm._process(1.0 / 60.0)
	print("PROBE|BattleManager._process = %.3f ms" % (float(Time.get_ticks_usec() - t0) / 10.0 / 1000.0))
	print("PROBE|DONE")
	get_tree().quit()
