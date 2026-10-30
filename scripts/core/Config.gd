extends Node

const MAP_SIZE = 120
const HIGH_GROUND_RADIUS = 25.0
const GRID_SIZE = 1.0
enum Team { PLAYER = 0, ENEMY = 1, NEUTRAL = 2 }

# 本局玩家所在队伍（0=蓝方 1=红方）：每局随机，UI 颜色/相机/出生点均据此判定
var player_team: int = Team.PLAYER
var _team_rolled: bool = false

func is_ally(team: int) -> bool:
	return team == player_team

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
