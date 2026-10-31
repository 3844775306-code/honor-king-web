"""Add Sun Wukong mechanics to Hero.gd — 6 insertion points."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "Hero.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'
fixed = 0

# Helper: join lines with CRLF
def lines(*args):
    return le.join(enc(s) for s in args) + le

# === FIX 1: Add flags after var liushan_q_timer ===
old1 = b'var liushan_q_timer: float = 0.0' + le
if data.count(old1) == 1:
    wukong_flags = lines(
        '# 孙悟空',
        'var sunwukong_enhanced_aa: bool = false',
        'var sunwukong_1_block_active: bool = false',
        'var sunwukong_1_block_timer: float = 0.0',
    )
    insert1 = data.find(old1) + len(old1)
    data = data[:insert1] + wukong_flags + data[insert1:]
    print("[OK] FIX 1: flags added")
    fixed += 1
else:
    print(f"[FAIL] FIX 1: count={data.count(old1)}")

# === FIX 2: Innate crit override after base_crit_damage = 1.85 ===
old2 = b'base_crit_damage = 1.85' + le
if data.count(old2) == 1:
    wukong_crit = lines(
        '\tif display_name == "孙悟空":',
        '\t\tbase_crit_chance = 0.20',
        '\t\tbase_crit_damage = 1.50',
    )
    insert2 = data.find(old2) + len(old2)
    data = data[:insert2] + wukong_crit + data[insert2:]
    print("[OK] FIX 2: crit override added")
    fixed += 1
else:
    print(f"[FAIL] FIX 2: count={data.count(old2)}")

# === FIX 3: Block in take_damage after wd_timer check ===
old3 = b'if wd_timer>0:' + le + b'\t\treturn' + le
if data.count(old3) == 1:
    wukong_block = lines(
        '\t# 孙悟空1技能：格挡一次敌方技能',
        '\tif sunwukong_1_block_active and skill_id > 0 and source != null and is_instance_valid(source) and source.team != team:',
        '\t\tsunwukong_1_block_active = false',
        '\t\twd_timer = 0.2',
        '\t\tvar _sh_bonus_hp = actual_max_health - max_health',
        '\t\tvar _shield_val = int(500 + 100*(skill_levels[0]-1) + 1.5*bonus_attack + 0.15*_sh_bonus_hp)',
        '\t\tshield_remaining = max(shield_remaining, _shield_val)',
        '\t\tshield_timer = 4.0',
        '\t\treturn',
    )
    insert3 = data.find(old3) + len(old3)
    data = data[:insert3] + wukong_block + data[insert3:]
    print("[OK] FIX 3: block check added")
    fixed += 1
else:
    print(f"[FAIL] FIX 3: count={data.count(old3)}")

# === FIX 4: Force-crit after is_crit roll ===
old4 = b'var is_crit = randf() < actual_crit_chance' + le
if data.count(old4) == 1:
    wukong_force_crit = lines(
        '\t# 孙悟空被动：强化普攻必定暴击',
        '\tif display_name == "孙悟空" and sunwukong_enhanced_aa:',
        '\t\tis_crit = true',
    )
    insert4 = data.find(old4) + len(old4)
    data = data[:insert4] + wukong_force_crit + data[insert4:]
    print("[OK] FIX 4: force-crit added")
    fixed += 1
else:
    print(f"[FAIL] FIX 4: count={data.count(old4)}")

# === FIX 5: Enhanced AA + mark consumption in melee branch ===
# Pattern: else:\r\n\t\t\r\n\t\tif display_name == "铠":
old5 = b'else:' + le + b'\t\t' + le + enc('\t\tif display_name == "铠":')
if data.count(old5) == 1:
    # Build the replacement: the entire else: ... if display_name == "铠":
    parts = [
        'else:',
        '\t# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）',
        '\tif display_name == "孙悟空" and sunwukong_enhanced_aa:',
        '\t\tsunwukong_enhanced_aa = false',
        '\t\tdmg = 475 + actual_attack_damage',
        '\t\tif is_instance_valid(target) and target.health > 0:',
        '\t\t\tglobal_position = target.global_position',
        '\t\t# R印记消耗',
        '\t\tfor _mi in range(target.markers.size() - 1, -1, -1):',
        '\t\t\tif target.markers[_mi].get("type") == "sunwukong_r" and target.markers[_mi].get("source") == self:',
        '\t\t\t\tvar _mark_dmg = int(200 + 100*(skill_levels[2]-1) + bonus_attack * 0.65)',
        '\t\t\t\ttarget.take_damage(_mark_dmg, self, false, -3, 0)',
        '\t\t\t\ttarget.markers.remove_at(_mi)',
        '\t\t\t\tbreak',
        '',  # blank line
        '\t\tif display_name == "铠":',
    ]
    wukong_melee = le.join(enc(p) for p in parts)
    data = data.replace(old5, wukong_melee, 1)
    print("[OK] FIX 5: enhanced AA + mark consumption added")
    fixed += 1
else:
    print(f"[FAIL] FIX 5: count={data.count(old5)}")

# === FIX 6: Model map ===
old6 = enc('"刘禅"') + b':     ["res://model/hero/character-male-b.glb", ""],' + le
if data.count(old6) == 1:
    wukong_model = enc('"孙悟空": ["res://model/hero/character-male-a.glb", ""],') + le
    insert6 = data.find(old6)
    data = data[:insert6] + wukong_model + data[insert6:]
    print("[OK] FIX 6: model map added")
    fixed += 1
else:
    print(f"[FAIL] FIX 6: count={data.count(old6)}")

with open(path, 'wb') as f:
    f.write(data)

print(f"\n=== Done: {fixed}/6 fixes applied ===")
