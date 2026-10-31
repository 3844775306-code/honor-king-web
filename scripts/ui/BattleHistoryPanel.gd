class_name BattleHistoryPanel
extends Control
## 大厅「对战纪录」：列表（胜负 / 英雄 / KDA / 时间 / 比分）→ 点开某局 = 复刻结算面板。
## 数据来源 BattleHistory（user://battle_history.json），纯容器布局，随屏宽缩放。

var _recs: Array = []
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
		var empty := _lab("还没有对战纪录：打完一局（单机或联机）后，结算数据会自动记录在这里。", UiKit.FS_MD, UiKit.C_TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(empty)
		return
	for i in _recs.size():
		_body.add_child(_record_row(i))


func _record_row(i: int) -> Control:
	var rec: Dictionary = _recs[i]
	var win := int(rec.get("winner", -1)) == Config.Team.PLAYER
	var rows: Array = rec.get("rows", [])
	var k := 0
	var d := 0
	var a := 0
	var enemy_kills := 0
	var my_name := "—"
	var my_gold := 0
	var foe_gold := 0
	for r in rows:
		if int(r.get("team", -1)) == Config.Team.PLAYER:
			k += int(r.get("k", 0))
			d += int(r.get("d", 0))
			a += int(r.get("a", 0))
			my_gold += int(r.get("gold", 0))
			if bool(r.get("mine", false)):
				my_name = str(r.get("name", "—"))
		else:
			enemy_kills += int(r.get("k", 0))
			foe_gold += int(r.get("gold", 0))

	var accent: Color = UiKit.C_TEAM0 if win else UiKit.C_TEAM1
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiKit.skin_chip(accent, 0.5, int(12.0 * _s)))
	row.custom_minimum_size = Vector2(0, int(96.0 * _s))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(14.0 * _s))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)

	var badge := _lab("胜" if win else "负", UiKit.FS_XL, accent)
	badge.custom_minimum_size = Vector2(int(58.0 * _s), 0)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(col)
	col.add_child(_lab("%s    KDA %d/%d/%d" % [my_name, k, d, a], UiKit.FS_LG, UiKit.C_TEXT))
	col.add_child(_lab("%s · %s · 时长 %s" % [
		str(rec.get("mode", "单机")), _time_text(int(rec.get("ts", 0))), _dur_text(float(rec.get("dur", 0.0)))],
		UiKit.FS_SM, UiKit.C_TEXT_DIM))
	# 第三条：经济差 + 推塔 + 段位变化
	var turrets: Array = rec.get("turrets", [])
	var turret_txt := ""
	if turrets.size() >= 2:
		turret_txt = " · 推塔 %d/%d" % [int(turrets[1]), int(turrets[0])]
	var rank_txt := _rank_text(rec.get("rank", {}))
	col.add_child(_lab("经济差 %s%s%s" % [_signed_gold(my_gold - foe_gold), turret_txt, rank_txt],
		UiKit.FS_SM, UiKit.C_GOLD))

	var score := _lab("%d : %d" % [k, enemy_kills], UiKit.FS_XL, UiKit.C_GOLD)
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(score)
	var go := _lab("查看 ›", UiKit.FS_MD, UiKit.C_TEXT_DIM)
	go.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(go)

	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(i)
	)
	return row


# ---------- 结算回看 ----------

func _show_detail(i: int) -> void:
	_detail = i
	var rec: Dictionary = _recs[i]
	var win := int(rec.get("winner", -1)) == Config.Team.PLAYER
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
	# 总览条：击杀差 / 经济差 / 推塔 / 段位变化
	_body.add_child(_summary_strip(rec, rows))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(18.0 * _s))
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(cols)
	cols.add_child(_team_block("我方", rows, Config.Team.PLAYER, UiKit.C_TEAM0))
	cols.add_child(_team_block("敌方", rows, Config.Team.ENEMY, UiKit.C_TEAM1))
	# 与结算页「数据」页同口径的完整战后数据表
	_body.add_child(_data_table(rows, Config.Team.PLAYER, UiKit.C_TEAM0))
	_body.add_child(_data_table(rows, Config.Team.ENEMY, UiKit.C_TEAM1))


## 细节条：击杀差 / 经济差 / 推塔 / 段位变化 / 双方承伤总和
func _summary_strip(rec: Dictionary, rows: Array) -> Control:
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
		if int(r.get("team", -1)) == Config.Team.PLAYER:
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
		h.add_child(_lab("推塔 %d : %d" % [int(turrets[1]), int(turrets[0])], UiKit.FS_MD, UiKit.C_TEXT))
	h.add_child(_lab("我方承伤 %s · 治疗 %s · 控制 %.1fs" % [
		_gold_text(my_taken), _gold_text(my_heal), float(my_cc) / 10.0], UiKit.FS_MD, UiKit.C_TEXT_DIM))
	var rank_txt := _rank_text(rec.get("rank", {}))
	if rank_txt != "":
		h.add_child(_lab(rank_txt.trim_prefix(" · "), UiKit.FS_MD, UiKit.C_GOLD))
	return panel


func _team_block(title: String, rows: Array, team: int, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.skin_chip(Color(color.r, color.g, color.b, 0.4), 0.5, int(14.0 * _s)))
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
	col.add_child(_lab("%s    总击杀 %d · 团队经济 %s" % [title, kills, _gold_text(gold)], UiKit.FS_MD, color))
	for r in list:
		col.add_child(_row_line(r, color))
	if list.is_empty():
		col.add_child(_lab("—", UiKit.FS_MD, UiKit.C_TEXT_DIM))
	return panel


func _row_line(r: Dictionary, color: Color) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", int(10.0 * _s))
	wrap.add_child(h)
	var name_txt := str(r.get("name", "—"))
	if bool(r.get("mvp", false)):
		name_txt = "★ " + name_txt
	if bool(r.get("mine", false)):
		name_txt += "（我）"
	var nm := _lab(name_txt, UiKit.FS_MD, UiKit.C_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(nm)
	var role := str(r.get("role", ""))
	if role != "":
		h.add_child(_lab(role, UiKit.FS_SM, UiKit.C_TEXT_DIM))
	h.add_child(_lab("Lv.%d" % int(r.get("lv", 1)), UiKit.FS_SM, UiKit.C_TEXT_DIM))
	h.add_child(_lab("%d/%d/%d" % [int(r.get("k", 0)), int(r.get("d", 0)), int(r.get("a", 0))], UiKit.FS_MD, color))
	h.add_child(_lab(_gold_text(int(r.get("gold", 0))), UiKit.FS_SM, UiKit.C_GOLD))
	if int(r.get("dmg", 0)) > 0:
		h.add_child(_lab("输出 %s" % _gold_text(int(r.get("dmg", 0))), UiKit.FS_SM, UiKit.C_TEXT_DIM))
	# 第二行：承伤 / 治疗 / 控制 / 推塔伤害 / 补刀 / 野怪经济 + 装备
	var d2 := HBoxContainer.new()
	d2.add_theme_constant_override("separation", int(10.0 * _s))
	wrap.add_child(d2)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(int(6.0 * _s), 0)
	d2.add_child(gap)
	d2.add_child(_lab("承伤 %s · 治疗 %s · 控制 %.1fs · 推塔 %s · 补刀 %d · 野怪经济 %d" % [
		_gold_text(int(r.get("taken", 0))), _gold_text(int(r.get("heal", 0))),
		float(r.get("cc", 0)) / 10.0, _gold_text(int(r.get("turret", 0))),
		int(r.get("lh", 0)), int(r.get("jungle", 0))], UiKit.FS_SM, UiKit.C_TEXT_DIM))
	var items: Array = r.get("items", [])
	var item_txt := " · ".join(items) if not items.is_empty() else "—"
	var it := _lab("装备：%s" % item_txt, UiKit.FS_SM, Color(0.72, 0.78, 0.9))
	it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	it.clip_text = true
	d2.add_child(it)
	return wrap


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


func _data_table(rows: Array, team: int, color: Color) -> Control:
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
	box.add_child(_lab("战后数据 · %s" % ("我方" if team == Config.Team.PLAYER else "敌方"),
		UiKit.FS_MD, color))
	var grid := GridContainer.new()
	grid.columns = list.size() + 1
	grid.add_theme_constant_override("h_separation", int(12.0 * _s))
	grid.add_theme_constant_override("v_separation", int(1.0 * _s))
	box.add_child(grid)
	# 表头：英雄名 + 评分
	grid.add_child(_lab("评分", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	for r in list:
		var nm := str(r.get("name", "—"))
		if bool(r.get("mine", false)):
			nm += "（我）"
		var sc := _rating(r, ctx)
		grid.add_child(_lab("%s · %.1f %s" % [nm, sc, _grade(sc)], UiKit.FS_SM, color))
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

