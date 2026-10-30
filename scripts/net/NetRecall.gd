class_name NetRecall extends Control
## P3e 回城指示器：host own.recalling/recall_ratio 喂入（recall_ratio=(1-recall_timer/7)→0..1 走完）。
## 复刻主机 UI_Manager._create_recall_indicator + _update 段的回城条：屏幕正中 100×100（×ui_scale）暗色圆
## + 顺时针进度填充（Color(0.15,0.4,0.95,0.75)）+ 居中剩余秒数（"%.1fs"，字号 14×ui_scale，黑描边 2）。
## 仅 recalling 时可见。

const SIZE_V := 100.0           # 同 host：recall_indicator.size = 100×100
const RECALL_DURATION := 7.0    # 同 Hero.RECALL_DURATION（host 用 hero.recall_timer 反推剩余）

var _active := false
var _ratio := 0.0
var _f := UiKit.font()

# 同主机 UI_Manager.ui_scale()：maxf(1.0, 视口宽/2400) * 1.35
func _us() -> float:
	return UiKit.scale()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func feed(recalling: int, ratio: float) -> void:
	_active = recalling != 0
	_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	if not _active:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	var sz := SIZE_V * _us()
	var center := area * 0.5
	var radius := sz * 0.5
	var frac := clampf(_ratio, 0.0, 1.0)
	# 背景暗色圆（同 host bg：Color(0,0,0,0.55)）
	draw_circle(center, radius, Color(0, 0, 0, 0.55))
	# 顺时针进度扇形（同 host TextureProgressBar 填充色 + FILL_CLOCKWISE）
	if frac > 0.0:
		var steps := maxi(3, int(56.0 * frac))
		var pts := PackedVector2Array()
		pts.append(center)
		for i in range(steps + 1):
			var ang := -PI * 0.5 + TAU * frac * float(i) / float(steps)
			pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
		draw_colored_polygon(pts, Color(0.15, 0.4, 0.95, 0.75))
	# 居中剩余秒数（同 host recall_label："%.1fs" % recall_timer，字号 14×ui_scale、白字黑描边 2）
	var txt := "%.1fs" % ((1.0 - frac) * RECALL_DURATION)
	var fs := int(round(14.0 * _us()))
	var tw := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(center.x - tw * 0.5, center.y + fs * 0.36)
	draw_string_outline(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 2, Color.BLACK)
	draw_string(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
