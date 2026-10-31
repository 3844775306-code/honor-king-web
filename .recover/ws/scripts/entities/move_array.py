"""Move bushes array before wall generation — ASCII-only anchors."""

import pathlib
path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
mods = 0

# ============================================================
# Find key positions using ASCII-only anchors
# ============================================================

# Anchor 1: 'for pos in bushes:' — unique, follows the array
idx_for = text.find('for pos in bushes:')
if idx_for < 0:
    print('FAILED: for pos in bushes: not found')
    exit(1)

# Anchor 2: 'var bushes = [' — unique, starts the array
idx_var = text.rfind('var bushes = [', 0, idx_for)
if idx_var < 0:
    print('FAILED: var bushes = [ not found')
    exit(1)

# Anchor 3: the closing ']' between var and for
idx_bracket = text.rfind(']', idx_var, idx_for)
if idx_bracket < 0:
    print('FAILED: closing bracket not found')
    exit(1)

# Find the start of the line containing 'var bushes = ['
idx_var_line_start = text.rfind('\n', 0, idx_var) + 1

# Also include the comment line right before var bushes (if present)
# Go back one more newline to get the comment line
idx_prev_nl = text.rfind('\n', 0, idx_var_line_start - 1)
if idx_prev_nl >= 0 and idx_var_line_start - idx_prev_nl < 120:
    # The comment line is short, include it
    block_start = idx_prev_nl + 1
else:
    block_start = idx_var_line_start

# The array definition block: from block_start to idx_bracket+1 (inclusive of ])
arr_def = text[block_start:idx_bracket + 1]

# The loop text: from idx_for to the end of add_child(bush)
add_child_idx = text.find('add_child(bush)', idx_for)
if add_child_idx >= 0:
    # Find the newline after add_child(bush)
    nl_after = text.find('\n', add_child_idx)
    if nl_after >= 0:
        loop_end = nl_after
    else:
        loop_end = add_child_idx + len('add_child(bush)')
else:
    loop_end = idx_for + 100

loop_text = text[idx_for:loop_end]

# Combined block currently in file
full_block = arr_def + '\n' + loop_text

print(f'Array block: {len(arr_def)} bytes, starts with: {repr(arr_def[:50])}')
print(f'Loop text: {repr(loop_text[:60])}')

# ============================================================
# Remove the full block, keep only loop
# ============================================================
if full_block in text:
    text = text.replace(full_block, loop_text, 1)
    mods += 1
    print('Step 1 OK: Removed array block from original position')
else:
    print('FAILED: full_block not found in text')
    # Debug
    print(f'  arr_def[:80]: {repr(arr_def[:80])}')
    print(f'  loop_text[:80]: {repr(loop_text[:80])}')
    # Try to find arr_def in text
    test_idx = text.find(arr_def)
    print(f'  arr_def in text: {test_idx}')

# ============================================================
# Insert array def before wall generation + add _bush_positions
# ============================================================
wall_marker = '# ---- 墙体与草丛生成 ----'
idx_wall = text.find(wall_marker)
if idx_wall < 0:
    print('FAILED: wall marker not found')
else:
    # Find the start of the line containing the wall marker
    wall_line_start = text.rfind('\n', 0, idx_wall) + 1

    # Build the insertion: array def + _bush_positions assignment + blank line
    insertion = arr_def + '\n\t_bush_positions = bushes\n\n'

    text = text[:wall_line_start] + insertion + text[wall_line_start:]
    mods += 1
    print('Step 2 OK: Inserted array before wall generation')

# ============================================================
# Verify order
# ============================================================
idx_wall2 = text.find('# ---- 墙体与草丛生成 ----')
idx_bushes2 = text.find('var bushes = [')
idx_bush_pos = text.find('_bush_positions = bushes')
print(f'\nVerification:')
print(f'  _bush_positions = bushes at byte {idx_bush_pos}')
print(f'  var bushes at byte {idx_bushes2}')
print(f'  wall gen at byte {idx_wall2}')
print(f'  Order correct: {idx_bushes2 < idx_bush_pos < idx_wall2}')

# ============================================================
# Write
# ============================================================
path.write_text(text, 'utf-8')
print(f'\nTotal modifications: {mods}')
print('Done.')
