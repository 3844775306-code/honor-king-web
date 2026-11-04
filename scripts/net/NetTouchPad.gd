class_name NetTouchPad
extends CanvasLayer
## NetTouchPad —— 联机接管客户端的触摸操作层（M4-U P1a/P1b/P1c：摇杆/普攻轮盘/推塔/小兵/
## 移动模式/技能扇形与升级/召唤师/恢复/回城/主动装/取消施法）。几何 1:1 复刻主机桌面
## TouchController 的对应控件；控件本体仍是纯 ScreenTouch（由 emulate_touch_from_mouse 驱动），
## 不含任何英雄/UI 依赖。NetClientBattle 每帧把这里的状态/事件翻译成 C_DRIVE / C_ATTACK_AUTO /
## C_PRIORITY / C_ATTACK / C_CAST / C_UPGRADE / C_SUMMONER / C_RECOVER / C_RECALL / C_ACTIVE
## 发给主机。

# —— 几何常量：与主机 TouchController._build_ui 的字面量一致。
# TouchController.gd 为 peer 并行编辑文件，故本地复制这些值、不跨文件引用（避免 class 缓存错位）。
const TOUCH_CLUSTER_INSET := Vector2(80, 20)
const JOY_HOME := Vector2(330, 300)    # 摇杆中心：距左下角（宽 600 = 2×激活半径）
const JOY_SIDE := 600.0
const MOVE_TOGGLE_POS := Vector2(1600, 150)   # 桌面 WASD 模式键，不放右下角簇 inset
const MOVE_TOGGLE_SIZE := Vector2(330, 46)
const ATTACK_POS := Vector2(40, 40)
const ATTACK_SIZE := 350.0
const PRIO_TOWER_POS := Vector2(40, 395)
const PRIO_MINION_POS := Vector2(215, 395)
const PRIO_BTN_SIZE := 165.0

# 技能扇形（同 TouchController：圆弧圆心=普攻中心，半径 560，角度 70/35/0°，键 260）
const SKILL_SIZE := 260.0
const UPGRADE_SIZE := 176.0
const FAN_RADIUS := 560.0
const SKILL_FAN_ANGLES_DEG := [70.0, 35.0, 0.0]
# 第4技能按钮（兰陵王·隐身）圆心（同 TouchController 字面量）
const EXTRA_SKILL_CENTER := Vector2(1050, 406)

# —— P1c：召唤师 / 恢复 / 回城 / 主动装 / 取消施法（同 TouchController 字面量）——
const ROW_FROM_BOTTOM := 30.0      # 贴底横带的安全区高度
const AUX_SIZE := 220.0            # 召唤师 / 恢复 / 回城按钮边长
const ACTIVE_SIZE := 230.0         # 主动装备按钮边长
const CANCEL_SIZE := 300.0         # 取消施法按钮边长
const ACTIVE_POS := [Vector2(120, 1055), Vector2(370, 1055)]

# 敌人索敌头像条（同 TouchController：技能扇形外侧同圆心弧线，仅范围内敌方英雄；点选锁敌）
const PICKER_SIZE := 118.0
const PICKER_RADIUS := 800.0
const PICKER_ANGLE_MIN := 8.0
const PICKER_ANGLE_MAX := 76.0
const PICKER_MAX := 5
const HeroArt = preload("res://scripts/ui/HeroArt.gd")

# 键位自定义布局（同 host TouchController：拖动调位置 / ＋－ 调大小 / PlayerPrefs 持久化）
const LAYOUT_SCALE_MIN := 0.55
const LAYOUT_SCALE_MAX := 1.70
const LAYOUT_LABELS := {
	"joystick": "摇杆", "attack": "普攻", "tower": "推塔", "minion": "小兵",
	"skill_1": "1技能", "skill_2": "2技能", "skill_3": "3技能", "skill_4": "4技能",
	"summoner": "召唤师技能", "recover": "恢复", "recall": "回城",
	"equip_1": "主动装1", "equip_2": "主动装2", "cancel": "取消施法",
}

# 单个索敌头像（头像 + 队伍环；锁定态金环；点按发 tapped）
class NetEnemyAvatar extends Control:
	var nid := -1
	var hero_name := ""
	var locked := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		HeroArt.draw_portrait(self, c, r, hero_name, Color(1.0, 0.33, 0.264), false)
		draw_arc(c, r + 3.0, 0.0, TAU, 40, Color(0, 0, 0, 0.85), 4.0)
		draw_arc(c, r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 if locked else 0.72), 40,
			Color(1.0, 0.84, 0.2) if locked else Color(1.0, 0.4, 0.32), 3.0)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			enemy_tapped.emit(nid)
		elif ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			enemy_tapped.emit(nid)

	signal enemy_tapped(nid: int)

# —— 模式常量（与 TouchController / Hero 同义）——
const MOVE_MODE_TURN := 0
const MOVE_MODE_DIR := 1
const PRIO_AUTO := 0
const PRIO_TOWER := 1
const PRIO_MINION := 2

# 技能键效果小字两种配色（host 编码 own.sx 只标敌我 0/1，颜色由 client 统一给：绿=自身增益/蓝=对敌负面）
const FX_BUFF_COL := Color(0.45, 1.0, 0.62)
const FX_DEBUFF_COL := Color(0.55, 0.85, 1.0)

signal move_mode_changed(mode: int)
signal enemy_picker_tapped(nid: int)   # 索敌头像条点选（同 host _on_enemy_picker_tapped）

var touch_active := true    # 由 NetClientBattle 每帧从全局 TouchController.touch_active 同步

var attack_priority := PRIO_AUTO   # 本地状态：按钮高亮 / 同键取消判定
var move_mode := MOVE_MODE_DIR     # 本地状态：随 C_DRIVE 发送、控制键盘移动方式（默认前后左右，与单机 TouchController 一致）

# 同 TouchController：不写死 class_name 类型，避免编辑器类缓存滞后导致的
# "Invalid access to property or key 'move_vector'" 误报
var _joystick
var _attack_btn: AttackWheelButton
var _move_toggle: MoveModeToggle
var _tower_btn: TouchActionButton
var _minion_btn: TouchActionButton
var _attack_release_pending := {}   # 待消费的普攻轮盘松手信息 {drag, cancel}
var _priority_press_pending := -1   # 待消费的优先级按键（PRIO_TOWER/MINION），-1=无

# —— P1b 技能扇形（技能按钮 ×3 + 每键升级钮 + 第4技能按钮[兰陵王·隐身]）——
var _skill_btns: Array = []           # SkillTouchButton，索引 0..2（与技能槽位同）
var _upgrade_btns: Array = []         # TouchActionButton“+”升级钮，索引 0..2
var _extra_skill_btn: SkillTouchButton = null   # 第4技能按钮（skill_index=3），仅兰陵王显示
var _skill_release_pending: Array = [{}, {}, {}, {}]   # 索引 0..3 的 {drag, cancel}，空=无
var _upgrade_pending := -1            # 待消费的升级槽位（0..2），-1=无

# —— P1c：召唤师 / 恢复 / 回城 / 主动装 / 取消施法 ——
var _summoner_btn: SkillTouchButton = null
var _recover_btn: SkillTouchButton = null
var _recall_btn: TouchActionButton = null
var _ui_root: Control = null
var _cc_banner: Label = null
var _active_btns: Array = []          # 主动装备钮 ×2（TouchActionButton）
var _cancel_btn: CancelCastButton = null
var _picker_root: Control = null
var _layout_btns: Array = []
var _edit_root: Control = null
var _edit_sel: Control = null
var _edit_hint: Label = null
var _edit_drag_last := Vector2.ZERO
var _edit_drag_moved := 0.0
var _picker_btns: Array = []
var _summoner_release_pending := {}   # 召唤师松手信息 {drag, cancel}；空=无
var _recover_press_pending := false   # 恢复点按待消费
var _recall_press_pending := false    # 回城点按待消费
var _active_press_pending := -1       # 主动装点按待消费（0..1），-1=无

func _ready() -> void:
	layer = UiKit.LAYER_TOUCH
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_ui_root = root

	# 固定摇杆：底座中心钉在距左下 (330,300)，边长 600（同 TouchController：按下点须落在
	# 中心 ACTIVATE_RADIUS=300 内才启动，激活圆之外不抢占输入）
	var joy = preload("res://scripts/mobile/VirtualJoystick.gd").new()
	var hs := JOY_SIDE * 0.5
	# 手机横屏挖孔/手势条避让（桌面 safe_* 为 0）
	var sl := UiKit.safe_left()
	var sb := UiKit.safe_bottom()
	joy.anchor_left = 0.0
	joy.anchor_top = 1.0
	joy.anchor_right = 0.0
	joy.anchor_bottom = 1.0
	joy.offset_left = sl + JOY_HOME.x - hs
	joy.offset_top = -(sb + JOY_HOME.y + hs)
	joy.offset_right = sl + JOY_HOME.x + hs
	joy.offset_bottom = -(sb + JOY_HOME.y - hs)
	root.add_child(joy)
	_joystick = joy

	# 桌面 WASD 移动模式切换
	var mm := MoveModeToggle.new()
	mm.set_mode(move_mode)
	mm.mode_changed.connect(_on_move_mode_changed)
	_anchor_br(mm, MOVE_TOGGLE_POS, MOVE_TOGGLE_SIZE, Vector2.ZERO)
	# 桌面键盘 WASD 模式切换：手机端隐藏（否则在窄屏上会从左侧越界）
	mm.visible = not Config.on_mobile()
	root.add_child(mm)
	_move_toggle = mm

	# 普攻轮盘（按住普攻 / 拖动精准选敌）
	var atk := AttackWheelButton.new()
	atk.label_text = "普攻"
	atk.color = Color(0.9, 0.4, 0.3, 0.85)
	atk.pressed_changed.connect(_on_attack_pressed_changed)
	atk.released.connect(_on_attack_released)
	_anchor_br(atk, ATTACK_POS, Vector2(ATTACK_SIZE, ATTACK_SIZE))
	root.add_child(atk)
	_attack_btn = atk

	# 推塔 / 小兵（王者式进阶攻击目标优先级切换；同键再按取消的逻辑在 NetClientBattle）
	var tower_btn := TouchActionButton.new()
	tower_btn.label_text = "推塔"
	tower_btn.color = Color(0.85, 0.5, 0.12, 0.92)
	tower_btn.hold_to_act = false
	tower_btn.emit_activated_on_press = true
	tower_btn.activated.connect(func(): _priority_press_pending = PRIO_TOWER)
	_anchor_br(tower_btn, PRIO_TOWER_POS, Vector2(PRIO_BTN_SIZE, PRIO_BTN_SIZE))
	root.add_child(tower_btn)
	_tower_btn = tower_btn

	var minion_btn := TouchActionButton.new()
	minion_btn.label_text = "小兵"
	minion_btn.color = Color(0.3, 0.72, 0.42, 0.92)
	minion_btn.hold_to_act = false
	minion_btn.emit_activated_on_press = true
	minion_btn.activated.connect(func(): _priority_press_pending = PRIO_MINION)
	_anchor_br(minion_btn, PRIO_MINION_POS, Vector2(PRIO_BTN_SIZE, PRIO_BTN_SIZE))
	root.add_child(minion_btn)
	_minion_btn = minion_btn
	_sync_priority_buttons()

	# —— P1b 技能扇形（几何照抄 TouchController）——
	_build_skill_cluster(root)
	# —— P1c：召唤师 / 恢复 / 回城 / 主动装 / 取消施法（几何照抄 TouchController）——
	_build_aux_cluster(root)
	_build_enemy_picker(root)
	_assign_layout_keys()

	visible = false   # 接管且对局开始后才由 NetClientBattle 显示

func _build_skill_cluster(root: Control) -> void:
	var skill_colors := [Color(0.3, 0.7, 1.0), Color(0.35, 0.9, 0.45), Color(1.0, 0.7, 0.25)]
	var atk_center := ATTACK_POS + Vector2(ATTACK_SIZE, ATTACK_SIZE) * 0.5
	for i in range(3):
		var ang := deg_to_rad(SKILL_FAN_ANGLES_DEG[i])
		var fb := atk_center + Vector2(FAN_RADIUS * sin(ang), FAN_RADIUS * cos(ang))
		fb -= Vector2(SKILL_SIZE, SKILL_SIZE) * 0.5
		var b := SkillTouchButton.new()
		b.skill_index = i
		b.color = skill_colors[i]
		b.name_below = true   # 技能名画在按钮下方，中央不显示 1/2/3（同主机）
		b.pressed_changed.connect(_on_skill_pressed_changed)
		b.released.connect(_on_skill_released)
		_anchor_br(b, fb, Vector2(SKILL_SIZE, SKILL_SIZE))
		root.add_child(b)
		_skill_btns.append(b)
		# 升级“+”钮：位于技能上沿中央（同主机 TouchController）
		var upg := TouchActionButton.new()
		upg.label_text = "+"
		upg.label_font_size = 72.0
		upg.color = Color(0.98, 0.84, 0.25, 0.95)
		upg.hold_to_act = false
		upg.emit_activated_on_press = true
		upg.activated.connect(_on_upgrade_pressed.bind(i))
		var upg_fb := fb + Vector2((SKILL_SIZE - UPGRADE_SIZE) * 0.5, SKILL_SIZE)
		_anchor_br(upg, upg_fb, Vector2(UPGRADE_SIZE, UPGRADE_SIZE))
		root.add_child(upg)
		_upgrade_btns.append(upg)
	# 第4技能按钮（真实第4技能槽英雄=兰陵王·隐身才显示）；点按即施放、无瞄准
	var ex := SkillTouchButton.new()
	ex.skill_index = 3
	ex.color = Color(0.72, 0.45, 1.0, 0.85)
	ex.name_below = true
	var ex_fb := EXTRA_SKILL_CENTER - Vector2(SKILL_SIZE, SKILL_SIZE) * 0.5
	_anchor_br(ex, ex_fb, Vector2(SKILL_SIZE, SKILL_SIZE))
	ex.pressed_changed.connect(_on_skill_pressed_changed)
	ex.released.connect(_on_skill_released)
	ex.visible = false
	root.add_child(ex)
	_extra_skill_btn = ex

# —— P1c：贴底横带（召唤师 / 恢复 / 回城）+ 主动装 ×2 + 取消施法（几何照抄 TouchController._build_ui）——
func _build_aux_cluster(root: Control) -> void:
	# 召唤师：按住瞄准（拖动=闪现等位移类技能的方向）、松开施放（王者荣耀式）
	var sum := SkillTouchButton.new()
	sum.skill_index = -1
	sum.display_name = "召唤"
	sum.color = Color(0.7, 0.35, 1.0, 0.85)
	sum.pressed_changed.connect(_on_summoner_pressed_changed)
	sum.released.connect(_on_summoner_released)
	_anchor_br(sum, Vector2(420, ROW_FROM_BOTTOM), Vector2(AUX_SIZE, AUX_SIZE))
	root.add_child(sum)
	_summoner_btn = sum

	# 恢复 —— 召唤师技能左方：点按即时回血（不拖方向）；中央显示“恢复”，画 60s 冷却遮罩
	var recv := SkillTouchButton.new()
	recv.skill_index = 4
	recv.display_name = "恢复"
	recv.color = Color(0.9, 0.35, 0.35, 0.85)
	recv.pressed_changed.connect(func(_idx: int, pressed: bool):
		if pressed:
			_recover_press_pending = true)
	_anchor_br(recv, Vector2(660, ROW_FROM_BOTTOM), Vector2(AUX_SIZE, AUX_SIZE))
	root.add_child(recv)
	_recover_btn = recv

	# 回城 —— 恢复左方（回城中再按=主机 no-op，打断靠移动/普攻/技能）
	var rec := TouchActionButton.new()
	rec.label_text = "回城"
	rec.color = Color(0.3, 0.8, 0.7, 0.85)
	rec.hold_to_act = false
	rec.emit_activated_on_press = true
	rec.activated.connect(func(): _recall_press_pending = true)
	_anchor_br(rec, Vector2(900, ROW_FROM_BOTTOM), Vector2(AUX_SIZE, AUX_SIZE))
	root.add_child(rec)
	_recall_btn = rec

	# 主动装备 ×2（大招上方；仅拥有对应主动装时显示）
	for i in range(2):
		var ab := TouchActionButton.new()
		ab.label_text = "装%d" % (i + 1)
		ab.color = Color(0.9, 0.75, 0.2, 0.85)
		ab.hold_to_act = false
		ab.emit_activated_on_press = true
		ab.activated.connect(_on_active_pressed.bind(i))
		_anchor_br(ab, ACTIVE_POS[i], Vector2(ACTIVE_SIZE, ACTIVE_SIZE))
		ab.visible = false
		root.add_child(ab)
		_active_btns.append(ab)

	# 取消施法按钮：任一技能/召唤师按钮按住瞄准时显示（见 refresh_cancel_aim）
	var cancel := CancelCastButton.new()
	cancel.name = "CancelCast"
	_anchor_br(cancel, Vector2(700, 760), Vector2(CANCEL_SIZE, CANCEL_SIZE))
	cancel.visible = false
	root.add_child(cancel)
	_cancel_btn = cancel

# —— 底部靠右簇锚定：from_br（右下角坐标）+ inset，尺寸 size（同 TouchController._anchor_br）——
# 索敌头像条：技能扇形外侧同圆心弧线（同 TouchController._create_enemy_picker/_update_enemy_picker）
func _build_enemy_picker(root: Control) -> void:
	_picker_root = Control.new()
	_picker_root.name = "EnemyPicker"
	_picker_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_root.visible = false
	root.add_child(_picker_root)
	_picker_btns.clear()
	for i in PICKER_MAX:
		var av: NetEnemyAvatar = NetEnemyAvatar.new()
		av.visible = false
		av.enemy_tapped.connect(func(nid: int): enemy_picker_tapped.emit(nid))
		_picker_root.add_child(av)
		_picker_btns.append(av)


func set_enemy_picker(list: Array) -> void:
	if _picker_root == null:
		return
	var n: int = mini(list.size(), PICKER_MAX)
	_picker_root.visible = n > 0
	if n <= 0:
		for av in _picker_btns:
			av.visible = false
		return
	var atk_center: Vector2 = ATTACK_POS + Vector2(ATTACK_SIZE, ATTACK_SIZE) * 0.5
	for i in _picker_btns.size():
		var av: NetEnemyAvatar = _picker_btns[i]
		if i >= n:
			av.visible = false
			continue
		var e: Array = list[i]
		var t: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		var ang := deg_to_rad(lerpf(PICKER_ANGLE_MIN, PICKER_ANGLE_MAX, t))
		var pos: Vector2 = atk_center + Vector2(PICKER_RADIUS * sin(ang), PICKER_RADIUS * cos(ang))
		_anchor_br(av, pos - Vector2(PICKER_SIZE, PICKER_SIZE) * 0.5, Vector2(PICKER_SIZE, PICKER_SIZE))
		av.visible = true
		av.nid = int(e[0])
		av.hero_name = str(e[1])
		av.locked = bool(e[2]) if e.size() > 2 else false
		av.queue_redraw()


# ---------------- 键位自定义布局（同 host TouchController 编辑器交互） ----------------

func _assign_layout_keys() -> void:
	var kv: Array = [
		[_joystick, "joystick"], [_attack_btn, "attack"], [_tower_btn, "tower"], [_minion_btn, "minion"],
		[_extra_skill_btn, "skill_4"], [_summoner_btn, "summoner"], [_recover_btn, "recover"],
		[_recall_btn, "recall"], [_cancel_btn, "cancel"],
	]
	for i in range(_skill_btns.size()):
		kv.append([_skill_btns[i], "skill_%d" % (i + 1)])
	for i in range(_active_btns.size()):
		kv.append([_active_btns[i], "equip_%d" % (i + 1)])
	for pair in kv:
		var c = pair[0]
		if c == null or not is_instance_valid(c):
			continue
		c.set_meta("layout_key", str(pair[1]))
		_register_layout(c)

func _register_layout(ctrl: Control) -> void:
	var key := str(ctrl.get_meta("layout_key", ""))
	if key == "":
		return
	ctrl.set_meta("layout_def", [ctrl.offset_left, ctrl.offset_top, ctrl.offset_right, ctrl.offset_bottom])
	if not _layout_btns.has(ctrl):
		_layout_btns.append(ctrl)
	var lay: Dictionary = PlayerPrefs.get_btn_layout()
	_apply_layout_one(ctrl, lay.get(key, {}))

func _apply_layout_one(ctrl: Control, e) -> void:
	var entry: Dictionary = e if e is Dictionary else {}
	var dx := float(entry.get("x", 0.0))
	var dy := float(entry.get("y", 0.0))
	var sc := clampf(float(entry.get("s", 1.0)), LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX)
	if dx != 0.0 or dy != 0.0:
		ctrl.offset_left += dx
		ctrl.offset_right += dx
		ctrl.offset_top += dy
		ctrl.offset_bottom += dy
	ctrl.pivot_offset = Vector2((ctrl.offset_right - ctrl.offset_left) * 0.5,
		(ctrl.offset_bottom - ctrl.offset_top) * 0.5)
	ctrl.scale = Vector2(sc, sc)

## 进入键位编辑：不暂停联机对局（避免服务器超时），用全屏 STOP 层挡住战斗输入
func enter_layout_edit() -> void:
	if _edit_root != null and is_instance_valid(_edit_root):
		return
	_edit_root = Control.new()
	_edit_root.name = "NetLayoutEdit"
	_edit_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edit_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_edit_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_edit_root)
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -430.0; bar.offset_right = 430.0
	bar.offset_top = 10.0; bar.offset_bottom = 118.0
	bar.add_theme_stylebox_override("panel", UiKit.panel_style(0.96, 12.0))
	_edit_root.add_child(bar)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 14.0; vb.offset_right = -14.0
	vb.offset_top = 8.0; vb.offset_bottom = -8.0
	vb.add_theme_constant_override("separation", 6)
	bar.add_child(vb)
	_edit_hint = Label.new()
	_edit_hint.text = "拖动按钮调整位置 · 点选后用 ＋/－ 调大小 · 保存后进入对局自动生效"
	_edit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit_hint.add_theme_font_override("font", UiKit.font())
	_edit_hint.add_theme_font_size_override("font_size", 17)
	_edit_hint.add_theme_color_override("font_color", UiKit.C_TEXT)
	vb.add_child(_edit_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(_layout_bar_btn("－ 缩小", UiKit.C_TEAM0, func(): _scale_layout_sel(-0.1)))
	row.add_child(_layout_bar_btn("＋ 放大", UiKit.C_TEAM0, func(): _scale_layout_sel(0.1)))
	row.add_child(_layout_bar_btn("保存", UiKit.C_GOLD, func(): _exit_layout_edit(true)))
	row.add_child(_layout_bar_btn("重置", UiKit.C_DANGER, _reset_layout_edit))
	row.add_child(_layout_bar_btn("取消", UiKit.C_PANEL_EDGE, func(): _exit_layout_edit(false)))
	_edit_root.gui_input.connect(_on_layout_edit_input)
	if not _layout_btns.is_empty():
		select_layout_button(_layout_btns[0])

func _layout_bar_btn(txt: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(150.0, 42.0)
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", UiKit.C_TEXT)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, col, false))
	b.pressed.connect(cb)
	return b

func select_layout_button(ctrl: Control) -> void:
	_edit_sel = ctrl
	if _edit_hint != null and is_instance_valid(_edit_hint):
		var key := str(ctrl.get_meta("layout_key", ""))
		_edit_hint.text = "已选中「%s」（%.0f%%）· 拖动调整位置 · ＋/－ 调大小" % [
			str(LAYOUT_LABELS.get(key, key)), ctrl.scale.x * 100.0]
	if ctrl != null:
		ctrl.grab_focus()

func _scale_layout_sel(d: float) -> void:
	if _edit_sel == null or not is_instance_valid(_edit_sel):
		return
	_edit_sel.scale = Vector2(clampf(_edit_sel.scale.x + d, LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX),
		clampf(_edit_sel.scale.x + d, LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX))
	select_layout_button(_edit_sel)

func _on_layout_edit_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_edit_drag_last = mb.position
			_edit_drag_moved = 0.0
			var hit := _layout_hit(mb.position)
			if hit != null:
				select_layout_button(hit)
			return
		return
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_edit_drag_last = st.position
			_edit_drag_moved = 0.0
			var hit2 := _layout_hit(st.position)
			if hit2 != null:
				select_layout_button(hit2)
		return
	if ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag_sel((ev as InputEventMouseMotion).position)
		return
	if ev is InputEventScreenDrag:
		_drag_sel((ev as InputEventScreenDrag).position)

func _drag_sel(pos: Vector2) -> void:
	if _edit_sel == null or not is_instance_valid(_edit_sel):
		return
	var d: Vector2 = pos - _edit_drag_last
	_edit_drag_last = pos
	_edit_sel.offset_left += d.x
	_edit_sel.offset_right += d.x
	_edit_sel.offset_top += d.y
	_edit_sel.offset_bottom += d.y
	_edit_drag_moved += d.length()

func _layout_hit(pos: Vector2) -> Control:
	for i in range(_layout_btns.size() - 1, -1, -1):
		var c: Control = _layout_btns[i]
		if is_instance_valid(c) and c.visible and c.get_global_rect().has_point(pos):
			return c
	return null

func _reset_layout_edit() -> void:
	PlayerPrefs.clear_btn_layout()
	for c in _layout_btns:
		if not is_instance_valid(c):
			continue
		var def = c.get_meta("layout_def", [])
		if def is Array and def.size() == 4:
			c.offset_left = float(def[0])
			c.offset_top = float(def[1])
			c.offset_right = float(def[2])
			c.offset_bottom = float(def[3])
		c.pivot_offset = Vector2.ZERO
		c.scale = Vector2.ONE
	if not _layout_btns.is_empty():
		select_layout_button(_layout_btns[0])

func _exit_layout_edit(save_it: bool) -> void:
	if save_it:
		var lay: Dictionary = {}
		for c in _layout_btns:
			if not is_instance_valid(c):
				continue
			var key := str(c.get_meta("layout_key", ""))
			var def = c.get_meta("layout_def", [])
			if key == "" or not (def is Array) or (def as Array).size() != 4:
				continue
			var dx: float = c.offset_left - float(def[0])
			var dy: float = c.offset_top - float(def[1])
			if absf(dx) < 0.5 and absf(dy) < 0.5 and absf(c.scale.x - 1.0) < 0.001:
				continue
			lay[key] = {"x": dx, "y": dy, "s": c.scale.x}
		PlayerPrefs.set_btn_layout(lay)
	else:
		# 取消：重新套用已保存布局（丢弃本次拖动）
		for c in _layout_btns:
			if not is_instance_valid(c):
				continue
			var def2 = c.get_meta("layout_def", [])
			if def2 is Array and (def2 as Array).size() == 4:
				c.offset_left = float(def2[0])
				c.offset_top = float(def2[1])
				c.offset_right = float(def2[2])
				c.offset_bottom = float(def2[3])
			c.pivot_offset = Vector2.ZERO
			c.scale = Vector2.ONE
		var lay2: Dictionary = PlayerPrefs.get_btn_layout()
		for c in _layout_btns:
			if is_instance_valid(c):
				_apply_layout_one(c, lay2.get(str(c.get_meta("layout_key", "")), {}))
	if _edit_root != null and is_instance_valid(_edit_root):
		_edit_root.queue_free()
	_edit_root = null
	_edit_sel = null
	_edit_hint = null


func _anchor_br(ctrl: Control, from_br: Vector2, size: Vector2, inset: Vector2 = TOUCH_CLUSTER_INSET) -> void:
	from_br += inset
	# 手机横屏：右侧挖孔/圆角与底部手势条避让；桌面 safe_* 恒为 0
	from_br.x += UiKit.safe_right()
	from_br.y += UiKit.safe_bottom()
	ctrl.anchor_left = 1.0
	ctrl.anchor_top = 1.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.offset_left = -from_br.x - size.x
	ctrl.offset_top = -from_br.y - size.y
	ctrl.offset_right = -from_br.x
	ctrl.offset_bottom = -from_br.y

# —— 公开读取接口（NetClientBattle 每帧调用，对应 TouchController 的同名 getter 子集）——

func get_move_vector() -> Vector2:
	if touch_active and _joystick:
		return _joystick.move_vector
	return Vector2.ZERO

func is_attack_held() -> bool:
	if touch_active and _attack_btn:
		return _attack_btn.is_held()
	return false

# 消费普攻轮盘松手选敌信息（返回 {drag, cancel}；无松开事件返回空字典）
func consume_attack_release() -> Dictionary:
	var v: Dictionary = _attack_release_pending
	_attack_release_pending = {}
	return v

# 消费优先级按键：返回按下的模式（PRIO_TOWER/MINION），无则 -1
func consume_priority_press() -> int:
	var v := _priority_press_pending
	_priority_press_pending = -1
	return v

## 回放：外部触发技能/普攻按钮按下动效
func flash_skill(i: int) -> void:
	if i >= 0 and i < _skill_btns.size() and is_instance_valid(_skill_btns[i]):
		_skill_btns[i].call("flash_press")
	elif i == 3 and _extra_skill_btn != null and is_instance_valid(_extra_skill_btn):
		_extra_skill_btn.call("flash_press")


func flash_attack() -> void:
	if _attack_btn != null and is_instance_valid(_attack_btn):
		_attack_btn.flash_press()


## 回放：摇杆视觉跟随英雄移动方向（不产生输入）
func apply_control_feedback(kind: String, left: float, cleanse: Array, cleanse_summoner: bool) -> void:
	if kind == "":
		for b in _skill_btns:
			if b != null and is_instance_valid(b):
				b.blocked = false
				b.block_cue = ""
				b.modulate = Color.WHITE
		if _extra_skill_btn != null:
			_extra_skill_btn.blocked = false
			_extra_skill_btn.block_cue = ""
			_extra_skill_btn.modulate = Color.WHITE
		if _summoner_btn != null: _summoner_btn.blocked = false; _summoner_btn.block_cue = ""; _summoner_btn.modulate = Color.WHITE
		if _recover_btn != null: _recover_btn.blocked = false; _recover_btn.block_cue = ""; _recover_btn.modulate = Color.WHITE
		if _attack_btn != null: _attack_btn.modulate = Color.WHITE
		if _recall_btn != null: _recall_btn.dimmed = false; _recall_btn.modulate = Color.WHITE
		if _joystick != null: _joystick.modulate = Color.WHITE
		if _cc_banner != null: _cc_banner.visible = false
		return
	var hard := kind in ["suppress", "stun", "knockup", "freeze"]
	var locks_skill := kind in ["suppress", "stun", "knockup", "freeze", "silence"]
	var locks_atk := hard
	var locks_move := hard
	var label: String = {"stun": "眩晕", "knockup": "击飞", "freeze": "冰冻", "suppress": "压制",
		"silence": "沉默", "slow": "减速"}.get(kind, "受控")
	var tint: Color = {"stun": Color(1.0, 0.88, 0.35), "knockup": Color(1.0, 0.62, 0.25),
		"freeze": Color(0.45, 0.9, 1.0), "suppress": Color(1.0, 0.28, 0.28),
		"silence": Color(0.52, 0.68, 1.0), "slow": Color(0.62, 0.82, 1.0)}.get(kind, Color.WHITE)
	for i in range(_skill_btns.size()):
		var b: SkillTouchButton = _skill_btns[i]
		if b == null or not is_instance_valid(b):
			continue
		var can_cleanse: bool = i < cleanse.size() and bool(cleanse[i]) and kind != "suppress"
		if locks_skill and not can_cleanse:
			b.blocked = true; b.block_cue = label; b.modulate = Color(1.0, 0.72, 0.72, 1.0)
		elif can_cleanse:
			b.blocked = false; b.block_cue = ""; b.modulate = Color(0.72, 1.0, 0.78, 1.0)
		else:
			b.blocked = false; b.block_cue = ""; b.modulate = Color.WHITE
		b.queue_redraw()
	if _summoner_btn != null:
		var sc: bool = cleanse_summoner and kind != "suppress"
		_summoner_btn.blocked = locks_skill and not sc
		_summoner_btn.block_cue = label if _summoner_btn.blocked else ""
		_summoner_btn.modulate = Color(0.72, 1.0, 0.78, 1.0) if sc else (Color(1.0, 0.72, 0.72, 1.0) if locks_skill else Color.WHITE)
		_summoner_btn.queue_redraw()
	if _recover_btn != null:
		_recover_btn.blocked = locks_skill
		_recover_btn.block_cue = label if locks_skill else ""
		_recover_btn.modulate = Color(1.0, 0.72, 0.72, 1.0) if locks_skill else Color.WHITE
		_recover_btn.queue_redraw()
	if _attack_btn != null: _attack_btn.modulate = Color(1.0, 0.55, 0.55, 1.0) if locks_atk else Color.WHITE
	if _recall_btn != null: _recall_btn.dimmed = locks_skill; _recall_btn.modulate = Color(1.0, 0.68, 0.68, 1.0) if locks_skill else Color.WHITE
	if _joystick != null: _joystick.modulate = Color(0.65, 0.78, 1.0, 1.0) if locks_move else Color.WHITE
	if _cc_banner == null and _ui_root != null:
		_cc_banner = Label.new()
		_cc_banner.anchor_left = 0.28; _cc_banner.anchor_right = 0.72
		_cc_banner.anchor_top = 0.68; _cc_banner.anchor_bottom = 0.76
		_cc_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cc_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cc_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cc_banner.add_theme_font_size_override("font_size", int(28 * UiKit.scale()))
		_cc_banner.add_theme_constant_override("outline_size", 4)
		_cc_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_ui_root.add_child(_cc_banner)
	if _cc_banner != null:
		_cc_banner.visible = true
		_cc_banner.text = "%s  %.1fs" % [label, maxf(0.0, left)]
		_cc_banner.add_theme_color_override("font_color", tint)
		var lk := ""
		if locks_move: lk += "移动 "
		if locks_skill: lk += "技能/回城/恢复 "
		if locks_atk: lk += "普攻 "
		if lk != "": _cc_banner.text += " · " + lk + "锁定"
		elif kind == "slow": _cc_banner.text += " · 移速降低"


func set_joystick_external(v: Vector2) -> void:
	if _joystick != null and is_instance_valid(_joystick):
		_joystick.set_external_move(v)


func set_attack_priority(p: int) -> void:
	attack_priority = p if (p == PRIO_TOWER or p == PRIO_MINION) else PRIO_AUTO
	_sync_priority_buttons()

func get_move_mode() -> int:
	return move_mode

# —— P1b：技能按钮状态读取（与 TouchController.get_skill_held/get_skill_drag 同义）——

func is_skill_held(i: int) -> bool:
	if touch_active and i >= 0 and i < _skill_btns.size():
		return _skill_btns[i].is_held()
	return false

func get_skill_drag(i: int) -> Vector2:
	if touch_active and i >= 0 and i < _skill_btns.size():
		return _skill_btns[i].get_drag()
	return Vector2.ZERO

# 消费技能按钮松手施放信息：返回 {drag, cancel}；无松开事件返回空字典（索引 0..2；3=第4技能）
func consume_skill_release(i: int) -> Dictionary:
	if i < 0 or i >= _skill_release_pending.size():
		return {}
	var v: Dictionary = _skill_release_pending[i]
	_skill_release_pending[i] = {}
	return v

# 消费升级钮按下：返回被点的技能槽位（0..2），无则 -1
func consume_upgrade_press() -> int:
	var v := _upgrade_pending
	_upgrade_pending = -1
	return v

# —— P1b：NetClientBattle 每帧推送按钮显示状态（来源=own 块 + manifest，见 NetClientBattle）——
# 基础字段：name/level/max_level/cd(剩余)/cdmax(总量)/mana_ok
# 图标读数字段（M4-U，来自 own.sx，host 按 TouchController 同款烘焙）：iw(重施窗口0/1)/wl(窗口剩)/wt(窗口总)/
# sg(剩段数)/icon_dmg/icon_dmg_magic/icon_dmg2/icon_dmg2_magic/icon_count/icon_fx([[k,txt,hostile]]…)/
# icon_aa/charge_max/charge_now/blocked/block_cue —— 字段缺失时按钮回到「无图标」默认态
func set_skill_state(i: int, st: Dictionary) -> void:
	if i < 0 or i >= _skill_btns.size():
		return
	var b: SkillTouchButton = _skill_btns[i]
	var nm := str(st.get("name", ""))
	if b.display_name != nm:
		b.display_name = nm
	b.art_hero = str(st.get("hero", ""))
	var sid := str(st.get("sid", ""))
	b.art_skill = SkillDatabase.get_skill(sid) if sid != "" else null
	b.max_level = int(st.get("max_level", 0))
	b.skill_level = int(st.get("level", 0))
	var total := maxf(float(st.get("cdmax", 0.0)), 0.001)
	var cd := float(st.get("cd", 0.0))
	b.cd_ratio = clampf(cd / total, 0.0, 1.0)
	b.cd_total = total
	b.mana_ok = bool(st.get("mana_ok", true))
	# —— M4-U：技能键图标读数透传（own.sx 由 host 烘焙 TouchController 同款数据；键缺失=隐藏）——
	# 多段重施窗口（李白Q/夏侯惇Q…）：冷却遮罩让位给青色窗口扇形（同 host：窗口期 cd_ratio/cd_total=0）
	var iw := bool(st.get("iw", false))
	if iw:
		b.in_window = true
		b.win_left = float(st.get("wl", 0.0))
		b.win_total = maxf(float(st.get("wt", 1.0)), 0.001)
		b.segments_left = maxi(0, int(st.get("sg", 0)))
		b.cd_ratio = 0.0
		b.cd_total = 0.0
	else:
		b.in_window = false
		b.win_left = 0.0
		b.win_total = 1.0
		b.segments_left = 0
	b.icon_dmg = int(st.get("icon_dmg", -1))
	b.icon_dmg_magic = bool(st.get("icon_dmg_magic", false))
	b.icon_dmg2 = int(st.get("icon_dmg2", 0))
	b.icon_dmg2_magic = bool(st.get("icon_dmg2_magic", false))
	b.icon_count = int(st.get("icon_count", 0))
	b.icon_fx = _decode_net_fx(st.get("icon_fx", []))
	b.icon_aa = bool(st.get("icon_aa", false))
	b.blocked = bool(st.get("blocked", false))
	b.block_cue = str(st.get("block_cue", ""))
	b.charge_max = int(st.get("charge_max", 0))
	b.charge_now = int(st.get("charge_now", 0))
	b.queue_redraw()

# host 烘焙的 fx 网络行 [[k,txt,hostile(0/1)],…] → SkillTouchButton 用的 {k,txt,col} 小字行
func _decode_net_fx(rows) -> Array:
	var out: Array = []
	if rows is Array:
		for e in rows:
			if not (e is Array) or e.size() < 3:
				continue
			out.append({"k": str(e[0]), "txt": str(e[1]),
				"col": FX_DEBUFF_COL if int(e[2]) == 1 else FX_BUFF_COL})
	return out

# 普攻键读数（own.aa 原生数组 [伤害, 每秒攻速, 强化普攻0/1, 装备被动小字行…]）→
# AttackWheelButton 的伤害/攻速/强化态 + 装备被动小字（与 host _push_attack_stats 同屏内容）
func set_attack_state(aa: Array) -> void:
	if _attack_btn == null:
		return
	if aa.size() < 4:
		_attack_btn.set_item_rows([])
		return
	_attack_btn.set_battle_stats(int(aa[0]), float(aa[1]), int(aa[2]) == 1)
	var rows: Array = []
	for e in aa[3]:
		if not (e is Array) or e.size() < 5:
			continue
		var c := Color(1.0, 0.6, 0.3)
		var cs := str(e[4])
		if cs.begins_with("#") and cs.length() == 7:
			c = Color(cs.substr(1, 2).hex_to_int() / 255.0,
				cs.substr(3, 2).hex_to_int() / 255.0,
				cs.substr(5, 2).hex_to_int() / 255.0)
		rows.append({
			"k": str(e[0]), "name": str(e[1]), "txt": str(e[2]),
			"armed": int(e[3]) == 1, "col": c,
		})
	_attack_btn.set_item_rows(rows)

# 第4技能按钮（兰陵王·隐身）状态 + 显隐
func set_extra_skill_state(st: Dictionary) -> void:
	if _extra_skill_btn == null:
		return
	var b: SkillTouchButton = _extra_skill_btn
	var nm := str(st.get("name", ""))
	if b.display_name != nm:
		b.display_name = nm
	# 与 host 一致：英雄元素色 + 技能纹样（host TouchController._update_skill_button_ui 对 i=3 同样推送 art_hero/art_skill）
	b.art_hero = str(st.get("hero", ""))
	var sid4 := str(st.get("sid", ""))
	b.art_skill = SkillDatabase.get_skill(sid4) if sid4 != "" else null
	b.max_level = int(st.get("max_level", 1))
	b.skill_level = maxi(int(st.get("level", 1)), 1)
	var total := maxf(float(st.get("cdmax", 0.0)), 0.001)
	var cd := float(st.get("cd", 0.0))
	b.cd_ratio = clampf(cd / total, 0.0, 1.0)
	b.cd_total = total
	# 第4技能在 host 不画任何图标读数（TouchController L1053-1063 全清），此处同态复位
	b.mana_ok = bool(st.get("mana_ok", true))
	b.in_window = false
	b.win_left = 0.0
	b.win_total = 1.0
	b.segments_left = 0
	b.icon_dmg = -1
	b.icon_dmg_magic = false
	b.icon_dmg2 = 0
	b.icon_dmg2_magic = false
	b.icon_count = 0
	b.icon_fx = []
	b.icon_aa = false
	b.blocked = false
	b.block_cue = ""
	b.charge_max = 0
	b.charge_now = 0
	b.queue_redraw()

func set_extra_skill_visible(v: bool) -> void:
	if _extra_skill_btn:
		_extra_skill_btn.visible = v

# 升级“+”钮显隐（仅该技能可升级时显示，与主机 Hero.can_upgrade_skill 判定同源）
func set_upgrade_visible(i: int, v: bool) -> void:
	if i >= 0 and i < _upgrade_btns.size():
		(_upgrade_btns[i] as TouchActionButton).glow = v
		_upgrade_btns[i].visible = v

# —— P1c：召唤师 / 恢复 / 回城 / 主动装 / 取消施法状态读取与消费 ——

func get_summoner_held() -> bool:
	if touch_active and _summoner_btn:
		return _summoner_btn.is_held()
	return false

func get_summoner_drag() -> Vector2:
	if touch_active and _summoner_btn:
		return _summoner_btn.get_drag()
	return Vector2.ZERO

# 消费召唤师按钮松开信息（{drag, cancel}；空字典=无松开事件）
func consume_summoner_release() -> Dictionary:
	var v: Dictionary = _summoner_release_pending
	_summoner_release_pending = {}
	return v

func consume_recover_press() -> bool:
	var v := _recover_press_pending
	_recover_press_pending = false
	return v

func consume_recall_press() -> bool:
	var v := _recall_press_pending
	_recall_press_pending = false
	return v

func consume_active_press() -> int:
	var v := _active_press_pending
	_active_press_pending = -1
	return v

# 召唤师按钮显示状态（NetClientBattle 用 own 块喂值）：具体召唤师名 / 冷却遮罩 / 惩击副字
func set_summoner_state(st: Dictionary) -> void:
	if _summoner_btn == null:
		return
	var b := _summoner_btn
	var nm := str(st.get("name", ""))
	if b.display_name != nm:
		b.display_name = nm
	var total := maxf(float(st.get("cdmax", 0.0)), 0.001)
	var cd := float(st.get("cd", 0.0))
	b.cd_ratio = clampf(cd / total, 0.0, 1.0)
	b.cd_total = total
	b.mana_ok = true
	b.icon_dmg = -1
	b.icon_fx = []
	# 惩击按钮下方显示对野怪/史诗怪物的伤害值（随英雄等级成长，同主机）
	if nm == "惩击":
		b.sub_text = "%d" % (1500 + int(st.get("level", 1)) * 100)
	else:
		b.sub_text = ""
	b.queue_redraw()

# 恢复按钮：冷却总量=恢复技能 cooldown（60s），剩余=own.cd[4]，画暗色冷却遮罩 + 剩余秒数
func set_recover_state(st: Dictionary) -> void:
	if _recover_btn == null:
		return
	var b := _recover_btn
	var total := maxf(float(st.get("cdmax", 60.0)), 0.001)
	var cd := float(st.get("cd", 0.0))
	b.cd_ratio = clampf(cd / total, 0.0, 1.0)
	b.cd_total = total
	b.queue_redraw()

# 主动装备钮显隐（own.act 驱动：仅拥有对应主动装时显示，同主机）
func set_active_visible(i: int, v: bool) -> void:
	if i >= 0 and i < _active_btns.size():
		_active_btns[i].visible = v

# 取消施法按钮：任一技能/召唤师按钮按住瞄准时显示；手指拖到其上时高亮（同主机 TouchController）
func refresh_cancel_aim() -> void:
	if _cancel_btn == null:
		return
	var aiming := false
	var over := false
	var aim_btns: Array = _skill_btns.duplicate()
	if _extra_skill_btn != null:
		aim_btns.append(_extra_skill_btn)
	if _summoner_btn != null:
		aim_btns.append(_summoner_btn)
	for b in aim_btns:
		if b.is_held():
			aiming = true
			var tg: Vector2 = b.get_touch_global()
			if tg != Vector2.ZERO and _cancel_btn.get_global_rect().has_point(tg):
				over = true
			break
	_cancel_btn.visible = aiming
	_cancel_btn.set_highlighted(over)

# —— 内部回调 ——

func _on_move_mode_changed(m: int) -> void:
	move_mode = m
	move_mode_changed.emit(m)

func _on_attack_pressed_changed(pressed: bool) -> void:
	if pressed:
		_attack_release_pending = {}   # 清除上一手残留的松手信息

func _on_attack_released(final_drag: Vector2, cancelled: bool) -> void:
	_attack_release_pending = {"drag": final_drag, "cancel": cancelled}

func _sync_priority_buttons() -> void:
	_tower_btn.toggled = attack_priority == PRIO_TOWER
	_tower_btn.queue_redraw()
	_minion_btn.toggled = attack_priority == PRIO_MINION
	_minion_btn.queue_redraw()

# 技能按钮按下：清除上一手的松手施放信息（新手势从零开始）
func _on_skill_pressed_changed(index: int, pressed: bool) -> void:
	if pressed and index >= 0 and index < _skill_release_pending.size():
		_skill_release_pending[index] = {}

# 技能按钮松开（王者荣耀式）：记录最终拖拽与「拖回按钮取消」标记，供 NetClientBattle 施放消费。
# 取消判定（同主机）：① 拖出去又拖回按钮（cancelled）② 松手落在取消施法按钮上。
# 索引 3 为第4技能（点按即放；仍保留拖回取消语义）。
func _on_skill_released(index: int, final_drag: Vector2, cancelled: bool, release_global: Vector2) -> void:
	if index >= 0 and index < _skill_release_pending.size():
		var cancel := cancelled
		if not cancel and _cancel_btn and _cancel_btn.visible \
				and _cancel_btn.get_global_rect().has_point(release_global):
			cancel = true
		_skill_release_pending[index] = {"drag": final_drag, "cancel": cancel}

# 升级“+”钮按下：记录待消费槽位（NetClientBattle 每帧消费后发 C_UPGRADE）
func _on_upgrade_pressed(i: int) -> void:
	_upgrade_pending = i

# 召唤师按钮按下：清除上一手的松手信息（新手势从零开始）
func _on_summoner_pressed_changed(_index: int, pressed: bool) -> void:
	if pressed:
		_summoner_release_pending = {}

# 召唤师按钮松开（王者荣耀式）：拖拽方向=位移类技能（如闪现）的施放方向；拖到取消键再松手=取消
func _on_summoner_released(_index: int, final_drag: Vector2, cancelled: bool, release_global: Vector2) -> void:
	var cancel := cancelled
	if not cancel and _cancel_btn and _cancel_btn.visible \
			and _cancel_btn.get_global_rect().has_point(release_global):
		cancel = true
	_summoner_release_pending = {"drag": final_drag, "cancel": cancel}

# 主动装按钮按下：记录待消费索引（NetClientBattle 每帧消费后发 C_ACTIVE）
func _on_active_pressed(i: int) -> void:
	_active_press_pending = i

# —— 右半屏拖拽相机（同 TouchController：只吃未被按钮/摇杆消费的空白区触摸）——
var cam_pan_index := -1
var cam_pan_start := Vector2.ZERO
var cam_pan_cur := Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if not touch_active or not visible:
		cam_pan_index = -1
		return
	if event is InputEventScreenTouch and not event.pressed and event.index == cam_pan_index:
		cam_pan_index = -1
		return
	if event is InputEventScreenTouch and event.pressed and cam_pan_index < 0:
		var vp := get_viewport().get_visible_rect().size
		if event.position.x >= vp.x * 0.5:
			cam_pan_index = event.index
			cam_pan_start = event.position
			cam_pan_cur = event.position
	elif event is InputEventScreenDrag and event.index == cam_pan_index:
		cam_pan_cur = event.position

# 相机拖拽状态（NetClientBattle 每帧轮询读取；松手由客户端 10/s 回正）
func camera_pan_active() -> bool:
	return cam_pan_index >= 0

func get_camera_pan_current() -> Vector2:
	return cam_pan_cur
