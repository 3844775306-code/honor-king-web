class_name HealthPack
extends Area3D

## 血包（真实 3D 模型）：石台 + 悬浮发光药球 + 十字光标 + 地面光斑 + 上浮粒子，
## 并保留原有「灰色外环 + 绿色回复进度弧」与全部逻辑字段/行为。
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
var _cross_h: MeshInstance3D      # 十字横
var _cross_v: MeshInstance3D      # 十字竖
var _ground: MeshInstance3D       # 地面光斑
var _spark: CPUParticles3D        # 上浮粒子
var _t: float = 0.0               # 本地动画时钟

func _ready():
	add_to_group("health_packs")
	_create_visual()
	body_entered.connect(_on_body_entered)

func _create_visual():
	# —— 石台（粗糙暗石，让血包"落在"地上而不是浮空）——
	var ped := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.52
	pm.bottom_radius = 0.66
	pm.height = 0.14
	pm.radial_segments = 16
	ped.mesh = pm
	ped.position.y = 0.07
	ped.material_override = _mat(Color(0.26, 0.25, 0.23), 0.95, 0.0)
	add_child(ped)
	# 石台顶面暗色内凹
	var inlay := MeshInstance3D.new()
	var im := CylinderMesh.new()
	im.top_radius = 0.40
	im.bottom_radius = 0.42
	im.height = 0.02
	im.radial_segments = 16
	inlay.mesh = im
	inlay.position.y = 0.145
	inlay.material_override = _mat(Color(0.13, 0.20, 0.14), 0.9, 0.0)
	add_child(inlay)

	# —— 药球（自发绿光，核心很亮）——
	mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.24
	sm.height = 0.48
	sm.radial_segments = 24
	sm.rings = 12
	mesh.mesh = sm
	mesh.position.y = 0.62
	mesh.material_override = _glow_mat(Color(0.16, 0.95, 0.42), 2.4, 0.85)
	add_child(mesh)

	# —— 外层柔光晕（加色混合）——
	_glow = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.42
	gm.height = 0.84
	gm.radial_segments = 20
	gm.rings = 10
	_glow.mesh = gm
	_glow.position.y = 0.62
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(0.25, 1.0, 0.55, 0.16)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow.material_override = gmat
	add_child(_glow)

	# —— 十字光标（药性标识）——
	_cross_h = _make_cross_bar(Vector3(0.52, 0.10, 0.10))
	_cross_v = _make_cross_bar(Vector3(0.10, 0.52, 0.10))
	add_child(_cross_h)
	add_child(_cross_v)

	# —— 地面光斑（远景也能看出这里有补给）——
	_ground = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.4, 2.4)
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
	add_child(_ground)

	# —— 上浮微粒 ——
	_spark = CPUParticles3D.new()
	_spark.amount = 12
	_spark.lifetime = 1.6
	_spark.position.y = 0.35
	_spark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_spark.emission_sphere_radius = 0.28
	_spark.direction = Vector3(0, 1, 0)
	_spark.spread = 18.0
	_spark.initial_velocity_min = 0.18
	_spark.initial_velocity_max = 0.42
	_spark.gravity = Vector3(0, 0.35, 0)
	_spark.scale_amount_min = 0.02
	_spark.scale_amount_max = 0.045
	_spark.color = Color(0.55, 1.0, 0.68, 0.85)
	add_child(_spark)

	# —— 灰色底座圆环（原表现保留，压暗更像石刻）——
	ring_grey = MeshInstance3D.new()
	var torus_grey = TorusMesh.new()
	torus_grey.inner_radius = 0.9
	torus_grey.outer_radius = 1.0
	torus_grey.rings = 64
	ring_grey.mesh = torus_grey
	var mat_grey = StandardMaterial3D.new()
	mat_grey.albedo_color = Color(0.42, 0.44, 0.46, 0.9)
	mat_grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_grey.material_override = mat_grey
	add_child(ring_grey)

	# —— 绿色回复进度弧（动态生成，逻辑不变）——
	ring_green = MeshInstance3D.new()
	add_child(ring_green)

	# 碰撞体
	col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.5
	add_child(col)

func _make_cross_bar(size: Vector3) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bar.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 1.0, 0.9, 0.92)
	m.emission_enabled = true
	m.emission = Color(0.45, 1.0, 0.6)
	m.emission_energy_multiplier = 2.6
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	bar.material_override = m
	bar.position.y = 0.62
	return bar

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
	if _glow: _glow.visible = v
	if _cross_h: _cross_h.visible = v
	if _cross_v: _cross_v.visible = v
	if _ground: _ground.visible = v
	if _spark: _spark.emitting = v

func _process(delta):
	_t += delta
	if available:
		# 悬浮上下 + 光晕呼吸 + 十字缓慢旋转
		var bob: float = sin(_t * 2.1) * 0.055
		if mesh: mesh.position.y = 0.62 + bob
		if _glow: _glow.position.y = 0.62 + bob * 0.7
		if _cross_h: _cross_h.position.y = 0.62 + bob
		if _cross_v:
			_cross_v.position.y = 0.62 + bob
			_cross_v.rotation.y = _t * 1.1
		if _glow:
			var s: float = 1.0 + sin(_t * 2.6) * 0.07
			_glow.scale = Vector3(s, s, s)
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
	var y = 0.3

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
		body.apply_regen(heal_hp, heal_mp, 5.0, "health_pack")
		SfxManager.try_heal_sfx(body.display_name)
		available = false
		_set_orb_visible(false)
		col.disabled = true
		cooldown_timer = respawn_time

func _on_turret_died():
	queue_free()
