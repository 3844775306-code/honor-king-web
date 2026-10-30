"""Fix BattleManager.gd and HeroPassive.gd — CRLF files."""
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
# BattleManager.gd — Fix hero_config insertion (CRLF file)
# ================================================================
path = os.path.join(BASE, "scripts", "core", "BattleManager.gd")
data = rb(path)

name_wzj = b'"name": "\xe7\x8e\x8b\xe6\x98\xad\xe5\x90\x9b"'
idx = data.find(name_wzj)
if idx >= 0:
    # The config entry closes with \r\n\t\t\t},
    # Find the closing of 王昭君's entry
    close_pattern = b'\r\n\t\t\t},'
    brace = data.find(close_pattern, idx)
    if brace >= 0:
        insert_at = brace + len(close_pattern)
        cfg = enc(
            '\r\n\t"刘禅": {\r\n'
            '\t\t"name": "刘禅", "role": "辅助",\r\n'
            '\t\t"max_health": 3539, "attack": 180, "attack_range": 325,\r\n'
            '\t\t"move_speed": 375, "max_mana": 600,\r\n'
            '\t\t"armor": 150, "magic_resist": 75,\r\n'
            '\t\t"skills": ["liushan_q", "liushan_w", "liushan_r"], "summoner": "flash",\r\n'
            '\t\t"hp_reg": 84, "mana_reg": 15\r\n'
            '\t\t\t},'
        )
        data = data[:insert_at] + cfg + data[insert_at:]
        print("[OK] BattleManager.gd: hero_config added (CRLF)")
    else:
        print("[FAIL] BattleManager.gd: closing brace pattern")
else:
    print("[FAIL] BattleManager.gd: 王昭君 config name")

wb(path, data)

# ================================================================
# HeroPassive.gd — Fix Q timer decay (CRLF file)
# ================================================================
path = os.path.join(BASE, "scripts", "entities", "HeroPassive.gd")
data = rb(path)

# Pattern with CRLF
art_q_timer = data.find(b'if hero.arthur_q_active:\r\n\t\t\thero.arthur_q_timer -= delta\r\n\t\t\tif hero.arthur_q_timer <= 0: hero.arthur_q_active = false')
if art_q_timer >= 0:
    insert_at = art_q_timer + len(b'if hero.arthur_q_active:\r\n\t\t\thero.arthur_q_timer -= delta\r\n\t\t\tif hero.arthur_q_timer <= 0: hero.arthur_q_active = false')
    ls_timer = enc(
        '\r\n\t\t# 刘禅Q：强化普攻定时器\r\n'
        '\t\tif hero.liushan_q_active:\r\n'
        '\t\t\thero.liushan_q_timer -= delta\r\n'
        '\t\t\tif hero.liushan_q_timer <= 0: hero.liushan_q_active = false'
    )
    data = data[:insert_at] + ls_timer + data[insert_at:]
    print("[OK] HeroPassive.gd: Q timer decay added (CRLF)")
else:
    print("[FAIL] HeroPassive.gd: Arthur Q timer pattern (CRLF)")

wb(path, data)

print("\n=== Fixes applied ===")
