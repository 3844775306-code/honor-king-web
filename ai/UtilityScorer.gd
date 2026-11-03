class_name UtilityScorer
extends RefCounted
## 意愿评分：把固定优先级替换为按战场信息计算的 utility（0~1），再映射到 1~900。
## 生存类硬约束仍由 HeroAI 前置分支处理，不进入本评分池。

const MAX_PRIORITY := 900


static func _u(v: float) -> float:
	return clampf(v, 0.0, 1.0)


static func to_priority(u: float) -> int:
	return clampi(int(round(_u(u) * float(MAX_PRIORITY))), 1, MAX_PRIORITY)


static func _tree(hero: Hero):
	return hero.get_tree()


static func _heroes(tree, team: int) -> Array:
	var out: Array = []
	for e in tree.get_nodes_in_group("heroes"):
		if e is Hero and int((e as Hero).team) == team and (e as Hero).health > 0.0:
			out.append(e)
	return out


static func _adv(tree, team: int) -> float:
	var a: int = _heroes(tree, team).size()
	var b: int = _heroes(tree, 1 - team).size()
	return _u((float(a - b) + 3.0) / 6.0)


static func _enemy_near(tree, team: int, pos: Vector3, radius: float) -> int:
	var n := 0
	for e in _heroes(tree, 1 - team):
		if (e as Hero).global_position.distance_to(pos) <= radius:
			n += 1
	return n


static func _ally_near(tree, team: int, pos: Vector3, radius: float) -> int:
	var n := 0
	for e in _heroes(tree, team):
		if (e as Hero).global_position.distance_to(pos) <= radius:
			n += 1
	return n


static func _safe_at(tree, team: int, pos: Vector3, radius: float = 12.0) -> float:
	return _u(1.0 - float(_enemy_near(tree, team, pos, radius)) / 3.0)


static func _travel(ai: HeroAI, d: float) -> float:
	var spd: float = maxf(ai.hero.actual_move_speed * 0.01, 0.1)
	var t: float = d / spd
	return _u(1.0 - t / 8.0)


static func _threat(ai: HeroAI) -> float:
	var v := 0.0
	if ai.threat_model != null:
		v = ai.threat_model.enemy_threat() / 2.0
	return _u(v)


static func _hp(h: Hero) -> float:
	return _u(h.health / maxf(h.actual_max_health, 1.0))


static func _mp(h: Hero) -> float:
	if h.actual_mana_max <= 0.0:
		return 1.0
	return _u(h.mana / h.actual_mana_max)


static func _tower_low(t) -> float:
	if t == null or not is_instance_valid(t) or not (t is Turret):
		return 0.0
	var tt := t as Turret
	return _u(1.0 - tt.health / maxf(tt.max_health, 1.0))


static func _nearest_enemy(tree, team: int, pos: Vector3) -> Hero:
	var best: Hero = null
	var bd := INF
	for e in _heroes(tree, 1 - team):
		var d: float = (e as Hero).global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


static func _nearest_tower(tree, team: int, pos: Vector3, only_enemy: bool = true) -> Turret:
	var best: Turret = null
	var bd := INF
	for e in tree.get_nodes_in_group("turrets"):
		if not (e is Turret):
			continue
		var t := e as Turret
		if t.health <= 0.0:
			continue
		if only_enemy and int(t.team) == team:
			continue
		var d: float = t.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = t
	return best


static func _skill_ready(h: Hero) -> float:
	var ready := 0.0
	for i in range(mini(3, h.skills.size())):
		if i < h.skill_levels.size() and int(h.skill_levels[i]) <= 0:
			continue
		if i < h.skill_cooldowns.size() and float(h.skill_cooldowns[i]) <= 0.0:
			ready = 1.0
			break
	if h.summoner_skill != null and h.summoner_cooldown <= 0.0:
		ready = maxf(ready, 0.6)
	return ready


# ==================== 团队任务层 ====================

static func team_task_priority(tt: TeamTactics, h: Hero, task_type: int, target_pos: Vector3,
		target_hero: Hero = null) -> int:
	var tree = h.get_tree()
	var team: int = int(h.team)
	var u := 0.0
	match task_type:
		TeamTask.Type.DEFEND_LANE:
			var crystal_threat: float = float(tt._enemy_minions_near_crystal(team, 30.0).size()) / 6.0
			var tower := tt._crystal_of(team)
			var tp: Vector3 = tower.global_position if tower != null else target_pos
			var low: float = _tower_low(tower)
			var d: float = h.global_position.distance_to(tp)
			u = 0.45 * _u(crystal_threat) + 0.25 * low + 0.20 * _safe_at(tree, team, tp) + 0.10 * _u(1.0 - (d / maxf(h.actual_move_speed * 0.01, 0.1)) / 8.0)
		TeamTask.Type.PUSH_TOWER:
			var gold_diff: int = tt._get_total_team_gold(team) - tt._get_total_team_gold(tt._enemy_team(team))
			var gold_lead := _u(float(maxi(gold_diff, 0)) / 10000.0)
			var owns: int = 0
			for e in tree.get_nodes_in_group("minions"):
				if e is Minion and int((e as Minion).team) == team and (e as Minion).health > 0.0 \
						and (e as Node3D).global_position.distance_to(target_pos) <= 15.0:
					owns += 1
			var wave := _u(float(owns) / 5.0)
			var tower_low: float = _tower_low(_nearest_tower(tree, team, target_pos))
			var epic_recent := 0.0
			if tt.bm != null and int(tt.bm.last_dragon_kill_team) == team \
					and tt.bm.game_time - float(tt.bm.last_dragon_kill_time) <= 12.0:
				epic_recent = 1.0
			var enemy_defense := _u(float(_enemy_near(tree, team, target_pos, 20.0)) / 5.0)
			u = 0.30 * _adv(tree, team) + 0.20 * gold_lead + 0.20 * wave + 0.15 * tower_low \
				+ 0.15 * epic_recent - 0.25 * enemy_defense
		TeamTask.Type.INVADE_JUNGLE:
			var camp := 0
			for e in tree.get_nodes_in_group("jungle_monsters"):
				if e is JungleMonster and (e as JungleMonster).health > 0.0 \
						and BattleManager.in_enemy_jungle_zone((e as Node3D).global_position, team):
					camp += 1
			var gold_diff2: int = tt._get_total_team_gold(team) - tt._get_total_team_gold(tt._enemy_team(team))
			u = 0.35 * _adv(tree, team) + 0.25 * _u(float(camp) / 6.0) \
				+ 0.15 * (1.0 if _is_jungler(h) else 0.3) \
				+ 0.15 * _u(1.0 - h.global_position.distance_to(target_pos) / maxf(h.actual_move_speed * 0.01, 0.1) / 8.0) \
				+ 0.10 * _u(float(maxi(gold_diff2, 0)) / 10000.0) \
				- 0.20 * _u(float(_enemy_near(tree, team, target_pos, 15.0)) / 3.0)
		TeamTask.Type.OBJECTIVE:
			var gold_diff3: int = tt._get_total_team_gold(team) - tt._get_total_team_gold(tt._enemy_team(team))
			var parity := _u(1.0 - absf(float(gold_diff3)) / 10000.0)
			var ally_near := _u(float(_ally_near(tree, team, target_pos, 15.0)) / 5.0)
			var dead:= 0
			for e in tree.get_nodes_in_group("heroes"):
				if e is Hero and int((e as Hero).team) != team and (e as Hero).health <= 0.0:
					dead += 1
			u = 0.30 * parity + 0.25 * ally_near + 0.20 * _u(float(dead) / 5.0) \
				+ 0.15 * _safe_at(tree, team, target_pos) \
				+ 0.10 * _u(1.0 - (h.global_position.distance_to(target_pos) / maxf(h.actual_move_speed * 0.01, 0.1)) / 8.0)
		TeamTask.Type.GANK:
			var gs := 0.0
			if target_hero != null and is_instance_valid(target_hero):
				gs = tt._gank_score(team, target_hero)
			u = _u(gs / 5.0)
		TeamTask.Type.PEEL:
			var carry: Hero = target_hero
			if carry == null or not is_instance_valid(carry) or carry.health <= 0.0:
				return 1
			var carry_threat := _u(float(_enemy_near(tree, team, carry.global_position, 10.0)) / 3.0)
			var carry_low := 1.0 - _hp(carry)
			var self_near := _u(1.0 - h.global_position.distance_to(carry.global_position) / 12.0)
			var dive := _u(float(_enemy_near(tree, team, carry.global_position, 6.0)) / 2.0)
			u = 0.40 * carry_threat + 0.25 * carry_low + 0.20 * self_near + 0.15 * dive
		_:
			# PUSH_LANE / 其它兜底
			var own_minions := 0
			for e in tree.get_nodes_in_group("minions"):
				if e is Minion and int((e as Minion).team) == team and (e as Minion).health > 0.0 \
						and (e as Node3D).global_position.distance_to(h.global_position) <= 15.0:
					own_minions += 1
			var t2 := _nearest_tower(tree, team, target_pos)
			u = 0.35 * _u(float(own_minions) / 5.0) + 0.25 * _safe_at(tree, team, h.global_position) \
				+ 0.20 * _tower_low(t2) + 0.10 * (1.0 if _is_jungler(h) else 0.5) \
				+ 0.10 * _u(1.0 - h.global_position.distance_to(target_pos) / 40.0)
	# 团队任务个人适配 + 任务类型价值（统一量纲用）
	var fit := 0.75 + 0.25 * _role_fit(h, task_type)
	var task_value := 1.0
	match task_type:
		TeamTask.Type.DEFEND_LANE:
			task_value = 1.8
		TeamTask.Type.PUSH_TOWER:
			task_value = 2.5
		TeamTask.Type.INVADE_JUNGLE:
			task_value = 1.7
		TeamTask.Type.OBJECTIVE:
			task_value = 1.8
		TeamTask.Type.GANK:
			task_value = 1.8
		TeamTask.Type.PEEL:
			task_value = 1.5
		TeamTask.Type.PUSH_LANE:
			task_value = 1.3
	return to_priority(u * fit * task_value)


static func _is_jungler(h: Hero) -> bool:
	for c in h.get_children():
		if c is HeroAI and bool((c as HeroAI)._is_natural_jungler):
			return true
	return false


static func _role_fit(h: Hero, task_type: int) -> float:
	match task_type:
		TeamTask.Type.GANK:
			return 1.0 if str(h.role) in ["刺客", "战士"] else 0.5
		TeamTask.Type.PUSH_TOWER:
			return 1.0 if str(h.role) in ["射手", "战士", "坦克"] else 0.55
		TeamTask.Type.INVADE_JUNGLE:
			return 1.0 if _is_jungler(h) else 0.3
		TeamTask.Type.PEEL:
			return 1.0 if str(h.role) in ["辅助", "坦克"] else 0.4
		TeamTask.Type.OBJECTIVE:
			return 0.8
		_:
			return 0.7


static func hero_team_task_priority(ai: HeroAI, t: TeamTask) -> int:
	if t == null:
		return 1
	var bn = ai.hero.get_tree().get_first_node_in_group("battle_manager")
	if bn == null or bn.get("team_tactics") == null:
		return clampi(int(t.priority), 1, MAX_PRIORITY)
	return team_task_priority(bn.team_tactics, ai.hero, int(t.type), t.target_pos, t.target_hero)


# ==================== 英雄 Action 层 ====================

static func action_priority(ai: HeroAI, type: int, ctx: Dictionary = {}) -> int:
	var h: Hero = ai.hero
	if h == null or not is_instance_valid(h):
		return 1
	var tree = h.get_tree()
	var team: int = int(h.team)
	var hp: float = _hp(h)
	var low_hp: float = 1.0 - hp
	var mp: float = _mp(h)
	var low_mp: float = 1.0 - mp
	var u := 0.0
	match type:
		AIAction.Type.SAFE_RECALL:
			var no_blue := 0.0
			if h.actual_mana_max > 0.0 and not bool(h.blue_buff_active) and mp < 0.5:
				no_blue = 1.0
			u = 0.40 * low_hp + 0.30 * low_mp + 0.20 * _threat(ai) + 0.10 * no_blue
			# 硬性：身边 6m 内有敌方英雄时，回城价值压到极低，避免贴脸读条
			if _enemy_near(tree, team, h.global_position, 6.0) > 0:
				u = minf(u, 0.12)
		AIAction.Type.RETURN_TO_BASE:
			var cd := 0.0
			if ai.trade_planner != null:
				cd = _u(ai.trade_planner.cooldown / 8.0)
			u = 0.35 * _threat(ai) + 0.25 * low_hp + 0.15 * cd + 0.15 * _safe_at(tree, team, h.global_position) + 0.10 * _u(float(_enemy_near(tree, team, h.global_position, 6.0)) / 2.0)
		AIAction.Type.DEFEND_TOWER:
			var tur: Turret = ctx.get("turret")
			var tp: Vector3 = tur.global_position if tur != null else h.global_position
			var enemy_minions:= 0
			for e in tree.get_nodes_in_group("minions"):
				if e is Minion and int((e as Minion).team) != team and (e as Minion).health > 0.0 \
						and (e as Node3D).global_position.distance_to(tp) <= 12.0:
					enemy_minions += 1
			var under := 1.0 if tur != null and tur.health < tur.max_health else 0.0
			u = 0.35 * _tower_low(tur) + 0.25 * under + 0.20 * _u(float(enemy_minions) / 4.0) \
				+ 0.10 * hp + 0.10 * _travel(ai, h.global_position.distance_to(tp))
		AIAction.Type.TRADE:
			var target: Hero = ctx.get("target")
			if target == null or not is_instance_valid(target) or target.health <= 0.0:
				return 1
			var adv_hp := _u(hp - _hp(target))
			var target_low := 1.0 - _hp(target)
			var ally_adv := _u((float(_ally_near(tree, team, h.global_position, 12.0) - _enemy_near(tree, team, h.global_position, 12.0)) + 3.0) / 6.0)
			var no_tower := 1.0 - _u(float(_enemy_near(tree, team, h.global_position, 8.0)) / 3.0)
			u = 0.30 * adv_hp + 0.20 * target_low + 0.15 * ally_adv + 0.15 * no_tower \
				+ 0.10 * _skill_ready(h) + 0.10 * _u(1.0 - h.global_position.distance_to(target.global_position) / 8.0)
			u *= 0.55 + 0.45 * maxf(adv_hp, target_low)
			# 超出自己能打到的距离，换血价值大幅下降（10m 外不应压过团队任务）
			var reach: float = h.attack_range * 0.01 + 1.5
			u *= 0.40 + 0.60 * _u(1.0 - h.global_position.distance_to(target.global_position) / reach)
			# 敌人在身边时必须先处理战斗，给近身换血额外加成
			u *= 1.0 + 0.60 * _u(1.0 - h.global_position.distance_to(target.global_position) / 6.0)
		AIAction.Type.FINISH_CHASE:
			var ct: Hero = ctx.get("target")
			if ct == null or not is_instance_valid(ct) or ct.health <= 0.0:
				return 1
			var no_tower2 := 1.0 if not _under_enemy_tower(tree, team, h.global_position) else 0.0
			var support := _u(float(_ally_near(tree, team, h.global_position, 12.0)) / 3.0)
			u = 0.30 * (1.0 - _hp(ct)) + 0.20 * _u(1.0 - ct.health / maxf(h.health, 1.0)) \
				+ 0.20 * no_tower2 + 0.15 * support + 0.15 * _skill_ready(h)
		AIAction.Type.TEMP_CLEAR:
			var tm: GameEntity = ctx.get("target")
			var gold_risk := 0.5
			if tm != null and is_instance_valid(tm):
				gold_risk = 0.5 + 0.5 * (1.0 - _u(tm.health / maxf(tm.max_health, 1.0)))
			var lane_pressure := _u(float(_enemy_near(tree, team, h.global_position, 12.0)) / 3.0)
			u = 0.35 * gold_risk + 0.20 * lane_pressure + 0.20 * _safe_at(tree, team, h.global_position) \
				+ 0.15 * _travel(ai, h.global_position.distance_to(tm.global_position) if tm != null else 0.0) \
				+ 0.10 * (0.0 if ai.team_task != null else 1.0)
		AIAction.Type.BLUE_BUFF:
			var bb: GameEntity = ctx.get("target")
			var bd := h.global_position.distance_to(bb.global_position) if bb != null else 99.0
			u = 0.40 * low_mp + 0.25 * (1.0 if bd <= 12.0 else 0.0) + 0.20 * _safe_at(tree, team, h.global_position) \
				+ 0.15 * _travel(ai, bd)
		AIAction.Type.TRIPOD:
			var pot: GameEntity = ctx.get("target")
			var pv := 0.5
			if pot != null and is_instance_valid(pot):
				pv = 1.0 - _u(pot.health / maxf(pot.max_health, 1.0))
			var e_absent := 1.0 - _u(float(_enemy_near(tree, team, h.global_position, 15.0)) / 3.0)
			u = 0.45 * pv + 0.25 * _safe_at(tree, team, h.global_position) \
				+ 0.20 * _travel(ai, h.global_position.distance_to(pot.global_position) if pot != null else 0.0) \
				+ 0.10 * e_absent
		AIAction.Type.JUNGLE_FARM:
			var camp_d := 99.0
			for e in tree.get_nodes_in_group("jungle_monsters"):
				if e is JungleMonster and (e as JungleMonster).health > 0.0 \
						and (e as JungleMonster).team == Config.Team.NEUTRAL:
					camp_d = minf(camp_d, h.global_position.distance_to((e as Node3D).global_position))
			u = 0.35 * (1.0 if camp_d <= 12.0 else 0.0) + 0.25 * (1.0 if _is_jungler(h) else 0.3) \
				+ 0.20 * _safe_at(tree, team, h.global_position) + 0.20 * _travel(ai, camp_d)
			if _enemy_near(tree, team, h.global_position, 6.0) > 0:
				u *= 0.25   # 敌人在身边时不能无视敌人去推线/刷野
		AIAction.Type.PUSH_LANE:
			var own_minions2 := 0
			for e in tree.get_nodes_in_group("minions"):
				if e is Minion and int((e as Minion).team) == team and (e as Minion).health > 0.0 \
						and (e as Node3D).global_position.distance_to(h.global_position) <= 15.0:
					own_minions2 += 1
			var tw := _nearest_tower(tree, team, h.global_position)
			u = 0.30 * _u(float(own_minions2) / 5.0) + 0.20 * _safe_at(tree, team, h.global_position) \
				+ 0.10 * _tower_low(tw) + 0.10 * 0.7
			if _enemy_near(tree, team, h.global_position, 6.0) > 0:
				u *= 0.25   # 敌人在身边时不能无视敌人去推线/刷野
		AIAction.Type.TEAM_TASK:
			if ai.team_task != null:
				return hero_team_task_priority(ai, ai.team_task)
			return 0
		AIAction.Type.DODGE, AIAction.Type.TOWER_ESCAPE:
			return 1000
		_:
			u = 0.3
	return to_priority(u)


## 原型用候选生成：原有候选 + 敌人贴脸时的撤退/换血候选
static func synthetic_candidates(ai: HeroAI) -> Array:
	var out: Array = ai._build_action_candidates()
	var h: Hero = ai.hero
	if h == null or not is_instance_valid(h):
		return out
	var tree = h.get_tree()
	var team: int = int(h.team)
	var near := _nearest_enemy(tree, team, h.global_position)
	var has_trade := false
	var has_retreat := false
	for a in out:
		if int(a.type) == int(AIAction.Type.TRADE):
			has_trade = true
		if int(a.type) == int(AIAction.Type.RETURN_TO_BASE):
			has_retreat = true
	if near != null and h.global_position.distance_to(near.global_position) <= 10.0:
		if not has_trade:
			var ta := AIAction.new(AIAction.Type.TRADE, action_priority(ai, AIAction.Type.TRADE, {"target": near}),
				AIAction.PauseClass.SURVIVAL, "近身换血")
			ta.target = near
			out.append(ta)
		if not has_retreat:
			var ra := AIAction.new(AIAction.Type.RETURN_TO_BASE, action_priority(ai, AIAction.Type.RETURN_TO_BASE),
				AIAction.PauseClass.SURVIVAL, "贴脸撤退")
			out.append(ra)
	return out

static func _under_enemy_tower(tree, team: int, pos: Vector3) -> bool:
	var t := _nearest_tower(tree, team, pos)
	if t == null:
		return false
	return pos.distance_to(t.global_position) <= t.attack_range * 0.01 + 2.0









