import pathlib
TAB = chr(9)

p = pathlib.Path(r'C:\Users\18749\Documents\honor-king\ai\HeroAI.gd')
t = p.read_text('utf-8')

anchor = 'func _assign_lane():'
idx = t.find(anchor)
# Find from match to the end of state assignment
start = t.find('match hero.role:', idx)
end = t.find('has_respawned_recently', start)

old = t[start:end]
print(f'Replacing from {start} to {end}:')
print(repr(old))

new = TAB + '''match hero.role:
''' + TAB + TAB + '''"射手": lane = AiConfig.Lane.FARM
''' + TAB + TAB + '''"法师": lane = AiConfig.Lane.MID
''' + TAB + TAB + '''"刺客": lane = AiConfig.Lane.JUNGLE ; _is_natural_jungler = true
''' + TAB + TAB + '''"战士": lane = AiConfig.Lane.CLASH
''' + TAB + TAB + '''"坦克": lane = AiConfig.Lane.CLASH
''' + TAB + TAB + '''"辅助": lane = AiConfig.Lane.FARM
''' + TAB + TAB + '''_: lane = randi() % 4
''' + TAB + '''jungle_kill_count = 0
''' + TAB

t = t[:start] + new + t[end:]
p.write_text(t, 'utf-8')
print('Done')
