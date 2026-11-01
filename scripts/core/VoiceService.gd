extends Node
## 语音播报：把 AI 聊天 / 灵宝说话读出来。
## - 有系统 TTS（Windows SAPI / macOS / Linux）：优先中文音色朗读
## - 无 TTS 或没有中文音色（Android / 精简系统）：自动降级为「拟声语音」
##   （按字数生成短促音调，像动物森友会式说话声，三端都能出声，不需要任何音频资源）

var enabled := true
var _ok := false            # 系统 TTS 可用
var _has_zh := false        # TTS 里有中文音色
var _voice := ""
var _lang := ""
var _fallback_blip := false # 是否走拟声语音
var _utt := 0
var _last_text := ""
var _last_ms := 0
var _blip: AudioStreamPlayer = null


func _ready() -> void:
	_blip = AudioStreamPlayer.new()
	_blip.name = "BlipVoice"
	_blip.bus = "Master"
	add_child(_blip)
	_fallback_blip = true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	if not DisplayServer.has_method("tts_speak") or not DisplayServer.has_method("tts_get_voices"):
		return
	_ok = true
	_voice = _pick_voice()
	_fallback_blip = _voice == ""
	if _voice == "":
		# 有 TTS 能力但枚举不到音色：按不可用处理，走拟声
		_ok = false
	if OS.is_debug_build():
		print("[VOICE] init ", diagnose())


func _pick_voice() -> String:
	var best := ""
	var best_lang := ""
	var voices: Array = DisplayServer.tts_get_voices()
	for v in voices:
		var vid := str(v.get("id", ""))
		var lang := str(v.get("language", "")).to_lower()
		var nm := str(v.get("name", "")).to_lower()
		if vid == "":
			continue
		if best == "":
			best = vid
			best_lang = lang
		if lang.begins_with("zh") or lang.begins_with("cmn") or lang.begins_with("yue") \
				or nm.find("chinese") >= 0 or nm.find("huihui") >= 0 or nm.find("yaoyao") >= 0 \
				or nm.find("kangkang") >= 0 or nm.find("xiaoxiao") >= 0 or nm.find("yunxi") >= 0:
			_lang = lang
			_has_zh = true
			return vid
	_lang = best_lang
	return best


## 朗读一句话。speaker 用来区分声线（灵宝偏高偏快，英雄按名字微调音高）
func speak(text: String, speaker: String = "") -> void:
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
	var is_cjk := _has_cjk(clean)
	if _ok and (not is_cjk or _has_zh):
		var pitch := 1.0
		var rate := 1.0
		if speaker == "灵宝":
			pitch = 1.38
			rate = 1.06
		elif speaker != "":
			pitch = 0.92 + float(int(abs(hash(speaker))) % 18) * 0.01
		_utt += 1
		if _utt > 900000:
			_utt = 1
		DisplayServer.tts_speak(clean, _voice, 90, pitch, rate, _utt, false)
		if OS.is_debug_build():
			print("[VOICE] tts speak id=", _utt, " voice=", _voice, " zh=", _has_zh)
		_verify_tts(_utt, clean, speaker)
	else:
		_blip_speak(clean, speaker)


## 系统 TTS 可能静默失败（缺语音包/驱动问题）：0.2s 后还没在发声就补拟声，保证能听到
func _verify_tts(my_utt: int, clean: String, speaker: String) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.22).timeout
	if my_utt != _utt:
		return   # 已经被后续语音顶掉
	if DisplayServer.has_method("tts_is_speaking") and DisplayServer.tts_is_speaking():
		return
	if OS.is_debug_build():
		print("[VOICE] tts seems silent -> blip fallback")
	_blip_speak(clean, speaker)


func diagnose() -> Dictionary:
	var speaking := false
	if DisplayServer.has_method("tts_is_speaking"):
		speaking = DisplayServer.tts_is_speaking()
	return {
		"enabled": enabled, "tts_ok": _ok, "has_zh": _has_zh, "voice": _voice, "lang": _lang,
		"fallback": _fallback_blip, "tts_speaking": speaking,
		"master_db": AudioServer.get_bus_volume_db(0), "master_mute": AudioServer.is_bus_mute(0),
	}


func stop() -> void:
	if _ok and DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()
	if _blip != null:
		_blip.stop()


## 无 TTS 时的拟声语音：按字数生成一串短音（有音高/节奏，听感像在说话）
func _blip_speak(clean: String, speaker: String) -> void:
	if _blip == null:
		return
	_blip.stop()
	var n := clampi(clean.length(), 2, 12)
	var sr := 22050
	var step := 0.085
	var samples := int((float(n) * step + 0.1) * float(sr))
	if samples <= 0:
		return
	var buf := PackedByteArray()
	buf.resize(samples * 2)
	var base := 300.0
	if speaker == "灵宝":
		base = 520.0
	elif speaker != "":
		base = 280.0 + float(int(abs(hash(speaker))) % 130)
	var peak := 0.55
	for i in range(n):
		var start := int(float(i) * step * float(sr))
		var dur := int(0.062 * float(sr))
		var f: float = base * (1.0 + 0.18 * sin(float(i) * 1.9))
		for s in range(dur):
			var idx := start + s
			if idx >= samples:
				break
			var tt := float(s) / float(sr)
			var env := sin(PI * float(s) / float(dur))
			var v: float = (sin(TAU * f * tt) * 0.6 + sin(TAU * f * 2.0 * tt) * 0.25) * env * peak
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


## 清掉表情/控制字符，压平空白，控制长度（TTS 读长句很慢）
func _clean(text: String) -> String:
	var t := str(text)
	t = t.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var out := ""
	for ch in t:
		var c: int = ch.unicode_at(0)
		if c < 32:
			continue
		# 常见表情/符号区（emoji、装饰符号、方块）跳过，避免 TTS 读成乱码
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
	# 纯标点/空白不读
	var has_word := false
	for ch in out:
		if ch.is_valid_identifier() or (ch.unicode_at(0) > 0x2E80):
			has_word = true
			break
	if not has_word:
		return ""
	return out
