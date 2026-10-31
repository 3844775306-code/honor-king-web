"""Fix remaining top/bot references in BattleManager.gd."""
import pathlib

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
mods = 0

# Dictionary keys
for old, new, label in [
    ('"top": bool, "mid": bool, "bot": bool', '"farm": bool, "mid": bool, "clash": bool', 'dict comment'),
    ('"top": false, "mid": false, "bot": false', '"farm": false, "mid": false, "clash": false', 'dict defaults'),
    # Variable names
    ('player_waypoints_top', 'player_waypoints_farm', 'var top'),
    ('player_waypoints_bot', 'player_waypoints_clash', 'var bot'),
    ('enemy_waypoints_top', 'enemy_waypoints_farm', 'var enemy top'),
    ('enemy_waypoints_bot', 'enemy_waypoints_clash', 'var enemy bot'),
    # String values
    ('lane = "top"', 'lane = "farm"', 'string top'),
    ('lane = "bot"', 'lane = "clash"', 'string bot'),
]:
    c = text.count(old)
    if c:
        text = text.replace(old, new)
        mods += c
        print(f'{label}: {c}')

path.write_text(text, 'utf-8')
print(f'\nTotal: {mods}')
