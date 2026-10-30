"""Fix the corrupted lane detection block."""
import pathlib
TAB = chr(9)

p = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
t = p.read_text('utf-8')

start_marker = TAB + '#print(line)'
end_marker = TAB + '# 获取动态属性'

start = t.find(start_marker)
end = t.find(end_marker)

if start < 0 or end < 0:
    # Try with different tab count
    start_marker = TAB + TAB + '#print(line)'
    start = t.find(start_marker)
    end_marker = TAB + TAB + '# 获取动态属性'
    end = t.find(end_marker)

if start < 0 or end < 0:
    print(f'ERROR: start={start}, end={end}')
    # Show context around spawn_single_minion
    idx = t.find('func spawn_single_minion(')
    print(repr(t[idx:idx+550]))
    exit(1)

old = t[start:end]
print(f'Start={start}, End={end}, old_len={len(old)}')

new = TAB + '''#print(line)
''' + TAB + '''# 判断分路（敌方坐标模式与玩家方镜像，需按队伍区分）
''' + TAB + '''var is_mid = abs(waypoints[0].x) == abs(waypoints[0].z)
''' + TAB + '''var lane = ""
''' + TAB + '''if abs(waypoints[0].x) < abs(waypoints[0].z):
''' + TAB + TAB + '''lane = "farm" if team == Config.Team.PLAYER else "clash"
''' + TAB + '''elif abs(waypoints[0].x) == abs(waypoints[0].z):
''' + TAB + TAB + '''lane = "mid"
''' + TAB + '''else:
''' + TAB + TAB + '''lane = "clash" if team == Config.Team.PLAYER else "farm"

''' + TAB + '''# 如果该分路高地被摧毁，替换为超级兵
''' + TAB + '''if high_tower_destroyed[1-team].get(lane, false) and type in ["siege"]:
''' + TAB + TAB + '''type = "super"
''' + TAB + TAB + '''ui.show_kill_feed("超级兵",team,"出动！")
'''

t = t[:start] + new + t[end:]
p.write_text(t, 'utf-8')
print('Done')
