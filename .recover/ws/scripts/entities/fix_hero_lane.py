import pathlib
TAB = chr(9)

p = pathlib.Path(r'C:\Users\18749\Documents\honor-king\ai\HeroAI.gd')
t = p.read_text('utf-8')

anchor = 'func _assign_lane():'
idx = t.find(anchor)

start2 = t.find(TAB + 'var is_blue = hero.team == Config.Team.PLAYER\n' + TAB + 'match hero.role:', idx)
if start2 < 0:
    print('NOT FOUND')
    print(repr(t[idx:idx+350]))
else:
    end2 = t.find(TAB + 'jungle_kill_count = 0', start2)
    old2 = t[start2:end2]
    print(f'Found at {start2}-{end2}, len={len(old2)}')

    new2 = 'match hero.role:\n' + TAB + TAB + '"射手": lane = AiConfig.Lane.FARM\n' + TAB + TAB + '"法师": lane = AiConfig.Lane.MID\n' + TAB + TAB + '"刺客": lane = AiConfig.Lane.JUNGLE ; _is_natural_jungler = true\n' + TAB + TAB + '"战士": lane = AiConfig.Lane.CLASH\n' + TAB + TAB + '"坦克": lane = AiConfig.Lane.CLASH\n' + TAB + TAB + '"辅助": lane = AiConfig.Lane.FARM\n' + TAB + TAB + '_: lane = randi() % 4\n' + TAB

    t = t[:start2] + new2 + t[end2:]
    p.write_text(t, 'utf-8')
    print('Done')
