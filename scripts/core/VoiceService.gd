extends Node
## 语音播报：把 AI 聊天 / 灵宝说话读出来，并尽量做得「灵动」。
## - 有系统 TTS（Windows SAPI / macOS / Linux）：按标点/情绪词分句，每句单独调整音高、语速、
##   音量（问句上扬、感叹提高、省略号放慢、笑声加快…）；同角色多音色轮换
## - 无 TTS 或没有中文音色：拟声语音带语调曲线（问句上扬/感叹更亮/省略号拖长），不是单调嘀声

var enabled := true
var _ok := false
var _has_zh := false
var _voice := ""
var _voice_pool: Array = []   # 可用中文音色 id（声线轮换）
var _voice_pool_female: Array = []
var _voice_pool_male: Array = []
# 女性英雄（其余为男性）；灵宝为女声
const FEMALE_HEROES := {
	"孙尚香": true, "不知火舞": true, "甄姬": true, "安琪拉": true, "妲己": true,
	"小乔": true, "王昭君": true, "沈梦溪": true,
}
const FEMALE_VOICE_KEYS := ["xiaoxiao", "xiaoyi", "huihui", "yaoyao", "female", "woman", "女"]
const MALE_VOICE_KEYS := ["yunxi", "yunjian", "yunyang", "kangkang", "male", "man", "男"]
var _lang := ""
var _fallback_blip := false
var _utt := 0
var _last_text := ""
var _last_ms := 0
var _blip: AudioStreamPlayer = null
var edge_enabled := true
var _edge: Node = null
var _edge_player: AudioStreamPlayer = null
var _edge_busy := false
var _edge_queue: Array = []
var _edge_seq := 0
var _edge_cur: Dictionary = {}
var _edge_cache: Dictionary = {}
var _edge_fail_streak := 0
var _edge_notice_shown := false
const EdgeScript = preload("res://scripts/core/EdgeTTS.gd")
const HttpTtsScript = preload("res://scripts/core/HttpTTS.gd")
const SapiScript = preload("res://scripts/core/SapiTTS.gd")
var _sapi: Node = null
var _sapi_enabled := true
var _diag_tail: Array = []
var _http_tts: Node = null
var _http_busy := false
var _http_queue: Array = []
var _http_seq := 0
var _http_cur: Dictionary = {}
var _http_cache: Dictionary = {}
var _online_mode := "edge"   # edge / http / local / browser
var _web_tts := false          # 浏览器原生 speechSynthesis（手机 Web 端优先，避免 MP3 解码成杂音）


func _ready() -> void:
	_blip = AudioStreamPlayer.new()
	_blip.name = "BlipVoice"
	_blip.bus = "Master"
	_blip.volume_db = 0.0
	add_child(_blip)
	_edge_player = AudioStreamPlayer.new()
	_edge_player.name = "EdgeVoice"
	_edge_player.bus = "Master"
	add_child(_edge_player)
	_edge = EdgeScript.new()
	_edge.name = "EdgeTTS"
	add_child(_edge)
	_sapi = SapiScript.new()
	_sapi.name = "SapiTTS"
	add_child(_sapi)
	_http_tts = HttpTtsScript.new()
	_http_tts.name = "HttpTTS"
	add_child(_http_tts)
	_http_tts.connect("done", Callable(self, "_on_http_done"))
	_http_tts.connect("failed", Callable(self, "_on_http_failed"))
	_edge.connect("done", Callable(self, "_on_edge_done"))
	_edge.connect("failed", Callable(self, "_on_edge_failed"))
	# 预热 Edge 连接：把首次 ~0.9s TLS/WS 握手提前到游戏启动后（失败会自动降级，不阻塞）
	get_tree().create_timer(0.6).timeout.connect(func():
		if _edge != null and edge_enabled and enabled:
			_edge.call("warmup"))
	_fallback_blip = true
	# 手机 Web：优先浏览器原生 speechSynthesis（音频由系统输出，彻底绕开 MP3 动画/解码在手机端的杂音）
	if OS.has_feature("web"):
		_web_tts = bool(JavaScriptBridge.eval("!!(window.speechSynthesis && window.SpeechSynthesisUtterance)", true))
		if _web_tts:
			_online_mode = "browser"
	# 原生手机：启用系统 TTS（Android/iOS 系统中文语音），避免在线 MP3 在手机解码器上出杂音
	var _native_mobile := Config.on_mobile() and not OS.has_feature("web")
	# 本地 TTS 走 Windows WinRT 语音合成（SAPI/WinRT SpeechSynthesis）。在没有中文语音包、
	# 精简版系统或受限环境下，引擎内部会抛 winrt::hresult_error 且未捕获，直接把进程打崩
	# （表现为「导出的 exe 双击打不开 / 一闪退」，headless 不崩是因为没有 TTS 设备）。
	# 因此本地 TTS 默认关闭、按需在 player_prefs 里把 op_tts_local 打开；语音播报仍走 Edge 在线语音。
	if not PlayerPrefs.opt_bool("tts_local", false) and not _native_mobile:
		if OS.is_debug_build():
			print("[VOICE] 本地 TTS 未启用（op_tts_local=false），跳过 WinRT 语音枚举")
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	if not DisplayServer.has_method("tts_speak") or not DisplayServer.has_method("tts_get_voices"):
		return
	_ok = true
	_pick_voices()
	_voice = "" if _voice_pool.is_empty() else str(_voice_pool[0])
	_fallback_blip = _voice == ""
	if _voice == "":
		_ok = false
	if _native_mobile and _ok:
		_online_mode = "local"   # 原生手机优先系统 TTS，不再走在线 MP3
	if OS.is_debug_build():
		print("[VOICE] init ", diagnose())


func _pick_voices() -> void:
	var voices: Array = DisplayServer.tts_get_voices()
	var zh: Array = []
	var zh_pref: Array = []
	for v in voices:
		var vid := str(v.get("id", ""))
		var lang := str(v.get("language", "")).to_lower()
		var nm := str(v.get("name", "")).to_lower()
		if vid == "":
			continue
		var is_zh: bool = lang.begins_with("zh") or lang.begins_with("cmn") or lang.begins_with("yue") \
			or nm.find("chinese") >= 0 or nm.find("huihui") >= 0 or nm.find("yaoyao") >= 0 \
			or nm.find("kangkang") >= 0 or nm.find("xiaoxiao") >= 0 or nm.find("yunxi") >= 0
		if is_zh:
			zh.append(vid)
			_lang = lang
			if nm.find("yaoyao") >= 0 or nm.find("xiaoxiao") >= 0 or nm.find("huihui") >= 0:
				zh_pref.append(vid)
	for v in zh_pref:
		if not zh.has(v):
			zh.append(v)
	_voice_pool = zh
	_voice_pool_female.clear()
	_voice_pool_male.clear()
	for v in voices:
		var vid2 := str(v.get("id", ""))
		if vid2 == "" or not zh.has(vid2):
			continue
		var nm2 := (str(v.get("name", "")) + " " + vid2).to_lower()
		var fem := false
		var mal := false
		for k in FEMALE_VOICE_KEYS:
			if nm2.find(k) >= 0: fem = true
		for k in MALE_VOICE_KEYS:
			if nm2.find(k) >= 0: mal = true
		if fem and not mal:
			_voice_pool_female.append(vid2)
		elif mal and not fem:
			_voice_pool_male.append(vid2)
	_has_zh = not zh.is_empty()


## 按角色性别选音色：女性英雄固定女声池、男性英雄固定男声池；灵宝女声
func _is_female(speaker: String) -> bool:
	return speaker == "灵宝" or FEMALE_HEROES.has(speaker)


func _voice_for(speaker: String) -> String:
	var pool: Array = _voice_pool_female if _is_female(speaker) else _voice_pool_male
	if pool.is_empty():
		pool = _voice_pool
	if pool.is_empty():
		return ""
	var idx: int = int(abs(hash(speaker)) % pool.size())
	return str(pool[idx])


## 朗读。speaker 区分声线；标点/情绪词改变音高语速；volume_db 为按距离衰减后的音量
func speak(text: String, speaker: String = "", volume_db: float = 0.0) -> void:
	if not enabled:
		return
	var clean := _clean(text)
	if clean == "":
		return
	var now := Time.get_ticks_msec()
	if clean == _last_text and now - _last_ms < 3000:
		return
	_last_text = clean
	_last_ms = now
	var emo := _emotion_params(clean, speaker)
	emo["vol_db"] = clampf(volume_db, -40.0, 6.0)
	if _online_mode == "browser" and _speak_web(clean, speaker, emo):
		return
	if _online_mode == "edge" and edge_enabled and _edge != null:
		_request_edge(clean, speaker, emo)
		return
	if _online_mode == "http" and _http_tts != null:
		_request_http(clean, speaker, emo)
		return
	_speak_local(clean, speaker, emo)


## 浏览器原生语音：手机 Web 端直接调用 speechSynthesis（无需 MP3 解码，不会出现杂音）
func _speak_web(clean: String, speaker: String, emo: Dictionary) -> bool:
	if not _web_tts:
		return false
	var txt := JSON.stringify(clean)
	var pitch := clampf(float(emo.get("pitch", 1.0)), 0.5, 2.0)
	var rate := clampf(float(emo.get("rate", 1.0)) * 0.95, 0.5, 2.0)
	var female := "true" if _is_female(speaker) else "false"
	var js := """(function(){try{
		var ss=window.speechSynthesis; if(!ss) return false;
		ss.cancel();
		var u=new SpeechSynthesisUtterance(%s);
		u.lang='zh-CN'; u.pitch=%f; u.rate=%f; u.volume=%f;
		try{
			var vs=(ss.getVoices()||[]).filter(function(v){return /^zh/i.test(v.lang||'');});
			var f=vs.find(function(v){return /(xiaoxiao|xiaoyi|huihui|yaoyao|female|女)/i.test(v.name||'');});
			var m=vs.find(function(v){return /(yunxi|yunjian|yunyang|kangkang|male|男)/i.test(v.name||'');});
			var pick=%s?f:m; if(!pick) pick=vs[0]; if(pick) u.voice=pick;
		}catch(e2){}
		ss.speak(u); return true;
	}catch(e){return false;}})()""" % [txt, pitch, rate, clampf(db_to_linear(float(emo.get("vol_db", 0.0))), 0.0, 1.0), female]
	return bool(JavaScriptBridge.eval(js, true))


## 本地 TTS / 拟声（Edge 不可用时的兜底）
func _speak_local(clean: String, speaker: String, emo: Dictionary) -> void:
	# Windows 本地 SAPI 兜底：网络音频不可用时至少能正确读出文字
	if _sapi_enabled and _sapi != null and _sapi.call("available"):
		var rate_i: int = clampi(int(round((float(emo.get("rate", 1.0)) - 1.0) * 10.0)), -5, 6)
		var sapi_vol: int = clampi(int(round(db_to_linear(float(emo.get("vol_db", 0.0))) * 100.0)), 0, 100)
		if _sapi.call("speak", clean, rate_i, _is_female(speaker), sapi_vol):
			diag("local sapi speak rate=%d text=%s" % [rate_i, clean.substr(0, 20)])
			return
	var clauses := _split_clauses(clean)
	if clauses.is_empty():
		return
	if _ok:
		var ids: Array = []
		for i in range(clauses.size()):
			var c: Dictionary = clauses[i]
			var prog: float = float(i) / maxf(1.0, float(clauses.size() - 1))
			var pitch: float = float(emo["pitch"]) + float(emo["pitch_curve"]) * prog
			var rate: float = float(emo["rate"]) + float(emo["rate_curve"]) * prog
			_utt += 1
			if _utt > 900000:
				_utt = 1
			var att: float = clampf(db_to_linear(float(emo.get("vol_db", 0.0))), 0.0, 1.0)
			var vol: int = clampi(int(round((float(emo["volume"]) + float(c.get("vol", 0))) * att)), 0, 100)
			DisplayServer.tts_speak(str(c["text"]), _voice_for(speaker), vol,
				clampf(pitch, 0.5, 2.0), clampf(rate, 0.5, 2.0), _utt, false)
			ids.append(_utt)
		if OS.is_debug_build():
			print("[VOICE] local tts clauses=", clauses.size(), " emo=", emo)
		if not ids.is_empty():
			_verify_tts(int(ids[ids.size() - 1]), clean, speaker)
	else:
		_blip_speak(clean, speaker, emo)
	if _edge != null:
		_edge.call("diag", "local speech tts_ok=%s text=%s" % [str(_ok), clean.substr(0, 20)])


## ---------------- Edge 在线神经语音 ----------------

func _edge_voice(speaker: String) -> String:
	if _is_female(speaker):
		var fem := ["zh-CN-XiaoxiaoNeural", "zh-CN-XiaoyiNeural"]
		return fem[int(abs(hash(speaker)) % fem.size())]
	var male := ["zh-CN-YunxiNeural", "zh-CN-YunjianNeural", "zh-CN-YunyangNeural"]
	return male[int(abs(hash(speaker)) % male.size())]


func _edge_pct(v: float, lo: int, hi: int) -> int:
	return clampi(int(round((v - 1.0) * 100.0)), lo, hi)


func _request_edge(clean: String, speaker: String, emo: Dictionary) -> void:
	var key := speaker + "|" + clean
	if _edge_cache.has(key):
		_play_edge(_edge_cache[key], emo)
		return
	if _edge_busy:
		if _edge_queue.size() < 4:
			_edge_queue.append({"t": clean, "s": speaker, "e": emo})
		return
	var pitch_pct: int = _edge_pct(float(emo["pitch"]), -25, 45)
	var rate_pct: int = _edge_pct(float(emo["rate"]), -25, 35)
	var vol_pct: int = clampi(int(round(float(emo["volume"]))) - 88, -20, 20)
	if speaker == "灵宝":
		pitch_pct += 10
		rate_pct += 4
	_edge_busy = true
	_edge_seq += 1
	_edge_cur = {"key": key, "t": clean, "s": speaker, "e": emo}
	_edge.call("synth", _edge_seq, clean, _edge_voice(speaker), pitch_pct, rate_pct, vol_pct)
	if OS.is_debug_build():
		print("[VOICE] edge request voice=", _edge_voice(speaker), " pitch=", pitch_pct, " rate=", rate_pct)


func _on_edge_done(_id: int, stream: AudioStreamMP3) -> void:
	_edge_fail_streak = 0
	var key := str(_edge_cur.get("key", ""))
	if key != "":
		if _edge_cache.size() > 120:
			_edge_cache.clear()
		_edge_cache[key] = stream
	_play_edge(stream, _edge_cur.get("e", {}))
	_edge_next()


func _on_edge_failed(_id: int) -> void:
	_edge_fail_streak += 1
	if _edge != null:
		_edge.call("diag", "voice edge failed, fallback local")
	if not _edge_notice_shown:
		_edge_notice_shown = true
		var cs = get_node_or_null("/root/ChatService")
		if cs != null:
			cs.call("system_note", "在线语音不可用，已切换本地语音（详见 voice_diag.log）")
	# 连续失败：本次会话回退本地 TTS/拟声，避免每条语音都等 8 秒超时
	if _edge_fail_streak >= 2:
		edge_enabled = false
		if OS.is_debug_build():
			print("[VOICE] edge unavailable -> local fallback for this session")
	var t := str(_edge_cur.get("t", ""))
	var sp := str(_edge_cur.get("s", ""))
	var em: Dictionary = _edge_cur.get("e", {})
	_edge_next()
	if t != "":
		# Edge 连不上（常见于 TLS/证书/网络策略）：本次会话切到有道 HTTP 在线语音
		edge_enabled = false
		_online_mode = "http"
		_request_http(t, sp, em)


func _request_http(clean: String, speaker: String, emo: Dictionary) -> void:
	var key := speaker + "|" + clean
	if _http_cache.has(key):
		_play_edge(_http_cache[key], emo)
		return
	if _http_busy:
		if _http_queue.size() < 4:
			_http_queue.append({"t": clean, "s": speaker, "e": emo})
		return
	_http_busy = true
	_http_seq += 1
	_http_cur = {"key": key, "t": clean, "s": speaker, "e": emo}
	_http_tts.call("synth", _http_seq, clean)


func _on_http_done(_id: int, stream: AudioStreamMP3) -> void:
	var key := str(_http_cur.get("key", ""))
	if key != "":
		if _http_cache.size() > 120:
			_http_cache.clear()
		_http_cache[key] = stream
	_play_edge(stream, _http_cur.get("e", {}))
	_http_next()


func _on_http_failed(_id: int) -> void:
	var t := str(_http_cur.get("t", ""))
	var sp := str(_http_cur.get("s", ""))
	var em: Dictionary = _http_cur.get("e", {})
	_http_next()
	if t != "":
		_online_mode = "local"
		if not _edge_notice_shown:
			_edge_notice_shown = true
			var cs = get_node_or_null("/root/ChatService")
			if cs != null:
				cs.call("system_note", "在线语音不可用，已切换本地语音（voice_diag.log）")
		_speak_local(t, sp, em)


func _http_next() -> void:
	_http_busy = false
	_http_cur = {}
	if _http_queue.is_empty():
		return
	var nx: Dictionary = _http_queue.pop_front()
	_request_http(str(nx.get("t", "")), str(nx.get("s", "")), nx.get("e", {}))


func _edge_next() -> void:
	_edge_busy = false
	_edge_cur = {}
	if _edge_queue.is_empty():
		return
	var nx: Dictionary = _edge_queue.pop_front()
	_request_edge(str(nx.get("t", "")), str(nx.get("s", "")), nx.get("e", {}))


func _play_edge(stream: AudioStreamMP3, emo: Dictionary = {}) -> void:
	if _edge_player == null or stream == null:
		return
	var vol_db: float = float(emo.get("vol_db", 0.0))
	var vol_lin: float = clampf(db_to_linear(vol_db), 0.0, 1.0)
	if _edge != null:
		_edge.call("diag", "play edge audio bytes=%d" % stream.data.size())
	if _ok and DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()
	_blip.stop()
	# 手机 Web 无 speechSynthesis 时：用浏览器 <audio> 解码 MP3，绕开 Godot Web Audio 的 MP3 解码杂音
	if OS.has_feature("web") and stream.data.size() > 64:
		var b64 := Marshalls.raw_to_base64(stream.data)
		var js2 := """(function(){try{
			var a=window.__hkVoiceAudio;
			if(!a){a=new Audio(); window.__hkVoiceAudio=a;}
			a.volume=%f;
			a.pause(); a.src='data:audio/mpeg;base64,%s';
			var p=a.play(); if(p&&p.catch) p.catch(function(){});
			return true;
		}catch(e){return false;}})()""" % [vol_lin, b64]
		if bool(JavaScriptBridge.eval(js2, true)):
			return
	_edge_player.stream = stream
	_edge_player.volume_db = vol_db
	_edge_player.play()


## 标点/情绪 → 音高、语速、音量与句内曲线
func _emotion_params(text: String, speaker: String) -> Dictionary:
	var pitch := 1.0
	var rate := 1.0
	var vol := 88.0
	var pitch_curve := 0.0
	if speaker == "灵宝":
		pitch = 1.30
		rate = 1.08
	elif speaker != "":
		pitch = 0.93 + float(int(abs(hash(speaker))) % 15) * 0.01
	if text.contains("？") or text.contains("?"):
		pitch += 0.10
		pitch_curve = 0.12
		rate -= 0.04
	if text.contains("！") or text.contains("!"):
		pitch += 0.08
		rate += 0.08
		vol += 5.0
	if text.contains("…") or text.contains("...") or text.contains("～") or text.contains("~"):
		rate -= 0.10
		pitch -= 0.02
		vol -= 3.0
	var laugh := ["哈哈", "嘿嘿", "嘻嘻", "嚯", "呵"]
	var sad := ["唉", "呜", "哎", "呜呜", "哼"]
	var surprise := ["哇", "啊", "呀", "咦", "哦"]
	var anger := ["哼", "切", "可恶", "笨蛋"]
	var excited := ["冲", "打", "上", "牛", "太强", "厉害"]
	for w in laugh:
		if text.find(w) >= 0:
			rate += 0.14
			pitch += 0.04
			break
	for w in sad:
		if text.find(w) >= 0:
			rate -= 0.12
			pitch -= 0.06
			break
	for w in surprise:
		if text.find(w) >= 0:
			pitch += 0.10
			rate += 0.05
			break
	for w in anger:
		if text.find(w) >= 0:
			pitch += 0.05
			rate += 0.06
			vol += 3.0
			break
	for w in excited:
		if text.find(w) >= 0:
			rate += 0.10
			pitch += 0.06
			break
	var ln := text.length()
	if ln <= 6:
		rate += 0.06
		pitch += 0.03
	elif ln >= 40:
		rate -= 0.06
	var jitter := float(int(abs(hash(text))) % 100) / 100.0
	pitch += (jitter - 0.5) * 0.06
	rate += (float(int(abs(hash(text + "#"))) % 100) / 100.0 - 0.5) * 0.06
	return {
		"pitch": pitch, "rate": rate, "volume": vol,
		"pitch_curve": pitch_curve, "rate_curve": 0.0,
	}


## 按中文标点分句（最多 6 段）
func _split_clauses(text: String) -> Array:
	var out: Array = []
	var cur := ""
	for ch in text:
		cur += ch
		if ch in ["，", "。", "！", "？", "；", "、", ",", ".", "!", "?", ";", "…", "～", "~"]:
			out.append({"text": cur, "vol": 0.0})
			cur = ""
	if cur.strip_edges() != "":
		out.append({"text": cur, "vol": -2.0})
	var merged: Array = []
	for c in out:
		if not merged.is_empty() and str(c["text"]).strip_edges().length() <= 1:
			merged[merged.size() - 1]["text"] = str(merged[merged.size() - 1]["text"]) + str(c["text"])
		else:
			merged.append(c)
	if merged.size() > 6:
		var tail := ""
		for i in range(6, merged.size()):
			tail += str(merged[i]["text"])
		merged = merged.slice(0, 6)
		merged[5]["text"] = str(merged[5]["text"]) + tail
	return merged


## 系统 TTS 静默失败：0.25s 后没在发声就补拟声
func _verify_tts(my_utt: int, clean: String, speaker: String) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.25).timeout
	if my_utt != _utt:
		return
	if DisplayServer.has_method("tts_is_speaking") and DisplayServer.tts_is_speaking():
		return
	if OS.is_debug_build():
		print("[VOICE] tts seems silent -> blip fallback")
	_blip_speak(clean, speaker, _emotion_params(clean, speaker))


func diag(msg: String) -> void:
	print("[VOICE] ", msg)
	_diag_tail.append(msg)
	if _diag_tail.size() > 20:
		_diag_tail.pop_front()


func diagnose() -> Dictionary:
	var edge_log: Array = []
	if _edge != null and _edge.has_method("diag_tail"):
		edge_log = _edge.call("diag_tail")
	var speaking := false
	if DisplayServer.has_method("tts_is_speaking"):
		speaking = DisplayServer.tts_is_speaking()
	return {
		"enabled": enabled, "tts_ok": _ok, "has_zh": _has_zh, "voice": _voice,
		"pool": _voice_pool, "lang": _lang, "fallback": _fallback_blip, "tts_speaking": speaking,
		"edge_enabled": edge_enabled, "edge_busy": _edge_busy, "edge_fail": _edge_fail_streak,
		"edge_cache": _edge_cache.size(), "online_mode": _online_mode,
		"http_busy": _http_busy, "http_cache": _http_cache.size(),
		"sapi": _sapi != null, "voice_log": _diag_tail, "edge_log": edge_log,
		"master_db": AudioServer.get_bus_volume_db(0), "master_mute": AudioServer.is_bus_mute(0),
	}


func stop() -> void:
	if _ok and DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()
	if _blip != null:
		_blip.stop()
	if _edge_player != null:
		_edge_player.stop()
	if _edge != null:
		_edge.call("abort")
	if _http_tts != null:
		_http_tts.call("abort")
	_edge_busy = false
	_edge_queue.clear()
	_http_busy = false
	_http_queue.clear()


## 拟声语音：带语调曲线（问句上挑/感叹更亮/省略号拖长）+ 颤音 + 轻微气声
func _blip_speak(text: String, speaker: String, emo: Dictionary) -> void:
	if _blip == null:
		return
	_blip.stop()
	_blip.volume_db = float(emo.get("vol_db", 0.0))
	var n := clampi(text.length(), 3, 16)
	var sr := 22050
	var pitch_mul: float = float(emo.get("pitch", 1.0))
	var rate_mul: float = float(emo.get("rate", 1.0))
	var base := 300.0
	if speaker == "灵宝":
		base = 620.0
	elif speaker != "":
		base = 280.0 + float(int(abs(hash(speaker))) % 140)
	base *= clampf(pitch_mul, 0.6, 1.6)
	var question: bool = text.contains("？") or text.contains("?")
	var exclaim: bool = text.contains("！") or text.contains("!")
	var slow: bool = text.contains("…") or text.contains("...") or text.contains("～")
	var step: float = 0.075 / clampf(rate_mul, 0.6, 1.6)
	var tail_len: float = 0.10 if (question or exclaim) else 0.06
	var samples := int((float(n) * step + tail_len + 0.06) * float(sr))
	if samples <= 0:
		return
	var buf := PackedByteArray()
	buf.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(hash(text + speaker))) & 0x7fffffff
	var end_shift: float = 0.26 if question else (-0.16 if exclaim else 0.06)
	for i in range(n):
		var tpos: float = float(i) / maxf(1.0, float(n - 1))
		var f0: float = base * (1.0 + end_shift * tpos)
		if exclaim:
			f0 *= 1.08
		var dur_s: float = (0.055 + 0.022 * absf(sin(float(i) * 1.7 + 0.4))) * (1.35 if slow else 1.0)
		var dur := int(dur_s * float(sr))
		var start := int(float(i) * step * float(sr))
		var accent: float = 1.25 if i == 0 else (1.1 if i == n - 1 else 1.0)
		var noise_amp: float = 0.035 if speaker == "灵宝" else 0.025
		for s in range(dur):
			var idx := start + s
			if idx >= samples:
				break
			var tt := float(s) / float(sr)
			var env := sin(PI * float(s) / float(dur))
			var f: float = f0 * (1.0 + 0.03 * sin(PI * float(s) / float(dur)) + 0.006 * sin(TAU * 6.0 * tt))
			var v: float = sin(TAU * f * tt) * 0.52 + sin(TAU * f * 2.0 * tt) * 0.20 + sin(TAU * f * 3.0 * tt) * 0.07
			v += rng.randf_range(-1.0, 1.0) * noise_amp
			v *= env * 0.6 * accent
			buf.encode_s16(idx * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = buf
	_blip.stream = w
	_blip.play()


func _has_cjk(text: String) -> bool:
	for ch in text:
		if ch.unicode_at(0) >= 0x2E80:
			return true
	return false


## 清掉表情/控制字符，压平空白，限制长度
func _clean(text: String) -> String:
	var t := str(text)
	t = t.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	if t.contains("："):
		var idx2 := t.find("：")
		if idx2 >= 0 and idx2 <= 8:
			t = t.substr(idx2 + 1)
	var out := ""
	for ch in t:
		var c: int = ch.unicode_at(0)
		if c < 32:
			continue
		if c >= 0x1F000 and c <= 0x1FAFF:
			continue
		if c >= 0x2600 and c <= 0x27BF:
			continue
		if c >= 0x2B00 and c <= 0x2BFF:
			continue
		if c >= 0xFE00 and c <= 0xFE0F:
			continue
		if c >= 0x1F1E6 and c <= 0x1F1FF:
			continue
		out += ch
	out = out.strip_edges()
	while out.find("  ") >= 0:
		out = out.replace("  ", " ")
	if out.length() > 90:
		out = out.substr(0, 90)
	var has_word := false
	for ch in out:
		if ch.is_valid_identifier() or (ch.unicode_at(0) > 0x2E80):
			has_word = true
			break
	if not has_word:
		return ""
	return out
