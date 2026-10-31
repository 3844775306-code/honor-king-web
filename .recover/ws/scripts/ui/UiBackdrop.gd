extends Control
## 全屏程序化背景：纵向渐变 + 中心冷光辉光 + 斜向网格 + 缓慢漂浮粒子 + 暗角。
## 用法：UiKit.make_backdrop(parent, accent)（自动铺满 full rect 并置于最底层）。
## 无贴图、纯 _draw，移动端开销可控（约 60~80 个 draw call / 帧）。

var accent := Color(0.32, 0.62, 1.0)
var particle_count := 42
var glow_strength := 1.0
var show_grid := true
var vignette := true

var _t := 0.0
var _particles: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in particle_count:
		_particles.append(Vector3(randf(), randf(), randf_range(0.12, 0.7)))
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var s := size
	if s.x <= 1.0 or s.y <= 1.0:
		return
	# 1) 纵向渐变底（24 条，深海军蓝 -> 略亮的墨蓝）
	var steps := 24
	for i in steps:
		var k := float(i) / float(steps - 1)
		var c := Color(0.020, 0.028, 0.048).lerp(Color(0.060, 0.082, 0.128), k)
		draw_rect(Rect2(0.0, s.y * k, s.x, s.y / float(steps) + 2.0), c)
	# 2) 中心辉光（同心圆叠加，缓慢呼吸）
	var ctr := Vector2(s.x * 0.5, s.y * 0.40)
	var breath := 0.85 + 0.15 * sin(_t * 0.35)
	var rings := 26
	for i in rings:
		var r := s.x * (0.10 + 0.55 * float(i) / float(rings))
		var a := 0.010 * glow_strength * breath * (1.0 - float(i) / float(rings))
		draw_circle(ctr, r, Color(accent.r, accent.g, accent.b, a))
	# 3) 斜向网格（极淡，给“科技感”底纹）
	if show_grid:
		var gap := maxf(96.0, s.x / 18.0)
		var gc := Color(0.55, 0.70, 1.0, 0.022)
		var x := -s.y
		while x < s.x:
			draw_line(Vector2(x, 0.0), Vector2(x + s.y, s.y), gc, 1.0)
			x += gap
	# 4) 漂浮粒子（缓慢上升 + 横向漂移，靠近中心更亮）
	var pc := Color(accent.r, accent.g, accent.b, 1.0)
	for i in _particles.size():
		var p: Vector3 = _particles[i]
		var px := fmod(p.x * s.x + _t * 14.0 * p.z + sin(_t * 0.5 + float(i)) * 18.0, s.x + 20.0) - 10.0
		var py := fmod(p.y * s.y - _t * 26.0 * p.z * 3.0 + s.y + sin(_t * 0.7 + float(i) * 1.7) * 10.0, s.y + 20.0) - 10.0
		var tw := 0.5 + 0.5 * sin(_t * 1.3 + float(i) * 2.1)
		var r := 1.2 + 2.2 * p.z
		draw_circle(Vector2(px, py), r, Color(pc.r, pc.g, pc.b, 0.05 + 0.10 * tw * p.z))
	# 5) 暗角：四边向内加深
	if vignette:
		var vsteps := 14
		for i in vsteps:
			var k := float(i) / float(vsteps)
			var a := 0.055 * (1.0 - k)
			var d := (s.y * 0.28) * (1.0 - k)
			draw_rect(Rect2(0.0, 0.0, s.x, d), Color(0.0, 0.0, 0.0, a))
			draw_rect(Rect2(0.0, s.y - d, s.x, d), Color(0.0, 0.0, 0.0, a))
			draw_rect(Rect2(0.0, 0.0, d * 0.6, s.y), Color(0.0, 0.0, 0.0, a))
			draw_rect(Rect2(s.x - d * 0.6, 0.0, d * 0.6, s.y), Color(0.0, 0.0, 0.0, a))
