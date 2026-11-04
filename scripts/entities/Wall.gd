class_name Wall
extends StaticBody3D

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")

# 高规格墙体标记（高地外周墙用）：由 BattleManager._add_wall 在加入场景前设置
var hq: bool = false
# 外周连续城墙：端面平齐的 2m 墙段，相邻段无缝拼接
var outer: bool = false
var outer_len: float = 2.0
# 野区连续墙：>0 表示一段端面平齐的墙体（长度=该值），相邻段首尾相接、无缝隙
var continuous_len: float = 0.0
var pillar: bool = false          # 连续墙两端的小柱
var open_end: bool = false        # 开放端：龙坑等故意不封口的墙，不参与自动补柱
var thick: float = 1.0            # 厚度倍率：不同墙段的厚度差异化（由 BattleManager 按位置哈希分配）

func _ready():
	# 程序化石墙模型（替代原 wall.glb）：按坐标哈希取种子，镜像对称仍然成立
	var seed_v: int = int(round(absf(position.x) * 10.0)) * 37 + int(round(absf(position.z) * 10.0)) * 91
	var thick_v: float = maxf(thick, 1.0)
	var vis: Node3D
	if pillar:
		vis = DecorMesh.pillar_visual()
	elif continuous_len > 0.0:
		# 野区连续墙：端面与相邻段平齐，高度压到 62% 免得挡视野；厚度按墙段差异化
		vis = DecorMesh.outer_wall_visual(continuous_len)
		vis.scale = Vector3(1.0, 0.62, thick_v)
	elif outer:
		vis = DecorMesh.outer_wall_visual(outer_len)
	elif hq:
		vis = DecorMesh.wall_visual_hq(seed_v)
	else:
		vis = DecorMesh.wall_visual(seed_v)
	# 让墙基贴合所在地面高度：分路台面/高地砖面会埋掉墙脚，墙看起来像直接插进地里
	vis.position.y = _visual_ground_y()
	add_child(vis)
	# 较厚的老墙挂常春藤等装饰（少量墙段，控制 draw call）
	if continuous_len > 0.0 and thick_v > 1.10 and seed_v % 3 == 0:
		add_child(DecorMesh.wall_decor_visual(seed_v))
	# 墙体为静态装饰：不投影（阴影 pass 里 700+ 墙段是主要 draw call 负担）
	_set_shadow_off(vis)

	# 碰撞形状（连续段沿墙长方向铺满，杜绝穿过缝隙）
	var col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	if continuous_len > 0.0:
		box.size = Vector3(continuous_len, 1.76, 0.55 * thick_v)
		col.position.y = 0.88
	elif pillar:
		box.size = Vector3(0.66, 2.40, 0.66)
		col.position.y = 1.20
	else:
		box.size = Vector3(0.4, 3, 0.4)
	col.shape = box
	add_child(col)
	add_to_group("walls")
	# 设置碰撞层
	collision_layer = 1
	collision_mask = 0

# 墙根视觉基准高度：分路路面 y≈0.14、高地砖面 y≈0.20、野区/外墙 y≈0。
# 只抬视觉根节点，碰撞体仍贴 y=0，避免影响寻路/推挤。
func _visual_ground_y() -> float:
	return DecorMesh.wall_ground_y(position)

func _set_shadow_off(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadow_off(c)
