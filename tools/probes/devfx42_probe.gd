extends Node

var t := 0
var hits := 0
var ctrl = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())
	ctrl = Control.new()
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.position = Vector2(300, 300)
	ctrl.size = Vector2(200, 100)
	ctrl.z_index = 500
	get_viewport().add_child(ctrl)
	ctrl.gui_input.connect(func(ev):
		if ev is InputEventMouseButton:
			hits += 1
			print("L ctrl_gui_input pos=", ev.position))

func _process(_d: float) -> void:
	t += 1
	if t == 10:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(350, 340)
		ev.global_position = Vector2(350, 340)
		get_viewport().push_input(ev)
		print("L pushed, hits=", hits)
	elif t == 30:
		print("L final_hits=", hits)
		get_tree().quit()
