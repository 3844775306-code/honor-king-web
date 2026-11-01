extends Control
## 左下角无面板聊天区：直接画文字（名字=阵营色，内容=白色）+ 底部「聊天/语音」按钮与输入条。
## 由 ChatService 自动创建，通过 ChatService.message 信号喂数据。

const MX := 26.0            # 左边距
const BOTTOM := 128.0       # 消息区底部距离
const MAX_SHOW := 6         # 最多同时显示 6 条
const LIFE := 13.0          # 停留时间
const FADE := 1.6

var _msgs: Array = []       # {name, text, col, t}
var _edit: LineEdit = null
var _chat_btn: Button = null
var _mic_btn: Button = null
var _close_btn: Button = null
var _mobile := false
var _btn_size := Vector2(88, 42)


func _ready() -> void:
	_mobile = Config.on_mobile()
	_btn_size = Vector2(132, 60) if _mobile else Vector2(88, 42)
	name = "ChatBox"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 80
	_build_widgets()
	ChatService.message.connect(_on_message)
	set_process(true)


func _build_widgets() -> void:
	var fs := int(round((22.0 if _mobile else 17.0) * UiKit.scale()))
	_chat_btn = _mk_btn("聊天", fs, UiKit.C_TEAM0)
	_chat_btn.name = "ChatToggle"
	_chat_btn.tooltip_text = "打开聊天输入（Enter 也可）"
	_chat_btn.pressed.connect(_toggle_input)
	add_child(_chat_btn)
	_mic_btn = _mk_btn("语音", fs, UiKit.C_GOLD)
	_mic_btn.name = "ChatVoice"
	_mic_btn.tooltip_text = "语音输入（Windows 语音识别）"
	_mic_btn.pressed.connect(func(): ChatService.listen_voice())
	add_child(_mic_btn)
	_close_btn = _mk_btn("✕", fs, UiKit.C_TEAM1)
	_close_btn.name = "ChatClose"
	_close_btn.visible = false
	_close_btn.pressed.connect(_close_input)
	add_child(_close_btn)
	_edit = LineEdit.new()
	_edit.name = "ChatInput"
	_edit.placeholder_text = "说点什么…（Enter 发送 / Esc 关闭）"
	_edit.max_length = 40
	_edit.visible = false
	_edit.add_theme_font_size_override("font_size", int(round((24.0 if _mobile else 20.0) * UiKit.scale())))
	_edit.add_theme_color_override("font_color", Color(1, 1, 1, 0.97))
	_edit.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.45))
	var st: StyleBoxFlat = UiKit.flat(0.60, 10, 2, Color(0.55, 0.78, 1.0, 0.85),
		Color(0.02, 0.035, 0.06, 0.80), 10.0, 0.0)
	_edit.add_theme_stylebox_override("normal", st)
	_edit.add_theme_stylebox_override("focus", st)
	_edit.text_submitted.connect(func(t): _submit(t))
	_edit.gui_input.connect(_on_edit_input)
	add_child(_edit)


func _mk_btn(txt: String, fs: int, col: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = _btn_size
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", col, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", col, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", col, false))
	b.focus_mode = Control.FOCUS_NONE
	return b


func _process(_delta: float) -> void:
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp
	# 输入行贴在消息区下面：聊天 / 输入框 / 语音 / 关闭
	var row_y: float = vp.y - BOTTOM + (40.0 if _mobile else 66.0)
	var x: float = MX
	var step: float = _btn_size.x + 8.0
	_chat_btn.position = Vector2(x, row_y)
	x += step
	if _edit.visible:
		_edit.position = Vector2(x, row_y - 2.0)
		_edit.size = Vector2(clampf(vp.x * (0.34 if _mobile else 0.30), 320.0, 640.0),
			54.0 if _mobile else 46.0)
		x += _edit.size.x + 8.0
	_mic_btn.position = Vector2(x, row_y)
	x += step
	_close_btn.position = Vector2(x, row_y)
	# 消息老化
	var t := Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for m in _msgs:
		if t - float(m["t"]) < LIFE + FADE:
			keep.append(m)
	_msgs = keep
	queue_redraw()


func _alpha(m: Dictionary) -> float:
	var age: float = Time.get_ticks_msec() / 1000.0 - float(m["t"])
	if age < LIFE:
		return 1.0
	return clampf(1.0 - (age - LIFE) / FADE, 0.0, 1.0)


func _on_message(from_name: String, team: int, text: String, is_self: bool) -> void:
	var col: Color = UiKit.C_GOLD if is_self else (
		Color(0.55, 0.80, 1.0) if team == Config.player_team else Color(1.0, 0.55, 0.50))
	if from_name == "系统":
		col = Color(1.0, 0.86, 0.45)
	_msgs.append({"name": from_name, "text": text, "col": col, "t": Time.get_ticks_msec() / 1000.0})
	if _msgs.size() > 30:
		_msgs = _msgs.slice(_msgs.size() - 30)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var f := UiKit.font()
	var fs: int = int(round(21.0 * UiKit.scale()))
	var outline: int = maxi(3, int(round(fs * 0.24)))
	var wrap_w: float = clampf(vp.x * 0.34, 420.0, 900.0)
	var line_h: float = fs * 1.42
	var y: float = vp.y - BOTTOM
	var shown := 0
	for i in range(_msgs.size() - 1, -1, -1):
		if shown >= MAX_SHOW:
			break
		var m: Dictionary = _msgs[i]
		var a: float = _alpha(m)
		if a <= 0.02:
			continue
		shown += 1
		var head := str(m["name"]) + "："
		var body := str(m["text"])
		var col: Color = m["col"]
		var head_w: float = f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var body_w: float = f.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var rows: int = maxi(1, int(ceil(body_w / wrap_w)))
		y -= line_h * float(rows)
		# 名字（阵营色）
		draw_string_outline(f, Vector2(MX, y + fs), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline,
			Color(0.02, 0.02, 0.03, 0.85 * a))
		draw_string(f, Vector2(MX, y + fs), head, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(col.r, col.g, col.b, col.a * a))
		# 内容（白色，长句自动换行）
		draw_string_outline(f, Vector2(MX + head_w, y + fs), body, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs, outline,
			Color(0.02, 0.02, 0.03, 0.85 * a))
		draw_multiline_string(f, Vector2(MX + head_w, y + fs), body, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, fs, -1,
			Color(0.96, 0.97, 1.0, 0.97 * a))
		y -= line_h * 0.24
	if shown == 0 and not _edit.visible:
		# 空态提示：不抢镜，淡一点
		var tip := "按 Enter 或点「聊天」和队友说话"
		draw_string_outline(f, Vector2(MX, vp.y - BOTTOM + 22.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(round(15.0 * UiKit.scale())), 3, Color(0, 0, 0, 0.35))
		draw_string(f, Vector2(MX, vp.y - BOTTOM + 22.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(round(15.0 * UiKit.scale())), Color(1, 1, 1, 0.22))


func _input(event: InputEvent) -> void:
	if _edit == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			if not _edit.visible and not _modal_open():
				_open_input()
				get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and _edit.visible:
			_close_input()
			get_viewport().set_input_as_handled()


## 商店/英雄面板等全屏面板打开时，别抢 Enter 键
func _modal_open() -> bool:
	return UiManager.blocks_gameplay_input() and not ChatService.typing


func _toggle_input() -> void:
	if _edit.visible:
		_close_input()
	else:
		_open_input()


func _open_input() -> void:
	_edit.visible = true
	_close_btn.visible = true
	_edit.text = ""
	_edit.grab_focus()
	ChatService.typing = true
	UiManager.chat_typing = true


func _close_input() -> void:
	_edit.visible = false
	_close_btn.visible = false
	_edit.release_focus()
	ChatService.typing = false
	UiManager.chat_typing = false


func _submit(text: String) -> void:
	var t := text.strip_edges()
	_close_input()
	if t == "":
		return
	ChatService.send_player(t)


## 语音识别结果回填输入框，玩家可先改再发
func fill_input(text: String) -> void:
	_open_input()
	_edit.text = text
	_edit.caret_column = _edit.text.length()


func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_close_input()
		get_viewport().set_input_as_handled()
