class_name Minimap
extends Control

const MAP_SIZE = 120
const MinimapDraw = preload("res://scripts/ui/MinimapDraw.gd")
# 移动端由 BattleManager 在加入场景前放大为 300（1.5 倍）；默认桌面 200
var MINIMAP_SIZE := 200
const DRAG_THRESHOLD = 5.0
# —— 我方防御塔被攻击警告（小地图黄色收缩圈）——
const PING_COOLDOWN := 10.0   # 每座塔两次警告的最短间隔（秒）
const PING_DURATION := 1.35   # 单次警告动画总时长（秒）
const PING_CYCLES := 3        # 黄色警告圈收缩重复次数
const PING_SCAN_TICK := 0.1   # 扫描"塔正在被攻击"状态的间隔（秒）

var minions: Array = []
var jungle_monsters: Array = []

var heroes: Array = []
var turrets: Array = []
var player_team: int = 0

var is_dragging: bool = false
var drag_started: bool = false
var mouse_down_pos: Vector2 = Vector2.ZERO
var battle: BattleManager = null

# 传送模式
var is_teleport_mode: bool = false
var summoner_teleport: bool = false
var original_position: Vector2
var original_scale: Vector2
var original_size: Vector2

# 性能优化：地形底图预渲染为纹理，避免每帧 14400 次 draw_rect
var _terrain_texture: ImageTexture = null
var _static_bushes: Array = []      # 草丛小地图坐标（一次性缓存）
var _static_walls: Array = []       # 墙体 [{p, a}]
# 性能优化：草丛/墙体一次性烘焙成一张透明贴图，替代每帧约 3000 次 draw_* 调用
var _static_overlay_texture: ImageTexture = null
# queue_redraw 节流计数器（每 3 帧重绘一次）
var _redraw_counter: int = 0
# 我方塔被攻击警告状态（用于限频与动画）
var _ping_clock := 0.0            # 本地时钟（秒）
var _ping_scan_timer := 0.0       # 距下次扫描的倒计时
var _tower_ping_time := {}        # 塔 instance_id -> 上次警告时的时钟（10s 限频）
var _active_pings := {}           # 塔 instance_id -> {"pos": Vector2, "start": 时钟}
# 野怪记忆：默认显示，只有「我方有视野时确认死亡」才按复活时间隐藏
var _jg_clock := 0.0              # 本地时钟（秒）
var _jg_seen: Dictionary = {}     # 野怪 instance_id -> 最后一次我方有视野的时钟
var _jg_dead: Dictionary = {}     # 野怪 instance_id -> 我方确认死亡后的复活完成时钟

func _ready():
	self_modulate = Color.WHITE
	original_position = position
	original_scale = scale
	original_size = size

func set_battle(bm: BattleManager):
	battle = bm

func _process(delta):
	if is_teleport_mode:
		if summoner_teleport:
			pass  # 召唤师传送不检查传送阵
		elif battle and battle.hero and not battle.hero.is_dead:
			var zone = battle._get_teleport_zone_for_hero(battle.hero)
			if not zone:
				exit_teleport_mode()
		else:
			exit_teleport_mode()
	# 我方塔被攻击警告：推进本地时钟 + 低频扫描触发警告圈
	_ping_clock += delta
	_ping_scan_timer -= delta
	if _ping_scan_timer <= 0.0:
		_ping_scan_timer = PING_SCAN_TICK
		_scan_tower_warnings()
	_update_jungle_memory(delta)
	# 节流：无警告动画时每 3 帧重绘；有动画时每帧重绘，保证收缩动画平滑
	_redraw_counter += 1
	if not _active_pings.is_empty() or _redraw_counter >= 3:
		_redraw_counter = 0
		queue_redraw()

func _gui_input(event):
	# 移动端 emulate_mouse_from_touch 的合成鼠标事件会让每次触摸被处理两次，跳过
	if Input.is_emulating_mouse_from_touch() and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	# 桌面端 emulate_touch_from_mouse 的合成触摸事件会让每次鼠标点击被处理两次，跳过
	if Input.is_emulating_touch_from_mouse() and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	# 统一提取事件类型（鼠标/触摸等价处理）
	var is_press := false
	var is_release := false
	var is_drag := false
	var local := Vector2.ZERO
	if event is InputEventScreenTouch:
		local = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			local = event.position
			is_press = event.pressed
			is_release = not event.pressed
	elif event is InputEventScreenDrag:
		local = event.position
		is_drag = true
	elif event is InputEventMouseMotion:
		local = event.position
		is_drag = true

	if is_teleport_mode:
		# 传送模式：只检测传送目标点击
		if is_press:
			var clicked_entity = _get_entity_at_minimap(local)
			if clicked_entity and battle and clicked_entity.team == battle.hero.team:
				battle.request_teleport(battle.hero, clicked_entity)
				exit_teleport_mode()
		accept_event()
		return  # 屏蔽所有其他输入

	if is_press:
		mouse_down_pos = local
		drag_started = false
		is_dragging = false
		accept_event()
	elif is_release:
		if not drag_started:
			var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if bm and bm.hero and not bm.hero.is_dead:
				var zone = bm._get_teleport_zone_for_hero(bm.hero)
				if zone:
					enter_teleport_mode()
					accept_event()
					return
			# 正常跳转
			var world = _local_to_world(local)
			if world != Vector3.ZERO and bm:
				bm.minimap_drag_pos = world
				bm.minimap_jump_requested = true
		else:
			is_dragging = false
			if battle:
				battle.minimap_dragging = false
		accept_event()
	elif is_drag:
		if is_dragging:
			var world_pos = _local_to_world(local)
			if world_pos != Vector3.ZERO and battle:
				battle.minimap_drag_pos = world_pos
				battle.minimap_dragging = true
			accept_event()
		elif (event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or event is InputEventScreenDrag:
			if not drag_started and (local - mouse_down_pos).length() > DRAG_THRESHOLD:
				drag_started = true
				is_dragging = true
				var world_pos = _local_to_world(local)
				if world_pos != Vector3.ZERO and battle:
					battle.minimap_drag_pos = world_pos
					battle.minimap_dragging = true
				accept_event()

func enter_teleport_mode():
	if is_teleport_mode: return
	is_teleport_mode = true
	original_position = position
	original_scale = scale
	original_size = size
	scale = Vector2(2, 2)
	position = (get_viewport().get_visible_rect().size - size * scale) / 2

func exit_teleport_mode():
	summoner_teleport = false
	is_teleport_mode = false
	position = original_position
	scale = original_scale
	size = original_size

func _get_entity_at_minimap(local_pos: Vector2) -> GameEntity:
	
	var world_x = (local_pos.x / MINIMAP_SIZE - 0.5) * MAP_SIZE
	var world_z = (local_pos.y / MINIMAP_SIZE - 0.5) * MAP_SIZE
	var world_pos = Vector3(world_x, 0, world_z)
	
	var best_entity: GameEntity = null
	var best_dist: float = 5.0
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.team == battle.hero.team and entity.health > 0:
			var dist = entity.global_position.distance_to(world_pos)
			if dist < best_dist:
				best_dist = dist
				best_entity = entity
	if best_entity: return best_entity
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Turret and entity.team == battle.hero.team and entity.health > 0:
			var dist = entity.global_position.distance_to(world_pos)
			if dist < best_dist:
				best_dist = dist
				best_entity = entity
	if best_entity: return best_entity
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Minion and entity.team == battle.hero.team and entity.health > 0:
			var dist = entity.global_position.distance_to(world_pos)
			if dist < best_dist:
				best_dist = dist
				best_entity = entity
	return best_entity

func _local_to_world(local_pos: Vector2) -> Vector3:
	if local_pos.x < 0 or local_pos.x > MINIMAP_SIZE or local_pos.y < 0 or local_pos.y > MINIMAP_SIZE:
		return Vector3.ZERO
	return Vector3((local_pos.x / MINIMAP_SIZE - 0.5) * MAP_SIZE, 0, (local_pos.y / MINIMAP_SIZE - 0.5) * MAP_SIZE)

func add_teleport_line(from: Vector3, to: Vector3):
	# 由 BattleManager 调用，这里不再需要单独存储
	pass

# 原有 _draw 及其他代码保持不变...

	
func _draw():
	# 预渲染地形底图（一次性生成，见 _ensure_terrain_texture）
	_ensure_terrain_texture()
	draw_texture_rect(_terrain_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)

	# ---- 草丛 / 墙体（静态地形装饰：压在地形上、单位下）----
	# 已预烘焙为一张透明贴图（见 _bake_static_overlay），每帧仅 1 次绘制
	if _static_overlay_texture == null:
		_cache_static_map()
		if not _static_walls.is_empty():
			_static_overlay_texture = _bake_static_overlay()
	if _static_overlay_texture != null:
		draw_texture_rect(_static_overlay_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)

	# ---- 防御塔（外塔方 / 内塔带框 / 高地菱形 / 水晶六边形；血量底部填充；摧毁灰 X） ----
	for t in turrets:
		if not is_instance_valid(t): continue
		var pos := _world_to_minimap(t.global_position)
		var color := Color(0.0, 0.886, 1.0) if t.team == player_team else Color(1.0, 0.33, 0.264)
		var ratio := clampf(t.health / maxf(t.max_health, 1.0), 0.0, 1.0)
		MinimapDraw.draw_turret(self, pos, ratio, color, str(t.tower_type), t.health > 0.0)

	# ---- 小兵：主宰先锋/风暴先锋 = 有翼龙形，攻城车/超级兵 = 菱形，其余聚类成簇 ----
	var ally_dots: Array = []
	var enemy_dots: Array = []
	for m in minions:
		if not is_instance_valid(m): continue
		if m.team != player_team and not m.visible: continue
		var pos := _world_to_minimap(m.global_position)
		var nm := str(m.display_name)
		var mcol := Color(0.0, 0.886, 1.0) if m.team == player_team else Color(1.0, 0.33, 0.264)
		if nm in ["dragon", "shadow_dragon", "storm"]:
			MinimapDraw.draw_dragon(self, pos, mcol, nm)
		elif nm == "siege" or nm == "super":
			MinimapDraw.draw_elite_minion(self, pos, mcol, nm)
		elif m.team == player_team:
			ally_dots.append(pos)
		else:
			enemy_dots.append(pos)
	MinimapDraw.draw_clusters(self, MinimapDraw.cluster(ally_dots, 3.0), Color(0.0, 0.886, 1.0, 0.9), 3.5)
	MinimapDraw.draw_clusters(self, MinimapDraw.cluster(enemy_dots, 3.0), Color(1.0, 0.33, 0.264, 0.9), 3.0)
	# ---- 野怪：默认显示（无视野压暗）；确认击杀后按复活时间隐藏 ----
	for j in jungle_monsters:
		if not is_instance_valid(j): continue
		var jid: int = j.get_instance_id()
		if _jg_dead.has(jid) and _jg_clock < float(_jg_dead[jid]):
			continue
		var jpos := _world_to_minimap(j.global_position)
		var jname := str(j.display_name)
		var seen: bool = j.visible and float(_jg_seen.get(jid, -9999.0)) >= _jg_clock - 0.5
		MinimapDraw.draw_jungle(self, jpos, jname, seen)

	# ---- 英雄（阵营色 + 朝向箭头 + 血量弧；本人白边；阵亡灰点 + 复活倒计时） ----
	for h in heroes:
		if not is_instance_valid(h): continue
		if h.team != player_team and not h.visible and h.health > 0.0: continue
		var pos := _world_to_minimap(h.global_position)
		var base_col := Color(0.0, 0.886, 1.0) if h.team == player_team else Color(1.0, 0.33, 0.264)
		var hp_ratio := clampf(h.health / maxf(h.max_health, 1.0), 0.0, 1.0)
		var dir := Vector2(sin(h.rotation.y), cos(h.rotation.y))
		if h.velocity.length() > 0.2:
			dir = Vector2(h.velocity.x, h.velocity.z)
		MinimapDraw.draw_hero(self, pos, dir, base_col, hp_ratio, not h.is_ai, h.health <= 0.0, float(h.respawn_timer), str(h.display_name))

	# 血包：可用=绿光十字，已拿走=灰色空心环
	for p2 in get_tree().get_nodes_in_group("health_packs"):
		if p2 is HealthPack and p2.team == player_team:
			MinimapDraw.draw_health_pack(self, _world_to_minimap(p2.global_position), p2.available)

	# 绘制传送/回城连线
	if battle:
		for line in battle.teleport_lines:
			draw_line(_world_to_minimap(line["from"]), _world_to_minimap(line["to"]), Color.CYAN, 2)
		for line in battle.recall_lines.values():
			draw_line(_world_to_minimap(line["hero_pos"]), _world_to_minimap(line["spring_pos"]), Color.YELLOW, 2)

	# 摄像头视野框（拖拽/传送模式画虚线）：小地图最重要的定位反馈
	MinimapDraw.draw_viewport(self, MinimapDraw.viewport_corners(get_viewport().get_camera_3d(), Callable(self, "_world_to_minimap")), is_teleport_mode)

	# 视野迷雾（我方英雄/小兵/塔 + 泉水点亮；未覆盖区域压暗）
	MinimapDraw.draw_fog(self, MinimapDraw.fog_grid(_fog_sources(), MAP_SIZE), MINIMAP_SIZE)
	# 暴君 / 主宰 刷新倒计时
	MinimapDraw.draw_objectives(self, _objective_entries(), MINIMAP_SIZE)
	# ---- 我方防御塔被攻击警告圈（绘制在最上层） ----
	_draw_tower_pings()
	_draw_frame()
## 小地图边框：深色圆角底 + 双层描边（外暗内亮）+ 四角金色角标，压住底图边缘锯齿
func _draw_frame() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE))
	# 外框阴影/底座（略微外扩，避免遮住内部地图）
	draw_style_box(UiKit.flat(0.0, 12, 2, Color(0.02, 0.03, 0.05, 0.95),
		Color(0, 0, 0, 0), 0.0, 0.0), r.grow(2.0))
	draw_style_box(UiKit.flat(0.0, 8, 1, Color(0.62, 0.74, 0.92, 0.55),
		Color(0, 0, 0, 0), 0.0, 0.0), r.grow(0.5))
	# 四角金色角标（L 形，长度 16，宽 3）
	var L := minf(16.0, MINIMAP_SIZE * 0.10)
	var gc := Color(0.98, 0.82, 0.32, 0.95)
	for i in range(4):
		var cx: float = 0.0 if i % 2 == 0 else float(MINIMAP_SIZE)
		var cy: float = 0.0 if i < 2 else float(MINIMAP_SIZE)
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sy := 1.0 if i < 2 else -1.0
		draw_line(Vector2(cx + sx * 2.0, cy + sy * 2.0), Vector2(cx + sx * L, cy + sy * 2.0), gc, 3.0)
		draw_line(Vector2(cx + sx * 2.0, cy + sy * 2.0), Vector2(cx + sx * 2.0, cy + sy * L), gc, 3.0)

# 扫描我方塔：正在被攻击（塔的 under_attack_timer > 0）且距上次警告≥10s → 触发一次警告
func _scan_tower_warnings():
	var alive := {}
	for t in turrets:
		if not is_instance_valid(t) or t.team != player_team or t.health <= 0.0:
			continue
		var id: int = t.get_instance_id()
		alive[id] = true
		if t.under_attack_timer <= 0.0:
			continue
		var last: float = float(_tower_ping_time.get(id, -PING_COOLDOWN))
		if _ping_clock - last >= PING_COOLDOWN:
			_tower_ping_time[id] = _ping_clock
			_active_pings[id] = {"pos": _world_to_minimap(t.global_position), "start": _ping_clock}
	# 清理已消失塔的限频记录（正在播放的警告圈由绘制侧按时长过期）
	for id in _tower_ping_time.keys():
		if not alive.has(id):
			_tower_ping_time.erase(id)

# 绘制所有活动警告圈；坐标取触发瞬间的快照，塔被打掉/消失也能播完动画
func _draw_tower_pings():
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
		var ppos: Vector2 = p["pos"]
		_draw_ping_effect(ppos, age)
	for key in done:
		_active_pings.erase(key)

# 单个警告圈：半径从大缩到小，重复 PING_CYCLES 次，末段整体渐隐
func _draw_ping_effect(pos: Vector2, age: float):
	var t := clampf(age / PING_DURATION, 0.0, 1.0)
	var big_r := clampf(MINIMAP_SIZE * 0.11, 14.0, 32.0)
	var cyc_t := t * float(PING_CYCLES)
	var frac: float = cyc_t - floor(cyc_t)
	var r := lerpf(big_r, 2.0, frac)
	var alpha: float = 1.0 - 0.9 * frac          # 每圈收尾时淡一点
	if t > 0.72:                            # 最后一次收圈后整体淡出
		alpha *= clampf((1.0 - t) / 0.28, 0.0, 1.0)
	alpha = clampf(alpha, 0.0, 1.0)
	var col := Color(1.0, 0.82, 0.12, alpha)
	draw_circle(pos, r, Color(1.0, 0.82, 0.12, alpha * 0.15))  # 淡色内填充，弱化遮挡
	draw_arc(pos, r, 0, TAU, 48, col, 3.0)

# 一次性把 120×120 地形网格渲染成 200×200 像素的纹理（每像素取所在网格的底色）
func _ensure_terrain_texture():
	if _terrain_texture:
		return
	# 共享地形底图：120 网格取色 + 双线性放大 + 交界描边 + 暗角（host/client 同源）
	_terrain_texture = MinimapDraw.terrain_texture(256, MAP_SIZE)


func _world_to_minimap(world_pos: Vector3) -> Vector2:
	var gx = world_pos.x + MAP_SIZE / 2.0
	var gy = world_pos.z + MAP_SIZE / 2.0
	return Vector2(gx * MINIMAP_SIZE / MAP_SIZE, gy * MINIMAP_SIZE / MAP_SIZE)
func _get_minimap_terrain(wx: float, wz: float) -> int:
	# 河道判定（对角线宽度20）
	var dist_to_diag = abs(wx - wz) / sqrt(2.0)
	if dist_to_diag <= 10.0:
		return 2

	# 分路判定（简化：在发育路/中路/对抗路矩形条带内）
	# 发育路：大致 y = x + 10 附近，宽15
	var lane_farm_dist = abs(abs(wx)-55)
	var lane_mid_dist = abs(wz + wx) / sqrt(2.0)
	var lane_clash_dist = abs(abs(wz )-55)
	if lane_farm_dist <= 8 or lane_mid_dist <= 8 or lane_clash_dist <= 8:
		
		return 1
	else:
		return 0

# ---------- 视野迷雾 / 目标计时数据 ----------
func _fog_sources() -> Array:
	var out: Array = []
	for h in heroes:
		if is_instance_valid(h) and h.team == player_team and h.health > 0.0:
			out.append({"p": h.global_position, "r": 16.0})
	for m in minions:
		if is_instance_valid(m) and m.team == player_team and m.health > 0.0:
			out.append({"p": m.global_position, "r": 9.0})
	for t in turrets:
		if is_instance_valid(t) and t.team == player_team and t.health > 0.0:
			out.append({"p": t.global_position, "r": 18.0})
	out.append({"p": Vector3(-58.0, 0.0, 58.0), "r": 24.0})
	out.append({"p": Vector3(-53.0, 0.0, 53.0), "r": 18.0})
	return out

func _objective_entries() -> Array:
	if battle == null:
		return []
	return [
		{"label": "暴君", "t": battle.tyrant_timer, "alive": battle.tyrant_alive, "color": Color(0.95, 0.6, 0.35)},
		{"label": "主宰", "t": battle.dragon_timer, "alive": battle.dragon_alive, "color": Color(0.55, 0.8, 1.0)},
	]
# ---------- 静态地图（草丛 / 墙体）缓存：小地图坐标为像素空间 ----------
func _cache_static_map() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	if not _static_bushes.is_empty():
		return
	var bp: Variant = battle.get("_bush_positions")
	if bp is Array:
		for p in bp:
			_static_bushes.append(_world_to_minimap(p))
	_static_walls.clear()
	for w in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(w):
			continue
		var th: float = w.rotation.y
		# 墙体长轴 = 容器前向（+Z 经 yaw 旋转）→ 小地图方向角
		_static_walls.append({"p": _world_to_minimap(w.global_position), "a": atan2(cos(th), sin(th))})

# 把草丛/墙体一次性画进透明 Image 纹理（小地图像素空间），之后每帧只贴这张图
func _bake_static_overlay() -> ImageTexture:
	var px := int(MINIMAP_SIZE)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bush_r: float = 3.0 * MINIMAP_SIZE / MAP_SIZE
	for b in _static_bushes:
		_paint_disc(img, b, bush_r * 1.5, Color(0.28, 0.62, 0.32, 0.16))
		_paint_disc(img, b, bush_r, Color(0.10, 0.30, 0.16, 0.85))
	var wl: float = 1.8 * MINIMAP_SIZE / MAP_SIZE
	var wt: float = 1.1 * MINIMAP_SIZE / MAP_SIZE
	for w in _static_walls:
		_paint_wall_quad(img, w["p"] + Vector2(1.4, 1.6), w["a"], wl, wt, Color(0, 0, 0, 0.35))
		_paint_wall_quad(img, w["p"], w["a"], wl, wt, Color(0.20, 0.21, 0.24, 0.95))
	return ImageTexture.create_from_image(img)

func _paint_disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var r2 := r * r
	var x0 := int(floor(c.x - r))
	var x1 := int(ceil(c.x + r))
	var y0 := int(floor(c.y - r))
	var y1 := int(ceil(c.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) + 0.5 - c.x
			var dy := float(y) + 0.5 - c.y
			if dx * dx + dy * dy <= r2:
				_blend_pixel(img, x, y, col)

func _paint_wall_quad(img: Image, pos: Vector2, ang: float, length: float, thick: float, col: Color) -> void:
	var d := Vector2(cos(ang), sin(ang))
	var p := Vector2(-d.y, d.x)
	var hl := length * 0.5
	var ht := thick * 0.5
	var steps := int(maxf(ceil(length * 3.0), 2.0))
	for i in range(steps + 1):
		var base := pos + d * (-hl + length * float(i) / float(steps))
		for j in range(4):
			var off := -ht + thick * float(j) / 3.0
			_blend_pixel(img, int(round(base.x + p.x * off)), int(round(base.y + p.y * off)), col)

func _blend_pixel(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var dst := img.get_pixel(x, y)
	if dst.a <= 0.001:
		img.set_pixel(x, y, col)
		return
	var a := col.a
	var out_a := a + dst.a * (1.0 - a)
	if out_a <= 0.001:
		return
	img.set_pixel(x, y, Color(
		(col.r * a + dst.r * dst.a * (1.0 - a)) / out_a,
		(col.g * a + dst.g * dst.a * (1.0 - a)) / out_a,
		(col.b * a + dst.b * dst.a * (1.0 - a)) / out_a,
		out_a))
# ---------- 野怪记忆（默认显示 / 只有确认死亡才按复活时间隐藏） ----------
func _has_vision_of(pos: Vector3) -> bool:
	for h in heroes:
		if is_instance_valid(h) and h.team == player_team and h.health > 0.0:
			if Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z).length() <= 18.0:
				return true
	for m in minions:
		if is_instance_valid(m) and m.team == player_team and m.health > 0.0:
			if Vector2(m.global_position.x - pos.x, m.global_position.z - pos.z).length() <= 9.0:
				return true
	for t in turrets:
		if is_instance_valid(t) and t.team == player_team and t.health > 0.0:
			if Vector2(t.global_position.x - pos.x, t.global_position.z - pos.z).length() <= 16.0:
				return true
	return false

func _update_jungle_memory(delta: float) -> void:
	_jg_clock += delta
	for j in jungle_monsters:
		if not is_instance_valid(j):
			continue
		var jid: int = j.get_instance_id()
		var alive: bool = j.visible and j.health > 0.0
		if alive:
			if _has_vision_of(j.global_position):
				_jg_seen[jid] = _jg_clock
			_jg_dead.erase(jid)   # 已复活 → 清死亡记忆
			continue
		# 死亡中：死亡前后 1.5s 内我方看见过 → 记住复活时间
		if not _jg_dead.has(jid) and float(_jg_seen.get(jid, -9999.0)) >= _jg_clock - 1.5:
			_jg_dead[jid] = _jg_clock + maxf(float(j.get("respawn_time")), 1.0)
	# 过期记忆清理（节点已被释放的情况）
	for key in _jg_dead.keys():
		if _jg_clock >= float(_jg_dead[key]) + 5.0:
			_jg_dead.erase(key)

## 联机：我方「已确认在复活中」的野怪点位（客户端据此画幽灵/隐藏）
func jg_dead_list() -> Array:
	var out: Array = []
	for j in jungle_monsters:
		if not is_instance_valid(j):
			continue
		var jid: int = j.get_instance_id()
		if _jg_dead.has(jid) and _jg_clock < float(_jg_dead[jid]):
			out.append([j.global_position.x, j.global_position.z])
	return out
