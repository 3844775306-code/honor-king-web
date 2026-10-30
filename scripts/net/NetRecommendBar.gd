class_name NetRecommendBar extends Control
## P3d+：主界面右上「金币 chip + 推荐装备 + 购买」带（host UI_Manager.gd:477-516 同款位置/交互）。
## 数据由 host own.rb 每帧烘焙（UI_Manager._compute_recommended_bundle 单源，host 主界面同样调用），
## 客户端无 ItemDatabase 合成链、只纯绘制：点 chip = 开/关商店（signal），点“+” = C_BUY 推荐 id。
## Layer 65：高于 buff 行(60)/战报(40)，低于目标面板(55)上的小地图(80)与各模态（商店 102/结算 110）。
## 根 Control 全屏但 MOUSE_FILTER_IGNORE —— 只有 chip 与“+”两个小块 STOP，不拦小地图/世界点击。

const TouchActionButtonScript = preload("res://scripts/mobile/TouchActionButton.gd")

signal shop_requested   # 点金币 chip：由 NetClientBattle 接去切商店（商店开着时 chip 被 102 层面板遮住点不到）

var _f := UiKit.font()
var _gold := 0
var _rec_id := ""
var _rec_text := ""
var _rec_show := false
var _plus: TouchActionButtonScript
var _chip: GoldChip
var _card: RecCard


# 同主机 UI_Manager.ui_scale()：以虚拟宽 2400 为 1.0 再乘固定放大系数。
func _us() -> float:
	return UiKit.scale()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 推荐装备卡（紧贴金币 chip 下方：chip 底边 60 → 卡 y 68..168）
	_card = RecCard.new()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.offset_left = -470.0
	_card.offset_top = 68.0
	_card.offset_right = -20.0
	_card.offset_bottom = 168.0
	add_child(_card)

	# “+”快速购买按钮（与推荐卡同高，贴右下）
	_plus = TouchActionButtonScript.new()
	_plus.label_text = "+"
	_plus.label_font_size = 80.0
	_plus.color = Color(0.98, 0.84, 0.25, 0.95)
	_plus.hold_to_act = false
	_plus.emit_activated_on_press = true
	_plus.activated.connect(_on_buy_clicked)
	_plus.anchor_left = 1.0
	_plus.anchor_top = 0.0
	_plus.offset_left = -120.0
	_plus.offset_top = 76.0
	_plus.offset_right = -30.0
	_plus.offset_bottom = 166.0
	_plus.visible = false   # 初始隐藏，feed 按 host 烘焙 show 刷新（买得起才亮）
	add_child(_plus)

	# 金币 chip：右上角（同 host gold chip：right -285..-55, top 12..52），点按开/关商店
	_chip = GoldChip.new()
	_chip.anchor_left = 1.0
	_chip.anchor_top = 0.0
	_chip.offset_left = -285.0
	_chip.offset_top = 12.0
	_chip.offset_right = -55.0
	_chip.offset_bottom = 60.0
	_chip.tapped.connect(func(): shop_requested.emit())
	add_child(_chip)

	visible = false

# 每帧喂 own（接管且对局中）；阵亡时 host 仍算推荐（死亡也能出装），只在未接管时整体隐藏
func feed(o: Dictionary) -> void:
	visible = true
	_gold = int(o.get("gold", 0))
	var rb = o.get("rb", {})
	if rb is Dictionary:
		_rec_id = str(rb.get("id", ""))
		_rec_text = str(rb.get("text", ""))
		_rec_show = bool(rb.get("show", false))
	else:
		_rec_id = ""
		_rec_text = ""
		_rec_show = false
	_card.item_name = str(rb.get("name", "")) if rb is Dictionary else ""
	_card.tier = int(rb.get("tier", 2)) if rb is Dictionary else 2
	_card.cost = int(rb.get("cost", 0)) if rb is Dictionary else 0
	_card.maxed = bool(rb.get("maxed", false)) if rb is Dictionary else false
	_card.slot_full = bool(rb.get("slot_full", false)) if rb is Dictionary else false
	_card.gold = _gold
	# 金币不足自动收起成图标；买得起后自动展开
	_card.set_collapsed_for_gold(not _rec_show and _rec_id != "" and not _card.maxed)
	_card.queue_redraw()
	_plus.visible = _rec_show and _rec_id != "" and not _card.collapsed
	_chip.set_gold(_gold)

func hide_panel() -> void:
	visible = false

func _on_buy_clicked() -> void:
	if _rec_id != "":
		NetSession.send_command([NetSession.C_BUY, _rec_id])

# —— 推荐装备卡：与 host 同一套 UiKit.rec_card 绘制 ——
class RecCard extends Control:
	var item_name := ""
	var tier := 2
	var cost := 0
	var gold := 0
	var maxed := false
	var slot_full := false
	var collapsed := false          # 点按收起：只留右侧装备图标（灰=暂不可买）
	var auto_collapsed := false     # 因金币不足自动收起；金币够了自动展开
	func affordable() -> bool:
		return cost > 0 and gold >= cost
	func set_collapsed_for_gold(should_collapse: bool) -> void:
		if should_collapse:
			if not collapsed:
				collapsed = true
				auto_collapsed = true
				offset_left = -112.0
				queue_redraw()
		elif auto_collapsed:
			collapsed = false
			auto_collapsed = false
			offset_left = -470.0
			queue_redraw()
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			collapsed = not collapsed
			auto_collapsed = false
			offset_left = -112.0 if collapsed else -470.0   # 收起时缩成图标大小，避免挡住后方面板
			queue_redraw()
			accept_event()
	func _draw() -> void:
		if collapsed:
			var s := minf(size.y - 8.0, 84.0)
			var ir := Rect2(size.x - s - 4.0, (size.y - s) * 0.5, s, s)
			UiKit.item_icon(self, ir, tier, item_name)
			if not affordable() and not maxed:
				draw_circle(ir.get_center(), s * 0.5, Color(0.10, 0.11, 0.14, 0.60))
				UiKit.text(self, Vector2(ir.position.x, ir.position.y + s * 0.5 + 8.0), "缺",
					22, Color(0.78, 0.80, 0.86), HORIZONTAL_ALIGNMENT_CENTER, s)
			return
		UiKit.rec_card(self, Rect2(Vector2.ZERO, size), item_name, tier, cost, gold, maxed, slot_full)

# —— 金币 chip：半透明圆角矩形 + 金色金币数（同 host gold_chip Panel+Label 观感）——
class GoldChip:
	extends Control
	signal tapped
	var gold := 0
	var _f := UiKit.font()
	func _us() -> float:
		return UiKit.scale()
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
	func set_gold(v: int) -> void:
		if v == gold:
			return
		gold = v
		queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		# 同 host gold_chip：_apply_panel_style(0.55) 纯黑半透明、无描边
		draw_rect(r, Color(0, 0, 0, 0.55))
		var txt := "金币: %d" % gold
		var fs := 16.0 * _us()   # host: _apply_label_style(gold_label, 16, UiKit.C_GOLD)
		var w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c := size * 0.5 + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(_f, c, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs)), 1, Color.BLACK)
		draw_string(_f, c, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.84, 0.0))
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			tapped.emit()
