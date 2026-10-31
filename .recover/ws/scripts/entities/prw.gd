class_name Prw
extends Node3D
@export var team: float = 0
@export var damage: float = 0
@export var magic: float = 0
@export var applies_slow: float = 0.0   # 减速百分比
@export var slow_duration: float = 0.0
@export var applies_stun: float = 0.0   # 眩晕时长
@export var applies_knockup: float = 0.0 # 击飞时长
@export var prw: MeshInstance3D
func _ready() -> void:
	add_to_group("preview")
