extends Node
## Microsoft Edge 在线神经语音（免费、无需 Key）
## 关键优化：保持一条常驻 WSS 连接（单次握手约 0.9s，复用后每句只要 ~0.4s），
## 上一句合成完立即可以接下一句（音频还在播也能预取）。
## 由 VoiceService 调用；失败/超时会通过 failed 信号，让上层回退到本地 SAPI / 有声兜底。

signal done(req_id: int, stream: AudioStreamMP3)
signal failed(req_id: int)

const TRUSTED := "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
const EdgeTokenScript = preload("res://scripts/core/EdgeToken.gd")
const EDGE_URL := "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
const GEC_VERSION := "2-143.0.3650.75"
const TIMEOUT := 6.0
const CONNECT_TIMEOUT := 3.0
const DIAG_PATH := "user://voice_diag.log"
const DIAG_FALLBACK := "res://voice_diag.log"

var _ws: WebSocketPeer = null
var _req_id := -1
var _rid := ""
var _text := ""
var _voice := ""
var _pitch := 0
var _rate := 0
var _vol := 0
var _buf := PackedByteArray()
var _elapsed := 0.0
var _synth_t := 0.0
var _sent_config := false
var _ssml_sent := false
var _retried_unsafe := false
var _prefer_unsafe := false
var _ignored_pkts := 0
var _diag_buf: Array = []


func diag(msg: String) -> void:
	print("[EDGE] ", msg)
	_diag_buf.append(msg)
	if _diag_buf.size() > 20:
		_diag_buf.pop_front()
	var line := "%s %s\n" % [Time.get_datetime_string_from_system(false), msg]
	var exe_log := OS.get_executable_path().get_base_dir().path_join("voice_diag.log")
	var fe := FileAccess.open(exe_log, FileAccess.READ_WRITE)
	if fe == null:
		fe = FileAccess.open(exe_log, FileAccess.WRITE)
	if fe != null:
		fe.seek_end()
		fe.store_string(line)
		fe.close()
	var f := FileAccess.open(DIAG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(DIAG_FALLBACK, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(DIAG_PATH, FileAccess.WRITE)
		if f != null:
			f.close()
		f = FileAccess.open(DIAG_PATH, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	if f.get_length() > 65536:
		f.close()
		var w := FileAccess.open(DIAG_PATH, FileAccess.WRITE)
		if w != null:
			w.close()
		f = FileAccess.open(DIAG_PATH, FileAccess.READ_WRITE)
		if f == null:
			return
	f.store_string(line)
	f.close()


func diag_tail() -> Array:
	return _diag_buf.duplicate()


func _ready() -> void:
	set_process(false)


## 启动/首次说话前预热连接，省掉第一句的握手延迟
func warmup() -> void:
	if _ws != null:
		return
	_retried_unsafe = false
	_elapsed = 0.0
	if _connect(_prefer_unsafe):
		set_process(true)


func synth(req_id: int, text: String, voice: String, pitch_pct: int = 0, rate_pct: int = 0, vol_pct: int = 0) -> void:
	_req_id = req_id
	_rid = Crypto.new().generate_random_bytes(16).hex_encode()
	_text = text
	_voice = voice
	_pitch = pitch_pct
	_rate = rate_pct
	_vol = vol_pct
	_buf.clear()
	_ignored_pkts = 0
	_synth_t = 0.0
	_ssml_sent = false
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not _sent_config:
			_ws.send_text(_config_msg())
			_sent_config = true
		_send_ssml()
		set_process(true)
		return
	# 连接不在/已断：重连（记住上次只能用不校验证书模式，避免每次多等）
	_retried_unsafe = false
	_elapsed = 0.0
	if not _connect(_prefer_unsafe):
		_emit_fail()
		return
	set_process(true)


func abort() -> void:
	set_process(false)
	_close_conn()
	_req_id = -1
	_buf.clear()


func _close_conn() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	_sent_config = false
	_ssml_sent = false


func _connect(unsafe: bool) -> bool:
	_ws = WebSocketPeer.new()
	_ws.set_handshake_headers(PackedStringArray([
		"Pragma: no-cache",
		"Cache-Control: no-cache",
		"Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold",
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0",
		"Accept-Language: en-US,en;q=0.9",
		"Sec-CH-UA: \" Not;A Brand\";v=\"99\", \"Microsoft Edge\";v=\"143\", \"Chromium\";v=\"143\"",
		"Sec-CH-UA-Mobile: ?0",
	]))
	var cid := Crypto.new().generate_random_bytes(16).hex_encode()
	var url := "%s?TrustedClientToken=%s&Sec-MS-GEC=%s&Sec-MS-GEC-Version=%s&ConnectionId=%s" % [
		EDGE_URL, TRUSTED, gec_token(), GEC_VERSION, cid]
	var err: int = _ws.connect_to_url(url, TLSOptions.client_unsafe() if unsafe else TLSOptions.client())
	if err != OK:
		diag("connect err=%d unsafe=%s" % [err, str(unsafe)])
		return false
	_sent_config = false
	_ssml_sent = false
	return true


func _process(delta: float) -> void:
	if _ws == null:
		set_process(false)
		return
	_elapsed += delta
	_ws.poll()
	var st := _ws.get_ready_state()
	match st:
		WebSocketPeer.STATE_CONNECTING:
			if _elapsed > CONNECT_TIMEOUT:
				if not _retried_unsafe:
					_retried_unsafe = true
					_prefer_unsafe = true
					diag("tls normal failed -> retry unsafe")
					_elapsed = 0.0
					_close_conn()
					if not _connect(true):
						_emit_fail()
				else:
					_emit_fail()
			return
		WebSocketPeer.STATE_OPEN:
			if not _sent_config:
				_ws.send_text(_config_msg())
				_sent_config = true
			if _req_id >= 0 and not _ssml_sent:
				_send_ssml()
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				if _ws.was_string_packet():
					var txt := pkt.get_string_from_utf8()
					if txt.contains("Path:turn.end"):
						_finish_keep_alive()
						return
				elif pkt.size() > 2:
					var hlen: int = (int(pkt[0]) << 8) | int(pkt[1])
					if hlen > 0 and hlen < 4096 and pkt.size() > 2 + hlen:
						var hdr := pkt.slice(2, 2 + mini(hlen, 120)).get_string_from_utf8()
						var is_audio := hdr.find("Path:audio") >= 0 and hdr.find("metadata") < 0
						if is_audio:
							_buf.append_array(pkt.slice(2 + hlen))
						else:
							_ignored_pkts += 1
			if _req_id >= 0:
				_synth_t += delta
				if _synth_t > TIMEOUT:
					diag("synth timeout")
					_emit_fail()
			return
		WebSocketPeer.STATE_CLOSED:
			diag("closed code=%s reason=%s" % [str(_ws.get_close_code()), str(_ws.get_close_reason())])
			_close_conn()
			if _req_id >= 0:
				_emit_fail()
			else:
				set_process(false)
			return


func _send_ssml() -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(_ssml_msg())
	_ssml_sent = true
	_synth_t = 0.0


func _finish_keep_alive() -> void:
	if _buf.size() < 128:
		_emit_fail()
		return
	var ok := false
	if _buf.size() >= 3 and _buf[0] == 0x49 and _buf[1] == 0x44 and _buf[2] == 0x33:
		ok = true
	elif _buf.size() >= 2 and _buf[0] == 0xFF and (_buf[1] & 0xE0) == 0xE0:
		ok = true
	if not ok:
		var hex := ""
		for bi in range(mini(16, _buf.size())):
			hex += "%02X" % int(_buf[bi])
		diag("invalid audio head=" + hex)
		_emit_fail()
		return
	var mp3 := AudioStreamMP3.new()
	mp3.data = _buf
	var id := _req_id
	_req_id = -1
	_buf.clear()
	_ssml_sent = false
	_synth_t = 0.0
	# 不断开连接：下一句直接复用（省 ~0.9s 握手）
	done.emit(id, mp3)


func _emit_fail() -> void:
	var id := _req_id
	_req_id = -1
	_buf.clear()
	_ssml_sent = false
	_close_conn()
	failed.emit(id)


func _config_msg() -> String:
	var ts := _edge_date()
	return ("X-Timestamp:%s\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
		+ "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}\r\n") % ts


func _ssml_msg() -> String:
	var ts := _edge_date()
	var esc := _text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
	var hz: int = clampi(_pitch * 2, -100, 100)
	var prosody := "<prosody pitch=\"%+dHz\" rate=\"%+d%%\" volume=\"%+d%%\">%s</prosody>" % [hz, _rate, _vol, esc]
	var ssml := "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"zh-CN\"><voice name=\"%s\">%s</voice></speak>" % [_voice, prosody]
	return "X-RequestId:%s\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:%s\r\nPath:ssml\r\n\r\n%s" % [_rid, ts, ssml]


func _edge_date() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	var wd := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var mo := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var w: int = int(d["weekday"])
	var tstr := "%s %s %02d %04d %02d:%02d:%02d GMT+0000 (Coordinated Universal Time)" % [
		wd[w], mo[int(d["month"]) - 1], int(d["day"]), int(d["year"]),
		int(d["hour"]), int(d["minute"]), int(d["second"])]
	return tstr + "Z"


## 新版 Edge 要求 v2 令牌（混淆 SHA256 + CS64，每 5 分钟变化）
static func gec_token() -> String:
	return EdgeTokenScript.current_token()
