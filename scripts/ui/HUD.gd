# scripts/ui/HUD.gd
extends CanvasLayer
## 世界血条/名称：非英雄单位统一交给 WorldBarPainter 合批绘制（单 Control 一次 _draw，
## 节点数从「2/单位」降到「1 个总节点」；同时做屏幕剔除 + 距离 LOD + 文本按需更新）。
## 英雄仍用 HeroInfoControl（等级环/状态/暗印/MVP 等富信息），只做投影定位。

const BarPainterScript = preload("res://scripts/ui/WorldBarPainter.gd")
var bars = null
var hero_info_controls: Dictionary = {}  # Hero -> HeroInfoControl
var fp_player_bar: HeroInfoControl = null  # 第一人称下屏幕底部固定的自身血条
var _bar_rows: Dictionary = {}   # entity -> row（复用字典，避免每帧分配）
var _row_buf: Array = []

func _ready():
	set_process(true)
	bars = BarPainterScript.new()
	bars.name = "WorldBars"
	add_child(bars)

func _process(_delta):
	_update_health_bars()

func _update_health_bars():
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	var cam_forward: Vector3 = -cam.global_transform.basis.z
	var cam_pos: Vector3 = cam.global_position
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var vp_rect := Rect2(Vector2(-60, -80), vp + Vector2(120, 220))
	var delta: float = get_process_delta_time()

	# 清理已失效 / 已死亡 / 已变成英雄的行缓存
	var stale: Array = []
	for e in _bar_rows.keys():
		if not is_instance_valid(e) or e is Hero or e.health <= 0:
			stale.append(e)
	for e in stale:
		_bar_rows.erase(e)

	# 清理英雄信息控件
	var to_remove: Array = []
	for hero in hero_info_controls.keys():
		if not is_instance_valid(hero) or hero.health <= 0:
			hero_info_controls[hero].queue_free()
			to_remove.append(hero)
	for hero in to_remove:
		hero_info_controls.erase(hero)

	_row_buf.clear()
	for entity in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(entity): continue
		if entity is Hero:
			if entity.health <= 0 and not entity.is_reviving: continue
			if not entity.visible: continue
			_update_hero_bar(entity, cam, cam_forward)
			continue
		if entity.health <= 0: continue
		if not entity.visible: continue
		_update_unit_row(entity, cam, cam_forward, cam_pos, vp_rect, delta)
	bars.rows = _row_buf

	# 第一人称：自身世界血条被隐藏（锚点在相机正上方），改用屏幕底部固定血条
	var bm = get_tree().get_first_node_in_group("battle_manager")
	var fp_active = bm != null and bm.first_person_view and bm.hero != null and is_instance_valid(bm.hero)
	if fp_active:
		if not fp_player_bar or not is_instance_valid(fp_player_bar) or fp_player_bar.hero != bm.hero:
			if fp_player_bar and is_instance_valid(fp_player_bar):
				fp_player_bar.queue_free()
			fp_player_bar = HeroInfoControl.new()
			fp_player_bar.hero = bm.hero
			add_child(fp_player_bar)
		fp_player_bar.size = Vector2(200, 90)
		var vw := get_viewport().get_visible_rect().size
		fp_player_bar.position = Vector2(vw.x / 2.0 - 100.0, vw.y - 446.0)
		fp_player_bar.visible = true
	elif fp_player_bar and is_instance_valid(fp_player_bar):
		fp_player_bar.visible = false

# 英雄血条（富信息控件）：只做投影定位
func _update_hero_bar(entity, cam, cam_forward: Vector3) -> void:
	if entity not in hero_info_controls:
		var info = HeroInfoControl.new()
		info.hero = entity
		info.visible = true
		add_child(info)
		hero_info_controls[entity] = info
	var info = hero_info_controls[entity]
	# 英雄血条被顶部中央战况带遮挡：锚点整体下移，避开 band
	var world_pos = entity.global_position + Vector3.UP * (entity.body_radius * 2.0 + 1.2)
	# 锚点在相机后方（含第一人称自身：锚点位于相机正上方，深度≈0）时隐藏，避免 unproject 投影错乱
	if cam_forward.dot(world_pos - cam.global_position) <= 0.3:
		info.visible = false
		return
	info.visible = true
	var screen_pos = cam.unproject_position(world_pos)
	info.position = screen_pos - info.custom_minimum_size / 2
	info.queue_redraw()

# 非英雄单位：屏幕剔除 + 距离 LOD，然后填一行交给 WorldBarPainter
func _update_unit_row(entity, cam, cam_forward: Vector3, cam_pos: Vector3, vp_rect: Rect2, delta: float) -> void:
	var is_turret: bool = entity is Turret
	var is_monster: bool = entity is JungleMonster
	var is_epic: bool = is_monster and (entity as JungleMonster).is_epic()
	var dist: float = cam_pos.distance_to(entity.global_position)
	# 小兵：远处直接舍弃（原系统给全图每个兵建 Control + Label 两个节点）
	if not (is_turret or is_monster) and dist > 44.0:
		return

	var anchor: float = entity.body_radius * 2.0 + 1.0
	if is_epic:
		anchor = entity.bar_anchor_height()
	var world_pos: Vector3 = entity.global_position + Vector3.UP * anchor
	if cam_forward.dot(world_pos - cam.global_position) <= 0.3:
		return
	var sp: Vector2 = cam.unproject_position(world_pos)
	if not vp_rect.has_point(sp):
		return

	var hp: float = entity.health
	var mx: float = maxf(1.0, entity.max_health)
	# 满血小兵且在中远距离：只画缩小细条（不带文字），避免屏幕被“320/320”塞满
	var small_bar: bool = not (is_turret or is_monster) and hp >= mx and dist > 20.0

	var row = _bar_rows.get(entity)
	if row == null:
		row = {
			"lag": hp, "flash_t": 0.0, "flash_amt": 0.0, "heal_t": 0.0, "heal_amt": 0.0,
			"prev_hp": hp, "num_key": -1, "num_text": "", "marker_list": [],
			"disp_name": str(entity.get("display_name") if "display_name" in entity else "??"),
		}
		_bar_rows[entity] = row

	var prev: float = float(row["prev_hp"])
	if hp < prev:
		row["flash_amt"] = prev - hp
		row["flash_t"] = 0.5
		row["heal_t"] = 0.0
	elif hp > prev:
		row["heal_amt"] = hp - prev
		row["heal_t"] = 0.5
		row["flash_t"] = 0.0
		row["lag"] = hp
	row["prev_hp"] = hp
	var ft: float = float(row["flash_t"])
	var ht: float = float(row["heal_t"])
	if ft > 0.0: row["flash_t"] = maxf(0.0, ft - delta)
	if ht > 0.0: row["heal_t"] = maxf(0.0, ht - delta)
	var lag: float = float(row["lag"])
	if lag > hp:
		lag = lerpf(lag, hp, clampf(delta * 7.0, 0.0, 1.0))
		if lag - hp < 1.0: lag = hp
	else:
		lag = hp
	row["lag"] = lag

	# 尺寸（与原控件一致）
	var w: float = 110.0
	var h: float = 15.0
	if is_turret:
		w = 300.0
		h = 22.0
	elif is_epic:
		var segs: int = maxi(1, int(ceil(mx / 1000.0)))
		w = clampf(float(segs) * 22.0, 380.0, 880.0)
		h = 30.0
	if small_bar:
		w = 72.0
		h = 8.0
	row["w"] = w
	row["h"] = h
	row["pos"] = sp - Vector2(w, h) * 0.5
	row["hp"] = hp
	row["max_hp"] = mx
	row["epic"] = is_epic
	row["ticks"] = is_turret

	row["team"] = int(entity.team)
	match int(entity.team):
		0: row["team_color"] = Color(0.0, 0.886, 1.0, 1.0)
		1: row["team_color"] = Color(1.0, 0.33, 0.264, 1.0)
		2: row["team_color"] = Color(0.0, 0.886, 0.431, 1.0)
		_: row["team_color"] = Color(0.945, 0.925, 0.251, 1.0)

	row["interfere"] = 0.0
	row["shield_icon"] = false
	if is_turret:
		var turret = entity as Turret
		if turret.interfere_timer > 0 and turret.interfere_max > 0:
			row["interfere"] = clampf(turret.interfere_timer / turret.interfere_max, 0.0, 1.0)
		row["shield"] = float(turret.tower_shield)
		row["shield_icon"] = turret.shield_protected_no_minion
	else:
		row["shield"] = float(entity.shield_remaining)
		if is_epic:
			var battle := get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if battle and battle.hero and is_instance_valid(battle.hero):
				row["shield_icon"] = (battle.get_bonded_team(entity) == battle.hero.team)

	# 李元芳暗印预判（血条尾部黄段）：先看有无暗印，避免每帧空数组分配
	var doom := 0.0
	if entity is GameEntity and not entity.lyf_marks.is_empty():
		var pred := 0.0
		for lm in entity.lyf_mark_summary():
			pred += float(lm["pred"])
		doom = clampf(pred - float(row["shield"]), 0.0, hp)
	row["doom"] = doom

	# 文本：名称/血量（血量键值不变就不重建字符串）
	var is_herolike: bool = is_turret or is_monster
	row["show_name"] = is_herolike
	# 默认隐藏具体血量数值（如需按距离显示，把下面的 false 换成 dist <= 26.0）
	row["show_numbers"] = false
	row["name_text"] = str(row["disp_name"])
	var nk: int = int(hp * 10.0) * 16 + int(mx)
	if int(row["num_key"]) != nk:
		row["num_key"] = nk
		row["num_text"] = "%d/%d" % [int(hp), int(mx)]
	# 层数标记：只有真有标记的单位才拼字符串（原实现每帧对每个单位都建空数组）
	# 标记图标：只对真有标记的单位收集（数组元素含层数，由绘制器画成专属图标）
	var mlist: Array = row["marker_list"]
	mlist.clear()
	if is_monster and dist <= 26.0 and entity is GameEntity and not entity.markers.is_empty():
		for src in entity.get_marker_sources():
			var cnt: int = entity.count_markers(src)
			if cnt > 0:
				mlist.append({"name": str(src.display_name), "count": cnt, "type": ""})
	_row_buf.append(row)
