extends RefCounted
## 英睿（Yingrui）视觉设计：无 glb 专用模型 → 用「男战士底座 + 程序化签名道具」+ 大招 LabiB 毛绒变身形态。
## 设计语言：冰蓝/雪白主色（与拳套武器同源）+ 奶茶红点缀；人形 = 冰茶拳少年（耳机 + 挂腰红茶 + 背包小毛绒），
## 大招「变身LabiB」= 换成一只等身毛绒怪兽（长耳 / 大眼 / 锯齿笑 / 短手短脚 / 爪拳），外形一眼可辨。
## 全部尺寸用「英雄实际身高 ~2.16m 的米制坐标」；通过 container_scale 适配不同调用方（主城 ×1 / 联机与预览要按各自模型缩放换算）。

const CREAM := Color(0.96, 0.94, 0.88)
const CREAM_SHADE := Color(0.88, 0.86, 0.78)
const ICE := Color(0.55, 0.85, 1.0)
const ICE_DEEP := Color(0.20, 0.46, 0.66)
const SLATE := Color(0.28, 0.34, 0.45)
const CHARCOAL := Color(0.10, 0.11, 0.14)
const TEA := Color(0.58, 0.24, 0.12)
const LABEL := Color(0.97, 0.97, 0.95)


## 人形签名道具：耳机 / 挂腰冰红茶 / 背包小 LabiB。
## parent = 英雄模型根（HeroModel，米制）；container_scale = 1 / 联机模型缩放 / 预览模型缩放。
static func attach_props(parent: Node3D, container_scale: float = 1.0) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var root := Node3D.new()
	root.name = "YR_Props"
	root.scale = Vector3.ONE * container_scale
	parent.add_child(root)
	_build_headphones(root)
	_build_tea_bottle(root)
	_build_back_plush(root)
	return root


## 大招「变身LabiB」形态：等身毛绒怪兽（脚底 y=0，耳朵最高 ~2.3m）。
static func build_labib() -> Node3D:
	var root := Node3D.new()
	root.name = "YR_LabiB"
	var fur := _mat(CREAM, 0.0, 0.72)
	var fur2 := _mat(CREAM_SHADE, 0.0, 0.78)
	var ice := _mat(ICE, 0.15, 0.32, 0.55)
	var ice_glow := _mat(ICE, 0.1, 0.25, 1.15)
	var dark := _mat(CHARCOAL, 0.1, 0.22)
	var eye := _mat(Color(0.98, 0.98, 1.0), 0.0, 0.15, 0.35)
	var slate := _mat(SLATE, 0.55, 0.4)

	# —— 身体（圆胖，略前倾）——
	_p(root, _sphere(0.44, 0.92), fur, Vector3(0.0, 0.74, 0.0), Vector3.ZERO, Vector3(1.0, 1.05, 0.92))
	_p(root, _sphere(0.30, 0.62), _mat(Color(0.99, 0.98, 0.94), 0.0, 0.8), Vector3(0.0, 0.72, 0.20), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
	# 脚
	for sx in [-1.0, 1.0]:
		_p(root, _sphere(0.18, 0.24), fur2, Vector3(0.19 * sx, 0.13, 0.06), Vector3.ZERO, Vector3(1.0, 0.7, 1.25))
	# 短腿
	for sx in [-1.0, 1.0]:
		_p(root, _cyl(0.13, 0.15, 0.30), fur, Vector3(0.19 * sx, 0.30, 0.0))
	# 尾巴
	_p(root, _sphere(0.10, 0.16), fur2, Vector3(0.0, 0.62, -0.44), Vector3(20.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.3))

	# —— 头（大，占身高近一半，毛绒玩偶比例）——
	_p(root, _sphere(0.52, 1.04), fur, Vector3(0.0, 1.52, 0.02), Vector3.ZERO, Vector3(1.0, 0.96, 0.95))
	# 脸颊绒毛簇
	for sx in [-1.0, 1.0]:
		for i in range(3):
			var t := float(i) / 2.0
			_p(root, _sphere(0.10 + 0.03 * t, 0.20), fur2,
				Vector3(sx * (0.42 + 0.05 * t), 1.40 - 0.12 * t, 0.20 - 0.02 * t))
	# 口鼻
	_p(root, _sphere(0.22, 0.30), _mat(Color(0.99, 0.98, 0.94), 0.0, 0.78),
		Vector3(0.0, 1.34, 0.44), Vector3.ZERO, Vector3(1.15, 0.78, 0.55))
	_p(root, _sphere(0.055, 0.08), dark, Vector3(0.0, 1.42, 0.60), Vector3.ZERO, Vector3(1.35, 0.9, 1.0))
	# 笑口 + 锯齿牙
	_p(root, _box(Vector3(0.40, 0.16, 0.06)), dark, Vector3(0.0, 1.25, 0.50))
	for i in range(6):
		var tx := -0.155 + 0.062 * float(i)
		_p(root, _prism(Vector3(0.055, 0.085, 0.03)), _mat(Color(1.0, 1.0, 0.98), 0.0, 0.3),
			Vector3(tx, 1.30, 0.545), Vector3(0.0, 0.0, 180.0))
	for i in range(5):
		var bx := -0.13 + 0.065 * float(i)
		_p(root, _prism(Vector3(0.048, 0.07, 0.03)), _mat(Color(1.0, 1.0, 0.98), 0.0, 0.3),
			Vector3(bx, 1.195, 0.545))
	# 大眼（冰蓝虹膜 + 高光）
	for sx in [-1.0, 1.0]:
		_p(root, _sphere(0.135, 0.27), eye, Vector3(0.185 * sx, 1.66, 0.40), Vector3.ZERO, Vector3(1.0, 1.0, 0.72))
		_p(root, _sphere(0.085, 0.17), ice_glow, Vector3(0.185 * sx, 1.66, 0.485), Vector3.ZERO, Vector3(1.0, 1.0, 0.6))
		_p(root, _sphere(0.032, 0.064), _mat(Color(0.05, 0.06, 0.09), 0.1, 0.1), Vector3(0.185 * sx, 1.66, 0.535), Vector3.ZERO, Vector3(1.0, 1.0, 0.5))
		_p(root, _sphere(0.024, 0.048), _mat(Color(1.0, 1.0, 1.0), 0.0, 0.1, 0.9), Vector3(0.155 * sx, 1.72, 0.545))
	# 眉毛（斜挑，凶萌）
	for sx in [-1.0, 1.0]:
		_p(root, _box(Vector3(0.16, 0.035, 0.05)), fur2, Vector3(0.19 * sx, 1.83, 0.40), Vector3(0.0, 0.0, -18.0 * sx))
	# —— 长耳（LabiB 标志）——
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(0.26 * sx, 1.92, -0.02)
		ear.rotation_degrees = Vector3(-6.0, 0.0, 16.0 * sx)
		root.add_child(ear)
		_p(ear, _sphere(0.135, 0.72), fur, Vector3(0.0, 0.30, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.55))
		_p(ear, _sphere(0.085, 0.48), ice, Vector3(0.0, 0.30, 0.06), Vector3.ZERO, Vector3(1.0, 1.0, 0.35))
	# 头顶冰晶（大招形态强化「冰」属性）
	for i in range(3):
		var ang := -0.5 + 0.5 * float(i)
		_p(root, _prism(Vector3(0.09, 0.26, 0.09)), ice_glow,
			Vector3(0.12 * ang, 2.02 + 0.03 * float(i % 2), 0.10), Vector3(0.0, 0.0, 14.0 * ang))
	# —— 手脚 ——
	for sx in [-1.0, 1.0]:
		_p(root, _cyl(0.12, 0.13, 0.42), fur, Vector3(0.46 * sx, 1.02, 0.02), Vector3(0.0, 0.0, 12.0 * sx))
		_p(root, _sphere(0.155, 0.24), slate, Vector3(0.56 * sx, 0.78, 0.08))
		for i in range(3):
			_p(root, _prism(Vector3(0.05, 0.10, 0.05)), ice_glow,
				Vector3(0.56 * sx + 0.055 * float(i - 1), 0.86, 0.16))
	# 右爪攥一瓶冰红茶（人形道具的呼应）：下半截实心红茶红 + 上身透明 + 瓶盖
	var glass := _mat(Color(0.88, 0.93, 0.99), 0.15, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.38
	_p(root, _cyl(0.055, 0.053, 0.14), _mat(TEA, 0.05, 0.4, 0.18), Vector3(-0.56, 0.83, 0.12))
	_p(root, _cyl(0.055, 0.055, 0.09), glass, Vector3(-0.56, 0.945, 0.12))
	_p(root, _cyl(0.045, 0.045, 0.05), slate, Vector3(-0.56, 1.04, 0.12))
	return root


static func _build_headphones(root: Node3D) -> void:
	var band := MeshInstance3D.new()
	band.name = "YR_Headphones"
	band.mesh = _torus(0.165, 0.215)
	band.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	band.position = Vector3(0.0, 1.97, -0.01)
	band.material_override = _mat(SLATE, 0.6, 0.35)
	root.add_child(band)
	for sx in [-1.0, 1.0]:
		_p(root, _cyl(0.078, 0.078, 0.065, 12), _mat(ICE, 0.2, 0.3, 0.5),
			Vector3(0.205 * sx, 1.90, -0.01), Vector3(0.0, 0.0, 90.0))
		_p(root, _torus(0.052, 0.082), _mat(ICE, 0.05, 0.25, 1.1),
			Vector3(0.243 * sx, 1.90, -0.01), Vector3(0.0, 90.0, 0.0))
		_p(root, _box(Vector3(0.035, 0.16, 0.045)), _mat(SLATE, 0.5, 0.4),
			Vector3(0.205 * sx, 1.97, -0.01))


static func _build_tea_bottle(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "YR_TeaBottle"
	holder.position = Vector3(-0.31, 1.06, -0.20)
	holder.rotation_degrees = Vector3(-12.0, 0.0, -16.0)
	root.add_child(holder)
	# 冰红茶：下半瓶身直接做实心红茶红（不靠透明玻璃透色，远处也认得出），上半截透明塑料 + 白标签 + 吸管
	var glass := _mat(Color(0.88, 0.93, 0.99), 0.15, 0.10)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.38
	_p(holder, _cyl(0.058, 0.056, 0.145, 12), _mat(TEA, 0.05, 0.38, 0.18), Vector3(0.0, 0.0725, 0.0))
	_p(holder, _cyl(0.058, 0.058, 0.10, 12), glass, Vector3(0.0, 0.192, 0.0))
	_p(holder, _cyl(0.060, 0.060, 0.055, 12), _mat(LABEL, 0.0, 0.5), Vector3(0.0, 0.150, 0.0))
	_p(holder, _cyl(0.045, 0.045, 0.05, 12), _mat(SLATE, 0.5, 0.35), Vector3(0.0, 0.255, 0.0))
	_p(holder, _cyl(0.012, 0.012, 0.20, 8), _mat(ICE, 0.1, 0.3, 0.6),
		Vector3(0.035, 0.33, 0.0), Vector3(0.0, 0.0, -10.0))


static func _build_back_plush(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "YR_BackPlush"
	holder.position = Vector3(0.0, 1.36, -0.29)
	root.add_child(holder)
	_p(holder, _sphere(0.155, 0.31), _mat(CREAM, 0.0, 0.8), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	for sx in [-1.0, 1.0]:
		_p(holder, _sphere(0.048, 0.15), _mat(CREAM, 0.0, 0.8),
			Vector3(0.075 * sx, 0.19, 0.0), Vector3(0.0, 0.0, 12.0 * sx), Vector3(1.0, 1.0, 0.6))
		_p(holder, _sphere(0.03, 0.09), _mat(ICE, 0.1, 0.4, 0.5),
			Vector3(0.075 * sx, 0.19, 0.045), Vector3(0.0, 0.0, 12.0 * sx), Vector3(1.0, 1.0, 0.4))
		_p(holder, _sphere(0.026, 0.052), _mat(CHARCOAL, 0.1, 0.2), Vector3(0.055 * sx, 0.075, 0.125))
	# 背带（从肩膀绕到背后，别让挂件看起来悬空）
	for sx in [-1.0, 1.0]:
		_p(root, _box(Vector3(0.045, 0.40, 0.028)), _mat(SLATE, 0.35, 0.5),
			Vector3(0.155 * sx, 1.42, -0.135), Vector3(-12.0, 0.0, 4.0 * sx))


static func _p(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _mat(col: Color, metallic: float = 0.2, rough: float = 0.5, emis: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, height: float, segs: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segs
	return m


static func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if h > 0.0 else r * 2.0
	m.radial_segments = 14
	m.rings = 7
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 18
	m.ring_segments = 8
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m
