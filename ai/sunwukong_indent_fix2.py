"""Atomic replacement of the full Wukong else-block with correct indentation."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "Hero.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'
tab = b'\t'

# The corrupted block starts with: \telse:\r\n\t\t# 孙悟空被动...
# and ends with the blank line before Kai check
# Find the exact boundaries

# Pattern: from the last occurrence of "splash_bullet" before Kai
kai_idx = data.find(enc('\t\tif display_name == "铠":'))
if kai_idx < 0:
    print("ERROR: Kai check not found")
    exit(1)

# Find the else: before Kai
else_idx = data[:kai_idx].rfind(b'else:')
if else_idx < 0:
    print("ERROR: else not found")
    exit(1)

# Find the line before else:
prev_nl = data.rfind(le, 0, else_idx)
block_start = prev_nl + len(le)  # start of the "else:" line

print(f"else_idx={else_idx}, kai_idx={kai_idx}, block_start={block_start}")

# Build the CORRECT replacement block
correct_block_lines = [
    # else: body starts here (at 2 tabs = 1 for outer + 1 for else body)
    enc('\telse:'),
    enc('\t\t# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）'),
    enc('\t\tif display_name == "孙悟空" and sunwukong_enhanced_aa:'),
    enc('\t\t\tsunwukong_enhanced_aa = false'),
    enc('\t\t\tdmg = 475 + actual_attack_damage'),
    enc('\t\t\tif is_instance_valid(target) and target.health > 0:'),
    enc('\t\t\t\tglobal_position = target.global_position'),
    enc('\t\t\t# R印记消耗'),
    enc('\t\t\tfor _mi in range(target.markers.size() - 1, -1, -1):'),
    enc('\t\t\t\tif target.markers[_mi].get("type") == "sunwukong_r" and target.markers[_mi].get("source") == self:'),
    enc('\t\t\t\t\tvar _mark_dmg = int(200 + 100*(skill_levels[2]-1) + bonus_attack * 0.65)'),
    enc('\t\t\t\t\ttarget.take_damage(_mark_dmg, self, false, -3, 0)'),
    enc('\t\t\t\t\ttarget.markers.remove_at(_mi)'),
    enc('\t\t\t\t\tbreak'),
    enc(''),  # blank line
    enc('\t\tif display_name == "铠":'),
]

correct_block = le.join(correct_block_lines) + le

# Replace from block_start to the end of the Kai check line
kai_line_end = data.find(le, kai_idx) + len(le)
print(f"Replacing bytes {block_start}-{kai_line_end} ({kai_line_end - block_start} bytes)")

data = data[:block_start] + correct_block + data[kai_line_end:]

with open(path, 'wb') as f:
    f.write(data)

print("Done")
