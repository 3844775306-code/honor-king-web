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
func get_combos(_target: GameEntity) -> Array:
	# 默认连招: 有技能就按 2(大招)→0→1 顺序释放
	var combos := []
	if hero.skills.size() >= 3:
		combos.append({
			"name": "burst",
			"skills": [2, 0, 1],
			"priority": 0.5,
		})
	# 常规消耗: 0→1
	combos.append({
		"name": "poke",
		"skills": [0, 1],
		"priority": 0.3,
	})
	return combos


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
