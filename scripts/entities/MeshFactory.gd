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
