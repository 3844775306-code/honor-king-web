class_name BattleHistoryPanel
extends Control
## 大厅「对战纪录」：列表（胜负 / 英雄 / KDA / 时间 / 比分）→ 点开某局 = 复刻结算面板。
## 数据来源 BattleHistory（user://battle_history.json），纯容器布局，随屏宽缩放。

var _recs: Array = []
var _item_tier_cache: Dictionary = {}
var _detail := -1
var _title: Label
var _body: VBoxContainer
var _s := 1.0


func _ready() -> void:
	_s = UiKit.scale()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_recs = BattleHistory.all()

	var bd := UiKit.make_backdrop(self, UiKit.C_GOLD, 0.8)
	if bd != null:
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.025, 0.05, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := int(30.0 * _s)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(16.0 * _s))
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(12.0 * _s))
	col.add_child(head)
	_title = _lab("对战纪录", UiKit.FS_HUGE, UiKit.C_GOLD)
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close_btn := _btn("×  关闭", UiKit.C_DANGER)
	close_btn.pressed.connect(_close)
	head.add_child(close_btn)
	# 战绩总览（胜率 / 连胜 / 最近 5 局点阵）
	var summary := _summary_card()
	if summary != null:
		col.add_child(summary)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", int(10.0 * _s))
	scroll.add_child(_body)

	_show_list()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _detail >= 0:
			_show_list()
		else:
			_close()
		get_viewport().set_input_as_handled()


# ---------- 列表 ----------

func _show_list() -> void:
	_detail = -1
	_title.text = "对战纪录（%d 局）" % _recs.size()
	_clear_body()
	if _recs.is_empty():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", int(10.0 * _s))
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.custom_minimum_size = Vector2(0, int(420.0 * _s))
		_body.add_child(box)
		var t := _lab("还没有对战纪录", UiKit.FS_HUGE, UiKit.C_GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(t)
		var hint := _lab("打完一局（单机或联机）后，结算数据会自动记录在这里。", UiKit.FS_MD, UiKit.C_TEXT_DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
		return
	for i in _recs.size():
		_body.add_child(_record_row(i))


func _record_row(i: int) -> Control:
	var rec: Dictionary = _recs[i]
	var my_team := BattleHistory.player_team_of(rec)
	var enemy_team := 1 - my_team
	var win := int(rec.get("winner", -1)) == my_team
	var accent: Color = UiKit.C_TEAM0 if win else UiKit.C_TEAM1
	var rows: Array = rec.get("rows", [])
	var k := 0
	var d := 0
	var a := 0
	var enemy_kills := 0
	var my_name := "—"
	var my_nick := ""
	var my_gold := 0
	var foe_gold := 0
	for r in rows:
		if int(r.get("team", -1)) == my_team:
			k += int(r.get("k", 0))
			d += int(r.get("d", 0))
			a += int(r.get("a", 0))
			my_gold += int(r.get("gold", 0))
			if bool(r.get("mine", false)):
				my_name = str(r.get("name", "—"))
				my_nick = str(r.get("nick", ""))
		else:
			enemy_kills += int(r.get("k", 0))
			foe_gold += int(r.get("gold", 0))
	if my_name == "—":
		for r in rows:
			if int(r.get("team", -1)) == my_team:
				my_name = str(r.get("name", "—"))
				my_nick = str(r.get("nick", ""))
				break

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, int(112.0 * _s))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal_style := _row_style(accent, false)
	row.add_theme_stylebox_override("panel", normal_style)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(16.0 * _s))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	# 左侧胜负色条
	var strip := ColorRect.new()
	strip.color = accent
	strip.custom_minimum_size = Vector2(int(6.0 * _s), 0)
	strip.size_flags_vertical = Control.SIZE_FILL
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(strip)

	# 胜负徽章：实心色块 + 深色字
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(int(64.0 * _s), 0)
	badge.add_theme_stylebox_override("panel", UiKit.skin_chip(accent, 0.92, int(10.0 * _s)))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := _lab("胜" if win else "负", UiKit.FS_XL, Color(0.05, 0.05, 0.08))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	h.add_child(badge)
	# 英雄头像（程序化，与选人/结算页同源）
	h.add_child(_hero_face(my_name, accent, int(54.0 * _s)))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(2.0 * _s))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)

	# 第一行：英雄名（+昵称）+ 彩色 KDA
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", int(10.0 * _s))
	line1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line1)
	line1.add_child(_lab(my_name, UiKit.FS_LG, UiKit.C_TEXT))
	if my_nick != "":
		var nl := _lab(my_nick, UiKit.FS_SM, Color(0.66, 0.74, 0.88))
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line1.add_child(nl)
	line1.add_child(_kda_box(k, d, a))
	# 第二行：模式 / 时间 / 时长
	col.add_child(_lab("%s · %s · 时长 %s" % [
		str(rec.get("mode", "单机")), _time_text(int(rec.get("ts", 0))), _dur_text(float(rec.get("dur", 0.0)))],
		UiKit.FS_SM, UiKit.C_TEXT_DIM))
	# 第三行：经济差 + 推塔 + 段位变化
	var turrets: Array = rec.get("turrets", [])
	var turret_txt := ""
	if turrets.size() >= 2:
		# 按玩家所在方显示：我方推掉的敌塔 / 敌方推掉的我塔
		turret_txt = " · 推塔 %d/%d" % [int(turrets[enemy_team]), int(turrets[my_team])]
	var rank_txt := _rank_text(rec.get("rank", {}))
	col.add_child(_lab("经济差 %s%s%s" % [_signed_gold(my_gold - foe_gold), turret_txt, rank_txt],
		UiKit.FS_SM, UiKit.C_GOLD))

	# 玩家本局装备图标（列表也带一眼出装）
	var mine_row := _find_mine_row(rows, my_team)
	if not mine_row.is_empty():
		h.add_child(_item_strip(_row_equips(mine_row), int(22.0 * _s)))

	# 右侧：比分块 + 查看
	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 0)
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.custom_minimum_size = Vector2(int(120.0 * _s), 0)
	score_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(score_box)
	var sl := _lab("%d : %d" % [k, enemy_kills], UiKit.FS_XL, UiKit.C_GOLD)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(sl)
	var go := _lab("查看详情 ›", UiKit.FS_SM, UiKit.C_TEXT_DIM)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_box.add_child(go)

	# 悬浮高亮
	row.mouse_entered.connect(func() -> void:
		row.add_theme_stylebox_override("panel", _row_style(accent, true))
		go.add_theme_color_override("font_color", UiKit.C_GOLD)
	)
	row.mouse_exited.connect(func() -> void:
		row.add_theme_stylebox_override("panel", normal_style)
		go.add_theme_color_override("font_color", UiKit.C_TEXT_DIM)
	)
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(i)
	)
	return row


# 列表行底板：深色玻璃 + 胜负色描边（悬浮提亮）
func _row_style(accent: Color, hovered: bool) -> StyleBoxFlat:
	var base := Color(0.13, 0.15, 0.21) if hovered else Color(0.09, 0.105, 0.155)
	var sb: StyleBoxFlat = UiKit.skin_chip(base, 0.96 if hovered else 0.88, int(12.0 * _s))
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.95 if hovered else 0.6)
	sb.set_border_width_all(maxi(1, int(round(1.5 * _s))))
	sb.content_margin_left = int(14.0 * _s)
	sb.content_margin_right = int(14.0 * _s)
	sb.content_margin_top = int(8.0 * _s)
	sb.content_margin_bottom = int(8.0 * _s)
	return sb


# 战绩总览：总场次 / 胜率 / 连胜 / 最近 5 局点阵
func _summary_card() -> Control:
	if _recs.is_empty():
		return null
	var wins := 0
	var streak := 0
	for i in _recs.size():
		var rec: Dictionary = _recs[i]
		if int(rec.get("winner", -1)) == BattleHistory.player_team_of(rec):
			wins += 1
	for r in _recs:
		var rec2: Dictionary = r
		if int(rec2.get("winner", -1)) == BattleHistory.player_team_of(rec2):
			streak += 1
		else:
			break
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.skin_chip(Color(1.0, 0.84, 0.0, 0.30), 0.5, int(12.0 * _s)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(26.0 * _s))
	panel.add_child(h)
	h.add_child(_lab("总场次 %d" % _recs.size(), UiKit.FS_MD, UiKit.C_TEXT))
	var pct := float(wins) / float(maxi(1, _recs.size())) * 100.0
	h.add_child(_lab("胜率 %.0f%%" % pct, UiKit.FS_MD, UiKit.C_GOLD))
	h.add_child(_lab("%d 胜 %d 负" % [wins, _recs.size() - wins], UiKit.FS_SM, UiKit.C_TEXT_DIM))
	if streak > 1:
		h.add_child(_lab("%d 连胜" % streak, UiKit.FS_MD, UiKit.C_TEAM0))
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", int(6.0 * _s))
	dots.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(dots)
	dots.add_child(_lab("最近", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	for i in mini(_recs.size(), 5):
		var rec: Dictionary = _recs[i]
		var pt := BattleHistory.player_team_of(rec)
		var w := int(rec.get("winner", -1)) == pt
		var mine := _find_mine_row(rec.get("rows", []), pt)
		var hero_name := str(mine.get("name", "—"))
		var face := _hero_face(hero_name, UiKit.C_TEAM0 if w else UiKit.C_TEAM1, int(26.0 * _s))
		dots.add_child(face)
	return panel


# ---------- 结算回看 ----------

func _show_detail(i: int) -> void:
	_detail = i
	var rec: Dictionary = _recs[i]
	var my_team := BattleHistory.player_team_of(rec)
	var enemy_team := 1 - my_team
	var win := int(rec.get("winner", -1)) == my_team
	var accent: Color = UiKit.C_TEAM0 if win else UiKit.C_TEAM1
	_title.text = "对局结算回看"
	_clear_body()

	var back := _btn("‹  返回列表", UiKit.C_GOLD)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_show_list)
	_body.add_child(back)

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UiKit.skin_chip(accent, 0.5, int(14.0 * _s)))
	_body.add_child(banner)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", int(26.0 * _s))
	banner.add_child(bh)
	var result := _lab("对局胜利" if win else "对局失败", UiKit.FS_HUGE, accent)
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bh.add_child(result)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(info)
	info.add_child(_lab("%s · %s" % [str(rec.get("mode", "单机")), _time_text(int(rec.get("ts", 0)))],
		UiKit.FS_MD, UiKit.C_TEXT))
	info.add_child(_lab("对局时长 %s" % _dur_text(float(rec.get("dur", 0.0))), UiKit.FS_SM, UiKit.C_TEXT_DIM))

	var rows: Array = rec.get("rows", [])
	# 本局 MVP：英雄头像 + 名字 + 昵称
	for r in rows:
		if bool(r.get("mvp", false)):
			var mvp_row := HBoxContainer.new()
			mvp_row.add_theme_constant_override("separation", int(8.0 * _s))
			mvp_row.add_child(_hero_face(str(r.get("name", "—")), Color(1.0, 0.84, 0.25), int(32.0 * _s)))
			var mvp_txt := "本局 MVP：" + str(r.get("name", "—"))
			var mvp_nick := str(r.get("nick", ""))
			if mvp_nick != "":
				mvp_txt += " · " + mvp_nick
			var mvp_lab := _lab(mvp_txt, UiKit.FS_MD, Color(1.0, 0.84, 0.25))
			mvp_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			mvp_row.add_child(mvp_lab)
			info.add_child(mvp_row)
			break
	# 总览条：击杀差 / 经济差 / 推塔 / 段位变化
	_body.add_child(_summary_strip(rec, rows))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(18.0 * _s))
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	cols.add_child(_team_block("我方", rows, my_team, _team_color(my_team)))
	cols.add_child(_team_block("敌方", rows, enemy_team, _team_color(enemy_team)))
	# 与结算页「数据」页同口径的完整战后数据表
	_body.add_child(_data_table(rows, my_team, _team_color(my_team), my_team))
	_body.add_child(_data_table(rows, enemy_team, _team_color(enemy_team), my_team))


## 细节条：击杀差 / 经济差 / 推塔 / 段位变化 / 双方承伤总和
func _summary_strip(rec: Dictionary, rows: Array) -> Control:
	var my_team := BattleHistory.player_team_of(rec)
	var enemy_team := 1 - my_team
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.skin_chip(Color(1.0, 0.84, 0.0, 0.30), 0.5, int(12.0 * _s)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(22.0 * _s))
	panel.add_child(h)
	var my_k := 0
	var foe_k := 0
	var my_g := 0
	var foe_g := 0
	var my_taken := 0
	var my_heal := 0
	var my_cc := 0
	for r in rows:
		if int(r.get("team", -1)) == my_team:
			my_k += int(r.get("k", 0))
			my_g += int(r.get("gold", 0))
			my_taken += int(r.get("taken", 0))
			my_heal += int(r.get("heal", 0))
			my_cc += int(r.get("cc", 0))
		else:
			foe_k += int(r.get("k", 0))
			foe_g += int(r.get("gold", 0))
	h.add_child(_lab("击杀 %d : %d" % [my_k, foe_k], UiKit.FS_MD, UiKit.C_TEXT))
	h.add_child(_lab("经济差 %s" % _signed_gold(my_g - foe_g), UiKit.FS_MD, UiKit.C_GOLD))
	var turrets: Array = rec.get("turrets", [])
	if turrets.size() >= 2:
		h.add_child(_lab("推塔 %d : %d" % [int(turrets[enemy_team]), int(turrets[my_team])], UiKit.FS_MD, UiKit.C_TEXT))
	h.add_child(_lab("我方承伤 %s · 治疗 %s · 控制 %.1fs" % [
		_gold_text(my_taken), _gold_text(my_heal), float(my_cc) / 10.0], UiKit.FS_MD, UiKit.C_TEXT_DIM))
	var rank_txt := _rank_text(rec.get("rank", {}))
	if rank_txt != "":
		h.add_child(_lab(rank_txt.trim_prefix(" · "), UiKit.FS_MD, UiKit.C_GOLD))
	return panel


func _team_block(title: String, rows: Array, team: int, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.skin_chip(Color(color.r, color.g, color.b, 0.42), 0.5, int(14.0 * _s)))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(6.0 * _s))
	panel.add_child(col)

	var kills := 0
	var gold := 0
	var list: Array = []
	for r in rows:
		if int(r.get("team", -1)) == team:
			list.append(r)
			kills += int(r.get("k", 0))
			gold += int(r.get("gold", 0))
	var ctx := _team_ctx(rows, team)
	# 队头：队名 + 击杀/经济 + 奖牌统计
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(12.0 * _s))
	col.add_child(head)
	head.add_child(_lab(title, UiKit.FS_LG, color))
	head.add_child(_lab("总击杀 %d · 团队经济 %s" % [kills, _gold_text(gold)], UiKit.FS_SM, UiKit.C_TEXT_DIM))
	var mg := 0
	var ms := 0
	var mb := 0
	var mmvp := 0
	for r in list:
		var md := _medal_of(r, ctx)
		if md == 0:
			mg += 1
		elif md == 1:
			ms += 1
		elif md == 2:
			mb += 1
		if bool(r.get("mvp", false)):
			mmvp += 1
	var msum := HBoxContainer.new()
	msum.add_theme_constant_override("separation", int(8.0 * _s))
	msum.alignment = BoxContainer.ALIGNMENT_END
	msum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(msum)
	if mmvp > 0:
		msum.add_child(_medal_chip("MVP", Color(1.0, 0.84, 0.25)))
	if mg > 0:
		msum.add_child(_medal_chip("金牌 %d" % mg, Color(1.0, 0.84, 0.25)))
	if ms > 0:
		msum.add_child(_medal_chip("银牌 %d" % ms, Color(0.80, 0.86, 0.98)))
	if mb > 0:
		msum.add_child(_medal_chip("铜牌 %d" % mb, Color(0.85, 0.62, 0.40)))

	for r in list:
		col.add_child(_player_row(r, color, ctx))
	if list.is_empty():
		col.add_child(_lab("—", UiKit.FS_MD, UiKit.C_TEXT_DIM))
	return panel


## 单英雄条目：奖牌/MVP 徽章 + 英雄名 + 昵称 + KDA + 经济 + 评分 + 装备
func _player_row(r: Dictionary, color: Color, ctx: Dictionary) -> Control:
	var medal := _medal_of(r, ctx)
	var mvp := bool(r.get("mvp", false))
	var rowp := PanelContainer.new()
	var bg := Color(0.10, 0.12, 0.17) if not mvp else Color(0.17, 0.145, 0.07)
	rowp.add_theme_stylebox_override("panel", UiKit.skin_chip(bg, 0.92, int(10.0 * _s)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(10.0 * _s))
	rowp.add_child(h)

	# 徽章列：MVP 优先，其次金银铜牌
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(int(64.0 * _s), 0)
	h.add_child(badge)
	var bcol := VBoxContainer.new()
	bcol.alignment = BoxContainer.ALIGNMENT_CENTER
	bcol.add_theme_constant_override("separation", 0)
	badge.add_child(bcol)
	if mvp:
		bcol.add_child(_medal_chip("MVP", Color(1.0, 0.84, 0.25)))
	if medal >= 0:
		bcol.add_child(_medal_chip(_medal_text(medal), _medal_color(medal)))

	# 英雄头像
	h.add_child(_hero_face(str(r.get("name", "—")), color, int(42.0 * _s)))

	# 名字 + 昵称
	var nmcol := VBoxContainer.new()
	nmcol.add_theme_constant_override("separation", 0)
	nmcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nmcol)
	var nm_txt := str(r.get("name", "—"))
	if bool(r.get("mine", false)):
		nm_txt += "（我）"
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", int(8.0 * _s))
	nmcol.add_child(name_line)
	name_line.add_child(_lab(nm_txt, UiKit.FS_MD, UiKit.C_TEXT))
	var nick := str(r.get("nick", ""))
	if nick != "":
		var nl := _lab(nick, UiKit.FS_SM, Color(0.64, 0.72, 0.86))
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_line.add_child(nl)
	var role := str(r.get("role", ""))
	var meta2 := "Lv.%d" % int(r.get("lv", 1))
	if role != "":
		meta2 = role + " · " + meta2
	nmcol.add_child(_lab(meta2, UiKit.FS_SM, UiKit.C_TEXT_DIM))

	# 数据：KDA / 经济 / 评分
	var stat := VBoxContainer.new()
	stat.add_theme_constant_override("separation", 0)
	stat.custom_minimum_size = Vector2(int(150.0 * _s), 0)
	h.add_child(stat)
	stat.add_child(_kda_box(int(r.get("k", 0)), int(r.get("d", 0)), int(r.get("a", 0))))
	var sc := _rating(r, ctx)
	stat.add_child(_lab("经济 %s · 评分 %.1f %s" % [_gold_text(int(r.get("gold", 0))), sc, _grade(sc)],
		UiKit.FS_SM, UiKit.C_GOLD if sc >= 64.0 else UiKit.C_TEXT_DIM))

	# 装备：品质色图标（旧纪录只有名称时按名称回查品质）
	var icon_strip := _item_strip(_row_equips(r), int(26.0 * _s))
	icon_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_strip.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(icon_strip)
	return rowp


# 彩色 KDA（击杀金 / 死亡红 / 助攻蓝），用 Label 组避免 RichTextLabel 撑高
func _kda_box(k: int, d: int, a: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(2.0 * _s))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_lab(str(k), UiKit.FS_MD, Color(1.0, 0.84, 0.42)))
	box.add_child(_lab("/", UiKit.FS_SM, Color(0.49, 0.52, 0.58)))
	box.add_child(_lab(str(d), UiKit.FS_MD, Color(1.0, 0.56, 0.50)))
	box.add_child(_lab("/", UiKit.FS_SM, Color(0.49, 0.52, 0.58)))
	box.add_child(_lab(str(a), UiKit.FS_MD, Color(0.48, 0.85, 1.0)))
	return box


# —— 奖牌：0 金 / 1 银 / 2 铜 / -1 无（优先读纪录里的 medal 字段，旧纪录按评分回算） ——
func _medal_of(r: Dictionary, ctx: Dictionary) -> int:
	if r.has("medal"):
		return int(r.get("medal", -1))
	var sc := _rating(r, ctx)
	if sc >= 78.0:
		return 0
	if sc >= 64.0:
		return 1
	if sc >= 52.0:
		return 2
	return -1


func _medal_text(medal: int) -> String:
	if medal == 0:
		return "金牌"
	if medal == 1:
		return "银牌"
	if medal == 2:
		return "铜牌"
	return ""


func _medal_color(medal: int) -> Color:
	if medal == 0:
		return Color(1.0, 0.84, 0.25)
	if medal == 1:
		return Color(0.80, 0.86, 0.98)
	return Color(0.85, 0.62, 0.40)


func _medal_chip(txt: String, color: Color) -> Control:
	var chip := PanelContainer.new()
	var sb: StyleBoxFlat = UiKit.skin_chip(color, 0.9, int(6.0 * _s))
	sb.bg_color = Color(color.r * 0.24, color.g * 0.24, color.b * 0.24, 0.95)
	chip.add_theme_stylebox_override("panel", sb)
	var l := _lab(txt, UiKit.FS_SM, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip


# ---------- 战后数据表：口径与结算页「数据」页一致 ----------

const STAT_META: Array = [
	["伤", "对英雄伤害"], ["抗", "承受伤害"], ["金", "总经济"], ["团", "参团率"],
	["转", "伤害转化比"], ["死", "每死承伤"], ["野", "野怪经济"], ["刀", "补刀数"],
	["控", "控制时长"], ["疗", "治疗量"], ["塔", "对塔伤害"],
]


# 队伍上下文：队内最高值与团队总量（评分/占比都用它）
func _team_ctx(rows: Array, team: int) -> Dictionary:
	var ctx := {"max_k": 1, "max_dmg": 1.0, "max_gold": 1, "max_taken": 1.0,
		"total_k": 0, "total_dmg": 0.0, "total_gold": 0.0, "max_deaths": 1}
	for r in rows:
		if int(r.get("team", -1)) != team:
			continue
		ctx["max_k"] = maxi(int(ctx["max_k"]), int(r.get("k", 0)))
		ctx["max_dmg"] = maxf(float(ctx["max_dmg"]), float(r.get("dmg", 0)))
		ctx["max_gold"] = maxi(int(ctx["max_gold"]), int(r.get("gold", 0)))
		ctx["max_taken"] = maxf(float(ctx["max_taken"]), float(r.get("taken", 0)))
		ctx["total_k"] = int(ctx["total_k"]) + int(r.get("k", 0))
		ctx["total_dmg"] = float(ctx["total_dmg"]) + float(r.get("dmg", 0)) + float(r.get("turret", 0))
		ctx["total_gold"] = float(ctx["total_gold"]) + float(r.get("gold", 0))
		ctx["max_deaths"] = maxi(int(ctx["max_deaths"]), int(r.get("d", 0)))
	return ctx


# 与 ResultsPanel._get_hero_stats 同口径的 11 项数据
func _hero_stats(r: Dictionary, ctx: Dictionary) -> Array:
	var dmg := float(r.get("dmg", 0))
	var taken := float(r.get("taken", 0))
	var gold := float(r.get("gold", 0))
	var tk := float(maxi(1, int(ctx["total_k"])))
	var participation := float(int(r.get("k", 0)) + int(r.get("a", 0))) / tk * 100.0
	var dmg_pct := (dmg + float(r.get("turret", 0))) / maxf(1.0, float(ctx["total_dmg"])) * 100.0
	var gold_pct := gold / maxf(1.0, float(ctx["total_gold"])) * 100.0
	var conversion := dmg_pct / maxf(0.01, gold_pct)
	var per_death := taken / maxf(1.0, float(int(r.get("d", 0))))
	return [dmg, taken, gold, participation, conversion, per_death,
		float(r.get("jungle", 0)), float(r.get("lh", 0)), float(r.get("cc", 0)) / 10.0,
		float(r.get("heal", 0)), float(r.get("turret", 0))]


# 与 ResultsPanel._calculate_rating 同口径的评分
func _rating(r: Dictionary, ctx: Dictionary) -> float:
	var k := float(int(r.get("k", 0)))
	var a := float(int(r.get("a", 0)))
	var d := float(int(r.get("d", 0)))
	var gold := float(r.get("gold", 0))
	var dmg := float(r.get("dmg", 0))
	var taken := float(r.get("taken", 0))
	var kill_score := k / float(ctx["max_k"]) * 100.0
	var assist_score := a / float(maxi(1, int(ctx["total_k"]))) * 100.0
	var death_penalty := (1.0 - d / float(maxi(1, int(ctx["max_deaths"])))) * 100.0
	var gold_score := gold / float(ctx["max_gold"]) * 100.0
	var damage_score := dmg / maxf(1.0, float(ctx["max_dmg"])) * 100.0
	var taken_score := taken / maxf(1.0, float(ctx["max_taken"])) * 100.0
	var participation := (k + a) / float(maxi(1, int(ctx["total_k"]))) * 100.0
	var total: float = (kill_score * 0.15 + assist_score * 0.10 + maxf(0.0, death_penalty) * 0.05 +
		gold_score * 0.15 + damage_score * 0.25 + taken_score * 0.10 + participation * 0.20)
	return clampf(total, 0.0, 100.0)


func _grade(score: float) -> String:
	if score >= 90.0: return "超神"
	if score >= 80.0: return "MVP"
	if score >= 70.0: return "优秀"
	if score >= 60.0: return "良好"
	if score >= 50.0: return "一般"
	return "低迷"


func _fmt_stat(stat_name: String, value: float) -> String:
	match stat_name:
		"参团率": return "%.1f%%" % value
		"伤害转化比": return "%.2f" % value
		"控制时长": return "%.1fs" % value
		"补刀数": return str(int(value))
		_: return _gold_text(int(value))


func _data_table(rows: Array, team: int, color: Color, my_team: int = Config.Team.PLAYER) -> Control:
	var list: Array = []
	for r in rows:
		if int(r.get("team", -1)) == team:
			list.append(r)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.skin_chip(Color(color.r, color.g, color.b, 0.28), 0.5, int(12.0 * _s)))
	if list.is_empty():
		return panel
	var ctx := _team_ctx(rows, team)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(3.0 * _s))
	panel.add_child(box)
	box.add_child(_lab("战后数据 · %s" % ("我方" if team == my_team else "敌方"),
		UiKit.FS_MD, color))
	var grid := GridContainer.new()
	grid.columns = list.size() + 1
	grid.add_theme_constant_override("h_separation", int(12.0 * _s))
	grid.add_theme_constant_override("v_separation", int(1.0 * _s))
	box.add_child(grid)
	# 表头：英雄头像 + 英雄名 + 评分
	grid.add_child(_lab("评分", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	for r in list:
		var nm := str(r.get("name", "—"))
		if bool(r.get("mine", false)):
			nm += "（我）"
		var sc := _rating(r, ctx)
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", int(1.0 * _s))
		head.add_child(_hero_face(str(r.get("name", "—")), color, int(28.0 * _s)))
		head.add_child(_lab("%s · %.1f %s" % [nm, sc, _grade(sc)], UiKit.FS_SM, color))
		grid.add_child(head)
	# 每项数据：队内最高标金
	var matrix: Array = []
	for r in list:
		matrix.append(_hero_stats(r, ctx))
	for si in STAT_META.size():
		var sn: String = STAT_META[si][1]
		grid.add_child(_lab("%s %s" % [STAT_META[si][0], sn], UiKit.FS_SM, UiKit.C_TEXT_DIM))
		var best := 0.0
		for col in matrix:
			best = maxf(best, float(col[si]))
		for col in matrix:
			var v := float(col[si])
			var lc: Color = UiKit.C_GOLD if (best > 0.0 and v >= best - 0.0001) else UiKit.C_TEXT
			grid.add_child(_lab(_fmt_stat(sn, v), UiKit.FS_SM, lc))
	return panel


# ---------- 图标 / 阵营小工具 ----------

func _team_color(team: int) -> Color:
	return UiKit.C_TEAM0 if team == Config.Team.PLAYER else UiKit.C_TEAM1


## 找玩家自己的行（优先 mine；旧纪录没有 mine 时退而取玩家阵营第一行）
func _find_mine_row(rows: Array, my_team: int) -> Dictionary:
	for r in rows:
		if bool(r.get("mine", false)) and int(r.get("team", -1)) in [Config.Team.PLAYER, Config.Team.ENEMY]:
			return r
	for r in rows:
		if int(r.get("team", -1)) == my_team:
			return r
	return {}


## 英雄头像控件（HBox 中使用时按正方形显示）
func _hero_face(hero_name: String, accent: Color, px: int) -> Control:
	var face := HeroFace.new()
	face.hero_name = hero_name
	face.ring = accent
	face.custom_minimum_size = Vector2(px, px)
	face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return face


## 装备图标条：最多 6 格，空槽画暗底；图标带装备名 tooltip
func _item_strip(entries: Array, px: int, slots: int = 6) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", int(4.0 * _s))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(slots):
		var ic := ItemSlotIcon.new()
		ic.custom_minimum_size = Vector2(px, px)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < entries.size():
			var e = entries[i]
			var nm := str(e[0]) if e is Array else str(e)
			var tier := int(e[1]) if (e is Array and (e as Array).size() > 1) else 1
			ic.item_name = nm
			ic.tier = tier
			ic.tooltip_text = nm
		else:
			ic.item_name = ""
			ic.tier = 1
		strip.add_child(ic)
	return strip


## 从行数据取装备：[名称, 品质]。兼容新记录 equips、联机 equip 的 ID、旧记录 items 名称。
func _row_equips(r: Dictionary) -> Array:
	var out: Array = []
	var equips = r.get("equips", [])
	if equips is Array:
		for e in equips:
			if e is Array and (e as Array).size() >= 2:
				out.append([str(e[0]), int(e[1])])
			elif e is Dictionary:
				out.append([str((e as Dictionary).get("name", "")), int((e as Dictionary).get("tier", 1))])
	if out.is_empty():
		for id in r.get("equip", []):
			var info: Dictionary = ItemDatabase.get_item(str(id))
			if not info.is_empty():
				out.append([str(info.get("name", id)), int(info.get("tier", 1))])
	if out.is_empty():
		for nm in r.get("items", []):
			out.append([str(nm), _tier_for_item(str(nm))])
	return out


## 旧纪录只有装备名：查 ItemDatabase 回填品质（缓存避免每行全表扫描）
func _tier_for_item(item_name: String) -> int:
	if _item_tier_cache.has(item_name):
		return int(_item_tier_cache[item_name])
	for v in ItemDatabase.items.values():
		if str(v.get("name", "")) == item_name:
			_item_tier_cache[item_name] = int(v.get("tier", 1))
			return int(v.get("tier", 1))
	_item_tier_cache[item_name] = 1
	return 1


# ---------- 小工具 ----------

func _fs(tier: int) -> int:
	return int(round(tier * _s))


func _lab(txt: String, tier: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", _fs(tier))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(txt: String, accent: Color, filled := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b.custom_minimum_size = Vector2(0, int(52.0 * _s))
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))
	b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.0) if filled else UiKit.C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.0) if filled else Color.WHITE)
	return b


func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()


func _close() -> void:
	queue_free()


func _time_text(ts: int) -> String:
	if ts <= 0:
		return "—"
	var d := Time.get_datetime_dict_from_unix_time(ts)
	return "%02d-%02d %02d:%02d" % [int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"])]


func _dur_text(seconds: float) -> String:
	var t := int(maxf(0.0, seconds))
	if t <= 0:
		return "—"
	return "%d分%02d秒" % [t / 60, t % 60]


func _gold_text(g: int) -> String:
	if g >= 1000:
		return "%.1fk" % (g / 1000.0)
	return str(g)


func _signed_gold(g: int) -> String:
	var t := _gold_text(absi(g))
	return ("+" + t) if g >= 0 else ("-" + t)


## 段位变化文本（旧纪录没有 rank 字段 → 返回空串）
func _rank_text(rank: Variant) -> String:
	if not (rank is Dictionary) or (rank as Dictionary).is_empty():
		return ""
	var d := rank as Dictionary
	var old_label := str(d.get("old_label", ""))
	var new_label := str(d.get("new_label", ""))
	if old_label == "" and new_label == "":
		return ""
	var mark := ""
	if bool(d.get("promoted", false)):
		mark = "（晋升）"
	elif bool(d.get("demoted", false)):
		mark = "（降段）"
	elif bool(d.get("protected", false)):
		mark = "（保星）"
	var delta := int(d.get("star_change", 0))
	var dtxt := ("+%d 星" % delta) if delta > 0 else ("%d 星" % delta)
	return " · 段位 %s → %s %s%s" % [old_label, new_label, dtxt, mark]


# ==================== 内部控件：英雄头像 / 装备图标 ====================

class HeroFace extends Control:
	const ART = preload("res://scripts/ui/HeroArt.gd")
	var hero_name: String = ""
	var ring: Color = Color.WHITE
	var dead := false

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		if r <= 2.0:
			return
		var c: Vector2 = size * 0.5
		ART.draw_portrait(self, c, maxf(1.0, r - 2.0), hero_name, ring, dead)
		draw_arc(c, r - 1.0, 0.0, TAU, 40, ring, 2.0, true)


class ItemSlotIcon extends Control:
	var item_name: String = ""
	var tier: int = 1

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		if s <= 2.0:
			return
		var rect := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
		if item_name == "":
			draw_style_box(UiKit.flat(0.5, 5, 1, Color(0.30, 0.36, 0.46, 0.5),
				Color(0.06, 0.07, 0.10, 0.55), 0.0, 0.0), rect)
			return
		UiKit.item_icon(self, rect, tier, item_name)

