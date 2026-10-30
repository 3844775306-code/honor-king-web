class_name NetYuanliuSwitch extends Control
## M4-U 元流之子·泉水流派切换（接管客户端复刻主机 UI_Manager「流派·切换」钮 + show_yuanliu_pick 面板）。
## 只读呈现：每次快照由 NetClientBattle feed(_own)；读 own.name/x/z/alive/yl_pick 自行判定
## 「身处自家泉水且存活」→ 显示右上角常驻钮。点钮弹四选一面板（当前项高亮），确认走
## NetSession.send_command([C_YUANLIU_PICK, pick]) 由 host 权威校验后 set_yuanliu_pick（绝不本地改状态）。
## 几何/字号对齐 host：钮 = 右上 (-268..-12, 118..190) 按钮（host 字号 override 17 原始像素）；
## 面板 = 540×640 ×ui_scale 居中、左右内边距 26×us、上下 16×us、间距 10×us，
## 标题 24×us / 提示 13×us / 选项 92×us 高、16×us 字 / 取消 64×us 高、16×us 字。
## 挂在 CanvasLayer 104：高于触摸层(100)/C·T(101)/商店(102)/数值弹出(103)，低于结算(110)。

const FONT_CYAN := Color(0.55, 0.95, 1.0)
const FONT_WHITE := Color(1, 1, 1)
const FONT_DIM := Color(1, 1, 1, 0.72)
const PANEL_W := 540.0          # 同 host：540 * ui_scale
const PANEL_H := 640.0          # 同 host：640 * ui_scale

var _open := false            # 四选一面板是否打开（打开=全屏模态）
var _need := false            # 本帧是否应展示（泉水+元流+存活）
var _cur := "生机"            # host 当前流派（own.yl_pick）
var _f: Font = null

# 同主机 UI_Manager.ui_scale()
func _us() -> float:
	return UiKit.scale()

func _ready() -> void:
	_f = UiKit.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()

# —— 每帧喂入 own（NetClientBattle._process 已接管且对局中调用；未接管传空 dict 隐藏）——
func feed(o: Dictionary) -> void:
	if _f == null:
		_f = UiKit.font()
	var name := str(o.get("name", ""))
	var alive := int(o.get("alive", 1))
	var team := int(o.get("team", 0))
	var x := float(o.get("x", 0.0))
	var z := float(o.get("z", 0.0))
	_cur = str(o.get("yl_pick", "生机"))
	var fx := -58.0 if team == 0 else 58.0
	var fz := 58.0 if team == 0 else -58.0
	var near_fountain := absf(x - fx) <= 5.0 and absf(z - fz) <= 5.0
	_need = name == "元流之子" and alive == 1 and near_fountain
	if not _need and _open:
		_open = false
	_refresh_shape()
	queue_redraw()

func _refresh_shape() -> void:
	if not _need:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	if _open:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		# 收缩为右上角 chip（y 118..190，与主机 UI_Manager._create_yuanliu_switch_btn 同坐标）
		anchor_left = 0.0; anchor_top = 0.0
		anchor_right = 0.0; anchor_bottom = 0.0
		offset_left = area.x - 268.0
		offset_top = 118.0
		offset_right = area.x - 12.0
		offset_bottom = 190.0

func _text(pos: Vector2, txt: String, sz: float, col: Color) -> void:
	if _f == null:
		return
	draw_string(_f, pos + Vector2(1.5, 1.5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.55))
	draw_string(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _draw() -> void:
	if _f == null:
		return
	# 同 host _update_yuanliu_switch_btn：不在「自家泉水+存活+元流之子」时整个钮隐藏
	if not _need:
		return
	if _open:
		_draw_modal()
	else:
		_draw_chip()

# —— 关闭态：右上角小钮「流派·切换」（同 host Button：font_size override 17、居中）——
func _draw_chip() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.02, 0.06, 0.12, 0.92))
	draw_rect(r, Color(1.0, 0.82, 0.35, 0.9), false, 2.0)
	var cx: float = r.size.x * 0.5
	var label := "流派·切换"
	var fs := 17.0   # 同 host：_yl_switch_btn 字号 override 17（原始像素，不乘 ui_scale）
	var w: float = _f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(Vector2(cx - w * 0.5, r.size.y * 0.5 + fs * 0.36), label, fs, Color(1.0, 0.92, 0.6))

# —— 打开态：全屏模态（dim + 面板 + 四选一 + 取消）——
func _draw_modal() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	var lay := _layout(area)
	draw_rect(Rect2(Vector2.ZERO, area), Color(0, 0, 0, 0.62))
	var pr: Rect2 = lay["panel"]
	draw_rect(pr, Color(0, 0, 0, 0.92))   # 同 host _apply_panel_style(panel, 0.92)
	draw_rect(pr, Color(1, 1, 1, 0.16), false, 3.0)
	var cx: float = pr.position.x + pr.size.x * 0.5
	var us := _us()
	var tfs := 24.0 * us      # host title: _apply_label_style(..., 24, 青)
	_center_text(cx, float(lay["title_y"]), "万物为流 · 流派切换", tfs, FONT_CYAN)
	var hfs := 13.0 * us      # host hint: 13×us 白 0.72
	var hlines: Array = lay["hint_lines"]
	for i in range(hlines.size()):
		_center_text(cx, float(lay["hint_y"]) + i * hfs * 1.35, str(hlines[i]), hfs, FONT_DIM)
	var ofs := 16.0 * us      # host 选项按钮字 16×us
	var rows: Array = lay["rows"]
	var opts := _opts()
	for i in range(rows.size()):
		var rr: Rect2 = rows[i]
		var o: Array = opts[i]
		draw_rect(rr, Color(1, 1, 1, 0.05))
		draw_rect(rr, o[2].darkened(0.15), false, 2.0)
		var glyph: String = o[0]
		var txt := ("✔ 当前·【%s】  %s" if glyph == _cur else "【%s】  %s") % [glyph, o[1]]
		_text(Vector2(rr.position.x + 18.0, rr.position.y + (rr.size.y + ofs * 0.72) * 0.5), txt, ofs, o[2])
	# 取消钮（同 host：高 64×us、字 16×us）
	var cr: Rect2 = lay["cancel"]
	draw_rect(cr, Color(1, 1, 1, 0.08))
	draw_rect(cr, Color(1, 1, 1, 0.3), false, 2.0)
	var ct := "取消"
	var cts := _f.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, ofs)
	_text(Vector2(pr.position.x + (pr.size.x - cts.x) * 0.5, cr.position.y + (cr.size.y + ofs * 0.72) * 0.5),
			ct, ofs, Color(1, 1, 1, 0.85))

func _center_text(cx: float, baseline_y: float, txt: String, sz: float, col: Color, max_w: float = -1.0) -> void:
	var s: float = sz
	if max_w > 0.0:
		var str_w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if str_w > max_w:
			s = sz * max_w / str_w
	var ts := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, s)
	_text(Vector2(cx - ts.x * 0.5, baseline_y), txt, s, col)

func _opts() -> Array:
	return [
		["生机", "额外最大生命 +300 → +600", Color(0.45, 0.95, 0.62)],
		["穿心", "额外物理攻击 +30 → +60", Color(1.0, 0.55, 0.38)],
		["迅疾", "移动速度 +12.5 → +25", Color(0.55, 0.9, 1.0)],
		["凝神", "冷却缩减 +5% → +10%", Color(0.8, 0.62, 1.0)],
	]

# 提示文案（同 host show_yuanliu_pick 的 reopen 分支）按面板内容宽折行
func _hint_lines(max_w: float, fs: float) -> Array:
	var txt := "身处自家泉水：可随时更换被动强化路线，确认后立即生效；离泉后本次选择持续到下次回泉。"
	var out: Array = []
	var line := ""
	var w := 0.0
	for i in txt.length():
		var ch := txt[i]
		var cw: float = _f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w + cw > max_w and line != "":
			out.append(line)
			line = ch
			w = cw
		else:
			line += ch
			w += cw
	if line != "":
		out.append(line)
	return out

# 面板内所有几何集中在此（_draw_modal 与 _gui_input 共用，避免两处漂移）
func _layout(area: Vector2) -> Dictionary:
	var us := _us()
	var pw := PANEL_W * us
	var ph := PANEL_H * us
	var px := (area.x - pw) * 0.5
	var py := (area.y - ph) * 0.5
	var pad_l := 26.0 * us
	var pad_t := 16.0 * us
	var sep := 10.0 * us
	var tfs := 24.0 * us
	var hfs := 13.0 * us
	var title_base := py + pad_t + tfs * 0.82
	var hint_y := title_base + sep + hfs * 0.82
	var lines := _hint_lines(pw - 2.0 * pad_l, hfs)
	var cy := hint_y + lines.size() * hfs * 1.35 + sep
	var row_h := 92.0 * us     # 同 host 选项按钮 custom_minimum_size.y = 92 * rs
	var cancel_h := 64.0 * us  # 同 host 取消按钮 64 * rs
	var rows: Array = []
	for i in range(_opts().size()):
		rows.append(Rect2(px + pad_l, cy, pw - 2.0 * pad_l, row_h))
		cy += row_h + sep
	var cancel := Rect2(px + pad_l, cy, pw - 2.0 * pad_l, cancel_h)
	return {"panel": Rect2(px, py, pw, ph), "title_y": title_base, "hint_y": hint_y,
			"hint_lines": lines, "rows": rows, "cancel": cancel}

func _row_rects() -> Array:
	# 与 _draw_modal 同式：返回 [{r:Rect2, pick:String}]
	var vp := get_viewport()
	var out: Array = []
	if vp == null:
		return out
	var lay := _layout(vp.get_visible_rect().size)
	for i in range(_opts().size()):
		out.append({"r": lay["rows"][i], "pick": str(_opts()[i][0])})
	return out

func _gui_input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not press:
		return
	if _open:
		var pos := _event_pos(ev)
		for hit in _row_rects():
			var hr: Rect2 = hit.r
			if hr.has_point(pos):
				var pk: String = hit.pick
				_open = false
				_refresh_shape()
				queue_redraw()
				NetSession.send_command([NetSession.C_YUANLIU_PICK, pk])
				accept_event()
				return
		# 空白/dim：取消并吞掉（模态挡世界输入）
		_open = false
		_refresh_shape()
		queue_redraw()
		accept_event()
	else:
		# 小钮区内：打开面板
		_open = true
		_refresh_shape()
		queue_redraw()
		accept_event()

func _event_pos(ev: InputEvent) -> Vector2:
	if ev is InputEventMouseButton:
		return (ev as InputEventMouseButton).position
	if ev is InputEventScreenTouch:
		return (ev as InputEventScreenTouch).position
	return Vector2.ZERO
