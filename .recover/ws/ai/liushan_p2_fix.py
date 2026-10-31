"""Fix Bullet.gd turret override — correct tab indentation."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "Bullet.gd")

with open(path, 'rb') as f:
    data = f.read()

# Exact pattern from grep: \t\tif target is Turret...\r\n\t\t\tpass
old = b'\t\tif target is Turret and skill_id >0:\r\n\t\t\tpass'

idx = data.find(old)
if idx >= 0:
    new = (
        b'\t\tif target is Turret and skill_id >0:\r\n'
        b'\t\t\tif source.display_name == "\xe5\x88\x98\xe7\xa6\x85":\r\n'
        b'\t\t\t\t# \xe8\xa2\xab\xe5\x8a\xa8\xef\xbc\x9a\xe6\x8a\x80\xe8\x83\xbd\xe5\xaf\xb9\xe9\x98\xb2\xe5\xbe\xa1\xe5\xa1\x94\xe7\xad\x89\xe9\x87\x8f\xe4\xbc\xa4\xe5\xae\xb3+\xe5\xb9\xb2\xe6\x89\xb0+\xe5\x9b\x9e\xe8\xa1\x80\r\n'
        b'\t\t\t\ttarget.take_damage(damage, source, is_magic, skill_id, pen_percent)\r\n'
        b'\t\t\t\tif stun_dur > 0 or knock_dur > 0:\r\n'
        b'\t\t\t\t\ttarget.interfere_timer = max(target.interfere_timer, 1.2)\r\n'
        b'\t\t\t\tsource.health = min(source.health + 280, source.actual_max_health)\r\n'
        b'\t\t\t\ttarget.apply_slow(slow_dur, slow_per)\r\n'
        b'\t\t\t\tcheck_transfer()\r\n'
        b'\t\t\t\treturn\r\n'
        b'\t\t\tpass'
    )
    data = data.replace(old, new, 1)
    print(f"[OK] Bullet.gd: turret override added at offset {idx}")
else:
    # Try LF variant
    old2 = b'\t\tif target is Turret and skill_id >0:\n\t\t\tpass'
    idx2 = data.find(old2)
    if idx2 >= 0:
        new2 = (
            b'\t\tif target is Turret and skill_id >0:\n'
            b'\t\t\tif source.display_name == "\xe5\x88\x98\xe7\xa6\x85":\n'
            b'\t\t\t\t# \xe8\xa2\xab\xe5\x8a\xa8\xef\xbc\x9a\xe6\x8a\x80\xe8\x83\xbd\xe5\xaf\xb9\xe9\x98\xb2\xe5\xbe\xa1\xe5\xa1\x94\xe7\xad\x89\xe9\x87\x8f\xe4\xbc\xa4\xe5\xae\xb3+\xe5\xb9\xb2\xe6\x89\xb0+\xe5\x9b\x9e\xe8\xa1\x80\n'
            b'\t\t\t\ttarget.take_damage(damage, source, is_magic, skill_id, pen_percent)\n'
            b'\t\t\t\tif stun_dur > 0 or knock_dur > 0:\n'
            b'\t\t\t\t\ttarget.interfere_timer = max(target.interfere_timer, 1.2)\n'
            b'\t\t\t\tsource.health = min(source.health + 280, source.actual_max_health)\n'
            b'\t\t\t\ttarget.apply_slow(slow_dur, slow_per)\n'
            b'\t\t\t\tcheck_transfer()\n'
            b'\t\t\t\treturn\n'
            b'\t\t\tpass'
        )
        data = data.replace(old2, new2, 1)
        print(f"[OK] Bullet.gd: turret override added (LF) at offset {idx2}")
    else:
        print("[FAIL] Bullet.gd: pattern not found")

with open(path, 'wb') as f:
    f.write(data)

print("Done")
