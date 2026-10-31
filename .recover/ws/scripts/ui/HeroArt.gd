extends RefCounted
## 英雄专属徽记：纯矢量程序化绘制（项目无美术资源），用于小地图右侧的友方/敌方英雄环形头像。
## 用法：const HeroArt = preload("res://scripts/ui/HeroArt.gd")，再 HeroArt.draw_portrait(...)

## 每个英雄的专属图形（按英雄名，缺失时回退到元素色圆环）
const MOTIF := {
	"亚瑟": "sword_shield",
	"吕布": "halberd",
	"马超": "spear",
	"铠": "armor",
	"不知火舞": "flame_fan",
	"甄姬": "ripple",
	"狄仁杰": "token",
	"太乙真人": "gourd",
	"东皇太一": "eclipse",
	"李白": "sword_wine",
	"兰陵王": "mask",
	"孙尚香": "cannon",
	"马可波罗": "dual_guns",
	"张飞": "serpent_spear",
	"沈梦溪": "bomb",
	"刘禅": "gear",
	"孙悟空": "staff",
	"英睿": "wing",
	"安琪拉": "fireball",
	"妲己": "fox_charm",
	"小乔": "blossom",
	"鲁班七号": "automaton",
	"夏侯惇": "eye_blade",
	"后羿": "sun_bow",
	"李元芳": "shuriken",
	"元流之子": "core",
	"大禹": "mountain_axe",
	"王昭君": "snowflake",}

## 英雄专属主色（同元素英雄靠色相再区分一档）
const ACCENT := {
	"亚瑟": Color(0.45, 0.72, 1.0),
	"吕布": Color(1.0, 0.45, 0.25),
	"马超": Color(0.35, 0.90, 1.0),
	"铠": Color(0.64, 0.50, 1.0),
	"不知火舞": Color(1.0, 0.42, 0.32),
	"甄姬": Color(0.55, 0.86, 1.0),
	"狄仁杰": Color(1.0, 0.80, 0.36),
	"太乙真人": Color(0.45, 0.95, 0.66),
	"东皇太一": Color(0.72, 0.52, 1.0),
	"李白": Color(0.78, 0.88, 1.0),
	"兰陵王": Color(0.42, 0.88, 0.78),
	"孙尚香": Color(1.0, 0.66, 0.30),
	"马可波罗": Color(1.0, 0.90, 0.62),
	"张飞": Color(1.0, 0.52, 0.30),
	"沈梦溪": Color(1.0, 0.62, 0.56),
	"刘禅": Color(0.82, 0.90, 0.42),
	"孙悟空": Color(1.0, 0.85, 0.32),
	"英睿": Color(0.62, 0.82, 1.0),
	"安琪拉": Color(1.0, 0.55, 0.30),
	"妲己": Color(1.0, 0.50, 0.75),
	"小乔": Color(1.0, 0.72, 0.85),
	"鲁班七号": Color(1.0, 0.85, 0.45),
	"夏侯惇": Color(1.0, 0.40, 0.35),
	"后羿": Color(1.0, 0.78, 0.35),
	"李元芳": Color(0.60, 0.95, 0.60),
	"元流之子": Color(0.75, 0.80, 1.0),
	"大禹": Color(0.70, 0.85, 0.55),
	"王昭君": Color(0.60, 0.90, 1.0),}

static func accent_of(hero_name: String) -> Color:
	if ACCENT.has(hero_name):
		return ACCENT[hero_name]
	return Vfx.color_for_hero(hero_name)

## 环形英雄头像：深色内盘 + 英雄色径向光 + 专属徽记 + 阵营细边；dead=true 整体压暗去色
# ==================== 原初印记等级（非数字：环上符文 + 段位色） ====================
# 0 级不画；1~6 级依次点亮 1~6 枚环上符文（自顶部顺时针），同时整体换段位色：
# 青铜(1~2)/银(3)/金(4)/赤金(5)/紫金(6，光晕+内环)。不看数字，凭「亮几枚 + 什么颜色」一眼读等级。
const MARK_TIER_COL := [
	Color(0.0, 0.0, 0.0, 0.0),
	Color(0.80, 0.52, 0.26),
	Color(0.92, 0.60, 0.30),
	Color(0.80, 0.88, 0.98),
	Color(1.00, 0.84, 0.34),
	Color(1.00, 0.56, 0.22),
	Color(0.82, 0.55, 1.00),
]

static func draw_primitive_mark(ci: CanvasItem, center: Vector2, radius: float, level: int) -> void:
	var lv := clampi(level, 0, 6)
	if lv <= 0 or radius < 2.5:
		return
	var col: Color = MARK_TIER_COL[lv]
	var rr := radius * 1.14
	var pip := maxf(radius * 0.15, 1.15)
	# 5/6 级：外发光环；6 级再加内环，和 5 级拉开差距
	if lv >= 5:
		ci.draw_arc(center, rr, 0.0, TAU, 30, Color(col.r, col.g, col.b, 0.22 if lv == 5 else 0.34),
			maxf(radius * 0.22, 2.2), true)
	if lv >= 6:
		ci.draw_arc(center, radius * 0.74, -PI * 0.5, PI * 1.5, 24,
			Color(col.r, col.g, col.b, 0.55), maxf(radius * 0.10, 1.2), true)
	for i in lv:
		var a := -PI * 0.5 + TAU * float(i) / 6.0
		var p := center + Vector2(cos(a), sin(a)) * rr
		var up := Vector2(cos(a), sin(a))
		var side := Vector2(-up.y, up.x)
		var pts := PackedVector2Array([p - up * pip, p - side * pip * 0.72,
			p + up * pip, p + side * pip * 0.72])
		ci.draw_colored_polygon(pts, col)
		ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]),
			Color(0, 0, 0, 0.55), maxf(pip * 0.30, 1.0))

static func draw_portrait(ci: CanvasItem, center: Vector2, radius: float, hero_name: String,
		team_col: Color, dead := false) -> void:
	var acc := accent_of(hero_name)
	ci.draw_circle(center, radius, Color(0.03, 0.045, 0.075, 0.96))
	for i in range(10):
		var t := 1.0 - float(i) / 9.0
		ci.draw_circle(center, radius * 0.94 * t, Color(acc.r, acc.g, acc.b, 0.055))
	var k := radius * 0.52
	var motif := str(MOTIF.get(hero_name, ""))
	var col := acc.lightened(0.35) if not dead else Color(0.62, 0.64, 0.70)
	if motif != "":
		_emblem(ci, center, k * 1.22, motif, Color(acc.r, acc.g, acc.b, 0.16))
		_emblem(ci, center, k, motif, col)
	else:
		ci.draw_arc(center, k * 0.9, 0, TAU, 26, col, maxf(k * 0.16, 1.4), true)
	if dead:
		ci.draw_circle(center, radius, Color(0.02, 0.02, 0.03, 0.52))
	# 阵营细边（保留队伍辨识）
	ci.draw_arc(center, radius - 1.5, 0, TAU, 40, Color(team_col.r, team_col.g, team_col.b, 0.85),
		maxf(radius * 0.045, 1.6), true)

# ---------------- 徽记：k 为单位半径，坐标相对中心 ----------------
static func _emblem(ci: CanvasItem, c: Vector2, k: float, id: String, col: Color) -> void:
	if col.a <= 0.01:
		return
	match id:
		"sword_shield":  # 亚瑟：圣剑 + 圆盾
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.55 * k, -1.02 * k), c + Vector2(0.20 * k, -0.30 * k),
				c + Vector2(0.44 * k, -0.22 * k), c + Vector2(0.80 * k, -0.95 * k)]), col)
			ci.draw_line(c + Vector2(0.30 * k, -0.12 * k), c + Vector2(-0.20 * k, 0.34 * k),
				col, maxf(k * 0.18, 1.6), true)
			ci.draw_circle(c + Vector2(-0.30 * k, 0.48 * k), k * 0.30, col)
			ci.draw_circle(c + Vector2(-0.30 * k, 0.48 * k), k * 0.16, Color(0.03, 0.05, 0.08, 0.85))
		"halberd":  # 吕布：方天画戟（长杆 + 月牙刃）
			ci.draw_line(c + Vector2(0.10 * k, 1.0 * k), c + Vector2(0.10 * k, -1.0 * k),
				col, maxf(k * 0.14, 1.4), true)
			ci.draw_arc(c + Vector2(0.10 * k, -0.62 * k), k * 0.52, -PI * 0.95, PI * 0.15,
				16, col, maxf(k * 0.20, 1.8), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.10 * k, -1.02 * k), c + Vector2(0.34 * k, -0.72 * k),
				c + Vector2(0.06 * k, -0.66 * k)]), col)
		"spear":  # 马超：长枪 + 冲刺纹
			ci.draw_line(c + Vector2(-0.62 * k, 0.92 * k), c + Vector2(0.52 * k, -0.86 * k),
				col, maxf(k * 0.13, 1.3), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.52 * k, -0.86 * k), c + Vector2(0.66 * k, -0.36 * k),
				c + Vector2(0.20 * k, -0.66 * k)]), col)
			for i in range(2):
				var y := 0.10 * k + i * 0.34 * k
				ci.draw_line(c + Vector2(-0.86 * k, y), c + Vector2(-0.40 * k, y),
					Color(col.r, col.g, col.b, 0.75), maxf(k * 0.11, 1.2), true)
		"armor":  # 铠：魔铠（六边护甲 + 双角）
			var hex := PackedVector2Array()
			for i in range(6):
				var a := -PI / 2 + i * TAU / 6.0
				hex.append(c + Vector2(cos(a), sin(a)) * k * 0.88)
			ci.draw_polyline(hex + PackedVector2Array([hex[0]]), col, maxf(k * 0.13, 1.3), true)
			ci.draw_line(c + Vector2(-0.40 * k, -0.74 * k), c + Vector2(-0.72 * k, -1.02 * k),
				col, maxf(k * 0.14, 1.4), true)
			ci.draw_line(c + Vector2(0.40 * k, -0.74 * k), c + Vector2(0.72 * k, -1.02 * k),
				col, maxf(k * 0.14, 1.4), true)
			ci.draw_circle(c, k * 0.22, col)
		"flame_fan":  # 不知火舞：折扇 + 火舌
			var fan := PackedVector2Array([c])
			for i in range(9):
				var a := -PI * 0.55 + i * PI * 1.1 / 8.0
				fan.append(c + Vector2(cos(a), sin(a)) * k * 0.95)
			ci.draw_colored_polygon(fan, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.10 * k), c + Vector2(0.28 * k, 0.55 * k),
				c + Vector2(0, 0.92 * k), c + Vector2(-0.28 * k, 0.55 * k)]), Color(0.02, 0.04, 0.07, 0.8))
		"ripple":  # 甄姬：洛水涟漪
			for i in range(3):
				ci.draw_arc(c, k * (0.36 + i * 0.28), -PI * 0.85, PI * 0.15,
					16, Color(col.r, col.g, col.b, 0.9 - i * 0.2), maxf(k * 0.12, 1.2), true)
			ci.draw_circle(c + Vector2(0, 0.18 * k), k * 0.14, col)
		"token":  # 狄仁杰：令牌 + 三道令纹
			ci.draw_style_box(UiKit.flat(0.9, int(k * 0.3), int(maxf(k * 0.12, 2.0)),
				col, Color(0.04, 0.05, 0.08, 0.9), 0.0, 0.0),
				Rect2(c - Vector2(0.44 * k, 0.86 * k), Vector2(0.88 * k, 1.72 * k)))
			for i in range(3):
				var y := c.y - 0.44 * k + i * 0.42 * k
				ci.draw_line(Vector2(c.x - 0.26 * k, y), Vector2(c.x + 0.26 * k, y), col,
					maxf(k * 0.09, 1.1), true)
		"gourd":  # 太乙真人：炼丹葫芦
			ci.draw_circle(c + Vector2(0, 0.34 * k), k * 0.46, col)
			ci.draw_circle(c + Vector2(0, -0.42 * k), k * 0.32, col)
			ci.draw_line(c + Vector2(0, -0.74 * k), c + Vector2(0, -0.98 * k), col,
				maxf(k * 0.16, 1.5), true)
			ci.draw_circle(c + Vector2(0.24 * k, 0.20 * k), k * 0.10, Color(0.03, 0.05, 0.08, 0.85))
		"eclipse":  # 东皇太一：日月蚀
			ci.draw_circle(c, k * 0.92, Color(col.r, col.g, col.b, 0.24))
			ci.draw_arc(c, k * 0.88, 0, TAU, 28, col, maxf(k * 0.16, 1.4), true)
			ci.draw_circle(c + Vector2(0.18 * k, -0.12 * k), k * 0.46, Color(0.03, 0.04, 0.07, 0.9))
			for i in range(2):
				var a := -PI * 0.5 + i * PI
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 1.02, k * 0.12, col)
		"sword_wine":  # 李白：剑 + 酒葫芦
			ci.draw_line(c + Vector2(0.30 * k, -0.98 * k), c + Vector2(-0.24 * k, 0.42 * k),
				col, maxf(k * 0.15, 1.4), true)
			ci.draw_line(c + Vector2(-0.52 * k, 0.24 * k), c + Vector2(0.06 * k, 0.54 * k),
				col, maxf(k * 0.13, 1.3), true)
			ci.draw_circle(c + Vector2(0.42 * k, 0.62 * k), k * 0.26, col)
			ci.draw_circle(c + Vector2(-0.74 * k, -0.62 * k), k * 0.10,
				Color(col.r, col.g, col.b, 0.8))
		"mask":  # 兰陵王：面甲
			ci.draw_style_box(UiKit.flat(0.92, int(k * 0.5), int(maxf(k * 0.12, 2.0)), col,
				Color(0.04, 0.05, 0.08, 0.92), 0.0, 0.0),
				Rect2(c - Vector2(0.66 * k, 0.92 * k), Vector2(1.32 * k, 1.54 * k)))
			ci.draw_line(c + Vector2(-0.42 * k, -0.10 * k), c + Vector2(-0.08 * k, -0.02 * k),
				Color(0.02, 0.03, 0.05, 0.9), maxf(k * 0.13, 1.3), true)
			ci.draw_line(c + Vector2(0.42 * k, -0.10 * k), c + Vector2(0.08 * k, -0.02 * k),
				Color(0.02, 0.03, 0.05, 0.9), maxf(k * 0.13, 1.3), true)
			ci.draw_line(c + Vector2(0, -0.92 * k), c + Vector2(0, -1.16 * k), col,
				maxf(k * 0.14, 1.4), true)
		"cannon":  # 孙尚香：重炮 + 炮口闪光
			ci.draw_line(c + Vector2(-0.52 * k, 0.60 * k), c + Vector2(0.42 * k, -0.52 * k),
				col, maxf(k * 0.30, 2.6), true)
			ci.draw_circle(c + Vector2(-0.52 * k, 0.60 * k), k * 0.22, col)
			for i in range(4):
				var a := -PI * 0.25 + i * PI * 0.25
				ci.draw_line(c + Vector2(0.44 * k, -0.56 * k),
					c + Vector2(0.44 * k + cos(a) * 0.42 * k, -0.56 * k + sin(a) * 0.42 * k),
					Color(col.r, col.g, col.b, 0.85), maxf(k * 0.09, 1.1), true)
		"dual_guns":  # 马可波罗：双枪
			ci.draw_line(c + Vector2(-0.62 * k, -0.58 * k), c + Vector2(0.30 * k, 0.34 * k),
				col, maxf(k * 0.22, 2.0), true)
			ci.draw_line(c + Vector2(0.62 * k, -0.58 * k), c + Vector2(-0.30 * k, 0.34 * k),
				col, maxf(k * 0.22, 2.0), true)
			ci.draw_circle(c + Vector2(-0.66 * k, -0.66 * k), k * 0.14,
				Color(col.r, col.g, col.b, 0.9))
			ci.draw_circle(c + Vector2(0.66 * k, -0.66 * k), k * 0.14,
				Color(col.r, col.g, col.b, 0.9))
			ci.draw_circle(c, k * 0.16, Color(1, 1, 1, minf(col.a, 0.85)))
		"serpent_spear":  # 张飞：蛇矛
			var pts := PackedVector2Array()
			for i in range(9):
				var t := float(i) / 8.0
				pts.append(c + Vector2(sin(t * TAU * 1.1) * 0.16 * k - 0.10 * k,
					(0.92 - t * 1.84) * k))
			ci.draw_polyline(pts, col, maxf(k * 0.13, 1.3), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.10 * k, -1.02 * k), c + Vector2(0.30 * k, -0.60 * k),
				c + Vector2(-0.10 * k, -0.52 * k)]), col)
			ci.draw_circle(c + Vector2(0.34 * k, 0.60 * k), k * 0.18,
				Color(col.r, col.g, col.b, 0.85))
		"bomb":  # 沈梦溪：猫咪炸弹
			ci.draw_circle(c + Vector2(0, 0.16 * k), k * 0.66, col)
			ci.draw_line(c + Vector2(0.20 * k, -0.48 * k), c + Vector2(0.52 * k, -0.90 * k),
				Color(col.r, col.g, col.b, 0.9), maxf(k * 0.12, 1.2), true)
			for i in range(2):
				var sx := -0.42 * k + i * 0.84 * k
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(sx, -0.42 * k), c + Vector2(sx + 0.26 * k, -0.86 * k),
					c + Vector2(sx + 0.34 * k, -0.40 * k)]), col)
			ci.draw_circle(c + Vector2(-0.22 * k, 0.10 * k), k * 0.09, Color(0.03, 0.04, 0.07, 0.9))
			ci.draw_circle(c + Vector2(0.22 * k, 0.10 * k), k * 0.09, Color(0.03, 0.04, 0.07, 0.9))
		"gear":  # 刘禅：机关齿轮
			ci.draw_arc(c, k * 0.66, 0, TAU, 22, col, maxf(k * 0.14, 1.4), true)
			for i in range(8):
				var a := i * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.66,
					c + Vector2(cos(a), sin(a)) * k * 0.96, col, maxf(k * 0.12, 1.2), true)
			ci.draw_circle(c, k * 0.22, col)
		"staff":  # 孙悟空：金箍棒
			ci.draw_line(c + Vector2(0, -0.96 * k), c + Vector2(0, 0.96 * k), col,
				maxf(k * 0.20, 1.8), true)
			for i in range(2):
				var y := (-0.96 + i * 1.92) * k
				ci.draw_arc(c + Vector2(0, y), k * 0.24, 0, TAU, 14, col, maxf(k * 0.13, 1.2), true)
		"wing":  # 英睿：羽翼 + 核心
			for i in range(2):
				var s := -1.0 if i == 0 else 1.0
				for j in range(3):
					ci.draw_line(c + Vector2(s * 0.16 * k, 0.10 * k),
						c + Vector2(s * (0.62 + j * 0.16) * k, -0.72 * k + j * 0.34 * k),
						Color(col.r, col.g, col.b, 0.9 - j * 0.18), maxf(k * 0.10, 1.1), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.34 * k), c + Vector2(0.22 * k, 0.06 * k),
				c + Vector2(0, 0.46 * k), c + Vector2(-0.22 * k, 0.06 * k)]), col)
		"fireball":  # 安琪拉：爆裂火球
			ci.draw_circle(c + Vector2(0, 0.12 * k), k * 0.62, col)
			ci.draw_circle(c + Vector2(0, 0.12 * k), k * 0.30, Color(1, 1, 1, minf(col.a, 0.55)))
			for i in range(3):
				var a := -PI * 0.75 + i * PI * 0.5
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.72,
					c + Vector2(cos(a), sin(a)) * k * 1.02, Color(col.r, col.g, col.b, 0.85),
					maxf(k * 0.10, 1.1), true)
		"fox_charm":  # 妲己：狐耳 + 心形尾
			for i in range(2):
				var s := -1.0 if i == 0 else 1.0
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(s * 0.34 * k, -0.34 * k), c + Vector2(s * 0.62 * k, -1.0 * k),
					c + Vector2(s * 0.80 * k, -0.28 * k)]), col)
			ci.draw_circle(c + Vector2(-0.18 * k, 0.30 * k), k * 0.22, col)
			ci.draw_circle(c + Vector2(0.18 * k, 0.30 * k), k * 0.22, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.38 * k, 0.42 * k), c + Vector2(0.38 * k, 0.42 * k),
				c + Vector2(0, 0.98 * k)]), col)
		"blossom":  # 小乔：桃花
			for i in range(5):
				var a := -PI * 0.5 + i * TAU / 5.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 0.52, k * 0.30, col)
			ci.draw_circle(c, k * 0.22, Color(1.0, 0.95, 0.78, minf(col.a, 0.95)))
		"automaton":  # 鲁班七号：机关木偶
			ci.draw_style_box(UiKit.flat(0.92, int(k * 0.28), int(maxf(k * 0.12, 2.0)), col,
				Color(0.04, 0.05, 0.08, 0.92), 0.0, 0.0),
				Rect2(c - Vector2(0.62 * k, 0.42 * k), Vector2(1.24 * k, 1.10 * k)))
			ci.draw_line(c + Vector2(0, -0.42 * k), c + Vector2(0, -0.92 * k), col,
				maxf(k * 0.13, 1.2), true)
			ci.draw_circle(c + Vector2(-0.26 * k, 0.10 * k), k * 0.12, Color(0.03, 0.04, 0.07, 0.9))
			ci.draw_circle(c + Vector2(0.26 * k, 0.10 * k), k * 0.12, Color(0.03, 0.04, 0.07, 0.9))
			ci.draw_line(c + Vector2(-0.24 * k, 0.48 * k), c + Vector2(0.24 * k, 0.48 * k),
				Color(0.03, 0.04, 0.07, 0.9), maxf(k * 0.10, 1.1), true)
		"eye_blade":  # 夏侯惇：独眼 + 鬼刀
			ci.draw_line(c + Vector2(-0.66 * k, 0.82 * k), c + Vector2(0.52 * k, -0.86 * k),
				col, maxf(k * 0.15, 1.4), true)
			ci.draw_arc(c + Vector2(-0.22 * k, 0.10 * k), k * 0.40, PI * 0.15, PI * 0.85,
				12, col, maxf(k * 0.13, 1.2), true)
			ci.draw_circle(c + Vector2(-0.22 * k, 0.10 * k), k * 0.14, col)
		"sun_bow":  # 后羿：落日神弓
			ci.draw_arc(c + Vector2(-0.16 * k, 0), k * 0.92, -PI * 0.5, PI * 0.5,
				18, col, maxf(k * 0.13, 1.2), true)
			ci.draw_line(c + Vector2(-0.16 * k, -0.92 * k), c + Vector2(-0.16 * k, 0.92 * k),
				Color(col.r, col.g, col.b, 0.85), maxf(k * 0.07, 1.0), true)
			for i in range(8):
				var a := i * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.34,
					c + Vector2(cos(a), sin(a)) * k * 0.56, Color(1, 0.95, 0.70, 0.9),
					maxf(k * 0.08, 1.0), true)
		"shuriken":  # 李元芳：四角飞镖
			for i in range(4):
				var a := i * TAU / 4.0
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(cos(a), sin(a)) * k * 0.98,
					c + Vector2(cos(a + 0.9), sin(a + 0.9)) * k * 0.34,
					c + Vector2(cos(a + 1.8), sin(a + 1.8)) * k * 0.20]), col)
			ci.draw_circle(c, k * 0.16, Color(0.03, 0.04, 0.07, 0.9))
		"core":  # 元流之子：流形核心
			ci.draw_circle(c, k * 0.46, col)
			ci.draw_circle(c, k * 0.22, Color(1, 1, 1, minf(col.a, 0.75)))
			for i in range(2):
				ci.draw_arc(c, k * (0.72 + i * 0.22), -PI * 0.85 + i * 0.5, PI * 0.15 + i * 0.5,
					14, Color(col.r, col.g, col.b, 0.85 - i * 0.25), maxf(k * 0.09, 1.0), true)
		"mountain_axe":  # 大禹：山河 + 开山斧
			for i in range(2):
				var dx := -0.36 * k + i * 0.72 * k
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(dx - 0.30 * k, 0.66 * k), c + Vector2(dx, -0.10 * k),
					c + Vector2(dx + 0.30 * k, 0.66 * k)]), col)
			ci.draw_line(c + Vector2(0.10 * k, -0.95 * k), c + Vector2(0.10 * k, 0.20 * k),
				col, maxf(k * 0.14, 1.3), true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.10 * k, -0.95 * k), c + Vector2(0.64 * k, -0.64 * k),
				c + Vector2(0.10 * k, -0.40 * k)]), col)
		"snowflake":  # 王昭君：凛冬冰晶
			for i in range(3):
				var a := i * PI / 3.0
				ci.draw_line(c - Vector2(cos(a), sin(a)) * k * 0.92,
					c + Vector2(cos(a), sin(a)) * k * 0.92, col, maxf(k * 0.10, 1.1), true)
				for j in range(2):
					var s := -1.0 if j == 0 else 1.0
					var pt := c + Vector2(cos(a), sin(a)) * k * 0.58 * s
					ci.draw_line(pt, pt + Vector2(cos(a + 1.0), sin(a + 1.0)) * k * 0.26,
						col, maxf(k * 0.09, 1.0), true)
			ci.draw_circle(c, k * 0.14, Color(1, 1, 1, minf(col.a, 0.9)))
