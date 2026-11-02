class_name ItemActiveTactics
extends RefCounted

var hero: Hero
var perception: AiPerception
var state: int
var last_action := ""


func _init(p_hero: Hero, p_perception: AiPerception) -> void:
	hero = p_hero
	perception = p_perception


func try_use(p_state: int) -> void:
	state = p_state
	_try_purify()
	_try_golden_body()
	_try_blood_rage()
	_try_sunspire()
	_try_thornmail()
	_try_ice_shock()
	_try_shadow_dart()


func _try_purify() -> void:
	if hero.purify_cd > 0 or not hero.equipment_slots.has("purify"):
		return
	if perception.count_enemy_heroes_near(AiConfig.MELEE_RANGE) < AiConfig.PURIFY_ENEMY_COUNT:
		return
	if hero.health >= hero.actual_max_health * AiConfig.HEALTH_DEFEND:
		return
	hero.purify_cd = AiConfig.CD_PURIFY
	last_action = "净化"
	hero._apply_df_buff(0, 0.3, 3.0, false)
	hero._apply_df_buff(0, 0.3, 3.0, true)


func _try_golden_body() -> void:
	if hero.golden_body_cd > 0 or not hero.equipment_slots.has("golden_body"):
		return
	if hero.health >= hero.actual_max_health * AiConfig.HEALTH_CRITICAL:
		return
	if perception.count_enemy_heroes_near(AiConfig.MELEE_RANGE) < AiConfig.GOLDEN_BODY_ENEMY_COUNT:
		return
	hero.golden_body_cd = AiConfig.CD_GOLDEN_BODY
	last_action = "金身"
	hero.golden_body_active = true
	hero.golden_body_timer = AiConfig.DUR_GOLDEN_BODY
	hero.wd_timer = AiConfig.GOLDEN_BODY_INVINCIBLE
	hero.stun_timer = AiConfig.GOLDEN_BODY_INVINCIBLE


func _try_blood_rage() -> void:
	if hero.blood_rage_cd > 0:
		return
	if not (hero.equipment_slots.has("blood_rage") or hero.equipment_slots.has("rage_ghost")):
		return
	if hero.health >= hero.actual_max_health * (AiConfig.HEALTH_LOW - 0.1):
		return
	hero.blood_rage_cd = AiConfig.CD_BLOOD_RAGE
	last_action = "血怒"
	hero.blood_rage_active = true
	hero.blood_rage_timer = AiConfig.DUR_BLOOD_RAGE
	var hp_drain = hero.health * AiConfig.BLOOD_RAGE_HP_DRAIN_RATIO / AiConfig.DUR_BLOOD_RAGE
	hero.apply_regen(-hp_drain, 0, AiConfig.DUR_BLOOD_RAGE, "blood_rage_hp")
	hero.shield_remaining = max(hero.shield_remaining, hero.actual_max_health * AiConfig.BLOOD_RAGE_SHIELD_RATIO)
	hero.shield_timer = AiConfig.DUR_BLOOD_RAGE


func _try_sunspire() -> void:
	if hero.sunspire_active_cd > 0:
		return
	if not (hero.equipment_slots.has("sunspire_bow") or hero.equipment_slots.has("swift_day")):
		return
	if state != AIAction.Type.PUSH_LANE:
		return
	if not perception.find_nearest_enemy_hero(AiConfig.SUNSPIRE_ACTIVE_RANGE):
		return
	hero.sunspire_active_cd = AiConfig.CD_SUNSPIRE
	last_action = "逐日"
	hero.sunspire_active = true
	hero.sunspire_active_timer = AiConfig.DUR_SUNSPIRE
	var spd = AiConfig.SUNSPIRE_SPEED_BOOST_UPGRADE if hero.equipment_slots.has("swift_day") else AiConfig.SUNSPIRE_SPEED_BOOST
	hero.apply_move_pct_buff("ms_haste", AiConfig.SUNSPIRE_SLOW_DURATION, spd)
	if hero.attack_range > AiConfig.SUNSPIRE_RANGE_THRESHOLD:
		hero.multiply_attack_range_base(AiConfig.SUNSPIRE_RANGE_BOOST_RATIO)


func _try_thornmail() -> void:
	if hero.thornmail_cd > 0 or not hero.equipment_slots.has("thornmail"):
		return
	if perception.count_enemy_heroes_near(AiConfig.MELEE_RANGE) < AiConfig.THORNMAIL_ENEMY_COUNT:
		return
	hero.thornmail_cd = AiConfig.CD_THORNMAIL
	last_action = "反伤"
	hero.thornmail_active = true
	hero.thornmail_timer = AiConfig.DUR_THORNMAIL


func _try_ice_shock() -> void:
	if hero.ice_shock_cd > 0:
		return
	if not (hero.equipment_slots.has("ice_shock") or hero.equipment_slots.has("sereve_winter")):
		return
	if perception.count_enemy_heroes_near(AiConfig.MELEE_RANGE) < AiConfig.ICE_SHOCK_ENEMY_COUNT:
		return
	hero.ice_shock_cd = AiConfig.CD_ICE_SHOCK
	last_action = "冰霜冲击"
	var rng = AiConfig.ICE_SHOCK_RANGE_UPGRADE if hero.equipment_slots.has("sereve_winter") else AiConfig.ICE_SHOCK_RANGE_NORMAL
	var slw_val = AiConfig.ICE_SHOCK_SLOW_UPGRADE if hero.equipment_slots.has("sereve_winter") else AiConfig.ICE_SHOCK_SLOW_NORMAL + hero.level * 0.002
	for ent in hero.get_tree().get_nodes_in_group("entities"):
		if ent != hero and ent.health > 0 and ent.team != hero.team:
			if hero.global_position.distance_to(ent.global_position) <= rng:
				ent.apply_move_pct_buff("ms_slow", AiConfig.ICE_SHOCK_SLOW_DUR, -min(slw_val, 0.9), true)
				ent.take_damage(AiConfig.ICE_SHOCK_DAMAGE_BASE + hero.level * AiConfig.ICE_SHOCK_DAMAGE_PER_LEVEL, hero, true, -44, 0)
				ent.froze_timer = AiConfig.ICE_SHOCK_FROZE_DUR


func _try_shadow_dart() -> void:
	if hero.shadow_dart_cd > 0 or not hero.equipment_slots.has("shadow_dart"):
		return
	if hero.health >= hero.actual_max_health * (AiConfig.HEALTH_LOW - 0.1):
		return
	if perception.count_enemy_heroes_near(AiConfig.SHADOW_DART_RANGE) < 1:
		return
	hero.shadow_dart_cd = AiConfig.CD_SHADOW_DART
	last_action = "幽影袖箭"
	hero.shadow_dart_active = true
	var dur = AiConfig.DUR_SHADOW_DART_MELEE if hero.attack_range <= 400 else AiConfig.DUR_SHADOW_DART_RANGED
	hero.shadow_dart_timer = dur
	hero.shadow_dart_heal_tick = 0.0
	hero.visible = false
	hero.collision_layer = 0
	hero.apply_move_pct_buff("ms_haste", dur, AiConfig.SHADOW_DART_SPEED_BOOST)
