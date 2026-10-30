extends Control
## 临时预览：把移动端摇杆/按键并排画出来，跑一帧后截图。仅用于本次视觉验收。

func _ready() -> void:
	var vp := get_viewport_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "移动端按键 / 摇杆质感预览"
	title.position = Vector2(60, 42)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	add_child(title)

	var joy = preload("res://scripts/mobile/VirtualJoystick.gd").new()
	joy.position = Vector2(40, vp.y - 620)
	joy.size = Vector2(600, 600)
	add_child(joy)

	var atk := AttackWheelButton.new()
	atk.size = Vector2(340, 340)
	atk.position = Vector2(vp.x - 390, vp.y - 410)
	atk.color = Color(0.9, 0.4, 0.3, 0.85)
	atk.show_damage = 326
	atk.show_speed = 1.42
	add_child(atk)

	var skill := SkillTouchButton.new()
	skill.size = Vector2(260, 260)
	skill.position = Vector2(vp.x - 760, vp.y - 350)
	skill.art_hero = "甄姬"
	skill.display_name = "泪如泉涌"
	skill.name_below = true
	skill.skill_index = 0
	skill.skill_level = 3
	skill.max_level = 5
	skill.color = Color(0.28, 0.62, 1.0, 0.9)
	add_child(skill)

	var act := TouchActionButton.new()
	act.size = Vector2(180, 180)
	act.position = Vector2(vp.x - 520, vp.y - 280)
	act.label_text = "回城"
	act.color = Color(0.85, 0.6, 0.15, 0.85)
	add_child(act)

	var cancel := CancelCastButton.new()
	cancel.size = Vector2(250, 250)
	cancel.position = Vector2(vp.x - 1120, vp.y - 350)
	cancel.set_highlighted(true)
	add_child(cancel)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://scripts/dev/_ui_preview.png")
	get_tree().quit()
