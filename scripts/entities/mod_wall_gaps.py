"""Widen lane wall gaps and add flanking bushes at gap positions."""
import math
import pathlib

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
changes = 0

# ============================================================
# Part 1: Widen the gaps (6 places in _generate_lane_edge_walls)
# ============================================================

old_gap = '(t >= 24.0 and t <= 29.0) or (t >= 51.0 and t <= 56.0)'
new_gap = '(t >= 22.0 and t <= 31.0) or (t >= 49.0 and t <= 58.0)'
while old_gap in text:
    text = text.replace(old_gap, new_gap, 1)
    changes += 1
    print(f'Replaced lane gap #{changes}: {old_gap} -> {new_gap}')

old_mid_gap = '(lane_t >= 24.0 and lane_t <= 29.0) or (lane_t >= 51.0 and lane_t <= 56.0)'
new_mid_gap = '(lane_t >= 22.0 and lane_t <= 31.0) or (lane_t >= 49.0 and lane_t <= 58.0)'
while old_mid_gap in text:
    text = text.replace(old_mid_gap, new_mid_gap, 1)
    changes += 1
    print(f'Replaced mid gap #{changes}: {old_mid_gap} -> {new_mid_gap}')

print(f'Total gap replacements: {changes}')

# ============================================================
# Part 2: Compute bush positions at gaps
# ============================================================

# Gap boundaries (widened): t in [22, 31] and [49, 58]
# t = pos + 40, so pos = t - 40
# Gap 1: z/x in [22-40, 31-40] = [-18, -9]
# Gap 2: z/x in [49-40, 58-40] = [9, 18]

gap1_lo, gap1_hi = -18.0, -9.0   # world-space z/x range
gap2_lo, gap2_hi = 9.0, 18.0

bush_lines = []

# Helper: add bush position
def add_bush(x, z, label=''):
    bush_lines.append(f'\t\tVector3({x:.2f}, 0, {z:.2f}),  {label}'.rstrip())

# ============================
# Top lane blue side: inner wall at x=-47 (z from -37 to 37)
# ============================
add_bush(-47, gap1_lo - 0.5, '// 上路蓝方缺口1')
add_bush(-47, gap1_hi + 0.5, '')
add_bush(-47, gap2_lo - 0.5, '// 上路蓝方缺口2')
add_bush(-47, gap2_hi + 0.5, '')

# ============================
# Top lane red side: inner wall at x=47 (z from -37 to 37)
# ============================
add_bush(47, gap1_lo - 0.5, '// 上路红方缺口1')
add_bush(47, gap1_hi + 0.5, '')
add_bush(47, gap2_lo - 0.5, '// 上路红方缺口2')
add_bush(47, gap2_hi + 0.5, '')

# ============================
# Bottom lane blue side: inner wall at z=47 (x from -37 to 37)
# ============================
add_bush(gap1_lo - 0.5, 47, '// 下路蓝方缺口1')
add_bush(gap1_hi + 0.5, 47, '')
add_bush(gap2_lo - 0.5, 47, '// 下路蓝方缺口2')
add_bush(gap2_hi + 0.5, 47, '')

# ============================
# Bottom lane red side: inner wall at z=-47 (x from -37 to 37)
# ============================
add_bush(gap1_lo - 0.5, -47, '// 下路红方缺口1')
add_bush(gap1_hi + 0.5, -47, '')
add_bush(gap2_lo - 0.5, -47, '// 下路红方缺口2')
add_bush(gap2_hi + 0.5, -47, '')

# ============================
# Mid lane blue side: center(-30,30), fwd=(0.707,0,-0.707), right=(0.707,0,0.707)
# Left inner wall: mc + (-8)*right + t*fwd
# Right inner wall: mc + 8*right + t*fwd
# ============================
sqrt2_2 = math.sqrt(2) / 2  # ≈ 0.7071
mc_bx, mc_bz = -30.0, 30.0
fwd_x_b, fwd_z_b = sqrt2_2, -sqrt2_2
right_x, right_z = sqrt2_2, sqrt2_2

# Left inner wall at gap edges
for label, t_val in [('// 中路蓝方左墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路蓝方左墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_bx + (-8) * right_x + t_val * fwd_x_b
    wz = mc_bz + (-8) * right_z + t_val * fwd_z_b
    add_bush(round(wx, 2), round(wz, 2), label)

# Right inner wall at gap edges
for label, t_val in [('// 中路蓝方右墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路蓝方右墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_bx + 8 * right_x + t_val * fwd_x_b
    wz = mc_bz + 8 * right_z + t_val * fwd_z_b
    add_bush(round(wx, 2), round(wz, 2), label)

# ============================
# Mid lane red side: center(30,-30), fwd=(-0.707,0,0.707), right=(0.707,0,0.707)
# ============================
mc_rx, mc_rz = 30.0, -30.0
fwd_x_r, fwd_z_r = -sqrt2_2, sqrt2_2

# Left inner wall
for label, t_val in [('// 中路红方左墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路红方左墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_rx + (-8) * right_x + t_val * fwd_x_r
    wz = mc_rz + (-8) * right_z + t_val * fwd_z_r
    add_bush(round(wx, 2), round(wz, 2), label)

# Right inner wall
for label, t_val in [('// 中路红方右墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路红方右墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_rx + 8 * right_x + t_val * fwd_x_r
    wz = mc_rz + 8 * right_z + t_val * fwd_z_r
    add_bush(round(wx, 2), round(wz, 2), label)

# ============================================================
# Print all bush positions
# ============================================================
print('\n=== Bush positions to add ===')
for b in bush_lines:
    print(b)

# ============================================================
# Part 3: Insert bush positions into the file
# ============================================================

insert_block = '\t\t# ==== 三路城墙缺口草丛 ====\n' + '\n'.join(bush_lines)

# Find the insertion point: after the last bush position (the one from task G)
old_anchor = '\t\tVector3(37.88, 0, 42.12),\n\t]'
if old_anchor in text:
    new_anchor = '\t\tVector3(37.88, 0, 42.12),\n' + insert_block + '\n\t]'
    text = text.replace(old_anchor, new_anchor, 1)
    changes += 1
    print('\nSUCCESS: Bushes inserted into BattleManager.gd')
else:
    print('\nFAILED: Could not find insertion anchor')
    # Try to find the last bush from Task G
    idx = text.find('Vector3(37.88, 0, 42.12)')
    if idx >= 0:
        print(f'Found at {idx}: {repr(text[idx:idx+60])}')
    else:
        # Try alternative: find the closing bracket after bushes
        idx = text.find('右下角中路方向草丛（40,40中心，7个）')
        if idx >= 0:
            print(f'Found comment at {idx}')

# Write the file
path.write_text(text, 'utf-8')
print(f'Total modifications: {changes}')
