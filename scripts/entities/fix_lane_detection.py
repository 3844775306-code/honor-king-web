"""Fix lane detection to account for team (player vs enemy) perspective."""
import pathlib

p = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
t = p.read_text('utf-8')

# Find the exact text using ASCII-only anchors
# Anchor: the line before the lane detection
anchor_before = 'func spawn_single_minion(type: String, team: int, pos: Vector3, waypoints: Array,line):'

idx = t.find(anchor_before)
if idx < 0:
    print('ERROR: anchor not found')
    exit(1)

# Find the lane detection block
block_start = t.find('var lane = ""', idx)
block_end = t.find('high_tower_destroyed', block_start)

if block_start < 0 or block_end < 0:
    print(f'ERROR: block not found. start={block_start}, end={block_end}')
    exit(1)

old_block = t[block_start:block_end]
print(f'Old block ({len(old_block)} chars):')
print(repr(old_block[:200]))

new_block = '''var lane = ""
\t\tif abs(waypoints[0].x) < abs(waypoints[0].z):
\t\t\tlane = "farm" if team == Config.Team.PLAYER else "clash"
\t\telif abs(waypoints[0].x) == abs(waypoints[0].z):
\t\t\tlane = "mid"
\t\telse:
\t\t\tlane = "clash" if team == Config.Team.PLAYER else "farm"
\t
\t\t# '''

# Also fix the comment + is_mid line before lane detection
old_comment = '# 判断是否为中路（简单通过X坐标判断）'
new_comment = '# 判断分路（敌方坐标模式与玩家方镜像，需按队伍区分）'
c_comment = t.count(old_comment)
t = t.replace(old_comment, new_comment)

old_ismid = 'var is_mid = abs(waypoints[0].x) ==  abs(waypoints[0].z)   # 中路塔X接近0'
new_ismid = 'var is_mid = abs(waypoints[0].x) == abs(waypoints[0].z)'
c_ismid = t.count(old_ismid)
t = t.replace(old_ismid, new_ismid)

# Replace the lane block
old_lane_comment = ' # 判断分路\n\t\tvar lane = ""'
new_lane_comment = '\n\t\tvar lane = ""'
c_lane_comment = t.count(old_lane_comment)
t = t.replace(old_lane_comment, new_lane_comment)

t = t.replace(old_block, new_block)
p.write_text(t, 'utf-8')

print(f'Comment fix: {c_comment}')
print(f'is_mid fix: {c_ismid}')
print(f'Lane comment removal: {c_lane_comment}')
print('Done')
