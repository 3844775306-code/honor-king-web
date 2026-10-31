extends Control
## 主菜单背景：极简动态网格（鼠标视差 + 缓慢漂移）+ 金色光晕 + 暗角。
## 纯自绘，无贴图，开销极低。

const GOLD := Color(1.0, 0.84, 0.35)
const LINE := Color(0.50, 0.70, 1.0)

var _t := 0.0
var _m := Vector2(0.5, 0.5)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var vp := get_viewport()
	if vp != null:
		var sz := vp.get_visible_rect().size
		if sz.x > 4.0 and sz.y > 4.0:
			var mp := vp.get_mouse_position() / sz
			var want := Vector2(clampf(mp.x, 0.0, 1.0), clampf(mp.y, 0.0, 1.0))
			_m = _m.lerp(want, clampf(delta * 2.2, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x < 8.0 or s.y < 8.0:
		return
	# 底色：上深蓝灰 → 下近黑
	var c_top := Color(0.045, 0.055, 0.085)
	var c_bot := Color(0.008, 0.011, 0.020)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([c_top, c_top, c_bot, c_bot]))
	# 左上金色光晕（标题后方）
	var gc := Vector2(s.x * (0.17 + (_m.x - 0.5) * 0.03), s.y * (0.20 + (_m.y - 0.5) * 0.02))
	for i in range(7):
		draw_circle(gc, s.y * (0.10 + float(i) * 0.055), Color(GOLD.r, GOLD.g, GOLD.b, 0.016))
	# 透视网格：水平线随 “drift” 缓慢下移，底线密度更高
	var vanish := Vector2(s.x * (0.70 + (_m.x - 0.5) * 0.05), s.y * (0.93 + (_m.y - 0.5) * 0.03))
	var drift := fmod(_t * 20.0, 110.0)
	for i in range(28):
		var y := vanish.y - pow(float(i), 1.55) * 9.0 + drift
		if y > vanish.y - 4.0 or y < -s.y * 0.4:
			continue
		var a := clampf(0.105 - float(i) * 0.0034, 0.012, 0.105)
		draw_line(Vector2(0.0, y), Vector2(s.x, y), Color(LINE.r, LINE.g, LINE.b, a), 1.0)
	for i in range(-14, 15):
		var x2 := vanish.x + float(i) * s.x * 0.085
		draw_line(vanish, Vector2(x2, -s.y * 0.7), Color(LINE.r, LINE.g, LINE.b, 0.048), 1.0)
	# 暗角
	var bands := 9
	for i in range(bands):
		var a2 := 0.050 * (1.0 - float(i) / float(bands))
		var t := s.y * 0.055 * float(i)
		draw_rect(Rect2(0.0, 0.0, s.x, t), Color(0, 0, 0, a2 * 0.7))
		draw_rect(Rect2(0.0, s.y - t, s.x, t), Color(0, 0, 0, a2 * 0.7))
		draw_rect(Rect2(0.0, 0.0, t, s.y), Color(0, 0, 0, a2 * 0.55))
		draw_rect(Rect2(s.x - t, 0.0, t, s.y), Color(0, 0, 0, a2 * 0.55))
