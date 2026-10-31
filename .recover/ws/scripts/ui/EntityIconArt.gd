extends RefCounted
## 战报 / 目标面板通用实体图标：英雄头像、防御塔、小兵、野怪。
## 无美术资源，全部用程序化矢量绘制；名称同时负责英文 display_name → 中文短名。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")

const TOWER := {
	"outer": {"kind": "tower", "key": "outer", "label": "外塔"},
	"inner": {"kind": "tower", "key": "inner", "label": "二塔"},
	"high": {"kind": "tower", "key": "high", "label": "高地塔"},
	"crystal": {"kind": "tower", "key": "crystal", "label": "水晶"},
}
const MINION := {
	"melee": {"kind": "minion", "key": "melee", "label": "近战兵"},
	"ranged": {"kind": "minion", "key": "ranged", "label": "远程兵"},
	"siege": {"kind": "minion", "key": "siege", "label": "攻城车"},
	"super": {"kind": "minion", "key": "super", "label": "超级兵"},
	"dragon": {"kind": "minion", "key": "dragon", "label": "主宰先锋"},
	"storm": {"kind": "minion", "key": "storm", "label": "风暴先锋"},
	"shadow_dragon": {"kind": "minion", "key": "shadow_dragon", "label": "暗影先锋"},
}
const JUNGLE := {
	"暴君": {"kind": "jungle", "key": "tyrant", "label": "暴君"},
	"暗影暴君": {"kind": "jungle", "key": "shadow_tyrant", "label": "暗影暴君"},
	"主宰": {"kind": "jungle", "key": "dragon", "label": "主宰"},
	"先知主宰": {"kind": "jungle", "key": "dragon", "label": "先知主宰"},
	"风暴龙王": {"kind": "jungle", "key": "storm_dragon", "label": "风暴龙王"},
}

static func spec_for(raw_name: String) -> Dictionary:
	var n := raw_name.strip_edges()
	if n == "":
		return {}
	if HeroArt.MOTIF.has(n) or HeroArt.ACCENT.has(n):
		return {"kind": "hero", "key": n, "label": n}
	var low := n.to_lower()
	if TOWER.has(low):
		return TOWER[low].duplicate()
	if MINION.has(low):
		return MINION[low].duplicate()
	if JUNGLE.has(n):
		return JUNGLE[n].duplicate()
	match n:
		"外塔": return TOWER["outer"].duplicate()
		"二塔": return TOWER["inner"].duplicate()
		"高地塔", "防御塔": return TOWER["high"].duplicate()
		"水晶": return TOWER["crystal"].duplicate()
		"近战兵", "小兵": return MINION["melee"].duplicate()
		"远程兵": return MINION["ranged"].duplicate()
		"攻城车": return MINION["siege"].duplicate()
		"超级兵": return MINION["super"].duplicate()
		"主宰先锋": return MINION["dragon"].duplicate()
		"风暴先锋": return MINION["storm"].duplicate()
		"暗影先锋": return MINION["shadow_dragon"].duplicate()
	return {}

static func display_name(raw_name: String) -> String:
	var sp := spec_for(raw_name)
	return str(sp.get("label", raw_name)) if not sp.is_empty() else raw_name

static func draw(ci: CanvasItem, center: Vector2, radius: float, sp: Dictionary, team_col: Color) -> void:
	if sp.is_empty() or radius <= 1.0:
		return
	match str(sp.get("kind", "")):
		"hero":
			var mk := int(sp.get("mark", 0))
			if mk > 0:
				# 原初印记等级：头像略缩，环上符文画到图标满径（小图标也读得出等级）
				HeroArt.draw_portrait(ci, center, radius * 0.84, str(sp.get("key", "")), team_col)
				HeroArt.draw_primitive_mark(ci, center, radius, mk)
			else:
				HeroArt.draw_portrait(ci, center, radius, str(sp.get("key", "")), team_col)
		"tower":
			_icon_disc(ci, center, radius, team_col)
			_draw_tower(ci, center, radius, str(sp.get("key", "outer")), team_col)
		"minion":
			_icon_disc(ci, center, radius, team_col)
			_draw_minion(ci, center, radius, str(sp.get("key", "melee")), team_col)
		_:
			_icon_disc(ci, center, radius, team_col)
			_draw_jungle(ci, center, radius, str(sp.get("key", "tyrant")), team_col)

static func _icon_disc(ci: CanvasItem, c: Vector2, r: float, team_col: Color) -> void:
	ci.draw_circle(c, r, Color(0.03, 0.045, 0.075, 0.96))
	ci.draw_arc(c, r - maxf(1.0, r * 0.05), 0.0, TAU, 32,
		Color(team_col.r, team_col.g, team_col.b, 0.88), maxf(1.2, r * 0.075), true)

static func _draw_tower(ci: CanvasItem, c: Vector2, r: float, kind: String, col: Color) -> void:
	var dark := Color(0.055, 0.065, 0.09, 0.96)
	var lit := col.lightened(0.38)
	var h := r * 0.62
	match kind:
		"crystal":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := -PI * 0.5 + TAU * float(i) / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * h)
			ci.draw_colored_polygon(pts, dark)
			ci.draw_colored_polygon(PackedVector2Array([pts[5], pts[0], pts[1], pts[2], c + Vector2(0, h * 0.2)]), lit)
			ci.draw_colored_polygon(PackedVector2Array([pts[2], pts[3], pts[4], pts[5], c + Vector2(0, h * 0.2)]), col.darkened(0.30))
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.4)
			ci.draw_line(pts[2], c + Vector2(0, h * 0.75), Color(1, 1, 1, 0.35), 1.0)
		"high":
			var d := PackedVector2Array([c + Vector2(0, -h * 1.2), c + Vector2(h * 0.82, 0), c + Vector2(0, h), c + Vector2(-h * 0.82, 0)])
			ci.draw_colored_polygon(d, dark)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.95), c + Vector2(h * 0.52, 0), c + Vector2(0, h * 0.62), c + Vector2(-h * 0.52, 0)]), lit)
			ci.draw_polyline(d + PackedVector2Array([d[0]]), Color(1, 1, 1, 0.55), 1.2)
			ci.draw_line(c + Vector2(0, -h * 1.2), c + Vector2(0, -h * 1.7), Color(1, 0.86, 0.42), 1.6)
		"inner":
			var pts := PackedVector2Array()
			for i in range(8):
				var a := -PI * 0.5 + TAU * float(i) / 8.0 + PI / 8.0
				pts.append(c + Vector2(cos(a), sin(a)) * h)
			ci.draw_colored_polygon(pts, dark)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.62), c + Vector2(h * 0.62, 0), c + Vector2(0, h * 0.62), c + Vector2(-h * 0.62, 0)]), lit)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.55), 1.2)
		_:
			var body := Rect2(c - Vector2(h * 0.78, h), Vector2(h * 1.56, h * 2.0))
			ci.draw_rect(body, dark)
			ci.draw_rect(Rect2(c - Vector2(h * 0.60, h * 0.78), Vector2(h * 1.20, h * 1.56)), lit)
			ci.draw_rect(Rect2(c - Vector2(h * 0.78, h * 1.15), Vector2(h * 0.42, h * 0.55)), dark)
			ci.draw_rect(Rect2(c + Vector2(h * 0.36, -h * 1.15), Vector2(h * 0.42, h * 0.55)), dark)
			ci.draw_rect(body, Color(1, 1, 1, 0.5), false, 1.1)
			ci.draw_circle(c + Vector2(0, h * 0.1), maxf(1.2, h * 0.15), Color(1, 1, 1, 0.8))

static func _draw_minion(ci: CanvasItem, c: Vector2, r: float, kind: String, col: Color) -> void:
	var lit := col.lightened(0.36)
	var dark := Color(0.06, 0.075, 0.10, 0.96)
	var k := r * 0.62
	match kind:
		"super":
			var pts := PackedVector2Array()
			for i in range(6):
				var a := -PI * 0.5 + TAU * float(i) / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * k * 1.05)
			ci.draw_circle(c, k * 1.28, Color(1.0, 0.85, 0.35, 0.16))
			ci.draw_colored_polygon(pts, dark)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k * 0.72), c + Vector2(k * 0.62, 0), c + Vector2(0, k * 0.72), c + Vector2(-k * 0.62, 0)]), lit)
			ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 0.88, 0.40), 1.4)
			ci.draw_circle(c, k * 0.22, Color(1, 1, 1, 0.95))
		"siege":
			var d := PackedVector2Array([c + Vector2(0, -k), c + Vector2(k, 0), c + Vector2(0, k), c + Vector2(-k, 0)])
			ci.draw_colored_polygon(d, dark)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k * 0.62), c + Vector2(k * 0.62, 0), c + Vector2(0, k * 0.62), c + Vector2(-k * 0.62, 0)]), lit)
			ci.draw_polyline(d + PackedVector2Array([d[0]]), Color(1.0, 0.62, 0.28), 1.3)
		"ranged":
			ci.draw_circle(c + Vector2(0, k * 0.15), k * 0.62, dark)
			ci.draw_arc(c + Vector2(0, 0), k * 0.65, -PI * 0.85, PI * 0.35, 18, lit, maxf(1.4, k * 0.16))
			ci.draw_line(c + Vector2(-k * 0.42, -k * 0.72), c + Vector2(k * 0.55, k * 0.55), lit, maxf(1.2, k * 0.12))
			ci.draw_circle(c + Vector2(0, -k * 0.45), k * 0.30, lit)
		_:
			ci.draw_circle(c + Vector2(0, k * 0.15), k * 0.68, dark)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.44, -k * 0.72), Vector2(k * 0.88, k * 0.55)), lit)
			ci.draw_line(c + Vector2(-k * 0.55, k * 0.12), c + Vector2(k * 0.62, -k * 0.62), lit, maxf(1.3, k * 0.16))
			ci.draw_line(c + Vector2(-k * 0.55, k * 0.12), c + Vector2(k * 0.62, -k * 0.62), Color(1, 1, 1, 0.45), 1.0)

static func _draw_jungle(ci: CanvasItem, c: Vector2, r: float, kind: String, _col: Color) -> void:
	var body := Color(0.96, 0.45, 0.24)
	var ring := Color(1.0, 0.74, 0.38)
	if kind == "shadow_tyrant":
		body = Color(0.64, 0.34, 0.92)
		ring = Color(0.84, 0.66, 1.0)
	elif kind == "dragon":
		body = Color(0.34, 0.76, 0.96)
		ring = Color(0.74, 0.94, 1.0)
	elif kind == "storm_dragon":
		body = Color(1.0, 0.84, 0.30)
		ring = Color(1.0, 0.96, 0.64)
	var k := r * 0.62
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.9, -k * 0.35), c + Vector2(-k * 0.35, -k * 1.15), c + Vector2(-k * 0.12, -k * 0.30)]), ring)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k * 0.9, -k * 0.35), c + Vector2(k * 0.35, -k * 1.15), c + Vector2(k * 0.12, -k * 0.30)]), ring)
	ci.draw_circle(c + Vector2(0, k * 0.15), k * 0.76, body)
	ci.draw_arc(c + Vector2(0, k * 0.15), k * 0.76, 0, TAU, 24, Color(0.05, 0.05, 0.08), 1.2)
	ci.draw_circle(c + Vector2(-k * 0.28, 0), maxf(1.0, k * 0.13), Color(1, 1, 1, 0.95))
	ci.draw_circle(c + Vector2(k * 0.28, 0), maxf(1.0, k * 0.13), Color(1, 1, 1, 0.95))
