extends Node
## 可选的大模型聊天后端（OpenAI 兼容 /chat/completions）。
## 默认关闭：只有 user://ai_chat.cfg 里配好 api_key（或环境变量 HONORKING_LLM_KEY）才启用；
## 任何失败都静默降级，调用方继续用本地台词库，绝不卡帧（全程 HTTPRequest 异步）。

const CFG_PATHS := ["res://ai_chat.cfg", "user://ai_chat.cfg"]
const DEF_URL := "https://api.deepseek.com/v1/chat/completions"
const DEF_MODEL := "deepseek-chat"
const TIMEOUT := 6.0
const MIN_GAP := 1.5          # 两次请求最小间隔，防刷

var enabled := false
var _url := DEF_URL
var _max_tokens := 160
var _timeout := 8.0
var _model := DEF_MODEL
var _key := ""
var _http: HTTPRequest = null
var _busy := false
var _last_req := -99.0
var _pending: Callable = Callable()


func _ready() -> void:
	name = "LLMChat"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_load_cfg()


func _load_cfg() -> void:
	var key := OS.get_environment("HONORKING_LLM_KEY")
	var url := OS.get_environment("HONORKING_LLM_URL")
	var model := OS.get_environment("HONORKING_LLM_MODEL")
	var cfg_enabled := true
	# 先读工程根目录（开发期方便），再读 user://（打包后放外面，别把 key 提交进仓库）
	for p in CFG_PATHS:
		var cf := ConfigFile.new()
		if cf.load(p) != OK:
			continue
		key = str(cf.get_value("llm", "api_key", key))
		url = str(cf.get_value("llm", "base_url", url if url != "" else DEF_URL))
		model = str(cf.get_value("llm", "model", model if model != "" else DEF_MODEL))
		cfg_enabled = bool(cf.get_value("llm", "enabled", cfg_enabled))
		_max_tokens = int(cf.get_value("llm", "max_tokens", _max_tokens))
		_timeout = float(cf.get_value("llm", "timeout", _timeout))
		break
	_key = key.strip_edges()
	if url != null and str(url).strip_edges() != "":
		_url = str(url).strip_edges()
	if model != null and str(model).strip_edges() != "":
		_model = str(model).strip_edges()
	if _http != null:
		_http.timeout = _timeout
	enabled = _key != "" and cfg_enabled


## 问一句：ctx 里带英雄/局势信息；回调收到一句台词，失败给空串
func ask(system_prompt: String, player_text: String, cb: Callable) -> bool:
	if not enabled or _busy:
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_req < MIN_GAP:
		return false
	_last_req = now
	_busy = true
	_pending = cb
	var body := {
		"model": _model,
		"stream": false,
		"max_tokens": _max_tokens,
		"temperature": 0.9,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": player_text},
		],
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _key,
	])
	var err := _http.request(_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		_pending = Callable()
		return false
	return true


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var cb := _pending
	_pending = Callable()
	var text := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			var choices = parsed.get("choices", [])
			if choices is Array and not choices.is_empty():
				var msg = choices[0].get("message", {})
				if msg is Dictionary:
					text = _clean(str(msg.get("content", "")))
	if cb.is_valid():
		cb.call(text)


func _clean(raw: String) -> String:
	var s := raw.strip_edges()
	s = s.replace("\r", " ").replace("\n", " ")
	# 去掉模型爱加的引号
	for q in ["\"", "“", "”", "'", "「", "」"]:
		s = s.replace(q, "")
	# 去掉「名字：」这类前缀（模型常把说话人写进来）
	var ci := s.find("：")
	if ci < 0:
		ci = s.find(":")
	if ci > 0 and ci <= 8:
		s = s.substr(ci + 1)
	if s.length() > 26:
		s = s.substr(0, 26)
	return s.strip_edges()
