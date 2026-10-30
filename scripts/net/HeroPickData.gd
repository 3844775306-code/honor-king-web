# HeroPickData.gd — 大厅选人阶段共享只读目录（host 与每个 client 同屏选人共用）
#
# 需求：客户端与服务器开局前各自选英雄+召唤师，全员锁齐后 host 才开局。
# 本文件是选人面板（NetLobby）与校验/分配（NetSession）的目录源；BattleManager 仍是
# 造英雄的权威（hero_configs 实例 var），_start_net_lineup 开局时对每个选人做存在性断言。
#
# 与 BattleManager.hero_configs 保持一致的 28 名英雄角色（2026-08 核对）；未来在 hero_configs
# 增删英雄时请同步此处 HERO_ROLE。
# 纯 Control/纯数据，中文 UI，所有 GDScript 用 TAB 缩进。

class_name HeroPickData
extends RefCounted

# 蓝方固定 5 个职责槽位（与 BM 选人 roles_order 一致），严格一人一职
const ROLES_ORDER: Array = ["战士", "法师", "刺客", "射手", "辅助"]

# 分路（与职责一一对应）：玩家在菜单选定分路后，选人阶段固定占用该职责
const LANES: Array = ["对抗路", "打野", "中路", "发育路", "游走"]

const LANE_ROLE := {
	"对抗路": "战士", "打野": "刺客", "中路": "法师", "发育路": "射手", "游走": "辅助",
}

static func lane_role(lane: String) -> String:
	return str(LANE_ROLE.get(lane, "战士"))

static func role_lane(role: String) -> String:
	for lane in LANE_ROLE:
		if str(LANE_ROLE[lane]) == role:
			return str(lane)
	return "对抗路"

const ROLE_COLORS := {
	"战士": Color(0.85, 0.3, 0.2),
	"法师": Color(0.3, 0.5, 1.0),
	"刺客": Color(0.6, 0.2, 0.9),
	"射手": Color(0.9, 0.55, 0.1),
	"辅助": Color(0.1, 0.8, 0.65),
}

# 召唤师技能：中文名 -> SkillDatabase id（与 BM 选人 summons 一致）
const SUMMONERS := {
	"闪现": "flash", "疾跑": "sprint", "传送": "teleport", "治疗术": "heal", "终结": "execute",
	"狂暴": "frenzy", "晕眩": "stun", "净化": "cleanse_summoner", "弱化": "weaken", "惩击": "smite",
}

# 英雄名字 -> 职责（与 BattleManager.hero_configs 各条目的 role 字段一一对应）
const HERO_ROLE := {
	"吕布": "战士", "亚瑟": "战士", "铠": "战士", "东皇太一": "战士", "夏侯惇": "战士", "英睿": "战士",
	"马超": "刺客", "李白": "刺客", "兰陵王": "刺客", "孙悟空": "刺客",
	"不知火舞": "法师", "甄姬": "法师", "沈梦溪": "法师", "安琪拉": "法师", "妲己": "法师", "小乔": "法师", "王昭君": "法师",
	"狄仁杰": "射手", "孙尚香": "射手", "马可波罗": "射手", "鲁班七号": "射手", "后羿": "射手", "李元芳": "射手", "元流之子": "射手",
	"太乙真人": "辅助", "张飞": "辅助", "大禹": "辅助", "刘禅": "辅助",
}

# 英雄推荐召唤师技能（与 BM hero_configs 的 summoner 字段一致；其余默认闪现）
const HERO_SUMMONER := {"李白": "smite", "孙悟空": "smite"}

static func recommended_summoner(hero_name: String) -> String:
	return HERO_SUMMONER.get(hero_name, "flash")
