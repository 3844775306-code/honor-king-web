extends Control
## 全局英雄信息面板（主机 C 键 / 联机客户端 C·T 键共用视图）
## 版式：顶部结论条 + 左右分队双列（左=我方蓝底板 / 右=敌方红底板），
## 每列 5 行按该队总经济从高到低排序；自己所在行用绿色底板。
## 单卡 = 队内名次 / 头像 / 名字·等级·分路 / 血量 / 4 个技能图标 / 6 格装备 / 属性徽章 / KDA·经济。
## 纯 _draw 绘制，数据由 host UI_Manager 或 NetSession 推送的 roster 行转换而来。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const SkillArt = preload("res://scripts/ui/SkillArt.gd")

signal closed_by_user

const PANEL_W := 2160.0
const HEAD_H := 96.0
const ROW_GAP := 12.0
const COL_GAP := 24.0
const TEAM_ROWS := 5
const C_ALLY := Color(0.22, 0.66, 1.0)
const C_ENEMY := Color(1.0, 0.33, 0.264)
const C_OWN := Color(0.36, 0.95, 0.55)
const C_GOLD := Color(0.98, 0.84, 0.38)
const C_DIM := Color(0.66, 0.73, 0.85)
const C_CARD_ALLY := Color(0.045, 0.145, 0.315, 0.92)
const C_CARD_ENEMY := Color(0.235, 0.045, 0.065, 0.92)
const C_CARD_OWN := Color(0.035, 0.215, 0.115, 0.94)
const PAD := 0.965

var rows: Array = []
var mode := "attr"
var panel_h := 1200.0
var _row_h := 200.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_rows(r: Array, md: String = "attr") -> void:
	# 两队各自按总经济降序（并列时按击杀、再按名字稳定排序），列内名次即队内经济名次
	rows = r.duplicate()
	rows.sort_custom(func(a, b):
		var ga := int(a.get("gold", 0))
		var gb := int(b.get("gold", 0))
		if ga != gb:
			return ga > gb
		var ka := int(a.get("k", 0))
		var kb := int(b.get("k", 0))
		if ka != kb:
			return ka > kb
		return str(a.get("name", "")) < str(b.get("name", "")))
	mode = md
	# 只更新数据，不在这里显示面板：面板开关必须由持有者统一控制，
	# 否则关闭后下一次秒级刷新会把已关闭的面板重新弹出来。
	if visible:
		queue_redraw()

func _s() -> float:
	return clampf(UiKit.scale(), 0.88, 1.35)

func _split() -> Array:
	var ally: Array = []
	var foe: Array = []
	for r in rows:
		if Config.is_ally(int(r.get("team", 0))):
			ally.append(r)
		else:
			foe.append(r)
	return [ally, foe]

## 版式：全部由自身矩形（= 屏幕可用区）推算，保证任何分辨率/缩放下不越界
func _layout() -> Dictionary:
	var avail := size
	if avail.x <= 1.0 or avail.y <= 1.0:
		avail = Vector2(2400.0, 1400.0)
	var need_h := HEAD_H + 22.0 + 5.0 * 206.0 + ROW_GAP * float(TEAM_ROWS - 1)
	var s := minf(_s(), minf(avail.x * PAD / PANEL_W, avail.y * PAD / need_h))
	var ph := minf(avail.y * PAD / s, 1600.0)
	var rh := maxf((ph - HEAD_H - 22.0 - ROW_GAP * float(TEAM_ROWS - 1)) / float(TEAM_ROWS), 168.0)
	var w := PANEL_W * s
	var h := minf((HEAD_H + 22.0 + rh * float(TEAM_ROWS) + ROW_GAP * float(TEAM_ROWS - 1)) * s, avail.y * PAD)
	return {"s": s, "ph": ph, "rh": rh, "w": w, "h": h, "o": ((avail - Vector2(w, h)) * 0.5).floor()}

func _draw() -> void:
	var L := _layout()
	var s: float = L.s
	panel_h = L.ph
	_row_h = L.rh
	var origin: Vector2 = L.o
	draw_set_transform(origin, 0.0, Vector2(s, s))
	# 背板
	draw_style_box(UiKit.flat(0.96, 18, 1, Color(0.40, 0.50, 0.66, 0.55), Color(0.035, 0.045, 0.07, 0.97), 0.0, 20.0),
		Rect2(0.0, 0.0, PANEL_W, panel_h))
	draw_rect(Rect2(24.0, 0.0, PANEL_W - 48.0, 2.5), Color(0.98, 0.82, 0.32, 0.85))
	_header()
	var split := _split()
	var ally: Array = split[0]
	var foe: Array = split[1]
	var cw := (PANEL_W - 44.0 - COL_GAP) * 0.5
	var y := HEAD_H + 6.0
	for i in range(TEAM_ROWS):
		var ar: Dictionary = ally[i] if i < ally.size() else {}
		var er: Dictionary = foe[i] if i < foe.size() else {}
		_card(ar, i + 1, true, Rect2(22.0, y, cw, _row_h))
		_card(er, i + 1, false, Rect2(22.0 + cw + COL_GAP, y, cw, _row_h))
		y += _row_h + ROW_GAP
	# 关闭按钮
	var cr := _close_rect()
	draw_style_box(UiKit.flat(0.7, 8, 1, Color(0.45, 0.55, 0.72, 0.6), Color(0.10, 0.12, 0.18, 0.9), 0.0, 4.0), cr)
	UiKit.text(self, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.74), "×", 22,
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _header() -> void:
	var split := _split()
	var ally: Array = split[0]
	var foe: Array = split[1]
	var ag := 0
	var eg := 0
	var ak := 0
	var ek := 0
	var aa := 0
	var ea := 0
	var al := 0
	var el := 0
	for r in ally:
		ag += int(r.get("gold", 0)); ak += int(r.get("k", 0)); aa += int(r.get("a", 0))
		if not bool(r.get("dead", false)): al += 1
	for r in foe:
		eg += int(r.get("gold", 0)); ek += int(r.get("k", 0)); ea += int(r.get("a", 0))
		if not bool(r.get("dead", false)): el += 1
	# 左上：我方标题 + 汇总（蓝）
	UiKit.text(self, Vector2(44.0, 44.0), "我方" if mode != "team" else "我方队伍", 30, C_ALLY)
	UiKit.text(self, Vector2(140.0, 43.0), "经济 %s · 击杀 %d · 存活 %d/5" % [_fmt_gold(ag), ak, al], 19, Color(0.82, 0.90, 1.0))
	# 右上：敌方标题 + 汇总（红，右对齐）
	var rx := PANEL_W - 44.0
	UiKit.text(self, Vector2(rx - 340.0, 44.0), "敌方", 30, C_ENEMY, HORIZONTAL_ALIGNMENT_RIGHT, 340.0)
	UiKit.text(self, Vector2(rx - 560.0, 43.0), "敌方 经济 %s · 击杀 %d · 存活 %d/5" % [_fmt_gold(eg), ek, el], 19,
		Color(1.0, 0.82, 0.78), HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	# 中间：经济差
	var diff := ag - eg
	var diff_col := Color(0.40, 0.95, 0.55) if diff >= 0 else Color(1.0, 0.36, 0.30)
	UiKit.text(self, Vector2(PANEL_W * 0.5 - 130.0, 44.0), "经济差 %s%d" % ["+" if diff >= 0 else "-", absi(diff)],
		23, diff_col, HORIZONTAL_ALIGNMENT_CENTER, 260.0)
	# 图例（自己=绿底板）
	UiKit.text(self, Vector2(44.0, 76.0), "两列各按本队经济从高到低 · 绿底=你 · 点面板外或 × 关闭", 17,
		Color(0.62, 0.70, 0.82))
	draw_rect(Rect2(24.0, 88.0, PANEL_W - 48.0, 1.0), Color(0.40, 0.50, 0.66, 0.30))

# ---------- 单行卡 ----------

func _card(r: Dictionary, rank: int, ally_side: bool, rect: Rect2) -> void:
	var accent := C_ALLY if ally_side else C_ENEMY
	var plate := C_CARD_ALLY if ally_side else C_CARD_ENEMY
	if r.is_empty():
		draw_style_box(UiKit.flat(0.42, 12, 1, Color(accent.r, accent.g, accent.b, 0.22), Color(0.05, 0.06, 0.09, 0.55), 0.0, 6.0), rect)
		UiKit.text(self, rect.position + Vector2(0.0, rect.size.y * 0.5), "（暂无英雄）", 19, C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		return
	var dead := bool(r.get("dead", false))
	var own := bool(r.get("own", false))
	if own:
		accent = C_OWN
		plate = C_CARD_OWN
	var sb := UiKit.flat(0.92, 12, 1, accent, plate, 0.0, 8.0)
	sb.border_width_left = 6
	draw_style_box(sb, rect)
	var x := rect.position.x
	var y := rect.position.y
	var W := rect.size.x
	var H := rect.size.y
	var hero_name := str(r.get("hero", r.get("name", "")))
	# 队内名次徽章（含绿色=自己时描边绿）
	draw_circle(Vector2(x + 36.0, y + 40.0), 19.0, Color(accent.r, accent.g, accent.b, 0.18))
	draw_arc(Vector2(x + 36.0, y + 40.0), 19.0, 0.0, TAU, 26, Color(accent.r, accent.g, accent.b, 0.85), 2.0, true)
	UiKit.text(self, Vector2(x + 17.0, y + 49.0), str(rank), 24, accent.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, 38.0)
	# 头像（程序化立绘，与选人界面同源）
	HeroArt.draw_portrait(self, Vector2(x + 104.0, y + 74.0), 44.0, hero_name, accent, dead)
	# 名字 / 等级·分路·状态
	var nm := str(r.get("name", "?"))
	if bool(r.get("is_ai", false)):
		nm += " [AI]"
	if own:
		nm += "  （你）"
	UiKit.text(self, Vector2(x + 162.0, y + 58.0), nm, 29,
		C_OWN.lightened(0.25) if own else (Color.WHITE if ally_side else Color(1.0, 0.72, 0.68)))
	var sub := "Lv.%d" % int(r.get("level", 1))
	var role := str(r.get("role", ""))
	if role != "":
		sub += "  ·  " + role
	if dead:
		sub += "  ·  %ds 复活" % int(ceil(float(r.get("respawn", 0.0))))
	elif float(r.get("hp_ratio", 1.0)) < 0.3:
		sub += "  ·  残血"
	UiKit.text(self, Vector2(x + 162.0, y + 88.0), sub, 18, C_GOLD if not dead else Color(1.0, 0.48, 0.42))
	# 血条
	var hp_w := 200.0
	draw_rect(Rect2(x + 162.0, y + 98.0, hp_w, 6.0), Color(0.08, 0.11, 0.16, 0.9))
	draw_rect(Rect2(x + 162.0, y + 98.0, hp_w * clampf(float(r.get("hp_ratio", 1.0)), 0.0, 1.0), 6.0),
		Color(0.32, 0.92, 0.48) if not dead else Color(0.55, 0.32, 0.30))
	# 右上：KDA / 经济
	var rx := x + W - 24.0
	UiKit.text(self, Vector2(rx - 230.0, y + 52.0), "%d / %d / %d" % [int(r.get("k", 0)), int(r.get("d", 0)), int(r.get("a", 0))],
		26, Color(0.92, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 224.0)
	UiKit.text(self, Vector2(rx - 230.0, y + 84.0), "经济 %s" % _fmt_gold(int(r.get("gold", 0))), 23, C_GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT, 224.0)
	# 技能图标 4 个（1/2/3 + 召唤）：真实程序化技能图标
	var sk: Array = r.get("skills", [])
	for i in range(4):
		var has := i < sk.size()
		var slot := int(sk[i][0]) if has else (9 if i == 3 else i + 1)
		var sname := str(sk[i][1]) if has else ""
		var lv := int(sk[i][2]) if has else 0
		var cd := float(sk[i][3]) if has else 0.0
		var stype := int(sk[i][4]) if has and (sk[i] as Array).size() > 4 else -1
		var cpos := Vector2(x + 176.0 + float(i) * 56.0, y + 152.0)
		SkillArt.draw_icon(self, cpos, 21.0, hero_name, sname, stype, slot, lv > 0, cd <= 0.0)
		if cd > 0.0:
			var frac := clampf(cd / maxf(cd + 0.01, 6.0), 0.0, 1.0)
			draw_arc(cpos, 20.4, -PI * 0.5, -PI * 0.5 + TAU * frac, 20, Color(0, 0, 0, 0.72), 4.0, true)
		if lv > 0:
			UiKit.text(self, Vector2(cpos.x + 11.0, cpos.y + 30.0), "%d" % lv, 14, C_GOLD)
	# 装备图标 6 格
	var eq: Array = r.get("equips", [])
	for i in range(6):
		var ir := Rect2(x + 416.0 + float(i) * 33.0, y + 128.0, 27.0, 27.0)
		if i < eq.size():
			var e: Array = eq[i]
			UiKit.item_icon(self, ir, int(e[1]) if e.size() > 1 else 1, str(e[0]))
		else:
			draw_style_box(UiKit.flat(0.5, 5, 1, Color(0.30, 0.36, 0.46, 0.5), Color(0.06, 0.07, 0.10, 0.55), 0.0, 0.0), ir)
	# 属性徽章（装备下方，最多 4 条）
	var chips: Array = r.get("chips", [])
	var cx := x + 416.0
	var cy2 := y + 184.0
	var shown := 0
	for c in chips:
		if shown >= 4:
			break
		if cx > x + W - 30.0:
			break
		cx = _chip(cx, cy2, str(c[0]), c[1], str(c[2]))
		shown += 1
	# 死亡压暗
	if dead:
		draw_style_box(UiKit.flat(0.55, 12, 0, Color(0, 0, 0, 0), Color(0.02, 0.02, 0.04, 0.55), 0.0, 0.0), rect)

func _chip(x: float, baseline: float, glyph: String, col: Color, txt: String) -> float:
	_glyph(Vector2(x + 8.0, baseline - 6.0), 8.0, glyph, col)
	UiKit.text(self, Vector2(x + 22.0, baseline), txt, 16, col.lightened(0.32))
	var w := UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	return x + 26.0 + w + 10.0

func _glyph(c: Vector2, r: float, id: String, col: Color) -> void:
	var w := maxf(r * 0.34, 1.2)
	match id:
		"heart":
			draw_circle(c + Vector2(-r * 0.34, -r * 0.18), r * 0.46, col)
			draw_circle(c + Vector2(r * 0.34, -r * 0.18), r * 0.46, col)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.80, r * 0.02), c + Vector2(r * 0.80, r * 0.02), c + Vector2(0, r * 0.95)]), col)
		"sword":
			draw_line(c + Vector2(-r * 0.65, r * 0.75), c + Vector2(r * 0.55, -r * 0.75), col, w * 1.3, true)
			draw_line(c + Vector2(-r * 0.70, r * 0.30), c + Vector2(-r * 0.20, r * 0.80), col.lightened(0.4), w, true)
		"spark":
			for i in range(4):
				var a := i * PI / 2.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.95, col, w, true)
		"shield":
			draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.70, -r * 0.55), c + Vector2(0, -r * 0.90), c + Vector2(r * 0.70, -r * 0.55),
				c + Vector2(r * 0.70, r * 0.10), c + Vector2(0, r * 0.92), c + Vector2(-r * 0.70, r * 0.10),
				c + Vector2(-r * 0.70, -r * 0.55)]), col, w * 1.1, true)
		"gem":
			draw_polyline(PackedVector2Array([
				c + Vector2(0, -r * 0.92), c + Vector2(r * 0.68, 0), c + Vector2(0, r * 0.92),
				c + Vector2(-r * 0.68, 0), c + Vector2(0, -r * 0.92)]), col, w * 1.1, true)
		"chev":
			draw_polyline(PackedVector2Array([
				c + Vector2(-r * 0.70, r * 0.55), c + Vector2(0, -r * 0.40), c + Vector2(r * 0.70, r * 0.55)]), col, w * 1.2, true)
		"bolt":
			draw_polyline(PackedVector2Array([
				c + Vector2(r * 0.20, -r * 0.92), c + Vector2(-r * 0.52, r * 0.08),
				c + Vector2(-r * 0.02, r * 0.08), c + Vector2(-r * 0.26, r * 0.92)]), col, w * 1.2, true)
		"drop":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.92), c + Vector2(r * 0.58, r * 0.30), c + Vector2(0, r * 0.90),
				c + Vector2(-r * 0.58, r * 0.30)]), col)
		"cross":
			draw_line(c + Vector2(-r * 0.75, 0), c + Vector2(r * 0.75, 0), col, w * 1.4, true)
			draw_line(c + Vector2(0, -r * 0.75), c + Vector2(0, r * 0.75), col, w * 1.4, true)
		"dmg":
			draw_line(c + Vector2(-r * 0.60, r * 0.60), c + Vector2(r * 0.55, -r * 0.62), col, w * 1.5, true)
			draw_circle(c + Vector2(r * 0.66, -r * 0.72), r * 0.26, col.lightened(0.3))
		"pierce":
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.92, 0), c + Vector2(-r * 0.55, -r * 0.62), c + Vector2(-r * 0.55, r * 0.62)]), col)
		"tough":
			for i in range(3):
				var a := i * PI / 3.0
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.75, c + Vector2(cos(a), sin(a)) * -r * 0.75, col, w, true)
		"clock":
			draw_arc(c, r * 0.80, 0, TAU, 18, col, w * 1.2, true)
			draw_line(c, c + Vector2(0, -r * 0.55), col, w, true)
			draw_line(c, c + Vector2(r * 0.42, 0), col, w, true)
		_:
			draw_circle(c, r * 0.55, col)

func _close_rect() -> Rect2:
	return Rect2(PANEL_W - 92.0, 14.0, 40.0, 34.0)

func _fmt_gold(v: int) -> String:
	if v >= 10000:
		return "%.1f万" % (float(v) / 10000.0)
	return str(v)

func _gui_input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not press:
		return
	var L := _layout()
	var s: float = L.s
	var origin: Vector2 = L.o
	var p: Vector2 = ((ev as InputEventMouse).position - origin) / s if ev is InputEventMouse \
		else ((ev as InputEventScreenTouch).position - origin) / s
	var in_panel := Rect2(0.0, 0.0, PANEL_W, float(L.ph)).has_point(p)
	if _close_rect().has_point(p) or not in_panel:
		closed_by_user.emit()
		UiKit.hide_panel(self, 0.12)
		visible = false
		accept_event()

func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		closed_by_user.emit()
		visible = false
		get_viewport().set_input_as_handled()
