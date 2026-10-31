extends Node
var f := 0
var bm
func _ready() -> void:
	var ps := load("res://scenes/battle.tscn") as PackedScene
	var root: Node = ps.instantiate()
	add_child(root)
	bm = root.get_node("BattleManager")
func _process(_d: float) -> void:
	f += 1
	if f == 230:
		bm._show_game_over()
	if f == 250:
		get_viewport().get_texture().get_image().save_png("res://screenshots/ui_results_p0.png")
		print("[P0] results shot")
		get_tree().quit()
