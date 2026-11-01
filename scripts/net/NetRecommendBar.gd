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
var _opt_cards: Array = []
var _opt_plus: Array = []
var _opt_sig := ""


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
	# 同 host UI_Manager.rec_card：right -410..-20，top 53..137（金币 chip 底边 45 下方 8px）
	_card.offset_left = -362.0
	_card.offset_top = 70.0
	_card.offset_right = -116.0
	_card.offset_bottom = 190.0
	_card.buy_requested.connect(_on_buy_clicked)
	add_child(_card)

	# “+”快速购买按钮（与推荐卡同高，贴右下）
	_plus = TouchActionButtonScript.new()
	_plus.label_text = "+"
	_plus.label_font_size = 76.0     # 同 host buy_plus_btn.label_font_size
	_plus.color = Color(0.98, 0.84, 0.25, 0.95)
	_plus.hold_to_act = false
	_plus.emit_activated_on_press = true
	_plus.activated.connect(_on_buy_clicked)
	_plus.anchor_left = 1.0
	_plus.anchor_top = 0.0
	_plus.offset_left = -108.0
	_plus.offset_top = 79.0
	_plus.offset_right = -12.0
	_plus.offset_bottom = 181.0
	_plus.visible = false   # 初始隐藏，feed 按 host 烘焙 show 刷新（买得起才亮）
	add_child(_plus)

	# 金币 chip：右上角（同 host gold_chip：right -250..-45, top 8..45），点按开/关商店
	_chip = GoldChip.new()
	_chip.anchor_left = 1.0
	_chip.anchor_top = 0.0
	_chip.offset_left = -286.0
	_chip.offset_top = 8.0
	_chip.offset_right = -40.0
	_chip.offset_bottom = 62.0
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
	_card.desc = str(rb.get("desc", "")) if rb is Dictionary else ""
	var opts: Array = rb.get("options", []) if rb is Dictionary else []
	_sync_options(opts)
	# 金币不足自动收起成图标；买得起后自动展开（以卡片自身可买判定兜底）
	var can_show: bool = _rec_show or _card.affordable()
	_card.set_collapsed_for_gold(false)
	_card.queue_redraw()
	var has_opts: bool = not opts.is_empty()
	_card.visible = not has_opts
	_plus.visible = (not has_opts) and can_show and _rec_id != "" and not _card.collapsed
	_chip.set_gold(_gold)

# 双推荐卡：与 host 同版式（右锚 246×120，竖排 y=70/198，各带黄色“+”）
func _sync_options(opts: Array) -> void:
	var sig := ""
	for o in opts:
		sig += str(o.get("id", "")) + "|"
	if sig == _opt_sig:
		for i in range(_opt_cards.size()):
			var c2: RecCard = _opt_cards[i]
			c2.gold = _gold
			c2.queue_redraw()
		for i in range(_opt_plus.size()):
			var p2 = _opt_plus[i]
			if is_instance_valid(p2) and i < opts.size():
				p2.visible = _gold >= int(opts[i].get("cost", 0))
		return
	_opt_sig = sig
	for c in _opt_cards:
		if is_instance_valid(c):
			c.queue_free()
	for p3 in _opt_plus:
		if is_instance_valid(p3):
			p3.queue_free()
	_opt_cards.clear()
	_opt_plus.clear()
	var pi := 0
	for o in opts:
		if pi >= 2:
			break
		var card := RecCard.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.anchor_left = 1.0
		card.anchor_right = 1.0
		card.offset_left = -246.0
		card.offset_right = 0.0
		card.offset_top = 70.0 + float(pi) * 128.0
		card.offset_bottom = card.offset_top + 120.0
		card.item_name = str(o.get("name", ""))
		card.tier = int(o.get("tier", 1))
		card.cost = int(o.get("cost", 0))
		card.gold = _gold
		card.desc = str(o.get("desc", ""))
		card.tap_buy = true
		var buy_id := str(o.get("id", ""))
		card.buy_requested.connect(func(): _buy_id(buy_id))
		add_child(card)
		_opt_cards.append(card)
		var plus := TouchActionButtonScript.new()
		plus.label_text = "+"
		plus.label_font_size = 76.0
		plus.color = Color(0.98, 0.84, 0.25, 0.95)
		plus.hold_to_act = false
		plus.emit_activated_on_press = true
		plus.anchor_left = 1.0
		plus.anchor_top = 0.0
		plus.anchor_right = 1.0
		plus.offset_left = -108.0
		plus.offset_right = -12.0
		plus.offset_top = 70.0 + float(pi) * 128.0 + 9.0
		plus.offset_bottom = plus.offset_top + 102.0
		plus.activated.connect(func(): _buy_id(buy_id))
		plus.visible = _gold >= int(o.get("cost", 0))
		add_child(plus)
		_opt_plus.append(plus)
		pi += 1


func _buy_id(buy_id: String) -> void:
	if buy_id != "":
		NetSession.send_command([NetSession.C_BUY, buy_id])


func hide_panel() -> void:
	visible = false

func _on_buy_clicked() -> void:
	if _rec_id != "":
		NetSession.send_command([NetSession.C_BUY, _rec_id])

# —— 推荐装备卡：与 host 同一套 UiKit.rec_card 绘制 ——
class RecCard extends Control:
	signal buy_requested
	var item_name := ""
	var tier := 2
	var cost := 0
	var gold := 0
	var maxed := false
	var slot_full := false
	var desc := ""                  # 装备效果一行简介（host 烘焙进 rb.desc）
	var collapsed := false          # 点按收起：只留右侧装备图标（灰=暂不可买）
	var tap_buy := false            # true=点一下直接买（双推荐卡）
	var _last_should_collapse := false
	var _glow_t := 0.0              # 可购买发光拖尾相位
	func _process(delta: float) -> void:
		if affordable():
			_glow_t += delta
			queue_redraw()
	func affordable() -> bool:
		return cost > 0 and gold >= cost
	func set_collapsed_for_gold(should_collapse: bool) -> void:
		# 只在金币状态切换时自动收/展，避免每帧覆盖玩家刚点出的状态
		if should_collapse == _last_should_collapse:
			return
		_last_should_collapse = should_collapse
		if should_collapse:
			if not collapsed:
				collapsed = true
				offset_left = -208.0    # 收起后仍保留 92px 可点宽度（含图标）
				queue_redraw()
		elif collapsed:
			collapsed = false
			offset_left = -362.0
			queue_redraw()
	func _gui_input(ev: InputEvent) -> void:
		var is_tap := false
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			is_tap = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif ev is InputEventScreenTouch:
			is_tap = (ev as InputEventScreenTouch).pressed
		if is_tap:
			if tap_buy:
				buy_requested.emit()
				accept_event()
				return
			# 收起态点击 = 展开；展开且买不起时才允许点回收起。买得起时保持展开，购买走右侧“+”
			if collapsed:
				collapsed = false
				offset_left = -362.0
			elif not affordable():
				collapsed = true
				offset_left = -208.0    # 收起态宽度必须容得下图标本身
			queue_redraw()
			accept_event()
	func _draw() -> void:
		if collapsed:
			var s := minf(size.y - 8.0, 84.0)
			var ir := Rect2(size.x - s - 4.0, (size.y - s) * 0.5, s, s)
			if affordable():
				_glow_ring(ir.get_center(), s * 0.5 + 5.0)
			UiKit.item_icon(self, ir, tier, item_name)
			if not affordable() and not maxed:
				draw_circle(ir.get_center(), s * 0.5, Color(0.10, 0.11, 0.14, 0.60))
				UiKit.text(self, Vector2(ir.position.x, ir.position.y + s * 0.5 + 8.0), "缺",
					22, Color(0.78, 0.80, 0.86), HORIZONTAL_ALIGNMENT_CENTER, s)
			# 收起态也把缺额写出来：还差 N 金
			if cost > 0 and gold < cost and not maxed:
				var dfs := int(size.y * 0.16)
				draw_string(UiKit.font(), Vector2(10.0, size.y * 0.5 + float(dfs) * 0.35),
					"还差 %d 金" % (cost - gold), HORIZONTAL_ALIGNMENT_LEFT,
					size.x - s - 22.0, dfs, Color(1.0, 0.84, 0.35, 0.95))
			return
		UiKit.rec_card(self, Rect2(Vector2.ZERO, size), item_name, tier, cost, gold, maxed, slot_full, desc)
		if affordable():
			var ic := UiKit.rec_icon_rect(Rect2(Vector2.ZERO, size))
			_glow_ring(ic.get_center(), ic.size.x * 0.5 + 5.0)
	# 图标四周旋转发光拖尾（同 host RecItemCard）
	func _glow_ring(c: Vector2, r: float) -> void:
		for gi in 3:
			var a0 := _glow_t * 3.2 + TAU * float(gi) / 3.0
			for gk in 6:
				var gt := float(gk) / 6.0
				draw_arc(c, r + gt * 7.0, a0, a0 + 1.0, 10,
					Color(1.0, 0.86, 0.32, (1.0 - gt) * 0.6), 5.0 - gt * 2.6, true)

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
		# 同 host gold_chip：_apply_panel_style(0.55) 圆角玻璃 + 冷光描边
		draw_style_box(UiKit.flat(0.55, 12, 1), r)
		var txt := "金币: %d" % gold
		var fs := 23.0 * _us()   # host: _apply_label_style(gold_label, 23, UiKit.C_GOLD)
		var w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var c := size * 0.5 + Vector2(-w * 0.5, fs * 0.36)
		draw_string_outline(_f, c, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(fs)), 1, Color.BLACK)
		draw_string(_f, c, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.84, 0.0))
	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			tapped.emit()

