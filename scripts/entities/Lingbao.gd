extends Node3D
## 灵宝：跟在玩家英雄身边的小精灵（程序化建模，无美术资源）。
## 会看局势说话（击杀/阵亡/残血/推塔）、能摸（好感度/点身上任意位置都算）、能聊（聊天里 @灵宝 会回话）。
## 创建：BattleManager._create_player_hero() 里 LingbaoScript.ensure(self)

const Store = preload("res://scripts/core/LingbaoStore.gd")
const GROUP := "lingbao"
const FOLLOW_OFFSET := Vector2(1.05, 1.75)   # 相机右 / 世界高度
const POLL := 0.35
const HIT_LAYER := 106    # 高于触控(100)/聊天(45)，低于结算页(110)：战斗中摸得到，结算页不挡

const LINES_HELLO := ["我来啦！这局好好打～", "又见面啦，一起上分！", "今天也要赢哦"]
const LINES_KILL := ["厉害！这波帅到我了", "刚才那下好准", "继续压，别停", "对面心态崩了吧"]
const LINES_DIED := ["呜…别难过，复活再战", "小心点嘛", "下次我先帮你探草"]
const LINES_LOW := ["血不多了，先回城吧", "先撤一下，别硬拼"]
const LINES_TOWER := ["塔推掉了，好耶", "这波推塔漂亮"]
const LINES_PET := ["嘿嘿～", "好舒服", "再摸摸嘛", "最喜欢你了", "嗯…再来一下"]
const LINES_TALK := ["我在呢，说给我听", "嗯嗯，我听着呢", "别紧张，我在你旁边"]

var hero = null
var _bm = null
var _art: Node3D = null          # 模型根（受摸头/开心时挤压缩放，与跟随缩放互不干扰）
var _body: MeshInstance3D = null
var _head: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _halo_glow: MeshInstance3D = null
var _bubble: Label3D = null
var _sparkle: CPUParticles3D = null
var _hearts: CPUParticles3D = null
var _light: OmniLight3D = null
var _eyes: Array = []            # [MeshInstance3D] 眼睛（眨眼用）
var _eye_dots: Array = []        # [MeshInstance3D] 眼里的高光点
var _ears: Array = []            # [Node3D] 耳朵（轻晃用）
var _mat_body: StandardMaterial3D = null
var _mat_glow: StandardMaterial3D = null
var _base_color := Color.WHITE
var _t := 0.0
var _poll := 0.0
var _bubble_t := 0.0
var _last_kills := 0
var _last_deaths := 0
var _low_cd := 0.0
var _last_towers := -1
var _btn: Button = null
var _hit: Control = null
var _layer: CanvasLayer = null
var _blink_wait := 3.0
var _blink_t := 0.0
var _mood := 0.0          # 情绪偏移（正=开心，负=沮丧），驱动上下浮动幅度


static func ensure(bm) -> Node:
	if bm == null or not is_instance_valid(bm):
		return null
	var found = bm.get_tree().get_first_node_in_group(GROUP)
	if found != null:
		return found
	var lb = load("res://scripts/entities/Lingbao.gd").new()
	lb.name = "Lingbao"
	bm.add_child(lb)
	return lb


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_base_color = Store.color()
	_build_art()
	_build_ui()
	_bm = get_tree().get_first_node_in_group("battle_manager")
	hero = _bm.hero if _bm != null and is_instance_valid(_bm) else null
	if hero != null:
		global_position = hero.global_position + Vector3(0.0, FOLLOW_OFFSET.y, 0.0)
		_last_kills = int(hero.kills)
		_last_deaths = int(hero.deaths)
	set_process(true)
	_talk(str(LINES_HELLO[randi() % LINES_HELLO.size()]), 3.2)
	if ChatService != null:
		ChatService.system_note("灵宝 %s 已就位（好感度 %d · Lv.%d）" % [Store.name(), Store.affection(), Store.level()])


# ---------------- 建模（Q 版小精灵：大头 + 大眼 + 腮红 + 耳朵 + 光环 + 星尘） ----------------

func _body_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.lightened(0.20)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.45
	m.roughness = 0.26
	m.rim_enabled = true
	m.rim = 0.6
	m.rim_tint = 0.55
	return m


func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.35)
	m.emission_enabled = true
	m.emission = col.lightened(0.25)
	m.emission_energy_multiplier = 1.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _sphere(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material,
		seg: int = 18, rings: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = height
	sm.radial_segments = seg
	sm.rings = rings
	mi.mesh = sm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_art() -> void:
	_art = Node3D.new()
	_art.name = "Art"
	_art.scale = Vector3(0.95, 0.95, 0.95)
	add_child(_art)

	_mat_body = _body_mat(_base_color)
	_mat_glow = _glow_mat(_base_color)

	# 身体（蛋形，略压扁）
	_body = _sphere(_art, 0.30, 0.46, Vector3(0.0, 0.10, 0.0), _mat_body)
	_body.scale = Vector3(1.0, 1.04, 1.0)
	# 脚（两只小圆脚，飘着也像站着）
	_sphere(_art, 0.085, 0.10, Vector3(-0.12, -0.14, 0.09), _mat_body)
	_sphere(_art, 0.085, 0.10, Vector3(0.12, -0.14, 0.09), _mat_body)
	# 小手
	var arm_l := _sphere(_art, 0.062, 0.15, Vector3(-0.30, 0.20, 0.02), _mat_body)
	arm_l.rotation = Vector3(0.0, 0.0, deg_to_rad(28.0))
	var arm_r := _sphere(_art, 0.062, 0.15, Vector3(0.30, 0.20, 0.02), _mat_body)
	arm_r.rotation = Vector3(0.0, 0.0, deg_to_rad(-28.0))

	# 大头
	_head = _sphere(_art, 0.26, 0.52, Vector3(0.0, 0.62, 0.0), _mat_body)

	# 耳朵（两只小圆锥 + 发光耳尖）
	var ear_col := _body_mat(_base_color.lightened(0.12))
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(sx * 0.15, 0.80, 0.0)
		ear.rotation = Vector3(0.0, 0.0, deg_to_rad(-sx * 22.0))
		_art.add_child(ear)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.075
		cm.height = 0.24
		cm.radial_segments = 12
		cone.mesh = cm
		cone.position = Vector3(0.0, 0.12, 0.0)
		cone.material_override = ear_col
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ear.add_child(cone)
		var tip := _sphere(ear, 0.035, 0.07, Vector3(0.0, 0.245, 0.0), _mat_glow, 10, 6)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ears.append(ear)

	# 眼睛：大号亮眼 + 高光点
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.06, 0.11)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.16, 0.32, 0.62)
	eye_mat.emission_energy_multiplier = 0.55
	eye_mat.roughness = 0.12
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(1, 1, 1, 0.98)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1, 1, 1)
	dot_mat.emission_energy_multiplier = 1.2
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for sx in [-1.0, 1.0]:
		var eye := _sphere(_art, 0.078, 0.156, Vector3(sx * 0.095, 0.63, 0.212), eye_mat)
		_eyes.append(eye)
		var dot := _sphere(_art, 0.027, 0.054, Vector3(sx * 0.095 - 0.025, 0.668, 0.268), dot_mat, 10, 6)
		_eye_dots.append(dot)
	# 腮红（粉色扁球）
	var cheek_mat := StandardMaterial3D.new()
	cheek_mat.albedo_color = Color(1.0, 0.52, 0.60, 0.9)
	cheek_mat.emission_enabled = true
	cheek_mat.emission = Color(1.0, 0.42, 0.52)
	cheek_mat.emission_energy_multiplier = 0.35
	cheek_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for sx in [-1.0, 1.0]:
		var cheek := _sphere(_art, 0.055, 0.05, Vector3(sx * 0.175, 0.545, 0.198), cheek_mat, 12, 8)
		cheek.scale = Vector3(1.0, 0.72, 0.45)
	# 小嘴（三点组成微笑）
	var mouth_mat := StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.35, 0.10, 0.16)
	mouth_mat.emission_enabled = true
	mouth_mat.emission = Color(0.45, 0.12, 0.20)
	mouth_mat.emission_energy_multiplier = 0.3
	_sphere(_art, 0.020, 0.03, Vector3(0.0, 0.535, 0.242), mouth_mat, 8, 5)
	_sphere(_art, 0.017, 0.026, Vector3(-0.038, 0.545, 0.232), mouth_mat, 8, 5)
	_sphere(_art, 0.017, 0.026, Vector3(0.038, 0.545, 0.232), mouth_mat, 8, 5)

	# 头顶光环（金）+ 外层半透明辉光圈
	_halo = MeshInstance3D.new()
	var ts := TorusMesh.new()
	ts.inner_radius = 0.215
	ts.outer_radius = 0.285
	ts.rings = 28
	ts.ring_segments = 14
	_halo.mesh = ts
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.92, 0.58)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.86, 0.42)
	hm.emission_energy_multiplier = 1.6
	_halo.material_override = hm
	_halo.position = Vector3(0.0, 1.03, 0.0)
	_halo.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(_halo)

	_halo_glow = MeshInstance3D.new()
	var tg := TorusMesh.new()
	tg.inner_radius = 0.275
	tg.outer_radius = 0.36
	tg.rings = 28
	tg.ring_segments = 10
	_halo_glow.mesh = tg
	var hg := _glow_mat(Color(1.0, 0.85, 0.45))
	_halo_glow.material_override = hg
	_halo_glow.position = Vector3(0.0, 1.03, 0.0)
	_halo_glow.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_halo_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_art.add_child(_halo_glow)

	# 自身柔光，照亮脚下一小圈
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 0.55, 0.15)
	_light.light_color = _base_color
	_light.light_energy = 0.55
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	_art.add_child(_light)

	# 星尘
	_sparkle = CPUParticles3D.new()
	_sparkle.amount = 16
	_sparkle.lifetime = 1.5
	_sparkle.position = Vector3(0.0, 0.45, 0.0)
	_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 0.5
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 180.0
	_sparkle.gravity = Vector3(0.0, 0.6, 0.0)
	_sparkle.initial_velocity_min = 0.05
	_sparkle.initial_velocity_max = 0.3
	_sparkle.scale_amount_min = 0.22
	_sparkle.scale_amount_max = 0.55
	var q := SphereMesh.new()
	q.radius = 0.04
	q.height = 0.08
	q.radial_segments = 6
	q.rings = 3
	_sparkle.mesh = q
	_sparkle.material_override = _glow_mat(Color(1.0, 0.95, 0.72))
	_sparkle.emitting = true
	_art.add_child(_sparkle)

	# 摸头爱心（一次性喷射）
	_hearts = CPUParticles3D.new()
	_hearts.amount = 10
	_hearts.lifetime = 1.3
	_hearts.one_shot = true
	_hearts.emitting = false
	_hearts.position = Vector3(0.0, 0.62, 0.0)
	_hearts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_hearts.emission_sphere_radius = 0.22
	_hearts.direction = Vector3.UP
	_hearts.spread = 55.0
	_hearts.gravity = Vector3(0.0, 1.4, 0.0)
	_hearts.initial_velocity_min = 0.35
	_hearts.initial_velocity_max = 0.9
	_hearts.scale_amount_min = 0.5
	_hearts.scale_amount_max = 1.1
	var hs := SphereMesh.new()
	hs.radius = 0.055
	hs.height = 0.09
	hs.radial_segments = 8
	hs.rings = 5
	_hearts.mesh = hs
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(1.0, 0.42, 0.58)
	hmat.emission_enabled = true
	hmat.emission = Color(1.0, 0.32, 0.5)
	hmat.emission_energy_multiplier = 1.2
	_hearts.material_override = hmat
	_art.add_child(_hearts)

	# 说话气泡（始终面向相机、不被墙遮挡）
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.font_size = 48
	_bubble.outline_size = 14
	_bubble.modulate = Color(1, 1, 1, 0.98)
	_bubble.outline_modulate = Color(0.03, 0.05, 0.10, 0.9)
	_bubble.pixel_size = 0.006
	_bubble.position = Vector3(0.0, 1.34, 0.0)
	_bubble.visible = false
	add_child(_bubble)


# ---------------- 每帧 ----------------

func _process(delta: float) -> void:
	_t += delta
	if hero == null or not is_instance_valid(hero):
		if _bm == null or not is_instance_valid(_bm):
			_bm = get_tree().get_first_node_in_group("battle_manager")
		hero = _bm.hero if _bm != null and is_instance_valid(_bm) else null
		visible = hero != null
		if hero == null:
			return
	# 跟随：贴在英雄右上（相对相机方向），带缓动
	var cam := get_viewport().get_camera_3d()
	var right := Vector3.RIGHT
	if cam != null:
		right = cam.global_transform.basis.x
	var target: Vector3 = hero.global_position + right * FOLLOW_OFFSET.x + Vector3(0.0, FOLLOW_OFFSET.y, 0.0)
	target.y += sin(_t * 2.4) * 0.10 + _mood * 0.10
	global_position = global_position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	scale = scale.lerp(Vector3.ONE, clampf(delta * 8.0, 0.0, 1.0))
	# 朝向相机 + 光环自转
	if cam != null:
		var to_cam: Vector3 = cam.global_position - global_position
		if to_cam.length() > 0.05:
			look_at(global_position + to_cam, Vector3.UP)
	_update_art(delta)
	var vp := get_viewport().get_visible_rect().size
	if _layer != null:
		_layer.visible = true
	if _btn != null:
		_btn.position = _button_pos(vp)
	_update_hit(cam, vp)
	if _bubble != null and _bubble.visible:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if _low_cd > 0.0:
		_low_cd -= delta
	# 局势事件（0.35s 一次，够快也不费）
	_poll += delta
	if _poll >= POLL:
		_poll = 0.0
		_check_events()


## 眨眼 / 耳朵轻晃 / 呼吸 / 光环
func _update_art(delta: float) -> void:
	if _body != null:
		var br := sin(_t * 3.1)
		_body.scale = Vector3(1.0 + br * 0.025, 1.04 - br * 0.025, 1.0)
	if _head != null:
		_head.position.y = 0.62 + sin(_t * 3.1 + 0.6) * 0.012
	# 眨眼
	if _blink_t > 0.0:
		_blink_t -= delta
		var k: float = 0.12 if _blink_t > 0.0 else 1.0
		for e in _eyes:
			if is_instance_valid(e):
				e.scale.y = k
		for d in _eye_dots:
			if is_instance_valid(d):
				d.visible = _blink_t <= 0.0
	else:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_wait = randf_range(2.2, 4.6)
			_blink_t = 0.13
	# 耳朵轻晃
	for i in range(_ears.size()):
		var ear = _ears[i]
		if is_instance_valid(ear):
			var sx := -1.0 if i == 0 else 1.0
			ear.rotation.z = deg_to_rad(-sx * 22.0) + sin(_t * 2.6 + sx * 0.9) * 0.10
	# 光环自转 + 呼吸
	if _halo != null:
		_halo.rotation.y += delta * 1.6
		_halo.position.y = 1.03 + sin(_t * 2.0) * 0.015
	if _halo_glow != null:
		_halo_glow.rotation.y -= delta * 0.9
		_halo_glow.position.y = 1.03 + sin(_t * 2.0) * 0.015
	_mood = lerpf(_mood, 0.0, clampf(delta * 0.8, 0.0, 1.0))


## 模型身上的点击热区：投影跟随，点它=摸头（吞掉点击，不触发普攻/走位）
func _update_hit(cam: Camera3D, vp: Vector2) -> void:
	if _hit == null:
		return
	var show := false
	if cam != null and visible and hero != null and is_instance_valid(hero):
		var wp: Vector3 = global_position + Vector3(0.0, 0.5, 0.0)
		if not cam.is_position_behind(wp):
			var sp: Vector2 = cam.unproject_position(wp)
			var s: float = 150.0 * clampf(UiKit.scale(), 0.75, 1.5)
			if sp.x > -s and sp.x < vp.x + s and sp.y > -s and sp.y < vp.y + s:
				_hit.size = Vector2(s, s * 1.15)
				_hit.position = sp - _hit.size * 0.5
				show = true
	_hit.visible = show


func _check_events() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var k := int(hero.kills)
	var d := int(hero.deaths)
	if k != _last_kills:
		_last_kills = k
		react_cheer()
		_talk(str(LINES_KILL[randi() % LINES_KILL.size()]), 2.6)
	elif d != _last_deaths:
		_last_deaths = d
		react_sad()
		_talk(str(LINES_DIED[randi() % LINES_DIED.size()]), 2.6)
	elif hero.health > 0 and float(hero.health) / maxf(1.0, float(hero.max_health)) < 0.3 and _low_cd <= 0.0:
		_low_cd = 24.0
		_talk(str(LINES_LOW[randi() % LINES_LOW.size()]), 2.4)
	var towers := _tower_count()
	if _last_towers >= 0 and towers < _last_towers:
		_talk(str(LINES_TOWER[randi() % LINES_TOWER.size()]), 2.4)
		react_cheer()
	_last_towers = towers


func _tower_count() -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("turrets"):
		if is_instance_valid(t) and int(t.team) == Config.player_team and int(t.tower_type) >= 2:
			n += 1
	if n == 0:
		# 兜底：本队建筑总数（含水晶以外）
		for t in get_tree().get_nodes_in_group("turrets"):
			if is_instance_valid(t) and int(t.team) != Config.player_team:
				n += 0
	return n


# ---------------- 表现 ----------------

func react_cheer() -> void:
	_mood = 1.0
	if _art == null:
		return
	var tw := create_tween()
	tw.tween_property(_art, "scale", Vector3(1.16, 1.16, 1.16) * 0.95, 0.10)
	tw.tween_property(_art, "scale", Vector3(0.95, 0.95, 0.95), 0.26)
	if _sparkle != null:
		_sparkle.emitting = true


func react_sad() -> void:
	_mood = -1.0
	if _art == null:
		return
	var tw := create_tween()
	tw.tween_property(_art, "scale", Vector3(0.88, 0.82, 0.88) * 0.95, 0.25)
	tw.tween_property(_art, "scale", Vector3(0.95, 0.95, 0.95), 0.45)


func react_pet() -> void:
	react_cheer()
	if _sparkle != null:
		_sparkle.restart()
	if _hearts != null:
		_hearts.restart()


func _talk(text: String, dur: float) -> void:
	if _bubble != null:
		_bubble.text = text
		_bubble.visible = true
		_bubble_t = dur
	var _vs = get_node_or_null("/root/VoiceService")
	if _vs != null and text != "":
		_vs.call("speak", text, "灵宝")


## 外部（聊天里 @灵宝）调用：气泡 + 聊天频道都说一句
func respond(text: String) -> void:
	_talk(text, 3.4)
	if ChatService != null:
		ChatService.say_lingbao(text, true)


# ---------------- 交互 UI ----------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "LingbaoLayer"
	_layer.layer = HIT_LAYER
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	# 模型热区（主交互：直接点小精灵）
	_hit = Control.new()
	_hit.name = "LingbaoHit"
	_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hit.tooltip_text = "摸摸灵宝（右键换配色）"
	_hit.visible = false
	root.add_child(_hit)
	_hit.gui_input.connect(_on_hit_input)

	# 左下角按钮（备用入口：手机上模型可能被手挡住）
	_btn = Button.new()
	_btn.name = "LingbaoButton"
	_btn.text = "灵宝"
	_btn.custom_minimum_size = Vector2(96, 42)
	_btn.add_theme_font_size_override("font_size", int(round(17.0 * UiKit.scale())))
	_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var col := _base_color.darkened(0.25)
	_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", col, false))
	_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", col, false))
	_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", col, false))
	_btn.tooltip_text = "摸摸灵宝（右键换配色）"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.pressed.connect(_on_pet)
	_btn.gui_input.connect(_on_btn_input)
	root.add_child(_btn)
	var vp := get_viewport().get_visible_rect().size
	_btn.position = _button_pos(vp)


func _on_hit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_pet()
			_hit.accept_event()   # 吞掉点击：不触发普攻/走位
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cycle_color()
			_hit.accept_event()


func _on_btn_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cycle_color()


func _cycle_color() -> void:
	var i := Store.cycle_color()
	_base_color = Store.color()
	_apply_color(_base_color)
	_talk("换个颜色，好看吗（第 %d 种）" % (i + 1), 2.6)


func _apply_color(col: Color) -> void:
	if _mat_body != null:
		_mat_body.albedo_color = col.lightened(0.20)
		_mat_body.emission = col
	if _mat_glow != null:
		_mat_glow.albedo_color = Color(col.r, col.g, col.b, 0.35)
		_mat_glow.emission = col.lightened(0.25)
	if _light != null:
		_light.light_color = col
	if _btn != null:
		var c := col.darkened(0.25)
		_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", c, false))
		_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", c, false))
		_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", c, false))


func _on_pet() -> void:
	var aff := Store.add_affection(1)
	react_pet()
	_talk(str(LINES_PET[randi() % LINES_PET.size()]), 2.4)
	if _btn != null:
		_btn.tooltip_text = "好感度 %d · Lv.%d（右键换配色）" % [aff, Store.level()]
	if aff % 20 == 0:
		_talk("我升到 Lv.%d 啦！" % Store.level(), 3.0)


func _button_pos(vp: Vector2) -> Vector2:
	return Vector2(26.0, vp.y - 114.0)
