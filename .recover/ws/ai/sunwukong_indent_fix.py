"""Fix indentation: Wukong code inside else should be +1 tab deeper."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "Hero.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'
tab = b'\t'

# Fix pattern: \telse:\r\n\t# 孙悟空被动...\r\n\tif display_name == "孙悟空"
# Target:     \telse:\r\n\t\t# 孙悟空被动...\r\n\t\tif display_name == "孙悟空"

old_start = b'\telse:' + le + enc('\t# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）')

if data.count(old_start) == 1:
    # Replace the comment with correct indent
    data = data.replace(
        enc('\t# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）'),
        enc('\t\t# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）'),
        1
    )
    # Fix the if line
    data = data.replace(
        enc('\tif display_name == "孙悟空" and sunwukong_enhanced_aa:'),
        enc('\t\tif display_name == "孙悟空" and sunwukong_enhanced_aa:'),
        1
    )
    print("[OK] Comment and if indent fixed")
else:
    print(f"[FAIL] start pattern count={data.count(old_start)}")

# Now fix inner lines (each needs +1 tab)
# Start from the unique context: after the if line, before the Kai check
# These are lines that should shift from current tabs to +1 tab

fixes = [
    # Old indent -> New indent (must be unique in context)
    ('\t\tsunwukong_enhanced_aa = false', '\t\t\tsunwukong_enhanced_aa = false'),
    ('\t\tdmg = 475 + actual_attack_damage', '\t\t\tdmg = 475 + actual_attack_damage'),
    ('\t\tif is_instance_valid(target) and target.health > 0:', '\t\t\tif is_instance_valid(target) and target.health > 0:'),
    ('\t\t\tglobal_position = target.global_position', '\t\t\t\tglobal_position = target.global_position'),
    ('\t\t# R印记消耗', '\t\t\t# R印记消耗'),
    ('\t\tfor _mi in range(target.markers.size() - 1, -1, -1):', '\t\t\tfor _mi in range(target.markers.size() - 1, -1, -1):'),
    ('\t\t\tif target.markers[_mi]', '\t\t\t\tif target.markers[_mi]'),
    ('\t\t\t\tvar _mark_dmg = int(200 + 100*(skill_levels[2]-1) + bonus_attack * 0.65)', '\t\t\t\t\tvar _mark_dmg = int(200 + 100*(skill_levels[2]-1) + bonus_attack * 0.65)'),
    ('\t\t\t\ttarget.take_damage(_mark_dmg, self, false, -3, 0)', '\t\t\t\t\ttarget.take_damage(_mark_dmg, self, false, -3, 0)'),
    ('\t\t\t\ttarget.markers.remove_at(_mi)', '\t\t\t\t\ttarget.markers.remove_at(_mi)'),
]

for old_line, new_line in fixes:
    o = enc(old_line) + le
    n = enc(new_line) + le
    c = data.count(o)
    if c == 1:
        data = data.replace(o, n, 1)
    elif c == 0:
        print(f'  NOT FOUND: {old_line}')
    else:
        print(f'  MULTIPLE ({c}): {old_line}')

# Fix break: there are multiple breaks, so find it in context
# Pattern: .remove_at(_mi)\r\n\t\t\t\tbreak\r\n\r\n\t\tif display_name == "铠":
old_break = enc('\t\t\t\ttarget.markers.remove_at(_mi)') + le + enc('\t\t\t\tbreak') + le + le + enc('\t\tif display_name == "铠":')
if data.count(old_break) == 1:
    new_break = enc('\t\t\t\t\ttarget.markers.remove_at(_mi)') + le + enc('\t\t\t\t\tbreak') + le + le + enc('\t\tif display_name == "铠":')
    data = data.replace(old_break, new_break, 1)
    print("[OK] break indent fixed with context")
else:
    print(f"[FAIL] break context count={data.count(old_break)}")

with open(path, 'wb') as f:
    f.write(data)

print("Done")
