class_name ActorPresenter
extends RefCounted
## 三端共享「角色表现参数」：行走质感（步频/起伏/摆臂/脚步扬尘/腿部枢轴）与动画动作选择。
## host Minion/Hero/JungleMonster、联机 NetClientBattle、回放 ReplayScreen 都从这里取参数，
## 禁止再各写一份 walk opts / clip 猜测，保证移动与攻击/施法/死亡动作三端一致。

const WALK_HERO := {"stride": 1.9, "bob": 0.055, "sway": 0.028, "lean": 0.075, "dust_size": 0.24}
const WALK_JUNGLE := {"stride": 1.6, "bob": 0.045, "sway": 0.03, "lean": 0.045, "dust_size": 0.26}
const WALK_DRAGON := {"stride": 1.7, "bob": 0.075, "sway": 0.036, "lean": 0.05, "dust": false}
const WALK_SIEGE := {"stride": 1.3, "bob": 0.022, "sway": 0.03, "lean": 0.02, "dust_size": 0.16}
const WALK_MELEE := {"stride": 1.06, "bob": 0.045, "sway": 0.032, "lean": 0.06, "dust_size": 0.18}

const TOUCH_INSET := Vector2(80.0, 20.0)


## 行走参数（kind="hero"/"minion"/"jungle"）。model_root 用于取腿/翼枢轴，可传 null。
static func walk_opts(kind: String, unit_name: String, model_root: Node3D = null) -> Dictionary:
	match kind:
		"hero":
			return WALK_HERO.duplicate()
		"jungle":
			return WALK_JUNGLE.duplicate()
		"minion":
			if AnimMap.is_dragon(unit_name):
				var d: Dictionary = WALK_DRAGON.duplicate()
				if model_root != null:
					d["wings"] = [model_root.get_node_or_null("ModelPivot/WingL"),
						model_root.get_node_or_null("ModelPivot/WingR")]
				return d
			if unit_name == "siege":
				return WALK_SIEGE.duplicate()
			var m: Dictionary = WALK_MELEE.duplicate()
			if model_root != null:
				m["legs"] = [model_root.get_node_or_null("ModelPivot/LegL"),
					model_root.get_node_or_null("ModelPivot/LegR")]
			m["leg_swing"] = 0.52 if unit_name == "super" else 0.62
			return m
	return WALK_JUNGLE.duplicate()


## 语义动作 clip（统一走 AnimMap）
static func clip(ap: AnimationPlayer, action: String, unit_name: String = "") -> String:
	return AnimMap.clip(ap, action, unit_name)


## 近战左右交替 clip
static func melee_clip(ap: AnimationPlayer, flip: bool, unit_name: String = "") -> String:
	return AnimMap.melee(ap, flip, unit_name)
