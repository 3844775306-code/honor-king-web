extends Panel
## AI 思考过程覆盖层：F3 显示/隐藏，内容由外部 set_text 刷新

var body: RichTextLabel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.58
	anchor_bottom = 1.0
	offset_left = 8.0
	offset_top = 8.0
	offset_right = -8.0
	offset_bottom = -8.0
	add_theme_stylebox_override("panel", UiKit.panel_style(0.94, 12.0))
	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = false
	body.scroll_active = true
	body.selection_enabled = true
	body.mouse_filter = Control.MOUSE_FILTER_STOP
	body.anchor_right = 1.0
	body.anchor_bottom = 1.0
	body.offset_left = 14.0
	body.offset_top = 12.0
	body.offset_right = -14.0
	body.offset_bottom = -12.0
	body.add_theme_font_override("normal_font", UiKit.font())
	body.add_theme_font_size_override("normal_font_size", int(round(13.0 * UiKit.scale())))
	body.add_theme_color_override("default_color", Color(0.86, 0.92, 1.0))
	body.add_theme_constant_override("line_separation", 2)
	add_child(body)


func set_text(t: String) -> void:
	if body != null:
		body.text = t
