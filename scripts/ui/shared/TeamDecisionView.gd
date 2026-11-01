class_name TeamDecisionView
extends Control
## 三端共享「团队决策面板」绘制（数据驱动）：标题 / 对局时间 / 分推模式 / 经济差 / 龙状态 /
## 我方与敌方英雄分路计划列表（host 与联机客户端输出同一份版面；host 由 UI_Manager 适配，
## 联机由 own.tt + 英雄快照适配，回放可只读复用）。
## 数据字典：
##   {"time": 对局秒, "mode": 模式名, "gold_diff": int, "dragon": bool,
##    "allies": ["[AI] 名字 (role) -> 分路", ...], "foes": [...]}

const PANEL_W := 420.0
const PANEL_H := 1000.0
const ROW_H := 20.0

var data: Dictionary = {}
var _f: Font = UiKit.font()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func set_data(d: Dictionary) -> void:
	data = d
	queue_redraw()

func _panel_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var h := minf(PANEL_H, vp.y - 40.0)
	return Rect2((vp.x - PANEL_W) * 0.5, (vp.y - h) * 0.5, PANEL_W, h)

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.42))
	var r := _panel_rect()
	draw_rect(r, Color(0.055, 0.075, 0.12, 0.96))
	draw_rect(r, Color(0.85, 0.68, 0.24, 0.9), false, 2.0)
	var x := r.position.x + 16.0
	var y := r.position.y + 20.0
	# 标题
	draw_string(_f, Vector2(x + 2.0, y + 2.0), "团队决策面板", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0, 0, 0, 0.6))
	draw_string(_f, Vector2(x, y), "团队决策面板", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.84, 0.2))
	y += 14.0
	var gt := float(data.get("time", 0.0))
	_small(x, y, "时间: %02d:%02d" % [int(gt) / 60, int(gt) % 60], Color.WHITE)
	y += ROW_H
	_small(x, y, "模式: " + str(data.get("mode", "—")), Color(0.85, 0.9, 1.0))
	y += ROW_H
	var diff := int(data.get("gold_diff", 0))
	var gcol := Color(0.4, 1.0, 0.45) if diff >= 0 else Color(1.0, 0.4, 0.35)
	_small(x, y, ("经济: 领先 +%d" % diff) if diff >= 0 else ("经济: 落后 %d" % diff), gcol)
	y += ROW_H
	var dragon := bool(data.get("dragon", false))
	_small(x, y, "龙: " + ("存活" if dragon else "已击杀"),
		Color(1.0, 0.62, 0.2) if dragon else Color(0.6, 0.62, 0.68))
	y += ROW_H + 8.0
	# 我方列表
	_small(x, y, "我方", Color(0.0, 0.86, 1.0))
	y += ROW_H
	for line in (data.get("allies", []) as Array):
		_small(x + 8.0, y, str(line), _row_color(str(line), true))
		y += ROW_H
	y += 8.0
	# 敌方列表
	_small(x, y, "敌方", Color(1.0, 0.42, 0.34))
	y += ROW_H
	for line in (data.get("foes", []) as Array):
		_small(x + 8.0, y, str(line), _row_color(str(line), false))
		y += ROW_H

func _row_color(line: String, ally: bool) -> Color:
	if line.begins_with("[AI]"):
		return Color(0.6, 0.9, 1.0) if ally else Color(1.0, 0.7, 0.7)
	return Color(1.0, 0.84, 0.3)

func _small(x: float, y: float, txt: String, col: Color) -> void:
	draw_string(_f, Vector2(x + 1.5, y + 1.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, 0.55))
	draw_string(_f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and (ev as InputEventKey).pressed \
			and (ev as InputEventKey).keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
