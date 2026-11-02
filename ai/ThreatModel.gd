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


func threat_balance(radius: float = -1.0) -> float:
	return ally_threat(radius) - enemy_threat(radius)


## 从当前威胁质心向外找安全方向；找不到威胁返回 ZERO。
func safe_position() -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	var weighted := Vector3.ZERO
	var weight := 0.0
	for rec in memory.values():
		var age := maxf(0.0, now - float(rec.get("seen", now)))
		if age > MEMORY_MAX_AGE:
			continue
		var ep: Vector3 = rec.get("pos", Vector3.ZERO)
		var d := hero.global_position.distance_to(ep)
		if d > dynamic_radius() or d < 0.1:
			continue
		var w := (1.0 - d / dynamic_radius()) * exp(-age / 5.0)
		weighted += ep * w
		weight += w
	if weight <= 0.001:
		return Vector3.ZERO
	var centroid := weighted / weight
	var away := hero.global_position - centroid
	away.y = 0.0
	if away.length() < 0.2:
		# 被完全贴身：沿远离地图中心的方向退
		away = Vector3(hero.global_position.x, 0.0, hero.global_position.z).normalized()
	if away.length() < 0.1:
		return Vector3.ZERO
	var dest := hero.global_position + away.normalized() * 6.0
	var half := Config.MAP_SIZE / 2.0
	dest.x = clampf(dest.x, -half, half)
	dest.z = clampf(dest.z, -half, half)
	return dest

