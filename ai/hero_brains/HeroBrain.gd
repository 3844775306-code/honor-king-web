class_name HeroBrain
extends RefCounted

var hero: Hero
var perception: AiPerception
var tactics: SkillTactics


func _init(p_hero: Hero, p_perception: AiPerception, p_tactics: SkillTactics) -> void:
	hero = p_hero
	perception = p_perception
	tactics = p_tactics


# ==================== 英雄特判钩子 ====================
# 通用 AI 代码只调这三个钩子，不再写 display_name 字符串判断；
# 需要特判的英雄各自覆盖（后羿大招只打英雄 / 刘禅可拆塔 / 孙悟空筋斗云回城）。

# 是否允许对防御塔释放技能（默认不允许）
func can_cast_on_turret() -> bool:
	return false


# 是否允许对目标释放第 index 个技能（默认允许）
func can_cast_on(_index: int, _target: GameEntity) -> bool:
	return true


# 安全回城：返回 true 表示本英雄已自行处理（如筋斗云飞行中/已在泉水），HeroAI 跳过通用流程
func handle_recall_safe() -> bool:
	return false


# 每帧处理技能窗口期逻辑（如李白Q、太乙Q）
func process_skill_windows() -> void:
	pass


# 每个think tick的额外行为（如兰陵王隐身）
func process_special_actions(state: int) -> void:
	pass


# 修改技能评分（英雄偏好某些技能）
func modify_skill_score(_skill_index: int, _base_score: float) -> float:
	return _base_score


# 获取英雄连招列表
# 返回 Array[Dictionary]: [{name, skills:[idx,...], priority:0.8}]
# 默认按“英雄自己的技能构成”自适应生成，不再所有英雄统一 [2,0,1]/[0,1]。
func get_combos(_target: GameEntity) -> Array:
	var combos: Array = []
	var order: Array = []
	var setup: Array = []
	var finishers: Array = []
	var ult_finisher := false
	for i in range(mini(3, hero.skills.size())):
		var sk: Skill = hero.skills[i]
		if sk == null:
			continue
		var ss := _combo_setup_score(sk)
		if ss > 0.0:
			setup.append({"i": i, "s": ss})
		elif i == 2:
			ult_finisher = true
		else:
			finishers.append({"i": i, "d": float(sk.damage)})
	setup.sort_custom(func(a, b): return float(a.s) > float(b.s))
	finishers.sort_custom(func(a, b): return float(a.d) > float(b.d))
	for e in setup:
		order.append(int(e.i))
	for e in finishers:
		order.append(int(e.i))
	# 大招没有起手价值时放在最后，作为终结技
	if ult_finisher:
		order.append(2)
	if order.is_empty():
		return combos
	combos.append({
		"name": "adaptive_burst",
		"skills": order,
		"priority": _combo_priority_by_role(),
	})
	# 消耗连招：只收有伤害的技能，按射程从远到近
	var poke: Array = []
	for i in range(mini(3, hero.skills.size())):
		var sk2: Skill = hero.skills[i]
		if sk2 != null and sk2.damage > 0.0:
			poke.append({"i": i, "r": float(sk2.cast_range)})
	poke.sort_custom(func(a, b): return float(a.r) > float(b.r))
	var poke_order: Array = []
	for e in poke:
		poke_order.append(int(e.i))
	if not poke_order.is_empty():
		combos.append({"name": "adaptive_poke", "skills": poke_order, "priority": 0.3})
	return combos


# 起手价值：控制 > 位移 > 增益 > AoE；没有起手价值就归为伤害/终结技
func _combo_setup_score(sk: Skill) -> float:
	var s := 0.0
	if sk.applies_stun > 0.0 or sk.applies_knockup > 0.0 or sk.applies_slow > 0.0:
		s += 3.0
	if sk.type == 4 or sk.self_displacement > 0.0:
		s += 2.5
	if sk.type == 2:
		s += 1.5
	if sk.type == 1:
		s += 0.5
	return s


func _combo_priority_by_role() -> float:
	match str(hero.role):
		"刺客": return 0.70
		"战士": return 0.60
		"法师": return 0.55
		"射手": return 0.50
		"辅助": return 0.45
	return 0.5


# 工厂方法：根据英雄名创建对应的 Brain
static func create(hero_name: String, p_hero: Hero, p_perception: AiPerception, p_tactics: SkillTactics) -> HeroBrain:
	match hero_name:
		"李白": return LibaiBrain.new(p_hero, p_perception, p_tactics)
		"太乙真人": return TaiyiBrain.new(p_hero, p_perception, p_tactics)
		"兰陵王": return LanlingBrain.new(p_hero, p_perception, p_tactics)
		"后羿": return HouyiBrain.new(p_hero, p_perception, p_tactics)
		"刘禅": return LiushanBrain.new(p_hero, p_perception, p_tactics)
		"孙悟空": return WukongBrain.new(p_hero, p_perception, p_tactics)
		_: return HeroBrain.new(p_hero, p_perception, p_tactics)
