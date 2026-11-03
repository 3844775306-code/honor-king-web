class_name  BattleManager
extends Node3D
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const EndBannerScript = preload("res://scripts/ui/EndBanner.gd")
const PostMatchViewScript = preload("res://scripts/ui/PostMatchView.gd")
const PostMatchStageScript = preload("res://scripts/ui/PostMatchStage.gd")
const CrystalFinaleScript = preload("res://scripts/fx/CrystalFinale.gd")
const MatchResultScript = preload("res://scripts/core/MatchResult.gd")
const CloudSyncScript = preload("res://scripts/core/CloudSync.gd")
const AIDebugPanelScript = preload("res://scripts/ui/AIDebugPanel.gd")
const PauseOverlayScript = preload("res://scripts/ui/PauseOverlay.gd")
const HeroSkinTable = preload("res://scripts/core/HeroSkins.gd")
const AIDebugFormatScript = preload("res://scripts/debug/AIDebugFormat.gd")
const SelectArt = preload("res://scripts/ui/SelectArt.gd")
const VisionSpiritScript = preload("res://scripts/entities/VisionSpirit.gd")
var hero_selected: bool = false
# 开局运镜：由远及近拉到泉水，期间暂停整棵场景树并隐藏 HUD/小地图，结束后再开始计时与 AI
var intro_active: bool = false
var building_battle: bool = false   # 真实加载：加载界面显示期间同步搭建战场
var _intro_waiting: bool = false   # 加载界面仍覆盖、等待战场渲染就绪
var _intro_time: float = 0.0
var _intro_start: Vector3 = Vector3.ZERO
var _intro_end: Vector3 = Vector3.ZERO
const INTRO_DURATION: float = 2.8
# 固定俯角 -60° 的跟随机位：12/tan60°≈6.93，让镜头正对英雄脚下的地面点（英雄居中）
const CAMERA_FOLLOW_OFFSET := Vector3(0.0, 12.0, 6.93)
const HERO_BAR_CENTER_UP := 4.2   # 主英雄血条锚点：body_radius1.5*2+1.2；相机目标上移使血条位于屏幕正中
var selected_summoner: String = "flash"
var selected_skin_id: String = ""
var selected_hero_type: String = ""
var select_ui: CanvasLayer = null
# 英雄选择UI状态
var ROLE_COLORS = {
	"战士": Color(0.85, 0.3, 0.2),
	"法师": Color(0.3, 0.5, 1.0),
	"刺客": Color(0.6, 0.2, 0.9),
	"射手": Color(0.9, 0.55, 0.1),
	"辅助": Color(0.1, 0.8, 0.65),
}
var selected_hero_card: Panel = null
var selected_summ_card: Panel = null
var select_confirm_btn: Button = null
var select_summary_label: Label = null
var select_summ_detail: Label = null
# 召唤师技能描述
var SUMMONER_DESCRIPTIONS = {
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
# 视野之灵（己方边路二塔摧毁后生成）
var vision_spirits: Array = []
# 记录分路高地塔状态：{ team: { "farm": bool, "mid": bool, "clash": bool } }
var high_tower_destroyed = {
	Config.Team.PLAYER: { "farm": false, "mid": false, "clash": false },
	Config.Team.ENEMY: { "farm": false, "mid": false, "clash": false }
}
# 团队统计
var stats_timer: float = 0
var debug_refresh_timer: float = 0.0
var _ai_dbg: Control = null          # F3 AI 思考覆盖层
var _ai_dbg_t: float = 0.0
static var debug_kill_rewards: bool = true  # 调试：击杀奖励触发日志（排查单次死亡多次奖励，用BattleManager.debug_kill_rewards访问）
var team_player_gold: int = 0
var team_player_exp: int = 0
var team_player_kills: int = 0
var team_enemy_gold: int = 0
var team_enemy_exp: int = 0
var team_enemy_kills: int = 0
# 赛后统计
var _last_recorded_minute: int = 0
# 前4分钟 AI 评估快照（t=240s 打印/写 user://；供阶段化调参对比）
var _early_metrics_logged := false
var early_game_metrics: Dictionary = {}
var _last_turret_count_p := -1
var _last_turret_count_e := -1
var _last_dragon_alive := false
# 前4分钟 AI 无头基准：--ai-bench / --ai-bench-seed=N / --ai-bench-speed=N
var _ai_benchmark := false
var _ai_benchmark_seed := 1
var _ai_benchmark_speed := 1.0
var _ai_benchmark_keep := false
var _ai_test_match := false          # 主菜单测试模块：10 AI 随机阵容 + 4x + 赛后自动存档并回大厅
var _training_mode := false          # 主菜单训练营
var _record_replay := true           # 本局是否录像（测试/训练营由入口询问）
var _training_minions := false
var _training_jungle := false
var _training_minion_changed := false
var _training_hud: CanvasLayer = null
var _training_label: Label = null
var _training_minion_btn: Button = null
var _training_jungle_btn: Button = null
var _training_ai: Array = []
var _training_ai_count := 0
var _training_ai_level := 1
var _training_dummies: Array = []
var _training_dummy_armor := 500.0
var _training_dummy_label: RichTextLabel = null
var _training_def_btn: Button = null
var _training_ai_hero_name := ""
var _training_ai_hero_btn: Button = null
var _training_stats_t := 0.0
var _training_panel: PanelContainer = null
var _training_content: VBoxContainer = null
var _training_collapsed := false
var _training_stats_panel: PanelContainer = null
var _training_stats_content: VBoxContainer = null
var _training_stats_collapsed := false
var _training_invincible := false
var _training_no_cd := false
var _training_invincible_btn: Button = null
var _training_no_cd_btn: Button = null
var _training_skin_btn: Button = null
var _test_view_hero: Hero = null     # 测试观战主英雄（可切换）
var _test_prev_pos := Vector3.ZERO
var _test_layer: CanvasLayer = null
var _test_pause_btn: Button = null
var _test_speed_btn: Button = null
var _test_hero_btn: Button = null
var _test_name_lab: Label = null
var _test_paused := false
var _test_speed_idx := 4
const TEST_SPEEDS := [0.5, 1.0, 2.0, 3.0, 4.0]
var team_gold_diff_history: Array = [0]  # 每分钟蓝方减红方经济差
var player_base_health: int = 5000
var enemy_base_health: int = 5000
# 野怪出生延时：常规营地30秒首刷、空间之灵60秒首刷（墙在开局即登记）
const JUNGLE_FIRST_SPAWN := 30.0
const SPATIAL_FIRST_SPAWN := 60.0
var jungle_monsters :Array = []
var jungle_camp_positions :Array = []
var _bush_positions: Array = []
# 延时物化的野怪组：{type, config, center, count, at}，game_time>=at 时物化
var _pending_jungle_spawns: Array = []
# 分帧生成队列：一波兵/一组野怪不在同一帧创建（避免单帧 100~2500ms 卡顿）
var _minion_spawn_queue: Array = []
var _jungle_group_queue: Array = []
# 核心实体
var hero: Hero
var enemy_hero: Hero
var _pfx_hp: float = -1.0   # PostFX 受击红晕：上一帧本地英雄血量（-1=未初始化）
var turrets: Array = []
var minions: Array = []
var game_time: float = 0.0
# 全场MVP：每30秒重算一次；mvp_hero 指向当前评分最高的英雄（可能为 null）
var mvp_hero: Hero = null
var _mvp_interval: int = 0   # 已结算到的 game_time/30 档位（0档=开局0~30s不结算）
# —— 野区保护几何：PLAYER 水晶 (-53,53)、ENEMY 水晶 (53,-53)，半区分界 x=z ——
const JG_PLAYER_CRYSTAL := Vector3(-53.0, 0, 53.0)
const JG_ENEMY_CRYSTAL := Vector3(53.0, 0, -53.0)
const JG_RIVER_BAND := 14.142136  # 河道沿 x=z 对角线、垂直全宽20 => |x-z| <= 10*sqrt(2)

# 前4分钟野区保护判定：pos 距敌方水晶比距己方水晶更近（=进入敌方半区），且不在河道带内
static func in_enemy_jungle_zone(pos: Vector3, team: int) -> bool:
	var own := JG_PLAYER_CRYSTAL if team == Config.Team.PLAYER else JG_ENEMY_CRYSTAL
	var enemy := JG_ENEMY_CRYSTAL if team == Config.Team.PLAYER else JG_PLAYER_CRYSTAL
	if pos.distance_squared_to(enemy) >= pos.distance_squared_to(own):
		return false
	return absf(pos.x - pos.z) > JG_RIVER_BAND

# —— 越塔保护（伤害与 buff 图标共用判定）——
# 身处敌方存活防御塔射程内的英雄 = “越塔中”
func hero_under_enemy_tower(hero) -> bool:
	for t in get_tree().get_nodes_in_group("turrets"):
		if t is Turret and t.team != hero.team and t.health > 0:
			if t.global_position.distance_to(hero.global_position) <= t.attack_range * 0.01:
				return true
	return false

# 越塔减伤系数：前4分钟-25% → 4-10分钟-10% → 10分钟后-5%
func tower_dive_factor() -> float:
	if game_time < 240.0:
		return 0.75
	if game_time < 600.0:
		return 0.9
	return 0.95

# 集中式团队分推协调
var team_tactics: TeamTactics = null
var team_tactics_timer: float = 0.0
# 系统

var ui: UI_Manager
var minimap: Minimap
var cam
var first_person_view: bool = false   # 第一人称视角开关（Tab切换）
var first_blood_occurred: bool = false
# 兵线
var minion_spawn_timer: float = 0.0
var minimap_dragging: bool = false
var minimap_drag_pos: Vector3 = Vector3.ZERO
var minimap_jump_requested: bool = false
# —— 右半屏拖拽相机：按住右半屏拖动看视野，松手平滑回正（手势由 TouchController 提供）——
var cam_pan_offset: Vector3 = Vector3.ZERO
var cam_yaw: float = 0.0   # 玩家在红方时镜头绕Y轴转180°，使红方出生与蓝方手感一致
var cam_pan_prev_valid: bool = false
var cam_pan_prev_screen: Vector2 = Vector2.ZERO
# 桌面中键自由镜头：拖动平移，松手保持，Y 回正；_cam_touch_decay 仅手机端松手回正用
var _cam_mid_drag: bool = false
var _cam_touch_decay: bool = false
var _cam_snap: bool = false
# 阵亡观战：玩家阵亡后可点击存活队友头像，镜头切到该队友；复活自动收回
var spectate_hero: Hero = null
# P0 镜头反馈（本地表现层，不参与联机判定）
var _shake_amp: float = 0.0
var _shake_dur: float = 0.0
var _shake_t: float = 0.0
var _cam_base_fov: float = -1.0
var _hitstop_until_msec: int = 0
const SPELL_FX = preload("res://scripts/core/SpellFxTable.gd")
var teleport_lines: Array = []
var recall_lines: Dictionary = {}
func add_teleport_line(hero: Hero, target: Vector3):
	# 清除该英雄已有的旧连线
	for i in range(teleport_lines.size() - 1, -1, -1):
		if teleport_lines[i]["hero"] == hero:
			teleport_lines.remove_at(i)
	teleport_lines.append({"hero": hero, "from": hero.global_position, "to": target})

func remove_teleport_line(hero: Hero, target: Vector3):
	for i in range(teleport_lines.size() - 1, -1, -1):
		if teleport_lines[i]["hero"] == hero and teleport_lines[i]["to"].distance_to(target) < 1.0:
			teleport_lines.remove_at(i)
			break

func request_teleport(hero: Hero, target: Node3D) -> void:
	# 只能传送到友方防御塔或小兵
	if not is_instance_valid(hero) or hero.is_teleporting:
		return
	if target is Turret and target.team == hero.team:
		hero.start_teleport(target.global_position)
	elif target is Minion and target.team == hero.team:
		# 选中的小兵作为传送锚点：引导期间站定、停手、免伤
		hero.start_teleport(target.global_position, target as Minion)

func add_recall_line(hero: Hero, spring: Vector3):
	recall_lines[hero] = {"hero_pos": hero.global_position, "spring_pos": spring}

func remove_recall_line(hero: Hero):
	recall_lines.erase(hero)
func _ready():
	# 录像回放用：只构建与对局完全一致的地形视觉（不跑任何对局逻辑）
	if has_meta("map_only"):
		# 录像回放用：与对局完全一致的地图（含野区弧形墙/龙坑墙）。
		# 野怪只登记营地位置、不物化（game_time 恒 0），回放里的野怪由录像数据驱动。
		MapVisuals.setup_environment(self)
		_create_map()
		_create_jungle()
		_generate_jungle_arc_walls()
		return
	add_to_group("battle_manager")
	# --damage-audit：单机/训练营统一开启伤害审计日志
	GameEntity.damage_audit_enabled = "--damage-audit" in OS.get_cmdline_user_args()
	if GameEntity.damage_audit_enabled:
		var _stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_").replace(" ", "_")
		var _mode := "training" if "--training-camp" in OS.get_cmdline_user_args() else "battle"
		GameEntity.damage_audit_path = "user://damage_audit_%s_%s.log" % [_mode, _stamp]
		print("[DMG_AUDIT] 本局日志: ", ProjectSettings.globalize_path(GameEntity.damage_audit_path))
	# AI 思考过程覆盖层（F3 开关；懒创建面板）
	var _dbg_cl := CanvasLayer.new()
	_dbg_cl.name = "AIDebugLayer"
	_dbg_cl.layer = 280
	add_child(_dbg_cl)
	_ai_dbg = AIDebugPanelScript.new()
	_ai_dbg.visible = false
	_dbg_cl.add_child(_ai_dbg)
	# 单机 P 暂停覆盖层（联机不暂停，避免不同步）
	if NetSession.mode == NetSession.Mode.NONE:
		var _pause_cl := CanvasLayer.new()
		_pause_cl.name = "PauseLayer"
		_pause_cl.layer = 290
		add_child(_pause_cl)
		var _po = PauseOverlayScript.new()
		_pause_cl.add_child(_po)
	Config.reset_player_team()
	# 选人/加载阶段沿用大厅氛围音乐（真正开局 _start_game_body 会淡出；直接从本场景启动也有音乐）
	SfxManager.start_menu_music()

	# 环境 + 灯光（地图视觉层：天空盒 / 天空环境光 / ACES / 深度雾 / 软阴影）
	MapVisuals.setup_environment(self)

	# 摄像机（俯角比原 -70° 更平缓，能看见远景与雾）
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 70.0
	cam.size = 30
	cam.position = Vector3(0, 20, 10)
	cam.rotation_degrees = Vector3(-60, 0, 0)
	add_child(cam)

	# 地图
	_create_map()
	team_tactics = TeamTactics.new(self)
	# AI 难度：应用本机偏好（联机只有 host 跑 AI，天然主机权威）
	AiConfig.difficulty = PlayerPrefs.get_ai_difficulty()

	# 视野管理器

	# 大厅选人开局（host 带全员锁定阵容进入）：跳过选人 UI，见 _ready 末尾的 _start_net_lineup
	var _auto_boot := PlayerPrefs.opt_bool("ai_test_match", false) \
		or PlayerPrefs.opt_bool("training_mode", false) \
		or "--ai-test" in OS.get_cmdline_user_args() \
		or "--training-camp" in OS.get_cmdline_user_args() \
		or "--net-test" in OS.get_cmdline_user_args() \
		or "--ai-bench" in OS.get_cmdline_user_args()
	if NetSession.mode == NetSession.Mode.HOST and NetSession.has_picks():
		pass
	elif _auto_boot:
		pass   # 测试/训练/无头模式直接进入加载，不显示选人界面
	else:
		_show_hero_select_ui()

	# UI 层：复用自加载单例 UiManager（不再新建第二套 HUD，避免重复绘制与大厅鬼影）
	ui = UiManager as UI_Manager
	if ui != null:
		ui.enter_battle()
	else:
		ui = UI_Manager.new()
		add_child(ui)

	# 小地图 (添加到 UI 层，但这里简单直接加在主树)
	minimap = Minimap.new()
	# 两端统一：再放大 1.5 倍（200 → 300 → 450），手机端看得更清
	var mm_size := 450
	minimap.MINIMAP_SIZE = mm_size
	# 左上角锚定（稍向中心收，避免贴死角落）
	var mm_inset := 40
	minimap.anchor_left = 0.0
	minimap.anchor_top = 0.0
	minimap.anchor_right = 0.0
	minimap.anchor_bottom = 0.0
	# 刘海/挖孔避让：小地图整体内收 safe_top/safe_left（桌面端为 0，无影响）
	var mm_safe_top := UiKit.safe_top()
	var mm_safe_left := UiKit.safe_left()
	minimap.offset_left = mm_inset + mm_safe_left
	minimap.offset_top = mm_inset + mm_safe_top
	minimap.offset_right = mm_inset + mm_safe_left + mm_size
	minimap.offset_bottom = mm_inset + mm_safe_top + mm_size
	minimap.size = Vector2(mm_size, mm_size)

	minimap.heroes = [hero, enemy_hero]
	minimap.turrets = turrets
	minimap.player_team = Config.player_team
	add_child(minimap)
	minimap.set_battle(self)
	set_process(true)
	# 选人/BP 期间预热小兵模型模板并各渲染一帧（被选人界面遮挡），
	# 避免首波兵线在真实渲染下每只 100~230ms 的模型构建 + 首次绘制卡顿
	_prewarm_battle_assets()
	# 大厅选人开局（host 已在 NetLobby 里 begin_pick→全员锁齐→start_match）：
	# 带全员锁定阵容直接开战局，guest 英雄由 NetSession.assign_lineup 逐一分发接管。
	if NetSession.mode == NetSession.Mode.HOST and NetSession.has_picks():
		call_deferred("_start_net_lineup", NetSession.get_picks())
	# 联机 CI：--net-test（放在 `--` 之后）时跳过选人 UI 直接自动开局，
	# 让无头主机能跑一局完整 AI 对局供快照广播。有画面时同样生效，便于本地双开调试。
	elif "--net-test" in OS.get_cmdline_user_args() or "--ai-bench" in OS.get_cmdline_user_args():
		call_deferred("_start_game", "亚瑟")
	elif PlayerPrefs.opt_bool("ai_test_match", false):
		_ai_test_match = true
		_record_replay = PlayerPrefs.opt_bool("ai_test_record", false)
		PlayerPrefs.set_opt("ai_test_match", false)
		PlayerPrefs.set_opt("ai_test_record", false)
		call_deferred("_start_ai_test_match")
	elif "--ai-test" in OS.get_cmdline_user_args():
		# CLI/无头测试入口：与主菜单测试模块同一流程（CLI 默认不录像）
		_ai_test_match = true
		_record_replay = false
		call_deferred("_start_ai_test_match")
	elif PlayerPrefs.opt_bool("training_mode", false) or "--training-camp" in OS.get_cmdline_user_args():
		_training_mode = true
		_record_replay = PlayerPrefs.opt_bool("training_record", false) and "--training-camp" not in OS.get_cmdline_user_args()
		PlayerPrefs.set_opt("training_mode", false)
		PlayerPrefs.set_opt("training_record", false)
		call_deferred("_start_training_camp")

## 主菜单测试模块：随机英雄开局，双方 10 个 AI，4 倍速；对局结束自动保存录像并回大厅
func _start_ai_test_match() -> void:
	# 按职责各选1人，保证每队5条分路不重复；双方共10名不重复英雄
	var role_order := ["战士", "法师", "刺客", "射手", "辅助"]
	var by_role := {}
	for nm in hero_configs.keys():
		if str(nm) == "元流之子":   # 避免测试局弹万物为流选择面板
			continue
		var r := str(hero_configs[nm].get("role", "战士"))
		if not by_role.has(r):
			by_role[r] = []
		by_role[r].append(str(nm))
	var used := {}
	var picks: Array = []
	for r in role_order:
		var pool: Array = by_role.get(r, []).duplicate()
		pool.shuffle()
		var chosen := ""
		for nm in pool:
			if not used.has(nm):
				chosen = str(nm)
				break
		if chosen == "":
			# 极端兜底：从全部未使用英雄补位
			var rest: Array = []
			for nm in hero_configs.keys():
				if str(nm) != "元流之子" and not used.has(nm):
					rest.append(str(nm))
			rest.shuffle()
			chosen = str(rest[0]) if not rest.is_empty() else "亚瑟"
		picks.append(chosen)
		used[chosen] = true
	# 第二队再按职责各选1人，且避开第一队
	for r in role_order:
		var pool: Array = by_role.get(r, []).duplicate()
		pool.shuffle()
		var chosen := ""
		for nm in pool:
			if not used.has(nm):
				chosen = str(nm)
				break
		if chosen == "":
			var rest: Array = []
			for nm in hero_configs.keys():
				if str(nm) != "元流之子" and not used.has(nm):
					rest.append(str(nm))
			rest.shuffle()
			chosen = str(rest[0]) if not rest.is_empty() else "亚瑟"
		picks.append(chosen)
		used[chosen] = true
	sel_player_seat = 0
	sel_ally_picks = picks.slice(0, 5)
	sel_enemy_picks = picks.slice(5, 10)
	print("[AI-TEST] start random 10 AI at 4x (roles: %s)" % str(role_order))
	_start_game(str(picks[0]))


## 测试观战 HUD：倍速/暂停/切换主视角/结束，模仿回放控制条
func _setup_test_hud() -> void:
	if _test_layer != null and is_instance_valid(_test_layer):
		return
	_test_view_hero = hero
	_test_prev_pos = hero.global_position if is_instance_valid(hero) else Vector3.ZERO
	_test_layer = CanvasLayer.new()
	_test_layer.layer = 125
	_test_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_test_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_test_layer.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 18
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	center.add_child(bar)
	_test_pause_btn = _test_mk_btn("⏸ 暂停")
	_test_pause_btn.pressed.connect(_test_toggle_pause)
	bar.add_child(_test_pause_btn)
	_test_speed_btn = _test_mk_btn("4.0×")
	_test_speed_btn.pressed.connect(_test_cycle_speed)
	bar.add_child(_test_speed_btn)
	_test_hero_btn = _test_mk_btn("切换视角")
	_test_hero_btn.pressed.connect(_test_cycle_hero)
	bar.add_child(_test_hero_btn)
	_test_name_lab = Label.new()
	_test_name_lab.add_theme_font_size_override("font_size", int(round(UiKit.FS_MD * UiKit.scale())))
	_test_name_lab.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	bar.add_child(_test_name_lab)
	var exit_btn := _test_mk_btn("✕ 结束测试")
	exit_btn.pressed.connect(_exit_ai_test)
	bar.add_child(exit_btn)
	if is_instance_valid(TouchController):
		TouchController.set_hero(hero)
	_test_refresh_label()


func _test_mk_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(120, 44)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	b.add_theme_font_size_override("font_size", int(round(UiKit.FS_MD * UiKit.scale())))
	return b


func _test_refresh_label() -> void:
	if _test_name_lab == null or not is_instance_valid(hero):
		return
	_test_name_lab.text = "主视角：%s" % str(hero.display_name)


func _test_toggle_pause() -> void:
	_test_paused = not _test_paused
	get_tree().paused = _test_paused
	if _test_pause_btn != null:
		_test_pause_btn.text = "▶ 继续" if _test_paused else "⏸ 暂停"
	if not _test_paused:
		Engine.time_scale = float(TEST_SPEEDS[_test_speed_idx])


func _test_cycle_speed() -> void:
	_test_speed_idx = (_test_speed_idx + 1) % TEST_SPEEDS.size()
	var sp: float = float(TEST_SPEEDS[_test_speed_idx])
	if not _test_paused:
		Engine.time_scale = sp
	if _test_speed_btn != null:
		_test_speed_btn.text = "%.1f×" % sp


## 测试观战：点英雄头像直接切主视角（供 UI 头像点击调用）
func set_test_view_hero(h: Hero) -> void:
	if not _ai_test_match or h == null or not is_instance_valid(h) or h.is_dead:
		return
	hero = h
	_test_view_hero = h
	_test_prev_pos = h.global_position
	spectate_hero = null
	_cam_snap = true
	if is_instance_valid(TouchController):
		TouchController.set_hero(h)
	if minimap != null:
		minimap.heroes = [h, enemy_hero]
	_test_refresh_label()

func _test_cycle_hero() -> void:
	var hs: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero and e.health > 0.0:
			hs.append(e)
	if hs.is_empty():
		return
	var cur: int = hs.find(hero)
	var nx: int = (cur + 1) % hs.size() if cur >= 0 else 0
	hero = hs[nx]
	_test_view_hero = hero
	spectate_hero = null
	_cam_snap = true
	if is_instance_valid(TouchController):
		TouchController.set_hero(hero)
	if minimap != null:
		minimap.heroes = [hero, enemy_hero]
	_test_refresh_label()


func _exit_ai_test() -> void:
	_ai_test_match = false
	_test_paused = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


## 测试观战每帧：主视角回正/死亡自动切换、摇杆跟随 AI 移动方向
func _test_tick(delta: float) -> void:
	if hero == null or not is_instance_valid(hero) or hero.health <= 0.0:
		_test_cycle_hero()
		return
	var p: Vector3 = hero.global_position
	var d: Vector3 = p - _test_prev_pos
	_test_prev_pos = p
	if is_instance_valid(TouchController):
		if d.length() > 0.01:
			TouchController.set_test_move(Vector2(d.x, -d.z).normalized())
		else:
			TouchController.set_test_move(Vector2.ZERO)
	_test_refresh_label()


## Hero 侧回调：仅测试局且为当前主视角英雄时闪对应按钮
func test_hero_action(h: Hero, kind: String, slot: int = 0) -> void:
	if not _ai_test_match or h != hero or not is_instance_valid(TouchController):
		return
	if kind == "attack":
		TouchController.flash_attack()
	else:
		TouchController.flash_skill(slot)


## 训练营：开局提示 + 控制面板
func _start_training_camp() -> void:
	_training_mode = true
	_training_minions = false
	_training_jungle = false
	_training_ai_count = 0
	_training_ai_level = 1
	_training_ai.clear()
	_training_dummies.clear()
	_start_game("亚瑟")


func _training_mk_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(158, 42)
	b.add_theme_font_size_override("font_size", int(round(UiKit.FS_SM * UiKit.scale())))
	b.add_theme_color_override("font_color", Color(0.93, 0.96, 1.0))
	b.add_theme_color_override("font_hover_color", UiKit.C_GOLD)
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", Color(0.45, 0.62, 0.9), false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _setup_training_hud() -> void:
	if _training_hud != null and is_instance_valid(_training_hud):
		return
	_training_hud = CanvasLayer.new()
	_training_hud.layer = 120
	add_child(_training_hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_training_hud.add_child(root)

	# 小地图上方：训练操作（直接覆盖小地图）
	_training_panel = PanelContainer.new()
	_training_panel.position = Vector2(40 + UiKit.safe_left(), 40 + UiKit.safe_top())
	_training_panel.custom_minimum_size = Vector2(400, 0)
	_training_panel.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD, false, 0.96))
	root.add_child(_training_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_training_panel.add_child(outer)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)
	var title := Label.new()
	title.text = "训 练 营"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", int(round(UiKit.FS_LG * UiKit.scale())))
	title.add_theme_color_override("font_color", UiKit.C_GOLD)
	header.add_child(title)
	var collapse_btn := _training_mk_btn("▾")
	collapse_btn.custom_minimum_size = Vector2(44, 36)
	collapse_btn.pressed.connect(_training_toggle_collapse)
	header.add_child(collapse_btn)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	outer.add_child(vb)
	_training_content = vb
	_training_label = Label.new()
	_training_label.add_theme_font_size_override("font_size", int(round(UiKit.FS_SM * UiKit.scale())))
	_training_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0))
	vb.add_child(_training_label)
	var hk := Label.new()
	hk.text = "快捷键 F6兵线 F7野怪 F8升级 F9满级 F10金币\nCtrl+F6木偶 Ctrl+F7清木偶 · Alt+1无敌 Alt+2无CD · Alt+H切英雄 Alt+J切AI Alt+K/L AI数量"
	hk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hk.add_theme_font_size_override("font_size", int(round(UiKit.FS_XS * UiKit.scale())))
	hk.add_theme_color_override("font_color", Color(0.62, 0.72, 0.86))
	vb.add_child(hk)
	var sep := HSeparator.new()
	vb.add_child(sep)
	_training_minion_btn = _training_mk_btn("兵线：关")
	_training_minion_btn.pressed.connect(_training_toggle_minions)
	vb.add_child(_training_minion_btn)
	_training_jungle_btn = _training_mk_btn("野怪：关")
	_training_jungle_btn.pressed.connect(_training_toggle_jungle)
	vb.add_child(_training_jungle_btn)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vb.add_child(row1)
	var b_lv := _training_mk_btn("等级 +1")
	b_lv.pressed.connect(_training_level_up)
	row1.add_child(b_lv)
	var b_max := _training_mk_btn("满级")
	b_max.pressed.connect(_training_max_level)
	row1.add_child(b_max)
	var b_gold := _training_mk_btn("+1000 金币")
	b_gold.pressed.connect(_training_add_gold)
	vb.add_child(b_gold)
	var b_dummy := _training_mk_btn("放置木偶（原地）")
	b_dummy.pressed.connect(_training_place_dummy)
	vb.add_child(b_dummy)
	var b_clear := _training_mk_btn("清除木偶")
	b_clear.pressed.connect(_training_clear_dummies)
	vb.add_child(b_clear)
	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 6)
	vb.add_child(ai_row)
	var b_ai_add := _training_mk_btn("AI +1")
	b_ai_add.pressed.connect(func(): _training_set_ai_count(_training_ai_count + 1))
	ai_row.add_child(b_ai_add)
	var b_ai_sub := _training_mk_btn("AI -1")
	b_ai_sub.pressed.connect(func(): _training_set_ai_count(_training_ai_count - 1))
	ai_row.add_child(b_ai_sub)
	var ai_row2 := HBoxContainer.new()
	ai_row2.add_theme_constant_override("separation", 6)
	vb.add_child(ai_row2)
	var b_ai_lv := _training_mk_btn("AI 等级 +1")
	b_ai_lv.pressed.connect(_training_ai_level_up)
	ai_row2.add_child(b_ai_lv)
	var b_ai_gold := _training_mk_btn("AI +1000")
	b_ai_gold.pressed.connect(_training_ai_gold)
	ai_row2.add_child(b_ai_gold)
	var hero_btn := _training_mk_btn("切换我的英雄")
	hero_btn.pressed.connect(_training_cycle_player_hero)
	vb.add_child(hero_btn)
	_training_skin_btn = _training_mk_btn("我的皮肤：经典")
	_training_skin_btn.pressed.connect(_training_cycle_player_skin)
	vb.add_child(_training_skin_btn)
	_training_ai_hero_btn = _training_mk_btn("AI 英雄：随机")
	_training_ai_hero_btn.pressed.connect(_training_cycle_ai_hero)
	vb.add_child(_training_ai_hero_btn)
	var def_row := HBoxContainer.new()
	def_row.add_theme_constant_override("separation", 6)
	vb.add_child(def_row)
	_training_def_btn = _training_mk_btn("防御：500")
	_training_def_btn.pressed.connect(_training_cycle_defense)
	def_row.add_child(_training_def_btn)
	var b_def_lo := _training_mk_btn("防 -50")
	b_def_lo.pressed.connect(func(): _training_set_dummy_resist(_training_dummy_armor - 50.0))
	def_row.add_child(b_def_lo)
	var b_def_hi := _training_mk_btn("防 +50")
	b_def_hi.pressed.connect(func(): _training_set_dummy_resist(_training_dummy_armor + 50.0))
	def_row.add_child(b_def_hi)
	var buff_row := HBoxContainer.new()
	buff_row.add_theme_constant_override("separation", 6)
	vb.add_child(buff_row)
	_training_invincible_btn = _training_mk_btn("无敌：关")
	_training_invincible_btn.pressed.connect(_training_toggle_invincible)
	buff_row.add_child(_training_invincible_btn)
	_training_no_cd_btn = _training_mk_btn("无冷却：关")
	_training_no_cd_btn.pressed.connect(_training_toggle_no_cd)
	buff_row.add_child(_training_no_cd_btn)
	var b_back := _training_mk_btn("返回大厅")
	b_back.pressed.connect(_training_exit)
	vb.add_child(b_back)

	# 原英雄头像位置：木偶详细统计（直接覆盖头像区）
	_training_stats_panel = PanelContainer.new()
	# 贴右上角布局：不再用固定 x=500 与左侧训练面板重叠（高缩放下训练面板会更宽）
	_training_stats_panel.anchor_left = 1.0
	_training_stats_panel.anchor_right = 1.0
	_training_stats_panel.offset_left = -540.0 - UiKit.safe_right()
	_training_stats_panel.offset_right = -40.0 - UiKit.safe_right()
	_training_stats_panel.offset_top = 28.0 + UiKit.safe_top()
	_training_stats_panel.custom_minimum_size = Vector2(500, 0)
	_training_stats_panel.add_theme_stylebox_override("panel", UiKit.skin_card(Color(0.55, 0.78, 1.0), false, 0.96))
	root.add_child(_training_stats_panel)
	var s_outer := VBoxContainer.new()
	s_outer.add_theme_constant_override("separation", 6)
	_training_stats_panel.add_child(s_outer)
	var s_header := HBoxContainer.new()
	s_header.add_theme_constant_override("separation", 8)
	s_outer.add_child(s_header)
	var stitle := Label.new()
	stitle.text = "木偶伤害统计"
	stitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stitle.add_theme_font_size_override("font_size", int(round(UiKit.FS_LG * UiKit.scale())))
	stitle.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	s_header.add_child(stitle)
	var s_collapse := _training_mk_btn("▾")
	s_collapse.custom_minimum_size = Vector2(44, 36)
	s_collapse.pressed.connect(_training_toggle_stats_collapse)
	s_header.add_child(s_collapse)
	var svb := VBoxContainer.new()
	svb.add_theme_constant_override("separation", 8)
	s_outer.add_child(svb)
	_training_stats_content = svb
	_training_dummy_label = RichTextLabel.new()
	_training_dummy_label.bbcode_enabled = true
	_training_dummy_label.fit_content = false
	_training_dummy_label.scroll_active = false
	_training_dummy_label.custom_minimum_size = Vector2(0, 230)
	_training_dummy_label.add_theme_font_size_override("normal_font_size", int(round(UiKit.FS_XS * UiKit.scale())))
	svb.add_child(_training_dummy_label)
	var reset_btn := _training_mk_btn("重置木偶统计")
	reset_btn.pressed.connect(_training_reset_dummy_stats)
	svb.add_child(reset_btn)
	_training_refresh_label()
	_training_refresh_dummy_stats()
	_training_refresh_skin_btn()


func _training_handle_hotkey(event: InputEventKey) -> bool:
	if event.alt_pressed:
		match event.keycode:
			KEY_1: _training_toggle_invincible(); return true
			KEY_2: _training_toggle_no_cd(); return true
			KEY_H: _training_cycle_player_hero(); return true
			KEY_J: _training_cycle_ai_hero(); return true
			KEY_K: _training_set_ai_count(_training_ai_count + 1); return true
			KEY_L: _training_set_ai_count(_training_ai_count - 1); return true
			KEY_R: _training_reset_dummy_stats(); return true
		return false
	match event.keycode:
		KEY_F6:
			if event.ctrl_pressed: _training_place_dummy()
			else: _training_toggle_minions()
			return true
		KEY_F7:
			if event.ctrl_pressed: _training_clear_dummies()
			else: _training_toggle_jungle()
			return true
		KEY_F8: _training_level_up(); return true
		KEY_F9: _training_max_level(); return true
		KEY_F10: _training_add_gold(); return true
	return false


func _training_toggle_invincible() -> void:
	_training_invincible = not _training_invincible
	if hero != null and is_instance_valid(hero):
		hero.training_invincible = _training_invincible
	if _training_invincible_btn != null:
		_training_invincible_btn.text = "无敌：%s" % ("开" if _training_invincible else "关")


func _training_toggle_no_cd() -> void:
	_training_no_cd = not _training_no_cd
	if hero != null and is_instance_valid(hero):
		hero.training_no_cooldown = _training_no_cd
	if _training_no_cd_btn != null:
		_training_no_cd_btn.text = "无冷却：%s" % ("开" if _training_no_cd else "关")


func _training_toggle_collapse() -> void:
	_training_collapsed = not _training_collapsed
	if _training_content != null:
		_training_content.visible = not _training_collapsed
	_training_panel.custom_minimum_size = Vector2(400, 0)


func _training_toggle_stats_collapse() -> void:
	_training_stats_collapsed = not _training_stats_collapsed
	if _training_stats_content != null:
		_training_stats_content.visible = not _training_stats_collapsed


func _training_refresh_label() -> void:
	if _training_label == null:
		return
	var lv := 1
	var gold := 0
	if hero != null and is_instance_valid(hero):
		lv = int(hero.level)
		gold = int(hero.gold)
	_training_label.text = "训练营 · Lv.%d · 金币 %d · AI %d(等级%d)" % [lv, gold, _training_ai_count, _training_ai_level]
	if _training_minion_btn != null:
		_training_minion_btn.text = "兵线：%s" % ("开" if _training_minions else "关")
	if _training_jungle_btn != null:
		_training_jungle_btn.text = "野怪：%s" % ("开" if _training_jungle else "关")


func _training_toggle_minions() -> void:
	_training_minions = not _training_minions
	if not _training_minions:
		for m in get_tree().get_nodes_in_group("minions"):
			if is_instance_valid(m):
				m.queue_free()
		_minion_spawn_queue.clear()
	else:
		minion_spawn_timer = 0.0
		_spawn_minion_wave()
	_training_refresh_label()


func _training_toggle_jungle() -> void:
	_training_jungle = not _training_jungle
	if not _training_jungle:
		_pending_jungle_spawns.clear()
		_jungle_group_queue.clear()
		for j in get_tree().get_nodes_in_group("jungle_monsters"):
			if is_instance_valid(j):
				j.queue_free()
		jungle_monsters.clear()
	else:
		_create_jungle()
		_update_pending_jungle_spawns()
	_training_refresh_label()


func _training_level_up() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if hero.level < 15:
		hero.level_up()
	_training_refresh_label()


func _training_max_level() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	hero.level = 15
	hero.skill_points = 15
	hero._check_fourth_skill_unlock()
	hero._recalculate_attributes()
	_training_refresh_label()


func _training_add_gold() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	hero.gold += 1000
	_training_refresh_label()


func _training_place_dummy() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var d := TrainingDummyScript.new()
	var cfg := {
		"name": "训练木偶", "team": Config.foe_team(),
		"max_health": 10000.0, "attack": 0.0, "armor": _training_dummy_armor,
		"magic_resist": _training_dummy_armor, "attack_range": 0.0, "attack_speed": 1.0,
		"move_speed": 0.0, "body_radius": 1.0,
	}
	d.setup(cfg)
	d.actual_max_health = 10000.0
	d.health = 10000.0
	d.set_resist(_training_dummy_armor)
	d.position = hero.global_position   # 原地放置
	add_child(d)
	_training_dummies.append(d)
	_training_refresh_label()


func _training_clear_dummies() -> void:
	for d in _training_dummies:
		if is_instance_valid(d):
			d.queue_free()
	_training_dummies.clear()
	_training_refresh_dummy_stats()


func _training_set_ai_count(n: int) -> void:
	n = clampi(n, 0, 5)
	for h in _training_ai:
		if is_instance_valid(h):
			h.queue_free()
	_training_ai.clear()
	_training_ai_count = n
	enemy_hero = null
	if n > 0:
		var before := {}
		for e in get_tree().get_nodes_in_group("heroes"):
			before[e.get_instance_id()] = true
		var forced: Array = []
		if _training_ai_hero_name != "":
			forced = [_training_ai_hero_name]
		_create_team_ai(Config.foe_team(), n, [], forced)
		for e in get_tree().get_nodes_in_group("heroes"):
			if e is Hero and e.team == Config.foe_team() and not before.has(e.get_instance_id()):
				while e.level < _training_ai_level:
					e.level_up()
				_training_ai.append(e)
		if not _training_ai.is_empty():
			enemy_hero = _training_ai[0]
	_training_refresh_label()


func _training_ai_level_up() -> void:
	_training_ai_level = mini(15, _training_ai_level + 1)
	for h in _training_ai:
		if is_instance_valid(h):
			while h.level < _training_ai_level:
				h.level_up()
	_training_refresh_label()


func _training_ai_gold() -> void:
	for h in _training_ai:
		if is_instance_valid(h):
			h.gold += 1000
	_training_refresh_label()


func _training_tick(delta: float) -> void:
	_training_stats_t += delta
	if _training_stats_t >= 0.1:
		_training_stats_t = 0.0
		_training_refresh_dummy_stats()
	_training_refresh_label()


func _training_refresh_dummy_stats() -> void:
	if _training_dummy_label == null:
		return
	var d = null
	for i in range(_training_dummies.size() - 1, -1, -1):
		if is_instance_valid(_training_dummies[i]):
			d = _training_dummies[i]
			break
	if d == null:
		_training_dummy_label.text = "[color=#9fb3cc]尚未放置训练木偶[/color]\n[color=#6f829a]HP 10000 · 防御 %.0f[/color]" % _training_dummy_armor
		return
	var st: Dictionary = d.stats
	var groups: Dictionary = st.get("groups", {})
	var keys: Array = groups.keys()
	keys.sort_custom(func(a, b): return float(groups[a]) > float(groups[b]))
	var lines: Array = []
	var dummy_max: float = maxf(d.actual_max_health, 1.0)
	lines.append("[color=#ffd966][b]HP[/b]  [color=#e8f2ff]%d / %d[/color]    [color=#ffd966][b]防御[/b]  [color=#e8f2ff]%.0f[/color]" % [int(d.health), int(dummy_max), d.armor])
	lines.append("[color=#9fd7ff]攻击时长[/color] [color=#ffffff][b]%.2fs[/b][/color]    [color=#9fd7ff]命中[/color] [color=#ffffff][b]%d[/b][/color]    [color=#9fd7ff]总伤害[/color] [color=#ffffff][b]%d[/b][/color]    [color=#9fd7ff]DPS[/color] [color=#ffd966][b]%.0f[/b][/color]" % [
		d.active_time(), int(st.get("hits", 0)), int(st.get("total", 0.0)), d.dps()])
	lines.append("[color=#7fe3a0]物理 %d[/color]    [color=#c9a7ff]法术 %d[/color]    [color=#ff9b7a]真伤 %d[/color]" % [
		int(st.get("phys", 0.0)), int(st.get("magic", 0.0)), int(st.get("true", 0.0))])
	lines.append("[color=#5e7698]──────── 伤害来源 ────────[/color]")
	for k in keys:
		if keys.find(k) >= 10:
			break
		lines.append("[color=#c7d7ec]%s[/color]    [color=#ffffff][b]%d[/b][/color]" % [str(k), int(groups[k])])
	if keys.is_empty():
		lines.append("[color=#6f829a]暂无伤害记录[/color]")
	_training_dummy_label.text = "\n".join(lines)


func _training_reset_dummy_stats() -> void:
	for d in _training_dummies:
		if is_instance_valid(d) and d.has_method("reset_stats"):
			d.reset_stats()
	_training_refresh_dummy_stats()


func _training_set_dummy_resist(v: float) -> void:
	_training_dummy_armor = clampi(int(round(v)), 0, 5000)
	if _training_def_btn != null:
		_training_def_btn.text = "防御：%d" % int(_training_dummy_armor)
	for d in _training_dummies:
		if is_instance_valid(d) and d.has_method("set_resist"):
			d.set_resist(_training_dummy_armor)
	_training_refresh_dummy_stats()


func _training_cycle_defense() -> void:
	var tiers := [250.0, 500.0, 1000.0]
	var nx := 250.0
	for t in tiers:
		if t > _training_dummy_armor:
			nx = t
			break
	_training_set_dummy_resist(nx)


func _training_cycle_player_hero() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var names: Array = hero_configs.keys()
	if names.is_empty():
		return
	var cur := names.find(hero.display_name)
	var nx := 0 if cur < 0 else (cur + 1) % names.size()
	var nm := str(names[nx])
	var pos: Vector3 = hero.global_position
	var lv: int = int(hero.level)
	var gold: int = int(hero.gold)
	var old := hero
	# 切换英雄：重置技能等级，并回退已花费技能点（第4技能免费，不计）
	var refund := int(old.skill_points)
	for si in range(mini(3, old.skill_levels.size())):
		refund += int(old.skill_levels[si])
	var keep_inv := bool(old.training_invincible)
	var keep_nocd := bool(old.training_no_cooldown)
	old.queue_free()
	_create_player_hero(nm)
	if hero != null and is_instance_valid(hero):
		hero.global_position = pos
		hero.level = lv
		hero.gold = gold
		for si in range(hero.skill_levels.size()):
			hero.skill_levels[si] = 0
		hero.skill_points = refund
		hero._check_fourth_skill_unlock()
		hero.training_invincible = keep_inv
		hero.training_no_cooldown = keep_nocd
		hero._recalculate_attributes()
	_training_refresh_label()
	_training_refresh_skin_btn()


func _training_refresh_skin_btn() -> void:
	if _training_skin_btn == null:
		return
	if hero == null or not is_instance_valid(hero):
		_training_skin_btn.text = "我的皮肤：—"
		return
	var sid := str(hero.hero_skin_id)
	if sid == "":
		sid = HeroSkinTable.selected_id(hero.display_name)
	_training_skin_btn.text = "我的皮肤：%s" % HeroSkinTable.skin_name(hero.display_name, sid)


func _training_cycle_player_skin() -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var cur := str(hero.hero_skin_id)
	if cur == "":
		cur = HeroSkinTable.selected_id(hero.display_name)
	var nxt := HeroSkinTable.cycle(hero.display_name, cur)
	hero.hero_skin_id = nxt
	HeroSkinTable.set_selected(hero.display_name, nxt)
	HeroSkinTable.apply_to(hero.visual_mesh, hero.display_name, nxt)
	_training_refresh_skin_btn()
	_training_refresh_label()


func _training_cycle_ai_hero() -> void:
	var names: Array = hero_configs.keys()
	if names.is_empty():
		return
	var cur := names.find(_training_ai_hero_name) if _training_ai_hero_name != "" else -1
	var nx := 0 if cur < 0 else (cur + 1) % names.size()
	_training_ai_hero_name = str(names[nx])
	if _training_ai_hero_btn != null:
		_training_ai_hero_btn.text = "AI 英雄：%s" % _training_ai_hero_name
	if _training_ai_count > 0:
		_training_set_ai_count(_training_ai_count)


func _training_exit() -> void:
	_training_mode = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _start_net_lineup(picks: Dictionary) -> void:
	Config.reset_player_team()
	# 大厅选人结果开局：picks = { peer_id: { hero, summoner, role } }
	# 席位 1 = host（本机操控），其余 guest 以“PLAYER 队、无 AI 控制”形态生成，
	# 由 NetSession.assign_lineup() 在开局后按 display_name 逐一配给对应 client 接管。
	var host_pick: Dictionary = picks.get(1, {})
	var host_hero: String = str(host_pick.get("hero", "亚瑟"))
	var host_summ: String = str(host_pick.get("summoner", "flash"))
	if not hero_configs.has(host_hero):
		printerr("[Net] 主机所选英雄不在 hero_configs：", host_hero)
		host_hero = "亚瑟"
	selected_hero_type = host_hero
	hero_selected = true
	GameEntity.debug_show_path = true
	selected_skin_id = str(host_pick.get("skin", ""))
	_create_player_hero(host_hero, host_summ)          # host 本人
	# 其余人类席：按各自选择阵营生成（蓝方/红方），is_ai=true 但不挂 HeroAI（等接管）
	var occupied_roles := [str(host_pick.get("role", ""))]
	var occupied_red: Array = []
	var used_heroes: Array = [host_hero]
	var blue_humans := 1
	var red_humans := 0
	for pid in picks:
		var pn := int(pid)
		if pn == 1:
			continue
		var p: Dictionary = picks[pid]
		var htype: String = str(p.get("hero", ""))
		var summ: String = str(p.get("summoner", "flash"))
		if htype.is_empty():
			continue
		if not hero_configs.has(htype):
			printerr("[Net] 所选英雄不在 hero_configs：", htype)
			continue
		var camp := clampi(int(p.get("team", Config.player_team)), 0, 1)
		var cfg = hero_configs[htype].duplicate()
		cfg["team"] = camp
		var gh := Hero.new()
		gh.setup(cfg)
		gh.is_ai = true
		gh.gold = 500
		gh.position = (Vector3(-58 + randf_range(-2, 2), 0, 58 + randf_range(-2, 2)) if camp == 0
			else Vector3(58 + randf_range(-2, 2), 0, -58 + randf_range(-2, 2)))
		gh.setup_skills_from_database(cfg.get("skills", []), summ)
		gh.hero_skin_id = str(p.get("skin", ""))
		add_child(gh)
		NetSession.assign_guest_hero(pn, gh)
		if gh.display_name == "元流之子":
			gh.yuanliu_pick = ["生机", "穿心", "迅疾", "凝神"][randi() % 4]
			gh._recalculate_attributes()
		used_heroes.append(htype)
		if camp == 0:
			blue_humans += 1
			occupied_roles.append(str(p.get("role", "")))
		else:
			red_humans += 1
			occupied_red.append(str(p.get("role", "")))
	# 顺序选人里展示的 AI/红方席位按 BP 结果生成（避免「看到 X 实际是 Y」）；无 draft 时退回随机
	var drafted: Dictionary = NetSession.get_draft_teams()
	var ally_forced: Array = []
	var enemy_forced: Array = []
	for h in drafted.get("ally", []):
		var hn := str(h)
		if hn != "" and not used_heroes.has(hn):
			ally_forced.append(hn)
	for h in drafted.get("enemy", []):
		var hn2 := str(h)
		if hn2 != "" and not used_heroes.has(hn2) and not ally_forced.has(hn2):
			enemy_forced.append(hn2)
	# 蓝方 AI 补齐到 5：人类已占的职责不重复选（_create_team_ai 内部再排除 host.role）
	_create_team_ai(Config.Team.PLAYER, maxi(0, 5 - blue_humans), occupied_roles, ally_forced)
	_create_team_ai(Config.Team.ENEMY, maxi(0, 5 - red_humans), occupied_red, enemy_forced)   # 红方 AI 补足
	_create_turrets()
	_create_jungle()
	# 元流之子·万物为流：host 泉水四选一（AI 已在生成时随机）
	if hero and hero.display_name == "元流之子":
		UiManager.show_yuanliu_pick(hero)
	_generate_jungle_arc_walls()
	PathFinder.build_navigation_map()
	# 开局语音链：欢迎→准备→全军出击（host 经战报通道转发给接管客户端）
	SfxManager.announce_chain(["welcome", "ready", "attack"])
	# 把 guest 英雄按锁定阵容分发给人（复用接管流程，晚加入兜底仍走 _scan_assignments）
	NetSession.assign_lineup()

# 选人结束倒计时：全部玩家选定英雄后停留 5 秒（数字 5→1），再切到加载界面
const PICK_COUNTDOWN: float = 5.0

func _play_pick_countdown() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vb)
	var tip := Label.new()
	tip.text = "全部玩家已选定英雄"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 34)
	tip.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0))
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tip.add_theme_constant_override("outline_size", 6)
	vb.add_child(tip)
	var num := Label.new()
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 132)
	num.add_theme_color_override("font_color", Color(1.0, 0.84, 0.30))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num.add_theme_constant_override("outline_size", 10)
	vb.add_child(num)
	var timer := get_tree().create_timer(PICK_COUNTDOWN)
	while timer.time_left > 0.0 and is_inside_tree():
		num.text = str(maxi(1, int(ceil(timer.time_left))))
		await get_tree().process_frame
	if is_instance_valid(layer):
		layer.queue_free()

func _start_game(hero_type: String, summoner_id: String = "flash"):
	# 先显示王者式加载界面：BP 用双方 picks，网络 host / --net-test 无 BP 数据时占位
	if _loading_shown: return
	_loading_shown = true
	spectate_hero = null
	rank_result = {}
	# 选人页当前展示的出装顺序（含自动套用的已保存方案）就是本局推荐出装
	if sel_build_hero == hero_type and not sel_build_ids.is_empty():
		ItemDatabase.set_recommended_override(hero_type, sel_build_ids)
	# 随机分配玩家阵营（加载界面/出生点/镜头都由 Config.player_team 决定；联机保持蓝方）
	if NetSession.mode == NetSession.Mode.NONE and not _training_mode:
		Config.roll_player_team()
	# 全部玩家选定英雄后：先走 5 秒倒计时，再进入加载界面
	await _play_pick_countdown()
	var heroes: Array = []
	if sel_ally_picks.size() == 5 and sel_enemy_picks.size() == 5:
		for i in 5:
			var hn := str(sel_ally_picks[i])
			if i == sel_player_seat and hn == "": hn = hero_type
			var ent := {"name": hn if hn != "" else "—", "role": _hero_role(hn), "team": Config.player_team}
			if i == sel_player_seat:
				ent["is_player"] = true
				ent["skin"] = selected_skin_id if selected_skin_id != "" else HeroSkinTable.selected_id(hn)
			elif hn != "":
				ent["skin"] = HeroSkinTable.auto_id(hn, i)
			heroes.append(ent)
		for i in 5:
			var hn := str(sel_enemy_picks[i])
			heroes.append({"name": hn if hn != "" else "—", "role": _hero_role(hn), "team": Config.foe_team(),
				"skin": HeroSkinTable.auto_id(hn, i) if hn != "" else ""})
	else:
		heroes.append({"name": hero_type, "role": _hero_role(hero_type), "team": Config.player_team, "is_player": true,
			"skin": selected_skin_id if selected_skin_id != "" else HeroSkinTable.selected_id(hero_type)})
		for i in 4:
			heroes.append({"name": "—", "role": "我方 %d 号位" % (i + 2), "team": Config.player_team})
		for i in 5:
			heroes.append({"name": "—", "role": "敌方 %d 号位" % (i + 1), "team": Config.foe_team()})
	# 兜底：保证加载界面至少有一张卡按本机真实段位显示
	var has_player_card := false
	for h in heroes:
		if h is Dictionary and bool(h.get("is_player", false)):
			has_player_card = true
			break
	if not has_player_card and not heroes.is_empty():
		heroes[0]["is_player"] = true
	loading_screen = LoadingScreen.new()
	loading_screen.manual_progress = true
	loading_screen.hold_full = true
	loading_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	loading_screen.setup(heroes, "对局加载中", "王者峡谷 · 5v5", 0.1)
	add_child(loading_screen)
	loading_screen.set_progress(0.0)
	if select_ui:
		select_ui.visible = false
	# 加载界面出现即开始搭建战场：暂停游戏逻辑，让加载层作为唯一活动的 UI
	if ui:
		ui.visible = false
	if minimap:
		minimap.visible = false
	if is_instance_valid(TouchController):
		TouchController.set_intro_hidden(true)
	building_battle = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	_start_game_body(hero_type, summoner_id)

# 预热：各兵种×阵营建 1 个原型并各渲染 2 帧，既填充 MinionModel 模板缓存，
# 又让 Mesh/材质完成首帧上传；原型在选人界面后（或在开局时 _clear_prewarm_protos 兜底释放）
var _prewarm_protos: Array = []
func _prewarm_battle_assets() -> void:
	var types := ["melee", "ranged", "siege", "super", "dragon", "storm"]
	for t in types:
		for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
			var wp := [Vector3.ZERO, Vector3(6, 0, 0)]
			var m = spawn_single_minion(t, team, Vector3(0, 1.0, 0), wp, 0)
			if m != null:
				m.set_physics_process(false)
				m.set_process(false)
				_prewarm_protos.append(m)
			await get_tree().process_frame
			await get_tree().process_frame
	_clear_prewarm_protos()

func _clear_prewarm_protos() -> void:
	for p in _prewarm_protos:
		if is_instance_valid(p):
			p.queue_free()
	_prewarm_protos.clear()

func _hero_role(hero_name: String) -> String:
	if hero_name == "" or not hero_configs.has(hero_name): return ""
	return str(hero_configs[hero_name].get("role", ""))

# 加载条到 100% 时战场仍未创建：保持加载界面覆盖，构建完成后再销毁加载层并进入运镜
func _on_loading_progress_full(hero_type: String, summoner_id: String) -> void:
	_start_game_body(hero_type, summoner_id)

func _on_loading_finished(hero_type: String, summoner_id: String) -> void:
	loading_screen = null
	_loading_shown = false
	_start_game_body(hero_type, summoner_id)

func _set_loading_progress(p: float) -> void:
	if loading_screen:
		loading_screen.set_progress(clampf(p, 0.0, 1.0))

# 每个构建阶段推一次真实进度，并让加载界面渲染一帧
func _load_step(p: float) -> void:
	_set_loading_progress(p)
	await get_tree().process_frame

func _start_game_body(hero_type: String, summoner_id: String = "flash"):
	await _load_step(0.04)
	_early_metrics_logged = false
	early_game_metrics = {}
	# 无头 AI 基准：--ai-bench 会把玩家英雄也交给 AI，固定随机种子并加速到 4 分钟后退出。
	var _bench_args := OS.get_cmdline_user_args()
	_ai_benchmark = "--ai-bench" in _bench_args
	_ai_benchmark_keep = "--ai-bench-keep" in _bench_args
	if _ai_test_match:
		Config.player_team = Config.Team.PLAYER
		Engine.time_scale = 4.0
		print("[AI-TEST] time_scale=4")
	if _training_mode:
		Config.player_team = Config.Team.PLAYER
		Engine.time_scale = 1.0
		print("[TRAINING] start")
	if _ai_benchmark:
		for a in _bench_args:
			if str(a).begins_with("--ai-bench-seed="):
				_ai_benchmark_seed = int(str(a).get_slice("=", 1))
			elif str(a).begins_with("--ai-bench-speed="):
				_ai_benchmark_speed = clampf(float(str(a).get_slice("=", 1)), 1.0, 20.0)
		seed(_ai_benchmark_seed)
		AiConfig.difficulty = AiConfig.Difficulty.GOLD
		Config.player_team = Config.Team.PLAYER
		Engine.time_scale = _ai_benchmark_speed
		print("[AI-BENCH] start seed=%d speed=%.1f" % [_ai_benchmark_seed, _ai_benchmark_speed])
	# 进入对局：淡出大厅环境音乐
	SfxManager.stop_menu_music()
	_clear_prewarm_protos()
	selected_hero_type = hero_type
	hero_selected = true
	cam_yaw = PI if Config.player_team == Config.Team.ENEMY else 0.0
	cam.rotation_degrees = Vector3(-60, rad_to_deg(cam_yaw), 0)
	# 调试：默认开启AI路径小球显示（F4可切换）
	GameEntity.debug_show_path = true
	print("[Debug] AI路径球显示已开启（F4切换）")
	print("[Debug] 击杀奖励调试日志已开启（BattleManager.debug_kill_rewards）")
	# 销毁选择UI
	if select_ui:
		select_ui.queue_free()
		select_ui = null
	await _load_step(0.12)

	# 创建实体：BP 结果传入（我方 AI 按号位顺序排除玩家席位；网络 host 路径数组为空→原随机）
	_create_player_hero(hero_type, summoner_id)          # 玩家英雄
	# 基准模式：玩家席位也交给 HeroAI，保证双方都是 5 个 AI，避免“玩家原地挂机”污染指标
	if (_ai_benchmark or _ai_test_match) and is_instance_valid(hero):
		hero.is_ai = true
		var _bench_ai := HeroAI.new()
		hero.add_child(_bench_ai)
	sel_ally_ai_picks = []
	if _training_mode:
		sel_ally_ai_picks = []
		sel_enemy_picks = []
		_training_minions = false
		_training_jungle = false
	elif _ai_test_match:
		# 测试局：加载界面与本局实际生成共用 sel_*_picks 名单
		sel_ally_ai_picks = []
		if sel_ally_picks.size() == 5:
			for i in 5:
				if i != sel_player_seat and str(sel_ally_picks[i]) != "":
					sel_ally_ai_picks.append(str(sel_ally_picks[i]))
			# sel_enemy_picks 保持 5 个，传给 _create_team_ai 作为强制阵容
		else:
			sel_enemy_picks = []
	elif _ai_benchmark:
		# 固定双方阵容，避免每次随机 BP 改变对位，导致前后对比混入阵容噪声
		sel_ally_ai_picks = ["妲己", "李白", "狄仁杰", "太乙真人"]
		sel_enemy_picks = ["铠", "安琪拉", "兰陵王", "孙尚香", "东皇太一"]
	elif sel_ally_picks.size() == 5:
		for i in 5:
			if i != sel_player_seat and str(sel_ally_picks[i]) != "":
				sel_ally_ai_picks.append(str(sel_ally_picks[i]))
	await _load_step(0.26)
	if not _training_mode:
		_create_team_ai(Config.player_team, 4, [], sel_ally_ai_picks)  # 4个己方AI
	await _load_step(0.44)
	if not _training_mode:
		_create_team_ai(Config.foe_team(), 5, [], sel_enemy_picks)    # 5个敌方AI
	# 测试观战：双方 AI 也常显普攻范围圈（便于观察攻距）
	if _ai_test_match:
		for _th in get_tree().get_nodes_in_group("heroes"):
			if _th is Hero:
				_th.show_attack_range_always = true
	sel_ally_picks = []
	sel_enemy_picks = []
	sel_taken = {}
	await _load_step(0.56)
	_create_turrets()
	await _load_step(0.66)
	if not _training_mode:
		_create_jungle()
	await _load_step(0.74)

	# 元流之子·万物为流：玩家开局泉水四选一（弹出面板，AI 已在生成时随机选好）
	if hero and hero.display_name == "元流之子":
		UiManager.show_yuanliu_pick(hero)

	# 野区弧形墙体（必须在 _create_jungle() 之后，营地位置已知）
	_generate_jungle_arc_walls()
	await _load_step(0.84)

	# 重建A*导航网格（包含野区墙体）
	PathFinder.build_navigation_map()
	# 0–4 分钟也先下发一次团队基础任务：分路/保护射手/抓人。
	if team_tactics != null:
		team_tactics.create_initial_tasks()
		_distribute_lane_assignments(team_tactics.assignments)
	await _load_step(0.96)
	await _load_step(1.0)
	if _ai_test_match:
		_setup_test_hud()
	if _training_mode:
		_setup_training_hud()
	# 加载完成后停留 2 秒（进度条 100% 展示完整）再进入战斗
	if loading_screen != null and is_instance_valid(loading_screen):
		await get_tree().create_timer(2.0).timeout
	building_battle = false

	# 开局运镜：镜头由远及近拉向泉水，期间隐藏 UI、暂停 AI 与全部计时
	_begin_intro()
# 三路兵线正常交汇处（= 河道与各路的交叉口）的圆形青砖擂台
const ARENA_SPOTS: Array = [Vector3(43, 0, 43), Vector3(0, 0, 0), Vector3(-43, 0, -43)]
const ARENA_RADIUS: float = 7.2

func _create_map():
	# 1. 浮空岛顶面（圆岛外由 shader discard，露出天空；岛缘/树林在背景层生成）
	var wild = MeshInstance3D.new()
	wild.mesh = PlaneMesh.new()
	wild.mesh.size = Vector2(220, 220)
	# 细分网格：给地面 shader 的顶点起伏（野区微地形）提供顶点
	wild.mesh.subdivide_width = 120
	wild.mesh.subdivide_depth = 120
	wild.position = Vector3(0, -0.02, 0)
	wild.material_override = MapVisuals.island_ground_material()
	add_child(wild)

	# 2. 分路浅绿色（宽度16，沿三路路径绘制，这里简化为三个长矩形平面）
	# 边路一直铺到 ±63 外墙脚下，避免路端悬在墙前留下一条草缝
	# 外侧留 0.3m 让石路缘收进外墙内，不把路缘挑到悬崖外
	_add_lane_plane(Vector3(-55,0,0), Vector2(15.4, 126), 2)   # 对抗路
	# 中路两块正好在 (0,0) 对接，不再留中间草缝（半长 = √(30²+30²) = 42.426）
	_add_lane_plane(Vector3(-30,0,30), Vector2(16, 84.85), 1)     # 中路（沿对角线旋转45度）
	_add_lane_plane(Vector3(0,0,55), Vector2(126, 15.4), 0) # 发育路
	_add_lane_plane(Vector3(55,0,0), Vector2(15.4, 126), 0)   # 发育路
	_add_lane_plane(Vector3(30,0,-30), Vector2(16, 84.85), 1)     # 中路（沿对角线旋转45度）
	_add_lane_plane(Vector3(0,0,-55), Vector2(126, 15.4), 2) # 对抗路
	# 3. 高地青砖色扇形（90度扇形，以地图顶点为中心，面向地图内部）
	var high_player = _create_fan_plane(Vector3(-60,0.2,60), 35, -90, 0, Color.CHARTREUSE, Vector3(-53, 0, 53))
	var high_enemy = _create_fan_plane(Vector3(60,0.2,-60), 35, 90, 180, Color.CHARTREUSE, Vector3(53, 0, -53))
	add_child(high_player)
	add_child(high_enemy)
	# 高地与外墙之间的 3m 石质台沿补齐，并把高地弧边做成斜面石裙
	_add_high_ground_aprons(Vector3(-60,0,60), Vector3(-1,0,0), Vector3(0,0,1), Vector3(-53, 0, 53))
	_add_high_ground_aprons(Vector3(60,0,-60), Vector3(1,0,0), Vector3(0,0,-1), Vector3(53, 0, -53))
	_add_high_ground_rim(Vector3(-60,0,60), -90.0, 0.0)
	_add_high_ground_rim(Vector3(60,0,-60), 90.0, 180.0)

	# 3.5 泉水视觉：基地角上的喷泉广场（圆心沿中路对角线外移，避开水晶攻击范围）
	_add_fountain(Vector3(-62, 0.0, 62), Color(0.2, 0.55, 1.0, 0.35))
	_add_fountain(Vector3(62, 0.0, -62), Color(1.0, 0.25, 0.2, 0.35))

	# 4. 河道（对角线，宽度20，颜色蓝色）
	# 河道必须是不透明材质：透明的大型地面平面会扰乱透明物体排序，
	# 导致贴地特效（如甄姬大招水区）被河道覆盖而不可见
	var river = MeshInstance3D.new()
	var river_mesh = PlaneMesh.new()
	river_mesh.size = Vector2(20, 141)  # 100*1.414
	river_mesh.subdivide_width = 24   # 顶点波动需要足够细分
	river_mesh.subdivide_depth = 70
	river.mesh = river_mesh
	river.rotation_degrees = Vector3(0, 45, 0)
	river.position = Vector3(0, 0.02, 0)  # 高于野区基底(-0.02)，水面波纹也不会被地面遮挡
	river.material_override = MapVisuals.water_material()
	add_child(river)
	# 两岸装饰：湿沙河滩 + 半浸礁石 + 芦苇 + 睡莲
	MapVisuals.spawn_river_banks(self)
	# 三条分路兵线正常交汇处（= 河道与各路的交叉口）：铺圆形青砖擂台
	for i in range(ARENA_SPOTS.size()):
		var arena := DecorMesh.arena_visual(ARENA_SPOTS[i], ARENA_RADIUS)
		arena.name = "LaneArena%d" % i
		arena.position = ARENA_SPOTS[i]
		add_child(arena)

	# 地面碰撞（射线检测用）
	var ground_body = StaticBody3D.new()
	ground_body.collision_layer = 2
	var col = CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	col.shape.size = Vector3(Config.MAP_SIZE, 0.1, Config.MAP_SIZE)
	ground_body.add_child(col)
	ground_body.position = Vector3(0, -0.1, 0)
	add_child(ground_body)

	# 草丛: 兵线交汇处两侧（朝向与河道垂直，与中路平行）
	var bushes = [
		# ==== 中路中心交汇处（河道交叉口） ====
		# 中路中心左侧（偏移-8）
		Vector3(-11,0,-1),
		Vector3(-10,0,-2),
		Vector3(-9,0,-3),
		Vector3(-8,0,-4),
		Vector3(-7,0,-5),
		Vector3(-5,0,-7),
		Vector3(-4,0,-8),
		Vector3(-3,0,-9),
		Vector3(-2,0,-10),
		Vector3(-1,0,-11),
		# 中路中心右侧（偏移+8）
		Vector3(1,0,11),
		Vector3(2,0,10),
		Vector3(3,0,9),
		Vector3(4,0,8),
		Vector3(5,0,7),
		Vector3(7,0,5),
		Vector3(8,0,4),
		Vector3(9,0,3),
		Vector3(10,0,2),
		Vector3(11,0,1),
		Vector3(-47.00, 0, -18.50), 
		Vector3(-47.00, 0, -8.50),
		Vector3(-47.00, 0, 8.50),  
		Vector3(-47.00, 0, 18.50),
		Vector3(47.00, 0, -18.50), 
		Vector3(47.00, 0, -8.50),
		Vector3(47.00, 0, 8.50), 
		Vector3(47.00, 0, 18.50),
		Vector3(-18.50, 0, 47.00),  
		Vector3(-8.50, 0, 47.00),
		Vector3(8.50, 0, 47.00),  
		Vector3(18.50, 0, 47.00),
		Vector3(-18.50, 0, -47.00), 
		Vector3(-8.50, 0, -47.00),
		Vector3(8.50, 0, -47.00),  
		Vector3(18.50, 0, -47.00),
		Vector3(-48.74, 0, 37.42),  
		Vector3(-41.67, 0, 30.35),
		Vector3(-29.65, 0, 18.33), 
		Vector3(-22.58, 0, 11.26),
		Vector3(-37.42, 0, 48.74),  
		Vector3(-30.35, 0, 41.67),
		Vector3(-18.33, 0, 29.65), 
		Vector3(-11.26, 0, 22.58),
		Vector3(37.42, 0, -48.74),  
		Vector3(30.35, 0, -41.67),
		Vector3(18.33, 0, -29.65),  
		Vector3(11.26, 0, -22.58),
		Vector3(48.74, 0, -37.42),  
		Vector3(41.67, 0, -30.35),
		Vector3(29.65, 0, -18.33),  
		Vector3(22.58, 0, -11.26),

		# ---- 蓝方野区草丛 ----
		Vector3(-25,0,35),
		Vector3(-35,0,25),
		Vector3(-15,0,15),
		Vector3(-40,0,0),
		Vector3(-30,0,-10),
		# ---- 红方野区草丛 ----
		Vector3(25,0,-35),
		Vector3(35,0,-25),
		Vector3(15,0,-15),
		Vector3(40,0,0),
		Vector3(30,0,10),
		# ---- 龙坑草丛 ----
		Vector3(-22,0,-22),
		Vector3(22,0,22),
				# ---- 野区弧形墙背后草丛（蓝方） ----
		Vector3(-3,0,37),
		Vector3(-38,0,-3),
		Vector3(-32,0,12),
		Vector3(-44,0,2),
		Vector3(-20,0,35),
		Vector3(-50,0,-23),
		# ---- 野区弧形墙背后草丛（红方） ----
		Vector3(3,0,-37),
		Vector3(38,0,3),
		Vector3(32,0,-12),
		Vector3(44,0,-2),
		Vector3(20,0,-35),
		Vector3(50,0,23),
		# ==== 左上角中路方向草丛（-55,-55中心，11个） ====
		Vector3(-58.54, 0, -51.46),
		Vector3(-57.83, 0, -52.17),
		Vector3(-57.12, 0, -52.88),
		Vector3(-56.41, 0, -53.59),
		Vector3(-55.71, 0, -54.29),
		Vector3(-55.0, 0, -55.0),
		Vector3(-54.29, 0, -55.71),
		Vector3(-53.59, 0, -56.41),
		Vector3(-52.88, 0, -57.12),
		Vector3(-52.17, 0, -57.83),
		Vector3(-51.46, 0, -58.54),
		# ==== 左上角中路方向草丛（-40,-40中心，7个） ====
		Vector3(-42.12, 0, -37.88),
		Vector3(-41.41, 0, -38.59),
		Vector3(-40.71, 0, -39.29),
		Vector3(-40.0, 0, -40.0),
		Vector3(-39.29, 0, -40.71),
		Vector3(-38.59, 0, -41.41),
		Vector3(-37.88, 0, -42.12),
		# ==== 右下角中路方向草丛（55,55中心，11个） ====
		Vector3(58.54, 0, 51.46),
		Vector3(57.83, 0, 52.17),
		Vector3(57.12, 0, 52.88),
		Vector3(56.41, 0, 53.59),
		Vector3(55.71, 0, 54.29),
		Vector3(55.0, 0, 55.0),
		Vector3(54.29, 0, 55.71),
		Vector3(53.59, 0, 56.41),
		Vector3(52.88, 0, 57.12),
		Vector3(52.17, 0, 57.83),
		Vector3(51.46, 0, 58.54),
		# ==== 右下角中路方向草丛（40,40中心，7个） ====
		Vector3(42.12, 0, 37.88),
		Vector3(41.41, 0, 38.59),
		Vector3(40.71, 0, 39.29),
		Vector3(40.0, 0, 40.0),
		Vector3(39.29, 0, 40.71),
		Vector3(38.59, 0, 41.41),
		Vector3(37.88, 0, 42.12),
		# ==== 三路城墙缺口草丛 ====
			]
	# 塔射程内 / 高地内不放草丛（塔下、高地内部不应有隐身草）
	var _bush_kept: Array = []
	for _bp in bushes:
		if _bush_forbidden(_bp):
			continue
		_bush_kept.append(_bp)
	bushes = _bush_kept
	_bush_positions = bushes

	# ---- 墙体与草丛生成 ----
	_generate_lane_edge_walls()
	_generate_high_ground_walls()
	_generate_outer_walls()
	# 野区弧形墙体移到 _start_game() 中 _create_jungle() 之后生成

	# 划分草丛区域：草丛排列间距约1.4m(对角相邻)，同排仅个别2.83m缺口(河道交汇)，
	# 取2.9m作为“同一排”判距——互相连通的草丛归为一个区域，同排内敌我英雄互相暴露
	var _bush_region_of: Array[int] = []
	_bush_region_of.resize(bushes.size())
	_bush_region_of.fill(-1)
	var next_bush_region := 0
	for i in bushes.size():
		if _bush_region_of[i] >= 0:
			continue
		_bush_region_of[i] = next_bush_region
		var stack: Array[int] = [i]
		while not stack.is_empty():
			var ci: int = stack.pop_back()
			for j in bushes.size():
				if _bush_region_of[j] >= 0:
					continue
				var ca: Vector3 = bushes[ci]
				var cb: Vector3 = bushes[j]
				if Vector2(ca.x, ca.z).distance_to(Vector2(cb.x, cb.z)) <= 2.9:
					_bush_region_of[j] = next_bush_region
					stack.append(j)
		next_bush_region += 1

	for i in bushes.size():
		var bush = Bush.new()
		bush.position = bushes[i]
		bush.region_id = _bush_region_of[i]
		add_child(bush)

	# 装饰物（草丛 / 河岸石墙 / 陶罐，MultiMesh 批量，移动端友好）
	MapVisuals.scatter_decorations(self)
	# 浮空岛：岛缘岩壁、岛底倒锥、墙外树林/草坡/碎石与远处浮岩
	MapVisuals.spawn_floating_island(self)

# 分路平面登记表：{lane: [MeshInstance3D]}（0发育路 1中路 2对抗路）
var lane_plane_nodes: Dictionary = {}
var _lane_plane_idx := 0
# 暗影之径计时：{team: {lane: 剩余秒数}}（固定60秒，与先锋存活无关）
var shadow_path_timers: Dictionary = {}


func _add_lane_plane(center: Vector3, size: Vector2, lane: int):
	var plane = MeshInstance3D.new()
	plane.mesh = PlaneMesh.new()
	plane.mesh.size = size
	plane.position = center
	if center.x+center.z==0:
		plane.rotation_degrees = Vector3(0, -45, 0)
	# 不同走向的路面错开 1~2mm，交叉口不出现同高面 z-fighting
	plane.position.y = 0.14 + 0.0012 * float(_lane_plane_idx % 6)
	_lane_plane_idx += 1
	plane.material_override = MapVisuals.ground_material()
	# 分路两侧石质路缘：沿长边铺满，把路/河/草地的硬接缝收进石头边里。
	# 经过兵线交汇擂台的路缘必须断开，否则那条石台会直接架在青砖擂台上。
	var curb_mat: Material = DecorMesh.rock_material()
	var along_x: bool = size.x >= size.y
	var curb_len: float = size.x if along_x else size.y
	for s in [-1.0, 1.0]:
		var offset: float = (size.y * 0.5 + 0.25) * s if along_x else (size.x * 0.5 + 0.25) * s
		for seg in _curb_segments(center, plane.rotation.y, along_x, offset, curb_len):
			var cm := BoxMesh.new()
			var curb := MeshInstance3D.new()
			var span: float = seg.y - seg.x
			if span < 0.3:
				continue
			if along_x:
				cm.size = Vector3(span, 0.22, 0.6)
				curb.position = Vector3((seg.x + seg.y) * 0.5, -0.04, offset)
			else:
				cm.size = Vector3(0.6, 0.22, span)
				curb.position = Vector3(offset, -0.04, (seg.x + seg.y) * 0.5)
			curb.mesh = cm
			curb.material_override = curb_mat
			plane.add_child(curb)
	add_child(plane)
	if not lane_plane_nodes.has(lane):
		lane_plane_nodes[lane] = []
	lane_plane_nodes[lane].append(plane)


## 路缘被擂台挖断后的剩余区间（平面局部沿轴坐标，Vector2(起, 止)）
func _curb_segments(plane_pos: Vector3, yaw: float, along_x: bool, offset: float, length: float) -> Array:
	var half: float = length * 0.5
	var inv := Basis(Vector3.UP, yaw).inverse()
	var r: float = ARENA_RADIUS + 0.35
	var gaps: Array = []
	for spot in ARENA_SPOTS:
		var lp: Vector3 = inv * (spot - plane_pos)
		var across: float = lp.z if along_x else lp.x
		var along: float = lp.x if along_x else lp.z
		var d: float = absf(across - offset)
		if d >= r:
			continue
		var dx: float = sqrt(r * r - d * d)
		gaps.append(Vector2(along - dx, along + dx))
	var segs: Array = []
	if gaps.is_empty():
		segs.append(Vector2(-half, half))
		return segs
	gaps.sort_custom(func(a, b): return a.x < b.x)
	var cursor: float = -half
	for g in gaps:
		var a: float = maxf(g.x, -half)
		var b: float = minf(g.y, half)
		if b <= a:
			continue
		if a > cursor + 0.3:
			segs.append(Vector2(cursor, a))
		cursor = maxf(cursor, b)
	if half > cursor + 0.3:
		segs.append(Vector2(cursor, half))
	# 擂台把路缘断开后，落在路平面末端的那半截露头台阶直接不要，只保留靠里侧的长段
	if segs.size() > 1:
		var longest: Vector2 = segs[0]
		for sgm in segs:
			if (sgm.y - sgm.x) > (longest.y - longest.x):
				longest = sgm
		return [longest]
	return segs


# 暗影之径视觉：分路平面淡淡染紫 + 路面暗影能量覆盖层（流动脉络 / 发光路缘，淡入淡出）
var shadow_path_overlays: Dictionary = {}   # lane -> [MeshInstance3D]
var shadow_path_mats: Dictionary = {}       # lane -> ShaderMaterial（同路共享，整路一起淡入淡出）
var shadow_path_fade: Dictionary = {}       # lane -> [当前强度, 目标强度]
const SHADOW_PATH_SHADER := preload("res://shaders/fx_shadow_path.gdshader")


# 首次激活时按分路平面尺寸铺一层暗影覆盖贴片（子节点，随分路平面一起变换）
func _ensure_shadow_path_overlay(lane: int) -> void:
	if shadow_path_mats.has(lane):
		return
	var mat := ShaderMaterial.new()
	mat.shader = SHADOW_PATH_SHADER
	mat.set_shader_parameter("intensity", 0.0)
	shadow_path_mats[lane] = mat
	var nodes: Array = []
	for plane in lane_plane_nodes.get(lane, []):
		var pm := plane.mesh as PlaneMesh
		if pm == null:
			continue
		var ov := MeshInstance3D.new()
		var om := PlaneMesh.new()
		om.size = pm.size
		ov.mesh = om
		ov.material_override = mat
		ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ov.position = Vector3(0.0, 0.03, 0.0)
		ov.visible = false
		plane.add_child(ov)
		nodes.append(ov)
	shadow_path_overlays[lane] = nodes


# 每帧推进覆盖层淡入淡出（与计时分离，保证结束后也能平滑淡出）
func _update_shadow_path_fades(delta: float) -> void:
	if shadow_path_fade.is_empty():
		return
	for lane in shadow_path_fade.keys():
		var st: Array = shadow_path_fade[lane]
		var cur: float = move_toward(float(st[0]), float(st[1]), delta / 0.45)
		st[0] = cur
		var mat: ShaderMaterial = shadow_path_mats.get(lane, null)
		if mat:
			mat.set_shader_parameter("intensity", cur)
		if cur <= 0.002 and float(st[1]) <= 0.0:
			for ov in shadow_path_overlays.get(lane, []):
				ov.visible = false
			shadow_path_fade.erase(lane)


# 暗影之径视觉：分路平面变紫/恢复
func _set_shadow_path_visual(lane: int, active: bool):
	_ensure_shadow_path_overlay(lane)
	for ov in shadow_path_overlays.get(lane, []):
		if active:
			ov.visible = true
	var prev: Array = shadow_path_fade.get(lane, [0.0, 0.0])
	shadow_path_fade[lane] = [float(prev[0]), 1.0 if active else 0.0]
	for plane in lane_plane_nodes.get(lane, []):
		var mat = plane.material_override
		if mat == null:
			continue
		if mat is ShaderMaterial:
			# 地面视觉层用的是地面着色器：靠 tint / emission 参数染紫（淡染，主要光效交给覆盖层）
			var sm := mat as ShaderMaterial
			if active:
				sm.set_shader_parameter("tint", Color(0.80, 0.66, 1.0, 1.0))
				sm.set_shader_parameter("emission_color", Color(0.42, 0.22, 0.85, 1.0))
				sm.set_shader_parameter("emission_strength", 0.22)
			else:
				sm.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 1.0))
				sm.set_shader_parameter("emission_strength", 0.0)
		elif mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			if active:
				std.albedo_color = Color(0.62, 0.42, 0.85)
				std.emission_enabled = true
				std.emission = Color(0.35, 0.2, 0.55)
				std.emission_energy_multiplier = 0.22
			else:
				std.albedo_color = Color.FOREST_GREEN
				std.emission_enabled = false


# 暗影之径计时递减：某分路两队均无激活时恢复平面颜色
func _update_shadow_paths(delta: float):
	if shadow_path_timers.is_empty():
		return
	var expired: Array = []
	for team in shadow_path_timers.keys():
		var lanes: Dictionary = shadow_path_timers[team]
		for lane in lanes.keys():
			lanes[lane] -= delta
			if lanes[lane] <= 0:
				expired.append([team, lane])
	for pair in expired:
		shadow_path_timers[pair[0]].erase(pair[1])
		if shadow_path_timers[pair[0]].is_empty():
			shadow_path_timers.erase(pair[0])
		var any_active = false
		for team2 in shadow_path_timers.keys():
			if shadow_path_timers[team2].has(pair[1]):
				any_active = true
				break
		if not any_active:
			_set_shadow_path_visual(pair[1], false)


# 判断位置是否处于指定分路（X+Z>0=发育路0，X+Z<0=对抗路2，|X+Z|<=15=中路1）
func _is_on_lane(pos: Vector3, lane: int) -> bool:
	var s = pos.x + pos.z
	if abs(s) <= 15:
		return lane == 1   # 中路（河道对角线带）
	return (s > 0 and lane == 0) or (s < 0 and lane == 2)

## 任意位置所属分路（0发育路 / 1中路 / 2对抗路），与 _is_on_lane 同口径
func _lane_of_position(pos: Vector3) -> int:
	var s := pos.x + pos.z
	if absf(s) <= 15.0:
		return 1
	return 0 if s > 0.0 else 2


# 指定队伍在当前位置的暗影之径是否激活
func is_on_shadow_path(team: int, pos: Vector3) -> bool:
	if not shadow_path_timers.has(team):
		return false
	for lane in shadow_path_timers[team].keys():
		if _is_on_lane(pos, lane):
			return true
	return false

## 高地到外墙之间的 3m 石台：out_a/out_b 为两条朝外墙的方向，补齐高地直边与城墙间的草缝
## 材质与高度跟高地扇形砖完全一致（同一套以水晶为圆心的同心环砖、砖顶 0.177），
## 这样高地砖 → 台沿 → 外周城墙是一条连续的砖面，直边处不再出现材质/高差错缝
func _add_high_ground_aprons(center: Vector3, out_a: Vector3, out_b: Vector3, brick_center: Vector3) -> void:
	var mat := DecorMesh.hq_ring_brick_material(brick_center)
	var inward_a := -out_a
	var inward_b := -out_b
	# 两条 3m 宽石台，长度取高地半径 35；转角再补 3×3
	_add_flat_quad(center + out_a * 1.5 + inward_b * 17.5, Vector2(3.0, 35.0), mat, 0.177)
	_add_flat_quad(center + out_b * 1.5 + inward_a * 17.5, Vector2(35.0, 3.0), mat, 0.177)
	_add_flat_quad(center + out_a * 1.5 + out_b * 1.5, Vector2(3.0, 3.0), mat, 0.177)


func _add_flat_quad(pos: Vector3, size_v: Vector2, mat: Material, y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size_v
	mi.mesh = pm
	# PlaneMesh 本身就是水平 XZ 面，不能再绕 X 转 90°，否则石台会竖起来
	mi.position = Vector3(pos.x, y, pos.z)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## 高地弧形边缘的石质斜裙：从砖面外沿落到草地；压在分路上时只落到路面高度（0.146），
## 这样高地砖与分路平面的接壤处是一段缓坡石阶，不再是 5cm 高的硬切口。
func _add_high_ground_rim(center: Vector3, start_deg: float, end_deg: float) -> void:
	var steps := 96
	var raw: Array = []
	for i in steps + 1:
		var a := deg_to_rad(start_deg + (end_deg - start_deg) * float(i) / float(steps))
		var wx: float = center.x + cos(a) * 36.0
		var wz: float = center.z + sin(a) * 36.0
		raw.append(0.146 if MapVisuals._lane_mask(wx, wz) > 0.05 else 0.025)
	# 只把"压在分路上"的那几段抬到路面高度（外扩一格），草地部分仍落到地面，免得斜裙悬空
	var out_ys: Array = []
	for i in raw.size():
		var v: float = float(raw[i])
		v = maxf(v, float(raw[clampi(i - 1, 0, raw.size() - 1)]))
		v = maxf(v, float(raw[clampi(i + 1, 0, raw.size() - 1)]))
		out_ys.append(v)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := deg_to_rad(start_deg + (end_deg - start_deg) * float(i) / float(steps))
		var a1 := deg_to_rad(start_deg + (end_deg - start_deg) * float(i + 1) / float(steps))
		var y0: float = float(out_ys[i])
		var y1: float = float(out_ys[i + 1])
		# 内沿必须与高地砖面齐平(砖顶 0.175)：原来 0.198 会让石裙内沿比砖面高 2.3cm，
		# 低机位能看到砖面与石裙之间那条缝，故压到 0.176 与砖面贴合
		var in0 := center + Vector3(cos(a0) * 34.5, 0.176, sin(a0) * 34.5)
		var in1 := center + Vector3(cos(a1) * 34.5, 0.176, sin(a1) * 34.5)
		var out0 := center + Vector3(cos(a0) * 36.4, y0, sin(a0) * 36.4)
		var out1 := center + Vector3(cos(a1) * 36.4, y1, sin(a1) * 36.4)
		st.add_vertex(in0); st.add_vertex(in1); st.add_vertex(out0)
		st.add_vertex(in1); st.add_vertex(out1); st.add_vertex(out0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HighGroundRim"
	mi.mesh = st.commit()
	mi.material_override = _double_sided_rock()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)


func _double_sided_rock() -> ShaderMaterial:
	var base := DecorMesh.rock_material()
	var sh := (base.shader as Shader).duplicate() as Shader
	sh.code = sh.code.replace(
		"render_mode diffuse_burley, specular_schlick_ggx;",
		"render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _create_fan_plane(center: Vector3, radius: float, start_angle: float, end_angle: float, color: Color,
		brick_center: Vector3 = Vector3.ZERO) -> Node3D:
	var csg = CSGPolygon3D.new()
	var poly = PackedVector2Array()
	poly.append(Vector2.ZERO)
	var steps = 32
	for i in range(steps + 1):
		var a = deg_to_rad(start_angle + (end_angle - start_angle) * i / steps)
		poly.append(Vector2(cos(a) * radius, sin(a) * radius))
	csg.polygon = poly
	csg.depth = 0.05
	csg.position = center + Vector3(0, -0.025, 0)
	csg.rotation_degrees = Vector3(90, 0, 0)
	# 高地青砖：整体是以水晶为圆心的同心圆环（无水晶圆心时退回旧材质）
	if brick_center != Vector3.ZERO:
		csg.material_override = DecorMesh.hq_ring_brick_material(brick_center)
	else:
		csg.material_override = MapVisuals.high_ground_material()
	return csg

# 泉水视觉：石砌池沿 + 波纹水面 + 中央喷泉柱 + 溅水粒子 + 旋转符文环 + 顶光（纯程序化）
func _add_fountain(center: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.name = "Fountain"
	root.position = Vector3(center.x, 0.0, center.z)
	add_child(root)
	var stone := DecorMesh.rock_material()
	# 石质池底（外沿略大，厚度感）
	var basin := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 3.30
	bcyl.bottom_radius = 3.50
	bcyl.height = 0.28
	bcyl.radial_segments = 40
	basin.mesh = bcyl
	basin.position = Vector3(0, 0.14, 0)
	basin.material_override = stone
	root.add_child(basin)
	# 池沿石环
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.87
	torus.outer_radius = 3.37
	torus.rings = 40
	torus.ring_segments = 10
	rim.mesh = torus
	rim.position = Vector3(0, 0.30, 0)
	rim.material_override = stone
	root.add_child(rim)
	# 水面（波纹 shader）
	var water := MeshInstance3D.new()
	var wcyl := CylinderMesh.new()
	wcyl.top_radius = 2.95
	wcyl.bottom_radius = 2.95
	wcyl.height = 0.05
	wcyl.radial_segments = 48
	water.mesh = wcyl
	water.position = Vector3(0, 0.295, 0)
	water.material_override = _fountain_water_material(color)
	root.add_child(water)
	# 中央石座
	var ped := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.42
	pcyl.bottom_radius = 0.72
	pcyl.height = 0.95
	pcyl.radial_segments = 16
	ped.mesh = pcyl
	ped.position = Vector3(0, 0.75, 0)
	ped.material_override = stone
	root.add_child(ped)
	# 水柱
	var jet := MeshInstance3D.new()
	var jcyl := CylinderMesh.new()
	jcyl.top_radius = 0.20
	jcyl.bottom_radius = 0.34
	jcyl.height = 2.10
	jcyl.radial_segments = 14
	jet.mesh = jcyl
	jet.position = Vector3(0, 2.30, 0)
	jet.material_override = _fountain_jet_material(color)
	root.add_child(jet)
	# 溅水粒子
	var splash := CPUParticles3D.new()
	splash.amount = 44
	splash.lifetime = 1.15
	var drop := SphereMesh.new()
	drop.radius = 0.065
	drop.height = 0.13
	drop.radial_segments = 6
	drop.rings = 3
	splash.mesh = drop
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.42
	splash.position = Vector3(0, 3.30, 0)
	splash.direction = Vector3.UP
	splash.spread = 42.0
	splash.initial_velocity_min = 0.6
	splash.initial_velocity_max = 1.9
	splash.gravity = Vector3(0, -5.2, 0)
	splash.scale_amount_min = 0.7
	splash.scale_amount_max = 1.6
	splash.color = Color(color.r * 0.5 + 0.5, color.g * 0.55 + 0.55, 1.0, 0.75)
	var splash_mat := StandardMaterial3D.new()
	splash_mat.albedo_color = Color(0.82, 0.93, 1.0, 1.0)
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.vertex_color_use_as_albedo = true
	splash.material_override = splash_mat
	root.add_child(splash)
	# 旋转符文环（12 块发光刻符）
	var rune := Node3D.new()
	rune.name = "RuneRing"
	root.add_child(rune)
	var rune_mesh := BoxMesh.new()
	rune_mesh.size = Vector3(0.14, 0.035, 0.40)
	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = color
	rune_mat.emission_enabled = true
	rune_mat.emission = Color(color.r, color.g, color.b)
	rune_mat.emission_energy_multiplier = 2.4
	rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		var rmi := MeshInstance3D.new()
		rmi.mesh = rune_mesh
		rmi.material_override = rune_mat
		rmi.position = Vector3(cos(a) * 3.72, 0.09, sin(a) * 3.72)
		rmi.rotation.y = -a
		rune.add_child(rmi)
	# 地面队伍色光晕（脉动）
	var glow := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 3.60
	gcyl.bottom_radius = 3.60
	gcyl.height = 0.02
	gcyl.radial_segments = 40
	glow.mesh = gcyl
	glow.position = Vector3(0, 0.05, 0)
	glow.material_override = _fountain_glow_material(color)
	root.add_child(glow)
	# 顶部点光
	var lt := OmniLight3D.new()
	lt.light_color = color
	lt.light_energy = 2.0
	lt.omni_range = 11.0
	lt.position = Vector3(0, 2.9, 0)
	root.add_child(lt)
	# 符文环缓慢旋转（纯视觉；不在场景树时跳过）
	if not is_inside_tree():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(rune, "rotation:y", TAU, 16.0).from(0.0)

func _fountain_water_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

uniform vec4 tint : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.4, 0.8, 1.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = clamp(length(uv), 0.0, 1.0);
	float t = TIME;
	float w = sin(r * 26.0 - t * 3.0) * 0.5 + 0.5;
	float w2 = sin(r * 10.0 + t * 1.5) * 0.5 + 0.5;
	float rings = smoothstep(0.45, 0.95, w * 0.55 + w2 * 0.55);
	ALBEDO = tint.rgb * (0.70 + 0.40 * rings);
	EMISSION = glow.rgb * (0.16 + 0.95 * rings * (1.0 - r * 0.55));
	ALPHA = clamp(0.55 + 0.42 * rings * (1.0 - r), 0.0, 1.0);
	ROUGHNESS = 0.10;
	SPECULAR = 0.85;
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("glow", Color(color.r * 0.45 + 0.45, color.g * 0.55 + 0.55, 1.0))
	return mat

func _fountain_jet_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(0.6, 0.85, 1.0, 1.0);

void fragment() {
	float flow = fract(UV.y * 2.4 - TIME * 1.5);
	float stripe = smoothstep(0.0, 0.30, flow) * smoothstep(1.0, 0.55, flow);
	float wob = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 9.0 + UV.x * 6.2831);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * (0.85 + 1.6 * stripe);
	ALPHA = clamp(0.14 + 0.42 * stripe * wob, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Color(color.r * 0.45 + 0.45, color.g * 0.55 + 0.55, 1.0))
	return mat

func _fountain_glow_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = clamp(length(uv), 0.0, 1.0);
	float pulse = 0.72 + 0.28 * sin(TIME * 1.6);
	float a = (1.0 - smoothstep(0.0, 1.0, r)) * 0.45 + smoothstep(0.62, 1.0, r) * 0.60;
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 1.5 * pulse;
	ALPHA = clamp(a * pulse, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	return mat

const LingbaoScript = preload("res://scripts/entities/Lingbao.gd")
const ReplayScript = preload("res://scripts/core/ReplayRecorder.gd")   # 对局录像（P1）
const TrainingDummyScript = preload("res://scripts/entities/TrainingDummy.gd")

func _create_player_hero(type: String, summoner_id: String = "flash"):
	var config = hero_configs[type].duplicate()
	config["team"] = Config.player_team
	hero = Hero.new()
	hero.setup(config)
	hero.player_name = NameStore.player_name()
	hero.position = Vector3(-60, 0, 60) if Config.player_team == Config.Team.PLAYER else Vector3(60, 0, -60)
	hero.setup_skills_from_database(config.get("skills", []), summoner_id)
	hero.gold = 500
	# 本局所选皮肤：优先用选人界面当前选择，其次读每个英雄的持久化选择
	var _skin_pick := selected_skin_id if selected_hero_type == type else ""
	if _skin_pick == "":
		_skin_pick = HeroSkinTable.selected_id(type)
	hero.hero_skin_id = _skin_pick
	add_child(hero)
	TouchController.set_hero(hero)
	LingbaoScript.ensure(self)
	if _record_replay:
		ReplayScript.ensure(self)

func _create_team_ai(team: int, count: int, exclude_roles: Array = [], forced_heroes: Array = []):
	# 只有apply_skills实现的英雄
	var valid_heroes = ["狄仁杰", "马可波罗", "孙尚香", "马超", "吕布", "沈梦溪", "不知火舞", "甄姬", "铠", "亚瑟", "太乙真人", "东皇太一", "李白", "兰陵王", "张飞", "安琪拉", "妲己", "小乔", "鲁班七号", "王昭君", "夏侯惇", "后羿", "李元芳", "元流之子", "大禹", "刘禅", "孙悟空", "英睿"]
	var roles = {"刺客": [], "法师": [], "射手": [], "战士": [], "辅助": [], "坦克": []}
	for type in valid_heroes:
		var cfg = hero_configs.get(type, {})
		var r = cfg.get("role", "战士")
		if r == "刺客": roles["刺客"].append(type)
		elif r == "法师": roles["法师"].append(type)
		elif r == "射手": roles["射手"].append(type)
		elif r == "辅助": roles["辅助"].append(type)
		elif r == "坦克": roles["坦克"].append(type)
		else: roles["战士"].append(type)
	var picks = []
	# 指定英雄优先（BP 结果）：按数组顺序，跳过不存在/空值/重复
	for f in forced_heroes:
		if picks.size() >= count: break
		var fname := str(f)
		if fname == "" or not hero_configs.has(fname) or picks.has(fname): continue
		picks.append(fname)
	var required = ["刺客", "法师", "射手", "战士", "辅助"]
	# 玩家方：排除人类已占职责（大厅 lock 的 exclude_roles + host 本人），AI 补齐缺的职责
	if team == Config.player_team:
		for r in exclude_roles:
			required.erase(r)
		if hero and hero.role in required:
			required.erase(hero.role)
	elif not exclude_roles.is_empty():
		# 联机 PvP：红方真人已占职责同样排除，AI 补剩余职责
		for r2 in exclude_roles:
			required.erase(r2)
	# 敌方(ENEMY)不排除任何职责；单机 PLAYER count=4 时 exclude_roles 为空 → 同原逻辑
	for r in required:
		if picks.size() >= count: break
		var avail: Array = []
		for t in roles[r]:
			if not picks.has(t): avail.append(t)
		if avail.size() > 0:
			picks.append(avail[randi() % avail.size()])
	# 若所需英雄数 > 已选数，用剩余英雄补齐
	var all_remaining = []
	for r in roles:
		for t in roles[r]:
			if not picks.has(t): all_remaining.append(t)
	all_remaining.shuffle()
	var k := 0
	while picks.size() < count and k < all_remaining.size():
		picks.append(all_remaining[k])
		k += 1
	for type in picks:
		var config = hero_configs[type].duplicate()
		config["team"] = team
		var ai_hero = Hero.new()
		ai_hero.setup(config)
		ai_hero.is_ai = true
		if _match_ai_names.is_empty():
			_match_ai_names = sel_ai_names.duplicate() if not sel_ai_names.is_empty() else NameStore.random_ai_names(10, [NameStore.player_name()])
			_ai_name_cursor = 0
		ai_hero.player_name = str(_match_ai_names[_ai_name_cursor % _match_ai_names.size()])
		_ai_name_cursor += 1
		ai_hero.gold = 500
		# 测试模式：给每个 AI 随机分配一套皮肤
		if _ai_test_match or "--ai-bench" in OS.get_cmdline_user_args():
			ai_hero.hero_skin_id = HeroSkinTable.random_test_id(ai_hero.display_name)
		if team == Config.Team.PLAYER:
			ai_hero.position = Vector3(-60 + randf_range(-0.4,0.4), 0, 60 + randf_range(-0.4,0.4))
		else:
			ai_hero.position = Vector3(60 + randf_range(-0.4,0.4), 0, -60 + randf_range(-0.4,0.4))
		# AI 使用英雄推荐召唤师技能，不再随机
		var ai_summ := _hero_summ_id(str(ai_hero.display_name))
		if ai_summ == "" or ai_summ == "flash":
			var rec := HeroPickData.recommended_summoner(str(ai_hero.display_name))
			if rec != "":
				ai_summ = rec
		ai_hero.setup_skills_from_database(config.get("skills", []), ai_summ)
		var ai = HeroAI.new()
		ai_hero.add_child(ai)
		add_child(ai_hero)
		# 元流之子·万物为流：AI 泉水四选一随机（数值烘焙到重算）
		if ai_hero.display_name == "元流之子":
			ai_hero.yuanliu_pick = ["生机", "穿心", "迅疾", "凝神"][randi() % 4]
			ai_hero._recalculate_attributes()
func _get_turret_config(type: String, team: int) -> Dictionary:
	var base = {}
	match type:
		"outer":
			base = {"max_health": 7500, "attack": 510, "attack_speed": 1.0, "attack_range": 890, "armor": 200, "magic_resist": 200, "body_radius": 0.5}
		"inner":
			base = {"max_health": 8500, "attack": 510, "attack_speed": 1.0, "attack_range": 890, "armor": 200, "magic_resist": 200, "body_radius": 0.5}
		"high":
			base = {"max_health": 9000, "attack": 630, "attack_speed": 1.0, "attack_range": 890, "armor": 200, "magic_resist": 200, "body_radius": 0.5}
		"crystal":
			base = {"max_health": 9000, "attack": 550, "attack_speed": 0.7, "attack_range": 890, "armor": 200, "magic_resist": 200, "body_radius": 0.5}
	base["team"] = team
	return base
func spawn_tower_wreck(team: int, pos: Vector3, slow_pct: float):
	var wreck := TurretWreck.new()
	wreck.team = team
	wreck.radius = 8.9   # 塔原攻击半径
	wreck.slow_pct = slow_pct
	wreck.position = pos
	add_child(wreck)
	spawn_tower_stump(team, pos)

# 原地永久塔墩：残破石台 + 断柱 + 断口碎块 + 地面碎石 + 阵营色残环（无碰撞，不挡兵线）
func spawn_tower_stump(team: int, pos: Vector3) -> void:
	var key := "%d_%d" % [int(round(pos.x)), int(round(pos.z))]
	if _tower_stumps.has(key):
		return
	var stump := Node3D.new()
	stump.name = "TowerStump"
	stump.position = Vector3(pos.x, 0.0, pos.z)
	var team_col: Color = Color(0.32, 0.56, 1.0) if team == Config.Team.PLAYER else Color(1.0, 0.40, 0.34)
	# 底座石台
	var base := MeshInstance3D.new()
	var bm2 := CylinderMesh.new()
	bm2.top_radius = 1.85
	bm2.bottom_radius = 2.02
	bm2.height = 0.34
	bm2.radial_segments = 12
	base.mesh = bm2
	base.position = Vector3(0, 0.17, 0)
	base.material_override = _stump_mat(Color(0.40, 0.40, 0.44))
	stump.add_child(base)
	# 断柱（轻微倾斜，像被炸断）
	var col := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = 0.96
	cm2.bottom_radius = 1.24
	cm2.height = 1.06
	cm2.radial_segments = 10
	col.mesh = cm2
	col.position = Vector3(0.07, 0.84, -0.05)
	col.rotation = Vector3(deg_to_rad(4.5), deg_to_rad(18.0), deg_to_rad(-3.0))
	col.material_override = _stump_mat(Color(0.30, 0.30, 0.34))
	stump.add_child(col)
	# 断口碎块
	for i in 4:
		var frag := MeshInstance3D.new()
		var fm2 := BoxMesh.new()
		fm2.size = Vector3(0.34, 0.16, 0.30)
		frag.mesh = fm2
		frag.position = Vector3(0.18 * (float(i) - 1.5), 1.33 + 0.03 * float(i), 0.10 * (float(i) - 2.0))
		frag.rotation = Vector3(0.2 * float(i), 0.7 * float(i), 0.15 * float(i))
		frag.material_override = _stump_mat(Color(0.26, 0.26, 0.30))
		stump.add_child(frag)
	# 地面碎石
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 131.0 + pos.z * 17.0)
	for i in 7:
		var rock := MeshInstance3D.new()
		var rm2 := SphereMesh.new()
		rm2.radius = 0.16 + rng.randf() * 0.12
		rm2.height = rm2.radius * 1.4
		rock.mesh = rm2
		var ang := rng.randf() * TAU
		var rr := 1.9 + rng.randf() * 1.4
		rock.position = Vector3(cos(ang) * rr, 0.11, sin(ang) * rr)
		rock.scale = Vector3(1.0, 0.62, 1.0)
		rock.material_override = _stump_mat(Color(0.34, 0.33, 0.36))
		stump.add_child(rock)
	# 阵营色残环（标明原归属）
	var ring := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 1.90
	tm2.outer_radius = 2.06
	ring.mesh = tm2
	ring.position = Vector3(0, 0.35, 0)
	var rmat2 := StandardMaterial3D.new()
	rmat2.albedo_color = Color(team_col.r, team_col.g, team_col.b, 0.55)
	rmat2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat2
	stump.add_child(ring)
	stump.add_to_group("tower_stumps")   # 废墟塔墩：参与实体推挤（不靠寻路网格阻挡）
	add_child(stump)
	_tower_stumps[key] = stump

func _stump_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	return m

func spawn_health_pack(pos: Vector3, team: int):
	var pack = HealthPack.new()
	pack.team = team
	pack.position = pos
	pack.position.y +=0.3
	add_child(pack)
const HEALTH_PACK_SPAWNS := [
	[Vector3(24, 0, 58), 0], [Vector3(-58, 0, -24), 0], [Vector3(-17, 0, 17), 0],
	[Vector3(-24, 0, -58), 1], [Vector3(58, 0, 24), 1], [Vector3(17, 0, -17), 1],
]

func _create_turrets():
	# 玩家方防御塔数据
	for hp_spawn in HEALTH_PACK_SPAWNS:
		spawn_health_pack(hp_spawn[0], int(hp_spawn[1]))
	var player_turret_data = [
		# 发育路外塔、二塔、高地塔
		{"pos": Vector3(28,0,58), "type": "outer"},
		{"pos": Vector3(-15,0,56), "type": "inner"},
		{"pos": Vector3(-35,0,55), "type": "high"},
		# 中路外、二、高地
		{"pos": Vector3(-14,0,14), "type": "outer"},
		{"pos": Vector3(-27,0,27), "type": "inner"},
		{"pos": Vector3(-40,0,40), "type": "high"},
		# 对抗路外、二、高地
		{"pos": Vector3(-58,0,-28), "type": "outer"},
		{"pos": Vector3(-56,0,15), "type": "inner"},
		{"pos": Vector3(-55,0,35), "type": "high"},
		{"pos": Vector3(-53,0,53), "type": "crystal"},
	]
	for data in player_turret_data:
		var t = Turret.new()
		var turret_config = _get_turret_config(data["type"], Config.Team.PLAYER)
		turret_config["name"] = data["type"]
		t.setup(turret_config)
		t.tower_type = str(data["type"])   # 塔分级（小地图形状/HeroAI 高地判定都依赖）

		t.position = data["pos"]
		add_child(t)
		turrets.append(t)
		_add_turret_ring_pave(data["pos"], str(data["type"]), Config.Team.PLAYER)

	# 敌方防御塔（镜像位置 + 类型反转）
	# 敌方对抗路：对应玩家发育路
	# 敌方中路：对应玩家中路
	# 敌方发育路：对应玩家对抗路
	# 为了方便，可以直接硬编码敌方塔的位置和类型，确保对称。
	var enemy_turret_data = [
		{"pos": Vector3(-28,0,-58), "type": "outer"},
		{"pos": Vector3(--15,0,-56), "type": "inner"},
		{"pos": Vector3(--35,0,-55), "type": "high"},
		# 中路外、二、高地
		{"pos": Vector3(--14,0,-14), "type": "outer"},
		{"pos": Vector3(--27,0,-27), "type": "inner"},
		{"pos": Vector3(--40,0,-40), "type": "high"},
		# 对抗路外、二、高地
		{"pos": Vector3(--58,0,--28), "type": "outer"},
		{"pos": Vector3(--56,0,-15), "type": "inner"},
		{"pos": Vector3(--55,0,-35), "type": "high"},
		{"pos": Vector3(--53,0,-53), "type": "crystal"},]
	for data in enemy_turret_data:
		var t = Turret.new()
		var turret_config = _get_turret_config(data["type"], Config.Team.ENEMY)
		turret_config["name"] = data["type"]
		t.setup(turret_config)
		t.tower_type = str(data["type"])
		t.position = data["pos"]
		add_child(t)
		turrets.append(t)
		_add_turret_ring_pave(data["pos"], str(data["type"]), Config.Team.ENEMY)

# 防御塔底座的圆环状青砖：独立挂在 BattleManager 下（不随塔销毁而消失），
# 以塔心为圆心的同心环砖，中间留洞给塔基；塔被摧毁后这圈砖仍然留在原地。
func _add_turret_ring_pave(pos: Vector3, tier: String, team: int) -> void:
	var outer: float = 5.8 if tier == "crystal" else 4.7
	# 内圈留洞只到塔基中心（塔基台半径约 2.1），塔倒后残柱(半径≈1.2)也能盖住洞口
	var inner: float = 1.45 if tier == "crystal" else 1.15
	var hq_center := Vector3(-60, 0, 60) if team == Config.Team.PLAYER else Vector3(60, 0, -60)
	var on_high_ground: bool = Vector2(pos.x - hq_center.x, pos.z - hq_center.z).length() < 35.0
	# 顶面：高地砖面 0.177 / 分路路面之上 0.152，都只抬高 1~2mm，避免像旧圆盘那样浮起来露缝
	var top_y: float = 0.177 if on_high_ground else 0.152
	var pave := DecorMesh.turret_ring_pave(pos, inner, outer, top_y)
	pave.name = "TurretRingPave_%d_%d" % [int(round(pos.x)), int(round(pos.z))]
	pave.add_to_group("turret_paves")
	add_child(pave)

# 在 BattleManager.gd 中批量生成一组相同类型的野怪
# delay>0：开局只登记营地中心（弧形墙/导航用），野怪实体延后到 game_time>=delay 才物化（出生）
func _spawn_jungle_group(type: String, config: Dictionary, center: Vector3, count: int,
		delay: float = JUNGLE_FIRST_SPAWN):
	for i in range(count):
		jungle_camp_positions.append(center)
	if delay > 0.0:
		_pending_jungle_spawns.append({
			"type": type, "config": config.duplicate(),
			"center": center, "count": count, "at": delay,
		})
		return
	_materialize_jungle_group(type, config, center, count)

# 到点物化待命野怪组（普通营地30s / 空间之灵60s）
func _update_pending_jungle_spawns():
	for i in range(_pending_jungle_spawns.size() - 1, -1, -1):
		var entry: Dictionary = _pending_jungle_spawns[i]
		if game_time >= float(entry.get("at", 0.0)):
			_pending_jungle_spawns.remove_at(i)
			# 分帧物化：一次只物化一组，避免开局 30s 整片野区同帧生成造成卡顿
			_jungle_group_queue.append(entry)

func _drain_jungle_group_queue() -> void:
	if _jungle_group_queue.is_empty():
		return
	var entry: Dictionary = _jungle_group_queue.pop_front()
	_materialize_jungle_group(
		str(entry.get("type", "")), entry.get("config", {}),
		entry.get("center", Vector3.ZERO), int(entry.get("count", 1)))

# 实际生成一组野怪（怪物 + 活动范围环；同组每个实例在同一中心登记/加环，与历史一致）
func _materialize_jungle_group(type: String, config: Dictionary, center: Vector3, count: int):
	for i in range(count):
		var monster = JungleMonster.new()
		var cfg: Dictionary = config.duplicate()
		cfg["team"] = Config.Team.NEUTRAL
		cfg["name"] = type
		cfg["attack_speed"] = 0.5
		# 根据类型设置 buff 或其他特殊属性
		match type:
			"red_buff":
				monster.buff_type = "red"
				cfg["kill_gold"] = 84
				cfg["kill_exp"] = 56
			"blue_buff":
				monster.buff_type = "blue"
				cfg["kill_gold"] = 84
				cfg["kill_exp"] = 56
			"bird":
				cfg["kill_gold"] = 49
				cfg["kill_exp"] = 34
			"wolf":
				cfg["kill_gold"] = 38
				cfg["kill_exp"] = 28
			"lizard":
				cfg["kill_gold"] = 42
				cfg["kill_exp"] = 30
			"pig":
				cfg["kill_gold"] = 45
				cfg["kill_exp"] = 32
			"worm":
				cfg["kill_gold"] = 38
				cfg["kill_exp"] = 28
			"monkey":
				cfg["kill_gold"] = 42
				cfg["kill_exp"] = 30
			"spatial_spirit":
				cfg["kill_gold"] = 70
				cfg["kill_exp"] = 28
			"river_spirit":
				cfg["kill_gold"] = 64
				cfg["kill_exp"] = 30
			# 其他类型无特殊buff
		# 在中心点周围随机偏移，避免重叠
		var offset = Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
		monster.setup(cfg)
		# 入树前用本地坐标定位（父节点 BM 为场景根、恒等变换，本地==世界），
		# 避免未入树时取 global_position 触发 !is_inside_tree 报错
		monster.position = center + offset
		monster.body_radius = 1.5
		if type == "spatial_spirit":
			monster.respawn_time = 60.0   # 空间之灵：刷新间隔只有60秒
		add_child(monster)
		# 活动范围环：与史诗怪同一套（默认隐藏，只有玩家正在攻击它时显示，出圈变红）。
		# 旧逻辑在这里挂了一个常亮黄色 Torus，导致"全场野怪一直有黄圈"，已删除。
		_add_activity_ring(monster, maxf(monster.activity_radius, 4.0))
		jungle_monsters.append(monster)
		# 野怪不需要提供视野（或可提供较小视野），此处省略
func _create_jungle():
	# 红Buff
	_spawn_jungle_group("red_buff", {"max_health": 4200, "attack":190, "armor": 210, "magic_resist": 150}, Vector3(3,0,38), 1)
	_spawn_jungle_group("blue_buff", {"max_health": 4200, "attack":190, "armor": 210, "magic_resist": 150}, Vector3(-28,0,-5), 1)
	_spawn_jungle_group("red_buff", {"max_health": 4200, "attack":190, "armor": 210, "magic_resist": 150}, Vector3(-3,0,-38), 1)
	_spawn_jungle_group("blue_buff", {"max_health": 4200, "attack":190, "armor": 210, "magic_resist": 150}, Vector3(28,0,5), 1)

	# 山豪（三猪）

	_spawn_jungle_group("pig", {"max_health": 1600, "attack":120, "armor": 180, "magic_resist": 90}, Vector3(-6,0,26), 2)

	# 烈雉（红区鸟）
	_spawn_jungle_group("bird", {"max_health": 3927, "attack": 135, "armor": 210}, Vector3(25,0,40), 1)
	_spawn_jungle_group("worm", {"max_health": 4660, "attack": 166, "armor": 210}, Vector3(-40,0,-25), 1)
	# 暗影狼（双狼）
	_spawn_jungle_group("wolf", {"max_health": 2800, "attack": 155, "armor": 180}, Vector3(-35,0,15), 2)

	# 魔种蜥蜴
	_spawn_jungle_group("lizard", {"max_health": 3200, "attack": 125, "armor": 180}, Vector3(-41,0,5), 1)
	_spawn_jungle_group("monkey", {"max_health": 2800, "attack": 120, "armor": 180}, Vector3(-16,0,38), 1)

	# 河道之灵（边路）
	_spawn_jungle_group("spatial_spirit", {"max_health": 2500, "attack": 120, "armor": 100, "magic_resist": 100}, Vector3(-58,0,-58), 1, SPATIAL_FIRST_SPAWN)

	# 山豪（三猪）

	_spawn_jungle_group("pig", {"max_health": 1600, "attack":120, "armor": 180, "magic_resist": 90}, Vector3(6,0,-26), 2)

	# 烈雉（红区鸟）
	_spawn_jungle_group("bird", {"max_health": 3927, "attack": 135, "armor": 210}, Vector3(-25,0,-40), 1)
	_spawn_jungle_group("worm", {"max_health": 4660, "attack": 166, "armor": 210}, Vector3(--40,0,--25), 1)
	# 暗影狼（双狼）
	_spawn_jungle_group("wolf", {"max_health": 2800, "attack": 155, "armor": 180}, Vector3(--35,0,-15), 2)

	# 魔种蜥蜴
	_spawn_jungle_group("lizard", {"max_health": 3200, "attack": 125, "armor": 180}, Vector3(41,0,-5), 1)
	_spawn_jungle_group("monkey", {"max_health": 2800, "attack": 120, "armor": 180}, Vector3(--16,0,-38), 1)

	# 河道之灵（边路）
	_spawn_jungle_group("river_spirit", {"max_health": 2500, "attack": 120, "armor": 100, "magic_resist": 100}, Vector3(--58,0,--58), 1)
# 主宰/暴君龙坑中心（开局即生成围墙；阶段进化风暴龙王随机选坑）
var epic_pit_centers: Array = [Vector3(24, 0, 26), Vector3(-24, 0, -26)]
var tyrant_timer: float = 0.0
var dragon_timer: float = 0.0
var tyrant_alive: bool = false
var dragon_alive: bool = false
var dragon_count:int = 0
var _epic_spawn_voice_done := false   # 4:00 普通暴君/先知主宰首次降临播报（整个阶段0只报一次）

# ==================== 史诗龙阶段状态机 ====================
# 阶段0（4:00-9:30）普通暴君/先知主宰；阶段1（10:00-20:00）暗影暴君/暗影主宰；阶段2（20:00+）风暴龙王
var epic_phase: int = 0
var phase0_cleared: bool = false    # 9:30 已清除一阶段龙
var storm_timer: float = 0.0
var storm_alive: bool = false
# 原初羁绊（90秒）：击杀暴君的队伍对主宰伤害降低，反之亦然
var bond_team_tyrant: int = -1
var bond_team_dragon: int = -1
var bond_timer_tyrant: float = 0.0
var bond_timer_dragon: float = 0.0
# 主宰进化（9分钟公告）：0头部 1躯干 2手臂 3无
var dragon_evolution_part: int = -1
var evolution_decided: bool = false
# 主宰先锋波次参数
var dragon_minion_type: String = "dragon"
var dragon_minion_budget: int = 9
var dragon_minion_boost: bool = false
var vanguard_ever: bool = false   # 是否已有队伍击败过主宰/风暴龙（用于对局面板显示）

## 先锋波数名称（主宰先锋/暗影先锋/风暴先锋）
func vanguard_wave_name() -> String:
	if dragon_minion_type == "storm":
		return "风暴先锋"
	if dragon_minion_type == "shadow":
		return "暗影先锋"
	return "主宰先锋"

## 该队剩余未出动的先锋波数（budget 按"路次"计，一波 = 3 路）
func vanguard_waves_left(team: int) -> int:
	if dominant_buff_team != team:
		return 0
	var left := dragon_minion_budget - dragon_count
	if left <= 0:
		return 0
	return int(ceil(float(left) / 3.0))


func _get_epic_phase() -> int:
	if game_time >= 1200.0:
		return 2
	if game_time >= 600.0:
		return 1
	return 0


func _update_epic_monsters(delta):
	if _training_mode and not _training_jungle:
		return   # 训练营关闭野怪时不刷龙
	var ph := _get_epic_phase()
	if ph != epic_phase:
		_on_phase_transition(epic_phase, ph)
		epic_phase = ph

	# 9:30 一阶段龙消失（一次性，10:00 刷暗影版本）
	if game_time >= 570.0 and game_time < 600.0 and not phase0_cleared:
		phase0_cleared = true
		_clear_epic_monsters_phase0()

	# 原初羁绊计时
	if bond_timer_tyrant > 0:
		bond_timer_tyrant -= delta
		if bond_timer_tyrant <= 0:
			bond_team_tyrant = -1
	if bond_timer_dragon > 0:
		bond_timer_dragon -= delta
		if bond_timer_dragon <= 0:
			bond_team_dragon = -1

	# 9分钟主宰进化方向公告
	if game_time >= 540.0 and not evolution_decided:
		evolution_decided = true
		if dragon_alive:
			dragon_evolution_part = randi() % 4
			var part_name = ["头部", "躯干", "手臂", "无"][dragon_evolution_part]
			print("[EPIC] t=%.0f 主宰进化方向公告：%s" % [game_time, part_name])
			ui.show_kill_feed("先知主宰", Config.Team.NEUTRAL, "进化方向", part_name, Config.Team.NEUTRAL)

	match ph:
		0, 1:
			# 进化过渡期（9:30-10:00）不刷新
			if game_time >= 570.0 and game_time < 600.0:
				return
			# 暴君（普通/暗影）
			if not tyrant_alive:
				tyrant_timer -= delta
				if tyrant_timer <= 0:
					if ph == 0 and not _epic_spawn_voice_done:
						_epic_spawn_voice_done = true
						SfxManager.play_announce("epic_spawn", true)
					_spawn_epic("tyrant" if ph == 0 else "shadow_tyrant", ph, Vector3(24, 0, 26))
			# 主宰（先知/暗影）
			if not dragon_alive:
				dragon_timer -= delta
				if dragon_timer <= 0:
					_spawn_epic("dragon" if ph == 0 else "shadow_dragon", ph, Vector3(-24, 0, -26))
		2:
			# 风暴龙王：随机坑位
			if not storm_alive:
				storm_timer -= delta
				if storm_timer <= 0:
					_spawn_storm_dragon()


func _on_phase_transition(from_phase: int, to_phase: int):
	print("[EPIC] 阶段切换 %d → %d (t=%.0f)" % [from_phase, to_phase, game_time])
	if to_phase == 1:
		_clear_epic_monsters_phase0()
		tyrant_timer = 0.0
		dragon_timer = 0.0
	elif to_phase == 2:
		_clear_epic_monsters_phase1()
		storm_alive = false
		storm_timer = 0.0


# 清除一阶段龙（9:30 进化过渡）：确有存活才播「消失」音效（对应文件注记「如果还存在」）
func _clear_epic_monsters_phase0():
	if not tyrant_alive and not dragon_alive:
		return
	SfxManager.play_announce("epic_gone", true)
	if tyrant_alive:
		_despawn_epic(_find_epic_monster("tyrant"))
		tyrant_alive = false
	if dragon_alive:
		_despawn_epic(_find_epic_monster("dragon"))
		dragon_alive = false


# 清除二阶段龙（20:00 风暴龙王降临）
func _clear_epic_monsters_phase1():
	if tyrant_alive:
		_despawn_epic(_find_epic_monster("shadow_tyrant"))
		tyrant_alive = false
	if dragon_alive:
		_despawn_epic(_find_epic_monster("shadow_dragon"))
		dragon_alive = false


# 阶段进化移除（不走 die()，不发放奖励）
func _despawn_epic(monster: JungleMonster):
	if monster == null or not is_instance_valid(monster):
		return
	print("[EPIC] t=%.0f %s 消失（阶段进化）" % [game_time, monster.display_name])
	monster.visible = false
	monster.collision_layer = 0
	monster.queue_free()


func _find_epic_monster(display_name: String) -> JungleMonster:
	for entity in get_tree().get_nodes_in_group("jungle_monsters"):
		if entity is JungleMonster and entity.display_name == display_name and entity.health > 0:
			return entity
	return null


# 生成史诗龙（DOC 数值：HP 24700/×3/×7，AD 470/820/1460，双抗 183/360）
# 主宰/暴君/风暴龙王全部伤害统一降为原来的 0.4 倍（普攻与技能都按 attack 派生）
const EPIC_DAMAGE_MULT := 0.8   # 暴君/主宰/风暴龙王攻击力整体上调为原来的 2 倍
func _spawn_epic(display_name: String, phase: int, pos: Vector3):
	var stats := {
		"max_health": int(24700 * [1.0, 2.0, 4.0][phase]),
		"attack": int(round([470, 820, 1460][phase] * EPIC_DAMAGE_MULT)),
		"attack_speed": 0.2,   # DOC：爪击普攻CD1.5秒
		"attack_range": 650,    # 攻击距离6.5单位（修复：默认1.0×0.01≈0.01导致龙永远够不到目标）
		"armor": 360 if phase == 2 else 183,
		"magic_resist": 360 if phase == 2 else 183,
		"body_radius": 5.0,
	}
	var m := JungleMonster.new()
	var config := {"name": display_name, "team": Config.Team.NEUTRAL}
	config.merge(stats)
	m.setup(config)
	m.position = pos
	m.activity_radius = 8
	m.search_radius = 12
	m.monster_phase = phase
	_add_activity_ring(m, 8.0)
	add_child(m)
	if display_name in ["tyrant", "shadow_tyrant"]:
		tyrant_alive = true
	elif display_name in ["dragon", "shadow_dragon"]:
		dragon_alive = true
	print("[EPIC] t=%.0f 刷新 %s HP=%d 攻=%d 双抗=%d" % [game_time, display_name, stats["max_health"], stats["attack"], stats["armor"]])


# 固定活动范围环（挂在怪物子节点，随怪物销毁）
# 默认隐藏：只有玩家英雄正在攻击该野怪时，JungleMonster 才会把它显出来
# 位置固定回营地圆心（不随怪移动）；怪在圈内=白色，走出圈外=红色（见 JungleMonster._update_activity_ring）
func _add_activity_ring(monster: JungleMonster, radius: float):
	# 贴地活动范围圈：与地面起伏贴合、柔化边缘 + 磨损斑驳（原来是一条纯色 Torus）
	var ring := MeshFactory.create_ground_ring(radius, Color(1.0, 1.0, 1.0, 0.42), 0.0)
	ring.name = "ActivityRing"
	ring.top_level = true   # 世界坐标固定：不跟随怪物移动/转向，圆心固定在营地
	ring.visible = false
	monster.add_child(ring)
	monster.activity_ring = ring
	monster.activity_ring_radius = radius


# 风暴龙王：20:00 降临随机龙坑
func _spawn_storm_dragon():
	storm_alive = true
	var pit := Vector3(24, 0, 26) if randi() % 2 == 0 else Vector3(-24, 0, -26)
	_spawn_epic("storm_dragon", 2, pit)
	ui.show_kill_feed("风暴龙王", Config.Team.NEUTRAL, "降临", "随机龙坑", Config.Team.NEUTRAL)


# 史诗怪物统一死亡分发器（JungleMonster.die 调用）
func on_epic_died(monster: JungleMonster, killer: Hero):
	if monster == null:
		return
	var mname := monster.display_name
	print("[EPIC] t=%.0f %s 被击杀 killer=%s" % [game_time, mname, killer.display_name if killer else "null"])
	if killer != null:
		last_dragon_kill_team = int(killer.team)
		last_dragon_kill_time = game_time

	# 存活标记 + 4分钟刷新
	match mname:
		"tyrant", "shadow_tyrant":
			tyrant_alive = false
			tyrant_timer = 240.0
		"dragon", "shadow_dragon":
			dragon_alive = false
			dragon_timer = 240.0
		"storm_dragon":
			storm_alive = false
			storm_timer = 240.0

	var name_cn := {"tyrant": "暴君", "dragon": "先知主宰", "shadow_tyrant": "暗影暴君", "shadow_dragon": "暗影主宰", "storm_dragon": "风暴龙王"}
	var rewards := {"tyrant": [140, 120], "dragon": [140, 160], "shadow_tyrant": [220, 240], "shadow_dragon": [220, 280], "storm_dragon": [300, 320]}
	if killer:
		var r: Array = rewards.get(mname, [0, 0])
		_grant_team_reward(killer.team, r[0], r[1])
		# 击败主宰/暴君助攻：龙坑 12m 内同队英雄（只列英雄，不列小兵）
		var e_assists: Array = []
		for e in get_tree().get_nodes_in_group("heroes"):
			if e is Hero and e != killer and e.team == killer.team and e.health > 0.0 \
					and e.global_position.distance_to(monster.global_position) < 12.0:
				e_assists.append({"name": e.display_name, "team": e.team})
		ui.show_kill_feed(killer.display_name, killer.team, "已击败", name_cn[mname], Config.Team.NEUTRAL, e_assists)
		match mname:
			"tyrant", "shadow_tyrant":
				# 击杀暴君 → 羁绊：对主宰伤害降低
				bond_team_dragon = killer.team
				bond_timer_dragon = 90.0
				if mname == "tyrant":
					_apply_junlin_buff(killer.team)
				else:
					_apply_shadow_junlin_buff(killer.team)
			"dragon", "shadow_dragon":
				# 击杀主宰 → 羁绊：对暴君伤害降低 + 主宰先锋波次
				bond_team_tyrant = killer.team
				bond_timer_tyrant = 90.0
				dominant_buff_team = killer.team
				dragon_count = 0
				if mname == "dragon":
					dragon_minion_type = "dragon"
					dragon_minion_budget = 6   # 先知主宰：2波×3路
					dragon_minion_boost = dragon_evolution_part >= 0 and dragon_evolution_part <= 2
					vanguard_ever = true
				else:
					dragon_minion_type = "shadow"
					dragon_minion_budget = 9   # 暗影主宰：3波×3路
					dragon_minion_boost = false
					_spawn_shadow_dragon_vanguard(killer)
			"storm_dragon":
				dominant_buff_team = killer.team
				dragon_count = 0
				dragon_minion_type = "storm"
				vanguard_ever = true
				dragon_minion_budget = 9
				dragon_minion_boost = false
				_apply_storm_buff(killer.team)
	# 关键抢夺独立播报命中则不叠普通击杀音；否则播 主宰/暴君被击败
	if killer:
		if not _maybe_epic_steal(monster, killer):
			SfxManager.play_announce("epic_slain", true)


# 返回对指定龙有羁绊的队伍（击杀另一只龙的队伍），无则 -1
func get_bonded_team(monster: GameEntity) -> int:
	if monster is JungleMonster:
		if monster.display_name in ["dragon", "shadow_dragon"]:
			return bond_team_dragon if bond_timer_dragon > 0 else -1
		if monster.display_name in ["tyrant", "shadow_tyrant"]:
			return bond_team_tyrant if bond_timer_tyrant > 0 else -1
	return -1


# 暗影先锋：选择（敌方塔数-己方塔数）最大的一路（平局中路优先），清空该路敌方兵线并在己方基地召唤巨型暗影先锋（暗影之径60秒，与先锋存活无关）
func _spawn_shadow_dragon_vanguard(killer: Hero):
	if killer == null:
		return
	var team := killer.team
	# 暗影之径：优先选择「敌方小兵距离己方水晶最近」的那一路；
	# 没有存活敌方小兵时回退到原塔数差逻辑（平局中路优先）。
	var best_lane := 1
	var own_crystal: Turret = null
	for _ct in turrets:
		if not is_instance_valid(_ct):
			continue
		if _ct is Turret and _ct.team == team and str(_ct.display_name) == "crystal" and _ct.health > 0.0:
			own_crystal = _ct
			break
	var _nearest_enemy_dist := INF
	var _nearest_lane := -1
	if own_crystal != null:
		for _em in get_tree().get_nodes_in_group("minions"):
			if not is_instance_valid(_em) or not (_em is Minion) or _em.team == team or _em.health <= 0.0:
				continue
			var _d: float = _em.global_position.distance_to(own_crystal.global_position)
			if _d < _nearest_enemy_dist:
				_nearest_enemy_dist = _d
				_nearest_lane = _lane_of_position(_em.global_position)
	if _nearest_lane >= 0:
		best_lane = _nearest_lane
	else:
		# 没有敌方小兵：沿用（敌方防御塔数量 - 己方防御塔数量）最大的一路
		var best_diff := -999
		for ln in [1, 0, 2]:
			var enemy_towers := 0
			var ally_towers := 0
			for t in turrets:
				if not is_instance_valid(t) or t.health <= 0: continue
				if t.display_name == "crystal": continue   # 水晶不计入分路塔数
				if not _is_on_lane(t.global_position, ln): continue
				if t.team == team: ally_towers += 1
				else: enemy_towers += 1
			var diff = enemy_towers - ally_towers
			if diff > best_diff:
				best_diff = diff
				best_lane = ln
	# 清空该路敌方兵线（走标准死亡流程正常发金币经验）
	var enemy_team = Config.Team.ENEMY if team == Config.Team.PLAYER else Config.Team.PLAYER
	var cleared_count := 0
	for m in get_tree().get_nodes_in_group("minions"):
		if m is Minion and m.team == enemy_team and m.line == best_lane and m.health > 0:
			m.take_damage(m.max_health * 5, killer, false, -55, 1.0)
			cleared_count += 1
	var lane_name = ["发育路", "中路", "对抗路"][best_lane]
	ui.show_kill_feed("暗影先锋", team, "扫清%s兵线！" % lane_name)
	print("[EPIC] t=%.0f 暗影先锋清空%s路兵线：%d只" % [game_time, lane_name, cleared_count])
	# 在该路己方高地塔生成巨型暗影先锋（分路起点，立即可见）
	var waypoints_list = [player_waypoints_farm, player_waypoints_mid, player_waypoints_clash] if team == Config.Team.PLAYER else [enemy_waypoints_farm, enemy_waypoints_mid, enemy_waypoints_clash]
	var wp: Array = waypoints_list[best_lane]
	spawn_single_minion("shadow_dragon", team, wp[0], wp, best_lane)
	# 暗影先锋无寿命上限（自然死亡为止）；暗影之径固定60秒，与先锋存活无关
	if not shadow_path_timers.has(team):
		shadow_path_timers[team] = {}
	shadow_path_timers[team][best_lane] = 60.0
	_set_shadow_path_visual(best_lane, true)
	ui.show_kill_feed("暗影先锋", team, "出动！")
	print("[EPIC] t=%.0f 暗影先锋出动：队伍=%d 分路=%d" % [game_time, team, best_lane])


# 君临：全队命中触发闪电链（英雄10+10×等级/非英雄30+30×等级法术伤害，3s内置CD，90秒）
func _apply_junlin_buff(team: int):
	print("[BUFF] t=%.0f 君临 施加于队伍 %d" % [game_time, team])
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team:
			entity.tyrant_lightning_active = true
			entity.tyrant_lightning_shadow = false
			entity.tyrant_lightning_timer = 90.0
			entity.tyrant_lightning_cd = 0.0


# 暗影君临：闪电链翻倍（英雄30+30×等级/非英雄50+50×等级）+ 全队+10%移速 +5%脱战移速，90秒
func _apply_shadow_junlin_buff(team: int):
	print("[BUFF] t=%.0f 暗影君临 施加于队伍 %d" % [game_time, team])
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team:
			entity.tyrant_lightning_active = true
			entity.tyrant_lightning_shadow = true
			entity.tyrant_lightning_timer = 90.0
			entity.tyrant_lightning_cd = 0.0
			# +10%移速：快照进通用buff（到期由君临计时块重算清除）
			entity.active_buffs.append({"timer": 90.0, "bonus_move_speed": entity.base_move_speed * 0.1})
			entity._recalculate_attributes()


# 风暴觉醒：一次性护盾（50%最大生命）+ 每秒对8单位内敌方4%最大生命真伤，90秒
func _apply_storm_buff(team: int):
	print("[BUFF] t=%.0f 风暴觉醒 施加于队伍 %d" % [game_time, team])
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team:
			entity.storm_aura_active = true
			entity.storm_aura_timer = 90.0
			entity.storm_aura_tick = 0.0
			entity.storm_shield_amount = entity.max_health * 0.5
			entity.storm_shield_timer = 90.0
			entity.shield_remaining = max(entity.shield_remaining, entity.storm_shield_amount)
			# 风暴觉醒光环视觉（8单位紫色圆环，跟随英雄移动）
			if entity.storm_aura_ring == null:
				var ring = MeshFactory.create_torus_ring(7.7, 8.0, Color(0.8, 0.4, 1.0), true, 0.45, true)
				ring.position = Vector3(0, 0.05, 0)
				entity.add_child(ring)
				entity.storm_aura_ring = ring
# 击杀英雄的金币计算（包含连续死亡递减、一血、等级、原初积分等）

func get_kill_gold(killer: Hero, victim: Hero) -> int:
	var base_gold = 150
	if victim.level >= 7:       base_gold = 200
	elif victim.level >= 4:     base_gold = 175

	# 连续死亡递减：索引=死者本局此前的死亡次数。0=首次死亡必须拿满额
	#（原表首项 0 且无条件覆盖 base_gold，导致“首次死亡击杀奖励=0”）
	var death_penalty = [0, 200, 180, 150, 120, 100, 60, 40, 20]
	var index = clampi(victim.continuous_deaths, 0, death_penalty.size() - 1)
	if index > 0:
		base_gold = death_penalty[index]

	# 一血
	if not first_blood_occurred:
		base_gold += 75
		first_blood_occurred = true

	# 原初积分加成
	var primitive_bonus = [0, 200, 250, 290, 325, 455, 550]
	var lv = min(victim.primitive_score / 100, primitive_bonus.size() - 1)  # 假设100积分为一级
	base_gold = max(base_gold, primitive_bonus[lv])

	return base_gold

# 助攻金币
func get_assist_gold(killer_gold: int, assist_count: int) -> int:
	if assist_count <= 0: return 0
	return int(killer_gold * 0.5 / assist_count)

# 激励金币包（贡献度最高者额外30%）
func get_motivation_gold(killer_gold: int) -> int:
	return int(killer_gold * 0.3)

# 多人吃线经济分配
func get_lane_gold(base_gold: int, player_count: int) -> int:
	var ratios = [1.0, 0.8, 0.55, 0.43, 0.37]
	var ratio = ratios[min(player_count - 1, ratios.size() - 1)]
	return int(base_gold * ratio)

# 推塔全队收益
func award_tower_gold(team: int, tower_type: String):
	var gold = 75 if tower_type == "outer" else (97 if tower_type == "inner" else 120)
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team:
			entity.add_gold(gold)

# 原初积分变化
func modify_primitive_score(hero: Hero, amount: int):
	hero.primitive_score = clamp(hero.primitive_score + amount, 0, 600)

# 英雄死亡时的完整处理
func on_hero_killed(killer: Hero, victim: Hero):
	if debug_kill_rewards:
		var st = get_stack()
		var chain = ""
		for k in range(min(st.size(), 5)):
			chain += "%s:%d " % [st[k].get("function", "?"), st[k].get("line", 0)]
		print("[击杀奖励] t=%.1f 杀手=%s 死者=%s 死者连续死亡=%d 调用链: %s" % [game_time, killer.display_name, victim.display_name, victim.continuous_deaths, chain])
	# 一血判定（金币加成在 get_kill_gold 内翻 75；首次击杀补“第一滴血”战报/语音）
	var is_first_blood := not first_blood_occurred
	# 击杀者金币
	var kill_gold = get_kill_gold(killer, victim)
	killer.add_gold(kill_gold)
	if is_first_blood and ui:
		ui.show_kill_feed(killer.display_name, killer.team, "第一滴血", victim.display_name, victim.team)
	NetSession.push_net_gold(victim.global_position, kill_gold, NetSession.is_assigned(killer))
	if ui: ui.show_gold_popup(victim.global_position, kill_gold, killer == hero)
	var exp = 80
	if victim.level > killer.level: exp += min((victim.level - killer.level) * 10, 30)
	elif victim.level < killer.level: exp -= min((killer.level - victim.level) * 10, 30)
	exp = max(exp, 20)
	# 连杀递减
	if hero.consecutive_kills >= 4: exp = int(exp * 0.4)
	elif hero.consecutive_kills : exp = int(exp * 0.6)
	elif hero.consecutive_kills : exp = int(exp * 0.8)
	spawn_exp_orb(victim.global_position, killer, exp)
	NetSession.push_net_exp(victim.global_position, killer, exp)
	# 助攻统计（遍历附近队友）
	var assists = []
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == killer.team and entity != killer:
			if entity.global_position.distance_to(victim.global_position) < 12.0:
				assists.append(entity)
	var assist_gold = get_assist_gold(kill_gold, assists.size())
	for hero in assists:
		hero.assists +=1
		hero.add_gold(assist_gold)
		NetSession.push_net_gold(hero.global_position, assist_gold, NetSession.is_assigned(hero))
		if ui: ui.show_gold_popup(hero.global_position, assist_gold)

	# 激励金币包（简化处理：给伤害最高的助攻者）
	# 这里需要外部记录伤害贡献，暂时省略，可后续添加

	# 原初积分更新
	modify_primitive_score(killer, 100)
	modify_primitive_score(victim, -50)

	# 连续死亡与连杀重置
	victim.continuous_deaths += 1
	killer.continuous_deaths = 0
	_maybe_nice_kill(killer, victim)

# —— 秀操作/团灭类播报：host 权威触发，带同键冷却；SfxManager 本地播 + 广播到接管客户端 ——
var _special_announce_last: Dictionary = {}

func _special_ready(key: String, gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_special_announce_last.get(key, -999.0)) < gap:
		return false
	_special_announce_last[key] = now
	return true

func trigger_special_announce(key: String, gap := 6.0) -> void:
	if not _special_ready(key, gap):
		return
	SfxManager.play_announce(key, true)

# 团灭判定：victim 阵亡后其队伍是否已全员阵亡/复活中（连同一瞬多笔死亡也只在整队全灭时触发一次）
func check_team_wipe(victim: Hero) -> void:
	if victim == null:
		return
	var all_down := true
	for e in get_tree().get_nodes_in_group("heroes"):
		var h := e as Hero
		if h == null or h.team != victim.team:
			continue
		if not h.is_dead and not h.is_reviving and h.health > 0.0:
			all_down = false
			break
	if not all_down:
		return
	if victim.team == Config.player_team:
		trigger_special_announce("wiped", 3.0)
	else:
		trigger_special_announce("perfect_fight", 3.0)

# 漂亮的击杀：我方越塔强杀 / 敌方越我方塔被反杀 / 远距离击杀（百步穿杨）
func _maybe_nice_kill(killer: Hero, victim: Hero) -> void:
	if killer == null or killer.team != Config.player_team:
		return
	var dive := hero_under_enemy_tower(killer)
	var defend := false
	var snipe := false
	if victim:
		defend = hero_under_enemy_tower(victim)
		snipe = killer.global_position.distance_to(victim.global_position) >= 10.0
	if dive or defend or snipe:
		trigger_special_announce("nice_kill", 6.0)

# 关键抢夺：史诗怪被输出占优队伍之外的队伍击杀（抢主宰/暴君；含敌方抢我方）。命中返回 true 让
# 调用方不再叠播普通「主宰暴君被击败」。
func _maybe_epic_steal(monster: JungleMonster, killer: Hero) -> bool:
	if monster == null or killer == null:
		return false
	var owner := -1
	var max_dmg := 0.0
	for t in monster.dmg_by_team:
		var d := float(monster.dmg_by_team[t])
		if d > max_dmg:
			max_dmg = d
			owner = int(t)
	if owner < 0 or owner == killer.team:
		return false
	# 对面需实质投入（≥其 8% 血量，800 保底），否则不算"抢"
	var threshold := maxf(800.0, float(monster.max_health) * 0.08)
	if max_dmg < threshold:
		return false
	if killer.team == Config.player_team:
		trigger_special_announce("steal", 4.0)
	else:
		trigger_special_announce("e_steal", 4.0)
	return true

func apply_item_effects(hero: Hero, base_gold: int) -> int:
	var gold = base_gold
	# 辅助装游击
	if hero.equipment_slots.has("ancient_coin"):
		gold = int(gold * 0.3)
	# 打野刀游击
	if hero.equipment_slots.has("hunter_knife"):  # 弃鳞短刃
		if game_time < 240.0 and _has_nearby_ally(hero):
			gold = int(gold * 0.5)
	return gold
# 实体死亡时的全局处理（例如野怪、小兵）
func distribute_experience(source: GameEntity, killer: GameEntity = null):
	var base_exp = source.kill_exp

	if base_exp <= 0: return

	# 小兵经验随时间成长（0-10分钟每分钟+7.5%，10分钟后上限140%）
	if source is Minion:
		var growth = min(game_time / 60.0 * 0.075, 0.4)
		base_exp = int(base_exp * (1.0 + growth))
	# 野怪经验10分钟后×2.2
	elif source is JungleMonster:
		if game_time >= 600: base_exp = int(base_exp * 2.2)

	# 野怪奖励只给击杀者同队；普通单位沿用原“排除来源队伍=奖励对方”的逻辑。
	var same_team := false
	var reward_team = source.team
	if source is JungleMonster:
		if not (killer is Hero):
			return
		reward_team = killer.team
		same_team = true
	var heroes = _get_nearby_heroes(source.global_position, 12.0, reward_team, same_team)
	if heroes.is_empty(): return

	# 多人分配
	var count = heroes.size()
	var ratio = 1.0
	match count:
		2: ratio = 0.8
		3: ratio = 0.55
		4: ratio = 0.43
		_: ratio = 0.37 if count >= 5 else 1.0

	for h in heroes:
		var exp_gain = int(base_exp * ratio)
			# 打野刀：经验+25% + 叠层
		if source is JungleMonster:
			for jid in h.equipment_slots:
				var jitem = ItemDatabase.get_item(jid)
				if jitem.get("class", "") == "jungle":
					exp_gain = int(exp_gain * 1.25)
					if h.jungle_stacks < (25 if jitem.get("tier",1) >= 3 else 15 if jitem.get("tier",1) >= 2 else 0): h.jungle_stacks += 1
					break
		if h == killer:
			exp_gain*=1.5
		# 辅助装：不参与分配，单独拿30%（需经济最低+身边有队友）
		if _has_support_item(h) and _is_lowest_gold(h) and _has_nearby_ally(h):
			exp_gain = int(base_exp * 0.3)   # 队友拿100%，辅助额外拿30%
		# 打野刀前4分钟蹭线
		elif _has_jungle_item(h) and game_time < 240 and source is Minion:
			if count > 1:
				# 队友拿全额，打野单独拿50%
				if h != killer:
					continue   # 队友正常分配，打野不在heroes里？
				else:
					exp_gain = int(base_exp * 0.5)
		# 追赶机制
		var avg_level = _get_average_level()
		if h.level < avg_level:
			var diff = avg_level - h.level
			exp_gain = int(exp_gain * (1.0 + min(diff * 0.1, 0.5)))
		spawn_exp_orb(source.global_position, h, exp_gain)
		NetSession.push_net_exp(source.global_position, h, exp_gain)
func distribute_gold(source:GameEntity, killer: GameEntity):
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not bm: return

	# 基础金币
	var base_gold = source.kill_gold

	if base_gold <= 0: return
	# 0-10分钟每分钟+7.5%，之后封顶1.5倍
	var growth = min(bm.game_time / 60.0 * 0.075, 0.5)
	base_gold = int(base_gold * (1.0 + growth))

	# 自然金币（附近己方英雄平分？不，小兵金币只给补刀者+附近队友）

	var same_team := false
	var reward_team = source.team
	if source is JungleMonster:
		if not (killer is Hero):
			return
		reward_team = killer.team
		same_team = true
	var nearby_heroes = _get_nearby_heroes(source.global_position, 12.0, reward_team, same_team)

	for hero in nearby_heroes:
		var lane_gold = get_lane_gold(base_gold, nearby_heroes.size())
			# 打野刀：金币+20%(2级以上)
		if source is JungleMonster:
			for jid in hero.equipment_slots:
				var jitem = ItemDatabase.get_item(jid)
				if jitem.get("class", "") == "jungle" and jitem.get("tier", 1) >= 2: lane_gold = int(lane_gold * 1.2); break
			# 太乙被动: 8米内友方击杀额外金币
			if source is Minion or source is JungleMonster:
				var taiyi_hero = null
				for h2 in get_tree().get_nodes_in_group("heroes"):
					if h2 is Hero and h2.display_name == "太乙真人" and h2.team == hero.team:
						if h2.global_position.distance_to(source.global_position) <= 8.0: taiyi_hero = h2; break
				if taiyi_hero: lane_gold = int(lane_gold * (1.093 + taiyi_hero.level * 0.007))
		if source is JungleMonster:
			for jid in hero.equipment_slots:
				var jitem = ItemDatabase.get_item(jid)
				if jitem.get("class", "") == "jungle" and jitem.get("tier", 1) >= 2: lane_gold = int(lane_gold * 1.2); break
			# 太乙被动: 8米内友方击杀额外金币
			if source is Minion or source is JungleMonster:
				var taiyi_hero = null
				for h2 in get_tree().get_nodes_in_group("heroes"):
					if h2 is Hero and h2.display_name == "太乙真人" and h2.team == hero.team:
						if h2.global_position.distance_to(source.global_position) <= 8.0: taiyi_hero = h2; break
				if taiyi_hero: lane_gold = int(lane_gold * (1.093 + taiyi_hero.level * 0.007))

		# 辅助装、打野刀效果在此处叠加
		lane_gold = apply_item_effects(hero, lane_gold)

		if hero == killer:
			lane_gold*=1.5
		hero.add_gold(lane_gold)
		# 赛后统计：野怪金币
		if source is JungleMonster:
			hero.jungle_gold += lane_gold
		# #44 金币事件只广播接管方英雄的所得（host 窗口侧另按 bm.hero 弹，两者互不依赖）
		if NetSession.is_assigned(hero):
			NetSession.push_net_gold(hero.global_position, lane_gold, hero == killer)
		if bm.ui and hero == bm.hero:
			bm.ui.show_gold_popup(hero.global_position, lane_gold, hero == killer,
				hero == killer and source is Minion)
func _get_nearby_heroes(center: Vector3, radius: float, team, same_team: bool = false) -> Array:
	var result = []
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.health > 0:
			if entity.global_position.distance_to(center) <= radius:
				if same_team and entity.team != team:
					continue
				if not same_team and entity.team == team:
					continue
				result.append(entity)
	return result

func _has_nearby_ally(hero: Hero) -> bool:
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity != hero and entity.team == hero.team and entity.health > 0:
			if hero.global_position.distance_to(entity.global_position) < 12.0:
				return true
	return false

func _has_support_item(hero: Hero) -> bool:
	return hero.equipment_slots.has("ancient_coin") or hero.equipment_slots.has("wind_blessing") or hero.equipment_slots.has("guardian_glory") or hero.equipment_slots.has("extreme_shadow") or hero.equipment_slots.has("redeemer_guard") or hero.equipment_slots.has("star_spring_guard") or hero.equipment_slots.has("galloping_wolf_guard") or hero.equipment_slots.has("revealing_light_guard") or hero.equipment_slots.has("redeemer_shadow") or hero.equipment_slots.has("star_spring_shadow") or hero.equipment_slots.has("galloping_wolf_shadow") or hero.equipment_slots.has("revealing_light_shadow")

func _has_jungle_item(hero: Hero) -> bool:
	return hero.equipment_slots.has("hunter_knife") or hero.equipment_slots.has("upgraded_hunter")  # 对应你的装备ID

func _is_lowest_gold(hero: Hero) -> bool:
	for h in get_tree().get_nodes_in_group("heroes"):
		if h is Hero and h.team == hero.team and h.gold < hero.gold:
			return false
	return true

func _get_average_level() -> float:
	var total = 0.0
	var count = 0
	for h in get_tree().get_nodes_in_group("heroes"):
		if h is Hero:
			total += h.level
			count += 1
	return total / max(count, 1)

func _grant_team_reward(team: int, gold: int, exp: int = 0):
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team:
			entity.add_gold(gold)
			if exp > 0:
				entity.add_exp(exp)

# 全队平分金币：总额在存活队友间均分（5人全活则每人 1/5）
func grant_team_split_reward(team: int, amount: int):
	var members: Array = []
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == team and entity.health > 0:
			members.append(entity)
	if members.is_empty():
		return
	var base := amount / members.size()
	var rem := amount % members.size()
	for i in range(members.size()):
		var h: Hero = members[i]
		h.add_gold(base + (1 if i < rem else 0))

# 空间之灵击杀 → 开启传送阵（持续到10分钟；已有传送阵则不叠加）
func open_spatial_teleport(pos: Vector3):
	if game_time >= 600.0:
		return
	for zone in get_tree().get_nodes_in_group("teleport_zones"):
		if is_instance_valid(zone) and zone.global_position.distance_to(pos) < 6.0:
			return
	var zone = TeleportZone.new()
	zone.duration = 600.0 - game_time
	zone.global_position = pos
	add_child(zone)
var dominant_buff_team: int = -1

func _generate_lane_edge_walls():
	var step = 2.0
	# ---- 地图最外圈边缘墙：保持外周城墙样式（2m 段、端面平齐）----
	var z = -37.0
	while z <= 37.0:
		_add_wall(Vector3(-63, 0, z), Vector3(1, 0, 0), false, false, true)
		_add_wall(Vector3(63, 0, z), Vector3(-1, 0, 0), false, false, true)
		z += step
	var x = -37.0
	while x <= 37.0:
		_add_wall(Vector3(x, 0, 63), Vector3(0, 0, 1), false, false, true)
		_add_wall(Vector3(x, 0, -63), Vector3(0, 0, 1), false, false, true)
		x += step
	# ---- 分路内缘墙（非外周）：与野区墙同一标准，实段=连续墙链 + 两端小柱 ----
	_lane_inner_wall(-47.0, "z")
	_lane_inner_wall(47.0, "z")
	_lane_inner_wall(47.0, "x")
	_lane_inner_wall(-47.0, "x")
	# ---- 中路两侧墙：同样按连续墙链重建（三路入口处断开）----
	_mid_lane_inner_walls(Vector3(-30, 0, 30), 0.707, -0.707, Vector3(-60, 0, 60))
	_mid_lane_inner_walls(Vector3(30, 0, -30), -0.707, 0.707, Vector3(60, 0, -60))

## 分路内缘：沿轴每 2m 采样，野区入口缺口处断开，实段连成连续墙链（两端小柱）
func _lane_inner_wall(fixed: float, axis: String) -> void:
	var step := 2.0
	var run: Array = []
	var v := -37.0
	while v <= 37.0:
		var t := v + 40.0
		var in_gap := (t >= 22.0 and t <= 31.0) or (t >= 49.0 and t <= 58.0)
		if in_gap:
			_flush_wall_run(run); run = []
		else:
			run.append(Vector3(fixed, 0.0, v) if axis == "z" else Vector3(v, 0.0, fixed))
		v += step
	_flush_wall_run(run)

## 中路两侧墙：沿路方向每 2m 采样，入口缺口/高地内侧断开，实段连成连续墙链
func _mid_lane_inner_walls(center: Vector3, fwd_x: float, fwd_z: float, base: Vector3) -> void:
	var right_x := 0.707
	var right_z := 0.707
	var step := 2.0
	for side in [-1.0, 1.0]:
		var run: Array = []
		var t := -36.0
		while t <= 36.0:
			var lane_t := t + 40.0
			var in_gap := (lane_t >= 22.0 and lane_t <= 31.0) or (lane_t >= 49.0 and lane_t <= 58.0)
			var pos := Vector3(center.x + side * 8.0 * right_x + t * fwd_x, 0.0,
				center.z + side * 8.0 * right_z + t * fwd_z)
			if in_gap or pos.distance_to(base) < 38.0:
				_flush_wall_run(run); run = []
			else:
				run.append(pos)
			t += step
		_flush_wall_run(run)

# 地图外周城墙：沿 |x|=63 / |z|=63 整圈围合（已有分路外墙的中段不重复放），
# 野区两个外角圆弧倒角；泉水半径内让开，避免城墙插进喷泉池

func _generate_outer_walls() -> void:
	var edge: float = 63.0
	var step: float = 2.0
	var t: float = -edge
	while t <= edge:
		# 分路外墙已覆盖 |t| ≤ 37 的中段，这里只补缺
		if absf(t) > 37.0:
			_add_outer_wall(Vector3(-edge, 0.0, t), Vector3(1, 0, 0))
			_add_outer_wall(Vector3(edge, 0.0, t), Vector3(-1, 0, 0))
			_add_outer_wall(Vector3(t, 0.0, -edge), Vector3(0, 0, 1))
			_add_outer_wall(Vector3(t, 0.0, edge), Vector3(0, 0, -1))
		t += step
	# 野区两个外角 ((-63,-63) / (63,63)) 圆弧倒角：半径 8.5，与两条边线相切
	for corner in [Vector2(-1, -1), Vector2(1, 1)]:
		var cx: float = float(corner.x) * (edge - 8.5)
		var cz: float = float(corner.y) * (edge - 8.5)
		var base_ang: float = 180.0 if corner.x < 0.0 else 0.0
		for i in range(10):
			var a: float = deg_to_rad(base_ang + 10.0 * float(i))
			_add_outer_wall(Vector3(cx + cos(a) * 8.5, 0.0, cz + sin(a) * 8.5), Vector3(cos(a), 0.0, sin(a)), 2.0, false)

	# 泉水外周城墙（基地角）：以泉水为圆心半径 4.35 的 270° 石环（外周墙同款模型），
	# 朝地图内的 90° 留出入口；石环同时把外周城墙在基地角上的缺口补齐
	for corner in [Vector2(-62, 62), Vector2(62, -62)]:
		var c: Vector2 = corner
		var inward_ang: float = 315.0 if c.x < 0.0 else 135.0
		for i in range(30):
			var ang: float = 12.0 * float(i)
			var rel: float = fposmod(ang - inward_ang + 180.0, 360.0) - 180.0
			if absf(rel) <= 45.0:
				continue
			var a: float = deg_to_rad(ang)
			_add_wall(Vector3(c.x + cos(a) * 4.35, 0.0, c.y + sin(a) * 4.35), Vector3(cos(a), 0.0, sin(a)), true, false, true, 2.0)
		# 石环与地图边界外墙的接缝补墙，外周不留缝
		if c.x < 0.0:
			_add_wall(Vector3(-63, 0, 57.5), Vector3(1, 0, 0), true, false, true, 2.0)
			_add_wall(Vector3(-57.5, 0, 63), Vector3(0, 0, -1), true, false, true, 2.0)
		else:
			_add_wall(Vector3(63, 0, -57.5), Vector3(-1, 0, 0), true, false, true, 2.0)
			_add_wall(Vector3(57.5, 0, -63), Vector3(0, 0, 1), true, false, true, 2.0)

## 外周城墙落点：避开泉水（半径 5.25 的池子 + 边缘），其余按 force 放置
func _add_outer_wall(pos: Vector3, facing: Vector3, len: float = 2.0, outer_style: bool = true) -> void:
	var blue := Vector2(-62.0, 62.0)
	var red := Vector2(62.0, -62.0)
	var p := Vector2(pos.x, pos.z)
	if p.distance_to(blue) < 5.3 or p.distance_to(red) < 5.3:
		return
	_add_wall(pos, facing, true, false, outer_style, len)

func _generate_high_ground_walls():
	# 高地扇形弧线（非外周）：与野区墙同一标准 —— 连续弧墙链，三路入口处断开，链端加小柱
	for spec in [
		{"c": Vector3(-60, 0, 60), "a0": -90.0, "a1": 0.0,
			"gaps": [[-90.0, -69.0], [-58.0, -32.0], [-21.0, 0.0]]},
		{"c": Vector3(60, 0, -60), "a0": 90.0, "a1": 180.0,
			"gaps": [[90.0, 111.0], [122.0, 148.0], [159.0, 180.0]]},
	]:
		var c: Vector3 = spec.c
		var run: Array = []
		var angle: float = spec.a0
		while angle <= spec.a1:
			var in_gap := false
			for g in spec.gaps:
				if angle >= float(g[0]) and angle <= float(g[1]):
					in_gap = true
					break
			if in_gap:
				_flush_wall_run(run); run = []
			else:
				var a := deg_to_rad(angle)
				run.append(c + Vector3(cos(a) * 35.0, 0.0, sin(a) * 35.0))
			angle += 3.0
		_flush_wall_run(run)

func _generate_jungle_arc_walls():
	for camp_center in jungle_camp_positions:
		var facing = _get_nearest_lane_direction(camp_center)
		_add_arc_walls(camp_center, facing, 90.0, 3.5, 8)
	# 史诗龙坑墙（主宰/暴君）：开局即出现，留朝向最近分路的开口，方便英雄进坑/野怪被勾出
	for pit_center in epic_pit_centers:
		_add_epic_pit_walls(pit_center)
	_cap_arc_wall_ends()

# 单个龙坑围墙：半径8.5环绕，仅留 mouth±45° 的开口
func _add_epic_pit_walls(center: Vector3):
	# 龙坑墙=开放型：只做背向最近分路的半圈连续矮墙，两端不补柱、不封口
	var mouth := _get_nearest_lane_direction(center)
	var radius := 8.5
	var pts: Array = []
	var angle := 0.0
	while angle < 360.0:
		var rel := fmod(angle - mouth + 360.0, 360.0)
		if rel > 90.0 and rel < 270.0:
			var a := deg_to_rad(angle)
			pts.append(center + Vector3(cos(a) * radius, 0, sin(a) * radius))
		angle += 5.0
	_add_wall_chain(pts, false, true)

## 连续墙链：把一串采样点连成端面平齐的连续墙（非外周墙统一标准）。
## pillar=true → 链首尾各补一根小柱；open_ends=true → 故意敞开（龙坑口），不补柱也不参与自动收口。
## 相邻采样点距离 >6m 视为断口，自动拆成多条链。
func _add_wall_chain(pts: Array, pillar: bool = true, open_ends: bool = false) -> void:
	if pts.size() < 2:
		if pts.size() == 1:
			_add_wall(pts[0], Vector3.ZERO, false, false, false, 2.0, 0.0, false, open_ends)
		return
	var chain: Array = [pts[0]]
	for i in range(1, pts.size()):
		var prev: Vector3 = chain[chain.size() - 1]
		if prev.distance_to(pts[i]) > 6.0:
			_emit_wall_chain(chain, pillar, open_ends)
			chain = [pts[i]]
		else:
			chain.append(pts[i])
	_emit_wall_chain(chain, pillar, open_ends)

## 墙体厚度差异化：按位置哈希分三档（1.0 / 1.2 / 1.4），用 abs 保证镜像对称
func _wall_thickness_for(p: Vector3) -> float:
	var h := int(round(absf(p.x) * 13.0 + absf(p.z) * 7.0))
	return 1.0 + 0.2 * float(h % 3)

func _emit_wall_chain(pts: Array, pillar: bool, open_ends: bool) -> void:
	if pts.size() < 2:
		return
	# 整段墙共用一个厚度：按起点位置哈希取 1.0/1.2/1.4，镜像对称且不同墙段厚薄不一
	var thick := _wall_thickness_for(pts[0])
	# 记录“实际落位”的连续段：被过滤掉的段会断开链，端柱只补在真实端头，避免悬空柱子
	var run_start := Vector3.ZERO
	var run_end := Vector3.ZERO
	var in_run := false
	for i in range(pts.size() - 1):
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var delta := p1 - p0
		var seg := delta.length()
		if seg < 0.05:
			continue
		var mid := (p0 + p1) * 0.5
		var tangent := delta / seg
		# 墙面法线：切线绕 Y 轴转 90°（墙长沿局部 X、局部 +Z 为正面朝向）
		var normal := Vector3(tangent.z, 0.0, -tangent.x)
		var placed := _add_wall(mid, normal.normalized(), false, false, false, 2.0, seg + 0.12, false, open_ends, thick)
		if placed:
			if not in_run:
				in_run = true
				run_start = p0
			run_end = p1
		elif in_run:
			if pillar and not open_ends:
				_add_wall(run_start, Vector3.ZERO, true, false, false, 2.0, 0.0, true)
				_add_wall(run_end, Vector3.ZERO, true, false, false, 2.0, 0.0, true)
			in_run = false
	if in_run and pillar and not open_ends:
		_add_wall(run_start, Vector3.ZERO, true, false, false, 2.0, 0.0, true)
		_add_wall(run_end, Vector3.ZERO, true, false, false, 2.0, 0.0, true)

## 采样段落位：≥2 点走连续墙链（两端小柱），单点退回旧式单块墙
func _flush_wall_run(run: Array) -> void:
	if run.size() >= 2:
		_add_wall_chain(run, true, false)
	elif run.size() == 1:
		_add_wall(run[0], Vector3.ZERO)

## 连续墙收口：没有相邻墙段接合的“开放端头”各补一根小柱（open_end 墙跳过）
func _cap_arc_wall_ends() -> void:
	var segs: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		if w is Wall and absf(w.continuous_len) > 0.01 and not w.open_end and not w.pillar:
			segs.append(w)
	if segs.is_empty():
		return
	var pillar_pts: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		if w is Wall and w.pillar:
			pillar_pts.append(w.position)
	var ends: Array = []
	for w in segs:
		var th: float = w.rotation.y
		var half: float = absf(w.continuous_len) * 0.5
		var dir := Vector3(cos(th), 0.0, -sin(th))
		ends.append(w.position - dir * half)
		ends.append(w.position + dir * half)
	var added: Array = []
	for i in range(ends.size()):
		var e: Vector3 = ends[i]
		var joined := false
		for j in range(ends.size()):
			if j == i:
				continue
			if e.distance_to(ends[j]) < 0.50:
				joined = true
				break
		if not joined:
			for pp in pillar_pts:
				if e.distance_to(pp) < 0.45:
					joined = true
					break
		if joined:
			continue
		var too_close := false
		for pp in added:
			if e.distance_to(pp) < 0.70:
				too_close = true
				break
		if too_close:
			continue
		added.append(e)
		_add_wall(e, Vector3.ZERO, true, false, false, 2.0, 0.0, true)

## 野区弧墙：采样点连成一段段连续墙（端面平齐、无缝），两端各一根小柱。
func _add_arc_walls(center: Vector3, facing_angle: float, arc_span: float, radius: float, count: int):
	if count < 2: return
	var pts: Array = []
	for i in range(count):
		var a = deg_to_rad(facing_angle - arc_span / 2.0 + arc_span * i / (count - 1))
		pts.append(center + Vector3(cos(a) * radius, 0, sin(a) * radius))
	_add_wall_chain(pts, true, false)

func _get_nearest_lane_direction(pos: Vector3) -> float:
	var lane_centers = [
		Vector3(-55, 0, 0), Vector3(55, 0, 0),
		Vector3(-30, 0, 30), Vector3(30, 0, -30),
		Vector3(0, 0, 55), Vector3(0, 0, -55),
	]
	var best_dist = INF
	var best_center = Vector3.ZERO
	for lc in lane_centers:
		var d = pos.distance_squared_to(lc)
		if d < best_dist:
			best_dist = d
			best_center = lc
	var dir = best_center - pos
	return rad_to_deg(atan2(dir.x, dir.z))

func _get_teleport_zone_for_hero(hero: Hero):
	for zone in get_tree().get_nodes_in_group("teleport_zones"):
		if is_instance_valid(zone) and hero.global_position.distance_to(zone.global_position) < 5.0:
			return zone
	return null

func _add_wall(pos: Vector3, facing: Vector3 = Vector3.ZERO, force: bool = false, hq: bool = false, outer: bool = false, outer_len: float = 2.0,
		continuous_len: float = 0.0, pillar: bool = false, open_end: bool = false, thick: float = 1.0) -> bool:
	if not force and _is_inside_high_ground(pos):
		return false
	# 跳过距离草丛<1m的墙体（force=true 时强制落位：弧墙端柱不被草丛吃掉）
	for bp in _bush_positions:
		if not force and pos.distance_to(bp) < 1.0:
			return false
	var wall = Wall.new()
	wall.hq = hq
	wall.outer = outer
	wall.outer_len = outer_len
	wall.continuous_len = continuous_len
	wall.pillar = pillar
	wall.open_end = open_end
	wall.thick = thick
	wall.position = pos
	if facing != Vector3.ZERO:
		wall.rotation.y = atan2(facing.x, facing.z)
	add_child(wall)
	return true

func _is_inside_high_ground(pos: Vector3) -> bool:
	# 仅过滤高地内部（半径33以内），保留半径35处的弧线墙体；
	# 地图边界线（|x| 或 |z| > 61）属于外周城墙圈，不过滤，否则城墙会开天窗
	if absf(pos.x) > 61.0 or absf(pos.z) > 61.0:
		return false
	var hg_radius = 33.0
	var blue_center = Vector3(-60, 0, 60)
	var red_center = Vector3(60, 0, -60)
	if pos.distance_squared_to(blue_center) < hg_radius * hg_radius:
		return true
	if pos.distance_squared_to(red_center) < hg_radius * hg_radius:
		return true
	return false

# 草丛禁区：高地内部，或落在任一防御塔射程（8.9m + 塔体 0.5 + 草丛半宽 1.0）内
func _bush_forbidden(bp: Vector3) -> bool:
	if _is_inside_high_ground(bp):
		return true
	var p := Vector2(bp.x, bp.z)
	for tp in _turret_ground_positions():
		if p.distance_to(tp) <= 10.4:
			return true
	return false

# 全部 20 座防御塔的地面坐标（与 _create_turrets 保持一致）
func _turret_ground_positions() -> Array:
	return [
		Vector2(28, 58), Vector2(-15, 56), Vector2(-35, 55),
		Vector2(-14, 14), Vector2(-27, 27), Vector2(-40, 40),
		Vector2(-58, -28), Vector2(-56, 15), Vector2(-55, 35), Vector2(-53, 53),
		Vector2(-28, -58), Vector2(15, -56), Vector2(35, -55),
		Vector2(14, -14), Vector2(27, -27), Vector2(40, -40),
		Vector2(58, 28), Vector2(56, -15), Vector2(55, -35), Vector2(53, -53),
	]

var hero_configs = {
	"吕布": {
		"name": "吕布", "role": "战士",
		"max_health": 3587, "attack": 182, "attack_range": 475, 
	"move_speed": 380, "max_mana": 0,

		"skills": ["lvbu_q", "lvbu_w", "lvbu_r"], "summoner": "flash",
		"hp_reg": 54
	},
	"亚瑟": {
		"name": "亚瑟", "role": "战士",
		"max_health": 3628, "attack": 175, "attack_range": 325, 
		"move_speed": 385, "max_mana": 0,
		"skills": ["arthur_q", "arthur_w", "arthur_r"], "summoner": "flash",
		"hp_reg": 55
	},
	"马超": {
		"name": "马超", "role": "刺客",
		"max_health": 3482, "attack": 172, "attack_range": 325, 
		"move_speed": 375, "max_mana": 4,
		"skills": ["machao_q", "machao_w", "machao_r"], "summoner": "smite",
		"hp_reg": 50
	},
	"铠": {
		"name": "铠", "role": "战士",
		"max_health": 3476, "attack": 178, "attack_range": 325, 
		 "move_speed": 385,  "max_mana": 580,
		"skills": ["kai_q", "kai_w", "kai_r"], "summoner": "flash",
		"hp_reg": 44,"mana_reg": 14
	},
	"不知火舞": {
		"name": "不知火舞", "role": "法师",
		"max_health": 3288, "attack": 172,  "attack_range": 325, 
		"move_speed": 385,  "max_mana": 200,
		"skills": ["huowu_q", "huowu_w", "huowu_r"], "summoner": "flash",
		"hp_reg": 46,"mana_reg": 50
	},
	"甄姬": {
		"name": "甄姬", "role": "法师",
		"max_health": 3202, "attack": 168, "attack_range": 650, 
		"move_speed": 360,  "max_mana": 640,
		"skills": ["zhenji_q", "zhenji_w", "zhenji_r"], "summoner": "flash",
		"hp_reg": 45,"mana_reg": 16
	},
	"狄仁杰": {
		"name": "狄仁杰", "role": "射手",
		"max_health": 3352, "attack": 170, "attack_range": 825, 
		"move_speed": 370,"max_mana": 600,
		"skills": ["direnjie_q", "direnjie_cleanse", "direnjie_r"], "summoner": "flash",
		"hp_reg": 40,"mana_reg": 15
	},
	"太乙真人": {
		"name": "太乙真人", "role": "辅助",
		"max_health": 3475, "attack": 160, "attack_range": 350,
		"move_speed": 375, "max_mana": 600,
		"skills": ["taiyi_q", "taiyi_w", "taiyi_r"], "summoner": "flash",
		"hp_reg": 77,"mana_reg": 15
	},
	"东皇太一": {
		"name": "东皇太一", "role": "战士",
		"max_health": 3309, "attack": 168, "attack_range": 675, "attack_speed": 500,
		"move_speed": 365,  "max_mana": 620,
		"skills": ["donghuang_q", "donghuang_w", "donghuang_r"], "summoner": "flash",
		"hp_reg": 80,"mana_reg": 15
	},
	"李白": {
		"name": "李白", "role": "刺客",
		"max_health": 3257, "attack": 171, "attack_range": 325,
		 "move_speed": 385, "max_mana": 560,
		"skills": ["libai_q", "libai_w", "libai_r"], "summoner": "smite",
		"hp_reg": 49,"mana_reg": 14
	},
	"兰陵王": {
		"name": "兰陵王", "role": "刺客",
		"max_health": 3340, "attack": 173, "attack_range":325, 
		"move_speed": 390,  "max_mana": 560,
		"skills": ["lanling_q", "lanling_w", "lanling_r", "lanling_stealth"], "summoner": "smite",
		"hp_reg": 52,"mana_reg": 14
	},
	"孙尚香": {
		"name": "孙尚香", "role": "射手",
		"max_health": 3329, "attack": 169, "attack_range": 725, 
		 "move_speed":360, "max_mana": 600,
		"skills": ["sunshangxiang_q", "sunshangxiang_w", "sunshangxiang_r"], "summoner": "flash",
		"hp_reg": 40,"mana_reg": 15
	},
	"马可波罗": {
		"name": "马可波罗", "role": "射手",
		"max_health": 3207, "attack": 175, "attack_range": 700, 
		 "move_speed": 360,"max_mana": 200,
		"skills": ["makeboluo_q", "makeboluo_w", "makeboluo_r"], "summoner": "flash",
		"hp_reg": 46,"mana_reg": 50
	},
	"张飞": {
		"name": "张飞", "role": "辅助",
		"max_health": 3538, "attack": 168, "attack_range": 325,
		"move_speed": 375, "max_mana": 100,
		"skills": ["zhangfei_q", "zhangfei_w", "zhangfei_r"], "summoner": "flash",
		"hp_reg": 86,"mana_reg": 5
	},
	"沈梦溪": {
		"name": "沈梦溪", "role": "法师",
		"max_health": 3300, "attack": 172,  "attack_range": 650, 
		 "move_speed": 365, "max_mana": 10,
		"skills": ["shenmengxi_q", "shenmengxi_w", "shenmengxi_r"], "summoner": "flash",
		"hp_reg": 46,"mana_reg": 5
	},
		"安琪拉": {
			"name": "安琪拉", "role": "法师",
			"max_health": 3328, "attack": 172, "attack_range": 700,
			"move_speed": 360, "max_mana": 640,
			"skills": ["angela_q", "angela_w", "angela_r"], "summoner": "flash",
			"hp_reg": 47, "mana_reg": 16

	},
		"妲己": {
			"name": "妲己", "role": "法师",
			"max_health": 3295, "attack": 172, "attack_range": 700,
			"move_speed": 360, "max_mana": 640,
			"skills": ["daji_q", "daji_w", "daji_r"], "summoner": "flash",
			"hp_reg": 46, "mana_reg": 16
		},
		"小乔": {
			"name": "小乔", "role": "法师",
			"max_health": 3200, "attack": 163, "attack_range": 700,
			"move_speed": 365, "max_mana": 640,
			"skills": ["xiaoqiao_q", "xiaoqiao_w", "xiaoqiao_r"], "summoner": "flash",
			"hp_reg": 44, "mana_reg": 16
		},
		"鲁班七号": {
			"name": "鲁班七号", "role": "射手",
			"max_health": 3366, "attack": 174, "attack_range": 750,
			"move_speed": 370, "max_mana": 600,
			"skills": ["luban_q", "luban_w", "luban_r"], "summoner": "flash",
			"hp_reg": 42, "mana_reg": 15
		},

		"夏侯惇": {
			"name": "夏侯惇", "role": "战士",
			"max_health": 3590, "attack": 183, "attack_range": 475,
			"move_speed": 380, "max_mana": 600,
			"skills": ["xiahou_q", "xiahou_w", "xiahou_r"], "summoner": "flash",
			"hp_reg": 84, "mana_reg": 15
		},
		"后羿": {
			"name": "后羿", "role": "射手",
			"max_health": 3362, "attack": 166, "attack_range": 750,
			"move_speed": 370, "max_mana": 600,
			"skills": ["houyi_q", "houyi_w", "houyi_r"], "summoner": "flash",
			"hp_reg": 41, "mana_reg": 15
		},
		"李元芳": {
			"name": "李元芳", "role": "射手",
			"max_health": 3257, "attack": 165, "attack_range": 700,
			"move_speed": 360, "max_mana": 600,
			"skills": ["liyuanfang_q", "liyuanfang_w", "liyuanfang_r"], "summoner": "flash",
			"hp_reg": 37, "mana_reg": 15
		},
		"元流之子": {
			"name": "元流之子", "role": "射手",
			"max_health": 3250, "attack": 170, "attack_range": 700,
			"move_speed": 360, "max_mana": 600,
			"skills": ["yuanliu_q", "yuanliu_w", "yuanliu_r"], "summoner": "flash",
			"hp_reg": 40, "mana_reg": 15
		},
		"大禹": {
			"name": "大禹", "role": "辅助",
			"max_health": 3900, "attack": 155, "attack_range": 350,
			"move_speed": 380, "max_mana": 800,
			"skills": ["dayu_q", "dayu_w", "dayu_r"], "summoner": "治疗术",
			"hp_reg": 55, "mana_reg": 16
		},

			"王昭君": {
				"name": "王昭君", "role": "法师",
				"max_health": 3206, "attack": 166, "attack_range": 700,
				"move_speed": 365, "max_mana": 640,
				"skills": ["wangzhaojun_q", "wangzhaojun_w", "wangzhaojun_r"], "summoner": "flash",
				"hp_reg": 44, "mana_reg": 16
			},
	"刘禅": {
		"name": "刘禅", "role": "辅助",
		"max_health": 3539, "attack": 180, "attack_range": 325,
		"move_speed": 375, "max_mana": 600,
		"armor": 150, "magic_resist": 75,
		"skills": ["liushan_q", "liushan_w", "liushan_r"], "summoner": "flash",
		"hp_reg": 84, "mana_reg": 15
			},

	"孙悟空": {
		"name": "孙悟空", "role": "刺客",
		"max_health": 3334, "attack": 173, "attack_range": 325,
		"move_speed": 385, "max_mana": 560,
		"armor": 150, "magic_resist": 75,
		"skills": ["sunwukong_q", "sunwukong_w", "sunwukong_r"], "summoner": "smite",
		"hp_reg": 50, "mana_reg": 14
			},

	"英睿": {
		"name": "英睿", "role": "战士",
		"max_health": 3620, "attack": 178, "attack_range": 325,
		"move_speed": 380, "max_mana": 580,
		"armor": 150, "magic_resist": 75,
		"skills": ["yingrui_q", "yingrui_w", "yingrui_r"], "summoner": "flash",
		"hp_reg": 50, "mana_reg": 15
			},
}


# ---------- 单机选人界面：视觉/规格对齐联机大厅选人（NetLobby._show_select） ----------
# P0 调色板收敛：不再自建一套，统一取 UiKit 设计系统
var SEL_BG: Color = UiKit.C_PANEL_BG
var SEL_TITLE: Color = UiKit.C_GOLD
var SEL_SUB: Color = UiKit.C_TEXT_DIM
var SEL_TEXT: Color = UiKit.C_TEXT
var SEL_DIM: Color = UiKit.C_TEXT_DISABLED
var SEL_GOLD: Color = UiKit.C_GOLD
var SEL_SUMM_COLOR: Color = Color(0.36, 0.46, 0.66)
# 选人页状态：3D 立绘 / 底部英雄条 / 席位（沿用原 sel_prev_* 预览字段）
var sel_prev_name: Label = null
var sel_prev_role_chip: PanelContainer = null
var sel_prev_role_label: Label = null
var sel_prev_info_chip: PanelContainer = null
var sel_prev_info_label: Label = null
var sel_prev_skill_box: HBoxContainer = null
var sel_prev_stats: HBoxContainer = null
var sel_preview_3d: HeroPreview = null
var sel_skin_btn: Button = null
var sel_hero_strip: HBoxContainer = null
var sel_tab_buttons: Dictionary = {}
var sel_active_role: String = "全部"
var sel_seat_hero_label: Label = null
var sel_seat_summ_label: Label = null
var sel_mini_hero_label: Label = null
# 玩家固定分路（PlayerPrefs，由主菜单选择）
var sel_lane_role: String = "战士"
var sel_lane_name: String = "对抗路"
# —— 拟真 BP 选人流程 ——
const SEL_DRAFT_TURN_TIME := 20.0
# 10 步选人顺序：[队伍(0=我方,1=敌方), 队伍内号位(0-based)]
const SEL_DRAFT_ORDER := [[0, 0], [1, 0], [1, 1], [0, 1], [0, 2], [1, 2], [1, 3], [0, 3], [0, 4], [1, 4]]
var sel_player_seat: int = 0
var sel_ai_names: Array = []            # 本局 9 个 AI 的随机昵称（选人席位 ↔ 对局内同名）
var sel_name_edit: LineEdit = null      # 昵称输入框
var sel_player_name_label: Label = null # 玩家席位昵称（输入时实时刷新）
var _match_ai_names: Array = []         # 本局实际分配的 AI 昵称序列
var _ai_name_cursor: int = 0
var sel_draft_active: bool = false
var sel_draft_done: bool = false
var sel_draft_step: int = 0
var sel_draft_time: float = SEL_DRAFT_TURN_TIME
var sel_ai_timer: float = 0.0
var sel_ai_wait: float = 1.5
var sel_draft_done_timer: float = 0.0
var sel_ally_picks: Array = []
var sel_enemy_picks: Array = []
var sel_taken: Dictionary = {}
var sel_summ_manual: bool = false
var sel_player_picked: bool = false
var sel_player_summ: String = "flash"
var sel_ally_ai_picks: Array = []
# 席位/顶栏标签引用（按号位索引 0-based）
var sel_ally_hero_labels: Array = []
var sel_ally_summ_labels: Array = []
var sel_foe_hero_labels: Array = []
var sel_foe_summ_labels: Array = []
var sel_mini_hero_labels: Array = []
var sel_foe_mini_hero_labels: Array = []
var sel_ally_avatars: Array = []
var sel_foe_avatars: Array = []
var sel_mini_avatars: Array = []
var sel_foe_mini_avatars: Array = []
var sel_prev_summ_icon = null
# 阶段块文字 / 倒计时环数字 / 叉选提示
var sel_stage_title_label: Label = null
var sel_stage_sub_label: Label = null
var sel_stage_ring_label: Label = null
var sel_tip_label: Label = null
var sel_tip_time: float = 0.0
# 右栏「召唤 / 出装」tab 与出装顺序调整
var sel_right_tab: String = "召唤"
var sel_summ_tab_btn: Button = null
var sel_build_tab_btn: Button = null
var sel_summ_panel: Control = null
var sel_build_panel: Control = null
var sel_build_rows: GridContainer = null
var sel_build_ids: Array = []
var sel_build_hero: String = ""
var sel_build_scheme_row: GridContainer = null
# 对局加载界面（BP 结束 / 网络 host 直接开局）
var loading_screen: LoadingScreen = null
var _loading_shown := false
# 召唤师卡悬停浮层
var sel_hover_panel: PanelContainer = null
var sel_build_hover: PanelContainer = null   # 出装卡悬浮详情（选人界面）
# 塔被摧毁后原地的永久塔墩（key = 塔位坐标）
var _tower_stumps: Dictionary = {}
# —— 选人两阶段：true=未选英雄（中央英雄面板）/ false=已选英雄（3D 立绘 + 底部召唤·出装） ——
var sel_stage_picking := true
var sel_pick_layer: Control = null
var sel_pick_panel: PanelContainer = null
var sel_pick_hint: Label = null
var sel_bottom_row: Control = null
var sel_right_tabs: Control = null
var sel_right_body: Control = null
var sel_preview_box: Control = null
var sel_overlay: Control = null
var sel_back_btn: Button = null
# 技能悬浮详情浮层
var sel_skill_tip: PanelContainer = null
var sel_skill_tip_title: Label = null
var sel_skill_tip_body: Label = null
var _skill_tip_probe: Hero = null
var _skill_tip_probe_name: String = ""

# 装饰倒计时环（仅选人页）：底环 + 缓慢旋转的金色进度弧
class SelRing extends Control:
	var accent: Color = Color(1.0, 0.84, 0.35)
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := maxf(8.0, minf(size.x, size.y) * 0.5 - 4.0)
		draw_circle(c, r, Color(0.03, 0.04, 0.06, 0.72))
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.10), 3.0, true)
		var start := -PI * 0.5 + _t * 0.4
		draw_arc(c, r, start, start + TAU * 0.72, 64, accent, 5.0, true)
		draw_arc(c, r - 7.0, PI * 0.5, PI * 1.5, 64, Color(accent.r, accent.g, accent.b, 0.22), 2.0, true)

func _sel_label(text: String, size: int, color: Color, centered: bool = true) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", color)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	return lab

# 字号统一走 UiKit 档位（FS_XS..FS_HUGE）× 全局 scale
func _sel_fs(tier: int) -> int:
	return int(round(tier * UiKit.scale()))

func _sel_btn_style(color: Color, hovered: bool, filled: bool = false) -> StyleBoxFlat:
	return UiKit.skin_button("hover" if hovered else "normal", color, filled)

func _sel_btn(text: String, color: Color, filled: bool = false, min_size: Vector2 = Vector2(560, 76)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_LG))
	b.add_theme_stylebox_override("normal", _sel_btn_style(color, false, filled))
	b.add_theme_stylebox_override("hover", _sel_btn_style(color, true, filled))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", color, filled))
	b.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", color, filled))
	b.add_theme_color_override("font_color", SEL_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", SEL_DIM)
	return b

func _style_card(card: Panel, base_color: Color, selected: bool) -> void:
	if card == null: return
	card.add_theme_stylebox_override("panel", UiKit.skin_card(base_color, selected, 0.88 if selected else 0.72))

func _sel_summ_name(sid: String) -> String:
	match sid:
		"flash": return "闪现"
		"sprint": return "疾跑"
		"teleport": return "传送"
		"heal": return "治疗术"
		"execute": return "终结"
		"frenzy": return "狂暴"
		"stun": return "晕眩"
		"cleanse_summoner": return "净化"
		"weaken": return "弱化"
		"smite": return "惩击"
	return sid

func _sel_skill_type(t: int) -> String:
	match t:
		0: return "指向"
		1: return "范围"
		2: return "增益"
		3: return "线性"
		4: return "位移"
		5: return "多段"
		6: return "护盾"
	return "通用"

# 选人/加载界面按玩家真实阵营上色（蓝方=蓝，红方=红）
func sel_side_col() -> Color:
	return UiKit.C_TEAM0 if Config.player_team == Config.Team.PLAYER else UiKit.C_TEAM1

func sel_foe_col() -> Color:
	return UiKit.C_TEAM1 if Config.player_team == Config.Team.PLAYER else UiKit.C_TEAM0

# 立绘预览：切模型/职责色 + 左下角名称/标签/技能 chip（不改选人状态）
func _refresh_sel_preview(hero_name: String) -> void:
	if sel_prev_name == null: return
	var cfg: Dictionary = hero_configs.get(hero_name, {})
	if cfg.is_empty(): return
	var role: String = str(cfg.get("role", ""))
	var role_color: Color = ROLE_COLORS.get(role, UiKit.C_TEAM0)
	if HeroSkinTable.get_skin(hero_name, selected_skin_id).is_empty():
		selected_skin_id = HeroSkinTable.selected_id(hero_name)
	if sel_preview_3d:
		sel_preview_3d.set_hero(hero_name, selected_skin_id)
		sel_preview_3d.set_accent(role_color)
	if sel_skin_btn:
		sel_skin_btn.text = "皮肤 · " + HeroSkinTable.skin_name(hero_name, selected_skin_id)
	sel_prev_name.text = hero_name
	sel_prev_name.add_theme_color_override("font_color", SEL_GOLD)
	if sel_prev_role_label:
		sel_prev_role_label.text = "定位 · " + role
		sel_prev_role_label.add_theme_color_override("font_color", role_color.lightened(0.35))
	if sel_prev_role_chip:
		sel_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(role_color, 0.95, 12))
	var rec_summ_name := _sel_summ_name(str(cfg.get("summoner", "flash")))
	if sel_prev_info_label:
		sel_prev_info_label.text = "推荐召唤师 · " + rec_summ_name
	if sel_prev_summ_icon:
		sel_prev_summ_icon.set_summoner(rec_summ_name)
	if sel_prev_info_chip:
		sel_prev_info_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_GOLD, 0.9, 12))
	# 技能 1/2/3（+被动）横向 chip 行
	if sel_prev_skill_box:
		for c in sel_prev_skill_box.get_children():
			sel_prev_skill_box.remove_child(c)
			c.queue_free()
		var skills: Array = cfg.get("skills", [])
		for i in skills.size():
			var sk: Skill = SkillDatabase.get_skill(str(skills[i]))
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.58, 12))
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 7)
			var glyph := SelectArt.SkillGlyph.new(hero_name, sk, i, 62)
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(glyph)
			var info := VBoxContainer.new()
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_theme_constant_override("separation", 0)
			var name_lbl := _sel_label("%d  %s" % [i + 1, str(sk.skill_name) if sk != null else str(skills[i])], _sel_fs(UiKit.FS_SM), SEL_TEXT, false)
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(name_lbl)
			var meta := _sel_skill_type(int(sk.type) if sk != null else 0)
			if sk != null:
				meta += " · 冷却 %ds" % int(round(sk.cooldown))
				if sk.mana_cost > 0: meta += " · 法力 %d" % sk.mana_cost
			var meta_lbl := _sel_label(meta, int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)), SEL_DIM, false)
			meta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(meta_lbl)
			row.add_child(info)
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			chip.mouse_entered.connect(_show_skill_tip.bind(sk, i))
			chip.mouse_exited.connect(_hide_skill_tip)
			chip.add_child(row)
			sel_prev_skill_box.add_child(chip)
	# 推荐召唤师默认（玩家未手动改过时跟随英雄）+ 出装顺序面板刷新
	_apply_default_summoner(hero_name)
	_load_build_for_hero(hero_name)

# 王者式全屏选人：顶部阶段条 + 左右 5v5 席位 + 中央 3D 立绘 + 底部英雄条/召唤师/确认
func _show_hero_select_ui():
	# —— 进入选人：读取玩家固定分路 + 随机号位 + 重置 BP 状态 ——
	Config.reset_player_team()
	Config.roll_player_team()
	sel_lane_role = PlayerPrefs.get_lane_role()
	sel_lane_name = PlayerPrefs.get_lane()
	if sel_lane_name == "":
		sel_lane_name = HeroPickData.role_lane(sel_lane_role)
	sel_player_seat = randi() % 5
	sel_ally_picks = ["", "", "", "", ""]
	sel_enemy_picks = ["", "", "", "", ""]
	# 昵称：玩家从缓存读（空则必须先取名才能开始），AI 每局随机 9 个不重名
	var cached_name := NameStore.player_name()
	sel_ai_names = NameStore.random_ai_names(9, [cached_name])
	_match_ai_names = []
	_ai_name_cursor = 0
	sel_taken = {}
	sel_ally_hero_labels = [null, null, null, null, null]
	sel_ally_summ_labels = [null, null, null, null, null]
	sel_foe_hero_labels = [null, null, null, null, null]
	sel_foe_summ_labels = [null, null, null, null, null]
	sel_mini_hero_labels = [null, null, null, null, null]
	sel_foe_mini_hero_labels = [null, null, null, null, null]
	sel_ally_avatars = [null, null, null, null, null]
	sel_foe_avatars = [null, null, null, null, null]
	sel_mini_avatars = [null, null, null, null, null]
	sel_foe_mini_avatars = [null, null, null, null, null]
	sel_prev_summ_icon = null
	sel_draft_active = false
	sel_draft_done = false
	sel_draft_step = 0
	sel_draft_time = SEL_DRAFT_TURN_TIME
	sel_ai_timer = 0.0
	sel_summ_manual = false
	sel_player_picked = false
	sel_player_summ = "flash"
	sel_right_tab = "召唤"
	sel_build_ids = []
	sel_build_hero = ""
	sel_hover_panel = null
	selected_hero_type = ""
	selected_hero_card = null
	selected_summ_card = null
	selected_summoner = "flash"
	selected_skin_id = ""
	select_ui = CanvasLayer.new()
	select_ui.layer = UiKit.LAYER_PICK
	var root := Control.new()
	root.name = "SelectRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select_ui.add_child(root)
	# 兜底底色（置底不透明）+ 统一动态背景
	var bg := ColorRect.new()
	bg.name = "SelectBg"
	bg.color = Color(SEL_BG.r, SEL_BG.g, SEL_BG.b, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	UiKit.make_backdrop(root, sel_side_col(), 1.0)
	root.move_child(bg, 0)
	# 全屏边距：左右 16 / 上下 8
	var margin := MarginContainer.new()
	margin.name = "SelectMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 手机横屏：在基础边距上再避让刘海/圆角/手势条（桌面 safe_* 为 0）
	margin.add_theme_constant_override("margin_left", 16 + int(round(UiKit.safe_left())))
	margin.add_theme_constant_override("margin_right", 16 + int(round(UiKit.safe_right())))
	margin.add_theme_constant_override("margin_top", 8 + int(round(UiKit.safe_top())))
	margin.add_theme_constant_override("margin_bottom", 8 + int(round(UiKit.safe_bottom())))
	root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var first_hero := ""
	if not hero_configs.is_empty():
		first_hero = _first_lane_hero()
		if first_hero == "":
			first_hero = str(hero_configs.keys()[0])
	selected_hero_type = first_hero
	selected_skin_id = HeroSkinTable.selected_id(first_hero)
	# —— 顶部阶段条 h=92：我方 mini 席 / 阶段块 / 敌方 mini 席 ——
	var top := PanelContainer.new()
	top.name = "SelectTop"
	top.custom_minimum_size = Vector2(0, 92)
	# 收紧上下内边距，确保阶段块文字不把 92 高撑开
	var top_style := UiKit.skin_card(sel_side_col(), false, 0.5)
	top_style.content_margin_top = 2
	top_style.content_margin_bottom = 2
	top.add_theme_stylebox_override("panel", top_style)
	page.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)
	var our_tag := VBoxContainer.new()
	our_tag.alignment = BoxContainer.ALIGNMENT_CENTER
	our_tag.custom_minimum_size = Vector2(64, 0)
	our_tag.add_child(_sel_label("我方", _sel_fs(UiKit.FS_SM), sel_side_col(), false))
	our_tag.add_child(_sel_label("5 席", _sel_fs(UiKit.FS_XS), SEL_DIM, false))
	top_row.add_child(our_tag)
	for i in 5:
		top_row.add_child(_create_mini_slot(i, 0 if i == sel_player_seat else 1))
	var stage := HBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 18)
	var stage_txt := VBoxContainer.new()
	stage_txt.alignment = BoxContainer.ALIGNMENT_CENTER
	sel_stage_title_label = _sel_label("选择英雄", _sel_fs(UiKit.FS_XL), SEL_GOLD)
	stage_txt.add_child(sel_stage_title_label)
	sel_stage_sub_label = _sel_label("自选模式 · 不限时", _sel_fs(UiKit.FS_SM), SEL_SUB)
	stage_txt.add_child(sel_stage_sub_label)
	stage.add_child(stage_txt)
	stage.add_child(_create_stage_ring())
	top_row.add_child(stage)
	for i in 5:
		top_row.add_child(_create_mini_slot(i, 2))
	var foe_tag := VBoxContainer.new()
	foe_tag.alignment = BoxContainer.ALIGNMENT_CENTER
	foe_tag.custom_minimum_size = Vector2(64, 0)
	foe_tag.add_child(_sel_label("敌方", _sel_fs(UiKit.FS_SM), sel_foe_col(), false))
	foe_tag.add_child(_sel_label("5 席", _sel_fs(UiKit.FS_XS), SEL_DIM, false))
	top_row.add_child(foe_tag)
	# —— 中部 expand：左席位 / 中央立绘 / 右席位 ——
	var mid := HBoxContainer.new()
	mid.name = "SelectMiddle"
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	page.add_child(mid)
	var our_seats := VBoxContainer.new()
	our_seats.name = "SelectOurSeats"
	our_seats.custom_minimum_size = Vector2(218, 0)
	our_seats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	our_seats.add_theme_constant_override("separation", 8)
	mid.add_child(our_seats)
	for i in 5:
		our_seats.add_child(_create_team_seat(i, 0 if i == sel_player_seat else 1))
	var center := Control.new()
	center.name = "SelectStage"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.clip_contents = true
	mid.add_child(center)
	# 3D 立绘：AspectRatioContainer 保持 900×1100 竖版比例，避免宽屏拉伸变形
	var preview_box := AspectRatioContainer.new()
	preview_box.name = "SelectPreviewBox"
	preview_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_box.ratio = 900.0 / 1100.0
	preview_box.stretch_mode = 1          # STRETCH_HEIGHT：按高取宽，保持竖版比例
	preview_box.alignment_horizontal = 1  # ALIGNMENT_CENTER
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(preview_box)
	sel_preview_box = preview_box
	sel_preview_3d = preload("res://scripts/ui/HeroPreview.gd").new()
	sel_preview_3d.name = "SelectHeroPreview"
	preview_box.add_child(sel_preview_3d)
	sel_preview_3d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 覆盖层：左下英雄名 / 职责与推荐召唤师标签 / 技能 chip 行
	var overlay := MarginContainer.new()
	overlay.name = "SelectOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("margin_left", 42)
	overlay.add_theme_constant_override("margin_right", 42)
	overlay.add_theme_constant_override("margin_top", 24)
	overlay.add_theme_constant_override("margin_bottom", 26)
	center.add_child(overlay)
	sel_overlay = overlay
	var ov_v := VBoxContainer.new()
	ov_v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ov_v.size_flags_vertical = Control.SIZE_SHRINK_END
	ov_v.add_theme_constant_override("separation", 10)
	overlay.add_child(ov_v)
	sel_prev_name = _sel_label("—", int(round(UiKit.FS_HUGE * 1.12 * UiKit.scale())), SEL_GOLD, false)
	sel_prev_name.name = "SelectPreviewName"
	sel_prev_name.add_theme_constant_override("outline_size", 8)
	sel_prev_name.add_theme_color_override("font_outline_color", Color(0.10, 0.07, 0.02, 0.9))
	ov_v.add_child(sel_prev_name)
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 12)
	ov_v.add_child(chip_row)
	sel_prev_role_chip = PanelContainer.new()
	sel_prev_role_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.95, 12))
	sel_prev_role_label = _sel_label("定位 · —", _sel_fs(UiKit.FS_SM), UiKit.C_TEAM0, false)
	sel_prev_role_chip.add_child(sel_prev_role_label)
	chip_row.add_child(sel_prev_role_chip)
	sel_prev_info_chip = PanelContainer.new()
	sel_prev_info_chip.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_GOLD, 0.9, 12))
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 6)
	sel_prev_summ_icon = SelectArt.SummonerGlyph.new("", 48)
	info_row.add_child(sel_prev_summ_icon)
	sel_prev_info_label = _sel_label("推荐召唤师 · —", _sel_fs(UiKit.FS_SM), UiKit.C_GOLD, false)
	info_row.add_child(sel_prev_info_label)
	sel_prev_info_chip.add_child(info_row)
	chip_row.add_child(sel_prev_info_chip)
	sel_skin_btn = Button.new()
	sel_skin_btn.text = "皮肤 · 经典"
	sel_skin_btn.custom_minimum_size = Vector2(210, 40)
	sel_skin_btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	sel_skin_btn.add_theme_color_override("font_color", SEL_TEXT)
	sel_skin_btn.add_theme_stylebox_override("normal", UiKit.skin_chip(UiKit.C_GOLD, 0.9, 12))
	sel_skin_btn.add_theme_stylebox_override("hover", UiKit.skin_chip(UiKit.C_GOLD, 1.0, 12))
	sel_skin_btn.add_theme_stylebox_override("pressed", UiKit.skin_chip(UiKit.C_GOLD, 0.7, 12))
	sel_skin_btn.focus_mode = Control.FOCUS_NONE
	sel_skin_btn.pressed.connect(_cycle_selected_skin)
	chip_row.add_child(sel_skin_btn)
	sel_prev_skill_box = HBoxContainer.new()
	sel_prev_skill_box.add_theme_constant_override("separation", 10)
	ov_v.add_child(sel_prev_skill_box)
	var hint := _sel_label("分路：%s · 只能选择%s · 每队每个职责限选 1 名英雄" % [sel_lane_name, sel_lane_role], _sel_fs(UiKit.FS_XS), Color(1, 1, 1, 0.4), false)
	hint.name = "SelectHint"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -780
	hint.offset_top = -56
	hint.offset_right = -48
	hint.offset_bottom = -26
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hint)
	# 叉选/锁定等即时提示（居中顶部，短暂显示）
	sel_tip_label = _sel_label("", _sel_fs(UiKit.FS_MD), UiKit.C_GOLD, true)
	sel_tip_label.name = "SelectTip"
	sel_tip_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sel_tip_label.offset_left = -420
	sel_tip_label.offset_top = 14
	sel_tip_label.offset_right = 420
	sel_tip_label.offset_bottom = 54
	sel_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_tip_label.visible = false
	center.add_child(sel_tip_label)
	var foe_seats := VBoxContainer.new()
	foe_seats.name = "SelectFoeSeats"
	foe_seats.custom_minimum_size = Vector2(218, 0)
	foe_seats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	foe_seats.add_theme_constant_override("separation", 8)
	mid.add_child(foe_seats)
	for i in 5:
		foe_seats.add_child(_create_team_seat(i, 2))
	# —— 底部 h=300：职业页签 + 英雄卡横条 | 召唤师 + 按钮 ——
	var bottom := HBoxContainer.new()
	bottom.name = "SelectBottom"
	bottom.custom_minimum_size = Vector2(0, 344)
	bottom.add_theme_constant_override("separation", 16)
	page.add_child(bottom)
	# 英雄选择面板：屏幕正中浮层（职业页签 + 英雄卡横条）；未选英雄阶段只显示这一块
	sel_pick_layer = Control.new()
	sel_pick_layer.name = "SelectPickLayer"
	sel_pick_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sel_pick_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pick_center := CenterContainer.new()
	pick_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_pick_layer.add_child(pick_center)
	sel_pick_panel = PanelContainer.new()
	sel_pick_panel.name = "SelectPickPanel"
	sel_pick_panel.custom_minimum_size = Vector2(minf(1560.0, get_viewport().get_visible_rect().size.x * 0.88), 0)
	var pick_style := UiKit.skin_card(sel_side_col(), false, 0.94)
	pick_style.content_margin_left = 18
	pick_style.content_margin_right = 18
	pick_style.content_margin_top = 12
	pick_style.content_margin_bottom = 14
	sel_pick_panel.add_theme_stylebox_override("panel", pick_style)
	pick_center.add_child(sel_pick_panel)
	var pick_v := VBoxContainer.new()
	pick_v.add_theme_constant_override("separation", 10)
	sel_pick_panel.add_child(pick_v)
	var pick_head := HBoxContainer.new()
	pick_head.add_theme_constant_override("separation", 14)
	pick_v.add_child(pick_head)
	pick_head.add_child(_sel_label("选择英雄", _sel_fs(UiKit.FS_LG), SEL_GOLD, false))
	select_summary_label = _sel_label("请选择英雄", _sel_fs(UiKit.FS_SM), SEL_DIM, false)
	select_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pick_head.add_child(select_summary_label)
	sel_pick_hint = _sel_label("", _sel_fs(UiKit.FS_XS), SEL_DIM, false)
	sel_pick_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pick_head.add_child(sel_pick_hint)
	var tab_row := HBoxContainer.new()
	tab_row.custom_minimum_size = Vector2(0, 48)
	tab_row.add_theme_constant_override("separation", 8)
	pick_v.add_child(tab_row)
	var tab_roles := ["全部", "战士", "法师", "刺客", "射手", "辅助"]
	# 自动切到本局分路对应的职业栏
	sel_active_role = sel_lane_role if tab_roles.has(sel_lane_role) else "全部"
	for r in tab_roles:
		var tab_active: bool = r == sel_active_role
		var tab := _sel_btn(r, UiKit.C_GOLD if tab_active else UiKit.C_PANEL_EDGE, tab_active, Vector2(112, 48))
		tab.name = "SelectTab_" + r
		tab.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
		tab.pressed.connect(_on_sel_tab_pressed.bind(r))
		tab_row.add_child(tab)
		sel_tab_buttons[r] = tab
	var tab_gap := Control.new()
	tab_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(tab_gap)
	var strip_scroll := ScrollContainer.new()
	strip_scroll.name = "SelectHeroStripScroll"
	strip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	pick_v.add_child(strip_scroll)
	sel_hero_strip = HBoxContainer.new()
	sel_hero_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sel_hero_strip.add_theme_constant_override("separation", 8)
	strip_scroll.add_child(sel_hero_strip)
	root.add_child(sel_pick_layer)
	# 右 760：召唤 / 出装 双 tab + 内容区 + 返回/确定（出装卡要放得下图标+名称+价格）
	var right := VBoxContainer.new()
	right.name = "SelectRight"
	right.custom_minimum_size = Vector2(860, 0)
	right.add_theme_constant_override("separation", 6)
	bottom.add_child(right)
	var sp_l := Control.new()
	sp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp_l)
	bottom.move_child(sp_l, 0)
	var sp_r := Control.new()
	sp_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp_r)
	sel_bottom_row = bottom
	var right_tabs := HBoxContainer.new()
	right_tabs.custom_minimum_size = Vector2(0, 40)
	right_tabs.add_theme_constant_override("separation", 8)
	right.add_child(right_tabs)
	sel_right_tabs = right_tabs
	sel_summ_tab_btn = _sel_btn("召唤", UiKit.C_GOLD, true, Vector2(200, 40))
	sel_summ_tab_btn.name = "SelectSummTab"
	sel_summ_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_summ_tab_btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	sel_summ_tab_btn.pressed.connect(_on_right_tab_pressed.bind("召唤"))
	right_tabs.add_child(sel_summ_tab_btn)
	sel_build_tab_btn = _sel_btn("出装", UiKit.C_PANEL_EDGE, false, Vector2(200, 40))
	sel_build_tab_btn.name = "SelectBuildTab"
	sel_build_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_build_tab_btn.pressed.connect(_on_right_tab_pressed.bind("出装"))
	right_tabs.add_child(sel_build_tab_btn)
	_style_right_tab(sel_summ_tab_btn, true)
	_style_right_tab(sel_build_tab_btn, false)
	var right_body := Control.new()
	right_body.name = "SelectRightBody"
	right_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(right_body)
	sel_right_body = right_body
	# 召唤面板：2 列召唤师卡 + 详情
	sel_summ_panel = VBoxContainer.new()
	sel_summ_panel.name = "SelectSummPanel"
	sel_summ_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sel_summ_panel.add_theme_constant_override("separation", 4)
	right_body.add_child(sel_summ_panel)
	var summ_scroll := ScrollContainer.new()
	summ_scroll.name = "SelectSummScroll"
	summ_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summ_scroll.custom_minimum_size = Vector2(0, 236)
	summ_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	summ_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sel_summ_panel.add_child(summ_scroll)
	var summ_grid := GridContainer.new()
	summ_grid.columns = 5
	summ_grid.add_theme_constant_override("h_separation", 8)
	summ_grid.add_theme_constant_override("v_separation", 8)
	summ_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summ_scroll.add_child(summ_grid)
	var summons := {"闪现": "flash", "疾跑": "sprint", "传送": "teleport", "治疗术": "heal", "终结": "execute", "狂暴": "frenzy", "晕眩": "stun", "净化": "cleanse_summoner", "弱化": "weaken", "惩击": "smite"}
	for sname in summons:
		summ_grid.add_child(_create_summ_card(sname, str(summons[sname])))
	select_summ_detail = _sel_label("选中后显示冷却与说明", _sel_fs(UiKit.FS_XS), SEL_DIM, false)
	select_summ_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	select_summ_detail.custom_minimum_size = Vector2(0, 34)
	sel_summ_panel.add_child(select_summ_detail)
	# 出装面板：6 件推荐装顺序 + 恢复推荐
	sel_build_panel = VBoxContainer.new()
	sel_build_panel.name = "SelectBuildPanel"
	sel_build_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sel_build_panel.add_theme_constant_override("separation", 4)
	sel_build_panel.visible = false
	right_body.add_child(sel_build_panel)
	# 备战方案选择行：默认推荐 + HeroBuildStore 已保存方案（横向滚动，最多 6 套）
	var scheme_scroll := ScrollContainer.new()
	scheme_scroll.name = "SelectBuildSchemes"
	scheme_scroll.custom_minimum_size = Vector2(0, 92)
	scheme_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scheme_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sel_build_panel.add_child(scheme_scroll)
	sel_build_scheme_row = GridContainer.new()
	sel_build_scheme_row.name = "SelectBuildSchemeRow"
	sel_build_scheme_row.columns = 4
	sel_build_scheme_row.add_theme_constant_override("h_separation", 6)
	sel_build_scheme_row.add_theme_constant_override("v_separation", 6)
	scheme_scroll.add_child(sel_build_scheme_row)
	sel_build_rows = GridContainer.new()
	sel_build_rows.name = "SelectBuildRows"
	sel_build_rows.columns = 3
	sel_build_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_build_rows.add_theme_constant_override("h_separation", 6)
	sel_build_rows.add_theme_constant_override("v_separation", 6)
	sel_build_panel.add_child(sel_build_rows)
	# 两侧操作区：换英雄/返回大厅在左，确定/开始在右（不再占用右栏，避免挡住召唤/出装面板）
	var side_left := VBoxContainer.new()
	side_left.name = "SelectSideLeft"
	side_left.custom_minimum_size = Vector2(190, 0)
	side_left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side_left.add_theme_constant_override("separation", 10)
	bottom.add_child(side_left)
	bottom.move_child(side_left, 0)
	var side_right := VBoxContainer.new()
	side_right.name = "SelectSideRight"
	side_right.custom_minimum_size = Vector2(190, 0)
	side_right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	side_right.add_theme_constant_override("separation", 10)
	bottom.add_child(side_right)
	var leave := _sel_btn("返回大厅", UiKit.C_TEAM1, false, Vector2(180, 92))
	leave.name = "SelectLeave"
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	leave.pressed.connect(_on_select_leave)
	sel_back_btn = _sel_btn("换英雄", UiKit.C_PANEL_EDGE, false, Vector2(190, 86))
	sel_back_btn.name = "SelectBackToPick"
	sel_back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sel_back_btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	sel_back_btn.pressed.connect(_on_back_to_pick)
	side_left.add_child(sel_back_btn)
	leave.custom_minimum_size = Vector2(190, 86)
	side_left.add_child(leave)
	# 昵称输入：必填，输入即写缓存；未取名时确定/开始按钮不可用
	var name_box := VBoxContainer.new()
	name_box.name = "SelectNameBox"
	name_box.add_theme_constant_override("separation", 4)
	name_box.add_child(_sel_label("我的昵称（必填）", _sel_fs(UiKit.FS_XS), SEL_DIM, false))
	var name_edit := LineEdit.new()
	name_edit.name = "SelectNameEdit"
	name_edit.max_length = 12
	name_edit.placeholder_text = "输入昵称后开始游戏"
	name_edit.text = cached_name
	name_edit.custom_minimum_size = Vector2(190, 56)
	name_edit.add_theme_font_override("font", UiKit.font())
	name_edit.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	name_edit.add_theme_color_override("font_color", SEL_TEXT)
	name_edit.add_theme_color_override("font_placeholder_color", SEL_DIM)
	name_edit.add_theme_color_override("caret_color", SEL_GOLD)
	name_edit.add_theme_stylebox_override("normal", UiKit.skin_chip(UiKit.C_GOLD, 0.85))
	name_edit.add_theme_stylebox_override("focus", UiKit.skin_chip(UiKit.C_GOLD, 1.0))
	name_edit.text_changed.connect(_on_select_name_changed)
	name_box.add_child(name_edit)
	side_right.add_child(name_box)
	sel_name_edit = name_edit
	select_confirm_btn = _sel_btn("√  开始游戏", UiKit.C_GOLD, true, Vector2(190, 100))
	select_confirm_btn.name = "SelectConfirm"
	select_confirm_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	select_confirm_btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	select_confirm_btn.disabled = true
	select_confirm_btn.pressed.connect(_on_confirm)
	side_right.add_child(select_confirm_btn)
	# 技能悬浮详情浮层（悬停技能 chip 时弹出）
	sel_skill_tip = PanelContainer.new()
	sel_skill_tip.name = "SelectSkillTip"
	sel_skill_tip.visible = false
	sel_skill_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_skill_tip.custom_minimum_size = Vector2(430, 0)
	sel_skill_tip.add_theme_stylebox_override("panel", UiKit.skin_card(sel_side_col(), false, 0.96))
	var tip_v := VBoxContainer.new()
	tip_v.add_theme_constant_override("separation", 4)
	sel_skill_tip.add_child(tip_v)
	sel_skill_tip_title = _sel_label("", _sel_fs(UiKit.FS_MD), SEL_GOLD, false)
	tip_v.add_child(sel_skill_tip_title)
	sel_skill_tip_body = _sel_label("", _sel_fs(UiKit.FS_XS), SEL_TEXT, false)
	sel_skill_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_skill_tip_body.custom_minimum_size = Vector2(390, 0)
	tip_v.add_child(sel_skill_tip_body)
	root.add_child(sel_skill_tip)
	# 先入树让 HeroPreview 建好 SubViewport，再刷新立绘/席位/英雄条/BP 流程
	_update_selection_summary()
	_update_confirm_button_style()
	add_child(select_ui)
	_refresh_sel_preview(first_hero)
	_refresh_sel_seats(first_hero)
	_rebuild_hero_strip()
	_refresh_pick_display()
	_start_sel_draft()
	sel_pick_hint.text = "分路：%s · 只能选择%s英雄" % [sel_lane_name, sel_lane_role]
	_set_sel_stage(true)

# 圆盘首字徽记（英雄卡 / 席位 / mini 槽共用）
func _sel_disc(letter: String, color: Color, disc_size: int) -> Panel:
	var disc := Panel.new()
	disc.custom_minimum_size = Vector2(disc_size, disc_size)
	disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override("panel", UiKit.flat(1.0, int(disc_size * 0.5), 1, color.lightened(0.25), color.darkened(0.35), 0.0))
	var lab := _sel_label(letter, _sel_fs(UiKit.FS_MD), SEL_TEXT)
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(lab)
	return disc

# 顶部 mini 席位：kind 0=玩家 1=我方AI 2=敌方AI
func _create_mini_slot(idx: int, kind: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = ("MiniFoe_%d" % (idx + 1)) if kind == 2 else ("MiniOur_%d" % (idx + 1))
	slot.custom_minimum_size = Vector2(136, 84)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sty: StyleBoxFlat
	if kind == 0:
		sty = UiKit.skin_card(UiKit.C_GOLD, true, 0.9)
	elif kind == 1:
		sty = UiKit.skin_chip(sel_side_col(), 0.75)
	else:
		sty = UiKit.skin_chip(sel_foe_col(), 0.75)
	sty.content_margin_top = 2
	sty.content_margin_bottom = 2
	slot.add_theme_stylebox_override("panel", sty)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(h)
	var accent := UiKit.C_GOLD if kind == 0 else (sel_side_col() if kind == 1 else sel_foe_col())
	var avatar = SelectArt.Avatar.new("", accent, 56)
	h.add_child(avatar)
	if kind == 2:
		sel_foe_mini_avatars[idx] = avatar
	else:
		sel_mini_avatars[idx] = avatar
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var nm := ("我 · %s" % sel_lane_name) if kind == 0 else ("队友 %d" % (idx + 1) if kind == 1 else "AI %d" % (idx + 1))
	v.add_child(_sel_label(nm, int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)), SEL_DIM, false))
	var hero := _sel_label("选择中" if kind == 0 else ("待定" if kind == 1 else "未知"), _sel_fs(UiKit.FS_XS), SEL_GOLD if kind == 0 else SEL_SUB, false)
	v.add_child(hero)
	if kind == 2:
		sel_foe_mini_hero_labels[idx] = hero
	else:
		sel_mini_hero_labels[idx] = hero
	if kind == 0:
		sel_mini_hero_label = hero
	return slot

# 中部竖排席位：kind 0=玩家 1=我方AI 2=敌方AI
## 席位 → AI 昵称：己方 AI 用前 4 个（按非玩家席位顺序），敌方用后 5 个
func _sel_ai_name(kind: int, idx: int) -> String:
	if sel_ai_names.is_empty():
		return "AI"
	if kind == 2:
		var fi: int = 4 + idx
		return str(sel_ai_names[fi]) if fi < sel_ai_names.size() else "AI"
	var ai_ord: int = idx - (1 if idx > sel_player_seat else 0)
	var ai_i: int = clampi(ai_ord, 0, 3)
	return str(sel_ai_names[ai_i]) if ai_i < sel_ai_names.size() else "AI"

## 当前是否已有昵称（输入框实时文本优先，其次缓存）
func _has_player_name() -> bool:
	if sel_name_edit != null and is_instance_valid(sel_name_edit):
		return sel_name_edit.text.strip_edges() != ""
	return NameStore.player_name() != ""

## 昵称输入：写缓存 + 实时刷新自己席位文字 + 刷新按钮可用态
func _on_select_name_changed(t: String) -> void:
	var nm := t.strip_edges()
	if nm != "":
		NameStore.save_player_name(nm)
	if sel_player_name_label != null and is_instance_valid(sel_player_name_label):
		sel_player_name_label.text = "我 · %s" % (nm if nm != "" else "未取名")
		sel_player_name_label.add_theme_color_override("font_color", SEL_TEXT if nm != "" else Color(1.0, 0.58, 0.45))
	_update_confirm_button_style()

func _create_team_seat(idx: int, kind: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.name = ("SeatFoe_%d" % (idx + 1)) if kind == 2 else ("SeatOur_%d" % (idx + 1))
	slot.custom_minimum_size = Vector2(214, 138)
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var seat_sty: StyleBoxFlat
	if kind == 0:
		seat_sty = UiKit.skin_card(UiKit.C_GOLD, true, 0.9)
	elif kind == 1:
		seat_sty = UiKit.skin_chip(sel_side_col(), 0.72)
	else:
		seat_sty = UiKit.skin_chip(sel_foe_col(), 0.72)
	seat_sty.content_margin_left = 8
	seat_sty.content_margin_right = 8
	seat_sty.content_margin_top = 2
	seat_sty.content_margin_bottom = 2
	slot.add_theme_stylebox_override("panel", seat_sty)
	var accent := UiKit.C_GOLD if kind == 0 else (sel_side_col() if kind == 1 else sel_foe_col())
	var seat_h := HBoxContainer.new()
	seat_h.add_theme_constant_override("separation", 6)
	seat_h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(seat_h)
	var avatar = SelectArt.Avatar.new("", accent, 76)
	seat_h.add_child(avatar)
	if kind == 2:
		sel_foe_avatars[idx] = avatar
	else:
		sel_ally_avatars[idx] = avatar
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 1)
	seat_h.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(_sel_label("%d 号位" % (idx + 1), int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)), SEL_DIM, false))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_sel_label("我" if kind == 0 else ("队友" if kind == 1 else "敌方"), int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)), accent.lightened(0.3), false))
	v.add_child(head)
	# 席位显示昵称：自己=缓存昵称；队友/对手=本局随机 AI 名
	var pname := ""
	var pname_col := SEL_TEXT
	if kind == 0:
		var pn := NameStore.player_name()
		pname = "我 · %s" % (pn if pn != "" else "未取名")
		if pn == "":
			pname_col = Color(1.0, 0.58, 0.45)
	elif kind == 1:
		pname = "队友 %d · %s" % [idx + 1, _sel_ai_name(1, idx)]
	else:
		pname = "对手 %d · %s" % [idx + 1, _sel_ai_name(2, idx)]
	var pname_lab := _sel_label(pname, _sel_fs(UiKit.FS_XS), pname_col, false)
	v.add_child(pname_lab)
	if kind == 0:
		sel_player_name_label = pname_lab
	var hero_lab := _sel_label("选择中" if kind == 0 else ("待选" if kind == 1 else "未知"), _sel_fs(UiKit.FS_XS), SEL_GOLD if kind == 0 else SEL_SUB, false)
	hero_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hero_lab)
	var summ_lab := _sel_label("召唤师 · " + (_sel_summ_name(selected_summoner) if kind == 0 else ("待定" if kind == 1 else "未知")), int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)), SEL_DIM, false)
	v.add_child(summ_lab)
	if kind == 2:
		sel_foe_hero_labels[idx] = hero_lab
		sel_foe_summ_labels[idx] = summ_lab
	else:
		sel_ally_hero_labels[idx] = hero_lab
		sel_ally_summ_labels[idx] = summ_lab
	if kind == 0:
		sel_seat_hero_label = hero_lab
		sel_seat_summ_label = summ_lab
	return slot

# 顶部阶段块的装饰倒计时环（∞）
func _create_stage_ring() -> Control:
	var ring := SelRing.new()
	ring.name = "SelectStageRing"
	ring.custom_minimum_size = Vector2(72, 72)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lab := _sel_label("20", _sel_fs(UiKit.FS_XL), SEL_GOLD)
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(lab)
	sel_stage_ring_label = lab
	return ring

# 点职业 tab：刷新按钮态并重建底部英雄卡条
func _on_sel_tab_pressed(role: String) -> void:
	sel_active_role = role
	for r in sel_tab_buttons:
		_style_sel_tab(sel_tab_buttons[r], r == role)
	_rebuild_hero_strip()


# 选人两阶段切换：picking=true → 中央英雄面板（隐藏 3D 立绘与召唤/出装）；false → 3D 立绘 + 底部召唤/出装
func _set_sel_stage(picking: bool) -> void:
	sel_stage_picking = picking
	if sel_pick_layer != null and is_instance_valid(sel_pick_layer):
		sel_pick_layer.visible = picking
	if sel_preview_box != null and is_instance_valid(sel_preview_box):
		sel_preview_box.visible = not picking
	if sel_overlay != null and is_instance_valid(sel_overlay):
		sel_overlay.visible = not picking
	if sel_right_tabs != null and is_instance_valid(sel_right_tabs):
		sel_right_tabs.visible = not picking
	if sel_right_body != null and is_instance_valid(sel_right_body):
		sel_right_body.visible = not picking
	if sel_bottom_row != null and is_instance_valid(sel_bottom_row):
		sel_bottom_row.custom_minimum_size = Vector2(0, 0 if picking else 344)
	if sel_back_btn != null and is_instance_valid(sel_back_btn):
		sel_back_btn.visible = (not picking) and not sel_player_picked
	if picking:
		_hide_skill_tip()

func _on_back_to_pick() -> void:
	if sel_player_picked or sel_draft_done:
		_flash_tip("已锁定，无法更换英雄")
		return
	_set_sel_stage(true)

func _tip_dist(v: float) -> String:
	return "%.1f" % (v * 0.01) if v > 20.0 else "%.1f" % v

# 选人页技能悬浮提示用的“裸装 1 级英雄”探针：只用于按真实公式算数值，不进场、不画模型。
func _skill_tip_probe_for(hero_name: String) -> Hero:
	if _skill_tip_probe != null and _skill_tip_probe_name == hero_name:
		return _skill_tip_probe
	var cfg: Dictionary = hero_configs.get(hero_name, {})
	if cfg.is_empty():
		return null
	var h := Hero.new()
	h.display_name = hero_name
	h.team = int(Config.player_team)
	h.level = 1
	var hp := maxf(1.0, float(cfg.get("max_health", 3300.0)))
	h.base_health = hp
	h.max_health = hp
	h.health = hp
	h.actual_max_health = hp
	var atk := float(cfg.get("attack", 170.0))
	h.base_attack = atk
	h.attack = atk
	h.actual_attack_damage = atk
	h.bonus_attack = 0.0
	h.base_ability_power = 0.0
	h.ability_power = 0.0
	h.actual_ability_power = 0.0
	h.bonus_health = 0.0
	h.bonus_move_speed = 0.0
	h.skill_levels = [1, 1, 1]
	h.donghuang_orbs = 3          # 东皇二技能按满能量体预览发数
	h.taiyi_q_timer = 5.0         # 太乙一技能按满蓄力预览伤害
	_skill_tip_probe = h
	_skill_tip_probe_name = hero_name
	return h

func _skill_tip_max_level(idx: int) -> int:
	if idx >= 3: return 1
	return Hero.SKILL_MAX_LEVEL if idx < 2 else Hero.ULTIMATE_MAX_LEVEL

func _skill_tip_damage_at(probe: Hero, idx: int, lv: int) -> Dictionary:
	if probe == null or idx < 0 or idx >= probe.skill_levels.size():
		return {}
	probe.skill_levels[idx] = lv
	return SkillDatabase.get_skill_icon_damage(probe, idx)

func _skill_tip_fmt_damage(d: Dictionary) -> String:
	if not bool(d.get("valid", false)):
		return ""
	var parts: Array = []
	var dm := int(d.get("dmg", 0))
	if dm > 0:
		parts.append("%s %d" % ["法术" if bool(d.get("magic", false)) else "物理", dm])
	if d.has("dmg2"):
		var dm2 := int(d.get("dmg2", 0))
		if dm2 > 0:
			parts.append("%s %d" % ["法术" if bool(d.get("magic2", false)) else "物理", dm2])
	return " / ".join(parts)

func _skill_tip_raw_damage(sk: Skill) -> String:
	if sk == null:
		return ""
	var parts: Array = []
	if sk.phy_damage > 0.0:
		parts.append("物理 %d" % int(round(sk.phy_damage)))
	var mag := maxf(sk.mag_damage, sk.damage)
	if mag > 0.0:
		parts.append("法术 %d" % int(round(mag)))
	return " / ".join(parts)

func _skill_tip_damage_text(sk: Skill, probe: Hero, idx: int, max_lv: int) -> String:
	if probe != null:
		var s1 := _skill_tip_fmt_damage(_skill_tip_damage_at(probe, idx, 1))
		var sm := _skill_tip_fmt_damage(_skill_tip_damage_at(probe, idx, max_lv))
		if s1 == "" and sm == "":
			s1 = _skill_tip_raw_damage(sk)
		if sm != "" and sm != s1:
			return "伤害（裸装）：%s（技能1级）→ %s（技能满级）" % [s1, sm]
		if s1 != "":
			return "伤害（裸装）：%s" % s1
	var raw := _skill_tip_raw_damage(sk)
	return "伤害：%s" % raw if raw != "" else ""

func _skill_tip_fx(probe: Hero, idx: int, lv: int) -> Dictionary:
	var res := {"count": 0, "unit": "", "lines": [], "texts": []}
	if probe == null or idx < 0 or idx >= probe.skill_levels.size():
		return res
	probe.skill_levels[idx] = lv
	var fx: Dictionary = SkillDatabase.get_skill_fx(probe, idx)
	res["count"] = int(fx.get("count", 0))
	res["unit"] = str(fx.get("unit", ""))
	var lines: Array = []
	for e in fx.get("fx", []):
		var line := _skill_tip_effect_text(e)
		if line != "":
			lines.append(line)
	res["lines"] = lines
	res["texts"] = fx.get("texts", [])
	return res

func _skill_tip_effect_text(e: Dictionary) -> String:
	var t := str(e.get("t", ""))
	var v := float(e.get("v", 0.0))
	var d := float(e.get("d", 0.0))
	match t:
		"slow": return "减速 %d%% · %.1f秒" % [int(round(v)), d]
		"selfspeed": return "移速 +%d%% · %.1f秒" % [int(round(v)), d]
		"msup": return "移速 +%d · %.1f秒" % [int(round(v)), d]
		"stun": return "眩晕 %.1f秒" % v
		"knockup": return "击飞 %.1f秒" % v
		"freeze": return "冰冻 %.1f秒" % v
		"suppress": return "压制 %.1f秒" % v
		"bt": return "霸体 %.1f秒" % v
		"unsel": return "无法选中 %.1f秒" % v
		"shield": return "护盾 %d" % int(round(v))
		"heal": return "回复 %d" % int(round(v))
		"defup": return "双抗 +%d · %.1f秒" % [int(round(v)), d]
		"defdn": return "双防 -%d%% · %.1f秒" % [int(round(v)), d]
		"armup": return "护甲 +%d · %.1f秒" % [int(round(v)), d]
		"armdn": return "护甲 -%d%% · %.1f秒" % [int(round(v)), d]
		"armred": return "护甲 -%d · %.1f秒" % [int(round(v)), d]
		"mrup": return "魔抗 +%d · %.1f秒" % [int(round(v)), d]
		"mrdn": return "魔抗 -%d · %.1f秒" % [int(round(v)), d]
		"asup": return "攻速 +%d%% · %.1f秒" % [int(round(v)), d]
		"asdn": return "攻速 -%d%% · %.1f秒" % [int(round(v)), d]
		"atkdn": return "攻击 -%d%% · %.1f秒" % [int(round(v)), d]
		"cleanse": return "净化控制"
	return ""

func _skill_tip_raw_effects(sk: Skill) -> String:
	if sk == null:
		return ""
	var parts: Array = []
	if sk.applies_stun > 0.0: parts.append("眩晕 %.1f秒" % sk.applies_stun)
	if sk.applies_knockup > 0.0: parts.append("击飞 %.1f秒" % sk.applies_knockup)
	if sk.applies_slow > 0.0: parts.append("减速 %d%% · %.1f秒" % [int(round(sk.applies_slow * 100.0)), sk.slow_duration])
	return "；".join(parts)

# 技能悬浮详情（名称 / 类型 / 冷却 / 具体伤害与逐级成长 / 弹数 / 控制与增益数值 / 范围）
func _build_skill_tip_lines(sk: Skill, idx: int) -> Array:
	var lines: Array = []
	if sk != null:
		var max_lv := _skill_tip_max_level(idx)
		var meta := "类型：%s · 冷却 %.1fs" % [_sel_skill_type(int(sk.type)), sk.cooldown]
		var cd_max := maxf(0.0, sk.cooldown - sk.cd_bonus * float(max_lv - 1))
		if absf(cd_max - sk.cooldown) > 0.05:
			meta += "（满级 %.1fs）" % cd_max
		if sk.mana_cost > 0:
			var mana_max := maxi(0, sk.mana_cost - int(round(sk.power_bonus * float(max_lv - 1))))
			meta += " · 法力 %d" % sk.mana_cost
			if mana_max != sk.mana_cost:
				meta += "（满级 %d）" % mana_max
		lines.append(meta)

		var probe := _skill_tip_probe_for(selected_hero_type)
		var dmg_text := _skill_tip_damage_text(sk, probe, idx, max_lv)
		if dmg_text != "":
			lines.append(dmg_text)

		var f1 := _skill_tip_fx(probe, idx, 1)
		var fm := _skill_tip_fx(probe, idx, max_lv)
		var c1 := int(f1["count"])
		var cm := int(fm["count"])
		if c1 > 1 or cm > 1:
			var unit := str(fm["unit"]) if str(fm["unit"]) != "" else str(f1["unit"])
			if c1 != cm and c1 > 1 and cm > 1:
				lines.append("弹数：%d%s（技能1级）→ %d%s（技能满级）" % [c1, unit, cm, unit])
			else:
				lines.append("弹数：%d%s" % [maxi(c1, cm), unit])

		var e1: Array = f1["lines"]
		var em: Array = fm["lines"]
		var s1 := "；".join(e1)
		var sm := "；".join(em)
		if s1 != "" or sm != "":
			if s1 == sm:
				lines.append("效果：" + s1)
			else:
				if s1 != "": lines.append("技能1级效果：" + s1)
				if sm != "": lines.append("技能满级效果：" + sm)
		else:
			var raw_fx := _skill_tip_raw_effects(sk)
			if raw_fx != "": lines.append("效果：" + raw_fx)

		var texts: Array = fm.get("texts", [])
		if texts.is_empty():
			texts = f1.get("texts", [])
		for txt in texts:
			lines.append("· " + str(txt))

		if sk.shield_amount > 0.0 and sk.skill_name != "大变活人":
			lines.append("护盾 %d" % int(round(sk.shield_amount)))
		if sk.restore > 0:
			var rest_max := sk.restore + int(round(sk.restore_bonus * float(max_lv - 1)))
			lines.append("可存储 %d 层（满级 %d 层）" % [sk.restore, rest_max])
		if sk.cast_range > 0.0: lines.append("施法距离 %s 米" % _tip_dist(sk.cast_range))
		if sk.bullet_range > 0.0: lines.append("弹道距离 %s 米" % _tip_dist(sk.bullet_range))
		if sk.radius > 0.0: lines.append("范围半径 %s 米" % _tip_dist(sk.radius))
		if sk.self_displacement > 0.0: lines.append("位移 %s 米" % _tip_dist(sk.self_displacement))
		if sk.duration > 0.0: lines.append("持续 %.1f 秒" % sk.duration)
	return lines

func _show_skill_tip(sk: Skill, idx: int) -> void:
	if sel_skill_tip == null or not is_instance_valid(sel_skill_tip): return
	if sel_stage_picking: return
	sel_skill_tip_title.text = "%d  %s" % [idx + 1, sk.skill_name if sk != null else "技能"]
	var lines := _build_skill_tip_lines(sk, idx)
	sel_skill_tip_body.text = "\n".join(lines) if not lines.is_empty() else "（无详细数据）"
	sel_skill_tip.visible = true
	sel_skill_tip.reset_size()
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var sz: Vector2 = sel_skill_tip.size
	var tpos := mp + Vector2(20, -sz.y - 16)
	tpos.x = clampf(tpos.x, 8.0, maxf(8.0, vs.x - sz.x - 8.0))
	tpos.y = clampf(tpos.y, 8.0, maxf(8.0, vs.y - sz.y - 8.0))
	sel_skill_tip.position = tpos

func _hide_skill_tip() -> void:
	if sel_skill_tip != null and is_instance_valid(sel_skill_tip):
		sel_skill_tip.visible = false


func _style_sel_tab(btn: Button, active: bool) -> void:
	if btn == null: return
	var accent := UiKit.C_GOLD if active else UiKit.C_PANEL_EDGE
	var fc := Color(0.07, 0.08, 0.12) if active else SEL_TEXT
	btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, active))
	btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, active))
	btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, active))
	btn.add_theme_color_override("font_color", fc)
	btn.add_theme_color_override("font_hover_color", Color(0.04, 0.05, 0.08) if active else Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", fc)

# 按当前职业过滤重建底部英雄卡条；保留已选英雄高亮
func _rebuild_hero_strip() -> void:
	if sel_hero_strip == null: return
	for c in sel_hero_strip.get_children():
		sel_hero_strip.remove_child(c)
		c.queue_free()
	selected_hero_card = null
	var taken_roles := _team_roles_taken(0)
	for hero_name in hero_configs:
		var cfg: Dictionary = hero_configs[hero_name]
		var role: String = str(cfg.get("role", ""))
		if sel_active_role != "全部" and role != sel_active_role: continue
		var role_color: Color = ROLE_COLORS.get(role, Color.GRAY)
		var card := _create_hero_card(hero_name, role, role_color)
		sel_hero_strip.add_child(card)
		if sel_taken.has(str(hero_name)):
			# 叉选：已选英雄置灰 + 职责小字改「已被选」
			_style_card(card, Color(0.42, 0.42, 0.48), false)
			card.modulate = Color(0.62, 0.62, 0.66)
			var inner = card.get_child(0)
			if inner != null and inner.get_child_count() >= 3 and inner.get_child(2) is Label:
				var role_lab := inner.get_child(2) as Label
				role_lab.text = "已被选"
				role_lab.add_theme_color_override("font_color", Color(1.0, 0.48, 0.42))
			continue
		if taken_roles.has(role):
			# 同队职责唯一：本队已有该职责的卡置灰不可点
			_style_card(card, Color(0.42, 0.42, 0.48), false)
			card.modulate = Color(0.7, 0.68, 0.6)
			var inner2 = card.get_child(0)
			if inner2 != null and inner2.get_child_count() >= 3 and inner2.get_child(2) is Label:
				var role_lab2 := inner2.get_child(2) as Label
				role_lab2.text = "本队已有%s" % role
				role_lab2.add_theme_color_override("font_color", Color(0.95, 0.76, 0.35))
			continue
		if not _is_player_role(str(hero_name)):
			# 固定分路：非本分路英雄置灰不可点
			_style_card(card, Color(0.42, 0.42, 0.48), false)
			card.modulate = Color(0.58, 0.6, 0.66)
			var inner3 = card.get_child(0)
			if inner3 != null and inner3.get_child_count() >= 3 and inner3.get_child(2) is Label:
				var role_lab3 := inner3.get_child(2) as Label
				role_lab3.text = "分路不符"
				role_lab3.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
			continue
		if hero_name == selected_hero_type:
			_style_card(card, role_color, true)
			selected_hero_card = card

# 玩家席位/顶部 mini 槽跟随选中英雄（已锁定后由 _refresh_pick_display 接管）
func _refresh_sel_seats(hero_name: String) -> void:
	if sel_player_picked: return
	var txt := hero_name if hero_name != "" else "选择中"
	if sel_seat_hero_label:
		sel_seat_hero_label.text = txt
		sel_seat_hero_label.add_theme_color_override("font_color", SEL_GOLD)
	if sel_mini_hero_label:
		sel_mini_hero_label.text = txt
	var av = sel_ally_avatars[sel_player_seat] if sel_player_seat < sel_ally_avatars.size() else null
	if av != null:
		av.set_hero(hero_name)
	var mav = sel_mini_avatars[sel_player_seat] if sel_player_seat < sel_mini_avatars.size() else null
	if mav != null:
		mav.set_hero(hero_name)

# ======================= 拟真 BP 选人流程 =======================
# 召唤师配置值可能是 id 或中文名（如大禹「治疗术」），统一转 id
func _sel_summ_id(value: String) -> String:
	match value:
		"flash", "sprint", "teleport", "heal", "execute", "frenzy", "stun", "cleanse_summoner", "weaken", "smite":
			return value
		"闪现": return "flash"
		"疾跑": return "sprint"
		"传送": return "teleport"
		"治疗术": return "heal"
		"终结": return "execute"
		"狂暴": return "frenzy"
		"晕眩": return "stun"
		"净化": return "cleanse_summoner"
		"弱化": return "weaken"
		"惩击": return "smite"
	return value

func _hero_summ_id(hero_name: String) -> String:
	return _sel_summ_id(str(hero_configs.get(hero_name, {}).get("summoner", "flash")))

func _find_summ_card(sid: String) -> Panel:
	if select_ui == null: return null
	var root := select_ui.get_node_or_null("SelectRoot")
	if root == null: return null
	return root.find_child("SummCard_" + sid, true, false) as Panel

# 玩家未手动改过召唤师时，自动跟随当前英雄的推荐召唤师
func _apply_default_summoner(hero_name: String) -> void:
	if sel_summ_manual: return
	if hero_name == "" or not hero_configs.has(hero_name): return
	var sid := _hero_summ_id(hero_name)
	if sid == "": return
	if selected_summoner == sid:
		if selected_summ_card == null:
			selected_summ_card = _find_summ_card(sid)
		return
	_on_summoner_selected(sid, _sel_summ_name(sid), _find_summ_card(sid))

func _flash_tip(msg: String) -> void:
	if sel_tip_label == null: return
	sel_tip_label.text = msg
	sel_tip_label.visible = true
	sel_tip_time = 1.6

func _start_sel_draft() -> void:
	sel_draft_active = true
	sel_draft_done = false
	sel_draft_step = 0
	sel_draft_time = SEL_DRAFT_TURN_TIME
	sel_ai_timer = 0.0
	sel_player_picked = false
	sel_player_summ = "flash"
	_begin_draft_step()

func _draft_order_info() -> Array:
	return SEL_DRAFT_ORDER[clampi(sel_draft_step, 0, 9)]

func _draft_team() -> int:
	return int(_draft_order_info()[0])

func _draft_seat() -> int:
	return int(_draft_order_info()[1])

func _is_player_turn() -> bool:
	if not sel_draft_active or sel_draft_done or sel_player_picked: return false
	return _draft_team() == 0 and _draft_seat() == sel_player_seat

func _begin_draft_step() -> void:
	sel_draft_time = SEL_DRAFT_TURN_TIME
	sel_ai_timer = 0.0
	sel_ai_wait = randf_range(1.2, 2.2)
	_update_draft_stage()
	_update_confirm_button_style()
	if _is_player_turn():
		_flash_tip("轮到我方 · %d 号位，请选择英雄" % (sel_player_seat + 1))

func _update_draft_stage() -> void:
	var left := int(ceil(maxf(0.0, sel_draft_time)))
	if sel_stage_ring_label:
		sel_stage_ring_label.text = str(left)
	if sel_stage_sub_label:
		sel_stage_sub_label.text = "%s选择 · 剩余 %ds" % ["我方" if _draft_team() == 0 else "敌方", left]

func _update_sel_draft(delta: float) -> void:
	if sel_tip_time > 0.0:
		sel_tip_time -= delta
		if sel_tip_time <= 0.0 and sel_tip_label:
			sel_tip_label.visible = false
	if sel_draft_done:
		return
	if not sel_draft_active: return
	sel_draft_time = maxf(0.0, sel_draft_time - delta)
	_update_draft_stage()
	if _is_player_turn():
		if sel_draft_time <= 0.0:
			_lock_player_pick(selected_hero_type)
	else:
		sel_ai_timer += delta
		if sel_ai_timer >= sel_ai_wait or sel_draft_time <= 0.0:
			_ai_pick_current()

func _advance_draft() -> void:
	sel_draft_step += 1
	if sel_draft_step >= 10:
		_finish_draft()
	else:
		_begin_draft_step()

func _finish_draft() -> void:
	sel_draft_active = false
	sel_draft_done = true
	sel_draft_time = 0.0
	if sel_stage_title_label: sel_stage_title_label.text = "双方阵容已定"
	if sel_stage_sub_label: sel_stage_sub_label.text = "进入对局加载…"
	if sel_stage_ring_label: sel_stage_ring_label.text = "√"
	_update_confirm_button_style()
	_flash_tip("双方阵容已定")
	# 直接进入加载界面，加载完成后再真正开局
	if selected_hero_type == "":
		selected_hero_type = _random_untaken_hero()
	_start_game(selected_hero_type, selected_summoner)

# 玩家落位：点「确定选择」/ 超时锁定当前预览（无预览则随机）
func _lock_player_pick(preview_name: String) -> void:
	if sel_player_picked or not sel_draft_active or sel_draft_done: return
	var pick := preview_name
	if not _is_player_role(pick) or sel_taken.has(pick) or not hero_configs.has(pick):
		pick = _random_lane_hero()
	if pick == "":
		pick = _random_untaken_hero()
	if pick == "": return
	selected_hero_type = pick
	_apply_default_summoner(pick)
	sel_player_summ = selected_summoner
	sel_ally_picks[sel_player_seat] = pick
	sel_taken[pick] = true
	sel_player_picked = true
	_set_sel_stage(false)
	_refresh_sel_seats(pick)
	_refresh_pick_display()
	_rebuild_hero_strip()
	_flash_tip("已锁定 %s，等待其他席位…" % pick)
	_advance_draft()

func _random_untaken_hero() -> String:
	var pool: Array = []
	for hero_name in hero_configs:
		if not sel_taken.has(str(hero_name)):
			pool.append(str(hero_name))
	if pool.is_empty(): return ""
	return str(pool[randi() % pool.size()])

# 该队已选英雄的职责列表（过滤空席）
func _team_roles_taken(team: int) -> Array:
	var picks: Array = sel_ally_picks if team == 0 else sel_enemy_picks
	var roles: Array = []
	for p in picks:
		var pname := str(p)
		if pname == "" or not hero_configs.has(pname): continue
		var role := _hero_role(pname)
		if role != "" and not roles.has(role):
			roles.append(role)
	return roles

# 该队是否还能选这名英雄：合法 + 全局未被选 + 本队没有同职责
func _can_pick_hero(hero_name: String, team: int) -> bool:
	if hero_name == "" or not hero_configs.has(hero_name): return false
	if sel_taken.has(hero_name): return false
	var role := _hero_role(hero_name)
	if role == "": return false
	return not _team_roles_taken(team).has(role)

# 该英雄是否属于玩家的固定分路职责
func _is_player_role(hero_name: String) -> bool:
	return hero_name != "" and _hero_role(hero_name) == sel_lane_role

# 玩家本局可选的英雄：分路职责匹配 + 既有的全局/本队唯一校验
func _can_player_pick(hero_name: String) -> bool:
	return _is_player_role(hero_name) and _can_pick_hero(hero_name, 0)

func _first_lane_hero() -> String:
	for hero_name in hero_configs:
		if _is_player_role(str(hero_name)):
			return str(hero_name)
	return ""

# 分路内随机一名未选英雄（超时锁定/初始兜底）
func _random_lane_hero() -> String:
	var pool: Array = []
	for hero_name in hero_configs:
		var hn := str(hero_name)
		if sel_taken.has(hn) or not _is_player_role(hn): continue
		pool.append(hn)
	if pool.is_empty(): return ""
	return str(pool[randi() % pool.size()])

# 本队尚缺职责里随机一名未选英雄（极端无解时退化为任意未选）
func _random_pickable_hero(team: int) -> String:
	var taken_roles := _team_roles_taken(team)
	var pool: Array = []
	var fallback_pool: Array = []
	for hero_name in hero_configs:
		var hn := str(hero_name)
		if sel_taken.has(hn): continue
		var role := _hero_role(hn)
		if role == "" or taken_roles.has(role): continue
		fallback_pool.append(hn)
		# 我方 AI 不占玩家的固定分路，该职责留给玩家
		if team == 0 and role == sel_lane_role: continue
		pool.append(hn)
	if pool.is_empty(): pool = fallback_pool
	if pool.is_empty(): return _random_untaken_hero()
	return str(pool[randi() % pool.size()])

# AI 选人：只补本队尚缺职责，同职责内随机
func _choose_ai_hero(team: int, seat: int) -> String:
	return _random_pickable_hero(team)

func _ai_pick_current() -> void:
	if not sel_draft_active or sel_draft_done: return
	var team := _draft_team()
	var seat := _draft_seat()
	if team == 0 and seat == sel_player_seat:
		_lock_player_pick(selected_hero_type)
		return
	var pick := _choose_ai_hero(team, seat)
	if pick == "":
		_advance_draft()
		return
	if team == 0:
		sel_ally_picks[seat] = pick
	else:
		sel_enemy_picks[seat] = pick
	sel_taken[pick] = true
	_refresh_pick_display()
	_rebuild_hero_strip()
	_flash_tip("%s · %d 号位 选择了 %s" % ["我方" if team == 0 else "敌方", seat + 1, pick])
	_advance_draft()

# 席位/顶栏同步已选结果（玩家未落位时保留其预览文字）
func _refresh_pick_display() -> void:
	for i in 5:
		var ally := str(sel_ally_picks[i]) if i < sel_ally_picks.size() else ""
		var foe := str(sel_enemy_picks[i]) if i < sel_enemy_picks.size() else ""
		var ah: Label = sel_ally_hero_labels[i] if i < sel_ally_hero_labels.size() else null
		var asumm: Label = sel_ally_summ_labels[i] if i < sel_ally_summ_labels.size() else null
		if ah != null and (ally != "" or i != sel_player_seat):
			ah.text = ally if ally != "" else "待选"
			ah.add_theme_color_override("font_color", SEL_GOLD if (i == sel_player_seat and ally != "") else (SEL_TEXT if ally != "" else SEL_SUB))
		if asumm != null and ally != "":
			asumm.text = "召唤师 · " + (_sel_summ_name(selected_summoner) if i == sel_player_seat else _sel_summ_name(_hero_summ_id(ally)))
		var aav = sel_ally_avatars[i] if i < sel_ally_avatars.size() else null
		if aav != null and (ally != "" or i != sel_player_seat):
			aav.set_hero(ally)
		var am: Label = sel_mini_hero_labels[i] if i < sel_mini_hero_labels.size() else null
		if am != null and (ally != "" or i != sel_player_seat):
			am.text = ally if ally != "" else "待定"
		var mav = sel_mini_avatars[i] if i < sel_mini_avatars.size() else null
		if mav != null and (ally != "" or i != sel_player_seat):
			mav.set_hero(ally)
		var fh: Label = sel_foe_hero_labels[i] if i < sel_foe_hero_labels.size() else null
		var fsumm: Label = sel_foe_summ_labels[i] if i < sel_foe_summ_labels.size() else null
		if fh != null:
			fh.text = foe if foe != "" else "未知"
			fh.add_theme_color_override("font_color", SEL_TEXT if foe != "" else SEL_SUB)
		if fsumm != null:
			fsumm.text = "召唤师 · " + (_sel_summ_name(_hero_summ_id(foe)) if foe != "" else "未知")
		var fav = sel_foe_avatars[i] if i < sel_foe_avatars.size() else null
		if fav != null:
			fav.set_hero(foe)
		var fm: Label = sel_foe_mini_hero_labels[i] if i < sel_foe_mini_hero_labels.size() else null
		if fm != null:
			fm.text = foe if foe != "" else "未知"
		var fmav = sel_foe_mini_avatars[i] if i < sel_foe_mini_avatars.size() else null
		if fmav != null:
			fmav.set_hero(foe)

# —— 右栏 召唤 / 出装 ——
func _on_right_tab_pressed(tab: String) -> void:
	sel_right_tab = tab
	_style_right_tab(sel_summ_tab_btn, tab == "召唤")
	_style_right_tab(sel_build_tab_btn, tab == "出装")
	if sel_summ_panel: sel_summ_panel.visible = tab == "召唤"
	if sel_build_panel: sel_build_panel.visible = tab == "出装"
	if tab == "出装":
		_rebuild_build_panel()

# 右栏 40 高双 tab：压掉按钮皮肤上下内边距，保证行高固定 40
func _style_right_tab(btn: Button, active: bool) -> void:
	if btn == null: return
	_style_sel_tab(btn, active)
	for state in ["normal", "hover", "pressed"]:
		var sb: StyleBox = btn.get_theme_stylebox(state)
		if sb is StyleBoxFlat:
			var flat_sb := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
			flat_sb.content_margin_top = 0
			flat_sb.content_margin_bottom = 0
			btn.add_theme_stylebox_override(state, flat_sb)

# 切换英雄时载入出装顺序：本局 override > 已保存方案（默认套第一套）> 内置推荐方案1
func _load_build_for_hero(hero_name: String, prefer_saved: bool = true) -> void:
	if sel_build_rows == null or not hero_configs.has(hero_name): return
	sel_build_hero = hero_name
	var ov: Array = ItemDatabase.get_recommended_override(hero_name)
	if not ov.is_empty():
		sel_build_ids = ov.duplicate()
	elif prefer_saved and not HeroBuildStore.get_builds(hero_name).is_empty():
		# 选人页直接沿用玩家保存的第一套方案，不再无条件回落到职业默认
		sel_build_ids = _clean_build_items(HeroBuildStore.get_builds(hero_name)[0].get("items", []))
	else:
		sel_build_ids = _preset_build(hero_name, 0)
	_rebuild_build_panel()

# 内置推荐方案（每英雄 3 套，直接给玩家选；不足时回落职业方案）
func _preset_builds(hero_name: String) -> Array:
	if hero_name == "" or not hero_configs.has(hero_name): return []
	var vs: Array = ItemDatabase.get_recommended_variants(hero_name)
	if vs.is_empty():
		vs = ItemDatabase.get_recommended_variants(str(hero_configs[hero_name].get("role", "战士")))
	return vs

func _preset_build(hero_name: String, idx: int) -> Array:
	var vs := _preset_builds(hero_name)
	if vs.is_empty(): return []
	return _clean_build_items(vs[clampi(idx, 0, vs.size() - 1)])

# 方案按钮 tooltip：列出 6 件装备名
func _build_items_tooltip(items: Array) -> String:
	var names: PackedStringArray = []
	for id in items:
		var it: Dictionary = ItemDatabase.get_item(str(id))
		names.append(str(it.get("name", id)))
	return " · ".join(names)

func _clean_build_items(src: Array) -> Array:
	var out: Array = []
	for it in src:
		var id := str(it)
		if id != "" and not out.has(id) and not ItemDatabase.get_item(id).is_empty():
			out.append(id)
	return out.slice(0, 6)

func _rebuild_build_panel() -> void:
	if sel_build_rows == null: return
	for c in sel_build_rows.get_children():
		sel_build_rows.remove_child(c)
		c.queue_free()
	for i in sel_build_ids.size():
		sel_build_rows.add_child(_build_row(i, str(sel_build_ids[i])))
	_rebuild_build_schemes()

# 备战方案按钮行：内置推荐方案（每英雄 3 套）+ 已保存方案 + 恢复推荐；与当前列表一致的高亮金 filled
func _rebuild_build_schemes() -> void:
	if sel_build_scheme_row == null: return
	for c in sel_build_scheme_row.get_children():
		sel_build_scheme_row.remove_child(c)
		c.queue_free()
	if sel_build_hero == "": return
	var current_scheme := _current_build_scheme_name()
	var presets := _preset_builds(sel_build_hero)
	for i in presets.size():
		var pitems: Array = _clean_build_items(presets[i])
		var pbtn := _sel_btn("推荐方案%d" % (i + 1), UiKit.C_TEAM0, pitems == sel_build_ids, Vector2(180, 40))
		pbtn.name = "BuildPreset_%d" % i
		pbtn.tooltip_text = _build_items_tooltip(pitems)
		pbtn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
		pbtn.pressed.connect(_on_build_preset_pressed.bind(i))
		sel_build_scheme_row.add_child(pbtn)
	var builds: Array = HeroBuildStore.get_builds(sel_build_hero)
	for i in mini(builds.size(), 6):
		var bname := str(builds[i].get("name", ""))
		var btn := _sel_btn(bname, UiKit.C_GOLD, bname == current_scheme, Vector2(180, 40))
		btn.name = "BuildScheme_%d" % i
		btn.tooltip_text = _build_items_tooltip(_clean_build_items(builds[i].get("items", [])))
		btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
		btn.pressed.connect(_on_build_scheme_pressed.bind(i))
		sel_build_scheme_row.add_child(btn)
	# 恢复推荐（并入方案网格末尾，省掉底部一行）
	var reset_btn := _sel_btn("恢复推荐", UiKit.C_GOLD, false, Vector2(180, 40))
	reset_btn.name = "SelectBuildRestore"
	reset_btn.tooltip_text = "回到内置推荐方案1"
	reset_btn.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	reset_btn.pressed.connect(_on_build_restore)
	sel_build_scheme_row.add_child(reset_btn)
	# 方案行按行数撑高（4 列一行；3 套内置 + 6 套自存 + 恢复 = 最多 3 行），避免被裁掉
	var rows := int(ceil(float(sel_build_scheme_row.get_child_count()) / 4.0))
	var sc := sel_build_scheme_row.get_parent()
	if sc is ScrollContainer:
		(sc as ScrollContainer).custom_minimum_size = Vector2(0, 6 + rows * 46)

func _current_build_scheme_name() -> String:
	if sel_build_hero == "": return ""
	for b in HeroBuildStore.get_builds(sel_build_hero):
		var items: Array = b.get("items", [])
		if items == sel_build_ids:
			return str(b.get("name", ""))
	return ""

func _on_build_scheme_default() -> void:
	if sel_build_hero == "": return
	ItemDatabase.set_recommended_override(sel_build_hero, [])
	_load_build_for_hero(sel_build_hero, false)

# 套用内置推荐方案：载入 6 件 + 写 override，对局内推荐/快买即按该方案
func _on_build_preset_pressed(idx: int) -> void:
	if sel_build_hero == "": return
	var items := _preset_build(sel_build_hero, idx)
	if items.is_empty(): return
	sel_build_ids = items
	ItemDatabase.set_recommended_override(sel_build_hero, sel_build_ids)
	_rebuild_build_panel()

# 套用备战方案：载入 6 件 + 写 override，对局内推荐/快买即按此方案
func _on_build_scheme_pressed(idx: int) -> void:
	if sel_build_hero == "": return
	var builds: Array = HeroBuildStore.get_builds(sel_build_hero)
	if idx < 0 or idx >= builds.size(): return
	var items: Array = _clean_build_items(builds[idx].get("items", []))
	if items.is_empty(): return
	sel_build_ids = items
	ItemDatabase.set_recommended_override(sel_build_hero, sel_build_ids)
	_rebuild_build_panel()

func _build_row(idx: int, item_id: String) -> PanelContainer:
	# 装备卡（卡宽 256）：左侧大图标 68 + 右侧「序号·名称」/「价格 · ↑↓」，名称与价格都完整显示
	var item: Dictionary = ItemDatabase.get_item(item_id) if item_id != "" else {}
	var nm := str(item.get("name", item_id))
	var cost := int(item.get("cost", 0))
	var tier := int(item.get("tier", 1))
	var card := PanelContainer.new()
	card.name = "BuildRow_%d" % idx
	card.custom_minimum_size = Vector2(0, 96)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cs: StyleBoxFlat = UiKit.skin_chip(UiKit.C_PANEL_EDGE, 0.8, 10)
	cs.content_margin_left = 8
	cs.content_margin_right = 8
	cs.content_margin_top = 4
	cs.content_margin_bottom = 4
	card.add_theme_stylebox_override("panel", cs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	row.add_child(SelectArt.ItemIcon.new(nm, tier, 64))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(v)
	# 第一行：序号 + 装备名（字号 FS_SM，不再截断）
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	v.add_child(top)
	var idx_lab := _sel_label("%d." % (idx + 1), _sel_fs(UiKit.FS_XS), SEL_GOLD, false)
	idx_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(idx_lab)
	var name_lab := _sel_label(nm, _sel_fs(UiKit.FS_SM), SEL_TEXT, false)
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lab.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	top.add_child(name_lab)
	# 第二行：价格（金色独立一行）+ 上调/下调
	var bot := HBoxContainer.new()
	bot.add_theme_constant_override("separation", 6)
	v.add_child(bot)
	var price_lab := _sel_label("%d 金" % cost, _sel_fs(UiKit.FS_SM), SEL_GOLD, false)
	price_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bot.add_child(price_lab)
	var up := _sel_btn("↑", UiKit.C_TEAM0, false, Vector2(44, 26))
	up.name = "BuildUp_%d" % idx
	up.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	up.disabled = idx <= 0
	up.pressed.connect(_on_build_move.bind(idx, -1))
	bot.add_child(up)
	var down := _sel_btn("↓", UiKit.C_TEAM0, false, Vector2(44, 26))
	down.name = "BuildDown_%d" % idx
	down.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_SM))
	down.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	down.disabled = idx >= sel_build_ids.size() - 1
	down.pressed.connect(_on_build_move.bind(idx, 1))
	bot.add_child(down)
	# 鼠标悬浮：弹出装备详情（属性 / 被动 / 主动 / 合成路径 / 价格）
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(_show_build_hover.bind(str(item_id), card))
	card.mouse_exited.connect(_hide_build_hover)
	return card
func _on_build_move(idx: int, dir: int) -> void:
	var j := idx + dir
	if idx < 0 or j < 0 or idx >= sel_build_ids.size() or j >= sel_build_ids.size(): return
	var tmp = sel_build_ids[idx]
	sel_build_ids[idx] = sel_build_ids[j]
	sel_build_ids[j] = tmp
	if sel_build_hero != "":
		ItemDatabase.set_recommended_override(sel_build_hero, sel_build_ids)
	_rebuild_build_panel()

func _on_build_restore() -> void:
	if sel_build_hero == "": return
	ItemDatabase.set_recommended_override(sel_build_hero, [])
	_load_build_for_hero(sel_build_hero, false)

# —— 召唤师卡悬停浮层 ——
func _on_summ_hover(sname: String, sid: String, card: Panel, hover: bool) -> void:
	if hover:
		_show_summ_hover(sname, sid, card)
	else:
		_hide_summ_hover()

func _hide_summ_hover() -> void:
	if sel_hover_panel != null and is_instance_valid(sel_hover_panel):
		sel_hover_panel.queue_free()
	sel_hover_panel = null

# 字符串数组拼接（避免 String.join 的 PackedStringArray 类型限制）
func _join_dot(parts: Array) -> String:
	var out := ""
	for p in parts:
		out = str(p) if out == "" else out + " · " + str(p)
	return out

func _join_plus(parts: Array) -> String:
	var out := ""
	for p in parts:
		out = str(p) if out == "" else out + " + " + str(p)
	return out

# —— 出装卡悬浮：装备详细信息浮层（属性 / 被动 / 主动 / 合成 / 价格）——
func _hide_build_hover() -> void:
	if sel_build_hover != null and is_instance_valid(sel_build_hover):
		sel_build_hover.queue_free()
	sel_build_hover = null

func _show_build_hover(item_id: String, card: Control) -> void:
	_hide_build_hover()
	if select_ui == null or card == null or item_id == "":
		return
	var item: Dictionary = ItemDatabase.get_item(item_id)
	if item.is_empty():
		return
	var root := select_ui.get_node_or_null("SelectRoot")
	if root == null:
		return
	var tier := int(item.get("tier", 1))
	var qcol: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)] if tier >= 1 else SEL_GOLD
	var panel := PanelContainer.new()
	panel.name = "BuildHover"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(qcol, true, 0.97))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(_sel_label(str(item.get("name", item_id)), _sel_fs(UiKit.FS_LG), qcol.lightened(0.25), false))
	var meta := "T%d · %d 金" % [tier, int(item.get("cost", 0))]
	var cls_map := {"attack": "物理", "magic": "法术", "defense": "防御", "boots": "鞋子",
		"jungle": "打野", "support": "游走", "survival": "保命", "attack_speed": "攻速"}
	var cls := str(item.get("class", ""))
	if cls != "":
		meta += " · " + str(cls_map.get(cls, cls))
	v.add_child(_sel_label(meta, _sel_fs(UiKit.FS_SM), SEL_SUB, false))
	# 属性行
	var stat_names := {"attack": "攻击", "magic_attack": "法强", "health": "生命", "armor": "物防",
		"magic_resist": "法防", "attack_speed": "攻速%", "crit_chance": "暴击%", "cooldown": "冷缩%",
		"speed": "移速", "lifesteal": "吸血%", "mana": "蓝量", "hp_regen": "回血",
		"armor_pen_percent": "物穿%", "magic_pen": "法穿"}
	var parts: Array = []
	for k in stat_names:
		var val := int(item.get(str(k), 0))
		if val != 0:
			parts.append("%s+%d" % [str(stat_names[k]), val])
	if not parts.is_empty():
		var sl := _sel_label("属性：" + _join_dot(parts), _sel_fs(UiKit.FS_SM), SEL_TEXT, false)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(390, 0)
		v.add_child(sl)
	var passive := str(item.get("passive", ""))
	if passive != "":
		var pl := _sel_label("被动：" + passive, _sel_fs(UiKit.FS_SM), SEL_GOLD, false)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(390, 0)
		v.add_child(pl)
	var active := str(item.get("active", ""))
	if active != "":
		var al := _sel_label("主动：" + active, _sel_fs(UiKit.FS_SM), Color(0.55, 0.85, 1.0), false)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size = Vector2(390, 0)
		v.add_child(al)
	var reqs: Array = item.get("requires", [])
	if not reqs.is_empty():
		var names: Array = []
		for rid in reqs:
			names.append(str(ItemDatabase.get_item(str(rid)).get("name", rid)))
		v.add_child(_sel_label("合成：" + _join_plus(names), _sel_fs(UiKit.FS_SM), SEL_SUB, false))
	(root as Control).add_child(panel)
	panel.size = panel.get_combined_minimum_size()
	var r: Rect2 = card.get_global_rect()
	var pos := Vector2(r.position.x - panel.size.x - 14.0, r.position.y)
	if pos.x < 16.0:
		pos.x = r.end.x + 14.0
	pos.x = clampf(pos.x, 16.0, 2400.0 - panel.size.x - 16.0)
	pos.y = clampf(pos.y, 16.0, 1400.0 - panel.size.y - 16.0)
	panel.position = pos
	sel_build_hover = panel

func _show_summ_hover(sname: String, sid: String, card: Panel) -> void:
	_hide_summ_hover()
	if select_ui == null or card == null: return
	var sk: Skill = SkillDatabase.get_skill(sid)
	var panel := PanelContainer.new()
	panel.name = "SummHover"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(SEL_SUMM_COLOR, true, 0.96))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(_sel_label(sname, _sel_fs(UiKit.FS_LG), SEL_GOLD, false))
	var meta := "冷却 %ds · 类型 %s" % [int(round(sk.cooldown)) if sk != null else 0, _sel_skill_type(int(sk.type) if sk != null else 0)]
	if sk != null and sk.cast_range > 0.0:
		meta += " · 施法距离 %.1f" % sk.cast_range
	v.add_child(_sel_label(meta, _sel_fs(UiKit.FS_SM), SEL_SUB, false))
	var desc := str(SUMMONER_DESCRIPTIONS.get(sname, ""))
	if desc != "":
		var dl := _sel_label(desc, _sel_fs(UiKit.FS_SM), SEL_TEXT, false)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(340, 0)
		v.add_child(dl)
	var tag := "已选" if sid == selected_summoner else ""
	if tag == "" and _hero_summ_id(selected_hero_type) == sid:
		tag = "推荐"
	if tag != "":
		v.add_child(_sel_label(tag, _sel_fs(UiKit.FS_SM), UiKit.C_GOLD, false))
	var root := select_ui.get_node_or_null("SelectRoot")
	if root == null: return
	(root as Control).add_child(panel)
	panel.size = panel.get_combined_minimum_size()
	var r: Rect2 = card.get_global_rect()
	var pos := Vector2(r.position.x, r.end.y + 16.0)
	if pos.y + panel.size.y > 1400.0 - 16.0:
		pos.y = r.position.y - panel.size.y - 16.0
	pos.x = clampf(pos.x, 16.0, 2400.0 - panel.size.x - 16.0)
	pos.y = clampf(pos.y, 16.0, 1400.0 - panel.size.y - 16.0)
	panel.position = pos
	sel_hover_panel = panel

func _create_hero_card(hero_name: String, role: String, role_color: Color) -> Panel:
	var card = Panel.new()
	card.name = "HeroCard_" + hero_name
	card.custom_minimum_size = Vector2(150, 152)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.add_theme_stylebox_override("panel", UiKit.skin_card(role_color, false, 0.72))
	var inner_v = VBoxContainer.new()
	inner_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner_v.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_v.add_theme_constant_override("separation", 0)
	card.add_child(inner_v)
	inner_v.add_child(SelectArt.Avatar.new(hero_name, role_color, 72))
	var name_label = Label.new()
	name_label.text = hero_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_XS))
	name_label.add_theme_color_override("font_color", SEL_TEXT)
	inner_v.add_child(name_label)
	var role_label = Label.new()
	role_label.text = role
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.add_theme_font_size_override("font_size", int(round(float(_sel_fs(UiKit.FS_XS)) * 0.85)))
	role_label.add_theme_color_override("font_color", role_color.lightened(0.35))
	inner_v.add_child(role_label)
	card.gui_input.connect(_on_hero_card_clicked.bind(hero_name, card, role_color))
	card.gui_input.connect(_on_hero_preview_input.bind(hero_name))
	card.mouse_entered.connect(_on_card_hover.bind(card, true, role_color))
	card.mouse_exited.connect(_on_card_hover.bind(card, false, role_color))
	return card

func _create_summ_card(sname: String, sid: String) -> Panel:
	# 紧凑竖排卡（图标上、名字下）：5 列 × 2 行一屏放下 10 个召唤师技能，无需滚动
	var card = Panel.new()
	card.name = "SummCard_" + sid
	card.custom_minimum_size = Vector2(96, 112)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiKit.skin_card(SEL_SUMM_COLOR, false, 0.72))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var glyph = SelectArt.SummonerGlyph.new(sname, 60)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(glyph)
	var lbl = Label.new()
	lbl.text = sname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _sel_fs(UiKit.FS_XS))
	lbl.add_theme_color_override("font_color", SEL_TEXT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lbl)
	card.gui_input.connect(_on_summ_card_clicked.bind(sid, sname, card))
	card.gui_input.connect(_on_summ_preview_input.bind(sname))
	card.mouse_entered.connect(_on_card_hover.bind(card, true, SEL_SUMM_COLOR))
	card.mouse_exited.connect(_on_card_hover.bind(card, false, SEL_SUMM_COLOR))
	card.mouse_entered.connect(_on_summ_hover.bind(sname, sid, card, true))
	card.mouse_exited.connect(_on_summ_hover.bind(sname, sid, card, false))
	return card
# 点/触英雄卡时同步 3D 立绘与玩家席位（独立监听，不影响既有选中回调）
func _on_hero_preview_input(event: InputEvent, hero_name: String) -> void:
	var is_click: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if not is_click: return
	if sel_taken.has(hero_name) or sel_player_picked: return
	if not _can_player_pick(hero_name): return
	_refresh_sel_preview(hero_name)
	_refresh_sel_seats(hero_name)

# 点/触召唤师卡时同步玩家席位的召唤师小字
func _on_summ_preview_input(event: InputEvent, sname: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_refresh_sel_summoner_seat(sname)
	elif event is InputEventScreenTouch and event.pressed:
		_refresh_sel_summoner_seat(sname)

func _refresh_sel_summoner_seat(sname: String) -> void:
	if sel_seat_summ_label:
		sel_seat_summ_label.text = "召唤师 · " + sname

func _on_card_hover(card: Panel, hover: bool, base_color: Color):
	if card == null or not is_instance_valid(card): return
	if card == selected_hero_card or card == selected_summ_card: return
	if hover:
		var st := UiKit.skin_card(base_color, false, 1.0)
		st.shadow_size = 5
		st.shadow_color = Color(base_color.r, base_color.g, base_color.b, 0.28)
		card.add_theme_stylebox_override("panel", st)
	else:
		card.add_theme_stylebox_override("panel", UiKit.skin_card(base_color, false, 0.72))
func _on_hero_card_clicked(event: InputEvent, hero_name: String, card: Panel, role_color: Color):
	# 桌面端 emulate_touch_from_mouse 会为鼠标点击生成合成触摸，跳过避免重复选中
	if Input.is_emulating_touch_from_mouse() and (event is InputEventScreenTouch):
		return
	var is_click := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_click = true
	elif event is InputEventScreenTouch and event.pressed:
		is_click = true
	if is_click:
		if sel_taken.has(hero_name):
			_flash_tip("该英雄已被选，不能重复选择")
			return
		if sel_player_picked or sel_draft_done:
			_flash_tip("已锁定，等待其他席位…")
			return
		if not _is_player_role(hero_name):
			_flash_tip("本局分路：%s · 只能选择%s英雄" % [sel_lane_name, sel_lane_role])
			return
		if not _can_pick_hero(hero_name, 0):
			_flash_tip("本队已有%s，不能重复职责" % _hero_role(hero_name))
			return
		_on_hero_selected(hero_name, card, role_color)

func _on_summ_card_clicked(event: InputEvent, sid: String, sname: String, card: Panel):
	# 桌面端 emulate_touch_from_mouse 会为鼠标点击生成合成触摸，跳过避免重复选中
	if Input.is_emulating_touch_from_mouse() and (event is InputEventScreenTouch):
		return
	var is_click := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		is_click = true
	elif event is InputEventScreenTouch and event.pressed:
		is_click = true
	if is_click:
		sel_summ_manual = true
		_hide_summ_hover()
		_on_summoner_selected(sid, sname, card)


func _on_hero_selected(type: String, card: Panel = null, role_color: Color = Color.WHITE):
	if selected_hero_card:
		var prev_role = hero_configs.get(selected_hero_type, {}).get("role", "")
		_style_card(selected_hero_card, ROLE_COLORS.get(prev_role, Color.GRAY), false)
	selected_hero_type = type
	selected_hero_card = card
	selected_skin_id = HeroSkinTable.selected_id(type)
	if card:
		_style_card(card, role_color, true)
	# 未手动改过召唤师时，换英雄自动跟随该英雄的推荐召唤师
	_apply_default_summoner(type)
	_refresh_sel_preview(type)
	# 选定英雄后：中央立绘支持滑动查看视角（拖动绕角色水平旋转 + 上下俯仰）
	if sel_preview_3d:
		sel_preview_3d.set_orbit_enabled(true)
	_load_build_for_hero(type)   # 右栏「出装」按该英雄载入推荐/已保存备战方案（切换英雄同刷）
	_set_sel_stage(false)
	_update_selection_summary()
	_update_confirm_button_style()

## 选人界面：切换当前英雄皮肤（写入 PlayerPrefs，进对局由 Hero 读取）
func _cycle_selected_skin() -> void:
	if selected_hero_type == "":
		return
	selected_skin_id = HeroSkinTable.cycle(selected_hero_type, selected_skin_id)
	HeroSkinTable.set_selected(selected_hero_type, selected_skin_id)
	_refresh_sel_preview(selected_hero_type)


func _on_summoner_selected(id: String, sname: String = "", card: Panel = null):
	selected_summoner = id
	if selected_summ_card:
		_style_card(selected_summ_card, SEL_SUMM_COLOR, false)
	selected_summ_card = card
	if card:
		_style_card(card, SEL_SUMM_COLOR, true)
	if select_summ_detail:
		var sdata = SkillDatabase.get_skill(id)
		var cd := 0.0
		if sdata:
			cd = sdata.cooldown
		select_summ_detail.text = "%s · 冷却 %d 秒\n%s" % [sname, int(round(cd)), SUMMONER_DESCRIPTIONS.get(sname, "")]
	_refresh_sel_summoner_seat(sname)
	_update_selection_summary()
	_update_confirm_button_style()

func _update_selection_summary():
	if not select_summary_label: return
	if selected_hero_type != "":
		var role = hero_configs[selected_hero_type].get("role", "")
		var summ_name := ""
		var summ_map := {"闪现": "flash", "疾跑": "sprint", "传送": "teleport", "治疗术": "heal", "终结": "execute", "狂暴": "frenzy", "晕眩": "stun", "净化": "cleanse_summoner", "弱化": "weaken", "惩击": "smite"}
		for sn in SUMMONER_DESCRIPTIONS:
			if summ_map.get(sn, "") == selected_summoner: summ_name = sn; break
		if summ_name != "":
			select_summary_label.text = "待开始：%s · %s + %s" % [role, selected_hero_type, summ_name]
			select_summary_label.add_theme_color_override("font_color", SEL_GOLD)
		else:
			select_summary_label.text = "已选英雄：%s（%s），请选择召唤师技能" % [selected_hero_type, role]
			select_summary_label.add_theme_color_override("font_color", SEL_TEXT)
	else:
		select_summary_label.text = "请先选英雄与召唤师技能"
		select_summary_label.add_theme_color_override("font_color", SEL_DIM)

func _update_confirm_button_style():
	if not select_confirm_btn: return
	var can := false
	var text := "等待其他席位…"
	if sel_draft_done:
		text = "双方阵容已定"
	elif not sel_draft_active:
		text = "等待开始…"
	elif sel_player_picked:
		text = "等待其他席位…"
	elif _is_player_turn():
		if _can_player_pick(selected_hero_type):
			can = true
			text = "√  确定选择"
		else:
			text = "请选择分路英雄"
	if can and not _has_player_name():
		can = false
		text = "请先输入昵称"
	select_confirm_btn.text = text
	select_confirm_btn.disabled = not can
	# 金色实心主按钮（hover 同色辉光，pressed 压暗）；不可点时走 disabled 皮肤
	select_confirm_btn.add_theme_stylebox_override("disabled", UiKit.skin_button("disabled", UiKit.C_GOLD, true))
	select_confirm_btn.add_theme_color_override("font_disabled_color", SEL_DIM)
	if can:
		select_confirm_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, true))
		select_confirm_btn.add_theme_stylebox_override("hover", UiKit.skin_button("hover", UiKit.C_GOLD, true))
		select_confirm_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, true))
		select_confirm_btn.add_theme_color_override("font_color", Color(0.07, 0.08, 0.12))
		select_confirm_btn.add_theme_color_override("font_hover_color", Color(0.04, 0.05, 0.08))
		select_confirm_btn.add_theme_color_override("font_pressed_color", Color(0.04, 0.05, 0.08))
	else:
		select_confirm_btn.add_theme_stylebox_override("normal", UiKit.skin_button("normal", UiKit.C_GOLD, false))
		select_confirm_btn.add_theme_stylebox_override("hover", UiKit.skin_button("normal", UiKit.C_GOLD, false))
		select_confirm_btn.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", UiKit.C_GOLD, false))
		select_confirm_btn.add_theme_color_override("font_color", SEL_DIM)
		select_confirm_btn.add_theme_color_override("font_hover_color", SEL_DIM)
		select_confirm_btn.add_theme_color_override("font_pressed_color", SEL_DIM)

func _on_select_leave():
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
# 「确定选择」：玩家回合落位；非 BP 状态下保持原开始游戏语义
func _on_confirm():
	# 以输入框当前文本为准（程序赋值不会触发 text_changed），空名不可开始
	if sel_name_edit != null and is_instance_valid(sel_name_edit):
		var typed := sel_name_edit.text.strip_edges()
		if typed != "":
			NameStore.save_player_name(typed)
	if not _has_player_name():
		_flash_tip("请先在右侧输入你的昵称")
		if sel_name_edit != null and is_instance_valid(sel_name_edit):
			sel_name_edit.grab_focus()
		return
	if sel_draft_done: return
	if sel_draft_active:
		if _is_player_turn() and not sel_player_picked and selected_hero_type != "":
			if not _is_player_role(selected_hero_type):
				_flash_tip("本局分路：%s · 只能选择%s英雄" % [sel_lane_name, sel_lane_role])
				return
			if sel_taken.has(selected_hero_type):
				_flash_tip("该英雄已被选，请重新选择")
				return
			if not _can_player_pick(selected_hero_type):
				_flash_tip("本队已有该职责，请重新选择")
				return
			_lock_player_pick(selected_hero_type)
		return
	if selected_hero_type != "":
		_start_game(selected_hero_type, selected_summoner)
func add_team_kill(team: int):
	if team == Config.player_team:
		team_player_kills += 1
	else:
		team_enemy_kills += 1
func _ai_lane_name(lane: int) -> String:
	match lane:
		AiConfig.Lane.FARM: return "发育路"
		AiConfig.Lane.MID: return "中路"
		AiConfig.Lane.CLASH: return "对抗路"
		AiConfig.Lane.JUNGLE: return "打野"
	return "未分配"


# 4 分钟阶段评估快照：先量化前4分钟，再对比后续改动是否真的有效
func _log_early_game_metrics() -> void:
	if _early_metrics_logged:
		return
	_early_metrics_logged = true
	var rows: Array = []
	var totals := {"player": {"kills": 0, "deaths": 0, "cs": 0, "gold": 0},
		"enemy": {"kills": 0, "deaths": 0, "cs": 0, "gold": 0}}
	for entity in get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero):
			continue
		var h := entity as Hero
		var ai_node: HeroAI = null
		for c in h.get_children():
			if c is HeroAI:
				ai_node = c
				break
		var team_key := "player" if h.team == Config.player_team else "enemy"
		var row := {
			"name": h.display_name, "role": h.role, "team": int(h.team),
			"is_ai": h.is_ai, "lane": _ai_lane_name(ai_node.lane if ai_node != null else -1),
			"level": h.level, "kills": h.kills, "deaths": h.deaths, "assists": h.assists,
			"cs": h.last_hits, "gold": h.total_gold_earned,
			"damage_heroes": roundi(h.damage_dealt_to_heroes),
			"damage_taken": roundi(h.damage_taken_from_heroes),
			"turret_damage": roundi(h.turret_damage),
			"jungle_gold": h.jungle_gold,
			"trade_attempts": (ai_node.trade_planner.attempts if ai_node != null and ai_node.trade_planner != null else 0),
			"trade_wins": (ai_node.trade_planner.wins if ai_node != null and ai_node.trade_planner != null else 0),
			"trade_damage_out": roundi(ai_node.trade_planner.damage_out) if ai_node != null and ai_node.trade_planner != null else 0,
			"trade_damage_in": roundi(ai_node.trade_planner.damage_in) if ai_node != null and ai_node.trade_planner != null else 0,
		}
		rows.append(row)
		totals[team_key]["kills"] += h.kills
		totals[team_key]["deaths"] += h.deaths
		totals[team_key]["cs"] += h.last_hits
		totals[team_key]["gold"] += h.total_gold_earned
	var doc := {"t": 240.0, "heroes": rows, "totals": totals,
		"task_stats": (team_tactics.task_stats.duplicate() if team_tactics != null else {}),
		"player_towers": _count_alive_turrets(Config.player_team),
		"enemy_towers": _count_alive_turrets(Config.foe_team())}
	early_game_metrics = doc
	var text := "[AI-EARLY-METRICS] " + JSON.stringify(doc)
	print(text)
	var f := FileAccess.open("user://ai_early_metrics.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
	if _ai_benchmark and not _ai_benchmark_keep:
		get_tree().quit()


func _count_alive_turrets(team: int) -> int:
	var n := 0
	for t in turrets:
		if is_instance_valid(t) and t.team == team and t.health > 0 and t.display_name != "crystal":
			n += 1
	return n


func _update_team_stats():
	team_player_gold = 0; team_player_exp = 0; 
	team_enemy_gold = 0; team_enemy_exp = 0; 
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Hero:
			if entity.team == Config.player_team:
				team_player_gold += entity.total_gold_earned
				team_player_exp += entity.exp
				# 人头数需要另外记录（可在击杀时累加到团队变量）
			elif entity.team == Config.foe_team():
				team_enemy_gold += entity.total_gold_earned
				team_enemy_exp += entity.exp
# 全场MVP评分：在全部存活/已阵亡英雄中按综合表现归一化打分（权重与结算面板一致，跨队伍比较）
func _refresh_mvp() -> void:
	var heroes := get_tree().get_nodes_in_group("heroes")
	if heroes.is_empty():
		if mvp_hero:
			mvp_hero.is_mvp = false
			mvp_hero = null
		return
	var max_kills := 1
	var max_deaths := 1
	var max_dmg := 1.0
	var max_gold := 1
	var max_taken := 1.0
	var total_kills := 0
	for h in heroes:
		var hh: Hero = h as Hero
		if hh == null or not is_instance_valid(hh):
			continue
		max_kills = max(max_kills, hh.kills)
		max_deaths = max(max_deaths, hh.deaths)
		max_dmg = max(max_dmg, hh.damage_dealt_to_heroes)
		max_gold = max(max_gold, hh.total_gold_earned)
		max_taken = max(max_taken, hh.damage_taken_from_heroes)
		total_kills += hh.kills
	var best: Hero = null
	var best_score := -1.0
	for h in heroes:
		var hh: Hero = h as Hero
		if hh == null or not is_instance_valid(hh):
			continue
		var kill_score := (float(hh.kills) / max_kills) * 100.0
		var assist_score: float = (float(hh.assists) / max(1, total_kills)) * 100.0
		var death_pen: float = (1.0 - float(hh.deaths) / max(1, max_deaths)) * 100.0
		var gold_score := (float(hh.total_gold_earned) / max_gold) * 100.0
		var dmg_score := (hh.damage_dealt_to_heroes / max_dmg) * 100.0
		var taken_score := (hh.damage_taken_from_heroes / max_taken) * 100.0
		var participation: float = (float(hh.kills + hh.assists) / max(1, total_kills)) * 100.0
		var score: float = (
			kill_score * 0.15 +
			assist_score * 0.10 +
			max(0.0, death_pen) * 0.05 +
			gold_score * 0.15 +
			dmg_score * 0.25 +
			taken_score * 0.10 +
			participation * 0.20
		)
		if score > best_score:
			best_score = score
			best = hh
	if mvp_hero == best:
		return
	if mvp_hero and is_instance_valid(mvp_hero):
		mvp_hero.is_mvp = false
	mvp_hero = best
	if best:
		best.is_mvp = true

# ---- P0 镜头/画面反馈（本地表现层，不改伤害与判定时序） ----
func camera_shake(amp: float = 0.12, dur: float = 0.22) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_dur = maxf(_shake_dur, dur)
	_shake_t = maxf(_shake_t, dur)

func _apply_camera_shake(delta: float) -> void:
	if _shake_t <= 0.0:
		return
	_shake_t = maxf(0.0, _shake_t - delta)
	var k: float = _shake_t / maxf(0.001, _shake_dur)
	var a: float = _shake_amp * k * k
	var now: float = Time.get_ticks_msec() * 0.001
	cam.global_position += Vector3(sin(now * 61.0), sin(now * 47.0) * 0.6, cos(now * 53.0)) * a
	if _shake_t <= 0.0:
		_shake_amp = 0.0

func fov_punch(amount: float = 2.5, dur: float = 0.35) -> void:
	if cam == null:
		return
	if _cam_base_fov < 0.0:
		_cam_base_fov = cam.fov
	var base: float = _cam_base_fov
	var tw := create_tween()
	tw.tween_property(cam, "fov", base - amount, dur * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam, "fov", base, dur * 0.7).set_ease(Tween.EASE_IN_OUT)

func hitstop(dur: float = 0.035) -> void:
	var now := Time.get_ticks_msec()
	if now < _hitstop_until_msec:
		return
	_hitstop_until_msec = now + int(dur * 1000.0)
	Engine.time_scale = 0.12
	var t := get_tree().create_timer(dur, true, false, true)
	t.timeout.connect(func():
		if Time.get_ticks_msec() >= _hitstop_until_msec:
			Engine.time_scale = 1.0
	)

# 本地玩家放大招：轻震屏 + FOV 推镜 + 重击技能顿帧 + 元素色闪屏（参数查 SpellFxTable）
func on_big_cast(hero: Hero) -> void:
	if hero != self.hero:
		return
	var ent: Dictionary = SPELL_FX.get_ult(hero.display_name)
	camera_shake(float(ent.get("shake", 0.10)), 0.28)
	fov_punch(2.5, 0.40)
	if bool(ent.get("heavy", false)):
		hitstop(0.03)
	Vfx.screen_flash(Vfx.color_for_hero(hero.display_name).lerp(Color.WHITE, 0.55), 0.20)

# PostFX：离开战斗场景时复位死亡去饱和/低血红屏，避免大厅/选人界面被压暗
func _exit_tree() -> void:
	# 若在加载/开局运镜暂停中退出场景，必须恢复场景树，避免大厅/选人界面被冻结
	if intro_active or building_battle:
		intro_active = false
		building_battle = false
		get_tree().paused = false
	PostFX.set_dead(false)
	PostFX.set_low_hp(1.0)
	# 离开对局：停掉播报/短音/回城循环，取消未播完的开局链
	if is_instance_valid(SfxManager):
		SfxManager.stop_all()
	# 单例 HUD：退出对局即隐藏，避免回大厅后残留
	if is_instance_valid(UiManager):
		UiManager.exit_battle()

# PostFX：本地英雄受击红晕 + 阵亡去饱和 + 低血量屏幕血光（纯表现，不参与战斗逻辑）
func _sync_postfx() -> void:
	if not is_instance_valid(hero):
		PostFX.set_low_hp(1.0)
		return
	if hero.is_dead:
		PostFX.set_dead(true)
		PostFX.set_low_hp(0.0)
		_pfx_hp = -1.0
		return
	PostFX.set_dead(false)
	# 低血量：护盾算有效生命，有盾时不弹血光
	PostFX.set_low_hp(clampf((hero.health + hero.shield_remaining) / maxf(hero.actual_max_health, 1.0), 0.0, 1.0))
	if _pfx_hp >= 0.0 and hero.health < _pfx_hp:
		var lost := (_pfx_hp - hero.health) / maxf(hero.actual_max_health, 1.0)
		PostFX.damage(clampf(0.3 + lost * 4.0, 0.0, 1.0), clampf(lost * 3.0, 0.0, 0.6))
	_pfx_hp = hero.health

# 阵亡观战选择：仅玩家阵亡时可选存活友方；复活时由 _process 自动清空并回正镜头
func set_spectate_target(target: Hero) -> void:
	if not is_instance_valid(hero) or not hero.is_dead:
		return
	if target == null or not is_instance_valid(target) or target == hero:
		return
	if target.is_dead or not Config.is_ally(target.team):
		return
	spectate_hero = target
	cam_pan_offset = Vector3.ZERO
	_cam_snap = true

func _follow_camera_unit(unit: Hero, delta: float) -> void:
	if not is_instance_valid(unit):
		return
	var follow_offset := CAMERA_FOLLOW_OFFSET.rotated(Vector3.UP, cam_yaw)
	if unit.display_name == "兰陵王" and unit.lanling_stealth_active:
		follow_offset *= 1.25
	var target: Vector3 = unit.global_position + follow_offset + cam_pan_offset + Vector3.UP * HERO_BAR_CENTER_UP
	if _cam_snap or cam.global_position.distance_to(target) > 25.0:
		cam.global_position = target
		_cam_snap = false
	else:
		cam.global_position = cam.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
	_apply_camera_shake(delta)

func _begin_intro() -> void:
	if intro_active or not is_instance_valid(hero):
		return
	intro_active = true
	_intro_waiting = true
	_intro_time = 0.0
	var follow := CAMERA_FOLLOW_OFFSET.rotated(Vector3.UP, cam_yaw)
	_intro_end = hero.global_position + follow + Vector3.UP * HERO_BAR_CENTER_UP
	# 起始机位沿同一俯视方向拉远、抬高；随后插值回正常跟随位
	_intro_start = _intro_end + Vector3(0, 70, 130).rotated(Vector3.UP, cam_yaw)
	cam.global_position = _intro_start
	cam.rotation_degrees = Vector3(-72, rad_to_deg(cam_yaw), 0)
	cam.fov = 52.0
	if ui:
		ui.visible = false
	if minimap:
		minimap.visible = false
	if is_instance_valid(TouchController):
		TouchController.set_intro_hidden(true)
	# 暂停整棵场景树：AI/英雄/小兵/野怪/计时全部停住；本节点自身继续跑运镜
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	MapVisuals.update_backlight_for_camera(cam)
	# 战场已构建完，但加载层仍覆盖：先渲染两帧让网格/材质/相机全部就绪，再撤加载层
	await get_tree().process_frame
	await get_tree().process_frame
	if not intro_active:
		return
	if loading_screen:
		loading_screen.visible = false
		loading_screen.queue_free()
		loading_screen = null
	_intro_waiting = false
	_intro_time = 0.0

func _process_intro(delta: float) -> void:
	_intro_time += delta
	var t := clampf(_intro_time / INTRO_DURATION, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - t, 3.0)
	cam.global_position = _intro_start.lerp(_intro_end, e)
	cam.rotation_degrees = Vector3(lerpf(-72.0, -60.0, e), rad_to_deg(cam_yaw), 0)
	cam.fov = lerpf(52.0, 70.0, e)
	MapVisuals.update_backlight_for_camera(cam)
	if t >= 1.0:
		_finish_intro()

func _finish_intro() -> void:
	intro_active = false
	cam.global_position = _intro_end
	cam.rotation_degrees = Vector3(-60, rad_to_deg(cam_yaw), 0)
	cam.fov = 70.0
	if ui:
		ui.visible = true
	if minimap:
		minimap.visible = true
	if is_instance_valid(TouchController):
		TouchController.set_intro_hidden(false)
	get_tree().paused = false
	process_mode = Node.PROCESS_MODE_INHERIT
	_cam_snap = true
	# 运镜结束再播开局播报：欢迎→准备→全军出击
	SfxManager.announce_chain(["welcome", "ready", "attack"])
	_spawn_lane_guides()


# ---------------- 开局地面推荐分路指引 ----------------
# 蓝（我方）/ 红（敌方）各画三条路的地面光带 + 方向箭头，玩家英雄对应分路加粗高亮；
# 12 秒后淡出释放，避免干扰对线期视野。
const LANE_GUIDE_HOLD := 12.0
const LANE_GUIDE_FADE := 1.6
# 分路光带着色器：柔边光带 + 中线亮带 + 沿线流动的虚线 + 箭头感前缘（沿路方向有流动感）
const LANE_GUIDE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 lane_color : source_color = vec4(0.30, 0.68, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float dash_count = 24.0;
uniform float flow_speed = 0.7;

void fragment() {
	float v = abs(UV.y - 0.5) * 2.0;                        // 0=中线 1=外缘
	float edge = 1.0 - smoothstep(0.60, 1.0, v);             // 外缘柔化
	float core = 1.0 - smoothstep(0.04, 0.55, v);            // 中线亮带
	float f = fract(UV.x * dash_count - TIME * flow_speed);  // 沿线流动
	float dash = smoothstep(0.02, 0.22, f) * (1.0 - smoothstep(0.70, 0.98, f));
	float chev = (1.0 - smoothstep(0.0, 0.55, abs(fract(UV.x * dash_count * 0.5) - 0.5)))
		* smoothstep(0.78, 1.0, f);                          // 箭头前缘
	float a = (edge * 0.14 + core * (0.16 + 0.5 * dash) + chev * 0.26) * intensity * lane_color.a;
	a *= smoothstep(0.0, 0.04, UV.x) * (1.0 - smoothstep(0.95, 1.0, UV.x));   // 两端渐隐
	vec3 col = mix(lane_color.rgb, vec3(1.0), dash * 0.35 + chev * 0.30);
	ALBEDO = col;
	EMISSION = lane_color.rgb * (0.5 + 1.5 * dash);
	ALPHA = clamp(a, 0.0, 0.92);
}
"""

func _spawn_lane_guides() -> void:
	if not is_instance_valid(hero):
		return
	var root := Node3D.new()
	root.name = "LaneGuide"
	add_child(root)
	var blue := Color(0.30, 0.68, 1.0)
	var red := Color(1.0, 0.34, 0.28)
	# 只给"本端玩家"画一条指引：分路取选人页选的分路（打野/游走也有各自的走法）
	var our_team: bool = Config.player_team == Config.Team.PLAYER
	var col: Color = blue if our_team else red
	var lane: String = PlayerPrefs.get_lane()
	if not HeroPickData.LANES.has(lane):
		lane = HeroPickData.role_lane(str(hero.role))
	# 辅助（游走）的开局推荐分路=发育路；必须在红蓝镜像前归一化，
	# 否则红方会拿「蓝方发育路」直接镜像，指到红方对抗路。
	if lane == "游走":
		lane = "发育路"
	# 红蓝双方镜像：红方的发育路/对抗路与蓝方相反（敌方对抗路=我方发育路）。
	# 先换成蓝方视角的同一条路，再做点镜像，才不会把红方玩家指到错误的分路。
	var route_lane: String = lane if our_team else _opposite_lane(lane)
	var pts: Array = _lane_route(route_lane)
	if not our_team:
		var mirrored: Array = []
		for p: Vector3 in pts:
			mirrored.append(Vector3(-p.x, p.y, -p.z))
		pts = mirrored
	_add_lane_guide(root, pts, col, true)
	var tw := create_tween()
	tw.tween_interval(LANE_GUIDE_HOLD)
	tw.tween_method(Callable(self, "_lane_guide_fade").bind(root), 0.0, 1.0, LANE_GUIDE_FADE)
	tw.tween_callback(root.queue_free)

## 红方镜像后的分路名：发育路 ↔ 对抗路，中路/打野/游走保持同名。
func _opposite_lane(lane: String) -> String:
	match lane:
		"发育路":
			return "对抗路"
		"对抗路":
			return "发育路"
	return lane

## 玩家分路的地面路线（坐标以蓝方基地 (-53,53) 为起点；红方先换相反分路再镜像）
func _lane_route(lane: String) -> Array:
	match lane:
		"发育路":
			return [Vector3(-53, 0, 53), Vector3(-35, 0, 55), Vector3(-15, 0, 56), Vector3(28, 0, 58)]
		"中路":
			return [Vector3(-53, 0, 53), Vector3(-40, 0, 40), Vector3(-27, 0, 27), Vector3(-14, 0, 14), Vector3(0, 0, 0)]
		"对抗路":
			return [Vector3(-53, 0, 53), Vector3(-55, 0, 35), Vector3(-56, 0, 15), Vector3(-58, 0, -28)]
		"打野":
			# 蓝 buff → 河道岔口 → 红 buff：从自家野区刷起，不走线上
			return [Vector3(-53, 0, 53), Vector3(-40, 0, 20), Vector3(-28, 0, -5), Vector3(-8, 0, 18), Vector3(3, 0, 38)]
		_:
			# 游走（辅助）：开局推荐分路 = 发育路（跟射手，蓝方走发育路、红方镜像后走红方发育路）
			return [Vector3(-53, 0, 53), Vector3(-35, 0, 55), Vector3(-15, 0, 56), Vector3(28, 0, 58)]

func _lane_guide_fade(v: float, root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var k: float = 1.0 - clampf(v, 0.0, 1.0)
	for c in root.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var mat := mi.material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).get_meta("lane_fade", false):
			(mat as ShaderMaterial).set_shader_parameter("intensity", k)
			continue
		if mi.has_meta("lane_ring"):
			var bc: Color = mi.get_meta("lane_ring")
			MeshFactory.set_ground_ring_color(mi, Color(bc.r, bc.g, bc.b, bc.a * k))
			continue
		mi.transparency = clampf(v, 0.0, 1.0)

func _add_lane_guide(parent: Node3D, pts: Array, color: Color, highlight: bool) -> void:
	var width: float = 4.6 if highlight else 2.8
	var alpha: float = 0.95 if highlight else 0.55
	# 必须高于高地砖面(0.2)与台裙(0.176)，否则光带会被高地压住看不见
	var y: float = 0.26
	# 累计长度 → UV.x（0..1 沿线），UV.y 横跨光带（0..1）
	var total := 0.0
	for i in range(pts.size() - 1):
		total += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
	total = maxf(total, 0.01)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var seg := d.length()
		if seg < 0.05:
			continue
		d = d / seg
		var n := Vector3(-d.z, 0.0, d.x) * width * 0.5
		var u0 := acc / total
		var u1 := (acc + seg) / total
		acc += seg
		var a0 := Vector3(a.x, y, a.z) + n
		var a1 := Vector3(a.x, y, a.z) - n
		var b0 := Vector3(b.x, y, b.z) + n
		var b1 := Vector3(b.x, y, b.z) - n
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(a0)
		st.set_uv(Vector2(u1, 0.0)); st.add_vertex(b0)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b1)
		st.set_uv(Vector2(u0, 0.0)); st.add_vertex(a0)
		st.set_uv(Vector2(u1, 1.0)); st.add_vertex(b1)
		st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a1)
	st.index()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sh := Shader.new()
	sh.code = LANE_GUIDE_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("lane_color", Color(color.r, color.g, color.b, alpha))
	sm.set_shader_parameter("intensity", 1.0)
	sm.set_shader_parameter("dash_count", 26.0 if highlight else 22.0)
	sm.set_shader_parameter("flow_speed", 0.8 if highlight else 0.55)
	sm.set_meta("lane_fade", true)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# 终点柔光环：标出这条路要去的方向（不是终点塔，只是视觉落点）
	var endp: Vector3 = pts[pts.size() - 1]
	var ring_col := Color(color.r, color.g, color.b, 0.5 * alpha)
	var ring := MeshFactory.create_ground_ring(2.6, ring_col, 0.0)
	ring.name = "LaneGoal"
	ring.position = Vector3(endp.x, y, endp.z)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_meta("lane_ring", ring_col)
	parent.add_child(ring)

func _process(delta):
	if building_battle:
		return
	if intro_active:
		if not _intro_waiting:
			_process_intro(delta)
		return
	if select_ui != null:
		_update_sel_draft(delta)
		if select_ui == null:
			return
	if game_over:
		if _ai_benchmark:
			print("[AI-BENCH] ended before 240s at t=%.1f" % game_time)
			get_tree().quit()
		return
	_sync_postfx()
	if _ai_test_match:
		_test_tick(delta)
	elif _training_mode:
		_training_tick(delta)
	# 金币自动增长
		# 摄像机控制
	if spectate_hero != null:
		var spectate_invalid := not is_instance_valid(spectate_hero) or spectate_hero.is_dead
		var player_alive := is_instance_valid(hero) and not hero.is_dead
		if spectate_invalid or player_alive:
			spectate_hero = null
			if player_alive:
				_cam_snap = true
	# 更新回城连线
	for hero in recall_lines.keys():
		if is_instance_valid(hero) and hero.is_recalling:
			recall_lines[hero]["hero_pos"] = hero.global_position
		else:
			recall_lines.erase(hero)
	# 右半屏拖拽相机：每帧根据触摸手势增量更新平移量
	_update_cam_pan()
	if first_person_view:
		if hero and is_instance_valid(hero) and not hero.is_dead:
			# 第一人称：摄像机位于英雄头部，朝向跟随英雄面朝方向
			# 英雄模型在rotation.y=0时朝+Z，摄像机朝-Z，需偏转180°对齐
			# 英雄模型总×3 后身高为×2 的 1.5 倍，FP 视点保持在约头顶 2/3（1.6×1.5=2.4）
			cam.global_position = hero.global_position + Vector3(0, 2.4, 0)
			cam.rotation = Vector3(0, hero.rotation.y + PI, 0)
		else:
			# 英雄阵亡时自动退回第三人称
			_set_camera_mode(false)
	elif minimap_dragging and minimap_drag_pos != Vector3.ZERO:

		cam.global_position.x = minimap_drag_pos.x
		cam.global_position.z = minimap_drag_pos.z
		# Y轴保持不变（保持高度）
		_cam_snap = true
	elif minimap_jump_requested and minimap_drag_pos != Vector3.ZERO:
		# 点击跳转，立即移动摄像机

		cam.global_position.x = minimap_drag_pos.x
		cam.global_position.z = minimap_drag_pos.z
		minimap_jump_requested = false
		_cam_snap = true
	elif is_instance_valid(hero) and hero.is_dead and is_instance_valid(spectate_hero) and not spectate_hero.is_dead:
		# 阵亡观战：镜头跟随被点选的存活队友，画面仍由 PostFX 阵亡去饱和保持灰白
		_follow_camera_unit(spectate_hero, delta)
	elif is_instance_valid(hero) and not hero.is_dead:
		# 正常跟随英雄：跟随偏移（还原初始镜头 (0,12,8)，无放大；沿 -70° 视角射线）
		_follow_camera_unit(hero, delta)
	# 逆光：主光始终在相机水平正前方，补光在相机后方（随第一人称/换边旋转同步）
	MapVisuals.update_backlight_for_camera(cam)
	if not hero_selected:
		return
	# F3 AI 思考覆盖层：0.4s 刷新
	if _ai_dbg != null and _ai_dbg.visible:
		_ai_dbg_t -= delta
		if _ai_dbg_t <= 0.0:
			_ai_dbg_t = 0.4
			_refresh_ai_debug()
	
	# 调试：每0.5秒刷新AI路径球显示
	debug_refresh_timer -= delta
	if debug_refresh_timer <= 0.0 and GameEntity.debug_show_path:
		debug_refresh_timer = 0.5
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent is GameEntity:
				ent._update_debug_path_visual()
	stats_timer -= delta
	if stats_timer <= 0:
		stats_timer = 1.0
		_update_team_stats()
		if team_tactics != null:
			team_tactics.update_tasks(game_time)
		_apply_natural_experience()
		_apply_natural_gold()
		# 团队事件：塔数变化 / 龙存活变化时立即请求重规划，而不是等10秒兜底
		if team_tactics != null and game_time >= 240.0:
			var tp_now := _count_alive_turrets(Config.player_team)
			var te_now := _count_alive_turrets(Config.foe_team())
			if (_last_turret_count_p >= 0 and tp_now != _last_turret_count_p) \
					or (_last_turret_count_e >= 0 and te_now != _last_turret_count_e) \
					or dragon_alive != _last_dragon_alive:
				team_tactics.request_replan()
			_last_turret_count_p = tp_now
			_last_turret_count_e = te_now
			_last_dragon_alive = dragon_alive
		if not _early_metrics_logged and game_time >= 240.0:
			_log_early_game_metrics()
		# 赛后统计：每分钟记录金币
		var current_minute = int(game_time / 60)
		if _last_recorded_minute < current_minute:
			_last_recorded_minute = current_minute
			for entity in get_tree().get_nodes_in_group("heroes"):
				if entity is Hero:
					entity.gold_history.append(entity.total_gold_earned)
			team_gold_diff_history.append(team_player_gold - team_enemy_gold)
	game_time += delta
	# 延时野怪出生（普通营地30s / 空间之灵60s）；每帧只物化一组，避免同帧建整片野区
	_update_pending_jungle_spawns()
	_drain_jungle_group_queue()
	# 全场MVP：每30秒重算一次（首档t<30s不结算，30s起每30s一档）
	var _mvp_interval_now := int(game_time / 30.0)
	if _mvp_interval_now > _mvp_interval:
		_mvp_interval = _mvp_interval_now
		_refresh_mvp()
	_update_shadow_paths(delta)
	_update_shadow_path_fades(delta)
	# 集中式团队分推协调（4分钟后每60s分配一次；4分钟前水晶受小兵威胁时立即应急回防）
	if team_tactics:
		var early_threat: bool = game_time < 240.0 and team_tactics.has_crystal_threat()
		if game_time >= 240.0 or early_threat:
			team_tactics_timer -= delta
			var urgent := team_tactics.consume_replan_request()
			if team_tactics_timer <= 0 or urgent:
				team_tactics_timer = (AiConfig.TEAM_ALLOCATION_INTERVAL if game_time >= 240.0 else 2.0)
				print("[BattleManager] t=%.0f 执行团队任务重规划（模式=%s，urgent=%s，早期回防=%s）" % [game_time, team_tactics.get_mode_name(), urgent, early_threat])
				var assignments := team_tactics.allocate_all()
				_distribute_lane_assignments(assignments)
	# 小兵生成
	if game_time >= 235:
		_update_epic_monsters(delta)
	minion_spawn_timer -= delta
	if minion_spawn_timer <= 0:
		minion_spawn_timer = 33.0
		_spawn_minion_wave()
	_drain_minion_spawn_queue()

	# 视野更新
	_update_vision(delta)

	# UI 更新
	ui.update(self)
	minimap.heroes = get_tree().get_nodes_in_group("heroes")
	minimap.minions = get_tree().get_nodes_in_group("minions")
	minimap.jungle_monsters = get_tree().get_nodes_in_group("jungle_monsters")
	minimap.turrets = turrets   # 已经维护

	minimap.player_team = Config.player_team
	minimap.queue_redraw()# 需要在创建野怪时加入数组

	# 胜利检测
	if player_base_health <= 0 or enemy_base_health <= 0:
		print("游戏结束")

	# 所有实体更新后
	var all_entities = get_tree().get_nodes_in_group("entities")
	CollisionSystem.apply_collision_pushback(all_entities, delta)
	# 小地图、UI更新...

func _distribute_lane_assignments(assignments: Dictionary) -> void:
	for hero in assignments:
		if not is_instance_valid(hero) or hero.health <= 0:
			continue
		var hero_ai: HeroAI = null
		for child in hero.get_children():
			if child is HeroAI:
				hero_ai = child
				break
		if not hero_ai:
			continue
		var task: TeamTask = team_tactics.tasks.get(hero, null)
		if task != null:
			hero_ai.assign_team_task(task)
			continue
		var lane := assignments[hero] as int
		if lane == AiConfig.Lane.JUNGLE:
			# 旧分路兜底：集合打龙
			hero_ai.is_dragon_rally = true
			hero_ai.dragon_rally_pos = team_tactics.dragon_pos_by_team.get(hero.team, team_tactics.dragon_pos)
			print("[BattleManager] t=%.0f %s 收到打龙指令，集合点=%s" % [game_time, hero.display_name, hero_ai.dragon_rally_pos])
		elif lane >= 0:
			hero_ai.is_dragon_rally = false
			hero_ai.apply_team_lane(lane)
# ---- 视野之灵 ----
# 己方边路二塔被摧毁 60 秒后，在二塔原位置生成 1 个视野之灵。
func schedule_vision_spirit(pos: Vector3, lane: String, delay: float = 60.0) -> void:
	if game_over or lane == "mid":
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay
	add_child(timer)
	timer.timeout.connect(func():
		if is_instance_valid(timer):
			timer.queue_free()
		if not game_over:
			_spawn_vision_spirit(pos))
	timer.start()

func _spawn_vision_spirit(pos: Vector3) -> void:
	var spirit = VisionSpiritScript.new()
	spirit.team = Config.player_team
	spirit.spawn_pos = Vector3(pos.x, 0.0, pos.z)
	spirit.bush_pos = _pick_vision_spirit_bush(pos)
	add_child(spirit)
	vision_spirits.append(spirit)

# 选择离生成点最近的 buff，再选该 buff 周围最近的草丛。
func _pick_vision_spirit_bush(spawn_pos: Vector3) -> Vector3:
	var buff_pos: Vector3 = spawn_pos
	var best_buff_d := INF
	for m in get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(m) or not (m is JungleMonster):
			continue
		var jm := m as JungleMonster
		if jm.buff_type not in ["red", "blue"]:
			continue
		var d := Vector2(spawn_pos.x, spawn_pos.z).distance_to(Vector2(jm.global_position.x, jm.global_position.z))
		if d < best_buff_d:
			best_buff_d = d
			buff_pos = jm.global_position
	var best_bush: Vector3 = spawn_pos
	var best_bush_d := INF
	for bp in _bush_positions:
		var d2 := Vector2(bp.x, bp.z).distance_to(Vector2(buff_pos.x, buff_pos.z))
		if d2 < best_bush_d:
			best_bush_d = d2
			best_bush = bp
	return Vector3(best_bush.x, 0.0, best_bush.z)

func _vision_spirit_sources() -> Array:
	var out: Array = []
	for s in get_tree().get_nodes_in_group("vision_spirits"):
		if is_instance_valid(s) and s.team == Config.player_team and s.vision_active:
			out.append(s)
	return out

func _seen_by_vision_spirit(pos: Vector3, spirits: Array) -> bool:
	for s in spirits:
		if is_instance_valid(s) and s.global_position.distance_to(pos) <= s.vision_radius:
			return true
	return false

# ---- vision update: enemy entities visible only within friendly vision ----
var _vision_timer: float = 0.0
# 死亡视野残留：防御塔倒后 2 秒、小兵死后 1 秒仍提供原半径视野（单机/联机 host 共用）
var _dead_visions: Array = []

func register_dead_vision(kind: String, team: int, pos: Vector3) -> void:
	var life: float = 2.0 if kind == "turret" else 1.0
	_dead_visions.append({
		"kind": kind, "team": int(team), "pos": pos,
		"until": Time.get_ticks_msec() * 0.001 + life,
	})

func get_dead_visions(team: int = -1) -> Array:
	var now := Time.get_ticks_msec() * 0.001
	var out: Array = []
	var keep: Array = []
	for d in _dead_visions:
		if float(d.get("until", 0.0)) <= now:
			continue
		keep.append(d)
		if team < 0 or int(d.get("team", -1)) == team:
			out.append(d)
	_dead_visions = keep
	return out

# 技能侦察区域（鲁班2/后羿R）：用于小地图雾层临时照亮
var _skill_reveal_zones: Array = []

func add_skill_reveal_zone(team: int, pos: Vector3, radius: float, duration: float) -> void:
	_skill_reveal_zones.append({
		"team": int(team), "pos": Vector3(pos.x, 0.0, pos.z),
		"r": float(radius), "until": Time.get_ticks_msec() * 0.001 + duration,
	})

func get_skill_reveal_zones(team: int = -1) -> Array:
	var now := Time.get_ticks_msec() * 0.001
	var keep: Array = []
	var out: Array = []
	for z in _skill_reveal_zones:
		if float(z.get("until", 0.0)) <= now:
			continue
		keep.append(z)
		if team < 0 or int(z.get("team", -1)) == team:
			out.append(z)
	_skill_reveal_zones = keep
	return out


func _seen_by_dead_vision(pos: Vector3, team: int) -> bool:
	for d in get_dead_visions(team):
		var vr: float = 10.0 if str(d.get("kind", "")) == "turret" else 8.0
		if (d.get("pos") as Vector3).distance_to(pos) <= vr:
			return true
	return false

func _update_vision(delta: float) -> void:
	_vision_timer -= delta
	if _vision_timer > 0:
		return

	_vision_timer = 0.2
	# 测试观战：全知视野，所有单位常显（不改 AI 逻辑，只改可见性）
	if _ai_test_match:
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent is GameEntity:
				ent.visible = true
		for hh in get_tree().get_nodes_in_group("heroes"):
			if hh is Hero:
				hh.visible = true
		return
	var player_team := Config.player_team

	# Collect friendly vision sources (heroes, minions, turrets)
	var vision_sources: Array[GameEntity] = []
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity) or entity.health <= 0:
			continue
		if entity.team != player_team:
			continue
		if entity is Hero or entity is Minion or entity is Turret or entity is Tripod:
			vision_sources.append(entity)
	var spirit_sources := _vision_spirit_sources()

	# Update visibility for enemy minions (heroes handled by HeroAI stealth system)
	for entity in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(entity) or entity.health <= 0:
			continue
		if entity.team == player_team:
			entity.visible = true
			continue

		# Attack exposure / 技能侦察：2s forced visibility after being hit or revealed
		if entity.vision_expose_timer > 0 \
				or (entity.skill_reveal_timer > 0 and entity.skill_reveal_team == player_team):
			if entity.vision_expose_timer > 0:
				entity.vision_expose_timer -= delta * 5.0
			entity.visible = true
			continue

		# Check if any friendly source can see this minion
		var in_vision := false
		for src in vision_sources:
			var vr := 12.0
			if src is Hero:
				# 玩家兰陵王隐身中：自视野半径+25%（12→15）
				if src.display_name == "兰陵王" and (src as Hero).lanling_stealth_active and src == hero:
					vr = 15.0
				else:
					vr = 12.0
			elif src is Minion:
				vr = 8.0
			elif src is Tripod:
				vr = 8.0   # 大禹的鼎：照亮周围 8 米（比小兵略广、弱于视野之灵）
			else:
				vr = 10.0
			if src.global_position.distance_to(entity.global_position) <= vr:
				in_vision = true
				break
		if not in_vision:
			in_vision = _seen_by_dead_vision(entity.global_position, player_team)
		if not in_vision:
			in_vision = _seen_by_vision_spirit(entity.global_position, spirit_sources)
		entity.visible = in_vision

	# Update visibility for jungle monsters (neutral, visible only within vision)
	for entity in get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(entity) or entity.health <= 0:
			continue

		# Attack exposure / 技能侦察：2s forced visibility after being hit or revealed
		if entity.vision_expose_timer > 0 \
				or (entity.skill_reveal_timer > 0 and entity.skill_reveal_team == player_team):
			if entity.vision_expose_timer > 0:
				entity.vision_expose_timer -= delta * 5.0
			entity.visible = true
			continue

		# Check if any friendly source can see this jungle monster
		var in_vision := false
		for src in vision_sources:
			var vr := 12.0
			if src is Hero:
				# 玩家兰陵王隐身中：自视野半径+25%（12→15）
				if src.display_name == "兰陵王" and (src as Hero).lanling_stealth_active and src == hero:
					vr = 15.0
				else:
					vr = 12.0
			elif src is Minion:
				vr = 8.0
			elif src is Tripod:
				vr = 8.0   # 大禹的鼎：照亮周围 8 米（比小兵略广、弱于视野之灵）
			else:
				vr = 10.0
			if src.global_position.distance_to(entity.global_position) <= vr:
				in_vision = true
				break
		if not in_vision:
			in_vision = _seen_by_dead_vision(entity.global_position, player_team)
		if not in_vision:
			in_vision = _seen_by_vision_spirit(entity.global_position, spirit_sources)
		entity.visible = in_vision

	# 敌方英雄同样遵守战争迷雾：仅当被我方任一视野源（英雄12/小兵8/塔10）看到、或被出手/受击暴露时才可见。
	# 优先级：己方常显 > 隐身（兰陵王·影袭/幽影袖箭）恒隐 > 攻击暴露强制可见 > 草丛隐藏 > 我方视野距离判定。
	for entity in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(entity) or entity is not Hero or entity.health <= 0:
			continue
		if entity.team == player_team:
			entity.visible = true
			continue
		# 隐身：即便在我方视野内也不可见
		if entity.lanling_stealth_active or entity.shadow_dart_active:
			entity.visible = false
			continue
		# 攻击暴露 / 技能侦察：出手/受击或鲁班2/后羿R 照出后 2 秒内强制可见
		if entity.skill_reveal_timer > 0 and entity.skill_reveal_team == player_team:
			entity.visible = true
			continue
		if entity.vision_expose_timer > 0:
			entity.visible = true
			continue
		# 草丛隐藏：身在草丛且同排无敌方英雄互相暴露时，草丛会遮挡视野；
		# 但视野之灵的 20 米视野可以直接照亮草丛内的敌人。
		if entity.hidden_in_bush:
			entity.visible = _seen_by_vision_spirit(entity.global_position, spirit_sources)
			continue
		# 草丛同区互见：与己方英雄共享同一连片草丛(region) → 区域级互相暴露，不看距离
		# （与 Hero._update_bush_stealth 语义一致；不收敛到 12m，否则长草两端会产生帧级竞态）
		if not (entity as Hero)._bush_region_counts.is_empty():
			entity.visible = true
			continue
		var in_vision := false
		for src in vision_sources:
			var vr := 12.0
			if src is Hero:
				# 玩家兰陵王隐身中：自视野半径+25%（12→15）
				if src.display_name == "兰陵王" and (src as Hero).lanling_stealth_active and src == hero:
					vr = 15.0
				else:
					vr = 12.0
			elif src is Minion:
				vr = 8.0
			elif src is Tripod:
				vr = 8.0   # 大禹的鼎：照亮周围 8 米（比小兵略广、弱于视野之灵）
			else:
				vr = 10.0
			if src.global_position.distance_to(entity.global_position) <= vr:
				in_vision = true
				break
		if not in_vision:
			in_vision = _seen_by_dead_vision(entity.global_position, player_team)
		if not in_vision:
			in_vision = _seen_by_vision_spirit(entity.global_position, spirit_sources)
		entity.visible = in_vision
func _apply_natural_gold():
	var gold_per_sec = 0
	if game_time < 30: gold_per_sec = 0
	elif game_time < 60: gold_per_sec = 2
	elif game_time < 240: gold_per_sec = 3
	elif game_time < 420: gold_per_sec = 4
	elif game_time < 600: gold_per_sec = 5
	else: gold_per_sec = 6

	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.health > 0:
			entity.add_gold(int(gold_per_sec))
func _apply_natural_experience():
	var exp_per_sec = 0
	if game_time < 30: exp_per_sec = 0
	elif game_time < 60: exp_per_sec = 2
	elif game_time < 240: exp_per_sec = 3
	elif game_time < 420: exp_per_sec = 4
	elif game_time < 600: exp_per_sec = 5
	elif game_time < 780: exp_per_sec = 6
	else: exp_per_sec = 7

	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.health > 0:
			entity.add_exp(int(exp_per_sec))

# 玩家方小兵路径（从己方水晶出发，依次经过己方高地、二塔、外塔，再攻击敌方外塔、二塔、高地，最终到敌方水晶）——发育路(上)
var player_waypoints_farm = [
		  # 己方水晶
	Vector3(-35,0,55),      # 己方发育路高地塔
	Vector3(-15,0,56),      # 己方发育路二塔
	Vector3(28,0,58),       # 己方发育路外塔
	Vector3(58,0,28),       # 敌方发育路外塔（敌方发育路外塔坐标）
	Vector3(56,0,-15),      # 敌方发育路二塔
	Vector3(55,0,-35),      # 敌方发育路高地塔
	Vector3(53,0,-53)       # 敌方水晶
]

var player_waypoints_mid = [

	Vector3(-40,0,40),      # 己方中路高地塔
	Vector3(-27,0,27),      # 己方中路二塔
	Vector3(-14,0,14),      # 己方中路外塔
	Vector3(14,0,-14),      # 敌方中路外塔
	Vector3(27,0,-27),      # 敌方中路二塔
	Vector3(40,0,-40),      # 敌方中路高地塔
	Vector3(53,0,-53)
]

var player_waypoints_clash = [

	Vector3(-55,0,35),      # 己方对抗路高地塔
	Vector3(-56,0,15),      # 己方对抗路二塔
	Vector3(-58,0,-28),     # 己方对抗路外塔
	Vector3(-28,0,-58),     # 敌方对抗路外塔
	Vector3(15,0,-56),      # 敌方对抗路二塔
	Vector3(35,0,-55),      # 敌方对抗路高地塔
	Vector3(53,0,-53)
]

# 敌方小兵路径（从敌方水晶出发，镜像路径）——对抗路(上)
var enemy_waypoints_clash = [
		 # 敌方水晶
	Vector3(35,0,-55),      # 敌方对抗路高地塔
	Vector3(15,0,-56),      # 敌方对抗路二塔
	Vector3(-28,0,-58),     # 敌方对抗路外塔
	Vector3(-58,0,-28),     # 己方对抗路外塔
	Vector3(-56,0,15),      # 己方对抗路二塔
	Vector3(-55,0,35),      # 己方对抗路高地塔
	Vector3(-53,0,53)       # 玩家水晶
]

var enemy_waypoints_mid = [

	Vector3(40,0,-40),
	Vector3(27,0,-27),
	Vector3(14,0,-14),
	Vector3(-14,0,14),
	Vector3(-27,0,27),
	Vector3(-40,0,40),
	Vector3(-53,0,53)
]

var enemy_waypoints_farm = [
		 # 敌方水晶
	Vector3(55,0,-35),      # 敌方发育路高地塔
	Vector3(56,0,-15),      # 敌方发育路二塔
	Vector3(58,0,28),       # 敌方发育路外塔
	Vector3(28,0,58),       # 己方发育路外塔
	Vector3(-15,0,56),      # 己方发育路二塔
	Vector3(-35,0,55),      # 己方发育路高地塔
	Vector3(-53,0,53)       # 玩家水晶
]
# 小兵基础属性表 (0分钟)
const MINION_BASE_TABLE = {
	"melee":    {"lane": {"health": 1860, "attack": 60, "armor": 180, "mr": 60},   "mid": {"health": 1488, "attack": 60, "armor": 180, "mr": 60}},
	"ranged":   {"lane": {"health": 1530, "attack": 90, "armor": 180, "mr": 60},   "mid": {"health": 1224, "attack": 120, "armor": 180, "mr": 60}},
	"siege":    {"health": 3355, "attack": 210, "armor": 180, "mr": 60},
	"super":    {"health": 5239, "attack": 631, "armor": 200, "mr": 200},
	"dragon":   {"health": 4878, "attack": 186, "armor": 300, "mr": 300},
	"storm":        {"health": 9756, "attack": 186, "armor": 300, "mr": 300},   # 风暴先锋：2× 龙兵血量
	"shadow_dragon":{"health": 12195, "attack": 279, "armor": 400, "mr": 200},  # 暗影先锋：2.5×HP/1.5×AD
}

# 成长曲线表 (时间: 分钟, 生命值, 攻击力)
const GROWTH_TABLE = {
	"melee_lane":   [ [4,2328,65], [10,3132,75], [15,3801,85], [20,7440,180], [25,9300,225] ],
	"melee_mid":    [ [4,1862,65], [10,2505,75], [15,3040,85], [20,5952,180], [25,7440,225] ],
	"ranged_lane":  [ [4,1915,101],[10,2576,131],[15,3127,170],[20,6120,360],[25,7650,450] ],
	"ranged_mid":   [ [4,1532,101],[10,2060,131],[15,2501,170],[20,4896,360],[25,6120,450] ],
	"siege":        [ [10,4513,242],[15,5477,272],[20,10720,576],[25,13400,720] ],
	"super":        [ [10,6000,700], [15,7500,800], [20,15000,1500], [25,19000,2200] ],   # 超级兵简化成长
	"dragon":       [ [10,5500,580], [15,8500,710], [20,16500,920], [25,19000,1040] ],    # 主宰先锋简化成长
	"storm":        [ [10,11000,580], [15,17000,710], [20,33000,920], [25,38000,1040] ],   # 风暴先锋 2×血量
	"shadow_dragon":[ [10,13750,870], [15,21250,1065], [20,41250,1380], [25,47500,1560] ], # 暗影先锋 2.5×HP/1.5×AD
}

# 根据时间计算小兵当前属性
func _get_minion_stats(type: String, game_time_min: float, is_mid: bool) -> Dictionary:
	var base
	if type in ["melee", "ranged"]:
		base = MINION_BASE_TABLE[type]["mid" if is_mid else "lane"]
	else:
		base = MINION_BASE_TABLE[type]

	var health = base.health
	var attack = base.attack
	var t
	var h
	var a
	# 成长曲线
	var growth_key = type + ("_mid" if is_mid else "_lane") if type in ["melee", "ranged"] else type
	var growths = GROWTH_TABLE.get(growth_key, [])
	for i in range(growths.size()):
		if i == 0:
			t = 0
			h = base.health
			a = base.attack
		else:
			t = growths[i-1][0]
			h = growths[i-1][1]
			a = growths[i-1][2]
		if game_time_min < growths[i][0]:
			# 线性插值到下一个节点
			if i < growths.size() - 1:
				var next_t = growths[i][0]
				var next_h = growths[i][1]
				var next_a = growths[i][2]
				var factor = (game_time_min - t) / (next_t - t)
				health = h + (next_h - h) * factor
				attack = a + (next_a - a) * factor
			else:
				# 最后一个节点，线性继续增长
				health = h + (game_time_min - t) * ((h - growths[i-1][1]) / (t - growths[i-1][0]+0.001))
				attack = a + (game_time_min - t) * ((a - growths[i-1][2]) / (t - growths[i-1][0]+0.001))
			break

	return {
		"health": health,
		"attack": attack,
		"armor": base.get("armor", 0),
		"magic_resist": base.get("mr", 0)
	}
func _spawn_minion_wave():
	if _training_mode and not _training_minions:
		return
	var include_siege = game_time > 240.0   # 4分钟后出炮车
	# 出生偏移：跑车离水晶最近(最后)，近战/超级离高地塔最近(最前)
	const OFFSET_MELEE: float = 5.0      # 近战/超级/主宰 — 最前
	const OFFSET_RANGED: float = 2.5     # 远程 — 中间
	const OFFSET_SIEGE: float = 0.5      # 炮车 — 最后（离水晶最近）
	# 玩家方
	var i = 0
	for line in [player_waypoints_farm, player_waypoints_mid, player_waypoints_clash]:
		var base = Vector3(-53,0,53)
		var lane_dir = (line[1] - line[0]).normalized()
		var team = Config.Team.PLAYER
		if dominant_buff_team == team and dragon_count < dragon_minion_budget:
			if dragon_count == 0:
				var wave_name := "风暴先锋" if dragon_minion_type == "storm" else "主宰先锋"
				ui.show_kill_feed(wave_name,dominant_buff_team,"出动！")
				print("[EPIC] t=%.0f %s波次出动 type=%s budget=%d" % [game_time, wave_name, dragon_minion_type, dragon_minion_budget])
			dragon_count += 1
			var wave_type := "storm" if dragon_minion_type == "storm" else "dragon"
			_queue_minion(wave_type, team, base + lane_dir * OFFSET_MELEE, line, i)
			continue
		if dragon_count >= dragon_minion_budget:
			dominant_buff_team = -1
			dragon_count = 0
		_queue_minion("melee", team, base + lane_dir * OFFSET_MELEE, line, i)
		if include_siege:
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
			_queue_minion("siege", team, base + lane_dir * OFFSET_SIEGE, line, i)
		else:
			if line == player_waypoints_mid:
				_queue_minion("melee", team, base + lane_dir * OFFSET_MELEE, line, i)
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
		i +=1
	# 敌方同理，镜像
	i = 0
	for line in [enemy_waypoints_farm, enemy_waypoints_mid, enemy_waypoints_clash]:
		var base = Vector3(53,0,-53)
		var lane_dir = (line[1] - line[0]).normalized()
		var team = Config.Team.ENEMY
		if dominant_buff_team == team and dragon_count < dragon_minion_budget:
			if dragon_count == 0:
				var wave_name := "风暴先锋" if dragon_minion_type == "storm" else "主宰先锋"
				ui.show_kill_feed(wave_name,dominant_buff_team,"出动！")
				print("[EPIC] t=%.0f %s波次出动 type=%s budget=%d" % [game_time, wave_name, dragon_minion_type, dragon_minion_budget])
			dragon_count += 1
			var wave_type := "storm" if dragon_minion_type == "storm" else "dragon"
			_queue_minion(wave_type, team, base + lane_dir * OFFSET_MELEE, line, i)
			continue
		if dragon_count >= dragon_minion_budget:
			dominant_buff_team = -1
			dragon_count = 0
		_queue_minion("melee", team, base + lane_dir * OFFSET_MELEE, line, i)
		if include_siege:
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
			_queue_minion("siege", team, base + lane_dir * OFFSET_SIEGE, line, i)
		else:
			if line == enemy_waypoints_mid:
				_queue_minion("melee", team, base + lane_dir * OFFSET_MELEE, line, i)
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
			_queue_minion("ranged", team, base + lane_dir * OFFSET_RANGED, line, i)
		i +=1
# 兵线分帧生成：整波兵入队，_process 每帧生成 2 个（约 10 帧出齐，实际延迟 <0.2s）
func _queue_minion(type: String, team: int, pos: Vector3, waypoints: Array, line: int) -> void:
	_minion_spawn_queue.append({"type": type, "team": team, "pos": pos, "wp": waypoints, "line": line})

func _drain_minion_spawn_queue() -> void:
	var budget := 2
	while budget > 0 and not _minion_spawn_queue.is_empty():
		var e: Dictionary = _minion_spawn_queue.pop_front()
		spawn_single_minion(str(e["type"]), int(e["team"]), e["pos"], e["wp"], int(e["line"]))
		budget -= 1

func spawn_single_minion(type: String, team: int, pos: Vector3, waypoints: Array,line) -> Minion:
	var m = Minion.new()

	#print(line)
	# 判断分路（X+Z>0=发育路, <0=对抗路, ==0=中路）
	var s = waypoints[0].x + waypoints[0].z
	var is_mid = s == 0
	var lane = ""
	if s > 0:
		lane = "farm"
	elif s < 0:
		lane = "clash"
	else:
		lane = "mid"

	# 如果该分路高地被摧毁，替换为超级兵；出动播报只在高地塔摧毁时触发一次
	if high_tower_destroyed[1-team].get(lane, false) and type in ["siege"]:
		type = "super"
	# 获取动态属性
	var stats = _get_minion_stats(type, game_time / 60.0, is_mid)

	var config = {
		"team": team,
		"max_health": stats.health,
		"attack": stats.attack,
		"armor": 380 if game_time<240  and  is_mid else stats.armor,
		"magic_resist": stats.magic_resist if game_time>240 else 180,
	}
	# 攻速、体积、移速等固定值补充
	match type:
		"melee":    config.merge({"attack_range":200, "attack_speed":0.7, "body_radius":0.7, "move_speed":350})
		"ranged":   config.merge({"attack_range":750, "attack_speed":0.6, "body_radius":0.7, "move_speed":350})
		"siege":    config.merge({"attack_range":800, "attack_speed":0.8, "body_radius":0.8, "move_speed":350})
		"super":    config.merge({"attack_range":250, "attack_speed":0.5, "body_radius":1.2, "move_speed":350})
		"dragon":   config.merge({"attack_range":700, "attack_speed":0.5, "body_radius":1.0, "move_speed":350})
		"storm":        config.merge({"attack_range":700, "attack_speed":0.5, "body_radius":1.0, "move_speed":350})
		"shadow_dragon":config.merge({"attack_range":700, "attack_speed":0.5, "body_radius":1.5, "move_speed":350})

	# 其他固定属性
	match type:
		"melee":
			config["kill_gold"] = 55
			config["kill_exp"] = 80
		"ranged", "mage":
			config["kill_gold"] = 43
			config["kill_exp"] = 50
		"siege":
			config["kill_gold"] = 72
			config["kill_exp"] = 100
		"dragon":
			config["kill_gold"] = 120
			config["kill_exp"] = 100
			pos.y =2
		"storm", "shadow_dragon":
			config["kill_gold"] = 120
			config["kill_exp"] = 100
			pos.y =2
		"super":
			config["kill_gold"] = 150
			config["kill_exp"] = 120
	# 主宰进化增幅（先知主宰波次）：头=攻击 / 躯干=血量 / 手臂=攻速 ×1.25
	if dragon_minion_boost and type in ["dragon", "storm"]:
		match dragon_evolution_part:
			0: config["attack"] = int(config["attack"] * 1.25)
			1: config["max_health"] = int(config["max_health"] * 1.25)
			2: config["attack_speed"] = config["attack_speed"] * 1.25
	var bonus = min(game_time / 120.0 * 0.05, 0.35)
	config["name"] = type
	config["attack_speed"] *= bonus+1
	config["move_speed"] *= bonus+1
	m.setup(config)
	m.line = line
	m.waypoints = waypoints
		# 设置路点，终点为敌方水晶

	m.global_position = pos

	add_child(m)
	minions.append(m)
	return m

# —— 右半屏拖拽相机：读取 TouchController 手势，每帧增量累加 / 松手平滑回正 cam_pan_offset ——
func _update_cam_pan():
	if game_over or not hero or not is_instance_valid(hero):
		cam_pan_offset = Vector3.ZERO
		cam_pan_prev_valid = false
		_cam_touch_decay = false
		return
	# 仅第三人称 & 存活时允许触摸拖拽（死亡 / 第一人称下禁止并把触摸平移量回正）
	var allow := not first_person_view and not hero.is_dead and TouchController.camera_pan_active()
	if not allow:
		cam_pan_prev_valid = false
		# 桌面中键的自由镜头松手保持，不做回正；只有手机端触摸松手后回正
		if not _cam_touch_decay:
			return
		if cam_pan_offset.length() < 0.05:
			cam_pan_offset = Vector3.ZERO
			_cam_touch_decay = false
		else:
			var d := get_process_delta_time()
			cam_pan_offset = cam_pan_offset.lerp(Vector3.ZERO, clampf(d * 10.0, 0.0, 1.0))
		return
	_cam_touch_decay = true
	var cur := TouchController.get_camera_pan_current()
	if cam_pan_prev_valid:
		var ga := _ground_from_screen(cam_pan_prev_screen, hero.global_position.y)
		var gb := _ground_from_screen(cur, hero.global_position.y)
		var _cam_sens: float = PlayerPrefs.opt_float("cam_sens", 1.0)
		cam_pan_offset += Vector3(ga.x - gb.x, 0.0, ga.z - gb.z) * _cam_sens
		# 限制拖拽距离，避免把镜头甩到地图另一端
		if cam_pan_offset.length() > 45.0:
			cam_pan_offset = cam_pan_offset.normalized() * 45.0
	else:
		cam_pan_prev_valid = true
	cam_pan_prev_screen = cur

# 屏幕坐标 → 地平面世界坐标（用于把手指拖动换算成相机平移）
func _ground_from_screen(screen: Vector2, plane_y: float) -> Vector3:
	var origin: Vector3 = cam.project_ray_origin(screen)
	var dir: Vector3 = cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3(origin.x, plane_y, origin.z)
	var t: float = (plane_y - origin.y) / dir.y
	return origin + dir * t

func _unhandled_input(event):
	if not hero_selected or intro_active or building_battle:
		return
	if _ai_test_match:
		return   # 测试局：玩家不能直接操作英雄/战场，只允许 HUD 观战按钮
	if _training_mode and event is InputEventKey and event.pressed and not event.echo:
		if _training_handle_hotkey(event):
			return

	# 中键：桌面自由镜头拖动平移（松手保持偏移，按 Y 回正）
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_cam_mid_drag = event.pressed
		if not event.pressed:
			cam_pan_prev_valid = false
		return
	if event is InputEventMouseMotion and _cam_mid_drag:
		var _cs: float = PlayerPrefs.opt_float("cam_sens", 1.0)
		cam_pan_offset.x -= event.relative.x / 60.0 * _cs
		cam_pan_offset.z += event.relative.y / 60.0 * _cs
		if cam_pan_offset.length() > 45.0:
			cam_pan_offset = cam_pan_offset.normalized() * 45.0
		_cam_touch_decay = false
		return
	if event is InputEventKey and event.keycode == KEY_Y and event.pressed:
		cam_pan_offset = Vector3.ZERO
		_cam_mid_drag = false
		_cam_touch_decay = false
		return

	# Tab：切换第一人称/第三人称视角
	if event is InputEventKey and event.keycode == KEY_TAB and event.pressed:
		_set_camera_mode(not first_person_view)

	# F3：AI 思考过程覆盖层
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		if _ai_dbg != null:
			_ai_dbg.visible = not _ai_dbg.visible
			_ai_dbg_t = 0.0
			print("[Debug] AI思考覆盖层: ", "开" if _ai_dbg.visible else "关")
		return

	# F5：隐藏/显示 AI 决策胶囊
	if event is InputEventKey and event.keycode == KEY_F5 and event.pressed and not event.echo:
		GameEntity.debug_show_ai_chip = not GameEntity.debug_show_ai_chip
		print("[Debug] AI决策胶囊: ", "开" if GameEntity.debug_show_ai_chip else "关")
		return

	# F4：切换AI的A*路径小球显示
	if event is InputEventKey and event.keycode == KEY_F4 and event.pressed:
		GameEntity.debug_show_path = not GameEntity.debug_show_path
		print("[Debug] A*路径显示: ", "开" if GameEntity.debug_show_path else "关")
		# 立即刷新所有实体的路径显示
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent is GameEntity:
				ent._update_debug_path_visual()

	# 空格键：锁定攻击范围内最近的敌方单位
	if event is InputEventKey and event.keycode == KEY_SPACE and event.pressed:
		if is_instance_valid(hero) and not hero.is_dead:
			var nearest_enemy: GameEntity = null
			var nearest_dist := 99999.0
			var atk_range := hero._aa_engage_reach()
			for entity in get_tree().get_nodes_in_group("entities"):
				if not (entity is GameEntity) or entity.health <= 0 or entity.team == hero.team:
					continue
				if entity is Hero and (entity as Hero).is_invisible_to_enemy():
					continue  # 隐身中的敌方英雄不可被空格锁定
				var dist := hero.global_position.distance_to(entity.global_position)
				if dist <= atk_range and dist < nearest_dist:
					nearest_dist = dist
					nearest_enemy = entity
			if nearest_enemy:
				hero.set_manual_target(nearest_enemy)

	# 移动端 emulate_mouse_from_touch 的合成鼠标事件已由 ScreenTouch 路径处理，跳过避免重复
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not Input.is_emulating_mouse_from_touch():
		# 确保英雄存在且有效
		if not is_instance_valid(hero):
			return
		var cam = get_viewport().get_camera_3d()
		var from = cam.project_ray_origin(event.position)
		var to = from + cam.project_ray_normal(event.position) * 100
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collide_with_bodies = true
		query.collision_mask = 1
		var result = space_state.intersect_ray(query)
		if result and result.collider is GameEntity:
			# 隐身中的敌方英雄不可被点击锁定（如隐身的兰陵王）
			if result.collider is Hero and (result.collider as Hero).is_invisible_to_enemy():
				hero.set_manual_target(null)
			elif result.collider.team != hero.team:
				hero.set_manual_target(result.collider)
			else:
				hero.set_manual_target(null)
		else:
			hero.set_manual_target(null)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not is_instance_valid(hero):
				return
			var cam = get_viewport().get_camera_3d()
			var from = cam.project_ray_origin(event.position)
			var to = from + cam.project_ray_normal(event.position) * 100
			var sp_st = get_world_3d().direct_space_state
			# 正常移动
			var space_state = sp_st
			var query = PhysicsRayQueryParameters3D.create(from, to)
			query.collision_mask = 2
			var result = space_state.intersect_ray(query)
			if result:
				hero.move_towards(result.position)

# 移动端已取消「点击地面移动 / 点击地面选目标」：移动只靠左轮盘/按键，目标靠普攻轮盘与技能拖拽选择。
# 切换摄像机视角模式（第一人称/第三人称）
func _set_camera_mode(first_person: bool):
	first_person_view = first_person
	if first_person_view:
		# 第一人称：拉大FOV，隐藏自身模型避免遮挡视野
		cam.fov = 90.0
		if is_instance_valid(hero) and hero.visual_mesh:
			hero.visual_mesh.visible = false
	else:
		# 恢复俯视视角（回到第三人称时硬设一次，避免从头部缓慢拉出）
		_cam_snap = true
		cam.fov = 70.0
		cam.rotation_degrees = Vector3(-60, rad_to_deg(cam_yaw), 0)
		if is_instance_valid(hero) and hero.visual_mesh:
			hero.visual_mesh.visible = true
var game_over: bool = false
var winner: int = -1
var rank_result: Dictionary = {}   # 本局单机排位结算（升/降星、晋升信息），联机为空
var last_dragon_kill_team := -1      # 最近一条龙（史诗生物）击杀方
var last_dragon_kill_time := -999.0  # 最近一条龙击杀的游戏时间

func crystal_destroyed(team: int):
	if _training_mode:
		return   # 训练营不结算胜负，允许继续测试
	if game_over: return
	game_over = true
	# 赛后统计：记录最终数据
	_last_recorded_minute = int(game_time / 60)
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero:
			entity.gold_history.append(entity.total_gold_earned)
	team_gold_diff_history.append(team_player_gold - team_enemy_gold)
	if team == Config.Team.PLAYER:
		winner = Config.Team.ENEMY
	else:
		winner = Config.Team.PLAYER
	# 胜负语音（host/离线；接管客户端由 NetResultPanel 收到结算广播时各自播）
	SfxManager.play_announce("victory" if winner == Config.player_team else "defeat")
	# 对战纪录：写入 user://battle_history.json（大厅「对战纪录」页回看）
	# 排位结算：胜 +1 星、负 -1 星；联机客户端由 NetResultPanel 各自结算
	# 测试局只演出不结算：不为玩家加减排位积分，也不写入玩家战绩/云端
	var local_rank_match := not ("--net-test" in OS.get_cmdline_user_args()) and not _ai_test_match
	if local_rank_match:
		var player_mvp := is_instance_valid(hero) and hero.is_mvp
		# 奖牌：铜 +12 / 银 +33 / 金 +100；评分 >90 额外 +200（均叠加在基础胜负积分上）
		var pm_team: Array = _pm_team_list(Config.player_team)
		var pm_rating: float = _pm_rating(hero, pm_team) if is_instance_valid(hero) else 0.0
		var pm_medal: int = MatchResultScript.medal_by_rating(pm_rating) if is_instance_valid(hero) else -1
		var medal_bonus: int = MatchResultScript.medal_bonus(pm_medal)
		var top_bonus: int = MatchResultScript.top_bonus(pm_rating)
		var pm_bonus: int = medal_bonus + top_bonus
		rank_result = RankSystem.apply_result(winner == Config.player_team, player_mvp, pm_bonus)
		rank_result["medal"] = pm_medal
		rank_result["medal_bonus"] = medal_bonus
		rank_result["top_bonus"] = top_bonus
		rank_result["rating"] = pm_rating
	# 对战纪录/云端：测试局不写入玩家数据
	if not _ai_test_match:
		var __hist := BattleHistory.payload_from_battle(self)
		__hist["rank"] = rank_result
		BattleHistory.record(__hist, "联机" if NetSession.is_online() else "单机")
		# 云端存档：开启「赛后自动上传」时把段位+对战纪录同步到云端（未配置则空操作）
		CloudSyncScript.auto_upload(get_tree())
	# 终局：先播 5 秒水晶爆炸 → 中央美术字（胜利/失败）→ 再进结算面板并冻结战场
	# 单机与联机统一走同一套终局演出（水晶爆炸 → EndBanner → 聚光灯舞台 → 个人表现 → 结算页）；
	# 联机结算数据仍由 NetSession 在 game_over 翻转时广播给客户端，不受演出时长影响。
	_play_end_sequence(team, winner == Config.player_team)

var _end_seq_on: bool = false
var _pm_stage_node: PostMatchStage = null
var _pm_view: Control = null
var _pm_layer: CanvasLayer = null
var _pm_heroes: Array = []
var _pm_player: Hero = null
var _pm_stage: Vector3 = Vector3.ZERO
var _pm_inward: Vector3 = Vector3.ZERO
var _pm_right: Vector3 = Vector3.ZERO
var _pm_env: Environment = null
var _pm_key: DirectionalLight3D = null
var _pm_hidden: Array = []
var _pm_lights: Array = []

## 测试局结束：等录像落盘后回主菜单（3 秒真实时间，ignore_time_scale）
func _finish_ai_test_match() -> void:
	await get_tree().create_timer(3.0, true, false, true).timeout
	var rec = get_tree().get_first_node_in_group("replay_recorder")
	if rec != null and rec.has_method("flush_save"):
		rec.call("flush_save")
	await get_tree().create_timer(1.0, true, false, true).timeout
	_ai_test_match = false
	_test_paused = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


## 终局演出（单机/离线 host）：won=true 为胜利（敌方水晶炸），false 为失败（我方水晶炸）
func _play_end_sequence(team: int, won: bool) -> void:
	_end_seq_on = true
	var pos := _crystal_world_pos(team)
	_focus_camera_on(pos, 1.1)
	_crystal_explosion(pos, won)
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func(): _show_end_banner(won))

func _show_end_banner(won: bool) -> void:
	var banner: Control = EndBannerScript.new()
	banner.name = "EndBanner"
	banner.set("won", won)
	var host: Node = ui if ui != null else self
	host.add_child(banner)
	banner.finished.connect(func():
		_enter_post_match(won)
		# 兜底：聚光灯层没建起来（或英雄都没收集到）就直接进结算，避免停在黑屏且点击无反应
		if _pm_view == null or not is_instance_valid(_pm_view):
			_show_game_over(true))
## 聚光灯舞台（终局第一幕）：己方 5 人 V 字站位（玩家居中）→ 点击 → 玩家个人表现 → 再点击 → 结算
func _enter_post_match(won: bool) -> void:
	if not is_instance_valid(hero):
		_show_game_over(true)
		return
	_pm_player = hero
	get_tree().paused = true
	if ui != null:
		ui.visible = false
	if is_instance_valid(TouchController):
		TouchController.set_intro_hidden(true)
	# 战场退场：隐藏其余所有场景物件（只留己方 5 人），镜头背景改为纯黑
	_pm_hidden.clear()
	for child in get_children():
		if child is Hero or child == cam:
			continue
		# CanvasLayer / 3D 场景物件 / 普通 Control（小地图等直挂在 BattleManager 上的 HUD）全部退场
		if child is CanvasLayer or child is Node3D or child is Control:
			child.visible = false
			_pm_hidden.append(child)
	if cam != null and is_instance_valid(cam):
		_pm_env = Environment.new()
		_pm_env.background_mode = Environment.BG_COLOR
		_pm_env.background_color = Color(0.0, 0.0, 0.0)
		_pm_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_pm_env.ambient_light_color = Color(0.24, 0.27, 0.34)
		_pm_env.ambient_light_energy = 1.05
		_pm_env.glow_enabled = true
		_pm_env.glow_intensity = 0.55
		cam.environment = _pm_env
		# 主光：从镜头方向斜上方打一盏平行光，保证 5 个英雄轮廓清晰（单纯聚光灯偏暗）
		var key := DirectionalLight3D.new()
		key.light_color = Color(0.98, 0.95, 0.90)
		key.light_energy = 1.35
		key.shadow_enabled = false
		add_child(key)
		_pm_key = key
		_pm_lights.append(key)
	# 收集 5 名己方英雄（玩家居中垫前，其余 4 人补位）
	_pm_heroes.clear()
	_pm_heroes.append(_pm_player)
	for h in get_tree().get_nodes_in_group("heroes"):
		if h is Hero and h != _pm_player and h.team == Config.player_team and _pm_heroes.size() < 5:
			_pm_heroes.append(h)
	# 评分 / 奖牌 / MVP：统一走 MatchResult（三端同一口径）
	var team_list: Array = _pm_team_list(Config.player_team)
	var medal_of: Dictionary = {}
	var mvp_hero: Hero = _pm_player
	var best_r := -1.0
	for eh in _pm_heroes:
		var rr: float = MatchResultScript.rating(eh, team_list)
		medal_of[eh] = MatchResultScript.medal_by_rating(rr)
		if rr > best_r:
			best_r = rr
			mvp_hero = eh
	var entries: Array = []
	for hh in _pm_heroes:
		entries.append({
			"world": hh.global_position,
			"hero": str(hh.display_name),
			"nick": str(hh.player_name),
			"lane": HeroPickData.role_lane(str(hh.role)),
			"mvp": hh == mvp_hero,
			"medal": int(medal_of.get(hh, -1)),
			"node": hh,
		})
	# 舞台本体：站位 / 聚光灯 / 黑背景 + 主光 / 铭牌层 / 镜头，全部由共享 PostMatchStage 负责
	_pm_stage_node = PostMatchStageScript.new()
	_pm_stage_node.name = "PostMatchStage"
	add_child(_pm_stage_node)
	_pm_stage_node.detail_provider = func() -> Dictionary: return _pm_player_detail(_pm_player)
	_pm_stage_node.finished.connect(_on_pm_finished)
	_pm_stage_node.setup(self, cam, _pm_heroes, entries, won, 0, {"own_team": Config.player_team})
	_pm_view = _pm_stage_node.view

## 某一方队伍英雄列表（评分归一化用）
func _pm_team_list(team: int) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("heroes"):
		if n is Hero and int(n.team) == team:
			out.append(n)
	return out


## 对战评分 0~100（与结算页评分同公式：队伍内归一化后加权）
func _pm_rating(h: Hero, team_heroes: Array) -> float:
	# 三端统一口径：MatchResult.rating（不要在这里再写第二份公式）
	return MatchResultScript.rating(h, team_heroes)


## 奖牌门槛（依据对战评分，评分不够没有奖牌）：0=金 1=银 2=铜 -1=无
func _pm_medal_by_rating(r: float) -> int:
	return MatchResultScript.medal_by_rating(r)


## 奖牌额外积分（数值由 RankSystem 统一维护）
func _pm_medal_bonus(medal: int) -> int:
	return MatchResultScript.medal_bonus(medal)

## 玩家个人表现数据（右侧面板 + 本局上/掉分）
func _pm_player_detail(h: Hero) -> Dictionary:
	var rows: Array = [
		["K / D / A", "%d / %d / %d" % [h.kills, h.deaths, h.assists]],
		["总经济", "%d" % h.total_gold_earned],
		["英雄伤害", "%d" % int(h.damage_dealt_to_heroes)],
		["承受伤害", "%d" % int(h.damage_taken_from_heroes)],
		["治疗量", "%d" % int(h.healing_done)],
		["补刀", "%d" % h.last_hits],
		["推塔伤害", "%d" % int(h.turret_damage)],
		["控制时长", "%.1f s" % h.cc_duration_dealt],
		["野区经济", "%d" % h.jungle_gold],
	]
	var rank_lines: Array = MatchResultScript.rank_lines(rank_result, game_time)
	return {
		"hero": str(h.display_name),
		"nick": str(h.player_name),
		"lane": HeroPickData.role_lane(str(h.role)),
		"mvp": bool(h.is_mvp),
		"rating": _pm_rating(h, _pm_team_list(int(h.team))),
		"medal": int(rank_result.get("medal", -1)) if not rank_result.is_empty() else -1,
		"rows": rows,
		"rank_lines": rank_lines,
	}


## 第二次点击：收掉舞台层，进结算面板
func _on_pm_finished() -> void:
	if _pm_view != null and is_instance_valid(_pm_view):
		_pm_view.queue_free()
	_pm_view = null
	if _pm_layer != null and is_instance_valid(_pm_layer):
		_pm_layer.queue_free()
	_pm_layer = null
	for n in _pm_lights:
		if is_instance_valid(n):
			n.queue_free()
	_pm_lights.clear()
	_pm_key = null
	for n in _pm_hidden:
		if is_instance_valid(n):
			n.visible = true
	_pm_hidden.clear()
	if cam != null and is_instance_valid(cam):
		cam.environment = null
	_pm_env = null
	if ui != null:
		ui.visible = true
	if is_instance_valid(TouchController):
		TouchController.set_intro_hidden(false)
	_show_game_over(true)


func _crystal_world_pos(team: int) -> Vector3:
	for t in turrets:
		if is_instance_valid(t) and t.team == team and str(t.display_name) == "crystal":
			return t.global_position
	return Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)

## 演出期间把镜头锁到水晶（game_over 后 _physics_process 已停跟镜头，这里直接补间）
func _focus_camera_on(pos: Vector3, dur: float) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var dir := Vector3(-pos.x, 0.0, -pos.z).normalized()   # 从地图内侧看水晶，避免被外墙挡住
	if dir == Vector3.ZERO:
		dir = Vector3(0, 0, 1)
	var cam_end: Vector3 = pos + dir * 24.0 + Vector3(0, 24.0, 0)
	var rot: Vector3 = Basis.looking_at((pos + Vector3(0, 2.5, 0) - cam_end).normalized(), Vector3.UP).get_euler()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cam, "global_position", cam_end, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(cam, "rotation", rot, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## 水晶爆炸：碎石四散 + 地面焦痕 + 5 秒递增冲击波/闪光/震屏，最后白闪收尾
## won=true 时整体走金白色调，失败走冷蓝+橙火色调
func _crystal_explosion(pos: Vector3, won: bool) -> void:
	# 与联机客户端 / 回放共用同一份终章爆炸实现（scripts/fx/CrystalFinale.gd），保证三端动画一致
	var fx := CrystalFinaleScript.new()
	fx.name = "CrystalFinale"
	add_child(fx)
	fx.play(pos, won)

func _show_game_over(halt: bool = false):
	var _is_test := _ai_test_match
	if _is_test:
		# 测试局结束：恢复时间倍速、清暂停、隐藏测试控制条；结算面板抑制排位加减
		Engine.time_scale = 1.0
		_test_paused = false
		_ai_test_match = false
		if _test_layer != null and is_instance_valid(_test_layer):
			_test_layer.visible = false
	get_tree().paused = false  # 取消暂停以便结算面板交互
	if ui and ui.death_overlay:
		ui.death_overlay.visible = false
	var panel = ResultsPanel.new()
	add_child(panel)
	panel.suppress_rank = _is_test
	panel.setup(self)
	if halt:
		# 终局：冻结战场上的所有进程（结算面板自身是 PROCESS_MODE_ALWAYS，不受影响）
		get_tree().paused = true
func spawn_exp_orb(world_pos: Vector3, target: Hero, amount: int):
	# 亮核 + 双层菲涅尔光晕；生成时弹性放大，再飞向目标英雄（尺寸再收一档、飞行更慢、带拖尾）
	var orb: Node3D = MeshFactory.create_exp_orb(0.085)
	orb.position = world_pos + Vector3.UP * 1.0
	orb.scale = Vector3(0.26, 0.26, 0.26)
	add_child(orb)
	Vfx.attach_trail(orb, Color(0.42, 1.0, 0.60), 0.12, 0.24, 8, Color(0.86, 1.0, 0.90, 0.55))

	var tween = create_tween()
	tween.tween_property(orb, "scale", Vector3(0.62, 0.62, 0.62), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(orb, "position", target.global_position + Vector3.UP * 1.5, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		target.add_exp(amount)
		orb.queue_free()
	)
	


## 刷新 F3 AI 思考覆盖层（信息量尽量全）
func _refresh_ai_debug() -> void:
	if _ai_dbg == null:
		return
	var snaps: Array = []
	for h in get_tree().get_nodes_in_group("heroes"):
		if h is Hero and h.is_ai and not h.net_taken:
			var snap: Dictionary = h.call("ai_debug_snapshot")
			if not snap.is_empty():
				snaps.append(snap)
	var txt: String = AIDebugFormatScript.all(snaps, "AI 思考过程（F3 关闭）", "对局时间 %.1fs" % float(game_time))
	_ai_dbg.set_text(txt)
