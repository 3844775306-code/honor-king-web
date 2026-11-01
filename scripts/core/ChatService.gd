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


func _ready() -> void:
	set_process(true)
	if is_instance_valid(NetSession):
		NetSession.net_chat.connect(_on_net_chat)
	_llm = preload("res://scripts/core/LLMChat.gd").new()
	add_child(_llm)


func _process(delta: float) -> void:
	_ensure_ui()
	_tick_voice()
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
			if int(h.team) == Config.player_team:
				_say_later(h, str(LINES_KILL[randi() % LINES_KILL.size()]), randf_range(0.3, 1.0))
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
				_say(h, str(p["text"]))
		else:
			keep.append(p)
	_pending = keep
	_ambient_t += delta
	if _ambient_t >= _ambient_next:
		_ambient_t = 0.0
		_ambient_next = randf_range(AMBIENT_MIN, AMBIENT_MAX)
		_ambient_line()


func _ambient_line() -> void:
	var speakers := _ai_speakers()
	if speakers.is_empty():
		return
	var h = speakers[randi() % speakers.size()]
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
	return ("你是手机 MOBA 游戏《王者荣耀》里的 AI 队友，本局操控英雄「%s」，%s。"
		+ "玩家在队伍频道发言，你要用一句中文口语回他：8~20 字，像真人玩家，"
		+ "可以给战术建议或带点情绪，不要自称 AI/模型，不要输出引号、括号或换行，只输出这一句话。"
		+ "当前第 %d 分钟，%s（我方 %d 杀，敌方 %d 杀）。") % [
		str(h.display_name), "队友" if int(h.team) == Config.player_team else "对手",
		mins, stance, mine, foe]


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


func _say(h, text: String) -> void:
	if not is_instance_valid(h):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_ai_t < AI_MIN_GAP:
		return
	_last_ai_t = now
	var nm := str(h.display_name)
	if nm == "":
		nm = "队友"
	_post(nm, int(h.team), text, false)
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.broadcast_chat(nm, int(h.team), text)


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
