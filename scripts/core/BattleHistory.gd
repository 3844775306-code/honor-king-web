class_name BattleHistory
## 对战纪录：每局结束把结算数据（winner + 全英雄行）追加到 user://battle_history.json，
## 大厅「对战纪录」页面读取后复刻结算面板。与联机结算广播共用同一份 rows 结构。

const PATH := "user://battle_history.json"
const MAX_RECORDS := 20


# 从进行中的战斗收集结算数据（离线 / 联机主机通用）
static func payload_from_battle(bm: Node) -> Dictionary:
	var rows: Array = []
	var turrets := [0, 0]        # [我方被拆塔数, 敌方被拆塔数]（每方 9 塔 + 1 水晶）
	if bm != null and is_instance_valid(bm):
		for e in bm.get_tree().get_nodes_in_group("heroes"):
			if e is Hero:
				var h := e as Hero
				rows.append({
					"name": h.display_name, "team": h.team, "lv": h.level,
					"k": h.kills, "d": h.deaths, "a": h.assists,
					"gold": int(h.total_gold_earned), "dmg": int(h.damage_dealt_to_heroes),
					"mvp": h.is_mvp, "mine": not h.is_ai,
					# —— 更详细的对战信息 ——
					"role": str(h.role), "lh": int(h.last_hits), "jungle": int(h.jungle_gold),
					"taken": int(h.damage_taken_from_heroes), "heal": int(h.healing_done),
					"cc": int(round(h.cc_duration_dealt * 10.0)), "turret": int(h.turret_damage),
					"items": _item_names(h),
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
		"dur": float(payload.get("dur", 0.0)),
		"turrets": payload.get("turrets", []),
		"rank": payload.get("rank", {}),
		"rows": rows,
	})
	while all_records.size() > MAX_RECORDS:
		all_records.pop_back()
	_save(all_records)


static func all() -> Array:
	if not FileAccess.file_exists(PATH):
		return []
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f = null
	var data: Variant = JSON.parse_string(txt)
	return data if data is Array else []


static func count() -> int:
	return all().size()


static func clear() -> void:
	var abs_path := ProjectSettings.globalize_path(PATH)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(abs_path)
	_save([])


static func _save(all_records: Array) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(all_records))
	f = null


