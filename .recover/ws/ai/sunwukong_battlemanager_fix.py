"""Add Sun Wukong to BattleManager.gd — fix hero_config insertion."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "core", "BattleManager.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

le = b'\r\n'  # CRLF

# Pattern: 刘禅 closing brace + hero_configs closing brace
# \t\t\t},\r\n}\r\n\r\nfunc _show_hero_select_ui
old = b'\t\t\t},' + le + b'}' + le + le + b'func _show_hero_select_ui'

if data.count(old) == 1:
    wukong_entry = (
        le +
        enc('\t"孙悟空": {') + le +
        enc('\t\t"name": "孙悟空", "role": "刺客",') + le +
        enc('\t\t"max_health": 3334, "attack": 173, "attack_range": 325,') + le +
        enc('\t\t"move_speed": 385, "max_mana": 560,') + le +
        enc('\t\t"armor": 150, "magic_resist": 75,') + le +
        enc('\t\t"skills": ["sunwukong_q", "sunwukong_w", "sunwukong_r"], "summoner": "smite",') + le +
        enc('\t\t"hp_reg": 50, "mana_reg": 14') + le +
        enc('\t\t\t},')
    )
    new = b'\t\t\t},' + le + wukong_entry + le + b'}' + le + le + b'func _show_hero_select_ui'
    data = data.replace(old, new, 1)
    print("[OK] FIX 2: hero_config entry added")
else:
    print(f"[FAIL] FIX 2: pattern count = {data.count(old)}")
    # Debug: try variant patterns
    for test in [
        b'\t\t\t},' + le + b'}',
        b'mana_reg": 15' + le + b'\t\t\t},',
    ]:
        print(f'  {test!r}: count={data.count(test)}')

with open(path, 'wb') as f:
    f.write(data)

print("Done")
