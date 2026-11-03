class_name AiConfig
extends RefCounted

# ==================== 分路枚举（共享） ====================
enum Lane { FARM, MID, CLASH, JUNGLE }

# ==================== 血量阈值 ====================
const HEALTH_CRITICAL: float = 0.2          # 极危 — 闪现逃离 / 金身触发
const HEALTH_RECALL: float = 0.25           # 回城阈值
const MANA_LOW: float = 0.30               # 低蓝：不再用耗蓝技能打小兵/野怪，主动找蓝 buff
const MANA_CRITICAL: float = 0.10          # 蓝量危急：触发回城
const BLUE_BUFF_SEARCH_RANGE: float = 60.0 # 低蓝找蓝 buff 的搜索半径
# 特殊资源英雄：不受普通蓝量阈值限制（马可/火舞等能量型；低蓝上限英雄自动豁免）
const MANA_EXEMPT_HEROES := ["马可波罗", "不知火舞", "张飞", "马超", "沈梦溪"]
const MANA_EXEMPT_MAX := 50.0
const HEALTH_LOW: float = 0.4               # 低血量 — 找血包 / 治疗术
const HEALTH_DEFEND: float = 0.5            # 防守倾向
const HEALTH_SAFE: float = 0.7              # 安全线 — 可用恢复
const HEALTH_RECOVERED: float = 1.0        # 泉水养伤完成线 — 血/蓝必须回满才离泉

# ==================== 感知范围 ====================
const SIGHT_HERO: float = 15.0              # 敌我英雄计数范围
const SIGHT_MINION: float = 12.0            # 小兵感知范围
const SIGHT_TURRET: float = 12.0            # 防御塔感知范围
const ENGAGE_RANGE: float = 8.0             # 交战/追击范围
const RETREAT_RANGE: float = 6.0            # 撤退触发范围
const MELEE_RANGE: float = 5.0              # 近身范围
const SKILL_USE_RANGE: float = 10.0          # 对目标使用技能的最大距离
const PUSH_TARGET_RANGE: float = 10.0       # 推进搜索目标范围
const FRIENDLY_TURRET_CLOSE: float = 9.0    # 贴近己方塔的范围
const FRIENDLY_TURRET_FAR: float = 40.0     # 远距离寻找己方塔
const DEFEND_LANE_TURRET_RANGE: float = 50.0    # 响应本线塔防御的最大距离
const TP_TURRET_RANGE: float = 80.0         # 传送寻找己方塔范围
const ENEMY_TURRET_CHECK: float = 30.0      # 检查敌方塔距离
const TP_ENEMY_TURRET_DIST: float = 40.0    # 传送时判断离敌方塔距离
const ALLY_MINION_RANGE: float = 7.0        # 兵线附近小兵检测
const TOWER_MINION_CHECK: float = 10.0      # 塔下小兵检测
const MONSTER_MOVE_RANGE: float = 3.0       # 移动到野怪的距离阈值
const SPAWN_DETECT_RANGE: float = 8.0       # 检测是否在泉水附近
const SPAWN_LEAVE_RANGE: float = 10.0       # 确认离开泉水
const FLASH_DISTANCE: float = 5.0           # 闪现距离
const LANLING_STEALTH_RANGE: float = 12.0   # 兰陵王隐身触发范围
const SUNSPIRE_ACTIVE_RANGE: float = 10.0   # 日冕主动范围
const ICE_SHOCK_RANGE_NORMAL: float = 4.5   # 冰霜冲击范围
const ICE_SHOCK_RANGE_UPGRADE: float = 6.0  # 凛冬范围
const SHADOW_DART_RANGE: float = 8.0        # 影镖脱离范围
const RECALL_DANGER_RADIUS: float = 18.0     # 回城读条中被敌方英雄压到该距离 → 取消换点
const RECALL_SPOT_CLEAR: float = 25.0        # 回城点离敌方英雄的最小安全距离

# ==================== 敌方数量阈值 ====================
const FLEE_ENEMY_COUNT: int = 2             # 附近≥N个敌人时逃跑
const WEAKEN_ENEMY_COUNT: int = 3            # 弱化技能触发
const PURIFY_ENEMY_COUNT: int = 2            # 净化触发
const GOLDEN_BODY_ENEMY_COUNT: int = 1       # 金身触发
const THORNMAIL_ENEMY_COUNT: int = 2         # 反甲触发
const ICE_SHOCK_ENEMY_COUNT: int = 2         # 冰霜冲击触发

# ==================== 计时器（秒） ====================
const THINK_INTERVAL: float = 0.5            # AI决策间隔
const BUY_INTERVAL: float = 5.0              # 购买检查间隔
const RECALL_TIME: float = 4.0               # 回城读条时间
const SKILL_FEED_COOLDOWN: float = 0.5       # 单个技能/连招起手后的全局施法间隔（原 2.0s）
const COMBO_STEP_GAP: float = 0.35           # 连招链两段之间的最小间隔（秒）
const PUSH_TOWER_GOLD_LEAD: int = 5000       # 抱团推塔：经济差触发阈值
const PUSH_TOWER_GOLD_COOLDOWN: float = 90.0 # 抱团推塔：经济差触发后的冷却（秒）
const RESPAWN_COOLDOWN: float = 1.0          # 复活后重新分配路线延迟
const SKILL_WINDOW_THRESHOLD: float = 4.5    # 技能窗口期上限
const TAIYI_Q_EXPLODE_WINDOW: float = 0.5   # 太乙Q引爆窗口
const SLOW_CLEANSE_THRESHOLD: float = 1.0    # 减速多久后用净化

# ==================== 装备主动技冷却 ====================
const CD_PURIFY: float = 75.0
const CD_GOLDEN_BODY: float = 75.0
const CD_BLOOD_RAGE: float = 75.0
const CD_SUNSPIRE: float = 75.0
const CD_THORNMAIL: float = 75.0
const CD_ICE_SHOCK: float = 75.0
const CD_SHADOW_DART: float = 60.0

# ==================== 装备主动技持续 ====================
const DUR_GOLDEN_BODY: float = 1.5
const DUR_BLOOD_RAGE: float = 4.0
const DUR_SUNSPIRE: float = 5.0
const DUR_THORNMAIL: float = 3.0
const DUR_SHADOW_DART_MELEE: float = 1.25
const DUR_SHADOW_DART_RANGED: float = 2.5

# ==================== Buff 数值 ====================
const GOLDEN_BODY_INVINCIBLE: float = 1.5
const BLOOD_RAGE_HP_DRAIN_RATIO: float = 0.3
const BLOOD_RAGE_SHIELD_RATIO: float = 0.1
const SUNSPIRE_SPEED_BOOST: float = 0.2
const SUNSPIRE_SPEED_BOOST_UPGRADE: float = 0.4
const SUNSPIRE_SLOW_DURATION: float = 5.0
const SUNSPIRE_RANGE_BOOST_RATIO: float = 1.25
const SUNSPIRE_RANGE_THRESHOLD: float = 500.0
const ICE_SHOCK_SLOW_NORMAL: float = 0.3
const ICE_SHOCK_SLOW_UPGRADE: float = 0.9
const ICE_SHOCK_DAMAGE_BASE: float = 100.0
const ICE_SHOCK_DAMAGE_PER_LEVEL: float = 6.6
const ICE_SHOCK_FROZE_DUR: float = 0.75
const ICE_SHOCK_SLOW_DUR: float = 0.75
const SHADOW_DART_SPEED_BOOST: float = 0.3

# ==================== 经济 ====================
const MIN_BUY_GOLD: int = 250                 # 最低购买金币
const GOLD_GAP_DEFEND: int = 2000             # 经济落后转入防守

# ==================== 野怪 ====================
const SMITE_DAMAGE_BASE: float = 1500.0
const SMITE_DAMAGE_PER_LEVEL: float = 100.0

# ==================== 其他 ====================
const INFINITE_RANGE: float = 9999.0          # 无限搜索范围
const ATTACK_RANGE_FACTOR: float = 0.01       # attack_range 单位转换系数

# ==================== 新AI决策系统 ====================
const EARLY_GAME_END: float = 240.0            # 早期结束时间（4分钟）
const LANE_SEARCH_RANGE: float = 12.0          # 线上目标搜索范围
const DEFENSIVE_HP_RATIO: float = 0.6          # 防守触发血量比（敌方/我方）
const JUNGLE_HERO_SEARCH_RANGE: float = 10.0   # 打野模式英雄搜索范围
const TEAM_ALLOCATION_INTERVAL: float = 10.0   # 团队任务重规划间隔（秒；事件另有 request_replan）
const MID_SWITCH_COOLDOWN: float = 30.0        # 中路换线冷却（秒）
const MID_SWITCH_GRACE: float = 30.0           # 开局保护：前 30 秒（第一波兵线未交火）不触发中路游走
const MID_SWITCH_QUIET: float = 6.0            # 中路连续无敌方兵线且无目标多少秒后才允许游走
const DRAGON_GOLD_DEFICIT: int = 3000          # 打龙经济落后放弃阈值
const SPLIT_LEAD_GOLD: int = 2000              # 4-1分推经济领先阈值
const SPLIT_DEFICIT_GOLD: int = 3000            # 4-1分推经济落后阈值
const TOWER_ATTACK_RANGE: float = 9.0          # 防御塔攻击范围
const UNSAFE_TOWER_MINION_HP: float = 500.0    # 塔下安全小兵血量阈值
const LANE_THINK_INTERVAL: float = 1.0         # 线上英雄决策间隔
const JUNGLE_THINK_INTERVAL: float = 0.5       # 打野决策间隔
const DEFEND_RECALL_RANGE: float = 40.0       # 防御无塔时回城范围
const DODGE_RANGE: float = 8.0               # 检测弹道的范围
const DODGE_MARGIN: float = 1.5              # 弹道碰撞安全边距
const DODGE_CHANCE: float = 0.6              # 躲避概率（0-1）

# ==================== 位移类技能（追击 / 逃跑） ====================
# AI 以前只会直线走位，位移技能（type=4）几乎只靠连招顺带放。
# 现在追击够不到时用位移贴脸、被贴身且血量偏低时用位移拉开。
const DASH_CHASE_MAX_RANGE: float = 14.0     # 追击时愿意用位移技能的最大距离
const DASH_CHASE_SLACK: float = 1.5          # 突进后仍够不到目标的余量（不够就不浪费）
const DASH_ESCAPE_THREAT: float = 8.0        # 敌方英雄贴近该距离才考虑位移逃跑
const SMALL_DASH_THROUGH_WALL_MAX: float = 3.0  # 小位移技能（<=该距离）允许直接穿墙
const DASH_ESCAPE_HP_RATIO: float = 0.55     # 自身生命低于该比例才用位移逃命

# ==================== 残血追击（收人头） ====================
# 电脑 AI 见到「附近唯一一个血量比自己还少的残血敌人」时会主动追击，
# 即使自身血量不高也追；追到敌人躲进防御塔、距离过远或对方回血/队友赶到才放弃。
const CHASE_START_RANGE: float = 18.0        # 发现并开始追击的最大距离
const CHASE_ABORT_RANGE: float = 24.0        # 追击中拉开到该距离即放弃
const CHASE_HP_RATIO: float = 0.40           # 目标残血判定：目标当前/最大生命比例上限
const CHASE_MIN_SELF_RATIO: float = 0.12     # 自身生命低于该比例不追（避免纯送）
const CHASE_MAX_TIME: float = 12.0           # 单次追击最长时长（秒）
const CHASE_ALLY_GUARD: float = 12.0         # 目标附近还有别的敌人英雄在该距离内则不追（防一打多）

# ==================== 赶路位移（AI 用位移技能加速转线/回线/刷野） ====================
const TRAVEL_DASH_TURRET_MARGIN: float = 2.0  # 距敌方塔(射程+此余量)内不赶路，避免滚进塔里白挨打

# ==================== 难度系统 ====================
enum Difficulty { BRONZE, SILVER, GOLD, PLATINUM, DIAMOND, KING }

static var difficulty: int = Difficulty.GOLD
const DIFFICULTY_NAMES: Array[String] = ["青铜", "白银", "黄金", "铂金", "钻石", "王者"]

# 各难度参数: 反应延迟 / 技能精度 / 决策随机性 / 视野利用率(预留未接入) / 预判帧数
# 黄金为基准档（= 旧行为：不预判、落点误差极小），铂金以上加预判，白银以下落点明显偏
static var DIFF_TABLE: Dictionary = {
	Difficulty.BRONZE:   {"reaction_delay": 0.20, "skill_accuracy": 0.55, "score_random": 0.30, "vision_use": 0.30, "prediction_frames": 0},
	Difficulty.SILVER:   {"reaction_delay": 0.10, "skill_accuracy": 0.72, "score_random": 0.20, "vision_use": 0.50, "prediction_frames": 0},
	Difficulty.GOLD:     {"reaction_delay": 0.00, "skill_accuracy": 0.88, "score_random": 0.12, "vision_use": 0.70, "prediction_frames": 0},
	Difficulty.PLATINUM: {"reaction_delay": 0.00, "skill_accuracy": 0.95, "score_random": 0.08, "vision_use": 0.85, "prediction_frames": 1},
	Difficulty.DIAMOND:  {"reaction_delay": 0.00, "skill_accuracy": 1.00, "score_random": 0.05, "vision_use": 0.95, "prediction_frames": 2},
	Difficulty.KING:     {"reaction_delay": 0.00, "skill_accuracy": 1.00, "score_random": 0.02, "vision_use": 1.00, "prediction_frames": 3},
}

static func difficulty_name(d: int = -1) -> String:
	var v: int = difficulty if d < 0 else d
	return DIFFICULTY_NAMES[clampi(v, 0, DIFFICULTY_NAMES.size() - 1)]

# 技能落点精度（1.0 = 不偏）；SkillTactics 用它换算瞄准误差半径
static func skill_accuracy() -> float:
	return float(DIFF_TABLE[difficulty].get("skill_accuracy", 1.0))

# 预判帧数：>0 时对移动目标按速度提前瞄准（1 帧 ≈ 50ms）
static func prediction_frames() -> int:
	return int(DIFF_TABLE[difficulty].get("prediction_frames", 0))

# 读取难度参数，乘以 base 值
static func diff(key: String, base_value: float = 1.0) -> float:
	return base_value * DIFF_TABLE[difficulty].get(key, 1.0)

# 青铜/白银的随机反应延迟：本帧直接跳过决策
static func should_skip_think() -> bool:
	return randf() < DIFF_TABLE[difficulty].get("reaction_delay", 0.0)

# 技能命中判定：精度低于随机数则miss
static func skill_hits() -> bool:
	return randf() < DIFF_TABLE[difficulty].get("skill_accuracy", 1.0)

# 决策随机扰动幅度
static func score_jitter() -> float:
	return DIFF_TABLE[difficulty].get("score_random", 0.15)


## 是否套用普通蓝量阈值（马可/火舞等能量型、蓝量上限极低的英雄不套用）
static func mana_rules_apply(h) -> bool:
	if h == null or not is_instance_valid(h):
		return false
	if str(h.display_name) in MANA_EXEMPT_HEROES:
		return false
	if float(h.actual_mana_max) <= MANA_EXEMPT_MAX:
		return false
	return true
