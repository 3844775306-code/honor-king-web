extends RefCounted
## 程序化防御塔模型（替换 model/turret/Turret.glb）：八角石塔 + 队伍色发光刻纹；
## 水晶为十二角基座 + 立柱 + 悬浮晶核。主机与联机客户端共用同一套构建函数。
## 尺寸对齐旧模型：普通塔 ≈2.2 宽 × 3.5 高，水晶 ≈3.0 宽 × 4.2 高（塔口 y≈2.0 / 3.0）。

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")

static var _accent_mats: Dictionary = {}
static var _crystal_mats: Dictionary = {}
static var _shield_shell_mats: Dictionary = {}
static var _shield_edge_mats: Dictionary = {}
static var _base_brick_mat: StandardMaterial3D = null

static func team_color(team: int) -> Color:
	return Color(1.0, 0.32, 0.24) if team == 1 else Color(0.26, 0.58, 1.0)

static func accent_material(team: int) -> StandardMaterial3D:
	if _accent_mats.has(team):
		return _accent_mats[team]
	var c: Color = team_color(team)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * 0.45, c.g * 0.45, c.b * 0.45, 1.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.5
	m.roughness = 0.35
	m.metallic = 0.25
	_accent_mats[team] = m
	return m

static func crystal_material(team: int) -> StandardMaterial3D:
	if _crystal_mats.has(team):
		return _crystal_mats[team]
	var c: Color = team_color(team)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * 0.55, c.g * 0.55, c.b * 0.55, 1.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.4
	m.roughness = 0.12
	m.metallic = 0.15
	_crystal_mats[team] = m
	return m

## 构建一座塔的视觉节点（root 自带 "_fx_team_tint" 标记，阻止 UnitVisuals 二次染色）
## 塔脚青白色地砖（独立材质/网格，塔身仍用原来的岩石色）
static func base_brick_material() -> StandardMaterial3D:
	if _base_brick_mat != null:
		return _base_brick_mat
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.76, 0.92, 0.95)
	m.roughness = 0.82
	m.metallic = 0.04
	_base_brick_mat = m
	return m

const TOWER_MODEL_SCALE := 1.38       # 普通塔模型：基准高3.76m -> 约5.2m
const CRYSTAL_MODEL_SCALE := 3.19     # 水晶模型：基准高3.26m -> 约10.4m，塔:水晶≈1:2


static func model_scale(tier: String) -> float:
	return CRYSTAL_MODEL_SCALE if tier == "crystal" else TOWER_MODEL_SCALE


static func visual(tier: String, team: int) -> Node3D:
	var root := Node3D.new()
	root.name = "TurretVisual"
	root.set_meta("_fx_team_tint", true)
	var base := MeshInstance3D.new()
	base.name = "BaseBricks"
	base.mesh = _build_crystal_base() if tier == "crystal" else _build_tower_base()
	base.material_override = base_brick_material()
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(base)
	var stone := MeshInstance3D.new()
	stone.name = "Stone"
	stone.mesh = _build_crystal_stone() if tier == "crystal" else _build_tower_stone()
	stone.material_override = DecorMesh.rock_material()
	stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(stone)
	if tier == "crystal":
		var pivot := Node3D.new()
		pivot.name = "CrystalPivot"
		pivot.position = Vector3(0.0, 0.0, 0.0)
		root.add_child(pivot)
		var body := MeshInstance3D.new()
		body.name = "Crystal"
		body.mesh = _octa(1.50, 1.55)          # 扁平宽体：半径加大、高度压低
		body.position = Vector3(0.0, 2.45, 0.0)
		body.material_override = crystal_material(team)
		body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		pivot.add_child(body)
		var core := MeshInstance3D.new()
		core.name = "Core"
		core.mesh = _octa(0.78, 0.88)
		core.position = Vector3(0.0, 2.42, 0.0)
		core.material_override = accent_material(team)
		pivot.add_child(core)
		var ring := MeshInstance3D.new()
		ring.name = "Ring"
		ring.mesh = _torus(1.80, 0.06, 28, 6)
		ring.position = Vector3(0.0, 2.18, 0.0)
		ring.material_override = accent_material(team)
		pivot.add_child(ring)
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		halo.mesh = _torus(1.62, 0.08, 28, 6)
		halo.position = Vector3(0.0, 1.95, 0.0)
		halo.material_override = accent_material(team)
		root.add_child(halo)
	else:
		var accent := MeshInstance3D.new()
		accent.name = "Accent"
		accent.mesh = _build_tower_accent()
		accent.material_override = accent_material(team)
		root.add_child(accent)
		# 塔顶晶核：独立 pivot，供 Turret 每帧自转/浮动（与水晶使用同一节点名）
		var tp := Node3D.new()
		tp.name = "CrystalPivot"
		root.add_child(tp)
		var tc := MeshInstance3D.new()
		tc.name = "Core"
		tc.mesh = _octa(0.19, 0.62)
		tc.position = Vector3(0.0, 3.42, 0.0)
		tc.material_override = crystal_material(team)
		tc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		tp.add_child(tc)
		var shard := _octa(0.055, 0.22)
		for i: int in range(3):
			var a: float = TAU * float(i) / 3.0
			var sm := MeshInstance3D.new()
			sm.mesh = shard
			sm.position = Vector3(cos(a) * 0.34, 3.38 + 0.05 * float(i % 2), sin(a) * 0.34)
			sm.material_override = accent_material(team)
			sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tp.add_child(sm)
		var orbit := MeshInstance3D.new()
		orbit.mesh = _torus(0.34, 0.018, 16, 4)
		orbit.position = Vector3(0.0, 3.42, 0.0)
		orbit.rotation.x = deg_to_rad(32.0)
		orbit.material_override = accent_material(team)
		orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tp.add_child(orbit)
	root.scale = Vector3.ONE * model_scale(tier)
	return root

# ==================== 普通塔 ====================

# 塔脚两级台阶 + 地面砖盘（青白色独立网格）
static func _build_tower_base() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_put(st, _cyl(1.02, 1.12, 0.30, 8), Vector3(0.0, 0.15, 0.0))
	_put(st, _cyl(0.96, 1.06, 0.22, 8), Vector3(0.0, 0.40, 0.0))
	st.append_from(_disc(1.22, 0.06, 10), 0, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)))
	return st.commit()

static func _build_tower_stone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 塔身（下粗上细）
	_put(st, _cyl(0.68, 0.84, 1.00, 8), Vector3(0.0, 0.98, 0.0))
	_put(st, _cyl(0.52, 0.66, 0.95, 8), Vector3(0.0, 2.02, 0.0))
	# 四根竖向石肋（凿刻感）
	var rib := BoxMesh.new()
	rib.size = Vector3(0.13, 2.30, 0.15)
	for i: int in range(4):
		var a: float = TAU * float(i) / 4.0 + PI / 4.0
		var b := Basis(Vector3.UP, a)
		st.append_from(rib, 0, Transform3D(b, Vector3(cos(a) * 0.74, 1.42, sin(a) * 0.74)))
	# 塔顶平台 + 雉堞
	_put(st, _cyl(0.82, 0.58, 0.28, 8), Vector3(0.0, 2.74, 0.0))
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.22, 0.26, 0.16)
	for i: int in range(8):
		var a2: float = TAU * float(i) / 8.0
		var b2 := Basis(Vector3.UP, -a2)
		st.append_from(merlon, 0, Transform3D(b2, Vector3(cos(a2) * 0.66, 3.00, sin(a2) * 0.66)))
	# 塔顶收分 + 基座碎石
	_put(st, _cyl(0.26, 0.46, 0.22, 8), Vector3(0.0, 3.14, 0.0))
	var rock := _rock()
	for i: int in range(5):
		var a3: float = TAU * float(i) / 5.0 + 0.7
		var rr: float = 0.11 + 0.05 * fmod(float(i) * 0.37, 1.0)
		st.append_from(rock, 0, Transform3D(Basis().scaled(Vector3(rr, rr * 0.7, rr)),
			Vector3(cos(a3) * 1.16, rr * 0.5, sin(a3) * 1.16)))
	return st.commit()

static func _build_tower_accent() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 两道发光石带（塔顶晶核已拆成 CrystalPivot，见 visual）
	_put(st, _cyl(0.73, 0.73, 0.10, 8), Vector3(0.0, 1.52, 0.0))
	_put(st, _cyl(0.57, 0.57, 0.09, 8), Vector3(0.0, 2.52, 0.0))
	return st.commit()

# ==================== 水晶 ====================

# 水晶塔脚三级基座 + 地面砖盘（青白色独立网格）
static func _build_crystal_base() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_put(st, _cyl(1.24, 1.36, 0.40, 12), Vector3(0.0, 0.20, 0.0))
	_put(st, _cyl(1.06, 1.16, 0.26, 12), Vector3(0.0, 0.53, 0.0))
	_put(st, _cyl(1.04, 1.14, 0.55, 12), Vector3(0.0, 0.94, 0.0))
	st.append_from(_disc(1.54, 0.07, 12), 0, Transform3D(Basis(), Vector3(0.0, 0.035, 0.0)))
	return st.commit()

static func _build_crystal_stone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 六根立柱
	var pillar := BoxMesh.new()
	pillar.size = Vector3(0.20, 1.15, 0.20)
	for i: int in range(6):
		var a: float = TAU * float(i) / 6.0 + PI / 6.0
		var b := Basis(Vector3.UP, -a)
		st.append_from(pillar, 0, Transform3D(b, Vector3(cos(a) * 0.93, 1.78, sin(a) * 0.93)))
	# 中央石座
	_put(st, _cyl(0.40, 0.64, 0.45, 8), Vector3(0.0, 1.38, 0.0))
	# 基座碎石
	var rock := _rock()
	for i: int in range(6):
		var a2: float = TAU * float(i) / 6.0 + 0.4
		var rr: float = 0.12 + 0.05 * fmod(float(i) * 0.41, 1.0)
		st.append_from(rock, 0, Transform3D(Basis().scaled(Vector3(rr, rr * 0.7, rr)),
			Vector3(cos(a2) * 1.44, rr * 0.5, sin(a2) * 1.44)))
	return st.commit()

# ==================== 防御塔护盾 ====================

## 塔盾实物模型：半透明晶面罩 + 发光棱骨/环带 + 顶部晶核。
## crystal=true 时尺寸覆盖水晶，否则覆盖普通防御塔。
static func tower_shield_visual(team: int, crystal: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "TowerShield"
	root.set_meta("_fx_team_tint", true)
	var radius: float = 2.12 if crystal else 1.55
	var height: float = 3.95 if crystal else 3.85
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = _build_shield_shell(radius, height)
	shell.material_override = shield_shell_material(team)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	frame.mesh = _build_shield_frame(radius, height)
	frame.material_override = shield_edge_material(team)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(frame)
	var apex := MeshInstance3D.new()
	apex.name = "Apex"
	apex.mesh = _octa(radius * 0.20, height * 0.15)
	apex.position = Vector3(0.0, height * 0.99, 0.0)
	apex.material_override = crystal_material(team)
	apex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(apex)
	return root


static func shield_shell_material(team: int) -> StandardMaterial3D:
	if _shield_shell_mats.has(team):
		return _shield_shell_mats[team]
	var c: Color = team_color(team)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.11)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	_shield_shell_mats[team] = m
	return m


static func shield_edge_material(team: int) -> StandardMaterial3D:
	if _shield_edge_mats.has(team):
		return _shield_edge_mats[team]
	var c: Color = team_color(team)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.2
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_edge_mats[team] = m
	return m


static func _build_shield_shell(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg: int = 12
	var levels: Array = [
		[0.10, radius],
		[height * 0.53, radius * 1.02],
		[height * 0.79, radius * 0.70],
		[height * 0.95, radius * 0.24],
	]
	for li in range(levels.size() - 1):
		var y0: float = float(levels[li][0])
		var r0: float = float(levels[li][1])
		var y1: float = float(levels[li + 1][0])
		var r1: float = float(levels[li + 1][1])
		for i in range(seg):
			var a0: float = TAU * float(i) / float(seg)
			var a1: float = TAU * float(i + 1) / float(seg)
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			st.add_vertex(p00); st.add_vertex(p10); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p01)
	# 顶端收成晶尖（底部留空，直接从塔基套上去）
	var top_y: float = float(levels[-1][0])
	var top_r: float = float(levels[-1][1])
	var apex := Vector3(0.0, height, 0.0)
	for i in range(seg):
		var a0b: float = TAU * float(i) / float(seg)
		var a1b: float = TAU * float(i + 1) / float(seg)
		var q0 := Vector3(cos(a0b) * top_r, top_y, sin(a0b) * top_r)
		var q1 := Vector3(cos(a1b) * top_r, top_y, sin(a1b) * top_r)
		st.add_vertex(q0); st.add_vertex(apex); st.add_vertex(q1)
	st.generate_normals()
	return st.commit()


static func _build_shield_frame(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg: int = 12
	var levels: Array = [
		[0.10, radius],
		[height * 0.53, radius * 1.02],
		[height * 0.79, radius * 0.70],
		[height * 0.95, radius * 0.24],
	]
	# 横向能量环
	for lv in levels:
		var y: float = float(lv[0])
		var r: float = float(lv[1])
		st.append_from(_torus(r, 0.025, 24, 4), 0, Transform3D(Basis(), Vector3(0.0, y, 0.0)))
	# 纵向棱骨
	var strut := CylinderMesh.new()
	strut.top_radius = 0.021
	strut.bottom_radius = 0.021
	strut.height = 1.0
	strut.radial_segments = 4
	strut.rings = 1
	for li in range(levels.size() - 1):
		var y0: float = float(levels[li][0])
		var r0: float = float(levels[li][1])
		var y1: float = float(levels[li + 1][0])
		var r1: float = float(levels[li + 1][1])
		for i in range(seg):
			var a: float = TAU * float(i) / float(seg)
			_append_strut(st, strut,
				Vector3(cos(a) * r0, y0, sin(a) * r0),
				Vector3(cos(a) * r1, y1, sin(a) * r1))
	var top_y: float = float(levels[-1][0])
	var top_r: float = float(levels[-1][1])
	var apex := Vector3(0.0, height, 0.0)
	for i in range(seg):
		var a2: float = TAU * float(i) / float(seg)
		_append_strut(st, strut, Vector3(cos(a2) * top_r, top_y, sin(a2) * top_r), apex)
	# 环带上的小晶片，让透明罩有实体细节
	var shard := _octa(0.075, 0.26)
	for i in range(6):
		var a3: float = TAU * float(i) / 6.0 + 0.25
		var y3: float = height * 0.60
		var rr: float = radius * 1.0
		st.append_from(shard, 0, Transform3D(
			Basis(Vector3.UP, a3).scaled(Vector3(1.0, 1.0, 1.0)),
			Vector3(cos(a3) * rr, y3, sin(a3) * rr)))
	return st.commit()


static func _append_strut(st: SurfaceTool, template: Mesh, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var q := Quaternion(Vector3.UP, d / l)
	var basis := Basis(q).scaled(Vector3(1.0, l, 1.0))
	st.append_from(template, 0, Transform3D(basis, (a + b) * 0.5))


# ==================== 基础网格工具 ====================

static func _put(st: SurfaceTool, mesh: Mesh, pos: Vector3) -> void:
	st.append_from(mesh, 0, Transform3D(Basis(), pos))

static func _cyl(top_r: float, bottom_r: float, height: float, segs: int) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = segs
	return cm

static func _disc(radius: float, height: float, segs: int) -> CylinderMesh:
	return _cyl(radius, radius * 1.06, height, segs)

static func _torus(inner_r: float, tube: float, rings: int, segs: int) -> TorusMesh:
	var tm := TorusMesh.new()
	tm.inner_radius = inner_r
	tm.outer_radius = inner_r + tube * 2.0
	tm.rings = rings
	tm.ring_segments = segs
	return tm

static func _sphere(radius: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	return sm

static func _rock() -> SphereMesh:
	var rm := SphereMesh.new()
	rm.radius = 1.0
	rm.height = 2.0
	rm.radial_segments = 5
	rm.rings = 3
	return rm

## 八面体（晶核）：半径 r、总高 h，平面着色
static func _octa(r: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0.0, h * 0.5, 0.0)
	var bot := Vector3(0.0, -h * 0.5, 0.0)
	var ring: Array[Vector3] = [
		Vector3(r, 0.0, 0.0), Vector3(0.0, 0.0, r), Vector3(-r, 0.0, 0.0), Vector3(0.0, 0.0, -r)
	]
	for i: int in range(4):
		var p1: Vector3 = ring[i]
		var p2: Vector3 = ring[(i + 1) % 4]
		st.add_vertex(top)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(bot)
		st.add_vertex(p2)
		st.add_vertex(p1)
	st.generate_normals()
	return st.commit()
