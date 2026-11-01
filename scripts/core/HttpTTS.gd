extends Node
## 有道在线 TTS（免费、无需 Key，走 HTTP 不依赖 TLS，可作为 Edge 失败后的兜底）
## 返回 MP3，交给 AudioStreamMP3 播放。

signal done(req_id: int, stream: AudioStreamMP3)
signal failed(req_id: int)

const BASE := "http://dict.youdao.com/dictvoice?le=zh&audio="
const TIMEOUT := 7.0

var _http: HTTPRequest = null
var _id := -1
var _elapsed := 0.0
var _text := ""


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_completed)
	set_process(false)


func synth(req_id: int, text: String) -> void:
	abort()
	_id = req_id
	_text = text
	_elapsed = 0.0
	if _http == null:
		_ready()
	var url := BASE + text.uri_encode()
	var err: int = _http.request(url)
	if err != OK:
		diag("http tts request err=%d" % err)
		_fail()
		return
	set_process(true)


func abort() -> void:
	set_process(false)
	if _http != null and _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	_id = -1


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > TIMEOUT:
		diag("http tts timeout")
		_fail()


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _id < 0:
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.size() < 512:
		diag("http tts bad result=%d code=%d bytes=%d" % [result, code, body.size()])
		_fail()
		return
	var valid := false
	if body.size() >= 3 and body[0] == 0x49 and body[1] == 0x44 and body[2] == 0x33:
		valid = true
	elif body.size() >= 2 and body[0] == 0xFF and (body[1] & 0xE0) == 0xE0:
		valid = true
	if not valid:
		var hex := ""
		for bi in range(mini(16, body.size())):
			hex += "%02X" % int(body[bi])
		diag("http tts invalid audio head=" + hex)
		_fail()
		return
	diag("http tts ok bytes=%d text=%s" % [body.size(), _text.substr(0, 20)])
	var mp3 := AudioStreamMP3.new()
	mp3.data = body
	var id := _id
	_cleanup()
	done.emit(id, mp3)


func _fail() -> void:
	if _id < 0:
		return
	var id := _id
	_cleanup()
	failed.emit(id)


func _cleanup() -> void:
	set_process(false)
	_id = -1


func diag(msg: String) -> void:
	print("[HTTPTTS] ", msg)
	# 复用 EdgeTTS 的日志文件，便于统一排查
	var edge = get_node_or_null("/root/EdgeTTSLogger")
	if edge != null:
		edge.call("diag", msg)
