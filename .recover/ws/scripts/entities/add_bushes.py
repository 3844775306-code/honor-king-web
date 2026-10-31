import math

# Mid-lane direction: (1, 0, -1) normalized
dx = 1.0 / math.sqrt(2)  # ≈ 0.7071
dz = -1.0 / math.sqrt(2) # ≈ -0.7071
step = 1.0

# Cluster 1: center (-55, 0, -55), 11 bushes
top_left_11 = []
for i in range(-5, 6):
    x = round(-55 + i * step * dx, 2)
    z = round(-55 + i * step * dz, 2)
    top_left_11.append((x, z))

# Cluster 2: center (-40, 0, -40), 7 bushes
top_left_7 = []
for i in range(-3, 4):
    x = round(-40 + i * step * dx, 2)
    z = round(-40 + i * step * dz, 2)
    top_left_7.append((x, z))

# Center-symmetry through origin: (x,z) → (-x,-z)
bot_right_11 = [(-x, -z) for x, z in top_left_11]
bot_right_7 = [(-x, -z) for x, z in top_left_7]

print("=== 左上角 (-55,0,-55) 11个草丛 ===")
for x, z in top_left_11:
    print(f"\t\tVector3({x}, 0, {z}),")

print("=== 左上角 (-40,0,-40) 7个草丛 ===")
for x, z in top_left_7:
    print(f"\t\tVector3({x}, 0, {z}),")

print("=== 右下角 (55,0,55) 11个草丛（中心对称） ===")
for x, z in bot_right_11:
    print(f"\t\tVector3({x}, 0, {z}),")

print("=== 右下角 (40,0,40) 7个草丛（中心对称） ===")
for x, z in bot_right_7:
    print(f"\t\tVector3({x}, 0, {z}),")

# Build the insertion string
insert_lines = []
insert_lines.append('\t\t# ==== 左上角中路方向草丛（-55,-55中心，11个） ====')
for x, z in top_left_11:
    insert_lines.append(f'\t\tVector3({x}, 0, {z}),')
insert_lines.append('\t\t# ==== 左上角中路方向草丛（-40,-40中心，7个） ====')
for x, z in top_left_7:
    insert_lines.append(f'\t\tVector3({x}, 0, {z}),')
insert_lines.append('\t\t# ==== 右下角中路方向草丛（55,55中心，11个） ====')
for x, z in bot_right_11:
    insert_lines.append(f'\t\tVector3({x}, 0, {z}),')
insert_lines.append('\t\t# ==== 右下角中路方向草丛（40,40中心，7个） ====')
for x, z in bot_right_7:
    insert_lines.append(f'\t\tVector3({x}, 0, {z}),')

# Now modify BattleManager.gd
import pathlib
path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')

# Find the last Vector3 in the bushes array and insert after it
old = '\t\tVector3(50,0,23),\n\t]'
insert_str = '\n'.join(insert_lines)
new = '\t\tVector3(50,0,23),\n' + insert_str + '\n\t]'

if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text, 'utf-8')
    print('\nSUCCESS: Bushes added to BattleManager.gd')
else:
    print('\nFAILED: Could not find insertion point')
    idx = text.find('Vector3(50,0,23)')
    if idx >= 0:
        print(f'Found at {idx}: {repr(text[idx:idx+50])}')
