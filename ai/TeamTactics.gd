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
var push_lane_by_team: Dictionary = {} # {int: int} 抱团推塔采用的分路
var invade_target_by_hero: Dictionary = {} # {Hero: Vector3} 人数优势时反野目标
var defend_assignees: Dictionary = {} # {Hero: bool} 守塔任务实际接取者
var defend_target_by_team: Dictionary = {} # {int: Vector3} 水晶位置
var gank_target_by_hero: Dictionary = {} # {Hero: Hero} 抓人接取者 -> 目标
var _push_gold_cd_until: Dictionary = {}   # {int: float} 经济差推塔冷却结束时间
var _push_dragon_cd_until: Dictionary = {} # {int: float} 打龙后推塔冷却结束时间
var _force_push_by_team: Dictionary = {}   # {int: bool} 本次推塔是否经济差触发（高优先级）

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
	return _enemy_minions_near_crystal(team, 30.0).size() > 0


## 任一方水晶 30m 内出现敌方小兵（供对局主循环在 4 分钟前也触发应急回防）
func has_crystal_threat() -> bool:
	return _should_defend(Config.Team.PLAYER) or _should_defend(Config.Team.ENEMY)


func _crystal_of(team: int) -> Turret:
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) == team and (e as Turret).health > 0 \
				and (e as Turret).display_name == "crystal":
			return e as Turret
	return null


func _enemy_minions_near_crystal(team: int, radius: float) -> Array:
	var crystal := _crystal_of(team)
	var out: Array = []
	if crystal == null:
		return out
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if e is Minion and int((e as Minion).team) != team and (e as Minion).health > 0:
			if (e as Node3D).global_position.distance_to(crystal.global_position) <= radius:
				out.append(e)
	return out


func _defend_assignees(team: int) -> Array:
	var crystal := _crystal_of(team)
	if crystal == null:
		return []
	var enemy_heroes := 0
	for e in _get_enemy_heroes(team):
		if e.global_position.distance_to(crystal.global_position) <= 20.0:
			enemy_heroes += 1
	# 水晶被小兵压境时至少 2 人回防；敌方英雄越多，回防人数继续增加
	var max_n := 2 + enemy_heroes
	var candidates := []
	for h in _get_ally_heroes(team):
		if h.is_ai:
			candidates.append(h)
	candidates.sort_custom(func(a, b):
		return a.global_position.distance_to(crystal.global_position) < b.global_position.distance_to(crystal.global_position))
	if candidates.size() > max_n:
		return candidates.slice(0, max_n)
	return candidates


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
			# 4分钟后 1-3-1：优先选择「敌方小兵离自己最近」的分路；
			# 某条路没有敌方小兵时，才回退到主路/相邻路角色分配。
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
				var nearest_lane := _nearest_enemy_minion_lane(team, h)
				if nearest_lane >= 0:
					out_assignments[h] = nearest_lane
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
			if t.lane == AiConfig.Lane.JUNGLE or t.initial_lane_tower_count < 0:
				return false
			return _enemy_tower_count_in_lane(h.team, t.lane) <= t.initial_lane_tower_count - 1
		TeamTask.Type.DEFEND_LANE:
			return not _enemy_minion_near(t.target_pos, 50.0, h.team)
		TeamTask.Type.OBJECTIVE:
			return not _jungle_monster_near(t.target_pos, 10.0)
		TeamTask.Type.GANK:
			if t.target_hero == null:
				return false
			return not is_instance_valid(t.target_hero) or (t.target_hero as Hero).health <= 0.0
		TeamTask.Type.PEEL:
			return false
		TeamTask.Type.PUSH_TOWER:
			return false
		TeamTask.Type.INVADE_JUNGLE:
			# 反野完成：目标野怪区域周围 20m 内已无「敌方半区」存活野怪
			return not _enemy_jungle_monster_near(t.target_pos, 20.0, h.team)
	return false


func _enemy_minion_near(pos: Vector3, radius: float, team: int) -> bool:
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if e is Minion and int((e as Minion).team) != team and (e as Minion).health > 0:
			if (e as Node3D).global_position.distance_to(pos) <= radius:
				return true
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


func _enemy_jungle_monster_near(pos: Vector3, radius: float, team: int) -> bool:
	for e in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(e):
			continue
		if e is JungleMonster and (e as JungleMonster).health > 0:
			var ep: Vector3 = (e as Node3D).global_position
			if BattleManager.in_enemy_jungle_zone(ep, team) and ep.distance_to(pos) <= radius:
				return true
	return false


func _jungle_monster_near(pos: Vector3, radius: float) -> bool:
	for e in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(e):
			continue
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
	# 重分配不立刻清空英雄手上的旧任务：让 HeroAI 按优先级决定是否抢占。
	if status == TeamTask.Status.REASSIGNED:
		return
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
	push_target_by_team.clear()
	push_lane_by_team.clear()
	invade_target_by_hero.clear()
	defend_assignees.clear()
	defend_target_by_team.clear()
	gank_target_by_hero.clear()

	var result: Dictionary = {}
	var dragon_alive := _is_dragon_alive()
	print("[TeamTactics] t=%.0f 龙存活=%s" % [bm.game_time, dragon_alive])

	for team in [Config.Team.PLAYER, Config.Team.ENEMY]:
		var team_label := "玩家方" if team == Config.Team.PLAYER else "敌方"
		var ally_alive := _get_ally_heroes(team).size()
		var enemy_alive := _get_enemy_heroes(team).size()
		# 优先级：DEFEND(100) > PUSH_TOWER(90) > INVADE(85) > OBJECTIVE(80)。
		if _should_defend(team):
			var dl := _defend_lane_for(team)
			var crystal := _crystal_of(team)
			defending[team] = true
			defend_lane_by_team[team] = dl
			defend_target_by_team[team] = crystal.global_position if crystal != null else _own_tower_pos(team, dl)
			_allocate_team(team, default_mode, result)
			for h in _defend_assignees(team):
				defend_assignees[h] = true
				result[h] = dl
			print("[TeamTactics] t=%.0f %s 水晶受小兵威胁，%d 人接守塔" % [bm.game_time, team_label, defend_assignees.size()])
			continue
		# 抱团推塔触发：人数碾压（敌方≤1 且我方≥3）或经济差 > 5000（90 秒冷却）
		var team_gold_diff := _get_total_team_gold(team) - _get_total_team_gold(_enemy_team(team))
		var gold_push_ready: bool = team_gold_diff > AiConfig.PUSH_TOWER_GOLD_LEAD \
			and bm.game_time >= float(_push_gold_cd_until.get(team, 0.0))
		var dragon_push_ready: bool = bm.last_dragon_kill_team == team \
			and bm.game_time - float(bm.last_dragon_kill_time) <= 12.0 \
			and bm.game_time >= float(_push_dragon_cd_until.get(team, 0.0))
		if (enemy_alive <= 1 and ally_alive >= 3) or gold_push_ready or dragon_push_ready:
			var pt := _push_tower_target(team)
			if pt != Vector3.ZERO:
				current_mode = SplitMode.PUSH_TOWER
				push_target_by_team[team] = pt
				_force_push_by_team[team] = gold_push_ready or dragon_push_ready
				if gold_push_ready:
					_push_gold_cd_until[team] = bm.game_time + AiConfig.PUSH_TOWER_GOLD_COOLDOWN
				if dragon_push_ready:
					_push_dragon_cd_until[team] = bm.game_time + AiConfig.PUSH_TOWER_GOLD_COOLDOWN
				var push_lane := int(push_lane_by_team.get(team, AiConfig.Lane.MID))
				for h in _get_ally_heroes(team):
					if h.is_ai:
						result[h] = push_lane
				if gold_push_ready:
					print("[TeamTactics] t=%.0f %s 经济差=%d>%d，抱团推塔（90s冷却）" % [bm.game_time, team_label, team_gold_diff, AiConfig.PUSH_TOWER_GOLD_LEAD])
				elif dragon_push_ready:
					print("[TeamTactics] t=%.0f %s 刚击杀龙，抱团推进（90s冷却）" % [bm.game_time, team_label])
				else:
					print("[TeamTactics] t=%.0f %s 人数碾压 %d:%d，抱团推塔" % [bm.game_time, team_label, ally_alive, enemy_alive])
				continue
		# 4分钟后只要人数有优势，就让打野尝试反野（其余人继续分推）。
		if ally_alive > enemy_alive:
			var invader := _find_natural_jungler(team)
			if invader != null:
				current_mode = SplitMode.INVADE
				# 每个反野成员各自选择敌方半区离自己最近的野怪
				invade_target_by_hero[invader] = _enemy_jungle_target(team, invader.global_position)
				var marksman := _find_carry(team)
				if marksman != null and marksman != invader:
					invade_target_by_hero[marksman] = _enemy_jungle_target(team, marksman.global_position)
				var candidates := []
				for h in _get_ally_heroes(team):
					if h.is_ai and h != invader and h != marksman:
						candidates.append(h)
				if not candidates.is_empty():
					var helper: Hero = candidates[randi() % candidates.size()]
					invade_target_by_hero[helper] = _enemy_jungle_target(team, helper.global_position)
				_allocate_team(team, default_mode, result)
				print("[TeamTactics] t=%.0f %s 人数优势 %d:%d，%s 带队反野" % [bm.game_time, team_label, ally_alive, enemy_alive, invader.display_name])
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
		_build_gank(team)

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
	if defend_assignees.has(h):
		var dl: int = int(defend_lane_by_team.get(h.team, lane))
		var dp: Vector3 = defend_target_by_team.get(h.team, _own_tower_pos(h.team, dl))
		t.setup(TeamTask.Type.DEFEND_LANE, dl, dp, null, 100, now, 18.0, "水晶守小兵", role)
		return t
	if push_target_by_team.has(h.team):
		var pl := int(push_lane_by_team.get(h.team, lane))
		# 经济差触发的抱团推塔优先级高于其他临时任务（临时清兵/血包/反野/抓人）
		var push_pri: int = 950 if bool(_force_push_by_team.get(h.team, false)) else 90
		t.setup(TeamTask.Type.PUSH_TOWER, pl, push_target_by_team[h.team], null, push_pri, now, 40.0, "抱团推塔", role)
		t.lane = pl
		return t
	if invade_target_by_hero.has(h):
		t.setup(TeamTask.Type.INVADE_JUNGLE, lane, invade_target_by_hero[h], null, 85, now, 20.0, "人数优势反野", role)
		return t
	if lane == AiConfig.Lane.JUNGLE and _is_dragon_alive():
		var dp: Vector3 = dragon_pos_by_team.get(h.team, dragon_pos)
		t.setup(TeamTask.Type.OBJECTIVE, lane, dp, null, 80, now, 22.0, "集合争夺资源", role)
		return t
	if gank_target_by_hero.has(h):
		var gt: Hero = gank_target_by_hero[h]
		t.setup(TeamTask.Type.GANK, lane, gt.global_position, gt, 70, now, 25.0, "组团抓落单", role)
		return t
	if lane == AiConfig.Lane.JUNGLE:
		t.setup(TeamTask.Type.PUSH_LANE, lane, Vector3.ZERO, null, 50, now, 18.0, "刷野/回线", role)
		return t
	if role == "辅助":
		var carry := _find_carry(h.team)
		if carry != null:
			t.setup(TeamTask.Type.PEEL, lane, carry.global_position, carry, 50, now, 20.0, "保排", role)
			return t
	t.setup(TeamTask.Type.PUSH_LANE, lane, Vector3.ZERO, null, 50, now, 25.0, "推线/LaneStrategy", role)
	t.initial_lane_tower_count = _enemy_tower_count_in_lane(h.team, lane)
	return t


func _enemy_tower_count_in_lane(team: int, lane: int) -> int:
	var n := 0
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) != team and (e as Turret).health > 0 \
				and (e as Turret).display_name != "crystal" and _get_turret_lane(e as Turret) == lane:
			n += 1
	return n


func _nearest_enemy_minion_lane(team: int, h: Hero) -> int:
	var best_lane := -1
	var best_d := INF
	for e in bm.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) == team or (e as Minion).health <= 0:
			continue
		var m := e as Minion
		if m.line != AiConfig.Lane.FARM and m.line != AiConfig.Lane.MID and m.line != AiConfig.Lane.CLASH:
			continue
		var d: float = h.global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best_lane = m.line
	return best_lane


func _find_carry(team: int) -> Hero:
	for h in _get_ally_heroes(team):
		if str(h.role) == "射手":
			return h
	return null


func ai_lane_of(h: Hero) -> int:
	for child in h.get_children():
		if child is HeroAI:
			return (child as HeroAI).lane
	return AiConfig.Lane.MID


func _in_own_half(pos: Vector3, team: int) -> bool:
	var own := Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var enemy := Vector3(53, 0, -53) if team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	return pos.distance_to(own) < pos.distance_to(enemy)


func _find_gank_target(team: int) -> Hero:
	var best: Hero = null
	var best_score := INF
	for h in _get_enemy_heroes(team):
		if h.is_untargetable_by_enemies() or not _in_own_half(h.global_position, team):
			continue
		var escort := 0
		for e in _get_enemy_heroes(team):
			if e != h and e.global_position.distance_to(h.global_position) <= 10.0:
				escort += 1
		if escort > 0:
			continue
		var score := h.health / maxf(1.0, h.actual_max_health)
		if score < best_score:
			best_score = score
			best = h
	return best


func _build_gank(team: int) -> void:
	if bm.game_time >= 360.0:
		var gank_target := _find_gank_target(team)
		if gank_target != null:
			for h in _get_ally_heroes(team):
				if h.is_ai and h.global_position.distance_to(gank_target.global_position) <= 40.0:
					gank_target_by_hero[h] = gank_target


func _find_natural_jungler(team: int) -> Hero:
	for h in _get_ally_heroes(team):
		if not h.is_ai:
			continue
		for child in h.get_children():
			if child is HeroAI and (child as HeroAI)._is_natural_jungler:
				return h
	return null


func _push_tower_target(team: int) -> Vector3:
	# 选“己方兵线前线离该路敌方塔最近”的分路，然后该路交给 LaneStrategy 推进。
	var own_crystal := Vector3(-53, 0, 53) if team == Config.Team.PLAYER else Vector3(53, 0, -53)
	var best_d := INF
	var best_tower: Turret = null
	var best_lane := AiConfig.Lane.MID
	for lane in [AiConfig.Lane.FARM, AiConfig.Lane.MID, AiConfig.Lane.CLASH]:
		var front := Vector3.ZERO
		var front_progress := -INF
		for e in bm.get_tree().get_nodes_in_group("minions"):
			if e is Minion and int((e as Minion).team) == team and (e as Minion).health > 0 \
					and int((e as Minion).line) == lane:
				var d := own_crystal.distance_to((e as Node3D).global_position)
				if d > front_progress:
					front_progress = d
					front = (e as Node3D).global_position
		if front == Vector3.ZERO:
			continue
		var tower := _nearest_tower_in_lane(team, lane, front)
		if tower == null:
			continue
		var dist := front.distance_to(tower.global_position)
		if dist < best_d:
			best_d = dist
			best_tower = tower
			best_lane = lane
	if best_tower != null:
		push_lane_by_team[team] = best_lane
		return best_tower.global_position
	return Vector3.ZERO


func _nearest_tower_in_lane(team: int, lane: int, from: Vector3) -> Turret:
	var best: Turret = null
	var best_d := INF
	for e in bm.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) == team or (e as Turret).health <= 0:
			continue
		if (e as Turret).display_name == "crystal" or _get_turret_lane(e as Turret) != lane:
			continue
		var d := from.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = e as Turret
	return best


func _enemy_jungle_target(team: int, from_pos: Vector3 = Vector3.ZERO) -> Vector3:
	# 优先选敌方半区离自己最近的「存活野怪」本体，而不是营地中心
	var best_monster_pos := Vector3.ZERO
	var best_monster_d := INF
	for e in bm.get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(e) or not (e is JungleMonster) or (e as JungleMonster).health <= 0.0:
			continue
		var mp: Vector3 = (e as Node3D).global_position
		if not BattleManager.in_enemy_jungle_zone(mp, team):
			continue
		var md := from_pos.distance_to(mp) if from_pos != Vector3.ZERO else 0.0
		if md < best_monster_d:
			best_monster_d = md
			best_monster_pos = mp
	if best_monster_pos != Vector3.ZERO:
		return best_monster_pos
	# 敌方野区暂时无怪：回退到最近的敌方营地中心，任务会被判定完成
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

