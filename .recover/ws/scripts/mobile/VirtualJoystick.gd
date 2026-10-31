extends Control
## 固定式虚拟摇杆（移动端左下角移动区 / 桌面鼠标拖动）
## 注意：故意不声明 class_name —— Godot 4.6+ 内置了同名原生类 VirtualJoystick，
## 脚本再用 class_name VirtualJoystick 会 Parse Error（hides a native class），
## 导致脚本加载失败、节点上没有 move_vector。需要引用本脚本时用 preload 路径。
## 固定式虚拟摇杆（移动端左下角移动区 / 桌面鼠标拖动）
## - 底座中心固定（在控件正中，控件被锚定到屏幕固定位置），不随按下位置跳变
## - 激活区：仅当手指/鼠标按下点与底座中心距离 < ACTIVATE_RADIUS 才激活摇杆
##   （在激活半径之外的触摸不会抢占摇杆，可留给世界点击等）
## - 摇杆头绕固定中心移动、被限制在 MAX_RADIUS 内
## 语义：move_vector.y 正 = 屏幕向上（Godot 屏幕坐标 y 向下为正，这里已翻转）

const ACTIVATE_RADIUS := 300.0    # 摇杆激活半径：按下点须离中心小于此值（扩大为最初版）
const MAX_RADIUS := 120.0         # 摇杆头最大行程半径（虚拟分辨率单位）
const KNOB_RADIUS := 48.0
const BASE_RADIUS := 84.0
const ACCENT := Color(0.52, 0.82, 1.0, 0.95)

var move_vector := Vector2.ZERO   # 归一化（-1..1），y 向上为正
var _active := false
var _active_touch := -1
var _knob_pos := Vector2.ZERO
var _visual_pos := Vector2.ZERO    # 松开后回弹动画位置（输入仍用 _knob_pos，保持零延迟）
var _press := 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	_visual_pos = get_home()
	set_process(true)

func _process(delta: float) -> void:
	if _active:
		_press = 1.0
		return
	var home := get_home()
	var moving := _visual_pos.distance_squared_to(home) > 0.04
	if moving:
		_visual_pos = _visual_pos.lerp(home, clampf(delta * 18.0, 0.0, 1.0))
		if _visual_pos.distance_squared_to(home) <= 0.04:
			_visual_pos = home
	var pressing := _press > 0.004
	if pressing:
		_press = move_toward(_press, 0.0, delta * 13.0)
	if moving or pressing:
		queue_redraw()

# 固定底座中心 = 控件中心（控件由 TouchController 锚定成以该中心为圆心的方形，
# 方形边长 = 2 * ACTIVATE_RADIUS，因此按下点只要落在激活圆内即可）
func get_home() -> Vector2:
	return size * 0.5

func is_active() -> bool:
	return _active

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch == -1:
				if event.position.distance_to(get_home()) < ACTIVATE_RADIUS:
					_active_touch = event.index
					_active = true
					_press = 1.0
					_update_knob(event.position)
					UiKit.haptic(6)
				accept_event()
		else:
			if event.index == _active_touch:
				_active_touch = -1
				_active = false
				_knob_pos = get_home()
				move_vector = Vector2.ZERO
				UiKit.haptic(4)
				queue_redraw()
			accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _active_touch:
			_update_knob(event.position)
		accept_event()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# 移动端 emulate_mouse_from_touch 会产生合成鼠标事件，吞掉防止漏到世界输入
		accept_event()

# 以固定中心为基准计算摇杆头位置与移动向量（拖出最大半径外则钳到边缘）
func _update_knob(finger: Vector2):
	var home := get_home()
	var delta: Vector2 = finger - home
	var len: float = delta.length()
	if len > MAX_RADIUS:
		delta = delta / len * MAX_RADIUS
	_knob_pos = home + delta
	_visual_pos = _knob_pos
	move_vector = Vector2(delta.x, -delta.y) / MAX_RADIUS
	queue_redraw()

func _draw():
	var home := get_home()
	var p := clampf(_press, 0.0, 1.0)
	# 激活范围：虚线仪表圈（按下时提亮）
	UiKit.touch_dash_ring(self, home, ACTIVATE_RADIUS,
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.075 + 0.075 * p), 2.0, 48)
	# 行程刻度圈
	UiKit.touch_dash_ring(self, home, MAX_RADIUS + 30.0,
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.10 + 0.08 * p), 1.5, 30)
	# 底座：金属外框 + 玻璃主体
	UiKit.touch_button_frame(self, home, BASE_RADIUS, ACCENT, p, 2.0, false)
	UiKit.touch_button_glass(self, home, BASE_RADIUS, ACCENT, p, false)
	# 内圈 + 八向刻度，像一块真正的摇杆底盘
	draw_arc(home, BASE_RADIUS * 0.67, 0, TAU, 44,
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18 + 0.10 * p), 1.5, true)
	draw_circle(home, 9.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.15 + 0.12 * p))
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		var inner := home + d * BASE_RADIUS * 0.76
		var outer := home + d * BASE_RADIUS * 0.92
		draw_line(inner, outer, Color(1, 1, 1, 0.22 + 0.16 * p), 2.0, true)
	# 当前推向：底座外侧亮弧，强化“往哪推”的反馈
	if _active and _visual_pos.distance_to(home) > 4.0:
		var sd := _visual_pos - home
		var sa := atan2(sd.y, sd.x)
		draw_arc(home, BASE_RADIUS + 7.0, sa - 0.34, sa + 0.34, 18,
			Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.34), 5.0, true)
	# 摇杆头：静止时半透明常显，按下后变亮并带高光
	var kp := _visual_pos
	var ka := 0.72 + 0.28 * p
	var kr := KNOB_RADIUS * (1.0 - 0.045 * p)
	draw_circle(kp + Vector2(0, 7), kr * 1.06, Color(0, 0, 0, 0.30 * ka))
	draw_circle(kp, kr + 9.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.05 + 0.09 * p))
	draw_circle(kp, kr + 2.0, Color(0.015, 0.020, 0.032, 0.94))
	draw_circle(kp, kr, Color(0.26, 0.34, 0.46, 0.96 * ka))
	draw_circle(kp - Vector2(0, kr * 0.12), kr * 0.88, Color(0.44, 0.56, 0.70, 0.30 * ka))
	draw_circle(kp + Vector2(0, kr * 0.14), kr * 0.74, Color(0.08, 0.11, 0.17, 0.18 * ka))
	draw_arc(kp, kr, 0, TAU, 48, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.78 * ka),
		maxf(2.0, kr * 0.06), true)
	draw_arc(kp - Vector2(0, kr * 0.18), kr * 0.76, -PI * 0.92, -PI * 0.08, 24,
		Color(1, 1, 1, 0.34 * ka), maxf(2.0, kr * 0.07), true)
	# 防滑颗粒 + 中心点
	for i in range(4):
		var a := TAU * float(i) / 4.0 + PI * 0.25
		draw_circle(kp + Vector2(cos(a), sin(a)) * kr * 0.48,
			maxf(1.5, kr * 0.045), Color(1, 1, 1, 0.22 * ka))
	draw_circle(kp, maxf(2.0, kr * 0.12), Color(1, 1, 1, 0.26 * ka))
