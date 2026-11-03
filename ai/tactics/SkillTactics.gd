class_name SkillTactics
extends RefCounted
# 施法规则以 docs/AI_SKILL_RULES.md 为唯一规则源；改规则必须同步文档。

var hero: Hero
var perception: AiPerception
var brain: HeroBrain = null   # 英雄特判钩子（对塔放技能 / 后羿大招等），由 HeroAI 注入
var skill_feed_timer: float = 0.0

# --- 连招链状态（起手段释放后由 update_combo 按段间间隔衔接） ---
var _combo_skills: Array = []
var _combo_step: int = 0
var _combo_target: GameEntity = null
var _combo_wait: float = 0.0


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception


func debug_snapshot() -> Dictionary:
	var tn := ""
	if _combo_target != null and is_instance_valid(_combo_target):
		tn = str(_combo_target.display_name)
	return {"combo_step": int(_combo_step), "combo_len": _combo_skills.size(),
		"combo_target": tn, "combo_wait": snappedf(float(_combo_wait), 0.1),
		"feed": snappedf(float(skill_feed_timer), 0.1)}


func update(delta: float) -> void:
	if skill_feed_timer > 0:
		skill_feed_timer -= delta


# ==================== 连招系统 ====================

# 尝试最佳连招 → 单技能评分 依次回退
# combos: Array[Dictionary] = [{name, skills:[idx,...], priority:0.8}]
func try_best_combo(target: GameEntity, combos: Array) -> bool:
	if _turret_blocked(target):
		return false
	if skill_feed_timer > 0:
		return false

	# 按优先级排序连招
	combos.sort_custom(func(a, b): return a.priority > b.priority)

	for combo in combos:
		if _can_execute_combo(combo, target):
			_execute_combo(combo, target)
			return true

	# 无可用连招 → 回退到最佳单技能
	return use_best_skill(target, 0.0)


# 检查连招所有技能是否可用
func _can_execute_combo(combo: Dictionary, target: GameEntity) -> bool:
	var skills: Array = combo.get("skills", [])
	if skills.is_empty():
		return false
	for idx in skills:
		if idx >= hero.skills.size():
			return false
		if hero.skill_levels[idx] <= 0:
			return false
		if hero.skill_cooldowns[idx] > 0:
			return false
		if hero.mana < hero.skills[idx].mana_cost:
			return false
		if idx == 2 and not _ult_allowed(target):
			return false
		if not _can_use_skill_on(idx, target):
			return false
		if not _skill_in_range(idx, target):
			return false
		if _low_mana_skill_blocked(idx, target):
			return false
	return true


# 执行连招起手技能，并记录后续段（由 update_combo 衔接）
func _execute_combo(combo: Dictionary, target: GameEntity) -> void:
	var skills: Array = combo.get("skills", [])
	var first_idx: int = skills[0]
	skill_feed_timer = AiConfig.SKILL_FEED_COOLDOWN
	_start_combo_skill(first_idx, target)
	_combo_skills = skills
	_combo_step = 0
	_combo_target = target
	_combo_wait = _step_gap(hero.skills[first_idx])


# 每帧推进连招链：目标失效 / 换目标 / 受控 / 不可行动 → 直接中止
func update_combo(delta: float) -> bool:
	if _combo_skills.is_empty():
		return false
	if not is_instance_valid(_combo_target) or _combo_target.health <= 0 \
			or not is_instance_valid(hero) or hero.is_dead \
			or hero.manual_target != _combo_target \
			or hero.casting_skill or hero.channeling_skill_index >= 0 \
			or hero.stun_timer > 0.0 or hero.knockup_timer > 0.0 \
			or hero.froze_timer > 0.0 or hero.suppress_timer > 0.0 or hero.silence_timer > 0.0:
		_clear_combo()
		return false
	_combo_wait -= delta
	if _combo_wait > 0.0:
		return false
	_combo_step += 1
	if _combo_step >= _combo_skills.size():
		_clear_combo()
		return false  # 连招结束
	var idx: int = _combo_skills[_combo_step]
	if idx >= hero.skills.size() or hero.skills[idx] == null \
			or hero.skill_levels[idx] <= 0 or hero.skill_cooldowns[idx] > 0.0 \
			or hero.mana < hero.skills[idx].mana_cost \
			or not _skill_in_range(idx, _combo_target) \
			or (idx == 2 and not _ult_allowed(_combo_target)) \
			or not _can_use_skill_on(idx, _combo_target):
		_clear_combo()
		return false
	_start_combo_skill(idx, _combo_target)
	_combo_wait = _step_gap(hero.skills[idx])
	return true


func _start_combo_skill(idx: int, target: GameEntity) -> void:
	hero._start_casting(idx, hero.skills[idx], _aim_pos(target))


# 段间间隔：至少等技能自身前摇结束，再留一点手感间隔
func _step_gap(sk: Skill) -> float:
	return maxf(sk.cast_time, AiConfig.COMBO_STEP_GAP)


func _clear_combo() -> void:
	_combo_skills = []
	_combo_step = 0
	_combo_target = null
	_combo_wait = 0.0


## 技能是否在自身实际施法距离内；0距离技能视为自身/AOE，不做距离限制。
func _skill_in_range(index: int, target: GameEntity) -> bool:
	if target == null or not is_instance_valid(target):
		return true
	if index < 0 or index >= hero.skills.size() or hero.skills[index] == null:
		return false
	var sk: Skill = hero.skills[index]
	if sk.type == 2 or sk.type == 6 or sk.cast_range <= 0.0:
		return true
	var reach: float = sk.cast_range + float(target.body_radius) + 0.6
	return hero.global_position.distance_to(target.global_position) <= reach


## 逃跑时只放低前摇的远程伤害或控制技能（≤0.4s），不因长前摇停下送人头。
func try_escape_skill(target: GameEntity, max_cast_time: float = 0.40) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
	if _turret_blocked(target):
		return false
	if skill_feed_timer > 0.0:
		return false
	var candidates := _get_candidates(target)
	if "--ai-skill-probe" in OS.get_cmdline_user_args():
		var dbg: Array = []
		for c in candidates:
			var sk: Skill = c["skill"]
			dbg.append("%s(t=%d,ct=%.2f,chan=%s,dmg=%.0f,ctl=%s,rng=%.1f)" % [
				sk.skill_name, sk.type, sk.cast_time, str(sk.is_channeling), sk.damage, str(_has_control(sk)), sk.cast_range])
		var raw_dbg: Array = []
		for ii in range(mini(3, hero.skills.size())):
			var raw: Skill = hero.skills[ii]
			if raw == null:
				continue
			raw_dbg.append("%s lv=%d cd=%.1f" % [raw.skill_name, hero.skill_levels[ii], hero.skill_cooldowns[ii]])
		print("[AISKILL] escape try %s -> %s dist=%.1f feed=%.1f cand=%s | raw=%s" % [
			hero.display_name, target.display_name,
			hero.global_position.distance_to(target.global_position), skill_feed_timer,
			",".join(dbg) if not dbg.is_empty() else "NONE", ",".join(raw_dbg)])
	var best: Dictionary = {}
	for c in candidates:
		var sk: Skill = c["skill"]
		# 注意：SkillDataBase 把 type 1/3/4 统一标 is_channeling=true（非指向标记），
		# 不能据此过滤，否则会屏蔽大部分远程消耗技能；实际长前摇由 cast_time 限制。
		if sk.cast_time > max_cast_time:
			continue
		# 只要进攻/控制/减速，不要赶路位移和纯增益；
		# 部分英雄的实际伤害写在 _finish_casting，数据库 sk.damage=0，因此按技能形态兜底
		if not _is_offensive_skill(sk):
			continue
		if best.is_empty() or float(c["score"]) > float(best["score"]):
			best = c
	if best.is_empty():
		return false
	skill_feed_timer = AiConfig.SKILL_FEED_COOLDOWN
	hero._start_casting(int(best["index"]), best["skill"], _aim_pos(target))
	if "--ai-skill-probe" in OS.get_cmdline_user_args():
		print("[AISKILL] escape %s -> %s  dist=%.1f  skill=%s  cast=%.2f" % [
			hero.display_name, target.display_name,
			hero.global_position.distance_to(target.global_position),
			str(best["skill"].skill_name), float(best["skill"].cast_time)])
	return true


# ==================== 单技能评分 ====================

# 选择最佳技能对目标使用（替代随机选择）
func use_best_skill(target: GameEntity, delta: float = 0.0) -> bool:
	if _turret_blocked(target):
		return false

	skill_feed_timer -= delta
	if skill_feed_timer > 0:
		return false

	var candidates := _get_candidates(target)
	if candidates.is_empty():
		return false

	candidates.sort_custom(func(a, b): return a.score > b.score)
	var best = candidates[0]

	if best.score <= 0:
		return false

	skill_feed_timer = AiConfig.SKILL_FEED_COOLDOWN
	hero._start_casting(best.index, best.skill, _aim_pos(target))
	return true


# 强制使用某个技能（英雄特判用）
func force_cast(skill_index: int, target_pos: Vector3) -> bool:
	if skill_index >= hero.skills.size():
		return false
	if hero.skill_cooldowns[skill_index] > 0:
		return false
	if hero.mana < hero.skills[skill_index].mana_cost:
		return false
	hero._start_casting(skill_index, hero.skills[skill_index], target_pos)
	return true


# ==================== 内部评分 ====================
func _get_candidates(target: GameEntity = null) -> Array:
	var result := []
	for i in range(hero.skills.size()):
		if i >= 4:
			continue                    # 槽4=恢复：由 HeroAI._try_use_recover 独立处理，不参与普通技能候选
		if hero.skills[i] == null:      # 空技能槽（如未配第 4 技能）：直接跳过，避免空引用崩溃
			continue
		if hero.skill_levels[i] <= 0:
			continue
		if hero.skill_cooldowns[i] > 0:
			continue
		if hero.mana < hero.skills[i].mana_cost:
			continue
		# 后羿大招仅对英雄使用
		if not _can_use_skill_on(i, target):
			continue
		if not _skill_in_range(i, target):
			continue
		if _low_mana_skill_blocked(i, target):
			continue
		var sk: Skill = hero.skills[i]
		var score := _score_skill(sk, i, target)
		result.append({"index": i, "skill": sk, "score": score})
	return result


# 后羿大招只打英雄等英雄特判：统一问 brain，通用代码不写 display_name
func _can_use_skill_on(index: int, target: GameEntity) -> bool:
	if brain:
		return brain.can_cast_on(index, target)
	return true


# 打塔限制：默认所有英雄都不能用技能打塔，刘禅例外（brain.can_cast_on_turret）
func _turret_blocked(target: GameEntity) -> bool:
	return target is Turret and not (brain and brain.can_cast_on_turret())

func _score_skill(sk: Skill, index: int, target: GameEntity = null) -> float:
	var score := 1.0

	# 基础分：有伤害加分
	if sk.damage > 0:
		score += minf(sk.damage / 500.0, 2.0)

	# 控制/增益对团战和换血的价值
	var rng := _skill_radius(sk)
	if sk.type == 1:
		# AoE：范围内敌人多则加分
		score += perception.count_enemy_heroes_near(rng) * 0.5
	elif sk.type == 2:
		# 增益：身边有敌人时说明即将接战/正在换血
		score += perception.count_enemy_heroes_near(rng) * 0.5
	if _has_control(sk):
		# 控制技能：附近每有 1 个友方英雄配合 +0.5
		score += perception.count_ally_heroes_near(rng) * 0.5
	if sk.type == 6:
		# 护盾：低血量加分
		if hero.health < hero.actual_max_health * AiConfig.HEALTH_DEFEND:
			score += 1.0

	# 大招：无人时不放；只有打“正在攻击我方塔的敌方小兵”时例外
	if index == 2:
		var enemy_heroes := perception.count_enemy_heroes_near(rng)
		if enemy_heroes <= 0:
			var minion_bonus := _ult_minion_tower_bonus(sk, target)
			if minion_bonus < 0.0:
				return 0.0
			score += minion_bonus
		else:
			score += float(enemy_heroes) * 1.0

	# 难度决策随机性：低难度评分抖动大，技能选择更“随意”
	var j: float = AiConfig.score_jitter()
	if j > 0.0:
		score += randf_range(-1.0, 1.0) * j * maxf(absf(score), 1.0)

	return score


## 技能有效范围：优先半径，其次施法距离，最后按交战距离兜底
func _skill_radius(sk: Skill) -> float:
	if sk == null:
		return AiConfig.ENGAGE_RANGE
	if sk.radius > 0.0:
		return sk.radius
	if sk.cast_range > 0.0:
		return sk.cast_range
	return AiConfig.ENGAGE_RANGE


## 大招使用门槛：半径内有敌方英雄，或例外（敌方小兵打我方塔且 HP>1000）
func _ult_allowed(target: GameEntity) -> bool:
	if hero.skills.size() <= 2 or hero.skills[2] == null:
		return true
	var sk: Skill = hero.skills[2]
	var rng := _skill_radius(sk)
	if perception.count_enemy_heroes_near(rng) > 0:
		return true
	return _ult_minion_tower_bonus(sk, target) >= 0.0


## 蓝量 <30% 时，不允许用耗蓝技能清理小兵/普通野怪；打蓝 buff 时放行。
func _low_mana_skill_blocked(index: int, target: GameEntity) -> bool:
	if hero == null or target == null or not is_instance_valid(target):
		return false
	if hero.display_name == "张飞":
		return false
	if index < 0 or index >= hero.skills.size() or hero.skills[index] == null:
		return false
	if hero.skills[index].mana_cost <= 0.0:
		return false
	if hero.actual_mana_max <= 0.0 or hero.mana >= hero.actual_mana_max * AiConfig.MANA_LOW:
		return false
	if target is Minion:
		return true
	if target is JungleMonster:
		return str((target as JungleMonster).buff_type) != "blue" \
			and str(target.display_name) != "blue_buff"
	return false


func _is_offensive_skill(sk: Skill) -> bool:
	if sk == null:
		return false
	if sk.damage > 0.0 or _has_control(sk):
		return true
	# type 0 目标 / 1 AOE / 3 直线：有射程即视为可消耗的进攻技能
	return sk.type in [0, 1, 3] and sk.cast_range > 0.0


## 是否带控制效果（眩晕/击飞/减速）
func _has_control(sk: Skill) -> bool:
	if sk == null:
		return false
	return sk.applies_stun > 0.0 or sk.applies_knockup > 0.0 or sk.applies_slow > 0.0


## 大招打小兵的例外：目标敌方小兵 HP>1000 且正在攻击我方防御塔；
## 返回 附近敌方小兵总血量/2500（上限 2.0），不满足返回 -1。
func _ult_minion_tower_bonus(sk: Skill, target: GameEntity) -> float:
	if target == null or not is_instance_valid(target) or not (target is Minion):
		return -1.0
	if float(target.health) <= 1000.0:
		return -1.0
	var ct = target.get("current_target")
	if ct == null or not is_instance_valid(ct) or not (ct is Turret):
		return -1.0
	if int((ct as Turret).team) != int(hero.team):
		return -1.0
	var r := maxf(_skill_radius(sk), AiConfig.TOWER_ATTACK_RANGE)
	var total := 0.0
	for m in hero.get_tree().get_nodes_in_group("minions"):
		if not (m is Minion) or int((m as Minion).team) == int(hero.team) or (m as Minion).health <= 0.0:
			continue
		if (m as Minion).global_position.distance_to(target.global_position) <= r:
			total += float((m as Minion).health)
	return minf(total / 2500.0, 2.0)


# 瞄准点：按难度加预判提前量 + 落点误差（低难度技能会偏）
# 1 预判帧 ≈ 50ms；误差半径 (1-精度)*3 米，青铜约 1.35m、黄金约 0.36m、钻石/王者为 0
func _aim_pos(target: GameEntity) -> Vector3:
	var p: Vector3 = target.global_position
	var frames: int = AiConfig.prediction_frames()
	if frames > 0:
		p += target.velocity * (0.05 * frames)
	var acc: float = AiConfig.skill_accuracy()
	if acc < 1.0:
		var err: float = (1.0 - acc) * 3.0
		var ang: float = randf() * TAU
		var r: float = randf() * err
		p += Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	return p


# 旧版随机逻辑（向后兼容）
func use_random_skill(target: GameEntity) -> bool:
	if _turret_blocked(target):
		return false
	if skill_feed_timer > 0:
		return false
	# 后羿大招仅对英雄使用：对非英雄目标重掷，直到抽中其他技能
	for _retry in range(hero.skills.size()):
		var i = randi() % hero.skills.size()
		if not _can_use_skill_on(i, target):
			continue
		if hero.skill_levels[i] <= 0:
			return false
		if hero.skill_cooldowns[i] <= 0 and hero.mana >= hero.skills[i].mana_cost:
			skill_feed_timer = AiConfig.SKILL_FEED_COOLDOWN
			hero._start_casting(i, hero.skills[i], target.global_position)
			return true
		return false
	return false


