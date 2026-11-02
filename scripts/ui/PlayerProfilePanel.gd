extends Control
## 云端玩家主页：昵称 / 段位 / 对战记录 / 出装方案（可复制）/ 灵宝 / 录像（可保存或播放）。
## 数据来自 Supabase cloud_saves（整包 files）+ hk_replay_meta。

const CloudSyncScript = preload("res://scripts/core/CloudSync.gd")
const ReplayScreenScript = preload("res://scripts/replay/ReplayScreen.gd")

var pid := ""
var fallback_nick := ""
var _s := 1.0
var _status: Label = null
var _box: VBoxContainer = null


func _init(p_pid: String = "", p_nick: String = "") -> void:
	pid = p_pid
	fallback_nick = p_nick


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_s = UiKit.scale()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.055, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var card := Panel.new()
	card.anchor_left = 0.10
	card.anchor_right = 0.90
	card.anchor_top = 0.05
	card.anchor_bottom = 0.95
	card.add_theme_stylebox_override("panel",
		UiKit.flat(0.92, 18, 1, Color(0.45, 0.62, 1.0, 0.30), Color(0.045, 0.06, 0.10, 0.96), 22.0, 18.0))
	add_child(card)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24.0
	col.offset_right = -24.0
	col.offset_top = 16.0
	col.offset_bottom = -16.0
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := _mk_label(fallback_nick if fallback_nick != "" else "玩家主页", 28, Color(0.96, 0.92, 0.72))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _btn("返回", Color(0.6, 0.7, 0.9))
	close.pressed.connect(func() -> void: queue_free())
	head.add_child(close)

	_status = _mk_label("读取玩家数据…", 16, Color(0.65, 0.82, 0.95))
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)

	if pid == "":
		_status.text = "玩家 ID 无效"
		return
	CloudSyncScript.get_player_bundle(get_tree(), pid, func(ok: bool, code: int, data: Dictionary) -> void:
		if not ok or data.is_empty():
			_status.text = "读取失败（%d）：云端没有该玩家的存档" % code
			return
		_status.text = ""
		var files_v: Variant = data.get("files", {})
		var files: Dictionary = files_v if files_v is Dictionary else {}
		_render(files)
	)
	_load_replays()


func _render(files: Dictionary) -> void:
	var nick := fallback_nick
	var ncf := _parse_cfg(str(files.get("profile.cfg", "")))
	if ncf != null:
		nick = str(ncf.get_value("player", "name", nick))
	if nick == "":
		nick = "玩家"
	# 段位
	var rank: Dictionary = _parse_json_dict(str(files.get("rank.json", "")))
	var rank_txt := RankSystem.label(rank) if not rank.is_empty() else "暂无段位"
	_box.add_child(_mk_label("%s  ·  %s  ·  %d 分  %d胜 %d负" % [
		nick, rank_txt, int(rank.get("points", 0)), int(rank.get("wins", 0)), int(rank.get("losses", 0))],
		20, Color(0.88, 0.94, 1.0)))
	# 灵宝
	var lcf := _parse_cfg(str(files.get("lingbao.cfg", "")))
	if lcf != null:
		_box.add_child(_mk_label("灵宝：好感度 %d · 配色 %d" % [
			int(lcf.get_value("lingbao", "affection", 0)), int(lcf.get_value("lingbao", "color", 0))],
			17, Color(0.78, 0.90, 1.0)))

	# 对战记录
	_box.add_child(_mk_label("最近对战", 20, Color(0.98, 0.84, 0.42)))
	var hist: Array = _parse_json_array(str(files.get("battle_history.json", "")))
	if hist.is_empty():
		_box.add_child(_mk_label("暂无对战记录", 16, Color(0.62, 0.70, 0.82)))
	else:
		var n := mini(10, hist.size())
		for i in range(n):
			var rec: Dictionary = hist[i] if hist[i] is Dictionary else {}
			var pt := int(rec.get("player_team", 0))
			var win := int(rec.get("winner", -1))
			var res := "胜" if win >= 0 and win == pt else ("负" if win >= 0 else "—")
			var my := {}
			for r in (rec.get("rows", []) as Array):
				if r is Dictionary and bool((r as Dictionary).get("mine", false)):
					my = r
					break
			var dur := int(float(rec.get("dur", 0.0)))
			_box.add_child(_mk_label("· %s  %s  %s %d/%d/%d  %02d:%02d" % [
				str(rec.get("mode", "")), res, str(my.get("name", "")),
				int(my.get("k", 0)), int(my.get("d", 0)), int(my.get("a", 0)),
				dur / 60, dur % 60], 16, Color(0.82, 0.88, 0.96)))

	# 出装方案（可复制）
	_box.add_child(_mk_label("出装方案（可复制到本地）", 20, Color(0.98, 0.84, 0.42)))
	var builds: Dictionary = _parse_json_dict(str(files.get("hero_builds.json", "")))
	if builds.is_empty():
		_box.add_child(_mk_label("暂无保存的出装方案", 16, Color(0.62, 0.70, 0.82)))
	else:
		for hero in builds.keys():
			for b in (builds[hero] as Array):
				if b is Dictionary:
					_box.add_child(_build_row(str(hero), b as Dictionary))


func _build_row(hero: String, b: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var items: Array = b.get("items", [])
	var names: Array = []
	for iid in items:
		names.append(str(ItemDatabase.get_item(str(iid)).get("name", iid)))
	var lab := _mk_label("%s · %s：%s" % [hero, str(b.get("name", "方案")), " / ".join(names)], 16, Color(0.86, 0.92, 1.0))
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(lab)
	var cp := _btn("复制", Color(0.55, 0.8, 0.65))
	cp.pressed.connect(func() -> void:
		HeroBuildStore.save_build(hero, str(b.get("name", "云端")), items)
		_status.text = "已复制出装：%s · %s" % [hero, str(b.get("name", ""))])
	row.add_child(cp)
	return row


func _load_replays() -> void:
	CloudSyncScript.list_cloud_replays(get_tree(), func(ok: bool, code: int, rows: Array) -> void:
		if not ok:
			_box.add_child(_mk_label("录像读取失败（%d）" % code, 16, Color(1.0, 0.55, 0.5)))
			return
		_box.add_child(_mk_label("该玩家的云端录像（可保存到本地）", 20, Color(0.98, 0.84, 0.42)))
		if rows.is_empty():
			_box.add_child(_mk_label("暂无上传的录像", 16, Color(0.62, 0.70, 0.82)))
			return
		for r in rows:
			var rec: Dictionary = r if r is Dictionary else {}
			if str(rec.get("pid", "")) != pid:
				continue
			_box.add_child(_replay_row(rec))
	, pid)


func _replay_row(rec: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lab := _mk_label("%s · %s · %s · %02d:%02d · %s" % [
		str(rec.get("hero", "")), str(rec.get("mode", "")),
		str(rec.get("time", "")), int(float(rec.get("duration", 0.0))) / 60,
		int(float(rec.get("duration", 0.0))) % 60, str(rec.get("name", ""))],
		16, Color(0.86, 0.92, 1.0))
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	var b_save := _btn("保存", Color(0.55, 0.8, 0.65))
	b_save.pressed.connect(func() -> void:
		_status.text = "保存录像中…"
		CloudSyncScript.download_cloud_replay(get_tree(), rec, true, func(ok2: bool, code2: int, _p: String) -> void:
			_status.text = "已保存到本机录像列表" if ok2 else "保存失败（%d）" % code2))
	row.add_child(b_save)
	var b_play := _btn("播放", Color(0.45, 0.75, 1.0))
	b_play.pressed.connect(func() -> void:
		_status.text = "下载录像中…"
		CloudSyncScript.download_cloud_replay(get_tree(), rec, false, func(ok2: bool, code2: int, path: String) -> void:
			if not ok2:
				_status.text = "播放失败（%d）" % code2
				return
			ReplayScreenScript.set_pending_file(path)
			get_tree().change_scene_to_file("res://scenes/replay.tscn")))
	row.add_child(b_play)
	return row


# —— 小工具 ——

func _parse_json_dict(txt: String) -> Dictionary:
	if txt == "":
		return {}
	var v: Variant = JSON.parse_string(txt)
	if v is Dictionary:
		return v as Dictionary
	return {}


func _parse_json_array(txt: String) -> Array:
	if txt == "":
		return []
	var v: Variant = JSON.parse_string(txt)
	if v is Array:
		return v as Array
	return []


func _parse_cfg(txt: String) -> ConfigFile:
	if txt == "":
		return null
	var cf := ConfigFile.new()
	if cf.parse(txt) != OK:
		return null
	return cf


func _mk_label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(round(float(fs) * _s)))
	l.add_theme_color_override("font_color", col)
	return l


func _btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 40)
	b.add_theme_font_size_override("font_size", int(round(17.0 * _s)))
	b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, false))
	b.focus_mode = Control.FOCUS_NONE
	return b

