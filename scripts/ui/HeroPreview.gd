class_name HeroPreview
extends SubViewportContainer
## 选人界面中央「3D 立绘」：独立 SubViewport 里摆一个英雄模型，
## 配三灯（主光 / 背光轮廓 / 地面染色）+ 脚下发光圆环 + 缓慢自转呼吸。
## 无贴图依赖；模型取 Hero.HERO_MODEL_MAP，缺模型时退化为角色色胶囊体。
## 加载后按模型包围盒自动缩放并重新构图（相机/圆环/地台随模型贴脚）。

var accent := Color(0.32, 0.62, 1.0)
## 渲染分辨率 / 轻量模式（加载界面 10 张缩略立绘用：关 MSAA/辉光/阴影，省 GPU）
var render_size := Vector2i(900, 1100)
var lightweight := false
var _viewport: SubViewport
var _ready_done := false
var _pending_hero := ""
var _model: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _floor: MeshInstance3D
var _key_light: DirectionalLight3D
var _rim_light: OmniLight3D
var _floor_light: OmniLight3D
var _camera: Camera3D
var _t := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.size = render_size if render_size.x > 8 else Vector2i(900, 1100)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED if lightweight else Viewport.MSAA_4X
	add_child(_viewport)

	var we := WorldEnvironment.new()
	we.environment = _make_env()
	_viewport.add_child(we)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 2.7, 7.4)
	_camera.fov = 36.0
	_viewport.add_child(_camera)
	_camera.look_at(Vector3(0.0, 2.1, 0.0))

	_key_light = DirectionalLight3D.new()
	_key_light.rotation_degrees = Vector3(-38, 32, 0)
	_key_light.light_energy = 1.5
	_key_light.shadow_enabled = not lightweight
	_viewport.add_child(_key_light)

	_rim_light = OmniLight3D.new()
	_rim_light.position = Vector3(-2.2, 3.6, -2.6)
	_rim_light.light_color = accent
	_rim_light.light_energy = 5.0
	_rim_light.omni_range = 12.0
	_viewport.add_child(_rim_light)

	_floor_light = OmniLight3D.new()
	_floor_light.position = Vector3(1.6, 0.6, 2.0)
	_floor_light.light_color = accent.lightened(0.2)
	_floor_light.light_energy = 1.6
	_floor_light.omni_range = 8.0
	_viewport.add_child(_floor_light)

	# 脚下发光圆环
	var torus := TorusMesh.new()
	torus.inner_radius = 1.42
	torus.outer_radius = 1.62
	torus.rings = 64
	torus.ring_segments = 12
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.9)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = accent
	_ring_mat.emission_energy_multiplier = 2.2
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0.0, 0.04, 0.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_ring)

	# 地台圆盘（承接阴影与光晕）
	_floor = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.6, 4.6)
	_floor.mesh = plane
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.02, 0.03, 0.05, 1.0)
	dm.roughness = 0.85
	_floor.material_override = dm
	_floor.position = Vector3(0.0, -0.01, 0.0)
	_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_floor)
	set_process(true)
	_ready_done = true
	if _pending_hero != "":
		var p := _pending_hero
		_pending_hero = ""
		_apply_hero(p)


func _make_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.64, 0.86)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = not lightweight
	env.glow_intensity = 0.6
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	return env


func _process(delta: float) -> void:
	_t += delta
	if _model != null and is_instance_valid(_model):
		_model.rotation.y = sin(_t * 0.42) * 0.30
		_model.position.y = sin(_t * 0.9) * 0.02
	if _ring != null and is_instance_valid(_ring):
		_ring.rotation.y = _t * 0.35
		if _ring_mat != null:
			_ring_mat.emission_energy_multiplier = 1.8 + 0.9 * (0.5 + 0.5 * sin(_t * 1.6))


## 切换展示英雄；缺模型时用角色色胶囊体兜底。未进树时先记下，进树后自动应用。
func set_hero(hero_name: String) -> void:
	if not _ready_done:
		_pending_hero = hero_name
		return
	_apply_hero(hero_name)


func _apply_hero(hero_name: String) -> void:
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
		_model = null
	var root := Node3D.new()
	root.name = "PreviewModel"
	var created := false
	var entry: Array = Hero.HERO_MODEL_MAP.get(hero_name, [])
	if entry.size() > 0:
		var packed := load(str(entry[0])) as PackedScene
		if packed != null:
			var inst: Node3D = packed.instantiate()
			root.add_child(inst)
			_play_first_anim(inst)
			created = true
	if not created:
		var cap := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.7
		mesh.height = 2.6
		cap.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = accent
		mat.metallic = 0.35
		mat.roughness = 0.35
		cap.material_override = mat
		cap.position.y = 1.3
		root.add_child(cap)
	_model = root
	_viewport.add_child(root)
	_frame_model()


func set_accent(color: Color) -> void:
	accent = color
	if _rim_light != null:
		_rim_light.light_color = color
	if _floor_light != null:
		_floor_light.light_color = color.lightened(0.2)
	if _ring_mat != null:
		_ring_mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
		_ring_mat.emission = color


## 按模型包围盒自动缩放 + 相机/圆环/地台构图
func _frame_model() -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var aabb := _model_aabb()
	if aabb.size.y <= 0.001:
		return
	var s := clampf(3.2 / aabb.size.y, 0.05, 12.0)
	_model.scale = Vector3(s, s, s)
	aabb = _model_aabb()
	var c := aabb.get_center()
	var h := maxf(aabb.size.y, 0.5)
	_camera.position = c + Vector3(0.0, h * 0.08, h * 2.05)
	_camera.look_at(c)
	var foot := aabb.position.y + 0.02
	var foot_r := clampf(maxf(aabb.size.x, aabb.size.z) * 0.62, 0.5, 3.0)
	_ring.position = Vector3(c.x, foot, c.z)
	_ring.scale = Vector3(foot_r, 1.0, foot_r)
	_floor.position = Vector3(c.x, foot - 0.03, c.z)
	var fs := maxf(foot_r * 2.6, 2.8)
	_floor.scale = Vector3(fs, 1.0, fs)
	_floor_light.position = c + Vector3(1.4, 0.4, 1.8)
	_rim_light.position = c + Vector3(-2.0, h * 0.9, -2.2)


func _model_aabb() -> AABB:
	var first := true
	var aabb := AABB()
	for mi in _collect_meshes(_model):
		var t: Transform3D = mi.global_transform
		var a: AABB = mi.get_aabb()
		for i in 8:
			var p := t * a.get_endpoint(i)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func _collect_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_collect_meshes(c))
	return out


func _play_first_anim(root: Node3D) -> void:
	var ap := _find_anim_player(root)
	if ap != null:
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
