extends Camera3D

@export var target: Node3D

func _process(delta):
	if target:
		global_position = target.global_position + Vector3(0, 15, 5)
