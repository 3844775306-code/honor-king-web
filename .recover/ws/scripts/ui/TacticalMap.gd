extends Control
## 主菜单「战术沙盘」：俯视峡谷示意图 + 5 个分路热点，点地图直接选分路。
## 纯自绘（不依赖 MinimapDraw / 对局状态），可独立放进任何页面。

signal lane_picked(lane: String)

const GOLD := Color(1.0, 0.84, 0.35)
const CYAN := Color(0.25, 0.85, 1.0)
const RED := Color(1.0, 0.40, 0.32)
const HS_COLOR := Color(0.10, 0.14, 0.22, 0.88)

## 归一化坐标 [-1,1]，左下是我方基地、右上是敌方基地
const LANE_PATHS := {
	"对抗路": [Vector2(-0.82, 0.82), Vector2(-0.82, -0.56), Vector2(-0.58, -0.82), Vector2(0.82, -0.82)],
	"中路": [Vector2(-0.82, 0.82), Vector2(0.82, -0.82)],
	"发育路": [Vector2(-0.82, 0.82), Vector2(0.56, 0.82), Vector2(0.82, 0.58), Vector2(0.82, -0.82)],
}
const HOTSPOTS := {
	"对抗路": Vector2(-0.82, -0.18),
	"打野": Vector2(-0.36, -0.36),
	"中路": Vector2(0.0, 0.0),
	"发育路": Vector2(0.56, 0.82),
	"游走": Vector2(0.30, 0.34),
}

var lane := ""
var hover := ""
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(true)


func set_lane(l: String) -> void:
	lane = l
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _map_rect() -> Rect2:
	var pad := 12.0
	var side: float = minf(size.x, size.y) - pad * 2.0
	if side < 40.0:
		side = 40.0
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _pt(n: Vector2) -> Vector2:
	var r := _map_rect()
	return r.position + (n * 0.5 + Vector2(0.5, 0.5)) * r.size


func _hs_radius() -> float:
	return _map_rect().size.x * 0.052


func _sample(pts: Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] - pts[i]).length()
	var want := clampf(t, 0.0, 1.0) * total
	for i in range(pts.size() - 1):
		var seg: float = (pts[i + 1] - pts[i]).length()
		if want <= seg and seg > 0.0001:
			return (pts[i] as Vector2).lerp(pts[i + 1], want / seg)
		want -= seg
	return pts[pts.size() - 1]


func _draw() -> void:
	var s := size
	if s.x < 40.0 or s.y < 40.0:
		return
	var mr := _map_rect()
	# 沙盘底板
	draw_style_box(UiKit.flat(0.74, 20, 2, Color(0.42, 0.64, 1.0, 0.26), Color(0, 0, 0, 0), 26.0, 16.0), mr)
	# 内部参考网格
	for i in range(1, 4):
		var f := float(i) / 4.0
		draw_line(Vector2(mr.position.x + mr.size.x * f, mr.position.y),
			Vector2(mr.position.x + mr.size.x * f, mr.end.y), Color(0.5, 0.7, 1.0, 0.05), 1.0)
		draw_line(Vector2(mr.position.x, mr.position.y + mr.size.y * f),
			Vector2(mr.end.x, mr.position.y + mr.size.y * f), Color(0.5, 0.7, 1.0, 0.05), 1.0)
	# 河道（与中路垂直的斜带）
	draw_line(_pt(Vector2(-0.72, -0.46)), _pt(Vector2(0.46, 0.72)),
		Color(CYAN.r, CYAN.g, CYAN.b, 0.10), mr.size.x * 0.11)
	# 野区色块
	for c in [Vector2(-0.30, -0.44), Vector2(0.34, -0.24), Vector2(-0.22, 0.34), Vector2(0.46, 0.30)]:
		draw_circle(_pt(c), mr.size.x * 0.075, Color(0.30, 0.85, 0.55, 0.055))
	# 分路
	for key in LANE_PATHS:
		var raw: Array = LANE_PATHS[key]
		var pts := PackedVector2Array()
		for p in raw:
			pts.append(_pt(p))
		var on: bool = str(key) == lane
		draw_polyline(pts, Color(1, 1, 1, 0.20), 6.0, true)
		if on:
			draw_polyline(pts, Color(GOLD.r, GOLD.g, GOLD.b, 0.16), 18.0, true)
			draw_polyline(pts, Color(GOLD.r, GOLD.g, GOLD.b, 0.95), 4.0, true)
			# 沿线流动的标记点
			var t := fmod(_t * 0.30, 1.0)
			var pos := _sample(raw, t)
			draw_circle(_pt(pos), 7.0, Color(1.0, 0.96, 0.80, 0.95))
			draw_circle(_pt(pos), 13.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.22))
		# 塔（我方 3 座 / 敌方 3 座）
		for tt in [0.16, 0.30, 0.44]:
			var a: Vector2 = _sample(raw, float(tt))
			var b: Vector2 = _sample(raw, 1.0 - float(tt))
			_draw_tower(_pt(a), 7.0, CYAN)
			_draw_tower(_pt(b), 7.0, RED)
	# 双方基地
	draw_circle(_pt(Vector2(-0.82, 0.82)), mr.size.x * 0.055, Color(CYAN.r, CYAN.g, CYAN.b, 0.16))
	draw_circle(_pt(Vector2(-0.82, 0.82)), mr.size.x * 0.028, Color(CYAN.r, CYAN.g, CYAN.b, 0.65))
	draw_circle(_pt(Vector2(0.82, -0.82)), mr.size.x * 0.055, Color(RED.r, RED.g, RED.b, 0.16))
	draw_circle(_pt(Vector2(0.82, -0.82)), mr.size.x * 0.028, Color(RED.r, RED.g, RED.b, 0.65))
	# 热点（5 个分路）
	var fs := int(round(21.0 * UiKit.scale()))
	for key in HOTSPOTS:
		var p := _pt(HOTSPOTS[key])
		var sel: bool = str(key) == lane
		var hov: bool = str(key) == hover
		var r := _hs_radius()
		if sel or hov:
			draw_circle(p, r * 1.55, Color(GOLD.r, GOLD.g, GOLD.b, 0.14 if sel else 0.07))
		draw_circle(p, r, Color(GOLD.r, GOLD.g, GOLD.b, 0.96) if sel else HS_COLOR)
		draw_arc(p, r, 0.0, TAU, 32, Color(GOLD.r, GOLD.g, GOLD.b, 0.55 if not sel else 0.9), 2.0, true)
		var col := Color(0.10, 0.09, 0.05) if sel else Color(0.94, 0.96, 1.0, 0.95)
		var w := r * 2.0
		UiKit.text(self, p + Vector2(-w * 0.5, fs * 0.36), str(key), fs, col,
			HORIZONTAL_ALIGNMENT_CENTER, w)
	# 角标文案
	var cap_fs := int(round(19.0 * UiKit.scale()))
	UiKit.text(self, mr.position + Vector2(26.0, 38.0), "战术沙盘 · 点选你的分路", cap_fs,
		Color(0.70, 0.78, 0.92, 0.85))
	if lane != "":
		UiKit.text(self, Vector2(mr.position.x + 26.0, mr.end.y - 20.0),
			"已选 %s · %s" % [lane, HeroPickData.lane_role(lane)], cap_fs, Color(GOLD.r, GOLD.g, GOLD.b, 0.92))


func _draw_tower(p: Vector2, r: float, col: Color) -> void:
	draw_circle(p, r, Color(0, 0, 0, 0.35))
	draw_circle(p, r * 0.72, Color(col.r, col.g, col.b, 0.85))


func _hit(p: Vector2) -> String:
	var r := _hs_radius() * 1.25
	for key in HOTSPOTS:
		if p.distance_to(_pt(HOTSPOTS[key])) <= r:
			return str(key)
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit((event as InputEventMouseMotion).position)
		if h != hover:
			hover = h
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var h2 := _hit(mb.position)
			if h2 != "":
				lane = h2
				queue_redraw()
				lane_picked.emit(h2)
