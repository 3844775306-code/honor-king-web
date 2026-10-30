class_name MeshFactory
extends RefCounted
# 网格工厂 — 创建常用视觉网格的静态工具方法
# 减少在 Hero.gd 和 HeroPassive.gd 中重复的 TorusMesh/SphereMesh + StandardMaterial3D 样板代码

const BUFF_AURA_SHADER := preload("res://assets/shaders/buff_aura.gdshader")

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
