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
	if err != OK:
		if OS.is_debug_build():
			print("[EDGE] connect error ", err, " unsafe=", unsafe)
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
	if OS.is_debug_build() and st == WebSocketPeer.STATE_CLOSED and _req_id >= 0:
		print("[EDGE] closed code=", _ws.get_close_code(), " reason=", _ws.get_close_reason())
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
						if OS.is_debug_build() and _buf.size() == 0:
							print("[EDGE] first audio pkt hlen=", hlen, " header=",
								pkt.slice(2, 2 + mini(hlen, 80)).get_string_from_utf8())
						_buf.append_array(pkt.slice(2 + hlen))
		WebSocketPeer.STATE_CLOSED:
			_fail()


func _finish() -> void:
	if _buf.size() < 128:
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
	_cleanup()
	failed.emit(id)


func _cleanup() -> void:
	set_process(false)
	if _ws != null:
		_ws.close()
	_ws = null
	_req_id = -1
	_buf.clear()


func _config_msg() -> String:
	var ts := Time.get_datetime_string_from_system(true) + "Z"
	return ("X-Timestamp:%s\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n"
		+ "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}") % ts


func _ssml_msg() -> String:
	var ts := Time.get_datetime_string_from_system(true) + "Z"
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
