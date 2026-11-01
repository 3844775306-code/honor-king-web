extends Node
## 对局录像（P1）：每 0.1s 采英雄/塔、每 0.3s 采小兵 + 击杀/推塔事件，对局结束写 user://replays/*.rep（zstd 压缩 JSON）
## 回放只重建「视觉」，不跑战斗逻辑，所以不会因为随机数/版本差异失真。
## 创建：BattleManager._create_player_hero() 里 ReplayScript.ensure(self)

const GROUP := "replay_recorder"
const DIR := "user://replays"
const DEV_DIR := "res://replays"          # user:// 不可写时（沙箱/只读环境）退到工程目录
const INDEX_PATH := "user://replays/index.json"
const DEV_INDEX := "res://replays/index.json"
const SAMPLE_HZ := 10.0
const MINI_HZ := 3.0
const MAX_FRAMES := 9000        # 最多录 15 分钟
const MAX_REPLAYS := 20         # 环形覆盖
const VERSION := 1

const TYPE_CODE := {
	"melee": 0, "ranged": 1, "siege": 2, "super": 3,
	"dragon": 4, "storm": 5, "shadow_dragon": 6,
}

var bm = null
var _acc := 0.0
var _mini_acc := 0.0
var _hero_ids := {}          # instance_id -> index
var _hero_meta: Array = []   # [{name, team, ai, nick, color}]
var _turret_meta: Array = [] # [{x, z, team, type, maxhp}]
var _turret_ids := {}
var _frames: Array = []      # [{t:int(ms), h:[[x,z,y,yaw,hp,maxhp,lvl,flags]...], tn:[[hp,alive]...]}]
var _mini_frames: Array = [] # [{t, m:[[id,x,z,hp,team,type]...]}]
var _mini_ids := {}
var _mini_next_id := 0
var _events: Array = []      # [{t,k,a,b,x,z,team}]
var _jungle_meta: Array = [] # [{name,x,z,maxhp}]
var _jungle_ids := {}
var _jungle_frames: Array = []  # [{t, j:[[id,x,z,hp]...]}]
var _map_meta: Dictionary = {}  # {walls:[[x,z,ry,hq,outer,olen,pillar,cont,thick]...], bushes:[[x,z,ry]...]}
var _map_captured := false
var _atk_last := {}          # hero_name -> 上次记录普攻的游戏时间（限流）
var _bullet_ids := {}        # 子弹 instance_id -> 录像内 id
var _bullet_next_id := 0
var _bullet_frames: Array = []  # [{t, b:[[id,x,z,team,r,g,bl,radius]...]}]
var _popup_events: Array = []   # [{t,k:"pop",p:kind,x,y,z,d:{...}}]
var _audio_events: Array = []   # [{t,k:"sfx"/"ann",key}]
const AUDIO_MAX := 40000
const POPUP_MAX := 30000
var _last_kills: Array = []
var _last_levels: Array = []
var _last_deaths: Array = []
var _last_turrets_alive := -1
var _last_crystal := -1
var _finished := false
var _saved := false
var _partial := false
var _grace := 0.0
var _started := false
var _t0 := 0.0


static func ensure(bm_node) -> Node:
	if bm_node == null or not is_instance_valid(bm_node):
		return null
	var found = bm_node.get_tree().get_first_node_in_group(GROUP)
	if found != null:
		return found
	var rec = load("res://scripts/core/ReplayRecorder.gd").new()
	rec.name = "ReplayRecorder"
	bm_node.add_child(rec)
	return rec


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	if _saved:
		return
	if bm == null or not is_instance_valid(bm):
		bm = get_tree().get_first_node_in_group("battle_manager")
		if bm == null:
			return
	if not _started:
		_try_start()
		if not _started:
			return
	# 对局结束：留 1.2s 收尾（水晶爆炸/结算），然后落盘
	if bool(bm.get("game_over")):
		if not _finished:
			_finished = true
			_grace = 0.0
		_grace += delta
		_sample(delta, true)
		if _grace >= 1.2:
			_save()
		return
	_sample(delta, false)


func _exit_tree() -> void:
	# 中途退出/投降：还没落盘就把已有的片段存成“中途退出”录像
	if _saved or not _started:
		return
	if _frames.size() < 60:
		return
	_partial = true
	_save()


func _try_start() -> void:
	var heroes := get_tree().get_nodes_in_group("heroes")
	var order: Array = []
	for h in heroes:
		if h is Hero:
			order.append(h)
	var gt: float = float(bm.get("game_time"))
	# 5v5 要等 10 人都进场（否则敌方英雄不会出现在录像里）；兜底：开局 3 秒后有多少录多少
	if order.size() < 10 and gt < 3.0:
		return
	if order.size() < 2:
		return
	# 玩家方排前（便于 UI 显示“我方”），其余按实例顺序
	order.sort_custom(func(a, b) -> bool:
		var aa: bool = Config.is_ally(int(a.team))
		var bb: bool = Config.is_ally(int(b.team))
		if aa != bb:
			return aa
		return int(a.get_instance_id()) < int(b.get_instance_id()))
	for i in range(order.size()):
		var h: Hero = order[i]
		_hero_ids[h.get_instance_id()] = i
		var _sd: Array = []
		for _si in range(5):
			var _tot := 1.0
			if _si < h.skills.size() and h.skills[_si] != null:
				_tot = maxf(0.001, float(h.skills[_si].cooldown))
			elif _si == 3 and h.summoner_skill != null:
				_tot = maxf(0.001, float(h.summoner_skill.cooldown))
			elif _si == 4 and h.skills.size() > 4 and h.skills[4] != null:
				_tot = maxf(0.001, float(h.skills[4].cooldown))
			_sd.append(_tot)
		_hero_meta.append({
			"name": str(h.display_name),
			"team": int(h.team),
			"ai": bool(h.is_ai),
			"nick": str(h.player_name),
			"sd": _sd,
		})
		_last_kills.append(int(h.kills))
		_last_levels.append(int(h.level))
		_last_deaths.append(int(h.deaths))
	_started = true
	_t0 = float(bm.get("game_time"))
	_last_turrets_alive = _turret_alive()
	_last_crystal = _crystal_alive()


func _sample(delta: float, finishing: bool) -> void:
	if _frames.size() >= MAX_FRAMES:
		return
	_acc += delta
	if _acc < 1.0 / SAMPLE_HZ:
		return
	_acc = 0.0
	var t_ms: int = int(round(float(bm.get("game_time")) * 1000.0))
	_discover_turrets()
	if not _map_captured:
		_capture_map()
	_discover_jungle()
	var hero_row: Array = []
	for i in range(_hero_meta.size()):
		hero_row.append([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, "", 0])
	for h in get_tree().get_nodes_in_group("heroes"):
		if not (h is Hero):
			continue
		var idx = _hero_ids.get(h.get_instance_id())
		if idx == null:
			continue
		var p: Vector3 = h.global_position
		var hp: int = maxi(0, int(round(h.health)))
		var flags := 0
		if hp > 0:
			flags |= 1
		if h.has_method("is_invisible_to_enemy") and bool(h.is_invisible_to_enemy()):
			flags |= 2
		var _cds: Array = []
		for _ci in range(5):
			_cds.append(int(round(float(h.skill_cooldowns[_ci]) * 100.0)) if _ci < h.skill_cooldowns.size() else 0)
		hero_row[idx] = [
			int(round(p.x * 100.0)), int(round(p.z * 100.0)), int(round(p.y * 100.0)),
			int(round(rad_to_deg(h.rotation.y))),
			hp, int(round(h.max_health)), int(h.level), flags,
			int(round(h.mana)), int(round(h.max_mana)), int(h.exp), int(maxi(1, h.exp_to_next)),
			int(h.kills), int(h.deaths), int(h.assists),
			int(round(h.actual_attack_damage)), int(round(h.ability_power)),
			int(round(h.actual_armor)), int(round(h.actual_magic_resist)),
			int(round(h.actual_move_speed * 10.0)), int(round(float(h.attack_speed) * 100.0)),
			_cds[0], _cds[1], _cds[2], _cds[3], _cds[4],
			int(h.skill_levels[0]) if h.skill_levels.size() > 0 else 0,
			int(h.skill_levels[1]) if h.skill_levels.size() > 1 else 0,
			int(h.skill_levels[2]) if h.skill_levels.size() > 2 else 0,
			int(h.skill_levels[3]) if h.skill_levels.size() > 3 else 0,
			int(round(h.shield_remaining * 10.0)),
			int(round(h.stun_timer * 100.0)), int(round(h.knockup_timer * 100.0)),
			int(round(h.froze_timer * 100.0)), int(round(h.suppress_timer * 100.0)),
			int(round(h.silence_timer * 100.0)), int(round(h.slow_timer * 100.0)),
			int(round(h.slow_amount * 100.0)), int(round(h.bt_timer * 100.0)),
			int(round(h.wd_timer * 100.0)), int(round(h.revive_timer * 100.0)),
			_markers_to_str(h),
			1 if h.is_mvp else 0,
		]
		# 事件：升级
		if idx < _last_levels.size() and int(h.level) > int(_last_levels[idx]):
			_events.append({"t": t_ms, "k": "lvl", "a": int(idx)})
			_last_levels[idx] = int(h.level)
		# 事件：击杀 / 阵亡
		if idx < _last_kills.size():
			if int(h.kills) > int(_last_kills[idx]):
				_events.append({"t": t_ms, "k": "k", "a": int(idx)})
				_last_kills[idx] = int(h.kills)
			if int(h.deaths) > int(_last_deaths[idx]):
				_events.append({"t": t_ms, "k": "d", "a": int(idx)})
				_last_deaths[idx] = int(h.deaths)
	# 子弹（普攻/直线技能弹道）：10Hz 采样，回放里插值移动
	var brows: Array = []
	for b in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(b):
			continue
		var bid = _bullet_ids.get(b.get_instance_id())
		if bid == null:
			bid = _bullet_next_id
			_bullet_next_id += 1
			_bullet_ids[b.get_instance_id()] = bid
		var bp2: Vector3 = b.global_position
		var cr := 1.0
		var cg := 1.0
		var cb := 1.0
		var src = b.get("source")
		if src is Hero and is_instance_valid(src):
			var cc: Color = Vfx.color_for_hero(str(src.display_name))
			cr = cc.r
			cg = cc.g
			cb = cc.b
		elif src is Turret or src is Minion:
			var tcol2: Color = Color(0.0, 0.886, 1.0) if Config.is_ally(int(b.team)) else Color(1.0, 0.33, 0.264)
			cr = tcol2.r
			cg = tcol2.g
			cb = tcol2.b
		brows.append([int(bid), int(round(bp2.x * 100.0)), int(round(bp2.z * 100.0)), int(b.team),
			snappedf(cr, 0.01), snappedf(cg, 0.01), snappedf(cb, 0.01), snappedf(float(b.get("radius")), 0.01)])
	_bullet_frames.append({"t": t_ms, "b": brows})
	# 塔血量（顺序与 meta 一致）
	var trow: Array = []
	trow.resize(_turret_meta.size())
	for i in range(trow.size()):
		trow[i] = [0, 0]
	for t in get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret):
			continue
		var tidx = _turret_ids.get(t.get_instance_id())
		if tidx == null:
			continue
		var hp2: int = maxi(0, int(round(t.health)))
		trow[int(tidx)] = [hp2, 1 if hp2 > 0 else 0]
	_frames.append({
		"t": t_ms, "h": hero_row, "tn": trow,
		"g": [int(round(float(bm.get("team_player_gold")))), int(round(float(bm.get("team_enemy_gold"))))],
	})
	# 推塔 / 水晶事件
	var alive_now := _turret_alive()
	if _last_turrets_alive >= 0 and alive_now < _last_turrets_alive:
		_events.append({"t": t_ms, "k": "tower", "b": _last_turrets_alive - alive_now})
		_last_turrets_alive = alive_now
	var cry := _crystal_alive()
	if _last_crystal >= 0 and cry < _last_crystal:
		_events.append({"t": t_ms, "k": "crystal"})
		_last_crystal = cry
	if finishing:
		pass
	# 小兵（3Hz）
	_mini_acc += 1.0 / SAMPLE_HZ
	if _mini_acc >= 1.0 / MINI_HZ:
		_mini_acc = 0.0
		var rows: Array = []
		for m in get_tree().get_nodes_in_group("minions"):
			if not is_instance_valid(m) or m.health <= 0:
				continue
			var mid = _mini_ids.get(m.get_instance_id())
			if mid == null:
				mid = _mini_next_id
				_mini_next_id += 1
				_mini_ids[m.get_instance_id()] = mid
			var mp: Vector3 = m.global_position
			rows.append([
				int(mid), int(round(mp.x * 100.0)), int(round(mp.z * 100.0)),
				maxi(0, int(round(m.health))), int(m.team),
				int(TYPE_CODE.get(str(m.display_name), 0)), int(round(m.max_health)),
			])
		_mini_frames.append({"t": t_ms, "m": rows})
		var jrows: Array = []
		for j in get_tree().get_nodes_in_group("jungle_monsters"):
			if not is_instance_valid(j):
				continue
			var jid = _jungle_ids.get(j.get_instance_id())
			if jid == null:
				continue
			var jp: Vector3 = j.global_position
			jrows.append([int(jid), int(round(jp.x * 100.0)), int(round(jp.z * 100.0)), maxi(0, int(round(j.health)))])
		_jungle_frames.append({"t": t_ms, "j": jrows})


## 技能出手（Hero._finish_cast 里调用）：记下英雄/槽位/落点/朝向 + 表现所需技能字段
## 飘字（伤害/治疗/金币）：由 UI_Manager 的三个飘字函数在真实对局中回调
func note_popup(kind: String, pos: Vector3, data: Dictionary) -> void:
	if _saved or not _started:
		return
	if _popup_events.size() >= POPUP_MAX:
		return
	var gt: float = float(bm.get("game_time")) if bm != null and is_instance_valid(bm) else 0.0
	_popup_events.append({
		"t": int(round(gt * 1000.0)), "k": "pop", "p": str(kind),
		"x": int(round(pos.x * 100.0)), "y": int(round(pos.y * 100.0)), "z": int(round(pos.z * 100.0)),
		"d": data,
	})


func note_cast(hero_name: String, slot: int, caster_pos: Vector3, target_pos: Vector3,
		facing: Vector3, skill) -> void:
	if _saved or not _started:
		return
	var gt: float = float(bm.get("game_time")) if bm != null and is_instance_valid(bm) else 0.0
	var skd: Dictionary = {}
	if skill != null:
		skd = {
			"type": int(skill.type),
			"radius": float(skill.radius),
			"duration": float(skill.duration),
			"self_displacement": float(skill.self_displacement),
			"is_channeling": bool(skill.is_channeling),
		}
	_events.append({
		"t": int(round(gt * 1000.0)), "k": "cast", "n": str(hero_name), "s": int(slot),
		"cx": int(round(caster_pos.x * 100.0)), "cz": int(round(caster_pos.z * 100.0)),
		"tx": int(round(target_pos.x * 100.0)), "tz": int(round(target_pos.z * 100.0)),
		"fx": snappedf(facing.x, 0.001), "fz": snappedf(facing.z, 0.001),
		"sk": skd,
	})


## 普攻出手（Hero._perform_attack 里调用）：按英雄限流，避免每帧刷爆事件表
func note_attack(hero_name: String, from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	if _saved or not _started:
		return
	var gt: float = float(bm.get("game_time")) if bm != null and is_instance_valid(bm) else 0.0
	var last: float = float(_atk_last.get(hero_name, -99.0))
	if gt - last < 0.12:
		return
	_atk_last[hero_name] = gt
	_events.append({
		"t": int(round(gt * 1000.0)), "k": "atk", "n": str(hero_name),
		"cx": int(round(from_pos.x * 100.0)), "cz": int(round(from_pos.z * 100.0)),
		"tx": int(round(to_pos.x * 100.0)), "tz": int(round(to_pos.z * 100.0)),
		"cr": snappedf(color.r, 0.01), "cg": snappedf(color.g, 0.01), "cb": snappedf(color.b, 0.01),
	})


func _markers_to_str(h) -> String:
	var parts: Array = []
	for src in h.get_marker_sources():
		if src == null or not is_instance_valid(src):
			continue
		var cnt: int = int(h.count_markers(src))
		if cnt > 0:
			parts.append("%s:%d" % [str(src.display_name), cnt])
	return "|".join(parts)


## 音效打点（SfxManager 调用）：回放时重播同一组合成音
func note_sfx(key: String, vol_offset: float = 0.0, is_ann: bool = false) -> void:
	if _saved or not _started:
		return
	if _audio_events.size() >= AUDIO_MAX:
		return
	var gt: float = float(bm.get("game_time")) if bm != null and is_instance_valid(bm) else 0.0
	_audio_events.append({"t": int(round(gt * 1000.0)), "k": "ann" if is_ann else "sfx",
		"key": str(key), "v": snappedf(vol_offset, 0.01)})


func _capture_map() -> void:
	var walls: Array = []
	for w in get_tree().get_nodes_in_group("walls"):
		if not is_instance_valid(w):
			continue
		walls.append([
			snappedf(w.global_position.x, 0.01), snappedf(w.global_position.z, 0.01),
			snappedf(w.rotation.y, 0.0001),
			int(w.get("hq") if w.get("hq") != null else 0),
			int(w.get("outer") if w.get("outer") != null else 0),
			float(w.get("outer_len") if w.get("outer_len") != null else 2.0),
			int(w.get("pillar") if w.get("pillar") != null else 0),
			float(w.get("continuous_len") if w.get("continuous_len") != null else 0.0),
			float(w.get("thick") if w.get("thick") != null else 1.0),
		])
	var bushes: Array = []
	for b in get_tree().get_nodes_in_group("bush"):
		if not is_instance_valid(b):
			continue
		bushes.append([
			snappedf(b.global_position.x, 0.01), snappedf(b.global_position.z, 0.01),
			snappedf(b.rotation.y, 0.0001),
		])
	if walls.is_empty() and bushes.is_empty():
		return
	_map_meta = {"walls": walls, "bushes": bushes}
	_map_captured = true


func _discover_jungle() -> void:
	for j in get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(j):
			continue
		if _jungle_ids.has(j.get_instance_id()):
			continue
		_jungle_ids[j.get_instance_id()] = _jungle_meta.size()
		_jungle_meta.append({
			"name": str(j.display_name),
			"x": int(round(j.global_position.x * 100.0)),
			"z": int(round(j.global_position.z * 100.0)),
			"maxhp": int(round(j.max_health)),
		})


func _discover_turrets() -> void:
	for t in get_tree().get_nodes_in_group("turrets"):
		if t is Turret:
			if not _turret_ids.has(t.get_instance_id()):
				_turret_ids[t.get_instance_id()] = _turret_meta.size()
				_turret_meta.append({
					"x": int(round(t.global_position.x * 100.0)),
					"z": int(round(t.global_position.z * 100.0)),
					"team": int(t.team),
					"type": str(t.display_name),
					"maxhp": int(round(t.max_health)),
				})
	if _last_turrets_alive < 0:
		_last_turrets_alive = _turret_alive()
	if _last_crystal < 0:
		_last_crystal = _crystal_alive()


func _turret_alive() -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("turrets"):
		if t is Turret and t.health > 0:
			n += 1
	return n


func _crystal_alive() -> int:
	var n := 0
	for t in get_tree().get_nodes_in_group("turrets"):
		if t is Turret and str(t.display_name) == "crystal" and t.health > 0:
			n += 1
	return n


func _save() -> void:
	_saved = true
	if _frames.size() < 20:
		queue_free()
		return
	var dir := DirAccess.open(DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace("-", "").replace(":", "").replace(" ", "_")
	var path := "%s/r_%s.rep" % [DIR, stamp]
	var my_rows: Array = []
	for i in range(_hero_meta.size()):
		var meta: Dictionary = _hero_meta[i]
		if not bool(meta.get("ai", true)):
			my_rows.append(i)
	var duration: float = 0.0
	if not _frames.is_empty():
		duration = float(int(_frames[_frames.size() - 1]["t"])) / 1000.0
	var winner: int = int(bm.get("winner")) if bm != null and is_instance_valid(bm) else -1
	var doc := {
		"v": VERSION,
		"meta": {
			"time": stamp, "duration": duration,
			"winner": winner,
			"player_team": int(Config.player_team),
			"mode": "联机" if NetSession.mode != NetSession.Mode.NONE else "单机",
			"hero_count": _hero_meta.size(),
			"me": my_rows[0] if my_rows.size() > 0 else 0,
			"partial": 1 if _partial else 0,
		},
		"heroes": _hero_meta,
		"turrets": _turret_meta,
		"frames": _frames,
		"minions": _mini_frames,
		"jungle": _jungle_frames,
		"bullets": _bullet_frames,
		"popups": _popup_events,
		"audio": _audio_events,
		"jungle_meta": _jungle_meta,
		"map": _map_meta,
		"events": _events,
	}
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		# 退到工程目录（沙箱/只读环境）；正式环境正常写 user://
		var dev_dir := DirAccess.open(DEV_DIR)
		if dev_dir == null:
			DirAccess.make_dir_recursive_absolute(DEV_DIR)
		path = "%s/r_%s.rep" % [DEV_DIR, stamp]
		f = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		print("[REPLAY] 写盘失败: ", path)
		queue_free()
		return
	f.store_string(JSON.stringify(doc))
	f.close()
	_append_index(path, doc)
	print("[REPLAY] 已保存 %s  时长 %.0fs  帧 %d" % [path, duration, _frames.size()])
	queue_free()


static func _append_index(path: String, doc: Dictionary) -> void:
	var arr: Array = load_index()
	var meta: Dictionary = doc.get("meta", {})
	var heroes: Array = doc.get("heroes", [])
	var me: int = int(meta.get("me", 0))
	var my: Dictionary = heroes[me] if me >= 0 and me < heroes.size() else {}
	arr.push_front({
		"file": path,
		"time": str(meta.get("time", "")),
		"duration": float(meta.get("duration", 0.0)),
		"mode": str(meta.get("mode", "")),
		"hero": str(my.get("name", "")),
		"nick": str(my.get("nick", "")),
		"winner": int(meta.get("winner", -1)),
		"player_team": int(meta.get("player_team", 0)),
		"partial": int(meta.get("partial", 0)),
		"size": FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0,
	})
	while arr.size() > MAX_REPLAYS:
		var drop: Dictionary = arr.pop_back()
		_delete_file(str(drop.get("file", "")))
	_write_index(arr)


static func _delete_file(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func load_index() -> Array:
	var txt := ""
	for p in [INDEX_PATH, DEV_INDEX]:
		var f := FileAccess.open(p, FileAccess.READ)
		if f != null:
			txt = f.get_as_text()
			f.close()
			break
	if txt == "":
		return []
	var data = JSON.parse_string(txt)
	return data if data is Array else []


static func _write_index(arr: Array) -> void:
	var f := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if f == null:
		var d := DirAccess.open(DEV_DIR)
		if d == null:
			DirAccess.make_dir_recursive_absolute(DEV_DIR)
		f = FileAccess.open(DEV_INDEX, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arr))
		f.close()


static func delete_replay(entry: Dictionary) -> void:
	var arr: Array = load_index()
	var out: Array = []
	for e in arr:
		if str(e.get("file", "")) != str(entry.get("file", "")):
			out.append(e)
	_delete_file(str(entry.get("file", "")))
	_write_index(out)


## 导出录像（分享用）：优先存到桌面，其次 user://exports，最后工程目录
static func export_replay(entry: Dictionary) -> String:
	var src := str(entry.get("file", ""))
	if src == "" or not FileAccess.file_exists(src):
		return ""
	var stamp := str(entry.get("time", "")) if str(entry.get("time", "")) != "" else "replay"
	var name := "HonorKing_%s.rep" % stamp
	var dirs: Array = []
	var desk := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if desk != "":
		dirs.append(desk)
	dirs.append("user://exports")
	dirs.append("res://exports")
	var data := FileAccess.get_file_as_bytes(src)
	for d in dirs:
		if not DirAccess.dir_exists_absolute(d):
			DirAccess.make_dir_recursive_absolute(d)
		var dst := str(d).path_join(name)
		var f := FileAccess.open(dst, FileAccess.WRITE)
		if f != null:
			f.store_buffer(data)
			f.close()
			return dst
	return ""


static func load_replay(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	return data if data is Dictionary else {}
