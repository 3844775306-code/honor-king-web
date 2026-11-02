extends Control
## 段位排行榜（云端 hk_profiles）：按大段位/小段位/星/积分排序，可点开玩家主页。

const CloudSyncScript = preload("res://scripts/core/CloudSync.gd")
const ProfilePanel = preload("res://scripts/ui/PlayerProfilePanel.gd")

var _s := 1.0
var _body: VBoxContainer = null
var _status: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_s = UiKit.scale()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.055, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var card := Panel.new()
	card.anchor_left = 0.06
	card.anchor_right = 0.94
	card.anchor_top = 0.05
	card.anchor_bottom = 0.95
	card.add_theme_stylebox_override("panel",
		UiKit.flat(0.92, 18, 1, Color(0.45, 0.62, 1.0, 0.30), Color(0.045, 0.06, 0.10, 0.96), 22.0, 18.0))
	add_child(card)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 26.0
	col.offset_right = -26.0
	col.offset_top = 18.0
	col.offset_bottom = -18.0
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var t := Label.new()
	t.text = "🏆  段位排行榜"
	t.add_theme_font_size_override("font_size", int(round(30.0 * _s)))
	t.add_theme_color_override("font_color", Color(0.96, 0.92, 0.72))
	head.add_child(t)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close := _btn("返回", Color(0.6, 0.7, 0.9))
	close.pressed.connect(func() -> void: queue_free())
	head.add_child(close)

	_status = Label.new()
	_status.text = ""
	_status.add_theme_font_size_override("font_size", int(round(16.0 * _s)))
	_status.add_theme_color_override("font_color", Color(0.65, 0.82, 0.95))
	col.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	_refresh()


func _refresh() -> void:
	for ch in _body.get_children():
		ch.queue_free()
	_status.text = "读取排行榜…"
	CloudSyncScript.list_leaderboard(get_tree(), func(ok: bool, code: int, rows: Array) -> void:
		if not ok:
			_status.text = "排行榜读取失败（%d）：先在 Supabase SQL Editor 执行 hk_profiles 建表 SQL" % code
			return
		if rows.is_empty():
			_status.text = "还没有玩家上榜：打一局后会自动上传段位"
			return
		for i in range(rows.size()):
			_body.add_child(_row(i + 1, rows[i] as Dictionary))
		_status.text = "共 %d 名玩家（段位/星/积分排序）" % rows.size())


func _row(rank: int, r: Dictionary) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.add_theme_stylebox_override("panel",
		UiKit.flat(0.85, 12, 1, Color(0.45, 0.62, 1.0, 0.22), Color(0.07, 0.09, 0.14, 0.92), 14.0, 0.0))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16.0
	hb.offset_right = -16.0
	hb.add_theme_constant_override("separation", 16)
	row.add_child(hb)

	var rk := Label.new()
	rk.text = "#%d" % rank
	rk.custom_minimum_size = Vector2(80, 0)
	rk.add_theme_font_size_override("font_size", int(round(22.0 * _s)))
	rk.add_theme_color_override("font_color", Color(0.98, 0.84, 0.42) if rank <= 3 else Color(0.70, 0.78, 0.90))
	rk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(rk)

	var nick := Label.new()
	nick.text = str(r.get("nickname", "")) if str(r.get("nickname", "")) != "" else "玩家"
	nick.custom_minimum_size = Vector2(240, 0)
	nick.add_theme_font_size_override("font_size", int(round(22.0 * _s)))
	nick.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	nick.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(nick)

	var tier_lab := Label.new()
	tier_lab.text = RankSystem.label({
		"tier": int(r.get("tier", 0)), "sub": int(r.get("sub", 0)),
		"stars": int(r.get("stars", 0)), "points": int(r.get("points", 0)),
	})
	tier_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_lab.add_theme_font_size_override("font_size", int(round(20.0 * _s)))
	tier_lab.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0))
	tier_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(tier_lab)

	var pts := Label.new()
	pts.text = "%d 分 · %d胜 %d负" % [int(r.get("points", 0)), int(r.get("wins", 0)), int(r.get("losses", 0))]
	pts.custom_minimum_size = Vector2(200, 0)
	pts.add_theme_font_size_override("font_size", int(round(18.0 * _s)))
	pts.add_theme_color_override("font_color", Color(0.66, 0.76, 0.90))
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(pts)

	var view := _btn("查看主页", Color(0.55, 0.75, 1.0))
	view.pressed.connect(func() -> void:
		add_child(ProfilePanel.new(str(r.get("pid", "")), str(r.get("nickname", "")))))
	hb.add_child(view)
	return row


func _btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 42)
	b.add_theme_font_size_override("font_size", int(round(18.0 * _s)))
	b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, false))
	b.focus_mode = Control.FOCUS_NONE
	return b
