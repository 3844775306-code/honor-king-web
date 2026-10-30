class_name MinionModel
extends RefCounted
## 程序化小兵模型（候选版，暂未接入）
## 风格：低多边形东方古风甲士，钢/青铜/皮革+队伍色布甲，贴合地图的写实偏冷色调。

const SUPPORTED := ["melee", "ranged", "siege", "super", "dragon", "storm", "shadow_dragon"]
const APPLIED := ["melee", "ranged", "siege", "super", "dragon", "storm", "shadow_dragon"]
const TEAM_CLOTH := [Color(0.16, 0.62, 0.74), Color(0.76, 0.20, 0.16)]
const TARGET_H := {"melee": 1.30, "ranged": 1.30, "siege": 1.30, "super": 1.95,
	"dragon": 2.15, "storm": 2.15, "shadow_dragon": 2.15}

# 模板缓存：同兵种同阵营只构建一次，之后 duplicate() 共享 Mesh/材质。
# 构建模型在真实渲染下约 60~170ms（headless 仅 2ms），每次出兵重建是每波兵线卡顿的根源。
static var _templates: Dictionary = {}


static func is_supported(kind: String) -> bool:
	return kind in SUPPORTED


static func is_applied(kind: String) -> bool:
	return kind in APPLIED


static func target_height(kind: String) -> float:
	return float(TARGET_H.get(kind, 1.30))


static func build(kind: String, team: int) -> Node3D:
	var key := "%s|%d" % [kind, team]
	var tpl: Node3D = _templates.get(key)
	if tpl == null:
		tpl = _build_template(kind, team)
		_templates[key] = tpl
	return tpl.duplicate() as Node3D


static func _build_template(kind: String, team: int) -> Node3D:
	var root := Node3D.new()
	var mats := _materials(team, kind)
	var sts: Dictionary = {}
	match kind:
		"melee":
			_body(sts, mats, false, true)
			_arms_melee(sts, mats)
		"ranged":
			_body(sts, mats, false, true)
			_arms_bow(sts, mats)
		"siege":
			_siege(sts, mats)
		"super":
			_body(sts, mats, true, true)
			_arms_halberd(sts, mats)
			_heavy_crest(sts, mats)
		"dragon", "storm", "shadow_dragon":
			_dragon(sts, mats, kind)
		_:
			_body(sts, mats, false, true)
			_arms_melee(sts, mats)
	var mesh := _commit(sts, mats)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	pivot.add_child(mi)
	root.add_child(pivot)
	# 拆出的双腿：髋关节枢轴，供行走摆动
	if kind in ["melee", "ranged", "super"]:
		_build_legs(pivot, mats, kind == "super")
	var h := mesh.get_aabb().end.y if kind in ["melee", "ranged", "super"] else mesh.get_aabb().size.y
	# 超级兵按甲士本体高度归一化，长戟不参与身高缩放
	if kind == "super":
		h = 1.36
	if h > 0.01:
		var s := target_height(kind) / h
		root.scale = Vector3(s, s, s)
	root.set_meta("minion_model_kind", kind)
	root.set_meta("tint_strength", 0.30)
	return root


# ==================== 材质 ====================

static func _materials(team: int, kind: String = "") -> Dictionary:
	var cloth: Color = TEAM_CLOTH[1] if team == 1 else TEAM_CLOTH[0]
	var d := {
		"steel": _mat(Color(0.54, 0.57, 0.61), 0.50, 0.38),
		"dark": _mat(Color(0.20, 0.21, 0.24), 0.38, 0.55),
		"bronze": _mat(Color(0.70, 0.51, 0.26), 0.55, 0.34),
		"gold": _mat(Color(0.92, 0.71, 0.32), 0.65, 0.28),
		"leather": _mat(Color(0.33, 0.23, 0.15), 0.05, 0.86),
		"wood": _mat(Color(0.34, 0.23, 0.12), 0.02, 0.90),
		"skin": _mat(Color(0.64, 0.49, 0.37), 0.0, 0.82),
		"cloth": _mat(cloth, 0.0, 0.86),
		"black": _mat(Color(0.045, 0.045, 0.05), 0.10, 0.72),
	}
	if kind in ["dragon", "storm", "shadow_dragon"]:
		var scale_col := Color(0.20, 0.34, 0.24)
		var memb_col := Color(0.24, 0.36, 0.20)
		var horn_col := Color(0.78, 0.68, 0.46)
		var eye_col := Color(1.0, 0.72, 0.18)
		var memb_emit := Color(0.0, 0.0, 0.0)
		if kind == "storm":
			scale_col = Color(0.16, 0.36, 0.48)
			memb_col = Color(0.20, 0.60, 0.78)
			horn_col = Color(0.72, 0.82, 0.90)
			eye_col = Color(0.45, 0.95, 1.0)
			memb_emit = Color(0.15, 0.62, 0.95)
		elif kind == "shadow_dragon":
			scale_col = Color(0.09, 0.07, 0.12)
			memb_col = Color(0.25, 0.08, 0.34)
			horn_col = Color(0.42, 0.30, 0.55)
			eye_col = Color(1.0, 0.35, 0.95)
			memb_emit = Color(0.55, 0.10, 0.95)
		d["scale"] = _mat(scale_col, 0.18, 0.62)
		d["membrane"] = _mat_emit(memb_col, memb_emit, 0.8)
		d["horn"] = _mat(horn_col, 0.42, 0.38)
		d["eye"] = _mat_emit(eye_col, eye_col, 3.0)
	return d


static func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _mat_emit(c: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(c, 0.15, 0.55)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit != Color(0.0, 0.0, 0.0):
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = energy
	return m


# ==================== 基础甲士 ====================

static func _body(sts: Dictionary, mats: Dictionary, heavy: bool, skip_legs: bool = false) -> void:
	var w := 1.12 if heavy else 1.0
	var lx := 0.105 * w
	# 腿 / 靴（几何单独拆到 LegL/LegR 两段，供行走摆动；skip_legs 时只留躯干）
	if not skip_legs:
		for s in [-1.0, 1.0]:
			_box(sts, mats, "leather", Vector3(0.15 * w, 0.09, 0.25), Vector3(s * lx, 0.045, 0.035))
			_box(sts, mats, "bronze", Vector3(0.15 * w, 0.035, 0.07), Vector3(s * lx, 0.105, 0.135))
			_cyl(sts, mats, "steel", 0.052, 0.062, 0.29, Vector3(s * lx, 0.245, 0.005), 8)
			_sph(sts, mats, "steel", 0.068, Vector3(s * lx, 0.39, 0.005), 8, 4)
			_cyl(sts, mats, "dark", 0.066, 0.074, 0.18, Vector3(s * lx, 0.47, -0.005), 8)
	# 胯 / 腰甲
	_box(sts, mats, "dark", Vector3(0.27 * w, 0.14, 0.19), Vector3(0, 0.56, 0))
	_box(sts, mats, "bronze", Vector3(0.31 * w, 0.055, 0.205), Vector3(0, 0.615, 0))
	_box(sts, mats, "gold", Vector3(0.07, 0.045, 0.025), Vector3(0, 0.615, 0.108))
	# 队伍色内裙
	_box(sts, mats, "cloth", Vector3(0.23 * w, 0.24, 0.02), Vector3(0, 0.47, 0.075))
	# 甲裙板
	for s in [-1.0, 1.0]:
		_box(sts, mats, "steel", Vector3(0.10, 0.215, 0.03), Vector3(s * 0.055, 0.49, 0.105), Vector3(0, 0, s * 6.0))
		_box(sts, mats, "bronze", Vector3(0.085, 0.19, 0.03), Vector3(s * 0.145, 0.48, 0.075), Vector3(0, 0, s * 10.0))
		_box(sts, mats, "dark", Vector3(0.10, 0.20, 0.03), Vector3(s * 0.165, 0.48, -0.015), Vector3(0, s * 72.0, 0))
	# 躯干
	_box(sts, mats, "dark", Vector3(0.26 * w, 0.29, 0.16 * w), Vector3(0, 0.73, 0))
	# 胸前札甲：3 排 5 片
	for row in range(3):
		var y := 0.675 + float(row) * 0.072
		for i in range(5):
			var x := -0.12 + float(i) * 0.06
			var key := "steel" if (row + i) % 2 == 0 else "bronze"
			_box(sts, mats, key, Vector3(0.055, 0.062, 0.024), Vector3(x * w, y, 0.102))
	# 侧肋甲
	for s in [-1.0, 1.0]:
		_box(sts, mats, "steel", Vector3(0.035, 0.20, 0.15), Vector3(s * 0.148 * w, 0.73, 0.02), Vector3(0, s * 22.0, 0))
	# 胸甲上缘 / 护颈
	_box(sts, mats, "steel", Vector3(0.30 * w, 0.08, 0.20), Vector3(0, 0.855, 0))
	_box(sts, mats, "bronze", Vector3(0.20, 0.035, 0.17), Vector3(0, 0.90, 0))
	# 斜挎队伍色绶带 / 领巾（正面也可辨认阵营）
	_box(sts, mats, "cloth", Vector3(0.065, 0.40, 0.022), Vector3(0, 0.73, 0.114), Vector3(0, 0, 24.0))
	_box(sts, mats, "cloth", Vector3(0.21, 0.055, 0.19), Vector3(0, 0.915, 0))
	# 披风
	_box(sts, mats, "cloth", Vector3(0.25 * w, 0.36, 0.02), Vector3(0, 0.72, -0.12), Vector3(5.0, 0, 0))
	_box(sts, mats, "bronze", Vector3(0.25 * w, 0.025, 0.03), Vector3(0, 0.545, -0.12))
	# 肩甲：三层札片
	for s in [-1.0, 1.0]:
		for i in range(3):
			var key := "steel" if i % 2 == 0 else "bronze"
			_box(sts, mats, key, Vector3(0.17 - 0.02 * i, 0.045, 0.20 - 0.02 * i),
				Vector3(s * (0.20 + 0.012 * i) * w, 0.855 - 0.055 * i, 0),
				Vector3(0, 0, -s * (12.0 + 3.0 * i)))
	# 手臂（近战/远程共用肩到肘；小臂由各兵种补）
	for s in [-1.0, 1.0]:
		_limb(sts, mats, "leather", 0.057, 0.052,
			Vector3(s * 0.205 * w, 0.83, 0), Vector3(s * 0.245 * w, 0.68, 0.03), 8)
	# 颈 / 头
	_cyl(sts, mats, "skin", 0.052, 0.060, 0.09, Vector3(0, 0.915, 0), 8)
	_sph(sts, mats, "skin", 0.10, Vector3(0, 1.005, 0.005), 10, 6)
	_box(sts, mats, "skin", Vector3(0.13, 0.10, 0.025), Vector3(0, 1.00, 0.095))
	for s in [-1.0, 1.0]:
		_box(sts, mats, "black", Vector3(0.026, 0.016, 0.012), Vector3(s * 0.032, 1.015, 0.109))
	_box(sts, mats, "skin", Vector3(0.026, 0.032, 0.02), Vector3(0, 0.99, 0.114))
	# 头盔
	_cyl(sts, mats, "steel", 0.135, 0.142, 0.025, Vector3(0, 1.065, 0), 12)
	_cyl(sts, mats, "steel", 0.035, 0.125, 0.16, Vector3(0, 1.145, 0), 12)
	_box(sts, mats, "bronze", Vector3(0.025, 0.10, 0.02), Vector3(0, 1.03, 0.112))
	for s in [-1.0, 1.0]:
		_box(sts, mats, "dark", Vector3(0.03, 0.10, 0.065), Vector3(s * 0.115, 1.00, 0.03))
	_box(sts, mats, "dark", Vector3(0.22, 0.055, 0.10), Vector3(0, 0.955, -0.025))
	_cyl(sts, mats, "gold", 0.018, 0.032, 0.045, Vector3(0, 1.235, 0), 8)
	# 盔缨：扇形队伍色冠饰
	for i in range(3):
		_box(sts, mats, "cloth", Vector3(0.045, 0.18, 0.10), Vector3((i - 1) * 0.045, 1.265, -0.01 - 0.012 * i),
			Vector3(-12.0, (i - 1) * 8.0, 0))
	_box(sts, mats, "cloth", Vector3(0.05, 0.22, 0.045), Vector3(0, 1.22, -0.10), Vector3(-24.0, 0, 0))


# 双腿：以髋关节为原点单独构建（Minion 行走时绕 hips 前后摆动）
static func _build_legs(pivot: Node3D, mats: Dictionary, heavy: bool) -> void:
	var w := 1.12 if heavy else 1.0
	var lx := 0.105 * w
	var hip_y := 0.555
	for s in [-1.0, 1.0]:
		var sts: Dictionary = {}
		var o := Vector3(0, -hip_y, 0)
		_box(sts, mats, "leather", Vector3(0.15 * w, 0.09, 0.25), o + Vector3(0, 0.045, 0.035))
		_box(sts, mats, "bronze", Vector3(0.15 * w, 0.035, 0.07), o + Vector3(0, 0.105, 0.135))
		_cyl(sts, mats, "steel", 0.052, 0.062, 0.29, o + Vector3(0, 0.245, 0.005), 8)
		_sph(sts, mats, "steel", 0.068, o + Vector3(0, 0.39, 0.005), 8, 4)
		_cyl(sts, mats, "dark", 0.066, 0.074, 0.18, o + Vector3(0, 0.47, -0.005), 8)
		var mi := MeshInstance3D.new()
		mi.mesh = _commit(sts, mats)
		var leg := Node3D.new()
		leg.name = "LegL" if s < 0.0 else "LegR"
		leg.position = Vector3(s * lx, hip_y, 0)
		leg.add_child(mi)
		pivot.add_child(leg)

static func _arms_melee(sts: Dictionary, mats: Dictionary) -> void:
	# 左臂圆盾
	for s in [-1.0, 1.0]:
		_limb(sts, mats, "steel", 0.050, 0.045,
			Vector3(s * 0.245, 0.68, 0.03), Vector3(s * 0.245, 0.55, 0.10), 8)
		_sph(sts, mats, "skin", 0.045, Vector3(s * 0.245, 0.545, 0.105), 8, 4)
	var c := Vector3(-0.275, 0.66, 0.13)
	_cyl(sts, mats, "steel", 0.155, 0.16, 0.035, c, 16, Vector3(90, 0, 0))
	_cyl(sts, mats, "bronze", 0.165, 0.17, 0.018, c + Vector3(0, 0, 0.012), 16, Vector3(90, 0, 0))
	_cyl(sts, mats, "gold", 0.045, 0.055, 0.035, c + Vector3(0, 0, 0.035), 10, Vector3(90, 0, 0))
	_box(sts, mats, "cloth", Vector3(0.10, 0.10, 0.018), c + Vector3(0, 0, 0.055))
	# 右手长剑
	var h := Vector3(0.245, 0.545, 0.10)
	_box(sts, mats, "leather", Vector3(0.030, 0.11, 0.030), h + Vector3(0, 0.015, 0))
	_box(sts, mats, "bronze", Vector3(0.145, 0.025, 0.035), h + Vector3(0, 0.075, 0))
	_box(sts, mats, "steel", Vector3(0.044, 0.42, 0.012), h + Vector3(0, 0.295, 0))
	_cyl(sts, mats, "steel", 0.0, 0.030, 0.09, h + Vector3(0, 0.55, 0), 4)
	_sph(sts, mats, "gold", 0.028, h + Vector3(0, -0.045, 0), 8, 4)


static func _arms_bow(sts: Dictionary, mats: Dictionary) -> void:
	# 双臂前伸持弓
	_limb(sts, mats, "steel", 0.048, 0.043,
		Vector3(-0.245, 0.68, 0.03), Vector3(-0.235, 0.70, 0.20), 8)
	_limb(sts, mats, "steel", 0.048, 0.043,
		Vector3(0.245, 0.68, 0.03), Vector3(-0.03, 0.70, 0.19), 8)
	_sph(sts, mats, "skin", 0.045, Vector3(-0.235, 0.70, 0.22), 8, 4)
	_sph(sts, mats, "skin", 0.045, Vector3(-0.02, 0.70, 0.20), 8, 4)
	# 弓身（YZ 平面，稍向前）
	var bx := -0.275
	var p0 := Vector3(bx, 0.44, 0.16)
	var p1 := Vector3(bx, 0.57, 0.26)
	var p2 := Vector3(bx, 0.71, 0.295)
	var p3 := Vector3(bx, 0.85, 0.26)
	var p4 := Vector3(bx, 0.98, 0.16)
	_limb(sts, mats, "wood", 0.020, 0.017, p0, p1, 6)
	_limb(sts, mats, "wood", 0.017, 0.016, p1, p2, 6)
	_limb(sts, mats, "wood", 0.016, 0.017, p2, p3, 6)
	_limb(sts, mats, "wood", 0.017, 0.020, p3, p4, 6)
	_limb(sts, mats, "black", 0.005, 0.005, p0, p4, 4)
	_box(sts, mats, "leather", Vector3(0.035, 0.12, 0.035), p2)
	# 箭
	_limb(sts, mats, "wood", 0.008, 0.008, Vector3(-0.10, 0.71, 0.295), Vector3(0.29, 0.71, 0.295), 4)
	_cyl(sts, mats, "steel", 0.0, 0.022, 0.07, Vector3(0.315, 0.71, 0.295), 4, Vector3(0, 0, -90))
	_box(sts, mats, "cloth", Vector3(0.05, 0.032, 0.012), Vector3(-0.075, 0.71, 0.295))
	# 背后箭袋
	_box(sts, mats, "leather", Vector3(0.085, 0.28, 0.075), Vector3(0.17, 0.78, -0.14), Vector3(-10.0, 0, -14.0))
	for i in range(3):
		var ox := -0.025 + 0.025 * i
		_limb(sts, mats, "wood", 0.007, 0.007, Vector3(0.15 + ox, 0.90, -0.16), Vector3(0.13 + ox, 1.04, -0.18), 4)
		_box(sts, mats, "cloth", Vector3(0.022, 0.055, 0.012), Vector3(0.13 + ox, 1.03, -0.18))
	# 面巾（队伍色）
	_box(sts, mats, "cloth", Vector3(0.15, 0.055, 0.025), Vector3(0, 0.955, 0.108))


static func _arms_halberd(sts: Dictionary, mats: Dictionary) -> void:
	# 重甲双臂
	for s in [-1.0, 1.0]:
		_limb(sts, mats, "steel", 0.062, 0.055,
			Vector3(s * 0.245, 0.68, 0.03), Vector3(s * 0.265, 0.56, 0.08), 8)
		_sph(sts, mats, "skin", 0.050, Vector3(s * 0.265, 0.55, 0.085), 8, 4)
	# 长戟：右手
	var gx := 0.315
	_limb(sts, mats, "wood", 0.024, 0.026, Vector3(gx, 0.10, 0.16), Vector3(gx, 1.55, 0.05), 8)
	_sph(sts, mats, "gold", 0.035, Vector3(gx, 0.54, 0.105), 8, 4)
	_box(sts, mats, "steel", Vector3(0.19, 0.24, 0.035), Vector3(gx + 0.10, 1.25, 0.06), Vector3(0, 0, -0.35))
	_cyl(sts, mats, "steel", 0.0, 0.045, 0.20, Vector3(gx, 1.68, 0.045), 4)
	_box(sts, mats, "bronze", Vector3(0.06, 0.06, 0.06), Vector3(gx, 1.52, 0.05))
	# 左手小圆盾
	var c := Vector3(-0.285, 0.64, 0.13)
	_cyl(sts, mats, "steel", 0.135, 0.14, 0.032, c, 14, Vector3(90, 0, 0))
	_cyl(sts, mats, "bronze", 0.145, 0.15, 0.016, c + Vector3(0, 0, 0.010), 14, Vector3(90, 0, 0))
	_sph(sts, mats, "gold", 0.040, c + Vector3(0, 0, 0.035), 8, 4)


static func _heavy_crest(sts: Dictionary, mats: Dictionary) -> void:
	# 重甲盔角 + 背旗 + 加大披风
	for s in [-1.0, 1.0]:
		_cyl(sts, mats, "bronze", 0.0, 0.035, 0.22, Vector3(s * 0.15, 1.16, 0.01), 6, Vector3(0, 0, s * 60))
		_box(sts, mats, "gold", Vector3(0.09, 0.035, 0.03), Vector3(s * 0.16, 0.94, 0.10))
	_box(sts, mats, "cloth", Vector3(0.34, 0.48, 0.02), Vector3(0, 0.72, -0.145), Vector3(6.0, 0, 0))
	_limb(sts, mats, "wood", 0.016, 0.016, Vector3(-0.28, 0.55, -0.16), Vector3(-0.36, 1.25, -0.16), 6)
	_box(sts, mats, "cloth", Vector3(0.22, 0.16, 0.012), Vector3(-0.44, 1.15, -0.16))
	_cyl(sts, mats, "gold", 0.02, 0.035, 0.05, Vector3(-0.36, 1.28, -0.16), 6)


# ==================== 攻城车（弩车） ====================

static func _siege(sts: Dictionary, mats: Dictionary) -> void:
	# 双大轮
	for s in [-1.0, 1.0]:
		var c := Vector3(s * 0.47, 0.28, 0)
		_cyl(sts, mats, "wood", 0.275, 0.275, 0.075, c, 18, Vector3(0, 0, 90))
		_cyl(sts, mats, "dark", 0.225, 0.225, 0.080, c, 18, Vector3(0, 0, 90))
		for k in range(6):
			_box(sts, mats, "wood", Vector3(0.035, 0.50, 0.035), c, Vector3(float(k) * 30.0, 0, 0))
		_sph(sts, mats, "gold", 0.06, c, 10, 5)
		_cyl(sts, mats, "bronze", 0.295, 0.30, 0.02, c + Vector3(0, 0, 0.035), 18, Vector3(0, 0, 90))
	# 车轴 / 底盘
	_cyl(sts, mats, "dark", 0.045, 0.045, 1.02, Vector3(0, 0.28, 0), 8, Vector3(0, 0, 90))
	_box(sts, mats, "wood", Vector3(0.72, 0.12, 1.02), Vector3(0, 0.42, 0))
	for i in range(4):
		_box(sts, mats, "leather", Vector3(0.72, 0.015, 0.045), Vector3(0, 0.49, -0.38 + 0.25 * i))
	for s in [-1.0, 1.0]:
		_box(sts, mats, "wood", Vector3(0.06, 0.09, 1.02), Vector3(s * 0.36, 0.50, 0))
		_box(sts, mats, "bronze", Vector3(0.08, 0.05, 0.12), Vector3(s * 0.36, 0.52, 0.38))
	# 前挡板
	_box(sts, mats, "bronze", Vector3(0.74, 0.18, 0.05), Vector3(0, 0.50, 0.51), Vector3(-0.20, 0, 0))
	# 弩炮
	_box(sts, mats, "dark", Vector3(0.32, 0.10, 0.34), Vector3(0, 0.53, 0.02))
	_cyl(sts, mats, "bronze", 0.10, 0.12, 0.10, Vector3(0, 0.60, 0.02), 10)
	_box(sts, mats, "wood", Vector3(0.20, 0.09, 0.66), Vector3(0, 0.63, 0.16))
	# 弩弓臂
	for s in [-1.0, 1.0]:
		_limb(sts, mats, "wood", 0.034, 0.026, Vector3(s * 0.10, 0.64, 0.44),
			Vector3(s * 0.37, 0.64, 0.33), 6)
		_cyl(sts, mats, "bronze", 0.045, 0.05, 0.08, Vector3(s * 0.12, 0.64, 0.44), 8)
	_limb(sts, mats, "black", 0.006, 0.006, Vector3(-0.37, 0.64, 0.33), Vector3(0.37, 0.64, 0.33), 4)
	# 巨型弩箭
	_limb(sts, mats, "wood", 0.026, 0.026, Vector3(0, 0.65, 0.05), Vector3(0, 0.65, 0.88), 6)
	_cyl(sts, mats, "steel", 0.0, 0.05, 0.14, Vector3(0, 0.65, 0.94), 4, Vector3(90, 0, 0))
	_box(sts, mats, "cloth", Vector3(0.10, 0.055, 0.012), Vector3(0, 0.65, 0.10))
	# 后部军旗
	_limb(sts, mats, "wood", 0.018, 0.018, Vector3(0.31, 0.46, -0.38), Vector3(0.31, 1.22, -0.38), 6)
	_box(sts, mats, "cloth", Vector3(0.30, 0.19, 0.014), Vector3(0.15, 1.10, -0.38))
	_box(sts, mats, "gold", Vector3(0.30, 0.018, 0.02), Vector3(0.15, 1.005, -0.38))
	_cyl(sts, mats, "gold", 0.018, 0.03, 0.055, Vector3(0.31, 1.25, -0.38), 6)


# ==================== 主宰先锋（龙形） ====================

static func _dragon(sts: Dictionary, mats: Dictionary, kind: String) -> void:
	var big := 1.12 if kind == "shadow_dragon" else 1.0
	# 躯干 / 胸腹
	_sph(sts, mats, "scale", 0.34, Vector3(0, 0.68, 0.02), 12, 6)
	_sph(sts, mats, "scale", 0.30, Vector3(0, 0.70, -0.32), 12, 6)
	_sph(sts, mats, "scale", 0.26, Vector3(0, 0.62, 0.30), 10, 5)
	for i in range(4):
		_box(sts, mats, "bronze", Vector3(0.30 - 0.03 * i, 0.035, 0.18),
			Vector3(0, 0.43 + 0.018 * i, 0.20 - 0.18 * i), Vector3(-10, 0, 0))
	# 脖子 / 头
	var n0 := Vector3(0, 0.82, 0.28)
	var n1 := Vector3(0, 1.04, 0.48)
	var n2 := Vector3(0, 1.18, 0.58)
	_limb(sts, mats, "scale", 0.16, 0.13, n0, n1, 10)
	_limb(sts, mats, "scale", 0.13, 0.105, n1, n2, 10)
	_sph(sts, mats, "scale", 0.17, Vector3(0, 1.20, 0.64), 12, 6)
	_box(sts, mats, "scale", Vector3(0.20, 0.14, 0.26), Vector3(0, 1.16, 0.79))
	_box(sts, mats, "scale", Vector3(0.18, 0.07, 0.22), Vector3(0, 1.08, 0.81))
	_box(sts, mats, "dark", Vector3(0.19, 0.018, 0.21), Vector3(0, 1.115, 0.83))
	# 眼睛 / 眉甲 / 鼻孔
	for s in [-1.0, 1.0]:
		_sph(sts, mats, "eye", 0.028, Vector3(s * 0.078, 1.225, 0.765), 6, 3)
		_box(sts, mats, "bronze", Vector3(0.10, 0.035, 0.08), Vector3(s * 0.085, 1.26, 0.75), Vector3(0, 0, -s * 12.0))
		_box(sts, mats, "black", Vector3(0.022, 0.018, 0.016), Vector3(s * 0.045, 1.16, 0.915))
	# 龙角：两段，暗影更长
	for s in [-1.0, 1.0]:
		var a := Vector3(s * 0.09, 1.27, 0.61)
		var b := Vector3(s * 0.19 * big, 1.43, 0.44)
		var c := Vector3(s * 0.15 * big, 1.56, 0.27)
		_limb(sts, mats, "horn", 0.045, 0.026, a, b, 6)
		_limb(sts, mats, "horn", 0.026, 0.0, b, c, 6)
		_limb(sts, mats, "horn", 0.022, 0.0, Vector3(s * 0.14, 1.22, 0.61), Vector3(s * 0.25, 1.14, 0.49), 5)
	# 头冠膜
	_tri(sts, mats, "membrane", Vector3(0, 1.28, 0.59), Vector3(-0.16, 1.44, 0.41), Vector3(0.16, 1.44, 0.41))
	# 背脊甲片
	for i in range(7):
		var z := -0.58 + 0.18 * i
		var y := 0.98 - absf(z + 0.05) * 0.12
		_box(sts, mats, "horn", Vector3(0.055, 0.12, 0.13), Vector3(0, y, z), Vector3(-18, 0, 0))
	# 鞍具 / 队伍色毯
	_box(sts, mats, "bronze", Vector3(0.42, 0.05, 0.55), Vector3(0, 0.92, -0.10))
	_box(sts, mats, "leather", Vector3(0.38, 0.055, 0.34), Vector3(0, 0.955, -0.16))
	_box(sts, mats, "cloth", Vector3(0.34, 0.035, 0.28), Vector3(0, 0.985, -0.16))
	for s in [-1.0, 1.0]:
		_box(sts, mats, "cloth", Vector3(0.05, 0.30, 0.24), Vector3(s * 0.31, 0.73, -0.10), Vector3(0, 0, s * 6.0))
	# 四肢
	for s in [-1.0, 1.0]:
		for z in [0.28, -0.34]:
			var hip := Vector3(s * 0.23, 0.62, z)
			var knee := Vector3(s * 0.29, 0.34, z + 0.04)
			var ankle := Vector3(s * 0.26, 0.10, z + 0.02)
			_limb(sts, mats, "scale", 0.095, 0.075, hip, knee, 8)
			_limb(sts, mats, "scale", 0.072, 0.055, knee, ankle, 8)
			_box(sts, mats, "scale", Vector3(0.17, 0.09, 0.24), Vector3(s * 0.26, 0.05, z + 0.08))
			for k in range(3):
				_cyl(sts, mats, "horn", 0.012, 0.028, 0.10,
					Vector3(s * 0.26 + (k - 1) * 0.045, 0.035, z + 0.20), 4, Vector3(90, 0, 0))
			_box(sts, mats, "bronze", Vector3(0.13, 0.05, 0.14), knee + Vector3(0, 0, 0.03))
	# 双翼：骨架 + 膜
	for s in [-1.0, 1.0]:
		var shoulder := Vector3(s * 0.24, 0.82, -0.05)
		var elbow := Vector3(s * 0.62 * big, 1.14, -0.18)
		var tip := Vector3(s * 1.10 * big, 0.88, -0.42)
		var inner := Vector3(s * 0.30, 0.70, -0.24)
		var low := Vector3(s * 0.22, 0.55, -0.40)
		_limb(sts, mats, "scale", 0.045, 0.034, shoulder, elbow, 6)
		_limb(sts, mats, "scale", 0.034, 0.022, elbow, tip, 6)
		_limb(sts, mats, "scale", 0.030, 0.018, shoulder, inner, 6)
		_tri(sts, mats, "membrane", shoulder, elbow, tip)
		_tri(sts, mats, "membrane", shoulder, tip, inner)
		_tri(sts, mats, "membrane", shoulder, inner, low)
		# 翼尖爪
		_limb(sts, mats, "horn", 0.022, 0.0, elbow, elbow + Vector3(s * 0.10, 0.10, -0.04), 5)
	# 尾巴
	var t0 := Vector3(0, 0.66, -0.48)
	var t1 := Vector3(0, 0.54, -0.82)
	var t2 := Vector3(0, 0.38, -1.10)
	var t3 := Vector3(0, 0.52, -1.32)
	_limb(sts, mats, "scale", 0.105, 0.075, t0, t1, 8)
	_limb(sts, mats, "scale", 0.075, 0.050, t1, t2, 8)
	_limb(sts, mats, "scale", 0.050, 0.030, t2, t3, 8)
	_box(sts, mats, "horn", Vector3(0.18, 0.035, 0.26), t3 + Vector3(0, 0, -0.10), Vector3(12, 0, 0))
	for i in range(3):
		var p := t1.lerp(t3, 0.28 + 0.26 * i)
		_box(sts, mats, "bronze", Vector3(0.06, 0.10, 0.08), p + Vector3(0, 0.09, 0))




static func _ensure(sts: Dictionary, mats: Dictionary, key: String) -> SurfaceTool:
	if not sts.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mats[key])
		sts[key] = st
	return sts[key]


static func _append(sts: Dictionary, mats: Dictionary, key: String, mesh: Mesh, xf: Transform3D) -> void:
	var st: SurfaceTool = _ensure(sts, mats, key)
	st.append_from(mesh, 0, xf)


static func _box(sts: Dictionary, mats: Dictionary, key: String, size: Vector3, pos: Vector3,
		rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	_append(sts, mats, key, m, Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos))


static func _cyl(sts: Dictionary, mats: Dictionary, key: String, r_top: float, r_bottom: float,
		h: float, pos: Vector3, seg := 10, rot := Vector3.ZERO) -> void:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_append(sts, mats, key, m, Transform3D(Basis.from_euler(rot * (PI / 180.0)), pos))


static func _sph(sts: Dictionary, mats: Dictionary, key: String, r: float, pos: Vector3,
		seg := 8, rings := 5) -> void:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	_append(sts, mats, key, m, Transform3D(Basis.IDENTITY, pos))


static func _limb(sts: Dictionary, mats: Dictionary, key: String, r0: float, r1: float,
		a: Vector3, b: Vector3, seg := 8) -> void:
	var d := b - a
	var h := d.length()
	if h < 0.0001:
		return
	var dir := d / h
	var axis := Vector3.UP.cross(dir)
	var basis: Basis
	if axis.length() < 0.0001:
		basis = Basis.IDENTITY if dir.y > 0.0 else Basis(Vector3.RIGHT, PI)
	else:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	var m := CylinderMesh.new()
	m.top_radius = r1
	m.bottom_radius = r0
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	_append(sts, mats, key, m, Transform3D(basis, (a + b) * 0.5))


static func _tri(sts: Dictionary, mats: Dictionary, key: String,
		a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length() < 0.00001:
		return
	n = n.normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b, c])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_append(sts, mats, key, m, Transform3D.IDENTITY)


static func _commit(sts: Dictionary, mats: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in mats.keys():
		if sts.has(key):
			var st: SurfaceTool = sts[key]
			st.commit(mesh)
	return mesh
