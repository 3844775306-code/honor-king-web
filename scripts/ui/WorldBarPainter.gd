extends Control
## 世界血条合批绘制：由 HUD 每帧填 rows（屏幕坐标/数值已算好），本节点一次性画完。
## 质感：渐变填充 + 顶部高光 + 底部暗边 + 中缝 + 1px 边框/队伍色外框 + 投影 + 残血拖尾 + 低血脉冲；
## 文字：合成粗体 + 阴影 + 描边；名称在上、数值在下，居中。

var rows: Array = []          # 本帧可见行（HUD 直接复用 row 字典，不新建）
var _had_rows: bool = false   # 上一帧是否画过血条（用于“清空后补一次重绘”）
var _font: Font = null
var _font_bold: FontVariation = null
var _t := 0.0

# —— 缓存纹理/材质（首次用到才建）——

const MarkerIconScript = preload("res://scripts/ui/MarkerIcon.gd")
const OUTLINE := Color(0, 0, 0, 0.92)
const SHADOW := Color(0, 0, 0, 0.55)
const BAR_BG_TOP := Color(0.11, 0.12, 0.16, 0.96)
const BAR_BG_BOT := Color(0.06, 0.07, 0.10, 0.96)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = UiKit.font()
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	# 有血条要画；或上一帧还有血条、这一帧没了 → 必须再重绘一次把旧血条擦掉。
	# 否则最后一个可见单位死亡/离开视野后，它的血条会一直留在屏幕上，
	# 直到下一次有血条出现触发重绘（表现就是“单位死了血条残留一会”）。
	if not rows.is_empty():
		_had_rows = true
		queue_redraw()
	elif _had_rows:
		_had_rows = false
		queue_redraw()

func _draw() -> void:
	for r in rows:
		if bool(r.get("epic", false)):
			_draw_epic(r)
		else:
			_draw_unit(r)

# ============================ 资源缓存 ============================
func _bold() -> Font:
	if _font_bold == null:
		var fv := FontVariation.new()
		fv.base_font = _font
		fv.variation_embolden = 0.45
		_font_bold = fv
	return _font_bold if _font_bold != null else _font

# ============================ 普通单位 ============================
func _draw_unit(r: Dictionary) -> void:
	var w: float = float(r["w"])
	var h: float = float(r["h"])
	if w <= 0.0 or h <= 0.0:
		return
	var p: Vector2 = r["pos"]
	var hp: float = float(r["hp"])
	var mx: float = maxf(1.0, float(r["max_hp"]))
	var shield: float = float(r.get("shield", 0.0))
	var tc: Color = r["team_color"]
	var team: int = int(r.get("team", 0))
	# 补刀提示：正在攻击且一次普攻即可击杀 → 整条血条改为灰白（带呼吸亮边）
	var last_hit: bool = bool(r.get("last_hit", false))
	var lh_pulse: float = 0.0
	if last_hit:
		lh_pulse = 0.5 + 0.5 * sin(_t * 7.0)
		tc = Color(0.90, 0.92, 0.95).lerp(Color(1.0, 1.0, 1.0), lh_pulse * 0.35)
	var top := Rect2(p, Vector2(w, h))
	var hw: float = clampf(hp / mx, 0.0, 1.0) * w

	# 投影（两层，软化）
	draw_rect(Rect2(p + Vector2(1.5, 2.5), Vector2(w, h)), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(p + Vector2(2.5, 3.5), Vector2(w, h)), Color(0, 0, 0, 0.10))

	# 外框：深色底 + 队伍色细边
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0.02, 0.03, 0.05, 0.94))
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(tc.r, tc.g, tc.b, 0.34), false, 1.0)
	if last_hit:
		# 补刀提示外光：白色呼吸描边 + 顶部一道亮线
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)),
			Color(1.0, 1.0, 1.0, 0.35 + 0.45 * lh_pulse), false, 1.5)
		draw_rect(Rect2(p + Vector2(0, -3.5), Vector2(w, 2)), Color(1, 1, 1, 0.25 + 0.35 * lh_pulse))

	# 空槽（上亮下暗）
	draw_rect(Rect2(p, Vector2(w, h * 0.5)), BAR_BG_TOP)
	draw_rect(Rect2(p + Vector2(0, h * 0.5), Vector2(w, h * 0.5)), BAR_BG_BOT)

	# 干扰条（塔被干扰时，血条上方灰条，带金属感）
	var iv: float = float(r.get("interfere", 0.0))
	if iv > 0.0:
		var ir := Rect2(p + Vector2(0, -7), Vector2(w, 5))
		draw_rect(ir, Color(0, 0, 0, 0.45))
		draw_rect(Rect2(ir.position, Vector2(w * clampf(iv, 0.0, 1.0), 5)), Color(0.66, 0.68, 0.74))
		draw_rect(Rect2(ir.position, Vector2(w * clampf(iv, 0.0, 1.0), 2)), Color(1, 1, 1, 0.35))
		draw_rect(ir, Color(0.02, 0.03, 0.05, 0.9), false, 1.0)

	# 残血拖尾（渐变白，尾部一道亮边）
	var lag: float = clampf(float(r.get("lag", hp)) / mx, 0.0, 1.0) * w
	if lag > hw + 0.5:
		var lw: float = lag - hw
		var lb: int = 4
		for li in lb:
			var lq: float = float(li) / float(lb - 1)
			draw_rect(Rect2(p + Vector2(hw, h * float(li) / float(lb)),
				Vector2(lw, h / float(lb) + 1.0)), Color(1.0, 0.94, 0.86, 0.52 - 0.32 * lq))
		draw_rect(Rect2(p + Vector2(lag - 1.5, 0), Vector2(1.5, h)), Color(1.0, 0.94, 0.82, 0.9))

	# 血量填充（分段渐变 + 顶部高光 + 底部暗边 + 中缝）
	if hw > 0.0:
		var bands: int = 5
		var c_top: Color = tc.lightened(0.42)
		var c_bot: Color = tc.darkened(0.38)
		for bi in bands:
			var q: float = float(bi) / float(bands - 1)
			var col: Color = c_top.lerp(c_bot, q)
			draw_rect(Rect2(p + Vector2(0, h * float(bi) / float(bands)),
				Vector2(hw, h / float(bands) + 1.0)), col)
		draw_rect(Rect2(p, Vector2(hw, maxf(1.5, h * 0.14))), Color(1, 1, 1, 0.45))
		draw_rect(Rect2(p + Vector2(0, maxf(1.5, h * 0.14)), Vector2(hw, maxf(1.0, h * 0.08))), Color(1, 1, 1, 0.10))
		draw_rect(Rect2(p + Vector2(0, h - 1.5), Vector2(hw, 1.5)), Color(0, 0, 0, 0.30))
		if h >= 10.0:
			draw_line(Vector2(p.x, p.y + h * 0.5), Vector2(p.x + hw, p.y + h * 0.5),
				Color(0, 0, 0, 0.22), 1.0)

	# 护盾（右侧淡蓝段 + 斜纹 + 左隔线）
	var sw: float = minf(clampf(shield / mx, 0.0, 1.0) * w, w - hw)
	if sw > 0.5:
		var sr := Rect2(p + Vector2(hw, 0), Vector2(sw, h))
		draw_rect(sr, Color(0.72, 0.82, 0.95, 0.92))
		draw_rect(Rect2(sr.position, Vector2(sw, maxf(1.5, h * 0.14))), Color(1, 1, 1, 0.55))
		var x := 2.0
		while x < sw:
			draw_line(sr.position + Vector2(x, h), sr.position + Vector2(x + h * 0.55, 0),
				Color(1, 1, 1, 0.28), 1.0)
			x += 4.0
		draw_rect(Rect2(sr.position, Vector2(1.0, h)), Color(1, 1, 1, 0.75))

	# 刻度：塔默认每 2000 血一格；野怪 / 主宰先锋等由 HUD 指定每 1000 血一格
	if bool(r.get("ticks", false)):
		var tick_hp: float = maxf(100.0, float(r.get("tick_step", 2000.0)))
		var step := tick_hp / mx * w
		if step > 5.0:
			var tx := step
			while tx < w - 1.0:
				draw_line(Vector2(p.x + tx, p.y), Vector2(p.x + tx, p.y + h), Color(0, 0, 0, 0.55), 1.5)
				draw_line(Vector2(p.x + tx + 1.5, p.y), Vector2(p.x + tx + 1.5, p.y + h),
					Color(1, 1, 1, 0.14), 1.0)
				tx += step

	# 塔盾下一触发点：白色短线（仅前4分钟由 HUD 下发 shield_next）
	var _shield_next: float = float(r.get("shield_next", -1.0))
	if _shield_next > 0.0:
		var _sx: float = p.x + w * clampf(_shield_next, 0.0, 1.0)
		draw_line(Vector2(_sx, p.y - 2.0), Vector2(_sx, p.y + h + 2.0), Color(0.02, 0.03, 0.05, 0.70), 3.0)
		draw_line(Vector2(_sx, p.y - 2.0), Vector2(_sx, p.y + h + 2.0), Color(1.0, 1.0, 1.0, 0.95), 1.5)

	# 受伤闪橙（渐变段 + 亮边）
	var ft: float = float(r.get("flash_t", 0.0))
	if ft > 0.0:
		var fw: float = minf(float(r.get("flash_amt", 0.0)) / mx * w * (ft / 0.5), w - hw)
		if fw > 0.5:
			var fr := Rect2(p + Vector2(hw, 0), Vector2(fw, h))
			draw_rect(fr, Color(1.0, 0.58, 0.10, 0.85))
			draw_rect(Rect2(fr.position, Vector2(fw, maxf(1.5, h * 0.14))), Color(1.0, 0.85, 0.55, 0.9))
			draw_rect(Rect2(fr.position + Vector2(fw - 1.0, 0), Vector2(1.0, h)), Color(1.0, 0.9, 0.6, 0.9))

	# 回血暗段
	var ht: float = float(r.get("heal_t", 0.0))
	if ht > 0.0:
		var hwd: float = float(r.get("heal_amt", 0.0)) / mx * w
		if hwd > 0.5:
			var rc := Rect2(p + Vector2(maxf(hw - hwd, 0.0), 0), Vector2(hwd, h))
			draw_rect(rc, Color(tc.r * 0.55, tc.g * 0.55, tc.b * 0.55, ht / 0.5 * 0.85))
			draw_rect(Rect2(rc.position, Vector2(hwd, maxf(1.0, h * 0.12))), Color(1, 1, 1, ht / 0.5 * 0.22))

	# 李元芳暗印预判（黄段 + 顶部亮边）
	var doom: float = float(r.get("doom", 0.0))
	if doom > 0.0:
		var dw: float = minf(doom / mx * w, hw)
		if dw > 0.5:
			var dr := Rect2(p + Vector2(hw - dw, 0), Vector2(dw, h))
			draw_rect(dr, Color(1.0, 0.84, 0.16, 0.85))
			draw_rect(Rect2(dr.position, Vector2(dw, maxf(1.5, h * 0.16))), Color(1.0, 0.95, 0.55, 0.75))

	# 低血脉冲（<30%：红色呼吸外发光 + 内描边）
	var ratio := hp / mx
	if ratio < 0.3 and hp > 0.0:
		var pulse: float = 0.30 + 0.35 * absf(sin(_t * 5.2))
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(w + 4, h + 4)),
			Color(1.0, 0.20, 0.14, pulse * 0.55), false, 2.0)
		draw_rect(top, Color(1.0, 0.30, 0.22, pulse * 0.22))

	# 顶沿高光（整条，像玻璃）
	draw_line(Vector2(p.x, p.y), Vector2(p.x + w, p.y), Color(1, 1, 1, 0.13), 1.0)

	# 盾形图标（原初羁绊 / 塔无兵线保护）
	if bool(r.get("shield_icon", false)):
		var s: float = minf(h * 0.74, 20.0)
		_draw_shield_icon(p + Vector2(-(s + 10.0), h * 0.5), s, tc)

	# ---------------- 文字：名称（上，粗体+阴影+描边）+ 数值（下，居中） ----------------
	var fs_name := 20
	var fs_num := 15
	if bool(r.get("show_name", false)):
		var nm: String = str(r.get("name_text", ""))
		if nm != "":
			var np := p + Vector2(0, -10.0)
			_text_center(nm, np, w, fs_name, Color(0.96, 0.97, 1.0))
	if bool(r.get("show_numbers", false)):
		var num: String = str(r.get("num_text", ""))
		if num != "" and h >= 10.0:
			var yy := p + Vector2(0, h + fs_num + 4.0)
			_text_center(num, yy, w, fs_num, Color(1, 1, 1, 0.97))
	# 防御塔：血条下方一个指向塔身的小三角箭头（替代原名称 label）
	if bool(r.get("turret_arrow", false)):
		var tc_ar: Color = r.get("team_color", Color(1, 1, 1))
		var ax: float = p.x + w * 0.5
		var ay: float = p.y + h + 2.0
		var aw: float = maxf(6.0, h * 0.5)
		var ah: float = aw * 1.2
		var tri := PackedVector2Array([
			Vector2(ax - aw, ay), Vector2(ax + aw, ay), Vector2(ax, ay + ah),
		])
		draw_colored_polygon(tri, Color(tc_ar.r, tc_ar.g, tc_ar.b, 0.95))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]),
			Color(0, 0, 0, 0.65), 1.2)
	# 标记图标（血条上方一行）：加大尺寸；有名称文字时整行再上移，避免压住名称
	var mlist: Array = r.get("marker_list", [])
	if not mlist.is_empty():
		var mr := 16.0
		var my := p.y - mr * 2.0 - 6.0
		if bool(r.get("show_name", false)):
			my -= 26.0
		MarkerIconScript.draw_row(self, p.x + w * 0.5, my, mlist, mr)

# 居中绘制一行文字：阴影 + 描边 + 主体
func _text_center(txt: String, pos: Vector2, width: float, fs: int, col: Color) -> void:
	var f := _bold()
	draw_string(f, pos + Vector2(1.2, 1.5), txt, HORIZONTAL_ALIGNMENT_CENTER, width, fs, SHADOW)
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 4, OUTLINE)
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)

# 左对齐绘制（英雄名用途由 HeroInfoControl 处理，这里仅备用）
func _text_left(txt: String, pos: Vector2, fs: int, col: Color) -> void:
	var f := _bold()
	draw_string(f, pos + Vector2(1.2, 1.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, SHADOW)
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, OUTLINE)
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# ============================ 史诗怪（紫色分格） ============================
func _draw_epic(r: Dictionary) -> void:
	var w: float = float(r["w"])
	var h: float = float(r["h"])
	var p: Vector2 = r["pos"]
	var hp: float = float(r["hp"])
	var mx: float = maxf(1.0, float(r["max_hp"]))
	var shield: float = float(r.get("shield", 0.0))
	var cell := 1000.0
	var seg_count := maxi(1, int(ceil(mx / cell)))
	var seg_total := float(seg_count) * cell
	var seg_w := w / float(seg_count)
	var to_w := w / seg_total
	var fill_w: float = clampf(hp, 0.0, mx) * to_w
	var sh_w: float = clampf(shield, 0.0, seg_total - hp) * to_w

	var margin := 1.5
	var inset_y := 2.5
	var avail_h: float = h - inset_y * 2.0
	var cell_top := Color(0.16, 0.07, 0.28, 0.96)
	var cell_bot := Color(0.10, 0.04, 0.18, 0.96)
	var top_col := Color(0.86, 0.52, 1.0)
	var bot_col := Color(0.44, 0.14, 0.80)

	# 投影 + 外框发光
	draw_rect(Rect2(p + Vector2(2, 3), Vector2(w, h)), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)), Color(0.06, 0.02, 0.10, 0.95), false, 2.0)

	for i in seg_count:
		var x0: float = float(i) * seg_w
		var x1: float = minf(float(i + 1) * seg_w, w)
		if x1 - x0 <= margin * 2.0:
			continue
		var rc := Rect2(p + Vector2(x0 + margin, inset_y), Vector2(x1 - x0 - margin * 2.0, avail_h))
		draw_rect(rc, cell_top)
		draw_rect(Rect2(rc.position + Vector2(0, rc.size.y * 0.55), Vector2(rc.size.x, rc.size.y * 0.45)), cell_bot)
		var filled: float = clampf(fill_w - rc.position.x + p.x, 0.0, rc.size.x)
		if filled > 0.0:
			draw_rect(Rect2(rc.position, Vector2(filled, avail_h * 0.5)), top_col)
			draw_rect(Rect2(rc.position + Vector2(0, avail_h * 0.5), Vector2(filled, avail_h * 0.5)), bot_col)
			draw_rect(Rect2(rc.position, Vector2(filled, 2.0)), Color(1, 1, 1, 0.35))
		# 每格高光竖边
		draw_line(rc.position + Vector2(0.5, 0), rc.position + Vector2(0.5, rc.size.y), Color(0, 0, 0, 0.45), 1.0)

	# 残血拖尾
	var lag: float = clampf(float(r.get("lag", hp)), 0.0, mx) * to_w
	if lag > fill_w + 0.5:
		draw_rect(Rect2(p + Vector2(fill_w, inset_y), Vector2(lag - fill_w, avail_h)), Color(1.0, 0.94, 0.86, 0.38))
		draw_rect(Rect2(p + Vector2(lag - 1.5, inset_y), Vector2(1.5, avail_h)), Color(1, 0.92, 1.0, 0.8))

	if sh_w > 0.0:
		var sh_x: float = clampf(fill_w, 0.0, w)
		var sh_use: float = clampf(sh_w, 0.0, w - sh_x)
		if sh_use > 0.0:
			draw_rect(Rect2(p + Vector2(sh_x, inset_y), Vector2(sh_use, avail_h)), Color(0.88, 0.90, 0.98, 0.94))
			draw_rect(Rect2(p + Vector2(sh_x, inset_y), Vector2(sh_use, 2.0)), Color(1, 1, 1, 0.6))

	var ft: float = float(r.get("flash_t", 0.0))
	if ft > 0.0:
		var fw: float = float(r.get("flash_amt", 0.0)) * to_w * (ft / 0.5)
		if fw > 0.5:
			draw_rect(Rect2(p + Vector2(fill_w, inset_y), Vector2(minf(fw, w - fill_w), avail_h)),
				Color(1.0, 0.52, 0.10, 0.85))

	var ht: float = float(r.get("heal_t", 0.0))
	if ht > 0.0:
		var hw2: float = float(r.get("heal_amt", 0.0)) * to_w
		if hw2 > 0.5:
			draw_rect(Rect2(p + Vector2(maxf(fill_w - hw2, 0.0), inset_y), Vector2(hw2, avail_h)),
				Color(top_col.r * 0.5, top_col.g * 0.5, top_col.b * 0.5, ht / 0.5 * 0.55))

	var doom: float = float(r.get("doom", 0.0))
	if doom > 0.0:
		var dw: float = doom * to_w
		if dw > 0.5:
			draw_rect(Rect2(p + Vector2(maxf(fill_w - dw, 0.0), inset_y), Vector2(dw, avail_h)),
				Color(1.0, 0.86, 0.18, 0.72))

	# 亮紫外框 + 顶部高光
	draw_rect(Rect2(p, Vector2(w, h)), Color(1.0, 0.90, 1.0, 0.55), false, 1.5)
	draw_line(Vector2(p.x, p.y), Vector2(p.x + w, p.y), Color(1, 1, 1, 0.16), 1.0)

	if bool(r.get("show_name", false)):
		var nm: String = str(r.get("name_text", ""))
		if nm != "":
			_text_center(nm, p + Vector2(0, -12.0), w, 24, Color(0.95, 0.84, 1.0))
	if bool(r.get("show_numbers", false)):
		var num: String = str(r.get("num_text", ""))
		if num != "":
			_text_center(num, p + Vector2(0, h + 26.0), w, 17, Color(1, 1, 1, 0.96))
	var emlist: Array = r.get("marker_list", [])
	if not emlist.is_empty():
		var emr := 16.0
		MarkerIconScript.draw_row(self, p.x + w * 0.5, p.y - emr * 2.0 - 36.0, emlist, emr)

# ============================ 盾形图标 ============================
func _draw_shield_icon(c: Vector2, s: float, col: Color) -> void:
	draw_shield_icon(self, c, s, col)


## 通用美化盾图标（塔/单位血条）：圆角盾形 + 双层描边 + 顶部高光 + 中心菱形盾徽 + 外发光
static func draw_shield_icon(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-0.50 * s, -0.78 * s), c + Vector2(-0.24 * s, -0.92 * s),
		c + Vector2(0.24 * s, -0.92 * s), c + Vector2(0.50 * s, -0.78 * s),
		c + Vector2(0.58 * s, -0.26 * s), c + Vector2(0.38 * s, 0.38 * s),
		c + Vector2(0.0 * s, 0.95 * s), c + Vector2(-0.38 * s, 0.38 * s),
		c + Vector2(-0.58 * s, -0.26 * s),
	])
	var glow := PackedVector2Array()
	for q in pts:
		glow.append(c + (q - c) * 1.16)
	ci.draw_colored_polygon(glow, Color(col.r, col.g, col.b, 0.18))
	ci.draw_colored_polygon(pts, Color(0.04, 0.06, 0.09, 0.94))
	var border := PackedVector2Array()
	for q in pts:
		border.append(c + (q - c) * 0.90)
	ci.draw_colored_polygon(border, Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 1.0))
	var face := PackedVector2Array()
	for q in pts:
		face.append(c + (q - c) * 0.74)
	ci.draw_colored_polygon(face, col)
	# 顶部高光
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-0.34 * s, -0.70 * s), c + Vector2(0.34 * s, -0.70 * s),
		c + Vector2(0.22 * s, -0.28 * s), c + Vector2(-0.22 * s, -0.28 * s),
	]), Color(1, 1, 1, 0.22))
	# 中心菱形盾徽
	var emblem := PackedVector2Array([
		c + Vector2(0.0, -0.44 * s), c + Vector2(0.21 * s, -0.03 * s),
		c + Vector2(0.0, 0.34 * s), c + Vector2(-0.21 * s, -0.03 * s),
	])
	ci.draw_colored_polygon(emblem, Color(1, 1, 1, 0.88))
	var em_out := emblem.duplicate()
	em_out.append(emblem[0])
	ci.draw_polyline(em_out, Color(0.10, 0.18, 0.22, 0.55), maxf(1.0, s * 0.05))
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(0.02, 0.03, 0.05, 0.85), maxf(1.2, s * 0.09))
	ci.draw_polyline(border, Color(1, 1, 1, 0.22), maxf(1.0, s * 0.05))
