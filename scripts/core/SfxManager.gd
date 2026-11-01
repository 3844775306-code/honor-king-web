extends Node
## SfxManager：全局音效/播报/音乐总控（autoload）。
## audio/ 下是 53 个双视角播报 mp3（00:42 批=我方/自己行动，01:20 批=敌方/受击/防御/失败）。
## 按击杀战报 desc + 敌我视角（actor_team 是否 PLAYER）映射播放：
##   我方英雄杀→我方声包（你击杀了一名敌人[本人]/一名敌人已被击杀[队友]），敌方英雄杀→敌方声包
##   （你被击杀[本人阵亡]/敌方击杀了一名英雄[队友阵亡]）；连杀/累计击杀档按击杀方取 我方/敌方双版本。
## 屏显文案不动（二连击破~五连绝世/大杀特杀~天下无双），音频就近映射到新包文件名。
## 单声道抢占：同一条已在响则不再叠播；更高优先级打断低优先级（第一滴血/五杀/终结 > 连杀 >
## 累计档 > 推塔/被摧毁 > 塔野杀 > 防御警报 > 单杀 > 开局）。
## 延伸触发（六杀~十杀双视角走战报 desc；秀操作/团灭类由 host 模拟直接 play_announce 广播）：
##   十杀>九杀>…>六杀（250~270）> 完美团战(我方团灭敌方)235 > 关键抢夺(抢龙/暴君,含敌方双版本)215
##   > 团灭(我方被团灭)205 > 关键操作(群控≥3)170 > 漂亮的击杀(越塔/反杀/远程)150 > 漂亮辅助(救人)90。
## 所有触发均从战报语义走：host/离线 UI_Manager.show_kill_feed、client NetKillFeed 各自本地播放，
## 互不依赖网络；开局欢迎/准备/全军出击由 host BattleManager 用 announce_chain 触发并经广播
## 转发（client NetKillFeed 收到 SFX:: 前缀剥离后本地播放、不画横幅）；胜利/失败 host 在
## crystal_destroyed 播、client 在 NetResultPanel 收到结算广播时播。
## 主宰/暴君三连报（host 权威 BM 触发，同样 SFX:: 广播）：4:00 首次降临 epic_spawn → 9:30
## 存活清除 epic_gone（“如果还存在”）→ 非抢夺的击杀 epic_slain（关键抢夺走 215 档独立播报）。
## 独立 SFX 层（不占播报单通道，可叠播）：普攻合成音（仅本地玩家英雄）、m_sting/e_sting 击杀/推塔
## 抢先短音（我方得手 vs 我方受挫），在 play_feed 里按解析出的语音键归类触发。
## 程序化合成短音层（无外部素材）：技能施放/受击/阵亡/升级/回城/金币/商店，运行时用
## AudioStreamWAV 合成；世界音与 UI 音分池，世界音仅本地玩家英雄触发。
## 定制音色（动态键）：aa:英雄 普攻元素层 / sk:英雄:槽位:类型 技能施放 / hit:英雄:伤害类型
## 技能命中 / item:装备id:类别 装备主动；mn:兵种 / jn:动物 / tw:塔档位:阵营 世界攻击音。
##
## 通道总览（AudioBus，统一在 _ready 创建并 Send 到 Master）：
##   Announcer  播报单通道（mp3，优先级抢占）
##   SFX        世界短音池 5 路（普攻/技能/塔/兵/野/装备/抢断音）
##   UI         界面短音池 2 路（coin/buy/sell/ui_click，独立于战斗音）
##   Music      大厅/备战循环音乐（程序化 16s）
##   RecallLoop 回城循环（挂 SFX 总线，独立播放器）
## 对外入口：play_feed / play_announce / announce_chain / try_*_sfx / play_ui_sfx；
## 离开对局由 BattleManager/NetClientBattle._exit_tree 调 stop_all()。

const ANN_PREFIX := "SFX::"

# —— 播放通道：所有声音统一走 4 条 AudioBus，便于分别调音量/静音 ——
# Announcer=播报语音单通道；SFX=世界短音池；UI=界面短音池；Music=大厅环境音乐
const BUS_ANNOUNCER := "Announcer"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const BUS_MUSIC := "Music"
const BUS_NAMES := [BUS_ANNOUNCER, BUS_SFX, BUS_UI, BUS_MUSIC]
const UI_SFX_KEYS := ["coin", "last_hit", "buy", "sell", "ui_click"]

# 通道/音量常量（dB）；-40 当作淡出静音位
const VOL_DB_OFF := -40.0
const VOL_DB_MUSIC := -7.0
const VOL_DB_RECALL := -2.0
const VOL_DB_SYNTH_BOOST := 5.0
const WORLD_POOL_SIZE := 5
const UI_POOL_SIZE := 2

# 音频键 -> 文件路径（新包双视角文件名）
const _PATHS := {
	# —— 开局（我方/中立）——
	"welcome":      "res://audio/01_开局欢迎.mp3",
	"ready":        "res://audio/02_开局准备.mp3",
	"attack":       "res://audio/03_全军出击.mp3",
	# —— 全局事件 ——
	"first_blood":  "res://audio/04_第一滴血.mp3",
	"shutdown":     "res://audio/13_终结.mp3",
	"env_kill":     "res://audio/13_英雄被小兵或防御塔、野怪击杀.mp3",
	# —— 我方行动（00:42 批）——
	"m_kill_you":   "res://audio/06_你击杀了一名敌人.mp3",
	"m_kill_ally":  "res://audio/05_一名敌人已被击杀.mp3",
	"m_double":     "res://audio/07_双杀.mp3",
	"m_triple":     "res://audio/08_三杀.mp3",
	"m_quad":       "res://audio/09_四杀.mp3",
	"m_penta":      "res://audio/10_五杀.mp3",
	"m_s3":         "res://audio/19_锋芒毕露.mp3",
	"m_s4":         "res://audio/20_无坚不摧.mp3",
	"m_s5":         "res://audio/21_不可阻挡.mp3",
	"m_s6":         "res://audio/横扫千军.mp3",
	"m_s7":         "res://audio/23_超神.mp3",
	"m_six":        "res://audio/14_六杀.mp3",
	"m_seven":      "res://audio/15_七杀.mp3",
	"m_eight":      "res://audio/16_八杀.mp3",
	"m_nine":       "res://audio/17_九杀.mp3",
	"m_ten":        "res://audio/18_十杀.mp3",
	"nice_kill":    "res://audio/24_漂亮的击杀（塔下反杀、百步穿杨）.mp3",
	"group_cc":     "res://audio/25_关键操作（关键群控）.mp3",
	"perfect_fight":"res://audio/26_完美团战.mp3",
	"assist_play":  "res://audio/27_漂亮辅助（辅助的技能使我方英雄免于死亡或使我方英雄完成击杀）.mp3",
	"steal":        "res://audio/28_关键抢夺（从敌方队伍手中抢杀主宰或暴君）.mp3",
	"my_push":      "res://audio/30_我方推塔.mp3",
	"victory":      "res://audio/31_胜利.mp3",
	# —— 敌方/受击（01:20 批）——
	"e_kill_you":   "res://audio/02_你被击杀.mp3",
	"e_kill_ally":  "res://audio/01_敌方击杀了一名英雄.mp3",
	"e_double":     "res://audio/03_敌方双杀.mp3",
	"e_triple":     "res://audio/04_敌方三杀.mp3",
	"e_quad":       "res://audio/05_敌方四杀.mp3",
	"e_penta":      "res://audio/06_敌方五杀.mp3",
	"e_s3":         "res://audio/15_敌方锋芒毕露.mp3",
	"e_s5":         "res://audio/16_敌方不可阻挡.mp3",
	"e_s4":         "res://audio/17_敌方无坚不摧.mp3",
	"e_s6":         "res://audio/18_敌方横扫千军.mp3",
	"e_s7":         "res://audio/19_敌方超神.mp3",
	"e_six":        "res://audio/07_敌方六杀.mp3",
	"e_seven":      "res://audio/08_敌方七杀.mp3",
	"e_eight":      "res://audio/09_敌方八杀.mp3",
	"e_nine":       "res://audio/10_敌方九杀.mp3",
	"e_ten":        "res://audio/11_敌方十杀.mp3",
	"wiped":        "res://audio/12_团灭.mp3",
	"e_steal_a":    "res://audio/20_敌方关键抢夺.mp3",
	"e_steal_b":    "res://audio/21_敌方关键抢夺.mp3",
	"tower_lost":   "res://audio/23_我方防御塔被摧毁.mp3",
	"tower_warn":   "res://audio/22_我方防御塔正在被攻击.mp3",
	"high_warn":    "res://audio/24_我方高地防御塔正在被攻击.mp3",
	"crystal_warn": "res://audio/26_我方水晶正在被攻击.mp3",
	"defeat":       "res://audio/27_失败.mp3",
	# —— 主宰/暴君（host 权威触发）——
	"epic_spawn":   "res://audio/主宰暴君降临（4分钟时播放）.mp3",
	"epic_slain":   "res://audio/主宰暴君被击败.mp3",
	"epic_gone":    "res://audio/9分30秒主宰暴君消失的音效（如果还存在）.mp3",
}

# 独立 SFX 层（不走播报优先级通道）：击杀/推塔抢先短音 + 塔爆炸
# 塔开火/普攻一律使用合成音；原「塔攻击小兵音效.mp3」与旧「普攻音效.mp3」内容相同，已移除。
const _SFX_PATHS := {
	"m_sting":    "res://audio/摧毁敌方塔或击杀敌方英雄最先播放的音效.mp3",
	"e_sting":    "res://audio/我方塔被摧毁或英雄被击杀最先播放的音效.mp3",
	"tower_boom": "res://audio/塔被摧毁的爆炸音效.mp3",
}

# 程序化合成短音（无外部文件）：kind=sweep 频率上/下滑，thump 低频闷响，bell 金属短鸣，
# arp 琶音，pad 铺底，fan 回旋气声，meteor 流星下落+落地。振幅/衰减按听感配好，别盖过播报。
const _SYNTH := {
	# —— 技能施放（仅保留英雄专属覆盖；其余技能走 sk: 动态键）——
	"cast_fan":     {"kind": "fan", "dur": 0.46, "vol": 0.34},
	"cast_meteor":  {"kind": "meteor", "dur": 0.95, "vol": 0.38},
	# —— 英雄状态/UI ——
	"hurt":     {"kind": "thump", "f0": 190.0, "f1": 65.0, "dur": 0.14, "vol": 0.34, "decay": 3.6, "noise": 0.12},
	"death":    {"kind": "sweep", "f0": 620.0, "f1": 90.0, "dur": 0.60, "vol": 0.30, "decay": 1.8, "noise": 0.06},
	"levelup":  {"kind": "arp", "notes": [523.25, 659.25, 783.99, 1046.5], "step": 0.075, "dur": 0.38, "vol": 0.30},
	"heal":     {"kind": "arp", "notes": [659.25, 880.0, 1046.5], "step": 0.07, "dur": 0.36, "vol": 0.27},
	"coin":     {"kind": "metal", "f0": 1975.5, "dur": 0.30, "vol": 0.32},
	# 补刀：更短、更高、起音带高频点击，和普通金币音区分开
	"last_hit": {"kind": "crisp_coin", "f0": 2637.0, "dur": 0.18, "vol": 0.34},
	"buy":      {"kind": "bell", "f0": 880.0, "dur": 0.16, "vol": 0.22, "decay": 5.0, "harmonic": 1.5},
	"sell":     {"kind": "bell", "f0": 587.33, "dur": 0.16, "vol": 0.20, "decay": 6.0, "harmonic": 1.5},
	"ui_click": {"kind": "bell", "f0": 1320.0, "dur": 0.06, "vol": 0.15, "decay": 8.0, "harmonic": 2.0},
	# 技能冷却结束“就绪”：两颗高音铃短促上行，音量压得比点击更低，避免频繁刺耳
	"skill_ready": {"kind": "arp", "notes": [1046.5, 1567.98], "step": 0.055, "dur": 0.16, "vol": 0.16},
	"recall":   {"kind": "sweep", "f0": 330.0, "f1": 660.0, "dur": 0.70, "vol": 0.22, "decay": 1.4, "noise": 0.04},
	"crit":     {"kind": "bell", "f0": 1568.0, "dur": 0.13, "vol": 0.25, "decay": 5.0, "harmonic": 2.01, "noise": 0.08},
	# —— 防御塔 / 主宰先锋 ——
	"tower_down_enemy":    {"kind": "collapse", "dur": 1.05, "vol": 0.40, "bright": true},
	"tower_down_own":      {"kind": "collapse", "dur": 1.20, "vol": 0.40, "bright": false},
	"vanguard_down_enemy": {"kind": "beast", "dur": 0.85, "vol": 0.40, "bright": true},
	"vanguard_down_own":   {"kind": "beast", "dur": 0.85, "vol": 0.40, "bright": false},
}

# 同类短音最小间隔（ms）：受击/金币/施法连续触发时防糊成一片
const _SFX_MIN_GAP := {"hurt": 320, "coin": 90, "last_hit": 65, "heal": 400, "crit": 140, "ui_click": 45, "skill_ready": 200}

# 英雄专属技能音色（其余按元素+技能类型动态合成）：小乔 Q 回旋扇 / R 流星
const _SKILL_SFX_OVERRIDE := {
	"小乔": {0: "cast_fan", 2: "cast_meteor"},
}

# 英雄元素 → 音色底子（与 Vfx.HERO_ELEMENT 对应）：动态合成普攻/技能/命中用
const _EL_SFX := {
	"fire":      {"kind": "sweep", "f0": 380.0, "f1": 980.0, "noise": 0.22, "harmonic": 2.0},
	"ice":       {"kind": "bell", "f0": 1010.0, "harmonic": 2.01},
	"water":     {"kind": "sweep", "f0": 300.0, "f1": 760.0, "noise": 0.10, "harmonic": 1.5},
	"lightning": {"kind": "arp", "notes": [880.0, 1320.0], "step": 0.035},
	"shadow":    {"kind": "sweep", "f0": 700.0, "f1": 190.0, "noise": 0.12},
	"holy":      {"kind": "bell", "f0": 784.0, "harmonic": 2.0},
	"blade":     {"kind": "sweep", "f0": 900.0, "f1": 2100.0, "noise": 0.18},
	"wind":      {"kind": "sweep", "f0": 520.0, "f1": 1300.0, "noise": 0.30},
	"earth":     {"kind": "thump", "f0": 160.0, "f1": 45.0, "noise": 0.20},
	"arcane":    {"kind": "bell", "f0": 660.0, "harmonic": 2.0},
}

# 元素音阶（技能/护盾/增益动态合成用）
const _EL_NOTES := {
	"fire": [392.0, 523.25, 659.25],
	"ice": [659.25, 880.0, 1318.5],
	"water": [440.0, 554.37, 659.25],
	"lightning": [880.0, 1174.66, 1567.98],
	"shadow": [370.0, 466.16, 554.37],
	"holy": [523.25, 659.25, 783.99],
	"blade": [587.33, 880.0, 1174.66],
	"wind": [659.25, 783.99, 987.77],
	"earth": [261.63, 329.63, 392.0],
	"arcane": [523.25, 659.25, 880.0],
}

# 装备主动类别 → 音色
const _ITEM_SFX := {
	"df":     {"kind": "pad", "notes": [392.0, 523.25, 659.25], "dur": 0.50, "vol": 0.26},
	"haste":  {"kind": "sweep", "f0": 320.0, "f1": 1280.0, "dur": 0.24, "vol": 0.26, "noise": 0.12},
	"range":  {"kind": "bell", "f0": 1174.66, "dur": 0.20, "vol": 0.24, "harmonic": 2.0},
	"thorn":  {"kind": "thump", "f0": 150.0, "f1": 60.0, "dur": 0.20, "vol": 0.28, "noise": 0.18},
	"blood":  {"kind": "thump", "f0": 120.0, "f1": 40.0, "dur": 0.30, "vol": 0.30, "noise": 0.15},
	"ice":    {"kind": "bell", "f0": 1318.5, "dur": 0.26, "vol": 0.24, "noise": 0.06},
	"stasis": {"kind": "bell", "f0": 987.77, "dur": 0.30, "vol": 0.24, "harmonic": 2.01},
}

# 小兵攻击（按兵种）
const _MINION_SFX := {
	"melee":  {"kind": "thump", "f0": 170.0, "f1": 70.0, "dur": 0.11, "vol": 0.24, "decay": 4.5, "noise": 0.10},
	"ranged": {"kind": "sweep", "f0": 900.0, "f1": 1500.0, "dur": 0.10, "vol": 0.18, "decay": 5.0, "noise": 0.05},
	"siege":  {"kind": "thump", "f0": 90.0, "f1": 42.0, "dur": 0.22, "vol": 0.22, "decay": 3.2, "noise": 0.15},
	"super":  {"kind": "thump", "f0": 230.0, "f1": 60.0, "dur": 0.16, "vol": 0.24, "decay": 3.4, "noise": 0.24},
	"dragon": {"kind": "sweep", "f0": 140.0, "f1": 460.0, "dur": 0.20, "vol": 0.22, "decay": 3.6, "noise": 0.14},
	"storm":  {"kind": "sweep", "f0": 220.0, "f1": 900.0, "dur": 0.20, "vol": 0.22, "decay": 3.6, "noise": 0.24},
	"shadow_dragon": {"kind": "sweep", "f0": 120.0, "f1": 720.0, "dur": 0.22, "vol": 0.24, "decay": 3.4, "noise": 0.24},
}

# 野怪/动物攻击
const _JUNGLE_SFX := {
	"pig":     {"kind": "thump", "f0": 210.0, "f1": 85.0, "dur": 0.14, "vol": 0.19, "decay": 4.0, "noise": 0.12},
	"bird":    {"kind": "arp", "notes": [1250.0, 1650.0], "step": 0.045, "dur": 0.10, "vol": 0.15},
	"worm":    {"kind": "thump", "f0": 130.0, "f1": 50.0, "dur": 0.18, "vol": 0.21, "decay": 3.6, "noise": 0.20},
	"wolf":    {"kind": "sweep", "f0": 380.0, "f1": 900.0, "dur": 0.16, "vol": 0.21, "decay": 3.8, "noise": 0.18},
	"lizard":  {"kind": "sweep", "f0": 650.0, "f1": 320.0, "dur": 0.14, "vol": 0.18, "decay": 4.0, "noise": 0.28},
	"monkey":  {"kind": "arp", "notes": [600.0, 760.0], "step": 0.05, "dur": 0.12, "vol": 0.16},
	"red_buff": {"kind": "sweep", "f0": 200.0, "f1": 720.0, "dur": 0.18, "vol": 0.21, "decay": 3.6, "noise": 0.20},
	"blue_buff": {"kind": "bell", "f0": 880.0, "dur": 0.18, "vol": 0.19, "harmonic": 2.01, "noise": 0.05},
	"tyrant":  {"kind": "thump", "f0": 95.0, "f1": 40.0, "dur": 0.30, "vol": 0.26, "decay": 2.8, "noise": 0.14},
	"shadow_tyrant": {"kind": "thump", "f0": 80.0, "f1": 35.0, "dur": 0.32, "vol": 0.28, "decay": 2.6, "noise": 0.18},
	"dragon":  {"kind": "sweep", "f0": 150.0, "f1": 520.0, "dur": 0.30, "vol": 0.22, "decay": 2.8, "noise": 0.18},
	"shadow_dragon": {"kind": "sweep", "f0": 120.0, "f1": 480.0, "dur": 0.32, "vol": 0.24, "decay": 2.8, "noise": 0.22},
	"storm_dragon": {"kind": "sweep", "f0": 110.0, "f1": 900.0, "dur": 0.34, "vol": 0.28, "decay": 2.6, "noise": 0.30},
	"spatial_spirit": {"kind": "bell", "f0": 1200.0, "dur": 0.18, "vol": 0.14, "harmonic": 2.0},
	"river_spirit": {"kind": "bell", "f0": 1000.0, "dur": 0.18, "vol": 0.14, "harmonic": 2.0},
}

# 防御塔攻击（按塔档位；阵营再做微变调）
const _TOWER_SFX := {
	"outer":   {"kind": "sweep", "f0": 520.0, "f1": 1400.0, "dur": 0.16, "vol": 0.26, "decay": 4.0, "noise": 0.05},
	"inner":   {"kind": "sweep", "f0": 620.0, "f1": 1600.0, "dur": 0.15, "vol": 0.27, "decay": 4.0, "noise": 0.06},
	"high":    {"kind": "sweep", "f0": 740.0, "f1": 1850.0, "dur": 0.14, "vol": 0.28, "decay": 4.0, "noise": 0.06},
	"crystal": {"kind": "sweep", "f0": 300.0, "f1": 1200.0, "dur": 0.24, "vol": 0.26, "decay": 3.0, "noise": 0.08},
}

# 按 play_feed 解析出的语音键归类短音：我方得手（敌英雄被击杀/推掉敌塔）→ m_sting，反受挫 → e_sting
const _STING_POS := ["m_kill_you", "m_kill_ally", "m_double", "m_triple", "m_quad", "m_penta",
		"m_s3", "m_s4", "m_s5", "m_s6", "m_s7", "m_six", "m_seven", "m_eight", "m_nine", "m_ten", "my_push"]
const _STING_NEG := ["e_kill_you", "e_kill_ally", "e_double", "e_triple", "e_quad", "e_penta",
		"e_s3", "e_s4", "e_s5", "e_s6", "e_s7", "e_six", "e_seven", "e_eight", "e_nine", "e_ten", "tower_lost"]

const _PRIORITY := {
	"victory":      400, "defeat": 400,
	"first_blood":  260,
	"m_ten":        270, "e_ten": 270,
	"m_nine":       265, "e_nine": 265,
	"m_eight":      260, "e_eight": 260,
	"m_seven":      255, "e_seven": 255,
	"m_six":        250, "e_six": 250,
	"m_penta":      240, "e_penta": 240,
	"perfect_fight":235,
	"shutdown":     220,
	"steal":        215, "e_steal_a": 215, "e_steal_b": 215,
	"wiped":        205,
	"m_quad":       180, "e_quad": 180,
	"group_cc":     170,
	"m_triple":     150, "e_triple": 150,
	"nice_kill":    150,
	"m_double":     120, "e_double": 120,
	"m_s6":         110, "e_s6": 110, "m_s7": 110, "e_s7": 110,
	"m_s3":         100, "e_s3": 100, "m_s4": 100, "e_s4": 100,
	"m_s5":         100, "e_s5": 100,
	"my_push":       90, "tower_lost": 90, "assist_play": 90,
	"e_kill_you":    80,
	"epic_slain":    150,
	"epic_spawn":    130,
	"epic_gone":     120,
	"env_kill":      70,
	"tower_warn":    60, "high_warn": 60, "crystal_warn": 60,
	"m_kill_ally":   45, "m_kill_you": 45, "e_kill_ally": 45,
	"welcome":       20, "ready": 20, "attack": 20,
}

## 本地玩家的英雄名（client 接管时由 NetClientBattle 写入；host/离线走 BattleManager.hero 兜底）。
var own_name := ""

var _player: AudioStreamPlayer
var _loaded: Dictionary = {}
var _playing_key := ""
var _playing_prio := -1
var _chain_keys: Array = []
var _chain_token := 0
var _world_sfx: Array = []     # 世界短音池（独立于 UI，避免点击/买卖挤掉战斗音）
var _ui_sfx: Array = []        # 界面短音池
var _world_next := 0
var _ui_next := 0
var _sfx_loaded := {}
var _sfx_last: Dictionary = {}   # 短音上次播放时刻（ms），用于同类节流
var _own_hero_ref: Node3D = null   # 本地英雄节点缓存（塔音效距离判定用）
var _recall_loop: AudioStreamPlayer = null   # 回城引导循环音（独立于短音池）
var _recall_stream: AudioStreamWAV = null
var _recall_tw: Tween = null
var _recall_stopping := false
var _menu_music: AudioStreamPlayer = null   # 大厅/备战环境音乐（独立通道）
var _menu_stream: AudioStreamWAV = null
var _menu_tw: Tween = null

func _ready() -> void:
	_ensure_buses()
	_player = _make_player("Announcer", BUS_ANNOUNCER)
	_world_sfx = _make_pool("WorldSfx", WORLD_POOL_SIZE, BUS_SFX)
	_ui_sfx = _make_pool("UiSfx", UI_POOL_SIZE, BUS_UI)

func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _make_player(player_name: String, bus_name: String) -> AudioStreamPlayer:
	var sp := AudioStreamPlayer.new()
	sp.name = player_name
	sp.bus = bus_name
	add_child(sp)
	return sp

func _make_pool(prefix: String, count: int, bus_name: String) -> Array:
	var pool: Array = []
	for i in count:
		pool.append(_make_player("%s%d" % [prefix, i], bus_name))
	return pool

# —— 通道音量/静音：供设置面板或调试统一调用，避免各处直接改 volume_db ——
func set_channel_volume(channel: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(channel)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func get_channel_volume(channel: String) -> float:
	var idx := AudioServer.get_bus_index(channel)
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0

func set_channel_muted(channel: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(channel)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)

func is_channel_muted(channel: String) -> bool:
	var idx := AudioServer.get_bus_index(channel)
	return AudioServer.is_bus_mute(idx) if idx >= 0 else false

## 战报单点（host UI_Manager.show_kill_feed / client NetKillFeed）：按 desc+敌我视角解析音频键。
func play_feed(actor: String, actor_team: int, desc: String, victim: String, victim_team: int) -> void:
	if desc.begins_with(ANN_PREFIX):
		return
	var key := _resolve_key(actor, actor_team, desc, victim, victim_team)
	if key != "":
		# 战报语音（推塔/丢塔/连杀等）也要写进录像音频事件；此前只有 play_announce 打点，
		# play_feed 解析出的 tower_lost/my_push 等播报回放里完全不会出现。
		var _rrec_feed = get_tree().get_first_node_in_group("replay_recorder")
		if _rrec_feed != null:
			_rrec_feed.call("note_sfx", key, 0.0, true)
		_play(key)
		var sting := _sting_key_for(key)
		if sting != "":
			_play_sfx(sting)

# 击杀/推塔抢先短音（独立层，与播报叠播）：语音键归类
func _sting_key_for(key: String) -> String:
	if key in _STING_POS:
		return "m_sting"
	if key in _STING_NEG:
		return "e_sting"
	return ""

# 本地玩家英雄普攻出音（Hero._perform_attack 每刀调用，非本人直接忽略）
# 只用按英雄定制的合成普攻音（近战闷响 / 远程元素破风），不再播原 mp3 底音
func try_attack_sfx(hero_name: String, attack_range: float = 0.0) -> void:
	if hero_name == "" or hero_name != _own_display():
		return
	_play_sfx("aa:%s:%d" % [hero_name, int(attack_range)])

# 塔摧毁爆炸：距本地英雄 ≤26 才响；塔开火已改走 try_tower_attack_sfx 的合成层，
# 不再播放外部 mp3。塔战斗只在主机/离线跑，接管客户端为纯视觉。
func try_tower_sfx(what: String, tower_pos: Vector3) -> void:
	if what != "boom":
		return
	var h := _own_hero_node()
	if h == null:
		return
	if h.global_position.distance_to(tower_pos) > 26.0:
		return
	_play_sfx("tower_boom")

# 世界音距离闸：只保留本地英雄附近，避免远路刷屏
func _near_own(pos: Vector3, max_dist: float) -> bool:
	var h := _own_hero_node()
	return h != null and is_instance_valid(h) and h.health > 0.0 and h.global_position.distance_to(pos) <= max_dist

# 小兵攻击：按兵种定制（melee/ranged/siege/super/dragon/storm/shadow_dragon），≤20 才响
func try_minion_attack_sfx(minion_type: String, pos: Vector3) -> void:
	if _near_own(pos, 20.0):
		_play_sfx("mn:" + minion_type, -2.0)

# 野怪/动物攻击：猪/鸟/虫/狼/蜥蜴/猴/红蓝buff/暴君/主宰/龙王，≤20 才响
func try_jungle_attack_sfx(beast: String, pos: Vector3) -> void:
	if _near_own(pos, 20.0):
		_play_sfx("jn:" + beast, -1.0)

# 防御塔开火：只播塔档位(outer/inner/high/crystal)+阵营专属合成层，≤24 才响
func try_tower_attack_sfx(tower_team: int, tier: String, pos: Vector3) -> void:
	if not _near_own(pos, 24.0):
		return
	_play_sfx("tw:%s:%d" % [tier, tower_team])

# 防御塔被摧毁：本方/敌方两种音色（与爆炸 mp3 叠成"倒塌"），≤34 才响，远处靠播报
func try_tower_destroyed_sfx(tower_team: int, tower_pos: Vector3) -> void:
	var h := _own_hero_node()
	if h == null or h.global_position.distance_to(tower_pos) > 34.0:
		return
	_play_sfx("tower_down_own" if Config.is_ally(tower_team) else "tower_down_enemy")

# 主宰先锋/风暴先锋/暗影先锋被击杀：敌方=奖励音色，我方=低沉；≤34 才响
func try_vanguard_down_sfx(minion_team: int, pos: Vector3) -> void:
	var h := _own_hero_node()
	if h == null or h.global_position.distance_to(pos) > 34.0:
		return
	_play_sfx("vanguard_down_own" if Config.is_ally(minion_team) else "vanguard_down_enemy")

# —— 世界短音（仅本地玩家英雄；Hero/GameEntity 每帧都会调，内部按名字过滤）——
# 技能施放音：英雄专属音色 > 大招 > 技能类型（0指向/1范围/2增益/3线性/4位移/5多段/6护盾）
func try_skill_sfx(hero_name: String, slot: int, skill: Skill = null) -> void:
	if not _is_own(hero_name):
		return
	var stype := int(skill.type) if skill != null else 0
	_play_sfx(_skill_sfx_key(hero_name, slot, stype))

func _skill_sfx_key(hero_name: String, slot: int, skill_type: int) -> String:
	var ov: Dictionary = _SKILL_SFX_OVERRIDE.get(hero_name, {})
	if ov.has(slot):
		return str(ov[slot])
	# 无专属覆盖：按 英雄元素 + 类型/槽位 动态合成（每个英雄每个技能音色不同）
	return "sk:%s:%d:%d" % [hero_name, slot, skill_type]

# 受到伤害的闷响
func try_hurt_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("hurt")

# 阵亡下坠音
func try_death_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("death")

# 升级琶音
func try_levelup_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("levelup")

# 回城起手音
func try_recall_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("recall")

# 回城引导循环音：起手时开，回城完成/取消/死亡后停（Hero 调用，SfxManager 每帧兜底）
func start_recall_loop(hero_name: String) -> void:
	if not _is_own(hero_name):
		return
	if _recall_loop == null:
		_recall_loop = _make_player("RecallLoop", BUS_SFX)
	if _recall_loop.playing:
		return
	_recall_stopping = false
	if _recall_stream == null:
		_recall_stream = _build_recall_loop()
		_recall_loop.stream = _recall_stream
	if _recall_tw != null and _recall_tw.is_valid():
		_recall_tw.kill()
	_recall_loop.volume_db = VOL_DB_OFF
	_recall_loop.play()
	_recall_tw = create_tween()
	_recall_tw.tween_property(_recall_loop, "volume_db", VOL_DB_RECALL, 0.30)

func stop_recall_loop(hero_name: String = "") -> void:
	if hero_name != "" and not _is_own(hero_name):
		return
	if _recall_loop == null or not _recall_loop.playing or _recall_stopping:
		return
	_recall_stopping = true
	if _recall_tw != null and _recall_tw.is_valid():
		_recall_tw.kill()
	_recall_tw = create_tween()
	_recall_tw.tween_property(_recall_loop, "volume_db", VOL_DB_OFF, 0.18)
	_recall_tw.tween_callback(_recall_loop.stop)

# 兜底：英雄死亡/场景切换/回城被打断时，循环音不会一直挂着
func _process(_delta: float) -> void:
	if _recall_loop == null or not _recall_loop.playing:
		return
	var h := _own_hero_node()
	if h == null or not (h is Hero) or not (h as Hero).is_recalling:
		stop_recall_loop()

# 治疗音（恢复按钮/治疗术/吃血包，仅本地玩家）
func try_heal_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("heal")

# 技能命中：本地英雄的技能伤害落到目标（GameEntity.take_damage 调用，内部按 160ms 合并）
func try_skill_hit_sfx(hero_name: String, is_magic: bool) -> void:
	if _is_own(hero_name):
		_play_sfx("hit:%s:%s" % [hero_name, "m" if is_magic else "p"])

# 普攻暴击（暴击类装备/铭文触发）
func try_crit_sfx(hero_name: String) -> void:
	if _is_own(hero_name):
		_play_sfx("crit")

# 装备主动：item_id 唯一变调 + 类别音色（df/haste/range/thorn/blood/ice/stasis）
func try_item_active_sfx(hero_name: String, item_id: String, cat: String) -> void:
	var _rrec_item = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_item != null:
		_rrec_item.call("note_item_active", hero_name, item_id, cat)
	if _is_own(hero_name):
		_play_sfx("item:%s:%s" % [item_id, cat])

# 本地 UI 短音（金币/商店买卖）：key 只能取 _SYNTH 里的键
func play_ui_sfx(key: String) -> void:
	_play_sfx(key)

# 接管客户端本地施法音（client 为纯视觉，host 侧 Hero 回调不会在本地跑）
# sk_res = manifest 技能字典（含 type），按 host 同一套规则分档
func client_cast_sfx(slot: int, sk_res = null) -> void:
	var stype := 0
	if sk_res is Dictionary:
		stype = int(sk_res.get("type", 0))
	_play_sfx(_skill_sfx_key(_own_display(), slot, stype))

# 本地英雄节点（缓存；按 display_name 从 heroes 组找，own_name/BattleManager.hero 兜底）
func _own_hero_node() -> Node3D:
	if _own_hero_ref != null and is_instance_valid(_own_hero_ref):
		return _own_hero_ref
	_own_hero_ref = null
	var dn := _own_display()
	if dn == "":
		return null
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero and e.display_name == dn and e.health > 0:
			_own_hero_ref = e
			break
	return _own_hero_ref

# 独立 SFX 池：找空闲播放器，全忙则轮询顶替（不影响播报单通道）
func _play_sfx(key: String, vol_offset: float = 0.0) -> void:
	var _rrec_sfx = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_sfx != null:
		_rrec_sfx.call("note_sfx", key, vol_offset, false)
	var is_synth := _SYNTH.has(key) or key.find(":") >= 0
	# 同类短音节流（受击/金币/施法叠得太密会糊；技能命中 160ms 内合并）
	var gap: int = int(_SFX_MIN_GAP.get(key, 0))
	if gap <= 0 and key.begins_with("hit:"):
		gap = 160
	elif gap <= 0 and key.begins_with("sk:"):
		gap = 90
	elif gap <= 0 and key.begins_with("mn:"):
		gap = 250
	elif gap <= 0 and key.begins_with("jn:"):
		gap = 300
	if gap > 0:
		var now := Time.get_ticks_msec()
		if now - int(_sfx_last.get(key, -100000)) < gap:
			return
		_sfx_last[key] = now
	var stream: AudioStream = _sfx_stream(key)
	if stream == null:
		return
	var pool: Array = _ui_sfx if key in UI_SFX_KEYS else _world_sfx
	var sp := _free_sfx_player(pool)
	sp.stream = stream
	# 合成短音峰值比 mp3 低（实测 mp3 普攻 max≈-3.6dB），抬 5dB 对齐；再做轻微变调避免机械重复
	sp.volume_db = (VOL_DB_SYNTH_BOOST if is_synth else 0.0) + vol_offset
	sp.pitch_scale = randf_range(0.97, 1.03) if is_synth else 1.0
	sp.play()

# 取（并缓存）短音流：合成键优先（含 ":" 的动态键），其次 audio/ 文件
func _sfx_stream(key: String) -> AudioStream:
	var cached: AudioStream = _sfx_loaded.get(key)
	if cached != null:
		return cached
	var stream: AudioStream = null
	if _SYNTH.has(key):
		stream = _build_synth(key)
	elif key.find(":") >= 0:
		stream = _build_dynamic(key)
	elif _SFX_PATHS.has(key):
		var path: String = _SFX_PATHS[key]
		if ResourceLoader.exists(path):
			stream = load(path)
	if stream != null:
		_sfx_loaded[key] = stream
	return stream

func _free_sfx_player(pool: Array) -> AudioStreamPlayer:
	for s in pool:
		if not s.playing:
			var idle: AudioStreamPlayer = s
			return idle
	var next := _ui_next if pool == _ui_sfx else _world_next
	var fallback: AudioStreamPlayer = pool[next % pool.size()]
	if pool == _ui_sfx:
		_ui_next += 1
	else:
		_world_next += 1
	return fallback

# 回城引导循环：2s 无缝（所有分音都是 0.5Hz 整数倍，首尾相位连续）
func _build_recall_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := 2.0
	var n := int(dur * rate)
	var freqs := [110.0, 220.0, 261.5, 329.5, 440.0, 659.0]
	var gains := [0.22, 0.20, 0.16, 0.13, 0.10, 0.05]
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		for j in freqs.size():
			s += sin(TAU * freqs[j] * t) * gains[j]
		s *= 0.55 * (0.72 + 0.28 * sin(TAU * 0.5 * t))   # 音量 + 2s 一个呼吸周期
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	_pad_loop_tail(st, n)
	return st

# —— 大厅/备战界面环境音乐：16s 无缝循环（所有分音频率都是 1/16Hz 整数倍，首尾相位连续）——
func start_menu_music() -> void:
	if _menu_music == null:
		_menu_music = _make_player("MenuMusic", BUS_MUSIC)
	if _menu_stream == null:
		_menu_stream = _build_menu_music()
	if _menu_tw != null and _menu_tw.is_valid():
		_menu_tw.kill()
	if _menu_music.playing:
		_menu_tw = create_tween()
		_menu_tw.tween_property(_menu_music, "volume_db", VOL_DB_MUSIC, 0.4)
		return
	_menu_music.stream = _menu_stream
	_menu_music.volume_db = VOL_DB_OFF
	_menu_music.play()
	_menu_tw = create_tween()
	_menu_tw.tween_property(_menu_music, "volume_db", VOL_DB_MUSIC, 0.9)

func stop_menu_music() -> void:
	if _menu_music == null or not _menu_music.playing:
		return
	if _menu_tw != null and _menu_tw.is_valid():
		_menu_tw.kill()
	_menu_tw = create_tween()
	_menu_tw.tween_property(_menu_music, "volume_db", VOL_DB_OFF, 0.45)
	_menu_tw.tween_callback(_menu_music.stop)

# 安静、偏空灵的大厅氛围垫：A 小调长音 + 每 2s 一个琶音点缀（最后 0.8s 静音，避免循环接缝）
func _build_menu_music() -> AudioStreamWAV:
	var rate := 22050
	var dur := 16.0
	var n := int(dur * rate)
	var freqs := [110.0, 164.8125, 220.0, 261.625, 329.625, 440.0]
	var gains := [0.22, 0.14, 0.18, 0.12, 0.09, 0.05]
	var arp := [440.0, 523.25, 659.25, 880.0, 659.25, 523.25, 440.0, 880.0]
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		for j in freqs.size():
			s += sin(TAU * freqs[j] * t) * gains[j]
		s *= 0.55 * (0.78 + 0.22 * sin(TAU * t / dur - PI * 0.5))
		var slot := int(t / 2.0)
		var nt := t - float(slot) * 2.0
		if slot < arp.size() and nt < 1.2:
			var env := minf(nt / 0.03, 1.0) * exp(-2.2 * nt)
			s += sin(TAU * float(arp[slot]) * nt) * env * 0.08
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	_pad_loop_tail(st, n)
	return st

# 循环点处混音器插值会多读 1~2 个采样，若 buffer 正好止于 loop_end，真机（Android）会越界读取直接闪退。
# 这里在尾部补 64 个静音采样作垫片（不参与循环），并确保 loop_end ≤ 采样数，彻底消除越界。
func _pad_loop_tail(st: AudioStreamWAV, samples: int) -> void:
	if st == null or samples <= 0:
		return
	var pad := 64
	var data: PackedByteArray = st.data
	if data.size() < (samples + pad) * 2:
		data.resize((samples + pad) * 2)   # 多出来的字节=0，即静音
		st.data = data
	st.loop_end = samples

# 程序化合成 16bit/22.05kHz 单声道短音（首次播放时生成并缓存）
func _build_synth(key: String) -> AudioStreamWAV:
	var cfg: Dictionary = _SYNTH.get(key, {})
	if cfg.is_empty():
		return null
	return _render_synth(cfg, key)

# 动态定制音色：aa:英雄:攻击距离 / sk:英雄:槽位:类型 / hit:英雄:伤害类型 / item:装备id:类别
func _build_dynamic(key: String) -> AudioStreamWAV:
	var cfg := _dyn_cfg(key)
	if cfg.is_empty():
		return null
	return _render_synth(cfg, key)

func _el_of(hero_name: String) -> String:
	return str(Vfx.element_of(hero_name))

# 同英雄/技能/装备的固定微变调（±6%），让每个技能听感不同又不跑调
func _detune(seed_text: String, n: int = 5) -> float:
	return 1.0 + float(hash(seed_text) % (n * 2 + 1) - n) * 0.012

func _dyn_cfg(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() < 2:
		return {}
	match parts[0]:
		"aa":
			return _cfg_aa(parts[1], float(parts[2]) if parts.size() > 2 else 0.0)
		"sk":
			return _cfg_skill(parts[1], int(parts[2]), int(parts[3]))
		"hit":
			return _cfg_hit(parts[1], parts[2] == "m")
		"item":
			return _cfg_item(parts[1], parts[2])
		"mn":
			return _cfg_from(_MINION_SFX, parts[1], "melee")
		"jn":
			return _cfg_from(_JUNGLE_SFX, parts[1], "pig")
		"tw":
			var tw: Dictionary = (_TOWER_SFX.get(parts[1], _TOWER_SFX["outer"]) as Dictionary).duplicate(true)
			return _scale_cfg(tw, 0.95 if Config.is_ally(int(parts[2])) else 1.06)
	return {}

func _cfg_from(table: Dictionary, key: String, fallback: String) -> Dictionary:
	return (table.get(key, table[fallback]) as Dictionary).duplicate(true)

# 各英雄普攻：元素音色 + 近战闷响/远程破风 + 固定微变调
func _cfg_aa(hero: String, attack_range: float) -> Dictionary:
	var fac := _detune("aa:" + hero, 4)
	var cfg: Dictionary
	if attack_range > 0.0 and attack_range < 400.0:
		cfg = {"kind": "thump", "f0": 150.0, "f1": 52.0, "dur": 0.12, "vol": 0.42, "decay": 4.5, "noise": 0.16}
	else:
		cfg = (_EL_SFX.get(_el_of(hero), _EL_SFX["arcane"]) as Dictionary).duplicate(true)
		cfg["dur"] = 0.13
		cfg["vol"] = 0.34
		cfg["decay"] = 4.0
		cfg["noise"] = float(cfg.get("noise", 0.0)) + 0.05
		if str(cfg.get("kind", "sweep")) == "arp":
			cfg = {"kind": "bell", "f0": 1100.0, "dur": 0.12, "vol": 0.30, "harmonic": 2.01}
	return _scale_cfg(cfg, fac)

# 各英雄技能：元素音色 + 技能类型轮廓 + 槽位（大招更重）+ 固定微变调
func _cfg_skill(hero: String, slot: int, stype: int) -> Dictionary:
	var el := _el_of(hero)
	var fac := _detune("sk:%s:%d" % [hero, slot], 5)
	var notes: Array = (_EL_NOTES.get(el, _EL_NOTES["arcane"]) as Array).duplicate()
	var cfg: Dictionary = (_EL_SFX.get(el, _EL_SFX["arcane"]) as Dictionary).duplicate(true)
	match stype:
		1:
			cfg = {"kind": "sweep", "f0": float(cfg.get("f0", 420.0)) * 0.62,
				"f1": float(cfg.get("f1", 820.0)) * 0.85, "dur": 0.34, "vol": 0.30,
				"noise": 0.16, "decay": 2.6}
		2:
			cfg = {"kind": "arp", "notes": notes, "step": 0.07, "dur": 0.36, "vol": 0.26}
		3:
			cfg = {"kind": "sweep", "f0": 760.0, "f1": 1700.0, "dur": 0.22, "vol": 0.26,
				"noise": 0.14, "decay": 3.4}
		4:
			cfg = {"kind": "sweep", "f0": 420.0, "f1": 1400.0, "dur": 0.16, "vol": 0.26,
				"noise": 0.28, "decay": 4.5}
		6:
			cfg = {"kind": "pad", "notes": notes, "dur": 0.55, "vol": 0.24}
	if slot == 2 and stype != 2 and stype != 6:
		cfg["dur"] = float(cfg.get("dur", 0.3)) * 1.5
		cfg["vol"] = float(cfg.get("vol", 0.26)) * 1.12
		cfg["f0"] = float(cfg.get("f0", 440.0)) * 0.82
		if cfg.has("f1"):
			cfg["f1"] = float(cfg["f1"]) * 0.9
	return _scale_cfg(cfg, fac)

# 技能命中：法术=高频金属点，物理=短闷响；按英雄元素微调
func _cfg_hit(hero: String, magic: bool) -> Dictionary:
	var fac := _detune("hit:" + hero, 4) * (1.0 + (0.08 if _el_of(hero) == "ice" else 0.0))
	if magic:
		return {"kind": "bell", "f0": 880.0 * fac, "dur": 0.13, "vol": 0.20,
			"decay": 5.0, "harmonic": 2.01}
	return {"kind": "thump", "f0": 190.0 * fac, "f1": 70.0, "dur": 0.11, "vol": 0.24,
		"decay": 4.5, "noise": 0.15}

# 装备主动：按 id 变调 + 类别音色
func _cfg_item(item_id: String, cat: String) -> Dictionary:
	var fac := _detune("item:" + item_id, 5)
	var cfg: Dictionary = (_ITEM_SFX.get(cat, _ITEM_SFX["df"]) as Dictionary).duplicate(true)
	return _scale_cfg(cfg, fac)

func _scale_cfg(cfg: Dictionary, fac: float) -> Dictionary:
	if absf(fac - 1.0) < 0.001:
		return cfg
	for k in ["f0", "f1"]:
		if cfg.has(k):
			cfg[k] = float(cfg[k]) * fac
	if cfg.has("notes"):
		var ns: Array = cfg["notes"].duplicate()
		for i in ns.size():
			ns[i] = float(ns[i]) * fac
		cfg["notes"] = ns
	return cfg

func _render_synth(cfg: Dictionary, key: String) -> AudioStreamWAV:
	var notes: Array = cfg.get("notes", [])
	var kind := str(cfg.get("kind", "sweep"))
	if (kind == "arp" or kind == "pad") and notes.is_empty():
		return null
	var rate := 22050
	var dur: float = float(cfg.get("dur", 0.2))
	var n := int(dur * rate)
	if n <= 0:
		return null
	var vol: float = float(cfg.get("vol", 0.25))
	var decay: float = float(cfg.get("decay", 3.0))
	var noise_amt: float = float(cfg.get("noise", 0.0))
	var f0: float = float(cfg.get("f0", 440.0))
	var f1: float = float(cfg.get("f1", f0))
	var step: float = float(cfg.get("step", 0.08))
	var harmonic: float = float(cfg.get("harmonic", 2.0))
	var bright := bool(cfg.get("bright", false))   # 敌方塔/先锋：尾巴加正向提示音
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var phase2 := 0.0   # 第二层（提示音/落地声）单独累计相位
	var lp := 0.0
	for i in n:
		var t := float(i) / float(rate)
		var s := 0.0
		var env := 1.0
		if kind == "arp":
			# 琶音：每 step 换一个音，音内指数衰减（4ms 起音防爆音）
			var idx := mini(int(t / step), notes.size() - 1)
			var local := fmod(t, step) / step
			env = exp(-3.4 * local) * (1.0 - 0.5 * t / dur) * minf(1.0, local * step / 0.004)
			phase += TAU * float(notes[idx]) / float(rate)
			s = sin(phase) * 0.8 + sin(phase * 2.0) * 0.12
		elif kind == "pad":
			# 护盾/增益铺底：多音叠加、慢起慢收
			env = minf(1.0, t / 0.12) * minf(1.0, (dur - t) / 0.22)
			for j in notes.size():
				s += sin(TAU * float(notes[j]) * t) * (1.0 if j == 0 else 0.6)
			s /= maxf(1.0, float(notes.size()))
		elif kind == "fan":
			# 小乔回旋扇：飞出 + 飞回两段气声，叠加旋转音高
			var out_p := exp(-pow((t - 0.11) / 0.075, 2.0))
			var back_p := exp(-pow((t - 0.31) / 0.085, 2.0))
			phase += TAU * (760.0 + 520.0 * sin(clampf(t / dur, 0.0, 1.0) * PI)) / float(rate)
			lp = lp * 0.68 + rng.randf_range(-1.0, 1.0) * 0.32
			env = minf(1.0, t / 0.012) * minf(1.0, (dur - t) / 0.03)
			s = sin(phase) * 0.20 * (out_p + back_p * 0.55) + lp * 0.85 * (out_p + back_p * 0.8)
		elif kind == "meteor":
			# 小乔大招流星：0.42s 下落呼啸 → 落地低频冲击 + 噪声尾
			if t < 0.42:
				phase += TAU * (2000.0 * pow(0.21, t / 0.42)) / float(rate)
				env = 0.08 + 0.24 * t / 0.42
				s = sin(phase)
			else:
				var dt := t - 0.42
				phase += TAU * 68.0 / float(rate)
				lp = lp * 0.90 + rng.randf_range(-1.0, 1.0) * 0.10
				env = exp(-5.5 * dt) * minf(1.0, dt / 0.004)
				var crack := rng.randf_range(-1.0, 1.0) * 0.12 * exp(-14.0 * dt)
				s = sin(phase) * 0.9 + lp * 0.45 * exp(-2.5 * dt) + crack
		elif kind == "collapse":
			# 防御塔倒塌：起始爆裂 + 低频轰鸣尾；bright=敌方塔（末尾上扬提示）
			phase += TAU * (95.0 * pow(0.4, clampf(t / 0.35, 0.0, 1.0))) / float(rate)
			lp = lp * 0.90 + rng.randf_range(-1.0, 1.0) * 0.10
			env = minf(1.0, t / 0.006)
			s = sin(phase) * 0.60 * exp(-8.0 * t) \
					+ lp * (0.90 * exp(-1.3 * t) + 0.25 * exp(-16.0 * t))
			if bright and t > 0.40:
				var up := clampf((t - 0.40) / 0.45, 0.0, 1.0)
				phase2 += TAU * (560.0 + 420.0 * up) / float(rate)
				s += sin(phase2) * 0.10 * (1.0 - up)
		elif kind == "beast":
			# 主宰先锋倒地：低吼下滑 + 落地闷响；bright=敌方先锋（金币提示）
			var u2 := t / dur
			phase += TAU * (250.0 * pow(0.38, clampf(u2 / 0.75, 0.0, 1.0))) / float(rate)
			var saw := sin(phase) + sin(phase * 2.0) * 0.5 + sin(phase * 3.0) * 0.33 + sin(phase * 4.0) * 0.25
			lp = lp * 0.85 + rng.randf_range(-1.0, 1.0) * 0.15
			env = minf(1.0, t / 0.02)   # 起音防爆；衰减写进低吼，避免连带压掉落地声
			s = (saw * 0.28 + lp * 0.20) * exp(-1.6 * u2)
			if t > 0.50:
				var dt2 := t - 0.50
				phase2 += TAU * 70.0 / float(rate)
				s += sin(phase2) * 0.85 * exp(-9.0 * dt2)
			if bright and t > 0.58:
				var dt3 := t - 0.58
				s += (sin(TAU * 1046.5 * t) + sin(TAU * 1568.0 * t) * 0.5) * 0.10 * exp(-6.0 * dt3)
		elif kind == "crisp_coin":
			# 补刀金币：高频清脆主音 + 极短金属泛音 + 瞬态噪声点击，快速收尾
			var hit := exp(-34.0 * t)
			if t > 0.035:
				hit += exp(-48.0 * (t - 0.035)) * 0.32
			phase += TAU * f0 / float(rate)
			phase2 += TAU * f0 * 2.01 / float(rate)
			var p3 := TAU * f0 * 3.01 * t
			var ns := rng.randf_range(-1.0, 1.0)
			lp = lp * 0.30 + ns * 0.70
			var hp := ns - lp
			s = (sin(phase) * 0.55 + sin(phase2) * 0.24 + sin(p3) * 0.10) * hit
			s += hp * 0.30 * exp(-120.0 * t)
			s += sin(TAU * f0 * 4.10 * t) * 0.05 * exp(-55.0 * t)
			env = minf(1.0, t / 0.0007)
		elif kind == "metal":
			# 金币/硬币：非谐金属分音（基频+2.756+5.404）+ 三次快速撞击 + 高频碎响
			var hits := exp(-13.0 * t)
			if t > 0.055:
				hits += exp(-16.0 * (t - 0.055)) * 0.55
			if t > 0.115:
				hits += exp(-19.0 * (t - 0.115)) * 0.30
			phase += TAU * f0 * (1.0 + 0.01 * sin(TAU * 7.0 * t)) / float(rate)
			phase2 += TAU * f0 * 2.756 / float(rate)
			var p3 := TAU * f0 * 5.404 * t
			lp = lp * 0.25 + rng.randf_range(-1.0, 1.0) * 0.75
			s = (sin(phase) * 0.55 + sin(phase2) * 0.26 + sin(p3) * 0.12) * hits
			s += lp * 0.07 * exp(-30.0 * t)   # 撞击瞬间的金属碎响
			env = minf(1.0, t / 0.0015)
		else:
			var u := t / dur
			env = exp(-decay * u) * minf(1.0, t / 0.005)   # 5ms 起音，避免爆音
			if kind == "thump":
				var tf := f0 * pow(maxf(f1, 1.0) / f0, u)   # 低频下坠
				phase += TAU * tf / float(rate)
				s = sin(phase)
			elif kind == "bell":
				phase += TAU * f0 / float(rate)
				s = sin(phase) + sin(phase * harmonic) * 0.35 + sin(phase * 3.01) * 0.12
			else:
				var sf: float = lerp(f0, f1, u * u)   # 频率上扫
				phase += TAU * sf / float(rate)
				s = sin(phase) * 0.85 + sin(phase * 2.0) * 0.10
			if noise_amt > 0.0:
				lp = lp * 0.72 + rng.randf_range(-1.0, 1.0) * 0.28   # 一阶低通白噪声
				s += lp * noise_amt
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = rate
	st.stereo = false
	st.data = data
	return st

func _resolve_key(actor: String, actor_team: int, desc: String, victim: String, victim_team: int) -> String:
	var my_side := Config.is_ally(actor_team)
	# 中性警报（host/客户端各自已加「我方/敌方」前缀，这里按类型出语音）
	if desc.find("正在被攻击") >= 0:
		if desc.find("水晶") >= 0:
			return "crystal_warn"
		if desc.find("高地") >= 0:
			return "high_warn"
		return "tower_warn"
	match desc:
		"第一滴血":
			return "first_blood"
		"终结":
			return "shutdown"
		"击杀了":
			return "env_kill"
		"我方防御塔正在被攻击":
			return "tower_warn"
		"我方高地防御塔正在被攻击":
			return "high_warn"
		"我方水晶正在被攻击":
			return "crystal_warn"
		"二连击破":
			return "m_double" if my_side else "e_double"
		"三连决胜":
			return "m_triple" if my_side else "e_triple"
		"四连超凡":
			return "m_quad" if my_side else "e_quad"
		"五连绝世":
			return "m_penta" if my_side else "e_penta"
		"六杀":
			return "m_six" if my_side else "e_six"
		"七杀":
			return "m_seven" if my_side else "e_seven"
		"八杀":
			return "m_eight" if my_side else "e_eight"
		"九杀":
			return "m_nine" if my_side else "e_nine"
		"十杀":
			return "m_ten" if my_side else "e_ten"
		"大杀特杀":
			return "m_s3" if my_side else "e_s3"
		"杀人如麻":
			return "m_s4" if my_side else "e_s4"
		"势不可挡":
			return "m_s5" if my_side else "e_s5"
		"横扫千军":
			return "m_s6" if my_side else "e_s6"
		"天下无双":
			return "m_s7" if my_side else "e_s7"
		"击败":
			var own := _own_display()
			if my_side:
				return "m_kill_you" if (own != "" and actor == own) else "m_kill_ally"
			return "e_kill_you" if (own != "" and victim == own) else "e_kill_ally"
		"已摧毁":
			# 塔被摧毁：victim_team 是被摧毁塔的阵营。水晶被破由 胜利/失败 结算播报接管，这里跳过。
			if Config.is_ally(victim_team):
				return "" if victim == "crystal" else "tower_lost"
			if victim_team == Config.Team.ENEMY or victim_team == Config.Team.PLAYER:
				return "" if victim == "crystal" else "my_push"
	return ""

## 单发播报（胜利/失败/通用）。to_net=true 时 host 转发给接管客户端（NetKillFeed 剥前缀本地播）。
func play_announce(key: String, to_net := false) -> void:
	var _rrec_ann = get_tree().get_first_node_in_group("replay_recorder")
	if _rrec_ann != null:
		_rrec_ann.call("note_sfx", key, 0.0, true)
	# 敌方关键抢夺有两个同文案音频变体，随机取一个
	if key == "e_steal":
		key = "e_steal_a" if randi() % 2 == 0 else "e_steal_b"
	if key == "" or not _PATHS.has(key):
		return
	_play(key)
	if to_net and NetSession.mode == NetSession.Mode.HOST and multiplayer.is_server():
		NetSession.broadcast_kill_feed("", Config.Team.PLAYER, ANN_PREFIX + key, "", -1)

## 开局链：按每条实际时长顺次播放（欢迎→准备→全军出击），避免同优先级互相抢占。
## token 用于取消旧链：重开/离开对局时不会被上一局的延迟 timer 追着播。
func announce_chain(keys: Array) -> void:
	_chain_token += 1
	_chain_keys = keys.duplicate()
	_announce_next(_chain_token)

func _announce_next(token: int) -> void:
	if token != _chain_token or _chain_keys.is_empty():
		return
	var key: String = str(_chain_keys.pop_front())
	play_announce(key, true)
	# 等本条播完再接下一条；未导入时兜底 2.4s
	var wait := 2.4
	var s: AudioStream = _loaded.get(key)
	if s:
		var len := s.get_length()
		if len > 0.0:
			wait = len + 0.35
	var t := get_tree().create_timer(wait)
	t.timeout.connect(func() -> void:
		if is_instance_valid(self) and token == _chain_token:
			_announce_next(token))

## 立即停掉所有声音并取消播报链（离开对局/回大厅时用，避免尾音残留）
func stop_all() -> void:
	_chain_token += 1
	_chain_keys.clear()
	_sfx_last.clear()
	_own_hero_ref = null
	_playing_key = ""
	_playing_prio = -1
	if _player != null:
		_player.stop()
	for s in _world_sfx:
		s.stop()
	for s in _ui_sfx:
		s.stop()
	if _recall_tw != null and _recall_tw.is_valid():
		_recall_tw.kill()
	_recall_tw = null
	if _recall_loop != null:
		_recall_loop.stop()
	_recall_stopping = false
	if _menu_tw != null and _menu_tw.is_valid():
		_menu_tw.kill()
	_menu_tw = null
	if _menu_music != null:
		_menu_music.stop()

func _own_display() -> String:
	if own_name != "":
		return own_name
	# host/离线：BattleManager 的玩家英雄兜底
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm and bm.get("hero") and is_instance_valid(bm.hero):
		return str(bm.hero.display_name)
	return ""

func _is_own(hero_name: String) -> bool:
	return hero_name != "" and hero_name == _own_display()

func _play(key: String) -> void:
	var path: String = _PATHS.get(key, "")
	if path == "":
		return
	# 同一条正在响：不叠播（避免连续单杀里同档语音互相打断）
	if _playing_key == key and _player.playing:
		return
	var prio: int = _PRIORITY.get(key, 0)
	if _player.playing and prio <= _playing_prio:
		return
	var stream: AudioStream = _loaded.get(key)
	if stream == null:
		if not ResourceLoader.exists(path):
			return
		stream = load(path)
		_loaded[key] = stream
	_player.stream = stream
	_player.play()
	_playing_key = key
	_playing_prio = prio
