class_name HouyiBrain
extends HeroBrain

# 后羿大招（3技能位）只对英雄使用：野怪 / 小兵 / 防御塔一律不放大招；
## 且只在“值得交大”的目标上使用，避免满血近战目标也乱甩大招。
func can_cast_on(index: int, target: GameEntity) -> bool:
	if index != 2:
		return true
	if not (target is Hero):
		return false
	var h := target as Hero
	if not is_instance_valid(h) or h.health <= 0.0:
		return false
	# 不可选中/隐身目标不浪费大招
	if h.is_untargetable_by_enemies() or h.is_invisible_to_enemy():
		return false
	var hp_ratio: float = h.health / maxf(h.actual_max_health, 1.0)
	# 满血/高血量且近距离目标不交大（普攻/1/2技能足够处理）
	if hp_ratio > 0.55:
		return false
	# 目标在敌方塔下时不交大，避免只打中塔边缘/追不进塔
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if t is Turret and t.team != hero.team and t.health > 0.0:
			if h.global_position.distance_to(t.global_position) <= t.attack_range * 0.01 + 1.5:
				return false
	return true
