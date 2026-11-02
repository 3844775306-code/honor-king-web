class_name TeamTask
extends RefCounted
## 团队指挥官下发给单个 AI 英雄的主线任务。
## HeroAI 只负责执行；任务类型/优先级/过期时间/目标由 TeamTactics 决定。

enum Type {
	NONE,
	PUSH_LANE,
	DEFEND_LANE,
	OBJECTIVE,
	GANK,
	PEEL,
	RETREAT,
	PUSH_TOWER,
	INVADE_JUNGLE,
}

enum Status { ACTIVE, COMPLETED, FAILED, EXPIRED, REASSIGNED }

var type: int = Type.NONE
var owner: Hero = null
var status: int = Status.ACTIVE
var quiet_time := 0.0
var last_update := 0.0
var lane: int = -1
var target_pos := Vector3.ZERO
var target_hero: Hero = null
var priority: int = 0
var created_at := 0.0
var expires_at := 0.0
var reason := ""
var role_hint := ""
var task_id := ""
var initial_lane_tower_count := -1


func setup(p_type: int, p_lane: int, p_target_pos: Vector3, p_target_hero: Hero,
		p_priority: int, p_now: float, p_duration: float, p_reason: String, p_role: String) -> void:
	type = p_type
	lane = p_lane
	target_pos = p_target_pos
	target_hero = p_target_hero
	priority = p_priority
	created_at = p_now
	expires_at = p_now + p_duration
	last_update = p_now
	reason = p_reason
	role_hint = p_role


func is_expired(now: float) -> bool:
	return type == Type.NONE or now >= expires_at


func mark(p_status: int) -> void:
	status = p_status


func is_active() -> bool:
	return status == Status.ACTIVE


func status_label() -> String:
	match status:
		Status.ACTIVE: return "执行中"
		Status.COMPLETED: return "完成"
		Status.FAILED: return "失败"
		Status.EXPIRED: return "超时"
		Status.REASSIGNED: return "重分配"
	return "未知"


func label() -> String:
	match type:
		Type.PUSH_LANE: return "推线"
		Type.DEFEND_LANE: return "守塔"
		Type.OBJECTIVE: return "争夺资源"
		Type.GANK: return "抓人"
		Type.PEEL: return "保排"
		Type.RETREAT: return "撤退"
		Type.PUSH_TOWER: return "抱团推塔"
		Type.INVADE_JUNGLE: return "反野"
	return "待命"
