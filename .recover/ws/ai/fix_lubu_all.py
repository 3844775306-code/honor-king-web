"""Comprehensive Lu Bu fix across all files."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"

def rb(path):
    with open(path, 'rb') as f:
        return f.read()

def wb(path, data):
    with open(path, 'wb') as f:
        f.write(data)

# ============================================================
# FILE 1: HeroPassive.gd — Fix passive timer
# ============================================================
path = os.path.join(BASE, "scripts", "entities", "HeroPassive.gd")
data = rb(path)

old = (b'\xe5\x90\x95\xe5\xb8\x83\xef\xbc\x9a\xe8\xa2\xab\xe5\x8a\xa8\xe8\xae\xa1\xe6\x97\xb6\xe5\x99\xa8\n'
       b'\tif hero.display_name == "\xe5\x90\x95\xe5\xb8\x83":\n'
       b'\t\tif hero.stat_timer > 0: \n'
       b'\t\t\thero.stat_timer -= delta\n'
       b'\t\t\thero.stat = 0\n'
       b'\t\telif hero.stat != 0: hero.stat_timer = 6.5\n')

new = (b'\xe5\x90\x95\xe5\xb8\x83\xef\xbc\x9a\xe8\xa2\xab\xe5\x8a\xa8\xe8\xae\xa1\xe6\x97\xb6\xe5\x99\xa8\n'
       b'\tif hero.display_name == "\xe5\x90\x95\xe5\xb8\x83":\n'
       b'\t\tif hero.stat_timer > 0:\n'
       b'\t\t\thero.stat_timer -= delta\n'
       b'\t\t\tif hero.stat_timer <= 0:\n'
       b'\t\t\t\thero.stat = 0\n'
       b'\t\telif hero.stat != 0:\n'
       b'\t\t\thero.stat_timer = 8.0\n')

if old in data:
    data = data.replace(old, new, 1)
    wb(path, data)
    print("[OK] HeroPassive.gd: passive timer fixed (countdown + 8s)")
else:
    print("[FAIL] HeroPassive.gd: pattern not found")

# ============================================================
# FILE 2: Bullet.gd — Fix on_hit(), AoE, check_transfer
# ============================================================
path = os.path.join(BASE, "scripts", "entities", "Bullet.gd")
data = rb(path)

# --- Fix 2a: Remove dead Lu Bu code in check_transfer ---
old_dead = (b'\xe5\x90\x95\xe5\xb8\x83" and skill_id ==1:\n'
            b'\t\t\tsource.health+=280+70*source.skill_levels[1]+0.07*source.max_health\n'
            b'\t\t\tsource.apply_slow(3,-0.12-0.03*source.skill_levels[1])\n'
            b'\t\t\tsource.apply_ak_slow(3,-0.12-0.03*source.skill_levels[1])\n'
            b'\t\t\n'
            b'\t\tlinear_dir=Vector3.ZERO')

# The Kai heal was accidentally attributed to Lu Bu. Remove it, keep the rest.
# After removal, just keep: \t\tlinear_dir=Vector3.ZERO
# But we need to find the exact boundary. Let me check: the line before is
# "elif not pierce:" and after the dead code is "\t\tlinear_dir=Vector3.ZERO"

# Actually, let me find the full context
idx = data.find(b'\xe5\x90\x95\xe5\xb8\x83" and skill_id ==1:')
if idx >= 0:
    # Find the start of this if-block (after "elif not pierce:\n")
    block_start = data.rfind(b'\n', 0, idx) + 1
    # Find where the dead code ends - look for "linear_dir=Vector3.ZERO" after idx
    linear_idx = data.find(b'linear_dir=Vector3.ZERO', idx)
    if linear_idx >= 0:
        # The dead code is from block_start to linear_idx
        dead_block = data[block_start:linear_idx]
        print(f"  Dead code length: {len(dead_block)} bytes")
        # Replace: remove the if block, keep just the newline+tab before linear_dir
        # After "elif not pierce:\n" the dead code starts, and we want to go directly to linear_dir
        # But we need to keep the indentation...
        # Actually the structure is:
        # \t\telif not pierce:\n
        # \t\t\tif source.display_name == "吕布" ...:\n...  <-- DEAD
        # \t\t\t\n
        # \t\t\tlinear_dir=Vector3.ZERO
        # We want:
        # \t\telif not pierce:\n
        # \t\t\tlinear_dir=Vector3.ZERO
        data = data[:block_start] + data[linear_idx:]
        wb(path, data)
        print("[OK] Bullet.gd: dead check_transfer Lu Bu code removed")
    else:
        print("[FAIL] Bullet.gd: linear_dir not found after dead code")

# Re-read for next fixes
data = rb(path)

# --- Fix 2b: on_hit() Lu Bu block ---
old_onhit = (b'\xe5\x90\x95\xe5\xb8\x83":\n'
             b'\t\t\t\tif  skill_id>0:\n'
             b'\t\t\t\t\tif skill_id == 2:\n'
             b'\t\t\t\t\t\tsource.shield_remaining +=280+70*source.skill_levels[skill_id]+0.07*source.max_health\n'
             b'\t\t\t\t\t\tsource.shield_remaining=min(source.shield_remaining,3*(280+70*source.skill_levels[skill_id]+0.07*source.max_health))\n'
             b'\t\t\t\t\t\tsource.health += 0.125*source.shield_remaining\n'
             b'\t\t\t\t\t\tsource.shield_remaining*=0.75\n'
             b'\t\t\t\t\telse:\n'
             b'\t\t\t\t\t\t\n'
             b'\t\t\t\t\t\tpen_percent = 1\n'
             b'\t\t\t\t\t\tif skill_id == 1:\n'
             b'\t\t\t\t\t\t\tsource.stat = 1\n'
             b'\t\t\t\t\t\t\tsource.health +=104+24*source.skill_levels[skill_id]+0.025*source.max_health\n'
             b'\t\t\t\t\t\telse:\n'
             b'\t\t\t\t\t\t\tsource.health +=65+65*source.skill_levels[skill_id]+0.025*source.max_health\n'
             b'\t\t\t\telse:\n'
             b'\t\t\t\t\tif source.stat == 1:\n'
             b'\t\t\t\t\t\tpen_percent =1\n'
             b'\t\t\t\t\t\tsource.health +=65+0.025*source.max_health\n'
             b'\t\t\t\t\telif source.stat == 2:\n'
             b'\t\t\t\t\t\tpen_percent = 1\n'
             b'\t\t\t\t\t\tsource.health +=65+65*source.skill_levels[3]+0.025*source.max_health\n'
             b'\t\t\t\t\telse:\t\n'
             b'\t\t\t\t\t\tpen_percent+=0.35')

new_onhit = (b'\xe5\x90\x95\xe5\xb8\x83":\n'
             b'\t\t\t\tif  skill_id>0:\n'
             b'\t\t\t\t\tif skill_id == 2:\n'
             b'\t\t\t\t\t\tvar _lv = source.skill_levels[1]\n'
             b'\t\t\t\t\t\tvar _bhp = source.actual_max_health - source.max_health\n'
             b'\t\t\t\t\t\tsource.shield_remaining += int(280 + 70*_lv + 0.07*_bhp)\n'
             b'\t\t\t\t\t\tsource.shield_remaining = min(source.shield_remaining, 3*int(280 + 70*_lv + 0.07*_bhp))\n'
             b'\t\t\t\t\t\tsource.health += 0.125*source.shield_remaining\n'
             b'\t\t\t\t\t\tsource.shield_remaining*=0.75\n'
             b'\t\t\t\t\telse:\n'
             b'\t\t\t\t\t\tpen_percent = 1\n'
             b'\t\t\t\t\t\tsource.stat = 1\n'
             b'\t\t\t\t\t\tsource.stat_timer = 8.0\n'
             b'\t\t\t\t\t\tif skill_id == 1:\n'
             b'\t\t\t\t\t\t\tvar _lv2 = source.skill_levels[0]\n'
             b'\t\t\t\t\t\t\tvar _bhp2 = source.actual_max_health - source.max_health\n'
             b'\t\t\t\t\t\t\tsource.health += int(104 + 26*_lv2 + 0.025*_bhp2)\n'
             b'\t\t\t\t\t\telse:\n'
             b'\t\t\t\t\t\t\tvar _lv3 = source.skill_levels[2]\n'
             b'\t\t\t\t\t\t\tvar _bhp3 = source.actual_max_health - source.max_health\n'
             b'\t\t\t\t\t\t\tsource.health += int(65 + 65*_lv3 + 0.025*_bhp3)\n'
             b'\t\t\t\telse:\n'
             b'\t\t\t\t\tif source.stat >= 1:\n'
             b'\t\t\t\t\t\tpen_percent = 1\n'
             b'\t\t\t\t\t\tvar _bhp4 = source.actual_max_health - source.max_health\n'
             b'\t\t\t\t\t\tsource.health += int(65 + 0.0125*_bhp4)\n'
             b'\t\t\t\t\telse:\t\n'
             b'\t\t\t\t\t\tpen_percent+=0.35')

if old_onhit in data:
    data = data.replace(old_onhit, new_onhit, 1)
    wb(path, data)
    print("[OK] Bullet.gd: on_hit() Lu Bu block fixed")
else:
    print("[FAIL] Bullet.gd: on_hit() pattern not found")
    # Debug
    idx2 = data.find(b'\xe5\x90\x95\xe5\xb8\x83":\n\t\t\t\tif  skill_id>0:')
    if idx2 >= 0:
        print(f"  Found at {idx2}, showing 400 bytes:")
        print(repr(data[idx2:idx2+400]))

# Re-read for next fix
data = rb(path)

# --- Fix 2c: AoE Lu Bu block (identical pattern but different indentation) ---
old_aoe = (b'\xe5\x90\x95\xe5\xb8\x83":\n'
           b'\t\t\t\t\tif  skill_id>0:\n'
           b'\t\t\t\t\t\tif skill_id == 2:\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining +=280+70*source.skill_levels[skill_id]+0.07*source.max_health\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining=min(source.shield_remaining,3*(280+70*source.skill_levels[skill_id]+0.07*source.max_health))\n'
           b'\t\t\t\t\t\t\tsource.health += 0.125*source.shield_remaining\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining*=0.75\n'
           b'\t\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\t\t\n'
           b'\t\t\t\t\t\t\tpen_percent = 1\n'
           b'\t\t\t\t\t\t\tif skill_id == 1:\n'
           b'\t\t\t\t\t\t\t\tsource.stat = 1\n'
           b'\t\t\t\t\t\t\t\tsource.health +=104+24*source.skill_levels[skill_id]+0.025*source.max_health\n'
           b'\t\t\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\t\t\tsource.health +=65+65*source.skill_levels[skill_id]+0.025*source.max_health\n'
           b'\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\tif source.stat == 1:\n'
           b'\t\t\t\t\t\t\tpen_percent =1\n'
           b'\t\t\t\t\t\t\tsource.health +=65+0.025*source.max_health\n'
           b'\t\t\t\t\t\telif source.stat == 2:\n'
           b'\t\t\t\t\t\t\tpen_percent = 1\n'
           b'\t\t\t\t\t\t\tsource.health +=65+65*source.skill_levels[3]+0.025*source.max_health\n'
           b'\t\t\t\t\t\telse:\t\n'
           b'\t\t\t\t\t\t\tpen_percent+=0.35')

new_aoe = (b'\xe5\x90\x95\xe5\xb8\x83":\n'
           b'\t\t\t\t\tif  skill_id>0:\n'
           b'\t\t\t\t\t\tif skill_id == 2:\n'
           b'\t\t\t\t\t\t\tvar _lv = source.skill_levels[1]\n'
           b'\t\t\t\t\t\t\tvar _bhp = source.actual_max_health - source.max_health\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining += int(280 + 70*_lv + 0.07*_bhp)\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining = min(source.shield_remaining, 3*int(280 + 70*_lv + 0.07*_bhp))\n'
           b'\t\t\t\t\t\t\tsource.health += 0.125*source.shield_remaining\n'
           b'\t\t\t\t\t\t\tsource.shield_remaining*=0.75\n'
           b'\t\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\t\tpen_percent = 1\n'
           b'\t\t\t\t\t\t\tsource.stat = 1\n'
           b'\t\t\t\t\t\t\tsource.stat_timer = 8.0\n'
           b'\t\t\t\t\t\t\tif skill_id == 1:\n'
           b'\t\t\t\t\t\t\t\tvar _lv2 = source.skill_levels[0]\n'
           b'\t\t\t\t\t\t\t\tvar _bhp2 = source.actual_max_health - source.max_health\n'
           b'\t\t\t\t\t\t\t\tsource.health += int(104 + 26*_lv2 + 0.025*_bhp2)\n'
           b'\t\t\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\t\t\tvar _lv3 = source.skill_levels[2]\n'
           b'\t\t\t\t\t\t\t\tvar _bhp3 = source.actual_max_health - source.max_health\n'
           b'\t\t\t\t\t\t\t\tsource.health += int(65 + 65*_lv3 + 0.025*_bhp3)\n'
           b'\t\t\t\t\telse:\n'
           b'\t\t\t\t\t\tif source.stat >= 1:\n'
           b'\t\t\t\t\t\t\tpen_percent = 1\n'
           b'\t\t\t\t\t\t\tvar _bhp4 = source.actual_max_health - source.max_health\n'
           b'\t\t\t\t\t\t\tsource.health += int(65 + 0.0125*_bhp4)\n'
           b'\t\t\t\t\t\telse:\t\n'
           b'\t\t\t\t\t\t\tpen_percent+=0.35')

if old_aoe in data:
    data = data.replace(old_aoe, new_aoe, 1)
    wb(path, data)
    print("[OK] Bullet.gd: AoE Lu Bu block fixed")
else:
    print("[FAIL] Bullet.gd: AoE pattern not found")
    idx3 = data.find(b'\xe5\x90\x95\xe5\xb8\x83":\n\t\t\t\t\tif  skill_id>0:')
    if idx3 >= 0:
        print(f"  Found at {idx3}, showing 400 bytes:")
        print(repr(data[idx3:idx3+400]))

print("\n=== Lu Bu Bullet.gd + HeroPassive.gd fixes complete ===")
