class_name NetDeathRecap extends Control
## P3e 死亡回放（客户端）：全屏压暗 + 共用 DeathRecapView（host 死亡跃迁推送 payload）。
## 复活（alive 回 1）自动关闭复位；Esc / × 可关。

const DeathRecapView = preload("res://scripts/ui/DeathRecapView.gd")

var _view = null
var _alive := 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_view = DeathRecapView.new()
	add_child(_view)
	_view.closed_by_user.connect(_close)
	NetSession.net_death_recap.connect(_on_recap)

## 公共入口：RPC 或快照兜底载荷都走这里；空载荷直接忽略，避免弹出空白面板
func show_payload(p: Dictionary) -> void:
	if p == null or (p as Dictionary).is_empty():
		return
	_on_recap(p)


func _on_recap(p: Dictionary) -> void:
	_view.set_data(p)
	_place()
	UiKit.show_panel(self, 0.18)
	queue_redraw()

func feed_alive(alive: int) -> void:
	if _alive == 0 and alive == 1:
		_alive = alive
		if _view != null:
			_view.visible = false
			_view.data = {}
		UiKit.hide_panel(self, 0.10)
		queue_redraw()
		return
	_alive = alive

func _close() -> void:
	UiKit.hide_panel(self, 0.10)
	UiKit.hide_panel(_view, 0.10)
	visible = false

func _place() -> void:
	if _view == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var sz: Vector2 = _view.size
	_view.position = ((vp - sz) * 0.5).floor() + Vector2(0, 8)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _view != null and _view.visible:
		_place()

func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.44))
