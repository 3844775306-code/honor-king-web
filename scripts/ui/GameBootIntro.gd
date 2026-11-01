extends Control
## 游戏启动界面：主菜单前的电影感开机动画。
## 纯 CanvasItem 自绘（无贴图/新资源）：暗色电影底 + 战术沙盘全息投影 + 五位英雄头像
## + 金色粒子/光扫 + 上下遮幅 + 标题逐渐亮起。点击/空格可跳过，超时自动进入主菜单。

signal finished
signal toggle_requested

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const BootHeroPool = preload("res://scripts/ui/BootHeroPool.gd")
const GOLD := Color(1.0, 0.84, 0.35)
const CYAN := Color(0.25, 0.85, 1.0)
const RED := Color(1.0, 0.40, 0.32)
const CREAM := Color(1.0, 0.93, 0.76)

var _heroes: Array = []

# 与主菜单战术沙盘同源的分路路径（归一化坐标）
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

var _t := 0.0
var _done := false
var _motes: Array = []
## 登录成功后作为 2D 过渡动画使用：更短、隐藏“点击进入/切换”提示。
var transition_mode := false
var _duration := 6.2


func _ready() -> void:
	_heroes = BootHeroPool.pick(5)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_duration = 4.4 if transition_mode else 6.2
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261101
	for i in range(72):
		_motes.append({
			"x": rng.randf_range(0.0, 1.0), "y": rng.randf_range(0.0, 1.0),
			"vx": rng.randf_range(-0.010, 0.014), "vy": rng.randf_range(-0.018, -0.006),
			"r": rng.randf_range(0.6, 2.3), "ph": rng.randf_range(0.0, TAU),
		})
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if not _done and _t >= _duration:
		_finish()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _done or _t < 0.9:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_V and not transition_mode:
			toggle_requested.emit()
			get_viewport().set_input_as_handled()
			return
		_finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		_finish()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.55)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free())


# ==================== 绘制 ====================

func _draw() -> void:
	var s := size
	if s.x < 32.0 or s.y < 32.0:
		return
	var p := _t
	_draw_background(s)
	_draw_motes(s, p)
	_draw_map(s, p)
	_draw_heroes(s, p)
	_draw_titles(s, p)
	_draw_sweep(s, p)
	_draw_vignette(s)
	_draw_film_bars(s, p)
	_draw_top_marks(s, p)
	_draw_bottom_marks(s, p)


func _draw_background(s: Vector2) -> void:
	var top := Color(0.018, 0.030, 0.075)
	var bottom := Color(0.002, 0.004, 0.012)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0.0), s, Vector2(0.0, s.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	# 沙盘中心冷光 + 标题后方暖光
	var mc := Vector2(s.x * 0.5, s.y * 0.47)
	for i in range(8):
		draw_circle(mc, s.y * (0.10 + 0.045 * float(i)), Color(0.10, 0.35, 0.62, 0.018))
	var tc := Vector2(s.x * 0.5, s.y * 0.255)
	for i in range(7):
		draw_circle(tc, s.y * (0.05 + 0.035 * float(i)), Color(GOLD.r, GOLD.g, GOLD.b, 0.012))
	# 细网格地平线，增加电影空间感
	for i in range(14):
		var y := s.y * 0.62 + float(i) * float(i) * s.y * 0.0028
		if y > s.y:
			break
		draw_line(Vector2(0.0, y), Vector2(s.x, y), Color(0.35, 0.60, 0.92, 0.035), 1.0)


func _draw_motes(s: Vector2, p: float) -> void:
	for m in _motes:
		var mx: float = fmod(float(m.x) + float(m.vx) * p + 1.0, 1.0)
		var my: float = fmod(float(m.y) + float(m.vy) * p + 1.0, 1.0)
		var tw: float = 0.45 + 0.55 * sin(p * 2.2 + float(m.ph))
		var a: float = clampf(tw, 0.0, 1.0) * 0.44
		var c := Color(GOLD.r, GOLD.g, GOLD.b, a * 0.7)
		draw_circle(Vector2(mx * s.x, my * s.y), float(m.r), c)


func _draw_map(s: Vector2, p: float) -> void:
	var reveal := _ease(p, 0.35, 1.55)
	if reveal <= 0.001:
		return
	var side := minf(s.x * 0.56, s.y * 0.54)
	var c := Vector2(s.x * 0.5, s.y * 0.47 + (1.0 - reveal) * s.y * 0.035)
	var a := reveal
	# 全息底座光晕
	for i in range(7):
		draw_circle(c, side * (0.16 + 0.055 * float(i)), Color(0.15, 0.55, 0.95, 0.014 * a))
	# 旋转刻度环
	var spin := p * 0.16
	for i in range(4):
		var ang := spin + float(i) * PI * 0.5
		draw_arc(c, side * 0.52, ang, ang + PI * 0.30, 28,
			Color(CYAN.r, CYAN.g, CYAN.b, 0.20 * a), 1.6, true)
		draw_arc(c, side * 0.46, -ang, -ang + PI * 0.18, 20,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.16 * a), 1.2, true)
	draw_arc(c, side * 0.53, 0.0, TAU, 96, Color(GOLD.r, GOLD.g, GOLD.b, 0.22 * a), 1.2, true)
	# 方形沙盘边界与网格
	var half := side * 0.50
	var corners := PackedVector2Array([
		c + Vector2(-half, -half), c + Vector2(half, -half),
		c + Vector2(half, half), c + Vector2(-half, half), c + Vector2(-half, -half)])
	draw_polyline(corners, Color(0.35, 0.68, 1.0, 0.24 * a), 1.4, true)
	for i in range(-2, 3):
		var off := float(i) * side * 0.10
		draw_line(c + Vector2(-half, off), c + Vector2(half, off),
			Color(0.35, 0.68, 1.0, 0.055 * a), 1.0)
		draw_line(c + Vector2(off, -half), c + Vector2(off, half),
			Color(0.35, 0.68, 1.0, 0.055 * a), 1.0)
	# 河道（与中路垂直的暗色水带）与野区节点
	var river_a := _map_pt(Vector2(-0.98, -0.98), c, side)
	var river_b := _map_pt(Vector2(0.98, 0.98), c, side)
	draw_line(river_a, river_b, Color(0.18, 0.55, 0.85, 0.10 * a), side * 0.075, true)
	draw_line(river_a, river_b, Color(0.35, 0.82, 1.0, 0.16 * a), 1.2, true)
	for camp in [Vector2(-0.45, 0.15), Vector2(0.45, -0.15), Vector2(-0.18, 0.48), Vector2(0.18, -0.48)]:
		var cp := _map_pt(camp, c, side)
		draw_circle(cp, 3.0, Color(0.45, 1.0, 0.55, 0.55 * a))
		draw_arc(cp, 7.0, 0.0, TAU, 18, Color(0.45, 1.0, 0.55, 0.20 * a), 1.0, true)
	# 暴君 / 主宰坑
	for pit in [Vector2(0.30, 0.12), Vector2(-0.30, -0.12)]:
		var pp := _map_pt(pit, c, side)
		draw_circle(pp, 7.5, Color(RED.r, RED.g, RED.b, 0.10 * a))
		draw_arc(pp, 8.0, 0.0, TAU, 24, Color(1.0, 0.62, 0.30, 0.52 * a), 1.3, true)
		draw_circle(pp, 2.2, Color(1.0, 0.72, 0.42, 0.85 * a))
	# 双方基地色盘
	draw_circle(_map_pt(Vector2(-0.82, 0.82), c, side), side * 0.075, Color(CYAN.r, CYAN.g, CYAN.b, 0.055 * a))
	draw_circle(_map_pt(Vector2(0.82, -0.82), c, side), side * 0.075, Color(RED.r, RED.g, RED.b, 0.055 * a))
	# 三路
	var lane_cols := {"对抗路": GOLD, "中路": CREAM, "发育路": CYAN}
	for lane in ["对抗路", "中路", "发育路"]:
		var path: Array = LANE_PATHS[lane]
		var col: Color = lane_cols[lane]
		for i in range(path.size() - 1):
			var a0 := _map_pt(path[i], c, side)
			var a1 := _map_pt(path[i + 1], c, side)
			draw_line(a0, a1, Color(col.r, col.g, col.b, 0.40 * a), 3.0, true)
			draw_line(a0, a1, Color(1.0, 1.0, 1.0, 0.10 * a), 1.0, true)
		# 沿路防御塔节点
		for frac in [0.18, 0.38, 0.62, 0.82]:
			var tp := _map_pt(_sample_path(path, float(frac)), c, side)
			draw_circle(tp, 2.4, Color(col.r, col.g, col.b, 0.68 * a))
			draw_arc(tp, 5.0, 0.0, TAU, 14, Color(col.r, col.g, col.b, 0.20 * a), 1.0, true)
		# 沿路流动的兵线光点
		for j in range(2):
			var frac: float = fmod(p * 0.16 + float(j) * 0.5, 1.0)
			var q := _map_pt(_sample_path(path, frac), c, side)
			draw_circle(q, 3.8, Color(GOLD.r, GOLD.g, GOLD.b, 0.72 * a))
			draw_circle(q, 8.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.10 * a))
	# 热点 / 分路标签
	for lane in ["对抗路", "中路", "发育路"]:
		var hp := _map_pt(HOTSPOTS[lane], c, side)
		draw_circle(hp, 4.5, Color(GOLD.r, GOLD.g, GOLD.b, 0.9 * a))
		draw_arc(hp, 10.0, 0.0, TAU, 20, Color(GOLD.r, GOLD.g, GOLD.b, 0.30 * a), 1.0, true)
		UiKit.text(self, hp + Vector2(-40.0, -13.0), lane, 13,
			Color(0.82, 0.90, 1.0, 0.62 * a), HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	# 双方基地水晶
	_draw_crystal(c + Vector2(-0.82, 0.82) * side * 0.5, 9.0, Color(CYAN.r, CYAN.g, CYAN.b, 0.95 * a))
	_draw_crystal(c + Vector2(0.82, -0.82) * side * 0.5, 9.0, Color(RED.r, RED.g, RED.b, 0.95 * a))
	# 中心王冠/徽记
	draw_circle(c, 12.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.10 * a))
	draw_arc(c, 13.0, 0.0, TAU, 32, Color(GOLD.r, GOLD.g, GOLD.b, 0.7 * a), 1.6, true)
	draw_line(c + Vector2(0.0, -7.0), c + Vector2(0.0, 7.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.65 * a), 1.5)
	draw_line(c + Vector2(-7.0, 0.0), c + Vector2(7.0, 0.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.65 * a), 1.5)


func _draw_crystal(pos: Vector2, r: float, col: Color) -> void:
	draw_circle(pos, r * 2.0, Color(col.r, col.g, col.b, col.a * 0.10))
	var pts := PackedVector2Array([pos + Vector2(0.0, -r), pos + Vector2(r * 0.7, 0.0),
		pos + Vector2(0.0, r), pos + Vector2(-r * 0.7, 0.0), pos + Vector2(0.0, -r)])
	draw_polyline(pts, col, 2.0, true)
	draw_circle(pos, r * 0.28, Color(1.0, 1.0, 1.0, col.a * 0.9))


func _draw_heroes(s: Vector2, p: float) -> void:
	var n := _heroes.size()
	for i in range(n):
		var k := _ease(p, 2.0 + float(i) * 0.13, 2.58 + float(i) * 0.13)
		if k <= 0.001:
			continue
		var x := s.x * (0.14 + 0.18 * float(i))
		var y := s.y * 0.695 + (1.0 - k) * s.y * 0.030
		var r := clampf(s.y * 0.048, 38.0, 70.0)
		var hero: Dictionary = _heroes[i]
		var accent := HeroArt.accent_of(str(hero.name))
		var c := Vector2(x, y)
		# 英雄背后的光晕与细环
		draw_circle(c, r * 1.55, Color(accent.r, accent.g, accent.b, 0.055 * k))
		draw_circle(c, r * 1.18, Color(0.02, 0.04, 0.08, 0.82 * k))
		HeroArt.draw_portrait(self, c, r, str(hero.name), accent, false)
		draw_arc(c, r + 2.0, 0.0, TAU, 40, Color(accent.r, accent.g, accent.b, 0.62 * k), 1.4, true)
		draw_arc(c, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * 0.35, 24,
			Color(GOLD.r, GOLD.g, GOLD.b, 0.42 * k), 1.0, true)
		UiKit.text(self, Vector2(x - 100.0, y + r + 30.0), str(hero.name), 21,
			Color(0.96, 0.96, 0.98, k), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
		UiKit.text(self, Vector2(x - 100.0, y + r + 52.0), "%s · %s" % [str(hero.role), str(hero.tag)], 13,
			Color(0.62, 0.74, 0.92, 0.76 * k), HORIZONTAL_ALIGNMENT_CENTER, 200.0)


func _draw_titles(s: Vector2, p: float) -> void:
	# 标题
	var tk := _ease(p, 1.0, 2.0)
	var fs := int(clampf(s.y * 0.102, 68.0, 166.0))
	var ty := s.y * 0.165 + (1.0 - tk) * s.y * 0.028
	var tc := Vector2(s.x * 0.5, ty - float(fs) * 0.34)
	for i in range(8):
		draw_circle(tc, s.y * (0.035 + 0.019 * float(i)), Color(GOLD.r, GOLD.g, GOLD.b, 0.013 * tk))
	UiKit.text(self, Vector2(0.0, ty), "荣耀王者", fs, Color(CREAM.r, CREAM.g, CREAM.b, tk),
		HORIZONTAL_ALIGNMENT_CENTER, s.x)
	# 副标 / tagline
	var sk := _ease(p, 1.35, 2.2)
	UiKit.text(self, Vector2(0.0, ty + float(fs) * 0.78), "H O N O R   K I N G",
		int(clampf(s.y * 0.027, 18.0, 36.0)), Color(GOLD.r, GOLD.g, GOLD.b, 0.78 * sk),
		HORIZONTAL_ALIGNMENT_CENTER, s.x)
	var tgk := _ease(p, 1.8, 2.6)
	UiKit.text(self, Vector2(0.0, ty + float(fs) * 1.18), "王者峡谷 · 5V5 公平竞技",
		int(clampf(s.y * 0.024, 16.0, 30.0)), Color(0.68, 0.78, 0.94, 0.72 * tgk),
		HORIZONTAL_ALIGNMENT_CENTER, s.x)


func _draw_sweep(s: Vector2, p: float) -> void:
	var k := _ease(p, 0.8, 3.4)
	if k <= 0.001:
		return
	var x := s.x * (-0.35 + k * 1.7)
	var band := PackedVector2Array([
		Vector2(x, 0.0), Vector2(x + s.x * 0.06, 0.0),
		Vector2(x - s.x * 0.22, s.y), Vector2(x - s.x * 0.28, s.y)])
	draw_polygon(band, PackedColorArray([
		Color(1.0, 0.94, 0.72, 0.018), Color(1.0, 0.94, 0.72, 0.010),
		Color(1.0, 0.94, 0.72, 0.002), Color(0.0, 0.0, 0.0, 0.0)]))
	# 横向胶片扫描线
	for i in range(18):
		var y := fmod(float(i) * s.y * 0.061 + p * 10.0, s.y)
		draw_line(Vector2(0.0, y), Vector2(s.x, y), Color(0.55, 0.78, 1.0, 0.014), 1.0)


func _draw_vignette(s: Vector2) -> void:
	var bands := 10
	for i in range(bands):
		var a := 0.052 * (1.0 - float(i) / float(bands))
		var t := s.y * 0.055 * float(i)
		draw_rect(Rect2(0.0, 0.0, s.x, t), Color(0, 0, 0, a * 0.72))
		draw_rect(Rect2(0.0, s.y - t, s.x, t), Color(0, 0, 0, a * 0.72))
		draw_rect(Rect2(0.0, 0.0, t, s.y), Color(0, 0, 0, a * 0.55))
		draw_rect(Rect2(s.x - t, 0.0, t, s.y), Color(0, 0, 0, a * 0.55))


func _draw_film_bars(s: Vector2, p: float) -> void:
	var k := _ease(p, 0.0, 0.9)
	var bh := s.y * 0.055 * k
	if bh <= 0.01:
		return
	draw_rect(Rect2(0.0, 0.0, s.x, bh), Color(0.0, 0.0, 0.0, 0.96))
	draw_rect(Rect2(0.0, s.y - bh, s.x, bh), Color(0.0, 0.0, 0.0, 0.96))
	draw_line(Vector2(0.0, bh), Vector2(s.x, bh), Color(GOLD.r, GOLD.g, GOLD.b, 0.32), 1.0)
	draw_line(Vector2(0.0, s.y - bh), Vector2(s.x, s.y - bh), Color(GOLD.r, GOLD.g, GOLD.b, 0.32), 1.0)


func _draw_top_marks(s: Vector2, p: float) -> void:
	var k := _ease(p, 0.0, 0.8) * (1.0 - _ease(p, 2.1, 2.8))
	if k <= 0.001:
		return
	var fs := int(clampf(s.y * 0.016, 12.0, 18.0))
	UiKit.text(self, Vector2(28.0, s.y * 0.055 + 17.0), "H O N O R   K I N G   S T U D I O", fs,
		Color(0.62, 0.75, 0.92, 0.70 * k))
	UiKit.text(self, Vector2(0.0, s.y * 0.055 + 17.0), "C H A P T E R   I   ·   T H E   C A N Y O N",
		fs, Color(0.62, 0.75, 0.92, 0.56 * k), HORIZONTAL_ALIGNMENT_RIGHT, s.x - 28.0)


func _draw_bottom_marks(s: Vector2, p: float) -> void:
	var status := _ease(p, 2.4, 3.0)
	if status > 0.001:
		var dots := ".".repeat(int(p * 3.0) % 3 + 1)
		var status_txt := "正在进入王者峡谷" if not transition_mode else "正在进入王者世界"
		UiKit.text(self, Vector2(0.0, s.y * 0.828), status_txt + dots,
			int(clampf(s.y * 0.020, 14.0, 24.0)), Color(0.62, 0.76, 0.94, 0.72 * status),
			HORIZONTAL_ALIGNMENT_CENTER, s.x)
		# 进度线
		var pw := s.x * 0.26
		var px := (s.x - pw) * 0.5
		var py := s.y * 0.865
		draw_line(Vector2(px, py), Vector2(px + pw, py), Color(0.35, 0.55, 0.82, 0.26), 2.0)
		var fill := clampf(p / (3.8 if transition_mode else 5.2), 0.0, 1.0)
		draw_line(Vector2(px, py), Vector2(px + pw * fill, py), Color(GOLD.r, GOLD.g, GOLD.b, 0.85), 2.0)
		for i in range(6):
			var qx := px + pw * (float(i) + 0.5) / 6.0
			draw_line(Vector2(qx, py - 3.0), Vector2(qx, py + 3.0), Color(0.05, 0.08, 0.12, 0.9), 1.0)
	if not transition_mode:
		var enter := _ease(p, 4.15, 4.7)
		if enter > 0.001:
			var pulse := 0.72 + 0.28 * sin(p * 4.2)
			UiKit.text(self, Vector2(0.0, s.y * 0.902), "点击进入  ›",
				int(clampf(s.y * 0.032, 22.0, 42.0)), Color(CREAM.r, CREAM.g, CREAM.b, enter * pulse),
				HORIZONTAL_ALIGNMENT_CENTER, s.x)
	var skip := _ease(p, 1.0, 1.5)
	if skip > 0.001 and not _done:
		var hint := "点击 / 空格 跳过  ·  V 切换 3D" if not transition_mode else "点击 / 空格 跳过"
		UiKit.text(self, Vector2(0.0, s.y * 0.935), hint,
			int(clampf(s.y * 0.014, 11.0, 16.0)), Color(0.55, 0.65, 0.80, 0.55 * skip),
			HORIZONTAL_ALIGNMENT_CENTER, s.x)


# ==================== 工具 ====================

func _ease(x: float, a: float, b: float) -> float:
	if b <= a:
		return 1.0 if x >= b else 0.0
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _map_pt(n: Vector2, c: Vector2, side: float) -> Vector2:
	return c + n * side * 0.5


func _sample_path(path: Array, t: float) -> Vector2:
	var total := 0.0
	for i in range(path.size() - 1):
		total += (path[i + 1] - path[i]).length()
	var want := clampf(t, 0.0, 1.0) * total
	for i in range(path.size() - 1):
		var seg: float = (path[i + 1] - path[i]).length()
		if want <= seg and seg > 0.0001:
			return (path[i] as Vector2).lerp(path[i + 1], want / seg)
		want -= seg
	return path[path.size() - 1]
