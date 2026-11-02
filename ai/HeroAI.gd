# HeroAI — 单个 AI 英雄的决策器（挂在 Hero 下，每英雄一个）。
# 只负责「打谁 / 去哪 / 放什么技能」：结论写入 hero.manual_target / hero.move_target / _start_casting()，
# 移动、寻路、普攻、施法由 Hero/GameEntity 用与玩家相同的原语执行。
# 分层：AiPerception 感知 → SkillTactics/SummonerTactics/ItemActiveTactics 战术
#      → LaneStrategy / JungleStrategy 阶段策略（0-4min）→ TeamTactics 团队分配（4min+，由 BattleManager 驱动）
#      → HeroBrain 英雄特判。计时与阈值见 AiConfig。
class_name HeroAI
extends Node

var current_action: AIAction = AIAction.new(AIAction.Type.IDLE)
var safety_stack: Array[AIAction] = []
var lane: int = AiConfig.Lane.MID
var hero: Hero
var perception: AiPerception
var skill_tactics: SkillTactics
var summoner_tactics: SummonerTactics
var item_tactics: ItemActiveTactics
var brain: HeroBrain
var threat_model: ThreatModel
var trade_planner: TradePlanner
var task_executor: TaskExecutor
var team_task: TeamTask = null
var think_timer: float = 0.0
var _frame_delta: float = 0.0
var _temp_clearing: bool = false
var _task_commit_until: float = -999.0
var _env_pause_used := false
var _task_pause_active := false
var _ai_path: Array = []
var _ai_path_goal := Vector3.ZERO
var _ai_path_time := 0.0
var _ai_path_index := 0
var _ai_path_risk := 0.0
var _ai_path_len := 0.0
var recall_timer: float = 0.0
var buy_timer: float = 5.0
var has_respawned_recently: bool = false
var jungle_kill_count: int = 0
var patrol_angle: float = 0.0
var _is_natural_jungler: bool = false
var decide_score: float = 0.0

# --- 新AI决策系统 ---
var lane_strategy: LaneStrategy = null
var jungle_strategy: JungleStrategy = null
var is_dragon_rally: bool = false
var dragon_rally_pos: Vector3 = Vector3.ZERO

# --- 中断检测追踪 ---
var _last_hp: float = 0.0
var _last_enemy_count: int = 0
var _last_target_ref: GameEntity = null
var _is_dodging: bool = false

# --- 残血追击（收人头）：附近唯一的残血敌人，即使自身血量不高也追 ---
var _chase_target: Hero = null
var _chase_time: float = 0.0

# --- 撤退/回城安全路线（A* 航点，不再直线撞墙/穿敌塔） ---
var _safe_route_path := PackedVector3Array()
var _safe_route_index := 0
var _safe_route_goal := Vector3.ZERO
var _safe_route_plan_time := -999.0
var _retreat_goal_cache := Vector3.ZERO
var _retreat_goal_time := -999.0
var _recall_spot_cache := Vector3.ZERO
var _recall_spot_time := -999.0

# --- 调试：思考过程（F3 / 录像） ---
var _dbg_log: Array = []
var _dbg_last_state := -1
var _dbg_last_target := ""
var _dbg_last_casting := false
var _dbg_last_recall := false
var _chip_cache: Dictionary = {}
var _chip_next_t := 0.0

func _ready():
	if get_parent() is Hero:
		hero = get_parent() as Hero
	else:
		for child in get_parent().get_children():
			if child is Hero and child.team != Config.Team.PLAYER:
				hero = child
				break
	hero.ai_path_controlled = true
	perception = AiPerception.new(hero)
	threat_model = ThreatModel.new(hero)
	trade_planner = TradePlanner.new(hero, threat_model, perception)
	task_executor = TaskExecutor.new(hero, perception)
	skill_tactics = SkillTactics.new(hero, perception)
	summoner_tactics = SummonerTactics.new(hero, perception, trade_planner)
	item_tactics = ItemActiveTactics.new(hero, perception)
	brain = HeroBrain.create(hero.display_name, hero, perception, skill_tactics)
	skill_tactics.brain = brain   # 技能层走英雄特判钩子（后羿大招/刘禅拆塔），不再硬编码名字
	recommended_items = _get_recommended_items()
	_assign_lane()
	# 初始化新AI策略模块
	lane_strategy = LaneStrategy.new(hero, perception, lane)
	jungle_strategy = JungleStrategy.new(hero, perception)

func _set_action(action_type: int, priority: int = 0, pause_class: int = AIAction.PauseClass.NONE, reason: String = "", data: Dictionary = {}) -> void:
	if current_action != null and current_action.is_active():
		if current_action.type == action_type:
			return
		if priority < current_action.priority:
			return
		current_action.mark(AIAction.Status.INTERRUPTED)
	current_action = AIAction.new(action_type, priority, pause_class, reason)

	if pause_class == AIAction.PauseClass.NONE:
		_task_pause_active = false
	if current_action.pause_class != AIAction.PauseClass.NONE and team_task != null and team_task.is_active():
		_pause_task_for(current_action)


func _push_safety_action(action_type: int) -> void:
	if _is_action(AIAction.Type.DODGE) or _is_action(AIAction.Type.TOWER_ESCAPE):
		return
	if current_action != null and current_action.is_active():
		safety_stack.append(current_action)
	current_action = AIAction.new(action_type, 1000, AIAction.PauseClass.SURVIVAL, "frame safety")
	_task_pause_active = true


func _resume_safety_action() -> void:
	while not safety_stack.is_empty():
		var prev: AIAction = safety_stack.pop_back()
		if prev != null and prev.is_active():
			current_action = prev
			_task_pause_active = false
			return
	current_action = AIAction.new(AIAction.Type.IDLE)


func _can_run_environment_action() -> bool:
	if team_task == null or not team_task.is_active():
		return true
	return not _env_pause_used


func _is_action(action_type: int) -> bool:
	return current_action != null and current_action.is_active() and current_action.type == action_type


func _pause_task_for(action: AIAction) -> void:
	if team_task == null or not team_task.is_active():
		return
	if action.pause_class == AIAction.PauseClass.SURVIVAL:
		_task_pause_active = true
	elif action.pause_class == AIAction.PauseClass.ENVIRONMENT and not _env_pause_used:
		_env_pause_used = true
		_task_pause_active = true


func _action_is_complete(action: AIAction) -> bool:
	match action.type:
		AIAction.Type.TRADE:
			return trade_planner.active_target == null or not is_instance_valid(trade_planner.active_target)
		AIAction.Type.FINISH_CHASE:
			return _chase_target == null or not is_instance_valid(_chase_target) or _chase_target.health <= 0.0
		AIAction.Type.TEMP_CLEAR:
			return _temp_clear_retarget_or_done()
		AIAction.Type.TEAM_TASK:
			return team_task == null or not team_task.is_active()
		AIAction.Type.SAFE_RECALL:
			return _fully_recovered()
		AIAction.Type.RETURN_TO_BASE:
			return _is_threat_low()
		AIAction.Type.DEFEND_TOWER:
			return _get_lane_turret_under_attack(lane) == null
		AIAction.Type.HEALTH_PACK:
			return hero.health > hero.actual_max_health * 0.60 or _find_safe_health_pack() == null
		AIAction.Type.TRIPOD:
			return hero.manual_target == null or not is_instance_valid(hero.manual_target)
		AIAction.Type.VISION_SPIRIT:
			return hero.move_target == Vector3.ZERO
	return false


func _finish_current_action() -> void:
	if current_action == null:
		return
	current_action.mark(AIAction.Status.COMPLETED)
	current_action = AIAction.new(AIAction.Type.IDLE)
	_task_pause_active = false


## 朝指定点走（A* 绕墙；泉水养伤/回城落点用）
func _walk_to(goal: Vector3) -> void:
	var now := _game_time()
	if _ai_path.is_empty() or _ai_path_goal.distance_to(goal) > 1.5 \
			or now - _ai_path_time > 0.8 or _ai_path_index >= _ai_path.size():
		_ai_path_goal = goal
		_ai_path = MovementPlanner.plan(hero, goal, threat_model)
		_ai_path_time = now
		_ai_path_index = 0
		_ai_path_len = MovementPlanner.path_length(_ai_path)
		_ai_path_risk = MovementPlanner.path_risk(hero, _ai_path, threat_model)
	if _ai_path.is_empty():
		_ai_path_len = 0.0
		_ai_path_risk = 0.0
		hero.move_target = goal
		return
	while _ai_path_index < _ai_path.size() - 1 \
			and hero.global_position.distance_to(_ai_path[_ai_path_index]) < 1.2:
		_ai_path_index += 1
	hero.move_target = _ai_path[_ai_path_index]

func _sync_ai_movement() -> void:
	var t = hero.manual_target
	if t == null or not is_instance_valid(t) or t.health <= 0.0:
		_ai_path.clear()
		return
	var reach: float = (hero._aa_engage_reach() if not t is JungleMonster else 2.0)
	var dist: float = hero.global_position.distance_to(t.global_position)
	if dist <= reach:
		_ai_path.clear()
		hero.move_target = Vector3.ZERO
		return
	var now := _game_time()
	if _ai_path.is_empty() or _ai_path_goal.distance_to(t.global_position) > 2.0 \
			or now - _ai_path_time > 0.8 or _ai_path_index >= _ai_path.size():
		_ai_path_goal = t.global_position
		_ai_path = MovementPlanner.plan(hero, _ai_path_goal, threat_model)
		_ai_path_time = now
		_ai_path_index = 0
		_ai_path_len = MovementPlanner.path_length(_ai_path)
		_ai_path_risk = MovementPlanner.path_risk(hero, _ai_path, threat_model)
	if _ai_path.is_empty():
		_ai_path_len = 0.0
		_ai_path_risk = 0.0
		hero.move_target = t.global_position
		return
	while _ai_path_index < _ai_path.size() - 1 \
			and hero.global_position.distance_to(_ai_path[_ai_path_index]) < 1.2:
		_ai_path_index += 1
	hero.move_target = _ai_path[_ai_path_index]


func _assign_lane():
	match hero.role:
		"射手": lane = AiConfig.Lane.FARM
		"法师": lane = AiConfig.Lane.MID
		"刺客": lane = AiConfig.Lane.JUNGLE ; _is_natural_jungler = true
		"战士": lane = AiConfig.Lane.CLASH
		"坦克": lane = AiConfig.Lane.CLASH
		"辅助": lane = AiConfig.Lane.FARM
		_: lane = randi() % 4
	jungle_kill_count = 0
	has_respawned_recently = true
	# 回城/复活后返回原分路
	if lane == AiConfig.Lane.JUNGLE:
		_set_action(AIAction.Type.JUNGLE_FARM)
	else:
		_set_action(AIAction.Type.PUSH_LANE)
	hero.manual_target = null
	hero.move_target = hero.global_position
	# 重置策略模块
	if _is_natural_jungler and jungle_strategy:
		jungle_strategy = JungleStrategy.new(hero, perception)
	elif not _is_natural_jungler and lane_strategy:
		lane_strategy = LaneStrategy.new(hero, perception, lane)
	is_dragon_rally = false


# ==================== 传送 ====================
func _try_teleport():
	if hero.is_teleporting or hero.teleport_timer > 0:
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle == null:
		return
	var zone = battle._get_teleport_zone_for_hero(hero)
	if zone == null:
		return
	var minion = perception.find_nearest_ally_minion_on_lane(lane)
	if minion == null:
		return
	var walk_time: float = hero.global_position.distance_to(minion.global_position) / maxf(1.0, hero.actual_move_speed)
	if walk_time <= Hero.TELEPORT_DURATION + 2.0:
		return
	battle.request_teleport(hero, minion)


# ==================== 技能升级 ====================
func _try_teleport_route() -> void:
	if hero.is_teleporting or hero.teleport_timer > 0.0:
		return
	if hero.manual_target != null and is_instance_valid(hero.manual_target):
		return
	if perception.count_enemy_heroes_near(15.0) > 0:
		return
	var minion = perception.find_nearest_ally_minion_on_lane(lane)
	if minion == null:
		return
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle == null:
		return
	var best_zone: Node3D = null
	var best_total := INF
	for z in get_tree().get_nodes_in_group("teleport_zones"):
		if not (z is Node3D):
			continue
		var d: float = hero.global_position.distance_to((z as Node3D).global_position)
		if d <= 5.0 or d > 20.0:
			continue
		var path_len := PathFinder.path_length(hero.global_position, (z as Node3D).global_position, hero.team)
		if path_len <= 0.0:
			path_len = d
		var total: float = path_len / maxf(1.0, hero.actual_move_speed) + Hero.TELEPORT_DURATION
		if total < best_total:
			best_total = total
			best_zone = z as Node3D
	if best_zone == null:
		return
	var direct: float = hero.global_position.distance_to(minion.global_position) / maxf(1.0, hero.actual_move_speed)
	if best_total + 2.0 >= direct:
		return
	hero.move_target = best_zone.global_position
	_set_action(AIAction.Type.ROTATE, 110, AIAction.PauseClass.NONE, "传送转线")


func _try_upgrade_skills():
	if hero.skill_points <= 0:
		return
	for i in range(3):
		if hero.skill_levels[i] <= 0:
			if hero.upgrade_skill(i):
				return
	var pool = []
	for i in range(3):
		var max_lv = 6 if i < 2 else 3
		if hero.skill_levels[i] < max_lv:
			pool.append(i)
	if pool.size() > 0:
		hero.upgrade_skill(pool[randi() % pool.size()])


# ==================== 赶路位移（非战斗位移技能） ====================
# 位移/加速赶路：只要离 move_target 超过普攻距离就尝试（技能类型4/self_displacement>0，如孙尚香Q翻滚、
# 马可波罗W漫游）；施法/受控/回城/有锁定目标时不触发。闪现只用于追击/逃跑，不用于赶路。
func _try_travel_dash():
	# 位移/加速：只要离目标点超过普攻距离就使用（不再限制 PUSH/FARM/9m/附近敌人）
	if not is_instance_valid(hero) or hero.is_dead or hero.is_reviving:
		return
	# 施法/引导/传送/回城等动作中不赶路
	if hero.casting_skill or hero.channeling_skill_index >= 0 \
			or hero.is_recalling or hero.is_teleporting or hero.teleport_timer > 0.0:
		return
	# 受控（眩晕/击飞/冰冻/压制/沉默）时不赶路
	if hero.stun_timer > 0.0 or hero.knockup_timer > 0.0 or hero.froze_timer > 0.0 \
			or hero.suppress_timer > 0.0 or hero.silence_timer > 0.0:
		return
	# 有攻击目标（正在接战/推进/追人）→ 位移留给作战连招，不赶路
	if is_instance_valid(hero.manual_target) and hero.manual_target.health > 0:
		return
	var dest := hero.move_target
	if dest == Vector3.ZERO:
		return
	var dist := hero.global_position.distance_to(dest)
	if dist <= hero.attack_range * 0.01:
		return
	# 闪现只在追击/逃跑时使用，不用于赶路
	# 强化普攻赶路（马超/铠/不知火舞空放，亚瑟Q/孙悟空借小兵/野怪跳）
	if _try_enhanced_aa_travel(dest):
		return
	var idx := _pick_travel_dash_skill()
	if idx < 0:
		return
	var sk: Skill = hero.skills[idx]
	if sk == null:
		return
	# 沿指向 move_target 的方向跳技能本身位移长度
	var dir := dest - hero.global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var end := _resolve_dash_end(hero.global_position, dir, sk.self_displacement)
	if end == Vector3.ZERO:
		return
	hero._start_casting(idx, sk, dest)


# 选择赶路用位移技能：只在 1/2 技能位找，大招(3)与特殊槽(隐身/恢复等)不用于赶路
func _pick_travel_dash_skill() -> int:
	var best := -1
	var best_cd := INF
	for i in range(2):
		if i >= hero.skills.size() or hero.skills[i] == null:
			continue
		var sk: Skill = hero.skills[i]
		# 只认引擎内「位移」类型(4)且确有位移距离；李白Q为type3三段折返、会记录回原点，排除
		if sk.type != 4 or sk.self_displacement <= 0.0:
			continue
		# 多段/持续窗口技能进行中不打断（保持窗口逻辑自洽）
		if i < hero.skill_window_timers.size() and hero.skill_window_timers[i] > 0.0:
			continue
		if i >= hero.skill_levels.size() or hero.skill_levels[i] < 1:
			continue    # 未学习
		if i < hero.skill_cooldowns.size() and hero.skill_cooldowns[i] > 0.0:
			continue    # CD中
		if sk.restore > 0.0 and (i >= hero.skill_restores.size() or hero.skill_restores[i] <= 0):
			continue    # 存储型技能无层数
		var mcost := sk.mana_cost - sk.power_bonus * maxi(hero.skill_levels[i] - 1, 0)
		if hero.mana < mcost:
			continue
		if hero.skill_prereq_blocked(i):
			continue
		var cd := sk.cooldown - sk.cd_bonus * maxi(hero.skill_levels[i] - 1, 0)
		if cd < best_cd:
			best_cd = cd
			best = i
	return best


## 计算位移落点：允许“穿墙”，但只在前方绕路明显更远时才穿；落点必须可站立、不进敌方塔
func _resolve_dash_end(from: Vector3, dir: Vector3, length: float) -> Vector3:
	if length <= 0.1:
		return Vector3.ZERO
	var end: Vector3 = from + dir * length
	if not PathFinder.is_walkable_world(end):
		end = PathFinder.nearest_walkable_world(end, dir)
		if end == Vector3.ZERO or from.distance_to(end) < length * 0.5:
			return Vector3.ZERO
	if from.distance_to(end) > length + 0.6:
		return Vector3.ZERO      # 可落点被推得太远，这一下位移够不到
	var straight: float = from.distance_to(end)
	if straight < 0.2:
		return Vector3.ZERO
	if _dash_line_blocked(from, end):
		# 直线被墙挡：只有走路需要绕远（>1.6 倍）才值得穿墙位移
		var walk := PathFinder.path_length(from, end, hero.team)
		if walk <= 0.0 or walk < straight * 1.6:
			return Vector3.ZERO
	if _dash_landing_in_enemy_turret(end):
		return Vector3.ZERO
	return end


# 直线段逐米采样 PathFinder 网格：只要命中一个不可通行格(solid，墙体3×3/地图边缘)就视为会被墙挡住
func _dash_line_blocked(from: Vector3, to: Vector3) -> bool:
	if not PathFinder.initialized or not PathFinder.astar:
		return true    # 导航未就绪时不跳，保守
	var total := from.distance_to(to)
	if total <= 0.01:
		return false
	var steps := maxi(1, int(ceil(total)))
	for k in range(1, steps + 1):
		var p := from.lerp(to, float(k) / float(steps))
		var cell := PathFinder._world_to_cell(p)
		if not PathFinder._is_in_bounds(cell):
			return true    # 采样点落出网格范围视为不可跳
		if PathFinder.astar.is_point_solid(cell):
			return true
	return false


# 位移落点是否在敌方防御塔射程内（用各塔自身 attack_range，单位转换×0.01；再加安全余量）
func _dash_landing_in_enemy_turret(end: Vector3) -> bool:
	var tree := hero.get_tree()
	if not tree:
		return true    # 场景未就绪时不跳，保守
	for t in tree.get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or t.team == hero.team:
			continue
		var reach: float = t.attack_range * 0.01
		if end.distance_to(t.global_position) < reach + AiConfig.TRAVEL_DASH_TURRET_MARGIN:
			return true
	return false


# ==================== 位移类技能：追击贴脸 / 逃跑拉开 ====================
## 取一个当前可用的位移技能（type=4）
func _pick_dash_skill() -> Dictionary:
	for i in range(mini(3, hero.skills.size())):
		if hero.skill_levels[i] <= 0:
			continue
		if hero.skill_cooldowns[i] > 0.0:
			continue
		var sk: Skill = hero.skills[i]
		if sk == null or sk.type != 4:
			continue
		if hero.mana < sk.mana_cost:
			continue
		# 与 Hero 执行同口径：优先 self_displacement，没有就用 cast_range
		var dash_len: float = sk.self_displacement if sk.self_displacement > 0.0 else sk.cast_range
		if dash_len <= 0.5:
			continue
		# 英雄前置门槛（兰陵王需隐身等）不满足时不选，避免反复白试
		if hero.skill_prereq_blocked(i):
			continue
		return {"index": i, "skill": sk, "len": dash_len}
	return {}


## 追击：目标在普攻距离外时，用位移技能突进贴脸（落点不进军敌塔）
## 闪现穿墙赶路：只有绕路明显更远时才用闪现，平时留给逃生/追击
func _try_flash_travel(dest: Vector3) -> bool:
	if not hero.summoner_skill or hero.summoner_cooldown > 0:
		return false
	if str(hero.summoner_skill.skill_name) != "闪现":
		return false
	var from: Vector3 = hero.global_position
	var dir: Vector3 = dest - from
	dir.y = 0.0
	if dir.length() < 1.0:
		return false
	dir = dir.normalized()
	var end: Vector3 = from + dir * AiConfig.FLASH_DISTANCE
	if not PathFinder.is_walkable_world(end):
		end = PathFinder.nearest_walkable_world(end, dir)
		if end == Vector3.ZERO:
			return false
	var straight: float = from.distance_to(end)
	if straight < 2.0:
		return false
	# 直线没墙就不值得交闪现（留给逃生）
	if not _dash_line_blocked(from, end):
		return false
	var walk := PathFinder.path_length(from, end, hero.team)
	if walk <= 0.0 or walk < straight * 1.6:
		return false
	hero.global_position = end
	hero._clamp_to_map_edge()
	hero.move_target = Vector3.ZERO
	hero.summoner_cooldown = hero.summoner_skill.cooldown
	return true


## 只有目标残血且已进入普攻距离时，才允许 AI 把强普位移用于一次必杀普攻
func _ai_update_enhanced_attack_flag() -> void:
	if not is_instance_valid(hero) or not hero.has_method("ai_enhanced_aa_ready"):
		return
	hero.ai_enhanced_attack_ok = false
	if not hero.ai_enhanced_aa_ready():
		return
	var t: GameEntity = hero.manual_target
	if t == null or not is_instance_valid(t) or t.health <= 0.0:
		return
	if t.team == hero.team:
		return
	var dist: float = hero.global_position.distance_to(t.global_position)
	var aa: float = hero.attack_range * 0.01
	if dist <= aa + 0.6 and float(t.health) <= float(t.actual_max_health) * 0.3:
		hero.ai_enhanced_attack_ok = true


## 马超：安全时走向附近掉落的枪，积攒强化普攻层数（stat_timer 上限 8）
func _try_collect_enhanced_charge() -> bool:
	if not is_instance_valid(hero) or str(hero.display_name) != "马超":
		return false
	if not _is_action(AIAction.Type.PUSH_LANE) and not _is_action(AIAction.Type.JUNGLE_FARM):
		return false
	if hero.stat_timer >= 8.0:
		return false
	if perception.find_nearest_enemy_hero(9.0) != null:
		return false
	var objs: Array = hero.objs
	if objs.is_empty():
		return false
	var best = null
	var best_d := 1e20
	for o in objs:
		if not is_instance_valid(o):
			continue
		var d: float = hero.global_position.distance_to(o.global_position)
		if d < 0.2 or d > 18.0:
			continue
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return false
	if _dash_landing_in_enemy_turret(best.global_position):
		return false
	hero.manual_target = null
	hero.move_target = best.global_position
	return true


## 强化普攻位移：赶路（马超/铠/不知火舞空放；亚瑟Q/孙悟空借敌方目标跳跃）
func _try_enhanced_aa_travel(dest: Vector3) -> bool:
	if not is_instance_valid(hero) or not hero.has_method("ai_enhanced_aa_ready"):
		return false
	if not hero.ai_enhanced_aa_ready():
		return false
	# 积攒期不随便把强普花在赶路：马超未满层/距离不够远就留着
	var dest_dist: float = hero.global_position.distance_to(dest)
	var nm := str(hero.display_name)
	if nm == "马超" and dest_dist < 22.0 and hero.stat_timer < 8.0:
		return false
	if nm == "铠" and dest_dist < 20.0:
		return false
	if nm == "不知火舞" and dest_dist < 18.0:
		return false
	var dir: Vector3 = dest - hero.global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		return false
	dir = dir.normalized()
	var dash_len: float = hero.ai_enhanced_aa_dash_len()
	if dash_len <= 0.1:
		return false
	# 位移落点：允许穿墙（绕路明显更远才穿），不进敌方塔
	var end: Vector3 = _resolve_dash_end(hero.global_position, dir, dash_len)
	if end == Vector3.ZERO:
		return false
	var jt: GameEntity = null
	if str(hero.display_name) in ["亚瑟", "孙悟空"]:
		jt = _find_enhanced_jump_target(dir, dash_len)
		if jt == null:
			return false
		if _dash_landing_in_enemy_turret(jt.global_position):
			return false
	if hero.ai_enhanced_aa_dash(dir, jt):
		hero.move_target = Vector3.ZERO
		if jt != null:
			# 跳跃型（亚瑟Q/孙悟空）只是借目标赶路，别被普攻锁定在原地
			hero.manual_target = null
		return true
	return false


## 追击：用强化普攻位移拉近（跳跃型需要有目标）
func _try_enhanced_aa_chase(target: GameEntity) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
	if not hero.has_method("ai_enhanced_aa_ready") or not hero.ai_enhanced_aa_ready():
		return false
	var dist: float = hero.global_position.distance_to(target.global_position)
	var aa: float = hero.attack_range * 0.01
	if dist <= aa + 0.6:
		return false
	var dash_len: float = hero.ai_enhanced_aa_dash_len()
	if dist > dash_len + aa + 1.2:
		return false
	var dir: Vector3 = target.global_position - hero.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	var jt: GameEntity = null
	if str(hero.display_name) in ["亚瑟", "孙悟空"]:
		if dist > dash_len:
			return false
		jt = target
	if hero.ai_enhanced_aa_dash(dir, jt):
		hero.move_target = Vector3.ZERO
		return true
	return false


## 逃跑：只用可空放的强普（马超/铠/不知火舞），朝安全方向拉开
func _try_enhanced_aa_escape(dir: Vector3) -> bool:
	if not hero.has_method("ai_enhanced_aa_ready") or not hero.ai_enhanced_aa_ready():
		return false
	if str(hero.display_name) not in ["马超", "铠", "不知火舞"]:
		return false
	var dash_len: float = hero.ai_enhanced_aa_dash_len()
	var end: Vector3 = _resolve_dash_end(hero.global_position, dir, dash_len)
	if end == Vector3.ZERO:
		return false
	if hero.ai_enhanced_aa_dash(dir, null):
		hero.move_target = Vector3.ZERO
		return true
	return false


## 找沿移动方向、在强化普攻距离内的敌方单位（亚瑟Q/孙悟空跳跃用）
func _find_enhanced_jump_target(dir: Vector3, reach: float) -> GameEntity:
	var best: GameEntity = null
	var best_d := 1e20
	for e in get_tree().get_nodes_in_group("entities"):
		if e == hero or not (e is GameEntity) or e.health <= 0.0 or e.team == hero.team:
			continue
		if not (e is Hero or e is Minion or e is JungleMonster):
			continue
		var to: Vector3 = e.global_position - hero.global_position
		to.y = 0.0
		var d := to.length()
		if d < 0.5 or d > reach:
			continue
		if to.normalized().dot(dir) < 0.45:
			continue          # 只跳向移动方向前方的目标
		if d < best_d:
			best_d = d
			best = e
	return best


func _try_chase_dash(target: GameEntity) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
	if hero.is_recalling:
		return false
	var dist: float = hero.global_position.distance_to(target.global_position)
	var aa: float = hero.attack_range * 0.01
	if dist <= aa + 0.6:
		return false                      # 已经在普攻距离内，不浪费位移
	if dist > AiConfig.DASH_CHASE_MAX_RANGE:
		return false
	# 强化普攻追击（马超/铠/不知火舞冲脸；亚瑟Q/孙悟空跳向目标）
	if _try_enhanced_aa_chase(target):
		return true
	var d := _pick_dash_skill()
	if d.is_empty():
		return false
	if dist > float(d["len"]) + aa + AiConfig.DASH_CHASE_SLACK:
		return false                      # 突进后还够不到，不追
	var dir: Vector3 = target.global_position - hero.global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	# 落点做墙面修正：dash_move_to 不受碰撞约束，不修正会穿墙/卡在墙里
	var end: Vector3 = _resolve_dash_end(hero.global_position, dir, float(d["len"]))
	if end == Vector3.ZERO:
		return false                      # 穿墙绕路不值得/落点危险
	hero.move_target = Vector3.ZERO      # 清掉走路指令，免得突进被移动逻辑覆盖
	hero._start_casting(int(d["index"]), d["skill"] as Skill, end)
	return true


## 逃跑：被敌方英雄贴身且血量偏低，朝最近己方防御塔方向位移拉开
func _try_escape_dash() -> bool:
	if hero.is_recalling:
		return false
	if hero.health > hero.actual_max_health * AiConfig.DASH_ESCAPE_HP_RATIO:
		return false
	var threat: Hero = perception.find_nearest_enemy_hero(AiConfig.DASH_ESCAPE_THREAT)
	if threat == null:
		return false
	# 强化普攻逃跑（马超/铠/不知火舞可空放；亚瑟/孙悟空跳跃型不用于逃跑）
	if str(hero.display_name) in ["马超", "铠", "不知火舞"]:
		var edir: Vector3 = hero.global_position - threat.global_position
		edir.y = 0.0
		var ft: Turret = perception.find_nearest_friendly_turret(30.0)
		if ft != null and is_instance_valid(ft):
			var to_t: Vector3 = ft.global_position - hero.global_position
			to_t.y = 0.0
			if to_t.length() > 1.0:
				edir = to_t
		if edir.length() > 0.1 and _try_enhanced_aa_escape(edir.normalized()):
			return true
	var d := _pick_dash_skill()
	if d.is_empty():
		return false
	var dir: Vector3 = hero.global_position - threat.global_position
	dir.y = 0.0
	var turret: Turret = perception.find_nearest_friendly_turret(30.0)
	if turret != null and is_instance_valid(turret):
		var to_t: Vector3 = turret.global_position - hero.global_position
		to_t.y = 0.0
		if to_t.length() > 1.0:
			dir = to_t
	if dir.length() < 0.1:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	# 逃跑落点同样做墙面修正：贴着墙位移否则会把自己塞进墙角
	var end: Vector3 = _resolve_dash_end(hero.global_position, dir, float(d["len"]))
	if end == Vector3.ZERO:
		return false                      # 落点不可站/穿墙绕路不值得
	hero.move_target = Vector3.ZERO      # 清掉走路指令，保证撤退位移真正生效
	hero._start_casting(int(d["index"]), d["skill"] as Skill, end)
	return true



# ==================== 主循环 ====================
func _process(delta):
	_frame_delta = delta
	# --- 塔攻击检测 ---
	if hero.under_tower_attack:
		hero.tower_attack_timer -= delta
		if hero.tower_attack_timer <= 0:
			hero.under_tower_attack = false
			hero.tower_attacker = null
			if _is_action(AIAction.Type.TOWER_ESCAPE):
				_resume_safety_action()
		elif hero.tower_attacker and is_instance_valid(hero.tower_attacker):
			if not _is_action(AIAction.Type.TOWER_ESCAPE):
				_push_safety_action(AIAction.Type.TOWER_ESCAPE)
			# 立即沿直线退出塔的攻击范围
			_retreat_from_turret(hero.tower_attacker)
	# --- 弹道躲避（每帧）：命中威胁时标记 DODGE ---
	if _dodge_threats():
		if not _is_action(AIAction.Type.DODGE):
			_push_safety_action(AIAction.Type.DODGE)
		return
	elif _is_action(AIAction.Type.DODGE):
		_resume_safety_action()
	if hero.manual_target and hero.manual_target is Hero and not _is_target_safe(hero.manual_target):
		hero.set_manual_target(null)
		if current_action != null:
			current_action.mark(AIAction.Status.INTERRUPTED)

	if not is_instance_valid(hero) or hero.is_dead:
		has_respawned_recently = false
		return

	# 泉水养伤是最高常态约束：进泉/回城落点附近且未回满时，任何任务都不能把 AI 拉出泉。
	# 3.6m 是泉水判定圈；8m 是缓冲圈，防止单位互相推挤把 AI 挤出判据圈后直接离泉。
	var spring := Vector3(-62, 0, 62) if hero.team == Config.Team.PLAYER else Vector3(62, 0, -62)
	var spring_dist := hero.global_position.distance_to(spring)
	if spring_dist <= 8.0 and not _fully_recovered():
		_set_action(AIAction.Type.SAFE_RECALL, 960, AIAction.PauseClass.SURVIVAL, "泉水养伤")
		hero.manual_target = null
		if hero.is_recalling:
			hero.cancel_recall()
		if spring_dist > 3.0:
			_walk_to(spring)   # PathFinder 已挖开泉水入口走廊，A* 可直达泉心
		else:
			hero.move_target = Vector3.ZERO
			_ai_path.clear()
		if hero.is_in_own_fountain():
			_recall_safe_behavior(delta)
		return
	_sync_ai_movement()
	# 目标死亡后的“附近是否还有其他小兵”交给 _action_is_complete 的 TEMP_CLEAR 分支处理
	_debug_track()

	# 威胁记忆与换血状态每帧维护：视野消失的敌人仍保留最后位置/血量，不直接消失。
	var _bm_now = get_tree().get_first_node_in_group("battle_manager")
	var _gt_now: float = float(_bm_now.game_time) if _bm_now != null else 0.0
	threat_model.update(_gt_now)
	trade_planner.update(delta, _gt_now)
	if (_task_pause_active or _temp_clearing) and team_task != null and team_task.is_active():
		team_task.expires_at += delta
	if current_action != null and current_action.is_active() and _action_is_complete(current_action):
		_finish_current_action()

	# --- 连招链推进：起手技能之后按段间隔自动衔接下一段，目标失效/换目标即中止 ---
	skill_tactics.update_combo(delta)

	# --- 残血追击：附近只有一个血量比自己还低的残血敌人时，无视自身血量偏低也要追 ---
	# 追到「对方躲进防御塔 / 距离过远 / 对方回血或队友赶到」才放弃（见 _update_finish_chase）
	if _update_finish_chase(delta):
		return

	# --- 复活/泉水检测 ---
	var spawn = Vector3(-60, 0, 60) if hero.team == Config.Team.PLAYER else Vector3(60, 0, -60)
	if hero.global_position.distance_to(spawn) < AiConfig.SPAWN_DETECT_RANGE \
			and not has_respawned_recently and _fully_recovered():
		_assign_lane()
	if hero.global_position.distance_to(spawn) > AiConfig.SPAWN_LEAVE_RANGE:
		has_respawned_recently = false

	# --- 决策时钟 ---
	think_timer -= delta
	skill_tactics.update(delta)

	if think_timer <= 0:
		think_timer = AiConfig.JUNGLE_THINK_INTERVAL if _is_natural_jungler else AiConfig.LANE_THINK_INTERVAL
		# 难度反应延迟：低难度有概率跳过本帧决策
		if AiConfig.should_skip_think():
			return
		_try_teleport()
		brain.process_skill_windows()            # 多态: 李白/太乙等英雄特判
		summoner_tactics.try_use(current_action.type, lane)
		item_tactics.try_use(current_action.type)
		brain.process_special_actions(current_action.type)     # 多态: 兰陵王隐身等
		
		_decide()
		_try_teleport_route()
		_try_upgrade_skills()
		_ai_update_enhanced_attack_flag()   # 只有能收掉残血目标时才把强普位移交给普攻
		_try_travel_dash()   # 非战斗位移技能赶路（孙尚香/马可波罗等）
		# 敌方AI在无敌人视野时隐身
		if hero.team != Config.Team.PLAYER:
			var has_enemy_near := perception.find_nearest_enemy_hero(AiConfig.SIGHT_HERO) != null
			var has_enemy_minion := perception.find_nearest_enemy_minion(AiConfig.SIGHT_MINION) != null
			var has_enemy_turret := perception.find_nearest_enemy_turret(AiConfig.SIGHT_TURRET) != null
			hero.visible = has_enemy_near or has_enemy_minion or has_enemy_turret

	# --- 购买 ---
	buy_timer -= delta
	if buy_timer <= 0:
		buy_timer = AiConfig.BUY_INTERVAL
		_try_buy_equipment()

	# --- 恢复 ---
	if hero.skill_cooldowns[4] <= 0:
		# 张飞的「蓝」由狂意值驱动（HeroPassive 每帧回写），泉水无法回复，不能按普通蓝量判断
		var need_mana: bool = hero.display_name != "张飞" and hero.mana < hero.actual_mana_max * AiConfig.HEALTH_SAFE
		if hero.health < hero.actual_max_health * AiConfig.HEALTH_SAFE or need_mana:
			_try_use_recover()

	# --- 血包（泉水养伤时不抢血包，否则会半血跑出泉） ---
	if hero.health < hero.actual_max_health * 0.60 and not hero.is_in_own_fountain() \
			and not _is_action(AIAction.Type.TEMP_CLEAR) and _can_run_environment_action():
		var pack = _find_safe_health_pack()
		if pack and is_instance_valid(pack):
			_set_action(AIAction.Type.HEALTH_PACK, 860, AIAction.PauseClass.ENVIRONMENT, "血包")
			hero.move_target = pack.global_position
			return

	# --- 马超：安全时顺路拾枪，积攒强化普攻层数（不浪费在普通对拼） ---
	if _try_collect_enhanced_charge():
		return

	# --- 状态行为分发：RETREAT / RECALL_SAFE 只跑生存行为，不参与输出 ---
	match current_action.type:
		AIAction.Type.SAFE_RECALL:
			_recall_safe_behavior(delta)
		AIAction.Type.RETURN_TO_BASE:
			_retreat_behavior()
	if _is_action(AIAction.Type.SAFE_RECALL) or _is_action(AIAction.Type.RETURN_TO_BASE):
		return

	# --- 视野之灵：友方 AI 捡金币，敌方 AI 近身 1 米压制 5 秒 ---
	if _try_vision_spirit_contact():
		return

	# --- 近身目标技能 ---
	if hero.manual_target and is_instance_valid(hero.manual_target) and hero.manual_target.health > 0:
		var skill_dist := hero.global_position.distance_to(hero.manual_target.global_position)
		# 追英雄时先考虑位移贴脸（够不到才用，已在普攻距离内不会浪费）
		var used_dash: bool = hero.manual_target is Hero and _try_chase_dash(hero.manual_target)
		if not used_dash and skill_dist < AiConfig.SKILL_USE_RANGE:
			_try_use_skills(hero.manual_target)
	else:
		hero.manual_target = null








# ==================== 决策 ====================
# 每个 think tick 评估一次：先处理高地/塔防御与撤退/回城，再交给分路/打野策略
# ==================== 调试：思考过程 ====================

func _debug_lane() -> String:
	match lane:
		AiConfig.Lane.FARM: return "下路"
		AiConfig.Lane.MID: return "中路"
		AiConfig.Lane.CLASH: return "上路"
		_: return "野区"


func _debug_intent() -> String:
	if hero.is_recalling: return "recall"
	if hero.is_teleporting: return "rotate"
	match current_action.type:
		AIAction.Type.RETURN_TO_BASE: return "retreat"
		AIAction.Type.SAFE_RECALL: return "recall"
		AIAction.Type.DODGE: return "avoid"
	if hero.manual_target != null and is_instance_valid(hero.manual_target):
		var t = hero.manual_target
		var d: float = hero.global_position.distance_to(t.global_position)
		var hp: float = float(t.health) / maxf(1.0, float(t.get("max_health")))
		if hp <= 0.3: return "kill"
		if d > hero.attack_range * 0.01 + 1.0: return "chase"
		return "fight"
	if _is_action(AIAction.Type.JUNGLE_FARM): return "jungle" if lane == AiConfig.Lane.JUNGLE else "farm"
	return "push"


func _dbg_time() -> float:
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm != null and is_instance_valid(bm):
		return float(bm.get("game_time"))
	return Time.get_ticks_msec() * 0.001


func _dbg_add(txt: String) -> void:
	_dbg_log.append({"t": snappedf(_dbg_time(), 0.1), "s": txt})
	if _dbg_log.size() > 30:
		_dbg_log.pop_front()


func _debug_track() -> void:
	if current_action.type != _dbg_last_state:
		_dbg_add("状态 -> %s（目标=%s）" % [current_action.label(), _ent_name(hero.manual_target)])
		_dbg_last_state = current_action.type
	var tn := _ent_name(hero.manual_target)
	if tn != _dbg_last_target:
		_dbg_add("锁定目标 -> %s" % (tn if tn != "" else "无"))
		_dbg_last_target = tn
	if hero.casting_skill != _dbg_last_casting:
		_dbg_add("施法 %s（技能槽=%d）" % ["开始" if hero.casting_skill else "结束", int(hero.pending_skill_index)])
		_dbg_last_casting = hero.casting_skill
	if hero.is_recalling != _dbg_last_recall:
		_dbg_add("回城 %s" % ("开始" if hero.is_recalling else "中断/完成"))
		_dbg_last_recall = hero.is_recalling


func _vec2(v: Vector3) -> Vector2:
	return Vector2(snappedf(v.x, 0.1), snappedf(v.z, 0.1))


func _safe_name(e) -> String:
	if e == null or not is_instance_valid(e):
		return ""
	var v = e.get("display_name")
	if v != null:
		return str(v)
	return str(e.name)


func _ent_name(e) -> String:
	return _safe_name(e)


func _ent_desc(e) -> String:
	if e == null or not is_instance_valid(e):
		return ""
	var d: float = hero.global_position.distance_to(e.global_position)
	var mx: float = maxf(1.0, float(e.get("max_health") if e.get("max_health") != null else 1.0))
	var hp: float = float(e.get("health") if e.get("health") != null else 0.0)
	return "%s(%s) hp%d%% d%.1f" % [_safe_name(e), str(e.get_class()), int(round(hp / mx * 100.0)), d]


func _nearest_desc(e) -> String:
	if e == null or not is_instance_valid(e):
		return ""
	var d: float = hero.global_position.distance_to(e.global_position)
	return "%s(%s) d%.1f" % [_safe_name(e), str(e.get_class()), d]


func _is_threat_low() -> bool:
	if threat_model == null:
		return true
	var et: float = threat_model.enemy_threat()
	var at: float = threat_model.ally_threat()
	return et < 0.35 and (at - et) > -1.0


## 胶囊威胁指标：ThreatModel 的敌方/我方威胁值（血量×距离×视野衰减）
func _chip_threat() -> String:
	if threat_model == null:
		return "敌0.00/我0.00(低)"
	var et: float = threat_model.enemy_threat()
	var at: float = threat_model.ally_threat()
	var bal: float = at - et
	var lvl := "低"
	if et >= 1.2 or bal <= -1.0:
		lvl = "高"
	elif et >= 0.35:
		lvl = "中"
	return "敌%.2f/我%.2f(%s)" % [et, at, lvl]


## 胶囊换血层：TradePlanner 当前状态
func _chip_trade() -> String:
	if trade_planner == null:
		return "待机"
	if trade_planner.active_target != null and is_instance_valid(trade_planner.active_target):
		return "对拼中"
	if trade_planner.exit_timer > 0.0:
		return "退出"
	if trade_planner.cooldown > 0.0:
		return "冷却"
	return "待机"


## 胶囊动作：最新 Action + priority + 暂停分类
func _chip_action() -> String:
	if current_action == null:
		return "待命"
	var txt := current_action.label()
	if current_action.priority > 0:
		txt += "p%d" % current_action.priority
	if current_action.pause_class == AIAction.PauseClass.SURVIVAL:
		txt += "[生]"
	elif current_action.pause_class == AIAction.PauseClass.ENVIRONMENT:
		txt += "[环]"
	return txt


## 胶囊任务：团队任务（含暂停状态）/龙团/回城
func _chip_task(now: float = -1.0) -> String:
	if team_task != null and is_instance_valid(team_task) and team_task.is_active():
		var t := team_task.label()
		if _task_pause_active:
			t += "(暂停)"
		elif now >= 0.0:
			var left := maxf(0.0, float(team_task.expires_at) - now)
			t += " %ds" % int(ceil(left))
		return t
	if is_dragon_rally:
		return "龙团"
	if hero.is_recalling:
		return "回城"
	if hero.is_teleporting:
		return "支援"
	return ""


## 胶囊路径：R=风险，L=米
func _chip_path() -> String:
	if _ai_path.is_empty():
		return "直行"
	return "R%.2f L%.0f" % [_ai_path_risk, _ai_path_len]


## AI 决策胶囊简要信息（两行；血条 HUD / 联机广播共用，0.25s 缓存避免每帧感知开销）
func debug_chip_info() -> Dictionary:
	var now := Time.get_ticks_msec() * 0.001
	if now < _chip_next_t and not _chip_cache.is_empty():
		return _chip_cache
	_chip_next_t = now + 0.25
	var lane_short := _debug_lane().replace("路", "")
	var task := _chip_task(_game_time_now())
	var p1: Array = ["路:" + lane_short, "行:" + _chip_action()]
	if task != "":
		p1.append("任:" + task)
	var line1 := " · ".join(p1)

	var tgt := ""
	if hero.manual_target != null and is_instance_valid(hero.manual_target):
		tgt = _safe_name(hero.manual_target)
	elif team_task != null and is_instance_valid(team_task) and team_task.target_hero != null and is_instance_valid(team_task.target_hero):
		tgt = _safe_name(team_task.target_hero)
	elif _chase_target != null and is_instance_valid(_chase_target):
		tgt = _safe_name(_chase_target)
	var threat_txt := _chip_threat()
	var p2: Array = ["胁:" + threat_txt]
	if tgt != "":
		p2.append("标:" + tgt)
	p2.append("径:" + _chip_path())
	var trade := _chip_trade()
	if trade != "待机":
		p2.append("血:" + trade)
	var line2 := " · ".join(p2)

	var col := Color(0.52, 0.78, 1.0)
	if threat_txt.ends_with("(高)"):
		col = Color(1.0, 0.46, 0.38)
	elif threat_txt.ends_with("(中)"):
		col = Color(1.0, 0.78, 0.34)
	if current_action != null and current_action.type == AIAction.Type.TOWER_ESCAPE:
		col = Color(1.0, 0.35, 0.28)
	elif current_action != null and current_action.type == AIAction.Type.DODGE:
		col = Color(1.0, 0.62, 0.30)
	_chip_cache = {"line1": line1, "line2": line2, "r": col.r, "g": col.g, "b": col.b}
	return _chip_cache

## 当前对局时间（秒）；团队任务 expires_at 用的就是这个时钟
func _game_time_now() -> float:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	return float(bm.game_time) if bm != null else 0.0


## 单个 AI 的完整思考快照（JSON 安全；F3 与录像共用）
func debug_snapshot() -> Dictionary:
	var _gnow := _game_time_now()
	var _task_on: bool = team_task != null and is_instance_valid(team_task) and team_task.is_active()
	var sn: Dictionary = perception.snapshot()
	var tactics := {}
	if skill_tactics != null and skill_tactics.has_method("debug_snapshot"):
		tactics = skill_tactics.call("debug_snapshot")
	var skills := []
	for i in range(mini(3, hero.skill_cooldowns.size())):
		skills.append({"lv": int(hero.skill_levels[i]) if i < hero.skill_levels.size() else 0,
			"cd": snappedf(float(hero.skill_cooldowns[i]), 0.1)})
	var brain_path := ""
	if brain != null:
		brain_path = str(brain.get_script().resource_path.get_file().get_basename())
	var lane_txt := ""
	if lane_strategy != null:
		lane_txt = "bush=(%.1f,%.1f) pending=%d" % [lane_strategy.default_bush_pos.x, lane_strategy.default_bush_pos.z, int(lane_strategy.pending_lane)]
	var jungle_txt := ""
	if jungle_strategy != null:
		jungle_txt = "phase=%d idx=%d assigned=%d" % [int(jungle_strategy.current_phase), int(jungle_strategy._phase_index), int(jungle_strategy.assigned_lane)]
	return {
		"name": hero.display_name, "role": hero.role, "team": int(hero.team),
		"state": current_action.label(), "lane": _debug_lane(),
		"action_type": int(current_action.type), "action_priority": int(current_action.priority),
		"action_pause": int(current_action.pause_class), "team_paused": bool(_task_pause_active),
		"env_pause_used": bool(_env_pause_used),
		"path": {"risk": snappedf(_ai_path_risk, 0.01), "len": snappedf(_ai_path_len, 0.1)},
		"intent": _debug_intent(), "intent_target": _ent_name(hero.manual_target),
		"hp": int(hero.health), "hp_max": int(hero.actual_max_health),
		"mana": int(hero.mana), "mana_max": int(hero.actual_mana_max),
		"lvl": int(hero.level), "k": int(hero.kills), "d": int(hero.deaths), "a": int(hero.assists),
		"pos": _vec2(hero.global_position),
		"think": snappedf(think_timer, 0.01), "score": snappedf(decide_score, 0.01),
		"manual": _ent_desc(hero.manual_target), "chase": _ent_desc(_chase_target),
		"move": _vec2(hero.move_target) if hero.move_target != Vector3.ZERO else Vector2.ZERO,
		"perception": {
			"near_enemy_hero": _nearest_desc(sn.get("nearest_enemy_hero")),
			"near_enemy_minion": _nearest_desc(sn.get("nearest_enemy_minion")),
			"near_enemy_turret": _nearest_desc(sn.get("nearest_enemy_turret")),
			"near_friendly_turret": _nearest_desc(sn.get("nearest_friendly_turret")),
			"near_jungle": _nearest_desc(sn.get("nearest_jungle")),
			"near_health_pack": _nearest_desc(sn.get("nearest_health_pack")),
			"allies6": perception.count_ally_heroes_near(6.0), "enemies6": perception.count_enemy_heroes_near(6.0),
			"allies12": perception.count_ally_heroes_near(12.0), "enemies12": perception.count_enemy_heroes_near(12.0),
			"allies20": perception.count_ally_heroes_near(20.0), "enemies20": perception.count_enemy_heroes_near(20.0),
		},
		"combat": {
			"skills": skills,
			"enhanced": bool(hero.call("_enhanced_aa_queued")),
			"recall": snappedf(float(hero.recall_timer), 0.1),
			"teleport": snappedf(float(hero.teleport_timer), 0.1),
			"is_recalling": bool(hero.is_recalling),
			"is_teleporting": bool(hero.is_teleporting),
			"stuck": snappedf(float(hero.get("_stuck_timer")), 0.1),
			"move_lock": snappedf(maxf(0.0, float(hero.get("_move_lock_until")) - Time.get_ticks_msec() * 0.001), 0.1),
		},
		"tactics": tactics,
		"items": {"last": str(item_tactics.last_action)},
		"summoner": {"last": str(summoner_tactics.last_action)},
		"brain": brain_path,
		"threat": {
			"enemy": snappedf(threat_model.enemy_threat(), 0.01) if threat_model != null else 0.0,
			"ally": snappedf(threat_model.ally_threat(), 0.01) if threat_model != null else 0.0,
			"balance": snappedf(threat_model.threat_balance(), 0.01) if threat_model != null else 0.0,
		},
		"strategy": {"lane": lane_txt, "jungle": jungle_txt},
		"chip": debug_chip_info(),
		"game_time": snappedf(_gnow, 0.1),
		"task": team_task.label() if _task_on else "",
		"task_left": snappedf(maxf(0.0, float(team_task.expires_at) - _gnow), 0.1) if _task_on else -1.0,
		"task_paused": bool(_task_pause_active),
		"log": _dbg_log.duplicate(),
	}


func _decide():
	var candidates := _build_action_candidates()
	if candidates.is_empty():
		return
	var best := _pick_candidate(candidates)
	if best == null:
		return
	if current_action != null and current_action.is_active() and best.priority < current_action.priority:
		return
	_execute_candidate(best)


func _build_action_candidates() -> Array[AIAction]:
	var out: Array[AIAction] = []
	var gt := _game_time()

	# 本线塔防御
	var turret := _get_lane_turret_under_attack(lane)
	if turret != null and hero.global_position.distance_to(turret.global_position) <= AiConfig.DEFEND_LANE_TURRET_RANGE:
		out.append(AIAction.new(AIAction.Type.DEFEND_TOWER, 940, AIAction.PauseClass.SURVIVAL, "守塔"))

	# 大禹鼎
	var pot := _find_enemy_tripod(AiConfig.ENGAGE_RANGE + 2.0)
	if pot != null and _can_run_environment_action():
		var a := AIAction.new(AIAction.Type.TRIPOD, 810, AIAction.PauseClass.ENVIRONMENT, "大禹鼎")
		a.target = pot
		out.append(a)

	# 回城
	if hero.is_in_own_fountain() and not _fully_recovered():
		out.append(AIAction.new(AIAction.Type.SAFE_RECALL, 960, AIAction.PauseClass.SURVIVAL, "回城"))
	elif hero.health < hero.actual_max_health * AiConfig.HEALTH_RECALL:
		out.append(AIAction.new(AIAction.Type.SAFE_RECALL, 960, AIAction.PauseClass.SURVIVAL, "回城"))

	# 换血
	var trade_intent := trade_planner.evaluate()
	if not trade_intent.is_empty():
		var tact := str(trade_intent.get("action", ""))
		if tact == "exit":
			var a := AIAction.new(AIAction.Type.RETURN_TO_BASE, 900, AIAction.PauseClass.SURVIVAL, "换血退出")
			a.data = trade_intent
			out.append(a)
		elif tact == "enter" or tact == "hold":
			var tt = trade_intent.get("target")
			if tt != null and is_instance_valid(tt) and (tt as Hero).health > 0.0:
				var a := AIAction.new(AIAction.Type.TRADE, 945, AIAction.PauseClass.SURVIVAL, "换血")
				a.target = tt
				out.append(a)

	# 临时清兵
	if _can_run_environment_action():
		var m := _find_temp_clear_target()
		if m != null:
			var a := AIAction.new(AIAction.Type.TEMP_CLEAR, 850, AIAction.PauseClass.ENVIRONMENT, "临时清兵")
			a.target = m
			out.append(a)

	# 团队任务
	if team_task != null and team_task.is_expired(gt):
		team_task = null
		is_dragon_rally = false
	if team_task != null:
		out.append(AIAction.new(AIAction.Type.TEAM_TASK, int(team_task.priority), AIAction.PauseClass.NONE, team_task.label()))

	# 默认本地
	if _is_natural_jungler:
		out.append(AIAction.new(AIAction.Type.JUNGLE_FARM, 20, AIAction.PauseClass.NONE, "刷野"))
	else:
		out.append(AIAction.new(AIAction.Type.PUSH_LANE, 20, AIAction.PauseClass.NONE, "推线"))

	# 守塔 vs 回城：守塔点附近无敌人且自身 >15%，守塔优先；否则回城优先
	var defend := _first_candidate(out, AIAction.Type.DEFEND_TOWER)
	var recall := _first_candidate(out, AIAction.Type.SAFE_RECALL)
	if defend != null and recall != null:
		if perception.count_enemy_heroes_near_center(defend_pos(defend), 15.0) == 0 and hero.health > hero.actual_max_health * 0.15:
			recall.priority = 0
		else:
			defend.priority = 0
	return out


func _first_candidate(items: Array[AIAction], t: int) -> AIAction:
	for a in items:
		if a.type == t:
			return a
	return null


func defend_pos(_a: AIAction) -> Vector3:
	var turret := _get_lane_turret_under_attack(lane)
	return turret.global_position if turret != null else hero.global_position


func _pick_candidate(items: Array[AIAction]) -> AIAction:
	var best: AIAction = null
	for a in items:
		if a.priority <= 0:
			continue
		if best == null or a.priority > best.priority:
			best = a
	return best


func _execute_candidate(a: AIAction):
	match a.type:
		AIAction.Type.DEFEND_TOWER:
			_handle_lane_turret_defense()
		AIAction.Type.TRIPOD:
			hero.manual_target = a.target
			_set_action(AIAction.Type.TRIPOD, a.priority, a.pause_class, a.reason)
		AIAction.Type.SAFE_RECALL:
			_set_action(AIAction.Type.SAFE_RECALL, a.priority, a.pause_class, a.reason)
		AIAction.Type.RETURN_TO_BASE:
			hero.manual_target = null
			var retreat_pos := Vector3.ZERO
			if a.data.has("pos"):
				retreat_pos = a.data.get("pos", Vector3.ZERO)
			hero.move_target = retreat_pos
			_set_action(AIAction.Type.RETURN_TO_BASE, 900, a.pause_class, a.reason, a.data)
		AIAction.Type.TRADE:
			hero.manual_target = a.target
			hero.move_target = Vector3.ZERO
			_set_action(AIAction.Type.TRADE, a.priority, a.pause_class, a.reason)
		AIAction.Type.TEMP_CLEAR:
			hero.manual_target = a.target
			hero.move_target = Vector3.ZERO
			_temp_clearing = true
			_set_action(AIAction.Type.TEMP_CLEAR, a.priority, a.pause_class, a.reason)
		AIAction.Type.TEAM_TASK:
			_execute_team_task()
		AIAction.Type.JUNGLE_FARM:
			_execute_local_task(true)
		AIAction.Type.PUSH_LANE:
			_execute_local_task(false)


func _execute_team_task() -> void:
	var gt := _game_time()
	var tr := task_executor.execute(team_task, gt)
	if tr.is_empty():
		return
	if tr.has("lane"):
		lane = int(tr.get("lane", lane))
		if lane_strategy:
			lane_strategy.pending_lane = lane
	if tr.has("manual_target"):
		hero.manual_target = tr.get("manual_target")
	if tr.has("move_target"):
		hero.move_target = tr.get("move_target")
	if str(tr.get("state", "push")) == "retreat":
		_set_action(AIAction.Type.RETURN_TO_BASE, 900, AIAction.PauseClass.SURVIVAL, "任务撤退")
	else:
		_set_action(AIAction.Type.TEAM_TASK, int(team_task.priority), AIAction.PauseClass.NONE, team_task.label())
	if team_task.type != TeamTask.Type.PUSH_LANE and team_task.type != TeamTask.Type.PUSH_TOWER:
		return
	_execute_local_task(_is_natural_jungler)


func _execute_local_task(jungle: bool) -> void:
	var gt := _game_time()
	if jungle:
		if jungle_strategy:
			jungle_strategy.update_time(gt)
			jungle_strategy.decide()
		_set_action(AIAction.Type.JUNGLE_FARM)
		return
	if gt >= AiConfig.EARLY_GAME_END and is_dragon_rally:
		if not _is_dragon_alive():
			is_dragon_rally = false
			_assign_lane()
		else:
			_dragon_rally_behavior()
			if is_dragon_rally:
				_set_action(AIAction.Type.OBJECTIVE, 80, AIAction.PauseClass.NONE, "打龙")
				_sync_ai_movement()
			return
	if lane_strategy:
		lane_strategy.update_time(gt)
		var force_push := team_task != null and team_task.is_active() \
			and (team_task.type == TeamTask.Type.PUSH_LANE or team_task.type == TeamTask.Type.PUSH_TOWER)
		lane_strategy.decide(force_push)
		if lane != lane_strategy.lane:
			lane = lane_strategy.lane
	_set_action(AIAction.Type.PUSH_LANE)


func _game_time() -> float:
	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	return bm.game_time if bm != null else 0.0


func _find_temp_clear_target() -> Minion:
	var radius := 15.0 + clampf((hero.actual_move_speed - 6.0) / 2.0, 0.0, 5.0)
	var m: Minion = null
	var best_d := radius
	for e in hero.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) == int(hero.team) or (e as Minion).health <= 0.0:
			continue
		var d := hero.global_position.distance_to((e as Node3D).global_position)
		if d > best_d or _minion_under_unsafe_tower(e as Minion):
			continue
		if not _temp_clear_path_safe(e as Minion):
			continue
		best_d = d
		m = e as Minion
	if m == null:
		_temp_clearing = false
	return m


# 临时清兵任务：15–20m（随移速增加）内有敌方小兵就锁定，清完自动结束。
func _try_temp_clear() -> bool:
	var radius := 15.0 + clampf((hero.actual_move_speed - 6.0) / 2.0, 0.0, 5.0)
	var m: Minion = null
	var best_d := radius
	for e in hero.get_tree().get_nodes_in_group("minions"):
		if not (e is Minion) or int((e as Minion).team) == int(hero.team) or (e as Minion).health <= 0.0:
			continue
		var d := hero.global_position.distance_to((e as Node3D).global_position)
		if d > best_d or _minion_under_unsafe_tower(e as Minion):
			continue
		# 不仅目标不能在我方塔下，去目标的整条路线也不能穿过敌方塔射程。
		if not _temp_clear_path_safe(e as Minion):
			continue
		best_d = d
		m = e as Minion
	if m == null:
		_temp_clearing = false
		return false
	hero.manual_target = m
	hero.move_target = Vector3.ZERO
	_set_action(AIAction.Type.TEMP_CLEAR, 850, AIAction.PauseClass.ENVIRONMENT, "临时清兵")
	_temp_clearing = true
	return true


func _temp_clear_retarget_or_done() -> bool:
	if not _temp_clearing:
		return true
	var t = hero.manual_target
	if t != null and is_instance_valid(t) and t.health > 0.0:
		return false
	# 原目标死亡/失效：在英雄附近继续找敌方小兵接替，直到附近没有小兵才算清完
	var next := _find_temp_clear_target()
	if next != null:
		hero.manual_target = next
		hero.move_target = Vector3.ZERO
		_ai_path.clear()
		_temp_clearing = true
		return false
	_temp_clearing = false
	return true


func _temp_clear_path_safe(m: Minion) -> bool:
	if not PathFinder.initialized:
		return false
	var path := PathFinder.find_path(hero.global_position, m.global_position, Vector3.ZERO, hero.team)
	if path.is_empty():
		return false
	for p in path:
		for e in hero.get_tree().get_nodes_in_group("turrets"):
			if e is Turret and int((e as Turret).team) != int(hero.team) and (e as Turret).health > 0:
				if p.distance_to((e as Node3D).global_position) <= (e as Turret).attack_range * 0.01 + 1.0:
					return false
	return true


func _minion_under_unsafe_tower(m: Minion) -> bool:
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or int((e as Turret).team) == int(hero.team) or (e as Turret).health <= 0:
			continue
		var t := e as Turret
		if m.global_position.distance_to(t.global_position) > AiConfig.TOWER_ATTACK_RANGE:
			continue
		var cover := 0.0
		for n in hero.get_tree().get_nodes_in_group("minions"):
			if n is Minion and int((n as Minion).team) == int(hero.team) and (n as Minion).health > 0:
				if t.global_position.distance_to((n as Node3D).global_position) <= AiConfig.TOWER_ATTACK_RANGE:
					cover += (n as Minion).health
		if cover < 500.0:
			return true
	return false


# 由团队指挥官下发的结构化主线任务
func assign_team_task(task: TeamTask) -> void:
	if task == null:
		return
	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var now := bm.game_time if bm else 0.0
	if team_task != null and team_task.is_active():
		# 高优先级立即抢占；低优先级保留当前任务；同优先级在承诺窗口内不换。
		if task.priority < team_task.priority:
			return
		if task.priority == team_task.priority and now < _task_commit_until:
			return
	team_task = task
	_task_commit_until = now + 2.0
	_env_pause_used = false
	_task_pause_active = false
	if task.type == TeamTask.Type.OBJECTIVE:
		is_dragon_rally = true
		dragon_rally_pos = task.target_pos
	else:
		is_dragon_rally = false
	if task.lane >= 0:
		lane = task.lane
		if _is_natural_jungler and jungle_strategy:
			jungle_strategy.pending_lane = task.lane
		elif not _is_natural_jungler and lane_strategy:
			lane_strategy.pending_lane = task.lane


func task_feedback() -> Dictionary:
	var tname := ""
	var ttype := TeamTask.Type.NONE
	if team_task != null:
		tname = team_task.label()
		ttype = team_task.type
	return {
		"task": tname, "type": ttype, "lane": lane,
		"hp_ratio": hero.health / maxf(1.0, hero.actual_max_health),
		"threat": threat_model.enemy_threat(),
		"need_help": hero.health < hero.actual_max_health * 0.38 and threat_model.enemy_threat() > 0.8,
		"can_engage": hero.health > hero.actual_max_health * 0.45,
	}


# 由 BattleManager 统一调用的分路分配接口
func apply_team_lane(new_lane: int) -> void:
	if new_lane == AiConfig.Lane.JUNGLE:
		is_dragon_rally = true
		# 若从非 _distribute_lane_assignments 路径调用，兜底找最近的龙
		if dragon_rally_pos == Vector3.ZERO:
			var bt := get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if bt and bt.team_tactics:
				dragon_rally_pos = bt.team_tactics.dragon_pos_by_team.get(hero.team, Vector3.ZERO)
	elif new_lane >= 0:
		is_dragon_rally = false
		if _is_natural_jungler and jungle_strategy:
			jungle_strategy.pending_lane = new_lane
		elif not _is_natural_jungler and lane_strategy:
			lane_strategy.pending_lane = new_lane

# ==================== 视野之灵交互 ====================
# 友方 AI：未领奖的视野之灵在附近时主动走过去触碰（10 金币）。
# 敌方 AI：已进入草丛提供视野的视野之灵在附近时，走到 1 米内站定，累计 5 秒将其逼退。
func _try_vision_spirit_contact() -> bool:
	if not _can_run_environment_action():
		return false
	# 正在清兵/血包/换血/追击/守塔/任务时，不要被视野之灵改写移动目标
	if current_action != null and current_action.is_active() \
			and current_action.type not in [AIAction.Type.PUSH_LANE, AIAction.Type.JUNGLE_FARM, AIAction.Type.TEAM_TASK]:
		return false
	var tree := hero.get_tree()
	if tree == null:
		return false
	if hero.health < hero.actual_max_health * 0.45:
		return false
	# 附近有敌方英雄时优先战斗，不绕路去碰视野之灵
	if perception.count_enemy_heroes_near(7.0) > 0:
		return false
	var best = null
	var best_d := INF
	var best_friendly := false
	for s in tree.get_nodes_in_group("vision_spirits"):
		if not is_instance_valid(s):
			continue
		var friendly: bool = s.team == hero.team
		if friendly and s.gold_claimed:
			continue
		if not friendly and not s.vision_active:
			continue
		var d: float = hero.global_position.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
			best_friendly = friendly
	if best == null:
		return false
	var max_range := 24.0 if best_friendly else 18.0
	if best_d > max_range:
		return false
	hero.manual_target = null
	# 0.8 米内站定，确保进入视野之灵的 1 米判定圈
	hero.move_target = hero.global_position if best_d <= 0.8 else best.global_position
	_set_action(AIAction.Type.VISION_SPIRIT, 820, AIAction.PauseClass.ENVIRONMENT, "视野之灵")
	return true

# ==================== 六维指标计算 ====================

# ==================== 打龙集合 ====================

func _dragon_rally_behavior() -> void:
	# 无龙存活：在集合点附近找残血敌方英雄
	if dragon_rally_pos != Vector3.ZERO:
		var best_hero: Hero = null
		var best_hp := 99999.0
		for entity in hero.get_tree().get_nodes_in_group("heroes"):
			if not (entity is Hero) or entity.health <= 0 or entity.team == hero.team:
				continue
			var h := entity as Hero
			if h.is_untargetable_by_enemies():
				continue
			var dist = h.global_position.distance_to(dragon_rally_pos)
			if dist > 15.0:
				continue
			if h.health < best_hp:
				best_hp = h.health
				best_hero = h
		if best_hero:
			print("[HeroAI] %s 打龙：龙坑附近发现残血敌人 %s，血量=%.0f" % [hero.display_name, best_hero.display_name, best_hp])
			hero.manual_target = best_hero
			return
	# 优先找最近的存活龙/暴君
	var target: GameEntity = null
	var best_dist := 99999.0
	for entity in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		var m := entity as JungleMonster
		if m.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
			var battle = hero.get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if battle and battle.get_bonded_team(m) == hero.team:
				continue   # 原初羁绊：打这只龙伤害减半还会触发怒，不锁定
			var d = hero.global_position.distance_to(m.global_position)
			if d < best_dist:
				best_dist = d
				target = m
	if target:
		print("[HeroAI] %s 打龙：锁定目标 %s，距离=%.1f，血量=%.0f" % [hero.display_name, target.display_name if target is JungleMonster else target.name, best_dist, target.health])
		hero.manual_target = target
		return

	

	

	# 彻底找不到目标：恢复正常分路
	print("[HeroAI] %s 打龙：彻底无目标，取消打龙集合" % hero.display_name)
	is_dragon_rally = false
	_assign_lane()


func _is_dragon_alive() -> bool:
	for entity in hero.get_tree().get_nodes_in_group("jungle_monsters"):
		if not (entity is JungleMonster) or entity.health <= 0:
			continue
		var m := entity as JungleMonster
		if m.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
			return true
	return false


func _move_to_friendly_turret() -> void:
	var goal := _choose_safe_retreat_goal()
	if goal == Vector3.ZERO:
		var turret := perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR)
		if turret and is_instance_valid(turret):
			goal = turret.global_position
	_follow_safe_route(goal)


# 撤退行为：仅在 TradePlanner 退出后执行，只去它给的安全点；威胁降到低即完成。
func _retreat_behavior() -> void:
	hero.manual_target = null
	var goal := Vector3.ZERO
	if current_action != null and current_action.data.has("pos"):
		goal = current_action.data.get("pos", Vector3.ZERO)
	if goal != Vector3.ZERO:
		_follow_safe_route(goal)
	else:
		hero.move_target = Vector3.ZERO


# 选撤退目标：己方塔 + 泉水，按 A* 路径风险和距离评分。
func _choose_safe_retreat_goal() -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	if _retreat_goal_cache != Vector3.ZERO and now - _retreat_goal_time < 0.8:
		return _retreat_goal_cache
	var best := Vector3.ZERO
	var best_score := INF
	var fountain := Vector3(-62.0, 0.0, 62.0) if hero.team == Config.Team.PLAYER else Vector3(62.0, 0.0, -62.0)
	var candidates: Array[Vector3] = [fountain]
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) == int(hero.team) and (e as Turret).health > 0:
			candidates.append((e as Turret).global_position)
	for p in candidates:
		var d := hero.global_position.distance_to(p)
		var score := _path_risk(p) * 10.0 + d * 0.15
		if p == fountain:
			score += 4.0   # 泉水更安全但更远，只在塔位风险高时优先
		if score < best_score:
			best_score = score
			best = p
	_retreat_goal_cache = best
	_retreat_goal_time = now
	return best


# 用 A* 航点跟随目标；每 1 秒或目标变化时重规划。
func _follow_safe_route(goal: Vector3) -> void:
	if goal == Vector3.ZERO:
		return
	var now := Time.get_ticks_msec() * 0.001
	if goal.distance_to(_safe_route_goal) > 2.0 or now - _safe_route_plan_time > 1.0 \
			or _safe_route_path.is_empty() or _safe_route_index >= _safe_route_path.size():
		_safe_route_goal = goal
		_safe_route_path = MovementPlanner.plan(hero, goal, threat_model)
		_safe_route_index = 0
		_safe_route_plan_time = now
	if _safe_route_path.is_empty():
		hero.move_target = goal
		return
	while _safe_route_index < _safe_route_path.size() \
			and hero.global_position.distance_to(_safe_route_path[_safe_route_index]) < 1.4:
		_safe_route_index += 1
	if _safe_route_index >= _safe_route_path.size():
		hero.move_target = goal
	else:
		hero.move_target = _safe_route_path[_safe_route_index]


# 实际 A* 路径风险：敌方英雄视野 + 敌方塔危险区 + 路径长度。
func _path_risk(goal: Vector3) -> float:
	var path := PathFinder.find_path(hero.global_position, goal, Vector3.ZERO, hero.team)
	if path.is_empty():
		return 20.0
	var risk := 0.0
	for i in range(path.size()):
		var p: Vector3 = path[i]
		if i % 2 == 0:
			risk += float(perception.count_enemy_heroes_near_center(p, 8.0)) * 4.0
		for e in hero.get_tree().get_nodes_in_group("turrets"):
			if e is Turret and int((e as Turret).team) != int(hero.team) and (e as Turret).health > 0:
				if p.distance_to((e as Turret).global_position) <= (e as Turret).attack_range * 0.01 + 2.0:
					risk += 8.0
	return risk + path.size() * 0.04


# 是否站在己方塔保护范围内
func _is_under_own_tower() -> bool:
	var turret: Turret = perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_CLOSE)
	return turret != null and is_instance_valid(turret) \
		and hero.global_position.distance_to(turret.global_position) <= AiConfig.FRIENDLY_TURRET_CLOSE


func _retreat_from_turret(turret: Turret) -> void:
	# 沿英雄→塔的直线方向退到塔范围外
	var to_hero := (hero.global_position - turret.global_position).normalized()
	var safe_dist := turret.attack_range * 0.01 + 1.0  # 塔攻击范围 + 安全距离
	hero.move_target = turret.global_position + to_hero * safe_dist
	hero.manual_target = null


func _dodge_threats() -> bool:
	# 检测弹道威胁并侧移躲避
	var threats = perception.find_threatening_projectiles(AiConfig.DODGE_RANGE, AiConfig.DODGE_MARGIN)
	if threats.is_empty():
		_is_dodging = false
		return false
	# 首次检测到威胁时掷骰子决定是否躲避
	if not _is_dodging:
		if randf() > AiConfig.DODGE_CHANCE:
			return false
		_is_dodging = true
	# 计算躲避方向：取所有威胁方向的反方向加权平均（越近权重越大）
	var dodge_dir := Vector2.ZERO
	var total_weight := 0.0
	for t in threats:
		var weight := 1.0 / maxf(t["dist"], 0.5)
		total_weight += weight
		dodge_dir += t["threat_dir"] * weight
	if total_weight > 0:
		dodge_dir /= total_weight
	# 取威胁方向的垂直方向之一作为躲避方向
	var main_dir := dodge_dir.normalized()
	var perp_left := Vector2(-main_dir.y, main_dir.x)
	dodge_dir = perp_left
	var dodge_target := Vector3(hero.global_position.x + dodge_dir.x * 4.0, 0, hero.global_position.z + dodge_dir.y * 4.0)
	hero.move_target = dodge_target
	hero.manual_target = null
	return true



func _tower_guarding(target: Hero) -> Turret:
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or (e as Turret).health <= 0 or int((e as Turret).team) == int(hero.team):
			continue
		var t := e as Turret
		if target.global_position.distance_to(t.global_position) <= t.attack_range * 0.01:
			return t
	return null


func _is_target_safe(target: Hero) -> bool:
	var tower := _tower_guarding(target)
	if tower == null:
		return true
	# 手长：站塔外能打到目标
	var reach := hero.attack_range * 0.01
	if hero.global_position.distance_to(tower.global_position) > tower.attack_range * 0.01 \
			and hero.global_position.distance_to(target.global_position) <= reach + 1.0:
		return true
	# 必须越塔：关键技能爆发 + 护盾，估算塔伤次数
	return _estimate_tower_hits(target, tower) <= 2


func _estimate_tower_hits(target: Hero, tower: Turret) -> int:
	var ehp := target.health + target.shield_remaining
	var burst := _estimate_burst_damage(target)
	var dps := maxf(1.0, hero.actual_attack_damage * hero.attack_speed)
	var kill_time := maxf(0.0, ehp - burst) / dps + 1.6
	var interval := 1.0 / maxf(0.2, tower.attack_speed)
	return int(ceil(kill_time / interval))


func _estimate_burst_damage(target: Hero) -> float:
	var burst := hero.actual_attack_damage
	for i in range(mini(3, hero.skills.size())):
		var sk: Skill = hero.skills[i]
		if sk == null or sk.damage <= 0.0:
			continue
		if i >= hero.skill_levels.size() or hero.skill_levels[i] <= 0:
			continue
		if i < hero.skill_cooldowns.size() and hero.skill_cooldowns[i] > 0.0:
			continue
		if sk.cast_range > 0.0 and hero.global_position.distance_to(target.global_position) > sk.cast_range + 2.0:
			continue
		burst += sk.damage
	return burst


# 检测目标是否在其己方塔下
func _is_under_enemy_tower(target: Hero) -> bool:
	var tree := hero.get_tree()
	if not tree:
		return false
	for entity in tree.get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0:
			continue
		if entity.team != target.team:
			continue
		if target.global_position.distance_to(entity.global_position) < AiConfig.FRIENDLY_TURRET_CLOSE:
			return true
	return false


# ==================== 残血追击（收人头） ====================
# 每帧调用；返回 true = 本帧处于追击状态（_process 直接 return，不再跑常规决策）
func _update_finish_chase(delta: float) -> bool:
	if _chase_target != null and (not is_instance_valid(_chase_target) or _chase_target.health <= 0):
		_chase_target = null
		_chase_time = 0.0
	if _chase_target != null:
		var dist := hero.global_position.distance_to(_chase_target.global_position)
		var t_ratio := _chase_target.health / maxf(_chase_target.actual_max_health, 1.0)
		var give_up := dist > AiConfig.CHASE_ABORT_RANGE \
			or _is_under_enemy_tower(_chase_target) \
			or _chase_time > AiConfig.CHASE_MAX_TIME \
			or _chase_target.health >= hero.health \
			or t_ratio > AiConfig.CHASE_HP_RATIO + 0.15 \
			or _enemy_reinforced(_chase_target)
		if give_up:
			_chase_target = null
			_chase_time = 0.0
	if _chase_target == null:
		_chase_target = _pick_finish_target()
		if _chase_target == null:
			return false
	_chase_time += delta
	# Hero 自身带 AI 追击：manual_target 在射程外会自动朝目标移动（move_target 必须清空，否则优先于追击）
	hero.manual_target = _chase_target
	_set_action(AIAction.Type.FINISH_CHASE, 940, AIAction.PauseClass.SURVIVAL, "残血追击")
	# AI 自动追击已关闭；这里必须重新写 move_target，否则仅设 manual_target 会原地站住。
	_sync_ai_movement()
	# 够不到就先交位移技能贴脸（追击用），贴身后再交伤害技能
	if _try_chase_dash(_chase_target):
		return true
	if hero.global_position.distance_to(_chase_target.global_position) < AiConfig.SKILL_USE_RANGE:
		_try_use_skills(_chase_target)
	return true


## 附近唯一的「血量比自己还少」的残血敌人（不在塔下、没有敌人增援）才值得追
func _pick_finish_target() -> Hero:
	if hero.health < hero.actual_max_health * AiConfig.CHASE_MIN_SELF_RATIO:
		return null
	var best: Hero = null
	var count := 0
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity == hero:
			continue
		var eh := entity as Hero
		if eh.team == hero.team or eh.health <= 0:
			continue
		if eh.is_untargetable_by_enemies():
			continue
		if hero.global_position.distance_to(eh.global_position) > AiConfig.CHASE_START_RANGE:
			continue
		if _is_under_enemy_tower(eh):
			continue
		if _enemy_reinforced(eh):
			continue
		var ratio := eh.health / maxf(eh.actual_max_health, 1.0)
		if ratio > AiConfig.CHASE_HP_RATIO:
			continue
		if eh.health >= hero.health:
			continue
		best = eh
		count += 1
	if count != 1:
		return null
	return best


## 目标身边（CHASE_ALLY_GUARD 内）还有别的敌方英雄 → 视为有增援，不追
func _enemy_reinforced(target: Hero) -> bool:
	for entity in hero.get_tree().get_nodes_in_group("heroes"):
		if not (entity is Hero) or entity == target or entity == hero:
			continue
		var eh := entity as Hero
		if eh.team == hero.team or eh.health <= 0:
			continue
		if eh.global_position.distance_to(target.global_position) <= AiConfig.CHASE_ALLY_GUARD:
			return true
	return false



# 塔下我方小兵总血量
func _sum_ally_minion_hp_near(center: Vector3, radius: float) -> float:
	var total := 0.0
	var tree := hero.get_tree()
	if not tree:
		return 0.0
	for entity in tree.get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0:
			continue
		if entity.team != hero.team:
			continue
		if center.distance_to(entity.global_position) > radius:
			continue
		total += (entity as Minion).health
	return total


# 后撤至本条分路上血量>1000且离敌方水晶最近的我方小兵旁
func _retreat_to_safe_minion_on_lane() -> void:
	var best: Minion = null
	var best_progress := -9999.0  # 沿兵线向敌方水晶的进度
	var tree := hero.get_tree()
	if not tree:
		return
	# 敌方水晶方向：以中路为参考，player方敌方水晶在(53,0,-53)，enemy方在(-53,0,53)
	var enemy_crystal := Vector3(53, 0, -53) if hero.team == Config.Team.PLAYER else Vector3(-53, 0, 53)
	for entity in tree.get_nodes_in_group("minions"):
		if not (entity is Minion) or entity.health <= 0:
			continue
		var m := entity as Minion
		if m.team != hero.team:
			continue
		if m.line != lane:
			continue
		if m.health <= 1000.0:
			continue
		# 进度 = 离敌方水晶越近越好（距离的负数）
		var progress := -m.global_position.distance_to(enemy_crystal)
		if progress > best_progress:
			best_progress = progress
			best = m
	if best:
		hero.move_target = best.global_position
		hero.manual_target = null


# ==================== 辅助函数 ====================

static func _enemy_team_for(h: Hero) -> int:
	return Config.Team.ENEMY if h.team == Config.Team.PLAYER else Config.Team.PLAYER


static func maxf(a: float, b: float) -> float:
	return a if a > b else b


static func clampf(val: float, lo: float, hi: float) -> float:
	return lo if val < lo else (hi if val > hi else val)


# ==================== 恢复 ====================
func _try_use_recover():
	if hero.skills.size() < 4:
		return
	var idx = 4
	if hero.skill_cooldowns[idx] > 0 or hero.mana < hero.skills[idx].mana_cost:
		return
	var low_mana := hero.display_name != "张飞" and hero.mana < hero.actual_mana_max * AiConfig.HEALTH_SAFE
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_SAFE or low_mana:
		hero._start_casting(4, hero.skills[4], hero.global_position)


# ==================== 安全回城 ====================
func _recall_safe_behavior(delta):
	# 孙悟空：飞行中/已在泉水由这里统一处理——必须血蓝全满才出泉，且不在泉里反复起飞
	if hero.display_name == "孙悟空":
		if hero.wukong_cloud_flying:
			return
		if hero.is_in_own_fountain():
			if hero.is_recalling:
				hero.cancel_recall()
			hero.move_target = Vector3.ZERO
			hero.manual_target = null
			hero.current_target = null
			if _fully_recovered():
				_assign_lane()
			return
	# 英雄特判（孙悟空筋斗云飞行中/已在泉水）→ 本英雄自行处理
	if brain.handle_recall_safe():
		return
	# 已回满：不管是否还在泉水判定圈内，都结束回城，避免走出泉边后又去安全点二次回城。
	if _fully_recovered():
		if hero.is_recalling:
			hero.cancel_recall()
		hero.move_target = Vector3.ZERO
		hero.manual_target = null
		_finish_current_action()
		_assign_lane()
		return
	# 已在自家泉水：养伤到血/蓝回到阈值才出门；未回满则原地待着（别走去“安全点”或重复回城）
	if hero.is_in_own_fountain():
		if hero.is_recalling:
			hero.cancel_recall()
		hero.move_target = Vector3.ZERO
		hero.manual_target = null
		if _fully_recovered():
			_assign_lane()
		return
	# 读条中敌人压过来（AI 读条期间不能动）：立刻取消，换到别的安全点再回城
	if hero.is_recalling \
			and perception.count_enemy_heroes_near(AiConfig.RECALL_DANGER_RADIUS) > 0:
		hero.cancel_recall()
	var safe_pos = _find_safe_recall_spot()
	if safe_pos == Vector3.ZERO:
		_leave_recall_spot()
		return
	if hero.global_position.distance_to(safe_pos) > 2.0:
		# 去安全点的路上有敌人/敌塔危险区，或敌人已压到身边：先拉开，不闷头跑/读条
		if perception.count_enemy_heroes_near(AiConfig.RECALL_DANGER_RADIUS) > 0 \
				or _recall_path_threatened(safe_pos):
			_leave_recall_spot()
			return
		_follow_safe_route(safe_pos)
	elif not hero.is_recalling and not _fully_recovered():
		hero.start_recall()


# 泉水养伤是否完成：血量（有蓝英雄再加蓝量）都回到 HEALTH_RECOVERED 才算满
func _fully_recovered() -> bool:
	# 孙悟空：回城后必须状态回满（血/蓝 100%）才离开泉水，避免半血出门再被打回城
	if hero.display_name == "孙悟空":
		if hero.health < hero.actual_max_health - 0.5:
			return false
		if hero.actual_mana_max > 0.0 and hero.mana < hero.actual_mana_max - 0.5:
			return false
		return true
	# 必须真正回满（留 0.5 浮点容差），不能 98% 就出泉。
	if hero.health < hero.actual_max_health - 0.5:
		return false
	# 张飞不消耗/回复普通蓝，蓝条由狂意值回写；只看血量即可离泉
	if hero.display_name == "张飞":
		return true
	if hero.actual_mana_max > 0.0 and hero.mana < hero.actual_mana_max - 0.5:
		return false
	return true

	


func _find_safe_health_pack() -> HealthPack:
	var enemy_pack: HealthPack = null
	var friend_pack: HealthPack = null
	var enemy_d := 20.0
	var friend_d := 20.0
	for e in hero.get_tree().get_nodes_in_group("health_packs"):
		if not (e is HealthPack):
			continue
		var pack := e as HealthPack
		if not pack.available:
			continue
		var d := hero.global_position.distance_to(pack.global_position)
		if d > 20.0:
			continue
		if int(pack.team) == int(hero.team):
			if d < friend_d:
				friend_d = d
				friend_pack = pack
		else:
			if not _enemy_pack_safe(pack):
				continue
			if d < enemy_d:
				enemy_d = d
				enemy_pack = pack
	return enemy_pack if enemy_pack != null else friend_pack


func _enemy_pack_safe(pack: HealthPack) -> bool:
	if perception.count_enemy_heroes_near_center(pack.global_position, 20.0) > 0:
		return false
	var tower := _enemy_tower_containing(pack.global_position)
	if tower != null and _sum_ally_minion_hp_near(tower.global_position, AiConfig.TOWER_ATTACK_RANGE) <= 1500.0:
		return false
	return true


func _enemy_tower_containing(pos: Vector3) -> Turret:
	for e in hero.get_tree().get_nodes_in_group("turrets"):
		if e is Turret and int((e as Turret).team) != int(hero.team) and (e as Turret).health > 0:
			if pos.distance_to((e as Node3D).global_position) <= (e as Turret).attack_range * 0.01:
				return e as Turret
	return null


func _find_safe_recall_spot() -> Vector3:
	var now := Time.get_ticks_msec() * 0.001
	if _recall_spot_cache != Vector3.ZERO and now - _recall_spot_time < 0.8:
		return _recall_spot_cache
	# 只在塔区/草丛附近没有敌方英雄时选点：读条 7 秒，敌人贴脸就会被打断甚至带走
	var turret := _pick_safe_recall_turret()
	if turret and is_instance_valid(turret):
		var dir = (hero.global_position - turret.global_position).normalized()
		_recall_spot_cache = turret.global_position + dir * 2
		_recall_spot_time = now
		return _recall_spot_cache
	var bush := perception.find_nearest_bush(AiConfig.FRIENDLY_TURRET_FAR)
	if bush != Vector3.ZERO and not _recall_point_threatened(bush) and not _recall_path_threatened(bush):
		_recall_spot_cache = bush
		_recall_spot_time = now
		return bush
	_recall_spot_cache = Vector3.ZERO
	_recall_spot_time = now
	return Vector3.ZERO


# 回城塔：离自己最近、且塔周围没有敌方英雄
func _pick_safe_recall_turret() -> Turret:
	var tree := hero.get_tree()
	if tree == null:
		return null
	var best: Turret = null
	var best_score := INF
	for entity in tree.get_nodes_in_group("turrets"):
		if not is_instance_valid(entity) or not (entity is Turret):
			continue
		var t := entity as Turret
		if t.health <= 0.0 or t.team != hero.team:
			continue
		var d: float = hero.global_position.distance_to(t.global_position)
		if d > AiConfig.FRIENDLY_TURRET_FAR:
			continue
		if _recall_point_threatened(t.global_position):
			continue
		var spot: Vector3 = t.global_position + (hero.global_position - t.global_position).normalized() * 2.0
		# 用实际 A* 路线风险选塔，而不是只比较直线距离
		var score := _path_risk(spot) * 10.0 + d * 0.15
		if score < best_score:
			best_score = score
			best = t
	return best


# 回城路径是否穿过敌人/敌塔危险区：沿英雄→安全点分段采样，避免"点安全但路上被截"
func _recall_path_threatened(target: Vector3) -> bool:
	var start: Vector3 = hero.global_position
	var total: float = start.distance_to(target)
	if total < 0.5:
		return false
	var steps: int = maxi(2, int(ceil(total / 5.0)))
	var tree := hero.get_tree()
	for i in range(steps + 1):
		var p: Vector3 = start.lerp(target, float(i) / float(steps))
		if perception.count_enemy_heroes_near_center(p, AiConfig.RECALL_DANGER_RADIUS) > 0:
			return true
		if tree == null:
			continue
		for ent in tree.get_nodes_in_group("turrets"):
			if not (ent is Turret) or ent.health <= 0.0 or ent.team == hero.team:
				continue
			var t := ent as Turret
			var reach: float = t.attack_range * 0.01 + 2.0
			if p.distance_to(t.global_position) <= reach:
				return true
	return false


# 该位置附近（RECALL_SPOT_CLEAR 内）有没有敌方英雄
func _recall_point_threatened(pos: Vector3) -> bool:
	return perception.count_enemy_heroes_near_center(pos, AiConfig.RECALL_SPOT_CLEAR) > 0


# 己方塔区全被敌人压着：背向最近的敌人退开，等敌人走了再回城（不原地读条送人头）
func _leave_recall_spot() -> void:
	hero.manual_target = null
	_move_to_friendly_turret()

# ==================== 技能使用 ====================
func _try_use_skills(target: GameEntity):
	skill_tactics.try_best_combo(target, brain.get_combos(target))


# ==================== 购买 ====================
func _get_recommended_items() -> Array:
	return ItemDatabase.get_recommended_items(hero.display_name)

var recommended_items: Array = []

func _try_buy_equipment():
	if hero.gold < AiConfig.MIN_BUY_GOLD:
		return

	if hero.equipment_slots.size() >= Hero.MAX_EQUIPMENT_SLOTS:
		for item_id in recommended_items:
			if hero.equipment_slots.has(item_id):
				continue
			if hero.buy_equipment(item_id):
				return
		# 尝试升级每件已有的低级装备（而非仅最后一件）
		for owned_id in hero.equipment_slots:
			var owned_tier = ItemDatabase.get_item(owned_id).get("tier", 1)
			if owned_tier >= 3:
				continue
			if owned_tier == 2:
				for rid in recommended_items:
					if hero.equipment_slots.has(rid):
						continue
					if owned_id in ItemDatabase.get_item(rid).get("requires", []):
						if hero.buy_equipment(rid):
							return
			else:
				for rid in recommended_items:
					if hero.equipment_slots.has(rid):
						continue
					for req_id in ItemDatabase.get_item(rid).get("requires", []):
						if hero.equipment_slots.has(req_id):
							continue
						var req_reqs = ItemDatabase.get_item(req_id).get("requires", [])
						if owned_id in req_reqs and not hero.equipment_slots.has(req_id):
							if hero.buy_equipment(req_id):
								return
		return

	for item_id in recommended_items:
		if hero.equipment_slots.has(item_id):
			continue
		if ItemDatabase.can_build(item_id, hero.equipment_slots):
			var cost = ItemDatabase.get_synthesis_cost(item_id, hero.equipment_slots)
			if hero.gold >= cost and hero.buy_equipment(item_id):
				return
		var target = _find_missing_basic(hero, item_id)
		if target != "":
			var req_item = ItemDatabase.get_item(target)
			if not req_item.is_empty():
				var can_build = req_item.has("requires") and ItemDatabase.can_build(target, hero.equipment_slots)
				var has_slot = hero.equipment_slots.size() < Hero.MAX_EQUIPMENT_SLOTS or can_build
				var cost = req_item["cost"]
				if can_build:
					cost = ItemDatabase.get_synthesis_cost(target, hero.equipment_slots)
				if hero.gold >= cost and has_slot and hero.buy_equipment(target):
					return
		return


func _find_missing_basic(hero_h: Hero, target_id: String) -> String:
	var target = ItemDatabase.get_item(target_id)
	if target.is_empty() or not target.has("requires"):
		return target_id
	for req_id in target.get("requires", []):
		var owned_count = 0
		for oid in hero_h.equipment_slots:
			if oid == req_id:
				owned_count += 1
		var needed_count = 0
		for r in target["requires"]:
			if r == req_id:
				needed_count += 1
		if owned_count < needed_count:
			return _find_missing_basic(hero_h, req_id)
	return target_id
# ==================== 防御塔防御 ====================

# 检测防御塔是否正在被敌方英雄威胁（仅英雄，忽略小兵）
func _is_turret_threatened(turret: Turret) -> bool:
	if not is_instance_valid(turret) or turret.health <= 0:
		return false
	if turret.current_target and turret.current_target is Minion:
		return true
	return false

# 根据坐标判断防御塔所属分路（与小兵分路算法一致：abs(x)对比abs(z)）
func _get_turret_lane(turret: Turret) -> int:
	var s = turret.global_position.x + turret.global_position.z
	if s > 0:
		return AiConfig.Lane.FARM
	elif s < 0:
		return AiConfig.Lane.CLASH
	else:
		return AiConfig.Lane.MID

# 获取本线上正在被攻击的己方防御塔
func _get_lane_turret_under_attack(lane: int) -> Turret:
	var tree := hero.get_tree()
	
	var turret_count = 0
	for entity in tree.get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0:
			continue
		if entity.team != hero.team:
			continue
		var turret := entity as Turret
		if _get_turret_lane(turret) != lane:
			continue
		turret_count += 1
		if _is_turret_threatened(turret):
			return turret
	return null

# 查找被攻击的高地塔或水晶
# 优先级: 水晶 > 血量最低的高地塔
func _find_threatened_high_or_crystal() -> Turret:
	var crystal: Turret = null
	var high_turrets: Array[Turret] = []
	var tree := hero.get_tree()
	if not tree:
		return null
	for entity in tree.get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0:
			continue
		if entity.team != hero.team:
			continue
		var turret := entity as Turret
		if turret.display_name == "crystal":
			if _is_turret_threatened(turret):
				crystal = turret
		elif turret.tower_type == "high":
			if _is_turret_threatened(turret):
				high_turrets.append(turret)
	# 水晶最高优先级
	if crystal:
		return crystal
	# 其次血量最低的高地塔
	if high_turrets.size() > 0:
		high_turrets.sort_custom(func(a, b): return a.health < b.health)
		return high_turrets[0]
	return null

# 高地塔/水晶防御（覆盖所有状态，在_decide中作为P0调用）
# 返回true表示正在执行防御行动，应跳过其余决策
func _handle_high_defense() -> bool:
	var target := _find_threatened_high_or_crystal()
	if target == null or not is_instance_valid(target):
		return false
	var dist := hero.global_position.distance_to(target.global_position)
	# 距离太远不响应（避免全场 AI 都回防）
	if dist > AiConfig.DEFEND_LANE_TURRET_RANGE:
		return false
	if dist <= AiConfig.FRIENDLY_TURRET_CLOSE:
		# 已到塔边：优先打正在拆塔的敌方小兵（塔的 current_target 可能是英雄/空），并清掉旧 move_target
		var defender := _defense_target_for_turret(target)
		hero.manual_target = defender if (defender != null and is_instance_valid(defender) and defender.health > 0) else null
		if hero.manual_target != null:
			hero.move_target = Vector3.ZERO
	else:
		# 还没到：先跑过去（只换目标不移动 = 原地补兵，等于没防守）
		hero.manual_target = null
		hero.move_target = target.global_position
	_set_action(AIAction.Type.PUSH_LANE)
	return true

## 回防目标：优先塔当前仇敌；否则选塔附近最近的敌方小兵（拆塔主力），再退到敌方英雄
func _defense_target_for_turret(turret: Turret) -> GameEntity:
	if turret == null or not is_instance_valid(turret):
		return null
	var cur = turret.current_target
	if cur != null and is_instance_valid(cur) and cur.health > 0.0 and cur.team != hero.team:
		return cur
	var tree := hero.get_tree()
	if tree == null:
		return null
	var best_minion: GameEntity = null
	var best_minion_d := 14.0
	var best_hero: GameEntity = null
	var best_hero_d := 14.0
	for ent in tree.get_nodes_in_group("entities"):
		if not (ent is GameEntity) or ent == hero or ent.health <= 0.0 or ent.team == hero.team:
			continue
		var d: float = ent.global_position.distance_to(turret.global_position)
		if d > 14.0:
			continue
		if ent is Minion:
			if d < best_minion_d:
				best_minion_d = d
				best_minion = ent
		elif ent is Hero:
			if d < best_hero_d:
				best_hero_d = d
				best_hero = ent
	if best_minion != null:
		return best_minion
	return best_hero


func _handle_lane_turret_defense() -> bool:
	var turret := _get_lane_turret_under_attack(lane)
	if not turret or not is_instance_valid(turret):
		return false
	var dist := hero.global_position.distance_to(turret.global_position)
	# 距离太远不响应（避免全场 AI 都跑过来）
	if dist > AiConfig.DEFEND_LANE_TURRET_RANGE:
		return false
	# 还没走到塔边 → 先赶路；否则接手塔的仇恨目标
	if dist > AiConfig.FRIENDLY_TURRET_CLOSE:
		hero.manual_target = null
		hero.move_target = turret.global_position
		_set_action(AIAction.Type.DEFEND_TOWER, 930, AIAction.PauseClass.SURVIVAL, "守塔")
		return true
	var defender := _defense_target_for_turret(turret)
	if defender != null and is_instance_valid(defender) and defender.health > 0:
		hero.manual_target = defender
		hero.move_target = Vector3.ZERO   # 清掉“跑到塔中心”的旧移动指令，否则会压着目标不走、也不普攻
	else:
		hero.manual_target = null
	_set_action(AIAction.Type.DEFEND_TOWER, 930, AIAction.PauseClass.SURVIVAL, "守塔")
	return true


## 最近的敌方大禹治疗鼎（大招乾鼎不可攻击，跳过）
func _find_enemy_tripod(max_dist: float) -> Tripod:
	var best: Tripod = null
	var best_d := max_dist
	for t in get_tree().get_nodes_in_group("tripods"):
		if not (t is Tripod) or t.health <= 0 or t.team == hero.team or t.is_r_tripod:
			continue
		var d: float = hero.global_position.distance_to(t.global_position)
		if d < best_d:
			best_d = d
			best = t
	return best
