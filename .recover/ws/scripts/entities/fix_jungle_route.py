"""Fix JungleStrategy: randomize starting half and use phase-cycle array."""

import pathlib
path = pathlib.Path(r'C:\Users\18749\Documents\honor-king\ai\JungleStrategy.gd')
text = path.read_text('utf-8')
mods = 0

# ============================================================
# Step 1: Add _phase_cycle and _phase_index member variables
# ============================================================
old_vars = 'var game_time: float = 0.0'
new_vars = '''var _phase_cycle: Array = []       # 阶段循环序列
var _phase_index: int = 0            # 当前阶段在循环中的索引
var game_time: float = 0.0'''

if old_vars in text and '_phase_cycle' not in text:
    text = text.replace(old_vars, new_vars, 1)
    mods += 1
    print('Step 1 OK: Added phase cycle variables')

# ============================================================
# Step 2: Modify _init() to randomize starting half and init cycle
# ============================================================
old_init = '''func _init(p_hero: Hero, p_perception: AiPerception) -> void:
\thero = p_hero
\tperception = p_perception
\tassigned_lane = AiConfig.Lane.BOT if hero.team == Config.Team.PLAYER else AiConfig.Lane.TOP'''

new_init = '''func _init(p_hero: Hero, p_perception: AiPerception) -> void:
\thero = p_hero
\tperception = p_perception
\tassigned_lane = AiConfig.Lane.BOT if hero.team == Config.Team.PLAYER else AiConfig.Lane.TOP
\t# 随机选择路线：BOT→MID→TOP→LANE 或 TOP→MID→BOT→LANE
\tif randf() < 0.5:
\t\t_phase_cycle = [JunglePhase.BOT_HALF, JunglePhase.MID, JunglePhase.TOP_HALF, JunglePhase.LANE]
\telse:
\t\t_phase_cycle = [JunglePhase.TOP_HALF, JunglePhase.MID, JunglePhase.BOT_HALF, JunglePhase.LANE]
\tcurrent_phase = _phase_cycle[0]
\t_phase_index = 0'''

if old_init in text:
    text = text.replace(old_init, new_init, 1)
    mods += 1
    print('Step 2 OK: Randomized jungle starting half')
else:
    print('FAILED Step 2: old_init not found')
    idx = text.find('func _init(p_hero: Hero')
    if idx >= 0:
        print(f'  Found at {idx}: {repr(text[idx:idx+120])}')

# ============================================================
# Step 3: Replace _advance_phase() with cycle-based version
# ============================================================
old_advance = '''func _advance_phase() -> void:
\tmatch current_phase:
\t\tJunglePhase.BOT_HALF:
\t\t\tcurrent_phase = JunglePhase.MID
\t\t\tjungle_mode = false
\t\tJunglePhase.MID:
\t\t\tcurrent_phase = JunglePhase.TOP_HALF
\t\tJunglePhase.TOP_HALF:
\t\t\t# 随机选择上路或下路
\t\t\tassigned_lane = AiConfig.Lane.TOP if randf() < 0.5 else AiConfig.Lane.BOT
\t\t\tcurrent_phase = JunglePhase.LANE
\t\t\tjungle_mode = false
\t\tJunglePhase.LANE:
\t\t\tcurrent_phase = JunglePhase.BOT_HALF'''

new_advance = '''func _advance_phase() -> void:
\t_phase_index = (_phase_index + 1) % _phase_cycle.size()
\tcurrent_phase = _phase_cycle[_phase_index]
\tjungle_mode = false
\t# 进入LANE阶段时随机选择上路或下路
\tif current_phase == JunglePhase.LANE:
\t\tassigned_lane = AiConfig.Lane.TOP if randf() < 0.5 else AiConfig.Lane.BOT'''

if old_advance in text:
    text = text.replace(old_advance, new_advance, 1)
    mods += 1
    print('Step 3 OK: Replaced _advance_phase() with cycle-based version')
else:
    print('FAILED Step 3: old_advance not found')
    idx = text.find('func _advance_phase()')
    if idx >= 0:
        print(f'  Found at {idx}: {repr(text[idx:idx+250])}')

# ============================================================
# Write
# ============================================================
path.write_text(text, 'utf-8')
print(f'\nTotal modifications: {mods}')
