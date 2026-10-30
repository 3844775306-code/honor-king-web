extends RefCounted

## 世界装饰（墙体 / 草丛的"真实模型"细节）：纯程序化几何，不依赖美术资源，host 与 client 共用。
## 墙体：基底土地苔藓盘 + 3 块随机碎石（破掉"一根柱子立在地上"的塑料感）
## 草丛：地面苔藓盘 + 额外一小簇草（打散整齐轮廓）+ 风摆
const BushSwayScript = preload("res://scripts/entities/BushSway.gd")

static func decorate_wall(wall: Node3D) -> void:
	if wall == null or not is_instance_valid(wall):
		return
	var seed_num: int = int(absf(wall.position.x) * 10.0) + int(absf(wall.position.z) * 10.0) * 7
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_num
	# 基底土地 / 苔藓盘
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.15
	cm.height = 0.06
	cm.radial_segments = 12
	disc.mesh = cm
	disc.position.y = 0.03
	disc.material_override = _mat(Color(0.20, 0.21, 0.16), 1.0)
	wall.add_child(disc)
	# 碎石：大小/位置/朝向都随机，但按坐标哈希确定（镜像对称不破坏）
	for i in range(3):
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = rng.randf_range(0.10, 0.18)
		sm.height = sm.radius * 1.3
		sm.radial_segments = 6
		sm.rings = 3
		rock.mesh = sm
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.35, 0.72)
		rock.position = Vector3(cos(a) * d, sm.radius * 0.4, sin(a) * d)
		rock.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
		rock.material_override = _mat(Color(0.30, 0.29, 0.26), 0.95)
		wall.add_child(rock)

static func decorate_bush(bush_parent: Node3D, model: Node3D, phase: float) -> void:
	if bush_parent == null or not is_instance_valid(bush_parent):
		return
	# 地面苔藓盘：让草丛"长在土上"
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.15
	cm.bottom_radius = 1.25
	cm.height = 0.05
	cm.radial_segments = 14
	disc.mesh = cm
	disc.position.y = 0.025
	disc.material_override = _mat(Color(0.10, 0.20, 0.10), 1.0)
	bush_parent.add_child(disc)
	if model != null and is_instance_valid(model):
		# 额外一小簇草：错开位置/朝向/尺寸，轮廓更蓬松
		var extra = model.duplicate()
		if extra is Node3D:
			var e3: Node3D = extra
			e3.scale = model.scale * Vector3(0.62, 0.52, 0.62)
			e3.rotation.y = model.rotation.y + 0.9
			e3.position = Vector3(0.55, 0.0, -0.4)
			bush_parent.add_child(e3)
		# 风摆：只摆视觉模型
		var sway = BushSwayScript.new()
		sway.target = model
		sway.phase = phase
		bush_parent.add_child(sway)

static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
