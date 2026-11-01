class_name PostMatchStage
extends Node
## 赛后聚光灯舞台（单机 / 联机客户端 / 回放共用这一份）：
## V 字站位 → 5 盏聚光灯（无光柱）→ 黑背景 + 主平行光 → 镜头推近 → 点击聚焦玩家 + 个人面板 → 再点击交还结算。
## 各端只负责：隐藏/恢复自己的战场与 HUD、收集 units（Node3D）与 entries（名字/昵称/分路/MVP/奖牌）、提供个人详情数据。

signal advance
signal finished

const PostMatchViewScript = preload("res://scripts/ui/PostMatchView.gd")

var view: Control = null
var layer: CanvasLayer = null
var stage_pos: Vector3 = Vector3.ZERO
var inward: Vector3 = Vector3.ZERO
var right: Vector3 = Vector3.ZERO
var units: Array = []
var player_index := 0
## 阶段 B 个人详情数据提供者：Callable -> Dictionary（rows / rank_lines / rating / medal …）
var detail_provider: Callable = Callable()

var _cam: Camera3D = null
var _lights: Array = []
var _key: DirectionalLight3D = null
var _env: Environment = null
var _slot_offsets: Array = []


## host: 舞台节点挂载处（一般就是各端战斗宿主节点）
## unit_list: 舞台上的 5 个 Node3D（单机是 Hero，联机/回放是模型根节点）
## entries: 交给 PostMatchView 的铭牌数据（含 node 引用以便每帧跟随）
func setup(host: Node3D, cam: Camera3D, unit_list: Array, entries: Array, won: bool,
		player_i := 0, opts: Dictionary = {}) -> void:
	_cam = cam
	units = unit_list
	player_index = player_i
	var own_team: int = int(opts.get("own_team", Config.player_team))
	var base := Vector3(-53.0, 0.0, 53.0) if own_team == Config.Team.PLAYER else Vector3(53.0, 0.0, -53.0)
	inward = Vector3(-base.x, 0.0, -base.z).normalized()
	right = inward.cross(Vector3.UP).normalized()
	stage_pos = base + inward * 22.0
	stage_pos.y = 0.0
	_slot_offsets = [
		Vector3.ZERO,
		right * 4.6 - inward * 2.6,
		right * -4.6 - inward * 2.6,
		right * 9.2 - inward * 5.2,
		right * -9.2 - inward * 5.2,
	]
	# —— 站位 + 冻结 ——
	for i in range(units.size()):
		var u = units[i]
		if u == null or not is_instance_valid(u):
			continue
		if u is Hero:
			var eh: Hero = u
			# 阵亡的（终局时正在死亡/等待复活）也上台：恢复存活外观
			eh.is_dead = false
			eh.is_reviving = false
			eh.revive_timer = 0.0
			eh.respawn_timer = 0.0
			eh.health = eh.max_health
			eh.visible = true
			eh.scale = Vector3.ONE
			eh.global_position = stage_pos + _slot_offsets[i]
			eh.velocity = Vector3.ZERO
			eh.rotation = Vector3(0.0, atan2(inward.x, inward.z), 0.0)
			for ch in eh.get_children():
				if ch is HeroAI:
					ch.set_physics_process(false)
					ch.set_process(false)
			eh.set_physics_process(false)
			if eh.anim_player != null and eh.anim_player.has_animation("idle"):
				eh.anim_player.play("idle")
		elif u is Node3D:
			var nd: Node3D = u
			nd.visible = true
			nd.scale = Vector3.ONE
			nd.global_position = stage_pos + _slot_offsets[i]
			nd.rotation = Vector3(0.0, atan2(inward.x, inward.z), 0.0)
		_add_spotlight(stage_pos + _slot_offsets[i], i == player_index)
	# —— 黑背景 + 主平行光（避免只有聚光灯导致人物发黑） ——
	if cam != null and is_instance_valid(cam) and bool(opts.get("black_env", true)):
		_env = Environment.new()
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.0, 0.0, 0.0)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.24, 0.27, 0.34)
		_env.ambient_light_energy = 1.05
		_env.glow_enabled = true
		_env.glow_intensity = 0.55
		cam.environment = _env
	if bool(opts.get("key_light", true)) and host != null:
		var key := DirectionalLight3D.new()
		key.light_color = Color(0.98, 0.95, 0.90)
		key.light_energy = 1.35
		key.shadow_enabled = false
		host.add_child(key)
		_key = key
		_lights.append(key)
	# —— 铭牌层（独立 CanvasLayer，压在 HUD 之上） ——
	layer = CanvasLayer.new()
	layer.layer = int(opts.get("layer", 90))
	host.add_child(layer)
	view = PostMatchViewScript.new()
	layer.add_child(view)
	view.set_camera(cam)
	view.set_stage(won, entries)
	view.advance.connect(_on_advance_clicked)
	view.finished.connect(_on_finished_clicked)
	# —— 镜头推到 V 字正面 ——
	if cam != null and is_instance_valid(cam):
		var look: Vector3 = stage_pos + Vector3(0.0, 1.25, 0.0)
		var cam_end: Vector3 = stage_pos + inward * 6.2 + Vector3(0.0, 3.9, 0.0)
		var rot: Vector3 = Basis.looking_at((look - cam_end).normalized(), Vector3.UP).get_euler()
		if _key != null and is_instance_valid(_key):
			var light_dir: Vector3 = (-inward + Vector3(0.0, -0.85, 0.0)).normalized()
			_key.global_rotation = Basis.looking_at(light_dir, Vector3.UP).get_euler()
		var tw: Tween = view.create_tween()
		tw.set_parallel(true)
		tw.tween_property(cam, "global_position", cam_end, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(cam, "rotation", rot, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.finished.connect(func() -> void:
			if cam != null and is_instance_valid(cam):
				cam.global_position = cam_end
				cam.rotation = rot)


## 第一次点击：其余英雄不退场，镜头推到玩家左侧三分之一，并出右侧个人面板
func _on_advance_clicked() -> void:
	if view == null or not is_instance_valid(view):
		return
	var p = units[player_index] if player_index >= 0 and player_index < units.size() else null
	if p is Node3D and _cam != null and is_instance_valid(_cam):
		var pp: Vector3 = (p as Node3D).global_position
		var look: Vector3 = pp - right * 5.8 + Vector3(0.0, 1.45, 0.0)
		var cam_end: Vector3 = pp + inward * 9.6 - right * 5.8 + Vector3(0.0, 5.6, 0.0)
		var rot: Vector3 = Basis.looking_at((look - cam_end).normalized(), Vector3.UP).get_euler()
		var tw2: Tween = view.create_tween()
		tw2.set_parallel(true)
		tw2.tween_property(_cam, "global_position", cam_end, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.tween_property(_cam, "rotation", rot, 0.85).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.finished.connect(func() -> void:
			if _cam != null and is_instance_valid(_cam):
				_cam.global_position = cam_end
				_cam.rotation = rot)
	if detail_provider.is_valid():
		view.show_player_detail(detail_provider.call())
	advance.emit()


## 第二次点击：收掉舞台层与灯光，交还结算面板（战场/UI 恢复由各端在 finished 回调里做）
func _on_finished_clicked() -> void:
	cleanup()
	finished.emit()


func cleanup() -> void:
	if layer != null and is_instance_valid(layer):
		layer.queue_free()
	layer = null
	view = null
	for n in _lights:
		if is_instance_valid(n):
			n.queue_free()
	_lights.clear()
	_key = null
	if _cam != null and is_instance_valid(_cam):
		_cam.environment = null
	_env = null
	queue_free()


## 单盏聚光灯：顶光 + 地面光圈（不打体积光柱，避免糊住人物）
func _add_spotlight(pos: Vector3, is_player: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	_lights.append(root)
	var col: Color = Color(1.0, 0.92, 0.62) if is_player else Color(0.62, 0.86, 1.0)
	var sl := SpotLight3D.new()
	sl.position = Vector3(0.0, 7.5, 0.0)
	sl.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	sl.spot_range = 18.0
	sl.spot_angle = 32.0
	sl.light_energy = 4.5 if is_player else 3.2
	sl.light_color = col
	root.add_child(sl)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.25
	cm.bottom_radius = 1.25
	cm.height = 0.02
	cm.radial_segments = 40
	disc.mesh = cm
	disc.position = Vector3(0.0, 0.02, 0.0)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.albedo_color = Color(col.r, col.g, col.b, 0.34 if is_player else 0.22)
	disc.material_override = dm
	root.add_child(disc)
