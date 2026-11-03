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
var hud_info: Dictionary = {}   # 顶部附加战况（如主宰先锋波数）
var mode := "attr"
var panel_h := 1200.0
var _row_h := 200.0
# —— 装备悬浮详情（三端共用）：_draw 时记录每格装备的未缩放矩形与 item_id ——
var _equip_hits: Array = []          # [{rect:Rect2, id:String, name:String, tier:int}]
var _tip_hit: Dictionary = {}        # 当前悬浮的装备格（空=不显示）
var _tip_anchor := Vector2.ZERO      # 悬浮时鼠标/图标在图内的屏幕像素锚点
const ITEM_STATS := [
	["attack", "攻击"], ["ability_power", "法强"], ["health", "生命"], ["armor", "物防"],
	["magic_resist", "法防"], ["attack_speed", "攻速%"], ["crit_chance", "暴击%"],
	["crit_damage", "暴伤%"], ["lifesteal", "吸血%"], ["spell_vamp", "法吸%"],
	["cooldown", "冷缩%"], ["speed", "移速"], ["per_speed", "移速%"], ["mana", "蓝量"],
	["hp_regen", "回血"], ["armor_pen_percent", "物穿%"], ["magic_pen", "法穿"],
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func set_rows(r: Array, md: String = "attr", info: Dictionary = {}) -> void:
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
	hud_info = info
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
	_equip_hits.clear()
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
	UiKit.text(self, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.74), "×", 27,
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_item_tip(L)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_tip_hit = {}

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
	UiKit.text(self, Vector2(44.0, 44.0), "我方" if mode != "team" else "我方队伍", 37, C_ALLY)
	UiKit.text(self, Vector2(140.0, 43.0), "经济 %s · 击杀 %d · 存活 %d/5" % [_fmt_gold(ag), ak, al], 23, Color(0.82, 0.90, 1.0))
	# 右上：敌方标题 + 汇总（红，右对齐）
	var rx := PANEL_W - 44.0
	UiKit.text(self, Vector2(rx - 340.0, 44.0), "敌方", 37, C_ENEMY, HORIZONTAL_ALIGNMENT_RIGHT, 340.0)
	UiKit.text(self, Vector2(rx - 560.0, 43.0), "敌方 经济 %s · 击杀 %d · 存活 %d/5" % [_fmt_gold(eg), ek, el], 23,
		Color(1.0, 0.82, 0.78), HORIZONTAL_ALIGNMENT_RIGHT, 420.0)
	# 中间：经济差
	var diff := ag - eg
	var diff_col := Color(0.40, 0.95, 0.55) if diff >= 0 else Color(1.0, 0.36, 0.30)
	UiKit.text(self, Vector2(PANEL_W * 0.5 - 130.0, 44.0), "经济差 %s%d" % ["+" if diff >= 0 else "-", absi(diff)],
		28, diff_col, HORIZONTAL_ALIGNMENT_CENTER, 300.0)
	# 图例（自己=绿底板）
	UiKit.text(self, Vector2(44.0, 76.0), "两列各按本队经济从高到低 · 绿底=你 · 点面板外或 × 关闭", 21,
		Color(0.62, 0.70, 0.82))
	# 主宰/暗影/风暴被击败后的先锋波数（标注我方/敌方）
	var vg_txt := str(hud_info.get("vanguard", ""))
	if vg_txt != "":
		var vg_col: Color = hud_info.get("vanguard_color", Color(0.86, 0.92, 1.0))
		UiKit.text(self, Vector2(PANEL_W - 44.0 - 700.0, 76.0), vg_txt, 21, vg_col,
			HORIZONTAL_ALIGNMENT_RIGHT, 700.0)
	draw_rect(Rect2(24.0, 88.0, PANEL_W - 48.0, 1.0), Color(0.40, 0.50, 0.66, 0.30))

# ---------- 单行卡 ----------

func _card(r: Dictionary, rank: int, ally_side: bool, rect: Rect2) -> void:
	var accent := C_ALLY if ally_side else C_ENEMY
	var plate := C_CARD_ALLY if ally_side else C_CARD_ENEMY
	if r.is_empty():
		draw_style_box(UiKit.flat(0.42, 12, 1, Color(accent.r, accent.g, accent.b, 0.22), Color(0.05, 0.06, 0.09, 0.55), 0.0, 6.0), rect)
		UiKit.text(self, rect.position + Vector2(0.0, rect.size.y * 0.5), "（暂无英雄）", 23, C_DIM,
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
	# 版式按卡片高度等比放大，尽量占满整块面板：上半 = 头像/名字/KDA，下半 = 技能+装备+全部属性
	var k := clampf(H / 206.0, 0.85, 1.45)
	var top := y + 8.0 * k
	# 分区线（画在最底层，头像可压在线上）
	draw_rect(Rect2(x + 18.0, y + H * 0.50, W - 36.0, 1.0), Color(accent.r, accent.g, accent.b, 0.28))
	# 队内名次徽章（含绿色=自己时描边绿）
	var br := 19.0 * k
	var bc := Vector2(x + 30.0 * k + 8.0, top + br)
	draw_circle(bc, br, Color(accent.r, accent.g, accent.b, 0.18))
	draw_arc(bc, br, 0.0, TAU, 26, Color(accent.r, accent.g, accent.b, 0.85), 2.0 * k, true)
	UiKit.text(self, Vector2(bc.x - br, bc.y + 9.0 * k), str(rank), int(28.0 * k), accent.lightened(0.35),
		HORIZONTAL_ALIGNMENT_CENTER, br * 2.0)
	# 头像（程序化立绘，与选人界面同源）——明显放大
	var pr := clampf(H * 0.27, 40.0, 66.0)
	var pc := Vector2(x + 44.0 * k + pr, top + pr + 4.0)
	HeroArt.draw_portrait(self, pc, pr, hero_name, accent, dead)
	# 原初印记等级：环上符文 + 段位色（1~6，不显示数字）
	HeroArt.draw_primitive_mark(self, pc, pr, int(r.get("mark", 0)))
	# 名字 / 等级·分路·状态
	var nm := str(r.get("name", "?"))
	if bool(r.get("is_ai", false)):
		nm += " [AI]"
	if own:
		nm += "  （你）"
	var nx := pc.x + pr + 18.0 * k
	var name_fs := int(clampf(H * 0.175, 27.0, 40.0))
	var name_base := top + name_fs * 0.98
	UiKit.text(self, Vector2(nx, name_base), nm, name_fs,
		C_OWN.lightened(0.25) if own else (Color.WHITE if ally_side else Color(1.0, 0.72, 0.68)))
	var sub := "Lv.%d" % int(r.get("level", 1))
	var role := str(r.get("role", ""))
	if role != "":
		sub += "  ·  " + role
	var mk_lv := int(r.get("mark", 0))
	if mk_lv > 0:
		sub += "  ·  原初 Lv.%d" % mk_lv
	if dead:
		sub += "  ·  %ds 复活" % int(ceil(float(r.get("respawn", 0.0))))
	elif float(r.get("hp_ratio", 1.0)) < 0.3:
		sub += "  ·  残血"
	var sub_fs := int(clampf(H * 0.105, 20.0, 26.0))
	UiKit.text(self, Vector2(nx, name_base + sub_fs + 10.0 * k), sub, sub_fs,
		C_GOLD if not dead else Color(1.0, 0.48, 0.42))
	# 血条（加宽加高）
	var hp_w := clampf(W * 0.24, 190.0, 300.0)
	var hp_y := name_base + sub_fs + 18.0 * k
	var hp_h := 7.0 * k
	draw_rect(Rect2(nx, hp_y, hp_w, hp_h), Color(0.08, 0.11, 0.16, 0.9))
	draw_rect(Rect2(nx, hp_y, hp_w * clampf(float(r.get("hp_ratio", 1.0)), 0.0, 1.0), hp_h),
		Color(0.32, 0.92, 0.48) if not dead else Color(0.55, 0.32, 0.30))
	# 右上：KDA / 经济
	var rx := x + W - 22.0
	var kda_fs := int(clampf(H * 0.155, 25.0, 33.0))
	UiKit.text(self, Vector2(rx - 250.0, name_base), "%d / %d / %d" % [int(r.get("k", 0)), int(r.get("d", 0)), int(r.get("a", 0))],
		kda_fs, Color(0.92, 0.95, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 250.0)
	UiKit.text(self, Vector2(rx - 250.0, name_base + sub_fs + 10.0 * k), "经济 %s" % _fmt_gold(int(r.get("gold", 0))),
		int(clampf(H * 0.13, 22.0, 28.0)), C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 230.0)
	# 下半区：技能图标 4 个（1/2/3 + 召唤，放大）+ 装备 6 格（放大）+ 全部属性徽章
	var band_cy := y + H * 0.75
	var sk_r := clampf(H * 0.125, 19.0, 30.0)
	var sk_step := sk_r * 2.0 + 10.0 * k
	var sk_x := x + 26.0 + sk_r
	var sk: Array = r.get("skills", [])
	for i in range(4):
		var has := i < sk.size()
		var slot := int(sk[i][0]) if has else (9 if i == 3 else i + 1)
		var sname := str(sk[i][1]) if has else ""
		var lv := int(sk[i][2]) if has else 0
		var cd := float(sk[i][3]) if has else 0.0
		var stype := int(sk[i][4]) if has and (sk[i] as Array).size() > 4 else -1
		var cpos := Vector2(sk_x + float(i) * sk_step, band_cy)
		SkillArt.draw_icon(self, cpos, sk_r, hero_name, sname, stype, slot, lv > 0, cd <= 0.0)
		if cd > 0.0:
			var frac := clampf(cd / maxf(cd + 0.01, 6.0), 0.0, 1.0)
			draw_arc(cpos, sk_r * 0.97, -PI * 0.5, -PI * 0.5 + TAU * frac, 22, Color(0, 0, 0, 0.72), 4.0 * k, true)
		if lv > 0:
			UiKit.text(self, Vector2(cpos.x - sk_r * 0.5, cpos.y + sk_r * 1.42), "%d" % lv, int(17.0 * k), C_GOLD,
				HORIZONTAL_ALIGNMENT_CENTER, sk_r)
	# 装备图标 6 格（放大到约 1.4 倍）
	var eq_s := clampf(H * 0.19, 26.0, 42.0)
	var eq_gap := 6.0 * k
	var eq_x := sk_x + 3.0 * sk_step + sk_r + 22.0 * k
	var eq: Array = r.get("equips", [])
	for i in range(6):
		var ir := Rect2(eq_x + float(i) * (eq_s + eq_gap), band_cy - eq_s * 0.5, eq_s, eq_s)
		if i < eq.size():
			var e: Array = eq[i]
			var e_tier := int(e[1]) if e.size() > 1 else 1
			var e_name := str(e[0])
			var e_id := str(e[2]) if e.size() > 2 else ""
			if e_id == "":
				e_id = _item_id_by_name(e_name)
			UiKit.item_icon(self, ir, e_tier, e_name)
			_equip_hits.append({"rect": ir, "id": e_id, "name": e_name, "tier": e_tier})
		else:
			draw_style_box(UiKit.flat(0.5, 5, 1, Color(0.30, 0.36, 0.46, 0.5), Color(0.06, 0.07, 0.10, 0.55), 0.0, 0.0), ir)
	# 属性徽章：剩余宽度内换行画「全部」属性（含魔抗），不再只显示前 4 条
	var chips: Array = r.get("chips", [])
	var chip_fs := int(clampf(H * 0.092, 17.0, 22.0))
	var line_h := float(int(chip_fs * 1.62))
	var cx := eq_x + 6.0 * (eq_s + eq_gap) + 18.0 * k
	var cy := band_cy - line_h * 0.5
	var wrap_x1 := x + W - 18.0
	for c in chips:
		var txt := str(c[2])
		var w_px := UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, chip_fs).x
		var need := 22.0 + w_px + 12.0
		if cx + need > wrap_x1:
			cx = eq_x + 6.0 * (eq_s + eq_gap) + 18.0 * k
			cy += line_h
			if cy + line_h * 0.5 > y + H - 6.0:
				break
		cx = _chip(cx, cy, str(c[0]), c[1], txt, chip_fs)
	# 死亡压暗
	if dead:
		draw_style_box(UiKit.flat(0.55, 12, 0, Color(0, 0, 0, 0), Color(0.02, 0.02, 0.04, 0.55), 0.0, 0.0), rect)

func _chip(x: float, baseline: float, glyph: String, col: Color, txt: String, font_size: int = 19) -> float:
	var gr := font_size * 0.42
	_glyph(Vector2(x + gr + 1.0, baseline - gr * 0.72), gr, glyph, col)
	UiKit.text(self, Vector2(x + gr * 2.0 + 5.0, baseline), txt, font_size, col.lightened(0.32))
	var w := UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return x + gr * 2.0 + w + 16.0

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

# ==================== 装备悬浮详情（三端统一：C/T 面板） ====================

func _item_id_by_name(nm: String) -> String:
	if nm == "":
		return ""
	if ItemDatabase == null:
		return ""
	var all = ItemDatabase.get("items")
	if all is Dictionary:
		for iid in (all as Dictionary).keys():
			if str(((all as Dictionary)[iid] as Dictionary).get("name", "")) == nm:
				return str(iid)
	return ""


func _equip_at(p_un: Vector2) -> Dictionary:
	for h in _equip_hits:
		if (h["rect"] as Rect2).has_point(p_un):
			return h
	return {}


func _set_equip_hover(hit: Dictionary, local_px: Vector2) -> void:
	if hit.is_empty():
		if not _tip_hit.is_empty():
			_tip_hit = {}
			queue_redraw()
		return
	_tip_anchor = local_px
	if str(hit.get("id", "")) == str(_tip_hit.get("id", "")) and (hit.get("rect", Rect2()) as Rect2) == (_tip_hit.get("rect", Rect2()) as Rect2):
		return
	_tip_hit = hit
	queue_redraw()


func _hide_item_tip() -> void:
	if not _tip_hit.is_empty():
		_tip_hit = {}
		queue_redraw()


func _draw_item_tip(_L: Dictionary) -> void:
	if _tip_hit.is_empty():
		return
	var iid := str(_tip_hit.get("id", ""))
	var it: Dictionary = ItemDatabase.get_item(iid) if iid != "" else {}
	if it.is_empty():
		return
	var tier := int(it.get("tier", int(_tip_hit.get("tier", 1))))
	var qcol: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)]
	var cls_map := {"attack": "物理", "magic": "法术", "defense": "防御", "boots": "鞋子",
		"jungle": "打野", "support": "游走", "survival": "保命", "attack_speed": "攻速"}
	var cls := str(it.get("class", ""))
	var meta := "T%d · %d 金" % [tier, int(it.get("cost", 0))]
	if cls != "":
		meta += " · " + str(cls_map.get(cls, cls))
	var parts: Array = []
	for pair in ITEM_STATS:
		var val := int(it.get(str(pair[0]), 0))
		if val != 0:
			parts.append("%s+%d" % [str(pair[1]), val])
	var lines: Array = []
	lines.append([str(it.get("name", iid)), qcol.lightened(0.25), 22])
	lines.append([meta, Color(0.62, 0.70, 0.82), 16])
	if not parts.is_empty():
		lines.append(["属性：" + " · ".join(parts), Color(0.88, 0.93, 1.0), 16])
	var passive := str(it.get("passive", ""))
	if passive != "":
		lines.append(["被动：" + passive, Color(0.98, 0.86, 0.45), 16])
	var active := str(it.get("active", ""))
	if active != "":
		lines.append(["主动：" + active, Color(0.55, 0.88, 1.0), 16])
	var reqs: Array = it.get("requires", [])
	if not reqs.is_empty():
		var names: Array = []
		for rid in reqs:
			names.append(str(ItemDatabase.get_item(str(rid)).get("name", rid)))
		lines.append(["合成：" + " + ".join(names), Color(0.62, 0.70, 0.82), 16])
	var f := UiKit.font()
	var pad := 14.0
	var lh := 26.0
	var w := 360.0
	for ln in lines:
		var fs := int(ln[2])
		var tw := f.get_string_size(str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		w = maxf(w, tw + pad * 2.0)
	var h := pad * 2.0 + lh * float(lines.size())
	var vp := get_viewport_rect().size if get_viewport() != null else Vector2(2400.0, 1400.0)
	var pos := _tip_anchor + Vector2(18.0, 10.0)
	if pos.x + w > vp.x - 12.0:
		pos.x = _tip_anchor.x - w - 18.0
	if pos.y + h > vp.y - 12.0:
		pos.y = _tip_anchor.y - h - 10.0
	pos.x = clampf(pos.x, 12.0, maxf(12.0, vp.x - w - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vp.y - h - 12.0))
	draw_style_box(UiKit.flat(0.98, 10, 1, Color(qcol.r, qcol.g, qcol.b, 0.75), Color(0.03, 0.04, 0.07, 0.97), 0.0, 8.0), Rect2(pos, Vector2(w, h)))
	draw_rect(Rect2(pos + Vector2(0.0, 2.0), Vector2(3.0, h - 4.0)), qcol)
	var y := pos.y + pad + 18.0
	for ln in lines:
		draw_string(f, Vector2(pos.x + pad, y), str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, w - pad * 2.0, int(ln[2]), ln[1])
		y += lh

func _close_rect() -> Rect2:
	return Rect2(PANEL_W - 92.0, 14.0, 40.0, 34.0)

func _fmt_gold(v: int) -> String:
	if v >= 10000:
		return "%.1f万" % (float(v) / 10000.0)
	return str(v)

func _gui_input(ev: InputEvent) -> void:
	var L0 := _layout()
	var s0: float = L0.s
	var origin0: Vector2 = L0.o
	# —— 鼠标悬浮装备：显示装备详情（三端统一） ——
	if ev is InputEventMouseMotion:
		var lp: Vector2 = (ev as InputEventMouse).position
		var p_un: Vector2 = (lp - origin0) / s0
		_set_equip_hover(_equip_at(p_un), lp)
		return
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
	# 触屏：点装备格 = 查看详情（不关闭面板）
	var eq_hit := _equip_at(p)
	if not eq_hit.is_empty():
		var lp2: Vector2 = origin + (eq_hit["rect"] as Rect2).get_center() * s
		_set_equip_hover(eq_hit, lp2)
		accept_event()
		return
	_hide_item_tip()
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
		_hide_item_tip()
		visible = false
		get_viewport().set_input_as_handled()




