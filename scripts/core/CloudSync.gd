class_name CloudSync
extends RefCounted
## 云端存档：把「玩家段位 + 对战纪录」打包成 JSON，上传/下载到云端。
## 三种后端（主菜单「云端存档」页选择）：
##   http      自建/Serverless：POST {url}/upload、GET {url}/download?pid=，Bearer token 可选
##   leancloud 国内 BaaS：X-LC-Id / X-LC-Key，类 CloudSave（字段 pid / ts / data）
##   bmob      国内 BaaS：X-Bmob-Application-Id / X-Bmob-REST-API-Key，表 CloudSave（字段 pid / ts / data）
## 未配置时一切调用都是空操作，不影响单机流程。

const TIMEOUT := 10.0
const BACKEND_HTTP := "http"
const BACKEND_SUPABASE := "supabase"
const BACKEND_LEANCLOUD := "leancloud"
const BACKEND_BMOB := "bmob"
const LC_CLASS := "/1.1/classes/CloudSave"
const BMOB_BASE := "https://api.bmob.cn/1"
const BMOB_CLASS := "/classes/CloudSave"
const SUPA_TABLE := "/rest/v1/cloud_saves"


## 当前后端：http / leancloud / bmob
static func backend() -> String:
	var b := str(PlayerPrefs.cloud_cfg().get("backend", BACKEND_HTTP))
	if b != BACKEND_LEANCLOUD and b != BACKEND_BMOB and b != BACKEND_SUPABASE:
		return BACKEND_HTTP
	return b


## 是否已配置（按后端检查不同字段）
static func is_configured() -> bool:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	match backend():
		BACKEND_LEANCLOUD:
			return str(cfg.get("url", "")).strip_edges() != "" \
				and str(cfg.get("app_id", "")).strip_edges() != "" \
				and str(cfg.get("app_key", "")).strip_edges() != ""
		BACKEND_BMOB:
			return str(cfg.get("app_id", "")).strip_edges() != "" \
				and str(cfg.get("app_key", "")).strip_edges() != ""
		BACKEND_SUPABASE:
			# Supabase：url=项目地址，app_key=anon public key
			return str(cfg.get("url", "")).strip_edges() != "" \
				and str(cfg.get("app_key", "")).strip_edges() != ""
		_:
			return str(cfg.get("url", "")).strip_edges() != ""


## 本地玩家 ID（首次生成后固定，用于服务端按玩家分档）
static func player_id() -> String:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	var pid := str(cfg.get("pid", ""))
	if pid != "":
		return pid
	pid = "hk_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	cfg["pid"] = pid
	PlayerPrefs.set_cloud_cfg(cfg)
	return pid


## 打包本机存档
static func payload() -> Dictionary:
	return {
		"pid": player_id(),
		"ts": int(Time.get_unix_time_from_system()),
		"rank": RankSystem.state(),
		"history": BattleHistory.all(),
	}


## 上传（cb(ok, code, msg) 可选）
static func upload(tree: SceneTree, cb: Callable = Callable()) -> void:
	if not is_configured():
		_cb(cb, false, 0, "未配置云端服务")
		return
	match backend():
		BACKEND_LEANCLOUD:
			_lc_upload(tree, cb)
		BACKEND_BMOB:
			_bmob_upload(tree, cb)
		BACKEND_SUPABASE:
			_supabase_upload(tree, cb)
		_:
			_http_upload(tree, cb)


## 下载并写回本地（cb(ok, code, msg) 可选）
static func download(tree: SceneTree, cb: Callable = Callable()) -> void:
	if not is_configured():
		_cb(cb, false, 0, "未配置云端服务")
		return
	match backend():
		BACKEND_LEANCLOUD:
			_lc_download(tree, cb)
		BACKEND_BMOB:
			_bmob_download(tree, cb)
		BACKEND_SUPABASE:
			_supabase_download(tree, cb)
		_:
			_http_download(tree, cb)


## —— 通用 HTTP 后端 ——

static func _http_upload(tree: SceneTree, cb: Callable) -> void:
	var base := str(PlayerPrefs.cloud_cfg().get("url", "")).strip_edges().trim_suffix("/")
	var token := str(PlayerPrefs.cloud_cfg().get("token", ""))
	_do(tree, HTTPClient.METHOD_POST, base + "/upload", JSON.stringify(payload()), token, cb)


static func _http_download(tree: SceneTree, cb: Callable) -> void:
	var base := str(PlayerPrefs.cloud_cfg().get("url", "")).strip_edges().trim_suffix("/")
	var token := str(PlayerPrefs.cloud_cfg().get("token", ""))
	var url := "%s/download?pid=%s" % [base, player_id().uri_encode()]
	_do(tree, HTTPClient.METHOD_GET, url, "", token, func(ok: bool, code: int, body: String) -> void:
		if not ok:
			_cb(cb, false, code, body)
			return
		_apply_body(cb, code, body)
	)


## —— LeanCloud（国内 BaaS，免备案域名） ——

static func _lc_headers(cfg: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-LC-Id: " + str(cfg.get("app_id", "")).strip_edges(),
		"X-LC-Key: " + str(cfg.get("app_key", "")).strip_edges(),
	])


static func _lc_url(cfg: Dictionary) -> String:
	return str(cfg.get("url", "")).strip_edges().trim_suffix("/") + LC_CLASS


static func _lc_find(tree: SceneTree, cb_read: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	var where := JSON.stringify({"pid": player_id()}).uri_encode()
	var url := "%s?where=%s&limit=1" % [_lc_url(cfg), where]
	_do_headers(tree, HTTPClient.METHOD_GET, url, "", _lc_headers(cfg),
		func(ok: bool, code: int, body: String) -> void:
			if not ok:
				cb_read.call(false, code, "", {})
				return
			var arr := _results_of(body)
			if arr.is_empty():
				cb_read.call(true, code, "", {})
				return
			var obj: Dictionary = arr[0] if arr[0] is Dictionary else {}
			cb_read.call(true, code, str(obj.get("objectId", "")), obj.get("data", {}))
	)


static func _lc_upload(tree: SceneTree, cb: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	_lc_find(tree, func(ok: bool, code: int, oid: String, _d) -> void:
		if not ok:
			_cb(cb, false, code, "查询云端失败")
			return
		var data := payload()
		var body := JSON.stringify({"pid": player_id(), "ts": int(data["ts"]), "data": data})
		var method := HTTPClient.METHOD_PUT if oid != "" else HTTPClient.METHOD_POST
		var url := _lc_url(cfg) + ("/" + oid if oid != "" else "")
		_do_headers(tree, method, url, body, _lc_headers(cfg),
			func(ok2: bool, code2: int, resp: String) -> void:
				_cb(cb, ok2, code2, "已上传" if ok2 else resp.left(120))
		)
	)


static func _lc_download(tree: SceneTree, cb: Callable) -> void:
	_lc_find(tree, func(ok: bool, code: int, _oid: String, data) -> void:
		if not ok:
			_cb(cb, false, code, "读取云端失败")
			return
		if not (data is Dictionary) or (data as Dictionary).is_empty():
			_cb(cb, true, code, "云端无有效数据")
			return
		var merged := apply_remote(data as Dictionary)
		_cb(cb, true, code, "已同步" if merged else "云端无有效数据")
	)


## —— Bmob（国内 BaaS，免备案域名） ——

static func _bmob_headers(cfg: Dictionary) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"X-Bmob-Application-Id: " + str(cfg.get("app_id", "")).strip_edges(),
		"X-Bmob-REST-API-Key: " + str(cfg.get("app_key", "")).strip_edges(),
	])


static func _bmob_url(cfg: Dictionary) -> String:
	# 默认官方 api.bmob.cn；填了服务器地址时可用于自定义域名/本地联调
	var base := str(cfg.get("url", "")).strip_edges().trim_suffix("/")
	if base == "":
		base = BMOB_BASE
	elif not base.ends_with("/1"):
		base += "/1"
	return base + BMOB_CLASS


static func _bmob_find(tree: SceneTree, cb_read: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	var where := JSON.stringify({"pid": player_id()}).uri_encode()
	var url := "%s?where=%s&limit=1" % [_bmob_url(cfg), where]
	_do_headers(tree, HTTPClient.METHOD_GET, url, "", _bmob_headers(cfg),
		func(ok: bool, code: int, body: String) -> void:
			if not ok:
				cb_read.call(false, code, "", {})
				return
			var arr := _results_of(body)
			if arr.is_empty():
				cb_read.call(true, code, "", {})
				return
			var obj: Dictionary = arr[0] if arr[0] is Dictionary else {}
			cb_read.call(true, code, str(obj.get("objectId", "")), obj.get("data", {}))
	)


static func _bmob_upload(tree: SceneTree, cb: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	_bmob_find(tree, func(ok: bool, code: int, oid: String, _d) -> void:
		if not ok:
			_cb(cb, false, code, "查询云端失败")
			return
		var data := payload()
		var body := JSON.stringify({"pid": player_id(), "ts": int(data["ts"]), "data": data})
		var method := HTTPClient.METHOD_PUT if oid != "" else HTTPClient.METHOD_POST
		var url := _bmob_url(cfg) + ("/" + oid if oid != "" else "")
		_do_headers(tree, method, url, body, _bmob_headers(cfg),
			func(ok2: bool, code2: int, resp: String) -> void:
				_cb(cb, ok2, code2, "已上传" if ok2 else resp.left(120))
		)
	)


static func _bmob_download(tree: SceneTree, cb: Callable) -> void:
	_bmob_find(tree, func(ok: bool, code: int, _oid: String, data) -> void:
		if not ok:
			_cb(cb, false, code, "读取云端失败")
			return
		if not (data is Dictionary) or (data as Dictionary).is_empty():
			_cb(cb, true, code, "云端无有效数据")
			return
		var merged := apply_remote(data as Dictionary)
		_cb(cb, true, code, "已同步" if merged else "云端无有效数据")
	)


## —— Supabase（免费档，PostgREST 直连，无需部署 Edge Function） ——

static func _supabase_headers(cfg: Dictionary) -> PackedStringArray:
	var key := str(cfg.get("app_key", "")).strip_edges()
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + key,
		"Authorization: Bearer " + key,
	])


static func _supabase_url(cfg: Dictionary) -> String:
	return str(cfg.get("url", "")).strip_edges().trim_suffix("/") + SUPA_TABLE


static func _supabase_upload(tree: SceneTree, cb: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	var data := payload()
	var body := JSON.stringify({"pid": player_id(), "ts": int(data["ts"]), "data": data})
	var headers := _supabase_headers(cfg)
	headers.append("Prefer: resolution=merge-duplicates")
	# on_conflict=pid：主键冲突时覆盖（upsert），避免先查后写两次请求
	_do_headers(tree, HTTPClient.METHOD_POST, _supabase_url(cfg) + "?on_conflict=pid", body, headers,
		func(ok: bool, code: int, resp: String) -> void:
			_cb(cb, ok, code, "已上传" if ok else resp.left(120))
	)


static func _supabase_download(tree: SceneTree, cb: Callable) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	var url := "%s?pid=eq.%s&select=data&limit=1" % [_supabase_url(cfg), player_id().uri_encode()]
	_do_headers(tree, HTTPClient.METHOD_GET, url, "", _supabase_headers(cfg),
		func(ok: bool, code: int, body: String) -> void:
			if not ok:
				_cb(cb, false, code, "读取云端失败")
				return
			var arr := _results_of(body)
			if arr.is_empty():
				_cb(cb, true, code, "云端无有效数据")
				return
			var row: Dictionary = arr[0] if arr[0] is Dictionary else {}
			var data: Variant = row.get("data", {})
			if not (data is Dictionary) or (data as Dictionary).is_empty():
				_cb(cb, true, code, "云端无有效数据")
				return
			var merged := apply_remote(data as Dictionary)
			_cb(cb, true, code, "已同步" if merged else "云端无有效数据")
	)

## 把云端数据写回本地存档（段位 + 对战纪录合并）
static func apply_remote(data: Dictionary) -> bool:
	var any := false
	var rank_in: Variant = data.get("rank", {})
	if rank_in is Dictionary and not (rank_in as Dictionary).is_empty():
		any = RankSystem.import_state(rank_in as Dictionary) or any
	var hist_in: Variant = data.get("history", [])
	if hist_in is Array and not (hist_in as Array).is_empty():
		any = BattleHistory.import_all(hist_in as Array) or any
	return any


## 赛后自动上传（需在设置里开启「自动上传」）
static func auto_upload(tree: SceneTree) -> void:
	var cfg: Dictionary = PlayerPrefs.cloud_cfg()
	if not bool(cfg.get("auto", false)) or not is_configured():
		return
	upload(tree)


# —— 内部工具 ——

static func _apply_body(cb: Callable, code: int, body: String) -> void:
	var parsed: Variant = JSON.parse_string(body)
	if not (parsed is Dictionary):
		_cb(cb, false, code, "云端返回格式错误")
		return
	var merged := apply_remote(parsed as Dictionary)
	_cb(cb, true, code, "已同步" if merged else "云端无有效数据")


## LeanCloud / Bmob 查询结果：{"results":[...]}
static func _results_of(body: String) -> Array:
	var parsed: Variant = JSON.parse_string(body)
	if parsed is Array:
		return parsed as Array   # PostgREST / REST 顶层数组
	if parsed is Dictionary:
		var r: Variant = (parsed as Dictionary).get("results", [])
		if r is Array:
			return r as Array
	return []


static func _cb(cb: Callable, ok: bool, code: int, msg: String) -> void:
	if cb.is_valid():
		cb.call(ok, code, msg)


static func _do(tree: SceneTree, method: int, url: String, body: String, token: String, cb: Callable) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	_do_headers(tree, method, url, body, headers, cb)


static func _do_headers(tree: SceneTree, method: int, url: String, body: String,
		headers: PackedStringArray, cb: Callable) -> void:
	if tree == null:
		_cb(cb, false, 0, "无场景树")
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	tree.root.add_child(req)
	var err := req.request(url, headers, method, body)
	if err != OK:
		req.queue_free()
		_cb(cb, false, 0, "请求失败（%d）" % err)
		return
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
		if is_instance_valid(req):
			req.queue_free()
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
		_cb(cb, ok, code, resp.get_string_from_utf8()), CONNECT_ONE_SHOT)



