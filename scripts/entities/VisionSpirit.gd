class_name VisionSpirit
extends Node3D
## 视野之灵：己方边路二塔被摧毁 60 秒后，在二塔原位置生成。
## 友方英雄触碰获得 10 金币；随后走向附近 buff 周围的草丛并持续提供 20 米视野。
## 敌方英雄在 1 米内累计 5 秒后，视野之灵返回二塔位置并遁地消失。

const STATE_WALK := 0
const STATE_IDLE := 1
const STATE_RETURN := 2
const STATE_BURROW := 3
const ENEMY_RADIUS := 1.0
const ENEMY_TRIGGER_TIME := 5.0
const WALK_SPEED := 7.0

var team: int = 0
var spawn_pos: Vector3 = Vector3.ZERO
var bush_pos: Vector3 = Vector3.ZERO
var vision_radius: float = 20.0
var vision_active: bool = false
var gold_claimed: bool = false
var client_mode: bool = false   # 联机客户端只复刻表现，不跑模拟

var _state: int = STATE_WALK
var _t: float = 0.0
var _enemy_timer: float = 0.0
var _burrow_t: float = 0.0
var _visual: Node3D
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _orbit_a: MeshInstance3D
var _orbit_b: MeshInstance3D
var _base_ring: MeshInstance3D
var _timer_ring: MeshInstance3D
var _ring_arc: MeshInstance3D
var _label: Label3D
var _light: OmniLight3D

func _ready() -> void:
	add_to_group("vision_spirits")
	_build_visual()

func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# 幽蓝色灵体核心 + 外层柔光
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	_core.mesh = sm
	_core.material_override = _glow_mat(Color(0.52, 0.92, 1.0), 2.4, 0.95)
	_core.position.y = 0.86
	_visual.add_child(_core)

	_halo = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.46
	hm.height = 0.92
	_halo.mesh = hm
	_halo.material_override = _add_mat(Color(0.32, 0.82, 1.0, 0.16), 2.0)
	_halo.position.y = 0.86
	_visual.add_child(_halo)

	# 两颗环绕灵火，让它一眼区别于普通特效
	_orbit_a = _make_orb(Color(0.70, 1.0, 1.0), 0.075)
	_orbit_b = _make_orb(Color(1.0, 0.84, 0.38), 0.055)
	_visual.add_child(_orbit_a)
	_visual.add_child(_orbit_b)

	# 脚下淡青色底盘环
	var br := MeshInstance3D.new()
	var bt := TorusMesh.new()
	bt.inner_radius = 0.48
	bt.outer_radius = 0.60
	bt.rings = 48
	br.mesh = bt
	br.material_override = _unshaded(Color(0.30, 0.78, 1.0, 0.48), true)
	br.position.y = 0.055
	_visual.add_child(br)

	# 地面光斑
	var ground := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.4, 2.4)
	ground.mesh = qm
	ground.rotation_degrees = Vector3(-90, 0, 0)
	ground.position.y = 0.025
	ground.material_override = _add_mat(Color(0.20, 0.65, 1.0, 0.13), 0.0)
	_visual.add_child(ground)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.82, 1.0)
	_light.light_energy = 1.25
	_light.omni_range = 5.0
	_light.omni_attenuation = 1.7
	_light.shadow_enabled = false
	_light.position.y = 0.8
	_visual.add_child(_light)

	# 视野计时环：未触发时隐藏，敌方英雄靠近时显示
	_base_ring = MeshInstance3D.new()
	var tr := TorusMesh.new()
	tr.inner_radius = 0.64
	tr.outer_radius = 0.73
	tr.rings = 48
	_base_ring.mesh = tr
	_base_ring.material_override = _unshaded(Color(0.10, 0.12, 0.16, 0.72), false)
	_base_ring.position.y = 0.045
	_base_ring.visible = false
	add_child(_base_ring)
	_ring_arc = MeshInstance3D.new()
	_ring_arc.visible = false
	add_child(_ring_arc)

	# 上浮灵尘
	var spark := CPUParticles3D.new()
	spark.amount = 14
	spark.lifetime = 1.5
	spark.position.y = 0.45
	spark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spark.emission_sphere_radius = 0.28
	spark.direction = Vector3(0, 1, 0)
	spark.spread = 20.0
	spark.initial_velocity_min = 0.12
	spark.initial_velocity_max = 0.34
	spark.gravity = Vector3(0, 0.22, 0)
	spark.scale_amount_min = 0.015
	spark.scale_amount_max = 0.042
	spark.color = Color(0.55, 0.92, 1.0, 0.82)
	_visual.add_child(spark)

	_label = Label3D.new()
	_label.text = "视野之灵"
	_label.font_size = 30
	_label.pixel_size = 0.0045
	_label.position.y = 1.62
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(0.68, 0.94, 1.0)
	_label.outline_modulate = Color(0.01, 0.03, 0.06, 0.86)
	_label.outline_size = 8
	add_child(_label)

func _make_orb(c: Color, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = s
	sm.height = s * 2.0
	mi.mesh = sm
	mi.material_override = _glow_mat(c, 2.8, 0.95)
	return mi

func _glow_mat(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _unshaded(c: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _add_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = energy
	return m

func _process(delta: float) -> void:
	_t += delta
	_animate_visual()
	if client_mode:
		return
	if not gold_claimed:
		_check_gold_pickup()
	match _state:
		STATE_WALK:
			if _move_towards(bush_pos, delta):
				_state = STATE_IDLE
				vision_active = true
			else:
				_update_enemy_timer(delta)
		STATE_IDLE:
			vision_active = true
			_update_enemy_timer(delta)
		STATE_RETURN:
			vision_active = false
			if _move_towards(spawn_pos, delta):
				_start_burrow()
		STATE_BURROW:
			_burrow_t += delta
			_visual.position.y = -_burrow_t * 0.85
			_visual.scale = Vector3.ONE * maxf(0.05, 1.0 - _burrow_t * 0.9)
			if _burrow_t >= 1.0:
				# 消失后 3 分钟，在二塔原位置重新生成
				var bm = get_tree().get_first_node_in_group("battle_manager")
				if bm and bm.has_method("schedule_vision_spirit"):
					bm.schedule_vision_spirit(spawn_pos, "", 180.0)
				queue_free()

func _animate_visual() -> void:
	if _visual == null:
		return
	var bob := sin(_t * 2.2) * 0.07
	_core.position.y = 0.86 + bob
	_halo.position.y = 0.86 + bob
	_halo.scale = Vector3.ONE * (1.0 + sin(_t * 2.8) * 0.08)
	_light.light_energy = 1.15 + sin(_t * 2.8) * 0.18
	_orbit_a.position = Vector3(cos(_t * 1.8) * 0.42, 0.86 + bob + sin(_t * 3.1) * 0.08, sin(_t * 1.8) * 0.42)
	_orbit_b.position = Vector3(cos(_t * 1.8 + PI) * 0.36, 0.86 + bob - sin(_t * 3.1) * 0.06, sin(_t * 1.8 + PI) * 0.36)
	_label.position.y = 1.62 + bob

func _move_towards(target: Vector3, delta: float) -> bool:
	var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if to.length() <= 0.45:
		return true
	global_position += to.normalized() * WALK_SPEED * delta
	return false

func _check_gold_pickup() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		if not (h is Hero) or h.team != team or h.health <= 0.0:
			continue
		if global_position.distance_to(h.global_position) > 1.25:
			continue
		gold_claimed = true
		h.add_gold(10)
		var bm = get_tree().get_first_node_in_group("battle_manager")
		if bm and bm.ui:
			bm.ui.show_gold_popup(global_position + Vector3(0, 1.1, 0), 10, h == bm.hero)
		return

func _update_enemy_timer(delta: float) -> void:
	var enemy_near := false
	for h in get_tree().get_nodes_in_group("heroes"):
		if not (h is Hero) or h.team == team or h.health <= 0.0:
			continue
		if global_position.distance_to(h.global_position) < ENEMY_RADIUS:
			enemy_near = true
			break
	if not enemy_near:
		# 敌方英雄离开：计时直接归零，环形计时器隐藏
		_enemy_timer = 0.0
		_set_timer_ring(0.0)
		return
	_enemy_timer += delta
	if _enemy_timer >= ENEMY_TRIGGER_TIME:
		_enemy_timer = 0.0
		_set_timer_ring(0.0)
		_state = STATE_RETURN
		vision_active = false
		return
	_set_timer_ring(_enemy_timer / ENEMY_TRIGGER_TIME)

func _set_timer_ring(progress: float) -> void:
	var show := progress > 0.001
	_base_ring.visible = show
	_ring_arc.visible = show
	if not show:
		return
	_draw_ring_arc(clampf(progress, 0.0, 1.0))

func _draw_ring_arc(progress: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 56
	var a0 := -PI * 0.5
	var a1 := a0 + TAU * progress
	var inner_r := 0.64
	var outer_r := 0.73
	var y := 0.05
	for i in range(segments):
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var b0 := a0 + (a1 - a0) * t0
		var b1 := a0 + (a1 - a0) * t1
		var p1 := Vector3(cos(b0) * inner_r, y, sin(b0) * inner_r)
		var p2 := Vector3(cos(b1) * inner_r, y, sin(b1) * inner_r)
		var p3 := Vector3(cos(b0) * outer_r, y, sin(b0) * outer_r)
		var p4 := Vector3(cos(b1) * outer_r, y, sin(b1) * outer_r)
		st.add_vertex(p1); st.add_vertex(p2); st.add_vertex(p3)
		st.add_vertex(p2); st.add_vertex(p4); st.add_vertex(p3)
	st.generate_normals()
	st.set_material(_unshaded(Color(1.0, 0.58, 0.24, 0.92), false))
	_ring_arc.mesh = st.commit()

func _start_burrow() -> void:
	_state = STATE_BURROW
	_burrow_t = 0.0
	vision_active = false
	_set_timer_ring(0.0)
	_label.visible = false

func get_net_progress() -> float:
	return clampf(_enemy_timer / ENEMY_TRIGGER_TIME, 0.0, 1.0)

func get_net_state() -> int:
	return _state

func apply_net_state(pos: Vector3, active: bool, progress: float, st: int) -> void:
	global_position = Vector3(pos.x, 0.0, pos.z)
	vision_active = active
	_state = st
	_set_timer_ring(progress)
	if st == STATE_BURROW:
		_label.visible = false
		_visual.visible = false
