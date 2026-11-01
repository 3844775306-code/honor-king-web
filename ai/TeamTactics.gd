class_name TeamTactics
extends RefCounted
# 4分钟后团队分推协调（集中式，由 BattleManager 统一调用）
# 每10秒/事件触发重算双方队伍任务，结果分发到各 HeroAI

enum SplitMode { DRAGON, FOUR_ONE, ONE_THREE_ONE, DEFEND, PUSH_TOWER, INVADE }

var bm: BattleManager
var current_mode: int = SplitMode.FOUR_ONE
var assignments: Dictionary = {}       # {Hero: int} 映射（兼容旧分路）
var tasks: Dictionary = {}             # {Hero: TeamTask} 团队主线任务
var feedback: Dictionary = {}           # {Hero: HeroAI.task_feedback()}
var task_stats := {"issued": 0, "completed": 0, "failed": 0, "expired": 0, "reassigned": 0}
var _urgent_replan := false
var dragon_pos: Vector3 = Vector3.ZERO
var dragon_pos_by_team: Dictionary = {}  # {int: Vector3} 每队各自最近的龙位置
var defending: Dictionary = {}           # {int: bool} 本秒该队是否收缩防守
var defend_lane_by_team: Dictionary = {} # {int: int} 防守收缩到哪条分路
var push_target_by_team: Dictionary = {} # {int: Vector3} 人数碾压时抱团推塔目标
var invade_target_by_hero: Dictionary = {} # {Hero: Vector3} 人数优势时反野目标
var defend_tower_pos_by_team: Dictionary = {} # {int: Vector3} 10秒内会被小兵攻击的塔
var minion_memory: Dictionary = {} # 敌方小兵最后视野位置，供守塔预测
const MINION_VISION := 14.0
const MINION_THREAT_SECONDS := 10.0

func _init(p_bm: BattleManager) -> void:
	bm = p_bm


func get_mode_name() -> String:
	match current_mode:
		SplitMode.FOUR_ONE: return "4-1分推"
		SplitMode.ONE_THREE_ONE: return "1-3-1分推"
		SplitMode.DRAGON: return "集合打龙"
		SplitMode.DEFEND: return "收缩防守"
		SplitMode.PUSH_TOWER: return "人数碾压抱团推塔"
		SplitMode.INVADE: return "人数优势反野"
	return "未知"


# ==================== 辅助查询 ====================

func _get_ally_heroes(team: int) -> Array[Hero]:
	var result: Array[Hero] = []
	for entity in bm.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team != team:
			continue
		result.append(entity as Hero)
	return result


func _get_enemy_heroes(team: int) -> Array[Hero]:
	var result: Array[Hero] = []
	for entity in bm.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team == team:
			continue
		result.append(entity as Hero)
	return result


func _count_turrets_by_lane(team: int) -> Dictionary:
	var counts := {AiConfig.Lane.FARM: 0, AiConfig.Lane.MID: 0, AiConfig.Lane.CLASH: 0}
	for entity in bm.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != team:
			continue
		var turret := entity as Turret
		if turret.display_name == "crystal":
			continue
		var ln := _get_turret_lane(turret)
		if counts.has(ln):
			counts[ln] = counts[ln] + 1
	return counts


func _get_turret_lane(turret: Turret) -> int:
	var s = turret.global_position.x + turret.global_position.z
	if s > 0:
		return AiConfig.Lane.FARM
	elif s < 0:
		return AiConfig.Lane.CLASH
	else:
		return AiConfig.Lane.MID


func _get_total_team_gold(team: int) -> int:
	var total := 0
	for entity in bm.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity.health <= 0 or entity.team != team:
			continue
		total += (entity as Hero).total_gold_earned
	return total


func _is_dragon_alive() -> bool:
	for entity in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		var m := entity as JungleMonster
		if m.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
			return true
	return false


func _get_nearest_dragon_pos(team: int) -> Vector3:
	var best_pos := Vector3.ZERO
	var best_dist := 9999.0
	# 使用队伍中第一个存活英雄的位置作为参考
	var ref_pos := Vector3.ZERO
	for entity in bm.get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.health > 0 and entity.team == team:
			ref_pos = entity.global_position
			break
	for entity in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		var m := entity as JungleMonster
		if m.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
			if bm.get_bonded_team(m) == team:
				continue   # 原初羁绊：打这只龙伤害减半还会触发怒，不集合
			var dist := ref_pos.distance_to(m.global_position)
			if dist < best_dist:
				best_dist = dist
				best_pos = m.global_position
	return best_pos


func _enemy_team(team: int) -> int:
	return Config.Team.ENEMY if team == Config.Team.PLAYER else Config.Team.PLAYER


# ==================== 防守判定 ====================
# 己方高地为防守核心：水晶告急 / 敌方兵力压到水晶附近 / 经济大幅落后且塔数劣势 → 全队收缩
func _should_defend(team: int) -> bool:
	if _base_threatened(team) or _threatened_tower(team) != null:
		return true
	# 英雄回传：多人残血/需要支援时收缩，而不是只靠经济/塔数全知判断
	var need_help := 0
	for h in feedback:
		if is_instance_valid(h) and int((h as Hero).team) == team and bool((feedback[h] as Dictionary).get("need_help", false)):
			need_help += 1
	if need_help >= 2:
		return true
	var gold_diff := _get_total_team_gold(team) - _get_total_team_gold(_enemy_team(team))
	return gold_diff <= -AiConfig.GOLD_GAP_DEFEND and _count_turrets_total(team) < _count_turrets_total(_enemy_team(team))


func _base_threatened(team: int) -> bool:
	var crystal: Turret = null
	for entity in bm.get_tree().get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0 or entity.team != team:
			continue
		if (entity as Turret).display_name == "crystal":
			crystal = entity as Turret
			break
	if crystal == null:
		return false
	for entity in bm.get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and entity.health > 0 and entity.team != team \
				and entity.global_position.distance_to(crystal.global_position) < 30.0:
			return true
	for entity in bm.get_tree().get_nodes_in_group("minions"):
		if entity is Minion and entity.health > 0 and entity.team != team \
				and entity.global_position.distance_to(crystal.global_position) < 22.0:
			return true
	return false


func _count_turrets_total(team: int) -> int:
	var n := 0
	for entity in bm.get_tree().get_nodes_in_group("turrets"):
		if entity is Turret and entity.health > 0 and entity.team == team \
				and (entity as Turret).display_name != "crystal":
			n += 1
	return n


# 防守分路：己方剩余塔最少（压力最大）的分路
func _defend_lane_for(team: int) -> int:
	var threatened := _threatened_tower(team)
	if threatened != null:
		return _get_turret_lane(threatened)
	var counts := _count_turrets_by_lane(team)
	var best := AiConfig.Lane.MID
	var best_cnt := 9999
	for ln in [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]:
		if int(counts[ln]) < best_cnt:
			best_cnt = int(counts[ln])
			best = ln
	return best


# ==================== 分路选择 ====================

func _get_adjacent_lanes(ln: int) -> Array:
	match ln:
		AiConfig.Lane.FARM: return [AiConfig.Lane.MID]
		AiConfig.Lane.MID: return [AiConfig.Lane.FARM, AiConfig.Lane.CLASH]
		AiConfig.Lane.CLASH: return [AiConfig.Lane.MID]
	return []


func _select_main_lane(team: int) -> int:
	var ally_gold := _get_total_team_gold(team)
	var enemy_gold := _get_total_team_gold(_enemy_team(team))
	var gold_diff := ally_gold - enemy_gold

	if gold_diff >= AiConfig.SPLIT_LEAD_GOLD:
		# 经济领先 ≥ 2000：选敌方塔最多的分路
		var enemy_counts := _count_turrets_by_lane(_enemy_team(team))
		var best_ln := AiConfig.Lane.MID
		var best_cnt := -1
		for ln in [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]:
			if enemy_counts[ln] > best_cnt:
				best_cnt = enemy_counts[ln]
				best_ln = ln
		return best_ln

	elif gold_diff <= -AiConfig.SPLIT_DEFICIT_GOLD:
		# 经济落后 ≥ 300：选己方塔最少的分路（防守）
		var ally_counts := _count_turrets_by_lane(team)
		var best_ln := AiConfig.Lane.MID
		var best_cnt := 9999
		for ln in [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]:
			if ally_counts[ln] < best_cnt:
				best_cnt = ally_counts[ln]
				best_ln = ln
		return best_ln

	else:
		# 随机选择，中路概率 ×2
		var pool: Array[int] = [AiConfig.Lane.MID, AiConfig.Lane.MID, AiConfig.Lane.FARM, AiConfig.Lane.CLASH]
		return pool[randi() % pool.size()]


# ==================== 分推分配 ====================

# 为一个队伍的所有英雄分配分路
func _allocate_team(team: int, mode: int, out_assignments: Dictionary) -> void:
	var heroes := _get_ally_heroes(team)
	if heroes.is_empty():
		return

	var main_lane := _select_main_lane(team)

	match mode:
		SplitMode.FOUR_ONE:
			for h in heroes:
				if not h.is_ai:
					continue
				var role := h.role
				if role in ["坦克", "战士"]:
					var adj := _get_adjacent_lanes(main_lane)
					if adj.size() > 0:
						out_assignments[h] = adj[randi() % adj.size()]
					else:
						out_assignments[h] = main_lane
				else:
					out_assignments[h] = main_lane

		SplitMode.ONE_THREE_ONE:
			# 先确定坦克/战士去的相邻分路
			var tank_lane: int = -1
			for h in heroes:
				if not h.is_ai:
					continue
				if h.role in ["坦克", "战士"]:
					var adj := _get_adjacent_lanes(main_lane)
					if adj.size() > 0:
						tank_lane = adj[randi() % adj.size()]
					else:
						tank_lane = main_lane
					break

			for h in heroes:
				if not h.is_ai:
					continue
				var role := h.role
				if role == "刺客":
					# 刺客 → 未被选择的剩余分路
					var all_lanes := [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]
					var assigned_ln := AiConfig.Lane.FARM
					for ln in all_lanes:
						if ln != main_lane and ln != tank_lane:
							assigned_ln = ln
							break
					out_assignments[h] = assigned_ln
				elif role in ["坦克", "战士"]:
					out_assignments[h] = tank_lane if tank_lane >= 0 else main_lane
				else:
					out_assignments[h] = main_lane



# 开局 0–4 分钟也下发一次基础主线任务：分路/保护射手/打野抓人。
# 之后由英雄层局部策略执行，4 分钟后改由周期性团队指挥官重规划。
func create_initial_tasks() -> Dictionary:
	tasks.clear()
	assignments.clear()
	feedback.clear()
	for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
		for h in _get_ally_heroes(team):
			if not h.is_ai:
				continue
			var ai: HeroAI = null
			for child in h.get_children():
				if child is HeroAI:
					ai = child
					break
			if ai == null:
				continue
			assignments[h] = ai.lane
			tasks[h] = _make_task_for(h, ai.lane)
	return tasks


func update_wave_memory(now: float) -> void:
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion):
			continue
		var m := e as Minion
		if m.health <= 0.0:
			continue
		var key := m.get_instance_id()
		var rec: Dictionary = minion_memory.get(key, {})
		if _minion_visible(m):
			rec = {"node": m, "team": int(m.team), "line": int(m.line),
				"pos": m.global_position, "hp": m.health, "seen": now,
				"speed": maxf(2.0, m.move_speed * 0.01),
				"target": m.current_target, "visible": true}
			minion_memory[key] = rec
		elif not rec.is_empty():
			rec["visible"] = false
	for key in minion_memory.keys():
		var r: Dictionary = minion_memory[key]
		if now - float(r.get("seen", now)) > 15.0:
			minion_memory.erase(key)


func _minion_visible(m: Minion) -> bool:
	for h in _get_ally_heroes(m.team):
		if h.global_position.distance_to(m.global_position) <= MINION_VISION:
			return true
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) == int(m.team) and (e as Turret).health > 0:
			if (e as Node3D).global_position.distance_to(m.global_position) <= MINION_VISION:
				return true
	return false


func _tower_will_be_attacked(team: int, tower: Turret) -> bool:
	if tower == null or tower.health <= 0:
		return false
	if tower.under_attack_timer > 0.0 or tower.health < tower.max_health:
		return true
	var lane := _get_turret_lane(tower)
	for rec in minion_memory.values():
		if int(rec.get("team", -1)) == team:
			continue
		if int(rec.get("line", -1)) != lane:
			continue
		var age := bm.game_time - float(rec.get("seen", bm.game_time))
		if age > 15.0:
			continue
		var pos: Vector3 = rec.get("pos", Vector3.ZERO)
		var d := pos.distance_to(tower.global_position)
		var speed := float(rec.get("speed", 4.0))
		var target = rec.get("target")
		var engaged := target != null and is_instance_valid(target) and int(target.team) == team
		if not engaged:
			for m in bm.get_tree().get_nodes_in_group("minions"):
				if m is Minion and int((m as Minion).team) == team and (m as Minion).health > 0:
					if (m as Node3D).global_position.distance_to(pos) <= 7.0:
						engaged = true
						break
		# 不能只看距离：正在和我方小兵交战的小兵，即使还远也会把兵线推过来。
		if engaged and d <= 22.0:
			return true
		if d <= speed * MINION_THREAT_SECONDS + 2.0:
			return true
	return false


func _threatened_tower(team: int) -> Turret:
	var best: Turret = null
	var best_rank := -1
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) != team or (e as Turret).health <= 0:
			continue
		var t := e as Turret
		if not _tower_will_be_attacked(team, t):
			continue
		var rank := 0
		match t.tower_type:
			"crystal": rank = 4
			"high": rank = 3
			"inner": rank = 2
			_: rank = 1
		if rank > best_rank:
			best_rank = rank
			best = t
	return best


func update_tasks(now: float) -> void:
	for h in tasks.keys():
		var t: TeamTask = tasks[h]
		if t == null or not t.is_active():
			continue
		if not is_instance_valid(h) or (h as Hero).health <= 0:
			_finish_task(t, TeamTask.Status.FAILED)
			continue
		if t.is_expired(now):
			_finish_task(t, TeamTask.Status.EXPIRED)
			continue
		if _task_completed(t, h as Hero, now):
			_finish_task(t, TeamTask.Status.COMPLETED)


func _task_completed(t: TeamTask, h: Hero, now: float) -> bool:
	var dt := maxf(0.1, now - t.last_update)
	t.last_update = now
	match t.type:
		TeamTask.Type.PUSH_LANE:
			if t.lane == AiConfig.Lane.JUNGLE:
				return false
			return not _enemy_tower_near(t.target_pos, 6.0, h.team)
		TeamTask.Type.DEFEND_LANE:
			if _enemies_near(t.target_pos, 12.0, h.team) == 0:
				t.quiet_time += dt
			else:
				t.quiet_time = 0.0
			return t.quiet_time >= 2.5
		TeamTask.Type.OBJECTIVE:
			return not _jungle_monster_near(t.target_pos, 10.0)
		TeamTask.Type.GANK:
			if t.target_hero == null:
				return false
			return not is_instance_valid(t.target_hero) or (t.target_hero as Hero).health <= 0.0
		TeamTask.Type.PEEL:
			if t.target_hero == null or not is_instance_valid(t.target_hero) or (t.target_hero as Hero).health <= 0.0:
				return false
			if _enemies_near((t.target_hero as Node3D).global_position, 7.0, h.team) == 0:
				t.quiet_time += dt
			else:
				t.quiet_time = 0.0
			return t.quiet_time >= 2.5
		TeamTask.Type.PUSH_TOWER:
			return not _enemy_tower_near(t.target_pos, 8.0, h.team)
		TeamTask.Type.INVADE_JUNGLE:
			return not _jungle_monster_near(t.target_pos, 15.0)
		TeamTask.Type.JUNGLE_FARM:
			return not _jungle_monster_near(t.target_pos, 20.0)
		TeamTask.Type.CLEAR_WAVE:
			return not _enemy_minion_near(t.target_pos if t.target_pos != Vector3.ZERO else h.global_position, 20.0, h.team)
	return false


func _enemy_tower_near(pos: Vector3, radius: float, team: int) -> bool:
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) != team and (e as Turret).health > 0:
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				return true
	return false


func _enemies_near(pos: Vector3, radius: float, team: int) -> int:
	var n := 0
	for e in bm.get_tree().get_nodes_in_group("heroes"):
		if e is Hero and int((e as Hero).team) != team and (e as Hero).health > 0:
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				n += 1
	return n


func _enemy_minion_near(pos: Vector3, radius: float, team: int) -> bool:
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if e is Minion and int((e as Minion).team) != team and (e as Minion).health > 0:
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				return true
	return false


func _jungle_monster_near(pos: Vector3, radius: float) -> bool:
	for e in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if e is JungleMonster and (e as JungleMonster).health > 0:
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				return true
	return false


func _finish_task(t: TeamTask, status: int) -> void:
	if not t.is_active():
		return
	t.mark(status)
	match status:
		TeamTask.Status.COMPLETED: task_stats["completed"] += 1
		TeamTask.Status.FAILED: task_stats["failed"] += 1
		TeamTask.Status.EXPIRED: task_stats["expired"] += 1
		TeamTask.Status.REASSIGNED: task_stats["reassigned"] += 1
	var owner := t.owner
	if owner != null and is_instance_valid(owner):
		for child in owner.get_children():
			if child is HeroAI and (child as HeroAI).team_task == t:
				(child as HeroAI).team_task = null
				(child as HeroAI).is_dragon_rally = false
				break


func request_replan() -> void:
	_urgent_replan = true


func consume_replan_request() -> bool:
	var v := _urgent_replan
	_urgent_replan = false
	return v


# 主入口：计算双方队伍的分路分配与 TeamTask
func allocate_all() -> Dictionary:
	_urgent_replan = false
	for old_task in tasks.values():
		_finish_task(old_task, TeamTask.Status.REASSIGNED)
	tasks.clear()
	feedback.clear()
	# 重规划时先收一遍英雄反馈，避免指挥官完全靠全知数据判断。
	for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
		for h in _get_ally_heroes(team):
			if not h.is_ai:
				continue
			for child in h.get_children():
				if child is HeroAI:
					feedback[h] = (child as HeroAI).task_feedback()
					break
	# 根据局势选择分推模式（同一局保持模式连续性，避免每10秒随机换策略）
	var default_mode := SplitMode.FOUR_ONE if randi() % 2 == 0 else SplitMode.ONE_THREE_ONE
	if current_mode == SplitMode.FOUR_ONE or current_mode == SplitMode.ONE_THREE_ONE:
		default_mode = current_mode
	current_mode = default_mode
	dragon_pos_by_team.clear()
	defending.clear()
	defend_lane_by_team.clear()
	defend_tower_pos_by_team.clear()
	push_target_by_team.clear()
	invade_target_by_hero.clear()

	var result: Dictionary = {}
	var dragon_alive := _is_dragon_alive()
	print("[TeamTactics] t=%.0f 龙存活=%s" % [bm.game_time, dragon_alive])

	for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
		var team_label := "玩家方" if team == Config.Team.PLAYER else "敌方"
		var ally_alive := _get_ally_heroes(team).size()
		var enemy_alive := _get_enemy_heroes(team).size()
		# 人数碾压：敌方≤1 且我方≥3，全队放弃分推/打龙，直接抱团推塔。
		if enemy_alive <= 1 and ally_alive >= 3:
			var pt := _push_tower_target(team)
			if pt != Vector3.ZERO:
				current_mode = SplitMode.PUSH_TOWER
				push_target_by_team[team] = pt
				for h in _get_ally_heroes(team):
					if h.is_ai:
						result[h] = ai_lane_of(h)
				print("[TeamTactics] t=%.0f %s 人数碾压 %d:%d，抱团推塔" % [bm.game_time, team_label, ally_alive, enemy_alive])
				continue
		# 防守优先：高地告急 / 大幅落后 → 全队收缩到压力最大的分路
		if _should_defend(team):
			var dl := _defend_lane_for(team)
			var dt := _threatened_tower(team)
			defending[team] = true
			defend_lane_by_team[team] = dl
			defend_tower_pos_by_team[team] = dt.global_position if dt != null else _own_tower_pos(team, dl)
			current_mode = SplitMode.DEFEND
			for h in _get_ally_heroes(team):
				if h.is_ai:
					result[h] = dl
			print("[TeamTactics] t=%.0f %s 进入防守，收缩分路=%d" % [bm.game_time, team_label, dl])
			continue
		# 4分钟后只要人数有优势，就让打野尝试反野（其余人继续分推）。
		if ally_alive > enemy_alive:
			var invader := _find_natural_jungler(team)
			if invader != null:
				current_mode = SplitMode.INVADE
				invade_target_by_hero[invader] = _enemy_jungle_target(team, invader.global_position)
				_allocate_team(team, default_mode, result)
				print("[TeamTactics] t=%.0f %s 人数优势 %d:%d，%s 尝试反野" % [bm.game_time, team_label, ally_alive, enemy_alive, invader.display_name])
				continue
		if dragon_alive:
			var ally_gold := _get_total_team_gold(team)
			var enemy_gold := _get_total_team_gold(_enemy_team(team))
			var gold_diff := ally_gold - enemy_gold
			print("[TeamTactics] t=%.0f %s 经济差=%d (阈值≥%d)" % [bm.game_time, team_label, gold_diff, -AiConfig.DRAGON_GOLD_DEFICIT])
			if ally_gold >= enemy_gold - AiConfig.DRAGON_GOLD_DEFICIT:
				# 本队集合打龙
				current_mode = SplitMode.DRAGON
				dragon_pos_by_team[team] = _get_nearest_dragon_pos(team)
				print("[TeamTactics] t=%.0f %s 触发集合打龙！位置=%s" % [bm.game_time, team_label, dragon_pos_by_team[team]])
				for h in _get_ally_heroes(team):
					if h.is_ai:
						result[h] = AiConfig.Lane.JUNGLE  # 打龙标记
						print("[TeamTactics]   → %s 分配JUNGLE(打龙)" % h.display_name)
				continue  # 本队已分配完毕，跳过正常分推
			else:
				print("[TeamTactics] t=%.0f %s 经济差不足，不打龙" % [bm.game_time, team_label])
		# 不打龙 → 正常分推（使用 default_mode，不受另一队DRAGON影响）
		_allocate_team(team, default_mode, result)

	assignments = result
	# 把分路结果翻译成结构化主线任务；英雄层不再只收到一个 lane。
	for h in result:
		if is_instance_valid(h) and (h as Hero).is_ai:
			tasks[h] = _make_task_for(h, int(result[h]))
	return result


func _make_task_for(h: Hero, lane: int) -> TeamTask:
	var t := TeamTask.new()
	t.owner = h
	task_stats["issued"] += 1
	var now := bm.game_time
	var role := str(h.role)
	if push_target_by_team.has(h.team):
		t.setup(TeamTask.Type.PUSH_TOWER, lane, push_target_by_team[h.team], null, 120, now, 30.0, "人数碾压抱团推塔", role)
		return t
	if invade_target_by_hero.has(h):
		t.setup(TeamTask.Type.INVADE_JUNGLE, lane, invade_target_by_hero[h], null, 95, now, 20.0, "人数优势反野", role)
		return t
	if bool(defending.get(h.team, false)):
		var dl: int = int(defend_lane_by_team.get(h.team, lane))
		var dp: Vector3 = defend_tower_pos_by_team.get(h.team, _own_tower_pos(h.team, dl))
		t.setup(TeamTask.Type.DEFEND_LANE, dl, dp, null, 90, now, 18.0, "守塔", role)
		return t
	if lane == AiConfig.Lane.JUNGLE:
		if _is_dragon_alive():
			var dp: Vector3 = dragon_pos_by_team.get(h.team, dragon_pos)
			t.setup(TeamTask.Type.OBJECTIVE, lane, dp, null, 80, now, 22.0, "集合争夺资源", role)
			return t
		if _is_natural_jungler_of(h):
			t.setup(TeamTask.Type.JUNGLE_FARM, lane, _own_jungle_target(h.team, h.global_position), null, 35, now, 30.0, "刷野发育", role)
			return t
		t.setup(TeamTask.Type.PUSH_LANE, lane, Vector3.ZERO, null, 25, now, 18.0, "刷野/回线", role)
		return t
	if _is_natural_jungler_of(h):
		t.setup(TeamTask.Type.JUNGLE_FARM, lane, _own_jungle_target(h.team, h.global_position), null, 35, now, 30.0, "刷野发育", role)
		return t
	if role == "辅助":
		var guarded := _find_most_endangered_ally(h.team, h)
		if guarded != null:
			t.setup(TeamTask.Type.PEEL, lane, guarded.global_position, guarded, 45, now, 20.0, "支援最危险队友", role)
			return t
	if role == "刺客":
		var gt := _find_gank_target(h.team)
		if gt != null:
			t.setup(TeamTask.Type.GANK, lane, gt.global_position, gt, 55, now, 15.0, "抓我方半图敌人", role)
			return t
		var amb := _find_ambush_pos(h.team)
		if amb != Vector3.ZERO:
			t.setup(TeamTask.Type.AMBUSH, lane, amb, null, 40, now, 18.0, "草丛蹲人", role)
			return t
	var push_pos := _lane_push_pos(h.team, lane)
	t.setup(TeamTask.Type.PUSH_LANE, lane, push_pos, null, 30, now, 25.0, "推进兵线", role)
	return t


func _find_carry(team: int) -> Hero:
	for h in _get_ally_heroes(team):
		if str(h.role) == "射手":
			return h
	return null


func _in_own_half(pos: Vector3, team: int) -> bool:
	var own := Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var enemy := Vector3(53, 0, -53) if team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	return pos.distance_to(own) < pos.distance_to(enemy)


func _find_ambush_pos(team: int) -> Vector3:
	var enemy_crystal := Vector3(53, 0, -53) if team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best := Vector3.ZERO
	var best_d := INF
	for e in bm.get_tree().get_nodes_in_group("bush"):
		if not (e is Node3D):
			continue
		var p: Vector3 = (e as Node3D).global_position
		if not _in_own_half(p, team):
			continue
		var d := p.distance_to(enemy_crystal)
		if d < best_d:
			best_d = d
			best = p
	return best


func _find_gank_target(team: int) -> Hero:
	var best: Hero = null
	var best_score := INF
	for h in _get_enemy_heroes(team):
		if h.is_untargetable_by_enemies() or not _in_own_half(h.global_position, team):
			continue
		var score := h.health / maxf(1.0, h.actual_max_health)
		# 落单优先：附近敌方英雄越少分越低
		var escort := 0
		for e in _get_enemy_heroes(team):
			if e != h and e.global_position.distance_to(h.global_position) <= 10.0:
				escort += 1
		score += float(escort) * 0.25
		if score < best_score:
			best_score = score
			best = h
	return best


func _find_most_endangered_ally(team: int, support: Hero) -> Hero:
	var best: Hero = null
	var best_score := INF
	for h in _get_ally_heroes(team):
		if h == support or str(h.role) == "辅助":
			continue
		var score := h.health / maxf(1.0, h.actual_max_health)
		for e in _get_enemy_heroes(team):
			if e.global_position.distance_to(h.global_position) <= 10.0:
				score -= 0.25
		if score < best_score:
			best_score = score
			best = h
	return best


func ai_lane_of(h: Hero) -> int:
	for child in h.get_children():
		if child is HeroAI:
			return (child as HeroAI).lane
	return AiConfig.Lane.MID


func _find_natural_jungler(team: int) -> Hero:
	for h in _get_ally_heroes(team):
		if _is_natural_jungler_of(h):
			return h
	return null


func _is_natural_jungler_of(h: Hero) -> bool:
	if h == null or not h.is_ai:
		return false
	for child in h.get_children():
		if child is HeroAI and (child as HeroAI)._is_natural_jungler:
			return true
	return false


# 推塔目标：每条路我方兵线前线总血量 >1000 时，选离该前线最近的敌方塔。
# 无合格兵线则不返回目标，避免无兵线送塔。
func _push_tower_target(team: int) -> Vector3:
	var best := Vector3.ZERO
	var best_progress := -INF
	var own_crystal := Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)
	for lane in [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]:
		var info := _lane_front_info(team, lane)
		if float(info.get("hp", 0.0)) <= 1000.0:
			continue
		var front: Vector3 = info.get("pos", Vector3.ZERO)
		var tower := _nearest_tower_in_lane(team, lane, front)
		if tower == null:
			continue
		# 压塔选“有效兵线最靠前”的分路，而不是离塔最近的分路。
		var progress := own_crystal.distance_to(front)
		if progress > best_progress:
			best_progress = progress
			best = tower.global_position
	return best


func _own_jungle_target(team: int, from_pos: Vector3 = Vector3.ZERO) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for p in bm.jungle_camp_positions:
		var pos := p as Vector3
		if BattleManager.in_enemy_jungle_zone(pos, team):
			continue
		var d := from_pos.distance_to(pos) if from_pos != Vector3.ZERO else 0.0
		if d < best_d:
			best_d = d
			best = pos
	return best if best != Vector3.ZERO else (Vector3(-24, 0, 24) if team == Config.Team.PLAYER else Vector3(24, 0, -24))


func _enemy_jungle_target(team: int, from_pos: Vector3 = Vector3.ZERO) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for p in bm.jungle_camp_positions:
		var pos := p as Vector3
		if not BattleManager.in_enemy_jungle_zone(pos, team):
			continue
		var d := from_pos.distance_to(pos) if from_pos != Vector3.ZERO else 0.0
		if d < best_d:
			best_d = d
			best = pos
	return best if best != Vector3.ZERO else (Vector3(24, 0, -24) if team == Config.Team.PLAYER else Vector3(-24, 0, 24))


func _lane_front_info(team: int, lane: int) -> Dictionary:
	var own_crystal := Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var front := Vector3.ZERO
	var front_d := -INF
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) != team or (e as Minion).health <= 0.0:
			continue
		if (e as Minion).line != lane:
			continue
		var d: float = own_crystal.distance_to((e as Node3D).global_position)
		if d > front_d:
			front_d = d
			front = (e as Node3D).global_position
	if front == Vector3.ZERO:
		return {"pos": Vector3.ZERO, "hp": 0.0}
	var hp := 0.0
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if e is Minion and int((e as Minion).team) == team and (e as Minion).health > 0.0:
			if (e as Node3D).global_position.distance_to(front) <= 8.0:
				hp += (e as Minion).health
	return {"pos": front, "hp": hp}


func _nearest_tower_in_lane(team: int, lane: int, from: Vector3) -> Turret:
	var best: Turret = null
	var best_d := INF
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) == team or (e as Turret).health <= 0:
			continue
		if (e as Turret).display_name == "crystal" or _get_turret_lane(e as Turret) != lane:
			continue
		var d: float = from.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = e as Turret
	return best


func _lane_push_pos(team: int, lane: int) -> Vector3:
	var info := _lane_front_info(team, lane)
	if float(info.get("hp", 0.0)) > 1000.0:
		var tower := _nearest_tower_in_lane(team, lane, info["pos"])
		if tower != null:
			return tower.global_position
	if info["pos"] != Vector3.ZERO:
		return info["pos"]
	return _lane_front_pos(team, lane)


func _lane_front_pos(team: int, lane: int) -> Vector3:
	var enemy_crystal := Vector3(53, 0, -53) if team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	var best: Turret = null
	var best_d := 99999.0
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or (e as Turret).health <= 0 or int((e as Turret).team) == team:
			continue
		if _get_turret_lane(e as Turret) != lane:
			continue
		var d: float = (e as Node3D).global_position.distance_to(enemy_crystal)
		if d < best_d:
			best_d = d
			best = e as Turret
	if best != null:
		return best.global_position
	match lane:
		AiConfig.Lane.FARM: return Vector3(30, 0, 30)
		AiConfig.Lane.MID: return Vector3(0, 0, 0)
		AiConfig.Lane.CLASH: return Vector3(-30, 0, -30)
	return Vector3.ZERO


func _own_tower_pos(team: int, lane: int) -> Vector3:
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or (e as Turret).health <= 0 or int((e as Turret).team) != team:
			continue
		if _get_turret_lane(e as Turret) == lane:
			return (e as Node3D).global_position
	match lane:
		AiConfig.Lane.FARM: return Vector3(-40, 0, 40)
		AiConfig.Lane.MID: return Vector3(0, 0, 0)
		AiConfig.Lane.CLASH: return Vector3(40, 0, -40)
	return Vector3.ZERO
