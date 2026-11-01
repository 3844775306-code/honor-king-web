class_name TeamTactics
extends RefCounted
# 4分钟后团队分推协调（集中式，由 BattleManager 统一调用）
# 每10秒/事件触发重算双方队伍任务，结果分发到各 HeroAI

enum SplitMode { DRAGON, FOUR_ONE, ONE_THREE_ONE, DEFEND }

var bm: BattleManager
var current_mode: int = SplitMode.FOUR_ONE
var assignments: Dictionary = {}       # {Hero: int} 映射（兼容旧分路）
var tasks: Dictionary = {}             # {Hero: TeamTask} 团队主线任务
var feedback: Dictionary = {}           # {Hero: HeroAI.task_feedback()}
var _urgent_replan := false
var dragon_pos: Vector3 = Vector3.ZERO
var dragon_pos_by_team: Dictionary = {}  # {int: Vector3} 每队各自最近的龙位置
var defending: Dictionary = {}           # {int: bool} 本秒该队是否收缩防守
var defend_lane_by_team: Dictionary = {} # {int: int} 防守收缩到哪条分路

func _init(p_bm: BattleManager) -> void:
	bm = p_bm


func get_mode_name() -> String:
	match current_mode:
		SplitMode.FOUR_ONE: return "4-1分推"
		SplitMode.ONE_THREE_ONE: return "1-3-1分推"
		SplitMode.DRAGON: return "集合打龙"
		SplitMode.DEFEND: return "收缩防守"
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
	if _base_threatened(team):
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


func request_replan() -> void:
	_urgent_replan = true


func consume_replan_request() -> bool:
	var v := _urgent_replan
	_urgent_replan = false
	return v


# 主入口：计算双方队伍的分路分配与 TeamTask
func allocate_all() -> Dictionary:
	_urgent_replan = false
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

	var result: Dictionary = {}
	var dragon_alive := _is_dragon_alive()
	print("[TeamTactics] t=%.0f 龙存活=%s" % [bm.game_time, dragon_alive])

	for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
		var team_label := "玩家方" if team == Config.Team.PLAYER else "敌方"
		# 防守优先：高地告急 / 大幅落后 → 全队收缩到压力最大的分路
		if _should_defend(team):
			var dl := _defend_lane_for(team)
			defending[team] = true
			defend_lane_by_team[team] = dl
			current_mode = SplitMode.DEFEND
			for h in _get_ally_heroes(team):
				if h.is_ai:
					result[h] = dl
			print("[TeamTactics] t=%.0f %s 进入防守，收缩分路=%d" % [bm.game_time, team_label, dl])
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
	var now := bm.game_time
	var role := str(h.role)
	if lane == AiConfig.Lane.JUNGLE:
		# 开局/龙未刷新时只是“继续刷野”，不能把所有打野都派去一个不存在的龙坑。
		if not _is_dragon_alive():
			t.setup(TeamTask.Type.PUSH_LANE, lane, Vector3.ZERO, null, 25, now, 18.0, "刷野/回线", role)
			return t
		var dp: Vector3 = dragon_pos_by_team.get(h.team, dragon_pos)
		t.setup(TeamTask.Type.OBJECTIVE, lane, dp, null, 80, now, 22.0, "集合争夺资源", role)
		return t
	if bool(defending.get(h.team, false)):
		var dl: int = int(defend_lane_by_team.get(h.team, lane))
		t.setup(TeamTask.Type.DEFEND_LANE, dl, _own_tower_pos(h.team, dl), null, 90, now, 18.0, "防守压力分路", role)
		return t
	if role == "辅助":
		var carry := _find_carry(h.team)
		if carry != null:
			t.setup(TeamTask.Type.PEEL, lane, carry.global_position, carry, 45, now, 20.0, "保护射手", role)
			return t
	if role == "刺客" and current_mode == SplitMode.ONE_THREE_ONE:
		var gp := _lane_front_pos(h.team, lane)
		t.setup(TeamTask.Type.GANK, lane, gp, null, 55, now, 15.0, "抓单/切后", role)
		return t
	var push_pos := _lane_front_pos(h.team, lane)
	t.setup(TeamTask.Type.PUSH_LANE, lane, push_pos, null, 30, now, 25.0, "推进兵线", role)
	return t


func _find_carry(team: int) -> Hero:
	for h in _get_ally_heroes(team):
		if str(h.role) == "射手":
			return h
	return null


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
