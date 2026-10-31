extends Node3D
## 灵宝：跟在玩家英雄身边的小精灵（程序化建模，无美术资源）。
## 会看局势说话（击杀/阵亡/残血/推塔）、能摸（好感度）、能聊（聊天里 @灵宝 会回话）。
## 创建：BattleManager._create_player_hero() 里 LingbaoScript.ensure(self)

const Store = preload("res://scripts/core/LingbaoStore.gd")
const GROUP := "lingbao"
const FOLLOW_OFFSET := Vector2(1.05, 1.75)   # 相机右 / 世界高度
const POLL := 0.35

const LINES_HELLO := ["我来啦！这局好好打～", "又见面啦，一起上分！", "今天也要赢哦"]
const LINES_KILL := ["厉害！这波帅到我了", "刚才那下好准", "继续压，别停", "对面心态崩了吧"]
const LINES_DIED := ["呜…别难过，复活再战", "小心点嘛", "下次我先帮你探草"]
const LINES_LOW := ["血不多了，先回城吧", "先撤一下，别硬拼"]
const LINES_TOWER := ["塔推掉了，好耶", "这波推塔漂亮"]
const LINES_PET := ["嘿嘿～", "好舒服", "再摸摸嘛", "最喜欢你了", "嗯…再来一下"]
const LINES_TALK := ["我在呢，说给我听", "嗯嗯，我听着呢", "别紧张，我在你旁边"]

var hero = null
var _bm = null
var _body: MeshInstance3D = null
var _head: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _bubble: Label3D = null
var _sparkle: CPUParticles3D = null
var _base_color := Color.WHITE
var _t := 0.0
var _poll := 0.0
var _bubble_t := 0.0
var _last_kills := 0
var _last_deaths := 0
var _low_cd := 0.0
var _last_towers := -1
var _btn: Button = null
var _layer: CanvasLayer = null
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


# ---------------- 建模 ----------------

func _build_art() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _base_color
	mat.emission_enabled = true
	mat.emission = _base_color
	mat.emission_energy_multiplier = 0.55
	mat.roughness = 0.35
	# 身体：略压扁的球
	_body = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.34
	bs.height = 0.56
	bs.radial_segments = 20
	bs.rings = 12
	_body.mesh = bs
	_body.material_override = mat
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)
	# 头
	_head = MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.30
	hs.height = 0.56
	hs.radial_segments = 20
	hs.rings = 12
	_head.mesh = hs
	_head.position = Vector3(0.0, 0.42, 0.0)
	_head.material_override = mat
	_head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_head)
	# 眼睛（深色小球）
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.06, 0.07, 0.12)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.20, 0.55, 0.95)
	eye_mat.emission_energy_multiplier = 0.7
	for sx in [-0.11, 0.11]:
		var e := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.075
		es.height = 0.15
		es.radial_segments = 12
		es.rings = 8
		e.mesh = es
		e.material_override = eye_mat
		e.position = Vector3(sx, 0.44, 0.26)
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(e)
	# 头顶光环
	_halo = MeshInstance3D.new()
	var ts := TorusMesh.new()
	ts.inner_radius = 0.40
	ts.outer_radius = 0.47
	ts.rings = 24
	ts.ring_segments = 12
	_halo.mesh = ts
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(1.0, 0.90, 0.55)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.85, 0.42)
	hm.emission_energy_multiplier = 1.1
	_halo.material_override = hm
	_halo.position = Vector3(0.0, 0.78, 0.0)
	_halo.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	# 星尘
	_sparkle = CPUParticles3D.new()
	_sparkle.amount = 16
	_sparkle.lifetime = 1.5
	_sparkle.position = Vector3(0, 0.3, 0)
	_sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparkle.emission_sphere_radius = 0.55
	_sparkle.direction = Vector3.UP
	_sparkle.spread = 180.0
	_sparkle.gravity = Vector3(0, 0.6, 0)
	_sparkle.initial_velocity_min = 0.05
	_sparkle.initial_velocity_max = 0.35
	_sparkle.scale_amount_min = 0.25
	_sparkle.scale_amount_max = 0.7
	var q := SphereMesh.new()
	q.radius = 0.05
	q.height = 0.1
	q.radial_segments = 6
	q.rings = 3
	_sparkle.mesh = q
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.95, 0.72)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.92, 0.62)
	sm.emission_energy_multiplier = 1.4
	_sparkle.material_override = sm
	_sparkle.emitting = true
	add_child(_sparkle)
	# 说话气泡（始终面向相机、不被墙遮挡）
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.font_size = 48
	_bubble.outline_size = 14
	_bubble.modulate = Color(1, 1, 1, 0.98)
	_bubble.outline_modulate = Color(0.03, 0.05, 0.10, 0.9)
	_bubble.pixel_size = 0.006
	_bubble.position = Vector3(0.0, 1.30, 0.0)
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
	if _halo != null:
		_halo.rotation.y += delta * 1.6
	if _body != null:
		_body.scale = Vector3(1.0 + sin(_t * 3.1) * 0.02, 1.0 - sin(_t * 3.1) * 0.02, 1.0)
	_mood = lerpf(_mood, 0.0, clampf(delta * 0.8, 0.0, 1.0))
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
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.22, 1.22, 1.22), 0.12)
	tw.chain().tween_property(self, "scale", Vector3.ONE, 0.26)
	if _sparkle != null:
		_sparkle.emitting = true


func react_sad() -> void:
	_mood = -1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(0.88, 0.82, 0.88), 0.25)
	tw.chain().tween_property(self, "scale", Vector3.ONE, 0.45)


func react_pet() -> void:
	react_cheer()
	if _sparkle != null:
		_sparkle.restart()


func _talk(text: String, dur: float) -> void:
	if _bubble != null:
		_bubble.text = text
		_bubble.visible = true
		_bubble_t = dur


## 外部（聊天里 @灵宝）调用：气泡 + 聊天频道都说一句
func respond(text: String) -> void:
	_talk(text, 3.4)
	if ChatService != null:
		ChatService.say_lingbao(text, true)


# ---------------- 交互 UI ----------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "LingbaoLayer"
	_layer.layer = 46
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
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
	_btn.position = Vector2(26.0, get_viewport().get_visible_rect().size.y - 114.0)


func _on_btn_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var i := Store.cycle_color()
		_base_color = Store.color()
		_apply_color(_base_color)
		_talk("换个颜色，好看吗（第 %d 种）" % (i + 1), 2.6)


func _apply_color(col: Color) -> void:
	for n in [_body, _head]:
		if n != null and n.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = n.material_override
			m.albedo_color = col
			m.emission = col
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
