class_name OnHitProcessor
extends RefCounted
# 命中效果处理器 — 整合 _perform_attack 和 _finish_casting 之间重复的命中效果逻辑

# 打野刀狩猎DoT — 攻击完整伤害，技能1/4伤害
static func apply_jungle_hunt(hero: Hero, target: GameEntity, is_ability: bool) -> void:
	if target is Turret: return
	var has_jungle = hero.equipment_slots.has("hunter_knife") or hero.equipment_slots.has("guerrilla_blade") or hero.equipment_slots.has("chase_blade") or hero.equipment_slots.has("patrol_axe") or hero.equipment_slots.has("rune_blade") or hero.equipment_slots.has("greed_blade") or hero.equipment_slots.has("giant_grasp")
	if not has_jungle: return

	var tier = 1
	if hero.equipment_slots.has("rune_blade") or hero.equipment_slots.has("greed_blade") or hero.equipment_slots.has("giant_grasp"): tier = 3
	elif hero.equipment_slots.has("guerrilla_blade") or hero.equipment_slots.has("chase_blade") or hero.equipment_slots.has("patrol_axe"): tier = 2

	var hunt_base = 70 if tier == 1 else (90 if tier == 3 else 70)
	var hunt_lv = 140 if tier == 1 else (180 if tier == 3 else 140)
	var hunt_dmg = hunt_base + (hero.level - 1) * ((hunt_lv - hunt_base) / 14.0)
	if tier >= 2:
		hunt_dmg += target.max_health * (0.006 if tier == 3 else 0.0045)
	var is_magic = not (hero.equipment_slots.has("chase_blade") or hero.equipment_slots.has("patrol_axe") or hero.equipment_slots.has("greed_blade") or hero.equipment_slots.has("giant_grasp"))

	if is_ability:
		hunt_dmg /= 4.0
	# 技能：对英雄百分比
	if target is Hero and tier >= 2:
		hunt_dmg *= 0.25 if tier == 3 else 0.10

	target.hunt_damage = hunt_dmg
	target.hunt_ticks = 4
	target.hunt_tick_timer = 0.0
	target.hunt_source = hero
	target.hunt_is_magic = is_magic

# 逐风：普攻/技能命中叠层
static func apply_chase_wind(hero: Hero) -> void:
	if hero.equipment_slots.has("chase_wind"):
		hero.chase_wind_stacks = min(hero.chase_wind_stacks + 1, 5)
		hero.chase_wind_timer = 2.5

# 金色圣剑：普攻+60伤害+攻速叠层，技能仅叠层
static func apply_gold_saint_sword(hero: Hero, target: GameEntity, is_ability: bool) -> void:
	if not hero.equipment_slots.has("gold_saint_sword"): return
	if not is_ability:
		# 普攻：+60伤害 + 叠满额外AP法伤
		if hero.gold_saint_sword_stacks >= 2:
			var ap_dmg = hero.actual_ability_power * 0.3
			target.take_damage(ap_dmg, hero, true, -22, 0)
		else:
			hero._apply_ak_buff(0, 0.1, 5.0, false)
	else:
		hero._apply_ak_sp_buff(0.1, 5.0)
	hero.gold_saint_sword_timer = 5.0
	hero.gold_saint_sword_stacks = min(hero.gold_saint_sword_stacks + 1, 2)

# 寒霜袭侵：普攻/技能减速+额外物理伤害
static func apply_frost_assault(hero: Hero, target: GameEntity) -> void:
	if not hero.equipment_slots.has("frost_assault"): return
	if hero.frost_assault_cd > 0: return
	hero.frost_assault_cd = 3.0
	var sp = 0.05 + hero.level * 0.0005
	target.apply_move_pct_buff("ms_slow", 1.5, -min(sp, 0.1), true)
	var ed = 135 + hero.level * 9 + hero.bonus_attack * 0.45
	target.take_damage(ed, hero, false, -26, 0)

# 制裁之刃/梦魇之牙：重伤效果
static func apply_grievous_wounds(hero: Hero, target: GameEntity) -> void:
	if hero.equipment_slots.has("blade_of_sanction") or hero.equipment_slots.has("nightmare"):
		target.grievous_wounds = 0.35
		target.grievous_wounds_timer = 2.5

# 闪电匕首：技能命中附加法伤（普攻的链式电弧在 _perform_attack 中单独处理）
static func apply_lightning_knife_skill(hero: Hero, target: GameEntity) -> void:
	if hero.equipment_slots.has("lightning_knife"):
		target.take_damage(40 + hero.level * 2.6, hero, true, -43, 0)
