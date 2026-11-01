extends Node3D
## 录像回放（P1）：读 user://replays/*.rep，只重建视觉，不跑战斗逻辑。
## 入口：大厅「录像」→ ReplayBrowserPanel 设置 pending_file 后切到本场景。

const Repo = preload("res://scripts/core/ReplayRecorder.gd")
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const WorldBarPainterScript = preload("res://scripts/ui/WorldBarPainter.gd")
const DeathRecapViewScript = preload("res://scripts/ui/DeathRecapView.gd")
const NetBuffRowScript = preload("res://scripts/net/NetBuffRow.gd")
const AnimMap = preload("res://scripts/presentation/AnimMap.gd")   # 三端共享动画 clip 映射
const ProjectilePresenter = preload("res://scripts/presentation/ProjectilePresenter.gd")   # 三端共享子弹表现
const SkillFxPresenter = preload("res://scripts/presentation/SkillFxPresenter.gd")   # 三端共享技能特效
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
var _bullet_nodes: Dictionary = {}   # id -> Node3D
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
const HINT_TEXT := "空格 播放/暂停 · ←/→ ±5 秒 · N 下一击杀 · F 跟随英雄 · +/- 倍速 · 右键拖动旋转 · 滚轮缩放 · Esc 退出"

var _hint_label: Label = null
var _finisher_t := -1.0
var _hero_pos: Array = []        # 每帧英雄世界坐标（镜头跟随用）
var _kill_cam_t := 0.0           # 击杀镜头剩余时间
var _kill_cam_idx := -1          # 击杀镜头目标英雄
var _manual_follow := -1         # 手动跟随英雄下标（-1=关闭）
var _kill_times: Array = []      # 所有击杀时刻（集锦模式用）
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
	_jungle = _doc.get("jungle", [])
	_jungle_meta = _doc.get("jungle_meta", [])
	_bullets = _doc.get("bullets", [])
	_popups_data = _doc.get("popups", [])
	_buff_frames = _doc.get("buff_frames", [])
	_buff_defs = _doc.get("buff_defs", {})
	# 飘字/音效并入事件流（按时间排序），回放时与击杀/技能共用同一套推进逻辑
	var _combined: Array = (_doc.get("events", []) as Array).duplicate()
	_combined.append_array(_popups_data)
	_combined.append_array(_doc.get("audio", []))
	_combined.sort_custom(func(a, b) -> bool: return int(a.get("t", 0)) < int(b.get("t", 0)))
	_events = _combined
	_map = _doc.get("map", {})
	var meta: Dictionary = _doc.get("meta", {})
	_duration = maxf(float(meta.get("duration", 0.0)), 1.0)
	for ev in _events:
		if str(ev.get("k", "")) == "k":
			_kill_times.append(float(ev.get("t", 0)) / 1000.0)
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
		var model: Node3D = NetModels.hero(str(h.get("name", "")))
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
		var ap := _find_ap(root)
		_setup_idle_walk(ap)
		var idle_c := _clip_hint(ap, ["idle"])
		var walk_c := _clip_hint(ap, ["walk", "run"])
		var atk_c := _clip_hint(ap, ["attack"])
		if idle_c != "":
			ap.play(idle_c)
		# 名字/血条交给真实战场的 HeroInfoControl（下一段 _build_hud 创建），这里只留模型
		_hero_nodes.append({"root": root, "ap": ap, "idle": idle_c, "walk": walk_c, "attack": atk_c,
			"last": Vector3.ZERO, "anim": "idle", "atk_until": -1.0})
	# 防御塔 / 水晶
	for i in range(_turrets.size()):
		var t: Dictionary = _turrets[i]
		var root := Node3D.new()
		root.name = "T%d" % i
		var tp := Vector3(float(t.get("x", 0)) / 100.0, 0.0, float(t.get("z", 0)) / 100.0)
		root.position = tp
		add_child(root)
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
		var lbeam: Node3D = Vfx.make_lock_beam(Vfx.team_color(int(t.get("team", 0))))
		add_child(lbeam)
		lbeam.visible = false
		_turret_nodes.append({"root": root, "max": float(t.get("maxhp", 1)), "beam": lbeam})
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


func _update_world_hud(t: float) -> void:
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
		fake.is_mvp = int(st.get("mvp", 0)) == 1
		_apply_markers(fake, str(st.get("markers", "")))
		fake.exp = int(float(st.get("exp", 0)))
		fake.exp_to_next = int(maxf(1.0, float(st.get("exp_to_next", 200))))
		var wp: Vector3 = (st.get("pos", Vector3.ZERO) as Vector3) + Vector3.UP * 2.4
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
			anchor = 5.2 if sub == "crystal" else 4.6
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
		rows.append({
			"hp": hp, "max_hp": mx, "team": team_v, "team_color": team_col,
			"pos": sp2 - Vector2(w, hh) * 0.5, "w": w, "h": hh,
			"epic": epic, "ticks": ticks, "tick_step": step,
			"name_text": sub, "show_name": kind == "jungle",
			"turret": is_turret, "turret_arrow": false,
			"shield": 0.0, "interfere": 0.0, "doom": 0.0,
			"flash_t": 0.0, "flash_amt": 0.0, "heal_t": 0.0, "heal_amt": 0.0,
			"marker_list": [], "last_hit": false, "show_numbers": false, "num_text": "",
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
			"pings": pings_st, "marks": marks_st, "camps": camps_st,
			"me_team": int(meta_d.get("player_team", 0)),
			"feed": feed_st, "objectives": obj_st,
		}
		_hud2.queue_redraw()
		_update_buff_row()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 140
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# 顶部中央：标题 + 进度条 + 时间（右上角留给与对局同位置的战况带，y154 留给战报）
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

	_slider = HSlider.new()
	_slider.anchor_left = 0.5
	_slider.anchor_right = 0.5
	_slider.offset_left = -620.0
	_slider.offset_right = 620.0
	_slider.offset_top = 50.0
	_slider.offset_bottom = 74.0
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
	root.add_child(_slider)

	_ui_time = Label.new()
	_ui_time.anchor_left = 0.5
	_ui_time.anchor_right = 0.5
	_ui_time.offset_left = 632.0
	_ui_time.offset_right = 820.0
	_ui_time.offset_top = 52.0
	_ui_time.offset_bottom = 78.0
	_ui_time.add_theme_font_size_override("font_size", int(round(20.0 * UiKit.scale())))
	_ui_time.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	root.add_child(_ui_time)

	# 播放控制：底部右侧辅助键带（与对局「回城 / 恢复 / 召唤师」同尺寸 220、离底 30、离右 420/660/900/1140）
	_play_btn = _mk_btn("⏸ 暂停", Color(0.45, 0.7, 1.0))
	_anchor_br_btn(_play_btn, Vector2(420, 30), Vector2(220, 220))
	_play_btn.pressed.connect(_toggle_play)
	root.add_child(_play_btn)

	_speed_btn = _mk_btn("1.0×", Color(0.55, 0.85, 0.75))
	_anchor_br_btn(_speed_btn, Vector2(660, 30), Vector2(220, 220))
	_speed_btn.pressed.connect(_cycle_speed)
	root.add_child(_speed_btn)

	_hl_btn = _mk_btn("◆ 集锦", Color(1.0, 0.78, 0.4))
	_anchor_br_btn(_hl_btn, Vector2(900, 30), Vector2(220, 220))
	_hl_btn.pressed.connect(_toggle_highlight)
	root.add_child(_hl_btn)

	var quit := _mk_btn("✕ 退出", Color(0.9, 0.55, 0.45))
	_anchor_br_btn(quit, Vector2(1140, 30), Vector2(220, 220))
	quit.pressed.connect(_back_to_lobby)
	root.add_child(quit)

	# 击杀播报：与对局同位置（顶部居中、宽 620、top 154）
	_feed = VBoxContainer.new()
	_feed.anchor_left = 0.5
	_feed.anchor_right = 0.5
	_feed.offset_left = -310.0
	_feed.offset_right = 310.0
	_feed.offset_top = 154.0
	_feed.add_theme_constant_override("separation", 2)
	root.add_child(_feed)

	# 快捷键提示：顶部中央（标题/进度条下方，避开右上战况带与 y154 战报；底部让给播放键带）
	var hint := Label.new()
	hint.anchor_left = 0.5
	hint.anchor_right = 0.5
	hint.anchor_top = 0.0
	hint.anchor_bottom = 0.0
	hint.offset_left = -400.0
	hint.offset_right = 400.0
	hint.offset_top = 78.0
	hint.offset_bottom = 104.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.add_theme_font_size_override("font_size", int(round(15.0 * UiKit.scale())))
	hint.add_theme_color_override("font_color", Color(0.62, 0.7, 0.82))
	_hint_label = hint
	hint.text = HINT_TEXT
	root.add_child(hint)


## 右下锚点（同 TouchController._anchor_br：离右/离底偏移 + 簇内缩进 + 安全区）
func _anchor_br_btn(c: Control, from_br: Vector2, sz: Vector2) -> void:
	var off := from_br + Vector2(80.0, 20.0) + Vector2(UiKit.safe_right(), UiKit.safe_bottom())
	c.anchor_left = 1.0
	c.anchor_top = 1.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -off.x - sz.x
	c.offset_top = -off.y - sz.y
	c.offset_right = -off.x
	c.offset_bottom = -off.y


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
				var dclip := _clip_hint(dap, ["die", "death"])
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
		node["root"].position = Vector3(x, 0.0, z)
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
			var has_b: int = int(rb[4]) if rb.size() > 4 else has_a
			if hpv > 0.5 and (has_a == 1 or has_b == 1):
				var tx_a: float = float(ra[2]) if ra.size() > 2 else 0.0
				var tz_a: float = float(ra[3]) if ra.size() > 3 else 0.0
				var tx_b: float = float(rb[2]) if rb.size() > 2 else tx_a
				var tz_b: float = float(rb[3]) if rb.size() > 3 else tz_a
				var tgt_p := Vector3(lerpf(tx_a, tx_b, k) / 100.0, 1.0, lerpf(tz_a, tz_b, k) / 100.0)
				var src_p: Vector3 = (node2["root"] as Node3D).position + Vector3.UP * 4.0
				Vfx.aim_lock_beam(lbeam2, src_p, tgt_p, _t)
			else:
				lbeam2.visible = false
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
			_hud_turrets.append({"wx": float(td0.get("x", 0)) / 100.0, "wz": float(td0.get("z", 0)) / 100.0,
				"team": int(td0.get("team", 0)), "type": str(td0.get("type", "outer")),
				"alive": 1 if hpv > 0.5 else 0, "hp": hpv, "mx": maxf(1.0, float(node2["max"]))})
		if hpv > 0.5 and i < _turrets.size():
			var td: Dictionary = _turrets[i]
			_unit_world.append({"kind": "turret", "pos": Vector3(float(td.get("x", 0)) / 100.0, 0.0, float(td.get("z", 0)) / 100.0),
				"hp": hpv, "max": maxf(1.0, float(node2["max"])), "team": int(td.get("team", 0)),
				"name": str(td.get("type", "")), "sub": str(td.get("type", ""))})
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
			rows.append([id0, x0, z0, int(ra[5]), int(ra[4]), hp0,
				float(ra[6]) if ra.size() > 6 else 1000.0])
		var seen := {}
		for r in rows:
			var id: int = int(r[0])
			seen[id] = true
			var node3 = _mini_nodes.get(id)
			if node3 == null:
				node3 = _make_minion(int(r[3]), int(r[4]))
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
				"name": str(r[3]), "sub": TYPE_NAMES[clampi(int(r[3]), 0, TYPE_NAMES.size() - 1)]})
			# 朝向移动方向 + 行走动画（上下踏步 + 左右摆）
			var nowp: Vector3 = Vector3(float(r[1]), 0.0, float(r[2]))
			var prevp: Vector3 = node3.get_meta("prev", nowp)
			var dv: Vector3 = nowp - prevp
			var moving: bool = dv.length() > 0.01
			if moving:
				node3.rotation.y = atan2(dv.x, dv.z)
			node3.set_meta("prev", nowp)
			var ph: float = float(node3.get_meta("phase", 0.0))
			var bob: float = 0.055 * absf(sin(_t * 8.0 + ph)) if moving else 0.012 * absf(sin(_t * 2.0 + ph))
			node3.position = Vector3(nowp.x, bob, nowp.z)
			var mdl = node3.get_meta("model", null)
			if mdl is Node3D:
				(mdl as Node3D).rotation.z = 0.10 * sin(_t * 8.0 + ph) if moving else 0.0
				(mdl as Node3D).rotation.x = 0.0
		for id in _mini_nodes.keys():
			if seen.has(id):
				continue
			var nd2: Node3D = _mini_nodes[id]
			if not nd2.visible:
				continue
			if not bool(nd2.get_meta("dying", false)):
				nd2.set_meta("dying", true)
				nd2.set_meta("dead_at", _t)
			var age: float = _t - float(nd2.get_meta("dead_at", _t))
			var mdl2 = nd2.get_meta("model", null)
			if mdl2 is Node3D:
				(mdl2 as Node3D).rotation.x = minf(PI * 0.5, age * 7.0)
			nd2.position.y = -minf(0.35, age * 0.9)
			if age > 0.8:
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
			if jroot.visible:
				_unit_world.append({"kind": "jungle", "pos": jroot.position,
					"hp": jhp, "max": maxf(1.0, float(jnode["max"])), "team": 2,
					"name": str(_jungle_meta[ji2].get("name", "")) if ji2 < _jungle_meta.size() else "",
					"sub": str(_jungle_meta[ji2].get("name", "")) if ji2 < _jungle_meta.size() else ""})
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
		for bid in bmap.keys():
			var bid2: int = int(bid)
			var ra2: Array = bmap[bid2]
			var rb2: Array = bmap_b.get(bid2, ra2)
			var bx: float = lerpf(float(ra2[1]), float(rb2[1]) if rb2.size() > 1 else float(ra2[1]), bk) / 100.0
			var bz: float = lerpf(float(ra2[2]), float(rb2[2]) if rb2.size() > 2 else float(ra2[2]), bk) / 100.0
			seen_b[bid2] = true
			var node_b = _bullet_nodes.get(bid2)
			if node_b == null:
				var col_b := Color(float(ra2[4]), float(ra2[5]), float(ra2[6]))
				node_b = _make_bullet(ra2, col_b, maxf(0.08, float(ra2[7])))
				_bullet_nodes[bid2] = node_b
			node_b.visible = true
			node_b.position = Vector3(bx, 1.15, bz)
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


## 回放 BUFF 图标行：找最近一次 ≤t 的采样，按剩余时间回推，喂给 NetBuffRow（与联机同一份绘制）
func _update_buff_row() -> void:
	if _buff_view == null or _buff_frames.is_empty():
		return
	var fi: int = int(_follow_hero)
	if fi < 0:
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


func _hero_index_by_name(nm: String) -> int:
	for i in range(_heroes.size()):
		if str((_heroes[i] as Dictionary).get("name", "")) == nm:
			return i
	return -1


func _play_attack_anim(idx: int) -> void:
	if idx < 0 or idx >= _hero_nodes.size():
		return
	var nd: Dictionary = _hero_nodes[idx]
	var ap: AnimationPlayer = nd.get("ap")
	var clip := str(nd.get("attack", ""))
	if ap == null or clip == "":
		return
	var atk := ap.get_animation(clip)
	if atk != null:
		atk.loop_mode = Animation.LOOP_NONE
	ap.play(clip)
	nd["anim"] = "attack"
	nd["atk_until"] = _t + 0.42


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
		var node := ProjectilePresenter.make(kind, team, vk, radius)
		if node != null:
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
	if kind0 == "feed":
		var evt4: float = float(ev.get("t", 0)) / 1000.0
		if _playing and absf(evt4 - _t) < 0.9:
			_feed_items.append({"a": str(ev.get("a", "")), "at": int(ev.get("at", 0)),
				"d": str(ev.get("d", "")), "v": str(ev.get("v", "")), "vt": int(ev.get("vt", -1)),
				"as": ev.get("as", []), "t0": _t})
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
			txt = "防御塔被摧毁 ×%d" % int(ev.get("b", 1))
			col = Color(0.7, 0.85, 1.0)
		"crystal":
			txt = "水晶被摧毁"
			col = Color(1.0, 0.85, 0.4)
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
	var cp := Vector3(float(ev.get("cx", 0)) / 100.0, 0.0, float(ev.get("cz", 0)) / 100.0)
	var tp := Vector3(float(ev.get("tx", 0)) / 100.0, 0.0, float(ev.get("tz", 0)) / 100.0)
	var fd := Vector3(float(ev.get("fx", 0.0)), 0.0, float(ev.get("fz", 1.0)))
	if fd.length() < 0.01:
		fd = Vector3.FORWARD
	fd = fd.normalized()
	var skd: Dictionary = ev.get("sk", {})
	SkillFxPresenter.play_spell(caster_name, int(ev.get("s", 0)), cp, tp, fd,
		str(ev.get("sid", "")), skd, int(ev.get("tm", 0)), self, true)

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
	var to_p := Vector3(float(ev.get("tx", 0)) / 100.0, 1.0, float(ev.get("tz", 0)) / 100.0)
	var dir := (to_p - from_p)
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	var col := Color(float(ev.get("cr", 1.0)), float(ev.get("cg", 0.9)), float(ev.get("cb", 0.6)))
	var col2 := Vfx.color2_for_hero(nm) if nm != "" else col.lerp(Color.WHITE, 0.5)
	Vfx.muzzle(from_p, dir.normalized(), col, col2)
	Vfx.hit_spark(to_p + Vector3.UP * 0.6, col, Vector3.UP, 0.75)


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
	var kt: float = float(_kill_times[clampi(idx, 0, _kill_times.size() - 1)])
	_t = maxf(0.0, kt - 3.0)
	_hl_end = minf(_duration, kt + 3.0)
	_rebuild_feed(_t)
	_apply_frame(_t)


func _toggle_highlight() -> void:
	if _kill_times.is_empty():
		_hint_label.text = "这局没有击杀，无法生成集锦"
		return
	_highlight = not _highlight
	if _highlight:
		_hl_idx = _kl_index_after(_t)
		if _hl_idx >= _kill_times.size():
			_hl_idx = 0
		_hl_btn.text = "◆ 完整"
		_playing = true
		_play_btn.text = "⏸ 暂停"
		_jump_to_highlight(_hl_idx)
		_hint_label.text = "集锦模式：第 %d/%d 个击杀（←/→ 仍可切段，F 跟随）" % [_hl_idx + 1, _kill_times.size()]
	else:
		_hl_end = -1.0
		_hl_btn.text = "◆ 集锦"
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
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_LEFT:
				_t = maxf(0.0, _t - 5.0)
				_sync_highlight_seek()
				_rebuild_feed(_t)
			KEY_RIGHT:
				_t = minf(_duration, _t + 5.0)
				_sync_highlight_seek()
			KEY_ESCAPE:
				if _follow_hero >= 0 or _manual_follow >= 0:
					_clear_follow()
					if _hint_label != null:
						_hint_label.text = HINT_TEXT
				else:
					_back_to_lobby()
			KEY_F:
				_cycle_follow()
			KEY_N:
				_seek_next_kill()
			KEY_EQUAL, KEY_KP_ADD:
				_cycle_speed()
			KEY_MINUS, KEY_KP_SUBTRACT:
				_cycle_speed()
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _mm_drag:
				_mm_drag = false
				if _mm_was_follow >= 0:
					_follow_hero = _mm_was_follow
					_manual_follow = _mm_was_follow
				else:
					_follow_hero = -1
					_manual_follow = -1
					_cam_target = _mm_target
				_mm_was_follow = -1
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _hud2 != null:
			var hitd: Dictionary = _hud2.call("hit", mb.position)
			var hk := str(hitd.get("type", ""))
			if hk == "map":
				_mm_drag = true
				_mm_was_follow = _follow_hero
				_mm_target = Vector3(float(hitd.get("x", 0.0)), 0.0, float(hitd.get("z", 0.0)))
				return
			elif hk == "hero":
				_select_follow(int(hitd.get("idx", 0)))
				return
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
		if (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_cam_yaw -= mm.relative.x * 0.25
			_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.2, -85.0, -20.0)


func _update_camera() -> void:
	if _cam == null:
		return
	var sh := _shake_vec(get_process_delta_time())
	# 小地图拖动：相机只平移，高度/俯角保持单机跟随镜头的固定偏移（不会自动变高）
	if _mm_drag:
		_cam.global_position = _mm_target + Vector3(0.0, 12.0, 8.0) + sh
		_cam.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
		_cam.fov = 70.0
		return
	# 主视角：完全照搬单机对局镜头（固定偏移 (0,12,8)、俯角 -60°、fov70、指数平滑 + 远距吸附）
	if _follow_hero >= 0 and _follow_hero < _hero_pos.size():
		var tgt: Vector3 = _hero_pos[_follow_hero] + Vector3(0.0, 12.0, 8.0)
		var dlt: float = get_process_delta_time()
		if _cam.global_position.distance_to(tgt) > 25.0:
			_cam.global_position = tgt
		else:
			_cam.global_position = _cam.global_position.lerp(tgt, 1.0 - exp(-12.0 * dlt)) + sh
		_cam.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
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
	var yaw := deg_to_rad(_cam_yaw)
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
