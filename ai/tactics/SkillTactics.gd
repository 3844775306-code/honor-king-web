class_name SkillTactics
extends RefCounted

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
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
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
		if not _can_use_skill_on(idx, target):
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
			or hero.global_position.distance_to(_combo_target.global_position) > AiConfig.SKILL_USE_RANGE \
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


# ==================== 单技能评分 ====================

# 选择最佳技能对目标使用（替代随机选择）
func use_best_skill(target: GameEntity, delta: float = 0.0) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
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
## 追击/逃跑专用：只放有伤害的远程技能，不放控制、治疗、位移类技能。
func use_ranged_damage_skill(target: GameEntity) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
	if _turret_blocked(target):
		return false
	if skill_feed_timer > 0:
		return false
	var candidates := []
	for i in range(hero.skills.size()):
		if hero.skills[i] == null or hero.skill_levels[i] <= 0 or hero.skill_cooldowns[i] > 0:
			continue
		var sk: Skill = hero.skills[i]
		if sk.damage <= 0.0 or sk.cast_range <= 0.0 or sk.type == 4:
			continue
		if hero.mana < sk.mana_cost:
			continue
		if hero.global_position.distance_to(target.global_position) > sk.cast_range + 1.0:
			continue
		if not _can_use_skill_on(i, target):
			continue
		candidates.append({"index": i, "skill": sk, "score": _score_skill(sk, i)})
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a.score > b.score)
	skill_feed_timer = AiConfig.SKILL_FEED_COOLDOWN
	hero._start_casting(candidates[0].index, candidates[0].skill, _aim_pos(target))
	return true


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
		var sk: Skill = hero.skills[i]
		# 不对射程外目标空放技能；self-cast 技能没有目标时不会走到这里。
		if target != null and sk.cast_range > 0.0:
			var reach := sk.cast_range + 1.0
			if hero.global_position.distance_to(target.global_position) > reach:
				continue
		var score := _score_skill(sk, i)
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

func _score_skill(sk: Skill, index: int) -> float:
	var score := 1.0

	# 基础分：有伤害加分
	if sk.damage > 0:
		score += min(sk.damage / 500.0, 2.0)

	# 控制技能加分
	match sk.type:
		1:  # AoE → 范围内敌人多则加分
			var enemy_count = perception.count_enemy_heroes_near(sk.radius if sk.radius > 0 else AiConfig.ENGAGE_RANGE)
			score += enemy_count * 0.5
		4:  # 位移 → 危险时加分，安全时减分
			if hero.health < hero.actual_max_health * AiConfig.HEALTH_LOW:
				score += 1.5
			else:
				score -= 0.5
		6:  # 护盾 → 低血量加分
			if hero.health < hero.actual_max_health * AiConfig.HEALTH_DEFEND:
				score += 1.0

	# 指向性技能/直线技能基础可靠
	if sk.type == 0 or sk.type == 3:
		score += 0.3

	# 大招优先对重要目标
	if index == 2:
		score += 0.5

	# 难度决策随机性：低难度评分抖动大，技能选择更“随意”
	var j: float = AiConfig.score_jitter()
	if j > 0.0:
		score += randf_range(-1.0, 1.0) * j * maxf(absf(score), 1.0)

	return score


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


