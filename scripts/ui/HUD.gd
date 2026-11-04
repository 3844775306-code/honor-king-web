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
			if not entity.visible:
				# 英雄血条是常驻 Control：敌方脱离视野后必须显式隐藏，
				# 否则会停留在最后位置（表现就是“人已走远血条还挂着”）
				var hidden_info = hero_info_controls.get(entity)
				if hidden_info != null and is_instance_valid(hidden_info):
					hidden_info.visible = false
				continue
			_update_hero_bar(entity, cam, cam_forward)
			continue
		if entity.health <= 0: continue
		if entity is Tripod and (entity as Tripod).is_r_tripod:
			continue   # 大招乾鼎不可攻击，不画血条
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
	# 阵亡英雄保留倒地模型，但不再显示血条
	if entity.get("is_dead") == true:
		info.visible = false
		return
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
	if entity.has_method("bar_anchor_height"):
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

	# 尺寸：跟随模型实际体型（小兵已放大1.5倍；水晶已缩半但仍比普通塔宽）
	var w: float = 110.0
	var h: float = 15.0
	if is_turret:
		var tsz: Vector2 = BarPainterScript.turret_bar_size(str(entity.get("display_name")))
		w = tsz.x
		h = tsz.y
	elif is_epic:
		var segs: int = maxi(1, int(ceil(mx / 1000.0)))
		w = clampf(float(segs) * 22.0, 380.0, 880.0)
		h = 30.0
	elif entity is Minion:
		var ms: float = BarPainterScript.minion_bar_scale(str((entity as Minion).display_name))
		w *= ms
		h *= ms
	if small_bar:
		var ss: float = BarPainterScript.minion_bar_scale(str((entity as Minion).display_name)) if entity is Minion else 1.0
		w = 72.0 * ss
		h = 8.0 * ss
	row["w"] = w
	row["h"] = h
	row["pos"] = sp - Vector2(w, h) * 0.5
	row["hp"] = hp
	row["max_hp"] = mx
	row["epic"] = is_epic
	# 野怪 / 主宰先锋：血条每 1000 血一条分隔线；塔保持 2000 一格
	var is_vanguard := false
	if entity is Minion:
		# 主宰先锋：minion_type 未赋值（默认 melee），实际类型在 display_name 上
		var mtype := str((entity as Minion).display_name)
		is_vanguard = mtype in ["dragon", "storm", "shadow_dragon"]
	row["ticks"] = is_turret or is_monster or is_vanguard
	row["tick_step"] = 2000.0 if is_turret else 1000.0

	row["team"] = int(entity.team)
	# 玩家自己的血条恒为绿色（与阵营无关）
	var _bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if _bm and _bm.hero and is_instance_valid(_bm.hero) and entity == _bm.hero:
		row["team_color"] = Color(0.33, 0.95, 0.42, 1.0)
	else:
		match int(entity.team):
			0, 1: row["team_color"] = Color(0.0, 0.886, 1.0, 1.0) if Config.is_ally(int(entity.team)) else Color(1.0, 0.33, 0.264, 1.0)
			2: row["team_color"] = Color(0.0, 0.886, 0.431, 1.0)
			_: row["team_color"] = Color(0.945, 0.925, 0.251, 1.0)

	row["interfere"] = 0.0
	# 补刀提示（放宽）：屏幕内任意敌方单位，剩余血量 < 玩家一次普攻（按护甲减免后）→ 血条转灰白
	row["last_hit"] = false
	if _bm and _bm.hero and is_instance_valid(_bm.hero):
		var _ph = _bm.hero
		if entity != _ph and not Config.is_ally(int(entity.team)) and hp > 0.0:
			var _res: float = maxf(0.0, float(entity.armor) - float(_ph.flat_phys_pen))
			var _aa: float = float(_ph.actual_attack_damage) * (1.0 - _res / (_res + 602.0))
			if hp < _aa:
				row["last_hit"] = true
	row["shield_icon"] = false
	row["shield_next"] = -1.0
	if is_turret:
		var turret = entity as Turret
		if turret.interfere_timer > 0 and turret.interfere_max > 0:
			row["interfere"] = clampf(turret.interfere_timer / turret.interfere_max, 0.0, 1.0)
		row["shield"] = float(turret.tower_shield)
		row["shield_icon"] = turret.shield_protected_no_minion
		# 前 4 分钟：在血条上标出下一个塔盾触发点（75/50/25%）
		if _bm != null and _bm.game_time < 240.0 and turret.health > 0.0:
			var _hr: float = clampf(turret.health / maxf(1.0, turret.max_health), 0.0, 1.0)
			var _candidates := [
				[0.75, turret.shield_stage_75],
				[0.50, turret.shield_stage_50],
				[0.25, turret.shield_stage_25],
			]
			for _cand in _candidates:
				if not bool(_cand[1]) and _hr > float(_cand[0]):
					row["shield_next"] = float(_cand[0])
					break
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
	# 防御塔不再显示名称文字，改为血条下方一个指向塔身的小三角箭头
	row["show_name"] = false   # 野怪血条不显示名字
	row["turret_arrow"] = is_turret
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
	# 小兵/野怪都显示被动标记图标（此前只给野怪收集，小兵层数完全看不见）
	if dist <= 28.0 and entity is GameEntity and not entity.markers.is_empty():
		for src in entity.get_marker_sources():
			var cnt: int = entity.count_markers(src)
			if cnt > 0:
				mlist.append({"name": str(src.display_name), "count": cnt, "type": ""})
	_row_buf.append(row)
