"""Fix Hou Yi (后羿) enhanced AA splash — LF line endings edition."""
import os

BASE = r"C:\Users\18749\Documents\honor-king"
path = os.path.join(BASE, "scripts", "entities", "Hero.gd")

with open(path, 'rb') as f:
    data = f.read()

def enc(s):
    return s.encode('utf-8')

# ================================================================
# FIX 1: Replace splash ent.take_damage with bullet storage
# ================================================================
# Pattern from debug: ent.take_damage(int(dmg * 0.5), self, false, -1, 0)\n\t\t\t\t\tsplash_count += 1\n\t#
old1 = b'\t\t\t\t\tent.take_damage(int(dmg * 0.5), self, false, -1, 0)\n\t\t\t\t\tsplash_count += 1\n\t# \xe5\x86\xb0\xe7\x97\x95\xe4\xb9\x8b\xe6\x8f\xa1'
new1 = b'\t\t\t\t\thouyi_splash_targets.append(ent)\n\t\t\t\t\tsplash_count += 1\n\t# \xe5\x86\xb0\xe7\x97\x95\xe4\xb9\x8b\xe6\x8f\xa1'

if data.count(old1) == 1:
    data = data.replace(old1, new1, 1)
    print("[OK] FIX 1: Splash take_damage -> bullet storage")
else:
    print(f"[FAIL] FIX 1: pattern count = {data.count(old1)}")

# ================================================================
# FIX 1b: Add var houyi_splash_targets declaration before Q block
# ================================================================
# Pattern: OnHitProcessor.apply_chase_wind(self)\n\t# 后羿Q
old1b = b'OnHitProcessor.apply_chase_wind(self)\n\t# \xe5\x90\x8e\xe7\xbe\xbfQ\xef\xbc\x9a\xe5\xbc\xba\xe5\x8c\x96\xe6\x99\xae\xe6\x94\xbb+\xe5\x89\x8d\xe6\x96\xb92\xe7\x9b\xae\xe6\xa0\x87\xe6\xba\x85\xe5\xb0\x84'
new1b = b'OnHitProcessor.apply_chase_wind(self)\n\tvar houyi_splash_targets: Array = []\n\t# \xe5\x90\x8e\xe7\xbe\xbfQ\xef\xbc\x9a\xe5\xbc\xba\xe5\x8c\x96\xe6\x99\xae\xe6\x94\xbb+\xe5\x89\x8d\xe6\x96\xb92\xe7\x9b\xae\xe6\xa0\x87\xe6\xba\x85\xe5\xb0\x84'

if data.count(old1b) == 1:
    data = data.replace(old1b, new1b, 1)
    print("[OK] FIX 1b: var declaration added")
else:
    print(f"[FAIL] FIX 1b: pattern count = {data.count(old1b)}")

# ================================================================
# FIX 2: Add splash bullet creation after extra arrows
# ================================================================
# Pattern: \t\t\tget_parent().add_child(extra_bullet)\n\telse:\n\t\t\n\t\tif display_name == "铠":
old2 = b'\t\t\t\tget_parent().add_child(extra_bullet)\n\telse:\n\t\t\n\t\tif display_name == "\xe9\x93\xa0":'

if data.count(old2) == 1:
    # Insert splash bullet code between closing the extra_bullet add_child and else:
    insert_at = data.find(old2) + len(b'\t\t\t\tget_parent().add_child(extra_bullet)\n')
    splash_code = enc(
        '\n'
        '\t\t\t# 后羿Q：溅射子弹（受惩戒射击影响,dmg已包含40%惩罚）\n'
        '\t\t\tfor st in houyi_splash_targets:\n'
        '\t\t\t\tvar splash_dmg = int(dmg * 0.5)\n'
        '\t\t\t\tvar splash_dir = (st.global_position - global_position).normalized()\n'
        '\t\t\t\tvar splash_bullet = skillapply.create_bullet(splash_dmg, 0, 0, 0, false, self, splash_dir, -1)\n'
        '\t\t\t\tsplash_bullet.target = st\n'
        '\t\t\t\tsplash_bullet.life_time = 3\n'
        '\t\t\t\tget_parent().add_child(splash_bullet)\n'
    )
    data = data[:insert_at] + splash_code + data[insert_at:]
    print("[OK] FIX 2: Splash bullet creation added")
else:
    print(f"[FAIL] FIX 2: pattern count = {data.count(old2)}")

# ================================================================
# FIX 3: Fix nesting bug — 后羿 stat out of 狄仁杰 block
# ================================================================
# Pattern: 狄仁杰":\n\t\tstat_timer = 3.0\n\t\tif stat <5: stat +=1;\n\t\tif stat2 <3: stat2 +=1\n\t\tif display_name == "后羿":\n\t\t\tstat_timer = 3.0\n\t\t\tstat = min(stat + 1, 3)
old3 = enc('狄仁杰":\n\t\tstat_timer = 3.0\n\t\tif stat <5: stat +=1;\n\t\tif stat2 <3: stat2 +=1\n\t\tif display_name == "后羿":\n\t\t\tstat_timer = 3.0\n\t\t\tstat = min(stat + 1, 3)')

new3 = enc('狄仁杰":\n\t\tstat_timer = 3.0\n\t\tif stat <5: stat +=1;\n\t\tif stat2 <3: stat2 +=1\n\tif display_name == "后羿":\n\t\tstat_timer = 3.0\n\t\tstat = min(stat + 1, 3)')

if data.count(old3) == 1:
    data = data.replace(old3, new3, 1)
    print("[OK] FIX 3: Nesting bug fixed")
else:
    print(f"[FAIL] FIX 3: pattern count = {data.count(old3)}")

with open(path, 'wb') as f:
    f.write(data)

print("\n=== Done ===")
