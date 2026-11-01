extends Control
## 录像列表页（大厅）：读 user://replays/index.json，播放 / 删除。

const Repo = preload("res://scripts/core/ReplayRecorder.gd")
const ReplayScreenScript = preload("res://scripts/replay/ReplayScreen.gd")

var _body: VBoxContainer = null
var _status: Label = null
var _s := 1.0


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
	card.anchor_top = 0.06
	card.anchor_bottom = 0.94
	card.add_theme_stylebox_override("panel",
		UiKit.flat(0.92, 18, 1, Color(0.45, 0.62, 1.0, 0.30), Color(0.045, 0.06, 0.10, 0.96), 22.0, 18.0))
	add_child(card)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 26.0
	col.offset_right = -26.0
	col.offset_top = 18.0
	col.offset_bottom = -18.0
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	col.add_child(head)
	var t := Label.new()
	t.text = "▶  录像回放"
	t.add_theme_font_size_override("font_size", int(round(30.0 * _s)))
	t.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	head.add_child(t)
	var sub := Label.new()
	sub.text = "对局结束后自动录制，最多保留 %d 局；回放只重建画面，不影响对局数据" % Repo.MAX_REPLAYS
	sub.add_theme_font_size_override("font_size", int(round(16.0 * _s)))
	sub.add_theme_color_override("font_color", Color(0.60, 0.66, 0.78))
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
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
	for c in _body.get_children():
		c.queue_free()
	var arr: Array = Repo.load_index()
	if arr.is_empty():
		var empty := Label.new()
		empty.text = "还没有录像。打完一局（单机或联机）后会自动出现在这里。"
		empty.add_theme_font_size_override("font_size", int(round(20.0 * _s)))
		empty.add_theme_color_override("font_color", Color(0.62, 0.68, 0.80))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body.add_child(empty)
		return
	for e in arr:
		_body.add_child(_row(e))


## 录像所属玩家阵营：优先索引记录的 player_team；旧索引缺失时回退读录像 meta / 英雄列表
static func _team_of_entry(e: Dictionary) -> int:
	var mt: int = int(e.get("player_team", -1))
	if mt == 0 or mt == 1:
		return mt
	var doc: Dictionary = Repo.load_replay(str(e.get("file", "")))
	var meta: Dictionary = doc.get("meta", {})
	mt = int(meta.get("player_team", -1))
	if mt == 0 or mt == 1:
		return mt
	var mi: int = int(meta.get("me", -1))
	var hs: Array = doc.get("heroes", [])
	if mi >= 0 and mi < hs.size():
		return int((hs[mi] as Dictionary).get("team", int(Config.player_team)))
	return int(Config.player_team)

func _row(e: Dictionary) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 62)
	row.add_theme_stylebox_override("panel",
		UiKit.flat(0.85, 12, 1, Color(0.45, 0.62, 1.0, 0.22), Color(0.07, 0.09, 0.14, 0.92), 14.0, 0.0))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16.0
	hb.offset_right = -16.0
	hb.add_theme_constant_override("separation", 16)
	row.add_child(hb)

	var win: int = int(e.get("winner", -1))
	# 胜负必须按「这盘录像自己的玩家阵营」判断，不能用当前大厅的 Config.player_team
	var my_team: int = _team_of_entry(e)
	var res_txt: String = "胜利" if win == my_team else ("失败" if win >= 0 else "录像")
	if int(e.get("partial", 0)) == 1:
		res_txt = "中途退出"
	var hero := Label.new()
	hero.text = "%s  ·  %s" % [str(e.get("hero", "?")), res_txt]
	hero.custom_minimum_size = Vector2(360, 0)
	hero.add_theme_font_size_override("font_size", int(round(22.0 * _s)))
	hero.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.65) if res_txt == "胜利" else (Color(1.0, 0.55, 0.5) if res_txt == "失败" else Color(0.75, 0.80, 0.9)))
	hero.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(hero)

	var dur: float = float(e.get("duration", 0.0))
	var d: Label = Label.new()
	d.text = "%02d:%02d" % [int(dur) / 60, int(dur) % 60]
	d.custom_minimum_size = Vector2(110, 0)
	d.add_theme_font_size_override("font_size", int(round(20.0 * _s)))
	d.add_theme_color_override("font_color", Color(0.80, 0.86, 0.95))
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(d)

	var mode: Label = Label.new()
	mode.text = str(e.get("mode", ""))
	mode.custom_minimum_size = Vector2(90, 0)
	mode.add_theme_font_size_override("font_size", int(round(18.0 * _s)))
	mode.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	mode.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(mode)

	var tm: Label = Label.new()
	tm.text = _fmt_time(str(e.get("time", "")))
	tm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tm.add_theme_font_size_override("font_size", int(round(18.0 * _s)))
	tm.add_theme_color_override("font_color", Color(0.62, 0.70, 0.84))
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(tm)

	var play := _btn("▶ 播放", Color(0.45, 0.75, 1.0))
	play.pressed.connect(func() -> void:
		var file := str(e.get("file", ""))
		if file == "":
			return
		ReplayScreenScript.set_pending_file(file)
		get_tree().change_scene_to_file("res://scenes/replay.tscn"))
	hb.add_child(play)
	var exp := _btn("导出", Color(0.55, 0.8, 0.65))
	exp.pressed.connect(func() -> void:
		var p := Repo.export_replay(e)
		if _status != null:
			_status.text = ("已导出到：%s" % p) if p != "" else "导出失败：找不到录像文件"
			_status.add_theme_color_override("font_color",
				Color(0.55, 0.95, 0.65) if p != "" else Color(1.0, 0.5, 0.45)))
	hb.add_child(exp)
	var del := _btn("删除", Color(0.9, 0.45, 0.42))
	del.pressed.connect(func() -> void:
		Repo.delete_replay(e)
		_refresh())
	hb.add_child(del)
	return row


func _fmt_time(stamp: String) -> String:
	if stamp.length() < 15:
		return stamp
	return "%s-%s-%s %s:%s" % [stamp.substr(0, 4), stamp.substr(4, 2), stamp.substr(6, 2),
		stamp.substr(9, 2), stamp.substr(11, 2)]


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

