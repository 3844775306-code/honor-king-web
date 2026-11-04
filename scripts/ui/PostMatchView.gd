class_name PostMatchView
extends Control
## 赛后「聚光灯舞台」叠加层：分两阶段，供 BattleManager 调用。
## 阶段 A：屏幕顶部胜负大标题 + 下方 5 个英雄铭牌（跟随 3D 英雄脚下的世界坐标投影）。
## 阶段 B：屏幕右侧个人表现面板（英雄信息 + 属性行 + 段位积分变化）。
## 本层只做展示与点击推进：不换场景、不暂停游戏；3D 相机与英雄由 BattleManager 负责。

signal advance      # 第一次点击：进入阶段 B
signal finished     # 第二次点击：进结算

const PLATE_SIZE := Vector2(200.0, 86.0)   # 铭牌尺寸（约 200×86）
const TITLE_Y := 70.0                      # 大标题顶部 y
const TITLE_FONT := 84                     # 大标题字号
const HINT_FONT := 18                      # 底部提示字号
const PANEL_MIN_W := 520.0                 # 阶段 B 面板最小宽度
const PANEL_RIGHT_GAP := 40.0              # 阶段 B 面板右缘距屏边

var _phase := 0                    # 0=阶段 A，1=阶段 B
var _won := false                  # 阶段 A 是否胜利（大标题/装饰线配色）
var _cam: Camera3D = null          # BattleManager 传入的相机（铭牌投影用）
var _t := 0.0                      # 呼吸动画计时
var _title: Label = null           # 阶段 A 大标题
var _hint: Label = null            # 底部点击提示（两阶段共用，文案切换）
var _plate_nodes: Array[Panel] = []
var _plate_world: Array[Vector3] = []
var _plate_ref = []                # 对应英雄节点（每帧取实时位置，避免 AI 漂移导致铭牌错位）
var _detail: Panel = null          # 阶段 B 右侧面板
var _last_click_ms := -10000       # 上次推进时间（去重：鼠标+合成触摸/连发只算一次）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 满屏锚点会自动跟进视口尺寸（含 CanvasLayer 父节点）；这里不再显式写 size，
	# 否则会与左右非对称锚点冲突并被引擎覆盖。
	_build_title()
	_build_hint()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)
	resized.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if not is_inside_tree():
		return
	_layout_detail()
	if _detail != null and is_instance_valid(_detail):
		_fit_detail_height(_detail)


func _process(delta: float) -> void:
	_t += delta
	# 两个阶段都要跟随镜头更新铭牌：阶段 B 其余英雄仍留在台上，铭牌不能停在旧屏幕位置
	_update_plates()
	if _phase != 0:
		return
	# 底部提示轻微呼吸：直接算 sin，不额外开 tween
	if _hint != null and _hint.visible:
		_hint.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 3.0))


func _draw() -> void:
	var vp := size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	# 底部轻微渐隐（不遮黑整屏：只压暗下沿，保证铭牌与提示可读）
	var bands := 16
	var band_h := vp.y * 0.24 / float(bands)
	for i in range(bands):
		var a := 0.28 * float(i + 1) / float(bands)
		draw_rect(Rect2(0.0, vp.y - band_h * float(bands - i), vp.x, band_h + 1.0),
				Color(0.01, 0.02, 0.035, a))
	# 阶段 A：标题下方一条细装饰线 + 两端小菱形
	if _phase == 0:
		var acc := _accent()
		var cx := vp.x * 0.5
		draw_line(Vector2(cx - 300.0, 178.0), Vector2(cx + 300.0, 178.0),
				Color(acc.r, acc.g, acc.b, 0.50), 2.0, true)
		draw_rect(Rect2(cx - 306.0, 176.0, 6.0, 4.0), Color(acc.r, acc.g, acc.b, 0.85))
		draw_rect(Rect2(cx + 300.0, 176.0, 6.0, 4.0), Color(acc.r, acc.g, acc.b, 0.85))


func _gui_input(event: InputEvent) -> void:
	# 只有根 Control 接点击：阶段 B 的面板与阶段 A 的铭牌全部 MOUSE_FILTER_IGNORE
	var hit := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		hit = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		hit = st.pressed
	if not hit:
		return
	# 去重：桌面端 emulate_touch_from_mouse 会让一次鼠标点击同时产生鼠标事件+合成触摸，
	# 两者相隔几毫秒；若都推进就会「一次点击直接跳到结算」。同一时间窗只算一次。
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_click_ms < 300:
		accept_event()
		return
	_last_click_ms = now_ms
	accept_event()
	_advance_click()


# ============================== 对外 API ==============================


## BattleManager 传入相机，用于阶段 A 铭牌投影。
func set_camera(c: Camera3D) -> void:
	_cam = c


## 阶段 A 数据：每个英雄一个铭牌。
## 每项：{"world": Vector3, "hero": String, "nick": String, "lane": String,
##        "mvp": bool, "medal": int}（medal: 0=金牌 1=银牌 2=铜牌，-1/缺省不显示）
func set_stage(won: bool, entries: Array) -> void:
	_won = won
	_phase = 0
	_t = 0.0
	if _title != null:
		_title.text = "胜 利" if won else "失 败"
		_title.add_theme_color_override("font_color", _accent())
		_title.visible = true
	_set_hint_text("点击任意处继续")
	if _hint != null:
		_hint.visible = true
		_hint.modulate.a = 1.0
	_build_plates(entries)
	queue_redraw()


## 阶段 B 数据：右侧个人表现面板。
## {"hero","nick","lane","mvp", "rows":[[标签, 数值],...], "rank_lines":[String,...]}
func show_player_detail(d: Dictionary) -> void:
	_phase = 1
	if _title != null:
		_title.visible = false
	for p in _plate_nodes:
		if is_instance_valid(p):
			p.visible = false
	_set_hint_text("点击进入结算")
	if _hint != null:
		_hint.visible = true
		_hint.modulate.a = 1.0
	_build_detail(d)
	queue_redraw()


## 当前阶段：0=阶段 A，1=阶段 B。
func phase() -> int:
	return _phase


# ============================== 阶段 A ==============================


func _build_title() -> void:
	_title = _mk_label("", TITLE_FONT, UiKit.C_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.anchor_left = 0.0
	_title.anchor_right = 1.0
	_title.anchor_top = 0.0
	_title.anchor_bottom = 0.0
	_title.offset_left = 0.0
	_title.offset_right = 0.0
	_title.offset_top = TITLE_Y
	_title.offset_bottom = TITLE_Y + 130.0
	_title.visible = false
	add_child(_title)


func _build_hint() -> void:
	_hint = _mk_label("点击任意处继续", HINT_FONT, Color(1.0, 0.97, 0.88, 0.92))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 0.0
	_hint.offset_right = 0.0
	_hint.offset_top = -78.0
	_hint.offset_bottom = -42.0
	_hint.visible = false
	add_child(_hint)


func _set_hint_text(txt: String) -> void:
	if _hint != null:
		_hint.text = txt


func _build_plates(entries: Array) -> void:
	for p in _plate_nodes:
		if is_instance_valid(p):
			p.queue_free()
	_plate_nodes.clear()
	_plate_world.clear()
	_plate_ref.clear()
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var world: Vector3 = d.get("world", Vector3.ZERO)
		var plate := _make_plate(d)
		add_child(plate)
		_plate_nodes.append(plate)
		_plate_world.append(world)
		_plate_ref.append(d.get("node", null))


## 单个英雄铭牌：英雄名 / 昵称 / MVP + 奖牌 chip。
func _make_plate(d: Dictionary) -> Panel:
	var plate := Panel.new()
	plate.size = PLATE_SIZE
	plate.custom_minimum_size = PLATE_SIZE
	plate.clip_contents = true
	plate.add_theme_stylebox_override("panel", _plate_style())
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_right = -10.0
	box.offset_top = 6.0
	box.offset_bottom = -6.0
	box.add_theme_constant_override("separation", 1)
	plate.add_child(box)
	# 第 1 行：英雄名 22px 亮白
	var hero_lbl := _mk_label(str(d.get("hero", "")), 22, Color(1.0, 1.0, 1.0))
	hero_lbl.clip_text = true
	box.add_child(hero_lbl)
	# 第 2 行：昵称 15px 灰
	var nick_lbl := _mk_label(str(d.get("nick", "")), 15, UiKit.C_TEXT_DIM)
	nick_lbl.clip_text = true
	box.add_child(nick_lbl)
	# 第 3 行：标签行（MVP 与奖牌可并排）
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 5)
	box.add_child(tags)
	if bool(d.get("mvp", false)):
		tags.add_child(_mk_chip("MVP", UiKit.C_GOLD))
	var medal := int(d.get("medal", -1))
	if medal >= 0 and medal <= 2:
		var lane_txt := str(d.get("lane", ""))
		var chip_txt := _medal_name(medal)
		if lane_txt != "":
			chip_txt = "%s · %s" % [chip_txt, lane_txt]
		tags.add_child(_mk_chip(chip_txt, _medal_color(medal)))
	_pass_through(plate)
	return plate


func _plate_style() -> StyleBoxFlat:
	var acc := _accent()
	return UiKit.flat(0.90, 10, 1, Color(acc.r, acc.g, acc.b, 0.55),
			Color(0.045, 0.055, 0.08, 0.88), 0.0, 10.0)


## 铭牌挂在英雄头顶上方（不遮人）；阶段 B 只显示其余 4 人铭牌，并避让右侧个人面板
func _update_plates() -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	var vp := size
	# 阶段 B：右侧被个人面板占用，铭牌最多摆到面板左缘之前
	var max_right: float = vp.x - 8.0
	if _phase != 0 and _detail != null and is_instance_valid(_detail):
		max_right = minf(max_right, _detail.position.x - 12.0)
	for i in range(_plate_nodes.size()):
		var plate := _plate_nodes[i]
		if not is_instance_valid(plate):
			continue
		# 阶段 B：玩家自己的铭牌让位给右侧面板（其余英雄的铭牌继续显示）
		if _phase != 0 and i == 0:
			plate.visible = false
			continue
		var world := _plate_world[i] + Vector3(0.0, 2.55, 0.0)
		if i < _plate_ref.size() and is_instance_valid(_plate_ref[i]) and (_plate_ref[i] as Node3D).is_inside_tree():
			world = (_plate_ref[i] as Node3D).global_position + Vector3(0.0, 2.55, 0.0)
		if _cam.is_position_behind(world):
			plate.visible = false
			continue
		plate.visible = true
		var screen_pt := _cam.unproject_position(world)
		# 铭牌挂在头顶上方（底边贴头顶留 6px），不遮挡人物模型
		var pos := screen_pt - Vector2(plate.size.x * 0.5, plate.size.y + 6.0)
		pos.x = clampf(pos.x, 8.0, maxf(8.0, max_right - plate.size.x))
		pos.y = clampf(pos.y, TITLE_Y + 130.0, maxf(TITLE_Y + 130.0, vp.y - plate.size.y - 96.0))
		plate.position = pos


# ============================== 阶段 B ==============================


func _build_detail(d: Dictionary) -> void:
	if _detail != null and is_instance_valid(_detail):
		_detail.queue_free()
		_detail = null
	var panel := Panel.new()
	panel.clip_contents = true
	var sb := UiKit.flat(0.94, 20, 2, Color(0.60, 0.76, 1.0, 0.55),
			Color(0.035, 0.045, 0.07, 0.94), 0.0, 24.0)
	sb.shadow_color = Color(0.02, 0.04, 0.08, 0.60)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_detail = panel
	_layout_detail()

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26.0
	box.offset_right = -26.0
	box.offset_top = 24.0
	box.offset_bottom = -22.0
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	# ---- 头部卡：英雄头像 + 名字 / 昵称·分路 / 评分·奖牌 ----
	var head_card := Panel.new()
	head_card.custom_minimum_size = Vector2(0.0, 132.0)
	var hsb := UiKit.flat(0.5, 16, 1, Color(1.0, 0.85, 0.35, 0.22), Color(1.0, 1.0, 1.0, 0.05), 0.0, 16.0)
	head_card.add_theme_stylebox_override("panel", hsb)
	box.add_child(head_card)
	var head_row := HBoxContainer.new()
	head_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head_row.offset_left = 18.0
	head_row.offset_right = -18.0
	head_row.offset_top = 14.0
	head_row.offset_bottom = -14.0
	head_row.add_theme_constant_override("separation", 18)
	head_card.add_child(head_row)
	var face := _Portrait.new()
	face.hero_name = str(d.get("hero", ""))
	face.accent = UiKit.C_GOLD if bool(d.get("mvp", false)) else Color(0.55, 0.78, 1.0)
	face.custom_minimum_size = Vector2(96.0, 96.0)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(face)
	var hcol := VBoxContainer.new()
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hcol.add_theme_constant_override("separation", 4)
	head_row.add_child(hcol)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var hero_lbl := _mk_label(str(d.get("hero", "")), 38, Color(1.0, 0.95, 0.86))
	hero_lbl.clip_text = true
	name_row.add_child(hero_lbl)
	if bool(d.get("mvp", false)):
		var mvp_chip := _mk_chip("MVP", UiKit.C_GOLD)
		mvp_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(mvp_chip)
	var medal := int(d.get("medal", -1))
	if medal >= 0 and medal <= 2:
		var mchip := _mk_chip(_medal_name(medal), _medal_color(medal))
		mchip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(mchip)
	hcol.add_child(name_row)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 12)
	sub.add_child(_mk_label(str(d.get("nick", "")), 19, UiKit.C_TEXT_DIM))
	var lane_txt := str(d.get("lane", ""))
	if lane_txt != "":
		sub.add_child(_mk_label("·  " + lane_txt, 19, UiKit.C_TEAM0))
	hcol.add_child(sub)
	var rate_lbl := _mk_label("对战评分  %.1f" % float(d.get("rating", 0.0)), 20, _rating_color(float(d.get("rating", 0.0))))
	hcol.add_child(rate_lbl)

	# ---- 本局数据 ----
	_spacer_into(box, 4.0)
	box.add_child(_section_title("本局数据"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var rows: Array = d.get("rows", [])
	for i in range(rows.size()):
		var pair: Variant = rows[i]
		if not (pair is Array):
			continue
		var kv: Array = pair
		if kv.size() < 2:
			continue
		grid.add_child(_stat_cell(str(kv[0]), str(kv[1])))

	# ---- 段位结算 ----
	_spacer_into(box, 6.0)
	box.add_child(_section_title("段位结算"))
	var rank_box := VBoxContainer.new()
	rank_box.add_theme_constant_override("separation", 6)
	box.add_child(rank_box)
	var rank_lines: Array = d.get("rank_lines", [])
	for line_item in rank_lines:
		var txt := str(line_item)
		if txt == "":
			continue
		rank_box.add_child(_rank_line(txt))
	_pass_through(panel)
	_fit_detail_height(panel)


## 面板高度按内容自适应并垂直居中：避免底部大片空白
func _fit_detail_height(panel: Panel) -> void:
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var need := 0.0
	for ch in panel.get_children():
		need = maxf(need, (ch as Control).get_combined_minimum_size().y)
	need = clampf(need + 46.0, 420.0, size.y * 0.86)
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_top = -need * 0.5
	panel.offset_bottom = need * 0.5
	print("[PM] detail height=", need)


## 段位行：积分/星数强调，升降级用彩色标签，时长弱化
func _rank_line(txt: String) -> Control:
	var big := txt.contains("积分") and not txt.contains("时长")
	var col := UiKit.C_TEXT
	var fs := 21
	if txt.contains("时长"):
		col = UiKit.C_TEXT_DIM
		fs = 16
	elif txt.contains("↑") or txt.contains("晋升"):
		col = Color(0.55, 1.0, 0.62)
		fs = 20
	elif txt.contains("↓") or txt.contains("降级"):
		col = UiKit.C_DANGER
		fs = 20
	elif txt.contains("+"):
		col = UiKit.C_GOLD
		fs = 24 if big else 20
	elif txt.contains("-"):
		col = Color(1.0, 0.55, 0.5)
	if not big and txt.contains("时长"):
		return _mk_label(txt, fs, col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if big:
		var bar := ColorRect.new()
		bar.color = Color(1.0, 0.85, 0.32, 0.9)
		bar.custom_minimum_size = Vector2(4.0, 26.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bar)
	row.add_child(_mk_label(txt, fs, col))
	return row


## 小统计卡：上=项目名（小字灰）下=数值（大字白），半透明底
func _stat_cell(key_txt: String, val_txt: String) -> Control:
	var card := Panel.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 66.0)
	var sb := UiKit.flat(0.45, 12, 1, Color(1.0, 1.0, 1.0, 0.10), Color(1.0, 1.0, 1.0, 0.05), 0.0, 12.0)
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14.0
	vb.offset_right = -14.0
	vb.offset_top = 8.0
	vb.offset_bottom = -8.0
	vb.add_theme_constant_override("separation", 0)
	card.add_child(vb)
	var k := _mk_label(key_txt, 15, Color(0.62, 0.68, 0.78))
	vb.add_child(k)
	var v := _mk_label(val_txt, 25, Color(1.0, 1.0, 1.0))
	vb.add_child(v)
	_pass_through(card)
	return card


## 分区标题：金色小标题 + 渐隐分隔线
func _section_title(txt: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_mk_label(txt, 19, Color(1.0, 0.86, 0.45)))
	var line := ColorRect.new()
	line.color = Color(1.0, 0.86, 0.45, 0.22)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row


func _spacer_into(parent: Node, h: float) -> void:
	parent.add_child(_spacer(h))


func _rating_color(r: float) -> Color:
	if r >= 80.0:
		return Color(1.0, 0.55, 0.42)
	if r >= 68.0:
		return UiKit.C_GOLD
	if r >= 56.0:
		return Color(0.62, 0.92, 0.55)
	return Color(0.66, 0.71, 0.82)


## 头像（程序化立绘）：与结算页同源
class _Portrait extends Control:
	var hero_name: String = ""
	var accent: Color = Color.WHITE

	func _draw() -> void:
		var r: float = minf(size.x, size.y) * 0.5
		if r <= 2.0:
			return
		var c := size * 0.5
		var art = preload("res://scripts/ui/HeroArt.gd")
		art.draw_portrait(self, c, maxf(1.0, r - 3.0), hero_name, accent, false)
		draw_arc(c, r - 3.0, 0.0, TAU, 48, accent, 3.0, true)



func _layout_detail() -> void:
	if _detail == null or not is_instance_valid(_detail):
		return
	var vp := size
	var w: float = maxf(PANEL_MIN_W, vp.x * 0.44)
	_detail.anchor_left = 1.0
	_detail.anchor_right = 1.0
	_detail.anchor_top = 0.12
	_detail.anchor_bottom = 0.90
	_detail.offset_left = -(w + PANEL_RIGHT_GAP)
	_detail.offset_right = -PANEL_RIGHT_GAP
	_detail.offset_top = 0.0
	_detail.offset_bottom = 0.0


func _detail_row(key_txt: String, val_txt: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 40.0)
	row.add_theme_constant_override("separation", 12)
	var k := _mk_label(key_txt, 20, UiKit.C_TEXT_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(k)
	var v := _mk_label(val_txt, 22, UiKit.C_TEXT)
	v.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(v)
	return row


# ============================== 通用小工具 ==============================


func _mk_label(txt: String, fsize: int, col: Color) -> Label:
	var lab := Label.new()
	lab.text = txt
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_override("font", UiKit.font())
	lab.add_theme_font_size_override("font_size", fsize)
	lab.add_theme_color_override("font_color", col)
	# 叠在 3D 场景上：统一深色描边，保证亮背景下也能看清
	lab.add_theme_constant_override("outline_size", clampi(int(round(float(fsize) * 0.14)), 2, 8))
	lab.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	return lab


func _mk_chip(txt: String, accent: Color) -> Label:
	var lab := _mk_label(txt, 13, accent)
	var sb := UiKit.skin_tag(accent)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	lab.add_theme_stylebox_override("normal", sb)
	return lab


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _line(alpha: float) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(1.0, 1.0, 1.0, alpha)
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## 点击推进：阶段 A → 隐藏标题（铭牌保留给仍在台上的队友）、切阶段并发 advance；阶段 B → 发 finished。
func _advance_click() -> void:
	if _phase == 0:
		_phase = 1
		if _title != null:
			_title.visible = false
		# 只隐藏玩家自己的铭牌（其余英雄留在台上，铭牌继续跟随）
		if not _plate_nodes.is_empty() and is_instance_valid(_plate_nodes[0]):
			_plate_nodes[0].visible = false
		_set_hint_text("点击进入结算")
		if _hint != null:
			_hint.modulate.a = 1.0
		queue_redraw()
		advance.emit()
	else:
		finished.emit()


func _accent() -> Color:
	return UiKit.C_GOLD if _won else UiKit.C_TEAM1


func _medal_name(medal: int) -> String:
	match medal:
		0:
			return "金牌"
		1:
			return "银牌"
		2:
			return "铜牌"
	return ""


func _medal_color(medal: int) -> Color:
	match medal:
		0:
			return Color(1.0, 0.84, 0.35)
		1:
			return Color(0.85, 0.90, 0.97)
		2:
			return Color(0.85, 0.60, 0.38)
	return Color(0.85, 0.85, 0.85)


## 整棵子树鼠标穿透：只有根 Control 接点击。
func _pass_through(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in node.get_children():
		_pass_through(ch)



