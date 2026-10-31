extends Node
var f := 0
func _ready() -> void:
	add_child(load("res://scenes/lobby.tscn").instantiate())
func _process(_d: float) -> void:
	f += 1
	if f == 70:
		get_viewport().get_texture().get_image().save_png("res://screenshots/ui_lobby2.png")
		print("[P0] lobby shot")
		get_tree().quit()
