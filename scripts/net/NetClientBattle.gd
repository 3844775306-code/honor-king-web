extends Node3D
const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const NetModels = preload("res://scripts/net/NetModels.gd")
const MinionModelScript = preload("res://scripts/entities/MinionModel.gd")
const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
const NetTouchPadScript = preload("res://scripts/net/NetTouchPad.gd")
const NetMiniMapScript = preload("res://scripts/net/NetMiniMap.gd")
const ARENA_SPOTS: Array = [Vector3(43, 0, 43), Vector3(0, 0, 0), Vector3(-43, 0, -43)]
const ARENA_RADIUS: float = 7.2
const TouchActionButtonScript = preload("res://scripts/mobile/TouchActionButton.gd")
const NetTargetPanelScript = preload("res://scripts/net/NetTargetPanel.gd")
const NetBuffRowScript = preload("res://scripts/net/NetBuffRow.gd")
const NetRosterPanelScript = preload("res://scripts/net/NetRosterPanel.gd")
const NetShopPanelScript = preload("res://scripts/net/NetShopPanel.gd")
const NetRecommendBarScript = preload("res://scripts/net/NetRecommendBar.gd")
const NetKillFeedScript = preload("res://scripts/net/NetKillFeed.gd")
const NetRecallScript = preload("res://scripts/net/NetRecall.gd")
const NetDeathRecapScript = preload("res://scripts/net/NetDeathRecap.gd")
const NetResultPanelScript = preload("res://scripts/net/NetResultPanel.gd")
const PostMatchViewScript = preload("res://scripts/ui/PostMatchView.gd")
const EndBannerScript = preload("res://scripts/ui/EndBanner.gd")
const CrystalFinaleScript = preload("res://scripts/fx/CrystalFinale.gd")
const WukongCloudScript = preload("res://scripts/fx/WukongCloud.gd")
const MatchResultScript = preload("res://scripts/core/MatchResult.gd")
const PostMatchStageScript = preload("res://scripts/ui/PostMatchStage.gd")
const SharedHeroBarScript = preload("res://scripts/ui/shared/SharedHeroBar.gd")   # 三端共享英雄血条
const HeroSkinTable = preload("res://scripts/core/HeroSkins.gd")
const TeamDecisionViewScript = preload("res://scripts/ui/shared/TeamDecisionView.gd")   # 三端共享团队决策面板
const ActorPresenter = preload("res://scripts/presentation/ActorPresenter.gd")   # 三端共享角色表现参数
const AnimMap = preload("res://scripts/presentation/AnimMap.gd")                   # 三端共享动画 clip 映射
const ProjectilePresenter = preload("res://scripts/presentation/ProjectilePresenter.gd")   # 三端共享子弹表现
const SkillFxPresenter = preload("res://scripts/presentation/SkillFxPresenter.gd")   # 三端共享技能特效
const NetYuanliuScript = preload("res://scripts/net/NetYuanliuSwitch.gd")
const SpellFxTable = preload("res://scripts/core/SpellFxTable.gd")
## NetClientBattle —— M2-2 全 3D 渲染客户端。
## 读取主机快照渲染战场（不含任何模拟），接管主机同队 AI 后由真人发指令：
##   左键  行动（点敌方=攻击，点地=移动；预选技能时=施法目标）
##   1/2/3 预选英雄技能（再按或 Esc 取消）
##   R     回城
##   Tab   第一人称 / 第三人称（同主机 _set_camera_mode；阵亡自动退回）
##   右键按住拖动 旋转视角 / 滚轮 缩放 / 技能点自动分配
## 小地图（NetMiniMap）：画法复刻主机 Minimap.gd，按住拖动=本地取景、轻点=短跳转。
## 观战棋盘由 NetSession 在接管前显示，接管后自动隐藏。

# —— 快照布局（与 NetSession._build_snapshot 对齐）——
const SNAP_TIME := 0
const SNAP_STATE := 1
const SNAP_OWN := 2
const SNAP_HEROES := 3
const SNAP_MINIONS := 4
const SNAP_TURRETS := 5
const SNAP_JUNGLES := 6
const SNAP_BULLETS := 7
const SNAP_FX := 8
const SNAP_EVENTS := 9        # #44 数值弹出/经验珠/攻击动作事件段（host v5 idx9，仿 FX 缓冲/去重）
const SNAP_SCORE := 10        # 顶部实时战况（击杀比分+经济比分）：{pk,ek,pg,eg}（host 全量统计）
const SNAP_RESPAWN := 11      # 小地图右侧英雄环形头像带行（host _build_respawn_rows 尾段；长度守卫防旧 host）
const SNAP_VISION := 12       # 视野之灵行 [iid,x,z,active,progress,state]（host 快照尾段）
const SNAP_HEALTH_PACKS := 13 # 血包状态 [x,z,team,available,cooldown_timer,respawn_time]
const SNAP_SKILL_REVEALS := 14 # 技能侦察区域 [x,z,radius]（鲁班2/后羿R）
const SNAP_DEAD_HEROES := 15  # 阵亡尸体 [nid,team,x,z,yaw,name]（躺尸到复活）
const VisionSpiritScript = preload("res://scripts/entities/VisionSpirit.gd")
const MOVE_JUMP_UNITS := 100.0    # 相邻快照样本位移超此即判瞬移/位移技能/回城：直接贴最新，不插值滑行
const INTERP_DELAY := 0.08        # 实体插值回看窗口：WS（TCP）抖动下始终有下一个样本可插值，避免隔帧贴最新样本冻结

# —— #43 FX 播放参数（与 NetSession 快照 fx 段一致）——
const SNAP_FX_SEQ := 0      # fx 段 [0] 是 seq；[1..] 为条目
const FX_ROW_FID := 0
const FX_ROW_KIND := 1
const FX_ROW_X := 2
const FX_ROW_Y := 3
const FX_ROW_Z := 4
const FX_ROW_TEAM := 5
const FX_ROW_R := 6
const FX_ROW_LIFE := 7
const SNAP_BULLET_EXT := 0.066    # 子弹外推前向窗（=15Hz 快照间隔），超窗回贴最新采样
# —— FX kind 档位（与 NetSession 快照 fx 段/const 对齐；值同 SkillDataBase 视觉 helper）——
const FX_SPELL := 1          # create_spell：团队色 AoE 地面圆（矮圆柱）
const FX_PREVIEW := 2        # create_preview：范围瞄准环（暂不插桩）
const FX_TERRAIN := 3        # create_terrain：地形障碍（团队色）
const FX_WATER_SPLASH := 4   # 甄姬2 水花（0.35s 闪）
const FX_WATER_ZONE := 5     # 甄姬大招 水域（persist，蓝色）
const FX_WATER_PULSE := 6    # 甄姬R 水浪冲击（0.5s 扩）
const FX_LYF_STORM := 7      # 李元芳 风暴地面域（persist，橙）
const FX_YL_POOL := 8        # 元流 区域池（persist，青）
const FX_HOUYI_EXPLODE := 20 # Bullet.on_hit 后羿R 命中爆炸组（C 段插桩）
const FX_WAVE_RING := 21     # 扩散冲击环（薄环外扩一次性，刘禅R 波等）
const FX_XQ_WHIRL := 22      # 小乔2 甜蜜恋风：粉色渐缩旋风柱（~1s，固定粉，不看 team）
const FX_MACHAO_SPEAR := 23  # 马超Q/W 落地标枪（10s 地标）
const FX_SKILL_BURST := 24   # 通用技能命中爆发（元素色光球+环，一次扩散）
const FX_SKILL_DASH := 25    # 位移技能起手（脚下元素色环）
const FX_SKILL_ULT := 26     # 大招爆发（更大更久，元素色）
const FX_PILLAR := 27        # 地面光柱（技能柱/落地柱）
const FX_SKILL_GLOW := 28    # 施法蓄力/护盾起手光
const FX_SPELL_FULL := 29    # 完整技能视觉：直接调 Vfx.play_spell，与单机同源

# —— #44 events kind 与行字段（与 NetSession 快照 events 段对齐）——
#   段 = [seq(int), row, ...]；行 = [fid, kind, x, y, z, ...kind 专属]
#   DMG=[fid,1,x,y,z,dmg,crit,magic]  GOLD=[fid,2,x,y,z,amount,own]  EXP=[fid,3,sx,sy,sz,tx,tz,amount,nid]
#   ACT=[fid,4,nid,act,yaw]（动画阶段消费）
const EV_SEQ := 0
const EV_ROW_FID := 0
const EV_ROW_KIND := 1
const EV_ROW_X := 2
const EV_ROW_Y := 3
const EV_ROW_Z := 4
const EV_DMG := 1
const EV_GOLD := 2
const EV_EXP := 3
const EV_ACT := 4
const EV_DMG_AMT := 5
const EV_DMG_CRIT := 6
const EV_DMG_MAG := 7
const EV_DMG_SHIELD := 8
const EV_DMG_TRUE := 9
const EV_GOLD_AMT := 5
const EV_GOLD_OWN := 6
const EV_EXP_TX := 5
const EV_EXP_TZ := 6
const EV_EXP_AMT := 7
const EV_EXP_NID := 8
const EV_ACT_NID := 5
const EV_ACT_ACT := 6
const EV_ACT_YAW := 7

# 击杀金币小剑（近似复刻主机 KillGoldPopup 的矢量剑；label 上浮/淡出时随父 modulate 同步）
class _BladeMark:
	extends Control
	var fs := 24.0
	func _init(fs0: float) -> void:
		fs = fs0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := fs * 1.5
		var h := fs * 1.15
		var pts := PackedVector2Array([
			Vector2(0.0, h), Vector2(w * 0.62, h * 0.52),
			Vector2(w * 0.85, 0.0), Vector2(w, 0.0), Vector2(w * 0.6, h * 0.6)
		])
		draw_colored_polygon(pts, Color(1.0, 0.86, 0.25, 1.0))
		draw_line(Vector2(w * 0.05, h), Vector2(w * 0.9, h * 0.18), Color(1.0, 0.68, 0.1, 1.0), maxf(fs * 0.13, 2.0))
		draw_line(Vector2(0.0, h * 0.75), Vector2(w * 0.2, h * 0.58), Color(0.5, 0.32, 0.05, 1.0), maxf(fs * 0.14, 2.0))

# 普通金币徽标（近似复刻主机 ValuePopup 的矢量金币；label 上浮/淡出时随父 modulate 同步）
class _CoinMark:
	extends Control
	var fs := 24.0
	func _init(fs0: float) -> void:
		fs = fs0
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := fs * 0.42
		var c := size * 0.5
		var gold := Color(1.0, 0.86, 0.30, 1.0)
		draw_circle(c + Vector2(0.8, 1.2), r, Color(0, 0, 0, 0.40))
		draw_circle(c, r, gold.darkened(0.28))
		draw_circle(c, r * 0.84, gold)
		draw_circle(c, r * 0.50, gold.darkened(0.34))
		draw_arc(c, r * 0.84, PI * 1.10, PI * 1.62, 10, Color(1, 1, 1, 0.55), maxf(1.0, r * 0.18))

# —— 实体类型（与 NetSession 打包一致）——
const NET_HERO := 0
const NET_MINION := 1
const NET_TURRET := 2
const NET_JUNGLE := 3

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

# —— 配色 ——
const COL_GRASS := Color(0.13, 0.19, 0.11)
const COL_ROAD := Color(0.58, 0.46, 0.31)
const COL_ROAD_EDGE := Color(0.45, 0.36, 0.24)
const COL_BLUE := Color(0.30, 0.64, 1.0)
const COL_RED := Color(0.95, 0.30, 0.26)
const COL_NEUTRAL := Color(0.9, 0.78, 0.35)
const COL_ALLY_DIM := Color(0.30, 0.64, 1.0)
const COL_ENEMY := Color(0.95, 0.32, 0.30)

# 视口基准尺寸（HUD 按此缩放，避免高分屏字体过小）
const HUD_BASE := Vector2(1600.0, 900.0)

# 接管相机：复刻主机固定俯视镜头（BattleManager：fov70 / -70°俯角 / 自英雄偏移(0,8,5.33)=原(0,12,8)÷1.5 画面放大1.5倍）
const CAM_FOLLOW_OFF := Vector3(0.0, 12.0, 6.93)   # 同主机：固定俯角
const HERO_BAR_CENTER_UP := 4.2                   # 主英雄血条锚点(body_radius1.5*2+1.2)：相机目标上移使血条在屏幕正中
const CAM_FP_EYE := Vector3(0.0, 2.4, 0.0)    # 第一人称眼高（同主机；英雄模型总×3 后约头顶 2/3）
const MM_GAZE_MS := 1200                       # 小地图轻点跳转保持毫秒（主机单击仅一帧，放宽防误触无感）
# 普攻拖拽选敌阈值（与 Hero._handle_attack_wheel_input 同义）
const ATTACK_WHEEL_DRAG_THRESHOLD := 25.0
const KBD_HOVER_RADIUS := 1.2     # 桌面 type0 按住瞄准的候选吸附半径（对齐主机 SKILL_HOVER_LOCK_RADIUS）
const KBD_TAP_MS := 180           # 按住≤该毫秒=点按（退化为智能施放）

var _manifest := {}
var _skills: Array = []   # 从 manifest 解出的技能数组（{name,type,cd,...}）
var _owned := false
var _self_net := -1
var _state := -1
var _own := {}            # 本帧 own 字典（按 manifest.nid 匹配出来的那条）
var _score := {}          # 顶部实时战况（host SNAP_SCORE：pk/ek/pg/eg；对局中常显）
var _respawn_rows: Array = []   # SNAP_RESPAWN：小地图右侧英雄环形头像带行（host _build_respawn_rows）
var _last_snap_time := 0.0
var _rtime := -1.0        # 渲染插值时钟（游戏秒：领先最新快照 INTERP_DELAY，用于其它单位平滑插值）
var _interp_delay := INTERP_DELAY
var _rtime_self := -1.0   # 本机英雄插值时钟（不延迟：点地移动等未预测时保持即时响应，手感不拖）
                          # 相邻两个快照样本之间逐帧匀速扫过，杜绝 15Hz 离散目标"追赶→被拽走"的一顿一顿

var _views := {}          # net_id -> {node, type, team, name, hp, maxhp, bar_off, target, set}
var _health_packs := {}    # key "x_z" -> HealthPack（visual_only，纯表现）
var _health_pack_available := {}
var _residual_vision: Array = []   # 死亡视野残留 [{pos,r,until}]：塔2s / 小兵1s
var _vision_views := {}   # iid -> VisionSpirit（联机客户端表现副本）
var _tower_locks := {}      # 防御塔锁定光束：key(塔位) -> {mesh, from, to, cur, t}
var _map_applied := false
var _resync_timer := 0.0
var _net_dbg: Label = null
var _net_dbg_t := 0.0
var _static_root: Node3D = null
var _camp_rings := []     # 野区营地范围圈 [[环MeshInstance3D, 亮起秒数]]：普通营地 30s 首刷、空间之灵 60s，未到点前隐藏

# —— #42/#43：子弹与 FX 视觉层（纯呈现，不改模拟） ——
var _vis_root: Node3D = null   # 世界空间视觉根（子弹代理 + FX 网格，独立于 Entities 便于管理）
var _bullets := {}             # bullet iid -> {m, px,py,pz, x,y,z, vx,vy,vz, arr_ms, kind}（两帧采样插值）
var _b_pool: Dictionary = {}   # 已回收子弹空闲池：kind -> Array[Node3D]（glb/程序化复用同形状，跨 kind 不复用）
var _fx_seen_fid := {}         # 已实例化的 fx fid（host 缓冲重发去重）
var _fx_seq_last := -1         # 上次应用过的 fx 段 seq
var _fx_live := []             # {n, born_ms, life_ms, kind, r, team}（每帧推进动画/淡出）
# —— #44 events（纯呈现，仿 FX fid 去重；弹出 label 自带 tween，经验珠/错位键在此推进） ——
var _ev_seq_last := -1         # 上次应用过的 events 段 seq
var _ev_seen_fid := {}         # 已消费的 events fid（host 缓冲重发去重）
var _pop_cl: CanvasLayer = null   # 伤害/金币弹出层（CanvasLayer 103，盖过触摸/商店）
var _pop_root: Control = null
var _death_cl: CanvasLayer = null   # 死亡全屏压暗层（同 host UI_Manager.death_overlay：盖 3D+世界血条、不盖面板）
var _death_tint: ColorRect = null
var _pfx_hp: float = -1.0           # PostFX 受击红晕：上一帧 own.hp（-1=未初始化）
var _pop_offsets := {}         # key(0.1 精度 Vector3) -> {"count": int, "ms": int}（同点错开、过期清）
var _exp_orbs := []            # {n: Node3D, nid, tx, tz, spd}（每帧向目标英雄头顶飞行）
var _cam: Camera3D
var _cam_focus := Vector3.ZERO
var _spectate_nid := -1   # 阵亡后点队友头像观战的 net_id（复活自动清空，同 host spectate_hero）
var _cam_yaw := 225.0     # 度数；默认看向对角方向
var _cam_pitch := 42.0
var _cam_dist := 36.0
# 开局镜头拉近（同 host BattleManager._begin_intro）：从高远机位插值回固定跟随位
const CAM_INTRO_DUR := 2.8
var _cam_intro_t := -1.0   # <0 = 尚未开始；>=0 运镜已进行秒数
var _intro_loading = null  # 进场加载层：战场同步+接管+运镜就绪后才淡出
var _mouse_screen := Vector2()
var _pending_skill := -1
var _ret_point := Vector3.ZERO   # 鼠标在地面的交点（画准星）
# 桌面 type0 技能「按住瞄准-松手施放」（对齐主机 Hero 手感）：按下进入瞄准态，按鼠标方向
# 每帧吸附候选（目标与英雄相对角度里方向最近的敌方单位），松手 C_CAST；点按退化为智能施放。
var _kbd_hold_slot := -1
var _kbd_hold_nid := -1
var _kbd_hold_ms := -1

var _hud: Hud
var _status := ""

# —— 接管触摸层（NetTouchPad）与直驱输入状态 ——
var _atk_ring: MeshInstance3D = null   # 本机英雄普攻按住时贴地显示攻击范围圈
var _atk_ring_flash := 0.0               # 空放普攻后短暂显示范围圈的剩余秒数
var _pad: NetTouchPadScript
var _reach := 0.0          # manifest 里的普攻判定距离（米，Hero._aa_engage_reach 同义）
var _d_ax := 0.0           # 上次发送的 C_DRIVE 状态（键盘 x/z + 摇杆 xy + 移动模式）
var _d_az := 0.0
var _d_jx := 0.0
var _d_jy := 0.0
var _d_mode := -99
var _d_last := 0.0         # 墙钟秒：最近一次 C_DRIVE
var _atk_sent := false     # 上次发送的 C_ATTACK_AUTO 状态
var _atk_prev_held := false  # 上一帧普攻是否按住（空放普攻沿检测）
var _atk_last := 0.0       # 墙钟秒：最近一次 C_ATTACK_AUTO
# —— P1b：技能施放翻译状态 ——
var _manual_net := -1      # 本端 C_ATTACK 锁定的目标 net_id（复刻 host manual_target 语义）
var _shen_last := 0.0      # 沈梦溪1技能按住连发心跳墙钟（秒）
# —— P0-C：本机操控英雄移动预测（只位置；伤害/技能仍以主机为准） ——
var _pred_on := false           # 是否处于预测态（接管+存活+非回城）
var _pred_pos := Vector3.ZERO   # 预测位置
var _pred_snap := Vector3.ZERO  # 最近快照里本机英雄位置（校正目标）
var _pred_speed := 380.0        # 预估移速（客户端无 actual_move_speed，用快照位移自校准）
var _pred_sp_pos := Vector3.ZERO  # 上次校准用的快照位置
var _pred_sp_t := 0.0           # 上次校准用的快照时刻
var _pred_err := 0.0            # 最近一次预测与快照的水平误差（米，调试/探针）
var _pred_turn_cd := 0.0        # 转向模式本地转向节流（同 host turn_timer：0.05s/次）
# —— 手感：镜头反馈（同 host BattleManager camera_shake/fov_punch/hitstop/flash_screen） ——
var _shake_amp := 0.0
var _shake_dur := 0.0
var _shake_t := 0.0
var _fov_punch_amp := 0.0
var _fov_punch_dur := 0.0
var _fov_punch_t := 0.0
var _fov_punch_cur := 0.0
var _hitstop_until := 0
var _last_feedback_ms := 0
var _flash_rect: ColorRect = null
var _flash_tween: Tween = null
var _cam_pan := Vector3.ZERO     # 右半屏拖动取景偏移（同 host cam_pan_offset，上限 45m）
var _cam_pan_prev := Vector2.ZERO
var _cam_pan_prev_valid := false
var _cam_pan_decay := false
var _cam_mid_drag := false       # 桌面中键自由镜头拖动中

# —— P2：相机 / 小地图 / 世界血条 ——
var _mm: NetMiniMapScript       # 顶左小地图（CanvasLayer 80，触摸层 100 之下）
var _obj: Array = []             # 目标计时（host own.obj：暴君/主宰 秒数 + 存活标记）
var _jg: Array = []              # 野怪记忆（host own.jg：我方已确认复活的野怪点位）
var _first_person := false      # Tab 第一人称（同主机 BattleManager.first_person_view）
var _mm_gaze_until := 0         # 墙钟 ms：小地图轻点跳转取景保持到何时（到期回正跟随英雄）
# —— P3a：目标信息面板（复刻主机 target_detail_panel；CanvasLayer 55，纯展示）——
var _tp: NetTargetPanelScript
# —— P3b：buff 图标行（复刻主机 collect_buff_rows/BuffIcon；CanvasLayer 60，数据源 own.buffs）——
var _br: NetBuffRowScript
# —— 元流之子·泉水流派切换（复刻主机「流派·切换」钮；CanvasLayer 104，读 own.yl_pick/x/z）——
var _ys: NetYuanliuScript
# 设置面板（音量 / 投降，复刻 host UI_Manager 设置按钮；CanvasLayer overlay）
var _set_layer: CanvasLayer = null
var _set_panel: PanelContainer = null
var _vol_slider: HSlider = null
var _surrender_lab: Label = null
# —— P3c：属性 C / 队伍 T 面板（host _rpc_roster；CanvasLayer 101 盖过触摸层，模态）——
var _rp: NetRosterPanelScript
var _tdv: TeamDecisionViewScript = null
var _tdv_layer: CanvasLayer = null
# —— P3d：商店（host own.gold/equip/rec 喂入；CanvasLayer 102 盖过 C/T 面板）——
var _sp: NetShopPanelScript
# —— P3d+：主界面右上推荐带（own.rb 每帧喂入；CanvasLayer 65）——
var _rb: NetRecommendBarScript
# —— P3e：击杀战报带（host 广播；顶部中央）+ 回城指示（own.recalling/recall_ratio）——
var _kf: NetKillFeedScript
var _rk: NetRecallScript
# —— P3e：死亡回放（host 死亡跃迁推送一次；CanvasLayer 70 盖过战报/回城）——
var _dr: NetDeathRecapScript
var _own_alive_prev := 1     # 上一帧 own.alive：1→0 死亡跃迁时主动向主机补要死亡回放
# —— P3f：结算页（host game_over 广播；CanvasLayer 110 最顶层模态）——
var _go: NetResultPanelScript
# —— P3f：终局演出（与单机同款：聚光灯 V 字舞台 + PostMatchView 铭牌 + 镜头推近 + 个人表现面板）——
var _pm_view: Control = null
var _pm_layer: CanvasLayer = null
var _pm_stage_node: PostMatchStage = null
var _pm_stage_root: Node3D = null
var _pm_hidden_layers: Array = []
var _pm_payload := {}
var _pm_started := false
var _pm_stage := Vector3.ZERO
var _pm_inward := Vector3.ZERO
var _pm_right := Vector3.ZERO
var _pm_env: WorldEnvironment = null
var _pm_key: DirectionalLight3D = null
var _pm_self_name := ""
var _pm_player_node: Node3D = null
# —— 施法预览（按住技能钮/键盘 type0 按住瞄准时显示；世界空间贴地，复刻主机 Hero 预览三件套）——
var _pv_range: MeshInstance3D = null   # 自身施法范围圈（type0/1 用）
var _pv_aoe: MeshInstance3D = null     # AoE 实心填充圆 / type0 瞄准小标记
var _pv_impact: MeshInstance3D = null  # 半径型技能的第二段落点范围（吕布R/太乙Q 等）
var _pv_arrow: Node3D = null           # 线性/位移方向箭头（箭身+箭头）
var _pv_shaft: MeshInstance3D = null
var _pv_head: MeshInstance3D = null
var _pv_aim: Vector3 = Vector3.ZERO    # 最近一帧瞄准落点（供 _handle_skill_release 复算时一致用，纯预览用）
var _pv_color_key := ""

# —— 生命周期 ——
func _ready() -> void:
	add_to_group("net_client_battle")   # ChatService 据此在联机对局挂聊天/语音 UI
	# 进入对局：淡出大厅环境音乐
	SfxManager.stop_menu_music()
	# 客户端用自己的一套 HUD（NetXxx）：关掉主机单例 HUD，避免叠影
	if is_instance_valid(UiManager):
		UiManager.exit_battle()
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	if OS.has_feature("web"):
		_interp_delay = 0.14   # 浏览器经隧道 15Hz 快照：加大回看窗口，避免排队抖动造成一卡一卡
		Vfx.quality = 1
	var world := Node3D.new()
	world.name = "World"
	add_child(world)
	var ents := Node3D.new()
	ents.name = "Entities"
	add_child(ents)
	_vis_root = Node3D.new()
	_vis_root.name = "Vis"
	add_child(_vis_root)
	_build_world()
	_build_camera()
	if OS.has_feature("web"):
		_apply_web_perf()
	_build_hud()
	_build_pad()
	_build_minimap()
	_build_target_panel()
	_build_buff_row()
	_build_yuanliu_switch()
	_build_settings()
	_build_team_decision()
	_build_roster_hit()
	_build_roster_panel()
	_build_shop_panel()
	_build_rec_bar()
	_build_kill_feed()
	_build_recall()
	_build_death_recap()
	_build_result_panel()
	_build_event_layer()
	_build_death_overlay()
	_build_cast_preview()
	NetSession.net_takeover.connect(_on_takeover)
	NetSession.net_snapshot.connect(_on_snapshot)
	NetSession.net_tower_laser.connect(_on_tower_laser)
	NetSession.net_tower_lock.connect(_on_tower_lock)
	NetSession.net_game_over.connect(_on_net_game_over)
	# 场景就绪后主动请求补发地图/接管/首帧快照：Web 端首包或转场期 RPC 可能丢失。
	NetSession.request_battle_resync()
	_mouse_screen = get_viewport().get_mouse_position()
	_status = "已连接，等待接管同队 AI…（由主机分配）"
	# 大厅选人开局：host 的接管 rpc 可能在换场景瞬间先于本场景就绪（信号无人听），
	# 若 NetSession 已缓存 manifest，直接补接管自己在大厅锁定的英雄。
	if not NetSession._manifest.is_empty():
		_on_takeover(NetSession._manifest)
	# 进场加载界面（与单机/主机一致）：在 HUD 全部建好后再盖一层。
	# 关键：不按固定 2.4s 自动消失 —— 主机 manifest/首帧快照可能晚到 1s+，
	# 提前揭开会让镜头先停在地图中央再飞向英雄（用户看到的「跳中心顿一秒」）。
	# 改为 manual_progress：等战场同步 + 接管 + 入场运镜真正开始后再淡出。
	_intro_loading = LoadingScreen.new()
	_intro_loading.setup([], "对局加载中", "联机对局 · 等待同步战场", 2.4)
	_intro_loading.manual_progress = true
	_intro_loading.set_progress(0.06)
	add_child(_intro_loading)

func _process(delta: float) -> void:
	if _hud == null:
		return
	# 地图/接管任一未到就可靠补发，直到服务端状态真正落地（Web 转场期丢包兜底）。
	if not _map_applied or not _owned:
		_resync_timer -= delta
		if _resync_timer <= 0.0:
			_resync_timer = 2.0
			NetSession.request_battle_resync(not _map_applied)
	if _net_dbg != null:
		_net_dbg_t -= delta
		if _net_dbg_t <= 0.0:
			_net_dbg_t = 0.5
			var d := NetSession.debug_net_status()
			_net_dbg.text = "NET mode=%d phase=%d conn=%d fps=%d players=%d map=%dB snaps=%d manifest=%d own=%s map_ok=%s" % [
				int(d.get("mode", -1)), int(d.get("phase", -1)), int(d.get("conn", -1)),
				Engine.get_frames_per_second(), int(d.get("players", 0)), int(d.get("map", 0)), int(d.get("snaps", 0)),
				int(d.get("manifest", 0)), str(_owned), str(_map_applied)]
	_tick_intro_loading()
	_atk_ring_flash = maxf(0.0, _atk_ring_flash - delta)
	if not _map_applied:
		_apply_map_if_ready()
	if _tdv != null and _tdv.visible:
		_tdv.set_data(_team_decision_data())
	_update_atk_ring()
	_update_tower_rings()
	_update_epic_rings()
	# 野区营地范围圈：到出生秒数才亮起（普通 30s / 角落空间之灵 60s），与主机营地在野怪首刷时才出现的节奏一致
	if _state == 1 and not _camp_rings.is_empty():
		for cr in _camp_rings:
			var cr0: MeshInstance3D = cr[0]
			if not cr0.visible and _last_snap_time >= float(cr[1]):
				cr0.visible = true
	_update_tower_locks(delta)
	_update_wukong_clouds(delta)
	_mouse_screen = get_viewport().get_mouse_position()
	if _death_tint != null:
		_death_tint.visible = _owned and int(_own.get("alive", 1)) == 0
	_sync_postfx()
	_tick_feedback(delta)
	_update_cam_pan(delta)
	_hud.fp = _first_person
	_hud.game_time = _last_snap_time
	_hud.vg = _own.get("vg", [])
	_hud.u = _hud_scale()
	if _owned:
		NetSession.ack_takeover_applied()
		if _pending_skill >= 0:
			_ret_point = _ground_hit(_mouse_screen)
	# 实体平滑移动：_rtime 每帧按真实时间推进，封顶 = 最新快照时刻 - INTERP_DELAY（回看 80ms）。
	# WS（TCP）快照会在到达端抖动/成串：若封顶到最新样本，隔帧就会无样本可插值而冻结一下；
	# 回看一个窗口后始终有「下一个样本」，逐帧匀速插值。本机英雄未预测时用 _rtime_self（不延迟）保手感。
	# 单样本位移 > MOVE_JUMP_UNITS 判瞬移/回城/复活直接贴最新不过场。
	if _rtime < 0.0:
		_rtime = maxf(0.0, _last_snap_time - _interp_delay)   # 起步：落后最新样本一个插值窗口
	else:
		_rtime += delta
		var _rt_cap := maxf(0.0, _last_snap_time - _interp_delay)
		if _rtime > _rt_cap:
			_rtime = _rt_cap
	if _rtime_self < 0.0:
		_rtime_self = _last_snap_time
	else:
		_rtime_self += delta
		if _rtime_self > _last_snap_time:
			_rtime_self = _last_snap_time
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.node == null:
			continue
		if not v.set:
			if v.target != null:
				v.node.global_position = v.target
			v.set = true
			continue
		var h: Array = v.get("his", [])
		if h.size() < 2:
			continue
		# 本机英雄未处于输入预测态（点地移动/被控等）时用不延迟的时钟，保持操作即时响应
		var rt := _rtime
		if nid == _self_net and not _pred_on:
			rt = _rtime_self
		var a := 0
		var b := 0
		for i in range(h.size()):
			if float(h[i][0]) <= rt:
				a = i
			else:
				b = i
				break
		if b <= a:
			# 时钟落在历史窗口两端之外（起步 / 快照迟到）：贴窗口内最贴近的一侧样本，防超前跳动
			var L: Array = h[maxi(0, a)]
			v.node.global_position = Vector3(float(L[1]), 0.0, float(L[2]))
			continue
		var pa := Vector3(float(h[a][1]), 0.0, float(h[a][2]))
		var pb := Vector3(float(h[b][1]), 0.0, float(h[b][2]))
		if pa.distance_squared_to(pb) > MOVE_JUMP_UNITS * MOVE_JUMP_UNITS:
			v.node.global_position = pb   # 位移技能/闪现/回城/复活：瞬移不过场
			continue
		var f := 0.0
		var ta := float(h[a][0])
		var tb := float(h[b][0])
		if tb > ta:
			f = clampf((rt - ta) / (tb - ta), 0.0, 1.0)
		v.node.global_position = pa.lerp(pb, f)
		# 筋斗云/腾空：水平位置插值，垂直高度直接取最新快照（避免历史只存 x/z 被压回地面）
		if v.get("target") is Vector3:
			v.node.global_position.y = (v.get("target") as Vector3).y
	# P0-C：本机操控英雄改用「输入积分 + 快照校正」取代插值滞后（其它实体仍是上面的插值）
	_tick_self_prediction(delta)
	# #44 英雄动画：idle/walk 本地按位移切、attack 由 events 触发（须在平滑更新后取位移）
	_tick_hero_anims(delta)
	# #65 单位朝向：小兵/野怪/无动画英雄按位移方向转向（同 host Minion rotation.y=atan2(dir.x,dir.z)）
	_tick_entity_facing(delta)
	# 塔顶晶核自转/浮动 + 塔盾实物模型（与主机 Turret._process 同观感）
	_tick_turret_visuals(delta)
	# 相机聚焦（英雄跟随 / 小地图拖动+轻点覆盖 / Tab 第一人称）
	var want := Vector3.ZERO
	if _owned:
		# 阵亡观战：点队友头像后镜头跟随该队友，自己复活即收回（同 host：点存活队友头像切镜头）
		if int(_own.get("alive", 1)) == 1:
			_spectate_nid = -1
		var sv = _views.get(_self_net)
		if _spectate_nid >= 0 and _views.has(_spectate_nid):
			var tv = _views[_spectate_nid]
			if tv.get("node") != null and is_instance_valid(tv.node):
				want = Vector3(tv.node.global_position.x, 0.0, tv.node.global_position.z)
			sv = null
		if sv != null:
			want = Vector3(sv.node.global_position.x, 0.0, sv.node.global_position.z)
		elif _spectate_nid < 0:
			# 阵亡瞬间英雄被移出 snapshot：沿用 own 最后一次坐标，镜头停在阵亡点不飘走
			want = Vector3(float(_own.get("x", 0.0)), 0.0, float(_own.get("z", 0.0)))
	if _owned and _first_person:
		if int(_own.get("alive", 1)) != 1:
			_first_person = false   # 阵亡自动退回第三人称（同主机 _set_camera_mode(false)）
		else:
			_cam_focus = want       # 第一人称贴脸跟随，不参与 lerp
	elif _owned:
		var mm_now := Time.get_ticks_msec()
		if _mm != null and _mm.panning:
			# 按住小地图拖动取景：镜头随拖动平移（host 为即时硬设），松手回正跟随英雄
			_cam_focus = Vector3(_mm.pan_world.x, 0.0, _mm.pan_world.z)
		elif _mm != null and _mm.gaze_ready:
			_mm_gaze_until = mm_now + MM_GAZE_MS
			var g: Vector3 = _mm.take_gaze()
			_cam_focus = Vector3(g.x, 0.0, g.z)
		elif _mm_gaze_until <= mm_now:
			# 跟随手感同 host：指数平滑 12/s，目标跳变 >25m 直接硬设（小地图跳转/复活传送）
			if _cam_focus.distance_to(want) > 25.0:
				_cam_focus = want
			else:
				_cam_focus = _cam_focus.lerp(want, 1.0 - exp(-12.0 * delta))
	elif _last_snap_time <= 0.0:
		if _cam_focus.distance_to(want) > 25.0:
			_cam_focus = want
		else:
			_cam_focus = _cam_focus.lerp(want, 1.0 - exp(-12.0 * delta))
	# 第一人称：隐藏自身模型防挡视线（同主机隐藏 visual_mesh）；退出后恢复
	if _owned:
		var sv2: Dictionary = _views.get(_self_net, {})
		if sv2.has("node") and sv2.node != null:
			sv2.node.visible = not _first_person
	_update_camera()
	# 逆光：主光始终在相机水平正前方，补光在相机后方（与 host BattleManager 同源）
	MapVisuals.update_backlight_for_camera(_cam)
	# 小地图数据每帧喂入（引用式共享 views，纯展示不改模拟）
	if _mm != null:
		_mm.visible = _owned   # 未接管的观战棋盘期先不叠小地图
		_mm.player_team = Config.player_team
		_mm.self_net = _self_net
		_mm.views = _views
		_mm.residual_vision = _prune_residual_vision()
		_mm.active = _owned and _state == 1 and not _first_person
		_mm.obj = _obj
		_mm.jg = _jg
		# 全图技能弹（后羿R / 鲁班2）：按弹体实际位置在小地图上画
		_mm.shot_bullets = _mm_global_bullet_rows()
		if _owned:
			_mm.own_pos = _self_pos()
			_mm.own_recalling = int(_own.get("recalling", 0))
		else:
			_mm.own_pos = Vector3.ZERO
			_mm.own_recalling = 0
	# —— 世界血条：锚点→屏幕（同主机 HUD._update_health_bars：死亡隐藏 / 相机背后剔除 / 屏幕固定尺寸）——
	_hud.wrows = _collect_world_bars()
	# —— #42/#43：子弹外推 + FX 动画（观战/接管都播，纯视觉） ——
	_tick_visuals(delta)
	# HUD 快照数据
	if _owned:
		var hp := float(_own.get("hp", 0.0))
		var maxhp := float(_own.get("maxhp", 1.0))
		var mana := float(_own.get("mana", 0.0))
		var maxmana := float(_own.get("maxmana", 1.0))
		_hud.hp = hp
		_hud.maxhp = maxhp
		_hud.mana = mana
		_hud.maxmana = maxmana
		_hud.level = int(_own.get("level", 1))
		_hud.gold = int(_own.get("gold", 0))
		_hud.sp = int(_own.get("sp", 0))
		_hud.name_text = str(_own.get("name", "英雄"))
		_hud.owned = true
		if _tp:
			_tp.refresh(_own.get("tgt", []))   # P3a 目标信息面板（host 实时摘要）
		if _br:
			_br.refresh(_own.get("buffs", {}))   # P3b buff 图标行（host own.buffs）
		if _ys:
			_ys.feed(_own)   # 元流之子·流派切换钮（own 含 name/x/z/team/yl_pick）
		if _sp:
			_sp.feed(_own)   # P3d 商店 gold/equip/rec（visible 时 _process 每帧重绘刷新金币）
		if _rb:
			_rb.feed(_own)   # P3d+ 主界面右上推荐带（own.rb 烘焙 text/cost/show）
		if _rk:
			_rk.feed(int(_own.get("recalling", 0)), float(_own.get("recall_ratio", 0.0)))   # P3e 回城进度
		if _dr:
			_dr.feed_alive(int(_own.get("alive", 1)))   # P3e 复活时复位死亡回放
		var lv := int(_own.get("level", 1))
		var alive := int(_own.get("alive", 1))
		if alive == 0:
			_hud.status = ""   # 主机阵亡只有全屏压暗+死亡回放，无顶部提示文字
		elif lv < 0:
			_hud.status = ""
		else:
			_hud.status = ""
		var cds: Array = _own.get("cd", [])
		_hud.skills = []
		for i in range(3):
			var cd_max := 0.0
			if i < _skills.size():
				cd_max = float(_skills[i].get("cd", 0))
			var cd_cur := 0.0
			if i < cds.size():
				cd_cur = float(cds[i])
			_hud.skills.append({
				"name": _skill_disp(i),
				"cd": cd_cur, "cdmax": cd_max,
				"pending": _pending_skill == i,
			})
		_hud.reticle = _project_point(_ret_point) if _pending_skill >= 0 else Vector2(-9999.0, -9999.0)
		# 属性面板：own.sa = 18 行 [基础,装备,Buff] 三元组（顺序同 UiManager.ATTRIBUTE_ROWS）
		_hud.sa = _own.get("sa", [])
		# 主界面个人 K/D/A（own.kills/deaths/assists，同 host kda_label）
		_hud.kda = [int(_own.get("kills", 0)), int(_own.get("deaths", 0)), int(_own.get("assists", 0))]
		var wr: Array = []
		for rrow in _respawn_rows:
			if not (rrow is Array) or (rrow as Array).size() < 8:
				continue
			var rt := int((rrow as Array)[1])
			var rdead := int((rrow as Array)[7]) == 1
			if rt == int(Config.player_team) or rdead:
				wr.append(rrow)
		_hud.widget_rows = wr
		_hud.show_widget = _state == 1 and not _respawn_rows.is_empty()
	else:
		_hud.sa = []
		_hud.kda = []
		_hud.widget_rows = []
		_hud.show_widget = false
		_hud.owned = false
		_hud.status = _status
		if _tp:
			_tp.refresh([])   # 未接管/阵亡后不再显示目标面板
		if _br:
			_br.refresh({})   # 未接管/阵亡后 buff 行清空
		if _ys:
			_ys.feed({})   # 未接管/阵亡后流派切换钮隐藏
		if _sp:
			_sp.hide_panel()   # 未接管/阵亡后商店关闭
		if _rb:
			_rb.hide_panel()   # 未接管后推荐带隐藏
		if _rk:
			_rk.feed(0, 0.0)   # 未接管/阵亡后回城条隐藏
		if _dr:
			_dr.feed_alive(1)   # 未接管时死亡回放不弹
	# —— 接管触摸层：可见性跟随全局 F2 开关，接管且对局中才采集并翻译输入 ——
	if _pad:
		_pad.touch_active = TouchController.touch_active
		var show_pad := _owned and _state == 1 and TouchController.touch_active
		_pad.visible = show_pad
		if show_pad:
			_poll_touch_input()
			_update_skill_pad()
			_poll_skill_input()
			_update_aux_pad()
			_poll_aux_input()
			_pad.refresh_cancel_aim()
			# M4-U：普攻键读数（伤害/攻速/强化态 + 装备被动小字行，host _push_attack_stats 同款内容）
			_pad.set_attack_state(_own.get("aa", []) if _own != null else [])
			_pad.set_enemy_picker(_enemy_picker_list())
		if _hud:
			# 触控模式隐藏底部右侧旧的 1/2/3 预选技能栏（主机触控同样让旧技能条退场，以触摸层为准）
			_hud.pad_active = show_pad
	# 顶部实时战况（击杀比分+经济比分）：对局中常显（含接管前观战）
	_hud.sc = _score if (_owned or _self_net >= 0) and _state == 1 and not _score.is_empty() else {}
	_hud.queue_redraw()
	# 施法预览：按住技能钮瞄准中显示（世界空间贴地，取自已施放预检同款门禁）
	_update_cast_preview()

# —— 快照 → 实体池 ——
func _on_snapshot(snap: Array) -> void:
	_state = int(snap[SNAP_STATE])
	_last_snap_time = float(snap[SNAP_TIME])
	# 渲染时钟起步/卡顿恢复/中途入场：落后最新样本超 0.25s 直接对齐（不逐帧补播历史轨迹，防实体滞留 0.53s 滞后窗口）
	if _rtime < _last_snap_time - 0.25:
		_rtime = maxf(0.0, _last_snap_time - _interp_delay)
	if _rtime_self < _last_snap_time - 0.25:
		_rtime_self = _last_snap_time
	var own_dict: Dictionary = snap[SNAP_OWN]
	if _owned:
		for pid in own_dict:
			var ent: Dictionary = own_dict[pid]
			if int(ent.get("nid", -1)) == _self_net:
				_own = ent
				if ent.has("obj"):
					_obj = ent["obj"]
				if ent.has("jg"):
					_jg = ent["jg"]
				break
	var seen := {}
	var lists := [
		[NET_HERO, snap[SNAP_HEROES]],
		[NET_MINION, snap[SNAP_MINIONS]],
		[NET_TURRET, snap[SNAP_TURRETS]],
		[NET_JUNGLE, snap[SNAP_JUNGLES]],
	]
	for pair in lists:
		var typ: int = pair[0]
		var arr: Array = pair[1]
		for ent in arr:
			var nid := int(ent[0])
			var team := int(ent[2])
			var pos := Vector3(float(ent[3]), 0.0, float(ent[4]))
			var hp := float(ent[5])
			var maxhp := float(ent[6])
			# P0-C：本机英雄的最新权威位置 → 预测校正目标 + 移速自校准
			if nid == _self_net:
				_pred_snap = pos
				_calibrate_pred_speed(pos)
			# 名字字段：hero 元组 idx8（idx7 是等级），其他实体 idx7
			var name := ""
			if typ == NET_HERO and ent.size() > 8:
				name = str(ent[8])
			elif ent.size() > 7:
				name = str(ent[7])
			seen[nid] = true
			var v = _views.get(nid)
			if v == null:
				v = _make_view(nid, typ, team, name)
				_views[nid] = v
				if typ == NET_TURRET:
					_add_turret_pave(pos, name, team)
			v.type = typ
			v.team = team
			if typ == NET_HERO:
				if ent.size() > 26:
					pos.y = float(ent[26])   # 筋斗云/腾空高度
				v.pname = str(ent[17]) if ent.size() > 17 else ""
				v.mvp = int(ent[18]) == 1 if ent.size() > 18 else false
				v.status = ent[19] if ent.size() > 19 else []
				v.markers = ent[20] if ent.size() > 20 else []          # 标记图标行（专属图标+层数）
				v.ai_chip = ent[21] if ent.size() > 21 else []          # AI 决策胶囊 [label,r,g,b]
				v.role = str(ent[22]) if ent.size() > 22 else ""        # 职责（T 面板）
				v.lane_assigned = int(ent[23]) if ent.size() > 23 else -1  # 战术分路
				if ent.size() > 27:
					v.armor = float(ent[27])   # 护甲（补刀提示）
				if ent.size() > 28:
					var _skin := str(ent[28])
					if _skin != "" and str(v.get("skin", "")) != _skin:
						v["skin"] = _skin
						var _mdl = v.get("model")
						if _mdl != null and is_instance_valid(_mdl):
							HeroSkinTable.apply_to(_mdl, name, _skin)
			if typ != NET_HERO and typ != NET_TURRET and ent.size() > 14:
				v.armor = float(ent[14])   # 小兵/野怪护甲（补刀提示）
			# 受击模型反馈（同 host GameEntity._damage_feedback：闪白+脉冲；英雄加后仰；70ms 节流）
			if hp < float(v.get("prev_hp", hp)) - 0.5:
				_net_hit_flash(v)
			if typ == NET_JUNGLE:
				if hp < float(v.get("prev_hp", hp)) - 0.5:
					v["hit_t"] = _last_snap_time
				v["prev_hp"] = hp
			elif typ != NET_HERO:
				v["prev_hp"] = hp
			v.hp = hp
			v.maxhp = maxhp
			v.target = pos
			# 渲染插值：按游戏时间保留本实体快照位置历史（[t,x,z]，升序），供 _process 匀速线性插值
			# （15Hz 离散步进 → 视觉连续；旧版对最新目标每帧指数逼近会"减速→被拽走"一顿一顿）
			var his: Array = v.get("his", [])
			his.append([_last_snap_time, pos.x, pos.z])
			if his.size() > 8:
				his.pop_front()
			v.his = his
			# P2 尾字段：hero idx9..13 = mana/maxmana/shield/exp/exp_to_next；turret idx8 = 被攻击标记
			# 暗印摘要 lyf（数组，长度守卫防旧host）：hero idx14 / 塔 idx9 / 兵&野 idx8
			if typ == NET_HERO:
				v.level = int(ent[7])
				if ent.size() > 13:
					v.mana = float(ent[9])
					v.maxmana = float(ent[10])
					v.shield = float(ent[11])
					v.exp = float(ent[12])
					v.exp_to_next = float(ent[13])
				if ent.size() > 14:
					v.lyf = ent[14]
				# idx15：朝向（弧度）供客户端小地图画朝向箭头
				if ent.size() > 15:
					v.rot = float(ent[15])
				# idx16：草丛隐藏（主机 hidden_in_bush）→ 客户端血条上方画“隐”图标
				if ent.size() > 16:
					v.hidden = int(ent[16]) == 1
				# idx24/25：红/蓝 buff 状态 → 世界模型脚下光环（同单机）
				if ent.size() > 24:
					_set_buff_ring(v, 0, int(ent[24]) == 1)
				if ent.size() > 25:
					_set_buff_ring(v, 1, int(ent[25]) == 1)
			elif typ == NET_TURRET:
				if ent.size() > 8:
					v.under_attack = int(ent[8])
				if ent.size() > 9:
					v.lyf = ent[9]
				# idx10 范围环状态（0红/1绿/2黄）：同步主机塔环配色；旧 host 无则保持默认黄
				if ent.size() > 10:
					_set_tower_ring_color(v, int(ent[10]))
				# idx11：塔分级（客户端小地图形状）
				if ent.size() > 11:
					v.ttype = str(ent[11])
				# idx12/13：塔盾激活状态与盾量（旧 host 无此字段）
				if ent.size() > 12:
					v.tower_shield_active = int(ent[12]) == 1
				if ent.size() > 13:
					v.tower_shield = float(ent[13])
				if ent.size() > 14:
					v.shield_icon = int(ent[14]) == 1
				if ent.size() > 15:
					v.armor = float(ent[15])   # 塔护甲（补刀提示）
				# 倒塌：host 在 dying_visual 期间仍广播 hp=0 的塔 → 本地复刻坍塌动画
				if float(v.get("hp", 1.0)) <= 0.0 and not v.get("dying", false):
					v.dying = true
					var sf2 := 1.9 if str(v.get("name", "")) == "crystal" else 1.6
					Turret.play_collapse(v.node, sf2, v.node.get_parent())
					Vfx.shockwave(v.node.global_position + Vector3(0, 0.25, 0), 3.2 * sf2, Color(0.74, 0.70, 0.64), 0.8)
					Vfx.hit_spark(v.node.global_position + Vector3.UP * 1.4 * sf2, Color(1.0, 0.76, 0.42), Vector3.UP, 1.8)
					# 与单机 TurretWreck 同款的灰色残骸减速环（客户端只复刻视觉，减速仍由 host 结算）
					if str(v.get("name", "")) != "crystal":
						_spawn_tower_wreck_visual(v.node.global_position, int(v.team))
					if int(v.team) == int(Config.player_team):
						_add_residual_vision(v.node.global_position, 18.0, 2.0)
					v.dying_until = Time.get_ticks_msec() + 2400
			elif ent.size() > 8:
				v.lyf = ent[8]
				if ent.size() > 9:
					v.mk = ent[9]
				# idx10/11（host 追加）：朝向 + 正在攻击 → 客户端即使没收到 act 事件也能转向/出攻击动作
				if typ == NET_MINION or typ == NET_JUNGLE:
					if ent.size() > 10:
						v.face_yaw = float(ent[10])
						if v.node != null and is_instance_valid(v.node):
							v.node.rotation.y = float(v.face_yaw)
					if ent.size() > 12:
						var aseq := int(ent[12])
						if not v.has("atk_seq"):
							v["atk_seq"] = aseq          # 首帧只记录，不补动作
						elif aseq != int(v["atk_seq"]):
							v["atk_seq"] = aseq
							_v_unit_attack_now(v)        # 服务器真出手了才播，节奏严格一致
						if ent.size() > 13:
							v["atk_int"] = float(ent[13])
					elif ent.size() > 11 and int(ent[11]) == 1:
						_v_snap_unit_attack(v)   # 旧版 host 无序号：保留兜底
			if not v.set:
				v.node.global_position = pos
				v.set = true
	# 先处理本帧 events：死亡 ACT_DIE 会设置 dying_until，随后剔除阶段才能保留死亡动画。
	# 之前 events 在剔除之后处理，小兵/野怪死亡帧会先被 queue_free，死亡动作永远看不到。
	if snap.size() > SNAP_EVENTS:
		_apply_events(snap)
	# 剔除本帧不在的实体（死亡动作播放中的先留着，播完再释放）
	var now_ms := Time.get_ticks_msec()
	for nid in _views.keys():
		if not seen.has(nid):
			var v: Dictionary = _views[nid]
			if now_ms < int(v.get("dying_until", 0)):
				continue
			# 己方小兵死亡后保留 1 秒原位置视野（塔由倒塌分支单独记 2 秒）
			if int(v.get("type", -1)) == NET_MINION and int(v.get("team", -1)) == int(Config.player_team):
				var mp = v.get("target", null)
				if mp is Vector3:
					_add_residual_vision(mp, 9.0, 1.0)
			# 小兵/龙兵：先播放 host 同款「倒地后缓缓沉入地下」再释放（此前直接 queue_free，看起来凭空消失）
			if int(v.get("type", -1)) == NET_MINION and not bool(v.get("sinking", false)):
				var mn := str(v.get("name", ""))
				var depth: float = 2.4 if mn in ["dragon", "storm", "shadow_dragon"] else 1.5
				var nd = v.get("node")
				if nd != null and is_instance_valid(nd):
					v["sinking"] = true
					var tw2 := create_tween()
					tw2.tween_interval(0.62)   # 同 host Minion._start_sink_away：先倒地
					tw2.tween_property(nd, "position:y", (nd as Node3D).position.y - depth, 0.88) \
						.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
					tw2.tween_callback(nd.queue_free)
				_views.erase(nid)
				continue
			if v.node != null and is_instance_valid(v.node):
				v.node.queue_free()
			_views.erase(nid)
	# #42/#43：子弹与 FX 视觉段（纯呈现；host v5 才有，长度守卫防旧 host 兼容）
	if snap.size() > SNAP_BULLETS:
		_apply_bullets(snap)
	if snap.size() > SNAP_FX:
		_apply_fx(snap)
	# 顶部实时战况（host v6 idx10 全量统计）→ 击杀比分+经济比分
	_check_own_death_recap()
	if snap.size() > SNAP_SCORE:
		_score = snap[SNAP_SCORE]
	else:
		_score = {}
	# 小地图右侧英雄环形头像带（host v6 idx11）→ 每帧快照存最新行
	if snap.size() > SNAP_RESPAWN:
		_respawn_rows = snap[SNAP_RESPAWN]
	else:
		_respawn_rows = []
	if snap.size() > SNAP_VISION:
		_apply_vision_spirits(snap[SNAP_VISION])
	else:
		_apply_vision_spirits([])
	if snap.size() > SNAP_HEALTH_PACKS:
		_apply_health_packs(snap[SNAP_HEALTH_PACKS])
	else:
		_apply_health_packs([])
	if snap.size() > SNAP_SKILL_REVEALS:
		_mm.skill_reveal_rows = snap[SNAP_SKILL_REVEALS]
	else:
		_mm.skill_reveal_rows = []
	_update_dead_corpses(snap[SNAP_DEAD_HEROES] if snap.size() > SNAP_DEAD_HEROES else [])

# 阵亡英雄尸体：保留倒地模型直到复活（host 快照 SNAP_DEAD_HEROES 段）
var _corpses: Dictionary = {}   # nid -> Node3D

func _update_dead_corpses(rows: Array) -> void:
	var alive := {}
	for nid in _views.keys():
		alive[int(nid)] = true
	var want := {}
	for r in rows:
		if not (r is Array) or r.size() < 6:
			continue
		var nid := int(r[0])
		if nid <= 0 or alive.has(nid):
			continue
		want[nid] = true
		var node: Node3D = _corpses.get(nid)
		if node == null or not is_instance_valid(node):
			var ents := get_node_or_null("Entities")
			if ents == null:
				continue
			node = Node3D.new()
			node.name = "Corpse_%d" % nid
			var hm := NetModels.hero(str(r[5]))
			if hm != null:
				node.add_child(hm)
			ents.add_child(node)
			_corpses[nid] = node
		node.position = Vector3(float(r[2]), 0.0, float(r[3]))
		node.rotation = Vector3(-PI * 0.5, float(r[4]), 0.0)
	for nid in _corpses.keys():
		if not want.has(int(nid)) or alive.has(int(nid)):
			var nd = _corpses[int(nid)]
			if nd != null and is_instance_valid(nd):
				nd.queue_free()
			_corpses.erase(nid)

func _apply_health_packs(rows: Array) -> void:
	_health_pack_available.clear()
	for row in rows:
		if not (row is Array) or (row as Array).size() < 4:
			continue
		var hp_x := float(row[0])
		var hp_z := float(row[1])
		var key := "%d_%d" % [int(round(hp_x * 10.0)), int(round(hp_z * 10.0))]
		var pack = _health_packs.get(key, null)
		if pack == null or not is_instance_valid(pack):
			pack = HealthPack.new()
			pack.visual_only = true
			pack.team = int(row[2])
			pack.position = Vector3(hp_x, 0.3, hp_z)
			_static_root.add_child(pack)
			_health_packs[key] = pack
		var avail := int(row[3]) == 1
		var cd_left := float(row[4]) if row.size() > 4 else 0.0
		var cd_total := float(row[5]) if row.size() > 5 else 75.0
		pack.apply_remote_state(avail, cd_left, cd_total)
		_health_pack_available[key] = avail
	if _mm != null:
		_mm.health_pack_available = _health_pack_available


func _apply_vision_spirits(rows: Array) -> void:
	if _mm != null:
		_mm.vision_rows = rows
	if _vis_root == null:
		return
	var seen := {}
	for row in rows:
		var sid := int(row[0])
		seen[sid] = true
		var v = _vision_views.get(sid)
		if v == null or not is_instance_valid(v):
			v = VisionSpiritScript.new()
			v.client_mode = true
			_vis_root.add_child(v)
			_vision_views[sid] = v
		v.apply_net_state(Vector3(float(row[1]), 0.0, float(row[2])),
			int(row[3]) == 1, float(row[4]), int(row[5]))
	for sid in _vision_views.keys():
		if seen.has(sid):
			continue
		var old = _vision_views[sid]
		if is_instance_valid(old):
			old.queue_free()
		_vision_views.erase(sid)

# —— #42 子弹代理：host 每帧弹体列表 → 客户端 MeshInstance3D 池；两帧采样速度外推，视觉平滑 ——
func _apply_bullets(snap: Array) -> void:
	var arr: Array = snap[SNAP_BULLETS]
	var now := Time.get_ticks_msec()
	var seen := {}
	for row in arr:
		var bid := int(row[0])
		var bx := float(row[1])
		var by := float(row[2])
		var bz := float(row[3])
		var team := int(row[4])
		# idx8：全图技能弹标记（1=后羿R / 2=鲁班2）；旧 host 无此列
		var gsf := int(row[8]) if row.size() > 8 else 0
		seen[bid] = true
		var b = _bullets.get(bid)
		if b == null:
			# 弹体 kind：host v6 idx6 真模型档位；旧 host idx5 是 size（2=后羿R→kind4）。
			# idx7 定制视觉 vkind（v7）：>0 的 host 技能弹换过默认弹体 → 1000+vkind 定制档复刻原形。
			var bkind := int(row[6]) if row.size() > 6 else (4 if int(row[5]) >= 2 else int(row[5]))
			var vkind := int(row[7]) if row.size() > 7 else 0
			var bflags := int(row[9]) if row.size() > 9 else 0
			var bacc := Color(0, 0, 0, 0)
			if row.size() > 12:
				bacc = Color(float(row[10]), float(row[11]), float(row[12]))
			var vis_id := (1000 + vkind) if vkind > 0 else bkind
			b = _obtain_bullet(team, vis_id, bflags)
			b["skin_accent"] = bacc
			var _bm = b.get("m")
			if _bm != null and is_instance_valid(_bm):
				if bacc.a > 0.0:
					HeroSkinTable.apply_fx_color(_bm, bacc)
				else:
					HeroSkinTable.clear_fx_color(_bm)
			b.x = bx; b.y = by; b.z = bz
			b.px = bx; b.py = by; b.pz = bz
			b.arr_ms = now
			b.gs = gsf
			_bullets[bid] = b
			var m0: Node3D = b.m as Node3D
			if m0 != null:
				m0.global_position = Vector3(bx, by, bz)
			continue
		# 已有弹体：用上一采样位置与到达间隔算外推速度
		var dt_s := (now - int(b.arr_ms)) * 0.001
		if dt_s > 0.001:
			b.vx = (bx - float(b.x)) / dt_s
			b.vy = (by - float(b.y)) / dt_s
			b.vz = (bz - float(b.z)) / dt_s
		b.px = float(b.x); b.py = float(b.y); b.pz = float(b.z)
		b.x = bx; b.y = by; b.z = bz
		b.team = team
		b.arr_ms = now
		b.gs = gsf
		if row.size() > 12:
			var _new_acc := Color(float(row[10]), float(row[11]), float(row[12]))
			if Color(b.get("skin_accent", Color(0, 0, 0, 0))) != _new_acc:
				b["skin_accent"] = _new_acc
				var _bm2 = b.get("m")
				if _bm2 != null and is_instance_valid(_bm2):
					if _new_acc.a > 0.0:
						HeroSkinTable.apply_fx_color(_bm2, _new_acc)
					else:
						HeroSkinTable.clear_fx_color(_bm2)
		if row.size() > 9:
			b["flags"] = int(row[9])
		_bullets[bid] = b
	# 消失剔除（Mesh 回池复用，避免每帧 new/free）
	for bid in _bullets.keys():
		if not seen.has(bid):
			var bb: Dictionary = _bullets[bid]
			# 全图技能弹消失 → 若消失点贴着某个敌方英雄，给小地图打命中反馈
			var gs := int(bb.get("gs", 0))
			if gs > 0 and _mm != null:
				var bpos := Vector3(float(bb.x), float(bb.y), float(bb.z))
				var best_id := -1
				var best_d := 6.0
				for nid in _views:
					var hv: Dictionary = _views[nid]
					if int(hv.get("type", -1)) != NET_HERO or float(hv.get("hp", 0.0)) <= 0.0:
						continue
					var hd: float = _view_pos(hv).distance_to(bpos)
					if hd < best_d:
						best_d = hd
						best_id = int(nid)
				if best_id >= 0:
					_mm.shot_hits[best_id] = [Time.get_ticks_msec(), gs]
			_release_bullet(bb)
			_bullets.erase(bid)


# 小地图用：全图技能弹 [世界坐标, 飞行方向, 类型(1=后羿R/2=鲁班2)]
func _mm_global_bullet_rows() -> Array:
	var out: Array = []
	for bid in _bullets:
		var b: Dictionary = _bullets[bid]
		var gs := int(b.get("gs", 0))
		if gs <= 0:
			continue
		out.append([Vector3(float(b.x), float(b.y), float(b.z)),
			Vector3(float(b.vx), 0.0, float(b.vz)), gs])
	return out


func _add_residual_vision(pos: Vector3, radius: float, life: float) -> void:
	_residual_vision.append({
		"pos": Vector3(pos.x, 0.0, pos.z), "r": radius,
		"until": Time.get_ticks_msec() * 0.001 + life,
	})


func _prune_residual_vision() -> Array:
	var now := Time.get_ticks_msec() * 0.001
	var keep: Array = []
	for d in _residual_vision:
		if float(d.get("until", 0.0)) > now:
			keep.append(d)
	_residual_vision = keep
	return _residual_vision


func _spawn_tower_wreck_visual(pos: Vector3, team: int) -> void:
	var root := Node3D.new()
	root.name = "TowerWreck"
	root.position = Vector3(pos.x, 0.05, pos.z)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 8.75
	torus.outer_radius = 9.05
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.5, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	root.add_child(ring)
	_static_root.add_child(root)
	# host 的 TurretWreck 只存在 3 秒
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())


func _obtain_bullet(team: int, kind: int, flags: int = 0) -> Dictionary:
	var m: Node3D = null
	var pool: Array = _b_pool.get(kind, [])
	if not pool.is_empty():
		m = pool.pop_back()
		m.visible = true
	else:
		m = _make_bullet_visual(kind, team, flags)
		_vis_root.add_child(m)
	return {"m": m, "x": 0.0, "y": 0.0, "z": 0.0,
		"px": 0.0, "py": 0.0, "pz": 0.0,
		"vx": 0.0, "vy": 0.0, "vz": 0.0,
		"arr_ms": 0, "team": team, "kind": kind}


# 按 kind 还原 host 真模型（kind 0→弹石 / 1→弹丸×3 / 2→弓箭 / 3→炮弹 / 4→后羿R 太阳火箭自组）。
# kind>=1000 为定制视觉（v7 idx7 vkind，host 换过默认弹体的技能弹），派发到 _make_bullet_bespoke。
# 路径缺失时回退旧圆柱（保留队伍色近似），与 host Bullet.gd 的回退球体同一思路。
func _make_bullet_visual(kind: int, team: int = 0, flags: int = 0) -> Node3D:
	# 三端共享：kind 0..3 模型档 / 4 后羿R / 5 塔能量球 / 1000+vkind 定制档，全部走 ProjectilePresenter
	# 防御塔能量球在单机里是 Bullet.radius(默认0.2) 再 ×source_scale(3)；客户端 kind=5
	# 之前只传 0.15，实际球体只有单机 1/4 大，几乎看不见。
	var rr := 0.6 if kind == 5 else 0.15
	return ProjectilePresenter.make(kind, team, 0, rr, flags)



func _make_bullet_bespoke(vkind: int) -> Node3D:
	return ProjectilePresenter.make_bespoke(vkind)



func _release_bullet(b: Dictionary) -> void:
	var m: Node3D = b.m as Node3D
	if m != null and is_instance_valid(m):
		m.visible = false
	var kind := int(b.get("kind", 0))
	if not _b_pool.has(kind):
		_b_pool[kind] = []
	_b_pool[kind].append(m)


# —— #43 FX：快照 fx 段 → 本地视觉 catalog（kind 档位与 NetSession 快照约定对齐） ——
func _apply_fx(snap: Array) -> void:
	var seg: Array = snap[SNAP_FX]
	if seg.is_empty():
		return
	var seq := int(seg[SNAP_FX_SEQ])
	if seq == _fx_seq_last:
		return
	_fx_seq_last = seq
	var now := Time.get_ticks_msec()
	for i in range(1, seg.size()):
		var row: Array = seg[i]
		var fid := int(row[FX_ROW_FID])
		if _fx_seen_fid.has(fid):
			continue
		var kind := int(row[FX_ROW_KIND])
		var p := Vector3(float(row[FX_ROW_X]), float(row[FX_ROW_Y]), float(row[FX_ROW_Z]))
		var team := int(row[FX_ROW_TEAM])
		var rr := float(row[FX_ROW_R])
		var life := float(row[FX_ROW_LIFE])
		if life <= 0.0:
			life = 0.5
		var caster := str(row[9]) if row.size() > 9 else ""
		# 完整技能事件：直接复用单机 Vfx.play_spell（签名大招/元素爆发/技能道具全同款）
		if kind == FX_SPELL_FULL and row.size() >= 24:
			_spawn_full_spell_fx(row, caster)
			if caster != "":
				var _acc := _skin_accent_for_caster(caster)
				if _acc.a > 0.0:
					Vfx.skin_spell_burst(p, _acc)
			_fx_seen_fid[fid] = true
			continue
		# 旧版/其他技能类：直接调用 host 同款 Vfx 原语（cast_burst / cast_glow / shockwave / pillar）
		if kind == FX_SKILL_BURST or kind == FX_SKILL_DASH or kind == FX_SKILL_ULT \
				or kind == FX_SKILL_GLOW or kind == FX_PILLAR:
			_spawn_host_skill_fx(kind, Vfx.ground_pos(p), team, rr, life, caster)
			_fx_seen_fid[fid] = true
			continue
		var n: Node3D = _build_fx(kind, team, rr, life, caster)
		# 主机推送的贴地特效 y 可能为 0；客户端统一抬到所有地面类型之上
		n.position = Vfx.ground_pos(p)
		_vis_root.add_child(n)
		_fx_live.append({"n": n, "born_ms": now, "life_ms": life * 1000.0, "kind": kind, "r": rr, "team": team})
		_fx_seen_fid[fid] = true
	if _fx_seen_fid.size() > 512:
		_fx_seen_fid.clear()   # fid 单调递增；清掉旧键不会再撞（0.35s 缓冲早已播完）


# FX catalog：按 kind 还原 host 各 helper 的硬编码色/形/生命周期语义（值取自 SkillDataBase）。
# zone 类（spell 地面圈/地形/水域/风暴/元流池）= 落位即满尺寸、整段存在、末段淡出；
# one-shot 类（水花/水浪冲击/后羿爆炸）= 由小扩散 + 中段淡出。
func _build_fx(kind: int, team: int, r: float, life: float = 0.0, caster: String = "") -> Node3D:
	var root := Node3D.new()
	# 持续地面区域（王昭君暴风雪/吕布魔神法阵/亚瑟圣印/甄姬水域/元芳风暴/元流池）：
	# 直接用 host 同款 Vfx.ground_zone（同一 shader 法阵 + 元素装饰 + 末段淡出）
	if kind == FX_SPELL or kind == FX_WATER_ZONE or kind == FX_LYF_STORM or kind == FX_YL_POOL:
		root.add_child(Vfx.ground_zone(maxf(r, 0.15), team, caster, life))
		return root
	var mats: Array = []
	var team_col := COL_ENEMY if (team == 0 or team == 1) and not Config.is_ally(team) else COL_ALLY_DIM
	# 技能视觉（host VfxFactory 插桩）：元素色优先，缺失用阵营色（≤2 MeshInstance）
	if kind == FX_SKILL_BURST or kind == FX_SKILL_DASH or kind == FX_SKILL_ULT \
			or kind == FX_SKILL_GLOW or kind == FX_PILLAR:
		return _build_skill_fx(kind, team, r, caster)
	if kind == FX_MACHAO_SPEAR:
		var spear := HeroWeapons.spear_marker(team)
		root.add_child(spear)
		root.set_meta("mats", spear.get_meta("mats", []))
		return root
	if kind == FX_HOUYI_EXPLODE:
		var glow: MeshInstance3D = MeshFactory.create_sphere(0.8, Color(1.0, 0.6, 0.0, 0.7), true, 0.7)
		glow.position.y = 0.6
		root.add_child(glow)
		mats.append(glow.material_override)
		var ring: MeshInstance3D = MeshFactory.create_torus_ring(0.3, 0.5, Color(1.0, 0.5, 0.0), true, 1.0, true)
		ring.rotation.x = deg_to_rad(90)
		ring.position.y = 0.6
		root.add_child(ring)
		mats.append(ring.material_override)
		root.set_meta("mats", mats)
		return root
	if kind == FX_WAVE_RING:
		# 扩散冲击环：薄 ring 外扩（非 zone，走 one-shot 由小展开）；有施法者名时用元素色
		var wcol := Color(1.0, 0.45, 0.1, 0.7)
		if caster != "":
			var wc: Color = Vfx.color_for_hero(caster)
			wcol = Color(wc.r, wc.g, wc.b, 0.7)
		var wring: MeshInstance3D = MeshFactory.create_torus_ring(maxf(r - 0.15, 0.02), maxf(r, 0.15), wcol, true, 0.7, true)
		wring.rotation.x = deg_to_rad(90)
		wring.position.y = 0.12
		root.add_child(wring)
		mats.append(wring.material_override)
		for m3 in mats:
			var sm := m3 as StandardMaterial3D
			if sm != null:
				sm.set_meta("base_a", sm.albedo_color.a)
		root.set_meta("mats", mats)
		return root
	if kind == FX_XQ_WHIRL:
		# 小乔2 甜蜜恋风：与 host Vfx.tornado_fx 同款——中央风柱 + 三层螺旋环（world pos 已抬 y1.5）
		var pink := Color(1.0, 0.52, 0.74)
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.3
		cm.bottom_radius = 0.95
		cm.height = 2.7
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		cone.mesh = cm
		cone.position.y = -0.15
		var cone_mat := StandardMaterial3D.new()
		cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone_mat.albedo_color = Color(pink.r, pink.g, pink.b, 0.20)
		cone_mat.emission_enabled = true
		cone_mat.emission = pink
		cone_mat.emission_energy_multiplier = 2.4
		cone_mat.set_meta("base_a", 0.20)
		cone.material_override = cone_mat
		root.add_child(cone)
		mats.append(cone_mat)
		for i in range(3):
			var br := 1.05 - 0.2 * float(i)
			var ring := MeshFactory.create_torus_ring(br * 0.7, br, pink.lerp(Color.WHITE, 0.22 + 0.14 * float(i)), true, 0.52, true)
			ring.position.y = -1.16 + 0.62 * float(i)
			ring.rotation.x = deg_to_rad(15.0 + 5.0 * float(i))
			ring.rotation.z = deg_to_rad(-10.0 + 6.0 * float(i))
			root.add_child(ring)
			mats.append(ring.material_override)
		for m4 in mats:
			var sm4 := m4 as StandardMaterial3D
			if sm4 != null:
				sm4.set_meta("base_a", sm4.albedo_color.a)
		root.set_meta("mats", mats)
		root.set_meta("rings", root.get_children().slice(1))
		return root
	# 地面盘主体 + 外圈。颜色跟随 helper 具体画布，team 仅用于 spell/terrain 红蓝方。
	var pool_col := Color(0.3, 0.7, 1.0, 0.5)      # 甄姬水系默认
	var rim_col := Color(0.45, 0.85, 1.0, 1.0)
	var body_a := 0.35
	match kind:
		FX_WATER_ZONE:
			pool_col = Color(0.3, 0.7, 1.0, 0.6)
		FX_WATER_PULSE, FX_WATER_SPLASH:
			pool_col = Color(0.3, 0.6, 1.0, 0.7)
		FX_LYF_STORM:
			pool_col = Color(1.0, 0.38, 0.08, 0.22)
			rim_col = Color(1.0, 0.55, 0.15, 1.0)
		FX_YL_POOL:
			pool_col = Color(0.3, 0.8, 1.0, 0.26)
			rim_col = Color(0.35, 0.85, 1.0, 1.0)
		FX_SPELL, FX_TERRAIN:
			pool_col = Color(team_col.r, team_col.g, team_col.b, 0.6)
			rim_col = team_col
	# r 语义 = host 视觉半径（与 SkillDataBase 各 helper 的 cylinder/ring 半径对齐）
	var disc: MeshInstance3D = MeshFactory.create_sphere(maxf(r, 0.15), pool_col, false, body_a)
	disc.scale = Vector3(1.0, 0.12, 1.0)
	root.add_child(disc)
	mats.append(disc.material_override)
	var edge: MeshInstance3D = MeshFactory.create_torus_ring(maxf(r - 0.2, 0.05), maxf(r, 0.16), rim_col, true, 0.9, true)
	edge.rotation.x = deg_to_rad(90)
	edge.position.y = 0.08
	root.add_child(edge)
	mats.append(edge.material_override)
	# 溅落/冲击一类加中央光柱：host 有 water pulse 喷口/风暴核心等
	if kind == FX_WATER_PULSE or kind == FX_WATER_SPLASH or kind == FX_LYF_STORM:
		var core: MeshInstance3D = MeshFactory.create_cylinder(maxf(r * 0.08, 0.1), maxf(r * 0.06, 0.06), maxf(r * 0.6, 0.5), Color(pool_col.r, pool_col.g, pool_col.b, 0.4), 0.4)
		core.position.y = maxf(r * 0.3, 0.25)
		root.add_child(core)
		mats.append(core.material_override)
	for m3 in mats:
		var sm := m3 as StandardMaterial3D
		if sm != null:
			sm.set_meta("base_a", sm.albedo_color.a)
	root.set_meta("mats", mats)
	return root


# 完整技能事件：行尾附加 [slot, caster xyz, target xyz, facing xz, skill 参数]，
# 直接调用单机同一个 Vfx.play_spell，签名大招/元素爆发/技能道具都不会再走客户端简化版。
func _skin_accent_for_caster(caster: String) -> Color:
	for v in _views.values():
		if v is Dictionary and str(v.get("name", "")) == caster:
			var sid := str(v.get("skin", ""))
			if sid != "":
				return HeroSkinTable.accent_for(caster, sid)
	return Color(0, 0, 0, 0)


func _spawn_full_spell_fx(row: Array, caster: String) -> void:
	if caster == "":
		return
	# 三端共享 SkillFxPresenter：优先 skill id → SkillDatabase 原技能（与 host 完全同源）
	var slot := int(row[10])
	var cp := Vector3(float(row[11]), float(row[12]), float(row[13]))
	var tp := Vector3(float(row[14]), float(row[15]), float(row[16]))
	var fd := Vector3(float(row[17]), 0.0, float(row[18]))
	if fd.length() < 0.01:
		fd = Vector3.FORWARD
	fd = fd.normalized()
	var skd := {
		"type": int(row[19]), "radius": float(row[20]), "duration": float(row[21]),
		"self_displacement": float(row[22]), "is_channeling": int(row[23]) == 1,
	}
	var sid := str(row[24]) if row.size() > 24 else ""
	SkillFxPresenter.play_spell(caster, slot, cp, tp, fd, sid, skd, int(row[FX_ROW_TEAM]), _vis_root, false)
	# 大招语音台词：只播屏幕内英雄，音量按距离衰减（ChatService 统一判定）
	if slot == 2:
		var _cs_v = get_node_or_null("/root/ChatService")
		if _cs_v != null:
			_cs_v.call("hero_voice_ult", caster, cp)

func _spawn_host_skill_fx(kind: int, p: Vector3, team: int, r: float, life: float, caster: String) -> void:
	SkillFxPresenter.spawn_kind(kind, p, team, r, life, caster)

func _build_skill_fx(kind: int, team: int, r: float, caster: String) -> Node3D:
	var root := Node3D.new()
	var col: Color = COL_ENEMY if (team == 0 or team == 1) and not Config.is_ally(team) else COL_ALLY_DIM
	if caster != "":
		col = Vfx.color_for_hero(caster)
	col.a = 1.0
	var mats: Array = []
	if kind == FX_PILLAR:
		var core: MeshInstance3D = MeshFactory.create_cylinder(maxf(r * 0.5, 0.2), maxf(r, 0.25), maxf(r * 2.6, 1.5), Color(col.r, col.g, col.b, 0.5), 0.6)
		core.position.y = maxf(r * 1.3, 0.8)
		root.add_child(core)
		mats.append(core.material_override)
	else:
		var glow: MeshInstance3D = MeshFactory.create_sphere(maxf(r * 0.55, 0.25), Color(col.r, col.g, col.b, 0.55), true, 0.65)
		glow.position.y = 0.5
		root.add_child(glow)
		mats.append(glow.material_override)
		var ring: MeshInstance3D = MeshFactory.create_torus_ring(maxf(r * 0.55, 0.2), maxf(r, 0.3), col, true, 1.0, true)
		ring.rotation.x = deg_to_rad(90)
		ring.position.y = 0.12
		root.add_child(ring)
		mats.append(ring.material_override)
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm != null:
			sm.set_meta("base_a", sm.albedo_color.a)
	root.set_meta("mats", mats)
	return root


func _fx_is_zone(kind: int) -> bool:
	return kind == FX_SPELL or kind == FX_TERRAIN or kind == FX_WATER_ZONE \
		or kind == FX_LYF_STORM or kind == FX_YL_POOL or kind == FX_MACHAO_SPEAR


func _anim_fx(fx: Dictionary, t: float) -> void:
	var nn: Node3D = fx.n
	var life := maxf(float(fx.life_ms) * 0.001, 0.001)
	var k := clampf(t / life, 0.0, 1.0)
	var kind := int(fx.kind)
	if kind == FX_XQ_WHIRL:
		# 与 host 同款：三层倾斜环绕 Y 自转 + 整体稍长高、末段淡出
		var sc := lerpf(1.0, 1.15, minf(1.0, k * 2.0))
		nn.scale = Vector3(sc, lerpf(1.0, 0.85, k), sc)
		if nn.has_meta("rings"):
			var ri := 0
			for ring in nn.get_meta("rings"):
				if ring is Node3D:
					(ring as Node3D).rotation.y = t * (7.0 + 1.6 * float(ri))
				ri += 1
		if nn.has_meta("mats"):
			var fade := 1.0 - clampf((k - 0.65) / 0.35, 0.0, 1.0)
			for mi2 in nn.get_meta("mats"):
				var sm2 := mi2 as StandardMaterial3D
				if sm2 != null:
					sm2.albedo_color.a = clampf(float(sm2.get_meta("base_a", 1.0)) * fade, 0.0, 1.0)
		return
	if kind == FX_HOUYI_EXPLODE:
		var s := 0.5 + 1.6 * k   # 扩散冲击波
		nn.scale = Vector3(s, 1.0, s)
	elif not _fx_is_zone(kind):
		var g := 0.4 + 0.6 * (k / 0.25)   # one-shot 落地由小展开
		nn.scale = Vector3(g, 1.0, g)
	if nn.has_meta("mats"):
		var al := 1.0
		if k > 0.7:
			al = 1.0 - (k - 0.7) / 0.3   # 末段淡出
		var mats: Array = nn.get_meta("mats")
		for mi in mats:
			var sm := mi as StandardMaterial3D
			if sm != null:
				sm.albedo_color.a = clampf(float(sm.get_meta("base_a", 1.0)) * al, 0.0, 1.0)


func _tick_visuals(delta: float) -> void:
	var now := Time.get_ticks_msec()
	# 子弹外推平滑：前向窗 clamp 到采样间隔（约 66ms），避免跨 15Hz 快照台阶感
	for bid in _bullets:
		var b: Dictionary = _bullets[bid]
		var age := (now - int(b.arr_ms)) * 0.001
		var f := minf(age, SNAP_BULLET_EXT)
		var vx := float(b.vx)
		var vz := float(b.vz)
		var m: Node3D = b.m as Node3D
		if m == null or not is_instance_valid(m):
			continue
		m.global_position = Vector3(float(b.x) + vx * f, float(b.y) + float(b.vy) * f, float(b.z) + vz * f)
		if vx * vx + vz * vz > 0.0004:
			if m is MeshInstance3D and (m as MeshInstance3D).mesh is CylinderMesh:
				# 回退圆柱：长轴 +Y → 水平 +Z，再朝速度向
				m.rotation = Vector3(PI * 0.5, atan2(vx, vz), 0.0)
			else:
				# glb / 程序化：真模型自带朝向（已放平），仅绕 Y 追向速度
				m.rotation.y = atan2(vx, vz)
				# 箭矢类（BOLT/ARROW）随弹道俯仰，同 host Bullet._aim_visual
				if m.has_meta("pitch"):
					var vlen := sqrt(vx * vx + float(b.vy) * float(b.vy) + vz * vz)
					if vlen > 0.001:
						m.rotation.x = -asin(clampf(float(b.vy) / vlen, -1.0, 1.0))
			# 扇面自转件（小乔）：只转视觉子节点
			var spn := m.get_node_or_null("Spin")
			if spn is Node3D and is_instance_valid(spn):
				(spn as Node3D).rotate_y(float(m.get_meta("spin", 0.0)) * delta)
	# FX 每帧推进，超龄回收
	var done: Array = []
	for fx in _fx_live:
		var nn2: Node3D = fx.n
		var age2 := (now - int(fx.born_ms)) * 0.001
		if age2 >= float(fx.life_ms) * 0.001 or nn2 == null or not is_instance_valid(nn2):
			if nn2 != null and is_instance_valid(nn2):
				nn2.queue_free()
			done.append(fx)
			continue
		_anim_fx(fx, age2)
	for fx in done:
		_fx_live.erase(fx)
	# #44 事件侧：经验珠推进（弹出 label 自带 tween 自治）+ 错位键过期清理
	var now6 := Time.get_ticks_msec()
	for k in _pop_offsets.keys():
		if now6 - int(_pop_offsets[k]["ms"]) > 350:
			_pop_offsets.erase(k)
	_advance_exp_orbs(delta)


# —— #44 events：快照 idx9 尾段 → 伤害/金币弹出 + 经验珠（纯呈现，仿 FX fid 去重） ——
func _apply_events(snap: Array) -> void:
	# 注：headless 也走到这里逐行解析（视觉函数自带 null 守卫早退），以便集成门禁覆盖行索引/常量引用
	var seg: Array = snap[SNAP_EVENTS]
	if seg.is_empty():
		return
	var seq := int(seg[EV_SEQ])
	if seq == _ev_seq_last:
		return
	_ev_seq_last = seq
	for i in range(1, seg.size()):
		var row: Array = seg[i]
		var fid := int(row[EV_ROW_FID])
		if _ev_seen_fid.has(fid):
			continue
		_ev_seen_fid[fid] = true
		var kind := int(row[EV_ROW_KIND])
		var p := Vector3(float(row[EV_ROW_X]), float(row[EV_ROW_Y]), float(row[EV_ROW_Z]))
		if kind == EV_DMG:
			_spawn_dmg_label(p, int(round(float(row[EV_DMG_AMT]))),
				int(row[EV_DMG_CRIT]) != 0, int(row[EV_DMG_MAG]) != 0,
				row.size() > EV_DMG_SHIELD and int(row[EV_DMG_SHIELD]) != 0,
				row.size() > EV_DMG_TRUE and int(row[EV_DMG_TRUE]) != 0)
		elif kind == EV_GOLD:
			_spawn_gold_label(p, int(round(float(row[EV_GOLD_AMT]))), int(row[EV_GOLD_OWN]) != 0)
		elif kind == EV_EXP:
			_spawn_exp_orb(p, Vector3(float(row[EV_EXP_TX]), 0.0, float(row[EV_EXP_TZ])), int(row[EV_EXP_NID]))
		elif kind == EV_ACT:
			_apply_hero_act(int(row[EV_ACT_NID]), int(row[EV_ACT_ACT]), float(row[EV_ACT_YAW]))
	if _ev_seen_fid.size() > 512:
		_ev_seen_fid.clear()


# —— 弹出层：CanvasLayer 103（盖过触摸 100 / C·T 101 / 商店 102，结算 110 之下）——
func _build_event_layer() -> void:
	_pop_cl = CanvasLayer.new()
	_pop_cl.layer = UiKit.LAYER_POPUP
	add_child(_pop_cl)
	_pop_root = Control.new()
	_pop_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pop_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pop_cl.add_child(_pop_root)


# 死亡全屏压暗（复刻 host UI_Manager._create_death_overlay：黑色 0.5，复活即消失；层 21 在 HUD 之上、面板之下）
func _build_death_overlay() -> void:
	_death_cl = CanvasLayer.new()
	_death_cl.layer = UiKit.LAYER_RECAP - 1   # 104：盖住触控技能键(100)与飘字(103)，低于死亡面板(105)/结算(110)
	add_child(_death_cl)
	_death_tint = ColorRect.new()
	_death_tint.color = Color(0.0, 0.0, 0.0, 0.5)
	_death_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_death_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_tint.visible = false
	_death_cl.add_child(_death_tint)


# PostFX：本地英雄受击红晕 + 阵亡去饱和 + 低血量屏幕血光（纯表现；与 host BattleManager._sync_postfx 同逻辑）
func _sync_postfx() -> void:
	if not _owned:
		PostFX.set_dead(false)
		PostFX.set_low_hp(1.0)
		_pfx_hp = -1.0
		return
	if int(_own.get("alive", 1)) == 0:
		PostFX.set_dead(true)
		PostFX.set_low_hp(0.0)
		_pfx_hp = -1.0
		return
	PostFX.set_dead(false)
	var hp := float(_own.get("hp", 0.0))
	var maxhp := maxf(float(_own.get("maxhp", 1.0)), 1.0)
	PostFX.set_low_hp(clampf(hp / maxhp, 0.0, 1.0))
	if _pfx_hp >= 0.0 and hp < _pfx_hp:
		var lost := (_pfx_hp - hp) / maxhp
		PostFX.damage(clampf(0.3 + lost * 4.0, 0.0, 1.0), clampf(lost * 3.0, 0.0, 0.6))
		# 受击震屏：同 host GameEntity（伤害 > max(5, 2%maxhp)，90ms 节流；本机在镜头中心恒 <14m）
		var dmg := _pfx_hp - hp
		var now_ms := Time.get_ticks_msec()
		if dmg > maxf(5.0, maxhp * 0.02) and now_ms - _last_feedback_ms > 90:
			_last_feedback_ms = now_ms
			_camera_shake(clampf(0.03 + dmg / 5000.0, 0.03, 0.12), 0.18)
	_pfx_hp = hp


# PostFX：离开联机战斗场景时复位死亡去饱和/低血红屏，避免回大厅后画面仍压暗
func _exit_tree() -> void:
	PostFX.set_dead(false)
	PostFX.set_low_hp(1.0)
	Engine.time_scale = 1.0   # 本地顿帧兜底复位（防止中途退出卡在慢放）
	if is_instance_valid(SfxManager):
		SfxManager.stop_all()


## 屏幕内英雄（供英雄语音定时播报；只返回相机视锥+屏幕范围内的存活英雄）
func visible_voice_targets() -> Array:
	var out: Array = []
	if _cam == null or not is_instance_valid(_cam):
		return out
	var rect := get_viewport().get_visible_rect().grow(80.0)
	for v in _views.values():
		if int(v.get("type", -1)) != NET_HERO:
			continue
		if float(v.get("hp", 0.0)) <= 0.0:
			continue
		var pos: Vector3 = _view_pos(v)
		var wp: Vector3 = pos + Vector3.UP * 1.2
		if not _cam.is_position_in_frustum(wp):
			continue
		if not rect.has_point(_cam.unproject_position(wp)):
			continue
		out.append({"name": str(v.get("name", "")), "pos": pos, "role": ""})
	return out


# 视图节点当前世界位置（小地图绘制/距离判定用；无节点时退回快照目标点）
func _view_pos(v: Dictionary) -> Vector3:
	if v.has("node") and v["node"] != null:
		var n: Node3D = v["node"]
		return n.global_position
	return Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0)))


# 同一位置错开（复刻主机 UI_Manager._get_stagger_offset：同目标多次伤害向四周散开）
func _popup_stagger(wp: Vector3) -> Vector2:
	var key: Vector3 = (wp * 10.0).round() / 10.0
	var now := Time.get_ticks_msec()
	if not _pop_offsets.has(key) or now - int(_pop_offsets[key]["ms"]) > 350:
		_pop_offsets[key] = {"count": 0, "ms": now}
	var info: Dictionary = _pop_offsets[key]
	var idx := int(info["count"])
	info["count"] = int(info["count"]) + 1
	info["ms"] = now
	if idx == 0:
		return Vector2.ZERO
	var ang := float(idx - 1) * TAU / 8.0
	var ring := 1.0 + float((idx - 1) / 8)
	var r := 20.0 * ring
	return Vector2(cos(ang) * r, sin(ang) * r)



func _spawn_dmg_label(wp: Vector3, dmg: int, crit: bool, magic: bool, shielded: bool = false, true_dmg: bool = false) -> void:
	var cam := _cam
	if cam == null or _pop_root == null:
		return
	var sp := cam.unproject_position(wp + Vector3(0.0, 1.5, 0.0))
	var vp := get_viewport().get_visible_rect().size
	if sp.x < -320.0 or sp.x > vp.x + 320.0 or sp.y < -320.0 or sp.y > vp.y + 320.0:
		return
	var s := _hud_scale()
	var px := int(round(UiKit.damage_number_size(float(dmg), crit) * s))
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.text = str(dmg)
	lab.add_theme_font_size_override("font_size", px)
	# 与主机一致：真伤红 / 护盾吸收白 / 法术紫 / 物理橙 / 暴击金
	var col := Color(1.0, 0.30, 0.26) if true_dmg else (Color(0.96, 0.97, 1.0) if shielded else (Color(1.0, 0.90, 0.45) if crit else (Color(0.74, 0.53, 1.0) if magic else Color(1.0, 0.76, 0.34))))
	var edge := Color(0.30, 0.02, 0.02, 1.0) if true_dmg else (Color(0.10, 0.10, 0.14, 0.96) if shielded else (Color(0.40, 0.24, 0.02, 1.0) if crit else Color(0.12, 0.05, 0.02, 0.96)))
	lab.add_theme_color_override("font_color", col)
	lab.add_theme_color_override("font_outline_color", edge)
	lab.add_theme_constant_override("outline_size", clampi(int(round(px * 0.22)), 3, 14))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	lab.add_theme_constant_override("shadow_offset_x", maxi(1, int(round(px * 0.05))))
	lab.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(px * 0.08))))
	lab.add_theme_constant_override("shadow_outline_size", 0)
	if crit:
		# 暴击：数字左前方四芒星爆点（复刻 host UI_Manager.CritMark，随 Label 一起上浮/淡出）
		var mark := _CritMark.new()
		var _iw := px * 0.62
		var _ih := px * 0.7
		mark.size = Vector2(_iw, _ih)
		lab.add_child(mark)
	var off := _popup_stagger(wp)
	_pop_root.add_child(lab)
	lab.size = lab.get_combined_minimum_size()
	if crit and lab.get_child_count() > 0:
		var mark2: Control = lab.get_child(0)
		mark2.position = Vector2(-(mark2.size.x + px * 0.22), (lab.size.y - mark2.size.y) * 0.5 + px * 0.06)
	lab.position = sp - lab.size * 0.5 + off
	# 弹入（先放大再回弹）+ 上浮淡出，和主机节奏一致
	lab.pivot_offset = lab.size * 0.5
	lab.scale = Vector2(1.45, 1.45)
	var rise := (66.0 if crit else 54.0) * s
	var t1 := lab.create_tween()
	t1.tween_property(lab, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := lab.create_tween()
	tw.tween_property(lab, "position:y", lab.position.y - rise, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.45).set_delay(0.55)
	tw.tween_callback(lab.queue_free)


func _spawn_gold_label(wp: Vector3, amount: int, own: bool) -> void:
	var cam := _cam
	if cam == null or _pop_root == null:
		return
	var sp := cam.unproject_position(wp + Vector3(0.0, 1.5, 0.0))
	var vp := get_viewport().get_visible_rect().size
	if sp.x < -320.0 or sp.x > vp.x + 320.0 or sp.y < -320.0 or sp.y > vp.y + 320.0:
		return
	var s := _hud_scale()
	var fs := int(round((34.0 if own else 30.0) * s))
	var lab := Label.new()
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.text = "+%dg" % amount
	lab.add_theme_font_size_override("font_size", fs)
	lab.add_theme_color_override("font_color", Color(1.0, 0.87, 0.40))
	lab.add_theme_color_override("font_outline_color", Color(0.16, 0.08, 0.01, 0.95))
	lab.add_theme_constant_override("outline_size", maxi(2, int(round(fs * 0.20))))
	lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	lab.add_theme_constant_override("shadow_offset_x", maxi(1, int(round(fs * 0.05))))
	lab.add_theme_constant_override("shadow_offset_y", maxi(1, int(round(fs * 0.07))))
	lab.add_theme_constant_override("shadow_outline_size", 0)
	var off := _popup_stagger(wp)
	_pop_root.add_child(lab)
	lab.size = lab.get_combined_minimum_size()
	# 左侧矢量徽标：自己击杀=小剑，助攻/自然金币=金币（复刻主机 ValuePopup 语义，随 label 上浮/淡出）
	var icon_w: float = fs * (1.6 if own else 1.3)
	var mark: Control
	if own:
		var blade := _BladeMark.new(fs)
		blade.size = Vector2(fs * 1.5, fs * 1.3)
		mark = blade
	else:
		var coin := _CoinMark.new(fs)
		coin.size = Vector2(fs * 1.3, fs * 1.3)
		mark = coin
	lab.add_child(mark)
	mark.position = Vector2(-icon_w - fs * 0.30, (lab.size.y - mark.size.y) * 0.5)
	lab.position = sp - lab.size * 0.5 + off + Vector2(-icon_w * 0.45, 0.0)
	lab.pivot_offset = lab.size * 0.5
	lab.scale = Vector2(1.3, 1.3)
	var t1 := lab.create_tween()
	t1.tween_property(lab, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := lab.create_tween()
	tw.tween_property(lab, "position:y", lab.position.y - 55.0, 1.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lab, "modulate:a", 0.0, 0.6).set_delay(1.4)
	tw.tween_callback(lab.queue_free)


# 经验珠：source 处亮核光球 0.5s 飞向目标英雄头顶（host 单机 spawn_exp_orb 同款）
func _spawn_exp_orb(src: Vector3, end: Vector3, nid: int) -> void:
	if _vis_root == null:
		return
	var orb: Node3D = MeshFactory.create_exp_orb(0.16)
	_vis_root.add_child(orb)
	orb.global_position = Vector3(src.x, maxf(src.y + 0.3, 0.3), src.z)
	orb.scale = Vector3(0.4, 0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(orb, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var to := end + Vector3(0.0, 1.5, 0.0)
	var dist := to.distance_to(orb.global_position)
	_exp_orbs.append({"n": orb, "nid": nid, "tx": end.x, "tz": end.z,
		"spd": maxf(dist / 0.5, 2.0)})


# 目标为存活 view（持续跟随其头顶）；view 缺失/阵亡则飞向快照终点兜底
func _exp_orb_target(o: Dictionary) -> Vector3:
	var v: Dictionary = _views.get(int(o.nid), {})
	if v.has("node") and v.node != null and is_instance_valid(v.node):
		return v.node.global_position + Vector3(0.0, 1.5, 0.0)
	return Vector3(float(o.tx), 1.5, float(o.tz))


func _advance_exp_orbs(delta: float) -> void:
	if _exp_orbs.is_empty():
		return
	var done3: Array = []
	for o in _exp_orbs:
		var nn3: Node3D = o.n
		if nn3 == null or not is_instance_valid(nn3):
			done3.append(o)
			continue
		var to := _exp_orb_target(o)
		var dir := to - nn3.global_position
		var dist := dir.length()
		var mv := float(o.spd) * delta
		if dist <= mv:
			nn3.queue_free()
			done3.append(o)
			continue
		nn3.global_position += dir / dist * mv
	for o in done3:
		_exp_orbs.erase(o)


# —— #44 英雄动画：idle/walk 按位移速度本地切换；attack 由 events（EV_ACT）触发覆盖 ——
func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_ap(c)
		if f != null:
			return f
	return null


# 英雄 GLB 的 idle/walk clip 导入为 loop=none（同款 host 靠每物理帧重播维持循环）；
# client 是「状态切换单发播放」，播完会定格尾帧。此处把循环类 clip 转成 LOOP_LINEAR。
# 子资源随 PackedScene 共享 → 同模型多英雄实例一次设置全生效（幂等，重复调用无害）。
func _setup_anim_loops(ap: AnimationPlayer) -> void:
	# 英雄 clip 就叫 idle/walk；小兵/野怪是 CharacterArmature|Flying_Idle、Walk 之类，
	# 统一按关键字把「循环类」clip 转成 LOOP_LINEAR（子资源共享，幂等）。
	for nm in ap.get_animation_list():
		var low := String(nm).to_lower()
		if low.find("idle") >= 0 or low.find("walk") >= 0 or low.find("run") >= 0:
			ap.get_animation(nm).loop_mode = Animation.LOOP_LINEAR


# 按关键字在 AnimationPlayer 里找第一个匹配 clip（各模型命名不统一：英雄 attack-melee-left /
# holding-*-shoot，小兵 CharacterArmature|Punch，野怪 Attack）。取最短匹配避免抓到变体名。
func _clip_hint(ap: AnimationPlayer, hints: Array) -> String:
	# 三端统一：动画 clip 关键字匹配走 AnimMap.hint
	return AnimMap.hint(ap, hints)

# 快照里「正在攻击」时补一个攻击动作（host 的 act 事件有距离闸门，远处小兵收不到）
func _v_snap_unit_attack(v: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - int(v.get("snap_atk_ms", 0)) < 380:
		return
	v.snap_atk_ms = now
	var nn: Node3D = v.get("node")
	if nn == null or not is_instance_valid(nn) or not v.get("set", false):
		return
	nn.rotation.y = float(v.get("face_yaw", nn.rotation.y))
	if not v.has("ap"):
		_proc_recoil(v, float(v.get("face_yaw", nn.rotation.y)))
		return
	if now < int(v.get("att_until", 0)):
		return
	var ap: AnimationPlayer = v.ap
	if ap == null or not is_instance_valid(ap):
		return
	var clip := str(v.get("atk_clip", ""))
	if clip == "" or not ap.has_animation(clip):
		return
	ap.play(clip)
	v.anim = "attack"
	v.att_clip = clip
	v.att_play = now
	v.att_until = now + 620

# 红/蓝 buff 光环开关（which：0=红 1=蓝）
func _set_buff_ring(v: Dictionary, which: int, on: bool) -> void:
	var rings: Array = v.get("buff_rings", [])
	if which >= rings.size():
		return
	var mi = rings[which]
	if mi != null and is_instance_valid(mi) and mi.visible != on:
		mi.visible = on

func _proc_death(v: Dictionary) -> void:
	var mdl: Node3D = v.get("model", null)
	var nn: Node3D = v.node
	if mdl == null or not is_instance_valid(mdl) or mdl.has_meta("_proc_death_done"):
		return
	mdl.set_meta("_proc_death_done", true)
	if nn != null and is_instance_valid(nn):
		var walker := nn.get_node_or_null("WalkFeel")
		if walker:
			walker.set_process(false)
	var kind := str(mdl.get_meta("minion_model_kind", ""))
	var base := mdl.position
	var tw := mdl.create_tween()
	tw.set_parallel(true)
	if kind in ["dragon", "storm", "shadow_dragon"]:
		tw.tween_property(mdl, "rotation:x", 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mdl, "position:y", base.y - 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var dir := 1.0 if (nn.get_instance_id() % 2 == 0) else -1.0
		tw.tween_property(mdl, "rotation:z", dir * 1.35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(mdl, "position:y", base.y - 0.12, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# 服务器出手序号变化时调用：每次真出手播一次，节奏与 host 完全一致
func _v_unit_attack_now(v: Dictionary) -> void:
	var nn: Node3D = v.get("node")
	if nn == null or not is_instance_valid(nn) or not v.get("set", false):
		return
	nn.rotation.y = float(v.get("face_yaw", nn.rotation.y))
	var now := Time.get_ticks_msec()
	if not v.has("ap"):
		_proc_recoil(v, float(v.get("face_yaw", nn.rotation.y)))
		return
	var ap: AnimationPlayer = v.ap
	if ap == null or not is_instance_valid(ap):
		return
	var clip := str(v.get("atk_clip", ""))
	if clip == "" or not ap.has_animation(clip):
		return
	ap.play(clip)
	v.anim = "attack"
	v.att_clip = clip
	v.att_play = now
	v.att_until = now + 620


func _find_model_pivot(n: Node) -> Node3D:
	if n is Node3D and str(n.name) == "ModelPivot":
		return n as Node3D
	for c in n.get_children():
		var r := _find_model_pivot(c)
		if r != null:
			return r
	return null


# 无骨骼模型的普攻动作（与 host Minion._model_lunge/_siege_recoil 同参数）
func _proc_recoil(v: Dictionary, yaw: float) -> void:
	var mdl: Node3D = v.get("model", null)
	if mdl == null or not is_instance_valid(mdl):
		return
	var kind := str(v.get("name", mdl.get_meta("minion_model_kind", "")))
	var pivot: Node3D = _find_model_pivot(mdl)
	if kind == "siege":
		_siege_recoil_client(mdl, pivot, yaw)
		_fire_ammo_client(mdl)
		return
	if pivot == null:
		return
	var old: Tween = pivot.get_meta("atk_tween", null)
	if old != null and old.is_valid():
		old.kill()
	# 兵种手感：远程拉弓后弹射、超级兵重砸、龙兵俯冲冲撞、近战兵刺击
	var p := {"back": 0.12, "fwd": 0.36, "up": 0.18, "down": 0.18, "twist": 0.26, "dip": 0.05,
		"windup": 0.09, "strike": 0.10, "settle": 0.30}
	if kind == "ranged":
		p = {"back": 0.17, "fwd": 0.09, "up": 0.11, "down": 0.12, "twist": 0.15, "dip": 0.04,
			"windup": 0.13, "strike": 0.07, "settle": 0.26}
	elif kind == "super":
		p = {"back": 0.19, "fwd": 0.52, "up": 0.32, "down": 0.36, "twist": 0.46, "dip": 0.11,
			"windup": 0.13, "strike": 0.12, "settle": 0.36}
	elif kind in ["dragon", "storm", "shadow_dragon"]:
		p = {"back": 0.13, "fwd": 0.38, "up": 0.12, "down": 0.24, "twist": 0.0, "dip": 0.06,
			"windup": 0.10, "strike": 0.12, "settle": 0.30}
	var rest_pos: Vector3 = pivot.get_meta("rest_pos", pivot.position)
	var rest_rot: Vector3 = pivot.get_meta("rest_rot", pivot.rotation)
	var rest_scl: Vector3 = pivot.get_meta("rest_scl", pivot.scale)
	pivot.position = rest_pos
	pivot.rotation = rest_rot
	pivot.scale = rest_scl
	var base_pos := rest_pos
	var base_rot := rest_rot
	var base_scl := rest_scl
	var seed_v := absi(mdl.get_instance_id() % 89)
	var rnd := float(seed_v) / 89.0
	var side_dir: float = 1.0 if (seed_v % 2 == 0) else -1.0
	var back := float(p.back) * (0.85 + 0.30 * rnd)
	var fwd := float(p.fwd) * (0.90 + 0.20 * rnd)
	var up := float(p.up) * (0.85 + 0.30 * rnd)
	var down := float(p.down) * (0.85 + 0.30 * rnd)
	var twist := float(p.twist) * (0.80 + 0.40 * rnd)
	var dip := float(p.dip) * (0.85 + 0.30 * rnd)
	var windup := float(p.windup) * (0.85 + 0.30 * rnd)
	var strike := float(p.strike) * (0.85 + 0.30 * rnd)
	var settle := float(p.settle) * (0.90 + 0.20 * rnd)
	var swing := 0.0
	var roll := 0.0
	if kind in ["melee", "super"]:
		var heavy: float = 1.6 if kind == "super" else 1.0
		swing = (0.16 + 0.12 * rnd) * side_dir * heavy
		roll = (0.10 + 0.08 * rnd) * side_dir * heavy
	elif kind in ["dragon", "storm", "shadow_dragon"]:
		swing = 0.06 * side_dir
	var hop: float = up * 0.22 if kind in ["melee", "super"] else 0.0
	var tw := create_tween()
	pivot.set_meta("atk_tween", tw)
	tw.tween_property(pivot, "position:z", base_pos.z - back, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x + up, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y + twist, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x - swing * 0.45, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z + roll * 0.4, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y - dip * 0.35, windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 1.05, base_scl.y * 0.93, base_scl.z * 1.05), windup).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(pivot, "position:z", base_pos.z + fwd, strike).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x + swing, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y - dip + hop, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x - down, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y - twist * 1.5, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z - roll, strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 0.94, base_scl.y * 1.10, base_scl.z * 0.94), strike).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(pivot, "position:z", base_pos.z + fwd * 0.25, settle * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x + swing * 0.3, settle * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x + up * 0.2, settle * 0.45)
	tw.parallel().tween_property(pivot, "scale", Vector3(base_scl.x * 1.02, base_scl.y * 0.97, base_scl.z * 1.02), settle * 0.45)
	tw.tween_property(pivot, "position:z", base_pos.z, settle * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:x", base_pos.x, settle * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "position:y", base_pos.y, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:x", base_rot.x, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:y", base_rot.y, settle * 0.55)
	tw.parallel().tween_property(pivot, "rotation:z", base_rot.z, settle * 0.55)
	tw.parallel().tween_property(pivot, "scale", base_scl, settle * 0.55)
	_fire_ammo_client(mdl)


# 攻城车开炮后坐（与 host Minion._siege_recoil 同参数）
func _siege_recoil_client(mdl: Node3D, pivot: Node3D, yaw: float) -> void:
	var recoil_node: Node3D = pivot
	var dist := 0.45
	if recoil_node != null:
		dist = 0.20
	else:
		recoil_node = mdl
	var rest_pos2: Vector3 = recoil_node.get_meta("rest_pos", recoil_node.position)
	var rest_rot2: Vector3 = recoil_node.get_meta("rest_rot", recoil_node.rotation)
	recoil_node.position = rest_pos2
	recoil_node.rotation = rest_rot2
	var base := rest_pos2
	var base_rot := rest_rot2
	var tw := create_tween()
	tw.tween_property(recoil_node, "position:z", base.z - dist, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(recoil_node, "rotation:x", base_rot.x - 0.075, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(recoil_node, "position:z", base.z, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(recoil_node, "rotation:x", base_rot.x, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var mz := _minion_muzzle(mdl, str(mdl.get_meta("minion_model_kind", "")))
	Vfx.muzzle(mz, fwd, Color(1.0, 0.72, 0.35), Color(1.0, 0.95, 0.8))
	Vfx.cast_glow(mz + fwd * 0.22, Color(1.0, 0.55, 0.2), 0.65, 0.2)


func _minion_muzzle(mdl: Node3D, kind: String) -> Vector3:
	var local: Vector3 = MinionModelScript.muzzle_local(kind)
	var pivot: Node3D = mdl.get_node_or_null("ModelPivot")
	var base: Node3D = pivot if pivot != null else mdl
	return base.global_transform * local


func _fire_ammo_client(mdl: Node3D) -> void:
	if mdl == null or not is_instance_valid(mdl):
		return
	var ammo := mdl.get_node_or_null("ModelPivot/Ammo") as MeshInstance3D
	if ammo == null or not is_instance_valid(ammo):
		return
	ammo.visible = false
	var t := get_tree().create_timer(0.8)
	t.timeout.connect(func() -> void:
		if is_instance_valid(ammo):
			ammo.visible = true)


# 防御塔激光（host RPC）：细光束从塔顶连到目标，能量球本体走普通弹体快照（kind=5）
func _on_tower_laser(from: Vector3, to: Vector3, team: int, dur: float) -> void:
	var c: Color = Vfx.team_color(team)   # 固定按塔阵营：蓝=蓝、红=红
	Vfx.beam(from, to, c, 0.055, dur)
	await get_tree().create_timer(dur).timeout
	if is_inside_tree():
		Vfx.hit_spark(to, c, (from - to).normalized(), 0.8)


# 防御塔锁定光束：host 每 0.15s 刷新目标点，客户端逐帧插值 → 视觉上一直锁定
## 孙悟空筋斗云：英雄世界高度 >0.5 时脚下生成云团；落地/换人自动收回（与主视觉同源）
func _update_wukong_clouds(delta: float) -> void:
	for nid in _views:
		var v: Dictionary = _views[nid]
		if int(v.get("type", -1)) not in [NET_HERO]:
			continue
		var nm := str(v.get("name", ""))
		var nd = v.get("node")
		if nd == null or not is_instance_valid(nd):
			continue
		var y := float((v.get("target") as Vector3).y) if v.get("target") is Vector3 else 0.0
		var want: bool = nm == "孙悟空" and y > 0.45 and int(v.get("hp", 0.0)) > 0.0
		var cl = v.get("wcloud")
		if want and (cl == null or not is_instance_valid(cl)):
			cl = WukongCloudScript.build()
			nd.add_child(cl)
			v["wcloud"] = cl
		if cl != null and is_instance_valid(cl):
			cl.visible = want
			if want:
				var rot := float(nd.rotation.y)
				var dir := Vector3(sin(rot), 0.0, cos(rot))
				WukongCloudScript.tick(cl, dir, 10.0, Time.get_ticks_msec() * 0.001, true)


func _on_tower_lock(from: Vector3, to: Vector3, team: int, active: bool) -> void:
	var key: String = "%d_%d" % [int(from.x * 10.0), int(from.z * 10.0)]
	if not active:
		var old: Dictionary = _tower_locks.get(key, {})
		if old.has("mesh"):
			var om = old["mesh"]
			if is_instance_valid(om):
				om.queue_free()
		_tower_locks.erase(key)
		return
	var rec: Dictionary = _tower_locks.get(key, {})
	if not rec.has("mesh") or not is_instance_valid(rec["mesh"]):
		var col: Color = Vfx.team_color(team)   # 固定按塔阵营：蓝=蓝、红=红
		var mi: Node3D = Vfx.make_lock_beam(col)
		_static_root.add_child(mi)
		rec = {"mesh": mi, "from": from, "to": to, "cur": to, "t": Time.get_ticks_msec()}
		_tower_locks[key] = rec
	rec["from"] = from
	rec["to"] = to
	rec["t"] = Time.get_ticks_msec()
	rec["t"] = Time.get_ticks_msec()


func _update_tower_locks(delta: float) -> void:
	if _tower_locks.is_empty():
		return
	var now := Time.get_ticks_msec()
	for key in _tower_locks.keys():
		var rec: Dictionary = _tower_locks[key]
		var mi = rec.get("mesh")
		if mi == null or not is_instance_valid(mi):
			_tower_locks.erase(key)
			continue
		if now - int(rec.get("t", now)) > 450:
			mi.queue_free()
			_tower_locks.erase(key)
			continue
		# 与主机 Turret._update_lock_beam 同帧直瞄最新目标（host 每帧 aim；客户端无法每帧收包，但不再 lerp 滞后）
		Vfx.aim_lock_beam(mi, rec["from"], rec["to"], float(Time.get_ticks_msec()) * 0.001)


func _apply_hero_act(nid: int, act: int, yaw: float) -> void:
	var v: Dictionary = _views.get(nid, {})
	if v.is_empty():
		return
	var nn0: Node3D = v.get("node")
	if nn0 != null and is_instance_valid(nn0):
		# 攻击朝向：所有单位（含无 AnimationPlayer 的程序化小兵/攻城车）都先转向目标
		nn0.rotation.y = yaw
	if not v.has("ap"):
		if act == NetSession.ACT_DIE:
			_proc_death(v)
			# 程序化小兵/野怪没有 AnimationPlayer，必须自己留死亡动画时间；
			# 否则下一次快照剔除会立刻 queue_free，只剩“啪”一下消失。
			v.dying_until = Time.get_ticks_msec() + 1000
		elif act == NetSession.ACT_ATTACK_MELEE:
			_proc_recoil(v, yaw)   # 无骨骼动画的模型（攻城车/程序化兵种）：程序化动作
		if act == NetSession.ACT_ATTACK_MELEE:
			_net_melee_slash(v, yaw)
		return
	var nn: Node3D = v.node
	if nn != null and is_instance_valid(nn):
		nn.rotation.y = yaw   # 攻击朝向（host 用 rotation.y 面向目标，同约定）
	var now := Time.get_ticks_msec()
	var ap: AnimationPlayer = v.ap
	var is_hero := int(v.type) == NET_HERO
	var clip := ""
	match act:
		NetSession.ACT_DIE:
			clip = ActorPresenter.clip(ap, "die", str(v.get("name", "")))
			if clip == "":
				clip = str(v.get("atk_clip", ""))
		NetSession.ACT_CAST_SPRINT:
			clip = _clip_hint(ap, ["sprint"])
		NetSession.ACT_CAST_INTERACT:
			clip = _clip_hint(ap, ["interact"])
		NetSession.ACT_CAST_MELEE:
			clip = AnimMap.clip(ap, "attack_melee_right", str(v.get("name", "")))
		NetSession.ACT_CAST_BOTH_SHOOT:
			clip = "holding-both-shoot" if ap.has_animation("holding-both-shoot") else _clip_hint(ap, ["holding", "shoot"])
		_:
			if not is_hero:
				# 小兵/野怪：clip 命名与英雄不同，用建 view 时缓存的关键字匹配结果
				clip = str(v.get("atk_clip", ""))
			elif act == NetSession.ACT_ATTACK_SHOOT:
				clip = "holding-both-shoot" if str(v.get("name", "")) in ["后羿", "孙尚香", "元流之子"] else "holding-right-shoot"
				if not ap.has_animation(clip):
					clip = ActorPresenter.clip(ap, "attack_shoot", str(v.get("name", "")))
				if clip == "" or not ap.has_animation(clip):
					clip = str(v.get("atk_clip", ""))
			else:
				# 近战普攻左右交替（host 用 _melee_anim_flip 交替；clip 选择走 AnimMap）
				v.melee_flip = not bool(v.get("melee_flip", false))
				clip = AnimMap.melee(ap, bool(v.melee_flip), str(v.get("name", "")))
				if clip == "":
					clip = str(v.get("atk_clip", ""))
	if clip == "" or not ap.has_animation(clip):
		return
	ap.play(clip)
	# 武器模型动作（单机 Hero._perform_attack → "attack"、_finish_casting → "cast"）：
	# 客户端之前只播身体 clip，武器是静止的，所以观感不如单机
	if is_hero:
		var wm = v.get("model")
		if wm != null and is_instance_valid(wm):
			if act == NetSession.ACT_ATTACK_MELEE or act == NetSession.ACT_ATTACK_SHOOT:
				HeroWeapons.play(wm, "attack")
			elif act == NetSession.ACT_CAST_SHOOT or act == NetSession.ACT_CAST_MELEE or act == NetSession.ACT_CAST_BOTH_SHOOT:
				HeroWeapons.play(wm, "cast")
	v.anim = "attack"
	v.att_clip = clip
	v.att_play = now
	if act == NetSession.ACT_DIE:
		# 死亡动作：按 clip 长度留宽限，主机销毁节点后 view 也不会"啪"地消失
		v.dying_until = now + int(ap.get_animation(clip).length * 1000.0) + 250
		v.att_until = 0
	else:
		v.att_until = now + 620
	if act == NetSession.ACT_ATTACK_MELEE:
		_net_melee_slash(v, yaw)
	# 攻击特效：host 远程普攻的枪口粒子（Hero._perform_attack 里 Vfx.cast_burst）不进 FX 流，
	# 客户端本地补一次；只对英雄远程普攻加，其余保持与 host 一致。
	if is_hero and act == NetSession.ACT_ATTACK_SHOOT and nn != null and is_instance_valid(nn):
		var fwd2 := Vector3(sin(yaw), 0.0, cos(yaw))
		Vfx.cast_burst(str(v.get("name", "")),
			nn.global_position + Vector3.UP * 1.2 + fwd2 * 0.65, fwd2, 0.5)


# 近战出手挥砍光弧（复刻 host Hero/Minion 攻击里的 Vfx.weapon_hit，仅近处可见）
# 受击反馈（复刻 host：非英雄闪白+脉冲，英雄后仰；70ms 节流）
func _net_hit_flash(v: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - int(v.get("last_flash", 0)) < 70:
		return
	v["last_flash"] = now
	var mdl = v.get("model")
	var root3: Node3D = mdl if (mdl != null and is_instance_valid(mdl)) else v.get("node")
	if root3 == null or not is_instance_valid(root3):
		return
	UnitVisuals.hit_flash(root3)
	UnitVisuals.hit_pulse(root3)
	if int(v.get("type", -1)) == NET_HERO and mdl != null and is_instance_valid(mdl):
		var tw: Tween = mdl.create_tween()
		tw.tween_property(mdl, "rotation:x", -0.10, 0.06)
		tw.tween_property(mdl, "rotation:x", 0.0, 0.14)


func _net_melee_slash(v: Dictionary, yaw: float) -> void:
	var nn: Node3D = v.get("node")
	if nn == null or not is_instance_valid(nn):
		return
	var sp := _self_pos()
	var is_hero: bool = int(v.get("type", -1)) == NET_HERO
	if nn.global_position.distance_to(sp) > (30.0 if is_hero else 20.0):
		return
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var c: Color = Vfx.color_for_hero(str(v.get("name", ""))) if is_hero else Vfx.team_color(int(v.get("team", 0)))
	var from := nn.global_position + Vector3.UP * (1.2 if is_hero else 0.85) + fwd * 0.25
	var to := nn.global_position + Vector3.UP * (1.2 if is_hero else 0.9) + fwd * (2.0 if is_hero else 1.5)
	Vfx.weapon_hit(from, to, c, Color(1.0, 0.96, 0.86), 1.1 if is_hero else 0.9)


func _tick_hero_anims(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for nid in _views:
		var v: Dictionary = _views[nid]
		if not v.has("ap") or not v.get("set", false):
			continue
		var ap: AnimationPlayer = v.ap
		if ap == null or not is_instance_valid(ap):
			continue
		var nn: Node3D = v.node
		if int(v.get("dying_until", 0)) > now:
			continue   # 死亡动作播放中：不切 idle/walk
		if now < int(v.get("att_until", 0)):
			# 攻击动作覆盖窗内不切 idle/walk（攻击起步各英雄/小兵触发一次，窗后自然回落）
			if v.get("anim", "") != "attack":
				var c2: String = str(v.get("att_clip", v.get("atk_clip", "")))
				if c2 != "" and ap.has_animation(c2):
					ap.play(c2)
					v.anim = "attack"
			continue
		var pv: Vector3 = v.get("prevp", nn.global_position)
		var cur := nn.global_position
		var dx := cur.x - pv.x
		var dz := cur.z - pv.z
		v.prevp = cur
		var sp := sqrt(dx * dx + dz * dz) / maxf(delta, 0.0001)
		if sp > 0.45:
			var yaw2 := atan2(dx, dz)
			# 本机英雄朝向由预测直接管理（host 是即时 atan2 / 转向模式按键转向），此处不再平滑盖写
			if not (nid == _self_net and _owned):
				var dyaw := wrapf(yaw2 - nn.rotation.y, -PI, PI)
				nn.rotation.y = nn.rotation.y + dyaw * minf(1.0, delta * 10.0)
			if v.get("anim", "") != "walk":
				var cw: String = str(v.get("walk_clip", ""))
				if cw != "" and ap.has_animation(cw):
					ap.play(cw)
					v.anim = "walk"
		else:
			if v.get("anim", "") != "idle":
				var ci: String = str(v.get("idle_clip", ""))
				if ci != "" and ap.has_animation(ci):
					ap.play(ci)
					v.anim = "idle"


# —— #65 单位朝向：小兵/野怪/无动画英雄按位移方向转向（同 host Minion rotation.y=atan2(dir.x,dir.z)）——
func _tick_entity_facing(delta: float) -> void:
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.has("ap"):
			continue   # 有动画的（英雄/小兵/野怪）走 _tick_hero_anims 平滑转向（含攻击朝向覆盖）
		if v.type == NET_TURRET or not v.get("set", false):
			continue
		var nn: Node3D = v.node
		if nn == null or not is_instance_valid(nn):
			continue
		var pv: Vector3 = v.get("prevp", nn.global_position)
		var cur := nn.global_position
		var dx := cur.x - pv.x
		var dz := cur.z - pv.z
		v.prevp = cur
		if dx * dx + dz * dz > 0.0004:
			nn.rotation.y = atan2(dx, dz)


func _tick_turret_visuals(delta: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for nid in _views:
		var v: Dictionary = _views[nid]
		if int(v.get("type", -1)) != NET_TURRET:
			continue
		var node: Node3D = v.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var model: Node3D = v.get("model")
		if model != null and is_instance_valid(model):
			var pivot = model.get_node_or_null("CrystalPivot")
			if pivot != null:
				pivot.rotation.y += delta * (0.85 if str(v.get("name", "")) != "crystal" else 0.52)
				pivot.position.y = sin(now * 1.6 + float(nid) * 0.37) * 0.07
		var active: bool = bool(v.get("tower_shield_active", false)) \
			and float(v.get("tower_shield", 0.0)) > 0.0 \
			and float(v.get("hp", 0.0)) > 0.0
		var sn = v.get("shield_node")
		if active:
			if sn == null or not is_instance_valid(sn):
				sn = NetModels.tower_shield(int(v.get("team", 0)), str(v.get("name", "")) == "crystal")
				node.add_child(sn)
				v["shield_node"] = sn
				v["shield_t"] = 0.0
			sn.visible = true
			v["shield_t"] = float(v.get("shield_t", 0.0)) + delta
			sn.rotation.y += delta * 0.22
			var grow: float = minf(1.0, float(v["shield_t"]) * 6.0)
			var pulse: float = 1.0 + sin(float(v["shield_t"]) * 2.4) * 0.012
			var s: float = lerpf(0.80, 1.0, grow) * pulse
			sn.scale = Vector3(s, s, s)
		elif sn != null and is_instance_valid(sn):
			sn.queue_free()
			v.erase("shield_node")


# 塔基环形铺装（host BattleManager._add_turret_ring_pave 同款：高地 0.177 / 分路 0.152，内圈留塔基洞）
func _add_turret_pave(pos: Vector3, tier: String, team: int) -> void:
	var outer: float = 5.8 if tier == "crystal" else 4.7
	var inner: float = 1.45 if tier == "crystal" else 1.15
	var hq_center := Vector3(-60.0, 0.0, 60.0) if team == TEAM_PLAYER else Vector3(60.0, 0.0, -60.0)
	var on_high: bool = Vector2(pos.x - hq_center.x, pos.z - hq_center.z).length() < 35.0
	var top_y: float = 0.177 if on_high else 0.152
	var pave: Node3D = DecorMesh.turret_ring_pave(pos, inner, outer, top_y)
	pave.name = "TurretRingPave_%d_%d" % [int(round(pos.x)), int(round(pos.z))]
	pave.add_to_group("turret_paves")
	var w := get_node_or_null("World")
	if w != null:
		w.add_child(pave)
	else:
		add_child(pave)


func _make_view(nid: int, typ: int, team: int, name: String) -> Dictionary:
	var node := Node3D.new()
	var team_col := COL_ALLY_DIM
	if team == 0 or team == 1:
		team_col = COL_ALLY_DIM if Config.is_ally(team) else COL_ENEMY
	elif typ != NET_HERO:
		team_col = COL_NEUTRAL
	# 模型 + 头顶血条偏移（≈ 模型顶部）
	var head_off := 1.6
	var tower_ring: MeshInstance3D = null   # 防御塔攻击范围环（存回 view 供快照刷红/绿/黄）
	var epic_ring_ref: MeshInstance3D = null   # 野怪活动圈（默认隐藏，玩家攻击时显示）
	var _ring_r: float = 4.0                   # 野怪活动圈半径（普通营地 4 / 史诗 8，同 host）
	var model_ref: Node3D = null            # 主模型实例（无骨骼动画的兵种做程序化后坐用）
	var buff_rings: Array = []              # 英雄：红/蓝 buff 脚下光环（按快照开关）
	match typ:
		NET_HERO:
			var hm := NetModels.hero(name)
			if hm != null:
				# NetModels.hero 内部已是 HeroModel 根 + 模型×3.0，与主机 _load_hero_model 同结构
				node.add_child(hm)
				model_ref = hm
				# 红/蓝 buff 脚下光环（与单机 Hero.buff_ring_red/blue 同款）→ 放到 view 里按快照开关
				var br_r: MeshInstance3D = MeshFactory.create_buff_aura(0)
				br_r.position = Vector3(0.0, Config.GROUND_FX_Y, 0.0)
				br_r.visible = false
				node.add_child(br_r)
				var br_b: MeshInstance3D = MeshFactory.create_buff_aura(1)
				br_b.position = Vector3(0.0, Config.GROUND_FX_Y + 0.01, 0.0)
				br_b.visible = false
				node.add_child(br_b)
				buff_rings = [br_r, br_b]
				head_off = 4.2     # 与主机 HeroInfoControl 锚点完全一致（body_radius 1.5*2 + 1.2）
			else:
				_add_fallback_visual(node, typ, team_col)
				head_off = 2.6     # 兜底模型锚点随主机下压（3.2 → 2.6）
		NET_TURRET:
			var tm := NetModels.turret(name, team)
			if tm != null:
				node.add_child(tm)
				UnitVisuals.tint_team(tm, team)
				model_ref = tm
			else:
				_add_fallback_visual(node, typ, team_col)
			# 血条锚点：外/二/高地同尺寸 → 同一锚点；水晶更大
			head_off = 4.6
			if name == "crystal":
				head_off = 5.8
			# 塔攻击范围圈（同主机 Turret._create_range_preview：贴地柔化环带，radius = 8.9 + 0.5）
			tower_ring = MeshFactory.create_ground_ring(8.9 + 0.5, Color(1.0, 0.9, 0.35, 0.45))
			tower_ring.name = "TowerRangeRing"
			tower_ring.visible = false   # 与 host 一致：只在「敌方塔 + 本端玩家 ≤11m」时显示
			node.add_child(tower_ring)
		NET_MINION:
			var mm := NetModels.minion(name, team)
			if mm != null:
				node.add_child(mm)
				var mstr := float(mm.get_meta("tint_strength", 0.5))
				UnitVisuals.tint_team(mm, team, mstr)
				model_ref = mm
				# 血条锚点随放大后的兵种高度（模型2倍；超级兵/先锋 = 1.5× 普通兵）
				head_off = 4.6 if name in NetModels.MINION_BIG else 2.9
			else:
				_add_fallback_visual(node, typ, team_col)
				head_off = 0.9
			# 小兵脚下薄环区分敌我（模型同款，靠环色辨识）
			var mr := _make_flat_ring(0.5, 0.62, Color(team_col.r, team_col.g, team_col.b, 0.7))
			mr.position = Vector3(0.0, 0.02, 0.0)
			node.add_child(mr)
		_:
			var jm := NetModels.jungle(name)
			if jm != null:
				node.add_child(jm)
				model_ref = jm
				# 野怪模型2倍后血条抬到头顶（同主机锚点）
				head_off = 4.0
				if NetModels.is_epic_jungle(name):
					head_off = 8.0
					_ring_r = 8.0
				# 活动范围圈（同 host _add_activity_ring(max(activity_radius,4))：普通营地 4m、史诗 8m）
				# 圈固定回营地圆心（top_level，不随怪移动）；怪在圈内=白，拖出圈外=红
				# 默认隐藏：只有本端玩家正在攻击这只野怪时显示（同 host 规则）
				var er := MeshFactory.create_ground_ring(_ring_r, Color(1.0, 1.0, 1.0, 0.42), 0.0)
				er.name = "EpicActivityRing"
				er.top_level = true
				er.visible = false
				node.add_child(er)
				epic_ring_ref = er
			else:
				_add_fallback_visual(node, typ, team_col)
				head_off = 0.9
	# 角色可读性：rim 边缘光 + 脚下接地软阴影（仅英雄，material_overlay 单层，不覆盖原材质）
	if typ == NET_HERO:
		UnitVisuals.attach_hero(node, team, node)
	$Entities.add_child(node)
	# 记录 ModelPivot 的静止姿态：程序化普攻 tween 每次都从这里开始/回到这里，避免被打断后基准漂移（下沉）
	if model_ref != null:
		var _pv := _find_model_pivot(model_ref)
		if _pv != null:
			_pv.set_meta("rest_pos", _pv.position)
			_pv.set_meta("rest_rot", _pv.rotation)
			_pv.set_meta("rest_scl", _pv.scale)
	# 行走质感：客户端同样用步频起伏（dust=false，粒子只在 host 生成，避免双端预算翻倍）
	if model_ref != null:
		# 三端共享行走参数（ActorPresenter，与 host Minion/Hero/JungleMonster 同一份表）
		var _kind := "jungle"
		if typ == NET_HERO:
			_kind = "hero"
		elif typ == NET_MINION:
			_kind = "minion"
		WalkFeel.attach(node, model_ref, ActorPresenter.walk_opts(_kind, name, model_ref))
	# 自己英雄不再额外加竖直光柱（与单机一致，仅保留脚下队伍环）
	var view := {"node": node, "type": typ, "team": team, "name": name,
		"hp": 0.0, "maxhp": 1.0, "bar_off": head_off, "target": null, "set": false,
		"level": 1, "mana": 0.0, "maxmana": 1.0, "shield": 0.0,
		"exp": 0.0, "exp_to_next": 1.0, "under_attack": 0,
		"ring": tower_ring, "epic_ring": epic_ring_ref,   # 塔范围环（快照刷红/绿/黄；非塔为 null）
		"epic_center": Vector3.ZERO, "epic_center_set": false, "epic_red": false,
		"jring_r": (_ring_r if typ == NET_JUNGLE else 4.0), "prev_hp": 0.0, "hit_t": -999.0}
	if typ == NET_HERO:
		view["buff_rings"] = buff_rings
	if model_ref != null:
		view["model"] = model_ref
	# #44 动画：英雄/小兵/野怪模型带 AnimationPlayer 就挂 idle/walk/attack/cast/die 驱动状态
	if typ == NET_HERO or typ == NET_MINION or typ == NET_JUNGLE:
		var ap: AnimationPlayer = _find_ap(node)
		if ap != null:
			# GLB clip 全是 loop=none（host 每物理帧重播维持观感），client 单发播放须先转循环片
			_setup_anim_loops(ap)
			view["ap"] = ap
			view["anim"] = ""
			view["att_until"] = 0
			view["att_play"] = 0
			# 各模型 clip 命名不统一，建 view 时一次性解析缓存，避免每帧遍历 clip 列表
			view["idle_clip"] = _clip_hint(ap, ["idle"])
			view["walk_clip"] = _clip_hint(ap, ["walk", "run"])
			if str(view["walk_clip"]) == "":
				view["walk_clip"] = str(view["idle_clip"])
			view["atk_clip"] = _clip_hint(ap, ["punch", "attack-melee", "attack", "eat", "shoot"])
	view["prevp"] = node.global_position
	return view

# 模型缺失时的几何体兜底（与旧版本观感一致）
func _add_fallback_visual(node: Node3D, typ: int, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.metallic = 0.0
	m.roughness = 0.9
	m.albedo_color = col
	if typ == NET_HERO:
		var c := CapsuleMesh.new()
		c.height = 1.4
		c.radius = 0.45
		var mi := MeshInstance3D.new()
		mi.mesh = c
		mi.material_override = m
		mi.position = Vector3(0.0, 0.7, 0.0)
		node.add_child(mi)
	elif typ == NET_TURRET:
		var cy := CylinderMesh.new()
		cy.top_radius = 0.7
		cy.bottom_radius = 0.9
		cy.height = 2.4
		var mi := MeshInstance3D.new()
		mi.mesh = cy
		mi.material_override = m
		mi.position = Vector3(0.0, 1.2, 0.0)
		node.add_child(mi)
	elif typ == NET_MINION:
		var s := SphereMesh.new()
		s.radius = 0.28
		s.height = 0.56
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		mi.position = Vector3(0.0, 0.32, 0.0)
		node.add_child(mi)
	else:
		var s := SphereMesh.new()
		s.radius = 0.6
		s.height = 1.2
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		mi.position = Vector3(0.0, 0.6, 0.0)
		node.add_child(mi)

# 平铺在地面的圆环。Godot 4.5 TorusMesh 默认就是水平（躺在 XZ 平面、孔轴沿 Y），
# 不得再绕 X 转 90°（那会把地面环立起来成竖直圈）。主机 Turret/Jungle 环均不旋转即平放。
func _make_flat_ring(inner: float, outer: float, col: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = inner
	tor.outer_radius = outer
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = 0.6
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.mesh = tor
	ring.material_override = m
	return ring

# 塔范围环配色：0=红(塔正打玩家) 1=绿(敌方兵线近) 2=黄(默认)——与主机 Turret._update_range_preview 一致
func _set_tower_ring_color(v: Dictionary, st: int) -> void:
	var r: MeshInstance3D = v.get("ring")
	if r == null or not is_instance_valid(r):
		return
	var col := Color(1.0, 0.9, 0.35, 0.45)
	if st == 0:
		col = Color(1.0, 0.28, 0.24, 0.55)
	elif st == 1:
		col = Color(0.45, 1.0, 0.45, 0.5)
	MeshFactory.set_ground_ring_color(r, col)

# —— 施法预览（同主机 Hero 技能预览三件套：范围圈 / AoE填充圆 / 方向箭头）——
func _build_cast_preview() -> void:
	_pv_range = MeshFactory.create_cast_range(Color(0.32, 0.72, 1.0))
	_pv_range.visible = false
	add_child(_pv_range)
	_pv_aoe = MeshFactory.create_cast_area(Color(0.30, 0.72, 1.0), 0)
	_pv_aoe.visible = false
	add_child(_pv_aoe)
	_pv_impact = MeshFactory.create_cast_area(Color(0.30, 0.72, 1.0), 0)
	_pv_impact.visible = false
	add_child(_pv_impact)
	_pv_arrow = Node3D.new()
	_pv_arrow.visible = false
	_pv_shaft = MeshFactory.create_cast_line(Color(0.30, 0.72, 1.0))
	_pv_shaft.position = Vector3(0, 0, 0.5)
	_pv_shaft.scale = Vector3(0.9, 1.0, 1.0)
	_pv_arrow.add_child(_pv_shaft)
	_pv_head = MeshFactory.create_cast_reticle(Color(0.36, 0.80, 1.0))
	_pv_head.position = Vector3(0, 0, 1.0)
	_pv_arrow.add_child(_pv_head)
	add_child(_pv_arrow)

## 召唤师技能施法预览（同主机 Hero._update_summoner_preview：范围圈/落点圈/位移箭头）
func _update_summoner_preview() -> void:
	var sname := str(_own.get("summoner_name", ""))
	var sid := str(HeroPickData.SUMMONERS.get(sname, ""))
	var sk = SkillDatabase.get_skill(sid) if sid != "" else null
	if sk == null:
		_hide_cast_preview()
		return
	var drag: Vector2 = _pad.get_summoner_drag()
	var ry := float(_own.get("ry", 0.0))
	var self_pos := _self_pos()
	var aim_dir := Vector3(sin(ry), 0.0, cos(ry))
	if drag.length() > 12.0:
		# 屏幕拖拽 → 反投影到地面，取世界方向（按本机镜头，红方镜头转 180° 同样正确）
		var sc := get_viewport().get_visible_rect().size * 0.5 + drag.normalized() * 500.0
		var wpv: Vector3 = _ground_hit(sc)
		var dvv: Vector3 = wpv - self_pos
		dvv.y = 0.0
		if dvv.length() > 0.2:
			aim_dir = dvv.normalized()
	else:
		var md := _ground_hit(_mouse_screen) - self_pos
		md.y = 0.0
		if md.length() > 0.2:
			aim_dir = md.normalized()
	var pv_hero := str(_manifest.get("hero_name", ""))
	if _pv_color_key != pv_hero + "|sum":
		_pv_color_key = pv_hero + "|sum"
		var pv_col := Color(0.32, 0.72, 1.0)
		if pv_hero != "":
			pv_col = Vfx.color_for_hero(pv_hero)
		for mi in [_pv_range, _pv_aoe, _pv_impact, _pv_shaft, _pv_head]:
			MeshFactory.set_cast_preview_color(mi, pv_col)
	var ground_y := Config.GROUND_FX_Y
	var self_v := Vector3(self_pos.x, ground_y, self_pos.z)
	_pv_range.visible = false
	_pv_aoe.visible = false
	_pv_impact.visible = false
	_pv_arrow.visible = false
	match sname:
		"闪现":
			var land := self_pos + aim_dir * 5.0
			_pv_arrow.visible = true
			_pv_shaft.position = Vector3(0, 0, 2.5)
			_pv_shaft.scale = Vector3(0.9, 1.0, 5.0)
			_pv_head.position = Vector3(0, 0, 5.0)
			_pv_arrow.global_position = self_v + Vector3(0, 0.025, 0)
			_pv_arrow.rotation.y = atan2(aim_dir.x, aim_dir.z)
			_pv_impact.visible = true
			_pv_impact.global_position = Vector3(land.x, ground_y + 0.01, land.z)
			_pv_impact.scale = Vector3.ONE
		"终结", "惩击":
			var rng: float = 5.0 if sname == "终结" else 3.0
			var aim := self_pos + aim_dir * rng
			_pv_range.visible = true
			_pv_range.global_position = Vector3(self_pos.x, ground_y + 0.02, self_pos.z)
			_pv_range.scale = Vector3(rng, rng, rng)
			_pv_aoe.visible = true
			MeshFactory.set_cast_area_mode(_pv_aoe, 1)
			_pv_aoe.global_position = Vector3(aim.x, ground_y, aim.z)
			_pv_aoe.scale = Vector3(1.2, 1, 1.2)
		"晕眩", "弱化", "治疗术":
			var rad: float = 3.0 if sname == "治疗术" else 5.0
			_pv_aoe.visible = true
			MeshFactory.set_cast_area_mode(_pv_aoe, 0)
			_pv_aoe.global_position = self_v
			_pv_aoe.scale = Vector3(rad, 1, rad)
			_pv_impact.visible = true
			_pv_impact.global_position = self_v + Vector3(0, 0.01, 0)
			_pv_impact.scale = Vector3(rad, 1, rad)
		_:
			pass   # 疾跑/狂暴/净化/传送：无地面指示


func _hide_cast_preview() -> void:
	if _mm != null:
		_mm.aim_shot = {}
	if _pv_range:
		_pv_range.visible = false
	if _pv_aoe:
		_pv_aoe.visible = false
	if _pv_impact:
		_pv_impact.visible = false
	if _pv_arrow:
		_pv_arrow.visible = false

# 每帧：找到「正在按住瞄准的技能」→ 复刻主机预览。门禁与 _handle_skill_release 一致
#（cd/已学/蓝量）；aim 来源：键盘 type0=_pending_skill 鼠标地面点，触控=拖拽方向 `_cast_aim`。
func _update_cast_preview() -> void:
	if _pv_range == null:
		return
	if not _owned or _state != 1 or int(_own.get("alive", 1)) != 1:
		_hide_cast_preview()
		return
	var slot := -1
	var aim := Vector3.ZERO
	var touch_aiming := false
	var ry := float(_own.get("ry", 0.0))
	if _pending_skill >= 0 and _pending_skill < _skills.size():
		slot = _pending_skill
		aim = _ground_hit(_mouse_screen)
	elif _pad != null and _pad.touch_active:
		for i in range(3):
			if i >= _skills.size():
				continue
			if _pad.is_skill_held(i):
				slot = i
				touch_aiming = true
				var drag: Vector2 = _pad.get_skill_drag(i)
				aim = _cast_aim(i, _skills[i], drag, ry)
				break
	if slot < 0:
		# 召唤师技能：按住召唤师按钮时给同样的施法预览
		if _pad != null and _pad.touch_active and _pad.get_summoner_held() \
				and str(_own.get("summoner_name", "")) != "" \
				and float(_own.get("summoner_cd", 0.0)) <= 0.05:
			_update_summoner_preview()
			return
		_hide_cast_preview()
		return
	var sk: Dictionary = _skills[slot]
	var cds: Array = _own.get("cd", [])
	if slot < cds.size() and float(cds[slot]) > 0.05:
		_hide_cast_preview()
		return
	var lvls: Array = _own.get("levels", [])
	var slv := int(lvls[slot]) if slot < lvls.size() else 0
	if slv <= 0:
		_hide_cast_preview()
		return
	var cost := float(sk.get("mana", 0.0))
	var pw := float(sk.get("pw", 0.0))
	if slv >= 1:
		cost = maxf(cost - pw * float(slv - 1), 0.0)
	if float(_own.get("mana", 0.0)) < cost:
		_hide_cast_preview()
		return
	var self_pos := _self_pos()
	# 全图技能（鲁班2 / 后羿3）：给小地图喂瞄准方向 + 命中高亮（同主机 Minimap）
	var gs_name := str(_own.get("name", ""))
	if gs_name == "":
		gs_name = str(_manifest.get("hero_name", ""))
	var gs_prof: Dictionary = SkillDatabase.global_shot_profile(gs_name, slot)
	if _mm != null:
		if gs_prof.is_empty():
			_mm.aim_shot = {}
		else:
			var a_dir: Vector3 = aim - self_pos
			a_dir.y = 0.0
			if a_dir.length() < 0.15:
				a_dir = Vector3(sin(ry), 0.0, cos(ry))
			_mm.aim_shot = {"from": self_pos, "dir": a_dir.normalized(),
				"len": float(gs_prof["len"]), "hit_r": float(gs_prof["hit_r"]),
				"only_hero": bool(gs_prof["only_hero"]), "col": gs_prof["color"]}
	var typ := int(sk.get("type", 0))
	var range := float(sk.get("range", 0.0))
	var has_range := range > 0.0
	if range <= 0.0:
		range = 3.0
	# 预览配色跟随本端英雄元素色（同主机）
	var pv_hero := str(_manifest.get("hero_name", ""))
	var pv_key := "%s|%d" % [pv_hero, slot]
	if pv_key != _pv_color_key:
		_pv_color_key = pv_key
		var pv_col := Color(0.32, 0.72, 1.0)
		if pv_hero != "":
			pv_col = Vfx.color_for_hero(pv_hero)
			if slot > 0:
				pv_col = pv_col.lerp(Vfx.color2_for_hero(pv_hero), 0.16 * slot)
		for mi in [_pv_range, _pv_aoe, _pv_impact, _pv_shaft, _pv_head]:
			MeshFactory.set_cast_preview_color(mi, pv_col)
	_pv_aim = aim
	var rad := float(sk.get("rad", 0.0))
	_pv_impact.visible = false
	# 自身施法范围圈（有施法距离的瞄准技能；线性/位移用箭头示意长度，不复用范围圈）
	if has_range and (typ == 0 or typ == 1 or typ == 2 or typ == 6):
		_pv_range.visible = true
		_pv_range.global_position = Vector3(self_pos.x, Config.GROUND_FX_Y + 0.02, self_pos.z)
		_pv_range.scale = Vector3(range, range, range)
	else:
		_pv_range.visible = false
	if typ == 1:
		# 范围技能：柔光落点 + 准星
		_pv_aoe.visible = true
		MeshFactory.set_cast_area_mode(_pv_aoe, 0)
		_pv_aoe.global_position = Vector3(aim.x, Config.GROUND_FX_Y, aim.z)
		_pv_aoe.scale = Vector3(maxf(rad, 0.1), 1, maxf(rad, 0.1))
	elif typ == 3 or typ == 4:
		# 线性/位移：贴地能量带 + 终点准星（len：type3 优先子弹射程 br，type4 优先位移 dis）
		var len := range
		if typ == 3:
			len = float(sk.get("br", 0.0))
		else:
			len = float(sk.get("dis", 0.0))
		if len <= 0.0:
			len = range
		var dir := aim - self_pos
		dir.y = 0.0
		var angle_y := atan2(dir.x, dir.z) if dir.length() > 0.01 else ry
		_pv_arrow.visible = true
		_pv_shaft.position = Vector3(0, 0, len * 0.5)
		_pv_shaft.scale = Vector3(0.9, 1.0, len)
		_pv_head.position = Vector3(0, 0, len)
		_pv_arrow.global_position = Vector3(self_pos.x, Config.GROUND_FX_Y + 0.025, self_pos.z)
		_pv_arrow.rotation.y = angle_y
		_pv_aoe.visible = false
		if rad > 0.0:
			_pv_impact.visible = true
			_pv_impact.global_position = Vector3(aim.x, Config.GROUND_FX_Y + 0.01, aim.z)
			_pv_impact.scale = Vector3(rad, 1, rad)
	elif typ == 2 or typ == 6:
		# 增益/护盾：有半径的补落点范围，纯自身增益用脚下柔光
		_pv_arrow.visible = false
		if rad > 0.0:
			_pv_impact.visible = true
			_pv_impact.global_position = Vector3(aim.x, Config.GROUND_FX_Y + 0.01, aim.z)
			_pv_impact.scale = Vector3(rad, 1, rad)
			_pv_aoe.visible = false
		else:
			_pv_aoe.visible = true
			MeshFactory.set_cast_area_mode(_pv_aoe, 0)
			_pv_aoe.global_position = Vector3(self_pos.x, Config.GROUND_FX_Y, self_pos.z)
			_pv_aoe.scale = Vector3(1.6, 1, 1.6)
			_pv_impact.visible = false
	elif typ == 0:
		# 指向型：落点四段括号准星；有半径则叠加命中范围
		_pv_aoe.visible = true
		MeshFactory.set_cast_area_mode(_pv_aoe, 1)
		_pv_aoe.global_position = Vector3(aim.x, Config.GROUND_FX_Y, aim.z)
		_pv_aoe.scale = Vector3(1.2, 1, 1.2)
		_pv_arrow.visible = false
		if rad > 0.0:
			_pv_impact.visible = true
			_pv_impact.global_position = Vector3(aim.x, Config.GROUND_FX_Y + 0.01, aim.z)
			_pv_impact.scale = Vector3(rad, 1, rad)
	else:
		_pv_aoe.visible = false
		_pv_arrow.visible = false

# —— 接管 ——
# own 快照里的死亡回放兜底载荷（host 在死亡跃迁帧塞入）
func _check_own_death_recap() -> void:
	if _dr == null or _own.is_empty():
		return
	var al := int(_own.get("alive", 1))
	if _own_alive_prev == 1 and al == 0:
		# 死亡跃迁：主动向主机要一次回放数据（1→0 那一帧的 RPC/快照可能丢失，仅靠它们会空面板）
		NetSession.send_command([NetSession.C_RECAP])
		if OS.is_debug_build():
			print("[Net] 死亡回放：已向主机请求 payload")
	_own_alive_prev = al
	var d = _own.get("dr", null)
	if d is Dictionary and not (d as Dictionary).is_empty():
		_dr.show_payload(d)


# 索敌头像条数据：普攻射程内敌方英雄（同 host TouchController._update_enemy_picker：仅英雄、按距离排序、≤5）
func _enemy_picker_list() -> Array:
	if not _owned or int(_own.get("alive", 1)) != 1:
		return []
	var sp := _self_pos()
	var own_team: int = int(_manifest.get("team", TEAM_PLAYER))
	var reach: float = maxf(_reach, 1.0) + 1.2
	var cand: Array = []
	for nid in _views:
		var v: Dictionary = _views[nid]
		if int(v.get("type", -1)) != NET_HERO:
			continue
		if int(v.get("team", -1)) == own_team:
			continue
		if float(v.get("hp", 0.0)) <= 0.0:
			continue
		var nd = v.get("node")
		if nd == null or not is_instance_valid(nd):
			continue
		var d: float = sp.distance_to(nd.global_position)
		if d > reach:
			continue
		cand.append([int(nid), d])
	cand.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var out: Array = []
	for i in range(mini(cand.size(), 5)):
		var nid2 := int(cand[i][0])
		var vv: Dictionary = _views[nid2]
		out.append([nid2, str(vv.get("name", "")), nid2 == _manual_net])
	return out


# 点选索敌头像：再点已锁目标=解锁；否则锁该英雄并让普攻优先追它（同 host set_locked_target）
func _on_enemy_picker_tapped(nid: int) -> void:
	if nid < 0:
		return
	if _manual_net == nid:
		_manual_net = -1
		# 同 host：解锁后回到自动选敌（切换优先级会清 host 侧 manual_target）
		NetSession.send_command([NetSession.C_PRIORITY, _pad.attack_priority if _pad != null else 0])
		return
	_manual_net = nid
	NetSession.send_command([NetSession.C_ATTACK, nid])


func _on_takeover(manifest: Dictionary) -> void:
	# 主机在 ACK 前会重发同一份清单：重复应用会把镜头/输入状态重置，直接确认即可。
	if _owned and int(manifest.get("net_id", -1)) == _self_net:
		NetSession.ack_takeover_applied()
		return
	_manifest = manifest
	# 阵营：客户端可选择红/蓝方；接管后把本机 Config.player_team 切到该阵营，
	# 所有共享 HUD/小地图/聊天/面板/结算都按本地阵营着色与判断（host 端仍按模拟阵营）
	var own_team := clampi(int(manifest.get("team", Config.player_team)), 0, 1)
	Config.player_team = own_team
	Config._team_rolled = true
	if _mm != null and is_instance_valid(_mm):
		_mm.player_team = own_team
	_skills = manifest.get("skills", [])
	_self_net = int(manifest.get("net_id", -1))
	if _rp != null and is_instance_valid(_rp):
		_rp.self_net = _self_net
	_owned = _self_net >= 0
	_pending_skill = -1
	# 播报「你击杀…/你被击杀」需知道本地玩家英雄名（host 走 BM.hero 兜底，不必设）
	if _owned:
		SfxManager.own_name = str(manifest.get("hero_name", ""))
	if _owned:
		NetSession.hide_spectate_overlay()
		_status = "已接管 %s（%s方）—— 摇杆/WASD 移动，普攻轮盘攻击，R 回城" % [
			str(manifest.get("hero_name", "英雄")), "红" if own_team == 1 else "蓝"]
		_reach = float(manifest.get("reach", 0.0))
		_cam_focus = Vector3(float(manifest.get("x", 0)), 0.0, float(manifest.get("z", 0)))
		# 复位直驱/普攻发送状态与本地优先级（主机英雄接管时已是净初态）
		_reset_drive_state()
		if _pad:
			_pad.set_attack_priority(NetTouchPadScript.PRIO_AUTO)

# —— 输入 ——
# 接管态：世界鼠标输入全部让位触摸层（主机桌面同样用 emulate_touch 触摸控件操控，
# 空白区域点击不产生世界命令）。未接管的观战态保留鼠标环绕/缩放。
## 空格普攻：放在 _input（GUI 之前）处理，避免被聚焦按钮/聊天输入框吃掉
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k2 := event as InputEventKey
	if not k2.pressed or k2.echo:
		return
	if k2.physical_keycode != KEY_SPACE and k2.keycode != KEY_SPACE:
		return
	if ChatService.typing or not _owned or _state != 1:
		return
	if int(_own.get("alive", 1)) != 1:
		return
	# 商店/属性面板打开时不响应（同触摸普攻的 ui_block 规则）
	if (_sp != null and _sp.visible) or (_rp != null and _rp.visible):
		return
	_attack_nearest_in_reach()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.echo:
			return
		if k.pressed and (k.keycode == KEY_F5 or k.physical_keycode == KEY_F5):
			GameEntity.debug_show_ai_chip = not GameEntity.debug_show_ai_chip
			return
		if not _owned:
			# 未接管/观战也能看全局英雄面板（同 host：C/T 随时可开）
			if k.pressed and k.physical_keycode == KEY_C:
				_toggle_roster("attr")
			elif k.pressed and k.physical_keycode == KEY_T:
				_toggle_team_decision()
			elif k.pressed and k.physical_keycode == KEY_ESCAPE and _rp and _rp.visible:
				_rp.hide_panel()
			elif k.pressed and k.physical_keycode == KEY_ESCAPE and _tdv != null and _tdv.visible:
				_tdv.visible = false
			return
		if not k.pressed:
			# 松开 1/2/3：结束 type0「按住瞄准-松手施放」（_pending_skill 在按住期驱动准星）
			match k.physical_keycode:
				KEY_1, KEY_2, KEY_3:
					if _state == 1:
						_kbd_release_slot(k.physical_keycode - KEY_1)
			return
		# P1c：键盘热键双轨 —— 与主机桌面热键对齐（物理键位，见 project.godot：
		# skill_0..2=49/50/51，recover=53，summoner_spell=54；兰陵隐身 4、回城 R）
		match k.physical_keycode:
			KEY_R:
				NetSession.send_command([NetSession.C_RECALL])
			KEY_1, KEY_2, KEY_3:
				if _state == 1:
					_kbd_press_slot(k.physical_keycode - KEY_1)
			KEY_4:
				if _state == 1 and _skills.size() > 3 and _skills[3] != null:
					var sp := _self_pos()
					NetSession.send_command([NetSession.C_CAST, 3, -1, sp.x, sp.z])
					SfxManager.client_cast_sfx(3, _skills[3])
			KEY_5:
				if _state == 1:
					_kbd_recover()
			KEY_6:
				if _state == 1:
					_kbd_summoner()
			KEY_SPACE:
				# 空格：锁定普攻范围内最近的敌方单位（同主机 BattleManager._unhandled_input 的空格分支）
				if _state == 1 and int(_own.get("alive", 1)) == 1:
					_attack_nearest_in_reach()
			KEY_TAB:
				# 第一人称 / 第三人称切换（同主机 Tab → _set_camera_mode）；阵亡/未接管自动忽略
				if _state == 1 and int(_own.get("alive", 1)) == 1:
					_first_person = not _first_person
			KEY_C:
				_toggle_roster("attr")   # P3c 属性面板
			KEY_T:
				_toggle_team_decision()   # 团队决策面板（同 host T）
			KEY_ESCAPE:
				if _rp and _rp.visible:
					_rp.hide_panel()
				elif _tdv != null and _tdv.visible:
					_tdv.visible = false
			KEY_Y:
				# 桌面自由镜头回正（同 host BattleManager：Y 键清空 cam_pan_offset）
				_cam_pan = Vector3.ZERO
				_cam_mid_drag = false
				_cam_pan_decay = false
		return
	if _owned:
		# 桌面鼠标（同 host BattleManager 世界点击）：左键=锁定敌方/施法目标，右键=移动到地面点，中键=拖镜
		if event is InputEventMouseButton:
			var mb2 := event as InputEventMouseButton
			if mb2.button_index == MOUSE_BUTTON_LEFT and mb2.pressed:
				# 复活头像带：阵亡时点存活队友头像切换观战镜头（同 host respawn_container）
				if _hud != null and int(_own.get("alive", 1)) != 1:
					var wh: Array = _hud.widget_at(mb2.position)
					if wh.size() >= 4 and int(wh[1]) == int(_manifest.get("team", TEAM_PLAYER)) and int(wh[2]) == 0:
						_spectate_nid = int(wh[0])
						return
				# 属性面板标题条：点击展开/收起（同 host 点标题条 toggle_attribute_panel）
				if _hud != null and _hud._attr_head_rect.has_point(mb2.position):
					_hud.attr_collapsed = not _hud.attr_collapsed
					return
				if _pending_skill >= 0:
					_do_action(mb2.position)
				else:
					var tid := _pick_entity(mb2.position, false)
					if tid >= 0:
						NetSession.send_command([NetSession.C_ATTACK, tid])
				return
			if mb2.button_index == MOUSE_BUTTON_RIGHT and mb2.pressed:
				var g2 := _ground_hit(mb2.position)
				NetSession.send_command([NetSession.C_MOVE, g2.x, g2.z])
				return
			if mb2.button_index == MOUSE_BUTTON_MIDDLE:
				_cam_mid_drag = mb2.pressed
				if not mb2.pressed:
					_cam_pan_prev_valid = false
		elif event is InputEventMouseMotion and _cam_mid_drag:
			_cam_pan.x -= (event as InputEventMouseMotion).relative.x / 60.0
			_cam_pan.z += (event as InputEventMouseMotion).relative.y / 60.0
			if _cam_pan.length() > 45.0:
				_cam_pan = _cam_pan.normalized() * 45.0
			_cam_pan_decay = false
		return
	if event is InputEventMouseMotion:
		_mouse_screen = event.position
		if _rmb_down():
			_cam_yaw -= event.relative.x * 0.22
			_cam_pitch = clampf(_cam_pitch - event.relative.y * 0.18, 8.0, 80.0)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = clampf(_cam_dist - 3.0, 12.0, 90.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = clampf(_cam_dist + 3.0, 12.0, 90.0)

func _rmb_down() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

# 空格普攻：在客户端已知实体里找自身普攻射程内最近的敌方目标 → 发 C_ATTACK 锁定
# （主机空格是把 manual_target 设为最近的敌人，语义一致）
func _attack_nearest_in_reach() -> void:
	var reach := float(_own.get("reach", 0.0))
	if reach <= 0.5:
		reach = 6.0
	var sp := _self_pos()
	var best := -1
	var best_d := 1e20
	for nid in _views:
		var v: Dictionary = _views[nid]
		if int(v.get("team", -1)) == Config.player_team:
			continue
		if float(v.get("hp", 0.0)) <= 0.0:
			continue
		var d := sp.distance_to(_entity_pos(nid))
		if d <= reach and d < best_d:
			best_d = d
			best = nid
	if best >= 0:
		_manual_net = best
		NetSession.send_command([NetSession.C_ATTACK, best])

# —— P3c：C/T 面板切换（同视图再按=关闭；打开后面板自 0.5s 节流拉取 roster）——
func _toggle_roster(v: String) -> void:
	if _rp == null:
		return
	if _rp.visible and _rp.view == v:
		_rp.hide_panel()
	else:
		_rp.show_panel(v)

func _toggle_pending(idx: int) -> void:
	if not _owned:
		return
	if _pending_skill == idx:
		_pending_skill = -1
		return
	_pending_skill = idx

func _do_action(scr: Vector2) -> void:
	if not _owned or _state != 1:
		return
	var ground := _ground_hit(scr)
	if _pending_skill >= 0:
		var sk = _skills[_pending_skill] if _pending_skill < _skills.size() else null
		SfxManager.client_cast_sfx(_pending_skill, sk)
		var tid := _pick_entity(scr, true)
		if tid >= 0:
			NetSession.send_command([NetSession.C_CAST, _pending_skill, tid, ground.x, ground.z])
		else:
			NetSession.send_command([NetSession.C_CAST, _pending_skill, -1, ground.x, ground.z])
		_pending_skill = -1
		return
	var tid := _pick_entity(scr, false)
	if tid >= 0:
		NetSession.send_command([NetSession.C_ATTACK, tid])
	else:
		NetSession.send_command([NetSession.C_MOVE, ground.x, ground.z])

# P1b 说明：旧的 _auto_upgrade（自动分配技能点）已移除 —— 手动升级钮（升级小箭头）替代，
# 与主机触控一致；否则自动抢点会与玩家手动点大招升级冲突。

# —— 拾取 / 投影 ——
func _pick_radius(v: Dictionary) -> float:
	var typ: int = v.type
	var nm: String = str(v.get("name", ""))
	match typ:
		NET_HERO:
			return 1.4
		NET_TURRET:
			match nm:
				"crystal": return 2.6
				"high": return 2.2
				_: return 1.8
		NET_MINION:
			if nm == "siege":
				return 1.1
			if nm == "dragon" or nm == "storm" or nm == "shadow_dragon":
				return 2.0
			return 0.7
		_:
			if NetModels.is_epic_jungle(nm):
				return 3.2
			if nm == "red_buff" or nm == "blue_buff":
				return 1.8
			return 1.2

func _pick_entity(scr: Vector2, allow_ally: bool) -> int:
	var from := _cam.project_ray_origin(scr)
	var dir := _cam.project_ray_normal(scr)
	var best := -1
	var best_d := 1e9
	for nid in _views:
		var v: Dictionary = _views[nid]
		# 攻击模式：我方单位不可点（敌方塔/兵/野怪可点）
		if not allow_ally and v.team == Config.player_team:
			continue
		var gp: Vector3 = v.node.global_position
		var r := _pick_radius(v)
		var center := gp + Vector3.UP * (r * 0.9)
		var to_c := center - from
		var t := to_c.dot(dir)
		if t < 0.0:
			continue
		var closest := from + dir * t
		var d := closest.distance_to(center)
		if d <= r:
			if d < best_d:
				best_d = d
				best = nid
	return best

func _ground_hit(scr: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(scr)
	var dir := _cam.project_ray_normal(scr)
	if absf(dir.y) < 1e-4:
		return from + dir * 120.0
	var t := -from.y / dir.y
	if t < 0.0:
		return from + dir * 120.0
	return from + dir * t

func _project_entities(inp: Array) -> Array:
	var out := []
	for row in inp:
		var p: Vector3 = row[0]
		if _cam.is_position_behind(p):
			continue
		var sp := _cam.unproject_position(p)
		var mp := _cam.unproject_position(p + _cam.global_transform.basis.x * 1.0)
		var w := maxf(sp.distance_to(mp), 2.0)
		var h := w * 0.16
		out.append({"x": sp.x, "y": sp.y, "w": w, "h": h, "ratio": row[1], "col": row[2]})
	return out

func _project_point(p: Vector3) -> Vector2:
	if _cam == null or _cam.is_position_behind(p):
		return Vector2(-9999.0, -9999.0)
	return _cam.unproject_position(p)

# —— P2 世界血条收集（同主机 HUD._update_health_bars：死亡隐藏 / 相机背后剔除 / 固定屏幕尺寸）——
func _collect_world_bars() -> Array:
	var rows := []
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.node == null:
			continue
		if v.hp <= 0.0:
			continue   # 死亡隐藏（主机 health<=0 即移除/不绘制）
		if _first_person and nid == _self_net:
			continue   # 第一人称：自身世界血条隐藏（主机同刻锚点在相机正上方被背面剔除）
		var anchor: Vector3 = v.node.global_position + Vector3.UP * float(v.get("bar_off", 0.0))
		if _cam.is_position_behind(anchor):
			continue
		var sp := _cam.unproject_position(anchor)
		var dist: float = _cam.global_position.distance_to(v.node.global_position)
		var is_monster: bool = int(v.type) == NET_JUNGLE
		var is_turret_v: bool = int(v.type) == NET_TURRET
		# 主机 HUD 同规则：小兵远处直接舍弃（塔/野怪不剔）
		if not (is_turret_v or is_monster) and int(v.type) != NET_HERO and dist > 44.0:
			continue
		match int(v.type):
			NET_HERO:
				rows.append(_hero_bar_row(nid, v, sp))
			NET_TURRET:
				# 塔盾：host 血条读 tower.tower_shield（不是 entity.shield_remaining），同款接入
				var _tsh: float = float(v.get("tower_shield", 0.0)) if bool(v.get("tower_shield_active", false)) else 0.0
				var _trow := _unit_bar_row(nid, v, sp, 300.0, 22.0, 92.0, false, true, true, 2000.0)
				_trow["shield"] = _tsh
				rows.append(_trow)
			NET_MINION:
				var mn := str(v.get("name", ""))
				var vanguard := mn.find("先锋") >= 0 or mn in ["dragon", "storm", "shadow_dragon"]
				# 满血小兵且中远距离：缩小细条（72×8），同 host HUD
				var small: bool = float(v.hp) >= float(v.maxhp) and dist > 20.0
				if small:
					rows.append(_unit_bar_row(nid, v, sp, 72.0, 8.0, 84.0, false, false, false, 1000.0, false, true))
				else:
					rows.append(_unit_bar_row(nid, v, sp, 110.0, 15.0, 84.0, false, false, vanguard, 1000.0))
			NET_JUNGLE:
				if NetModels.is_epic_jungle(str(v.get("name", ""))):
					# 史诗怪大号分格紫条：宽随血量每格 1000 自适应（同主机 HUD）
					var segs := maxi(1, int(ceil(float(v.maxhp) / 1000.0)))
					rows.append(_unit_bar_row(nid, v, sp, clampf(segs * 22.0, 380.0, 880.0), 30.0, 84.0, true, false, true, 1000.0, true))
				else:
					rows.append(_unit_bar_row(nid, v, sp, 110.0, 15.0, 84.0, false, false, true, 1000.0, true))
	return rows

func _ai_chip_dict(a) -> Dictionary:
	if a is Array and (a as Array).size() >= 4:
		return {"label": str(a[0]), "r": float(a[1]), "g": float(a[2]), "b": float(a[3])}
	return {}


func _hero_bar_row(nid: int, v: Dictionary, sp: Vector2) -> Dictionary:
	# 主机 HeroInfoControl 颜色：敌方红 / 本窗口玩家绿 / 队友青（host 以 is_ai 区分，我们以是否 self 区分）
	var bar_col := Color(1.0, 0.33, 0.264)
	if Config.is_ally(int(v.team)):
		# 自己英雄恒为绿色（同 host HUD.gd），其余友方青色
		bar_col = Color(0.33, 0.95, 0.42, 1.0) if nid == _self_net else Color(0.0, 0.886, 1.0)
	return {"kind": "hero", "nid": nid, "cx": sp.x, "cy": sp.y,
		"name": str(v.get("name", "")), "pname": str(v.get("pname", "")), "level": int(v.get("level", 1)),
		"hp": float(v.hp), "maxhp": float(v.maxhp), "hp_col": bar_col,
		"shield": float(v.get("shield", 0.0)), "mvp": bool(v.get("mvp", false)),
		"status": v.get("status", []),
		"markers": v.get("markers", []),
		"ai_chip": _ai_chip_dict(v.get("ai_chip", [])),
		"mana": float(v.get("mana", 0.0)), "maxmana": float(v.get("maxmana", 0.0)),
		"exp": float(v.get("exp", 0.0)), "exp_to_next": float(v.get("exp_to_next", 0.0)),
		"hidden": bool(v.get("hidden", false)) and Config.is_ally(int(v.team)),
		"lyf": v.get("lyf", [])}

## 补刀提示（同 host HUD last_hit 规则）：本机英雄一次普攻、税前护甲按 602 公式减免
func _last_hit_of(team: int, hp: float, armor: float) -> bool:
	var _atk := float(_own.get("aa_dmg", 0.0))
	if _atk <= 0.0 or hp <= 0.0:
		return false
	if team == int(_manifest.get("team", TEAM_PLAYER)):
		return false
	var _pen := float(_own.get("flat_pen", 0.0))
	var res := maxf(0.0, armor - _pen)
	var dmg := _atk * (1.0 - res / (res + 602.0))
	return hp < dmg


func _unit_bar_row(nid: int, v: Dictionary, sp: Vector2, w: float, h: float, label_off: float,
		epic := false, turret := false, ticks := false, tick_step := 1000.0,
		monster := false, small := false) -> Dictionary:
	return {"kind": "unit", "nid": nid, "cx": sp.x, "cy": sp.y, "w": w, "h": h,
		"team": int(v.team), "epic": epic, "shield": float(v.get("shield", 0.0)),
		"armor": float(v.get("armor", 0.0)),
		"last_hit": _last_hit_of(int(v.team), float(v.hp), float(v.get("armor", 0.0))),
		"name": str(v.get("name", "")), "hp": float(v.hp), "maxhp": float(v.maxhp),
		"label_off": label_off, "lyf": v.get("lyf", []), "mk": v.get("mk", []),
		"turret": turret, "ticks": ticks, "tick_step": tick_step,
		"monster": monster, "small": small,
		"shield_icon": bool(v.get("shield_icon", false))}

# —— 世界 / 相机 / HUD 搭建 ——
func _make_mat(col: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = 0.0
	m.roughness = rough
	m.albedo_color = col
	return m

var _net_lane_idx := 0

func _add_lane_plane_net(center: Vector3, size: Vector2, diag: bool) -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	plane.mesh = pm
	if diag:
		plane.rotation_degrees = Vector3(0.0, -45.0, 0.0)
	# host 同款：不同走向错开 1~2mm 防交叉口 z-fighting；路缘沿长边铺
	plane.position = center + Vector3(0.0, 0.14 + 0.0012 * float(_net_lane_idx % 6), 0.0)
	_net_lane_idx += 1
	plane.material_override = MapVisuals.ground_material()
	var curb_mat: Material = DecorMesh.rock_material()
	var along_x: bool = size.x >= size.y
	var curb_len: float = size.x if along_x else size.y
	for sd in [-1.0, 1.0]:
		var offset: float = (size.y * 0.5 + 0.25) * sd if along_x else (size.x * 0.5 + 0.25) * sd
		for seg in _curb_segments_net(plane.position, plane.rotation.y, along_x, offset, curb_len):
			var span: float = seg.y - seg.x
			if span < 0.3:
				continue
			var cm := BoxMesh.new()
			var curb := MeshInstance3D.new()
			if along_x:
				cm.size = Vector3(span, 0.22, 0.6)
				curb.position = Vector3((seg.x + seg.y) * 0.5, -0.04, offset)
			else:
				cm.size = Vector3(0.6, 0.22, span)
				curb.position = Vector3(offset, -0.04, (seg.x + seg.y) * 0.5)
			curb.mesh = cm
			curb.material_override = curb_mat
			plane.add_child(curb)
	$World.add_child(plane)


# 路缘被擂台挖断后的剩余区间（与 host BattleManager._curb_segments 完全同款）
func _curb_segments_net(plane_pos: Vector3, yaw: float, along_x: bool, offset: float, length: float) -> Array:
	var half: float = length * 0.5
	var inv := Basis(Vector3.UP, yaw).inverse()
	var r: float = ARENA_RADIUS + 0.35
	var gaps: Array = []
	for spot in ARENA_SPOTS:
		var lp: Vector3 = inv * (spot - plane_pos)
		var across: float = lp.z if along_x else lp.x
		var along: float = lp.x if along_x else lp.z
		var d: float = absf(across - offset)
		if d >= r:
			continue
		var dx: float = sqrt(r * r - d * d)
		gaps.append(Vector2(along - dx, along + dx))
	var segs: Array = []
	if gaps.is_empty():
		segs.append(Vector2(-half, half))
		return segs
	gaps.sort_custom(func(a, b): return a.x < b.x)
	var cursor: float = -half
	for g in gaps:
		var a: float = maxf(g.x, -half)
		var b: float = minf(g.y, half)
		if b <= a:
			continue
		if a > cursor + 0.3:
			segs.append(Vector2(cursor, a))
		cursor = maxf(cursor, b)
	if half > cursor + 0.3:
		segs.append(Vector2(cursor, half))
	if segs.size() > 1:
		var longest: Vector2 = segs[0]
		for sgm in segs:
			if (sgm.y - sgm.x) > (longest.y - longest.x):
				longest = sgm
		return [longest]
	return segs


func _build_world() -> void:
	# 视觉与 host BattleManager._create_map 同源：同一套 MapVisuals 着色器/材质/装饰
	# 1. 浮空岛顶面（与 host 同源：岛外 discard，露出天空）
	var wild := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(220.0, 220.0)
	wm.subdivide_width = 120
	wm.subdivide_depth = 120
	wild.mesh = wm
	wild.position = Vector3(0.0, -0.02, 0.0)
	wild.material_override = MapVisuals.island_ground_material()
	$World.add_child(wild)
	# 2. 分路浅绿（土路由地面 shader 按世界坐标采样，平面只负责形状；同 host y=0.05）
	_add_lane_plane_net(Vector3(-55.0, 0.0, 0.0), Vector2(15.4, 126.0), false)
	_add_lane_plane_net(Vector3(-30.0, 0.0, 30.0), Vector2(16.0, 84.85), true)
	_add_lane_plane_net(Vector3(0.0, 0.0, 55.0), Vector2(126.0, 15.4), false)
	_add_lane_plane_net(Vector3(55.0, 0.0, 0.0), Vector2(15.4, 126.0), false)
	_add_lane_plane_net(Vector3(30.0, 0.0, -30.0), Vector2(16.0, 84.85), true)
	_add_lane_plane_net(Vector3(0.0, 0.0, -55.0), Vector2(126.0, 15.4), false)
	# 3. 高地青砖扇形（蓝左下 / 红右上，host 同款石材着色器）
	_add_high_ground_fan(Vector3(-60.0, 0.2, 60.0), -90.0, 0.0, Vector3(-53.0, 0.0, 53.0))
	_add_high_ground_fan(Vector3(60.0, 0.2, -60.0), 90.0, 180.0, Vector3(53.0, 0.0, -53.0))
	_add_high_ground_aprons_net(Vector3(-60.0, 0.0, 60.0), Vector3(-1,0,0), Vector3(0,0,1), Vector3(-53.0, 0.0, 53.0))
	_add_high_ground_aprons_net(Vector3(60.0, 0.0, -60.0), Vector3(1,0,0), Vector3(0,0,-1), Vector3(53.0, 0.0, -53.0))
	_add_high_ground_rim_net(Vector3(-60.0, 0.0, 60.0), -90.0, 0.0)
	_add_high_ground_rim_net(Vector3(60.0, 0.0, -60.0), 90.0, 180.0)
	# 3.5 泉水圆盘 + 光环
	_add_fountain(Vector3(-62.0, 0.0, 62.0), Color(0.2, 0.55, 1.0, 0.35))
	_add_fountain(Vector3(62.0, 0.0, -62.0), Color(1.0, 0.25, 0.2, 0.35))
	# 三条兵线交汇处的青砖擂台（host ARENA_SPOTS / ARENA_RADIUS 同款）
	for _ai in range(ARENA_SPOTS.size()):
		var _arena: Node3D = DecorMesh.arena_visual(ARENA_SPOTS[_ai], ARENA_RADIUS)
		_arena.name = "LaneArena%d" % _ai
		_arena.position = ARENA_SPOTS[_ai]
		$World.add_child(_arena)
	# 地面碰撞（与 host 同层同尺寸；客户端技能瞄准/点击走数学投影，但保持一致）
	var _gb := StaticBody3D.new()
	_gb.collision_layer = 2
	var _col := CollisionShape3D.new()
	var _box := BoxShape3D.new()
	_box.size = Vector3(Config.MAP_SIZE, 0.1, Config.MAP_SIZE)
	_col.shape = _box
	_gb.add_child(_col)
	_gb.position = Vector3(0.0, -0.1, 0.0)
	$World.add_child(_gb)
	# 4. 河道（水面 shader，y=0.02 同 host；不透明避免破坏贴地特效排序）
	_add_river()
	# 4.5 装饰物（草丛/河岸石墙/陶罐，host 同款 MultiMesh + 固定种子 → 位置一致）
	MapVisuals.scatter_decorations($World)
	# 4.6 浮空岛背景（岛缘/岛底/墙外树林，host 同源）
	MapVisuals.spawn_floating_island($World)
	# 5. 静态容器（墙/草丛/营地环，map payload 到达后由 _apply_map 填充）
	_static_root = Node3D.new()
	_static_root.name = "Statics"
	$World.add_child(_static_root)


func _add_high_ground_fan(center: Vector3, start_deg: float, end_deg: float, brick_center: Vector3) -> void:
	var csg := CSGPolygon3D.new()
	var poly := PackedVector2Array()
	poly.append(Vector2.ZERO)
	var steps := 32
	for i in range(steps + 1):
		var a := deg_to_rad(start_deg + (end_deg - start_deg) * float(i) / float(steps))
		poly.append(Vector2(cos(a) * 35.0, sin(a) * 35.0))
	csg.polygon = poly
	csg.depth = 0.05
	csg.position = center + Vector3(0.0, -0.025, 0.0)
	csg.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	# 与 host 一致：高地是以水晶为圆心的同心青砖环（无水晶圆心时退回旧材质）
	if brick_center != Vector3.ZERO:
		csg.material_override = DecorMesh.hq_ring_brick_material(brick_center)
	else:
		csg.material_override = MapVisuals.high_ground_material()
	$World.add_child(csg)


func _add_high_ground_aprons_net(center: Vector3, out_a: Vector3, out_b: Vector3, brick_center: Vector3) -> void:
	# 必须使用与高地扇形完全相同的同心环青砖材质；之前用 high_ground_material 会在直边处
	# 露出材质/UV 接缝，看起来像砖面和墙体之间少了一块。
	var mat := DecorMesh.hq_ring_brick_material(brick_center)
	var inward_a := -out_a
	var inward_b := -out_b
	_add_flat_quad_net(center + out_a * 1.5 + inward_b * 17.5, Vector2(3.0, 35.0), mat, 0.177)
	_add_flat_quad_net(center + out_b * 1.5 + inward_a * 17.5, Vector2(35.0, 3.0), mat, 0.177)
	_add_flat_quad_net(center + out_a * 1.5 + out_b * 1.5, Vector2(3.0, 3.0), mat, 0.177)


func _add_flat_quad_net(pos: Vector3, size_v: Vector2, mat: Material, y: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size_v
	mi.mesh = pm
	# PlaneMesh 本身就是水平 XZ 面，不能再绕 X 转 90°，否则石台会竖起来
	mi.position = Vector3(pos.x, y, pos.z)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	$World.add_child(mi)


func _add_high_ground_rim_net(center: Vector3, start_deg: float, end_deg: float) -> void:
	# 与 host BattleManager._add_high_ground_rim 完全同参数：96 段，内沿贴砖面 34.5/0.176；
	# 外沿压在分路上时抬到 0.146（否则斜裙落到路面以下，低机位会看到缝）。
	var steps := 96
	var raw: Array = []
	for i in steps + 1:
		var a := deg_to_rad(start_deg + (end_deg - start_deg) * float(i) / float(steps))
		var wx: float = center.x + cos(a) * 36.0
		var wz: float = center.z + sin(a) * 36.0
		raw.append(0.146 if MapVisuals._lane_mask(wx, wz) > 0.05 else 0.025)
	var out_ys: Array = []
	for i in raw.size():
		var v: float = float(raw[i])
		v = maxf(v, float(raw[clampi(i - 1, 0, raw.size() - 1)]))
		v = maxf(v, float(raw[clampi(i + 1, 0, raw.size() - 1)]))
		out_ys.append(v)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		var a0 := deg_to_rad(start_deg + (end_deg - start_deg) * float(i) / float(steps))
		var a1 := deg_to_rad(start_deg + (end_deg - start_deg) * float(i + 1) / float(steps))
		var y0: float = float(out_ys[i])
		var y1: float = float(out_ys[i + 1])
		var in0 := center + Vector3(cos(a0) * 34.5, 0.176, sin(a0) * 34.5)
		var in1 := center + Vector3(cos(a1) * 34.5, 0.176, sin(a1) * 34.5)
		var out0 := center + Vector3(cos(a0) * 36.4, y0, sin(a0) * 36.4)
		var out1 := center + Vector3(cos(a1) * 36.4, y1, sin(a1) * 36.4)
		st.add_vertex(in0); st.add_vertex(in1); st.add_vertex(out0)
		st.add_vertex(in1); st.add_vertex(out1); st.add_vertex(out0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "HighGroundRim"
	mi.mesh = st.commit()
	mi.material_override = _double_sided_rock_net()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	$World.add_child(mi)


func _double_sided_rock_net() -> ShaderMaterial:
	var base := DecorMesh.rock_material()
	var sh := (base.shader as Shader).duplicate() as Shader
	sh.code = sh.code.replace(
		"render_mode diffuse_burley, specular_schlick_ggx;",
		"render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _add_fountain(center: Vector3, color: Color) -> void:
	# 与 host BattleManager._add_fountain 完全同款：石砌池沿 + 波纹水面 + 中央喷泉柱 + 溅水粒子 + 旋转符文环 + 顶光
	var root := Node3D.new()
	root.name = "Fountain"
	root.position = Vector3(center.x, 0.0, center.z)
	$World.add_child(root)
	var stone := DecorMesh.rock_material()
	var basin := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 3.30
	bcyl.bottom_radius = 3.50
	bcyl.height = 0.28
	bcyl.radial_segments = 40
	basin.mesh = bcyl
	basin.position = Vector3(0, 0.14, 0)
	basin.material_override = stone
	root.add_child(basin)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.87
	torus.outer_radius = 3.37
	torus.rings = 40
	torus.ring_segments = 10
	rim.mesh = torus
	rim.position = Vector3(0, 0.30, 0)
	rim.material_override = stone
	root.add_child(rim)
	var water := MeshInstance3D.new()
	var wcyl := CylinderMesh.new()
	wcyl.top_radius = 2.95
	wcyl.bottom_radius = 2.95
	wcyl.height = 0.05
	wcyl.radial_segments = 48
	water.mesh = wcyl
	water.position = Vector3(0, 0.295, 0)
	water.material_override = _fountain_water_material(color)
	root.add_child(water)
	var ped := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.42
	pcyl.bottom_radius = 0.72
	pcyl.height = 0.95
	pcyl.radial_segments = 16
	ped.mesh = pcyl
	ped.position = Vector3(0, 0.75, 0)
	ped.material_override = stone
	root.add_child(ped)
	var jet := MeshInstance3D.new()
	var jcyl := CylinderMesh.new()
	jcyl.top_radius = 0.20
	jcyl.bottom_radius = 0.34
	jcyl.height = 2.10
	jcyl.radial_segments = 14
	jet.mesh = jcyl
	jet.position = Vector3(0, 2.30, 0)
	jet.material_override = _fountain_jet_material(color)
	root.add_child(jet)
	var splash := CPUParticles3D.new()
	splash.amount = 44
	splash.lifetime = 1.15
	var drop := SphereMesh.new()
	drop.radius = 0.065
	drop.height = 0.13
	drop.radial_segments = 6
	drop.rings = 3
	splash.mesh = drop
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	splash.emission_sphere_radius = 0.42
	splash.position = Vector3(0, 3.30, 0)
	splash.direction = Vector3.UP
	splash.spread = 42.0
	splash.initial_velocity_min = 0.6
	splash.initial_velocity_max = 1.9
	splash.gravity = Vector3(0, -5.2, 0)
	splash.scale_amount_min = 0.7
	splash.scale_amount_max = 1.6
	splash.color = Color(color.r * 0.5 + 0.5, color.g * 0.55 + 0.55, 1.0, 0.75)
	var splash_mat := StandardMaterial3D.new()
	splash_mat.albedo_color = Color(0.82, 0.93, 1.0, 1.0)
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.vertex_color_use_as_albedo = true
	splash.material_override = splash_mat
	root.add_child(splash)
	var rune := Node3D.new()
	rune.name = "RuneRing"
	root.add_child(rune)
	var rune_mesh := BoxMesh.new()
	rune_mesh.size = Vector3(0.14, 0.035, 0.40)
	var rune_mat := StandardMaterial3D.new()
	rune_mat.albedo_color = color
	rune_mat.emission_enabled = true
	rune_mat.emission = Color(color.r, color.g, color.b)
	rune_mat.emission_energy_multiplier = 2.4
	rune_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in range(12):
		var a: float = TAU * float(i) / 12.0
		var rmi := MeshInstance3D.new()
		rmi.mesh = rune_mesh
		rmi.material_override = rune_mat
		rmi.position = Vector3(cos(a) * 3.72, 0.09, sin(a) * 3.72)
		rmi.rotation.y = -a
		rune.add_child(rmi)
	var glow := MeshInstance3D.new()
	var gcyl := CylinderMesh.new()
	gcyl.top_radius = 3.60
	gcyl.bottom_radius = 3.60
	gcyl.height = 0.02
	gcyl.radial_segments = 40
	glow.mesh = gcyl
	glow.position = Vector3(0, 0.05, 0)
	glow.material_override = _fountain_glow_material(color)
	root.add_child(glow)
	var lt := OmniLight3D.new()
	lt.light_color = color
	lt.light_energy = 2.0
	lt.omni_range = 11.0
	lt.position = Vector3(0, 2.9, 0)
	root.add_child(lt)
	if not is_inside_tree():
		return
	var tw := create_tween().set_loops()
	tw.tween_property(rune, "rotation:y", TAU, 16.0).from(0.0)


# 泉水水面/水柱/地光材质（与 host BattleManager 完全同款着色器）
func _fountain_water_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

uniform vec4 tint : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform vec4 glow : source_color = vec4(0.4, 0.8, 1.0, 1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = clamp(length(uv), 0.0, 1.0);
	float t = TIME;
	float w = sin(r * 26.0 - t * 3.0) * 0.5 + 0.5;
	float w2 = sin(r * 10.0 + t * 1.5) * 0.5 + 0.5;
	float rings = smoothstep(0.45, 0.95, w * 0.55 + w2 * 0.55);
	ALBEDO = tint.rgb * (0.70 + 0.40 * rings);
	EMISSION = glow.rgb * (0.16 + 0.95 * rings * (1.0 - r * 0.55));
	ALPHA = clamp(0.55 + 0.42 * rings * (1.0 - r), 0.0, 1.0);
	ROUGHNESS = 0.10;
	SPECULAR = 0.85;
	METALLIC = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("glow", Color(color.r * 0.45 + 0.45, color.g * 0.55 + 0.55, 1.0))
	return mat


func _fountain_jet_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(0.6, 0.85, 1.0, 1.0);

void fragment() {
	float flow = fract(UV.y * 2.4 - TIME * 1.5);
	float stripe = smoothstep(0.0, 0.30, flow) * smoothstep(1.0, 0.55, flow);
	float wob = 0.5 + 0.5 * sin(TIME * 3.0 + UV.y * 9.0 + UV.x * 6.2831);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * (0.85 + 1.6 * stripe);
	ALPHA = clamp(0.14 + 0.42 * stripe * wob, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Color(color.r * 0.45 + 0.45, color.g * 0.55 + 0.55, 1.0))
	return mat


func _fountain_glow_material(color: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = clamp(length(uv), 0.0, 1.0);
	float pulse = 0.72 + 0.28 * sin(TIME * 1.6);
	float a = (1.0 - smoothstep(0.0, 1.0, r)) * 0.45 + smoothstep(0.62, 1.0, r) * 0.60;
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 1.5 * pulse;
	ALPHA = clamp(a * pulse, 0.0, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", color)
	return mat


func _add_river() -> void:
	var r := MeshInstance3D.new()
	var rm := PlaneMesh.new()
	rm.size = Vector2(20.0, 141.0)
	rm.subdivide_width = 24   # 顶点波动需要足够细分
	rm.subdivide_depth = 70
	r.mesh = rm
	r.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	r.position = Vector3(0.0, 0.02, 0.0)
	r.material_override = MapVisuals.water_material()
	$World.add_child(r)
	# 两岸装饰：湿沙河滩 + 半浸礁石 + 芦苇 + 睡莲
	MapVisuals.spawn_river_banks($World)


# —— 静态地图布局（墙/草丛/营地环），从 NetSession 的 map payload 一次性填充 ——
# 递归关闭投影（同 host Wall._set_shadow_off）
func _net_set_shadow_off(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_net_set_shadow_off(c)


func _apply_map_if_ready() -> void:
	if _map_applied or _static_root == null:
		return
	var payload := NetSession.get_map_payload()
	if payload.is_empty():
		return
	var bushes: Array = payload.get("bushes", [])
	var walls: Array = NetSession.decode_walls(payload.get("walls", []))
	var camps: Array = payload.get("camps", [])
	if bushes.is_empty() and walls.is_empty() and camps.is_empty():
		return
	_map_applied = true
	NetSession.ack_map_applied()
	for b in bushes:
		if b.size() < 2:
			continue
		var bush := NetModels.bush()
		if bush == null:
			continue
		bush.position = Vector3(float(b[0]), 0.0, float(b[1]))
		_static_root.add_child(bush)
		# 程序化灌木已自带苔藓盘/草叶/风摆（与主机同源），不再叠加旧装饰
	for w in walls:
		if w.size() < 3:
			continue
		var root := Node3D.new()
		root.position = Vector3(float(w[0]), 0.0, float(w[1]))
		root.rotation.y = float(w[2])
		# 与主机同源：payload 第 4 位标记高地外墙用高规格模型，第 5/6 位标记外周连续城墙
		var hq: bool = w.size() > 3 and int(w[3]) == 1
		var outer: bool = w.size() > 4 and int(w[4]) == 1
		var outer_len: float = float(w[5]) if w.size() > 5 else 2.0
		var cont_len: float = float(w[6]) if w.size() > 6 else 0.0
		var pillar: bool = int(w[7]) == 1 if w.size() > 7 else false
		var thick: float = float(w[9]) if w.size() > 9 else 1.0
		# 位置哈希种子（同 host Wall.gd：镜像对称）
		var seed_v: int = int(round(absf(root.position.x) * 10.0)) * 37 + int(round(absf(root.position.z) * 10.0)) * 91
		var wall_model := NetModels.wall(hq, outer, outer_len, cont_len, pillar, seed_v, thick)
		if wall_model == null:
			continue
		# 与主机同源的墙脚贴地抬升（分路/高地台面不埋墙根）
		wall_model.position.y = DecorMesh.wall_ground_y(root.position)
		root.add_child(wall_model)
		# 较厚的老墙挂常春藤等装饰（同 host Wall.gd 条件）
		if cont_len > 0.0 and maxf(thick, 1.0) > 1.10 and seed_v % 3 == 0:
			root.add_child(DecorMesh.wall_decor_visual(seed_v))
		# 静态墙体不投影（同 host：700+ 墙段是阴影 pass 主要 draw call）
		_net_set_shadow_off(wall_model)
		_static_root.add_child(root)
		# 程序化石墙已自带基底碎石与苔藓（与主机同源），不再叠加旧装饰
	# 野怪活动范围圈不预生成：与单机一致，只有"本端玩家正在攻击该野怪"时由
	# _update_epic_rings / _update_jungle_rings 逐只显示（此前的常显黄圈是多余表现）
	print("[NetClient] 静态地图已应用 bushes=", bushes.size(), " walls=", walls.size(), " camps=", camps.size())

# 进场加载层进度：地图同步 → 首帧快照 → 接管 → 入场运镜开始，才允许揭开
var _intro_wait := 0.0
func _tick_intro_loading() -> void:
	if _intro_loading == null or not is_instance_valid(_intro_loading):
		return
	_intro_wait += get_process_delta_time()
	var p := 0.10
	if _map_applied:
		p = 0.32
	if _state == 1:
		p = 0.55
	if _owned:
		p = 0.78
	# 入场运镜真正开始（_cam_intro_t>=0）后再走满并淡出，画面直接从远景推近，不经过地图中心
	if _owned and _cam_intro_t >= 0.0:
		p = 1.0
	# 观战/异常兜底：最长等 8s
	if _intro_wait > 8.0:
		p = 1.0
	_intro_loading.set_progress(p)
	if p >= 1.0:
		_intro_loading.manual_progress = false
		_intro_loading.set("_t", 99.0)
		_intro_loading = null

func _apply_web_perf() -> void:
	# WebGL 单线程 + 网络快照：关闭实时阴影/降低特效档，优先保帧率与操作跟手。
	for n in find_children("*", "DirectionalLight3D", true):
		if n is DirectionalLight3D:
			(n as DirectionalLight3D).shadow_enabled = false


func _build_camera() -> void:
	# 环境/灯光与 host 完全同源：天空盒 + 天空环境光 + ACES + 深度雾 + 暖阳光/冷补光
	MapVisuals.setup_environment(self)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.05
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()

func _update_camera() -> void:
	if _finale_cam_locked:
		return
	if _cam == null:
		return
	if _owned:
		if _first_person and int(_own.get("alive", 1)) == 1:
			# 第一人称：镜头在英雄头部，朝向跟随英雄面朝方向（own.ry = host hero.rotation.y）
			_cam.fov = 90.0 - _fov_punch_cur
			_cam.global_position = _cam_focus + CAM_FP_EYE
			_cam.rotation = Vector3(0.0, float(_own.get("ry", 0.0)) + PI, 0.0)
			return
		# 接管：固定俯视主机镜头 —— 视角锁定（fov70 / -60°，与 host BattleManager 完全一致），只随英雄平移。
		# 这样摇杆/键盘的「世界方向移动」与主机屏幕方向 1:1。
		var zoom := 1.0
		# 兰陵王隐身中：同主机把固定跟随镜头拉远/拉高 25%（看得更广）
		if int(_own.get("hidden_self", 0)) == 1:
			zoom = 1.25
		# host：目标点 = 英雄 + 跟随偏移 + 拖动平移偏移；震屏在其后叠加
		# 红方：镜头绕 Y 轴 180°（与单机 BattleManager.cam_yaw = PI 一致，出生在右下、操作方向同手感）
		var flip_yaw := PI if int(Config.player_team) == 1 else 0.0
		var cam_off := CAM_FOLLOW_OFF.rotated(Vector3.UP, flip_yaw)
		var pan_rot := _cam_pan.rotated(Vector3.UP, flip_yaw)
		var target := _cam_focus + cam_off * zoom + pan_rot + Vector3.UP * HERO_BAR_CENTER_UP + _shake_offset()
		if _cam_intro_t < 0.0:
			_cam_intro_t = 0.0
		if _cam_intro_t < CAM_INTRO_DUR:
			_cam_intro_t += get_process_delta_time()
			var e := 1.0 - pow(1.0 - clampf(_cam_intro_t / CAM_INTRO_DUR, 0.0, 1.0), 3.0)
			_cam.global_position = target + Vector3(0.0, 70.0, 130.0).rotated(Vector3.UP, flip_yaw) * (1.0 - e)
			_cam.rotation_degrees = Vector3(lerpf(-72.0, -60.0, e), rad_to_deg(flip_yaw), 0.0)
			_cam.fov = lerpf(52.0, 70.0, e) - _fov_punch_cur
			return
		_cam.global_position = target
		_cam.rotation_degrees = Vector3(-60.0, rad_to_deg(flip_yaw), 0.0)
		_cam.fov = 70.0 - _fov_punch_cur
		return
	var pitch := deg_to_rad(_cam_pitch)
	var yaw := deg_to_rad(_cam_yaw)
	var hoz := _cam_dist * cos(pitch)
	var off := Vector3(sin(yaw) * hoz, _cam_dist * sin(pitch), cos(yaw) * hoz)
	_cam.global_position = _cam_focus + off
	_cam.look_at(_cam_focus + Vector3.UP * 1.2, Vector3.UP)


# —— 手感：镜头反馈（照抄 host BattleManager camera_shake/fov_punch/hitstop；客户端只有表现） ——
func _camera_shake(amp: float = 0.12, dur: float = 0.22) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_dur = maxf(_shake_dur, dur)
	_shake_t = maxf(_shake_t, dur)


func _shake_offset() -> Vector3:
	if _shake_t <= 0.0:
		return Vector3.ZERO
	var k := _shake_t / maxf(0.001, _shake_dur)
	var a := _shake_amp * k * k
	var now := Time.get_ticks_msec() * 0.001
	return Vector3(sin(now * 61.0), sin(now * 47.0) * 0.6, cos(now * 53.0)) * a


func _fov_punch(amount: float = 2.5, dur: float = 0.35) -> void:
	_fov_punch_amp = amount
	_fov_punch_dur = maxf(0.01, dur)
	_fov_punch_t = _fov_punch_dur


func _local_hitstop(dur: float = 0.035) -> void:
	var now := Time.get_ticks_msec()
	if now < _hitstop_until:
		return
	_hitstop_until = now + int(dur * 1000.0)
	Engine.time_scale = 0.12


# 屏幕闪光：同 host UI_Manager.flash_screen（0→0.26 用 25% 时长，再 75% 时长回落）
func _screen_flash(color: Color, dur: float = 0.18) -> void:
	if _flash_rect == null:
		var cl := CanvasLayer.new()
		cl.layer = UiKit.LAYER_POPUP + 5
		add_child(cl)
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.color = Color(0, 0, 0, 0)
		_flash_rect.visible = false
		cl.add_child(_flash_rect)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.visible = true
	_flash_rect.color = Color(color.r, color.g, color.b, 0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.26, dur * 0.25)
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, dur * 0.75)
	_flash_tween.tween_callback(func(): _flash_rect.visible = false)


# 本机大招本地即时反馈（host Hero._start_casting → BattleManager.on_big_cast，参数查 SpellFxTable）
func _play_big_cast_feedback() -> void:
	var hn := str(_manifest.get("hero_name", ""))
	if hn == "" and _hud != null:
		hn = str(_hud.name_text)
	var ent: Dictionary = SpellFxTable.get_ult(hn)
	_camera_shake(float(ent.get("shake", 0.10)), 0.28)
	_fov_punch(2.5, 0.40)
	if bool(ent.get("heavy", false)):
		_local_hitstop(0.03)
	_screen_flash(Vfx.color_for_hero(hn).lerp(Color.WHITE, 0.55), 0.20)


func _tick_feedback(delta: float) -> void:
	# 顿帧复位（每帧墙钟判定；不用 SceneTreeTimer，避免 time_scale 下计时偏差）
	if Engine.time_scale != 1.0 and Time.get_ticks_msec() >= _hitstop_until:
		Engine.time_scale = 1.0
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - delta)
		if _shake_t <= 0.0:
			_shake_amp = 0.0
	if _fov_punch_t > 0.0:
		_fov_punch_t = maxf(0.0, _fov_punch_t - delta)
		var e := 1.0 - _fov_punch_t / _fov_punch_dur
		var k := (e / 0.3) if e < 0.3 else ((1.0 - e) / 0.7)
		_fov_punch_cur = _fov_punch_amp * clampf(k, 0.0, 1.0)
	else:
		_fov_punch_cur = 0.0


# —— 右半屏拖拽取景（同 host BattleManager._update_cam_pan：增量累加、上限 45m、松手 10/s 回正） ——
func _update_cam_pan(delta: float) -> void:
	if not _owned or _first_person or int(_own.get("alive", 1)) != 1:
		_cam_pan_prev_valid = false
		if not _cam_pan_decay:
			_cam_pan = Vector3.ZERO
			return
	var allow: bool = _owned and not _first_person and int(_own.get("alive", 1)) == 1 \
		and _pad != null and _pad.camera_pan_active()
	if not allow:
		_cam_pan_prev_valid = false
		if not _cam_pan_decay:
			return
		if _cam_pan.length() < 0.05:
			_cam_pan = Vector3.ZERO
			_cam_pan_decay = false
		else:
			_cam_pan = _cam_pan.lerp(Vector3.ZERO, clampf(delta * 10.0, 0.0, 1.0))
		return
	_cam_pan_decay = true
	var cur: Vector2 = _pad.get_camera_pan_current()
	if _cam_pan_prev_valid:
		var ga := _ground_hit(_cam_pan_prev)
		var gb := _ground_hit(cur)
		_cam_pan += Vector3(ga.x - gb.x, 0.0, ga.z - gb.z)
		if _cam_pan.length() > 45.0:
			_cam_pan = _cam_pan.normalized() * 45.0
	else:
		_cam_pan_prev_valid = true
	_cam_pan_prev = cur


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_HUD
	add_child(cl)
	_hud = Hud.new()
	cl.add_child(_hud)
	_hud.safe_top = UiKit.safe_top()
	_hud.hero_hit_cb = _on_net_hero_hit
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if OS.has_feature("web"):
		_net_dbg = Label.new()
		_net_dbg.anchor_left = 0.0
		_net_dbg.anchor_top = 1.0
		_net_dbg.anchor_right = 1.0
		_net_dbg.anchor_bottom = 1.0
		_net_dbg.offset_top = -34.0
		_net_dbg.offset_bottom = -8.0
		_net_dbg.offset_left = 12.0
		_net_dbg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_net_dbg.add_theme_font_size_override("font_size", 13)
		_net_dbg.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0, 0.85))
		_net_dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cl.add_child(_net_dbg)

# 英雄受击闪白：世界血条掉血 → 对应视图节点闪白（客户端无 Hero 实体，纯节点容错）
func _on_net_hero_hit(nid: int) -> void:
	var v = _views.get(nid)
	if v == null:
		return
	var n: Node3D = v.get("node")
	if n != null and is_instance_valid(n):
		UnitVisuals.flash(n)

func _hud_scale() -> float:
	# P0：与单机 UI_Manager.ui_scale() 完全同式（以 2400 虚拟宽为 1.0，再 ×1.35），
	# 仅用于顶部战况/属性面板等 UI_Manager 同源元素；世界血条按 host HUD 原始像素绘制。
	return UiKit.scale()

func _skill_disp(i: int) -> String:
	if i >= _skills.size():
		return ""
	return str(_skills[i].get("name", ""))

# —— 接管触摸层（P1a：摇杆 / 普攻轮盘 / 推塔 / 小兵 / 移动模式）——
func _build_pad() -> void:
	_pad = NetTouchPadScript.new()
	add_child(_pad)
	_pad.enemy_picker_tapped.connect(_on_enemy_picker_tapped)

# —— P2 小地图（复刻主机 Minimap.gd：左上 inset40 / 300×300 / 原生锚点布局）——
func _build_minimap() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_MINIMAP   # 世界血条/HUD(20)之上、触摸层(100)之下；只盖住地图区域
	add_child(cl)
	_mm = NetMiniMapScript.new()
	cl.add_child(_mm)
	_mm.mouse_filter = Control.MOUSE_FILTER_STOP
	_mm.offset_left = 40.0 + UiKit.safe_left()
	_mm.offset_top = 40.0 + UiKit.safe_top()
	_mm.offset_right = 40.0 + UiKit.safe_left() + NetMiniMapScript.MINIMAP_SIZE
	_mm.offset_bottom = 40.0 + UiKit.safe_top() + NetMiniMapScript.MINIMAP_SIZE

# —— P3a 目标信息面板：host own.tgt 每帧喂入，客户端只读复刻 host target_detail_panel ——
func _build_target_panel() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 55   # 世界血条/HUD(20)之上、小地图(80)/触摸层之下
	add_child(cl)
	_tp = NetTargetPanelScript.new()
	cl.add_child(_tp)

# —— P3b buff 图标行：host own.buffs 每帧喂入，客户端只读复刻主机 collect_buff_rows/BuffIcon ——
func _build_buff_row() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 60   # 目标面板(55)之上、小地图(80)/触摸层(100)之下；图标行在屏幕底部中央，不与触摸钮重叠
	add_child(cl)
	_br = NetBuffRowScript.new()
	cl.add_child(_br)

# —— 元流之子·泉水流派切换：读 own.x/z/name/yl_pick，右上角钮 + 四选一面板（发送 C_YUANLIU_PICK 由 host 校验）——
func _build_settings() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_OVERLAY
	add_child(cl)
	_set_layer = cl
	# 齿轮按钮：位置与 host settings_btn 一致（右锚 -108..-12，top 308）
	var gear := TouchActionButtonScript.new()
	gear.name = "NetSettingsBtn"
	gear.label_text = "✦"
	gear.label_font_size = 54.0
	gear.color = Color(1.0, 1.0, 1.0, 0.9)
	gear.hold_to_act = false
	gear.emit_activated_on_press = true
	gear.anchor_left = 1.0
	gear.anchor_top = 0.0
	gear.anchor_right = 1.0
	gear.offset_left = -108.0
	gear.offset_right = -12.0
	gear.offset_top = 308.0
	gear.offset_bottom = 344.0
	gear.activated.connect(_toggle_settings)
	cl.add_child(gear)

	var panel := PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD, true, 0.96))
	panel.offset_left = -520.0
	panel.offset_right = -40.0
	panel.offset_top = 352.0
	panel.offset_bottom = 640.0
	cl.add_child(panel)
	_set_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var t := Label.new()
	t.text = "设置"
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", UiKit.C_GOLD)
	v.add_child(t)
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 10)
	v.add_child(vrow)
	var vl := Label.new()
	vl.text = "音量"
	vl.add_theme_font_size_override("font_size", 22)
	vl.add_theme_color_override("font_color", UiKit.C_TEXT)
	vrow.add_child(vl)
	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 100.0
	_vol_slider.step = 1.0
	_vol_slider.value = _master_volume_pct()
	_vol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol_slider.custom_minimum_size = Vector2(0, 34)
	_vol_slider.value_changed.connect(_on_volume_changed)
	vrow.add_child(_vol_slider)
	var sur := Button.new()
	sur.text = "发起投降"
	sur.custom_minimum_size = Vector2(0, 52)
	for st in ["normal", "hover", "pressed"]:
		sur.add_theme_stylebox_override(st, UiKit.skin_button(st, UiKit.C_DANGER, false))
	sur.add_theme_font_size_override("font_size", 22)
	sur.pressed.connect(func():
		NetSession.send_command([NetSession.C_SURRENDER])
		if _surrender_lab != null:
			_surrender_lab.text = "已请求主机发起投降投票（需 6:00 后）"
	)
	v.add_child(sur)
	_surrender_lab = Label.new()
	_surrender_lab.text = "联机投降由主机按同一套投票规则裁决"
	_surrender_lab.add_theme_font_size_override("font_size", 18)
	_surrender_lab.add_theme_color_override("font_color", UiKit.C_TEXT_DIM)
	v.add_child(_surrender_lab)
	# 键位自定义布局（同 host TouchController 编辑器：拖动/±大小/PlayerPrefs 持久化）
	var lay_btn := Button.new()
	lay_btn.text = "自定义键位布局"
	lay_btn.custom_minimum_size = Vector2(0, 52)
	for st2 in ["normal", "hover", "pressed"]:
		lay_btn.add_theme_stylebox_override(st2, UiKit.skin_button(st2, UiKit.C_TEAM0, false))
	lay_btn.add_theme_font_size_override("font_size", 22)
	lay_btn.pressed.connect(func():
		_set_panel.visible = false
		if _pad != null:
			_pad.enter_layout_edit())
	v.add_child(lay_btn)
	# 关闭按钮（此前联机设置只能再点齿轮关闭，补一个显式关闭）
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(0, 48)
	for st3 in ["normal", "hover", "pressed"]:
		close_btn.add_theme_stylebox_override(st3, UiKit.skin_button(st3, UiKit.C_TEAM0, false))
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(func(): _set_panel.visible = false)
	v.add_child(close_btn)


func _toggle_settings() -> void:
	if _set_panel != null:
		_set_panel.visible = not _set_panel.visible


func _master_volume_pct() -> float:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return 100.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)


func _on_volume_changed(v: float) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(v / 100.0, 0.0, 1.0)))


func _build_yuanliu_switch() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_OVERLAY  # 高于触摸层(100)/C·T(101)/商店(102)/数值弹出(103)，低于结算(110)
	add_child(cl)
	_ys = NetYuanliuScript.new()
	cl.add_child(_ys)

# —— P3c 属性(C)/队伍(T)面板：host _rpc_roster，模态盖过触摸层(101) ——
# 顶右侧战况带点击区：与 host 版式一致（右锚 -781..-371 / top 6..196），点开属性（全局英雄）面板
func _build_roster_hit() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 45   # 高于 HUD(20)/战报(40)，低于小地图(80)/各模态面板
	add_child(cl)
	var hit := Button.new()
	hit.name = "RosterBandHit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.anchor_left = 1.0
	hit.anchor_right = 1.0
	hit.offset_left = -781.0
	hit.offset_right = -371.0
	hit.offset_top = 6.0
	hit.offset_bottom = 196.0
	hit.tooltip_text = "查看全局英雄面板（同主机点战况带 / C 键）"
	hit.pressed.connect(func(): _toggle_roster("attr"))
	cl.add_child(hit)


# T 团队决策面板（与单机同版面：时间/模式/经济/龙/双方分路计划，共享 TeamDecisionView）
func _build_team_decision() -> void:
	_tdv_layer = CanvasLayer.new()
	_tdv_layer.layer = UiKit.LAYER_OVERLAY - 2
	add_child(_tdv_layer)
	_tdv = TeamDecisionViewScript.new()
	_tdv_layer.add_child(_tdv)


func _toggle_team_decision() -> void:
	if _tdv == null:
		return
	if _tdv.visible:
		_tdv.visible = false
		return
	_tdv.set_data(_team_decision_data())
	_tdv.visible = true


func _team_decision_data() -> Dictionary:
	var tt: Array = _own.get("tt", [])
	var out := {
		"time": float(tt[4]) if tt.size() > 4 else 0.0,
		"mode": str(tt[0]) if tt.size() > 0 else "—",
		"dragon": bool(int(tt[1])) if tt.size() > 1 else false,
		"gold_diff": (int(tt[2]) - int(tt[3])) if tt.size() > 3 else 0,
		"allies": [], "foes": [],
	}
	for v in _views.values():
		if int(v.get("type", -1)) != NET_HERO:
			continue
		if float(v.get("hp", 0.0)) <= 0.0:
			continue
		var team: int = int(v.get("team", -1))
		var is_ally: bool = team == int(_manifest.get("team", TEAM_PLAYER))
		var line := "[AI] %s (%s) -> %s" % [str(v.get("name", "")), str(v.get("role", "")), _lane_name(int(v.get("lane_assigned", -1)))]
		if is_ally:
			(out["allies"] as Array).append(line)
		else:
			(out["foes"] as Array).append(line)
	return out


func _lane_name(lane: int) -> String:
	match lane:
		0: return "发育路"
		1: return "MID"
		2: return "对抗路"
		3: return "打龙"
	return "未分配"


func _build_roster_panel() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 101
	add_child(cl)
	_rp = NetRosterPanelScript.new()
	_rp.self_net = _self_net
	cl.add_child(_rp)

# —— P3d 商店：own.gold/equip/rec 喂入；CanvasLayer 102 盖过 C/T 面板；O/B/Esc 在面板自身处理 ——
func _build_shop_panel() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 102
	add_child(cl)
	_sp = NetShopPanelScript.new()
	cl.add_child(_sp)

# —— P3d+ 主界面右上推荐带：own.rb 每帧喂入；Layer 65（高于 buff 行 60、低于小地图 80/模态层）——
func _build_rec_bar() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 65
	add_child(cl)
	_rb = NetRecommendBarScript.new()
	_rb.shop_requested.connect(func():
		if _sp:
			_sp.toggle())
	cl.add_child(_rb)

# —— P3e 击杀战报带：监听 host 广播（UI_Manager.show_kill_feed 全网转发）；顶部中央，不拦截鼠标 ——
func _build_kill_feed() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 101   # 播报需压在英雄头像/HUD(20)与触摸键(100)之上，仍在死亡覆盖(104)/结算(110)之下
	add_child(cl)
	_kf = NetKillFeedScript.new()
	cl.add_child(_kf)

# —— P3e 回城指示：own.recalling/recall_ratio 喂入；屏幕中下居中，不拦截鼠标 ——
func _build_recall() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 42
	add_child(cl)
	# 回城/传送中央方框已按需求移除：不再创建 NetRecall 指示器（_rk 保持 null，下面的 feed 自动跳过）

# —— P3e 死亡回放：host 死亡跃迁推送；模态，盖过战报/回城，Esc/点遮罩/×可关 ——
func _build_death_recap() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_RECAP   # 死亡回放：盖住 buff 图标(60)/飘字(103)，低于结算(110)
	add_child(cl)
	_dr = NetDeathRecapScript.new()
	cl.add_child(_dr)

# —— P3f 结算页：host game_over 广播；CanvasLayer 110 最顶，Esc/点遮罩关闭 ——
func _build_result_panel() -> void:
	var cl := CanvasLayer.new()
	cl.layer = UiKit.LAYER_RESULTS
	add_child(cl)
	_go = NetResultPanelScript.new()
	cl.add_child(_go)
	_go.defer = true   # 先播终局演出，播完再显示结算页

# ==================== 终局演出（与单机 BattleManager._play_end_sequence 同一节奏） ====================
# 水晶爆炸（共享 CrystalFinale）→ 5 秒 → EndBanner → 聚光灯舞台 → 个人表现 → 结算页
var _finale_started := false
var _finale_cam_locked := false   # 终局运镜：镜头先平滑推到水晶，期间屏蔽常规跟随

func _on_net_game_over(p: Dictionary) -> void:
	if _pm_started or _finale_started:
		return
	_finale_started = true
	var won: bool = int(p.get("winner", -1)) == Config.player_team
	var own_team: int = int(_manifest.get("team", TEAM_PLAYER))
	var loser_team: int = (1 - own_team) if own_team == 0 else (1 - own_team)
	var crys_pos := Vector3(-53, 0, 53) if loser_team == Config.Team.PLAYER else Vector3(53, 0, -53)
	for v in _views.values():
		if str(v.get("name", "")) == "crystal" and v.get("node") != null and is_instance_valid(v.get("node")):
			crys_pos = (v.get("node") as Node3D).global_position
			break
	# 1) 与单机同节奏：先用 1.1s 把镜头运到水晶（不是瞬切），再播爆炸
	_finale_cam_locked = true
	_first_person = false
	if _cam != null and is_instance_valid(_cam):
		var flip := PI if int(Config.player_team) == 1 else 0.0
		var cam_end: Vector3 = crys_pos + CAM_FOLLOW_OFF.rotated(Vector3.UP, flip)
		var rot := Vector3(-60.0, rad_to_deg(flip), 0.0)
		var cam_tw := create_tween()
		cam_tw.set_parallel(true)
		cam_tw.tween_property(_cam, "global_position", cam_end, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		cam_tw.tween_property(_cam, "rotation_degrees", rot, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 与单机 BattleManager._play_end_sequence 同节奏：运镜与爆炸同帧启动，镜头 1.1s 滑到水晶
	# 2) 终章爆炸：与单机/回放同一份实现
	var fx: Node = CrystalFinaleScript.new()
	fx.name = "CrystalFinale"
	add_child(fx)
	fx.set("on_shake", Callable(self, "_camera_shake"))
	fx.set("on_flash", Callable(self, "_screen_flash"))
	fx.call("play", crys_pos, won)
	# 3) 5 秒后终局横幅（与单机 tw.tween_interval(5.0) → EndBanner 同节奏），横幅结束进聚光灯舞台
	await get_tree().create_timer(5.0).timeout
	if not is_inside_tree():
		return
	var banner: Control = EndBannerScript.new()
	banner.name = "EndBanner"
	banner.set("won", won)
	var bl := CanvasLayer.new()
	bl.layer = 200
	add_child(bl)
	bl.add_child(banner)
	banner.finished.connect(func() -> void:
		if is_instance_valid(bl):
			bl.queue_free()
		_start_post_match(p))


func _rows_of(p: Dictionary) -> Array:
	var rows: Array = p.get("rows", [])
	return rows if rows is Array else []


func _my_result_row(p: Dictionary) -> Dictionary:
	var my_name := ""
	for v in _views.values():
		if int(v.type) == NET_HERO and int(v.get("team", -1)) == int(_manifest.get("team", 0)) and int(v.get("nid", -1)) == _self_net:
			my_name = str(v.get("name", ""))
			break
	for r in _rows_of(p):
		if my_name != "" and str((r as Dictionary).get("name", "")) == my_name:
			return r
	for r in _rows_of(p):
		if bool((r as Dictionary).get("mine", false)):
			return r
	return {}


## 终局演出：隐藏战场只留己方 5 人 → V 字聚光灯舞台 → 点击镜头推近 + 个人表现 → 再点进结算页
func _start_post_match(p: Dictionary) -> void:
	_pm_started = true
	_pm_payload = p
	var won: bool = int(p.get("winner", -1)) == Config.player_team
	get_tree().paused = true
	# 1) 隐藏所有 HUD/面板层（演出层稍后自建）
	_pm_hidden_layers.clear()
	for child in get_children():
		if child is CanvasLayer:
			_pm_hidden_layers.append(child)
			child.visible = false
	# 2) 战场退场：World/Entities 隐藏，己方英雄节点搬到聚光灯舞台
	var world := get_node_or_null("World")
	if world != null:
		world.visible = false
	var ents := get_node_or_null("Entities")
	if ents != null:
		ents.visible = false
	var own_team: int = int(_manifest.get("team", TEAM_PLAYER))
	_pm_stage_root = Node3D.new()
	_pm_stage_root.name = "PmStage"
	add_child(_pm_stage_root)
	# 舞台容器：把己方 5 人模型从 Entities 搬进来（Entities 已隐藏，模型要留在可见容器）
	_pm_stage_root = Node3D.new()
	_pm_stage_root.name = "PmStage"
	add_child(_pm_stage_root)
	var allies: Array = []
	for nid in _views:
		var v: Dictionary = _views[nid]
		if int(v.type) != NET_HERO or int(v.get("team", -1)) != own_team:
			continue
		var nd = v.get("node")
		if nd == null or not is_instance_valid(nd):
			continue
		allies.append(v)
	allies.sort_custom(func(a, b):
		var sa: int = 0 if int(a.get("nid", -1)) == _self_net else 1
		var sb: int = 0 if int(b.get("nid", -1)) == _self_net else 1
		return sa < sb)
	var entries: Array = []
	var rows := _rows_of(p)
	var units: Array = []
	for i in range(mini(allies.size(), 5)):
		var v: Dictionary = allies[i]
		var nd: Node3D = v.node
		if nd.get_parent() != null:
			nd.get_parent().remove_child(nd)
		_pm_stage_root.add_child(nd)
		units.append(nd)
		if i == 0:
			_pm_player_node = nd
		if v.get("ap") != null and v.ap is AnimationPlayer and str(v.get("idle_clip", "")) != "":
			(v.ap as AnimationPlayer).play(str(v.idle_clip))
		var hname := str(v.get("name", ""))
		var row := {}
		for r in rows:
			if str((r as Dictionary).get("name", "")) == hname:
				row = r
				break
		entries.append({
			"world": nd.global_position,
			"hero": hname,
			"nick": str(v.get("pname", "")),
			"lane": HeroPickData.role_lane(str(row.get("role", ""))),
			"mvp": bool(row.get("mvp", v.get("mvp", false))),
			"medal": _pm_medal(row),
			"node": nd,
		})
	if entries.is_empty():
		_pm_finish_and_show()
		return
	# MVP / 奖牌：统一 MatchResult 口径（三端一致）
	var _best_i := 0
	var _best_r := -1.0
	for i in range(entries.size()):
		var _rr := _pm_rating(_row_by_name(str(entries[i]["hero"])))
		entries[i]["rating"] = _rr
		entries[i]["medal"] = MatchResultScript.medal_by_rating(_rr)
		if _rr > _best_r:
			_best_r = _rr
			_best_i = i
	for i in range(entries.size()):
		entries[i]["mvp"] = (i == _best_i)
	# 舞台本体（站位/聚光灯/黑背景+主光/铭牌/镜头）全部交给共享 PostMatchStage
	_pm_stage_node = PostMatchStageScript.new()
	_pm_stage_node.name = "PostMatchStage"
	add_child(_pm_stage_node)
	_pm_stage_node.detail_provider = func() -> Dictionary: return _pm_detail_dict()
	_pm_stage_node.finished.connect(_pm_finish_and_show)
	_pm_stage_node.setup(self, _cam, units, entries, won, 0, {"own_team": own_team})
	_pm_view = _pm_stage_node.view


# 评分 / 奖牌 / 行查找（全部委托 MatchResult，三端同一口径）
func _pm_medal(row: Dictionary) -> int:
	return MatchResultScript.medal_by_rating(_pm_rating(row))


func _pm_rating(r: Dictionary) -> float:
	if r.is_empty():
		return 0.0
	var team := int(r.get("team", 0))
	var team_rows: Array = []
	for o in _rows_of(_pm_payload):
		if int((o as Dictionary).get("team", -1)) == team:
			team_rows.append(o)
	return MatchResultScript.rating(r, team_rows)


func _pm_medal_by_rating(rr: float) -> int:
	return MatchResultScript.medal_by_rating(rr)


func _row_by_name(nm: String) -> Dictionary:
	for o in _rows_of(_pm_payload):
		if str((o as Dictionary).get("name", "")) == nm:
			return o
	return {}

## 阶段 B 的个人详情（供共享舞台调用）
func _pm_detail_dict() -> Dictionary:
	var row := _my_result_row(_pm_payload)
	var hero_name := str(row.get("name", _manifest.get("hero_name", "")))
	var nick := str(row.get("nick", ""))
	var rank: Dictionary = _pm_payload.get("rank", {})
	var rank_lines: Array = []
	if not rank.is_empty() and not str(rank.get("new_label", "")) == "":
		rank_lines.append("段位 %s → %s" % [str(rank.get("old_label", "")), str(rank.get("new_label", ""))])
		rank_lines.append("本局星数 %+d★" % int(rank.get("star_change", 0)))
	else:
		rank_lines.append("本局不计排位星")
	var dur_f := float(_pm_payload.get("dur", 0.0))
	rank_lines.append("对局时长 %02d:%02d" % [int(dur_f) / 60, int(dur_f) % 60])
	return {
		"hero": hero_name,
		"nick": nick,
		"lane": HeroPickData.role_lane(str(row.get("role", ""))),
		"mvp": bool(row.get("mvp", false)),
		"rating": _pm_rating(row),
		"medal": _pm_medal(row),
		"rows": [
			["K / D / A", "%d / %d / %d" % [int(row.get("k", 0)), int(row.get("d", 0)), int(row.get("a", 0))]],
			["总经济", "%d" % int(row.get("tgold", row.get("gold", 0)))],
			["英雄伤害", "%d" % int(row.get("dmg", 0))],
			["承受伤害", "%d" % int(row.get("taken", 0))],
			["治疗量", "%d" % int(row.get("heal", 0))],
			["补刀", "%d" % int(row.get("lh", 0))],
			["推塔伤害", "%d" % int(row.get("turret", 0))],
			["控制时长", "%.1f s" % (float(row.get("cc", 0)) / 10.0)],
			["野区经济", "%d" % int(row.get("jungle", 0))],
		],
		"rank_lines": rank_lines,
	}

func _pm_finish_and_show() -> void:
	if _pm_view != null and is_instance_valid(_pm_view):
		_pm_view.queue_free()
	_pm_view = null
	if _pm_layer != null and is_instance_valid(_pm_layer):
		_pm_layer.queue_free()
	_pm_layer = null
	if _pm_stage_root != null and is_instance_valid(_pm_stage_root):
		# 英雄节点搬回 Entities（避免视图字典里的 node 悬空），再释放舞台/灯光
		var ents3 := get_node_or_null("Entities")
		for v in _views.values():
			var nd3 = v.get("node")
			if nd3 != null and is_instance_valid(nd3) and nd3.get_parent() == _pm_stage_root:
				if ents3 != null:
					_pm_stage_root.remove_child(nd3)
					ents3.add_child(nd3)
		_pm_stage_root.queue_free()
	for cl in _pm_hidden_layers:
		if is_instance_valid(cl):
			cl.visible = true
	var world2 := get_node_or_null("World")
	if world2 != null:
		world2.visible = true
	var ents2 := get_node_or_null("Entities")
	if ents2 != null:
		ents2.visible = true
	get_tree().paused = false
	if _go != null:
		_go.show_deferred()


func _reset_drive_state() -> void:
	_d_ax = 0.0
	_d_az = 0.0
	_d_jx = 0.0
	_d_jy = 0.0
	_d_mode = -99
	_d_last = 0.0
	_atk_sent = false
	_atk_last = 0.0
	_manual_net = -1
	_shen_last = 0.0
	# 预测态复位：退出/重连后由下一次快照重新起算，避免残留旧位置
	_pred_on = false
	_pred_err = 0.0


# —— P0-C：本机操控英雄移动预测 ——
# 每帧按当前输入轴积分位置（与主机 Hero 直驱同公式 spd*0.01*delta），快照只做校正，
# 使走位零延迟；伤害/技能/命中仍全由主机结算。
# spd/lock/cc 由主机快照下发（同源）：移速含前摇减速与暗影加速，走A锁定与硬控期间与主机同样静止。
func _tick_self_prediction(delta: float) -> void:
	if not _owned or _state != 1 or _self_net < 0:
		_pred_on = false
		return
	# 与直驱输入同门禁：本端没有正在发送的移动输入时不预测（否则会出现"本地动、主机不动"的幽灵位移）
	if _pad == null:
		_pred_on = false
		return
	var ax := Input.get_axis("ui_left", "ui_right")
	var az := Input.get_axis("ui_down", "ui_up")
	var jv := _pad.get_move_vector()
	if int(Config.player_team) == 1:
		# 红方相机翻转：本地移动预测与发送方向保持一致
		ax = -ax
		az = -az
		jv = -jv
	# 无输入且尚未起预测：不介入（走快照插值）；已在预测态则继续做快照校正，保证松手瞬间不弹回滞后位置
	if absf(ax) < 0.02 and absf(az) < 0.02 and jv.length() < 0.02 and not _pred_on:
		_pred_turn_cd = 0.0
		return
	var v = _views.get(_self_net)
	if v == null or v.node == null or not is_instance_valid(v.node):
		_pred_on = false
		return
	# 死亡 / 回城中不预测（快照 own 里仅有的可用状态字段就是 alive / recalling）
	if int(_own.get("alive", 1)) != 1 or int(_own.get("recalling", 0)) == 1:
		_pred_on = false
		return
	var node: Node3D = v.node
	if not _pred_on:
		_pred_pos = node.global_position      # 起算：贴合当前显示位置，避免首帧拉扯
		_pred_snap = _pred_pos
		_pred_on = true
	# 0) 转向模式：左右键转向复刻 host（每 0.05s × 15°，只在有输入时推进；摇杆模式不用）
	var mm := _pad.get_move_mode()
	if mm == TouchController.MOVE_MODE_TURN and jv.length() <= 0.1 and absf(ax) > 0.1:
		_pred_turn_cd -= delta
		if _pred_turn_cd <= 0.0:
			node.rotation.y += ax * deg_to_rad(-15.0)
			_pred_turn_cd = 0.05
	else:
		_pred_turn_cd = 0.0
	# 1) 输入积分（方向映射与主机 Hero 直驱一致；移速/阻断同源下发）
	var dir := _pred_dir(node)
	if dir.length() > 0.01 and int(_own.get("cc", 0)) == 0 and float(_own.get("lock", 0.0)) <= 0.0:
		var spd := float(_own.get("spd", _pred_speed))
		_pred_pos += dir.normalized() * spd * 0.01 * delta
		var half := Config.MAP_SIZE / 2.0
		_pred_pos.x = clampf(_pred_pos.x, -half, half)
		_pred_pos.z = clampf(_pred_pos.z, -half, half)
		# 摇杆 / 前后左右模式：主机是即时朝向移动方向（Hero: rotation.y = atan2(dir.x, dir.z)）
		if jv.length() > 0.1 or mm != TouchController.MOVE_MODE_TURN:
			node.rotation.y = atan2(dir.x, dir.z)
	# 2) 快照校正：只修「预测不该有」的偏差（撞墙/被推/减速/位移技能），不把正常网络滞后当成错
	#    - 误差 >3m：位移技能/闪现/回城/复活，直接吸附
	#    - 误差 0.5~3m：6/s 缓慢回贴（撞墙被拦、被控位移）
	#    - 误差 <0.5m：即本端领先主机的合理前瞻量（≈移速×单程延迟），保持不动，否则会退回滞后位置
	var drift := _pred_snap - _pred_pos
	drift.y = 0.0
	_pred_err = drift.length()
	if _pred_err > 3.5:
		_pred_pos = Vector3(_pred_snap.x, node.global_position.y, _pred_snap.z)
	elif _pred_err > 0.8:
		_pred_pos += drift * clampf(delta * 4.0, 0.0, 0.2)
	node.global_position = Vector3(_pred_pos.x, node.global_position.y, _pred_pos.z)


# 预测方向：摇杆优先（同主机），其次键盘；转向模式沿 node 朝向走前后
func _pred_dir(node: Node3D) -> Vector3:
	var jv := _pad.get_move_vector() if _pad != null else Vector2.ZERO
	var ax := Input.get_axis("ui_left", "ui_right")
	var az := Input.get_axis("ui_down", "ui_up")
	var mm := _pad.get_move_mode() if _pad != null else TouchController.MOVE_MODE_DIR
	# 转向模式：左右转向、前后沿人物朝向（同 host）
	if mm == TouchController.MOVE_MODE_TURN and jv.length() <= 0.1:
		if int(Config.player_team) == 1:
			az = -az
		return Vector3(sin(node.rotation.y), 0.0, cos(node.rotation.y)) * az
	return _move_dir_from_input(ax, az, jv, mm)


## 屏幕/摇杆输入 → 世界方向。第三人称按阵营 180° 翻转；第一人称按当前英雄朝向旋转，
## 解决第一人称下“点左却往屏幕上/下走”的方向错乱。
func _move_dir_from_input(ax: float, az: float, jv: Vector2, mm: int) -> Vector3:
	var sx := ax
	var sy := az
	if jv.length() > 0.1:
		sx = jv.x
		sy = jv.y
	if absf(sx) < 0.01 and absf(sy) < 0.01:
		return Vector3.ZERO
	var theta := 0.0
	if _first_person:
		theta = float(_own.get("ry", 0.0)) + PI
	elif int(Config.player_team) == 1:
		theta = PI
	# 相机右向量 = (cosθ,0,-sinθ)，屏幕上方 = 相机 -Z 方向
	return Vector3(cos(theta) * sx - sin(theta) * sy, 0.0,
		-sin(theta) * sx - cos(theta) * sy)


# 用相邻快照位移自校准移速（客户端没有 actual_move_speed；过滤静止与闪现/位移的异常值）
func _calibrate_pred_speed(pos: Vector3) -> void:
	var dt := _last_snap_time - _pred_sp_t
	if dt > 0.005 and dt < 0.5:
		var est := (pos - _pred_sp_pos).length() / (0.01 * dt)
		if est > 150.0 and est < 700.0:
			_pred_speed = lerpf(_pred_speed, est, 0.3)
	_pred_sp_pos = pos
	_pred_sp_t = _last_snap_time


# 每帧（接管且对局中）把触摸层/键盘输入翻译为直驱指令。语义对齐主机 Hero._physics_process：
# 摇杆向量 = 世界方向；键盘 WASD 方向受 MoveModeToggle(移动模式) 约束，故随包发送模式值。
func _poll_touch_input() -> void:
	if _pad == null:
		return
	# 同 host UiManager.blocks_gameplay_input()：商店/属性面板打开时不响应移动与普攻（否则线上可在商店里跑）
	var ui_block: bool = (_sp != null and _sp.visible) or (_rp != null and _rp.visible)
	if ui_block:
		if absf(_d_ax) > 0.02 or absf(_d_az) > 0.02 or absf(_d_jx) > 0.02 \
				or absf(_d_jy) > 0.02 or _d_mode != -99:
			NetSession.send_command([NetSession.C_DRIVE, 0.0, 0.0, 0.0, 0.0, _pad.get_move_mode()])
			_d_ax = 0.0
			_d_az = 0.0
			_d_jx = 0.0
			_d_jy = 0.0
			_d_mode = _pad.get_move_mode()
		if _atk_sent:
			NetSession.send_command([NetSession.C_ATTACK_AUTO, 0])
			_atk_sent = false
		return
	var now := Time.get_ticks_msec() * 0.001
	# 移动：变化即发；持续非零每 0.03s 心跳（≥20Hz，帧率 60 时每 2 帧一次），防主机 0.5s 直驱超时误判松手
	var ax := Input.get_axis("ui_left", "ui_right")
	var az := Input.get_axis("ui_down", "ui_up")
	var jv := _pad.get_move_vector()
	var mm := _pad.get_move_mode()
	# 转向模式保留原始转向/前后语义；方向模式统一先换算成世界方向再发给 host。
	if mm == TouchController.MOVE_MODE_TURN and jv.length() <= 0.1:
		if int(Config.player_team) == 1:
			ax = -ax
			az = -az
	else:
		var world_dir := _move_dir_from_input(ax, az, jv, mm)
		ax = world_dir.x
		az = -world_dir.z
		jv = Vector2(world_dir.x, -world_dir.z)
	var changed := absf(ax - _d_ax) > 0.02 or absf(az - _d_az) > 0.02 \
		or absf(jv.x - _d_jx) > 0.02 or absf(jv.y - _d_jy) > 0.02 or mm != _d_mode
	var driving := absf(ax) > 0.02 or absf(az) > 0.02 or jv.length() > 0.02
	if changed:
		NetSession.send_command([NetSession.C_DRIVE, ax, az, jv.x, jv.y, mm])
		_d_ax = ax
		_d_az = az
		_d_jx = jv.x
		_d_jy = jv.y
		_d_mode = mm
		_d_last = now
	elif driving and now - _d_last > 0.03:
		NetSession.send_command([NetSession.C_DRIVE, ax, az, jv.x, jv.y, mm])
		_d_last = now
	# 普攻按住/松开：边沿发送；持续按住每 0.4s 心跳，防主机 0.8s 普攻超时误判松手
	var held := _pad.is_attack_held()
	if held and not _atk_prev_held:
		# 空放普攻：本端没有可打目标时通知 host 发一次空放（否则点普攻完全没反馈）
		var has_target := false
		var sp0 := _self_pos()
		var reach0 := float(_own.get("reach", 0.0))
		if reach0 <= 0.5:
			reach0 = 6.0
		for nid0 in _views:
			var v0: Dictionary = _views[nid0]
			if int(v0.get("team", -1)) == int(Config.player_team):
				continue
			if float(v0.get("hp", 0.0)) <= 0.0:
				continue
			if sp0.distance_to(_view_pos(v0)) <= reach0 + 0.5:
				has_target = true
				break
		if not has_target:
			NetSession.send_command([NetSession.C_ATTACK, -1])
			_atk_ring_flash = 0.45   # 与 host flash_attack_range_ring 一致：空放也亮一圈
	_atk_prev_held = held
	if held != _atk_sent:
		NetSession.send_command([NetSession.C_ATTACK_AUTO, 1 if held else 0])
		_atk_sent = held
		_atk_last = now
	elif held and now - _atk_last > 0.4:
		NetSession.send_command([NetSession.C_ATTACK_AUTO, 1])
		_atk_last = now
	# 普攻轮盘松手：非取消且拖出阈值 → 客户端按拖动方向选敌并锁定（C_ATTACK）
	var rel: Dictionary = _pad.consume_attack_release()
	if not rel.is_empty() and not bool(rel.get("cancel", false)):
		var drag: Vector2 = rel.get("drag", Vector2.ZERO)
		if drag.length() > ATTACK_WHEEL_DRAG_THRESHOLD:
			_attack_pick(drag)
	# 推塔/小兵：同键再按取消回自动（主机 Hero._handle_attack_priority_input 同规则）
	var pp := _pad.consume_priority_press()
	if pp >= 0:
		var final_p := pp if _pad.attack_priority != pp else NetTouchPadScript.PRIO_AUTO
		_pad.set_attack_priority(final_p)
		NetSession.send_command([NetSession.C_PRIORITY, final_p])
		_manual_net = -1   # 与主机 C_PRIORITY 清 manual_target 一致

# 拖拽选敌：与主机 Hero._pick_attack_target 一致 —— 以屏幕中心+拖动方向*500 取瞄准地面点，
# 从自身普攻判定距离内找离瞄准点最近的敌方单位锁定。
func _attack_pick(drag: Vector2) -> void:
	if _cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var aim_scr := vp * 0.5 + drag.normalized() * 500.0
	var aim := _ground_hit(aim_scr)
	var sv = _views.get(_self_net)
	if sv == null:
		return
	# 射程/距离判定用权威快照位（_self_pos/_entity_pos → target），不用滞后 ≤1 周期的插值渲染位 node，与主机判定同基准
	var own_pos := _self_pos()
	var gate := _reach + 1.0
	var best := -1
	var best_d := 1e9
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.team == Config.player_team or v.hp <= 0.0:
			continue
		if v.type != NET_HERO and v.type != NET_MINION and v.type != NET_TURRET and v.type != NET_JUNGLE:
			continue
		var epos := _entity_pos(nid)
		if epos.distance_to(own_pos) > gate:
			continue
		var d := epos.distance_to(aim)
		if d < best_d:
			best_d = d
			best = nid
	if best >= 0:
		_manual_net = best   # 本端 smart 施法目标锁定（复刻 host manual_target）
		NetSession.send_command([NetSession.C_ATTACK, best])

# —— P1b：技能钮群状态推送 / 施放翻译 → C_CAST / C_UPGRADE ——

# 每帧把 own 块 + manifest 转成触控技能钮的状态（cd 剩余、金环等级、蓝量、升级箭头可见性）。
func _update_skill_pad() -> void:
	if _pad == null:
		return
	var lvls: Array = _own.get("levels", [])
	var cds: Array = _own.get("cd", [])
	var level := int(_own.get("level", 1))
	var mana := float(_own.get("mana", 0.0))
	var sp := int(_own.get("sp", 0))
	for i in range(mini(_skills.size(), 3)):
		var sk: Dictionary = _skills[i]
		var slv := int(lvls[i]) if i < lvls.size() else 0
		var total := maxf(float(sk.get("cd", 0.0)), 0.001)
		var cdb := float(sk.get("cdb", 0.0))
		if slv >= 1:
			total = maxf(total - cdb * float(slv - 1), 0.001)
		var cd_cur := float(cds[i]) if i < cds.size() else 0.0
		var cost := float(sk.get("mana", 0.0))
		var pw := float(sk.get("pw", 0.0))
		if slv >= 1:
			cost = maxf(cost - pw * float(slv - 1), 0.0)
		var st := {
			"name": str(sk.get("name", "")),
			"sid": str(sk.get("sid", "")),
			"hero": str(_manifest.get("hero_name", "")),
			"level": slv,
			"max_level": 6 if i < 2 else 3,
			"cd": cd_cur, "cdmax": total,
			"mana_ok": mana >= cost,
		}
		# M4-U：own.sx 图标读数（伤害预览/效果小字/重施窗口/充能/前置阻塞，host 按 TouchController 同款烘焙）
		var ex := _skill_icon_extra(i)
		for k in ex:
			st[k] = ex[k]
		_pad.set_skill_state(i, st)
		_pad.set_upgrade_visible(i, _can_upgrade(i, sp, level, lvls))
	# 第4技能（兰陵王·隐身）：manifest 里存在才亮出按钮
	if _skills.size() > 3 and _skills[3] != null:
		var sk4: Dictionary = _skills[3]
		var slv4 := int(lvls[3]) if lvls.size() > 3 else 1
		var cd4 := float(cds[3]) if cds.size() > 3 else 0.0
		var total4 := maxf(float(sk4.get("cd", 0.0)), 0.001)
		_pad.set_extra_skill_state({
			"name": str(sk4.get("name", "")),
			"sid": str(sk4.get("sid", "")),   # 第4技能图标（同 host：英雄元素色 + 技能纹样）
			"hero": str(_manifest.get("hero_name", "")),
			"level": maxi(slv4, 1), "max_level": 1,
			"cd": cd4, "cdmax": total4,
			"mana_ok": mana >= float(sk4.get("mana", 0.0)),
		})
		_pad.set_extra_skill_visible(true)
	else:
		_pad.set_extra_skill_visible(false)

# own.sx 槽位 → set_skill_state 的图标扩展字段（sx 定长15；长度不符=无图标数据，按钮回默认态）
func _skill_icon_extra(i: int) -> Dictionary:
	if _own == null:
		return {}
	var sx: Array = _own.get("sx", [])
	if not (sx is Array) or i >= sx.size():
		return {}
	var f: Array = sx[i]
	if not (f is Array) or f.size() < 15:
		return {}
	return {
		"iw": int(f[0]) == 1,
		"wl": float(f[1]), "wt": float(f[2]), "sg": int(f[3]),
		"icon_dmg": int(f[4]), "icon_dmg_magic": int(f[5]) == 1,
		"icon_dmg2": int(f[6]), "icon_dmg2_magic": int(f[7]) == 1,
		"icon_count": int(f[8]),
		"icon_fx": f[9],
		"icon_aa": int(f[10]) == 1,
		"charge_max": int(f[11]), "charge_now": int(f[12]),
		"blocked": int(f[13]) == 1, "block_cue": str(f[14]),
	}

# 升级箭头可见判定：与主机 Hero.can_upgrade_skill 同源（大招要过等级门槛 [0,4,8,12]）。
func _can_upgrade(slot: int, sp: int, level: int, lvls: Array) -> bool:
	if sp <= 0 or slot < 0 or slot >= _skills.size():
		return false
	if slot < 2:
		var cur := int(lvls[slot]) if slot < lvls.size() else 0
		return cur < 6
	if slot == 2:
		var cur := int(lvls[slot]) if slot < lvls.size() else 0
		if cur >= 3:
			return false
		var reqs := [0, 4, 8, 12]
		return cur + 1 < reqs.size() and level >= int(reqs[cur + 1])
	return false

# 每帧消费触控技能按钮事件：升级点按、技能松手（含第4按钮）。
func _poll_skill_input() -> void:
	if _pad == null:
		return
	var up := _pad.consume_upgrade_press()
	if up >= 0 and up < 3:
		NetSession.send_command([NetSession.C_UPGRADE, up])
	var ry := float(_own.get("ry", 0.0))
	var hero_name := str(_manifest.get("hero_name", ""))
	# 沈梦溪1技能：主机按下是连发（release 直接 continue）；网络端用按住心跳每 0.75s 一发近似
	if hero_name == "沈梦溪" and _skills.size() > 0 and _pad.is_skill_held(0):
		var cds: Array = _own.get("cd", [])
		if cds.size() <= 0 or float(cds[0]) <= 0.0:
			var now := Time.get_ticks_msec() * 0.001
			if now - _shen_last > 0.75:
				_shen_last = now
				_handle_skill_release(0, _skills[0], _pad.get_skill_drag(0), ry)
	# 英雄 1/2/3 技能：松手施放（王者式；拖回按钮或拖出圈=取消）
	for i in range(3):
		if hero_name == "沈梦溪" and i == 0:
			continue   # 上面心跳连发已覆盖，避免松手多补一发
		var rel: Dictionary = _pad.consume_skill_release(i)
		if rel.is_empty() or bool(rel.get("cancel", false)):
			continue
		if i >= _skills.size():
			continue
		_handle_skill_release(i, _skills[i], rel.get("drag", Vector2.ZERO), ry)
	# 第4技能（兰陵王·隐身）：点按即施放、无方向
	var rel4: Dictionary = _pad.consume_skill_release(3)
	if not rel4.is_empty() and not bool(rel4.get("cancel", false)) and _skills.size() > 3 and _skills[3] != null:
		var sp := _self_pos()
		NetSession.send_command([NetSession.C_CAST, 3, -1, sp.x, sp.z])
		SfxManager.client_cast_sfx(3, _skills[3])

# —— P1c：召唤师 / 恢复 / 回城 / 主动装备按钮的状态推送与事件翻译 ——

# 每帧用 own 块喂召唤师/恢复/主动装备按钮显示状态（own 字段见 NetSession._build_snapshot）
func _update_aux_pad() -> void:
	if _pad == null:
		return
	var sn := str(_own.get("summoner_name", ""))
	if sn == "":
		sn = "召唤"
	_pad.set_summoner_state({
		"name": sn,
		"cd": float(_own.get("summoner_cd", 0.0)),
		"cdmax": float(_own.get("summoner_cdmax", 0.0)),
		"level": int(_own.get("level", 1)),
	})
	# 恢复：cd 总量=60（主机恢复固定 60s 冷却，槽位=第4号技能槽），剩余=own.cd[4]
	var cds: Array = _own.get("cd", [])
	var rcd := float(cds[4]) if cds.size() > 4 else 0.0
	_pad.set_recover_state({"cd": rcd, "cdmax": 60.0})
	# 主动装备按钮（≤2；own.act 由 NetSession._active_equips 打包 [[id,name,max_cd,cd_remaining],…]）
	var act: Array = _own.get("act", [])
	for i in range(2):
		_pad.set_active_visible(i, i < act.size())

# 每帧消费召唤师/恢复/回城/主动装点按事件 → 指令
func _poll_aux_input() -> void:
	if _pad == null:
		return
	# 召唤师：松手非取消 → C_SUMMONER（拖拽方向=世界方向，主机 _use_summoner 同语义；cd 由主机复核）
	var sum_rel: Dictionary = _pad.consume_summoner_release()
	if not sum_rel.is_empty() and not bool(sum_rel.get("cancel", false)):
		if float(_own.get("summoner_cd", 0.0)) <= 0.05:
			if str(_own.get("summoner_name", "")) != "":
				var aim2: Vector2 = sum_rel.get("drag", Vector2.ZERO)
				if aim2.length() <= 20.0:
					# 点按：退化为自身朝向（世界方向）
					var ry := float(_own.get("ry", 0.0))
					aim2 = Vector2(sin(ry), cos(ry)) * 100.0
				else:
					# 拖拽：按本机镜头把屏幕方向反投影成世界方向，主机按世界方向施放
					var sc2 := get_viewport().get_visible_rect().size * 0.5 + aim2.normalized() * 500.0
					var wp2: Vector3 = _ground_hit(sc2)
					var dv2: Vector3 = wp2 - _self_pos()
					dv2.y = 0.0
					if dv2.length() > 0.2:
						aim2 = Vector2(dv2.x, dv2.z).normalized() * 100.0
				NetSession.send_command([NetSession.C_SUMMONER, -1, aim2.x, aim2.y])
				_summoner_local_feedback()
	# 恢复：点按 → C_RECOVER（cd 预检；主机同款 index4=恢复槽）
	if _pad.consume_recover_press():
		var cds: Array = _own.get("cd", [])
		if cds.size() > 4 and float(cds[4]) <= 0.05:
			NetSession.send_command([NetSession.C_RECOVER])
	# 回城：点按 → C_RECALL（回城中再按=主机 no-op，打断靠移动/普攻/技能；本端不回发）
	if _pad.consume_recall_press():
		if int(_own.get("recalling", 0)) == 0:
			NetSession.send_command([NetSession.C_RECALL])
	# 主动装：点按 → C_ACTIVE（cd 未到由主机内部 no-op，与触控同一入口）
	var ap := _pad.consume_active_press()
	if ap >= 0:
		var act: Array = _own.get("act", [])
		if ap < act.size():
			NetSession.send_command([NetSession.C_ACTIVE, ap])

# —— P1c：键盘热键（双轨：触摸钮之外保留主机桌面热键手感）——

# 李元芳1技能(槽0)才能锁防御塔（同主机 _skill_target_allowed 口径）
func _lyf_slot_ok(slot: int) -> bool:
	return slot == 0 and str(_own.get("name", "")) == "李元芳"

func _kbd_skill_type(slot: int) -> int:
	if slot < 0 or slot >= _skills.size():
		return -1
	return int(_skills[slot].get("type", 0))

# 按下：type0 进入「按住瞄准」态（_process 每帧以鼠标刷新准星与候选），其余即时施放
func _kbd_press_slot(slot: int) -> void:
	if slot < 0 or slot >= _skills.size():
		return
	var cds: Array = _own.get("cd", [])
	if slot < cds.size() and float(cds[slot]) > 0.05:
		return
	var lvls: Array = _own.get("levels", [])
	var slv := int(lvls[slot]) if slot < lvls.size() else 0
	if slv <= 0:
		return
	if _kbd_skill_type(slot) == 0:
		_pending_skill = slot
		_kbd_hold_ms = Time.get_ticks_msec()
	else:
		_kbd_cast(slot)

# 松开：type0 结束瞄准 → 点按(≤KBD_TAP_MS)智能施放；长按取鼠标方向最近候选吸附（含李元芳Q锁塔）
func _kbd_release_slot(slot: int) -> void:
	if slot < 0 or slot >= _skills.size() or _kbd_skill_type(slot) != 0:
		return
	if _pending_skill != slot:
		return
	_pending_skill = -1
	var cds: Array = _own.get("cd", [])
	if slot < cds.size() and float(cds[slot]) > 0.05:
		return
	var lvls: Array = _own.get("levels", [])
	var slv := int(lvls[slot]) if slot < lvls.size() else 0
	if slv <= 0:
		return
	var held_ms := Time.get_ticks_msec() - _kbd_hold_ms
	var allow := _lyf_slot_ok(slot)
	var aim := _ground_hit(_mouse_screen)
	var range := float(_skills[slot].get("range", 0.0))
	if range <= 0.0:
		range = 3.0
	var target := -1
	if held_ms <= KBD_TAP_MS:
		var t2 := _type0_smart_target(range, allow)
		if t2 >= 0:
			target = t2
			aim = _entity_pos(t2)
	else:
		var cand := _pick_skill_target_net(aim, range, allow, KBD_HOVER_RADIUS)
		if cand >= 0:
			target = cand
			aim = _entity_pos(cand)
	_send_cast(slot, target, aim)

# 键盘 1/2/3：面向鼠标光标的地面落点施放（非 type0 即时；type0 走按住瞄准）
func _kbd_cast(slot: int) -> void:
	if slot < 0 or slot >= _skills.size():
		return
	var cds: Array = _own.get("cd", [])
	if slot < cds.size() and float(cds[slot]) > 0.05:
		return
	var lvls: Array = _own.get("levels", [])
	var slv := int(lvls[slot]) if slot < lvls.size() else 0
	if slv <= 0:
		return
	var aim := _ground_hit(_mouse_screen)
	_send_cast(slot, -1, aim)

func _kbd_recover() -> void:
	var cds: Array = _own.get("cd", [])
	if cds.size() <= 4 or float(cds[4]) > 0.05:
		return
	NetSession.send_command([NetSession.C_RECOVER])

# 键盘 6（召唤师）：朝向鼠标光标地面点的方向（闪现位移等）
func _kbd_summoner() -> void:
	if float(_own.get("summoner_cd", 0.0)) > 0.05:
		return
	if str(_own.get("summoner_name", "")) == "":
		return
	var from := _self_pos()
	var to := _ground_hit(_mouse_screen)
	var dir := Vector2(to.x - from.x, to.z - from.z)
	if dir.length() < 1.0:
		var ry := float(_own.get("ry", 0.0))
		dir = Vector2(sin(ry), cos(ry)) * 100.0
	else:
		dir = dir.normalized() * 100.0   # 主机以长度>20 判定“有方向”
	NetSession.send_command([NetSession.C_SUMMONER, -1, dir.x, dir.y])
	_summoner_local_feedback()

# 召唤师技能本地镜头反馈（同 host Hero._use_summoner：闪现 0.04/0.16，晕眩 0.08/0.25）
func _summoner_local_feedback() -> void:
	match str(_own.get("summoner_name", "")):
		"闪现":
			_camera_shake(0.04, 0.16)
		"晕眩":
			_camera_shake(0.08, 0.25)

func _send_cast(slot: int, target: int, aim: Vector3) -> void:
	NetSession.send_command([NetSession.C_CAST, slot, target, aim.x, aim.z])
	# 接管客户端本地施法短音（host 的 Hero 回调不在本地跑，仅此处补；按 manifest type 分档）
	var sk = _skills[slot] if slot >= 0 and slot < _skills.size() else null
	SfxManager.client_cast_sfx(slot, sk)
	# 大招本地即时反馈（震屏/FOV 推镜/顿帧/闪屏）：不等主机回包，手感与单机一致
	if slot == 2:
		_play_big_cast_feedback()
	elif sk != null and int(sk.get("type", 0)) == 4:
		_camera_shake(0.07, 0.14)   # 位移技能本地震屏（同 host VfxFactory.dash_fx 的本地反馈）

# 松手施放翻译。type0（指向）拖拽→吸附、点按→智能施法；其余类型只发瞄准点，
# host C_CAST 用 release 语义在 _start_casting/_finish_casting 复核施放。
func _handle_skill_release(slot: int, sk: Dictionary, drag: Vector2, ry: float) -> void:
	var cds: Array = _own.get("cd", [])
	if slot < cds.size() and float(cds[slot]) > 0.05:
		return   # 本地 cd 预检，避免无效指令刷屏（host 仍会复核）
	var lvls: Array = _own.get("levels", [])
	var slv := int(lvls[slot]) if slot < lvls.size() else 0
	if slv <= 0:
		return   # 未学（本地灰钮状态下的兜底）
	var cost := float(sk.get("mana", 0.0))
	var pw := float(sk.get("pw", 0.0))
	if slv >= 1:
		cost = maxf(cost - pw * float(slv - 1), 0.0)
	if float(_own.get("mana", 0.0)) < cost:
		return   # 蓝量预检
	var range := float(sk.get("range", 0.0))
	if range <= 0.0:
		range = 3.0
	var typ := int(sk.get("type", 0))
	var aim := _cast_aim(slot, sk, drag, ry)
	var target := -1
	var allow := _lyf_slot_ok(slot)
	if typ == 0:
		if drag.length() > 12.0:
			var cand := _pick_skill_target_net(aim, range, allow)
			if cand >= 0:
				target = cand
				aim = _entity_pos(cand)
		else:
			var cand2 := _type0_smart_target(range, allow)
			if cand2 >= 0:
				target = cand2
				aim = _entity_pos(cand2)
	_send_cast(slot, target, aim)

# 复刻 Hero._compute_skill_aim（拖拽≥12 → 屏幕中心+方向*500 打地面点；
# dist=lerp(2,range,drag/400)，type1 至少 rad*0.6）。点按：先锁目标（存活且不超射程），
# 否则朝自身朝向(own.ry)打 5 单位（超射程才 clamp）——与主机点按无目标走朝向*5 一致。
func _cast_aim(slot: int, sk: Dictionary, drag: Vector2, ry: float) -> Vector3:
	var self_pos := _self_pos()
	var typ := int(sk.get("type", 0))
	var range := float(sk.get("range", 0.0))
	if range <= 0.0:
		range = 3.0
	if drag.length() > 12.0:
		var vp := get_viewport().get_visible_rect().size
		var aim_scr := vp * 0.5 + drag.normalized() * 500.0
		var ap := _ground_hit(aim_scr)
		var dir := ap - self_pos
		dir.y = 0.0
		if dir.length() > 0.01:
			var frac := clampf(drag.length() / 400.0, 0.0, 1.0)
			var dist := lerpf(2.0, range, frac)
			if typ == 1:
				dist = maxf(dist, float(sk.get("rad", 0.0)) * 0.6)
			return self_pos + dir.normalized() * dist
		return ap
	var m := _manual_alive()
	if m >= 0:
		var mp := _entity_pos(m)
		var dd := Vector2(mp.x - self_pos.x, mp.z - self_pos.z).length()
		if dd <= range:
			return mp
		return self_pos + (mp - self_pos).normalized() * range
	var fdir := Vector3(sin(ry), 0.0, cos(ry))
	return self_pos + fdir * minf(5.0, range)   # 主机 facing 落点：global_position + 朝向*5，超射程 clamp

# type0 点按智能施法：复刻主机接管 AI 英雄 _get_attack_target(is_ai=true) 的优先级
# （本端 C_ATTACK 锁定 manual → 攻击模式同类目标 → 按住普攻时英雄低血/其它低血）。
func _type0_smart_target(range: float, allow_turret: bool = false) -> int:
	if _manual_alive() >= 0 and _self_pos().distance_to(_entity_pos(_manual_net)) <= range:
		# manual 若是防御塔：仅李元芳1技能允许作为目标型技能落点（同主机 _skill_target_allowed）
		if allow_turret or _views.get(_manual_net, {}).get("type", -1) != NET_TURRET:
			return _manual_net
	if _pad.attack_priority != NetTouchPadScript.PRIO_AUTO:
		var m := _pick_prio_view(_pad.attack_priority, range)
		if m >= 0:
			return m
	if _atk_sent:
		return _pick_lowest_enemy(range, allow_turret)
	return -1

func _pick_prio_view(mode: int, range: float) -> int:
	var self_pos := _self_pos()
	var best := -1
	var best_hp := 1e18
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.team == Config.player_team or v.hp <= 0.0 or v.node == null:
			continue
		var ok_type := false
		if mode == NetTouchPadScript.PRIO_TOWER and v.type == NET_TURRET:
			ok_type = true
		elif mode == NetTouchPadScript.PRIO_MINION and (v.type == NET_MINION or v.type == NET_JUNGLE):
			ok_type = true
		if not ok_type:
			continue
		var p := _entity_pos(nid)   # 距离判定用权威快照位（同 _self_pos），非滞后插值渲染位
		if p.distance_to(self_pos) > range:
			continue
		if v.hp < best_hp:
			best_hp = v.hp
			best = nid
	return best

func _pick_lowest_enemy(range: float, allow_turret: bool = true) -> int:
	var self_pos := _self_pos()
	var best_hero := -1
	var best_hp := 1e18
	var best_other := -1
	var best_ohp := 1e18
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.team == TEAM_PLAYER or v.hp <= 0.0 or v.node == null:
			continue
		if v.type != NET_HERO and v.type != NET_MINION and v.type != NET_TURRET and v.type != NET_JUNGLE:
			continue
		if v.type == NET_TURRET and not allow_turret:
			continue
		var p := _entity_pos(nid)   # 距离判定用权威快照位（同 _self_pos），非滞后插值渲染位
		if p.distance_to(self_pos) > range:
			continue
		if v.type == NET_HERO:
			if v.hp < best_hp:
				best_hp = v.hp
				best_hero = nid
		elif v.hp < best_ohp:
			best_ohp = v.hp
			best_other = nid
	if best_hero >= 0:
		return best_hero
	return best_other

# type0 拖拽吸附：从自身射程内找离瞄准点最近的敌方单位（类 host _pick_skill_target）。
# allow_turret：仅李元芳1技能可锁防御塔（同主机 _skill_target_allowed）；hover_radius>0 时
# 要求候选落在瞄准点该半径内（桌面按住瞄准的对齐吸附），否则维持全射程最近兜底。
func _pick_skill_target_net(aim: Vector3, range: float, allow_turret: bool = false, hover_radius: float = 0.0) -> int:
	var self_pos := _self_pos()
	var best := -1
	var best_d := 1e18
	for nid in _views:
		var v: Dictionary = _views[nid]
		if v.team == TEAM_PLAYER or v.hp <= 0.0 or v.node == null:
			continue
		if v.type != NET_HERO and v.type != NET_MINION and v.type != NET_TURRET and v.type != NET_JUNGLE:
			continue
		if v.type == NET_TURRET and not allow_turret:
			continue
		var p := _entity_pos(nid)   # 距离判定用权威快照位（同 _self_pos），非滞后插值渲染位
		if p.distance_to(self_pos) > range:
			continue
		var d := p.distance_to(aim)
		if hover_radius > 0.0 and d > hover_radius:
			continue
		if d < best_d:
			best_d = d
			best = nid
	return best

# —— 拾取 / 位置辅助 ——
# 交互判定一律用"最新快照权威位 target"（同一帧坐标，自/敌相对准确），不用插值渲染位 node——
# 渲染位滞后最新快照 ≤1 周期且各实体相位不同，直接参与射程/距离判定会互相错位。
## 按住普攻键即显攻击范围圈（与主机 Hero._aa_ring_show_timer 同视觉；客户端无 Hero 节点故本地自绘）
func _update_atk_ring() -> void:
	var held: bool = ((_pad != null and _pad.is_attack_held()) or _atk_ring_flash > 0.0) \
			and _owned and _state == 1 and int(_own.get("alive", 1)) != 0
	if not held:
		if _atk_ring != null and is_instance_valid(_atk_ring):
			_atk_ring.visible = false
		return
	if _atk_ring == null or not is_instance_valid(_atk_ring):
		_atk_ring = MeshFactory.create_ground_ring(1.0, Color(1, 1, 1, 0.32), 96.0)
		add_child(_atk_ring)
	var reach := float(_manifest.get("reach", 3.25))
	var pos := _self_pos()
	_atk_ring.visible = true
	_atk_ring.global_position = Vector3(pos.x, 0.02, pos.z)
	_atk_ring.scale = Vector3(reach, 1.0, reach)


## 史诗野怪活动圈：仅当本端玩家正在攻击这只野怪时显示（同主机 JungleMonster._update_activity_ring）
## 圈固定回巢穴圆心；怪在圈内=白色，走出圈外=红色
# 敌方塔范围环：本端玩家进到 11m 内才显示（同 host Turret._update_range_preview）
func _update_tower_rings() -> void:
	var sp := _self_pos()
	var alive := _owned and _state == 1 and int(_own.get("alive", 1)) != 0
	for v in _views.values():
		var r = v.get("ring")
		if r == null or not is_instance_valid(r):
			continue
		var nd = v.get("node")
		if nd == null or not is_instance_valid(nd):
			(r as Node3D).visible = false
			continue
		var show: bool = alive and int(v.get("team", Config.player_team)) != Config.player_team \
			and float(v.get("hp", 0.0)) > 0.0 \
			and nd.global_position.distance_to(sp) <= 11.0
		r.visible = show


func _update_epic_rings() -> void:
	var has_epic := false
	for v in _views.values():
		if v.get("epic_ring") != null:
			has_epic = true
			break
	if not has_epic:
		return
	var held: bool = _pad != null and _pad.is_attack_held() and _owned and _state == 1 \
			and int(_own.get("alive", 1)) != 0
	var tgt := -1
	if held:
		tgt = _manual_alive()
		if tgt < 0:
			tgt = _pick_lowest_enemy(float(_manifest.get("reach", 3.25)) + 1.0)
	for nid in _views:
		var v: Dictionary = _views[nid]
		var ring = v.get("epic_ring")
		if ring == null or not is_instance_valid(ring):
			continue
		var nd = v.get("node")
		if nd == null or not is_instance_valid(nd):
			(ring as Node3D).visible = false
			continue
		# host JungleMonster._update_activity_ring：最近 2 秒挨过玩家的打 + 当前目标就是它
		var recent: bool = float(_last_snap_time) - float(v.get("hit_t", -999.0)) <= 2.0
		var show: bool = recent and nid == tgt and float(v.get("hp", 0.0)) > 0.0
		ring.visible = show
		if not show:
			continue
		if not bool(v.get("epic_center_set", false)):
			v["epic_center_set"] = true
			v["epic_center"] = nd.global_position
		var ctr: Vector3 = v["epic_center"]
		(ring as Node3D).global_position = Vector3(ctr.x, ctr.y + 0.17, ctr.z)
		var _rr: float = float(v.get("jring_r", 4.0))
		var out: bool = nd.global_position.distance_to(ctr) > _rr
		if out != bool(v.get("epic_red", false)):
			v["epic_red"] = out
			MeshFactory.set_ground_ring_color(ring,
				Color(1.0, 0.22, 0.18, 0.55) if out else Color(1.0, 1.0, 1.0, 0.42))

func _self_pos() -> Vector3:
	if _self_net >= 0 and _views.has(_self_net):
		var sv: Dictionary = _views[_self_net]
		if sv.has("target") and sv.target != null:
			return sv.target
		if sv.node != null:
			return sv.node.global_position
	return Vector3(float(_own.get("x", 0.0)), 0.0, float(_own.get("z", 0.0)))

func _entity_pos(nid: int) -> Vector3:
	if _views.has(nid):
		var v: Dictionary = _views[nid]
		if v.has("target") and v.target != null:
			return v.target
		if v.node != null:
			return v.node.global_position
	return _self_pos()

func _manual_alive() -> int:
	if _manual_net >= 0 and _views.has(_manual_net):
		var v: Dictionary = _views[_manual_net]
		if v.team != Config.player_team and v.hp > 0.0 and v.node != null:
			return _manual_net
	return -1

# —— HUD 控件（纯展示，输入由外部节点处理）——
class Hud:
	extends Control
	const MarkerIconScript = preload("res://scripts/ui/MarkerIcon.gd")
	const BarPainterScript = preload("res://scripts/ui/WorldBarPainter.gd")
	var _font: Font
	var _bar_painter: Control = null   # 非英雄单位血条复用单机 WorldBarPainter，保证三端质感一致
	var u := 1.0
	var safe_top := 0.0   # 刘海/挖孔避让：顶部战况带与状态文字整体下移
	var BAND_SHIFT := 564.0   # 顶部战况带右移量（对齐 host：面板左缘 1619，右缘 2029）
	var name_text := ""
	var level := 1
	var hp := 0.0
	var maxhp := 1.0
	var mana := 0.0
	var maxmana := 1.0
	var gold := 0
	var sp := 0
	var owned := false
	var skills: Array = []        # [{name, cd, cdmax, pending}]
	var bars: Array = []          # 英雄头顶血条 [{x,y,w,h,ratio,col}]
	var turret_bars: Array = []
	var wrows: Array = []          # P2 世界血条行 {kind:"hero"/"unit", …}（复刻主机 HUD / HealthBarControl）
	var status := ""
	var fp := false               # 第一人称：同 host 底部居中自身血条（第三人称不画自身条，交给头顶世界血条）
	var game_time := 0.0          # host battle.game_time（快照时间秒）：顶部战况带计时
	var reticle := Vector2(-9999.0, -9999.0)
	var pad_active := false   # 触控模式：底部右侧旧 1/2/3 预选技能栏让位触摸层技能钮
	var sa: Array = []        # 自身属性面板：18 行 [基础,装备,Buff] 三元组（host own.sa，顺序同 UiManager.ATTRIBUTE_ROWS）
	var sc: Dictionary = {}
	var vg: Array = []   # 顶部信息带第三行：[先锋名, 我方波数, 敌方波数, 是否已出动]   # 顶部实时战况：{pk,ek,pg,eg}（host SNAP_SCORE 全量统计）
	var kda: Array = []       # 主界面个人 K/D/A：[kills,deaths,assists]（host own.kills/…，同 host kda_label）
	var widget_rows: Array = []   # 小地图右侧英雄环形头像带行（host SNAP_RESPAWN，见 NetSession._build_respawn_rows）
	var show_widget := false      # 头像带显隐：对局中且有接管英雄时展示
	var _widget_hits: Array = []  # 复活头像带命中区 [[nid,team,dead,Rect2]]（阵亡点队友头像切镜头）

	# —— 受伤闪橙（复刻主机 HeroInfoControl/HealthBarControl：血量比上帧少 → 血条右端 0.5s 衰减橙段）——
	# 按 net_id 记世界血条各实体的上一血量/闪断宽度/超时；闪段只在 draw 衰减时不占 process
	var _prev_hp: Dictionary = {}
	var _flash_amt: Dictionary = {}
	var _flash_exp: Dictionary = {}
	var _own_prev: float = -1.0   # 左下角自身血条上一血量（-1=未初始化）
	var _own_flash: float = 0.0
	var _own_flash_exp := 0
	var hero_hit_cb := Callable()  # 世界血条掉血 → 英雄受击闪白回调（net_id 参数，由世界侧绑定）

	# —— 属性面板复刻主机样式常量（色值对齐 UI_Manager）——
	const ATTR_BASE_C := Color(1.0, 1.0, 1.0, 0.96)
	const ATTR_EQUIP_C := Color(0.42, 0.9, 0.42)
	const ATTR_BUFF_C := Color(1.0, 0.62, 0.25)
	const ATTR_NAME_C := Color(0.8, 0.83, 0.87)
	const ATTR_ROWS_PER_COL := 9
	var attr_collapsed := true          # 默认折叠（同 host UiManager.attr_collapsed）
	var _attr_head_rect := Rect2()      # 折叠标题条命中区（点击展开/收起）

	func _init() -> void:
		_font = UiKit.font()

	func _ready() -> void:
		_bar_painter = BarPainterScript.new()
		_bar_painter.name = "WorldBars"
		_bar_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bar_painter)

	func _text(pos: Vector2, txt: String, sz: float, col: Color) -> void:
		var ow := maxi(1, int(round(sz * 0.10)))
		draw_string_outline(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ow, Color(0, 0, 0, 0.72))
		draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

	func _draw() -> void:
		var s := u
		if not owned:
			_own_prev = -1.0   # 非接管态归零自检基线，避免跨局串闪
		# —— 顶部实时战况（击杀比分+经济比分；对局中常显） ——
		if not sc.is_empty():
			_draw_score_strip(s)
		# —— 顶部状态 ——
		if status != "":
			var sz := 16.0 * s
			var pos := Vector2(size.x * 0.5 - status.length() * sz * 0.28, 24.0 * s + safe_top)
			_text(pos, status, sz, Color(1, 1, 0.92))
		# —— 第一人称：底部自身血条（复刻 host HUD.fp_player_bar：HeroInfoControl 200×90，水平居中、底边 y-446）——
		# 第三人称不画自身条：主机自身血量只由头顶世界血条显示（同 host HUD）
		if owned and fp:
			var cx2 := size.x * 0.5
			var r2 := {"cx": cx2, "cy": size.y - 446.0 + 160.0, "level": level, "name": name_text,
				"hp": hp, "maxhp": maxhp, "hp_col": Color(0.0, 0.886, 0.431),
				"shield": 0.0, "mana": mana, "maxmana": maxmana,
				"exp": 0.0, "exp_to_next": 0.0, "hidden": false, "lyf": [], "mk": [], "nid": -1}
			_draw_hero_bar(r2)
		# —— 底部右侧：技能栏（触控模式 pad_active 时隐藏，让位触摸层技能钮；与主机同）——
		if not pad_active:
			var sbx := size.x - 26.0 * s - 3.0 * 96.0 * s
			var sby := size.y - 26.0 * s - 96.0 * s
			for i in range(3):
				var slot := Rect2(sbx + i * 100.0 * s, sby, 92.0 * s, 92.0 * s)
				draw_rect(slot, Color(0.1, 0.1, 0.14, 0.82), true)
				draw_rect(slot, Color(0.6, 0.6, 0.65, 0.6), false, 2.0 * s)
				var pending := false
				var cd := 0.0
				var cdmax := 0.0
				var nm := ""
				if i < skills.size():
					var sk: Dictionary = skills[i]
					nm = str(sk.get("name", ""))
					cd = float(sk.get("cd", 0))
					cdmax = float(sk.get("cdmax", 0))
					pending = bool(sk.get("pending", false))
				if pending:
					draw_rect(slot, Color(1.0, 0.85, 0.2, 0.55), false, 4.0 * s)
				var label := nm if nm != "" else ("%d" % (i + 1))
				_text(slot.position + Vector2(16.0 * s, 62.0 * s), label, 22.0 * s, Color(0.95, 0.95, 0.95))
				if cdmax > 0.0 and cd > 0.0:
					var frac := clampf(cd / cdmax, 0.0, 1.0)
					var cdr := Rect2(slot.position + Vector2(0.0, slot.size.y * (1.0 - frac)), Vector2(slot.size.x, slot.size.y * frac))
					draw_rect(cdr, Color(0, 0, 0, 0.72), true)
					if frac > 0.08:
						_text(slot.get_center() + Vector2(-16.0 * s, 6.0 * s), "%d" % ceili(cd), 17.0 * s, Color(1, 1, 1))
				_text(slot.position + Vector2(6.0 * s, -2.0 * s), str(i + 1), 11.0 * s, Color(1, 1, 1, 0.7))
		# —— 世界血条（P2：复刻主机规格；死亡/背后剔除已在收集侧完成）——
		_sync_flash()   # 受伤闪橙：按 net_id 对上帧血量，血量下探即记 0.5s 衰减橙段
		var _unit_rows: Array = []
		for r in wrows:
			if str(r.get("kind", "")) == "hero":
				_draw_hero_bar(r)
			else:
				_unit_rows.append(_to_world_bar_row(r))
		if _bar_painter != null:
			_bar_painter.rows = _unit_rows
		# —— 小地图右侧英雄环形头像带（复刻主机 respawn_container/RespawnWidget，两排）——
		if show_widget and not widget_rows.is_empty():
			_draw_respawn_widget_rows()
		# —— 自身属性面板（左下，复刻主机 UI_Manager：18 行 2 列 基础白/装备绿/增益橙）——
		if owned and sa.size() >= 3:
			_draw_attr_panel(s)
		# —— 施法准星 ——
		if reticle.x > -1000.0:
			var c := reticle
			draw_circle(c, 10.0 * s, Color(1, 0.9, 0.35, 0.4))
			draw_arc(c, 10.0 * s, 0.0, TAU, 24, Color(1, 0.85, 0.25, 0.95), 2.0 * s)

	func _bar_rect(r: Rect2, ratio: float, col: Color) -> void:
		draw_rect(r, Color(0.08, 0.08, 0.1, 0.75), true)
		if ratio > 0.0:
			draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), col, true)
		draw_rect(r, Color(1, 1, 1, 0.35), false, 1.5)

	# —— P2 世界血条绘制（复刻主机 HUD / HeroInfoControl / HealthBarControl）——
	func _team_color(t: int) -> Color:
		# 血条颜色按「本机阵营」相对上色：红方客户端自己的塔/兵也必须是友方色
		if t == 0 or t == 1:
			return Color(0.0, 0.886, 1.0) if Config.is_ally(t) else Color(1.0, 0.33, 0.264)
		if t == 2:
			return Color(0.0, 0.886, 0.431)
		return Color(0.945, 0.925, 0.251)

	# 经验等级圈（血条左端，几何/配色同主机 HeroInfoControl._draw_level_ring）
	func _draw_level_ring(c: Vector2, r: float, level_text: String, exp_ratio: float) -> void:
		draw_circle(c, r + 2.0, Color(0, 0, 0, 0.92))
		draw_circle(c, r - 1.0, Color(0.07, 0.08, 0.12, 0.95))
		draw_arc(c, r, 0.0, TAU, 32, Color.DIM_GRAY, 2.6)
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * exp_ratio, 32, UiKit.C_GOLD, 3.2)
		draw_arc(c, r - 2.6, PI * 1.12, PI * 1.84, 20, Color(1, 1, 1, 0.22), 1.2)
		var fs := int(round(r * 0.82))
		var tw := _font.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, c + Vector2(-tw * 0.5, fs * 0.36), level_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

	# 草丛隐藏图标（同主机 HeroInfoControl._draw_hidden_badge）
	func _draw_hidden_badge(c: Vector2, s: float) -> void:
		var t := Time.get_ticks_msec() * 0.001
		var pulse := 0.5 + 0.5 * sin(t * 3.0)
		draw_circle(c, s * (1.18 + 0.06 * pulse), Color(0.30, 0.86, 1.0, 0.10 + 0.06 * pulse))
		draw_circle(c, s, Color(0.06, 0.09, 0.13, 0.90))
		draw_arc(c, s - 0.8, 0.0, TAU, 28, Color(0.55, 0.86, 0.98, 0.90), 1.6)
		var eye_col := Color(0.86, 0.96, 1.0, 0.95)
		var ew := s * 0.62
		var eh := s * 0.40
		var pts := PackedVector2Array()
		for i in range(13):
			var a := PI + PI * float(i) / 12.0
			pts.append(c + Vector2(cos(a) * ew, -sin(a) * eh))
		for i in range(13):
			var a2 := PI * float(i) / 12.0
			pts.append(c + Vector2(cos(a2) * ew, sin(a2) * eh))
		pts.append(pts[0])
		draw_polyline(pts, eye_col, 1.8)
		draw_circle(c, s * 0.20, eye_col)
		draw_line(c + Vector2(-ew * 1.15, eh * 1.5), c + Vector2(ew * 1.15, -eh * 1.5), Color(1.0, 0.40, 0.34, 0.95), 2.2)

	# MVP 王冠（复刻 host HeroInfoControl._draw_mvp_badge，尺寸随血条高度）
	func _draw_mvp_badge(c: Vector2, r: float) -> void:
		var t: float = Time.get_ticks_msec() * 0.001
		var pulse: float = 0.5 + 0.5 * sin(t * 2.1)
		draw_circle(c, r * (1.46 + 0.08 * pulse), Color(1.0, 0.78, 0.30, 0.08 + 0.05 * pulse))
		draw_circle(c, r * 1.14, Color(1.0, 0.70, 0.22, 0.18))
		draw_circle(c, r, Color(0.11, 0.07, 0.02, 0.97))
		draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1.0, 0.80, 0.34, 0.95), 2.4)
		draw_arc(c, r * 0.84, 0.0, TAU, 40, Color(1.0, 0.72, 0.24, 0.45), 1.1)
		draw_arc(c, r - 1.8, PI * 1.12, PI * 1.86, 24, Color(1.0, 0.96, 0.82, 0.85), 1.5)
		var s: float = r * 0.76
		var pts := PackedVector2Array([
			c + Vector2(-0.62, 0.26) * s, c + Vector2(-0.62, -0.18) * s,
			c + Vector2(-0.31, 0.04) * s, c + Vector2(0.0, -0.48) * s,
			c + Vector2(0.31, 0.04) * s, c + Vector2(0.62, -0.18) * s,
			c + Vector2(0.62, 0.26) * s,
		])
		draw_colored_polygon(pts, Color(1.0, 0.84, 0.38, 0.98))
		draw_rect(Rect2(c + Vector2(-0.62, 0.27) * s, Vector2(1.24, 0.17) * s), Color(1.0, 0.68, 0.16, 0.98))
		for i in range(3):
			var gx: float = -0.34 + 0.34 * i
			draw_circle(c + Vector2(gx, 0.355) * s, s * 0.08, Color(0.26, 0.09, 0.02, 0.95))
		for pp in [Vector2(-0.62, -0.18), Vector2(0.0, -0.48), Vector2(0.62, -0.18)]:
			draw_circle(c + pp * s, s * 0.085, Color(1.0, 0.97, 0.86, 0.95))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.36, 0.19, 0.02, 0.85), 1.4)

	# 无兵线保护盾形图标（复刻 host WorldBarPainter._draw_shield_icon）
	func _draw_shield_glyph(c: Vector2, s: float, col: Color) -> void:
		# 与单机/回放共用同一份美化盾图标
		BarPainterScript.draw_shield_icon(self, c, s, col)

	func _draw_hero_bar(r: Dictionary) -> void:
		# 共享绘制：三端同一份 scripts/ui/shared/SharedHeroBar.gd；这里只把快照/本地差值喂成数据
		var hp_now := clampf(float(r.hp), 0.0, float(r.maxhp))
		var nid_h := int(r.get("nid", -1))
		r["lag"] = _lag_value(nid_h, hp_now)
		r["flash_ratio"] = _flash_ratio_of(nid_h) if nid_h >= 0 else 0.0
		r["flash_amt"] = float(_flash_amt.get(nid_h, 0.0)) if nid_h >= 0 else 0.0
		SharedHeroBarScript.draw(self, _font, r)

	func _to_world_bar_row(r: Dictionary) -> Dictionary:
		var w := float(r.get("w", 110.0))
		var h := float(r.get("h", 15.0))
		var hp_now := float(r.get("hp", 0.0))
		var mhp := maxf(float(r.get("maxhp", 1.0)), 1.0)
		var nid := int(r.get("nid", -1))
		var shield := clampf(float(r.get("shield", 0.0)), 0.0, mhp)
		var fr := _flash_ratio_of(nid) if nid >= 0 else 0.0
		var famt := float(_flash_amt.get(nid, 0.0)) if nid >= 0 else 0.0
		var lyf_rows: Array = r.get("lyf", [])
		var doom := 0.0
		var mlist: Array = []
		for m in lyf_rows:
			if m.size() >= 3:
				doom += float(m[2])
				if int(m[1]) > 0:
					mlist.append({"name": str(m[0]), "count": int(m[1]), "type": "lyf"})
		for m in r.get("mk", []):
			if m.size() >= 2 and int(m[1]) > 0:
				mlist.append({"name": str(m[0]), "count": int(m[1]), "type": ""})
		doom = clampf(doom - shield, 0.0, hp_now)
		return {
			"pos": Vector2(float(r.get("cx", 0.0)) - w * 0.5, float(r.get("cy", 0.0)) - h * 0.5),
			"w": w, "h": h, "hp": hp_now, "max_hp": mhp,
			"team": int(r.get("team", 9)), "team_color": _team_color(int(r.get("team", 9))),
			"shield": shield, "epic": bool(r.get("epic", false)),
			"ticks": bool(r.get("ticks", false)), "tick_step": float(r.get("tick_step", 1000.0)),
			"interfere": 0.0, "last_hit": bool(r.get("last_hit", false)),
			"lag": hp_now + famt * fr, "flash_t": fr * 0.5, "flash_amt": famt,
			"heal_t": 0.0, "heal_amt": 0.0, "doom": doom,
			"show_name": false,   # 野怪血条不显示名字
			"name_text": str(r.get("name", "")),
			"show_numbers": false, "num_text": "",
			"turret_arrow": bool(r.get("turret", false)),
			"shield_icon": bool(r.get("shield_icon", false)),
			"marker_list": mlist,
		}

	func _draw_unit_bar(r: Dictionary) -> void:
		var bw := float(r.w)
		var bh := float(r.h)
		var left := float(r.cx) - bw / 2.0
		var top2 := float(r.cy) - bh / 2.0
		var mhp := maxf(float(r.maxhp), 1.0)
		var hp_now := clampf(float(r.hp), 0.0, float(r.maxhp))
		var lyf_rows2: Array = r.get("lyf", [])
		var lyf_pred2 := 0.0
		var ltxt2 := ""
		for m in lyf_rows2:
			if m.size() >= 3:
				lyf_pred2 += float(m[2])
				var _s3 := ("%d层" % int(m[1])) if int(m[1]) > 0 else ""
				ltxt2 += ("%s·暗印%s " % [str(m[0]), _s3])
		# 受伤闪橙（0.5s 衰减）读本行 net_id 的上帧血量差（史诗怪走分格紫条专用叠加）
		var _nid_u := int(r.get("nid", -1))
		var _fratio_u := 0.0
		var _fhp_u := 0.0
		if _nid_u >= 0:
			_fratio_u = _flash_ratio_of(_nid_u)
			if _fratio_u > 0.0:
				_fhp_u = float(_flash_amt.get(_nid_u, 0.0))
		if bool(r.get("epic", false)):
			_draw_epic_bar(left, top2, bw, bh, hp_now, mhp, lyf_pred2, float(r.get("shield", 0.0)), _fhp_u, _fratio_u)
		else:
			var tc := _team_color(int(r.get("team", 9)))
			draw_rect(Rect2(left, top2, bw, bh), Color(0, 0, 0, 0.4))
			var fw := bw * (hp_now / mhp)
			draw_rect(Rect2(left, top2, fw, bh / 2.0), tc.lightened(0.2))
			draw_rect(Rect2(left, top2 + bh / 2.0, fw, bh / 2.0), tc.darkened(0.2))
			# 暗印预判黄段（当前血右尾）
			var shield := clampf(float(r.get("shield", 0.0)), 0.0, float(r.maxhp))
			if lyf_pred2 > 0.0:
				var doom := clampf(lyf_pred2 - shield, 0.0, hp_now)
				var doom_w := (doom / mhp) * bw
				if doom_w > 0.5:
					draw_rect(Rect2(left + fw - doom_w, top2, doom_w, bh), Color(1.0, 0.88, 0.18, 0.9))
			if shield > 0.0:
				var sw := minf(shield / mhp * bw, bw - fw)
				if sw > 0.5:
					var sr := Rect2(left + fw, top2, sw, bh)
					draw_rect(sr, Color(0.72, 0.82, 0.95, 0.92))
					draw_rect(Rect2(sr.position, Vector2(sw, maxf(1.5, bh * 0.14))), Color(1, 1, 1, 0.55))
					var hx2 := 2.0
					while hx2 < sw:
						draw_line(sr.position + Vector2(hx2, bh), sr.position + Vector2(hx2 + bh * 0.55, 0),
							Color(1, 1, 1, 0.28), 1.0)
						hx2 += 4.0
					draw_rect(Rect2(sr.position, Vector2(1.0, bh)), Color(1, 1, 1, 0.75))
			# 受伤闪橙：血量右端 0.5s 衰减（同 host WorldBarPainter：1.0,0.58,0.10 + 顶部亮边）
			if _fratio_u > 0.0 and _fhp_u > 0.0:
				var _fw_u := (_fhp_u / mhp) * bw * _fratio_u
				if _fw_u > 0.5:
					draw_rect(Rect2(left + fw, top2, _fw_u, bh), Color(1.0, 0.58, 0.10, 0.85))
					draw_rect(Rect2(left + fw, top2, _fw_u, maxf(1.5, bh * 0.14)), Color(1.0, 0.85, 0.55, 0.9))
			# 低血脉冲（<30% 红色呼吸外发光，同 host）
			var _ratio_u := hp_now / mhp
			if _ratio_u < 0.3 and hp_now > 0.0:
				var _pulse_u: float = 0.30 + 0.35 * absf(sin(Time.get_ticks_msec() * 0.0052))
				draw_rect(Rect2(left - 2.0, top2 - 2.0, bw + 4.0, bh + 4.0),
					Color(1.0, 0.20, 0.14, _pulse_u * 0.55), false, 2.0)
				draw_rect(Rect2(left, top2, bw, bh), Color(1.0, 0.30, 0.22, _pulse_u * 0.22))
			# 野怪 / 主宰先锋：每 1000 血一条分隔线（复刻主机 WorldBarPainter）
			if bool(r.get("ticks", false)):
				var tick_step: float = maxf(100.0, float(r.get("tick_step", 1000.0))) / mhp * bw
				if tick_step > 5.0:
					var tx := tick_step
					while tx < bw - 1.0:
						draw_line(Vector2(left + tx, top2), Vector2(left + tx, top2 + bh),
							Color(0, 0, 0, 0.55), 1.5)
						draw_line(Vector2(left + tx + 1.5, top2), Vector2(left + tx + 1.5, top2 + bh),
							Color(1, 1, 1, 0.14), 1.0)
						tx += tick_step
			draw_rect(Rect2(left, top2, bw, bh), Color(tc.r, tc.g, tc.b, 0.5), false, 1.0)
		# 无兵线保护盾形图标（host：画在血条左侧居中，高 74% 血条高、上限 20px）
		if bool(r.get("shield_icon", false)):
			var _ss: float = minf(bh * 0.74, 20.0)
			_draw_shield_glyph(Vector2(left - (_ss + 10.0), top2 + bh * 0.5), _ss, _team_color(int(r.get("team", 9))))
		# 防御塔：不画名称标签，改为血条下方一个指向塔身的小三角箭头
		# host 规则：只有野怪显示名称（show_name = is_monster），字号 20、居中、带描边；小兵不挂名字
		var label := str(r.get("name", ""))
		var fs := 20.0
		var _lh := 0.0
		if bool(r.get("turret", false)):
			var tc_ar := _team_color(int(r.get("team", 9)))
			var ax2: float = left + bw * 0.5
			var ay2: float = top2 + bh + 3.0
			var aw2: float = maxf(8.0, bh * 0.5)
			var ah2: float = aw2 * 1.2
			draw_colored_polygon(PackedVector2Array([
				Vector2(ax2 - aw2, ay2), Vector2(ax2 + aw2, ay2), Vector2(ax2, ay2 + ah2),
			]), Color(tc_ar.r, tc_ar.g, tc_ar.b, 0.95))
			draw_polyline(PackedVector2Array([
				Vector2(ax2 - aw2, ay2), Vector2(ax2 + aw2, ay2), Vector2(ax2, ay2 + ah2),
				Vector2(ax2 - aw2, ay2),
			]), Color(0, 0, 0, 0.65), 1.2)
		elif bool(r.get("monster", false)) and not bool(r.get("small", false)) and label != "":
			# 野怪名称：居中压在血条上方 10px（与 host WorldBarPainter / HUD 同款：fs 20 + 阴影 + 4px 描边）
			var _asc := _font.get_ascent(fs)
			var np := Vector2(left + 1.2, top2 - 10.0 + _asc + 1.5)
			draw_string(_font, np, label, HORIZONTAL_ALIGNMENT_CENTER, bw, fs, Color(0, 0, 0, 0.55))
			draw_string_outline(_font, Vector2(left, top2 - 10.0 + _asc), label,
				HORIZONTAL_ALIGNMENT_CENTER, bw, fs, 4, Color(0, 0, 0, 0.9))
			draw_string(_font, Vector2(left, top2 - 10.0 + _asc), label,
				HORIZONTAL_ALIGNMENT_CENTER, bw, fs, Color(0.96, 0.97, 1.0))
		# 标记图标（血条上方一行；专属图标 + 右上角层数）
		var _mk_rows: Array = []
		for m in lyf_rows2:
			if m.size() >= 3 and int(m[1]) > 0:
				_mk_rows.append({"name": str(m[0]), "count": int(m[1]), "type": "lyf"})
		for m in r.get("mk", []):
			if m.size() >= 2 and int(m[1]) > 0:
				_mk_rows.append({"name": str(m[0]), "count": int(m[1]), "type": ""})
		if not _mk_rows.is_empty():
			var mr := 16.0
			var my := top2 - 8.0 - _lh - mr * 2.0 - 4.0
			MarkerIconScript.draw_row(self, left + bw * 0.5, my, _mk_rows, mr)

	# 史诗怪大号分格紫条（复刻 HealthBarControl._draw_epic_bar，静态分格填充）
	func _draw_epic_bar(left: float, top2: float, bw: float, bh: float, hp_now: float, mhp: float, lyf_pred2: float = 0.0, shield: float = 0.0, flash_hp: float = 0.0, flash_ratio: float = 0.0) -> void:
		var seg_count := maxi(1, int(ceil(mhp / 1000.0)))
		var seg_total := float(seg_count) * 1000.0
		var seg_w := bw / float(seg_count)
		var to_w := bw / seg_total
		var fill_w := hp_now * to_w
		var margin := 1.5
		var inset_y := 2.5
		var avail_h := bh - inset_y * 2.0
		var cell_color := Color(0.13, 0.05, 0.24, 0.95)
		var top_col := Color(0.8, 0.45, 1.0)
		var bot_col := Color(0.46, 0.16, 0.82)
		for i in seg_count:
			var x0 := float(i) * seg_w
			var x1 := minf((float(i) + 1.0) * seg_w, bw)
			if x1 - x0 <= margin * 2.0:
				continue
			var cell_w := x1 - x0 - margin * 2.0
			draw_rect(Rect2(left + x0 + margin, top2 + inset_y, cell_w, avail_h), cell_color)
			var filled := clampf(fill_w - (x0 + margin), 0.0, cell_w)
			if filled > 0.0:
				draw_rect(Rect2(left + x0 + margin, top2 + inset_y, filled, avail_h * 0.5), top_col)
				draw_rect(Rect2(left + x0 + margin, top2 + inset_y + avail_h * 0.5, filled, avail_h * 0.5), bot_col)
		# 暗印预判黄段（当前血量右尾，跨分格透明覆盖）
		if lyf_pred2 > 0.0:
			var doom := clampf(lyf_pred2 - shield, 0.0, hp_now)
			var dw := doom * to_w
			if dw > 0.5:
				draw_rect(Rect2(left + maxf(fill_w - dw, 0.0), top2 + inset_y, dw, avail_h), Color(1.0, 0.88, 0.18, 0.7))
		# 受伤闪橙：贴血量右边界 0.5s 衰减（复刻主机 HealthBarControl._draw_epic_bar L175-180）
		if flash_ratio > 0.0 and flash_hp > 0.0:
			var _few := flash_hp * to_w * flash_ratio
			if _few > 0.5:
				draw_rect(Rect2(left + fill_w, top2 + inset_y, minf(_few, bw - fill_w), avail_h), Color(1.0, 0.55, 0.1, 0.9))
		draw_rect(Rect2(left, top2, bw, bh), Color(1.0, 0.9, 1.0, 0.5), false, 1.5)

	func _sync_flash() -> void:
		var now := Time.get_ticks_msec()
		var seen := {}
		for r in wrows:
			var nid := int(r.get("nid", -1))
			if nid < 0:
				continue
			seen[nid] = true
			var hpv := float(r.hp)
			if not _prev_hp.has(nid):
				_prev_hp[nid] = hpv
			else:
				var prev := float(_prev_hp[nid])
				if hpv < prev - 0.1:
					_flash_amt[nid] = prev - hpv
					_flash_exp[nid] = now + 500
					# 英雄受击 → 模型闪白（与血条闪橙同源；小兵/塔不闪）
					if str(r.get("kind", "")) == "hero" and hero_hit_cb.is_valid():
						hero_hit_cb.call(nid)
				_prev_hp[nid] = hpv
		for nid in _prev_hp.keys():
			if not seen.has(nid):
				_prev_hp.erase(nid)
				_flash_amt.erase(nid)
				_flash_exp.erase(nid)

	# 残血拖尾值（同 host HeroInfoControl._hp_lag：按 delta×4 向当前血量收敛；回血时立即跟上）
	var _lag_hp: Dictionary = {}
	func _lag_value(nid: int, hp_now: float) -> float:
		if not _lag_hp.has(nid):
			_lag_hp[nid] = hp_now
			return hp_now
		var lag := float(_lag_hp[nid])
		if hp_now >= lag:
			_lag_hp[nid] = hp_now
			return hp_now
		var dt := clampf(get_process_delta_time(), 0.0, 0.1)
		lag = lerpf(lag, hp_now, clampf(dt * 4.0, 0.0, 1.0))
		_lag_hp[nid] = lag
		return lag

	func _flash_ratio_of(nid: int) -> float:
		var exp0: int = int(_flash_exp.get(nid, 0))
		if exp0 <= 0:
			return 0.0
		var ms := exp0 - Time.get_ticks_msec()
		if ms <= 0:
			_flash_exp.erase(nid)
			_flash_amt.erase(nid)
			return 0.0
		return clampf(float(ms) / 500.0, 0.0, 1.0)

	# —— 小地图右侧英雄环形头像带（同 host respawn_container：小地图右侧 (340,28)，单元 130×150、行距 6、环 r=56.25）——
	func _draw_respawn_widget_rows() -> void:
		_widget_hits.clear()
		var x0 := 500.0 + UiKit.safe_left()   # 小地图 450 宽 + 内距
		var y0 := 28.0 + safe_top
		var cell_w := 130.0
		var cell_h := 150.0
		var sep_x := 4.0     # host 行内 HBoxContainer 默认 separation
		var sep_y := 6.0     # host respawn_container.separation
		var row1: Array = []
		var row2: Array = []
		for r in widget_rows:
			if r.size() < 10:
				continue
			if int(r[1]) == int(Config.player_team):
				row1.append(r)   # 我方整排：含残血/复活读秒，恒显（红方玩家时=红方）
			else:
				row2.append(r)   # 敌方：host 只在阵亡时下发，复活自动消失
		var rows_all: Array = [row1]
		if not row2.is_empty():
			rows_all.append(row2)
		var yy := y0
		for row in rows_all:
			var xx := x0
			for r in row:
				_draw_widget_cell(r, xx, yy)
				if r.size() >= 8:
					_widget_hits.append([int(r[0]), int(r[1]), int(r[7]), Rect2(xx, yy, cell_w, cell_h)])
				xx += cell_w + sep_x
			yy += cell_h + sep_y

	func _draw_widget_cell(r: Array, xx: float, yy: float) -> void:
		var center := Vector2(xx + 65.0, yy + 75.0)   # 单元 130×150 中心（同 host custom_minimum_size）
		var ring_r := 56.25                            # 同 host ring_radius = 45×1.25
		var team := int(r[1])
		var is_ai := int(r[6]) == 1
		var dead := int(r[7]) == 1
		var ally := Config.is_ally(team)
		var bg := Color(1.0, 0.33, 0.264)
		if ally:
			bg = Color(0.0, 0.886, 1.0) if is_ai else Color(0.0, 0.886, 0.431)
		if dead:
			bg = Color(0.04, 0.05, 0.07) if ally else Color(0.32, 0.05, 0.07)
		# 专属英雄徽记头像（同 host RespawnWidget；r[2]=英雄名）
		var team_tint := (Color(0.0, 0.886, 1.0) if is_ai else Color(0.0, 0.886, 0.431)) if ally else Color(1.0, 0.33, 0.264)
		HeroArt.draw_portrait(self, center, ring_r, str(r[2]), team_tint, dead)
		draw_arc(center, ring_r + 3.75, 0.0, TAU, 48, Color.BLACK, 5.0)
		if dead:
			var total := float(r[9])
			var remain := maxf(float(r[8]), 0.0)
			var prog := 1.0
			if total > 0.0:
				prog = clampf(1.0 - remain / total, 0.0, 1.0)
			draw_arc(center, ring_r + 3.75, -PI / 2.0, -PI / 2.0 + TAU * prog, 48, Color.WHITE, 5.0)
			_draw_widget_mid(center, str(int(ceil(remain))))
		else:
			var maxhp := maxf(float(r[5]), 1.0)
			var hratio := clampf(float(r[4]) / maxhp, 0.0, 1.0)
			var hcol := Color(0.25, 1.0, 0.3) if hratio > 0.5 else (Color(1.0, 0.9, 0.2) if hratio > 0.25 else Color(1.0, 0.3, 0.2))
			draw_arc(center, ring_r + 3.75, -PI / 2.0, -PI / 2.0 + TAU * hratio, 48, hcol, 5.0)

	func widget_at(pos: Vector2) -> Array:
		for h in _widget_hits:
			if (h[3] as Rect2).has_point(pos):
				return h
		return []


	func _draw_widget_mid(center: Vector2, txt: String) -> void:
		var sz := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var mp := Vector2(center.x - sz * 0.5, center.y + 9.0)
		draw_string_outline(_font, mp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 3, Color(0, 0, 0, 0.75))
		draw_string(_font, mp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	# —— 顶部实时战况：与 host UI_Manager._create_info_labels/_update_team_stats 完全同版式 ——
	# 与 host UI_Manager._create_battle_hud 顶带逐项对齐：
	# team_stats_bg（中心 -145..+315 / y6..150，0.62 玻璃圆角 + 投影）、time_chip（-140..+110 / y8..52，居中 24px 计时）、
	# K/D/A（右对齐到 +300 / y12..48，20px）、经济比分（中心 +85 / y82 起，24px）、FPS（bg 内 (5,50) 120×24 居中，14px 固定绿）
	func _draw_score_strip(s: float) -> void:
		var st := safe_top
		# 与 host UI_Manager._create_info_labels 完全同一套右锚定坐标：
		# 主面板 x=W-781..W-371 / y=6..196；计时条 W-776..W-526 / y=8..52；比分中心 W-576。
		var panel_left := size.x - 781.0
		# 与单机 UI_Manager._apply_panel_style 完全同参数：深色玻璃 + 1px 冷光边 + 圆角 + 投影
		var bg_style := UiKit.flat(0.62, 12, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0.62), 10.0, 6.0)
		draw_style_box(bg_style, Rect2(panel_left, 6.0 + st, 410.0, 190.0))
		draw_style_box(bg_style, Rect2(size.x - 776.0, 8.0 + st, 250.0, 44.0))
		# 顶部玻璃反光：一条极淡的冷白高光，补足平面底板的廉价感
		draw_line(Vector2(panel_left + 12.0, 8.0 + st), Vector2(panel_left + 398.0, 8.0 + st),
			Color(0.72, 0.88, 1.0, 0.18), 1.0)
		draw_line(Vector2(size.x - 764.0, 9.0 + st), Vector2(size.x - 538.0, 9.0 + st),
			Color(0.72, 0.88, 1.0, 0.16), 1.0)
		var gs := 24.0 * s
		var gd := _font.get_ascent(gs) + _font.get_descent(gs)
		var gy := 8.0 + st + (44.0 - gd) * 0.5 + _font.get_ascent(gs)
		var time_txt := "%02d:%02d" % [int(game_time) / 60, int(game_time) % 60]
		draw_string_outline(_font, Vector2(size.x - 776.0, gy), time_txt,
				HORIZONTAL_ALIGNMENT_CENTER, 250.0, gs, 2, Color(0, 0, 0, 0.72))
		draw_string(_font, Vector2(size.x - 776.0, gy), time_txt,
				HORIZONTAL_ALIGNMENT_CENTER, 250.0, gs, Color.WHITE)
		# FPS：bg 内 (5,50) 120×24 居中，颜色与 host 一样按帧率变化
		var fs := 14.0 * s
		var fd := _font.get_ascent(fs) + _font.get_descent(fs)
		var fy := 6.0 + st + 50.0 + (24.0 - fd) * 0.5 + _font.get_ascent(fs)
		var fps_now := Engine.get_frames_per_second()
		var fps_col := Color(1.0, 0.42, 0.38) if fps_now < 30 else (Color(1.0, 0.82, 0.35) if fps_now < 50 else Color(0.55, 0.95, 0.65))
		var fps_txt := "FPS %d" % fps_now
		draw_string_outline(_font, Vector2(size.x - 776.0, fy), fps_txt,
				HORIZONTAL_ALIGNMENT_CENTER, 120.0, fs, 1, Color(0, 0, 0, 0.65))
		draw_string(_font, Vector2(size.x - 776.0, fy), fps_txt,
				HORIZONTAL_ALIGNMENT_CENTER, 120.0, fs, fps_col)
		if kda.size() >= 3:
			var ks := 20.0 * s
			var kd := _font.get_ascent(ks) + _font.get_descent(ks)
			var ky := 12.0 + st + (36.0 - kd) * 0.5 + _font.get_ascent(ks)
			var kda_txt := "K/D/A: %d/%d/%d" % [int(kda[0]), int(kda[1]), int(kda[2])]
			draw_string_outline(_font, Vector2(size.x - 773.0, ky), kda_txt,
					HORIZONTAL_ALIGNMENT_RIGHT, 394.0, ks, 2, Color(0, 0, 0, 0.72))
			draw_string(_font, Vector2(size.x - 773.0, ky), kda_txt,
					HORIZONTAL_ALIGNMENT_RIGHT, 394.0, ks, Color.WHITE)
		var sz := 24.0 * s
		var base := 82.0 + st + _font.get_ascent(sz)
		var _my_blue: bool = int(Config.player_team) == 0
		var my_g: int = int(sc.get("pg", 0)) if _my_blue else int(sc.get("eg", 0))
		var my_k: int = int(sc.get("pk", 0)) if _my_blue else int(sc.get("ek", 0))
		var foe_g: int = int(sc.get("eg", 0)) if _my_blue else int(sc.get("pg", 0))
		var foe_k: int = int(sc.get("ek", 0)) if _my_blue else int(sc.get("pk", 0))
		var segs: Array = [
			["%s " % _format_gold(my_g), Color(0.0, 0.886, 1.0)],
			["%d " % my_k, Color.WHITE],
			["vs", Color.WHITE],
			[" %d " % foe_k, Color.WHITE],
			[_format_gold(foe_g), Color(1.0, 0.33, 0.264)],
		]
		# 第三行：主宰/暗影/风暴先锋剩余波次（同 host 顶部信息带第三行）
		if vg.size() >= 4 and (int(vg[3]) == 1 or int(vg[1]) > 0 or int(vg[2]) > 0):
			var vs := 20.0 * s
			var vd := _font.get_ascent(vs) + _font.get_descent(vs)
			var vy := 148.0 + st + (38.0 - vd) * 0.5 + _font.get_ascent(vs)
			var vtxt := ""
			var vcol: Color = Color(0.72, 0.76, 0.85)
			if int(vg[1]) > 0:
				vtxt = "%s 我方 %d 波 · 敌方 %d 波" % [str(vg[0]), int(vg[1]), int(vg[2])]
				vcol = UiKit.C_GOLD
			elif int(vg[2]) > 0:
				vtxt = "%s 我方 %d 波 · 敌方 %d 波" % [str(vg[0]), int(vg[1]), int(vg[2])]
				vcol = Color(1.0, 0.33, 0.264)
			else:
				vtxt = "%s 已出完" % str(vg[0])
			draw_string_outline(_font, Vector2(panel_left, vy), vtxt,
				HORIZONTAL_ALIGNMENT_CENTER, 410.0, vs, 2, Color(0, 0, 0, 0.68))
			draw_string(_font, Vector2(panel_left, vy), vtxt,
				HORIZONTAL_ALIGNMENT_CENTER, 410.0, vs, vcol)
		# 第二行在比分面板内居中（host 面板中心 = 屏幕右缘 -576）
		var total := 0.0
		for g in segs:
			total += _font.get_string_size(str(g[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var bx := size.x - 576.0 - total * 0.5
		for g in segs:
			var txt: String = str(g[0])
			_text(Vector2(bx, base), txt, sz, g[1])
			bx += _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x

	# 金币格式化（对齐主机 UI_Manager._format_gold：≥1000 → %.1fk）
	func _format_gold(v: int) -> String:
		if v >= 1000:
			return "%.1fk" % (v / 1000.0)
		return str(v)

	# —— 自身属性面板（同 host attribute_panel：小地图下方 (40, 350+safe)，标题条 30rs + 图例 26rs + 18 行 2 列 ×28rs）——
	func _draw_attr_panel(s: float) -> void:
		var cfg: Array = UiManager.ATTRIBUTE_ROWS
		var n := mini(cfg.size(), int(sa.size() / 3))
		if n <= 0:
			return
		var pad := 12.0 * s
		var head_h := 30.0 * s
		var legend_h := 26.0 * s
		var row_h := 28.0 * s
		var col_w := 200.0 * s
		var col_gap := 12.0 * s
		var ncol := 2
		var panel_w := pad * 2.0 + col_w * float(ncol) + col_gap * float(ncol - 1)
		var panel_h := pad * 2.0 + head_h + legend_h + row_h * ATTR_ROWS_PER_COL
		# 默认折叠（同 host UiManager.attr_collapsed）：只留一条标题条，点一下展开
		if attr_collapsed:
			# 收起态底板宽度跟小地图同宽（450），否则比小地图窄/宽都会看着像底板错位
			panel_w = minf(panel_w, 450.0)
			panel_h = pad * 2.0 + head_h
		# 紧贴小地图下方（小地图 inset 40 + 450，再留 10），顶边固定、向下展开（同 host）
		var left := 40.0 + UiKit.safe_left()
		var top := 40.0 + safe_top + 460.0
		draw_style_box(UiKit.flat(0.5, 12, 1), Rect2(left, top, panel_w, panel_h))
		_attr_head_rect = Rect2(left, top, panel_w, maxf(panel_h, head_h + pad * 2.0))
		# 折叠标题条（同 host attr_header："属性  ▼"，16px）
		var hs := 16.0 * s
		draw_string(_font, Vector2(left + pad, top + 2.0 * s + (head_h - (_font.get_ascent(hs) + _font.get_descent(hs))) * 0.5 + _font.get_ascent(hs)),
				"属性  ▼" if attr_collapsed else "属性  ▲", HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.85, 0.9, 1.0, 0.95))
		if attr_collapsed:
			return
		# 图例：基础（白） +装备（绿） +增益（橙），同 host legend 文案/配色
		var lys := 13.0 * s
		var ly := top + pad + head_h + (_font.get_ascent(lys) + _font.get_descent(lys)) * 0.5 + _font.get_ascent(lys)
		var lx := left + pad
		for lg in [
			["基础", Color.WHITE],
			["  +装备", ATTR_EQUIP_C],
			["  +增益", ATTR_BUFF_C],
		]:
			var lt: String = str(lg[0])
			draw_string(_font, Vector2(lx, ly), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lys, lg[1])
			lx += _font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lys).x
		var y0 := top + pad + head_h + legend_h
		var rfs := 15.0 * s
		var nfs := 15.0 * s
		for i in range(n):
			var c: Dictionary = cfg[i]
			var col := int(i / ATTR_ROWS_PER_COL)
			var ri := i % ATTR_ROWS_PER_COL
			var x0 := left + pad + float(col) * (col_w + col_gap)
			var mult := float(c.get("mult", 1.0))
			var pct := bool(c.get("pct", false))
			var base_v := float(sa[i * 3]) * mult
			var equip_v := float(sa[i * 3 + 1]) * mult
			var buff_v := float(sa[i * 3 + 2]) * mult
			var row_y := y0 + float(ri) * row_h + row_h * 0.72
			var nm: String = str(c.get("name", "")) + "  "
			draw_string(_font, Vector2(x0, row_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, ATTR_NAME_C)
			var tx := x0 + _font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
			var wrote := false
			var segs2: Array = []
			for k in range(3):
				var v: float = [base_v, equip_v, buff_v][k]
				if absf(v) < 0.05:
					continue
				var t2: String = _attr_txt(v, pct)
				if k > 0 and v > 0.0:
					t2 = "+" + t2
				segs2.append([t2, [ATTR_BASE_C, ATTR_EQUIP_C, ATTR_BUFF_C][k]])
				wrote = true
			if not wrote:
				segs2.append(["0", ATTR_BASE_C])
			for seg3 in segs2:
				var t3: String = str(seg3[0])
				draw_string(_font, Vector2(tx, row_y), t3, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, seg3[1])
				tx += _font.get_string_size(t3, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x

	func _attr_txt(e: float, pct: bool) -> String:
		if pct:
			var r := roundf(e * 10.0) / 10.0
			if absf(r - roundf(r)) < 0.05:
				return "%d%%" % int(roundf(r))
			return "%.1f%%" % r
		return "%d" % int(roundf(e))


# 暴击四芒星爆点（复刻 host UI_Manager.CritMark：外层金色四芒星 + 内层橙红小星）
class _CritMark extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var k := minf(size.x, size.y) * 0.5
		var gold := Color(1.0, 0.8, 0.15, 1.0)
		var hot := Color(1.0, 0.45, 0.2, 1.0)
		var pts := PackedVector2Array()
		for i in range(8):
			var ang := float(i) * PI / 4.0 + PI / 8.0
			var rad := k if i % 2 == 0 else k * 0.22
			pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts, gold)
		var pts2 := PackedVector2Array()
		for i in range(8):
			var ang := float(i) * PI / 4.0 + PI / 8.0
			var rad := k * 0.48 if i % 2 == 0 else k * 0.14
			pts2.append(c + Vector2(cos(ang), sin(ang)) * rad)
		draw_colored_polygon(pts2, hot)


















