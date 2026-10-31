extends RefCounted
## 小地图绘制库（主机 / LAN 客户端共用）：地形底图、防御塔、英雄、小兵、野怪、迷雾、
## 目标计时、草丛/墙体/血包、视野框、兵线聚类。
## 所有函数为 CanvasItem 立即绘制，必须在 _draw() 内调用。

static var FONT: Font = ThemeDB.fallback_font
const ART = preload("res://scripts/ui/HeroArt.gd")   # 程序化英雄头像（与选人界面同源）

# 图标放大倍数：防御塔 / 普通野怪（水晶与暴君主宰保持原尺寸）
const TURRET_ICON_SCALE := 2.0
const JUNGLE_ICON_SCALE := 2.0
const EPIC_KINDS := ["tyrant", "shadow_tyrant", "dragon", "shadow_dragon", "storm_dragon"]

# ==================== 地形底图 ====================

## 世界坐标 → 小地图底色（120×120：野区深绿 / 兵线暖灰 / 河道青蓝 / 基地暖光）
static func world_color(wx: float, wz: float, map_size: float = 120.0) -> Color:
	var half := map_size * 0.5
	var base := Color(0.078, 0.140, 0.098)
	var n := sin(wx * 0.21 + wz * 0.13) + cos(wx * 0.09 - wz * 0.17)
	base = base.lightened(0.012 * n)
	# 兵线：中路沿 x = -z；发育路贴 z≈+half；对抗路贴 x≈-half
	var lane_col := Color(0.245, 0.222, 0.158)
	var mid_d := absf(wx + wz) / sqrt(2.0)
	if mid_d < 6.5:
		base = base.lerp(lane_col, (1.0 - mid_d / 6.5) * 0.90)
	var bot_d := absf(wz - (half - 4.0))
	if bot_d < 7.0 and absf(wx) < half - 2.0:
		base = base.lerp(lane_col, (1.0 - bot_d / 7.0) * 0.90)
	var left_d := absf(wx + half - 4.0)
	if left_d < 7.0 and absf(wz) < half - 2.0:
		base = base.lerp(lane_col, (1.0 - left_d / 7.0) * 0.90)
	# 河道：x = z 对角线（宽 ±9）
	var river_d := absf(wx - wz) / sqrt(2.0)
	if river_d < 9.0:
		var k := 1.0 - river_d / 9.0
		base = base.lerp(Color(0.10, 0.34, 0.44).lerp(Color(0.18, 0.55, 0.62), k), 0.55 + 0.45 * k)
	# 双方基地：暖色光晕
	for c in [Vector2(-half + 7.0, half - 7.0), Vector2(half - 7.0, -half + 7.0)]:
		var d: float = Vector2(wx, wz).distance_to(c)
		if d < 16.0:
			base = base.lerp(Color(0.45, 0.36, 0.17), (1.0 - d / 16.0) * 0.65)
	return base

## 一次性生成地形底图（120 网格采样后双线性放大，成本低且够清晰）
static func terrain_texture(px: int, map_size: float, grid: int = 120) -> ImageTexture:
	var img := Image.create(grid, grid, false, Image.FORMAT_RGBA8)
	for gy in range(grid):
		var wz: float = (float(gy) + 0.5) / float(grid) * map_size - map_size * 0.5
		for gx in range(grid):
			var wx: float = (float(gx) + 0.5) / float(grid) * map_size - map_size * 0.5
			var c := world_color(wx, wz, map_size)
			var edge: float = maxf(absf(wx), absf(wz)) / (map_size * 0.5)
			if edge > 0.82:
				c = c.darkened((edge - 0.82) / 0.18 * 0.45)
			img.set_pixel(gx, gy, c)
	img.resize(px, px, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)

# ==================== 防御塔 / 水晶 ====================

## 防御塔四种轮廓：外塔=方形城垛 / 内塔=八边形 / 高地塔=菱形 / 水晶=六边形宝石。
## 血量从底部向上填充，低于 45% 泛红；摧毁画灰叉。
static func draw_turret(ci: CanvasItem, pos: Vector2, ratio: float, col: Color, ttype: String, alive: bool = true) -> void:
	# 防御塔图标放大到原来的 2 倍（水晶保持原尺寸，避免遮挡基地周边）
	var s: float = 1.0 if ttype == "crystal" else TURRET_ICON_SCALE
	ci.draw_set_transform(pos, 0.0, Vector2(s, s))
	_draw_turret_shape(ci, Vector2.ZERO, ratio, col, ttype, alive)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_turret_shape(ci: CanvasItem, pos: Vector2, ratio: float, col: Color, ttype: String, alive: bool = true) -> void:
	var size: float = 9.0
	if ttype == "inner":
		size = 10.5
	elif ttype == "high":
		size = 11.5
	elif ttype == "crystal":
		size = 15.0
	var h: float = size * 0.5
	var dark := Color(0.045, 0.055, 0.075, 0.97)
	var lit: Color = col.lightened(0.42)
	var shade: Color = col.darkened(0.32)
	match ttype:
		"crystal":
			if alive:
				ci.draw_circle(pos, h + 6.0, Color(col.r, col.g, col.b, 0.14))
				ci.draw_circle(pos, h + 3.0, Color(col.r, col.g, col.b, 0.20))
			var pts := PackedVector2Array()
			for i in range(6):
				var a: float = -PI / 2.0 + TAU * float(i) / 6.0
				pts.append(pos + Vector2(cos(a), sin(a)) * h)
			ci.draw_colored_polygon(pts, dark)
			if alive:
				ci.draw_colored_polygon(PackedVector2Array([pts[5], pts[0], pts[1], pts[2], pos + Vector2(0, h * 0.2)]), lit)
				ci.draw_colored_polygon(PackedVector2Array([pts[2], pts[3], pts[4], pts[5], pos + Vector2(0, h * 0.2)]), shade)
				ci.draw_line(pts[2], pos + Vector2(0, h * 0.8), Color(1, 1, 1, 0.30), 1.2)
				ci.draw_circle(pos + Vector2(-h * 0.24, -h * 0.38), 2.0, Color(1, 1, 1, 0.60))
				ci.draw_arc(pos, h + 3.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(ratio, 0.0, 1.0), 28,
					Color(1.0, 0.42, 0.30) if ratio < 0.45 else Color(0.55, 1.0, 0.72), 2.0)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.4)
			if not alive:
				_dead_x(ci, pos, h + 1.5)
			return
		"high":
			var d := PackedVector2Array([pos + Vector2(0, -h - 1.5), pos + Vector2(h, 0), pos + Vector2(0, h), pos + Vector2(-h, 0)])
			ci.draw_colored_polygon(d, dark)
			if alive and ratio > 0.0:
				var fh: float = h * 2.0 * clampf(ratio, 0.0, 1.0)
				ci.draw_rect(Rect2(pos.x - h, pos.y + h - fh, h * 2.0, fh), col)
			ci.draw_polyline(d + PackedVector2Array([d[0]]), Color.BLACK, 1.4)
			if alive:
				var core := PackedVector2Array([pos + Vector2(0, -h * 0.46), pos + Vector2(h * 0.46, 0), pos + Vector2(0, h * 0.46), pos + Vector2(-h * 0.46, 0)])
				ci.draw_colored_polygon(core, lit.darkened(0.12))
				ci.draw_polyline(core + PackedVector2Array([core[0]]), Color(1, 1, 1, 0.45), 1.1)
			if not alive:
				_dead_x(ci, pos, h + 1.5)
			return
		"inner":
			# 八边形塔基：与方外塔 / 菱形高地塔 / 六边水晶轮廓明显不同
			if alive:
				ci.draw_circle(pos, h + 3.6, Color(col.r, col.g, col.b, 0.14))
				ci.draw_circle(pos, h + 1.2, Color(col.r, col.g, col.b, 0.24))
			var pts := PackedVector2Array()
			for i in range(8):
				var a: float = -PI / 2.0 + TAU * float(i) / 8.0 + PI / 8.0
				pts.append(pos + Vector2(cos(a), sin(a)) * h)
			ci.draw_colored_polygon(pts, dark)
			if alive and ratio > 0.0:
				var fh: float = h * 2.0 * clampf(ratio, 0.0, 1.0)
				ci.draw_rect(Rect2(pos.x - h * 0.72, pos.y + h - fh, h * 1.44, fh), col)
			if alive:
				var core := PackedVector2Array()
				for i in range(8):
					var a2: float = -PI / 2.0 + TAU * float(i) / 8.0 + PI / 8.0
					core.append(pos + Vector2(cos(a2), sin(a2)) * h * 0.46)
				ci.draw_colored_polygon(core, lit.darkened(0.10))
				ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.55), 1.2)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
			if not alive:
				_dead_x(ci, pos, h + 1.5)
			return
	# —— 外塔：方形塔身 + 城垛 + 白描边 ——
	ci.draw_rect(Rect2(pos - Vector2(h + 1.4, h + 1.4), Vector2(size + 2.8, size + 2.8)), Color(0.055, 0.065, 0.085, 0.95))
	ci.draw_rect(Rect2(pos - Vector2(h, h), Vector2(size, size)), dark)
	if alive and ratio > 0.0:
		var fill_h: float = size * clampf(ratio, 0.0, 1.0)
		ci.draw_rect(Rect2(pos.x - h, pos.y + h - fill_h, size, fill_h), col)
		if ratio < 0.45:
			ci.draw_rect(Rect2(pos.x - h, pos.y + h - fill_h, size, fill_h), Color(1.0, 0.32, 0.24, 0.38))
	var notch := Color(0.06, 0.07, 0.09, 0.95)
	ci.draw_rect(Rect2(pos.x - h * 0.62, pos.y - h - 1.6, h * 0.46, 1.8), notch)
	ci.draw_rect(Rect2(pos.x + h * 0.16, pos.y - h - 1.6, h * 0.46, 1.8), notch)
	ci.draw_rect(Rect2(pos - Vector2(h, h), Vector2(size, size)), Color(1, 1, 1, 0.55) if alive else Color.BLACK, false, 1.3)
	if alive:
		ci.draw_circle(pos, maxf(1.2, h * 0.16), Color(1, 1, 1, 0.75))
	if not alive:
		_dead_x(ci, pos, h + 1.5)

## 摧毁标记：灰色叉
static func _dead_x(ci: CanvasItem, pos: Vector2, r: float) -> void:
	var g := Color(0.55, 0.58, 0.62, 0.95)
	ci.draw_line(pos + Vector2(-r * 0.72, -r * 0.72), pos + Vector2(r * 0.72, r * 0.72), g, 2.0)
	ci.draw_line(pos + Vector2(r * 0.72, -r * 0.72), pos + Vector2(-r * 0.72, r * 0.72), g, 2.0)

# ==================== 精英小兵 / 先锋 ====================

## 主宰先锋 / 风暴先锋 / 暗影先锋：带角有翼的小标记
static func draw_dragon(ci: CanvasItem, pos: Vector2, col: Color, kind: String = "dragon") -> void:
	var s := 7.0
	if kind == "storm":
		s = 9.0
	elif kind == "shadow_dragon":
		s = 8.0
	var accent := Color(0.72, 0.42, 1.0) if kind == "shadow_dragon" else Color(1.0, 0.82, 0.32)
	if kind == "storm":
		accent = Color(1.0, 0.9, 0.45)
	ci.draw_circle(pos, s * 0.95, Color(accent.r, accent.g, accent.b, 0.16))
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(-1.0, -1.0), pos + Vector2(-s * 1.05, -s * 0.15), pos + Vector2(-s * 0.35, s * 0.5)]), col.darkened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(1.0, -1.0), pos + Vector2(s * 1.05, -s * 0.15), pos + Vector2(s * 0.35, s * 0.5)]), col.darkened(0.25))
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -s * 0.62), pos + Vector2(s * 0.34, 0), pos + Vector2(0, s * 0.62), pos + Vector2(-s * 0.34, 0)]), col)
	ci.draw_line(pos + Vector2(-s * 0.22, -s * 0.5), pos + Vector2(-s * 0.4, -s * 0.95), accent, 1.2)
	ci.draw_line(pos + Vector2(s * 0.22, -s * 0.5), pos + Vector2(s * 0.4, -s * 0.95), accent, 1.2)
	ci.draw_line(pos + Vector2(-s * 0.34, 0), pos + Vector2(0, -s * 0.62), Color(1, 1, 1, 0.35), 1.0)
	ci.draw_line(pos + Vector2(s * 0.34, 0), pos + Vector2(0, -s * 0.62), Color(0, 0, 0, 0.45), 1.0)
	ci.draw_polyline(PackedVector2Array([pos + Vector2(0, -s * 0.62), pos + Vector2(s * 0.34, 0), pos + Vector2(0, s * 0.62), pos + Vector2(-s * 0.34, 0), pos + Vector2(0, -s * 0.62)]), Color(0, 0, 0, 0.75), 1.0)
	if kind == "storm":
		ci.draw_arc(pos, s * 0.78, 0, TAU, 18, Color(1.0, 0.88, 0.4, 0.9), 1.4)

## 视野之灵：青色灵体菱形标记 + 20 米视野圈（仅 active 时显示范围）。
static func draw_vision_spirit(ci: CanvasItem, pos: Vector2, range_px: float, active: bool) -> void:
	if active and range_px > 2.0:
		ci.draw_circle(pos, range_px, Color(0.26, 0.82, 1.0, 0.075))
		ci.draw_arc(pos, range_px, 0.0, TAU, 48, Color(0.38, 0.92, 1.0, 0.68), 1.4, true)
		ci.draw_arc(pos, range_px * 0.72, 0.0, TAU, 36, Color(0.55, 0.96, 1.0, 0.20), 1.0, true)
	# 深色底 + 青色灵体菱形，避免和英雄圆形头像 / 小兵点混淆
	ci.draw_circle(pos, 6.0, Color(0.02, 0.07, 0.10, 0.92))
	var d := 6.2
	var pts := PackedVector2Array([pos + Vector2(0, -d), pos + Vector2(d * 0.72, 0),
		pos + Vector2(0, d), pos + Vector2(-d * 0.72, 0)])
	ci.draw_colored_polygon(pts, Color(0.42, 0.94, 1.0, 0.95))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.82), 1.0)
	ci.draw_circle(pos, 1.7, Color(1, 1, 1, 0.98))
	ci.draw_string_outline(FONT, pos + Vector2(7.0, -5.0), "灵", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.88))
	ci.draw_string(FONT, pos + Vector2(7.0, -5.0), "灵", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.78, 1.0, 1.0))

## 攻城车（菱形 + 橙色边）/ 超级兵（六边 + 金色边 + 白芯）
static func draw_elite_minion(ci: CanvasItem, pos: Vector2, col: Color, kind: String = "siege") -> void:
	if kind == "super":
		var s := 6.0
		var pts := PackedVector2Array()
		for i in range(6):
			var a: float = -PI / 2.0 + TAU * float(i) / 6.0
			pts.append(pos + Vector2(cos(a), sin(a)) * s)
		ci.draw_circle(pos, s + 2.0, Color(1.0, 0.85, 0.35, 0.18))
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 0.88, 0.40), 1.4)
		ci.draw_circle(pos, 1.6, Color(1, 1, 1, 0.95))
		return
	var d := 4.5
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -d), pos + Vector2(d, 0), pos + Vector2(0, d), pos + Vector2(-d, 0)]), col)
	ci.draw_polyline(PackedVector2Array([pos + Vector2(0, -d), pos + Vector2(d, 0), pos + Vector2(0, d), pos + Vector2(-d, 0), pos + Vector2(0, -d)]), Color(1.0, 0.62, 0.28), 1.3)
	ci.draw_line(pos + Vector2(-d * 0.55, 0), pos + Vector2(d * 0.55, 0), Color(0, 0, 0, 0.55), 1.2)

# ==================== 野怪 ====================

## 野怪标记：普通营地 / 红蓝 buff / 空间之灵 / 暴君·主宰专属图标。
## seen=false 表示"我方无视野下的默认显示"（略压暗但依然清晰可辨）
static func draw_jungle(ci: CanvasItem, pos: Vector2, kind: String, seen: bool = true) -> void:
	if kind in EPIC_KINDS:
		_draw_epic(ci, pos, kind, seen)   # 暴君/主宰/风暴龙王：保持原尺寸
		return
	# 普通野怪（红蓝 buff / 空间灵 / 河灵 / 常规营地）图标放大到原来的 2 倍
	ci.draw_set_transform(pos, 0.0, Vector2(JUNGLE_ICON_SCALE, JUNGLE_ICON_SCALE))
	_draw_camp(ci, Vector2.ZERO, kind, seen)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_camp(ci: CanvasItem, pos: Vector2, kind: String, seen: bool = true) -> void:
	var a: float = 1.0 if seen else 0.88
	match kind:
		"red_buff":
			ci.draw_circle(pos, 4.4, Color(0.95, 0.34, 0.26, 0.22 * a))
			ci.draw_circle(pos, 3.6, Color(0.96, 0.38, 0.28, a))
			ci.draw_arc(pos, 3.6, 0, TAU, 18, Color(1.0, 0.64, 0.44, a), 1.4)
			ci.draw_circle(pos, 1.5, Color(1.0, 0.88, 0.70, a))
		"blue_buff":
			ci.draw_circle(pos, 4.4, Color(0.35, 0.55, 1.0, 0.22 * a))
			ci.draw_circle(pos, 3.6, Color(0.40, 0.62, 1.0, a))
			ci.draw_arc(pos, 3.6, 0, TAU, 18, Color(0.72, 0.86, 1.0, a), 1.4)
			ci.draw_circle(pos, 1.5, Color(0.86, 0.95, 1.0, a))
		"spatial_spirit", "river_spirit":
			var d := PackedVector2Array([pos + Vector2(0, -4.4), pos + Vector2(3.9, 0), pos + Vector2(0, 4.4), pos + Vector2(-3.9, 0)])
			ci.draw_circle(pos, 4.8, Color(0.35, 0.90, 0.88, 0.20 * a))
			ci.draw_colored_polygon(d, Color(0.40, 0.92, 0.90, a))
			ci.draw_polyline(d + PackedVector2Array([d[0]]), Color(0.06, 0.28, 0.30, a), 1.3)
		_:
			# 普通营地：深色描边 + 亮绿芯，保证在深绿地形上也能一眼看到
			ci.draw_circle(pos, 3.6, Color(0.72, 0.88, 0.54, 0.24 * a))
			ci.draw_circle(pos, 2.8, Color(0.82, 0.95, 0.64, a))
			ci.draw_arc(pos, 2.8, 0, TAU, 14, Color(0.14, 0.22, 0.12, a), 1.3)
			ci.draw_circle(pos, 1.0, Color(1, 1, 1, 0.88 * a))

## 暴君 / 主宰 / 风暴龙王：大号专属图标（光环 + 双角 + 头颅 + 双眼）
static func _draw_epic(ci: CanvasItem, pos: Vector2, kind: String, seen: bool) -> void:
	var a: float = 1.0 if seen else 0.86
	var body := Color(0.96, 0.45, 0.24, a)
	var ring := Color(1.0, 0.74, 0.38, a)
	if kind == "shadow_tyrant":
		body = Color(0.64, 0.34, 0.92, a)
		ring = Color(0.84, 0.66, 1.0, a)
	elif kind == "dragon":
		body = Color(0.34, 0.76, 0.96, a)
		ring = Color(0.74, 0.94, 1.0, a)
	elif kind == "shadow_dragon":
		body = Color(0.56, 0.48, 1.0, a)
		ring = Color(0.82, 0.78, 1.0, a)
	elif kind == "storm_dragon":
		body = Color(1.0, 0.84, 0.30, a)
		ring = Color(1.0, 0.96, 0.64, a)
	ci.draw_circle(pos, 12.8, Color(body.r, body.g, body.b, 0.13 * a))
	ci.draw_arc(pos, 9.6, 0, TAU, 26, Color(ring.r, ring.g, ring.b, 0.62 * a), 1.8)
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(-6.0, -3.8), pos + Vector2(-2.4, -9.2), pos + Vector2(-0.8, -3.4)]), ring)
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(6.0, -3.8), pos + Vector2(2.4, -9.2), pos + Vector2(0.8, -3.4)]), ring)
	ci.draw_circle(pos + Vector2(0, 1.4), 5.8, body)
	ci.draw_arc(pos + Vector2(0, 1.4), 5.8, 0, TAU, 22, Color(0.05, 0.05, 0.08, a), 1.4)
	ci.draw_circle(pos + Vector2(-2.1, 0.4), 1.2, Color(1, 1, 1, 0.95 * a))
	ci.draw_circle(pos + Vector2(2.1, 0.4), 1.2, Color(1, 1, 1, 0.95 * a))
	if kind == "storm_dragon":
		ci.draw_polyline(PackedVector2Array([pos + Vector2(3.4, -6.6), pos + Vector2(0.9, -1.8), pos + Vector2(3.8, -1.4), pos + Vector2(1.3, 4.6)]), Color(1, 1, 1, 0.85 * a), 1.6)

# ==================== 英雄 ====================

## 英雄：朝向箭头 + 底盘 + 本人白环 + 血量弧；阵亡灰点 + 复活倒计时
static func draw_hero(ci: CanvasItem, pos: Vector2, dir: Vector2, base: Color, hp_ratio: float,
		is_self: bool = false, dead: bool = false, respawn: float = 0.0, hero_name: String = "",
		ring_col: Color = Color(0.30, 0.95, 0.42)) -> void:
	var d: Vector2 = dir.normalized() if dir.length() > 0.01 else Vector2(0, -1)
	var r := 21.0	# 头像再放大 2 倍（原 10.5，初始 7.0）
	var body: Color = base if not dead else Color(0.42, 0.44, 0.48, 0.9)
	ci.draw_circle(pos, r + 5.6, Color(0, 0, 0, 0.5))
	# 英雄头像（程序化绘制：元素底色 + 专属徽记 + 阵营环）替代原来的纯色圆点
	if hero_name != "":
		ART.draw_portrait(ci, pos, r, hero_name, base, dead)
	else:
		ci.draw_circle(pos, r, body)
		ci.draw_circle(pos + Vector2(-r * 0.3, -r * 0.34), r * 0.42, Color(1, 1, 1, 0.35))
	if dead:
		var txt := str(int(ceil(respawn)))
		ci.draw_string_outline(FONT, pos + Vector2(-r, r + 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, 4, Color(0, 0, 0, 0.85))
		ci.draw_string(FONT, pos + Vector2(-r, r + 6.0), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, Color(1, 1, 1, 0.95))
		return
	var perp := Vector2(-d.y, d.x)
	ci.draw_colored_polygon(PackedVector2Array([
		pos + d * (r + 13.6), pos + d * (r + 2.4) + perp * 8.4, pos + d * (r + 2.4) - perp * 8.4,
	]), Color(base.r, base.g, base.b, 0.95))
	ci.draw_arc(pos, r, 0, TAU, 24, Color(0, 0, 0, 0.55), 2.0)
	if is_self:
		ci.draw_arc(pos, r + 8.0, 0, TAU, 32, Color(0.32, 1.0, 0.45, 1.0), 3.6, true)
	var hp: float = clampf(hp_ratio, 0.0, 1.0)
	# 血量环颜色按阵营固定（我方绿 / 敌方红），弧长仍表示剩余血量；低血时略微提亮以保留警示
	var hcol := ring_col
	if hp <= 0.25:
		hcol = ring_col.lightened(0.25)
	ci.draw_arc(pos, r + 4.4, -PI / 2.0, -PI / 2.0 + TAU * hp, 28, hcol, 3.4)

# ==================== 小兵聚类 ====================

## 3px 内的小兵合并成一簇（数量多时不糊成一团）
static func cluster(points: Array, thr: float = 3.0) -> Array:
	var out: Array = []
	for p in points:
		var pv: Vector2 = p
		var merged := false
		for c in out:
			var arr: Array = c
			var sum := Vector2.ZERO
			for q in arr:
				sum += q
			if sum.length() > 0.001 and (sum / float(arr.size())).distance_to(pv) <= thr:
				arr.append(pv)
				merged = true
				break
		if not merged:
			out.append([pv])
	return out

static func draw_clusters(ci: CanvasItem, clusters: Array, col: Color, dot_r: float = 3.0) -> void:
	for c in clusters:
		var arr: Array = c
		var sum := Vector2.ZERO
		for q in arr:
			sum += q
		var ctr: Vector2 = sum / float(maxi(arr.size(), 1))
		var scale_f: float = 1.0 + clampf(float(arr.size() - 1) * 0.22, 0.0, 1.2)
		ci.draw_circle(ctr, dot_r * scale_f + 1.4, Color(0, 0, 0, 0.35))
		ci.draw_circle(ctr, dot_r * scale_f, col)
		if arr.size() > 1:
			ci.draw_arc(ctr, dot_r * scale_f + 1.2, 0, TAU, 14, col.lightened(0.45), 1.0)

# ==================== 视野框 / 迷雾 / 目标计时 ====================

## 摄像机视野四角 → 小地图坐标（射线与 y=0 平面求交）
static func viewport_corners(cam: Camera3D, to_minimap: Callable) -> PackedVector2Array:
	var out := PackedVector2Array()
	if cam == null:
		return out
	var vp := cam.get_viewport().get_visible_rect().size
	var corners := [Vector2(0, 0), Vector2(vp.x, 0), vp, Vector2(0, vp.y)]
	for c in corners:
		var origin: Vector3 = cam.project_ray_origin(c)
		var dir: Vector3 = cam.project_ray_normal(c)
		if absf(dir.y) < 0.0001:
			out.append(to_minimap.call(Vector3.ZERO))
			continue
		var t: float = -origin.y / dir.y
		var wpos: Vector3 = origin + dir * t
		out.append(to_minimap.call(Vector3(wpos.x, 0.0, wpos.z)))
	return out

static func draw_viewport(ci: CanvasItem, corners: PackedVector2Array, dashed: bool = false) -> void:
	if corners.size() < 4:
		return
	var col := Color(1, 1, 1, 0.30) if not dashed else Color(1.0, 0.86, 0.35, 0.55)
	if not dashed:
		ci.draw_polyline(PackedVector2Array([corners[0], corners[1], corners[2], corners[3], corners[0]]), col, 1.2)
		return
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var seg: float = 5.0
		var total: float = a.distance_to(b)
		var dir: Vector2 = (b - a) / maxf(total, 0.001)
		var s: float = 0.0
		while s < total:
			var e: float = minf(s + seg, total)
			ci.draw_line(a + dir * s, a + dir * e, col, 1.4)
			s += seg * 2.0

## 视野网格（默认 12×12）；sources = [{"p": Vector3, "r": float}]
static func fog_grid(sources: Array, map_size: float, cell: float = 10.0) -> Array:
	var n := int(ceil(map_size / cell))
	var grid: Array = []
	for y in range(n):
		var row: Array = []
		for x in range(n):
			row.append(false)
		grid.append(row)
	for s in sources:
		var d: Dictionary = s
		var p: Vector3 = d.get("p", Vector3.ZERO)
		var r: float = float(d.get("r", 10.0))
		var wx: float = p.x + map_size * 0.5
		var wz: float = p.z + map_size * 0.5
		var cx0: int = int(clampf(floor((wx - r) / cell), 0.0, float(n - 1)))
		var cx1: int = int(clampf(ceil((wx + r) / cell), 0.0, float(n - 1)))
		var cy0: int = int(clampf(floor((wz - r) / cell), 0.0, float(n - 1)))
		var cy1: int = int(clampf(ceil((wz + r) / cell), 0.0, float(n - 1)))
		for gy in range(cy0, cy1 + 1):
			for gx in range(cx0, cx1 + 1):
				var px: float = (float(gx) + 0.5) * cell
				var py: float = (float(gy) + 0.5) * cell
				if Vector2(px - wx, py - wz).length() <= r:
					grid[gy][gx] = true
	return grid

## 无视野区域压暗（0.26：能读出地形，又不至于把图标压黑）
static func draw_fog(ci: CanvasItem, grid: Array, size_px: float, alpha: float = 0.26) -> void:
	var n: int = grid.size()
	if n <= 0:
		return
	var cs: float = size_px / float(n)
	for y in range(n):
		var row: Array = grid[y]
		for x in range(row.size()):
			if bool(row[x]):
				continue
			ci.draw_rect(Rect2(float(x) * cs, float(y) * cs, cs + 0.5, cs + 0.5), Color(0.02, 0.03, 0.05, alpha))

## 目标倒计时（小地图下方，避免盖住地图）：entries = [{"label","t","alive","color"}]
## 只有「未存活且距诞生/复活 ≤ 60 秒」才读秒；更早（>1 分钟）整行不显示
const OBJECTIVE_COUNTDOWN_LEAD := 60.0

## 读秒字号：跟随小地图尺寸（小地图已放大到 450，写死 13 会小到看不清）
static func countdown_font(size_px: float) -> int:
	return maxi(13, int(round(size_px * 0.056)))

static func draw_objectives(ci: CanvasItem, entries: Array, size_px: float) -> void:
	if entries.is_empty():
		return
	var rows: Array = []
	for e in entries:
		var alive: bool = bool(e.get("alive", false))
		if not alive and float(e.get("t", 0.0)) > OBJECTIVE_COUNTDOWN_LEAD:
			continue   # 诞生/复活前 1 分钟才开始读秒
		rows.append(e)
	if rows.is_empty():
		return
	var fs: int = countdown_font(size_px)
	var row_h: float = float(fs) + 11.0
	var y: float = size_px + 20.0 + float(fs) - 13.0
	for i in range(rows.size()):
		var e: Dictionary = rows[i]
		var alive: bool = bool(e.get("alive", false))
		var col: Color = e.get("color", Color.WHITE)
		var txt := ""
		if alive:
			txt = "%s 已刷新" % str(e.get("label", ""))
			col = Color(1.0, 0.92, 0.55, 0.95)
		else:
			var t: int = maxi(int(ceil(float(e.get("t", 0.0)))), 0)
			txt = "%s %02d:%02d" % [str(e.get("label", "")), t / 60, t % 60]
			col = Color(col.r, col.g, col.b, 0.92)
		var tw := FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_rect(Rect2(2, y - float(fs) * 0.92, tw + 12.0, float(fs) + 6.0), Color(0.02, 0.03, 0.05, 0.55))
		ci.draw_string_outline(FONT, Vector2(8, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		ci.draw_string(FONT, Vector2(8, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += row_h

## 红蓝 buff 复活读秒：暗淡幽灵点位 + 剩余秒数（复活前 30 秒才画）；fs 跟随小地图尺寸
static func draw_camp_respawn(ci: CanvasItem, pos: Vector2, kind: String, left: float, fs: int = 13) -> void:
	if left <= 0.0:
		return
	var col := Color(1.0, 0.52, 0.40) if kind == "red_buff" else Color(0.55, 0.78, 1.0)
	# 幽灵点位：淡色小圆，表示"我方知道这里死了、正在等刷新"
	var dot_r: float = float(fs) * 0.36
	ci.draw_circle(pos, dot_r * 1.1, Color(col.r, col.g, col.b, 0.16))
	ci.draw_arc(pos, dot_r, 0, TAU, 18, Color(col.r, col.g, col.b, 0.55), 1.2, true)
	# 读秒数字（贴点位右侧，深底描边保证可读）
	var txt := "%d" % int(ceil(left))
	var tw := FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := pos + Vector2(dot_r * 1.7, float(fs) * 0.38)
	ci.draw_rect(Rect2(p.x - 2.0, p.y - float(fs) * 0.86, tw + 6.0, float(fs) + 3.0), Color(0.02, 0.03, 0.05, 0.70))
	ci.draw_string_outline(FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
	ci.draw_string(FONT, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# ==================== 静态地形装饰 ====================

## 草丛：柔光 + 深绿圆盘 + 叶脉
static func draw_bush(ci: CanvasItem, pos: Vector2, r: float = 3.4) -> void:
	ci.draw_circle(pos, r * 1.5, Color(0.28, 0.62, 0.32, 0.16))
	ci.draw_circle(pos, r, Color(0.10, 0.30, 0.16, 0.85))
	ci.draw_arc(pos, r, 0, TAU, 14, Color(0.34, 0.78, 0.40, 0.55), 1.0)
	for i in range(3):
		var a: float = TAU * float(i) / 3.0 + 0.5
		ci.draw_line(pos, pos + Vector2(cos(a), sin(a)) * r * 0.72, Color(0.42, 0.86, 0.48, 0.45), 1.0)

## 墙体：旋转长条 + 影子 + 顶部高光
static func draw_wall(ci: CanvasItem, pos: Vector2, ang: float, length: float = 5.0, thick: float = 2.6) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var p := Vector2(-d.y, d.x)
	var hl: float = length * 0.5
	var ht: float = thick * 0.5
	var quad := PackedVector2Array([pos - d * hl - p * ht, pos + d * hl - p * ht, pos + d * hl + p * ht, pos - d * hl + p * ht])
	ci.draw_colored_polygon(PackedVector2Array([quad[0] + Vector2(1.4, 1.6), quad[1] + Vector2(1.4, 1.6), quad[2] + Vector2(1.4, 1.6), quad[3] + Vector2(1.4, 1.6)]), Color(0, 0, 0, 0.35))
	ci.draw_colored_polygon(quad, Color(0.20, 0.21, 0.24, 0.95))
	ci.draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), Color(0.38, 0.40, 0.45, 0.85), 1.0)
	ci.draw_line(pos - d * hl * 0.85 - p * ht * 0.6, pos + d * hl * 0.85 - p * ht * 0.6, Color(0.52, 0.55, 0.60, 0.55), 1.0)

## 血包：可用=绿光十字；已拿走=灰色空心环
static func draw_health_pack(ci: CanvasItem, pos: Vector2, available: bool = true) -> void:
	if not available:
		ci.draw_arc(pos, 3.0, 0, TAU, 14, Color(0.55, 0.58, 0.62, 0.55), 1.2)
		return
	ci.draw_circle(pos, 5.4, Color(0.25, 0.95, 0.45, 0.18))
	ci.draw_circle(pos, 3.4, Color(0.16, 0.72, 0.36, 0.95))
	ci.draw_line(pos + Vector2(-1.8, 0), pos + Vector2(1.8, 0), Color(1, 1, 1, 0.95), 1.8)
	ci.draw_line(pos + Vector2(0, -1.8), pos + Vector2(0, 1.8), Color(1, 1, 1, 0.95), 1.8)


## 已开启的传送阵：紫色双层光环 + 反向旋转弧 + 环绕光点
static func draw_teleport_zone(ci: CanvasItem, pos: Vector2, t: float, highlight: bool = false) -> void:
	var col := Color(0.72, 0.52, 1.0)
	var r: float = 6.4 if highlight else 4.8
	ci.draw_circle(pos, r * 1.7, Color(col.r, col.g, col.b, 0.16))
	ci.draw_circle(pos, r * 0.55, Color(0.82, 0.66, 1.0, 0.30))
	ci.draw_arc(pos, r, 0.0, TAU, 28, Color(col.r, col.g, col.b, 0.95), 1.8, true)
	ci.draw_arc(pos, r * 0.62, t * 1.9, t * 1.9 + PI * 1.25, 18, Color(1, 1, 1, 0.85), 1.5, true)
	for i in 3:
		var a: float = -t * 2.4 + TAU * float(i) / 3.0
		ci.draw_circle(pos + Vector2(cos(a), sin(a)) * r * 0.82, 1.4, Color(1, 1, 1, 0.92))
	ci.draw_circle(pos, 1.6, Color(1, 1, 1, 0.95))


# ==================== 全图技能：瞄准线 / 命中锁定 / 飞行子弹 / 命中爆发 ====================

## 瞄准线：外发光 + 亮芯 + 流动光点（t 为本地时钟秒，驱动流动动画）
static func draw_global_aim(ci: CanvasItem, p0: Vector2, p1: Vector2, col: Color, t: float) -> void:
	var d: Vector2 = p1 - p0
	var ln: float = d.length()
	if ln < 1.0:
		return
	var dir: Vector2 = d / ln
	ci.draw_line(p0, p1, Color(col.r, col.g, col.b, 0.20), 6.0, true)
	ci.draw_line(p0, p1, Color(col.r, col.g, col.b, 0.62), 2.2, true)
	ci.draw_line(p0, p1, Color(1, 1, 1, 0.42), 0.9, true)
	# 流动光点：4 个沿瞄准线滚动的亮点，直观表达"子弹会往这飞"
	for i in 4:
		var f: float = fmod(t * 0.85 + float(i) * 0.25, 1.0)
		var p: Vector2 = p0 + dir * ln * f
		ci.draw_circle(p, 2.2, Color(col.r, col.g, col.b, 0.85))
		ci.draw_circle(p, 1.0, Color(1, 1, 1, 0.95))
	# 末端收束点
	ci.draw_circle(p1, 3.0, Color(col.r, col.g, col.b, 0.55))
	ci.draw_circle(p1, 1.4, Color(1, 1, 1, 0.9))

## 被瞄准锁定的敌人：头像外脉冲锁定环 + 四角括标（"这一发会命中他"）
static func draw_aim_lock(ci: CanvasItem, pos: Vector2, t: float, col: Color) -> void:
	var pulse: float = 0.5 + 0.5 * sin(t * 7.0)
	var r: float = 25.0 + 3.0 * pulse
	ci.draw_circle(pos, r, Color(col.r, col.g, col.b, 0.10 + 0.10 * pulse))
	ci.draw_arc(pos, r, 0.0, TAU, 30, Color(col.r, col.g, col.b, 0.55 + 0.35 * pulse), 2.4, true)
	# 四角括标
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + PI * 0.25
		var c: Vector2 = pos + Vector2(cos(a), sin(a)) * (r + 4.0)
		var tang: Vector2 = Vector2(-sin(a), cos(a))
		var rad: Vector2 = Vector2(cos(a), sin(a))
		ci.draw_line(c - tang * 4.5, c, Color(col.r, col.g, col.b, 0.95), 2.0)
		ci.draw_line(c, c + rad * 4.5, Color(col.r, col.g, col.b, 0.95), 2.0)

## 飞行中的全图子弹：拖尾 + 核心亮点 + 外圈光晕（dir_px 为小地图上的飞行方向）
static func draw_global_bullet(ci: CanvasItem, pos: Vector2, dir_px: Vector2, col: Color, t: float) -> void:
	var dn: Vector2 = dir_px.normalized() if dir_px.length() > 0.01 else Vector2(1, 0)
	# 拖尾：由远及近 3 段渐隐
	for i in 3:
		var back: Vector2 = -dn * (5.0 + float(i) * 4.5)
		var a: float = 0.32 - 0.09 * float(i)
		ci.draw_line(pos + back, pos + back * 0.45, Color(col.r, col.g, col.b, a), 3.2 - float(i) * 0.7, true)
	ci.draw_circle(pos, 6.4, Color(col.r, col.g, col.b, 0.20))
	ci.draw_circle(pos, 3.4, Color(col.r, col.g, col.b, 0.85))
	ci.draw_circle(pos, 1.6, Color(1, 1, 1, 0.95))
	# 呼吸光环，避免高亮弹体在密集小地图上被忽略
	ci.draw_arc(pos, 7.4 + sin(t * 9.0) * 1.2, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 1.2, true)

## 命中爆发：英雄头像外扩散的双环 + 放射短线（age 0→1 驱动扩散与淡出）
static func draw_shot_hit(ci: CanvasItem, pos: Vector2, age: float, col: Color) -> void:
	var a: float = clampf(1.0 - age, 0.0, 1.0)
	var r: float = 24.0 + 34.0 * clampf(age, 0.0, 1.0)
	ci.draw_arc(pos, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.85 * a), 3.4, true)
	ci.draw_arc(pos, r * 0.72, 0.0, TAU, 26, Color(1, 1, 1, 0.75 * a), 2.0, true)
	for i in 8:
		var ang: float = TAU * float(i) / 8.0
		var d: Vector2 = Vector2(cos(ang), sin(ang))
		ci.draw_line(pos + d * (r * 0.85), pos + d * (r * 1.18),
			Color(col.r, col.g, col.b, 0.9 * a), 2.2)
	ci.draw_circle(pos, 6.0 * a, Color(1, 1, 1, 0.55 * a))


