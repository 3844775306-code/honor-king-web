extends Node
## 灵宝 · 全局悬浮小精灵（autoload，任何界面都在：大厅 / 选人 / 备战 / 结算 / 联机）
## 战斗内由 3D 版 scripts/entities/Lingbao.gd 接管，本层检测到同组节点会自动隐藏，避免两只灵宝。
## 交互：点一下摸摸（+好感度）· 按住拖动换位置（本地记忆）· 右键换配色 · 聊天里 @灵宝 由本层接话。

const Store = preload("res://scripts/core/LingbaoStore.gd")
const LAYER := 130             # 高于结算页(110)、低于加载页(200)，所以结算时也能看见
const GROUP_3D := "lingbao"
const ART_SIZE := 180.0
const POS_KEY_X := "lingbao_pos_x"
const POS_KEY_Y := "lingbao_pos_y"

const LINES_PET := ["嘿嘿～", "好舒服", "再摸摸嘛", "最喜欢你了", "嗯…再来一下"]
const LINES_HELLO := ["我来啦，今天也一起加油～", "在呢在呢，我陪着你", "随时都在你旁边哦"]
const LINES_IDLE := ["要不要打一把呀？", "我在旁边看着呢", "挑个顺手的英雄吧", "今天想玩哪条路？", "慢慢来，别急～"]

var _layer: CanvasLayer = null
var _root: Control = null
var _spirit: Control = null
var _bubble: Panel = null
var _bubble_label: Label = null
var _bubble_t := 0.0
var _t := 0.0
var _scale := 1.0
var _color := Color.WHITE
var _aff := 0
var _hover := false
var _press := false
var _moved := false
var _pos_norm := Vector2(0.934, 0.795)
var _last_vp := Vector2.ZERO
var _check_t := 0.0
var _idle_t := 95.0
var _greeted := false
var _spark_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_color = Store.color()
	_aff = Store.affection()
	_pos_norm = Vector2(
		PlayerPrefs.opt_float(POS_KEY_X, 0.934),
		PlayerPrefs.opt_float(POS_KEY_Y, 0.795))
	_build()
	if ChatService != null:
		ChatService.lingbao_said.connect(_on_lingbao_said)
	_say(str(LINES_HELLO[randi() % LINES_HELLO.size()]), 3.2)
	set_process(true)


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "LingbaoOverlayLayer"
	_layer.layer = LAYER
	add_child(_layer)

	_root = Control.new()
	_root.name = "LingbaoOverlayRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)

	_spirit = SpiritArt.new()
	_spirit.name = "LingbaoSpirit"
	_spirit.host = self
	_spirit.mouse_filter = Control.MOUSE_FILTER_STOP
	_spirit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_root.add_child(_spirit)
	_spirit.gui_input.connect(_on_spirit_input)
	_spirit.mouse_entered.connect(func() -> void:
		_hover = true
		_spirit.queue_redraw())
	_spirit.mouse_exited.connect(func() -> void:
		_hover = false
		_spirit.queue_redraw())

	_bubble = Panel.new()
	_bubble.name = "LingbaoBubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel",
		UiKit.flat(0.94, 14, 1, Color(0.55, 0.78, 1.0, 0.55), Color(0.06, 0.09, 0.15, 0.94), 12.0, 10.0))
	_bubble.visible = false
	_root.add_child(_bubble)

	_bubble_label = Label.new()
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	_bubble_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_bubble_label.add_theme_constant_override("outline_size", 0)
	_bubble.add_child(_bubble_label)

	_relayout()


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_last_vp = vp
	_scale = clampf(vp.x / 2400.0, 0.68, 1.45)
	# 手机/iPad 上灵宝本体偏小，放大触摸目标与立绘；桌面保持原尺寸
	var s := ART_SIZE * _scale * (1.35 if Config.on_mobile() else 1.0)
	if _spirit != null:
		_spirit.size = Vector2(s, s)
		_spirit.pivot_offset = _spirit.size * 0.5
		var center := Vector2(_pos_norm.x * vp.x, _pos_norm.y * vp.y)
		_spirit.position = Vector2(
			clampf(center.x - s * 0.5, 0.0, maxf(0.0, vp.x - s)),
			clampf(center.y - s * 0.5, 0.0, maxf(0.0, vp.y - s)))
	if _bubble != null and _bubble.visible:
		_place_bubble()


func _process(delta: float) -> void:
	_t += delta
	if _spark_t > 0.0:
		_spark_t = maxf(0.0, _spark_t - delta * 2.0)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false
	if _spirit != null:
		_spirit.queue_redraw()
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.3
		_sync_visible()
		var vp := get_viewport().get_visible_rect().size
		if vp != _last_vp:
			_relayout()
	if _layer != null and _layer.visible:
		_idle_t -= delta
		if _idle_t <= 0.0:
			_idle_t = randf_range(70.0, 130.0)
			if _bubble_t <= 0.0:
				_say(str(LINES_IDLE[randi() % LINES_IDLE.size()]), 3.0)


## 战斗中有 3D 灵宝 → 隐藏本层（回大厅自动恢复并打招呼一次）
func _sync_visible() -> void:
	var busy := false
	var n3 = get_tree().get_first_node_in_group(GROUP_3D)
	if n3 != null and is_instance_valid(n3) and n3.is_inside_tree():
		busy = true
	if _layer.visible == busy:
		_layer.visible = not busy
		if not busy and not _greeted:
			_greeted = true
			_say(str(LINES_HELLO[randi() % LINES_HELLO.size()]), 3.2)


# ---------------- 说话 ----------------

func _say(text: String, dur: float = 3.4) -> void:
	var t := str(text).strip_edges()
	if t == "" or _bubble == null:
		return
	var fs := int(round(22.0 * UiKit.scale()))
	_bubble_label.add_theme_font_size_override("font_size", fs)
	_bubble_label.text = t
	var f := UiKit.font()
	var raw_w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var max_inner := 430.0 * _scale
	var inner := clampf(raw_w, 150.0, max_inner)
	var lines := maxf(1.0, ceil(raw_w / maxf(inner, 1.0)))
	var bh := lines * float(fs) * 1.45 + 20.0
	_bubble.set_meta("bw", inner + 30.0)
	_bubble.set_meta("bh", bh)
	_bubble.visible = true
	_bubble_t = dur
	_place_bubble()


func _place_bubble() -> void:
	var bw: float = float(_bubble.get_meta("bw", 320.0))
	var bh: float = float(_bubble.get_meta("bh", 80.0))
	var vp := get_viewport().get_visible_rect().size
	_bubble.size = Vector2(bw, bh)
	var bx: float = clampf(_spirit.position.x + _spirit.size.x * 0.5 - bw * 0.5, 6.0,
		maxf(6.0, vp.x - bw - 6.0))
	var by: float = maxf(6.0, _spirit.position.y - bh - 8.0)
	_bubble.position = Vector2(bx, by)
	_bubble_label.position = Vector2(15.0, 9.0)
	_bubble_label.size = Vector2(bw - 30.0, bh - 18.0)


## 供 ChatService（大厅里 @灵宝）调用：气泡 + 聊天频道
func respond(text: String) -> void:
	_say(text, 3.6)
	if ChatService != null:
		ChatService.say_lingbao(text, NetSession.mode == NetSession.Mode.HOST)


func _on_lingbao_said(text: String) -> void:
	_say(text, 3.4)


# ---------------- 交互 ----------------

func _on_spirit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press = true
				_moved = false
			else:
				if _press and not _moved:
					_pet()
				_press = false
				_save_pos()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var i: int = Store.cycle_color()
			_color = Store.color()
			_say("换个颜色，好看吗（第 %d 种）" % (i + 1), 2.6)
			_spirit.queue_redraw()
	elif event is InputEventMouseMotion and _press:
		var mm: InputEventMouseMotion = event
		var d: Vector2 = mm.relative
		if d.length() > 0.5:
			_moved = true
			var vp := get_viewport().get_visible_rect().size
			_spirit.position = (_spirit.position + d).clamp(Vector2.ZERO,
				Vector2(maxf(0.0, vp.x - _spirit.size.x), maxf(0.0, vp.y - _spirit.size.y)))
			_pos_norm = Vector2(
				(_spirit.position.x + _spirit.size.x * 0.5) / maxf(1.0, vp.x),
				(_spirit.position.y + _spirit.size.y * 0.5) / maxf(1.0, vp.y))
			if _bubble.visible:
				_place_bubble()


func _pet() -> void:
	_aff = Store.add_affection(1)
	_spark_t = 1.0
	var line := str(LINES_PET[randi() % LINES_PET.size()])
	if _aff % 20 == 0:
		line = "我升到 Lv.%d 啦！" % Store.level()
	_say(line, 2.6)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_spirit, "scale", Vector2(1.16, 1.16), 0.10)
	tw.chain().tween_property(_spirit, "scale", Vector2.ONE, 0.22)


func _save_pos() -> void:
	PlayerPrefs.set_opt(POS_KEY_X, _pos_norm.x)
	PlayerPrefs.set_opt(POS_KEY_Y, _pos_norm.y)


# ---------------- 绘制 ----------------

func _paint(c: Control) -> void:
	var sz: float = minf(c.size.x, c.size.y)
	if sz <= 1.0:
		return
	var center: Vector2 = c.size * 0.5 + Vector2(0.0, sin(_t * 2.1) * sz * 0.035)
	var r: float = sz * 0.205
	# 外发光
	for i in range(4):
		var k: float = 1.0 - float(i) * 0.2
		c.draw_circle(center, r * (1.45 + 0.2 * float(i)) * k,
			Color(_color.r, _color.g, _color.b, 0.05))
	# 光环
	var halo_r: float = r * 1.62
	var rot: float = _t * 0.9
	c.draw_arc(center + Vector2(0.0, -r * 0.12), halo_r, rot, rot + PI * 1.55, 40,
		Color(1.0, 0.86, 0.45, 0.85), maxf(2.0, sz * 0.016), true)
	# 身体 + 高光
	c.draw_circle(center, r, _color)
	c.draw_circle(center + Vector2(0.0, -r * 0.3), r * 0.74, _color.lightened(0.34))
	# 小手
	c.draw_circle(center + Vector2(-r * 1.02, r * 0.44), r * 0.22, _color.darkened(0.12))
	c.draw_circle(center + Vector2(r * 1.02, r * 0.44), r * 0.22, _color.darkened(0.12))
	# 眼睛（每 4.6 秒眨一次）
	var blink: bool = fmod(_t + 1.3, 4.6) > 4.42
	var eye_r: float = r * 0.17
	for s in [-1.0, 1.0]:
		var ep: Vector2 = center + Vector2(s * r * 0.34, -r * 0.06)
		if blink:
			c.draw_line(ep + Vector2(-eye_r, 0.0), ep + Vector2(eye_r, 0.0),
				Color(0.07, 0.09, 0.15), maxf(2.0, sz * 0.012))
		else:
			c.draw_circle(ep, eye_r, Color(0.07, 0.09, 0.15))
			c.draw_circle(ep + Vector2(-eye_r * 0.3, -eye_r * 0.35), eye_r * 0.32, Color(1, 1, 1, 0.92))
	# 腮红
	c.draw_circle(center + Vector2(-r * 0.62, r * 0.2), r * 0.13, Color(1.0, 0.55, 0.62, 0.5))
	c.draw_circle(center + Vector2(r * 0.62, r * 0.2), r * 0.13, Color(1.0, 0.55, 0.62, 0.5))
	# 嘴
	c.draw_arc(center + Vector2(0.0, r * 0.34), r * 0.2, 0.15 * PI, 0.85 * PI, 18,
		Color(0.12, 0.10, 0.18, 0.9), maxf(1.5, sz * 0.011), true)
	# 悬停光圈 + 名字/好感度
	if _hover:
		c.draw_arc(center, r * 1.34, 0.0, TAU, 48, Color(1.0, 0.95, 0.7, 0.45), maxf(1.5, sz * 0.008), true)
		UiKit.text(c, Vector2(0.0, c.size.y - sz * 0.02),
			"%s · 好感度 %d · Lv.%d" % [Store.name(), _aff, Store.level()],
			int(round(11.0 * UiKit.scale())), Color(0.90, 0.95, 1.0),
			HORIZONTAL_ALIGNMENT_CENTER, c.size.x)
	# 摸摸时的小星星
	if _spark_t > 0.0:
		var k2: float = _spark_t
		for i in range(5):
			var ang: float = _t * 3.0 + float(i) * TAU / 5.0
			var sp: Vector2 = center + Vector2(cos(ang), sin(ang) * 0.72) * r * (1.55 + 0.3 * (1.0 - k2))
			c.draw_circle(sp, maxf(1.2, r * 0.1 * k2), Color(1.0, 0.95, 0.6, k2))


class SpiritArt extends Control:
	var host = null

	func _draw() -> void:
		if host != null:
			host._paint(self)
