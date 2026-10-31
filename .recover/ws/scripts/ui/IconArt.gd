extends RefCounted
## 通用功能图标（推塔/小兵/回城/恢复/召唤师）：纯矢量程序化，按钮上统一走 IconArt.draw_icon。
## 颜色规则：推塔·小兵=白；回城=蓝；恢复=绿；召唤师按技能各自固定色。英雄技能不用本文件（走 SkillArt 英雄色）。

const COLORS := {
	"tower": Color(0.96, 0.97, 1.0),
	"minion": Color(0.96, 0.97, 1.0),
	"recall": Color(0.36, 0.66, 1.0),
	"recover": Color(0.40, 0.95, 0.55),
	"flash": Color(1.0, 0.86, 0.36),
	"sprint": Color(1.0, 0.72, 0.30),
	"heal": Color(0.45, 0.96, 0.60),
	"cleanse": Color(0.45, 0.92, 0.95),
	"smite": Color(1.0, 0.60, 0.25),
	"execute": Color(1.0, 0.35, 0.32),
	"stun": Color(0.72, 0.52, 1.0),
	"teleport": Color(0.76, 0.56, 1.0),
	"shield": Color(0.62, 0.86, 1.0),
	"summoner": Color(0.80, 0.84, 0.95),
}

## 召唤师技能名 → 图标类型（不在表内的一律通用圆环）
const SUMMONER_KIND := {
	"闪现": "flash",
	"疾跑": "sprint",
	"治疗术": "heal", "治疗": "heal",
	"净化": "cleanse",
	"惩击": "smite",
	"终结": "execute", "斩杀": "execute",
	"眩晕": "stun", "晕眩": "stun",
	"传送": "teleport",
	"护盾": "shield", "加护": "shield",
}

static func kind_for_summoner(skill_name: String) -> String:
	if SUMMONER_KIND.has(skill_name):
		return SUMMONER_KIND[skill_name]
	for k in SUMMONER_KIND.keys():
		if skill_name.find(k) >= 0:
			return SUMMONER_KIND[k]
	return "summoner"

static func color_of(kind: String) -> Color:
	return COLORS.get(kind, COLORS["summoner"])

## 在圆形按钮里画图标：深色底盘 + 元素色光环 + 白色/同色线稿图形；dim=不可用（压暗）
static func draw_icon(ci: CanvasItem, center: Vector2, radius: float, kind: String, dim := false) -> void:
	var col := color_of(kind)
	if dim:
		col = col.darkened(0.45)
	ci.draw_circle(center, radius, Color(0.05, 0.06, 0.09, 0.90 if not dim else 0.94))
	for i in range(8):
		var t := 1.0 - float(i) / 7.0
		ci.draw_circle(center, radius * 0.92 * t, Color(col.r, col.g, col.b, 0.035))
	# 顶部玻璃高光 + 底部元素色反光（与自绘触控键同一套质感）
	ci.draw_arc(center - Vector2(0, radius * 0.18), radius * 0.76, -PI * 0.92, -PI * 0.08,
		22, Color(1, 1, 1, 0.04 if dim else 0.11), maxf(1.5, radius * 0.045), true)
	ci.draw_arc(center + Vector2(0, radius * 0.12), radius * 0.80, PI * 0.16, PI * 0.84,
		20, Color(col.r, col.g, col.b, 0.05 if dim else 0.10), maxf(1.2, radius * 0.025), true)
	ci.draw_arc(center, radius - 1.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.75 if not dim else 0.35),
		maxf(radius * 0.05, 1.5), true)
	var k := radius * 0.60
	_motif(ci, center, k, kind, col)
	if dim:
		ci.draw_circle(center, radius, Color(0.02, 0.02, 0.03, 0.42))

static func _motif(ci: CanvasItem, c: Vector2, k: float, kind: String, col: Color) -> void:
	var w := maxf(k * 0.16, 1.6)
	match kind:
		"tower":  # 推塔：三层防御塔 + 底部波纹
			for i in range(3):
				var ww := k * (0.86 - i * 0.20)
				var y := c.y + (0.60 - i * 0.42) * k
				ci.draw_rect(Rect2(c.x - ww * 0.5, y - 0.30 * k, ww, 0.30 * k), col)
			ci.draw_line(c + Vector2(0, -0.30 * k), c + Vector2(0, -0.72 * k), col, w, true)
			ci.draw_circle(c + Vector2(0, -0.86 * k), k * 0.18, col)
			ci.draw_arc(c + Vector2(0, 0.76 * k), k * 0.62, PI * 0.15, PI * 0.85, 12, col, w * 0.8, true)
		"minion":  # 小兵：头盔 + 短剑
			ci.draw_arc(c + Vector2(-0.18 * k, -0.10 * k), k * 0.44, PI * 0.05, PI * 0.95, 14, col, w, true)
			ci.draw_rect(Rect2(c.x - 0.60 * k, c.y - 0.08 * k, 0.84 * k, 0.62 * k), col)
			ci.draw_line(c + Vector2(0.44 * k, 0.70 * k), c + Vector2(0.44 * k, -0.10 * k), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.44 * k, -0.86 * k), c + Vector2(0.70 * k, -0.36 * k),
				c + Vector2(0.18 * k, -0.36 * k)]), col)
		"recall":  # 回城：传送门 + 下坠箭头（蓝）
			ci.draw_arc(c, k * 0.80, PI * 0.10, PI * 0.90, 14, col, w, true)
			ci.draw_line(c + Vector2(0, -0.62 * k), c + Vector2(0, 0.42 * k), col, w * 1.3, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.34 * k, 0.34 * k), c + Vector2(0.34 * k, 0.34 * k),
				c + Vector2(0, 0.86 * k)]), col)
			for i in range(2):
				ci.draw_arc(c + Vector2(0, 0.86 * k), k * (0.42 + i * 0.26), PI * 1.05, PI * 1.95,
					10, Color(col.r, col.g, col.b, 0.6 - i * 0.22), w * 0.7, true)
		"recover":  # 恢复：心形 + 十字（绿）
			ci.draw_circle(c + Vector2(-0.26 * k, -0.16 * k), k * 0.30, col)
			ci.draw_circle(c + Vector2(0.26 * k, -0.16 * k), k * 0.30, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.54 * k, 0.0), c + Vector2(0.54 * k, 0.0),
				c + Vector2(0, 0.80 * k)]), col)
			ci.draw_rect(Rect2(c.x - 0.10 * k, c.y - 0.10 * k, 0.20 * k, 0.44 * k),
				Color(0.96, 1.0, 0.96, 0.95))
			ci.draw_rect(Rect2(c.x - 0.28 * k, c.y + 0.04 * k, 0.56 * k, 0.20 * k),
				Color(0.96, 1.0, 0.96, 0.95))
		"flash":  # 闪现：折线跳闪 + 星芒
			for i in range(2):
				var o := Vector2(-0.30 * k + i * 0.60 * k, 0.30 * k)
				var s := -1.0 if i == 0 else 1.0
				ci.draw_polyline(PackedVector2Array([
					o + Vector2(s * 0.52 * k, 0.34 * k), o + Vector2(-s * 0.16 * k, 0.0),
					o + Vector2(s * 0.40 * k, -0.16 * k), o + Vector2(-s * 0.30 * k, -0.62 * k)]),
					col, w, true)
			for i in range(4):
				var a := i * TAU / 4.0 + 0.4
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.30,
					c + Vector2(cos(a), sin(a)) * k * 0.74, col, w * 0.9, true)
		"sprint":  # 疾跑：双加速箭头
			for i in range(2):
				var y := (-0.42 + i * 0.62) * k
				ci.draw_polyline(PackedVector2Array([
					c + Vector2(-0.62 * k, y + 0.26 * k), c + Vector2(0, y - 0.10 * k),
					c + Vector2(0.62 * k, y + 0.26 * k)]), col, w * 1.2, true)
		"heal":  # 治疗：十字 + 光环
			ci.draw_arc(c, k * 0.86, 0, TAU, 26, Color(col.r, col.g, col.b, 0.7), w * 0.8, true)
			ci.draw_rect(Rect2(c.x - 0.18 * k, c.y - 0.62 * k, 0.36 * k, 1.24 * k), col)
			ci.draw_rect(Rect2(c.x - 0.62 * k, c.y - 0.18 * k, 1.24 * k, 0.36 * k), col)
		"cleanse":  # 净化：盾 + 亮星
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.52 * k, -0.56 * k), c + Vector2(0, -0.80 * k),
				c + Vector2(0.52 * k, -0.56 * k), c + Vector2(0.52 * k, 0.16 * k),
				c + Vector2(0, 0.82 * k), c + Vector2(-0.52 * k, 0.16 * k),
				c + Vector2(-0.52 * k, -0.56 * k)]), col, w, true)
			for i in range(4):
				var a := i * TAU / 4.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.14,
					c + Vector2(cos(a), sin(a)) * k * 0.40, col, w * 0.9, true)
		"smite":  # 惩击：闪电
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.18 * k, -0.92 * k), c + Vector2(-0.46 * k, 0.14 * k),
				c + Vector2(-0.06 * k, 0.14 * k), c + Vector2(-0.26 * k, 0.92 * k),
				c + Vector2(0.48 * k, -0.18 * k), c + Vector2(0.06 * k, -0.18 * k)]), col)
		"execute":  # 终结：断头刃 + 下箭头
			ci.draw_line(c + Vector2(-0.58 * k, -0.62 * k), c + Vector2(0.58 * k, 0.30 * k), col, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.30 * k, 0.36 * k), c + Vector2(0.30 * k, 0.36 * k),
				c + Vector2(0, 0.92 * k)]), col)
		"stun":  # 眩晕：螺旋
			var pts := PackedVector2Array()
			for i in range(16):
				var t := float(i) / 15.0
				var a := t * TAU * 1.7
				pts.append(c + Vector2(cos(a), sin(a)) * k * (0.16 + 0.72 * t))
			ci.draw_polyline(pts, col, w, true)
		"teleport":  # 传送：双向环
			for i in range(2):
				ci.draw_arc(c, k * (0.52 + i * 0.34), -PI * 0.85 + i * PI,
					PI * 0.85 + i * PI, 14, col, w * 1.1, true)
			ci.draw_circle(c, k * 0.20, col)
		"shield":  # 护盾：盾牌
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.58 * k, -0.52 * k), c + Vector2(0, -0.82 * k),
				c + Vector2(0.58 * k, -0.52 * k), c + Vector2(0.58 * k, 0.18 * k),
				c + Vector2(0, 0.90 * k), c + Vector2(-0.58 * k, 0.18 * k),
				c + Vector2(-0.58 * k, -0.52 * k)]), col, w * 1.1, true)
			ci.draw_line(c + Vector2(0, -0.40 * k), c + Vector2(0, 0.44 * k), col, w * 0.8, true)
		_:  # 通用召唤
			ci.draw_arc(c, k * 0.62, 0, TAU, 24, col, w * 1.1, true)
			for i in range(3):
				var a := -PI * 0.5 + i * TAU / 3.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 0.94, k * 0.16, col)
