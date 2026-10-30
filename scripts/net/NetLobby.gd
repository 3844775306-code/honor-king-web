# NetLobby.gd — 匹配大厅（单机 / 建房 / 加入 / 大厅选人）
#
# 界面态：
#   MENU    标题 + 单机/建房/加入（IP:端口 可编辑）
#   ROOM    在线名单；host 有「开始选人」，guest 等房主发起
#   SELECT  大厅选人：host 与每个 client 各自窗口选「职责→英雄→召唤师」并锁定；
#           前 5 席全员锁齐后 host 的「开始对局」才点亮（严格一人一职，空位 AI 补）
#
# 开局流程：host 点「开始选人」→ NetSession.begin_pick()（phase=SELECT）
#   → host 点「开始对局」（全员锁齐才允许）→ NetSession.start_match()（phase=BATTLE）
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
const BTN_W := 640.0
const BTN_H := 96.0
const PAGE_PAD_X := 64          # 页面左右内边距
const PAGE_PAD_Y := 40          # 页面上下内边距

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
var _host_go_btn: Button = null
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
var _diff_btn: Button = null           # 菜单页「AI 难度」循环按钮
var _lane_role := ""                   # 选人页本机分路对应职责
var _lane_locked := false              # 选人页是否强制锁该职责（被队友占用则不锁）
var _preview_name: Label = null    # 中栏英雄预览：名字
var _preview_role: Label = null    # 中栏英雄预览：职责
var _preview_summ: Label = null    # 中栏英雄预览：召唤师技能
var _preview_summ_icon = null      # 中栏英雄预览：召唤师技能图标


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
	_host_go_btn = null
	_prev = null
	_stage_title = null
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
	_set_page_pad(int(PAGE_PAD_X), int(PAGE_PAD_Y))
	_ui = UIState.MENU
	_role = -1
	_connecting = false

	# 两栏铺满：左 42% 品牌区 / 右 58% 菜单按钮列
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 48)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack.add_child(root)

	# —— 左栏：品牌区 ——
	var brand := _panel_block(UiKit.C_GOLD, 0.45)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.size_flags_stretch_ratio = 42.0
	brand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(brand)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 20)
	brand.add_child(bcol)

	var title := _mk_label("荣耀王者", int(_fs(UiKit.FS_HUGE) * 2.0), COL_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bcol.add_child(title)

	var sub := _mk_label("HONORKING · 5v5 联机版（主机权威）", _fs(UiKit.FS_LG), COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bcol.add_child(sub)

	# 金色分隔线
	var line := ColorRect.new()
	line.color = Color(UiKit.C_GOLD.r, UiKit.C_GOLD.g, UiKit.C_GOLD.b, 0.75)
	line.custom_minimum_size = Vector2(280, 4)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bcol.add_child(line)

	var desc := _mk_label("单机人机对局 / 自建房间 / 局域网加入；开局前同屏选英雄与召唤师技能。", _fs(UiKit.FS_MD), COL_TEXT)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bcol.add_child(desc)

	# 中段留白
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bcol.add_child(spacer)

	var ver := _mk_label("HonorKing · 主机权威联机（M0~M2）", _fs(UiKit.FS_SM), COL_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bcol.add_child(ver)

	# —— 右栏：菜单按钮列（垂直居中） ——
	var right := _panel_block(UiKit.C_TEAM0, 0.40)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 58.0
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	var mcol := VBoxContainer.new()
	mcol.add_theme_constant_override("separation", 20)
	mcol.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(mcol)

	var b_single := _mk_btn("🎮  单机游戏（本地人机对局）", UiKit.C_GOLD, true)
	b_single.pressed.connect(_start_singleplayer)
	mcol.add_child(b_single)

	# 分路选择：一行 5 芯片（写 PlayerPrefs，房间页与联机选人页沿用）
	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 4)
	lane_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_child(lane_row)
	var lane_cap := _mk_label("分路", _fs(UiKit.FS_SM), COL_GOLD)
	lane_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lane_row.add_child(lane_cap)
	_lane_btns.clear()
	for lane in HeroPickData.LANES:
		var lb := _mk_lane_btn(str(lane))
		lane_row.add_child(lb)
		_lane_btns[str(lane)] = lb
	_lane_sub_lab = _mk_label("", _fs(UiKit.FS_XS), COL_DIM)
	_lane_sub_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mcol.add_child(_lane_sub_lab)
	_style_lane_btns()

	# AI 难度：单行循环按钮（写 PlayerPrefs；进对局时 BattleManager 应用到 AiConfig，联机为主机生效）
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 12)
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_child(diff_row)
	var diff_cap := _mk_label("AI难度", _fs(UiKit.FS_SM), COL_GOLD)
	diff_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	diff_row.add_child(diff_cap)
	_diff_btn = _mk_btn("", UiKit.C_GOLD, false, Vector2(520, 48))
	_diff_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	_diff_btn.pressed.connect(_cycle_difficulty)
	diff_row.add_child(_diff_btn)
	_refresh_difficulty_btn()

	var b_host := _mk_btn("🏠  创建房间（本机当主机，等他人加入）", UiKit.C_TEAM0)
	b_host.pressed.connect(_create_host)
	mcol.add_child(b_host)

	var b_join := _mk_btn("🌐  加入房间（连接他人主机）", UiKit.C_TEAM0)
	b_join.pressed.connect(_join_room)
	mcol.add_child(b_join)

	var b_loadout := _mk_btn("⚙  备战 · 出装方案", UiKit.C_TEAM0)
	b_loadout.pressed.connect(_open_loadout)
	mcol.add_child(b_loadout)
	_menu_btns = [b_single, b_host, b_join, b_loadout]

	# 连接参数行
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_child(row)

	var lab_ip := _mk_label("主机IP", _fs(UiKit.FS_MD), COL_TEXT)
	lab_ip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(lab_ip)

	var ip_edit := LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.custom_minimum_size = Vector2(240, 54)
	ip_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	ip_edit.placeholder_text = "局域网 IP"
	row.add_child(ip_edit)

	var lab_port := _mk_label("端口", _fs(UiKit.FS_MD), COL_TEXT)
	row.add_child(lab_port)

	var port_edit := LineEdit.new()
	port_edit.text = "7000"
	port_edit.custom_minimum_size = Vector2(120, 54)
	port_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	port_edit.placeholder_text = "端口"
	row.add_child(port_edit)
	_ip_edit = ip_edit
	_port_edit = port_edit

	_status = _mk_label("", _fs(UiKit.FS_SM), COL_TEXT)
	mcol.add_child(_status)

	var hint := _mk_label("说明：host 点「开始选人」后，本窗与每个已连玩家各自弹面板选英雄+召唤师；全员锁齐后 host 才可开局；开局后才加入的连接自动接管空闲同队 AI。", _fs(UiKit.FS_SM), COL_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(BTN_W, 0)
	mcol.add_child(hint)


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


# AI 难度循环切换：青铜→白银→…→王者→青铜（本机偏好，联机时主机生效）
func _cycle_difficulty() -> void:
	PlayerPrefs.set_ai_difficulty((PlayerPrefs.get_ai_difficulty() + 1) % AiConfig.DIFF_TABLE.size())
	_refresh_difficulty_btn()


func _refresh_difficulty_btn() -> void:
	var d := PlayerPrefs.get_ai_difficulty()
	var t: Dictionary = AiConfig.DIFF_TABLE.get(d, {})
	if _diff_btn != null:
		_diff_btn.text = "%s · 反应 %.2fs · 精度 %d%% · 预判 %d 帧（点击切换）" % [
			AiConfig.difficulty_name(d),
			float(t.get("reaction_delay", 0.0)),
			int(round(float(t.get("skill_accuracy", 1.0)) * 100.0)),
			int(t.get("prediction_frames", 0)),
		]


# 房间页：本机分路值（只读，回主菜单可改）
func _refresh_lane_info() -> void:
	if _lane_info == null:
		return
	var lane := PlayerPrefs.get_lane()
	_lane_info.text = "%s（%s）· 回主菜单可更换" % [lane, HeroPickData.lane_role(lane)]


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

	# 本机分路（读 PlayerPrefs；回主菜单可换）
	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 6)
	rcol.add_child(lane_row)
	var lane_cap := _mk_label("本机分路：", _fs(UiKit.FS_SM), COL_GOLD)
	lane_row.add_child(lane_cap)
	_lane_info = _mk_label("", _fs(UiKit.FS_SM), COL_SUB)
	lane_row.add_child(_lane_info)
	_refresh_lane_info()

	var foot_text := "发起后本窗与每位已连玩家会各自弹出选人面板；全员锁齐后你的「开始对局」才点亮。"
	if _role == 0:
		_start_btn = _mk_btn("▶  开始选人（全员选英雄）", UiKit.C_HEAL, true)
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
	if _start_btn != null:
		_start_btn.text = "▶  开始选人（在线 %d 人）" % count
		_start_btn.disabled = count < 1


func _roster_text(players: Dictionary) -> String:
	var ids := players.keys()
	ids.sort()
	var lines: PackedStringArray = []
	for id in ids:
		var who := "房主" if int(id) == 1 else "玩家"
		var nm: String = str(players[id].get("name", "玩家%d" % id))
		var tag := "（本机）" if _self_peer() == int(id) else ""
		lines.append("  " + who + " · " + nm + tag)
	if lines.is_empty():
		return "  （暂无他人）"
	return "\n".join(lines)


func _on_begin_pick() -> void:
	if _role != 0:
		return
	NetSession.begin_pick()


func _leave_room() -> void:
	NetSession.disconnect_network()
	_show_menu()
	_status_text("已离开房间", COL_SUB)


# ---------- SELECT：大厅选人（host 与每个 client 各自窗口同屏） ----------

func _seat_rows(state: Dictionary) -> Dictionary:
	# 场上席 = 房主(1) + 在线客户端，按 peer 排序取前 5；其余列为旁观
	var ids: Array = [1]
	var pl: Dictionary = state.get("players", {})
	for p in pl:
		# players 里已含房主(1)：去重，避免同一席位在 5v5 里重复占位
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
	_ui = UIState.SELECT
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
	# 分路 → 职责：未被队友占用则锁死本局职责，否则放开并提示
	_lane_role = HeroPickData.lane_role(PlayerPrefs.get_lane())
	_lane_locked = _lane_role != "" and not _blocked_roles.has(_lane_role)
	if _lane_locked:
		_tab_role = _lane_role
	elif _tab_role == _lane_role:
		_tab_role = ""
	_adopt_self_choice(state, data)
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
	var lt := _mk_label("我方", _fs(UiKit.FS_XS), UiKit.C_TEAM0)
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
	_stage_title = _mk_label("选择英雄", _fs(UiKit.FS_XL), COL_TITLE)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_stage_title)
	# 副行：默认玩法说明；接分路锁定时改为分路提示
	var lane := PlayerPrefs.get_lane()
	var lane_hint := "联机自选 · 全员锁定后房主开局"
	if _lane_locked:
		lane_hint = "本机分路：%s · 只能选择%s" % [lane, _lane_role]
	elif _lane_role != "":
		lane_hint = "本机分路「%s」已被队友占用，可选其他职责" % lane
	var sub := _mk_label(lane_hint, _fs(UiKit.FS_XS), COL_SUB)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sub)
	mv.add_child(tv)
	mv.add_child(_mk_count_ring(_stage_seconds(state)))

	# 右：敌方 mini 席位槽
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rt := _mk_label("敌方", _fs(UiKit.FS_XS), UiKit.C_TEAM1)
	rt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.add_child(rt)
	_enemy_slots = HBoxContainer.new()
	_enemy_slots.add_theme_constant_override("separation", 6)
	right.add_child(_enemy_slots)
	h.add_child(right)

	# 填充 mini 槽（我方取真实席位，缺位 = AI 补齐；敌方 5 席 = AI）
	var seats: Array = data["seats"]
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		var mine := false
		var ttl := "席位 %d" % (i + 1)
		var sub_txt := "AI 补齐"
		if i < seats.size():
			var s: Dictionary = seats[i]
			mine = bool(s.is_me)
			ttl = "%d · %s" % [i + 1, str(s.name)]
			sub_txt = str(s.hero) if str(s.hero) != "" else "待选"
		_my_slots.add_child(_mk_mini_slot(ttl, sub_txt, UiKit.C_TEAM0, mine))
		_enemy_slots.add_child(_mk_mini_slot("%d · 敌方" % (i + 1), "AI", UiKit.C_TEAM1, false))
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
	_my_col.custom_minimum_size = Vector2(190, 0)
	_my_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_my_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_col.add_theme_constant_override("separation", 6)
	main.add_child(_my_col)
	var seats: Array = data["seats"]
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		var seat: Dictionary = seats[i] if i < seats.size() else {}
		_my_col.add_child(_mk_seat_card(i + 1, seat, false))

	main.add_child(_build_center_stage())

	_enemy_col = VBoxContainer.new()
	_enemy_col.custom_minimum_size = Vector2(190, 0)
	_enemy_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enemy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_enemy_col.add_theme_constant_override("separation", 6)
	main.add_child(_enemy_col)
	for i in range(NetSession.MAX_SIDE_PLAYERS):
		_enemy_col.add_child(_mk_seat_card(i + 1, {}, true))
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

	_preview_name = _mk_label("请选择英雄", int(_fs(UiKit.FS_HUGE) * 1.8), Color.WHITE)
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_preview_name)

	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 10)
	chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(chip_row)

	_prev_role_chip = PanelContainer.new()
	_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.55, 12))
	_prev_role_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_role = _mk_label("职责 —", _fs(UiKit.FS_MD), UiKit.C_TEAM0)
	_preview_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev_role_chip.add_child(_preview_role)
	chip_row.add_child(_prev_role_chip)

	_prev_summ_chip = PanelContainer.new()
	_prev_summ_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_GOLD, 0.55, 12))
	_prev_summ_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_summ_icon = SelectArt.SummonerGlyph.new("", 28)
	srow.add_child(_preview_summ_icon)
	_preview_summ = _mk_label("召唤师 · 未选择", _fs(UiKit.FS_MD), COL_GOLD)
	_preview_summ.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_preview_summ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(_preview_summ)
	_prev_summ_chip.add_child(srow)
	chip_row.add_child(_prev_summ_chip)

	_prev_chip_row = HBoxContainer.new()
	_prev_chip_row.add_theme_constant_override("separation", 8)
	_prev_chip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_prev_chip_row)

	var tip := _mk_label("点英雄卡选英雄 → 右侧选召唤师 → 点锁定；锁后仍可改选再锁", _fs(UiKit.FS_XS), COL_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tip)
	return box


# 190×130 席位卡：席位号+名字 / 英雄 / 职责·召唤师（自己金框）
func _mk_seat_card(idx: int, seat: Dictionary, enemy: bool) -> PanelContainer:
	var is_empty := seat.is_empty()
	var mine := bool(seat.get("is_me", false))
	var hero := str(seat.get("hero", ""))
	var role := str(seat.get("role", ""))
	var accent: Color = UiKit.C_TEAM1 if enemy else UiKit.C_TEAM0
	if hero != "":
		accent = HeroPickData.ROLE_COLORS.get(role, accent)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(196, 130)
	p.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD if mine else accent, mine, 0.72))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	row.add_child(SelectArt.Avatar.new(hero, accent, 44))
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 1)
	row.add_child(v)

	var who := "敌方 AI" if enemy else ("AI 补齐" if is_empty else str(seat.get("name", "")))
	var head := _mk_label("%d 号位 · %s" % [idx, who], _fs(UiKit.FS_XS),
		UiKit.C_GOLD if mine else COL_SUB)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(head)

	var hero_txt := "AI" if enemy else (hero if hero != "" else "待选")
	var hero_lab := _mk_label(hero_txt, _fs(UiKit.FS_SM),
		UiKit.C_GOLD if mine else (COL_TEXT if hero != "" else COL_DIM))
	hero_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(hero_lab)

	var sub_txt := "红方 · 电脑控制"
	if not enemy:
		if hero != "":
			sub_txt = "%s · %s" % [role, _summoner_name(str(seat.get("summoner", "")))]
		elif is_empty:
			sub_txt = "空位 · AI 补"
		else:
			sub_txt = "职责未定"
	var sub := _mk_label(sub_txt, _fs(UiKit.FS_XS), COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	return p


# 底部 300：左职业 tab + hero 横条 | 右召唤师 2 列 + 详情 + 离开/锁定/开始对局
func _build_select_bottom() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 300)

	# 左：职业 tab + 横向英雄卡条
	var left := _panel_block(UiKit.C_TEAM0, 0.32, 14, 10.0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 8)
	lv.add_child(_tab_row)
	_tab_btns.clear()
	var tabs: Array = [""]
	tabs.append_array(HeroPickData.ROLES_ORDER)
	for r in tabs:
		var active := str(r) == _tab_role
		var tb := _mk_tab_btn("全部" if str(r) == "" else str(r),
			UiKit.C_GOLD if active else UiKit.C_TEAM0, active)
		tb.pressed.connect(_select_tab.bind(str(r)))
		if _lane_locked and str(r) != _lane_role:
			# 分路已锁定：其它职业 tab 置灰不可点
			tb.disabled = true
			tb.tooltip_text = "本机分路：%s · 只能选择%s" % [PlayerPrefs.get_lane(), _lane_role]
		_tab_row.add_child(tb)
		_tab_btns[str(r)] = tb
	var strip_scroll := ScrollContainer.new()
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(strip_scroll)
	_hero_strip = HBoxContainer.new()
	_hero_strip.add_theme_constant_override("separation", 10)
	strip_scroll.add_child(_hero_strip)
	_rebuild_strip()

	# 右：召唤师技能 + 详情 + 操作键
	var right := _panel_block(UiKit.C_GOLD, 0.32, 14, 10.0)
	right.custom_minimum_size = Vector2(520, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right.add_child(rv)
	rv.add_child(_mk_label("召唤师技能（点击选择）", _fs(UiKit.FS_XS), COL_SUB))
	var sscroll := ScrollContainer.new()
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sscroll.custom_minimum_size = Vector2(0, 120)
	rv.add_child(sscroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.add_child(grid)
	_summ_btns.clear()
	for sname in HeroPickData.SUMMONERS:
		var sid: String = HeroPickData.SUMMONERS[sname]
		var sb := _mk_card_btn("", Color(0.36, 0.46, 0.66))
		sb.custom_minimum_size = Vector2(200, 64)
		var srow := HBoxContainer.new()
		srow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		srow.alignment = BoxContainer.ALIGNMENT_CENTER
		srow.add_theme_constant_override("separation", 8)
		srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		srow.add_child(SelectArt.SummonerGlyph.new(sname, 36))
		var slab := _mk_label(sname, _fs(UiKit.FS_MD), COL_TEXT)
		slab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		srow.add_child(slab)
		sb.add_child(srow)
		sb.pressed.connect(_pick_summ.bind(sname, sid))
		sb.mouse_entered.connect(_show_summ_tip.bind(sname, sid))
		sb.mouse_exited.connect(_hide_summ_tip)
		grid.add_child(sb)
		_summ_btns[sid] = sb

	_pick_status = _mk_label("", _fs(UiKit.FS_XS), COL_ERR)
	_pick_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rv.add_child(_pick_status)
	_pick_summary = _mk_label("", _fs(UiKit.FS_XS), COL_GOLD)
	_pick_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pick_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rv.add_child(_pick_summary)

	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 8)
	rv.add_child(brow)
	if _my_seat <= NetSession.MAX_SIDE_PLAYERS:
		_pick_confirm_btn = _mk_btn("✔  锁定选择", UiKit.C_TEAM0, true, Vector2(340, 92))
		_pick_confirm_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
		_pick_confirm_btn.pressed.connect(_on_pick_confirm)
		brow.add_child(_pick_confirm_btn)
	else:
		var sp := _mk_label("旁观中 · 有人离场可上场", _fs(UiKit.FS_XS), COL_DIM)
		brow.add_child(sp)
	_leave_btn = _mk_btn("离开房间", UiKit.C_DANGER, false, Vector2(180, 92))
	_leave_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	_leave_btn.pressed.connect(_leave_room)
	brow.add_child(_leave_btn)
	if _role == 0:
		_host_go_btn = _mk_btn("▶  开始对局（全员锁齐后可用）", UiKit.C_HEAL, true, Vector2(340, 92))
		_host_go_btn.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
		_host_go_btn.pressed.connect(_host_start_battle)
		rv.add_child(_host_go_btn)
	return bar


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


# 180×112 英雄卡：英雄名 + 职责（被他人占的职责置灰并标「已被占」）
func _mk_hero_card(hname: String, role: String, accent: Color) -> Button:
	# 分路锁定时非本职责英雄置灰不可点（「分路不符」）
	var lane_bad: bool = _lane_locked and role != _lane_role
	var blocked: bool = _blocked_roles.has(role) or lane_bad
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
	if lane_bad:
		tag = "分路不符"
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
	if _pick_confirm_btn != null:
		_pick_confirm_btn.disabled = _sel_hero == "" or _sel_sid == ""
	if _role == 0 and _host_go_btn != null:
		var ready := true
		var locked_n := 0
		for s in data["seats"]:
			if str(s.hero) != "":
				locked_n += 1
			else:
				ready = false
		_host_go_btn.disabled = not ready
		if ready:
			_host_go_btn.text = "▶  开始对局（%d 人已锁）" % locked_n
		else:
			_host_go_btn.text = "▶  开始对局（等全员锁齐）"


func _pick_hero(hname: String) -> void:
	if not HeroPickData.HERO_ROLE.has(hname):
		return
	var role := str(HeroPickData.HERO_ROLE[hname])
	if _lane_locked and role != _lane_role:
		if _pick_status != null:
			_pick_status.text = "本机分路：%s · 只能选择%s" % [PlayerPrefs.get_lane(), _lane_role]
			_pick_status.add_theme_color_override("font_color", COL_ERR)
		return
	if _blocked_roles.has(role):
		return
	_sel_hero = hname
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
	_sync_pick_ui()


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
		_pick_confirm_btn.disabled = _sel_hero == "" or _sel_sid == ""
	if _pick_summary != null and _sel_hero != "" and _sel_sid != "":
		_pick_summary.text = "待锁定：%s · %s + %s" % [str(HeroPickData.HERO_ROLE[_sel_hero]), _sel_hero, _sel_summ]
		_pick_summary.add_theme_color_override("font_color", COL_GOLD)
	_refresh_preview()


# 中栏立绘/覆盖层：随本机草稿实时刷新（未选 = 提示胶囊，已选 = 3D 模型 + 职责色 + chip 行）
func _refresh_preview() -> void:
	if _preview_name == null:
		return
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
	_preview_role.text = ("职责 · " + role) if role != "" else "职责 —"
	_preview_role.add_theme_color_override("font_color", rcol.lightened(0.2))
	if _prev_role_chip != null:
		_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(rcol, 0.55, 12))
	_preview_summ.text = "召唤师 · " + (_sel_summ if _sel_summ != "" else "未选择")
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
	_style_pick_cards()


func _on_pick_confirm() -> void:
	if _sel_hero == "" or _sel_sid == "":
		return
	# 分路锁定时锁定前再校验一次职责
	if _lane_locked and str(HeroPickData.HERO_ROLE.get(_sel_hero, "")) != _lane_role:
		_show_pick_error("本机分路：%s · 只能锁定%s英雄" % [PlayerPrefs.get_lane(), _lane_role])
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


func _host_start_battle() -> void:
	if _role != 0:
		return
	if _host_go_btn != null:
		_host_go_btn.disabled = true
	NetSession.start_match()


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
	var ph := int(state.get("phase", NetSession.Phase.LOBBY))
	_set_menu_enabled(true)
	if _role == -1:
		_role = 1 if NetSession.mode == NetSession.Mode.CLIENT else 0
	if ph == NetSession.Phase.SELECT:
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
	get_tree().call_deferred("change_scene_to_file", "res://scenes/battle.tscn")


func _route_client() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/net_client.tscn")
