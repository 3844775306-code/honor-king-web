class_name MeshFactory
extends RefCounted
# 网格工厂 — 创建常用视觉网格的静态工具方法
# 减少在 Hero.gd 和 HeroPassive.gd 中重复的 TorusMesh/SphereMesh + StandardMaterial3D 样板代码

const BUFF_AURA_SHADER := preload("res://assets/shaders/buff_aura.gdshader")
const CAST_RANGE_SHADER := preload("res://assets/shaders/cast_range.gdshader")
const CAST_AREA_SHADER := preload("res://assets/shaders/cast_area.gdshader")
const CAST_LINE_SHADER := preload("res://assets/shaders/cast_line.gdshader")
const TELEPORT_PORTAL_SHADER := preload("res://assets/shaders/teleport_portal.gdshader")
const EXP_ORB_SHADER := preload("res://assets/shaders/exp_orb.gdshader")

# 发光能量球（防御塔激光弹体）：核心亮球 + 两层加色光晕，观感比单球亮很多
static func create_energy_orb(radius: float, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "EnergyOrb"
	var core := create_sphere(radius, color, false)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 1.0, 0.94)
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = cmat
	root.add_child(core)
	for i in range(2):
		var g := create_sphere(radius * (1.9 if i == 0 else 3.1), color, false)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(color.r, color.g, color.b, 0.55 if i == 0 else 0.25)
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		g.material_override = gm
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
	root.set_meta("orb_core", core)
	return root

# 经验球：亮核 + 双层菲涅尔光晕，飞行时外层能量带持续流动
static func create_exp_orb(radius: float = 0.16) -> Node3D:
	var root := Node3D.new()
	root.name = "ExpOrb"
	var core := create_sphere(radius * 0.55, Color(0.82, 1.0, 0.88), false)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.86, 1.0, 0.90)
	cmat.emission_enabled = true
	cmat.emission = Color(0.35, 1.0, 0.45)
	cmat.emission_energy_multiplier = 2.4
	core.material_override = cmat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(core)
	for i in range(2):
		var halo := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = radius * (2.1 if i == 0 else 3.9)
		sm.height = sm.radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		halo.mesh = sm
		var mat := ShaderMaterial.new()
		mat.shader = EXP_ORB_SHADER
		mat.set_shader_parameter("orb_color", Color(0.16, 1.0, 0.38))
		mat.set_shader_parameter("core_color", Color(0.80, 1.0, 0.86))
		mat.set_shader_parameter("intensity", 0.85 if i == 0 else 0.34)
		halo.material_override = mat
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		halo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(halo)
	root.set_meta("orb_core", core)
	return root

# 传送阵：地面漩涡符文贴花 + 三层倾斜旋转能量环（返回 rings 供 TeleportZone 做缓慢转动）
static func create_teleport_portal(radius: float = 4.0) -> Node3D:
	var root := Node3D.new()
	root.name = "TeleportPortal"
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = TELEPORT_PORTAL_SHADER
	mat.set_shader_parameter("portal_color", Color(0.20, 0.55, 1.0))
	mat.set_shader_parameter("accent_color", Color(0.55, 0.95, 1.0))
	mi.material_override = mat
	mi.position.y = 0.03
	mi.scale = Vector3(1.04, 1.0, 1.04)   # 外环视觉半径对齐碰撞半径 4.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)

	var rings: Array = []
	var base_ys: Array = []
	var tints: Array = [Color(0.35, 0.82, 1.0), Color(0.62, 0.95, 1.0), Color(0.34, 0.70, 1.0)]
	for i in range(3):
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var rad := radius * (0.93 - 0.13 * i)
		torus.inner_radius = rad - 0.045
		torus.outer_radius = rad + 0.045
		torus.rings = 32
		torus.ring_segments = 8
		ring.mesh = torus
		var rm := StandardMaterial3D.new()
		var col: Color = tints[i]
		rm.albedo_color = Color(col.r, col.g, col.b, 0.42)
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		rm.emission_enabled = true
		rm.emission = col
		rm.emission_energy_multiplier = 1.8
		ring.material_override = rm
		ring.position.y = 0.36 + 0.52 * i
		ring.rotation = Vector3(0.42 - 0.18 * i, 0.35 * i, 0.24 - 0.20 * i)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(ring)
		rings.append(ring)
		base_ys.append(ring.position.y)
	root.set_meta("rings", rings)
	root.set_meta("ring_base_y", base_ys)
	return root

# 创建水平放置的圆环
static func create_torus_ring(inner_radius: float, outer_radius: float, color: Color, unshaded: bool = false, alpha: float = 1.0, emissive: bool = false) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = inner_radius
	torus.outer_radius = outer_radius
	# 特效环不需要高模：默认 64×32 太贵，统一压到低模
	torus.rings = 24
	torus.ring_segments = 8
	mi.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if alpha < 1.0:
		mat.albedo_color.a = alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
	mi.material_override = mat
	return mi

# 红/蓝 Buff 拥有者地面光环（着色器动画：旋转符文 + 元素流动，additive 发光）
static func create_buff_aura(mode: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.8, 4.8)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = BUFF_AURA_SHADER
	if mode == 1:
		mat.set_shader_parameter("mode", 1.0)
		mat.set_shader_parameter("ring_radius", 0.52)
		mat.set_shader_parameter("aura_color", Color(0.10, 0.42, 1.0))
		mat.set_shader_parameter("core_color", Color(0.55, 0.88, 1.0))
	else:
		mat.set_shader_parameter("mode", 0.0)
		mat.set_shader_parameter("ring_radius", 0.72)
		mat.set_shader_parameter("aura_color", Color(1.0, 0.22, 0.04))
		mat.set_shader_parameter("core_color", Color(1.0, 0.72, 0.20))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _cast_material(shader: Shader, color: Color, mode: float = -1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("hot", color.lerp(Color(1, 1, 1, 1), 0.45))
	if mode >= 0.0:
		mat.set_shader_parameter("mode", mode)
	return mat

# ==================== 地面范围圈（贴地着色器） ====================
# 与地面 shader 共用同一套野区起伏位移 → 圈随地形起伏，柔化边缘 + 磨损斑驳；
# 塔攻击范围 / 玩家攻击范围 / 野怪活动范围统一用这个，别再用纯 TorusMesh。
static var _ground_ring_shader: Shader = null

static func ground_ring_material(color: Color, dash_count: float = 72.0, fill_alpha: float = 0.06) -> ShaderMaterial:
	if _ground_ring_shader == null:
		_ground_ring_shader = load("res://shaders/fx_ground_ring.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _ground_ring_shader
	m.set_shader_parameter("ring_color", color)
	m.set_shader_parameter("dash_count", dash_count)
	m.set_shader_parameter("fill_alpha", fill_alpha)
	m.set_shader_parameter("bump_amount", 0.28)
	return m

# radius=世界半径（XZ 缩放实现，Y 不缩放以免起伏位移被拉伸）
static func create_ground_ring(radius: float, color: Color, dash_count: float = 72.0, subdiv: int = 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)   # 半径 1，由节点缩放决定实际半径
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	mi.mesh = plane
	mi.material_override = ground_ring_material(color, dash_count)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1.0, radius)
	# 分路平面在 y=0.14，圈必须压在它上方，否则会被路面完全盖住（表现为“圈看不见”）
	mi.position = Vector3(0.0, 0.17, 0.0)
	return mi

static func set_ground_ring_color(mi: MeshInstance3D, color: Color) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var m = mi.material_override
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter("ring_color", color)
	elif m is StandardMaterial3D:
		(m as StandardMaterial3D).albedo_color = color

# 施法范围环：双层亮度弧 + 刻度虚线 + 流转符文（水平面片，半径 1）
static func create_cast_range(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	mi.material_override = _cast_material(CAST_RANGE_SHADER, color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

# 施法落点：mode=0 范围填充 / mode=1 目标准星（水平面片，半径 1）
static func create_cast_area(color: Color, mode: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	mi.material_override = _cast_material(CAST_AREA_SHADER, color, float(mode))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

static func set_cast_area_mode(mi: MeshInstance3D, mode: int) -> void:
	if mi == null:
		return
	var mat := mi.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("mode", float(mode))

# 技能预览配色跟随英雄元素（火橙/冰蓝/暗影紫…），外套与内部高光一起改
static func set_cast_preview_color(mi: MeshInstance3D, color: Color) -> void:
	if mi == null:
		return
	var mat := mi.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("tint", color)
		mat.set_shader_parameter("hot", color.lerp(Color(1, 1, 1, 1), 0.45))

# 线性/位移预览能量带：单位面片，调用方 scale.x=宽度、scale.z=长度
static func create_cast_line(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	mi.mesh = pm
	mi.material_override = _cast_material(CAST_LINE_SHADER, color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

# 线性/位移终点准星（水平面片，半径 1.25）
static func create_cast_reticle(color: Color) -> MeshInstance3D:
	var mi := create_cast_area(color, 1)
	mi.scale = Vector3(1.25, 1.0, 1.25)
	return mi

# 创建球体
static func create_sphere(radius: float, color: Color, emissive: bool = false, alpha: float = 1.0) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	mi.mesh.radius = radius
	mi.mesh.height = radius * 2.0
	mi.mesh.radial_segments = 10
	mi.mesh.rings = 5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if alpha < 1.0:
		mat.albedo_color.a = alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
	mi.material_override = mat
	return mi

# 创建圆柱体（默认垂直放置，适合方向指示器）
static func create_cylinder(top_radius: float, bottom_radius: float, height: float, color: Color, alpha: float = 1.0) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = top_radius
	cyl.bottom_radius = bottom_radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 1
	mi.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	if alpha < 1.0:
		mat.albedo_color.a = alpha
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi

# ============ 刀刃类网格（李元芳飞镖 / 飞轮） ============
# 约定：刀面躺在 XY 平面，+Z 为刀面法线；每片刃都是封闭薄壳（正反面 + 侧壁），
# 因此无论从哪个角度看都是实心金属刀刃，而不是纸片三角。

## 十字飞镖（手里剑）：N 片后掠三角刃 + 中心轮毂
static func build_shuriken(blades: int, r_in: float, r_out: float, thickness: float,
		sweep_deg: float = 24.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := maxf(thickness, 0.006) * 0.5
	var hub := clampf(r_in, 0.01, r_out * 0.6)
	var n := maxi(blades, 3)
	var sweep := deg_to_rad(sweep_deg)
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var half_w := TAU / float(n) * 0.42
		var p_in_l := Vector2(cos(a - half_w), sin(a - half_w)) * hub
		var p_in_r := Vector2(cos(a + half_w), sin(a + half_w)) * hub
		var p_tip := Vector2(cos(a + sweep), sin(a + sweep)) * r_out
		_prism(st, p_in_l, p_in_r, p_tip, half)
		# 刃根小三角，收出「磨出的刃口」层次
		var p_mid := Vector2(cos(a), sin(a)) * (hub + (r_out - hub) * 0.45)
		_prism(st, p_in_l, p_in_r, p_mid, half * 1.15)
	st.generate_normals()
	st.index()
	return st.commit()

## 锯齿刃轮：环形刀盘（外缘锯齿）+ N 片外扩巨刃
static func build_saw_wheel(r_in: float, r_out: float, thickness: float, teeth: int = 24,
		tooth_depth: float = 0.12, big_blades: int = 4, blade_len: float = 0.55) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := maxf(thickness, 0.006) * 0.5
	var n := maxi(teeth, 8)
	# 刀盘：锯齿外缘的环带，每段都是实心柱状块
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var ro0 := r_out if i % 2 == 0 else r_out - tooth_depth
		var ro1 := r_out if (i + 1) % 2 == 0 else r_out - tooth_depth
		var i0 := Vector2(cos(a0), sin(a0)) * r_in
		var i1 := Vector2(cos(a1), sin(a1)) * r_in
		var o0 := Vector2(cos(a0), sin(a0)) * ro0
		var o1 := Vector2(cos(a1), sin(a1)) * ro1
		_prism(st, i0, i1, o0, half)
		_prism(st, i1, o1, o0, half)
	# 外扩巨刃
	var nb := maxi(big_blades, 0)
	for i in range(nb):
		var a := TAU * float(i) / float(maxi(nb, 1)) + TAU * 0.125
		var half_w := TAU / float(maxi(nb, 1)) * 0.15
		var base_l := Vector2(cos(a - half_w), sin(a - half_w)) * (r_out - tooth_depth)
		var base_r := Vector2(cos(a + half_w), sin(a + half_w)) * (r_out - tooth_depth)
		var tip := Vector2(cos(a + 0.12), sin(a + 0.12)) * (r_out + blade_len)
		_prism(st, base_l, base_r, tip, half)
	st.generate_normals()
	st.index()
	return st.commit()

## 三角刃实体：正反两片 + 三条侧壁，做成封闭薄壳
static func _prism(st: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, half: float) -> void:
	var a0 := Vector3(a.x, a.y, half)
	var b0 := Vector3(b.x, b.y, half)
	var c0 := Vector3(c.x, c.y, half)
	var a1 := Vector3(a.x, a.y, -half)
	var b1 := Vector3(b.x, b.y, -half)
	var c1 := Vector3(c.x, c.y, -half)
	# 正反刀面
	_tri(st, a0, b0, c0)
	_tri(st, a1, c1, b1)
	# 侧壁
	_tri(st, a0, b1, b0); _tri(st, a0, a1, b1)
	_tri(st, b0, c1, c0); _tri(st, b0, b1, c1)
	_tri(st, c0, a1, a0); _tri(st, c0, c1, a1)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

## 刀身金属材质（写实向：高金属度 + 低粗糙 + 热刃自发光 + 边缘光）
static func blade_metal(color: Color, edge: Color, roughness: float = 0.26) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.95
	mat.metallic_specular = 0.85
	mat.roughness = roughness
	mat.emission_enabled = true
	mat.emission = edge
	mat.emission_energy_multiplier = 0.55
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.7
	return mat


# ============ 齿轮 / 机甲件（刘禅机关类技能复用） ============
## 真齿轮网格：环形齿盘（可选中心孔）+ 梯形齿，XY 平面、+Z 为盘面法线
static func build_gear(radius: float, thickness: float, teeth: int = 16, tooth_h: float = 0.18,
		hole_r: float = 0.0, seg_per_tooth: int = 4) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := maxf(thickness, 0.006) * 0.5
	var n: int = maxi(teeth, 6) * maxi(seg_per_tooth, 2)
	var inner: float = clampf(hole_r, 0.0, radius * 0.85)
	# 每齿 4 段：齿根 - 齿升 - 齿顶 - 齿降，形成方梯形齿而不是圆锯
	var profile := [0.0, 0.62, 1.0, 0.62]
	for i in range(n):
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var k0: float = profile[i % profile.size()]
		var k1: float = profile[(i + 1) % profile.size()]
		var o0 := radius + tooth_h * k0
		var o1 := radius + tooth_h * k1
		var i0 := Vector2(cos(a0), sin(a0)) * inner
		var i1 := Vector2(cos(a1), sin(a1)) * inner
		var p0 := Vector2(cos(a0), sin(a0)) * o0
		var p1 := Vector2(cos(a1), sin(a1)) * o1
		_ring_solid(st, i0, i1, p0, p1, half)
	st.generate_normals()
	st.index()
	return st.commit()

static func _ring_solid(st: SurfaceTool, i0: Vector2, i1: Vector2, o0: Vector2, o1: Vector2, half: float) -> void:
	# 环带实体：上下两片 + 内外两圈侧壁
	_tri(st, Vector3(i0.x, i0.y, half), Vector3(o0.x, o0.y, half), Vector3(o1.x, o1.y, half))
	_tri(st, Vector3(i0.x, i0.y, half), Vector3(o1.x, o1.y, half), Vector3(i1.x, i1.y, half))
	_tri(st, Vector3(i0.x, i0.y, -half), Vector3(o1.x, o1.y, -half), Vector3(o0.x, o0.y, -half))
	_tri(st, Vector3(i0.x, i0.y, -half), Vector3(i1.x, i1.y, -half), Vector3(o1.x, o1.y, -half))
	# 外壁
	_tri(st, Vector3(o0.x, o0.y, half), Vector3(o0.x, o0.y, -half), Vector3(o1.x, o1.y, -half))
	_tri(st, Vector3(o0.x, o0.y, half), Vector3(o1.x, o1.y, -half), Vector3(o1.x, o1.y, half))
	# 内壁（反向）
	_tri(st, Vector3(i0.x, i0.y, half), Vector3(i1.x, i1.y, half), Vector3(i1.x, i1.y, -half))
	_tri(st, Vector3(i0.x, i0.y, half), Vector3(i1.x, i1.y, -half), Vector3(i0.x, i0.y, -half))

## 机甲金属材质：PBR 金属 + 边缘高光 + 可选的接缝自发光
static func metal_pbr(color: Color, roughness: float = 0.32, glow: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.9
	mat.metallic_specular = 0.75
	mat.roughness = roughness
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.5
	if glow.a > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 1.4
	return mat
