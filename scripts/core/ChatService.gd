extends Node
## 聊天总线（autoload）：玩家输入 / AI 聊天 / 联机同步 / 语音识别，并负责在对局中挂上左下角聊天区。
## 联机：主机生成 AI 台词并广播；客户端只发主机，由主机统一回显（全端同一份顺序）。

signal message(from_name: String, team: int, text: String, is_self: bool)
signal lingbao_said(text: String)   # 灵宝说话：全局悬浮灵宝（scripts/ui/LingbaoOverlay.gd）据此弹气泡

const BoxScript = preload("res://scripts/ui/ChatBox.gd")
const MAX_TEXT := 40
const AI_MIN_GAP := 4.0          # 任意两条 AI 台词的最小间隔
const AMBIENT_MIN := 22.0
const AMBIENT_MAX := 46.0

const LINES_AMBIENT := [
	"集合推中路", "下路小心，打野可能在", "我来开团，跟上", "大龙看了吗",
	"先清线再打团", "注意敌方刺客位置", "这波稳住别急", "对面残血，追",
	"塔下别站太久", "回城补个装", "辅助跟我走", "红区小心",
	"我先手了，跟", "别单走", "经济差不多，能打",
]
const LINES_AHEAD := ["稳住别浪，已经优势了", "推塔，别去打野了", "对面打不过这波"]
const LINES_BEHIND := ["缩塔发育，别硬打", "抱团，别一个个上", "先别送，等我发育"]
const LINES_ENEMY := ["别挣扎了", "这波团我们稳了", "小心，我来了", "再来啊", "你们打不过的"]
const LINES_KILL := ["漂亮", "这波我拿的", "走位可以", "继续压他"]
const LINES_DIED := ["我被抓了", "有人蹲我", "完了，我死了", "别追了"]
const LINES_ENEMY_TAUNT := ["就这？", "谢谢人头", "别来了"]
const LINES_REPLY := ["收到", "明白", "好嘞", "马上", "OK"]
const LINES_LOW_HP := ["我没血了，先撤", "我残血，回城补一下", "打不了了，我退了"]
const LINES_PLAYER_LOW := ["你血少了，先退一下", "别硬打，回城补状态", "你没状态，我来顶"]
const LINES_OBJ_SOON := ["龙快刷了，提前占位置", "准备抢龙，别站太远", "龙要刷新了，抱团"]
const LINES_OBJ_UP := ["龙出来了，去看看", "主宰刷新了，抱团", "大龙有了，别单走"]
const LINES_TOWER_PUSH := ["他们塔快掉了，推", "趁现在推塔", "点塔，别追人"]
const LINES_DEFEND := ["塔要掉了，回防", "先守塔，别出去", "回防，家要没了"]
const LINES_NUMBERS := ["别去，他们人多", "对面抱团了，小心", "人少，先撤"]
const LINES_OUTNUMBER := ["可以打，他们人少", "他们分开了，抓单", "上，我们人多"]
const LINES_DEAD_WAIT := ["别急，等你复活", "我们先稳一下，等你", "复活了再打"]
const LINES_OVEREXTEND := ["别一个人推太深", "回来，别单走", "一个人别过河"]
const LINES_SUPPORT := ["我保护你，往前打", "我给你奶，顶住", "跟着我，别怕"]
const LINES_KILL_AHEAD := ["这波赚了，推塔", "拿到了，继续压", "漂亮，趁势推进"]
const LINES_KILL_ENEMY := ["这仇记下了", "等会还回来", "别得意"]
# 按 AI 当前真实行为意图说话（说什么=接下来做什么）
const LINES_INTENT_PUSH := ["清线推塔，别断兵线", "我把这波线推过去", "推完这波就参团", "兵线压过去，跟我"]
const LINES_INTENT_FARM := ["我先把这波线清了", "补两波发育", "等我刷完这组", "别打架，我先发育"]
const LINES_INTENT_JUNGLE := ["我刷完这组就抓", "野区清一圈", "红开，马上到", "等我刷完就 gank"]
const LINES_INTENT_CHASE := ["我追一下，能杀", "别跑，我到了", "他残血，我追"]
const LINES_INTENT_KILL := ["能杀，我上", "别抢，我收", "他跑不掉了"]
const LINES_INTENT_RETREAT := ["我血不够，先撤", "打不了，我退了", "别追，我先走"]
const LINES_INTENT_RECALL := ["我回城补一下", "回城买装备，马上来", "我先回，别等我"]
const LINES_INTENT_DEFEND := ["塔要掉了，我回防", "守塔，别出去", "我回去守家"]
const LINES_INTENT_ROTATE := ["我游走一下", "去帮一波，等我", "我过去了，别开团"]
const LINES_INTENT_AVOID := ["先避一下", "别在塔下打", "绕一下再打"]

# AI 正在做的事（与意图同一来源，说“我正在…”而不是只说“我要去…”）
const LINES_DOING_PUSH := ["我在清这波线", "正在推塔，别断兵", "我在带线，你们抱团"]
const LINES_DOING_FARM := ["我正在补这波兵", "我在发育，等我两件", "正在清线攒钱"]
const LINES_DOING_JUNGLE := ["我正在刷这组野", "野区刷到一半", "我在打红，马上到"]
const LINES_DOING_CHASE := ["我正在追他", "我在追，别抢", "正追着残血呢"]
const LINES_DOING_KILL := ["我在收这个人头", "正在打，能杀", "我在他脸上"]
const LINES_DOING_RETREAT := ["我正在撤，别管我", "我在往塔下退", "正在跑，别回头"]
const LINES_DOING_RECALL := ["我正在回城读条", "我在泉水补状态", "正在回城，马上来"]
const LINES_DOING_DEFEND := ["我正在回防守塔", "我在守这座塔", "正在往家赶"]
const LINES_DOING_ROTATE := ["我正在赶过去", "我在路上，到了就开", "正在游走"]
const LINES_DOING_AVOID := ["我正在绕后", "我在避战拉扯", "正在找位置"]
const LINES_DOING_DEAD := ["我倒了，正在等复活", "我在看复活时间", "正在泉水等活"]
const LINES_DOING_CAST := ["我正在放技能", "我在读条，别打断", "正在蓄力"]
const HERO_VOICE_LINES := {
	"亚瑟": ["永不背叛！", "命运所在，别无选择。", "王者背负，王者审判，王者不可阻挡！", "为王者的信念，连睡觉也穿着铠甲。", "圣光，你有看到那个敌人吗？", "理想乡呼唤着我。", "不要被欲望玷污。", "因剑而亡。"],
	"铠": ["以绝望挥剑，着逝者为铠。", "长城，让我忘记自己孤身一人。", "一个人可以被毁灭，但绝不会被打败。", "比任何对手都强，乃人生最大的烦恼。", "对峙命运。", "被诅咒的可悲人生，终结于我的剑刃。", "磨砺的不止锋芒，还有灵魂。", "无限接近死亡，更能醒悟生存的真谛。", "饮血的刃，越发空虚。", "人，总是向死而生。"],
	"马超": ["我的枪去而复返，你的生命有去无回。", "不必辨认我，识我的枪吧。", "西凉锦马超在此，快来共决生死。", "头脑和心灵一样清楚。", "从未遗忘。", "别动，动也是死。", "穿膛而过！", "收割比正义来得快。", "只和理想结盟，只与纯洁立誓。", "枪若白狼，一收一放。"],
	"吕布": ["神挡杀神！", "从此刻开始，战场由我一人主宰。", "我的貂蝉在哪里？", "我是这个世界的梦魇！", "放马过来吧！", "心中的黑暗在不断膨胀。", "无法得到，那就将她彻底毁掉！", "痛快！痛快！", "前方深渊，身后地狱。"],
	"李白": ["大河之剑天上来！", "十步杀一人，千里不留行。", "今朝有酒今朝醉。", "我和我的剑到此一游。", "但愿长醉不复醒。", "一篇诗，一斗酒，一曲长歌，一剑天涯。", "将进酒，杯莫停。", "努力有用的话，还要天才干什么。", "你的血让我诗兴大发。", "来，干！"],
	"孙悟空": ["俺老孙来也！", "一个跟头十万八千里。", "呔！吃俺老孙一棒！", "取经之路，就在脚下。", "嗯？有妖气！", "超出三界之外，不在五行之中。", "妖孽，哪里逃？", "送佛送上西！"],
	"甄姬": ["悲伤，逆流成河。", "果然，先爱上的那个人，是输家。", "别靠近我，阿宓，不想带来不幸。", "明明说好的，要永远在一起。", "若轻云之蔽月，若流风之回雪。", "随波逐流的痛苦，你们不懂。", "沦陷在爱情的泡影中。", "人家抒发哀伤时，不要随便破坏氛围好吗？"],
	"王昭君": ["凛冬已至。", "故乡的梅花开了吗？", "身躯已然冰封，灵魂仍旧火热。", "寒流，无处不在。", "替你们消消火！", "白梅落下之日，归去故里之时。", "美貌是种罪孽，暴雪也无法掩埋。", "绝对零度！"],
	"孙尚香": ["大小姐驾到，通通闪开！", "来发子弹吗？满足你！", "你也是本小姐的粉丝吗？", "淑女什么的，哼，才不屑呢！", "没人气的家伙，不值得浪费炮火。", "送你一个轰轰烈烈的退场，感谢本小姐大恩大德吧！", "野外徘徊的可怜家伙，能够收获的只有炮火。", "3，2，1，boom！"],
	"马可波罗": ["Let's go baby！", "世界那么大，我想来看看。", "Are you ready？", "Show time！", "战争，一场行为艺术。", "行动和欲望，决定未来。", "让子弹快乐的飞吧。", "摩擦摩擦，是魔鬼的步伐。", "哟，躺枪啦！", "高风险，高回报！"],
	"东皇太一": ["日蚀亲临，如我之神迹！", "俯视低等种族的彷徨，循螺旋而上。", "比黑暗更深沉的黑暗，辉映着永恒。", "展现进化的可能性！", "听！恒星的哀嚎，它在祭献最后的烛火。", "舍弃怜悯，能让你蜕变为冷血的蜈蚣，丑陋又强大。", "庸人幻想禁忌，伟人制造禁忌。", "万物皆可知。"],
	"不知火舞": ["优雅的舞，是致命的毒。", "有破绽！", "忍法・不知火流！", "飞鼠之舞！", "樱花飘落，如我之舞。", "让你见识一下，真正的火舞！"],
	"狄仁杰": ["现在是逮捕时间！", "代表法律制裁你！", "我就是法律的化身！", "以陛下的名义，你被捕了！", "死者也会开口说话。", "为无辜者代言。", "想知道自己怎么死的吗？来～马上就告诉你。"],
	"太乙真人": ["参透不了永恒，便炼出那一炉。", "炼丹，要有耐心。", "万物皆可为丹。", "小爷我，从不差钱。"],
	"兰陵王": ["黑暗，是我的朋友。", "我有独特的观察力。", "低调，是最华丽的炫耀。", "藏好你的尾巴。", "刀光，闪过。"],
	"张飞": ["燕人张飞在此，谁敢放肆！", "百万军中，取人首级如探囊取物。", "三爷我长得丑，可惜你想得美。", "能吃苦，才配做英雄。", "燕人张翼德在此！"],
	"沈梦溪": ["看你一脸颓废，就送你个惊喜！", "那只猫，很不寻常！", "我的炸药，免费试用哦～", "想炸你很久了！"],
	"安琪拉": ["知识，就是力量！", "我很生气～后果很严重！", "前方高能！", "不，是幸福的味道。", "我的热情，就像你脚下的炉火。", "让火焰净化一切！"],
	"妲己": ["请尽情吩咐妲己，主人。", "妲己，会一直爱你。", "别靠近我，我怕被迷倒。", "来和妲己玩耍吧～", "主人，是妲己最想守护的人。"],
	"小乔": ["恋爱和战斗，都要勇往直前！", "小乔要努力变强！", "哼，一团团棉花糖。", "独自生存，才是最大的本事。", "无法想象的美好。"],
	"鲁班七号": ["鲁班大师，智商250。", "一炮，送你回老家！", "智商越高，炮越准。", "看我的蓝翔炮！", "能看穿你的人，就能打败你。"],
	"夏侯惇": ["独眼，看得更远。", "方向错了，就该回头。", "蓉城是我家，老爹最伟大！", "英雄，不问出处。"],
	"后羿": ["我，最后的太阳。", "苏醒了，猎杀时刻。", "周日被我射熄火了，所以今天是周一。", "最光明，最黑暗。", "哼，要变天了。"],
	"李元芳": ["秘密的密，探案的探！", "做坏蛋，要有结局会悲剧的觉悟。", "暗夜，才是密探的主场。", "狄大人，下月的工资评定，请对我温柔点！", "你有权保持沉默，但所说的都将成为呈堂证供。"],
	"元流之子": ["在战斗中，自己告诉自己真理。", "以剑为誓，以念为引。", "命运，握在自己手中。"],
	"大禹": ["害怕的话，就站在我身后吧。", "神斧破世，万兵来朝。", "大地之殇！", "苦难由我终结！", "开辟新生！", "冲锋！"],
	"刘禅": ["冲啊，暴走机关！", "给我来点烧鸡！不，是战机！", "爸，你去哪了？", "机关术，很有意思。"],
	"英睿": ["精准打击！", "看好了，这一击！", "数据不会说谎。"],
}
const HERO_VOICE_FALLBACK := ["看我的！", "受死吧！", "这一局，由我主宰！"]

const VOICE_AMBIENT_BY_ROLE := {
	"战士": ["跟我上！", "这波能打！", "我去开团！", "别退，顶住！"],
	"法师": ["等我技能。", "先消耗他们。", "注意站位。", "别被开到。"],
	"刺客": ["我绕后。", "找机会切后排。", "别暴露我。", "等我先手。"],
	"射手": ["保护我。", "我来输出。", "别抢我线。", "让我发育。"],
	"辅助": ["我跟你。", "小心草丛。", "我来开视野。", "稳住，别急。"],
}
const VOICE_AMBIENT_DEFAULT := ["小心点。", "稳住。", "注意地图。", "别浪。"]

var _hero_voice_t := 0.0
var _hero_voice_global_last := -99.0
var _hero_voice_next := {}
var _hero_ult_last := {}
var _hero_line_last := {}



var typing := false              # 正在打字：UiManager 据此屏蔽走位/技能输入

var _box: Control = null
var _layer: CanvasLayer = null
var _llm: Node = null
var _bm: Node = null
var _scan_t := 0.0
var _ambient_t := 0.0
var _ambient_next := 30.0
var _last_ai_t := -99.0
var _stat := {}                  # hero instance_id -> [kills, deaths]
var _pending: Array = []         # [{t, hero, text}]
var _voice_thread: Thread = null
var _voice_done := false
var _voice_lines: Array = []
var _player_last := {"kills": 0, "dead": false, "low": false, "low_cd": 0.0, "dead_said": false}
var _recent_lines: Array = []
var _last_minute := -1
var _minute_idx := 0
var _intent_t := 0.0
var _last_intent := {}
var _intent_said := {}


func _ready() -> void:
	set_process(true)
	if is_instance_valid(NetSession):
		NetSession.net_chat.connect(_on_net_chat)
	_llm = preload("res://scripts/core/LLMChat.gd").new()
	add_child(_llm)


func _process(delta: float) -> void:
	_ensure_ui()
	_tick_voice()
	_tick_hero_voice(delta)
	if _bm == null or not is_instance_valid(_bm):
		return
	if NetSession.mode == NetSession.Mode.CLIENT:
		return                     # 客户端不生成 AI 台词，等主机广播
	_scan_t += delta
	if _scan_t >= 1.0:
		_scan_t = 0.0
		_scan_ai()
	_tick_ai(delta)


# ---------------- 对外接口 ----------------

func send_player(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	# 调试命令：/voice 查看语音诊断；/voice test 触发一次播报
	if t == "/voice" or t == "/voice test":
		var vs = get_node_or_null("/root/VoiceService")
		if vs != null:
			system_note("语音诊断：" + JSON.stringify(vs.call("diagnose")))
			if t == "/voice test":
				vs.call("speak", "语音测试，一二三四五", "灵宝")
		return
	if t.length() > MAX_TEXT:
		t = t.substr(0, MAX_TEXT)
	var nm := NameStore.player_name()
	if nm == "":
		nm = "我"
	# 客户端：只把发言交给主机，等主机回显，保证全网顺序一致（AI 回复也由主机生成）
	if NetSession.mode == NetSession.Mode.CLIENT:
		NetSession.request_chat(t, Config.player_team)
		return
	_post(nm, Config.player_team, t, true)
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.broadcast_chat(nm, Config.player_team, t)
	_reply_to_player(t)


func system_note(text: String) -> void:
	_post("系统", -1, text, false)


## 灵宝说话：进聊天频道（名字「灵宝」，敌方不可见配色）
func say_lingbao(text: String, broadcast: bool = false) -> void:
	var t := str(text).strip_edges()
	if t == "":
		return
	_post("灵宝", Config.player_team, t, false)
	lingbao_said.emit(t)
	var _vs2 = get_node_or_null("/root/VoiceService")
	if _vs2 != null:
		_vs2.call("speak", t, "灵宝")
	if broadcast and NetSession.mode == NetSession.Mode.HOST:
		NetSession.broadcast_chat("灵宝", Config.player_team, t)


## 玩家在聊天里 @灵宝：小精灵回话（配了大模型就用大模型）
func _lingbao_reply(text: String) -> void:
	var lb = get_tree().get_first_node_in_group("lingbao")
	if lb == null or not is_instance_valid(lb):
		# 非战斗界面（大厅/选人/结算）：交给全局悬浮灵宝接话
		lb = get_node_or_null("/root/LingbaoOverlay")
	if lb == null or not is_instance_valid(lb):
		return
	var nm := "灵宝"
	var line := ""
	if _llm != null and bool(_llm.get("enabled")):
		var ok: bool = _llm.call("ask",
			"你是玩家手机 MOBA 游戏里的随身小精灵「灵宝」，性格活泼黏人，句尾常带「～」。"
			+ "玩家在跟你说话，用一句中文口语回他：8~20 字，不要自称 AI/模型，不要输出引号或换行，只输出这一句话。",
			"玩家「%s」说：%s" % [nm, text],
			func(reply: String) -> void:
				if reply.strip_edges() == "":
					lb.call("respond", _lingbao_canned())
				else:
					lb.call("respond", reply))
		if ok:
			return
	lb.call("respond", _lingbao_canned())


func _lingbao_canned() -> String:
	var pool := ["我在呢，说给我听～", "嗯嗯，我认真听着", "别紧张，我一直陪着你", "说点开心的嘛～"]
	return str(pool[randi() % pool.size()])




## 语音输入：Windows System.Speech 一次性识别（zh-CN），失败则提示不可用
func listen_voice() -> void:
	if _voice_thread != null:
		return
	_voice_lines = []
	_voice_done = false
	system_note("正在听…")
	_voice_thread = Thread.new()
	_voice_thread.start(Callable(self, "_voice_worker"))


# ---------------- 内部：UI ----------------

func _ensure_ui() -> void:
	_bm = get_tree().get_first_node_in_group("battle_manager")
	# 聊天区只在「对战界面」出现：选人/加载/大厅/结算都不挂（原来任何场景都会建，选人页也露按钮）
	var in_battle: bool = false
	if _bm != null and is_instance_valid(_bm):
		var sel_ui = _bm.get("select_ui")
		var sel_open: bool = sel_ui != null and is_instance_valid(sel_ui) and bool(sel_ui.visible)
		in_battle = _bm.get("hero") != null and not sel_open and not bool(_bm.get("game_over"))
	else:
		# 联机客户端：没有 BattleManager，用 NetClientBattle 的对局状态判定（同 host：接管后、未结算）
		var nc := get_tree().get_first_node_in_group("net_client_battle")
		if nc != null and is_instance_valid(nc):
			in_battle = int(nc.get("_state")) == 1 and bool(nc.get("_owned")) and not bool(nc.get("_pm_started"))
	if _box != null and is_instance_valid(_box):
		if _box.visible != in_battle:
			_box.visible = in_battle
			if not in_battle and typing:
				_box.call("_close_input")   # 离开对战：收掉输入条，别把按键锁死
		return
	if not in_battle:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		return
	_layer = CanvasLayer.new()
	_layer.name = "ChatLayer"
	# 聊天按钮必须在最上层（高于触控层/对局信息带/灵宝 130 层），否则左下角按钮点不到
	_layer.layer = 400
	host.add_child(_layer)
	_box = BoxScript.new()
	_layer.add_child(_box)


func _on_net_chat(from_name: String, team: int, text: String) -> void:
	var is_self: bool = str(from_name) == NameStore.player_name()
	_post(from_name, team, text, is_self)
	# 主机替客户端说话的人回一句（客户端自己不生成，避免重复）
	if not is_self and NetSession.mode == NetSession.Mode.HOST:
		_reply_to_player(text)


func _post(from_name: String, team: int, text: String, is_self: bool) -> void:
	# AI 英雄发言自动语音播报（玩家自己/系统/灵宝不在这里读，灵宝在 say_lingbao 里单独读）
	if not is_self and from_name != "灵宝" and from_name != "系统" and _is_ai_speaker_name(from_name):
		var _vs = get_node_or_null("/root/VoiceService")
		if _vs != null:
			_vs.call("speak", text, from_name)
	message.emit(from_name, team, text, is_self)


# ---------------- 内部：AI 聊天 ----------------

func _scan_ai() -> void:
	_scan_player_reactions()
	var heroes := get_tree().get_nodes_in_group("heroes")
	var human_ids := {}
	if is_instance_valid(NetSession):
		var ap = NetSession.get("_assign_peer")
		if ap is Dictionary:
			for k in ap.keys():
				human_ids[int(k)] = true
	if _bm != null and is_instance_valid(_bm) and _bm.get("hero") != null:
		human_ids[int(_bm.hero.get_instance_id())] = true
	for h in heroes:
		if not is_instance_valid(h):
			continue
		var id := int(h.get_instance_id())
		if human_ids.has(id):
			continue
		var k := int(h.kills)
		var d := int(h.deaths)
		var prev: Array = _stat.get(id, [k, d])
		var pk: int = int(prev[0])
		var pd: int = int(prev[1])
		_stat[id] = [k, d]
		if k > pk and _can_speak(h):
			var ctx_k := _contextual_line(h)
			if int(h.team) == Config.player_team:
				_say_later(h, ctx_k if ctx_k != "" else str(LINES_KILL[randi() % LINES_KILL.size()]), randf_range(0.3, 1.0))
			else:
				_say_later(h, str(LINES_ENEMY_TAUNT[randi() % LINES_ENEMY_TAUNT.size()]), randf_range(0.3, 1.0))
		if d > pd and _can_speak(h) and int(h.team) == Config.player_team:
			_say_later(h, str(LINES_DIED[randi() % LINES_DIED.size()]), randf_range(0.5, 1.4))
	if _bm != null and is_instance_valid(_bm) and _bm.get("hero") != null:
		var me = _bm.hero
		var id2 := int(me.get_instance_id())
		_stat[id2] = [int(me.kills), int(me.deaths)]


func _tick_ai(delta: float) -> void:
	# 延迟台词：到点的直接说，没到点的留到下一帧
	var now := Time.get_ticks_msec() / 1000.0
	var keep: Array = []
	for p in _pending:
		if now >= float(p["t"]):
			var h = p["hero"]
			if is_instance_valid(h):
				_say(h, str(p["text"]), bool(p.get("force", false)))
		else:
			keep.append(p)
	_pending = keep
	_ambient_t += delta
	if _ambient_t >= _ambient_next:
		_ambient_t = 0.0
		_ambient_next = randf_range(AMBIENT_MIN, AMBIENT_MAX)
		_ambient_line()
	# 行为意图变化：AI 说一句和它接下来要做的事一致的话
	_intent_t += delta
	if _intent_t >= 2.5:
		_intent_t = 0.0
		_announce_intent()
	# 整分钟：随机一位 AI 英雄说一句「结合局势」的高质量台词（优先大模型）
	if _bm != null and is_instance_valid(_bm):
		var minute := int(float(_bm.get("game_time")) / 60.0)
		if minute != _last_minute:
			_last_minute = minute
			if minute >= 1:
				_minute_llm_line()


func _ambient_line() -> void:
	var speakers := _ai_speakers()
	if speakers.is_empty():
		return
	var h = speakers[randi() % speakers.size()]
	# 优先说和它当前行为一致的话（清线/刷野/追击/回城/守塔…）
	var it := _ai_intent(h)
	if not it.is_empty() and randf() < 0.65:
		var il := _doing_line(h, it) if randf() < 0.5 else _intent_line(h, it)
		if il != "":
			_say(h, il)
			return
	# 70% 优先说与当前局势相关的话（残血/龙/推塔/人数差/玩家状态）
	if randf() < 0.7:
		var ctx := _contextual_line(h)
		if ctx != "":
			_say(h, ctx)
			return
	var pool: Array = LINES_AMBIENT
	if int(h.team) != Config.player_team:
		pool = LINES_ENEMY
	else:
		var diff := _kill_diff()
		if diff >= 5:
			pool = LINES_AHEAD
		elif diff <= -5:
			pool = LINES_BEHIND
	_say(h, str(pool[randi() % pool.size()]))


## AI 当前真实意图（来自 HeroAI.behavior_intent）
func _ai_intent(h) -> Dictionary:
	if h == null or not is_instance_valid(h):
		return {}
	for c in h.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("HeroAI.gd"):
			if c.has_method("behavior_intent"):
				var it = c.call("behavior_intent")
				if it is Dictionary:
					return it
	return {}


func _intent_text(it: Dictionary) -> String:
	var kind := str(it.get("kind", ""))
	var tgt := str(it.get("target", ""))
	match kind:
		"push":
			return "带线推进"
		"farm":
			return "清线发育"
		"jungle":
			return "刷野"
		"chase":
			return "追击" + (tgt if tgt != "" else "敌人")
		"kill":
			return "收残血" + (tgt if tgt != "" else "")
		"retreat":
			return "残血撤退"
		"recall":
			return "回城补状态"
		"defend":
			return "回防守塔"
		"rotate":
			return "游走支援"
		"avoid":
			return "避战绕后"
		"fight":
			return "正面接战"
		"dead":
			return "等待复活"
	return "带线"


## 当前正在做的事（比“接下来打算”更即时：回城/读条/追击/刷野/补刀…）
func _doing_line(h, it: Dictionary) -> String:
	if h == null or not is_instance_valid(h):
		return ""
	if bool(h.is_dead):
		return _pick(LINES_DOING_DEAD)
	if bool(h.get("casting_skill")):
		return _pick(LINES_DOING_CAST)
	if bool(h.is_recalling):
		return _pick(LINES_DOING_RECALL)
	var pool: Array = []
	match str(it.get("kind", "")):
		"push": pool = LINES_DOING_PUSH
		"farm": pool = LINES_DOING_FARM
		"jungle": pool = LINES_DOING_JUNGLE
		"chase": pool = LINES_DOING_CHASE
		"kill": pool = LINES_DOING_KILL
		"retreat": pool = LINES_DOING_RETREAT
		"recall": pool = LINES_DOING_RECALL
		"defend": pool = LINES_DOING_DEFEND
		"rotate": pool = LINES_DOING_ROTATE
		"avoid": pool = LINES_DOING_AVOID
		"dead": pool = LINES_DOING_DEAD
	if pool.is_empty():
		return ""
	return _pick(pool)


## 当前动作文本（喂给大模型，让它既能说正在做、也能说接下来）
func _doing_text(h, it: Dictionary) -> String:
	if h == null or not is_instance_valid(h):
		return "在行动"
	if bool(h.is_dead):
		return "已阵亡，正在等复活"
	if bool(h.get("casting_skill")):
		return "正在施放技能/读条"
	if bool(h.is_recalling):
		return "正在回城"
	if bool(h.is_teleporting):
		return "正在传送/游走"
	var k := str(it.get("kind", ""))
	match k:
		"push": return "正在清线推塔"
		"farm": return "正在清线发育"
		"jungle": return "正在刷野"
		"chase": return "正在追击敌人"
		"kill": return "正在收残血"
		"retreat": return "正在残血撤退"
		"defend": return "正在回防守塔"
		"rotate": return "正在游走支援"
		"avoid": return "正在避战找位置"
	return "正在带线"


func _intent_line(h, it: Dictionary) -> String:
	var pool: Array = []
	match str(it.get("kind", "")):
		"push":
			pool = LINES_INTENT_PUSH
		"farm":
			pool = LINES_INTENT_FARM
		"jungle":
			pool = LINES_INTENT_JUNGLE
		"chase":
			pool = LINES_INTENT_CHASE
		"kill":
			pool = LINES_INTENT_KILL
		"retreat":
			pool = LINES_INTENT_RETREAT
		"recall":
			pool = LINES_INTENT_RECALL
		"defend":
			pool = LINES_INTENT_DEFEND
		"rotate":
			pool = LINES_INTENT_ROTATE
		"avoid":
			pool = LINES_INTENT_AVOID
	if pool.is_empty():
		return ""
	return _pick(pool)


## 意图变化时播报（同一英雄 14s 内最多一句，避免刷屏）
func _announce_intent() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for h in _ai_speakers():
		var it := _ai_intent(h)
		if it.is_empty():
			continue
		var kind := str(it.get("kind", ""))
		if kind in ["dead", "fight"]:
			continue
		var id := int(h.get_instance_id())
		if str(_last_intent.get(id, "")) == kind:
			continue
		_last_intent[id] = kind
		if now - float(_intent_said.get(id, -99.0)) < 14.0:
			continue
		if randf() > 0.55:
			continue
		var line := _doing_line(h, it) if randf() < 0.45 else _intent_line(h, it)
		if line == "":
			continue
		_intent_said[id] = now
		_say(h, line)


## 当前是否处于真实对局（单机 host / 联机客户端接管后）；大厅与回放不播英雄语音
func _hero_voice_active_battle() -> bool:
	if _bm != null and is_instance_valid(_bm) and _bm.get("hero") != null:
		return true
	var nc = get_tree().get_first_node_in_group("net_client_battle")
	if nc != null and is_instance_valid(nc):
		return int(nc.get("_state")) == 1 and bool(nc.get("_owned"))
	return false


## 世界坐标是否在屏幕内（英雄语音只播屏幕中的英雄）
func _hero_point_visible(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var wp: Vector3 = pos + Vector3.UP * 1.2
	if not cam.is_position_in_frustum(wp):
		return false
	return get_viewport().get_visible_rect().grow(80.0).has_point(cam.unproject_position(wp))


## 播放英雄语音：音量按与相机的距离衰减（6m 内满音量，44m 外 -24dB）
func _hero_voice_at(text: String, speaker: String, pos: Vector3) -> void:
	if text == "":
		return
	var db := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d: float = cam.global_position.distance_to(pos)
		db = lerpf(0.0, -24.0, clampf((d - 6.0) / 38.0, 0.0, 1.0))
	var vs = get_node_or_null("/root/VoiceService")
	if vs != null:
		vs.call("speak", text, speaker, db)


## 英雄自己的台词池：优先不重复上一句（每个英雄单独记）
func _hero_pick_line(hero_name: String, pool: Array) -> String:
	if pool.is_empty():
		return ""
	var last := str(_hero_line_last.get(hero_name, ""))
	var use: Array = []
	for x in pool:
		if str(x) != last:
			use.append(x)
	if use.is_empty():
		use = pool
	var line := str(use[randi() % use.size()])
	_hero_line_last[hero_name] = line
	return line


## 大招台词（由 Hero._finish_casting 的 3 技能调用；只播屏幕内）
func hero_voice_ult(hero_name: String, pos: Vector3) -> void:
	if not _hero_voice_active_battle():
		return
	if not _hero_point_visible(pos):
		return
	var now := Time.get_ticks_msec() * 0.001
	var id := hero_name
	if now - float(_hero_ult_last.get(id, -99.0)) < 1.5:
		return
	_hero_ult_last[id] = now
	var pool: Array = HERO_VOICE_LINES.get(hero_name, [])
	if pool.is_empty():
		pool = HERO_VOICE_FALLBACK
	var line := _hero_pick_line(hero_name, pool)
	_hero_voice_at(line, hero_name, pos)


## 每隔一段时间：屏幕内每位英雄各自到点播一句（全局 8 秒最小间隔，避免叠音）
func _tick_hero_voice(delta: float) -> void:
	_hero_voice_t += delta
	if _hero_voice_t < 0.5:
		return
	_hero_voice_t = 0.0
	if not _hero_voice_active_battle():
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - _hero_voice_global_last < 8.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rect := get_viewport().get_visible_rect().grow(80.0)
	# 主机：遍历真实 Hero 节点；联机客户端：由 NetClientBattle 提供屏幕内英雄视图
	var targets: Array = []
	if _bm != null and is_instance_valid(_bm) and _bm.get("hero") != null:
		targets = get_tree().get_nodes_in_group("heroes")
	else:
		var nc = get_tree().get_first_node_in_group("net_client_battle")
		if nc != null and is_instance_valid(nc):
			targets = nc.call("visible_voice_targets")
	for t in targets:
		var nm := ""
		var role := ""
		var pos := Vector3.ZERO
		var key := ""
		if t is Node:
			if not is_instance_valid(t) or float(t.get("health")) <= 0.0:
				continue
			nm = str(t.display_name)
			role = str(t.get("role"))
			pos = t.global_position
			key = str(t.get_instance_id())
		elif t is Dictionary:
			nm = str(t.get("name", ""))
			role = str(t.get("role", ""))
			pos = t.get("pos", Vector3.ZERO)
			key = "n:" + nm + ":" + str(int(hash(str(pos))))
		if nm == "":
			continue
		var wp: Vector3 = pos + Vector3.UP * 1.2
		if not cam.is_position_in_frustum(wp):
			continue
		if not rect.has_point(cam.unproject_position(wp)):
			continue
		if not _hero_voice_next.has(key):
			_hero_voice_next[key] = now + randf_range(10.0, 30.0)
			continue
		if now < float(_hero_voice_next[key]):
			continue
		_hero_voice_next[key] = now + randf_range(35.0, 65.0)
		var pool: Array = HERO_VOICE_LINES.get(nm, [])
		if pool.is_empty():
			pool = VOICE_AMBIENT_BY_ROLE.get(role, VOICE_AMBIENT_DEFAULT)
		var text := _hero_pick_line(nm, pool)
		_hero_voice_at(text, nm, pos)
		_hero_voice_global_last = now
		break


## 读取当前局势：塔数、龙、金币差、双方站位人数、玩家状态、自身血量
func _situation(h) -> Dictionary:
	var st := {
		"minute": 0, "kill_diff": 0, "my_towers": 0, "foe_towers": 0,
		"my_tower_hp_min": 1.0, "foe_tower_hp_min": 1.0,
		"player_dead": false, "player_hp": 1.0, "player_near_allies": 0, "player_near_enemies": 0,
		"player_deep": false, "near_allies": 0, "near_enemies": 0,
		"gold_diff": 0, "obj": "", "obj_t": 999.0, "self_hp": 1.0,
	}
	if h == null or not is_instance_valid(h):
		return st
	st.self_hp = float(h.health) / maxf(1.0, float(h.actual_max_health))
	if _bm == null or not is_instance_valid(_bm):
		return st
	st.minute = int(float(_bm.get("game_time")) / 60.0)
	st.kill_diff = _kill_diff()
	# 塔
	for t in get_tree().get_nodes_in_group("turrets"):
		if not is_instance_valid(t) or float(t.health) <= 0.0:
			continue
		var tt := int(t.team)
		var ratio: float = float(t.health) / maxf(1.0, float(t.max_health))
		if tt == Config.player_team:
			st.my_towers += 1
			st.my_tower_hp_min = minf(st.my_tower_hp_min, ratio)
		else:
			st.foe_towers += 1
			st.foe_tower_hp_min = minf(st.foe_tower_hp_min, ratio)
	# 玩家 & 站位
	var ph = _bm.get("hero")
	if ph != null and is_instance_valid(ph):
		st.player_dead = float(ph.health) <= 0.0
		st.player_hp = float(ph.health) / maxf(1.0, float(ph.actual_max_health))
		var pp: Vector3 = ph.global_position
		for a in get_tree().get_nodes_in_group("heroes"):
			if not is_instance_valid(a) or a == ph:
				continue
			if pp.distance_to(a.global_position) <= 16.0:
				if int(a.team) == Config.player_team:
					st.player_near_allies += 1
				else:
					st.player_near_enemies += 1
		# 深入敌方半场：沿对角推进，超过 55 且身边没队友
		st.player_deep = (pp.x + pp.z) * (1.0 if Config.player_team == 0 else -1.0) > 110.0 and st.player_near_allies == 0
	if h != null and is_instance_valid(h):
		for a in get_tree().get_nodes_in_group("heroes"):
			if not is_instance_valid(a) or a == h:
				continue
			if h.global_position.distance_to(a.global_position) <= 16.0:
				if int(a.team) == int(h.team):
					st.near_allies += 1
				else:
					st.near_enemies += 1
	st.gold_diff = int(float(_bm.get("team_player_gold"))) - int(float(_bm.get("team_enemy_gold")))
	# 大龙/主宰
	var ty_t: float = float(_bm.get("tyrant_timer")) if _bm.get("tyrant_timer") != null else 999.0
	var dr_t: float = float(_bm.get("dragon_timer")) if _bm.get("dragon_timer") != null else 999.0
	# 大龙 4 分钟才刷；开局计时器为 0 时不要误报
	if int(st.minute) >= 3:
		if bool(_bm.get("tyrant_alive")):
			st.obj = "tyrant"
		elif bool(_bm.get("dragon_alive")):
			st.obj = "dragon"
		elif ty_t > 0.0 and ty_t <= 45.0:
			st.obj = "tyrant"; st.obj_t = ty_t
		elif dr_t > 0.0 and dr_t <= 45.0:
			st.obj = "dragon"; st.obj_t = dr_t
	return st


## 按局势挑一句最贴合当前情况的台词；没有合适情景返回 ""
func _contextual_line(h) -> String:
	var st := _situation(h)
	if not st.is_empty():
		if float(st.self_hp) < 0.25 and int(st.near_enemies) > 0:
			return _pick(LINES_LOW_HP)
		if bool(st.player_dead):
			return _pick(LINES_DEAD_WAIT)
		if float(st.player_hp) < 0.26 and not bool(st.player_dead):
			return _pick(LINES_PLAYER_LOW)
		if bool(st.player_deep):
			return _pick(LINES_OVEREXTEND)
		if int(st.player_near_enemies) >= 2 and int(st.player_near_allies) <= 1:
			return _pick(LINES_NUMBERS)
		if int(st.player_near_allies) >= 2 and int(st.player_near_enemies) == 1:
			return _pick(LINES_OUTNUMBER)
		if str(st.obj) != "":
			if float(st.obj_t) > 0.0:
				return _pick(LINES_OBJ_SOON)
			return _pick(LINES_OBJ_UP)
		if float(st.foe_tower_hp_min) < 0.22 and int(st.near_enemies) == 0:
			return _pick(LINES_TOWER_PUSH)
		if float(st.my_tower_hp_min) < 0.22:
			return _pick(LINES_DEFEND)
		if int(st.near_allies) == 0 and int(st.near_enemies) >= 2:
			return _pick(LINES_NUMBERS)
		if int(st.kill_diff) >= 8:
			return _pick(LINES_AHEAD)
		if int(st.kill_diff) <= -8:
			return _pick(LINES_BEHIND)
		if int(st.near_allies) >= 1 and int(st.self_hp) < 0.5:
			return _pick(LINES_SUPPORT)
	return ""


func _pick(pool: Array) -> String:
	if pool.is_empty():
		return ""
	# 避免短时间重复同一句
	var fresh: Array = []
	for x in pool:
		if not _recent_lines.has(x):
			fresh.append(x)
	var use: Array = fresh if not fresh.is_empty() else pool
	var line := str(use[randi() % use.size()])
	_recent_lines.append(line)
	if _recent_lines.size() > 8:
		_recent_lines.pop_front()
	return line


## 玩家状态变化（被蹲/残血/阵亡/拿人头）时，AI 队友或对手补一句
func _scan_player_reactions() -> void:
	if _bm == null or not is_instance_valid(_bm):
		return
	var ph = _bm.get("hero")
	if ph == null or not is_instance_valid(ph):
		return
	var pk := int(ph.kills)
	var dead: bool = float(ph.health) <= 0.0
	var hp_ratio: float = float(ph.health) / maxf(1.0, float(ph.actual_max_health))
	var speakers := _ai_speakers()
	if speakers.is_empty():
		return
	# 玩家拿人头：队友夸一句（对方阵营则嘴硬）
	if pk > int(_player_last.get("kills", 0)) and _can_speak(ph):
		var ally_h = null
		for a in speakers:
			if is_instance_valid(a) and int(a.team) == Config.player_team:
				ally_h = a
				break
		if ally_h != null:
			_say_later(ally_h, _pick(LINES_KILL_AHEAD), randf_range(0.3, 0.8))
		else:
			var foe_h = speakers[randi() % speakers.size()]
			if int(foe_h.team) != Config.player_team:
				_say_later(foe_h, _pick(LINES_KILL_ENEMY), randf_range(0.4, 1.0))
	_player_last["kills"] = pk
	# 玩家阵亡：队友劝稳
	if dead and not bool(_player_last.get("dead", false)):
		var ally2 = null
		for a in speakers:
			if is_instance_valid(a) and int(a.team) == Config.player_team:
				ally2 = a
				break
		if ally2 != null:
			_say_later(ally2, _pick(LINES_DEAD_WAIT), randf_range(0.6, 1.6))
	# 玩家残血警告（20 秒冷却一次）
	var now := Time.get_ticks_msec() / 1000.0
	_player_last["low_cd"] = maxf(0.0, float(_player_last.get("low_cd", 0.0)) - 1.0)
	if hp_ratio < 0.28 and not dead and not bool(_player_last.get("low", false)) 			and float(_player_last.get("low_cd", 0.0)) <= 0.0:
		_player_last["low_cd"] = 20.0
		var ally3 = null
		for a in speakers:
			if is_instance_valid(a) and int(a.team) == Config.player_team:
				ally3 = a
				break
		if ally3 != null:
			_say_later(ally3, _pick(LINES_PLAYER_LOW), randf_range(0.5, 1.2))
	_player_last["low"] = hp_ratio < 0.28
	_player_last["dead"] = dead


## 每分钟一次：挑一位 AI 英雄，结合局势让大模型说一句高质量台词；没有大模型则用情境台词兜底
func _minute_llm_line() -> void:
	var speakers := _ai_speakers()
	if speakers.is_empty():
		return
	var h = speakers[_minute_idx % speakers.size()]
	_minute_idx += 1
	var st := _situation(h)
	if _llm != null and bool(_llm.get("enabled")):
		var who = h
		var sys := _minute_system_prompt(h, st)
		var usr := _minute_user_prompt(h, st)
		var ok: bool = _llm.call("ask", sys, usr,
			func(reply: String) -> void:
				var line := _sanitize_llm_line(reply)
				if line == "":
					_say_later_force(who, _fallback_minute_line(who), randf_range(0.6, 1.4))
				else:
					_say_later_force(who, line, randf_range(0.4, 1.0)))
		if ok:
			return
	_say_later_force(h, _fallback_minute_line(h), randf_range(0.6, 1.5))


func _persona_of(h) -> String:
	var names := ["稳健", "激进", "冷静", "话痨", "幽默", "护短"]
	return names[int(abs(hash(str(h.display_name)))) % names.size()]


func _minute_system_prompt(h, st: Dictionary) -> String:
	return ("你是手机 MOBA《王者荣耀》对局中的 AI 队友，操控英雄「%s」（%s，性格%s）。"
		+ "现在第 %d 分钟，请主动在队伍频道说一句 8~20 字的中文，像真人玩家："
		+ "结合当前局势给队友一个具体建议或一句带情绪的话（催推进/提醒撤退/约龙/护人/吐槽都行），"
		+ "必须和你当前正在做、或接下来真正要做的事一致（例如正在清线/刷野/回城/追击，就说正在做；准备回城/追人/刷野，就说接下来要去做）。"
		+ "不要复述数字、不要自我介绍、不要自称 AI 或模型，不要引号、括号、换行，只输出这一句话。") % [
		str(h.display_name), str(h.role), _persona_of(h), int(st.get("minute", 0))]


func _minute_user_prompt(h, st: Dictionary) -> String:
	var obj_txt := "无大型资源"
	if str(st.get("obj", "")) == "tyrant":
		obj_txt = "主宰已刷新" if float(st.get("obj_t", 0.0)) <= 0.0 else "主宰快刷新"
	elif str(st.get("obj", "")) == "dragon":
		obj_txt = "暴君已刷新" if float(st.get("obj_t", 0.0)) <= 0.0 else "暴君快刷新"
	var player_txt := "玩家已阵亡" if bool(st.get("player_dead", false)) else ("玩家血量偏低" if float(st.get("player_hp", 1.0)) < 0.3 else "玩家状态正常")
	var lines := "、".join(_recent_lines.slice(maxi(0, _recent_lines.size() - 3)))
	var it_m := _ai_intent(h)
	var intent_txt := _intent_text(it_m)
	var doing_txt := _doing_text(h, it_m)
	return ("局势：我方塔%d/敌方塔%d，金币差%+d，%s，%s；你自己血量%d%%，身边敌人%d个。你当前正在：%s；接下来打算：%s。最近说过：%s。可以说正在做的事，也可以说接下来要做什么；换一种说法，别重复。") % [
		int(st.get("my_towers", 0)), int(st.get("foe_towers", 0)), int(st.get("gold_diff", 0)),
		player_txt, obj_txt, int(round(float(st.get("self_hp", 1.0)) * 100.0)),
		int(st.get("near_enemies", 0)), doing_txt, intent_txt, lines if lines != "" else "无"]


func _sanitize_llm_line(raw: String) -> String:
	var t := str(raw).replace("\n", " ").replace("\r", " ").replace("\t", " ")
	t = t.strip_edges()
	# 去掉引号/括号包裹与「英雄：」前缀
	t = t.trim_prefix("「").trim_suffix("」").trim_prefix("“").trim_suffix("”")
	t = t.trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"")
	t = t.trim_prefix("（").trim_suffix("）").trim_prefix("(").trim_suffix(")")
	if t.find("：") >= 0 and t.find("：") <= 8:
		t = t.substr(t.find("：") + 1)
	t = t.replace("\n", " ").strip_edges()
	while t.find("  ") >= 0:
		t = t.replace("  ", " ")
	# 拒绝自曝 AI / 空话
	if t.find("AI") >= 0 or t.find("模型") >= 0 or t.find("助手") >= 0:
		return ""
	if t.length() > 30:
		t = t.substr(0, 30)
	return t


func _fallback_minute_line(h) -> String:
	var it := _ai_intent(h)
	if not it.is_empty():
		var il := _doing_line(h, it) if randf() < 0.5 else _intent_line(h, it)
		if il != "":
			return il
	var ctx := _contextual_line(h)
	if ctx != "":
		return ctx
	var diff := _kill_diff()
	if int(h.team) == Config.player_team:
		if diff >= 5:
			return _pick(LINES_AHEAD)
		elif diff <= -5:
			return _pick(LINES_BEHIND)
		return _pick(LINES_AMBIENT)
	return _pick(LINES_ENEMY)


func _reply_to_player(text: String) -> void:
	# 喊灵宝就由小精灵回，不走队友 AI
	if text.find("灵宝") >= 0:
		_lingbao_reply(text)
		return
	var speakers := _ai_speakers()
	if speakers.is_empty():
		return
	var h = speakers[randi() % speakers.size()]
	# 配了大模型 key 就让模型来回（异步，失败自动退回本地台词库）
	if _llm != null and bool(_llm.get("enabled")):
		var who = h
		var ok: bool = _llm.call("ask", _llm_system_prompt(h), _llm_user_prompt(text),
			func(reply: String) -> void:
				if reply.strip_edges() == "":
					_say_later(who, str(LINES_REPLY[randi() % LINES_REPLY.size()]), 0.3)
				else:
					_say_later(who, reply, 0.3))
		if ok:
			return
	# 本地兜底：关键词命中且随机通过才回
	if text.find("集合") < 0 and text.find("推") < 0 and text.find("撤退") < 0 \
			and text.find("龙") < 0 and text.find("小心") < 0 and text.find("打") < 0:
		return
	if randf() > 0.65:
		return
	_say_later(h, str(LINES_REPLY[randi() % LINES_REPLY.size()]), randf_range(0.7, 1.8))


func _llm_system_prompt(h) -> String:
	var mins := 0
	if _bm != null and is_instance_valid(_bm):
		mins = int(float(_bm.get("game_time")) / 60.0)
	var diff := _kill_diff()
	var mine := 0
	var foe := 0
	for x in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(x):
			continue
		if int(x.team) == Config.player_team:
			mine += int(x.kills)
		else:
			foe += int(x.kills)
	var stance := "我方人头领先" if diff > 0 else ("我方人头落后" if diff < 0 else "双方人头持平")
	# 把具体局势塞进提示词，让回复贴合当前局面（塔/龙/玩家状态/金币差）
	var st := _situation(h)
	var obj_txt := ""
	if str(st.get("obj", "")) == "tyrant":
		obj_txt = "主宰已刷新" if float(st.get("obj_t", 0.0)) <= 0.0 else "主宰即将刷新"
	elif str(st.get("obj", "")) == "dragon":
		obj_txt = "暴君已刷新" if float(st.get("obj_t", 0.0)) <= 0.0 else "暴君即将刷新"
	var player_txt := "玩家已阵亡（等你复活）" if bool(st.get("player_dead", false)) else (
		"玩家血量偏低" if float(st.get("player_hp", 1.0)) < 0.3 else "玩家状态正常")
	var sit := "我方塔%d座/敌方塔%d座，金币差%+d，%s，%s" % [
		int(st.get("my_towers", 0)), int(st.get("foe_towers", 0)), int(st.get("gold_diff", 0)),
		player_txt, obj_txt if obj_txt != "" else "暂无大型资源"]
	return ("你是手机 MOBA 游戏《王者荣耀》里的 AI 队友，本局操控英雄「%s」，%s。"
		+ "玩家在队伍频道发言，你要用一句中文口语回他：8~20 字，像真人玩家，"
		+ "可以结合当前局势给战术建议或带点情绪，不要自称 AI/模型，不要输出引号、括号或换行，只输出这一句话。"
		+ "当前第 %d 分钟，%s（我方 %d 杀，敌方 %d 杀）。局势：%s。") % [
		str(h.display_name), "队友" if int(h.team) == Config.player_team else "对手",
		mins, stance, mine, foe, sit]


func _llm_user_prompt(text: String) -> String:
	var nm := NameStore.player_name()
	if nm == "":
		nm = "玩家"
	return "玩家「%s」：%s" % [nm, text]


func _is_ai_speaker_name(nm: String) -> bool:
	if nm == "":
		return false
	for h in get_tree().get_nodes_in_group("heroes"):
		if is_instance_valid(h) and str(h.display_name) == nm and bool(h.get("is_ai")):
			return true
	return false


func _ai_speakers() -> Array:
	var out: Array = []
	var me := _local_hero_id()
	var human_ids := {}
	if is_instance_valid(NetSession):
		var ap = NetSession.get("_assign_peer")
		if ap is Dictionary:
			for k in ap.keys():
				human_ids[int(k)] = true
	for h in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(h):
			continue
		if h.health <= 0:
			continue
		var hid := int(h.get_instance_id())
		if hid == me or human_ids.has(hid):
			continue
		out.append(h)
	return out


func _local_hero_id() -> int:
	if _bm != null and is_instance_valid(_bm) and _bm.get("hero") != null:
		return int(_bm.hero.get_instance_id())
	return -1


func _kill_diff() -> int:
	var mine := 0
	var foe := 0
	for h in get_tree().get_nodes_in_group("heroes"):
		if not is_instance_valid(h):
			continue
		if int(h.team) == Config.player_team:
			mine += int(h.kills)
		else:
			foe += int(h.kills)
	return mine - foe


func _can_speak(h) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return now - _last_ai_t >= AI_MIN_GAP


func _say_later(h, text: String, delay: float) -> void:
	_pending.append({"t": Time.get_ticks_msec() / 1000.0 + delay, "hero": h, "text": text})


func _say_later_force(h, text: String, delay: float) -> void:
	_pending.append({"t": Time.get_ticks_msec() / 1000.0 + delay, "hero": h, "text": text, "force": true})


func _say(h, text: String, force: bool = false) -> void:
	if not is_instance_valid(h):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _last_ai_t < AI_MIN_GAP:
		return
	_last_ai_t = now
	var nm := str(h.display_name)
	if nm == "":
		nm = "队友"
	# AI 发言统一先说身份，再进入聊天/TTS/联机广播，保证三端文本一致
	var line := str(text).strip_edges()
	if line != "" and not line.begins_with("我是") and not line.begins_with(nm):
		line = "我是%s，%s" % [nm, line]
	_post(nm, int(h.team), line, false)
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.broadcast_chat(nm, int(h.team), line)


# ---------------- 内部：语音 ----------------

const VOICE_PS := """
try {
  Add-Type -AssemblyName System.Speech
  $list = [System.Speech.Recognition.SpeechRecognitionEngine]::InstalledRecognizers()
  $ri = $list | Where-Object { $_.Culture.Name -eq 'zh-CN' } | Select-Object -First 1
  if ($ri -eq $null) { $ri = $list | Where-Object { $_.Culture.Name -like 'zh*' } | Select-Object -First 1 }
  if ($ri -eq $null) { Write-Output 'ERR:未安装中文语音识别，去 设置-时间和语言-语音 添加中文'; return }
  $r = $null
  try { $r = New-Object System.Speech.Recognition.SpeechRecognitionEngine($ri) }
  catch { $r = New-Object System.Speech.Recognition.SpeechRecognitionEngine([System.Globalization.CultureInfo]::GetCultureInfo('zh-CN')) }
  $r.SetInputToDefaultAudioDevice()
  $r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
  $res = $r.Recognize([TimeSpan]::FromSeconds(6))
  if ($res -ne $null) { Write-Output $res.Text.Trim() } else { Write-Output 'EMPTY' }
} catch { Write-Output ('ERR:' + $_.Exception.Message) }
"""

func _voice_worker() -> void:
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", VOICE_PS], out, true)
	_voice_lines = out
	_voice_done = true


func _tick_voice() -> void:
	if _voice_thread == null or not _voice_done:
		return
	_voice_thread.wait_to_finish()
	_voice_thread = null
	_voice_done = false
	var text := ""
	var err := ""
	for line in _voice_lines:
		var s := str(line).strip_edges()
		if s == "":
			continue
		if s.begins_with("ERR:"):
			err = s.substr(4)
		else:
			text = s
	_voice_lines = []
	if text == "EMPTY":
		text = ""
	if text != "":
		# 只回填输入框，玩家确认后再发（避免识别错就广播出去）
		if _box != null and is_instance_valid(_box):
			_box.call("fill_input", text)
		else:
			_post(str(NameStore.player_name() if NameStore.player_name() != "" else "我"),
				Config.player_team, text, true)
	elif err != "":
		system_note("语音识别不可用：%s" % err.substr(0, 60))
	else:
		system_note("没听清，再试一次")
