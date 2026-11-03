class_name ThreatModel
extends RefCounted
## 敌方威胁模型：视野记忆 + 血量×距离 + 时间衰减。
## AI 只看得见当前可选中英雄；视野消失后保留最后一次位置/血量，并按时间衰减，
## 不再像旧逻辑一样“草丛/隐身一消失就从世界删掉”。

const MEMORY_MAX_AGE := 15.0
const VISIBLE_GRACE := 0.45

var hero: Hero
var memory: Dictionary = {}       # enemy_instance_id -> {node, pos, hp, max_hp, seen, visible}
var _game_time := 0.0
var _last_update := -1.0


func _init(p_hero: Hero) -> void:
	hero = p_hero


func update(game_time: float) -> void:
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		return
	_game_time = game_time
	var now := Time.get_ticks_msec() * 0.001
	_last_update = now
	var alive_ids := {}
	for e in hero.get_tree().get_nodes_in_group("heroes"):
		if not (e is Hero) or e == hero or int(e.team) == int(hero.team):
			continue
		var h := e as Hero
		if h.is_dead or h.health <= 0.0:
			continue
		var key := h.get_instance_id()
		alive_ids[key] = true
		var rec: Dictionary = memory.get(key, {})
		var visible := not h.is_untargetable_by_enemies()
		if visible:
			rec["node"] = h
			rec["pos"] = h.global_position
			rec["hp"] = h.health
			rec["max_hp"] = maxf(1.0, h.actual_max_health)
			rec["seen"] = now
			rec["visible"] = true
		else:
			rec["visible"] = false
			if rec.is_empty():
				continue
		memory[key] = rec
	# 清理死亡/过期记忆，避免旧视野永久影响判断
	for key in memory.keys():
		if not alive_ids.has(key):
			memory.erase(key)
			continue
		if now - float(memory[key].get("seen", now)) > MEMORY_MAX_AGE:
			memory.erase(key)


func dynamic_radius() -> float:
	return 15.0 + minf(_game_time / 60.0 * 1.5, 6.0)


func visible_enemies() -> Array:
	var out: Array = []
	var now := Time.get_ticks_msec() * 0.001
	for rec in memory.values():
		if bool(rec.get("visible", false)) and now - float(rec.get("seen", 0.0)) <= VISIBLE_GRACE:
			var h = rec.get("node")
			if h != null and is_instance_valid(h) and (h as Hero).health > 0:
				out.append(rec)
	return out


func ally_count_near(radius: float) -> int:
	var n := 0
	for e in hero.get_tree().get_nodes_in_group("heroes"):
		if e == hero or not (e is Hero) or int(e.team) != int(hero.team) or (e as Hero).is_dead:
			continue
		if hero.global_position.distance_to((e as Hero).global_position) <= radius:
			n += 1
	return n


func enemy_count_near(radius: float) -> int:
	var n := 0
	for rec in memory.values():
		if (rec.get("pos", Vector3.ZERO) as Vector3).distance_to(hero.global_position) <= radius:
			n += 1
	return n


## 对当前英雄威胁最大的敌方英雄（与 enemy_threat 同一评分口径）
func most_threatening_enemy() -> Hero:
	var best: Hero = null
	var best_score := 0.0
	var r := dynamic_radius()
	var now := Time.get_ticks_msec() * 0.001
	for rec in memory.values():
		var h = rec.get("node")
		if h == null or not is_instance_valid(h) or not (h is Hero) or (h as Hero).health <= 0.0:
			continue
		var age := maxf(0.0, now - float(rec.get("seen", now)))
		if age > MEMORY_MAX_AGE:
			continue
		var ep: Vector3 = rec.get("pos", Vector3.ZERO)
		if ep.distance_to(hero.global_position) > r:
			continue
		var df := clampf(1.0 - ep.distance_to(hero.global_position) / r, 0.0, 1.0)
		var tf := exp(-age / 5.0)
		var hp_ratio := clampf(float(rec.get("hp", 1.0)) / float(rec.get("max_hp", 1.0)), 0.0, 1.0)
		var score := hp_ratio * df * tf
		if score > best_score:
			best_score = score
			best = h as Hero
	return best


## 敌方威胁总和：血量比例 × 距离系数 × 视野时间衰减。
func enemy_threat(radius: float = -1.0, at_pos: Vector3 = Vector3.ZERO) -> float:
	var r := dynamic_radius() if radius <= 0.0 else radius
	var p := hero.global_position if at_pos == Vector3.ZERO else at_pos
	var now := Time.get_ticks_msec() * 0.001
	var total := 0.0
	for rec in memory.values():
		var age := maxf(0.0, now - float(rec.get("seen", now)))
		if age > MEMORY_MAX_AGE:
			continue
		var ep: Vector3 = rec.get("pos", Vector3.ZERO)
		var dist := p.distance_to(ep)
		if dist > r:
			continue
		var df := clampf(1.0 - dist / r, 0.0, 1.0)
		var tf := exp(-age / 5.0)       # 视野消失越久，威胁越小
		var hp_ratio := clampf(float(rec.get("hp", 1.0)) / float(rec.get("max_hp", 1.0)), 0.0, 1.0)
		total += hp_ratio * df * tf
	return total


func ally_threat(radius: float = -1.0) -> float:
	var r := dynamic_radius() if radius <= 0.0 else radius
	var total := 0.0
	for e in hero.get_tree().get_nodes_in_group("heroes"):
		if not (e is Hero) or int(e.team) != int(hero.team) or (e as Hero).is_dead:
			continue
		var d := hero.global_position.distance_to((e as Hero).global_position)
		if d > r:
			continue
		var df := clampf(1.0 - d / r, 0.0, 1.0)
		var h := e as Hero
		total += clampf(h.health / maxf(1.0, h.actual_max_health), 0.0, 1.0) * df
	return total


## 点是否落在敌方防御塔攻击范围（含安全余量）内
func _in_enemy_tower_reach(p: Vector3) -> bool:
	if hero == null or not is_instance_valid(hero) or hero.get_tree() == null:
		return false
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and (e as Turret).health > 0.0 and int((e as Turret).team) != int(hero.team):
			if p.distance_to((e as Turret).global_position) <= (e as Turret).attack_range * 0.01 + 2.0:
				return true
	return false


## 最近的敌方防御塔位置（无塔返回 ZERO）
func _nearest_enemy_tower_pos(p: Vector3) -> Vector3:
	if hero == null or not is_instance_valid(hero) or hero.get_tree() == null:
		return Vector3.ZERO
	var best := 1.0e9
	var bp := Vector3.ZERO
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and (e as Turret).health > 0.0 and int((e as Turret).team) != int(hero.team):
			var d: float = p.distance_to((e as Turret).global_position)
			if d < best:
				best = d
				bp = (e as Turret).global_position
	return bp


## 点到最近敌方防御塔的距离（无塔返回大数）
func _nearest_enemy_tower_dist(p: Vector3) -> float:
	if hero == null or not is_instance_valid(hero) or hero.get_tree() == null:
		return 1.0e9
	var best := 1.0e9
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and (e as Turret).health > 0.0 and int((e as Turret).team) != int(hero.team):
			best = minf(best, p.distance_to((e as Turret).global_position))
	return best


func threat_balance(radius: float = -1.0) -> float:
	return ally_threat(radius) - enemy_threat(radius)


## 撤退方向：威胁英雄方向 + 附近友方防御塔方向 + 附近敌方防御塔方向的加权和
## 权重规则：威胁值越高 → 威胁英雄权重越高；离防御塔越近 → 该塔权重越高
func retreat_direction() -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	var dir := Vector3.ZERO
	var r := dynamic_radius()
	# 威胁英雄：按威胁值加权，方向为远离该英雄
	for rec in memory.values():
		var age := maxf(0.0, now - float(rec.get("seen", now)))
		if age > MEMORY_MAX_AGE:
			continue
		var ep: Vector3 = rec.get("pos", Vector3.ZERO)
		var d := hero.global_position.distance_to(ep)
		if d > r or d < 0.1:
			continue
		var df := clampf(1.0 - d / r, 0.0, 1.0)
		var tf := exp(-age / 5.0)
		var hp_ratio := clampf(float(rec.get("hp", 1.0)) / float(rec.get("max_hp", 1.0)), 0.0, 1.0)
		var threat := hp_ratio * df * tf
		if threat <= 0.0:
			continue
		var away := hero.global_position - ep
		away.y = 0.0
		if away.length() < 0.1:
			continue
		dir += away.normalized() * threat
	# 防御塔：越近权重越高；友方塔→朝塔，敌方塔→远离塔
	var tower_range := 30.0
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or (e as Turret).health <= 0.0:
			continue
		var tp: Vector3 = (e as Turret).global_position
		var td := hero.global_position.distance_to(tp)
		if td > tower_range or td < 0.1:
			continue
		var w := clampf(1.0 - td / tower_range, 0.0, 1.0)
		if int((e as Turret).team) == int(hero.team):
			var to_t := tp - hero.global_position
			to_t.y = 0.0
			if to_t.length() > 0.1:
				dir += to_t.normalized() * w * 2.5
		else:
			var away_t := hero.global_position - tp
			away_t.y = 0.0
			if away_t.length() > 0.1:
				dir += away_t.normalized() * w * 2.5
	if dir.length() < 0.1:
		return Vector3.ZERO
	return dir.normalized()


## 撤退安全点：沿加权撤退方向前进 6m；无方向返回 ZERO
func safe_position() -> Vector3:
	var dir := retreat_direction()
	if dir == Vector3.ZERO:
		return Vector3.ZERO
	var dest := hero.global_position + dir * 6.0
	var half := Config.MAP_SIZE / 2.0
	dest.x = clampf(dest.x, -half, half)
	dest.z = clampf(dest.z, -half, half)
	return dest

