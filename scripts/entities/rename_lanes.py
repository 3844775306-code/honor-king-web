"""Rename lanes: 上路→发育路(FARM), 下路→对抗路(CLASH), 中路 unchanged."""
import pathlib, re

BASE = pathlib.Path(r'C:\Users\18749\Documents\honor-king')
mods = 0

def apply(path, old, new, label):
    global mods
    t = path.read_text('utf-8')
    c = t.count(old)
    if c:
        t = t.replace(old, new)
        path.write_text(t, 'utf-8')
        mods += c
        print(f'  {label}: {c} occurrence(s)')
    else:
        print(f'  {label}: 0 (skip)')

# ============================================================
# File 1: AiConfig.gd — enum definition
# ============================================================
print('\n[1] ai/AiConfig.gd')
p = BASE / 'ai/AiConfig.gd'
apply(p,
    'enum Lane { TOP, MID, BOT, JUNGLE }',
    'enum Lane { FARM, MID, CLASH, JUNGLE }',
    'enum Lane rename')

# ============================================================
# File 2: JungleStrategy.gd — phase enum + all references + comments
# ============================================================
print('\n[2] ai/JungleStrategy.gd')
p = BASE / 'ai/JungleStrategy.gd'
apply(p, 'JunglePhase { BOT_HALF,  TOP_HALF, LANE }',
         'JunglePhase { FARM_HALF,  CLASH_HALF, LANE }', 'enum JunglePhase')
apply(p, 'BOT_HALF', 'FARM_HALF', 'BOT_HALF→FARM_HALF')
apply(p, 'TOP_HALF', 'CLASH_HALF', 'TOP_HALF→CLASH_HALF')
apply(p, 'AiConfig.Lane.TOP', 'AiConfig.Lane.FARM', 'Lane.TOP→FARM')
apply(p, 'AiConfig.Lane.BOT', 'AiConfig.Lane.CLASH', 'Lane.BOT→CLASH')
# Chinese comments
apply(p, '下半野区', '发育路半区', 'comment: 下半野区')
apply(p, '上半野区', '对抗路半区', 'comment: 上半野区')
apply(p, '上路/下路', '发育路/对抗路', 'comment: 上路/下路')

# ============================================================
# Files 3-7,9: All AI files — Lane.TOP→FARM, Lane.BOT→CLASH
# ============================================================
ai_files = [
    ('ai/AiCoordinator.gd', [
        ('上路默认1人', '发育路默认1人'),
        ('下路默认2人(射手+辅助)', '对抗路默认2人(射手+辅助)'),
    ]),
    ('ai/HeroAI.gd', []),
    ('ai/LaneStrategy.gd', []),
    ('ai/TeamTactics.gd', []),
    ('ai/perception/AiPerception.gd', [
        ('上下路血包', '发育路/对抗路血包'),
    ]),
]

for fname, extra_comments in ai_files:
    print(f'\n[{fname}]')
    p = BASE / fname
    for old, new in [('AiConfig.Lane.TOP', 'AiConfig.Lane.FARM'),
                      ('AiConfig.Lane.BOT', 'AiConfig.Lane.CLASH')]:
        apply(p, old, new, f'{old.split(".")[-1]} rename')
    for old_c, new_c in extra_comments:
        apply(p, old_c, new_c, f'comment: {old_c}')

# ============================================================
# File 8: UI_Manager.gd — display strings + enum refs
# ============================================================
print('\n[8] scripts/ui/UI_Manager.gd')
p = BASE / 'scripts/ui/UI_Manager.gd'
apply(p, 'AiConfig.Lane.TOP: lane_str = "TOP"',
         'AiConfig.Lane.FARM: lane_str = "发育路"', 'lane_str TOP')
apply(p, 'AiConfig.Lane.BOT: lane_str = "BOT"',
         'AiConfig.Lane.CLASH: lane_str = "对抗路"', 'lane_str BOT')

# ============================================================
# File 9: MiniMap.gd — comments + variable names
# ============================================================
print('\n[9] scripts/ui/MiniMap.gd')
p = BASE / 'scripts/ui/MiniMap.gd'
apply(p, '上路：大致', '发育路：大致', 'comment: 上路→发育路')
apply(p, 'lane_top_dist', 'lane_farm_dist', 'var: lane_top_dist')
apply(p, 'lane_bot_dist', 'lane_clash_dist', 'var: lane_bot_dist')

# ============================================================
# File 10: BattleManager.gd — comments only (many occurrences)
# ============================================================
print('\n[10] scripts/core/BattleManager.gd')
p = BASE / 'scripts/core/BattleManager.gd'

# Comment-only changes for Chinese lane names
comment_changes = [
    # Tower comments
    ('己方上路高地塔', '己方发育路高地塔'),
    ('己方上路二塔', '己方发育路二塔'),
    ('己方上路外塔', '己方发育路外塔'),
    ('己方下路高地塔', '己方对抗路高地塔'),
    ('己方下路二塔', '己方对抗路二塔'),
    ('己方下路外塔', '己方对抗路外塔'),
    ('敌方上路外塔', '敌方对抗路外塔'),
    ('敌方上路二塔', '敌方对抗路二塔'),
    ('敌方上路高地塔', '敌方对抗路高地塔'),
    ('敌方下路外塔', '敌方发育路外塔'),
    ('敌方下路二塔', '敌方发育路二塔'),
    ('敌方下路高地塔', '敌方发育路高地塔'),
    ('敌方下路外塔（敌方下路外塔坐标）', '敌方发育路外塔'),
    # Tower section header
    ('上路外塔、二塔、高地塔', '发育路外塔、二塔、高地塔'),
    ('下路外、二、高地', '对抗路外、二、高地'),
    ('敌方上路：对应玩家下路', '敌方对抗路：对应玩家发育路'),
    ('敌方下路：对应玩家上路', '敌方发育路：对应玩家对抗路'),
    ('玩家下路外塔', '对抗路外塔'),
    ('玩家下路二塔', '对抗路二塔'),
    ('玩家下路高地塔', '对抗路高地塔'),
    # Wall comments
    ('上路 蓝方', '发育路 蓝方'),
    ('上路 红方', '发育路 红方'),
    ('下路 蓝方', '对抗路 蓝方'),
    ('下路 红方', '对抗路 红方'),
    # High ground wall gaps
    ('上路[-', '发育路[-'),
    ('下路[-', '对抗路[-'),
    # Lane planes
    ('Vector3(-55,0,0), Vector2(16, 80))   # 上路', 'Vector3(-55,0,0), Vector2(16, 80))   # 对抗路'),
    ('Vector3(0,0,55), Vector2(80, 16)) # 下路', 'Vector3(0,0,55), Vector2(80, 16)) # 发育路'),
    ('Vector3(55,0,0), Vector2(16, 80))   # 上路', 'Vector3(55,0,0), Vector2(16, 80))   # 对抗路'),
    ('Vector3(0,0,-55), Vector2(80, 16)) # 下路', 'Vector3(0,0,-55), Vector2(80, 16)) # 发育路'),
]

for old_c, new_c in comment_changes:
    apply(p, old_c, new_c, f'comment: {old_c[:20]}...')

# Waypoint comment
apply(p, '# 玩家方小兵路径（从己方水晶出发，依次经过己方高地、二塔、外塔，再攻击敌方外塔、二塔、高地，最终到敌方水晶）',
         '# 玩家方小兵路径（从己方水晶出发，依次经过己方高地、二塔、外塔，再攻击敌方外塔、二塔、高地，最终到敌方水晶）——发育路(上)',
         'waypoint top comment')

print(f'\n=== Total modifications: {mods} ===')
