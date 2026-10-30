# ============================================================
# 1. Fix skill bar indentation (line 1257 elif)
# ============================================================
with open('scripts/ui/UI_Manager.gd', 'r', encoding='utf-8') as f:
    ui = f.read()

# Fix: Replace the broken skill update elif chain
old_skill_update = '''\t\tfor i in range(7):
\t\t\tvar icon = skill_icons[i] as SkillIcon if i < skill_icons.size() else null
\t\t\tvar lv_label = skill_level_labels[i] if i < skill_level_labels.size() else null
\t\t\tvar name_label = skill_name_labels[i] if i < skill_name_labels.size() else null
\t\t\tvar info_label = skill_info_labels[i] if i < skill_info_labels.size() else null
\t\t\ticon.hero = hero; icon.slot = i
\t\t\tif i >= 4 and hero.summoner_skill != null:
\t\t\t\ticon.skill = hero.summoner_skill; icon.skill_level = 1; icon.max_cd = hero.summoner_skill.cooldown; icon.cd_remaining = hero.summoner_cooldown; icon.mana_cost = hero.summoner_skill.mana_cost; icon.current_mana = int(hero.mana)
\t\t\t\tif lv_label: lv_label.text = ""
\t\t\t\tif name_label: name_label.text = hero.summoner_skill.skill_name
\t\t\t\tif info_label: info_label.text = "%.0fs" % icon.max_cd
\t\t\t\ticon.visible = true; if lv_label: lv_label.visible = true; if name_label: name_label.visible = true; if info_label: info_label.visible = true
\t\t\telif i < hero.skills.size() and hero.skills[i]:
\t\t\t\tvar skill = hero.skills[i] as Skill; icon.skill = skill; icon.skill_level = hero.skill_levels[i]
\t\t\t\ticon.max_cd = icon.skill.cooldown - icon.skill.cd_bonus * (hero.skill_levels[i] - 1)
\t\t\t\ticon.mana_cost = icon.skill.mana_cost - icon.skill.power_bonus * (hero.skill_levels[i] - 1)
\t\t\t\ticon.cd_remaining = hero.skill_cooldowns[i]; icon.current_mana = int(hero.mana)
\t\t\t\tif lv_label: lv_label.text = "Lv.%d" % icon.skill_level if i <3 else ""
\t\t\t\tif name_label: name_label.text = skill.skill_name
\t\t\t\tif info_label: info_label.text = "%d蓝 %.1fs" % [icon.mana_cost, icon.max_cd]
\t\t\t\ticon.visible = true; if lv_label: lv_label.visible = true; if name_label: name_label.visible = true; if info_label: info_label.visible = true
\t\t\t\telif i >= 5:
\t\t\t\t\t# 动态主动装备槽
\t\t\t\t\tvar ae_list = _get_active_equip_list(hero)
\t\t\t\t\tvar ae_idx = i - 5
\t\t\t\t\tif ae_idx < ae_list.size():
\t\t\t\t\t\tvar ae = ae_list[ae_idx]
\t\t\t\t\t\ticon.skill = null; icon.skill_level = 1
\t\t\t\t\t\ticon.max_cd = ae.max_cd; icon.cd_remaining = ae.cd_remaining
\t\t\t\t\t\ticon.current_mana = 0; icon.hero = hero; icon.slot = i
\t\t\t\t\t\ticon.is_active_equip = true; icon.active_equip_id = ae.id
\t\t\t\t\t\ticon.visible = true
\t\t\t\t\t\tif lv_label: lv_label.text = ""; lv_label.visible = true
\t\t\t\t\t\tif name_label: name_label.text = ae.name; name_label.visible = true
\t\t\t\t\t\tif info_label: info_label.text = "%.0fs" % ae.max_cd; info_label.visible = true
\t\t\t\t\telse:
\t\t\t\t\t\ticon.visible = false
\t\t\t\t\t\tif lv_label: lv_label.visible = false
\t\t\t\t\t\tif name_label: name_label.visible = false
\t\t\t\t\t\tif info_label: info_label.visible = false
\t\t\t\t\t\ticon.queue_redraw()
\t\t\t\t\t\tcontinue
\t\t\t\ticon.queue_redraw()'''

new_skill_update = '''\t\tfor i in range(7):
\t\t\tvar icon = skill_icons[i] as SkillIcon if i < skill_icons.size() else null
\t\t\tvar lv_label = skill_level_labels[i] if i < skill_level_labels.size() else null
\t\t\tvar name_label = skill_name_labels[i] if i < skill_name_labels.size() else null
\t\t\tvar info_label = skill_info_labels[i] if i < skill_info_labels.size() else null
\t\t\tif icon == null: continue
\t\t\ticon.hero = hero; icon.slot = i
\t\t\tif i == 4 and hero.summoner_skill != null:
\t\t\t\ticon.skill = hero.summoner_skill; icon.skill_level = 1
\t\t\t\ticon.max_cd = hero.summoner_skill.cooldown
\t\t\t\ticon.cd_remaining = hero.summoner_cooldown
\t\t\t\ticon.mana_cost = hero.summoner_skill.mana_cost; icon.current_mana = int(hero.mana)
\t\t\t\tif lv_label: lv_label.text = \"\"
\t\t\t\tif name_label: name_label.text = hero.summoner_skill.skill_name
\t\t\t\tif info_label: info_label.text = \"%.0fs\" % icon.max_cd
\t\t\t\ticon.visible = true
\t\t\t\tif lv_label: lv_label.visible = true
\t\t\t\tif name_label: name_label.visible = true
\t\t\t\tif info_label: info_label.visible = true
\t\t\telif i < hero.skills.size() and hero.skills[i] and i < 4:
\t\t\t\tvar skill = hero.skills[i] as Skill; icon.skill = skill
\t\t\t\ticon.skill_level = hero.skill_levels[i]
\t\t\t\ticon.max_cd = skill.cooldown - skill.cd_bonus * (hero.skill_levels[i] - 1)
\t\t\t\ticon.mana_cost = skill.mana_cost - skill.power_bonus * (hero.skill_levels[i] - 1)
\t\t\t\ticon.cd_remaining = hero.skill_cooldowns[i]; icon.current_mana = int(hero.mana)
\t\t\t\tif lv_label: lv_label.text = \"Lv.%d\" % icon.skill_level if i < 3 else \"\"
\t\t\t\tif name_label: name_label.text = skill.skill_name
\t\t\t\tif info_label: info_label.text = \"%d蓝 %.1fs\" % [icon.mana_cost, icon.max_cd]
\t\t\t\ticon.visible = true
\t\t\t\tif lv_label: lv_label.visible = true
\t\t\t\tif name_label: name_label.visible = true
\t\t\t\tif info_label: info_label.visible = true
\t\t\telif i >= 5:
\t\t\t\tvar ae_list = _get_active_equip_list(hero)
\t\t\t\tvar ae_idx = i - 5
\t\t\t\tif ae_idx < ae_list.size():
\t\t\t\t\tvar ae = ae_list[ae_idx]
\t\t\t\t\ticon.skill = null; icon.skill_level = 1
\t\t\t\t\ticon.max_cd = ae.max_cd; icon.cd_remaining = ae.cd_remaining
\t\t\t\t\ticon.current_mana = 0
\t\t\t\t\ticon.is_active_equip = true; icon.active_equip_id = ae.id
\t\t\t\t\ticon.visible = true
\t\t\t\t\tif lv_label: lv_label.text = \"\"; lv_label.visible = true
\t\t\t\t\tif name_label: name_label.text = ae.name; name_label.visible = true
\t\t\t\t\tif info_label: info_label.text = \"%.0fs\" % ae.max_cd; info_label.visible = true
\t\t\t\telse:
\t\t\t\t\ticon.visible = false
\t\t\t\t\tif lv_label: lv_label.visible = false
\t\t\t\t\tif name_label: name_label.visible = false
\t\t\t\t\tif info_label: info_label.visible = false
\t\t\telse:
\t\t\t\ticon.visible = false
\t\t\t\tif lv_label: lv_label.visible = false
\t\t\t\tif name_label: name_label.visible = false
\t\t\t\tif info_label: info_label.visible = false
\t\t\ticon.queue_redraw()'''

if old_skill_update in ui:
    ui = ui.replace(old_skill_update, new_skill_update)
    print('1. Fixed skill bar update indentation')
else:
    print('1. Skill update pattern not found - searching...')
    idx = ui.find('for i in range(7):\n\t\t\tvar icon = skill_icons')
    if idx >= 0:
        print(f'  Found at {idx}')
    else:
        print('  NOT FOUND')

with open('scripts/ui/UI_Manager.gd', 'w', encoding='utf-8') as f:
    f.write(ui)

# ============================================================
# 2. Add summoner spell selection to hero select UI
# ============================================================
with open('scripts/core/BattleManager.gd', 'r', encoding='utf-8') as f:
    bm = f.read()

# Find _show_hero_select_ui and modify to include summoner selection
old_select = 'func _show_hero_select_ui():'
old_select_end = bm.find('func add_team_kill', bm.find(old_select))

if old_select >= 0:
    new_select = '''func _show_hero_select_ui():
\tselect_ui = CanvasLayer.new()
\tvar panel = Panel.new()
\tpanel.size = Vector2(600, 500)
\tpanel.position = (get_viewport().get_visible_rect().size - panel.size) / 2
\tselect_ui.add_child(panel)

\tvar vbox = VBoxContainer.new()
\tvbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
\tvbox.alignment = BoxContainer.ALIGNMENT_CENTER
\tpanel.add_child(vbox)

\tvar title = Label.new()
\ttitle.text = "选择英雄 + 召唤师技能"
\ttitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
\ttitle.add_theme_font_size_override("font_size", 20)
\tvbox.add_child(title)

\tvar hbox = HBoxContainer.new()
\thbox.alignment = BoxContainer.ALIGNMENT_CENTER
\tvbox.add_child(hbox)

\t# 英雄列表
\tvar hero_vbox = VBoxContainer.new()
\tvar hero_title = Label.new()
\thero_title.text = "英雄"
\thero_title.add_theme_font_size_override("font_size", 16)
\thero_vbox.add_child(hero_title)
\tfor type in hero_configs.keys():
\t\tvar btn = Button.new()
\t\tbtn.text = type; btn.custom_minimum_size = Vector2(160, 32)
\t\tbtn.pressed.connect(_on_hero_selected.bind(type))
\t\thero_vbox.add_child(btn)
\thbox.add_child(hero_vbox)

\t# 召唤师技能列表
\tvar summ_vbox = VBoxContainer.new()
\tvar summ_title = Label.new()
\tsumm_title.text = "召唤师技能"
\tsumm_title.add_theme_font_size_override("font_size", 16)
\tsumm_vbox.add_child(summ_title)
\tvar summons = {"闪现": "flash", "疾跑": "sprint", "治疗术": "heal", "终结": "execute", "狂暴": "frenzy", "晕眩": "stun", "净化": "cleanse_summoner", "弱化": "weaken", "惩击": "smite"}
\tfor sname in summons:
\t\tvar btn = Button.new()
\t\tbtn.text = sname; btn.custom_minimum_size = Vector2(160, 32)
\t\tbtn.pressed.connect(_on_summoner_selected.bind(summons[sname]))
\t\tsumm_vbox.add_child(btn)
\thbox.add_child(summ_vbox)

\tadd_child(select_ui)
\tselected_summoner = "flash"

func _on_summoner_selected(id: String):
\tselected_summoner = id

func _on_hero_selected(type: String):
\tif selected_summoner == "": selected_summoner = "flash"
\t_start_game(type, selected_summoner)
'''

    # Find _start_game and modify signature
    old_start_game = 'func _start_game(hero_type: String):'
    new_start_game = 'func _start_game(hero_type: String, summoner_id: String = "flash"):'
    bm = bm.replace(old_start_game, new_start_game)

    # Add summoner to player hero creation
    old_player_create = 'hero.setup_skills_from_database(config.get("skills", []), "flash")'
    new_player_create = 'hero.setup_skills_from_database(config.get("skills", []), summoner_id)'
    bm = bm.replace(old_player_create, new_player_create)

    # Add selected_summoner variable
    old_hero_sel = 'var hero_selected: bool = false'
    new_hero_sel = 'var hero_selected: bool = false\nvar selected_summoner: String = "flash"'
    bm = bm.replace(old_hero_sel, new_hero_sel)

    # Replace the old _show_hero_select_ui
    bm = bm[:old_select] + new_select + bm[old_select_end:]
    print('2. Added summoner spell selection UI')

with open('scripts/core/BattleManager.gd', 'w', encoding='utf-8') as f:
    f.write(bm)

# ============================================================
# 3. Optimize AI equipment logic
# ============================================================
with open('ai/HeroAI.gd', 'r', encoding='utf-8') as f:
    ai = f.read()

# Replace _get_recommended_items with role-based builds from the guide
old_rec = ai.find('func _get_recommended_items() -> Array:')
old_rec_end = ai.find('var recommended_items: Array = []', old_rec)

if old_rec >= 0 and old_rec_end >= 0:
    new_rec = '''func _get_recommended_items() -> Array:
\t# 基于标准出装思路的分位置推荐
\tmatch hero.role:
\t\t\"射手\":
\t\t\treturn [\"swift_boots\", \"world_end\", \"purify\", \"dawn\", \"mage_robe\", \"famous_blade\"]
\t\t\"战士\":
\t\t\treturn [\"resist_boots\", \"battle_axe\", \"ice_fist\", \"breaker\", \"omen\", \"mage_robe\"]
\t\t\"坦克\":
\t\t\treturn [\"armor_boots\", \"red_cloak\", \"eye_of_the_phoenix\", \"omen\", \"mage_robe\", \"blood_rage\"]
\t\t\"法师\":
\t\t\treturn [\"cd_boots\", \"echo_staff\", \"rabadon\", \"void_staff\", \"golden_body\", \"sky_book\"]
\t\t\"刺客\":
\t\t\treturn [\"resist_boots\", \"battle_axe\", \"infinity_edge\", \"breaker\", \"famous_blade\", \"omen\"]
\t\t\"辅助\":
\t\t\treturn [\"guardian_glory\", \"resist_boots\", \"omen\", \"mage_robe\", \"heavy_armor\", \"redeemer_guard\"]
\t\t_:
\t\t\treturn [\"resist_boots\", \"battle_axe\", \"bloodthirster\", \"breaker\", \"omen\", \"mage_robe\"]
'''

    ai = ai[:old_rec] + new_rec + ai[old_rec_end:]
    print('3. Optimized AI recommended builds')

# Improve AI buy priority: boots first, then components
old_buy_comment = '# 严格按推荐顺序处理'
new_buy_comment = ('# 出装优先级：鞋子 > 小件过渡 > 核心大件 > 针对性防具 > 保命装\n'
                   '\t# 第一波回家先补鞋子\n'
                   '\tvar has_boots = false\n'
                   '\tfor oid in hero.equipment_slots:\n'
                   '\t\tvar oitem = ItemDatabase.get_item(oid)\n'
                   '\t\tif oitem.get(\"class\", \"\") == \"boots\":\n'
                   '\t\t\thas_boots = true; break\n'
                   '\tif not has_boots:\n'
                   '\t\tfor bid in [\"resist_boots\", \"armor_boots\", \"swift_boots\", \"cd_boots\", \"spell_boots\", \"run_boots\"]:\n'
                   '\t\t\tif not hero.equipment_slots.has(bid) and hero.gold >= ItemDatabase.get_item(bid)[\"cost\"]:\n'
                   '\t\t\t\tif hero.buy_equipment(bid): return\n'
                   '\t' + old_buy_comment)
ai = ai.replace(old_buy_comment, new_buy_comment)
print('3b. Added boots priority')

with open('ai/HeroAI.gd', 'w', encoding='utf-8') as f:
    f.write(ai)

# ============================================================
# 4. Optimize AI lane/decision logic
# ============================================================
with open('ai/HeroAI.gd', 'r', encoding='utf-8') as f:
    ai = f.read()

# Replace _assign_lane with role-based lane assignment
old_lane = 'func _assign_lane():\n\tlane = randi() % 4'
new_lane = ('func _assign_lane():\n'
            '\t# 基于职业的标准分路\n'
            '\tmatch hero.role:\n'
            '\t\t\"射手\": lane = Lane.BOT\n'
            '\t\t\"法师\": lane = Lane.MID\n'
            '\t\t\"刺客\": lane = Lane.JUNGLE\n'
            '\t\t\"战士\": lane = Lane.TOP if randf() < 0.7 else Lane.JUNGLE\n'
            '\t\t\"坦克\": lane = Lane.TOP\n'
            '\t\t\"辅助\": lane = Lane.BOT\n'
            '\t\t_: lane = randi() % 4')
ai = ai.replace(old_lane, new_lane)
print('4. Role-based lane assignment')

# Improve _decide with better retreat logic
old_decide_end = 'else:\n\t\t\t\t# 线上始终保持推进状态，由推进逻辑内部处理细节\n\t\t\t\tstate = State.PUSH'
new_decide_end = ('else:\n'
                  '\t\t\t\t# 线上始终保持推进状态\n'
                  '\t\t\t\tstate = State.PUSH\n'
                  '\t# 逆风检测：己方经济落后>2000时更谨慎\n'
                  '\tvar bm = get_tree().get_first_node_in_group(\"battle_manager\") as BattleManager\n'
                  '\tif bm:\n'
                  '\t\tvar our_gold = bm.team_player_gold\n'
                  '\t\tvar enemy_gold = bm.team_enemy_gold\n'
                  '\t\tif enemy_gold - our_gold > 2000 and hero.role in [\"射手\",\"法师\"]:\n'
                  '\t\t\t# 逆风输出位优先保命\n'
                  '\t\t\tif hero.equipment_slots.size() < 3:\n'
                  '\t\t\t\tstate = State.DEFEND')
ai = ai.replace(old_decide_end, new_decide_end)
print('4b. Wind-aware AI decisions')

with open('ai/HeroAI.gd', 'w', encoding='utf-8') as f:
    f.write(ai)

print('\nDone!')
