extends Node

var items: Dictionary = {}

# 选人界面「出装调整」写入：英雄名 → 自定义顺序的推荐出装 id 数组（对局内推荐/快买按此顺序）
var recommended_overrides: Dictionary = {}

func _ready():
	_init_items()

func set_recommended_override(hero_name: String, ids: Array) -> void:
	if ids.is_empty():
		recommended_overrides.erase(hero_name)
	else:
		recommended_overrides[hero_name] = ids.duplicate()

func get_recommended_override(hero_name: String) -> Array:
	return recommended_overrides.get(hero_name, [])

func _init_items():
	# =========================================================================
	# 装备三级体系：tier 1=基础小件  2=中级合成件  3=终极大件
	# 合成差价 = 总价 - 所有素材价格之和（购买时自动计算）
	# =========================================================================

	# =====================================================================
	# 一级基础小件 (tier=1) — 直接购买，无合成需求
	# =====================================================================

	# --- 物理攻击 ---
	items["iron_sword"] = {
		"name": "铁剑", "tier": 1, "attack": 20, "cost": 275, "class": "attack"
	}
	items["knife"] = {
		"name": "匕首", "tier": 1, "attack_speed": 10, "cost": 300, "class": "attack"
	}
	items["battle_fist"] = {
		"name": "搏击拳套", "tier": 1, "crit_chance": 8, "cost": 300, "class": "attack"
	}
	items["vampire_scythe"] = {
		"name": "吸血之镰", "tier": 1, "lifesteal": 8, "cost": 300, "class": "attack"
	}
	items["storm_sword"] = {
		"name": "风暴巨剑", "tier": 2, "attack": 75, "cost": 850, "class": "attack",
		"requires": ["iron_sword", "iron_sword"]
	}

	# --- 法术 ---
	items["magic_book"] = {
		"name": "咒术典籍", "tier": 1, "ability_power": 35, "cost": 275, "class": "magic"
	}
	items["blue_diamond"] = {
		"name": "蓝宝石", "tier": 1, "mana": 400, "cost": 275, "class": "magic"
	}
	items["secert_spell"] = {
		"name": "秘法残页", "tier": 1, "spell_vamp": 8, "cost": 300, "class": "magic"
	}
	items["crystal_flow"] = {
		"name": "元流结晶", "tier": 1, "cooldown": 5, "cost": 300, "class": "magic"
	}
	items["big_bang"] = {
		"name": "大棒", "tier": 2, "ability_power": 120, "cost": 820, "class": "magic",
		"requires": ["magic_book", "magic_book"]
	}

	# --- 防御 ---
	items["cloth_armor"] = {
		"name": "布甲", "tier": 1, "armor": 100, "cost": 275, "class": "defense"
	}
	items["cloth_magic_armor"] = {
		"name": "抗魔披风", "tier": 1, "magic_resist": 100, "cost": 275, "class": "defense"
	}
	items["red_diamond"] = {
		"name": "红玛瑙", "tier": 1, "health": 300, "cost": 300, "class": "defense"
	}
	items["regen_crystal"] = {
		"name": "提神水晶", "tier": 1, "hp_regen": 20, "cost": 300, "class": "defense"
	}

	# --- 移速/功能 ---
	items["boots"] = {
		"name": "神速之靴", "tier": 1, "speed": 30, "cost": 250, "class": "boots"
	}
	items["enchanted_feather"] = {
		"name": "附魔之羽", "tier": 1, "per_speed": 5, "cost": 300, "class": "attack"
	}
	
	# =====================================================================
	# 二级合成件 (tier=2) — 由2件一级小件合成，无专属被动
	# =====================================================================

	# --- 物理攻击合成件 ---
	items["swift_spear"] = {
		"name": "迅捷长矛", "tier": 2, "attack": 35, "per_speed": 7.5, "cost": 760, "class": "attack",
		"requires": ["iron_sword", "enchanted_feather"]
	}
	items["thundercry_blade"] = {
		"name": "雷鸣刀", "tier": 2, "attack": 25, "crit_chance": 12, "cost": 820, "class": "attack",
		"requires": ["iron_sword", "battle_fist"]
	}
	items["corona"] = {
		"name": "日冕", "tier": 2, "attack": 35, "health": 400, "cost": 760, "class": "attack",
		"requires": ["iron_sword", "red_diamond"]
	}
	items["furious_dual_blades"] = {
		"name": "狂暴双刃", "tier": 2, "attack_speed": 15, "per_speed": 7.5, "cost": 760, "class": "attack",
		"requires": ["knife", "enchanted_feather"]
	}
	items["meteorite"] = {
		"name": "陨星", "tier": 2, "attack": 35, "cooldown": 8, "cost": 760, "class": "attack",
		"requires": ["iron_sword", "crystal_flow"]
	}
	items["speedy_strike_spear"] = {
		"name": "速击之枪", "tier": 2, "attack": 35, "attack_speed": 15, "cost": 800, "class": "attack",
		"requires": ["iron_sword", "knife"]
	}
	items["forged_steel_blade"] = {
		"name": "精钢锻刀", "tier": 2, "attack": 25, "attack_speed": 15, "health": 450, "cost": 850, "class": "attack",
		"requires": ["knife", "red_diamond"]
	}
	items["bloodsoul_blade"] = {
		"name": "血魂刃", "tier": 2, "attack": 35, "lifesteal": 12, "cost": 800, "class": "attack",
		"requires": ["iron_sword", "vampire_scythe"]
	}
	items["piercing_cloud_bow"] = {
		"name": "穿云弓", "tier": 2, "attack": 25, "attack_speed": 15, "crit_chance": 12, "cost": 800, "class": "attack",
		"requires": ["iron_sword", "battle_fist"]
	}
	items["bramble_gauntlets"] = {
		"name": "荆棘护手", "tier": 2, "attack": 35, "armor": 150, "cost": 750, "class": "defense",
		"requires": ["iron_sword", "cloth_armor"]
	}

	# --- 法术合成件 ---
	items["saint_spell"] = {
		"name": "圣者法典", "tier": 2, "ability_power": 60, "cooldown": 8, "cost": 800, "class": "magic",
		"requires": ["magic_book", "crystal_flow"]
	}
	items["spell_vamp_book"] = {
		"name": "血族之书", "tier": 2, "ability_power": 60, "spell_vamp": 12, "cost": 800, "class": "magic",
		"requires": ["magic_book", "secert_spell"]
	}
	items["spell_stone"] = {
		"name": "魔道之石", "tier": 2, "ability_power": 60, "per_speed": 7.5, "cost": 800, "class": "magic",
		"requires": ["magic_book", "enchanted_feather"]
	}
	items["cloud_wood"] = {
		"name": "云灵木", "tier": 2, "ability_power": 60, "health": 450, "cost": 840, "class": "magic",
		"requires": ["magic_book", "red_diamond"]
	}
	items["phantom_mask"] = {
		"name": "魅影面罩", "tier": 2, "ability_power": 50, "magic_pen_percent": 15, "cost": 800, "class": "magic",
		"requires": ["magic_book", "cloth_magic_armor"]
	}

	# --- 防御合成件 ---
	items["swift_armor"] = {
		"name": "急速铠甲", "tier": 2, "cooldown": 8, "health": 450, "cost": 800, "class": "defense",
		"requires": ["red_diamond", "crystal_flow"]
	}
	items["strength_belt"] = {
		"name": "力量腰带", "tier": 2, "health": 900, "cost": 850, "class": "defense",
		"requires": ["red_diamond", "red_diamond"]
	}
	items["tarnkappe"] = {
		"name": "神隐斗篷", "tier": 2, "magic_resist": 150, "health": 450, "cost": 800, "class": "defense",
		"requires": ["red_diamond", "cloth_magic_armor"]
	}
	items["snow_shield"] = {
		"name": "雪山圆盾", "tier": 2, "cooldown": 8, "armor": 150, "cost": 750, "class": "defense",
		"requires": ["cloth_armor", "crystal_flow"]
	}
	items["guardian_armor"] = {
		"name": "守护者之铠", "tier": 2, "armor": 150, "health": 450, "cost": 800, "class": "defense",
		"requires": ["cloth_armor", "red_diamond"]
	}
	items["agate_breastplate_mirror"] = {
		"name": "玛瑙护心镜", "tier": 2, "health": 450, "per_speed": 7.5, "cost": 800, "class": "defense",
		"requires": ["red_diamond", "enchanted_feather"]
	}
	items["sky_earth_stone"] = {
		"name": "天地石", "tier": 2, "armor": 150, "magic_resist": 150, "cost": 800, "class": "defense",
		"requires": ["cloth_armor", "cloth_magic_armor"]
	}

	# --- 二级鞋子 (tier=2, 由1级鞋+1件基础小件合成) ---
	items["armor_boots"] = {
		"name": "影忍之足", "tier": 2, "armor": 100, "magic_resist": 50, "speed": 50, "toughness": 25,
		"cost": 700, "class": "boots", "requires": ["boots", "cloth_armor"],
		"passive": "减少6-12%受到的物理伤害(随等级)"
	}
	items["resist_boots"] = {
		"name": "抵抗之靴", "tier": 2, "magic_resist": 100, "armor": 50, "speed": 50, "toughness": 25,
		"cost": 700, "class": "boots", "requires": ["boots", "cloth_magic_armor"]
	}
	items["cd_boots"] = {
		"name": "冷静之靴", "tier": 2, "cooldown": 15, "speed": 50, "cost": 700, "class": "boots",
		"passive": "召唤师技能冷却恢复速度+10-20%(随等级)",
		"requires": ["boots", "crystal_flow"]
	}
	items["swift_boots"] = {
		"name": "急速战靴", "tier": 2, "attack_speed": 20, "speed": 50, "cost": 700, "class": "boots",
		"passive": "每次普攻回复20-40生命(远程30-60, 随等级)",
		"requires": ["boots", "knife"]
	}
	items["spell_boots"] = {
		"name": "秘法之靴", "tier": 2, "mana": 400, "speed": 50, "cost": 700, "class": "boots", "magic_pen": 60,
		"passive": "+60-120法穿(随等级), 每5秒回复10法力",
		"requires": ["boots", "blue_diamond"]
	}
	items["run_boots"] = {
		"name": "疾步之靴", "tier": 2, "health": 300, "speed": 70, "cost": 700, "class": "boots",
		"passive": "5秒无战斗额外+35-70移速(随等级)",
		"requires": ["boots", "red_diamond"]
	}

	# --- 辅助装合成件 ---
	items["wind_blessing"] = {
		"name": "凤鸣指环", "tier": 2, "per_speed": 7.5, "mana_regen": 6, "cost": 1210, "class": "support",
		"requires": ["ancient_coin"],
		"passive": "附近友方增加攻速"
	}

	# =====================================================================
	# 三级终极大件 (tier=3) — 由2件二级装备+合成费合成，带核心被动/主动
	# =====================================================================

	# --- 物理攻击大件 ---
	items["bloodthirster"] = {
		"name": "泣血之刃", "tier": 3, "attack": 80, "lifesteal": 25, "health": 500,
		"cost": 2020, "class": "attack",
		"requires": ["bloodsoul_blade", "corona"],
		"passive": "技能额外+25%物理吸血; 溢出治疗50%转最大生命(上限400-800)"
	}
	items["infinity_edge"] = {
		"name": "无尽战刃", "tier": 3, "attack": 120, "crit_chance": 20, "crit_damage": 20,
		"cost": 2110, "class": "attack",
		"requires": ["storm_sword", "thundercry_blade"],
		"passive": "暴击伤害+20%+0.5暴击率(至多50%)"
	}
	items["sage_power"] = {
		"name": "宗师之力", "tier": 3, "attack": 55, "crit_chance": 20, "attack_speed": 15, "health": 600,
		"cost": 2100, "class": "attack",
		"requires": ["forged_steel_blade", "thundercry_blade"],
		"passive": "使用技能后+12%移速2秒, 5秒内下次普攻额外+80%AD伤害(冷却3秒)"
	}
	items["battle_axe"] = {
		"name": "暗影战斧", "tier": 3, "attack": 80, "cooldown": 10, "health": 500,
		"cost": 2090, "class": "attack",
		"requires": ["meteorite", "corona"],
		"passive": "增加90-180物理穿透(随等级成长)"
	}
	items["breaker"] = {
		"name": "破军", "tier": 3, "attack": 150, "cooldown": 5,
		"cost": 2540, "class": "attack",
		"requires": ["storm_sword", "storm_sword"],
		"passive": "对生命低于50%的敌人额外造成30%伤害"
	}
	items["star_shatterer"] = {
		"name": "碎星锤", "tier": 3, "attack": 90, "armor_pen_percent": 30, "health": 700,
		"per_speed": 7.5, "cost": 2080, "class": "attack",
		"requires": ["swift_spear", "corona"],
		"passive": "+30%物理穿透"
	}
	items["demon_bane_blade"] = {
		"name": "破魔刀", "tier": 3, "attack": 90, "magic_resist": 150, "health": 600,
		"cost": 2060, "class": "attack",
		"requires": ["storm_sword", "tarnkappe"],
		"passive": "获得等同于额外物理攻击50%的法术防御，最多不超过250点"
	}
	items["frost_assault"] = {
		"name": "寒霜袭侵", "tier": 3, "attack": 70, "attack_speed": 25, "health": 750,
		"cost": 2040, "class": "attack",
		"requires": ["speedy_strike_spear", "corona"],
		"passive": "普攻/技能命中造成5%-10%减速(1.5秒,可叠2层)，额外造成135-270+45%AD物理伤害(冷却3秒)"
	}
	items["blade_of_sanction"] = {
		"name": "制裁之刃", "tier": 3, "attack": 100, "attack_speed": 20, "lifesteal": 20,
		"cost": 2080, "class": "attack",
		"requires": ["speedy_strike_spear", "bloodsoul_blade"],
		"passive": "重伤: 降低目标35%生命回复和吸血, 持续2.5秒(同制裁之刃)"
	}
	items["world_end"] = {
		"name": "末世", "tier": 3, "attack": 40, "attack_speed": 20, "lifesteal": 20, "health": 500,
		"cost": 2100, "class": "attack",
		"requires": ["bloodsoul_blade", "forged_steel_blade"],
		"passive": "普攻额外造成80-160+7%目标生命值物理伤害"
	}
	items["purify"] = {
		"name": "纯净苍穹", "tier": 3, "attack": 80, "armor": 150, "cooldown": 10,
		"cost": 2140, "class": "survival",
		"passive": "技能命中首个敌人造成10-20%减速并降低其20%伤害(3秒, 8s冷却)", "active": "获得30%减伤持续3秒(75s冷却, 按V键)",
		"requires": ["meteorite", "bramble_gauntlets"],
		
	}

	# --- 攻速暴击大件 ---
	items["lightning_knife"] = {
		"name": "闪电匕首", "tier": 3, "attack": 50, "attack_speed": 35, "per_speed": 7.5,
		"cost": 2040, "class": "attack_speed",
		"requires": ["furious_dual_blades", "speedy_strike_spear"],
		"passive": "普攻额外40-80法伤，每3次普攻释放链式电弧(160-400法伤, 传导100距离)"
	}
	items["shadow_blade"] = {
		"name": "影刃", "tier": 3, "attack": 45, "crit_chance": 20, "attack_speed": 35, "per_speed": 7.5,
		"cost": 2040, "class": "attack_speed",
		"requires": ["furious_dual_blades", "thundercry_blade"],
		"passive": "普攻命中+10%攻速(暴击+20%)和5%移速，持续3秒"
	}
	items["sunspire_bow"] = {
		"name": "逐日之弓", "tier": 3, "attack": 40, "crit_chance": 15, "attack_speed": 20, "per_speed": 7.5,
		"cost": 2100, "class": "attack_speed",
		"passive": "普攻伤害+25(远程+50)", "active": "增加25%射程(仅远程)和20%移速，持续5秒(75s冷却, 按6键)",
		"requires": ["piercing_cloud_bow", "swift_spear"],
		
	}
	items["dawn"] = {
		"name": "仁者破晓", "tier": 3, "attack": 75, "attack_speed": 30, "crit_chance": 15,
		"armor_pen_percent": 15, "cost": 2570, "class": "attack_speed",
		"requires": ["piercing_cloud_bow", "speedy_strike_spear"],
		"passive": "+15%物理穿透(远程30%)，普攻伤害+25(远程+50)"
	}
	items["chase_wind"] = {
		"name": "逐风", "tier": 3, "attack": 50, "attack_speed": 30, "health": 600,
		"cost": 2080, "class": "attack_speed",
		"requires": ["speedy_strike_spear", "forged_steel_blade"],
		"passive": "普攻/技能命中叠加2%攻速+移速+伤害(最多5层，持续2.5秒)"
	}
	items["shadow_dart"] = {
		"name": "幽影袖箭", "tier": 3, "attack": 40, "attack_speed": 20, "crit_chance": 20, "health": 650,
		"cost": 2040, "class": "attack_speed",
		"requires": ["piercing_cloud_bow", "corona"],
		"active": "隐身2.5秒(近战1.25秒)+30%移速，每0.5秒回复110-220+6%已损生命(按7键，60s冷却)"
	}

	# --- 法术大件 ---
	items["echo_staff"] = {
		"name": "回响之杖", "tier": 3, "ability_power": 220, "per_speed": 7.5,
		"cost": 2050, "class": "magic",
		"requires": ["spell_stone", "big_bang"],
		"passive": "技能命中后爆炸(100码, 140-280+28%AP法伤, 5s冷却)"
	}
	items["nightmare"] = {
		"name": "梦魇之牙", "tier": 3, "ability_power": 220, "cooldown": 8, "per_speed": 7.5,
		"cost": 2050, "class": "magic",
		"requires": ["spell_stone", "saint_spell"],
		"passive": "重伤: 降低目标35%生命回复和吸血, 持续2.5秒(同制裁之刃)"
	}
	items["rabadon"] = {
		"name": "博学者之怒", "tier": 3, "ability_power": 210, "per_ability_power": 30,
		"cost": 2140, "class": "magic",
		"requires": ["big_bang", "big_bang"],
		"passive": "+30%法术强度"
	}
	items["void_staff"] = {
		"name": "虚无法杖", "tier": 3, "ability_power": 210, "health": 500, "magic_pen_percent": 45,
		"cooldown": 5, "cost": 2040, "class": "magic",
		"requires": ["big_bang", "cloud_wood"],
		"passive": "+45%法术穿透"
	}
	items["golden_body"] = {
		"name": "辉月", "tier": 3, "ability_power": 160, "cooldown": 8, "spell_vamp": 12,
		"cost": 2080, "class": "magic",
		"requires": ["spell_vamp_book", "saint_spell"],
		"active": "进入无敌1.5秒(不可移动/攻击/技能, 75s冷却, 按8键)"
	}
	items["pain_mask"] = {
		"name": "痛苦面具", "tier": 3, "ability_power": 100, "cooldown": 8, "health": 900,
		"cost": 2080, "class": "magic",
		"requires": ["cloud_wood", "swift_armor"],
		"passive": "技能命中后3秒内4次3%当前生命法伤(野怪上限200, 冷却3秒)"
	}
	items["dusk_flow"] = {
		"name": "日暮之流", "tier": 3, "ability_power": 160, "cooldown": 10, "health": 500,
		"cost": 2040, "class": "magic",
		"requires": ["cloud_wood", "saint_spell"],
		"passive": "对英雄造成伤害获得20-40法穿(随等级), 最多6层, 持续4秒"
	}
	items["fire_dominate"] = {
		"name": "炽热支配者", "tier": 3, "ability_power": 150, "per_speed": 7.5, "spell_vamp": 12,
		"cost": 2040, "class": "magic",
		"requires": ["spell_vamp_book", "spell_stone"],
		"passive": "血量<30%时净化+护盾(500-1000+100%AP+7.5%HP)+30%移速(4秒, 90s冷却)"
	}
	items["gold_saint_sword"] = {
		"name": "金色圣剑", "tier": 3, "ability_power": 150, "attack_speed": 20, "per_speed": 7.5,
		"cost": 2070, "class": "magic",
		"requires": ["big_bang", "furious_dual_blades"],
		"passive": "普攻+60伤害; 命中+10%攻速(5s, 2层); 叠满后额外30%AP法伤"
	}
	items["saint_cup"] = {
		"name": "圣杯", "tier": 3, "ability_power": 150, "health": 500, "cooldown": 15,
		"cost": 2020, "class": "magic",
		"requires": ["saint_spell", "swift_armor"],
		"passive": "每秒回复1.5%最大法力+0.5%最大生命; 法力满时额外+0.5%生命"
	}
	items["godslayer_book"] = {
		"name": "噬神之书", "tier": 3, "ability_power": 160, "health": 750, "spell_vamp": 24,
		"cost": 2060, "class": "magic",
		"requires": ["spell_vamp_book", "spell_vamp_book"],
		"passive": "提供25%法术吸血; 每100法强额外+0.5冷却缩减"
	}
	items["witch_staff"] = {
		"name": "巫术法杖", "tier": 3, "ability_power": 180, "health": 600, "mana": 300, "speed": 8,
		"cost": 2080, "class": "magic",
		"requires": ["spell_stone", "cloud_wood"],
		"passive": "使用技能后下次普攻额外180-360+40%AP法伤(冷却2.5秒)"
	}
	items["prophecy_of_time"] = {
		"name": "时之预言", "tier": 3, "ability_power": 140, "health": 900, "mana": 450,
		"cost": 2150, "class": "magic",
		"requires": ["big_bang", "strength_belt"],
		"passive": "升级后3秒回复20%HP和法力; 满级每45秒触发; 额外双抗=50-100+10%AP"
	}
	items["break_cocoon_cloth"] = {
		"name": "破茧之衣", "tier": 3, "ability_power": 120, "health": 900,
		"cost": 2120, "class": "magic",
		"requires": ["cloud_wood", "cloud_wood"],
		"passive": "额外HP转AP(20-40+2%HP, 上限100)和法穿(30-60+3%HP, 上限150)"
	}
	items["sky_book"] = {
		"name": "贤者天书", "tier": 3, "ability_power": 350, "cooldown": 10,
		"cost": 2610, "class": "magic",
		"requires": ["saint_spell", "big_bang"],
		"passive": "每100法强使伤害+0.5%, 受伤-0.5%"
	}
	items["frost_breath"] = {
		"name": "凝冰之息", "tier": 3, "ability_power": 180, "cooldown": 8, "health": 500,
		"cost": 2100, "class": "magic",
		"requires": ["big_bang", "swift_armor"],
		"passive": "普攻/技能命中造成5-10%减速(1.5s, 2层)和75-150+15%AP法伤(冷却3秒)"
	}

	# --- 防御大件 ---
	items["thornmail"] = {
		"name": "反伤刺甲", "tier": 3, "armor": 300, "health": 700, "attack": 45,
		"cost": 2020, "class": "defense",
		"requires": ["bramble_gauntlets", "guardian_armor"],
		"passive": "受到物理伤害反弹25%给攻击者", "active": "3秒内将35%受伤以真伤回敬来源(75s冷却, 按9键)"
	}
	items["omen"] = {
		"name": "不祥征兆", "tier": 3, "armor": 300, "health": 1200,
		"cost": 2020, "class": "defense",
		"requires": ["guardian_armor", "guardian_armor"],
		"passive": "受到伤害减少攻击者20-40%攻速+7.5-15%移速(2.5s, 3s冷却)"
	}
	items["mage_robe"] = {
		"name": "魔女斗篷", "tier": 3, "magic_resist": 300, "health": 1100,
		"cost": 2020, "class": "defense",
		"requires": ["tarnkappe", "tarnkappe"],
		"passive": "每15秒获400-800+7%HP法术护盾; +15%法防的物防"
	}
	items["dragon_shield"] = {
		"name": "怒龙剑盾", "tier": 3, "armor": 150, "magic_resist": 150, "health": 1100,
		"cost": 2040, "class": "defense",
		"requires": ["guardian_armor", "tarnkappe"],
		"passive": "普攻/技能对野怪额外7%HP物伤(回复50%),对英雄/塔3.5%HP(2s冷却)"
	}
	items["red_cloak"] = {
		"name": "红莲斗篷", "tier": 3, "armor": 240, "health": 1350,
		"cost": 2040, "class": "defense",
		"requires": ["guardian_armor", "strength_belt"],
		"passive": "每秒对周围3.75米敌人造成1.5%HP法伤(小兵野怪翻倍)+重伤"
	}
	items["heavy_armor"] = {
		"name": "霸者重装", "tier": 3, "armor": 180, "health": 1800, "magic_resist": 90,
		"cost": 2450, "class": "defense",
		"requires": ["strength_belt", "strength_belt"],
		"passive": "+4%最大生命; 每秒回复0.5%HP(3秒未受英雄/塔伤害翻倍)"
	}
	items["eye_of_the_phoenix"] = {
		"name": "不死鸟之眼", "tier": 3, "armor": 90, "health": 1350, "magic_resist": 180,
		"cost": 2040, "class": "defense",
		"requires": ["strength_belt", "tarnkappe"],
		"passive": "每损失10%生命, 生命回复效果+5%"
	}
	items["ice_storm"] = {
		"name": "极寒风暴", "tier": 3, "armor": 240, "cooldown": 20, "health": 600,
		"cost": 2040, "class": "defense",
		"requires": ["swift_armor", "snow_shield"],
		"passive": "单次受伤>10%当前HP时冰爆3米(130-260法伤+降攻速移速2s, 2s冷却)"
	}
	items["fierce_armor"] = {
		"name": "暴烈之甲", "tier": 3, "armor": 210, "health": 900, "attack": 35,
		"cost": 2050, "class": "defense",
		"requires": ["bramble_gauntlets", "strength_belt"],
		"passive": "受击+1%伤害移速(3s, 最多10层)"
	}
	items["night_guardian"] = {
		"name": "永夜守护", "tier": 3, "armor": 90, "health": 900, "magic_resist": 180, "speed": 8,
		"cost": 2020, "class": "defense",
		"requires": ["tarnkappe", "agate_breastplate_mirror"],
		"passive": "2.5秒受伤>25%HP→2.5秒内每0.5秒回2%HP+减50%减速(7s冷却)"
	}
	items["ice_fist"] = {
		"name": "冰痕之握", "tier": 3, "armor": 300, "attack": 55, "cooldown": 10,
		"cost": 2060, "class": "defense",
		"requires": ["bramble_gauntlets", "snow_shield"],
		"passive": "技能后5秒内普攻额外140-280+40%AD物伤+15-30%减速0.5s(1.25s冷却)"
	}
	items["ice_shock"] = {
		"name": "冰霜冲击", "tier": 3, "armor": 150, "health": 900, "cooldown": 8,
		"cost": 2030, "class": "defense",
		"passive": "+10%韧性; 受控时获10%HP护盾(15s冷却)", "active": "周围4.5米减速30-60%→0.75s后冰冻0.75s+100-200法伤(75s冷却,按-键)",
		"requires": ["guardian_armor", "swift_armor"],
		
	}
	items["rising_sun"] = {
		"name": "旭日初光", "tier": 3, "armor": 210, "health": 900, "cooldown": 10,
		"cost": 2040, "class": "defense",
		"requires": ["strength_belt", "snow_shield"],
		"passive": "对英雄造成伤害时为自身+3.5米内最低血友方提供250-500+4%HP护盾(3s,10s冷却,无友方+50%)",
	}

	# --- 保命大件 ---
	items["blood_rage"] = {
		"name": "血魔之怒", "tier": 3, "attack": 75, "health": 900,
		"cost": 2180, "class": "survival",
		"passive": "普攻额外1.5%HP物伤(HP<50%时+25-50%)", "active": "扣除30%当前生命,4秒内逐渐获得40%最大生命护盾(75s冷却,按0键)",
		"requires": ["storm_sword", "strength_belt"],
		
	}
	items["famous_blade"] = {
		"name": "名刀·司命", "tier": 3, "attack": 75, "attack_speed": 15, "health": 500,
		"cost": 2060, "class": "survival",
		"requires": ["storm_sword", "forged_steel_blade"],
		"passive": "受到致命伤害时无敌+15%移速1秒(120s冷却, 每局最多3次)"
	}
	items["revive"] = {
		"name": "贤者的庇护", "tier": 3, "armor": 150, "magic_resist": 150, "health": 900, "cooldown": 5,
		"cost": 2280, "class": "survival",
		"requires": ["strength_belt", "sky_earth_stone"],
		"passive": "死亡2秒后复活(2000-3000HP), 每局最多2次, 150s冷却"
	}

	# --- 原初遗珠 (特殊tier=3, 由复活甲用尽后获得，也可直接购买) ---
	items["primal_pearl"] = {
		"name": "原初遗珠", "tier": 3, "armor": 150, "magic_resist": 150,
		"cost": 800, "class": "defense",
		"passive": "可与其他大件合成顶级神装"
	}

	# --- 原初遗珠·终级神装 (tier=4, 六神后终极升级) ---
	items["swift_day"] = {
		"name": "迅疾·日渊", "tier": 4, "attack": 40, "crit_chance": 15, "attack_speed": 20, "speed": 8,
		"cost": 3320, "class": "attack_speed",
		"requires": ["sunspire_bow", "primal_pearl"],
		"passive": "继承逐日之弓效果。主动额外+20%移速，普攻对周围目标溅射30%伤害"
	}
	items["immovable_firmament"] = {
		"name": "不动·天穹", "tier": 4, "attack": 80, "armor": 150, "cooldown": 10,
		"cost": 3280, "class": "survival",
		"requires": ["purify", "primal_pearl"],
		"passive": "继承纯净苍穹效果。主动额外+30%移速+无视地形+净化"
	}
	items["rage_ghost"] = {
		"name": "侵略·怒魂", "tier": 4, "attack": 75, "health": 900,
		"cost": 3300, "class": "survival",
		"passive": "血魔主动期间每秒对3米内敌人4%HP法伤",
		"requires": ["blood_rage", "primal_pearl"],
		"active": "蓄力造成范围真实伤害并获护盾"
	}
	items["sereve_winter"] = {
		"name": "徐行·凛冬", "tier": 4, "armor": 150, "health": 900, "cooldown": 8,
		"cost": 3190, "class": "defense",
		"passive": "冰霜主动减速效果增强为90%, 范围扩大至6米",
		"requires": ["ice_shock", "primal_pearl"],
		"active": "范围冰冻+减速"
	}
	items["moon_god"] = {
		"name": "难知·月神", "tier": 4, "ability_power": 160, "cooldown": 8, "spell_vamp": 12,
		"cost": 3340, "class": "magic",
		"passive": "辉月主动期间额外回复1000+100%AP生命",
		"requires": ["golden_body", "primal_pearl"],
		"active": "免疫所有伤害1.5秒，结束后回复生命"
	}
	# =====================================================================
	# 打野刀系列
	# =====================================================================
	items["hunter_knife"] = {"name": "狩猎宽刀", "tier": 1, "cost": 250, "class": "jungle", "passive": "狩猎: 普攻/技能命中野怪每0.5秒70-140法伤持续2秒; 对野怪减伤25%+经验+25%"}
	items["guerrilla_blade"] = {"name": "游击弯刀", "tier": 2, "ability_power": 40, "cost": 700, "class": "jungle", "requires": ["hunter_knife"], "passive": "狩猎: 70-140+0.45%HP法伤(英雄10%); 奖赏: +6AP/层(15层); 野怪减伤25%+经验25%+金币20%"}
	items["chase_blade"] = {"name": "追击刀锋", "tier": 2, "attack": 25, "cost": 700, "class": "jungle", "requires": ["hunter_knife"], "passive": "狩猎(物理): 70-140+0.45%HP物伤(英雄10%); 奖赏: +3AD/层(15层)"}
	items["patrol_axe"] = {"name": "巡守利斧", "tier": 2, "health": 400, "cost": 700, "class": "jungle", "requires": ["hunter_knife"], "passive": "狩猎(物理): 70-140+0.45%HP物伤(英雄10%); 奖赏: +30HP/层(15层)"}
	items["rune_blade"] = {"name": "符文大剑", "tier": 3, "ability_power": 130, "cooldown": 10, "per_speed": 5, "cost": 2100, "class": "jungle", "requires": ["guerrilla_blade", "saint_spell"], "passive": "狩猎: 90-180+0.6%HP法伤(英雄25%); 奖赏: 25层+6AP/层+0.2%CD"}
	items["greed_blade"] = {"name": "贪婪之噬", "tier": 3, "attack": 90, "cooldown": 8, "per_speed": 5, "cost": 2100, "class": "jungle", "requires": ["chase_blade", "meteorite"], "passive": "狩猎(物理): 90-180+0.6%HP物伤(英雄25%); 奖赏: 25层+3AD/层+0.2%CD"}
	items["giant_grasp"] = {"name": "巨人之握", "tier": 3, "health": 1200, "cooldown": 5, "per_speed": 5, "cost": 2100, "class": "jungle", "requires": ["patrol_axe", "swift_armor"], "passive": "狩猎(物理): 90-180+0.6%HP物伤(英雄25%); 奖赏: 25层+30HP/层+0.2%CD"}
	# =====================================================================
	# 游走装系列
	# =====================================================================
	items["ancient_coin"] = {
		"name": "学识宝石", "tier": 1, "speed": 5, "cost": 300, "class": "support"
	}
	items["guardian_glory"] = {"name": "近卫·荣耀", "tier": 2, "health": 500, "speed": 5, "cost": 850, "class": "support", "requires": ["ancient_coin", "red_diamond"], "passive": "奉献: 不分配兵线收益(25-50%); 每3秒+5exp+给经济最低队友5金; 奖赏: +200-400HP+15-30AD(或30-60AP); 守护光环: 8米队友+36-72双抗+0.4%HP回血(自身双倍)"}
	items["extreme_shadow"] = {"name": "极影·迅光", "tier": 2, "health": 500, "speed": 5, "cost": 850, "class": "support", "requires": ["ancient_coin", "red_diamond"], "passive": "奉献: 同上; 奖赏: 同上; 迅捷光环: 8米队友+6%攻速+4.5%CD+5回蓝(自身双倍)"}
	items["redeemer_guard"] = {"name": "救赎·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["guardian_glory", "strength_belt"], "passive": "守护光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "救赎: 5米队友+240-480+10%HP护盾4秒(60s冷却),按6键"}
	items["redeemer_shadow"] = {"name": "救赎·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["extreme_shadow", "strength_belt"], "passive": "迅捷光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "救赎: 5米队友+240-480+10%HP护盾4秒(60s冷却),按6键"}
	items["star_spring_guard"] = {"name": "星泉·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["guardian_glory", "strength_belt"], "passive": "守护光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "星泉: 链接1名队友每秒回100-212+4%HP+5%法力5秒(50s/次,最多2次),按6键"}
	items["star_spring_shadow"] = {"name": "星泉·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["extreme_shadow", "strength_belt"], "passive": "迅捷光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "星泉: 链接1名队友每秒回100-212+4%HP+5%法力5秒(50s/次,最多2次),按6键"}
	items["galloping_wolf_guard"] = {"name": "奔狼·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["guardian_glory", "strength_belt"], "passive": "守护光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "奔狼: 5米队友每0.5秒+25-50%移速5秒(90s冷却),按6键"}
	items["galloping_wolf_shadow"] = {"name": "奔狼·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["extreme_shadow", "strength_belt"], "passive": "迅捷光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "奔狼: 5米队友每0.5秒+25-50%移速5秒(90s冷却),按6键"}
	items["revealing_light_guard"] = {"name": "形昭·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["guardian_glory", "strength_belt"], "passive": "守护光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "形昭: 12米光波每0.5秒3%当前HP真伤+25-50%减速2秒+反隐(75s冷却),按6键"}
	items["revealing_light_shadow"] = {"name": "形昭·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support", "requires": ["extreme_shadow", "strength_belt"], "passive": "迅捷光环升级: +400-800HP+25-50AD(或50-100AP)", "active": "形昭: 12米光波每0.5秒3%当前HP真伤+25-50%减速2秒+反隐(75s冷却),按6键"}


# =========================================================================
# 公共接口
# =========================================================================

func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


# 检查是否能用已拥有的装备合成目标装备
func can_build(item_id: String, owned_items: Array) -> bool:
	var item = items.get(item_id, {})
	if item.is_empty(): return false
	var requires = item.get("requires", [])
	if requires.is_empty(): return false
	var have = owned_items.duplicate()
	for req in requires:
		var idx = have.find(req)
		if idx == -1: return false
		have.remove_at(idx)
	return true


# 计算合成差价：总价 - 素材价格之和
func get_synthesis_cost(item_id: String, owned_items: Array) -> int:
	var item = items.get(item_id, {})
	if item.is_empty(): return 0
	var requires = item.get("requires", [])
	if requires.is_empty():
		return item["cost"]
	var component_cost = 0
	for req in requires:
		var req_item = items.get(req, {})
		if not req_item.is_empty():
			component_cost += req_item["cost"]
	var synthesis = item["cost"] - component_cost
	return max(synthesis, 0)


# 获取装备的合成树描述
func get_synthesis_tree(item_id: String) -> String:
	var item = items.get(item_id, {})
	if item.is_empty(): return ""
	var requires = item.get("requires", [])
	if requires.is_empty():
		return "基础装备，直接购买"
	var parts = []
	for req in requires:
		var req_item = items.get(req, {})
		if not req_item.is_empty():
			parts.append(req_item["name"] + "(" + str(req_item["cost"]) + "金)")
	return " = ".join(parts) + "  →  +" + str(get_synthesis_cost(item_id, [])) + "金"


# 内置推荐出装方案（每英雄 3 套，选人页可直接挑选）；传职业名时回落为每职业 1 套
func get_recommended_variants(hero_name: String) -> Array:
	# 每名英雄3套专属出装方案
	var builds = {
		# ==================== 战士 ====================
		"吕布": [
			["battle_axe", "resist_boots", "sage_power", "breaker", "fierce_armor", "omen"],
			["red_cloak", "armor_boots", "omen", "dragon_shield", "eye_of_the_phoenix", "blood_rage"],
			["battle_axe", "resist_boots", "infinity_edge", "sage_power", "purify", "revive"],
		],
		"亚瑟": [
			["battle_axe", "cd_boots", "ice_fist", "fierce_armor", "omen", "blood_rage"],
			["red_cloak", "armor_boots", "ice_shock", "omen", "dragon_shield", "eye_of_the_phoenix"],
			["battle_axe", "resist_boots", "sage_power", "breaker", "star_shatterer", "purify"],
		],
		"铠": [
			["battle_axe", "resist_boots", "sage_power", "infinity_edge", "breaker", "purify"],
			["battle_axe", "armor_boots", "fierce_armor", "ice_fist", "omen", "blood_rage"],
			["lightning_knife", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "revive"],
		],
		"东皇太一": [
			["red_cloak", "resist_boots", "omen", "night_guardian", "dragon_shield", "eye_of_the_phoenix"],
			["ice_storm", "cd_boots", "red_cloak", "omen", "mage_robe", "heavy_armor"],
			["prophecy_of_time", "resist_boots", "pain_mask", "omen", "night_guardian", "blood_rage"],
		],
		"夏侯惇": [
			["battle_axe", "resist_boots", "fierce_armor", "omen", "ice_fist", "dragon_shield"],
			["red_cloak", "armor_boots", "omen", "ice_storm", "night_guardian", "heavy_armor"],
			["ice_shock", "cd_boots", "omen", "fierce_armor", "mage_robe", "blood_rage"],
		],
		"英睿": [
			["battle_axe", "resist_boots", "ice_fist", "fierce_armor", "omen", "blood_rage"],
			["red_cloak", "armor_boots", "omen", "ice_storm", "night_guardian", "dragon_shield"],
			["battle_axe", "cd_boots", "sage_power", "infinity_edge", "breaker", "revive"],
		],
		# ==================== 刺客 ====================
		"马超": [
			["greed_blade", "resist_boots", "battle_axe", "sage_power", "infinity_edge", "breaker"],
			["greed_blade", "cd_boots", "battle_axe", "star_shatterer", "breaker", "purify"],
			["greed_blade", "resist_boots", "battle_axe", "ice_fist", "fierce_armor", "blood_rage"],
		],
		"李白": [
			["greed_blade", "resist_boots", "battle_axe", "sage_power", "breaker", "famous_blade"],
			["giant_grasp", "resist_boots", "battle_axe", "fierce_armor", "star_shatterer", "blood_rage"],
			["greed_blade", "swift_boots", "bloodthirster", "battle_axe", "infinity_edge", "purify"],
		],
		"兰陵王": [
			["greed_blade", "cd_boots", "battle_axe", "sage_power", "breaker", "famous_blade"],
			["greed_blade", "resist_boots", "battle_axe", "star_shatterer", "shadow_dart", "purify"],
			["giant_grasp", "resist_boots", "battle_axe", "ice_fist", "omen", "blood_rage"],
		],
		"孙悟空": [
			["greed_blade", "swift_boots", "infinity_edge", "sage_power", "battle_axe", "famous_blade"],
			["greed_blade", "swift_boots", "lightning_knife", "shadow_blade", "infinity_edge", "dawn"],
			["giant_grasp", "resist_boots", "battle_axe", "sage_power", "fierce_armor", "revive"],
		],
		# ==================== 法师 ====================
		"不知火舞": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "moon_god"],
			["echo_staff", "cd_boots", "pain_mask", "prophecy_of_time", "dusk_flow", "frost_breath"],
			["prophecy_of_time", "resist_boots", "echo_staff", "pain_mask", "break_cocoon_cloth", "moon_god"],
		],
		"甄姬": [
			["echo_staff", "cd_boots", "rabadon", "void_staff", "godslayer_book", "frost_breath"],
			["echo_staff", "cd_boots", "pain_mask", "frost_breath", "nightmare", "void_staff"],
			["prophecy_of_time", "resist_boots", "echo_staff", "pain_mask", "break_cocoon_cloth", "ice_storm"],
		],
		"沈梦溪": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "moon_god"],
			["echo_staff", "cd_boots", "pain_mask", "frost_breath", "nightmare", "void_staff"],
			["prophecy_of_time", "resist_boots", "echo_staff", "dusk_flow", "break_cocoon_cloth", "saint_cup"],
		],
		"安琪拉": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "moon_god"],
			["echo_staff", "cd_boots", "pain_mask", "saint_cup", "void_staff", "frost_breath"],
			["prophecy_of_time", "resist_boots", "echo_staff", "pain_mask", "fire_dominate", "break_cocoon_cloth"],
		],
		"妲己": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "witch_staff"],
			["echo_staff", "cd_boots", "pain_mask", "saint_cup", "void_staff", "frost_breath"],
			["echo_staff", "cd_boots", "frost_breath", "nightmare", "pain_mask", "void_staff"],
		],
		"小乔": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "moon_god"],
			["echo_staff", "swift_boots", "rabadon", "void_staff", "frost_breath", "witch_staff"],
			["prophecy_of_time", "resist_boots", "echo_staff", "pain_mask", "frost_breath", "saint_cup"],
		],
		"王昭君": [
			["echo_staff", "spell_boots", "rabadon", "void_staff", "godslayer_book", "frost_breath"],
			["echo_staff", "cd_boots", "pain_mask", "frost_breath", "nightmare", "ice_storm"],
			["prophecy_of_time", "resist_boots", "echo_staff", "pain_mask", "break_cocoon_cloth", "ice_shock"],
		],
		# ==================== 射手 ====================
		"狄仁杰": [
			["lightning_knife", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "bloodthirster"],
			["battle_axe", "swift_boots", "world_end", "shadow_dart", "dawn", "purify"],
			["world_end", "resist_boots", "lightning_knife", "shadow_blade", "dawn", "revive"],
		],
		"孙尚香": [
			["infinity_edge", "swift_boots", "sage_power", "shadow_blade", "dawn", "bloodthirster"],
			["battle_axe", "swift_boots", "star_shatterer", "shadow_dart", "dawn", "purify"],
			["lightning_knife", "swift_boots", "shadow_blade", "world_end", "dawn", "revive"],
		],
		"马可波罗": [
			["world_end", "swift_boots", "lightning_knife", "shadow_blade", "dawn", "purify"],
			["chase_wind", "swift_boots", "lightning_knife", "infinity_edge", "dawn", "bloodthirster"],
			["world_end", "resist_boots", "battle_axe", "lightning_knife", "shadow_blade", "revive"],
		],
		"鲁班七号": [
			["infinity_edge", "swift_boots", "shadow_blade", "sage_power", "dawn", "bloodthirster"],
			["lightning_knife", "swift_boots", "shadow_blade", "world_end", "dawn", "chase_wind"],
			["battle_axe", "swift_boots", "star_shatterer", "shadow_dart", "dawn", "purify"],
		],
		"后羿": [
			["lightning_knife", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "bloodthirster"],
			["world_end", "swift_boots", "lightning_knife", "blade_of_sanction", "dawn", "chase_wind"],
			["world_end", "resist_boots", "lightning_knife", "blade_of_sanction", "dawn", "revive"],
		],
		"李元芳": [
			["lightning_knife", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "famous_blade"],
			["lightning_knife", "swift_boots", "world_end", "shadow_blade", "dawn", "revive"],
			["lightning_knife", "resist_boots", "world_end", "blade_of_sanction", "dawn", "revive"],
		],
		"元流之子": [
			["world_end", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "bloodthirster"],
			["world_end", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "chase_wind"],
			["world_end", "resist_boots", "blade_of_sanction", "shadow_blade", "dawn", "revive"],
		],
		# ==================== 辅助 ====================
		"太乙真人": [
			["guardian_glory", "cd_boots", "omen", "ice_storm", "mage_robe", "heavy_armor"],
			["extreme_shadow", "cd_boots", "omen", "night_guardian", "dragon_shield", "ice_shock"],
			["extreme_shadow", "cd_boots", "echo_staff", "prophecy_of_time", "pain_mask", "frost_breath"],
		],
		"张飞": [
			["guardian_glory", "armor_boots", "omen", "red_cloak", "mage_robe", "heavy_armor"],
			["extreme_shadow", "armor_boots", "omen", "fierce_armor", "night_guardian", "dragon_shield"],
			["guardian_glory", "armor_boots", "red_cloak", "omen", "ice_storm", "eye_of_the_phoenix"],
		],
		"大禹": [
			["guardian_glory", "cd_boots", "omen", "ice_storm", "dragon_shield", "heavy_armor"],
			["extreme_shadow", "cd_boots", "omen", "fierce_armor", "ice_fist", "blood_rage"],
			["guardian_glory", "resist_boots", "battle_axe", "ice_fist", "omen", "ice_storm"],
		],
		"刘禅": [
			["guardian_glory", "armor_boots", "red_cloak", "omen", "fierce_armor", "ice_storm"],
			["extreme_shadow", "armor_boots", "omen", "ice_shock", "mage_robe", "rising_sun"],
			["guardian_glory", "cd_boots", "red_cloak", "ice_storm", "omen", "blood_rage"],
		],
	}
	if builds.has(hero_name):
		return builds[hero_name]
	# 兜底：按角色返回通用方案
	var role_pools = {
		"战士": ["battle_axe", "resist_boots", "ice_fist", "sage_power", "fierce_armor", "omen"],
		"射手": ["lightning_knife", "swift_boots", "shadow_blade", "infinity_edge", "dawn", "bloodthirster"],
		"法师": ["echo_staff", "cd_boots", "rabadon", "void_staff", "saint_cup", "frost_breath"],
		"刺客": ["greed_blade", "resist_boots", "battle_axe", "sage_power", "breaker", "famous_blade"],
		"辅助": ["guardian_glory", "cd_boots", "omen", "ice_storm", "dragon_shield", "heavy_armor"],
	}
	return [role_pools.get(hero_name, role_pools["战士"])]


# 获取推荐出装（取第一套内置方案；对联机/AI 等只要一套的调用方保持原语义）
func get_recommended_items(hero_name: String) -> Array:
	var vs := get_recommended_variants(hero_name)
	return (vs[0] as Array).duplicate() if not vs.is_empty() else []
