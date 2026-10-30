class_name Bush
extends Area3D

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")

# 所属草丛区域编号：由 BattleManager 在创建时按“连片草丛(同一排)”分配；-1 表示未分配
var region_id: int = -1

func _ready():
	add_to_group("bush")
	# 程序化灌木模型（替代原 grass-large.glb）：坐标哈希取种子，镜像对称不被破坏
	var seed_b: int = int(round(absf(position.x) * 10.0)) * 131 + int(round(absf(position.z) * 10.0)) * 17
	add_child(DecorMesh.bush_visual(seed_b))

	# 区域检测
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(2, 2, 2)
	add_child(col)
	# 连接信号
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body is Hero:
		if region_id < 0:
			return
		body.enter_bush_region(region_id)

func _on_body_exited(body):
	if body is Hero:
		if region_id < 0:
			return
		body.exit_bush_region(region_id)
