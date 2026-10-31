class_name HealthPack
extends Area3D

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const ORB_Y := 0.74

## 血包（真实 3D 模型）：三层风化石台 + 石刻十字符文 + 玻璃药球（内含药液核心与晶片）
## + 绿色点光 + 地面光斑 + 上浮粒子，并保留原有「灰色外环 + 绿色回复进度弧」与全部逻辑。
var team: int = 0
var respawn_time: float = 75.0
var cooldown_timer: float = 0.0
var available: bool = true
var turret: Turret = null
var col: CollisionShape3D
var ring_grey: MeshInstance3D
var ring_green: MeshInstance3D
var mesh: MeshInstance3D          # 药球（可用性切换沿用此字段）

var _glow: MeshInstance3D         # 外层光晕
var _cross_h: MeshInstance3D      # 石刻十字横
var _cross_v: MeshInstance3D      # 石刻十字竖
var _ground: MeshInstance3D       # 地面光斑
var _spark: CPUParticles3D        # 上浮粒子
var _shell: MeshInstance3D        # 玻璃外壳
var _shard_root: Node3D           # 药液核心晶片组
var _light: OmniLight3D           # 绿色药光
var _t: float = 0.0               # 本地动画时钟

func _ready():
	add_to_group("health_packs")
	_create_visual()
	body_entered.connect(_on_body_entered)

func _create_visual():
	# —— 三层风化石台：底石、收腰石、顶盖，逐层收分，像被长期踩踏磨圆的古迹 ——
	var stone := DecorMesh.rock_material()
	_add_cylinder(Vector3(0, 0.055, 0), 0.78, 0.84, 0.11, 12, stone)
	_add_cylinder(Vector3(0, 0.155, 0), 0.60, 0.66, 0.09, 12, stone)
	_add_cylinder(Vector3(0, 0.245, 0), 0.48, 0.53, 0.09, 12, stone)
	# 顶面深色药池凹槽 + 铜色包边，让石台有“容器”结构
	_add_cylinder(Vector3(0, 0.296, 0), 0.43, 0.45, 0.018, 12,
		_mat(Color(0.075, 0.13, 0.085), 0.88, 0.05))
	var band := _add_torus(0.475, 0.505, 0.032, Vector3(0, 0.286, 0),
		_mat(Color(0.46, 0.34, 0.16), 0.42, 0.72))
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 石缝苔藓与边缘碎石
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		var moss := _add_sphere(Vector3(cos(a) * 0.64, 0.105, sin(a) * 0.64),
			Vector3(0.19, 0.045, 0.13), _mat(Color(0.085, 0.17, 0.075), 0.95, 0.0))
		moss.rotation.y = a
		moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# —— 石刻十字符文：嵌在顶面，不再悬浮在球体外 ——
	_cross_h = _make_rune_bar(Vector3(0.46, 0.016, 0.068))
	_cross_v = _make_rune_bar(Vector3(0.068, 0.016, 0.46))
	_cross_h.position.y = 0.309
	_cross_v.position.y = 0.309

	# —— 玻璃药球外壳：低透明度、低粗糙度，保留内部药液的通透感 ——
	_shell = _add_sphere(Vector3(0, ORB_Y, 0), Vector3.ONE * 0.285,
		_glass_mat(Color(0.48, 1.0, 0.66, 0.24)), 24, 14)

	# 内部药液核心（真实发光体），mesh 字段继续作为可用性开关
	mesh = _add_sphere(Vector3(0, ORB_Y, 0), Vector3.ONE * 0.165,
		_glow_mat(Color(0.18, 0.98, 0.45), 2.2, 0.94), 20, 12)
	# 药液中的晶片：三片细长棱晶，缓慢旋转，像被搅动的药性结晶
	_shard_root = Node3D.new()
	_shard_root.position.y = ORB_Y
	add_child(_shard_root)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.07, 0.22, 0.07)
		shard.mesh = prism
		shard.position = Vector3(cos(a) * 0.095, 0.015, sin(a) * 0.095)
		shard.rotation = Vector3(0.22, a, 0.18)
		shard.material_override = _glow_mat(Color(0.62, 1.0, 0.75), 3.0, 0.92)
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_shard_root.add_child(shard)

	# —— 外层柔光晕（加色混合，比原版更薄，避免糊成一团）——
	_glow = _add_sphere(Vector3(0, ORB_Y, 0), Vector3.ONE * 0.40,
		_mat(Color.WHITE, 1.0, 0.0), 20, 10)
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(0.25, 1.0, 0.55, 0.12)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.material_override = gmat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# —— 绿色药光：真正照亮石台边缘与附近地面 ——
	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 1.0, 0.55)
	_light.light_energy = 1.35
	_light.omni_range = 5.5
	_light.omni_attenuation = 1.6
	_light.shadow_enabled = false
	_light.position.y = ORB_Y
	add_child(_light)

	# —— 地面光斑（远景也能看出这里有补给）——
	_ground = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.3, 2.3)
	_ground.mesh = qm
	_ground.rotation_degrees = Vector3(-90, 0, 0)
	_ground.position.y = 0.03
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qmat.albedo_color = Color(0.18, 0.85, 0.36, 0.13)
	qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground.material_override = qmat
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)

	# —— 上浮药尘：少量绿色 + 金色微光，围在药球周围 ——
	_spark = CPUParticles3D.new()
	_spark.amount = 16
	_spark.lifetime = 1.8
	_spark.position.y = 0.42
	_spark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spark.emission_sphere_radius = 0.34
	_spark.direction = Vector3(0, 1, 0)
	_spark.spread = 22.0
	_spark.initial_velocity_min = 0.16
	_spark.initial_velocity_max = 0.40
	_spark.gravity = Vector3(0, 0.32, 0)
	_spark.scale_amount_min = 0.018
	_spark.scale_amount_max = 0.05
	_spark.color = Color(0.55, 1.0, 0.68, 0.85)
	add_child(_spark)

	# —— 灰色底座圆环（原表现保留，压暗更像石刻）——
	ring_grey = MeshInstance3D.new()
	var torus_grey = TorusMesh.new()
	torus_grey.inner_radius = 0.9
	torus_grey.outer_radius = 1.0
	torus_grey.rings = 64
	ring_grey.mesh = torus_grey
	ring_grey.position.y = 0.06
	var mat_grey = StandardMaterial3D.new()
	mat_grey.albedo_color = Color(0.42, 0.44, 0.46, 0.9)
	mat_grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_grey.material_override = mat_grey
	ring_grey.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_grey)

	# —— 绿色回复进度弧（动态生成，逻辑不变）——
	ring_green = MeshInstance3D.new()
	add_child(ring_green)

	# 碰撞体
	col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.5
	add_child(col)

func _make_rune_bar(size: Vector3) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bar.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.68, 1.0, 0.78, 0.95)
	m.emission_enabled = true
	m.emission = Color(0.34, 1.0, 0.52)
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar.material_override = m
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar


func _add_cylinder(pos: Vector3, top_r: float, bottom_r: float, h: float, seg: int, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = h
	cyl.radial_segments = seg
	cyl.rings = 1
	mi.mesh = cyl
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_sphere(pos: Vector3, scale_v: Vector3, mat: Material, seg: int = 16, rings: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = seg
	sm.rings = rings
	mi.mesh = sm
	mi.position = pos
	mi.scale = scale_v
	mi.material_override = mat
	add_child(mi)
	return mi


func _add_torus(inner: float, outer: float, tube_y: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 48
	mi.mesh = tm
	mi.position = pos
	mi.scale.y = tube_y / maxf((outer - inner) * 0.5, 0.001)
	mi.material_override = mat
	add_child(mi)
	return mi


func _glass_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.035
	m.metallic = 0.12
	m.emission_enabled = true
	m.emission = Color(0.28, 1.0, 0.5)
	m.emission_energy_multiplier = 0.18
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _glow_mat(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.12
	m.metallic = 0.05
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _set_orb_visible(v: bool) -> void:
	if mesh: mesh.visible = v
	if _shell: _shell.visible = v
	if _shard_root: _shard_root.visible = v
	if _glow: _glow.visible = v
	if _light: _light.visible = v
	if _cross_h: _cross_h.visible = v
	if _cross_v: _cross_v.visible = v
	if _ground: _ground.visible = v
	if _spark: _spark.emitting = v

func _process(delta):
	_t += delta
	if available:
		# 药球悬浮 + 光晕呼吸 + 内部晶片旋转；石刻十字固定不跟随
		var bob: float = sin(_t * 2.1) * 0.048
		var oy := ORB_Y + bob
		if mesh: mesh.position.y = oy
		if _shell: _shell.position.y = oy
		if _shard_root:
			_shard_root.position.y = oy
			_shard_root.rotation.y = _t * 0.85
		if _glow:
			_glow.position.y = oy
			var s: float = 1.0 + sin(_t * 2.6) * 0.06
			_glow.scale = Vector3(s, s, s)
		if _light:
			_light.position.y = oy
			_light.light_energy = 1.3 + sin(_t * 2.6) * 0.16
		if _ground:
			_ground.scale = Vector3.ONE * (1.0 + sin(_t * 1.7) * 0.05)
		return
	cooldown_timer -= delta
	if cooldown_timer <= 0:
		available = true
		_set_orb_visible(true)
		col.disabled = false
		ring_green.visible = false
	else:
		var progress = 1.0 - (cooldown_timer / respawn_time)
		_draw_green_arc(progress)

func _draw_green_arc(progress: float):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments = 64
	var angle_from = -PI / 2
	var angle_to = -PI / 2 + 2 * PI * progress
	var inner_r = 0.9
	var outer_r = 1.0
	var y = 0.335

	for i in range(segments):
		var a1 = angle_from + (angle_to - angle_from) * i / segments
		var a2 = angle_from + (angle_to - angle_from) * (i + 1) / segments
		var p1 = Vector3(cos(a1) * inner_r, y, sin(a1) * inner_r)
		var p2 = Vector3(cos(a2) * inner_r, y, sin(a2) * inner_r)
		var p3 = Vector3(cos(a1) * outer_r, y, sin(a1) * outer_r)
		var p4 = Vector3(cos(a2) * outer_r, y, sin(a2) * outer_r)
		st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p3)
		st.add_vertex(p2); st.add_vertex(p4); st.add_vertex(p3)

	st.generate_normals()
	var green_mat = StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.25, 1.0, 0.5, 0.85)
	green_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(green_mat)
	ring_green.mesh = st.commit()
	ring_green.visible = true

func _on_body_entered(body):
	if body is Hero and available:
		var level = body.level
		var heal_hp = 200 + 12 * level
		var heal_mp = 16 + 4 * level
		body.apply_regen(heal_hp, heal_mp, 5.0, "health_pack", 1.0)   # 每秒 1 次整块回复
		SfxManager.try_heal_sfx(body.display_name)
		available = false
		_set_orb_visible(false)
		col.disabled = true
		cooldown_timer = respawn_time

func _on_turret_died():
	queue_free()
