"""Implement Liu Shan (刘禅) - Phase 2: SkillDataBase.gd + Bullet.gd."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"

def rb(path):
    with open(path, 'rb') as f:
        return f.read()

def wb(path, data):
    with open(path, 'wb') as f:
        f.write(data)

def enc(s):
    return s.encode('utf-8')

# ================================================================
# FILE 5: SkillDataBase.gd — Skill definitions + apply_skills
# ================================================================
path = os.path.join(BASE, "assets", "SkillDataBase.gd")
data = rb(path)

# A. Insert skill definitions after 王昭君's R (before 召唤师技能 section)
insert_after = b'skills["wangzhaojun_r"] = sk\r\n\r\n'
idx = data.find(insert_after)
if idx >= 0:
    insert_at = idx + len(insert_after)
    skill_defs = enc(
        '\t# ==================== 刘禅 ====================\r\n'
        '\tsk = Skill.new()\r\n'
        '\tsk.skill_name = "小霸王护盾"; sk.cooldown = 9.0; sk.mana_cost = 50\r\n'
        '\tsk.cd_bonus = 0.4; sk.type = 2; sk.cast_time = 0.15\r\n'
        '\tskills["liushan_q"] = sk\r\n'
        '\r\n'
        '\tsk = Skill.new()\r\n'
        '\tsk.skill_name = "机关魔爪"; sk.cooldown = 7.5; sk.mana_cost = 40\r\n'
        '\tsk.cd_bonus = 0.3; sk.type = 1; sk.radius = 2.0; sk.cast_range = 3.0; sk.cast_time = 0.2\r\n'
        '\tskills["liushan_w"] = sk\r\n'
        '\r\n'
        '\tsk = Skill.new()\r\n'
        '\tsk.skill_name = "暴走熊猫"; sk.cooldown = 40.0; sk.mana_cost = 100\r\n'
        '\tsk.cd_bonus = 5.0; sk.type = 2; sk.radius = 4.0; sk.cast_time = 0.2\r\n'
        '\tskills["liushan_r"] = sk\r\n'
        '\r\n'
    )
    data = data[:insert_at] + skill_defs + data[insert_at:]
    print("[OK] SkillDataBase.gd: skill definitions added")
else:
    print("[FAIL] SkillDataBase.gd: wangzhaojun_r insert point")

# B. Insert apply_skills block at end of match (after 王昭君 case 3, before match closes)
insert_after2 = b'\t\tw3_zone.queue_free()\r\n\r\n'
# But there might be multiple occurrences — find the one near offset 59100
idx2 = data.find(insert_after2, 58000)
if idx2 >= 0:
    insert_at2 = idx2 + len(b'\t\tw3_zone.queue_free()\r\n')
    apply_block = enc(
        '\r\n'
        '\t\t"刘禅":match  skill_id:\r\n'
        '\t\t\t1:  # 小霸王护盾：护盾+加速+强化普攻\r\n'
        '\t\t\t\tvar _bonus_hp = hero.actual_max_health - hero.max_health\r\n'
        '\t\t\t\tvar _shield_amt = int(520 + 130*level + 0.14*_bonus_hp)\r\n'
        '\t\t\t\thero.shield_remaining = max(hero.shield_remaining, _shield_amt)\r\n'
        '\t\t\t\thero.shield_timer = 3.0\r\n'
        '\t\t\t\tvar _speed_boost = 0.4 + 0.1*level\r\n'
        '\t\t\t\thero.apply_slow(3.0, -_speed_boost)\r\n'
        '\t\t\t\thero.liushan_q_active = true\r\n'
        '\t\t\t\thero.liushan_q_timer = 3.0\r\n'
        '\t\t\t2:  # 机关魔爪：AoE伤害+眩晕\r\n'
        '\t\t\t\tvar w2_preview = create_preview(2.0, pos, hero.team)\r\n'
        '\t\t\t\tw2_preview.visible = true\r\n'
        '\t\t\t\thero.get_parent().add_child(w2_preview)\r\n'
        '\t\t\t\tawait hero.get_tree().create_timer(0.35).timeout\r\n'
        '\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\r\n'
        '\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\r\n'
        '\t\t\t\tvar w2_bullet = create_bullet(int(320+80*level),1.0,0,0,false,hero,dir,2)\r\n'
        '\t\t\t\tw2_bullet.damage_range = 2.0\r\n'
        '\t\t\t\tw2_bullet.stun_dur = 1.0\r\n'
        '\t\t\t\tw2_bullet.speed = 15.0\r\n'
        '\t\t\t\tw2_bullet.set_goal(pos)\r\n'
        '\t\t\t\thero.get_parent().add_child(w2_bullet)\r\n'
        '\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\r\n'
        '\t\t\t\tif is_instance_valid(w2_preview): w2_preview.queue_free()\r\n'
        '\t\t\t3:  # 暴走熊猫：3秒旋转AoE+减速\r\n'
        '\t\t\t\tfor _tick in range(6):\r\n'
        '\t\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\r\n'
        '\t\t\t\t\tif hero.health <= 0: break\r\n'
        '\t\t\t\t\tvar _bonus_ad = hero.bonus_attack\r\n'
        '\t\t\t\t\tvar _tick_dmg = int(190 + 190*level + 1.1*_bonus_ad)\r\n'
        '\t\t\t\t\tvar _slow_pct = 0.075 + 0.075*level\r\n'
        '\t\t\t\t\tfor ent in hero.get_tree().get_nodes_in_group("entities"):\r\n'
        '\t\t\t\t\t\tif ent == hero or ent.health <= 0 or ent.team == hero.team: continue\r\n'
        '\t\t\t\t\t\tvar _dist = hero.global_position.distance_to(ent.global_position)\r\n'
        '\t\t\t\t\t\tif _dist <= 4.0:\r\n'
        '\t\t\t\t\t\t\tif ent is Turret:\r\n'
        '\t\t\t\t\t\t\t\tent.take_damage(_tick_dmg, hero, false, -3, 0)\r\n'
        '\t\t\t\t\t\t\t\tent.interfere_timer = max(ent.interfere_timer, 1.2)\r\n'
        '\t\t\t\t\t\t\t\thero.health = min(hero.health + 280, hero.actual_max_health)\r\n'
        '\t\t\t\t\t\t\telse:\r\n'
        '\t\t\t\t\t\t\t\tent.take_damage(_tick_dmg, hero, false, 3, 0)\r\n'
        '\t\t\t\t\t\t\tent.apply_slow(0.5, _slow_pct)\r\n'
        '\r\n'
    )
    data = data[:insert_at2] + apply_block + data[insert_at2:]
    print("[OK] SkillDataBase.gd: apply_skills block added")
else:
    print("[FAIL] SkillDataBase.gd: w3_zone.queue_free insert point")

wb(path, data)

# ================================================================
# FILE 6: Bullet.gd — Turret interaction override
# ================================================================
path = os.path.join(BASE, "scripts", "entities", "Bullet.gd")
data = rb(path)

# Find the turret pass block
# Pattern: if target is Turret and skill_id >0:\n\t\t\t\tpass
old_pat = b'if target is Turret and skill_id >0:\n\t\t\t\tpass'
idx = data.find(old_pat)
if idx >= 0:
    new_block = (
        b'if target is Turret and skill_id >0:\n'
        b'\t\t\t\tif source.display_name == "\xe5\x88\x98\xe7\xa6\x85":\n'
        b'\t\t\t\t\t# \xe8\xa2\xab\xe5\x8a\xa8\xef\xbc\x9a\xe6\x8a\x80\xe8\x83\xbd\xe5\xaf\xb9\xe9\x98\xb2\xe5\xbe\xa1\xe5\xa1\x94\xe7\xad\x89\xe9\x87\x8f\xe4\xbc\xa4\xe5\xae\xb3+\xe5\xb9\xb2\xe6\x89\xb0+\xe5\x9b\x9e\xe8\xa1\x80\n'
        b'\t\t\t\t\ttarget.take_damage(damage, source, is_magic, skill_id, pen_percent)\n'
        b'\t\t\t\t\tif stun_dur > 0 or knock_dur > 0:\n'
        b'\t\t\t\t\t\ttarget.interfere_timer = max(target.interfere_timer, 1.2)\n'
        b'\t\t\t\t\tsource.health = min(source.health + 280, source.actual_max_health)\n'
        b'\t\t\t\t\ttarget.apply_slow(slow_dur, slow_per)\n'
        b'\t\t\t\t\tcheck_transfer()\n'
        b'\t\t\t\t\treturn\n'
        b'\t\t\t\tpass'
    )
    data = data.replace(old_pat, new_block, 1)
    print("[OK] Bullet.gd: turret override added")
else:
    # Try CRLF
    old_pat2 = b'if target is Turret and skill_id >0:\r\n\t\t\t\tpass'
    idx2 = data.find(old_pat2)
    if idx2 >= 0:
        new_block2 = (
            b'if target is Turret and skill_id >0:\r\n'
            b'\t\t\t\tif source.display_name == "\xe5\x88\x98\xe7\xa6\x85":\r\n'
            b'\t\t\t\t\t# \xe8\xa2\xab\xe5\x8a\xa8\xef\xbc\x9a\xe6\x8a\x80\xe8\x83\xbd\xe5\xaf\xb9\xe9\x98\xb2\xe5\xbe\xa1\xe5\xa1\x94\xe7\xad\x89\xe9\x87\x8f\xe4\xbc\xa4\xe5\xae\xb3+\xe5\xb9\xb2\xe6\x89\xb0+\xe5\x9b\x9e\xe8\xa1\x80\r\n'
            b'\t\t\t\t\ttarget.take_damage(damage, source, is_magic, skill_id, pen_percent)\r\n'
            b'\t\t\t\t\tif stun_dur > 0 or knock_dur > 0:\r\n'
            b'\t\t\t\t\t\ttarget.interfere_timer = max(target.interfere_timer, 1.2)\r\n'
            b'\t\t\t\t\tsource.health = min(source.health + 280, source.actual_max_health)\r\n'
            b'\t\t\t\t\ttarget.apply_slow(slow_dur, slow_per)\r\n'
            b'\t\t\t\t\tcheck_transfer()\r\n'
            b'\t\t\t\t\treturn\r\n'
            b'\t\t\t\tpass'
        )
        data = data.replace(old_pat2, new_block2, 1)
        print("[OK] Bullet.gd: turret override added (CRLF)")
    else:
        print("[FAIL] Bullet.gd: turret pass pattern not found (tried LF and CRLF)")
        # Debug: show the area around line 238
        lb = data.find(b'Turret and skill_id')
        if lb >= 0:
            print(f"  Found 'Turret and skill_id' at {lb}: {repr(data[lb:lb+50])}")

wb(path, data)

print("\n=== Phase 2/2 complete ===")
