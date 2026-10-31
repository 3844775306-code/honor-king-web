"""Unify all lane detection to X+Z rule: >0=farm, <0=clash, ==0=mid."""
import pathlib
TAB = chr(9)

def fix_file(rel_path, replacements):
    p = pathlib.Path(r'C:\Users\18749\Documents\honor-king') / rel_path
    t = p.read_text('utf-8')
    total = 0
    for old, new, label in replacements:
        c = t.count(old)
        if c:
            t = t.replace(old, new)
            total += c
            print(f'  {label}: {c}')
        else:
            print(f'  {label}: NOT FOUND')
    p.write_text(t, 'utf-8')
    print(f'  -> {total} total changes')
    return total

grand = 0

# ============================================================
# 1. BattleManager.gd - spawn_single_minion lane detection
# ============================================================
print('\n[1] BattleManager.gd')
grand += fix_file('scripts/core/BattleManager.gd', [
    (TAB + TAB + '''var lane = ""
''' + TAB + TAB + '''if abs(waypoints[0].x) < abs(waypoints[0].z):
''' + TAB + TAB + TAB + '''lane = "farm" if team == Config.Team.PLAYER else "clash"
''' + TAB + TAB + '''elif abs(waypoints[0].x) == abs(waypoints[0].z):
''' + TAB + TAB + TAB + '''lane = "mid"
''' + TAB + TAB + '''else:
''' + TAB + TAB + TAB + '''lane = "clash" if team == Config.Team.PLAYER else "farm"''',
     TAB + TAB + '''var lane = ""
''' + TAB + TAB + '''var s = waypoints[0].x + waypoints[0].z
''' + TAB + TAB + '''if s > 0:
''' + TAB + TAB + TAB + '''lane = "farm"
''' + TAB + TAB + '''elif s < 0:
''' + TAB + TAB + TAB + '''lane = "clash"
''' + TAB + TAB + '''else:
''' + TAB + TAB + TAB + '''lane = "mid"''',
     'spawn_single_minion lane detection'),
])

# ============================================================
# 2. Turret.gd - high tower destroyed lane detection
# ============================================================
print('\n[2] Turret.gd')
grand += fix_file('scripts/entities/Turret.gd', [
    ('''\t\tvar pos_x = abs(global_position.x)
\t\tvar pos_z = abs(global_position.z)
\t\tif pos_x > pos_z :
\t\t\tlane = "farm"
\t\telif pos_x == pos_z :
\t\t\tlane = "mid"
\t\telif pos_x < pos_z :
\t\t\tlane = "clash"''',
     '''\t\tvar s = global_position.x + global_position.z
\t\tif s > 0:
\t\t\tlane = "farm"
\t\telif s < 0:
\t\t\tlane = "clash"
\t\telse:
\t\t\tlane = "mid"''',
     'high tower lane detection'),
])

# ============================================================
# 3. LaneStrategy.gd - _get_turret_lane
# ============================================================
print('\n[3] LaneStrategy.gd')
grand += fix_file('ai/LaneStrategy.gd', [
    ('''func _get_turret_lane(turret: Turret) -> int:
\tvar ax := absf(turret.global_position.x)
\tvar az := absf(turret.global_position.z)
\tif ax < az:
\t\treturn AiConfig.Lane.FARM
\telif ax == az:
\t\treturn AiConfig.Lane.MID
\telse:
\t\treturn AiConfig.Lane.CLASH''',
     '''func _get_turret_lane(turret: Turret) -> int:
\tvar s = turret.global_position.x + turret.global_position.z
\tif s > 0:
\t\treturn AiConfig.Lane.FARM
\telif s < 0:
\t\treturn AiConfig.Lane.CLASH
\telse:
\t\treturn AiConfig.Lane.MID''',
     '_get_turret_lane'),
])

# ============================================================
# 4. TeamTactics.gd - _get_turret_lane
# ============================================================
print('\n[4] TeamTactics.gd')
grand += fix_file('ai/TeamTactics.gd', [
    ('''func _get_turret_lane(turret: Turret) -> int:
\tvar ax := absf(turret.global_position.x)
\tvar az := absf(turret.global_position.z)
\tif ax < az:
\t\treturn AiConfig.Lane.FARM
\telif ax == az:
\t\treturn AiConfig.Lane.MID
\telse:
\t\treturn AiConfig.Lane.CLASH''',
     '''func _get_turret_lane(turret: Turret) -> int:
\tvar s = turret.global_position.x + turret.global_position.z
\tif s > 0:
\t\treturn AiConfig.Lane.FARM
\telif s < 0:
\t\treturn AiConfig.Lane.CLASH
\telse:
\t\treturn AiConfig.Lane.MID''',
     '_get_turret_lane'),
])

# ============================================================
# 5. HeroAI.gd - _get_turret_lane
# ============================================================
print('\n[5] HeroAI.gd')
grand += fix_file('ai/HeroAI.gd', [
    ('''func _get_turret_lane(turret: Turret) -> int:
\tvar ax := absf(turret.global_position.x)
\tvar az := absf(turret.global_position.z)
\tif ax < az:
\t\treturn AiConfig.Lane.FARM
\telif ax == az:
\t\treturn AiConfig.Lane.MID
\telse:
\t\treturn AiConfig.Lane.CLASH''',
     '''func _get_turret_lane(turret: Turret) -> int:
\tvar s = turret.global_position.x + turret.global_position.z
\tif s > 0:
\t\treturn AiConfig.Lane.FARM
\telif s < 0:
\t\treturn AiConfig.Lane.CLASH
\telse:
\t\treturn AiConfig.Lane.MID''',
     '_get_turret_lane'),
])

# ============================================================
# 6. JungleStrategy.gd - _get_turret_lane
# ============================================================
print('\n[6] JungleStrategy.gd')
grand += fix_file('ai/JungleStrategy.gd', [
    ('''func _get_turret_lane(turret: Turret) -> int:
\tvar ax := absf(turret.global_position.x)
\tvar az := absf(turret.global_position.z)
\tif ax < az:
\t\treturn AiConfig.Lane.FARM
\telif ax == az:
\t\treturn AiConfig.Lane.MID
\telse:
\t\treturn AiConfig.Lane.CLASH''',
     '''func _get_turret_lane(turret: Turret) -> int:
\tvar s = turret.global_position.x + turret.global_position.z
\tif s > 0:
\t\treturn AiConfig.Lane.FARM
\telif s < 0:
\t\treturn AiConfig.Lane.CLASH
\telse:
\t\treturn AiConfig.Lane.MID''',
     '_get_turret_lane'),
])

# ============================================================
# 7. AiPerception.gd - _get_health_pack_lane
# ============================================================
print('\n[7] AiPerception.gd')
grand += fix_file('ai/perception/AiPerception.gd', [
    ('''func _get_health_pack_lane(pos: Vector3) -> int:
\t# 发育路/对抗路血包靠近地图边缘
\tif abs(pos.x) > 50:
\t\treturn AiConfig.Lane.FARM
\tif abs(pos.z) > 50:
\t\treturn AiConfig.Lane.CLASH
\treturn AiConfig.Lane.MID''',
     '''func _get_health_pack_lane(pos: Vector3) -> int:
\tvar s = pos.x + pos.z
\tif s > 0:
\t\treturn AiConfig.Lane.FARM
\telif s < 0:
\t\treturn AiConfig.Lane.CLASH
\telse:
\t\treturn AiConfig.Lane.MID''',
     '_get_health_pack_lane'),
])

print(f'\n=== Grand total: {grand} changes ===')
