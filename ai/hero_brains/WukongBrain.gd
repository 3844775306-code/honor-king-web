class_name WukongBrain
extends HeroBrain

# 筋斗云回城：飞行中不干预；已在泉水附近则等自动回血。
# 其余情况交回 HeroAI 通用回城流程（走到安全点后 start_recall → Hero 内部转筋斗云）。
func handle_recall_safe() -> bool:
	if hero.wukong_cloud_flying:
		return true
	var spawn := Vector3(-60, 0, 60) if hero.team == Config.Team.PLAYER else Vector3(60, 0, -60)
	return hero.global_position.distance_to(spawn) < AiConfig.SPAWN_LEAVE_RANGE
