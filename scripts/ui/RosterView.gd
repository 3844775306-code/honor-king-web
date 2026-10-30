extends Control
## 全局英雄信息面板（主机 C 键 / 联机客户端 C·T 键共用视图）
## 版式：顶部结论条 + 5 行「分路对位」双列（左我方 / 右敌方），单卡=头像/名字/等级/状态/KDA/属性徽章/装备图标/技能徽章。
## 纯 _draw 绘制，数据由 host UI_Manager 或 NetSession 推送的 roster 行转换而来。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")

signal closed_by_user

const PANEL_W := 2160.0
const HEAD_H := 96.0
const ROW_GAP := 10.0
const C_ALLY := Color(0.0, 0.886, 1.0)
const C_ENEMY := Color(1.0, 0.33, 0.264)
const C_GOLD := Color(0.98, 0.84, 0.38)
const C_DIM := Color(0.66, 0.73, 0.85)
const C_CARD_ALLY := Color(0.03, 0.10, 0.18, 0.86)
const C_CARD_ENEMY := Color(0.14, 0.04, 0.06, 0.86)
const SKILL_TAG := ["1", "2", "3", "召"]
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
	rows = r
	mode = md
	if not visible:
		visible = true
		UiKit.show_panel(self, 0.15)
	queue_redraw()

func _s() -> float:
	return clampf(UiKit.scale(), 0.88, 1.35)

## 版式：全部由自身矩形（= 屏幕可用区）推算，保证任何分辨率/缩放下不越界
func _layout() -> Dictionary:
	var avail := size
	if avail.x <= 1.0 or avail.y <= 1.0:
		avail = Vector2(2400.0, 1400.0)
	var s := minf(_s(), minf(avail.x * PAD / PANEL_W, 1.35))
	var ph := minf(avail.y * PAD / s, 1600.0)
	var rh := maxf((ph - HEAD_H - 24.0 - ROW_GAP * 5.0) / 5.0, 112.0)
	var w := PANEL_W * s
	var h := ph * s
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
	var pairs := _pair_rows()
	var y := HEAD_H + 6.0
	for i in range(5):
		var ally: Dictionary = pairs[i][0]
		var foe: Dictionary = pairs[i][1]
		_card(ally, Rect2(22.0, y, PANEL_W * 0.5 - 32.0, _row_h), C_CARD_ALLY, C_ALLY)
		_card(foe, Rect2(PANEL_W * 0.5 + 10.0, y, PANEL_W * 0.5 - 32.0, _row_h), C_CARD_ENEMY, C_ENEMY)
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
	var title := "队伍信息" if mode == "team" else "战场信息"
	UiKit.text(self, Vector2(44.0, 44.0), title, 32, C_GOLD)
	# 结论条：经济差 / 人头 / 存活（由行数据实时汇总，两端同源）
	var ag := 0
	var eg := 0
	var ak := 0
	var ek := 0
	var aa := 0
	var ea := 0
	var al := 0
	var el := 0
	for r in rows:
		var team := int(r.get("team", 0))
		if team == 0:
			ag += int(r.get("gold", 0)); ak += int(r.get("k", 0)); aa += int(r.get("a", 0))
			if not bool(r.get("dead", false)): al += 1
		else:
			eg += int(r.get("gold", 0)); ek += int(r.get("k", 0)); ea += int(r.get("a", 0))
			if not bool(r.get("dead", false)): el += 1
	var diff := ag - eg
	var diff_col := Color(0.40, 0.95, 0.55) if diff >= 0 else Color(1.0, 0.36, 0.30)
	var x := 190.0
	var txt := "经济差 %s%d" % ["+" if diff >= 0 else "-", absi(diff)]
	UiKit.text(self, Vector2(x, 44.0), txt, 21, diff_col)
	x += UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 26.0
	txt = "击杀 %d:%d" % [ak, ek]
	UiKit.text(self, Vector2(x, 44.0), txt, 21, Color(0.88, 0.92, 0.98))
	x += UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 26.0
	txt = "存活 %d:%d" % [al, el]
	UiKit.text(self, Vector2(x, 44.0), txt, 21, Color(0.88, 0.92, 0.98))
	UiKit.text(self, Vector2(44.0, 76.0), "按分路对位 · 点面板外或 × 关闭", 17, Color(0.62, 0.70, 0.82))
	# 分隔
	draw_rect(Rect2(24.0, 88.0, PANEL_W - 48.0, 1.0), Color(0.40, 0.50, 0.66, 0.30))

# ---------- 单卡 ----------

func _card(r: Dictionary, rect: Rect2, bg: Color, accent: Color) -> void:
	if r.is_empty():
		draw_style_box(UiKit.flat(0.5, 12, 1, Color(0.3, 0.36, 0.46, 0.35), Color(0.06, 0.07, 0.10, 0.6), 0.0, 6.0), rect)
		UiKit.text(self, rect.position + Vector2(0.0, rect.size.y * 0.5), "（无对位英雄）", 19, C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		return
	var dead := bool(r.get("dead", false))
	var sb := UiKit.flat(0.9, 12, 1, accent, bg, 0.0, 8.0)
	sb.border_width_left = 4
	draw_style_box(sb, rect)
	var x := rect.position.x
	var y := rect.position.y
	var ch := rect.size.y
	var top := y + (ch - 148.0) * 0.5
	if top < y + 8.0:
		top = y + 8.0
	# 头像环
	HeroArt.draw_portrait(self, Vector2(x + 44.0, top + 44.0), 32.0, str(r.get("hero", r.get("name", ""))),
		accent, dead)
	# 名字 / 等级 / 分路
	var nm := str(r.get("name", "?"))
	if bool(r.get("is_ai", false)):
		nm += " [AI]"
	UiKit.text(self, Vector2(x + 84.0, top + 34.0), nm, 27, Color.WHITE if int(r.get("team", 0)) == 0 else Color(1.0, 0.66, 0.62))
	var sub := "Lv.%d" % int(r.get("level", 1))
	var role := str(r.get("role", ""))
	if role != "":
		sub += "  ·  " + role
	UiKit.text(self, Vector2(x + 84.0, top + 58.0), sub, 18, C_GOLD)
	# 状态
	var st := "存活"
	var stc := Color.GREEN
	if dead:
		st = "%ds 后复活" % int(ceil(float(r.get("respawn", 0.0))))
		stc = Color(1.0, 0.42, 0.36)
	elif float(r.get("hp_ratio", 1.0)) < 0.3:
		st = "残血"
		stc = Color.ORANGE
	UiKit.text(self, Vector2(x + 84.0, top + 80.0), st, 18, stc)
	# KDA / 经济（右对齐）
	var rx := x + rect.size.x - 18.0
	UiKit.text(self, Vector2(rx - 220.0, top + 34.0), "%d / %d / %d" % [int(r.get("k", 0)), int(r.get("d", 0)), int(r.get("a", 0))],
		24, Color(0.92, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	UiKit.text(self, Vector2(rx - 220.0, top + 58.0), "经济 %s" % _fmt_gold(int(r.get("gold", 0))), 18, C_GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT, 210.0)
	# 属性徽章（最多 7，超出折叠）
	var chips: Array = r.get("chips", [])
	var cx := x + 84.0
	var cy := top + 104.0
	var shown := 0
	for c in chips:
		if shown >= 7:
			UiKit.text(self, Vector2(cx, cy), "+%d" % (chips.size() - 7), 16, C_DIM)
			break
		cx = _chip(cx, cy, str(c[0]), c[1], str(c[2]))
		shown += 1
	if chips.is_empty():
		UiKit.text(self, Vector2(cx, cy), "（无属性）", 16, C_DIM)
	# 装备图标 6 格
	var eq: Array = r.get("equips", [])
	for i in range(6):
		var ir := Rect2(x + 84.0 + float(i) * 30.0, top + 118.0, 26.0, 26.0)
		if i < eq.size():
			var e: Array = eq[i]
			UiKit.item_icon(self, ir, int(e[1]) if e.size() > 1 else 1, str(e[0]))
		else:
			draw_style_box(UiKit.flat(0.5, 5, 1, Color(0.30, 0.36, 0.46, 0.5), Color(0.06, 0.07, 0.10, 0.55), 0.0, 0.0), ir)
	# 技能徽章 4 个（1/2/3/召唤）
	var sk: Array = r.get("skills", [])
	var hero_name := str(r.get("hero", r.get("name", "")))
	var acc := HeroArt.accent_of(hero_name)
	for i in range(4):
		var cpos := Vector2(x + 300.0 + float(i) * 40.0, top + 131.0)
		var slot := int(sk[i][0]) if i < sk.size() else (9 if i == 3 else i + 1)
		var cd := float(sk[i][3]) if i < sk.size() else 0.0
		var lv := int(sk[i][2]) if i < sk.size() else 0
		var ready := cd <= 0.0
		var tint := acc if ready else acc.darkened(0.55)
		draw_circle(cpos, 17.0, Color(tint.r, tint.g, tint.b, 0.22))
		draw_arc(cpos, 17.0, 0.0, TAU, 24, tint, 2.0, true)
		if not ready:
			var frac := clampf(cd / maxf(cd + 0.01, 6.0), 0.0, 1.0)
			draw_arc(cpos, 13.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 20, Color(0, 0, 0, 0.75), 4.0, true)
		UiKit.text(self, Vector2(cpos.x - 17.0, cpos.y + 6.0), SKILL_TAG[i], 18,
			Color.WHITE if ready else Color(0.72, 0.76, 0.84), HORIZONTAL_ALIGNMENT_CENTER, 34.0)
		if lv > 0:
			UiKit.text(self, Vector2(cpos.x + 8.0, cpos.y + 24.0), "%d" % lv, 14, C_GOLD)
	# 死亡压暗
	if dead:
		draw_style_box(UiKit.flat(0.55, 12, 0, Color(0, 0, 0, 0), Color(0.02, 0.02, 0.04, 0.55), 0.0, 0.0), rect)

func _chip(x: float, baseline: float, glyph: String, col: Color, txt: String) -> float:
	_glyph(Vector2(x + 8.0, baseline - 6.0), 8.5, glyph, col)
	UiKit.text(self, Vector2(x + 22.0, baseline), txt, 17, col.lightened(0.32))
	var w := UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	return x + 26.0 + w + 12.0

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

# ---------- 对位配对 ----------

func _pair_rows() -> Array:
	var ally: Array = []
	var foe: Array = []
	for r in rows:
		if int(r.get("team", 0)) == 0:
			ally.append(r)
		else:
			foe.append(r)
	var _by_lane := func(a, b):
		var la := int(a.get("lane", 99))
		var lb := int(b.get("lane", 99))
		if la != lb:
			return la < lb
		return int(a.get("gold", 0)) > int(b.get("gold", 0))
	ally.sort_custom(_by_lane)
	foe.sort_custom(_by_lane)
	var pairs: Array = []
	for i in range(5):
		pairs.append([ally[i] if i < ally.size() else {}, foe[i] if i < foe.size() else {}])
	return pairs

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
