"""Add Sun Wukong block timer decay to HeroPassive.gd — LF line endings."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "HeroPassive.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\n'

# Find # 太乙真人 Q 技能引爆 and insert before it
idx = data.find(enc('# 太乙真人 Q 技能引爆'))
if idx >= 0:
    prev_nl = data.rfind(le, 0, idx)
    insert_pos = prev_nl + len(le)

    lines = [
        '\t# 孙悟空1技能：格挡窗口计时',
        '\tif hero.sunwukong_1_block_timer > 0:',
        '\t\thero.sunwukong_1_block_timer -= delta',
        '\t\tif hero.sunwukong_1_block_timer <= 0:',
        '\t\t\thero.sunwukong_1_block_active = false',
        '',  # blank
    ]
    wukong_block = le.join(enc(l) for l in lines)
    data = data[:insert_pos] + wukong_block + data[insert_pos:]
    print(f"[OK] Block timer decay added at {insert_pos}")
else:
    print("[FAIL] Could not find insertion point")

with open(path, 'wb') as f:
    f.write(data)

print("Done")
