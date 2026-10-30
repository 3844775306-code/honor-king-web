"""Delete walls within 1m of any bush."""

import pathlib
path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
mods = 0

# ============================================================
# Step 1: Add member variable _bush_positions
# ============================================================
old1 = 'var jungle_camp_positions :Array = []'
new1 = 'var jungle_camp_positions :Array = []\nvar _bush_positions: Array = []'
if old1 in text and new1 not in text:
    text = text.replace(old1, new1, 1)
    mods += 1
    print('Step 1 OK: Added _bush_positions member variable')

# ============================================================
# Step 2: Move bushes array before wall generation
# ============================================================

# Find the array definition + loop block
# The array starts with: \t\t# 草丛: ...\n\t\tvar bushes = [
# The loop is: \t\tfor pos in bushes:\n\t\t\tvar bush...
# We want to split them: array goes before wall gen, loop stays

# Find the array block start and end
arr_start_marker = '\t\t# 草丛: 兵线交汇处两侧（朝向与河道垂直，与中路平行）\n\t\tvar bushes = ['
arr_end_marker = '\t\t]\n\t\tfor pos in bushes:'

idx_arr_start = text.find(arr_start_marker)
idx_arr_end = text.find(arr_end_marker)

if idx_arr_start < 0 or idx_arr_end < 0:
    print(f'FAILED Step 2: arr_start={idx_arr_start}, arr_end={idx_arr_end}')
else:
    # Extract the array definition (everything from comment to ])
    arr_def = text[idx_arr_start:idx_arr_end + 2]  # +2 for '\t\t'

    # The loop text that should remain
    loop_text = '\t\tfor pos in bushes:\n\t\t\tvar bush = Bush.new()\n\t\t\tbush.position = pos\n\t\t\tadd_child(bush)'

    # Remove the entire block (array def + loop) from original position
    full_block = arr_def + '\n' + loop_text
    text = text.replace(full_block, loop_text, 1)

    # Now insert array def before wall generation, with _bush_positions assignment
    wall_marker = '\t\t# ---- 墙体与草丛生成 ----'
    insertion = arr_def + '\n\t\t_bush_positions = bushes\n\n' + wall_marker
    if wall_marker in text:
        text = text.replace(wall_marker, insertion, 1)
        mods += 1
        print('Step 2 OK: Moved bushes array before wall generation')
    else:
        print('FAILED Step 2b: wall_marker not found')

# ============================================================
# Step 3: Modify _add_wall() to skip walls within 1m of any bush
# ============================================================
old_add_wall = '''func _add_wall(pos: Vector3, facing: Vector3 = Vector3.ZERO):
\tif _is_inside_high_ground(pos):
\t\treturn
\tvar wall = Wall.new()'''

new_add_wall = '''func _add_wall(pos: Vector3, facing: Vector3 = Vector3.ZERO):
\tif _is_inside_high_ground(pos):
\t\treturn
\t# 跳过距离草丛<1m的墙体
\tfor bp in _bush_positions:
\t\tif pos.distance_to(bp) < 1.0:
\t\t\treturn
\tvar wall = Wall.new()'''

if old_add_wall in text:
    text = text.replace(old_add_wall, new_add_wall, 1)
    mods += 1
    print('Step 3 OK: Modified _add_wall() with bush proximity check')
else:
    print('FAILED Step 3: _add_wall() not found')
    # Debug: find the function
    idx = text.find('func _add_wall')
    if idx >= 0:
        print(f'  Found at {idx}: {repr(text[idx:idx+150])}')

# ============================================================
# Step 4: Clean up orphaned comment inside bushes array
# ============================================================
# The comment "# ==== 三路城墙缺口草丛 ====" has no entries under it. Remove it.
orphan = '\t\t\t# ==== 三路城墙缺口草丛 ====\n\t\t]'
if orphan in text:
    text = text.replace(orphan, '\t\t]', 1)
    mods += 1
    print('Step 4 OK: Removed orphaned section comment')
else:
    # Try different variant
    orphan2 = '\t\t\t# ==== 三路城墙缺口草丛 ====\n\t\t\t]'
    if orphan2 in text:
        text = text.replace(orphan2, '\t\t\t]', 1)
        mods += 1
        print('Step 4 OK: Removed orphaned section comment (3-tab variant)')
    else:
        print('Step 4: Orphan comment not found, checking...')
        idx = text.find('三路城墙缺口草丛')
        if idx >= 0:
            print(f'  Found at {idx}: {repr(text[idx:idx+60])}')

# ============================================================
# Write result
# ============================================================
path.write_text(text, 'utf-8')
print(f'\nTotal modifications: {mods}')
print('Done.')
