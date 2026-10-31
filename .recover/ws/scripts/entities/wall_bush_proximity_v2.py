"""Delete walls within 1m of any bush — v2 with correct indentation."""

import pathlib
path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
mods = 0

# ============================================================
# Step 1: Add member variable
# ============================================================
old1 = 'var jungle_camp_positions :Array = []'
new1 = 'var jungle_camp_positions :Array = []\nvar _bush_positions: Array = []'
if old1 in text and new1 not in text:
    text = text.replace(old1, new1, 1)
    mods += 1
    print('Step 1 OK')

# ============================================================
# Step 2: Move bushes array before wall generation
# ============================================================

# Find array start: 'var bushes = [' (unique in file)
arr_var_idx = text.find('\tvar bushes = [\n')
if arr_var_idx < 0:
    arr_var_idx = text.find('var bushes = [\n')
    prefix = ''
else:
    prefix = '\t'

if arr_var_idx < 0:
    print(f'FAILED: var bushes not found')
else:
    # Find the line before var bushes (the comment line)
    line_before_idx = text.rfind('\n', 0, arr_var_idx)
    if line_before_idx < 0 or arr_var_idx - line_before_idx < 10:
        # The comment line ends at a newline before arr_var_idx
        # Find the comment line start
        comment_start = text.rfind('\n', 0, arr_var_idx - 1)
        comment_line = text[comment_start+1:arr_var_idx]
        print(f'Comment line before array: {repr(comment_line[:60])}')
    else:
        comment_line = ''

    # Find the matching closing bracket and the for loop
    # The array ends with ']\n' followed by 'for pos in bushes:'
    for_end_marker = ']\n\tfor pos in bushes:'
    for_end_idx = text.find(for_end_marker, arr_var_idx)
    if for_end_idx < 0:
        # Try 2-tab variant
        for_end_marker = ']\n\t\tfor pos in bushes:'
        for_end_idx = text.find(for_end_marker, arr_var_idx)

    if for_end_idx < 0:
        print(f'FAILED: for loop after array not found')
        # Debug
        remaining = text[arr_var_idx:arr_var_idx+3000]
        bracket_idx = remaining.find('for pos in bushes:')
        if bracket_idx >= 0:
            print(f'  for loop found at offset {bracket_idx}: {repr(remaining[max(0,bracket_idx-10):bracket_idx+30])}')
    else:
        # Get the array definition (from the comment line before var to the closing ])
        # Backtrack from arr_var_idx to find the start of the comment line
        comment_line_start = text.rfind('\n', 0, arr_var_idx - 1)
        if comment_line_start < 0:
            comment_line_start = 0
        else:
            comment_line_start += 1  # skip the newline

        arr_def = text[comment_line_start:for_end_idx + 2]  # +2 for ']\n'

        # The loop that instantiates bushes
        # Find the full loop text (for pos in bushes: ... add_child(bush))
        loop_start = for_end_idx + 2  # right after ']\n'
        # Find where the loop ends (next blank line or next function)
        loop_search = text[loop_start:loop_start+200]
        add_child_idx = loop_search.find('add_child(bush)')
        if add_child_idx >= 0:
            loop_end = loop_start + add_child_idx + len('add_child(bush)')
        else:
            loop_end = loop_start + 100  # fallback

        loop_text = text[loop_start:loop_end]

        # Remove the full block (array def + loop) from current position
        full_block = arr_def + loop_text
        text = text.replace(full_block, loop_text, 1)

        # Now insert array definition before wall generation
        wall_marker = '\t# ---- 墙体与草丛生成 ----'
        if wall_marker not in text:
            wall_marker = '\t\t# ---- 墙体与草丛生成 ----'

        if wall_marker in text:
            insertion = arr_def + '\t_bush_positions = bushes\n\n' + wall_marker
            text = text.replace(wall_marker, insertion, 1)
            mods += 1
            print('Step 2 OK: Moved array before wall generation')
        else:
            print('FAILED: wall marker not found after move')

# ============================================================
# Step 3: Clean up orphaned comment
# ============================================================
orphan = '三路城墙缺口草丛 ====\n\t\t\t]\n\tfor pos in bushes:'
idx_orphan = text.find(orphan)
if idx_orphan >= 0:
    text = text[:idx_orphan] + '三路城墙缺口草丛 ====\n\t\t]\n\tfor pos in bushes:' + text[idx_orphan + len(orphan):]
    mods += 1
    print('Step 3 OK: Fixed orphan comment indentation')
else:
    print('Step 3: Orphan pattern not found, checking vars...')
    idx = text.find('三路城墙缺口草丛')
    if idx >= 0:
        print(f'  Found at {idx}: {repr(text[idx:idx+80])}')

# ============================================================
# Write
# ============================================================
path.write_text(text, 'utf-8')
print(f'\nTotal modifications: {mods}')
