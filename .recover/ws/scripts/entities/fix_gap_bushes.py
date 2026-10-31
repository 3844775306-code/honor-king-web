"""Fix gap bush positions: offset 1.5m away from wall centers toward lane."""
import math
import pathlib

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')

sqrt2_2 = math.sqrt(2) / 2  # ≈ 0.7071
OFFSET = 1.5  # meters from wall center (wall collision is 0.4m wide)

# Gap boundaries (widened): z/x range
gap1_lo, gap1_hi = -18.0, -9.0
gap2_lo, gap2_hi = 9.0, 18.0

bush_lines = []

def add_bush(x, z, label=''):
    bush_lines.append(f'\t\tVector3({x:.2f}, 0, {z:.2f}),  {label}'.rstrip())

# ============================
# Top lane blue: inner wall at x=-47 (facing +X toward lane)
# Offset: toward lane = +X → x = -47 + OFFSET = -45.5
# ============================
wx = -47.0 + OFFSET
add_bush(wx, gap1_lo - 0.5, '// 上路蓝方缺口1')
add_bush(wx, gap1_hi + 0.5, '')
add_bush(wx, gap2_lo - 0.5, '// 上路蓝方缺口2')
add_bush(wx, gap2_hi + 0.5, '')

# ============================
# Top lane red: inner wall at x=47 (facing -X toward lane)
# Offset: toward lane = -X → x = 47 - OFFSET = 45.5
# ============================
wx = 47.0 - OFFSET
add_bush(wx, gap1_lo - 0.5, '// 上路红方缺口1')
add_bush(wx, gap1_hi + 0.5, '')
add_bush(wx, gap2_lo - 0.5, '// 上路红方缺口2')
add_bush(wx, gap2_hi + 0.5, '')

# ============================
# Bottom lane blue: inner wall at z=47 (facing +Z toward lane... wait)
# Code: _add_wall(Vector3(x, 0, 47), Vector3(0, 0, -1)) — facing -Z toward lane
# Offset: toward lane = -Z → z = 47 - OFFSET = 45.5
# ============================
wz = 47.0 - OFFSET
add_bush(gap1_lo - 0.5, wz, '// 下路蓝方缺口1')
add_bush(gap1_hi + 0.5, wz, '')
add_bush(gap2_lo - 0.5, wz, '// 下路蓝方缺口2')
add_bush(gap2_hi + 0.5, wz, '')

# ============================
# Bottom lane red: inner wall at z=-47 (facing -Z toward lane)
# Code: _add_wall(Vector3(x, 0, -47), Vector3(0, 0, -1))
# The "toward lane" direction for z=-47 would be +Z (since lane center is at smaller |z|)
# Actually: facing is (0,0,-1) which points in -Z direction. The wall face is on the -Z side.
# The lane center is at z=0, which is +Z from z=-47.
# So "toward lane" = +Z → z = -47 + OFFSET = -45.5
# ============================
wz = -47.0 + OFFSET
add_bush(gap1_lo - 0.5, wz, '// 下路红方缺口1')
add_bush(gap1_hi + 0.5, wz, '')
add_bush(gap2_lo - 0.5, wz, '// 下路红方缺口2')
add_bush(gap2_hi + 0.5, wz, '')

# ============================
# Mid lane blue side: center(-30,30), fwd=(0.707,0,-0.707), right=(0.707,0,0.707)
# Left inner wall: mc + (-8)*right + t*fwd, facing = right
#   Offset toward lane = -right * OFFSET
# Right inner wall: mc + 8*right + t*fwd, facing = -right
#   Offset toward lane = +right * OFFSET
# ============================
mc_bx, mc_bz = -30.0, 30.0
fwd_x_b, fwd_z_b = sqrt2_2, -sqrt2_2
right_x, right_z = sqrt2_2, sqrt2_2

# Blue left inner wall (offset toward lane by -right * OFFSET)
for label, t_val in [('// 中路蓝方左墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路蓝方左墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_bx + (-8) * right_x + t_val * fwd_x_b + (-right_x) * OFFSET
    wz = mc_bz + (-8) * right_z + t_val * fwd_z_b + (-right_z) * OFFSET
    add_bush(round(wx, 2), round(wz, 2), label)

# Blue right inner wall (offset toward lane by +right * OFFSET)
for label, t_val in [('// 中路蓝方右墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路蓝方右墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_bx + 8 * right_x + t_val * fwd_x_b + right_x * OFFSET
    wz = mc_bz + 8 * right_z + t_val * fwd_z_b + right_z * OFFSET
    add_bush(round(wx, 2), round(wz, 2), label)

# ============================
# Mid lane red side: center(30,-30), fwd=(-0.707,0,0.707), right=(0.707,0,0.707)
# Left inner wall: mc + (-8)*right + t*fwd, facing = right
#   Offset = -right * OFFSET
# Right inner wall: mc + 8*right + t*fwd, facing = -right
#   Offset = +right * OFFSET
# ============================
mc_rx, mc_rz = 30.0, -30.0
fwd_x_r, fwd_z_r = -sqrt2_2, sqrt2_2

# Red left inner wall (offset -right)
for label, t_val in [('// 中路红方左墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路红方左墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_rx + (-8) * right_x + t_val * fwd_x_r + (-right_x) * OFFSET
    wz = mc_rz + (-8) * right_z + t_val * fwd_z_r + (-right_z) * OFFSET
    add_bush(round(wx, 2), round(wz, 2), label)

# Red right inner wall (offset +right)
for label, t_val in [('// 中路红方右墙缺口1', gap1_lo - 0.5),
                       ('', gap1_hi + 0.5),
                       ('// 中路红方右墙缺口2', gap2_lo - 0.5),
                       ('', gap2_hi + 0.5)]:
    wx = mc_rx + 8 * right_x + t_val * fwd_x_r + right_x * OFFSET
    wz = mc_rz + 8 * right_z + t_val * fwd_z_r + right_z * OFFSET
    add_bush(round(wx, 2), round(wz, 2), label)

print('=== Corrected bush positions (1.5m from wall) ===')
for b in bush_lines:
    print(b)

# Now replace the old section in the file
insert_block = '\t\t# ==== 三路城墙缺口草丛（离墙≥1.5m）====\n' + '\n'.join(bush_lines)

# Find the old section and replace it
old_start = '\t\t# ==== 三路城墙缺口草丛 ===='
old_end = '\t\tVector3(22.58, 0, -11.26),\n\t]'

# Build the search pattern: everything from old_start to old_end
idx_start = text.find(old_start)
idx_end = text.find(old_end)

if idx_start >= 0 and idx_end > idx_start:
    # Replace the entire old section
    before = text[:idx_start]
    after = text[idx_end + len(old_end):]
    text = before + insert_block + '\n\t]'
    path.write_text(text, 'utf-8')
    print('\nSUCCESS: Corrected bush positions written to BattleManager.gd')
else:
    print(f'\nFAILED: idx_start={idx_start}, idx_end={idx_end}')
    # Fallback: try finding just the old section start
    if idx_start >= 0:
        print(f'Found start at {idx_start}')
        # Print around the start to debug
        print(repr(text[idx_start:idx_start+200]))
