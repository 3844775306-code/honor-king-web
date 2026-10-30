class_name CancelCastButton
extends Control
## 王者荣耀式「取消施法」按钮：拖动技能瞄准时出现在右缘，
## 手指拖到其上（松手落在按钮内）即取消施放。
## 纯显示 + 矩形命中检测（由 TouchController 轮询），不拦截输入（MOUSE_FILTER_IGNORE）。

var _highlighted := false
var _hl := 0.0

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示，不参与触摸/鼠标命中
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if _highlighted else 0.0
	if absf(_hl - target) < 0.003:
		return
	_hl = move_toward(_hl, target, delta * 12.0)
	queue_redraw()

func set_highlighted(v: bool):
	if v != _highlighted:
		_highlighted = v
		queue_redraw()

func _draw():
	var h := clampf(_hl, 0.0, 1.0)
	var center := size * 0.5 + Vector2(0, -2.0 * h)
	var radius := minf(size.x, size.y) * 0.4 * (1.0 + 0.035 * h)
	# 放大后线宽/提示字随按钮尺寸等比缩放（设计基准 150）
	var k := maxf(1.0, size.x / 150.0)
	var accent := Color(1.0, 0.35, 0.30, 0.88).lerp(Color(1.0, 0.58, 0.42, 1.0), h)
	UiKit.touch_button_frame(self, center, radius, accent, h, 4.0, false)
	# 红色玻璃主体：拖到其上时整体提亮
	var body := Color(0.22, 0.06, 0.06, 0.86).lerp(Color(0.42, 0.10, 0.09, 0.92), h)
	draw_circle(center, radius, body)
	draw_circle(center - Vector2(0, radius * 0.12), radius * 0.84, Color(1.0, 0.30, 0.24, 0.055 + 0.04 * h))
	draw_circle(center + Vector2(0, radius * 0.16), radius * 0.76, Color(0, 0, 0, 0.10))
	draw_arc(center, radius - 1.5, 0, TAU, 40, Color(1, 1, 1, 0.10 + 0.10 * h),
		maxf(1.4, radius * 0.02), true)
	draw_arc(center - Vector2(0, radius * 0.18), radius * 0.78, -PI * 0.92, -PI * 0.08,
		24, Color(1, 1, 1, 0.16 + 0.10 * h), maxf(2.0, radius * 0.045), true)
	if h > 0.02:
		draw_arc(center, radius + 9.0 + 2.0 * h, 0, TAU, 40,
			Color(1.0, 0.45, 0.32, 0.18 * h), 2.0, true)
	# ×
	var l := radius * 0.42
	var lw := 8.0 * k
	draw_line(center - Vector2(l, l), center + Vector2(l, l), Color(0, 0, 0, 0.35), lw + 4.0 * k)
	draw_line(center + Vector2(-l, l), center + Vector2(l, -l), Color(0, 0, 0, 0.35), lw + 4.0 * k)
	draw_line(center - Vector2(l, l), center + Vector2(l, l), Color.WHITE, lw)
	draw_line(center + Vector2(-l, l), center + Vector2(l, -l), Color.WHITE, lw)
	# 小字提示
	var fs := int(maxf(20.0, 20.0 * k))
	var tw := 80.0 * k
	draw_string(UiKit.font(), center + Vector2(-tw * 0.5, radius + 26.0 * k), "取消施法",
		HORIZONTAL_ALIGNMENT_CENTER, tw, fs, Color(1, 1, 1, 0.82 + 0.15 * h))
