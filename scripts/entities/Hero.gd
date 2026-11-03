class_name Hero
extends GameEntity
const ActorPresenter = preload("res://scripts/presentation/ActorPresenter.gd")
const WukongCloud = preload("res://scripts/fx/WukongCloud.gd")
const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
const HeroYingrui = preload("res://scripts/core/HeroYingrui.gd")
const HeroSkinTable = preload("res://scripts/core/HeroSkins.gd")
# 泉水回复节拍（秒/跳）；每跳回 10% 最大生命与法力，等于原来的 20%/秒
const FOUNTAIN_TICK := 0.5
# 线性技能预览线
# 技能预览：地面箭头（线性/位移技能用）
var arrow_preview: Node3D
var arrow_shaft: MeshInstance3D
var arrow_head: MeshInstance3D
var _pv_color_key := ""
var buff_ring_red: MeshInstance3D
var buff_ring_blue: MeshInstance3D
var damage_log: Array = []  
# ==================== 基础属性（1级） ====================
var base_health: float = 3000

var base_mana: float = 0

var preview_mesh: MeshInstance3D
# 新增职业成长表
const ROLE_GROWTH = {
	"坦克":     {"health": 240, "attack": 8,  "armor": 18, "attack_speed": 0.005, "magic_resist": 8.5},
	"战士":     {"health": 200, "attack": 12, "armor": 15, "attack_speed": 0.015, "magic_resist": 8.5},
	"刺客":     {"health": 175, "attack": 14, "armor": 12, "attack_speed": 0.015, "magic_resist": 8.5},
	"射手":     {"health": 185, "attack": 14, "armor": 10, "attack_speed": 0.02,  "magic_resist": 8.5},
	"法师":     {"health": 180, "attack": 10, "armor": 10, "attack_speed": 0.005, "magic_resist": 8.5},
	"辅助":     {"health": 170, "attack": 10, "armor": 10, "attack_speed": 0.005, "magic_resist": 8.5},
	"肉辅":     {"health": 240, "attack": 8,  "armor": 18, "attack_speed": 0.005, "magic_resist": 8.5}
}

# 当前英雄的职业成长数据（运行时赋值）
var role_growth: Dictionary = {}
  
var role: String = "战士"
# ==================== 装备加成 ====================
var bonus_health: float = 0


var bonus_hp_regen: float = 0
var bonus_mana_regen: float = 0
var consecutive_kills: int = 0
# ==================== 实时属性 ====================

var actual_mana_max: float = 300
var actual_hp_regen: float = 0.0
var actual_mana_regen: float = 0.0
var regen_timer:float = 0.0
var turn_timer:float = 0.0   # 按键转向冷却：每0.1秒最多旋转一次
var marked:Array = []
var _debug_atk_info: String = ""
var _debug_skill_info: String = ""
var _makeboluo_w2_active: bool = false
# ==================== 装备系统 ====================
var equipment_slots: Array = []
const MAX_EQUIPMENT_SLOTS = 6

# ==================== 经验与等级 ====================
var exp: int = 0
var is_ai: bool = false   # 是否由AI控制
var hero_skin_id: String = ""   # 英雄皮肤 id（HeroSkins 表；空=按玩家/AI规则选）
var ai_path_controlled: bool = false   # AI自行给 move_target 时关闭 Hero 自动追击
var ai_enhanced_attack_ok: bool = false   # AI 是否允许把强普位移用于普攻（默认攒着赶路/追击/逃跑）
# 已被联机真人接管（NetSession._assign_hero_to 置 true；is_ai 仍保持 true 以走同一批原语）。
# 区别于纯 AI 的关键：普攻/锁定目标不会自动追击超范围敌人——只打射程内目标，超出即脱锁等待玩家走近。
var net_taken: bool = false
var exp_to_next: int = 200
var gold: int = 300   
# ==================== 战斗操作变量 ====================
var move_target: Vector3 = Vector3.ZERO
# 远程真人接管直驱输入（NetSession 收到 C_DRIVE 后写入；全默认值=未接管，行为与单机完全一致）
var net_axis: Vector3 = Vector3.ZERO
var net_joy: Vector2 = Vector2.ZERO
var net_move_mode: int = -1
# 远程真人按住普攻：为 true 时英雄站定自动选敌持续攻击（同单机按住普攻键）；
# net_attack_priority 为 -1=跟随主机全局优先级，0..2=该真人的推塔/小兵/自动优先级覆盖
var net_attack_hold := false
var net_attack_priority: int = -1
var hidden_in_bush: bool = false   # 每帧由 _update_bush_stealth() 刷新：草丛中且同排无敌方英雄时为 true
var _bush_region_counts: Dictionary = {}   # 所在草区域 {region_id: 重叠计数}
var visual_mesh: Node3D
var _death_pose := false
var _death_pose_tween: Tween = null
var _death_vis_node: Node3D = null
var _death_vis_rot := Vector3.ZERO
var _death_vis_pos := Vector3.ZERO
var manual_target: GameEntity = null
# 锁敌头像锁定的目标（移动端点头像确定；与普攻/世界点击的 manual_target 分开存，互不覆盖）
var locked_target: Hero = null
# 最近一次普攻的命中目标（补刀提示用：血量低于一次普攻伤害 → 血条变灰白）
var aa_target: GameEntity = null
var aa_target_t: float = 0.0
# 技能预览：AOE填充圆 + 施法范围圈 + 命中半径圈（半径型技能的第二段范围，如吕布R/太乙Q）
var aoe_fill: MeshInstance3D
var cast_range_ring: MeshInstance3D
var impact_ring: MeshInstance3D
# 普攻轮盘选敌准星（拖动普攻键时高亮即将锁定的目标）
var attack_aim_marker: MeshInstance3D
# 技能预览法阵（瞄准技能时脚下浮现）
var _foot_sigil: Node3D = null
# ==================== 技能系统 ====================
var skills: Array = []               # 存储 Skill 资源
var skill_cooldowns: Array = []
var skill_window_timers: Array = []  # 技能窗口倒计时      # 每个技能的剩余冷却
var skill_uses: Array = []
var summoner_skill: Skill = null
var summoner_cooldown: float = 0.0
var _summoner_preview_on := false   # 本帧是否由召唤师技能占用地面的施法预览

# —— 阵亡状态清零：技能冷却/被动层数/Buff/控制/装备被动计时…（召唤师冷却、战绩、复活类除外）——
# 快照在首个物理帧抓取（此时装备/技能等级已初始化），死亡时按快照还原成"出生状态"。
const STATE_RESET_SUFFIX := ["_cd", "_cooldown", "_timer", "_t", "_stacks", "_stack", "_count",
	"_phase", "_active", "_ready", "_uses", "_window", "_left", "_until", "_hold", "_edge",
	"_enhanced", "_channeling", "_stealth", "_protected", "_fuse", "_barrage", "_flying",
	"_burrow", "_float", "_flow", "_pick", "_picked", "_stage", "_angle", "_marks", "_orb",
	"_idle", "_auras", "_ticks", "_mana", "_transformed"]
const STATE_RESET_EXACT := ["stat", "stat2", "parry", "marked", "markers", "lyf_marks",
	"active_buffs", "active_regen", "shield_remaining", "grievous_wounds", "toughness", "fly",
	"hunt_damage", "hunt_source", "slow_amount", "skill_cooldowns", "skill_restores",
	"skill_window_timers", "channeling_skill_index", "pending_skill_index", "pending_skill_target_entity"]
const STATE_RESET_SKIP := ["summoner_", "respawn_", "revive_", "skill_uses", "is_dead", "is_reviving",
	"dayu_", "donghuang_orb"]   # 召唤物（大禹鼎/东皇能量体）与召唤师技能不受死亡影响
# 装备被动倒计时也不清零（防止靠送死刷新装备被动/保命装冷却）
const STATE_RESET_KEEP := ["famous_blade_cd", "frost_assault_cd", "sanction_regen_cd", "purify_cd",
	"sage_power_cd", "sunspire_active_cd", "shadow_dart_cd", "golden_body_cd", "fire_dominate_cd",
	"echo_staff_cd", "pain_mask_cd", "witch_staff_cd", "frost_breath_cd", "thornmail_cd",
	"blood_rage_cd", "ice_shock_cd", "ice_shock_shield_cd", "dragon_shield_cd", "rising_sun_cd",
	"mage_robe_shield_cd", "ice_storm_cd", "revive_cd", "night_guardian_cd", "ice_fist_cd",
	"tyrant_lightning_cd"]
var _base_state_snap: Dictionary = {}
var _base_state_captured := false
var channeling_skill_index: int = -1
var channeling_preview_pos: Vector3 = Vector3.ZERO
var casting_skill: bool = false
var aim_slot: int = -1                  # 正在按住瞄准的技能槽（-1=没在瞄准；小地图瞄准线用）
var aim_world: Vector3 = Vector3.ZERO   # 当前瞄准点（世界坐标）
var pending_skill_index: int = -1
var pending_skill_target: Vector3 = Vector3.ZERO
var pending_skill_target_entity: GameEntity = null   # 目标型技能拖拽/智能施法选中的目标
var _cast_windup_left: float = 0.0   # 技能前摇剩余秒数（>0=前摇中；归零后由 _physics_process 结算 _finish_casting）
var _aa_anim_until: float = 0.0      # 走A：普攻动作保护截止（Time.get_ticks_msec()/1000.0），期间移动不覆盖 walk
var _move_lock_until: float = 0.0    # 走A：普攻瞬间锁移动截止（0.5s），攻击动画期间原地完成出手
var _cast_anim_until: float = 0.0    # 施法动作收招截止（同口径），期间移动不覆盖 walk，避免一出手就被走打断
# 桌面目标型(type0)技能「按住瞄准-松手施放」状态：按住技能键进入瞄准，按拖动轮盘(鼠标)角度
# 计算锁定对象（目标与英雄的相对方向里最近者），松手施放；点按(≤DT0_TAP_MS)退化为智能施法。
var _dt0_hold: int = -1
var _dt0_ent: GameEntity = null
var _dt0_pos: Vector3 = Vector3.ZERO
var _dt0_press_ms: int = -1
# 基础属性
var base_crit_chance: float = 0.0
var base_crit_damage: float = 1.85      # 默认 200%
var base_phys_lifesteal: float = 0.12
var base_magic_lifesteal: float = 0.0
var base_phys_pen_percent: float = 0.0
var base_magic_pen_percent: float = 0.0
var base_hp_regen: float=40.0
var base_mana_regen: float = 15.0
var kills: int = 0
var deaths: int = 0
var assists: int=0
var is_mvp: bool = false   # 当前全场MVP标记（由 BattleManager 每30秒重算维护，血条左侧显示MVP角标）
# ==================== 赛后统计变量 ====================
var damage_dealt_to_heroes: float = 0.0
var damage_taken_from_heroes: float = 0.0
var healing_done: float = 0.0
var cc_duration_dealt: float = 0.0
var turret_damage: float = 0.0
var jungle_gold: int = 0
var last_hits: int = 0
var gold_history: Array = []  # 每分钟金币快照
var respawn_time_total: float = 0.0
# 装备加成
var bonus_crit_chance: float = 0.0
var bonus_crit_damage: float = 0.0
var bonus_phys_lifesteal: float = 0.0
var bonus_magic_lifesteal: float = 0.0
var bonus_phys_pen_percent: float = 0.0
var bonus_magic_pen_percent: float = 0.0
var bonus_flat_phys_pen: float = 0.0
var bonus_flat_magic_pen: float = 0.0
var flat_phys_pen: float = 0.0
var flat_magic_pen: float = 0.0
var actual_cd_timer: float = 1.0

# 实时属性
var actual_crit_chance: float = 0.0
var actual_crit_damage: float = 1.85
var actual_phys_lifesteal: float = 0.0
var actual_magic_lifesteal: float = 0.0
var actual_phys_pen_percent: float = 0.0
var actual_magic_pen_percent: float = 0.0
var skill_levels: Array = []          # 每个技能的当前等级（1~max）
const SKILL_MAX_LEVEL = 6             # 普通技能最高等级
const ULTIMATE_MAX_LEVEL = 3          # 大招最高等级
const ULTIMATE_REQUIRED_LEVEL = [0, 4, 8, 12]   # 大招升至第 N 级（N=1/2/3）所需英雄等级
var skill_points: int = 0             # 剩余技能点数
var training_invincible := false       # 训练营：无敌
var training_no_cooldown := false      # 训练营：无冷却
var skill_restores:Array = []
var base_attack_speed: float = 1.0       # 基础攻速（每秒攻击次数）
var attack_speed_growth: float = 0.02   
var total_gold_earned: int = 300   # 累计获得的金币（初始500）
# ==================== Buff ====================
var red_buff_active: bool = false
var red_buff_timer: float = 0.0
var blue_buff_active: bool = false
var blue_buff_timer: float = 0.0
const BUFF_DURATION: float = 75.0

var respawn_timer: float = 0.0
const RESPAWN_BASE_TIME: float = 5.0
const RESPAWN_SCALE: float = 1.5
# 攻速系统（王者荣耀机制）
var base_as: float = 1000.0               # 基础AS值（1000=0%攻速）
	# 额外攻速百分比（装备/铭文/Buff）
var skillapply :SkillApplier = null
var item_passive: ItemPassive = null
var hero_passive: HeroPassive = null
var last_health: float = 0.0          # 用于检测回血变化
const HEAL_POPUP_THRESHOLD: float = 50.0  # 回血量超过此值才显示
# 模型A攻速阈值表（攻速% -> 攻击间隔秒）
var target_indicator: Node3D   # 锁定目标标识（四角括号 + 双环刻度 + 顶部标记）
var _reticle_t: float = 0.0
var _reticle_brackets: Array = []
var _reticle_spin_a: Node3D = null
var _reticle_spin_b: Node3D = null
var _reticle_billboard: Node3D = null
var _reticle_ground: Node3D = null
var _reticle_top: Node3D = null
const MODEL_A_THRESHOLDS = [
	[0, 1.0],
	[1, 0.95],
	[8.2, 0.9],
	[16.6, 0.85],
	[26.2, 0.8],
	[37.6, 0.75],
	[51.4, 0.7],
	[68.2, 0.65],
	[89.2, 0.6],
	[116, 0.55],
	[152, 0.5]
]
# 攻击范围预览环
var attack_range_ring: MeshInstance3D
var _melee_anim_flip := false   # 近战普攻左右挥砍交替
var _aa_ring_leap := false  # 攻击范围圈当前是否处于跳跃强化普攻状态（×2+金色）
var _aa_ring_show_timer := 0.0   # 攻击范围圈剩余显示时间（普攻出手才亮，>0 时可见）
var under_tower_attack: bool = false
var tower_attacker: Turret = null
var tower_attack_timer: float = 0.0
var is_teleporting: bool = false
# 最近一次「被敌方英雄实际打到」的记录（防御塔越塔保护用；不用 AI 的 current_target 猜）
var last_hero_attacker: Hero = null
var last_hero_attacker_at: float = -9999.0
var last_hero_attacked_from: Vector3 = Vector3.ZERO
var last_hero_attacked_at: Vector3 = Vector3.ZERO
var is_dashing: bool = false        # 位移（突进/闪现）滑行中：位置由 Tween 逐帧推进，不再瞬移
var _dash_tw: Tween = null
var _dash_preview: MeshInstance3D = null   # 位移预览落点环
var teleport_targeting: bool = false
# 亚瑟
var arthur_q_active: bool = false
var arthur_q_timer: float = 0.0
# 刘禅
var liushan_q_active: bool = false
var liushan_q_timer: float = 0.0
# 孙悟空
var sunwukong_enhanced_aa: bool = false
var sunwukong_1_block_active: bool = false
var sunwukong_1_block_timer: float = 0.0
var arthur_w_active: bool = false
var arthur_w_timer: float = 0.0
var _arthur_heal_tick: float = 2.0
var arthur_w_shields: Array = []
var arthur_w_angle: float = 0.0
var arthur_w_hit_cd: Dictionary = {}
var taiyi_q_channeling: bool = false

var taiyi_q_timer: float = 0.0
# 沈梦溪
var shen_fuse_active: bool = false   # W疾跑引燃中：窗口内可手动引爆，4秒到期自动引爆
var shen_barrage_active: bool = false   # 1技能猫咪炸弹连发进行中：防重入，禁止并发连发（同帧叠多段伤害）
var player_name: String = ""   # 玩家/本局 AI 昵称（血条上方与选人界面显示）
var donghuang_orbs: int = 0
var donghuang_orb_angle: float = 0.0
var donghuang_suppress_target: Hero = null
var donghuang_speed_boost: float = 0.0
var donghuang_orb_meshes: Array = []
var donghuang_aim_rings: Array = []
var donghuang_orb_hit_cd: Dictionary = {}
# 李白
var libai_sword_auras: int = 0
var libai_sword_timer: float = 0.0
var libai_xia_active: bool = false
var libai_xia_timer: float = 0.0
var libai_q_origin: Vector3 = Vector3.ZERO

var libai_w_active: bool = false
var libai_w_timer: float = 0.0
var libai_w_ring: Node3D = null
# 兰陵王
var lanling_stealth_active: bool = false
var lanling_stealth_cd: float = 0.0
var lanling_stealth_timer: float = 0.0
var lanling_as_buff_timer: float = 0.0
# 张飞
var zhangfei_transformed: bool = false
var zhangfei_transform_timer: float = 0.0
var zhangfei_mana: float = 50.0
var zhangfei_q_active: bool = false
var zhangfei_q_angle: float = 0.0
var zhangfei_q_timer: float = 0.0
var zhangfei_q_elapsed: float = 0.0
var zhangfei_q_dmg: float = 0.0
var zhangfei_q_mesh: MeshInstance3D = null
var zhangfei_q_hit_cd: Dictionary = {}
var zhangfei_form_ring: MeshInstance3D = null
# 英睿
var yingrui_transformed: bool = false
var yingrui_transform_timer: float = 0.0
var yingrui_stacks: int = 0
var yingrui_stack_timer: float = 0.0
var yingrui_aa_count: int = 0          # 被动：已普攻计数（满3次后下次普攻为肘击）
var yingrui_elbow_ready: bool = false  # 被动：下次普攻是否为肘击
var yingrui_w_stage: int = 0           # W三段：当前已释放段数（1~2窗口期，3打完关闭）
# 英睿 视觉（HeroYingrui.gd）：人形底座 + 大招 LabiB 毛绒形态切换
var yingrui_body: Node3D = null
var yingrui_plush: Node3D = null
var _yingrui_form_on: bool = false


var revive_hp: float = 0.0
var fountain_tick_timer: float = 0.0   # 泉水回复节拍计时（FOUNTAIN_TICK 一跳）
var teleport_progress: float = 0.0
var teleport_target_pos: Vector3
var teleport_minion: Minion = null   # 传送落点小兵：引导期间锁定/免伤
var teleport_timer: float = 0.0
var last_kill_time: float = 0.0          # 上次击杀时间（秒）
var streak_count: int = 0               # 10秒内连杀计数
var active_regen: Dictionary = {}   # 记录各种回复效果
var _regen_ring: MeshInstance3D = null   # 恢复中：脚下旋转绿环
var _regen_fx: CPUParticles3D = null     # 恢复中：上浮绿光粒子
var _regen_t: float = 0.0
var is_recalling: bool = false
var recall_timer: float = 0.0
const RECALL_DURATION: float = 7.0
const TELEPORT_DURATION: float = 4.0
# 回城/传送动画（纯程序化 VFX：双层法阵 + 光晕盘 + 光柱 + 上升粒子，挂在英雄身上跟随）
var _recall_ring: MeshInstance3D = null
var _recall_ring2: MeshInstance3D = null
var _recall_glow: MeshInstance3D = null
var _recall_pillar: MeshInstance3D = null
var _recall_spark: CPUParticles3D = null
var _recall_vfx_t: float = 0.0
var stat:float = 0.0
var stat_timer:float=0.0
var stat2:float = 0.0
var stat2_timer:float = 0.0
var _aa_prev_held := false          # 通用：上一帧普攻是否按住（空放普攻检测按下沿）
var _aa_edge := false                # 通用：本帧普攻按下沿
var machao_prev_aa_held := false    # 马超：上一帧普攻是否按住（检测按下沿）
var machao_aa_edge := false         # 马超：普攻按下沿（无目标空冲仅在点按那帧触发）
var kai_prev_aa_held := false    # 铠：上一帧普攻是否按住（检测按下沿）
var kai_aa_edge := false         # 铠：普攻按下沿（强普无目标空冲仅在点按那帧触发）
var mai_prev_aa_held := false    # 不知火舞：上一帧普攻是否按住（检测按下沿）
var mai_aa_edge := false         # 不知火舞：普攻按下沿（强普无目标空放仅在点按那帧触发）
var luban_passive_stacks: int = 0         # 鲁班七号被动层数（5层触发扫射）
var luban_skill_enhanced: bool = false     # 鲁班七号技能后下次普攻强化
var luban_r_active: bool = false           # 鲁班七号R技能防重入守卫
var xiahou_passive_cd: float = 0.0         # 夏侯惇被动冷却
var xiahou_passive_active: bool = false     # 夏侯惇噬目激活中
var xiahou_passive_timer: float = 0.0       # 夏侯惇噬目剩余时间
var xiahou_enhanced_attacks: int = 0        # 夏侯惇W强化普攻剩余次数
# 后羿Q：多重箭矢
var houyi_q_active: bool = false
var houyi_q_timer: float = 0.0
# 大禹：戍鼎系统
var dayu_tripods: Array = []
var dayu_tripod_max: int:
	get:
		return min(3 + level / 3, 8)
var dayu_teleport_cd: float = 0.0
var dayu_w_enhanced: bool = false
var dayu_w_enhanced_timer: float = 0.0
var dayu_w_used_enhanced: bool = false
var dayu_teleport_channeling: bool = false
var dayu_teleport_target: Vector3 = Vector3.ZERO
var dayu_teleport_progress: float = 0.0
var dayu_r_landing_pos: Vector3 = Vector3.ZERO
const DAYU_TELEPORT_DURATION: float = 4.0
# 孙悟空：筋斗云回城
var wukong_cloud_flying: bool = false
var wukong_cloud_phase: int = 0          # 0=腾空, 1=飞行
var wukong_cloud_timer: float = 0.0      # 腾空计时
var wukong_cloud_speed: float = 0.0      # 当前飞行速度
var wukong_cloud_target: Vector3 = Vector3.ZERO
var wukong_last_z_time: float = -1.0
var _wukong_cloud_vis: Node3D = null
var _wukong_cloud_t := 0.0
var wangzhaojun_aa_counter: int = 0        # 被动普攻计数器
var wangzhaojun_shield_was_active: bool = false  # 护盾破裂检测
var bt_timer:float = 0.0
var wd_timer:float = 0.0
# 李元芳：Q攻击距离加成已改走 bonus_attack_range buff 管线（见 _recalculate_attributes）
# W钻地(无法选中) / 被动谛听探测CD / dash起点
var _lyf_burrow: float = 0.0            # W钻地剩余时长：>0时模型隐藏+wd免伤免控(不可选中)
var lyf_reveal_cd: Dictionary = {}      # 被动·密探谛听: 敌方英雄 -> 下次可再次暴露的纪元秒
var dash_from: Vector3 = Vector3.ZERO   # type4位移起点（供W燃痕/位移类技能回读）
# 元流之子·万物为流：流层 / 泉水四选一 / 破釜连发 / 浮空
var yuanliu_flow: int = 0               # "流"层数 0~9
var yuanliu_flow_idle: float = 5.0      # 距「流」首层流失的倒计时（获得/消耗即重置为5秒）
var yuanliu_pick: String = "生机"       # 生机/穿心/迅疾/凝神（泉水四选一，可回泉重选）
var last_move_dir: Vector3 = Vector3.ZERO  # 最近一帧世界移动方向（破釜摇杆小位移用；摇杆/按键/AI追击统一写）
var yuanliu_w_phase: int = 0            # 破釜连发阶段 0/1(参连)/2(凌空)
var yuanliu_w_window: float = 0.0       # 连发窗口剩余（>0 视为 2s 内连放）
var yuanliu_float: float = 0.0          # 浮空剩余：模型上抬+wd免控近似
var yuanliu_picked: bool = false        # 泉水四选一是否已完成
# 名刀
var famous_blade_cd: float = 0.0
var famous_blade_uses: int = 0
var famous_blade_purchase_time: float = -1.0
var famous_blade_upgrade: int = 0
var famous_blade_ready: bool = true

# 寒霜袭侵
var frost_assault_cd: float = 0.0
# 制裁之刃
var sanction_regen_cd: float = 0.0
# 纯净苍穹
var purify_cd: float = 0.0
# 宗师之力
var sage_power_buff: bool = false
var sage_power_timer: float = 0.0
var sage_power_cd: float = 0.0
# 闪电匕首
var lightning_count: int = 0
# 逐日之弓
var sunspire_active_cd: float = 0.0
var sunspire_active: bool = false
var sunspire_active_timer: float = 0.0
# 主动装备按钮槽
# 逐风
var chase_wind_stacks: int = 0
var chase_wind_timer: float = 0.0
# 幽影袖箭
var shadow_dart_cd: float = 0.0
var shadow_dart_active: bool = false
var shadow_dart_timer: float = 0.0
var shadow_dart_heal_tick: float = 0.0
# 辉月
var golden_body_cd: float = 0.0
var golden_body_active: bool = false
var golden_body_timer: float = 0.0
	# 炽热支配
var fire_dominate_cd: float = 0.0
# 日暮之流
var dusk_flow_stacks: int = 0
var dusk_flow_timer: float = 0.0
# 金色圣剑
var gold_saint_sword_stacks: int = 0
var gold_saint_sword_timer: float = 0.0
# 回响之杖
var echo_staff_cd: float = 0.0
# 痛苦面具
var pain_mask_cd: float = 0.0
	# 巫术法杖
var witch_staff_buff: bool = false
var witch_staff_cd: float = 0.0
# 凝冰之息
var frost_breath_cd: float = 0.0
# 时之预言
var last_level: int = 4
var prophecy_timer: float = 0.0
# 打野刀
var jungle_stacks: int = 0
# 疾步之靴
var boots_speed_timer: float = 999.0
# 游走装
var support_gold_timer: float = 0.0
# 反伤刺甲
var thornmail_active: bool = false
var thornmail_timer: float = 0.0
var thornmail_cd: float = 0.0
var red_cloak_timer: float = 0.0
# 血魔之怒
var blood_rage_cd: float = 0.0
var blood_rage_active: bool = false
var blood_rage_timer: float = 0.0
# 冰霜冲击
var ice_shock_cd: float = 0.0
var ice_shock_shield_cd: float = 0.0
# 怒龙剑盾
var dragon_shield_cd: float = 0.0
# 旭日初光
var rising_sun_cd: float = 0.0
# 霸者重装
var heavy_armor_last_hit: float = 999.0
# 不祥征兆
# 不死鸟之眼: bonus applied in recalc
# 魔女斗篷
var mage_robe_shield_cd: float = 0.0
# 极寒风暴
var ice_storm_cd: float = 0.0
# 贤者的庇护
var revive_count: int = 0
var revive_cd: float = 0.0
var is_reviving: bool = false
var revive_timer: float = 0.0
# 暴烈之甲
var fierce_armor_stacks: int = 0
var fierce_armor_timer: float = 0.0
# 永夜守护
var night_guardian_hp_track: float = 0.0
var night_guardian_timer: float = 0.0
var night_guardian_cd: float = 0.0
# 冰痕之握
var ice_fist_buff: bool = false
var ice_fist_cd: float = 0.0
var parry:float = 0.0
var objs:Array=[]
var last_indicator_time: float = 0.0
const INDICATOR_COOLDOWN = 0.5
func start_recall():
	if is_dead: return
	# 孙悟空：双击回城键触发筋斗云
	if display_name == "孙悟空" and not is_ai:
		var _now = Time.get_ticks_msec() / 1000.0
		if is_recalling and wukong_last_z_time > 0 and _now - wukong_last_z_time < 0.5:
			cancel_recall()
			_start_wukong_cloud()
			return
		wukong_last_z_time = _now
	# AI孙悟空：回城直接乘筋斗云；已回自家泉水则留在泉里回满，不再反复起飞
	if display_name == "孙悟空" and is_ai:
		if wukong_cloud_flying:
			return
		if is_in_own_fountain():
			return
		_start_wukong_cloud()
		return
	if is_recalling: return
	# 大禹：如果附近有戍鼎，传送到最远鼎（非回城）
	if display_name == "大禹" and dayu_teleport_cd <= 0:
		var furthest = _get_furthest_tripod()
		if furthest and global_position.distance_to(furthest.global_position) <= 6.0:
			_start_tripod_teleport(furthest)
			return
	is_recalling = true
	recall_timer = RECALL_DURATION
	_recall_vfx_start()
	# 本地玩家回城起手短音 + 引导循环音（完成/取消时停）
	SfxManager.try_recall_sfx(display_name)
	SfxManager.start_recall_loop(display_name)
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm:
		var spring = Vector3(-62,0,62) if team == Config.Team.PLAYER else Vector3(62,0,-62)
		bm.add_recall_line(self, spring)
func cancel_recall():
	is_recalling = false
	_recall_vfx_stop()
	SfxManager.stop_recall_loop(display_name)
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm:
		bm.remove_recall_line(self)

# ---------- 回城/传送动画（程序化 VFX，无美术资源） ----------
func _recall_vfx_start(col_override: Color = Color(0, 0, 0, 0)) -> void:
	_recall_vfx_stop()
	_recall_vfx_t = 0.0
	var col: Color = col_override if col_override.a > 0.0 else (Color(0.40, 0.80, 1.0) if team == Config.Team.PLAYER else Color(1.0, 0.55, 0.40))
	# 地面法阵环（双环叠加，缓慢旋转）
	_recall_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.32
	tm.rings = 32
	tm.ring_segments = 8
	_recall_ring.mesh = tm
	_recall_ring.position.y = 0.06
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_recall_ring.material_override = rm
	add_child(_recall_ring)
	# 光柱（半透明加色圆柱，随引导进度升高/变亮）
	_recall_pillar = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.30
	cm.height = 6.0
	cm.radial_segments = 24
	cm.cap_top = false
	cm.cap_bottom = false
	_recall_pillar.mesh = cm
	_recall_pillar.position.y = 3.0
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_color = Color(col.r, col.g, col.b, 0.14)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_recall_pillar.material_override = pm
	add_child(_recall_pillar)
	# 上升粒子
	_recall_spark = CPUParticles3D.new()
	_recall_spark.amount = 36
	_recall_spark.lifetime = 1.15
	_recall_spark.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_recall_spark.emission_sphere_radius = 1.35
	_recall_spark.position.y = 0.3
	_recall_spark.spread = 18.0
	_recall_spark.initial_velocity_min = 1.6
	_recall_spark.initial_velocity_max = 3.2
	_recall_spark.gravity = Vector3(0, 0.6, 0)
	_recall_spark.scale_amount_min = 0.03
	_recall_spark.scale_amount_max = 0.07
	_recall_spark.color = Color(col.r, col.g, col.b, 0.85)
	add_child(_recall_spark)
	# 外圈反向法阵（两层环反向旋转，视觉更"转"）
	_recall_ring2 = MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 1.58
	tm2.outer_radius = 1.78
	tm2.rings = 40
	tm2.ring_segments = 8
	_recall_ring2.mesh = tm2
	_recall_ring2.position.y = 0.10
	var rm2 := StandardMaterial3D.new()
	rm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm2.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm2.albedo_color = Color(col.r, col.g, col.b, 0.34)
	rm2.cull_mode = BaseMaterial3D.CULL_DISABLED
	_recall_ring2.material_override = rm2
	add_child(_recall_ring2)
	# 地面光晕盘（贴地加色圆盘，随进度变亮）
	_recall_glow = MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 1.9
	gm.bottom_radius = 1.9
	gm.height = 0.02
	gm.radial_segments = 36
	_recall_glow.mesh = gm
	_recall_glow.position.y = 0.04
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gmat.albedo_color = Color(col.r, col.g, col.b, 0.10)
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_recall_glow.material_override = gmat
	add_child(_recall_glow)
	# 起手一圈爆发
	Vfx.sigil(global_position, col, 2.2, 0.8)
	Vfx.cast_glow(global_position + Vector3.UP * 0.9, col, 1.4, 0.6)

func _recall_vfx_tick(delta: float, k_in: float = -1.0) -> void:
	_recall_vfx_t += delta
	var k: float = k_in if k_in >= 0.0 else clampf(1.0 - recall_timer / RECALL_DURATION, 0.0, 1.0)
	if is_instance_valid(_recall_ring):
		_recall_ring.rotation.y += delta * 2.4
		var s: float = 1.0 + sin(_recall_vfx_t * 3.4) * 0.05 + k * 0.18
		_recall_ring.scale = Vector3(s, 1.0, s)
	if is_instance_valid(_recall_pillar):
		var ph: float = 0.35 + k * 0.85
		_recall_pillar.scale = Vector3(1.0, ph, 1.0)
		_recall_pillar.position.y = 3.0 * ph
	if is_instance_valid(_recall_spark):
		_recall_spark.emitting = true
	# 外圈反向旋转 + 呼吸；进度越高转得越快
	if is_instance_valid(_recall_ring2):
		_recall_ring2.rotation.y -= delta * (1.7 + k * 2.2)
		var s2: float = 1.0 + sin(_recall_vfx_t * 2.1) * 0.04 + k * 0.10
		_recall_ring2.scale = Vector3(s2, 1.0, s2)
	if is_instance_valid(_recall_glow):
		var gm: StandardMaterial3D = _recall_glow.material_override as StandardMaterial3D
		if gm != null:
			gm.albedo_color.a = 0.10 + k * 0.30
		var gs: float = 0.92 + sin(_recall_vfx_t * 2.6) * 0.05 + k * 0.16
		_recall_glow.scale = Vector3(gs, 1.0, gs)

func _recall_vfx_stop() -> void:
	if is_instance_valid(_recall_ring):
		_recall_ring.queue_free()
	if is_instance_valid(_recall_ring2):
		_recall_ring2.queue_free()
	if is_instance_valid(_recall_glow):
		_recall_glow.queue_free()
	if is_instance_valid(_recall_pillar):
		_recall_pillar.queue_free()
	if is_instance_valid(_recall_spark):
		_recall_spark.queue_free()
	_recall_ring = null
	_recall_ring2 = null
	_recall_glow = null
	_recall_pillar = null
	_recall_spark = null

# 孙悟空：筋斗云回城
func _start_wukong_cloud():
	if wukong_cloud_flying: return
	wukong_cloud_flying = true
	wukong_cloud_phase = 0
	collision_layer = 0   # 筋斗云全程无视碰撞（起飞即关闭，避免升空阶段被墙体推离）
	wukong_cloud_timer = 0.5
	wukong_cloud_speed = 0.0
	wukong_cloud_target = Vector3(-62, 0, 62) if team == Config.Team.PLAYER else Vector3(62, 0, -62)   # 落点=泉水圆心
	bt_timer = 1.5  # 腾空+飞行初期霸体
	# 筋斗云视觉：脚下云团 + 起飞爆发；飞行中随速度前倾/拉长、云絮拖尾
	if _wukong_cloud_vis == null or not is_instance_valid(_wukong_cloud_vis):
		_wukong_cloud_vis = WukongCloud.build()
		add_child(_wukong_cloud_vis)
		_wukong_cloud_vis.scale = Vector3(0.35, 0.35, 0.35)
		var tw := create_tween()
		tw.tween_property(_wukong_cloud_vis, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	WukongCloud.burst(global_position)
	# 取消当前攻击/施法
	casting_skill = false
	current_target = null
	manual_target = null
	move_target = Vector3.ZERO

func _end_wukong_cloud():
	wukong_cloud_flying = false
	wukong_cloud_phase = 0
	wukong_cloud_speed = 0.0
	collision_layer = 1
	# 落地：恢复Y坐标 + 云团收束爆发
	global_position.y = 0.0
	WukongCloud.burst(global_position)
	if _wukong_cloud_vis != null and is_instance_valid(_wukong_cloud_vis):
		var vis := _wukong_cloud_vis
		_wukong_cloud_vis = null
		var tw2 := create_tween()
		tw2.tween_property(vis, "scale", Vector3(0.05, 0.05, 0.05), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw2.tween_callback(vis.queue_free)

func _get_furthest_tripod() -> Node:
	var furthest = null
	var max_dist = -1.0
	for t in get_tree().get_nodes_in_group("tripods"):
		if t.team == team and is_instance_valid(t):
			var d = global_position.distance_to(t.global_position)
			if d > max_dist: max_dist = d; furthest = t
	return furthest

func _start_tripod_teleport(tripod):
	dayu_teleport_channeling = true
	dayu_teleport_progress = 0.0
	dayu_teleport_target = tripod.global_position
	dayu_teleport_cd = 60.0
	_recall_vfx_start(Color(0.55, 0.85, 0.45) if team == Config.Team.PLAYER else Color(1.0, 0.70, 0.40))
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm: bm.add_teleport_line(self, dayu_teleport_target)

func apply_regen(hp_per_sec: float, mp_per_sec: float, duration: float, source: String, tick_interval: float = 0.0):
	active_regen[source] = {"hp": hp_per_sec, "mp": mp_per_sec, "timer": duration, "tick": tick_interval, "acc": 0.0}

# 统一回血入口：所有治疗/生命回复都经此（累加治疗量用于赛后统计，按重伤削减、不死鸟之眼被动）。
# 返回实际回血量；amount<=0 或已死亡时不产生回血。
func _apply_healing(amount: float) -> float:
	if amount <= 0 or health <= 0: return 0.0
	amount *= grievous_wounds
	if equipment_slots.has("eye_of_the_phoenix"):
		var mp = (actual_max_health - health) / actual_max_health
		var pb = int(mp * 10) * 0.05
		amount *= pb
	var actual = min(amount, max(actual_max_health - health, 0.0))
	if actual > 0:
		healing_done += actual
		health += actual
	return max(actual, 0.0)

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false, skill_id:int=-1, pen_percent: float = 0.0, is_crit_forced: int = -1):
	if training_invincible:
		return
	# 先调用基类处理护盾/伤害
	if wd_timer>0:
		return
	# 传送阵/召唤师传送引导中受到敌方攻击 → 立即打断传送
	if is_teleporting and source != null and is_instance_valid(source) and source.team != team:
		_interrupt_teleport()
	# 记录真实的英雄伤害来源与命中位置：防御塔只据此判断「是否在塔内打了己方英雄」
	if source is Hero and source.team != team:
		last_hero_attacker = source as Hero
		last_hero_attacker_at = Time.get_ticks_msec() * 0.001
		last_hero_attacked_from = source.global_position
		last_hero_attacked_at = global_position
	# 孙悟空1技能：格挡一次敌方技能
	if sunwukong_1_block_active and skill_id > 0 and source != null and is_instance_valid(source) and source.team != team:
		sunwukong_1_block_active = false
		wd_timer = 0.2
		var _sh_bonus_hp = actual_max_health - max_health
		var _shield_val = int(500 + 100*(skill_levels[0]-1) + 1.5*bonus_attack + 0.15*_sh_bonus_hp)
		shield_remaining = max(shield_remaining, _shield_val)
		shield_timer = 4.0
		return
	amount = max(amount - parry, 0)
	# 影忍之足：减少6-12%物理伤害
	if equipment_slots.has("armor_boots") and not is_magic:
		amount *= (1.0 - (0.06 + level * 0.004))
	# 打野刀：对野怪减伤25%
	if source is JungleMonster:
		var has_jg = false
		for jid in equipment_slots:
			var jitem = ItemDatabase.get_item(jid)
			if jitem.get("class", "") == "jungle": has_jg = true; break
		if has_jg: amount *= 0.75
	# 破军：对生命低于50%的敌人额外造成30%伤害
	if source is Hero and source.equipment_slots.has("breaker") and health < max_health * 0.5:
		amount *= 1.3
	# 不祥征兆：减少攻击者攻速移速(2.5s)
	if equipment_slots.has("omen") and source and source != self:
		source.apply_attack_pct_buff("as_slow", 2.5, -(0.2 + level * 0.013), true)
		source.apply_move_pct_buff("ms_slow", 2.5, -(0.075 + level * 0.005), true)
	# 暴烈之甲：受击叠层(最多10层,3s)
	if equipment_slots.has("fierce_armor"):
		fierce_armor_stacks = min(fierce_armor_stacks + 1, 10)
		fierce_armor_timer = 3.0
	# 永夜守护：追踪2.5秒内受伤量
	if equipment_slots.has("night_guardian"):
		if night_guardian_timer <= 0:
			night_guardian_hp_track = 0
			night_guardian_timer = 2.5
		night_guardian_hp_track += amount
	# 反伤刺甲：主动期间35%真伤反弹
	if thornmail_active and source and source.team != team:
		source.take_true_damage(amount * 0.35, self, false, -42, 1.0)
	# 名刀·司命：受到致命伤害时触发无敌(120s CD, 最多3次)
	if health > 0 and health - amount <= 0 and equipment_slots.has("famous_blade") and famous_blade_cd <= 0 and famous_blade_uses < 3:
		famous_blade_cd = 120.0
		famous_blade_uses += 1
		wd_timer = 1.0
		apply_move_pct_buff("ms_haste", 1.0, 0.15)
		var ui_node = get_tree().get_first_node_in_group("ui") as UI_Manager
		if ui_node: ui_node.show_kill_feed(display_name, team, "名刀触发(%d/3)" % famous_blade_uses)
		return
	
	super.take_damage(amount, source, is_magic, skill_id, pen_percent, is_crit_forced)
	# 夏侯惇被动：HP<50%受伤触发噬目
	if display_name == "夏侯惇" and health > 0 and health < actual_max_health * 0.5 and xiahou_passive_cd <= 0 and not xiahou_passive_active:
		xiahou_passive_active = true
		xiahou_passive_timer = 8.0
		xiahou_passive_cd = 25.0
	# 东皇R: 压制双方承受等量伤害
	if donghuang_suppress_target and is_instance_valid(donghuang_suppress_target) and suppress_timer > 0:
		
		donghuang_suppress_target.take_damage(amount, self, is_magic, skill_id, pen_percent)
	# 极寒风暴：单次伤害>10%当前HP→冰爆AoE(2s CD)
	if equipment_slots.has("ice_storm") and ice_storm_cd <= 0 and source and amount > health * 0.1:
		ice_storm_cd = 2.0
		var is_dmg = 130 + level * 8.6
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent != self and ent.health > 0 and ent.team != team:
				if ent.global_position.distance_to(source.global_position) <= 3.0:
					ent.take_damage(is_dmg, self, true, -33, 0)
					ent.apply_attack_pct_buff("as_slow", 2.0, -0.15, true)
					ent.apply_move_pct_buff("ms_slow", 2.0, -(0.15 + level * 0.01), true)
		# 视觉
		var ring = MeshFactory.create_torus_ring(3.0, 3.2, Color.CYAN, false, 0.6, true)
		ring.position = source.global_position + Vector3.UP * 0.5
		get_parent().add_child(ring)
		var tw3 = create_tween(); tw3.tween_interval(0.5); tw3.tween_callback(ring.queue_free)
	# 疾步之靴：战斗重置计时
	if source and (source is Hero or self is Hero):
		boots_speed_timer = 0.0
	# 记录防御塔攻击
	if source is Turret and source.team != team:
		under_tower_attack = true
		tower_attacker = source
		tower_attack_timer = 1.0 
	
	if is_recalling and not dayu_teleport_channeling:
		cancel_recall()
	# 冰霜冲击：受到伤害时获得10%HP护盾(15s CD)
	if equipment_slots.has("ice_shock") and ice_shock_shield_cd <= 0:
		ice_shock_shield_cd = 15.0
		shield_remaining = max(shield_remaining, actual_max_health * 0.1)
		shield_timer = 5.0
	# 霸者重装：受到英雄/塔伤害重置计时
	if source is Hero or source is Turret:
		heavy_armor_last_hit = 0.0
	for src in active_regen.keys():
				if src != "fountain":
					active_regen.erase(src)
	# ... 其他初始化代码 ...

func _create_attack_range_ring():
	# 贴地攻击范围圈（柔化环带 + 磨损斑驳，随野区起伏贴地），替代原来的纯色 Torus 环
	attack_range_ring = MeshFactory.create_ground_ring(attack_range*0.01, Color(1, 1, 1, 0.32), 96.0)
	# 统一抬到所有地面之上（高地砖面约 0.20、分路 0.14），避免强化范围环被高地平面盖住
	attack_range_ring.position.y = Config.GROUND_FX_Y
	attack_range_ring.visible = false   # 只在普攻出手瞬间短暂显示
	add_child(attack_range_ring)

## 普攻出手时亮一圈（0.45s 后自动收起），让玩家看清本次攻击的判定范围
func flash_attack_range_ring(duration: float = 0.45) -> void:
	if is_ai:
		return
	_aa_ring_show_timer = maxf(_aa_ring_show_timer, duration)
	_update_attack_range_ring()
	if attack_range_ring and is_instance_valid(attack_range_ring):
		attack_range_ring.visible = true

func _update_attack_range_ring():
	if attack_range_ring and is_instance_valid(attack_range_ring):
		var leap := _enhanced_aa_queued()
		var reach := _aa_engage_reach()  # 跳跃强化普攻就绪时 = 攻击距离×2
		attack_range_ring.scale = Vector3(reach, 1.0, reach)
		# 跳跃强化普攻：金色更亮；平时白色半透（与地面混合，不抢眼）
		MeshFactory.set_ground_ring_color(attack_range_ring,
			Color(1.0, 0.82, 0.25, 0.55) if leap else Color(1.0, 1.0, 1.0, 0.32))
		_aa_ring_leap = leap
# ==================== 草丛(同一排)视野 ====================
# Bush 通过 Area3D 进出事件维护英雄所在草区域(region)的重叠计数
func enter_bush_region(region_id: int) -> void:
	if region_id < 0: return
	_bush_region_counts[region_id] = int(_bush_region_counts.get(region_id, 0)) + 1

func exit_bush_region(region_id: int) -> void:
	if region_id < 0: return
	var c: int = int(_bush_region_counts.get(region_id, 0)) - 1
	if c <= 0:
		_bush_region_counts.erase(region_id)
	else:
		_bush_region_counts[region_id] = c

# 每帧刷新草丛隐藏状态：有敌方英雄身处同一连片草丛(region)时，互相暴露(可见可攻击)
func _update_bush_stealth() -> void:
	hidden_in_bush = false
	if _bush_region_counts.is_empty():
		return
	for r in _bush_region_counts.keys():
		for ent in get_tree().get_nodes_in_group("heroes"):
			if not is_instance_valid(ent) or not (ent is Hero):
				continue
			if ent == self or ent.team == team or ent.health <= 0:
				continue
			if (ent as Hero)._bush_region_counts.has(r):
				return   # 有敌方英雄同在草丛：保持暴露
	hidden_in_bush = true


# 敌方视野语义：兰陵王·影袭隐身 / 幽影袖箭隐身 —— 完全不可见（视觉与索敌），但仍参与碰撞阻挡
func is_invisible_to_enemy() -> bool:
	return lanling_stealth_active or shadow_dart_active

# 敌方当前不可被锁定/选中的全集：草丛隐身 / 无敌·不可选中(李白W·金身 wd_timer) / 隐身
# AI 视野与双方索敌（普攻/技能/空格/点击/自动索敌）统一走这一判断
func is_untargetable_by_enemies() -> bool:
	return hidden_in_bush or wd_timer > 0.0 or lanling_stealth_active or shadow_dart_active

func _ready():
	add_to_group("heroes")
	_create_visual()
	if not is_ai:
		_create_attack_range_ring()
	kill_exp = 200
	kill_gold = 200
	last_health = health
	skillapply = SkillApplier.new()
	add_child(skillapply)  # 必须加入场景树，否则SkillApplier内create_tween失效
	# 装备被动组件
	item_passive = ItemPassive.new()
	add_child(item_passive)
	# 英雄被动组件
	hero_passive = HeroPassive.new()
	add_child(hero_passive)
	# 技能预览：贴地能量带（线性/位移技能用）
	arrow_preview = Node3D.new()
	arrow_preview.visible = false
	arrow_shaft = MeshFactory.create_cast_line(Color(0.30, 0.72, 1.0))
	arrow_shaft.position = Vector3(0, 0, 0.5)
	arrow_shaft.scale = Vector3(0.9, 1.0, 1.0)
	arrow_preview.add_child(arrow_shaft)
	# 终点准星：四段括号 + 十字线，替代原来的锥体箭头
	arrow_head = MeshFactory.create_cast_reticle(Color(0.36, 0.80, 1.0))
	arrow_head.position = Vector3(0, 0, 1.0)
	arrow_preview.add_child(arrow_head)
	add_child(arrow_preview)

	# AOE落点：柔和填充 + 外环 + 准星（着色器贴地面片）
	aoe_fill = MeshFactory.create_cast_area(Color(0.30, 0.72, 1.0), 0)
	aoe_fill.visible = false
	add_child(aoe_fill)

	# 施法范围指示：双层光环 + 刻度虚线 + 流转符文
	cast_range_ring = MeshFactory.create_cast_range(Color(0.32, 0.72, 1.0))
	cast_range_ring.visible = false
	add_child(cast_range_ring)
	# 命中半径圈：给 radius>0 的技能补第二段落点范围（不改变原技能类型预览）
	impact_ring = MeshFactory.create_cast_area(Color(0.30, 0.72, 1.0), 0)
	impact_ring.visible = false
	add_child(impact_ring)
	# 锁定目标标识（默认隐藏）
	_build_target_reticle()

	# 普攻轮盘选敌准星（拖动普攻键时高亮即将锁定的目标）
	attack_aim_marker = MeshFactory.create_torus_ring(0.4, 0.55, Color(1.0, 0.65, 0.25), true, 0.6)
	attack_aim_marker.visible = false
	add_child(attack_aim_marker)
	# 技能预览法阵：瞄准任意技能时浮现在脚底（柔光底 + 双层反向光环 + 刻度符文）
	_build_foot_sigil()

# ==================== 锁定目标标识 ====================
# 玩家锁定目标时显示：四角括号（呼吸收束）+ 内外反向旋转刻度环 + 头顶下压标记 + 脚下光圈
func _reticle_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _reticle_bar(box_size: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.material_override = _reticle_mat(color, alpha)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	return mi

func _build_target_reticle() -> void:
	target_indicator = Node3D.new()
	target_indicator.name = "TargetReticle"
	target_indicator.visible = false
	add_child(target_indicator)
	var gold := Color(1.0, 0.78, 0.36)
	var hot := Color(1.0, 0.93, 0.76)
	# 内环：细金环，慢速顺转
	_reticle_spin_a = Node3D.new()
	_reticle_spin_a.name = "SpinInner"
	target_indicator.add_child(_reticle_spin_a)
	var inner_ring := MeshFactory.create_torus_ring(0.72, 0.77, gold, true, 0.85, true)
	inner_ring.material_override = _reticle_mat(gold, 0.85)
	inner_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_spin_a.add_child(inner_ring)
	# 外环：8 段刻度，快速逆转，读作“扫描”
	_reticle_spin_b = Node3D.new()
	_reticle_spin_b.name = "SpinTicks"
	target_indicator.add_child(_reticle_spin_b)
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		var seg := _reticle_bar(Vector3(0.18, 0.016, 0.034), gold, 0.8)
		seg.position = Vector3(cos(ang) * 0.95, 0.0, sin(ang) * 0.95)
		seg.rotation.y = -(ang + PI * 0.5)
		_reticle_spin_b.add_child(seg)
	# 四角括号：挂在朝向相机的立面上（经典锁定框形态），呼吸时整体向内收紧
	_reticle_billboard = Node3D.new()
	_reticle_billboard.name = "Billboard"
	target_indicator.add_child(_reticle_billboard)
	var half := 0.62
	for i in range(4):
		var sx: float = 1.0 if (i == 0 or i == 3) else -1.0
		var sy: float = 1.0 if i < 2 else -1.0
		var br := Node3D.new()
		br.name = "Bracket%d" % i
		br.position = Vector3(sx * half, sy * half, 0.0)
		var arm_x := _reticle_bar(Vector3(0.24, 0.04, 0.02), hot, 0.95)
		arm_x.position = Vector3(-sx * 0.12, 0.0, 0.0)
		br.add_child(arm_x)
		var arm_y := _reticle_bar(Vector3(0.04, 0.24, 0.02), hot, 0.95)
		arm_y.position = Vector3(0.0, -sy * 0.12, 0.0)
		br.add_child(arm_y)
		_reticle_billboard.add_child(br)
		_reticle_brackets.append(br)
	# 头顶下压标记：倒锥 + 细环，轻微起伏（同立面内，始终朝向相机）
	_reticle_top = Node3D.new()
	_reticle_top.name = "TopMark"
	_reticle_top.position = Vector3(0.0, half + 0.36, 0.0)
	_reticle_billboard.add_child(_reticle_top)
	var cone := MeshFactory.create_cylinder(0.12, 0.0, 0.24, hot, 0.95)
	cone.material_override = _reticle_mat(hot, 0.95)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_top.add_child(cone)
	var top_ring := MeshFactory.create_torus_ring(0.21, 0.26, gold, true, 0.7, true)
	top_ring.material_override = _reticle_mat(gold, 0.7)
	top_ring.position = Vector3(0.0, 0.18, 0.0)
	top_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_top.add_child(top_ring)
	# 脚下光圈：暗金虚环 + 12 道刻度，缓慢旋转
	_reticle_ground = Node3D.new()
	_reticle_ground.name = "GroundRing"
	_reticle_ground.position = Vector3(0.0, -1.28, 0.0)
	target_indicator.add_child(_reticle_ground)
	var gr := MeshFactory.create_torus_ring(0.60, 0.66, Color(1.0, 0.55, 0.16), true, 0.42, true)
	gr.material_override = _reticle_mat(Color(1.0, 0.55, 0.16), 0.42)
	gr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_ground.add_child(gr)
	for i in range(12):
		var ang: float = TAU * float(i) / 12.0
		var tick := _reticle_bar(Vector3(0.08, 0.012, 0.028), gold, 0.32)
		tick.position = Vector3(cos(ang) * 0.72, 0.0, sin(ang) * 0.72)
		tick.rotation.y = -(ang + PI * 0.5)
		_reticle_ground.add_child(tick)

func _update_target_reticle(delta: float) -> void:
	_reticle_t += delta
	var t := _reticle_t
	if _reticle_spin_a != null:
		_reticle_spin_a.rotation.y += delta * 0.55
	if _reticle_spin_b != null:
		_reticle_spin_b.rotation.y -= delta * 1.35
	if _reticle_ground != null:
		_reticle_ground.rotation.y += delta * 1.05
	if _reticle_top != null:
		_reticle_top.position.y = 0.98 + 0.05 * sin(t * 3.6)
	# 括号：立面转向相机 + 呼吸收紧（锁定感）
	if _reticle_billboard != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to_cam: Vector3 = cam.global_position - target_indicator.global_position
			_reticle_billboard.rotation.y = atan2(to_cam.x, to_cam.z)
		var breath: float = 0.5 + 0.5 * sin(t * 4.2)
		_reticle_billboard.scale = Vector3.ONE * (1.0 - 0.06 * breath)
		_reticle_billboard.position.y = 0.025 * sin(t * 4.2)

# 脚底技能预览法阵（创建一次，预览时显隐）
func _build_foot_sigil() -> void:
	var col: Color = Vfx.color_for_hero(display_name)
	_foot_sigil = Node3D.new()
	_foot_sigil.visible = false
	_foot_sigil.position = Vector3(0.0, Config.GROUND_FX_Y + 0.02, 0.0)
	add_child(_foot_sigil)
	# 柔光底 + 外圈呼吸环
	_foot_sigil.add_child(Vfx.preview_ring(2.25, team))
	# 外层环（顺时针）
	var outer := MeshFactory.create_torus_ring(2.02, 2.16, col, true, 0.9, true)
	outer.name = "SigilOuter"
	_foot_sigil.add_child(outer)
	# 内层环（逆时针）+ 内圈细环
	var inner := MeshFactory.create_torus_ring(1.28, 1.4, col.lerp(Color.WHITE, 0.35), true, 0.85, true)
	inner.name = "SigilInner"
	_foot_sigil.add_child(inner)
	var core := MeshFactory.create_torus_ring(0.72, 0.8, col.lerp(Color.WHITE, 0.55), true, 0.7, true)
	_foot_sigil.add_child(core)
	# 12 道刻度符文：短条沿半径方向，读作法阵刻线
	var runes := Node3D.new()
	runes.name = "SigilRunes"
	_foot_sigil.add_child(runes)
	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = col.lerp(Color.WHITE, 0.5)
	rune_mat.emission_enabled = true
	rune_mat.emission = col
	rune_mat.emission_energy_multiplier = 2.4
	rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune_mat.albedo_color.a = 0.85
	rune_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for i in range(12):
		var tick := MeshInstance3D.new()
		var tb := BoxMesh.new()
		var long_tick := i % 3 == 0
		tb.size = Vector3(0.09 if long_tick else 0.06, 0.02, 0.42 if long_tick else 0.24)
		tick.mesh = tb
		var ang := TAU * float(i) / 12.0
		tick.position = Vector3(cos(ang), 0.0, sin(ang)) * 1.72
		tick.rotation.y = -ang
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tick.material_override = rune_mat
		runes.add_child(tick)
	# 旋转：外环顺时针、内环逆时针、符文层顺时针（不同速度，形成法阵运转感）
	var t1 := outer.create_tween()
	t1.set_loops()
	t1.tween_property(outer, "rotation:y", TAU, 7.0).from(0.0)
	var t2 := inner.create_tween()
	t2.set_loops()
	t2.tween_property(inner, "rotation:y", -TAU, 4.6).from(0.0)
	var t3 := runes.create_tween()
	t3.set_loops()
	t3.tween_property(runes, "rotation:y", -TAU, 11.0).from(0.0)
func buy_equipment(item_id: String) -> bool:
	var item_data = ItemDatabase.get_item(item_id)
	if item_data.is_empty(): return false
	# 计算：移除已拥有的素材，不足的部分补全款
	var owned_components = []
	var requires = item_data.get("requires", [])
	var remaining = requires.duplicate()
	for oid in equipment_slots:
		var idx = remaining.find(oid)
		if idx >= 0:
			owned_components.append(oid)
			remaining.remove_at(idx)
	# 计算花费：总价 - 已拥有素材价值
	var component_value = 0
	for cid in owned_components:
		var ci = ItemDatabase.get_item(cid)
		if not ci.is_empty(): component_value += ci["cost"]
	var actual_cost = item_data["cost"] - component_value
	# 槽位检查：合成后净槽位数 = 当前 - 消耗素材数 + 1(新装备)
	var net_slots = equipment_slots.size() - owned_components.size() + 1
	if net_slots > MAX_EQUIPMENT_SLOTS: return false
	if gold < actual_cost: return false
	gold -= actual_cost
	# 移除消耗的素材
	for cid in owned_components:
		equipment_slots.erase(cid)
	equipment_slots.append(item_id)
	_recalculate_attributes()
	return true

# 新增加钱方法
func add_gold(amount: int):
	gold += amount
	total_gold_earned += amount
func setup(config: Dictionary):
	super.setup(config)
	# Hero.gd 的 setup 中
	role = config.get("role", "战士")
	role_growth = ROLE_GROWTH.get(role, ROLE_GROWTH["战士"])
	match role:
		"射手": base_as = 1000
		"法师","刺客":base_as = 500
		"战士","坦克","辅助","肉辅":base_as = 0
	display_name = config.get("name", "英雄")
	gold = config.get("initial_gold", 300)   # 允许外部设置初始金币
	
	attack_speed_growth = config.get("attack_speed_growth", 0.02)   # 默认2%/级
	base_health = config.get("max_health", 3300)
	base_mana = config.get("max_mana", 0)
	base_attack = config.get("attack", 170)
	base_armor =150
	base_magic_resist = 75
	base_move_speed = config.get("move_speed", 350)
	base_crit_damage = 1.85
	if display_name == "孙悟空":
		base_crit_chance = 0.20
		base_crit_damage = 1.50
	base_hp_regen = config.get("hp_reg", 50)
	base_mana_regen = config.get("mana_reg", 0)
	body_radius = 1.5

	level = 1
	# 初始1级
	skill_points = 1   # 1级时拥有1个技能点（可用来学习第一个技能，也可默认已学）
	exp = 0
	exp_to_next = 162
	_recalculate_attributes()
	health = actual_max_health
	mana = actual_mana_max

func _create_visual():
		# 红Buff圆环
	
	buff_ring_red = MeshFactory.create_buff_aura(0)
	buff_ring_red.position = Vector3(0, Config.GROUND_FX_Y, 0)
	buff_ring_red.visible = false
	add_child(buff_ring_red)

	# 蓝Buff光环（内圈霜雾；与红环同心，可同时显示）
	buff_ring_blue = MeshFactory.create_buff_aura(1)
	buff_ring_blue.position = Vector3(0, Config.GROUND_FX_Y + 0.01, 0)
	buff_ring_blue.visible = false
	add_child(buff_ring_blue)
	
	# 加载英雄角色模型
	visual_mesh = _load_hero_model()
	if visual_mesh:
		add_child(visual_mesh)
	else:
		# 回退：胶囊体
		var fallback = MeshInstance3D.new()
		fallback.mesh = CapsuleMesh.new()
		fallback.mesh.radius = 1.2
		fallback.mesh.height = 3
		fallback.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(fallback)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLUE if team == Config.Team.PLAYER else Color.RED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fallback.material_override = mat
		visual_mesh = fallback

	# 皮肤：玩家用已选皮肤；AI 用自动分配的定制皮肤；经典皮肤保留原模型
	if hero_skin_id == "":
		hero_skin_id = HeroSkinTable.auto_id(display_name, int(get_instance_id())) if is_ai else HeroSkinTable.selected_id(display_name)
	if hero_skin_id != "":
		HeroSkinTable.apply_to(visual_mesh, display_name, hero_skin_id)

	# 英睿：大招「变身LabiB」等身毛绒形态（同一 visual_mesh 下的兄弟节点，默认隐藏，变身时切换）
	if display_name == "英睿" and visual_mesh:
		yingrui_plush = HeroYingrui.build_labib()
		yingrui_plush.visible = false
		visual_mesh.add_child(yingrui_plush)

	# 角色可读性：rim 边缘光 + 脚下接地软阴影（仅 material_overlay / 独立子节点，不改原材质）
	UnitVisuals.attach_hero(self, team, visual_mesh)
	# 行走质感：步频起伏 + 左右摆 + 前倾 + 步点扬尘（只动模型，不改位移/碰撞）
	WalkFeel.attach(self, visual_mesh, ActorPresenter.walk_opts("hero", display_name, visual_mesh))

	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.5
	
	add_child(col)
		# 状态效果视觉指示器（脚下光环）

func apply_zhangfei_form_visual():
	# 张飞变身：模型放大 + 脚下金色Buff光环（真身提示）
	if visual_mesh:
		visual_mesh.scale = Vector3(1.25, 1.25, 1.25)
	if zhangfei_form_ring == null:
		zhangfei_form_ring = MeshFactory.create_torus_ring(1.1, 1.5, Color(1.0, 0.72, 0.12), true, 1.0, true)
		zhangfei_form_ring.position = Vector3(0, 0.08, 0)
		add_child(zhangfei_form_ring)
	else:
		zhangfei_form_ring.visible = true

func clear_zhangfei_form_visual():
	# 张飞变身结束：恢复模型大小并移除脚下光环
	if visual_mesh:
		visual_mesh.scale = Vector3.ONE
	if zhangfei_form_ring and is_instance_valid(zhangfei_form_ring):
		zhangfei_form_ring.queue_free()
	zhangfei_form_ring = null

func setup_skills_from_database(skill_ids: Array, summoner_id: String = ""):
	skills.clear()
	skill_cooldowns.clear()
	for id in skill_ids:
		
		if id == "" or id == null:
			continue
		var skill = SkillDatabase.get_skill(id).duplicate()
		if skill:
			skills.append(skill)
			skill_levels.append(0) 
			skill_restores.append(0)
			skill_uses.append(0)
			skill_window_timers.append(0)
			skill_cooldowns.append(0.0)
	if skill_cooldowns.size()<4:
		skills.append(null)
		skill_levels.append(0) 
		skill_restores.append(0)
		skill_uses.append(0)
		skill_window_timers.append(0)
		skill_cooldowns.append(0.0)
	else: skill_levels[3] = 0   # 第4技能：统一 4 级自动解锁（见 _check_fourth_skill_unlock），不占技能点
	var recover = SkillDatabase.get_skill("recover")
	if recover:
		skills.append(recover)
		skill_cooldowns.append(0.0)
		skill_restores.append(0)
		skill_levels.append(1) 
		skill_uses.append(0)
		skill_window_timers.append(0)
	if summoner_id != "":
		summoner_skill = SkillDatabase.get_skill(summoner_id)
		summoner_cooldown = 0.0
# Hero.gd
func on_kill(victim: GameEntity):
	kills += 1
	consecutive_kills += 1 
	
	var now = Time.get_ticks_msec() / 1000.0
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle: return
	# ----- 短时间连杀（10秒窗口） -----
	if now - last_kill_time <= 10.0:
		streak_count += 1
	else:
		streak_count = 1
	last_kill_time = now
	# 助攻者（与 BattleManager.on_hero_killed 同口径：击杀点 12m 内同队英雄，排除自己）
	var kf_assists: Array = []
	if victim is Hero:
		for e in get_tree().get_nodes_in_group("heroes"):
			if e is Hero and e != self and e.team == team \
					and e.global_position.distance_to(victim.global_position) < 12.0:
				kf_assists.append({"name": e.display_name, "team": e.team})
	if victim is Hero and victim.consecutive_kills >= 3:
		battle.ui.show_kill_feed(display_name, team, "终结", victim.display_name, victim.team, kf_assists)
		return

	var short_desc = ""
	match streak_count:
		2: short_desc = "二连击破"
		3: short_desc = "三连决胜"
		4: short_desc = "四连超凡"
		5: short_desc = "五连绝世"
		6: short_desc = "六杀"
		7: short_desc = "七杀"
		8: short_desc = "八杀"
		9: short_desc = "九杀"
		10: short_desc = "十杀"
	# 不死累计（consecutive_kills 已存在）：此段原被上面的短连杀分支 return 短路，
	# 造成 3/4/5 档永远不可达、超窗累计 6/7+ 也不报——现在窗口外普通击杀跨过档位也会补报。
	var cumulative_desc = ""
	match consecutive_kills:
		3: cumulative_desc = "大杀特杀"
		4: cumulative_desc = "杀人如麻"
		5: cumulative_desc = "势不可挡"
		6: cumulative_desc = "横扫千军"
		_: cumulative_desc = "天下无双" if consecutive_kills >= 7 else ""
	if battle.ui:
		if short_desc != "":
			# 10 秒窗口内的连续击杀：短连杀文案优先（二连击破~五连绝世）
			battle.ui.show_kill_feed(display_name, team, short_desc, victim.display_name, victim.team, kf_assists)
		elif cumulative_desc != "":
			# 窗口外击杀但累计连续击杀跨过档位：补报累计档（大杀特杀~天下无双）
			battle.ui.show_kill_feed(display_name, team, cumulative_desc, victim.display_name, victim.team, kf_assists)
		else:
			# 普通单杀（且未跨累计档位）
			battle.ui.show_kill_feed(display_name, team, "击败", victim.display_name, victim.team, kf_assists)
		
	# 原有金币奖励、击杀播报等...

	# ...原有死亡逻辑...
# 君临/暗影君临：命中触发闪电链（3s内置CD，持续90秒）
var tyrant_lightning_active: bool = false
var tyrant_lightning_shadow: bool = false   # 暗影君临：链伤害翻倍 + 移速加成
var tyrant_lightning_timer: float = 0.0
var tyrant_lightning_cd: float = 0.0
# 风暴觉醒：一次性护盾（50%最大生命）+ 每秒光环真伤（90秒）
var storm_aura_active: bool = false
var storm_aura_timer: float = 0.0
var storm_aura_tick: float = 0.0
var storm_shield_amount: float = 0.0
var storm_shield_timer: float = 0.0
var storm_aura_ring: Node3D = null   # 风暴觉醒光环视觉节点

# ==================== 阵亡状态清零 ====================
func _is_reset_state_var(n: String) -> bool:
	for s in STATE_RESET_SKIP:
		if n.begins_with(s):
			return false
	if STATE_RESET_KEEP.has(n):
		return false
	if STATE_RESET_EXACT.has(n):
		return true
	for s in STATE_RESET_SUFFIX:
		if n.ends_with(s):
			return true
	return false


## 出生首帧抓取"无状态"基线（只记录状态类变量，含继承自 GameEntity 的）
func _capture_state_baseline() -> void:
	if _base_state_captured:
		return
	for p in get_property_list():
		if (int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var n: String = p.name
		if not _is_reset_state_var(n):
			continue
		var v = get(n)
		if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
			_base_state_snap[n] = v.duplicate(true)
		else:
			_base_state_snap[n] = v
	_base_state_captured = true


## 死亡时把一切临时状态还原为出生基线；召唤师技能冷却、复活类与战绩类不动
func _reset_states_on_death() -> void:
	_clear_teleport_minion()
	_capture_state_baseline()
	var zf_was := zhangfei_transformed
	var yr_was := _yingrui_form_on
	var cloud_was := wukong_cloud_flying
	# 临时视觉节点：快照只能清变量，节点必须显式销毁否则会残留
	# （召唤物——大禹鼎、东皇能量体——不清：阵亡后仍保留，复活后继续存在）
	for node_name in ["_regen_ring", "_regen_fx", "_recall_ring", "_recall_ring2", "_recall_glow", "_recall_pillar", "_recall_spark",
			"storm_aura_ring", "libai_w_ring", "zhangfei_q_mesh"]:
		var nd = get(node_name)
		if nd != null and is_instance_valid(nd):
			(nd as Node).queue_free()
	for key in _base_state_snap.keys():
		var v = _base_state_snap[key]
		if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
			set(key, v.duplicate(true))
		else:
			set(key, v)
	# 快照外的硬清
	for arr in [skill_cooldowns, skill_window_timers, skill_restores]:
		if arr.size() < skills.size():
			arr.resize(skills.size())
		for i in range(arr.size()):
			arr[i] = 0.0
	channeling_skill_index = -1
	channeling_preview_pos = Vector3.ZERO
	casting_skill = false
	pending_skill_index = -1
	pending_skill_target = Vector3.ZERO
	pending_skill_target_entity = null
	manual_target = null
	current_target = null
	remove_cc_speed_buffs()
	if is_recalling:
		cancel_recall()
	if zf_was:
		clear_zhangfei_form_visual()
	if yr_was:
		_yingrui_apply_form(false)
	if cloud_was:
		_end_wukong_cloud()
	if buff_ring_red:
		buff_ring_red.visible = false
	if buff_ring_blue:
		buff_ring_blue.visible = false
	_update_shield_visual()
	# Buff 清空后重算属性（攻击/双抗/移速回落装备+等级基准）
	_recalculate_attributes()


## 阵亡倒地：保留模型，优先播死亡剪辑，否则绕脚原点前倒 90° 躺地
func _start_death_pose() -> void:
	_death_pose = true
	if _death_pose_tween != null and _death_pose_tween.is_valid():
		_death_pose_tween.kill()
	_death_pose_tween = null
	if anim_player != null:
		for nm in ["die", "death", "Die", "Death", "dead"]:
			if anim_player.has_animation(nm):
				anim_player.play(nm)
				current_anim = nm
				break
	# 注意：visual_mesh 外层被 WalkFeel 每帧归位旋转，不能直接转；转它下面的模型实例
	_death_vis_node = null
	if visual_mesh != null and is_instance_valid(visual_mesh):
		for ch in visual_mesh.get_children():
			if ch is Node3D:
				_death_vis_node = ch
				break
		if _death_vis_node == null:
			_death_vis_node = visual_mesh
	if _death_vis_node == null or not is_instance_valid(_death_vis_node):
		return
	_death_vis_rot = _death_vis_node.rotation
	_death_vis_pos = _death_vis_node.position
	_death_pose_tween = create_tween()
	_death_pose_tween.set_parallel(true)
	_death_pose_tween.tween_property(_death_vis_node, "rotation:x", _death_vis_rot.x - PI * 0.5, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_pose_tween.tween_property(_death_vis_node, "position:y", _death_vis_pos.y + 0.06, 0.32)


## 复活起身：恢复模型姿态
func _end_death_pose() -> void:
	if not _death_pose:
		return
	_death_pose = false
	if _death_pose_tween != null and _death_pose_tween.is_valid():
		_death_pose_tween.kill()
	_death_pose_tween = null
	if _death_vis_node != null and is_instance_valid(_death_vis_node):
		_death_vis_node.rotation = _death_vis_rot
		_death_vis_node.position = _death_vis_pos
	_death_vis_node = null
	if anim_player != null and current_anim in ["die", "death", "Die", "Death", "dead"]:
		anim_player.stop()
		current_anim = ""
		_play_anim("idle")

func die(killer):
	if is_dead:
		return
	if is_reviving:
		return  # 复活倒计时中：禁止再次进入死亡流程（防重复击杀奖励/重复消耗复活次数）
	# 调试：die调用日志（重复出现=死亡流程被多次触发）
	if BattleManager.debug_kill_rewards:
		var _k = killer.display_name if killer else "无"
		print("[die调用] %s killer=%s 太乙保护=%s 贤者=%s revive_count=%d" % [display_name, _k, str(taiyi_protected), str(equipment_slots.has("revive")), revive_count])
	# 太乙R复活
	if taiyi_protected and taiyi_protect_timer > 0:
		taiyi_protected = false; taiyi_protect_timer = 0.0
		revive_timer = 2.0
		is_reviving = true
		# 漂亮辅助：我方太乙大招把队友从死亡边缘救回
		if Config.is_ally(team):
			var bm_taiyi := get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if bm_taiyi:
				bm_taiyi.trigger_special_announce("assist_play", 8.0)
		return
	# 贤者的庇护：死亡后复活(最多2次,150s CD)
	if equipment_slots.has("revive") and revive_count < 2 and revive_cd <= 0:
		revive_count += 1
		revive_cd = 150.0
		
		revive_timer = 2.0
		is_reviving = true
		revive_hp = 2000+67*level
		stun_timer = 0; knockup_timer = 0; remove_cc_speed_buffs()
		var ui_node = get_tree().get_first_node_in_group("ui") as UI_Manager
		if ui_node: ui_node.show_kill_feed(display_name, team, "复活中")
		return
	deaths += 1
	kill_gold = 200
	is_dead = true
	# 本地玩家阵亡短音（复活类提前 return，不在此响）
	SfxManager.try_death_sfx(display_name)
	respawn_timer = RESPAWN_BASE_TIME + (level - 1) * RESPAWN_SCALE * 2
	respawn_time_total = RESPAWN_BASE_TIME + (level - 1) * RESPAWN_SCALE * 2
	# 阵亡：保留模型 + 播倒地（有 death 剪辑用剪辑，否则程序化前倒），躺到复活
	visible = true
	_start_death_pose()
	collision_layer = 0
	stun_timer = 0.0; knockup_timer = 0.0; remove_cc_speed_buffs()
	shield_remaining = 0.0; shield_timer = 0.0
	move_target = Vector3.ZERO
	# 死亡后清空A*导航状态（防复活后沿旧路径移动）
	_nav_path = PackedVector3Array()
	_nav_index = 0
	_nav_target = Vector3.ZERO
	manual_target = null
	current_target = null
	channeling_skill_index = -1
	if display_name == "沈梦溪":
		shen_fuse_active = false   # 引燃死亡即熄灭（防复活后原地自动引爆）
		shen_barrage_active = false   # 死亡清掉连发占用标记，避免复活后1技能被自己挡住
		if 1 < skill_window_timers.size():
			skill_window_timers[1] = 0
	consecutive_kills = 0
	# 筋斗云中断（飞行中死亡）
	wukong_cloud_flying = false
	wukong_cloud_phase = 0
	wukong_cloud_speed = 0.0
	# 全部临时状态清零（技能冷却/被动层数/Buff/控制/装备被动计时…；召唤师技能冷却除外）
	_reset_states_on_death()
	# 团灭判定：本英雄阵亡后若整队同时阵亡 → host 结算 团灭(我方被灭)/完美团战(我方团灭敌方)
	var bm_wipe := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm_wipe:
		bm_wipe.check_team_wipe(self)

func _respawn():
	_end_death_pose()
	if display_name == "沈梦溪":
		stat = 10
	is_dead = false
	health = actual_max_health
	mana = actual_mana_max
	visible = true
	collision_layer = 1
	if team == Config.Team.PLAYER:
		global_position = Vector3(-60, 0, 60)
	else:
		global_position = Vector3(60, 0, -60)
	# 复活不清空技能/召唤师冷却（死亡期间已照常推进到对应剩余值）
	attack_timer = 0.0
func start_teleport(target: Vector3, minion: Minion = null):
	_clear_teleport_minion()
	is_teleporting = true
	teleport_progress = 0.0
	teleport_target_pos = target
	teleport_minion = minion
	if teleport_minion != null and is_instance_valid(teleport_minion):
		teleport_minion.set_teleport_channel_protected(true)
	# 传送引导动画：紫蓝色法阵，与回城同款但换色
	_recall_vfx_start(Color(0.62, 0.48, 1.0) if team == Config.Team.PLAYER else Color(1.0, 0.45, 0.72))
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm and teleport_target_pos != Vector3.ZERO:
		bm.add_teleport_line(self, teleport_target_pos)
	# 传送已开始：小地图立即从放大的选点模式退回正常位置/尺寸
	if bm and bm.minimap:
		bm.minimap.exit_teleport_mode()

# 解除传送落点小兵的保护（完成/打断/死亡都走这里）
func _clear_teleport_minion() -> void:
	if teleport_minion != null and is_instance_valid(teleport_minion):
		teleport_minion.set_teleport_channel_protected(false)
	teleport_minion = null


# 传送被打断：清进度/法阵/连线，并让小地图恢复正常
func _interrupt_teleport() -> void:
	if not is_teleporting:
		return
	var target := teleport_target_pos
	is_teleporting = false
	teleport_progress = 0.0
	_clear_teleport_minion()
	_recall_vfx_stop()
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if bm:
		bm.remove_teleport_line(self, target)
		if bm.minimap:
			bm.minimap.exit_teleport_mode()

# 位移表现统一入口：不再瞬移，而是在 dur 秒（约 7~10 帧）内快速滑到落点，并让英雄做出冲刺/跳跃动作。
# anim 传 "" 表示不覆盖当前动作（例如突进普攻已在播攻击动作）。
func dash_move_to(target: Vector3, dur: float = 0.16, anim: String = "sprint") -> void:
	var to := target
	to.y = global_position.y
	var from := global_position
	var flat := to - from
	flat.y = 0.0
	if flat.length() < 0.05:
		global_position = to
		return
	if dur <= 0.01:
		global_position = to
		return
	if _dash_tw != null and _dash_tw.is_valid():
		_dash_tw.kill()
	rotation.y = atan2(flat.x, flat.z)
	is_dashing = true
	if anim != "" and is_instance_valid(anim_player):
		_play_anim(anim)
		# 保护动作不被「移动→walk」立刻覆盖（约等于滑行时长）
		_aa_anim_until = maxf(_aa_anim_until, Time.get_ticks_msec() * 0.001 + dur + 0.05)
	_dash_tw = create_tween()
	_dash_tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dash_tw.tween_property(self, "global_position", to, dur)
	_dash_tw.finished.connect(_on_dash_finished.bind(anim))

func _on_dash_finished(anim: String) -> void:
	is_dashing = false
	if health > 0 and anim != "":
		_play_anim("idle")

# 技能/召唤师冷却统一递减（死亡/复活倒计时期间也照常走，复活时不清空）
func _tick_skill_cooldowns(delta):
	if training_no_cooldown:
		for j in range(skill_cooldowns.size()):
			skill_cooldowns[j] = 0.0
		summoner_cooldown = 0.0
		return
	for j in range(skill_cooldowns.size()):
		if skills[j] == null: continue
		if skill_cooldowns[j] > 0:
			if skill_window_timers[j] > 0: skill_window_timers[j] -= delta / actual_cd_timer
			else:
				skill_cooldowns[j] -= delta / actual_cd_timer
				skill_uses[j] = 0
		elif skill_restores[j] < skills[j].restore and skill_levels[j] > 0:
			skill_restores[j] += 1
			if skill_restores[j] < skills[j].restore:
				skill_cooldowns[j] = skills[j].cooldown - skills[j].cd_bonus * (skill_levels[j] - 1)
	if summoner_cooldown > 0:
		summoner_cooldown -= delta / actual_cd_timer

# 多段/重施窗口信息（供技能图标UI读取）。仅当该技能当前处于重施窗口时返回：
#   { total=总段数, used=已用段数, win_total=窗口总时长(秒), win_left=窗口剩余(秒) }
# 非多段技能 / 窗口未开启返回空字典（UI 不显示段数与窗口）。
# 各英雄段数语义须与 SkillDataBase 中的施放逻辑一致。
func get_multicast_window(slot: int) -> Dictionary:
	if slot >= skill_window_timers.size():
		return {}
	var win_left: float = float(skill_window_timers[slot])
	if win_left <= 0.0:
		return {}
	var total := 2
	var used := 1
	var win_total := 3.0
	if display_name == "李白" and slot == 0:      # 将进酒：3段（两段突进+返回原处）
		total = 3
		used = clampi(skill_uses[slot], 1, 3)
		win_total = 5.0
	elif display_name == "太乙真人" and slot == 0: # 炼药 → 引爆
		win_total = 5.0
	elif display_name == "夏侯惇" and slot == 0:   # 豪气斩：一段刃风 → 二段重击
		pass
	elif display_name == "大禹" and slot == 2:     # 大招：腾空击飞 → 传送至鼎
		pass
	elif display_name == "沈梦溪" and slot == 1:   # 点燃引信 → 引爆（重按/4秒后自然引爆，与太乙Q同模板）
		win_total = 4.0
	elif display_name == "英睿" and slot == 1:     # 肘击：3段
		total = 3
		used = clampi(yingrui_w_stage, 1, 3)
		win_total = 3.0
	else:
		return {}
	return {"total": total, "used": used, "win_total": win_total, "win_left": win_left}

# 马超大招的施放前提：12 单位内是否有可召回的枪（与 SkillDataBase 万刃归鞘的收枪距离一致）
func machao_has_spear() -> bool:
	if display_name != "马超":
		return true
	for o in objs:
		if is_instance_valid(o):
			if global_position.distance_to(o.global_position) < 12.0:
				return true
	return false

# 技能当前是否可立即施放（综合：蓝量 / 冷却 / 充能层数 / 特殊前提）。
#  - 普通技能：CD 归零且有蓝即可；
#  - 存储型(restore>0)：只要有已存层数即可放，CD 只代表「下一层回充中」；
#  - 多段重施窗口：窗口内始终可再按（段数>0）。
func skill_cast_ready(slot: int) -> bool:
	if slot < 0 or slot >= skills.size() or skills[slot] == null:
		return false
	var sk: Skill = skills[slot]
	if slot < skill_window_timers.size() and skill_window_timers[slot] > 0.0:
		return true
	if slot >= skill_levels.size() or skill_levels[slot] < 1:
		return false    # 未学习（如大招等级未到）不可施放
	# 蓝耗按技能等级缩放（与 _handle_skill_input 中 skill.mana_cost 的换算一致）
	var mcost := sk.mana_cost - sk.power_bonus * maxi(skill_levels[slot] - 1, 0)
	if mana < mcost:
		return false
	if sk.restore > 0.0:
		if slot >= skill_restores.size() or skill_restores[slot] <= 0:
			return false
	elif slot >= skill_cooldowns.size() or skill_cooldowns[slot] > 0.0:
		# 元流之子·流连发：冷却未走完但"流"充足（破釜≥4 / 万箭≥5）→ 放行；消耗在 _finish_casting 结算
		if display_name == "元流之子" and slot == 1 and yuanliu_flow >= 4:
			return true
		if display_name == "元流之子" and slot == 2 and yuanliu_flow >= 5:
			return true
		return false
	# 英雄前置状态门槛：李白大招需侠客行、沈梦溪1/2需炸弹、马超R需身边有枪、
	# 东皇2技能需能量球、兰陵王大招需隐身——不满足即不可施放（与触屏按钮 blocked 同源）
	if skill_prereq_blocked(slot):
		return false
	return true

# 前置门槛判定：某技能在“资源/状态未就绪”时根本放不出来（与按钮画斜杠一致）。
# 李白大招需侠客行；沈梦溪1(猫咪炸弹)/2(点燃引信)均需消耗1颗炸弹；马超大招需身边有枪；
# 东皇2(堕神契约)需至少1颗能量球；兰陵王大招(秘技·暗袭)需处于隐身。
# 显示层(TouchController blocked)与施放层(skill_cast_ready/_start_casting，含 AI 入口)共用，
# 保证按钮“不可用”与实际能否放出完全一致。
func skill_prereq_blocked(slot: int) -> bool:
	if slot < 0 or slot >= skills.size() or skills[slot] == null:
		return false
	match display_name:
		"李白":
			if slot == 2 and not libai_xia_active:
				return true
		"沈梦溪":
			# 1/2技能都耗弹；2技能点燃后的4秒引爆窗口内放行（再按=手动引爆，不耗弹）
			if (slot == 0 or slot == 1) and stat < 1.0:
				if slot == 1 and slot < skill_window_timers.size() and skill_window_timers[slot] > 0.0:
					return false
				return true
		"马超":
			if slot == 2 and not machao_has_spear():
				return true
		"东皇太一":
			if slot == 1 and donghuang_orbs <= 0:
				return true
		"兰陵王":
			if slot == 2 and not lanling_stealth_active:
				return true
	return false

# 按钮 blocked 提示语（与上方判断同源；空串=无前置门槛）
func skill_prereq_cue(slot: int) -> String:
	if not skill_prereq_blocked(slot):
		return ""
	match display_name:
		"李白": return "侠客"
		"沈梦溪": return "炸弹"
		"马超": return "无枪"
		"东皇太一": return "能量"
		"兰陵王": return "隐身"
	return ""

# 远程接管所用移动模式：peer 显式选择（C_DRIVE 携带）优先；未选则跟随主机当前全局模式，
# 保证与主机本地键盘/摇杆手感一致。
func _net_move_mode() -> int:
	if net_move_mode >= 0:
		return net_move_mode
	return TouchController.get_move_mode()

# —— 远程客户端预测用：把本帧主机实际采用的位移速度/阻断状态原样下发 ——
# 客户端不用猜移速（含前摇减速、暗影君临加速等烘焙项）与走A锁定，预测与主机逐帧同源。
func net_predict_speed() -> float:
	var mult := 1.0
	if tyrant_lightning_active and tyrant_lightning_shadow and vision_expose_timer <= 0.0:
		mult = 1.05
	if _cast_windup_left > 0.0:
		mult *= CAST_WINDUP_MOVE_MULT
	return actual_move_speed * mult

func net_predict_blocked() -> bool:
	return stun_timer > 0.0 or knockup_timer > 0.0 or froze_timer > 0.0 \
		or suppress_timer > 0.0 or wukong_cloud_flying

func net_predict_locked() -> float:
	return maxf(0.0, _move_lock_until - Time.get_ticks_msec() * 0.001)

func _physics_process(delta):
	if not _base_state_captured:
		_capture_state_baseline()   # 出生首帧记录状态基线（死亡时用来清零）
	# 元流之子·「流」衰减：不使用流（无获得/消耗）→ 闲置5秒先失1层，此后每秒1层直至用流。
	# 放在最顶、死亡/回城分支之前 → 死亡等一切状态都照常流失；客户端 doll 的 yuanliu_flow 恒为0 → 无副作用。
	if display_name == "元流之子":
		if yuanliu_flow > 0:
			yuanliu_flow_idle -= delta
			if yuanliu_flow_idle <= 0.0:
				yuanliu_flow_idle = 1.0
				yuanliu_flow -= 1
		else:
			yuanliu_flow_idle = 5.0
	if is_dead:
		if casting_skill: _cancel_cast_windup()
		respawn_timer -= delta
		# 死亡期间技能/召唤师冷却照常推进（复活后不再清空）
		_tick_skill_cooldowns(delta)
		if respawn_timer <= 0:
			_respawn()
		return
	if health <= 0 and not is_dead:
		if casting_skill: _cancel_cast_windup()
		if is_reviving:
			revive_timer-=delta
			if revive_timer <=0:
				is_reviving = false
				health = revive_hp
			_tick_skill_cooldowns(delta)   # 太乙/复活甲躺地阶段冷却照常走
		return
	# 技能前摇打断：受控/沉默 → 取消施法（不扣蓝不进 CD，资源只在 _finish_casting 结算）
	if casting_skill and _cast_windup_left > 0.0 \
			and (stun_timer > 0.0 or knockup_timer > 0.0 or froze_timer > 0.0 \
				or suppress_timer > 0.0 or silence_timer > 0.0):
		_cancel_cast_windup()
	
	if manual_target and manual_target.health <= 0 :
		manual_target = null
	if is_recalling:
		recall_timer -= delta
		_recall_vfx_tick(delta, clampf(1.0 - recall_timer / RECALL_DURATION, 0.0, 1.0))
		if recall_timer <= 0:
			# 完成瞬间：光柱爆发 + 波环，再位移回泉水
			var rcol: Color = Color(0.40, 0.80, 1.0) if team == Config.Team.PLAYER else Color(1.0, 0.55, 0.40)
			Vfx.pillar(global_position, rcol, 1.6, 9.0, 0.6)
			Vfx.nova(global_position, rcol, 3.2)
			global_position = Vector3(-62, 0, 62) if team == Config.Team.PLAYER else Vector3(62, 0, -62)   # 回城落点=泉水圆心
			cancel_recall()
	# 传送吟唱（TELEPORT_DURATION 秒，读条与特效同一时长）
	if is_teleporting:
		teleport_progress += delta / TELEPORT_DURATION
		_recall_vfx_tick(delta, clampf(teleport_progress, 0.0, 1.0))
		if teleport_progress >= 1.0:
			var tcol: Color = Color(0.62, 0.48, 1.0) if team == Config.Team.PLAYER else Color(1.0, 0.45, 0.72)
			Vfx.pillar(global_position, tcol, 1.4, 9.0, 0.55)
			Vfx.nova(global_position, tcol, 3.0)
			global_position = teleport_target_pos
			is_teleporting = false
			teleport_progress = 0.0
			_clear_teleport_minion()
			_recall_vfx_stop()
			Vfx.nova(global_position, tcol, 2.6)
			var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if bm:
				bm.remove_teleport_line(self, teleport_target_pos)
	# 大禹传送进度
	if dayu_teleport_channeling:
		dayu_teleport_progress += delta / DAYU_TELEPORT_DURATION
		_recall_vfx_tick(delta, clampf(dayu_teleport_progress, 0.0, 1.0))
		if dayu_teleport_progress >= 1.0:
			global_position = dayu_teleport_target
			dayu_teleport_channeling = false
			_recall_vfx_stop()
			var bm2 = get_tree().get_first_node_in_group("battle_manager") as BattleManager
			if bm2: bm2.remove_teleport_line(self, dayu_teleport_target)
	# 孙悟空：筋斗云飞行
	if wukong_cloud_flying:
		_wukong_cloud_t += delta
		var _cdir := (wukong_cloud_target - global_position)
		WukongCloud.tick(_wukong_cloud_vis, _cdir, wukong_cloud_speed, _wukong_cloud_t, wukong_cloud_phase == 1)
		if wukong_cloud_phase == 0:
			# 腾空阶段：0.5秒升空
			wukong_cloud_timer -= delta
			global_position.y += delta * 15.0
			stun_timer = 0; knockup_timer = 0; remove_cc_speed_buffs()
			if wukong_cloud_timer <= 0:
				wukong_cloud_phase = 1
				collision_layer = 0  # 无视碰撞
		else:
			# 飞行阶段：直线加速飞向水晶
			
			var _cloud_dir = (wukong_cloud_target - global_position).normalized()
			wukong_cloud_speed = min(wukong_cloud_speed + delta * 20.0, 10.0)
			global_position += _cloud_dir * wukong_cloud_speed * delta
			# 到达泉水上空（水平距离判定，保证落在泉水内）；落点对齐泉水圆心
			if Vector2(global_position.x, global_position.z).distance_to(Vector2(wukong_cloud_target.x, wukong_cloud_target.z)) < 1.0:
				global_position = Vector3(wukong_cloud_target.x, global_position.y, wukong_cloud_target.z)
				_end_wukong_cloud()
			# 玩家操控移动后停止
			elif not is_ai:
				var _check_input = Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
				if _check_input.length() > 0.1 or move_target != Vector3.ZERO:
					_end_wukong_cloud()
	# 泉水回复：自家泉水范围内每 0.5s 一跳（每跳 10% 最大生命/法力 = 原 20%/秒；半径判据与 is_in_own_fountain 同源）
	if is_in_own_fountain():
		fountain_tick_timer -= delta
		if fountain_tick_timer <= 0.0:
			fountain_tick_timer = FOUNTAIN_TICK
			_apply_healing(actual_max_health * 0.1)
			mana = minf(mana + actual_mana_max * 0.1, actual_mana_max)
	else:
		fountain_tick_timer = 0.0   # 出泉立即归零：进泉第一跳不等待
	_update_regen_fx(delta)
	
	buff_ring_red.visible = red_buff_active
	buff_ring_blue.visible = blue_buff_active
		# 英雄被动处理
	if hero_passive: hero_passive.process_passive(delta)
	# 技能冷却（含召唤师技能）
	_tick_skill_cooldowns(delta)
	if dayu_teleport_cd > 0: dayu_teleport_cd -= delta
	if attack_timer > 0: attack_timer -= delta * attack_speed_timer
	if aa_target_t > 0.0:
		aa_target_t -= delta
		if aa_target_t <= 0.0:
			aa_target = null
	# Buff计时
	if red_buff_active:
		red_buff_timer -= delta
		if red_buff_timer <= 0: red_buff_active = false; _recalculate_attributes()
	if blue_buff_active:
		blue_buff_timer -= delta
		if blue_buff_timer <= 0: blue_buff_active = false; _recalculate_attributes()
	# 君临/暗影君临计时（到期重算属性，清除移速残留）
	if tyrant_lightning_active:
		tyrant_lightning_timer -= delta
		if tyrant_lightning_timer <= 0: tyrant_lightning_active = false; tyrant_lightning_shadow = false; _recalculate_attributes()
	if tyrant_lightning_cd > 0: tyrant_lightning_cd -= delta
	# 风暴觉醒：护盾到期只扣风暴部分；光环每秒对8单位内敌方造成4%最大生命真伤
	if storm_shield_timer > 0:
		storm_shield_timer -= delta
		if storm_shield_timer <= 0:
			shield_remaining = max(0.0, shield_remaining - storm_shield_amount)
			storm_shield_amount = 0.0
	if storm_aura_active:
		storm_aura_timer -= delta
		if storm_aura_timer <= 0:
			storm_aura_active = false
			if storm_aura_ring:
				storm_aura_ring.queue_free()
				storm_aura_ring = null
		else:
			storm_aura_tick -= delta
			if storm_aura_tick <= 0:
				storm_aura_tick = 1.0
				for entity in get_tree().get_nodes_in_group("entities"):
					if entity == self or entity.health <= 0: continue
					if entity is Turret: continue
					if entity.team == team: continue
					if global_position.distance_to(entity.global_position) <= 8.0:
						entity.take_true_damage(entity.max_health * 0.04, self, true, -54, 1.0)
	if shield_timer > 0:
		shield_timer -= delta
		if shield_timer <= 0: shield_remaining = 0.0
	if grievous_wounds_timer >0:
		grievous_wounds_timer-=delta
		if grievous_wounds_timer <=0:
			grievous_wounds= 1
	# 持续回复效果（血包、技能等）；tick>0 时按固定间隔整块结算（如血包每秒 1 次）
	for src in active_regen.keys():
		var regen_data = active_regen[src]
		regen_data["timer"] -= delta
		var tick: float = float(regen_data.get("tick", 0.0))
		if tick > 0.0:
			regen_data["acc"] = float(regen_data.get("acc", 0.0)) + delta
			while float(regen_data["acc"]) >= tick and regen_data["timer"] > 0.0:
				regen_data["acc"] = float(regen_data["acc"]) - tick
				_apply_healing(regen_data["hp"] * tick)
				mana = min(mana + regen_data["mp"] * tick, actual_mana_max)
		else:
			_apply_healing(regen_data["hp"] * delta)
			mana = min(mana + regen_data["mp"] * delta, actual_mana_max)
		if regen_data["timer"] <= 0:
			active_regen.erase(src)
	# 草丛互见刷新：先于下方隐身视觉逻辑，保证同排敌我英雄互相暴露
	_update_bush_stealth()
	# 隐身/草丛视觉效果
	if visual_mesh:
		var _in_bush_region := not _bush_region_counts.is_empty()
		var target_alpha = 1.0
		# 测试观战：全知视野下隐身/草丛英雄也必须可见
		var _tbm_v = get_tree().get_first_node_in_group("battle_manager")
		var _test_omni: bool = _tbm_v != null and bool(_tbm_v.get("_ai_test_match"))
		if _test_omni:
			visible = true
			target_alpha = 1.0
		# 隐身优先于草丛互见：隐身期间即便与敌方同处一片草丛也保持隐匿
		elif hidden_in_bush or lanling_stealth_active or shadow_dart_active:
			# 己方（玩家=兰陵王时）呈透明造型；敌方完全隐藏
			target_alpha = 0.25 if Config.is_ally(team) else 0.0  # 敌方不可见
			visible = Config.is_ally(team)  # 敌方完全隐藏
		elif _in_bush_region:
			# 同排草丛互见：敌方英雄就在本连片草丛中 → 完全可见可攻击
			visible = true
		else:
			# 出草/非隐身：己方英雄常显；敌方是否可见交给战争迷雾（BattleManager._update_vision 每帧按我方视野刷新）。
			# 此处不要给敌方无条件设 visible=true，否则会每帧覆盖迷雾结果。
			if Config.is_ally(team):
				visible = true
		# 递归设置所有子网格透明度
		_set_node_alpha(visual_mesh, target_alpha, _frozen_tint_active)

	# 攻击暴露视野：受伤后2秒内强制可见 —— 隐身/影袭期间受击不显形
	if vision_expose_timer > 0:
		vision_expose_timer -= delta
		if not (lanling_stealth_active or shadow_dart_active):
			visible = true
			_set_node_alpha(visual_mesh, 1.0, _frozen_tint_active)
	
	# 基础恢复
	regen_timer -= delta
	if regen_timer < 0:
		regen_timer = 5.0
		if health > 0 and health < actual_max_health: _apply_healing(actual_hp_regen)
		if mana < actual_mana_max: mana = min(mana + actual_mana_regen, actual_mana_max)
	if health > last_health + HEAL_POPUP_THRESHOLD:
		var heal_amount = health - last_health
		var ui2 = get_tree().get_first_node_in_group("ui") as UI_Manager
		if ui2: ui2.show_heal_number(global_position + Vector3(0, body_radius * 2, 0), int(heal_amount))
	last_health = health

	# 装备被动处理
	if item_passive: item_passive.process_items(delta)
	# 状态效果
	if stun_timer > 0: stun_timer -= delta
	if bt_timer > 0 or dayu_teleport_channeling: stun_timer = 0; knockup_timer = 0; remove_cc_speed_buffs(); if bt_timer > 0: bt_timer -= delta
	if wd_timer > 0: stun_timer = 0; knockup_timer = 0; remove_cc_speed_buffs(); wd_timer -= delta
	# 李元芳：Q攻击距离加成经 buff 管线(bonus_attack_range)到期自动还原 / W钻地计时(隐藏模型，出土恢复)
	if _lyf_burrow > 0:
		_lyf_burrow -= delta
		var _lyf_hm = get_node_or_null("HeroModel")
		if _lyf_hm:
			_lyf_hm.visible = _lyf_burrow <= 0.0
	# 元流之子：破釜连发窗口（超窗重置阶段）／浮空计时（模型上抬回落）
	if yuanliu_w_window > 0:
		yuanliu_w_window -= delta
		if yuanliu_w_window <= 0:
			yuanliu_w_phase = 0
	if yuanliu_float > 0:
		yuanliu_float -= delta
		var _yl_hm = get_node_or_null("HeroModel")
		if _yl_hm:
			_yl_hm.position.y = minf(yuanliu_float / 0.7, 1.0)
			if yuanliu_float <= 0:
				_yl_hm.position.y = 0.0
	# 传送瞄准模式
	if teleport_targeting:
		if Input.is_action_just_pressed("move_forward") or Input.is_action_just_pressed("move_back") or Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
			teleport_targeting = false  # 移动取消瞄准
	# 玩家 / 联机真人接管：锁定目标超出普攻范围 → 清空锁定（不再主动追击，等待玩家自己走近/换目标）
	# 跳跃强化普攻就绪时普攻距离×2，此时保留更远的锁定以便位移出手
	if (not is_ai or net_taken) and manual_target and is_instance_valid(manual_target):
		if manual_target.health <= 0:
			manual_target = null   # 锁定目标已阵亡：脱锁（锁敌条不保留尸体）
			locked_target = null
		elif global_position.distance_to(manual_target.global_position) \
				> _aa_engage_reach() + float(manual_target.body_radius) + 0.15:
			# 锁敌头像的目标只在「自己的攻击范围」内保持锁定；一旦超出就脱锁，
			# 不再借用自动追击的 3 米余量把锁定拖得很远。
			manual_target = null
	# 锁定目标进入隐身（兰陵王·影袭 / 幽影袖箭）：立即脱锁 —— 隐身期间不可被锁定攻击，仅受AoE波及
	if manual_target and is_instance_valid(manual_target) and manual_target is Hero and (manual_target as Hero).is_invisible_to_enemy():
		manual_target = null
	# 通用普攻按下沿（空放普攻：无目标点按普攻 → 动画+朝向子弹+范围圈）
	if not is_ai or net_taken:
		var _aa_now := Input.is_action_pressed("ui_accept") or TouchController.get_attack_held() or net_attack_hold
		_aa_edge = _aa_now and not _aa_prev_held
		_aa_prev_held = _aa_now
	# 马超：普攻按下沿检测（用于无目标空冲；长按不会连续空冲）
	if not is_ai and display_name == "马超" and health > 0:
		var _atk_now = Input.is_action_pressed("ui_accept") or TouchController.get_attack_held()
		machao_aa_edge = _atk_now and not machao_prev_aa_held
		machao_prev_aa_held = _atk_now
	# 铠：普攻按下沿检测（用于强普无目标空冲；长按不会连续空冲）
	if not is_ai and display_name == "铠" and health > 0:
		var kai_atk_now = Input.is_action_pressed("ui_accept") or TouchController.get_attack_held()
		kai_aa_edge = kai_atk_now and not kai_prev_aa_held
		kai_prev_aa_held = kai_atk_now
	# 不知火舞：普攻按下沿检测（用于强化普攻无目标空放位移；长按不会连续空放）
	if (not is_ai or net_taken) and display_name == "不知火舞" and health > 0:
		var mai_atk_now = Input.is_action_pressed("ui_accept") or TouchController.get_attack_held() or net_attack_hold
		mai_aa_edge = mai_atk_now and not mai_prev_aa_held
		mai_prev_aa_held = mai_atk_now
	# 移动控制
	# 全屏面板（商店/英雄面板）打开时不响应键盘/摇杆，避免按 W/S 选装备时英雄跟着跑
	var ui_block: bool = (not is_ai) and UiManager.blocks_gameplay_input()
	# 远程接管直驱：net_axis/net_joy 非零时视为键盘/摇杆本地输入（见 _net_move_mode）
	var net_driven := net_joy != Vector2.ZERO or net_axis != Vector3.ZERO
	var input_dir = Vector3.ZERO
	var joy_vec := Vector2.ZERO
	if net_driven or (not is_ai and not ui_block):
		if net_driven:
			input_dir = net_axis
			joy_vec = net_joy
		else:
			# get_axis(负轴, 正轴)：ui_up 是正轴（W=前进+1），ui_down 是负轴（S=后退-1）
			input_dir = Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_down", "ui_up"))
			joy_vec = TouchController.get_move_vector()   # 移动端摇杆（屏幕x右+，y上+）
	var move_vec = Vector3.ZERO
	var keyboard_move := false
	var auto_chase_moved := false   # 本帧是否因锁定目标自动追击而移动：移动帧不自动普攻
	if stun_timer <= 0 and knockup_timer <= 0 and froze_timer <= 0 and suppress_timer <= 0 and not wukong_cloud_flying:
		if is_recalling and not is_ai and (joy_vec.length() > 0.1 or input_dir.length() > 0.1 or move_target != Vector3.ZERO): cancel_recall()

		# 移动端摇杆：世界方向移动（屏幕右→+X，屏幕上→-Z），并朝移动方向转向
		# 玩家在红方时镜头绕Y轴转180°：屏幕方向整体取反，保持与蓝方同一手感
		var cam_flip := -1.0 if Config.player_team == Config.Team.ENEMY else 1.0
		if joy_vec.length() > 0.1:
			move_vec = Vector3(joy_vec.x * cam_flip, 0, -joy_vec.y * cam_flip).normalized()
			move_target = Vector3.ZERO
			keyboard_move = false
		elif (not is_ai or net_driven) and _net_move_mode() == TouchController.MOVE_MODE_DIR:
			# 前后左右模式：W/S/A/D 按屏幕方向直接移动（与摇杆方向映射一致：上→-Z，右→+X）
			if input_dir.length() > 0.1:
				move_vec = Vector3(input_dir.x * cam_flip, 0, -input_dir.z * cam_flip).normalized()
				move_target = Vector3.ZERO
				keyboard_move = false
			elif move_target != Vector3.ZERO:
				var dir = move_target - global_position
				if dir.length() < 0.3: move_target = Vector3.ZERO
				else: move_vec = dir.normalized()
		elif (not is_ai or net_driven) and input_dir.length() > 0.1 and joy_vec.length() <= 0.1 \
				and _net_move_mode() == TouchController.MOVE_MODE_TURN:
			# 转向模式（现状）：左右键旋转朝向，前后沿人物朝向移动
			if absf(input_dir.x) > 0.1:
				turn_timer -= delta
				if turn_timer <= 0:
					rotation.y += input_dir.x * deg_to_rad(-15.0) * cam_flip
					turn_timer = 0.05
			keyboard_move = absf(input_dir.z) > 0.1
			if keyboard_move:
				var facing := Vector3(sin(rotation.y), 0, cos(rotation.y))
				move_vec = facing * input_dir.z
			move_target = Vector3.ZERO
		elif move_target != Vector3.ZERO:
			var dir = move_target - global_position
			if dir.length() < 0.3: move_target = Vector3.ZERO
			else: move_vec = dir.normalized()
		elif is_ai and not net_taken and not ai_path_controlled and manual_target and global_position.distance_to(manual_target.global_position) > (_aa_engage_reach() if not manual_target is JungleMonster else 2.0):
			# 纯 AI 才主动追击目标；联机真人接管（net_taken）禁止自动追击——远程玩家自己走位，普攻只打射程内
			var dir: Vector3
			dir = manual_target.global_position - global_position
			move_target = Vector3.ZERO; move_vec = dir.normalized()
		
		# 减速/加速已由重算属性时按净百分比烘焙进 actual_move_speed，此处不再逐帧乘算
		# AI 回城引导中：不能移动/攻击/施法（玩家侧由移动输入取消回城，AI 直接锁住动作）
		if is_ai and is_recalling:
			move_vec = Vector3.ZERO
		# 走A：攻击瞬间锁移动 0.5s，让攻击动画原地播完（玩家与 AI 一致；锁定期仍可继续普攻）
		if Time.get_ticks_msec() * 0.001 < _move_lock_until:
			move_vec = Vector3.ZERO
		if move_vec.length() > 0.1:
			if display_name == "兰陵王" and manual_target and manual_target is Hero:move_vec*=(1.15+0.01*level)
			# AI：有攻击目标时传入攻击距离，路径截断到首次进入射程的点
			# 玩家直接输入（摇杆/按键，move_target已清零）：不做A*寻路，直接沿输入方向移动，
			#   墙体由CollisionSystem的碰撞推离自然阻挡（含贴墙滑行）；右键寻路与AI才走A*避障
			var player_direct := not is_ai and move_target == Vector3.ZERO
			if not player_direct:
				if is_ai and manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
					move_vec = _avoid_walls(move_vec, delta, manual_target.global_position, (_aa_engage_reach() if not manual_target is JungleMonster else 2.0), manual_target.global_position)
				else:
					move_vec = _avoid_walls(move_vec, delta, move_target)
			# 卡墙超时：_avoid_walls返回零向量表示放弃，清除move_target让AI重新决策
			if move_vec.length() < 0.01 and move_target != Vector3.ZERO:
				move_target = Vector3.ZERO
			var move_mult := 1.0
			if tyrant_lightning_active and tyrant_lightning_shadow and vision_expose_timer <= 0:
				move_mult = 1.05   # 暗影君临：脱战移速+5%
			if _cast_windup_left > 0.0:
				move_mult *= CAST_WINDUP_MOVE_MULT   # 技能前摇：移速降低（可移动调整站位，不打断施法）
			# 元流之子·破釜之箭摇杆小位移方向：记录最近实际移动方向（站定时保留上一方向作回退）
			if not is_recalling:
				last_move_dir = move_vec.normalized()
			global_position += move_vec * actual_move_speed * move_mult * delta * 0.01
			# 模型朝向移动方向（按键移动沿自身朝向，无需转向）
			if not keyboard_move:
				rotation.y = atan2(move_vec.x, move_vec.z)
			# 走A：移动中「按住普攻」才出手（没按普攻键只移动）；攻击动作播放期间不覆盖 walk
			_try_walk_attack()
			var _now_s: float = Time.get_ticks_msec() * 0.001
			if _now_s > _aa_anim_until and _now_s > _cast_anim_until:
				_play_anim("walk")
			_clamp_to_map_edge()
		else:
			# 自动追击：锁定目标在「射程 + 追击距离」内但还没进射程 → 站定时自动靠近（移动输入会打断）
			if not is_ai and manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
				var _chase_m := _auto_chase_margin()
				if _chase_m > 0.0:
					var _cdir: Vector3 = manual_target.global_position - global_position
					_cdir.y = 0.0
					var _cdist := _cdir.length()
					if _cdist > _aa_engage_reach() and _cdist <= _aa_engage_reach() + _chase_m and stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and Time.get_ticks_msec() * 0.001 > _move_lock_until:
						global_position += _cdir.normalized() * actual_move_speed * delta * 0.01
						rotation.y = atan2(_cdir.x, _cdir.z)
						auto_chase_moved = true
						_play_anim("walk")
						_clamp_to_map_edge()
			var target = _get_attack_target()
			# 马超拾枪强化普攻 = 突进（替代普攻）：点/按普攻键 → 朝「普攻轮盘方向→目标方向→面朝方向」位移2.5米，
			# 对位移沿途所有敌人都造成强化普攻伤害，每次突进消耗1次强化普攻（stat_timer 扣4秒，拾枪/召回各+4秒、上限8秒）。
			
			if target and target.health > 0:
				var can_act = stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and silence_timer <= 0
				# 推塔/小兵模式开启且当前目标是其类别时：即使不按普攻也自动持续攻击（如站塔下自动点塔）。
				# 只在目标确实是「类别内」时自动开火，避免模式开启时误伤/追着无关目标打。
				var mode_auto := not is_ai and can_act and _is_mode_target(target)
				# 铠强化普攻就绪：普攻键改为突进，此处不再发普通普攻（由下方铠强普突进块处理）
				var kai_enh_gate := not (display_name == "铠" and int(stat) == 1)
				var auto_atk_on: bool = PlayerPrefs.opt_bool("auto_atk", true)
				# 自动普攻只在真正站定时触发；自动追击的移动帧只走路，不边追边打。
				# 按住普攻/手动操作保留走A能力，不受此限制。
				var should_attack = kai_enh_gate and not casting_skill and not (is_ai and is_recalling) \
					and (is_ai or ((Input.is_action_pressed("ui_accept") or TouchController.get_attack_held()) and can_act) \
						or (auto_atk_on and not auto_chase_moved and manual_target and is_instance_valid(manual_target)) \
						or (mode_auto and not auto_chase_moved))
				if is_recalling and not is_ai and should_attack: cancel_recall()
				if should_attack and attack_timer <= 0: _perform_attack(target); attack_timer = 1.0 / attack_speed;
			else:
				# 空放普攻：没有可攻击目标时点按普攻 → 播放普攻动画、沿英雄朝向发射子弹、生成普攻范围圈
				var can_act_e := stun_timer <= 0.0 and knockup_timer <= 0.0 and suppress_timer <= 0.0 and silence_timer <= 0.0
				if (not is_ai or net_taken) and _aa_edge and can_act_e and not casting_skill \
						and not is_recalling and attack_timer <= 0.0 \
						and not UiManager.blocks_gameplay_input() and _empty_attack_allowed():
					if is_recalling and not is_ai: cancel_recall()
					_empty_attack()
					attack_timer = 1.0 / attack_speed
		if display_name == "马超" and stat_timer > 0 and not casting_skill and attack_timer <= 0:
			var target = _get_attack_target()
			var can_act_m = stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and silence_timer <= 0
			var atk_held_m = (Input.is_action_pressed("ui_accept") or TouchController.get_attack_held()) and can_act_m
			if target and target.health > 0:
				# 有可达目标：与普攻一致，AI/按住普攻/锁定目标/自动模式均触发突进
				var mode_auto_m := not is_ai and can_act_m and _is_mode_target(target)
				var want_dash = (is_ai and ai_enhanced_attack_ok) or atk_held_m or (not is_ai and manual_target and is_instance_valid(manual_target)) or mode_auto_m
				if want_dash:
					if is_recalling and not is_ai: cancel_recall()
					_machao_enhanced_dash(target)
					attack_timer = 1.0 / attack_speed
					target = null
			elif not is_ai and can_act_m and atk_held_m and machao_aa_edge:
				# 无可达目标：仅在点按那帧沿轮盘/面朝方向空冲 2.5 米（作为机动位移，长按不会连续空冲）
				if is_recalling: cancel_recall()
				_machao_enhanced_dash(null)
				attack_timer = 1.0 / attack_speed
				target = null
		if display_name == "铠" and int(stat) == 1 and not casting_skill and attack_timer <= 0:
			var target = _get_attack_target()
			var can_act_k = stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and silence_timer <= 0
			var atk_held_k = (Input.is_action_pressed("ui_accept") or TouchController.get_attack_held()) and can_act_k
			if target and target.health > 0:
				# 有可达目标：与普攻一致，AI/按住普攻/锁定目标/自动模式均触发突进
				var mode_auto_k := not is_ai and can_act_k and _is_mode_target(target)
				var want_dash_k = (is_ai and ai_enhanced_attack_ok) or atk_held_k or (not is_ai and manual_target and is_instance_valid(manual_target)) or mode_auto_k
				if want_dash_k:
					if is_recalling and not is_ai: cancel_recall()
					_kai_enhanced_dash(target)
					attack_timer = 1.0 / attack_speed
					target = null
			elif not is_ai and can_act_k and atk_held_k and kai_aa_edge:
				# 无可达目标：仅在点按那帧沿轮盘/面朝方向空冲 2.5 米（作为机动位移，长按不会连续空冲）
				if is_recalling: cancel_recall()
				_kai_enhanced_dash(null)
				attack_timer = 1.0 / attack_speed
				target = null
		# 不知火舞：强化普攻（stat_timer>=5）就绪时无目标也能空放 → 快速向前位移一小段（参照马超强普突进）
		if display_name == "不知火舞" and stat_timer >= 5.0 and not casting_skill and attack_timer <= 0:
			var can_act_mai = stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and silence_timer <= 0
			var atk_held_mai = (Input.is_action_pressed("ui_accept") or TouchController.get_attack_held() or net_attack_hold) and can_act_mai
			var target_mai = _get_attack_target()
			if (not is_ai or net_taken) and can_act_mai and atk_held_mai and mai_aa_edge and not (target_mai and target_mai.health > 0):
				# 无目标：仅在点按那帧沿「普攻轮盘方向→面朝方向」前冲 2.2 米（强化普攻释放，可当机动位移）
				if is_recalling: cancel_recall()
				_mai_enhanced_dash()
				attack_timer = 1.0 / attack_speed
		if not is_ai and not ui_block:
			if Input.is_key_pressed(KEY_CTRL):
				for i in range(3):
					if Input.is_action_just_pressed("skill_%d" % i): upgrade_skill(i)
			_handle_skill_input(delta)
			_handle_desktop_type0_aim()
			_handle_attack_wheel_input()
			_handle_attack_priority_input()
			_update_dash_preview()
		if casting_skill:
			if _cast_windup_left > 0.0:
				_cast_windup_left -= delta
				if _cast_windup_left <= 0.0:
					_cast_windup_left = 0.0
					_finish_casting()   # 前摇结束才真正出手（扣蓝/进 CD/结算都在 _finish_casting）
			else:
				_finish_casting()
	# 更新锁定目标标识
	if manual_target and is_instance_valid(manual_target) and manual_target.health > 0 and not is_ai:
		target_indicator.global_position = manual_target.global_position + Vector3(0, 1.5, 0)
		target_indicator.visible = true
		_update_target_reticle(delta)
	else:
		target_indicator.visible = false
	# 攻击范围圈：按住普攻键即显示（不必等真正出手），松开后按 0.45s 余辉收起
	if not is_ai and attack_range_ring and is_instance_valid(attack_range_ring):
		_aa_ring_show_timer = maxf(0.0, _aa_ring_show_timer - delta)
		var atk_held_ring: bool = health > 0.0 and (Input.is_action_pressed("ui_accept") or TouchController.get_attack_held())
		# 强化普攻就绪时自动常显范围环，不必按住普攻键；出手后由 show_timer 余辉收起
		var enhanced_ready: bool = health > 0.0 and _enhanced_aa_queued()
		var show_ring: bool = _aa_ring_show_timer > 0.0 or atk_held_ring or enhanced_ready
		if attack_range_ring.visible != show_ring:
			attack_range_ring.visible = show_ring
		if _aa_ring_leap != enhanced_ready:
			_update_attack_range_ring()
	if taiyi_protected and taiyi_protect_timer > 0:
		taiyi_protect_timer -= delta
		if taiyi_protect_timer <= 0:
			taiyi_protected = false
	# 王昭君：护盾破裂检测 → 冰霜冲击（范围法伤+冰冷减速）
	if display_name == "王昭君":
		if wangzhaojun_shield_was_active and shield_remaining <= 0:
			wangzhaojun_shield_was_active = false
			var sk_lv = level
			var burst_dmg = int(372 + 26.7 * sk_lv) + actual_ability_power * 0.75
			var slow_pct = int(18.3 + 1.8 * level)
			var slow_dur = 2.0
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent != self and ent.health > 0 and ent.team != team:
					if global_position.distance_to(ent.global_position) <= 4.0:
						ent.take_damage(burst_dmg, self, true, -51, 0)
						ent.apply_move_pct_buff("ms_slow", slow_dur, -slow_pct, true)
						ent.apply_attack_pct_buff("as_slow", slow_dur, -slow_pct, true)
			
			# 冰晶碎片（向外扩散）
			for j in range(10):
				var shard_angle = deg_to_rad(j * 36.0)
				var shard = MeshFactory.create_cylinder(0.05, 0.08, 0.6, Color(0.5, 0.8, 1.0, 0.8))
				shard.position = global_position + Vector3.UP * 1.0
				shard.rotation_degrees = Vector3(randi() % 90, randi() % 90, randi() % 90)
				get_parent().add_child(shard)
				var dx = cos(shard_angle) * (2.0 + randf() * 3.0)
				var dz = sin(shard_angle) * (2.0 + randf() * 3.0)
				var st = create_tween()
				st.set_parallel(true)
				st.tween_property(shard, "position:x", shard.position.x + dx, 0.5)
				st.tween_property(shard, "position:z", shard.position.z + dz, 0.5)
				st.tween_property(shard, "position:y", shard.position.y + 1.5 + randf() * 2.0, 0.5)
				st.tween_property(shard.material_override, "albedo_color:a", 0.0, 0.5)
				st.tween_callback(shard.queue_free).set_delay(0.5)
		if shield_remaining > 0:
			wangzhaojun_shield_was_active = true
	# 孙尚香：Q翻滚强普就绪后倒计时5秒，超时未出手则过期消失（stat_timer 由 Q 置位时写入 5.0）
	if display_name == "孙尚香":
		if stat >= 1 and stat_timer > 0.0:
			stat_timer -= delta
			if stat_timer <= 0.0:
				stat = 0
				stat_timer = 0.0
		elif stat < 1:
			stat_timer = 0.0
	# 马超：拾枪检测
	if display_name == "马超" and objs.size() > 0:
		const MACHAO_PICKUP_RANGE = 2.0
		for i in range(objs.size() - 1, -1, -1):
			var spear = objs[i]
			if not is_instance_valid(spear):
				objs.remove_at(i)
				continue
			var to_spear = spear.global_position - global_position
			to_spear.y = 0
			var dist = to_spear.length()
			if dist <= MACHAO_PICKUP_RANGE:
				# 拾取枪
				objs.remove_at(i)
				spear.queue_free()
				mana += 1
				stat_timer = min(stat_timer+4.0, 8.0)
				# 马超拾枪：直接按数值 +5 移速（5秒）——固定数值型移速 buff
				_apply_healing((7*level+94+0.02*bonus_health)*0.5)
				apply_flat_move_buff("machao_speed", 5.0, int(18.8+1.4*level))
	
	# 马可波罗 二技能被动：500范围内有敌方英雄→+20%伤害+移速（常驻光环）
	if display_name == "马可波罗" and skill_levels.size() > 1 and skill_levels[1] > 0:
		var near_enemy = _get_nearest_enemy_in_range(5.0)
		if near_enemy and not _makeboluo_w2_active:
			_makeboluo_w2_active = true
			_apply_ak_buff(0, 0.2, 999.0, false)
			if active_buffs.size() > 0:
				active_buffs.back()["_tag"] = "makeboluo_w2_dmg"
			# 移速加成单独占一个常驻计时条目（独立 tag），不挤占/被其它加速覆盖
			apply_move_pct_buff("makeboluo_w2_spd", 999.0, 0.12 + skill_levels[1] * 0.03)
		elif not near_enemy and _makeboluo_w2_active:
			_makeboluo_w2_active = false
			remove_speed_buff("makeboluo_w2_spd")
			remove_speed_buff("makeboluo_w2_dmg")

	# 英睿: 变身LabiB计时 + 被动冰爽层数计时
	if display_name == "英睿":
		if yingrui_transformed:
			yingrui_transform_timer -= delta
			if yingrui_transform_timer <= 0:
				yingrui_transformed = false
				scale = Vector3.ONE
		if yingrui_stacks > 0:
			yingrui_stack_timer -= delta
			if yingrui_stack_timer <= 0:
				yingrui_stacks = 0
				_recalculate_attributes()
		# W三段：窗口过期后重置段数（下次W重新从第一段开始）
		if yingrui_w_stage > 0 and skill_window_timers.size() > 1 and skill_window_timers[1] <= 0:
			yingrui_w_stage = 0
		# 视觉：人形 ←→ LabiB 毛绒形态切换（只换模型，不改碰撞/数值）
		if yingrui_transformed != _yingrui_form_on:
			_yingrui_apply_form(yingrui_transformed)

# 英睿大招形态切换：隐藏人形底座、显示等身 LabiB（scale 在技能里另放大，这里只管可见性）
func _yingrui_apply_form(on: bool) -> void:
	_yingrui_form_on = on
	if yingrui_body and is_instance_valid(yingrui_body):
		yingrui_body.visible = not on
	if yingrui_plush and is_instance_valid(yingrui_plush):
		yingrui_plush.visible = on

# 跳跃式强化普攻就绪：孙悟空被动 / 亚瑟Q 强化普攻（攻击距离×2 并位移至目标身边攻击）
func _leap_aa_ready() -> bool:
	if display_name == "孙悟空":
		return sunwukong_enhanced_aa
	if display_name == "亚瑟":
		return arthur_q_active
	return false

# 当前普攻可锁定的最大距离（世界单位）：
# 跳跃强化普攻（亚瑟Q/孙悟空被动）就绪时 = 普攻距离×2；
# 孙尚香强化普攻就绪 +20%；马超持枪强化普攻 +40%。
func _aa_engage_reach() -> float:
	# 不做近战贴身压缩：攻击距离由武器长度体现（武器按 attack_range 加长，见 HeroWeapons.attach）
	var reach := attack_range * 0.01
	if _leap_aa_ready():
		reach *= 1.75
	elif display_name == "孙尚香" and int(stat) == 1:
		reach *= 1.2
	elif display_name == "马超" and stat_timer > 0:
		reach *= 1.4
	return reach


# 是否近战普攻（按射程阈值判定：≤475 = 武器近战，>475 = 远程弹道）
func is_melee_aa() -> bool:
	return attack_range <= MELEE_AA_RANGE_MAX

# 是否存在「下一次普攻强化」的就绪状态（用于普攻键/攻击范围圈的金色提示）。
# 注意：位移跳跃类（亚瑟Q、孙悟空）除变色外普攻距离还要×2，见 _aa_engage_reach/_leap_aa_ready。
func _enhanced_aa_queued() -> bool:
	if display_name == "亚瑟" and arthur_q_active:
		return true
	if display_name == "孙悟空" and sunwukong_enhanced_aa:
		return true
	if display_name == "刘禅" and liushan_q_active:
		return true
	if display_name == "铠" and int(stat) == 1:
		return true
	if display_name == "孙尚香" and int(stat) == 1:
		return true
	if display_name == "不知火舞" and stat_timer >= 5.0:
		return true
	if display_name == "大禹" and dayu_w_enhanced and not dayu_w_used_enhanced:
		return true
	if display_name == "后羿" and houyi_q_active:
		return true
	if display_name == "夏侯惇" and xiahou_enhanced_attacks > 0:
		return true
	if display_name == "马超" and stat_timer > 0:
		return true
	# 鲁班扫射 / 王昭君冰锥 / 狄仁杰强化令牌：下一次普攻会替换为强化形态
	if display_name == "鲁班七号" and (luban_skill_enhanced or luban_passive_stacks >= 5):
		return true
	if display_name == "王昭君" and wangzhaojun_aa_counter >= 2:
		return true
	if display_name == "狄仁杰" and int(stat2) >= 3:
		return true
	return false


## AI 专用：强化普攻是否可用于位移
## 马超/铠/不知火舞可空放位移；亚瑟Q/孙悟空被动是跳跃强化普攻，需要借助敌方目标
func ai_enhanced_aa_ready() -> bool:
	if health <= 0.0:
		return false
	match display_name:
		"马超":
			return stat_timer > 0.0
		"铠":
			return int(stat) == 1
		"不知火舞":
			return stat_timer >= 5.0
		"亚瑟":
			return arthur_q_active
		"孙悟空":
			return sunwukong_enhanced_aa
	return false


## AI 专用：用强化普攻位移。dir 为期望方向；jump_target 仅亚瑟Q/孙悟空需要（跳跃目标）
func ai_enhanced_aa_dash(dir: Vector3, jump_target: GameEntity = null) -> bool:
	if not ai_enhanced_aa_ready():
		return false
	if casting_skill or attack_timer > 0.0:
		return false
	if stun_timer > 0.0 or knockup_timer > 0.0 or suppress_timer > 0.0 or silence_timer > 0.0:
		return false
	var d := dir
	d.y = 0.0
	if d.length() < 0.05:
		return false
	d = d.normalized()
	match display_name:
		"马超":
			_machao_enhanced_dash(null, d)
			attack_timer = 1.0 / attack_speed
			return true
		"铠":
			_kai_enhanced_dash(null, d)
			attack_timer = 1.0 / attack_speed
			return true
		"不知火舞":
			_mai_enhanced_dash(d)
			attack_timer = 1.0 / attack_speed
			return true
		"亚瑟", "孙悟空":
			if jump_target == null or not is_instance_valid(jump_target) or jump_target.health <= 0.0:
				return false
			if jump_target.team == team:
				return false
			if global_position.distance_to(jump_target.global_position) > _aa_engage_reach():
				return false
			manual_target = jump_target
			_perform_attack(jump_target)
			attack_timer = 1.0 / attack_speed
			return true
	return false


## AI 专用：这次强化普攻位移的距离（规划/判定用）
func ai_enhanced_aa_dash_len() -> float:
	match display_name:
		"马超", "铠":
			return 2.5
		"不知火舞":
			return 2.2
		"亚瑟", "孙悟空":
			return maxf(1.0, _aa_engage_reach())
	return 0.0


# 位移至目标身旁：沿自身→目标方向落下，站距取（双方半径和+余量）且不超出普攻距离，
# 使落点既紧贴目标、又能接着普攻（避免原「瞬移到目标中心」导致的身体重叠）。
func _dash_beside_target(target: GameEntity) -> void:
	if not is_instance_valid(target):
		return
	var offset := global_position - target.global_position
	offset.y = 0.0
	if offset.length() < 0.001:
		offset = Vector3.FORWARD
	var dir := offset.normalized()
	var standoff := minf(target.body_radius + body_radius + 0.15, attack_range * 0.01 - 0.25)
	standoff = maxf(standoff, 0.3)
	var cur_dist: float = global_position.distance_to(target.global_position)
	if cur_dist <= standoff + 0.05:
		return   # 已在攻击间距内，无需位移
	if cur_dist > attack_range * 0.02 + 0.1:
		return   # 超出 2×普攻距离上限，不做跨图位移
	# 跳跃类强化普攻：几帧内跃到目标身旁（不再是瞬移），空中播跳跃动作
	dash_move_to(Vector3(target.global_position.x + dir.x * standoff,
		global_position.y, target.global_position.z + dir.z * standoff), 0.13, "jump")

# 普攻键实时预览：若下一次普攻是数值/跳跃类强化普攻，返回强化后的未减甲伤害与金色高亮标记。
# 口径与普攻键当前显示的「原始攻击力」一致；孙悟空强化普攻必定暴击故乘暴击系数。
func _attack_button_preview() -> Dictionary:
	var dmg := actual_attack_damage
	var enhanced := false
	var crit_mult := 1.0
	if display_name == "亚瑟" and arthur_q_active:
		enhanced = true
		dmg += 260.0 + skill_levels[0] * 65.0 + bonus_attack
	elif display_name == "孙悟空" and sunwukong_enhanced_aa:
		enhanced = true
		dmg = 475.0 + actual_attack_damage
		crit_mult = actual_crit_damage
	elif display_name == "刘禅" and liushan_q_active:
		enhanced = true
		dmg += 300.0 + 50.0 * skill_levels[0] + 1.22 * actual_attack_damage
	elif display_name == "铠" and int(stat) == 1:
		enhanced = true
		dmg += 100.0 + 25.0 * skill_levels[1] + 0.32 * bonus_attack
	elif display_name == "孙尚香" and int(stat) == 1:
		enhanced = true
		dmg = 250.0 + 20.0 * skill_levels[0] + actual_attack_damage
	elif display_name == "不知火舞" and stat_timer >= 5.0:
		enhanced = true
		dmg += 100.0 + actual_ability_power
	elif display_name == "大禹" and dayu_w_enhanced and not dayu_w_used_enhanced:
		enhanced = true
		dmg += 160.0 + (skill_levels[1] - 1.0) * 30.0 + actual_attack_damage
	elif display_name == "后羿" and houyi_q_active:
		enhanced = true
		dmg = 110.0 + (skill_levels[0] - 1.0) * 22.0 + actual_attack_damage * 0.75
	elif display_name == "夏侯惇" and xiahou_enhanced_attacks > 0:
		enhanced = true
		dmg += 150.0 + (skill_levels[1] - 1.0) * 30.0 + bonus_attack * 0.45
	elif display_name == "马超" and stat_timer > 0:
		enhanced = true
		dmg += 65.0 + 0.22 * bonus_attack + 5.0 * level
	return {"dmg": int(round(dmg * crit_mult)), "enhanced": enhanced}

# 普攻键装备被动小字行：每件已装备的普攻触发被动出一行（小图标+装备短名+实时效果数值）。
# 只读查询：镜像 _perform_attack / OnHitProcessor 的命中公式现算数值，不改变任何状态/冷却/层数/锁定目标。
# 由 TouchController 每帧拉取（_push_attack_stats），AttackWheelButton 内容变化时才重绘。
func aa_item_passive_rows() -> Array:
	var rows: Array = []
	var PHYS_COL := Color(1.0, 0.6, 0.3)        # 物理伤害
	var MAGIC_COL := Color(0.82, 0.55, 1.0)     # 法术伤害
	var HEAL_COL := Color(0.45, 1.0, 0.62)      # 自身回血
	var AS_COL := Color(0.55, 0.9, 1.0)         # 攻速增益
	var FIRE_COL := Color(1.0, 0.62, 0.28)      # 狩猎灼烧
	# 当前最可能的普攻目标（只读：手动锁定优先，其次最近一次攻击目标）
	var tgt: GameEntity = null
	if manual_target and is_instance_valid(manual_target) and manual_target.health > 0 and manual_target.team != team:
		tgt = manual_target
	elif current_target and is_instance_valid(current_target) and current_target.health > 0 and current_target.team != team:
		tgt = current_target
	for jid in equipment_slots:
		var it = ItemDatabase.get_item(jid)
		if it.is_empty():
			continue
		var nm := String(it.get("name", jid))
		var r := {}
		var armed := true
		var k := "phys"
		var col := PHYS_COL
		var txt := ""
		match String(jid):
			"world_end":
				var flat = 80.0 + level * 5.3
				if tgt is Hero:
					txt = "+%d(7%%血)" % int(round(flat + (tgt as Hero).bonus_health * 0.07))
				else:
					txt = "+%d物·英雄另+7%%血" % int(round(flat))
			"lightning_knife":
				k = "magic"; col = MAGIC_COL
				var per = 40.0 + level * 2.6
				var arc = 160.0 + level * 16.0
				if lightning_count >= 2:
					txt = "+%d法·下击电弧+%d" % [int(round(per)), int(round(arc))]
				else:
					txt = "+%d法·每3击电弧+%d" % [int(round(per)), int(round(arc))]
			"gold_saint_sword":
				if gold_saint_sword_stacks >= 2:
					txt = "+%d物·满层法伤+%d" % [60, int(round(actual_ability_power * 0.3))]
				else:
					txt = "+%d物·叠攻速%d/2" % [60, gold_saint_sword_stacks]
			"sunspire_bow", "dawn":
				txt = "+%d物伤" % int(round(50.0 if attack_range > 500 else 25.0))
			"swift_day":
				armed = sunspire_active
				txt = "溅射30%伤害" if sunspire_active else "开启后溅射30%"
			"shadow_blade":
				k = "as"; col = AS_COL
				txt = "命中攻速+10%/暴击+20%·移速5%"
			"swift_boots":
				k = "heal"; col = HEAL_COL
				var bh = 30.0 + level * 0.6 if attack_range > 500 else 20.0 + level * 1.3
				txt = "命中回血+%d" % int(round(bh))
			"chase_wind":
				k = "as"; col = AS_COL
				txt = "命中叠攻速·%d/5" % chase_wind_stacks
			"frost_breath":
				k = "magic"; col = MAGIC_COL
				armed = frost_breath_cd <= 0
				var fb = 75.0 + level * 5.0 + actual_ability_power * 0.15
				txt = "减速+%d法伤" % int(round(fb))
			"frost_assault":
				armed = frost_assault_cd <= 0
				var fa = 135.0 + level * 9.0 + bonus_attack * 0.45
				txt = "减速+%d物伤" % int(round(fa))
			"dragon_shield":
				armed = dragon_shield_cd <= 0
				if tgt is JungleMonster:
					txt = "野怪+%d(7%%血)" % int(round(actual_max_health * 0.07))
				elif tgt is Hero or tgt is Turret:
					txt = "英雄/塔+%d(3.5%%血)" % int(round(actual_max_health * 0.035))
				else:
					txt = "对野+7%血/英雄塔3.5%"
			"blood_rage":
				var br = actual_max_health * 0.015
				if health < actual_max_health * 0.5:
					br *= 1.25 + level * 0.016
					txt = "+%d(1.5%%血·低血增幅)" % int(round(br))
				else:
					txt = "+%d(1.5%%血)" % int(round(br))
			"ice_fist":
				armed = ice_fist_buff and ice_fist_cd <= 0
				var inf = 140.0 + level * 9.3 + actual_attack_damage * 0.4
				txt = "技能后普攻+%d物·减速" % int(round(inf))
			"sage_power":
				armed = sage_power_buff and sage_power_cd <= 0
				txt = "技能后普攻+%d物(80%%AD)" % int(round(actual_attack_damage * 0.8))
			"witch_staff":
				k = "magic"; col = MAGIC_COL
				armed = witch_staff_buff and witch_staff_cd <= 0
				var ws = 180.0 + level * 12.0 + actual_ability_power * 0.4
				txt = "技能后普攻+%d法伤" % int(round(ws))
			"hunter_knife", "guerrilla_blade", "chase_blade", "patrol_axe", "rune_blade", "greed_blade", "giant_grasp":
				k = "hunt"; col = FIRE_COL
				txt = "普攻附加燃烧Dot"
		if not txt.is_empty():
			r["k"] = k
			r["name"] = nm
			r["txt"] = txt
			r["col"] = col
			r["armed"] = armed
			rows.append(r)
	return rows

func _get_attack_target(range: float = -1.0, respect_mode: bool = true) -> GameEntity:
	if range < 0.0:
		range = _aa_engage_reach()
	if manual_target and is_instance_valid(manual_target):
		# 目标进入隐身（兰陵王·影袭 / 幽影袖箭）或不可选中（李白W剑阵/金身、李元芳W钻地）：立即脱锁
		if manual_target is Hero and ((manual_target as Hero).is_invisible_to_enemy() or (manual_target as Hero).is_untargetable_by_enemies()):
			manual_target = null
		elif manual_target.health > 0:
			var dist = global_position.distance_to(manual_target.global_position)
			# 锁敌头像用的是「距离 - 目标体积」判定，这里同步把目标体积计入射程，
			# 否则头像边缘锁定的敌人会出现“锁了但普攻不选中”的情况。
			var body_pad: float = float(manual_target.body_radius) + 0.15 if manual_target is GameEntity else 0.0
			if dist <= range + body_pad:
				return manual_target
	# 玩家：自动选敌 —— 范围内优先英雄（剩余血量最低优先），其次非英雄（小兵/塔/野怪，剩余血量最低优先）
	# 远程接管英雄：net_attack_hold（按住普攻）或已启用具体优先级模式（推塔/小兵，站定自动持续攻击）时生效。
	if not is_ai:
		# 推塔/小兵优先级模式：范围内存在对应类别目标 → 直接返回该类最低血目标；否则回退普通选敌。
		# respect_mode=false（目标型技能智能施法兜底）时不应用模式，避免技能被拉到塔/小兵上。
		if respect_mode:
			var pri := TouchController.get_attack_priority()
			if pri != TouchController.ATTACK_PRIORITY_AUTO:
				var mode_target := _pick_priority_target(pri, range)
				if mode_target:
					return mode_target
		var best_hero: GameEntity = null
		var best_hero_s := 999999.0
		var best_other: GameEntity = null
		var best_other_s := 999999.0
		var best_pot: GameEntity = null
		var best_pot_s := 999999.0
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
				continue
			if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster or ent is Tripod):
				continue  # 排除墙体/草丛/治疗包等非战斗实体
			if global_position.distance_to(ent.global_position) > range:
				continue
			var sc: float = _target_prio_score(ent)
			if ent is Hero:
				if (ent as Hero).is_invisible_to_enemy() or (ent as Hero).is_untargetable_by_enemies():
					continue  # 隐身中的敌方英雄不可被自动索敌（AoE 仍可波及）
				if sc < best_hero_s:
					best_hero_s = sc
					best_hero = ent
			elif ent is Tripod:
				# 大禹治疗鼎优先级最低：不抢英雄/兵线/塔的自动索敌
				if sc < best_pot_s:
					best_pot_s = sc
					best_pot = ent
			else:
				if sc < best_other_s:
					best_other_s = sc
					best_other = ent
		if best_hero:
			return best_hero
		if best_other:
			return best_other
		return best_pot
	if net_attack_hold or (net_attack_priority >= 0 and net_attack_priority != TouchController.ATTACK_PRIORITY_AUTO):
		# 推塔/小兵模式：与上面玩家分支同规则（该类目标最低血优先）；无该类目标时若仅在按住普攻
		# 才回退通用选敌（站定自动点塔/点兵不因周围有英雄而改打英雄）
		if net_attack_priority >= 0 and net_attack_priority != TouchController.ATTACK_PRIORITY_AUTO:
			var mode_target := _pick_priority_target(net_attack_priority, range)
			if mode_target:
				return mode_target
		if net_attack_hold:
			# 按住普攻的通用回退：与玩家按住普攻一致 —— 英雄优先（剩余血量最低），其次非英雄
			var best_hero: GameEntity = null
			var best_hero_hp := 999999.0
			var best_other: GameEntity = null
			var best_other_hp := 999999.0
			var best_pot: GameEntity = null
			var best_pot_hp := 999999.0
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
					continue
				if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster or ent is Tripod):
					continue
				if global_position.distance_to(ent.global_position) > range:
					continue
				if ent is Hero:
					if (ent as Hero).is_invisible_to_enemy() or (ent as Hero).is_untargetable_by_enemies():
						continue
					if ent.health < best_hero_hp:
						best_hero_hp = ent.health
						best_hero = ent
				elif ent is Tripod:
					if ent.health < best_pot_hp:
						best_pot_hp = ent.health
						best_pot = ent
				else:
					if ent.health < best_other_hp:
						best_other_hp = ent.health
						best_other = ent
			if best_hero:
				return best_hero
			if best_other:
				return best_other
			return best_pot
	return null

# 目标优先级模式的同类选敌：范围内选「类别符合」的敌方单位中剩余血量最低者
# （TOWER=防御塔；MINION=小兵/野怪）。无对应类别目标返回 null。
# 自动索敌排序分：0=百分比血量最低 1=绝对血量最低 2=距离最近
func _target_prio_score(ent: GameEntity) -> float:
	var mode: int = PlayerPrefs.opt_int("target_prio", 0)
	if mode == 2:
		return global_position.distance_to(ent.global_position)
	if mode == 0:
		var mx: float = float(ent.get("actual_max_health")) if ent.get("actual_max_health") != null else ent.max_health
		return ent.health / maxf(mx, 1.0)
	return ent.health

# 自动追击距离余量（米）：0=标准+3 1=近+1 2=关
func _auto_chase_margin() -> float:
	var m: int = PlayerPrefs.opt_int("auto_chase", 0)
	if m == 1:
		return 1.0
	if m == 2:
		return 0.0
	return 3.0

# 位移落点（考虑墙体）：沿 dir 前进 dist，撞墙则停在墙前 0.4m
func clamp_dash_landing(dir: Vector3, dist: float) -> Vector3:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return global_position
	var from := global_position + flat.normalized() * 0.4
	var to := from + flat.normalized() * dist
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.7, to + Vector3.UP * 0.7)
	q.collision_mask = 1
	q.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(q)
	var out := to
	if not hit.is_empty() and hit.get("collider") is Wall:
		var p: Vector3 = hit["position"] + (hit["normal"] as Vector3) * 0.45
		out = Vector3(p.x, global_position.y, p.z)
	return out

# 位移预览环：拖动闪现/位移技能时在落点画圈（已按墙体修正）；关=不显示
func _update_dash_preview() -> void:
	if is_ai or health <= 0 or not PlayerPrefs.opt_bool("move_preview", true):
		if _dash_preview != null and is_instance_valid(_dash_preview):
			_dash_preview.visible = false
		return
	var dir := Vector3.ZERO
	var dist := 0.0
	var sum_drag := TouchController.get_summoner_drag()
	if sum_drag.length() > 20.0 and summoner_skill != null and str(summoner_skill.skill_name) == "闪现":
		dir = _resolve_flash_dir(sum_drag)
		dist = 5.0
	else:
		for i in range(mini(skills.size(), 3)):
			if TouchController.get_skill_held(i) and skills[i] != null and int(skills[i].type) == 4:
				var drag := TouchController.get_skill_drag(i)
				if drag.length() > 20.0:
					# 与真实施法同一套换算：屏幕拖拽 → 反投影到地面（红方镜头转了 180° 也不会反）
					var cam2 := get_viewport().get_camera_3d()
					if cam2 != null:
						var sc := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
						var wp := _screen_ray_world(sc)
						var dv := wp - global_position
						dv.y = 0.0
						if dv.length() > 0.05:
							dir = dv.normalized()
					dist = clampf(float(skills[i].cast_range), 2.0, 12.0)
					break
	if dist <= 0.0:
		if _dash_preview != null and is_instance_valid(_dash_preview):
			_dash_preview.visible = false
		return
	var endp := clamp_dash_landing(dir, dist)
	if _dash_preview == null or not is_instance_valid(_dash_preview):
		_dash_preview = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42
		tm.outer_radius = 0.55
		_dash_preview.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.55, 0.85, 1.0, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dash_preview.material_override = mat
		var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		if host != null:
			host.add_child(_dash_preview)
	_dash_preview.global_position = endp + Vector3.UP * 0.12
	_dash_preview.visible = true

func _pick_priority_target(pri: int, range: float) -> GameEntity:
	var best: GameEntity = null
	var best_hp := 999999.0
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		var ok := false
		if pri == TouchController.ATTACK_PRIORITY_TOWER:
			ok = ent is Turret
		elif pri == TouchController.ATTACK_PRIORITY_MINION:
			ok = ent is Minion or ent is JungleMonster
		if not ok:
			continue
		if global_position.distance_to(ent.global_position) > range:
			continue
		if ent.health < best_hp:
			best_hp = ent.health
			best = ent
	return best

# 目标是否属于当前激活的优先级模式的类别（推塔=防御塔 / 小兵=小兵·野怪）；否则返回 false
func _is_mode_target(t: GameEntity) -> bool:
	if t == null:
		return false
	var pri := TouchController.get_attack_priority()
	if pri == TouchController.ATTACK_PRIORITY_TOWER:
		return t is Turret
	if pri == TouchController.ATTACK_PRIORITY_MINION:
		return t is Minion or t is JungleMonster
	return false

# 目标型技能：在瞄准点附近（且处于施法范围内）选最近的敌方单位 —— 王者荣耀式拖拽选目标
# max_aim_dist>0 时只收「离瞄准点≤该半径」的候选（桌面悬停吸附用；拖拽轮盘/触屏=不限半径）
func _pick_skill_target(aim_pos: Vector3, cast_range: float, max_aim_dist: float = -1.0) -> GameEntity:
	var best: GameEntity = null
	var best_dist := 999999.0
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster):
			continue
		if global_position.distance_to(ent.global_position) > cast_range:
			continue
		if ent is Hero and (ent as Hero).is_invisible_to_enemy():
			continue  # 隐身单位不可被目标型技能/轮盘选中（AoE 仍可命中）
		var d: float = ent.global_position.distance_to(aim_pos)
		if max_aim_dist > 0.0 and d > max_aim_dist:
			continue
		if d < best_dist:
			best_dist = d
			best = ent
	return best

# 目标型技能可锁实体门禁：防御塔仅李元芳 1 技能允许锁定（维持 HoK 其它目标技不可点塔）
func _skill_target_allowed(t: GameEntity, slot: int = -1) -> bool:
	if not (t is Turret):
		return true
	if slot < 0:
		slot = pending_skill_index
	return display_name == "李元芳" and slot == 0

## 取本英雄的 AI 调试快照（F3 覆盖层 / 录像共用；非 AI 或未挂 HeroAI 返回空）
func ai_debug_snapshot() -> Dictionary:
	for c in get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("HeroAI.gd"):
			if c.has_method("debug_snapshot"):
				return c.call("debug_snapshot")
	return {}


## 空放普攻是否允许（强化普攻有专属空放位移的英雄优先走各自的空放逻辑，避免同帧双重触发）
func _empty_attack_allowed() -> bool:
	match display_name:
		"马超":
			return stat_timer <= 0.0
		"铠":
			return int(stat) != 1
		"不知火舞":
			return stat_timer < 5.0
	return true


## 空放普攻：播放普攻动画 → 沿英雄朝向发射子弹 → 生成普攻范围圈（不要求锁定目标）
func _empty_attack() -> void:
	if health <= 0.0:
		return
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var now_s := Time.get_ticks_msec() * 0.001
	_move_lock_until = now_s + 0.5
	_aa_anim_until = now_s + 0.5
	HeroWeapons.play(visual_mesh, "attack")
	_attack_anim()
	SfxManager.try_attack_sfx(display_name, attack_range)
	flash_attack_range_ring()
	# 录像：空放普攻也记录，回放能播攻击动画
	var _replay_rec = get_tree().get_first_node_in_group("replay_recorder")
	if _replay_rec != null:
		_replay_rec.call("note_attack", display_name, global_position + Vector3.UP * 1.2,
			global_position + fwd * 4.0, Vfx.color_for_hero(display_name))
	var _tbm = get_tree().get_first_node_in_group("battle_manager")
	if _tbm != null and _tbm.has_method("test_hero_action"):
		_tbm.call("test_hero_action", self, "attack", 0)
	if not is_melee_aa():
		# 远程：沿朝向直线弹道（无锁定目标）
		var bullet := Bullet.new()
		bullet.speed = 40.0
		bullet.damage = actual_attack_damage
		bullet.team = team
		bullet.source = self
		bullet.is_magic = false
		bullet.skill_id = 0
		bullet.pen_percent = actual_phys_pen_percent
		bullet.is_crit = false
		bullet.global_position = global_position + Vector3(0.0, 1.2, 0.0)
		bullet.set_linear(fwd, maxf(attack_range * 0.01, 6.0))
		get_parent().add_child(bullet)
	else:
		# 近战：朝面向空挥一刀（刀光+接触火花），不发子弹
		var tip := global_position + fwd * maxf(attack_range * 0.01 * 0.8, 1.0) + Vector3.UP * 0.9
		Vfx.weapon_hit(global_position + Vector3.UP * 0.9 + fwd * 0.6, tip,
			Vfx.color_for_hero(display_name), Color(1.0, 0.96, 0.86), 0.9)


func _perform_attack(target: GameEntity):
	# 走A：每次普攻瞬间播放攻击动画并锁移动 0.5s（玩家与 AI 一致），避免边打边滑
	var now_s := Time.get_ticks_msec() * 0.001
	_move_lock_until = now_s + 0.5
	_aa_anim_until = now_s + 0.5
	HeroWeapons.play(visual_mesh, "attack")   # 武器普攻动作
	var _replay_rec2 = get_tree().get_first_node_in_group("replay_recorder")
	if _replay_rec2 != null:
		var _aim: Vector3 = target.global_position if target != null and is_instance_valid(target) else global_position + Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * 3.0
		var _tk := ""
		var _tr := 0.85
		var _th := 1.15
		if target is Minion:
			_tk = "minion"; _tr = float(target.body_radius) + 0.3; _th = 0.75
		elif target is Turret:
			_tk = "turret"; _tr = 1.5; _th = 1.6
		elif target is Hero:
			_tk = "hero"
		_replay_rec2.call("note_attack", display_name, _muzzle_pos(), _aim, Vfx.color_for_hero(display_name),
			is_melee_aa(), _tk, _tr, _th)
	var _tbm2 = get_tree().get_first_node_in_group("battle_manager")
	if _tbm2 != null and _tbm2.has_method("test_hero_action"):
		_tbm2.call("test_hero_action", self, "attack", 0)
	manual_target = target
	# 补刀提示：记录本次普攻目标并给一个略长于攻击间隔的有效期
	aa_target = target
	aa_target_t = clampf(1.6 / maxf(attack_speed, 0.1), 0.5, 1.8)
	# 本地玩家英雄普攻出音（非本人内部直接忽略；按英雄元素/远近程叠加专属音色）
	SfxManager.try_attack_sfx(display_name, attack_range)
	# 普攻出手：攻击范围圈亮一下（仅玩家本人；AI 不显示避免满屏圆环）
	flash_attack_range_ring()
	# 攻击退出隐身
	if shadow_dart_active:
		shadow_dart_active = false; collision_layer = 1
	if lanling_stealth_active:
		lanling_stealth_active = false; collision_layer = 1; lanling_stealth_timer = 0.0
		lanling_as_buff_timer = 5.0; _recalculate_attributes()  # 解隐攻速buff：立即烘焙进 attack_speed_timer
	# 幽影袖箭：普攻退出隐身
	if shadow_dart_active:
		shadow_dart_active = false
		visible = true
		collision_layer = 1
	# 跳跃类强化普攻出手前先位移至目标身旁：孙悟空被动/亚瑟Q（攻击距离已×2）及铠强化普攻
	if _leap_aa_ready() or (display_name == "铠" and int(stat) == 1):
		_dash_beside_target(target)
		if display_name == "铠":
			target.knockup_timer = 1.0
			_cc_burst(target)
	# 英睿被动：每3次普攻后下次普攻必为肘击（同W效果，肘击替代本次普攻）
	if display_name == "英睿":
		if yingrui_elbow_ready:
			yingrui_elbow_ready = false
			var elbow_pos = target.global_position if target and is_instance_valid(target) else global_position + Vector3.FORWARD * 2.0
			yingrui_elbow(elbow_pos)
			return
		else:
			yingrui_aa_count += 1
			if yingrui_aa_count >= 3:
				yingrui_aa_count = 0
				yingrui_elbow_ready = true
	# 计算伤害
	current_target = target
	var dmg = actual_attack_damage
	var wukong_leap := false   # 本次普攻是否为孙悟空被动强化普攻（必定暴击）
	if display_name == "孙悟空" and sunwukong_enhanced_aa:
			sunwukong_enhanced_aa = false
			dmg = 475 + actual_attack_damage
			wukong_leap = true
	# 后羿Q：强化普攻+前方2目标溅射
	var houyi_splash_targets: Array = []
	if display_name == "后羿" and houyi_q_active:
		var q_base = 110 + (skill_levels[0] - 1) * 22
		dmg = q_base + actual_attack_damage * 0.75
		var splash_count = 0
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or ent == target or ent.health <= 0 or ent.team == team: continue
			if splash_count >= 2: break
			var to_ent = ent.global_position - global_position
			var to_target = target.global_position - global_position
			if to_ent.normalized().dot(to_target.normalized()) > 0.7:
				if to_ent.length() <= attack_range:
					houyi_splash_targets.append(ent)
					splash_count += 1
	if display_name == "鲁班七号":
		if luban_skill_enhanced or luban_passive_stacks >= 5:
			luban_passive_stacks = 0
			luban_skill_enhanced = false
			_luban_sweep_attack(target)
			return
	# 王昭君：每3次普攻强化→朝目标直线发射3枚冰锥（替换本次普攻，仿鲁班七号）
	if display_name == "王昭君":
		wangzhaojun_aa_counter += 1
		if wangzhaojun_aa_counter >= 3:
			wangzhaojun_aa_counter = 0
			_wangzhaojun_spike_attack(target)
			return
	if display_name == "孙尚香":
			if stat ==1:
				stat = 0
				dmg=250+20*skill_levels[0]+1*actual_attack_damage
	var _dbg_ad = dmg
	var _dbg_arthur_q = arthur_q_active
	var _dbg_ice_fist = ice_fist_buff and ice_fist_cd <= 0
	var _dbg_sage = sage_power_buff and sage_power_cd <= 0
	# 打野刀狩猎DoT（普攻完整伤害）
	if target is JungleMonster or target is Hero:
		OnHitProcessor.apply_jungle_hunt(self, target, false)
	# 闪电匕首：普攻额外40-80法伤，每3次释放链式电弧
	if equipment_slots.has("lightning_knife"):
		var lk_dmg = 40 + level * 2.6
		target.take_damage(lk_dmg, self, true, -20, 0)
		lightning_count += 1
		if lightning_count >= 3:
			lightning_count = 0
			var lc_dmg = 160 + level * 16
			# 链式电弧：从目标向周围敌人传导
			var chained = [target]
			var last = target
			for _i in range(4):
				var nearest = null
				var best_dist = 4.0
				for ent in get_tree().get_nodes_in_group("entities"):
					if ent == self or ent.health <= 0 or ent.team == team: continue
					if ent in chained: continue
					var d = last.global_position.distance_to(ent.global_position)
					if d < best_dist:
						best_dist = d
						nearest = ent
				if nearest:
					# 画电弧线(多个小球连接)
					var steps = 8
					var prev_pos = last.global_position + Vector3.UP * 1.5
					for s in range(1, steps + 1):
						var t = float(s) / steps
						var pos = last.global_position.lerp(nearest.global_position, t) + Vector3.UP * 1.5
						# 画线段
						var seg = MeshInstance3D.new()
						var box = BoxMesh.new()
						box.size = Vector3(0.1, 0.1, prev_pos.distance_to(pos))
						seg.mesh = box
						var seg_mid = (prev_pos + pos) / 2
						seg.position = seg_mid
						seg.look_at(pos, Vector3.UP)
						var smat = StandardMaterial3D.new()
						smat.albedo_color = Color.YELLOW
						smat.emission_enabled = true; smat.emission = Color.YELLOW
						smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						seg.material_override = smat
						get_parent().add_child(seg)
						var tw2 = create_tween()
						tw2.tween_interval(0.3)
						tw2.tween_callback(seg.queue_free)
						prev_pos = pos
					nearest.take_damage(lc_dmg, self, true, -20, 0)
					chained.append(nearest)
					last = nearest
				else:
					break
	# 末世：普攻额外造成80-160+7%目标生命物理伤害
	if equipment_slots.has("world_end"):
		dmg += 80 + level * 5.3 
		if target is Hero: 
			dmg += target.bonus_health * 0.07
	
	# 日渊：主动期间普攻对周围最近目标造成30%溅射伤害
	if equipment_slots.has("swift_day") and sunspire_active:
		var splash_target = null
		var splash_dist = 300.0
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or ent == target or ent.health <= 0 or ent.team == team: continue
			var d2 = target.global_position.distance_to(ent.global_position)
			if d2 < splash_dist:
				splash_dist = d2
				splash_target = ent
		if splash_target:
			splash_target.take_damage(dmg * 0.3, self, false, -30, 0)
	# 逐风叠层
	OnHitProcessor.apply_chase_wind(self)
	
	
	# 冰痕之握：技能后下次普攻额外伤害+减速(1.25s CD)
	if equipment_slots.has("ice_fist") and ice_fist_cd <= 0:
		ice_fist_buff = true
	# 李白: 普攻积累剑气
	if display_name == "李白":
		libai_sword_auras = min(libai_sword_auras + 1, 4); libai_sword_timer = 3.0
		if libai_sword_auras >= 4 :
			libai_xia_active = true; libai_xia_timer = 5.0
			_recalculate_attributes()   # 侠客行激活/延续 → 重算同步 +30 攻击 buff
	# 张飞: 普攻+3法力, 变身后额外伤害
	if display_name == "张飞":
		
		if zhangfei_transformed:
			var zfd = 110 + 110 * skill_levels[2] + bonus_attack * 0.65
			target.take_damage(zfd, self, false, -47, 0)
		else:zhangfei_mana = min(zhangfei_mana + 3, 100); mana = zhangfei_mana
	# 英睿: 普攻命中回复5点蓝 + 变身LabiB 普攻附加伤害
	if display_name == "英睿":
		mana = min(mana + 5, actual_mana_max)
		if yingrui_transformed:
			var yr_r_lv = maxi(skill_levels[2] if skill_levels.size() > 2 else 1, 1)
			var yr_dmg = 140 + 55 * yr_r_lv + bonus_attack * 0.8
			target.take_damage(yr_dmg, self, false, -60, 0)
	if display_name == "亚瑟":
		# 亚瑟Q：强化普攻(增加伤害+沉默+标记)
		if arthur_q_active:
			arthur_q_active = false
			dmg += 260 + skill_levels[0] * 65 + bonus_attack * 1.0
			target.stun_timer = 1.25
			_cc_burst(target)
			# 标记目标5秒(用GameEntity markers)
			target.markers.append({"timer": 5.0, "source": self})
		
		# 亚瑟：对标记目标额外1%最大生命法伤
		
		if target.count_markers(self) > 0:
			target.take_damage(target.max_health * 0.01, self, true, -48, 0)
	# 刘禅Q：强化普攻(击飞+额外伤害)
	if display_name == "刘禅":
		if liushan_q_active:
			liushan_q_active = false
			dmg += int(300 + 50 * skill_levels[0] + 1.22 * actual_attack_damage)
			if target is Turret:
				target.interfere_timer = max(target.interfere_timer, 1.2)
				_apply_healing(225)
			else:
				target.knockup_timer = max(target.knockup_timer, 1.0)
				_cc_burst(target)
# 大禹W：强化普攻（4秒内1次，额外伤害+回血）
	if display_name == "大禹" and dayu_w_enhanced and not dayu_w_used_enhanced:
		dayu_w_used_enhanced = true
		var w_lv = skill_levels[1]
		var enhance_dmg = 160 + (w_lv - 1) * 30 + actual_attack_damage * 1.0
		dmg += int(enhance_dmg)
		var heal_amt = 100 + (w_lv - 1) * 20 + bonus_health * 0.02
		_apply_healing(heal_amt)
	# 巫术法杖：技能后普攻额外法伤(2.5s CD)
	if witch_staff_buff and witch_staff_cd <= 0:
		witch_staff_buff = false
		witch_staff_cd = 2.5
		var ws_dmg = 180 + level * 12 + actual_ability_power * 0.4
		target.take_damage(ws_dmg, self, true, -23, 0)
	# 冰痕之握：技能后普攻额外AD伤害+减速(1.25s CD)
	if ice_fist_buff and ice_fist_cd <= 0:
		ice_fist_buff = false
		ice_fist_cd = 1.25
		dmg += 140 + level * 9.3 + actual_attack_damage * 0.4
		
		target.apply_move_pct_buff("ms_slow", 0.5, -(0.15 + level * 0.01), true)
	# 暴烈之甲：每层+1%伤害和移速
	if fierce_armor_stacks > 0:
		dmg *= (1.0 + fierce_armor_stacks * 0.01)
		apply_move_pct_buff("ms_haste", 0.1, fierce_armor_stacks * 0.01)
	# 宗师之力：技能后下次普攻额外80%AD伤害
	if sage_power_buff and sage_power_cd <= 0:
		sage_power_buff = false
		sage_power_cd = 3.0
		dmg += actual_attack_damage * 0.8
		
	# 凝冰之息：普攻减速+法伤(3s CD)
	if equipment_slots.has("frost_breath") and frost_breath_cd <= 0:
		frost_breath_cd = 3.0
		target.apply_move_pct_buff("ms_slow", 1.5, -(0.05 + level * 0.0005), true)
		var fb_dmg2 = 75 + level * 5 + actual_ability_power * 0.15
		target.take_damage(fb_dmg2, self, true, -25, 0)
	# 寒霜袭侵：减速+额外伤害
	OnHitProcessor.apply_frost_assault(self, target)
	# 金色圣剑：普攻+60伤害+攻速叠层(2层)，叠满AP法伤
	if equipment_slots.has("gold_saint_sword"):
		dmg += 60
		OnHitProcessor.apply_gold_saint_sword(self, target, false)
		
		
	# 影刃：普攻命中+10%攻速(暴击+20%)和5%移速3秒
	if equipment_slots.has("shadow_blade"):
		var sb_as = 20 if randf() < actual_crit_chance else 10
		_apply_ak_sp_buff(sb_as, 3.0)
		apply_move_pct_buff("ms_haste", 3.0, 0.05)
	# 逐日之弓+仁者破晓：普攻增伤
	if equipment_slots.has("sunspire_bow"):
		dmg += 50 if attack_range > 500 else 25
	if equipment_slots.has("dawn"):
		dmg += 50 if attack_range > 500 else 25
	# 怒龙剑盾：普攻对野怪+7%HP(回复50%伤害)、对英雄/塔+3.5%HP(2s CD)
	if equipment_slots.has("dragon_shield") and dragon_shield_cd <= 0:
		dragon_shield_cd = 2.0
		var ds_dmg = 0.0
		if target is JungleMonster:
			ds_dmg = actual_max_health * 0.07
		elif target is Hero or target is Turret:
			ds_dmg = actual_max_health * 0.035
		if ds_dmg > 0:
			target.take_damage(ds_dmg, self, false, -32, 0)
			_apply_healing(ds_dmg * 0.5)
	# 血魔之怒：普攻额外1.5%HP物伤(HP<50%时+25-50%)
	if equipment_slots.has("blood_rage"):
		var br_dmg = actual_max_health * 0.015
		if health < actual_max_health * 0.5:
			br_dmg *= 1.25 + level * 0.016
		target.take_damage(br_dmg, self, false, -41, 0)
	# 急速战靴：每次普攻回复20-40生命(远程30-60)
	if equipment_slots.has("swift_boots"):
		var bh = 30 + level * 0.6 if attack_range > 500 else 20 + level * 1.3
		_apply_healing(bh)
	# 制裁之刃：普攻重伤
	# 制裁/梦魇：重伤效果
	OnHitProcessor.apply_grievous_wounds(self, target)
	
	var is_crit = randf() < actual_crit_chance
	# 孙悟空被动：强化普攻必定暴击（wukong_leap 在强化普攻分支开头置位，此时原标记已消费）
	if wukong_leap:
		is_crit = true
	# 防御塔免疫暴击：任何暴击判定对防御塔不生效（孙悟空强化普攻同样不暴击塔）
	if target is Turret:
		is_crit = false
	if is_crit:
		dmg *= actual_crit_damage
	# 穿透百分比
	var pen = actual_phys_pen_percent
	# === 调试：普攻加成明细 ===
	var _dbg_bm2 = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var _dbg_gt = _dbg_bm2.game_time if _dbg_bm2 else 0.0
	# 攻击力拆分：基础 + 等级成长 + 装备(逐件) + BUFF
	var _dbg_base = base_attack
	var _dbg_growth = role_growth.get("attack", 0) * (level - 1)
	var _dbg_equip = 0
	var _dbg_equip_list: Array = []
	for jid2 in equipment_slots:
		var it = ItemDatabase.get_item(jid2)
		var _dbg_e_atk = it.get("attack", 0)
		if _dbg_e_atk != 0:
			_dbg_equip += _dbg_e_atk
			_dbg_equip_list.append(it.get("name", jid2) + "+" + str(round(_dbg_e_atk)))
	var _dbg_buff = 0
	for bf in active_buffs:
		_dbg_buff += bf.get("bonus_attack", 0)
	_dbg_ad = actual_attack_damage
	var _dbg_parts = ["基础=" + str(round(_dbg_base))]
	if _dbg_growth > 0: _dbg_parts.append("成长+" + str(round(_dbg_growth)))
	if _dbg_equip > 0: _dbg_parts.append("装备(" + ", ".join(_dbg_equip_list) + ")")
	if _dbg_buff > 0: _dbg_parts.append("BUFF+" + str(round(_dbg_buff)))
	var _dbg_sum = _dbg_base + _dbg_growth + _dbg_equip + _dbg_buff
	if abs(_dbg_sum - actual_attack_damage) > 1:
		_dbg_parts.append("其他+" + str(round(actual_attack_damage - _dbg_sum)))
	var _dbg_dmg = _dbg_ad
	if equipment_slots.has("world_end"):
		var _w = 80 + level * 5.3
		if target is Hero: 
			_w +=target.bonus_health * 0.07
		_dbg_parts.append("末世+" + str(round(_w)))
		_dbg_dmg += _w
	if equipment_slots.has("gold_saint_sword"):
		_dbg_parts.append("圣剑+60")
		_dbg_dmg += 60
	if equipment_slots.has("sunspire_bow"):
		var _s = 50 if attack_range > 500 else 25
		_dbg_parts.append("逐日+" + str(_s))
		_dbg_dmg += _s
	if equipment_slots.has("dawn"):
		var _d = 50 if attack_range > 500 else 25
		_dbg_parts.append("破晓+" + str(_d))
		_dbg_dmg += _d
	if _dbg_arthur_q:
		var _aq = 260 + skill_levels[0] * 65 + actual_attack_damage * 1.0
		_dbg_parts.append("亚瑟Q+" + str(round(_aq)))
		_dbg_dmg += _aq
	if _dbg_ice_fist:
		var _ifb = 140 + level * 9.3 + actual_attack_damage * 0.4
		_dbg_parts.append("冰痕+" + str(round(_ifb)))
		_dbg_dmg += _ifb
	if _dbg_sage:
		var _sp = actual_attack_damage * 0.8
		_dbg_parts.append("宗师+" + str(round(_sp)))
		_dbg_dmg += _sp
	if fierce_armor_stacks > 0:
		_dbg_parts.append("暴烈x" + "%.2f" % (1.0 + fierce_armor_stacks * 0.01))
		_dbg_dmg *= (1.0 + fierce_armor_stacks * 0.01)
	if is_crit:
		_dbg_parts.append("CRITx" + "%.1f" % actual_crit_damage)
		_dbg_dmg *= actual_crit_damage
	var _dbg_jg = ""
	for jid in equipment_slots:
		var jitem = ItemDatabase.get_item(jid)
		if jitem.get("class", "") == "jungle":
			_dbg_jg = " | 打野刀:" + jid + " stacks=" + str(jungle_stacks) + "%.1f层" % jungle_stacks
			break
	_debug_atk_info = " | AD:" + " + ".join(_dbg_parts) + " =" + str(round(dmg)) + _dbg_jg
	if not is_melee_aa():  # 远程弹道
		var bullet = Bullet.new()
		bullet.speed = 40.0
		if display_name == "狄仁杰":
			if stat2==3: 
				stat2=0
				var ang = atan2((-target.global_position.z + global_position.z),(target.global_position.x - global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				bullet.set_linear(dir,11)
				bullet.pierce = true
				if randf()<0.5:
					dmg*=0.5
					bullet.slow_dur = 1
					bullet.slow_per = 0.15
		
		bullet.damage = dmg
		# 后羿被动：惩戒射击：3层后每支箭40%伤害
		if display_name == "后羿" and stat >= 3:
			stat_timer = 3.0
			dmg = dmg * 1.2
			bullet.damage = dmg
		bullet.team = team
		bullet.target = target
		# 元流之子·万物为流：持有"流"时普攻自动升级为贯穿弩箭（耗1层，贯穿命中额外伤害在 Bullet 结算）
		if display_name == "元流之子" and yuanliu_flow > 0 and is_instance_valid(target):
			yuanliu_flow -= 1
			yuanliu_flow_activity()   # 消耗「流」→ 重置5秒闲置窗口
			bullet.pierce = true
			bullet.yuanliu_strong = true
			bullet.yuanliu_strong_extra = int(74.4+5.7*level) + float(bonus_attack) * 0.2
			bullet.scale = Vector3(1.8, 1.8, 1.8)
			var _yl_dir = (Vector3(target.global_position.x, 0.0, target.global_position.z) - Vector3(global_position.x, 0.0, global_position.z)).normalized()
			if _yl_dir.length() > 0.1:
				bullet.set_linear(_yl_dir, 10.0)
				bullet.max_distance = 15.0
		if red_buff_active:
			bullet.slow_per = 0.3
			bullet.slow_dur = 2
			bullet.fire_damage = 30+level*3
		bullet.source = self
		bullet.is_magic = false
		bullet.skill_id = 0   # 普攻
		bullet.pen_percent = pen   # 需要扩展 Bullet 类
		bullet.is_crit = is_crit   # 本次普攻掷出的暴击随子弹传给受击方
		bullet.global_position = global_position + Vector3(0, 1.2, 0)
		get_parent().add_child(bullet)
		# 后羿被动：额外2支箭矢（总计3支=120%伤害）
		if display_name == "后羿" and stat >= 3:
			

			# 后羿Q：溅射子弹（受惩戒射击影响,dmg已包含40%惩罚）
			for st in houyi_splash_targets:
				var splash_dmg = int(dmg * 0.5)
				var splash_dir = (st.global_position - global_position).normalized()
				var splash_bullet = skillapply.create_bullet(splash_dmg, 0, 0, 0, false, self, splash_dir, -1)
				splash_bullet.target = st
				splash_bullet.life_time = 3
				get_parent().add_child(splash_bullet)
	else:
		# 孙悟空被动：强化普攻（冲刺+暴击+印记消耗）
		if display_name == "孙悟空" :
			
			# R印记消耗
			for _mi in range(target.markers.size() - 1, -1, -1):
				if target.markers[_mi].get("type") == "sunwukong_r" and target.markers[_mi].get("source") == self:
					var _mark_dmg = int(200 + 100*(skill_levels[2]-1) + bonus_attack * 0.65)
					dmg += _mark_dmg
					target.markers.remove_at(_mi)
					break

		if display_name == "铠":
			if stat ==1:
				stat = 0
				dmg+=int(100+25*skill_levels[1]+0.32*bonus_attack)
		var bullet = Bullet.new()
		bullet.speed = 40.0
		bullet.damage_range =1.2
		if display_name == "不知火舞":
			bullet.damage_range = 0
			if stat_timer >=5:
				bullet.repel = true
				stat_timer = 0
				target.take_damage(100+1*actual_ability_power,self,true,0,actual_magic_pen_percent)
				mana+=10
		if display_name == "马超":
			bullet.damage_range = 0
			if stat_timer >0:
				stat_timer = max(stat_timer-4,0)
				dmg+=65+0.22*bonus_attack+5*level
				_apply_healing(7*level+94+0.02*bonus_health)
				for i in range(skill_cooldowns.size()):
					if skill_cooldowns[i] > 0: skill_cooldowns[i] *=0.85
		bullet.damage = dmg
		bullet.team = team
		bullet.target = target
		if red_buff_active:
			bullet.slow_per = 0.3
			bullet.slow_dur = 2
			bullet.fire_damage = 30+level*3
		bullet.source = self
		bullet.is_magic = false
		bullet.skill_id = 0   # 普攻
		bullet.pen_percent = pen   # 需要扩展 Bullet 类
		bullet.is_crit = is_crit   # 本次普攻掷出的暴击随子弹传给受击方
		bullet.global_position = global_position + Vector3(0, 1.2, 0)
		bullet.visible = false     # 近战：不显示弹道，命中表现交给武器刀光+接触火花
		get_parent().add_child(bullet)
		_melee_weapon_fx(target)
	attack_timer = 1.0 / attack_speed
	_attack_anim()
	var dir = target.global_position - global_position
	rotation.y = atan2(dir.x, dir.z)
	if not is_melee_aa():
		Vfx.cast_burst(display_name, _muzzle_pos(), Vector3(sin(rotation.y), 0.0, cos(rotation.y)), 0.5)
	if display_name == "孙尚香":
		if skill_cooldowns[0] > 0: skill_cooldowns[0] *=0.9
	if display_name == "狄仁杰":
		stat_timer = 3.0
		if stat <5: stat +=1;
		if stat2 <3: stat2 +=1
		_recalculate_attributes()   # 叠层变化 → 重算同步叠层被动 buff
	if display_name == "后羿":
		stat_timer = 3.0
		stat = min(stat + 1, 3)
		_recalculate_attributes()   # 叠层变化 → 重算同步叠层被动 buff
	if display_name == "鲁班七号":
		luban_passive_stacks = min(luban_passive_stacks + 1, 5)
	# 夏侯惇：W强化普攻真伤
	if display_name == "夏侯惇" and xiahou_enhanced_attacks > 0:
		xiahou_enhanced_attacks -= 1
		var w_true_dmg = 150 + (skill_levels[1] - 1) * 30 + bonus_attack * 0.45
		target.take_true_damage(int(w_true_dmg), self, false, -50, 1.0)
		skill_cooldowns[2] = max(0, skill_cooldowns[2] - 1.0)
	# 夏侯惇：被动噬目回血
	if display_name == "夏侯惇" and xiahou_passive_active:
		var heal_amt = 220 + bonus_health * 0.06
		_apply_healing(heal_amt)


# 近战普攻「武器真的砍到」：从武器握点向敌人身体表面拉一道刀光 + 接触火花
func _melee_weapon_fx(target: GameEntity) -> void:
	if target == null or not is_instance_valid(target):
		return
	var fwd := target.global_position - global_position
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	fwd = fwd.normalized()
	# 命中点：敌人「朝我这一侧」的体表（不是身体中心），高度按体型取胸腹
	var r := 0.85
	var hit_h := 1.15
	if target is Minion:
		r = float(target.body_radius) + 0.3
		hit_h = 0.75
	elif target is Turret:
		r = 1.5
		hit_h = 1.6
	var contact := target.global_position - fwd * r + Vector3.UP * hit_h
	var tip := _weapon_world_pos(fwd, contact)
	Vfx.weapon_hit(tip, contact, Vfx.color_for_hero(display_name), Vfx.color2_for_hero(display_name), 1.0)
	# 本地玩家砍中敌方英雄：极短顿帧，强化“砍到了”的手感
	if not is_ai and target is Hero and Vfx.quality >= 2:
		Vfx.hitstop(0.018)


# 武器刀光起点：沿攻击方向、按武器实际长度取刀刃中段（武器越长，起点越靠前）
func _weapon_world_pos(fwd: Vector3, contact: Vector3) -> Vector3:
	var blade := _weapon_blade_len()
	var dist := Vector2(contact.x - global_position.x, contact.z - global_position.z).length()
	var d := clampf(blade * 0.78, 0.8, maxf(dist - 0.9, 0.8))
	return global_position + fwd * d + Vector3.UP * 1.25


# 武器刀刃长度（世界米）：有武器模型时取模型沿长轴的长度，否则按 1.2m 兜底
func _weapon_blade_len() -> float:
	var rig = visual_mesh.get_meta("weapon_rig", null) if visual_mesh != null and is_instance_valid(visual_mesh) else null
	if rig is Node3D and is_instance_valid(rig):
		var mesh := (rig as Node3D).get_node_or_null("WeaponMesh")
		if mesh is Node3D and is_instance_valid(mesh):
			var top: float = HeroWeapons._local_top(mesh)
			if top > 0.3:
				return top
	return 1.2


# 马超强化普攻（突进）：拾枪/召回获得强化普攻后，点普攻键 → 朝「普攻轮盘方向→目标方向→面朝方向」
# 位移2.5米，对位移路径沿途所有敌人施加强化普攻伤害（物理，走护甲/穿透公式）；
# 回复与全技能减CD沿用原拾枪强化普攻数值，每次冲刺结算一次；消耗4秒 stat_timer（即1次强化普攻）。
func _machao_enhanced_dash(aim_target: GameEntity = null, dir_override: Vector3 = Vector3.ZERO) -> void:
	# 方向：AI 指定方向 > 普攻轮盘拖拽 > 攻击目标 > 面朝兜底（空冲）
	var dir := Vector3.ZERO
	if dir_override.length() > 0.05:
		dir = dir_override.normalized()
	if not is_ai:
		var drag := TouchController.get_attack_drag()
		if drag.length() > ATTACK_WHEEL_DRAG_THRESHOLD:
			var aim_screen := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
			var aim := _screen_ray_world(aim_screen)
			var d := aim - global_position
			d.y = 0.0
			if d.length() > 0.05:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		var t: GameEntity = null
		if aim_target and is_instance_valid(aim_target) and aim_target.health > 0:
			t = aim_target
		elif manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
			t = manual_target
		else:
			t = _get_attack_target(_aa_engage_reach(), true)
		if t:
			var d := t.global_position - global_position
			d.y = 0.0
			if d.length() > 0.05:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	# 位移 2.5 米（几帧内突进过去，不做寻路）
	var start := global_position
	var end: Vector3 = start + dir * 2.5
	rotation.y = atan2(dir.x, dir.z)
	global_position = end
	global_position.y = 0.5
	_clamp_to_map_edge()
	end = global_position
	global_position = start
	Vfx.dash_fx(start, end, Vfx.color_for_hero(display_name), not is_ai, 2.5)
	dash_move_to(end, 0.14, "")
	_attack_anim()
	# 位移沿途敌人（水平投影到线段的距离 ≤ 自身半径+余量 视为命中）各吃一次强化普攻伤害
	var dash_dmg := int(actual_attack_damage + 65.0 + 0.22 * bonus_attack + 5.0 * level)
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster):
			continue
		if _dist_point_segment_h(ent.global_position, start, end) <= ent.body_radius + 0.6:
			ent.take_damage(dash_dmg, self, false, 0, actual_phys_pen_percent)
	# 拾枪强化普攻的回复与全技能冷却缩短（每次冲刺结算一次）
	_apply_healing(7 * level + 94 + 0.02 * bonus_health)
	for i in range(skill_cooldowns.size()):
		if skill_cooldowns[i] > 0:
			skill_cooldowns[i] *= 0.85
	# 消耗1次强化普攻
	stat_timer = max(stat_timer - 4.0, 0.0)

# 铠强化普攻（突进）：W 出手后获得1次强化普攻，点/按普攻键 → 朝「普攻轮盘方向→目标方向→面朝方向」
# 位移2.5米，对位移路径沿途所有敌人各造成一次强化普攻伤害（完整普攻+强化附加，物理走护甲/穿透公式）
# 并击飞；每次突进消耗1次强化普攻（stat 置0），无目标时也能沿轮盘/面朝空冲作为机动位移。
func _kai_enhanced_dash(aim_target: GameEntity = null, dir_override: Vector3 = Vector3.ZERO) -> void:
	# 方向：AI 指定方向 > 普攻轮盘拖拽 > 攻击目标 > 面朝兜底（空冲）
	var dir := Vector3.ZERO
	if dir_override.length() > 0.05:
		dir = dir_override.normalized()
	if not is_ai:
		var drag := TouchController.get_attack_drag()
		if drag.length() > ATTACK_WHEEL_DRAG_THRESHOLD:
			var aim_screen := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
			var aim := _screen_ray_world(aim_screen)
			var d := aim - global_position
			d.y = 0.0
			if d.length() > 0.05:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		var t: GameEntity = null
		if aim_target and is_instance_valid(aim_target) and aim_target.health > 0:
			t = aim_target
		elif manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
			t = manual_target
		else:
			t = _get_attack_target(_aa_engage_reach(), true)
		if t:
			var d := t.global_position - global_position
			d.y = 0.0
			if d.length() > 0.05:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	# 位移 2.5 米（几帧内突进过去，不做寻路）
	var start := global_position
	var end: Vector3 = start + dir * 2.5
	rotation.y = atan2(dir.x, dir.z)
	global_position = end
	global_position.y = 0.5
	_clamp_to_map_edge()
	end = global_position
	global_position = start
	Vfx.dash_fx(start, end, Vfx.color_for_hero(display_name), not is_ai, 2.5)
	dash_move_to(end, 0.14, "")
	_attack_anim()
	# 位移沿途敌人（水平投影到线段距离 ≤ 自身半径+余量 视为命中）各吃一次强化普攻伤害；命中者击飞
	var dash_dmg := int(actual_attack_damage + 100.0 + 25.0 * skill_levels[1] + 0.32 * bonus_attack)
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster):
			continue
		if _dist_point_segment_h(ent.global_position, start, end) <= ent.body_radius + 0.6:
			ent.take_damage(dash_dmg, self, false, 0, actual_phys_pen_percent)
			if ent is Hero or ent is Minion or ent is JungleMonster:
				ent.knockup_timer = maxf(ent.knockup_timer, 1.0)
				_cc_burst(ent)
	# 消耗本次强化普攻
	stat = 0

# 不知火舞强化普攻·空放位移（参照马超强普突进）：
# 强化普攻（stat_timer>=5）就绪且没有可打目标时，点/按普攻键 → 沿「普攻轮盘方向→面朝方向」前冲 2.2 米，
# 位移沿途敌人各吃一次强化普攻的魔法伤害（100+AP，走法穿），命中者被忍蜂推开（同强化普攻的 repel）；
# 出手后清空 stat_timer（消耗这次强化普攻，重新蓄力）。
func _mai_enhanced_dash(dir_override: Vector3 = Vector3.ZERO) -> void:
	var dir := Vector3.ZERO
	if dir_override.length() > 0.05:
		dir = dir_override.normalized()
	if not is_ai:
		var drag := TouchController.get_attack_drag()
		if drag.length() > ATTACK_WHEEL_DRAG_THRESHOLD:
			var aim_screen := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
			var aim := _screen_ray_world(aim_screen)
			var d := aim - global_position
			d.y = 0.0
			if d.length() > 0.05:
				dir = d.normalized()
	if dir == Vector3.ZERO:
		dir = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var start := global_position
	var end: Vector3 = start + dir * 2.2
	rotation.y = atan2(dir.x, dir.z)
	global_position = end
	global_position.y = 0.5
	_clamp_to_map_edge()
	end = global_position
	global_position = start
	Vfx.dash_fx(start, end, Vfx.color_for_hero(display_name), not is_ai, 2.2)
	dash_move_to(end, 0.12, "")
	_attack_anim()
	# 沿途命中：强化普攻的魔法伤害（与普攻强化结算同口径）
	var mai_dmg := int(100.0 + 1.0 * actual_ability_power)
	var hit_any := false
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster):
			continue
		if _dist_point_segment_h(ent.global_position, start, end) <= ent.body_radius + 0.6:
			ent.take_damage(mai_dmg, self, true, 0, actual_magic_pen_percent)
			hit_any = true
			if not (ent is Turret):
				ent.global_position += (ent.global_position - start).normalized() * 2.5   # 忍蜂推开
	# 命中回蓝（同强化普攻命中）+ 消耗强化普攻
	if hit_any:
		mana = minf(mana + 10.0, actual_mana_max)
	stat_timer = 0.0

# —— 关键操作（群控）判定 ——
# 同一英雄 0.9s 内对 ≥3 名敌方英雄施加硬控（眩晕/击飞）→ 我方"关键操作"播报。
# 各处施加硬控的落点统一调用 _cc_burst(target) 上报。
var _cc_burst_targets: Dictionary = {}
var _cc_burst_last: float = 0.0

func _cc_burst(target) -> void:
	if not Config.is_ally(team) or target == null or not (target is Hero):
		return
	if target.team == team:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _cc_burst_last > 0.9:
		_cc_burst_targets.clear()
	_cc_burst_last = now
	_cc_burst_targets[target.get_instance_id()] = now
	if _cc_burst_targets.size() >= 3:
		_cc_burst_targets.clear()
		var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm:
			bm.trigger_special_announce("group_cc", 6.0)

# 点 p 到水平线段 a→b（忽略Y）的最短距离
func _dist_point_segment_h(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := p - a
	pa.y = 0.0
	var ab := b - a
	ab.y = 0.0
	var ab_len2 := ab.length_squared()
	if ab_len2 < 0.0001:
		return pa.length()
	var t := clampf(pa.dot(ab) / ab_len2, 0.0, 1.0)
	return (pa - ab * t).length()

func set_manual_target(target: GameEntity):
	# 来自世界点击/普攻轮盘等其它输入：先解除锁敌头像的锁定，避免两个变量指向不同目标
	if target != locked_target:
		locked_target = null
	if target and target.team != team:
		var dist = global_position.distance_to(target.global_position) 
		if dist <= attack_range:
			manual_target = target
			#move_towards(target.global_position)
			return
	manual_target = null

# 锁敌头像：记录/解除独立锁定目标（同时同步 manual_target 让普攻/技能直接吃这个目标）
func set_locked_target(t: Hero) -> void:
	if locked_target != null and manual_target == locked_target:
		manual_target = null
	locked_target = t
	if t != null and is_instance_valid(t) and t.health > 0:
		manual_target = t

func move_towards(pos: Vector3):
	if is_ai:
		return   # AI 英雄不响应玩家右键移动
	move_target = pos
	_create_move_indicator(pos)

func _create_move_indicator(world_pos: Vector3):
	# 冷却限制，避免频繁点击产生过多特效
	var now = Time.get_ticks_msec() / 1000.0
	if now - last_indicator_time < INDICATOR_COOLDOWN:
		return
	last_indicator_time = now
	var indicator = MeshFactory.create_torus_ring(0.30, 0.45, Color.GREEN, true, 0.7)
	indicator.position = world_pos + Vector3.UP * 0.3
	get_parent().add_child(indicator)
	# 0.8秒后淡出并移除
	var tween = create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(indicator.material_override, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(indicator.queue_free)

# 计算技能瞄准点（王者荣耀式）：
# - source_mouse=false（移动端）：有拖拽 → 屏幕中心+拖拽方向；否则朝锁定目标；否则朝面朝方向
# - source_mouse=true（桌面键盘）：瞄准 = 鼠标位置
# 结果经地面射线取世界坐标，并限制在 skill.cast_range 内
# 轻点技能的自动索敌：英雄 > 小兵 > 野怪（中立），不考虑防御塔/建筑；同档内取最近
func _nearest_skill_target(range: float) -> GameEntity:
	if range <= 0.0:
		range = attack_range * 0.01
	var best: GameEntity = null
	var best_rank := 9
	var best_d := 1e18
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is JungleMonster):
			continue   # 防御塔/水晶/墙体/草丛等建筑与地形不参与自动索敌
		if ent is Hero and ((ent as Hero).is_invisible_to_enemy() or (ent as Hero).is_untargetable_by_enemies()):
			continue
		var d: float = global_position.distance_to(ent.global_position) - ent.body_radius
		if d > range:
			continue
		var rank := 0 if ent is Hero else (1 if ent is Minion else 2)
		if rank < best_rank or (rank == best_rank and d < best_d):
			best_rank = rank
			best_d = d
			best = ent
	return best

func _compute_skill_aim(drag_in: Vector2, skill: Skill, source_mouse: bool) -> Vector3:
	var drag := drag_in * PlayerPrefs.opt_float("skill_sens", 1.0)
	var cam := get_viewport().get_camera_3d()
	var target_pos := global_position + Vector3.FORWARD * 5.0
	if cam:
		var aim_screen := get_viewport().get_mouse_position()
		var direct := Vector3.ZERO
		var has_direct := false
		if not source_mouse:
			var is_tap := drag.length() <= 12.0
			if not is_tap:
				aim_screen = get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
			elif skill != null and int(skill.type) == 4:
				# 位移类技能轻点：默认朝英雄朝向
				aim_screen = cam.unproject_position(global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 5.0)
			elif skill != null and int(skill.type) in [0, 1, 3, 5]:
				# 线性/目标/AOE 轻点：默认朝最近敌人（英雄 > 小兵 > 野怪，忽略防御塔）
				var auto_t = _nearest_skill_target(skill.cast_range)
				if auto_t and is_instance_valid(auto_t):
					direct = auto_t.global_position
					has_direct = true
				else:
					aim_screen = cam.unproject_position(global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 5.0)
			else:
				if manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
					direct = manual_target.global_position
					has_direct = true
				else:
					aim_screen = cam.unproject_position(global_position + Vector3(sin(rotation.y), 0, cos(rotation.y)) * 5.0)
		if has_direct:
			target_pos = Vfx.ground_pos(direct)
		else:
			target_pos = _screen_ray_world(aim_screen)
		# 移动端拖拽：拖得越长投放越远（≤施法范围），可精准控制投放距离；桌面用鼠标位置自然定距
		if not source_mouse and drag.length() > 12.0:
			var aim_dir := target_pos - global_position
			aim_dir.y = 0.0
			var aim_len := aim_dir.length()
			if aim_len > 0.01:
				var frac := clampf(drag.length() / SKILL_AIM_FULL_DRAG, 0.0, 1.0)
				var dist := lerpf(2.0, skill.cast_range, frac)
				if skill.type == 1:
					dist = maxf(dist, skill.radius * 0.6)   # 范围技中心不贴在自己脚下
				target_pos = global_position + aim_dir / aim_len * dist
		elif global_position.distance_to(target_pos) > skill.cast_range:
			var dir := (target_pos - global_position).normalized()
			target_pos = global_position + dir * skill.cast_range
	return target_pos

# 全图技能瞄准态（小地图瞄准线/命中的敌人高亮用）：{} 或 {from, dir, len, hit_r, only_hero, color}
func global_aim() -> Dictionary:
	if aim_slot < 0 or health <= 0.0:
		return {}
	var prof: Dictionary = SkillDatabase.global_shot_profile(display_name, aim_slot)
	if prof.is_empty():
		return {}
	var d: Vector3 = aim_world - global_position
	d.y = 0.0
	if d.length() < 0.15:
		d = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if d.length() < 0.01:
		return {}
	return {"from": global_position, "dir": d.normalized(), "len": float(prof["len"]),
		"hit_r": float(prof["hit_r"]), "only_hero": bool(prof["only_hero"]), "color": prof["color"]}

# 屏幕坐标 → 地面世界坐标（射线打到地面/墙体；落空时取射线远端）
func _screen_ray_world(aim_screen: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return global_position
	var from := cam.project_ray_origin(aim_screen)
	var to := from + cam.project_ray_normal(aim_screen) * 100
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result:
		return result.position
	return from + cam.project_ray_normal(aim_screen) * 25.0

# 连发技能（沈梦溪1猫咪炸弹 / 东皇太一2堕神契约等）逐发重取瞄准点：
# 每发发射前重读「技能按钮轮盘」的实时拖动指示 —— 连发期间按住技能键拖到哪，
# 这一发（以及后续未再拖动时）就朝哪打；未在拖轮盘 / AI 则沿用当前落点 cur
# （首发 = 本次施放时的瞄准点）。
func barrage_live_aim(slot: int, cur: Vector3) -> Vector3:
	if is_ai or health <= 0 or slot < 0 or slot >= skills.size() or skills[slot] == null:
		return cur
	if TouchController.get_skill_held(slot):
		var drag := TouchController.get_skill_drag(slot)
		if drag.length() > 12.0:
			return _compute_skill_aim(drag, skills[slot], false)
	return cur

# 东皇太一2技能（堕神契约）连发落点预览：第0发落在瞄准点，后一发在前一发身后1.5米，
# 预览环数量=当前能量体数（最多3个，随轮盘拖动实时刷新）；无能量体则全部隐藏。
func _show_donghuang_w_preview(aim_pos: Vector3):
	var total: int = clampi(donghuang_orbs, 0, 3)
	var dir := aim_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = Vector3(sin(rotation.y), 0, cos(rotation.y))
	dir = dir.normalized()
	while donghuang_aim_rings.size() < total:
		var ring := MeshFactory.create_cast_area(
			Color(1.0, 0.33, 0.264, 1.0) if team == 1 else Color(0.0, 0.886, 1.0, 1.0), 1)
		MeshFactory.set_cast_preview_color(ring, Vfx.color_for_hero(display_name))
		ring.scale = Vector3(3.2, 1.0, 3.2)
		add_child(ring)
		donghuang_aim_rings.append(ring)
	for i in range(donghuang_aim_rings.size()):
		if i < total:
			var ring: MeshInstance3D = donghuang_aim_rings[i]
			var landing := aim_pos - dir * (1.5 * i)
			ring.global_position = Vector3(landing.x, Config.GROUND_FX_Y + 0.01, landing.z)
			ring.visible = true
		else:
			donghuang_aim_rings[i].visible = false

func _hide_donghuang_w_preview():
	for ring in donghuang_aim_rings:
		ring.visible = false

# 普攻轮盘选敌：按拖拽方向（屏幕中心为原点）投影，选出最接近落点的可攻击目标
func _pick_attack_target(drag: Vector2, pick_range: float) -> GameEntity:
	var aim_screen := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
	var aim_pos := _screen_ray_world(aim_screen)
	var best: GameEntity = null
	var best_dist := 999999.0
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
			continue
		if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster or ent is Tripod):
			continue
		if global_position.distance_to(ent.global_position) > pick_range:
			continue
		if ent is Hero and (ent as Hero).is_invisible_to_enemy():
			continue  # 隐身单位不可被目标型技能/轮盘选中（AoE 仍可命中）
		var d: float = ent.global_position.distance_to(aim_pos)
		if d < best_dist:
			best_dist = d
			best = ent
	return best

## 召唤师技能施法预览：复用技能的地面指示器（范围圈/落点圈/位移箭头/脚下法阵）
func _update_summoner_preview(drag: Vector2, touch_aiming: bool) -> void:
	var sk := summoner_skill
	var col: Color = Vfx.color_for_hero(display_name)
	if _pv_color_key != display_name + "|sum":
		_pv_color_key = display_name + "|sum"
		for mi in [cast_range_ring, aoe_fill, impact_ring, arrow_shaft, arrow_head]:
			MeshFactory.set_cast_preview_color(mi, col)
	var ground_y := Config.GROUND_FX_Y
	var self_pos := Vector3(global_position.x, ground_y, global_position.z)
	# 瞄准方向：桌面=鼠标地面点；移动端=拖拽方向（未拖时取面朝方向）
	var aim_dir := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if touch_aiming:
		if drag.length() > 12.0:
			# 拖拽方向按真实镜头反投影（红方镜头转了 180°，不能再直接把屏幕 y 当世界 z）
			aim_dir = _drag_to_world_dir(drag)
	elif get_viewport() != null:
		var md: Vector3 = _screen_ray_world(get_viewport().get_mouse_position()) - global_position
		md.y = 0.0
		if md.length() > 0.2:
			aim_dir = md.normalized()
	arrow_preview.visible = false
	aoe_fill.visible = false
	impact_ring.visible = false
	cast_range_ring.visible = false
	if _foot_sigil != null and is_instance_valid(_foot_sigil):
		_foot_sigil.visible = true
	match sk.skill_name:
		"闪现":
			var land := global_position + aim_dir * 5.0
			arrow_preview.visible = true
			arrow_shaft.position = Vector3(0, 0, 2.5)
			arrow_shaft.scale = Vector3(0.9, 1.0, 5.0)
			arrow_head.position = Vector3(0, 0, 5.0)
			arrow_preview.global_position = self_pos + Vector3(0, 0.025, 0)
			arrow_preview.global_rotation.y = atan2(aim_dir.x, aim_dir.z)
			impact_ring.visible = true
			impact_ring.global_position = Vector3(land.x, ground_y + 0.01, land.z)
			impact_ring.scale = Vector3.ONE
		"终结", "惩击":
			var rng: float = 5.0 if sk.skill_name == "终结" else 3.0
			var aim_pos := global_position + aim_dir * rng
			cast_range_ring.visible = true
			cast_range_ring.global_position = self_pos + Vector3(0, 0.02, 0)
			cast_range_ring.scale = Vector3(rng, rng, rng)
			aoe_fill.visible = true
			MeshFactory.set_cast_area_mode(aoe_fill, 1)
			aoe_fill.global_position = Vector3(aim_pos.x, ground_y, aim_pos.z)
			aoe_fill.scale = Vector3(1.2, 1, 1.2)
		"晕眩", "弱化", "治疗术":
			var rad: float = 3.0 if sk.skill_name == "治疗术" else 5.0
			aoe_fill.visible = true
			MeshFactory.set_cast_area_mode(aoe_fill, 0)
			aoe_fill.global_position = self_pos
			aoe_fill.scale = Vector3(rad, 1, rad)
			impact_ring.visible = true
			impact_ring.global_position = self_pos + Vector3(0, 0.01, 0)
			impact_ring.scale = Vector3(rad, 1, rad)
		_:
			pass   # 疾跑/狂暴/净化/传送：仅脚下法阵提示（传送在小地图选点）


func _handle_skill_input(delta):
	if Input.is_key_pressed(KEY_CTRL):
		return
	_summoner_preview_on = false
	# 召唤师技能施法预览：按住召唤师按钮/键（且没在按技能）时，复用技能同一套地面指示器
	# 注意不能提前 return：召唤师技能的施放走本函数末尾（移动端松手/桌面 just_pressed）
	if summoner_skill != null and summoner_cooldown <= 0.0 and not is_ai:
		var sk_held := false
		for i in range(3):
			if i < skills.size() and skill_levels[i] >= 1 \
					and (TouchController.get_skill_held(i) or Input.is_action_pressed("skill_%d" % i)):
				sk_held = true
				break
		if not sk_held:
			var sum_touch := TouchController.get_summoner_held()
			if sum_touch or Input.is_action_pressed("summoner_spell"):
				_summoner_preview_on = true
				_update_summoner_preview(TouchController.get_summoner_drag(), sum_touch)
	var any_held = false
	var held_index = -1
	for i in range(3):
		if i >= skills.size() or skill_levels[i] < 1:
			continue    # 技能不可用
		if TouchController.get_skill_held(i) or Input.is_action_pressed("skill_%d" % i):
			any_held = true
			held_index = i
			if is_recalling and not is_ai: cancel_recall()
			break
	var skill = skills[held_index].duplicate() as Skill
	skill.cooldown = skill.cooldown - skill.cd_bonus*(skill_levels[held_index]-1)
	skill.mana_cost = skill.mana_cost - skill.power_bonus*(skill_levels[held_index]-1)
	# 瞄准来源：移动端=技能按钮拖拽方向（未拖时朝攻击目标/面朝方向）；桌面=鼠标位置
	var touch_aiming := held_index >= 0 and TouchController.get_skill_held(held_index)
	var target_pos := _compute_skill_aim(TouchController.get_skill_drag(held_index) if touch_aiming else Vector2.ZERO, skill, not touch_aiming)
	# 目标型技能：瞄准点吸附到附近最近的敌方单位（王者荣耀式拖拽选目标）
	if touch_aiming and skill.type == 0:
		var snap := _pick_skill_target(target_pos, skill.cast_range)
		if snap:
			target_pos = snap.global_position
	# 预览控制
	if any_held and held_index < skills.size():
		if skill_cast_ready(held_index):
			aim_slot = held_index
			aim_world = target_pos
			# 预览配色跟随英雄元素色（技能 1/2/3 依次偏向副元素）
			var pv_key := "%s|%d" % [display_name, held_index]
			if pv_key != _pv_color_key:
				_pv_color_key = pv_key
				var pv_col: Color = Vfx.color_for_hero(display_name)
				if held_index > 0:
					pv_col = pv_col.lerp(Vfx.color2_for_hero(display_name), 0.16 * held_index)
				for mi in [cast_range_ring, aoe_fill, impact_ring, arrow_shaft, arrow_head]:
					MeshFactory.set_cast_preview_color(mi, pv_col)
			# 任何技能进入瞄准/预览：脚底浮现法阵（随英雄移动，跟随朝向旋转）
			if _foot_sigil != null and is_instance_valid(_foot_sigil):
				_foot_sigil.visible = true
			var dir = target_pos - global_position
			var dist = dir.length()
			var angle_y = atan2(dir.x, dir.z) if dist > 0.01 else 0.0
			var ground_y := Config.GROUND_FX_Y
			var radius: float = maxf(skill.radius, 0.0)
			var aim_pos := Vector3(target_pos.x, ground_y, target_pos.z)
			impact_ring.visible = false
			
			if display_name == "东皇太一" and held_index == 1:
				_show_donghuang_w_preview(target_pos)
				arrow_preview.visible = false
				aoe_fill.visible = false
				cast_range_ring.visible = false
			elif skill.type == 1:   # 范围技能：柔光落点 + 双层范围圈
				# 元流之子/东皇太一 的一技能是「以自身为中心的AOE」：预览圈固定跟随自身
				var self_centered_aoe: bool = held_index == 0 and (display_name == "元流之子" or display_name == "东皇太一" or display_name == "吕布")
				aoe_fill.visible = true
				MeshFactory.set_cast_area_mode(aoe_fill, 0)
				aoe_fill.global_position = Vector3(global_position.x, ground_y, global_position.z) if self_centered_aoe else aim_pos
				aoe_fill.scale = Vector3(radius, 1, radius)
				cast_range_ring.visible = skill.cast_range > 0.0 and not self_centered_aoe
				cast_range_ring.global_position = Vector3(global_position.x, ground_y + 0.02, global_position.z)
				cast_range_ring.scale = Vector3(skill.cast_range, skill.cast_range, skill.cast_range)
				arrow_preview.visible = false
			elif skill.type == 3: # 线性技能：贴地能量带，长度=子弹最远飞行距离；有半径则补落点圈
				var arrow_len = skill.bullet_range if skill.bullet_range > 0 else skill.cast_range
				arrow_preview.visible = true
				arrow_shaft.position = Vector3(0, 0, arrow_len * 0.5)
				arrow_shaft.scale = Vector3(0.9, 1.0, arrow_len)
				arrow_head.position = Vector3(0, 0, arrow_len)
				arrow_preview.global_position = Vector3(global_position.x, ground_y + 0.025, global_position.z)
				arrow_preview.global_rotation.y = angle_y
				aoe_fill.visible = false
				cast_range_ring.visible = false
				if radius > 0.0:
					impact_ring.visible = true
					impact_ring.global_position = aim_pos + Vector3(0, 0.01, 0)
					impact_ring.scale = Vector3(radius, 1, radius)
			elif skill.type == 4: # 位移技能：贴地能量带，长度=位移最远距离；有半径则补落点圈
				var dash_len = skill.self_displacement if skill.self_displacement > 0 else skill.cast_range
				arrow_preview.visible = true
				arrow_shaft.position = Vector3(0, 0, dash_len * 0.5)
				arrow_shaft.scale = Vector3(0.9, 1.0, dash_len)
				arrow_head.position = Vector3(0, 0, dash_len)
				arrow_preview.global_position = Vector3(global_position.x, ground_y + 0.025, global_position.z)
				arrow_preview.global_rotation.y = angle_y
				aoe_fill.visible = false
				cast_range_ring.visible = false
				if radius > 0.0:
					impact_ring.visible = true
					impact_ring.global_position = aim_pos + Vector3(0, 0.01, 0)
					impact_ring.scale = Vector3(radius, 1, radius)
			elif skill.type == 2 or skill.type == 6:
				# 增益/护盾：有半径的（吕布R/太乙Q/小乔R/刘禅R）补落点范围；
				# 纯自身增益用脚下柔光，不再显示误导性的瞄准准星。
				arrow_preview.visible = false
				if radius > 0.0:
					aoe_fill.visible = false
					impact_ring.visible = true
					impact_ring.global_position = aim_pos + Vector3(0, 0.01, 0)
					impact_ring.scale = Vector3(radius, 1, radius)
				else:
					aoe_fill.visible = true
					MeshFactory.set_cast_area_mode(aoe_fill, 0)
					aoe_fill.global_position = Vector3(global_position.x, ground_y, global_position.z)
					aoe_fill.scale = Vector3(1.6, 1, 1.6)
				cast_range_ring.visible = skill.cast_range > 0.0
				cast_range_ring.global_position = Vector3(global_position.x, ground_y + 0.02, global_position.z)
				cast_range_ring.scale = Vector3(skill.cast_range, skill.cast_range, skill.cast_range)
			else:   # 目标类：施法范围圈 + 瞄准准星；有半径则叠加命中范围
				arrow_preview.visible = false
				aoe_fill.visible = true
				MeshFactory.set_cast_area_mode(aoe_fill, 1)
				aoe_fill.scale = Vector3(1.2, 1, 1.2)
				aoe_fill.global_position = aim_pos
				if radius > 0.0:
					impact_ring.visible = true
					impact_ring.global_position = aim_pos + Vector3(0, 0.01, 0)
					impact_ring.scale = Vector3(radius, 1, radius)
				cast_range_ring.visible = skill.cast_range > 0.0
				cast_range_ring.global_position = Vector3(global_position.x, ground_y + 0.02, global_position.z)
				cast_range_ring.scale = Vector3(skill.cast_range, skill.cast_range, skill.cast_range)
		else:
			aim_slot = -1
			_hide_donghuang_w_preview()
			arrow_preview.visible = false
			aoe_fill.visible = false
			impact_ring.visible = false
			cast_range_ring.visible = false
			if _foot_sigil != null and is_instance_valid(_foot_sigil):
				_foot_sigil.visible = false
	else:
		aim_slot = -1
		if not _summoner_preview_on:
			_hide_donghuang_w_preview()
			arrow_preview.visible = false
			aoe_fill.visible = false
			impact_ring.visible = false
			cast_range_ring.visible = false
			if _foot_sigil != null and is_instance_valid(_foot_sigil):
				_foot_sigil.visible = false
	# 引导技能释放（键盘/桌面：按住瞄准、松开施放；移动端由下方 consume_skill_release 统一处理）
	if not touch_aiming:
		if any_held and held_index < skills.size():
			if (skill.is_channeling and skill_cast_ready(held_index)) \
					or (held_index < skill_window_timers.size() and skill_window_timers[held_index] > 0):
				channeling_skill_index = held_index
				channeling_preview_pos = target_pos
			else:
				channeling_skill_index = -1
		else:
			if channeling_skill_index != -1:
				if skill_cast_ready(channeling_skill_index):
					_start_casting(channeling_skill_index, skills[channeling_skill_index], channeling_preview_pos)
				channeling_skill_index = -1
	# 移动端：松开施放（王者荣耀式 —— 按住瞄准、松手施放、拖回按钮取消）
	for i in range(3):
		var rel := TouchController.consume_skill_release(i)
		if rel.is_empty():
			continue
		if rel.cancel:
			if channeling_skill_index == i:
				channeling_skill_index = -1
			continue
		if i >= skills.size() or silence_timer > 0:
			continue
		# 太乙Q: 炼药中再按引爆（已在按下时处理，这里跳过避免重复）
		if taiyi_q_channeling and i == 0:
			continue
		# 沈梦溪1技能：按下即开始连发、松开即停 —— 松开不再触发第二次施放
		if display_name == "沈梦溪" and i == 0:
			continue
		# 李白R仅侠客行可用
		if display_name == "李白" and i == 2 and not libai_xia_active:
			continue
		if not skill_cast_ready(i):
			continue
		var cast_pos := _compute_skill_aim(rel.drag, skills[i], false)
		if skills[i].type == 0:
			# 拖拽 → 吸附瞄准点附近目标；点按 → 智能施法自动选优先级目标（英雄最低血优先）
			var pick: GameEntity = null
			if rel.drag.length() > 12.0:
				pick = _pick_skill_target(cast_pos, skills[i].cast_range)
			else:
				# 轻点：朝最近敌人（英雄 > 小兵 > 野怪，忽略防御塔）
				pick = _nearest_skill_target(skills[i].cast_range)
			if pick and not _skill_target_allowed(pick, i):
				pick = null   # 拖拽/点按选到塔但该技能不可点塔 → 丢弃，走自动兜底
			if pick:
				cast_pos = pick.global_position
				pending_skill_target_entity = pick
				# 精准/智能选中后锁定为普攻优先目标（超出普攻范围会自动清空）
				manual_target = pick
		_start_casting(i, skills[i], cast_pos)
	# 触摸按下：进入瞄准（不立即施放，等松开）；太乙Q特例：炼药中再按 → 立即引爆
	for i in range(3):
		if TouchController.consume_skill_press(i):
			# 沈梦溪W：触摸再按引爆（疾跑引燃中）
			if shen_fuse_active and i == 1:
				_shen_w_explode()
				return
			# 沈梦溪1技能（猫咪炸弹）：按下技能轮盘即开始释放——首发立即出，
			# 按住期间每0.75秒一发、实时跟踪轮盘方向；松开 / 弹尽 / 满5发即停
			if display_name == "沈梦溪" and i == 0 and silence_timer <= 0 and skill_cast_ready(0):
				if stat <= 0.0:
					continue
				var cast_pos := _compute_skill_aim(TouchController.get_skill_drag(0), skills[0], false)
				_start_casting(0, skills[0], cast_pos)
			if i < skills.size() and taiyi_q_channeling and i == 0:
				if taiyi_q_timer > 1:
					_taiyi_q_explode()
				return
	# 键盘/桌面：非引导技能按下即施放（瞄准=鼠标位置）
	for i in range(3):
		if Input.is_action_just_pressed("skill_%d" % i) and i < skills.size() and silence_timer <= 0:
			# 沈梦溪W：键盘再按引爆（疾跑引燃中）
			if shen_fuse_active and i == 1:
				_shen_w_explode()
				return
			# 太乙Q: 炼药中再按引爆
			if taiyi_q_channeling and i == 0:
				if taiyi_q_timer>1:
					_taiyi_q_explode()
				return
			# 李白R仅侠客行可用
			if display_name == "李白" and i == 2 and not libai_xia_active: continue
			if (not skills[i].is_channeling and skill_cast_ready(i)) or (i < skill_window_timers.size() and skill_window_timers[i] > 0):
				# 目标型(type0)技能：按键只进入「按住瞄准」态，由 _handle_desktop_type0_aim 松手施放；
				# 引导类/连发窗口类(type0非窗口)不在此列，维持旧即时语义
				if skills[i].type == 0 and not skills[i].is_channeling \
						and (i >= skill_window_timers.size() or skill_window_timers[i] <= 0):
					continue
				_start_casting(i, skills[i], target_pos)
	# 召唤师技能：移动端/鼠标=按住召唤师按钮拖方向（闪现等位移类）、松开施放；桌面=快捷键即时
	var sum_rel := TouchController.consume_summoner_release()
	if not sum_rel.is_empty():
		if not sum_rel.cancel and summoner_skill and summoner_cooldown <= 0:
			_use_summoner(sum_rel.drag)
	if Input.is_action_just_pressed("summoner_spell"):
		_use_summoner()
		# 恢复技能（F键，若未设置其他召唤师技能）
		# 主动装备快捷键
	if item_passive: item_passive.handle_active_input()
	# 兰陵王第4技能(隐身)：桌面快捷键(4) —— 与触控第4技能按钮共用统一入口
	if Input.is_key_pressed(KEY_4):
		_try_cast_lanling_stealth()
	# 触控第4技能按钮：点按(松开即施放、无瞄准方向)；拖到取消键再松开则取消
	TouchController.consume_skill_press(3)
	var rel4 := TouchController.consume_skill_release(3)
	if not rel4.is_empty() and not rel4.cancel:
		_try_cast_lanling_stealth()
	if TouchController.consume_recall_press():
		start_recall()
	if TouchController.consume_recover_press() or Input.is_action_just_pressed("recover"):

		if skill_cooldowns[4] <= 0:
			skill_cooldowns[4] = 60.0
			apply_regen(actual_max_health * 0.01, actual_mana_max * 0.01, 5.0, "recover_skill")
			SfxManager.try_heal_sfx(display_name)

# 桌面目标型(type0)技能：按住技能键(1/2/3)进入瞄准 → 拖动轮盘/鼠标移动 = 调整瞄准方向
# （目标与英雄的相对角度里、方向上最近的敌方单位被锁定为准星高亮）→ 松手施放。
# 点按(≤DT0_TAP_MS)不进入拖拽、直接按鼠标地面智能施法，保留旧「按下即放」手感。
func _handle_desktop_type0_aim():
	if is_ai or health <= 0:
		if _dt0_hold >= 0:
			_dt0_hold = -1
			_dt0_ent = null
			attack_aim_marker.visible = false
		return
	for i in range(3):
		if i >= skills.size() or skills[i] == null or skills[i].type != 0:
			continue
		if skills[i].is_channeling:
			continue
		# 触控链路正在拖这个技能钮：交给触屏逻辑并清掉残留桌面态
		if TouchController.get_skill_held(i):
			if _dt0_hold == i:
				_dt0_hold = -1
				_dt0_ent = null
				attack_aim_marker.visible = false
			continue
		if Input.is_action_just_pressed("skill_%d" % i):
			if silence_timer <= 0 and skill_cast_ready(i) and _dt0_hold == -1:
				_dt0_hold = i
				_dt0_press_ms = Time.get_ticks_msec()
				_dt0_ent = null
				_dt0_pos = Vector3.ZERO
		elif Input.is_action_just_released("skill_%d" % i) and _dt0_hold == i:
			var held_ms := Time.get_ticks_msec() - _dt0_press_ms
			var aim := _dt0_pos
			var lock_ent: GameEntity = _dt0_ent
			var is_tap := held_ms <= DT0_TAP_MS
			_dt0_hold = -1
			_dt0_ent = null
			attack_aim_marker.visible = false
			if is_dead or health <= 0:
				return
			if silence_timer > 0 or not skill_cast_ready(i) or (i < skill_window_timers.size() and skill_window_timers[i] > 0):
				return   # 按住期间被控/进CD/已进入连发窗口 → 放弃本次
			var cast_pos := aim
			pending_skill_target_entity = null
			if lock_ent and is_instance_valid(lock_ent) and lock_ent.health > 0 and _skill_target_allowed(lock_ent, i):
				cast_pos = lock_ent.global_position
				pending_skill_target_entity = lock_ent   # 命中段优先吃该锁定（含防御塔）
			elif is_tap or aim == Vector3.ZERO:
				cast_pos = _compute_skill_aim(Vector2.ZERO, skills[i], false)   # 点按：自动索敌（英雄>小兵>野怪）
			_start_casting(i, skills[i], cast_pos)
	# 按住中：逐帧刷新瞄准落点 + 准星候选
	if _dt0_hold >= 0 and _dt0_hold < skills.size() and skills[_dt0_hold] and skills[_dt0_hold].type == 0:
		if not Input.is_action_pressed("skill_%d" % _dt0_hold):
			_dt0_hold = -1
			_dt0_ent = null
			attack_aim_marker.visible = false
			return
		var sk: Skill = skills[_dt0_hold]
		var tp := _compute_skill_aim(Vector2.ZERO, sk, true)
		var cand := _pick_skill_target(tp, sk.cast_range, SKILL_HOVER_LOCK_RADIUS)
		if cand and not _skill_target_allowed(cand, _dt0_hold):
			cand = null
		_dt0_ent = cand
		_dt0_pos = tp
		if cand:
			attack_aim_marker.global_position = cand.global_position + Vector3(0, 1.2, 0)
			attack_aim_marker.visible = true
		else:
			attack_aim_marker.visible = false

const ATTACK_WHEEL_DRAG_THRESHOLD := 25.0   # 拖过此距离才算「拖动选敌」；点按不改变锁定
const MELEE_AA_RANGE_MAX := 500.0           # 射程 ≤ 此值(单位cm)，普攻走「近战武器挥砍」而非远程弹道
const ATTACK_PICK_RANGE_BONUS := 1.0        # 选敌判定 = 普攻范围 + 该余量
const SKILL_AIM_FULL_DRAG := 400.0          # 技能拖拽达到此距离=最远投放（用于范围技定距）
const SKILL_HOVER_LOCK_RADIUS := 1.2        # 目标型技能悬停吸附半径（离瞄准落点≤该值才锁定）
const DT0_TAP_MS := 180                     # 桌面目标型技能：按住≤该毫秒=点按（退化为智能施法，保持按下即放手感）

# 普攻轮盘（王者荣耀式）：拖动时高亮方向选中的目标，松手锁定为 manual_target（普攻最优先攻击）
func _handle_attack_wheel_input():
	# 拖动瞄准：高亮即将锁定的目标（准星跟随）
	var adrag := TouchController.get_attack_drag()
	if adrag.length() > ATTACK_WHEEL_DRAG_THRESHOLD:
		var cand := _pick_attack_target(adrag, _aa_engage_reach() + ATTACK_PICK_RANGE_BONUS)
		if cand:
			attack_aim_marker.global_position = cand.global_position + Vector3(0, 1.2, 0)
			attack_aim_marker.visible = true
		else:
			attack_aim_marker.visible = false
	else:
		attack_aim_marker.visible = false
	# 松手选敌
	var rel := TouchController.consume_attack_release()
	if rel.is_empty():
		return
	if rel.cancel:
		return   # 拖回按钮：取消本次选敌，保留原锁定
	var drag: Vector2 = rel.drag
	if drag.length() <= ATTACK_WHEEL_DRAG_THRESHOLD:
		return   # 点按：仅普攻当前目标，不改变锁定
	var picked := _pick_attack_target(drag, _aa_engage_reach() + ATTACK_PICK_RANGE_BONUS)
	if picked:
		manual_target = picked
	attack_aim_marker.visible = false

# 推塔/小兵优先级按键（王者荣耀式进阶攻击）：
# 点按切换目标优先级，再按同一键取消（回自动）；点另一个键直接切过去。
# 切换时清除旧锁定让新模式生效；若范围内已有对应类别目标则顺手锁定，英雄站定后即自动持续攻击。
func _handle_attack_priority_input():
	var pressed := TouchController.consume_priority_press()
	if pressed < 0:
		return
	var cur := TouchController.get_attack_priority()
	if pressed == cur:
		TouchController.set_attack_priority(TouchController.ATTACK_PRIORITY_AUTO)
		manual_target = null
		return
	TouchController.set_attack_priority(pressed)
	manual_target = null
	var t := _pick_priority_target(pressed, _aa_engage_reach() + ATTACK_PICK_RANGE_BONUS)
	if t:
		manual_target = t

# ---- P0 施法动作映射：复用 GLB 自带 clip，不新增美术资源 ----
const CAST_ANIM_MELEE := ["吕布", "铠", "亚瑟", "夏侯惇", "孙悟空", "英睿", "李白", "马超", "兰陵王", "不知火舞", "刘禅", "大禹"]
const CAST_ANIM_TWOHAND := ["安琪拉", "妲己", "小乔", "王昭君", "东皇太一", "后羿", "孙尚香", "元流之子", "张飞", "太乙真人", "甄姬", "沈梦溪"]

func _cast_anim_name(skill: Skill, _index: int) -> String:
	if skill == null:
		return "idle"
	if skill.type == 4:
		return "sprint"
	if skill.type == 6:
		return "interact-right"
	# 大招（槽位3）单独一套：近战踢击、双手持械、单手举械，和 1/2 技能区分开
	if _index >= 2:
		if display_name in CAST_ANIM_MELEE:
			return "attack-kick-right"
		if display_name in CAST_ANIM_TWOHAND:
			return "holding-both"
		return "holding-both-shoot"
	# 自身增益（type2 非大招）：近战改用 hold 姿势，避免看起来像在挥刀
	if skill.type == 2:
		if display_name in CAST_ANIM_MELEE:
			return "holding-right"
		if display_name in CAST_ANIM_TWOHAND:
			return "holding-both-shoot"
		return "holding-right-shoot"
	if display_name in CAST_ANIM_MELEE:
		return "attack-melee-right"
	if display_name in CAST_ANIM_TWOHAND:
		return "holding-both-shoot"
	return "holding-right-shoot"

# 普攻动画：远程用持械射击，近战左右挥砍交替（修复远程英雄挥拳的问题）
func _attack_anim() -> void:
	if not is_melee_aa():
		_play_anim("holding-both-shoot" if display_name in ["后羿", "孙尚香", "元流之子"] else "holding-right-shoot")
		NetSession.hero_anim(self, NetSession.ACT_ATTACK_SHOOT)
		return
	_melee_anim_flip = not _melee_anim_flip
	_play_anim("attack-melee-left" if _melee_anim_flip else "attack-melee-right")
	NetSession.hero_anim(self, NetSession.ACT_ATTACK_MELEE)

# 手口位置（施法粒子/枪口闪光的统一出生点）
func _muzzle_pos() -> Vector3:
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	return global_position + Vector3.UP * 1.2 + fwd * 0.65

# 连续施法同一 clip 时强制重播（GameEntity._play_anim 对同 clip 直接 return，不会回时间轴）
func _restart_anim(an: String) -> void:
	if anim_player and anim_player.has_animation(an):
		anim_player.play(an)
		anim_player.seek(0.0)
		current_anim = an

# 施法瞬间：动作 + 脚下蓄力光；大招（槽位3）额外触发本地镜头反馈
func _cast_feedback(skill: Skill, index: int) -> void:
	if skill == null:
		return
	var an := _cast_anim_name(skill, index)
	_restart_anim(an)
	_cast_anim_until = Time.get_ticks_msec() * 0.001 + 0.35   # 收招：0.35s 内移动不覆盖施法动作
	# 联机：施法动作也推给客户端（同一套 clip 名 → 同一套动作档）
	var code := NetSession.ACT_CAST_SHOOT
	match an:
		"sprint": code = NetSession.ACT_CAST_SPRINT
		"interact-right": code = NetSession.ACT_CAST_INTERACT
		"attack-melee-right": code = NetSession.ACT_CAST_MELEE
		"holding-both-shoot": code = NetSession.ACT_CAST_BOTH_SHOOT
	NetSession.hero_anim(self, code)
	# 前摇蓄力：地面三旋法阵 + 内吸能量 + 手中聚能球 + 元素点缀（时长对齐真实前摇）
	var fdir := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	var windup: float = _cast_windup_time(skill)
	var charge_dur: float = maxf(windup, 0.40 if index >= 2 else 0.24)
	Vfx.cast_charge(display_name, global_position, fdir, pending_skill_target, index, charge_dur)
	# 本地玩家施法短音（非本人内部直接忽略；按技能类型/英雄专属分档）
	SfxManager.try_skill_sfx(display_name, index, skill)
	if index == 2 and not is_ai:
		var bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm and bm.hero == self and bm.has_method("on_big_cast"):
			bm.on_big_cast(self)

# ==================== 手感 P0：技能前摇 / 走A ====================
const CAST_WINDUP_BY_TYPE := {0: 0.14, 1: 0.20, 3: 0.16, 4: 0.10, 6: 0.10}
# 专属多段/引导手感英雄：保持即时施放，避免打断其连段窗口逻辑
const CAST_WINDUP_IMMEDIATE_HEROES := ["沈梦溪", "太乙真人", "元流之子", "马超"]
const CAST_WINDUP_MOVE_MULT := 0.55   # 前摇期间移速倍率（乘在当前移速上）

# 技能默认前摇：skill.cast_time>0 优先；增益/多段/引导与豁免英雄保持 0（走原即时路径）
func _cast_windup_time(skill: Skill) -> float:
	if skill == null:
		return 0.0
	if skill.cast_time > 0.0:
		return skill.cast_time
	if skill.is_channeling or skill.type == 2 or skill.type == 5:
		return 0.0
	if display_name in CAST_WINDUP_IMMEDIATE_HEROES:
		return 0.0
	return float(CAST_WINDUP_BY_TYPE.get(skill.type, 0.0))

# 前摇打断：清施法状态 / pending / 预览，不扣蓝不进 CD（资源只在 _finish_casting 结算）
func _cancel_cast_windup() -> void:
	casting_skill = false
	_cast_windup_left = 0.0
	pending_skill_index = -1
	pending_skill_target = Vector3.ZERO
	pending_skill_target_entity = null
	channeling_skill_index = -1
	_dt0_hold = -1
	_dt0_ent = null
	_hide_donghuang_w_preview()
	arrow_preview.visible = false
	aoe_fill.visible = false
	cast_range_ring.visible = false
	attack_aim_marker.visible = false

# 走A：只有「一边移动一边按住普攻」才出手（玩家/远程真人）；没按普攻键 = 纯移动。
# AI 维持原「站定才打」行为；站定时的自动普攻（锁定目标/推塔小兵模式）仍走站定分支，不受影响。
func _try_walk_attack() -> void:
	if is_ai and not net_taken:
		return
	if casting_skill or attack_timer > 0.0:
		return
	if display_name == "铠" and int(stat) == 1:
		return   # 铠强化普攻突进由站定分支处理
	if display_name == "马超" and stat_timer > 0.0:
		return   # 马超拾枪突进由站定分支处理
	var can_act := stun_timer <= 0 and knockup_timer <= 0 and suppress_timer <= 0 and silence_timer <= 0
	if not can_act:
		return
	var atk_held := Input.is_action_pressed("ui_accept") or TouchController.get_attack_held() or net_attack_hold
	if not atk_held:
		return
	var target: GameEntity = _get_attack_target()
	if target == null or target.health <= 0:
		return
	if is_recalling: cancel_recall()
	_perform_attack(target)
	attack_timer = 1.0 / attack_speed

func _start_casting(index: int, skill: Skill, target_pos: Vector3):
	aim_slot = -1   # 松手施放：小地图瞄准线立即消失
	# AI 回城引导中禁止施法（玩家施法/移动会取消回城，AI 直接不允许动作）
	if is_ai and is_recalling:
		return
	# 前摇期间重复按技能键忽略（不重置 pending / 不叠加前摇）
	if casting_skill and _cast_windup_left > 0.0:
		return
	# 存储型技能守卫（所有调用入口，含 AI/触屏/键盘，与 can_cast_skill 同规则）：
	# 无已存层数不放，避免白耗
	if skill and skill.restore > 0.0 and index < skill_restores.size() and skill_restores[index] <= 0:
		return
	# 英雄前置状态门槛统一守卫（李白大招侠客行 / 沈梦溪1、2需炸弹 / 马超R需枪 /
	# 东皇2需能量球 / 兰陵王大招需隐身）——与按钮 blocked 同源，各入口（含 AI 连招）一致拦截
	if index >= 0 and index < skills.size() and skills[index] and skill_prereq_blocked(index):
		return
	casting_skill = true
	_cast_windup_left = _cast_windup_time(skill)
	pending_skill_index = index

	pending_skill_target = target_pos
	# 目标型技能保留调用方已锁定的实体（触屏拖拽/桌面悬停/联机 C_CAST 写入）；非目标型清空防串台。
	# 到期由 _finish_casting 尾部统一复位。
	if skill == null or skill.type != 0:
		pending_skill_target_entity = null
	_cast_feedback(skill, index)

# 太乙真人 Q 技能引爆（委托给 HeroPassive）
func _taiyi_q_explode():
	if hero_passive: hero_passive._taiyi_q_explode()
# 沈梦溪 W 疾跑引爆（委托给 HeroPassive）
func _shen_w_explode():
	if hero_passive: hero_passive._shen_w_explode()



# 兰陵王第4技能(隐身, 技能槽3)统一施放入口：桌面 KEY_4 与触控第4技能按钮共用。
# 命中即设冷却(取技能表 cooldown)并进入施放管线，防止按住/重复触发；语义与历史快捷键一致。
func _try_cast_lanling_stealth() -> bool:
	if display_name != "兰陵王":
		return false
	if casting_skill:
		return false   # 前摇中忽略，避免先扣 CD 再被 _start_casting 拦截
	if skills.size() <= 3 or not skills[3] or skill_cooldowns.size() <= 3 or skill_cooldowns[3] > 0:
		return false
	skill_cooldowns[3] = skills[3].cooldown
	_start_casting(3, skills[3], global_position)
	return true

func _apply_ak_sp_buff(flat_bonus: float, duration: float):
	active_buffs.append({"timer": duration, "bonus_attack_speed": flat_bonus})
	_recalculate_attributes()

# 攻距 buff 通用写入：同 tag 刷新时长/数值，否则追加（值经 _calculate_buff 聚合进 bonus_attack_range，
# 再由 _recalculate_attributes 派生到 attack_range；到期条目被 _process 移除时自动还原）。
func apply_attack_range_buff(tag: String, duration: float, flat: float) -> void:
	for b in active_buffs:
		if b.get("_tag", "") == tag:
			b["timer"] = duration
			b["bonus_attack_range"] = flat
			_recalculate_attributes()
			return
	active_buffs.append({"_tag": tag, "timer": duration, "bonus_attack_range": flat})
	_recalculate_attributes()

# 逐日弓/日渊：把攻击距离的永久倍率作用在攻距底值上（保持既有数值语义，同时不污染派生公式）
func multiply_attack_range_base(ratio: float) -> void:
	if _range_base < 0.0:
		_range_base = attack_range - bonus_attack_range
	_range_base *= ratio
	attack_range = _range_base + bonus_attack_range
	_update_attack_range_ring()



func _finish_casting():
	if not casting_skill: return
	casting_skill = false
	HeroWeapons.play(visual_mesh, "cast")   # 武器施法动作
	dash_from = global_position   # 记录本次施放起点（位移类技能/燃痕回读）
	if pending_skill_index < 0 or pending_skill_index >= skills.size(): return
	# 大招（3 技能）语音台词：只播屏幕内、音量按距离衰减（ChatService 判定）
	if pending_skill_index == 2:
		var _cs_voice = get_tree().get_root().get_node_or_null("ChatService")
		if _cs_voice != null:
			_cs_voice.call("hero_voice_ult", display_name, global_position)
	var skill = skills[pending_skill_index].duplicate()
	if skill_restores[pending_skill_index]>0:
		skill_restores[pending_skill_index]-=1
	skill.cooldown = skill.cooldown - skill.cd_bonus*(skill_levels[pending_skill_index] - 1)
	skill.mana_cost = skill.mana_cost - skill.power_bonus*(skill_levels[pending_skill_index] - 1)
	
	# 调试：技能释放信息
	var _dbg_sk_lv = skill_levels[pending_skill_index]
	var _dbg_bm3 = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var _dbg_gt2 = _dbg_bm3.game_time if _dbg_bm3 else 0.0
	print("[SKILL t=", "%.1f" % _dbg_gt2, "] ", display_name, " casts ", skill.skill_name, "(", pending_skill_index+1, ") Lv", _dbg_sk_lv, " CD=", skill.cooldown, " cost=", skill.mana_cost)
	_debug_skill_info = " | " + skill.skill_name + "(" + str(pending_skill_index+1) + ") Lv" + str(_dbg_sk_lv)
	if skill_window_timers[pending_skill_index] <= 0:
		mana -= skill.mana_cost
		# 元流之子·流连发：冷却未走完却获准施放 = 消耗"流"换额外释放
		# （skill_cast_ready 已按 破釜≥4/万箭≥5 放行；此处回读冷却本就在转判定为连发）
		if display_name == "元流之子" and pending_skill_index == 1 and skill_cooldowns[1] > 0.0 and yuanliu_flow >= 4:
			yuanliu_flow -= 4
			yuanliu_flow_activity()   # 连发消耗「流」→ 重置5秒闲置窗口
			if yuanliu_w_window <= 0.0:
				yuanliu_w_phase = 0
			yuanliu_w_phase = mini(yuanliu_w_phase + 1, 2)
			yuanliu_w_window = 2.0
			# 凌空段：第二段参连之后的第三段 → 上抬+无法选中近似
			if yuanliu_w_phase >= 2:
				yuanliu_float = 0.7
				wd_timer = maxf(wd_timer, 0.6)
		elif display_name == "元流之子" and pending_skill_index == 2 and skill_cooldowns[2] > 0.0 and yuanliu_flow >= 5:
			yuanliu_flow -= 5
			yuanliu_flow_activity()   # 连发消耗「流」→ 重置5秒闲置窗口
			yuanliu_float = 0.7
			wd_timer = maxf(wd_timer, 0.6)
		elif display_name == "元流之子" and pending_skill_index == 1:
			# 破釜首发：启动 2 秒连发窗口（未消耗流，阶段归零）
			yuanliu_w_window = 2.0
			if yuanliu_w_phase != 0:
				yuanliu_w_phase = 0
		# 存储型技能（restore>0）：CD 只是「下一层回充」计时，层数用完后才开始转；
		# 已在回充中则继续计时，不要每次施放都重置为满 CD（否则多段存储无法连放）
		if skill.restore > 0:
			if skill_restores[pending_skill_index] < skill.restore and skill_cooldowns[pending_skill_index] <= 0:
				skill_cooldowns[pending_skill_index] = skill.cooldown
		else:
			skill_cooldowns[pending_skill_index] = skill.cooldown
	# 元流之子·破釜之箭：施放瞬间沿摇杆/移动方向小位移 2.5m（站定/无方向则不滑；位移与巨箭瞄准方向解耦）
	if display_name == "元流之子" and pending_skill_index == 1:
		var yl_dash_dir := last_move_dir
		if yl_dash_dir.length() > 0.1:
			var yl_end: Vector3 = global_position + yl_dash_dir.normalized() * 2.5
			yl_end.y = 0.5
			dash_move_to(yl_end, 0.14, "sprint")
	#print(pending_skill_index)
	var pos = pending_skill_target
	# 右下角索敌头像锁定：锁定目标在施法范围内时，普攻与技能统一以此为目标/落点
	# （增益/位移/护盾类不吃锁定，避免把保命技能甩到敌人身上）
	if manual_target and is_instance_valid(manual_target) and manual_target.health > 0 \
			and manual_target is GameEntity and skill.type != 2 and skill.type != 4 and skill.type != 6 \
			and not (is_ai and display_name == "鲁班七号" and pending_skill_index == 1):
		# AI鲁班2技能是全图狙击：绝不能被同帧近身锁定的 manual_target 改写瞄准落点
		var _lk_dist: float = global_position.distance_to(manual_target.global_position)
		if _lk_dist <= maxf(skill.cast_range, attack_range * 0.01) + manual_target.body_radius + 2.0:
			pos = manual_target.global_position
	# P0/P1：技能真正出手表现（签名大招查 SpellFxTable，其余走通用元素爆发；伤害时序不变）
	var _cast_fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	Vfx.play_spell(display_name, pending_skill_index, global_position + Vector3.UP * 1.2 + _cast_fwd * 0.65, pos, skill, _cast_fwd, not is_ai)
	# 定制皮肤：额外叠一层皮肤强调色技能爆发，让技能特效明显换色
	if skin_is_custom():
		Vfx.skin_spell_burst(global_position + Vector3.UP * 1.2 + _cast_fwd * 0.65, skin_accent_color())	
	var _replay_rec = get_tree().get_first_node_in_group("replay_recorder")
	if _replay_rec != null:
		_replay_rec.call("note_cast", display_name, pending_skill_index,
			global_position + Vector3.UP * 1.2 + _cast_fwd * 0.65, pos, _cast_fwd, skill, int(team))
	var _tbm3 = get_tree().get_first_node_in_group("battle_manager")
	if _tbm3 != null and _tbm3.has_method("test_hero_action"):
		_tbm3.call("test_hero_action", self, "skill", pending_skill_index)
	match skill.type:
		0:
			# 优先使用瞄准时选中的目标（拖拽吸附 / 悬停锁定 / 联机 C_CAST 传入实体）；
			# 否则对当前瞄准落点做小半径悬停吸附；仍无再智能施法（英雄低血优先，不应用推塔/小兵模式）
			var target: GameEntity = null
			if pending_skill_target_entity and is_instance_valid(pending_skill_target_entity) \
					and pending_skill_target_entity.health > 0 and _skill_target_allowed(pending_skill_target_entity):
				target = pending_skill_target_entity
			elif not is_ai and pos != Vector3.ZERO:
				var hover := _pick_skill_target(pos, skill.cast_range, SKILL_HOVER_LOCK_RADIUS)
				if hover and _skill_target_allowed(hover):
					target = hover
					pending_skill_target_entity = hover   # 供 _lyf_q 命中段读回已锁实体
			if target == null:
				target = _get_attack_target(skill.cast_range, false)
			if target:
				pos = target.global_position
				pending_skill_target_entity = target
			else:
				pos = Vector3.ZERO
				
		4:  # 位移：几帧内快速滑到落点 + 冲刺动作（不再瞬移）
			
			var dir = (pos - global_position).normalized()
			if dir.length() < 0.1: dir = Vector3.FORWARD
			# 位移距离：优先 self_displacement；标成 cast_range 的技能（如夏侯惇大招）用它兜底，
			# 否则 AI/玩家放出来会原地不动（预览圈却显示有位移距离）
			var disp_len: float = skill.self_displacement if skill.self_displacement > 0.0 else skill.cast_range
			# 落点做墙面修正：dash_move_to 是 Tween 直接改坐标、不受碰撞约束，
			# 不修正会直接穿墙/卡在墙里（AI 追击、逃跑尤其明显）
			var dash_end: Vector3 = clamp_dash_landing(dir, disp_len)
			dash_end.y = 0.5
			dash_move_to(dash_end, 0.16, "sprint")
		6:  # 护盾
			shield_remaining = max(shield_remaining, skill.shield_amount)
			shield_timer = skill.duration
	# 旭日初光：对英雄造成伤害→护盾(10s CD)
	if equipment_slots.has("rising_sun") and rising_sun_cd <= 0 and pos != Vector3.ZERO:
		var target_hero = _get_nearest_enemy_in_range(attack_range * 0.01)
		if target_hero:
			rising_sun_cd = 10.0
			var rs_shield = 250 + level * 16 + actual_max_health * 0.04
			var lowest_ally = null; var lowest_hp = 99999.0
			for ent in get_tree().get_nodes_in_group("heroes"):
				if ent != self and ent.team == team and ent.health > 0:
					if global_position.distance_to(ent.global_position) <= 3.5:
						if ent.health < lowest_hp:
							lowest_hp = ent.health; lowest_ally = ent
			if lowest_ally:
				lowest_ally.shield_remaining = max(lowest_ally.shield_remaining, rs_shield)
				lowest_ally.shield_timer = 3.0
			else:
				rs_shield *= 1.5
			shield_remaining = max(shield_remaining, rs_shield)
			shield_timer = 3.0
	# 回响之杖：技能命中后爆炸(100码, 5s CD)
	if equipment_slots.has("echo_staff") and echo_staff_cd <= 0:
		echo_staff_cd = 5.0
		var echo_dmg = 140 + level * 9.3 + actual_ability_power * 0.28
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or ent.health <= 0 or ent.team == team: continue
			if ent.global_position.distance_to(pos) <= 1:
				ent.take_damage(echo_dmg, self, true, -27, 0)
		# 视觉效果
		var expl = MeshFactory.create_sphere(1.5, Color.ORANGE, true, 0.5)
		expl.position = pos + Vector3.UP * 1.5
		get_parent().add_child(expl)
		var tw2 = create_tween()
		tw2.tween_property(expl, "scale", Vector3(2,2,2), 0.4)
		tw2.parallel().tween_property(expl.material_override, "albedo_color:a", 0.0, 0.4)
		tw2.tween_callback(expl.queue_free)
	# 痛苦面具：技能命中3秒内4次3%当前生命法伤(3s CD)
	if equipment_slots.has("pain_mask") and pain_mask_cd <= 0 and pos != Vector3.ZERO:
		pain_mask_cd = 3.0
		var pm_target = _get_nearest_enemy_in_range(attack_range * 0.01)
		if pm_target:
			for _k in range(4):
				if not pm_target:break
				var pm_dmg = pm_target.health * 0.03
				if pm_target is JungleMonster:
					pm_dmg = min(pm_dmg, 200)
				pm_target.take_damage(pm_dmg, self, true, -28, 0)
				await get_tree().create_timer(0.75).timeout
	# 冰痕之握：技能后下次普攻额外伤害+减速(1.25s CD)
	if equipment_slots.has("ice_fist") and ice_fist_cd <= 0:
		ice_fist_buff = true
	# 巫术法杖：技能后下次普攻额外法伤
	if equipment_slots.has("witch_staff") and witch_staff_cd <= 0:
		witch_staff_buff = true
	# 凝冰之息：技能命中减速+法伤(3s CD)
	if equipment_slots.has("frost_breath") and frost_breath_cd <= 0:
		frost_breath_cd = 3.0
		var fb_target = _get_nearest_enemy_in_range(attack_range * 0.01)
		if fb_target:
			fb_target.apply_move_pct_buff("ms_slow", 1.5, -(0.05 + level * 0.0005), true)
			var fb_dmg = 75 + level * 5 + actual_ability_power * 0.15
			fb_target.take_damage(fb_dmg, self, true, pending_skill_index+1, 0)
	skillapply.apply_skills(self,pending_skill_index+1,pos)

	# 王昭君大招刷新护盾：旧盾破裂→冰霜冲击→刷新满盾
	if display_name == "王昭君" and pending_skill_index == 2:
		if wangzhaojun_shield_was_active and shield_remaining > 0:
			var sk_lv = level
			var burst_dmg = int(372 + 26.7 * sk_lv) + actual_ability_power * 0.75
			var slow_pct = int(18.3 + 1.8 * level)
			var slow_dur = 2.0
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent != self and ent.health > 0 and ent.team != team:
					if global_position.distance_to(ent.global_position) <= 4.0:
						ent.take_damage(burst_dmg, self, true, -51, 0)
						ent.apply_move_pct_buff("ms_slow", slow_dur, -slow_pct, true)
						ent.apply_attack_pct_buff("as_slow", slow_dur, -slow_pct, true)
			
		var shield_val =  450.0 +level* 30.0 + actual_ability_power * 0.58
		shield_remaining = shield_val
		wangzhaojun_shield_was_active = true
	# 张飞变身后技能减速
	if display_name == "张飞" and zhangfei_transformed:
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent != self and ent.health > 0 and ent.team != team:
				if global_position.distance_to(ent.global_position) <= 3.5:
					ent.apply_move_pct_buff("ms_slow", 2.0, -(0.25 + level * 0.0167), true)
	# === 技能触发装备被动 ===
	var st = _get_nearest_enemy_in_range(attack_range * 0.01)
	if st:
		# 闪电匕首：技能附加法伤
		OnHitProcessor.apply_lightning_knife_skill(self, st)
		# 逐风叠层
		OnHitProcessor.apply_chase_wind(self)
		# 金色圣剑叠层
		if equipment_slots.has("gold_saint_sword"): OnHitProcessor.apply_gold_saint_sword(self, st, true)
		# 末世
		# 寒霜袭侵：减速+额外伤害
		OnHitProcessor.apply_frost_assault(self, st)
		# 制裁/梦魇：重伤效果
		OnHitProcessor.apply_grievous_wounds(self, st)
	# 打野刀狩猎：技能命中触发DoT(1/4伤害)（对防御塔无效）
	var jg_st = _get_nearest_enemy_in_range(attack_range * 0.01)
	if jg_st and not (jg_st is Turret):
		OnHitProcessor.apply_jungle_hunt(self, jg_st, true)
	# 纯净苍穹：技能命中首个敌人减速+减伤
	if equipment_slots.has("purify") and purify_cd <= 0:
		var target = _get_nearest_enemy_in_range(attack_range * 0.01)
		if target:
			target.apply_move_pct_buff("ms_slow", 3.0, -(0.1 + level * 0.001), true)
			purify_cd = 8.0
	# 宗师之力：技能后加速+强化下次普攻
	if equipment_slots.has("sage_power"):
		sage_power_buff = true
		sage_power_timer = 5.0
		apply_move_pct_buff("ms_haste", 2.0, 0.12)
	pending_skill_index = -1
	pending_skill_target = Vector3.ZERO
	pending_skill_target_entity = null
	if display_name == "不知火舞":
		apply_move_pct_buff("ms_haste", 1, 0.5)
	if display_name == "马超":
		# 马超技能后（投掷枪后）也获得 +5 数值移速（5秒）
		apply_flat_move_buff("machao_speed", 5.0, 4.7+0.45*level)
## aim_dir：本地输入传屏幕拖拽（x右/y下），按本机镜头朝向换算；
## world_dir=true 表示调用方已换算成世界方向（联机客户端 C_SUMMONER 传的就是世界方向）
func _use_summoner(aim_dir: Vector2 = Vector2.ZERO, world_dir: bool = false):
	if not summoner_skill or summoner_cooldown > 0: return
	# AI 回城引导中禁止使用召唤师技能
	if is_ai and is_recalling: return
	var cd = summoner_skill.cooldown
	if equipment_slots.has("cd_boots"):
		cd /= (1.0 + 0.10 + level * 0.007)
	match summoner_skill.skill_name:
		"闪现":
			# 方向：优先召唤师按钮拖拽轮盘；其次当前移动方向（摇杆/键鼠）；兜底面朝
			var _flash_from := global_position
			var _flash_dir: Vector3 = _resolve_flash_dir(aim_dir)
			if world_dir and aim_dir.length() > 20.0:
				_flash_dir = Vector3(aim_dir.x, 0.0, aim_dir.y).normalized()
			var _flash_to := clamp_dash_landing(_flash_dir, 5.0)
			_flash_to.y = 0.5
			Vfx.cast_burst(display_name, _flash_from + Vector3.UP * 1.0, Vector3.UP, 0.7)
			Vfx.cast_burst(display_name, _flash_to + Vector3.UP * 1.0, Vector3.UP, 0.8)
			# 5 米在 6~8 帧内滑过去（仍是闪现手感，但不是「啪」地瞬移）
			Vfx.dash_fx(_flash_from, _flash_to, Vfx.color_for_hero(display_name), not is_ai, 5.0)
			dash_move_to(_flash_to, 0.11, "jump")
			Vfx.camera_shake(0.04, 0.16)
		"疾跑":
			_cleanse()
			apply_move_pct_buff("ms_haste", 10.0, 0.3); 
			Vfx.cast_glow(global_position, Color(0.45, 1.0, 0.65), 1.3, 0.8)
		"传送":
			# 进入传送瞄准模式：在小地图点击己方防御塔或小兵传送
			Vfx.cast_glow(global_position, Color(0.55, 0.85, 1.0), 1.2, 0.6)
			var mm = get_tree().get_first_node_in_group("battle_manager").minimap
			mm.summoner_teleport = true
			mm.enter_teleport_mode()
		"治疗术":
			_apply_healing(actual_max_health * 0.15)
			apply_move_pct_buff("ms_haste", 2.0, 0.15)
			Vfx.cast_glow(global_position, Color(0.4, 1.0, 0.5), 1.5, 0.8)
			SfxManager.try_heal_sfx(display_name)
			for ent in get_tree().get_nodes_in_group("heroes"):
				if ent != self and ent.team == team and global_position.distance_to(ent.global_position) <= 3.0:
					ent._apply_healing(ent.actual_max_health * 0.15)
					Vfx.cast_glow(ent.global_position, Color(0.45, 1.0, 0.55), 0.8, 0.6)
		"终结":
			var target = _get_nearest_enemy_in_range(5.0)
			if target and target is Hero:
				var missing_hp = target.actual_max_health - target.health
				var td = missing_hp * 0.16
				target.take_damage(td, self, false, -49, 1.0)
				Vfx.beam(_muzzle_pos(), target.global_position + Vector3.UP * 1.2, Color(1.0, 0.35, 0.3), 0.22, 0.3)
				Vfx.shockwave(target.global_position, 1.6, Color(1.0, 0.3, 0.25), 0.4)
				if target.health <= 0: cd *= 0.1
		"狂暴":
			active_buffs.append({"timer": 7.0, "bonus_attack": 0, "frenzy_dmg": 0.10, "frenzy_toughness": 0.25, "frenzy_phys_ls": 0.20, "frenzy_mag_ls": 0.30})
			_recalculate_attributes()
			Vfx.cast_glow(global_position, Color(1.0, 0.32, 0.22), 1.3, 0.9)
		"晕眩":
			Vfx.shockwave(global_position, 5.0, Color(1.0, 0.82, 0.35), 0.5)
			Vfx.camera_shake(0.08, 0.25)
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent != self and ent.health > 0 and ent.team != team:
					if global_position.distance_to(ent.global_position) <= 5.0:
						ent.stun_timer = 0.75; ent.apply_move_pct_buff("ms_slow", 1.0, -0.3, true)
						_cc_burst(ent)
		"净化":
			_cleanse(); bt_timer = 0; wd_timer = 0; stun_timer = 0
			slow_timer = 0; knockup_timer = 0; froze_timer = 0; bt_timer = 1.5
			Vfx.shockwave(global_position, 1.8, Color(0.55, 0.95, 1.0), 0.45)
		"弱化":
			Vfx.shockwave(global_position, 5.0, Color(0.55, 0.3, 0.85), 0.55)
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent != self and ent.health > 0 and ent.team != team:
					if global_position.distance_to(ent.global_position) <= 5.0:
						ent._apply_ak_buff(0, -0.3, 4.0, false)
			_apply_df_buff(0, 0.3, 4.0, false); _apply_df_buff(0, 0.3, 4.0, true)
		"惩击":
			var target2 = _get_nearest_enemy_in_range(3.0)
			if target2:
				var sd = 1500 + level * 100
				Vfx.beam(global_position + Vector3.UP * 1.5, target2.global_position + Vector3.UP * 0.8, Color(0.7, 0.6, 1.0), 0.20, 0.3)
				Vfx.hit_spark(target2.global_position + Vector3.UP * 1.0, Color(0.8, 0.7, 1.0), Vector3.UP, 1.2)
				if target2 is JungleMonster: target2.take_damage(sd, self, false, -50, 1.0)
				else: target2.take_damage(sd * 0.25, self, false, -50, 1.0)
				target2.apply_move_pct_buff("ms_slow", 2.0, -0.3, true)
	summoner_cooldown = cd

# 闪现方向解析。aim_dir = 召唤师按钮拖拽向量（屏幕 x右+/y下+，与技能拖拽一致）。
# 优先级：①召唤师轮盘拖拽 → ②当前移动方向（摇杆/键鼠）→ ③面朝方向兜底
func _resolve_flash_dir(aim_dir: Vector2) -> Vector3:
	# 红方镜头绕 Y 轴转 180°：屏幕方向整体取反，保持与蓝方同一手感（否则闪现会朝反方向）
	var cam_flip := -1.0 if Config.player_team == Config.Team.ENEMY else 1.0
	if aim_dir.length() > 20.0:
		# 屏幕拖拽 → 用当前镜头反投影成世界方向：不依赖阵营常量，红蓝方/任意镜头都正确
		return _drag_to_world_dir(aim_dir)
	# 轻点闪现：智能寻敌 → 朝锁定目标/最近敌方英雄方向
	if PlayerPrefs.opt_int("flash_dir", 0) == 1:
		var tgt: GameEntity = null
		if manual_target and is_instance_valid(manual_target) and manual_target.health > 0:
			tgt = manual_target
		else:
			var best_d := 8.0
			for e in get_tree().get_nodes_in_group("heroes"):
				if e is Hero and e != self and e.team != team and e.health > 0 and not (e as Hero).is_invisible_to_enemy():
					var d: float = global_position.distance_to(e.global_position)
					if d < best_d:
						best_d = d
						tgt = e
		if tgt != null:
			var to_t: Vector3 = tgt.global_position - global_position
			to_t.y = 0.0
			if to_t.length() > 0.2:
				return to_t.normalized()
	var jv := TouchController.get_move_vector()
	if jv.length() > 0.1:
		return Vector3(jv.x * cam_flip, 0, -jv.y * cam_flip).normalized()
	if not is_ai:
		var kx := Input.get_axis("ui_left", "ui_right")
		var kz := Input.get_axis("ui_down", "ui_up")   # W=+1
		if TouchController.get_move_mode() == TouchController.MOVE_MODE_DIR:
			# 前后左右模式：按键即屏幕方向
			if absf(kx) > 0.1 or absf(kz) > 0.1:
				return Vector3(kx * cam_flip, 0, -kz * cam_flip).normalized()
		elif absf(kz) > 0.1:
			# 转向模式：前后沿面朝方向
			return Vector3(sin(rotation.y), 0, cos(rotation.y)) * signf(kz)
	return Vector3(sin(rotation.y), 0, cos(rotation.y))
## 屏幕拖拽（x 右 / y 下）→ 世界地面方向：用当前镜头把屏幕点反投影到地面
func _drag_to_world_dir(drag: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null or drag.length() < 0.01:
		return Vector3(sin(rotation.y), 0, cos(rotation.y))
	var sc := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
	var wp := _screen_ray_world(sc)
	var d := wp - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3(sin(rotation.y), 0, cos(rotation.y))
	return d.normalized()


func _get_nearest_enemy_in_range(range: float) -> GameEntity:
	var best: GameEntity = null
	var best_dist = range + 1.0
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity.health <= 0 or entity.team == team: continue
		var dist = global_position.distance_to(entity.global_position)
		if dist <= range and dist < best_dist:
			best_dist = dist
			best = entity
	return best

func _cleanse():
	remove_cc_speed_buffs(); stun_timer = 0; knockup_timer = 0
# ---------- 属性成长 ----------
# 经验表：1-15级所需升级经验（累计总经验仅参考，不需要）
const EXP_TABLE = [0, 162, 296, 446, 526, 611, 713, 826, 952, 1085, 1246, 1400, 1589, 1778, 2000]

func add_exp(amount: int):
	exp += amount
	while level < 15 and exp >= exp_to_next:
		exp -= exp_to_next
		if level <14:
			exp_to_next = EXP_TABLE[level+1]
		else:exp_to_next = 2000
		level_up()
# 该技能当前是否可升级（与 upgrade_skill 的成功条件一致，供 UI 显示“可升级”提示）
func can_upgrade_skill(slot: int) -> bool:
	if slot < 0 or slot >= skills.size():
		return false
	if skill_points <= 0:
		return false
	if slot < 2:
		return skill_levels[slot] < SKILL_MAX_LEVEL
	if slot == 2:
		# 大招：升至第 N 级需要英雄达到指定等级（1→4级、2→8级、3→12级）
		var next_lv = skill_levels[slot] + 1
		return skill_levels[slot] < ULTIMATE_MAX_LEVEL \
			and next_lv < ULTIMATE_REQUIRED_LEVEL.size() \
			and level >= ULTIMATE_REQUIRED_LEVEL[next_lv]
	return false

func upgrade_skill(slot: int) -> bool:
	if not can_upgrade_skill(slot):
		return false
	skill_levels[slot] += 1
	skills[slot].restore+=skills[slot].restore_bonus
	skill_points -= 1
	_recalculate_attributes()   # 技能等级影响被动（如铠永久移速）→ 重算同步
	return true
# 第4技能（兰陵王·隐匿等真实第4技能槽）：统一在英雄 4 级自动解锁；
# 固定 1 级、不消耗技能点、不需要“+”升级钮（与其他 1/2/3 技能的手动升级区分）。
func _check_fourth_skill_unlock() -> void:
	if level < 4 or skills.size() <= 3 or skill_levels.size() <= 3:
		return
	if skills[3] == null or skill_levels[3] >= 1:
		return
	skill_levels[3] = 1
	_recalculate_attributes()

func level_up():
	skill_points+=1
	level += 1
	_check_fourth_skill_unlock()
	# 时之预言：升级后3秒内回复20%生命和法力
	if equipment_slots.has("prophecy_of_time"):
		apply_regen(actual_max_health * 0.2 / 3.0, actual_mana_max * 0.2 / 3.0, 3.0, "prophecy")
		last_level = level
	
	_apply_healing(base_health * 0.2)
	mana = min(mana + base_mana * 0.2, actual_mana_max)
	_recalculate_attributes()
	# 本地玩家升级短音
	SfxManager.try_levelup_sfx(display_name)
var bonus_attack_speed: float = 0.0   # 来自装备的攻速百分比加成
var bonus_attack_range: float = 0.0   # 攻击距离加成（Q 等 buff 聚合，派生进 attack_range）
var _range_base: float = -1.0         # 攻距底值：首次重算懒捕获；逐日弓的×倍乘作用于底值

# ---- 属性来源拆分（供左侧属性面板：基础 + 装备 + Buff）----
var equip_snapshot: Dictionary = {}   # _snapshot_equip_stats() 在计算 Buff 前记录“装备”分量
var stat_breakdown: Dictionary = {}   # 每个属性存 [基础, 装备, Buff] 三段（_update_stat_breakdown 填充）

func _calculate_buff():
	
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i]["timer"] > 0:
			bonus_attack += active_buffs[i].get("bonus_attack",0)
			bonus_ability_power += active_buffs[i].get("bonus_ability_power",0)
			bonus_armor += active_buffs[i].get("bonus_armor_resist",0)
			bonus_magic_resist += active_buffs[i].get("bonus_magic_resist",0)
			bonus_attack_speed += active_buffs[i].get("bonus_attack_speed",0)
			bonus_attack_speed_pct += active_buffs[i].get("attack_speed_pct",0)
			bonus_attack_range += active_buffs[i].get("bonus_attack_range",0)
			bonus_toughness += active_buffs[i].get("frenzy_toughness",0)
			bonus_phys_lifesteal += active_buffs[i].get("frenzy_phys_ls",0)
			bonus_magic_lifesteal += active_buffs[i].get("frenzy_mag_ls",0)
			bonus_move_speed += active_buffs[i].get("bonus_move_speed",0)
			bonus_move_speed_pct += _entry_move_pct(active_buffs[i])
			if active_buffs[i].get("frenzy_dmg",0) > 0: bonus_attack *= (1.0 + active_buffs[i].get("frenzy_dmg",0))
	# 英睿被动：冰爽层数双抗（每层 +8护甲 +5魔抗）
	if display_name == "英睿" and yingrui_stacks > 0:
		bonus_armor += 8.0 * yingrui_stacks
		bonus_magic_resist += 5.0 * yingrui_stacks

# —— 被动效果统一成 active_buffs 计时条目 ——
# 叠层/侠客行/永久被动原本在 _recalculate_attributes 末尾直接乘算，现改由本函数按当前状态
# 把数值写进带 _tag 的 buff 条目（在 _calculate_buff 之前调用，随后统一聚合），数值与原来逐字一致。
func _sync_passive_buffs():
	if display_name == "狄仁杰":
		var dur := _passive_stack_remaining()
		_sync_tagged_entry("direnjie_ms", stat > 0,
			{"move_speed_pct": 0.05 * stat, "timer": dur, "cc": false})
		_sync_tagged_entry("direnjie_as", stat > 0,
			{"attack_speed_pct": stat * (3.25 + 0.25 * level) / 100.0, "timer": dur, "cc": false})
	elif display_name == "后羿":
		_sync_tagged_entry("houyi_as", stat > 0,
			{"attack_speed_pct": stat * 0.02, "timer": _passive_stack_remaining(), "cc": false})
	elif display_name == "李白":
		_sync_tagged_entry("libai_xia_ad", libai_xia_active,
			{"bonus_attack": 28.0+2.0*level, "timer": maxf(libai_xia_timer, 0.05)})
	elif display_name == "铠" and skill_levels.size() > 1:
		# 永久移速：随2技能等级成长（升级经 upgrade_skill 触发重算刷新）
		_sync_tagged_entry("kai_passive_ms", true,
			{"bonus_move_speed": 8.0 + 2.0 * skill_levels[1], "timer": 9999.0})
	elif display_name == "元流之子":
		# 万物为流：攻速 +10~20%（随等级）；四选一选择分支也随等级成长
		var _yl_t := minf((level - 1) / 14.0, 1.0)
		_sync_tagged_entry("yuanliu_as", true,
			{"attack_speed_pct": 0.10 + 0.10 * _yl_t, "timer": 9999.0, "cc": false})
		if yuanliu_pick == "穿心":
			_sync_tagged_entry("yuanliu_choice", true,
				{"bonus_attack": 30.0 + 30.0 * _yl_t, "timer": 9999.0})
		elif yuanliu_pick == "迅疾":
			_sync_tagged_entry("yuanliu_choice", true,
				{"bonus_move_speed": 12.5 + 12.5 * _yl_t, "timer": 9999.0})
		else:
			# 生机/凝神走 _recalculate_attributes 特判（HP/CDR 不在 buff 聚合键表内）
			_sync_tagged_entry("yuanliu_choice", false, {})

# 叠层被动（狄仁杰/后羿）距全部层数衰减完的剩余时间：stat_timer 到期后每 0.5s 掉一层
func _passive_stack_remaining() -> float:
	if stat <= 0:
		return 0.0
	return maxf(stat_timer + (stat - 1) * 0.5, 0.05)

# 无递归的 tag 条目写入：仅在 _recalculate_attributes 内部使用——写入后由紧随其后的
# _calculate_buff() 聚合，自身不再触发重算（避免与重算互为递归）。
func _sync_tagged_entry(tag: String, active: bool, fields: Dictionary):
	for i in range(active_buffs.size()):
		if active_buffs[i].get("_tag", "") == tag:
			if not active:
				active_buffs.remove_at(i)
				return
			for k in fields:
				active_buffs[i][k] = fields[k]
			return
	if active:
		var entry: Dictionary = fields.duplicate()
		entry["_tag"] = tag
		active_buffs.append(entry)

# 地图边界钳制：统一到 Config.MAP_EDGE_LIMIT；泉水小院（泉水圆心 ±62）允许再向外到 ±62.5
func _clamp_to_map_edge() -> void:
	var half: float = Config.MAP_EDGE_LIMIT
	var spring := Vector3(-62, 0, 62) if team == Config.Team.PLAYER else Vector3(62, 0, -62)
	if global_position.distance_to(spring) <= 7.5:
		half += 1.3
	global_position.x = clampf(global_position.x, -half, half)
	global_position.z = clampf(global_position.z, -half, half)

# 恢复中（泉水/血包/恢复技能等持续回血回蓝）的展示动画：脚下旋转绿环 + 上浮绿光粒子
func _update_regen_fx(delta: float) -> void:
	var active: bool = health > 0.0 and (not active_regen.is_empty() or (is_in_own_fountain() and health < actual_max_health))
	if not active:
		if _regen_ring != null and is_instance_valid(_regen_ring):
			_regen_ring.visible = false
		if _regen_fx != null and is_instance_valid(_regen_fx):
			_regen_fx.emitting = false
		return
	if _regen_ring == null or not is_instance_valid(_regen_ring) or _regen_fx == null or not is_instance_valid(_regen_fx):
		_build_regen_fx()
	_regen_t += delta
	_regen_ring.visible = true
	_regen_fx.emitting = true
	_regen_ring.rotation.y = _regen_t * 1.8
	var pulse: float = 1.0 + 0.10 * sin(_regen_t * 5.5)
	_regen_ring.scale = Vector3(pulse, 1.0, pulse)

func _build_regen_fx() -> void:
	# 脚下绿环
	_regen_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.28
	torus.outer_radius = 1.48
	torus.rings = 36
	torus.ring_segments = 8
	_regen_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.28, 1.0, 0.48, 0.50)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.20, 0.95, 0.42)
	ring_mat.emission_energy_multiplier = 1.8
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_regen_ring.material_override = ring_mat
	_regen_ring.position = Vector3(0, 0.10, 0)
	_regen_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_regen_ring.visible = false
	add_child(_regen_ring)
	# 上浮绿色粒子
	_regen_fx = CPUParticles3D.new()
	_regen_fx.amount = 20
	_regen_fx.lifetime = 0.9
	_regen_fx.emitting = false
	_regen_fx.position = Vector3(0, 0.35, 0)
	_regen_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_regen_fx.emission_sphere_radius = 0.85
	_regen_fx.direction = Vector3.UP
	_regen_fx.spread = 18.0
	_regen_fx.initial_velocity_min = 1.1
	_regen_fx.initial_velocity_max = 2.3
	_regen_fx.gravity = Vector3(0, 1.2, 0)
	_regen_fx.scale_amount_min = 0.5
	_regen_fx.scale_amount_max = 1.1
	_regen_fx.color = Color(0.45, 1.0, 0.62, 0.95)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	_regen_fx.mesh = quad
	var fx_mat := StandardMaterial3D.new()
	fx_mat.albedo_color = Color(1, 1, 1, 0.9)
	fx_mat.emission_enabled = true
	fx_mat.emission = Color(0.30, 1.0, 0.50)
	fx_mat.emission_energy_multiplier = 2.2
	fx_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fx_mat.vertex_color_use_as_albedo = true
	_regen_fx.material_override = fx_mat
	add_child(_regen_fx)
# 是否身处自家泉水（泉水回复 / 元流流派切换 / AI 养伤共用同一半径判据）
func is_in_own_fountain() -> bool:
	if health <= 0.0:
		return false
	var spring := Vector3(-62.0, 0.0, 62.0) if team == Config.Team.PLAYER else Vector3(62.0, 0.0, -62.0)
	return global_position.distance_to(spring) <= 3.6

# 元流之子：是否身处自家泉水（回复/流派切换共用同一半径判据；回复段仍保留原内联判据不搬）
func in_own_fountain() -> bool:
	return display_name == "元流之子" and is_in_own_fountain()

# 元流之子·万物为流：安全切换流派——先整条移除 yuanliu_choice buff 条目再重算，
# 避免换向时残留旧加成键（如穿心 bonus_attack 残留到迅疾）；生机/凝神走重算特判。
# 调用方负责泉水时机（离线泉水按钮 / 联机 host 校验），本方法自身不强判。
func set_yuanliu_pick(pk: String) -> bool:
	if display_name != "元流之子":
		return false
	if pk != "生机" and pk != "穿心" and pk != "迅疾" and pk != "凝神":
		return false
	if pk == yuanliu_pick:
		return true
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].get("_tag", "") == "yuanliu_choice":
			active_buffs.remove_at(i)
			break
	yuanliu_pick = pk
	_recalculate_attributes()
	if health > actual_max_health:
		health = actual_max_health
	if mana > actual_mana_max:
		mana = actual_mana_max
	return true

# 元流之子·万物为流：获得/消耗「流」即把 5 秒闲置流失窗口重置回满（普攻耗流/连发耗流/Q获得）
func yuanliu_flow_activity() -> void:
	if display_name == "元流之子":
		yuanliu_flow_idle = 5.0

# 「技能视作普攻」命中结算入口（Bullet.counts_as_aa 首段命中调用）：
# 复刻 _perform_attack 中“普攻命中”才生效的装备效果——闪电匕首/末世/圣剑/凝冰/寒霜/制裁/影刃/
# 急速靴/逐日/破晓；不消费“技能后下次普攻”类强化标记（宗师/冰痕/巫术），也不触发打野/日渊主动等。
func proc_aa_item_effects(target) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return
	if not is_instance_valid(self) or health <= 0.0:
		return
	if target.team == team:
		return
	if equipment_slots.has("lightning_knife"):
		_aa_lightning_proc(target)
	# 末世：普攻额外 80-160 物伤，对英雄按目标额外生命 7% 追加
	if equipment_slots.has("world_end"):
		var we_dmg = 80.0 + level * 5.3
		if target is Hero:
			we_dmg += target.bonus_health * 0.07
		target.take_damage(we_dmg, self, false, -72, 0)
	# 金色圣剑：普攻+60 物伤并叠攻速层（叠满AP法伤由 apply_gold_saint_sword 处理）
	if equipment_slots.has("gold_saint_sword"):
		target.take_damage(60.0, self, false, -73, 0)
		OnHitProcessor.apply_gold_saint_sword(self, target, false)
	# 凝冰之息：普攻减速+法伤（3s CD）
	if equipment_slots.has("frost_breath") and frost_breath_cd <= 0:
		frost_breath_cd = 3.0
		target.apply_move_pct_buff("ms_slow", 1.5, -(0.05 + level * 0.0005), true)
		var fb_dmg2 = 75 + level * 5 + actual_ability_power * 0.15
		target.take_damage(fb_dmg2, self, true, -25, 0)
	# 寒霜袭侵 / 制裁·梦魇：普攻减速与重伤
	OnHitProcessor.apply_frost_assault(self, target)
	OnHitProcessor.apply_grievous_wounds(self, target)
	# 影刃：普攻命中+攻速(暴击+20%)与5%移速 3秒
	if equipment_slots.has("shadow_blade"):
		var sb_as = 20 if randf() < actual_crit_chance else 10
		_apply_ak_sp_buff(sb_as, 3.0)
		apply_move_pct_buff("ms_haste", 3.0, 0.05)
	# 急速战靴：每次普攻回复生命（远程30-60/近战20-40）
	if equipment_slots.has("swift_boots"):
		var bh = 30.0 + level * 0.6 if attack_range > 500 else 20.0 + level * 1.3
		_apply_healing(bh)
	# 逐日之弓 / 仁者破晓：普攻增伤（远程+50/近战+25，物理附伤单独结算）
	if equipment_slots.has("sunspire_bow"):
		target.take_damage(50.0 if attack_range > 500 else 25.0, self, false, -74, 0)
	if equipment_slots.has("dawn"):
		target.take_damage(50.0 if attack_range > 500 else 25.0, self, false, -75, 0)

# 闪电匕首·普攻命中特效（视作普攻的子弹也走同一套：附伤+共享链式电弧计数/冷却）
func _aa_lightning_proc(target) -> void:
	if not equipment_slots.has("lightning_knife"):
		return
	var lk_dmg = 40.0 + level * 2.6
	target.take_damage(lk_dmg, self, true, -20, 0)
	lightning_count += 1
	if lightning_count < 3:
		return
	lightning_count = 0
	var lc_dmg = 160.0 + level * 16.0
	# 链式电弧：从目标向周围敌人传导
	var chained = [target]
	var last = target
	for _i in range(4):
		var nearest = null
		var best_dist = 4.0
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or ent.health <= 0 or ent.team == team:
				continue
			if ent in chained:
				continue
			var d = last.global_position.distance_to(ent.global_position)
			if d < best_dist:
				best_dist = d
				nearest = ent
		if nearest == null:
			break
		# 画电弧线(多个小球连接)
		var steps = 8
		var prev_pos = last.global_position + Vector3.UP * 1.5
		for s in range(1, steps + 1):
			var t = float(s) / steps
			var pos = last.global_position.lerp(nearest.global_position, t) + Vector3.UP * 1.5
			var seg = MeshInstance3D.new()
			var box = BoxMesh.new()
			box.size = Vector3(0.1, 0.1, prev_pos.distance_to(pos))
			seg.mesh = box
			var seg_mid = (prev_pos + pos) / 2
			seg.position = seg_mid
			seg.look_at(pos, Vector3.UP)
			var smat = StandardMaterial3D.new()
			smat.albedo_color = Color.YELLOW
			smat.emission_enabled = true; smat.emission = Color.YELLOW
			smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			seg.material_override = smat
			get_parent().add_child(seg)
			var tw2 = create_tween()
			tw2.tween_interval(0.3)
			tw2.tween_callback(seg.queue_free)
			prev_pos = pos
		nearest.take_damage(lc_dmg, self, true, -20, 0)
		chained.append(nearest)
		last = nearest

# 英睿肘击：2米位移 + 路径伤害(距离越近越高) + 击飞0.5s（W三段与被动共用）
func yingrui_elbow(target_pos: Vector3) -> void:
	if display_name != "英睿":
		return
	var ang = atan2((-target_pos.z + global_position.z), (target_pos.x - global_position.x))
	var dir = Vector3(cos(ang), 0, -sin(ang))
	var old_pos = global_position
	var new_pos = old_pos + dir * 2.0
	new_pos.y = 0.5
	var line_vec = new_pos - old_pos
	var w_lv = maxi(skill_levels[1] if skill_levels.size() > 1 else 0, 1)
	var w_dmg_base = int(420 + 45 * (w_lv - 1) + bonus_attack * 1.4)
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == self or ent.health <= 0 or ent.team == team: continue
		var t = clampf((ent.global_position - old_pos).dot(line_vec) / line_vec.length_squared(), 0, 1)
		var closest = old_pos + line_vec * t
		if closest.distance_to(ent.global_position) <= 1.2:
			# 距离越近伤害越高
			var dist = global_position.distance_to(ent.global_position)
			var ratio = 1.1
			if dist <= 0.8: ratio = 1.4
			elif dist > 1.5: ratio = maxf(0.7, 1.1 - (dist - 1.5) * 0.4)
			ent.take_damage(int(w_dmg_base * ratio), self, false, 2, 0)
			ent.knockup_timer = max(ent.knockup_timer, 0.5)
			_cc_burst(ent)
			if ent is Hero:
				yingrui_add_stack()
	dash_move_to(new_pos, 0.13, "")
	# 肘击冲击环视觉
	var ring = MeshInstance3D.new()
	var rm = TorusMesh.new()
	rm.inner_radius = 0.5; rm.outer_radius = 0.6
	ring.mesh = rm
	var r_mat = StandardMaterial3D.new()
	r_mat.albedo_color = Color(1.0, 0.85, 0.3)
	r_mat.emission_enabled = true; r_mat.emission = Color(1.0, 0.7, 0.2)
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.albedo_color.a = 0.8
	ring.material_override = r_mat
	ring.position = new_pos + Vector3(0, 0.2, 0)
	get_parent().add_child(ring)
	var tw_r = create_tween()
	tw_r.tween_property(ring, "scale", Vector3(2.5, 1, 2.5), 0.35)
	tw_r.parallel().tween_property(ring.material_override, "albedo_color:a", 0.0, 0.35)
	tw_r.tween_callback(ring.queue_free)

# 英睿被动：技能命中敌方英雄 → 回复生命 + 叠冰爽层数
func yingrui_add_stack():
	if display_name != "英睿":
		return
	yingrui_stacks = mini(yingrui_stacks + 1, 5)
	yingrui_stack_timer = 6.0
	_apply_healing(50 + 10 * level)
	_recalculate_attributes()


# 依据当前聚合的 bonus_move_speed_pct（含 ≥50% 爆发加速按剩余时长衰减后的瞬时值）烘焙实际移速。
# 500 软上限 + 自身后置倍率（暴烈叠层 / 兰陵王隐身）集中在此：重算与每帧衰减刷新共用同一入口。
func _bake_move_speed_from_pool():
	var total_move_speed := (base_move_speed + bonus_move_speed) * (1.0 + bonus_per_speed)
	if total_move_speed > 500: total_move_speed = 500 + (total_move_speed - 500) * 0.5
	total_move_speed *= (1.0 + bonus_move_speed_pct)
	if total_move_speed < 0.0: total_move_speed = 0.0
	actual_move_speed = total_move_speed
	if fierce_armor_stacks > 0:
		actual_move_speed *= (1.0 + fierce_armor_stacks * 0.01)
	if lanling_stealth_active:
		actual_move_speed *= (1.0 + 0.15 + level * 0.01)

# 有衰减中的加速条目时每帧轻量刷新移速：只重聚移速池并按衰减瞬时值重烘焙，
# 避免把整套属性重算（装备/攻速/UI 面板等）挂到每帧
func _refresh_decaying_move_speed():
	bonus_move_speed_pct = 0.0
	for b in active_buffs:
		if float(b.get("timer", 0.0)) > 0.0:
			bonus_move_speed_pct += _entry_move_pct(b)
	_bake_move_speed_from_pool()
	_refresh_speed_report()

func _recalculate_attributes():
	_apply_equipment_bonuses()
	_snapshot_equip_stats()
	# 被动（狄仁杰/后羿叠层、李白侠客行、铠永久移速）统一写成 buff 条目后再聚合
	_sync_passive_buffs()
	_calculate_buff()
	actual_max_health = base_health + role_growth["health"] * (level - 1) + bonus_health
	# 元流之子·生机：额外 +300~600 生命（随等级 t=(level-1)/14 线性成长）
	if display_name == "元流之子" and yuanliu_pick == "生机":
		actual_max_health += 300.0 + 300.0 * minf((level - 1) / 14.0, 1.0)
	actual_attack_damage = base_attack + role_growth["attack"] * (level - 1) + bonus_attack
	actual_armor = base_armor + role_growth["armor"] * (level - 1) + bonus_armor
	actual_magic_resist = base_magic_resist + role_growth["magic_resist"] * (level - 1) + bonus_magic_resist
	armor = actual_armor
	magic_resist = actual_magic_resist
	var panel_attack_speed = (base_as / 1000.0 - 1.0) + attack_speed_growth * 100 * (level - 1) + bonus_attack_speed
	panel_attack_speed = clamp(panel_attack_speed, -50, 200)
	var thresholds = MODEL_A_THRESHOLDS
	var interval = 1.0
	for i in range(thresholds.size() - 1, -1, -1):
		if panel_attack_speed >= thresholds[i][0]: interval = thresholds[i][1]; break
	attack_speed = 1.0 / interval
	# 减速/加速净百分比统一在此烘焙进实际移速（各 move_speed_pct buff 条目经 _calculate_buff 聚合，替代旧的逐帧乘算）
	_bake_move_speed_from_pool()
	actual_ability_power = (base_ability_power + bonus_ability_power) * (1.0 + bonus_per_ability_power)
	actual_mana_max = base_mana + bonus_max_mana
	actual_hp_regen = base_hp_regen + bonus_hp_regen
	actual_mana_regen = base_mana_regen + bonus_mana_regen
	if blue_buff_active: actual_mana_regen += 0.1 * actual_mana_max; actual_cd_timer -= 0.2
	# 元流之子·凝神：额外 +5%~10% 冷却缩减（随等级，与装备/CD 叠乘后 clamp 0.4）
	if display_name == "元流之子" and yuanliu_pick == "凝神":
		actual_cd_timer -= 0.05 + 0.05 * minf((level - 1) / 14.0, 1.0)
	if actual_cd_timer < 0.4: actual_cd_timer = 0.4

	# 面板式攻速增益（逐风/兰陵王解隐）并入 attack_speed_timer；
	# 狄仁杰/后羿叠层攻速改走 _sync_passive_buffs() 的攻速 buff 聚合
	var as_factor := 1.0
	actual_crit_chance = clamp(base_crit_chance + bonus_crit_chance, 0.0, 1.0)
	actual_crit_damage = base_crit_damage + bonus_crit_damage
	actual_phys_lifesteal = base_phys_lifesteal + bonus_phys_lifesteal
	actual_magic_lifesteal = base_magic_lifesteal + bonus_magic_lifesteal
	actual_phys_pen_percent = clamp(base_phys_pen_percent + bonus_phys_pen_percent, 0.0, 1.0)

	actual_magic_pen_percent = clamp(base_magic_pen_percent + bonus_magic_pen_percent, 0.0, 1.0)
	flat_phys_pen = bonus_flat_phys_pen
	flat_magic_pen = bonus_flat_magic_pen
	# 逐风叠层加成
	if chase_wind_stacks > 0: var cwb = chase_wind_stacks * 0.02; actual_attack_damage *= (1.0 + cwb); as_factor *= (1.0 + cwb)
	# 暴烈之甲叠层加成
	if fierce_armor_stacks > 0: var fab = fierce_armor_stacks * 0.01; actual_attack_damage *= (1.0 + fab)   # 移速部分由 _bake_move_speed_from_pool 计入
	# 兰陵王: 隐身移速已由 _bake_move_speed_from_pool 计入；解隐攻速并入 as_factor
	if lanling_as_buff_timer > 0: as_factor *= (1.0 + 0.30 + level * 0.02)
	toughness = bonus_toughness
	# 狄仁杰/后羿叠层攻速移速、李白侠客行攻击、铠永久移速均已由 _sync_passive_buffs()
	# 写成 active_buffs 计时条目并经上方 _calculate_buff() 聚合，此处不再直接乘算。
	# 攻速计时因子：攻速类buff(attack_speed_pct 聚合) × 面板式攻速增益
	attack_speed_timer = clampf((1.0 + bonus_attack_speed_pct) * as_factor, 0.3, 3.0)
	# 攻击距离 = 底值 + buff 加成（李元芳 Q 等 bonus_attack_range 派生；逐日弓倍率乘在 _range_base）
	if _range_base < 0.0:
		_range_base = attack_range - bonus_attack_range
	attack_range = _range_base + bonus_attack_range
	_refresh_speed_report()
	_update_attack_range_ring()
	_update_stat_breakdown()



var bonus_max_mana: float = 0.0
var bonus_per_ability_power: float = 0.0
var bonus_toughness: float = 0.0
var bonus_per_speed: float = 0.0

func _apply_equipment_bonuses():
	bonus_health = 0; bonus_attack = 0; bonus_armor = 0; bonus_magic_resist = 0
	bonus_move_speed = 0; bonus_ability_power = 0; bonus_hp_regen = 0; bonus_mana_regen = 0
	bonus_attack_speed =0;bonus_crit_chance =0;bonus_crit_damage =0;bonus_phys_lifesteal =0;
	bonus_magic_lifesteal =0;bonus_phys_pen_percent =0;bonus_magic_pen_percent =0;actual_cd_timer =1;bonus_flat_phys_pen = 0;bonus_flat_magic_pen = 0;
	bonus_max_mana = 0; bonus_per_ability_power = 0; bonus_toughness = 0; bonus_per_speed = 0
	bonus_move_speed_pct = 0; bonus_attack_speed_pct = 0; bonus_attack_range = 0
	for item_id in equipment_slots:
		var item = ItemDatabase.get_item(item_id)
		if not item.is_empty():
			bonus_health += item.get("health", 0)
			bonus_attack += item.get("attack", 0)
			bonus_armor += item.get("armor", 0)
			bonus_magic_resist += item.get("magic_resist", 0)
			bonus_move_speed += item.get("speed", 0)
			bonus_ability_power += item.get("ability_power", 0)
			bonus_hp_regen += item.get("hp_regen", 0)
			bonus_mana_regen += item.get("mana_regen", 0)
			bonus_attack_speed += item.get("attack_speed", 0)
			bonus_crit_chance += item.get("crit_chance", 0) / 100.0
			bonus_crit_damage += item.get("crit_damage", 0) / 100.0
			bonus_phys_lifesteal += item.get("lifesteal", 0) / 100.0
			bonus_magic_lifesteal += item.get("spell_vamp", 0) / 100.0
			bonus_phys_pen_percent += item.get("armor_pen_percent", 0) / 100.0
			bonus_magic_pen_percent += item.get("magic_pen_percent", 0) / 100.0
			actual_cd_timer -= item.get("cooldown", 0) / 100.0
			bonus_max_mana += item.get("mana", 0)
			bonus_per_ability_power += item.get("per_ability_power", 0) / 100.0
			bonus_toughness += item.get("toughness", 0) / 100.0
			bonus_per_speed += item.get("per_speed", 0) / 100.0
			bonus_flat_phys_pen += item.get("phys_pen", 0)
			bonus_flat_magic_pen += item.get("magic_pen", 0)
	# --- 装备特殊效果 ---
	if equipment_slots.has("heavy_armor"): bonus_health += max_health * 0.04
	if equipment_slots.has("ice_shock"): bonus_toughness += 0.10
	if equipment_slots.has("mage_robe"): bonus_armor += bonus_magic_resist * 0.15
	if equipment_slots.has("demon_bane_blade"): bonus_magic_resist += min(attack * 0.5, 250)
	if equipment_slots.has("battle_axe"): bonus_flat_phys_pen += 90 + level * 6
	if equipment_slots.has("dusk_flow") and dusk_flow_stacks > 0: bonus_flat_magic_pen += (20 + level * 1.3) * dusk_flow_stacks
	if equipment_slots.has("break_cocoon_cloth"): bonus_ability_power += min(20 + level * 1.3 + bonus_health * 0.02, 100); bonus_flat_magic_pen += min(30 + level * 2 + bonus_health * 0.03, 150)
	if equipment_slots.has("prophecy_of_time"): var ptb = 50 + level * 3.3 + bonus_ability_power * 0.1; bonus_armor += ptb; bonus_magic_resist += ptb
	if equipment_slots.has("guerrilla_blade") or equipment_slots.has("rune_blade"): bonus_ability_power += jungle_stacks * 6
	if equipment_slots.has("chase_blade") or equipment_slots.has("greed_blade"): bonus_attack += jungle_stacks * 3
	if equipment_slots.has("patrol_axe") or equipment_slots.has("giant_grasp"): bonus_health += jungle_stacks * 30
	if equipment_slots.has("rune_blade") or equipment_slots.has("greed_blade") or equipment_slots.has("giant_grasp"): actual_cd_timer -= jungle_stacks * 0.002
	if equipment_slots.has("infinity_edge"): bonus_crit_damage += min(0.5, 0.2 + (bonus_crit_chance+base_crit_chance) * 0.5)
	if equipment_slots.has("godslayer_book"): actual_cd_timer -= bonus_ability_power / 100.0 * 0.005

# 装备属性快照：_apply_equipment_bonuses() 之后、_calculate_buff() 之前调用，
# 记录当前 bonus_* 即“装备来源”分量基准。
func _snapshot_equip_stats():
	equip_snapshot = {
		"health": bonus_health, "attack": bonus_attack,
		"armor": bonus_armor, "magic_resist": bonus_magic_resist,
		"move_speed": bonus_move_speed, "ability_power": bonus_ability_power,
		"attack_speed": bonus_attack_speed, "crit_chance": bonus_crit_chance,
		"phys_lifesteal": bonus_phys_lifesteal, "magic_lifesteal": bonus_magic_lifesteal,
		"phys_pen_percent": bonus_phys_pen_percent, "magic_pen_percent": bonus_magic_pen_percent,
		"flat_phys_pen": bonus_flat_phys_pen, "flat_magic_pen": bonus_flat_magic_pen,
		"max_mana": bonus_max_mana, "cd_timer": actual_cd_timer,
		"crit_damage": bonus_crit_damage, "toughness": bonus_toughness,
	}

# 将「基础 / 装备 / Buff」三段线性分量等比缩放到与最终 actual_* 完全一致。
# 处理乘算被动（逐风/暴烈/狂暴/贤者书等）：三者同比例伸缩，保证白+绿+橙 ≡ 实际总值。
func _scaled_split(b0: float, e0: float, f0: float, total: float) -> Array:
	var s := b0 + e0 + f0
	if absf(s) < 0.001:
		return [0.0, 0.0, 0.0]
	if absf(s - total) <= 0.01:
		return [b0, e0, f0]
	var k := total / s
	return [b0 * k, e0 * k, f0 * k]

# 计算各属性三段分量（在 _recalculate_attributes 末尾调用；结果供 UI 属性面板读取）
func _update_stat_breakdown():
	var gl := level - 1
	var gr: Dictionary = role_growth
	var es: Dictionary = equip_snapshot
	var sb: Dictionary = {}
	sb["health"] = _scaled_split(base_health + float(gr.get("health", 0)) * gl,
		float(es.get("health", 0)), bonus_health - float(es.get("health", 0)), actual_max_health)
	sb["mana"] = _scaled_split(base_mana,
		float(es.get("max_mana", 0)), bonus_max_mana - float(es.get("max_mana", 0)), actual_mana_max)
	sb["attack"] = _scaled_split(base_attack + float(gr.get("attack", 0)) * gl,
		float(es.get("attack", 0)), bonus_attack - float(es.get("attack", 0)), actual_attack_damage)
	sb["ability_power"] = _scaled_split(base_ability_power,
		float(es.get("ability_power", 0)), bonus_ability_power - float(es.get("ability_power", 0)), actual_ability_power)
	sb["armor"] = _scaled_split(base_armor + float(gr.get("armor", 0)) * gl,
		float(es.get("armor", 0)), bonus_armor - float(es.get("armor", 0)), actual_armor)
	sb["magic_resist"] = _scaled_split(base_magic_resist + float(gr.get("magic_resist", 0)) * gl,
		float(es.get("magic_resist", 0)), bonus_magic_resist - float(es.get("magic_resist", 0)), actual_magic_resist)
	sb["move_speed"] = _scaled_split(base_move_speed,
		float(es.get("move_speed", 0)), bonus_move_speed - float(es.get("move_speed", 0)), actual_move_speed)
	# 攻速以「面板攻速%」计（基础项已含等级成长）
	var as_base := base_as / 1000.0 - 1.0 + float(gr.get("attack_speed", 0)) * 100.0 * gl
	var as_equip := float(es.get("attack_speed", 0))
	var as_buff := bonus_attack_speed - as_equip
	sb["attack_speed"] = _scaled_split(as_base, as_equip, as_buff,
		clampf(as_base + as_equip + as_buff, -50.0, 200.0))
	# 以下原值多为 0~1 小数，面板显示时 ×100 成百分比
	sb["crit_chance"] = _scaled_split(base_crit_chance,
		float(es.get("crit_chance", 0)), bonus_crit_chance - float(es.get("crit_chance", 0)), actual_crit_chance)
	sb["crit_damage"] = _scaled_split(base_crit_damage,
		float(es.get("crit_damage", 0)), bonus_crit_damage - float(es.get("crit_damage", 0)), actual_crit_damage)
	sb["phys_lifesteal"] = _scaled_split(base_phys_lifesteal,
		float(es.get("phys_lifesteal", 0)), bonus_phys_lifesteal - float(es.get("phys_lifesteal", 0)), actual_phys_lifesteal)
	sb["magic_lifesteal"] = _scaled_split(base_magic_lifesteal,
		float(es.get("magic_lifesteal", 0)), bonus_magic_lifesteal - float(es.get("magic_lifesteal", 0)), actual_magic_lifesteal)
	sb["phys_pen_percent"] = _scaled_split(base_phys_pen_percent,
		float(es.get("phys_pen_percent", 0)), bonus_phys_pen_percent - float(es.get("phys_pen_percent", 0)), actual_phys_pen_percent)
	sb["magic_pen_percent"] = _scaled_split(base_magic_pen_percent,
		float(es.get("magic_pen_percent", 0)), bonus_magic_pen_percent - float(es.get("magic_pen_percent", 0)), actual_magic_pen_percent)
	# 数值类穿透（基础恒为 0，仅装备/特殊被动提供）
	var fpp_e := float(es.get("flat_phys_pen", 0.0))
	sb["phys_pen_flat"] = _scaled_split(0.0, fpp_e, bonus_flat_phys_pen - fpp_e, flat_phys_pen)
	var fmp_e := float(es.get("flat_magic_pen", 0.0))
	sb["magic_pen_flat"] = _scaled_split(0.0, fmp_e, bonus_flat_magic_pen - fmp_e, flat_magic_pen)
	# 冷却缩减
	var cd_total := (1.0 - actual_cd_timer) * 100.0
	var cd_equip := (1.0 - float(es.get("cd_timer", 1.0))) * 100.0
	# 韧性:基础为 0,主要来自装备/被动与 Buff(显示为百分比)
	var toughness_e := float(es.get("toughness", 0.0))
	sb["toughness"] = _scaled_split(0.0, toughness_e, bonus_toughness - toughness_e, bonus_toughness)
	sb["cd"] = _scaled_split(0.0, cd_equip, cd_total - cd_equip, cd_total)
	stat_breakdown = sb

# 移速面板实时分量：减速/加速等临时移速效果已烘焙进 actual_move_speed 与
# stat_breakdown 的 Buff 段，三段和即当前实际移速，无需逐帧修正。
func _live_move_speed_parts() -> Array:
	return stat_breakdown.get("move_speed", [0.0, 0.0, 0.0])

func apply_red_buff():
	
	red_buff_active = true
	red_buff_timer = BUFF_DURATION
	
	_recalculate_attributes()

func apply_blue_buff():
	if not blue_buff_active:
		blue_buff_active = true
		blue_buff_timer = BUFF_DURATION


# 英雄模型映射表：display_name → [模型路径, 可选配件路径]
const HERO_MODEL_MAP = {
	# 女英雄 (6)
	"甄姬":     ["res://model/hero/character-female-a.glb", ""],
	"安琪拉":   ["res://model/hero/character-female-b.glb", ""],
	"妲己":     ["res://model/hero/character-female-c.glb", ""],
	"不知火舞": ["res://model/hero/character-female-d.glb", ""],
	"孙尚香":   ["res://model/hero/character-female-e.glb", ""],
	"沈梦溪":   ["res://model/hero/character-female-f.glb", ""],
	"小乔":     ["res://model/hero/character-female-a.glb", ""],
		"王昭君":   ["res://model/hero/character-female-a.glb", ""],
	# 男英雄 (6)
	"吕布":     ["res://model/hero/character-male-a.glb", ""],
	"亚瑟":     ["res://model/hero/character-male-b.glb", ""],
	"铠":       ["res://model/hero/character-male-c.glb", ""],
	"李白":     ["res://model/hero/character-male-d.glb", ""],
	"兰陵王":   ["res://model/hero/character-male-e.glb", ""],
	"张飞":     ["res://model/hero/character-male-f.glb", ""],
	# 特殊英雄 (5) — 复用底座 + 配件区分
	"东皇太一": ["res://model/hero/character-male-a.glb", "res://model/hero/aid-mask.glb"],
	"马超":     ["res://model/hero/character-male-b.glb", ""],
	"狄仁杰":   ["res://model/hero/character-male-c.glb", "res://model/hero/aid-glasses.glb"],
	"马可波罗": ["res://model/hero/character-male-d.glb", "res://model/hero/aid-sunglasses.glb"],
	"太乙真人": ["res://model/hero/character-male-f.glb", "res://model/hero/aid-cane.glb"],
	"鲁班七号": ["res://model/hero/character-male-a.glb", ""],
	"夏侯惇": ["res://model/hero/character-male-a.glb", ""],
	"后羿": ["res://model/hero/character-male-a.glb", ""],
	"李元芳": ["res://model/hero/character-male-a.glb", ""],
	"元流之子": ["res://model/hero/character-male-a.glb", ""],
	"大禹": ["res://model/hero/character-male-a.glb", ""],
	"孙悟空": ["res://model/hero/character-male-a.glb", ""],
"刘禅":     ["res://model/hero/character-male-b.glb", ""],
	# 英睿：男战士底座 + 程序化签名道具（耳机/冰红茶/背包 LabiB），大招换等身 LabiB 毛绒形态（HeroYingrui.gd）
	"英睿":     ["res://model/hero/character-male-d.glb", ""],

}

## 皮肤强调色：经典皮肤仍用原英雄元素色
func skin_accent_color() -> Color:
	if hero_skin_id == "" or HeroSkinTable.get_skin(display_name, hero_skin_id).is_empty():
		return Vfx.color_for_hero(display_name)
	if not HeroSkinTable.is_custom(display_name, hero_skin_id):
		return Vfx.color_for_hero(display_name)
	return HeroSkinTable.accent_for(display_name, hero_skin_id)


func skin_is_custom() -> bool:
	return HeroSkinTable.is_custom(display_name, hero_skin_id)


func _load_hero_model() -> Node3D:
	var entry = HERO_MODEL_MAP.get(display_name, [])
	if entry.is_empty():
		return null
	var model_path: String = entry[0]
	var accessory_path: String = entry[1] if entry.size() > 1 else ""
	var model = load(model_path)
	if not model:
		return null
	var root = Node3D.new()
	root.name = "HeroModel"
	var instance = model.instantiate()
	# 英雄模型总放大×3.0（原已×2.0，再×1.5；张飞变身倍率在 visual_mesh 上独立叠加）
	instance.scale = Vector3(3.0, 3.0, 3.0)
	root.add_child(instance)
	# 轮椅英雄：角色本体 + 座椅（本体上抬并切坐姿，避免只剩一把椅子）
	if HeroWeapons.is_wheelchair_hero(display_name):
		HeroWeapons.mount_wheelchair(root, instance, display_name, 3.0)
	# 专属武器（程序化建模，按英雄名区分造型）
	HeroWeapons.attach(instance, display_name, attack_range * 0.01)
	# 英睿：签名道具（耳机 / 挂腰冰红茶 / 背包小 LabiB），米制坐标挂在 HeroModel 根（同 aid-mask 配件做法）
	if display_name == "英睿":
		yingrui_body = instance
		HeroYingrui.attach_props(root)
	# 查找动画播放器
	anim_player = _find_anim_player(instance)
	if anim_player:
		_play_anim("idle")
	# 加载配件
	if accessory_path != "":
		var acc = load(accessory_path)
		if acc:
			var acc_instance = acc.instantiate()
			root.add_child(acc_instance)
			# 轮椅英雄：辅具按坐姿重新摆位（配件是米制尺寸，原本挂在模型根原点=贴地）
			if HeroWeapons.is_wheelchair_hero(display_name):
				if display_name == "太乙真人":
					acc_instance.position = Vector3(0.62, 0.0, 0.30)   # 手杖立在轮椅旁
				else:
					acc_instance.position = Vector3(0.0, 1.10, 0.10)  # 眼镜/墨镜架在面部高度
	return root


# 鲁班七号被动扫射：与普通普攻不同的双手持械扫射动作，3 轮、每轮命中前方 30° 扇形内全部敌人
func _luban_sweep_attack(target: GameEntity) -> void:
	if not target or not is_instance_valid(target):
		return
	# 扫射动作：双手持械连续射击（普通普攻是单手持械），联机同步同一档动作
	_restart_anim("holding-both-shoot")
	NetSession.hero_anim(self, NetSession.ACT_CAST_BOTH_SHOOT)
	var flat_fwd := Vector3(target.global_position.x - global_position.x, 0.0,
		target.global_position.z - global_position.z)
	if flat_fwd.length() < 0.01:
		flat_fwd = Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	flat_fwd = flat_fwd.normalized()
	var half_deg := 15.0   # 30° 扇形 = 左右各 15°
	for _i in range(3):
		if not target or not is_instance_valid(target) or target.health <= 0:
			break
		# 扇形内所有敌人各吃一发；子弹只负责表现与命中结算（保留普攻特效/装备命中）
		for ent in get_tree().get_nodes_in_group("entities"):
			if ent == self or not (ent is GameEntity) or ent.health <= 0 or ent.team == team:
				continue
			if not (ent is Hero or ent is Minion or ent is Turret or ent is JungleMonster):
				continue
			var to_ent := Vector3(ent.global_position.x - global_position.x, 0.0,
				ent.global_position.z - global_position.z)
			var dist := to_ent.length()
			if dist > attack_range * 0.01 + float(ent.body_radius):
				continue
			if dist < 0.01:
				continue
			if flat_fwd.dot(to_ent / dist) < cos(deg_to_rad(half_deg)):
				continue
			var base_dmg: float
			if ent is Hero:
				base_dmg = 70 + level * 5 + ent.max_health * (0.045 + bonus_attack * 0.0001)
			else:
				base_dmg = 120 + level * 8.57 + bonus_attack * 0.5
			var sweep_bullet = skillapply.create_bullet(int(base_dmg), 0, 0, 0, false, self, to_ent / dist, 0)
			sweep_bullet.target = ent
			sweep_bullet.life_time = 1.5
			get_parent().add_child(sweep_bullet)
		if _i < 2:
			await get_tree().create_timer(0.11).timeout


# 王昭君被动强化普攻：朝目标直线发射3枚冰锥（无角度偏差，线性飞行，间隔0.08秒）
func _wangzhaojun_spike_attack(target: GameEntity) -> void:
	if not target or not is_instance_valid(target):
		return
	var per_spike_dmg = (56 + 4.3 * level) + actual_ability_power * 0.12
	for _i in range(3):
		if not target or not is_instance_valid(target) or target.health <= 0:
			break
		var spike_dir = (target.global_position - global_position).normalized()
		var spike_bullet = skillapply.create_bullet(per_spike_dmg, 0, 0.12, 0, true, self, spike_dir, -52)
		spike_bullet.target = target
		spike_bullet.life_time = 1.5
		get_parent().add_child(spike_bullet)
		if _i < 2:
			await get_tree().create_timer(0.11).timeout
func _houyi_spike_attack(target: GameEntity,dmg:float) -> void:
	if not target or not is_instance_valid(target):
		return
	var per_spike_dmg = dmg
	for _i in range(3):
		if not target or not is_instance_valid(target) or target.health <= 0:
			break
		var spike_dir = (target.global_position - global_position).normalized()
		var spike_bullet = skillapply.create_bullet(per_spike_dmg, 0, 0.12, 0, true, self, spike_dir, -52)
		spike_bullet.target = target
		spike_bullet.life_time = 1.5
		get_parent().add_child(spike_bullet)
		if _i < 2:
			await get_tree().create_timer(0.15).timeout
