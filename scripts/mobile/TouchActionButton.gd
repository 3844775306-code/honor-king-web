class_name TouchActionButton
extends Control
const IconArt = preload("res://scripts/ui/IconArt.gd")
## 移动端通用动作按钮（普攻 / 召唤师技能 / 回城 / 主动装备）
## - emit_activated_on_press=true 时按下即触发一次（召唤师、回城、主动装）
## - 否则仅维护按住状态（普攻），由外部读取 is_held()

signal activated()
signal held_changed(held: bool)

const SIZE_V := 90.0

var label_text := "攻"
var icon_kind := ""           # 非空时画程序化功能图标（推塔/小兵/回城…），不再画文字
var name_text := ""           # 图标按钮下方的名称条（推塔/小兵/回城）
var dimmed := false           # 图标压暗（不可用状态）
var label_font_size := 0.0     # 0=自动按半径缩放；>0=固定字号（用于升级“+”等需要更醒目字号的按钮）
var color := Color(0.85, 0.6, 0.15, 0.85)
var emit_activated_on_press := false
var hold_to_act := true        # true=按住持续有效（普攻），false=按下触发一次
var toggled := false           # 开关选中态（推塔/小兵等模式键）：外圈金环 + 金字高亮

var _active := false
var _active_touch := -1
var _press := 0.0

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)
	# 尺寸由调用方通过 _anchor_br 指定（普攻 150 / 主动装 100 / 升级 44 等）；
	# 未显式设置时退回默认 90。
	if size.x <= 0.0:
		size = Vector2(SIZE_V, SIZE_V)
		custom_minimum_size = Vector2(SIZE_V, SIZE_V)

func is_held() -> bool:
	return _active

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch == -1:
				_active_touch = event.index
				_active = true
				_press = 1.0
				UiKit.haptic(6)
				if emit_activated_on_press:
					activated.emit()
				held_changed.emit(true)
				queue_redraw()
				accept_event()
		else:
			if event.index == _active_touch:
				_active_touch = -1
				_active = false
				held_changed.emit(false)
				queue_redraw()
				accept_event()
	elif event is InputEventScreenDrag:
		# 拖出按钮一定距离视为取消
		if event.index == _active_touch and not event.position.is_zero_approx():
			var center := size * 0.5
			if event.position.distance_to(center) > size.x * 0.9 and not hold_to_act:
				_active_touch = -1
				_active = false
				held_changed.emit(false)
				queue_redraw()
				accept_event()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# 移动端 emulate_mouse_from_touch 会产生合成鼠标事件，吞掉防止漏到世界输入
		accept_event()

func _process(delta: float) -> void:
	var target := 1.0 if _active else 0.0
	if absf(_press - target) < 0.003:
		return
	_press = move_toward(_press, target, delta * 14.0)
	queue_redraw()

func _draw():
	var p := clampf(_press, 0.0, 1.0)
	var center := size * 0.5 + Vector2(0, p * 1.8)
	var radius := minf(size.x, size.y) * 0.45 * (1.0 - p * 0.014)
	var base_col := color if _active else color.darkened(0.25)
	var accent := base_col.lightened(0.35)
	UiKit.touch_button_frame(self, center, radius, accent, p, 3.0, dimmed)
	# 开关选中态（推塔/小兵等模式键）：外圈金环 + 文字转金色
	if toggled:
		draw_arc(center, radius + 9, 0, TAU, 40, Color(1.0, 0.82, 0.25, 0.95), 4.0, true)
	if icon_kind != "":
		IconArt.draw_icon(self, center, radius * 0.98, icon_kind, dimmed)
		_draw_name(center, radius)
		return
	UiKit.touch_button_glass(self, center, radius, accent, p, dimmed)
	var fs := int(label_font_size) if label_font_size > 0.0 else int(maxf(22.0, radius * 0.58))
	# draw_string 的 pos.y 是基线；“+”字形重心在基线下方约 0.36em，
	# 若沿用中心上方 0.4em 的基线会让加号偏出圆心上方，故对 “+” 单独下移基线使其落在圆心。
	# （其他如“回城/血/装N”等 CJK 标签保持原位置，避免误动）
	var baseline := center.y - fs * 0.4
	if label_text == "+":
		baseline = center.y + fs * 0.36
	var tc := Color(1.0, 0.92, 0.5, 1.0) if toggled else Color.WHITE
	draw_string(UiKit.font(), Vector2(center.x - radius, baseline), label_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, tc)

## 图标按钮的名称条：按钮内侧底部圆角小条 + 描边白字
## 几何与 SkillTouchButton 的 name_below 名称条完全一致（同样 220 尺寸的回城/恢复才能对齐）
func _draw_name(center: Vector2, radius: float) -> void:
	if name_text == "":
		return
	var k := maxf(1.0, minf(size.x, size.y) / 110.0)
	var band_h := 30.0 * k
	var band := Rect2(center.x - radius * 0.92, center.y + radius - band_h + 2.0 * k,
		radius * 1.84, band_h)
	UiKit.chip(self, band, 0.74, 7.0 * k, color)
	var cfs := int(18.0 * k)
	var inner_w := band.size.x - 14.0 * k
	while cfs > int(12.0 * k) and UiKit.font().get_string_size(
			name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, cfs).x > inner_w:
		cfs -= 1
	var tw := UiKit.font().get_string_size(name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, cfs).x
	UiKit.text(self, Vector2(band.position.x + 7.0 * k + (inner_w - tw) * 0.5,
		band.position.y + band.size.y * 0.5 + cfs * 0.36), name_text, cfs, Color.WHITE)