"""Add Sun Wukong to BattleManager.gd — valid_heroes + hero_config."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "core", "BattleManager.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'  # CRLF
fixed = 0

# === FIX 1: Append "孙悟空" to valid_heroes ===
# Pattern: 刘禅"] at end of valid_heroes list
old1 = enc('"刘禅"]')
new1 = enc('"刘禅", "孙悟空"]')
if data.count(old1) == 1:
    data = data.replace(old1, new1, 1)
    print("[OK] FIX 1: valid_heroes += 孙悟空")
    fixed += 1
else:
    print(f"[FAIL] FIX 1: pattern count = {data.count(old1)}")

# === FIX 2: Insert hero_config entry before closing "}" of hero_configs ===
# Pattern: 刘禅 entry close: \t\t\t},\r\n\t}  (end of hero_configs dict)
old2 = b'\t\t\t\t},' + le + b'\t}'
if data.count(old2) == 1:
    insert_pos = data.find(old2)
    wukong_config = enc(
        '\t"孙悟空": {' + le +
        '\t\t"name": "孙悟空", "role": "刺客",' + le +
        '\t\t"max_health": 3334, "attack": 173, "attack_range": 325,' + le +
        '\t\t"move_speed": 385, "max_mana": 560,' + le +
        '\t\t"armor": 150, "magic_resist": 75,' + le +
        '\t\t"skills": ["sunwukong_q", "sunwukong_w", "sunwukong_r"], "summoner": "smite",' + le +
        '\t\t"hp_reg": 50, "mana_reg": 14' + le +
        '\t\t\t\t},' + le
    )
    data = data[:insert_pos] + wukong_config + data[insert_pos:]
    print("[OK] FIX 2: hero_config entry added")
    fixed += 1
else:
    # Try alternative: just the 刘禅 closing
    print(f"[FAIL] FIX 2: pattern count = {data.count(old2)}")
    # Let's try to find the exact point
    idx = data.find(enc('"刘禅":'))
    if idx >= 0:
        # Find the closing of 刘禅 entry and the dict close after it
        segment = data[idx:idx+500]
        print(f"  Segment: {segment[:200]!r}")

with open(path, 'wb') as f:
    f.write(data)

print(f"\n=== Done: {fixed}/2 fixes applied ===")
