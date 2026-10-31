"""Add Sun Wukong skill definitions + apply_skills to SkillDataBase.gd — CRLF."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "assets", "SkillDataBase.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'
tab = b'\t'
fixed = 0

# === PART A: Skill definitions (insert after 刘禅 R, before 召唤师技能) ===
# Pattern: \tskills["liushan_r"] = sk\r\n\r\n\t# ==== 召唤师技能 ====
old_a = tab + enc('skills["liushan_r"] = sk') + le + le + tab + enc('# ==================== 召唤师技能 ====================')

if data.count(old_a) == 1:
    insert_pos = data.find(old_a) + len(tab + enc('skills["liushan_r"] = sk') + le)
    def_parts = [
        le,
        tab + enc('# ==================== 孙悟空 ===================='),
        tab + enc('sk = Skill.new()'),
        tab + enc('sk.skill_name = "护身咒法"; sk.cooldown = 12.0; sk.mana_cost = 65'),
        tab + enc('sk.cd_bonus = 0.4; sk.type = 2; sk.cast_time = 0.1'),
        tab + enc('skills["sunwukong_q"] = sk'),
        le,
        tab + enc('sk = Skill.new()'),
        tab + enc('sk.skill_name = "斗战冲锋"; sk.cooldown = 6.0; sk.mana_cost = 45'),
        tab + enc('sk.cd_bonus = 0.2; sk.type = 2; sk.cast_time = 0.1'),
        tab + enc('skills["sunwukong_w"] = sk'),
        le,
        tab + enc('sk = Skill.new()'),
        tab + enc('sk.skill_name = "如意金箍"; sk.cooldown = 40.0; sk.mana_cost = 100'),
        tab + enc('sk.cd_bonus = 5.0; sk.type = 1; sk.radius = 4.0; sk.cast_time = 0.3'),
        tab + enc('skills["sunwukong_r"] = sk'),
        le,
    ]
    skill_defs_block = b''.join(def_parts)  # each part already has \r\n or is standalone
    data = data[:insert_pos] + skill_defs_block + data[insert_pos:]
    print("[OK] PART A: skill definitions added")
    fixed += 1
else:
    print(f"[FAIL] PART A: count={data.count(old_a)}")

# === PART B: apply_skills block ===
# Pattern: \t\t\t\t\tent.apply_slow(0.5, _slow_pct)\r\n\r\n\r\n# 冰冷效果
old_b = tab*5 + enc('ent.apply_slow(0.5, _slow_pct)') + le + le + le + enc('# 冰冷效果：同时削减移速和攻速')

if data.count(old_b) == 1:
    insert_pos = data.find(old_b) + len(tab*5 + enc('ent.apply_slow(0.5, _slow_pct)') + le)

    # Build the apply_skills block as raw bytes
    apply_parts = [
        le,  # blank line before 孙悟空 case
        tab*2 + enc('"孙悟空":match  skill_id:'),
        tab*3 + enc('1:  # 护身咒法：加速40% 1秒 + 格挡窗口1.5秒'),
        tab*4 + enc('hero.apply_slow(1.0, -0.4)'),
        tab*4 + enc('hero.sunwukong_1_block_active = true'),
        tab*4 + enc('hero.sunwukong_1_block_timer = 1.5'),
        tab*4 + enc('hero.sunwukong_enhanced_aa = true'),
        tab*3 + enc('2:  # 斗战冲锋：冲刺+碰撞伤害+斩杀'),
        tab*4 + enc('var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))'),
        tab*4 + enc('var dir = Vector3(cos(ang),0,-sin(ang))'),
        tab*4 + enc('var old_pos = hero.global_position'),
        tab*4 + enc('hero.global_position += dir * 4.0'),
        tab*4 + enc('hero.global_position.y = 0.5'),
        tab*4 + enc('var new_pos = hero.global_position'),
        tab*4 + enc('var line_vec = new_pos - old_pos'),
        tab*4 + enc('var w_dmg = int(320 + 64*(level-1) + hero.bonus_attack * 1.0)'),
        tab*4 + enc('var hit_enemy = false'),
        tab*4 + enc('for ent in hero.get_tree().get_nodes_in_group("entities"):'),
        tab*5 + enc('if ent == hero or ent.health <= 0 or ent.team == hero.team: continue'),
        tab*5 + enc('var t = clamp((ent.global_position - old_pos).dot(line_vec) / line_vec.length_squared(), 0, 1)'),
        tab*5 + enc('var closest = old_pos + line_vec * t'),
        tab*5 + enc('if closest.distance_to(ent.global_position) <= 2.0:'),
        tab*6 + enc('hit_enemy = true'),
        tab*6 + enc('# 斩杀：小兵/非史诗野怪低于15%HP → 99999真实伤害'),
        tab*6 + enc('if (ent is Minion) or (ent is JungleMonster and ent.display_name not in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]):'),
        tab*7 + enc('if ent.health < ent.max_health * 0.15:'),
        tab*8 + enc('ent.take_damage(99999, hero, false, 2, 1.0)'),
        tab*8 + enc('continue'),
        tab*6 + enc('# 史诗野怪：25%→50%额外伤害'),
        tab*6 + enc('if ent is JungleMonster and ent.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:'),
        tab*7 + enc('var bonus = 0.25 + 0.05*(level-1)'),
        tab*7 + enc('ent.take_damage(int(w_dmg * (1.0 + bonus)), hero, false, 2, 0)'),
        tab*6 + enc('else:'),
        tab*7 + enc('ent.take_damage(w_dmg, hero, false, 2, 0)'),
        tab*4 + enc('if hit_enemy:'),
        tab*5 + enc('hero.apply_slow(1.0, -0.9)'),
        tab*4 + enc('hero.sunwukong_enhanced_aa = true'),
        tab*3 + enc('3:  # 如意金箍：预览圈+延时 → AoE 4.0 击飞1秒 + 3层印记6秒'),
        tab*4 + enc('var r_preview = create_preview(4.0, hero.global_position, hero.team)'),
        tab*4 + enc('r_preview.visible = true'),
        tab*4 + enc('hero.get_parent().add_child(r_preview)'),
        tab*4 + enc('await hero.get_tree().create_timer(0.3).timeout'),
        tab*4 + enc('var r_dmg = int(250 + 125*(level-1) + hero.bonus_attack * 0.8)'),
        tab*4 + enc('for ent in hero.get_tree().get_nodes_in_group("entities"):'),
        tab*5 + enc('if ent == hero or ent.health <= 0 or ent.team == hero.team: continue'),
        tab*5 + enc('var dist = hero.global_position.distance_to(ent.global_position)'),
        tab*5 + enc('if dist <= 4.0:'),
        tab*6 + enc('ent.take_damage(r_dmg, hero, false, 3, 0)'),
        tab*6 + enc('ent.knockup_timer = max(ent.knockup_timer, 1.0)'),
        tab*6 + enc('for _j in range(3):'),
        tab*7 + enc('ent.markers.append({"timer": 6.0, "source": hero, "type": "sunwukong_r"})'),
        tab*4 + enc('if is_instance_valid(r_preview): r_preview.queue_free()'),
        tab*4 + enc('hero.sunwukong_enhanced_aa = true'),
        le,  # blank line after
    ]
    apply_block = le.join(apply_parts)
    data = data[:insert_pos] + apply_block + data[insert_pos:]
    print("[OK] PART B: apply_skills added")
    fixed += 1
else:
    print(f"[FAIL] PART B: count={data.count(old_b)}")
    # Debug: try to find just the apply_slow line
    idx2 = data.find(enc('ent.apply_slow(0.5, _slow_pct)'))
    if idx2 >= 0:
        # Count tabs before it
        lstart = data.rfind(le, 0, idx2) + len(le)
        tcount = 0
        while idx2 > lstart and data[lstart + tcount:lstart + tcount + 1] == tab:
            tcount += 1
        print(f"  ent.apply_slow at {idx2}, {tcount} tabs before")

with open(path, 'wb') as f:
    f.write(data)

print(f"\n=== Done: {fixed}/2 parts added ===")
