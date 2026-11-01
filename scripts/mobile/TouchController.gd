extends Node
const IconArt = preload("res://scripts/ui/IconArt.gd")
const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const SkillArt = preload("res://scripts/ui/SkillArt.gd")
## 移动端触摸控制总控（autoload: TouchController）
## - 左下固定摇杆：移动（中心固定，仅距中心一定距离内按下才激活）
## - 右下技能按钮：按下瞄准、拖动定方向、松开施放（外圈金环按等级分段）
## - 普攻大按钮（右下角）/ 召唤师技能 / 恢复 / 回城 / 主动装备
## - 召唤师技能：按住拖动选方向（闪现等位移类）、松开施放
## - 桌面 WASD 两种移动模式切换（转向 / 前后左右，见 MoveModeToggle）
## - 每个技能上方的“+”升级按钮（仅该技能可升级时显示）
## - 桌面调试：F2 显示/隐藏触摸层（配合 emulate_touch_from_mouse 模拟触摸）

const SKILL_COUNT := 3
# 触摸层按键整体尺寸：相比原版整体放大 2 倍（技能 / 普攻 / 升级 / 主动装 / 横带）
const SKILL_SIZE := 260.0
const UPGRADE_SIZE := 176.0
const ACTIVE_SIZE := 230.0

# 敌人索敌头像条：攻击范围内敌人 ≥2 时，沿技能扇形「外侧」同圆心弧线排布（点击锁定普攻/技能目标）
const PICKER_MAX := 5
const PICKER_SIZE := 118.0
const PICKER_RADIUS := 800.0     # 比技能扇半径 560 再外扩一圈，落在技能键外沿之外
const PICKER_ANGLE_MIN := 8.0    # 0°=普攻正上方（正方向朝屏幕左侧），与技能扇同角度基准
const PICKER_ANGLE_MAX := 76.0

# 普攻键 —— 技能扇形唯一的圆心
const ATTACK_POS := Vector2(40, 40)
const ATTACK_SIZE := 350.0
# 技能扇形：1/2/3 技能在同一圆弧上，圆弧圆心 = 普攻中心。
# 半径取 560：260px 技能键在相邻 35° 角下互不重叠（弦长≈2·560·sin17.5°≈337>260），
# 且放大后扇形最高处（大招上沿）距屏幕底约 905 < 1400，整簇可完整显示。
const FAN_RADIUS := 560.0
# 各技能相对圆心的角度：0° = 普攻正上方，正方向朝屏幕左侧；
# 1 技能(70°)最贴近普攻、可高频施放，3 大招(0°)在最高点
const SKILL_FAN_ANGLES_DEG := [70.0, 35.0, 0.0]
# 底部横向条带（回城|恢复|召唤师）底部高度，留出安全区
const ROW_FROM_BOTTOM := 30.0

# 右下角整簇触摸按键（普攻轮盘 + 技能扇形 + 升级/横带 + 推塔/小兵 + 主动装 + 取消）
# 相对屏幕右下角的整体“左 / 上”留白增量。_anchor_br 默认把它加到 from_br 上，整簇作为刚体
# 平移、内部相对布局不变；调大 = 继续向左上移，调小 = 回右下。摇杆（手锚定）与桌面 WASD
# 切换键 mm（显式传 Vector2.ZERO）不属于该簇，不受影响。
const TOUCH_CLUSTER_INSET := Vector2(80, 20)

# 普攻目标优先级（王者荣耀式：推塔/小兵键切换，再按一次取消）。只影响玩家英雄普攻的自动选敌：
# - AUTO   自动：范围内英雄（最低血）优先，其次小兵/塔/野怪（最低血）
# - TOWER  推塔：范围内优先攻击防御塔；无塔时回退自动规则
# - MINION 小兵：范围内优先攻击小兵与野怪；无时回退自动规则
const ATTACK_PRIORITY_AUTO := 0
const ATTACK_PRIORITY_TOWER := 1
const ATTACK_PRIORITY_MINION := 2

# 桌面键盘移动模式
const MOVE_MODE_TURN := 0      # 转向模式（现状）：A/D 原地转向，W/S 沿面朝前后移动
const MOVE_MODE_DIR := 1       # 前后左右模式：W/S/A/D 按屏幕方向直接移动

# 按住技能按钮超过该时长 → 在按钮左侧弹出技能详情面板（展示该技能的全部数值信息）
const SKILL_DETAIL_HOLD := 2.0
const SKILL_TYPE_NAMES := {
	0: "目标", 1: "范围", 2: "增益", 3: "直线", 4: "位移", 5: "多段", 6: "护盾",
}
# 效果条目标签（fx item 的 t）→ 圆底汉字图标 + 底色。两参类型(slow/selfspeed/…)取 v%d%·d秒，
# 秒参类型(stun/knockup/freeze/suppress/bt)取 v 为秒，数值类型(shield/heal)直接取 v 数值。
const FX_META := {
	"slow":      {"ic": "缓", "c": Color(0.35, 0.78, 1.0), "two": true},
	"selfspeed": {"ic": "速", "c": Color(0.55, 1.0, 0.6), "two": true},
	"stun":      {"ic": "晕", "c": Color(1.0, 0.88, 0.4), "sec": true},
	"knockup":   {"ic": "飞", "c": Color(1.0, 0.68, 0.32), "sec": true},
	"freeze":    {"ic": "冰", "c": Color(0.5, 0.82, 1.0), "sec": true},
	"suppress":  {"ic": "压", "c": Color(1.0, 0.5, 0.5), "sec": true},
	"bt":        {"ic": "霸", "c": Color(1.0, 0.82, 0.35), "sec": true},
	"shield":    {"ic": "盾", "c": Color(0.52, 0.72, 1.0)},
	"heal":      {"ic": "愈", "c": Color(0.6, 1.0, 0.7)},
	# 属性类增益/削减（数值取自各技能真实公式；图标=双抗/物抗/魔抗/攻速/攻击，配色绿=自身增益·蓝=对敌负面）：
	# durs=数值提升+时长（如“+150 5S”）；two=百分比+时长（如“50% 5S”）；num=数值削减+时长（如“-90 3S”）
	"defup":     {"ic": "抗", "c": Color(0.6, 1.0, 0.72), "durs": true},   # 双抗提升（两抗同额）
	"defdn":     {"ic": "削", "c": Color(0.55, 0.85, 1.0), "two": true},   # 双防削减
	"armup":     {"ic": "甲", "c": Color(0.6, 1.0, 0.72), "durs": true},   # 护甲提升
	"armdn":     {"ic": "甲", "c": Color(0.55, 0.85, 1.0), "two": true},   # 护甲削减
	"mrup":      {"ic": "魔", "c": Color(0.6, 1.0, 0.72), "durs": true},   # 魔抗提升
	"mrdn":      {"ic": "魔", "c": Color(0.55, 0.85, 1.0), "num": true},   # 魔抗削减（数值类：不知火舞二技能为固定数值削减，区别于百分比）
	"asup":      {"ic": "攻", "c": Color(0.6, 1.0, 0.72), "two": true},    # 攻速提升
	"asdn":      {"ic": "钝", "c": Color(0.55, 0.85, 1.0), "two": true},   # 攻速削减
	"atkdn":     {"ic": "攻", "c": Color(0.55, 0.85, 1.0), "two": true},   # 攻击力削减（百分比：不知火舞大招命中削减敌人攻击）
	"msup":      {"ic": "速", "c": Color(0.55, 1.0, 0.6), "durs": true},   # 自身移速数值提升（沈梦溪1/2投掷疾跑、铠3大招等固定+移速，非百分比）
	"armred":    {"ic": "甲", "c": Color(0.55, 0.85, 1.0), "num": true},   # 护甲固定数值削减（李白2剑阵命中：-(120+30·Lv)点，区别于 armdn 的百分比）
	"unsel":     {"ic": "免", "c": Color(0.6, 1.0, 0.72), "sec": true},    # 无法选中/免伤免控（李白2剑阵3秒、李白3穿梭2.5秒；wd_timer 时长）
	"cleanse":   {"ic": "净", "c": Color(0.6, 1.0, 0.72), "flag": true},   # 净化自身（李白2/狄仁杰2 施放瞬间；纯图标，无数值/时长）
}
# 技能键效果小字的两种配色：作用于敌人的负面效果 → 蓝；作用于自身/友军的增益 → 绿
const FX_HOSTILE_TYPES := [
	"slow", "stun", "knockup", "freeze", "suppress",
	"defdn", "armdn", "armred", "mrdn", "asdn", "atkdn",   # 削减双抗/护甲/魔抗/攻速/攻击（对敌；armred=护甲固定数值削减）
]
const FX_BUFF_COL := Color(0.45, 1.0, 0.62)
const FX_DEBUFF_COL := Color(0.55, 0.85, 1.0)
# 召唤师技能一句话效果说明（与英雄选择界面一致，详情面板底部展示）
const SUMMONER_DESCRIPTIONS := {
	"闪现": "向指定方向瞬间移动一段距离",
	"疾跑": "短时间内获得高额移动速度加成",
	"传送": "引导后传送至友方建筑或小兵",
	"治疗术": "回复自身及周围友军生命值",
	"终结": "对残血敌人造成高额真实伤害",
	"狂暴": "短时间内提升伤害、韧性与吸血",
	"晕眩": "眩晕周围敌人并造成减速",
	"净化": "解除控制并获得短暂霸体",
	"弱化": "减少周围敌人攻击力，提升自身防御",
	"惩击": "对野怪造成巨额伤害并减速",
}

var touch_layer: CanvasLayer
var _gameplay_root: Control          # 摇杆 + 技能 + 普攻等（全屏面板打开时隐藏）
# 不标 JoystickPad 类型：编辑器对 class_name 脚本的类缓存会滞后，静态类型引用会误报
# （注：类名不能叫 VirtualJoystick——Godot 4.6+ 有同名原生类，会 Parse Error "hides a native class"）
var _joystick
var _skill_buttons: Array = []
var _attack_button: AttackWheelButton
var _upgrade_buttons: Array = []
var _active_equip_buttons: Array = []
var _cancel_btn: CancelCastButton    # 拖动技能/召唤师瞄准时出现的取消施法按钮
var _summoner_button: SkillTouchButton    # 召唤师技能按钮（按住拖方向、松开施放）
var _recover_button: SkillTouchButton     # 恢复按钮（按下即时回血、显示 60s 冷却遮罩）
var _extra_skill_button: SkillTouchButton  # 第4技能按钮(真实第4技能槽英雄=兰陵王隐身才显示)
var _picker_root: Control = null           # 敌人索敌头像条容器
var _picker_buttons: Array = []            # 复用的头像按钮池（_EnemyAvatar）
var _picker_tap_ms := 0                     # 兜底命中防重复触发（触摸+模拟鼠标可能成对到达）
var _picker_tap_id := 0

var _move_mode_btn: MoveModeToggle        # 桌面 WASD 移动模式切换（手机端隐藏）

# 边缘触发缓存（被消费后清除）
var _skill_press_pending: Array = [false, false, false, false]

# 王者荣耀式松开施放：松开技能按钮时的最终拖拽/取消信息（字典 {drag, cancel}，空=无）
var _skill_release_pending: Array = [{}, {}, {}, {}]

# 普攻轮盘松手选敌信息（字典 {drag, cancel}，空=无）
var _attack_release_pending: Dictionary = {}
# 召唤师按钮松手信息（{drag, cancel}，空=无）；拖拽方向=闪现等位移类技能的方向
var _summoner_release_pending: Dictionary = {}
var _recover_press_pending := false
var _recall_press_pending := false

var _tower_button: TouchActionButton      # 推塔键（普攻键上方）：切换普攻目标优先级=防御塔
var _minion_button: TouchActionButton     # 小兵键（推塔键左侧）：切换普攻目标优先级=小兵/野怪
var _attack_priority := ATTACK_PRIORITY_AUTO   # 当前普攻目标优先级（见顶部常量）
var _priority_press_pending := -1         # 待消费的优先级按键（TOWER/MINION），-1=无

var move_mode := MOVE_MODE_DIR  # 默认前后左右（W/S/A/D 直接按屏幕方向）

# 按住技能查看详情（状态与面板）
var _skill_detail_panel: Panel = null
var _skill_detail_title: Label = null
var _skill_detail_tag: Label = null
var _skill_detail_body: RichTextLabel = null
var _skill_detail_icon: Control = null
var _skill_detail_accent: ColorRect = null
var _skill_detail_divider: ColorRect = null
var _skill_detail_section: Label = null
var _skill_detail_fx_title: Label = null
var _skill_detail_hint: Label = null
var _fx_holder: Control = null      # 效果“圆角徽章”的承载体（详情面板下方，普通 Control 手动排布）
var _detail_index := -1              # 当前展示的技能详情（-1=无；0..2=英雄技能，3=召唤师）
var _hold_start: Array = [-1.0, -1.0, -1.0, -1.0]   # 每个候选按钮的按住起始时刻（秒）

var touch_active := false
var intro_hidden := false   # 开局运镜期间隐藏全部触摸 HUD
var hero: Hero = null

# —— 右半屏拖拽相机（王者式：空白区拖动看视野，松手由 BattleManager 回正）——
var cam_pan_index: int = -1
var cam_pan_start: Vector2 = Vector2.ZERO
var cam_pan_cur: Vector2 = Vector2.ZERO

# 运行时获取 UiManager 自动加载实例（不依赖分析期自动加载名注册）
@onready var _ui_mgr: UI_Manager = get_node("/root/UiManager") as UI_Manager

func _ready():
	# 电脑版与手机完全一致：两端都启用触摸操作层。
	# 桌面端用鼠标模拟触摸（emulate_touch_from_mouse），可点击/拖拽触摸按钮操作；
	# 移动端开启触摸→鼠标模拟，让普通 Button（商店/英雄选择等）响应触摸。
	Input.set_emulate_touch_from_mouse(not Config.on_mobile())
	Input.set_emulate_mouse_from_touch(Config.on_mobile())
	touch_active = true
	_build_ui()
	_update_visibility()

func _input(event):
	# 锁敌头像优先于世界点击：在 _input 阶段按头像矩形命中，避免被全屏容器/世界点击抢走。
	if not touch_active or hero == null or not is_instance_valid(hero):
		return
	if _gameplay_root and not _gameplay_root.visible:
		return
	if event is InputEventScreenTouch and event.pressed and _try_tap_enemy_picker(event.position):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and _try_tap_enemy_picker(event.position):
		get_viewport().set_input_as_handled()

func _unhandled_input(event):
	# F2：桌面调试切换触摸层（移动端不受影响）
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		touch_active = not touch_active
		Input.set_emulate_touch_from_mouse(touch_active)
		cam_pan_index = -1
		_update_visibility()
		return

	# 右半屏拖拽相机：只响应未被按钮/摇杆/轮盘消费的触摸（即空白区）。
	# 先处理“抬起”：即使中途打开了商店等全屏面板，也要解除占用，避免残留卡死。
	if event is InputEventScreenTouch and not event.pressed and event.index == cam_pan_index:
		cam_pan_index = -1
		return

	if not touch_active:
		return
	if not hero or not is_instance_valid(hero):
		return
	if _gameplay_root and not _gameplay_root.visible:
		return
	if event is InputEventScreenTouch and event.pressed and cam_pan_index < 0:
		var vp := get_viewport().get_visible_rect().size
		if event.position.x >= vp.x * 0.5:
			cam_pan_index = event.index
			cam_pan_start = event.position
			cam_pan_cur = event.position
	elif event is InputEventScreenDrag and event.index == cam_pan_index:
		cam_pan_cur = event.position

# 相机拖拽状态（BattleManager 每帧轮询读取）
func camera_pan_active() -> bool:
	return cam_pan_index >= 0

func get_camera_pan_current() -> Vector2:
	return cam_pan_cur


func _process(_delta):
	_update_visibility()
	# 全屏面板打开 / 触摸层关闭时，终止可能残留的相机拖拽占用
	if (not touch_active) or (_gameplay_root and not _gameplay_root.visible):
		cam_pan_index = -1
	if not touch_active:
		return
	if hero and is_instance_valid(hero):
		_update_enemy_picker()
		_update_skill_button_ui()
		_push_attack_stats()
		_update_skill_detail()

func set_hero(h: Hero):
	hero = h

# ---------------- 敌人索敌头像条（技能扇形外侧弧线） ----------------

# 每帧扫描玩家攻击范围内的敌人：范围内有敌方英雄就出现头像；按距离排序取前 PICKER_MAX 个，
# 沿与技能扇同圆心、更大半径的弧线布点；高亮 = 当前锁定目标（Hero.manual_target）。
func _try_tap_enemy_picker(pos: Vector2) -> bool:
	if _picker_root == null or not _picker_root.visible:
		return false
	for av in _picker_buttons:
		if av.visible and av.get_global_rect().has_point(pos):
			if not is_instance_valid(av.entity):
				return false
			var now := Time.get_ticks_msec()
			var eid: int = av.entity.get_instance_id()
			if now - _picker_tap_ms < 300 and eid == _picker_tap_id:
				return true   # 触摸与模拟鼠标成对到达：只切换一次
			_picker_tap_ms = now
			_picker_tap_id = eid
			_on_enemy_picker_tapped(av.entity)
			return true
	return false

func _update_enemy_picker():
	if _picker_root == null:
		return
	if not PlayerPrefs.opt_bool("lock_portrait", true):
		_picker_root.visible = false
		return
	if hero == null or not is_instance_valid(hero) or hero.health <= 0:
		_picker_root.visible = false
		return
	var reach: float = hero.attack_range * 0.01
	var list: Array = []
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == hero or not (ent is GameEntity) or ent.health <= 0 or ent.team == hero.team:
			continue
		# 锁敌条只锁定英雄：小兵/防御塔/野怪一律不上头像（用下方推塔/小兵优先级键处理）
		if not (ent is Hero):
			continue
		if (ent as Hero).is_invisible_to_enemy() or (ent as Hero).is_untargetable_by_enemies():
			continue   # 隐身/不可选中的英雄不该出现在索敌条上
		if hero.global_position.distance_to(ent.global_position) - ent.body_radius > reach:
			continue
		list.append(ent)
	if list.is_empty():
		_picker_root.visible = false
		return   # 范围内没有敌方英雄时隐藏
	var hpos: Vector3 = hero.global_position
	list.sort_custom(func(a, b): return hpos.distance_squared_to(a.global_position) < hpos.distance_squared_to(b.global_position))
	if list.size() > PICKER_MAX:
		list = list.slice(0, PICKER_MAX)
	_picker_root.visible = true
	var n: int = list.size()
	var atk_center := ATTACK_POS + Vector2(ATTACK_SIZE, ATTACK_SIZE) * 0.5
	for i in range(_picker_buttons.size()):
		var av = _picker_buttons[i]
		if i >= n:
			av.visible = false
			continue
		var ent = list[i]
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var ang := deg_to_rad(lerpf(PICKER_ANGLE_MIN, PICKER_ANGLE_MAX, t))
		var pos: Vector2 = atk_center + Vector2(PICKER_RADIUS * sin(ang), PICKER_RADIUS * cos(ang))
		_anchor_br(av, pos - Vector2(PICKER_SIZE, PICKER_SIZE) * 0.5, Vector2(PICKER_SIZE, PICKER_SIZE))
		av.visible = true
		av.entity = ent
		av.hero_name = str(ent.display_name)
		av.kind = "hero"   # 锁敌条只锁英雄
		av.dead = false
		av.locked = (hero.locked_target == ent)
		av.queue_redraw()


# 点头像：锁定该敌人（普攻自动追击/攻击、技能以此为瞄准目标）；再点一次取消锁定
func _on_enemy_picker_tapped(ent) -> void:
	if hero == null or not is_instance_valid(hero) or not is_instance_valid(ent):
		return
	if not (ent is Hero):
		return   # 只允许锁定英雄
	if hero.locked_target == ent:
		hero.set_locked_target(null)
	else:
		hero.set_locked_target(ent)   # 单独记录锁敌目标（内部同步 manual_target）
		hero.current_target = ent     # 锁敌头像就是当前目标，技能/普攻共用
	_update_enemy_picker()

# 每帧把当前普攻伤害与攻击速度（次/秒）推送到普攻键上显示；
# 若下一次普攻为强化普攻（亚瑟Q/孙悟空被动等），显示强化后的伤害并切换为金色高亮
func _push_attack_stats():
	if _attack_button and hero and is_instance_valid(hero):
		var preview: Dictionary = hero._attack_button_preview()
		_attack_button.set_battle_stats(
			int(preview.get("dmg", round(hero.actual_attack_damage))),
			hero.attack_speed * hero.attack_speed_timer,
			bool(preview.get("enhanced", false)))
		# 装备被动对普攻的影响（每件生效装一行：小图标+短名+实时数值）
		_attack_button.set_item_rows(hero.aa_item_passive_rows())

# ---------------- 技能详情面板（按住技能按钮 >2 秒 → 按钮左侧弹出） ----------------

# 每帧检测：任一技能/召唤师按钮按住超过 SKILL_DETAIL_HOLD → 弹出详情；松开即收起。
func _update_skill_detail():
	if not touch_active or not _gameplay_root or not _gameplay_root.visible \
			or not hero or not is_instance_valid(hero):
		if _detail_index >= 0:
			_hide_skill_detail()
		_reset_skill_hold_timers()
		return
	# 收集当前按住的候选（0..2=英雄技能，3=召唤师）
	var held: Array = []
	for i in range(3):
		if i < _skill_buttons.size() and _skill_buttons[i].is_held():
			held.append(i)
	if _summoner_button and _summoner_button.is_held():
		held.append(3)
	if held.is_empty():
		if _detail_index >= 0:
			_hide_skill_detail()
		# 松开后必须清掉起始时刻，否则下一次按下会沿用旧时间戳、瞬间弹详情
		_reset_skill_hold_timers()
		return
	# 未被按住的按钮清除计时（重新按下从头计时）
	for i in range(_hold_start.size()):
		if not held.has(i):
			_hold_start[i] = -1.0
	# 正在展示的技能已松开 → 收起
	if _detail_index >= 0 and not held.has(_detail_index):
		_hide_skill_detail()
	var now := Time.get_ticks_msec() * 0.001
	var target := -1
	var earliest := INF
	for i in held:
		if _hold_start[i] < 0.0:
			_hold_start[i] = now
		if _hold_start[i] < earliest:
			earliest = _hold_start[i]
			target = i
	if _detail_index != target and now - _hold_start[target] >= SKILL_DETAIL_HOLD:
		_open_skill_detail(target)

func _create_skill_detail_panel():
	var rs := _ui_mgr.ui_scale() if _ui_mgr else 1.35
	_skill_detail_panel = Panel.new()
	_skill_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiKit.flat(0.97, 16, 2, Color(0.44, 0.78, 1.0, 0.52),
		Color(0.035, 0.055, 0.085, 0.97), 0.0, 16.0)
	_skill_detail_panel.add_theme_stylebox_override("panel", sb)
	_gameplay_root.add_child(_skill_detail_panel)
	# 顶部强调线：给详情卡一个明确的第一眼层次，不靠满屏边框堆装饰
	_skill_detail_accent = ColorRect.new()
	_skill_detail_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_accent.color = Color(0.44, 0.78, 1.0, 0.8)
	_skill_detail_panel.add_child(_skill_detail_accent)
	_skill_detail_icon = _DetailSkillIcon.new()
	_skill_detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_panel.add_child(_skill_detail_icon)
	_skill_detail_title = Label.new()
	_skill_detail_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_title.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	_skill_detail_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_skill_detail_title.add_theme_constant_override("outline_size", 2)
	_skill_detail_title.add_theme_font_size_override("font_size", int(round(23.0 * rs)))
	_skill_detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_detail_panel.add_child(_skill_detail_title)
	_skill_detail_tag = Label.new()
	_skill_detail_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_tag.add_theme_color_override("font_color", Color(0.56, 0.76, 0.94, 0.95))
	_skill_detail_tag.add_theme_font_size_override("font_size", int(round(14.0 * rs)))
	_skill_detail_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_skill_detail_panel.add_child(_skill_detail_tag)
	_skill_detail_divider = ColorRect.new()
	_skill_detail_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_divider.color = Color(0.42, 0.58, 0.78, 0.22)
	_skill_detail_panel.add_child(_skill_detail_divider)
	_skill_detail_section = Label.new()
	_skill_detail_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_section.text = "技能数据"
	_skill_detail_section.add_theme_color_override("font_color", Color(0.52, 0.62, 0.76, 0.9))
	_skill_detail_section.add_theme_font_size_override("font_size", int(round(12.0 * rs)))
	_skill_detail_panel.add_child(_skill_detail_section)
	_skill_detail_body = RichTextLabel.new()
	_skill_detail_body.bbcode_enabled = true
	_skill_detail_body.scroll_active = false
	_skill_detail_body.fit_content = true
	_skill_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_detail_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_body.add_theme_font_size_override("normal_font_size", int(round(15.0 * rs)))
	_skill_detail_body.add_theme_color_override("default_color", Color(0.84, 0.89, 0.96))
	_skill_detail_body.add_theme_constant_override("line_separation", int(round(5.0 * rs)))
	_skill_detail_panel.add_child(_skill_detail_body)
	# 效果徽章区（放数值行之后；open 时按 fx 数量重建并手动排布）
	_skill_detail_fx_title = Label.new()
	_skill_detail_fx_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_fx_title.text = "附加效果"
	_skill_detail_fx_title.add_theme_color_override("font_color", Color(0.52, 0.62, 0.76, 0.9))
	_skill_detail_fx_title.add_theme_font_size_override("font_size", int(round(12.0 * rs)))
	_skill_detail_panel.add_child(_skill_detail_fx_title)
	_fx_holder = Control.new()
	_fx_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_panel.add_child(_fx_holder)
	_skill_detail_hint = Label.new()
	_skill_detail_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skill_detail_hint.text = "松开收起"
	_skill_detail_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skill_detail_hint.add_theme_color_override("font_color", Color(0.48, 0.56, 0.68, 0.85))
	_skill_detail_hint.add_theme_font_size_override("font_size", int(round(11.0 * rs)))
	_skill_detail_panel.add_child(_skill_detail_hint)
	_skill_detail_panel.visible = false

func _open_skill_detail(which: int):
	if _skill_detail_panel == null or hero == null:
		return
	# 标题 = 技能名（召唤师技能取 hero.summoner_skill）
	var sk: Skill = null
	if which == 3:
		sk = hero.summoner_skill
	elif which >= 0 and which < hero.skills.size():
		sk = hero.skills[which]
	if sk == null or sk.skill_name == "":
		return
	var btn: Control = _summoner_button if which == 3 else (_skill_buttons[which] if which < _skill_buttons.size() else null)
	if btn == null:
		return
	# 英雄技能才取“弹数/效果”数据；召唤师技能保持原展示（面板底部有专属说明行）
	var fx_info := {}
	if which < 3 and hero:
		fx_info = SkillDatabase.get_skill_fx(hero, which)
	var body_text := _build_skill_detail_body(which)
	if body_text == "":
		return
	_detail_index = which
	var rs := _ui_mgr.ui_scale() if _ui_mgr else 1.35
	var accent := Vfx.color_for_hero(hero.display_name)
	_skill_detail_panel.add_theme_stylebox_override("panel",
		UiKit.flat(0.97, 16, 2, Color(accent.r, accent.g, accent.b, 0.58),
			Color(0.035, 0.055, 0.085, 0.97), 0.0, 16.0))
	_skill_detail_accent.color = Color(accent.r, accent.g, accent.b, 0.88)
	# 头部：技能图标 + 技能名 +「槽位·等级」小标签
	_skill_detail_icon.setup(hero.display_name, sk, which,
		_summoner_button.icon_kind if which == 3 and _summoner_button else "")
	_skill_detail_title.text = sk.skill_name
	_skill_detail_title.add_theme_font_size_override("font_size", int(round(23.0 * rs)))
	_skill_detail_tag.text = _detail_slot_tag(which)
	_skill_detail_tag.add_theme_font_size_override("font_size", int(round(13.5 * rs)))
	# 数值区：RichTextLabel 开启 fit_content，用实际内容高度排版，避免长文本被裁切
	var vp := get_viewport().get_visible_rect().size
	var pad := 16.0 * rs
	var panel_w := minf(380.0 * rs, vp.x - 28.0)
	var content_w := panel_w - pad * 2.0
	var icon_sz := 52.0 * rs
	var header_h := maxf(icon_sz, 58.0 * rs)
	var gap := 8.0 * rs
	var section_h := 18.0 * rs
	_skill_detail_body.add_theme_font_size_override("normal_font_size", int(round(15.0 * rs)))
	_skill_detail_body.add_theme_constant_override("line_separation", int(round(5.0 * rs)))
	_skill_detail_body.size = Vector2(content_w, 8.0)
	_skill_detail_body.text = body_text
	var body_h := maxf(_skill_detail_body.get_content_height(), 26.0 * rs)
	# 附加效果徽章：宽卡两列、窄卡单列，全部塞进内容宽度内
	var fx: Array = fx_info.get("fx", [])
	var fx_h := _rebuild_fx_badges(fx, rs, content_w)
	var fx_block_h := 0.0
	if fx_h > 0.0:
		fx_block_h = gap + section_h + fx_h
	var hint_h := 17.0 * rs
	var panel_h := pad * 0.65 + header_h + gap + section_h + body_h + fx_block_h + gap + hint_h + pad * 0.45
	_skill_detail_panel.size = Vector2(panel_w, panel_h)
	# 子元素布局
	_skill_detail_accent.position = Vector2(pad, 1.0)
	_skill_detail_accent.size = Vector2(panel_w - pad * 2.0, 3.0)
	_skill_detail_icon.position = Vector2(pad, pad * 0.65)
	_skill_detail_icon.size = Vector2(icon_sz, icon_sz)
	var text_x := pad + icon_sz + 11.0 * rs
	var text_w := panel_w - text_x - pad
	_skill_detail_title.position = Vector2(text_x, pad * 0.65)
	_skill_detail_title.size = Vector2(text_w, 28.0 * rs)
	_skill_detail_tag.position = Vector2(text_x, pad * 0.65 + 28.0 * rs)
	_skill_detail_tag.size = Vector2(text_w, 18.0 * rs)
	var header_y := pad * 0.65 + header_h
	_skill_detail_divider.position = Vector2(pad, header_y + gap * 0.5)
	_skill_detail_divider.size = Vector2(content_w, 1.0)
	_skill_detail_section.position = Vector2(pad, header_y + gap)
	_skill_detail_section.size = Vector2(content_w, section_h)
	var body_y := header_y + gap + section_h
	_skill_detail_body.position = Vector2(pad, body_y)
	_skill_detail_body.size = Vector2(content_w, body_h)
	if fx_h > 0.0:
		var fx_y := body_y + body_h + gap
		_skill_detail_fx_title.position = Vector2(pad, fx_y)
		_skill_detail_fx_title.size = Vector2(content_w, section_h)
		_fx_holder.position = Vector2(pad, fx_y + section_h)
		_fx_holder.size = Vector2(content_w, fx_h)
	_fx_holder.visible = fx_h > 0.0
	_skill_detail_fx_title.visible = fx_h > 0.0
	_skill_detail_hint.position = Vector2(pad, panel_h - hint_h - pad * 0.45)
	_skill_detail_hint.size = Vector2(content_w, hint_h)
	# 优先放按钮正上方；纵向空间不足再退到左侧，最后夹回屏幕
	var rect := btn.get_global_rect()
	var px := rect.position.x + rect.size.x * 0.5 - panel_w * 0.5
	var py := rect.position.y - panel_h - 18.0 * rs
	if py < 10.0:
		px = rect.position.x - panel_w - 20.0 * rs
		py = rect.position.y + rect.size.y * 0.5 - panel_h * 0.5
	px = clampf(px, 10.0, maxf(10.0, vp.x - panel_w - 10.0))
	py = clampf(py, 10.0, maxf(10.0, vp.y - panel_h - 10.0))
	_skill_detail_panel.position = Vector2(px, py)
	_skill_detail_panel.visible = true

# 详情卡右上角“槽位 · 等级”标签（召唤师技能无等级成长）
func _detail_slot_tag(which: int) -> String:
	if which == 3:
		return "召唤师技能"
	var names := ["一技能", "二技能", "大招"]
	var tag: String = names[which] if which >= 0 and which < names.size() else "技能"
	if hero and which < hero.skill_levels.size():
		var lv: int = hero.skill_levels[which]
		var max_lv := 0
		if which < _skill_buttons.size():
			max_lv = _skill_buttons[which].max_level
		if lv <= 0:
			return tag + " · 未学习"
		if max_lv > 0:
			return tag + " · Lv.%d/%d" % [lv, max_lv]
		return tag + " · Lv.%d" % lv
	return tag

# 重建“附加效果”徽章区；返回该区高度（无效果返回 0）。badge 手动排布，超出宽度自动换行。
func _rebuild_fx_badges(fx: Array, rs: float, content_w: float) -> float:
	if _fx_holder == null or fx.is_empty():
		return 0.0
	for c in _fx_holder.get_children():
		c.visible = false
		c.queue_free()
	var bw := minf(104.0 * rs, content_w)
	var bh := 52.0 * rs
	var gap := 8.0 * rs
	var per_row := maxi(1, int(floor((content_w + gap) / (bw + gap))))
	var n := fx.size()
	var rows := int(ceil(float(n) / float(per_row)))
	var k := 0
	for item in fx:
		if not item is Dictionary:
			continue
		var data: Dictionary = _fx_badge_data(item, rs)
		var b := _FxBadge.new()
		b.setup(String(data.get("ic", "效")), data.get("col", Color.WHITE),
			String(data.get("sub", "")), float(data.get("rs", rs)))
		var row := int(k / per_row)
		var col := k % per_row
		b.position = Vector2(float(col) * (bw + gap), float(row) * (bh + gap))
		b.size = Vector2(bw, bh)
		b.queue_redraw()
		_fx_holder.add_child(b)
		k += 1
	return rows * (bh + gap) - gap if n > 0 else 0.0

# 把 fx 条目格式化为“汉字图标 + 颜色 + 副文案（数字/百分比·秒）”
func _fx_badge_data(item: Dictionary, rs: float) -> Dictionary:
	var t := str(item.get("t", ""))
	var meta: Dictionary = FX_META.get(t, {})
	var ic := "效"
	var col := Color(0.78, 0.8, 0.9)
	var sub := ""
	if meta.is_empty():
		return {"ic": ic, "col": col, "sub": sub, "rs": rs}
	ic = str(meta.get("ic", "效"))
	col = meta.get("c", Color.WHITE)
	var v := float(item.get("v", 0.0))
	var d := float(item.get("d", 0.0))
	if meta.has("sec"):
		sub = "%.1f秒" % v
	elif meta.has("durs"):
		sub = "+%d·%.1f秒" % [int(roundf(v)), d]
	elif meta.has("num"):
		sub = "-%d·%.1f秒" % [int(roundf(v)), d]
	elif meta.has("two"):
		sub = "%d%%·%.1f秒" % [int(roundf(v)), d]
	elif meta.has("flag"):
		sub = ""   # 纯图标类：无数值/时长
	else:
		sub = "%d" % int(roundf(v))
	return {"ic": ic, "col": col, "sub": sub, "rs": rs}

# 把 fx 效果条目压成技能键上的一行小字：{k:类型, col:配色, txt:数值+时长}。
# 格式：slow/selfspeed 显示“v% 时长S”，stun/knockup/freeze/suppress/bt 显示“时长S”，shield/heal 显示数值；
# 配色：作用于敌人的负面 → 蓝，作用于自身/友军的增益 → 绿。无法识别的类型直接跳过。
func _encode_button_fx(fx: Array) -> Array:
	var out: Array = []
	for item in fx:
		if not item is Dictionary:
			continue
		var t := str(item.get("t", ""))
		var meta: Dictionary = FX_META.get(t, {})
		if meta.is_empty():
			continue
		var v := float(item.get("v", 0.0))
		var d := float(item.get("d", 0.0))
		var txt := ""
		if meta.has("flag"):
			txt = ""   # 纯图标类（净化等）：无数值/时长，按钮只画矢量图标
		elif meta.has("sec"):
			txt = _fmt_fx_num(v) + "S"
		elif meta.has("durs"):
			txt = "+" + str(int(roundf(v)))   # 属性增益数值类（双抗/护甲/魔抗提升）：整数值+时长
			if d > 0.001:
				txt += " " + _fmt_fx_num(d) + "S"
		elif meta.has("num"):
			txt = "-" + str(int(roundf(v)))   # 属性削减数值类（魔抗削减等对敌减益）：负号+整数值+时长，与百分比(%)类区分
			if d > 0.001:
				txt += " " + _fmt_fx_num(d) + "S"
		elif meta.has("two"):
			txt = _fmt_fx_num(v) + "%"
			if d > 0.001:
				txt += " " + _fmt_fx_num(d) + "S"
		else:
			txt = str(int(roundf(v)))   # 护盾/回血等数值类：显示整数值
		if txt == "" and not meta.has("flag"):
			continue
		var col := FX_DEBUFF_COL if FX_HOSTILE_TYPES.has(t) else FX_BUFF_COL
		out.append({"k": t, "col": col, "txt": txt})
	return out

# 数值去尾零（整显示为整数，0.75/2.5 等保留小数），用于技能键小字
func _fmt_fx_num(x: float) -> String:
	var xr := roundf(x * 100.0) / 100.0
	return str(xr)

func _reset_skill_hold_timers() -> void:
	for i in range(_hold_start.size()):
		_hold_start[i] = -1.0


func _hide_skill_detail():
	if _skill_detail_panel:
		_skill_detail_panel.visible = false
	_detail_index = -1

func _append_detail_row(buf: String, key: String, val: String) -> String:
	return buf + "[color=#7f8da2]" + key + "[/color]    [color=#e8eff8]" + val + "[/color]\n"

# 详情面板“伤害”行的单段伤害文字：数值 + 可选“×N弹数” + 物/法色标（物=橙、法=紫，与图标一致）
func _skill_dmg_part(dmg: int, cnt_suffix: String, is_magic: bool) -> String:
	var col := "#c98aff" if is_magic else "#ff9a54"
	return str(dmg) + cnt_suffix + "　[color=" + col + "]" + ("法" if is_magic else "物") + "[/color]"

func _fmt_unit(x: float) -> String:
	if absf(x - roundf(x)) < 0.05:
		return "%d" % int(roundf(x))
	return "%.1f" % x

# 汇总该技能（/召唤师技能）的全部可用数值信息，返回 bbcode 多行文本（每行一条）
func _build_skill_detail_body(which: int) -> String:
	var skill: Skill = null
	var tag := ""
	var lvl := 0
	var max_lv := 0
	if which == 3:
		tag = "召唤师技能"
		if hero:
			skill = hero.summoner_skill
	else:
		var slot_names := ["一技能", "二技能", "大招"]
		if which >= 0 and which < slot_names.size():
			tag = slot_names[which]
		if hero and which < hero.skills.size():
			skill = hero.skills[which]
		if hero and which < hero.skill_levels.size():
			lvl = hero.skill_levels[which]
		if which >= 0 and which < _skill_buttons.size():
			max_lv = _skill_buttons[which].max_level
	if skill == null or skill.skill_name == "":
		return ""
	# 召唤师技能无等级成长；英雄技能显示 槽位 · 当前等级
	var loc := tag
	if which != 3:
		var lvl_txt := "未学习" if lvl <= 0 else "Lv.%d" % lvl
		if max_lv > 0 and lvl > 0:
			lvl_txt = "Lv.%d / %d" % [lvl, max_lv]
		loc = tag + " · " + lvl_txt
	var lines := ""
	lines = _append_detail_row(lines, "定位", loc)
	lines = _append_detail_row(lines, "类型", SKILL_TYPE_NAMES.get(skill.type, "其他")
		+ ("（引导技能）" if skill.is_channeling else ""))
	# 英雄技能：伤害行紧跟类型之后（数值=每段/主段，随等级与出装实时；物/法用颜色区分与图标一致）
	var info := {}
	var cnt := 0
	var unit := ""
	if which < 3 and hero:
		info = SkillDatabase.get_skill_fx(hero, which)
		cnt = int(info.get("count", 0))
		unit = String(info.get("unit", ""))
		var dm: Dictionary = SkillDatabase.get_skill_icon_damage(hero, which)
		if dm.get("valid", false) and int(dm.get("dmg", 0)) > 0:
			var cnt_suffix := (" ×%d%s" % [cnt, unit]) if cnt > 1 else ""
			# 伤害值可能拆成两段（主段 dmg + 附段 dmg2，如狄仁杰每段同时命中物理与法术）。
			# 两段拼在同一行：主段“数值[×N] + 物/法”色标在前，附段为正数时全角空格隔开
			# 排在其后（同样着色 + ×N 弹数），与图标读数的“物理旁法术”保持一致
			var dmg_parts: Array = []
			var main_dmg := int(dm.get("dmg", 0))
			var main_magic := bool(dm.get("magic", false))
			dmg_parts.append(_skill_dmg_part(main_dmg, cnt_suffix, main_magic))
			var extra_dmg := int(dm.get("dmg2", 0))
			if extra_dmg > 0:
				var extra_magic := bool(dm.get("magic2", false))
				dmg_parts.append(_skill_dmg_part(extra_dmg, cnt_suffix, extra_magic))
			lines = _append_detail_row(lines, "伤害", "　".join(dmg_parts))
		# 冷却/距离等基础数值（Skill 资源里未填写的字段自然不出现）
		if skill.cooldown > 0.001:
			var cur_cd := maxf(skill.cooldown - skill.cd_bonus * maxf(float(lvl) - 1.0, 0.0), 0.0)
			if skill.cd_bonus > 0.001 and lvl > 1:
				lines = _append_detail_row(lines, "冷却", "当前 %.1f 秒（基础 %.1f，每级 -%.1f）" % [cur_cd, skill.cooldown, skill.cd_bonus])
			else:
				lines = _append_detail_row(lines, "冷却", "%.1f 秒" % skill.cooldown)
		if skill.mana_cost > 0:
			var m_cost := maxi(int(skill.mana_cost - skill.power_bonus * maxf(float(lvl) - 1.0, 0.0)), 0)
			if skill.power_bonus > 0.001 and lvl > 1:
				lines = _append_detail_row(lines, "法力消耗", "%d 点（基础 %d）" % [m_cost, skill.mana_cost])
			else:
				lines = _append_detail_row(lines, "法力消耗", "%d 点" % m_cost)
		else:
			lines = _append_detail_row(lines, "消耗", "无消耗")
		if skill.cast_range > 0.001:
			lines = _append_detail_row(lines, "施法距离", _fmt_unit(skill.cast_range))
		if skill.radius > 0.001:
			lines = _append_detail_row(lines, "作用范围", "半径 " + _fmt_unit(skill.radius))
		if skill.duration > 0.001:
			lines = _append_detail_row(lines, "持续时间", "%.1f 秒" % skill.duration)
		if skill.self_displacement > 0.001:
			lines = _append_detail_row(lines, "位移距离", _fmt_unit(skill.self_displacement))
		if skill.bullet_range > 0.001:
			lines = _append_detail_row(lines, "飞行距离", _fmt_unit(skill.bullet_range))
		# 补充说明行（图标区表达不了的机制细节），与主数值行隔开一行
		var details: Array = info.get("texts", [])
		if not details.is_empty():
			lines += "\n"
			for dt in details:
				lines += "[color=#8f97a3]" + String(dt) + "[/color]\n"
	else:
		# 召唤师技能：保留全部基础字段 + 一句话效果说明（无等级成长）
		if skill.cooldown > 0.001:
			lines = _append_detail_row(lines, "冷却", "%.1f 秒" % skill.cooldown)
		if skill.cast_range > 0.001:
			lines = _append_detail_row(lines, "施法距离", _fmt_unit(skill.cast_range))
		if skill.radius > 0.001:
			lines = _append_detail_row(lines, "作用范围", "半径 " + _fmt_unit(skill.radius))
		if skill.shield_amount > 0.001:
			lines = _append_detail_row(lines, "护盾", "%d 点" % int(roundf(skill.shield_amount)))
		if skill.applies_slow > 0.001:
			lines = _append_detail_row(lines, "减速", "%d%%，持续 %.1f 秒" % [int(roundf(skill.applies_slow * 100.0)), skill.slow_duration])
		if skill.applies_stun > 0.001:
			lines = _append_detail_row(lines, "眩晕", "%.1f 秒" % skill.applies_stun)
		if skill.applies_knockup > 0.001:
			lines = _append_detail_row(lines, "击飞", "%.1f 秒" % skill.applies_knockup)
		if hero and hero.summoner_skill and SUMMONER_DESCRIPTIONS.has(hero.summoner_skill.skill_name):
			lines = _append_detail_row(lines, "效果", SUMMONER_DESCRIPTIONS[hero.summoner_skill.skill_name])
	return lines

# ---------------- 公开读取接口（Hero / BattleManager 每帧调用） ----------------

func get_move_vector() -> Vector2:
	if _joystick and touch_active:
		return _joystick.move_vector
	return Vector2.ZERO

func get_attack_held() -> bool:
	if _attack_button and touch_active:
		return _attack_button.is_held()
	return false

func get_attack_drag() -> Vector2:
	if _attack_button and touch_active:
		return _attack_button.get_drag()
	return Vector2.ZERO

# 消费普攻轮盘的松手选敌信息（王者荣耀式：拖动精准选敌、松手锁定）。
# 返回 {drag: Vector2, cancel: bool}；无松开事件时返回空字典。
func consume_attack_release() -> Dictionary:
	var v: Dictionary = _attack_release_pending
	_attack_release_pending = {}
	return v

func get_skill_held(i: int) -> bool:
	if _joystick and i >= 0 and i < _skill_buttons.size() and touch_active:
		return _skill_buttons[i].is_held()
	return false

func get_skill_drag(i: int) -> Vector2:
	if i >= 0 and i < _skill_buttons.size() and touch_active:
		return _skill_buttons[i].get_drag()
	return Vector2.ZERO

func consume_skill_press(i: int) -> bool:
	if i < 0 or i >= _skill_press_pending.size():
		return false
	var v: bool = _skill_press_pending[i]
	_skill_press_pending[i] = false
	return v

# 消费技能按钮的松开信息（王者荣耀式：按住瞄准、松手施放、拖回按钮取消）。
# 返回 {drag: Vector2, cancel: bool}；无松开事件时返回空字典。
func consume_skill_release(i: int) -> Dictionary:
	if i < 0 or i >= _skill_release_pending.size():
		return {}
	var v: Dictionary = _skill_release_pending[i]
	_skill_release_pending[i] = {}
	return v

func consume_recover_press() -> bool:
	var v: bool = _recover_press_pending
	_recover_press_pending = false
	return v

func consume_recall_press() -> bool:
	var v: bool = _recall_press_pending
	_recall_press_pending = false
	return v

# 推塔/小兵：普攻目标优先级（Hero 读取，决定玩家普攻自动选敌的类别）
func get_attack_priority() -> int:
	return _attack_priority

func set_attack_priority(p: int):
	_attack_priority = p if (p == ATTACK_PRIORITY_TOWER or p == ATTACK_PRIORITY_MINION) else ATTACK_PRIORITY_AUTO
	_sync_priority_buttons()

# 消费优先级按键（Hero 每帧调用）：返回按下的模式（TOWER/MINION），无按键返回 -1
func consume_priority_press() -> int:
	var v: int = _priority_press_pending
	_priority_press_pending = -1
	return v

func _sync_priority_buttons():
	if _tower_button:
		_tower_button.toggled = _attack_priority == ATTACK_PRIORITY_TOWER
		_tower_button.queue_redraw()
	if _minion_button:
		_minion_button.toggled = _attack_priority == ATTACK_PRIORITY_MINION
		_minion_button.queue_redraw()

# ---------------- 桌面移动模式（转向 / 前后左右） ----------------
func get_move_mode() -> int:
	return move_mode

func set_move_mode(m: int):
	move_mode = MOVE_MODE_DIR if m == MOVE_MODE_DIR else MOVE_MODE_TURN
	if _move_mode_btn:
		_move_mode_btn.set_mode(move_mode)

func _on_move_mode_changed(m: int):
	move_mode = m

# ---------------- 召唤师技能（按住瞄准、松开施放） ----------------
func get_summoner_held() -> bool:
	if _summoner_button and touch_active:
		return _summoner_button.is_held()
	return false

func get_summoner_drag() -> Vector2:
	if _summoner_button and touch_active:
		return _summoner_button.get_drag()
	return Vector2.ZERO

# 消费召唤师按钮松开信息（{drag, cancel}；空字典=无松开事件）
func consume_summoner_release() -> Dictionary:
	var v: Dictionary = _summoner_release_pending
	_summoner_release_pending = {}
	return v

# ---------------- 构建触摸 UI ----------------

func _build_ui():
	touch_layer = CanvasLayer.new()
	touch_layer.layer = UiKit.LAYER_TOUCH
	touch_layer.name = "TouchControls"
	add_child(touch_layer)

	# ---- 游戏操作区（摇杆 + 技能 + 普攻等）----
	_gameplay_root = Control.new()
	_gameplay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameplay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_layer.add_child(_gameplay_root)

	# 固定摇杆：底座中心钉在屏幕左下 (距左 330, 距底 300)。
	# 控件做成「边长 = 2×激活半径」的方形并锚定到屏幕，JoystickPad 中心即底座中心；
	# 按下点须落在此中心半径 ACTIVATE_RADIUS 内才会启动摇杆（激活圆以外不抢占输入）。
	var joy = preload("res://scripts/mobile/VirtualJoystick.gd").new()
	var joy_home := Vector2(330, 300)
	joy.set_meta("layout_key", "joystick")
	# 边长 = 2×激活半径 = 600。写成字面量（与 JoystickPad.ACTIVATE_RADIUS=300 保持同步），
	# 不跨文件调用任何新常量/新方法——编辑器对 class_name 脚本的类缓存可能滞后，跨文件引用
	# 会先后触发 "Cannot find member" 分析期错误与 "Nonexistent function" 运行期错误
	var joy_side := 600.0
	# 手机横屏挖孔/圆角/手势条避让：摇杆整体内收，避免底座被屏幕边缘裁切
	var sl := UiKit.safe_left()
	var sb := UiKit.safe_bottom()
	joy.anchor_left = 0.0
	joy.anchor_top = 1.0
	joy.anchor_right = 0.0
	joy.anchor_bottom = 1.0
	joy.offset_left = sl + joy_home.x - joy_side * 0.5
	joy.offset_top = -(sb + joy_home.y + joy_side * 0.5)
	joy.offset_right = sl + joy_home.x + joy_side * 0.5
	joy.offset_bottom = -(sb + joy_home.y - joy_side * 0.5)
	_register_layout(joy)
	_gameplay_root.add_child(joy)
	_joystick = joy

	# 桌面 WASD 移动模式切换（电脑端专属，手机端隐藏）——置于摇杆激活圆右上方的空区
	var mm := MoveModeToggle.new()
	mm.set_mode(move_mode)
	mm.mode_changed.connect(_on_move_mode_changed)
	_anchor_br(mm, Vector2(1600, 150), Vector2(330, 46), Vector2.ZERO)  # 桌面 WASD 切换键在摇杆上方空区，不属于右下角簇
	_gameplay_root.add_child(mm)
	_move_mode_btn = mm

	# 普攻轮盘：最大号，右下角（按住普攻、拖动精准选敌），是技能扇形唯一的圆心
	var atk := AttackWheelButton.new()
	atk.label_text = "普攻"
	atk.color = Color(0.9, 0.4, 0.3, 0.85)
	atk.set_meta("layout_key", "attack")
	_anchor_br(atk, ATTACK_POS, Vector2(ATTACK_SIZE, ATTACK_SIZE))
	atk.pressed_changed.connect(_on_attack_pressed_changed)
	atk.released.connect(_on_attack_released)
	_gameplay_root.add_child(atk)
	_attack_button = atk

	# 推塔/小兵键（王者荣耀式进阶攻击的普攻目标优先级切换）。
	# 摆放：普攻键占屏 x2010-2360 / y1010-1360，大招在其上方 x2055-2315 / y495-755，
	# 两键置于二者之间的空隙带 x2020-2360 / y840-1005 —— 推塔在普攻正上方、小兵在其左侧。
	# 点按切换模式（Hero 侧处理：再按同一键取消，见 _handle_attack_priority_input）。
	var tower_btn := TouchActionButton.new()
	tower_btn.label_text = ""
	tower_btn.name_text = "推塔"
	tower_btn.icon_kind = "tower"
	tower_btn.color = Color(0.16, 0.18, 0.24, 0.94)
	tower_btn.hold_to_act = false
	tower_btn.emit_activated_on_press = true
	tower_btn.activated.connect(func(): _priority_press_pending = ATTACK_PRIORITY_TOWER)
	tower_btn.set_meta("layout_key", "tower")
	_anchor_br(tower_btn, Vector2(40, 395), Vector2(165, 165))
	_gameplay_root.add_child(tower_btn)
	_tower_button = tower_btn

	var minion_btn := TouchActionButton.new()
	minion_btn.label_text = ""
	minion_btn.name_text = "小兵"
	minion_btn.icon_kind = "minion"
	minion_btn.color = Color(0.16, 0.18, 0.24, 0.94)
	minion_btn.hold_to_act = false
	minion_btn.emit_activated_on_press = true
	minion_btn.activated.connect(func(): _priority_press_pending = ATTACK_PRIORITY_MINION)
	minion_btn.set_meta("layout_key", "minion")
	_anchor_br(minion_btn, Vector2(215, 395), Vector2(165, 165))
	_gameplay_root.add_child(minion_btn)
	_minion_button = minion_btn
	_sync_priority_buttons()
	if not PlayerPrefs.opt_bool("siege_keys", true):
		_tower_button.visible = false
		_minion_button.visible = false

	# 技能扇形：1/2/3 技能在同一圆弧上「环绕」普攻键 —— 圆弧圆心 = 普攻中心，
	# 各键中心到圆心的距离恒为 FAN_RADIUS；角度取 SKILL_FAN_ANGLES_DEG。
	var skill_colors := [Color(0.3, 0.7, 1.0), Color(0.35, 0.9, 0.45), Color(1.0, 0.7, 0.25)]
	var atk_center := ATTACK_POS + Vector2(ATTACK_SIZE, ATTACK_SIZE) * 0.5
	for i in range(SKILL_COUNT):
		var ang := deg_to_rad(SKILL_FAN_ANGLES_DEG[i])
		var fb := atk_center + Vector2(FAN_RADIUS * sin(ang), FAN_RADIUS * cos(ang))
		fb -= Vector2(SKILL_SIZE, SKILL_SIZE) * 0.5
		var b := SkillTouchButton.new()
		b.skill_index = i
		b.color = skill_colors[i]
		b.name_below = true   # 技能名画在按钮下方，中央不显示 1/2/3
		b.set_meta("layout_key", "skill_%d" % (i + 1))
		_anchor_br(b, fb, Vector2(SKILL_SIZE, SKILL_SIZE))
		b.pressed_changed.connect(_on_skill_pressed_changed)
		b.released.connect(_on_skill_released)
		_gameplay_root.add_child(b)
		_skill_buttons.append(b)
		# 技能升级“+”按钮：位于技能上沿中央、水平不越出自身宽度，避免挤占相邻技能
		var upg := TouchActionButton.new()
		upg.label_text = "+"
		upg.label_font_size = 0.0
		upg.compact_badge = true
		upg.color = Color(0.98, 0.84, 0.25, 0.95)
		upg.hold_to_act = false
		upg.emit_activated_on_press = true
		upg.activated.connect(_on_upgrade_pressed.bind(i))
		var upg_fb := fb + Vector2((SKILL_SIZE - UPGRADE_SIZE) * 0.5, SKILL_SIZE)
		_anchor_br(upg, upg_fb, Vector2(UPGRADE_SIZE, UPGRADE_SIZE))
		_gameplay_root.add_child(upg)
		_upgrade_buttons.append(upg)

	# 第4技能按钮：拥有真实第4技能槽的英雄(兰陵王·隐身)才显示；其余英雄 skills[3]=null 占位隐藏。
	# 位置：1技能(θ70°)左侧同高的空档(回城键上方)；点按松开即施放、无瞄准方向。
	var ex_btn := SkillTouchButton.new()
	ex_btn.skill_index = 3
	ex_btn.color = Color(0.72, 0.45, 1.0, 0.85)
	ex_btn.name_below = true
	var ex_center := Vector2(1050, 406)
	ex_btn.set_meta("layout_key", "skill_4")
	_anchor_br(ex_btn, ex_center - Vector2(SKILL_SIZE, SKILL_SIZE) * 0.5, Vector2(SKILL_SIZE, SKILL_SIZE))
	ex_btn.pressed_changed.connect(_on_skill_pressed_changed)
	ex_btn.released.connect(_on_skill_released)
	ex_btn.visible = false
	_gameplay_root.add_child(ex_btn)
	_extra_skill_button = ex_btn

	# 敌人索敌头像条：攻击范围内有敌方英雄时，沿技能扇形外侧同圆心弧线排布，点按锁定目标
	_picker_root = Control.new()
	_picker_root.name = "EnemyPicker"
	_picker_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 头像子控件自身可点；漏分发时 _input 里的矩形命中兜底会接住。
	_picker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_root.visible = false
	_gameplay_root.add_child(_picker_root)
	for _i in range(PICKER_MAX):
		var av := _EnemyAvatar.new()
		av.visible = false
		av.tapped.connect(_on_enemy_picker_tapped)
		_anchor_br(av, Vector2.ZERO, Vector2(PICKER_SIZE, PICKER_SIZE))
		_picker_root.add_child(av)
		_picker_buttons.append(av)

	# 召唤师 / 恢复 / 回城：贴底同一横带（屏幕从左到右：回城 | 恢复 | 召唤师）
	# 召唤师：按住瞄准（拖动=闪现等位移类技能的方向）、松开施放（王者荣耀式）
	var sum := SkillTouchButton.new()
	sum.skill_index = -1
	sum.display_name = "召唤"
	sum.color = Color(0.7, 0.35, 1.0, 0.85)
	sum.pressed_changed.connect(_on_summoner_pressed_changed)
	sum.released.connect(_on_summoner_released)
	sum.set_meta("layout_key", "summoner")
	_anchor_br(sum, Vector2(420, ROW_FROM_BOTTOM), Vector2(220, 220))
	_gameplay_root.add_child(sum)
	_summoner_button = sum

	# 恢复 —— 召唤师技能左方：点按即时回血（不拖方向）。此前名字误为“血”且无冷却显示；
	# 改为 SkillTouchButton：中央显示“恢复”，并读取 Hero 第 4 号技能槽(恢复)画出 60s 冷却遮罩。
	var recv := SkillTouchButton.new()
	recv.skill_index = 4
	recv.display_name = "恢复"
	recv.name_below = true
	recv.icon_kind = "recover"
	recv.color = Color(0.22, 0.38, 0.26, 0.94)
	recv.pressed_changed.connect(func(_idx: int, pressed: bool):
		if pressed:
			_recover_press_pending = true)
	recv.set_meta("layout_key", "recover")
	_anchor_br(recv, Vector2(660, ROW_FROM_BOTTOM), Vector2(220, 220))
	_gameplay_root.add_child(recv)
	_recover_button = recv

	# 回城 —— 恢复左方
	var rec := TouchActionButton.new()
	rec.label_text = ""
	rec.name_text = "回城"
	rec.icon_kind = "recall"
	rec.color = Color(0.20, 0.28, 0.42, 0.94)
	rec.hold_to_act = false
	rec.emit_activated_on_press = true
	rec.activated.connect(func(): _recall_press_pending = true)
	rec.set_meta("layout_key", "recall")
	_anchor_br(rec, Vector2(900, ROW_FROM_BOTTOM), Vector2(220, 220))
	_gameplay_root.add_child(rec)

	# 主动装备 x2（放大后的大招上方；仅拥有对应主动装时显示）。
	# 与技能键同款圆形按钮：程序化装备图标 + 名称条 + 冷却遮罩（不再是“装1/装2”纯文字）
	var equip_pos := [Vector2(120, 1055), Vector2(370, 1055)]
	for i in range(2):
		var ab := SkillTouchButton.new()
		ab.skill_index = -1
		ab.name_below = true
		ab.color = Color(0.9, 0.75, 0.2, 0.85)
		var slot_i := i
		ab.pressed_changed.connect(func(_idx: int, pressed: bool):
			if pressed:
				_on_active_pressed(slot_i))
		ab.set_meta("layout_key", "equip_%d" % (i + 1))
		_anchor_br(ab, equip_pos[i], Vector2(ACTIVE_SIZE, ACTIVE_SIZE))
		_gameplay_root.add_child(ab)
		_active_equip_buttons.append(ab)

	# 取消施法按钮：拖动技能瞄准时显示在扇形右上方的空隙；松手落在其上 → 取消施放。
	# 原位置(20,740)被放大后的大招键覆盖；现放在放大扇形左上方、主动装键左侧的空隙
	# （screen 约 x1400..1700, y340..640），避开 buff 面板与升级键。
	var cancel := CancelCastButton.new()
	cancel.name = "CancelCast"
	_anchor_br(cancel, Vector2(700, 760), Vector2(300, 300))
	_gameplay_root.add_child(cancel)
	_cancel_btn = cancel

	# 技能详情面板：按住技能按钮超 2 秒时在按钮左侧弹出（内容见 _build_skill_detail_body）
	_create_skill_detail_panel()

func _on_skill_pressed_changed(index: int, pressed: bool):
	# 每次手势从按下这一刻重新计时，不能沿用上一次长按留下的 _hold_start
	if index >= 0 and index < _hold_start.size():
		_hold_start[index] = -1.0
	if pressed:
		_skill_press_pending[index] = true
		_skill_release_pending[index] = {}  # 新手势：清除上一回的松开信息

# 技能按钮松开（王者荣耀式）：记录最终拖拽与取消标记，供 Hero 释放时消费。
# 取消判定：① 拖出去又拖回按钮（cancelled） ② 松手落在取消施法按钮上。
func _on_skill_released(index: int, final_drag: Vector2, cancelled: bool, release_global: Vector2):
	if index >= 0 and index < _skill_release_pending.size():
		var cancel := cancelled
		# 看过技能详情后松手依然施放（详情面板只在查看期间常驻，不影响施放）
		if not cancel and _cancel_btn and _cancel_btn.visible \
				and _cancel_btn.get_global_rect().has_point(release_global):
			cancel = true
		_skill_release_pending[index] = {"drag": final_drag, "cancel": cancel}

# 召唤师按钮按下：清除上一回的松手施放信息（新手势从零开始）
func _on_summoner_pressed_changed(_index: int, pressed: bool):
	_hold_start[3] = -1.0
	if pressed:
		_summoner_release_pending = {}

# 召唤师按钮松开（王者荣耀式）：拖拽方向=位移类技能（如闪现）的施放方向
func _on_summoner_released(_index: int, final_drag: Vector2, cancelled: bool, release_global: Vector2):
	var cancel := cancelled
	if not cancel and _cancel_btn and _cancel_btn.visible \
			and _cancel_btn.get_global_rect().has_point(release_global):
		cancel = true
	_summoner_release_pending = {"drag": final_drag, "cancel": cancel}

# 普攻轮盘按下：清除上一回的松手选敌信息（新手势从零开始）
func _on_attack_pressed_changed(pressed: bool):
	if pressed:
		_attack_release_pending = {}

# 普攻轮盘松开（王者荣耀式）：记录最终拖拽与「拖回取消」标记，供 Hero 精准选敌
func _on_attack_released(final_drag: Vector2, cancelled: bool):
	_attack_release_pending = {"drag": final_drag, "cancel": cancelled}

# 对应技能的升级按钮：直接升级该技能（仅可升级时可见）
func _on_upgrade_pressed(i: int):
	if hero and is_instance_valid(hero) and i < hero.skill_levels.size():
		hero.upgrade_skill(i)

func _on_active_pressed(index: int):
	if hero and is_instance_valid(hero):
		_ui_mgr._trigger_active_equip(hero, index)

func _update_skill_button_ui():
	var pts: int = hero.skill_points if hero else 0
	# 第4技能（真实第4槽英雄，如兰陵王·隐匿）：与 1/2/3 技能走完全相同的图标/冷却/读数推送，
	# 只是固定 1 级（4 级自动解锁，无“+”升级钮），保证图标 UI 与其他技能一致。
	var has4: bool = hero.skills.size() > 3 and hero.skills[3] != null
	for i in range(SKILL_COUNT + (1 if has4 else 0)):
		var b: SkillTouchButton = _skill_buttons[i] if i < SKILL_COUNT else _extra_skill_button
		if b == null:
			continue
		# 等级金环数据：按技能最大等级分小段，亮段数=当前技能等级
		b.max_level = 1 if i >= 3 else (hero.SKILL_MAX_LEVEL if i < 2 else hero.ULTIMATE_MAX_LEVEL)
		b.skill_level = hero.skill_levels[i] if i < hero.skill_levels.size() else 0
		# 技能图标：英雄元素配色 + 技能纹样（SkillArt 程序化绘制）
		b.art_hero = str(hero.display_name)
		b.art_skill = hero.skills[i] if i < hero.skills.size() else null
		# 按钮下方显示实际技能名（不再在中央显示 1/2/3）
		if i < hero.skills.size() and hero.skills[i]:
			var sname := str(hero.skills[i].skill_name)
			if sname == "":
				sname = str(i + 1)
			if b.display_name != sname:
				b.display_name = sname
		if i < hero.skills.size() and hero.skills[i]:
			var skill: Skill = hero.skills[i]
			var mi: Dictionary = {}
			if i < hero.skill_window_timers.size():
				mi = hero.get_multicast_window(i)
			if not mi.is_empty():
				# 多段重施窗口：显示窗口剩余秒数 + 剩余段数（冷却比例改由窗口计时驱动）
				b.in_window = true
				b.win_left = float(mi.win_left)
				b.win_total = maxf(float(mi.win_total), 0.001)
				b.segments_left = maxi(0, int(mi.total) - int(mi.used))
				b.cd_ratio = 0.0
				b.cd_total = 0.0
			else:
				b.in_window = false
				b.segments_left = 0
				var cd: float = hero.skill_cooldowns[i] if i < hero.skill_cooldowns.size() else 0.0
				var lvl: int = hero.skill_levels[i] if i < hero.skill_levels.size() else 0
				var total: float = maxf(skill.cooldown - skill.cd_bonus * maxi(lvl - 1, 0), 0.001)
				b.cd_ratio = clampf(cd / total, 0.0, 1.0)
				b.cd_total = total
			b.mana_ok = hero.mana >= skill.mana_cost
		else:
			b.cd_ratio = 0.0
			b.mana_ok = true
			b.in_window = false
			b.segments_left = 0
		# 技能图标伤害预览：SkillDatabase 按当前技能等级/出装算出“主要命中段”伤害与类型（物理橙/法术紫）
		# 同时推送弹/段数与效果小字：多发技能伤害显示“伤害×N”；效果(减速/眩晕/护盾…)绘制成图标+数值/时长
		var dm: Dictionary = SkillDatabase.get_skill_icon_damage(hero, i)
		var fx_info: Dictionary = SkillDatabase.get_skill_fx(hero, i)
		if dm.get("valid", false):
			b.icon_dmg = int(dm.get("dmg", 0))
			b.icon_dmg_magic = bool(dm.get("magic", false))
			b.icon_dmg2 = int(dm.get("dmg2", 0))
			b.icon_dmg2_magic = bool(dm.get("magic2", false))
		else:
			b.icon_dmg = -1
			b.icon_dmg2 = 0
		b.icon_count = int(fx_info.get("count", 0))
		b.icon_fx = _encode_button_fx(fx_info.get("fx", []))
		# 附带强化普攻的技能（亚瑟Q/铠W/孙悟空技能…）：在按钮读数最前放一枚金色普攻小剑，
		# 让“这个技能给你一次强化普攻”一目了然，并与普攻键/攻击范围预览环的金色状态保持一致
		b.icon_aa = SkillDatabase.skill_grants_enhanced_aa(str(hero.display_name), i)
		# 存储型技能（restore>0，可存多层，如马超大招）：推送当前已存层数/上限；
		# 已学且前置不满足（马超 R 需身边 12 内有枪可召回）→ blocked=true，按钮置灰并提示“无枪”
		var charge_cap := 0
		var charge_cur := 0
		var block_flag := false
		if i < hero.skills.size() and hero.skills[i] and i < hero.skill_levels.size() and hero.skill_levels[i] > 0:
			if hero.skills[i].restore > 0.0:
				charge_cap = int(hero.skills[i].restore)
				charge_cur = hero.skill_restores[i] if i < hero.skill_restores.size() else 0
			# 前置状态门槛（李白大招侠客 / 沈梦溪1、2炸弹 / 马超R枪 / 东皇2能量 / 兰陵王大招隐身）：
			# 施放中该技能（如李白R穿梭期间侠客行被清零）不视为不可用，避免按钮闪斜杠
			if not (hero.casting_skill and hero.pending_skill_index == i):
				block_flag = hero.skill_prereq_blocked(i)
		b.charge_max = charge_cap
		b.charge_now = charge_cur
		b.blocked = block_flag
		b.block_cue = hero.skill_prereq_cue(i) if block_flag else ""
		# 该技能当前可升级？（与 Hero.upgrade_skill 的成功条件一致）
		var upgradeable: bool = hero.can_upgrade_skill(i)
		b.upgrade_ready = upgradeable
		b.queue_redraw()
		if i < _upgrade_buttons.size():
			var ub = _upgrade_buttons[i]
			ub.visible = upgradeable
			# 可升级时“+”外圈旋转发光拖尾（推动相位并在状态切换时重绘）
			if ub.glow != upgradeable:
				ub.glow = upgradeable
				ub.queue_redraw()
	# 召唤师按钮：显示具体召唤师技能名（如“闪现/惩击”），并做冷却显示（无等级不画金环）
	if _summoner_button:
		var sname := "召唤"
		if hero.summoner_skill:
			var real := str(hero.summoner_skill.skill_name)
			if real != "": sname = real
		if _summoner_button.display_name != sname:
			_summoner_button.display_name = sname
			# 名字居中画在圆内（name_below 会让名字条伸出按钮底部、并与惩击伤害数字重叠）
			_summoner_button.name_below = false
			_summoner_button.icon_kind = IconArt.kind_for_summoner(sname)
			_summoner_button.color = IconArt.color_of(_summoner_button.icon_kind)
		if hero.summoner_skill and hero.summoner_skill.cooldown > 0.001:
			var stot: float = hero.summoner_skill.cooldown
			_summoner_button.cd_ratio = clampf(hero.summoner_cooldown / stot, 0.0, 1.0)
			_summoner_button.cd_total = stot
		else:
			_summoner_button.cd_ratio = 0.0
		# 惩击按钮下方显示对野怪/史诗怪物的伤害值（随英雄等级成长）
		if sname == "惩击":
			_summoner_button.sub_text = "%d" % (1500 + hero.level * 100)
		else:
			_summoner_button.sub_text = ""
		_summoner_button.art_hero = ""
		_summoner_button.art_skill = hero.summoner_skill
		_summoner_button.queue_redraw()
	# 恢复按钮：读取 Hero 第 4 号技能槽(恢复，Hero.setup_skills_from_database 追加)，
	# 冷却总量=技能自身 cooldown(60s)，剩余=skill_cooldowns[4]，画暗色冷却遮罩 + 剩余秒数
	if _recover_button:
		var rtot: float = 60.0
		if hero.skills.size() > 4:
			var rec_skill: Skill = hero.skills[4]
			if rec_skill and rec_skill.cooldown > 0.001:
				rtot = rec_skill.cooldown
		var rcd: float = hero.skill_cooldowns[4] if hero.skill_cooldowns.size() > 4 else 0.0
		_recover_button.cd_ratio = clampf(rcd / rtot, 0.0, 1.0)
		_recover_button.cd_total = rtot
		_recover_button.art_hero = str(hero.display_name)
		_recover_button.art_skill = hero.skills[4] if hero.skills.size() > 4 else null
		_recover_button.queue_redraw()
	# 主动装备按钮：仅拥有对应主动装时显示；推送装备图标/品质/名称/冷却（与技能键同款视觉）
	var ae_list := _ui_mgr._get_active_equip_list(hero) if _ui_mgr else []
	for i in range(_active_equip_buttons.size()):
		var ab: SkillTouchButton = _active_equip_buttons[i]
		ab.visible = i < ae_list.size()
		if not ab.visible:
			continue
		var ae: Dictionary = ae_list[i]
		var inm := str(ae.get("name", ""))
		if inm == "":
			inm = "装%d" % (i + 1)
		if ab.display_name != inm:
			ab.display_name = inm
		ab.item_name = inm
		var it: Dictionary = ItemDatabase.get_item(str(ae.get("id", "")))
		ab.item_tier = int(it.get("tier", 1)) if not it.is_empty() else 1
		var mx := maxf(float(ae.get("max_cd", 60.0)), 0.001)
		ab.cd_total = mx
		ab.cd_ratio = clampf(float(ae.get("cd_remaining", 0.0)) / mx, 0.0, 1.0)
		ab.max_level = 0
		ab.queue_redraw()
	# 取消施法按钮：任一技能/召唤师按钮按住瞄准时显示；手指拖到其上时高亮
	var aiming := false
	var over_cancel := false
	if _cancel_btn:
		var aim_btns: Array = _skill_buttons.duplicate()
		if _extra_skill_button:

			aim_btns.append(_extra_skill_button)

		if _summoner_button:
			aim_btns.append(_summoner_button)
		for b in aim_btns:
			if b.is_held():
				aiming = true
				var tg: Vector2 = b.get_touch_global()
				if tg != Vector2.ZERO and _cancel_btn.get_global_rect().has_point(tg):
					over_cancel = true
				break
		_cancel_btn.visible = aiming
		_cancel_btn.set_highlighted(over_cancel)

func set_intro_hidden(hidden: bool) -> void:
	intro_hidden = hidden
	_update_visibility()

func _update_visibility():
	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var started := bm != null and bm.hero_selected
	var blocked := _is_fullscreen_open()
	_gameplay_root.visible = touch_active and started and not blocked and not intro_hidden
	touch_layer.visible = touch_active
	# 桌面键盘移动模式切换：仅电脑端显示（手机只有摇杆移动）
	if _move_mode_btn:
		_move_mode_btn.visible = _gameplay_root.visible and not Config.on_mobile()
	# 屏幕下方原技能图标栏全部隐藏（两端统一，以触摸层替代）；
	# 英雄头像（respawn 区）已移到小地图右侧横向排列，常显
	var ui := _ui_mgr
	if ui:
		for arr in [ui.skill_icons, ui.skill_name_labels, ui.skill_level_labels, ui.skill_info_labels]:
			for c in arr:
				if c is CanvasItem:
					c.visible = false
		if ui.skill_detail_label:
			ui.skill_detail_label.visible = false

	# 第4技能按钮可见性：仅真实拥有第4技能槽的英雄(兰陵王·隐身)时显示
	if _extra_skill_button:
		_extra_skill_button.visible = _gameplay_root.visible and hero != null and hero.skills.size() > 3 and hero.skills[3] != null
	if _tower_button:
		var _siege_on: bool = _gameplay_root.visible and PlayerPrefs.opt_bool("siege_keys", true)
		_tower_button.visible = _siege_on
		if _minion_button:
			_minion_button.visible = _siege_on

func _is_fullscreen_open() -> bool:
	var ui := _ui_mgr
	if ui.shop_ui and is_instance_valid(ui.shop_ui) and ui.shop_ui.visible:
		return true
	if ui.hero_detail_panel and is_instance_valid(ui.hero_detail_panel) and ui.hero_detail_panel.visible:
		return true
	if ui.team_decision_panel and is_instance_valid(ui.team_decision_panel) and ui.team_decision_panel.visible:
		return true
	return false

func _anchor_br(ctrl: Control, from_br: Vector2, size: Vector2, inset: Vector2 = TOUCH_CLUSTER_INSET):
	from_br += inset
	# 手机横屏：右侧挖孔/圆角与底部手势条避让；桌面 safe_* 恒为 0，布局不变
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
	_register_layout(ctrl)

func _anchor_tl(ctrl: Control, from_tl: Vector2, size: Vector2):
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = from_tl.x
	ctrl.offset_top = from_tl.y
	ctrl.offset_right = from_tl.x + size.x
	ctrl.offset_bottom = from_tl.y + size.y
	_register_layout(ctrl)

# ==================== 键位自定义布局（拖动调位置 / ＋－ 调大小） ====================
# 每个可自定义控件在创建时带 meta "layout_key"，_anchor_* 结束时登记默认位置；
# 进入编辑模式后可直接拖动按钮，保存到 PlayerPrefs.btn_layout，下次对局自动套用。
const LAYOUT_SCALE_MIN := 0.55
const LAYOUT_SCALE_MAX := 1.70
const LAYOUT_LABELS := {
	"joystick": "摇杆", "attack": "普攻", "tower": "推塔", "minion": "小兵",
	"skill_1": "1技能", "skill_2": "2技能", "skill_3": "3技能", "skill_4": "4技能",
	"summoner": "召唤师技能", "recover": "恢复", "recall": "回城",
	"equip_1": "主动装1", "equip_2": "主动装2",
}
var _layout_btns: Array = []
var _edit_root: Control = null
var _edit_sel: Control = null
var _edit_box: Panel = null
var _edit_hint: Label = null
var _edit_drag_last := Vector2.ZERO
var _edit_drag_moved := 0.0
var _edit_was_paused := false

## 登记默认可自定义按钮，并套用已保存的偏移/缩放
func _register_layout(ctrl: Control) -> void:
	var key: String = str(ctrl.get_meta("layout_key", ""))
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
	var s := clampf(float(entry.get("s", 1.0)), LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX)
	if dx != 0.0 or dy != 0.0:
		ctrl.offset_left += dx
		ctrl.offset_right += dx
		ctrl.offset_top += dy
		ctrl.offset_bottom += dy
	ctrl.pivot_offset = Vector2((ctrl.offset_right - ctrl.offset_left) * 0.5,
		(ctrl.offset_bottom - ctrl.offset_top) * 0.5)
	ctrl.scale = Vector2(s, s)

## 回到默认位置后再套用已保存布局（取消编辑 / 重置时用）
func apply_btn_layout() -> void:
	var lay: Dictionary = PlayerPrefs.get_btn_layout()
	for c in _layout_btns:
		if not is_instance_valid(c):
			continue
		var ctrl := c as Control
		var def = ctrl.get_meta("layout_def", [])
		if def is Array and def.size() == 4:
			ctrl.offset_left = float(def[0])
			ctrl.offset_top = float(def[1])
			ctrl.offset_right = float(def[2])
			ctrl.offset_bottom = float(def[3])
		_apply_layout_one(ctrl, lay.get(str(ctrl.get_meta("layout_key", "")), {}))

## 进入键位编辑：暂停对局，按钮保持可见并可直接拖动
func enter_layout_edit() -> void:
	if _edit_root != null and is_instance_valid(_edit_root):
		return
	if touch_layer == null:
		return
	_edit_was_paused = get_tree().paused
	get_tree().paused = true
	_gameplay_root.visible = true
	_edit_root = Control.new()
	_edit_root.name = "LayoutEdit"
	_edit_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edit_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_edit_root.process_mode = Node.PROCESS_MODE_ALWAYS
	touch_layer.add_child(_edit_root)
	_edit_box = Panel.new()
	_edit_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_box.visible = false
	_edit_box.add_theme_stylebox_override("panel", UiKit.flat(0.95, 8, 2,
		Color(1.0, 0.85, 0.32, 0.95), Color(0.06, 0.07, 0.10, 0.0), 0.0, 6))
	_edit_root.add_child(_edit_box)
	_build_layout_bar()
	_edit_root.gui_input.connect(_on_layout_edit_input)
	var first = null
	for c2 in _layout_btns:
		if str(c2.get_meta("layout_key", "")) == "skill_1":
			first = c2
			break
	if first == null and not _layout_btns.is_empty():
		first = _layout_btns[0]
	select_layout_button(first)

func _build_layout_bar() -> void:
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bar.offset_left = -430.0
	bar.offset_right = 430.0
	bar.offset_top = 10.0
	bar.offset_bottom = 118.0
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

func _layout_bar_btn(txt: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(150.0, 42.0)
	b.add_theme_font_override("font", UiKit.font())
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", UiKit.C_TEXT)
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", col, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", col, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", col, false))
	b.pressed.connect(cb)
	return b

## 选中按钮：金色描边框跟随（拖动/缩放都作用于当前选中项）
func select_layout_button(ctrl: Control) -> void:
	_edit_sel = ctrl
	if _edit_box == null or not is_instance_valid(_edit_box):
		return
	if ctrl == null or not is_instance_valid(ctrl):
		_edit_box.visible = false
		return
	var key := str(ctrl.get_meta("layout_key", ""))
	if _edit_hint != null and is_instance_valid(_edit_hint):
		_edit_hint.text = "已选中「%s」（%.0f%%）· 拖动调整位置 · ＋/－ 调大小" % [
			str(LAYOUT_LABELS.get(key, key)), ctrl.scale.x * 100.0]
	var p: Vector2 = ctrl.get_global_rect().position - _edit_root.get_global_rect().position
	var sz: Vector2 = ctrl.get_global_rect().size
	_edit_box.visible = true
	_edit_box.position = p - Vector2(4, 4)
	_edit_box.size = sz + Vector2(8, 8)

func _on_layout_edit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var pressed: bool = event.pressed
		var pos: Vector2 = event.position
		if pressed:
			var hit := _layout_hit(pos)
			_edit_drag_last = pos
			_edit_drag_moved = 0.0
			if hit != null:
				select_layout_button(hit)
		else:
			# 点空白处=取消选中；没拖动过的点按不改变布局
			if _edit_drag_moved <= 2.0 and _layout_hit(pos) == null:
				select_layout_button(null)
			_edit_drag_moved = 0.0
		return
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _edit_sel == null or not is_instance_valid(_edit_sel):
			return
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		var d: Vector2 = event.position - _edit_drag_last
		if d.length() < 0.01:
			return
		_edit_drag_last = event.position
		_edit_drag_moved += d.length()
		_edit_sel.offset_left += d.x
		_edit_sel.offset_right += d.x
		_edit_sel.offset_top += d.y
		_edit_sel.offset_bottom += d.y
		select_layout_button(_edit_sel)

func _layout_hit(pos: Vector2) -> Control:
	for i in range(_layout_btns.size() - 1, -1, -1):
		var c = _layout_btns[i]
		if not is_instance_valid(c):
			continue
		var ctrl := c as Control
		if not ctrl.visible or not ctrl.is_inside_tree():
			continue
		if ctrl.get_global_rect().has_point(pos + _edit_root.get_global_rect().position):
			return ctrl
	return null

func _scale_layout_sel(delta: float) -> void:
	if _edit_sel == null or not is_instance_valid(_edit_sel):
		return
	var s := clampf(_edit_sel.scale.x + delta, LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX)
	_edit_sel.scale = Vector2(s, s)
	select_layout_button(_edit_sel)
	if _edit_hint != null and is_instance_valid(_edit_hint):
		_edit_hint.text = "当前大小 %.0f%% · 拖动按钮调位置 · 保存后生效" % (s * 100.0)

func _reset_layout_edit() -> void:
	PlayerPrefs.clear_btn_layout()
	apply_btn_layout()
	select_layout_button(_edit_sel)
	if _edit_hint != null and is_instance_valid(_edit_hint):
		_edit_hint.text = "已恢复默认布局"

func _exit_layout_edit(save: bool) -> void:
	if save:
		var out: Dictionary = {}
		for c in _layout_btns:
			if not is_instance_valid(c):
				continue
			var ctrl := c as Control
			var def = ctrl.get_meta("layout_def", [])
			if not (def is Array and def.size() == 4):
				continue
			var dx: float = ctrl.offset_left - float(def[0])
			var dy: float = ctrl.offset_top - float(def[1])
			var s: float = clampf(ctrl.scale.x, LAYOUT_SCALE_MIN, LAYOUT_SCALE_MAX)
			if absf(dx) < 0.5 and absf(dy) < 0.5 and absf(s - 1.0) < 0.01:
				continue
			out[str(ctrl.get_meta("layout_key", ""))] = {
				"x": snappedf(dx, 0.5), "y": snappedf(dy, 0.5), "s": snappedf(s, 0.01),
			}
		PlayerPrefs.set_btn_layout(out)
	else:
		apply_btn_layout()
	if _edit_root != null and is_instance_valid(_edit_root):
		_edit_root.queue_free()
	_edit_root = null
	_edit_sel = null
	_edit_box = null
	_edit_hint = null
	get_tree().paused = _edit_was_paused

## 布局编辑中？
func is_layout_editing() -> bool:
	return _edit_root != null and is_instance_valid(_edit_root)


# 详情卡头部技能缩略图：英雄技能走 SkillArt 元素纹样，召唤师技能走 IconArt 功能图标
class _DetailSkillIcon extends Control:
	var _hero_name := ""
	var _skill: Skill = null
	var _slot := 0
	var _icon_kind := ""
	func setup(hero_name: String, skill: Skill, slot: int, icon_kind: String) -> void:
		_hero_name = hero_name
		_skill = skill
		_slot = slot
		_icon_kind = icon_kind
		queue_redraw()
	func _draw():
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r + 3.0, Color(0.02, 0.035, 0.06, 0.9))
		if _icon_kind != "":
			IconArt.draw_icon(self, c, r * 0.92, _icon_kind, false)
		else:
			SkillArt.draw_bg(self, c, r, _hero_name, _skill, _slot, true, true)
		draw_arc(c, r + 2.0, 0.0, TAU, 36, Color(0.46, 0.78, 1.0, 0.62), 1.6, true)

# 详情面板中的“附加效果”徽章：左侧圆底汉字图标 + 右侧数值，整体为圆角深色芯片
class _FxBadge extends Control:
	var _ic := "效"
	var _col := Color.WHITE
	var _sub := ""
	var _rs := 1.0
	func setup(ic: String, col: Color, sub: String, rs: float) -> void:
		_ic = ic
		_col = col
		_sub = sub
		_rs = rs
		queue_redraw()
	func _draw():
		var sb := UiKit.flat(0.92, 10, 1, Color(_col.r, _col.g, _col.b, 0.42),
			Color(0.045, 0.065, 0.105, 0.94), 0.0, 0.0)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2(0, 8.0 * _rs), Vector2(2.4 * _rs, size.y - 16.0 * _rs)),
			Color(_col.r, _col.g, _col.b, 0.9))
		var center := Vector2(21.0 * _rs, size.y * 0.5)
		var rr := 13.0 * _rs
		draw_circle(center, rr, Color(_col.r, _col.g, _col.b, 0.18))
		draw_arc(center, rr, 0.0, TAU, 24, Color(_col.r, _col.g, _col.b, 0.92), 1.4, true)
		var hfs := int(round(16.0 * _rs))
		UiKit.text(self, Vector2(center.x - rr, center.y + hfs * 0.36), _ic, hfs,
			Color(0.97, 0.99, 1.0), HORIZONTAL_ALIGNMENT_CENTER, rr * 2.0)
		if _sub != "":
			var sfs := int(round(13.0 * _rs))
			var avail := size.x - 43.0 * _rs
			while sfs > int(10.0 * _rs) and UiKit.font().get_string_size(
					_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x > avail:
				sfs -= 1
			UiKit.text(self, Vector2(39.0 * _rs, center.y + sfs * 0.36), _sub, sfs,
				Color(0.90, 0.95, 1.0), HORIZONTAL_ALIGNMENT_LEFT, avail)


# 索敌头像按钮：圆形立绘（英雄）或兵种图标（小兵/塔/野怪）+ 阵营色描边，锁定态金色双环
class _EnemyAvatar extends Control:
	signal tapped(ent)
	var entity: Node3D = null
	var hero_name := ""
	var kind := "hero"
	var locked := false
	var dead := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		var hit := false
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			hit = true
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			hit = true
		if hit:
			tapped.emit(entity)
			accept_event()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 5.0
		var foec := Color(1.0, 0.40, 0.34)
		# 底盘 + 外圈（锁定=金色加粗双环）
		draw_circle(c, r + 4.0, Color(0.02, 0.03, 0.05, 0.80))
		if locked:
			draw_arc(c, r + 4.0, 0.0, TAU, 40, Color(1.0, 0.84, 0.30, 0.95), 5.0, true)
			draw_arc(c, r + 10.0, -PI * 0.9, -PI * 0.1, 18, Color(1.0, 0.86, 0.36, 0.55), 3.0, true)
		else:
			draw_arc(c, r + 2.0, 0.0, TAU, 36, Color(foec.r, foec.g, foec.b, 0.62), 2.6, true)
		if kind == "hero":
			HeroArt.draw_portrait(self, c, r, hero_name, foec, dead)
		else:
			IconArt.draw_icon(self, c, r * 0.94, kind, false)
