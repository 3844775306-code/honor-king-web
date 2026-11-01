extends Control
## 3D 开机动画之后的账号入口：登录已有云端账号 / 新建账号。
## 同设备同一账号在 30 天内免登录；登录后显示「开始游戏」，由大厅接 2D 过渡动画进主菜单。

signal start_requested

var _user: LineEdit
var _pass: LineEdit
var _title: Label
var _hint: Label
var _status: Label
var _primary: Button
var _switch: Button
var _form_box: VBoxContainer
var _start_box: VBoxContainer
var _welcome: Label
var _busy := false
var _mode_new := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	_build()
	if AccountService.has_valid_session():
		_show_start(AccountService.session_username(), true)
	else:
		_show_form(AccountService.last_username())


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0.006, 0.010, 0.022, 0.97)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	# 顶部/底部金色细线，延续开机画面的电影感
	var top_line := ColorRect.new()
	top_line.color = Color(0.83, 0.66, 0.28, 0.55)
	top_line.position = Vector2(0.0, 80.0)
	top_line.size = Vector2(1.0, 2.0)
	add_child(top_line)
	var bottom_line := ColorRect.new()
	bottom_line.color = top_line.color
	bottom_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_line.position.y = -82.0
	bottom_line.size.y = 2.0
	add_child(bottom_line)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780.0, 0.0)
	panel.add_theme_stylebox_override("panel",
		UiKit.skin_chip(Color(0.035, 0.050, 0.080, 0.97), 0.98, 20))
	center.add_child(panel)
	var outer := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 42)
	panel.add_child(outer)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	outer.add_child(col)

	var brand := Label.new()
	brand.text = "H O N O R   K I N G"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_override("font", UiKit.font())
	brand.add_theme_font_size_override("font_size", 17)
	brand.add_theme_color_override("font_color", Color(0.62, 0.76, 0.96, 0.72))
	col.add_child(brand)
	_title = _lab("登录云端账号", 44, Color(1.0, 0.93, 0.76))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_hint = _lab("同一设备同一账号 30 天内免登录", 17, Color(0.62, 0.72, 0.88, 0.78))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)

	_form_box = VBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 10)
	col.add_child(_form_box)
	_user = _edit("用户名", false)
	_user.text = AccountService.last_username()
	_form_box.add_child(_field_row("用户名", _user))
	_pass = _edit("密码（至少 4 位）", true)
	_pass.text_submitted.connect(func(_t: String) -> void: _do_primary())
	_form_box.add_child(_field_row("密码", _pass))
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_form_box.add_child(btn_row)
	_primary = _btn("登 录", UiKit.C_GOLD, true)
	_primary.pressed.connect(_do_primary)
	btn_row.add_child(_primary)
	_switch = _btn("新建账号", UiKit.C_TEAM0, false)
	_switch.pressed.connect(_toggle_mode)
	btn_row.add_child(_switch)
	_status = _lab("", 16, UiKit.C_DANGER)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)

	_start_box = VBoxContainer.new()
	_start_box.add_theme_constant_override("separation", 14)
	_start_box.visible = false
	col.add_child(_start_box)
	_welcome = _lab("", 22, Color(0.78, 0.90, 1.0))
	_welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_box.add_child(_welcome)
	var start_btn := _btn("开 始 游 戏", UiKit.C_GOLD, true)
	start_btn.custom_minimum_size = Vector2(0, 66)
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.pressed.connect(func() -> void:
		if not _busy:
			_busy = true
			start_btn.disabled = true
			start_requested.emit())
	_start_box.add_child(start_btn)
	var switch_btn := _btn("切换账号", UiKit.C_TEAM0, false)
	switch_btn.pressed.connect(_on_switch_account)
	_start_box.add_child(switch_btn)


func _show_form(prefill: String = "") -> void:
	_busy = false
	_form_box.visible = true
	_start_box.visible = false
	_mode_new = false
	if prefill != "":
		_user.text = prefill
	_refresh_mode()
	_pass.text = ""
	_status.text = ""
	_pass.grab_focus()


func _show_start(username: String, remembered: bool) -> void:
	_busy = false
	_form_box.visible = false
	_start_box.visible = true
	_title.text = "欢迎回来" if remembered else "登录成功"
	_hint.text = "本机已保存登录 · 30 天内免登录" if remembered else "云端数据已就绪"
	_welcome.text = "召唤师 · %s" % username
	_status.text = ""


func _on_switch_account() -> void:
	AccountService.sign_out()
	_show_form("")


func _toggle_mode() -> void:
	_mode_new = not _mode_new
	_status.text = ""
	_refresh_mode()


func _refresh_mode() -> void:
	if _mode_new:
		_title.text = "创建云端账号"
		_hint.text = "注册后自动登录，并同步本机段位与对战纪录"
		_primary.text = "创建并登录"
		_switch.text = "返回登录"
	else:
		_title.text = "登录云端账号"
		_hint.text = "同一设备同一账号 30 天内免登录"
		_primary.text = "登 录"
		_switch.text = "新建账号"


func _do_primary() -> void:
	if _busy:
		return
	var u := _user.text.strip_edges()
	var p := _pass.text
	if u.length() < 2:
		_status.text = "请输入至少 2 个字符的用户名"
		return
	if p.length() < 4:
		_status.text = "密码至少 4 位"
		return
	_busy = true
	_set_enabled(false)
	_status.text = "正在创建账号..." if _mode_new else "正在登录云端账号..."
	if _mode_new:
		AccountService.register(get_tree(), u, p, _on_auth_result)
	else:
		AccountService.login(get_tree(), u, p, _on_auth_result)


func _on_auth_result(ok: bool, msg: String) -> void:
	_busy = false
	_set_enabled(true)
	if not ok:
		_status.text = msg
		return
	_show_start(_user.text.strip_edges(), false)
	_status.text = msg


func _set_enabled(v: bool) -> void:
	_primary.disabled = not v
	_switch.disabled = not v
	_user.editable = v
	_pass.editable = v


# ==================== 小控件 ====================

func _lab(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", UiKit.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 52)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_override("font", UiKit.font())
	e.add_theme_font_size_override("font_size", 21)
	e.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	e.add_theme_color_override("font_placeholder_color", Color(0.42, 0.52, 0.68, 0.85))
	e.add_theme_stylebox_override("normal",
		UiKit.skin_chip(Color(0.045, 0.060, 0.090, 0.94), 0.9, 9))
	e.add_theme_stylebox_override("focus",
		UiKit.skin_chip(Color(0.065, 0.085, 0.125, 0.98), 0.98, 9))
	UiKit.bind_mobile_text_edit(e, placeholder)
	return e


func _field_row(label_txt: String, edit: LineEdit) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lab := _lab(label_txt, 18, Color(0.68, 0.78, 0.92))
	lab.custom_minimum_size = Vector2(86, 0)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	row.add_child(edit)
	return row


func _btn(txt: String, accent: Color, filled: bool) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 21)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))
	b.add_theme_color_override("font_color", Color(0.06, 0.05, 0.02) if filled else Color(0.92, 0.96, 1.0))
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.05, 0.02) if filled else Color.WHITE)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b
