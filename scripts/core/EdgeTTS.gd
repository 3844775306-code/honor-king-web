extends Node
## Microsoft Edge 在线神经语音（免费、无需 Key）
## 协议：WSS + speech.config + SSML，返回 MP3 音频分片。
## 由 VoiceService 调用；失败/超时会通过 failed 信号，让上层回退到本地 SAPI / 拟声。

signal done(req_id: int, stream: AudioStreamMP3)
signal failed(req_id: int)

const TRUSTED := "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
const EDGE_URL := "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
const GEC_VERSION := "1-130.0.2849.68"
const TIMEOUT := 6.0
const CONNECT_TIMEOUT := 3.5

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
var _sent := false
var _retried_unsafe := false
var _ignored_pkts := 0
const DIAG_PATH := "user://voice_diag.log"
const DIAG_FALLBACK := "res://voice_diag.log"


func diag(msg: String) -> void:
	# 同时打到控制台和文件（导出包没有控制台时看 user://voice_diag.log）
	print("[EDGE] ", msg)
	var line := "%s %s\n" % [Time.get_datetime_string_from_system(false), msg]
	# 导出包没有控制台：再往 exe 同目录写一份，用户容易找到
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


func _ready() -> void:
	set_process(false)


func synth(req_id: int, text: String, voice: String, pitch_pct: int = 0, rate_pct: int = 0, vol_pct: int = 0) -> void:
	abort()
	_req_id = req_id
	_rid = Crypto.new().generate_random_bytes(16).hex_encode()
	_text = text
	_voice = voice
	_pitch = pitch_pct
	_rate = rate_pct
	_vol = vol_pct
	_buf.clear()
	_elapsed = 0.0
	_sent = false
	_retried_unsafe = false
	_ignored_pkts = 0
	if not _connect(false):
		_fail()
		return
	set_process(true)


func _connect(unsafe: bool) -> bool:
	_ws = WebSocketPeer.new()
	_ws.set_handshake_headers(PackedStringArray([
		"Origin: https://edge.microsoft.com",
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0",
	]))
	var url := "%s?TrustedClientToken=%s&Sec-MS-GEC=%s&Sec-MS-GEC-Version=%s&ConnectionId=%s" % [
		EDGE_URL, TRUSTED, gec_token(), GEC_VERSION, _rid]
	var err: int = _ws.connect_to_url(url, TLSOptions.client_unsafe() if unsafe else TLSOptions.client())
	diag("connect unsafe=%s err=%s voice=%s text=%s" % [str(unsafe), str(err), _voice, _text.substr(0, 20)])
	if err != OK:
		return false
	return true


func abort() -> void:
	set_process(false)
	if _ws != null:
		_ws.close()
	_ws = null
	_req_id = -1
	_buf.clear()


func _process(delta: float) -> void:
	if _ws == null or _req_id < 0:
		return
	_elapsed += delta
	if _elapsed > TIMEOUT:
		_fail()
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED and _req_id >= 0:
		diag("closed code=%s reason=%s" % [str(_ws.get_close_code()), str(_ws.get_close_reason())])
	match st:
		WebSocketPeer.STATE_CONNECTING:
			if _elapsed > CONNECT_TIMEOUT:
				_fail()
			return
		WebSocketPeer.STATE_OPEN:
			if not _sent:
				_sent = true
				_ws.send_text(_config_msg())
				_ws.send_text(_ssml_msg())
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				if _ws.was_string_packet():
					var txt := pkt.get_string_from_utf8()
					if txt.contains("Path:turn.end"):
						_finish()
						return
				elif pkt.size() > 2:
					# 协议：前 2 字节是「大端」头长度（不是小端！用 decode_u16 会错位，把头部当音频放出杂音）
					var hlen: int = (int(pkt[0]) << 8) | int(pkt[1])
					if hlen > 0 and hlen < 4096 and pkt.size() > 2 + hlen:
						var hdr := pkt.slice(2, 2 + mini(hlen, 120)).get_string_from_utf8()
						# Edge 会混发 audio.metadata（JSON）包：不能拼进 MP3，否则音频全成噪音
						var is_audio := hdr.find("Path:audio") >= 0 and hdr.find("metadata") < 0
						if not is_audio:
							_ignored_pkts += 1
							if _buf.size() == 0 and _ignored_pkts <= 2:
								diag("skip pkt hdr=" + hdr.replace("\r\n", "|"))
						else:
							if _buf.size() == 0:
								var head_hex := ""
								for bi in range(mini(2 + hlen + 8, pkt.size())):
									head_hex += "%02X" % int(pkt[bi])
								diag("first_audio hlen=%d hdr=%s head=%s" % [hlen, hdr.replace("\r\n", "|"), head_hex])
							_buf.append_array(pkt.slice(2 + hlen))
		WebSocketPeer.STATE_CLOSED:
			_fail()


func _finish() -> void:
	if _buf.size() < 128:
		diag("finish too small bytes=%d" % _buf.size())
		_fail()
		return
	# MP3 头校验：ID3 或 0xFFEx/0xFFFx；不合法说明拼包/格式不对，直接走兜底而不是放噪音
	var ok := false
	if _buf.size() >= 3 and _buf[0] == 0x49 and _buf[1] == 0x44 and _buf[2] == 0x33:
		ok = true
	elif _buf.size() >= 2 and _buf[0] == 0xFF and (_buf[1] & 0xE0) == 0xE0:
		ok = true
	diag("finish bytes=%d mp3_valid=%s ignored_pkts=%d" % [_buf.size(), str(ok), _ignored_pkts])
	if not ok:
		var hex := ""
		for bi in range(mini(16, _buf.size())):
			hex += "%02X" % int(_buf[bi])
		diag("invalid audio head=" + hex)
		_fail()
		return
	var mp3 := AudioStreamMP3.new()
	mp3.data = _buf
	var id := _req_id
	_cleanup()
	done.emit(id, mp3)


func _fail() -> void:
	if _req_id < 0:
		return
	# 某些环境（精简系统/受限账户）Godot 读不到系统根证书：自动用不校验证书方式重试一次。
	# 只用于下载公开的 TTS 音频，不涉及任何账号/密钥。
	if not _retried_unsafe:
		_retried_unsafe = true
		if _connect(true):
			_elapsed = 0.0
			return
	var id := _req_id
	diag("failed")
	_cleanup()
	failed.emit(id)


func _cleanup() -> void:
	set_process(false)
	if _ws != null:
		_ws.close()
	_ws = null
	_req_id = -1
	_buf.clear()


func _edge_date() -> String:
	var d := Time.get_datetime_dict_from_system(true)
	var wd := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var mo := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var w: int = int(d["weekday"])
	var tstr := "%s %s %02d %04d %02d:%02d:%02d GMT+0000 (Coordinated Universal Time)" % [
		wd[w], mo[int(d["month"]) - 1], int(d["day"]), int(d["year"]),
		int(d["hour"]), int(d["minute"]), int(d["second"])]
	return tstr + "Z"


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


## 新版 Edge TTS 需要的 Sec-MS-GEC 令牌：Windows FILETIME 取整 5 分钟 + 固定 token 的 SHA256
static func gec_token() -> String:
	var unix := int(Time.get_unix_time_from_system())
	var ticks := (unix + 11644473600) * 10000000
	ticks -= int(ticks % 3000000000)
	var s := str(ticks)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((s + TRUSTED).to_utf8_buffer())
	return ctx.finish().hex_encode().to_upper()
