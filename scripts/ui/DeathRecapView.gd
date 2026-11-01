extends Control
## 死亡面板（主机 UI_Manager 与联机客户端 NetDeathRecap 共用视图）
## 信息层级：击杀者/复活读秒 → 承伤构成（横向堆叠条）→ 伤害来源排行 → 自动归因 + 一条建议
## 点击来源行展开该来源的每一次伤害（6 条/页）；纯 _draw 绘制，数据由 build() 或 host payload 提供。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const BuffArt = preload("res://scripts/ui/BuffArt.gd")

signal closed_by_user

const CARD_W := 520.0
const CARD_H_MIN := 560.0
const MOBILE_FONT_BOOST := 1.35   # 手机端死亡回放：正文/来源/逐次伤害字体再放大
const HIT_ROWS := 6
const HIT_ROW_H := 22.0
const PAGE_BTN_W := 30.0
const PAGE_BTN_H := 24.0
const C_PHYS := Color(1.0, 0.62, 0.24)
const C_MAG := Color(0.72, 0.52, 1.0)
const C_TRUE := Color(0.95, 0.97, 1.0)
const C_DIM := Color(0.66, 0.73, 0.85)
const C_PANEL_BG := Color(0.045, 0.055, 0.085, 0.97)

var data: Dictionary = {}
var card_h := 640.0
var _close_btn: Button = null   # 真实 Button 接管 × 点击（自定义 _gui_input 在桌面模拟触摸下可能收不到 Mouse 事件）
var _tick_acc := 0.0
var _expanded := -1          # 当前展开的伤害来源行（-1=未展开）
var _hit_page := 0           # 展开列表页码（最近一次伤害在前）

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.flat = true
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_btn.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0, 0.95))
	_close_btn.pressed.connect(_close_by_user)
	add_child(_close_btn)

func set_data(d: Dictionary) -> void:
	data = d
	_expanded = -1
	_hit_page = 0
	card_h = maxf(float(_layout()["h"]), CARD_H_MIN)
	var s := _s()
	size = Vector2(CARD_W * s, card_h * s)
	_place_close_btn()
	visible = true
	set_process(true)
	UiKit.show_panel(self, 0.16)
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or data.is_empty():
		return
	var rem := float(data.get("respawn", 0.0))
	if rem <= 0.0:
		set_process(false)
		return
	_tick_acc += delta
	if _tick_acc < 0.1:
		return
	var step := _tick_acc
	_tick_acc = 0.0
	data["respawn"] = maxf(0.0, rem - step)
	if int(ceil(rem)) != int(ceil(float(data["respawn"]))):
		queue_redraw()

## 统一缩放：内部坐标一律用未缩放单位，绘制时整体缩放（字号/描边随之等比）
## 手机端面板太小看不清：整体再放大 1.5 倍，并夹到屏幕高度以内（底部不越界）
func _font(base: int) -> int:
	return int(round(float(base) * (MOBILE_FONT_BOOST if Config.on_mobile() else 1.0)))


func _s() -> float:
	var s := clampf(UiKit.scale(), 0.90, 1.35) * 1.5
	var vp := Vector2(2400.0, 1400.0)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	var need := maxf(card_h, CARD_H_MIN)
	if need > 1.0:
		s = minf(s, maxf(0.7, (vp.y - 24.0) / need))
	return s

func _hit_source() -> Dictionary:
	var sources: Array = data.get("sources", [])
	if _expanded < 0 or _expanded >= mini(sources.size(), 4):
		return {}
	return sources[_expanded] as Dictionary

func _hit_pages() -> int:
	var src := _hit_source()
	if src.is_empty():
		return 1
	return maxi(1, int(ceil(float((src.get("hits", []) as Array).size()) / float(HIT_ROWS))))

func _source_rect(i: int, L: Dictionary) -> Rect2:
	# 行高铺满整格 38（=行间距）：与下一行相接、无死区，第二行「普攻/技能」文字也点得到
	return Rect2(24.0, float(L["src_rows"]) + float(i) * 38.0 - 4.0, CARD_W - 48.0, 38.0)

func _page_rects() -> Array:
	var L := _layout()
	var y := float(L.get("hit_pager", 0.0))
	return [
		Rect2(28.0, y, PAGE_BTN_W, PAGE_BTN_H),
		Rect2(CARD_W - 28.0 - PAGE_BTN_W, y, PAGE_BTN_W, PAGE_BTN_H),
	]

## 展开/收起后保持面板顶部不动：来源行不随展开上下跳动，点击才落在瞄准的那一行
## （原来保持中心，展开后整块内容上移半个增量，光标下的行会变成别的行）
func _resize_keep_top() -> void:
	var s := _s()
	var top_left := global_position.round()
	card_h = maxf(float(_layout()["h"]), CARD_H_MIN)
	size = Vector2(CARD_W * s, card_h * s)
	_place_close_btn()
	var vp := get_viewport().get_visible_rect().size
	var max_y := maxf(8.0, vp.y - 8.0 - size.y)
	top_left.y = clampf(top_left.y, 8.0, max_y)
	global_position = top_left
	queue_redraw()

func _layout() -> Dictionary:
	var sources: Array = data.get("sources", [])
	var attrib: Array = data.get("attrib", [])
	var n: int = mini(sources.size(), 4)
	var L := {}
	var y := 132.0
	y += 16.0
	L["compose_title"] = y
	y += 24.0
	L["compose_bar"] = y
	y += 28.0
	L["compose_legend"] = y
	y += 26.0
	L["cc_title"] = y
	y += 22.0
	L["cc_line"] = y
	y += 22.0
	L["sep1"] = y
	y += 16.0
	L["src_title"] = y
	y += 24.0
	L["src_rows"] = y
	y += float(n) * 38.0 + 8.0
	if _expanded >= 0 and _expanded < n:
		y += 4.0
		L["hit_title"] = y + 14.0
		y += 20.0
		L["hit_rows"] = y
		y += float(HIT_ROWS) * HIT_ROW_H
		y += 4.0
		L["hit_pager"] = y
		y += PAGE_BTN_H + 4.0
	L["sep2"] = y
	y += 16.0
	L["att_title"] = y
	y += 24.0
	L["att_rows"] = y
	y += float(maxi(attrib.size(), 1)) * 26.0
	if str(data.get("advice", "")) != "":
		y += 6.0
		L["advice"] = y
		y += 32.0
	y += 20.0
	L["h"] = y
	return L

func _draw() -> void:
	if data.is_empty():
		return
	var s := _s()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# 卡片
	draw_style_box(UiKit.flat(0.95, 16, 1, Color(0.40, 0.50, 0.66, 0.55), C_PANEL_BG, 0.0, 18.0),
		Rect2(0.0, 0.0, CARD_W, card_h))
	# 顶部危险色细条 + 底部渐隐
	draw_rect(Rect2(18.0, 0.0, CARD_W - 36.0, 2.5), Color(0.95, 0.30, 0.26, 0.9))
	draw_rect(Rect2(18.0, card_h - 1.5, CARD_W - 36.0, 1.5), Color(0.40, 0.50, 0.66, 0.35))
	_header()
	var L := _layout()
	_divider(float(L["sep1"]))
	_divider(float(L["sep2"]))
	_label(28.0, float(L["compose_title"]), "承伤构成 · 近 7 秒", 14, C_DIM)
	_compose_bar(float(L["compose_bar"]))
	_compose_legend(float(L["compose_legend"]))
	_cc_section(float(L["cc_title"]), float(L["cc_line"]))
	_label(28.0, float(L["src_title"]), "伤害来源 · 点击展开每次伤害", 14, C_DIM)
	_sources(float(L["src_rows"]))
	if L.has("hit_title"):
		_hits(float(L["hit_title"]), float(L["hit_rows"]), float(L["hit_pager"]))
	_label(28.0, float(L["att_title"]), "本场死亡归因", 14, C_DIM)
	_attrib(float(L["att_rows"]))
	if L.has("advice"):
		_advice(float(L["advice"]))
	# 关闭按钮 + 底部提示
	var cr := _close_rect()
	draw_style_box(UiKit.flat(0.7, 8, 1, Color(0.45, 0.55, 0.72, 0.6), Color(0.10, 0.12, 0.18, 0.9), 0.0, 4.0), cr)
	UiKit.text(self, Vector2(cr.position.x, cr.position.y + cr.size.y * 0.72), "×", _font(22),
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	UiKit.text(self, Vector2(0.0, card_h - 16.0), "复活后自动关闭", _font(11), Color(0.5, 0.57, 0.68, 0.75),
		HORIZONTAL_ALIGNMENT_CENTER, CARD_W)

# ---------- 各区块 ----------

func _header() -> void:
	var killer := str(data.get("killer", ""))
	var khero := str(data.get("killer_hero", killer))
	var kteam := int(data.get("killer_team", 1))
	var tint := Color(0.0, 0.886, 1.0) if Config.is_ally(kteam) else Color(1.0, 0.36, 0.30)
	# 击杀者环形头像
	HeroArt.draw_portrait(self, Vector2(66.0, 62.0), 34.0, khero, tint, false)
	# 标题
	var title := "你被 %s 击杀" % killer if killer != "" else "你已阵亡"
	UiKit.text(self, Vector2(116.0, 60.0), title, _font(23), Color.WHITE)
	var total := float(data.get("total", 0.0))
	UiKit.text(self, Vector2(116.0, 86.0), "近 7 秒承伤 %d" % int(total), _font(14), C_DIM)
	# 复活读秒（右侧大数字 + 进度条）
	var rem := float(data.get("respawn", 0.0))
	var tot := maxf(float(data.get("respawn_total", rem)), 0.001)
	UiKit.text(self, Vector2(CARD_W - 190.0, 62.0), "%.0f" % ceil(rem), _font(38), Color(0.98, 0.84, 0.38),
		HORIZONTAL_ALIGNMENT_RIGHT, 154.0)
	UiKit.text(self, Vector2(CARD_W - 190.0, 90.0), "秒后复活", _font(13), C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 154.0)
	var br := Rect2(CARD_W - 190.0, 104.0, 154.0, 6.0)
	draw_style_box(UiKit.flat(0.9, 3, 0, Color(0, 0, 0, 0), Color(0.10, 0.12, 0.17, 0.95), 0.0, 0.0), br)
	var ratio := clampf(rem / tot, 0.0, 1.0)
	if ratio > 0.001:
		draw_style_box(UiKit.flat(0.95, 3, 0, Color(0, 0, 0, 0), Color(0.36, 0.66, 1.0), 0.0, 0.0),
			Rect2(br.position, Vector2(br.size.x * ratio, br.size.y)))

func _cc_section(y_title: float, y_line: float) -> void:
	var cc := maxf(0.0, float(data.get("cc", 0.0)))
	BuffArt.draw_buff(self, Vector2(38.0, y_title - 5.0), 8.5, "stun",
		Color(1.0, 0.62, 0.32))
	_label(52.0, y_title, "受控统计 · 近 7 秒", 14, C_DIM)
	var cc_col := Color(1.0, 0.62, 0.32) if cc > 0.05 else C_DIM
	UiKit.text(self, Vector2(CARD_W - 220.0, y_title), "受控 %.1f 秒" % cc, _font(16),
		cc_col, HORIZONTAL_ALIGNMENT_RIGHT, 192.0)
	if cc <= 0.05:
		_label(28.0, y_line, "本段未受到控制", 13, C_DIM)
		return
	var srcs: Array = data.get("cc_sources", [])
	var parts: Array = []
	for i in range(mini(srcs.size(), 2)):
		var e: Dictionary = srcs[i]
		parts.append("%s·%s %.1fs" % [str(e.get("hero", "?")), str(e.get("skill", "控制")),
			float(e.get("duration", 0.0))])
	if parts.is_empty():
		_label(28.0, y_line, "来源未记录（仅统计时长）", 13, C_DIM)
		return
	var txt := "  ·  ".join(parts)
	if srcs.size() > 2:
		txt += "  +%d" % (srcs.size() - 2)
	_label(28.0, y_line, txt, 13, Color(0.86, 0.78, 1.0))

func _compose_bar(y: float) -> void:
	var total := maxf(float(data.get("total", 0.0)), 1.0)
	var ph := float(data.get("phys", 0.0))
	var mg := float(data.get("mag", 0.0))
	var tr := float(data.get("true", 0.0))
	var r := Rect2(28.0, y, CARD_W - 56.0, 16.0)
	draw_style_box(UiKit.flat(0.9, 8, 0, Color(0, 0, 0, 0), Color(0.09, 0.11, 0.16, 0.95), 0.0, 0.0), r)
	var x := r.position.x
	for seg in [[ph, C_PHYS], [mg, C_MAG], [tr, C_TRUE]]:
		var v := float(seg[0])
		if v <= 0.01:
			continue
		var w := r.size.x * (v / total)
		var col: Color = seg[1]
		draw_style_box(UiKit.flat(0.92, 4, 0, Color(0, 0, 0, 0), col, 0.0, 0.0),
			Rect2(x, r.position.y, maxf(w, 2.0), r.size.y))
		x += w

func _compose_legend(y: float) -> void:
	var total := maxf(float(data.get("total", 0.0)), 1.0)
	var x := 28.0
	for seg in [["物理", float(data.get("phys", 0.0)), C_PHYS],
			["法术", float(data.get("mag", 0.0)), C_MAG],
			["真伤", float(data.get("true", 0.0)), C_TRUE]]:
		var v := float(seg[1])
		if v <= 0.01:
			continue
		draw_circle(Vector2(x + 4.0, y - 4.0), 4.0, seg[2])
		var txt := "%s %d (%.0f%%)" % [str(seg[0]), int(v), v / total * 100.0]
		UiKit.text(self, Vector2(x + 13.0, y), txt, _font(12), Color(0.86, 0.9, 0.96))
		x += 22.0 + UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, _font(12)).x

func _sources(y: float) -> void:
	var sources: Array = data.get("sources", [])
	var total := maxf(float(data.get("total", 0.0)), 1.0)
	if sources.is_empty():
		UiKit.text(self, Vector2(28.0, y + 20.0), "（近 7 秒未被直接攻击）", _font(14), C_DIM)
		return
	for i in range(mini(sources.size(), 4)):
		var row: Dictionary = sources[i]
		var ry := y + float(i) * 38.0
		var sel := _expanded == i
		if sel:
			draw_style_box(UiKit.flat(0.45, 8, 1, Color(0.55, 0.68, 0.92, 0.45),
				Color(0.10, 0.13, 0.20, 0.82), 0.0, 0.0), Rect2(24.0, ry - 4.0, CARD_W - 48.0, 38.0))
		HeroArt.draw_portrait(self, Vector2(46.0, ry + 16.0), 13.0,
			str(row.get("hero", row.get("name", ""))),
			Color(0.0, 0.886, 1.0) if Config.is_ally(int(row.get("team", 1))) else Color(1.0, 0.36, 0.30), false)
		UiKit.text(self, Vector2(68.0, ry + 14.0), str(row.get("name", "?")), _font(17), Color.WHITE)
		var skills := str(row.get("skills", ""))
		if skills != "":
			UiKit.text(self, Vector2(68.0, ry + 32.0), skills, _font(12), Color(0.6, 0.68, 0.8))
		var v := float(row.get("total", 0.0))
		UiKit.text(self, Vector2(CARD_W - 220.0, ry + 14.0), "%d" % int(v), _font(17), Color(0.98, 0.86, 0.55),
			HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
		UiKit.text(self, Vector2(CARD_W - 92.0, ry + 14.0), "%.0f%%" % (v / total * 100.0), _font(14), C_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT, 64.0)
		UiKit.text(self, Vector2(CARD_W - 24.0, ry + 16.0), "▲" if sel else "▼", _font(14),
			Color(0.82, 0.88, 1.0) if sel else C_DIM)

func _hits(title_y: float, rows_y: float, pager_y: float) -> void:
	var src := _hit_source()
	if src.is_empty():
		return
	var hits: Array = src.get("hits", [])
	var pages := _hit_pages()
	_hit_page = clampi(_hit_page, 0, pages - 1)
	var top := title_y - 18.0
	var bottom := pager_y + PAGE_BTN_H + 6.0
	draw_style_box(UiKit.flat(0.52, 10, 1, Color(0.42, 0.54, 0.74, 0.38),
		Color(0.065, 0.080, 0.12, 0.92), 0.0, 0.0), Rect2(24.0, top, CARD_W - 48.0, bottom - top))
	UiKit.text(self, Vector2(34.0, title_y),
		"「%s」每次伤害 · 共 %d 次（最近优先）" % [str(src.get("name", "?")), hits.size()],
		_font(13), Color(0.78, 0.84, 0.94))
	if hits.is_empty():
		UiKit.text(self, Vector2(34.0, rows_y + 16.0), "没有逐次记录", _font(13), C_DIM)
		return
	for j in range(HIT_ROWS):
		var idx := hits.size() - 1 - (_hit_page * HIT_ROWS + j)
		if idx < 0:
			break
		var h: Dictionary = hits[idx]
		var ry := rows_y + float(j) * HIT_ROW_H
		if j % 2 == 0:
			draw_rect(Rect2(30.0, ry, CARD_W - 60.0, HIT_ROW_H), Color(1.0, 1.0, 1.0, 0.025))
		var t := float(h.get("t", 0.0))
		var is_mag := bool(h.get("is_magic", false))
		var type_txt := "法术" if is_mag else "物理"
		var type_col := C_MAG if is_mag else C_PHYS
		UiKit.text(self, Vector2(34.0, ry + 15.0), "%.1fs前" % absf(t), _font(12), C_DIM)
		UiKit.text(self, Vector2(100.0, ry + 15.0), str(h.get("skill", "?")), _font(13),
			Color(0.88, 0.92, 0.98))
		UiKit.text(self, Vector2(210.0, ry + 15.0), "%d" % int(roundf(float(h.get("amount", 0.0)))),
			_font(13), Color(0.98, 0.86, 0.55), HORIZONTAL_ALIGNMENT_RIGHT, 72.0)
		UiKit.text(self, Vector2(290.0, ry + 15.0), type_txt, _font(12), type_col)
		if bool(h.get("crit", false)):
			UiKit.text(self, Vector2(344.0, ry + 15.0), "暴击", _font(12), Color(1.0, 0.42, 0.32))
	if pages > 1:
		var prs := _page_rects()
		for k in range(2):
			var r: Rect2 = prs[k]
			draw_style_box(UiKit.flat(0.75, 6, 1, Color(0.48, 0.60, 0.80, 0.5),
				Color(0.10, 0.13, 0.20, 0.95), 0.0, 3.0), r)
			UiKit.text(self, Vector2(r.position.x, r.position.y + r.size.y * 0.76),
				"<" if k == 0 else ">", _font(16), Color(0.9, 0.94, 1.0),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		UiKit.text(self, Vector2(68.0, pager_y + 16.0),
			"第 %d/%d 页 · 点击箭头翻页" % [_hit_page + 1, pages], _font(12), C_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, CARD_W - 136.0)
	else:
		UiKit.text(self, Vector2(34.0, pager_y + 16.0), "完整记录", _font(12), C_DIM)

func _attrib(y: float) -> void:
	var attrib: Array = data.get("attrib", [])
	if attrib.is_empty():
		UiKit.text(self, Vector2(28.0, y + 18.0), "无特殊归因（对拼落败）", _font(14), C_DIM)
		return
	for i in range(attrib.size()):
		var a: Dictionary = attrib[i]
		var ay := y + float(i) * 26.0
		BuffArt.draw_buff(self, Vector2(38.0, ay + 10.0), 11.0, str(a.get("key", "")),
			a.get("color", Color(1.0, 0.62, 0.3)))
		UiKit.text(self, Vector2(56.0, ay + 16.0), str(a.get("text", "")), _font(15), Color(0.88, 0.92, 0.98))

func _advice(y: float) -> void:
	var txt := str(data.get("advice", ""))
	if txt == "":
		return
	draw_style_box(UiKit.flat(0.6, 8, 1, Color(0.98, 0.82, 0.32, 0.55), Color(0.10, 0.10, 0.10, 0.55), 0.0, 0.0),
		Rect2(24.0, y - 6.0, CARD_W - 48.0, 28.0))
	UiKit.text(self, Vector2(34.0, y + 14.0), txt, _font(14), Color(0.98, 0.86, 0.45))

func _divider(y: float) -> void:
	draw_rect(Rect2(28.0, y, CARD_W - 56.0, 1.0), Color(0.40, 0.50, 0.66, 0.28))

func _label(x: float, baseline: float, txt: String, fs: int, col: Color) -> void:
	UiKit.text(self, Vector2(x, baseline), txt, _font(fs), col)

func _place_close_btn() -> void:
	if _close_btn == null:
		return
	var s := _s()
	var r := _close_rect()
	_close_btn.position = r.position * s
	_close_btn.size = r.size * s
	_close_btn.add_theme_font_size_override("font_size", int(round(20.0 * s)))


func _close_by_user() -> void:
	closed_by_user.emit()
	UiKit.hide_panel(self, 0.10)
	visible = false
	set_process(false)


func _close_rect() -> Rect2:
	return Rect2(CARD_W - 44.0, 10.0, 30.0, 26.0)

func _gui_input(ev: InputEvent) -> void:
	# TouchController 会双向模拟输入（桌面：鼠标→触摸；移动端：触摸→鼠标），
	# 同一次点击会同时收到 Mouse 与 ScreenTouch 两套事件 → 行展开被切换两次（等于没反应）。
	# 因此每端只认一套事件。
	var mobile := Config.on_mobile()
	if ev is InputEventMouseButton:
		if mobile:
			return
	elif ev is InputEventScreenTouch:
		if not mobile:
			return
	else:
		return
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not press:
		return
	var p: Vector2 = (ev as InputEventMouse).position / _s() if ev is InputEventMouse \
		else (ev as InputEventScreenTouch).position / _s()
	if _close_rect().has_point(p):
		_close_by_user()
		accept_event()
		return
	# 展开区翻页
	if _expanded >= 0 and _hit_pages() > 1:
		var prs := _page_rects()
		for k in range(2):
			if (prs[k] as Rect2).has_point(p):
				var pages := _hit_pages()
				_hit_page = ((_hit_page + (-1 if k == 0 else 1)) % pages + pages) % pages
				queue_redraw()
				accept_event()
				return
	# 点击来源行展开/收起逐次伤害
	var L := _layout()
	var sources: Array = data.get("sources", [])
	for i in range(mini(sources.size(), 4)):
		if _source_rect(i, L).has_point(p):
			_expanded = -1 if _expanded == i else i
			_hit_page = 0
			_resize_keep_top()
			accept_event()
			return

# ---------- 数据构建（主机与 NetSession 共用，保证 payload 一致） ----------

static func skill_key(skill_id: int) -> String:
	match skill_id:
		1: return "1技能"
		2: return "2技能"
		3: return "3技能"
		-2: return "灼烧"
		-10: return "红莲"
		-20: return "电刀"
		-21: return "末世"
		-22: return "圣剑"
		-23: return "巫术"
		-24: return "宗师"
		-25: return "凝冰"
		-26: return "寒霜"
		-27: return "回响"
		-28: return "面具"
		-29: return "冰痕"
		-30: return "日渊"
		-31: return "血魔"
		-32: return "怒龙"
		-33: return "极寒"
		-36: return "逐日"
		-37: return "破晓"
		-51: return "冰霜冲击"
		-52: return "强化普攻"
		_:
			return ("装备" if skill_id < -9 else "普攻")

## 从 Hero.damage_log（近 7 秒）聚合出面板数据；battle 可空（客户端/无战场时跳过越塔归因）
static func build(hero, battle = null) -> Dictionary:
	if hero == null:
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	var by_src: Dictionary = {}
	var order: Array = []
	var total := 0.0
	var phys := 0.0
	var mag := 0.0
	var tru := 0.0
	var last_src := ""
	var last_t := -999.0
	for log in hero.damage_log:
		var t := float(log.get("time", 0.0))
		if now - t > 7.0:
			continue
		var src := str(log.get("source", "?"))
		var amt := float(log.get("amount", 0.0))
		var is_mag := bool(log.get("is_magic", false))
		var key := skill_key(int(log.get("skill_id", 0)))
		if not by_src.has(src):
			by_src[src] = {"total": 0.0, "phys": 0.0, "mag": 0.0, "skills": {}, "hits": []}
			order.append(src)
		var e: Dictionary = by_src[src]
		(e["hits"] as Array).append({
			"t": snappedf(t - now, 0.1), "amount": roundf(amt),
			"is_magic": is_mag, "crit": bool(log.get("crit", false)), "skill": key,
		})
		e["total"] = float(e["total"]) + amt
		if is_mag:
			e["mag"] = float(e["mag"]) + amt
			mag += amt
		else:
			e["phys"] = float(e["phys"]) + amt
			phys += amt
		var sk: Dictionary = e["skills"]
		sk[key] = float(sk.get(key, 0.0)) + amt
		total += amt
		if t >= last_t:
			last_t = t
			last_src = src
	# 英雄名录：名字 → (team, hero_name)
	var roster: Dictionary = {}
	if hero != null and hero.is_inside_tree():
		for n in hero.get_tree().get_nodes_in_group("heroes"):
			if n is GameEntity:
				roster[str((n as GameEntity).display_name)] = n
	var sources: Array = []
	for src in order:
		var e: Dictionary = by_src[src]
		var node = roster.get(src)
		var team := 1
		var hname: String = str(src)
		if node != null and node is GameEntity:
			team = int((node as GameEntity).team)
			hname = str((node as GameEntity).display_name)
		# 该来源的 Top2 技能
		var paired: Array = []
		for k in (e["skills"] as Dictionary).keys():
			paired.append([str(k), float(e["skills"][k])])
		paired.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
		var parts: Array = []
		for i in range(mini(paired.size(), 2)):
			parts.append("%s %d" % [str(paired[i][0]), int(roundf(float(paired[i][1])))])
		sources.append({
			"name": src, "hero": hname, "team": team,
			"total": roundf(float(e["total"])),
			"phys": roundf(float(e["phys"])), "mag": roundf(float(e["mag"])),
			"skills": " · ".join(parts), "hits": e["hits"],
		})
	sources.sort_custom(func(a, b): return float(a["total"]) > float(b["total"]))
	var killer := last_src
	var killer_hero := str(sources[0]["hero"]) if sources.size() > 0 else killer
	var killer_team := int(sources[0]["team"]) if sources.size() > 0 else 1
	# —— 自动归因 ——
	var cc := 0.0
	if hero != null and hero.has_method("get_cc_duration"):
		cc = float(hero.get_cc_duration(7.0))
	# 受控源：按「英雄·技能」聚合时长，供面板直接展示“被谁的什么技能控了多久”
	var cc_sources: Array = []
	if hero != null and hero.has_method("get_cc_breakdown"):
		for e in hero.get_cc_breakdown(7.0):
			var sid := int(e.get("skill", -999))
			var hname := str(e.get("hero", ""))
			if hname == "":
				hname = "未知来源"
			var sk_name := "控制" if sid <= -900 else skill_key(sid)
			cc_sources.append({
				"hero": hname, "skill": sk_name,
				"duration": snappedf(float(e.get("duration", 0.0)), 0.1),
			})
	cc_sources.sort_custom(func(a, b): return float(a["duration"]) > float(b["duration"]))
	var attrib: Array = []
	if cc >= 2.0:
		attrib.append({"key": "stun", "color": Color(1.0, 0.36, 0.30),
			"text": "被控制 %.1f 秒后阵亡" % cc})
	# 参与击杀人数只统计英雄：小兵/野怪/防御塔的伤害源不计入“几人击杀”
	var hero_src_n := 0
	for s in sources:
		var snode = roster.get(str(s["name"]))
		if snode is Hero:
			hero_src_n += 1
	if hero_src_n >= 2:
		attrib.append({"key": "suppress", "color": Color(0.72, 0.55, 1.0),
			"text": "%d 名英雄参与击杀" % hero_src_n})
	var under_tower := false
	if battle != null and battle.has_method("hero_under_enemy_tower") and hero != null:
		under_tower = bool(battle.hero_under_enemy_tower(hero))
	if under_tower:
		attrib.append({"key": "tower_dive", "color": Color(0.98, 0.62, 0.35),
			"text": "在敌方防御塔射程内阵亡"})
	# 秒杀判定：死亡前 1 秒内承伤 ≥ 最大生命 60%
	var burst := 0.0
	var is_burst := false
	if hero != null and hero.is_inside_tree():
		for log in hero.damage_log:
			if now - float(log.get("time", 0.0)) <= 1.0:
				burst += float(log.get("amount", 0.0))
		if burst >= float(hero.actual_max_health) * 0.6:
			is_burst = true
			attrib.append({"key": "junlin", "color": Color(1.0, 0.85, 0.4),
				"text": "1 秒内被瞬秒（%d 伤害）" % int(burst)})
	if attrib.is_empty():
		attrib.append({"key": "sword", "color": Color(0.9, 0.6, 0.35),
			"text": "对拼落败：承伤高于输出"})
	var advice := "建议：注意站位与血量，别在无视野处开团"
	if cc >= 2.0:
		advice = "建议：抵抗之靴 / 净化类技能留给关键控制"
	elif under_tower:
		advice = "建议：先让兵线进塔、确认敌方打野位置再越塔"
	elif sources.size() >= 3:
		advice = "建议：少单独深入，开团与队友保持 10m 内"
	elif is_burst:
		advice = "建议：先手控住爆发英雄，或提前出保命装"
	return {
		"killer": killer, "killer_hero": killer_hero, "killer_team": killer_team,
		"respawn": float(hero.respawn_timer) if hero != null else 0.0,
		"respawn_total": float(hero.respawn_time_total) if hero != null else 0.0,
		"cc": cc, "cc_sources": cc_sources,
		"total": roundf(total), "phys": roundf(phys), "mag": roundf(mag),
		"true": roundf(tru), "sources": sources, "attrib": attrib, "advice": advice,
	}
