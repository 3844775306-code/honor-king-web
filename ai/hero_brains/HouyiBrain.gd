class_name HouyiBrain
extends HeroBrain

# 后羿大招（3技能位）只对英雄使用：野怪 / 小兵 / 防御塔一律不放大招
func can_cast_on(index: int, target: GameEntity) -> bool:
	if index == 2:
		return target is Hero
	return true
