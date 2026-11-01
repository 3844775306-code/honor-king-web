extends Control
## 3D 版开机动画：3D 英雄列阵 + 浮空石台 + 场景灯光/雾/粒子，叠电影标题 UI。
## 与 2D 版共用同一套启动节奏；按 V 可切回 2D 版对比。

signal finished
signal toggle_requested

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const BootHeroPool = preload("res://scripts/ui/BootHeroPool.gd")
var _heroes: Array = []
const GOLD := Color(1.0, 0.84, 0.35)
const CREAM := Color(1.0, 0.93, 0.76)
const HERO_X := [-5.0, -2.5, 0.0, 2.5, 5.0]
const HERO_Z := [0.75, 0.20, -0.35, 0.20, 0.75]
const PLATFORM_TOP := 0.28

var _t := 0.0
var _done := false
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _hero_roots: Array = []
var _ui: Control
var _title: Label
var _title_glow: Label
var _sub: Label
var _tag: Label
var _status: Label
var _enter: Label
var _hint: Label
var _studio: Label
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _prog_bg: ColorRect
var _prog_fill: ColorRect
var _vignette: Control


func _ready() -> void:
	_heroes = BootHeroPool.pick(5)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_build_viewport()
	_build_world()
	_build_ui()
	resized.connect(_layout)
	_layout()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_animate()
	if not _done and _t >= 6.2:
		_finish()


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_V:
			toggle_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if _t >= 0.9:
			_finish()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _t >= 0.9:
			_finish()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		if _t >= 0.9:
			_finish()
			get_viewport().set_input_as_handled()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


# ==================== 3D 场景 ====================

func _build_viewport() -> void:
	var sc := SubViewportContainer.new()
	sc.name = "Boot3DViewport"
	sc.stretch = true
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sc)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1600, 1000)
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sc.add_child(_vp)
	_world = Node3D.new()
	_world.name = "BootWorld"
	_vp.add_child(_world)


func _build_world() -> void:
	# 暗色电影环境：冷雾 + 暖金轮廓光
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.035, 0.095)
	sky_mat.sky_horizon_color = Color(0.18, 0.34, 0.56)
	sky_mat.ground_horizon_color = Color(0.06, 0.12, 0.20)
	sky_mat.ground_bottom_color = Color(0.004, 0.007, 0.018)
	sky_mat.sky_curve = 0.16
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 0.80
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.72
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.26, 0.42)
	env.fog_light_energy = 0.8
	env.fog_density = 0.010
	env.fog_sky_affect = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.position = Vector3(-5.8, 4.9, 16.0)
	_cam.look_at(Vector3(0.0, 2.0, 0.0))
	_world.add_child(_cam)
	_cam.make_current()

	# 主光：暖色逆光 + 冷色补光，保留英雄轮廓
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 160.0, 0.0)
	key.light_color = Color(1.0, 0.90, 0.72)
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.shadow_bias = 0.05
	key.directional_shadow_max_distance = 40.0
	_world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-22.0, 20.0, 0.0)
	fill.light_color = Color(0.42, 0.60, 1.0)
	fill.light_energy = 0.85
	fill.shadow_enabled = false
	_world.add_child(fill)

	_build_platform()
	_build_backdrop()
	_build_heroes()
	_build_particles()


func _build_platform() -> void:
	var root := Node3D.new()
	root.name = "BootPlatform"
	_world.add_child(root)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 8.4
	cyl.bottom_radius = 9.4
	cyl.height = 0.7
	cyl.radial_segments = 64
	cyl.rings = 2
	body.mesh = cyl
	body.material_override = _stone_mat()
	body.position.y = -0.08
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	# 发光台沿 / 内圈
	_add_ring(root, 8.35, 8.52, 0.30, Color(1.0, 0.78, 0.34, 0.8), true)
	_add_ring(root, 7.7, 7.78, 0.26, Color(0.30, 0.72, 1.0, 0.36), false)
	_add_ring(root, 4.9, 5.0, 0.255, Color(1.0, 0.84, 0.42, 0.22), false)
	# 台面中心王冠光斑
	for i in range(5):
		var r := 1.0 + float(i) * 0.65
		_add_ring(root, r, r + 0.06, 0.27 + float(i) * 0.002,
			Color(1.0, 0.78, 0.32, 0.10), false)


func _add_ring(parent: Node3D, inner: float, outer: float, y: float, col: Color, glow: bool) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 64
	torus.ring_segments = 8
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	if glow:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.8
	mi.material_override = mat
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _build_backdrop() -> void:
	# 远景悬浮岩柱，雾中剪影，给 3D 场景纵深
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for i in range(14):
		var a := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(14.0, 26.0)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 7
		sm.rings = 4
		mi.mesh = sm
		mi.material_override = _stone_mat()
		mi.position = Vector3(cos(a) * rad, rng.randf_range(-4.0, 2.0), sin(a) * rad)
		mi.scale = Vector3(rng.randf_range(1.4, 3.6), rng.randf_range(2.0, 6.0), rng.randf_range(1.4, 3.6))
		mi.rotation.y = rng.randf_range(0.0, TAU)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(mi)
	# 背景王冠光环
	var halo := MeshInstance3D.new()
	var ht := TorusMesh.new()
	ht.inner_radius = 5.9
	ht.outer_radius = 6.04
	ht.rings = 64
	ht.ring_segments = 8
	halo.mesh = ht
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1.0, 0.78, 0.34, 0.16)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.72, 0.30)
	hm.emission_energy_multiplier = 1.0
	halo.material_override = hm
	halo.position = Vector3(0.0, 5.0, -16.0)
	halo.rotation.x = PI * 0.5
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(halo)
	# 金色浮尘光柱
	for x in [-5.8, 5.8]:
		var pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.5
		cyl.height = 9.0
		cyl.radial_segments = 12
		pillar.mesh = cyl
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.albedo_color = Color(1.0, 0.80, 0.36, 0.06)
		pillar.material_override = pm
		pillar.position = Vector3(float(x), 4.2, -4.0)
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(pillar)


func _build_heroes() -> void:
	for i in range(_heroes.size()):
		var hero: Dictionary = _heroes[i]
		var name := str(hero.name)
		var x := float(HERO_X[i])
		var z := float(HERO_Z[i])
		var root := _spawn_hero(name, Vector3(x, PLATFORM_TOP, z))
		if root == null:
			continue
		_hero_roots.append(root)
		# 脚下阵营色光环
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.95
		torus.outer_radius = 1.12
		torus.rings = 48
		ring.mesh = torus
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(1.0, 0.82, 0.38, 0.48)
		ring.material_override = rm
		ring.position = Vector3(x, PLATFORM_TOP + 0.03, z)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_world.add_child(ring)
		# 名字 / 职责浮标
		var lab := Label3D.new()
		lab.text = "%s\n%s" % [name, str(hero.role)]
		lab.font_size = 30
		lab.pixel_size = 0.0042
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(1.0, 0.91, 0.70)
		lab.outline_modulate = Color(0.01, 0.02, 0.05, 0.9)
		lab.outline_size = 8
		lab.position = Vector3(x, 3.55, z)
		lab.no_depth_test = true
		_world.add_child(lab)
		# 每个英雄一盏低强度轮廓灯
		var rim := OmniLight3D.new()
		rim.light_color = HeroArt.accent_of(name)
		rim.light_energy = 1.15
		rim.omni_range = 3.2
		rim.position = Vector3(x, 2.4, z - 1.2)
		rim.shadow_enabled = false
		_world.add_child(rim)


func _spawn_hero(hero_name: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "BootHero_" + hero_name
	var entry: Array = Hero.HERO_MODEL_MAP.get(hero_name, [])
	var created := false
	if entry.size() > 0:
		var packed := load(str(entry[0])) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate()
			root.add_child(inst)
			_play_idle(inst)
			created = true
	if not created:
		var cap := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.55
		cm.height = 2.4
		cap.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = HeroArt.accent_of(hero_name)
		mat.metallic = 0.3
		mat.roughness = 0.35
		cap.material_override = mat
		cap.position.y = 1.2
		root.add_child(cap)
	_world.add_child(root)
	root.position = Vector3.ZERO
	root.rotation.y = 0.0
	var aabb := _model_aabb(root)
	if aabb.size.y > 0.01:
		var s := clampf(3.15 / aabb.size.y, 0.03, 12.0)
		root.scale = Vector3(s, s, s)
		aabb = _model_aabb(root)
		root.position = Vector3(pos.x, pos.y - aabb.position.y, pos.z)
	else:
		root.position = pos
	return root


func _play_idle(node: Node) -> void:
	var ap := _find_anim_player(node)
	if ap == null:
		return
	if ap.has_animation("idle"):
		ap.play("idle")
	else:
		var names := ap.get_animation_list()
		if names.size() > 0:
			ap.play(names[0])


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null


func _model_aabb(root: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for mi in _collect_meshes(root):
		var xf: Transform3D = mi.global_transform
		var a: AABB = mi.get_aabb()
		for i in range(8):
			var p := xf * a.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


func _collect_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _stone_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.13, 0.16)
	m.roughness = 0.82
	m.metallic = 0.12
	return m


func _build_particles() -> void:
	var p := CPUParticles3D.new()
	p.amount = 70
	p.lifetime = 5.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.8
	p.position = Vector3(0.0, 1.4, 0.0)
	p.direction = Vector3(0.0, 1.0, 0.0)
	p.spread = 25.0
	p.initial_velocity_min = 0.12
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.0, 0.10, 0.0)
	p.scale_amount_min = 0.018
	p.scale_amount_max = 0.055
	p.color = Color(1.0, 0.78, 0.36, 0.72)
	_world.add_child(p)


# ==================== 2D 叠层 UI ====================

func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "BootOverlay"
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_vignette = _Vignette.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_vignette)
	_bar_top = ColorRect.new()
	_bar_top.color = Color(0.0, 0.0, 0.0, 0.96)
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color(0.0, 0.0, 0.0, 0.96)
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_bar_bottom)
	_title_glow = _mk_label("荣耀王者", GOLD, 8, 0.18)
	_ui.add_child(_title_glow)
	_title = _mk_label("荣耀王者", CREAM, 8, 1.0)
	_ui.add_child(_title)
	_sub = _mk_label("H O N O R   K I N G", GOLD, 3, 0.82)
	_ui.add_child(_sub)
	_tag = _mk_label("王者峡谷 · 5V5 公平竞技", Color(0.72, 0.82, 1.0), 3, 0.72)
	_ui.add_child(_tag)
	_studio = _mk_label("H O N O R   K I N G   S T U D I O", Color(0.62, 0.75, 0.92), 2, 0.62)
	_ui.add_child(_studio)
	_status = _mk_label("正在进入王者峡谷...", Color(0.64, 0.78, 0.96), 3, 0.0)
	_ui.add_child(_status)
	_prog_bg = ColorRect.new()
	_prog_bg.color = Color(0.18, 0.28, 0.44, 0.58)
	_prog_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_prog_bg)
	_prog_fill = ColorRect.new()
	_prog_fill.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.92)
	_prog_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_prog_fill)
	_enter = _mk_label("点击进入  ›", CREAM, 5, 0.0)
	_ui.add_child(_enter)
	_hint = _mk_label("点击 / 空格 跳过  ·  V 切换 2D/3D", Color(0.58, 0.68, 0.84), 2, 0.0)
	_ui.add_child(_hint)


func _mk_label(txt: String, col: Color, tier: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate = Color(1.0, 1.0, 1.0, alpha)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.05, 0.88))
	l.add_theme_constant_override("outline_size", 8)
	l.set_meta("tier", tier)
	return l


func _layout() -> void:
	var s := size
	if _ui == null or s.x < 32.0 or s.y < 32.0:
		return
	_vignette.size = s
	_bar_top.position = Vector2.ZERO
	_bar_top.size = Vector2(s.x, s.y * 0.055)
	_bar_bottom.position = Vector2(0.0, s.y * 0.945)
	_bar_bottom.size = Vector2(s.x, s.y * 0.055)
	var title_fs := int(clampf(s.y * 0.092, 64.0, 154.0))
	_title.add_theme_font_size_override("font_size", title_fs)
	_title_glow.add_theme_font_size_override("font_size", title_fs + 8)
	_title.size = Vector2(s.x, float(title_fs) * 1.35)
	_title.position = Vector2(0.0, s.y * 0.070)
	_title.set_meta("y0", _title.position.y)
	_title_glow.size = _title.size
	_title_glow.position = _title.position + Vector2(0.0, 2.0)
	_sub.add_theme_font_size_override("font_size", int(clampf(s.y * 0.027, 18.0, 36.0)))
	_sub.size = Vector2(s.x, 48.0)
	_sub.position = Vector2(0.0, s.y * 0.070 + float(title_fs) * 1.38)
	_tag.add_theme_font_size_override("font_size", int(clampf(s.y * 0.023, 16.0, 29.0)))
	_tag.size = Vector2(s.x, 40.0)
	_tag.position = Vector2(0.0, s.y * 0.070 + float(title_fs) * 1.68)
	_studio.add_theme_font_size_override("font_size", int(clampf(s.y * 0.015, 11.0, 17.0)))
	_studio.size = Vector2(s.x - 56.0, 26.0)
	_studio.position = Vector2(28.0, s.y * 0.055 + 8.0)
	_studio.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status.add_theme_font_size_override("font_size", int(clampf(s.y * 0.020, 14.0, 24.0)))
	_status.size = Vector2(s.x, 38.0)
	_status.position = Vector2(0.0, s.y * 0.818)
	var pw := s.x * 0.26
	_prog_bg.position = Vector2((s.x - pw) * 0.5, s.y * 0.858)
	_prog_bg.size = Vector2(pw, 3.0)
	_prog_fill.position = _prog_bg.position
	_prog_fill.size = Vector2(0.0, 3.0)
	_enter.add_theme_font_size_override("font_size", int(clampf(s.y * 0.030, 21.0, 40.0)))
	_enter.size = Vector2(s.x, 56.0)
	_enter.position = Vector2(0.0, s.y * 0.885)
	_hint.add_theme_font_size_override("font_size", int(clampf(s.y * 0.014, 11.0, 16.0)))
	_hint.size = Vector2(s.x, 30.0)
	_hint.position = Vector2(0.0, s.y * 0.935)


func _animate() -> void:
	var k := _ease(_t, 0.9, 1.9)
	_title.modulate.a = k
	_title_glow.modulate.a = 0.17 * k
	if not _title.has_meta("y0"):
		_title.set_meta("y0", _title.position.y)
	var title_y0: float = float(_title.get_meta("y0", _title.position.y))
	_title.position.y = title_y0 + (1.0 - k) * 18.0
	_title_glow.position.y = _title.position.y + 2.0
	_sub.modulate.a = _ease(_t, 1.25, 2.1) * 0.82
	_tag.modulate.a = _ease(_t, 1.65, 2.5) * 0.72
	_studio.modulate.a = _ease(_t, 0.0, 0.7) * (1.0 - _ease(_t, 2.1, 2.8)) * 0.62
	_status.modulate.a = _ease(_t, 2.3, 3.0) * 0.8
	var fill := clampf(_t / 5.2, 0.0, 1.0)
	_prog_fill.size.x = _prog_bg.size.x * fill
	var enter := _ease(_t, 4.1, 4.7)
	_enter.modulate.a = enter * (0.72 + 0.28 * sin(_t * 4.2))
	_hint.modulate.a = _ease(_t, 1.0, 1.5) * 0.55
	# 镜头缓慢横移 + 呼吸
	var ang := lerpf(-0.36, 0.10, _ease(_t, 0.0, 6.0))
	var dist := lerpf(16.0, 15.0, _ease(_t, 0.0, 4.5))
	_cam.position = Vector3(sin(ang) * dist, 4.9, cos(ang) * dist)
	_cam.look_at(Vector3(0.0, 2.0, 0.0))


func _ease(x: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if x >= b else 0.0
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


class _Vignette extends Control:
	func _draw() -> void:
		var s := size
		if s.x < 8.0 or s.y < 8.0:
			return
		var bands := 10
		for i in range(bands):
			var a := 0.070 * (1.0 - float(i) / float(bands))
			var t := s.y * 0.055 * float(i)
			draw_rect(Rect2(0.0, 0.0, s.x, t), Color(0, 0, 0, a * 0.8))
			draw_rect(Rect2(0.0, s.y - t, s.x, t), Color(0, 0, 0, a * 0.8))
			draw_rect(Rect2(0.0, 0.0, t, s.y), Color(0, 0, 0, a * 0.65))
			draw_rect(Rect2(s.x - t, 0.0, t, s.y), Color(0, 0, 0, a * 0.65))
