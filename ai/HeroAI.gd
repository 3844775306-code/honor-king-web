# HeroAI — 单个 AI 英雄的决策器（挂在 Hero 下，每英雄一个）。
# 只负责「打谁 / 去哪 / 放什么技能」：结论写入 hero.manual_target / hero.move_target / _start_casting()，
# 移动、寻路、普攻、施法由 Hero/GameEntity 用与玩家相同的原语执行。
# 分层：AiPerception 感知 → SkillTactics/SummonerTactics/ItemActiveTactics 战术
#      → LaneStrategy / JungleStrategy 阶段策略（0-4min）→ TeamTactics 团队分配（4min+，由 BattleManager 驱动）
#      → HeroBrain 英雄特判。计时与阈值见 AiConfig。
class_name HeroAI
extends Node

enum State { PUSH, FARM, RETREAT, RECALL, AVOID, RECALL_SAFE }  # 行为标签，供战术层判断；真正的分支在 _decide

var state: int = State.PUSH
var lane: int = AiConfig.Lane.MID
var hero: Hero
var perception: AiPerception
var skill_tactics: SkillTactics
var summoner_tactics: SummonerTactics
var item_tactics: ItemActiveTactics
var brain: HeroBrain
var think_timer: float = 0.0
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
var _defending_high_turret: Turret = null

func _ready():
	if get_parent() is Hero:
		hero = get_parent() as Hero
	else:
		for child in get_parent().get_children():
			if child is Hero and child.team != Config.Team.PLAYER:
				hero = child
				break
	perception = AiPerception.new(hero)
	skill_tactics = SkillTactics.new(hero, perception)
	summoner_tactics = SummonerTactics.new(hero, perception)
	item_tactics = ItemActiveTactics.new(hero, perception)
	brain = HeroBrain.create(hero.display_name, hero, perception, skill_tactics)
	skill_tactics.brain = brain   # 技能层走英雄特判钩子（后羿大招/刘禅拆塔），不再硬编码名字
	recommended_items = _get_recommended_items()
	_assign_lane()
	# 初始化新AI策略模块
	lane_strategy = LaneStrategy.new(hero, perception, lane)
	jungle_strategy = JungleStrategy.new(hero, perception)

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
	state = State.FARM if lane == AiConfig.Lane.JUNGLE else State.PUSH
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
	var zone = battle._get_teleport_zone_for_hero(hero)
	if zone:
		var minion = perception.find_nearest_ally_minion_on_lane(lane)
		if minion:
			battle.request_teleport(hero, minion)


# ==================== 技能升级 ====================
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
# 让 AI 在「走过去」而非接战/撤退时用位移类技能(技能类型4/self_displacement>0，如孙尚香Q翻滚、
# 马可波罗W漫游)沿 move_target 方向瞬移一段，加快回线/转线/刷野。仅当直线无墙(网格逐格采样)、
# 附近无可见敌英雄/不在敌塔射程内才施放，避免把位移浪费在战斗外/跳进墙里。
func _try_travel_dash():
	# 只在推进/刷野这类「走路」状态下赶路；撤退/回城/躲避交给各自逻辑处理
	if state != State.PUSH and state != State.FARM:
		return
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
	if dist < AiConfig.TRAVEL_DASH_MIN_DIST:
		return
	# 附近有可见敌方英雄：位移保留给先手/逃生
	if perception.find_nearest_enemy_hero(AiConfig.TRAVEL_DASH_ENEMY_GUARD) != null:
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
	var end := hero.global_position + dir * sk.self_displacement
	# 直线段逐格采样：有任何不可通行格(墙/地图边界)则不跳，防止卡进墙里
	if _dash_line_blocked(hero.global_position, end):
		return
	# 落点不进入任何敌方防御塔射程（避免赶路滚进塔里白挨打）
	if _dash_landing_in_enemy_turret(end):
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


# ==================== 主循环 ====================
func _process(delta):
	# --- 塔攻击检测 ---
	if hero.under_tower_attack:
		hero.tower_attack_timer -= delta
		if hero.tower_attack_timer <= 0:
			hero.under_tower_attack = false
			hero.tower_attacker = null
		elif hero.tower_attacker and is_instance_valid(hero.tower_attacker):
			# 立即沿直线退出塔的攻击范围
			_retreat_from_turret(hero.tower_attacker)
	# --- 弹道躲避（每帧） ---
	if _dodge_threats():
		return
	if hero.manual_target and hero.manual_target is Hero and _is_under_enemy_tower(hero.manual_target ):hero.set_manual_target(null)

	if not is_instance_valid(hero) or hero.is_dead:
		has_respawned_recently = false
		return

	# --- 连招链推进：起手技能之后按段间隔自动衔接下一段，目标失效/换目标即中止 ---
	skill_tactics.update_combo(delta)

	# --- 复活/泉水检测 ---
	var spawn = Vector3(-60, 0, 60) if hero.team == Config.Team.PLAYER else Vector3(60, 0, -60)
	if hero.global_position.distance_to(spawn) < AiConfig.SPAWN_DETECT_RANGE and not has_respawned_recently:
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
		summoner_tactics.try_use(state, lane)
		item_tactics.try_use(state)
		brain.process_special_actions(state)     # 多态: 兰陵王隐身等
		
		_decide()
		_try_upgrade_skills()
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
		if hero.health < hero.actual_max_health * AiConfig.HEALTH_SAFE or hero.mana < hero.actual_mana_max * AiConfig.HEALTH_SAFE:
			_try_use_recover()

	# --- 血包（泉水养伤时不抢血包，否则会半血跑出泉） ---
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_LOW and not hero.is_in_own_fountain():
		var pack = perception.find_health_pack_on_lane(lane)
		if pack and is_instance_valid(pack):
			hero.move_target = pack.global_position
			return

	# --- 状态行为分发 ---
	if state == State.RECALL_SAFE:
		_recall_safe_behavior(delta)


	# --- 近身目标技能 ---
	if hero.manual_target and is_instance_valid(hero.manual_target) and hero.manual_target.health > 0:
		var skill_dist := hero.global_position.distance_to(hero.manual_target.global_position)
		if skill_dist < AiConfig.SKILL_USE_RANGE:
			_try_use_skills(hero.manual_target)
	else:
		hero.manual_target = null








# ==================== 决策（六维加权指标） ====================
# 每0.5秒评估，6项指标加权求和，阈值判定行为
const SCORE_HERO_DIFF_W: float = 4.0       # 人数差权重
const SCORE_ECONOMY_W: float = 3.0         # 经济差权重
const SCORE_SKILL_CD_W: float = 0        # 技能CD差权重
const SCORE_MINION_W: float = 0          # 小兵战力差权重
const SCORE_DIVE_W: float = 4.0            # 越塔人数差权重
const SCORE_TURRET_W: float = 2.0          # 防御塔血量差权重

const SCORE_ATTACK_THRESHOLD: float = 4.0   # >4 攻击残血英雄
const SCORE_RETREAT_THRESHOLD: float = -4.0 # <-4 向己方塔移动
const SCORE_SWITCH_THRESHOLD: float = -8.0  # <-8 切换分路/打野

func _decide():
	var tree := hero.get_tree()
	for turret in tree.get_nodes_in_group("turrets"):
		if turret.display_name == "crystal" and turret.team == hero.team: 
			for entity in tree.get_nodes_in_group("minions"):
				if entity.team != hero.team and turret.global_position.distance_to(entity.global_position) < 15:
					hero.manual_target = entity
					return
		
	# P0: 高地塔/水晶防御（覆盖所有状态）
	if _handle_high_defense():
		return

	# P1: 本线防御塔防御（外塔/内塔）
	if _handle_lane_turret_defense():
		return

	# 泉水养伤：在自家泉水范围内血/蓝没回到阈值前不出门（原来只要血量>2000 就走，等于半血出门）
	if hero.is_in_own_fountain() and not _fully_recovered():
		state = State.RECALL_SAFE
		return

	if hero.health < hero.actual_max_health * AiConfig.HEALTH_RECALL:
		state = State.RECALL_SAFE
		return

	var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var gt := bm.game_time if bm else 0.0

	# 同步分路到策略模块
	if not _is_natural_jungler:
		if lane_strategy:
			lane_strategy.lane = lane
	else:
		if jungle_strategy and lane != AiConfig.Lane.JUNGLE:
			jungle_strategy.assigned_lane = lane

	if gt < AiConfig.EARLY_GAME_END:
		# === 0-4分钟：早期对线 ===
		if _is_natural_jungler:
			if jungle_strategy:
				jungle_strategy.update_time(gt)
				jungle_strategy.decide()
			state = State.FARM
		else:
			if lane_strategy:
				lane_strategy.update_time(gt)
				lane_strategy.decide()
				# 中路换线同步回HeroAI
				if lane != lane_strategy.lane:
					lane = lane_strategy.lane
			state = State.PUSH
	else:
		# === 4分钟+：团队分推（分路由 BattleManager 统一分配） ===

		# 打龙集合检查
		if is_dragon_rally:
			if not _is_dragon_alive():
				print("[HeroAI] t=%.0f %s 龙已死，取消打龙集合" % [(get_tree().get_first_node_in_group("battle_manager") as BattleManager).game_time if get_tree().get_first_node_in_group("battle_manager") else 0.0, hero.display_name])
				is_dragon_rally = false
				_assign_lane()
			else:
				_dragon_rally_behavior()
				return

		# 正常分路行为
		if _is_natural_jungler:
			if jungle_strategy:
				jungle_strategy.update_time(gt)
				jungle_strategy.decide()
			state = State.FARM
		else:
			if lane_strategy:
				lane_strategy.update_time(gt)
				lane_strategy.decide()
				if lane != lane_strategy.lane:
					lane = lane_strategy.lane
			state = State.PUSH


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
	var turret := perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR)
	if turret and is_instance_valid(turret):
		hero.move_target = turret.global_position


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
	if hero.skill_cooldowns[idx] <= 0 and hero.mana >= hero.skills[idx].mana_cost:
		if hero.health < hero.actual_max_health * AiConfig.HEALTH_SAFE or hero.mana < hero.actual_mana_max * AiConfig.HEALTH_SAFE:
			hero._start_casting(4, hero.skills[4], hero.global_position)


# ==================== 安全回城 ====================
func _recall_safe_behavior(delta):
	# 英雄特判（孙悟空筋斗云飞行中/已在泉水）→ 本英雄自行处理
	if brain.handle_recall_safe():
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
	var safe_pos = _find_safe_recall_spot()
	if safe_pos != Vector3.ZERO:
		if hero.global_position.distance_to(safe_pos) > 2.0:
			hero.move_target = safe_pos
		else:
			if not hero.is_recalling:
				hero.start_recall()
	else:
		_move_to_friendly_turret()


# 泉水养伤是否完成：血量（有蓝英雄再加蓝量）都回到 HEALTH_RECOVERED 才算满
func _fully_recovered() -> bool:
	if hero.health < hero.actual_max_health * AiConfig.HEALTH_RECOVERED:
		return false
	if hero.actual_mana_max > 0.0 and hero.mana < hero.actual_mana_max * AiConfig.HEALTH_RECOVERED:
		return false
	return true

	


func _find_safe_recall_spot() -> Vector3:
	var turret = perception.find_nearest_friendly_turret(AiConfig.FRIENDLY_TURRET_FAR)
	if turret and is_instance_valid(turret):
		var dir = (hero.global_position - turret.global_position).normalized()
		return turret.global_position + dir * 2
	return perception.find_nearest_bush(AiConfig.FRIENDLY_TURRET_FAR)

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
		# 已到塔边：直接接手塔的仇恨目标
		var attacker = target.current_target
		hero.manual_target = attacker if (attacker and is_instance_valid(attacker) and attacker.health > 0) else null
	else:
		# 还没到：先跑过去（只换目标不移动 = 原地补兵，等于没防守）
		hero.manual_target = null
		hero.move_target = target.global_position
	return true

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
		return true
	var attacker = turret.current_target
	if attacker and is_instance_valid(attacker) and attacker.health > 0:
		hero.manual_target = attacker
	return true
