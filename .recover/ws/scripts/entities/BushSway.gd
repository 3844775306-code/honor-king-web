class_name BushSway
extends Node

## 草丛风摆：绕根部轻微摇摆（只转视觉模型，不影响 Area3D 区域判定与碰撞）
var target: Node3D = null
var phase: float = 0.0
var amp: float = 0.035

func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t: float = Time.get_ticks_msec() * 0.001
	target.rotation.z = sin(t * 0.9 + phase) * amp
	target.rotation.x = cos(t * 0.7 + phase * 1.3) * amp * 0.6
