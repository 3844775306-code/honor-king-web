class_name UI_Manager
extends CanvasLayer

const SkillArt = preload("res://scripts/ui/SkillArt.gd")
const DeathRecapView = preload("res://scripts/ui/DeathRecapView.gd")
const RosterView = preload("res://scripts/ui/RosterView.gd")
const EntityIconArtScript = preload("res://scripts/ui/EntityIconArt.gd")

# ---------- 通用样式辅助函数 ----------
# UI 自适应缩放：以基准虚拟宽度 2400 为 1.0，叠加固定放大系数保证手机可读。
# 项目用 canvas_items+expand 拉伸，横屏下虚拟高度恒为 1400、宽度随设备变化（≥2400）。
func ui_scale() -> float:
	return UiKit.scale()

func _apply_label_style(label: Label, font_size: int = 14, color: Color = UiKit.C_TEXT):
	label.add_theme_font_size_override("font_size", int(round(font_size * ui_scale())))
	label.add_theme_color_override("font_color", color)
	# 描边随字号缩放（原来恒为 1px，字号一大描边就消失，3D 场景上白字发糊）
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	label.add_theme_constant_override("outline_size", UiKit.outline_size(font_size * ui_scale()))

func _apply_rich_label_style(rich: RichTextLabel, font_size: int = 14):
	rich.add_theme_font_size_override("normal_font_size", int(round(font_size * ui_scale())))
	rich.add_theme_color_override("default_color", UiKit.C_TEXT)

func _apply_panel_style(panel: Panel, alpha: float = 0.8):
	# P0 统一皮肤：扁平深色玻璃 + 1px 冷光描边（比 64px 9-slice 拉伸更锐利，且带柔和投影）
	panel.add_theme_stylebox_override("panel",
		UiKit.flat(clampf(alpha, 0.35, 1.0), 12, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0), 10.0, 6.0))

func _apply_button_style(btn: Button):
	btn.add_theme_font_size_override("font_size", int(round(14 * ui_scale())))
	btn.add_theme_color_override("font_color", UiKit.C_TEXT)
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.72))
	btn.add_theme_constant_override("outline_size", 1)

# ---------- 商店 / 英雄面板的视觉辅助 ----------
func _shop_tier_color(tier: int) -> Color:
	match tier:
		1: return UiKit.QUALITY_COLORS[0]
		2: return UiKit.QUALITY_COLORS[2]
		3: return UiKit.QUALITY_COLORS[3]
		4: return UiKit.C_GOLD
		_: return Color(0.85, 0.85, 0.85)

func _shop_tier_name(tier: int) -> String:
	match tier:
		1: return "基础"
		2: return "中级"
		3: return "终极大件"
		4: return "终极神装"
		_: return ""

func _shop_cat_style(cat: String) -> Array:
	if cat == "推荐": return ["star", Color(0.98, 0.84, 0.38)]
	match cat:
		"物理": return ["刃", Color(1.0, 0.52, 0.22)]
		"法术": return ["杖", Color(0.72, 0.5, 1.0)]
		"防御": return ["盾", Color(0.4, 0.72, 1.0)]
		"靴子": return ["鞋", Color(0.95, 0.75, 0.42)]
		"打野": return ["猎", Color(0.45, 0.85, 0.42)]
		"游走": return ["辅", Color(0.25, 0.85, 0.85)]
		"保命": return ["护", Color(1.0, 0.42, 0.42)]
		"辅助": return ["助", Color(0.95, 0.86, 0.3)]
		_: return ["装", Color(0.85, 0.85, 0.85)]

# 商店各分类的装备 ID 列表（辅助=游走同源的辅助装）
func _shop_categories() -> Dictionary:
	var roam: Array = ["ancient_coin", "wind_blessing", "guardian_glory", "extreme_shadow", "redeemer_guard", "star_spring_guard", "galloping_wolf_guard", "revealing_light_guard", "redeemer_shadow", "star_spring_shadow", "galloping_wolf_shadow", "revealing_light_shadow"]
	return {
		"物理": ["iron_sword", "vampire_scythe", "storm_sword", "swift_spear", "thundercry_blade", "corona", "meteorite", "speedy_strike_spear", "bloodsoul_blade", "bramble_gauntlets", "bloodthirster", "infinity_edge", "sage_power", "battle_axe", "breaker", "star_shatterer", "blade_of_sanction", "world_end", "purify", "demon_bane_blade", "frost_assault", "knife", "battle_fist", "enchanted_feather", "furious_dual_blades", "forged_steel_blade", "piercing_cloud_bow", "lightning_knife", "shadow_blade", "sunspire_bow", "dawn", "chase_wind", "shadow_dart", "swift_day"],
		"法术": ["magic_book", "blue_diamond", "secert_spell", "crystal_flow", "big_bang", "saint_spell", "spell_vamp_book", "spell_stone", "cloud_wood", "phantom_mask", "echo_staff", "nightmare", "rabadon", "void_staff", "golden_body", "pain_mask", "dusk_flow", "fire_dominate", "gold_saint_sword", "saint_cup", "godslayer_book", "witch_staff", "prophecy_of_time", "break_cocoon_cloth", "sky_book", "frost_breath", "moon_god"],
		"防御": ["cloth_armor", "cloth_magic_armor", "red_diamond", "regen_crystal", "swift_armor", "strength_belt", "tarnkappe", "snow_shield", "guardian_armor", "agate_breastplate_mirror", "sky_earth_stone", "thornmail", "omen", "mage_robe", "dragon_shield", "red_cloak", "heavy_armor", "eye_of_the_phoenix", "ice_storm", "fierce_armor", "night_guardian", "ice_fist", "ice_shock", "rising_sun"],
		"靴子": ["boots", "armor_boots", "resist_boots", "cd_boots", "swift_boots", "spell_boots", "run_boots"],
		"保命": ["blood_rage", "famous_blade", "revive", "primal_pearl", "immovable_firmament", "rage_ghost", "sereve_winter"],
		"打野": ["hunter_knife", "guerrilla_blade", "chase_blade", "patrol_axe", "rune_blade", "greed_blade", "giant_grasp"],
		"游走": roam,
	}

# 分类页按钮：统一皮肤；选中时分类色描边 + 底边加粗强调
func _cat_button_style(cat: String, selected: bool) -> StyleBoxFlat:
	var tint: Color = _shop_cat_style(cat)[1]
	var sb := UiKit.skin_chip(tint if selected else UiKit.C_PANEL_EDGE, 0.95 if selected else 0.88, 10)
	if selected:
		sb.bg_color = Color(0.16, 0.18, 0.24, 0.96)
		sb.border_width_bottom = 3
	sb.content_margin_left = 14; sb.content_margin_right = 14
	return sb

# 装备卡：统一卡片皮肤 + 品级色
func _item_card_style(tier: int, selected: bool) -> StyleBoxFlat:
	var sb := UiKit.skin_card(_shop_tier_color(tier), selected, 0.94)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

# 常用扁平小按钮（辅助按钮：实心强调 / 描边两态）
func _flat_action_style(filled: bool, accent: Color) -> StyleBoxFlat:
	if filled:
		return UiKit.skin_button("normal", accent, true)
	return UiKit.skin_chip(accent, 0.9, 8)

# ---------- 变量声明 ----------
var target_detail_panel: Panel
var target_detail_hp_bar: ProgressBar
var target_detail_labels: Dictionary = {}
var target_detail_accent: ColorRect      # 顶部队色强调条（每帧按目标阵营上色）
var target_detail_team_dot: ColorRect    # 姓名前的队色小方块
var target_detail_hp_fill: StyleBoxFlat  # 血条填充样式，填充色跟随阵营
var target_detail_hp_gloss: Control     # 血条质感层（高光/刻度/末端亮边）
var target_detail_hp_pill: Panel        # 血条读数底衬（深色圆角，保证数字清晰）
var target_detail_icons: Dictionary = {} # 属性徽章图标（键=属性名）
var target_detail_entity_icon: Control   # 目标实体图标（英雄头像/塔/小兵/野怪）
var kda_label: Label
var time_chip: Panel

var skill_icons: Array = []
var skill_name_labels: Array = []
var skill_level_labels: Array = []
var skill_info_labels: Array = []
var skill_detail_label: Label

var team_stats_label: RichTextLabel
var vanguard_label: Label        # 顶部信息带第三行：主宰/暗影/风暴先锋剩余波次
var team_stats_bg: Panel
var gold_label: Label
var game_time_label: Label
var fps_label: Label
var recommended_equip_label: Label
var rec_card: RecItemCard
var recommended_equip_id: String = ""
var recommended_equip_cost: int = 0
var buy_plus_btn: TouchActionButton = null   # 推荐装备旁“+”快速购买（仅金币足够时显示）
var rec_option_row: Control = null     # 多件素材都能买时的自选购买按钮列（上下两个同款，手动排布）
var rec_option_btns: Array = []
var rec_option_sig: String = ""
var settings_btn: Button = null              # 推荐装下面的「设置」按钮
var _settings_btn_h := 36.0                  # 移动端加大后的按钮高度
var settings_panel: Control = null
var surrender_status_label: Label = null
var surrender_vote_running: bool = false
const SURRENDER_MIN_TIME := 360.0            # 6 分钟后才能发起投降
const SURRENDER_MIN_YES := 4                 # 本队 5 人中需 4 票通过
# 推荐位：两件素材都可买时，直接把两张「推荐卡」并排占据推荐卡位置（不再在卡下方加购买按钮）
const REC_OPTION_W := 246.0
const REC_OPTION_H := 120.0
const REC_OPTION_TOP := 70.0
var cached_recommended_list: Array = []
var cached_recommended_for: String = ""

# 战报：每次只播 1 条，固定 2.0s（1.75s 停留 + 0.25s 淡出），多条累计进队列延迟播出
const KF_MAX := 3               # 兼容旧引用（不再堆叠）
const KF_QUEUE_MAX := 12        # 队列上限：超出丢最旧，避免大团战后播报跟不上
const KF_W := 620.0
const KF_H := 64.0
const KF_ASSIST_H := 44.0       # 有助攻时的第二行（助攻者头像）
const KF_GAP := 8.0
const KF_TOP := 154.0
const KF_SHOW := 1.75           # 停留
const KF_FADE := 0.25           # 淡出（合计 2.0s/条）
var kill_feed_slots: Array = [] # 兼容旧字段（现始终至多 1 个元素）
var _kf_queue: Array = []       # [{actor,a_team,desc,victim,v_team,a_mark,v_mark,assists:[[name,team,mark],...]}]
var _kf_cur: Panel = null       # 当前正在播的 1 条

var shop_ui: Control = null
var shop_category_container: HBoxContainer = null
var shop_item_list: VBoxContainer = null
var shop_detail_panel: Control = null
var shop_owned_container: HBoxContainer = null
var shop_selected_item: String = ""
var shop_buy_sell_btn: Button = null
var shop_price_label: Label = null
var shop_selected_category: String = "物理"
var shop_item_grid: GridContainer = null
var shop_card_w: float = 300.0        # 装备卡片列宽（_open_shop 按抽屉宽度算）
var shop_stat_labels: Dictionary = {}
var shop_sell_btn: Button = null
var shop_owned_slot: float = 72.0
var shop_title_label: Label = null
var shop_grid_ids: Array = []            # 当前分类可见装备 id（键盘 ↑↓ 选装用）
var shop_grid_scroll: ScrollContainer = null

var respawn_container: VBoxContainer
var _respawn_sig: String = ""          # 复活/观战部件重建签名（避免每帧重建）
var death_recap_panel            # DeathRecapView 实例（纯绘制死亡面板）
var death_overlay: ColorRect = null   # 死亡全屏压暗层（高 CanvasLayer：盖住 HUD/buff/技能键）
var death_high_layer: CanvasLayer = null
var death_recap_high_layer: CanvasLayer = null
var death_recap_shown: bool = false
var _band_children: int = -1
var death_recap_closed: bool = false  # 玩家手动关闭后本局不再自动弹出

var hero_detail_panel            # RosterView 实例（双列对位英雄信息面板）
var hero_detail_visible: bool = false
var hero_detail_refresh_timer: float = 0.0
var hero_detail_dim: ColorRect = null   # 移动端抽屉遮罩
var chat_typing: bool = false   # 聊天输入框打开中（由 ChatBox 置位）

# 团队决策面板
var team_decision_panel: Panel = null
var team_decision_visible: bool = false
var team_decision_refresh_timer: float = 0.0
var team_decision_labels: Dictionary = {}

var entity_health_bars: Dictionary = {}
var _popup_offsets: Dictionary = {}  # 伤害数值错开：{Vector3: {count:int, timer:float}}
var _device_status: Control = null   # 顶部信息带：电量/网络小组件
var _dev_poll := 0.0                 # 电量/网络轮询计时（1s 一次，避免每帧读系统接口）
var _yl_switch_btn: Button = null    # 元流之子「流派·切换」钮：自家泉水中常驻，点击重开万物为流面板
var _yl_panel_open: bool = false     # 万物为流选择面板是否打开（打开时隐藏切换钮、防重复叠开面板）

# === 底部 Buff 图标条 ===
const BUFF_ROW_Y := 980.0       # 下排图标格顶边 y：2× 尺寸后图标底=980+136=1116，比右下角回城/恢复/召唤师横带上沿(y≈1130)高 14px，
								# 整条图标带已从原 1222 整体上移（净上移≈240px），横带左移后不再遮挡；如需微调改此值
const BUFF_INFO_W := 460.0      # 点击图标弹出的详情面板宽
var buff_icon_nodes: Dictionary = {}   # key -> BuffIcon
var selected_buff_key: String = ""     # 当前查看详情的 buff key（点图标弹出/再点关闭）
var buff_info_panel: Panel = null
var buff_info_title: Label = null
var buff_info_desc: Label = null

# === 左侧属性面板（基础=白 / 装备=绿 / Buff=橙） ===
const ATTR_ROWS_PER_COL := 9
const ATTRIBUTE_ROWS := [
	{"key": "health", "name": "生命", "mult": 1.0, "pct": false},
	{"key": "mana", "name": "法力", "mult": 1.0, "pct": false},
	{"key": "attack", "name": "攻击", "mult": 1.0, "pct": false},
	{"key": "ability_power", "name": "法强", "mult": 1.0, "pct": false},
	{"key": "armor", "name": "护甲", "mult": 1.0, "pct": false},
	{"key": "magic_resist", "name": "魔抗", "mult": 1.0, "pct": false},
	{"key": "move_speed", "name": "移速", "mult": 1.0, "pct": false},
	{"key": "attack_speed", "name": "攻速", "mult": 1.0, "pct": true},
	{"key": "crit_chance", "name": "暴击", "mult": 100.0, "pct": true},
	{"key": "crit_damage", "name": "暴击伤害", "mult": 100.0, "pct": true},
	{"key": "phys_lifesteal", "name": "物理吸血", "mult": 100.0, "pct": true},
	{"key": "magic_lifesteal", "name": "法术吸血", "mult": 100.0, "pct": true},
	{"key": "cd", "name": "冷却", "mult": 1.0, "pct": true},
	{"key": "phys_pen_percent", "name": "物穿%", "mult": 100.0, "pct": true},
	{"key": "phys_pen_flat", "name": "物穿(数值)", "mult": 1.0, "pct": false},
	{"key": "magic_pen_percent", "name": "法穿%", "mult": 100.0, "pct": true},
	{"key": "magic_pen_flat", "name": "法穿(数值)", "mult": 1.0, "pct": false},
	{"key": "toughness", "name": "韧性", "mult": 100.0, "pct": true},
]
var attribute_panel: Panel = null
var attr_row_labels: Array = []
var attr_header: Label = null            # 折叠标题条（点一下展开/收起）
var attr_legend: RichTextLabel = null    # 顶部图例（收起时一并隐藏）
var attr_collapsed := true               # 默认收起，标题条紧贴小地图下方
var attr_panel_h_full := 0.0             # 展开时的完整高度
var attr_header_h := 0.0                 # 收起后保留的标题条高度
var attr_panel_w_full := 0.0             # 展开时完整宽度（收起时与小地图同宽）
var attr_panel_top := 0.0                # 面板顶边（固定，向下展开）

# ---------- 初始化 ----------
var _fx_flash: ColorRect = null
var _fx_flash_tween: Tween = null

# P0 屏幕反馈：暖色闪屏（仅本地表现，不参与联机）。放在 CanvasLayer 最底层，
# 只给 3D 画面染色，不洗白 UI。
func _create_fx_flash():
	_fx_flash = ColorRect.new()
	_fx_flash.color = Color(1, 1, 1, 0)
	_fx_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_flash.visible = false
	add_child(_fx_flash)
	move_child(_fx_flash, 0)

func flash_screen(color: Color, dur: float = 0.18) -> void:
	if _fx_flash == null:
		return
	if _fx_flash_tween and _fx_flash_tween.is_valid():
		_fx_flash_tween.kill()
	_fx_flash.visible = true
	_fx_flash.color = Color(color.r, color.g, color.b, 0.0)
	_fx_flash_tween = create_tween()
	_fx_flash_tween.tween_property(_fx_flash, "color:a", 0.26, dur * 0.25)
	_fx_flash_tween.tween_property(_fx_flash, "color:a", 0.0, dur * 0.75)
	_fx_flash_tween.tween_callback(func(): _fx_flash.visible = false)

func _create_death_overlay():
	# 独立高 CanvasLayer：触控技能键在 100 层，死亡压暗必须高于它才能盖住技能/装备键
	death_high_layer = CanvasLayer.new()
	death_high_layer.name = "DeathHighLayer"
	death_high_layer.layer = UiKit.LAYER_RECAP - 1   # 104：盖住触控100/飘字103，低于死亡面板105
	add_child(death_high_layer)
	death_overlay = ColorRect.new()
	death_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	death_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_overlay.visible = false
	death_high_layer.add_child(death_overlay)


# —— 同画布内 z 分带：常驻 HUD 永远在功能面板之下、死亡回放在两者之上 ——
# 之前 buff 图标是运行时建的（add_child 晚于死亡回放），会盖住回放面板；改为显式 z_index 后与建节点顺序无关。
func _apply_layer_bands() -> void:
	for c in get_children():
		if c is CanvasItem:
			c.z_index = UiKit.Z_HUD
	if death_overlay: death_overlay.z_index = UiKit.Z_DIM
	if hero_detail_dim: hero_detail_dim.z_index = UiKit.Z_DIM
	if hero_detail_panel: hero_detail_panel.z_index = UiKit.Z_PANEL
	if attribute_panel: attribute_panel.z_index = UiKit.Z_PANEL
	if team_decision_panel: team_decision_panel.z_index = UiKit.Z_PANEL
	if death_recap_panel: death_recap_panel.z_index = UiKit.Z_RECAP
	if buff_info_panel: buff_info_panel.z_index = UiKit.Z_TOOLTIP
	_band_children = get_child_count()
func _ready():
	layer = UiKit.LAYER_HUD   # 分层见 UiKit：后处理(1) < 世界血条(8) < 本画布(20) < 触控(100)；本画布内再用 z_index 分带
	add_to_group("ui")
	_create_fx_flash()
	_create_death_overlay()
	_create_target_detail_panel()
	_create_skill_bar()
	_create_info_labels()
	_create_buff_icons()
	_create_attribute_panel()
	_create_hero_detail_panel()
	_create_yuanliu_switch_btn()
	_create_death_recap_panel()
	_create_team_decision_panel()
	# 单例 HUD：默认隐藏，避免在大厅/客户端露出战斗控件；进入对局由 enter_battle() 打开
	visible = false
	_apply_layer_bands()

# 由 BattleManager 在进入对局时调用：打开 HUD 并清掉上一局残留
func enter_battle() -> void:
	visible = true
	_clear_battle_hud()
	# 视口尺寸在进入战斗时才是最终值，重排依赖视口高度的左栏面板
	_layout_attribute_panel()

# 离开对局（回大厅 / 联机客户端接管自己的 HUD）：关掉 HUD 并清理瞬时控件
func exit_battle() -> void:
	visible = false
	_clear_battle_hud()

func _clear_battle_hud() -> void:
	for p in kill_feed_slots:
		if is_instance_valid(p):
			p.queue_free()
	kill_feed_slots.clear()
	_kf_queue.clear()
	_kf_cur = null
	if shop_ui != null and is_instance_valid(shop_ui):
		shop_ui.queue_free()
		shop_ui = null
	if death_overlay != null:
		death_overlay.visible = false
	if death_recap_panel != null:
		death_recap_panel.visible = false
	if target_detail_panel != null:
		target_detail_panel.visible = false


# 运行时新建的控件（飘字/击杀播报/buff 图标等）默认归入常驻 HUD 带，避免落到 z=0 被其它 HUD/面板盖住
func _sync_layer_bands() -> void:
	var n: int = get_child_count()
	if n == _band_children:
		return
	for c in get_children():
		if c is CanvasItem and int(c.z_index) == 0:
			c.z_index = UiKit.Z_HUD
	_band_children = n

func _process(delta: float):
	_sync_layer_bands()
	var expired: Array = []
	for key in _popup_offsets:
		var info = _popup_offsets[key]
		info.timer -= delta
		if info.timer <= 0:
			expired.append(key)
	for key in expired:
		_popup_offsets.erase(key)

# ---------- UI 创建函数 ----------
func _create_target_detail_panel():
	# 攻击目标信息框：小地图下方。配色上——阵营色用于顶部队条/血条填充/姓名前小方块；
	# 属性色用于各属性徽章与数值（物攻橙 / 法强紫 / 护甲金 / 魔抗青）；
	# “图标”用程序化彩色圆徽章（本作无美术资源，统一用矢量色块充当）。
	target_detail_panel = Panel.new()
	var rs := ui_scale()
	target_detail_panel.size = Vector2(330 * rs, 170 * rs)
	# 顶部横向带：插在英雄头像与右侧战况面板之间（5 头像右缘≈1190，战况面板左缘≈1619）
	# 宽度收至 89%，视觉右缘≈1597，给面板阴影留出安全间距
	target_detail_panel.position = Vector2(1200 + UiKit.safe_left(), 8 + UiKit.safe_top())
	target_detail_panel.scale = Vector2(0.89, 0.97)
	target_detail_panel.visible = false
	# 面板底：深色玻璃 + 双层描边（外冷光 / 内高光）+ 柔和投影，比纯 flat 更有层次
	var frame := UiKit.flat(0.94, 12, 2, Color(0.62, 0.74, 0.96, 0.22), Color(0.025, 0.045, 0.095, 0.92), 0.0, 16.0)
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.set_corner_detail(10)
	target_detail_panel.add_theme_stylebox_override("panel", frame)
	add_child(target_detail_panel)

	# 顶部渐隐冷光（压在面板上、标签下），让顶边有玻璃反光质感
	var sheen := ColorRect.new()
	sheen.position = Vector2(2, 2)
	sheen.size = Vector2(326, 2.0) * rs
	sheen.color = Color(1, 1, 1, 0.10)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_detail_panel.add_child(sheen)

	# 顶部阵营色强调条 + 姓名前同色小方块（二者颜色在每帧 update 中随目标阵营切换）
	target_detail_accent = ColorRect.new()
	target_detail_accent.position = Vector2.ZERO
	target_detail_accent.size = Vector2(330, 5) * rs
	target_detail_panel.add_child(target_detail_accent)
	var accent_shine := TargetAccentShine.new()
	accent_shine.position = Vector2.ZERO
	accent_shine.size = Vector2(330, 5) * rs
	accent_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_detail_panel.add_child(accent_shine)
	# 目标实体图标：英雄头像 / 塔 / 小兵 / 野怪（数据在 _update 中刷新）
	target_detail_entity_icon = EntityIconControl.new()
	target_detail_entity_icon.position = Vector2(12, 7) * rs
	target_detail_entity_icon.size = Vector2(30, 30) * rs
	target_detail_entity_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_detail_panel.add_child(target_detail_entity_icon)

	target_detail_team_dot = ColorRect.new()
	target_detail_team_dot.position = Vector2(47, 13) * rs
	target_detail_team_dot.size = Vector2(8, 8) * rs
	target_detail_panel.add_child(target_detail_team_dot)

	var name_label = Label.new()
	name_label.position = Vector2(60, 8) * rs; name_label.size = Vector2(146, 26) * rs
	_apply_label_style(name_label, 17, Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	target_detail_panel.add_child(name_label); target_detail_labels["name"] = name_label
	# 等级徽章底片（金色描边小胶囊），让右侧 Lv 不再是裸字
	var lv_chip := Panel.new()
	lv_chip.position = Vector2(210, 7) * rs
	lv_chip.size = Vector2(108, 24) * rs
	lv_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_chip.add_theme_stylebox_override("panel",
		UiKit.flat(0.60, 7, 1, Color(1.0, 0.82, 0.35, 0.28), Color(0.09, 0.07, 0.02, 0.55)))
	target_detail_panel.add_child(lv_chip)
	var lv_label = Label.new()
	lv_label.position = Vector2(224, 10) * rs; lv_label.size = Vector2(92, 22) * rs
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_label_style(lv_label, 14, Color(1.0, 0.82, 0.35))
	target_detail_panel.add_child(lv_label); target_detail_labels["level"] = lv_label

	# 血条：外描边圆角底 + 阵营色填充（更高更厚，读数清晰）
	target_detail_hp_bar = ProgressBar.new()
	target_detail_hp_bar.position = Vector2(16, 43) * rs
	target_detail_hp_bar.size = Vector2(298, 22) * rs
	target_detail_hp_bar.show_percentage = false
	var hp_bg = StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.02, 0.03, 0.05, 0.85)
	hp_bg.set_corner_radius_all(11)
	hp_bg.set_border_width_all(1)
	hp_bg.border_color = Color(1, 1, 1, 0.14)
	target_detail_hp_bar.add_theme_stylebox_override("background", hp_bg)
	target_detail_hp_fill = StyleBoxFlat.new()
	target_detail_hp_fill.bg_color = Color(0.2, 0.9, 1.0)
	target_detail_hp_fill.set_corner_radius_all(11)
	target_detail_hp_fill.border_width_bottom = 2
	target_detail_hp_fill.border_color = Color(0, 0, 0, 0.25)
	target_detail_hp_bar.add_theme_stylebox_override("fill", target_detail_hp_fill)
	target_detail_panel.add_child(target_detail_hp_bar)
	# 血条质感层：顶部高光、底部内阴影、10% 刻度、填充末端亮边（在文字之下）
	var hp_gloss := TargetHpGloss.new()
	hp_gloss.position = Vector2(16, 43) * rs
	hp_gloss.size = Vector2(298, 22) * rs
	hp_gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_detail_panel.add_child(hp_gloss)
	target_detail_hp_gloss = hp_gloss
	# 读数底衬：深色半透明圆角胶囊，宽度随文字自适应（文字压在任意亮色填充上都清晰）
	target_detail_hp_pill = Panel.new()
	target_detail_hp_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_detail_hp_pill.add_theme_stylebox_override("panel",
		UiKit.flat(0.66, 8, 1, Color(1, 1, 1, 0.10), Color(0.01, 0.02, 0.035, 0.78)))
	target_detail_hp_pill.size = Vector2(110, 17) * rs
	target_detail_panel.add_child(target_detail_hp_pill)
	var hp_text = Label.new()
	hp_text.position = Vector2(16, 43) * rs; hp_text.size = Vector2(298, 22) * rs
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(hp_text, 14, Color(1, 1, 1, 0.98))
	hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hp_text.add_theme_constant_override("outline_size", 3)
	hp_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hp_text.add_theme_constant_override("shadow_offset_x", 1)
	hp_text.add_theme_constant_override("shadow_offset_y", 2)
	target_detail_panel.add_child(hp_text); target_detail_labels["hp"] = hp_text

	# 属性区：2×2 的「彩色圆徽章 + 属性色数值」；两行各垫一条低对比底片分出层次
	for chip_y in [74.0, 110.0]:
		var chip := Panel.new()
		chip.position = Vector2(10, chip_y) * rs
		chip.size = Vector2(310, 30) * rs
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_stylebox_override("panel",
			UiKit.flat(0.22, 8, 1, Color(1, 1, 1, 0.05), Color(0.05, 0.075, 0.13, 0.40)))
		target_detail_panel.add_child(chip)
	var attrs := ["攻击", "法强", "护甲", "魔抗"]
	var tints := {
		"攻击": Color(1.0, 0.58, 0.2),
		"法强": Color(0.82, 0.5, 1.0),
		"护甲": Color(1.0, 0.8, 0.32),
		"魔抗": Color(0.4, 0.88, 1.0),
	}
	var cols: Array[float] = [16.0, 168.0]
	for i in range(4):
		var attr: String = attrs[i]
		var col_x: float = cols[i % 2]
		var row_y: float = 82.0 if i < 2 else 118.0
		var icon := StatIcon.new()
		icon.shape = {"攻击": "sword", "法强": "spark", "护甲": "shield", "魔抗": "gem"}.get(attr, "")
		icon.tint = tints[attr]
		icon.position = Vector2(col_x, row_y) * rs
		icon.size = Vector2(26, 26) * rs
		target_detail_panel.add_child(icon); target_detail_icons[attr] = icon
		var lab = Label.new()
		lab.position = Vector2(col_x + 35, row_y) * rs
		lab.size = Vector2(118, 28) * rs
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_label_style(lab, 18, tints[attr])
		target_detail_panel.add_child(lab); target_detail_labels[attr] = lab

func _create_skill_bar():
	skill_icons.clear(); skill_name_labels.clear(); skill_level_labels.clear(); skill_info_labels.clear()
	# 8 个图标整体水平居中（虚拟高度恒 1400，y 固定；宽度随设备变化）
	var vw := get_viewport().get_visible_rect().size.x
	var start_x := (vw - 940.0) / 2.0
	for i in range(8):
		var icon = SkillIcon.new();
		icon.position = Vector2(start_x + i * 120.0, 1210); icon.size = Vector2(100, 100)
		skill_icons.append(icon); add_child(icon)

		var lv_label = Label.new(); lv_label.position = icon.position + Vector2(-18, 120)
		_apply_label_style(lv_label, 20, Color.BLACK)
		lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_level_labels.append(lv_label); add_child(lv_label)

		var name_label = Label.new(); name_label.position = icon.position + Vector2(22, 120)
		_apply_label_style(name_label, 20, Color.BLACK)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT; name_label.size.x = 50
		skill_name_labels.append(name_label); add_child(name_label)

		var info_label = Label.new(); info_label.position = icon.position + Vector2(0, 94)
		_apply_label_style(info_label, 20, Color.BLUE)
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; info_label.size.x = 50
		skill_info_labels.append(info_label); add_child(info_label)

	skill_detail_label = Label.new(); skill_detail_label.position = Vector2(200, 300)
	_apply_label_style(skill_detail_label, 32, Color.WHITE)
	skill_detail_label.visible = false; add_child(skill_detail_label)

	# 触控统一布局：电脑版与手机版都用触控技能键，旧桌面技能条整组隐藏
	_set_legacy_skill_bar_visible(false)

func _set_legacy_skill_bar_visible(v: bool):
	for j in range(skill_icons.size()):
		skill_icons[j].visible = v
		if j < skill_level_labels.size(): skill_level_labels[j].visible = v
		if j < skill_name_labels.size(): skill_name_labels[j].visible = v
		if j < skill_info_labels.size(): skill_info_labels[j].visible = v
	skill_detail_label.visible = v

# 可点击区域的通用手势处理：触摸按下 / 桌面鼠标左键按下触发 action，并吞掉事件防止漏到世界
func _connect_tap_to_action(ctrl: Control, action: Callable):
	ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctrl.gui_input.connect(func(e):
		# 桌面端 emulate_touch_from_mouse 会为鼠标点击生成合成触摸，跳过避免重复触发
		if Input.is_emulating_touch_from_mouse() and (e is InputEventScreenTouch or e is InputEventScreenDrag):
			ctrl.accept_event()
			return
		if e is InputEventScreenTouch:
			if e.pressed:
				action.call()
			ctrl.accept_event()
		elif e is InputEventScreenDrag:
			ctrl.accept_event()
		elif e is InputEventMouseButton or e is InputEventMouseMotion:
			ctrl.accept_event()
			# 移动端由 emulate_mouse_from_touch 产生合成鼠标事件，触摸分支已处理，这里跳过
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed and not Input.is_emulating_mouse_from_touch():
				action.call()
	)

func _create_info_labels():
	# 电脑版与手机完全一致：顶部/右上/头像等布局两端统一
	# 顶部信息带右锚定：紧贴推荐装备左侧，向左展开；中间让出目标信息面板的位置
	var RIGHT_X := 1.0

	# === 战况信息带（顶右侧，可点击打开英雄面板）：击杀比分+经济对比板块整体×2 ===
	team_stats_bg = Panel.new()
	team_stats_bg.anchor_left = RIGHT_X; team_stats_bg.anchor_right = RIGHT_X
	# 2400 宽画布：右缘 2029（推荐装备左缘 2038），左缘 1619；目标面板占 1200..1605
	team_stats_bg.offset_left = -781; team_stats_bg.offset_top = 6
	team_stats_bg.offset_right = -371; team_stats_bg.offset_bottom = 196
	_apply_panel_style(team_stats_bg, 0.62)
	_connect_tap_to_action(team_stats_bg, Callable(self, "toggle_hero_detail"))
	add_child(team_stats_bg)

	time_chip = Panel.new()
	time_chip.anchor_left = RIGHT_X; time_chip.anchor_right = RIGHT_X
	time_chip.offset_left = -776; time_chip.offset_top = 8
	time_chip.offset_right = -526; time_chip.offset_bottom = 52
	_apply_panel_style(time_chip, 0.62)
	_connect_tap_to_action(time_chip, Callable(self, "toggle_hero_detail"))
	add_child(time_chip)
	game_time_label = Label.new()
	game_time_label.anchor_left = RIGHT_X; game_time_label.anchor_right = RIGHT_X
	game_time_label.offset_left = -776; game_time_label.offset_top = 8
	game_time_label.offset_right = -526; game_time_label.offset_bottom = 52
	game_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(game_time_label, 24, Color.WHITE)
	add_child(game_time_label)

	# K/D/A（并入战况带第一行右侧，解决与战况信息重叠的问题）
	kda_label = Label.new()
	kda_label.anchor_left = RIGHT_X; kda_label.anchor_right = RIGHT_X
	kda_label.offset_left = -773; kda_label.offset_top = 12
	kda_label.offset_right = -379; kda_label.offset_bottom = 48
	kda_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kda_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(kda_label, 20, Color.WHITE)
	add_child(kda_label)

	# 双方比分（战况带第二行）
	team_stats_label = RichTextLabel.new()
	team_stats_label.anchor_left = RIGHT_X; team_stats_label.anchor_right = RIGHT_X
	team_stats_label.offset_left = -766; team_stats_label.offset_top = 82
	team_stats_label.offset_right = -381; team_stats_label.offset_bottom = 142
	team_stats_label.fit_content = true
	team_stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rich_label_style(team_stats_label, 24)
	add_child(team_stats_label)

	# 主宰先锋波次（顶部信息带第三行，替代原先只在英雄面板底部显示的信息）
	vanguard_label = Label.new()
	vanguard_label.anchor_left = RIGHT_X; vanguard_label.anchor_right = RIGHT_X
	vanguard_label.offset_left = -781; vanguard_label.offset_top = 148
	vanguard_label.offset_right = -371; vanguard_label.offset_bottom = 186
	vanguard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vanguard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vanguard_label.visible = false
	_apply_label_style(vanguard_label, 20, UiKit.C_TEXT_DIM)
	add_child(vanguard_label)

	# FPS：顶部信息带内、计时下方留白处（不挡 K/D/A 与比分行）
	fps_label = Label.new()
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.position = Vector2(5, 50)
	fps_label.size = Vector2(120, 24)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(fps_label, 14, Color(0.55, 0.95, 0.65))
	fps_label.text = "FPS --"
	team_stats_bg.add_child(fps_label)

	# 电量 / 网络：顶部战况带内、FPS 右侧空白处（132..398 × 48..82 局部坐标，不压比分行）
	if _device_status == null:
		var ds := DeviceStatusArt.new()
		ds.name = "DeviceStatus"
		ds.position = Vector2(132, 48)
		ds.size = Vector2(266, 34)
		team_stats_bg.add_child(ds)
		_device_status = ds

	# === 金币（右上角，可点击打开商店）===
	# 稍向中心收，避免贴死角落
	var gold_left := -286.0; var gold_right := -40.0
	var gold_chip := Panel.new()
	gold_chip.anchor_left = 1.0; gold_chip.anchor_top = 0.0; gold_chip.anchor_right = 1.0
	# 金币芯片放大到 2 倍高度，字号取 HUD 正文档
	gold_chip.offset_left = gold_left; gold_chip.offset_top = 8
	gold_chip.offset_right = gold_right; gold_chip.offset_bottom = 62
	_apply_panel_style(gold_chip, 0.55)
	_connect_tap_to_action(gold_chip, Callable(self, "toggle_shop"))
	add_child(gold_chip)
	gold_label = Label.new()
	gold_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(gold_label, 23, UiKit.C_GOLD)
	gold_chip.add_child(gold_label)

	# === 推荐装备（紧贴金币芯片下方，旁边带“+”快速购买按钮）===
	# 金币芯片底边 y=45，推荐卡从 y=53 起，横向与金币区右对齐
	# 卡片式推荐位：品质图标 + 名称 + 价格/差额 + 金币进度条（原为一整行右对齐纯文本）
	# 展开宽度与金币 UI 对齐：246（金币 -286..-40），右侧仍留给“+”按钮
	var rec_left := -362.0; var rec_right := -116.0
	recommended_equip_label = Label.new()
	recommended_equip_label.visible = false
	add_child(recommended_equip_label)
	rec_card = RecItemCard.new()
	rec_card.anchor_left = 1.0; rec_card.anchor_top = 0.0; rec_card.anchor_right = 1.0
	rec_card.offset_left = rec_left; rec_card.offset_top = 70
	rec_card.offset_right = rec_right; rec_card.offset_bottom = 190
	rec_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rec_card)
	rec_card.buy_requested.connect(Callable(self, "buy_recommended"))
	buy_plus_btn = TouchActionButton.new()
	buy_plus_btn.label_text = "+"
	buy_plus_btn.label_font_size = 76.0      # 更大更醒目的“+”
	buy_plus_btn.color = Color(0.98, 0.84, 0.25, 0.95)
	buy_plus_btn.hold_to_act = false
	buy_plus_btn.emit_activated_on_press = true
	buy_plus_btn.activated.connect(Callable(self, "buy_recommended"))
	buy_plus_btn.anchor_left = 1.0; buy_plus_btn.anchor_top = 0.0
	buy_plus_btn.offset_left = -108; buy_plus_btn.offset_top = 79
	buy_plus_btn.offset_right = -12; buy_plus_btn.offset_bottom = 181
	buy_plus_btn.visible = false              # 初始隐藏，_update_recommended_equip 按金币刷新
	add_child(buy_plus_btn)
	# 两件都买得起时：直接在推荐卡位置竖排两张推荐卡（各推荐一件装备，点卡即买）
	rec_option_row = Control.new()
	rec_option_row.anchor_left = 1.0; rec_option_row.anchor_top = 0.0; rec_option_row.anchor_right = 1.0
	rec_option_row.offset_left = -362.0; rec_option_row.offset_top = REC_OPTION_TOP
	rec_option_row.offset_right = -362.0 + REC_OPTION_W
	rec_option_row.offset_bottom = REC_OPTION_TOP + (REC_OPTION_H + 8.0) * 2.0
	rec_option_row.visible = false
	add_child(rec_option_row)
	# 设置按钮：推荐装下面，点开调音量 / 发起投降
	settings_btn = Button.new()
	settings_btn.text = "设置"
	var mobile_ui := Config.on_mobile()
	var sw := 136.0 if mobile_ui else 92.0
	_settings_btn_h = 58.0 if mobile_ui else 36.0
	settings_btn.anchor_left = 1.0; settings_btn.anchor_top = 0.0; settings_btn.anchor_right = 1.0
	settings_btn.offset_left = -12.0 - sw; settings_btn.offset_top = 308
	settings_btn.offset_right = -12.0; settings_btn.offset_bottom = 308.0 + _settings_btn_h
	settings_btn.add_theme_font_override("font", UiKit.font())
	settings_btn.add_theme_font_size_override("font_size", 24 if mobile_ui else 16)
	settings_btn.add_theme_color_override("font_color", UiKit.C_TEXT)
	settings_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, false))
	settings_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, false))
	settings_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, false))
	settings_btn.pressed.connect(_open_settings)
	add_child(settings_btn)

	# Buff 改为底部中央图标条：见 _create_buff_icons / _update_buff_icons（右上方已不再放文字面板）

	# 英雄头像：小地图右侧横向排列（两端统一，小地图均为 40..340），整体复位
	# 外层竖排：第一排=我方英雄（含复活读秒），第二排=已阵亡的敌方英雄，见 _update_respawn_widgets
	respawn_container = VBoxContainer.new()
	respawn_container.anchor_left = 0.0; respawn_container.anchor_top = 0.0
	# 环形头像×1.25 收到小地图右侧 (340,28)，行距收紧，避免与紧凑后的顶带挤在一起
	respawn_container.position = Vector2(500 + UiKit.safe_left(), 28 + UiKit.safe_top())
	respawn_container.add_theme_constant_override("separation", 6)
	add_child(respawn_container)

	# 刘海/挖孔避让：顶部信息带、金币、推荐装备、环形头像整体下移（桌面端 safe_top=0，无影响）
	var safe_top := UiKit.safe_top()
	if safe_top > 0.0:
		for top_ctrl in [team_stats_bg, game_time_label, kda_label, team_stats_label, gold_chip,
				recommended_equip_label, buy_plus_btn, rec_card, time_chip]:
			UiKit.apply_safe_top(top_ctrl)
		respawn_container.position.y += safe_top
# 全屏面板：吞掉未被子控件消费的触摸，防止漏到世界输入（_unhandled_input 移动指令）
func _block_touch_to_world(c: Control):
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenTouch or e is InputEventScreenDrag:
			c.accept_event()
	)

func _create_hero_detail_panel():
	# 全局英雄信息：遮罩 + RosterView（双列分路对位，纯绘制；主机与联机客户端共用）
	hero_detail_dim = ColorRect.new()
	hero_detail_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hero_detail_dim.color = Color(0, 0, 0, 0.4)
	hero_detail_dim.visible = false
	add_child(hero_detail_dim)
	_connect_tap_to_action(hero_detail_dim, Callable(self, "close_hero_detail"))
	hero_detail_panel = RosterView.new()
	hero_detail_panel.visible = false
	add_child(hero_detail_panel)
	hero_detail_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 关闭信号必须只执行“关闭”，不能复用 toggle：同一帧出现重复关闭事件时 toggle 会把它重新打开
	hero_detail_panel.closed_by_user.connect(close_hero_detail)

func _create_death_recap_panel():
	# 死亡面板：纯绘制视图（击杀者/复活读秒/承伤构成/来源排行/自动归因），主机与联机客户端共用
	# 放独立 CanvasLayer 105：压在 buff 图标、触控技能键和死亡压暗层之上
	death_recap_high_layer = CanvasLayer.new()
	death_recap_high_layer.name = "DeathRecapHighLayer"
	death_recap_high_layer.layer = UiKit.LAYER_RECAP
	add_child(death_recap_high_layer)
	death_recap_panel = DeathRecapView.new()
	death_recap_panel.visible = false
	death_recap_high_layer.add_child(death_recap_panel)
	death_recap_panel.closed_by_user.connect(_close_death_recap)

func _create_team_decision_panel():
	team_decision_panel = Panel.new()
	team_decision_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	# 中心锚点下用 offset 定义矩形；position 是父级绝对坐标，会把面板推出屏幕
	team_decision_panel.offset_left = -210
	team_decision_panel.offset_top = -500
	team_decision_panel.offset_right = 210
	team_decision_panel.offset_bottom = 500
	team_decision_panel.visible = false
	_apply_panel_style(team_decision_panel, 0.85)
	add_child(team_decision_panel)
	_block_touch_to_world(team_decision_panel)

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	team_decision_panel.add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "团队决策面板"
	_apply_label_style(title, 20, UiKit.C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	team_decision_labels["title"] = title

	# 游戏时间
	var game_time_lbl = Label.new()
	_apply_label_style(game_time_lbl, 14, Color.WHITE)
	vbox.add_child(game_time_lbl)
	team_decision_labels["game_time"] = game_time_lbl

	# 分推模式
	var mode_lbl = Label.new()
	_apply_label_style(mode_lbl, 16, Color.CYAN)
	vbox.add_child(mode_lbl)
	team_decision_labels["mode"] = mode_lbl

	# 经济差
	var gold_lbl = Label.new()
	_apply_label_style(gold_lbl, 14, Color.WHITE)
	vbox.add_child(gold_lbl)
	team_decision_labels["gold"] = gold_lbl

	# 龙状态
	var dragon_lbl = Label.new()
	_apply_label_style(dragon_lbl, 14, Color.WHITE)
	vbox.add_child(dragon_lbl)
	team_decision_labels["dragon"] = dragon_lbl

	# 分隔线
	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 我方标题
	var blue_title = Label.new()
	blue_title.text = "-- 我方 --"
	_apply_label_style(blue_title, 14, Color(0.0, 0.886, 1.0))
	vbox.add_child(blue_title)
	team_decision_labels["blue_title"] = blue_title

	# 蓝方英雄列表容器
	var blue_vbox = VBoxContainer.new()
	vbox.add_child(blue_vbox)
	team_decision_labels["blue_vbox"] = blue_vbox

	# 分隔线
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# 敌方标题
	var red_title = Label.new()
	red_title.text = "-- 敌方 --"
	_apply_label_style(red_title, 14, Color(1.0, 0.33, 0.264))
	vbox.add_child(red_title)
	team_decision_labels["red_title"] = red_title

	# 红方英雄列表容器
	var red_vbox = VBoxContainer.new()
	vbox.add_child(red_vbox)
	team_decision_labels["red_vbox"] = red_vbox


func _refresh_team_decision_panel():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.team_tactics:
		return
	var tt = battle.team_tactics

	# 游戏时间
	var gt = battle.game_time
	var gt_label := team_decision_labels.get("game_time") as Label
	if gt_label:
		gt_label.text = "时间: %02d:%02d" % [int(gt) / 60, int(gt) % 60]

	# 分推模式
	var mode_label := team_decision_labels.get("mode") as Label
	if mode_label:
		mode_label.text = "模式: " + tt.get_mode_name()

	# 经济差
	var gold_label := team_decision_labels.get("gold") as Label
	if gold_label:
		var diff = battle.team_player_gold - battle.team_enemy_gold
		if diff >= 0:
			gold_label.text = "经济: 领先 +%d" % diff
			gold_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			gold_label.text = "经济: 落后 %d" % diff
			gold_label.add_theme_color_override("font_color", Color.RED)

	# 龙状态
	var dragon_label := team_decision_labels.get("dragon") as Label
	if dragon_label:
		var dragon_alive = tt._is_dragon_alive()
		dragon_label.text = "龙: " + ("存活" if dragon_alive else "已击杀")
		dragon_label.add_theme_color_override("font_color", Color.ORANGE if dragon_alive else Color.GRAY)

	# 我方英雄列表
	var blue_vbox := team_decision_labels.get("blue_vbox") as VBoxContainer
	if blue_vbox:
		for child in blue_vbox.get_children():
			child.queue_free()
		for entity in battle.get_tree().get_nodes_in_group("heroes"):
			if not (entity is Hero) or entity.health <= 0:
				continue
			var h := entity as Hero
			if not Config.is_ally(h.team):
				continue
			var line := _format_hero_lane_line(h, tt.assignments.get(h, -1), h.is_ai)
			var lbl = Label.new()
			_apply_label_style(lbl, 12, Color(0.6, 0.9, 1.0) if h.is_ai else UiKit.C_GOLD)
			lbl.text = line
			blue_vbox.add_child(lbl)

	# 敌方英雄列表
	var red_vbox := team_decision_labels.get("red_vbox") as VBoxContainer
	if red_vbox:
		for child in red_vbox.get_children():
			child.queue_free()
		for entity in battle.get_tree().get_nodes_in_group("heroes"):
			if not (entity is Hero) or entity.health <= 0:
				continue
			var h := entity as Hero
			if Config.is_ally(h.team):
				continue
			var line := _format_hero_lane_line(h, tt.assignments.get(h, -1), h.is_ai)
			var lbl = Label.new()
			_apply_label_style(lbl, 12, Color(1.0, 0.7, 0.7) if h.is_ai else UiKit.C_GOLD)
			lbl.text = line
			red_vbox.add_child(lbl)


func _format_hero_lane_line(h: Hero, assigned_lane: int, is_ai: bool) -> String:
	var lane_str := "未分配"
	match assigned_lane:
		AiConfig.Lane.FARM: lane_str = "发育路"
		AiConfig.Lane.MID: lane_str = "MID"
		AiConfig.Lane.CLASH: lane_str = "对抗路"
		AiConfig.Lane.JUNGLE: lane_str = "打龙" if is_ai else "JUNGLE"
	var marker := "[AI]" if is_ai else "[P]"
	return "%s %s (%s) -> %s" % [marker, h.display_name, h.role, lane_str]


# ---------- 战报系统 ----------
## assists：[{name:String, team:int}]（可选；推塔时可含小兵）。英雄头像会自动带原初印记等级。
func show_kill_feed(actor: String, actor_team: int, desc: String, victim: String = "", victim_team: int = -1,
		assists: Array = []):
	var _rrec_feed = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_feed != null:
		var _as_rows: Array = []
		for a in assists:
			_as_rows.append({"name": str(a.get("name", "")), "team": int(a.get("team", 0))})
		_rrec_feed.call("note_feed", actor, actor_team, desc, victim, victim_team, _as_rows)
	# 原初印记等级在“事件发生这一刻”取样（排队延迟播出时不跟着变）
	var a_mark := _feed_mark_of(actor)
	var v_mark := _feed_mark_of(victim)
	var assist_rows: Array = []
	for a in assists:
		var nm := str(a.get("name", ""))
		if nm == "":
			continue
		assist_rows.append([nm, int(a.get("team", actor_team)), _feed_mark_of(nm)])
	# P3e：网络对局时把击杀/塔/龙/名刀/复活等全部战报经 NetSession 广播给接管客户端（全网单点入口）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.broadcast_kill_feed(actor, actor_team, desc, victim, victim_team,
			assist_rows, a_mark, v_mark)
	# 播报语音（host/离线本地单点；接管客户端由 NetKillFeed 各自触发）
	SfxManager.play_feed(actor, actor_team, desc, victim, victim_team)
	# 进队列：每条只播 1 条，前一条播满 2.0s 再播下一条
	_kf_queue.append({"actor": actor, "a_team": actor_team, "desc": desc,
		"victim": victim, "v_team": victim_team, "a_mark": a_mark, "v_mark": v_mark,
		"assists": assist_rows})
	while _kf_queue.size() > KF_QUEUE_MAX:
		_kf_queue.pop_front()
	_kf_pump()

## 英雄当前原初印记等级（0~6，每 100 原初积分 1 级；非英雄返回 0）
func _feed_mark_of(entity_name: String) -> int:
	if entity_name == "":
		return 0
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero and e.display_name == entity_name:
			return clampi(int((e as Hero).primitive_score / 100), 0, 6)
	return 0

## 单条播报出队：同一时刻只存在 1 条，播完（2.0s）自动接队首
func _kf_pump() -> void:
	if _kf_cur != null and is_instance_valid(_kf_cur):
		return
	if _kf_queue.is_empty():
		return
	var p: Dictionary = _kf_queue.pop_front()
	var panel := _create_kill_feed_panel(p)
	_kf_cur = panel
	kill_feed_slots = [panel]
	add_child(panel)
	_layout_kill_feed()
	var tw := create_tween()
	tw.tween_interval(KF_SHOW)
	tw.tween_property(panel, "modulate:a", 0.0, KF_FADE)
	tw.tween_callback(func():
		if is_instance_valid(panel):
			panel.queue_free()
		if _kf_cur == panel:
			_kf_cur = null
		kill_feed_slots.clear()
		_kf_pump())

func _layout_kill_feed():
	var rs := ui_scale()
	for p in kill_feed_slots:
		if not is_instance_valid(p):
			continue
		var h: float = KF_H + (KF_ASSIST_H if p.has_meta("kf_assist") else 0.0)
		p.offset_left = -KF_W * 0.5 * rs
		p.offset_right = KF_W * 0.5 * rs
		p.offset_top = KF_TOP * rs
		p.offset_bottom = p.offset_top + h * rs

func _create_kill_feed_panel(p: Dictionary) -> Panel:
	var actor: String = str(p.get("actor", ""))
	var actor_team: int = int(p.get("a_team", 0))
	var desc: String = str(p.get("desc", ""))
	var victim: String = str(p.get("victim", ""))
	var victim_team: int = int(p.get("v_team", -1))
	var assists: Array = p.get("assists", [])
	var panel = Panel.new()
	panel.z_index = UiKit.Z_HUD_TOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_panel_style(panel, 0.6)
	var box = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.custom_minimum_size = Vector2(0, KF_H * ui_scale())
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hbox)

	if actor != "":
		var actor_icon := _make_feed_icon(actor, actor_team, int(p.get("a_mark", 0)), 40)
		if actor_icon != null:
			hbox.add_child(actor_icon)
		var actor_label = Label.new(); actor_label.text = EntityIconArtScript.display_name(actor)
		_apply_label_style(actor_label, 24, _feed_team_color(actor_team))
		hbox.add_child(actor_label)
	var desc_label = Label.new(); desc_label.text = desc; _apply_label_style(desc_label, 24, Color.WHITE)
	hbox.add_child(desc_label)
	if victim != "":
		var victim_icon := _make_feed_icon(victim, victim_team, int(p.get("v_mark", 0)), 40)
		if victim_icon != null:
			hbox.add_child(victim_icon)
		var victim_label = Label.new(); victim_label.text = EntityIconArtScript.display_name(victim)
		_apply_label_style(victim_label, 24, _feed_team_color(victim_team))
		hbox.add_child(victim_label)
	# 第二行：助攻者图像（有助攻才加；仅推塔时可能含小兵）
	if not assists.is_empty():
		panel.set_meta("kf_assist", true)
		var arow = HBoxContainer.new()
		arow.alignment = BoxContainer.ALIGNMENT_CENTER
		arow.custom_minimum_size = Vector2(0, KF_ASSIST_H * ui_scale())
		arow.add_theme_constant_override("separation", 8)
		arow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(arow)
		var cap = Label.new(); cap.text = "助攻"; _apply_label_style(cap, 16, Color(0.72, 0.80, 0.94, 0.9))
		arow.add_child(cap)
		for a in assists:
			var ic := _make_feed_icon(str(a[0]), int(a[1]), int(a[2]), 30)
			if ic != null:
				arow.add_child(ic)
	return panel

func _feed_team_color(team: int) -> Color:
	if Config.is_ally(team):
		return Color(0.0, 0.886, 1.0)
	if team == Config.Team.PLAYER or team == Config.Team.ENEMY:
		return Color(1.0, 0.33, 0.264)
	return Color.PURPLE

func _make_feed_icon(entity_name: String, team: int, mark_level: int = 0, sz: float = 26.0) -> Control:
	var sp := EntityIconArtScript.spec_for(entity_name)
	if sp.is_empty():
		return null
	sp["mark"] = mark_level
	var px := sz * ui_scale()
	var ic := EntityIconControl.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.setup(sp, _feed_team_color(team))
	return ic

# ---------- 伤害/金币/治疗弹出 ----------
# 错开分布：同一位置多个数值时水平分散
# 同目标短时间多次伤害：数值向四周散开（8 方向环绕，绕满一圈半径再加一级）
func _get_stagger_offset(world_pos: Vector3) -> Vector2:
	var key = (world_pos * 10).round() / 10.0  # 0.1 精度取整
	if not _popup_offsets.has(key):
		_popup_offsets[key] = {"count": 0, "timer": 0.0}
	var info = _popup_offsets[key]
	info.timer = 0.35  # 重置窗口
	var idx = info.count
	info.count += 1
	if idx == 0:
		return Vector2.ZERO
	var ang := float(idx - 1) * TAU / 8.0
	var ring := 1.0 + float((idx - 1) / 8)
	var r := 20.0 * ring
	return Vector2(cos(ang) * r, sin(ang) * r)

func show_damage_number(world_pos: Vector3, damage: float, is_crit: bool, is_magic: bool, shielded: bool = false, true_dmg: bool = false):
	# 录像：把对局真实飘字数据记进录像（回放端用同一套数值/颜色规则重绘）
	if damage >= 1.0:
		var _rrec_pop = get_tree().get_first_node_in_group("replay_recorder")
		if _rrec_pop != null:
			_rrec_pop.call("note_popup", "dmg", world_pos, {"am": damage, "crit": is_crit, "mag": is_magic, "shield": shielded})
	var cam = get_viewport().get_camera_3d(); if not cam: return
	var screen_pos = cam.unproject_position(world_pos + Vector3.UP * 1.5)
	var dmg := int(damage)
	var rs := ui_scale()
	var fs := UiKit.damage_number_size(float(dmg), is_crit)
	var px := int(round(fs * rs))
	var label = Label.new(); label.text = str(dmg)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", px)
	# 数字配色：真伤红 / 护盾吸收白 / 法术品紫 / 物理暖橙 / 暴击亮金（描边跟着换深色）
	var col: Color = Color(1.0, 0.30, 0.26) if true_dmg else (Color(0.96, 0.97, 1.0) if shielded else (Color(1.0, 0.90, 0.45) if is_crit else (Color(0.74, 0.53, 1.0) if is_magic else Color(1.0, 0.76, 0.34))))
	var edge: Color = Color(0.30, 0.02, 0.02, 1.0) if true_dmg else (Color(0.10, 0.10, 0.14, 0.96) if shielded else (Color(0.40, 0.24, 0.02, 1.0) if is_crit else Color(0.12, 0.05, 0.02, 0.96)))
	label.add_theme_color_override("font_color", col)
	label.add_theme_color_override("font_outline_color", edge)
	# 描边按字号缩放：伤害数字大小差 16→60px，固定 3px 描边在大字上几乎看不出
	label.add_theme_constant_override("outline_size", clampi(int(round(fs * 0.22 * rs)), 3, 14))
	# 柔和投影：把数字从杂乱战场背景里托出来（暴击不加，避免和金描边糊成一圈）
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_x", maxi(1, int(round(fs * 0.05 * rs))))
	label.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(fs * 0.08 * rs))))
	label.add_theme_constant_override("shadow_outline_size", 0)
	var stagger_off: Vector2 = _get_stagger_offset(world_pos)
	# 暴击：在伤害数字左前方自绘四芒星爆点图标（fallback 字体无此字形，随 Label 一起上浮/淡出）
	if is_crit:
		var mark := CritMark.new()
		var _iw := px * 0.62
		var _ih := px * 0.7
		mark.size = Vector2(_iw, _ih)
		label.add_child(mark)
	add_child(label)
	label.size = label.get_combined_minimum_size()
	if is_crit and label.get_child_count() > 0:
		var mark: Control = label.get_child(0)
		mark.position = Vector2(-(mark.size.x + px * 0.22), (label.size.y - mark.size.y) * 0.5 + px * 0.06)
	label.position = screen_pos - label.size * 0.5 + stagger_off
	# 弹入：先放大再回弹（暴击弹得更狠），之后匀速上浮淡出，比纯平移更有打击感
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.45, 1.45)
	var rise: float = (66.0 if is_crit else 54.0) * rs
	var tween = create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tween2 = create_tween()
	tween2.tween_property(label, "position:y", label.position.y - rise, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween2.parallel().tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.55)
	tween2.tween_callback(label.queue_free)

func show_gold_popup(world_pos: Vector3, amount: int, own_kill := false, last_hit := false):
	var _rrec_gold = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_gold != null and amount > 0:
		_rrec_gold.call("note_popup", "gold", world_pos, {"am": amount, "own": own_kill, "lh": last_hit})
	var cam = get_viewport().get_camera_3d(); if not cam: return
	var screen_pos = cam.unproject_position(world_pos + Vector3.UP * 1.5)
	var stagger_off: Vector2 = _get_stagger_offset(world_pos)
	var rs := ui_scale()
	# 金币弹出统一用矢量徽标：自己击杀=金色小剑+大号，助攻/自然金币=👍+金币图标+常规号
	var pop := ValuePopup.new()
	if own_kill:
		SfxManager.play_ui_sfx("last_hit" if last_hit else "coin")
		pop.setup("+%dg" % amount, "sword", UiKit.C_GOLD, rs, 34)
	else:
		# 非补刀金币（助攻/兵线/自然经济）：数值前面画一个竖大拇指
		pop.setup("+%dg" % amount, "thumb", Color(1.0, 0.87, 0.40), rs, 30, "coin")
	pop.position = screen_pos - pop.size / 2 + stagger_off
	add_child(pop)
	pop.pivot_offset = pop.size * 0.5
	pop.scale = Vector2(1.3, 1.3)
	var tween = create_tween()
	tween.tween_property(pop, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 金币弹出统一停留约2秒：上浮1.4s、末段0.6s淡出
	var tween2 = create_tween()
	tween2.tween_property(pop, "position:y", pop.position.y - 55, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween2.parallel().tween_property(pop, "modulate:a", 0.0, 0.6).set_delay(1.4)
	tween2.tween_callback(pop.queue_free)

func show_heal_number(world_pos: Vector3, amount: int):
	var _rrec_heal = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_heal != null and amount > 0:
		_rrec_heal.call("note_popup", "heal", world_pos, {"am": amount})
	var cam = get_viewport().get_camera_3d(); if not cam: return
	var screen_pos = cam.unproject_position(world_pos + Vector3.UP * 1.5)
	var stagger_off: Vector2 = _get_stagger_offset(world_pos)
	var rs := ui_scale()
	# 治疗：绿色十字徽标 + 数值，比纯绿字更易和伤害数字区分
	var pop := ValuePopup.new()
	pop.setup("+%d" % amount, "cross", Color(0.50, 1.0, 0.60), rs, 26)
	pop.position = screen_pos - pop.size / 2 + stagger_off
	add_child(pop)
	pop.pivot_offset = pop.size * 0.5
	pop.scale = Vector2(1.25, 1.25)
	var tween = create_tween()
	tween.tween_property(pop, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tween2 = create_tween()
	tween2.tween_property(pop, "position:y", pop.position.y - 46, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween2.parallel().tween_property(pop, "modulate:a", 0.0, 0.55).set_delay(0.35)
	tween2.tween_callback(pop.queue_free)

# ---------- 商店系统 ----------
func _open_shop():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	# 面板常驻：已建过则直接复用（刷新数据），不再重建节点
	if shop_ui != null and is_instance_valid(shop_ui):
		shop_ui.visible = true
		UiKit.show_panel(shop_ui, 0.16)
		_refresh_shop_all()
		return
	if shop_selected_category == "": shop_selected_category = "物理"
	var rs := ui_scale()
	shop_ui = Control.new()
	shop_ui.z_index = UiKit.Z_PANEL
	shop_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 遮罩（点击关闭）
	var dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.4)
	shop_ui.add_child(dim)
	_connect_tap_to_action(dim, Callable(self, "_close_shop"))

	# 居中对称抽屉：宽度不超过可视区（窄屏/平板不再左右溢出）
	var vw := get_viewport().get_visible_rect().size.x
	var drawer_w := minf(2280.0, vw - 48.0)
	# 装备网格两列宽度：ScrollContainer 宽度的一半（否则卡片最小宽度为 0，两列会叠在一起导致文字重叠）
	shop_card_w = maxf(240.0 * rs, (drawer_w * 0.55 - 26.0 * rs) * 0.5)
	# 三块区域共用一套纵向基准，避免分类栏压住网格、底部已购栏压住详情购买条
	var tabs_top := 56.0
	var tab_h := 42.0 * rs
	var content_top := tabs_top + tab_h + 12.0
	# 已购栏按左列可用宽度计算六格尺寸：比原来 46×42 的图标大很多，并填满整条底板
	var owned_gap := 8.0 * rs
	var owned_caption := 78.0 * rs
	var owned_inner_w := drawer_w * 0.55 - 20.0 * rs
	var owned_slot := clampf((owned_inner_w - owned_caption - owned_gap * 6.0) / 6.0, 64.0, 150.0)
	shop_owned_slot = owned_slot
	var owned_area_h := owned_slot + 18.0
	var drawer = Panel.new()
	drawer.anchor_left = 0.5; drawer.anchor_right = 0.5
	drawer.anchor_top = 0.0; drawer.anchor_bottom = 1.0
	drawer.offset_left = -drawer_w * 0.5; drawer.offset_right = drawer_w * 0.5
	drawer.offset_top = 0; drawer.offset_bottom = 0
	_apply_panel_style(drawer, 0.90)
	shop_ui.add_child(drawer)
	UiKit.make_backdrop(drawer, UiKit.C_TEAM0, 0.55)

	# 标题：商店 + 金币 + 可买件数
	shop_title_label = Label.new()
	shop_title_label.position = Vector2(22 * rs, 10)
	_apply_label_style(shop_title_label, 20, UiKit.C_GOLD)
	drawer.add_child(shop_title_label)
	_refresh_shop_title()

	# 关闭按钮
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.anchor_left = 1.0; close_btn.anchor_top = 0.0; close_btn.anchor_right = 1.0
	close_btn.offset_left = -56; close_btn.offset_top = 6
	close_btn.offset_right = -6; close_btn.offset_bottom = 56
	close_btn.add_theme_font_size_override("font_size", int(round(26 * ui_scale())))
	close_btn.add_theme_color_override("font_color", UiKit.C_TEXT)
	for _st in ["normal", "hover", "pressed"]:
		close_btn.add_theme_stylebox_override(_st, UiKit.skin_button(_st, UiKit.C_DANGER, false))
	close_btn.pressed.connect(Callable(self, "_close_shop"))
	drawer.add_child(close_btn)

	# 分类栏（含「推荐」页，按钮显示可买件数）：固定高度、均分整行，避免分类按钮溢出/压住网格
	shop_category_container = HBoxContainer.new()
	shop_category_container.anchor_left = 0.0; shop_category_container.anchor_top = 0.0
	shop_category_container.anchor_right = 1.0
	shop_category_container.offset_left = 20.0 * rs
	shop_category_container.offset_right = -20.0 * rs
	shop_category_container.offset_top = tabs_top
	shop_category_container.offset_bottom = tabs_top + tab_h
	shop_category_container.add_theme_constant_override("separation", int(6 * rs))
	drawer.add_child(shop_category_container)
	_rebuild_shop_categories()

	# 左侧 2 列装备网格
	var scroll = ScrollContainer.new()
	scroll.anchor_left = 0.02; scroll.anchor_right = 0.57
	scroll.anchor_top = 0.0; scroll.anchor_bottom = 1.0
	scroll.offset_top = content_top
	scroll.offset_bottom = -(owned_area_h + 38.0)
	drawer.add_child(scroll)
	shop_item_grid = GridContainer.new()
	shop_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_item_grid.columns = 2
	shop_item_grid.add_theme_constant_override("h_separation", int(6 * rs))
	shop_item_grid.add_theme_constant_override("v_separation", int(6 * rs))
	shop_grid_scroll = scroll
	scroll.add_child(shop_item_grid)

	# 右侧详情（固定头 + 滚动体 + 固定购买条）
	shop_detail_panel = Control.new()
	shop_detail_panel.anchor_left = 0.60; shop_detail_panel.anchor_right = 0.98
	shop_detail_panel.anchor_top = 0.0; shop_detail_panel.anchor_bottom = 1.0
	shop_detail_panel.offset_top = content_top
	shop_detail_panel.offset_bottom = -14.0
	drawer.add_child(shop_detail_panel)

	# 底部已拥有装备：独立底板 + 大图标，只占左列，不再与右侧购买条重叠
	var owned_panel := Panel.new()
	owned_panel.anchor_left = 0.02; owned_panel.anchor_right = 0.57
	owned_panel.anchor_top = 1.0; owned_panel.anchor_bottom = 1.0
	owned_panel.offset_top = -(owned_area_h + 18.0)
	owned_panel.offset_bottom = -8.0
	_apply_panel_style(owned_panel, 0.58)
	drawer.add_child(owned_panel)
	shop_owned_container = HBoxContainer.new()
	shop_owned_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_owned_container.offset_left = 10.0 * rs
	shop_owned_container.offset_right = -10.0 * rs
	shop_owned_container.offset_top = 8.0
	shop_owned_container.offset_bottom = -8.0
	shop_owned_container.add_theme_constant_override("separation", int(8 * rs))
	shop_owned_container.alignment = BoxContainer.ALIGNMENT_CENTER
	owned_panel.add_child(shop_owned_container)

	_refresh_shop_grid()
	_refresh_owned_items()
	_block_touch_to_world(shop_ui)
	add_child(shop_ui)
	UiKit.show_panel(shop_ui, 0.16)
func _item_category_of(item_id: String) -> String:
	var _cats := _shop_categories()
	for _c in _cats:
		if item_id in _cats[_c]:
			return _c
	return ""

# 分类选择回调
func _on_category_selected(cat: String):
	shop_selected_category = cat
	shop_selected_item = ""
	_refresh_category_styles()
	_refresh_shop_grid()

func _refresh_category_styles():
	if shop_category_container == null: return
	for btn in shop_category_container.get_children():
		if not (btn is Button): continue
		var bc: String = str(btn.get_meta("cat", ""))
		var sel := bc == shop_selected_category
		var tint: Color = _cat_tint(bc)
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4) if sel else tint.lightened(0.55))
		btn.add_theme_stylebox_override("normal", _cat_button_style(bc, sel))
		btn.add_theme_stylebox_override("hover", _cat_button_style(bc, sel))
		btn.add_theme_stylebox_override("pressed", _cat_button_style(bc, true))

func _cat_tint(cat: String) -> Color:
	if cat == "推荐": return UiKit.C_GOLD
	return _shop_cat_style(cat)[1]

func _shop_list_for(cat: String, hero) -> Array:
	if cat == "推荐": return _get_recommended_items(hero)
	return _shop_categories().get(cat, [])

func _shop_affordable_count(hero, cat: String) -> int:
	var n := 0
	for id in _shop_list_for(cat, hero):
		var it = ItemDatabase.get_item(str(id))
		if it.is_empty(): continue
		var tier: int = int(it.get("tier", 1))
		if hero.equipment_slots.has(str(id)) and tier >= 3: continue
		var pay: int = int(it["cost"])
		if it.has("requires"):
			pay = _shop_pay_for(str(id), hero)
		if int(hero.gold) >= pay: n += 1
	return n

func _refresh_shop_title():
	if shop_title_label == null: return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var hero = battle.hero
	var afford := 0
	for cat in _shop_categories().keys():
		afford += _shop_affordable_count(hero, str(cat))
	shop_title_label.text = "商店      金币 %d      可买 %d 件" % [int(hero.gold), afford]

func _rebuild_shop_categories():
	if shop_category_container == null: return
	for child in shop_category_container.get_children():
		shop_category_container.remove_child(child)
		child.queue_free()
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var hero = battle.hero
	var rs := ui_scale()
	var tab_h := 42.0 * rs
	var cats: Array = ["推荐"]
	for k in _shop_categories().keys(): cats.append(str(k))
	for cat in cats:
		var btn := Button.new()
		btn.set_meta("cat", cat)
		var cnt := _shop_affordable_count(hero, str(cat))
		btn.text = str(cat) if cnt <= 0 else "%s %d" % [str(cat), cnt]
		btn.custom_minimum_size = Vector2(0.0, tab_h)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", int(round(14 * rs)))
		btn.add_theme_color_override("font_outline_color", Color.BLACK)
		btn.add_theme_constant_override("outline_size", 1)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.pressed.connect(_on_category_selected.bind(str(cat)))
		shop_category_container.add_child(btn)
	_refresh_category_styles()

func _shop_quick_buy(item_id: String):
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	if not battle.hero.buy_equipment(item_id):
		_shop_toast("金币不足或装备栏已满", true)
		return
	SfxManager.play_ui_sfx("buy")
	var _bnm: String = str(ItemDatabase.get_item(item_id).get("name", item_id))
	_refresh_shop_all()
	_shop_toast("已购买 %s" % _bnm)

func _refresh_shop_all():
	_refresh_shop_title()
	_rebuild_shop_categories()
	_refresh_shop_grid()
	_refresh_owned_items()
	_update_shop_detail()

func _attr_tint(key: String) -> Color:
	if key in ["attack", "armor", "armor_pen_percent", "lifesteal", "crit_chance", "crit_damage", "attack_speed", "phys_pen", "speed", "per_speed", "hp_regen"]:
		return Color(1.0, 0.62, 0.28)
	if key in ["ability_power", "magic_resist", "magic_pen_percent", "spell_vamp", "per_ability_power", "mana", "mana_regen", "cooldown"]:
		return Color(0.72, 0.55, 1.0)
	return Color(0.45, 0.95, 0.62)

func _attr_glyph(key: String) -> String:
	match key:
		"attack", "phys_pen", "per_speed":
			return "sword"
		"armor_pen_percent", "magic_pen_percent":
			return "pierce"
		"crit_chance", "crit_damage", "hp_regen":
			return "cross"
		"attack_speed":
			return "bolt"
		"lifesteal", "spell_vamp", "health":
			return "heart"
		"armor", "magic_resist", "toughness":
			return "shield"
		"ability_power", "per_ability_power", "mana", "mana_regen", "cooldown":
			return "spark"
		"speed":
			return "chev"
	return "gem"

func _refresh_shop_grid():
	if not shop_item_grid: return
	var _sv: int = shop_grid_scroll.scroll_vertical if shop_grid_scroll != null else 0
	for child in shop_item_grid.get_children():
		shop_item_grid.remove_child(child)
		child.queue_free()
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var hero = battle.hero
	var rs := ui_scale()
	var rec: Array = _get_recommended_items(hero)
	var entries: Array = []
	for id in _shop_list_for(shop_selected_category, hero):
		var item = ItemDatabase.get_item(str(id))
		if item.is_empty(): continue
		var tier: int = int(item.get("tier", 1))
		var owned: bool = hero.equipment_slots.has(str(id))
		if owned and tier >= 3: continue   # 已成型大件不再上架
		var pay: int = int(item["cost"])
		if item.has("requires"):
			pay = _shop_pay_for(str(id), hero)
		entries.append({"id": str(id), "tier": tier, "cost": int(item["cost"]), "pay": pay,
			"name": str(item["name"]), "owned": owned, "rec": str(id) in rec})
	entries.sort_custom(func(a, b): return a.tier > b.tier if a.tier != b.tier else a.cost > b.cost)
	if entries.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "该分类暂无可购买装备"
		_apply_label_style(empty_lbl, 16, Color(0.7, 0.75, 0.85))
		shop_item_grid.add_child(empty_lbl)
		return
	# 选择记忆：当前选中不在列表里才回退到第一件可买
	var keep := false
	for e in entries:
		if str(e.id) == shop_selected_item: keep = true
	if not keep:
		var first_id := ""
		for e in entries:
			if int(e.pay) <= int(hero.gold):
				first_id = str(e.id); break
		if first_id == "": first_id = str(entries[0].id)
		shop_selected_item = first_id
	shop_grid_ids.clear()
	for e in entries:
		shop_grid_ids.append(str(e.id))
	for e in entries:
		var id: String = str(e.id)
		var tier: int = int(e.tier)
		var pay: int = int(e.pay)
		var afford: bool = int(hero.gold) >= pay
		var is_sel: bool = id == shop_selected_item
		var owned: bool = bool(e.owned)
		var is_rec: bool = bool(e.rec)
		var card := Button.new()
		card.custom_minimum_size = Vector2(shop_card_w, 86 * rs)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("normal", _item_card_style(tier, is_sel))
		card.add_theme_stylebox_override("hover", _item_card_style(tier, true))
		card.add_theme_stylebox_override("pressed", _item_card_style(tier, true))
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if not afford:
			card.modulate = Color(0.64, 0.66, 0.72)
		card.pressed.connect(_on_shop_item_selected.bind(id))
		shop_item_grid.add_child(card)
		# 图标（统一品质色 item_icon，与推荐装/装备栏/英雄面板一致）
		var ib := ItemIconBox.new()
		ib.position = Vector2(10 * rs, 16 * rs)
		ib.size = Vector2(54 * rs, 54 * rs)
		ib.item_name = str(e.name)
		ib.tier = tier
		ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(ib)
		# 名称
		var nm := Label.new()
		nm.text = str(e.name)
		nm.position = Vector2(74 * rs, 10 * rs)
		nm.size = Vector2(220 * rs, 22 * rs)
		_apply_label_style(nm, 16, Color.WHITE)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(nm)
		# 价格
		var pr := Label.new()
		pr.text = ("差价 %d 金" % pay) if pay < int(e.cost) else ("%d 金" % pay)
		pr.position = Vector2(74 * rs, 34 * rs)
		_apply_label_style(pr, 13, Color(1.0, 0.82, 0.3) if afford else Color(1.0, 0.45, 0.40))
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pr)
		# 状态行：推荐 / 可合成 / 已拥有 / 买不起
		var tag := ""
		var tag_col := Color(0.62, 0.72, 0.86)
		if is_rec:
			tag = "★推荐"
			tag_col = UiKit.C_GOLD
		elif pay < int(e.cost):
			tag = "可合成"
			tag_col = Color(0.45, 1.0, 0.5)
		elif owned:
			tag = "已拥有"
			tag_col = Color(0.45, 1.0, 0.5)
		elif not afford:
			tag = "金币不足"
			tag_col = Color(1.0, 0.5, 0.42)
		if tag != "":
			var tg := Label.new()
			tg.text = tag
			tg.position = Vector2(74 * rs, 58 * rs)
			_apply_label_style(tg, 12, tag_col)
			tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(tg)
		# 快捷购买按钮
		var qb := Button.new()
		qb.text = "买"
		qb.anchor_left = 1.0
		qb.anchor_right = 1.0
		qb.anchor_top = 0.5
		qb.anchor_bottom = 0.5
		qb.offset_left = -80 * rs
		qb.offset_top = -16 * rs
		qb.offset_right = -8 * rs
		qb.offset_bottom = 16 * rs
		qb.add_theme_font_size_override("font_size", int(round(15 * rs)))
		qb.focus_mode = Control.FOCUS_NONE
		if afford:
			for _q in ["normal", "hover", "pressed"]:
				qb.add_theme_stylebox_override(_q, UiKit.skin_button(_q, UiKit.C_GOLD, true))
			qb.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
			qb.pressed.connect(_shop_quick_buy.bind(id))
		else:
			qb.disabled = true
			qb.text = "差%d" % (pay - int(hero.gold))
			qb.add_theme_stylebox_override("disabled", UiKit.skin_button("normal", Color(0.30, 0.32, 0.38), true))
			qb.add_theme_color_override("font_disabled_color", Color(0.72, 0.75, 0.82))
		card.add_child(qb)
	_update_shop_detail()
	if shop_grid_scroll != null:
		shop_grid_scroll.set_deferred("scroll_vertical", _sv)

func _on_shop_item_selected(item_id: String):
	shop_selected_item = item_id
	_update_shop_detail()
	_refresh_shop_selection_styles()   # 高亮跟随点击/键盘选择（原来只有详情刷新，卡片边框停在旧装备）

## 只重刷卡片选中态样式（比重建整个网格便宜，且不丢滚动位置）
func _refresh_shop_selection_styles() -> void:
	if shop_item_grid == null:
		return
	var cards: Array = []
	for ch in shop_item_grid.get_children():
		if ch is Button:
			cards.append(ch)
	for i in range(mini(cards.size(), shop_grid_ids.size())):
		var card: Button = cards[i]
		var it: Dictionary = ItemDatabase.get_item(str(shop_grid_ids[i]))
		var tier: int = int(it.get("tier", 1))
		var sel: bool = str(shop_grid_ids[i]) == shop_selected_item
		card.add_theme_stylebox_override("normal", _item_card_style(tier, sel))
		card.add_theme_stylebox_override("hover", _item_card_style(tier, true))
		card.add_theme_stylebox_override("pressed", _item_card_style(tier, true))

func _update_shop_detail():
	if not shop_detail_panel: return
	for child in shop_detail_panel.get_children(): child.queue_free()
	var item = ItemDatabase.get_item(shop_selected_item)
	if item.is_empty(): return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var hero = battle.hero
	var rs := ui_scale()
	var tier: int = int(item.get("tier", 1))
	var tcol: Color = _shop_tier_color(tier)
	var owned: bool = hero.equipment_slots.has(shop_selected_item)

	# 固定头部：图标 + 品级/名称 + 总价/实付
	var head := HBoxContainer.new()
	head.anchor_right = 1.0
	head.offset_bottom = 92.0
	head.add_theme_constant_override("separation", int(14 * rs))
	shop_detail_panel.add_child(head)
	var icon := ItemIconBox.new()
	icon.custom_minimum_size = Vector2(72 * rs, 72 * rs)
	icon.item_name = str(item.get("name", shop_selected_item))
	icon.tier = tier
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 2)
	var tl := Label.new()
	tl.text = "[" + _shop_tier_name(tier) + "]  " + _item_category_of(shop_selected_item)
	_apply_label_style(tl, 13, tcol)
	info.add_child(tl)
	var nl := Label.new()
	nl.text = str(item["name"])
	_apply_label_style(nl, 24, Color.WHITE)
	info.add_child(nl)
	var pay: int = int(item["cost"])
	var comp_val := 0
	if item.has("requires"):
		var rem: Array = item["requires"].duplicate()
		for oid in hero.equipment_slots:
			var idx2: int = rem.find(oid)
			if idx2 >= 0:
				var ri = ItemDatabase.get_item(oid)
				if not ri.is_empty(): comp_val += int(ri["cost"])
				rem.remove_at(idx2)
		pay = maxi(int(item["cost"]) - comp_val, 0)
	var pl := Label.new()
	if comp_val > 0:
		pl.text = "总价 %d 金  ·  素材抵扣 %d  ·  实付 %d 金" % [int(item["cost"]), comp_val, pay]
	else:
		pl.text = "总价 %d 金" % int(item["cost"])
	_apply_label_style(pl, 15, Color(1.0, 0.82, 0.3))
	info.add_child(pl)
	head.add_child(info)

	# 滚动体
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_top = 96.0
	scroll.offset_bottom = -76.0
	shop_detail_panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", int(6 * rs))
	scroll.add_child(vbox)

	# 合成路径（图标化 + 已知素材进度）
	if item.has("requires"):
		var shl := Label.new()
		shl.text = "合成路径"
		_apply_label_style(shl, 14, Color(0.78, 0.86, 1.0))
		vbox.add_child(shl)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", int(8 * rs))
		flow.add_theme_constant_override("v_separation", int(6 * rs))
		for rid in item["requires"]:
			var rhas: bool = hero.equipment_slots.has(rid)
			var rbox := HBoxContainer.new()
			rbox.add_theme_constant_override("separation", 4)
			var ri2 := ItemIconBox.new()
			ri2.custom_minimum_size = Vector2(40 * rs, 40 * rs)
			var ritem = ItemDatabase.get_item(rid)
			ri2.item_name = str(ritem.get("name", rid)) if not ritem.is_empty() else str(rid)
			ri2.tier = int(ritem.get("tier", 1)) if not ritem.is_empty() else 1
			ri2.dim = not rhas
			rbox.add_child(ri2)
			var has_lbl := Label.new()
			has_lbl.text = "已合成" if rhas else "+%d金" % int(ritem.get("cost", 0))
			_apply_label_style(has_lbl, 12, Color(0.45, 1.0, 0.5) if rhas else Color(1.0, 0.5, 0.42))
			has_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rbox.add_child(has_lbl)
			flow.add_child(rbox)
		vbox.add_child(flow)
		if ItemDatabase.can_build(shop_selected_item, hero.equipment_slots):
			var ok_lbl := Label.new()
			ok_lbl.text = "可立即合成（仍需补 %d 金）" % _shop_pay_for(shop_selected_item, hero)
			_apply_label_style(ok_lbl, 13, Color(0.45, 1.0, 0.5))
			vbox.add_child(ok_lbl)
		var missing: Array = []
		for rid in item["requires"]:
			if not hero.equipment_slots.has(str(rid)):
				missing.append(str(rid))
		if not missing.is_empty():
			var mb := Button.new()
			mb.text = "买齐缺件 %d 件（%d 金）" % [missing.size(), _shop_missing_cost(missing)]
			mb.custom_minimum_size = Vector2(0, int(32 * rs))
			mb.add_theme_font_size_override("font_size", int(round(14 * rs)))
			for _ms in ["normal", "hover", "pressed"]:
				mb.add_theme_stylebox_override(_ms, UiKit.skin_button(_ms, Color(0.55, 0.85, 1.0), false))
			mb.pressed.connect(_shop_buy_missing.bind(shop_selected_item))
			vbox.add_child(mb)

	# 装备属性（图标徽章，自动换行）
	var attrs: Array = []
	for attr_data in [["attack","攻击力"],["ability_power","法强"],["attack_speed","攻速","%"],["crit_chance","暴击率","%"],["crit_damage","暴伤","%"],["armor","物防"],["magic_resist","法防"],["phys_pen","物穿"],["magic_pen","法穿"],["armor_pen_percent","物穿","%"],["magic_pen_percent","法穿","%"],["lifesteal","物吸","%"],["spell_vamp","法吸","%"],["speed","移速"],["per_speed","移速","%"],["cooldown","冷却","%"],["health","生命"],["mana","法力"],["hp_regen","回复"],["mana_regen","回蓝"],["toughness","韧性","%"],["per_ability_power","法强","%"]]:
		var key: String = str(attr_data[0])
		if item.has(key) and int(item[key]) != 0:
			attrs.append([str(attr_data[1]), int(item[key]), str(attr_data[2]) if attr_data.size() > 2 else "", _attr_tint(key), key])
	if not attrs.is_empty():
		vbox.add_child(HSeparator.new())
		var al := Label.new()
		al.text = "装备属性"
		_apply_label_style(al, 14, Color(0.78, 0.86, 1.0))
		vbox.add_child(al)
		var aflow := HFlowContainer.new()
		aflow.add_theme_constant_override("h_separation", int(18 * rs))
		aflow.add_theme_constant_override("v_separation", int(6 * rs))
		for a in attrs:
			var chip := HBoxContainer.new()
			chip.add_theme_constant_override("separation", 4)
			var ic := StatIcon.new()
			ic.shape = _attr_glyph(str(a[4]))
			ic.tint = a[3]
			ic.custom_minimum_size = Vector2(18 * rs, 18 * rs)
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(ic)
			var vl := Label.new()
			vl.text = "+%d%s %s" % [int(a[1]), str(a[2]), str(a[0])]
			_apply_label_style(vl, 13, (a[3] as Color).lightened(0.35))
			vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			chip.add_child(vl)
			aflow.add_child(chip)
		vbox.add_child(aflow)

	# 被动 / 主动
	if item.has("passive"):
		vbox.add_child(HSeparator.new())
		var pl2 := Label.new()
		pl2.text = "[被动] " + str(item["passive"])
		pl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_label_style(pl2, 13, Color(1.0, 0.92, 0.55))
		vbox.add_child(pl2)
	if item.has("active"):
		var al2 := Label.new()
		al2.text = "[主动] " + str(item["active"])
		al2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_apply_label_style(al2, 13, Color(0.62, 0.9, 1.0))
		vbox.add_child(al2)

	# 固定底部：购买 / 出售
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -66.0
	bar.offset_bottom = -6.0
	bar.add_theme_constant_override("separation", int(10 * rs))
	shop_detail_panel.add_child(bar)
	var can_buy_more: bool = (not owned) or tier < 3
	var buy := Button.new()
	buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy.add_theme_font_size_override("font_size", int(round(17 * rs)))
	if not can_buy_more:
		buy.text = "已拥有"
		buy.disabled = true
		buy.add_theme_stylebox_override("disabled", UiKit.skin_button("normal", Color(0.35, 0.38, 0.44), true))
	elif int(hero.gold) < pay:
		buy.text = "还差 %d 金" % (pay - int(hero.gold))
		buy.disabled = true
		buy.add_theme_stylebox_override("disabled", UiKit.skin_button("normal", Color(0.45, 0.22, 0.22), true))
		buy.add_theme_color_override("font_disabled_color", Color(1.0, 0.5, 0.45))
	else:
		buy.text = "购买 %d 金" % pay
		for _st in ["normal", "hover", "pressed", "disabled"]:
			buy.add_theme_stylebox_override(_st, UiKit.skin_button("normal" if _st == "disabled" else _st, UiKit.C_GOLD, true))
		buy.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
	buy.pressed.connect(Callable(self, "_on_shop_buy_sell"))
	bar.add_child(buy)
	shop_buy_sell_btn = buy
	shop_sell_btn = null
	if owned:
		var sell := Button.new()
		sell.text = "出售 +%d" % int(float(item["cost"]) * 0.7)
		sell.custom_minimum_size = Vector2(140 * rs, 0)
		sell.add_theme_font_size_override("font_size", int(round(16 * rs)))
		for _st2 in ["normal", "hover", "pressed"]:
			sell.add_theme_stylebox_override(_st2, UiKit.skin_button(_st2, Color(0.55, 0.75, 0.95), false))
		sell.pressed.connect(Callable(self, "_on_shop_sell"))
		bar.add_child(sell)
		shop_sell_btn = sell
func _on_shop_buy_sell():
	if shop_selected_item == "": return
	_on_buy_equipment(shop_selected_item)
	_refresh_shop_all()   # 金币变了：网格差价/金币不足标签、标题「可买」、分类角标一起刷新

# 出售按钮回调
func _on_shop_sell():
	if shop_selected_item == "": return
	var battle2 = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle2 == null or battle2.hero == null: return
	if not battle2.hero.equipment_slots.has(shop_selected_item):
		return   # 未拥有不出售（防止白拿金币）
	_sell_equipment(shop_selected_item)
	SfxManager.play_ui_sfx("sell")
	_refresh_shop_all()

func _on_buy_equipment(item_id: String):
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	if battle.hero.buy_equipment(item_id):
		SfxManager.play_ui_sfx("buy")

# ---------- 推荐装备 ----------
func _get_recommended_items(hero) -> Array:
	if cached_recommended_for != hero.display_name:
		# 选人界面「出装调整」确认过顺序时优先用自定义顺序
		var ov: Array = ItemDatabase.get_recommended_override(hero.display_name)
		if not ov.is_empty():
			cached_recommended_list = ov.duplicate()
		else:
			cached_recommended_list = ItemDatabase.get_recommended_items(hero.role)
		cached_recommended_for = hero.display_name
	return cached_recommended_list

# 获取推荐购买的下一个装备ID（优先合成 > 缺素材买素材 > 存钱）
func _get_best_recommended_item(hero: Hero) -> String:
	var list = _get_recommended_items(hero)

	# 槽满时：尝试消耗素材合成推荐大件（支持部分素材补差价）
	if hero.equipment_slots.size() >= Hero.MAX_EQUIPMENT_SLOTS:
		# 1. 遍历推荐列表，能合成就推荐
		for id in list:
			if hero.equipment_slots.has(id): continue
			var reqs = ItemDatabase.get_item(id).get("requires", [])
			for req_id in reqs:
				if hero.equipment_slots.has(req_id):
					return id  # 至少拥有1件素材，可以补差价合成
		# 2. 无法合成→升级已有的低级装备（遍历所有槽位）
		for owned_id in hero.equipment_slots:
			var owned_tier = ItemDatabase.get_item(owned_id).get("tier", 1)
			if owned_tier >= 3: continue
			if owned_tier == 2:
				for rid in list:
					if hero.equipment_slots.has(rid): continue
					if owned_id in ItemDatabase.get_item(rid).get("requires", []):
						return rid
			else:
				# Tier 1: 2步升级路径
				for rid in list:
					if hero.equipment_slots.has(rid): continue
					for mid_id in ItemDatabase.get_item(rid).get("requires", []):
						if hero.equipment_slots.has(mid_id): continue
						if owned_id in ItemDatabase.get_item(mid_id).get("requires", []):
							return mid_id
		# 3. 兜底：推荐列表中第一个未拥有的
		for id in list:
			if not hero.equipment_slots.has(id):
				return id
		return list[0]

	# 1. 素材齐全 → 推荐合成大件
	for id in list:
		if hero.equipment_slots.has(id): continue
		if ItemDatabase.can_build(id, hero.equipment_slots):
			return id

	# 2. 按合成路径推荐：沿路径从大件往叶子走，优先「素材齐、现在就能合成」的中间件，
	#    其次买得起的中间件，最后才退回最便宜的缺失叶子（不再一上来就推低级散件）
	for id in list:
		if hero.equipment_slots.has(id): continue
		var path: Array = []
		_collect_missing_path(hero, str(id), path)
		if path.is_empty(): continue
		for pid in path:
			if ItemDatabase.can_build(str(pid), hero.equipment_slots):
				return str(pid)
		for pid in path:
			if hero.gold >= _shop_pay_for(str(pid), hero):
				return str(pid)
		return str(path[path.size() - 1])

	return ""

# 合成路径上仍缺的节点（大件 → 叶子顺序），按每个父件里的需求份数计缺失
func _collect_missing_path(hero: Hero, id: String, out: Array) -> void:
	var item: Dictionary = ItemDatabase.get_item(id)
	if item.is_empty(): return
	var reqs: Array = item.get("requires", [])
	if reqs.is_empty():
		if not hero.equipment_slots.has(id):
			out.append(id)
		return
	var missing_child := false
	for r in reqs:
		if not _owns_enough(hero, str(r), reqs):
			missing_child = true
			break
	if not hero.equipment_slots.has(id):
		out.append(id)
	if not missing_child:
		return
	for r in reqs:
		var rid := str(r)
		if not _owns_enough(hero, rid, reqs):
			_collect_missing_path(hero, rid, out)

# 该件是否已按父件需求份数备齐（同名素材可能要求 2 份）
func _owns_enough(hero: Hero, id: String, reqs: Array) -> bool:
	var need := 0
	for r in reqs:
		if str(r) == id:
			need += 1
	var have := 0
	for oid in hero.equipment_slots:
		if str(oid) == id:
			have += 1
	return have >= need

func _find_missing_basic(hero: Hero, target_id: String) -> String:
	var target = ItemDatabase.get_item(target_id)
	if target.is_empty() or not target.has("requires"):
		return target_id
	for req_id in target.get("requires", []):
		var owned_count = 0
		for oid in hero.equipment_slots:
			if oid == req_id:
				owned_count += 1
		var needed_count = 0
		for r in target["requires"]:
			if r == req_id:
				needed_count += 1
		if owned_count < needed_count:
			return _find_missing_basic(hero, req_id)
	return target_id

func _update_recommended_equip():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var b := _compute_recommended_bundle(battle.hero)
	var can_buy := bool(b["show"])
	if recommended_equip_label:
		recommended_equip_label.text = b["text"] if b["text"] != "" else "推荐: -"
	recommended_equip_id = b["id"]
	recommended_equip_cost = b["cost"]
	if rec_card:
		rec_card.item_name = str(b.get("name", ""))
		rec_card.tier = int(b.get("tier", 2))
		rec_card.cost = int(b.get("cost", 0))
		rec_card.maxed = bool(b.get("maxed", false))
		rec_card.slot_full = bool(b.get("slot_full", false))
		rec_card.desc = str(b.get("desc", ""))
		rec_card.gold = int(battle.hero.gold) if battle.hero else 0
		# 金币不足自动收起成图标；买得起后自动展开（以卡片自身可买判定兜底）
		var affordable_now: bool = can_buy or rec_card.affordable()
		# 金币不足保持展开，卡面直接显示「还差 N 金」；收起只由玩家手动点按触发
		rec_card.set_collapsed_for_gold(false)
		rec_card.queue_redraw()
		can_buy = affordable_now
	if buy_plus_btn:
		buy_plus_btn.visible = can_buy and not (rec_card != null and rec_card.collapsed)
	# 两件素材都可买：两张推荐卡顶替单卡位置（各推荐一件装备），单卡与“+”都收起
	var opts_arr: Array = b.get("options", [])
	_sync_rec_options(opts_arr, int(battle.hero.gold))
	if rec_card:
		rec_card.visible = opts_arr.is_empty()
	if buy_plus_btn and not opts_arr.is_empty():
		buy_plus_btn.visible = false

# 推荐位双卡：两件素材都买得起时，在推荐卡位置竖排两张完整推荐卡（各推荐一件装备，点卡即买）。
# 只有 1 件可选时不走这里（单推荐卡 + “+” 已经能表达）。
func _sync_rec_options(opts: Array, gold: int) -> void:
	if rec_option_row == null:
		return
	var sig := ""
	for o in opts:
		sig += str(o["id"]) + "|"
	if sig != rec_option_sig:
		rec_option_sig = sig
		for c in rec_option_row.get_children():
			rec_option_row.remove_child(c)
			c.queue_free()
		for e in rec_option_btns:
			var old_plus = e.get("plus")
			if old_plus != null and is_instance_valid(old_plus):
				old_plus.queue_free()
		rec_option_btns.clear()
		var pi := 0
		for o in opts:
			var card := RecItemCard.new()
			card.name = "RecOption_%d" % pi
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			# 右锚定：与单推荐卡同宽 246（-362..-116），收起态从右往左收
			card.anchor_left = 1.0
			card.anchor_right = 1.0
			card.offset_left = -REC_OPTION_W
			card.offset_right = 0.0
			card.offset_top = float(pi) * (REC_OPTION_H + 8.0)
			card.offset_bottom = card.offset_top + REC_OPTION_H
			card.item_name = str(o["name"])
			card.tier = int(o.get("tier", 1))
			card.cost = int(o["cost"])
			card.gold = gold
			card.slot_full = false
			card.desc = str(o.get("desc", ""))
			card.tap_buy = true
			card.left_full = -REC_OPTION_W
			card.left_collapsed = -minf(REC_OPTION_W, 208.0)
			card.set_collapsed_for_gold(false)
			card.buy_requested.connect(_shop_quick_buy.bind(str(o["id"])))
			rec_option_row.add_child(card)
			# 每张卡右侧配同款黄色“+”快速购买（和单推荐卡一致）
			var plus := TouchActionButton.new()
			plus.name = "RecOptionPlus_%d" % pi
			plus.label_text = "+"
			plus.label_font_size = 76.0
			plus.color = Color(0.98, 0.84, 0.25, 0.95)
			plus.hold_to_act = false
			plus.emit_activated_on_press = true
			plus.anchor_left = 1.0; plus.anchor_top = 0.0
			plus.anchor_right = 1.0
			plus.offset_left = -108.0
			plus.offset_right = -12.0
			plus.offset_top = REC_OPTION_TOP + float(pi) * (REC_OPTION_H + 8.0) + 9.0
			plus.offset_bottom = plus.offset_top + 102.0
			plus.activated.connect(_shop_quick_buy.bind(str(o["id"])))
			add_child(plus)
			rec_option_btns.append({"card": card, "plus": plus, "cost": int(o["cost"])})
			pi += 1
		rec_option_row.visible = not opts.is_empty()
	for e in rec_option_btns:
		var c2: RecItemCard = e["card"]
		c2.gold = gold
		c2.set_collapsed_for_gold(false)
		c2.queue_redraw()
		var p2 = e.get("plus")
		if p2 != null and is_instance_valid(p2):
			p2.visible = gold >= int(e["cost"])   # 与单卡“+”同规则：买得起才显示
	# 设置按钮跟着双卡高度下移（单卡时保持原位）
	if settings_btn != null:
		var rows: int = rec_option_btns.size()
		var st_top: float = 308.0
		if rows > 0:
			st_top = REC_OPTION_TOP + float(rows) * (REC_OPTION_H + 8.0) + 8.0
		settings_btn.offset_top = st_top
		settings_btn.offset_bottom = st_top + _settings_btn_h

# ==================== 设置面板（音量 / 投降） ====================
func _master_volume_pct() -> float:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return 100.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)

func _apply_master_volume(pct: float) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, pct <= 0.5)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(pct, 0.0, 100.0) / 100.0))

func _settings_label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", UiKit.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

func _open_settings() -> void:
	if settings_panel != null and is_instance_valid(settings_panel):
		settings_panel.visible = true
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	settings_panel = Control.new()
	settings_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_panel.add_child(dim)
	var card := Panel.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -250.0; card.offset_right = 250.0
	card.offset_top = -215.0; card.offset_bottom = 215.0
	card.add_theme_stylebox_override("panel", UiKit.panel_style(0.98, 18.0))
	settings_panel.add_child(card)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 26.0; vb.offset_top = 20.0
	vb.offset_right = -26.0; vb.offset_bottom = -20.0
	vb.add_theme_constant_override("separation", 18)
	card.add_child(vb)
	var title := _settings_label("设置", 26, UiKit.C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	# 音量
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 12)
	vol_row.add_child(_settings_label("音量", 18, UiKit.C_TEXT))
	var slider := HSlider.new()
	slider.min_value = 0.0; slider.max_value = 100.0; slider.step = 1.0
	slider.value = _master_volume_pct()
	slider.custom_minimum_size = Vector2(270.0, 30.0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_row.add_child(slider)
	var vol_val := _settings_label("%d%%" % int(slider.value), 18, UiKit.C_EXP)
	vol_val.custom_minimum_size = Vector2(56.0, 0.0)
	vol_row.add_child(vol_val)
	vb.add_child(vol_row)
	# 键位布局：进入编辑模式后可直接拖动各个战斗按钮、调大小，保存后永久生效
	var layout_btn := Button.new()
	layout_btn.text = "自定义键位布局"
	layout_btn.custom_minimum_size = Vector2(0.0, 44.0)
	layout_btn.add_theme_font_override("font", UiKit.font())
	layout_btn.add_theme_font_size_override("font_size", 20)
	layout_btn.add_theme_color_override("font_color", UiKit.C_TEXT)
	layout_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, false))
	layout_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, false))
	layout_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, false))
	layout_btn.pressed.connect(func():
		_close_settings()
		TouchController.enter_layout_edit())
	vb.add_child(layout_btn)
	slider.value_changed.connect(func(v: float) -> void:
		vol_val.text = "%d%%" % int(v)
		_apply_master_volume(v))
	# 投降
	var sur := Button.new()
	sur.text = "发起投降"
	sur.custom_minimum_size = Vector2(0.0, 44.0)
	sur.add_theme_font_override("font", UiKit.font())
	sur.add_theme_font_size_override("font_size", 20)
	sur.add_theme_color_override("font_color", UiKit.C_TEXT)
	sur.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_DANGER, true))
	sur.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_DANGER, true))
	sur.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_DANGER, true))
	sur.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", UiKit.C_DANGER, true))
	sur.pressed.connect(_start_surrender_vote)
	var sur_hint := _settings_label("", 15, UiKit.C_TEXT_DIM)
	if battle != null:
		if battle.game_time < SURRENDER_MIN_TIME:
			sur.disabled = true
			sur_hint.text = "对局满 6:00 后才可发起投降"
		else:
			sur_hint.text = "需本队 5 人中至少 4 人同意"
	vb.add_child(sur)
	vb.add_child(sur_hint)
	surrender_status_label = _settings_label("", 16, UiKit.C_GOLD)
	surrender_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(surrender_status_label)
	# 关闭
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(0.0, 40.0)
	close.add_theme_font_override("font", UiKit.font())
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_color_override("font_color", UiKit.C_TEXT)
	close.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_TEAM0, false))
	close.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_TEAM0, false))
	close.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_TEAM0, false))
	close.pressed.connect(_close_settings)
	vb.add_child(close)

func _close_settings() -> void:
	if settings_panel != null and is_instance_valid(settings_panel):
		settings_panel.visible = false

## 发起投降：满 6 分钟 + 本队 5 人中 4 票同意才结束对局（单人/联机 host 的 AI 队友按局势表态）
func _start_surrender_vote() -> void:
	if surrender_vote_running:
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle == null or battle.game_over:
		return
	if battle.game_time < SURRENDER_MIN_TIME:
		_hud_toast("对局满 6:00 后才可发起投降", true)
		return
	surrender_vote_running = true
	var total := 1
	var yes := 1
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero and e.team == Config.player_team and e != battle.hero:
			total += 1
	var losing: bool = battle.team_player_gold < battle.team_enemy_gold or battle.team_player_kills < battle.team_enemy_kills
	_update_surrender_status(yes, total)
	for e2 in get_tree().get_nodes_in_group("heroes"):
		if not (e2 is Hero) or e2.team != Config.player_team or e2 == battle.hero:
			continue
		await get_tree().create_timer(randf_range(0.5, 1.0)).timeout
		if not is_instance_valid(self) or battle.game_over:
			surrender_vote_running = false
			return
		if losing or randf() < 0.3:
			yes += 1
		_update_surrender_status(yes, total)
	surrender_vote_running = false
	if yes >= SURRENDER_MIN_YES:
		_update_surrender_status(yes, total, "投降通过（%d/%d），对局结束" % [yes, total])
		_hud_toast("投降通过（%d/%d）" % [yes, total])
		_close_settings()
		battle.crystal_destroyed(Config.player_team)
	else:
		_update_surrender_status(yes, total, "投降未通过（%d/%d，需 4 票）" % [yes, total])
		_hud_toast("投降未通过（%d/%d 票）" % [yes, total], true)

func _update_surrender_status(yes: int, total: int, txt: String = "") -> void:
	if surrender_status_label == null or not is_instance_valid(surrender_status_label):
		return
	surrender_status_label.text = txt if txt != "" else "投降投票中… %d/%d" % [yes, total]

## HUD 轻提示（不依赖商店面板，淡出后销毁）
func _hud_toast(txt: String, bad: bool = false) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", UiKit.font())
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if bad else Color(0.60, 1.0, 0.66))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: Vector2 = get_viewport().get_visible_rect().size
	l.position = Vector2(vp.x * 0.5 - 300.0, vp.y * 0.22)
	l.custom_minimum_size = Vector2(600.0, 0.0)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(1.2)
	tw.tween_callback(l.queue_free)

# 推荐带数据打包（纯计算，供本类主界面 _update_recommended_equip 与 NetSession own.rb 快照广播单源调用；
# 客户端无 ItemDatabase 合成链，只把 text/cost/show/id 画出来）
func _compute_recommended_bundle(hero: Hero, with_options: bool = true) -> Dictionary:
	if hero == null:
		return {"id": "", "text": "", "cost": 0, "show": false, "name": "", "tier": 2, "maxed": false, "slot_full": false}
	var best := _get_best_recommended_item(hero)
	if best == "":
		return {"id": "", "text": "", "cost": 0, "show": false, "name": "", "tier": 2, "maxed": true, "slot_full": false}
	var item = ItemDatabase.get_item(best)
	if item.is_empty():
		return {"id": best, "text": "", "cost": 0, "show": false, "name": str(ItemDatabase.get_item(best).get("name", "")), "tier": int(ItemDatabase.get_item(best).get("tier", 2)), "maxed": false, "slot_full": hero.equipment_slots.size() >= Hero.MAX_EQUIPMENT_SLOTS}
	var list = _get_recommended_items(hero)
	var is_final = best in list
	var out_text := ""
	var out_cost := 0
	if is_final:
		# 推荐大件：显示合成差价（含部分素材）或全价
		var cost = item["cost"]
		var remaining = item.get("requires", []).duplicate()
		var owned_val = 0
		for oid in hero.equipment_slots:
			var idx = remaining.find(oid)
			if idx >= 0:
				var ri = ItemDatabase.get_item(oid)
				if not ri.is_empty(): owned_val += ri["cost"]
				remaining.remove_at(idx)
		cost = item["cost"] - owned_val
		var slot_full = hero.equipment_slots.size() >= Hero.MAX_EQUIPMENT_SLOTS
		if owned_val > 0:
			out_text = "推荐: %s (合成 %d金)" % [item["name"], cost]
			if slot_full: out_text += " [槽满升级]"
		elif slot_full:
			out_text = "推荐: %s (%d金) [槽满]" % [item["name"], cost]
		else:
			out_text = "推荐: %s (%d金) [存钱]" % [item["name"], cost]
		out_cost = cost
	else:
		# 推荐素材：显示是为哪个大件准备的
		var parent_name = ""
		for pid in list:
			if hero.equipment_slots.has(pid): continue
			var pitem = ItemDatabase.get_item(pid)
			if pitem.is_empty(): continue
			# 直接在推荐的requires中查找
			if best in pitem.get("requires", []):
				parent_name = pitem["name"]; break
			# 或是推荐的素材的素材（2级→3级的链）
			for req_id in pitem.get("requires", []):
				var req_reqs = ItemDatabase.get_item(req_id).get("requires", [])
				if best in req_reqs:
					parent_name = pitem["name"] + "(via " + ItemDatabase.get_item(req_id)["name"] + ")"; break
			if parent_name != "": break
		# 计算素材的花费（自身也可能有合成，按已拥有素材抵差价）
		var best_cost = item["cost"]
		if item.has("requires"):
			best_cost = _shop_pay_for(best, hero)
		out_cost = best_cost
		var cost_text = "%d金" % best_cost
		if best_cost != item["cost"]: cost_text += "(合成)"
		var suffix = " → " + parent_name if parent_name != "" else ""
		out_text = "推荐: %s (%s)%s" % [item["name"], cost_text, suffix]
	# 加号购买按钮：仅在金币足够买下推荐项时显示
	# 双卡自选：大件还买不起、而合成路径上有 2 件以上买得起时，列出最接近大件的两件让玩家挑
	var opts: Array = _recommended_options(hero, best, list) if with_options else []
	return {"id": best, "text": out_text, "cost": out_cost, "show": hero.gold >= out_cost, "name": str(item["name"]), "tier": int(item.get("tier", 2)), "maxed": false, "slot_full": hero.equipment_slots.size() >= Hero.MAX_EQUIPMENT_SLOTS, "options": opts,
		"desc": UiKit.item_effect(item)}

# 合成路径上「现在买得起」的节点清单（≥2 件才返回）：钱够大件时不给自选，直接推大件
func _recommended_options(hero: Hero, best_id: String, list: Array) -> Array:
	if best_id == "":
		return []
	var target_id := best_id if best_id in list else ""
	if target_id == "":
		for rid in list:
			if hero.equipment_slots.has(rid):
				continue
			if rid != best_id and _item_depends_on(rid, best_id):
				target_id = rid
				break
	if target_id == "":
		return []
	# 大件已经买得起：单卡直推大件，不弹自选
	if hero.gold >= _shop_pay_for(target_id, hero):
		return []
	var path: Array = []
	_collect_missing_path(hero, target_id, path)
	var opts: Array = []
	var seen := {}
	var order := 0
	for mid in path:
		var oid := str(mid)
		if seen.has(oid) or hero.equipment_slots.has(oid):
			order += 1
			continue
		seen[oid] = true
		var mi = ItemDatabase.get_item(oid)
		if mi.is_empty():
			continue
		var pay := _shop_pay_for(oid, hero)
		if hero.gold >= pay:
			opts.append({"id": oid, "name": str(mi.get("name", oid)), "cost": pay, "tier": int(mi.get("tier", 1)),
				"order": order, "desc": UiKit.item_effect(mi)})
		order += 1
	# 按合成路径顺序（越靠近大件越前）排序，不再按散件品质乱排
	opts.sort_custom(_opts_path_first)
	# 若某件是前面已列装备的合成件，就不再重复列（买大件已包含它）
	var kept: Array = []
	for o in opts:
		var oid := str(o.get("id", ""))
		var covered := false
		for k in kept:
			if _item_depends_on(str(k.get("id", "")), oid):
				covered = true
				break
		if not covered:
			kept.append(o)
	opts = kept
	if opts.size() < 2:
		return []
	if opts.size() > 2:
		opts.resize(2)   # 最多同时推荐 2 件
	return opts

# 推荐自选项排序：合成路径越靠前（越接近大件）越优先，同位置按差价大的排前
func _opts_path_first(a: Dictionary, b: Dictionary) -> bool:
	var oa := int(a.get("order", 99))
	var ob := int(b.get("order", 99))
	if oa != ob:
		return oa < ob
	return int(a.get("cost", 0)) > int(b.get("cost", 0))

func _item_depends_on(id: String, comp: String) -> bool:
	if id == comp:
		return true
	for req in ItemDatabase.get_item(id).get("requires", []):
		if _item_depends_on(str(req), comp):
			return true
	return false

func _collect_missing_leaves(hero: Hero, id: String, out: Array) -> void:
	var item = ItemDatabase.get_item(id)
	if item.is_empty():
		return
	var reqs: Array = item.get("requires", [])
	if reqs.is_empty():
		if not hero.equipment_slots.has(id):
			out.append(id)
		return
	for req in reqs:
		_collect_missing_leaves(hero, str(req), out)

func _sell_equipment(item_id: String):
	var hero = get_tree().get_first_node_in_group("battle_manager").hero
	if hero == null or not hero.equipment_slots.has(item_id):
		return
	var refund = int(ItemDatabase.get_item(item_id)["cost"] * 0.7)
	hero.gold += refund
	hero.equipment_slots.erase(item_id)
	hero._apply_equipment_bonuses()
	hero._recalculate_attributes()

func _refresh_owned_items():
	if not shop_owned_container: return
	for child in shop_owned_container.get_children():
		shop_owned_container.remove_child(child)
		child.queue_free()
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero: return
	var hero = battle.hero
	var rs := ui_scale()
	var cap := Label.new()
	cap.text = "已购装备"
	cap.custom_minimum_size = Vector2(78.0 * rs, 0.0)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(cap, 13, Color(0.74, 0.80, 0.90))
	shop_owned_container.add_child(cap)
	var ids: Array = []
	for id in hero.equipment_slots: ids.append(str(id))
	for i in range(Hero.MAX_EQUIPMENT_SLOTS):
		var has: bool = i < ids.size()
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(shop_owned_slot, shop_owned_slot)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		btn.add_theme_stylebox_override("hover", UiKit.skin_chip(UiKit.C_GOLD, 0.5, 6))
		btn.add_theme_stylebox_override("pressed", UiKit.skin_chip(UiKit.C_GOLD, 0.7, 6))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var box := ItemIconBox.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if has:
			var it = ItemDatabase.get_item(ids[i])
			box.item_name = str(it.get("name", ids[i])) if not it.is_empty() else str(ids[i])
			box.tier = int(it.get("tier", 1)) if not it.is_empty() else 1
			btn.tooltip_text = box.item_name
			btn.pressed.connect(_on_shop_item_selected.bind(ids[i]))
		btn.add_child(box)
		shop_owned_container.add_child(btn)

func _trigger_active_equip(hero: Hero, index: int):
	var ae_list = _get_active_equip_list(hero)
	if index >= ae_list.size(): return
	var ae = ae_list[index]
	if ae.cd_remaining > 0: return
	var id = ae.id
	if id == "golden_body":
		if hero.golden_body_cd <= 0 and not hero.golden_body_active:
			hero.golden_body_cd = 75.0
			hero.golden_body_active = true
			hero.golden_body_timer = 1.5
			hero.wd_timer = 1.5
			hero.stun_timer = 1.5
	elif id == "shadow_dart":
		hero.shadow_dart_cd = 60.0
		hero.shadow_dart_active = true
		var dur2 = 1.25 if hero.attack_range <= 400 else 2.5
		hero.shadow_dart_timer = dur2
		hero.shadow_dart_heal_tick = 0.0
		hero.visible = false
		hero.collision_layer = 0
		hero.apply_move_pct_buff("ms_haste", dur2, 0.3)
	elif id == "purify":
		hero.purify_cd = 75.0
		hero._apply_df_buff(0, 0.3, 3.0, false)
		hero._apply_df_buff(0, 0.3, 3.0, true)
	elif id == "sunspire_bow":
		hero.sunspire_active_cd = 75.0
		hero.sunspire_active = true
		hero.sunspire_active_timer = 5.0
		hero.apply_move_pct_buff("ms_haste", 5.0, 0.2)
		if hero.attack_range > 500:
			hero.multiply_attack_range_base(1.25)

# ---------- Buff 图标条 ----------
# 增益/减益 各占一个小图标，水平铺在屏幕底部中央：
# 图标 = 色环圆形 + 中央单字字形 + 剩余时间扇形遮罩（正上方顺时针覆盖“已流逝”部分，
#        剩余越少图标越暗）；点击图标弹出名称与效果说明，再次点击或效果结束自动关闭。
func _push_icon(cfgs: Array, key: String, glyph: String, tint: Color, bname: String,
		desc: String, rem: float = 0.0, tot: float = 0.0, steady: bool = false, sub: String = ""):
	cfgs.append({"key": key, "glyph": glyph, "tint": tint, "name": bname, "desc": desc,
		"remaining": rem, "total": tot, "steady": steady, "sub": sub})

# —— Buff 图标池辅助：创建/复用节点，并记录到 cur ——
func _apply_buff_cfg(c: Dictionary, cur: Dictionary) -> void:
	var key: String = c.key
	var node = buff_icon_nodes.get(key)
	if not node:
		node = BuffIcon.new()
		node.key = key
		node.z_index = UiKit.Z_HUD
		add_child(node)
		buff_icon_nodes[key] = node
		_connect_tap_to_action(node, Callable(self, "_on_buff_icon_tapped").bind(key))
	node.apply(c)
	cur[key] = node

# —— 单行水平居中排布 ——
func _layout_buff_row(cur: Dictionary, keys: Array, y: float, vw: float) -> void:
	if keys.size() == 0:
		return
	var row_w: float = keys.size() * BuffIcon.CELL_W
	var x0 := (vw - row_w) * 0.5
	for i in range(keys.size()):
		var key: String = keys[i]
		var node = cur.get(key)
		if not node:
			continue
		node.size = Vector2(BuffIcon.CELL_W, BuffIcon.CELL_H)
		node.position = Vector2(x0 + i * BuffIcon.CELL_W, y)
		node.visible = true
		node.selected = (key == selected_buff_key)

# —— 受击印记 → Buff 图标（按来源英雄+印记类型聚合；己方→下排，敌方→上排）——
func _push_marker_buffs(hero: Hero, top_cfgs: Array, bot_cfgs: Array) -> void:
	if hero.markers.size() == 0:
		return
	var groups: Dictionary = {}
	for m in hero.markers:
		var src = m.get("source")
		if src == null or not (src is GameEntity) or not is_instance_valid(src):
			continue
		var mtype: String = str(m.get("type", ""))
		var gk := str(src.get_instance_id()) + "|" + mtype
		if not groups.has(gk):
			groups[gk] = {"src": src, "type": mtype, "count": 0, "rem": 0.0}
		var g: Dictionary = groups[gk]
		g.count += 1
		g.rem = maxf(g.rem, float(m.get("timer", 0.0)))
	for gk in groups.keys():
		var g: Dictionary = groups[gk]
		var src = g.src
		var cfgs: Array = bot_cfgs if (src.team == hero.team) else top_cfgs
		var meta := _marker_meta(src, g.type)
		_push_icon(cfgs, "mark_" + gk, meta.glyph, meta.tint, meta.name,
			"%s（当前 %d 层）。" % [meta.desc, g.count], g.rem, g.rem, false, "%d层" % g.count)

# —— 印记元数据（字形/配色/名称/说明）；未知来源按阵营通用配色兜底 ——
func _marker_meta(src, mtype: String) -> Dictionary:
	var dn: String = src.display_name
	var tint := Color(0.9, 0.5, 0.4)
	var glyph := "印"
	var name := dn + "印记"
	var desc := "被 %s 施加了标记。" % dn
	if dn == "马可波罗":
		if mtype == "makeboluo_dd":
			glyph = "破"; tint = Color(1.0, 0.35, 0.3); name = "马可波罗·防御破坏"
			desc = "防御破坏（5 秒）：期间受到的攻击附加额外真实伤害，印记无法继续叠加"
		else:
			glyph = "真"; tint = Color(1.0, 0.66, 0.3); name = "马可波罗·真实印记"
			desc = "真实伤害印记（5 秒/层，最多 10 层）：叠满触发“防御破坏”"
	elif dn == "孙悟空" and mtype == "sunwukong_r":
		glyph = "箍"; tint = Color(1.0, 0.85, 0.4); name = "孙悟空·大圣神威"
		desc = "定海神针印记（6 秒/层，最多 3 层）：孙悟空普攻命中会消耗 1 层并附加高额伤害"
	elif dn == "孙尚香" and mtype == "sunshangxiang_w":
		glyph = "箭"; tint = Color(1.0, 0.62, 0.4); name = "孙尚香·箭袭"
		desc = "被箭羽标记（5 秒）：孙尚香命中带印记目标时附加额外伤害"
	elif dn == "亚瑟":
		glyph = "誓"; tint = Color(0.95, 0.8, 0.45); name = "亚瑟·誓约"
		desc = "誓约之斩印记（5 秒）：亚瑟攻击带印记目标时额外造成最大生命 1% 法术伤害"
	elif dn == "兰陵王":
		glyph = "刃"; tint = Color(0.85, 0.5, 1.0); name = "兰陵王·暗刃"
		desc = "暗刃标记（3 秒）：到期后爆炸造成物理伤害；被兰陵王命中会眩晕"
	elif dn == "妲己":
		glyph = "魅"; tint = Color(1.0, 0.55, 0.85); name = "妲己·魅火"
		desc = "魅惑印记（3 秒/层，最多 3 层）：每层削减魔法抗性"
	elif dn == "甄姬":
		glyph = "凝"; tint = Color(0.45, 0.78, 1.0); name = "甄姬·凝霜"
		desc = "凝霜印记（7 秒/层）：累计 3 层会被冰冻并受到额外伤害"
	elif dn == "安琪拉":
		glyph = "灼"; tint = Color(1.0, 0.55, 0.22); name = "安琪拉·灼烧"
		desc = "灼烧印记（3 秒/层，最多 10 层）：层数越高，后续受到的技能伤害越高"
	elif dn == "沈梦溪":
		glyph = "爆"; tint = Color(1.0, 0.72, 0.25); name = "沈梦溪·爆弹"
		desc = "爆弹印记（5 秒）：被沈梦溪再次命中时引爆并追加爆炸伤害"
	else:
		if src is Hero and Config.is_ally(src.team):
			tint = Color(0.4, 0.9, 1.0)
	return {"glyph": glyph, "tint": tint, "name": name, "desc": desc}

# —— 各英雄被动 / 强化普攻的计时状态 → 增益 Buff（仅当前操作英雄会命中）——
func _push_hero_passive_buffs(hero: Hero, bot: Array) -> void:
	# 通用：霸体 / 无敌
	if hero.bt_timer > 0.0:
		_push_icon(bot, "bt", "霸", Color(0.98, 0.9, 0.5), "霸体",
			"免疫控制（眩晕/击飞/冰冻/减速等），持续 %.1f 秒。" % hero.bt_timer, hero.bt_timer)
	if hero.wd_timer > 0.0:
		_push_icon(bot, "wd", "免", Color(1.0, 0.92, 0.4), "无敌",
			"免疫一切伤害，持续 %.1f 秒。" % hero.wd_timer, hero.wd_timer)
	# 太乙大招守护：被守护者（太乙自身 / 范围内血量最低队友）在守护期间阵亡将原地复活
	if hero.taiyi_protected and hero.taiyi_protect_timer > 0:
		_push_icon(bot, "hs_taiyi_prot", "命", Color(0.45, 0.95, 0.7), "太乙·守护",
			"被太乙真人大招守护：若在 %.1f 秒内阵亡将原地复活。" % hero.taiyi_protect_timer, hero.taiyi_protect_timer)
	match hero.display_name:
		"亚瑟":
			if hero.arthur_q_active:
				_push_icon(bot, "hs_arthur_q", "斩", Color(1.0, 0.82, 0.4), "誓约之斩",
					"强化普攻就绪：下一次普攻大幅增伤并使目标眩晕，剩余 %.1f 秒。" % hero.arthur_q_timer, hero.arthur_q_timer)
			if hero.arthur_w_active:
				_push_icon(bot, "hs_arthur_w", "旋", Color(0.98, 0.9, 0.55), "圣盾",
					"圣盾环绕自身旋转并持续伤害附近敌人，剩余 %.1f 秒。" % hero.arthur_w_timer, hero.arthur_w_timer)
		"刘禅":
			if hero.liushan_q_active:
				_push_icon(bot, "hs_liushan_q", "砸", Color(1.0, 0.8, 0.42), "小霸王护符",
					"强化普攻就绪：下一次普攻大幅增伤并击飞目标（对防御塔改为干扰+回血），剩余 %.1f 秒。" % hero.liushan_q_timer, hero.liushan_q_timer)
		"孙悟空":
			if hero.sunwukong_enhanced_aa:
				_push_icon(bot, "hs_wukong_aa", "棒", Color(1.0, 0.82, 0.3), "大圣·强化普攻",
					"强化普攻就绪：下一次普攻必定暴击并造成高额伤害。", 0.0, 0.0, true, "就绪")
			if hero.sunwukong_1_block_active:
				_push_icon(bot, "hs_wukong_block", "挡", Color(0.75, 0.85, 1.0), "护身咒法",
					"格挡窗口：下一次受到的敌方技能将被抵挡并获得护盾，剩余 %.1f 秒。" % hero.sunwukong_1_block_timer, hero.sunwukong_1_block_timer)
		"李白":
			if hero.libai_xia_active:
				_push_icon(bot, "hs_libai_xia", "侠", Color(0.85, 0.65, 1.0), "侠客行",
					"侠客行：获得强化效果，剩余 %.1f 秒。" % hero.libai_xia_timer, hero.libai_xia_timer)
			elif hero.libai_sword_auras > 0:
				_push_icon(bot, "hs_libai_aura", "剑", Color(0.7, 0.9, 1.0), "剑气",
					"普攻积累剑气，攒满 4 层触发“侠客行”（当前 %d 层，%.1f 秒后衰减）。" % [hero.libai_sword_auras, hero.libai_sword_timer],
					hero.libai_sword_timer, 0.0, false, "%d层" % hero.libai_sword_auras)
		"兰陵王":
			if hero.lanling_stealth_active:
				_push_icon(bot, "hs_lanling_stealth", "隐", Color(0.7, 0.65, 1.0), "隐袭",
					"进入隐身：敌人无法看见你、也不会锁定你，仍可阻挡敌人移动；受击不显形，主动攻击解除；期间自身视野+25%。剩余 %.1f 秒。" % hero.lanling_stealth_timer, hero.lanling_stealth_timer)
			if hero.lanling_as_buff_timer > 0:
				_push_icon(bot, "hs_lanling_as", "锋", Color(0.55, 0.95, 0.62), "影袭·攻速",
					"显形后攻击速度提升，持续 %.1f 秒。" % hero.lanling_as_buff_timer, hero.lanling_as_buff_timer)
		"张飞":
			if hero.zhangfei_transformed:
				_push_icon(bot, "hs_zhangfei_x", "变", Color(0.95, 0.42, 0.25), "狂兽真身",
					"变身后强化普攻与技能，剩余 %.1f 秒。" % hero.zhangfei_transform_timer, hero.zhangfei_transform_timer)
		"英睿":
			if hero.yingrui_transformed:
				_push_icon(bot, "hs_yingrui_x", "神", Color(0.45, 0.85, 1.0), "英睿·变身",
					"变身后普攻附加额外伤害，剩余 %.1f 秒。" % hero.yingrui_transform_timer, hero.yingrui_transform_timer)
			if hero.yingrui_elbow_ready:
				_push_icon(bot, "hs_yingrui_elbow", "肘", Color(0.95, 0.8, 0.45), "英睿·肘击",
					"被动就绪：下一次普攻变为肘击，造成高额伤害。", 0.0, 0.0, true, "就绪")
		"夏侯惇":
			if hero.xiahou_passive_active:
				_push_icon(bot, "hs_xiahou", "噬", Color(0.72, 0.85, 1.0), "噬目",
					"被动激活：技能命中敌人会回复生命，持续 %.1f 秒。" % hero.xiahou_passive_timer, hero.xiahou_passive_timer)
		"后羿":
			if hero.houyi_q_active:
				_push_icon(bot, "hs_houyi_q", "连", Color(1.0, 0.72, 0.3), "多重箭矢",
					"强化普攻：攻击额外分裂两支箭矢，持续 %.1f 秒。" % hero.houyi_q_timer, hero.houyi_q_timer)
			if hero.stat > 0:
				_push_icon(bot, "hs_houyi_p", "惩", Color(1.0, 0.8, 0.45), "惩戒射击",
					"被动叠层，3 层后普攻分裂三支箭（当前 %d 层）。" % int(hero.stat),
					hero.stat_timer, 0.0, false, "%d层" % int(hero.stat))
		"鲁班七号":
			if hero.luban_skill_enhanced or hero.luban_passive_stacks >= 5:
				_push_icon(bot, "hs_luban_ready", "扫", Color(0.92, 0.7, 0.95), "扫射",
					"强化普攻就绪：下一次普攻为扫射（穿透扇形攻击）。", 0.0, 0.0, true, "就绪")
			elif hero.luban_passive_stacks > 0:
				_push_icon(bot, "hs_luban_stack", "扫", Color(0.8, 0.62, 0.88), "火力压制",
					"普攻/技能叠加扫射层数，满 5 层触发扫射（当前 %d 层）。" % hero.luban_passive_stacks,
					0.0, 0.0, true, "%d层" % hero.luban_passive_stacks)
		"大禹":
			if hero.dayu_w_enhanced:
				_push_icon(bot, "hs_dayu_w", "禹", Color(0.55, 0.82, 1.0), "大禹·强化普攻",
					"强化下一次普攻：附加额外伤害并回复生命，剩余 %.1f 秒。" % hero.dayu_w_enhanced_timer, hero.dayu_w_enhanced_timer)
		"铠":
			if hero.stat >= 1:
				_push_icon(bot, "hs_kai", "刃", Color(0.95, 0.9, 0.6), "铠·强化普攻",
					"强化普攻就绪：下一次普攻冲向目标并附加额外伤害。", 0.0, 0.0, true, "就绪")
		"孙尚香":
			if hero.stat >= 1:
				_push_icon(bot, "hs_sunxiang", "弩", Color(1.0, 0.78, 0.35), "孙尚香·强化普攻",
					"翻滚后强化普攻就绪：下一次普攻大幅增伤（攻击范围+20%）。5秒内未出手将过期，剩余 %.1f 秒。" % hero.stat_timer, hero.stat_timer, 5.0)
		"马超":
			if hero.stat_timer > 0:
				_push_icon(bot, "hs_machao", "枪", Color(0.98, 0.9, 0.5), "马超·拾枪",
					"拾取标枪后点击普攻键即向该方向突进并贯穿沿途敌人，附加伤害、回复生命并缩短冷却。剩余强化普攻 %.1f 秒。" % hero.stat_timer, hero.stat_timer)
		"吕布":
			if hero.stat_timer > 0:
				_push_icon(bot, "hs_lvbu", "附", Color(1.0, 0.62, 0.3), "方天画斩",
					"武器附魔：普攻与技能附带真实伤害，持续 %.1f 秒。" % hero.stat_timer, hero.stat_timer)
		"不知火舞":
			if hero.stat_timer >= 5:
				_push_icon(bot, "hs_bzw", "扇", Color(0.95, 0.72, 0.5), "不知火舞·强化普攻",
					"强化普攻就绪：下一次普攻附带击退与额外法术伤害。", 0.0, 0.0, true, "就绪")
		"狄仁杰":
			if hero.stat > 0:
				_push_icon(bot, "hs_direnjie", "迅", Color(0.75, 0.88, 1.0), "狄仁杰·迅捷",
					"被动叠层，提升攻速（当前 %d 层，逐层衰减）。" % int(hero.stat),
					hero.stat_timer, 0.0, false, "%d层" % int(hero.stat))
		"元流之子":
			if hero.yuanliu_flow > 0:
				_push_icon(bot, "hs_yuanliu_flow", "流", Color(0.45, 0.92, 1.0), "万物为流·流",
					"持有“流”：普攻自动升级为贯穿弩箭，消耗 1 层；对沿途每个目标追加 80+20%%额外物攻（0.7^已命中 递减）伤害。当前 %d/9 层。" % hero.yuanliu_flow,
					0.0, 0.0, false, "%d/9" % hero.yuanliu_flow)
			var _yl_glv: int = hero.level
			var _yl_t: float = minf(float(_yl_glv - 1) / 14.0, 1.0)
			var _yl_desc := ""
			match hero.yuanliu_pick:
				"生机":
					_yl_desc = "额外生命上限 +%d（随等级成长，当前）" % int(300.0 + 300.0 * _yl_t)
				"穿心":
					_yl_desc = "额外物攻 +%d（随等级成长，当前）" % int(30.0 + 30.0 * _yl_t)
				"迅疾":
					_yl_desc = "移动速度 +%d（随等级成长，当前）" % int(round(12.5 + 12.5 * _yl_t))
				_:
					_yl_desc = "冷却缩减 +%d%%（随等级成长，当前）" % int(5.0 + 5.0 * _yl_t)
			_push_icon(bot, "hs_yuanliu_pick", hero.yuanliu_pick.left(1), Color(0.72, 0.95, 0.62), "万物为流·" + hero.yuanliu_pick,
				_yl_desc, 0.0, 0.0, true, "常驻")

func show_yuanliu_pick(hero: Hero, reopen: bool = false) -> void:
	# 元流之子·万物为流：开局泉水四选一（首次自动弹）；自家泉水中可点「流派·切换」重开（reopen=true）。
	# 首次打开置 yuanliu_picked 防重复自动弹；reopen 不加门槛。确认一律走 set_yuanliu_pick（先整条移除旧
	# 流派 buff 条目再重算，避免换向残留加成键导致属性翻倍）。
	if hero == null or not is_instance_valid(hero):
		return
	if not reopen:
		if hero.yuanliu_picked:
			return
		hero.yuanliu_picked = true
	_yl_panel_open = true
	var rs := ui_scale()
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var pw := 540.0 * rs
	var ph := 640.0 * rs
	# 中心锚点：用 offset 居中（position 是父级绝对坐标，会跑到左上角外）
	panel.offset_left = -pw * 0.5
	panel.offset_top = -ph * 0.5
	panel.offset_right = pw * 0.5
	panel.offset_bottom = ph * 0.5
	_apply_panel_style(panel, 0.92)
	_block_touch_to_world(panel)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 26.0 * rs
	vbox.offset_top = 16.0 * rs
	vbox.offset_right = -26.0 * rs
	vbox.offset_bottom = -16.0 * rs
	vbox.add_theme_constant_override("separation", 10.0 * rs)
	panel.add_child(vbox)
	var close_panel := func():
		_yl_panel_open = false
		if is_instance_valid(panel):
			panel.queue_free()
	var title := Label.new()
	title.text = "万物为流 · 泉水抉择" if not reopen else "万物为流 · 流派切换"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(title, 24, Color(0.55, 0.95, 1.0))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = ("元流之子执“流”而生：请选择被动强化路线。数值随英雄等级逐步成长，开局选定后仍可回到泉水随时切换。"
		if not reopen else
		"身处自家泉水：可随时更换被动强化路线，确认后立即生效；离泉后本次选择持续到下次回泉。")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(hint, 13, Color(1, 1, 1, 0.72))
	vbox.add_child(hint)
	var cur_pick: String = str(hero.yuanliu_pick)
	var opts: Array = [
		["生机", "额外最大生命 +300 → +600", Color(0.45, 0.95, 0.62)],
		["穿心", "额外物理攻击 +30 → +60", Color(1.0, 0.55, 0.38)],
		["迅疾", "移动速度 +12.5 → +25", Color(0.55, 0.9, 1.0)],
		["凝神", "冷却缩减 +5% → +10%", Color(0.8, 0.62, 1.0)],
	]
	for o in opts:
		var b := Button.new()
		var pick_name: String = o[0]
		var is_cur: bool = reopen and pick_name == cur_pick
		if is_cur:
			b.text = "√ 当前·【%s】  %s" % [o[0], o[1]]
		else:
			b.text = "【%s】  %s" % [o[0], o[1]]
		b.custom_minimum_size = Vector2(0, 92.0 * rs)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_apply_button_style(b)
		b.add_theme_font_size_override("font_size", int(round(16.0 * rs)))
		b.add_theme_color_override("font_color", o[2])
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.pressed.connect(func():
			if is_instance_valid(hero):
				hero.set_yuanliu_pick(pick_name)
			close_panel.call())
		vbox.add_child(b)
	if reopen:
		var cancel := Button.new()
		cancel.text = "取消"
		cancel.custom_minimum_size = Vector2(0, 64.0 * rs)
		_apply_button_style(cancel)
		cancel.add_theme_font_size_override("font_size", int(round(16.0 * rs)))
		cancel.pressed.connect(func(): close_panel.call())
		vbox.add_child(cancel)

# —— 元流之子·泉水流派切换钮（常驻）：自家泉水中可见，点击打开可重开的万物为流面板 ——
func _create_yuanliu_switch_btn():
	if _yl_switch_btn != null:
		return
	_yl_switch_btn = Button.new()
	# 右上角金币/推荐带下方空档（右侧一列，避开商店钮区/触控横带/小地图）；与联机客户端同坐标（CanvasLayer 61）
	_yl_switch_btn.anchor_left = 1.0; _yl_switch_btn.anchor_top = 0.0
	_yl_switch_btn.anchor_right = 1.0; _yl_switch_btn.anchor_bottom = 0.0
	_yl_switch_btn.offset_left = -268.0
	_yl_switch_btn.offset_top = 118.0
	_yl_switch_btn.offset_right = -12.0
	_yl_switch_btn.offset_bottom = 190.0
	_yl_switch_btn.text = "流派·切换"
	_apply_button_style(_yl_switch_btn)
	_yl_switch_btn.add_theme_font_size_override("font_size", 17)
	_yl_switch_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_yl_switch_btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	_yl_switch_btn.visible = false
	_yl_switch_btn.pressed.connect(_open_yuanliu_switch)
	add_child(_yl_switch_btn)

func _open_yuanliu_switch():
	if _yl_panel_open:
		return
	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm == null or bm.hero == null or not is_instance_valid(bm.hero):
		return
	show_yuanliu_pick(bm.hero, true)

func _update_yuanliu_switch_btn(hero: Hero) -> void:
	if _yl_switch_btn == null:
		return
	var want := is_instance_valid(hero) and hero.display_name == "元流之子" \
		and not _yl_panel_open and hero.health > 0.0 \
		and not hero.is_recalling and not hero.is_dead and hero.in_own_fountain()
	_yl_switch_btn.visible = want

func _create_buff_icons():
	buff_info_panel = Panel.new()
	buff_info_panel.name = "BuffInfoPanel"
	_apply_panel_style(buff_info_panel, 0.88)
	buff_info_panel.visible = false
	add_child(buff_info_panel)
	buff_info_title = Label.new()
	buff_info_title.position = Vector2(15, 10)
	buff_info_title.size = Vector2(BUFF_INFO_W - 30, 0)
	_apply_label_style(buff_info_title, 18, UiKit.C_GOLD)
	buff_info_panel.add_child(buff_info_title)
	buff_info_desc = Label.new()
	buff_info_desc.position = Vector2(15, 40)
	buff_info_desc.size = Vector2(BUFF_INFO_W - 30, 0)
	_apply_label_style(buff_info_desc, 14, Color.WHITE)
	buff_info_panel.add_child(buff_info_desc)

# —— 纯计算：收集当前英雄要展示的 buff 图标行配置（不触碰任何节点）。
# 主机 NetSession 调用它给被接管英雄生成 own.buffs（客户端触控 HUD 1:1 复刻本行 buff），
# 本机 _update_buff_icons 也调用它做绘制——两条路径同源、永不漂移。——
func collect_buff_rows(hero: Hero) -> Dictionary:
	# 本轮要显示的图标：上排 top_cfgs = 减益/控制/敌方印记；下排 bot_cfgs = 增益/己方印记
	var top_cfgs: Array = []
	var bot_cfgs: Array = []
	# jungle protection: during first 4 min a hero standing in the enemy zone
	# (closer to the enemy crystal, outside the river) deals 25% less damage.
	var jg_battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if jg_battle and jg_battle.game_time < 240.0 and BattleManager.in_enemy_jungle_zone(hero.global_position, hero.team):
		var jg_rem: float = 240.0 - float(jg_battle.game_time)
		_push_icon(top_cfgs, "jungle_protect", "侵", Color(1.0, 0.6, 0.3), "野区保护·入侵",
			"身处敌方半区（河道外）：前4分钟内对敌方英雄与野怪造成伤害降低25%%，%.1f 秒后结束。" % jg_rem,
			jg_rem, 240.0)
	# 越塔保护：身处敌方防御塔射程内 → 对敌方英雄伤害降低（前4分钟25% → 4-10分钟10% → 10分钟后5%）
	if jg_battle and jg_battle.hero_under_enemy_tower(hero):
		var _dive_pct := int((1.0 - jg_battle.tower_dive_factor()) * 100.0)
		if jg_battle.game_time < 240.0:
			var _dive_rem: float = 240.0 - float(jg_battle.game_time)
			_push_icon(top_cfgs, "tower_dive", "越", Color(0.98, 0.62, 0.35), "越塔保护",
				"身处敌方防御塔射程内：对敌方英雄造成伤害降低%d%%%（%.1f 秒后衰减为10%%）。" % [_dive_pct, _dive_rem],
				_dive_rem, 240.0, false, "%d%%" % _dive_pct)
		elif jg_battle.game_time < 600.0:
			var _dive_rem2: float = 600.0 - float(jg_battle.game_time)
			_push_icon(top_cfgs, "tower_dive", "越", Color(0.98, 0.62, 0.35), "越塔保护",
				"身处敌方防御塔射程内：对敌方英雄造成伤害降低%d%%%（%.1f 秒后衰减为5%%）。" % [_dive_pct, _dive_rem2],
				_dive_rem2, 360.0, false, "%d%%" % _dive_pct)
		else:
			_push_icon(top_cfgs, "tower_dive", "越", Color(0.98, 0.62, 0.35), "越塔保护",
				"身处敌方防御塔射程内：对敌方英雄造成伤害降低%d%%。" % _dive_pct,
				0.0, 0.0, true, "%d%%" % _dive_pct)

	# —— 控制 / 减益（上排）——
	if hero.stun_timer > 0:
		_push_icon(top_cfgs, "stun", "晕", Color(1.0, 0.33, 0.27), "眩晕",
			"无法移动、普攻与施法，持续 %.1f 秒。" % hero.stun_timer, hero.stun_timer)
	if hero.knockup_timer > 0:
		_push_icon(top_cfgs, "knockup", "飞", Color(1.0, 0.55, 0.22), "击飞",
			"被击飞至空中，期间无法行动（%.1f 秒）。" % hero.knockup_timer, hero.knockup_timer)
	if hero.froze_timer > 0:
		_push_icon(top_cfgs, "froze", "冻", Color(0.45, 0.75, 1.0), "冰冻",
			"被冰冻，无法移动与攻击，持续 %.1f 秒。" % hero.froze_timer, hero.froze_timer)
	if hero.silence_timer > 0:
		_push_icon(top_cfgs, "silence", "默", Color(0.78, 0.58, 0.96), "沉默",
			"无法使用技能与主动装备，持续 %.1f 秒。" % hero.silence_timer, hero.silence_timer)
	if hero.suppress_timer > 0:
		_push_icon(top_cfgs, "suppress", "压", Color(0.6, 0.45, 1.0), "压制",
			"被完全压制，无法做任何操作（%.1f 秒）。" % hero.suppress_timer, hero.suppress_timer)
	if hero.slow_amount > 0.0 and hero.slow_timer > 0:
		_push_icon(top_cfgs, "slow", "缓", Color(0.5, 0.7, 1.0), "减速",
			"移动速度降低 %.0f%%，持续 %.1f 秒。" % [hero.slow_amount * 100.0, hero.slow_timer], hero.slow_timer)
	if hero.slow_amount < 0.0 and hero.slow_timer > 0:
		_push_icon(bot_cfgs, "hasten", "疾", Color(0.42, 0.93, 0.6), "加速",
			"移动速度提升 %.0f%%，持续 %.1f 秒。" % [-hero.slow_amount * 100.0, hero.slow_timer], hero.slow_timer)
	if hero.grievous_wounds_timer > 0:
		_push_icon(top_cfgs, "grievous", "创", Color(1.0, 0.62, 0.2), "重伤",
			"受到的治疗与回复效果降低，持续 %.1f 秒。" % hero.grievous_wounds_timer, hero.grievous_wounds_timer)
	# —— 护盾 / 野区 Buff ——
	if hero.shield_remaining > 0 and hero.shield_timer > 0:
		_push_icon(bot_cfgs, "shield", "盾", Color(0.5, 0.87, 1.0), "护盾",
			"吸收 %.0f 点伤害的护盾，%.1f 秒后消失。" % [hero.shield_remaining, hero.shield_timer], hero.shield_timer)
	if hero.red_buff_active and hero.red_buff_timer > 0:
		_push_icon(bot_cfgs, "red", "红", Color(0.96, 0.34, 0.22), "红Buff",
			"普攻附带灼烧伤害并减速目标，持续 %.1f 秒。" % hero.red_buff_timer,
			hero.red_buff_timer, Hero.BUFF_DURATION)
	if hero.blue_buff_active and hero.blue_buff_timer > 0:
		_push_icon(bot_cfgs, "blue", "蓝", Color(0.36, 0.6, 1.0), "蓝Buff",
			"提升回蓝与技能冷却缩减，持续 %.1f 秒。" % hero.blue_buff_timer,
			hero.blue_buff_timer, Hero.BUFF_DURATION)
	if hero.jungle_stacks > 0:
		_push_icon(bot_cfgs, "jungle", "野", Color(0.52, 0.9, 0.5), "打野装备",
			"已叠 %d 层：提升对野怪的伤害与击杀收益。" % hero.jungle_stacks,
			0.0, 0.0, true, "%d层" % hero.jungle_stacks)
	# —— 史诗野怪 Buff：君临 / 暗影君临 / 风暴觉醒 ——
	if hero.tyrant_lightning_active and hero.tyrant_lightning_timer > 0:
		if hero.tyrant_lightning_shadow:
			_push_icon(bot_cfgs, "shadow_junlin", "霆", Color(0.7, 0.5, 1.0), "暗影君临",
				"击杀暗影暴君获得：命中触发闪电链（伤害翻倍）并提升移速，持续 %.1f 秒。" % hero.tyrant_lightning_timer,
				hero.tyrant_lightning_timer)
		else:
			_push_icon(bot_cfgs, "junlin", "霆", Color(1.0, 0.85, 0.4), "君临",
				"击杀暴君获得：命中触发闪电链，持续 %.1f 秒。" % hero.tyrant_lightning_timer,
				hero.tyrant_lightning_timer)
	if hero.storm_aura_active and hero.storm_aura_timer > 0:
		_push_icon(bot_cfgs, "storm", "暴", Color(0.82, 0.56, 1.0), "风暴觉醒",
			"击杀风暴龙王获得：风暴光环每秒对周围敌人造成最大生命 4% 真实伤害，持续 %.1f 秒。" % hero.storm_aura_timer,
			hero.storm_aura_timer)
	# —— active_buffs 属性增益（按属性聚合）——
	var agg: Dictionary = {}
	for b in hero.active_buffs:
		var t: float = float(b.get("timer", 0.0))
		if b.get("_tag", "") == "kai_passive_ms": continue  # 铠永久移速不占临时增益图标
		if t <= 0.0: continue
		for fkey in ["bonus_attack", "bonus_ability_power", "bonus_armor_resist",
				"bonus_magic_resist", "bonus_attack_speed", "bonus_move_speed"]:
			if not b.has(fkey): continue
			var entry: Dictionary = agg.get(fkey, {"v": 0.0, "t": 0.0})
			entry.v += float(b[fkey])
			entry.t = maxf(float(entry.t), t)
			agg[fkey] = entry
		if b.has("frenzy_dmg"):
			var fe: Dictionary = agg.get("frenzy", {"v": 0.0, "t": 0.0})
			fe.t = maxf(float(fe.t), t)
			agg["frenzy"] = fe
	if agg.has("bonus_attack") and float(agg["bonus_attack"].v) > 0:
		_push_icon(bot_cfgs, "atk_up", "攻", Color(1.0, 0.62, 0.3), "攻击增益",
			"临时攻击力 +%.0f，持续 %.1f 秒。" % [agg["bonus_attack"].v, agg["bonus_attack"].t], agg["bonus_attack"].t)
	if agg.has("bonus_ability_power") and float(agg["bonus_ability_power"].v) > 0:
		_push_icon(bot_cfgs, "ap_up", "法", Color(0.75, 0.55, 1.0), "法术增益",
			"临时法术强度 +%.0f，持续 %.1f 秒。" % [agg["bonus_ability_power"].v, agg["bonus_ability_power"].t], agg["bonus_ability_power"].t)
	if agg.has("bonus_armor_resist") and float(agg["bonus_armor_resist"].v) > 0:
		_push_icon(bot_cfgs, "armor_up", "甲", Color(0.95, 0.82, 0.4), "护甲增益",
			"临时护甲 +%.0f，持续 %.1f 秒。" % [agg["bonus_armor_resist"].v, agg["bonus_armor_resist"].t], agg["bonus_armor_resist"].t)
	if agg.has("bonus_magic_resist") and float(agg["bonus_magic_resist"].v) > 0:
		_push_icon(bot_cfgs, "mr_up", "魔", Color(0.5, 0.8, 1.0), "魔抗增益",
			"临时魔法抗性 +%.0f，持续 %.1f 秒。" % [agg["bonus_magic_resist"].v, agg["bonus_magic_resist"].t], agg["bonus_magic_resist"].t)
	if agg.has("bonus_attack_speed") and float(agg["bonus_attack_speed"].v) > 0:
		_push_icon(bot_cfgs, "as_up", "速", Color(0.6, 0.9, 0.45), "攻速增益",
			"临时攻击速度提升，持续 %.1f 秒。" % agg["bonus_attack_speed"].t, agg["bonus_attack_speed"].t)
	if agg.has("bonus_move_speed") and float(agg["bonus_move_speed"].v) > 0:
		_push_icon(bot_cfgs, "ms_up", "移", Color(0.5, 0.93, 0.9), "移速增益",
			"临时移动速度提升，持续 %.1f 秒。" % agg["bonus_move_speed"].t, agg["bonus_move_speed"].t)
	if agg.has("frenzy"):
		_push_icon(bot_cfgs, "frenzy", "狂", Color(1.0, 0.42, 0.5), "狂暴",
			"进入狂暴：提升伤害、坦度与吸血，持续 %.1f 秒。" % agg["frenzy"].t, agg["frenzy"].t)
	# —— 强化普攻：就绪 / 冷却中 ——
	if hero.witch_staff_buff and hero.witch_staff_cd <= 0:
		_push_icon(bot_cfgs, "witch_ready", "巫", Color(0.82, 0.58, 1.0), "巫术之杖",
			"强化普攻就绪：下一次普攻附带额外法术伤害。", 0.0, 0.0, true, "就绪")
	elif hero.witch_staff_cd > 0 and not hero.witch_staff_buff:
		_push_icon(bot_cfgs, "witch_cd", "巫", Color(0.62, 0.58, 0.7), "巫术之杖",
			"巫术被动冷却中，%.1f 秒后再次强化普攻。" % hero.witch_staff_cd, hero.witch_staff_cd)
	if hero.sage_power_buff and hero.sage_power_cd <= 0:
		if hero.sage_power_timer > 0:
			_push_icon(bot_cfgs, "sage_active", "宗", Color(1.0, 0.72, 0.32), "宗师之力",
				"强化普攻：使用技能后的普攻造成额外伤害，持续 %.1f 秒。" % hero.sage_power_timer, hero.sage_power_timer)
		else:
			_push_icon(bot_cfgs, "sage_ready", "宗", Color(1.0, 0.78, 0.4), "宗师之力",
				"强化普攻就绪。", 0.0, 0.0, true, "就绪")
	elif hero.sage_power_cd > 0 and not hero.sage_power_buff:
		_push_icon(bot_cfgs, "sage_cd", "宗", Color(0.62, 0.58, 0.7), "宗师之力",
			"宗师被动冷却中，%.1f 秒后再次强化普攻。" % hero.sage_power_cd, hero.sage_power_cd)
	if hero.ice_fist_buff and hero.ice_fist_cd <= 0:
		_push_icon(bot_cfgs, "ice_ready", "冰", Color(0.45, 0.82, 1.0), "冰痕之握",
			"强化普攻就绪：下一次普攻减速并附带范围伤害。", 0.0, 0.0, true, "就绪")
	elif hero.ice_fist_cd > 0 and not hero.ice_fist_buff:
		_push_icon(bot_cfgs, "ice_cd", "冰", Color(0.62, 0.58, 0.7), "冰痕之握",
			"冰痕被动冷却中，%.1f 秒后再次强化普攻。" % hero.ice_fist_cd, hero.ice_fist_cd)
	# —— 装备主动开启状态 ——
	if hero.thornmail_active:
		_push_icon(bot_cfgs, "thornmail", "反", Color(1.0, 0.46, 0.3), "反伤刺甲",
			"开启荆棘反伤：反弹所受物理伤害，持续 %.1f 秒。" % hero.thornmail_timer, hero.thornmail_timer)
	if hero.golden_body_active:
		_push_icon(bot_cfgs, "golden", "辉", Color(1.0, 0.85, 0.36), "辉月",
			"进入无敌状态，持续 %.1f 秒。" % hero.golden_body_timer, hero.golden_body_timer)
	if hero.sunspire_active:
		_push_icon(bot_cfgs, "sunspire", "逐", Color(1.0, 0.8, 0.24), "逐日之弓",
			"普攻射程与攻速提升，持续 %.1f 秒。" % hero.sunspire_active_timer, hero.sunspire_active_timer)
	if hero.shadow_dart_active:
		_push_icon(bot_cfgs, "shadow", "影", Color(0.6, 0.68, 1.0), "幽影",
			"进入隐身状态，持续 %.1f 秒。" % hero.shadow_dart_timer, hero.shadow_dart_timer)
	if hero.blood_rage_active:
		_push_icon(bot_cfgs, "bloodrage", "血", Color(0.95, 0.32, 0.3), "血魔之怒",
			"获得护盾与攻击加成，持续 %.1f 秒。" % hero.blood_rage_timer, hero.blood_rage_timer)
	# —— 叠加层数 ——
	if hero.chase_wind_stacks > 0:
		_push_icon(bot_cfgs, "chasewind", "风", Color(0.5, 0.95, 0.62), "逐风",
			"普攻叠加攻击速度，已叠 %d 层，%.1f 秒后衰减。" % [hero.chase_wind_stacks, hero.chase_wind_timer],
			hero.chase_wind_timer, 0.0, false, "%d层" % hero.chase_wind_stacks)
	if hero.dusk_flow_stacks > 0:
		_push_icon(bot_cfgs, "duskflow", "暮", Color(0.74, 0.58, 1.0), "日暮",
			"技能命中叠加法术穿透，已叠 %d 层，%.1f 秒后衰减。" % [hero.dusk_flow_stacks, hero.dusk_flow_timer],
			hero.dusk_flow_timer, 0.0, false, "%d层" % hero.dusk_flow_stacks)
	if hero.fierce_armor_stacks > 0:
		_push_icon(bot_cfgs, "fierce", "烈", Color(1.0, 0.6, 0.34), "暴烈",
			"受击叠加伤害与移速，已叠 %d 层，%.1f 秒后衰减。" % [hero.fierce_armor_stacks, hero.fierce_armor_timer],
			hero.fierce_armor_timer, 0.0, false, "%d层" % hero.fierce_armor_stacks)
	if hero.gold_saint_sword_stacks > 0:
		_push_icon(bot_cfgs, "saintsword", "圣", Color(1.0, 0.85, 0.4), "圣剑",
			"击杀叠加暴击与移速，已叠 %d 层，%.1f 秒后衰减。" % [hero.gold_saint_sword_stacks, hero.gold_saint_sword_timer],
			hero.gold_saint_sword_timer, 0.0, false, "%d层" % hero.gold_saint_sword_stacks)
	# —— 回复 / 复活 ——
	if hero.active_regen.size() > 0:
		var mt := 0.0
		for reg in hero.active_regen.values():
			mt = maxf(mt, reg.timer)
		if mt > 0:
			_push_icon(bot_cfgs, "regen", "愈", Color(0.35, 0.94, 0.55), "生命回复",
				"持续回复生命值，剩余 %.1f 秒。" % mt, mt)
	if hero.is_reviving:
		_push_icon(bot_cfgs, "revive", "复", Color(0.5, 0.95, 0.6), "等待复活",
			"即将原地复活（%.1f 秒）。" % hero.revive_timer, hero.revive_timer)
	# —— 受击印记（敌方→上排 / 己方→下排）——
	_push_marker_buffs(hero, top_cfgs, bot_cfgs)
	# —— 英雄被动/强化普攻等计时状态（增益→下排）——
	_push_hero_passive_buffs(hero, bot_cfgs)
	return {"top": top_cfgs, "bot": bot_cfgs}


func _update_buff_icons(hero: Hero):
	# 绘制路径：读 collect_buff_rows 的纯结果，只做节点复用池与两行水平居中排布
	var rows := collect_buff_rows(hero)
	var top_cfgs: Array = rows["top"]
	var bot_cfgs: Array = rows["bot"]
	# —— 图标复用池：新增 / 复用 / 移除 ——
	var cur: Dictionary = {}
	var top_keys: Array = []
	for c in top_cfgs:
		top_keys.append(c.key)
		_apply_buff_cfg(c, cur)
	var bot_keys: Array = []
	for c in bot_cfgs:
		bot_keys.append(c.key)
		_apply_buff_cfg(c, cur)
	for key in buff_icon_nodes.keys():
		if not cur.has(key):
			var dead = buff_icon_nodes[key]
			buff_icon_nodes.erase(key)
			dead.visible = false
			dead.queue_free()
	# —— 两行水平居中排布（屏幕底部中央）：上排减益 / 下排增益 ——
	var vw := get_viewport().get_visible_rect().size.x
	var bot_y := BUFF_ROW_Y
	var top_y := bot_y - (BuffIcon.CELL_H + 6.0)
	if bot_keys.size() > 0:
		_layout_buff_row(cur, bot_keys, bot_y, vw)
	if top_keys.size() > 0:
		# 仅存在减益时也贴底排布，避免孤悬高处
		_layout_buff_row(cur, top_keys, (bot_y if bot_keys.size() == 0 else top_y), vw)
	# —— 选中详情：跟随刷新 / 消失关闭 ——
	if selected_buff_key == "":
		return
	if cur.has(selected_buff_key):
		_update_buff_info(cur[selected_buff_key], vw)
	else:
		_close_buff_info()

func _on_buff_icon_tapped(key: String):
	if selected_buff_key == key:
		_close_buff_info()
		return
	var node = buff_icon_nodes.get(key)
	if not node: return
	selected_buff_key = key
	_update_buff_info(node, get_viewport().get_visible_rect().size.x)

func _close_buff_info():
	selected_buff_key = ""
	if buff_info_panel:
		buff_info_panel.visible = false

func _update_buff_info(node, vw: float):
	# 说明文本本身每帧刷新（时长已内嵌随剩余值变化），无需另加“剩余时间”行
	var txt: String = node.effect_desc
	if buff_info_desc.text != txt:
		buff_info_title.text = node.display_name
		buff_info_desc.text = txt
		_resize_buff_info()
	buff_info_panel.visible = true
	_position_buff_info(node, vw)

func _resize_buff_info():
	var font: Font = UiKit.font()
	var tfs := 18
	var dfs := 14
	var text_w := BUFF_INFO_W - 30.0
	var title_h: float = font.get_height(tfs)
	var lines := _buff_info_lines(buff_info_desc.text, dfs, text_w)
	var desc_h: float = font.get_height(dfs) * float(lines)
	var h: float = 12.0 + title_h + 4.0 + desc_h + 10.0
	buff_info_panel.size = Vector2(BUFF_INFO_W, h)
	buff_info_title.size = Vector2(text_w, title_h)
	buff_info_title.position = Vector2(15, 10)
	buff_info_desc.size = Vector2(text_w, desc_h)
	buff_info_desc.position = Vector2(15, 10.0 + title_h + 4.0)

func _position_buff_info(node, vw: float):
	var W: float = buff_info_panel.size.x
	var half := W * 0.5
	var lo := half + 10.0
	var hi := maxf(lo, vw - half - 10.0)
	var cx := clampf(float(node.position.x) + float(node.size.x) * 0.5, lo, hi)
	var py: float = float(node.position.y) - buff_info_panel.size.y - 10.0
	if py < 96.0:
		py = float(node.position.y) + float(node.size.y) + 12.0
	buff_info_panel.position = Vector2(cx - half, py)

func _buff_info_lines(text: String, fs: int, max_w: float) -> int:
	var font: Font = UiKit.font()
	var total := 0
	for seg in text.split("\n"):
		if seg.is_empty():
			total += 1
			continue
		var w := 0.0
		var lines := 1
		for ch in seg:
			var cw: float = font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			w += cw
			if w > max_w:
				lines += 1
				w = cw
		total += lines
	return maxi(total, 1)

func _close_shop():
	# 面板常驻复用（不再 queue_free）：仅隐藏，避免每次开关重建 100+ 节点
	if shop_ui != null and is_instance_valid(shop_ui):
		shop_ui.visible = false
		UiKit.hide_panel(shop_ui, 0.12)

func _refresh_hero_detail_panel():
	if not hero_detail_visible:
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle:
		return
	var rows: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or not (e is Hero):
			continue
		var row: Dictionary = _roster_row(e as Hero, battle)
		row["own"] = e == battle.hero
		rows.append(row)
	hero_detail_panel.set_rows(rows, "attr", {})   # 先锋波次已挪到顶部对局信息带

## 对局信息：主宰/暗影/风暴被击败后的先锋波数（我方/敌方）
func _vanguard_info(battle) -> Dictionary:
	if battle == null:
		return {}
	var my_w: int = battle.vanguard_waves_left(Config.player_team)
	var en_w: int = battle.vanguard_waves_left(Config.foe_team())
	var nm: String = battle.vanguard_wave_name()
	var txt := ""
	var col: Color = UiKit.C_TEXT_DIM
	if my_w > 0 and en_w > 0:
		txt = "%s 我方 %d 波 · 敌方 %d 波" % [nm, my_w, en_w]
		col = UiKit.C_GOLD
	elif my_w > 0:
		txt = "%s 我方 %d 波" % [nm, my_w]
		col = UiKit.C_GOLD
	elif en_w > 0:
		txt = "%s 敌方 %d 波" % [nm, en_w]
		col = UiKit.C_TEAM1
	else:
		# 两方都没有待出动的先锋波次 → 这一行直接留空（信息带只在有待出动波次时显示）
		return {}
	return {"vanguard": txt, "vanguard_color": col}

## 单英雄行数据（供 RosterView 双列对位绘制；与客户端 NetSession 行载荷字段同名）
func _roster_row(h: Hero, battle) -> Dictionary:
	var chips: Array = []
	chips.append(["heart", Color(0.45, 1.0, 0.55), "%d/%d" % [int(h.health), int(h.actual_max_health)]])
	chips.append(["sword", Color(1.0, 0.62, 0.24), "%d" % int(h.actual_attack_damage)])
	chips.append(["spark", Color(0.72, 0.5, 1.0), "%d" % int(h.actual_ability_power)])
	chips.append(["shield", Color(1.0, 0.78, 0.3), "%d" % int(h.actual_armor)])
	chips.append(["gem", Color(0.4, 0.88, 1.0), "%d" % int(h.actual_magic_resist)])
	chips.append(["chev", Color(0.45, 0.9, 0.7), "%.0f" % h.actual_move_speed])
	chips.append(["bolt", Color(1.0, 0.85, 0.3), "%.2f" % h.attack_speed])
	if h.actual_mana_max > 0:
		chips.append(["drop", Color(0.3, 0.7, 1.0), "%d/%d" % [int(h.mana), int(h.actual_mana_max)]])
	if h.actual_crit_chance > 0:
		chips.append(["cross", Color(1.0, 0.42, 0.36), "%.0f%%" % (h.actual_crit_chance * 100)])
	if h.actual_phys_pen_percent > 0:
		chips.append(["pierce", Color(1.0, 0.72, 0.3), "%.0f%%" % (h.actual_phys_pen_percent * 100)])
	if h.actual_magic_pen_percent > 0:
		chips.append(["pierce", Color(0.7, 0.55, 1.0), "%.0f%%" % (h.actual_magic_pen_percent * 100)])
	if h.actual_phys_lifesteal > 0:
		chips.append(["heart", Color(1.0, 0.56, 0.34), "%.0f%%" % (h.actual_phys_lifesteal * 100)])
	if h.bonus_toughness > 0:
		chips.append(["tough", Color(0.96, 0.9, 0.5), "%.0f%%" % (h.bonus_toughness * 100)])
	if h.actual_cd_timer < 1.0:
		chips.append(["clock", Color(0.5, 0.85, 1.0), "%.0f%%" % ((1.0 - h.actual_cd_timer) * 100)])
	var skills: Array = []
	for i in range(mini(h.skills.size(), 3)):
		var sk = h.skills[i]
		skills.append([i + 1, sk.skill_name if sk != null else "", int(h.skill_levels[i]),
			float(h.skill_cooldowns[i]), int(sk.type) if sk != null else -1])
	if h.summoner_skill != null:
		skills.append([9, str(h.summoner_skill.skill_name), 0, float(h.summoner_cooldown),
			int(h.summoner_skill.type)])
	var equips: Array = []
	for item_id in h.equipment_slots:
		var it: Dictionary = ItemDatabase.get_item(item_id)
		equips.append([str(it.get("name", item_id)), int(it.get("tier", 1))])
	var lane := -1
	if battle != null and battle.team_tactics != null:
		lane = int(battle.team_tactics.assignments.get(h, -1))
	return {
		"name": str(h.display_name), "hero": str(h.display_name), "team": int(h.team),
		"role": str(h.role), "lane": lane, "level": int(h.level),
		"k": int(h.kills), "d": int(h.deaths), "a": int(h.assists),
		"gold": int(h.total_gold_earned),
		"hp_ratio": float(h.health) / float(h.actual_max_health) if h.actual_max_health > 0.0 else 1.0,
		"dead": bool(h.is_dead), "respawn": float(h.respawn_timer),
		"chips": chips, "skills": skills, "equips": equips, "is_ai": bool(h.is_ai),
		"mark": clampi(int(h.primitive_score / 100), 0, 6),
	}

func _update_death_recap():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero:
		if death_overlay: death_overlay.visible = false
		return
	var hero = battle.hero
	# 死亡全屏压暗：盖在 3D 之上、其余 UI 之下；复活即消失
	if death_overlay: death_overlay.visible = hero.is_dead
	if not hero.is_dead:
		death_recap_panel.visible = false
		death_recap_shown = false
		death_recap_closed = false
	elif not death_recap_shown and not death_recap_closed:
		_show_death_recap(hero)
		death_recap_shown = true
func _close_death_recap():
	death_recap_panel.visible = false
	death_recap_shown = true
	death_recap_closed = true
func _show_death_recap(hero: Hero):
	var battle = get_tree().get_first_node_in_group("battle_manager")
	death_recap_panel.set_data(DeathRecapView.build(hero, battle))
	if death_recap_panel != null:
		death_recap_panel.visible = true
		var sz: Vector2 = death_recap_panel.size
		death_recap_panel.set_anchors_preset(Control.PRESET_CENTER)
		death_recap_panel.offset_left = -sz.x * 0.5
		death_recap_panel.offset_right = sz.x * 0.5
		death_recap_panel.offset_top = -sz.y * 0.5 + 8.0
		death_recap_panel.offset_bottom = sz.y * 0.5 + 8.0
func _update_respawn_widgets():
	# 只在「阵亡状态 / 观战目标」变化时重建：此前每帧重建会持续泄漏空行节点，移动端跑久了内存越吃越多
	if respawn_container == null or not is_instance_valid(respawn_container):
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var heroes := get_tree().get_nodes_in_group("heroes")
	var player_dead: bool = battle != null and is_instance_valid(battle.hero) and battle.hero.is_dead
	var spec_id: int = 0
	if battle != null and is_instance_valid(battle.spectate_hero):
		spec_id = battle.spectate_hero.get_instance_id()
	var sig := "%s|%d" % [player_dead, spec_id]
	for h in heroes:
		if not is_instance_valid(h):
			continue
		sig += "|%d:%s" % [h.get_instance_id(), h.is_dead]
	if sig == _respawn_sig:
		return
	_respawn_sig = sig
	for child in respawn_container.get_children():
		respawn_container.remove_child(child)
		child.queue_free()
	# 第一排：我方英雄（含残血/复活读秒，始终显示）；玩家阵亡时可点存活队友观战
	var ally_row := HBoxContainer.new()
	ally_row.add_theme_constant_override("separation", 10)
	for h in heroes:
		if not is_instance_valid(h) or not Config.is_ally(h.team): continue
		var widget = RespawnWidget.new()
		widget.hero = h
		widget.spectatable = player_dead and h != battle.hero and not h.is_dead
		widget.spectating = battle != null and battle.spectate_hero == h
		widget.spectate_clicked.connect(_on_respawn_spectate_clicked)
		ally_row.add_child(widget)
	respawn_container.add_child(ally_row)
	# 第二排：已阵亡的敌方英雄（复活后自动从第二排消失）
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 10)
	var any_enemy := false
	for h in heroes:
		if not is_instance_valid(h) or Config.is_ally(h.team) or not h.is_dead: continue
		var widget = RespawnWidget.new(); widget.hero = h; enemy_row.add_child(widget); any_enemy = true
	if any_enemy:
		respawn_container.add_child(enemy_row)
	else:
		enemy_row.queue_free()

func _on_respawn_spectate_clicked(target: Hero):
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle != null:
		battle.set_spectate_target(target)

# ---------- 公开控制接口（供移动端触摸按钮调用） ----------
## 全屏面板（商店 / 英雄面板）打开时，英雄应停止响应键盘与摇杆：
## 否则在商店里按 W/S 选装备、按 Enter 购买会同时驱动英雄移动/普攻。
func blocks_gameplay_input() -> bool:
	if shop_ui != null and is_instance_valid(shop_ui) and shop_ui.visible:
		return true
	if hero_detail_panel != null and is_instance_valid(hero_detail_panel) and hero_detail_visible:
		return true
	# 聊天输入中：别让 WASD/技能键把英雄带跑
	if chat_typing:
		return true
	return false

func toggle_shop():
	if shop_ui != null and is_instance_valid(shop_ui) and shop_ui.visible:
		_close_shop()
	else:
		_open_shop()

func toggle_hero_detail():
	if hero_detail_visible:
		close_hero_detail()
	else:
		open_hero_detail()

func open_hero_detail():
	if hero_detail_panel == null or not is_instance_valid(hero_detail_panel):
		return
	hero_detail_visible = true
	UiKit.show_panel(hero_detail_panel, 0.15)
	UiKit.show_panel(hero_detail_dim, 0.15)
	# 打开英雄面板时关闭商店抽屉，避免叠在一起
	if shop_ui:
		_close_shop()
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle:
		hero_detail_refresh_timer = battle.game_time
	_refresh_hero_detail_panel()

func close_hero_detail():
	if hero_detail_panel == null or not is_instance_valid(hero_detail_panel):
		return
	hero_detail_visible = false
	UiKit.hide_panel(hero_detail_panel, 0.12)
	UiKit.hide_panel(hero_detail_dim, 0.12)

func toggle_team_decision():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	team_decision_visible = !team_decision_visible
	if team_decision_visible:
		UiKit.show_panel(team_decision_panel, 0.15)
		team_decision_refresh_timer = battle.game_time if battle else 0.0
		_refresh_team_decision_panel()
	else:
		UiKit.hide_panel(team_decision_panel, 0.12)

func buy_recommended():
	_on_buy_equipment(recommended_equip_id)

# ---------- 输入处理 ----------
func _input(event):
	# 忽略操作系统的按键自动重复：长按 C/O/T 不能反复开关面板
	if event is InputEventKey and event.pressed and not event.echo:
		# 商店打开时优先处理商店键位（1-9 切分类 / ↑↓·W S 选装 / Enter 购买 / Esc 关闭）
		if shop_ui != null and is_instance_valid(shop_ui) and _shop_handle_key(event):
			get_viewport().set_input_as_handled()
			return
		var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		match event.keycode:
			KEY_C: toggle_hero_detail()
			KEY_O: toggle_shop()
			KEY_B: buy_recommended()
			KEY_Z: 
				if battle and battle.hero and not battle.hero.is_dead: 
					if battle.hero.display_name == "大禹" and battle.hero.dayu_teleport_cd <= 0: 
						var furthest = battle.hero._get_furthest_tripod(); 
						if furthest and battle.hero.global_position.distance_to(furthest.global_position) <= 6.0: battle.hero._start_tripod_teleport(furthest) 
						else: battle.hero.start_recall() 
					else: battle.hero.start_recall()
			KEY_T: toggle_team_decision()
			KEY_6: if battle and battle.hero: _trigger_active_equip(battle.hero, 0)
			KEY_7: if battle and battle.hero: _trigger_active_equip(battle.hero, 1)

# ---------- 主更新函数 ----------
# ---------- 左侧属性面板（基础+装备+Buff 三段拆分） ----------
func _create_attribute_panel():
	var rs := ui_scale()
	var colw := 200.0 * rs
	var gap := 12.0 * rs
	var pad := 12.0 * rs
	var legend_h := 26.0 * rs
	var row_h := 28.0 * rs
	var cols := 2
	var panel_w := pad * 2.0 + colw * cols + gap * (cols - 1)
	var head_h := 30.0 * rs
	var panel_h := pad * 2.0 + head_h + legend_h + row_h * ATTR_ROWS_PER_COL
	attr_header_h = head_h
	attr_panel_h_full = panel_h
	attr_panel_w_full = panel_w
	attribute_panel = Panel.new()
	attribute_panel.size = Vector2(panel_w, panel_h)
	# 紧贴小地图下方（小地图：inset 40 + 300 见 BattleManager），顶边固定、向下展开
	attr_panel_top = 40.0 + UiKit.safe_top() + 450.0 + 10.0
	attribute_panel.position = Vector2(40.0 + UiKit.safe_left(), attr_panel_top)
	_apply_panel_style(attribute_panel, 0.5)
	add_child(attribute_panel)

	# 折叠标题条：点击切换展开/收起（收起时只保留这一条，宽度与小地图对齐）
	attr_header = Label.new()
	attr_header.text = "属性  ▼"
	attr_header.position = Vector2(pad, 2.0 * rs)
	attr_header.size = Vector2(panel_w - pad * 2.0, head_h)
	attr_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(attr_header, 16, Color(0.85, 0.9, 1.0, 0.95))
	attribute_panel.add_child(attr_header)
	_connect_tap_to_action(attr_header, Callable(self, "toggle_attribute_panel"))

	# 顶部图例：白=基础 绿=装备 橙=Buff
	var legend := RichTextLabel.new()
	legend.position = Vector2(pad, pad + head_h)
	legend.size = Vector2(panel_w - pad * 2.0, legend_h)
	legend.bbcode_enabled = true
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rich_label_style(legend, 13)
	legend.text = "[color=#ffffff]基础[/color]  [color=#72e35f]+装备[/color]  [color=#ffa04a]+增益[/color]"
	attribute_panel.add_child(legend)
	attr_legend = legend

	attr_row_labels.clear()
	for i in range(ATTRIBUTE_ROWS.size()):
		var lab := RichTextLabel.new()
		lab.position = Vector2(pad + (i / ATTR_ROWS_PER_COL) * (colw + gap),
			pad + head_h + legend_h + (i % ATTR_ROWS_PER_COL) * row_h)
		lab.size = Vector2(colw, row_h)
		lab.autowrap_mode = TextServer.AUTOWRAP_OFF
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_rich_label_style(lab, 15)
		attribute_panel.add_child(lab)
		attr_row_labels.append(lab)

	# 建完即按默认折叠态布局（_update_attribute_panel 每帧还会按 attr_collapsed 校正行显隐）
	_layout_attribute_panel()
	# 目标信息框固定在顶部队列（头像与战况面板之间），不再跟随属性面板下移

# 属性面板布局：顶边固定在小地图下方，展开/收起只改高度，向下伸展
func _layout_attribute_panel():
	if attribute_panel == null:
		return
	var rs := ui_scale()
	var pad := 12.0 * rs
	var h: float = (attr_header_h + 4.0) if attr_collapsed else attr_panel_h_full
	# 收起态底板宽度必须跟小地图同宽（小地图 450，见 BattleManager），否则窄一截看着就是底板错位
	var w: float = (450.0 if attr_collapsed else attr_panel_w_full)
	attribute_panel.size = Vector2(w, h)
	attribute_panel.position.y = attr_panel_top
	if attr_header:
		attr_header.size = Vector2(w - pad * 2.0, attr_header_h)
	if attr_legend:
		attr_legend.visible = not attr_collapsed
	for lab in attr_row_labels:
		if is_instance_valid(lab):
			lab.visible = not attr_collapsed
	attr_header.text = "属性  ▼" if attr_collapsed else "属性  ▲"

func toggle_attribute_panel():
	if attribute_panel == null:
		return
	attr_collapsed = not attr_collapsed
	_layout_attribute_panel()

func _attr_val_str(v: float, mult: float, pct: bool) -> String:
	var x := v * mult
	if pct:
		var r := roundf(x * 10.0) / 10.0
		if absf(r - roundf(r)) < 0.05:
			return "%d%%" % int(round(r))
		return "%.1f%%" % r
	return "%d" % int(round(x))

func _build_attr_row(rich: RichTextLabel, cfg: Dictionary, parts: Array):
	var mult: float = cfg.get("mult", 1.0)
	var pct: bool = cfg.get("pct", false)
	var colors: Array[Color] = [Color.WHITE, Color(0.45, 0.9, 0.4), Color(1.0, 0.62, 0.25)]
	rich.clear()
	rich.push_color(Color(0.92, 0.92, 0.92, 0.95))
	rich.add_text(str(cfg.get("name", "")) + "  ")
	rich.pop()
	var wrote := false
	for k in range(3):
		var v: float = float(parts[k])
		if absf(v * mult) < 0.05:
			continue
		if k > 0 and v > 0.0:
			rich.push_color(colors[k])
			rich.add_text("+")
			rich.pop()
		rich.push_color(colors[k])
		rich.add_text(_attr_val_str(v, mult, pct))
		rich.pop()
		wrote = true
	if not wrote:
		rich.push_color(Color.WHITE)
		rich.add_text("0")
		rich.pop()

func _update_attribute_panel(hero: Hero):
	if not attribute_panel or not hero:
		return
	var bd: Dictionary = hero.stat_breakdown
	attribute_panel.visible = not bd.is_empty()
	if bd.is_empty():
		return
	for i in range(ATTRIBUTE_ROWS.size()):
		var lab: RichTextLabel = attr_row_labels[i] if i < attr_row_labels.size() else null
		if lab == null:
			continue
		var cfg: Dictionary = ATTRIBUTE_ROWS[i]
		var key: String = cfg.key
		if not bd.has(key):
			lab.visible = false
			continue
		lab.visible = not attr_collapsed
		var parts: Array = bd[key]
		if key == "move_speed":
			# 移速含实时减速/加速：逐帧取分量，让临时移速效果显示在 Buff(橙) 段
			parts = hero._live_move_speed_parts()
		_build_attr_row(lab, cfg, parts)

func update(battle: BattleManager):
	if not battle or not battle.hero: return
	var hero = battle.hero
	# 英雄面板每秒自动刷新
	if hero_detail_visible:
		if battle.game_time - hero_detail_refresh_timer >= 1.0:
			hero_detail_refresh_timer = battle.game_time
			_refresh_hero_detail_panel()

	# 团队决策面板 0.5s 刷新
	if team_decision_visible:
		if battle.game_time - team_decision_refresh_timer >= 0.5:
			team_decision_refresh_timer = battle.game_time
			_refresh_team_decision_panel()

	game_time_label.text = "%02d:%02d" % [int(battle.game_time)/60, int(battle.game_time)%60]
	kda_label.text = "K/D/A: %d/%d/%d" % [battle.hero.kills, battle.hero.deaths, battle.hero.assists]
	gold_label.text = "金币: %d" % hero.gold
	# 帧率：顶部信息带常显，<30 红 / <50 黄 / 其余绿
	if fps_label:
		var fps := Engine.get_frames_per_second()
		fps_label.text = "FPS %d" % fps
		fps_label.add_theme_color_override("font_color",
			Color(1.0, 0.42, 0.38) if fps < 30 else (Color(1.0, 0.82, 0.35) if fps < 50 else Color(0.55, 0.95, 0.65)))
	# 电量/网络：1s 轮询一次系统状态
	_dev_poll -= get_process_delta_time()
	if _dev_poll <= 0.0:
		_dev_poll = 1.0
		_refresh_device_status()

	# 刷新Buff显示
	_update_buff_icons(hero)
	_update_attribute_panel(hero)
	_update_yuanliu_switch_btn(hero)
	team_stats_label.clear()
	team_stats_label.push_color(Color(0.0, 0.886, 1.0))
	team_stats_label.add_text(_format_gold(battle.team_player_gold) + " ")
	team_stats_label.pop()
	team_stats_label.add_text(str(battle.team_player_kills) + " ")
	team_stats_label.add_text("vs")
	team_stats_label.add_text(" " + str(battle.team_enemy_kills) + " ")
	team_stats_label.push_color(Color(1.0, 0.33, 0.264))
	team_stats_label.add_text(_format_gold(battle.team_enemy_gold))
	team_stats_label.pop()
	# 第二行在「比分面板」内水平居中（面板右锚定，中心相对屏幕右缘 -576）
	var plain := "%s %d vs %d %s" % [_format_gold(battle.team_player_gold), battle.team_player_kills, battle.team_enemy_kills, _format_gold(battle.team_enemy_gold)]
	var tw := UiKit.font().get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(24 * ui_scale()))).x
	team_stats_label.offset_left = -576.0 - tw * 0.5
	team_stats_label.offset_right = -576.0 + tw * 0.5 + 4.0
	# 主宰先锋波次：顶部对局信息带常显（我方/敌方各剩几波）
	if vanguard_label != null:
		var vg: Dictionary = _vanguard_info(battle)
		var vtxt := str(vg.get("vanguard", ""))
		# 只有「还有先锋波次没出」时才占位；波次出完立即隐藏，
		# 不再用 vanguard_ever 让这一行永久挂「暗影先锋 已出完」
		var vg_live: bool = int(battle.vanguard_waves_left(Config.player_team)) > 0 \
			or int(battle.vanguard_waves_left(Config.foe_team())) > 0
		vanguard_label.visible = vtxt != "" and vg_live
		vanguard_label.text = vtxt
		vanguard_label.add_theme_color_override("font_color", vg.get("vanguard_color", UiKit.C_TEXT_DIM))

	_update_recommended_equip()
	_update_death_recap()
	_update_respawn_widgets()

	var target = hero.manual_target
	# 属性面板展开时让位（两者同处左侧栏），避免叠影
	if attr_collapsed and target and is_instance_valid(target) and target.health > 0:
		target_detail_panel.visible = true
		# 阵营主色：敌方橙红 / 己方青蓝 / 中立金黄（默认按敌方显示，与攻击目标面板的直觉一致）
		var tcol := Color(1.0, 0.45, 0.2)
		if "team" in target and Config.is_ally(target.team):
			tcol = Color(0.2, 0.9, 1.0)
		elif "team" in target and target.team == Config.Team.NEUTRAL:
			tcol = Color(1.0, 0.8, 0.35)
		target_detail_accent.color = tcol
		target_detail_team_dot.color = tcol
		target_detail_hp_fill.bg_color = tcol
		var name_lab: Label = target_detail_labels["name"]
		name_lab.text = EntityIconArtScript.display_name(str(target.display_name))
		name_lab.add_theme_color_override("font_color", tcol.lightened(0.3))
		if target_detail_entity_icon != null:
			target_detail_entity_icon.setup(EntityIconArtScript.spec_for(str(target.display_name)), tcol)
		var lv_lab: Label = target_detail_labels["level"]
		lv_lab.text = "Lv.%d" % target.level if target is Hero else ""
		target_detail_hp_bar.max_value = maxf(1.0, target.max_health)
		target_detail_hp_bar.value = target.health
		if target_detail_hp_gloss != null:
			target_detail_hp_gloss.max_hp = maxf(1.0, target.max_health)
			target_detail_hp_gloss.hp = target.health
			target_detail_hp_gloss.queue_redraw()
		var hp_txt := "%d / %d" % [int(target.health), int(target.max_health)]
		var hp_lab: Label = target_detail_labels["hp"]
		hp_lab.text = hp_txt
		# 读数底衬随文字宽度自适应，并居中贴合血条
		if target_detail_hp_pill != null and is_instance_valid(target_detail_hp_pill):
			var rs2 := ui_scale()
			var tw2 := UiKit.font().get_string_size(hp_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var ph := 18.0 * rs2
			var pw := tw2 + 20.0 * rs2
			target_detail_hp_pill.size = Vector2(pw, ph)
			target_detail_hp_pill.position = Vector2(
				16.0 * rs2 + (298.0 * rs2 - pw) * 0.5,
				43.0 * rs2 + (22.0 * rs2 - ph) * 0.5)
		target_detail_labels["攻击"].text = "%d" % int(target.attack)
		target_detail_labels["法强"].text = "%d" % int(target.ability_power if target is Hero else 0)
		target_detail_labels["护甲"].text = "%d" % int(target.armor)
		target_detail_labels["魔抗"].text = "%d" % int(target.magic_resist)
	else:
		target_detail_panel.visible = false

	for i in range(8):
		var icon = skill_icons[i] as SkillIcon if i < skill_icons.size() else null
		var lv_label = skill_level_labels[i] if i < skill_level_labels.size() else null
		var name_label = skill_name_labels[i] if i < skill_name_labels.size() else null
		var info_label = skill_info_labels[i] if i < skill_info_labels.size() else null
		if i == 5 and hero.summoner_skill != null:
			icon.skill = hero.summoner_skill; icon.skill_level = 1
			icon.max_cd = hero.summoner_skill.cooldown; icon.cd_remaining = hero.summoner_cooldown
			icon.mana_cost = hero.summoner_skill.mana_cost; icon.current_mana = int(hero.mana)
			if lv_label: lv_label.text = ""
			if name_label: name_label.text = hero.summoner_skill.skill_name
			if info_label: info_label.text = "%.0fs" % icon.max_cd
			icon.visible = true
		elif i < hero.skills.size() and hero.skills[i] and i < 5:
			var skill = hero.skills[i] as Skill; icon.skill = skill; icon.skill_level = hero.skill_levels[i]
			icon.max_cd = icon.skill.cooldown - icon.skill.cd_bonus * (hero.skill_levels[i] - 1)
			icon.mana_cost = icon.skill.mana_cost - icon.skill.power_bonus * (hero.skill_levels[i] - 1)
			icon.cd_remaining = hero.skill_cooldowns[i]; icon.current_mana = int(hero.mana)
			# 多段/重施窗口：按键变蓝并显示窗口剩余倒计时
			if hero.skill_window_timers[i] > 0:
				icon.blue = true; icon.cd_remaining = hero.skill_window_timers[i]
			else: icon.blue = false
				
			
				
			if lv_label: lv_label.text = "Lv.%d" % icon.skill_level if i <4 else ""
				# 李白R: 非侠客行时灰色
			if hero.display_name == "李白" and i == 2 and not hero.libai_xia_active:
				icon.skill_level = 0
			if name_label: name_label.text = skill.skill_name
			if info_label: info_label.text = "%d蓝 %.1fs" % [icon.mana_cost, icon.max_cd]
			icon.visible = true; if lv_label: lv_label.visible = true; if name_label: name_label.visible = true; if info_label: info_label.visible = true
		elif i >= 6:
			# 动态主动装备槽
			var ae_list = _get_active_equip_list(hero)
			var ae_idx = i - 6
			if ae_idx < ae_list.size():
				var ae = ae_list[ae_idx]
				icon.skill = null; icon.skill_level = 1
				icon.max_cd = ae.max_cd; icon.cd_remaining = ae.cd_remaining
				icon.current_mana = 0; icon.hero = hero; icon.slot = i
				icon.is_active_equip = true; icon.active_equip_id = ae.id
				icon.visible = true
				if lv_label: lv_label.text = ""; lv_label.visible = true
				if name_label: name_label.text = ae.name; name_label.visible = true
				if info_label: info_label.text = "%.0fs" % ae.max_cd; info_label.visible = true
			else:
				icon.visible = false
				if lv_label: lv_label.visible = false
				if name_label: name_label.visible = false
				if info_label: info_label.visible = false
		else:
			icon.visible = false
			if lv_label: lv_label.visible = false
			if name_label: name_label.visible = false
			if info_label: info_label.visible = false
		icon.queue_redraw()
	# 旧桌面技能条整组强制隐藏（上述分支会把图标重新设为可见，触控统一布局下必须最后收口）
	_set_legacy_skill_bar_visible(false)

# 获取主动装备列表
func _get_active_equip_list(hero: Hero) -> Array:
	var result = []
	for item_id in hero.equipment_slots:
		var item = ItemDatabase.get_item(item_id)
		if item.has("active"):
			var max_cd = 75.0
			var cd = 0.0
			if item_id == "purify" or item_id == "immovable_firmament": max_cd = 75.0; cd = hero.purify_cd
			elif item_id == "sunspire_bow" or item_id == "swift_day": max_cd = 75.0; cd = hero.sunspire_active_cd
			elif item_id == "shadow_dart": max_cd = 60.0; cd = hero.shadow_dart_cd
			elif item_id == "golden_body" or item_id == "moon_god": max_cd = 75.0; cd = hero.golden_body_cd
			elif item_id == "thornmail": max_cd = 75.0; cd = hero.thornmail_cd
			elif item_id == "blood_rage" or item_id == "rage_ghost": max_cd = 75.0; cd = hero.blood_rage_cd
			elif item_id == "ice_shock" or item_id == "sereve_winter": max_cd = 75.0; cd = hero.ice_shock_cd
			elif "redeemer" in item_id or "star_spring" in item_id: max_cd = 60.0 if "redeemer" in item_id else 50.0; cd = 0.0
			
			elif "galloping_wolf" in item_id: max_cd = 90.0; cd = 0.0
			elif "revealing_light" in item_id: max_cd = 75.0; cd = 0.0
			else: max_cd = 60.0
			result.append({"name": item["name"], "max_cd": max_cd, "cd_remaining": cd, "id": item_id})
	return result

func _format_gold(g: int) -> String:
	if g >= 1000: return "%.1fk" % (g / 1000.0)
	return str(g)

# ---------- 内部类 ----------
class EntityIconControl extends Control:
	# 战报/目标面板通用实体图标（英雄头像 / 防御塔 / 小兵 / 野怪）
	const Art = preload("res://scripts/ui/EntityIconArt.gd")
	var spec: Dictionary = {}
	var team_col := Color.WHITE
	func setup(sp: Dictionary, col: Color) -> void:
		spec = sp
		team_col = col
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()
	func _draw() -> void:
		if spec.is_empty():
			return
		Art.draw(self, size * 0.5, minf(size.x, size.y) * 0.5, spec, team_col)

class RecItemCard extends Control:
	# 推荐装备卡：数据由 _update_recommended_equip 推送，绘制走 UiKit.rec_card（host/客户端共用）
	signal buy_requested
	var item_name := ""
	var tier := 2
	var cost := 0
	var gold := 0
	var maxed := false
	var slot_full := false
	var desc := ""                  # 装备效果一行简介（passive 首句，卡上小字显示）
	var tap_buy := false            # true=点一下直接买（推荐位自选卡）；false=点按只收/展（主推荐卡）
	var left_full := -362.0         # 展开态左偏移（右锚定；主卡 246 宽：-362..-116）
	var left_collapsed := -208.0    # 收起态左偏移（只留图标宽度）
	var collapsed := false          # 点按收起：只留右侧装备图标
	var _last_should_collapse := false
	var _glow_t := 0.0              # 可购买发光拖尾相位（仅 affordable 时推进）
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
				offset_left = left_collapsed
				queue_redraw()
		elif collapsed:
			collapsed = false
			offset_left = left_full
			queue_redraw()
	func _gui_input(ev: InputEvent) -> void:
		var is_tap := false
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			is_tap = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif ev is InputEventScreenTouch:
			is_tap = (ev as InputEventScreenTouch).pressed
		if is_tap:
			# 自选卡：点一下就买；主推荐卡：收起态点击=展开，展开且买不起时才允许点回收起（购买走右侧“+”）
			if tap_buy:
				buy_requested.emit()
				accept_event()
				return
			if collapsed:
				collapsed = false
				offset_left = left_full
			elif not affordable():
				collapsed = true
				offset_left = left_collapsed    # 收起态宽度必须容得下图标本身
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
				# 暂不可购买：叠灰罩 + 灰字
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
			# 图标矩形与 UiKit.rec_card 内部一致（窄卡会收缩图标）
			var ic := UiKit.rec_icon_rect(Rect2(Vector2.ZERO, size))
			_glow_ring(ic.get_center(), ic.size.x * 0.5 + 5.0)
	# 图标四周一圈旋转发光拖尾：3 段渐变弧随时间旋转、尾端淡出
	func _glow_ring(c: Vector2, r: float) -> void:
		for gi in 3:
			var a0 := _glow_t * 3.2 + TAU * float(gi) / 3.0
			for gk in 6:
				var gt := float(gk) / 6.0
				draw_arc(c, r + gt * 7.0, a0, a0 + 1.0, 10,
					Color(1.0, 0.86, 0.32, (1.0 - gt) * 0.6), 5.0 - gt * 2.6, true)

class SkillIcon extends Control:
	var skill: Skill = null
	var cd_remaining: float = 0.0
	var max_cd: float = 1.0
	var mana_cost: int = 0
	var current_mana: int = 0
	var skill_level: int = 1
	var hero :Hero= null
	var slot = 0
	var is_active_equip: bool = false
	var active_equip_id: String = ""
	var blue: bool = false
	var _glow_t := 0.0              # 可升级“+”发光相位
	var _last_cd := 0.0             # 上一帧冷却（检测「刚好转好」）
	var _ready_t := 0.0             # 就绪动画剩余时间
	const READY_ANIM := 0.55
	func _process(delta: float) -> void:
		# 冷却刚好归零 → 播一次就绪动画（金环扩散 + 白闪）
		var cd := maxf(0.0, cd_remaining)
		if _last_cd > 0.0005 and cd <= 0.01 and max_cd > 0.05 and skill_level > 0:
			_ready_t = READY_ANIM
		_last_cd = cd
		if _ready_t > 0.0:
			_ready_t = maxf(0.0, _ready_t - delta)
			queue_redraw()
		if hero and hero.skill_points > 0 and slot < 3 and hero.can_upgrade_skill(slot):
			_glow_t += delta
			queue_redraw()
	func _draw():
		var center = size / 2; var radius = min(size.x, size.y) / 2 - 2
		# 蓝=就绪，灰=冷却/无法力/未学习
		var bg_color = Color.DIM_GRAY
		if skill_level > 0:
			if cd_remaining <= 0:
				if is_active_equip or slot >= 5:
					bg_color = Color.ROYAL_BLUE
				elif current_mana >= mana_cost:
					bg_color = Color.ROYAL_BLUE
		if blue :bg_color = Color.ROYAL_BLUE
		SkillArt.draw_bg(self, center, radius, str(hero.display_name) if hero else "", skill, slot,
			skill_level > 0, skill_level > 0 and cd_remaining <= 0.0 and current_mana >= mana_cost)
		# CD圆弧
		if max_cd > 0 and cd_remaining > 0 and skill_level > 0:
			var ratio = cd_remaining / max_cd
			var end_angle = -PI/2 + 2 * PI * ratio
			draw_arc(center, radius + 4, -PI/2, end_angle, 32, Color(0, 0, 0, 0.6), 4.0)
		# 冷却就绪动画：白闪 + 两圈金色扩散环（不挡技能图标，纯叠加绘制）
		if _ready_t > 0.0:
			var p: float = 1.0 - _ready_t / READY_ANIM
			var a: float = 1.0 - p
			draw_circle(center, radius, Color(1.0, 0.97, 0.86, 0.28 * a))
			draw_arc(center, radius * (1.0 + 0.55 * p), 0.0, TAU, 48,
				Color(1.0, 0.86, 0.36, 0.92 * a), maxf(1.0, 5.5 * a), true)
			draw_arc(center, radius * (0.92 + 0.30 * p), 0.0, TAU, 40,
				Color(1.0, 1.0, 0.94, 0.5 * a), maxf(1.0, 2.5 * a), true)
		# 方案A：就绪不写字，冷却只显示整数秒；文字统一描边并真正居中
		var font = UiKit.font()
		var text := ""
		if skill_level > 0 and cd_remaining > 0:
			text = str(ceili(cd_remaining))
		if text != "":
			var fs := 26
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			UiKit.text(self, center + Vector2(-tw * 0.5, fs * 0.36), text, fs,
				Color(0.97, 0.94, 0.86))
		if hero and hero.skill_points > 0 and slot < 3 and hero.can_upgrade_skill(slot):
			# 小而克制的右上角金色升级点，不再用 60px 大加号压住技能图标
			var pp: Vector2 = center + Vector2(radius * 0.70, -radius * 0.70)
			draw_circle(pp, maxf(7.0, radius * 0.16), Color(1.0, 0.84, 0.30, 0.96))
			draw_arc(pp, maxf(7.0, radius * 0.16), 0, TAU, 20, Color(1, 1, 1, 0.65), 1.2, true)
			draw_string(font, pp + Vector2(-6, 6), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.12, 0.09, 0.04))

class StatIcon extends Control:
	# 属性徽章“图标”：程序化彩色圆徽章 + 中央「图形图标」（爱心=生命、剑=物理攻击…）。
	# 字体缺字形（爱心/剑等符号在引擎字体里没有），所以全部用绘图指令画出来；
	# shape 为空时回退单字字形 glyph，兼容旧调用。
	var glyph := "攻"
	var shape := ""
	var tint := Color.WHITE
	
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示，不拦截触摸
	func _draw():
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, tint.darkened(0.62))
		draw_arc(c, r, 0, TAU, 24, tint, 2.0, true)
		if shape != "":
			_draw_shape(c, minf(size.x, size.y) * 0.36, tint.lightened(0.35))
			return
		var fs := maxi(10, int(r * 1.05))
		draw_string(UiKit.font(), Vector2(c.x - r, c.y + fs * 0.18),
				glyph, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, tint.lightened(0.25))
	# 以 c 为中心、k 为单位半径（符号最远到 ±k，圆内径约 0.5*min 远超 k），逐笔画矢量图标
	func _draw_shape(c: Vector2, k: float, col: Color):
		match shape:
			"heart":  # 爱心=生命（双圆 + 下三角）
				draw_circle(c + Vector2(-0.42 * k, -0.12 * k), k * 0.5, col)
				draw_circle(c + Vector2(0.42 * k, -0.12 * k), k * 0.5, col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.92 * k, 0.0), c + Vector2(0.92 * k, 0.0), c + Vector2(0.0, 0.98 * k)]), col)
			"sword":  # 剑=物理攻击（斜刃 + 护手 + 剑柄球）
				var e0 := c + Vector2(-0.5 * k, 0.7 * k)
				var e1 := c + Vector2(0.85 * k, -0.55 * k)
				var d := (e1 - e0).normalized()
				var n := Vector2(-d.y, d.x)
				draw_line(e0 - n * k * 0.28, e0 + n * k * 0.28, col, 1.8)   # 护手
				draw_line(e0, e1, col, 3.0)                                # 刃身
				draw_circle(e0 - d * k * 0.18, k * 0.1, col)               # 柄部圆球
			"spark":  # 四芒星=法术强度
				var pts := PackedVector2Array()
				for i in range(8):
					var ang := float(i) * PI / 4.0 + PI / 8.0
					var rad := k * 0.85 if i % 2 == 0 else k * 0.2
					pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
				draw_colored_polygon(pts, col)
			"shield":  # 盾=护甲
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.82 * k, -0.7 * k), c + Vector2(0.82 * k, -0.7 * k),
					c + Vector2(0.82 * k, 0.1 * k), c + Vector2(0.0, 0.96 * k), c + Vector2(-0.82 * k, 0.1 * k)]), col)
			"gem":  # 菱形宝石=魔抗
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.0, -0.92 * k), c + Vector2(0.66 * k, -0.22 * k),
					c + Vector2(0.0, 0.92 * k), c + Vector2(-0.66 * k, -0.22 * k)]), col)
			"chev":  # 双层右箭头=移速
				for sx in PackedFloat32Array([0.0, 0.45]):
					var xo: float = c.x + sx * k
					draw_line(Vector2(xo - k * 0.3, c.y - k * 0.5), Vector2(xo + k * 0.05, c.y), col, 2.0)
					draw_line(Vector2(xo - k * 0.3, c.y + k * 0.5), Vector2(xo + k * 0.05, c.y), col, 2.0)
			"bolt":  # 闪电=攻击速度
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.15 * k, -0.95 * k), c + Vector2(-0.7 * k, 0.16 * k), c + Vector2(-0.05 * k, 0.16 * k),
					c + Vector2(-0.15 * k, 0.95 * k), c + Vector2(0.7 * k, -0.16 * k), c + Vector2(0.05 * k, -0.16 * k)]), col)
			"drop":  # 水滴=蓝量
				draw_circle(c + Vector2(0.0, -0.2 * k), k * 0.52, col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.52 * k, -0.06 * k), c + Vector2(0.52 * k, -0.06 * k), c + Vector2(0.0, 0.98 * k)]), col)
			"cross":  # 准星=暴击率
				draw_arc(c, k * 0.4, 0, TAU, 24, col, 1.6, true)
				draw_line(c, c + Vector2(0, -k * 0.68), col, 2.0)
				draw_line(c, c + Vector2(0, k * 0.68), col, 2.0)
				draw_line(c, c + Vector2(-k * 0.68, 0), col, 2.0)
				draw_line(c, c + Vector2(k * 0.68, 0), col, 2.0)
				draw_circle(c, k * 0.1, col)
			"dmg":  # 交叉斩=暴击伤害
				draw_line(c + Vector2(-0.68 * k, -0.68 * k), c + Vector2(0.68 * k, 0.68 * k), col, 2.6)
				draw_line(c + Vector2(0.68 * k, -0.68 * k), c + Vector2(-0.68 * k, 0.68 * k), col, 2.6)
			"pierce":  # 破甲箭=物理/法术穿透（箭矢贯穿甲板）
				draw_line(c + Vector2(-0.85 * k, 0.38 * k), c + Vector2(0.85 * k, 0.38 * k), col, 2.0)
				draw_line(c + Vector2(0.0, 0.55 * k), c + Vector2(0.0, -0.6 * k), col, 2.2)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.0, -0.98 * k), c + Vector2(-0.24 * k, -0.56 * k), c + Vector2(0.24 * k, -0.56 * k)]), col)
			"tough":  # 盾+对勾=韧性
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-0.8 * k, -0.7 * k), c + Vector2(0.8 * k, -0.7 * k),
					c + Vector2(0.8 * k, 0.1 * k), c + Vector2(0.0, 0.95 * k), c + Vector2(-0.8 * k, 0.1 * k)]), col)
				draw_line(c + Vector2(-0.4 * k, 0.05 * k), c + Vector2(-0.12 * k, 0.33 * k), Color.WHITE, 2.2)
				draw_line(c + Vector2(-0.12 * k, 0.33 * k), c + Vector2(0.42 * k, -0.28 * k), Color.WHITE, 2.2)
			"clock":  # 表盘=冷却缩减
				draw_arc(c, k * 0.68, 0, TAU, 28, col, 1.8, true)
				draw_line(c, c + Vector2(0, -k * 0.4), col, 1.8)
				draw_line(c, c + Vector2(k * 0.36, 0), col, 1.8)
				draw_circle(c, k * 0.07, col)

class BadgeBox extends Control:
	# 圆角“图标块”：暗底 + 品级/类别色边框与顶带 + 中央单字图标（无美术资源的程序化图标）
	var glyph := ""
	var tint := Color.WHITE
	var border := Color(1, 1, 1, 0.25)
	var glyph_size := 0.0
	
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw():
		var sb := UiKit.flat(0.72, int(maxf(4.0, minf(size.x, size.y) * 0.14)), 2, border,
			Color(0.03, 0.05, 0.08, 0.72), 0.0)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(0, 0, size.x, 3), tint, true)
		if glyph != "":
			var fs := int(glyph_size) if glyph_size > 0.0 else int(size.y * 0.5)
			draw_string(UiKit.font(), Vector2(0, size.y * 0.5 + fs * 0.18),
					glyph, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, tint.lightened(0.35))

class HeroDisc extends Control:
	# 英雄“头像圆盘”：阵营色外环 + 血量状态弧 + 职业字符（刺客/法师/射手/战士/辅助）
	var role := ""
	var team := 0
	var dead := false
	var hp_ratio := 1.0
	
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _role_style() -> Array:
		match role:
			"刺客": return ["刺", Color(0.95, 0.55, 0.95)]
			"法师": return ["法", Color(0.55, 0.62, 1.0)]
			"射手": return ["射", Color(1.0, 0.62, 0.28)]
			"战士": return ["战", Color(1.0, 0.42, 0.3)]
			"辅助": return ["辅", Color(0.45, 0.9, 0.55)]
			_: return ["英", Color(0.9, 0.9, 0.9)]
	func _draw():
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var st := _role_style()
		var team_col := Color(0.0, 0.886, 1.0) if Config.is_ally(team) else Color(1.0, 0.33, 0.264)
		if dead: team_col = Color(0.32, 0.32, 0.36)
		# 外环 + 暗色内盘
		draw_circle(c, r, Color(0.02, 0.04, 0.07, 0.92))
		draw_arc(c, r, 0, TAU, 32, team_col, 3.0, true)
		# 血量状态弧（从 12 点顺时针，绿→黄→红）
		if not dead and hp_ratio > 0.0:
			var hc := Color(0.35, 1.0, 0.5) if hp_ratio > 0.5 \
					else Color(1.0, 0.85, 0.25) if hp_ratio > 0.25 else Color(1.0, 0.3, 0.3)
			draw_arc(c, r - 5, -PI / 2, -PI / 2 + TAU * clampf(hp_ratio, 0.0, 1.0), 24, hc, 3.0, true)
		var glyph: String = st[0]
		var fs := int(r * 0.8)
		draw_string(UiKit.font(), Vector2(c.x - r, c.y + fs * 0.2),
				glyph, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, st[1].lightened(0.25))

class RespawnWidget extends Control:
	signal spectate_clicked(hero: Hero)
	const HeroArt = preload("res://scripts/ui/HeroArt.gd")
	# 左侧英雄圆圈头像（整体 ×1.25 放大；Request B 初版 ×1.5 → 微调复位 ×1.25）
	var hero: Hero = null
	var ring_radius: float = 45.0 * 1.25
	var spectatable := false
	var spectating := false
	var _hover := false

	func _ready():
		# 单元尺寸 ×1.25：环形头像(直径≈112.5)放进 130px 单元内不互相挤碰
		custom_minimum_size = Vector2(104 * 1.25, 118.0)
		if spectatable:
			mouse_filter = Control.MOUSE_FILTER_STOP
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			tooltip_text = "点击切换视角，观战该队友"
			mouse_entered.connect(func(): _hover = true; queue_redraw())
			mouse_exited.connect(func(): _hover = false; queue_redraw())
		else:
			mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示，不拦截触摸
		set_process(true)

	func _gui_input(event):
		if not spectatable:
			return
		var pressed := false
		if event is InputEventMouseButton:
			pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			pressed = event.pressed
		if pressed:
			accept_event()
			spectate_clicked.emit(hero)

	func _process(_delta): queue_redraw()
	func _draw():
		if not is_instance_valid(hero): return
		var center = size / 2
		if spectatable:
			var ring_col := Color(1.0, 0.86, 0.32, 0.95) if spectating else Color(0.75, 0.92, 1.0, 0.9 if _hover else 0.5)
			draw_arc(center, ring_radius + 7.5, 0, 2 * PI, 48, ring_col, 4.5 if spectating else 2.5, true)
		var bg_color = Color(0.0, 0.886, 1.0, 1.0) if Config.is_ally(hero.team) else Color(1.0, 0.33, 0.264, 1.0)
		# 阵亡后底色变深：我方=近黑，敌方(第二排)=暗红，一眼区分两排归属
		if hero.is_dead:
			bg_color = Color(0.32, 0.05, 0.07, 1.0) if not Config.is_ally(hero.team) else Color(0.04, 0.05, 0.07, 1.0)
		# 专属英雄徽记头像（取代原来的纯色圆盘；阵营色留在最外细边，血弧/阵亡压暗不变）
		var team_tint := Color(0.0, 0.886, 1.0) if Config.is_ally(hero.team) else Color(1.0, 0.33, 0.264)
		HeroArt.draw_portrait(self, center, ring_radius, hero.display_name, team_tint, hero.is_dead)
		draw_arc(center, ring_radius + 3.75, 0, 2*PI, 48, Color.BLACK, 5.0)
		if hero.is_dead:
			var progress = 1.0 - (hero.respawn_timer / hero.respawn_time_total)
			draw_arc(center, ring_radius + 3.75, -PI/2, -PI/2 + 2*PI*progress, 48, Color.WHITE, 5.0)
			UiKit.text(self, Vector2(center.x - ring_radius, center.y + 9.0), str(int(ceil(hero.respawn_timer))), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, ring_radius * 2.0)
		else:
			var hp_ratio = hero.health / hero.actual_max_health
			var hp_color = Color.GREEN if hp_ratio > 0.5 else Color.YELLOW if hp_ratio > 0.25 else Color.RED
			draw_arc(center, ring_radius + 3.75, -PI/2, -PI/2 + 2*PI*hp_ratio, 48, hp_color, 5.0)
		# 鲁班七号被动扫射层数显示
		if hero.display_name == "鲁班七号" and not hero.is_dead:
			var passive_ready = hero.luban_skill_enhanced or hero.luban_passive_stacks >= 5
			var stack_str = "扫射 %d/5" % hero.luban_passive_stacks
			var stack_color = UiKit.C_GOLD if passive_ready else Color(0.75, 0.75, 0.75)
			UiKit.text(self, Vector2(center.x - ring_radius, center.y + 33.75), stack_str, 18, stack_color, HORIZONTAL_ALIGNMENT_CENTER, ring_radius * 2.0)
		var tri_size = 9.375; var start_y = ring_radius*2 + 18.75
		var positions = [center.x - 28.125, center.x, center.x + 28.125]
		for i in range(3):
			var x = positions[i]; var y = start_y
			var col = Color.GREEN if i < hero.skill_cooldowns.size() and hero.skill_cooldowns[i] <= 0 else Color.GRAY
			draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x - tri_size, y + tri_size*2), Vector2(x + tri_size, y + tri_size*2)]), [col])

class DamageChart extends Control:
	var damage_data: Dictionary = {}
	var bar_width: float = 30.0
	var bar_spacing: float = 10.0
	var chart_height: float = 200.0

	
	func _ready():
		custom_minimum_size = Vector2(400, chart_height + 40)
		set_process(false)

	func set_data(data: Dictionary):
		damage_data = data
		queue_redraw()

	func _draw():
		if damage_data.is_empty(): return
		var x_start = 10.0
		var bottom_y = size.y - 25
		var max_total = 1.0
		for src in damage_data.values():
			var total = 0.0
			for skill in src.values():
				total += skill["physical"] + skill["magical"]
			if total > max_total: max_total = total

		var font = UiKit.font()
		for src_name in damage_data.keys():
			var src_data = damage_data[src_name]
			var group_center = x_start + bar_width / 2
			var skill_keys = ["attack", "skill1", "skill2", "skill3", "fire"]
			var skill_labels = ["普攻", "技1", "技2", "技3", "灼烧"]
			for i in range(skill_keys.size()):
				var key = skill_keys[i]
				if src_data.has(key):
					var skill = src_data[key]
					var phys = skill.get("physical", 0.0)
					var mag = skill.get("magical", 0.0)
					var total = phys + mag
					if total <= 0: continue

					var bar_height = (total / max_total) * chart_height
					var bar_x = group_center - bar_width/2 + i * (bar_width + bar_spacing)
					var bar_y = bottom_y - bar_height

					var phys_ratio = phys / total if total > 0 else 0.0
					var phys_height = bar_height * phys_ratio
					draw_rect(Rect2(bar_x, bottom_y - phys_height, bar_width, phys_height), Color.ORANGE)
					var mag_height = bar_height - phys_height
					draw_rect(Rect2(bar_x, bar_y, bar_width, mag_height), Color.PURPLE)

					var dmg_text = str(int(total))
					var text_width = len(dmg_text) * 8
					draw_string(font, Vector2(bar_x + bar_width/2 - text_width/2, bar_y - 12), dmg_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
					var label = skill_labels[i]
					var label_width = len(label) * 8
					draw_string(font, Vector2(bar_x + bar_width/2 - label_width/2, bottom_y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

			var name_width = len(src_name) * 8
			draw_string(font, Vector2(group_center - name_width/2, bottom_y + 20), src_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
			x_start += (bar_width + bar_spacing) * 4 + 20

class ValuePopup extends Control:
	# 战场漂浮数值（金币 / 治疗）：左侧矢量徽标 + 数值，停留约2秒后淡出。
	# fallback 字体没有剑/金币/十字字形，整个弹出全部用 draw_* 指令矢量绘制。
	var text := ""
	var icon := "coin"          # coin / sword / cross / thumb
	var icon2 := ""             # 第二枚徽标（非补刀金币 = 👍 + 金币）
	var col := Color(1.0, 0.84, 0.35)
	var rs := 1.0
	var fs := 34
	func setup(txt: String, icon_kind: String, color: Color, scale: float, font_size: int = 34, icon_kind2: String = "") -> void:
		text = txt
		icon = icon_kind
		icon2 = icon_kind2
		col = color
		rs = scale
		fs = font_size
		var m := measure()
		custom_minimum_size = m
		size = m   # 直接作为 CanvasLayer 的子节点，无容器自动布局，需显式给尺寸
		mouse_filter = Control.MOUSE_FILTER_IGNORE   # 纯显示，不拦截触摸
		queue_redraw()
	func _icon_w() -> float:
		var w: float = round((26.0 if icon == "cross" else 30.0) * rs)
		if icon2 == "":
			return w
		return w + round(5.0 * rs) + round((26.0 if icon2 == "cross" else 30.0) * rs)
	func measure() -> Vector2:
		var font: Font = UiKit.font()
		var px := int(round(fs * rs))
		var asc := font.get_ascent(px)
		var desc := font.get_descent(px)
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var icon_w: float = _icon_w()
		var gap: float = round(8 * rs)
		return Vector2(icon_w + gap + text_w, maxf(asc + desc, icon_w * 1.15))
	func _draw():
		var font: Font = UiKit.font()
		var px := int(round(fs * rs))
		var asc := font.get_ascent(px)
		var desc := font.get_descent(px)
		var icon_w: float = _icon_w()
		var w1: float = round((26.0 if icon == "cross" else 30.0) * rs)
		var ic_center := Vector2(w1 * 0.5, size.y * 0.5)
		match icon:
			"sword":
				_draw_sword(ic_center, w1)
			"cross":
				_draw_cross(ic_center, w1)
			"thumb":
				_draw_thumb(ic_center, w1)
			_:
				_draw_coin(ic_center, w1)
		if icon2 != "":
			var w2: float = round((26.0 if icon2 == "cross" else 30.0) * rs)
			var c2 := Vector2(w1 + round(5.0 * rs) + w2 * 0.5, size.y * 0.5)
			match icon2:
				"sword":
					_draw_sword(c2, w2)
				"cross":
					_draw_cross(c2, w2)
				"thumb":
					_draw_thumb(c2, w2)
				_:
					_draw_coin(c2, w2)
		var x0: float = icon_w + round(8 * rs)
		var baseline := size.y * 0.5 - (asc + desc) * 0.5 + asc
		draw_string_outline(font, Vector2(x0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
				-1, px, maxi(2, int(round(px * 0.22))), Color(0.10, 0.06, 0.02, 0.95))
		draw_string(font, Vector2(x0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	# 金色小剑（与 StatIcon 的 sword 图形同款坐标，k 以图标格宽为单位）
	func _draw_sword(c: Vector2, w: float) -> void:
		var k: float = w * 0.36
		var e0 := c + Vector2(-0.5 * k, 0.7 * k)
		var e1 := c + Vector2(0.85 * k, -0.55 * k)
		var d := (e1 - e0).normalized()
		var n := Vector2(-d.y, d.x)
		draw_line(e0 - n * k * 0.28, e0 + n * k * 0.28, col, 2.2)   # 护手
		draw_line(e0, e1, col, 3.6)                                  # 刃身
		draw_circle(e0 - d * k * 0.18, maxf(1.2, k * 0.12), col)    # 柄部圆球
	# 治疗十字：圆角底 + 粗十字，和伤害数字明显区分
	func _draw_cross(c: Vector2, w: float) -> void:
		var k: float = w * 0.30
		var tw: float = maxf(2.4, k * 0.46)
		draw_circle(c, w * 0.36, Color(0, 0, 0, 0.35))
		draw_line(c + Vector2(-k, 0), c + Vector2(k, 0), col, tw)
		draw_line(c + Vector2(0, -k), c + Vector2(0, k), col, tw)
		draw_circle(c, tw * 0.5, Color(1, 1, 1, 0.55))
	# 👍（非补刀金币）：矢量竖大拇指 —— fallback 字体没有 emoji 字形，只能自己画
	func _draw_thumb(c: Vector2, w: float) -> void:
		var k: float = w * 0.30
		var line: Color = Color(0.12, 0.07, 0.02, 0.55)
		# 手掌：圆 + 矩形叠成圆角块
		draw_circle(c + Vector2(0.30 * k, 0.42 * k), 0.72 * k, col)
		draw_rect(Rect2(c + Vector2(-0.42 * k, -0.32 * k), Vector2(0.72 * k, 1.44 * k)), col)
		# 拇指：斜向上 + 圆头
		var t0 := c + Vector2(0.02 * k, -0.26 * k)
		var t1 := c + Vector2(-0.62 * k, -1.02 * k)
		draw_line(t0, t1, col, maxf(2.0, 0.46 * k))
		draw_circle(t1, maxf(1.4, 0.30 * k), col)
		# 袖口
		draw_rect(Rect2(c + Vector2(-0.42 * k, 0.86 * k), Vector2(1.5 * k, 0.34 * k)), col.darkened(0.24))
		# 指缝：三条暗线，读成手指
		for n in range(3):
			var y: float = c.y + (0.10 + 0.34 * float(n)) * k
			draw_line(Vector2(c.x - 0.30 * k, y), Vector2(c.x + 0.92 * k, y), line, maxf(1.0, 0.10 * k))
		# 高光
		draw_circle(c + Vector2(-0.10 * k, -0.05 * k), maxf(1.0, 0.12 * k), Color(1, 1, 1, 0.45))

	# 金币：外圈金环 + 内圈亮面 + 高光弧 + 底部投影
	func _draw_coin(c: Vector2, w: float) -> void:
		var r: float = w * 0.38
		draw_circle(c + Vector2(0.8, 1.2), r, Color(0, 0, 0, 0.40))
		draw_circle(c, r, col.darkened(0.28))
		draw_circle(c, r * 0.84, col)
		draw_circle(c, r * 0.50, col.darkened(0.34))
		draw_arc(c, r * 0.84, PI * 1.10, PI * 1.62, 10, Color(1, 1, 1, 0.55), maxf(1.0, r * 0.18))

class BuffIcon extends Control:
	const BuffArt = preload("res://scripts/ui/BuffArt.gd")
	# 底部 Buff 图标：色环圆盘 + 中央单字 + 剩余时间的扇形冷却遮罩 + 底部小字（秒数/层数）
	# 原 66×68、半径26；按要求整体放大 2 倍（圆盘、字形、小字同步放大）
	const CELL_W := 132.0
	const CELL_H := 136.0
	var key := ""
	var glyph := "?"
	var tint := Color.WHITE
	var display_name := ""
	var effect_desc := ""
	var remaining := 0.0
	var steady := false          # 无持续时间的常驻状态（打野层数 / 强化普攻就绪），不画扇形
	var sub_text := ""           # 圆下方小字：剩余秒数 或 层数
	var selected := false        # 点击选中，画高亮圈
	var R := 52.0
	var _draw_total := 0.0       # 扇形占比的总时长（传入的总长，否则记录运行时见过的最大剩余）
	
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(CELL_W, CELL_H)
	func apply(c: Dictionary):
		glyph = c.glyph
		tint = c.tint
		display_name = c.name
		effect_desc = c.desc
		remaining = float(c.remaining)
		steady = bool(c.steady)
		if str(c.get("sub", "")) != "":
			sub_text = str(c.sub)
		elif steady:
			sub_text = ""
		elif remaining > 0.0:
			sub_text = "%ds" % int(ceil(remaining))
		else:
			sub_text = ""
		if not steady:
			var tot := float(c.total)
			if tot > 0.0:
				_draw_total = tot
			elif remaining > _draw_total:
				_draw_total = remaining
		size = Vector2(CELL_W, CELL_H)
		queue_redraw()
	func _draw():
		var cx := size.x * 0.5
		var cy := R
		var center := Vector2(cx, cy)
		var font: Font = UiKit.font()
		# 底色圆盘
		draw_circle(center, R, Color(0.02, 0.05, 0.1, 0.95))
		# 内圈淡色衬底（类别色）
		draw_circle(center, R - 14.0, Color(tint.r, tint.g, tint.b, 0.16))
		# 扇形冷却：自正上方顺时针覆盖“已流逝”的部分 → 剩余越少，图标越暗
		if not steady and _draw_total > 0.0 and remaining > 0.0:
			var frac := clampf(remaining / _draw_total, 0.0, 1.0)
			var elapsed := 1.0 - frac
			if elapsed > 0.02:
				var segs := 26
				var pts := PackedVector2Array()
				pts.append(center)
				for i in range(segs + 1):
					var ang := -PI / 2.0 + TAU * elapsed * float(i) / float(segs)
					pts.append(center + Vector2(cos(ang), sin(ang)) * R)
				draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		# 外圈（选中时金色高亮）
		draw_arc(center, R, 0, TAU, 40, Color(1.0, 0.9, 0.42) if selected else tint, 7.0 if selected else 6.0)
		# 中央专属图标：按 buff key 选程序化纹样（同类状态共享一套图形语言）
		BuffArt.draw_buff(self, center, R * 0.62, key, tint)
		# 底部小字
		if sub_text != "":
			draw_string(font, Vector2(0.0, size.y - 4.0), sub_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.92))

class CritMark extends Control:
	# 暴击伤害弹出：伤害数字左前方的四芒星爆点（纯 draw_* 矢量绘制）
	
	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw():
		var c := size * 0.5
		var k := minf(size.x, size.y) * 0.5
		var gold := Color(1.0, 0.8, 0.15, 1.0)
		var hot := Color(1.0, 0.45, 0.2, 1.0)
		# 外层：金色四芒星（爆点）
		var pts := PackedVector2Array()
		for i in range(8):
			var ang := float(i) * PI / 4.0 + PI / 8.0
			var rad := k if i % 2 == 0 else k * 0.22
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts, gold)
		# 内层：橙红小星（叠色增强“暴”感）
		var pts2 := PackedVector2Array()
		for i in range(8):
			var ang := float(i) * PI / 4.0 + PI / 8.0
			var rad := k * 0.48 if i % 2 == 0 else k * 0.14
			pts2.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts2, hot)

# 统一装备图标格：品质色底 + 名称首字（与推荐装/装备栏/英雄面板同一套 item_icon）
class ItemIconBox extends Control:
	var item_name := ""
	var tier := 1
	var dim := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if item_name == "":
			draw_style_box(UiKit.flat(0.5, 6, 1, Color(0.30, 0.36, 0.46, 0.5), Color(0.06, 0.07, 0.10, 0.55), 0.0, 0.0), r)
			var efs := int(clampf(r.size.y * 0.16, 12.0, 22.0))
			UiKit.text(self, Vector2(0.0, r.size.y * 0.5 + efs * 0.36), "空", efs, Color(0.42, 0.48, 0.58),
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
			return
		UiKit.item_icon(self, r, tier, item_name)
		if dim:
			draw_rect(r, Color(0.0, 0.0, 0.0, 0.5))

# ---------- 商店键位与购买反馈（P1） ----------
func _shop_handle_key(ev: InputEventKey) -> bool:
	var kc: int = ev.keycode
	match kc:
		KEY_ESCAPE:
			_close_shop()
			return true
		KEY_UP, KEY_W:
			_shop_move_sel(-1)
			return true
		KEY_DOWN, KEY_S:
			_shop_move_sel(1)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			if shop_selected_item != "":
				_shop_quick_buy(shop_selected_item)
			return true
	var cats: Array = ["推荐"]
	for k in _shop_categories().keys():
		cats.append(str(k))
	var idx := -1
	match kc:
		KEY_1: idx = 0
		KEY_2: idx = 1
		KEY_3: idx = 2
		KEY_4: idx = 3
		KEY_5: idx = 4
		KEY_6: idx = 5
		KEY_7: idx = 6
		KEY_8: idx = 7
		KEY_9: idx = 8
	if idx >= 0 and idx < cats.size():
		_on_category_selected(str(cats[idx]))
		return true
	return false

func _shop_move_sel(d: int) -> void:
	if shop_grid_ids.is_empty():
		return
	var i: int = shop_grid_ids.find(shop_selected_item)
	if i < 0:
		i = 0
	else:
		i = clampi(i + d, 0, shop_grid_ids.size() - 1)
	_on_shop_item_selected(str(shop_grid_ids[i]))
	if shop_grid_scroll != null and shop_item_grid != null and i < shop_item_grid.get_child_count():
		shop_grid_scroll.ensure_control_visible(shop_item_grid.get_child(i))

func _shop_missing_cost(missing: Array) -> int:
	var s := 0
	for rid in missing:
		var it: Dictionary = ItemDatabase.get_item(str(rid))
		if not it.is_empty():
			s += int(it.get("cost", 0))
	return s

## 一键买齐目标装备的直接素材（两轮：素材本身也可能由小件合成）
func _shop_buy_missing(target: String) -> void:
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or not battle.hero:
		return
	var hero = battle.hero
	var got := 0
	for _pass in range(2):
		var item: Dictionary = ItemDatabase.get_item(target)
		if item.is_empty():
			break
		for rid in item.get("requires", []):
			var sid := str(rid)
			if hero.equipment_slots.has(sid):
				continue
			if hero.buy_equipment(sid):
				got += 1
	if got > 0:
		SfxManager.play_ui_sfx("buy")
		_refresh_shop_all()
		_shop_toast("已补齐 %d 件素材" % got)
	else:
		_shop_toast("购买失败（金币不足或栏位已满）", true)

func _shop_toast(txt: String, bad: bool = false) -> void:
	if shop_ui == null or not is_instance_valid(shop_ui):
		return
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(420.0, 0)
	l.add_theme_font_size_override("font_size", int(round(18 * ui_scale())))
	l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if bad else Color(0.58, 1.0, 0.62))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_ui.add_child(l)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	l.position = Vector2(vp.x * 0.5 - 210.0, vp.y * 0.14)
	var tw2 := l.create_tween()
	tw2.tween_property(l, "modulate:a", 0.0, 0.75).set_delay(0.55)
	tw2.tween_callback(Callable(l, "queue_free"))
## 商店差价（正确口径）：总价 - 仅「已拥有」素材的价格；ItemDatabase.get_synthesis_cost 会抵扣全部素材，不能用于显示
func _shop_pay_for(id: String, hero) -> int:
	var it: Dictionary = ItemDatabase.get_item(id)
	if it.is_empty():
		return 0
	var cost: int = int(it.get("cost", 0))
	var requires: Array = it.get("requires", [])
	if requires.is_empty():
		return cost
	var rem: Array = requires.duplicate()
	var off := 0
	for oid in hero.equipment_slots:
		var idx: int = rem.find(oid)
		if idx >= 0:
			var ri: Dictionary = ItemDatabase.get_item(str(oid))
			if not ri.is_empty():
				off += int(ri.get("cost", 0))
			rem.remove_at(idx)
	return maxi(cost - off, 0)


# ---------- 目标信息面板：质感装饰层（纯视觉，不参与交互） ----------
class TargetAccentShine extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		# 顶部色条：左亮右隐的玻璃高光 + 1px 冷光顶边
		var steps := 14
		for i in range(steps):
			var a := 0.24 * (1.0 - float(i) / float(steps))
			draw_rect(Rect2(w * float(i) / float(steps), 0, w / float(steps) + 1.0, h),
				Color(1, 1, 1, a))
		draw_rect(Rect2(0, 0, w, 1.0), Color(1, 1, 1, 0.32))


class TargetHpGloss extends Control:
	var max_hp := 1000.0
	var hp := 1000.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 2.0 or h <= 2.0:
			return
		var ratio := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
		var fill_w: float = maxf(3.0, w * ratio)
		# 1) 填充区竖向渐变高光（上亮下暗，做出金属/玻璃厚度）
		var steps := 6
		for i in range(steps):
			var t := float(i) / float(steps)
			draw_rect(Rect2(0.0, t * h * 0.55, fill_w, h * 0.55 / float(steps) + 1.0),
				Color(1, 1, 1, 0.11 * (1.0 - t)))
		# 2) 填充底部内阴影
		draw_rect(Rect2(0.0, h * 0.68, fill_w, h * 0.32), Color(0, 0, 0, 0.20))
		# 3) 末端亮边 + 向后柔光，血条推进方向更醒目
		if fill_w > 5.0:
			draw_rect(Rect2(fill_w - 2.0, 2.0, 1.6, h - 4.0), Color(1, 1, 1, 0.55))
			for gi in 3:
				draw_rect(Rect2(fill_w - 5.0 - gi * 2.0, 3.5, 1.2, h - 7.0),
					Color(1, 1, 1, maxf(0.0, 0.13 - gi * 0.035)))
		# 4) 10% 刻度（细线，填充/空白区都可见，用来快速判读血量）
		var step_w := w * 0.1
		var x := step_w
		while x < w - 2.0:
			draw_rect(Rect2(x, 2.0, 1.0, h - 4.0), Color(0, 0, 0, 0.20))
			x += step_w
		# 5) 上下边缘的玻璃反光 / 内暗线，让条体更立体
		draw_rect(Rect2(10.0, 1.4, maxf(w - 20.0, 0.0), 1.2), Color(1, 1, 1, 0.18))
		draw_rect(Rect2(10.0, h - 2.8, maxf(w - 20.0, 0.0), 1.2), Color(0, 0, 0, 0.28))
# ==================== 顶部信息带：电量 / 网络 ====================

func _refresh_device_status() -> void:
	if _device_status == null or not is_instance_valid(_device_status):
		return
	# 电池接口按引擎版本动态取（4.x 起 OS 上已没有 get_power_state；直接调用会解析失败）
	# 取不到就显示 -1（组件画成“--/PC”），不要假装 100% 误导玩家
	var pct: float = -1.0
	var charging := false
	var os: Object = Engine.get_singleton("OS")
	if os != null:
		if os.has_method("get_power_percent_left"):
			pct = float(os.call("get_power_percent_left"))
		if os.has_method("get_power_state"):
			var st := int(os.call("get_power_state"))
			charging = st == 3 or st == 4   # 3=CHARGING 4=CHARGED
	# Android：部分机型 OS 接口取不到电量时，退到 sysfs 直接读电池容量
	if pct < 0.0 and OS.get_name() == "Android":
		var cap := _read_sysfs_int("/sys/class/power_supply/battery/capacity")
		if cap >= 0:
			pct = float(cap)
		var sts := _read_sysfs_text("/sys/class/power_supply/battery/status")
		if sts.contains("Charg") or sts.contains("Full"):
			charging = true
	var mode := 0          # 0 本地 / 1 主机 / 2 客户端
	var ping_ms := -1.0
	if NetSession != null and NetSession.mode != NetSession.Mode.NONE:
		mode = 1 if NetSession.mode == NetSession.Mode.HOST else 2
		var mp = multiplayer.multiplayer_peer
		if mp is ENetMultiplayerPeer:
			var ids: Array = (mp as ENetMultiplayerPeer).get_peers()
			if mode == 2:
				ids = [1]
			var best := -1.0
			for pid in ids:
				var peer = (mp as ENetMultiplayerPeer).get_peer(int(pid))
				if peer != null and peer.has_method("get_statistic"):
					var rtt: float = float(peer.call("get_statistic", ENetPacketPeer.PEER_ROUND_TRIP_TIME))
					if rtt > 0.0 and (best < 0.0 or rtt < best):
						best = rtt
			ping_ms = best
	_device_status.call("set_data", pct, charging, mode, ping_ms)


func _read_sysfs_int(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var t := f.get_as_text().strip_edges()
	f.close()
	if t == "":
		return -1
	return int(t)


func _read_sysfs_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text().strip_edges()
	f.close()
	return t


class DeviceStatusArt extends Control:
	var batt_pct := -1.0
	var charging := false
	var net_mode := 0          # 0 本地 / 1 主机 / 2 客户端
	var ping_ms := -1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_data(pct: float, chg: bool, mode: int, ping: float) -> void:
		if absf(pct - batt_pct) < 0.5 and chg == charging and mode == net_mode and absf(ping - ping_ms) < 1.0:
			return
		batt_pct = pct
		charging = chg
		net_mode = mode
		ping_ms = ping
		queue_redraw()

	func _draw() -> void:
		var bright := Color(0.93, 0.97, 1.0, 0.94)
		var dim := Color(0.60, 0.67, 0.78, 0.92)
		# —— 电量：电池外框 + 电量填充 + 充电闪电 + 百分比 ——
		var bx := 0.0
		var by := 7.0
		var bw := 34.0
		var bh := 17.0
		var known: bool = batt_pct >= 0.0
		var pct: float = clampf(batt_pct, 0.0, 100.0) if known else 0.0
		var col := Color(0.55, 0.95, 0.62)
		if known:
			if pct <= 20.0:
				col = Color(1.0, 0.42, 0.38)
			elif pct <= 50.0:
				col = Color(1.0, 0.80, 0.36)
		if charging:
			col = Color(0.48, 0.87, 1.0)
		draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.22), false, 1.6)
		draw_rect(Rect2(bx + bw, by + bh * 0.32, 3.0, bh * 0.36), Color(1, 1, 1, 0.38))
		if known and pct > 0.5:
			draw_rect(Rect2(bx + 2.4, by + 2.4, maxf(1.0, (bw - 4.8) * pct / 100.0), bh - 4.8), col)
		if charging:
			var bolt := PackedVector2Array([
				Vector2(bx + bw * 0.56, by + 2.0), Vector2(bx + bw * 0.40, by + bh * 0.56),
				Vector2(bx + bw * 0.53, by + bh * 0.56), Vector2(bx + bw * 0.42, by + bh - 1.5),
				Vector2(bx + bw * 0.68, by + bh * 0.40), Vector2(bx + bw * 0.55, by + bh * 0.40),
				Vector2(bx + bw * 0.66, by + 2.0)])
			draw_colored_polygon(bolt, Color(0.04, 0.10, 0.16, 0.88))
		var btxt: String = ("%d%%" % int(round(pct))) if known else ("充电中" if charging else "--")
		UiKit.text(self, Vector2(bx + bw + 8.0, by + bh - 1.5), btxt, 17, bright if known else dim)

		# —— 分隔线 ——
		draw_line(Vector2(112.0, 4.0), Vector2(112.0, 30.0), Color(1, 1, 1, 0.14), 1.0)

		# —— 网络：四格信号 + 本地/联机/延迟 ——
		var nx := 124.0
		var net_col := dim
		var net_txt := "本地"
		var level := 0
		if net_mode > 0:
			net_txt = "联机"
			if ping_ms >= 0.0:
				level = 4 if ping_ms < 60.0 else (3 if ping_ms < 120.0 else (2 if ping_ms < 220.0 else 1))
				net_txt = "%dms" % int(round(ping_ms))
			else:
				level = 4
			if level >= 3:
				net_col = Color(0.55, 0.95, 0.62)
			elif level == 2:
				net_col = Color(1.0, 0.80, 0.36)
			else:
				net_col = Color(1.0, 0.42, 0.38)
		for i in range(4):
			var hh: float = 6.0 + 4.5 * float(i)
			var rx: float = nx + float(i) * 8.0
			var ry: float = 25.0 - hh
			draw_rect(Rect2(rx, ry, 5.5, hh), net_col if i < level else Color(1, 1, 1, 0.16))
		UiKit.text(self, Vector2(nx + 38.0, 24.0), net_txt, 17, bright if net_mode > 0 else dim)
