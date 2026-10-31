extends Control
## 终局美术字（胜利/失败通用）：全屏压暗 + 中央背景板 + 弹出式美术字（入场回弹、收尾淡出）

signal finished

const HOLD := 2.6          # 停留时间（含入场/淡出）
const FADE_IN := 0.5
const FADE_OUT := 0.45

var won := false           # true=胜利（金色调），false=失败（暗红色调）
var _t := 0.0
var _done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 直接挂在 CanvasLayer 下：anchors 不会自动给尺寸，必须显式铺满视口，否则 size=0 通篇画不出来
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	position = Vector2.ZERO
	z_index = 75
	get_viewport().size_changed.connect(_fit_viewport)


func _fit_viewport() -> void:
	size = get_viewport_rect().size


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if not _done and _t >= HOLD:
		_done = true
		finished.emit()
		queue_free()


func _draw() -> void:
	var vp := get_viewport_rect().size
	var w: float = maxf(vp.x, 2400.0)
	var h: float = maxf(vp.y, 1400.0)
	# 整体透明度：淡入 → 停留 → 淡出
	var a := clampf(_t / FADE_IN, 0.0, 1.0)
	if _t > HOLD - FADE_OUT:
		a = clampf((HOLD - _t) / FADE_OUT, 0.0, 1.0)
	var center := Vector2(w * 0.5, h * 0.5)
	# 配色：胜利走金蓝，失败走暗红
	var plate_bg := Color(0.055, 0.075, 0.115, 0.94 * a) if won else Color(0.10, 0.035, 0.045, 0.94 * a)
	var plate_edge := Color(1.0, 0.86, 0.42, 0.95 * a) if won else Color(0.98, 0.78, 0.34, 0.92 * a)
	var glow_col := Color(0.95, 0.72, 0.20, a) if won else Color(0.62, 0.06, 0.06, a)
	var text_col := Color(1.0, 0.82, 0.30, a) if won else Color(0.96, 0.74, 0.28, a)
	var text_top := Color(1.0, 0.99, 0.86, 0.62 * a) if won else Color(1.0, 0.96, 0.80, 0.55 * a)
	var band_col := Color(1.0, 0.92, 0.58, a) if won else Color(0.99, 0.80, 0.36, a)
	# ---- 全屏压暗 ----
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Color(0.01, 0.015, 0.03, 0.62 * a) if won
		else Color(0.02, 0.012, 0.016, 0.62 * a))
	# ---- 中央背景板 ----
	var pw: float = w * 0.52
	var ph: float = h * 0.34
	var plate := Rect2(center.x - pw * 0.5, center.y - ph * 0.5, pw, ph)
	# 外发光：三层递扩的圆角底光
	for i in range(3):
		var grow: float = 18.0 + 26.0 * float(i)
		var ga: float = (0.20 - 0.055 * float(i)) * a
		draw_style_box(UiKit.flat(ga, 26, 0, Color(0, 0, 0, 0), Color(glow_col.r, glow_col.g, glow_col.b, ga),
			0.0, 0.0), plate.grow(grow))
	# 板体：深色底 + 亮边
	draw_style_box(UiKit.flat(0.94 * a, 18, 3, plate_edge, plate_bg, 0.0, 22.0), plate)
	draw_rect(Rect2(plate.position + Vector2(3, 3), Vector2(plate.size.x - 6, plate.size.y * 0.42)),
		Color(glow_col.r, glow_col.g, glow_col.b, 0.20 * a))
	# 板内上下两道金线（渐隐）
	for sy in [plate.position.y + plate.size.y * 0.16, plate.position.y + plate.size.y * 0.84]:
		for seg in range(24):
			var k0: float = float(seg) / 24.0
			var k1: float = float(seg + 1) / 24.0
			var seg_a: float = (1.0 - absf(k0 * 2.0 - 1.0)) * 0.85 * a
			var x0: float = plate.position.x + plate.size.x * (0.10 + 0.80 * k0)
			var x1: float = plate.position.x + plate.size.x * (0.10 + 0.80 * k1)
			draw_line(Vector2(x0, sy), Vector2(x1, sy), Color(band_col.r, band_col.g, band_col.b, seg_a), 2.5)
	# ---- 美术字 ----
	var f := UiKit.font()
	var fs: int = int(round(h * 0.150))
	var k := clampf((_t - 0.06) / 0.42, 0.0, 1.0)
	# 回弹放大：0.62 → 1.06 → 1.0，并带一点入场抖动
	var pop: float = 0.62 + 0.44 * (1.0 - pow(1.0 - k, 3.0))
	if k > 0.78:
		pop = 1.06 - 0.06 * clampf((k - 0.78) / 0.22, 0.0, 1.0)
	var jitter := Vector2(sin(_t * 62.0) * 10.0, cos(_t * 55.0) * 6.0) * (1.0 - k)
	draw_set_transform(center + jitter, 0.0, Vector2(pop, pop))
	var ty: float = fs * 0.36
	# 以屏幕中心为原点、按 pop 缩放绘制（x 传 -w/2 + 居中宽度，保证中心不动）
	var tx: float = -w * 0.5
	var txt := "胜利" if won else "失败"
	# 1) 外发光（大描边）
	draw_string_outline(f, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
		int(round(fs * 0.20)), Color(glow_col.r, glow_col.g, glow_col.b, 0.34 * a))
	# 2) 深色厚描边（字身压边）
	draw_string_outline(f, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs,
		maxi(6, int(round(fs * 0.075))), Color(0.08, 0.05, 0.02, 0.96 * a))
	# 3) 主体金色
	draw_string(f, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, text_col)
	# 4) 上半高光（模拟垂直渐变：同一字形上移一点再叠亮色）
	draw_string(f, Vector2(tx, ty - fs * 0.055), txt, HORIZONTAL_ALIGNMENT_CENTER, w, fs, text_top)
	draw_set_transform(Vector2.ZERO)
	# ---- 副标题 ----
	var fs2: int = int(round(h * 0.030))
	var sub := "敌方水晶已被摧毁" if won else "我方水晶已被摧毁"
	UiKit.text(self, Vector2(center.x, center.y + ph * 0.30), sub, fs2,
		Color(1.0, 0.92, 0.72, 0.92 * a) if won else Color(1.0, 0.86, 0.66, 0.92 * a),
		HORIZONTAL_ALIGNMENT_CENTER, w)
