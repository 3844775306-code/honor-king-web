class_name AIAction
extends RefCounted
## 英雄层行为动作。替代旧的 State 枚举；状态由 ActionStatus 表达。

enum Type {
	IDLE,
	PUSH_LANE,
	JUNGLE_FARM,
	TRADE,
	FINISH_CHASE,
	DEFEND_TOWER,
	SAFE_RECALL,
	RETURN_TO_BASE,
	HEALTH_PACK,
	TEMP_CLEAR,
	VISION_SPIRIT,
	TRIPOD,
	TEAM_TASK,
	OBJECTIVE,
	ROTATE,
	DODGE,
	TOWER_ESCAPE,
	BLUE_BUFF,
}

enum Status { ACTIVE, COMPLETED, FAILED, INTERRUPTED }
enum PauseClass { NONE, SURVIVAL, ENVIRONMENT }

var type: int = Type.IDLE
var status: int = Status.ACTIVE
var priority: int = 0
var pause_class: int = PauseClass.NONE
var interruptible := true
var target: GameEntity = null
var data: Dictionary = {}
var target_pos := Vector3.ZERO
var lane := -1
var created_at := 0.0
var expires_at := 0.0
var reason := ""


func _init(p_type: int = Type.IDLE, p_priority: int = 0, p_pause: int = PauseClass.NONE, p_reason: String = "") -> void:
	type = p_type
	priority = p_priority
	pause_class = p_pause
	reason = p_reason


func is_active() -> bool:
	return status == Status.ACTIVE


func mark(p_status: int) -> void:
	status = p_status


func label() -> String:
	match type:
		Type.PUSH_LANE: return "推线"
		Type.JUNGLE_FARM: return "刷野"
		Type.TRADE: return "换血"
		Type.FINISH_CHASE: return "追击"
		Type.DEFEND_TOWER: return "守塔"
		Type.SAFE_RECALL: return "回城"
		Type.RETURN_TO_BASE: return "撤回"
		Type.HEALTH_PACK: return "血包"
		Type.TEMP_CLEAR: return "临时清兵"
		Type.VISION_SPIRIT: return "视野之灵"
		Type.TRIPOD: return "大禹鼎"
		Type.TEAM_TASK: return "团队任务"
		Type.OBJECTIVE: return "打龙/资源"
		Type.ROTATE: return "传送转线"
		Type.DODGE: return "躲避"
		Type.TOWER_ESCAPE: return "塔下逃生"
		Type.BLUE_BUFF: return "打蓝 buff"
	return "待命"
