class_name BootHeroPool
extends RefCounted
## 开机动画随机英雄池：2D/3D 共用，只选同时有角色定义和 3D 模型的英雄。

const ROLE_TAG := {
	"战士": "不屈战魂", "法师": "秘法掌控", "刺客": "暗影利刃",
	"射手": "百步穿杨", "辅助": "守护之心",
}


static func pick(count: int = 5) -> Array:
	var names: Array = []
	for nm in HeroPickData.HERO_ROLE.keys():
		if Hero.HERO_MODEL_MAP.has(nm):
			names.append(str(nm))
	names.shuffle()
	var out: Array = []
	for i in range(mini(count, names.size())):
		var nm: String = names[i]
		var role: String = str(HeroPickData.HERO_ROLE.get(nm, "战士"))
		out.append({"name": nm, "role": role, "tag": str(ROLE_TAG.get(role, "荣耀英雄"))})
	return out
