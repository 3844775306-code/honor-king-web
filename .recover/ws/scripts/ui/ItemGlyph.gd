extends RefCounted
## 程序化装备图案：每件装备按「名称关键词 → 造型原型」绘制矢量小图，
## 再用名称哈希做长度/角度/符文的唯一变体；替代原先的「名称首字」占位。
## 只画几何图形，不依赖任何贴图资源。

static var _bg_cache: Dictionary = {}

static func draw(ci: CanvasItem, rect: Rect2, tier: int, qc: Color, item_name: String) -> void:
	if ci == null or rect.size.x < 6.0 or rect.size.y < 6.0:
		return
	var p := Painter.new(ci, rect, tier, qc, item_name)
	p.render(_bg(tier, qc))

static func _bg(tier: int, qc: Color) -> StyleBoxFlat:
	if _bg_cache.has(tier):
		return _bg_cache[tier]
	var sb := StyleBoxFlat.new()
	sb.bg_color = qc.darkened(0.76)
	sb.border_color = qc.lightened(0.18)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 9
	sb.corner_radius_top_right = 9
	sb.corner_radius_bottom_left = 9
	sb.corner_radius_bottom_right = 9
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 2
	_bg_cache[tier] = sb
	return sb


class Painter:
	var ci: CanvasItem
	var rect: Rect2
	var tier: int
	var qc: Color
	var item_name: String
	var seed: int
	var c: Vector2
	var u: float
	var metal := Color(0.80, 0.86, 0.93)
	var metal_hi := Color(0.96, 0.98, 1.0)
	var metal_dark := Color(0.38, 0.44, 0.53)
	var gold := Color(1.0, 0.80, 0.30)
	var gold_hi := Color(1.0, 0.94, 0.66)
	var wood := Color(0.52, 0.33, 0.19)
	var leather := Color(0.45, 0.27, 0.17)
	var ink := Color(0.02, 0.03, 0.05, 0.8)
	var flip := 1.0
	var motif_scale := 1.0

	func _init(p_ci: CanvasItem, p_rect: Rect2, p_tier: int, p_qc: Color, p_name: String) -> void:
		ci = p_ci
		rect = p_rect
		tier = p_tier
		qc = p_qc
		item_name = p_name
		seed = absi(item_name.hash())
		c = rect.get_center()
		u = minf(rect.size.x, rect.size.y) / 64.0
		# 同原型的装备也做镜像/缩放/饰色变体，避免出现完全相同的图案
		flip = 1.0 if h(0) > 0.5 else -1.0
		motif_scale = 0.90 + h(9) * 0.16
		var accents := [Color(1.0, 0.80, 0.30), Color(0.40, 0.88, 1.0), Color(0.78, 0.52, 1.0),
			Color(0.48, 1.0, 0.62), Color(1.0, 0.55, 0.28), Color(1.0, 0.45, 0.64)]
		gold = Color(accents[seed % accents.size()]).lerp(qc.lightened(0.22), 0.28)
		gold_hi = gold.lightened(0.42)

	func render(bg: StyleBoxFlat) -> void:
		ci.draw_style_box(bg, rect)
		# 顶部冷光 + 底部暗角，让平面图标有厚度
		ci.draw_rect(Rect2(rect.position + Vector2(5.0, 2.0), Vector2(rect.size.x - 10.0, rect.size.y * 0.28)),
			Color(1, 1, 1, 0.035))
		ci.draw_circle(c, rect.size.y * 0.44, Color(qc.r, qc.g, qc.b, 0.10))
		# 背景中的专属星图（名称哈希决定位置）
		_stars()
		match _motif():
			"sword": _sword()
			"dagger": _dagger()
			"axe": _axe()
			"hammer": _hammer()
			"bow": _bow()
			"spear": _spear()
			"staff": _staff()
			"book": _book()
			"gem": _gem()
			"orb": _orb()
			"scythe": _scythe()
			"armor": _armor()
			"shield": _shield()
			"cloak": _cloak()
			"boots": _boots()
			"ring": _ring()
			"mask": _mask()
			"fist": _fist()
			"wing": _wing()
			"eye": _eye()
			"claw": _claw()
			"cup": _cup()
			"crown": _crown()
			"hourglass": _hourglass()
			"moon": _moon()
			"banner": _banner()
			_: _gem()
		# 边框刻痕：每件装备的 4 个位置由哈希决定，进一步区分同原型装备
		_marks()

	# ---------- 原型选择 ----------
	func _motif() -> String:
		var n := item_name
		if n.contains("镰"):
			return "scythe"
		if n.contains("弓") or n.contains("箭"):
			return "bow"
		if n.contains("斧"):
			return "axe"
		if n.contains("锤"):
			return "hammer"
		if n.contains("枪") or n.contains("矛"):
			return "spear"
		if n.contains("匕首"):
			return "dagger"
		if n.contains("拳") or n.contains("握"):
			return "fist"
		if n.contains("刀") or n.contains("剑") or n.contains("刃"):
			return "sword"
		if n.contains("杖") or n.contains("棒"):
			return "staff"
		if n.contains("书") or n.contains("典") or n.contains("页") or n.contains("录") or n.contains("学者"):
			return "book"
		if n.contains("反伤"):
			return "shield"
		if n.contains("盾") or n.contains("护"):
			return "shield"
		if n.contains("甲") or n.contains("铠") or n.contains("重装"):
			return "armor"
		if n.contains("袍") or n.contains("篷") or n.contains("披风") or n.contains("衣"):
			return "cloak"
		if n.contains("靴") or n.contains("足"):
			return "boots"
		if n.contains("戒") or n.contains("指环"):
			return "ring"
		if n.contains("面具") or n.contains("面罩"):
			return "mask"
		if n.contains("羽") or n.contains("翼"):
			return "wing"
		if n.contains("杯"):
			return "cup"
		if n.contains("眼"):
			return "eye"
		if n.contains("牙") or n.contains("爪"):
			return "claw"
		if n.contains("时"):
			return "hourglass"
		if n.contains("月"):
			return "moon"
		if n.contains("旗"):
			return "banner"
		if n.contains("冠"):
			return "crown"
		if n.contains("水晶") or n.contains("宝石") or n.contains("玛瑙") or n.contains("结晶") \
				or n.contains("珠") or n.contains("石") or n.contains("精") or n.contains("日") or n.contains("星"):
			return "gem"
		var fallback := ["sword", "gem", "staff", "shield", "orb", "armor", "boots", "ring", "book", "hammer", "spear", "bow", "cloak", "mask"]
		return str(fallback[seed % fallback.size()])

	# ---------- 变体哈希 ----------
	func h(i: int) -> float:
		var x := fposmod(sin(float(seed) * 0.00013 + float(i) * 12.9898) * 43758.5453, 1.0)
		return x

	func tilt() -> float:
		return (h(1) - 0.5) * 0.5

	func _pt(x: float, y: float, ang: float = 0.0) -> Vector2:
		var v := Vector2(x * flip, y) * motif_scale
		if absf(ang) > 0.0001:
			v = v.rotated(ang)
		return c + v * u

	func _poly(pts: Array, col: Color, ang := 0.0, outline := true) -> void:
		var pv := PackedVector2Array()
		for p in pts:
			pv.append(_pt(p.x, p.y, ang))
		ci.draw_colored_polygon(pv, col)
		if outline:
			var closed := PackedVector2Array()
			closed.append_array(pv)
			closed.append(pv[0])
			ci.draw_polyline(closed, Color(0, 0, 0, 0.42), maxf(1.0, u * 0.9), true)

	func _line(x0: float, y0: float, x1: float, y1: float, col: Color, w := 1.4, ang := 0.0) -> void:
		ci.draw_line(_pt(x0, y0, ang), _pt(x1, y1, ang), col, maxf(1.0, u * w), true)

	func _circle_at(x: float, y: float, r: float, col: Color, ang := 0.0) -> void:
		ci.draw_circle(_pt(x, y, ang), u * r, col)

	func _ring_at(x: float, y: float, r: float, col: Color, w := 1.4, ang := 0.0) -> void:
		var p := _pt(x, y, ang)
		ci.draw_arc(p, u * r, 0.0, TAU, 24, col, maxf(1.0, u * w), true)

	func _arc_at(x: float, y: float, r: float, a0: float, a1: float, col: Color, w := 1.4, ang := 0.0) -> void:
		var p := _pt(x, y, ang)
		ci.draw_arc(p, u * r, a0 + ang, a1 + ang, 24, col, maxf(1.0, u * w), true)

	func _rect_at(x: float, y: float, w: float, hgt: float, col: Color, ang := 0.0) -> void:
		_poly([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + hgt), Vector2(x, y + hgt)], col, ang)

	func _stars() -> void:
		for i in range(4):
			var x := -27.0 + h(20 + i) * 54.0
			var y := -27.0 + h(30 + i) * 54.0
			ci.draw_circle(_pt(x, y), maxf(0.7, u * 0.75), Color(qc.r, qc.g, qc.b, 0.36))
		if h(40) > 0.45:
			ci.draw_line(_pt(-24.0, -18.0), _pt(-7.0, -24.0), Color(qc.r, qc.g, qc.b, 0.14), maxf(1.0, u * 0.55))

	func _marks() -> void:
		for i in range(4):
			var side := i % 4
			var t := h(50 + i)
			var col := qc.lightened(0.34)
			match side:
				0:
					ci.draw_line(_pt(-27.0 + t * 20.0, -27.0), _pt(-27.0 + t * 20.0 + 3.0, -23.5), col, maxf(1.0, u * 0.7))
				1:
					ci.draw_line(_pt(27.0 - t * 20.0, 27.0), _pt(27.0 - t * 20.0 - 3.0, 23.5), col, maxf(1.0, u * 0.7))
				2:
					ci.draw_circle(_pt(-27.0 + t * 54.0, 27.0), maxf(0.7, u * 0.6), col)
				3:
					ci.draw_circle(_pt(-27.0 + t * 54.0, -27.0), maxf(0.7, u * 0.6), col)

	# ---------- 造型 ----------
	func _sword() -> void:
		var a := tilt()
		var ln := 17.0 + h(2) * 8.0
		var wd := 2.0 + h(3) * 1.2
		_poly([Vector2(0, -ln), Vector2(wd, 7), Vector2(-wd, 7)], metal, a)
		_poly([Vector2(0, -ln), Vector2(-wd * 0.72, -ln * 0.45), Vector2(-wd, 7), Vector2(-wd * 0.2, 7)],
			metal_hi, a, false)
		_line(0, -ln * 0.92, 0, 5.5, metal_dark, 0.75, a)
		var gw := 6.5 + h(4) * 3.0
		_poly([Vector2(-gw, 7.5), Vector2(gw, 7.5), Vector2(gw * 0.8, 10.5), Vector2(-gw * 0.8, 10.5)], gold, a)
		_line(-gw, 9.0, gw, 9.0, gold_hi, 0.8, a)
		_poly([Vector2(-1.7, 10.5), Vector2(1.7, 10.5), Vector2(1.4, 18.0), Vector2(-1.4, 18.0)], leather, a)
		for i in range(3):
			_line(-1.6, 12.0 + i * 1.7, 1.6, 13.0 + i * 1.7, gold.darkened(0.15), 0.65, a)
		_circle_at(0, 19.0, 2.2 + h(5) * 1.0, gold, a)
		# 剑刃侧面的独特缺口/小三角
		if h(6) > 0.4:
			var yy := -ln * 0.30 - h(7) * 4.0
			_poly([Vector2(wd, yy), Vector2(wd + 2.2, yy + 1.8), Vector2(wd, yy + 3.6)], gold_hi, a, false)
		_line(-wd * 0.35, -ln * 0.65, wd * 0.2, -ln * 0.15, Color(1, 1, 1, 0.55), 0.6, a)

	func _dagger() -> void:
		var a := -0.35 + h(2) * 0.4
		for k in range(2):
			var side := 1.0 if k == 0 else -1.0
			var b := a + side * 0.25
			var ox := -4.0 if k == 0 else 4.0
			_poly([Vector2(ox, -15), Vector2(ox + 2.0, -12), Vector2(ox + 2.0, 12), Vector2(ox - 2.0, 12), Vector2(ox - 2.0, -12)], metal, b)
			_line(ox, -12, ox, 10, metal_dark, 0.6, b)
			_poly([Vector2(ox - 4.5, 7), Vector2(ox + 4.5, 7), Vector2(ox + 4.5, 9), Vector2(ox - 4.5, 9)], gold, b)
			_circle_at(ox, 13.0, 1.6, gold, b)

	func _axe() -> void:
		var a := -0.28 + h(2) * 0.35
		_line(-7, 24, 5, -16, wood, 3.2, a)
		var hx := 5.0
		var hy := -14.0
		_poly([Vector2(hx, hy - 8), Vector2(hx + 14, hy - 10), Vector2(hx + 18, hy + 2),
			Vector2(hx + 10, hy + 6), Vector2(hx + 4, hy + 2)], metal, a)
		_poly([Vector2(hx + 2, hy - 4), Vector2(hx + 12, hy - 6), Vector2(hx + 14, hy + 1), Vector2(hx + 5, hy + 2)], metal_hi, a, false)
		_line(hx + 2, hy - 7, hx + 13, hy + 1, qc.lightened(0.2), 0.8, a)
		_line(-6, 22, -2, 12, leather, 1.8, a)

	func _hammer() -> void:
		var a := 0.22 + h(2) * 0.35
		_line(-2, 23, 4, -18, wood, 3.0, a)
		_poly([Vector2(-10, -23), Vector2(15, -19), Vector2(13, -8), Vector2(-12, -11)], metal, a)
		_poly([Vector2(-9, -21), Vector2(10, -18), Vector2(9, -13), Vector2(-8, -15)], metal_hi, a, false)
		_line(-8, -18, 10, -16, metal_dark, 0.8, a)
		# 锤面上的闪电刻纹（线段绘制，避免细长折线三角化失败）
		_line(5, -18, 2, -12, qc.lightened(0.42), 1.8, a)
		_line(2, -12, 6, -12, qc.lightened(0.42), 1.8, a)
		_line(6, -12, 2, -5, qc.lightened(0.42), 1.8, a)
		_circle_at(-9, 20, 2.5, gold, a)

	func _bow() -> void:
		var a := -0.15 + h(2) * 0.3
		_arc_at(1.0, 2.0, 19.0, -1.18, 1.18, wood, 3.0, a)
		_arc_at(1.0, 2.0, 16.5, -1.02, 1.02, gold.darkened(0.2), 0.75, a)
		_line(-7.0, -16.5, -7.0, 20.5, Color(0.9, 0.9, 0.82, 0.9), 0.75, a)
		_line(-6.5, -15.0, 16.0, 1.5, metal, 2.0, a)
		_poly([Vector2(16.0, 1.5), Vector2(11.0, -1.0), Vector2(12.0, 4.0)], gold_hi, a)
		for i in range(3):
			_line(2.0, -6.0 + i * 4.0, 7.0, -5.0 + i * 4.0, leather, 1.2, a)
		_circle_at(-7.0, 20.0, 1.5, gold, a)

	func _spear() -> void:
		var a := -0.55 + h(2) * 0.2
		_line(-15, 22, 12, -20, wood, 2.6, a)
		_poly([Vector2(12, -20), Vector2(7, -10), Vector2(17, -9), Vector2(22, -18)], metal, a)
		_line(12, -20, 19, -11, metal_hi, 0.9, a)
		_poly([Vector2(8, -8), Vector2(12, -11), Vector2(10, -2)], gold, a)
		for i in range(3):
			_line(10.0 + i * 2.0, -2.0, 7.0 + i * 3.0, 4.0, gold.darkened(0.2), 0.8, a)
		_line(-12, 19, -7, 15, leather, 1.5, a)

	func _staff() -> void:
		var a := -0.28 + h(2) * 0.2
		_line(-13, 23, 6, -15, wood, 3.0, a)
		_line(-12, 22, 5, -13, gold.darkened(0.3), 0.8, a)
		var ox := 8.0
		var oy := -19.0
		_circle_at(ox, oy, 6.0 + h(3) * 2.0, qc.lightened(0.15), a)
		_ring_at(ox, oy, 9.0, gold, 1.4, a)
		_poly([Vector2(ox, oy - 7), Vector2(ox + 4, oy), Vector2(ox, oy + 7), Vector2(ox - 4, oy)], metal_hi, a, false)
		_circle_at(-13, 23, 2.0, gold, a)
		for i in range(3):
			_circle_at(ox - 7.0 + i * 5.0, oy - 12.0 - h(10 + i) * 3.0, 1.1, qc.lightened(0.45), a)

	func _book() -> void:
		var a := -0.12 + h(2) * 0.16
		_poly([Vector2(-19, -12), Vector2(0, -9), Vector2(0, 14), Vector2(-19, 11)], qc.darkened(0.38), a)
		_poly([Vector2(19, -12), Vector2(0, -9), Vector2(0, 14), Vector2(19, 11)], qc.darkened(0.52), a)
		_poly([Vector2(-17, -9), Vector2(-1, -6), Vector2(-1, 11), Vector2(-17, 8)], Color(0.80, 0.76, 0.62), a)
		_poly([Vector2(17, -9), Vector2(1, -6), Vector2(1, 11), Vector2(17, 8)], Color(0.70, 0.66, 0.54), a)
		_line(0, -9, 0, 14, gold, 1.8, a)
		for i in range(3):
			_line(-14, -4 + i * 4, -4, -2 + i * 4, Color(0.35, 0.30, 0.22), 0.65, a)
		_ring_at(-9, 4, 3.6, gold, 1.1, a)
		_poly([Vector2(-9, 1), Vector2(-6, 4), Vector2(-9, 7), Vector2(-12, 4)], qc.lightened(0.2), a, false)
		_line(1, -6, 15, -8, qc.lightened(0.3), 0.8, a)

	func _gem() -> void:
		var r := 15.0 + h(2) * 5.0
		var a := h(3) * TAU
		var pts := [Vector2(0, -r), Vector2(r * 0.76, -r * 0.35), Vector2(r * 0.52, r * 0.75),
			Vector2(-r * 0.52, r * 0.75), Vector2(-r * 0.76, -r * 0.35)]
		_poly(pts, qc.lightened(0.08), a)
		for i in range(pts.size()):
			_poly([Vector2(0, 0), pts[i], pts[(i + 1) % pts.size()]],
				qc.lightened(0.30 if i % 2 == 0 else 0.04), a, false)
		_poly([Vector2(0, -r), Vector2(r * 0.40, -r * 0.25), Vector2(0, r * 0.18), Vector2(-r * 0.35, -r * 0.2)],
			Color(1, 1, 1, 0.35), a, false)
		_ring_at(0, 0, r + 4.0, gold, 1.0, a)
		for i in range(2):
			var ang := a + h(12 + i) * TAU
			_circle_at(cos(ang) * (r + 4.0), sin(ang) * (r + 4.0), 1.4, gold_hi)

	func _orb() -> void:
		var a := h(2) * TAU
		_circle_at(0, 0, 16.0, qc.lightened(0.1), a)
		_circle_at(0, 0, 11.0, qc.lightened(0.32), a)
		_ring_at(0, 0, 19.0, gold, 1.4, a)
		_arc_at(0, 0, 23.0, -0.5, 2.0, gold_hi, 1.1, a)
		_arc_at(0, 0, 23.0, 2.7, 5.2, gold_hi, 1.1, a)
		_poly([Vector2(-9, -6), Vector2(1, -12), Vector2(10, -2), Vector2(2, 9), Vector2(-8, 5)], Color(1, 1, 1, 0.28), a, false)
		for i in range(3):
			_circle_at(-10.0 + i * 10.0, 13.0 + h(13 + i) * 3.0, 1.0, gold_hi, a)

	func _armor() -> void:
		var a := -0.05 + h(2) * 0.12
		_poly([Vector2(-14, -17), Vector2(-7, -21), Vector2(7, -21), Vector2(14, -17),
			Vector2(12, 2), Vector2(0, 18), Vector2(-12, 2)], metal, a)
		_poly([Vector2(-11, -16), Vector2(-4, -19), Vector2(-3, 7), Vector2(-9, 1)], metal_hi, a, false)
		_poly([Vector2(11, -16), Vector2(4, -19), Vector2(3, 7), Vector2(9, 1)], metal_dark, a, false)
		_poly([Vector2(-9, -20), Vector2(-3, -23), Vector2(3, -23), Vector2(9, -20), Vector2(6, -15), Vector2(-6, -15)], qc.darkened(0.2), a)
		_line(-8, -12, 8, -12, gold, 1.0, a)
		_line(-10, 0, 10, 0, gold.darkened(0.1), 1.0, a)
		_poly([Vector2(0, -6), Vector2(6, 2), Vector2(0, 11), Vector2(-6, 2)], qc.lightened(0.18), a, false)
		for i in range(2):
			_circle_at(-8 + i * 16, -18, 1.1, gold_hi, a)

	func _shield() -> void:
		var a := -0.08 + h(2) * 0.14
		_poly([Vector2(0, -23), Vector2(19, -16), Vector2(16, 7), Vector2(0, 23), Vector2(-16, 7), Vector2(-19, -16)],
			qc.lightened(0.12), a)
		_poly([Vector2(0, -18), Vector2(14, -13), Vector2(12, 5), Vector2(0, 18), Vector2(-12, 5), Vector2(-14, -13)],
			qc.darkened(0.35), a, false)
		_line(0, -17, 0, 16, gold, 1.8, a)
		_line(-12, -3, 12, -3, gold, 1.8, a)
		_circle_at(0, -3, 3.5, gold_hi, a)
		for i in range(4):
			_circle_at(-14 + (i % 2) * 28, -12 + int(i / 2) * 20, 1.0, gold_hi, a)
		# 反伤刺甲：盾缘尖刺
		if item_name.contains("反伤"):
			for i in range(3):
				var sx := -12.0 + i * 12.0
				_poly([Vector2(sx, 10), Vector2(sx + 4, 23), Vector2(sx + 8, 10)], qc.lightened(0.3), a, false)

	func _cloak() -> void:
		var a := -0.08 + h(2) * 0.12
		_poly([Vector2(0, -24), Vector2(14, -14), Vector2(20, 21), Vector2(7, 14), Vector2(0, 23),
			Vector2(-7, 14), Vector2(-20, 21), Vector2(-14, -14)], qc.darkened(0.45), a)
		_poly([Vector2(0, -24), Vector2(9, -15), Vector2(4, 15), Vector2(0, 23), Vector2(-4, 15), Vector2(-9, -15)],
			qc.lightened(0.15), a, false)
		_arc_at(0, -15, 9, 3.3, 6.1, gold, 1.4, a)
		_line(0, -15, 0, 20, qc.lightened(0.3), 0.8, a)
		_circle_at(0, -14, 2.0, gold_hi, a)
		for i in range(2):
			_line(-8 + i * 16, 0, -10 + i * 20, 15, qc.lightened(0.24), 0.7, a)

	func _boots() -> void:
		var a := -0.15 + h(2) * 0.25
		_poly([Vector2(-7, -22), Vector2(5, -22), Vector2(7, 2), Vector2(18, 10), Vector2(18, 19),
			Vector2(-8, 19), Vector2(-8, 10), Vector2(-3, 4)], leather, a)
		_poly([Vector2(-5, -19), Vector2(2, -19), Vector2(4, 1), Vector2(14, 9), Vector2(14, 16), Vector2(-5, 16), Vector2(-5, 9)],
			leather.lightened(0.22), a, false)
		_line(-8, 19, 18, 19, metal_dark, 2.0, a)
		for i in range(3):
			_line(-5 + i * 7, 19, -3 + i * 7, 24, gold, 1.0, a)
		_line(-5, -8, 5, -8, gold, 1.2, a)
		_circle_at(3, -3, 1.8, gold_hi, a)

	func _ring() -> void:
		var a := h(2) * 0.6 - 0.3
		_ring_at(0, 3, 15.0, gold, 3.4, a)
		_ring_at(0, 3, 15.0, gold_hi, 1.0, a)
		_poly([Vector2(0, -23), Vector2(8, -15), Vector2(0, -7), Vector2(-8, -15)], qc.lightened(0.2), a)
		_poly([Vector2(0, -21), Vector2(4, -15), Vector2(0, -10), Vector2(-4, -15)], Color(1, 1, 1, 0.4), a, false)
		for i in range(2):
			_circle_at(-15 + i * 30, 3, 2.3, gold_hi, a)
			_line(-12 + i * 24, 13, -18 + i * 36, 21, gold, 0.9, a)

	func _mask() -> void:
		var a := -0.06 + h(2) * 0.12
		_poly([Vector2(-18, -16), Vector2(-7, -23), Vector2(7, -23), Vector2(18, -16),
			Vector2(13, 4), Vector2(0, 20), Vector2(-13, 4)], qc.darkened(0.15), a)
		_poly([Vector2(-13, -11), Vector2(-5, -14), Vector2(-2, -5), Vector2(-10, -2)], ink, a, false)
		_poly([Vector2(13, -11), Vector2(5, -14), Vector2(2, -5), Vector2(10, -2)], ink, a, false)
		_circle_at(-7, -7, 2.0, qc.lightened(0.5), a)
		_circle_at(7, -7, 2.0, qc.lightened(0.5), a)
		_line(0, -3, 0, 9, gold, 1.2, a)
		_line(-4, 10, 4, 10, gold.darkened(0.1), 1.0, a)
		for i in range(3):
			_circle_at(-14 + i * 14, -18, 1.0, gold_hi, a)

	func _fist() -> void:
		var a := -0.18 + h(2) * 0.25
		_poly([Vector2(-14, -10), Vector2(-4, -19), Vector2(8, -17), Vector2(16, -5),
			Vector2(12, 12), Vector2(-4, 18), Vector2(-15, 7)], metal, a)
		for i in range(3):
			_poly([Vector2(-10 + i * 7, -17), Vector2(-5 + i * 7, -20), Vector2(-2 + i * 7, -12), Vector2(-7 + i * 7, -9)], metal_hi, a, false)
		_poly([Vector2(-12, 4), Vector2(8, 9), Vector2(4, 17), Vector2(-9, 13)], qc.darkened(0.35), a)
		_line(-11, 0, 10, 5, gold, 1.5, a)
		for i in range(3):
			_poly([Vector2(-10 + i * 9, -18), Vector2(-5 + i * 9, -24), Vector2(-2 + i * 9, -17)], gold, a, false)
		_line(-15, 7, -21, 15, gold.darkened(0.1), 1.8, a)

	func _wing() -> void:
		var a := -0.12 + h(2) * 0.2
		_poly([Vector2(0, 4), Vector2(-10, -21), Vector2(-24, -12), Vector2(-17, 3), Vector2(-22, 16), Vector2(-6, 12)],
			metal_hi, a)
		_poly([Vector2(0, 4), Vector2(10, -21), Vector2(24, -12), Vector2(17, 3), Vector2(22, 16), Vector2(6, 12)],
			metal, a)
		for i in range(3):
			_line(-7, -15 + i * 8, -18, -9 + i * 9, metal_dark, 1.0, a)
			_line(7, -15 + i * 8, 18, -9 + i * 9, metal_dark, 1.0, a)
		_circle_at(0, 2, 3.0, gold, a)
		_poly([Vector2(0, 2), Vector2(6, -4), Vector2(12, 3), Vector2(0, 11), Vector2(-12, 3), Vector2(-6, -4)], qc.lightened(0.2), a, false)

	func _eye() -> void:
		var a := -0.05 + h(2) * 0.1
		var pts := PackedVector2Array()
		pts.append(_pt(-24, 0, a))
		pts.append(_pt(-10, -13, a))
		pts.append(_pt(10, -13, a))
		pts.append(_pt(24, 0, a))
		pts.append(_pt(10, 13, a))
		pts.append(_pt(-10, 13, a))
		ci.draw_colored_polygon(pts, Color(0.82, 0.78, 0.66))
		_ring_at(0, 0, 10.0, qc.lightened(0.1), 5.0, a)
		_ring_at(0, 0, 5.0, ink, 4.0, a)
		_circle_at(2.5, -3.0, 1.8, Color(1, 1, 1, 0.75), a)
		_arc_at(0, 0, 15.0, 3.5, 5.9, gold, 1.0, a)
		for i in range(3):
			_line(-20 + i * 20, -19, -16 + i * 20, -15, qc.lightened(0.4), 0.8, a)

	func _claw() -> void:
		var a := -0.2 + h(2) * 0.4
		for i in range(3):
			var ox := -12.0 + i * 12.0
			_poly([Vector2(ox - 2, 19), Vector2(ox - 4, 4), Vector2(ox - 1, -18), Vector2(ox + 1, -21),
				Vector2(ox + 3, -18), Vector2(ox + 4, 4), Vector2(ox + 2, 19)],
				metal if i != 1 else qc.lightened(0.15), a)
			_line(ox - 2, 17, ox, -17, metal_hi, 0.9, a)
		_poly([Vector2(-17, 14), Vector2(17, 14), Vector2(12, 22), Vector2(-12, 22)], leather, a)
		for i in range(2):
			_line(-8 + i * 16, 14, -6 + i * 16, 22, gold, 0.8, a)

	func _cup() -> void:
		var a := -0.08 + h(2) * 0.16
		_poly([Vector2(-13, -19), Vector2(13, -19), Vector2(10, -2), Vector2(5, 5), Vector2(-5, 5), Vector2(-10, -2)], gold, a)
		_poly([Vector2(-10, -16), Vector2(10, -16), Vector2(7, -4), Vector2(-7, -4)], qc.lightened(0.3), a, false)
		_line(-13, -19, 13, -19, gold_hi, 1.8, a)
		_line(0, 5, 0, 15, gold, 2.2, a)
		_poly([Vector2(-10, 20), Vector2(10, 20), Vector2(8, 15), Vector2(-8, 15)], gold, a)
		_poly([Vector2(-7, -7), Vector2(7, -7), Vector2(5, -2), Vector2(-5, -2)], qc.lightened(0.4), a, false)
		_circle_at(0, -12, 2.0, qc.lightened(0.55), a)
		for i in range(2):
			_circle_at(-8 + i * 16, 12, 1.2, qc.lightened(0.5), a)

	func _crown() -> void:
		var a := -0.05 + h(2) * 0.1
		var pts := [Vector2(-20, 16), Vector2(-20, -11), Vector2(-10, -2), Vector2(0, -21),
			Vector2(10, -2), Vector2(20, -11), Vector2(20, 16)]
		_poly(pts, gold, a)
		_poly([Vector2(-17, 14), Vector2(-17, -6), Vector2(-9, 1), Vector2(0, -14), Vector2(9, 1), Vector2(17, -6), Vector2(17, 14)],
			gold_hi, a, false)
		_line(-15, 11, 15, 11, Color(0.35, 0.22, 0.06), 1.1, a)
		for i in range(3):
			_circle_at(-10 + i * 10, 2, 2.0, qc.lightened(0.3), a)
		_circle_at(0, -21, 2.2, qc.lightened(0.5), a)

	func _hourglass() -> void:
		var a := -0.06 + h(2) * 0.12
		_rect_at(-15, -22, 30, 4, gold, a)
		_rect_at(-15, 18, 30, 4, gold, a)
		_poly([Vector2(-12, -18), Vector2(12, -18), Vector2(0, 0)], qc.lightened(0.12), a)
		_poly([Vector2(-12, 18), Vector2(12, 18), Vector2(0, 0)], qc.lightened(0.22), a)
		_line(-12, -18, 12, -18, gold_hi, 1.0, a)
		_line(-12, 18, 12, 18, gold_hi, 1.0, a)
		_poly([Vector2(-7, 15), Vector2(7, 15), Vector2(0, 5)], qc.lightened(0.42), a, false)
		_line(0, 0, 0, 15, Color(1, 1, 1, 0.35), 0.7, a)
		for i in range(3):
			_circle_at(-5 + i * 5, -13 + h(20 + i) * 5.0, 1.0, gold_hi, a)

	func _moon() -> void:
		var a := h(2) * TAU
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		for i in range(18):
			var t := TAU * float(i) / 18.0
			outer.append(_pt(cos(t) * 21.0, sin(t) * 21.0, a))
			inner.append(_pt(cos(t) * 16.0 + 8.0, sin(t) * 16.0, a))
		ci.draw_colored_polygon(outer, qc.lightened(0.25))
		ci.draw_colored_polygon(inner, Color(qc.r * 0.32, qc.g * 0.32, qc.b * 0.40, 1.0))
		_ring_at(0, 0, 24.0, gold, 1.1, a)
		for i in range(4):
			var t2 := TAU * h(30 + i)
			_circle_at(cos(t2) * 27.0, sin(t2) * 27.0, 1.2, gold_hi)

	func _banner() -> void:
		var a := -0.08 + h(2) * 0.2
		_line(-8, 23, -4, -24, wood, 2.6, a)
		_poly([Vector2(-4, -22), Vector2(19, -18), Vector2(15, -4), Vector2(20, 6), Vector2(-4, 2)], qc.darkened(0.2), a)
		_poly([Vector2(-3, -19), Vector2(15, -15), Vector2(12, -5), Vector2(16, 2), Vector2(-3, -1)], qc.lightened(0.25), a, false)
		_poly([Vector2(0, -12), Vector2(8, -7), Vector2(0, -2), Vector2(-6, -7)], gold, a, false)
		_circle_at(-4, -24, 2.0, gold_hi, a)

	func _scythe() -> void:
		var a := -0.18 + h(2) * 0.36
		_line(-8, 23, 4, -22, wood, 3.0, a)
		var pts := PackedVector2Array()
		for i in range(12):
			var t := 0.25 + float(i) / 11.0 * 2.3
			pts.append(_pt(4.0 + cos(t) * 19.0, -22.0 - sin(t) * 15.0, a))
		for i in range(11, -1, -1):
			var t := 0.25 + float(i) / 11.0 * 2.3
			pts.append(_pt(4.0 + cos(t) * 10.0, -22.0 - sin(t) * 8.0, a))
		ci.draw_colored_polygon(pts, metal)
		_ring_at(20, -33, 10.0, qc.lightened(0.3), 0.8, a)
		_circle_at(-8, 23, 2.2, gold, a)


