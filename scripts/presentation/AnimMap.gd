class_name AnimMap
extends RefCounted
## 三端统一动画映射（host / 联机客户端 / 回放共用）：模型 clip 命名不统一（GLB 各不相同），
## 所有"按语义找 clip"的逻辑集中在这里，避免三端各自 keyword 猜测导致走路/攻击/施法/死亡动作不一致。

const DRAGON_NAMES := ["dragon", "storm", "shadow_dragon"]

## 主宰/暗影/风暴先锋等龙类模型：使用 DragonBaby 的 clip 命名
static func is_dragon(unit_name: String) -> bool:
	return unit_name in DRAGON_NAMES

## 在 AnimationPlayer 里按关键字优先级找第一个存在的 clip
static func hint(ap: AnimationPlayer, hints: Array) -> String:
	if ap == null:
		return ""
	for h in hints:
		var key := str(h)
		if key != "" and ap.has_animation(key):
			return key
	return ""

## 语义动作 → 具体 clip 名（返回空串=该模型没有这个动作）
static func clip(ap: AnimationPlayer, action: String, unit_name: String = "") -> String:
	if ap == null:
		return ""
	if is_dragon(unit_name):
		match action:
			"idle", "walk":
				return hint(ap, ["CharacterArmature|Flying_Idle", "Flying_Idle", "idle"])
			"attack":
				return hint(ap, ["CharacterArmature|Punch", "Punch", "attack"])
			"die":
				return hint(ap, ["CharacterArmature|Death", "Death", "die", "death"])
			"cast":
				return hint(ap, ["CharacterArmature|Punch", "Punch", "cast"])
	match action:
		"idle":
			return hint(ap, ["idle", "Idle", "Flying_Idle"])
		"walk":
			var w := hint(ap, ["walk", "Walk", "run", "Run"])
			return w if w != "" else hint(ap, ["idle", "Idle", "Flying_Idle"])
		"attack":
			return hint(ap, ["punch", "attack-melee", "attack", "eat", "shoot", "Attack"])
		"attack_melee_left":
			return hint(ap, ["attack-melee-left", "punch", "attack", "Attack"])
		"attack_melee_right":
			return hint(ap, ["attack-melee-right", "punch", "attack", "Attack"])
		"attack_shoot":
			var s := hint(ap, ["holding-both-shoot", "holding-right-shoot", "shoot", "attack", "Attack"])
			return s if s != "" else hint(ap, ["punch", "attack-melee", "attack"])
		"cast":
			return hint(ap, ["cast", "Cast", "skill", "spell", "punch"])
		"die":
			return hint(ap, ["death", "die", "Death", "Die"])
	return ""


## 近战左右交替（host Hero/Minion 同款：每次普攻翻转）
static func melee(ap: AnimationPlayer, flip: bool, unit_name: String = "") -> String:
	var key := "attack_melee_left" if flip else "attack_melee_right"
	var c := clip(ap, key, unit_name)
	if c == "":
		c = clip(ap, "attack", unit_name)
	return c
