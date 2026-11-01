extends Node
## 语音播报：把 AI 聊天 / 灵宝说话用系统 TTS 读出来（Windows SAPI / macOS / Linux speech-dispatcher）。
## 三端共用（单机、联机客户端、回放都不需要额外接入；回放无聊天内容时不会触发）。

var enabled := true
var _ok := false
var _voice := ""
var _utt := 0
var _last_text := ""
var _last_ms := 0
var _lang := ""


func _ready() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	if not DisplayServer.has_method("tts_speak") or not DisplayServer.has_method("tts_get_voices"):
		return
	_ok = true
	_voice = _pick_voice()


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
			return vid
	_lang = best_lang
	return best


## 朗读一句话。speaker 用来区分声线（灵宝偏高偏快，英雄按名字微调音高）
func speak(text: String, speaker: String = "") -> void:
	if not enabled or not _ok or _voice == "":
		return
	var clean := _clean(text)
	if clean == "":
		return
	var now := Time.get_ticks_msec()
	if clean == _last_text and now - _last_ms < 3000:
		return
	_last_text = clean
	_last_ms = now
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
	DisplayServer.tts_speak(clean, _voice, 80, pitch, rate, _utt, false)


func stop() -> void:
	if _ok and DisplayServer.has_method("tts_stop"):
		DisplayServer.tts_stop()


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
