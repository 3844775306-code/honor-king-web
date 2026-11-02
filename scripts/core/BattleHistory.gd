class_name BattleHistory
## 对战纪录：每局结束把结算数据（winner + 全英雄行）追加到 user://battle_history.json，
## 大厅「对战纪录」页面读取后复刻结算面板。与联机结算广播共用同一份 rows 结构。

static func _path() -> String:
	return UserScope.path("battle_history.json")
const MAX_RECORDS := 20


# 从进行中的战斗收集结算数据（离线 / 联机主机通用）
static func payload_from_battle(bm: Node) -> Dictionary:
	var rows: Array = []
	var turrets := [0, 0]        # [蓝方被拆塔数, 红方被拆塔数]（每方 9 塔 + 1 水晶）
	if bm != null and is_instance_valid(bm):
		for e in bm.get_tree().get_nodes_in_group("heroes"):
			if e is Hero:
				var h := e as Hero
				rows.append({
					"name": h.display_name, "nick": str(h.player_name), "team": h.team, "lv": h.level,
					"k": h.kills, "d": h.deaths, "a": h.assists,
					"gold": int(h.total_gold_earned), "dmg": int(h.damage_dealt_to_heroes),
					"mvp": h.is_mvp, "mine": not h.is_ai,
					# —— 更详细的对战信息 ——
					"role": str(h.role), "lh": int(h.last_hits), "jungle": int(h.jungle_gold),
					"taken": int(h.damage_taken_from_heroes), "heal": int(h.healing_done),
					"cc": int(round(h.cc_duration_dealt * 10.0)), "turret": int(h.turret_damage),
					"items": _item_names(h),
					"equips": _item_entries(h),
				})
		# 存活塔数 → 被拆数（塔阵亡后会自行 queue_free，缺失即视为已拆）
		for team in 2:
			var alive := 0
			for t in bm.get_tree().get_nodes_in_group("turrets"):
				if t is Turret and int(t.team) == team and t.health > 0.0:
					alive += 1
			turrets[team] = maxi(0, Turret.TOTAL_PER_SIDE - alive)
	return {"winner": int(bm.get("winner")) if bm != null else -1,
			"dur": float(bm.get("game_time")) if bm != null else 0.0,
			"turrets": turrets,
			# 本局玩家所在阵营：离线随机红蓝，胜负判断必须按它而不是固定 PLAYER(蓝)
			"player_team": int(Config.player_team),
			"rows": rows}


# 出征装备名列表（跳过空槽）
static func _item_names(h: Hero) -> Array:
	var out: Array = []
	for id in h.equipment_slots:
		if str(id) == "":
			continue
		var info: Dictionary = ItemDatabase.get_item(str(id))
		out.append(str(info.get("name", id)))
	return out


# 装备图标数据：[名称, 品质]；旧存档只有 items 名称时由界面回退查品质
static func _item_entries(h: Hero) -> Array:
	var out: Array = []
	for id in h.equipment_slots:
		if str(id) == "":
			continue
		var info: Dictionary = ItemDatabase.get_item(str(id))
		out.append([str(info.get("name", id)), int(info.get("tier", 1))])
	return out


# 本局玩家阵营：新记录直读 player_team；旧记录用 mine 行反推；再兜底蓝方
static func player_team_of(rec: Dictionary) -> int:
	var pt := int(rec.get("player_team", -1))
	if pt == Config.Team.PLAYER or pt == Config.Team.ENEMY:
		return pt
	for r in rec.get("rows", []):
		var team := int(r.get("team", -1))
		if bool(r.get("mine", false)) and (team == Config.Team.PLAYER or team == Config.Team.ENEMY):
			return team
	return Config.Team.PLAYER


static func enemy_team_of(rec: Dictionary) -> int:
	return 1 - player_team_of(rec)


# 追加一条纪录（最多保留 MAX_RECORDS 条，新的在最前）
static func record(payload: Dictionary, mode: String) -> void:
	var rows: Array = payload.get("rows", [])
	if rows.is_empty():
		return
	var all_records := all()
	all_records.push_front({
		"ts": int(Time.get_unix_time_from_system()),
		"mode": mode,
		"winner": int(payload.get("winner", -1)),
		"player_team": player_team_of(payload),
		"dur": float(payload.get("dur", 0.0)),
		"turrets": payload.get("turrets", []),
		"rank": payload.get("rank", {}),
		"rows": rows,
	})
	while all_records.size() > MAX_RECORDS:
		all_records.pop_back()
	_save(all_records)


static func all() -> Array:
	if not FileAccess.file_exists(_path()):
		return []
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f = null
	var data: Variant = JSON.parse_string(txt)
	return data if data is Array else []


static func count() -> int:
	return all().size()


static func clear() -> void:
	var abs_path := ProjectSettings.globalize_path(_path())
	if FileAccess.file_exists(_path()):
		DirAccess.remove_absolute(abs_path)
	_save([])


static func _save(all_records: Array) -> void:
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(all_records))
	f = null
	CloudSync.schedule_push()


# 云端恢复：本地与云端纪录合并去重（云端在前，保留最新 MAX_RECORDS 条）
static func import_all(records: Array) -> bool:
	if records.is_empty():
		return false
	var merged: Array = []
	var seen: Dictionary = {}
	for rec in records:
		if not (rec is Dictionary):
			continue
		var key := JSON.stringify(rec)
		if seen.has(key):
			continue
		seen[key] = true
		merged.append(rec)
	for rec2 in all():
		if not (rec2 is Dictionary):
			continue
		var key2 := JSON.stringify(rec2)
		if seen.has(key2):
			continue
		seen[key2] = true
		merged.append(rec2)
	while merged.size() > MAX_RECORDS:
		merged.pop_back()
	_save(merged)
	return true




