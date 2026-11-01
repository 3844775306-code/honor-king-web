extends Control
## 单机暂停覆盖层：P 暂停/继续。节点常驻（process_mode=ALWAYS），非暂停时鼠标穿透。

var _dim: ColorRect = null
var _panel: Panel = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -220.0
	_panel.offset_right = 220.0
	_panel.offset_top = -110.0
	_panel.offset_bottom = 110.0
	_panel.add_theme_stylebox_override("panel",
		UiKit.flat(0.96, 18, 1, Color(0.45, 0.62, 1.0, 0.45), Color(0.04, 0.055, 0.09, 0.97), 22.0, 18.0))
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 24.0
	vb.offset_right = -24.0
	vb.offset_top = 22.0
	vb.offset_bottom = -22.0
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)
	var title := Label.new()
	title.text = "已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(round(40.0 * UiKit.scale())))
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vb.add_child(title)
	var hint := Label.new()
	hint.text = "按 P 继续"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", int(round(22.0 * UiKit.scale())))
	hint.add_theme_color_override("font_color", Color(0.70, 0.80, 0.95))
	vb.add_child(hint)


func _can_pause() -> bool:
	if NetSession.mode != NetSession.Mode.NONE:
		return false
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null or not is_instance_valid(bm):
		return false
	return bool(bm.get("hero_selected")) and not bool(bm.get("intro_active")) 		and not bool(bm.get("building_battle")) and not bool(bm.get("game_over"))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode != KEY_P:
		return
	if not get_tree().paused and not _can_pause():
		return
	get_viewport().set_input_as_handled()
	if get_tree().paused:
		_resume()
	else:
		_pause()


func _pause() -> void:
	_dim.visible = true
	_panel.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = true


func _resume() -> void:
	get_tree().paused = false
	_dim.visible = false
	_panel.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	if get_tree().paused:
		get_tree().paused = false
