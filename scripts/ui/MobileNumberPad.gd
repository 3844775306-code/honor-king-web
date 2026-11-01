extends Control
## 移动端数字输入弹窗：不依赖系统虚拟键盘（iOS Safari/原生 WebView 常唤不起键盘）
## 用途：联机大厅「主机 IP / 端口」等只需数字（和小数点）的输入框

var _le: LineEdit = null
var _title := ""
var _allow_dot := false
var _max_len := 15
var _buf := ""
var _disp: Label = null
var _layer: CanvasLayer = null


static func open(le: LineEdit, title: String, allow_dot: bool = false, max_len: int = 15) -> void:
	if le == null or not is_instance_valid(le):
		return
	var p = load("res://scripts/ui/MobileNumberPad.gd").new()
	p._le = le
	p._title = title
	p._allow_dot = allow_dot
	p._max_len = max_len
	var layer := CanvasLayer.new()
	layer.name = "MobileNumberPadLayer"
	layer.layer = 500
	p._layer = layer
	layer.add_child(p)
	var host: Node = le.get_tree().current_scene
	if host == null:
		host = le.get_tree().root
	host.add_child(layer)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_buf = str(_le.text) if _le != null and is_instance_valid(_le) else ""
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var card := Panel.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -280.0
	card.offset_right = 280.0
	card.offset_top = -330.0
	card.offset_bottom = 330.0
	card.add_theme_stylebox_override("panel", UiKit.panel_style(0.98, 18.0))
	add_child(card)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24.0
	vb.offset_top = 18.0
	vb.offset_right = -24.0
	vb.offset_bottom = -18.0
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)
	var title := Label.new()
	title.text = _title
	title.add_theme_font_override("font", UiKit.font())
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiKit.C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	_disp = Label.new()
	_disp.add_theme_font_override("font", UiKit.font())
	_disp.add_theme_font_size_override("font_size", 34)
	_disp.add_theme_color_override("font_color", UiKit.C_TEXT)
	_disp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_disp.custom_minimum_size = Vector2(0, 56)
	vb.add_child(_disp)
	_refresh_disp()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for ch in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]:
		grid.add_child(_mk_key(ch))
	grid.add_child(_mk_key("." if _allow_dot else "清"))
	if _allow_dot:
		grid.add_child(_mk_key("0"))
		grid.add_child(_mk_key("←"))
	else:
		grid.add_child(_mk_key("0"))
		grid.add_child(_mk_key("←"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
	var b_cancel := _mk_btn("取消", UiKit.C_DANGER, false)
	b_cancel.pressed.connect(_cancel)
	row.add_child(b_cancel)
	var b_clear := _mk_btn("清空", UiKit.C_TEAM0, false)
	b_clear.pressed.connect(_clear)
	row.add_child(b_clear)
	var b_ok := _mk_btn("确定", UiKit.C_HEAL, true)
	b_ok.pressed.connect(_ok)
	row.add_child(b_ok)


func _mk_key(ch: String) -> Button:
	var b := Button.new()
	b.text = ch
	b.custom_minimum_size = Vector2(160.0, 72.0)
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", UiKit.C_TEXT)
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_TEAM0, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_TEAM0, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_TEAM0, false))
	if ch == "←":
		b.pressed.connect(_del)
	elif ch == "清":
		b.pressed.connect(_clear)
	else:
		b.pressed.connect(_press.bind(ch))
	return b


func _mk_btn(txt: String, accent: Color, filled: bool) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0.0, 64.0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", UiKit.C_TEXT)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))
	return b


func _press(ch: String) -> void:
	if ch == ".":
		# IP 需要多个点（如 192.168.1.10）：只禁止开头/连续点
		if not _allow_dot or _buf == "" or _buf.ends_with("."):
			return
	if _buf.length() >= _max_len:
		return
	_buf += ch
	_refresh_disp()


func _del() -> void:
	if _buf.length() > 0:
		_buf = _buf.substr(0, _buf.length() - 1)
		_refresh_disp()


func _clear() -> void:
	_buf = ""
	_refresh_disp()


func _refresh_disp() -> void:
	if _disp != null:
		_disp.text = _buf if _buf != "" else "输入数字"


func _ok() -> void:
	if _le != null and is_instance_valid(_le):
		_le.text = _buf
		_le.caret_column = _le.text.length()
		_le.text_changed.emit(_le.text)
		_le.text_submitted.emit(_le.text)
	_close()


func _cancel() -> void:
	_close()


func _close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()
