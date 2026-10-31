extends Node
## 标记图标：每种标记一个专属矢量形状（不再是“圆圈+字”），血条上方一行显示，右上角数字=层数。
## 形状分两层：底板形状（六边/菱形/八边…）+ 内部符号（雪花/准星/爆星/刀刃/印/火焰/长戟/音叉…）。
## 运行时用 preload 引用；entries 元素：{"name": 来源英雄名, "count": 层数, "type": 变体类型(可空)}

const R := 15.0
const GAP := 7.0

# name/type -> {c: 专属色, plate: 底板形状, sym: 内部符号}
const SPEC := {
	"甄姬": {"c": Color(0.55, 0.85, 1.0), "plate": "hex", "sym": "snow"},
	"王昭君": {"c": Color(0.45, 0.78, 1.0), "plate": "hex", "sym": "crystal"},
	"安琪拉": {"c": Color(1.0, 0.52, 0.22), "plate": "tri", "sym": "flame"},
	"马可波罗": {"c": Color(1.0, 0.74, 0.26), "plate": "oct", "sym": "crosshair"},
	"李元芳": {"c": Color(1.0, 0.88, 0.30), "plate": "diamond", "sym": "seal"},
	"孙尚香": {"c": Color(1.0, 0.42, 0.36), "plate": "oct", "sym": "blast"},
	"兰陵王": {"c": Color(0.72, 0.50, 1.0), "plate": "diamond", "sym": "blade"},
	"吕布": {"c": Color(1.0, 0.28, 0.28), "plate": "tri", "sym": "spear"},
	"太乙真人": {"c": Color(0.38, 0.95, 0.68), "plate": "hex", "sym": "orb"},
	"东皇太一": {"c": Color(0.76, 0.44, 1.0), "plate": "diamond", "sym": "tri_down"},
	"张飞": {"c": Color(1.0, 0.50, 0.20), "plate": "tri", "sym": "horns"},
	"杨玉环": {"c": Color(1.0, 0.60, 0.85), "plate": "oct", "sym": "note"},
}

static func spec(name: String, type: String) -> Dictionary:
	if type == "lyf":
		return {"c": Color(1.0, 0.88, 0.30), "plate": "diamond", "sym": "seal"}
	if type == "makeboluo_dd":
		return {"c": Color(1.0, 0.74, 0.26), "plate": "oct", "sym": "crosshair"}
	if type == "sunshangxiang_w":
		return {"c": Color(1.0, 0.42, 0.36), "plate": "oct", "sym": "blast"}
	if type == "lanling_mark_dmg":
		return {"c": Color(0.72, 0.50, 1.0), "plate": "diamond", "sym": "blade"}
	if SPEC.has(name):
		return SPEC[name]
	# 未知来源：按名字散列取色，底板/符号也按散列分派 → 每个英雄都有稳定且互不相同的形状
	var h: int = int(abs(hash(name)))
	var shapes := ["hex", "oct", "diamond", "tri"]
	var syms := ["blade", "crystal", "orb", "tri_down", "hex"]
	return {"c": Color.from_hsv(float(h % 360) / 360.0, 0.66, 0.96),
		"plate": shapes[h % shapes.size()], "sym": syms[(h / 7) % syms.size()]}

# 画一行图标（在调用者的 _draw 内调用）；返回下一行的 y
static func draw_row(ci: CanvasItem, cx: float, y: float, entries: Array, r: float = R) -> float:
	var n: int = entries.size()
	if n == 0:
		return y
	var step: float = r * 2.0 + GAP
	var x0: float = cx - (float(n) * step - GAP) * 0.5 + r
	for i in range(n):
		var e: Dictionary = entries[i]
		var sp: Dictionary = spec(str(e.get("name", "")), str(e.get("type", "")))
		_draw_badge(ci, Vector2(x0 + float(i) * step, y + r), r, sp["c"],
			str(sp["plate"]), str(sp["sym"]), int(e.get("count", 1)))
	return y + r * 2.0 + 4.0

static func _sides(plate: String) -> int:
	match plate:
		"hex": return 6
		"oct": return 8
		"diamond": return 4
		"tri": return 3
	return 6

static func _poly(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a: float = rot + TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

static func _close(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out

static func _draw_badge(ci: CanvasItem, c: Vector2, r: float, col: Color, plate: String, sym: String, stacks: int) -> void:
	# 底板：旋转让菱形/三角都立起来（顶点朝上）
	var rot: float = -PI * 0.5
	if plate == "diamond":
		rot = -PI * 0.5
	elif plate == "tri":
		rot = -PI * 0.5
	elif plate == "hex" or plate == "oct":
		rot = -PI * 0.5 + PI / float(_sides(plate))
	var pts := _poly(c, r, _sides(plate), rot)
	# 投影 + 黑边 + 专属色底 + 内侧提亮 + 亮边
	ci.draw_colored_polygon(_poly(c + Vector2(0, 2.0), r + 2.0, _sides(plate), rot), Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(_poly(c, r + 2.0, _sides(plate), rot), Color(0.03, 0.04, 0.07, 0.97))
	ci.draw_colored_polygon(pts, col.darkened(0.55))
	ci.draw_colored_polygon(_poly(c - Vector2(0, r * 0.16), r * 0.74, _sides(plate), rot), col.darkened(0.22))
	ci.draw_polyline(_close(pts), col.lightened(0.12), 1.6, true)
	# 内部专属符号
	_draw_symbol(ci, c, r * 0.60, col.lightened(0.55), sym)
	# 层数刻度：图标底部最多 5 格，叠层数量一眼可读（数字气泡仍保留精确值）
	if stacks > 0 and r >= 12.0:
		var pips: int = mini(stacks, 5)
		var pw: float = maxf(2.0, r * 0.16)
		var pg: float = maxf(1.2, r * 0.08)
		var total_w: float = float(pips) * pw + float(pips - 1) * pg
		var sx: float = c.x - total_w * 0.5
		var py: float = c.y + r * 0.72
		ci.draw_rect(Rect2(sx - 2.0, py - 1.2, total_w + 4.0, maxf(2.2, r * 0.16)), Color(0, 0, 0, 0.55))
		for i in range(pips):
			ci.draw_rect(Rect2(sx + float(i) * (pw + pg), py, pw, maxf(2.0, r * 0.12)),
				col.lightened(0.40))
	# 右上角层数气泡：加大字号 + 深色描边，远距离也能辨认
	var b := c + Vector2(r * 0.70, -r * 0.70)
	var br: float = maxf(7.2, r * 0.50)
	ci.draw_circle(b + Vector2(0, 1.2), br + 1.1, Color(0, 0, 0, 0.55))
	ci.draw_circle(b, br, Color(0.035, 0.045, 0.075, 0.98))
	ci.draw_arc(b, br, 0, TAU, 20, col, 1.8, true)
	var f: Font = UiKit.font()
	var txt: String = str(stacks)
	var tfs: int = int(maxf(13.0, br * 1.72))
	var ts: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
	var tp := b + Vector2(-ts.x * 0.5, tfs * 0.36)
	ci.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 2, Color(0, 0, 0, 0.85))
	ci.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(1, 1, 1, 0.99))

static func _draw_symbol(ci: CanvasItem, c: Vector2, k: float, col: Color, sym: String) -> void:
	match sym:
		"snow":  # 六向雪花 + 小分叉
			for i in range(6):
				var a: float = TAU * float(i) / 6.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c, c + d * k, col, 1.8, true)
				var mid: Vector2 = c + d * k * 0.62
				ci.draw_line(mid, mid + Vector2(cos(a + 0.8), sin(a + 0.8)) * k * 0.28, col, 1.2, true)
				ci.draw_line(mid, mid + Vector2(cos(a - 0.8), sin(a - 0.8)) * k * 0.28, col, 1.2, true)
			ci.draw_circle(c, k * 0.14, col)
		"crystal":  # 四角冰晶
			ci.draw_colored_polygon(_poly(c, k, 4, -PI * 0.5), col.darkened(0.25))
			ci.draw_polyline(_close(_poly(c, k, 4, -PI * 0.5)), col, 1.4, true)
			ci.draw_line(c - Vector2(k * 0.5, 0), c + Vector2(k * 0.5, 0), col, 1.0, true)
		"crosshair":  # 准星：环 + 四刻线 + 中点
			ci.draw_arc(c, k * 0.78, 0, TAU, 20, col, 1.6, true)
			ci.draw_circle(c, k * 0.20, col)
			for i in range(4):
				var a2: float = TAU * float(i) / 4.0
				var d2 := Vector2(cos(a2), sin(a2))
				ci.draw_line(c + d2 * k * 0.52, c + d2 * k * 1.06, col, 1.6, true)
		"blast":  # 爆炸星芒（八向尖刺）
			for i in range(8):
				var a3: float = TAU * float(i) / 8.0 + PI / 8.0
				var d3 := Vector2(cos(a3), sin(a3))
				ci.draw_line(c + d3 * k * 0.22, c + d3 * k * (1.08 if i % 2 == 0 else 0.72), col, 2.0, true)
			ci.draw_circle(c, k * 0.26, col.darkened(0.1))
		"seal":  # 方印：外框 + 中横竖（印文感）
			var h := k * 0.82
			ci.draw_rect(Rect2(c - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), col, false, 1.8)
			ci.draw_line(c - Vector2(h * 0.52, 0), c + Vector2(h * 0.52, 0), col, 1.4, true)
			ci.draw_line(c - Vector2(0, h * 0.52), c + Vector2(0, h * 0.52), col, 1.4, true)
		"blade":  # 匕首：细长刀身 + 护手
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k * 1.05), c + Vector2(k * 0.42, k * 0.18),
				c + Vector2(0, k * 0.45), c + Vector2(-k * 0.42, k * 0.18)]), col)
			ci.draw_line(c + Vector2(-k * 0.62, k * 0.42), c + Vector2(k * 0.62, k * 0.42), col, 1.8, true)
		"flame":  # 火焰：双层三角
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k * 1.1), c + Vector2(k * 0.72, k * 0.72), c + Vector2(-k * 0.72, k * 0.72)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k * 0.35), c + Vector2(k * 0.34, k * 0.62), c + Vector2(-k * 0.34, k * 0.62)]), col.darkened(0.45))
		"spear":  # 长戟：枪尖 + 杆
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -k * 1.1), c + Vector2(k * 0.4, -k * 0.05), c + Vector2(0, k * 0.2),
				c + Vector2(-k * 0.4, -k * 0.05)]), col)
			ci.draw_line(c + Vector2(0, k * 0.2), c + Vector2(0, k * 1.05), col, 1.8, true)
			ci.draw_line(c + Vector2(-k * 0.45, k * 0.55), c + Vector2(k * 0.45, k * 0.55), col, 1.4, true)
		"orb":  # 太极/丹丸：外环 + 内核 + 两点
			ci.draw_arc(c, k * 0.92, 0, TAU, 24, col, 1.5, true)
			ci.draw_circle(c, k * 0.42, col)
			ci.draw_circle(c + Vector2(-k * 0.95, 0), k * 0.18, col)
			ci.draw_circle(c + Vector2(k * 0.95, 0), k * 0.18, col)
		"tri_down":  # 倒三角（堕落印记）
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, k * 1.05), c + Vector2(k * 0.95, -k * 0.72), c + Vector2(-k * 0.95, -k * 0.72)]), col)
			ci.draw_line(c + Vector2(-k * 0.45, -k * 0.2), c + Vector2(k * 0.45, -k * 0.2), col.darkened(0.5), 1.6, true)
		"horns":  # 双角（狂）
			ci.draw_line(c + Vector2(-k * 0.8, k * 0.7), c + Vector2(-k * 0.55, -k * 0.85), col, 2.2, true)
			ci.draw_line(c + Vector2(k * 0.8, k * 0.7), c + Vector2(k * 0.55, -k * 0.85), col, 2.2, true)
			ci.draw_line(c + Vector2(-k * 0.2, k * 0.75), c + Vector2(0, -k * 0.35), col, 1.8, true)
			ci.draw_line(c + Vector2(k * 0.2, k * 0.75), c + Vector2(0, -k * 0.35), col, 1.8, true)
		"note":  # 音符（音）
			ci.draw_arc(c + Vector2(-k * 0.35, k * 0.55), k * 0.38, 0, TAU, 16, col, 1.8, true)
			ci.draw_line(c + Vector2(0.0, k * 0.55), c + Vector2(0.0, -k * 0.95), col, 1.8, true)
			ci.draw_line(c + Vector2(0.0, -k * 0.95), c + Vector2(k * 0.62, -k * 0.7), col, 1.8, true)
		_:  # 兜底：六边形 + 中点
			ci.draw_polyline(_close(_poly(c, k * 0.9, 6, -PI * 0.5)), col, 1.6, true)
			ci.draw_circle(c, k * 0.22, col)
