extends RefCounted
## SpellFxTable — 逐技能视觉参数表（P1：28 个签名大招 = 全英雄覆盖 + 通用引导/蓄力）。
## 只描述"怎么表现"，不含伤害/时序；Vfx.play_spell() 负责执行。
## 结构：{ "el": 元素, "shape": 形状, "shake": 镜头幅度, "heavy": 是否顿帧 }
## shape: self_stamp 自身爆发柱 / target_big 落点大法阵 / target_zone 区域法阵
##        self_zone 自身区域 / beam 光束 / nova 环形爆发 / slash 连斩 / dash 突进

const ULTS := {
	"吕布":     {"el": "shadow", "shape": "target_big",  "shake": 0.18, "heavy": true},
	"张飞":     {"el": "earth",  "shape": "self_stamp",  "shake": 0.16, "heavy": true},
	"铠":       {"el": "shadow", "shape": "self_stamp",  "shake": 0.14, "heavy": true},
	"安琪拉":   {"el": "fire",   "shape": "beam",        "shake": 0.10, "heavy": false},
	"王昭君":   {"el": "ice",    "shape": "self_zone",   "shake": 0.10, "heavy": false},
	"甄姬":     {"el": "water",  "shape": "target_zone", "shake": 0.10, "heavy": false},
	"小乔":     {"el": "wind",   "shape": "nova",        "shake": 0.10, "heavy": false},
	"后羿":     {"el": "fire",   "shape": "beam",        "shake": 0.10, "heavy": false},
	"孙悟空":   {"el": "holy",   "shape": "nova",        "shake": 0.14, "heavy": true},
	"李白":     {"el": "blade",  "shape": "slash",       "shake": 0.12, "heavy": false},
	"东皇太一": {"el": "shadow", "shape": "beam",        "shake": 0.12, "heavy": false},
	"太乙真人": {"el": "holy",   "shape": "self_stamp",  "shake": 0.10, "heavy": false},
	"亚瑟":     {"el": "holy",   "shape": "self_stamp",  "shake": 0.14, "heavy": true},
	"孙尚香":   {"el": "fire",   "shape": "beam",        "shake": 0.08, "heavy": false},
	"鲁班七号": {"el": "fire",   "shape": "target_zone", "shake": 0.10, "heavy": false},
	"兰陵王":   {"el": "shadow", "shape": "dash",        "shake": 0.10, "heavy": false},
	# ---- P0-1 补齐：其余 12 英雄签名大招（按技能语义 el/shape，全 8 种 shape 均有分支） ----
	"马超":     {"el": "blade",  "shape": "self_stamp",  "shake": 0.12, "heavy": false},  # 万刃归鞘(type2 自身多段收枪)
	"不知火舞": {"el": "fire",   "shape": "slash",       "shake": 0.12, "heavy": false},  # 必杀·狂舞(type3 6m 突进横扫)
	"狄仁杰":   {"el": "blade",  "shape": "beam",        "shake": 0.10, "heavy": false},  # 逮捕令(type3 5m 令牌齐射)
	"马可波罗": {"el": "fire",   "shape": "self_zone",   "shake": 0.10, "heavy": false},  # 狂热弹幕(type4 4m 环绕扫射)
	"沈梦溪":   {"el": "fire",   "shape": "target_zone", "shake": 0.10, "heavy": false},  # 综合轰炸(type1 6m 4.5 范围)
	"妲己":     {"el": "shadow", "shape": "nova",        "shake": 0.10, "heavy": false},  # 狐火(type0 自身 7m)
	"夏侯惇":   {"el": "blade",  "shape": "dash",        "shake": 0.14, "heavy": true},   # 不羁之刃(type4 8m 突进)
	"李元芳":   {"el": "shadow", "shape": "slash",       "shake": 0.10, "heavy": false},  # 无间刃风(type3 7.5m 风刃)
	"元流之子": {"el": "water",  "shape": "target_zone", "shake": 0.10, "heavy": false},  # 万箭齐发(type1 7m 箭雨区)
	"大禹":     {"el": "earth",  "shape": "target_zone", "shake": 0.16, "heavy": true},   # 乾坤以同(type1 10m 鼎落)
	"刘禅":     {"el": "fire",   "shape": "self_stamp",  "shake": 0.14, "heavy": true},   # 暴走熊猫(type2 4m 机甲暴走)
	"英睿":     {"el": "holy",   "shape": "self_stamp",  "shake": 0.10, "heavy": false},  # 变身LabiB(type2 变身 buff)
}

static func get_ult(hero_name: String) -> Dictionary:
	return ULTS.get(hero_name, {})

static func has_ult(hero_name: String) -> bool:
	return ULTS.has(hero_name)

## 逐英雄技能道具（P2.5）：把"法球/扇子/冰柱"这类实体挂到具体槽位。
## 未列出的英雄/槽位不生成道具，走原有程序化特效。
const SKILL_PROPS := {
	"小乔": {0: "fan", 1: "tornado"},
	"甄姬": {0: "ice_pillars", 1: "ice_crystal"},
	"王昭君": {0: "ice_crystal", 1: "ice_pillars"},
	"安琪拉": {0: "orbs", 1: "orbs"},
	"妲己": {0: "orbs", 1: "orbs"},
	"李白": {0: "swords", 1: "swords"},
	"后羿": {0: "sun_orb", 1: "sun_orb"},
	"东皇太一": {0: "orbs"},
}

static func get_prop(hero_name: String, slot: int) -> String:
	var d: Dictionary = SKILL_PROPS.get(hero_name, {})
	return str(d.get(slot, ""))

## 非签名技能按 Skill 类型自动分档（P2）：
## type 0 指向 / 1 区域 / 3 直线 / 4 位移 / 6 护盾。
## 注意：SkillDataBase 会把 type 1/3/4 统一标 is_channeling=true（只是"非指向"标记），
## 因此这里不能拿 is_channeling 分档，只能在区域内用它延长表现时间。
static func get_skill_shape(skill) -> String:
	if skill == null:
		return "bolt"
	match int(skill.type):
		1:
			return "zone"
		3:
			return "line"
		4:
			return "dash"
		6:
			return "aura"
		_:
			return "bolt"
