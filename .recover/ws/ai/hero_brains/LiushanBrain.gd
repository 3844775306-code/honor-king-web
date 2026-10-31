class_name LiushanBrain
extends HeroBrain

# 刘禅可以拆塔：允许 AI 对防御塔释放技能（其余英雄默认不打塔）
func can_cast_on_turret() -> bool:
	return true
