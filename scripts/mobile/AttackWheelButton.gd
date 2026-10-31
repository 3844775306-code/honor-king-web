class_name AttackWheelButton
extends Control
## 移动端普攻轮盘（王者荣耀式）：
## - 按住持续普攻（is_held，由 Hero 读取）
## - 拖动进入选敌瞄准：画出方向指示，外部据此精准锁定目标
## - 松手：final_drag=松手时的拖拽向量；cancelled=「拖出又拖回按钮」→ 取消选敌
## - 点按（未拖出）不改变目标锁定，仅普攻当前目标

signal pressed_changed(held: bool)
# 王者荣耀式松手选敌：final_drag=松手时的拖拽向量；cancelled=「拖出又拖回按钮」→ 取消选敌
signal released(final_drag: Vector2, cancelled: bool)

const TAP_THRESHOLD := 30.0      # 超过此拖拽距离才算“拖出去”（进入选敌）
const CANCEL_RADIUS := 40.0      # 松手位置距按下起点小于此值且拖出去过 → 视为拖回按钮，取消
const MIN_HOLD_MS := 120         # 快速点按也至少保持 120ms，保证 Hero 的物理帧能读到一次普攻

var label_text := "普攻"
var color := Color(0.9, 0.4, 0.3, 0.85)

# 普攻键上的数值说明：普攻伤害 + 攻击速度（每次/秒），由 TouchController 每帧推送
var show_damage := 0
var show_speed := 0.0
# 强化普攻就绪（数值类强化/跳跃类强化）：伤害数值显示强化后数值，文字与外圈转金色
var enhanced := false
# 装备被动影响普攻的小字行（小图标+装备短名+实时效果数值），每帧由 TouchController 推送
var _item_rows: Array = []
var _item_sig := ""

func set_battle_stats(dmg: int, speed_per_sec: float, is_enhanced: bool = false):
	if dmg == show_damage and absf(speed_per_sec - show_speed) < 0.001 and is_enhanced == enhanced:
		return
	show_damage = dmg
	show_speed = speed_per_sec
	enhanced = is_enhanced
	queue_redraw()

# 装备被动小字行内容更新：内容未变化（数值/就绪状态均同）则不重绘，避免每帧闪烁
func set_item_rows(rows: Array):
	var sig := ""
	for r in rows:
		var d: Dictionary = r
		sig += str(d.get("k", "")) + "|" + str(d.get("name", "")) + "|" + str(d.get("txt", "")) + "|" + str(d.get("armed", true)) + "\n"
	if sig != _item_sig:
		_item_sig = sig
		_item_rows = rows
		queue_redraw()

var _active := false
var _active_touch := -1
var _origin := Vector2.ZERO      # 按下起点（局部坐标）
var _drag := Vector2.ZERO        # 当前拖拽偏移
var _max_drag := 0.0             # 本次手势的最大拖拽距离
var _press := 0.0
var _held_until := 0             # 点按保持窗口（毫秒），避免极短触摸被物理帧漏掉

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if _active else 0.0
	if absf(_press - target) < 0.003:
		return
	_press = move_toward(_press, target, delta * 14.0)
	queue_redraw()

func is_held() -> bool:
	return _active or Time.get_ticks_msec() < _held_until

func get_drag() -> Vector2:
	return _drag if _active else Vector2.ZERO

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch == -1:
				_active_touch = event.index
				_active = true
				_press = 1.0
				_origin = event.position
				_drag = Vector2.ZERO
				_max_drag = 0.0
				_held_until = Time.get_ticks_msec() + MIN_HOLD_MS
				UiKit.haptic(6)
				pressed_changed.emit(true)
				queue_redraw()
				accept_event()
		else:
			if event.index == _active_touch:
				var final_drag: Vector2 = event.position - _origin
				var cancelled: bool = _max_drag > TAP_THRESHOLD and final_drag.length() < CANCEL_RADIUS
				_active_touch = -1
				_active = false
				_drag = Vector2.ZERO
				_max_drag = 0.0
				pressed_changed.emit(false)
				released.emit(final_drag, cancelled)
				queue_redraw()
				accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _active_touch:
			_drag = event.position - _origin
			_max_drag = maxf(_max_drag, _drag.length())
			queue_redraw()
			accept_event()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# 移动端 emulate_mouse_from_touch 会产生合成鼠标事件，吞掉防止漏到世界输入
		accept_event()

func _draw():
	var p := clampf(_press, 0.0, 1.0)
	var center := size * 0.5 + Vector2(0, p * 1.8)
	var radius := minf(size.x, size.y) * 0.45 * (1.0 - p * 0.022)
	var base_col := color if _active else color.darkened(0.25)
	# 外圈：强化普攻就绪时外圈与伤害数字转金色（数值也已切换为强化后伤害）
	var ring_col := Color(1.0, 0.85, 0.3) if enhanced else base_col.lightened(0.3)
	var ring_w := 5.0 if enhanced else 3.0
	UiKit.touch_button_frame(self, center, radius, ring_col, p, ring_w, false)
	UiKit.touch_button_glass(self, center, radius, ring_col, p, false)
	var fs := int(maxf(22.0, radius * 0.5))
	# 普攻图标：交叉双剑（矢量绘制，压在文字上方）
	_draw_attack_glyph(Vector2(center.x, center.y - radius * 0.40), radius * 0.23, Color(1, 1, 1, 0.92))
	draw_string(UiKit.font(), Vector2(center.x - radius, center.y + fs * 0.16), label_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, Color.WHITE)
	# 普攻键数值说明：中心文字下方两行小字（强化=金色/普通=白色，攻速青色）
	if show_damage > 0 or show_speed > 0.0:
		var fs2 := int(maxf(12.0, radius * 0.22))
		var line_y := center.y + fs * 0.16 + fs2 + 4.0
		var dmg_col := Color(1.0, 0.88, 0.35, 1.0) if enhanced else Color(0.93, 0.93, 0.93, 0.92)
		draw_string(UiKit.font(), Vector2(center.x - radius, line_y),
			"伤害 %d" % show_damage, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs2, dmg_col)
		draw_string(UiKit.font(), Vector2(center.x - radius, line_y + fs2 + 2),
			"攻速 %.2f/秒" % show_speed, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs2, Color(0.55, 0.9, 1.0, 0.95))
	# 装备被动对普攻的影响：攻速行下方的小字行（每件生效装一行）
	_draw_item_rows(center, radius)
	# 拖动选敌：方向指示线 + 摇杆头样式小圆（像移动轮盘一样）
	if _active and _drag.length() > TAP_THRESHOLD:
		var d := _drag.normalized()
		var knob := center + d * radius * 0.85
		var kr := maxf(20.0, radius * 0.18)
		draw_line(center, knob, Color(1.0, 0.85, 0.3, 0.85), maxf(3.0, radius * 0.022))
		draw_circle(knob + Vector2(0, 3), kr * 1.05, Color(0, 0, 0, 0.28))
		draw_circle(knob, kr + 2, Color(0.02, 0.025, 0.04, 0.9))
		draw_circle(knob, kr, Color(0.30, 0.37, 0.48, 0.94))
		draw_circle(knob - Vector2(0, kr * 0.12), kr * 0.86, Color(0.55, 0.64, 0.76, 0.28))
		draw_arc(knob, kr, 0, TAU, 32, Color(1.0, 0.85, 0.3, 0.82), maxf(2.0, kr * 0.08), true)
		draw_arc(knob - Vector2(0, kr * 0.18), kr * 0.74, -PI * 0.9, -PI * 0.1, 18,
			Color(1, 1, 1, 0.30), maxf(1.5, kr * 0.08), true)

# 普攻图标：交叉双剑（纯矢量，无美术资源）
func _draw_attack_glyph(pc: Vector2, r: float, col: Color) -> void:
	var lw := maxf(2.0, r * 0.22)
	for sgn in [-1.0, 1.0]:
		var dir := Vector2(float(sgn), -1.0).normalized()
		var tip := pc + dir * r
		var butt := pc - dir * r * 0.78
		draw_line(butt, tip, col, lw)
		draw_circle(tip, lw * 0.75, col)
		# 护手（与剑身垂直的短横）
		var perp := Vector2(-dir.y, dir.x)
		var guard := pc - dir * r * 0.30
		draw_line(guard - perp * r * 0.34, guard + perp * r * 0.34, col, lw)
		# 剑柄末端小球
		draw_circle(butt, lw * 0.6, Color(1, 1, 1, 0.85))
	draw_arc(pc, r * 0.20, 0, TAU, 16, Color(1, 1, 1, 0.30), lw * 0.8)

# ---------------- 装备被动小字行绘制（攻速行下方，逐行 图标+装备短名+效果小字） ----------------
func _draw_item_rows(center: Vector2, radius: float):
	var rows: Array = _item_rows
	if rows.is_empty():
		return
	var fs := int(maxf(22.0, radius * 0.5))
	var fs2 := int(maxf(12.0, radius * 0.22))
	# 攻速行最后一行基线之下 6px 开始，向下最多到圆内 0.96 半径处
	var top_y := center.y + fs * 0.16 + fs2 * 3.0 + 10.0
	var bottom := center.y + radius * 0.96
	var avail := bottom - top_y
	if avail < 10.0:
		return
	var n := rows.size()
	# 先按竖直高度估字号（每行 ~1.5 倍字号），再按最宽行宽度收缩；下限 8
	var fs_i := int(maxf(8.0, minf(16.0, avail / (float(n) * 1.5))))
	var max_w := radius * 1.9
	for _pass in 2:
		var widest := 0.0
		for r in rows:
			var d: Dictionary = r
			var w := UiKit.font().get_string_size(String(d.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_i).x
			w += UiKit.font().get_string_size(String(d.get("txt", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs_i).x
			widest = maxf(widest, w)
		if widest > max_w and fs_i > 8:
			fs_i = maxi(8, int(fs_i * max_w / widest))
	var row_h := float(fs_i) * 1.5
	var ic := float(fs_i) * 1.2
	var name_gap := 4.0
	var txt_gap := 4.0
	for idx in n:
		var d: Dictionary = rows[idx]
		var name := String(d.get("name", ""))
		var txt := String(d.get("txt", ""))
		var col: Color = d.get("col", Color(1.0, 0.6, 0.3))
		var armed := bool(d.get("armed", true))
		var eff_col := col if armed else Color(col.r, col.g, col.b, 0.45)
		var name_col := Color(1, 1, 1, 0.92) if armed else Color(1, 1, 1, 0.5)
		var fname := UiKit.font()
		var nw := fname.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_i).x
		var tw := fname.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_i).x
		var row_w := ic
		if nw > 0:
			row_w += nw + name_gap
		if tw > 0:
			row_w += tw + txt_gap
		var row_top := top_y + row_h * float(idx)
		var x := center.x - row_w * 0.5
		_draw_mini_glyph(String(d.get("k", "phys")), Vector2(x + ic * 0.5, row_top + fs_i * 0.55), ic * 0.5, eff_col)
		var tx := x + ic
		var base_y := row_top + float(fs_i)
		if nw > 0:
			draw_string(fname, Vector2(tx, base_y), name, HORIZONTAL_ALIGNMENT_LEFT, nw, fs_i, name_col)
			tx += nw + name_gap
		if tw > 0:
			draw_string(fname, Vector2(tx, base_y), txt, HORIZONTAL_ALIGNMENT_LEFT, tw, fs_i, eff_col)

# 行首小图标：仅用矢量基本形状，与 _draw_fx_glyph 同一风格
func _draw_mini_glyph(kind: String, pc: Vector2, r: float, col: Color):
	var lw := maxf(1.2, r * 0.28)
	match kind:
		"magic":
			# 法术：四角星
			var pts := PackedVector2Array()
			for i in 8:
				var ang := TAU * float(i) / 8.0 + PI * 0.25
				var rr := r if i % 2 == 0 else r * 0.35
				pts.append(pc + Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(pts, col)
		"heal":
			# 回血：十字圈
			draw_arc(pc, r, 0, TAU, 16, col, lw, true)
			draw_line(pc + Vector2(-r * 0.4, 0), pc + Vector2(r * 0.4, 0), col, lw)
			draw_line(pc + Vector2(0, -r * 0.4), pc + Vector2(0, r * 0.4), col, lw)
		"as":
			# 攻速：时钟
			draw_arc(pc, r, 0, TAU, 16, col, lw, true)
			draw_line(pc, pc + Vector2(0, -r * 0.5), col, lw * 0.9)
			draw_line(pc, pc + Vector2(r * 0.35, r * 0.05), col, lw * 0.9)
		"hunt":
			# 狩猎灼烧：水滴焰
			var pts := PackedVector2Array([pc + Vector2(0, -r), pc + Vector2(r * 0.75, r * 0.15), pc + Vector2(0, r), pc + Vector2(-r * 0.75, r * 0.15)])
			draw_colored_polygon(pts, col)
			draw_circle(pc + Vector2(0, r * 0.2), r * 0.26, Color(1.0, 0.9, 0.45, 0.95))
		"phys":
			# 物理：上指小剑
			var pts := PackedVector2Array([pc + Vector2(-r * 0.26, -r * 0.9), pc + Vector2(r * 0.26, -r * 0.9), pc + Vector2(r * 0.26, r * 0.6), pc + Vector2(-r * 0.26, r * 0.6)])
			draw_colored_polygon(pts, col)
			draw_line(pc + Vector2(-r * 0.6, r * 0.15), pc + Vector2(r * 0.6, r * 0.15), col, lw)
			draw_line(pc + Vector2(-r * 0.18, r * 0.85), pc + Vector2(r * 0.18, r * 0.85), col, lw)
		_:
			# 兜底：圆点
			draw_circle(pc, r * 0.6, col)
