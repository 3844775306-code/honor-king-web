extends Node

const MAP_SIZE = 120
# 统一可移动边界：外墙中心在 ±63，内表面约 ±62.8；留出余量后统一钳到 ±61.2。
# 原来英雄 60 / 碰撞 59 两套边界与外墙不一致，会夹住边路外塔外侧的通道。
const MAP_EDGE_LIMIT := 61.2
const HIGH_GROUND_RADIUS = 25.0
const GRID_SIZE = 1.0
# 地面特效/施法预览的最低世界高度：高于野区起伏(最高≈0.26)、分路(0.14)、
# 高地(≈0.2)与泉水池沿(≈0.3)，避免贴地圈被任何地面遮住
const GROUND_FX_Y := 0.34
enum Team { PLAYER = 0, ENEMY = 1, NEUTRAL = 2 }

# 本局玩家所在队伍（0=蓝方 1=红方）：每局随机，UI 颜色/相机/出生点均据此判定
var player_team: int = Team.PLAYER
var _team_rolled: bool = false

func is_ally(team: int) -> bool:
	return team == player_team

# 触屏判定：原生移动平台 + 移动浏览器（网页版 OS.has_feature("mobile") 为 false，需看 web_android/web_ios）
func on_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

# 网页版判定
func on_web() -> bool:
	return OS.has_feature("web")

func foe_team() -> int:
	return Team.ENEMY if player_team == Team.PLAYER else Team.PLAYER

# 每局开局前随机分配玩家阵营（只在本局尚未分配时生效）
func roll_player_team() -> void:
	if _team_rolled:
		return
	player_team = Team.PLAYER if randf() < 0.5 else Team.ENEMY
	_team_rolled = true

func reset_player_team() -> void:
	player_team = Team.PLAYER
	_team_rolled = false
