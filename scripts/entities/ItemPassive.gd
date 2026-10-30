class_name ItemPassive
extends Node
# 装备被动组件 — 管理装备冷却计时、光环、回复和主动装备热键
# 作为 Hero 的子节点附加，通过 hero 引用访问装备状态变量

var hero: Hero

func _ready() -> void:
	if get_parent() is Hero:
		hero = get_parent() as Hero

# 从 Hero._physics_process 提取的装备每帧处理
func process_items(delta: float) -> void:
	if not hero: return

	# 装备冷却计时
	if hero.ice_shock_cd > 0: hero.ice_shock_cd -= delta
	if hero.ice_shock_shield_cd > 0: hero.ice_shock_shield_cd -= delta
	if hero.dragon_shield_cd > 0: hero.dragon_shield_cd -= delta
	if hero.rising_sun_cd > 0: hero.rising_sun_cd -= delta
	if hero.mage_robe_shield_cd > 0: hero.mage_robe_shield_cd -= delta
	if hero.ice_storm_cd > 0: hero.ice_storm_cd -= delta
	if hero.revive_cd > 0: hero.revive_cd -= delta
	if hero.fierce_armor_timer > 0: hero.fierce_armor_timer -= delta
	if hero.red_cloak_timer > 0: hero.red_cloak_timer -= delta
	if hero.fierce_armor_timer <= 0: hero.fierce_armor_stacks = 0
	if hero.night_guardian_timer > 0: hero.night_guardian_timer -= delta
	if hero.ice_fist_cd > 0: hero.ice_fist_cd -= delta
	if hero.famous_blade_cd > 0: hero.famous_blade_cd -= delta
	if hero.sanction_regen_cd > 0: hero.sanction_regen_cd -= delta
	if hero.prophecy_timer > 0: hero.prophecy_timer -= delta

	# 游走装：每3秒+5经验+给最低经济队友5金币
	var has_support = hero.equipment_slots.has("ancient_coin") or hero.equipment_slots.has("wind_blessing") or hero.equipment_slots.has("guardian_glory") or hero.equipment_slots.has("extreme_shadow") or hero.equipment_slots.has("redeemer_guard") or hero.equipment_slots.has("star_spring_guard") or hero.equipment_slots.has("galloping_wolf_guard") or hero.equipment_slots.has("revealing_light_guard") or hero.equipment_slots.has("redeemer_shadow") or hero.equipment_slots.has("star_spring_shadow") or hero.equipment_slots.has("galloping_wolf_shadow") or hero.equipment_slots.has("revealing_light_shadow")
	if has_support:
		hero.support_gold_timer -= delta
		if hero.support_gold_timer <= 0:
			hero.support_gold_timer = 3.0
			hero.add_exp(5)
			var lowest_ally = null; var lowest_gold = 99999
			for ent in hero.get_tree().get_nodes_in_group("heroes"):
				if ent != hero and ent.team == hero.team and ent.health > 0:
					if ent.gold < lowest_gold:
						lowest_gold = ent.gold; lowest_ally = ent
			if lowest_ally:
				lowest_ally.add_gold(5)

	# 疾步之靴计时（脱战5秒后：固定数值移速 buff；受击重置计时后移除）
	if hero.equipment_slots.has("run_boots"):
		hero.boots_speed_timer += delta
		if hero.boots_speed_timer >= 5.0:
			if not hero.has_speed_buff("run_boots"):
				hero.apply_flat_move_buff("run_boots", 999.0, 35 + hero.level * 2.3)
		elif hero.has_speed_buff("run_boots"):
			hero.remove_speed_buff("run_boots")

	# 红莲斗篷光环（每秒1跳）
	if hero.equipment_slots.has("red_cloak") and hero.red_cloak_timer <= 0:
		hero.red_cloak_timer = 1.0
		for ent in hero.get_tree().get_nodes_in_group("entities"):
			if ent != hero and ent.health > 0 and ent.team != hero.team:
				if hero.global_position.distance_to(ent.global_position) <= 3.75:
					var rc_dmg = hero.actual_max_health * 0.015
					if ent is Minion or ent is JungleMonster: rc_dmg *= 2.0
					ent.take_damage(rc_dmg, hero, true, -10, 0)
					ent.grievous_wounds = 0.35; ent.grievous_wounds_timer = 1.0

	# 霸者重装脱战回复
	if hero.equipment_slots.has("heavy_armor"):
		var ha_regen = hero.actual_max_health * 0.005
		if hero.heavy_armor_last_hit >= 3.0: ha_regen *= 2.0
		hero._apply_healing(ha_regen * delta)
		hero.heavy_armor_last_hit += delta

	# 圣杯法力/生命回复
	if hero.equipment_slots.has("saint_cup"):
		hero.mana = min(hero.mana + hero.actual_mana_max * 0.015 * delta, hero.actual_mana_max)
		var sc_hp = hero.actual_max_health * 0.005 * delta
		if hero.mana >= hero.actual_mana_max: sc_hp += hero.actual_max_health * 0.005 * delta
		hero._apply_healing(sc_hp)

	# 炽热支配：低血量自动净化+护盾+加速
	if hero.equipment_slots.has("fire_dominate") and hero.health < hero.actual_max_health * 0.3 and hero.health > 0 and hero.fire_dominate_cd <= 0:
		hero.fire_dominate_cd = 90.0; hero._cleanse()
		var fd_shield = 500 + hero.level * 33 + hero.actual_ability_power * 1.0 + hero.actual_max_health * 0.075
		hero.shield_remaining = max(hero.shield_remaining, fd_shield); hero.shield_timer = 4.0
		hero.apply_move_pct_buff("ms_haste", 4.0, 0.3)

	# 制裁之刃：低血量自动回复
	if hero.equipment_slots.has("blade_of_sanction") and hero.health < hero.actual_max_health * 0.3 and hero.health > 0:
		if hero.sanction_regen_cd <= 0: hero.sanction_regen_cd = 20.0; var tr = 375 + hero.level * 25; hero.apply_regen(tr / 5.0, 0, 5.0, "sanction")

	# 永夜守护：受击回复
	if hero.equipment_slots.has("night_guardian") and hero.night_guardian_cd <= 0 and hero.night_guardian_hp_track > hero.actual_max_health * 0.25:
		hero.night_guardian_cd = 7.0; hero.apply_regen(hero.actual_max_health * 0.02 / 0.5, 0, 2.5, "night_guardian")
		hero.apply_move_pct_buff("ms_haste", 2.5, 0.5); hero.night_guardian_hp_track = 0

	# 魔女斗篷：脱战法伤护盾
	if hero.equipment_slots.has("mage_robe") and hero.mage_robe_shield_cd <= 0:
		hero.mage_robe_shield_cd = 15.0
		var mr_shield = 400 + hero.level * 26 + hero.actual_max_health * 0.07
		hero.shield_remaining = max(hero.shield_remaining, mr_shield); hero.shield_timer = 999

	# 血魔之怒(怒魂)：变身光环伤害
	if hero.equipment_slots.has("rage_ghost") and hero.blood_rage_active:
		for ent in hero.get_tree().get_nodes_in_group("entities"):
			if ent != hero and ent.health > 0 and ent.team != hero.team:
				if hero.global_position.distance_to(ent.global_position) <= 3.0:
					ent.take_damage(hero.actual_max_health * 0.04, hero, true, -11, 0)

# 主动装备快捷键处理（从 Hero._handle_skill_input 提取）
func handle_active_input() -> void:
	if not hero: return

	# V=纯净苍穹/天穹
	if Input.is_key_pressed(KEY_V):
		var has_tq = hero.equipment_slots.has("immovable_firmament")
		var has_cl = hero.equipment_slots.has("purify")
		if (has_cl or has_tq) and hero.purify_cd <= 0:
			hero.purify_cd = 75.0
			hero._apply_df_buff(0, 0.3, 3.0, false)
			hero._apply_df_buff(0, 0.3, 3.0, true)
			if has_tq:
				hero.apply_move_pct_buff("ms_haste", 3.0, 0.3)
				hero.fly = 0.5; hero.fly_timer = 3.0
				hero._cleanse()
			SfxManager.try_item_active_sfx(hero.display_name, "immovable_firmament" if has_tq else "purify", "df")

	# 7=幽影袖箭
	if Input.is_key_pressed(KEY_7) and hero.equipment_slots.has("shadow_dart") and hero.shadow_dart_cd <= 0 and not hero.shadow_dart_active:
		hero.shadow_dart_cd = 60.0; hero.shadow_dart_active = true
		var dur = 1.25 if hero.attack_range <= 400 else 2.5
		hero.shadow_dart_timer = dur; hero.shadow_dart_heal_tick = 0.0
		hero.collision_layer = 0
		hero.apply_move_pct_buff("ms_haste", dur, 0.3)
		SfxManager.try_item_active_sfx(hero.display_name, "shadow_dart", "haste")

	# =逐日之弓/日渊
	if Input.is_key_pressed(KEY_EQUAL):
		var has_ry = hero.equipment_slots.has("swift_day")
		var has_zr = hero.equipment_slots.has("sunspire_bow")
		if (has_zr or has_ry) and hero.sunspire_active_cd <= 0:
			hero.sunspire_active_cd = 75.0; hero.sunspire_active = true; hero.sunspire_active_timer = 5.0
			var spd_bonus = 0.4 if has_ry else 0.2
			hero.apply_move_pct_buff("ms_haste", 5.0, spd_bonus)
			if hero.attack_range > 500: hero.multiply_attack_range_base(1.25)
			SfxManager.try_item_active_sfx(hero.display_name, "sunspire_bow" if has_zr else "swift_day", "range")

	# 9=反伤刺甲
	if Input.is_key_pressed(KEY_9) and hero.equipment_slots.has("thornmail") and hero.thornmail_cd <= 0:
		hero.thornmail_cd = 75.0; hero.thornmail_active = true; hero.thornmail_timer = 3.0
		SfxManager.try_item_active_sfx(hero.display_name, "thornmail", "thorn")

	# 0=血魔之怒/怒魂
	if Input.is_key_pressed(KEY_0) and (hero.equipment_slots.has("blood_rage") or hero.equipment_slots.has("rage_ghost")) and hero.blood_rage_cd <= 0:
		hero.blood_rage_cd = 75.0; hero.blood_rage_active = true; hero.blood_rage_timer = 4.0
		var hp_drain_per_sec = hero.health * 0.3 / 4.0
		var shield_per_sec = hero.actual_max_health * 0.4 / 4.0
		hero.apply_regen(-hp_drain_per_sec, 0, 4.0, "blood_rage_hp")
		hero.apply_regen(0, 0, 4.0, "blood_rage_shield")
		hero.shield_remaining = max(hero.shield_remaining, shield_per_sec)
		hero.shield_timer = 1.0
		SfxManager.try_item_active_sfx(hero.display_name, "rage_ghost" if hero.equipment_slots.has("rage_ghost") else "blood_rage", "blood")

	# -=冰霜冲击/凛冬
	if Input.is_key_pressed(KEY_MINUS) and (hero.equipment_slots.has("ice_shock") or hero.equipment_slots.has("sereve_winter")) and hero.ice_shock_cd <= 0:
		hero.ice_shock_cd = 75.0
		var range2 = 6.0 if hero.equipment_slots.has("sereve_winter") else 4.5
		var slow2 = 0.9 if hero.equipment_slots.has("sereve_winter") else 0.3 + hero.level * 0.002
		for ent in hero.get_tree().get_nodes_in_group("entities"):
			if ent != hero and ent.health > 0 and ent.team != hero.team:
				if hero.global_position.distance_to(ent.global_position) <= range2:
					ent.apply_move_pct_buff("ms_slow", 0.75, -min(slow2, 0.9), true)
					ent.take_damage(100 + hero.level * 6.6, hero, true, -44, 0)
					ent.froze_timer = 0.75
		SfxManager.try_item_active_sfx(hero.display_name, "sereve_winter" if hero.equipment_slots.has("sereve_winter") else "ice_shock", "ice")

	# 8=辉月/月神
	if Input.is_key_pressed(KEY_8) and (hero.equipment_slots.has("golden_body") or hero.equipment_slots.has("moon_god")) and hero.golden_body_cd <= 0 and not hero.golden_body_active:
		hero.golden_body_cd = 75.0; hero.golden_body_active = true; hero.golden_body_timer = 1.5
		hero.wd_timer = 1.5; hero.stun_timer = 1.5
		if hero.equipment_slots.has("moon_god"):
			var mg_heal_total = 1000 + hero.actual_ability_power * 1.0
			hero.apply_regen(mg_heal_total / 1.5, 0, 1.5, "moon_god")
		SfxManager.try_item_active_sfx(hero.display_name, "moon_god" if hero.equipment_slots.has("moon_god") else "golden_body", "stasis")
