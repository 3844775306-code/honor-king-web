class_name MoveModeToggle
extends Control
## 桌面移动模式切换（电脑端专属，手机上隐藏）：
## 点按在 转向模式 ↔ 前后左右模式 之间切换。
## - 转向模式：A/D 原地转向，W/S 沿面朝前后移动（现状）
## - 前后左右模式：W/S/A/D 直接按屏幕方向移动（上→远离镜头，与摇杆方向映射一致）

signal mode_changed(mode: int)

const MODE_NAMES := ["转向模式", "前后左右模式"]

var mode := 0
var _active_touch := -1
var _press := 0.0

func set_mode(m: int):
	mode = m
	queue_redraw()

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _process(delta: float) -> void:
	if _press <= 0.003:
		return
	_press = move_toward(_press, 0.0, delta * 14.0)
	queue_redraw()

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch == -1:
				_active_touch = event.index
				_press = 1.0
				UiKit.haptic(5)
				queue_redraw()
				accept_event()
		else:
			if event.index == _active_touch:
				_active_touch = -1
				mode = (mode + 1) % MODE_NAMES.size()
				mode_changed.emit(mode)
				queue_redraw()
				accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _active_touch:
			accept_event()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# 移动端 emulate_mouse_from_touch 会产生合成鼠标事件，吞掉防止漏到世界输入
		accept_event()

func _draw():
	var w := size.x
	var h := size.y
	var p := clampf(_press, 0.0, 1.0)
	var oy := p * 1.5
	# 半透明圆角底框（统一皮肤）：按下时缩短阴影、整体下压
	var style := UiKit.flat(0.56, 9, 2, Color(1, 1, 1, 0.26), Color(0.03, 0.04, 0.06, 0.68), 10.0)
	draw_style_box(style, Rect2(0, oy + 2.0, w, h))
	draw_style_box(style, Rect2(0, oy, w, h))
	# 左侧金色状态条 + 顶部玻璃高光
	draw_rect(Rect2(8.0, oy + 8.0, 3.0, h - 16.0), Color(1.0, 0.82, 0.34, 0.80), true)
	draw_line(Vector2(12.0, oy + 2.0), Vector2(w - 12.0, oy + 2.0),
		Color(1, 1, 1, 0.14), 1.2, true)
	# 主文字：当前模式
	draw_string(UiKit.font(), Vector2(20, h * 0.5 + 10 + oy), "WASD移动：%s" % MODE_NAMES[mode],
			HORIZONTAL_ALIGNMENT_LEFT, w - 56, 26, Color(1, 1, 1, 0.95))
	# 切换提示箭头
	draw_string(UiKit.font(), Vector2(w - 34, h * 0.5 + 10 + oy), "↻",
			HORIZONTAL_ALIGNMENT_LEFT, 26, 28, Color(1, 0.85, 0.35, 0.95))
