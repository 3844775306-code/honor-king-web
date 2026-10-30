class_name NetRosterPanel
extends Control
## 客户端 C（属性）/ T（队伍）面板：全屏压暗 + 共用 RosterView（双列分路对位）
## 数据：host _rpc_roster 行载荷（NetSession._pack_roster_row）→ 转成 RosterView 行字典。

const RosterView = preload("res://scripts/ui/RosterView.gd")

var view := "attr"          # "attr"=属性面板 / "team"=队伍面板（同视图，标题不同）
var _v = null
var self_net := -1      # 本端 net_id：与自己同 id 的行用绿色底板
var _req := 0.0
var _rows: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_v = RosterView.new()
	add_child(_v)
	_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_v.closed_by_user.connect(hide_panel)
	set_process(false)

func show_panel(v: String) -> void:
	view = v
	visible = true
	UiKit.show_panel(self, 0.15)
	if _v != null and is_instance_valid(_v):
		UiKit.show_panel(_v, 0.15)
	_req = 99.0
	set_process(true)
	queue_redraw()

func hide_panel() -> void:
	UiKit.hide_panel(self, 0.12)
	UiKit.hide_panel(_v, 0.12)
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	if not visible:
		return
	_req -= delta
	if _req > 0.0:
		return
	_req = 0.5
	NetSession.send_command([NetSession.C_ROSTER])
	var p: Array = NetSession.get_roster_payload()
	if p.size() > 0:
		_rows = p
		_apply()

func _apply() -> void:
	var out: Array = []
	for r in _rows:
		if r is Array and (r as Array).size() >= 10:
			out.append(_row_from_net(r as Array))
	if _v != null:
		_v.set_rows(out, view)

func _row_from_net(r: Array) -> Dictionary:
	var eq: Array = []
	for item_id in (r[10] as Array):
		var it: Dictionary = ItemDatabase.get_item(str(item_id))
		eq.append([str(it.get("name", item_id)), int(it.get("tier", 1))])
	var hp := float(r[4])
	var mhp := float(r[5])
	return {
		"name": str(r[1]), "hero": str(r[1]), "team": int(r[2]), "level": int(r[3]),
		"own": self_net >= 0 and int(r[0]) == self_net,
		"hp_ratio": hp / mhp if mhp > 0.0 else 1.0,
		"k": int(r[6]), "d": int(r[7]), "a": int(r[8]),
		"gold": int(r[16]) if r.size() > 16 else int(r[9]),
		"is_ai": bool(int(r[17])) if r.size() > 17 else false,
		"role": str(r[18]) if r.size() > 18 else "",
		"dead": bool(int(r[19])) if r.size() > 19 else false,
		"respawn": float(r[20]) if r.size() > 20 else 0.0,
		"chips": r[22] if r.size() > 22 else [],
		"skills": r[27] if r.size() > 27 else [],
		"lane": int(r[26]) if r.size() > 26 else -1,
		"equips": eq,
	}

func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		hide_panel()
		get_viewport().set_input_as_handled()

func _gui_input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
		or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if press:
		hide_panel()
		accept_event()

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.4))
