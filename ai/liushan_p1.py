"""Implement Liu Shan (刘禅) - Phase 1. Uses runtime encoding for Chinese chars."""
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
# FILE 1: Turret.gd - Add interfere_timer
# ================================================================
path = os.path.join(BASE, "scripts", "entities", "Turret.gd")
data = rb(path)

old = b'var tower_type: String = "outer"        # outer/inner/high\nvar tower_shield: float = 0.0'
new = b'var tower_type: String = "outer"        # outer/inner/high\nvar interfere_timer: float = 0.0\nvar tower_shield: float = 0.0'
data = data.replace(old, new, 1)
print("[OK] Turret.gd: interfere_timer variable added")

old2 = b'if health <= 0: return\n\tif attack_timer > 0: attack_timer -= delta'
new2 = b'if health <= 0: return\n\tif interfere_timer > 0:\n\t\tinterfere_timer -= delta\n\t\treturn\n\tif attack_timer > 0: attack_timer -= delta'
data = data.replace(old2, new2, 1)
print("[OK] Turret.gd: interfere_timer gate added")

wb(path, data)

# ================================================================
# FILE 2: BattleManager.gd - Hero registration
# ================================================================
path = os.path.join(BASE, "scripts", "core", "BattleManager.gd")
data = rb(path)

# Add to valid_heroes - find by the closing bracket after 王昭君
wzj_bytes = enc("王昭君")
idx = data.find(wzj_bytes)
if idx >= 0:
    # Find the ] after this entry
    end_idx = data.find(b']', idx)
    if end_idx >= 0:
        data = data[:end_idx] + enc(', "刘禅"') + data[end_idx:]
        print("[OK] BattleManager.gd: valid_heroes updated")
    else:
        print("[FAIL] BattleManager.gd: closing bracket")
else:
    print("[FAIL] BattleManager.gd: 王昭君 in valid_heroes")

# Add hero_config after 王昭君's config block
wzj_config = enc('"name": "王昭君"')
wzj_idx = data.find(wzj_config)
if wzj_idx >= 0:
    brace = data.find(b'\n\t},', wzj_idx)
    if brace >= 0:
        brace += 4  # after \n\t},
        cfg = enc(
            '\n\t"刘禅": {\n'
            '\t\t"name": "刘禅", "role": "辅助",\n'
            '\t\t"max_health": 3539, "attack": 180, "attack_range": 325,\n'
            '\t\t"move_speed": 375, "max_mana": 600,\n'
            '\t\t"armor": 150, "magic_resist": 75,\n'
            '\t\t"skills": ["liushan_q", "liushan_w", "liushan_r"], "summoner": "flash",\n'
            '\t\t"hp_reg": 84, "mana_reg": 15\n'
            '\t},'
        )
        data = data[:brace] + cfg + data[brace:]
        print("[OK] BattleManager.gd: hero_config added")
    else:
        print("[FAIL] BattleManager.gd: closing brace")
else:
    print("[FAIL] BattleManager.gd: 王昭君 config")

wb(path, data)

# ================================================================
# FILE 3: Hero.gd - Model map + flag + _perform_attack
# ================================================================
path = os.path.join(BASE, "scripts", "entities", "Hero.gd")
data = rb(path)

# A. Add HERO_MODEL_MAP entry after 王昭君
wzj_model = data.find(enc("王昭君"))
if wzj_model >= 0:
    eol = data.find(b'\n', wzj_model)
    if eol >= 0:
        eol += 1
        new_line = enc('\t"刘禅":     ["res://model/hero/character-male-b.glb", ""],\n')
        data = data[:eol] + new_line + data[eol:]
        print("[OK] Hero.gd: HERO_MODEL_MAP entry added")
    else:
        print("[FAIL] Hero.gd: newline after model")
else:
    print("[FAIL] Hero.gd: 王昭君 model map")

# B. Add liushan_q_active/timer flag after arthur_q_timer
art_timer = data.find(b'var arthur_q_timer: float = 0.0\n')
if art_timer >= 0:
    insert_at = art_timer + len(b'var arthur_q_timer: float = 0.0\n')
    flag_block = enc('\t# 刘禅\n\tvar liushan_q_active: bool = false\n\tvar liushan_q_timer: float = 0.0\n\t')
    data = data[:insert_at] + flag_block + data[insert_at:]
    print("[OK] Hero.gd: liushan_q_active flag added")
else:
    print("[FAIL] Hero.gd: arthur_q_timer")

# C. Add enhanced AA consumption in _perform_attack
# Find the Arthur marker append and insert Liu Shan block after it
arthur_marker = data.find(b'"timer": 5.0, "source": self})\n')
if arthur_marker >= 0:
    insert_at = arthur_marker + len(b'"timer": 5.0, "source": self})\n')
    ls_block = enc(
        '\t\t# 刘禅Q：强化普攻(击飞+额外伤害)\n'
        '\t\tif display_name == "刘禅":\n'
        '\t\t\tif liushan_q_active:\n'
        '\t\t\t\tliushan_q_active = false\n'
        '\t\t\t\tdmg += int(300 + 50 * skill_levels[0] + 1.22 * actual_attack_damage)\n'
        '\t\t\t\tif target is Turret:\n'
        '\t\t\t\t\ttarget.interfere_timer = max(target.interfere_timer, 1.2)\n'
        '\t\t\t\t\thealth = min(health + 280, actual_max_health)\n'
        '\t\t\t\telse:\n'
        '\t\t\t\t\ttarget.knockup_timer = max(target.knockup_timer, 1.0)\n'
    )
    data = data[:insert_at] + ls_block + data[insert_at:]
    print("[OK] Hero.gd: _perform_attack enhanced AA added")
else:
    print("[FAIL] Hero.gd: arthur marker append")

wb(path, data)

# ================================================================
# FILE 4: HeroPassive.gd - Q timer decay
# ================================================================
path = os.path.join(BASE, "scripts", "entities", "HeroPassive.gd")
data = rb(path)

# Find Arthur Q timer block and insert after it
art_q_timer = data.find(b'if hero.arthur_q_active:\n\t\t\thero.arthur_q_timer -= delta\n\t\t\tif hero.arthur_q_timer <= 0: hero.arthur_q_active = false')
if art_q_timer >= 0:
    insert_at = art_q_timer + len(b'if hero.arthur_q_active:\n\t\t\thero.arthur_q_timer -= delta\n\t\t\tif hero.arthur_q_timer <= 0: hero.arthur_q_active = false')
    ls_timer = enc(
        '\n\t\t# 刘禅Q：强化普攻定时器\n'
        '\t\tif hero.liushan_q_active:\n'
        '\t\t\thero.liushan_q_timer -= delta\n'
        '\t\t\tif hero.liushan_q_timer <= 0: hero.liushan_q_active = false'
    )
    data = data[:insert_at] + ls_timer + data[insert_at:]
    print("[OK] HeroPassive.gd: Q timer decay added")
else:
    print("[FAIL] HeroPassive.gd: Arthur Q timer pattern")

wb(path, data)

print("\n=== Phase 1/2 complete ===")
