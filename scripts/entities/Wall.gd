class_name Wall
extends StaticBody3D

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")

# 高规格墙体标记（高地外周墙用）：由 BattleManager._add_wall 在加入场景前设置
var hq: bool = false
# 外周连续城墙：端面平齐的 2m 墙段，相邻段无缝拼接
var outer: bool = false
var outer_len: float = 2.0

func _ready():
	# 程序化石墙模型（替代原 wall.glb）：按坐标哈希取种子，镜像对称仍然成立
	var seed_v: int = int(round(absf(position.x) * 10.0)) * 37 + int(round(absf(position.z) * 10.0)) * 91
	var vis: Node3D
	if outer:
		vis = DecorMesh.outer_wall_visual(outer_len)
	elif hq:
		vis = DecorMesh.wall_visual_hq(seed_v)
	else:
		vis = DecorMesh.wall_visual(seed_v)
	add_child(vis)
	# 墙体为静态装饰：不投影（阴影 pass 里 700+ 墙段是主要 draw call 负担）
	_set_shadow_off(vis)

	# 碰撞形状
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(0.4, 3, 0.4)
	add_child(col)
	add_to_group("walls")
	# 设置碰撞层
	collision_layer = 1
	collision_mask = 0

func _set_shadow_off(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadow_off(c)
