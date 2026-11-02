class_name TrainingDummy
extends GameEntity
## 训练营木偶：站桩、超高血量、不移动不攻击，供技能/伤害测试。

func _ready() -> void:
	add_to_group("training_dummies")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.0
	shape.height = 2.4
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	add_child(col)
	_build_visual()
	visible = true

func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.42, 0.24)
	mat.roughness = 0.9
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.85
	bm.height = 2.2
	body.mesh = bm
	body.position.y = 1.1
	body.material_override = mat
	add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.55
	hm.height = 1.1
	head.mesh = hm
	head.position.y = 2.45
	head.material_override = mat
	add_child(head)
	# 靶心环：醒目可瞄准
	for i in range(3):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9 + i * 0.22
		tm.outer_radius = 1.02 + i * 0.22
		tm.rings = 24
		tm.ring_segments = 8
		ring.mesh = tm
		ring.position.y = 1.0 + i * 0.32
		ring.rotation.x = PI * 0.5
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.55, 0.18, 0.75)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = rm
		add_child(ring)
	var lab := Label3D.new()
	lab.text = "训练木偶"
	lab.font_size = 42
	lab.outline_size = 8
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position.y = 3.1
	lab.modulate = Color(1.0, 0.88, 0.55)
	add_child(lab)


func bar_anchor_height() -> float:
	return 3.25


func die(_killer = null) -> void:
	# 训练木偶不被击杀：血量归零后立即满血复位
	health = actual_max_health if actual_max_health > 0.0 else max_health
	is_dead = false
	visible = true
