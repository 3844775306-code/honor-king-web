extends Node3D
## 录像回放（P1）：读 user://replays/*.rep，只重建视觉，不跑战斗逻辑。
## 入口：大厅「录像」→ ReplayBrowserPanel 设置 pending_file 后切到本场景。

const Repo = preload("res://scripts/core/ReplayRecorder.gd")
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const WorldBarPainterScript = preload("res://scripts/ui/WorldBarPainter.gd")
const DeathRecapViewScript = preload("res://scripts/ui/DeathRecapView.gd")
const NetBuffRowScript = preload("res://scripts/net/NetBuffRow.gd")
const AnimMap = preload("res://scripts/presentation/AnimMap.gd")
const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
const WukongCloudScript = preload("res://scripts/fx/WukongCloud.gd")   # 三端共享动画 clip 映射
const ProjectilePresenter = preload("res://scripts/presentation/ProjectilePresenter.gd")   # 三端共享子弹表现
const SkillFxPresenter = preload("res://scripts/presentation/SkillFxPresenter.gd")   # 三端共享技能特效
const NetTouchPadScript = preload("res://scripts/net/NetTouchPad.gd")
const NetRecommendBarScript = preload("res://scripts/net/NetRecommendBar.gd")
const NetTargetPanelScript = preload("res://scripts/net/NetTargetPanel.gd")
const RosterViewScript = preload("res://scripts/ui/RosterView.gd")
const NetKillFeedScript = preload("res://scripts/net/NetKillFeed.gd")
const NetRecallScript = preload("res://scripts/net/NetRecall.gd")
const TeamDecisionViewScript = preload("res://scripts/ui/shared/TeamDecisionView.gd")
const ChatBoxScript = preload("res://scripts/ui/ChatBox.gd")
const EndBannerScript = preload("res://scripts/ui/EndBanner.gd")
const CrystalFinaleScript = preload("res://scripts/fx/CrystalFinale.gd")
const MatchResultScript = preload("res://scripts/core/MatchResult.gd")
const PostMatchStageScript = preload("res://scripts/ui/PostMatchStage.gd")
const PostMatchViewScript = preload("res://scripts/ui/PostMatchView.gd")
const NetResultPanelScript = preload("res://scripts/net/NetResultPanel.gd")
const HeroInfoControlScript = preload("res://scripts/ui/HeroInfoControl.gd")
const ReplayHudScript = preload("res://scripts/replay/ReplayHud.gd")
const TEAM_COL := [Color(0.28, 0.72, 1.0), Color(1.0, 0.36, 0.30)]
const TYPE_NAMES := ["melee", "ranged", "siege", "super", "dragon", "storm", "shadow_dragon"]
const TYPE_COL := [Color(0.80, 0.78, 0.72), Color(0.86, 0.72, 0.52), Color(0.62, 0.58, 0.66),
	Color(0.95, 0.86, 0.55), Color(0.55, 0.85, 1.0), Color(0.72, 0.62, 1.0), Color(0.62, 0.45, 0.85)]

static var pending_file := ""

# preload 的脚本常量不能直接给 static var 赋值（GDScript 会报“给常量重新赋值”），统一走 setter
static func set_pending_file(path: String) -> void:
	pending_file = path

var _doc: Dictionary = {}
var _heroes: Array = []
var _turrets: Array = []
var _frames: Array = []
var _minis: Array = []
var _health_frames: Array = []       # 录像血包状态关键帧
var _health_packs: Dictionary = {}   # key -> HealthPack 视觉节点
var _health_rows: Array = []         # 当前帧 [x,z,team,available]（HUD 小地图用）
var _events: Array = []
var _duration := 0.0
var _hero_nodes: Array = []
var _turret_nodes: Array = []
var _mini_nodes: Dictionary = {}     # id -> Node3D
var _jungle_meta: Array = []
var _bullets: Array = []
var _popups_data: Array = []
var _marker_src_cache: Dictionary = {}
var _recall_nodes: Dictionary = {}   # hero idx -> 回城/传送特效节点
var _mm_pings: Array = []
var _feed_items: Array = []
var _frame_obj: Array = []
var _mm_marks: Array = []
var _pops: Array = []
var _shake_t := 0.0
var _shake_amp := 0.0
var _shake_dur := 0.1
var _bullet_nodes: Dictionary = {}
var _bullet_last_pos: Dictionary = {}   # bullet id -> 上一帧小地图坐标（弹体朝向）   # id -> Node3D
var _jungle: Array = []
var _jungle_nodes: Array = []
var _map: Dictionary = {}
var _world: Node3D = null
var _hud_layer: CanvasLayer = null
var _hud_root: Control = null
var _bars: Control = null
var _dr_view = null
var _dr_layer: CanvasLayer = null
var _buff_frames: Array = []
var _buff_defs: Dictionary = {}
var _buff_ptr := 0
var _buff_view = null
var _buff_sig := ""
var _ui_frames: Array = []
var _ui_ptr := 0
var _pad = null
var _rec_bar = null
var _tgt_panel = null
var _rview = null
var _rview_layer: CanvasLayer = null
var _last_hero_rows: Array = []
var _flash_cache := {}   # 单位血条受伤闪橙：key -> {hp,t,amt}
var _lag_cache := {}     # 单位血条残血拖尾：key -> lag
var _rb_cache := {}
var _det_cache := {}      # hero idx -> 操作盘/HUD 细节（aa/sx/sa/summoner/recall）
var _tt_cache: Array = []
var _kfeed = null
var _recall_view = null
var _tdv = null
var _tdv_layer: CanvasLayer = null
var _me_team := 0
var _chat_events: Array = []
var _chat_ptr := 0
var _chat_box = null
var _final_rows: Array = []
var _ui_layer: CanvasLayer = null
var _end_started := false
var _end_cam_owned := false
var _banner_layer: CanvasLayer = null
var _banner = null
var _pm_view = null
var _pm_layer: CanvasLayer = null
var _pm_stage_node: PostMatchStage = null
var _pm_stage_root: Node3D = null
var _pm_env: WorldEnvironment = null
var _pm_key: DirectionalLight3D = null
var _pm_stage := Vector3.ZERO
var _pm_inward := Vector3.FORWARD
var _pm_right := Vector3.RIGHT
var _pm_player_node: Node3D = null
var _pm_payload: Dictionary = {}
var _result_layer: CanvasLayer = null
var _result_panel = null   # hero idx -> 最近一次推荐装 bundle（录像变化才记录，播放时续用）
var _hero_uis: Array = []          # [{info, fake, i}]
var _hero_state: Array = []        # 每帧英雄状态（血/蓝/等级/经验/位置）
var _unit_world: Array = []        # 本帧需要画血条的单位（世界坐标）
var _hud2: Control = null          # 小地图/英雄信息/技能/属性面板
var _follow_hero := -1             # 主视角跟随英雄（-1=自由镜头）
var _frame_gold: Array = [0, 0]
var _hud_static: Dictionary = {}     # 墙体/草丛（小地图烘焙用）
var _hud_turrets: Array = []
var _hud_minions: Array = []
var _hud_jungle: Array = []
var _mm_drag := false
var _spectate_origin := -1
var _mm_target := Vector3.ZERO
var _mm_was_follow := -1
var _statics: Node3D = null
var _cam: Camera3D = null
var _cam_yaw := 0.0
var _cam_pitch := -55.0
var _cam_dist := 62.0
var _cam_target := Vector3.ZERO
var _t := 0.0
var _playing := true
var _speed := 1.0
var _frame_ptr := 0
var _ev_ptr := 0
var _ui_time: Label = null
var _slider: HSlider = null
var _play_btn: Button = null
var _speed_btn: Button = null
var _title: Label = null
var _feed: VBoxContainer = null
var _event_toasts: Array = []
var _dragging := false
var _cam_drag := false          # 回放：直接拖动屏幕平移相机
var _cam_drag_moved := false
var _cam_drag_last := Vector2.ZERO
var _cam_drag_prev_follow := -1
const HINT_TEXT := "空格 播放/暂停 · ←/→ ±5秒（Shift ±1秒） · ↑/↓ 倍速 · 1~5 指定倍速 · N/J 下/上个击杀 · F 切换英雄（Shift+F 反向）\nP 集锦 · C 英雄面板 · T 团队面板 · Home/End 首尾 · PageUp/PageDown ±30秒 · R 重置镜头 · H 隐藏界面 · Esc 退出 · 左键平移/右键旋转/滚轮缩放"

var _hint_label: Label = null
var _finisher_t := -1.0
var _hero_pos: Array = []        # 每帧英雄世界坐标（镜头跟随用）
var _kill_cam_t := 0.0           # 击杀镜头剩余时间
var _kill_cam_idx := -1          # 击杀镜头目标英雄
var _manual_follow := -1         # 手动跟随英雄下标（-1=关闭）
var _kill_times: Array = []      # 所有击杀时刻（集锦模式用）
var _kill_heroes: Array = []     # 与 _kill_times 对应：击杀者英雄下标（集锦自动跟随）
var _hl_prev_manual := -1        # 进入集锦前的主视角，退出时恢复
var _highlight := false          # 集锦模式（只看击杀前后 3 秒）
var _hl_idx := 0
var _hl_end := -1.0
var _hl_btn: Button = null


func _ready() -> void:
	var path := pending_file
	if path == "":
		path = _latest_replay_path()
	_doc = Repo.load_replay(path)
	if _doc.is_empty():
		push_error("[REPLAY] 无法读取录像: " + path)
		_back_to_lobby()
		return
	_heroes = _doc.get("heroes", [])
	_turrets = _doc.get("turrets", [])
	_frames = _doc.get("frames", [])
	_minis = _doc.get("minions", [])
	_health_frames = _doc.get("health_packs", [])
	_jungle = _doc.get("jungle", [])
	_jungle_meta = _doc.get("jungle_meta", [])
	_bullets = _doc.get("bullets", [])
	_popups_data = _doc.get("popups", [])
	_buff_frames = _doc.get("buff_frames", [])
	_buff_defs = _doc.get("buff_defs", {})
	_ui_frames = _doc.get("ui_frames", [])
	_chat_events = _doc.get("chat", [])
	_final_rows = _doc.get("final", [])
	# 飘字/音效并入事件流（按时间排序），回放时与击杀/技能共用同一套推进逻辑
	var _combined: Array = (_doc.get("events", []) as Array).duplicate()
	_combined.append_array(_popups_data)
	_combined.append_array(_doc.get("audio", []))
	# 聊天事件此前只存进 _chat_events 供 seek 回填，没有并入主事件流，播放时永远不会触发
	_combined.append_array(_chat_events)
	_combined.sort_custom(func(a, b) -> bool: return int(a.get("t", 0)) < int(b.get("t", 0)))
	_events = _combined
	_map = _doc.get("map", {})
	var meta: Dictionary = _doc.get("meta", {})
	# 录像玩家阵营：优先 meta.player_team；旧录像缺失时用 meta.me 对应英雄的 team 回推，
	# 最后才退全局 Config.player_team（否则红方玩家的胜负会被当成蓝方判反）
	var _mt_raw: int = int(meta.get("player_team", -1))
	var _me_idx0: int = int(meta.get("me", -1))
	if (_mt_raw != 0 and _mt_raw != 1) and _me_idx0 >= 0 and _me_idx0 < _heroes.size():
		_mt_raw = int((_heroes[_me_idx0] as Dictionary).get("team", int(Config.player_team)))
	if _mt_raw != 0 and _mt_raw != 1:
		_mt_raw = int(Config.player_team)
	_me_team = _mt_raw
	Config.player_team = _me_team   # 回放视角=录像玩家阵营：警报/播报前缀按同一口径
	# 回放默认锁定录像玩家英雄视角；读取英雄列表后即可用 meta.me（旧录像无 me 则保持自由镜头）
	var _me_idx := int(meta.get("me", -1))
	if _me_idx >= 0 and _me_idx < _heroes.size():
		_follow_hero = _me_idx
		_manual_follow = _me_idx
	_duration = maxf(float(meta.get("duration", 0.0)), 1.0)
	for ev in _events:
		if str(ev.get("k", "")) == "k":
			_kill_times.append(float(ev.get("t", 0)) / 1000.0)
			_kill_heroes.append(int(ev.get("a", -1)))
	_build_world()
	_build_actors()
	_build_ui()
	_build_hud()
	_t = 0.0
	_apply_frame(0.0)


func _exit_tree() -> void:
	PostFX.set_dead(false)
	PostFX.set_low_hp(1.0)
	# fake hero 只是给 HeroInfoControl 提供字段，没进树，退出时手动释放
	for ui in _hero_uis:
		var fake = ui.get("fake")
		if fake != null and is_instance_valid(fake):
			fake.free()
	_hero_uis.clear()
	for k in _recall_nodes.keys():
		var rn = _recall_nodes[k]
		if rn != null and is_instance_valid(rn):
			rn.queue_free()
	_recall_nodes.clear()


func _latest_replay_path() -> String:
	var arr: Array = Repo.load_index()
	if arr.is_empty():
		return ""
	return str(arr[0].get("file", ""))


# ---------------- 场景 ----------------

func _build_world() -> void:
	# 与真实对局完全一致：用 BattleManager 的「只建地图」模式生成地形/分路/高地/河道/
	# 泉水/装饰/墙体/草丛（同一份代码，不存在两套地形）。
	var bm := BattleManager.new()
	bm.name = "ReplayMap"
	bm.set_meta("map_only", true)
	add_child(bm)
	bm.remove_from_group("battle_manager")   # 别让 HUD/触控把它当成正在进行的对局
	bm.set_process(false)
	bm.set_physics_process(false)
	bm.process_mode = Node.PROCESS_MODE_DISABLED
	_world = bm
	# 回放世界里的血包：有状态关键帧时由 _apply_replay_health_packs 动态创建；
	# 旧录像没有该字段则回退固定点位全可用。
	if _health_frames.is_empty():
		for hp_spawn in BattleManager.HEALTH_PACK_SPAWNS:
			_make_replay_health_pack(hp_spawn[0].x, hp_spawn[0].z, int(hp_spawn[1]))
			_health_rows.append([hp_spawn[0].x, hp_spawn[0].z, int(hp_spawn[1]), 1])
	# 小地图静态数据（墙体/草丛）
	var _walls: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		if is_instance_valid(w):
			_walls.append([w.global_position.x, w.global_position.z, w.rotation.y,
				float(w.get("continuous_len") if w.get("continuous_len") != null else 5.0)])
	var _bushes: Array = []
	for bsh in get_tree().get_nodes_in_group("bush"):
		if is_instance_valid(bsh):
			_bushes.append([bsh.global_position.x, bsh.global_position.z])
	_hud_static = {"walls": _walls, "bushes": _bushes}
	# 回放自己的相机
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 70.0
	_cam.near = 0.05
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	_update_camera()


func _billboard_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	return m


func _make_bar(parent: Node3D, width: float, y: float) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, 0.16)
	bg.mesh = q
	bg.material_override = _billboard_mat(Color(0.05, 0.06, 0.08, 0.85))
	bg.position = Vector3(0, y, 0)
	parent.add_child(bg)
	var fill := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(width, 0.13)
	fill.mesh = q2
	fill.material_override = _billboard_mat(Color(0.45, 1.0, 0.55, 0.95))
	fill.position = Vector3(0, y, 0.01)
	fill.set_meta("w", width)
	parent.add_child(fill)
	return fill


func _build_actors() -> void:
	# 英雄
	for i in range(_heroes.size()):
		var h: Dictionary = _heroes[i]
		var root := Node3D.new()
		root.name = "H%d" % i
		add_child(root)
		var col: Color = TEAM_COL[0] if int(h.get("team", 0)) == int(Config.player_team) else TEAM_COL[1]
		var model: Node3D = NetModels.hero(str(h.get("name", "")), float(h.get("ar", -1.0)))
		var body: MeshInstance3D = null
		if model != null:
			root.add_child(model)
		else:
			# 兜底：没有同源模型的英雄用胶囊占位
			body = MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.52
			cap.height = 1.85
			body.mesh = cap
			body.position.y = 0.92
			var bm := StandardMaterial3D.new()
			bm.albedo_color = col
			bm.emission_enabled = true
			bm.emission = col.darkened(0.6)
			bm.emission_energy_multiplier = 0.4
			bm.roughness = 0.45
			body.material_override = bm
			root.add_child(body)
		# 红/蓝 buff 地面光环（与单机 Hero.buff_ring_red/blue、联机 NetClientBattle 同款）
		var _br := MeshFactory.create_buff_aura(0)
		_br.position = Vector3(0.0, Config.GROUND_FX_Y, 0.0)
		_br.visible = false
		root.add_child(_br)
		var _bb := MeshFactory.create_buff_aura(1)
		_bb.position = Vector3(0.0, Config.GROUND_FX_Y + 0.01, 0.0)
		_bb.visible = false
		root.add_child(_bb)
		var ap := _find_ap(root)
		_setup_idle_walk(ap)
		var _hname := str(h.get("name", ""))
		var idle_c := AnimMap.clip(ap, "idle", _hname)
		var walk_c := AnimMap.clip(ap, "walk", _hname)
		var atk_c := AnimMap.clip(ap, "attack", _hname)
		var atk_shoot := AnimMap.clip(ap, "attack_shoot", _hname)
		var atk_l := AnimMap.clip(ap, "attack_melee_left", _hname)
		var atk_r := AnimMap.clip(ap, "attack_melee_right", _hname)
		var _ar := float(h.get("ar", -1.0))
		if _ar < 0.0:
			# 旧录像没有 ar 字段：按职业回退（射手/法师远程，其余近战）
			var _role := str(h.get("role", ""))
			_ar = 4.5 if _role in ["射手", "法师"] else 1.5
		if idle_c != "":
			ap.play(idle_c)
		# 名字/血条交给真实战场的 HeroInfoControl（下一段 _build_hud 创建），这里只留模型
		_hero_nodes.append({"root": root, "ap": ap, "idle": idle_c, "walk": walk_c, "attack": atk_c,
			"atk_shoot": atk_shoot, "atk_l": atk_l, "atk_r": atk_r, "ar": _ar, "melee_flip": false,
			"last": Vector3.ZERO, "anim": "idle", "atk_until": -1.0,
			"buff_red": _br, "buff_blue": _bb})
	# 防御塔 / 水晶
	for i in range(_turrets.size()):
		var t: Dictionary = _turrets[i]
		var root := Node3D.new()
		root.name = "T%d" % i
		var tp := Vector3(float(t.get("x", 0)) / 100.0, 0.0, float(t.get("z", 0)) / 100.0)
		root.position = tp
		add_child(root)
		# 塔基青白砖环（与单机/联机同一份 DecorMesh.turret_ring_pave；塔毁后砖仍在地面）
		var _ttype := str(t.get("type", "outer"))
		var _inner := 1.45 if _ttype == "crystal" else 1.15
		var _outer := 5.8 if _ttype == "crystal" else 4.7
		var _hq := Vector3(-60.0, 0.0, 60.0) if int(t.get("team", 0)) == 0 else Vector3(60.0, 0.0, -60.0)
		var _on_high: bool = Vector2(tp.x - _hq.x, tp.z - _hq.z).length() < 35.0
		var _top_y: float = 0.177 if _on_high else 0.152
		var _pave := DecorMesh.turret_ring_pave(tp, _inner, _outer, _top_y)
		_pave.name = "TurretRingPave_%d" % i
		add_child(_pave)
		var is_crystal: bool = str(t.get("type", "")) == "crystal"
		var col: Color = TEAM_COL[0] if int(t.get("team", 0)) == int(Config.player_team) else TEAM_COL[1]
		var tmodel: Node3D = NetModels.turret(str(t.get("type", "outer")), int(t.get("team", 0)))
		if tmodel != null:
			root.add_child(tmodel)
		else:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.35 if is_crystal else 0.85
			cm.bottom_radius = 1.75 if is_crystal else 1.05
			cm.height = 4.6 if is_crystal else 3.4
			cm.radial_segments = 8
			mi.mesh = cm
			mi.position.y = cm.height * 0.5
			var m := StandardMaterial3D.new()
			m.albedo_color = col.darkened(0.25)
			m.emission_enabled = true
			m.emission = col.darkened(0.7)
			m.emission_energy_multiplier = 0.5
			m.roughness = 0.6
			mi.material_override = m
			root.add_child(mi)
		var _bt := int(t.get("team", 0))
		# 固定按防御塔阵营取色：蓝方塔=蓝、红方塔=红（三端统一，不随回放视角反转）
		var lbeam: Node3D = Vfx.make_lock_beam(Vfx.team_color(_bt))
		root.add_child(lbeam)   # 与主机同层级：挂塔根节点，塔隐藏/坍塌时光束一同消失
		lbeam.visible = false
		_turret_nodes.append({"root": root, "max": float(t.get("maxhp", 1)), "beam": lbeam,
			"shield": null, "shield_t0": 0.0})
	_build_jungle()


func _build_jungle() -> void:
	for i in range(_jungle_meta.size()):
		var jm: Dictionary = _jungle_meta[i]
		var root := Node3D.new()
		root.name = "J%d" % i
		root.position = Vector3(float(jm.get("x", 0)) / 100.0, 0.0, float(jm.get("z", 0)) / 100.0)
		root.rotation.y = randf() * TAU
		add_child(root)
		var model: Node3D = NetModels.jungle(str(jm.get("name", "")))
		if model != null:
			root.add_child(model)
		var jap := _find_ap(root)
		_setup_idle_walk(jap)
		var jidle := _clip_hint(jap, ["idle"])
		if jidle != "":
			jap.play(jidle)
		_jungle_nodes.append({"root": root, "max": maxf(1.0, float(jm.get("maxhp", 1))),
			"ap": jap, "idle": jidle, "dying": false})


## 真实战场的血条层：英雄用 HeroInfoControl（血/蓝/等级/经验/名字），其他单位交给 WorldBarPainter
func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 121
	add_child(_hud_layer)
	_hud_root = Control.new()
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_hud_root)
	_bars = WorldBarPainterScript.new()
	_hud_root.add_child(_bars)
	for i in range(_heroes.size()):
		var h: Dictionary = _heroes[i]
		var fake := Hero.new()
		fake.display_name = str(h.get("name", ""))
		fake.team = int(h.get("team", 0))
		fake.is_ai = bool(h.get("ai", true))
		fake.player_name = str(h.get("nick", ""))
		fake.level = 1
		fake.max_health = 1000.0
		fake.health = 1000.0
		fake.max_mana = 1000.0
		fake.mana = 1000.0
		fake.actual_max_health = 1000.0
		fake.actual_mana_max = 1000.0
		fake.exp = 0
		fake.exp_to_next = 200
		var info = HeroInfoControlScript.new()
		info.hero = fake
		info.visible = false
		_hud_root.add_child(info)
		_hero_uis.append({"info": info, "fake": fake})
	_hud2 = ReplayHudScript.new()
	_hud_root.add_child(_hud2)
	# 回放 BUFF 图标行：复用联机客户端同一份 NetBuffRow（数据来自录制 buff_frames）
	var bcl := CanvasLayer.new()
	bcl.layer = UiKit.LAYER_HUD + 40
	add_child(bcl)
	_buff_view = NetBuffRowScript.new()
	bcl.add_child(_buff_view)
	_buff_view.refresh({})
	# —— 主视角操作键（与单机完全同布局的 NetTouchPad，回放只显示不响应）——
	var pcl := CanvasLayer.new()
	pcl.layer = 100
	add_child(pcl)
	_pad = NetTouchPadScript.new()
	pcl.add_child(_pad)
	_pad.touch_active = false
	_pad.visible = false
	# —— 目标单位信息框（复用联机同款 NetTargetPanel）——
	var tcl := CanvasLayer.new()
	tcl.layer = 122
	add_child(tcl)
	_tgt_panel = NetTargetPanelScript.new()
	tcl.add_child(_tgt_panel)
	# —— 金币/推荐装购买卡片（复用联机同款 NetRecommendBar）——
	var rcl := CanvasLayer.new()
	rcl.layer = 65
	add_child(rcl)
	_rec_bar = NetRecommendBarScript.new()
	rcl.add_child(_rec_bar)
	_rec_bar.visible = false
	# —— 击杀战报（复用联机同款 NetKillFeed：头像/印记/助攻行）——
	var kcl := CanvasLayer.new()
	kcl.layer = 125   # 播报压在 ReplayHud(121，含英雄头像栏/战况带)之上，回放控制 UI(140)之下
	add_child(kcl)
	_kfeed = NetKillFeedScript.new()
	kcl.add_child(_kfeed)
	# —— 回城指示：与单机一致，由 HeroInfoControl 的状态进度条（回城）显示，不再自建圆形进度 ——
	# —— T 团队决策面板（共享 TeamDecisionView）——
	_tdv_layer = CanvasLayer.new()
	_tdv_layer.layer = 101
	add_child(_tdv_layer)
	_tdv = TeamDecisionViewScript.new()
	_tdv_layer.add_child(_tdv)


func _make_replay_health_pack(wx: float, wz: float, team: int):
	var key := "%d_%d" % [int(round(wx * 10.0)), int(round(wz * 10.0))]
	var hp = _health_packs.get(key, null)
	if hp != null and is_instance_valid(hp):
		return hp
	hp = HealthPack.new()
	hp.visual_only = true
	hp.team = team
	hp.position = Vector3(wx, 0.3, wz)
	add_child(hp)
	_health_packs[key] = hp
	return hp


func _find_health_frame(t: float) -> int:
	if _health_frames.is_empty():
		return -1
	var lo := 0
	var hi := _health_frames.size() - 1
	var ans := 0
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(_health_frames[mid].get("t", 0)) / 1000.0 <= t:
			ans = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return ans


func _apply_replay_health_packs(t: float) -> void:
	if _health_frames.is_empty():
		return
	var fi := _find_health_frame(t)
	var rows: Array = _health_frames[fi].get("h", []) if fi >= 0 else []
	var seen := {}
	_health_rows.clear()
	for row in rows:
		if not (row is Array) or (row as Array).size() < 4:
			continue
		var wx := float(row[0]) / 100.0
		var wz := float(row[1]) / 100.0
		var team := int(row[2])
		var avail := int(row[3]) == 1
		var hp = _make_replay_health_pack(wx, wz, team)
		hp.visible = true
		hp.apply_remote_state(avail,
			float(row[4]) / 10.0 if row.size() > 4 else 0.0,
			float(row[5]) / 10.0 if row.size() > 5 else 75.0)
		var key := "%d_%d" % [int(round(wx * 10.0)), int(round(wz * 10.0))]
		seen[key] = true
		_health_rows.append([wx, wz, team, 1 if avail else 0])
	# 状态帧里消失的血包 = 被塔毁等永久移除
	for key in _health_packs:
		if not seen.has(key):
			var hp2 = _health_packs[key]
			if hp2 != null and is_instance_valid(hp2):
				hp2.visible = false


func _update_world_hud(t: float) -> void:
	var _hud_fi: int = _find_frame(t)
	if _cam == null or _bars == null:
		return
	var vp := get_viewport().get_visible_rect().size
	# —— 英雄：真实 HeroInfoControl ——
	for i in range(_hero_uis.size()):
		var ui: Dictionary = _hero_uis[i]
		var info: Control = ui["info"]
		var fake: Hero = ui["fake"]
		if i >= _hero_state.size() or _hero_state[i].is_empty():
			info.visible = false
			continue
		var st: Dictionary = _hero_state[i]
		if not bool(st.get("alive", false)) or bool(st.get("invis", false)):
			info.visible = false
			continue
		fake.health = clampf(float(st.get("hp", 0)), 0.0, maxf(1.0, float(st.get("mx", 1))))
		# 闪橙只按录像采样帧的伤害触发；压住 HeroInfoControl 对“插值血量每帧微降”的连续触发
		info.set("previous_health", fake.health)
		var _hf: Array = _frame_flash("h%d" % i, _hud_fi, fake.health, maxf(0.001, get_process_delta_time()))
		if _hf[0] > 0.0:
			info.set("damage_flash_amount", _hf[1])
			info.set("damage_flash_timer", _hf[0])
		fake.max_health = maxf(1.0, float(st.get("mx", 1)))
		fake.level = int(st.get("lvl", 1))
		fake.actual_max_health = maxf(1.0, float(st.get("mx", 1)))
		fake.mana = float(st.get("mana", 0))
		fake.max_mana = maxf(1.0, float(st.get("max_mana", 1)))
		fake.actual_mana_max = maxf(1.0, float(st.get("max_mana", 1)))
		fake.shield_remaining = float(st.get("shield", 0.0))
		fake.stun_timer = float(st.get("stun", 0.0))
		fake.knockup_timer = float(st.get("knock", 0.0))
		fake.froze_timer = float(st.get("froze", 0.0))
		fake.suppress_timer = float(st.get("suppress", 0.0))
		fake.silence_timer = float(st.get("silence", 0.0))
		fake.slow_timer = float(st.get("slow", 0.0))
		fake.slow_amount = float(st.get("slow_amt", 0.0))
		fake.bt_timer = float(st.get("bt", 0.0))
		fake.wd_timer = float(st.get("wd", 0.0))
		fake.revive_timer = float(st.get("revive", 0.0))
		# 回城/传送：与单机 HeroInfoControl.status_entries_of 同源，画出「回城」进度条
		fake.recall_timer = float(st.get("recall", 0.0))
		fake.is_recalling = int(st.get("is_recall", 0)) == 1 or fake.recall_timer > 0.0
		fake.teleport_timer = float(st.get("tp", 0.0))
		fake.is_teleporting = int(st.get("is_tp", 0)) == 1 or fake.teleport_timer > 0.0
		fake.is_mvp = int(st.get("mvp", 0)) == 1
		# 被动条/附魔/层数等：优先用录像里录下的状态条（与单机 status_entries_of 同源）
		info.external_statuses = _decode_statuses(st.get("st", []))
		_apply_markers(fake, str(st.get("markers", "")))
		fake.exp = int(float(st.get("exp", 0)))
		fake.exp_to_next = int(maxf(1.0, float(st.get("exp_to_next", 200))))
		var wp: Vector3 = (st.get("pos", Vector3.ZERO) as Vector3) + Vector3.UP * 4.2   # 与单机 HeroInfoControl 血条锚点一致
		if _cam.is_position_behind(wp):
			info.visible = false
			continue
		var sp: Vector2 = _cam.unproject_position(wp)
		if sp.x < -400.0 or sp.x > vp.x + 400.0 or sp.y < -200.0 or sp.y > vp.y + 200.0:
			info.visible = false
			continue
		info.visible = true
		info.position = sp - info.custom_minimum_size * 0.5
		info.queue_redraw()
	# —— 塔 / 小兵 / 野怪：真实 WorldBarPainter ——
	var rows: Array = []
	for u in _unit_world:
		var hp: float = float(u.get("hp", 0.0))
		if hp <= 0.0:
			continue
		var mx: float = maxf(1.0, float(u.get("max", 1.0)))
		var pos: Vector3 = u.get("pos", Vector3.ZERO)
		var kind := str(u.get("kind", ""))
		var sub := str(u.get("sub", ""))
		var anchor := 1.35
		var w := 110.0
		var hh := 15.0
		var epic := false
		var ticks := false
		var step := 1000.0
		var is_turret := false
		if kind == "turret":
			# 与单机 HUD._update_unit_row 同锚点：Turret body_radius=1.5 → 1.5*2+1 = 4.0
			anchor = 4.0
			w = 300.0
			hh = 22.0
			ticks = true
			step = 2000.0
			is_turret = true
		elif kind == "minion":
			anchor = 2.0 if sub in ["super", "dragon", "storm", "shadow_dragon"] else 1.45
			ticks = sub in ["dragon", "storm", "shadow_dragon"]
		else:
			var is_epic: bool = sub in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]
			if is_epic:
				var segs: int = maxi(1, int(ceil(mx / 1000.0)))
				w = clampf(float(segs) * 22.0, 380.0, 880.0)
				hh = 30.0
				epic = true
				anchor = 4.8
			else:
				anchor = 2.8
				ticks = true
		var wp2: Vector3 = pos + Vector3.UP * anchor
		if _cam.is_position_behind(wp2):
			continue
		var sp2: Vector2 = _cam.unproject_position(wp2)
		if sp2.x < -500.0 or sp2.x > vp.x + 500.0 or sp2.y < -300.0 or sp2.y > vp.y + 300.0:
			continue
		var team_v: int = int(u.get("team", 0))
		var team_col: Color = Color(0.0, 0.886, 1.0, 1.0) if Config.is_ally(team_v) else Color(1.0, 0.33, 0.264, 1.0)
		if team_v == 2:
			team_col = Color(0.0, 0.886, 0.431, 1.0)
		# 残血拖尾（同单机 HUD：hp 下降后 lag 以 7×delta 追平）
		var _uk := str(u.get("kind", "")) + "_" + str(int(pos.x * 10.0)) + "_" + str(int(pos.z * 10.0))
		var _lag_prev: float = float(_lag_cache.get(_uk, hp))
		var _lag: float = hp if _lag_prev <= hp else lerpf(_lag_prev, hp, clampf(get_process_delta_time() * 7.0, 0.0, 1.0))
		if _lag - hp < 1.0:
			_lag = hp
		_lag_cache[_uk] = _lag
		var _fl: Array = [float(u.get("flash_t", 0.0)), float(u.get("flash_amt", 0.0))]
		rows.append({
			"hp": hp, "max_hp": mx, "team": team_v, "team_color": team_col,
			"pos": sp2 - Vector2(w, hh) * 0.5, "w": w, "h": hh,
			"epic": epic, "ticks": ticks, "tick_step": step,
			"name_text": sub, "show_name": false,   # 野怪血条不显示名字
			"turret": is_turret, "turret_arrow": is_turret,
			"shield": float(u.get("shield", 0.0)), "shield_icon": bool(u.get("shield_icon", false)),
			"interfere": 0.0, "doom": 0.0, "lag": _lag,
			"flash_t": _fl[0], "flash_amt": _fl[1], "heal_t": 0.0, "heal_amt": 0.0,
			"marker_list": [], "last_hit": _replay_last_hit(team_v, hp, float(u.get("armor", 0.0))),
			"show_numbers": false, "num_text": "",
		})
	_bars.rows = rows
	# —— 回放 HUD（小地图/英雄面板/对战信息/主视角技能） ——
	if _hud2 != null:
		var meta_d: Dictionary = _doc.get("meta", {})
		var me: int = int(meta_d.get("me", 0))
		var heroes_st: Array = []
		for i in range(_heroes.size()):
			var meta: Dictionary = _heroes[i]
			var st2: Dictionary = _hero_state[i] if i < _hero_state.size() and not (_hero_state[i] as Dictionary).is_empty() else {}
			var sd: Array = meta.get("sd", [])
			var pos3: Vector3 = st2.get("pos", Vector3.ZERO)
			heroes_st.append({
				"name": str(meta.get("name", "")), "team": int(meta.get("team", 0)),
				"nick": str(meta.get("nick", "")), "ai": bool(meta.get("ai", true)),
				"lvl": int(st2.get("lvl", 1)), "hp": float(st2.get("hp", 0)), "mx": maxf(1.0, float(st2.get("mx", 1))),
				"mana": float(st2.get("mana", 0)), "mmax": maxf(1.0, float(st2.get("max_mana", 1))),
				"k": int(st2.get("k", 0)), "d": int(st2.get("d", 0)), "a": int(st2.get("a", 0)),
				"ad": int(st2.get("ad", 0)), "ap": int(st2.get("ap", 0)),
				"armor": int(st2.get("armor", 0)), "mr": int(st2.get("mr", 0)),
				"ms": int(st2.get("ms", 0)), "as": int(st2.get("as", 0)),
				"cds": st2.get("cds", []), "cd_total": sd, "slevels": st2.get("slevels", []),
				"alive": 1 if bool(st2.get("alive", false)) else 0,
				"invis": 1 if bool(st2.get("invis", false)) else 0,
				"wx": pos3.x, "wz": pos3.z, "is_me": 1 if i == me else 0,
			})
		var tur_st: Array = _hud_turrets.duplicate()
		var jung_st: Array = []
		for i in range(_jungle_nodes.size()):
			var jn: Dictionary = _jungle_nodes[i]
			var jroot: Node3D = jn["root"]
			var jk := ""
			if i < _jungle_meta.size():
				jk = str((_jungle_meta[i] as Dictionary).get("name", ""))
			jung_st.append({"wx": jroot.position.x, "wz": jroot.position.z, "kind": jk,
				"alive": 1 if jroot.visible else 0})
		var pings_st: Array = []
		for pg in _mm_pings:
			var age_p: float = _t - float(pg.get("t0", 0))
			if age_p <= 2.0:
				pings_st.append({"wx": float(pg.get("wx", 0)), "wz": float(pg.get("wz", 0)), "age": age_p})
		var marks_st: Array = []
		for mk in _mm_marks:
			var age_m: float = _t - float(mk.get("t0", 0))
			if age_m <= 2.5:
				marks_st.append({"wx": float(mk.get("wx", 0)), "wz": float(mk.get("wz", 0)),
					"team": int(mk.get("team", 0)), "age": age_m, "kind": int(mk.get("kind", 0))})
		var camps_st: Array = []
		for jn2 in _jungle_nodes:
			var jroot2: Node3D = jn2["root"]
			if float(jn2.get("dead_t", -1.0)) >= 0.0 and float(jn2.get("last_seen", -1.0)) >= 0.0:
				var rt: float = 75.0
				var jidx2: int = _jungle_nodes.find(jn2)
				if jidx2 >= 0 and jidx2 < _jungle_meta.size():
					rt = float((_jungle_meta[jidx2] as Dictionary).get("rt", 75.0))
				var left: float = rt - (_t - float(jn2.get("dead_t", 0.0)))
				if left > 0.0:
					camps_st.append({"wx": jroot2.position.x, "wz": jroot2.position.z,
						"kind": str((_jungle_meta[jidx2] as Dictionary).get("name", "")) if jidx2 >= 0 and jidx2 < _jungle_meta.size() else "",
						"left": left})
		var feed_st: Array = []
		var keep_feed: Array = []
		for fd in _feed_items:
			var age_f: float = _t - float(fd.get("t0", 0))
			if age_f <= 6.0:
				feed_st.append({"a": fd.get("a", ""), "at": fd.get("at", 0), "d": fd.get("d", ""),
					"v": fd.get("v", ""), "vt": fd.get("vt", -1), "age": age_f})
				keep_feed.append(fd)
		_feed_items = keep_feed
		var obj_st: Array = []
		if _frame_obj.size() >= 4:
			obj_st.append({"label": "暴君", "t": float(_frame_obj[0]), "alive": int(_frame_obj[1]) == 1,
				"color": Color(0.85, 0.6, 0.35)})
			obj_st.append({"label": "主宰", "t": float(_frame_obj[2]), "alive": int(_frame_obj[3]) == 1,
				"color": Color(0.65, 0.55, 0.95)})
		var hero_nm := ""
		if me >= 0 and me < _heroes.size():
			hero_nm = str((_heroes[me] as Dictionary).get("name", ""))
		_hud2.st = {
			"t": float(_t), "heroes": heroes_st, "turrets": tur_st, "gold": _frame_gold,
			"follow": _follow_hero, "mode": str(meta_d.get("mode", "")), "hero": hero_nm,
			"walls": _hud_static.get("walls", []), "bushes": _hud_static.get("bushes", []),
			"jungle": jung_st, "minions": _hud_minions, "cam": _cam,
			"health_packs": _health_rows, "health_data": not _health_frames.is_empty(),
			"pings": pings_st, "marks": marks_st, "camps": camps_st,
			"me_team": int(meta_d.get("player_team", 0)),
			"feed": feed_st, "objectives": obj_st,
			"sa": _detail_for(_follow_hero).get("sa", []),
		}
		_hud2.queue_redraw()
		_last_hero_rows = heroes_st
		_update_buff_row()
		_update_replay_controls()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 140
	add_child(layer)
	_ui_layer = layer
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 顶部中央：标题 + 快捷键提示（战报/战况带/头像行均在 HUD 层）
	_title = Label.new()
	_title.anchor_left = 0.5
	_title.anchor_right = 0.5
	_title.offset_left = -620.0
	_title.offset_right = 620.0
	_title.offset_top = 8.0
	_title.offset_bottom = 42.0
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", int(round(22.0 * UiKit.scale())))
	_title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	root.add_child(_title)
	var meta: Dictionary = _doc.get("meta", {})
	var me: int = int(meta.get("me", 0))
	var my: Dictionary = _heroes[me] if me >= 0 and me < _heroes.size() else {}
	var win: int = int(meta.get("winner", -1))
	var res: String = ("胜利" if win == int(Config.player_team) else "失败") if win >= 0 else "录像"
	_title.text = "%s · %s · %s" % [str(my.get("name", "")), str(meta.get("mode", "")), res]

	# 底部：回放进度条 + 回放相关按钮（回放专属，单机没有）
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.add_theme_stylebox_override("panel",
		UiKit.flat(0.9, 14, 1, Color(0.45, 0.62, 1.0, 0.35), Color(0.05, 0.07, 0.11, 0.94), 14.0, 12.0))
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 0.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 24.0 + UiKit.safe_left()
	bar.offset_right = bar.offset_left + 1500.0
	bar.offset_top = -104.0 - UiKit.safe_bottom()
	bar.offset_bottom = -16.0 - UiKit.safe_bottom()
	root.add_child(bar)

	_slider = HSlider.new()
	_slider.position = Vector2(20.0, 14.0)
	_slider.size = Vector2(720.0, 24.0)
	_slider.min_value = 0.0
	_slider.max_value = _duration
	_slider.step = 0.05
	_slider.value = 0.0
	_slider.value_changed.connect(func(v: float) -> void:
		if _dragging or not _playing:
			_t = clampf(float(v), 0.0, _duration)
			_sync_highlight_seek()
			_apply_frame(_t))
	_slider.drag_started.connect(func() -> void: _dragging = true)
	_slider.drag_ended.connect(func(_v: bool) -> void: _dragging = false)
	bar.add_child(_slider)

	_ui_time = Label.new()
	_ui_time.position = Vector2(752.0, 10.0)
	_ui_time.size = Vector2(120.0, 30.0)
	_ui_time.add_theme_font_size_override("font_size", int(round(20.0 * UiKit.scale())))
	_ui_time.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	bar.add_child(_ui_time)

	_play_btn = _mk_btn("⏸ 暂停", Color(0.45, 0.7, 1.0))
	_play_btn.position = Vector2(886.0, 8.0)
	_play_btn.custom_minimum_size = Vector2(140.0, 40.0)
	_play_btn.pressed.connect(_toggle_play)
	bar.add_child(_play_btn)
	_speed_btn = _mk_btn("1.0×", Color(0.55, 0.85, 0.75))
	_speed_btn.position = Vector2(1036.0, 8.0)
	_speed_btn.custom_minimum_size = Vector2(140.0, 40.0)
	_speed_btn.pressed.connect(_cycle_speed)
	bar.add_child(_speed_btn)
	_hl_btn = _mk_btn("◆ 集锦", Color(1.0, 0.78, 0.4))
	_hl_btn.position = Vector2(1186.0, 8.0)
	_hl_btn.custom_minimum_size = Vector2(140.0, 40.0)
	_hl_btn.pressed.connect(_toggle_highlight)
	bar.add_child(_hl_btn)
	var quit := _mk_btn("✕ 退出", Color(0.9, 0.55, 0.45))
	quit.position = Vector2(1336.0, 8.0)
	quit.custom_minimum_size = Vector2(140.0, 40.0)
	quit.pressed.connect(_back_to_lobby)
	bar.add_child(quit)

	var hint := Label.new()
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.offset_left = -400.0
	hint.offset_right = 400.0
	hint.offset_top = 74.0
	hint.offset_bottom = 122.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	hint.add_theme_font_size_override("font_size", int(round(15.0 * UiKit.scale())))
	hint.add_theme_color_override("font_color", Color(0.62, 0.7, 0.82))
	_hint_label = hint
	hint.text = HINT_TEXT
	root.add_child(hint)
	# 聊天/语音（与单机同款 ChatBox；回放消息由录像 chat 事件推送）
	var ccl := CanvasLayer.new()
	ccl.layer = 45
	add_child(ccl)
	_chat_box = ChatBoxScript.new()
	ccl.add_child(_chat_box)


func _mk_btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(124, 40)
	b.add_theme_font_size_override("font_size", int(round(24.0 * UiKit.scale())))
	b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	b.add_theme_stylebox_override("normal", UiKit.skin_button("normal", accent, false))
	b.add_theme_stylebox_override("hover", UiKit.skin_button("hover", accent, false))
	b.add_theme_stylebox_override("pressed", UiKit.skin_button("pressed", accent, false))
	b.focus_mode = Control.FOCUS_NONE
	return b


# ---------------- 播放 ----------------

func _process(delta: float) -> void:
	if _playing and not _dragging:
		_t += delta * _speed
	if _t >= _duration:
		_t = _duration
		_playing = false
	if not _end_started and _t >= _duration - 0.05:
		_begin_end_sequence()
	if _end_started:
		return
		_play_btn.text = "▶ 播放"
	# 集锦模式：播完当前击杀的前后 3 秒就跳到下一个击杀
	if _highlight and _t >= _hl_end:
		_hl_idx += 1
		if _hl_idx < _kill_times.size():
			_jump_to_highlight(_hl_idx)
			_playing = true
			_play_btn.text = "⏸ 暂停"
		else:
			_highlight = false
			_hl_btn.text = "◆ 集锦"
			_playing = false
			_play_btn.text = "▶ 播放"
			_hint_label.text = "集锦播放完毕（点 ◆ 集锦 重看，或拖时间轴回到完整回放）"
			_t = _duration
	_apply_frame(_t)
	_auto_spectate()
	_update_popups(delta)
	_update_toasts()
	_update_postfx(delta)
	_update_ui()
	_update_camera()


func _apply_frame(t: float) -> void:
	_apply_replay_health_packs(t)
	_unit_world.clear()
	_hud_turrets.clear()
	_hud_minions.clear()
	# 英雄插值
	var fi := _find_frame(t)
	var fa: Dictionary = _frames[fi] if fi >= 0 and fi < _frames.size() else {}
	var _g: Array = fa.get("g", [])
	_frame_gold = [int(_g[0]) if _g.size() > 0 else 0, int(_g[1]) if _g.size() > 1 else 0]
	_frame_obj = fa.get("obj", [])
	var fb: Dictionary = _frames[mini(fi + 1, _frames.size() - 1)] if not _frames.is_empty() else {}
	var ta: float = float(fa.get("t", 0)) / 1000.0
	var tb: float = float(fb.get("t", 0)) / 1000.0
	var k: float = 0.0 if tb - ta <= 0.0001 else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	var ha: Array = fa.get("h", [])
	var hb: Array = fb.get("h", [])
	for i in range(_hero_nodes.size()):
		var node: Dictionary = _hero_nodes[i]
		var row_a: Array = ha[i] if i < ha.size() else []
		var row_b: Array = hb[i] if i < hb.size() else row_a
		if row_a.is_empty():
			node["root"].visible = false
			continue
		var x: float = lerpf(float(row_a[0]), float(row_b[0] if row_b.size() > 0 else row_a[0]), k) / 100.0
		var z: float = lerpf(float(row_a[1]), float(row_b[1] if row_b.size() > 1 else row_a[1]), k) / 100.0
		var hp: float = lerpf(float(row_a[4]), float(row_b[4] if row_b.size() > 4 else row_a[4]), k)
		var mx: float = maxf(1.0, float(row_a[5] if row_a.size() > 5 else 1))
		var flags_a: int = int(row_a[7]) if row_a.size() > 7 else 0
		var flags_b: int = int(row_b[7]) if row_b.size() > 7 else flags_a
		var alive: bool = (flags_a & 1) != 0 or (flags_b & 1) != 0
		if not alive:
			# 阵亡：播死亡剪辑（没有就程序化倒地），1.1s 后隐藏
			if not bool(node.get("dying", false)):
				node["dying"] = true
				node["dead_at"] = _t
				var dap: AnimationPlayer = node.get("ap")
				var dclip := AnimMap.clip(dap, "die", str((_heroes[i] as Dictionary).get("name", "")))
				if dap != null and dclip != "":
					dap.play(dclip)
			var dage: float = _t - float(node.get("dead_at", _t))
			node["root"].rotation.x = minf(PI * 0.5, dage * 6.0)
			node["root"].position.y = -minf(0.5, dage * 1.2)
			if dage > 1.1:
				node["root"].visible = false
			# 阵亡也要更新状态（复活倒计时/观战/名册都需要）
			while _hero_state.size() <= i:
				_hero_state.append({})
			_hero_state[i] = {
				"hp": 0.0, "mx": maxf(1.0, float(row_a[5] if row_a.size() > 5 else 1)),
				"lvl": int(row_a[6]) if row_a.size() > 6 else 1,
				"mana": 0.0, "max_mana": 1.0, "exp": 0.0, "exp_to_next": 1.0,
				"k": int(row_a[12]) if row_a.size() > 12 else 0,
				"d": int(row_a[13]) if row_a.size() > 13 else 0,
				"a": int(row_a[14]) if row_a.size() > 14 else 0,
				"ad": 0, "ap": 0, "armor": 0, "mr": 0, "ms": 0, "as": 0,
				"cds": [], "slevels": [], "yaw": float(row_a[3]) if row_a.size() > 3 else 0.0,
				"shield": 0.0, "stun": 0.0, "knock": 0.0, "froze": 0.0, "suppress": 0.0,
				"silence": 0.0, "slow": 0.0, "slow_amt": 0.0, "bt": 0.0, "wd": 0.0,
				"revive": float(row_a[40]) / 100.0 if row_a.size() > 40 else 0.0,
				"markers": "", "mvp": int(row_a[42]) if row_a.size() > 42 else 0,
				"pos": Vector3(x, 0.0, z), "alive": false, "invis": true,
			}
			continue
		if bool(node.get("dying", false)):
			node["dying"] = false
			node["root"].rotation.x = 0.0
			node["root"].position.y = 0.0
			var iap: AnimationPlayer = node.get("ap")
			var iclip := str(node.get("idle", ""))
			if iap != null and iclip != "":
				iap.play(iclip)
		node["root"].visible = true
		var prev: Vector3 = node.get("last", Vector3.ZERO)
		var _fy: float = float(row_a[2]) / 100.0 if row_a.size() > 2 else 0.0
		node["root"].position = Vector3(x, _fy, z)
		_update_replay_wukong_cloud(i, str((_heroes[i] as Dictionary).get("name", "")), _fy, x, z)
		var moved: bool = prev.distance_to(Vector3(x, 0.0, z)) > 0.02
		node["last"] = Vector3(x, 0.0, z)
		var ap2: AnimationPlayer = node.get("ap")
		var want: String = str(node.get("anim", "idle"))
		var atk_until: float = float(node.get("atk_until", -1.0))
		if atk_until > 0.0 and _t > atk_until and want == "attack":
			node["anim"] = "idle"
			want = "idle"
			var idle_clip2 := str(node.get("idle", ""))
			if ap2 != null and idle_clip2 != "":
				ap2.play(idle_clip2)
		if ap2 != null and want != "attack" and moved != (want == "walk"):
			want = "walk" if moved else "idle"
			var clip := str(node.get(want, ""))
			if clip != "":
				ap2.play(clip)
			node["anim"] = want
		while _hero_pos.size() <= i:
			_hero_pos.append(Vector3.ZERO)
		_hero_pos[i] = Vector3(x, 0.0, z)
		var yaw_a: float = float(row_a[3]) if row_a.size() > 3 else 0.0
		var yaw_b: float = float(row_b[3]) if row_b.size() > 3 else yaw_a
		node["root"].rotation.y = deg_to_rad(lerpf(yaw_a, yaw_b, k))
		var invis: bool = ((flags_a | flags_b) & 2) != 0
		node["root"].visible = not invis
		while _hero_state.size() <= i:
			_hero_state.append({})
		var _cds: Array = []
		for _ci in range(5):
			var _raw = int(row_a[21 + _ci]) if row_a.size() > 21 + _ci else 0
			_cds.append(float(_raw) / 100.0)
		var _lv: Array = []
		for _li in range(4):
			_lv.append(int(row_a[26 + _li]) if row_a.size() > 26 + _li else 0)
		_hero_state[i] = {
			"hp": hp, "mx": mx, "lvl": int(row_a[6]) if row_a.size() > 6 else 1,
			"mana": float(row_a[8]) if row_a.size() > 8 else 0.0,
			"max_mana": float(row_a[9]) if row_a.size() > 9 else 100.0,
			"exp": float(row_a[10]) if row_a.size() > 10 else 0.0,
			"exp_to_next": float(row_a[11]) if row_a.size() > 11 else 200.0,
			"k": int(row_a[12]) if row_a.size() > 12 else 0,
			"d": int(row_a[13]) if row_a.size() > 13 else 0,
			"a": int(row_a[14]) if row_a.size() > 14 else 0,
			"ad": int(row_a[15]) if row_a.size() > 15 else 0,
			"ap": int(row_a[16]) if row_a.size() > 16 else 0,
			"armor": int(row_a[17]) if row_a.size() > 17 else 0,
			"mr": int(row_a[18]) if row_a.size() > 18 else 0,
			"ms": int(row_a[19]) if row_a.size() > 19 else 0,
			"as": int(row_a[20]) if row_a.size() > 20 else 0,
			"cds": _cds, "slevels": _lv, "yaw": float(row_a[3]) if row_a.size() > 3 else 0.0,
			"flat_pen": float(row_a[47]) if row_a.size() > 47 else 0.0,
			"shield": float(row_a[30]) / 10.0 if row_a.size() > 30 else 0.0,
			"stun": float(row_a[31]) / 100.0 if row_a.size() > 31 else 0.0,
			"knock": float(row_a[32]) / 100.0 if row_a.size() > 32 else 0.0,
			"froze": float(row_a[33]) / 100.0 if row_a.size() > 33 else 0.0,
			"suppress": float(row_a[34]) / 100.0 if row_a.size() > 34 else 0.0,
			"silence": float(row_a[35]) / 100.0 if row_a.size() > 35 else 0.0,
			"slow": float(row_a[36]) / 100.0 if row_a.size() > 36 else 0.0,
			"slow_amt": float(row_a[37]) / 100.0 if row_a.size() > 37 else 0.0,
			"bt": float(row_a[38]) / 100.0 if row_a.size() > 38 else 0.0,
			"wd": float(row_a[39]) / 100.0 if row_a.size() > 39 else 0.0,
			"revive": float(row_a[40]) / 100.0 if row_a.size() > 40 else 0.0,
			"markers": str(row_a[41]) if row_a.size() > 41 else "",
			"mvp": int(row_a[42]) if row_a.size() > 42 else 0,
			"recall": float(row_a[43]) / 100.0 if row_a.size() > 43 else 0.0,
			"tp": float(row_a[44]) / 100.0 if row_a.size() > 44 else 0.0,
			"is_recall": int(row_a[45]) if row_a.size() > 45 else 0,
			"is_tp": int(row_a[46]) if row_a.size() > 46 else 0,
			"st": (row_a[48] if row_a.size() > 48 and row_a[48] is Array else []),
			"pos": Vector3(x, 0.0, z), "alive": alive, "invis": invis,
		}
		_update_recall_fx(i, Vector3(x, 0.0, z), alive, _hero_state[i])
	# 塔
	var tna: Array = fa.get("tn", [])
	var tnb: Array = fb.get("tn", [])
	for i in range(_turret_nodes.size()):
		var node2: Dictionary = _turret_nodes[i]
		var ra: Array = tna[i] if i < tna.size() else []
		var rb: Array = tnb[i] if i < tnb.size() else ra
		if ra.is_empty():
			continue
		var hpv: float = lerpf(float(ra[0]), float(rb[0] if rb.size() > 0 else ra[0]), k)
		var lbeam2 = node2.get("beam")
		if lbeam2 != null and is_instance_valid(lbeam2):
			var has_a: int = int(ra[4]) if ra.size() > 4 else 0
			var has_b: int = int(rb[4]) if rb.size() > 4 else 0
			# 与单机一致：当前采样帧没有目标就立即隐藏（不再等下一帧也变 0 才隐藏）
			if hpv > 0.5 and has_a == 1:
				var tx_a: float = float(ra[2]) if ra.size() > 2 else 0.0
				var tz_a: float = float(ra[3]) if ra.size() > 3 else 0.0
				var tx_b: float = float(rb[2]) if rb.size() > 2 else tx_a
				var tz_b: float = float(rb[3]) if rb.size() > 3 else tz_a
				# 目标切换/瞬移时不做跨目标插值（否则光束会扫过一段不存在的轨迹），直接贴当前帧
				var _jump: float = Vector2(tx_b - tx_a, tz_b - tz_a).length() / 100.0
				var _k: float = k if (has_b == 1 and _jump < 6.0) else 0.0
				var tgt_p := Vector3(lerpf(tx_a, tx_b, _k) / 100.0, 1.0, lerpf(tz_a, tz_b, _k) / 100.0)
				var _tier := str((_turrets[i] as Dictionary).get("type", "")) if i < _turrets.size() else "outer"
				var _src_h := 3.30 if _tier == "crystal" else 3.45
				var src_p: Vector3 = (node2["root"] as Node3D).position + Vector3.UP * _src_h
				Vfx.aim_lock_beam(lbeam2, src_p, tgt_p, _t)
			else:
				lbeam2.visible = false
		# —— 塔护盾：录像层记录开关/盾量，实体与单机/联机同款（TurretMesh.tower_shield_visual）——
		var _sh_on: int = int(ra[5]) if ra.size() > 5 else 0
		var _sh_a: float = float(ra[6]) / 10.0 if ra.size() > 6 else 0.0
		var _sh_b: float = float(rb[6]) / 10.0 if rb.size() > 6 else _sh_a
		var _sh_amt: float = lerpf(_sh_a, _sh_b, k)
		var _sh_icon: int = int(ra[7]) if ra.size() > 7 else 0
		var _sh_active: bool = _sh_on == 1 and _sh_amt > 0.0 and hpv > 0.5
		var _shn = node2.get("shield")
		if _sh_active:
			if _shn == null or not is_instance_valid(_shn):
				_shn = NetModels.tower_shield(int((_turrets[i] as Dictionary).get("team", 0)) if i < _turrets.size() else 0,
					str((_turrets[i] as Dictionary).get("type", "")) == "crystal" if i < _turrets.size() else false)
				node2["root"].add_child(_shn)
				node2["shield"] = _shn
				node2["shield_t0"] = _t
			_shn.visible = true
			var _gt: float = _t - float(node2.get("shield_t0", _t))
			var _grow: float = minf(1.0, _gt * 6.0)
			var _pulse: float = 1.0 + sin(_t * 2.4) * 0.012
			var _ss: float = lerpf(0.80, 1.0, _grow) * _pulse
			_shn.scale = Vector3(_ss, _ss, _ss)
			_shn.rotation.y = _t * 0.22
		elif _shn != null and is_instance_valid(_shn):
			_shn.queue_free()
			node2["shield"] = null
		if hpv > 0.5:
			node2["root"].visible = true
		elif not bool(node2.get("collapsed", false)):
			node2["collapsed"] = true
			node2["root"].visible = true
			var is_crys: bool = i < _turrets.size() and str((_turrets[i] as Dictionary).get("type", "")) == "crystal"
			Turret.play_collapse(node2["root"], 1.9 if is_crys else 1.6, get_parent())
		if i < _turrets.size():
			var td0: Dictionary = _turrets[i]
			var prev_hp: float = float(node2.get("prev_hp", hpv))
			if hpv > 0.5 and prev_hp - hpv >= 30.0:
				_mm_pings.append({"wx": float(td0.get("x", 0)) / 100.0, "wz": float(td0.get("z", 0)) / 100.0, "t0": _t})
			node2["prev_hp"] = hpv
			var _uf: Array = _unit_flash("t%d" % i, hpv, maxf(0.001, get_process_delta_time()))
			_hud_turrets.append({"wx": float(td0.get("x", 0)) / 100.0, "wz": float(td0.get("z", 0)) / 100.0,
				"team": int(td0.get("team", 0)), "type": str(td0.get("type", "outer")),
				"alive": 1 if hpv > 0.5 else 0, "hp": hpv, "mx": maxf(1.0, float(node2["max"])),
				"shield": _sh_amt if _sh_active else 0.0, "shield_icon": _sh_icon == 1,
				"flash_t": _uf[0], "flash_amt": _uf[1]})
		if hpv > 0.5 and i < _turrets.size():
			var td: Dictionary = _turrets[i]
			var _uf2: Array = _frame_flash("t%d" % i, fi, float(ra[0]), maxf(0.001, get_process_delta_time()))
			_unit_world.append({"kind": "turret", "pos": Vector3(float(td.get("x", 0)) / 100.0, 0.0, float(td.get("z", 0)) / 100.0),
				"hp": hpv, "max": maxf(1.0, float(node2["max"])), "team": int(td.get("team", 0)),
				"name": str(td.get("type", "")), "sub": str(td.get("type", "")),
				"armor": float(td.get("armor", 0.0)),
				"shield": _sh_amt if _sh_active else 0.0, "shield_icon": _sh_icon == 1,
				"flash_t": _uf2[0], "flash_amt": _uf2[1]})
	# 小兵：相邻两帧按 id 插值（3Hz 采样也能走得顺）
	var mi := _find_mini_frame(t)
	var rows: Array = []      # [id, x, z, type, team]
	if mi >= 0 and mi < _minis.size():
		var ma: Dictionary = _minis[mi]
		var mb: Dictionary = _minis[mini(mi + 1, _minis.size() - 1)]
		var tma: float = float(ma.get("t", 0)) / 1000.0
		var tmb: float = float(mb.get("t", 0)) / 1000.0
		var k2: float = 0.0 if tmb - tma <= 0.0001 else clampf((t - tma) / (tmb - tma), 0.0, 1.0)
		var by_id: Dictionary = {}
		for rb in mb.get("m", []):
			by_id[int(rb[0])] = rb
		for ra in ma.get("m", []):
			var id0: int = int(ra[0])
			var rb2: Array = by_id.get(id0, [])
			var x0: float = lerpf(float(ra[1]), float(rb2[1]) if rb2.size() > 1 else float(ra[1]), k2) / 100.0
			var z0: float = lerpf(float(ra[2]), float(rb2[2]) if rb2.size() > 2 else float(ra[2]), k2) / 100.0
			var hp0: float = lerpf(float(ra[3]), float(rb2[3]) if rb2.size() > 3 else float(ra[3]), k2)
			var _mf: Array = _frame_flash("m%d" % id0, mi, float(ra[3]), maxf(0.001, get_process_delta_time()))
			rows.append([id0, x0, z0, int(ra[5]), int(ra[4]), hp0,
				float(ra[6]) if ra.size() > 6 else 1000.0,
				float(ra[7]) if ra.size() > 7 else 0.0,
				int(ra[8]) if ra.size() > 8 else 0,
				float(ra[9]) if ra.size() > 9 else 0.0,
				_mf[0], _mf[1]])
		var seen := {}
		for r in rows:
			var id: int = int(r[0])
			seen[id] = true
			var node3 = _mini_nodes.get(id)
			if node3 == null:
				node3 = _make_minion(int(r[3]), int(r[4]))
				node3.set_meta("type_name", str(r[3]))
				_mini_nodes[id] = node3
				# 兵线出生光效（与对局兵线刷出时的落地波一致）
				var spawn_p := Vector3(float(r[1]), 0.2, float(r[2]))
				var spawn_col: Color = Color(0.0, 0.886, 1.0) if Config.is_ally(int(r[4])) else Color(1.0, 0.33, 0.264)
				Vfx.shockwave(spawn_p, 1.4, spawn_col, 0.32)
				Vfx.cast_glow(spawn_p + Vector3.UP * 0.4, spawn_col, 0.9, 0.3)
			node3.visible = true
			node3.set_meta("dying", false)
			_hud_minions.append({"wx": float(r[1]), "wz": float(r[2]), "team": int(r[4])})
			_unit_world.append({"kind": "minion", "pos": Vector3(float(r[1]), 0.0, float(r[2])),
				"hp": float(r[5]), "max": maxf(1.0, float(r[6])), "team": int(r[4]),
				"name": str(r[3]), "sub": TYPE_NAMES[clampi(int(r[3]), 0, TYPE_NAMES.size() - 1)],
				"armor": float(r[9]) if r.size() > 9 else 0.0,
				"flash_t": float(r[10]) if r.size() > 10 else 0.0,
				"flash_amt": float(r[11]) if r.size() > 11 else 0.0})
			# 朝向移动方向 + 行走动画（上下踏步 + 左右摆）
			var nowp: Vector3 = Vector3(float(r[1]), 0.0, float(r[2]))
			var prevp: Vector3 = node3.get_meta("prev", nowp)
			var dv: Vector3 = nowp - prevp
			var moving: bool = dv.length() > 0.01
			if moving:
				node3.rotation.y = atan2(dv.x, dv.z)
			node3.set_meta("prev", nowp)
			node3.position = Vector3(nowp.x, 0.0, nowp.z)   # 行走起伏/摆动交给 WalkFeel，与单机同源
			# 攻击序号变化 → 播一次与单机同参数的程序化攻击动作（攻城车后坐/弓兵拉弓/近战前刺）
			var atk_seq := int(r[8]) if r.size() > 8 else 0
			if atk_seq > int(node3.get_meta("atk_seq", 0)):
				node3.set_meta("atk_seq", atk_seq)
				if r.size() > 7:
					node3.rotation.y = float(r[7])
				_play_minion_attack(node3, int(r[3]))
		for id in _mini_nodes.keys():
			if seen.has(id):
				continue
			var nd2: Node3D = _mini_nodes[id]
			if not nd2.visible:
				continue
			if not bool(nd2.get_meta("dying", false)):
				nd2.set_meta("dying", true)
				nd2.set_meta("dead_at", _t)
				nd2.set_meta("sink_base_y", nd2.position.y)
				var walker2 = nd2.get_node_or_null("WalkFeel")
				if walker2:
					walker2.set_process(false)
			var age: float = _t - float(nd2.get_meta("dead_at", _t))
			var mdl2 = nd2.get_meta("model", null)
			var mname := str(nd2.get_meta("type_name", ""))
			var is_drg: bool = mname in ["dragon", "storm", "shadow_dragon"]
			var depth2: float = 2.4 if is_drg else 1.5
			var fall_t: float = 0.7 if is_drg else 0.55
			if mdl2 is Node3D:
				var m3 := mdl2 as Node3D
				if age <= 0.62:
					if is_drg:
						var kd := clampf(age / fall_t, 0.0, 1.0)
						m3.rotation.x = 0.55 * kd
						m3.position.y = -0.55 * kd
					else:
						var dirf := 1.0 if (id % 2 == 0) else -1.0
						var kn := clampf(age / fall_t, 0.0, 1.0)
						m3.rotation.z = dirf * 1.35 * kn
						m3.position.y = -0.12 * kn
				else:
					# 倒地后缓缓沉入地面（同 host _start_sink_away：0.88s Sine EaseIn）
					var ks := clampf((age - 0.62) / 0.88, 0.0, 1.0)
					var es := 1.0 - cos(ks * PI * 0.5)
					nd2.position.y = float(nd2.get_meta("sink_base_y", 0.0)) - depth2 * es
			if age > 1.56:
				nd2.visible = false
	# 野怪 / 史诗龙：位置插值 + 血量归零隐藏（灵魂/被击杀后不再出现）
	var ji := _find_jungle_frame(t)
	if ji >= 0 and ji < _jungle.size():
		var ja: Dictionary = _jungle[ji]
		var jb: Dictionary = _jungle[mini(ji + 1, _jungle.size() - 1)]
		var jta: float = float(ja.get("t", 0)) / 1000.0
		var jtb: float = float(jb.get("t", 0)) / 1000.0
		var jk: float = 0.0 if jtb - jta <= 0.0001 else clampf((t - jta) / (jtb - jta), 0.0, 1.0)
		var jma: Dictionary = {}
		for jr in ja.get("j", []):
			jma[int(jr[0])] = jr
		var jmb: Dictionary = {}
		for jrb in jb.get("j", []):
			jmb[int(jrb[0])] = jrb
		var jseen: Dictionary = {}
		for jid in jma.keys():
			var ji2: int = int(jid)
			if ji2 < 0 or ji2 >= _jungle_nodes.size():
				continue
			jseen[ji2] = true
			var jra: Array = jma[ji2]
			var jrb2: Array = jmb.get(ji2, jra)
			var jhp: float = lerpf(float(jra[3]), float(jrb2[3]) if jrb2.size() > 3 else float(jra[3]), jk)
			var jnode: Dictionary = _jungle_nodes[ji2]
			# 野怪最大生命值逐帧取录像值（史诗阶段会成长；旧录像无 idx4 时回退初始 max）
			var jmax: float = float(jrb2[4]) if jrb2.size() > 4 else (float(jra[4]) if jra.size() > 4 else float(jnode["max"]))
			jnode["max"] = maxf(1.0, jmax)
			var jroot: Node3D = jnode["root"]
			var jap2: AnimationPlayer = jnode.get("ap")
			if jhp > 0.5:
				jnode["last_seen"] = _t
			elif float(jnode.get("last_seen", -1.0)) >= 0.0 and float(jnode.get("dead_t", -1.0)) < 0.0:
				jnode["dead_t"] = _t
			if jhp > 0.5:
				if bool(jnode.get("dying", false)):
					jnode["dying"] = false
					jroot.rotation.x = 0.0
					jroot.position.y = 0.0
					var jic := str(jnode.get("idle", ""))
					if jap2 != null and jic != "":
						jap2.play(jic)
				jroot.visible = true
			else:
				if not bool(jnode.get("dying", false)):
					jnode["dying"] = true
					jnode["dead_at"] = _t
					var jdc := _clip_hint(jap2, ["die", "death"])
					if jap2 != null and jdc != "":
						jap2.play(jdc)
				var jage: float = _t - float(jnode.get("dead_at", _t))
				jroot.rotation.x = minf(PI * 0.5, jage * 6.0)
				jroot.position.y = -minf(0.4, jage * 1.0)
				if jage > 1.0:
					jroot.visible = false
			var _jf: Array = _frame_flash("j%d" % ji2, ji, float(jra[3]), maxf(0.001, get_process_delta_time()))
			if jroot.visible:
				_unit_world.append({"kind": "jungle", "pos": jroot.position,
					"hp": jhp, "max": maxf(1.0, float(jnode["max"])), "team": 2,
					"armor": float(jrb2[5]) if jrb2.size() > 5 else (float(jra[5]) if jra.size() > 5 else 0.0),
					"name": str(_jungle_meta[ji2].get("name", "")) if ji2 < _jungle_meta.size() else "",
					"sub": str(_jungle_meta[ji2].get("name", "")) if ji2 < _jungle_meta.size() else "",
					"flash_t": _jf[0], "flash_amt": _jf[1]})
				jroot.position = Vector3(
					lerpf(float(jra[1]), float(jrb2[1]) if jrb2.size() > 1 else float(jra[1]), jk) / 100.0,
					0.0,
					lerpf(float(jra[2]), float(jrb2[2]) if jrb2.size() > 2 else float(jra[2]), jk) / 100.0)
		# 从帧里消失的野怪 = 被击杀/回城：播放倒地并开始刷新倒计时
		for jidx_u in range(_jungle_nodes.size()):
			if jseen.has(jidx_u):
				continue
			var jn_u: Dictionary = _jungle_nodes[jidx_u]
			var jroot_u: Node3D = jn_u["root"]
			if not jroot_u.visible and float(jn_u.get("last_seen", -1.0)) < 0.0:
				continue
			if float(jn_u.get("last_seen", -1.0)) >= 0.0 and float(jn_u.get("dead_t", -1.0)) < 0.0:
				jn_u["dead_t"] = _t
			if not bool(jn_u.get("dying", false)):
				jn_u["dying"] = true
				jn_u["dead_at"] = _t
				var jap_u: AnimationPlayer = jn_u.get("ap")
				var jdc_u := _clip_hint(jap_u, ["die", "death"])
				if jap_u != null and jdc_u != "":
					jap_u.play(jdc_u)
			var jage_u: float = _t - float(jn_u.get("dead_at", _t))
			jroot_u.rotation.x = minf(PI * 0.5, jage_u * 6.0)
			jroot_u.position.y = -minf(0.4, jage_u * 1.0)
			if jage_u > 1.0:
				jroot_u.visible = false
	# 子弹：10Hz 采样插值，短命弹体按缺帧隐藏
	var bi := _find_bullet_frame(t)
	if bi >= 0 and bi < _bullets.size():
		var ba: Dictionary = _bullets[bi]
		var bb: Dictionary = _bullets[mini(bi + 1, _bullets.size() - 1)]
		var bta: float = float(ba.get("t", 0)) / 1000.0
		var btb: float = float(bb.get("t", 0)) / 1000.0
		var bk: float = 0.0 if btb - bta <= 0.0001 else clampf((t - bta) / (btb - bta), 0.0, 1.0)
		var bmap: Dictionary = {}
		for rb in ba.get("b", []):
			bmap[int(rb[0])] = rb
		var bmap_b: Dictionary = {}
		for rbb in bb.get("b", []):
			bmap_b[int(rbb[0])] = rbb
		var seen_b := {}
		var last_pos: Dictionary = _bullet_last_pos
		for bid in bmap.keys():
			var bid2: int = int(bid)
			var ra2: Array = bmap[bid2]
			var rb2: Array = bmap_b.get(bid2, ra2)
			var bx: float = lerpf(float(ra2[1]), float(rb2[1]) if rb2.size() > 1 else float(ra2[1]), bk) / 100.0
			var bz: float = lerpf(float(ra2[2]), float(rb2[2]) if rb2.size() > 2 else float(ra2[2]), bk) / 100.0
			var y_a: float = float(ra2[10]) / 100.0 if ra2.size() > 10 else 1.15
			var y_b: float = float(rb2[10]) / 100.0 if rb2.size() > 10 else y_a
			var by: float = lerpf(y_a, y_b, bk)   # 高度同样插值，避免 10Hz 阶梯式上下跳
			seen_b[bid2] = true
			var node_b = _bullet_nodes.get(bid2)
			if node_b == null:
				var col_b := Color(float(ra2[4]), float(ra2[5]), float(ra2[6]))
				node_b = _make_bullet(ra2, col_b, maxf(0.08, float(ra2[7])))
				_bullet_nodes[bid2] = node_b
				# 与 host Bullet._build_unified_visual 同款出手弹跳：0.7 → 1.08 → 1.0
				var _vk0: int = int(ra2[9]) if ra2.size() > 9 else 0
				if _vk0 >= 100:
					var fs: Vector3 = node_b.scale
					node_b.scale = fs * 0.7
					var btw := create_tween()
					btw.tween_property(node_b, "scale", fs * 1.08, 0.06)
					btw.tween_property(node_b, "scale", fs, 0.05)
			node_b.visible = true
			node_b.position = Vector3(bx, by, bz)
			# Spin 子节点旋转（host Bullet._spin_node）
			var _spn = node_b.get_node_or_null("Spin")
			if _spn is Node3D:
				(_spn as Node3D).rotate_y(float(node_b.get_meta("spin", 0.0)) * get_process_delta_time())
			# 朝向：用广播帧的真实位移（render-t 帧间位移在 10Hz 采样下会抖动/反向，导致轨迹看起来歪）
			var pdx: float = (float(rb2[1]) - float(ra2[1])) / 100.0 if rb2.size() > 1 else 0.0
			var pdz: float = (float(rb2[2]) - float(ra2[2])) / 100.0 if rb2.size() > 2 else 0.0
			last_pos[bid2] = Vector2(bx, bz)
			if absf(pdx) + absf(pdz) > 0.0005:
				node_b.rotation.y = atan2(pdx, pdz)
				if node_b.has_meta("pitch"):
					var py: float = (float(rb2[10]) - float(ra2[10])) / 100.0 if (rb2.size() > 10 and ra2.size() > 10) else 0.0
					var hl := sqrt(pdx * pdx + pdz * pdz)
					if hl > 0.0005:
						node_b.rotation.x = -atan2(py, hl)
		for bid3 in _bullet_nodes.keys():
			if not seen_b.has(bid3):
				_bullet_nodes[bid3].visible = false
	_update_world_hud(t)
	# 事件：向前推进时播报；回退时按时间重建最近几条
	if t < _t - 0.5 or t < _last_ev_time - 0.5:
		_rebuild_feed(t)
	_t = t
	while _ev_ptr < _events.size() and float(_events[_ev_ptr].get("t", 0)) / 1000.0 <= t:
		_push_event(_events[_ev_ptr])
		_ev_ptr += 1
	_last_ev_time = t
	_purge_feed()


var _last_ev_time := -1.0


func _find_frame(t: float) -> int:
	if _frames.is_empty():
		return -1
	var lo := 0
	var hi := _frames.size() - 1
	while lo < hi:
		var mid := int((lo + hi) / 2)
		if float(_frames[mid].get("t", 0)) / 1000.0 < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0 and float(_frames[lo].get("t", 0)) / 1000.0 > t:
		lo -= 1
	return clampi(lo, 0, _frames.size() - 1)


func _find_mini_frame(t: float) -> int:
	if _minis.is_empty():
		return -1
	var lo := 0
	var hi := _minis.size() - 1
	while lo < hi:
		var mid := int((lo + hi) / 2)
		if float(_minis[mid].get("t", 0)) / 1000.0 < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0 and float(_minis[lo].get("t", 0)) / 1000.0 > t:
		lo -= 1
	return clampi(lo, 0, _minis.size() - 1)


func _find_jungle_frame(t: float) -> int:
	if _jungle.is_empty():
		return -1
	var lo := 0
	var hi := _jungle.size() - 1
	while lo < hi:
		var mid := int((lo + hi) / 2)
		if float(_jungle[mid].get("t", 0)) / 1000.0 < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0 and float(_jungle[lo].get("t", 0)) / 1000.0 > t:
		lo -= 1
	return clampi(lo, 0, _jungle.size() - 1)


## 飘字：用与对局一致的数值/配色规则（伤害：物伤黄白/法伤紫/暴击更大；金币金色；治疗绿色）
## 被动标记：fake 英雄的 markers 是 [{source: GameEntity, ...}] 数组，source 只用来显示名字
func _marker_source(nm: String) -> GameEntity:
	var cached = _marker_src_cache.get(nm)
	if cached != null and is_instance_valid(cached):
		return cached
	var ge := GameEntity.new()
	ge.display_name = nm
	_marker_src_cache[nm] = ge
	return ge


func _apply_markers(fake: Hero, txt: String) -> void:
	var arr: Array = []
	if txt != "":
		for part in txt.split("|", false):
			var kv := str(part).split(":", false)
			if kv.size() < 2:
				continue
			var src := _marker_source(str(kv[0]))
			var cnt: int = int(kv[1])
			for k in range(cnt):
				arr.append({"source": src, "stack": k + 1})
	fake.markers = arr


## PostFX：跟随英雄的受击红晕 / 低血红屏 / 阵亡灰屏（与对局同源）
## 回放死亡回放面板：跟随英雄阵亡时弹出，复活自动收起（同 host 自动展示）
func _show_death_recap(d) -> void:
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return
	if _dr_layer == null:
		_dr_layer = CanvasLayer.new()
		_dr_layer.layer = 141
		add_child(_dr_layer)
		_dr_view = DeathRecapViewScript.new()
		_dr_layer.add_child(_dr_view)
		_dr_view.closed_by_user.connect(func():
			if _dr_view != null:
				_dr_view.visible = false)
	_dr_view.set_data(_json_unsafe(d))


func _json_unsafe(v):
	if v is Dictionary:
		var d: Dictionary = v as Dictionary
		if d.has("__c") and d["__c"] is Array and (d["__c"] as Array).size() >= 3:
			var ca: Array = d["__c"]
			return Color(float(ca[0]), float(ca[1]), float(ca[2]), float(ca[3]) if ca.size() > 3 else 1.0)
		if d.has("__v2") and d["__v2"] is Array:
			var v2: Array = d["__v2"]
			return Vector2(float(v2[0]), float(v2[1]))
		if d.has("__v3") and d["__v3"] is Array:
			var v3: Array = d["__v3"]
			return Vector3(float(v3[0]), float(v3[1]), float(v3[2]))
		var out: Dictionary = {}
		for k in d.keys():
			out[k] = _json_unsafe(d[k])
		return out
	if v is Array:
		var arr: Array = []
		for it in v:
			arr.append(_json_unsafe(it))
		return arr
	return v


## 录像状态条解码：[label, ratio, [r,g,b], segments, value, pulse] → HeroInfoControl 用的字典
func _decode_statuses(arr) -> Array:
	var out: Array = []
	if not (arr is Array):
		return out
	for s in (arr as Array):
		if not (s is Array) or (s as Array).size() < 6:
			continue
		var c: Array = (s as Array)[2] if ((s as Array)[2] is Array) else [1.0, 1.0, 1.0]
		out.append({
			"label": str((s as Array)[0]),
			"ratio": clampf(float((s as Array)[1]), 0.0, 1.0),
			"color": Color(float(c[0]), float(c[1]), float(c[2])),
			"segments": int((s as Array)[3]),
			"value": str((s as Array)[4]),
			"pulse": int((s as Array)[5]) == 1,
		})
	return out

## 回放：按 buff 帧里各英雄的 red/blue 键开关地面光环（与单机/联机一致）
func _apply_buff_rings(fr: Dictionary) -> void:
	var act_r := {}
	var act_b := {}
	for ent in (fr.get("b", []) as Array):
		var hidx := int((ent as Array)[0])
		for tier in [1, 2]:
			for row in ((ent as Array)[tier] as Array):
				var key := str((row as Array)[0])
				if key == "red":
					act_r[hidx] = true
				elif key == "blue":
					act_b[hidx] = true
	for i in range(_hero_nodes.size()):
		var nd: Dictionary = _hero_nodes[i]
		var rr = nd.get("buff_red")
		if rr != null and is_instance_valid(rr):
			rr.visible = act_r.has(i)
		var bb = nd.get("buff_blue")
		if bb != null and is_instance_valid(bb):
			bb.visible = act_b.has(i)


func _hide_all_buff_rings() -> void:
	for nd in _hero_nodes:
		var rr = (nd as Dictionary).get("buff_red")
		if rr != null and is_instance_valid(rr):
			rr.visible = false
		var bb = (nd as Dictionary).get("buff_blue")
		if bb != null and is_instance_valid(bb):
			bb.visible = false

## 回放 BUFF 图标行：找最近一次 ≤t 的采样，按剩余时间回推，喂给 NetBuffRow（与联机同一份绘制）
func _update_buff_row() -> void:
	if _buff_view == null or _buff_frames.is_empty():
		_hide_all_buff_rings()
		return
	var fi: int = int(_follow_hero)
	if fi < 0:
		_hide_all_buff_rings()
		if _buff_sig != "":
			_buff_view.refresh({})
			_buff_sig = ""
		return
	var t_ms: int = int(round(_t * 1000.0))
	while _buff_ptr + 1 < _buff_frames.size() and int(_buff_frames[_buff_ptr + 1].get("t", 0)) <= t_ms:
		_buff_ptr += 1
	if int(_buff_frames[_buff_ptr].get("t", 0)) > t_ms and _buff_ptr > 0:
		_buff_ptr -= 1
	var fr: Dictionary = _buff_frames[_buff_ptr]
	_apply_buff_rings(fr)
	var elapsed: float = maxf(0.0, (t_ms - int(fr.get("t", 0))) / 1000.0)
	var top: Array = []
	var bot: Array = []
	for ent in (fr.get("b", []) as Array):
		if int((ent as Array)[0]) != fi:
			continue
		for tier in [0, 1]:
			var dst: Array = top if tier == 0 else bot
			for row in ((ent as Array)[1 + tier] as Array):
				var key := str((row as Array)[0])
				var def: Array = _buff_defs.get(key, [])
				if def.is_empty():
					continue
				var rem: float = maxf(0.0, float((row as Array)[1]) / 1000.0 - elapsed)
				var tot: float = maxf(0.001, float((row as Array)[2]) / 1000.0)
				dst.append([key, str(def[0]), def[1], str(def[2]), str(def[3]), rem, tot, false, str((row as Array)[3])])
	if top.is_empty() and bot.is_empty():
		if _buff_sig != "":
			_buff_view.refresh({})
			_buff_sig = ""
		return
	var sig := "%d|%d" % [fi, int(ceil(_t))]
	if sig == _buff_sig:
		return
	_buff_sig = sig
	_buff_view.refresh({"top": top, "bot": bot})


## 回放操作盘/目标框/推荐装：完全复刻单机布局与数据来源（NetTouchPad / NetTargetPanel / NetRecommendBar）
func _update_replay_controls() -> void:
	if _pad == null:
		return
	var fi: int = int(_follow_hero)
	if fi < 0 or fi >= _heroes.size() or fi >= _hero_state.size():
		_pad.visible = false
		if _tgt_panel != null:
			_tgt_panel.refresh([])
		if _rec_bar != null:
			_rec_bar.visible = false
		return
	_pad.visible = true
	var meta: Dictionary = _heroes[fi] if _heroes[fi] is Dictionary else {}
	var hs: Dictionary = _hero_state[fi] if _hero_state[fi] is Dictionary else {}
	var det := _detail_for(fi)
	var cds: Array = det.get("cds", hs.get("cds", []))
	var totals: Array = det.get("cdmax", hs.get("cd_total", []))
	var levels: Array = hs.get("slevels", [])
	var sk_names: Array = meta.get("skills", [])
	var sx: Array = det.get("sx", [])
	for i in range(3):
		var stsk := {
			"name": str(sk_names[i]) if i < sk_names.size() else "",
			"level": int(levels[i]) if i < levels.size() else 0,
			"max_level": 6 if i < 2 else 3,
			"cd": float(cds[i]) if i < cds.size() else 0.0,
			"cdmax": float(totals[i]) if i < totals.size() else 1.0,
			"mana_ok": true,
		}
		var ex: Dictionary = _sx_extra(sx, i)
		for k in ex:
			stsk[k] = ex[k]
		_pad.set_skill_state(i, stsk)
		_pad.set_upgrade_visible(i, false)
	if int(meta.get("has4", 0)) == 1:
		_pad.set_extra_skill_visible(true)
		_pad.set_extra_skill_state({
			"name": str(sk_names[3]) if sk_names.size() > 3 else "",
			"level": 1, "max_level": 1,
			"cd": float(cds[3]) if cds.size() > 3 else 0.0,
			"cdmax": float(totals[3]) if totals.size() > 3 else 1.0,
			"mana_ok": true,
		})
	else:
		_pad.set_extra_skill_visible(false)
	_pad.set_summoner_state({"name": str(meta.get("summoner", "")),
		"cd": float(det.get("sum_cd", 0.0)), "cdmax": float(det.get("sum_max", 1.0))})
	_pad.set_recover_state({"cd": float(cds[4]) if cds.size() > 4 else 0.0, "cdmax": 60.0})
	for i in range(2):
		_pad.set_active_visible(i, false)
	# 普攻轮盘读数（aa：伤害/攻速/强化/装备被动小字）
	_pad.set_attack_state(det.get("aa", []))
	# 回城进度：HeroInfoControl 状态条按 fake hero 的 is_recalling/recall_timer 自动绘制（同单机）
	# 敌人索敌头像条：射程内敌方英雄（同单机规则）
	_pad.set_enemy_picker(_replay_enemy_picker(fi, meta))
	var ui_row := _ui_row_for(fi)
	if _tgt_panel != null:
		var tr: Array = ui_row.get("tgt", []) if ui_row is Dictionary else []
		# 旧录像/非英雄目标行的 maxhp 可能为 0：用当前回放世界里的同阵营同名单位补正
		if tr.size() >= 6 and float(tr[5]) <= 0.0:
			for uw in _unit_world:
				if str(uw.get("name", "")) == str(tr[2]) and int(uw.get("team", -1)) == int(tr[1]):
					tr = tr.duplicate()
					tr[5] = float(uw.get("max", 1.0))
					break
		_tgt_panel.refresh(tr)
	if _rec_bar != null:
		var rb = ui_row.get("rb", null) if ui_row is Dictionary else null
		if rb is Dictionary:
			_rec_bar.feed({"gold": int(ui_row.get("gold", 0)), "rb": rb})
			_rec_bar.visible = true
		else:
			_rec_bar.visible = false


## 取某英雄最近的 ui 采样（金币/目标/推荐装）
func _ui_row_for(idx: int) -> Dictionary:
	if _ui_frames.is_empty():
		return {}
	var tms: int = int(round(_t * 1000.0))
	while _ui_ptr + 1 < _ui_frames.size() and int(_ui_frames[_ui_ptr + 1].get("t", 0)) <= tms:
		_ui_ptr += 1
	if int(_ui_frames[_ui_ptr].get("t", 0)) > tms and _ui_ptr > 0:
		_ui_ptr -= 1
	var fr: Dictionary = _ui_frames[_ui_ptr]
	for row in (fr.get("h", []) as Array):
		if int((row as Array)[0]) == idx:
			var rb = (row as Array)[3]
			if rb is Dictionary:
				_rb_cache[idx] = rb
			else:
				rb = _rb_cache.get(idx, null)
			if (row as Array).size() > 4 and (row as Array)[4] is Array:
				_det_cache[idx] = (row as Array)[4]
			if fr.get("tt", []) is Array and not (fr.get("tt", []) as Array).is_empty():
				_tt_cache = fr.get("tt", [])
			return {"gold": int((row as Array)[1]), "tgt": (row as Array)[2], "rb": rb, "tgold": (int((row as Array)[5]) if (row as Array).size() > 5 else -1), "equips": (row as Array)[6] if (row as Array).size() > 6 else []}
	return {}


func _detail_for(idx: int) -> Dictionary:
	var d = _det_cache.get(idx, null)
	if not (d is Array) or (d as Array).size() < 7:
		return {}
	return {"aa": d[0], "sx": d[1], "sa": d[2],
		"sum_cd": float(d[3]), "sum_max": float(d[4]),
		"recalling": int(d[5]), "recall_ratio": float(d[6]),
		"cds": d[7] if d.size() > 7 else [], "cdmax": d[8] if d.size() > 8 else []}


## 技能图标读数解码（与 NetSession._pack_skill_icons / NetClientBattle._skill_icon_extra 同编码）
func _sx_extra(sx: Array, i: int) -> Dictionary:
	if i >= sx.size():
		return {}
	var f: Array = sx[i]
	if not (f is Array) or f.size() < 15:
		return {}
	return {
		"in_window": int(f[0]) == 1,
		"win_left": float(f[1]), "win_total": float(f[2]), "segments_left": int(f[3]),
		"icon_dmg": int(f[4]), "icon_dmg_magic": int(f[5]) == 1,
		"icon_dmg2": int(f[6]), "icon_dmg2_magic": int(f[7]) == 1,
		"icon_count": int(f[8]), "icon_fx": f[9], "icon_aa": int(f[10]) == 1,
		"charge_max": int(f[11]), "charge_now": int(f[12]),
		"blocked": int(f[13]) == 1, "block_cue": str(f[14]),
	}


## 点顶部战况带 → 打开全局英雄信息面板（同单机 C 面板，复用 RosterView）
## 索敌头像条：跟随英雄射程内敌方英雄（按距离排序，≤5）
func _replay_enemy_picker(fi: int, meta: Dictionary) -> Array:
	var ar := float(meta.get("ar", 0.0))
	if ar <= 0.0 or fi < 0 or fi >= _hero_pos.size():
		return []
	var my_team := int(meta.get("team", _me_team))
	var sp: Vector3 = _hero_pos[fi]
	var cand: Array = []
	for i in range(_heroes.size()):
		if i == fi:
			continue
		var hm: Dictionary = _heroes[i] if _heroes[i] is Dictionary else {}
		if int(hm.get("team", -1)) == my_team:
			continue
		var hs: Dictionary = _hero_state[i] if i < _hero_state.size() and _hero_state[i] is Dictionary else {}
		if int(hs.get("alive", 1)) == 0:
			continue
		var d: float = sp.distance_to(_hero_pos[i])
		if d > ar + 1.2:
			continue
		cand.append([i, d])
	cand.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var out: Array = []
	for i in range(mini(cand.size(), 5)):
		var idx := int(cand[i][0])
		out.append([idx, str((_heroes[idx] as Dictionary).get("name", "")), false])
	return out


## T 团队决策面板：录像 tt（模式/龙/经济/时长）+ 双方分路计划
func _toggle_team_decision() -> void:
	if _tdv == null:
		return
	if _tdv.visible:
		_tdv.visible = false
		return
	var tt: Array = _tt_cache
	var data := {
		"time": float(tt[4]) if tt.size() > 4 else _t,
		"mode": str(tt[0]) if tt.size() > 0 else "—",
		"dragon": bool(int(tt[1])) if tt.size() > 1 else false,
		"gold_diff": (int(tt[2]) - int(tt[3])) if tt.size() > 3 else 0,
		"allies": [], "foes": [],
	}
	for i in range(_heroes.size()):
		var m: Dictionary = _heroes[i] if _heroes[i] is Dictionary else {}
		var role := str(m.get("role", ""))
		var line := "[AI] %s (%s) -> %s" % [str(m.get("name", "")), role, _lane_name(HeroPickData.role_lane(role))]
		if int(m.get("team", 0)) == _me_team:
			(data["allies"] as Array).append(line)
		else:
			(data["foes"] as Array).append(line)
	_tdv.set_data(data)
	_tdv.visible = true


func _lane_name(lane: String) -> String:
	match lane:
		"发育路": return "发育路"
		"中路", "MID": return "MID"
		"对抗路": return "对抗路"
		"打野": return "打龙"
	return "未分配"


# ---------------- 终局：EndBanner → 聚光灯舞台 → 结算页（与单机/联机同实现） ----------------

func _result_rows() -> Array:
	var owner: Dictionary = _doc.get("meta", {}) as Dictionary
	var rows: Array = []
	for i in range(_heroes.size()):
		var m: Dictionary = _heroes[i] if _heroes[i] is Dictionary else {}
		var hs: Dictionary = _hero_state[i] if i < _hero_state.size() and _hero_state[i] is Dictionary else {}
		var gold := int(_ui_row_for(i).get("gold", 0))
		var f: Array = []
		for fr in _final_rows:
			if (fr as Array).size() > 1 and int((fr as Array)[0]) == i:
				f = fr
				break
		rows.append({
			"name": str(m.get("name", "")), "team": int(m.get("team", 0)),
			"k": int(f[1]) if f.size() > 1 else int(hs.get("k", 0)),
			"d": int(f[2]) if f.size() > 2 else int(hs.get("d", 0)),
			"a": int(f[3]) if f.size() > 3 else int(hs.get("a", 0)),
			"gold": int(f[4]) if f.size() > 4 else gold,
			"tgold": int(f[5]) if f.size() > 5 else gold,
			"dmg": int(f[6]) if f.size() > 6 else 0,
			"taken": int(f[7]) if f.size() > 7 else 0,
			"heal": int(f[8]) if f.size() > 8 else 0,
			"lh": int(f[9]) if f.size() > 9 else 0,
			"cc": int(f[10]) if f.size() > 10 else 0,
			"turret": int(f[11]) if f.size() > 11 else 0,
			"jungle": int(f[12]) if f.size() > 12 else 0,
			"mvp": int(f[13]) == 1 if f.size() > 13 else false,
			"equip": f[14] if f.size() > 14 else [],
			"role": str(m.get("role", "")), "nick": str(m.get("nick", "")),
			"lv": int(hs.get("lvl", 1)),
			"mine": i == int(owner.get("me", -1)),
			"ai": bool(m.get("ai", true)),
		})
	return rows


func _pm_rating(r: Dictionary) -> float:
	if r.is_empty():
		return 0.0
	var team := int(r.get("team", 0))
	var team_rows: Array = []
	for o in (_pm_payload.get("rows", []) as Array):
		if int((o as Dictionary).get("team", -1)) == team:
			team_rows.append(o)
	return MatchResultScript.rating(r, team_rows)


func _pm_medal_by_rating(rr: float) -> int:
	return MatchResultScript.medal_by_rating(rr)

func _row_by_name(nm: String) -> Dictionary:
	for o in (_pm_payload.get("rows", []) as Array):
		if str((o as Dictionary).get("name", "")) == nm:
			return o
	return {}


func _begin_end_sequence() -> void:
	if _end_started:
		return
	var win := int(_doc.get("meta", {}).get("winner", -1))
	if win < 0:
		return
	_end_started = true
	_playing = false
	_end_cam_owned = true
	# 1) 镜头锁到被摧毁的水晶，播终章爆炸（与单机/联机共用 CrystalFinale）
	var crys_pos := _finale_crystal_pos(win)
	var pitch := deg_to_rad(-58.0)
	var yaw := deg_to_rad(_cam_yaw)
	var off := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * 30.0
	_cam_target = crys_pos
	_cam.position = crys_pos + off
	_cam.look_at(crys_pos + Vector3(0, 1.6, 0), Vector3.UP)
	var fx: Node = CrystalFinaleScript.new()
	fx.name = "CrystalFinale"
	add_child(fx)
	fx.set("on_shake", Callable(self, "_shake"))
	fx.call("play", crys_pos, win == _me_team)
	# 2) 5 秒后终局横幅（与单机 tw.tween_interval(5.0) → EndBanner 同节奏）
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	# 终局横幅（与单机同款 EndBanner）
	_banner_layer = CanvasLayer.new()
	_banner_layer.layer = 200
	add_child(_banner_layer)
	_banner = EndBannerScript.new()
	_banner.won = win == _me_team
	_banner_layer.add_child(_banner)
	_banner.finished.connect(_start_postmatch)


## 被摧毁水晶的世界坐标（输的一方的水晶；录像里塔坐标是厘米整数）
func _finale_crystal_pos(win: int) -> Vector3:
	var loser_team: int = (1 - win) if win == 0 or win == 1 else win
	for t in _turrets:
		if not (t is Dictionary):
			continue
		if str((t as Dictionary).get("type", "")) != "crystal":
			continue
		if int((t as Dictionary).get("team", -1)) != loser_team:
			continue
		return Vector3(float((t as Dictionary).get("x", 0)) / 100.0, 0.0,
			float((t as Dictionary).get("z", 0)) / 100.0)
	return Vector3(-53, 0, 53) if loser_team == Config.Team.PLAYER else Vector3(53, 0, -53)


func _start_postmatch() -> void:
	if _banner_layer != null and is_instance_valid(_banner_layer):
		_banner_layer.queue_free()
	_banner_layer = null
	# 隐藏对局 HUD / 操作盘 / 世界（保留英雄模型进入聚光灯舞台）
	if _ui_layer != null: _ui_layer.visible = false
	if _hud_layer != null: _hud_layer.visible = false
	if _pad != null: _pad.visible = false
	if _tgt_panel != null: _tgt_panel.visible = false
	if _rec_bar != null: _rec_bar.visible = false
	if _kfeed != null: _kfeed.visible = false
	if _recall_view != null: _recall_view.visible = false
	if _chat_box != null: _chat_box.visible = false
	if _world != null: _world.visible = false
	if _statics != null: _statics.visible = false
	# 聚光灯舞台只保留随后搬入的己方 5 名英雄：先隐藏场景里所有其他 3D 对象
	# （防御塔/水晶/小兵/野怪/子弹/塔基砖/遗留特效），避免它们出现在舞台背景。
	for child in get_children():
		if child == _cam:
			continue
		if child is Node3D:
			(child as Node3D).visible = false
	if _buff_view != null:
		_buff_view.visible = false
	for i in range(_hero_nodes.size()):
		var root3 = _hero_nodes[i].get("root")
		if root3 != null and is_instance_valid(root3):
			root3.visible = false
	# 舞台容器：把己方 5 名英雄模型搬进来（对局层已隐藏，模型要留在可见容器）
	_pm_stage_root = Node3D.new()
	_pm_stage_root.name = "PMStage"
	add_child(_pm_stage_root)
	_pm_payload = {
		"winner": int(_doc.get("meta", {}).get("winner", -1)),
		"dur": _duration, "player_team": _me_team,
		"rows": _result_rows(),
		# 回放经济曲线：从逐帧 g=[我方总经济,敌方总经济] 按分钟取一个点
		"gold_hist": _replay_gold_hist(),
		"replay": true,
	}


	var entries: Array = []
	var ally_ids: Array = []
	for i in range(_heroes.size()):
		var m: Dictionary = _heroes[i] if _heroes[i] is Dictionary else {}
		if int(m.get("team", -1)) == _me_team:
			ally_ids.append(i)
	var units: Array = []
	for k in range(ally_ids.size()):
		var idx := int(ally_ids[k])
		var m: Dictionary = _heroes[idx] if _heroes[idx] is Dictionary else {}
		var nd: Node3D = _hero_nodes[idx].get("root")
		if nd == null or not is_instance_valid(nd):
			continue
		var old_parent := nd.get_parent()
		if old_parent != null:
			old_parent.remove_child(nd)
		_pm_stage_root.add_child(nd)
		units.append(nd)
		nd.visible = true
		var ap = _hero_nodes[idx].get("ap")
		var idle := str(_hero_nodes[idx].get("idle", ""))
		if ap is AnimationPlayer and idle != "":
			(ap as AnimationPlayer).play(idle)
		var row := _row_by_name(str(m.get("name", "")))
		entries.append({"world": nd.global_position, "hero": str(m.get("name", "")),
			"nick": str(m.get("nick", "")),
			"lane": HeroPickData.role_lane(str(row.get("role", ""))),
			"mvp": false, "medal": -1, "node": nd})
	if entries.is_empty():
		_finish_and_show_result()
		return
	# MVP / 奖牌：统一 MatchResult 口径
	var best_i := 0
	var best_r := -1.0
	for i in range(entries.size()):
		var rr := _pm_rating(_row_by_name(str(entries[i]["hero"])))
		entries[i]["rating"] = rr
		entries[i]["medal"] = MatchResultScript.medal_by_rating(rr)
		if rr > best_r:
			best_r = rr
			best_i = i
	for i in range(entries.size()):
		entries[i]["mvp"] = (i == best_i)
	# 舞台本体（站位/聚光灯/黑背景+主光/铭牌/镜头）交给共享 PostMatchStage
	_pm_stage_node = PostMatchStageScript.new()
	_pm_stage_node.name = "PostMatchStage"
	add_child(_pm_stage_node)
	_pm_stage_node.detail_provider = func() -> Dictionary: return _pm_detail_dict()
	_pm_stage_node.finished.connect(_finish_and_show_result)
	_pm_stage_node.setup(self, _cam, units, entries, int(_doc.get("meta", {}).get("winner", -1)) == _me_team,
		0, {"own_team": _me_team})
	_pm_view = _pm_stage_node.view


func _replay_gold_hist() -> Array:
	var out: Array = []
	var last_min := -1
	for fr in _frames:
		if not (fr is Dictionary):
			continue
		var minute := int(float(fr.get("t", 0)) / 60000.0)
		if minute == last_min:
			continue
		last_min = minute
		var g = fr.get("g", [])
		if g is Array and (g as Array).size() >= 2:
			out.append(int(g[0]) - int(g[1]))
	if out.is_empty():
		out.append(0)
	return out


func _pm_detail_dict() -> Dictionary:
	var row := _row_by_name(str((_pm_payload.get("rows", []) as Array)[0].get("name", ""))) if _pm_payload.has("rows") else {}
	# 找到玩家自己的数据行
	for o in (_pm_payload.get("rows", []) as Array):
		if bool((o as Dictionary).get("mine", false)):
			row = o
			break
	var rank_lines: Array = ["本局不计排位星"]
	rank_lines.append("对局时长 %02d:%02d" % [int(_duration) / 60, int(_duration) % 60])
	return {
		"hero": str(row.get("name", "")), "nick": str(row.get("nick", "")),
		"lane": HeroPickData.role_lane(str(row.get("role", ""))),
		"mvp": bool(row.get("mvp", false)), "rating": _pm_rating(row),
		"medal": MatchResultScript.medal_by_rating(_pm_rating(row)),
		"rows": [
			["K / D / A", "%d / %d / %d" % [int(row.get("k", 0)), int(row.get("d", 0)), int(row.get("a", 0))]],
			["总经济", "%d" % int(row.get("tgold", row.get("gold", 0)))],
			["英雄伤害", "%d" % int(row.get("dmg", 0))],
			["承受伤害", "%d" % int(row.get("taken", 0))],
			["治疗量", "%d" % int(row.get("heal", 0))],
			["补刀", "%d" % int(row.get("lh", 0))],
			["推塔伤害", "%d" % int(row.get("turret", 0))],
			["控制时长", "%.1f s" % (float(row.get("cc", 0)) / 10.0)],
			["野区经济", "%d" % int(row.get("jungle", 0))],
		],
		"rank_lines": rank_lines,
	}

func _finish_and_show_result() -> void:
	# 舞台层/灯光/黑环境由共享 PostMatchStage 自行清理
	_pm_view = null
	_pm_stage_node = null
	if _pm_stage_root != null and is_instance_valid(_pm_stage_root):
		_pm_stage_root.queue_free()
		_pm_stage_root = null
	# 结算页（与联机同一份 NetResultPanel → 单机 ResultsPanel 版式）
	_result_layer = CanvasLayer.new()
	_result_layer.layer = 110
	add_child(_result_layer)
	_result_panel = NetResultPanelScript.new()
	_result_panel.defer = false
	_result_layer.add_child(_result_panel)
	_result_panel._on_result(_pm_payload)

func _toggle_global_panel() -> void:
	if _rview == null:
		_rview_layer = CanvasLayer.new()
		_rview_layer.layer = 142
		add_child(_rview_layer)
		_rview = RosterViewScript.new()
		_rview_layer.add_child(_rview)
		_rview.closed_by_user.connect(func():
			if _rview != null:
				_rview.visible = false)
	if _rview.visible:
		_rview.visible = false
		return
	var rows: Array = []
	for i in range(_heroes.size()):
		var meta: Dictionary = _heroes[i] if _heroes[i] is Dictionary else {}
		var hs: Dictionary = _hero_state[i] if i < _hero_state.size() and _hero_state[i] is Dictionary else {}
		var ui := _ui_row_for(i)
		var mx: float = maxf(1.0, float(hs.get("mx", 1.0)))
		# 装备/总经济：优先用 2Hz ui 采样（新录像），旧录像回退到终局 final 行
		var eq_ids: Array = []
		var ui_eq = ui.get("equips", [])
		if ui_eq is Array and not (ui_eq as Array).is_empty():
			eq_ids = ui_eq
		else:
			for fr in _final_rows:
				if (fr as Array).size() > 14 and int((fr as Array)[0]) == i:
					eq_ids = (fr as Array)[14] if (fr as Array)[14] is Array else []
					break
		var equips: Array = []
		for iid in eq_ids:
			var it2: Dictionary = ItemDatabase.get_item(str(iid))
			equips.append([str(it2.get("name", iid)), int(it2.get("tier", 1)), str(iid)])
		# 总经济：新录像 ui 采样带 tgold；旧录像回退终局 final[5]；再退当前金币
		var tgold: int = int(ui.get("tgold", -1))
		if tgold < 0:
			for fr2 in _final_rows:
				if (fr2 as Array).size() > 5 and int((fr2 as Array)[0]) == i:
					tgold = int((fr2 as Array)[5])
					break
		if tgold < 0:
			tgold = int(ui.get("gold", 0))
		rows.append({
			"name": str(meta.get("name", "")), "hero": str(meta.get("name", "")),
			"team": int(meta.get("team", 0)), "level": int(hs.get("lvl", 1)),
			"own": i == int(_follow_hero), "hp_ratio": clampf(float(hs.get("hp", 0.0)) / mx, 0.0, 1.0),
			"k": int(hs.get("k", 0)), "d": int(hs.get("d", 0)), "a": int(hs.get("a", 0)),
			"gold": tgold, "is_ai": bool(meta.get("ai", true)),
			"role": str(meta.get("role", "")), "dead": int(hs.get("alive", 1)) == 0,
			"respawn": float(hs.get("revive", 0.0)),
			"chips": [], "skills": [], "lane": -1, "mark": 0, "equips": equips, "equip_ids": eq_ids,
		})
	_rview.set_rows(rows, "attr")
	_rview.visible = true


func _update_postfx(delta: float) -> void:
	if _follow_hero < 0 or _follow_hero >= _hero_state.size():
		return
	var st: Dictionary = _hero_state[_follow_hero] if not (_hero_state[_follow_hero] as Dictionary).is_empty() else {}
	if st.is_empty():
		return
	if not bool(st.get("alive", false)):
		PostFX.set_dead(true)
		PostFX.set_low_hp(0.0)
		return
	PostFX.set_dead(false)
	if _dr_view != null and _dr_view.visible:
		_dr_view.visible = false   # 复活：收起死亡回放（同 host 复活自动关闭）
	var mx: float = maxf(1.0, float(st.get("mx", 1.0)))
	PostFX.set_low_hp(clampf((float(st.get("hp", 0.0)) + float(st.get("shield", 0.0))) / mx, 0.0, 1.0))


func _spawn_popup(ev: Dictionary) -> void:
	var kind := str(ev.get("p", ""))
	var d: Dictionary = ev.get("d", {})
	var wp := Vector3(float(ev.get("x", 0)) / 100.0, float(ev.get("y", 0)) / 100.0, float(ev.get("z", 0)) / 100.0)
	var txt := ""
	var col := Color(1, 1, 1)
	var fs := int(round(22.0 * UiKit.scale()))
	var rise := 48.0
	var crit := false
	match kind:
		"dmg":
			var am := int(round(float(d.get("am", 0.0))))
			txt = "%d" % am
			crit = bool(d.get("crit", false))
			fs = int(round(float(UiKit.damage_number_size(float(am), crit)) * UiKit.scale()))
			if crit:
				col = Color(1.0, 0.55, 0.18)
				rise = 62.0
			elif bool(d.get("mag", false)):
				col = Color(0.86, 0.55, 1.0)
			else:
				col = Color(1.0, 0.93, 0.72)
			if bool(d.get("shield", false)):
				col = Color(0.55, 0.85, 1.0)
			if float(d.get("am", 0.0)) >= 80.0:
				Vfx.hit_impact(wp + Vector3.UP * 0.6, Vector3.UP, col, col.lightened(0.3),
					clampf(float(d.get("am", 0.0)) / 260.0, 0.5, 1.7))
			elif float(d.get("am", 0.0)) >= 40.0:
				Vfx.hit_spark(wp + Vector3.UP * 0.8, col, Vector3.UP, 0.55)
				if _follow_hero >= 0 and _follow_hero < _hero_pos.size():
					if wp.distance_to(_hero_pos[_follow_hero]) < 18.0 and float(d.get("am", 0.0)) >= 60.0:
						_shake(0.16, 0.16)
					if wp.distance_to(_hero_pos[_follow_hero]) < 14.0:
						# 跟随英雄受击：同对局红晕闪一下
						PostFX.damage(clampf(float(d.get("am", 0.0)) / 400.0, 0.2, 0.9),
							clampf(float(d.get("am", 0.0)) / 900.0, 0.0, 0.5))
		"gold":
			txt = "+%d" % int(d.get("am", 0))
			col = Color(1.0, 0.86, 0.35)
			fs = int(round(20.0 * UiKit.scale()))
		"heal":
			txt = "+%d" % int(d.get("am", 0))
			col = Color(0.45, 1.0, 0.55)
			fs = int(round(20.0 * UiKit.scale()))
		_:
			return
	if txt == "" or not (_hud_layer != null):
		return
	var lab := Label.new()
	lab.text = txt
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", fs)
	lab.add_theme_color_override("font_color", col)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("outline_size", 4 if crit else 3)
	_hud_root.add_child(lab)
	_pops.append({"node": lab, "world": wp, "age": 0.0, "rise": rise})


func _update_popups(delta: float) -> void:
	if _pops.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	var alive: Array = []
	for p in _pops:
		var lab: Label = p["node"]
		if not is_instance_valid(lab):
			continue
		p["age"] = float(p["age"]) + delta
		var age: float = float(p["age"])
		if age > 0.95:
			lab.queue_free()
			continue
		var wp: Vector3 = p["world"]
		if _cam != null and not _cam.is_position_behind(wp):
			var sp: Vector2 = _cam.unproject_position(wp)
			lab.position = sp + Vector2(-lab.size.x * 0.5, -float(p["rise"]) * age)
			lab.visible = sp.x > -200 and sp.x < vp.x + 200 and sp.y > -200 and sp.y < vp.y + 200
		else:
			lab.visible = false
		var a: float = clampf(1.0 - (age - 0.5) / 0.45, 0.0, 1.0)
		lab.modulate.a = a
		alive.append(p)
	_pops = alive


func _clear_popups() -> void:
	for p in _pops:
		var lab: Label = p["node"]
		if is_instance_valid(lab):
			lab.queue_free()
	_pops.clear()


func _shake(amp: float, dur: float) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_dur = maxf(_shake_dur, dur)
	_shake_t = maxf(_shake_t, dur)


func _shake_vec(delta: float) -> Vector3:
	if _shake_t <= 0.0:
		return Vector3.ZERO
	_shake_t = maxf(0.0, _shake_t - delta)
	var k: float = _shake_t / maxf(0.001, _shake_dur)
	var a: float = _shake_amp * k * k
	var now: float = Time.get_ticks_msec() * 0.001
	if _shake_t <= 0.0:
		_shake_amp = 0.0
	return Vector3(sin(now * 61.0), sin(now * 47.0) * 0.6, cos(now * 53.0)) * a


## 阵亡观战（与对局一致）：主视角英雄阵亡 → 自动跟最近存活友方；复活自动切回
func _auto_spectate() -> void:
	if _follow_hero < 0 or _follow_hero >= _hero_state.size():
		_spectate_origin = -1
		return
	var st: Dictionary = _hero_state[_follow_hero]
	if st.is_empty():
		return
	if not bool(st.get("alive", false)):
		if _spectate_origin < 0:
			_spectate_origin = _follow_hero
		# 英雄死亡 → 跳到“下一个还活着的英雄”（按名册顺序循环，不限于友方）
		var n: int = _heroes.size()
		for step in range(1, n + 1):
			var ni: int = (_follow_hero + step) % n
			if ni >= _hero_state.size():
				continue
			var si: Dictionary = _hero_state[ni]
			if si.is_empty() or not bool(si.get("alive", false)):
				continue
			_follow_hero = ni
			_manual_follow = ni
			break
	elif _spectate_origin >= 0 and _spectate_origin != _follow_hero:
		var os: Dictionary = _hero_state[_spectate_origin] if _spectate_origin < _hero_state.size() else {}
		if not os.is_empty() and bool(os.get("alive", false)):
			_follow_hero = _spectate_origin
			_manual_follow = _spectate_origin
			_spectate_origin = -1


func _update_recall_fx(i: int, pos: Vector3, alive: bool, st: Dictionary) -> void:
	var node: Node3D = _recall_nodes.get(i)
	var rec_t: float = float(st.get("recall", 0.0))
	var tp_t: float = float(st.get("tp", 0.0))
	var active: bool = alive and (float(st.get("is_recall", 0)) != 0.0 or rec_t > 0.0 or tp_t > 0.0)
	if not active:
		if node != null:
			node.visible = false
		return
	if node == null:
		node = Node3D.new()
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 1.9
		tm.outer_radius = 2.45
		tm.rings = 48
		tm.ring_segments = 8
		ring.mesh = tm
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.45, 0.82, 1.0, 0.75)
		rm.emission_enabled = true
		rm.emission = Color(0.35, 0.75, 1.0)
		rm.emission_energy_multiplier = 2.2
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = rm
		ring.position.y = 0.12
		node.add_child(ring)
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.8
		cyl.height = 6.0
		cyl.radial_segments = 20
		beam.mesh = cyl
		var bm2 := StandardMaterial3D.new()
		bm2.albedo_color = Color(0.5, 0.85, 1.0, 0.18)
		bm2.emission_enabled = true
		bm2.emission = Color(0.4, 0.8, 1.0)
		bm2.emission_energy_multiplier = 1.2
		bm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.material_override = bm2
		beam.position.y = 3.0
		node.add_child(beam)
		add_child(node)
		_recall_nodes[i] = node
	node.visible = true
	node.position = pos
	var prog: float = 1.0
	if rec_t > 0.0:
		prog = clampf(1.0 - rec_t / 7.0, 0.0, 1.0)
	elif tp_t > 0.0:
		prog = clampf(1.0 - tp_t / 4.0, 0.0, 1.0)
	var ring2: MeshInstance3D = node.get_child(0)
	ring2.rotation.y += get_process_delta_time() * 2.2
	ring2.scale = Vector3.ONE * (0.85 + 0.3 * prog + 0.04 * sin(_t * 10.0))


func _add_mm_mark(idx: int, kind: int) -> void:
	if idx < 0 or idx >= _hero_state.size():
		return
	var st: Dictionary = _hero_state[idx]
	if st.is_empty():
		return
	var pos3: Vector3 = st.get("pos", Vector3.ZERO)
	_mm_marks.append({"wx": pos3.x, "wz": pos3.z, "team": int((_heroes[idx] as Dictionary).get("team", 0)),
		"kind": kind, "t0": _t})


## 受击反馈：闪白+脉冲（英雄再加一次后仰），与 host GameEntity._damage_feedback 同观感
func _play_hit_react(idx: int, amount: float) -> void:
	if idx < 0 or idx >= _hero_nodes.size():
		return
	var nd: Dictionary = _hero_nodes[idx]
	var root3: Node3D = nd.get("root")
	if root3 == null or not is_instance_valid(root3):
		return
	UnitVisuals.hit_flash(root3)
	UnitVisuals.hit_pulse(root3)
	if amount > 0.0:
		var tw: Tween = root3.create_tween()
		tw.tween_property(root3, "rotation:x", -0.10, 0.06)
		tw.tween_property(root3, "rotation:x", 0.0, 0.14)


## 施法起手动作：与 host 同一 AnimMap.clip(cast)（回放此前只播特效不播动作）
func _play_cast_anim(idx: int) -> void:
	if idx < 0 or idx >= _hero_nodes.size():
		return
	var nd: Dictionary = _hero_nodes[idx]
	var ap: AnimationPlayer = nd.get("ap")
	if ap == null:
		return
	var nm := str((_heroes[idx] as Dictionary).get("name", ""))
	var clip := AnimMap.clip(ap, "cast", nm)
	if clip == "":
		clip = str(nd.get("attack", ""))
	if clip == "" or not ap.has_animation(clip):
		return
	ap.play(clip)
	var _wm2 := _hero_model_of(nd)
	if _wm2 != null:
		HeroWeapons.play(_wm2, "cast")
	nd["anim"] = "attack"
	nd["atk_until"] = _t + 0.55


func _hero_model_of(nd: Dictionary) -> Node3D:
	var rt = nd.get("root")
	if rt == null or not is_instance_valid(rt):
		return null
	var hm = rt.get_node_or_null("HeroModel")
	return hm as Node3D


func _hero_index_by_name(nm: String) -> int:
	for i in range(_heroes.size()):
		if str((_heroes[i] as Dictionary).get("name", "")) == nm:
			return i
	return -1


func _play_attack_anim(idx: int) -> void:
	if idx < 0 or idx >= _hero_nodes.size():
		return
	var nd: Dictionary = _hero_nodes[idx]
	# 武器挥砍/后坐动作与单机 Hero._perform_attack 同源（WeaponRig 程序化动作）
	var _wm := _hero_model_of(nd)
	if _wm != null:
		HeroWeapons.play(_wm, "attack")
	var ap: AnimationPlayer = nd.get("ap")
	if ap == null:
		return
	var clip := ""
	var ar := float(nd.get("ar", -1.0))
	var shoot := str(nd.get("atk_shoot", ""))
	var al := str(nd.get("atk_l", ""))
	var ar2 := str(nd.get("atk_r", ""))
	if ar > 5.0 and shoot != "":
		clip = shoot
	elif al != "" or ar2 != "":
		var flip := bool(nd.get("melee_flip", false))
		nd["melee_flip"] = not flip
		clip = al if flip else ar2
	else:
		clip = str(nd.get("attack", ""))
	if clip == "":
		return
	var atk := ap.get_animation(clip)
	if atk != null:
		atk.loop_mode = Animation.LOOP_NONE
	ap.play(clip)
	nd["anim"] = "attack"
	nd["atk_until"] = _t + 0.5


## 回放孙悟空筋斗云：按录像高度/位移驱动脚下云团（与主机同一份 WukongCloud）
func _update_replay_wukong_cloud(i: int, nm: String, y: float, x: float, z: float) -> void:
	if i < 0 or i >= _hero_nodes.size():
		return
	var nd: Dictionary = _hero_nodes[i]
	var root3 = nd.get("root")
	if root3 == null or not is_instance_valid(root3):
		return
	var want: bool = nm == "孙悟空" and y > 0.45
	var cl = nd.get("cloud")
	if want and (cl == null or not is_instance_valid(cl)):
		cl = WukongCloudScript.build()
		root3.add_child(cl)
		nd["cloud"] = cl
	if cl != null and is_instance_valid(cl):
		cl.visible = want
		if want:
			var last: Vector3 = nd.get("last", Vector3(x, 0, z))
			var d := Vector3(x - last.x, 0.0, z - last.z)
			WukongCloudScript.tick(cl, d, 10.0, _t, true)


## 单位血条闪橙（同 WorldBarPainter 的 flash_t/flash_amt）：掉血瞬间 0.5s 渐变橙段
## 补刀提示（同 host HUD last_hit 规则）：以当前主视角英雄的一次普攻（护甲减免后）判断能否补刀
func _replay_last_hit(team: int, hp: float, armor: float) -> bool:
	var ci: int = int(_follow_hero)
	if ci < 0:
		ci = int((_doc.get("meta", {}) as Dictionary).get("me", -1))
	if ci < 0 or ci >= _hero_state.size():
		return false
	var hs: Dictionary = _hero_state[ci]
	if hs.is_empty():
		return false
	var my_team: int = int((_heroes[ci] as Dictionary).get("team", -1)) if ci < _heroes.size() else -1
	if my_team < 0 or team == my_team or hp <= 0.0:
		return false
	var atk: float = float(hs.get("ad", 0.0))
	var pen: float = float(hs.get("flat_pen", 0.0))
	if atk <= 0.0:
		return false
	var res := maxf(0.0, armor - pen)
	var dmg := atk * (1.0 - res / (res + 602.0))
	return hp < dmg


## 帧级闪橙：只在录像采样帧切换且该帧血量下降时触发（插值血量逐帧下降不能当受伤）
func _frame_flash(key: String, frame_idx: int, frame_hp: float, dt: float) -> Array:
	var e: Dictionary = _flash_cache.get(key, {})
	var ft: float = maxf(0.0, float(e.get("t", 0.0)) - dt)
	var fa: float = float(e.get("amt", 0.0))
	if int(e.get("f", -1)) != frame_idx:
		var prev_hp: float = float(e.get("hp", frame_hp))
		if frame_hp < prev_hp - 0.5:
			ft = 0.5
			fa = prev_hp - frame_hp
		e["f"] = frame_idx
		e["hp"] = frame_hp
	e["t"] = ft
	e["amt"] = fa
	_flash_cache[key] = e
	return [ft, fa]


func _unit_flash(key: String, hp: float, dt: float) -> Array:
	var e: Dictionary = _flash_cache.get(key, {})
	var prev: float = float(e.get("hp", hp))
	var ft: float = float(e.get("t", 0.0))
	var fa: float = float(e.get("amt", 0.0))
	if hp < prev - 0.5:
		fa = prev - hp
		ft = 0.5
	elif ft > 0.0:
		ft = maxf(0.0, ft - dt)
	_flash_cache[key] = {"hp": hp, "t": ft, "amt": fa}
	return [ft, fa]


func _find_bullet_frame(t: float) -> int:
	if _bullets.is_empty():
		return -1
	var lo := 0
	var hi := _bullets.size() - 1
	while lo < hi:
		var mid := int((lo + hi) / 2)
		if float(_bullets[mid].get("t", 0)) / 1000.0 < t:
			lo = mid + 1
		else:
			hi = mid
	if lo > 0 and float(_bullets[lo].get("t", 0)) / 1000.0 > t:
		lo -= 1
	return clampi(lo, 0, _bullets.size() - 1)


func _make_bullet(row: Array, col: Color, radius: float) -> Node3D:
	# 三端共享：录像带 kind/vkind（row[8]/row[9]）→ 与 host/联机同形弹体；旧录像回退发光球
	var kind := int(row[8]) if row.size() > 8 else -1
	if kind >= 0:
		var team := int(row[3]) if row.size() > 3 else 0
		var vk := int(row[9]) if row.size() > 9 else 0
		var flags := int(row[11]) if row.size() > 11 else 0
		var node := ProjectilePresenter.make(kind, team, vk, radius, flags)
		if node != null:
			add_child(node)   # 必须挂进场景树，否则回放里永远看不到子弹（之前漏了这一步）
			return node
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 1.6
	sm.height = radius * 3.2
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col.lightened(0.2)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _make_minion(type_code: int, team: int) -> Node3D:
	var root := Node3D.new()
	var tname: String = TYPE_NAMES[clampi(type_code, 0, TYPE_NAMES.size() - 1)]
	var model: Node3D = NetModels.minion(tname, team)
	if model != null:
		root.add_child(model)
		root.set_meta("model", model)
		# 行走质感与单机/客户端同源：步频起伏、左右摆、前倾、腿部/龙翼枢轴
		WalkFeel.attach(root, model, _minion_walk_opts(tname, model))
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var big: bool = type_code >= 4
		bm.size = Vector3(1.15, 1.15, 1.15) if big else Vector3(0.7, 0.7, 0.7)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		var col: Color = TEAM_COL[0] if team == int(Config.player_team) else TEAM_COL[1]
		m.albedo_color = col.lerp(TYPE_COL[clampi(type_code, 0, TYPE_COL.size() - 1)], 0.45)
		m.roughness = 0.7
		mi.material_override = m
		root.add_child(mi)
	# 小兵也挂走路循环，避免像滑行的盒子
	var ap := _find_ap(root)
	_setup_idle_walk(ap)
	var walk_c := _clip_hint(ap, ["walk", "run"])
	if walk_c != "":
		ap.play(walk_c)
	add_child(root)
	return root


## 模型相对 root 的最高点（用于把名字/血条放到模型头顶，而不是写死高度）
func _model_top(root: Node3D) -> float:
	var top := 0.0
	var inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var aabb: AABB = mi.get_aabb()
			var g: Transform3D = inv * mi.global_transform
			for i in range(8):
				var p2: Vector3 = g * aabb.get_endpoint(i)
				top = maxf(top, p2.y)
		for c in n.get_children():
			stack.append(c)
	return top


func _minion_walk_opts(kind: String, model: Node3D) -> Dictionary:
	# 与单机 Minion._walk_opts 完全同源：ActorPresenter 统一参数（步频/起伏/摆幅/腿翼枢轴）
	return ActorPresenter.walk_opts("minion", kind, model)


## 小兵普攻动作：与单机 Minion._model_lunge / _siege_recoil 同参数的程序化版本
func _play_minion_attack(root: Node3D, type_code: int) -> void:
	var mdl = root.get_meta("model", null)
	if not (mdl is Node3D) or not is_instance_valid(mdl):
		return
	var kind: String = TYPE_NAMES[clampi(type_code, 0, TYPE_NAMES.size() - 1)]
	var pivot: Node3D = (mdl as Node3D).get_node_or_null("ModelPivot")
	if pivot == null:
		return
	var old: Tween = pivot.get_meta("atk_tween", null)
	if old != null and old.is_valid():
		old.kill()
	var base_pos := pivot.position
	var base_rot := pivot.rotation
	if kind == "siege":
		var dist := 0.20
		var tw := create_tween()
		tw.tween_property(pivot, "position:z", base_pos.z - dist, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "rotation:x", base_rot.x - 0.075, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(pivot, "position:z", base_pos.z, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(pivot, "rotation:x", base_rot.x, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		var p := {"back": 0.12, "fwd": 0.36, "up": 0.18, "down": 0.18, "twist": 0.26, "dip": 0.05,
			"windup": 0.09, "strike": 0.10, "settle": 0.30}
		if kind == "ranged":
			p = {"back": 0.17, "fwd": 0.09, "up": 0.11, "down": 0.12, "twist": 0.15, "dip": 0.04,
				"windup": 0.13, "strike": 0.07, "settle": 0.26}
		elif kind == "super":
			p = {"back": 0.19, "fwd": 0.52, "up": 0.32, "down": 0.36, "twist": 0.46, "dip": 0.11,
				"windup": 0.13, "strike": 0.12, "settle": 0.36}
		elif kind in ["dragon", "storm", "shadow_dragon"]:
			p = {"back": 0.13, "fwd": 0.38, "up": 0.12, "down": 0.24, "twist": 0.0, "dip": 0.06,
				"windup": 0.10, "strike": 0.12, "settle": 0.30}
		var swing := 0.0
		if kind in ["melee", "super"]:
			swing = 0.16 if kind == "melee" else 0.26
		var tw := create_tween()
		tw.tween_property(pivot, "position:z", base_pos.z - float(p["back"]), float(p["windup"])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "rotation:x", base_rot.x + float(p["up"]), float(p["windup"]))
		tw.parallel().tween_property(pivot, "rotation:y", base_rot.y + float(p["twist"]), float(p["windup"]))
		tw.parallel().tween_property(pivot, "position:x", base_pos.x - swing * 0.45, float(p["windup"]))
		tw.tween_property(pivot, "position:z", base_pos.z + float(p["fwd"]), float(p["strike"])).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "position:x", base_pos.x + swing, float(p["strike"]))
		tw.parallel().tween_property(pivot, "rotation:x", base_rot.x - float(p["down"]), float(p["strike"]))
		tw.parallel().tween_property(pivot, "rotation:y", base_rot.y - float(p["twist"]) * 1.5, float(p["strike"]))
		tw.tween_property(pivot, "position:z", base_pos.z, float(p["settle"])).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(pivot, "position:x", base_pos.x, float(p["settle"]))
		tw.parallel().tween_property(pivot, "rotation:x", base_rot.x, float(p["settle"]))
		tw.parallel().tween_property(pivot, "rotation:y", base_rot.y, float(p["settle"]))
	if kind == "ranged" or kind == "siege":
		var ammo := (mdl as Node3D).get_node_or_null("ModelPivot/Ammo") as MeshInstance3D
		if ammo != null:
			ammo.visible = false
			get_tree().create_timer(0.8).timeout.connect(func() -> void:
				if is_instance_valid(ammo):
					ammo.visible = true)


func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null


func _setup_idle_walk(ap: AnimationPlayer) -> void:
	if ap == null:
		return
	for clip in ap.get_animation_list():
		var low := str(clip).to_lower()
		if low.find("idle") >= 0 or low.find("walk") >= 0 or low.find("run") >= 0:
			var a := ap.get_animation(clip)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR


func _clip_hint(ap: AnimationPlayer, hints: Array) -> String:
	# 三端统一：回放同样走 AnimMap.hint（与 host / 联机同一份 clip 映射）
	return AnimMap.hint(ap, hints)

func _set_bar(fill: MeshInstance3D, ratio: float) -> void:
	var w: float = float(fill.get_meta("w", 1.5))
	var r: float = clampf(ratio, 0.0, 1.0)
	fill.scale.x = maxf(r, 0.001)
	fill.position.x = -w * 0.5 + w * r * 0.5
	var mat: StandardMaterial3D = fill.material_override
	if r > 0.55:
		mat.albedo_color = Color(0.45, 1.0, 0.55, 0.95)
	elif r > 0.28:
		mat.albedo_color = Color(1.0, 0.82, 0.35, 0.95)
	else:
		mat.albedo_color = Color(1.0, 0.38, 0.33, 0.95)


func _update_ui() -> void:
	if _slider != null and not _dragging:
		_slider.set_value_no_signal(clampf(_t, 0.0, _duration))
	if _ui_time != null:
		_ui_time.text = "%s / %s" % [_fmt(_t), _fmt(_duration)]


func _fmt(sec: float) -> String:
	var s: int = int(maxf(0.0, sec))
	return "%02d:%02d" % [s / 60, s % 60]


# ---------------- 事件/播报 ----------------

func _push_event(ev: Dictionary) -> void:
	var kind0 := str(ev.get("k", ""))
	if kind0 == "hit":
		# 受击反馈（与 host 同一时刻）：闪白+脉冲；英雄后仰
		var hi_hit := int(ev.get("a", -1))
		if hi_hit >= 0 and hi_hit < _hero_nodes.size():
			_play_hit_react(hi_hit, float(ev.get("d", 0.0)))
		return
	if kind0 == "sfx" or kind0 == "ann":
		var evt3: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt3 - _t) < 0.5:
			var key := str(ev.get("key", ""))
			if key != "":
				if kind0 == "ann":
					SfxManager.play_announce(key, false)
				else:
					SfxManager.call("_play_sfx", key, float(ev.get("v", 0.0)))
		return
	if kind0 == "dr":
		var hi_dr := int(ev.get("a", -1))
		if _playing and _follow_hero == hi_dr:
			_show_death_recap(ev.get("d", {}))
		return
	if kind0 == "item":
		var evt5: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt5 - _t) < 0.9:
			_play_item_fx(str(ev.get("n", "")), str(ev.get("c", "")), str(ev.get("i", "")))
		return
	if kind0 == "chat":
		var ct: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(ct - _t) < 0.9:
			var speaker := str(ev.get("n", ""))
			if _chat_box != null:
				_chat_box.call("_on_message", speaker, int(ev.get("tm", 0)),
					str(ev.get("txt", "")), int(ev.get("me", 0)) == 1)
			var is_ai: bool = int(ev.get("ai", 0)) == 1
			if not is_ai and not ev.has("ai"):
				is_ai = _chat_speaker_is_ai(speaker)   # 兼容旧录像
			if is_ai:
				var vs = get_node_or_null("/root/VoiceService")
				if vs != null and vs.has_method("speak"):
					vs.call("speak", str(ev.get("txt", "")), speaker)
		return
	if kind0 == "feed":
		var evt4: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt4 - _t) < 0.9 and _kfeed != null:
			_kfeed.push(str(ev.get("a", "")), int(ev.get("at", 0)), str(ev.get("d", "")),
				str(ev.get("v", "")), int(ev.get("vt", -1)), ev.get("as", []), 0, 0)
		return
	if kind0 == "pop":
		var evt2: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt2 - _t) < 0.9:
			_spawn_popup(ev)
		return
	if kind0 == "lvl":
		var evt1: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt1 - _t) < 0.9:
			var hi2: int = int(ev.get("a", -1))
			if hi2 >= 0 and hi2 < _hero_pos.size():
				var lp: Vector3 = _hero_pos[hi2] + Vector3.UP * 1.0
				Vfx.sigil(lp, Color(1.0, 0.86, 0.4), 1.6, 0.5)
				Vfx.cast_glow(lp, Color(1.0, 0.92, 0.6), 1.4, 0.7)
		return
	if kind0 == "fx" and int(ev.get("kind", 0)) != 29:
		var evt_f: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt_f - _t) < 0.9:
			var fp := Vector3(float(ev.get("x", 0)) / 100.0, float(ev.get("y", 0)) / 100.0,
				float(ev.get("z", 0)) / 100.0)
			SkillFxPresenter.spawn_kind(int(ev.get("kind", 24)), fp, int(ev.get("tm", 0)),
				float(ev.get("r", 1.0)), float(ev.get("life", 0.5)), str(ev.get("caster", "")))
		return
	if kind0 == "hitfx":
		var evt_h: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt_h - _t) < 0.9:
			var hp2 := Vector3(float(ev.get("x", 0)) / 100.0, float(ev.get("y", 0)) / 100.0,
				float(ev.get("z", 0)) / 100.0)
			var hd := Vector3(float(ev.get("dx", 0)), float(ev.get("dy", 0)), float(ev.get("dz", 1)))
			var hc1: Array = ev.get("c1", [])
			var hc2: Array = ev.get("c2", [])
			var hc1c := Color(float(hc1[0]), float(hc1[1]), float(hc1[2])) if hc1.size() >= 3 else Color.WHITE
			var hc2c := Color(float(hc2[0]), float(hc2[1]), float(hc2[2])) if hc2.size() >= 3 else Color.WHITE
			Vfx.hit_impact(hp2, hd, hc1c, hc2c, float(ev.get("sf", 1.0)),
				str(ev.get("tk", "hero")), str(ev.get("sk", "hero")), int(ev.get("crit", 0)) == 1)
		return
	if kind0 == "cast" or kind0 == "atk":
		var evt0: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt0 - _t) < 0.9:
			if kind0 == "cast":
				_play_cast_fx(ev)
			else:
				_play_attack_fx(ev)
				_play_attack_anim(_hero_index_by_name(str(ev.get("n", ""))))
		return
	var txt := ""
	var col := Color(0.92, 0.96, 1.0)
	match str(ev.get("k", "")):
		"k":
			_add_mm_mark(int(ev.get("a", -1)), 0)
			var who := _hero_name(int(ev.get("a", -1)))
			txt = "%s 击杀" % who
			col = Color(1.0, 0.86, 0.45)
		"d":
			_add_mm_mark(int(ev.get("a", -1)), 1)
			var who2 := _hero_name(int(ev.get("a", -1)))
			txt = "%s 阵亡" % who2
			col = Color(1.0, 0.5, 0.45)
		"tower":
			var t_tm := int(ev.get("tm", -1))
			if t_tm < 0:
				txt = "防御塔被摧毁 ×%d" % int(ev.get("b", 1))
				col = Color(0.7, 0.85, 1.0)
			else:
				var mine := t_tm == _me_team
				txt = ("我方塔被摧毁 ×%d" if mine else "敌方塔被摧毁 ×%d") % int(ev.get("b", 1))
				col = Color(0.7, 0.85, 1.0) if mine else Color(1.0, 0.55, 0.45)
		"crystal":
			var c_tm := int(ev.get("tm", -1))
			if c_tm < 0:
				txt = "水晶被摧毁"
				col = Color(1.0, 0.85, 0.4)
			else:
				txt = "我方水晶被摧毁" if c_tm == _me_team else "敌方水晶被摧毁"
				col = Color(1.0, 0.45, 0.4) if c_tm == _me_team else Color(1.0, 0.85, 0.4)
	if txt == "":
		return
	# 击杀/阵亡瞬间切一次跟拍镜头（约 2.4s），正在手动跟随时不抢镜头
	var kind := str(ev.get("k", ""))
	if (kind == "k" or kind == "d") and _manual_follow < 0:
		var ev_t: float = float(ev.get("t", 0)) / 1000.0
		if absf(ev_t - _t) < 0.8:
			_kill_cam_idx = int(ev.get("a", -1))
			_kill_cam_t = 2.4
	var hname := ""
	if kind == "k" or kind == "d":
		hname = _hero_name(int(ev.get("a", -1)))
	_spawn_toast(txt, hname, col, _fmt(float(ev.get("t", 0)) / 1000.0))


## 技能出手特效：用录制下来的定位 + 最小技能参数，调与对局同一个 Vfx.play_spell
## 关键事件提示卡：头像 + 事件文字 + 时间，圆角描边，淡入淡出自动回收
func _spawn_toast(text: String, hero_name: String, accent: Color, tstr: String) -> void:
	if _feed == null:
		return
	var toast := EventToast.new()
	toast.hero_name = hero_name
	toast.text = text
	toast.time_text = tstr
	toast.accent = accent
	toast.custom_minimum_size = Vector2(380.0 * UiKit.scale(), 52.0 * UiKit.scale())
	toast.modulate.a = 0.0
	_feed.add_child(toast)
	_event_toasts.append({"node": toast, "t0": _t})
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.16)


func _update_toasts() -> void:
	if _event_toasts.is_empty():
		return
	var alive: Array = []
	for it in _event_toasts:
		var node = it["node"]
		if node == null or not is_instance_valid(node):
			continue
		var age: float = _t - float(it["t0"])
		if age > 3.6:
			node.queue_free()
			continue
		node.modulate.a = clampf(1.0 - (age - 2.9) / 0.7, 0.0, 1.0)
		alive.append(it)
	_event_toasts = alive


func _clear_toasts() -> void:
	for it in _event_toasts:
		var node = it["node"]
		if node != null and is_instance_valid(node):
			node.queue_free()
	_event_toasts.clear()


func _play_cast_fx(ev: Dictionary) -> void:
	# 三端共享 SkillFxPresenter：录像带 skill id 时用 SkillDatabase 原技能，与 host 播放完全同源
	var caster_name := str(ev.get("n", ""))
	# host 记录的 caster_pos 已是 Vfx.play_spell 的 cp（含 +UP*1.2 + fwd*0.65）；
	# SkillFxPresenter 内部还会再加一次，这里先减掉，避免回放技能特效整体偏高/偏前。
	var cp := Vector3(float(ev.get("cx", 0)) / 100.0, float(ev.get("cy", 120)) / 100.0, float(ev.get("cz", 0)) / 100.0)
	var tp := Vector3(float(ev.get("tx", 0)) / 100.0, 0.0, float(ev.get("tz", 0)) / 100.0)
	var fd := Vector3(float(ev.get("fx", 0.0)), 0.0, float(ev.get("fz", 1.0)))
	if fd.length() < 0.01:
		fd = Vector3.FORWARD
	fd = fd.normalized()
	var skd: Dictionary = ev.get("sk", {})
	SkillFxPresenter.play_spell(caster_name, int(ev.get("s", 0)), cp - Vector3.UP * 1.2 - fd * 0.65,
		tp, fd, str(ev.get("sid", "")), skd, int(ev.get("tm", 0)), self, true)
	# 施法起手动作（同一时刻，与 host 的 cast 动画同源）
	_play_cast_anim(_hero_index_by_name(caster_name))

func _play_item_fx(nm: String, cat: String, _item: String) -> void:
	var hi: int = _hero_index_by_name(nm)
	if hi < 0 or hi >= _hero_pos.size():
		return
	var p: Vector3 = _hero_pos[hi] + Vector3.UP * 0.15
	var col := Color(0.6, 0.85, 1.0)
	match cat:
		"df":
			col = Color(0.7, 0.95, 1.0)
		"haste":
			col = Color(0.45, 0.95, 1.0)
		"range":
			col = Color(1.0, 0.86, 0.45)
		"thorn":
			col = Color(0.85, 0.6, 0.4)
		"blood":
			col = Color(1.0, 0.32, 0.28)
		"ice":
			col = Color(0.6, 0.85, 1.0)
		"stasis":
			col = Color(1.0, 0.88, 0.4)
	Vfx.cast_glow(p + Vector3.UP * 1.0, col, 1.4, 0.6)
	Vfx.sigil(p, col, 2.2, 0.55)
	Vfx.shockwave(p, 2.0, col, 0.4)
	if cat == "stasis":
		Vfx.pillar(p, col, 1.2, 5.0, 0.8)


func _play_attack_fx(ev: Dictionary) -> void:
	var nm := str(ev.get("n", ""))
	var from_p := Vector3(float(ev.get("cx", 0)) / 100.0, 1.2, float(ev.get("cz", 0)) / 100.0)
	var to_p := Vector3(float(ev.get("tx", 0)) / 100.0, 0.0, float(ev.get("tz", 0)) / 100.0)
	var dir := (to_p - from_p)
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var col := Color(float(ev.get("cr", 1.0)), float(ev.get("cg", 0.9)), float(ev.get("cb", 0.6)))
	var col2 := Vfx.color2_for_hero(nm) if nm != "" else col.lerp(Color.WHITE, 0.5)
	var melee: bool = bool(int(ev.get("mz", -1)) == 1)
	if int(ev.get("mz", -1)) < 0:
		# 旧录像无 mz：按录像里的 attack_range 判定（host MELEE_AA_RANGE_MAX=5m）
		melee = _hero_ar_of(nm) <= 5.0
	if melee:
		# 与 host _melee_weapon_fx 同款：武器刀光从刀身拉向敌人朝我侧体表 + 接触火花
		var tr: float = float(ev.get("tr", 0.85))
		var th: float = float(ev.get("th", 1.15))
		var contact: Vector3 = to_p - dir * tr + Vector3.UP * th
		var tip: Vector3 = contact - dir * 1.2 + Vector3.UP * 0.1
		Vfx.weapon_hit(tip, contact, col, col2, 1.0)
	else:
		# 与 host _perform_attack 远程普攻同款：元素枪口爆发
		Vfx.cast_burst(nm, from_p, dir, 0.5)


func _hero_ar_of(nm: String) -> float:
	for m in _heroes:
		if str((m as Dictionary).get("name", "")) == nm:
			return float((m as Dictionary).get("ar", 0.0))
	return 0.0


func _chat_speaker_is_ai(nm: String) -> bool:
	for h in _heroes:
		if (h is Dictionary) and str(h.get("name", "")) == nm and bool(h.get("ai", false)):
			return true
	return false


func _hero_name(idx: int) -> String:
	if idx >= 0 and idx < _heroes.size():
		return str(_heroes[idx].get("name", "")).to_upper()
	return "?"


func _purge_feed() -> void:
	while _feed_items.size() > 5:
		var it: Dictionary = _feed_items.pop_front()
		if is_instance_valid(it["label"]):
			it["label"].queue_free()


func _rebuild_feed(t: float) -> void:
	if _kfeed != null:
		_kfeed.clear()
	if _chat_box != null:
		_chat_box.clear()
		# 回退后补最近 4 条聊天，避免聊天区空掉
		var recent: Array = []
		for ce in _chat_events:
			if float(ce.get("t", 0)) / 1000.0 <= t and float(ce.get("t", 0)) / 1000.0 >= t - 8.0:
				recent.append(ce)
		for ci in range(maxi(0, recent.size() - 4), recent.size()):
			var ce2: Dictionary = recent[ci]
			_chat_box.call("_on_message", str(ce2.get("n", "")), int(ce2.get("tm", 0)),
				str(ce2.get("txt", "")), int(ce2.get("me", 0)) == 1)
	_clear_popups()
	_clear_toasts()
	_feed_items.clear()
	for it in _feed_items:
		if is_instance_valid(it["label"]):
			it["label"].queue_free()
	_feed_items.clear()
	var start: int = 0
	for i in range(_events.size()):
		if float(_events[i].get("t", 0)) / 1000.0 <= t:
			start = i
	_ev_ptr = start + 1
	for i in range(maxi(0, start - 4), start + 1):
		if i >= 0 and i < _events.size():
			# chat 已由上面的最近 4 条单独回填，避免 seek 后重复插入
			if str(_events[i].get("k", "")) == "chat":
				continue
			_push_event(_events[i])


# ---------------- 输入/相机 ----------------

func _toggle_play() -> void:
	_playing = not _playing
	if _t >= _duration:
		_t = 0.0
		_playing = true
	_play_btn.text = "⏸ 暂停" if _playing else "▶ 播放"


func _cycle_speed() -> void:
	var opts := [0.5, 1.0, 1.5, 2.0, 4.0]
	var idx := opts.find(_speed)
	idx = (idx + 1) % opts.size()
	_speed = float(opts[idx])
	_speed_btn.text = "%.1f×" % _speed


func _sync_highlight_seek() -> void:
	if not _highlight:
		return
	_hl_idx = _kl_index_after(_t)
	_hl_end = -1.0
	if _hl_idx < _kill_times.size():
		_hl_end = minf(_duration, float(_kill_times[_hl_idx]) + 3.0)
		_follow_highlight_killer()
	else:
		_highlight = false
		_hl_btn.text = "◆ 集锦"
		_hint_label.text = HINT_TEXT


func _kl_index_after(t: float) -> int:
	for i in range(_kill_times.size()):
		if float(_kill_times[i]) >= t - 0.05:
			return i
	return _kill_times.size()


func _jump_to_highlight(idx: int) -> void:
	var ii := clampi(idx, 0, _kill_times.size() - 1)
	_hl_idx = ii
	var kt: float = float(_kill_times[ii])
	_t = maxf(0.0, kt - 3.0)
	_hl_end = minf(_duration, kt + 3.0)
	_follow_highlight_killer()
	if _hint_label != null and ii < _kill_heroes.size():
		var hi := int(_kill_heroes[ii])
		if hi >= 0 and hi < _heroes.size():
			_hint_label.text = "集锦 %d/%d：%s 击杀（已自动切到击杀者视角）" % [ii + 1, _kill_times.size(), str((_heroes[hi] as Dictionary).get("name", ""))]
	_rebuild_feed(_t)
	_apply_frame(_t)


## 集锦模式：切到当前击杀者的主视角
func _follow_highlight_killer() -> void:
	if not _highlight:
		return
	if _hl_idx < 0 or _hl_idx >= _kill_heroes.size():
		return
	var hi := int(_kill_heroes[_hl_idx])
	if hi >= 0 and hi < _heroes.size():
		if _manual_follow != hi:
			_select_follow(hi)


func _toggle_highlight() -> void:
	if _kill_times.is_empty():
		_hint_label.text = "这局没有击杀，无法生成集锦"
		return
	_highlight = not _highlight
	if _highlight:
		_hl_prev_manual = _manual_follow
		_hl_idx = _kl_index_after(_t)
		if _hl_idx >= _kill_times.size():
			_hl_idx = 0
		_hl_btn.text = "◆ 完整"
		_playing = true
		_play_btn.text = "⏸ 暂停"
		_jump_to_highlight(_hl_idx)
		_hint_label.text = "集锦模式：第 %d/%d 个击杀（自动跟随击杀者，←/→ 切段）" % [_hl_idx + 1, _kill_times.size()]
	else:
		_hl_end = -1.0
		_hl_btn.text = "◆ 集锦"
		# 退出集锦：恢复进入前的主视角
		if _hl_prev_manual >= 0 and _hl_prev_manual < _heroes.size():
			_select_follow(_hl_prev_manual)
			_hint_label.text = "已退出集锦，恢复 %s 视角" % str((_heroes[_hl_prev_manual] as Dictionary).get("name", ""))
		elif _manual_follow >= 0:
			_clear_follow()
			_hint_label.text = HINT_TEXT
		else:
			_hint_label.text = HINT_TEXT


## 点英雄头像：切到该英雄主视角
func _select_follow(idx: int) -> void:
	if idx < 0 or idx >= _heroes.size():
		return
	_follow_hero = idx
	_manual_follow = idx
	_spectate_origin = -1
	_kill_cam_t = 0.0
	_cam_pitch = -60.0
	_cam_dist = 52.0
	if _hint_label != null:
		_hint_label.text = "正在跟随：%s（Esc 回自由镜头 / 点小地图跳转）" % str((_heroes[idx] as Dictionary).get("name", ""))


func _clear_follow() -> void:
	_follow_hero = -1
	_manual_follow = -1
	_cam_pitch = -60.0
	_cam_dist = 62.0
	_cam_target = Vector3.ZERO


func _cycle_follow() -> void:
	if _heroes.is_empty():
		return
	_manual_follow += 1
	if _manual_follow >= _heroes.size():
		_manual_follow = -1
	_kill_cam_t = 0.0
	_follow_hero = _manual_follow
	if _manual_follow >= 0:
		_hint_label.text = "正在跟随：%s（F 切换 / Esc 回自由视角）" % str(_heroes[_manual_follow].get("name", ""))
	else:
		_hint_label.text = HINT_TEXT


func _seek_by(sec: float) -> void:
	_t = clampf(_t + sec, 0.0, _duration)
	_sync_highlight_seek()
	_rebuild_feed(_t)
	_apply_frame(_t)


func _jump_to_time(t: float) -> void:
	_t = clampf(t, 0.0, _duration)
	_sync_highlight_seek()
	_rebuild_feed(_t)
	_apply_frame(_t)


func _change_speed(step: int) -> void:
	var opts := [0.5, 1.0, 1.5, 2.0, 4.0]
	var idx := opts.find(_speed)
	if idx < 0:
		idx = 1
	idx = clampi(idx + step, 0, opts.size() - 1)
	_speed = float(opts[idx])
	_speed_btn.text = "%.1f×" % _speed


func _set_speed_preset(i: int) -> void:
	var opts := [0.5, 1.0, 1.5, 2.0, 4.0]
	_speed = float(opts[clampi(i, 0, opts.size() - 1)])
	_speed_btn.text = "%.1f×" % _speed


func _seek_prev_kill() -> void:
	for i in range(_events.size() - 1, -1, -1):
		var ev: Dictionary = _events[i]
		var et: float = float(ev.get("t", 0)) / 1000.0
		if str(ev.get("k", "")) == "k" and et < _t - 0.3:
			_t = maxf(0.0, et)
			_playing = false
			_play_btn.text = "▶ 播放"
			_rebuild_feed(_t)
			_apply_frame(_t)
			return


func _cycle_follow_prev() -> void:
	if _heroes.is_empty():
		return
	_manual_follow -= 1
	if _manual_follow < -1:
		_manual_follow = _heroes.size() - 1
	_kill_cam_t = 0.0
	_follow_hero = _manual_follow
	if _manual_follow >= 0:
		_hint_label.text = "正在跟随：%s（Shift+F 反向 / Esc 回自由视角）" % str((_heroes[_manual_follow] as Dictionary).get("name", ""))
	else:
		_hint_label.text = HINT_TEXT


func _reset_camera() -> void:
	_cam_yaw = 0.0
	_cam_pitch = -55.0
	_cam_dist = 62.0
	_kill_cam_t = 0.0
	_cam_drag = false


func _toggle_hud_visible() -> void:
	if _hud2 == null:
		return
	_hud2.visible = not _hud2.visible
	if _hint_label != null:
		_hint_label.text = "界面已隐藏（H 显示）" if not _hud2.visible else HINT_TEXT


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _seek_next_kill() -> void:
	for ev in _events:
		var et: float = float(ev.get("t", 0)) / 1000.0
		if str(ev.get("k", "")) == "k" and et > _t + 0.3:
			_t = minf(_duration, et)
			_playing = false
			_play_btn.text = "▶ 播放"
			_rebuild_feed(_t)
			_apply_frame(_t)
			return


func _back_to_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if _end_started and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_back_to_lobby()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		var shift := ek.shift_pressed
		match ek.keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_T:
				_toggle_team_decision()
			KEY_LEFT:
				_seek_by(-1.0 if shift else -5.0)
			KEY_RIGHT:
				_seek_by(1.0 if shift else 5.0)
			KEY_HOME:
				_jump_to_time(0.0)
			KEY_END:
				_jump_to_time(_duration)
			KEY_PAGEUP:
				_seek_by(-30.0)
			KEY_PAGEDOWN:
				_seek_by(30.0)
			KEY_UP:
				_change_speed(1)
			KEY_DOWN:
				_change_speed(-1)
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_set_speed_preset(int(ek.keycode - KEY_1))
			KEY_ESCAPE:
				# 先关最上层面板，再退跟随，最后退出回放
				if _rview != null and _rview.visible:
					_toggle_global_panel()
					return
				if _tdv != null and _tdv.visible:
					_toggle_team_decision()
					return
				if _follow_hero >= 0 or _manual_follow >= 0:
					_clear_follow()
					if _hint_label != null:
						_hint_label.text = HINT_TEXT
				else:
					_back_to_lobby()
			KEY_F:
				if shift:
					_cycle_follow_prev()
				else:
					_cycle_follow()
			KEY_N:
				_seek_next_kill()
			KEY_J:
				_seek_prev_kill()
			KEY_P:
				_toggle_highlight()
			KEY_C:
				_toggle_global_panel()
			KEY_R:
				_reset_camera()
			KEY_H:
				_toggle_hud_visible()
			KEY_EQUAL, KEY_KP_ADD:
				_change_speed(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_change_speed(-1)
			KEY_F11:
				_toggle_fullscreen()
		return
	if event is InputEventScreenTouch:
		var stouch: InputEventScreenTouch = event
		if stouch.pressed:
			# 触屏先交给 HUD 命中测试：点头像切视角、点小地图跳转，不能被相机拖动吞掉
			if not _handle_hud_press(stouch.position):
				_begin_cam_drag(stouch.position)
		else:
			_finish_map_drag()
			if _cam_drag:
				_end_cam_drag()
		return
	if event is InputEventScreenDrag:
		if _mm_drag and _hud2 != null:
			var hd_s: Dictionary = _hud2.call("hit", (event as InputEventScreenDrag).position)
			if str(hd_s.get("type", "")) == "map":
				_mm_target = Vector3(float(hd_s.get("x", 0.0)), 0.0, float(hd_s.get("z", 0.0)))
		elif _cam_drag:
			_pan_cam_drag((event as InputEventScreenDrag).position)
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_finish_map_drag()
			if _cam_drag:
				_end_cam_drag()
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# 先处理 HUD；返回 false 才表示点在空白战场，可开始拖动相机
			if not _handle_hud_press(mb.position):
				_begin_cam_drag(mb.position)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 6.0, 22.0, 110.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 6.0, 22.0, 110.0)
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative != Vector2.ZERO:
		var mm: InputEventMouseMotion = event
		if _mm_drag and _hud2 != null:
			var hitd2: Dictionary = _hud2.call("hit", mm.position)
			if str(hitd2.get("type", "")) == "map":
				_mm_target = Vector3(float(hitd2.get("x", 0.0)), 0.0, float(hitd2.get("z", 0.0)))
			return
		if _cam_drag:
			_pan_cam_drag(mm.position)
		if (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_cam_yaw -= mm.relative.x * 0.25
			_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.2, -85.0, -20.0)


## 统一的 HUD 点击处理（鼠标/触屏共用）；返回 true 表示事件已被 HUD 消费
func _handle_hud_press(pos: Vector2) -> bool:
	if _hud2 == null:
		return false
	var hitd: Dictionary = _hud2.call("hit", pos)
	var hk := str(hitd.get("type", ""))
	match hk:
		"hero_ring", "hero":
			_select_follow(int(hitd.get("idx", -1)))
			return true
		"attr_head":
			_hud2.attr_collapsed = not _hud2.attr_collapsed
			_hud2.queue_redraw()
			return true
		"band":
			_toggle_global_panel()
			return true
		"map":
			_mm_drag = true
			_mm_was_follow = _follow_hero
			_mm_target = Vector3(float(hitd.get("x", 0.0)), 0.0, float(hitd.get("z", 0.0)))
			_follow_hero = -1
			_manual_follow = -1
			return true
	return false


func _finish_map_drag() -> void:
	if not _mm_drag:
		return
	_mm_drag = false
	if _mm_was_follow >= 0:
		_follow_hero = _mm_was_follow
		_manual_follow = _mm_was_follow
	else:
		_follow_hero = -1
		_manual_follow = -1
		_cam_target = _mm_target
	_mm_was_follow = -1


func _begin_cam_drag(screen: Vector2) -> void:
	if _mm_drag:
		return
	_cam_drag = true
	_cam_drag_moved = false
	_cam_drag_last = screen
	_cam_drag_prev_follow = _follow_hero
	# 跟随状态下拖动屏幕：先把自由视角目标放到当前英雄，再退出跟随，避免镜头跳回原点
	if _follow_hero >= 0 and _follow_hero < _hero_pos.size():
		_cam_target = _hero_pos[_follow_hero]
	_follow_hero = -1
	_manual_follow = -1


func _pan_cam_drag(screen: Vector2) -> void:
	var delta := screen - _cam_drag_last
	if delta.length() < 0.01:
		return
	_cam_drag_last = screen
	if delta.length() > 1.5:
		_cam_drag_moved = true
	var g_prev = _cam_ground_at(screen - delta)
	var g_cur = _cam_ground_at(screen)
	if g_prev != null and g_cur != null:
		_cam_target += (g_prev as Vector3) - (g_cur as Vector3)
	else:
		# 射线打不到地面（极端俯角/屏幕外）时用相机朝向估算平移
		var yaw := deg_to_rad(_cam_yaw) + (PI if _me_team == 1 else 0.0)
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var k := maxf(0.08, _cam_dist * 0.0018)
		_cam_target += (-right * delta.x + fwd * delta.y) * k
	_cam_target.y = 0.0
	_cam_target.x = clampf(_cam_target.x, -60.0, 60.0)
	_cam_target.z = clampf(_cam_target.z, -60.0, 60.0)


func _end_cam_drag() -> void:
	_cam_drag = false
	# 只是点了一下没拖动：恢复原来的跟随，不影响点选操作
	if not _cam_drag_moved and _cam_drag_prev_follow >= 0:
		_follow_hero = _cam_drag_prev_follow
		_manual_follow = _cam_drag_prev_follow
	_cam_drag_prev_follow = -1


func _cam_ground_at(screen: Vector2):
	if _cam == null:
		return null
	var origin := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return null
	var t := -origin.y / dir.y
	if t < 0.0:
		return null
	return origin + dir * t


func _update_camera() -> void:
	if _end_cam_owned:
		return
	if _cam == null:
		return
	var sh := _shake_vec(get_process_delta_time())
	# 红方回放：整机位绕 Y 轴 180°（同单机 BattleManager：出生在右下、操作方向一致）
	var flip_yaw := PI if _me_team == 1 else 0.0
	var follow_off := Vector3(0.0, 12.0, 8.0).rotated(Vector3.UP, flip_yaw)
	# 小地图拖动：相机只平移，高度/俯角保持单机跟随镜头的固定偏移（不会自动变高）
	if _mm_drag:
		_cam.global_position = _mm_target + follow_off + sh
		_cam.rotation_degrees = Vector3(-60.0, rad_to_deg(flip_yaw), 0.0)
		_cam.fov = 70.0
		return
	# 主视角：完全照搬单机对局镜头（固定偏移 (0,12,8)、俯角 -60°、fov70、指数平滑 + 远距吸附）
	if _follow_hero >= 0 and _follow_hero < _hero_pos.size():
		var tgt: Vector3 = _hero_pos[_follow_hero] + follow_off + Vector3.UP * 4.2
		var dlt: float = get_process_delta_time()
		if _cam.global_position.distance_to(tgt) > 25.0:
			_cam.global_position = tgt
		else:
			_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-12.0 * dlt)) + sh
		_cam.rotation_degrees = Vector3(-60.0, rad_to_deg(flip_yaw), 0.0)
		_cam.fov = 70.0
		return
	# 手动跟随优先；否则击杀镜头短暂跟拍；都没有时保持自由视角
	if _manual_follow >= 0 and _manual_follow < _hero_pos.size():
		_cam_target = _cam_target.lerp(_hero_pos[_manual_follow], clampf(get_process_delta_time() * 8.0, 0.0, 1.0))
		_cam_dist = lerpf(_cam_dist, 30.0, 0.05)
	elif _kill_cam_t > 0.0:
		_kill_cam_t = maxf(0.0, _kill_cam_t - get_process_delta_time())
		if _kill_cam_idx >= 0 and _kill_cam_idx < _hero_pos.size():
			_cam_target = _cam_target.lerp(_hero_pos[_kill_cam_idx], clampf(get_process_delta_time() * 6.0, 0.0, 1.0))
		_cam_dist = lerpf(_cam_dist, 34.0, 0.05)
	var pitch := deg_to_rad(_cam_pitch)
	var yaw := deg_to_rad(_cam_yaw) + flip_yaw
	var offset := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch)) * _cam_dist
	_cam.position = _cam_target + offset + sh
	_cam.look_at(_cam_target, Vector3.UP)


## 关键事件卡片（回放专用，纯绘制，不走 Label）
class EventToast extends Control:
	var hero_name := ""
	var text := ""
	var time_text := ""
	var accent := Color(1.0, 0.86, 0.45)
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiKit.flat(0.85, 10, 1, Color(accent.r, accent.g, accent.b, 0.55),
			Color(0.04, 0.055, 0.09, 0.92), 8.0, 6.0), r)
		draw_rect(Rect2(Vector2.ZERO, Vector2(4.0, size.y)), accent)
		var tx := 16.0
		if hero_name != "":
			HeroArt.draw_portrait(self, Vector2(32.0, size.y * 0.5), 17.0, hero_name, accent, false)
			tx = 58.0
		UiKit.text(self, Vector2(tx, size.y * 0.5 + 7.0), text,
			int(round(19.0 * UiKit.scale())), Color(0.97, 0.99, 1.0))
		UiKit.text(self, Vector2(size.x - 90.0, size.y * 0.5 + 6.0), time_text,
			int(round(14.0 * UiKit.scale())), Color(0.62, 0.72, 0.86))














