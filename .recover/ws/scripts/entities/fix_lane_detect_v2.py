"""Fix the corrupted lane detection block by replacing from anchor to anchor."""
import pathlib

p = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
t = p.read_text('utf-8')

# Find the spawn_single_minion function
anchor = 'func spawn_single_minion(type: String, team: int, pos: Vector3, waypoints: Array,line):'
idx = t.find(anchor)
if idx < 0:
    print('ERROR: anchor not found')
    exit(1)

# Find the corrupted block: from "#print(line)" to the line before "获取动态属性"
start_marker = '\t\t#print(line)'
end_marker = '\t\t# 获取动态属性'

start = t.find(start_marker, idx)
end = t.find(end_marker, idx)

if start < 0 or end < 0:
    print(f'ERROR: markers not found. start={start}, end={end}')
    exit(1)

# Include the start marker line itself
old = t[start:end]
print(f'Replacing {len(old)} chars')

new = '''\t\t#print(line)
\t\t# 判断分路（敌方坐标模式与玩家方镜像，需按队伍区分）
\t\tvar is_mid = abs(waypoints[0].x) == abs(waypoints[0].z)
\t\tvar lane = ""
\t\tif abs(waypoints[0].x) < abs(waypoints[0].z):
\t\t\tlane = "farm" if team == Config.Team.PLAYER else "clash"
\t\telif abs(waypoints[0].x) == abs(waypoints[0].z):
\t\t\tlane = "mid"
\t\telse:
\t\t\tlane = "clash" if team == Config.Team.PLAYER else "farm"

\t\t# 如果该分路高地被摧毁，替换为超级兵
\t\tif high_tower_destroyed[1-team].get(lane, false) and type in ["siege"]:
\t\t\ttype = "super"
\t\t\tui.show_kill_feed("超级兵",team,"出动！")
'''

t = t[:start] + new + t[end:]
p.write_text(t, 'utf-8')
print('Done')
