# ============================================================
# 1. ItemDatabase - 修正为8件3级游走装 + 升级奖赏
# ============================================================
with open('assets/ItemDatabase.gd', 'r', encoding='utf-8') as f:
    items = f.read()

# Remove the old 4 mixed items and replace with 8 proper ones
old_support_block = items.find('# 3级游走装')
old_support_end = items.find('\n\t# =============================================================\n\t# 打野刀系列', old_support_block)
if old_support_end < 0:
    old_support_end = items.find('\n\t# ====', old_support_block + 500)

if old_support_block >= 0:
    new_8_support = '''\t# 3级游走装 (2光环 x 4主动 = 8件)
\titems["redeemer_guard"] = {
\t\t"name": "救赎·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["guardian_glory", "strength_belt"],
\t\t"passive": "守护光环(升级): 8米内+65-130双抗+0.6%HP回血(自身双倍); 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "救赎: 5米队友+240-480+10%HP护盾4秒(60s冷却,按6键)"
\t}
\titems["star_spring_guard"] = {
\t\t"name": "星泉·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["guardian_glory", "strength_belt"],
\t\t"passive": "守护光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "星泉: 链接1名队友每秒回100-212+4%HP+5%法力5秒(50s/次,最多2次,按6键)"
\t}
\titems["galloping_wolf_guard"] = {
\t\t"name": "奔狼·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["guardian_glory", "strength_belt"],
\t\t"passive": "守护光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "奔狼: 5米队友每0.5秒+25-50%移速5秒(90s冷却,按6键)"
\t}
\titems["revealing_light_guard"] = {
\t\t"name": "形昭·守护", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["guardian_glory", "strength_belt"],
\t\t"passive": "守护光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "形昭: 12米光波每0.5秒3%当前HP真伤+25-50%减速2秒+反隐(75s冷却,按6键)"
\t}
\titems["redeemer_shadow"] = {
\t\t"name": "救赎·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["extreme_shadow", "strength_belt"],
\t\t"passive": "迅捷光环(升级): 8米内+10%攻速+7.5%CD+8回蓝(自身双倍); 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "救赎: 5米队友+240-480+10%HP护盾4秒(60s冷却,按6键)"
\t}
\titems["star_spring_shadow"] = {
\t\t"name": "星泉·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["extreme_shadow", "strength_belt"],
\t\t"passive": "迅捷光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "星泉: 链接1名队友每秒回100-212+4%HP+5%法力5秒(50s/次,最多2次,按6键)"
\t}
\titems["galloping_wolf_shadow"] = {
\t\t"name": "奔狼·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["extreme_shadow", "strength_belt"],
\t\t"passive": "迅捷光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "奔狼: 5米队友每0.5秒+25-50%移速5秒(90s冷却,按6键)"
\t}
\titems["revealing_light_shadow"] = {
\t\t"name": "形昭·迅光", "tier": 3, "health": 1200, "speed": 8, "cost": 2080, "class": "support",
\t\t"requires": ["extreme_shadow", "strength_belt"],
\t\t"passive": "迅捷光环(升级): 同上; 奖赏: +400-800HP+25-50AD或50-100AP",
\t\t"active": "形昭: 12米光波每0.5秒3%当前HP真伤+25-50%减速2秒+反隐(75s冷却,按6键)"
\t}\n'''

    items = items[:old_support_block] + new_8_support + items[old_support_end:]
    print('1a. Replaced with 8 support items')

with open('assets/ItemDatabase.gd', 'w', encoding='utf-8') as f:
    f.write(items)

# ============================================================
# 2. SkillDatabase - 添加9个召唤师技能
# ============================================================
with open('assets/SkillDataBase.gd', 'r', encoding='utf-8') as f:
    skills = f.read()

# Find the summoner skills section (flash, smite)
summ_start = skills.find('# 闪现、惩戒等召唤师技能')
summ_end = skills.find('func get_skill', summ_start)

new_summ = '''\t# ==================== 召唤师技能 ====================
\tsk = Skill.new()
\tsk.skill_name = "闪现"; sk.cooldown = 120.0; sk.mana_cost = 0
\tsk.type = 4; sk.self_displacement = 5.0; sk.cast_time = 0.0
\tskills["flash"] = sk

\tsk = Skill.new()
\tsk.skill_name = "疾跑"; sk.cooldown = 75.0; sk.mana_cost = 0
\tsk.type = 2; sk.duration = 10.0; sk.cast_time = 0.0
\tskills["sprint"] = sk

\tsk = Skill.new()
\tsk.skill_name = "传送"; sk.cooldown = 75.0; sk.mana_cost = 0
\tsk.type = 2; sk.cast_time = 2.0
\tskills["teleport"] = sk

\tsk = Skill.new()
\tsk.skill_name = "治疗术"; sk.cooldown = 120.0; sk.mana_cost = 0
\tsk.type = 2; sk.cast_time = 0.0
\tskills["heal"] = sk

\tsk = Skill.new()
\tsk.skill_name = "终结"; sk.cooldown = 60.0; sk.mana_cost = 0
\tsk.type = 0; sk.cast_range = 5.0; sk.cast_time = 0.0
\tskills["execute"] = sk

\tsk = Skill.new()
\tsk.skill_name = "狂暴"; sk.cooldown = 75.0; sk.mana_cost = 0
\tsk.type = 2; sk.duration = 7.0; sk.cast_time = 0.0
\tskills["frenzy"] = sk

\tsk = Skill.new()
\tsk.skill_name = "晕眩"; sk.cooldown = 90.0; sk.mana_cost = 0
\tsk.type = 1; sk.radius = 5.0; sk.cast_time = 0.0
\tskills["stun"] = sk

\tsk = Skill.new()
\tsk.skill_name = "净化"; sk.cooldown = 120.0; sk.mana_cost = 0
\tsk.type = 2; sk.cast_time = 0.0
\tskills["cleanse_summoner"] = sk

\tsk = Skill.new()
\tsk.skill_name = "弱化"; sk.cooldown = 75.0; sk.mana_cost = 0
\tsk.type = 2; sk.duration = 4.0; sk.cast_time = 0.0
\tskills["weaken"] = sk

\tsk = Skill.new()
\tsk.skill_name = "惩击"; sk.cooldown = 30.0; sk.mana_cost = 0
\tsk.damage = 1500.0; sk.bonus_ratio = 0.0; sk.type = 0; sk.cast_range = 3.0; sk.cast_time = 0.0
\tskills["smite"] = sk\n'''

if summ_start >= 0:
    skills = skills[:summ_start] + new_summ + skills[summ_end:]
    print('2. Added 9 summoner spells')
else:
    print('2. Could not find summoner section')

with open('assets/SkillDataBase.gd', 'w', encoding='utf-8') as f:
    f.write(skills)

# ============================================================
# 3. Hero.gd - 实现召唤师技能效果
# ============================================================
with open('scripts/entities/Hero.gd', 'r', encoding='utf-8') as f:
    hero = f.read()

# Find _use_summoner and replace with expanded version
old_use = hero.find('func _use_summoner():')
old_use_end = hero.find('func _get_nearest_enemy_in_range', old_use)

if old_use_start >= 0 and old_use_end >= 0:
    new_use = '''func _use_summoner():
\tif not summoner_skill or summoner_cooldown > 0: return
\tvar cd = summoner_skill.cooldown
\t# 冷静之靴加速冷却
\tif equipment_slots.has("cd_boots"):
\t\tcd /= (1.0 + 0.10 + level * 0.007)
\tmatch summoner_skill.skill_name:
\t\t"闪现":
\t\t\tvar dir = Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
\t\t\tif dir.length() < 0.1: dir = Vector3.FORWARD
\t\t\tglobal_position += dir.normalized() * 5.0
\t\t"疾跑":
\t\t\tapply_slow(10.0, -0.3)\n\t\t\t_cleanse()
\t\t"传送":
\t\t\tvar target_pos = global_position
\t\t\tvar nearest_turret = null; var best_d2 = 99999.0
\t\t\tfor ent in get_tree().get_nodes_in_group("entities"):
\t\t\t\tif ent is Turret and ent.team == team and ent.health > 0:
\t\t\t\t\tvar d2 = global_position.distance_squared_to(ent.global_position)
\t\t\t\t\tif d2 < best_d2: best_d2 = d2; nearest_turret = ent
\t\t\tif nearest_turret: start_teleport(nearest_turret.global_position)
\t\t"治疗术":
\t\t\thealth = min(health + actual_max_health * 0.15, actual_max_health)
\t\t\tapply_slow(2.0, -0.15)
\t\t\tfor ent in get_tree().get_nodes_in_group("heroes"):
\t\t\t\tif ent != self and ent.team == team and global_position.distance_to(ent.global_position) <= 3.0:
\t\t\t\t\tent.health = min(ent.health + ent.actual_max_health * 0.15, ent.actual_max_health)
\t\t"终结":
\t\t\tvar target = _get_nearest_enemy_in_range(5.0)
\t\t\tif target and target is Hero:
\t\t\t\tvar missing_hp = target.actual_max_health - target.health
\t\t\t\tvar td = missing_hp * 0.16
\t\t\t\ttarget.take_damage(td, self, false, -1, 1.0)
\t\t\tif target and target.health <= 0: cd *= 0.1
\t\t"狂暴":
\t\t\t_apply_ak_buff(0, 0.1, 7.0, false)
\t\t\tbonus_toughness += 0.25
\t\t\tbonus_phys_lifesteal += 0.20
\t\t\tbonus_magic_lifesteal += 0.30
\t\t\t_recalculate_attributes()
\t\t"晕眩":
\t\t\tfor ent in get_tree().get_nodes_in_group("entities"):
\t\t\t\tif ent != self and ent.health > 0 and ent.team != team:
\t\t\t\t\tif global_position.distance_to(ent.global_position) <= 5.0:
\t\t\t\t\t\tent.stun_timer = 0.75; ent.apply_slow(1.0, 0.3)
\t\t"净化":
\t\t\t_cleanse(); bt_timer = 0; wd_timer = 0; stun_timer = 0; slow_timer = 0
\t\t\tknockup_timer = 0; froze_timer = 0
\t\t\tbt_timer = 1.5
\t\t"弱化":
\t\t\tfor ent in get_tree().get_nodes_in_group("entities"):
\t\t\t\tif ent != self and ent.health > 0 and ent.team != team:
\t\t\t\t\tif global_position.distance_to(ent.global_position) <= 5.0:
\t\t\t\t\t\tent._apply_ak_buff(0, -0.2, 4.0, false)
\t\t\t_apply_df_buff(0, 0.2, 4.0, false); _apply_df_buff(0, 0.2, 4.0, true)
\t\t"惩击":
\t\t\tvar target2 = _get_nearest_enemy_in_range(3.0)
\t\t\tif target2:
\t\t\t\tvar sd = 1500 + level * 100
\t\t\t\tif target2 is JungleMonster: target2.take_damage(sd, self, false, -1, 1.0)
\t\t\t\telse: target2.take_damage(sd * 0.25, self, false, -1, 1.0)
\t\t\t\ttarget2.apply_slow(2.0, 0.3)
\tsummoner_cooldown = cd
'''

    hero = hero[:old_use] + new_use + hero[old_use_end:]
    print('3. Expanded _use_summoner with all spells')
else:
    print(f'3. Could not find _use_summoner: start={old_use}, end={old_use_end}')

with open('scripts/entities/Hero.gd', 'w', encoding='utf-8') as f:
    f.write(hero)

# ============================================================
# 4. BattleManager - AI random summoner + hero select fix
# ============================================================
with open('scripts/core/BattleManager.gd', 'r', encoding='utf-8') as f:
    bm = f.read()

# Add summoner selection for heroes
old_summ_sel = 'hero.setup_skills_from_database(config.get("skills", []), config.get("summoner", ""))'
new_summ_sel = ('# 随机召唤师技能（AI用）\n'
                '\tvar summoner_pool = ["flash","sprint","heal","execute","frenzy","stun","cleanse_summoner","weaken","smite"]\n'
                '\tvar chosen_summoner = config.get("summoner", summoner_pool[randi() % summoner_pool.size()])\n'
                '\thero.setup_skills_from_database(config.get("skills", []), chosen_summoner)')
# Replace for AI heroes only (the one inside _create_team_ai)
old_ai_summ = 'ai_hero.setup_skills_from_database(config.get("skills", []), config.get("summoner", ""))'
if old_ai_summ in bm:
    bm = bm.replace(old_ai_summ, new_summ_sel)
    # Also fix the player hero
    old_player_summ = 'hero.setup_skills_from_database(config.get("skills", []), config.get("summoner", ""))'
    if old_player_summ in bm:
        bm = bm.replace(old_player_summ, 'hero.setup_skills_from_database(config.get("skills", []), config.get("summoner", "flash"))')
    print('4. AI random summoner + player flash')
else:
    print('4. Could not find summoner setup')

with open('scripts/core/BattleManager.gd', 'w', encoding='utf-8') as f:
    f.write(bm)

# ============================================================
# 5. Update shop categories with 8 support items
# ============================================================
with open('scripts/ui/UI_Manager.gd', 'r', encoding='utf-8') as f:
    ui = f.read()

old_sup_ids = '"redeemer","star_spring","galloping_wolf","revealing_light"'
new_sup_ids = '"redeemer_guard","star_spring_guard","galloping_wolf_guard","revealing_light_guard","redeemer_shadow","star_spring_shadow","galloping_wolf_shadow","revealing_light_shadow"'
ui = ui.replace(old_sup_ids, new_sup_ids)
# Also fix the first occurrence in _open_shop
ui = ui.replace(old_sup_ids, new_sup_ids)  # Second occurrence in grid
print('5. Updated shop support item IDs')

with open('scripts/ui/UI_Manager.gd', 'w', encoding='utf-8') as f:
    f.write(ui)

# Also update Hero support checks
with open('scripts/entities/Hero.gd', 'r', encoding='utf-8') as f:
    hero = f.read()

old_sup_check = 'equipment_slots.has("redeemer") or equipment_slots.has("star_spring") or equipment_slots.has("galloping_wolf") or equipment_slots.has("revealing_light")'
new_sup_check = 'equipment_slots.has("redeemer_guard") or equipment_slots.has("star_spring_guard") or equipment_slots.has("galloping_wolf_guard") or equipment_slots.has("revealing_light_guard") or equipment_slots.has("redeemer_shadow") or equipment_slots.has("star_spring_shadow") or equipment_slots.has("galloping_wolf_shadow") or equipment_slots.has("revealing_light_shadow")'
hero = hero.replace(old_sup_check, new_sup_check)

# Update is_t3 check
old_t3_check = 'var is_t3 = equipment_slots.has("redeemer") or equipment_slots.has("star_spring")'
new_t3_check = 'var is_t3 = equipment_slots.has("redeemer_guard") or equipment_slots.has("star_spring_guard") or equipment_slots.has("galloping_wolf_guard") or equipment_slots.has("revealing_light_guard") or equipment_slots.has("redeemer_shadow") or equipment_slots.has("star_spring_shadow") or equipment_slots.has("galloping_wolf_shadow") or equipment_slots.has("revealing_light_shadow")'
hero = hero.replace(old_t3_check, new_t3_check)

old_t3b_check = 'var is_t3b = equipment_slots.has("galloping_wolf") or equipment_slots.has("revealing_light")'
new_t3b_check = 'var is_t3b = equipment_slots.has("galloping_wolf_guard") or equipment_slots.has("revealing_light_guard") or equipment_slots.has("galloping_wolf_shadow") or equipment_slots.has("revealing_light_shadow") or equipment_slots.has("redeemer_shadow") or equipment_slots.has("star_spring_shadow")'
hero = hero.replace(old_t3b_check, new_t3b_check)

with open('scripts/entities/Hero.gd', 'w', encoding='utf-8') as f:
    f.write(hero)
print('5b. Updated Hero support checks')

print('\nDone!')
