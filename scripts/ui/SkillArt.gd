extends RefCounted
## 技能按钮图标：纯矢量程序化绘制（项目无美术资源）。
## 用法：const SkillArt = preload("res://scripts/ui/SkillArt.gd")，再调用其 static 方法。
## 每个技能按「技能名关键词 → 纹样」匹配，匹配不到按技能 type 兜底，
## 配色取英雄元素色（Vfx.color_for_hero），因此 51 个英雄技能各有可辨识的图形。

## 关键词 → 纹样（靠前者优先）
const KEYWORDS := [
	[["火", "焰", "炎", "焚", "燃", "爆"], "flame"],
	[["冰", "霜", "寒", "雪", "冻"], "ice"],
	[["雷", "电", "霆", "闪"], "bolt"],
	[["风", "飓", "旋", "卷"], "wind"],
	[["箭", "矢", "矛", "枪", "针"], "arrow"],
	[["剑", "刃", "斩", "刀", "锋", "刺"], "blade"],
	[["盾", "护", "壁", "甲", "披"], "shield"],
	[["星", "辰", "陨"], "star"],
	[["月"], "moon"],
	[["阳", "日", "耀", "光", "辉", "圣"], "sun"],
	[["毒", "腐", "疫", "蚀"], "poison"],
	[["愈", "疗", "回", "奶", "生", "血"], "heal"],
	[["锁", "链", "缚", "禁", "绳"], "chain"],
	[["阵", "域", "圈", "场", "区", "印", "坛"], "trap"],
	[["门", "空间", "瞬", "移", "传送", "跃"], "portal"],
	[["拳", "掌", "踢", "爪", "击"], "punch"],
	[["锤", "棍", "棒", "杖"], "hammer"],
	[["扇"], "fan"],
	[["书", "卷", "符", "典", "牌"], "book"],
	[["音", "歌", "咏", "琴"], "music"],
	[["眼", "瞳", "视", "窥"], "eye"],
	[["魂", "灵", "幽", "鬼", "影", "冥"], "shadow"],
	[["花", "藤", "木", "林", "叶", "种"], "leaf"],
	[["时", "钟", "沙"], "clock"],
	[["球", "弹", "珠"], "orb"],
]

## 技能纹样名（供外部探测/调试）
static func motif_for(skill, slot: int) -> String:
	if skill == null:
		return ["lock", "aoe", "beam", "dash", "shield"][clampi(slot, 0, 4)]
	var n := str(skill.skill_name)
	for entry in KEYWORDS:
		for kw in entry[0]:
			if n.find(str(kw)) >= 0:
				return str(entry[1])
	match int(skill.type):
		0: return "lock"
		1: return "aoe"
		3: return "beam"
		4: return "dash"
		6: return "shield"
	return "orb"

## 画按钮底盘 + 纹样。learned=false 压暗，ready=false 加冷灰罩
static func draw_bg(ci: CanvasItem, c: Vector2, r: float, hero_name: String, skill, slot: int,
		learned: bool, ready: bool) -> void:
	var base: Color = Vfx.color_for_hero(hero_name) if hero_name != "" else Color(0.42, 0.60, 0.88)
	# 同英雄 1/2/3 技能用副元素色偏色，避免三格颜色一模一样
	if hero_name != "" and slot > 0:
		base = base.lerp(Vfx.color2_for_hero(hero_name), 0.16 * clampi(slot, 0, 3))
	var deep := base.darkened(0.80)
	ci.draw_circle(c, r, deep)
	# 径向高光：多层低 alpha 圆叠加，避免硬边色环
	for i in range(12):
		var t := 1.0 - float(i) / 11.0
		ci.draw_circle(c, r * 0.97 * t, Color(base.r, base.g, base.b, 0.055))
	# 环境弧光 + 底部压暗，保证技能名/伤害读数可读
	ci.draw_arc(c, r * 0.88, -PI * 0.95, -PI * 0.15, 22, Color(1, 1, 1, 0.12), maxf(r * 0.09, 1.5), true)
	ci.draw_circle(c + Vector2(0, r * 0.62), r * 0.62, Color(0, 0, 0, 0.16))
	# 纹样（外发光 + 主色 + 高光芯）
	var m := motif_for(skill, slot)
	var k := r * 0.46
	var col := base.lightened(0.42)
	_glyph(ci, c, k * 1.26, m, Color(base.r, base.g, base.b, 0.20))
	_glyph(ci, c, k, m, col)
	_glyph(ci, c, k * 0.66, m, Color(1, 1, 1, 0.22))
	# 槽位标记：1/2/3 技能 = 底部 1/2/3 段短弧，同纹样技能也能一眼区分
	var marks := clampi(slot + 1, 1, 4)
	for i in range(marks):
		var a := -PI * 0.5 + (float(i) - (marks - 1) * 0.5) * 0.20
		ci.draw_arc(c, r * 0.74, a - 0.07, a + 0.07, 4, Color(1, 1, 1, 0.34),
			maxf(r * 0.045, 1.1), true)
	# 外圈细边
	ci.draw_arc(c, r * 0.98, 0, TAU, 40, Color(1, 1, 1, 0.16), maxf(r * 0.028, 1.2), true)
	if not learned:
		ci.draw_circle(c, r, Color(0.02, 0.02, 0.03, 0.62))
	elif not ready:
		ci.draw_circle(c, r, Color(0.02, 0.03, 0.06, 0.42))

# ---------------- 纹样绘制：k 为单位半径，坐标一律相对中心 c ----------------
static func _glyph(ci: CanvasItem, c: Vector2, k: float, name: String, col: Color) -> void:
	if col.a <= 0.01:
		return
	match name:
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -1.05 * k), c + Vector2(0.72 * k, -0.10 * k),
				c + Vector2(0.34 * k, 0.95 * k), c + Vector2(-0.34 * k, 0.95 * k),
				c + Vector2(-0.72 * k, -0.10 * k)]), col)
		"ice":
			var pts := PackedVector2Array()
			for i in range(12):
				var a := -PI / 2 + i * TAU / 12.0
				var rr := k * (1.05 if i % 2 == 0 else 0.34)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.30 * k, -1.0 * k), c + Vector2(-0.58 * k, 0.16 * k),
				c + Vector2(-0.04 * k, 0.16 * k), c + Vector2(-0.24 * k, 1.0 * k),
				c + Vector2(0.66 * k, -0.20 * k), c + Vector2(0.10 * k, -0.20 * k)]), col)
		"wind":
			for i in range(3):
				ci.draw_arc(c + Vector2(0, (i - 1) * 0.52 * k), 0.66 * k, -PI * 0.95, PI * 0.35,
					14, col, maxf(k * 0.16, 1.5), true)
		"arrow":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -1.0 * k), c + Vector2(0.52 * k, -0.10 * k), c + Vector2(0, -0.10 * k)]), col)
			ci.draw_line(c + Vector2(0, -0.30 * k), c + Vector2(0, 1.0 * k), col, maxf(k * 0.18, 1.5), true)
			ci.draw_line(c + Vector2(-0.40 * k, 0.62 * k), c + Vector2(0, 0.92 * k), col, maxf(k * 0.14, 1.2), true)
			ci.draw_line(c + Vector2(0.40 * k, 0.62 * k), c + Vector2(0, 0.92 * k), col, maxf(k * 0.14, 1.2), true)
		"blade":
			ci.draw_line(c + Vector2(0.52 * k, -0.92 * k), c + Vector2(-0.42 * k, 0.42 * k), col, maxf(k * 0.26, 2.0), true)
			ci.draw_line(c + Vector2(-0.62 * k, 0.02 * k), c + Vector2(0.08 * k, 0.70 * k), col, maxf(k * 0.20, 1.8), true)
			ci.draw_circle(c + Vector2(-0.62 * k, 0.72 * k), k * 0.16, col)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.78 * k, -0.85 * k), c + Vector2(0.78 * k, -0.85 * k),
				c + Vector2(0.66 * k, 0.32 * k), c + Vector2(0, 1.0 * k),
				c + Vector2(-0.66 * k, 0.32 * k)]), col)
		"star":
			var pts := PackedVector2Array()
			for i in range(10):
				var a := -PI / 2 + i * TAU / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (k * (1.06 if i % 2 == 0 else 0.42)))
			ci.draw_colored_polygon(pts, col)
		"moon":
			ci.draw_circle(c, k * 0.92, col)
			ci.draw_circle(c + Vector2(0.44 * k, -0.22 * k), k * 0.80, Color(0.02, 0.03, 0.06, 0.9))
		"sun":
			ci.draw_circle(c, k * 0.52, col)
			for i in range(8):
				var a := i * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.70,
					c + Vector2(cos(a), sin(a)) * k * 1.02, col, maxf(k * 0.13, 1.2), true)
		"poison":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -1.0 * k), c + Vector2(0.58 * k, 0.10 * k),
				c + Vector2(0, 0.98 * k), c + Vector2(-0.58 * k, 0.10 * k)]), col)
			ci.draw_circle(c + Vector2(0.72 * k, -0.52 * k), k * 0.18, col)
			ci.draw_circle(c + Vector2(-0.76 * k, -0.30 * k), k * 0.12, col)
		"heal":
			ci.draw_rect(Rect2(c + Vector2(-0.26 * k, -0.92 * k), Vector2(0.52 * k, 1.84 * k)), col)
			ci.draw_rect(Rect2(c + Vector2(-0.92 * k, -0.26 * k), Vector2(1.84 * k, 0.52 * k)), col)
		"chain":
			for i in range(3):
				var o := c + Vector2(0, (i - 1) * 0.72 * k)
				ci.draw_arc(o, k * 0.40, 0, TAU, 16, col, maxf(k * 0.14, 1.4), true)
		"trap":
			var pts := PackedVector2Array()
			for i in range(16):
				var a := i * TAU / 16.0
				pts.append(c + Vector2(cos(a), sin(a)) * (k * (1.02 if i % 2 == 0 else 0.74)))
			ci.draw_polyline(pts, col, maxf(k * 0.10, 1.2), true)
			ci.draw_circle(c, k * 0.26, col)
		"portal":
			ci.draw_arc(c, k * 0.88, 0, TAU, 24, col, maxf(k * 0.16, 1.6), true)
			ci.draw_arc(c, k * 0.46, 0, TAU, 20, col, maxf(k * 0.14, 1.4), true)
			ci.draw_line(c + Vector2(-0.92 * k, 0), c + Vector2(-0.52 * k, 0), col, maxf(k * 0.12, 1.2), true)
			ci.draw_line(c + Vector2(0.92 * k, 0), c + Vector2(0.52 * k, 0), col, maxf(k * 0.12, 1.2), true)
		"punch":
			ci.draw_circle(c, k * 0.66, col)
			ci.draw_line(c + Vector2(-0.96 * k, -0.24 * k), c + Vector2(-0.56 * k, -0.24 * k), col, maxf(k * 0.16, 1.5), true)
			ci.draw_line(c + Vector2(-0.84 * k, 0.06 * k), c + Vector2(-0.50 * k, 0.24 * k), col, maxf(k * 0.14, 1.3), true)
		"hammer":
			ci.draw_rect(Rect2(c + Vector2(-0.72 * k, -0.92 * k), Vector2(1.44 * k, 0.62 * k)), col)
			ci.draw_line(c + Vector2(0, -0.24 * k), c + Vector2(0, 1.0 * k), col, maxf(k * 0.22, 2.0), true)
		"fan":
			var pts := PackedVector2Array([c])
			for i in range(9):
				var a := -PI * 0.42 + i * PI * 0.84 / 8.0
				pts.append(c + Vector2(sin(a), -cos(a)) * k * 1.02)
			ci.draw_colored_polygon(pts, col)
		"book":
			ci.draw_rect(Rect2(c + Vector2(-0.86 * k, -0.76 * k), Vector2(1.72 * k, 1.52 * k)), col)
			ci.draw_line(c + Vector2(0, -0.76 * k), c + Vector2(0, 0.76 * k), Color(0.02, 0.03, 0.06, 0.9), maxf(k * 0.10, 1.2), true)
		"music":
			ci.draw_circle(c + Vector2(-0.30 * k, 0.62 * k), k * 0.30, col)
			ci.draw_line(c + Vector2(0, 0.62 * k), c + Vector2(0, -0.86 * k), col, maxf(k * 0.14, 1.4), true)
			ci.draw_line(c + Vector2(0, -0.86 * k), c + Vector2(0.62 * k, -0.62 * k), col, maxf(k * 0.14, 1.4), true)
		"eye":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.98 * k, 0), c + Vector2(0, -0.68 * k), c + Vector2(0.98 * k, 0),
				c + Vector2(0, 0.68 * k)]), col)
			ci.draw_circle(c, k * 0.30, Color(0.02, 0.03, 0.06, 0.92))
		"shadow":
			for i in range(3):
				var o := c + Vector2((i - 1) * 0.56 * k, 0)
				ci.draw_colored_polygon(PackedVector2Array([
					o + Vector2(0, -0.92 * k), o + Vector2(0.34 * k, 0.10 * k),
					o + Vector2(0, 0.92 * k), o + Vector2(-0.34 * k, 0.10 * k)]), col)
		"leaf":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -1.0 * k), c + Vector2(0.62 * k, -0.10 * k),
				c + Vector2(0, 1.0 * k), c + Vector2(-0.62 * k, -0.10 * k)]), col)
			ci.draw_line(c + Vector2(0, -0.86 * k), c + Vector2(0, 0.86 * k), Color(0.02, 0.03, 0.06, 0.8), maxf(k * 0.10, 1.0), true)
		"clock":
			ci.draw_arc(c, k * 0.92, 0, TAU, 24, col, maxf(k * 0.13, 1.3), true)
			ci.draw_line(c, c + Vector2(0, -0.60 * k), col, maxf(k * 0.12, 1.2), true)
			ci.draw_line(c, c + Vector2(0.44 * k, 0.16 * k), col, maxf(k * 0.12, 1.2), true)
		"lock":
			ci.draw_arc(c, k * 0.86, 0, TAU, 24, col, maxf(k * 0.11, 1.2), true)
			ci.draw_circle(c, k * 0.22, col)
			for i in range(4):
				var a := i * PI / 2.0 + PI / 4.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * k * 0.62, c + d * k * 1.05, col, maxf(k * 0.12, 1.2), true)
		"aoe":
			ci.draw_arc(c, k * 1.00, 0, TAU, 26, col, maxf(k * 0.10, 1.2), true)
			ci.draw_arc(c, k * 0.62, 0, TAU, 22, col, maxf(k * 0.10, 1.2), true)
			ci.draw_circle(c, k * 0.20, col)
		"beam":
			for i in range(3):
				var x := (i - 1) * 0.52 * k
				ci.draw_line(c + Vector2(x, -0.95 * k), c + Vector2(x, 0.95 * k), col, maxf(k * 0.16, 1.5), true)
			ci.draw_circle(c, k * 0.24, Color(1, 1, 1, minf(col.a, 0.85)))
		"dash":
			for i in range(3):
				var x := (i - 1) * 0.56 * k
				ci.draw_line(c + Vector2(x - 0.30 * k, -0.62 * k), c + Vector2(x + 0.26 * k, 0),
					col, maxf(k * 0.16, 1.6), true)
				ci.draw_line(c + Vector2(x + 0.26 * k, 0), c + Vector2(x - 0.30 * k, 0.62 * k),
					col, maxf(k * 0.16, 1.6), true)
		_:
			ci.draw_arc(c, k * 0.92, 0, TAU, 24, col, maxf(k * 0.14, 1.4), true)
			ci.draw_circle(c, k * 0.34, col)
