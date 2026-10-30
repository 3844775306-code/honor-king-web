class_name NetMiniMap
extends Control
## NetMiniMap —— 联机接管客户端的小地图（M4-U P2）。
## 画法/常量按主机 scripts/ui/Minimap.gd 重做（同尺寸/同色/同警告圈/同点线标记），
## 数据源换成 NetClientBattle 每帧同步的 _views 引用（纯展示，不含任何模拟）。
## 输入语义同主机：按住拖动=相机本地取景平移（松手回正跟随英雄），轻点=一次相机跳转，
## 均只覆盖本地镜头、不发任何命令。

const MAP_SIZE := 120
const MINIMAP_SIZE := 300.0
const MinimapDraw = preload("res://scripts/ui/MinimapDraw.gd")        # 两端统一（主机 BattleManager：桌面/手机一律放大为 300，左上角 inset 40）
const DRAG_THRESHOLD := 5.0

# —— 我方防御塔被攻击警告圈（同主机 Minimap.gd 常量）——
const PING_COOLDOWN := 10.0
const PING_DURATION := 1.35
const PING_CYCLES := 3
const PING_SCAN_TICK := 0.1

# 阵营/类型常量（同 NetClientBattle）
const TEAM_PLAYER := 0
const TEAM_ENEMY := 1
const NET_HERO := 0
const NET_MINION := 1
const NET_TURRET := 2
const NET_JUNGLE := 3

var player_team := TEAM_PLAYER
var views := {}              # net_id -> view（NetClientBattle 每帧整体替换引用）
var self_net := -1
var own_recalling := 0       # 自己英雄回城中（画回城黄线）
var own_pos := Vector3.ZERO  # 自己英雄世界坐标
var obj: Array = []             # 目标计时 [暴君秒, 暴君存活, 主宰秒, 主宰存活]（host own.obj 传入）
var jg: Array = []              # 野怪记忆：host own.jg（我方已确认在复活中的野怪点位）
var active := false          # 接管且对局中且非第一人称才响应取景（NetClientBattle 每帧喂入）

# 相机覆盖状态（NetClientBattle 每帧读取后自行应用/复位）
var panning := false
var pan_world := Vector3.ZERO
var gaze_ready := false
var gaze_world := Vector3.ZERO

var _is_dragging := false
var _drag_started := false
var _mouse_down_pos := Vector2.ZERO

var _terrain_texture: ImageTexture = null
var _static_bushes: Array = []      # 草丛（小地图像素坐标）
var _static_walls: Array = []       # 墙体 [{p, a}]
var _static_packs: Array = []       # 血包点位
var _static_camps: Array = []       # 野怪营地中心（无视野时默认显示的幽灵点位）
var _static_done := false
var _redraw_counter := 0
var _ping_clock := 0.0
var _ping_scan_timer := 0.0
var _tower_ping_time := {}    # net_id -> 上次警告时的时钟
var _active_pings := {}       # net_id -> {"pos": Vector2, "start": 时钟}

func _ready() -> void:
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	_ping_clock += delta
	_ping_scan_timer -= delta
	if _ping_scan_timer <= 0.0:
		_ping_scan_timer = PING_SCAN_TICK
		_scan_tower_warnings()
	# 节流：无警告动画时每 3 帧重绘；有动画时每帧重绘保证收缩动画平滑（同主机）
	_redraw_counter += 1
	if not _active_pings.is_empty() or _redraw_counter >= 3:
		_redraw_counter = 0
		queue_redraw()

# —— 相机覆盖读取（NetClientBattle 每帧调用；消费后复位轻点）——
func take_gaze() -> Vector3:
	gaze_ready = false
	return gaze_world

func _gui_input(event: InputEvent) -> void:
	if not active:
		return   # 观战 / 第一人称下不拦截（桌面右键环视仍走 _unhandled_input）
	# 桌面端 emulate_touch_from_mouse 的合成触摸会让每次鼠标被处理两次，跳过（同主机 Minimap）
	if Input.is_emulating_touch_from_mouse() and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# 移动端 emulate_mouse_from_touch 的合成鼠标同理跳过
	if Input.is_emulating_mouse_from_touch() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var is_press := false
	var is_release := false
	var is_drag := false
	var local := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		local = mb.position
		is_press = mb.pressed
		is_release = not mb.pressed
	elif event is InputEventMouseMotion:
		local = (event as InputEventMouseMotion).position
		is_drag = true
	elif event is InputEventScreenTouch:
		local = (event as InputEventScreenTouch).position
		is_press = (event as InputEventScreenTouch).pressed
		is_release = not is_press
	elif event is InputEventScreenDrag:
		local = (event as InputEventScreenDrag).position
		is_drag = true

	if is_press:
		_mouse_down_pos = local
		_drag_started = false
		_is_dragging = false
		panning = false
		accept_event()
	elif is_release:
		if not _drag_started:
			# 轻点（未拖出阈值）：一次相机跳转（同主机 minimap_jump_requested 单点语义）
			var world := _local_to_world(local)
			if world != Vector3.ZERO:
				gaze_world = world
				gaze_ready = true
		else:
			_is_dragging = false
			panning = false   # 松手回正跟随英雄（同主机 minimap_dragging 结束）
		accept_event()
	elif is_drag:
		if _is_dragging:
			var world_pos := _local_to_world(local)
			if world_pos != Vector3.ZERO:
				panning = true
				pan_world = world_pos
			accept_event()
		elif not _drag_started and (local - _mouse_down_pos).length() > DRAG_THRESHOLD:
			_drag_started = true
			_is_dragging = true
			var world_pos := _local_to_world(local)
			if world_pos != Vector3.ZERO:
				panning = true
				pan_world = world_pos
			accept_event()

# —— 坐标系换算（同主机 Minimap._local_to_world / _world_to_minimap）——
func _local_to_world(local_pos: Vector2) -> Vector3:
	if local_pos.x < 0.0 or local_pos.x > MINIMAP_SIZE or local_pos.y < 0.0 or local_pos.y > MINIMAP_SIZE:
		return Vector3.ZERO
	return Vector3((local_pos.x / MINIMAP_SIZE - 0.5) * MAP_SIZE, 0.0, (local_pos.y / MINIMAP_SIZE - 0.5) * MAP_SIZE)

func _world_to_minimap(w: Vector3) -> Vector2:
	return Vector2((w.x + MAP_SIZE / 2.0) * MINIMAP_SIZE / MAP_SIZE, (w.z + MAP_SIZE / 2.0) * MINIMAP_SIZE / MAP_SIZE)

# —— 绘制 ——
func _draw() -> void:
	_ensure_terrain_texture()
	draw_texture_rect(_terrain_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)
	# 静态地图：草丛 / 墙体 / 血包点位（host 下发 payload.bushes/walls/packs）
	if not _static_done:
		_cache_static_map()
	for b in _static_bushes:
		MinimapDraw.draw_bush(self, b, 7.5)
	for w in _static_walls:
		MinimapDraw.draw_wall(self, w["p"], w["a"], 4.5, 2.8)
	for pk in _static_packs:
		MinimapDraw.draw_health_pack(self, pk, true)
	var ally_col := Color(0.0, 0.886, 1.0)
	var enemy_col := Color(1.0, 0.33, 0.264)
	var ally_ring_col := Color(0.30, 0.95, 0.42)   # 血量环固定色（同单机 Minimap.gd）
	var enemy_ring_col := Color(1.0, 0.28, 0.24)

	# —— 防御塔（外塔/内塔/高地/水晶 分级形状；血量底部填充）——
	for nid in views:
		var v: Dictionary = views[nid]
		if int(v.get("type", -1)) != NET_TURRET:
			continue
		var tpos := _world_to_minimap(_view_pos(v))
		var tcol := ally_col if int(v.get("team", 9)) == player_team else enemy_col
		var tratio := _hp_ratio(float(v.get("hp", 0.0)), float(v.get("maxhp", 1.0)))
		MinimapDraw.draw_turret(self, tpos, tratio, tcol, str(v.get("ttype", "outer")), float(v.get("hp", 0.0)) > 0.0)

	# —— 小兵：主宰先锋/风暴先锋 = 有翼龙形，攻城车/超级兵 = 菱形，其余聚类 ——
	var ally_dots: Array = []
	var enemy_dots: Array = []
	for nid2 in views:
		var v2: Dictionary = views[nid2]
		if int(v2.get("type", -1)) != NET_MINION:
			continue
		if float(v2.get("hp", 0.0)) <= 0.0:
			continue
		var mpos := _world_to_minimap(_view_pos(v2))
		var nm := str(v2.get("name", ""))
		var mcol := Color(0.0, 0.886, 1.0) if int(v2.get("team", 9)) == player_team else Color(1.0, 0.33, 0.264)
		if nm in ["dragon", "shadow_dragon", "storm"]:
			MinimapDraw.draw_dragon(self, mpos, mcol, nm)
		elif nm == "siege" or nm == "super":
			MinimapDraw.draw_elite_minion(self, mpos, mcol, nm)
		elif int(v2.get("team", 9)) == player_team:
			ally_dots.append(mpos)
		else:
			enemy_dots.append(mpos)
	MinimapDraw.draw_clusters(self, MinimapDraw.cluster(ally_dots, 3.0), Color(0.0, 0.886, 1.0, 0.9), 3.5)
	MinimapDraw.draw_clusters(self, MinimapDraw.cluster(enemy_dots, 3.0), Color(1.0, 0.33, 0.264, 0.9), 3.0)
	# —— 野怪：我方有视野的直接画；无视野营地按默认显示（压暗幽灵），确认复活中的隐藏 ——
	var live_jg: Array = []
	for nid3 in views:
		var v3: Dictionary = views[nid3]
		if int(v3.get("type", -1)) != NET_JUNGLE:
			continue
		if float(v3.get("hp", 0.0)) <= 0.0:
			continue
		var jpos := _world_to_minimap(_view_pos(v3))
		live_jg.append(jpos)
		MinimapDraw.draw_jungle(self, jpos, str(v3.get("name", "")), true)
	for cp in _static_camps:
		var covered := false
		for lj: Vector2 in live_jg:
			if lj.distance_to(cp) <= 3.0:
				covered = true
				break
		if covered:
			continue
		# 我方已确认在复活中 → 不显示
		var dead := false
		for d in jg:
			if d is Array and d.size() >= 2:
				if cp.distance_to(_world_to_minimap(Vector3(float(d[0]), 0.0, float(d[1])))) <= 4.0:
					dead = true
					break
		if dead:
			continue
		MinimapDraw.draw_jungle(self, cp, "", false)

	# —— 英雄（阵营色 + 朝向箭头 + 血量弧；本窗口玩家白边）——
	for nid4 in views:
		var v4: Dictionary = views[nid4]
		if int(v4.get("type", -1)) != NET_HERO:
			continue
		if float(v4.get("hp", 0.0)) <= 0.0:
			continue
		var hpos := _world_to_minimap(_view_pos(v4))
		var hcol := enemy_col if int(v4.get("team", 9)) == TEAM_ENEMY else ally_col
		var hpr := _hp_ratio(float(v4.get("hp", 0.0)), float(v4.get("maxhp", 1.0)))
		var rot := float(v4.get("rot", 0.0))
		# 血环颜色按阵营固定（我方绿 / 敌方红），与单机 Minimap.gd 完全一致
		var hring: Color = enemy_ring_col if int(v4.get("team", 9)) == TEAM_ENEMY else ally_ring_col
		MinimapDraw.draw_hero(self, hpos, Vector2(sin(rot), cos(rot)), hcol, hpr, nid4 == self_net, false, 0.0, str(v4.get("name", "")), hring)

	# —— 自己回城黄线 ——
	if own_recalling != 0 and own_pos != Vector3.ZERO:
		draw_line(_world_to_minimap(own_pos), _world_to_minimap(Vector3(-58.0, 0.0, 58.0)), Color.YELLOW, 2)

	# —— 摄像头视野框 ——
	MinimapDraw.draw_viewport(self, MinimapDraw.viewport_corners(get_viewport().get_camera_3d(), Callable(self, "_world_to_minimap")), false)

	# —— 视野迷雾（我方英雄/小兵/塔 + 泉水；未覆盖区域压暗）——
	MinimapDraw.draw_fog(self, MinimapDraw.fog_grid(_fog_sources(), MAP_SIZE), MINIMAP_SIZE)
	# —— 暴君/主宰 刷新倒计时 ——
	MinimapDraw.draw_objectives(self, _obj_entries(), MINIMAP_SIZE)
	# —— 我方防御塔被攻击警告圈（最上层）——
	_draw_tower_pings()
	_draw_frame()
## 小地图边框（同主机 Minimap._draw_frame）：外底座 + 2px 描边 + 内侧高光 + 四角金色角标
func _draw_frame() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE))
	# 只画描边环，不填充（填充会盖住地图内容）：2px 外暗环 + 1px 内高光线
	draw_style_box(UiKit.flat(0.0, 12, 2, Color(0.02, 0.03, 0.05, 0.95),
		Color(0, 0, 0, 0), 0.0, 0.0), r.grow(2.0))
	draw_style_box(UiKit.flat(0.0, 8, 1, Color(0.62, 0.74, 0.92, 0.55),
		Color(0, 0, 0, 0), 0.0, 0.0), r.grow(0.5))
	var L := minf(16.0, MINIMAP_SIZE * 0.10)
	var gc := Color(0.98, 0.82, 0.32, 0.95)
	for i in range(4):
		var cx: float = 0.0 if i % 2 == 0 else float(MINIMAP_SIZE)
		var cy: float = 0.0 if i < 2 else float(MINIMAP_SIZE)
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sy := 1.0 if i < 2 else -1.0
		draw_line(Vector2(cx + sx * 2.0, cy + sy * 2.0), Vector2(cx + sx * L, cy + sy * 2.0), gc, 3.0)
		draw_line(Vector2(cx + sx * 2.0, cy + sy * 2.0), Vector2(cx + sx * 2.0, cy + sy * L), gc, 3.0)

func _view_pos(v: Dictionary) -> Vector3:
	if v.has("node") and v["node"] != null:
		var n: Node3D = v["node"]
		return n.global_position
	return Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0)))

func _hp_ratio(hp: float, mhp: float) -> float:
	if mhp <= 0.0:
		return 0.0
	return clampf(hp / mhp, 0.0, 1.0)

# —— 我方塔被攻击警告（同主机 Minimap._scan_tower_warnings）——
func _scan_tower_warnings() -> void:
	var alive := {}
	for nid in views:
		var v: Dictionary = views[nid]
		if int(v.get("type", -1)) != NET_TURRET:
			continue
		if int(v.get("team", 9)) != player_team or float(v.get("hp", 0.0)) <= 0.0:
			continue
		if not bool(v.get("under_attack", false)):
			continue
		alive[nid] = true
		var last: float = float(_tower_ping_time.get(nid, -PING_COOLDOWN))
		if _ping_clock - last >= PING_COOLDOWN:
			_tower_ping_time[nid] = _ping_clock
			_active_pings[nid] = {"pos": _world_to_minimap(_view_pos(v)), "start": _ping_clock}
	for id in _tower_ping_time.keys():
		if not alive.has(id):
			_tower_ping_time.erase(id)

func _draw_tower_pings() -> void:
	if _active_pings.is_empty():
		return
	var now := _ping_clock
	var done := []
	for key in _active_pings.keys():
		var p: Dictionary = _active_pings[key]
		var age := now - float(p["start"])
		if age >= PING_DURATION:
			done.append(key)
			continue
		_draw_ping_effect(p["pos"], age)
	for key in done:
		_active_pings.erase(key)

func _draw_ping_effect(pos: Vector2, age: float) -> void:
	var t := clampf(age / PING_DURATION, 0.0, 1.0)
	var big_r := clampf(MINIMAP_SIZE * 0.11, 14.0, 32.0)
	var cyc_t := t * float(PING_CYCLES)
	var frac: float = cyc_t - floor(cyc_t)
	var r := lerpf(big_r, 2.0, frac)
	var alpha: float = 1.0 - 0.9 * frac
	if t > 0.72:
		alpha *= clampf((1.0 - t) / 0.28, 0.0, 1.0)
	alpha = clampf(alpha, 0.0, 1.0)
	var col := Color(1.0, 0.82, 0.12, alpha)
	draw_circle(pos, r, Color(1.0, 0.82, 0.12, alpha * 0.15))
	draw_arc(pos, r, 0.0, TAU, 48, col, 3.0)

# —— 一次性地形底图（300×300 采样 120×120 网格，同主机 _ensure_terrain_texture）——
func _ensure_terrain_texture() -> void:
	if _terrain_texture:
		return
	# 共享地形底图（与主机 Minimap 同源）
	_terrain_texture = MinimapDraw.terrain_texture(320, MAP_SIZE)


func _get_minimap_terrain(wx: float, wz: float) -> int:
	var dist_to_diag := absf(wx - wz) / sqrt(2.0)
	if dist_to_diag <= 10.0:
		return 2
	var lane_farm_dist := absf(absf(wx) - 55.0)
	var lane_mid_dist := absf(wz + wx) / sqrt(2.0)
	var lane_clash_dist := absf(absf(wz) - 55.0)
	if lane_farm_dist <= 8.0 or lane_mid_dist <= 8.0 or lane_clash_dist <= 8.0:
		return 1
	return 0

# ---------- 视野迷雾 / 目标计时（与主机同源数据形状） ----------
func _fog_sources() -> Array:
	var out: Array = []
	for nid in views:
		var v: Dictionary = views[nid]
		var typ := int(v.get("type", -1))
		if typ == NET_JUNGLE:
			continue
		if int(v.get("team", 9)) != player_team:
			continue
		if float(v.get("hp", 0.0)) <= 0.0:
			continue
		var r := 16.0
		if typ == NET_MINION:
			r = 9.0
		elif typ == NET_TURRET:
			r = 18.0
		out.append({"p": _view_pos(v), "r": r})
	out.append({"p": Vector3(-58.0, 0.0, 58.0), "r": 24.0})
	return out

func _obj_entries() -> Array:
	if obj.size() < 4:
		return []
	return [
		{"label": "暴君", "t": float(obj[0]), "alive": int(obj[1]) != 0, "color": Color(0.95, 0.6, 0.35)},
		{"label": "主宰", "t": float(obj[2]), "alive": int(obj[3]) != 0, "color": Color(0.55, 0.8, 1.0)},
	]
# ---------- 静态地图缓存（草丛/墙体/血包，来自 host 地图 payload） ----------
func _cache_static_map() -> void:
	_static_done = true
	var payload: Dictionary = NetSession.get_map_payload()
	if payload.is_empty():
		_static_done = false
		return
	for b in payload.get("bushes", []):
		if b.size() >= 2:
			_static_bushes.append(_world_to_minimap(Vector3(float(b[0]), 0.0, float(b[1]))))
	for w in payload.get("walls", []):
		if w.size() >= 3:
			var th := float(w[2])
			_static_walls.append({"p": _world_to_minimap(Vector3(float(w[0]), 0.0, float(w[1]))), "a": atan2(cos(th), sin(th))})
	for c in payload.get("camps", []):
		if c.size() >= 2:
			_static_camps.append(_world_to_minimap(Vector3(float(c[0]), 0.0, float(c[1]))))
	for pk in payload.get("packs", []):
		if pk.size() >= 2:
			_static_packs.append(_world_to_minimap(Vector3(float(pk[0]), 0.0, float(pk[1]))))