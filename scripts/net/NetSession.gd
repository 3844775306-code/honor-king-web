# NetSession.gd — 联机会话（M0：连接/名单；M1：主机快照广播 + 客户端观战棋盘；M2：真人接管）
#
# 设计：房主权威（host-authoritative）。主机运行全部模拟；
# 客户端零模拟，只「收已揭示实体的快照」+「上行意图指令（rpc）」，由主机校验后执行。
#
# 命令行参数（放在 `--` 之后）：
#   --net-host [port]     本机当主机（默认端口 7000）
#   --net-join <ip:port>  本机当客户端，连到该主机
#   --net-test            CI 标记：host 让 BattleManager 自动开局；client headless 跑脚本化接管驱动
#
# 无网络参数启动时本文件零副作用，单机玩法不变。

extends Node

const DeathRecapView = preload("res://scripts/ui/DeathRecapView.gd")
const SNAPSHOT_HZ := 30.0
const SNAPSHOT_INTERVAL := 1.0 / SNAPSHOT_HZ

const TEAM_PLAYER := 0   # 与 Config.Team.PLAYER 一致，避免跨 autoload 解析

enum Mode { NONE, HOST, CLIENT }
enum Phase { LOBBY, SELECT, BATTLE }   # LOBBY=房间；SELECT=大厅选人（全员锁齐才可开局）；BATTLE=已开局

const MAX_SIDE_PLAYERS := 5   # 蓝方真人上限（host=1 + 先连 4 名 client），严格一人一职共 5 席

# —— 触控技能键效果小字元数据（与 TouchController.FX_META 同源，peer 并行文件故复制）——
# 客户端无 Hero/托管实体，技能键图标读数(伤害预览/效果小字/多段窗口/充能/前置阻塞)由 host 编码进
# own.sx 下传，NetTouchPad 再喂共享 SkillTouchButton。这里只保留 _encode_button_fx 所需：效果标签文本
# 规则(sec/durs/num/two/flag) + 敌我配色归属。client 端无需本表（NetTouchPad 用 buff/debuff 两色+解码）。
const FX_META := {
	"slow":      {"ic": "缓", "c": Color(0.35, 0.78, 1.0), "two": true},
	"selfspeed": {"ic": "速", "c": Color(0.55, 1.0, 0.6), "two": true},
	"stun":      {"ic": "晕", "c": Color(1.0, 0.88, 0.4), "sec": true},
	"knockup":   {"ic": "飞", "c": Color(1.0, 0.68, 0.32), "sec": true},
	"freeze":    {"ic": "冰", "c": Color(0.5, 0.82, 1.0), "sec": true},
	"suppress":  {"ic": "压", "c": Color(1.0, 0.5, 0.5), "sec": true},
	"bt":        {"ic": "霸", "c": Color(1.0, 0.82, 0.35), "sec": true},
	"shield":    {"ic": "盾", "c": Color(0.52, 0.72, 1.0)},
	"heal":      {"ic": "愈", "c": Color(0.6, 1.0, 0.7)},
	"defup":     {"ic": "抗", "c": Color(0.6, 1.0, 0.72), "durs": true},
	"defdn":     {"ic": "削", "c": Color(0.55, 0.85, 1.0), "two": true},
	"armup":     {"ic": "甲", "c": Color(0.6, 1.0, 0.72), "durs": true},
	"armdn":     {"ic": "甲", "c": Color(0.55, 0.85, 1.0), "two": true},
	"mrup":      {"ic": "魔", "c": Color(0.6, 1.0, 0.72), "durs": true},
	"mrdn":      {"ic": "魔", "c": Color(0.55, 0.85, 1.0), "num": true},
	"asup":      {"ic": "攻", "c": Color(0.6, 1.0, 0.72), "two": true},
	"asdn":      {"ic": "钝", "c": Color(0.55, 0.85, 1.0), "two": true},
	"atkdn":     {"ic": "攻", "c": Color(0.55, 0.85, 1.0), "two": true},
	"msup":      {"ic": "速", "c": Color(0.55, 1.0, 0.6), "durs": true},
	"armred":    {"ic": "甲", "c": Color(0.55, 0.85, 1.0), "num": true},
	"unsel":     {"ic": "免", "c": Color(0.6, 1.0, 0.72), "sec": true},
	"cleanse":   {"ic": "净", "c": Color(0.6, 1.0, 0.72), "flag": true},
}
# 效果落在敌人身上 → 蓝小字；落在自身/友军 → 绿（skill 键配色：作用于敌人=负面）
const FX_HOSTILE_TYPES := [
	"slow", "stun", "knockup", "freeze", "suppress",
	"defdn", "armdn", "armred", "mrdn", "asdn", "atkdn",
]
const FX_BUFF_COL := Color(0.45, 1.0, 0.62)
const FX_DEBUFF_COL := Color(0.55, 0.85, 1.0)

# --- 运行时状态 ---
var mode := Mode.NONE
var host_port := 7000
var join_address := "127.0.0.1"
var web_server_url := ""   # ?server=wss://... 网页邀请链接直接指定的完整联机地址
var net_test := false
var cli_mode := false   # 命令行直连（--net-host/--net-join），跳过大厅场景
var phase := Phase.LOBBY  # host=当前阶段；client=最近收到的主机阶段
var players := {}   # peer_id(int) -> { "name": String }
var self_name := ""
var self_rank := ""   # 本机昵称（建房/进房前由大厅设置，房间名单显示用）
# 联机大厅准备状态：peer_id -> { "camp":int(0蓝/1红), "lane":String, "ready":bool }
# 阵营确认 + 分路选择后 ready=true；房主必须等所有在线玩家 ready 才能开始选人/开局。
var lobby_ready := {}
var _picks := {}    # host：选人阶段 peer_id -> { "hero":String, "summoner":String, "role":String }
# 顺序选人（host 权威，随大厅状态广播）：{ "step":int, "left":float, "turn":[team,seat], "picks":{ "team-seat":hero } }
# 空字典 = 无顺序（旧端/未启用 → 退化为原来的同时选人）
var draft := {}

var is_headless := false
var _snap_timer := 0.0
var _snap_count := 0
var _last_snap: Array = []
var _last_log_time := 0.0
var _spectate: SpectatePanel = null
var _overlay_layer: CanvasLayer = null

# --- M2：实体 net-id 注册（instance_id ←→ net_id，跨帧稳定） ---
var _net_seq := 0
var _net_ids := {}     # instance_id(int) -> net_id(int)
var _net_by_id := {}   # net_id(int) -> instance_id(int)
var _prune_timer := 0.0

# --- M2：真人接管分配（host only） ---
var _assign_hero := {}      # peer_id -> Hero（该真人操控的英雄）
var _assign_peer := {}      # hero instance_id -> peer_id
var _assign_scan := 0.0
var _manifest := {}         # client：自己接管到的清单
var seat_order: Array = []     # 本局选人席位顺序（host 开局随机，全员广播；1..5 号位不再固定房主优先）
var _drive_time := {}       # host：peer_id -> 最近 C_DRIVE 墙钟秒（超时自动松手，防指令卡死）
var _attack_time := {}      # host：peer_id -> 最近 C_ATTACK_AUTO 墙钟秒（超时自动松开普攻，防卡自动攻击）

# --- M4：静态地图布局（墙/草丛/营地坐标） ---
var _map_payload := {}      # client：收到的 _rpc_map 载荷
var _roster_payload := []   # client：收到的 _rpc_roster 载荷（属性 C / 队伍 T 面板行）
var _prev_alive := {}   # P3e host：pid→上次 alive，死亡跃迁 1→0 时对该 pid 推一次死亡回放
var _result_sent := false   # P3f host：game_over 翻转时已广播结算（新一局重置）
var _map_sent_to := {}      # host：已发过地图的 peer_id

# --- #43 FX（host only）：技能视觉事件环形缓冲 → 快照 fx 段 ---
var _fx_seq := 0             # 每次快照 flush 递增（客户端据此去重）
var _fx_fid := 0             # 每次 push 自增（客户端按 fid 幂等）
var _fx_buf := []            # [fid, kind, x, y, z, team, r, life, born_ms]
var _fx_last_ms := 0         # 本进程 wall 时钟基准（push 时初始化，防 spawn 帧抖动）

# --- #44 数值弹出/经验珠/攻击动作 events（host only）：快照 idx9 尾段，仿 FX 缓冲/去重 ---
# 行序 = [fid, kind, x, y, z, ...kind 专属字段]（变长）；born_ms 单存 [0] 便于按龄剪枝。
var _ev_seq := 0
var _ev_fid := 0
var _ev_buf := []            # [born_ms(int), row(Array)]

# --- M2：headless 客户端脚本化接管驱动（--net-test 用） ---
var _nt := false
var _nt_step := 0
var _nt_wait := 0.0
var _nt_nid := -1
var _nt_start := Vector3.ZERO

# --- 信号（供客户端呈现层 NetClientBattle / 大厅 UI 使用） ---
signal net_takeover(manifest: Dictionary)   # client：收到接管清单
signal net_snapshot(snap: Array)            # client：收到一帧快照
signal net_lobby_state(state: Dictionary)   # 名单/阶段变化（host 本地亦触发，供房间刷新）
signal net_roster(payload: Array)           # client：收到 _rpc_roster（属性/队伍面板行）
signal net_connect_failed(msg: String)      # client：连接主机失败
signal net_disconnected_from_host           # client：与主机断开
signal net_pick_rejected(msg: String)       # guest：选人被主机拒绝（职责被占/队伍满员）
signal net_tower_laser(from: Vector3, to: Vector3, team: int, dur: float)   # client：防御塔激光（细光束+能量球）
signal net_tower_lock(from: Vector3, to: Vector3, team: int, active: bool)     # client：防御塔锁定光束（持续连到当前目标）

# 快照数组布局 v5（主机每帧打包，客户端 _rpc_snapshot 收到后原样存下）：
# [game_time, state, own, heroes, minions, turrets, jungles, bullets, fx, events]
#   own(Dictionary): peer_id -> Dict{name, hp, mana, maxhp, maxmana, level, gold, exp,
#                                  alive(1/0), respawn, cd(Array), levels(Array), summoner_cd,
#                                  sp(未分配技能点), x, z}
#   实体条目（分数组存放）: 末尾都带名字字段供客户端挑模型
#     hero   = [net_id, type=0, team, x, y, z, hp, maxhp, level, display_name]
#     其他    = [net_id, type, team, x, z, hp, maxhp, display_name]  (minion=1, turret=2, jungle=3)
#   子弹段  bullets 每行 = [iid, x, y, z, team, size(旧档 0默认/1英雄塔/2后羿), kind(0弹石/1弹丸×3/2弓箭/3炮弹/4后羿R)]
#          只发「存活的 且 (友方恒显 或 落入我方视野源 18m)」弹体；客户端用两帧采样做视觉插值。
#   FX 段    fx = [seq(int, 递增), [fid, kind, x, y, z, team, r, life], ...]
#          host 一次性事件在缓冲保留 ~0.35s（约 5 帧快照）防 unreliable 丢包；客户端按 fid 去重，
#          按 kind 走本地 catalog 复刻 host 同款基础形（颜色/位置/时长由事件携带、1:1）。
# 只发「存活且（友方恒显 或 该实体可见/暴露中）」；敌方塔按我方视野源距离过滤。
# 静态地图（墙/草丛/营地坐标）另由 _rpc_map 一次性可靠下发（见 _rpc_map）。
const SNAP_TIME := 0
const SNAP_STATE := 1
const SNAP_OWN := 2
const SNAP_HEROES := 3
const SNAP_MINIONS := 4
const SNAP_TURRETS := 5
const SNAP_JUNGLES := 6
const SNAP_BULLETS := 7
const SNAP_FX := 8
const SNAP_EVENTS := 9        # #44 数值弹出/经验珠/攻击动作事件段（host v5 idx9，仿 FX）
const SNAP_SCORE := 10        # 顶部实时战况（击杀比分+经济比分）：{pk,ek,pg,eg}（host 全量统计）
const SNAP_RESPAWN := 11      # 小地图右侧英雄环形头像带行（host _build_respawn_rows 尾段；长度守卫防旧 client）
const SNAP_DEAD_HEROES := 15  # 阵亡英雄尸体行 [nid,team,x,z,yaw,name]，躺尸到复活

# --- #43 FX kind（host push_net_fx / client catalog 共用，值即客户端视觉档） ---
# 1..8 对应 SkillDataBase(SkillApplier) 具名视觉 helper（B 段插桩）；20+ 一次性闪光（C 段）。
const FX_SPELL := 1         # create_spell：团队色扩圈
const FX_PREVIEW := 2       # create_preview：技能落点浅蓝地面圆
const FX_TERRAIN := 3       # create_terrain：地形块/圈（shape_id 后期追平）
const FX_WATER_SPLASH := 4  # _create_water_splash：甄姬水花闪
const FX_WATER_ZONE := 5    # _create_water_zone：甄姬地面水域（persist）
const FX_WATER_PULSE := 6   # _create_water_pulse：甄姬扩散水圈
const FX_LYF_STORM := 7     # _lyf_storm_visual：玉流风暴环
const FX_YL_POOL := 8       # _yuanliu_flow_pool：元流区域池
const FX_HOUYI_EXPLODE := 20  # Bullet.on_hit 后羿R 命中爆炸组（ring+glow+sparks）
const FX_WAVE_RING := 21      # 扩散冲击环（刘禅R 每tick橙色波等 thin ring 一次性扩环）
const FX_XQ_WHIRL := 22       # 小乔2 甜蜜恋风：粉色渐缩旋风柱（~1s，team=-1 固定色）
const FX_MACHAO_SPEAR := 23   # 马超Q/W 落地标枪（10s，团队色枪缨/地面光环）

# --- #44 events kind（host push_net_evt / client catalog 共用） ---
const EV_DMG := 1        # 伤害数字 行=[fid,1,x,y,z,dmg,crit(0/1),magic(0/1)]（crit=金描边放大）
const EV_GOLD := 2       # 金币弹出 行=[fid,2,x,y,z,amount,own(0/1)]（own=接管方英雄所得，画金剑）
const EV_EXP := 3        # 经验珠飞行 行=[fid,3,sx,sy,sz,tx,tz,amount,target_nid]
const EV_ACT := 4        # 攻击动作 行=[fid,4,x,y,z,nid,act,yaw]（act 见 ACT_*）

# ACT_*：EV_ACT 的动作档（host 播什么动作就推什么档，客户端逐档复刻）
const ACT_ATTACK_MELEE := 0    # 普攻近战（左右交替）
const ACT_ATTACK_SHOOT := 1    # 普攻远程射击
const ACT_CAST_SPRINT := 2     # 技能位移冲刺（skill.type==4 → "sprint"）
const ACT_CAST_INTERACT := 3   # 护盾/交互（skill.type==6 → "interact-right"）
const ACT_CAST_MELEE := 4      # 近战英雄施法 → "attack-melee-right"
const ACT_CAST_BOTH_SHOOT := 5 # 双手持械施法 → "holding-both-shoot"
const ACT_CAST_SHOOT := 6      # 单手持械施法 → "holding-right-shoot"
const ACT_DIE := 7             # 死亡

# 指令码（client→host，_rpc_command cmd[0]）
const C_MOVE := 0          # [0, x, z]
const C_ATTACK := 1        # [1, target_net_id]
const C_CAST := 2          # [2, idx, target_net_id(-1=无), tx, tz]
const C_UPGRADE := 3       # [3, skill_slot]
const C_RECALL := 4        # [4]
const C_CANCEL_RECALL := 5 # [5]
const C_BUY := 6           # [6, item_id(String)]
const C_DRIVE := 7         # [7, ax, az, jx, jy, move_mode(-1=默认)] 直驱（零向量=松手恢复 AI/原地）
const C_ATTACK_AUTO := 8   # [8, 1=按住普攻持续自动攻击, 0=松开]（零向量时由主机超时自动松开兜底）
const C_PRIORITY := 9      # [9, 优先级 0=自动/1=推塔/2=小兵]
const C_SUMMONER := 10     # [10, target_net_id(-1=无), tx, tz] 召唤师技能
const C_RECOVER := 11      # [11]
const C_ACTIVE := 12       # [12, active_slot]
const C_SELL := 13         # [13, slot]
const C_INSPECT := 14      # [14, target_net_id]
const C_ROSTER := 15       # [15] 打开属性(C)/队伍(T)面板时请求队伍行（host 立即回 _rpc_roster；0.5s 节流在客户端）
const C_YUANLIU_PICK := 16 # [16, pick名] 元流之子·万物为流切流派（host 校验身处自家泉水后 apply；仅限 元流之子）
const C_SURRENDER := 17     # [17] 发起投降（host 调 UiManager._start_surrender_vote，同单机流程）
const C_RECAP := 18         # [18] 客户端死亡后主动请求死亡回放（host 立即回 _rpc_death_recap）
const C_RESYNC := 19        # [19] 客户端进入战场后请求补发地图/接管/首帧快照（防 Web 端首包丢失黑屏）


func _ready() -> void:
	is_headless = DisplayServer.get_name() == "headless"
	_parse_args()
	if mode != Mode.NONE:
		_setup_peer()


# ---------- 参数解析 ----------

func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--net-host":
			mode = Mode.HOST
			cli_mode = true
			phase = Phase.BATTLE
			if i + 1 < args.size() and args[i + 1].is_valid_int():
				host_port = args[i + 1].to_int()
				i += 1
		elif a == "--net-join":
			mode = Mode.CLIENT
			cli_mode = true
			if i + 1 < args.size() and ":" in args[i + 1]:
				var parts: PackedStringArray = args[i + 1].split(":")
				join_address = parts[0]
				if parts[1].is_valid_int():
					host_port = parts[1].to_int()
				i += 1
		elif a == "--net-test":
			net_test = true
		i += 1


# ---------- 连接建立 ----------

func _setup_peer() -> void:
	var is_web := OS.has_feature("web")
	match mode:
		Mode.HOST:
			if is_web:
				# 浏览器内无法监听端口：网页版只能当客户端，房间由桌面/原生主机开
				printerr("[Net] 网页版不支持创建房间，请用桌面/手机原生版当主机")
				mode = Mode.NONE
				return
			# 统一用 WebSocket 主机：桌面/手机原生开 WS 服务，网页/iOS 浏览器客户端也能直接连
			var peer := WebSocketMultiplayerPeer.new()
			# 大包（静态地图布局 ~72KB：765 段墙）必须抬缓冲，默认 64KB 会整包丢弃 → 客户端看不到墙/草丛
			peer.inbound_buffer_size = 8 * 1024 * 1024
			peer.outbound_buffer_size = 8 * 1024 * 1024
			var err := peer.create_server(host_port)
			if err != OK:
				printerr("[Net] 主机创建失败(WS) err=", err)
				mode = Mode.NONE
				return
			multiplayer.multiplayer_peer = peer
			players[1] = { "name": _self_display_name() if _self_display_name() != "" else ("主机" if cli_mode else "房主"), "rank": self_rank }
			lobby_ready[1] = { "camp": 0, "lane": "", "ready": false }
			multiplayer.peer_connected.connect(_on_peer_connected)
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
			print("[Net] HOST(WS) 端口=", host_port, " 等待玩家加入…")
		Mode.CLIENT:
			# 统一 WebSocket 客户端：网页/原生都连 ws://host:port（网页版地址可用 ?host=ip:port 覆盖）
			var ws := WebSocketMultiplayerPeer.new()
			ws.inbound_buffer_size = 8 * 1024 * 1024
			ws.outbound_buffer_size = 8 * 1024 * 1024
			var err := ws.create_client(_web_ws_url())
			if err != OK:
				printerr("[Net] 客户端创建失败(WS) err=", err)
				mode = Mode.NONE
				return
			multiplayer.multiplayer_peer = ws
			multiplayer.connected_to_server.connect(_on_connected_to_server)
			multiplayer.connection_failed.connect(_on_connection_failed)
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
			print("[Net] CLIENT(WS) 连接 ", join_address, ":", host_port, " …")
			_ensure_overlay()
		_:
			return

# 联机地址：ws://host:port；Web 版可用页面 URL 参数 ?host=ip:port 覆盖
func set_web_server_url(url: String) -> void:
	web_server_url = url.strip_edges()


func _web_ws_url() -> String:
	# 邀请链接 ?server=wss://xxx.trycloudflare.com：直接使用完整地址，不再拼 host:port。
	if web_server_url != "":
		return web_server_url
	var addr := join_address.strip_edges()
	# 容错：用户可能把 ws:// / wss:// / http:// / https:// 一起粘进来
	var explicit_scheme := ""
	for pre in ["ws://", "wss://", "http://", "https://"]:
		if addr.begins_with(pre):
			explicit_scheme = pre.trim_suffix("://")
			addr = addr.substr(pre.length())
			break
	if addr.ends_with("/"):
		addr = addr.substr(0, addr.length() - 1)
	var port := host_port
	# 支持在主机框直接填 host:port
	if addr.count(":") == 1 and not addr.begins_with("["):
		var hp_parts := addr.split(":", false, 1)
		if hp_parts.size() == 2 and hp_parts[1].is_valid_int():
			addr = hp_parts[0]
			port = hp_parts[1].to_int()
	if explicit_scheme == "http":
		explicit_scheme = "ws"
	elif explicit_scheme == "https":
		explicit_scheme = "wss"
	var scheme := explicit_scheme
	if OS.has_feature("web"):
		var proto := str(JavaScriptBridge.eval("window.location.protocol", true))
		# 网页通过 HTTPS 打开时浏览器会拦截 ws://（mixed content），必须走 wss://。
		if scheme == "":
			scheme = "wss" if proto.begins_with("https") else "ws"
		elif proto.begins_with("https") and scheme == "ws":
			scheme = "wss"
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		var m := RegEx.create_from_string("[?&]host=([^&]+)").search(q)
		if m != null:
			var hp: String = m.get_string(1).uri_decode()
			if hp.contains(":"):
				addr = hp.get_slice(":", 0)
				port = int(hp.get_slice(":", 1))
			else:
				addr = hp
	elif scheme == "":
		scheme = "ws"
	return "%s://%s:%d" % [scheme, addr, port]


func _on_peer_connected(id: int) -> void:
	players[id] = { "name": "玩家%d" % id, "rank": "" }
	lobby_ready[id] = { "camp": 0, "lane": "", "ready": false }
	print("[Net] 玩家上线 peer=", id, " 在线=", players.size())
	_broadcast_lobby_state()
	_update_overlay()


func _on_peer_disconnected(id: int) -> void:
	if not players.has(id):
		return
	players.erase(id)
	lobby_ready.erase(id)
	if mode == Mode.CLIENT and id == 1:
		print("[Net] 与主机断开连接")
		_clear_overlay()
		net_disconnected_from_host.emit()
	elif mode == Mode.HOST:
		_release_peer(id)
		_picks.erase(id)   # 掉线释放其占用的职责位，旁观看台顺位补上
		print("[Net] 玩家掉线 peer=", id, " 在线=", players.size())
		_broadcast_lobby_state()
		_update_overlay()


func _on_connected_to_server() -> void:
	print("[Net] 已连上主机")
	var nm := _self_display_name()
	if nm != "":
		_rpc_register_name.rpc_id(1, nm, self_rank)
	_update_overlay()


## 本机昵称：大厅进入房间前设置；没设置时回退到全局昵称存储
func set_self_name(nm: String) -> void:
	self_name = nm.strip_edges()


func set_self_rank(rank: String) -> void:
	self_rank = rank.strip_edges()


func _self_display_name() -> String:
	if self_name != "":
		return self_name
	return NameStore.player_name().strip_edges()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_register_name(nm: String, rank: String = "") -> void:
	if mode != Mode.HOST:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid):
		return
	var clean := nm.strip_edges().substr(0, 16)
	if clean == "":
		return
	players[pid]["name"] = clean
	players[pid]["rank"] = rank.strip_edges().substr(0, 32)
	print("[Net] 玩家昵称 peer=", pid, " → ", clean, " 段位=", players[pid]["rank"])
	_broadcast_lobby_state()


func _on_connection_failed() -> void:
	print("[Net] 连接失败")
	mode = Mode.NONE
	phase = Phase.LOBBY
	_clear_overlay()
	net_connect_failed.emit("无法连接到主机（地址/端口有误或对方未建房）")


# ---------- 大厅：名单/阶段广播（host→all；host 本地也 emit 供房间 UI 刷新） ----------

func _broadcast_lobby_state() -> void:
	if mode != Mode.HOST:
		return
	var state := { "phase": phase, "players": players.duplicate(true), "picks": _picks.duplicate(true),
		"draft": draft.duplicate(true), "ready": lobby_ready.duplicate(true),
		"order": seat_order.duplicate() }
	if multiplayer == null or multiplayer.multiplayer_peer == null:
		net_lobby_state.emit(state)   # 无连接（单机探针/离线）时只本地 emit
		return
	rpc("_rpc_lobby_state", state)
	net_lobby_state.emit(state)


# 联机大厅准备：本机确认阵营/分路后上报房主；房主统一广播给所有人。
func set_lobby_ready(camp: int, lane: String, ready: bool) -> void:
	if mode == Mode.HOST:
		_apply_lobby_ready(1, camp, lane, ready)
		_broadcast_lobby_state()
	elif mode == Mode.CLIENT:
		rpc_id(1, "_rpc_lobby_ready", camp, lane, ready)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_lobby_ready(camp: int, lane: String, ready: bool) -> void:
	if mode != Mode.HOST:
		return
	var pid := multiplayer.get_remote_sender_id()
	if not players.has(pid):
		return
	_apply_lobby_ready(pid, camp, lane, ready)
	_broadcast_lobby_state()


func _apply_lobby_ready(pid: int, camp: int, lane: String, ready: bool) -> void:
	var lane_clean := str(lane).strip_edges()
	var camp_v := clampi(camp, 0, 1)
	if int(pid) == 1:
		camp_v = TEAM_PLAYER   # 房主固定蓝方（host 模拟端 Bm.hero/镜头/基地按蓝方）
	lobby_ready[pid] = {
		"camp": camp_v,
		"lane": lane_clean,
		"ready": bool(ready) and lane_clean != "",
	}
	# 红方真人不再自动配英雄：和蓝方一样进入选人页手动选英雄/召唤师并锁定。


## 该 peer 的阵营（房主固定蓝方）
## 是否 PvP 局（有真人选红方）：快照改为全单位下发，双方各自能操控/看到单位
func is_pvp() -> bool:
	for pid in lobby_ready:
		var r = lobby_ready[pid]
		if r is Dictionary and int((r as Dictionary).get("camp", 0)) == 1:
			return true
	return false


func _peer_camp(pid: int) -> int:
	if int(pid) == 1:
		return TEAM_PLAYER
	var r = lobby_ready.get(int(pid), {})
	if r is Dictionary:
		return clampi(int((r as Dictionary).get("camp", TEAM_PLAYER)), 0, 1)
	return TEAM_PLAYER


## 某阵营的真人席位序列（最多 5 人）；顺序沿用本局随机 seat_order。
func camp_peers(camp: int) -> Array:
	var out: Array = []
	for p in get_seat_order():
		if int(p) == 0:
			continue
		if _peer_camp(int(p)) == int(camp) and not out.has(int(p)):
			out.append(int(p))
	return out.slice(0, MAX_SIDE_PLAYERS)


## peer 在本阵营内的 0-based 席位；-1=本阵营已满/旁观。
func camp_seat_of(pid: int) -> int:
	var arr: Array = camp_peers(_peer_camp(int(pid)))
	var i := arr.find(int(pid))
	return i


## 红方真人按分路自动选一个未被占用的英雄（无需手动 BP）
func _autofill_red_peer(pid: int, lane: String) -> void:
	if mode != Mode.HOST or pid == 1 or _picks.has(pid):
		return
	var role := str(HeroPickData.lane_role(lane))
	var used := {}
	for q in _picks:
		used[str(_picks[q].get("hero", ""))] = true
	var dp = draft.get("picks", {})
	if dp is Dictionary:
		for k in dp:
			if str(k).begins_with("1-"):
				used[str((dp as Dictionary)[k])] = true
	var pick := ""
	for hero in HeroPickData.HERO_ROLE:
		if str(HeroPickData.HERO_ROLE[hero]) == role and not used.has(str(hero)):
			pick = str(hero)
			break
	if pick == "":
		for hero2 in HeroPickData.HERO_ROLE:
			if not used.has(str(hero2)):
				pick = str(hero2)
				break
	if pick == "":
		return
	_picks[pid] = {"hero": pick, "summoner": "flash",
		"role": str(HeroPickData.HERO_ROLE.get(pick, "")), "team": 1, "skin": ""}
	print("[Net] 红方真人自动配英雄 peer=", pid, " hero=", pick, " lane=", lane)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_lobby_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return  # 主机不执行自己的 rpc；以本地 emit 为准
	players.clear()
	for id in state.get("players", {}):
		players[int(id)] = state["players"][id]
	phase = int(state.get("phase", Phase.LOBBY))
	draft = state.get("draft", {})   # 旧端无此字段 → 空字典（退化同时选人）
	var od = state.get("order", [])
	if od is Array:
		seat_order.clear()
		for oid in od:
			seat_order.append(int(oid))
	lobby_ready.clear()
	var rd = state.get("ready", {})
	if rd is Dictionary:
		for id in rd:
			if rd[id] is Dictionary:
				lobby_ready[int(id)] = rd[id].duplicate(true)
	print("[Net] 大厅状态 phase=%d 在线=%d" % [phase, players.size()])
	_update_overlay()
	net_lobby_state.emit(state)


# ---------- 选人阶段 RPC（guest→host 上报选人；host→guest 拒绝回执） ----------

@rpc("any_peer", "reliable", "call_remote")
func _rpc_set_pick(hero: String, summoner: String, skin: String = "") -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not _apply_pick(pid, hero, summoner, skin):
		var msg := "该职责已被他人选择，或本方席位已满"
		if not draft.is_empty() and not _draft_is_turn_of(pid):
			msg = "还没轮到你选人，请等待当前席位"
		rpc_id(pid, "_rpc_pick_rejected", msg)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_pick_rejected(msg: String) -> void:
	if multiplayer.is_server():
		return
	net_pick_rejected.emit(msg)


# ---------- 大厅公开接口（大厅 UI 调用） ----------

func host_game(port: int = 7000) -> bool:
	if mode != Mode.NONE:
		return false
	web_server_url = ""
	host_port = port
	phase = Phase.LOBBY
	seat_order.clear()
	mode = Mode.HOST
	_setup_peer()
	return multiplayer != null and multiplayer.multiplayer_peer != null


func join_game(address: String, port: int = 7000) -> bool:
	if mode != Mode.NONE:
		return false
	join_address = address
	host_port = port
	phase = Phase.LOBBY
	seat_order.clear()
	mode = Mode.CLIENT
	_setup_peer()
	return multiplayer != null and multiplayer.multiplayer_peer != null


func begin_pick() -> void:
	if mode != Mode.HOST or phase != Phase.LOBBY:
		return
	# 选人位次随机：房主不再固定 1 号位，全员按同一随机顺序占 1..N 号位（先选/后选也随席位）
	var all_ids: Array = [1]
	for p in players:
		if not all_ids.has(int(p)):
			all_ids.append(int(p))
	all_ids.shuffle()
	seat_order = all_ids
	phase = Phase.SELECT
	draft.clear()   # 顺序由大厅按需重新下发
	_broadcast_lobby_state()
	print("[Net] 进入选人阶段：全员选英雄+召唤师，锁齐后可开局")


# ---------- 顺序选人（host 权威；无 draft 时旧流程不变） ----------

# host：更新并广播顺序选人状态（step/left/turn/picks 由 NetLobby 计算）
func set_draft(d: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	draft = d.duplicate(true)
	_broadcast_lobby_state()


func get_draft() -> Dictionary:
	return draft.duplicate(true)


func draft_active() -> bool:
	return not draft.is_empty()


# 顺序选人结果按阵营/席位排出：{ ally: [seat0..4 英雄], enemy: [seat0..4 英雄] }
# 开局阵容按它生成，避免「展示的 BP 阵容」和实际 AI 阵容不一致
func get_draft_teams() -> Dictionary:
	var picks: Dictionary = draft.get("picks", {})
	var ally: Array = []
	var enemy: Array = []
	for i in 5:
		ally.append(str(picks.get("0-%d" % i, "")))
		enemy.append(str(picks.get("1-%d" % i, "")))
	return {"ally": ally, "enemy": enemy}


# host：代某位玩家锁定（超时兜底用；与 guest 自己上报走同一套校验）
func host_force_pick(pid: int, hero: String, summoner: String = "flash") -> bool:
	if mode != Mode.HOST:
		return false
	return _apply_pick(pid, hero, summoner)


# 该 peer 是否正处在自己的顺序选人回合（host 判定/拒绝提示用）
func _draft_is_turn_of(pid: int) -> bool:
	var turn: Array = draft.get("turn", [])
	if turn.size() < 2:
		return false
	if int(turn[0]) != _peer_camp(int(pid)):
		return false
	return int(turn[1]) == camp_seat_of(int(pid))


# 顺序选人合法性：本回合玩家才可上报；展示阵容里的英雄/职责不重复
func _draft_allows(pid: int, hero: String) -> bool:
	if draft.is_empty():
		return true
	if int(draft.get("step", 0)) >= 10:
		return not _picks.has(pid)   # 顺序已结束：只允许补未锁席位，不允许改选
	var turn: Array = draft.get("turn", [])
	if turn.size() < 2:
		return true
	if int(turn[0]) != _peer_camp(int(pid)) or int(turn[1]) != camp_seat_of(int(pid)):
		return false   # 不是本阵营本席位回合
	var role := str(HeroPickData.HERO_ROLE.get(hero, ""))
	var dp: Dictionary = draft.get("picks", {})
	var prefix := "%d-" % _peer_camp(int(pid))
	for k in dp:
		if str(dp[k]) == hero:
			return false   # 展示阵容已占该英雄（全局唯一）
		if str(k).begins_with(prefix) and str(HeroPickData.HERO_ROLE.get(str(dp[k]), "")) == role:
			return false   # 同阵营已有该职责
	return true


func start_match() -> void:
	if mode != Mode.HOST:
		return
	if not _all_active_picked():
		printerr("[Net] 尚未全员锁齐，拒绝开局")
		return
	phase = Phase.BATTLE
	_broadcast_lobby_state()


func has_picks() -> bool:
	return not _picks.is_empty()


func get_picks() -> Dictionary:
	return _picks.duplicate(true)


func active_player_ids() -> Array:
	# 蓝方至多 5 名真人，其余连接列为旁观；位次用 host 随机顺序，避免房主固定 1 号
	if not seat_order.is_empty():
		return seat_order.slice(0, MAX_SIDE_PLAYERS)
	var ids: Array = [1]
	for p in players:
		ids.append(int(p))
	ids.sort()
	return ids.slice(0, MAX_SIDE_PLAYERS)


## 本局席位顺序（含旁观）：host 随机顺序；旧端/未开局回退排序
func get_seat_order() -> Array:
	if not seat_order.is_empty():
		return seat_order.duplicate()
	var ids: Array = [1]
	for p in players:
		if not ids.has(int(p)):
			ids.append(int(p))
	ids.sort()
	return ids


func _all_active_picked() -> bool:
	for pid in players:
		var p := int(pid)
		if p == 1:
			if not _picks.has(p):
				return false
			continue
		if camp_seat_of(p) >= 0 and not _picks.has(p):
			return false
	return true


func send_pick(hero: String, summoner: String, skin: String = "") -> bool:
	# host 本地选人直接落地；guest 走 rpc（返回 true 表示已发出，最终以主机广播为准）
	if mode == Mode.CLIENT:
		rpc("_rpc_set_pick", hero, summoner, skin)
		return true
	return _apply_pick(1, hero, summoner, skin)


func _apply_pick(pid: int, hero: String, summoner: String, skin: String = "") -> bool:
	if mode != Mode.HOST:
		return false
	if not HeroPickData.HERO_ROLE.has(hero):
		printerr("[Net] 选人拒绝：目录外英雄 hero=", hero)
		return false
	var role: String = HeroPickData.HERO_ROLE[hero]
	# 房间确认的分路是硬约束：host/客户端都不能绕过 UI 选其它职责
	var ready_row = lobby_ready.get(int(pid), {})
	var confirmed_lane := str((ready_row as Dictionary).get("lane", "")) if ready_row is Dictionary else ""
	if confirmed_lane != "" and role != HeroPickData.lane_role(confirmed_lane):
		printerr("[Net] 选人拒绝：分路不符 lane=", confirmed_lane, " hero=", hero)
		return false
	if not HeroPickData.SUMMONERS.values().has(summoner):
		summoner = "flash"
	if pid != 1 and not players.has(pid):
		return false
	if camp_seat_of(pid) < 0:
		printerr("[Net] 选人拒绝：本方席位已满 peer=", pid)
		return false
	# 一人一职按阵营内去重（蓝/红双方各自阵容可同职责）
	var my_team := _peer_camp(pid)
	for q in _picks:
		if int(q) == pid:
			continue
		if int(_picks[q].get("team", TEAM_PLAYER)) != my_team:
			continue
		if str(_picks[q].get("role", "")) == role:
			return false
	# 顺序选人：只允许本回合玩家上报，且不与展示阵容冲突
	if not _draft_allows(pid, hero):
		return false
	_picks[pid] = { "hero": hero, "summoner": summoner, "role": role, "team": my_team, "skin": skin }
	print("[Net] 选人锁定 peer=", pid, " hero=", hero, " role=", role)
	_broadcast_lobby_state()
	return true


func clear_pick(pid: int) -> void:
	if _picks.erase(pid):
		_broadcast_lobby_state()


func assign_lineup() -> void:
	# host：开局后把选人阶段已锁的 guest 英雄按 display_name 逐一分给对应 peer（复用接管流程）；
	# host 自己(pid=1)的 bm.hero 在本地操控，不入此表。
	if mode != Mode.HOST:
		return
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	for pid in _picks:
		var pidn := int(pid)
		if pidn == 1 or _assign_hero.has(pidn):
			continue
		var want: String = str(_picks[pid].get("hero", ""))
		if want.is_empty():
			continue
		var camp := _peer_camp(pidn)
		for e in get_tree().get_nodes_in_group("heroes"):
			if not is_instance_valid(e) or e is not Hero:
				continue
			var h: Hero = e
			if int(h.team) != camp or h.display_name != want:
				continue
			if _assign_peer.has(h.get_instance_id()):
				continue
			_assign_hero_to(pidn, h)
			print("[Net] 开局分配 peer=", pidn, " hero=", want)
			break


func disconnect_network() -> void:
	web_server_url = ""
	if mode == Mode.NONE:
		return
	mode = Mode.NONE
	phase = Phase.LOBBY
	cli_mode = false
	players.clear()
	lobby_ready.clear()
	_picks.clear()
	draft.clear()
	seat_order.clear()
	_manifest = {}
	_assign_hero.clear()
	_assign_peer.clear()
	_map_payload = {}
	_map_sent_to = {}
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_clear_overlay()
	print("[Net] 已断开网络")


func current_phase() -> int:
	return phase


# ---------- net-id 注册表 ----------

func _net_id_for(e: Node) -> int:
	var iid := e.get_instance_id()
	var nid: int = _net_ids.get(iid, -1)
	if nid < 0:
		_net_seq += 1
		nid = _net_seq
		_net_ids[iid] = nid
		_net_by_id[nid] = iid
	return nid


func _entity_by_net(nid: int) -> Node:
	var iid: int = _net_by_id.get(nid, 0)
	if iid == 0:
		return null
	var obj = instance_from_id(iid)
	if obj == null:
		return null
	return obj


func _prune_net_ids() -> void:
	for iid in _net_ids.keys():
		if not is_instance_id_valid(iid):
			var nid: int = _net_ids[iid]
			_net_ids.erase(iid)
			_net_by_id.erase(nid)


# ---------- M2-1：真人接管分配（host） ----------

func _has_ai_child(h: Node) -> bool:
	for c in h.get_children():
		if c is HeroAI:
			return true
	return false


func _scan_assignments() -> void:
	var pending: Array = []
	for pid in players:
		if pid == 1:
			continue
		if not _assign_hero.has(pid):
			pending.append(pid)
	if pending.is_empty():
		return
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	if bm.get("hero_selected") == null or not bool(bm.get("hero_selected")):
		return  # 对局未开始
	# 空闲（仍挂着 HeroAI）的同队 AI 英雄
	var taken := {}
	for pid in _assign_hero:
		taken[_assign_hero[pid]] = true
	var free_by_team := {0: [], 1: []}
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or e is not Hero:
			continue
		var h: Hero = e
		if not h.is_ai or h.health <= 0 or taken.has(h) or not _has_ai_child(h):
			continue
		var tm := clampi(int(h.team), 0, 1)
		free_by_team[tm].append(h)
	for pid in pending:
		var camp := _peer_camp(int(pid))
		if (free_by_team[camp] as Array).is_empty():
			continue
		var h2: Hero = (free_by_team[camp] as Array).pop_front()
		if h2 != null:
			_assign_hero_to(int(pid), h2)


func _assign_hero_to(pid: int, h: Hero) -> void:
	# 卸掉 AI 控制器；英雄保持 is_ai=true（移动/攻击由 Hero._physics_process 依据
	# move_target/manual_target/_start_casting 原语驱动，跟 AI 时期同路径）。
	for c in h.get_children():
		if c is HeroAI:
			c.queue_free()
			break
	# 接管 = 真人操控：置 net_taken 禁普攻自动追击；并清掉 AI 残留的追击/走位目标，
	# 避免真人刚接管还被旧 AI 目标带着走（客户端 _on_takeover 只复位本地发送状态，管不到模拟侧残留）
	h.net_taken = true
	h.manual_target = null
	h.move_target = Vector3.ZERO
	_assign_hero[pid] = h
	_assign_peer[h.get_instance_id()] = pid
	var nid := _net_id_for(h)
	var m := _build_manifest(pid, h, nid)
	rpc_id(pid, "_rpc_takeover", m)
	print("[Net] 玩家接管 peer=", pid, " hero=", h.display_name, " net_id=", nid)
	_update_overlay()


# 从 SkillDatabase 反查 Skill 资源对应的 id（manifest 里要让客户端画出同款技能图标）
func _skill_id_of(sk: Skill) -> String:
	if sk == null:
		return ""
	for sid in SkillDatabase.skills:
		var base: Skill = SkillDatabase.skills[sid]
		if base == null:
			continue
		if base == sk:
			return str(sid)
		# Hero 使用的是 SkillDatabase 的 duplicate()，不是同一个对象；按技能名+类型匹配回 id
		if str(base.skill_name) == str(sk.skill_name) and int(base.type) == int(sk.type):
			return str(sid)
	return ""


func _build_manifest(pid: int, h: Hero, nid: int) -> Dictionary:
	var sk: Array = []
	for i in range(h.skills.size()):
		var s = h.skills[i]
		if s == null:
			# 保留空槽位：客户端用 skills[3] 判断是否真的有第 4 技能，
			# 不能把后面的恢复技能前移成第 4 格，否则所有英雄都会亮出 4 技能按钮。
			sk.append(null)
			continue
		sk.append({
			"sid": _skill_id_of(s),   # 技能 id：客户端第 4 技能按钮要用它取 SkillDatabase 里的图标纹样
			"name": s.skill_name, "type": s.type, "cd": s.cooldown, "mana": s.mana_cost,
			"cdb": s.cd_bonus, "pw": s.power_bonus, "rad": s.radius,
			"range": s.cast_range, "dis": s.self_displacement, "shield": s.shield_amount,
			"dur": s.duration, "restore": s.restore,
			"br": (s.bullet_range if "bullet_range" in s and s.bullet_range != null else 0.0),
				# 线性技能弹体最远飞行距离（客户端 type3 施法预览箭头长度用；宿主 Hero 同字段）
		})
	var m := {
		"peer": pid, "net_id": nid, "hero_name": h.display_name, "role": h.role,
		"team": h.team, "skills": sk, "summoner": "",
		# 客户端普攻拖拽选敌的距离门：与 Hero._aa_engage_reach() 同义（普攻锁定上限≈射程+1）
		"reach": h.attack_range * 0.01,
	}
	if h.summoner_skill != null:
		m["summoner"] = h.summoner_skill.skill_name
	return m


func _release_peer(pid: int) -> void:
	if not _assign_hero.has(pid):
		return
	var h = _assign_hero[pid]
	_assign_hero.erase(pid)
	if is_instance_valid(h):
		_assign_peer.erase(h.get_instance_id())
		# 清掉接管残留的直驱/普攻/优先级，避免英雄带着旧输入卡死或自攻
		h.net_axis = Vector3.ZERO
		h.net_joy = Vector2.ZERO
		h.net_move_mode = -1
		h.net_attack_hold = false
		h.net_attack_priority = -1
		h.net_taken = false   # 释放接管：恢复 AI 语义（若日后重挂 HeroAI 会按 bot 规则追击）
	_drive_time.erase(pid)
	_attack_time.erase(pid)
	# 真人掉线：英雄先保持原地待命（后续可换 AI/交给下一位玩家接管）


# ---------- RPC：接管清单（client 收） ----------

@rpc("any_peer", "reliable", "call_remote")
func _rpc_takeover(manifest: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_manifest = manifest
	_nt_nid = int(manifest.get("net_id", -1))
	print("[Net] 接管成功 hero=", manifest.get("hero_name"), " net_id=", _nt_nid)
	_update_overlay()
	net_takeover.emit(manifest)
	# headless CI 客户端：开始脚本化接管驱动
	if is_headless and net_test and not _nt:
		_nt = true
		_nt_step = 0
		_nt_wait = 0.0
		print("[NetTest] driver-start hero=", manifest.get("hero_name"))


# ---------- RPC：意图指令（client→host） ----------

func request_battle_resync() -> void:
	if mode == Mode.CLIENT:
		send_command([C_RESYNC])


func send_command(cmd: Array) -> void:
	if mode == Mode.CLIENT:
		rpc("_rpc_command", cmd)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_command(cmd: Array) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	if not cmd.is_empty() and int(cmd[0]) == C_RESYNC:
		_resync_peer(pid)
		return
	if not _assign_hero.has(pid):
		printerr("[Net] 拒绝未分配玩家指令 from peer=", pid)
		return
	_apply_command(_assign_hero[pid], cmd, pid)


func _can_control(h: Hero) -> bool:
	if not is_instance_valid(h) or h.health <= 0 or h.is_dead:
		return false
	if h.stun_timer > 0.0 or h.knockup_timer > 0.0 or h.suppress_timer > 0.0 \
			or h.silence_timer > 0.0 or h.froze_timer > 0.0:
		return false
	return true


func _cancel_recall_if_needed(h: Hero) -> void:
	if h.is_recalling:
		h.cancel_recall()


# 主动装备列表（≤2，与主机触控「装1/装2」同入口）：[[id, name, max_cd, cd_remaining], …]
func _active_equips(h: Hero) -> Array:
	var ae: Array = []
	var list: Array = UiManager._get_active_equip_list(h)
	for i in range(mini(list.size(), 2)):
		var a: Dictionary = list[i]
		ae.append([str(a.get("id", "")), str(a.get("name", "")),
			float(a.get("max_cd", 0.0)), float(a.get("cd_remaining", 0.0))])
	return ae


func _apply_drive(h: Hero, cmd: Array, pid: int) -> void:
	# 直驱：客户端摇杆/键盘逐帧输入的旁路，独立于操控守卫（被控/死亡期间的松手清零也要落盘，
	# 否则一次抖动丢包就会留下恒久输入把英雄卡死在跑向旧方向）
	h.net_axis = Vector3(float(cmd[1]), 0.0, float(cmd[2]))
	h.net_joy = Vector2(float(cmd[3]), float(cmd[4]))
	h.net_move_mode = int(cmd[5]) if cmd.size() > 5 else -1
	_drive_time[pid] = Time.get_ticks_msec() * 0.001
	var driving := h.net_axis.length_squared() > 0.0001 or h.net_joy.length_squared() > 0.0001
	if driving and is_instance_valid(h) and not h.is_dead:
		if h.is_recalling:
			h.cancel_recall()
		# 抬手按住即放弃寻路目标：与主机按住摇杆/按键手感一致，松手不会莫名其妙折返
		h.move_target = Vector3.ZERO


func _apply_command(h: Hero, cmd: Array, pid: int) -> void:
	if cmd[0] == C_DRIVE:
		_apply_drive(h, cmd, pid)
		return
	# 普攻按住/优先级是状态写入：即使英雄被控/死亡期间的松手也要落盘，
	# 且按住要持续刷新（见 _process_host 超时兜底）。二者不进操控守卫。
	if cmd[0] == C_ATTACK_AUTO:
		h.net_attack_hold = int(cmd[1]) == 1
		_attack_time[pid] = Time.get_ticks_msec() * 0.001
		if h.net_attack_hold and is_instance_valid(h) and not h.is_dead:
			_cancel_recall_if_needed(h)
		return
	if cmd[0] == C_PRIORITY:
		var p := int(cmd[1])
		h.net_attack_priority = clamp(p, 0, 2)
		# 切换模式清旧锁定；与单机 _handle_attack_priority_input 的落点一致
		h.manual_target = null
		return
	if cmd[0] == C_ROSTER:
		# 属性(C)/队伍(T)面板数据：不要求可操控（观战/刚接管均可），host 立即回传
		rpc_id(pid, "_rpc_roster", _build_roster_payload(_peer_camp(pid)))
	elif cmd[0] == C_RECAP:
		# 死亡回放补发：客户端死亡时主动要一次，避免只有 1→0 跃迁帧的 RPC/快照丢失
		if _assign_hero.has(pid):
			var hh: Hero = _assign_hero[pid]
			if hh != null and is_instance_valid(hh):
				rpc_id(pid, "_rpc_death_recap", _pack_death_recap(hh))
		return
	if cmd[0] == C_YUANLIU_PICK:
		# 元流之子·万物为流切流派：host 权威校验——须身处自家泉水（回复判定同款半径）+ 合法流派名
		var pk := str(cmd[1])
		if h.display_name == "元流之子" and h.in_own_fountain() \
				and (pk == "生机" or pk == "穿心" or pk == "迅疾" or pk == "凝神"):
			h.set_yuanliu_pick(pk)
			print("[Net] 指令 流派切换->", pk, " from ", pid)
		else:
			printerr("[Net] 流派切换拒绝（非元流/非法流派/不在自家泉水） pick=", pk)
		return
	if not _can_control(h):
		printerr("[Net] 指令拒绝（不能操控）from peer=", pid, " cmd=", cmd[0])
		return
	match cmd[0]:
		C_MOVE:
			_cancel_recall_if_needed(h)
			h.manual_target = null
			h.move_target = Vector3(float(cmd[1]), 0.0, float(cmd[2]))
			print("[Net] 指令 move_to from ", pid)
		C_ATTACK:
			if int(cmd[1]) == -1:
				# 空放普攻：客户端没有可打目标时点按普攻 → host 播放动画/发子弹/亮范围圈
				if not is_instance_valid(h) or h.is_dead:
					return
				_cancel_recall_if_needed(h)
				h.move_target = Vector3.ZERO
				h.call("_empty_attack")
				h.attack_timer = 1.0 / maxf(h.attack_speed, 0.1)
				return
			var t = _entity_by_net(int(cmd[1]))
			if t == null or not is_instance_valid(t) or not (t is GameEntity):
				printerr("[Net] 攻击目标无效 net_id=", cmd[1])
				return
			if t.health <= 0 or (t.team == h.team):
				printerr("[Net] 攻击目标不可攻击 team=", t.team)
				return
			_cancel_recall_if_needed(h)
			h.move_target = Vector3.ZERO
			h.set_manual_target(t)
			print("[Net] 指令 attack -> ", str(t.name))
		C_CAST:
			# 布局 [2, idx, target_net_id(-1=无), tx, tz]（与 send_command 调用方一致）
			var idx := int(cmd[1])
			if idx == 3:
				# 第4技能按钮（兰陵王·隐身）：点按即施放、无瞄准方向 —— 与主机触控第4按钮同一入口
				if h.display_name == "兰陵王":
					if h._try_cast_lanling_stealth():
						print("[Net] 指令 cast4 隐身 from ", pid)
					else:
						printerr("[Net] 隐身施放失败（冷却中或前置不满足）")
				else:
					printerr("[Net] 技能索引无效 idx=", idx)
				return
			if idx < 0 or idx >= h.skills.size() or h.skills[idx] == null:
				printerr("[Net] 技能索引无效 idx=", idx)
				return
			if h.casting_skill or h.channeling_skill_index >= 0 or h.is_recalling or h.is_teleporting:
				printerr("[Net] 施法被占（casting/channel/recall/teleport）")
				return
			var sk = h.skills[idx]
			if h.skill_cooldowns[idx] > 0.0:
				printerr("[Net] 冷却中 cd=", h.skill_cooldowns[idx])
				return
			var cost: float = float(sk.mana_cost) - float(sk.power_bonus) * maxi(h.skill_levels[idx] - 1, 0)
			if h.mana < cost:
				printerr("[Net] 蓝量不足 mana=", h.mana, " need=", cost)
				return
			var tp := Vector3(float(cmd[3]), 0.0, float(cmd[4]))
			var target_entity = null
			if int(cmd[2]) >= 0:
				var te = _entity_by_net(int(cmd[2]))
				# 防御塔仅李元芳1技能(槽0)允许锁定，其余目标型技能不可点塔（同主机 _skill_target_allowed）
				if te != null and is_instance_valid(te) and te.health > 0 and te is GameEntity \
						and not (te is Turret and not (h.display_name == "李元芳" and idx == 0)):
					target_entity = te
			_cancel_recall_if_needed(h)
			h._start_casting(idx, sk, tp)
			if target_entity != null:
				h.pending_skill_target_entity = target_entity
			print("[Net] 指令 cast idx=", idx, " from ", pid)
		C_UPGRADE:
			var slot := int(cmd[1])
			var ok: bool = h.upgrade_skill(slot)
			print("[Net] 指令 upgrade slot=", slot, " ok=", ok)
		C_RECALL:
			if not h.is_recalling and not h.is_teleporting:
				h.start_recall()
			print("[Net] 指令 recall")
		C_CANCEL_RECALL:
			if h.is_recalling:
				h.cancel_recall()
			print("[Net] 指令 cancel_recall")
		C_BUY:
			var item_id: String = str(cmd[1])
			var ok2: bool = h.buy_equipment(item_id)
			print("[Net] 指令 buy ", item_id, " ok=", ok2)
		C_SUMMONER:
			# aim_dir=世界方向(x,z)，长度>20 即用于位移类；否则主机内部兜底（移动方向/面朝）
			if h.summoner_skill and h.summoner_cooldown <= 0.0:
				# 客户端已按自己的镜头把拖拽换算成世界方向，主机按世界方向施放（不能再按主机阵营翻转）
				h._use_summoner(Vector2(float(cmd[2]), float(cmd[3])), true)
			print("[Net] 指令 summoner from ", pid)
		C_SURRENDER:
			# 投降：交给 host UI_Manager 的同一套投票流程（6:00 后才能发起）
			UiManager._start_surrender_vote()
			print("[Net] 指令 surrender from ", pid)
		C_RECOVER:
			# 恢复槽固定 index 4（Hero.setup_skills_from_database 追加）；与主机键盘/触控同式
			if h.skill_cooldowns.size() > 4 and h.skill_cooldowns[4] <= 0.0:
				h.skill_cooldowns[4] = 60.0
				h.apply_regen(h.actual_max_health * 0.01, h.actual_mana_max * 0.01, 5.0, "recover_skill")
			print("[Net] 指令 recover from ", pid)
		C_ACTIVE:
			# 与主机触控「装1/装2」同 API；cd 未到/无效索引时 UI 函数内部 no-op
			UiManager._trigger_active_equip(h, int(cmd[1]))
			print("[Net] 指令 active slot=", cmd[1], " from ", pid)
		C_SELL:
			var sid := int(cmd[1])
			if sid >= 0 and sid < h.equipment_slots.size():
				var sid_item: String = str(h.equipment_slots[sid])
				var sit = ItemDatabase.get_item(sid_item)
				if not sit.is_empty():
					var refund := int(float(sit["cost"]) * 0.7)
					h.gold += refund
					h.equipment_slots.remove_at(sid)
					h._apply_equipment_bonuses()
					h._recalculate_attributes()
					print("[Net] 指令 sell slot=", sid, " refund=", refund, " from ", pid)
			else:
				printerr("[Net] 出售槽位无效 slot=", cmd[1])
		_:
			printerr("[Net] 未知指令码 ", cmd[0])


# ---------- M1/M2：主机快照广播 ----------

func _process(delta: float) -> void:
	if mode == Mode.HOST:
		_process_host(delta)
	elif mode == Mode.CLIENT:
		if _nt:
			_nt_drive(delta)


func _process_host(delta: float) -> void:
	_broadcast_map_if_needed()
	# P3f：game_over 翻转（任意方水晶被破）→ 广播结算（全英雄最终数据，无视视野）；新一局 game_over 复位后重发
	if players.size() > 1:
		var _bm := get_tree().get_first_node_in_group("battle_manager")
		if _bm != null:
			if bool(_bm.get("game_over")) and not _result_sent:
				_result_sent = true
				rpc("_rpc_game_over", _build_result_payload(_bm))
				print("[Net] 结算广播 winner=", _bm.get("winner"))
			elif not bool(_bm.get("game_over")) and _result_sent:
				_result_sent = false
	_snap_timer -= delta
	if _snap_timer <= 0.0:
		# 累加而非重设：低帧主机也能逼近配置的 30Hz（重设会被帧率量化成 2 帧一次）
		_snap_timer = maxf(_snap_timer + SNAPSHOT_INTERVAL, 0.0)
		if players.size() > 1:
			var bm := get_tree().get_first_node_in_group("battle_manager")
			if bm != null:
				# 每个客户端按自己的阵营生成一份快照，红方不能复用药方的全局视野。
				# host 自己(peer 1)直接操控战场，不需要收 RPC 快照。
				for pid in players:
					if int(pid) == 1:
						continue
					var snap := _build_snapshot(bm, _peer_camp(int(pid)))
					if not snap.is_empty():
						rpc_id(int(pid), "_rpc_snapshot", snap)
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = 1.0
		_prune_net_ids()
	_assign_scan -= delta
	if _assign_scan <= 0.0:
		_assign_scan = 0.5
		_scan_assignments()
	# 直驱超时保护：0.5s 内没收到新 C_DRIVE 视为断流/松手，清零直驱输入（防英雄卡死在旧方向）
	var now_s := Time.get_ticks_msec() * 0.001
	for pid in _drive_time.keys():
		if now_s - _drive_time[pid] > 0.5:
			if _assign_hero.has(pid) and is_instance_valid(_assign_hero[pid]):
				var hd: Hero = _assign_hero[pid]
				if hd.net_axis != Vector3.ZERO or hd.net_joy != Vector2.ZERO:
					hd.net_axis = Vector3.ZERO
					hd.net_joy = Vector2.ZERO
					print("[Net] 直驱超时松手 pid=", pid)
			_drive_time.erase(pid)
	# 普攻按住超时保护：0.8s 内没收到新 C_ATTACK_AUTO 视为松手/断流，松开自动攻击
	for pid in _attack_time.keys():
		if now_s - _attack_time[pid] > 0.8:
			if _assign_hero.has(pid) and is_instance_valid(_assign_hero[pid]):
				var ha: Hero = _assign_hero[pid]
				if ha.net_attack_hold:
					ha.net_attack_hold = false
					print("[Net] 普攻超时松开 pid=", pid)
			_attack_time.erase(pid)


func _build_snapshot(bm: Node, viewer_team: int = TEAM_PLAYER) -> Array:
	var viewer := clampi(viewer_team, 0, 1)
	var out: Array = []
	var gtime: float = 0.0
	if bm.get("game_time") != null:
		gtime = float(bm.get("game_time"))
	var in_battle := false
	if bm.get("hero_selected") != null:
		in_battle = bool(bm.get("hero_selected"))
	out.append(gtime)
	out.append(1 if in_battle else 0)

	# own 块：每个已接管真人的英雄动态状态（命名字典，客户端 HUD 直接读字段）
	var own := {}
	var _tt := _pack_team_tactics()   # T 团队决策面板数据（模式/龙/经济差/时长），随 own 下发
	for pid in _assign_hero:
		var h: Hero = _assign_hero[pid]
		if not is_instance_valid(h):
			continue
		var _al := 0 if h.is_dead else 1
		own[pid] = {
			"nid": _net_id_for(h),
			"name": h.display_name,
			"team": h.team,   # 客户端判定自家泉水（切流派钮可见性用）
			"hp": h.health, "mana": h.mana,
			"maxhp": _maxhp_of(h), "maxmana": h.actual_mana_max,
			"level": h.level, "gold": h.gold, "exp": h.exp,
			"alive": _al, "respawn": h.respawn_timer,
			"cd": h.skill_cooldowns.duplicate(), "levels": h.skill_levels.duplicate(),
			"summoner_cd": h.summoner_cooldown,
			"summoner_cdmax": (h.summoner_skill.cooldown if h.summoner_skill else 0.0),
			"summoner_name": (h.summoner_skill.skill_name if h.summoner_skill else ""),
			"recalling": 1 if h.is_recalling else 0,
			"recall_ratio": (clampf(1.0 - h.recall_timer / 7.0, 0.0, 1.0) if h.is_recalling else 0.0),
			"act": _active_equips(h),   # 主动装备（触控钮 ≤2）：[[id, name, max_cd, cd_remaining], …]
			"sp": h.skill_points,
			"yl_pick": str(h.yuanliu_pick),   # 元流之子当前流派（切流派面板高亮当前项）
			"x": h.global_position.x, "z": h.global_position.z,
			"ry": h.rotation.y,   # 接管英雄真实朝向：客户端点按技能/朝向 fallback 用
			# 客户端移动预测同源参数：本帧有效移速（含前摇/暗影倍率）、走A锁定剩余、硬控阻断
			"spd": h.net_predict_speed(), "lock": h.net_predict_locked(),
			"cc": 1 if h.net_predict_blocked() else 0,
			"exp_to_next": h.exp_to_next,   # 第一人称/等级环经验弧（客户端仅自已这一格用）
			"hidden_self": (1 if (h.display_name == "兰陵王" and h.lanling_stealth_active) else 0),
				# 兰陵王隐身中：客户端照主机把固定跟随镜头拉远/拉高 ×1.25
			"tgt": _pack_target(h),   # 实时攻击目标摘要（host h.manual_target）：[] 或 [nid,team,name,lvl,hp,maxhp,atk,ap,armor,mr]
			"buffs": _pack_buff_rows(h),   # P3b 缓冲行：{"top":[[..]],"bot":[[..]]}，客户端触控 HUD 直接按 host 同款 BuffIcon 画
			"equip": (h.equipment_slots.duplicate() if h.equipment_slots is Array else []),   # P3d 已购装备 id 序（客户端商店/出售用，槽位=索引）
		"obj": _pack_obj_timers(),   # 小地图目标计时：[暴君剩余秒, 暴君存活, 主宰剩余秒, 主宰存活]
		"jg": _pack_jg_dead(),       # 小地图野怪记忆：我方已确认在复活中的野怪点位 [[x,z],…]   # 小地图目标计时：[暴君剩余秒, 暴君存活, 主宰剩余秒, 主宰存活]
			"rec": UiManager._get_best_recommended_item(h),   # P3d host 同款 B 键推荐购买决策（合成/槽满逻辑一致），客户端 B 键直接 C_BUY 此 id
			"rb": UiManager._compute_recommended_bundle(h, true),   # 主界面右上推荐带：host 烘焙（含 options 双卡数据，客户端只画）
			"vg": _pack_vanguard(),   # 顶部对局信息带第三行：主宰/暗影/风暴先锋剩余波次
			"sa": _pack_stat_triples(h),   # 属性面板：18 行 [基础,装备,Buff] 三元组（顺序同 UiManager.ATTRIBUTE_ROWS）
			"bs": _pack_equip_bonus(h),    # 商店「总装备加成」：host 同款文本+配色（bonus_* 含装备被动换算，客户端只画）
			"sx": _pack_skill_icons(h),   # 触控技能键图标读数（4槽×编码数组，同 TouchController._update_skill_button_ui）
			"aa": _pack_attack_aa(h),     # 普攻键伤害/攻速/强化+装备被动小字行（同 _push_attack_stats）
			"aa_dmg": float(h.actual_attack_damage),   # 补刀提示：一次普攻伤害（同 host HUD last_hit 规则）
			"flat_pen": float(h.flat_phys_pen),        # 补刀提示：固定物理穿透
			"kills": int(h.kills), "deaths": int(h.deaths), "assists": int(h.assists),   # 主界面个人 K/D/A（同 host kda_label）
			"tt": _tt,   # T 团队决策：["模式名", 龙存活, 我方经济, 敌方经济, 对局时长]
		}
		# P3e 死亡跃迁 1→0：对该 pid 推一次死亡回放（受控时长 + 近7秒伤害聚合，host 同款逻辑）
		var _pa := int(_prev_alive.get(pid, _al))
		if _pa == 1 and _al == 0 and multiplayer.is_server():
			var _drp := _pack_death_recap(h)
			rpc_id(pid, "_rpc_death_recap", _drp)
			own[pid]["dr"] = _drp   # 兜底：随快照一起下发（RPC 单包丢失时客户端仍能弹完整回放）
		_prev_alive[pid] = _al
	out.append(own)

	# 视野源（本帧共享给同队客户端判定敌方塔显隐）
	var sources: Array = []
	if in_battle:
		for ent in get_tree().get_nodes_in_group("entities"):
			if not is_instance_valid(ent) or ent.health <= 0:
				continue
			if int(ent.team) != viewer:
				continue
			if ent is Hero or ent is Minion or ent is Turret:
				sources.append(ent)
		# 死亡视野残留：塔 2 秒 / 小兵 1 秒，按查看方阵营取 host 的计时
		if bm.has_method("get_dead_visions"):
			for d in bm.get_dead_visions(viewer):
				sources.append({
					"pos": d.get("pos", Vector3.ZERO),
					"r": 18.0 if str(d.get("kind", "")) == "turret" else 9.0,
				})

	var heroes: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or e.health <= 0:
			continue
		if _sees_unit(e, viewer, sources):
			heroes.append(_pack_hero(e))
	out.append(heroes)

	var minions: Array = []
	for e in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(e) or e.health <= 0:
			continue
		if _sees_unit(e, viewer, sources):
			minions.append(_pack_unit(e, 1))
	out.append(minions)

	var turrets: Array = []
	for e in get_tree().get_nodes_in_group("turrets"):
		if not is_instance_valid(e):
			continue
		# 倒塌动画中（hp=0 但节点还没删）仍广播，客户端据此本地复刻坍塌表现
		if e.health <= 0 and not e.get("dying_visual"):
			continue
		# 塔恒广播（不分敌我、不看视野）：防御塔是固定建筑，主机单机 Minimap 对小地图与世界里
		# 所有存活塔都一直可见（Minimap.gd 只对兵/英雄做 visible 过滤），客户端据此「无需视野」。
		# 尾字段 idx8：被攻击标记（供客户端小地图复刻主机「我方塔被攻击警告圈」）
		# idx10：范围环状态 0=红(正在打玩家) 1=绿(敌方兵线近) 2=黄(默认)，客户端复刻主机 Turret 范围环配色
		var _trow: Array = _pack_unit(e, 2, 1 if e.under_attack_timer > 0.0 else 0)
		_trow.append(int(e.range_ring_state))
		# idx11：塔分级（outer/inner/high/crystal）供客户端小地图绘制不同形状
		_trow.append(str(e.tower_type))
		# idx12/13：塔盾是否激活与实际盾量，客户端据此显示/隐藏塔盾实物模型
		var shield_on: int = 1 if e.tower_shield_active and e.tower_shield > 0.0 else 0
		_trow.append(shield_on)
		_trow.append(e.tower_shield)
		_trow.append(1 if e.shield_protected_no_minion else 0)   # idx14：无兵线保护（客户端血条左侧盾形图标）
		_trow.append(float(e.armor))                            # idx15：护甲（补刀提示）
		turrets.append(_trow)
	out.append(turrets)

	var jungles: Array = []
	for e in get_tree().get_nodes_in_group("jungle_monsters"):
		if not is_instance_valid(e) or e.health <= 0:
			continue
		if _sees_unit(e, viewer, sources):
			jungles.append(_pack_unit(e, 3))
	out.append(jungles)

	# #42 子弹段：存活弹体 [iid, x, y, z, team, size]——友方恒显，敌方须落我方视野源 18m 内（防隐藏英雄被透视）。
	# 尺寸：2=后羿R 太阳火箭（大号橙色彗星），1=英雄/塔普攻（host 放大×3），0=默认小弹。
	var bullets: Array = []
	for pr in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(pr) or pr.is_queued_for_deletion():
			continue
		var bl: Bullet = pr as Bullet
		if bl == null:
			continue
		if int(bl.team) != viewer \
				and not _pos_in_vision(Vector3(bl.global_position.x, 0.0, bl.global_position.z), sources):
			continue
		var bsz := 0
		if bl.is_houyi_ult:
			bsz = 2
		else:
			var bsrc = bl.source
			if bsrc != null and is_instance_valid(bsrc) and (bsrc is Hero or bsrc is Turret):
				bsz = 1
		# idx8：全图技能弹标记（1=后羿R / 2=鲁班七号2技能），客户端小地图据此画全图子弹
		var gsf := 0
		if bl.houyi_r:
			gsf = 1
		elif bl.luban_w_knockback:
			gsf = 2
		var bflags := _bullet_flags(bl)
		bullets.append([int(bl.get_instance_id()),
			bl.global_position.x, bl.global_position.y, bl.global_position.z,
			int(bl.team), bsz, _bullet_kind(bl), _bullet_vkind(bl), gsf, bflags])
	out.append(bullets)

	# #43 FX 段：[seq, [fid,kind,x,y,z,team,r,life], …]——事件保留 ~0.35s（约5帧快照）防 unreliable 丢包；
	# 超龄在此剪掉；客户端按 fid 幂等去重、按 kind 本地 catalog 复刻 host 视觉。
	_fx_seq += 1
	if not _fx_buf.is_empty():
		var now_ms := Time.get_ticks_msec()
		var keep: Array = []
		for e in _fx_buf:
			if now_ms - int(e[8]) <= 350:
				keep.append(e)
		_fx_buf = keep
	var fx_out: Array = [_fx_seq]
	for e in _fx_buf:
		# 按接收方阵营过滤：敌方远处的技能特效不下发，避免红方看到蓝方全图特效
		if int(e[5]) != viewer:
			var fp := Vector3(float(e[2]), float(e[3]), float(e[4]))
			if not _pos_in_vision(fp, sources):
				continue
		# 末位补施法英雄名；再附加完整技能字段（旧客户端按行大小判断兼容）
		var out_row := [e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[9]]
		if e.size() > 10:
			out_row.append_array(e.slice(10))
		fx_out.append(out_row)
	out.append(fx_out)

	# #44 数值/经验珠/攻击动作 events 段：[seq, [fid, kind, ...], …]——变长行、born_ms 单存 [0]；
	# 同 FX：保留 ~0.35s 防 unreliable 丢包，超龄剪掉；客户端按 fid 幂等去重。
	_ev_seq += 1
	if not _ev_buf.is_empty():
		var now_ms3 := Time.get_ticks_msec()
		var keep3: Array = []
		for e in _ev_buf:
			if now_ms3 - int(e[0]) <= 350:
				keep3.append(e)
		_ev_buf = keep3
	var ev_out: Array = [_ev_seq]
	for e in _ev_buf:
		ev_out.append(e[1])
	out.append(ev_out)

	# 顶部实时战况（击杀比分+经济比分）：与主机 UI_Manager.team_stats_label/_update_team_stats 完全同源——
	# 比分读 host 累计变量（add_team_kill，击杀计入击杀方），经济直接读 host 每帧求和值，避免双份漏算
	out.append({
		"pk": int(bm.get("team_player_kills")),
		"ek": int(bm.get("team_enemy_kills")),
		"pg": int(bm.get("team_player_gold")),
		"eg": int(bm.get("team_enemy_gold")),
	})
	# 小地图右侧英雄环形头像带（复刻主机 _update_respawn_widgets：我方 5 人恒显 + 已阵亡敌方第二排）。
	# 行 = [nid,team,name,level,hp,maxhp,is_ai,is_dead,respawn_remain,respawn_total]
	out.append(_build_respawn_rows())

	# 视野之灵：行 = [iid, x, z, active, 5 秒蓄力进度 0..1, 状态]
	# 追加在快照尾部，旧客户端按 snap.size() 守卫自然忽略。
	var vision_rows: Array = []
	for s in get_tree().get_nodes_in_group("vision_spirits"):
		if not is_instance_valid(s):
			continue
		if int(s.get("team")) != viewer:
			continue
		vision_rows.append([int(s.get_instance_id()), s.global_position.x, s.global_position.z,
			1 if s.vision_active else 0, s.get_net_progress(), s.get_net_state()])
	out.append(vision_rows)

	# 血包状态：[x,z,team,available,cooldown_timer,respawn_time]（客户端/回放模型驱动）
	var hp_rows: Array = []
	for hp in get_tree().get_nodes_in_group("health_packs"):
		if not is_instance_valid(hp):
			continue
		hp_rows.append([hp.global_position.x, hp.global_position.z, int(hp.get("team")),
			1 if bool(hp.get("available")) else 0,
			float(hp.get("cooldown_timer")), float(hp.get("respawn_time"))])
	out.append(hp_rows)

	# 技能侦察区域：[x,z,radius]（鲁班2/后羿R 命中点 2 秒照亮小地图）
	var reveal_rows: Array = []
	if bm.has_method("get_skill_reveal_zones"):
		for z in bm.get_skill_reveal_zones(viewer):
			reveal_rows.append([float(z.get("pos", Vector3.ZERO).x),
				float(z.get("pos", Vector3.ZERO).z), float(z.get("r", 8.0))])
	out.append(reveal_rows)

	# 阵亡英雄：保留倒地模型（尸体）直到复活；行 = [nid, team, x, z, yaw, name]
	var dead_rows: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or not (e is Hero) or not (e as Hero).is_dead:
			continue
		dead_rows.append([_net_id_for(e), int(e.team), e.global_position.x, e.global_position.z,
			e.rotation.y, str(e.display_name)])
	out.append(dead_rows)

	return out


func _turret_in_vision(t: Node, sources: Array) -> bool:
	for src in sources:
		if t.global_position.distance_to(src.global_position) <= 18.0:
			return true
	return false


func _pos_in_vision(p: Vector3, sources: Array) -> bool:
	for src in sources:
		var sp: Vector3
		var rr := 18.0
		if src is Dictionary:
			sp = src.get("pos", Vector3.ZERO)
			rr = float(src.get("r", 18.0))
		else:
			sp = src.global_position
		if p.distance_to(sp) <= rr:
			return true
	return false


## 某阵营视角下单位是否可见：
## - 同阵营恒可见；
## - 蓝方（host 玩家视角）沿用 host 已有的 e.visible / 暴露计时；
## - 红方没有 host 的视野状态，用红方自己的英雄/小兵/塔 18m 视野源判定。
func _sees_unit(e: Node, viewer: int, sources: Array) -> bool:
	if int(e.get("team")) == viewer:
		return true
	# 鲁班2/后羿R 技能侦察：双方客户端都强制可见，且优先于草丛/隐身隐藏
	if float(e.get("skill_reveal_timer")) > 0.0 and int(e.get("skill_reveal_team")) == viewer:
		return true
	if viewer == TEAM_PLAYER and (bool(e.get("visible")) or float(e.get("vision_expose_timer")) > 0.0):
		return true
	return _pos_in_vision(e.global_position, sources)


# 子弹「真模型」kind（与 host Bullet._ready 的弹道选型同款，客户端按 kind 挑 .glb/程序组装）：
# 0=弹石(boulder) 1=弹丸(bullet，英雄远程普攻+塔，host 放大×3) 2=弓手小兵箭 3=攻城炮弹 4=后羿R 太阳火箭(程序)
func _bullet_kind(bl: Bullet) -> int:
	if bl.is_houyi_ult:
		return 4
	var bsrc = bl.source
	if bsrc == null or not is_instance_valid(bsrc):
		return 0
	if bsrc is Turret:
		return 5   # 防御塔能量球（客户端专用发光球体档，区别于英雄远程普攻的 1）
	if bsrc is Minion:
		if bsrc.display_name == "ranged":
			return 2
		if bsrc.display_name == "siege":
			return 3
	if bsrc is Hero and float(bsrc.attack_range) > 400.0:
		return 1
	return 0


# 弹体「定制视觉」vkind（v7 起 idx7，0=无定制）。仅收录 host 侧把默认弹体 visual_mesh
# 换掉的技能弹——客户端 1000+vkind 走定制档复刻原形（vkind 1 = 小乔Q 绽放之舞回旋扇）。
## 弹体视觉附加标记（与 host Bullet._build_unified_visual 同判据）
## bit1：线性技能弹（host 在 build 前把 base ×1.7）
## bit2：英雄弹体元素拖尾（host: 非技能弹，或直线技能弹且有伤害）
func _bullet_flags(bl: Bullet) -> int:
	var f := 0
	var is_skill := int(bl.skill_id) != 0
	var linear: bool = bl.linear_dir != Vector3.ZERO
	if is_skill and linear:
		f |= 1
	var bsrc = bl.source
	if is_instance_valid(bsrc) and bsrc is Hero:
		if not is_skill or (linear and float(bl.damage) > 0.0):
			f |= 2
	return f


func _bullet_vkind(bl: Bullet) -> int:
	# 普攻/塔/兵弹道：统一程序化视觉，100+shape*16+palette 编码，客户端按同一构建器复刻
	var vk := BulletVisual.vkind_for(bl)
	if vk > 0:
		return vk
	var bsrc = bl.source
	if is_instance_valid(bsrc) and bsrc is Hero:
		if bsrc.display_name == "小乔" and int(bl.skill_id) == 1:
			return 1   # 飞出/飞回两枚同款扇盘
	return 0


# #43 FX 推流（host only；任何进程的 skillapply/Bullet 插桩都调它，非 HOST 立即 no-op）。
# 可见性闸门统一口径：离我方(PLAYER侧)所有存活实体 >18m 的特效一律丢（防隐藏敌人被透视）。
# team 只用于客户端上色：0/1 红蓝阵营色，-1 表示固定色域（水系/风暴/元流池，与阵营无关）。
# 事件入 _fx_buf 后由 _build_snapshot 随快照广播并 ~0.35s 后剪掉。
func push_net_fx(kind: int, pos: Vector3, team: int, r: float, life: float,
		hero_name: String = "", extra: Array = []) -> void:
	if mode != Mode.HOST:
		return
	if not _fx_ally_near(Vector3(pos.x, 0.0, pos.z)):
		return
	var now := Time.get_ticks_msec()
	_fx_fid += 1
	# 第 10 位：施法英雄名；第 11 位起为完整技能事件附加字段（slot/caster/target/facing/skill 参数）
	var row := [_fx_fid, kind, pos.x, pos.y, pos.z, int(team), r, life, now, hero_name]
	row.append_array(extra)
	_fx_buf.append(row)
	if _fx_buf.size() > 64:
		_fx_buf.pop_front()


func _fx_ally_near(p: Vector3) -> bool:
	for e in get_tree().get_nodes_in_group("entities"):
		if not is_instance_valid(e) or e.health <= 0:
			continue
		# 我方 = Config.player_team（开局会随机换边；写死 TEAM_PLAYER 会让换到敌方的玩家整局看不到 FX）
		if not Config.is_ally(int(e.team)):
			continue
		if p.distance_to(e.global_position) <= 18.0:
			return true
	return false


# 防御塔激光：塔开火频率低（~1发/秒/塔），逐发 RPC 比塞进快照 FX 段更简单，也不占快照空间
# 客户端据 dur 播同一道细光束，能量球本体走普通弹体快照（kind=5）
func push_tower_laser(from: Vector3, to: Vector3, team: int, dur: float) -> void:
	if mode != Mode.HOST:
		return
	if not _fx_ally_near(Vector3(to.x, 0.0, to.z)):
		return
	rpc("_rpc_tower_laser", from, to, team, dur)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_tower_laser(from: Vector3, to: Vector3, team: int, dur: float) -> void:
	net_tower_laser.emit(from, to, team, dur)


# 防御塔锁定光束：目标存活期间持续同步（细光束一直连到目标，而不是只在开火瞬间）
# 0.15s 刷新位置；目标死亡/脱战立刻推 active=false
func push_tower_lock(from: Vector3, to: Vector3, team: int, active: bool) -> void:
	if mode != Mode.HOST:
		return
	if active and not is_pvp() and not _fx_ally_near(Vector3(to.x, 0.0, to.z)):
		return
	rpc("_rpc_tower_lock", from, to, team, active)


@rpc("any_peer", "reliable", "call_remote")
func _rpc_tower_lock(from: Vector3, to: Vector3, team: int, active: bool) -> void:
	net_tower_lock.emit(from, to, team, active)


# #44 events 推流（host only；任何进程的 GameEntity/BattleManager 插桩都调它，非 HOST 立即 no-op）。
# 可见性闸门与 FX 同口径（离我方存活实体 18m）；own 语义指「接管方英雄」（≠ bm.hero，见 _assign_peer）。
func is_assigned(n: Node) -> bool:
	if mode != Mode.HOST:
		return false
	if n == null or not is_instance_valid(n):
		return false
	return _assign_peer.has(n.get_instance_id())


func _push_ev_row(pos: Vector3, row: Array) -> void:
	if mode != Mode.HOST:
		return
	if not _fx_ally_near(Vector3(pos.x, 0.0, pos.z)):
		return
	_ev_fid += 1
	row[0] = _ev_fid
	_ev_buf.append([Time.get_ticks_msec(), row])
	if _ev_buf.size() > 256:
		_ev_buf.pop_front()


func push_net_dmg(pos: Vector3, dmg: float, crit: bool, magic: bool, shielded: bool = false, true_dmg: bool = false) -> void:
	_push_ev_row(pos, [0, EV_DMG, pos.x, pos.y, pos.z, dmg, 1 if crit else 0, 1 if magic else 0, 1 if shielded else 0, 1 if true_dmg else 0])




func push_net_gold(pos: Vector3, amount: float, own: bool) -> void:
	_push_ev_row(pos, [0, EV_GOLD, pos.x, pos.y, pos.z, amount, 1 if own else 0])


# 经验珠只广播「接管方英雄」为目标的（客户端只需看到自己的绿珠飞向自己）
func push_net_exp(source: Vector3, target: Hero, amount: float) -> void:
	if mode != Mode.HOST:
		return
	if target == null or not is_instance_valid(target):
		return
	if not is_assigned(target):
		return
	var tid := _net_id_for(target)
	_push_ev_row(source, [0, EV_EXP, source.x, source.y, source.z,
		target.global_position.x, target.global_position.z, amount, tid])


# 攻击动作（act：0=普攻起步）；无视角的英雄动作不值得播。
# 闸门只按「我方英雄 18m」——客户端只关心自己/同路 AI 身旁的战斗动画，别让远端塔下小兵战刷动画事件。
func push_net_action(nid: int, act: int, yaw: float) -> void:
	if mode != Mode.HOST:
		return
	var ent = _entity_by_net(nid)
	if ent == null or not is_instance_valid(ent):
		return
	var p := Vector3(ent.global_position.x, 0.0, ent.global_position.z)
	# 死亡动作必须无条件下发：小兵/野怪死在视野边缘或远处时，原 18m 闸门会让客户端
	# 连死亡动作都收不到，模型直接消失。
	if act != ACT_DIE and not _hero_ally_near(p):
		return
	# 行布局与客户端 EV_* 下标一致：x/y/z 在 [2..4]，ACT 的 nid/act/yaw 在 [5..7]
	_push_ev_row(p, [0, EV_ACT, p.x, p.y, p.z, nid, act, yaw])


# Hero 插桩入口：攻击动画触达（自带头部动作发 yaw）
func hero_anim(h: Hero, act: int) -> void:
	if mode != Mode.HOST:
		return
	push_net_action(_net_id_for(h), act, h.rotation.y)


# 通用动作插桩入口（小兵/野怪等非 Hero）：act 0=近战一击
func net_action(ent: Node3D, act: int) -> void:
	if mode != Mode.HOST or ent == null or not is_instance_valid(ent):
		return
	push_net_action(_net_id_for(ent), act, ent.rotation.y)


func _hero_ally_near(p: Vector3) -> bool:
	# PvP：两端客户端都要看到附近战斗动画 → 任意存活英雄 45m 内都推；
	# 单机/合作：只关心本机蓝方英雄附近（18m），避免远端小兵战刷事件。
	var radius := 45.0 if is_pvp() else 18.0
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or e is not Hero or e.health <= 0:
			continue
		if not is_pvp() and e.team != TEAM_PLAYER:
			continue
		if p.distance_to(e.global_position) <= radius:
			return true
	return false


func _maxhp_of(e: Node) -> float:
	# actual_max_health 只在 Hero 维护（Hero.gd _apply_base_stats），GameEntity 默认 0——
	# 对兵/塔/野怪必须回退 max_health，否则快照里它们的 maxhp 全变 0。
	var actual = e.get("actual_max_health")
	if actual != null and float(actual) > 0.0:
		return float(actual)
	return e.max_health


func _pack_hero_status(e: Node) -> Array:
	var out: Array = []
	if e == null:
		return out
	for st in HeroInfoControl.status_entries_of(e):
		var c: Color = st.get("color", Color.WHITE)
		out.append([str(st.get("label", "")), float(st.get("ratio", 0.0)),
			c.r, c.g, c.b, str(st.get("value", "")), 1 if bool(st.get("pulse", false)) else 0])
	return out


func _pack_team_tactics() -> Array:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null or not is_instance_valid(bm):
		return []
	var tt = bm.get("team_tactics")
	if tt == null:
		return []
	var mode := ""
	var dragon := 0
	if tt.has_method("get_mode_name"):
		mode = str(tt.get_mode_name())
	if tt.has_method("_is_dragon_alive"):
		dragon = 1 if bool(tt._is_dragon_alive()) else 0
	return [mode, dragon, int(bm.get("team_player_gold")), int(bm.get("team_enemy_gold")), float(bm.get("game_time"))]


func _pack_assigned_lane(e: Node) -> int:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null or not is_instance_valid(bm):
		return -1
	var tt = bm.get("team_tactics")
	if tt == null:
		return -1
	var asg = tt.get("assignments")
	if asg is Dictionary:
		return int(asg.get(e, -1))
	return -1


func _pack_hero_markers(e: Node) -> Array:
	var out: Array = []
	if e == null or not e.has_method("get_marker_sources"):
		return out
	for src in e.get_marker_sources():
		var cnt: int = int(e.count_markers(src))
		if cnt > 0:
			out.append([str(src.display_name), cnt])
	return out


func _pack_ai_chip(e: Node) -> Array:
	if e == null or not bool(e.get("is_ai")):
		return []
	var ai = null
	for child in e.get_children():
		if child is HeroAI:
			ai = child
			break
	if ai == null:
		return []
	if ai.has_method("debug_chip_info"):
		var ci: Dictionary = ai.call("debug_chip_info")
		if not ci.is_empty():
			var txt := str(ci.get("line1", ""))
			var l2 := str(ci.get("line2", ""))
			if l2 != "":
				txt += "\n" + l2
			return [txt, float(ci.get("r", 0.52)), float(ci.get("g", 0.78)), float(ci.get("b", 1.0))]
	return []

func _pack_hero(e: Node) -> Array:
	# 尾字段 idx9.. = mana / maxmana / shield / exp / exp_to_next（客户端世界血条按主机
	# HeroInfoControl 规格绘制蓝条/护盾，等级环经验弧用后两段）；idx14 = 暗印摘要（黄段+层数）
	return [_net_id_for(e), 0, e.team, e.global_position.x, e.global_position.z, e.health, _maxhp_of(e), e.level, str(e.display_name),
		e.mana, _maxmana_of(e), e.shield_remaining, int(e.exp), int(e.exp_to_next),
		_pack_lyf(e), e.rotation.y, 1 if bool(e.get("hidden_in_bush")) else 0,
		str(e.get("player_name")),   # idx17：玩家/AI 昵称（无英雄名时兜底显示）
		1 if bool(e.get("is_mvp")) else 0,   # idx18：MVP 王冠（客户端世界血条右侧徽章）
		_pack_hero_status(e),   # idx19：状态条（附魔/枪意/炸弹/剑意/回城/传送… 与单机 HeroInfoControl 同源）
		_pack_hero_markers(e),  # idx20：标记图标行 [[name,count]]
		_pack_ai_chip(e),       # idx21：AI 决策胶囊 [label,r,g,b]（非 AI 为空）
		str(e.get("role")),     # idx22：职责（T 面板 [AI] 名字 (role) -> 分路）
		_pack_assigned_lane(e), # idx23：战术分配的 lane（-1=未分配）
		1 if bool(e.get("red_buff_active")) else 0,   # idx24：红 buff（客户端世界模型脚下红环）
		1 if bool(e.get("blue_buff_active")) else 0,  # idx25：蓝 buff（脚下蓝环）
		e.global_position.y,   # idx26：世界高度（孙悟空筋斗云/腾空表现）
		float(e.armor),        # idx27：护甲（补刀提示）
		str(e.get("hero_skin_id"))]   # idx28：皮肤 id


func _maxmana_of(e: Node) -> float:
	if e.get("actual_mana_max") != null:
		return e.actual_mana_max
	if e.get("max_mana") != null:
		return e.max_mana
	return 0.0


# 客户端目标信息面板（P3a）：受控英雄当前攻击目标的实时摘要，语义与 host target_detail_panel 更新一致。
# 数值一律读与 host UI 相同的字段（攻击/法强/护甲/魔抗/生命按 GameEntity 基字段；法强仅 Hero 有）。
func _pack_target(h: Hero) -> Array:
	var t = h.manual_target
	if t == null or not is_instance_valid(t) or not (t is GameEntity) or t.health <= 0:
		return []
	return [_net_id_for(t), t.team, str(t.display_name),
		(t.level if t is Hero else 0), t.health, t.max_health,
		int(t.attack), int(t.ability_power if t is Hero else 0),
		int(t.armor), int(t.magic_resist)]


# P3b buff 行（主机）：与被接管英雄同款纯计算 UiManager.collect_buff_rows（与 host 本机 buff
# 图标行 _update_buff_icons 同源），结果整行推给客户端，保证触控 HUD 的 buff 行 1:1。
# cfg 展开为可序列化行：[key, glyph, [r,g,b], name, desc, remaining, total, steady, sub]
func _pack_buff_rows(h: Hero) -> Dictionary:
	var out := {"top": [], "bot": []}
	var rows: Dictionary = UiManager.collect_buff_rows(h)
	for tier in ["top", "bot"]:
		for c in rows[tier]:
			var tint: Color = c["tint"]
			out[tier].append([str(c["key"]), str(c["glyph"]),
				[tint.r, tint.g, tint.b],
				str(c["name"]), str(c["desc"]),
				float(c["remaining"]), float(c["total"]),
				bool(c["steady"]), str(c["sub"])])
	return out


# P3c roster：属性(C)/队伍(T)面板行——我方 5 全员（含阵亡）+ 可见/已阵亡敌方（与 hero 快照同一套
# 可见性口径，避免未探明敌方被透视；阵亡敌方主界面头像带本就公开）。
# 基础 16 段 = [nid,name,team,level,hp,maxhp,kills,deaths,assists,gold,equipment(id串),atk,ap,armor,mr,ms]
# 追加 9 段（P3g，客户端尺寸不足时按旧 16 段兼容）= [16]total_gold [17]is_ai [18]role [19]is_dead
#   [20]respawn_remain [21]respawn_total [22]attr_chips [[glyph,Color,text],…]（host 英雄卡徽章同源）
#   [23]skill_txts [[text,Color],…]（技能 Lv/CD + 召唤师 + 名刀/复活 CD，host 同源）
#   [24]equip_txts [[text,Color],…]（装备名 + 主动 CD 后缀，host 同源）
#   [25]exp:int（当前经验：团队统计头「经验」合计用，host team_player_exp/enemy_exp 同源口径）
func _build_roster_payload(camp: int = TEAM_PLAYER) -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e):
			continue
		var dead: bool = bool(e.get("is_dead")) if e.get("is_dead") != null else e.health <= 0
		# 按「收件客户端阵营」判定：己方 5 人恒可见（含红方客户端），敌方仍需视野/阵亡
		if e.team == camp or dead or e.visible or e.vision_expose_timer > 0.0:
			out.append(_pack_roster_row(e))
	return out

func _pack_roster_row(e: Node) -> Array:
	var equip: Array = []
	for it in e.equipment_slots:
		equip.append(str(it))
	var dead: bool = bool(e.get("is_dead")) if e.get("is_dead") != null else e.health <= 0
	var row := [_net_id_for(e), str(e.display_name), e.team, e.level, e.health, _maxhp_of(e),
		int(e.kills), int(e.deaths), int(e.assists), int(e.gold), equip,
		int(e.attack), int(e.ability_power), int(e.armor), int(e.magic_resist), int(e.move_speed)]
	row.append(int(e.total_gold_earned) if e.get("total_gold_earned") != null else int(e.gold))
	row.append(1 if bool(e.is_ai) else 0)
	row.append(str(e.role) if e.get("role") != null else "")
	row.append(1 if dead else 0)
	row.append(float(e.respawn_timer) if dead else 0.0)
	row.append(float(e.respawn_time_total) if dead else 0.0)
	row.append(_pack_roster_chips(e, dead))
	row.append(_pack_roster_skills(e))
	row.append(_pack_roster_equips(e))
	row.append(int(e.exp))
	# 追加：[26]lane（分路对位排序用，-1=未分配） [27]skill_info [[slot,name,lv,cd],…]
	var _lane := -1
	var _bm = get_tree().get_first_node_in_group("battle_manager")
	if _bm != null and _bm.team_tactics != null:
		_lane = int(_bm.team_tactics.assignments.get(e, -1))
	row.append(_lane)
	row.append(_pack_roster_skill_info(e))
	# 追加：[28]原初印记等级（0~6，每 100 原初积分 1 级；面板头像环上符文用）
	var _ps: int = int(e.get("primitive_score")) if e.get("primitive_score") != null else 0
	row.append(clampi(_ps / 100, 0, 6))
	return row

# 英雄卡属性徽章：与 host UI_Manager._update_hero_detail（属性行 _achips）逐条同源（形状/主题色/文本）
func _pack_roster_chips(h: Node, dead: bool) -> Array:
	var chips: Array = []
	chips.append(["heart", Color(0.45, 1.0, 0.55), "%d/%d" % [int(h.health), int(h.actual_max_health)]])
	chips.append(["sword", Color(1.0, 0.62, 0.24), "%d" % int(h.actual_attack_damage)])
	chips.append(["spark", Color(0.72, 0.5, 1.0), "%d" % int(h.actual_ability_power)])
	chips.append(["shield", Color(1.0, 0.78, 0.3), "%d" % int(h.actual_armor)])
	chips.append(["gem", Color(0.4, 0.88, 1.0), "%d" % int(h.actual_magic_resist)])
	chips.append(["chev", Color(0.45, 0.9, 0.7), "%.0f" % h.actual_move_speed])
	chips.append(["bolt", Color(1.0, 0.85, 0.3), "%.2f" % h.attack_speed])
	if h.actual_mana_max > 0:
		chips.append(["drop", Color(0.3, 0.7, 1.0), "%d/%d" % [int(h.mana), int(h.actual_mana_max)]])
	if h.actual_crit_chance > 0:
		chips.append(["cross", Color(1.0, 0.42, 0.36), "%.0f%%" % (h.actual_crit_chance * 100)])
	if h.actual_crit_damage > 1.85:
		chips.append(["dmg", Color(1.0, 0.36, 0.3), "%.0f%%" % (h.actual_crit_damage * 100)])
	if h.flat_phys_pen > 0:
		chips.append(["pierce", Color(1.0, 0.72, 0.3), "%d" % int(h.flat_phys_pen)])
	if h.actual_phys_pen_percent > 0:
		chips.append(["pierce", Color(1.0, 0.72, 0.3), "%.0f%%" % (h.actual_phys_pen_percent * 100)])
	if h.flat_magic_pen > 0:
		chips.append(["pierce", Color(0.7, 0.55, 1.0), "%d" % int(h.flat_magic_pen)])
	if h.actual_magic_pen_percent > 0:
		chips.append(["pierce", Color(0.7, 0.55, 1.0), "%.0f%%" % (h.actual_magic_pen_percent * 100)])
	if h.actual_phys_lifesteal > 0:
		chips.append(["heart", Color(1.0, 0.56, 0.34), "%.0f%%" % (h.actual_phys_lifesteal * 100)])
	if h.actual_magic_lifesteal > 0:
		chips.append(["heart", Color(0.78, 0.52, 1.0), "%.0f%%" % (h.actual_magic_lifesteal * 100)])
	if h.bonus_toughness > 0:
		chips.append(["tough", Color(0.96, 0.9, 0.5), "%.0f%%" % (h.bonus_toughness * 100)])
	if h.actual_cd_timer < 1.0:
		chips.append(["clock", Color(0.5, 0.85, 1.0), "%.0f%%" % ((1.0 - h.actual_cd_timer) * 100)])
	return chips

# 英雄卡技能行：host 同款文本与颜色（就绪=亮/冷却=灰，召唤师金，名刀金/复活绿）
func _pack_roster_skills(h: Node) -> Array:
	var out: Array = []
	var sk: Array = h.skills
	var lv: Array = h.skill_levels
	var cds: Array = h.skill_cooldowns
	for i in range(mini(sk.size(), lv.size())):
		var s = sk[i]
		if s == null:
			continue
		var cd: float = float(cds[i]) if i < cds.size() else 0.0
		var ct := "(%.1fs)" % cd if cd > 0.0 else "(就绪)"
		out.append(["%s Lv.%d %s" % [s.skill_name, int(lv[i]), ct], Color.LIGHT_CYAN if cd <= 0.0 else Color.GRAY])
	if h.summoner_skill != null:
		var scd := float(h.summoner_cooldown)
		var sct := "(%.1fs)" % scd if scd > 0.0 else "(就绪)"
		out.append(["%s %s" % [h.summoner_skill.skill_name, sct], UiKit.C_GOLD if scd <= 0.0 else Color.GRAY])
		if h.equipment_slots.has("famous_blade"):
			var fb := "名刀CD:%.0fs(%d/3)" % [h.famous_blade_cd, h.famous_blade_uses] if h.famous_blade_cd > 0 else "名刀:就绪(%d/3)" % h.famous_blade_uses
			out.append([fb, UiKit.C_GOLD if h.famous_blade_cd <= 0 else Color.GRAY])
		if h.equipment_slots.has("revive"):
			var rv := "复活CD:%.0fs(%d/2)" % [h.revive_cd, h.revive_count] if h.revive_cd > 0 else "复活:就绪(%d/2)" % h.revive_count
			out.append([rv, Color.GREEN if h.revive_cd <= 0 else Color.GRAY])
	return out

# 英雄卡装备行：host 同款「装备名 + 主动CD后缀」，逐件浅绿
func _pack_roster_equips(h: Node) -> Array:
	var out: Array = []
	for item_id in h.equipment_slots:
		var it: Dictionary = ItemDatabase.get_item(str(item_id))
		var t: String = str(it["name"]) if not it.is_empty() else str(item_id)
		if it.has("active"):
			var cd := 0.0
			match str(item_id):
				"golden_body": cd = float(h.golden_body_cd)
				"shadow_dart": cd = float(h.shadow_dart_cd)
				"purify": cd = float(h.purify_cd)
				"sunspire_bow": cd = float(h.sunspire_active_cd)
			t += (" CD:%.0fs" % cd) if cd > 0.0 else " [就绪]"
		out.append([t, Color.LIGHT_GREEN])
	return out

# 商店「总装备加成」：host 同款标签/数值格式/配色（bonus_* 含装备被动换算，客户端只画）
func _pack_equip_bonus(h: Hero) -> Array:
	var total_stats := [
		["攻击力", h.bonus_attack],
		["法术强度", h.bonus_ability_power],
		["生命值", h.bonus_health],
		["护甲", h.bonus_armor],
		["魔抗", h.bonus_magic_resist],
		["移速", h.bonus_move_speed],
		["百分比移速", h.bonus_per_speed * 100.0],
		["攻速%", h.bonus_attack_speed],
		["暴击率", h.bonus_crit_chance * 100.0],
		["暴击伤害", h.bonus_crit_damage * 100.0],
		["冷却缩减", (1.0 - h.actual_cd_timer) * 100.0],
		["物理吸血", h.bonus_phys_lifesteal * 100.0],
		["法术吸血", h.bonus_magic_lifesteal * 100.0],
		["物穿", h.bonus_phys_pen_percent * 100.0],
		["法穿", h.bonus_magic_pen_percent * 100.0],
		["韧性", h.bonus_toughness * 100.0],
	]
	var out: Array = []
	for ts in total_stats:
		if float(ts[1]) != 0.0:
			var tc := Color.LIGHT_GREEN
			if ts[0] in ["攻击力", "护甲", "物穿", "物理吸血", "暴击率", "暴击伤害"]:
				tc = Color.ORANGE
			elif ts[0] in ["法术强度", "魔抗", "法穿", "法术吸血"]:
				tc = Color(0.7, 0.4, 1.0)
			out.append(["  %s: %+.0f" % [ts[0], float(ts[1])], tc])
	return out


# 小地图右侧英雄环形头d像带（复刻主机 UI_Manager._update_respawn_widgets）——
# 我方（PLAYER）英雄无论死活都进第一排（残血/复活读秒实时可见）；敌方只在阵亡时进第二排
# （复活即消失，同主机 RespawnWidget 判据 is_dead）。行字段：
#   [0]net_id [1]team [2]name [3]level [4]hp [5]maxhp [6]is_ai(0/1) [7]is_dead(0/1)
#   [8]respawn_remain（阵亡才>0） [9]respawn_total（画复活进度弧分母）
func _build_respawn_rows() -> Array:
	var out: Array = []
	for e in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(e) or not (e is Hero):
			continue
		if is_pvp() or e.team == TEAM_PLAYER or e.is_dead:
			var dead = e.is_dead
			out.append([
				_net_id_for(e), int(e.team), str(e.display_name), int(e.level),
				float(e.health), _maxhp_of(e),
				1 if e.is_ai else 0,   # is_ai(0/1)：与 host RespawnWidget 底色同判据（1=AI 青 / 0=真人 绿；接管英雄 is_ai 保持 true）
				1 if dead else 0,
				float(e.respawn_timer) if dead else 0.0,
				float(e.respawn_time_total) if dead else 0.0,
			])
	return out


# 客户端自身属性面板：与 host UiManager._update_attribute_panel 同源（ATTRIBUTE_ROWS 顺序），
# 每行 [基础,装备,Buff] 三元组；移速用实时分量（临时减速/加速已烘焙进 Buff 段），行缺失补 0。
func _pack_stat_triples(h: Hero) -> Array:
	var bd: Dictionary = h.stat_breakdown
	var out: Array = []
	for cfg in UiManager.ATTRIBUTE_ROWS:
		var key: String = str(cfg.get("key", ""))
		var parts: Array = h._live_move_speed_parts() if key == "move_speed" else bd.get(key, [])
		if parts is Array and parts.size() >= 3:
			out.append(float(parts[0]))
			out.append(float(parts[1]))
			out.append(float(parts[2]))
		else:
			out.append(0.0)
			out.append(0.0)
			out.append(0.0)
	return out

# —— 触控技能键图标读数打包（own.sx，每槽编码数组）——
# 与 host TouchController._update_skill_button_ui(L926-1001) 逐字段同源：客户端无 Hero 实体，
# 由 host 把多段重施窗口/伤害预览/效果小字/强化普攻/充能/前置阻塞烘焙成定长数组下传，客户端透传给
# 共享 SkillTouchButton 即得与 host 一致的技能键读数。定长 15 字段：
#   [0]=in_window(0/1) [1]=win_left [2]=win_total [3]=segments_left
#   [4]=icon_dmg [5]=icon_dmg_magic(0/1) [6]=icon_dmg2 [7]=icon_dmg2_magic(0/1)
#   [8]=icon_count [9]=icon_fx:[[k,txt,hostile(0/1)],…]（数值/时长文本已由 host 烘焙）
#   [10]=icon_aa(0/1) [11]=charge_max [12]=charge_now [13]=blocked(0/1) [14]=block_cue
func _pack_skill_icons(h: Hero) -> Array:
	var out: Array = []
	for i in range(4):
		var f: Array = [0, 0.0, 1.0, 0, -1, 0, 0, 0, 0, [], 0, 0, 0, 0, ""]
		if i >= h.skills.size() or h.skills[i] == null:
			out.append(f)
			continue
		# 第4技能(兰陵王·隐身)在 host 同样全清读数（TouchController L1053-1063）→ 不传
		if i >= 3:
			out.append(f)
			continue
		var mi: Dictionary = {}
		if i < h.skill_window_timers.size():
			mi = h.get_multicast_window(i)
		if not mi.is_empty():
			f[0] = 1
			f[1] = float(mi.win_left)
			f[2] = maxf(float(mi.win_total), 0.001)
			f[3] = maxi(0, int(mi.total) - int(mi.used))
		var dm: Dictionary = SkillDatabase.get_skill_icon_damage(h, i)
		if bool(dm.get("valid", false)):
			f[4] = int(dm.get("dmg", 0))
			f[5] = 1 if bool(dm.get("magic", false)) else 0
			f[6] = int(dm.get("dmg2", 0))
			f[7] = 1 if bool(dm.get("magic2", false)) else 0
		var fx_info: Dictionary = SkillDatabase.get_skill_fx(h, i)
		f[8] = int(fx_info.get("count", 0))
		f[9] = _encode_net_fx(fx_info.get("fx", []))
		f[10] = 1 if SkillDatabase.skill_grants_enhanced_aa(str(h.display_name), i) else 0
		if i < h.skill_levels.size() and h.skill_levels[i] > 0:
			var sk = h.skills[i]
			if sk.restore > 0.0:
				f[11] = int(sk.restore)
				f[12] = int(h.skill_restores[i]) if i < h.skill_restores.size() else 0
			if not (h.casting_skill and h.pending_skill_index == i):
				if h.skill_prereq_blocked(i):
					f[13] = 1
					f[14] = str(h.skill_prereq_cue(i))
		out.append(f)
	return out

# 效果条目标签烘焙成网络行 [k, txt, hostile]，与 _encode_button_fx(L419-453) 同源（client 只需两色解译）
func _encode_net_fx(fx: Array) -> Array:
	var out: Array = []
	for item in fx:
		if not item is Dictionary:
			continue
		var t := str(item.get("t", ""))
		var meta: Dictionary = FX_META.get(t, {})
		if meta.is_empty():
			continue
		var v := float(item.get("v", 0.0))
		var d := float(item.get("d", 0.0))
		var txt := ""
		if meta.has("flag"):
			txt = ""
		elif meta.has("sec"):
			txt = _net_fmt_num(v) + "S"
		elif meta.has("durs"):
			txt = "+" + str(int(roundf(v)))
			if d > 0.001:
				txt += " " + _net_fmt_num(d) + "S"
		elif meta.has("num"):
			txt = "-" + str(int(roundf(v)))
			if d > 0.001:
				txt += " " + _net_fmt_num(d) + "S"
		elif meta.has("two"):
			txt = _net_fmt_num(v) + "%"
			if d > 0.001:
				txt += " " + _net_fmt_num(d) + "S"
		else:
			txt = str(int(roundf(v)))
		if txt == "" and not meta.has("flag"):
			continue
		out.append([t, txt, 1 if FX_HOSTILE_TYPES.has(t) else 0])
	return out

func _net_fmt_num(x: float) -> String:
	var xr := roundf(x * 100.0) / 100.0
	return str(xr)

# 普攻键读数打包（own.aa）：[伤害, 每秒攻速(去倍率), 强化普攻0/1, 装备被动小字行…]
# 小字行每行 [k,name,txt,armed(0/1),col(#rrggbb)]，client 转回 dict 喂 AttackWheelButton.set_item_rows
func _pack_attack_aa(h: Hero) -> Array:
	var pr: Dictionary = h._attack_button_preview()
	var rows: Array = []
	for r in h.aa_item_passive_rows():
		if not r is Dictionary:
			continue
		var c: Color = r.get("col", Color(1.0, 0.6, 0.3))
		rows.append([
			str(r.get("k", "phys")), str(r.get("name", "")), str(r.get("txt", "")),
			1 if bool(r.get("armed", true)) else 0,
			"#%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)],
		])
	return [
		int(pr.get("dmg", 0)),
		h.attack_speed * h.attack_speed_timer,
		1 if bool(pr.get("enhanced", false)) else 0,
		rows,
	]


func _pack_unit(e: Node, type_code: int, extra = null) -> Array:
	# 尾字段：extra(仅防御塔=被攻击标记 idx8) 之后恒接暗印摘要 lyf（idx8 或 idx9）——
	# 客户端按 type+长度守卫读取（旧 host 无此字段则默认空）
	var row := [_net_id_for(e), type_code, e.team, e.global_position.x, e.global_position.z, e.health, _maxhp_of(e), str(e.display_name)]
	if extra != null:
		row.append(extra)
	row.append(_pack_lyf(e))
	# 小兵/野怪被动标记（idx9；塔不追加，保持既有 idx8/9 布局不变）
	if type_code != 2:
		row.append(_pack_markers(e))
		# idx10/11（小兵/野怪）：朝向 + 正在攻击标记，客户端无 act 事件时也能转向/出攻击动作
		var yaw: float = float(e.rotation.y)
		var atk := 0
		var ct = e.get("current_target")
		if ct != null and is_instance_valid(ct) and float(ct.health) > 0.0:
			var ar = e.get("attack_range")
			var reach: float = (float(ar) if ar != null else 100.0) * 0.01 + (3.2 if ct is Turret else 0.0)
			if e.global_position.distance_to(ct.global_position) <= reach + 0.8:
				atk = 1
		row.append(yaw)
		row.append(atk)
		# idx12/13：服务器出手序号 + 攻击间隔（客户端按序号精确复刻出手节奏，不再自己猜）
		row.append(int(e.get("anim_atk_seq")) if e.get("anim_atk_seq") != null else 0)
		var aspd: float = float(e.get("attack_speed")) if e.get("attack_speed") != null else 1.0
		row.append(1.0 / maxf(0.1, aspd))
		row.append(float(e.armor))   # idx14：护甲（补刀提示）
	return row

# 李元芳暗印摘要：[[源英雄名, 层数, 预测实际伤害], …]（客户端血条黄段/层数文字 1:1 复刻主机）
func _pack_lyf(e: Node) -> Array:
	var out: Array = []
	if e.has_method("lyf_mark_summary"):
		for m in e.lyf_mark_summary():
			var src = m["source"]
			out.append([str(src.display_name) if (src != null and is_instance_valid(src)) else "",
				int(m["stacks"]), float(m["pred"])])
	return out

# 通用被动标记摘要：[[源英雄名, 层数], …]（小兵/野怪血条图标用）
func _pack_markers(e: Node) -> Array:
	var out: Array = []
	if e.has_method("get_marker_sources"):
		for src in e.get_marker_sources():
			var cnt: int = int(e.count_markers(src))
			if cnt > 0:
				out.append([str(src.display_name) if (src != null and is_instance_valid(src)) else "", cnt])
	return out


# ---------- M4：静态地图布局（host 打包 / client 收到后供呈现层） ----------

func _broadcast_map_if_needed() -> void:
	if mode != Mode.HOST or players.size() < 2:
		return
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	if bm.get("hero_selected") == null or not bool(bm.get("hero_selected")):
		return  # 还没进对局
	var payload := _collect_map_payload(bm)
	for pid in players:
		var peer_id := int(pid)
		if peer_id == 1 or _map_sent_to.has(peer_id):
			continue
		rpc_id(peer_id, "_rpc_map", payload)
		_map_sent_to[peer_id] = true
		print("[Net] 地图布局已发 peer=", peer_id)


func _resync_peer(pid: int) -> void:
	if not multiplayer.is_server():
		return
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return
	# 地图重发
	rpc_id(pid, "_rpc_map", _collect_map_payload(bm))
	_map_sent_to[pid] = true
	# 当前接管清单
	if _assign_hero.has(pid) and is_instance_valid(_assign_hero[pid]):
		var h: Hero = _assign_hero[pid]
		rpc_id(pid, "_rpc_takeover", _build_manifest(pid, h, _net_id_for(h)))
	# 队伍面板 + 立即首帧快照
	rpc_id(pid, "_rpc_roster", _build_roster_payload(_peer_camp(pid)))
	if bool(bm.get("hero_selected")):
		rpc_id(pid, "_rpc_snapshot", _build_snapshot(bm, _peer_camp(pid)))
	print("[Net] 已补发初始状态 peer=", pid)


func _collect_map_payload(bm: Node) -> Dictionary:
	var bushes: Array = []
	var bush_arr = bm.get("_bush_positions")
	if bush_arr != null:
		for p in bush_arr:
			bushes.append([float(p.x), float(p.z)])
	var walls := PackedFloat32Array()
	for w in get_tree().get_nodes_in_group("walls"):
		if is_instance_valid(w):
			# 每段墙 10 个 float（stride=10）：x,z,yaw,hq,outer,outer_len,continuous_len,pillar,open_end,thick
			# 用 PackedFloat32Array 而不是 Array[Array]：765 段墙从 ~56KB 变 ~31KB，避免超过 WS 默认 64KB 单包上限
			var is_hq: float = 1.0 if w.get("hq") == true else 0.0
			var is_outer: float = 1.0 if w.get("outer") == true else 0.0
			var outer_len: float = float(w.get("outer_len")) if w.get("outer_len") != null else 2.0
			walls.append(float(w.global_position.x))
			walls.append(float(w.global_position.z))
			walls.append(float(w.rotation.y))
			walls.append(is_hq)
			walls.append(is_outer)
			walls.append(outer_len)
			walls.append(float(w.get("continuous_len")) if w.get("continuous_len") != null else 0.0)
			walls.append(1.0 if w.get("pillar") == true else 0.0)
			walls.append(1.0 if w.get("open_end") == true else 0.0)
			walls.append(float(w.get("thick")) if w.get("thick") != null else 1.0)
	var packs: Array = []
	for hp in get_tree().get_nodes_in_group("health_packs"):
		if is_instance_valid(hp) and hp.get("available") != null:
			packs.append([hp.global_position.x, hp.global_position.z, int(hp.team)])
	var camps: Array = []
	var camp_arr = bm.get("jungle_camp_positions")
	if camp_arr != null:
		for c in camp_arr:
			camps.append([float(c.x), float(c.z)])
	return { "bushes": bushes, "walls": walls, "camps": camps, "packs": packs }


func get_map_payload() -> Dictionary:
	return _map_payload


## 地图墙体载荷解码：兼容新 PackedFloat32Array（stride=10）与旧 Array[Array] 两种格式
static func decode_walls(raw) -> Array:
	var out: Array = []
	if raw is PackedFloat32Array:
		var pf := raw as PackedFloat32Array
		var i := 0
		while i + 9 < pf.size():
			out.append([pf[i], pf[i + 1], pf[i + 2], pf[i + 3], pf[i + 4],
				pf[i + 5], pf[i + 6], pf[i + 7], pf[i + 8], pf[i + 9]])
			i += 10
	elif raw is Array:
		for row in (raw as Array):
			if row is Array and (row as Array).size() >= 3:
				out.append(row)
	return out


@rpc("any_peer", "reliable", "call_remote")
func _rpc_map(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_map_payload = payload
	print("[Net] 收到地图布局 bushes=", payload.get("bushes", []).size(),
			" walls=", payload.get("walls", []).size(), " camps=", payload.get("camps", []).size())


func get_roster_payload() -> Array:
	return _roster_payload


@rpc("any_peer", "reliable", "call_remote")
func _rpc_roster(payload: Array) -> void:
	if multiplayer.is_server():
		return
	_roster_payload = payload
	net_roster.emit(payload)


# ---------- P3e：击杀战报广播（host→client；host UI_Manager.show_kill_feed 为全网单点转发入口） ----------
# assists：[[name,team,mark],…] 助攻者（推塔时含小兵）；a_mark/v_mark：事件时刻的原初印记等级
signal net_kill_feed(actor: String, actor_team: int, desc: String, victim: String, victim_team: int,
	assists: Array, a_mark: int, v_mark: int)

func broadcast_kill_feed(actor: String, actor_team: int, desc: String, victim: String = "", victim_team: int = -1,
		assists: Array = [], a_mark: int = 0, v_mark: int = 0) -> void:
	if mode != Mode.HOST or not multiplayer.is_server():
		return
	rpc("_rpc_kill_feed", str(actor), int(actor_team), str(desc), str(victim), int(victim_team),
		assists, int(a_mark), int(v_mark))

@rpc("any_peer", "reliable", "call_remote")
func _rpc_kill_feed(actor: String, actor_team: int, desc: String, victim: String, victim_team: int,
		assists: Array, a_mark: int, v_mark: int) -> void:
	if multiplayer.is_server():
		return
	net_kill_feed.emit(actor, actor_team, desc, victim, victim_team, assists, a_mark, v_mark)


# ---------- 聊天：主机统一广播；客户端发言先送主机再回显（全端同一顺序，含 AI 台词） ----------
signal net_chat(from_name: String, team: int, text: String)

var _chat_stamp := {}   # host：peer_id -> 上次发言毫秒（简易刷屏限流）

func broadcast_chat(from_name: String, team: int, text: String) -> void:
	if mode != Mode.HOST or not multiplayer.is_server():
		return
	rpc("_rpc_chat", str(from_name), int(team), str(text))

func request_chat(text: String, team: int) -> void:
	if mode != Mode.CLIENT:
		return
	rpc_id(1, "_rpc_chat_request", str(text), int(team))

@rpc("any_peer", "reliable", "call_remote")
func _rpc_chat_request(text: String, team: int) -> void:
	if not multiplayer.is_server():
		return
	var pid := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if now - int(_chat_stamp.get(pid, -99999)) < 700:
		return
	_chat_stamp[pid] = now
	var t := str(text).strip_edges()
	if t == "":
		return
	if t.length() > 40:
		t = t.substr(0, 40)
	var nm := str(players.get(pid, {}).get("name", "玩家"))
	var tm := clampi(int(team), 0, 1)
	broadcast_chat(nm, tm, t)
	net_chat.emit(nm, tm, t)   # 主机本机也要显示这条客户端发言（rpc 是 call_remote）

@rpc("any_peer", "reliable", "call_remote")
func _rpc_chat(from_name: String, team: int, text: String) -> void:
	if multiplayer.is_server():
		return
	net_chat.emit(from_name, team, text)


# ---------- P3e：死亡回放（host 死亡跃迁时对该 pid 推一次；client 弹层复刻主机 _show_death_recap 聚合视图） ----------
signal net_death_recap(payload: Dictionary)

func _recap_skill_key(skill_id: int) -> String:
	match skill_id:
		1: return "1技能"
		2: return "2技能"
		3: return "3技能"
		-2: return "灼烧"
		-10: return "红莲"
		-20: return "电刀"
		-21: return "末世"
		-22: return "圣剑"
		-23: return "巫术"
		-24: return "宗师"
		-25: return "凝冰"
		-26: return "寒霜"
		-27: return "回响"
		-28: return "面具"
		-29: return "冰痕"
		-30: return "日渊"
		-31: return "血魔"
		-32: return "怒龙"
		-33: return "极寒"
		-51: return "王昭君冰霜冲击"
		-52: return "王昭君强化普攻"
		_:
			return ("装备" if skill_id < -9 else "普攻")

func _pack_death_recap(h: Hero) -> Dictionary:
	# 与主机 UI_Manager._show_death_recap 共用同一份 payload 构建（单一真源，避免两端漂移）
	var battle = get_tree().get_first_node_in_group("battle_manager")
	return DeathRecapView.build(h, battle)

@rpc("any_peer", "reliable", "call_remote")
func _rpc_death_recap(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	net_death_recap.emit(payload)


# ---------- P3f：结算（host game_over 翻转广播一次；client 全英雄两列记分 + 胜负大字） ----------
signal net_game_over(payload: Dictionary)

## 是否是真人操控的英雄：host 本机英雄 is_ai=false；联机队友/对手的 Hero 在 host 上由 AI 代操（is_ai=true），
## 但 _assign_peer 里登记了 peer_id → 仍算真人，结算不能标 AI。
func is_human_hero(h) -> bool:
	if h == null:
		return false
	if not bool(h.get("is_ai")):
		return true
	return _assign_peer.has(h.get_instance_id())


func _build_result_payload(bm: Node) -> Dictionary:
	var rows: Array = []
	# 与 BattleHistory 同一套 rows 结构（含承伤/治疗/控制/推塔/补刀/装备），客户端结算与对战纪录都直接展示
	var turrets := [0, 0]
	for team in 2:
		var alive := 0
		for t in get_tree().get_nodes_in_group("turrets"):
			if t is Turret and int(t.team) == team and t.health > 0.0:
				alive += 1
		turrets[team] = maxi(0, Turret.TOTAL_PER_SIDE - alive)
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero:
			var h := e as Hero
			rows.append({
				"name": h.display_name, "team": h.team, "lv": h.level,
				"k": h.kills, "d": h.deaths, "a": h.assists,
				"gold": int(h.gold), "dmg": float(h.damage_dealt_to_heroes),
				"mvp": h.is_mvp, "mine": is_human_hero(h), "ai": not is_human_hero(h),
				"role": str(h.role), "lh": int(h.last_hits), "jungle": int(h.jungle_gold),
				"taken": float(h.damage_taken_from_heroes), "heal": float(h.healing_done),
				"cc": int(round(h.cc_duration_dealt * 10.0)), "turret": float(h.turret_damage),
				"equip": (h.equipment_slots.duplicate() if h.equipment_slots is Array else []),
				"nick": str(h.player_name),          # 英雄卡显示「英雄名 · 昵称」
				"tgold": int(h.total_gold_earned),   # 总经济（团队经济/评分口径）
			})
	var gold_hist: Array = []
	var gh = bm.get("team_gold_diff_history")
	if gh is Array:
		gold_hist = (gh as Array).duplicate()
	return {
		"winner": int(bm.get("winner")),
		"dur": float(bm.get("game_time")),
		"turrets": turrets,
		"player_team": int(Config.player_team),
		"rows": rows,
		# 复盘页经济曲线：host 每分钟记录一次双方总经济差，客户端/回放共用
		"gold_hist": gold_hist,
	}

@rpc("any_peer", "reliable", "call_remote")
func _rpc_game_over(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	net_game_over.emit(payload)


# ---------- RPC：快照（client 收） ----------

@rpc("any_peer", "unreliable_ordered", "call_remote")
func _rpc_snapshot(snap: Array) -> void:
	if multiplayer.is_server():
		return  # 主机已有真相
	_last_snap = snap
	_snap_count += 1
	_update_overlay()
	if _spectate != null:
		_spectate.set_snapshot(snap)
	net_snapshot.emit(snap)
	if is_headless and net_test:
		var now: float = Time.get_ticks_msec() / 1000.0
		if now - _last_log_time >= 2.0:
			_last_log_time = now
			_log_snapshot_summary()


func _log_snapshot_summary() -> void:
	var h: int = 0
	var m: int = 0
	var t: int = 0
	if _last_snap.size() > SNAP_JUNGLES:
		h = _last_snap[SNAP_HEROES].size()
		m = _last_snap[SNAP_MINIONS].size()
		t = _last_snap[SNAP_TURRETS].size()
	print("[Net] snap #%d t=%.0fs heroes=%d minions=%d turrets=%d" % [_snap_count, _snap_time(), h, m, t])


func _snap_time() -> float:
	if _last_snap.size() > SNAP_TIME:
		return float(_last_snap[SNAP_TIME])
	return 0.0


# ---------- 状态查询（供呈现层使用） ----------

func is_online() -> bool:
	return mode != Mode.NONE

func am_host() -> bool:
	return mode == Mode.HOST

func am_client() -> bool:
	return mode == Mode.CLIENT

func my_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer != null else 0

func get_online_count() -> int:
	return players.size()

func get_player_names() -> Array:
	var names: Array = []
	for id in players:
		names.append(players[id].name)
	return names

func hide_spectate_overlay() -> void:
	_clear_overlay()

func current_manifest() -> Dictionary:
	return _manifest

# 从最后一帧快照里取自己（按清单 net_id）英雄的世界位置
func own_hero_position() -> Vector3:
	if _manifest.is_empty() or _last_snap.size() <= SNAP_HEROES:
		return Vector3.ZERO
	var nid: int = int(_manifest.get("net_id", -1))
	if nid < 0:
		return Vector3.ZERO
	for arr in _last_snap[SNAP_HEROES]:
		var ent: Array = arr
		if int(ent[0]) == nid:
			return Vector3(float(ent[3]), 0.0, float(ent[4]))
	return Vector3.ZERO


# ---------- headless 客户端脚本化接管驱动（--net-test） ----------

func _nt_drive(delta: float) -> void:
	match _nt_step:
		0:
			# 等首帧快照含自己位置后：向右移 5 米
			var p := own_hero_position()
			if p != Vector3.ZERO:
				_nt_start = p
				send_command([C_MOVE, p.x + 5.0, p.z])
				_nt_step = 1
				_nt_wait = 0.0
				print("[NetTest] move_to sent at x=", p.x)
		1:
			_nt_wait += delta
			var p2 := own_hero_position()
			if p2 != Vector3.ZERO and p2.distance_to(_nt_start) > 2.0:
				print("[NetTest] move-ok dist=%.1f" % p2.distance_to(_nt_start))
				_nt_step = 2
				_nt_wait = 0.0
				if _manifest.has("skills") and (_manifest["skills"] as Array).size() > 0:
					send_command([C_CAST, 0, -1, p2.x, p2.z + 2.0])
					print("[NetTest] cast idx0 sent")
					_nt_step = 3
			elif _nt_wait > 8.0:
				print("[NetTest] move-fail timeout")
				_nt_step = 9
		3:
			_nt_wait += delta
			if _nt_wait > 1.0:
				print("[NetTest] driver-done (move+cast sent, no crash)")
				_nt_step = 9
		9:
			pass


# ---------- 客户端观战棋盘（M1，非 headless 时显示） ----------

func _ensure_overlay() -> void:
	# 联机测试浮层已按需求移除（右上角不再显示 [联机测试] 棋盘/状态）
	return
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 60
	add_child(_overlay_layer)
	_spectate = SpectatePanel.new()
	_spectate.anchor_left = 1.0
	_spectate.anchor_right = 1.0
	_spectate.anchor_top = 0.0
	_spectate.anchor_bottom = 0.0
	_spectate.offset_left = -540.0
	_spectate.offset_right = -30.0
	_spectate.offset_top = 40.0
	_spectate.offset_bottom = 510.0
	_spectate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_spectate)
	_update_overlay()


func _update_overlay() -> void:
	return
	if _spectate == null:
		return
	var txt := "[联机测试] "
	match mode:
		Mode.HOST:
			txt += "主机 端口=%d 在线=%d" % [host_port, players.size()]
		Mode.CLIENT:
			txt += "客户端 在线=%d" % players.size()
		_:
			txt += "未联网"
	if not _manifest.is_empty():
		txt += "  |  操控:" + str(_manifest.get("hero_name"))
	if _last_snap.size() > SNAP_TIME:
		txt += "  |  t=%.0fs" % _snap_time()
	_spectate.set_header(txt)


func _clear_overlay() -> void:
	if _overlay_layer != null:
		_overlay_layer.queue_free()
		_overlay_layer = null
		_spectate = null


# ---------- 观战棋盘（客户端视角，只画服务端推来的已揭示实体） ----------

class SpectatePanel:
	extends Control

	# 内类无法直接引用外层常量，这里复制一份快照下标。
	const SNAP_TIME := 0
	const SNAP_STATE := 1
	const SNAP_OWN := 2
	const SNAP_HEROES := 3
	const SNAP_MINIONS := 4
	const SNAP_TURRETS := 5
	const SNAP_JUNGLES := 6

	# 世界坐标 → 棋盘像素：把 (x,z) ∈ [-60,60] 映射到面板内边距 10 后的区域。
	const WORLD_HALF := 60.0
	const MARGIN := 10.0

	var _snap: Array = []
	var _header := ""
	var _connected := true

	func _ready() -> void:
		set_process(false)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_header(txt: String) -> void:
		_header = txt
		queue_redraw()

	func set_snapshot(snap: Array) -> void:
		_snap = snap
		queue_redraw()

	func set_connected(v: bool) -> void:
		_connected = v
		queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 1.0, 1.0, 0.18), false, 1.5)

		var font := UiKit.font()
		var title := _header
		if not _connected:
			title = "[与主机断开] " + _header
		draw_string(font, Vector2(MARGIN, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.95, 0.95))
		if _snap.is_empty():
			draw_string(font, Vector2(MARGIN, 38), "等待快照…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.75, 0.75))
			return

		var top := 30.0
		var fw: float = w - MARGIN * 2.0
		var fh: float = h - top - MARGIN
		draw_rect(Rect2(MARGIN, top, fw, fh), Color(0.03, 0.05, 0.03, 0.55))
		draw_rect(Rect2(MARGIN, top, fw, fh), Color(0.35, 0.5, 0.3, 0.8), false, 1.0)

		_draw_lanes(MARGIN, top, fw, fh)

		var hero_n: int = 0
		if _snap.size() > SNAP_HEROES:
			hero_n = _snap[SNAP_HEROES].size()
		var time_txt := "对局时间 %.0fs  已揭示英雄 %d" % [_snap_time_internal(), hero_n]
		draw_string(font, Vector2(MARGIN, 26), time_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.95, 0.9))

		if _snap.size() > SNAP_TURRETS:
			for arr in _snap[SNAP_TURRETS]:
				var ent: Array = arr
				_draw_turret(ent, MARGIN, top, fw, fh)
		if _snap.size() > SNAP_JUNGLES:
			for arr in _snap[SNAP_JUNGLES]:
				var ent: Array = arr
				_draw_jungle(ent, MARGIN, top, fw, fh)
		if _snap.size() > SNAP_MINIONS:
			for arr in _snap[SNAP_MINIONS]:
				var ent: Array = arr
				_draw_minion(ent, MARGIN, top, fw, fh)
		if _snap.size() > SNAP_HEROES:
			for arr in _snap[SNAP_HEROES]:
				var ent: Array = arr
				_draw_hero(ent, MARGIN, top, fw, fh)

	func _draw_lanes(mx: float, my: float, fw: float, fh: float) -> void:
		var c := Color(0.6, 0.6, 0.5, 0.16)
		draw_line(Vector2(mx, my), Vector2(mx + fw * 0.98, my + fh * 0.5), c, 2.0)
		draw_line(Vector2(mx + fw, my), Vector2(mx, my + fh), c, 2.0)
		draw_line(Vector2(mx, my), Vector2(mx, my + fh * 0.6), c, 2.0)

	func _to_px(sx: float, sz: float, mx: float, my: float, fw: float, fh: float) -> Vector2:
		var px: float = mx + ((sx + WORLD_HALF) / (WORLD_HALF * 2.0)) * fw
		var py: float = my + ((sz + WORLD_HALF) / (WORLD_HALF * 2.0)) * fh
		return Vector2(px, py)

	func _team_col(t: int) -> Color:
		match t:
			0: return Color(0.2, 0.8, 1.0, 1.0)
			1: return Color(1.0, 0.35, 0.3, 1.0)
			_: return Color(0.85, 0.8, 0.2, 1.0)

	func _draw_hero(ent: Array, mx: float, my: float, fw: float, fh: float) -> void:
		var p := _to_px(float(ent[3]), float(ent[4]), mx, my, fw, fh)
		var col := _team_col(int(ent[2]))
		draw_circle(p, 8.0, Color(col.r, col.g, col.b, 0.25))
		draw_circle(p, 5.0, col)
		draw_circle(p, 5.0, Color(0, 0, 0, 0.4), false, 1.0)
		var ratio := _hp_ratio(float(ent[5]), float(ent[6]))
		var bar_w := 14.0
		var bar_y := p.y - 10.0
		draw_rect(Rect2(p.x - bar_w / 2.0, bar_y, bar_w, 2.5), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p.x - bar_w / 2.0, bar_y, bar_w * ratio, 2.5), Color(0.25, 1.0, 0.35) if ratio > 0.4 else Color(1.0, 0.3, 0.3))

	func _draw_minion(ent: Array, mx: float, my: float, fw: float, fh: float) -> void:
		var p := _to_px(float(ent[3]), float(ent[4]), mx, my, fw, fh)
		draw_circle(p, 2.5, _team_col(int(ent[2])))

	func _draw_turret(ent: Array, mx: float, my: float, fw: float, fh: float) -> void:
		var p := _to_px(float(ent[3]), float(ent[4]), mx, my, fw, fh)
		var col := _team_col(int(ent[2]))
		draw_rect(Rect2(p.x - 5.0, p.y - 5.0, 10.0, 10.0), col)
		draw_rect(Rect2(p.x - 5.0, p.y - 5.0, 10.0, 10.0), Color(0, 0, 0, 0.5), false, 1.0)
		var ratio := _hp_ratio(float(ent[5]), float(ent[6]))
		draw_rect(Rect2(p.x - 5.0, p.y - 8.0, 10.0, 2.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p.x - 5.0, p.y - 8.0, 10.0 * ratio, 2.0), Color(0.3, 1.0, 0.4))

	func _draw_jungle(ent: Array, mx: float, my: float, fw: float, fh: float) -> void:
		var p := _to_px(float(ent[3]), float(ent[4]), mx, my, fw, fh)
		draw_circle(p, 2.0, Color(0.45, 0.9, 0.3, 0.9))

	func _hp_ratio(hp: float, mhp: float) -> float:
		if mhp <= 0.0:
			return 0.0
		return clampf(hp / mhp, 0.0, 1.0)

	func _snap_time_internal() -> float:
		if _snap.size() > SNAP_TIME:
			return float(_snap[SNAP_TIME])
		return 0.0

# 英雄卡技能徽章结构化数据：[[slot(1/2/3, 9=召唤师), name, level, cd],…]
func _pack_roster_skill_info(h: Node) -> Array:
	var out: Array = []
	for i in range(mini(h.skills.size(), 3)):
		var sk = h.skills[i]
		out.append([i + 1, str(sk.skill_name) if sk != null else "", int(h.skill_levels[i]),
			float(h.skill_cooldowns[i]), int(sk.type) if sk != null else -1])
	if h.summoner_skill != null:
		out.append([9, str(h.summoner_skill.skill_name), 0, float(h.summoner_cooldown),
			int(h.summoner_skill.type)])
	return out

# 小地图目标计时（客户端 MinimapDraw.draw_objectives 用）
# 先锋波次（顶部信息带第三行，与 host UI_Manager._vanguard_info 同口径）
func _pack_vanguard() -> Array:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return []
	var my_team: int = TEAM_PLAYER
	var en_team: int = 1 - TEAM_PLAYER
	return [str(bm.vanguard_wave_name()),
		int(bm.vanguard_waves_left(my_team)), int(bm.vanguard_waves_left(en_team)),
		1 if bool(bm.vanguard_ever) else 0]


func _pack_obj_timers() -> Array:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return []
	return [float(bm.tyrant_timer), 1 if bm.tyrant_alive else 0, float(bm.dragon_timer), 1 if bm.dragon_alive else 0]

# 小地图野怪记忆（客户端幽灵/隐藏同步用）
func _pack_jg_dead() -> Array:
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm == null:
		return []
	var mm = bm.get("minimap")
	if mm == null or not is_instance_valid(mm) or not mm.has_method("jg_dead_list"):
		return []
	return mm.jg_dead_list()
