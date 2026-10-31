"""Swap enemy waypoint names + fix all comments to correct lane."""
import pathlib

path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\scripts\core\BattleManager.gd')
text = path.read_text('utf-8')
mods = 0

# Step 1: Swap the two enemy variable names via temp name
text = text.replace('enemy_waypoints_farm', 'enemy_waypoints_TEMP')
text = text.replace('enemy_waypoints_clash', 'enemy_waypoints_farm')
text = text.replace('enemy_waypoints_TEMP', 'enemy_waypoints_clash')
mods += 6  # 3 declarations + 3 references
print('Step 1: Swapped enemy_waypoints_farm <-> enemy_waypoints_clash')

# Step 2: Fix comments in enemy_waypoints_farm (now the 发育路 path)
# Enemy 下路 towers (right edge x≈55) + Player 上路 towers (top edge z≈55) = 发育路
# Currently has no comments (just raw coords)
old_farm = '''var enemy_waypoints_farm = [

		Vector3(55,0,-35),
		Vector3(56,0,-15),
		Vector3(58,0,28),
		Vector3(28,0,58),
		Vector3(-15,0,56),
		Vector3(-35,0,55),
		Vector3(-53,0,53)
	]'''

new_farm = '''var enemy_waypoints_farm = [
		 # 敌方水晶
		Vector3(55,0,-35),      # 敌方发育路高地塔
		Vector3(56,0,-15),      # 敌方发育路二塔
		Vector3(58,0,28),       # 敌方发育路外塔
		Vector3(28,0,58),       # 己方发育路外塔
		Vector3(-15,0,56),      # 己方发育路二塔
		Vector3(-35,0,55),      # 己方发育路高地塔
		Vector3(-53,0,53)       # 玩家水晶
	]'''

if old_farm in text:
    text = text.replace(old_farm, new_farm)
    mods += 1
    print('Step 2: Fixed enemy_waypoints_farm comments → 发育路')
else:
    print('Step 2 FAILED: old_farm block not matched')

# Step 3: Fix comments in enemy_waypoints_clash (now the 对抗路 path)
# Enemy 上路 towers (bottom edge z≈-55) + Player 下路 towers (left edge x≈-55) = 对抗路
old_clash = '''var enemy_waypoints_clash = [
		 # 敌方水晶
		Vector3(35,0,-55),      # 敌方对抗路高地塔
		Vector3(15,0,-56),      # 敌方对抗路二塔
		Vector3(-28,0,-58),     # 敌方对抗路外塔
		Vector3(-58,0,-28),     # 对抗路外塔
		Vector3(-56,0,15),      # 对抗路二塔
		Vector3(-55,0,35),      # 对抗路高地塔
		Vector3(-53,0,53)       # 玩家水晶
	]'''

new_clash = '''var enemy_waypoints_clash = [
		 # 敌方水晶
		Vector3(35,0,-55),      # 敌方对抗路高地塔
		Vector3(15,0,-56),      # 敌方对抗路二塔
		Vector3(-28,0,-58),     # 敌方对抗路外塔
		Vector3(-58,0,-28),     # 己方对抗路外塔
		Vector3(-56,0,15),      # 己方对抗路二塔
		Vector3(-55,0,35),      # 己方对抗路高地塔
		Vector3(-53,0,53)       # 玩家水晶
	]'''

if old_clash in text:
    text = text.replace(old_clash, new_clash)
    mods += 1
    print('Step 3: Fixed enemy_waypoints_clash comments → 对抗路')
else:
    print('Step 3 FAILED: old_clash block not matched')
    # Debug: find the actual text
    idx = text.find('var enemy_waypoints_clash')
    if idx >= 0:
        print(f'  Found at {idx}: {repr(text[idx:idx+300])}')

# Step 4: Fix the section comment above enemy waypoints
old_section = '# 敌方小兵路径（从敌方水晶出发，镜像路径，顺序为：敌方水晶 → 敌方高地 → 敌方二塔 → 敌方外塔 → 玩家外塔 → 玩家二塔 → 玩家高地 → 玩家水晶）\nvar enemy_waypoints_clash'
new_section = '# 敌方小兵路径（从敌方水晶出发，镜像路径）——对抗路(上)\nvar enemy_waypoints_clash'

if old_section in text:
    text = text.replace(old_section, new_section)
    mods += 1
    print('Step 4: Fixed section comment')
else:
    print('Step 4: section comment not found (may be fine)')

path.write_text(text, 'utf-8')
print(f'\nTotal: {mods}')
