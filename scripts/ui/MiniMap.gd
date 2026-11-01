class_name Minimap
extends Control

const MAP_SIZE = 120
const MinimapDraw = preload("res://scripts/ui/MinimapDraw.gd")
# 移动端由 BattleManager 在加入场景前放大为 300（1.5 倍）；默认桌面 200
var MINIMAP_SIZE := 200
const DRAG_THRESHOLD = 5.0
# —— 我方防御塔被攻击警告（小地图黄色收缩圈；高地塔/水晶用红色警示圈，更久更大）——
const PING_COOLDOWN := 10.0   # 每座塔两次警告的最短间隔（秒）
const PING_DURATION := 1.35   # 单次警告动画总时长（秒）
const PING_CYCLES := 3        # 黄色警告圈收缩重复次数
const PING_SCAN_TICK := 0.1   # 扫描"塔正在被攻击"状态的间隔（秒）
# 高地塔 / 水晶：红色警报，持续时间更长、收缩圈更大、重复更多
const PING_COOLDOWN_HQ := 6.0
const PING_DURATION_HQ := 2.8
const PING_CYCLES_HQ := 5

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

# 轻点小地图放大查看：再点一次（或放大态点地图任意处）跳转并收起
var zoomed: bool = false
var _zoom_pos := Vector2.ZERO
var _zoom_scale := Vector2.ONE
var _zoom_z := 0

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
	# 传送已经真正开始（召唤师传送/传送阵）：立即退出放大的选点模式，
	# 不等传送动画结束；否则小地图会一直停在放大状态。
	if battle and battle.hero and (battle.hero.is_teleporting or battle.hero.dayu_teleport_channeling):
		if is_teleport_mode:
			exit_teleport_mode()
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
			if zoomed:
				# 放大态轻点：相机跳转到点击处，同时收起小地图
				var wz = _local_to_world(local)
				if wz != Vector3.ZERO and bm:
					bm.minimap_drag_pos = wz
					bm.minimap_jump_requested = true
				exit_zoom()
			elif bm and bm.hero and not bm.hero.is_dead and bm._get_teleport_zone_for_hero(bm.hero):
				enter_teleport_mode()
			else:
				# 常态轻点：小地图放大 2 倍查看（拖动仍是平移取景）
				enter_zoom()
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
	exit_zoom()
	is_teleport_mode = true
	original_position = position
	original_scale = scale
	original_size = size
	scale = Vector2(2, 2)
	position = (get_viewport().get_visible_rect().size - size * scale) / 2

func exit_teleport_mode():
	summoner_teleport = false
	if not is_teleport_mode:
		return
	is_teleport_mode = false
	position = original_position
	scale = original_scale
	size = original_size

# 轻点小地图：原地放大 2 倍到屏幕中央（同传送模式的缩放做法）
func enter_zoom():
	if zoomed or is_teleport_mode: return
	zoomed = true
	_zoom_pos = position
	_zoom_scale = scale
	_zoom_z = z_index
	var vp := get_viewport().get_visible_rect().size
	scale = Vector2(2.0, 2.0)
	position = (vp - size * scale) * 0.5
	z_index = _zoom_z + 20   # 放大时盖住同层 HUD 元素（收起时还原）
	queue_redraw()

func exit_zoom():
	if not zoomed: return
	zoomed = false
	position = _zoom_pos
	scale = _zoom_scale
	z_index = _zoom_z
	queue_redraw()

func _get_entity_at_minimap(local_pos: Vector2) -> GameEntity:
	if _flip180():
		local_pos = Vector2(MINIMAP_SIZE - local_pos.x, MINIMAP_SIZE - local_pos.y)
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
	if _flip180():
		local_pos = Vector2(MINIMAP_SIZE - local_pos.x, MINIMAP_SIZE - local_pos.y)
	return Vector3((local_pos.x / MINIMAP_SIZE - 0.5) * MAP_SIZE, 0, (local_pos.y / MINIMAP_SIZE - 0.5) * MAP_SIZE)

func add_teleport_line(from: Vector3, to: Vector3):
	# 由 BattleManager 调用，这里不再需要单独存储
	pass

# 原有 _draw 及其他代码保持不变...

	
func _draw():
	# 预渲染地形底图（一次性生成，见 _ensure_terrain_texture）
	_ensure_terrain_texture()
	if _flip180():
		# 红方：底图要原地旋转 180°。不能再用负尺寸 Rect2 画——本引擎会把整张图
		# 画到 (MINIMAP_SIZE, MINIMAP_SIZE) 处并旋转，看起来就是"小地图底板错位"到右下角。
		draw_set_transform(Vector2(MINIMAP_SIZE, MINIMAP_SIZE), PI, Vector2.ONE)
		draw_texture_rect(_terrain_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(_terrain_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)

	# ---- 草丛 / 墙体（静态地形装饰：压在地形上、单位下）----
	# 已预烘焙为一张透明贴图（见 _bake_static_overlay），每帧仅 1 次绘制
	if _static_overlay_texture == null:
		_cache_static_map()
		if not _static_walls.is_empty():
			_static_overlay_texture = _bake_static_overlay()
	if _static_overlay_texture != null:
		draw_texture_rect(_static_overlay_texture, Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE)), false)

	# ---- 我方视野之灵：20 米视野圈 + 青色灵体标记 ----
	for s in get_tree().get_nodes_in_group("vision_spirits"):
		if not is_instance_valid(s) or s.team != player_team:
			continue
		var spos := _world_to_minimap(s.global_position)
		var range_px := 20.0 / float(MAP_SIZE) * MINIMAP_SIZE
		MinimapDraw.draw_vision_spirit(self, spos, range_px, s.vision_active)

	# ---- 大禹的鼎：图标常显；我方鼎另画 8 米视野圈（与战场战争迷雾口径一致） ----
	for tr in get_tree().get_nodes_in_group("tripods"):
		if not is_instance_valid(tr) or not (tr is Tripod):
			continue
		var tpos := _world_to_minimap(tr.global_position)
		var tcol: Color = Color(0.0, 0.886, 1.0) if tr.team == player_team else Color(1.0, 0.33, 0.264)
		if tr.team == player_team and tr.health > 0.0:
			var vr := 8.0 / float(MAP_SIZE) * MINIMAP_SIZE
			draw_circle(tpos, vr, Color(tcol.r, tcol.g, tcol.b, 0.10))
			draw_arc(tpos, vr, 0.0, TAU, 44, Color(tcol.r, tcol.g, tcol.b, 0.42), 1.2, true)
		MinimapDraw.draw_tripod(self, tpos, tcol, bool(tr.heal_ready))

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
	# 红蓝 buff：只在复活前 30 秒开始读秒（且"上一次死亡时我方有视野"才会记进 _jg_dead）
	for j in jungle_monsters:
		if not is_instance_valid(j): continue
		var jid: int = j.get_instance_id()
		var jname := str(j.display_name)
		if _jg_dead.has(jid):
			var jleft: float = float(_jg_dead[jid]) - _jg_clock
			if jleft > 0.0:
				if (jname == "red_buff" or jname == "blue_buff") and jleft <= 30.0:
					MinimapDraw.draw_camp_respawn(self, _world_to_minimap(j.spawn_pos), jname, jleft,
						MinimapDraw.countdown_font(MINIMAP_SIZE))
				continue
		var jpos := _world_to_minimap(j.global_position)
		var seen: bool = j.visible and float(_jg_seen.get(jid, -9999.0)) >= _jg_clock - 0.5
		MinimapDraw.draw_jungle(self, jpos, jname, seen)

	# ---- 英雄（阵营色 + 朝向箭头 + 血量弧；本人白边；阵亡灰点 + 复活倒计时） ----
	# 血环统一：我方恒蓝 / 敌方恒红（弧长仍按血量比例，颜色不再随血量变化）
	var ally_ring := Color(0.25, 0.85, 1.0)
	var enemy_ring := Color(1.0, 0.28, 0.24)
	for h in heroes:
		if not is_instance_valid(h): continue
		if h.team != player_team and not h.visible and h.health > 0.0: continue
		# 敌方阵亡英雄不上图（己方阵亡仍显示灰点+复活倒计时）
		if h.team != player_team and h.health <= 0.0: continue
		var pos := _world_to_minimap(h.global_position)
		var base_col := Color(0.0, 0.886, 1.0) if h.team == player_team else Color(1.0, 0.33, 0.264)
		var hp_ratio := clampf(h.health / maxf(h.max_health, 1.0), 0.0, 1.0)
		var dir := Vector2(sin(h.rotation.y), cos(h.rotation.y))
		if h.velocity.length() > 0.2:
			dir = Vector2(h.velocity.x, h.velocity.z)
		if _flip180():
			dir = -dir
		var ring_col: Color = ally_ring if h.team == player_team else enemy_ring
		MinimapDraw.draw_hero(self, pos, dir, base_col, hp_ratio, not h.is_ai, h.health <= 0.0, float(h.respawn_timer), str(h.display_name), ring_col)

	# ---- 已开启的传送阵：紫色双层光环 + 旋转光点（存活期间才在组内） ----
	for z in get_tree().get_nodes_in_group("teleport_zones"):
		if not is_instance_valid(z): continue
		MinimapDraw.draw_teleport_zone(self, _world_to_minimap(z.global_position),
			Time.get_ticks_msec() * 0.001, zoomed or is_teleport_mode)

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
	var _fg := MinimapDraw.fog_grid(_fog_sources(), MAP_SIZE)
	if _flip180():
		_fg.reverse()
		for _row in _fg:
			_row.reverse()
	MinimapDraw.draw_fog(self, _fg, MINIMAP_SIZE)
	# ---- 全图技能：瞄准线 / 锁定高亮 / 飞行子弹 / 命中反馈（迷雾之上，避免被压暗） ----
	_draw_global_shots()
	# ---- 我方防御塔被攻击警告圈（绘制在最上层） ----
	_draw_tower_pings()
	_draw_frame()
	if zoomed:
		_draw_zoom_hint()

# 放大态提示：金色描边 + 底部操作条（轻点跳转并收起 / 拖动平移）
func _draw_zoom_hint() -> void:
	var r := Rect2(Vector2(-1.5, -1.5), Vector2(MINIMAP_SIZE + 3.0, MINIMAP_SIZE + 3.0))
	draw_rect(r, Color(1.0, 0.84, 0.35, 0.75), false, 1.5)
	var fs := int(round(MINIMAP_SIZE * 0.052))
	var txt := "轻点跳转 · 拖动平移 · 再点收起"
	var band_h := float(fs) * 1.9
	draw_rect(Rect2(Vector2(0, MINIMAP_SIZE - band_h), Vector2(MINIMAP_SIZE, band_h)),
		Color(0.03, 0.05, 0.09, 0.82))
	var f := UiKit.font()
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	UiKit.text(self, Vector2((MINIMAP_SIZE - tw) * 0.5, MINIMAP_SIZE - band_h * 0.5 + fs * 0.36),
		txt, fs, Color(1.0, 0.92, 0.72))
## 小地图边框：深色圆角底 + 双层描边（外暗内亮）+ 四角金色角标，压住底图边缘锯齿
func _draw_frame() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(MINIMAP_SIZE, MINIMAP_SIZE))
	# 边框与地图同界：不再向外扩 2px，避免深色底板相对地图/左上角看起来整体错位
	draw_style_box(UiKit.flat(0.0, 12, 2, Color(0.02, 0.03, 0.05, 0.95),
		Color(0, 0, 0, 0), 0.0, 0.0), r)
	draw_style_box(UiKit.flat(0.0, 8, 1, Color(0.62, 0.74, 0.92, 0.55),
		Color(0, 0, 0, 0), 0.0, 0.0), r.grow(-1.0))
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

# ==================== 全图技能（鲁班七号2 / 后羿3）：瞄准线 · 命中高亮 · 飞行子弹 · 命中反馈 ====================
func _draw_global_shots() -> void:
	var now := Time.get_ticks_msec() * 0.001
	# 1) 瞄准中：从英雄到全图方向的瞄准线 + 会被命中的敌人高亮
	if battle != null and battle.hero != null and not battle.hero.is_dead:
		var ga: Dictionary = battle.hero.global_aim()
		if not ga.is_empty():
			var from: Vector3 = ga["from"]
			var dir: Vector3 = ga["dir"]
			var col: Color = ga["color"]
			var p0 := _world_to_minimap(from)
			var p1 := _clip_to_map(p0, _world_to_minimap(from + dir * float(ga["len"])))
			MinimapDraw.draw_global_aim(self, p0, p1, col, now)
			var tg: GameEntity = _global_shot_target(from, dir, float(ga["len"]),
				float(ga["hit_r"]), bool(ga["only_hero"]))
			if tg is Hero:
				MinimapDraw.draw_aim_lock(self, _world_to_minimap(tg.global_position), now, col)
	# 2) 飞行中的全图子弹：按子弹实际位置画（拖尾 + 呼吸光环）
	for pr in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(pr) or not (pr is Bullet):
			continue
		var b: Bullet = pr
		var bcol := Color.WHITE
		if b.houyi_r:
			bcol = Color(1.0, 0.62, 0.14)
		elif b.luban_w_knockback:
			bcol = Color(0.42, 0.95, 0.72)
		else:
			continue
		var bdir := Vector2(b.linear_dir.x, b.linear_dir.z)
		if _flip180():
			bdir = -bdir
		MinimapDraw.draw_global_bullet(self, _world_to_minimap(b.global_position), bdir, bcol, now)
	# 3) 命中反馈：命中瞬间在被打英雄头像外扩散冲击环（0.7s）
	for h in heroes:
		if not is_instance_valid(h) or not h.has_meta("mm_shot_hit_ms"):
			continue
		var age: float = (Time.get_ticks_msec() - int(h.get_meta("mm_shot_hit_ms"))) / 700.0
		if age < 0.0 or age > 1.0:
			continue
		var hcol := Color(1.0, 0.62, 0.14)
		if str(h.get_meta("mm_shot_hit_kind", "houyi")) == "luban":
			hcol = Color(0.42, 0.95, 0.72)
		MinimapDraw.draw_shot_hit(self, _world_to_minimap(h.global_position), age, hcol)

# 沿瞄准方向找「第一个会被这颗子弹打中的单位」（撞墙/兵线/塔就算挡住，同真实弹道 pierce=false）
func _global_shot_target(from: Vector3, dir: Vector3, max_len: float, hit_r: float, only_hero: bool) -> GameEntity:
	var best: GameEntity = null
	var best_t := 1e20
	for e in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(e) or not (e is GameEntity):
			continue
		if e.team == player_team or e.health <= 0.0:
			continue
		if only_hero and not (e is Hero):
			continue
		# 敌方英雄没视野时不提示（与小地图英雄显示规则一致，避免透视）
		if e is Hero and not e.visible:
			continue
		var rel: Vector3 = e.global_position - from
		rel.y = 0.0
		var t: float = rel.dot(dir)
		if t <= 0.0 or t > max_len:
			continue
		if (rel - dir * t).length() > hit_r + e.body_radius:
			continue
		if t < best_t:
			best_t = t
			best = e
	return best

# 把瞄准线裁到小地图矩形内（子弹射程 160m > 地图 120m，必须裁剪）
func _clip_to_map(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var p: Array[float] = [-d.x, d.x, -d.y, d.y]
	var q: Array[float] = [a.x, float(MINIMAP_SIZE) - a.x, a.y, float(MINIMAP_SIZE) - a.y]
	for i in 4:
		var pi: float = p[i]
		var qi: float = q[i]
		if absf(pi) < 0.00001:
			if qi < 0.0:
				return a
			continue
		var r: float = qi / pi
		if pi < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return a
	return a + d * t1

# 扫描我方塔：正在被攻击（塔的 under_attack_timer > 0）且距上次警告够久 → 触发一次警告
# 高地塔 / 水晶 用红色长警报（更频繁、持续更久），其余塔保持黄色短警告
func _scan_tower_warnings():
	var alive := {}
	for t in turrets:
		if not is_instance_valid(t) or t.team != player_team or t.health <= 0.0:
			continue
		var id: int = t.get_instance_id()
		alive[id] = true
		if t.under_attack_timer <= 0.0:
			continue
		var is_hq: bool = _is_hq_turret(t)
		var cd: float = PING_COOLDOWN_HQ if is_hq else PING_COOLDOWN
		var last: float = float(_tower_ping_time.get(id, -cd))
		if _ping_clock - last >= cd:
			_tower_ping_time[id] = _ping_clock
			_active_pings[id] = {"pos": _world_to_minimap(t.global_position), "start": _ping_clock, "hq": is_hq}
	# 清理已消失塔的限频记录（正在播放的警告圈由绘制侧按时长过期）
	for id in _tower_ping_time.keys():
		if not alive.has(id):
			_tower_ping_time.erase(id)

# 高地塔 / 水晶判定（联机客户端字段可能缺省，display_name 兜底）
func _is_hq_turret(t) -> bool:
	var tier := str(t.tower_type)
	if tier == "":
		tier = str(t.display_name)
	return tier == "high" or tier == "crystal"

# 绘制所有活动警告圈；坐标取触发瞬间的快照，塔被打掉/消失也能播完动画
func _draw_tower_pings():
	if _active_pings.is_empty():
		return
	var now := _ping_clock
	var done := []
	for key in _active_pings.keys():
		var p: Dictionary = _active_pings[key]
		var is_hq: bool = bool(p.get("hq", false))
		var age := now - float(p["start"])
		if age >= (PING_DURATION_HQ if is_hq else PING_DURATION):
			done.append(key)
			continue
		var ppos: Vector2 = p["pos"]
		_draw_ping_effect(ppos, age, is_hq)
	for key in done:
		_active_pings.erase(key)

# 单个警告圈：半径从大缩到小，重复若干次，末段整体渐隐；高地/水晶为红色且更大
func _draw_ping_effect(pos: Vector2, age: float, is_hq: bool = false):
	var dur: float = PING_DURATION_HQ if is_hq else PING_DURATION
	var cycles: int = PING_CYCLES_HQ if is_hq else PING_CYCLES
	var t := clampf(age / dur, 0.0, 1.0)
	var big_r := clampf(MINIMAP_SIZE * (0.16 if is_hq else 0.11), 14.0, 46.0 if is_hq else 32.0)
	var cyc_t := t * float(cycles)
	var frac: float = cyc_t - floor(cyc_t)
	var r := lerpf(big_r, 2.0, frac)
	var alpha: float = 1.0 - 0.9 * frac          # 每圈收尾时淡一点
	if t > 0.72:                            # 最后一次收圈后整体淡出
		alpha *= clampf((1.0 - t) / 0.28, 0.0, 1.0)
	alpha = clampf(alpha, 0.0, 1.0)
	var col: Color = Color(1.0, 0.16, 0.12) if is_hq else Color(1.0, 0.82, 0.12)
	col.a = alpha
	draw_circle(pos, r, Color(col.r, col.g, col.b, alpha * 0.15))  # 淡色内填充，弱化遮挡
	draw_arc(pos, r, 0, TAU, 48, col, 3.6 if is_hq else 3.0)
	# 高地图警报：圆心再补一个红点，避免只靠收缩圈被其他图标盖住
	if is_hq:
		draw_circle(pos, 4.0, Color(1.0, 0.22, 0.16, alpha * 0.85))

# 一次性把 120×120 地形网格渲染成 200×200 像素的纹理（每像素取所在网格的底色）
func _ensure_terrain_texture():
	if _terrain_texture:
		return
	# 共享地形底图：120 网格取色 + 双线性放大 + 交界描边 + 暗角（host/client 同源）
	_terrain_texture = MinimapDraw.terrain_texture(256, MAP_SIZE)


# 玩家在红方时小地图整体旋转 180°（己方基地在左下，和镜头方向一致）
func _flip180() -> bool:
	return Config.player_team == Config.Team.ENEMY

func _world_to_minimap(world_pos: Vector3) -> Vector2:
	var gx = world_pos.x + MAP_SIZE / 2.0
	var gy = world_pos.z + MAP_SIZE / 2.0
	var p := Vector2(gx * MINIMAP_SIZE / MAP_SIZE, gy * MINIMAP_SIZE / MAP_SIZE)
	if _flip180():
		p = Vector2(MINIMAP_SIZE - p.x, MINIMAP_SIZE - p.y)
	return p
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
	for tr in get_tree().get_nodes_in_group("tripods"):
		if is_instance_valid(tr) and tr.team == player_team and tr.health > 0.0:
			out.append({"p": tr.global_position, "r": 8.0})
	if battle != null and is_instance_valid(battle):
		for s in battle.get_tree().get_nodes_in_group("vision_spirits"):
			if is_instance_valid(s) and s.team == player_team and s.vision_active:
				out.append({"p": s.global_position, "r": 20.0})
		if battle.has_method("get_dead_visions"):
			for d in battle.get_dead_visions(player_team):
				out.append({"p": d.get("pos", Vector3.ZERO),
					"r": 18.0 if str(d.get("kind", "")) == "turret" else 9.0})
	out.append({"p": Vector3(-58.0, 0.0, 58.0), "r": 24.0})
	out.append({"p": Vector3(-53.0, 0.0, 53.0), "r": 18.0})
	return out

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

## 联机：我方「已确认在复活中」的野怪点位（客户端据此画幽灵/隐藏/读秒）
## 每项 [x, z, 名称, 剩余复活秒数]
func jg_dead_list() -> Array:
	var out: Array = []
	for j in jungle_monsters:
		if not is_instance_valid(j):
			continue
		var jid: int = j.get_instance_id()
		if _jg_dead.has(jid) and _jg_clock < float(_jg_dead[jid]):
			out.append([j.spawn_pos.x, j.spawn_pos.z, str(j.display_name),
				maxf(float(_jg_dead[jid]) - _jg_clock, 0.0)])
	return out
