# NetLobby.gd — 匹配大厅（单机 / 建房 / 加入 / 大厅选人）
#
# 界面态：
#   MENU    标题 + 单机/建房/加入（IP:端口 可编辑）
#   ROOM    在线名单；host 有「开始选人」，guest 等房主发起
#   SELECT  大厅选人：host 与每个 client 各自窗口选「职责→英雄→召唤师」并锁定；
#           前 5 席全员锁齐后自动开局（严格一人一职，空位 AI 补）
#
# 开局流程：host 点「开始选人」→ NetSession.begin_pick()（phase=SELECT）
#   → 全员锁定后 host 延迟约 1.4s 自动 NetSession.start_match()（phase=BATTLE）
#   → 先盖一层加载界面（复用 LoadingScreen），至少 0.45s 后再切场景
#   → host 进 scenes/battle.tscn（按锁定阵容直接开局，不再弹 BM 选人）
#   → client 进 scenes/net_client.tscn，开局后接管自己在选人阶段锁定的英雄
#
# CLI 直连（--net-host/--net-join，cli_mode=true）不进大厅：
#   host → battle.tscn；client → net_client.tscn（保留旧双窗/CI 流程）。
#
# 纯 Control 界面，代码搭建（无 .tscn UI 资源）。中文 UI，所有 GDScript 用 TAB 缩进。

extends Control

enum UIState { MENU, ROOM, SELECT }

const SelectArt = preload("res://scripts/ui/SelectArt.gd")
const MenuBackdropScript = preload("res://scripts/ui/MenuBackdrop.gd")
const TacticalMapScript = preload("res://scripts/ui/TacticalMap.gd")
const ReplayBrowserPanelScript = preload("res://scripts/ui/ReplayBrowserPanel.gd")
const CloudSyncScript = preload("res://scripts/core/CloudSync.gd")
const BootIntroScript = preload("res://scripts/ui/GameBootIntro.gd")
const BootIntro3DScript = preload("res://scripts/ui/GameBootIntro3D.gd")
const LoginPanelScript = preload("res://scripts/ui/LoginPanel.gd")
const BTN_W := 640.0
const BTN_H := 96.0
const PAGE_PAD_X := 64          # 页面左右内边距
const PAGE_PAD_Y := 40          # 页面上下内边距
# 顺序选人（与单机 BattleManager 同款蛇形 10 步：[team, seat]，team0=我方）
const SEL_DRAFT_ORDER := [[0, 0], [1, 0], [1, 1], [0, 1], [0, 2], [1, 2], [1, 3], [0, 3], [0, 4], [1, 4]]
const SEL_DRAFT_TURN_TIME := 20.0
const AUTO_START_DELAY := 5.0   # 全员锁定 → 5 秒倒计时（同单机 BattleManager.PICK_COUNTDOWN）
const ROUTE_DELAY := 2.0        # 加载层最短显示时长（同单机加载界面 2 秒等待），之后才切场景

# --- 操作设置页（PlayerPrefs.opt_* / set_opt，键名与局内读取保持一致） ---
const CTRL_KEYS := ["siege_keys", "target_prio", "auto_chase", "lock_portrait", "flash_dir",
	"skill_sens", "cam_sens", "move_preview", "auto_atk"]
const CTRL_LABELS := {
	"siege_keys": "小兵 / 推塔键",
	"target_prio": "优先攻击目标",
	"auto_chase": "自动追击距离",
	"lock_portrait": "锁敌头像显示",
	"flash_dir": "轻点闪现方向",
	"skill_sens": "技能轮盘灵敏度",
	"cam_sens": "镜头灵敏度",
	"move_preview": "位移预览显示",
	"auto_atk": "自动普通攻击",
}
const CTRL_TARGET_TEXTS := ["百分比血量", "绝对血量", "距离最近"]
const CTRL_CHASE_TEXTS := ["标准（超出攻击范围 3 米）", "近（超出 1 米）", "关"]
const CTRL_SENS_STEPS := [0.6, 0.8, 1.0, 1.2, 1.4, 1.6]

# 统一调色板（取自 UiKit，保留 COL_* 变量名避免大范围改引用）
var COL_BG: Color = UiKit.C_PANEL_BG
var COL_TITLE: Color = UiKit.C_GOLD
var COL_SUB: Color = UiKit.C_TEXT_DIM
var COL_TEXT: Color = UiKit.C_TEXT
var COL_DIM: Color = UiKit.C_TEXT_DISABLED
var COL_OK: Color = UiKit.C_HEAL
var COL_ERR: Color = UiKit.C_DANGER
var COL_GOLD: Color = UiKit.C_GOLD

var _stack: VBoxContainer    # 页面内容根（铺满安全区，各页重建）
var _page: MarginContainer   # 安全内边距容器
var _ui := UIState.MENU
var _role := -1              # -1=无；0=房主；1=玩家（guest）
var _connecting := false
var _menu_btns: Array[Button] = []
var _tac_map = null          # 主菜单战术沙盘（点图选分路）
var _ip_edit: LineEdit = null
var _port_edit: LineEdit = null
var _status: Label = null    # MENU 下的状态行
var _roster_lab: Label = null
var _head_lab: Label = null
var _foot_lab: Label = null
var _start_btn: Button = null
var _leave_btn: Button = null
var _guest_wait_lab: Label = null

# --- 选人阶段（UIState.SELECT，王者式自选版式） ---
var _sel_hero := ""          # 本机当前选中英雄
var _sel_summ := ""          # 本机当前选中召唤师名（中文）
var _sel_sid := ""           # 其 SkillDatabase id
var _pick_status: Label = null
var _pick_summary: Label = null
var _pick_confirm_btn: Button = null
var _auto_start_lab: Label = null   # 底栏状态行：全员锁定后自动进入对局（原「开始对局」按钮位）
var _auto_start_wait := -1.0        # host：全员就绪后的开局倒计时（<0 = 未就绪）
var _auto_start_done := false       # host：已触发过自动开局（防重入）
var _loading: LoadingScreen = null  # 进入对局的加载层（复用单机 LoadingScreen）
var _route_pending := ""            # 待切换场景路径（空 = 无）
var _route_delay := 0.0             # 加载层剩余显示时间
var _route_count := 0               # 已触发的切场景次数（探针/防重入）
var _blocked_roles := {}     # 本机不可选的职责（他人已占）
var _my_seat := 1            # 本机在场席位下标（1..5；>5 即旁观）
var _prev: HeroPreview = null      # 中央 3D 立绘
var _stage_title: Label = null     # 顶部阶段标题
var _countdown_lab: Label = null   # 倒计时环内数字
var _my_slots: HBoxContainer = null    # 顶部我方 mini 席位槽
var _enemy_slots: HBoxContainer = null # 顶部敌方 mini 席位槽
var _my_col: VBoxContainer = null      # 左侧我方 5 席
var _enemy_col: VBoxContainer = null   # 右侧敌方 5 席
var _hero_strip: HBoxContainer = null  # 底部英雄卡条
var _tab_row: HBoxContainer = null     # 底部职业 tab
var _tab_btns := {}                    # role -> Button
var _tab_role := ""                    # "" = 全部
var _hero_btns := {}                   # 英雄名 -> 卡按钮
var _summ_btns := {}                   # 召唤师 id -> 卡按钮
var _summ_manual := false              # 玩家是否手动改过召唤师（false 时跟随英雄推荐）
var _summ_tip: PanelContainer = null   # 召唤师卡悬停浮层
var _prev_role_chip: PanelContainer = null
var _prev_summ_chip: PanelContainer = null
var _prev_chip_row: HBoxContainer = null
# --- 分路（PlayerPrefs，菜单选择 → 房间显示 → 联机选人锁职责） ---
var _lane_btns := {}                   # 分路 -> 菜单页芯片按钮
var _lane_sub_lab: Label = null        # 菜单页「发育路 · 射手」副行
var _lane_info: Label = null           # 房间页「本机分路：…」值
var _room_lane_btns := {}             # 房间页分路选择按钮
var _room_confirm_btn: Button = null  # 房间页「确认阵营与分路」
var _room_ready_lab: Label = null     # 房间页本机确认状态
var _room_camp_lab: Label = null      # 房间页阵营显示
var _room_camp := 0                    # 本机选择阵营（0=蓝方，1=红方；房主固定蓝方）
var _room_camp_btns := {}              # 房间页阵营按钮
var _diff_btn: Button = null           # 菜单页「AI 难度」循环按钮
var _lane_role := ""                   # 选人页本机分路对应职责
var _lane_locked := false              # 选人页是否强制锁该职责（被队友占用则不锁）
# --- 顺序选人（draft：host 权威；空/无此字段 = 旧流程同时选人） ---
var _draft_step := -1              # -1=无顺序；0..9=当前步；10=已完成
var _draft_left := 0.0             # 剩余秒（host 权威值，各端本地递减显示）
var _pick_stage := true          # true=选英雄浮层阶段（同单机 _set_sel_stage）
var _select_bar = null
var _select_right_block = null
var _select_side_left = null
var _select_side_right = null
var _select_pick_layer = null
var _select_pick_summary = null
var _select_nick_edit = null
var _draft_turn: Array = []        # 当前步 [team, seat]
var _draft_picks := {}             # "team-seat" -> 英雄名（我方 AI/敌方席位也按顺序自动选，用于展示/占位）
var _draft_taken := {}             # 展示阵容/他人已选英雄（本机不可再选）
var _draft_ai_timer := 0.0         # host：AI/敌方席位自动选人等待计时
var _draft_ai_wait := 0.0
var _draft_auto_sent := false      # guest：本回合超时自动选已提交
var _stage_sub: Label = null       # 顶部阶段副行（顺序/倒计时）
var _last_state := {}              # 最近一次大厅状态（取玩家名等）
var _preview_name: Label = null    # 中栏英雄预览：英雄名
var _preview_nick: Label = null    # 中栏英雄预览：玩家昵称
var _preview_role: Label = null    # 中栏英雄预览：职责
var _pick_ai_names: Array = []     # 本场 AI 补位/敌方昵称（与单机选人页一致）
var _pick_ai_names_ready := false
var _preview_summ: Label = null    # 中栏英雄预览：召唤师技能
var _preview_summ_icon = null      # 中栏英雄预览：召唤师技能图标
var _preview_tip: Label = null     # 中栏底部提示（含本局分路说明）
var _prev_skill_row: HBoxContainer = null    # 中栏英雄预览：3 个英雄技能 chip 行
var _prev_skill_tip: PanelContainer = null   # 技能 chip 悬停浮层
var _build_row: HBoxContainer = null         # （保留）旧出装按钮行容器引用
var _right_tab := "召唤"                     # 右栏当前页签：召唤 / 出装
var _summ_panel: VBoxContainer = null
var _build_panel: VBoxContainer = null
var _summ_tab_btn: Button = null
var _build_tab_btn: Button = null
var _build_scheme_row: GridContainer = null   # 出装面板：方案按钮网格（4 列）
var _build_cards: GridContainer = null        # 出装面板：6 张装备卡（3 列 × 2 行）
var _item_tip: PanelContainer = null          # 装备图标悬浮详情卡
var _summ_detail: Label = null                 # 召唤面板：选中召唤师的冷却/类型说明
var _build_hero := ""                        # 当前出装方案归属英雄
var _build_ids: Array = []                   # 当前套用的出装 id 列表
var _hero_cfg_cache := {}                    # BattleManager.hero_configs 懒加载缓存（只读）
static var _boot_intro_played := false       # 本次进程只播一次开机动画（战斗返回大厅不重播）
static var _login_completed := false         # 本次进程已完成登录/开始过渡，回到大厅直接进菜单
var _login_layer: CanvasLayer = null


func _ready() -> void:
	# CLI 直连（--net-host/--net-join）：不进大厅，直接路由
	if NetSession.cli_mode:
		if NetSession.mode == NetSession.Mode.HOST:
			_route_battle()
		else:
			_route_client()
		return
	_build_base()
	_connect_signals()
	_show_menu()
	SfxManager.start_menu_music()
	# 主菜单前的电影感启动界面：首次进入大厅播放，之后回大厅直接进菜单
	if not _boot_intro_played:
		_boot_intro_played = true
		_show_boot_intro()
	elif not _login_completed:
		_show_login_panel()


func _show_boot_intro() -> void:
	# 独立 CanvasLayer 高于灵宝悬浮层，保证开机动画期间不被常驻 UI 穿透
	var layer := CanvasLayer.new()
	layer.name = "BootIntroLayer"
	layer.layer = 150
	add_child(layer)
	_mount_boot_intro(layer, true)


func _mount_boot_intro(layer: CanvasLayer, use_3d: bool) -> void:
	for c in layer.get_children():
		if c is Control:
			(c as Control).visible = false
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.queue_free()
	var boot: Node = BootIntro3DScript.new() if use_3d else BootIntroScript.new()
	boot.name = "BootIntro3D" if use_3d else "BootIntro2D"
	layer.add_child(boot)
	boot.finished.connect(func() -> void:
		layer.queue_free()
		if not _login_completed:
			_show_login_panel())
	# 启动界面内按 V：2D / 3D 两个版本即时切换，方便对比
	boot.toggle_requested.connect(func() -> void:
		_mount_boot_intro(layer, not use_3d))


func _show_login_panel() -> void:
	if _login_completed:
		return
	if _login_layer != null and is_instance_valid(_login_layer):
		return
	_login_layer = CanvasLayer.new()
	_login_layer.name = "LoginLayer"
	_login_layer.layer = 160
	add_child(_login_layer)
	var panel: Control = LoginPanelScript.new()
	panel.name = "LoginPanel"
	_login_layer.add_child(panel)
	panel.start_requested.connect(func() -> void:
		if _login_layer != null and is_instance_valid(_login_layer):
			_login_layer.queue_free()
			_login_layer = null
		_play_2d_transition())


func _play_2d_transition() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StartTransitionLayer"
	layer.layer = 150
	add_child(layer)
	var intro: Control = BootIntroScript.new()
	intro.set("transition_mode", true)
	intro.name = "StartTransition2D"
	layer.add_child(intro)
	intro.finished.connect(func() -> void:
		layer.queue_free()
		_login_completed = true)


func _connect_signals() -> void:
	NetSession.net_lobby_state.connect(_on_lobby_state)
	NetSession.net_connect_failed.connect(_on_connect_failed)
	NetSession.net_disconnected_from_host.connect(_on_host_gone)
	NetSession.net_pick_rejected.connect(_on_pick_rejected)


func _build_base() -> void:
	# 兜底不透明底：先铺，保证首帧不透出默认 clear color
	var bg := ColorRect.new()
	bg.color = Color(COL_BG.r, COL_BG.g, COL_BG.b, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 程序化动态背景（渐变+辉光+网格+粒子+暗角）：铺满屏幕并压在最底层之上
	UiKit.make_backdrop(self, UiKit.C_TEAM0, 1.0)
	move_child(bg, 0)

	# 页面区：铺满 + 各页按需设置内边距（菜单/房间 64/40，选人页 16/8）
	_page = MarginContainer.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_page)
	_set_page_pad(int(PAGE_PAD_X), int(PAGE_PAD_Y))

	_stack = VBoxContainer.new()
	_stack.add_theme_constant_override("separation", 18)
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_child(_stack)


# 页面内边距（虚拟像素）
func _set_page_pad(x: int, y: int) -> void:
	if _page == null:
		return
	_page.add_theme_constant_override("margin_left", x)
	_page.add_theme_constant_override("margin_right", x)
	_page.add_theme_constant_override("margin_top", y)
	_page.add_theme_constant_override("margin_bottom", y)


func _clear_stack() -> void:
	for c in _stack.get_children():
		_stack.remove_child(c)
		c.queue_free()
	# 清理浮层（选人中央面板/悬停浮层等直接挂在 _page 上、不属于 _stack）
	if _page != null:
		for c2 in _page.get_children():
			if c2 == _stack:
				continue
			_page.remove_child(c2)
			c2.queue_free()
	# 同步清空指向已释放控件的缓存，避免跨页误用/误刷新
	_status = null
	_diff_btn = null
	_roster_lab = null
	_head_lab = null
	_foot_lab = null
	_start_btn = null
	_leave_btn = null
	_guest_wait_lab = null
	_pick_status = null
	_pick_summary = null
	_pick_confirm_btn = null
	_auto_start_lab = null
	_prev = null
	_stage_title = null
	_stage_sub = null
	_countdown_lab = null
	_my_slots = null
	_enemy_slots = null
	_my_col = null
	_enemy_col = null
	_hero_strip = null
	_tab_row = null
	_prev_role_chip = null
	_prev_summ_chip = null
	_prev_chip_row = null
	_preview_summ_icon = null
	_tab_btns = {}
	_hero_btns = {}
	_summ_btns = {}
	_lane_btns = {}
	_lane_sub_lab = null
	_lane_info = null
	_room_lane_btns = {}
	_room_confirm_btn = null
	_room_ready_lab = null
	_room_camp_lab = null
	_room_camp = 0
	_room_camp_btns = {}
	_lane_role = ""
	_lane_locked = false
	if _summ_tip != null and is_instance_valid(_summ_tip):
		_summ_tip.queue_free()
	_summ_tip = null
	_preview_name = null
	_preview_role = null
	_preview_summ = null
	_ip_edit = null
	_port_edit = null
	_menu_btns = []


# 字号统一走 UiKit 档位（FS_XS..FS_HUGE）× 全局 scale
func _fs(tier: int) -> int:
	return int(round(tier * UiKit.scale()))


# 半透明页面块底板（芯片/卡片），内边距略放大供内容呼吸
func _panel_block(accent: Color, alpha: float, radius := 16, pad := 26.0) -> PanelContainer:
	var p := PanelContainer.new()
	# 描边用低饱和同类色，避免出现纯亮底/亮框
	var sb := UiKit.skin_chip(Color(accent.r, accent.g, accent.b, 0.40), alpha, radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	p.add_theme_stylebox_override("panel", sb)
	return p


func _mk_label(text: String, size: int, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return lab


# 主行动按钮：UiKit.skin_button 四态（filled 实心强调 / 否则深底描边），最小尺寸只增不减
func _mk_btn(text: String, accent: Color, filled := false, min_size := Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size if min_size.x > 0.0 else Vector2(BTN_W, BTN_H)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_XL))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, filled))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, filled))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, filled))
	b.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", accent, filled))
	b.add_theme_color_override("font_color", Color.WHITE if filled else COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_DIM)
	return b


# ---------- MENU ----------

func _show_menu() -> void:
	_clear_stack()
	_set_page_pad(0, 0)
	_ui = UIState.MENU
	_role = -1
	_connecting = false

	# 全屏舞台：动态网格背景 + 中央战术沙盘 + 左右两栏（品牌 / 操作）
	var stage := Control.new()
	stage.name = "MenuStage"
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stack.add_child(stage)

	var bg = MenuBackdropScript.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)

	var map = TacticalMapScript.new()
	map.name = "TacticalMap"
	map.anchor_left = 0.275
	map.anchor_top = 0.085
	map.anchor_right = 0.715
	map.anchor_bottom = 0.845
	stage.add_child(map)
	map.lane_picked.connect(_select_lane)
	_tac_map = map

	# 沙盘下方：当前分路说明（沿用 _style_lane_btns 的文案更新）
	var lane_row := HBoxContainer.new()
	lane_row.anchor_left = 0.275
	lane_row.anchor_top = 0.855
	lane_row.anchor_right = 0.715
	lane_row.anchor_bottom = 0.905
	lane_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_child(lane_row)
	_lane_sub_lab = _mk_label("", _fs(UiKit.FS_MD), UiKit.C_GOLD)
	lane_row.add_child(_lane_sub_lab)
	_lane_btns.clear()
	_style_lane_btns()
	map.set_lane(PlayerPrefs.get_lane())

	# —— 左栏：品牌 + 段位 ——
	var left := VBoxContainer.new()
	left.anchor_left = 0.040
	left.anchor_top = 0.105
	left.anchor_right = 0.258
	left.anchor_bottom = 0.905
	left.add_theme_constant_override("separation", 14)
	stage.add_child(left)

	var title := _mk_label("荣耀王者", int(_fs(UiKit.FS_HUGE) * 1.85), COL_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_outline_color", Color(0.30, 0.16, 0.02, 0.85))
	title.add_theme_constant_override("outline_size", 14)
	left.add_child(title)

	var sub := _mk_label("HONORKING", _fs(UiKit.FS_LG), COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(sub)

	var line := ColorRect.new()
	line.color = Color(UiKit.C_GOLD.r, UiKit.C_GOLD.g, UiKit.C_GOLD.b, 0.8)
	line.custom_minimum_size = Vector2(220, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(line)

	var desc := _mk_label("5v5 峡谷 · 主机权威联机\n单机人机 / 自建房间 / 局域网加入", _fs(UiKit.FS_MD), COL_TEXT)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)

	# 段位卡（单机结算写入 user://rank.json，回主菜单刷新）
	var rs := RankSystem.state()
	var rank_panel := _panel_block(RankSystem.tier_color(rs), 0.34, 14, 18.0)
	rank_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(rank_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 2)
	rank_panel.add_child(rv)
	var r_title := _mk_label("当前段位", _fs(UiKit.FS_XS), COL_DIM)
	r_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rv.add_child(r_title)
	var r_name := _mk_label(RankSystem.label(rs), _fs(UiKit.FS_XL), UiKit.C_GOLD)
	r_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rv.add_child(r_name)
	var r_stars := _mk_label(RankSystem.star_text(rs), _fs(UiKit.FS_MD), RankSystem.tier_color(rs).lightened(0.25))
	r_stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rv.add_child(r_stars)
	var r_meta := _mk_label("胜 %d · 负 %d · 排位积分 %d/%d" % [
		int(rs.get("wins", 0)), int(rs.get("losses", 0)),
		int(rs.get("points", 0)), RankSystem.STAR_POINTS,
	], _fs(UiKit.FS_XS), COL_SUB)
	r_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rv.add_child(r_meta)

	var ver := _mk_label("HonorKing · 主机权威联机", _fs(UiKit.FS_XS), COL_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(ver)

	# —— 右栏：操作按钮列 ——
	var right := VBoxContainer.new()
	# 右栏给足按钮内容宽度，并留出右侧安全边距；内容按两列重排，避免最小宽度把整栏顶出屏幕
	right.anchor_left = 0.725
	right.anchor_top = 0.130
	right.anchor_right = 0.980
	right.anchor_bottom = 0.900
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 14)
	stage.add_child(right)

	var b_single := _mk_btn("▶  单机开局", UiKit.C_GOLD, true, Vector2(420, 88))
	b_single.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_single.pressed.connect(_start_singleplayer)
	right.add_child(b_single)

	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 12)
	right.add_child(room_row)
	var b_host := _mk_btn("■  创建房间", UiKit.C_TEAM0, false, Vector2(1, 72))
	b_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_host.pressed.connect(_create_host)
	room_row.add_child(b_host)
	var b_join := _mk_btn("◆  加入房间", UiKit.C_TEAM0, false, Vector2(1, 72))
	b_join.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_join.pressed.connect(_join_room)
	room_row.add_child(b_join)
	if Config.on_web():
		# 浏览器内无法监听端口：网页版隐藏建房，只能加入桌面主机
		b_host.text = "■  创建房间（网页不可用）"
		b_host.disabled = true

	# 连接参数（收成一行细输入，保持可用但不抢视线）
	var conn := HBoxContainer.new()
	conn.add_theme_constant_override("separation", 8)
	right.add_child(conn)
	var lab_ip := _mk_label("主机", _fs(UiKit.FS_XS), COL_DIM)
	conn.add_child(lab_ip)
	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(0, 44)
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	ip_edit.placeholder_text = "局域网 IP"
	conn.add_child(ip_edit)
	var port_edit := LineEdit.new()
	port_edit.text = "7000"
	port_edit.custom_minimum_size = Vector2(96, 44)
	port_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	port_edit.placeholder_text = "端口"
	conn.add_child(port_edit)
	_ip_edit = ip_edit
	_port_edit = port_edit

	# 功能按钮拆成两行两列：原来 4 个挤一行，最小宽度会把右栏撑出屏幕
	var act_row1 := HBoxContainer.new()
	act_row1.add_theme_constant_override("separation", 10)
	right.add_child(act_row1)
	var b_loadout := _mk_btn("≡  备战", UiKit.C_TEAM0, false, Vector2(1, 56))
	b_loadout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_loadout.pressed.connect(_open_loadout)
	act_row1.add_child(b_loadout)
	var b_history := _mk_btn("★  纪录", UiKit.C_TEAM0, false, Vector2(1, 56))
	b_history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_history.pressed.connect(_open_history)
	act_row1.add_child(b_history)

	var act_row2 := HBoxContainer.new()
	act_row2.add_theme_constant_override("separation", 10)
	right.add_child(act_row2)
	var b_controls := _mk_btn("⚙  设置", UiKit.C_TEAM0, false, Vector2(1, 56))
	b_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_controls.pressed.connect(_open_controls)
	act_row2.add_child(b_controls)
	var b_cloud := _mk_btn("☁  云端", UiKit.C_TEAM0, false, Vector2(1, 56))
	b_cloud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_cloud.pressed.connect(_open_cloud)
	act_row2.add_child(b_cloud)

	# 录像回放：单独一行，避免和功能按钮挤在一起
	var rec_row := HBoxContainer.new()
	rec_row.add_theme_constant_override("separation", 10)
	right.add_child(rec_row)
	var b_heroes := _mk_btn("英  雄", UiKit.C_GOLD, false, Vector2(1, 52))
	b_heroes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_heroes.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b_heroes.pressed.connect(_open_hero_codex)
	rec_row.add_child(b_heroes)
	var b_replay := _mk_btn("▶  录像回放", UiKit.C_TEAM0, false, Vector2(1, 52))
	b_replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_replay.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b_replay.pressed.connect(_open_replays)
	rec_row.add_child(b_replay)
	_menu_btns = [b_single, b_host, b_join, b_loadout, b_history, b_controls, b_cloud, b_heroes, b_replay]

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 10)
	right.add_child(diff_row)
	_diff_btn = _mk_btn("", UiKit.C_GOLD, false, Vector2(1, 48))
	_diff_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_diff_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
	_diff_btn.pressed.connect(_cycle_difficulty)
	diff_row.add_child(_diff_btn)
	_refresh_difficulty_btn()

	_status = _mk_label("", _fs(UiKit.FS_SM), COL_TEXT)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)

	var hint := _mk_label("点沙盘上的路 = 选分路；建房后点「开始选人」，全员锁定自动开局。",
		_fs(UiKit.FS_XS), COL_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)


func _set_menu_enabled(on: bool) -> void:
	for b in _menu_btns:
		if b:
			b.disabled = not on
	_connecting = not on


# 分路芯片（112×56，5 个 + 标签刚好收在 640 按钮列内）
func _mk_lane_btn(lane: String) -> Button:
	var b := Button.new()
	b.text = lane
	b.custom_minimum_size = Vector2(112, 56)
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b.pressed.connect(_select_lane.bind(lane))
	return b


func _style_lane_btns() -> void:
	var cur := PlayerPrefs.get_lane()
	for lane in _lane_btns:
		var b: Button = _lane_btns[lane]
		if not is_instance_valid(b):
			continue
		var on: bool = str(lane) == cur
		b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, on))
		b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, on))
		b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, true))
		b.add_theme_color_override("font_color", Color.WHITE if on else COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
	if _lane_sub_lab != null:
		_lane_sub_lab.text = "%s · %s" % [cur, HeroPickData.lane_role(cur)]


# 点芯片：写偏好 + 即时刷新样式（不重进页面）
func _select_lane(lane: String) -> void:
	PlayerPrefs.set_lane(lane)
	_style_lane_btns()
	_style_room_lane_btns()
	if _tac_map != null and is_instance_valid(_tac_map):
		_tac_map.set_lane(lane)
	# 房间内改分路 = 重新进入待确认状态，必须重新点确认
	if _ui == UIState.ROOM and NetSession.mode != NetSession.Mode.NONE:
		NetSession.set_lobby_ready(_room_camp, lane, false)
		_refresh_lane_info()
		_refresh_room_ready_ui()


func _style_room_lane_btns() -> void:
	var cur := PlayerPrefs.get_lane()
	for lane in _room_lane_btns:
		var b: Button = _room_lane_btns[lane]
		if not is_instance_valid(b):
			continue
		var on: bool = str(lane) == cur
		b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, on))
		b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, on))
		b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, true))
		b.add_theme_color_override("font_color", Color.WHITE if on else COL_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)


func _room_ready_entry() -> Dictionary:
	return NetSession.lobby_ready.get(_self_peer(), {})


func _all_lobby_ready() -> bool:
	if NetSession.mode != NetSession.Mode.HOST:
		return false
	for pid in NetSession.players:
		var r: Dictionary = NetSession.lobby_ready.get(int(pid), {})
		if not bool(r.get("ready", false)) or str(r.get("lane", "")) == "":
			return false
	return true


func _select_room_camp(camp: int) -> void:
	_room_camp = clampi(camp, 0, 1)
	# 改阵营需重新确认（分路不变）
	NetSession.set_lobby_ready(_room_camp, PlayerPrefs.get_lane(), false)
	_refresh_room_ready_ui()


func _on_room_confirm() -> void:
	var lane := PlayerPrefs.get_lane()
	if lane == "":
		if _room_ready_lab != null:
			_room_ready_lab.text = "请先选择分路"
			_room_ready_lab.add_theme_color_override("font_color", COL_ERR)
		return
	NetSession.set_lobby_ready(_room_camp, lane, true)
	_refresh_room_ready_ui()


func _refresh_room_ready_ui() -> void:
	var lane := PlayerPrefs.get_lane()
	var r := _room_ready_entry()
	var ready := bool(r.get("ready", false))
	if not r.is_empty():
		_room_camp = int(r.get("camp", _room_camp))
	var camp_name := "蓝方" if _room_camp == 0 else "红方"
	if _room_camp_lab != null:
		_room_camp_lab.text = camp_name
		_room_camp_lab.add_theme_color_override("font_color",
			UiKit.C_TEAM0 if _room_camp == 0 else UiKit.C_TEAM1)
	for c in _room_camp_btns:
		var cb: Button = _room_camp_btns[c]
		if is_instance_valid(cb):
			cb.set_pressed_no_signal(int(c) == _room_camp)
			cb.add_theme_stylebox_override("normal",
				UiKit.skin_button("normal", UiKit.C_TEAM0 if int(c) == 0 else UiKit.C_TEAM1, int(c) == _room_camp))
			cb.add_theme_stylebox_override("hover",
				UiKit.skin_button("hover", UiKit.C_TEAM0 if int(c) == 0 else UiKit.C_TEAM1, int(c) == _room_camp))
	if _room_ready_lab != null:
		_room_ready_lab.text = ("已确认 · %s · %s" % [camp_name, lane]) if ready else ("待确认 · %s · %s" % [camp_name, lane])
		_room_ready_lab.add_theme_color_override("font_color", COL_OK if ready else COL_GOLD)
	if _room_confirm_btn != null:
		_room_confirm_btn.disabled = ready
		_room_confirm_btn.text = "✓ 已确认阵营与分路" if ready else "✓ 确认阵营与分路"
	if _guest_wait_lab != null:
		_guest_wait_lab.text = "已确认，等待房主开始选人…" if ready else "请选择分路并确认阵营，等待房主开始"
		_guest_wait_lab.add_theme_color_override("font_color", COL_OK if ready else COL_SUB)


# AI 难度循环切换：青铜→白银→…→王者→青铜（本机偏好，联机时主机生效）
func _cycle_difficulty() -> void:
	PlayerPrefs.set_ai_difficulty((PlayerPrefs.get_ai_difficulty() + 1) % AiConfig.DIFF_TABLE.size())
	_refresh_difficulty_btn()


func _refresh_difficulty_btn() -> void:
	var d := PlayerPrefs.get_ai_difficulty()
	var t: Dictionary = AiConfig.DIFF_TABLE.get(d, {})
	if _diff_btn != null:
		_diff_btn.text = "AI 难度 · %s · 命中%d%%" % [
			AiConfig.difficulty_name(d),
			int(round(float(t.get("skill_accuracy", 1.0)) * 100.0)),
		]


# 房间页：本机分路值（房间内可直接点上方分路按钮更换）
func _refresh_lane_info() -> void:
	if _lane_info == null:
		return
	var lane := PlayerPrefs.get_lane()
	_lane_info.text = "本机分路：%s（%s）" % [lane, HeroPickData.lane_role(lane)]


func _status_text(text: String, color: Color) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


# ---------- 动作：单机 / 建房 / 加入 ----------

func _start_singleplayer() -> void:
	_route_battle()


func _create_host() -> void:
	if _connecting:
		return
	var port := _read_port()
	# 建房前把本机昵称交给 NetSession：房间名单里显示真实昵称而不是「房主/玩家N」
	NetSession.set_self_name(_local_nickname())
	var ok := NetSession.host_game(port)
	if not ok:
		_status_text("建房失败：本机已在房间中，或端口被占用", COL_ERR)
		return
	_role = 0
	_show_room()
	_refresh_room_local()


func _join_room() -> void:
	if _connecting:
		return
	var port := _read_port()
	var addr := _ip_edit.text.strip_edges()
	if addr.is_empty():
		_status_text("请先填写主机 IP", COL_ERR)
		return
	_set_menu_enabled(false)
	_status_text("正在连接 %s:%d …" % [addr, port], COL_SUB)
	# 进房前把本机昵称交给 NetSession，连上后自动 RPC 注册到主机名单
	NetSession.set_self_name(_local_nickname())
	NetSession.join_game(addr, port)


func _read_port() -> int:
	var p := _port_edit.text.strip_edges()
	if p.is_valid_int():
		return p.to_int()
	return 7000


# 备战：英雄自定义出装方案（scenes/loadout.tscn，由备战界面负责实现）
func _open_loadout() -> void:
	if _connecting:
		return
	get_tree().call_deferred("change_scene_to_file", "res://scenes/loadout.tscn")


func _open_history() -> void:
	if _connecting:
		return
	var panel := BattleHistoryPanel.new()
	add_child(panel)


# 录像回放列表（user://replays/index.json）
# 英雄模块：3D 模型 + 属性 / 技能 / 玩法 / 出装，可直接跳到该英雄的备战界面
func _open_hero_codex() -> void:
	if _connecting:
		return
	var panel: Control = HeroCodexPanel.new()
	add_child(panel)


func _open_replays() -> void:
	if _connecting:
		return
	var panel: Control = ReplayBrowserPanelScript.new()
	add_child(panel)


# ---------- 云端存档（段位 + 对战纪录；需自备 HTTP 服务） ----------

func _open_cloud() -> void:
	if _connecting:
		return
	_clear_stack()
	_set_page_pad(int(PAGE_PAD_X), int(PAGE_PAD_Y))

	var panel := _panel_block(UiKit.C_TEAM0, 0.42)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := _mk_label("云端存档", int(_fs(UiKit.FS_HUGE) * 1.6), COL_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)
	var tip := _mk_label("把「段位 + 对战纪录」备份到云端，换机可恢复。\n服务端约定：POST {地址}/upload 上传、GET {地址}/download?pid=玩家ID 下载（Bearer Token 可选）。",
		_fs(UiKit.FS_SM), COL_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(tip)

	var cfg := PlayerPrefs.cloud_cfg()
	col.add_child(_cloud_edit_row("服务器地址", "https://example.com/hk", str(cfg.get("url", "")), false))
	col.add_child(_cloud_edit_row("访问令牌", "可留空", str(cfg.get("token", "")), true))
	var pid_lab := _mk_label("玩家 ID：%s" % CloudSyncScript.player_id(), _fs(UiKit.FS_SM), COL_TEXT)
	col.add_child(pid_lab)

	var status := _mk_label("", _fs(UiKit.FS_SM), COL_GOLD)
	col.add_child(status)

	var auto_btn := _mk_btn("", UiKit.C_GOLD, false, Vector2(520, 48))
	auto_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	col.add_child(auto_btn)
	var _refresh_auto := func() -> void:
		auto_btn.text = "赛后自动上传：" + ("开启" if bool(PlayerPrefs.cloud_cfg().get("auto", false)) else "关闭")
	_refresh_auto.call()
	auto_btn.pressed.connect(func() -> void:
		_save_cloud_cfg()
		var c := PlayerPrefs.cloud_cfg()
		c["auto"] = not bool(c.get("auto", false))
		PlayerPrefs.set_cloud_cfg(c)
		_refresh_auto.call())

	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 16)
	col.add_child(act)
	var b_up := _mk_btn("↑  上传到云端", UiKit.C_GOLD, true, Vector2(320, 60))
	b_up.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b_up.pressed.connect(func() -> void:
		_save_cloud_cfg()
		status.text = "上传中…"
		CloudSyncScript.upload(get_tree(), func(ok: bool, code: int, msg: String) -> void:
			status.text = "上传成功" if ok else "上传失败（%d）%s" % [code, msg.left(60)]))
	act.add_child(b_up)
	var b_down := _mk_btn("↓  从云端恢复", UiKit.C_TEAM0, false, Vector2(320, 60))
	b_down.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b_down.pressed.connect(func() -> void:
		_save_cloud_cfg()
		status.text = "下载中…"
		CloudSyncScript.download(get_tree(), func(ok: bool, code: int, msg: String) -> void:
			status.text = msg if ok else "下载失败（%d）%s" % [code, msg.left(60)]))
	act.add_child(b_down)

	var back := _mk_btn("←  返回主菜单", UiKit.C_TEAM0)
	back.pressed.connect(_show_menu)
	col.add_child(back)


# 云端页的一行输入：左说明 + 右 LineEdit
func _cloud_edit_row(label_txt: String, placeholder: String, value: String, secret: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lab := _mk_label(label_txt, _fs(UiKit.FS_MD), COL_TEXT)
	lab.custom_minimum_size = Vector2(200, 0)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, 50)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_override("font", UiKit.font())
	edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	edit.name = "edit"
	row.add_child(edit)
	return row


# 把当前页面两个输入框写回 PlayerPrefs（pid/auto 保留原值）
func _save_cloud_cfg() -> void:
	var url := ""
	var token := ""
	if _stack != null:
		var edits := _stack.find_children("*", "LineEdit", true, false)
		if edits.size() > 0:
			url = (edits[0] as LineEdit).text
		if edits.size() > 1:
			token = (edits[1] as LineEdit).text
	var old := PlayerPrefs.cloud_cfg()
	PlayerPrefs.set_cloud_cfg({
		"url": url.strip_edges(),
		"token": token.strip_edges(),
		"pid": str(old.get("pid", CloudSyncScript.player_id())),
		"auto": bool(old.get("auto", false)),
	})


# ---------- 操作设置（页内切换，不弹独立窗口） ----------

# 9 行：左说明 Label + 右循环切换按钮；点按钮立即写 PlayerPrefs（进对局生效）
func _open_controls() -> void:
	if _connecting:
		return
	_clear_stack()
	_set_page_pad(int(PAGE_PAD_X), int(PAGE_PAD_Y))

	var panel := _panel_block(UiKit.C_TEAM0, 0.42)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := _mk_label("操作设置", int(_fs(UiKit.FS_HUGE) * 1.6), COL_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)

	var tip := _mk_label("设置立即保存，进入对局生效。", _fs(UiKit.FS_SM), COL_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(tip)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)

	for entry in CTRL_KEYS:
		var key := str(entry)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(row)

		var lab := _mk_label(str(CTRL_LABELS.get(key, key)), _fs(UiKit.FS_MD), COL_TEXT)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)

		var ctrl_btn := _mk_btn(_ctrl_btn_text(key), UiKit.C_GOLD, false, Vector2(520, 48))
		ctrl_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
		ctrl_btn.pressed.connect(_cycle_ctrl.bind(key, ctrl_btn))
		row.add_child(ctrl_btn)

	# 键位布局：按钮位置/大小需在对局内直接拖动（能看到真实按钮），这里只说明入口
	var lay_row := HBoxContainer.new()
	lay_row.add_theme_constant_override("separation", 24)
	lay_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(lay_row)
	var lay_lab := _mk_label("键位布局（按钮位置 / 大小）", _fs(UiKit.FS_MD), COL_TEXT)
	lay_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lay_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lay_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay_row.add_child(lay_lab)
	var lay_btn := _mk_btn("对局内「设置 → 自定义键位布局」", UiKit.C_GOLD, false, Vector2(520, 48))
	lay_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	lay_btn.disabled = true
	lay_row.add_child(lay_btn)

	var back := _mk_btn("←  返回主菜单", UiKit.C_TEAM0)
	back.pressed.connect(_show_menu)
	col.add_child(back)


# 当前值 → 按钮显示串（页面构建与点击切换共用）
func _ctrl_btn_text(key: String) -> String:
	match key:
		"siege_keys":
			return "开启" if PlayerPrefs.opt_bool(key, true) else "隐藏"
		"target_prio":
			return str(CTRL_TARGET_TEXTS[clampi(PlayerPrefs.opt_int(key, 0), 0, 2)])
		"auto_chase":
			return str(CTRL_CHASE_TEXTS[clampi(PlayerPrefs.opt_int(key, 0), 0, 2)])
		"lock_portrait":
			return "开启" if PlayerPrefs.opt_bool(key, true) else "关闭"
		"flash_dir":
			return "跟随移动方向" if PlayerPrefs.opt_int(key, 0) == 0 else "智能寻敌"
		"skill_sens", "cam_sens":
			return "%.1fx" % PlayerPrefs.opt_float(key, 1.0)
		"move_preview":
			return "开启" if PlayerPrefs.opt_bool(key, true) else "关闭"
		"auto_atk":
			return "开启" if PlayerPrefs.opt_bool(key, true) else "关闭"
	return str(key)


# 循环切换：读当前值 → 下一档 → 写 PlayerPrefs → 刷新按钮文字
func _cycle_ctrl(key: String, btn: Button) -> void:
	match key:
		"siege_keys":
			PlayerPrefs.set_opt(key, not PlayerPrefs.opt_bool(key, true))
		"target_prio":
			PlayerPrefs.set_opt(key, (clampi(PlayerPrefs.opt_int(key, 0), 0, 2) + 1) % 3)
		"auto_chase":
			PlayerPrefs.set_opt(key, (clampi(PlayerPrefs.opt_int(key, 0), 0, 2) + 1) % 3)
		"lock_portrait":
			PlayerPrefs.set_opt(key, not PlayerPrefs.opt_bool(key, true))
		"flash_dir":
			PlayerPrefs.set_opt(key, 1 - clampi(PlayerPrefs.opt_int(key, 0), 0, 1))
		"skill_sens", "cam_sens":
			var cur := PlayerPrefs.opt_float(key, 1.0)
			var idx := 0
			for i in CTRL_SENS_STEPS.size():
				if absf(float(CTRL_SENS_STEPS[i]) - cur) < 0.01:
					idx = i
					break
			PlayerPrefs.set_opt(key, float(CTRL_SENS_STEPS[(idx + 1) % CTRL_SENS_STEPS.size()]))
		"move_preview":
			PlayerPrefs.set_opt(key, not PlayerPrefs.opt_bool(key, true))
		"auto_atk":
			PlayerPrefs.set_opt(key, not PlayerPrefs.opt_bool(key, true))
	if btn != null and is_instance_valid(btn):
		btn.text = _ctrl_btn_text(key)


# ---------- ROOM ----------

func _show_room() -> void:
	_clear_stack()
	_set_page_pad(int(PAGE_PAD_X), int(PAGE_PAD_Y))
	_ui = UIState.ROOM
	_connecting = false

	# 两栏铺满：左 65% 座位/名单，右 35% 状态与开始按钮
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 40)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(root)

	var who := "房主" if _role == 0 else "玩家"

	# —— 左栏：玩家列表 ——
	var left := _panel_block(UiKit.C_TEAM0, 0.45)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 65.0
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 14)
	left.add_child(lcol)

	var title := _mk_label("对局房间", int(_fs(UiKit.FS_HUGE) * 1.7), COL_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcol.add_child(title)

	var sub := _mk_label("本机身份：" + who + "（" + _self_name() + "）", _fs(UiKit.FS_MD), COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcol.add_child(sub)

	_head_lab = _mk_label("", _fs(UiKit.FS_LG), COL_OK)
	_head_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcol.add_child(_head_lab)

	var cap := _mk_label("玩家列表", _fs(UiKit.FS_LG), COL_TEXT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcol.add_child(cap)

	# 名单：行高放大 + 字号走 FS_LG
	_roster_lab = _mk_label("", _fs(UiKit.FS_LG), COL_TEXT)
	_roster_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_roster_lab.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_roster_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roster_lab.add_theme_constant_override("line_spacing", 20)
	_roster_lab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(_roster_lab)

	var rule := _mk_label("线上玩家会自动接管你方 AI 队友（联机合作 2v5+）。", _fs(UiKit.FS_SM), COL_DIM)
	rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lcol.add_child(rule)

	# —— 右栏：状态 / 开始 / 离开 ——
	var right := _panel_block(UiKit.C_GOLD, 0.38)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 35.0
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 18)
	right.add_child(rcol)

	# 上留白 + 状态/开始块 + 下留白，把操作组放到栏内中偏上，说明与离开键压底
	var lead := Control.new()
	lead.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rcol.add_child(lead)

	var st := _mk_label("房主操作" if _role == 0 else "等待房主", _fs(UiKit.FS_LG), COL_SUB)
	rcol.add_child(st)

	# 阵营 + 分路：进入联机大厅后必须本机确认，全部在线玩家确认后房主才能开始
	var camp_row := HBoxContainer.new()
	camp_row.add_theme_constant_override("separation", 6)
	rcol.add_child(camp_row)
	var camp_cap := _mk_label("阵营：", _fs(UiKit.FS_SM), COL_GOLD)
	camp_row.add_child(camp_cap)
	_room_camp_lab = _mk_label("蓝方", _fs(UiKit.FS_SM), UiKit.C_TEAM0)
	camp_row.add_child(_room_camp_lab)
	# 阵营切换（联机 guest 可选红方；房主固定蓝方，保证 host 端模拟与 UI 一致）
	for c in [0, 1]:
		var cb := _mk_btn("蓝方" if c == 0 else "红方",
			UiKit.C_TEAM0 if c == 0 else UiKit.C_TEAM1, false, Vector2(86, 44))
		cb.toggle_mode = true
		cb.pressed.connect(_select_room_camp.bind(c))
		if NetSession.mode == NetSession.Mode.HOST and c == 1:
			cb.disabled = true
			cb.tooltip_text = "房主固定蓝方（红方请由客户端选择）"
		camp_row.add_child(cb)
		_room_camp_btns[c] = cb
	var lobby_rule := _mk_label("全员确认阵营与分路后，房主才能开始。", _fs(UiKit.FS_XS), COL_DIM)
	lobby_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(lobby_rule)

	var lane_pick := HBoxContainer.new()
	lane_pick.add_theme_constant_override("separation", 4)
	rcol.add_child(lane_pick)
	_room_lane_btns.clear()
	for lane in HeroPickData.LANES:
		var lb := _mk_lane_btn(lane)
		lb.custom_minimum_size = Vector2(102, 48)
		lane_pick.add_child(lb)
		_room_lane_btns[lane] = lb
	_room_confirm_btn = _mk_btn("✓ 确认阵营与分路", UiKit.C_HEAL, true)
	_room_confirm_btn.pressed.connect(_on_room_confirm)
	rcol.add_child(_room_confirm_btn)
	_room_ready_lab = _mk_label("尚未确认", _fs(UiKit.FS_XS), COL_DIM)
	_room_ready_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_room_ready_lab)
	_lane_info = _mk_label("", _fs(UiKit.FS_XS), COL_SUB)
	rcol.add_child(_lane_info)
	_refresh_lane_info()
	_style_room_lane_btns()

	var foot_text := "发起后本窗与每位已连玩家会各自弹出选人面板；全员锁齐后自动进入对局（无需点按钮）。"
	if _role == 0:
		_start_btn = _mk_btn("»  开始选人（全员选英雄）", UiKit.C_HEAL, true)
		_start_btn.pressed.connect(_on_begin_pick)
		rcol.add_child(_start_btn)
	else:
		foot_text = "房主开始选人后，本窗口会弹出英雄+召唤师选择面板；你需先锁定自己的选择。"
		_guest_wait_lab = _mk_label("已连接，等待房主开始选人…", _fs(UiKit.FS_MD), COL_SUB)
		_guest_wait_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rcol.add_child(_guest_wait_lab)

	# 中部留白，把说明与离开键压到底部
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rcol.add_child(spacer)

	_foot_lab = _mk_label(foot_text, _fs(UiKit.FS_SM), COL_DIM)
	_foot_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foot_lab.custom_minimum_size = Vector2(BTN_W, 0)
	rcol.add_child(_foot_lab)

	_leave_btn = _mk_btn("离开房间", UiKit.C_DANGER)
	_leave_btn.pressed.connect(_leave_room)
	rcol.add_child(_leave_btn)


func _refresh_room_local() -> void:
	# host 在房间里的本地刷新（不经过广播，直接用本地 players）
	_on_lobby_state({ "phase": NetSession.current_phase(), "players": NetSession.players })


func _refresh_room(state: Dictionary) -> void:
	var count := int(state.get("players", {}).size())
	if _head_lab != null:
		_head_lab.text = "在线：%d / 8" % count
	var names := _roster_text(state.get("players", {}))
	if _roster_lab != null:
		_roster_lab.text = names
	_refresh_room_ready_ui()
	if _start_btn != null:
		var all_ready := _all_lobby_ready()
		var ready_n := 0
		for pid in NetSession.players:
			if bool(NetSession.lobby_ready.get(int(pid), {}).get("ready", false)):
				ready_n += 1
		_start_btn.text = "»  开始选人（%d/%d 已确认）" % [ready_n, count]
		_start_btn.disabled = not all_ready
		_start_btn.tooltip_text = "" if all_ready else "所有在线玩家确认阵营与分路后才能开始"


func _roster_text(players: Dictionary) -> String:
	var ids := players.keys()
	ids.sort()
	var lines: PackedStringArray = []
	for id in ids:
		var who := "房主" if int(id) == 1 else "玩家"
		var nm: String = str(players[id].get("name", "玩家%d" % id))
		var tag := "（本机）" if _self_peer() == int(id) else ""
		var rr: Dictionary = NetSession.lobby_ready.get(int(id), {})
		if bool(rr.get("ready", false)):
			tag += " · ✓ %s/%s" % ["蓝方" if int(rr.get("camp", 0)) == 0 else "红方", str(rr.get("lane", ""))]
		else:
			tag += " · 待确认"
		lines.append("  " + who + " · " + nm + tag)
	if lines.is_empty():
		return "  （暂无他人）"
	return "\n".join(lines)


func _on_begin_pick() -> void:
	if _role != 0:
		return
	if not _all_lobby_ready():
		if _room_ready_lab != null:
			_room_ready_lab.text = "还有玩家未确认阵营/分路"
			_room_ready_lab.add_theme_color_override("font_color", COL_ERR)
		return
	_auto_start_done = false
	_auto_start_wait = -1.0
	_host_draft_reset()
	NetSession.begin_pick()
	_host_draft_push()


# ---------- 顺序选人：host 推进 10 步蛇形、各端只做倒计时显示（旧端无 draft → 同时选人） ----------

func _process(delta: float) -> void:
	if _route_pending != "":
		_tick_route(delta)
		return
	if _ui != UIState.SELECT:
		return
	_tick_auto_start(delta)
	if _draft_step < 0:
		return
	if _draft_active():
		_draft_left = maxf(0.0, _draft_left - delta)
		if _role == 0:
			_host_draft_tick(delta)
		else:
			_guest_draft_tick()
		_tick_draft_ui()
		return
	_tick_draft_ui()
	# 顺序已结束仍有真人未锁（中途加入/掉线重排）→ host 补齐，避免挡住自动开局
	if _role == 0 and _draft_done():
		for pid in NetSession.players:
			var pp := int(pid)
			if pp == 1 or NetSession.get_picks().has(pp):
				continue
			var hero := _draft_pick_hero(0)
			if hero == "":
				break
			NetSession.host_force_pick(pp, hero, "flash")


# ---------- 全员就绪 → 自动开局（host 权威；无需任何人点按钮） ----------

func _tick_auto_start(delta: float) -> void:
	if _auto_start_done:
		return
	var ready := false
	if _role == 0:
		ready = NetSession._all_active_picked() and (_draft_step < 0 or _draft_done())
	else:
		# 客机：顺序选人走完 + 10 手选满 → 本地同步同一段 5 秒倒计时（开局由 host 广播相位触发切场景）
		ready = _draft_done() and _draft_picks.size() >= 10
	if not ready:
		_auto_start_wait = -1.0
		if _role != 0 and _stage_sub != null and not _draft_active():
			_stage_sub.text = "等待房主开始对局…" if _draft_done() else _stage_sub.text
		return
	if _auto_start_wait < 0.0:
		_auto_start_wait = AUTO_START_DELAY
	var left := _auto_start_wait
	_auto_start_wait -= delta
	var secs: int = maxi(0, int(ceil(maxf(left, 0.0))))
	if _auto_start_lab != null:
		_auto_start_lab.text = "双方阵容已定 · %d 秒后进入对局…" % secs
		_auto_start_lab.add_theme_color_override("font_color", COL_OK)
	# 顶部倒计时环大字（同单机选人结束倒计时 5→1）
	if _countdown_lab != null:
		_countdown_lab.text = str(maxi(secs, 1))
	if _stage_sub != null and secs > 0:
		_stage_sub.text = "全员就绪 · 倒计时 %d 秒" % secs
	if _auto_start_wait > 0.0:
		return
	_auto_start_done = true   # 防重入：本局只触发一次
	if _role == 0:
		NetSession.start_match()


# ---------- 进入对局：加载层（复用 LoadingScreen）→ 延迟切场景 ----------

func _show_loading_then(path: String) -> void:
	if _route_pending != "" or _route_count > 0:
		return   # 防重入：已在过场中/已切过场景
	_route_pending = path
	_route_delay = ROUTE_DELAY
	if _loading == null or not is_instance_valid(_loading):
		_loading = LoadingScreen.new()
		_loading.manual_progress = true
		_loading.hold_full = true
		_loading.process_mode = Node.PROCESS_MODE_ALWAYS
		_loading.setup(_loading_heroes(), "进入对局", "王者峡谷 · 5v5", 2.0)
		add_child(_loading)
	_loading.visible = true
	_loading.set_progress(0.0)


func _tick_route(delta: float) -> void:
	_route_delay -= delta
	if _loading != null and is_instance_valid(_loading):
		_loading.set_progress(clampf(1.0 - maxf(_route_delay, 0.0) / ROUTE_DELAY, 0.0, 1.0))
	if _route_delay > 0.0:
		return
	var path := _route_pending
	_route_pending = ""
	_route_count += 1
	get_tree().call_deferred("change_scene_to_file", path)


# 加载界面阵容：我方真人锁定 + 顺序选人的展示位（AI 补位/敌方），无数据时占位
func _loading_heroes() -> Array:
	var out: Array = []
	var seats: Array = _seat_rows(_last_state)["seats"]
	var t_ally: int = Config.player_team
	var t_foe: int = 1 - Config.player_team
	for i in 5:
		var hn := ""
		if i < seats.size():
			hn = str(seats[i].get("hero", ""))
		if hn == "":
			hn = str(_draft_picks.get("0-%d" % i, ""))
		var role := str(HeroPickData.HERO_ROLE.get(hn, ""))
		var ent := { "name": hn if hn != "" else "—",
			"role": role if role != "" else "我方 %d 号位" % (i + 1), "team": t_ally }
		if i == 0:
			ent["is_player"] = true
		out.append(ent)
	for i in 5:
		var hn2 := str(_draft_picks.get("1-%d" % i, ""))
		var role2 := str(HeroPickData.HERO_ROLE.get(hn2, ""))
		out.append({ "name": hn2 if hn2 != "" else "—",
			"role": role2 if role2 != "" else "敌方 %d 号位" % (i + 1), "team": t_foe })
	return out


func _draft_active() -> bool:
	return _draft_step >= 0 and _draft_step < SEL_DRAFT_ORDER.size()


func _draft_done() -> bool:
	return _draft_step >= SEL_DRAFT_ORDER.size()


func _draft_is_my_turn() -> bool:
	if not _draft_active() or _draft_turn.size() < 2:
		return false
	return int(_draft_turn[0]) == 0 and int(_draft_turn[1]) == _my_seat - 1


# 我方第 seat 席（0-based）对应的 peer；超过真人数 = AI 席位（与 _seat_rows 同序、去重）
func _seat_peer(seat: int) -> int:
	var ids: Array = NetSession.get_seat_order()
	if seat < 0 or seat >= ids.size():
		return -1
	return int(ids[seat])


# 本机此刻能否锁定（草稿齐 + 轮到自己 + 未结束）
func _pick_ready() -> bool:
	if _sel_hero == "" or _sel_sid == "" or _draft_done():
		return false
	return not (_draft_active() and not _draft_is_my_turn())


func _hero_pickable(hname: String) -> bool:
	if hname == "" or not HeroPickData.HERO_ROLE.has(hname):
		return false
	var role := str(HeroPickData.HERO_ROLE[hname])
	if _draft_taken.has(hname) or _blocked_roles.has(role):
		return false
	if _lane_locked and role != _lane_role:
		return false
	return true


# 本分路内随机一名可选的英雄（超时自动选，同单机 _random_lane_hero）
func _random_lane_hero() -> String:
	var pool: Array = []
	for hn in HeroPickData.HERO_ROLE:
		var h := str(hn)
		if str(HeroPickData.HERO_ROLE[h]) == _lane_role and _hero_pickable(h):
			pool.append(h)
	if pool.is_empty():
		for hn in HeroPickData.HERO_ROLE:
			if _hero_pickable(str(hn)):
				pool.append(str(hn))
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])


# host：按「全局唯一 + 本队一职一人」挑展示用英雄（我方 AI 不占房主分路，同单机语义）
func _draft_pick_hero(team: int) -> String:
	var used := {}
	var roles := {}
	var picks := NetSession.get_picks()
	for k in _draft_picks:
		var h := str(_draft_picks[k])
		used[h] = true
		if int(str(k).split("-")[0]) == team:
			roles[str(HeroPickData.HERO_ROLE.get(h, ""))] = true
	for pid in picks:
		used[str(picks[pid].get("hero", ""))] = true
		if team == 0:
			roles[str(picks[pid].get("role", ""))] = true   # 敌方职责与本方独立
	var pool: Array = []
	var fallback: Array = []
	for hn in HeroPickData.HERO_ROLE:
		var h2 := str(hn)
		if used.has(h2):
			continue
		fallback.append(h2)
		var role := str(HeroPickData.HERO_ROLE[h2])
		if roles.has(role) or (team == 0 and role == _lane_role):
			continue
		pool.append(h2)
	if pool.is_empty():
		pool = fallback
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])


func _draft_turn_label() -> String:
	if _draft_turn.size() < 2:
		return ""
	var team := int(_draft_turn[0])
	var seat := int(_draft_turn[1])
	if team == 1:
		return "红方 %d 号位" % (seat + 1)
	var pid := _seat_peer(seat)
	if pid <= 0:
		return "我方 %d 号位 · AI" % (seat + 1)
	return "我方 %d 号位 · %s" % [seat + 1, _player_name(pid, _last_state)]


func _draft_title_text() -> String:
	if _draft_done():
		return "双方阵容已定"
	if not _draft_active():
		return "选择英雄"
	return "第 %d/10 步 · %s 选人" % [_draft_step + 1, _draft_turn_label()]


func _draft_sub_text() -> String:
	if _draft_done():
		return "阵容已定 · 全员就绪后自动进入对局"
	if not _draft_active():
		return ""
	var left := int(ceil(maxf(0.0, _draft_left)))
	if _draft_is_my_turn():
		return "轮到你选 · 剩余 %ds · 选英雄→召唤师→锁定" % left
	return "等待 %s · 剩余 %ds" % [_draft_turn_label(), left]


func _tick_draft_ui() -> void:
	# 开局 5 秒倒计时期间：标题/副行/环内数字由 _tick_auto_start 接管，别被选人页刷新覆盖
	if _auto_start_wait >= 0.0:
		return
	if _stage_title != null:
		_stage_title.text = _draft_title_text()
	if _stage_sub != null:
		_stage_sub.text = _draft_sub_text()
	if _countdown_lab != null:
		if _draft_active():
			_countdown_lab.text = str(int(ceil(maxf(0.0, _draft_left))))
		else:
			_countdown_lab.text = "√" if _draft_done() else "∞"


func _host_draft_reset() -> void:
	_draft_step = 0
	_draft_left = SEL_DRAFT_TURN_TIME
	_draft_turn = SEL_DRAFT_ORDER[0]
	_draft_picks = {}
	_draft_taken = {}
	_draft_ai_timer = 0.0
	_draft_ai_wait = randf_range(1.2, 2.2)


func _host_draft_push() -> void:
	NetSession.set_draft({
		"step": _draft_step,
		"left": _draft_left,
		"turn": _draft_turn,
		"picks": _draft_picks.duplicate(true),
	})


func _host_draft_advance() -> void:
	_draft_step += 1
	_draft_left = SEL_DRAFT_TURN_TIME
	_draft_ai_timer = 0.0
	_draft_ai_wait = randf_range(1.2, 2.2)
	_draft_turn = SEL_DRAFT_ORDER[_draft_step] if _draft_step < SEL_DRAFT_ORDER.size() else []
	_host_draft_push()


func _host_draft_tick(delta: float) -> void:
	if _draft_turn.size() < 2:
		return
	var team := int(_draft_turn[0])
	var seat := int(_draft_turn[1])
	var pid := _seat_peer(seat) if team == 0 else -1
	if pid > 0:
		# 真人回合：锁定后推进；剩 1s 仍没锁 → host 代选兜底（客户端自己 0s 会先自动选）
		if NetSession.get_picks().has(pid):
			_host_draft_advance()
		elif _draft_left <= 1.0:
			_host_auto_pick(pid)
		return
	# AI 席位／敌方 5 席：像单机一样等 1~2s 再自动选，作为展示阵容
	_draft_ai_timer += delta
	if _draft_ai_timer >= _draft_ai_wait or _draft_left <= 0.0:
		var hero := _draft_pick_hero(team)
		_draft_picks["%d-%d" % [team, seat]] = hero
		_host_draft_advance()


func _host_auto_pick(pid: int) -> void:
	var mine := pid == _self_peer()
	var hero := ""
	if mine:
		hero = _sel_hero if _hero_pickable(_sel_hero) else _random_lane_hero()
	if hero == "":
		hero = _draft_pick_hero(0)
	if hero == "":
		return
	var summ := _sel_sid if (mine and _sel_sid != "") else "flash"
	if NetSession.host_force_pick(pid, hero, summ):
		_host_draft_advance()


func _guest_draft_tick() -> void:
	if not _draft_is_my_turn() or _draft_auto_sent or _draft_left > 0.0:
		return
	_draft_auto_sent = true
	var hero := _sel_hero if _hero_pickable(_sel_hero) else _random_lane_hero()
	if hero == "":
		return
	NetSession.send_pick(hero, _sel_sid if _sel_sid != "" else "flash")
	if _pick_status != null:
		_pick_status.text = "超时自动锁定 %s" % hero
		_pick_status.add_theme_color_override("font_color", COL_SUB)


# 采纳主机广播的顺序状态（旧端/无字段 → -1 退化同时选人）
func _apply_draft_state(d) -> void:
	var nd: Dictionary = d if d is Dictionary else {}
	if nd.is_empty():
		_draft_step = -1
		_draft_left = 0.0
		_draft_turn = []
		_draft_picks = {}
		return
	var step := int(nd.get("step", -1))
	if step != _draft_step:
		_draft_auto_sent = false
	_draft_step = step
	_draft_left = float(nd.get("left", SEL_DRAFT_TURN_TIME))
	_draft_turn = nd.get("turn", [])
	_draft_picks = nd.get("picks", {})


func _draft_reset_local() -> void:
	_draft_step = -1
	_draft_left = 0.0
	_draft_turn = []
	_draft_picks = {}
	_draft_taken = {}
	_draft_auto_sent = false


func _leave_room() -> void:
	_draft_reset_local()
	_auto_start_done = false
	_auto_start_wait = -1.0
	NetSession.disconnect_network()
	_show_menu()
	_status_text("已离开房间", COL_SUB)


# ---------- SELECT：大厅选人（host 与每个 client 各自窗口同屏） ----------

func _seat_rows(state: Dictionary) -> Dictionary:
	# 场上席顺序 = host 随机席位顺序（不固定房主 1 号）；前 5 在场，其余旁观
	var ids: Array = NetSession.get_seat_order()
	if ids.is_empty():
		ids = [1]
		var pl0: Dictionary = state.get("players", {})
		for p in pl0:
			if not ids.has(int(p)):
				ids.append(int(p))
		ids.sort()
	var picks: Dictionary = state.get("picks", {})
	var seats: Array = []
	var spect: Array = []
	var idx := 0
	for pid in ids:
		idx += 1
		if idx > NetSession.MAX_SIDE_PLAYERS:
			spect.append(_player_name(int(pid), state))
			continue
		var pk: Dictionary = picks.get(pid, {})
		seats.append({
			"id": int(pid),
			"is_me": int(pid) == _self_peer(),
			"name": _player_name(int(pid), state),
			"hero": str(pk.get("hero", "")),
			"role": str(pk.get("role", "")),
			"summoner": str(pk.get("summoner", "")),
		})
	return { "seats": seats, "spectators": spect }


func _player_name(pid: int, state: Dictionary) -> String:
	var pl: Dictionary = state.get("players", {})
	var nm := "玩家%d" % pid
	if pid == 1:
		nm = "房主"
	elif pl.has(pid):
		var obj = pl[pid]
		if obj is Dictionary:
			nm = str(obj.get("name", nm))
		else:
			nm = str(obj)
	if pid == _self_peer():
		nm += "（本机）"
	return nm


# 本机昵称：优先玩家缓存，其次账号名，最后网络席位名
func _local_nickname() -> String:
	var nm := NameStore.player_name().strip_edges()
	if nm == "":
		nm = AccountService.last_username().strip_edges()
	if nm == "":
		nm = _player_name(_self_peer(), _last_state)
	return nm


func _ensure_pick_ai_names() -> void:
	if _pick_ai_names_ready:
		return
	var exclude: Array = [_local_nickname()]
	for pid in NetSession.players:
		var n := str(NetSession.players[pid].get("name", "")).strip_edges()
		if n != "":
			exclude.append(n)
	_pick_ai_names = NameStore.random_ai_names(10, exclude)
	_pick_ai_names_ready = true


# 把「真实席位 + 顺序选人自动补位 + 敌方 AI」统一成同一份展示数据：
# 昵称 / 英雄名 / 职责 / 召唤师，供席位卡、mini 槽、中央预览共用。
func _seat_view(i: int, actual: Dictionary, enemy: bool) -> Dictionary:
	_ensure_pick_ai_names()
	var hero := str(actual.get("hero", ""))
	if hero == "":
		hero = str(_draft_picks.get("%d-%d" % [1 if enemy else 0, i], ""))
	var role := str(actual.get("role", ""))
	if role == "" and hero != "":
		role = str(HeroPickData.HERO_ROLE.get(hero, ""))
	var summ := str(actual.get("summoner", ""))
	if summ == "" and hero != "":
		summ = HeroPickData.recommended_summoner(hero)
	var is_ai := actual.is_empty() or enemy
	var nm := str(actual.get("name", ""))
	if bool(actual.get("is_me", false)):
		nm = _local_nickname()
	elif is_ai:
		var ai_i := (5 + i) if enemy else i
		nm = str(_pick_ai_names[ai_i]) if ai_i < _pick_ai_names.size() else "AI %d" % (ai_i + 1)
	return {
		"name": nm, "hero": hero, "role": role, "summoner": summ,
		"is_ai": is_ai, "is_me": bool(actual.get("is_me", false)), "enemy": enemy,
	}


func _role_owner(role: String, data: Dictionary) -> String:
	for s in data["seats"]:
		if str(s.role) == role:
			return str(s.name)
	return ""


func _self_role(state: Dictionary) -> String:
	var mine: Dictionary = state.get("picks", {}).get(_self_peer(), {})
	return str(mine.get("role", ""))


func _summoner_name(sid: String) -> String:
	for sname in HeroPickData.SUMMONERS:
		if str(HeroPickData.SUMMONERS[sname]) == sid:
			return sname
	return sid


func _adopt_self_choice(state: Dictionary, data: Dictionary) -> void:
	# 权威里已有我的锁定 → 作为改选起点；否则保留本机未锁定的草稿（职责仍可用时）
	var mine: Dictionary = state.get("picks", {}).get(_self_peer(), {})
	if not mine.is_empty():
		_sel_hero = str(mine.get("hero", ""))
		_sel_sid = str(mine.get("summoner", ""))
		_sel_summ = _summoner_name(_sel_sid)
		return
	if _sel_hero != "" and HeroPickData.HERO_ROLE.has(_sel_hero):
		if not _blocked_roles.has(str(HeroPickData.HERO_ROLE[_sel_hero])):
			return
	_sel_hero = ""
	_sel_sid = ""
	_sel_summ = ""


# 倒计时环（纯 _draw 装饰环；无网络计时时只作视觉占位）
class CountRing extends Control:
	var accent := Color(0.25, 0.85, 1.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var ctr := size * 0.5
		var rad := maxf(6.0, minf(size.x, size.y) * 0.5 - 4.0)
		draw_circle(ctr, rad, Color(accent.r, accent.g, accent.b, 0.10))
		draw_arc(ctr, rad, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 5.0, true)
		draw_arc(ctr, rad, -PI * 0.5, PI * 0.9, 40, accent, 5.0, true)


# ==================== SELECT：王者式自选版式 ====================
# 顶部阶段条（我方/敌方 mini 槽 + 标题 + 倒计时环）→ 中部 5v5 席位 + 中央 3D 立绘 →
# 底部 职业 tab + 英雄卡条 + 右侧召唤师/详情/锁定。网络逻辑与回调全部沿用。
func _show_select(state: Dictionary) -> void:
	var entering_select := _ui != UIState.SELECT
	_ui = UIState.SELECT
	if entering_select:
		_pick_ai_names_ready = false
		_pick_stage = true
	_connecting = false
	_clear_stack()
	_set_page_pad(16, 8)
	# 手机横屏：选人页再避让刘海/圆角/手势条（桌面 safe_* 为 0）
	_page.add_theme_constant_override("margin_left", 16 + int(round(UiKit.safe_left())))
	_page.add_theme_constant_override("margin_right", 16 + int(round(UiKit.safe_right())))
	_page.add_theme_constant_override("margin_top", 8 + int(round(UiKit.safe_top())))
	_page.add_theme_constant_override("margin_bottom", 8 + int(round(UiKit.safe_bottom())))
	var data := _seat_rows(state)
	_my_seat = 1
	for s in data["seats"]:
		if s.is_me:
			break
		_my_seat += 1
	_blocked_roles = {}
	for s in data["seats"]:
		if s.is_me:
			continue
		if str(s.role) != "":
			_blocked_roles[str(s.role)] = true
	# 顺序选人的展示阵容（我方 AI/敌方席）也占英雄与职责：本机不可再选
	_draft_taken = {}
	if _draft_step >= 0:
		for k in _draft_picks:
			var dh := str(_draft_picks[k])
			if dh == "" or not HeroPickData.HERO_ROLE.has(dh):
				continue
			_draft_taken[dh] = true
			if str(k).begins_with("0-"):
				_blocked_roles[str(HeroPickData.HERO_ROLE[dh])] = true
	# 分路以房间确认的 lobby_ready.lane 为准（同步到本地 PlayerPrefs，选人页与房间不再不一致）
	var _room_r = _room_ready_entry()
	if _room_r is Dictionary:
		var _rl := str((_room_r as Dictionary).get("lane", "")).strip_edges()
		if _rl != "" and PlayerPrefs.get_lane() != _rl:
			PlayerPrefs.set_lane(_rl)
			_style_lane_btns()
			_style_room_lane_btns()
	# 分路 → 职责：未被队友占用则锁死本局职责，否则放开并提示
	_lane_role = HeroPickData.lane_role(PlayerPrefs.get_lane())
	_lane_locked = _lane_role != "" and not _blocked_roles.has(_lane_role)
	if _lane_locked:
		_tab_role = _lane_role
	elif _tab_role == _lane_role:
		_tab_role = ""
	_adopt_self_choice(state, data)
	# 进入选人页：已锁定/已选英雄时直接进入立绘阶段（同单机按 sel_player_picked 初始化）
	_pick_stage = _sel_hero == ""
	_stack.add_child(_build_stage_bar(data, state))
	_stack.add_child(_build_select_main(data))
	_stack.add_child(_build_select_bottom())
	_refresh_preview()
	_refresh_select(state, data)


# 顶部 92 高阶段条：我方 5 mini 席 | 标题+副行+倒计时环 | 敌方 5 mini 席
func _build_stage_bar(data: Dictionary, state: Dictionary) -> Control:
	var bar := _panel_block(UiKit.C_GOLD, 0.30, 14, 8.0)
	bar.custom_minimum_size = Vector2(0, 92)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	bar.add_child(h)

	# 左：我方 mini 席位槽（标题与槽同行，压住阶段条高度 92）
	var left := HBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lt := _mk_label("我方", _fs(UiKit.FS_SM), UiKit.C_TEAM0)
	lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.add_child(lt)
	_my_slots = HBoxContainer.new()
	_my_slots.add_theme_constant_override("separation", 6)
	left.add_child(_my_slots)
	h.add_child(left)

	# 中：标题 + 副行 + 倒计时环
	var mid := Control.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var mv := HBoxContainer.new()
	mv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 18)
	mid.add_child(mv)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", 0)
	_stage_title = _mk_label(_draft_title_text(), _fs(UiKit.FS_XL), COL_TITLE)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_stage_title)
	# 副行：顺序选人时显示回合/倒计时；无顺序时沿用玩法说明 + 分路提示
	var lane := PlayerPrefs.get_lane()
	var stage_sub_txt := _draft_sub_text()
	if stage_sub_txt == "":
		stage_sub_txt = "联机自选 · 全员锁定后自动开局"
		if _lane_locked:
			stage_sub_txt = "本机分路：%s · 只能选择%s" % [lane, _lane_role]
		elif _lane_role != "":
			stage_sub_txt = "本机分路「%s」已被队友占用，可选其他职责" % lane
	_stage_sub = _mk_label(stage_sub_txt, _fs(UiKit.FS_SM), COL_SUB)
	_stage_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_stage_sub)
	mv.add_child(tv)
	mv.add_child(_mk_count_ring(int(ceil(maxf(0.0, _draft_left))) if _draft_active() else _stage_seconds(state)))

	# 右：敌方 mini 席位槽
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rt := _mk_label("敌方", _fs(UiKit.FS_SM), UiKit.C_TEAM1)
	rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_child(rt)
	_enemy_slots = HBoxContainer.new()
	_enemy_slots.add_theme_constant_override("separation", 6)
	right.add_child(_enemy_slots)
	h.add_child(right)

	# 填充 mini 槽（我方取真实席位，缺位 = AI 补齐；敌方 5 席 = AI；顺序选人时显示已选英雄）
	var seats: Array = data["seats"]
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		var seat: Dictionary = seats[i] if i < seats.size() else {}
		var ally := _seat_view(i, seat, false)
		var mine := bool(ally.is_me)
		_my_slots.add_child(_mk_mini_slot(
			"%d · %s" % [i + 1, str(ally.name)],
			str(ally.hero) if str(ally.hero) != "" else "待选",
			UiKit.C_TEAM0, mine))
		var foe := _seat_view(i, {}, true)
		_enemy_slots.add_child(_mk_mini_slot(
			"%d · %s" % [i + 1, str(foe.name)],
			str(foe.hero) if str(foe.hero) != "" else "待选",
			UiKit.C_TEAM1, false))
	return bar


# 150×72 mini 席位槽：席位号+名字 / 已选英雄或待选（自己金框）
func _mk_mini_slot(title: String, sub: String, accent: Color, mine: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(150, 72)
	var sb: StyleBoxFlat = UiKit.skin_card(UiKit.C_GOLD, true) if mine else UiKit.skin_chip(accent, 0.55, 10)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 5)
	p.add_child(h)
	var av_name := sub if HeroPickData.HERO_ROLE.has(sub) else ""
	h.add_child(SelectArt.Avatar.new(av_name, accent, 28))
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var t := _mk_label(title, _fs(UiKit.FS_XS), UiKit.C_GOLD if mine else accent.lightened(0.25))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(t)
	var s := _mk_label(sub, _fs(UiKit.FS_XS), COL_TEXT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(s)
	return p


# 倒计时环 72×72：state 无剩余秒数时显示 ∞ 装饰环
func _mk_count_ring(seconds: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(72, 72)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring := CountRing.new()
	ring.accent = UiKit.C_TEAM0
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ring)
	_countdown_lab = _mk_label("∞" if seconds < 0 else str(seconds), _fs(UiKit.FS_MD), COL_TEXT)
	_countdown_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_countdown_lab)
	return box


# 选人阶段剩余秒数（NetSession 的 lobby_state 目前不带计时 → 缺省 -1 显示 ∞）
func _stage_seconds(state: Dictionary) -> int:
	for k in ["remain", "left", "time_left", "countdown", "seconds"]:
		if state.has(k):
			return int(state[k])
	return -1


# 中部：左我方 5 席 | 中央 3D 立绘 + 覆盖层 | 右敌方 5 席
func _build_select_main(data: Dictionary) -> Control:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 10)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_my_col = VBoxContainer.new()
	_my_col.custom_minimum_size = Vector2(218, 0)
	_my_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_my_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_col.add_theme_constant_override("separation", 6)
	main.add_child(_my_col)
	var seats: Array = data["seats"]
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		var seat: Dictionary = seats[i] if i < seats.size() else {}
		_my_col.add_child(_mk_seat_card(i + 1, _seat_view(i, seat, false), false))

	main.add_child(_build_center_stage())

	_enemy_col = VBoxContainer.new()
	_enemy_col.custom_minimum_size = Vector2(218, 0)
	_enemy_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enemy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemy_col.add_theme_constant_override("separation", 6)
	main.add_child(_enemy_col)
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		# 敌方虽然由 AI 操作，也显示 AI 昵称 + 顺序选人已选出的英雄名
		_enemy_col.add_child(_mk_seat_card(i + 1, _seat_view(i, {}, true), true))
	return main


# 中央：HeroPreview（独立 SubViewport，铺满中栏，不进 ScrollContainer）+ 覆盖层
func _build_center_stage() -> Control:
	var box := Control.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	_prev = preload("res://scripts/ui/HeroPreview.gd").new() as HeroPreview
	box.add_child(_prev)
	_prev.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 覆盖层：英雄名大标题 / 职责 chip / 召唤师 chip / 技能 chip 行
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 28)
	box.add_child(margin)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	_preview_name = _mk_label("—", int(round(UiKit.FS_HUGE * 1.12 * UiKit.scale())), COL_GOLD)
	_preview_name.add_theme_constant_override("outline_size", 8)
	_preview_name.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.02, 0.9))
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_preview_name)

	_preview_nick = _mk_label("玩家 · %s" % _local_nickname(), _fs(UiKit.FS_SM), COL_SUB)
	_preview_nick.visible = false   # 单机选人页预览层无昵称行（昵称在席位卡），保持一致
	_preview_nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_nick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_preview_nick)

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 10)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chip_row)

	_prev_role_chip = PanelContainer.new()
	_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.95, 12))
	_prev_role_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_role = _mk_label("定位 · —", _fs(UiKit.FS_SM), UiKit.C_TEAM0)
	_preview_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev_role_chip.add_child(_preview_role)
	chip_row.add_child(_prev_role_chip)

	_prev_summ_chip = PanelContainer.new()
	_prev_summ_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_GOLD, 0.9, 12))
	_prev_summ_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_summ_icon = SelectArt.SummonerGlyph.new("", 48)
	srow.add_child(_preview_summ_icon)
	_preview_summ = _mk_label("推荐召唤师 · —", _fs(UiKit.FS_SM), COL_GOLD)
	_preview_summ.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_summ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(_preview_summ)
	_prev_summ_chip.add_child(srow)
	chip_row.add_child(_prev_summ_chip)

	_prev_chip_row = HBoxContainer.new()
	_prev_chip_row.add_theme_constant_override("separation", 8)
	_prev_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_prev_chip_row)

	# 英雄技能 chip 行：3 个技能（图标 + 名称 + 类型/冷却），悬停看伤害/效果简介
	_prev_skill_row = HBoxContainer.new()
	_prev_skill_row.add_theme_constant_override("separation", 8)
	_prev_skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_prev_skill_row)

	_preview_tip = _mk_label("分路：%s · 只能选择%s · 每队每个职责限选 1 名英雄" % [PlayerPrefs.get_lane(), _lane_role], _fs(UiKit.FS_XS), Color(1,1,1,0.4))
	_preview_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_preview_tip)
	return box


# 196×136 席位卡：号位+身份 / 玩家昵称 / 英雄名 / 职责·召唤师（与单机选人对齐）
func _mk_seat_card(idx: int, seat: Dictionary, enemy: bool) -> PanelContainer:
	var mine := bool(seat.get("is_me", false))
	var is_ai := bool(seat.get("is_ai", false))
	var hero := str(seat.get("hero", ""))
	var role := str(seat.get("role", ""))
	var accent: Color = UiKit.C_TEAM1 if enemy else UiKit.C_TEAM0
	if hero != "":
		accent = HeroPickData.ROLE_COLORS.get(role, accent)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(214, 138)
	p.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD if mine else accent, mine, 0.72))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	row.add_child(SelectArt.Avatar.new(hero, accent, 76))
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 1)
	row.add_child(v)

	var side_txt := "我" if mine else ("敌方" if enemy else ("AI" if is_ai else "队友"))
	var head := _mk_label("%d 号位 · %s" % [idx, side_txt], _fs(UiKit.FS_XS),
		UiKit.C_GOLD if mine else COL_SUB)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(head)

	# 昵称行（同单机席位卡：「我 · 昵称」/「队友 1 · 昵称」/「对手 1 · 昵称」）
	var nick := str(seat.get("name", ""))
	if nick == "":
		nick = "AI %d" % idx
	var nick_line := ("我 · %s" % nick) if mine else (("对手 %d · %s" % [idx, nick]) if enemy else ("队友 %d · %s" % [idx, nick]))
	var pname := _mk_label(nick_line, _fs(UiKit.FS_XS),
		UiKit.C_GOLD if mine else (Color(1.0, 0.62, 0.58) if enemy else UiKit.C_TEAM0.lightened(0.45)))
	pname.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(pname)

	# 英雄名行（头像旁第二行，选中后显示真实英雄名；未选显示待选/选择中）
	var hero_line := hero if hero != "" else ("选择中" if mine else "待选")
	var hero_lab := _mk_label(hero_line, _fs(UiKit.FS_SM),
		UiKit.C_GOLD if mine else (COL_TEXT if hero != "" else COL_DIM))
	hero_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(hero_lab)

	var sub_txt := "红方 · 电脑控制"
	if hero != "":
		var summ_nm := _summoner_name(str(seat.get("summoner", "")))
		sub_txt = ("%s · %s" % [role, summ_nm]) if role != "" else summ_nm
	elif is_ai:
		sub_txt = "红方 · 电脑控制" if enemy else "空位 · AI 补"
	else:
		sub_txt = "职责未定"
	var sub := _mk_label(sub_txt, _fs(UiKit.FS_XS), COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	return p


# 底部 300：左职业 tab + hero 横条 | 右召唤师 2 列 + 详情 + 离开/锁定 + 自动开局状态行
func _build_select_bottom() -> Control:
	var bar := HBoxContainer.new()
	_select_bar = bar
	bar.add_theme_constant_override("separation", 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 0)

	# 左操作区（同单机 SelectSideLeft 190 宽）：换英雄 / 返回大厅
	var side_left := VBoxContainer.new()
	_select_side_left = side_left
	side_left.custom_minimum_size = Vector2(190, 0)
	side_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side_left.add_theme_constant_override("separation", 10)
	bar.add_child(side_left)
	var back_btn := _mk_btn("换英雄", UiKit.C_PANEL_EDGE, false, Vector2(190, 86))
	back_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	back_btn.pressed.connect(_back_to_pick)
	side_left.add_child(back_btn)
	_leave_btn = _mk_btn("返回大厅", UiKit.C_TEAM1, false, Vector2(190, 86))
	_leave_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	_leave_btn.pressed.connect(_leave_room)
	side_left.add_child(_leave_btn)

	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp_l)

	# 右 860：召唤 / 出装 双 tab（与单机右栏同尺寸）
	var right := _panel_block(UiKit.C_GOLD, 0.32, 14, 10.0)
	_select_right_block = right
	right.custom_minimum_size = Vector2(860, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)

	var rtab := HBoxContainer.new()
	rtab.custom_minimum_size = Vector2(0, 40)
	rtab.add_theme_constant_override("separation", 8)
	rv.add_child(rtab)
	_summ_tab_btn = _mk_tab_btn("召唤", UiKit.C_GOLD, true)
	_summ_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summ_tab_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	_summ_tab_btn.pressed.connect(_switch_right_tab.bind("召唤"))
	rtab.add_child(_summ_tab_btn)
	_build_tab_btn = _mk_tab_btn("出装", UiKit.C_TEAM0, false)
	_build_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_tab_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	_build_tab_btn.pressed.connect(_switch_right_tab.bind("出装"))
	rtab.add_child(_build_tab_btn)

	# —— 召唤面板：5 列召唤师卡 + 详情 ——
	_summ_panel = VBoxContainer.new()
	_summ_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summ_panel.add_theme_constant_override("separation", 6)
	rv.add_child(_summ_panel)
	var sscroll := ScrollContainer.new()
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summ_panel.add_child(sscroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.add_child(grid)
	_summ_btns.clear()
	for sname in HeroPickData.SUMMONERS:
		var sid: String = HeroPickData.SUMMONERS[sname]
		var sb := _mk_card_btn("", Color(0.36, 0.46, 0.66))
		sb.custom_minimum_size = Vector2(0, 84)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var srow := HBoxContainer.new()
		srow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		srow.add_theme_constant_override("separation", 4)
		srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		srow.add_child(SelectArt.SummonerGlyph.new(sname, 32))
		var slab := _mk_label(sname, _fs(UiKit.FS_SM), COL_TEXT)
		slab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		slab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		srow.add_child(slab)
		sb.add_child(srow)
		sb.pressed.connect(_pick_summ.bind(sname, sid))
		sb.mouse_entered.connect(_show_summ_tip.bind(sname, sid))
		sb.mouse_exited.connect(_hide_summ_tip)
		grid.add_child(sb)
		_summ_btns[sid] = sb
	_summ_detail = _mk_label("选中后显示冷却与说明", _fs(UiKit.FS_XS), COL_SUB)
	_summ_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summ_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_summ_detail.clip_text = true
	_summ_detail.custom_minimum_size = Vector2(0, 34)
	_summ_panel.add_child(_summ_detail)

	# —— 出装面板 ——
	_build_panel = VBoxContainer.new()
	_build_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_panel.add_theme_constant_override("separation", 6)
	_build_panel.visible = false
	rv.add_child(_build_panel)
	var bscroll2 := ScrollContainer.new()
	bscroll2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bscroll2.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bscroll2.custom_minimum_size = Vector2(0, 88)
	bscroll2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_panel.add_child(bscroll2)
	_build_scheme_row = GridContainer.new()
	_build_scheme_row.columns = 4
	_build_scheme_row.add_theme_constant_override("h_separation", 6)
	_build_scheme_row.add_theme_constant_override("v_separation", 6)
	_build_scheme_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bscroll2.add_child(_build_scheme_row)
	_build_cards = GridContainer.new()
	_build_cards.columns = 3
	_build_cards.add_theme_constant_override("h_separation", 6)
	_build_cards.add_theme_constant_override("v_separation", 6)
	_build_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_panel.add_child(_build_cards)

	var sp_r := Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp_r)

	# 右操作区（190 宽）：昵称 + 锁定 + 底栏状态（同单机 SelectSideRight）
	var side_right := VBoxContainer.new()
	_select_side_right = side_right
	side_right.custom_minimum_size = Vector2(190, 0)
	side_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side_right.add_theme_constant_override("separation", 8)
	bar.add_child(side_right)
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 4)
	name_box.add_child(_mk_label("我的昵称", _fs(UiKit.FS_XS), COL_DIM))
	var name_edit := LineEdit.new()
	_select_nick_edit = name_edit
	name_edit.max_length = 12
	name_edit.placeholder_text = "输入昵称"
	name_edit.text = _local_nickname()
	name_edit.custom_minimum_size = Vector2(190, 56)
	name_edit.add_theme_font_override("font", UiKit.font())
	name_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	name_edit.add_theme_color_override("font_color", COL_TEXT)
	name_edit.add_theme_color_override("font_placeholder_color", COL_DIM)
	name_edit.add_theme_stylebox_override("normal", UiKit.skin_chip(UiKit.C_GOLD, 0.85))
	name_edit.add_theme_stylebox_override("focus", UiKit.skin_chip(UiKit.C_GOLD, 1.0))
	name_edit.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() != "":
			NameStore.save_player_name(t.strip_edges()))
	name_box.add_child(name_edit)
	side_right.add_child(name_box)
	if _my_seat <= NetSession.MAX_SIDE_PLAYERS:
		_pick_confirm_btn = _mk_btn("√  锁定选择", UiKit.C_GOLD, true, Vector2(190, 100))
		_pick_confirm_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
		_pick_confirm_btn.pressed.connect(_on_pick_confirm)
		side_right.add_child(_pick_confirm_btn)
	else:
		var sp := _mk_label("旁观中 · 有人离场可上场", _fs(UiKit.FS_XS), COL_DIM)
		sp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_right.add_child(sp)
	_auto_start_lab = _mk_label("全员锁定后自动进入对局（0 人已锁）", _fs(UiKit.FS_XS), COL_SUB)
	_auto_start_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auto_start_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_right.add_child(_auto_start_lab)

	# —— 中央选英雄浮层（同单机 SelectPickLayer：未选英雄阶段只显示这一块）——
	var pick_layer := Control.new()
	_select_pick_layer = pick_layer
	pick_layer.name = "SelectPickLayer"
	pick_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pick_center := CenterContainer.new()
	pick_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pick_layer.add_child(pick_center)
	var pick_panel := PanelContainer.new()
	pick_panel.custom_minimum_size = Vector2(minf(1560.0, get_viewport().get_visible_rect().size.x * 0.88), 0)
	var pick_style := UiKit.skin_card(UiKit.C_TEAM0, false, 0.94)
	pick_style.content_margin_left = 18
	pick_style.content_margin_right = 18
	pick_style.content_margin_top = 12
	pick_style.content_margin_bottom = 14
	pick_panel.add_theme_stylebox_override("panel", pick_style)
	pick_center.add_child(pick_panel)
	var pick_v := VBoxContainer.new()
	pick_v.add_theme_constant_override("separation", 10)
	pick_panel.add_child(pick_v)
	var pick_head := HBoxContainer.new()
	pick_head.add_theme_constant_override("separation", 14)
	pick_v.add_child(pick_head)
	pick_head.add_child(_mk_label("选择英雄", _fs(UiKit.FS_LG), COL_GOLD))
	_select_pick_summary = _mk_label("请选择英雄", _fs(UiKit.FS_SM), COL_DIM)
	_select_pick_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select_pick_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pick_head.add_child(_select_pick_summary)
	_tab_row = HBoxContainer.new()
	_tab_row.custom_minimum_size = Vector2(0, 48)
	_tab_row.add_theme_constant_override("separation", 8)
	pick_v.add_child(_tab_row)
	_tab_btns.clear()
	var tabs: Array = [""]
	tabs.append_array(HeroPickData.ROLES_ORDER)
	for r in tabs:
		var active := str(r) == _tab_role
		var tb := _mk_tab_btn("全部" if str(r) == "" else str(r),
			UiKit.C_GOLD if active else UiKit.C_TEAM0, active)
		tb.custom_minimum_size = Vector2(112, 48)
		tb.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
		tb.pressed.connect(_select_tab.bind(str(r)))
		if _lane_locked and str(r) != _lane_role:
			tb.disabled = true
			tb.tooltip_text = "本机分路：%s · 只能选择%s" % [PlayerPrefs.get_lane(), _lane_role]
		_tab_row.add_child(tb)
		_tab_btns[str(r)] = tb
	var tab_gap := Control.new()
	tab_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.add_child(tab_gap)
	var strip_scroll := ScrollContainer.new()
	strip_scroll.custom_minimum_size = Vector2(0, 236)
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pick_v.add_child(strip_scroll)
	_hero_strip = HBoxContainer.new()
	_hero_strip.add_theme_constant_override("separation", 8)
	strip_scroll.add_child(_hero_strip)
	_rebuild_strip()
	_pick_status = _mk_label("", _fs(UiKit.FS_XS), COL_ERR)
	_pick_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick_v.add_child(_pick_status)
	_pick_summary = _mk_label("", _fs(UiKit.FS_XS), COL_GOLD)
	_pick_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pick_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick_v.add_child(_pick_summary)
	# 浮层挂到页面根（不占底部 HBox 高度，居中覆盖 3D 立绘）
	_page.add_child(pick_layer)

	_switch_right_tab("召唤")
	_update_select_stage()
	return bar


func _back_to_pick() -> void:
	if _sel_hero != "" and _pick_confirm_btn != null and _pick_confirm_btn.disabled == false:
		pass
	_pick_stage = true
	_update_select_stage()


## 与单机 _set_sel_stage 同义：选英雄阶段只显示中央浮层；选定后显示 3D 立绘 + 底部 344
func _update_select_stage() -> void:
	if _select_bar == null or _select_pick_layer == null:
		return
	var picking: bool = _pick_stage
	_select_pick_layer.visible = picking
	if _select_right_block != null:
		_select_right_block.visible = not picking
	if _select_side_left != null:
		_select_side_left.visible = not picking
	if _select_side_right != null:
		_select_side_right.visible = not picking
	_select_bar.custom_minimum_size = Vector2(0, 0 if picking else 344)


# 职业 tab 键
func _mk_tab_btn(text: String, accent: Color, active: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(132, 52)
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, active))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, active))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, true))
	b.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", accent, active))
	b.add_theme_color_override("font_color", Color.WHITE if active else COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", COL_DIM)
	return b


# 切职业 tab：重设 tab 样式并重建英雄卡条（"" = 全部；分路锁定时只允许本职责）
func _select_tab(role: String) -> void:
	if _lane_locked and role != _lane_role:
		return
	if role == _tab_role:
		return
	_tab_role = role
	for k in _tab_btns:
		var b: Button = _tab_btns[k]
		if is_instance_valid(b):
			var active: bool = str(k) == role
			var accent: Color = UiKit.C_GOLD if active else UiKit.C_TEAM0
			b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, active))
			b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, active))
			b.add_theme_color_override("font_color", Color.WHITE if active else COL_TEXT)
	_rebuild_strip()


# 按 _tab_role 重建底部英雄卡条
func _rebuild_strip() -> void:
	if _hero_strip == null:
		return
	for c in _hero_strip.get_children():
		_hero_strip.remove_child(c)
		c.queue_free()
	_hero_btns.clear()
	for role in HeroPickData.ROLES_ORDER:
		if _tab_role != "" and role != _tab_role:
			continue
		var rcol: Color = HeroPickData.ROLE_COLORS.get(role, COL_TEXT)
		for hname in HeroPickData.HERO_ROLE:
			if str(HeroPickData.HERO_ROLE[hname]) != role:
				continue
			var card := _mk_hero_card(hname, role, rcol)
			_hero_strip.add_child(card)
			_hero_btns[hname] = card
	_style_pick_cards()


# 180×112 英雄卡：英雄名 + 职责（他人已占/分路不符/非本机回合 置灰并标原因）
func _mk_hero_card(hname: String, role: String, accent: Color) -> Button:
	# 分路锁定时非本职责英雄置灰不可点（「分路不符」）
	var lane_bad: bool = _lane_locked and role != _lane_role
	var taken: bool = _draft_taken.has(hname)
	var waiting: bool = _draft_active() and not _draft_is_my_turn()
	var blocked: bool = _blocked_roles.has(role) or lane_bad or taken or waiting or _draft_done()
	var b := Button.new()
	b.custom_minimum_size = Vector2(180, 118)
	b.disabled = blocked
	b.add_theme_stylebox_override("normal", UiKit.skin_card(accent))
	b.add_theme_stylebox_override("hover", UiKit.skin_card(accent, true))
	b.add_theme_stylebox_override("pressed", UiKit.skin_card(accent.darkened(0.3), true))
	b.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", accent))
	b.pressed.connect(_pick_hero.bind(hname))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 1)
	v.add_child(SelectArt.Avatar.new(hname, accent, 34))
	var nm := _mk_label(hname, _fs(UiKit.FS_SM), COL_TEXT if not blocked else COL_DIM)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var tag := role
	if taken:
		tag = "已被占"
	elif lane_bad:
		tag = "分路不符"
	elif waiting:
		tag = "等待他人"
	elif _draft_done():
		tag = "已选定"
	elif _blocked_roles.has(role):
		tag = "已被占"
	var rl := _mk_label(tag, _fs(UiKit.FS_XS), COL_DIM if blocked else accent.lightened(0.35))
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rl)
	b.add_child(v)
	return b


# 英雄卡/召唤师卡选中态（皮肤卡片高亮）
func _style_pick_cards() -> void:
	for k in _hero_btns:
		var b: Button = _hero_btns[k]
		if is_instance_valid(b) and not b.disabled:
			var role := str(HeroPickData.HERO_ROLE.get(str(k), ""))
			var rcol: Color = HeroPickData.ROLE_COLORS.get(role, COL_TEXT)
			b.add_theme_stylebox_override("normal", UiKit.skin_card(rcol, str(k) == _sel_hero))
	for k in _summ_btns:
		var sb: Button = _summ_btns[k]
		if is_instance_valid(sb):
			sb.add_theme_stylebox_override("normal",
				UiKit.skin_card(Color(0.36, 0.46, 0.66), str(k) == _sel_sid))


# 小 chip（覆盖层技能/状态行）
func _mk_chip(text: String, accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin_chip(accent, 0.55, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lab := _mk_label(text, _fs(UiKit.FS_XS), COL_TEXT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lab)
	return p


# 技能类型中文（与单机选人一致）
func _skill_kind(t: int) -> String:
	match t:
		0: return "指向"
		1: return "范围"
		2: return "增益"
		3: return "线性"
		4: return "位移"
		5: return "多段"
		6: return "护盾"
	return "通用"


func _refresh_select(state: Dictionary, data: Dictionary) -> void:
	if _pick_summary != null:
		var mine: Dictionary = state.get("picks", {}).get(_self_peer(), {})
		if not mine.is_empty():
			_pick_summary.text = "你已锁定：%s · %s + %s（点其它卡片可改选，改后需再点锁定）" % [str(mine.role), str(mine.hero), _summoner_name(str(mine.summoner))]
			_pick_summary.add_theme_color_override("font_color", COL_OK)
		elif _sel_hero != "" and _sel_sid != "":
			_pick_summary.text = "待锁定：%s · %s + %s" % [str(HeroPickData.HERO_ROLE[_sel_hero]), _sel_hero, _sel_summ]
			_pick_summary.add_theme_color_override("font_color", COL_GOLD)
		else:
			_pick_summary.text = "请先选英雄与召唤师技能，再点「锁定选择」"
			_pick_summary.add_theme_color_override("font_color", COL_DIM)
		# 顺序选人：非本机回合/已结束覆盖为排队提示
		if _draft_active() and not _draft_is_my_turn():
			_pick_summary.text = "等待 %s · 剩余 %ds" % [_draft_turn_label(), int(ceil(maxf(0.0, _draft_left)))]
			_pick_summary.add_theme_color_override("font_color", COL_SUB)
		elif _draft_done():
			_pick_summary.text = "阵容已定 · 即将自动进入对局"
			_pick_summary.add_theme_color_override("font_color", COL_OK)
	if _pick_confirm_btn != null:
		_pick_confirm_btn.disabled = not _pick_ready()
	if _auto_start_lab != null:
		var locked_n := 0
		for s in data["seats"]:
			if str(s.hero) != "":
				locked_n += 1
		var total := maxi((data["seats"] as Array).size(), 1)
		if _auto_start_done:
			_auto_start_lab.text = "全员已就绪 · 正在进入对局…"
			_auto_start_lab.add_theme_color_override("font_color", COL_OK)
		elif locked_n >= total:
			_auto_start_lab.text = "全员已就绪 · 正在进入对局…"
			_auto_start_lab.add_theme_color_override("font_color", COL_OK)
		else:
			_auto_start_lab.text = "全员锁定后自动进入对局（%d/%d 已锁）" % [locked_n, total]
			_auto_start_lab.add_theme_color_override("font_color", COL_SUB)


func _pick_hero(hname: String) -> void:
	if not HeroPickData.HERO_ROLE.has(hname):
		return
	var role := str(HeroPickData.HERO_ROLE[hname])
	if _lane_locked and role != _lane_role:
		if _pick_status != null:
			_pick_status.text = "本机分路：%s · 只能选择%s" % [PlayerPrefs.get_lane(), _lane_role]
			_pick_status.add_theme_color_override("font_color", COL_ERR)
		return
	# 顺序选人：非本机回合全部不可选；展示阵容/他人已选的英雄不可再选
	if _draft_active() and not _draft_is_my_turn():
		_show_pick_error("还没轮到你 · 等待 %s" % _draft_turn_label())
		return
	if _draft_done():
		return
	if _draft_taken.has(hname):
		_show_pick_error("%s 已被选走，请另选" % hname)
		return
	if _blocked_roles.has(role):
		return
	_sel_hero = hname
	_pick_stage = false
	if not _summ_manual:
		_apply_recommended_summoner(hname)
	_sync_pick_ui()


# 未手动改过召唤师时跟随英雄推荐（李白/孙悟空 = 惩击，其余 = 闪现）
func _apply_recommended_summoner(hname: String) -> void:
	var sid := HeroPickData.recommended_summoner(hname)
	if sid == "" or not _summ_btns.has(sid):
		return
	_sel_sid = sid
	_sel_summ = _summoner_name(sid)


func _pick_summ(sname: String, sid: String) -> void:
	_sel_summ = sname
	_sel_sid = sid
	_summ_manual = true
	_refresh_summ_detail()
	_sync_pick_ui()


# 召唤面板详情行：冷却 / 类型 / 距离（与单机选人页的选中详情同口径）
func _refresh_summ_detail() -> void:
	if _summ_detail == null:
		return
	if _sel_sid == "":
		_summ_detail.text = "选中后显示冷却与说明"
		return
	var sk: Skill = SkillDatabase.get_skill(_sel_sid)
	if sk == null:
		_summ_detail.text = _sel_summ
		return
	var t := ""
	match int(sk.type):
		0: t = "指向"
		1: t = "范围"
		2: t = "增益"
		3: t = "线性"
		4: t = "位移"
		5: t = "多段"
		6: t = "护盾"
		_: t = "技能"
	var txt := "%s · %s · 冷却 %.0fs" % [_sel_summ, t, float(sk.cooldown)]
	if sk.cast_range > 0.0:
		txt += " · 距离 %.0fm" % float(sk.cast_range)
	_summ_detail.text = txt


# 召唤师卡悬停浮层：技能名 + 冷却/类型/距离/法力 + 推荐·已选标记（Skill 无描述字段，不编造）
func _show_summ_tip(sname: String, sid: String) -> void:
	var card: Button = _summ_btns.get(sid)
	if card == null or not is_instance_valid(card):
		return
	if _summ_tip != null and is_instance_valid(_summ_tip):
		_summ_tip.queue_free()
	_summ_tip = PanelContainer.new()
	_summ_tip.custom_minimum_size = Vector2(380, 0)
	_summ_tip.z_index = 200
	_summ_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summ_tip.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD, true, 0.94))
	add_child(_summ_tip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summ_tip.add_child(v)

	var nm := _mk_label(sname, _fs(UiKit.FS_LG), COL_GOLD)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var sk: Skill = SkillDatabase.get_skill(sid)
	if sk != null:
		var dist := "—" if sk.cast_range <= 0.0 else "%d m" % int(round(sk.cast_range))
		var meta := _mk_label("冷却 %ds · %s · 距离 %s" % [int(round(sk.cooldown)), _skill_kind(int(sk.type)), dist],
			_fs(UiKit.FS_SM), COL_SUB)
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(meta)
		if sk.mana_cost > 0:
			var mp := _mk_label("法力 %d" % sk.mana_cost, _fs(UiKit.FS_SM), COL_SUB)
			mp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(mp)

	var tag := ""
	if _sel_sid == sid:
		tag = "已选 · 当前"
	elif _sel_hero != "" and HeroPickData.recommended_summoner(_sel_hero) == sid:
		tag = "推荐 · %s" % _sel_hero
	if tag != "":
		var tg := _mk_label(tag, _fs(UiKit.FS_XS), UiKit.C_HEAL)
		tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tg)

	_summ_tip.reset_size()
	var vp := get_viewport_rect().size
	var pos := card.global_position + Vector2(16, 16)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - _summ_tip.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - _summ_tip.size.y - 8.0))
	_summ_tip.global_position = pos
	_summ_tip.visible = true


func _hide_summ_tip() -> void:
	if _summ_tip != null and is_instance_valid(_summ_tip):
		_summ_tip.visible = false


func _sync_pick_ui() -> void:
	if _pick_confirm_btn != null:
		_pick_confirm_btn.disabled = not _pick_ready()
	if _pick_summary != null and _sel_hero != "" and _sel_sid != "":
		_pick_summary.text = "待锁定：%s · %s + %s" % [str(HeroPickData.HERO_ROLE[_sel_hero]), _sel_hero, _sel_summ]
		_pick_summary.add_theme_color_override("font_color", COL_GOLD)
	_refresh_preview()


# 中栏立绘/覆盖层：随本机草稿实时刷新（未选 = 提示胶囊，已选 = 3D 模型 + 职责色 + chip 行）
func _refresh_preview() -> void:
	if _preview_name == null:
		return
	if _preview_nick != null:
		_preview_nick.text = "玩家 · %s" % _local_nickname()
	var role := ""
	var rcol: Color = UiKit.C_TEAM0
	if _sel_hero != "":
		role = str(HeroPickData.HERO_ROLE.get(_sel_hero, ""))
		rcol = HeroPickData.ROLE_COLORS.get(role, UiKit.C_TEAM0)
		_preview_name.text = _sel_hero
		if _prev != null and is_instance_valid(_prev):
			_prev.set_hero(_sel_hero)
			_prev.set_accent(rcol)
	else:
		_preview_name.text = "请选择英雄"
	_preview_role.text = ("定位 · " + role) if role != "" else "定位 —"
	_preview_role.add_theme_color_override("font_color", rcol.lightened(0.2))
	if _prev_role_chip != null:
		_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(rcol, 0.55, 12))
	var rec_sid := HeroPickData.recommended_summoner(_sel_hero) if _sel_hero != "" else ""
	var rec_tag := "（推荐）" if (rec_sid != "" and not _summ_manual) else ""
	_preview_summ.text = "召唤师 · " + (_sel_summ if _sel_summ != "" else "未选择") + rec_tag
	if _preview_summ_icon != null:
		_preview_summ_icon.set_summoner(_sel_summ)
	# 技能 chip 行：召唤师技能的类型/冷却/法力 + 可锁定状态
	if _prev_chip_row != null:
		for c in _prev_chip_row.get_children():
			_prev_chip_row.remove_child(c)
			c.queue_free()
		var sk: Skill = SkillDatabase.get_skill(_sel_sid) if _sel_sid != "" else null
		if sk != null:
			_prev_chip_row.add_child(_mk_chip("类型 " + _skill_kind(int(sk.type)), UiKit.C_TEAM0))
			_prev_chip_row.add_child(_mk_chip("冷却 %ds" % int(round(sk.cooldown)), UiKit.C_GOLD))
			if sk.mana_cost > 0:
				_prev_chip_row.add_child(_mk_chip("法力 %d" % int(sk.mana_cost), UiKit.C_AP))
		_prev_chip_row.add_child(_mk_chip(
			"可锁定" if (_sel_hero != "" and _sel_sid != "") else "先选英雄+召唤师",
			UiKit.C_HEAL if (_sel_hero != "" and _sel_sid != "") else UiKit.C_DANGER))
	_refresh_skill_chips()
	_refresh_build_row()
	if _preview_tip != null:
		_preview_tip.text = ("分路：%s · 只能选择%s英雄 · 锁后仍可改选再锁" % [PlayerPrefs.get_lane(), _lane_role]) if _lane_locked else "点英雄卡选英雄 → 右侧选召唤师 → 点锁定；锁后仍可改选再锁"
	_style_pick_cards()


# —— 英雄技能预览 + 推荐出装（对齐单机选人页）——

# 英雄配置（技能 id / 推荐召唤师）懒取 BattleManager.hero_configs，大厅不重复维护一份数据
func _hero_cfg(hero: String) -> Dictionary:
	if _hero_cfg_cache.is_empty():
		var bm := BattleManager.new()
		if bm != null:
			_hero_cfg_cache = bm.hero_configs
			bm.free()
	return _hero_cfg_cache.get(hero, {})

# 中栏技能 chip：3 个英雄技能（图标 + 名称 + 类型/冷却/法力），悬停看简介
func _refresh_skill_chips() -> void:
	if _prev_skill_row == null:
		return
	for c in _prev_skill_row.get_children():
		_prev_skill_row.remove_child(c)
		c.queue_free()
	if _sel_hero == "":
		return
	var skills: Array = _hero_cfg(_sel_hero).get("skills", [])
	for i in skills.size():
		var sid := str(skills[i])
		var sk: Skill = SkillDatabase.get_skill(sid)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.55, 12))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(SelectArt.SkillGlyph.new(_sel_hero, sk, i, 38))
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := _mk_label("%d  %s" % [i + 1, str(sk.skill_name) if sk != null else sid], _fs(UiKit.FS_SM), COL_TEXT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(nm)
		var meta := "技能" if sk == null else "%s · 冷却 %ds" % [_skill_kind(int(sk.type)), int(round(sk.cooldown))]
		var ml := _mk_label(meta, _fs(UiKit.FS_XS), COL_SUB)
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(ml)
		row.add_child(info)
		chip.add_child(row)
		chip.mouse_entered.connect(_show_skill_tip.bind(chip, sk, i))
		chip.mouse_exited.connect(_hide_skill_tip)
		_prev_skill_row.add_child(chip)

# 技能 chip 悬停浮层：类型/冷却/法力/距离 + 伤害·范围·持续·控制简介
func _show_skill_tip(card: Control, sk: Skill, idx: int) -> void:
	if _prev_skill_tip != null and is_instance_valid(_prev_skill_tip):
		_prev_skill_tip.queue_free()
	_prev_skill_tip = PanelContainer.new()
	_prev_skill_tip.custom_minimum_size = Vector2(360, 0)
	_prev_skill_tip.z_index = 200
	_prev_skill_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev_skill_tip.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_TEAM0, true, 0.94))
	add_child(_prev_skill_tip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev_skill_tip.add_child(v)
	var nm_text := ("%d  %s" % [idx + 1, str(sk.skill_name)]) if sk != null else ("技能 %d" % (idx + 1))
	var nm := _mk_label(nm_text, _fs(UiKit.FS_LG), COL_GOLD)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)
	if sk != null:
		var meta := "类型：%s · 冷却 %.1fs" % [_skill_kind(int(sk.type)), sk.cooldown]
		if sk.mana_cost > 0:
			meta += " · 法力 %d" % sk.mana_cost
		if sk.cast_range > 0.0:
			meta += " · 距离 %.0fm" % sk.cast_range
		var ml := _mk_label(meta, _fs(UiKit.FS_SM), COL_SUB)
		ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ml)
		var desc := _skill_desc(sk)
		if desc != "":
			var dl := _mk_label(desc, _fs(UiKit.FS_SM), COL_TEXT)
			dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(dl)
	_prev_skill_tip.reset_size()
	var vp := get_viewport_rect().size
	var pos := card.global_position + Vector2(16, 16)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - _prev_skill_tip.size.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - _prev_skill_tip.size.y - 8.0))
	_prev_skill_tip.global_position = pos

func _hide_skill_tip() -> void:
	if _prev_skill_tip != null and is_instance_valid(_prev_skill_tip):
		_prev_skill_tip.visible = false

# 技能简介：仅汇总 Skill 已有字段（伤害/范围/持续/护盾/控制），不编造文案
func _skill_desc(sk: Skill) -> String:
	var parts: Array = []
	var dmg := sk.damage + sk.phy_damage + sk.mag_damage
	if dmg > 0.0: parts.append("伤害 %d" % int(round(dmg)))
	if sk.radius > 0.0: parts.append("范围 %.0fm" % sk.radius)
	if sk.duration > 0.0: parts.append("持续 %.1fs" % sk.duration)
	if sk.shield_amount > 0.0: parts.append("护盾 %d" % int(round(sk.shield_amount)))
	if sk.applies_stun > 0.0: parts.append("眩晕 %.1fs" % sk.applies_stun)
	if sk.applies_knockup > 0.0: parts.append("击飞 %.1fs" % sk.applies_knockup)
	if sk.applies_slow > 0.0: parts.append("减速 %d%%" % int(round(sk.applies_slow * 100.0)))
	return " · ".join(parts)

# 出装方案按钮行：内置 3 套推荐 + 玩家已存方案 + 恢复推荐（点击写本局推荐出装）
# 右栏页签：召唤 / 出装（与单机选人页同款）
func _switch_right_tab(tab: String) -> void:
	_right_tab = tab
	if _summ_panel != null:
		_summ_panel.visible = tab == "召唤"
	if _build_panel != null:
		_build_panel.visible = tab == "出装"
	if _summ_tab_btn != null:
		_summ_tab_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, tab == "召唤"))
		_summ_tab_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, tab == "召唤"))
	if _build_tab_btn != null:
		_build_tab_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, tab == "出装"))
		_build_tab_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, tab == "出装"))
	if tab == "出装":
		_refresh_build_row()


func _refresh_build_row() -> void:
	if _build_scheme_row == null:
		return
	for c in _build_scheme_row.get_children():
		_build_scheme_row.remove_child(c)
		c.queue_free()
	if _sel_hero == "":
		return
	if _build_hero != _sel_hero:
		_load_build(_sel_hero)
	var presets := _preset_builds(_sel_hero)
	for i in presets.size():
		var ids := _clean_build_items(presets[i])
		_build_scheme_row.add_child(_mk_build_btn("推荐方案%d" % (i + 1), ids, _build_items_tooltip(ids), UiKit.C_TEAM0))
	var builds: Array = HeroBuildStore.get_builds(_sel_hero)
	for i in mini(builds.size(), 6):
		var ids := _clean_build_items((builds[i] as Dictionary).get("items", []))
		_build_scheme_row.add_child(_mk_build_btn(str((builds[i] as Dictionary).get("name", "方案")), ids,
			_build_items_tooltip(ids), UiKit.C_GOLD))
	_build_scheme_row.add_child(_mk_build_btn("恢复推荐", _preset_build(_sel_hero, 0), "回到内置推荐方案1", UiKit.C_GOLD))
	_refresh_build_cards()


# 出装面板下半：当前方案的 6 件装备卡（图标 + 名称 + 价格 + 效果一行，悬浮看详情）
func _refresh_build_cards() -> void:
	if _build_cards == null:
		return
	for c in _build_cards.get_children():
		_build_cards.remove_child(c)
		c.queue_free()
	if _sel_hero == "":
		return
	for i in range(6):
		var id := str(_build_ids[i]) if i < _build_ids.size() else ""
		_build_cards.add_child(_mk_item_card(i, id))


# 出装卡调序（写回本局推荐 override，与单机选人一致）
func _move_build_item(idx: int, dir: int) -> void:
	var j := idx + dir
	if idx < 0 or j < 0 or idx >= _build_ids.size() or j >= _build_ids.size():
		return
	var tmp = _build_ids[idx]
	_build_ids[idx] = _build_ids[j]
	_build_ids[j] = tmp
	if _sel_hero != "":
		ItemDatabase.set_recommended_override(_sel_hero, _build_ids)
	_refresh_build_row()


func _mk_item_card(idx: int, item_id: String) -> Control:
	var it: Dictionary = ItemDatabase.get_item(item_id) if item_id != "" else {}
	var tier := int(it.get("tier", 1))
	var nm := str(it.get("name", "空槽" if item_id == "" else item_id))
	var cost := int(it.get("cost", 0))
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_PANEL_EDGE, 0.8, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	card.add_child(h)
	if item_id != "":
		h.add_child(SelectArt.ItemIcon.new(nm, tier, 64))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var nl := _mk_label("%d. %s" % [idx + 1, nm], _fs(UiKit.FS_MD), COL_TEXT if item_id != "" else COL_DIM)
	nl.clip_text = true
	nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nl)
	if item_id != "":
		v.add_child(_mk_label("%d 金" % cost, _fs(UiKit.FS_SM), COL_GOLD))
		var eff := UiKit.item_effect(it)
		if eff != "":
			var el := _mk_label(eff, _fs(UiKit.FS_XS), COL_SUB)
			el.clip_text = true
			el.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			v.add_child(el)
		var up := _mk_btn("↑", UiKit.C_TEAM0, false, Vector2(34, 24))
		up.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
		up.disabled = idx <= 0
		up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		up.pressed.connect(_move_build_item.bind(idx, -1))
		h.add_child(up)
		var down := _mk_btn("↓", UiKit.C_TEAM0, false, Vector2(34, 24))
		down.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
		down.disabled = idx >= mini(5, _build_ids.size() - 1)
		down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		down.pressed.connect(_move_build_item.bind(idx, 1))
		h.add_child(down)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.mouse_entered.connect(_show_item_tip.bind(item_id, card))
		card.mouse_exited.connect(_hide_item_tip)
	return card


# 装备悬浮详情（名称 / 品质 / 价格 / 属性 / 被动 / 合成）
func _show_item_tip(item_id: String, ctrl: Control) -> void:
	_hide_item_tip()
	var it: Dictionary = ItemDatabase.get_item(item_id)
	if it.is_empty() or ctrl == null:
		return
	var tier := int(it.get("tier", 1))
	var qcol: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)]
	var tip := PanelContainer.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 300
	tip.custom_minimum_size = Vector2(_fs(420), 0)
	tip.add_theme_stylebox_override("panel", UiKit.skin_card(qcol, true, 0.97))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _fs(3))
	tip.add_child(v)
	v.add_child(_mk_label(str(it.get("name", item_id)), _fs(UiKit.FS_LG), qcol.lightened(0.25)))
	var cls_map := {"attack": "物理", "magic": "法术", "defense": "防御", "boots": "鞋子",
		"jungle": "打野", "support": "游走", "survival": "保命", "attack_speed": "攻速"}
	var cls := str(it.get("class", ""))
	var meta := "T%d · %d 金" % [tier, int(it.get("cost", 0))]
	if cls != "":
		meta += " · " + str(cls_map.get(cls, cls))
	v.add_child(_mk_label(meta, _fs(UiKit.FS_SM), COL_SUB))
	var stat_names := {"attack": "攻击", "magic_attack": "法强", "health": "生命", "armor": "物防",
		"magic_resist": "法防", "attack_speed": "攻速%", "crit_chance": "暴击%", "cooldown": "冷缩%",
		"speed": "移速", "lifesteal": "吸血%", "mana": "蓝量", "hp_regen": "回血",
		"armor_pen_percent": "物穿%", "magic_pen": "法穿"}
	var parts: Array = []
	for k in stat_names:
		var val := int(it.get(str(k), 0))
		if val != 0:
			parts.append("%s+%d" % [str(stat_names[k]), val])
	if not parts.is_empty():
		var sl := _mk_label("属性：" + " · ".join(parts), _fs(UiKit.FS_SM), COL_TEXT)
		v.add_child(sl)
	var passive := str(it.get("passive", ""))
	if passive != "":
		var pl := _mk_label("被动：" + passive, _fs(UiKit.FS_SM), COL_GOLD)
		v.add_child(pl)
	var reqs: Array = it.get("requires", [])
	if not reqs.is_empty():
		var names: Array = []
		for rid in reqs:
			names.append(str(ItemDatabase.get_item(str(rid)).get("name", rid)))
		v.add_child(_mk_label("合成：" + " + ".join(names), _fs(UiKit.FS_SM), COL_SUB))
	add_child(tip)
	tip.size = tip.get_combined_minimum_size()
	var r: Rect2 = ctrl.get_global_rect()
	var vp := get_viewport_rect().size
	var pos := Vector2(r.position.x, r.end.y + _fs(8))
	if pos.y + tip.size.y > vp.y - _fs(8):
		pos.y = r.position.y - tip.size.y - _fs(8)
	pos.x = clampf(pos.x, _fs(8), maxf(_fs(8), vp.x - tip.size.x - _fs(8)))
	tip.global_position = pos
	_item_tip = tip


func _hide_item_tip() -> void:
	if _item_tip != null and is_instance_valid(_item_tip):
		_item_tip.queue_free()
	_item_tip = null

func _mk_build_btn(text: String, ids: Array, tip: String, accent: Color) -> Button:
	var active: bool = ids == _build_ids
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(180, 40)
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, active))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, active))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, true))
	b.add_theme_color_override("font_color", Color.WHITE if active else COL_TEXT)
	b.pressed.connect(_pick_build.bind(ids))
	return b

# 点击方案：写成该英雄的本局推荐出装（对局内 UI_Manager 按 override 排序推荐/快买）
func _pick_build(ids: Array) -> void:
	if _sel_hero == "":
		return
	_build_ids = _clean_build_items(ids)
	ItemDatabase.set_recommended_override(_sel_hero, _build_ids)
	_refresh_build_row()

# 切英雄时载入出装：本局 override > 已存方案1 > 内置推荐方案1（与单机选人一致）
func _load_build(hero: String) -> void:
	_build_hero = hero
	var ov: Array = ItemDatabase.get_recommended_override(hero)
	if not ov.is_empty():
		_build_ids = _clean_build_items(ov)
	elif not HeroBuildStore.get_builds(hero).is_empty():
		_build_ids = _clean_build_items(HeroBuildStore.get_builds(hero)[0].get("items", []))
	else:
		_build_ids = _preset_build(hero, 0)

func _preset_builds(hero: String) -> Array:
	var vs: Array = ItemDatabase.get_recommended_variants(hero)
	if vs.is_empty():
		vs = ItemDatabase.get_recommended_variants(str(_hero_cfg(hero).get("role", "战士")))
	return vs

func _preset_build(hero: String, idx: int) -> Array:
	var vs := _preset_builds(hero)
	if vs.is_empty():
		return []
	return _clean_build_items(vs[clampi(idx, 0, vs.size() - 1)])

func _clean_build_items(src: Array) -> Array:
	var out: Array = []
	for it in src:
		var id := str(it)
		if id != "" and not out.has(id) and not ItemDatabase.get_item(id).is_empty():
			out.append(id)
	return out.slice(0, 6)

# 方案按钮 tooltip：列出 6 件装备名
func _build_items_tooltip(items: Array) -> String:
	var names: PackedStringArray = []
	for id in items:
		var it: Dictionary = ItemDatabase.get_item(str(id))
		names.append(str(it.get("name", id)))
	return " · ".join(names)

func _on_pick_confirm() -> void:
	if _sel_hero == "" or _sel_sid == "":
		return
	# 分路锁定时锁定前再校验一次职责
	if _lane_locked and str(HeroPickData.HERO_ROLE.get(_sel_hero, "")) != _lane_role:
		_show_pick_error("本机分路：%s · 只能锁定%s英雄" % [PlayerPrefs.get_lane(), _lane_role])
		return
	# 顺序选人：非本机回合不可锁定
	if _draft_active() and not _draft_is_my_turn():
		_show_pick_error("还没轮到你选人 · 等待 %s" % _draft_turn_label())
		return
	if _draft_done():
		return
	if _pick_status != null:
		_pick_status.text = ""
	if _role == 0:
		if not NetSession.send_pick(_sel_hero, _sel_sid):
			_show_pick_error("该职责已被他人选择或本方席位已满，请另选英雄")
	else:
		NetSession.send_pick(_sel_hero, _sel_sid)
		if _pick_status != null:
			_pick_status.text = "已提交，等待房主确认…"
			_pick_status.add_theme_color_override("font_color", COL_SUB)


func _show_pick_error(msg: String) -> void:
	if _pick_status != null:
		_pick_status.text = msg
		_pick_status.add_theme_color_override("font_color", COL_ERR)


func _on_pick_rejected(msg: String) -> void:
	# guest 才可能收到主机拒绝（职责被占/席位已满）；清空草稿提示换选
	if _ui != UIState.SELECT:
		return
	_show_pick_error(msg)


# 卡片按钮：UiKit.skin_card = 深底 + 职责色描边，hover 加同色发光
func _mk_card_btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(176, 62)
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b.add_theme_stylebox_override("normal", UiKit.skin_card(accent))
	b.add_theme_stylebox_override("hover", UiKit.skin_card(accent, true))
	b.add_theme_stylebox_override("pressed", UiKit.skin_card(accent.darkened(0.3), true))
	b.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", accent))
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.42, 0.46, 0.54))
	return b


# ---------- 信号回调 ----------

func _on_lobby_state(state: Dictionary) -> void:
	if NetSession.cli_mode:
		return
	_last_state = state
	var ph := int(state.get("phase", NetSession.Phase.LOBBY))
	_set_menu_enabled(true)
	if _role == -1:
		_role = 1 if NetSession.mode == NetSession.Mode.CLIENT else 0
	if ph == NetSession.Phase.SELECT:
		# 顺序选人：host 以自己的推进为准，guest 采纳主机广播（无 draft 字段 = 旧流程同时选人）
		if _role != 0:
			_apply_draft_state(state.get("draft", {}))
		# 大厅选人阶段：host 与每个 client 同屏选人。
		# 每次状态事件都整体重建面板（他人锁定改灰 / 掉线腾出职责 / 旁观升席都即时生效；
		# _adopt_self_choice 会保留本机未锁草稿，锁定态则采纳权威值）。
		_show_select(state)
		return
	if ph == NetSession.Phase.BATTLE:
		# 房主已开局（或加入时主机已在打）→ host 开战局、client 接管对战
		if _role == 0:
			_route_battle()
		else:
			_route_client()
		return
	# LOBBY：确认身份后进房间并刷新名单
	if _ui == UIState.MENU:
		_show_room()
		_refresh_room(state)
	else:
		_refresh_room(state)


func _on_connect_failed(msg: String) -> void:
	_set_menu_enabled(true)
	if _ui == UIState.MENU:
		_status_text("连接失败：" + msg, COL_ERR)


func _on_host_gone() -> void:
	if NetSession.cli_mode:
		return
	_auto_start_done = false
	_auto_start_wait = -1.0
	NetSession.disconnect_network()
	if _ui != UIState.MENU:
		_show_menu()
		_status_text("与主机断开连接", COL_ERR)


# ---------- 路由 ----------

func _self_name() -> String:
	if NetSession.players.has(1):
		return str(NetSession.players[1].get("name", "房主"))
	return "主机" if NetSession.mode == NetSession.Mode.HOST else "玩家"


func _self_peer() -> int:
	# client 场景里玩家自己即多人连接（net_id 视角为 peer id；单机 host 是 1）
	if NetSession.mode == NetSession.Mode.CLIENT:
		return multiplayer.get_unique_id() if multiplayer != null else 2
	return 1


func _route_battle() -> void:
	_show_loading_then("res://scenes/battle.tscn")


func _route_client() -> void:
	_show_loading_then("res://scenes/net_client.tscn")
