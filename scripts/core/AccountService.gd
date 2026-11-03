class_name AccountService
extends RefCounted
## 本机账号服务：用户名/密码登录、30 天免登录、登录后从 CloudSync 拉取云端存档。
## 账号记录只保存在本机 user://accounts.json（密码只存随机盐 + SHA256，不存明文）；
## 云端存档仍走已有 CloudSync（配置服务器后登录会自动 download 合并段位/对战纪录）。

const PATH := "user://accounts.json"
const SESSION_PATH := "user://account_session.json"
const FALLBACK_PATH := "res://saves/accounts.json"
const FALLBACK_SESSION_PATH := "res://saves/account_session.json"
const SESSION_SECONDS := 30 * 24 * 60 * 60


static func _load_accounts() -> Dictionary:
	var out := {"accounts": {}, "last_user": ""}
	for p in [PATH, FALLBACK_PATH]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			out = parsed as Dictionary
			break
	if not (out.get("accounts", {}) is Dictionary):
		out["accounts"] = {}
	return out


static func _save_accounts(data: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()
		CloudSync.schedule_push()
		return true
	# 受限环境（编辑器沙箱）user:// 不可写：退回 res://saves，和 PlayerPrefs 同策略
	DirAccess.make_dir_recursive_absolute("res://saves")
	var f2 := FileAccess.open(FALLBACK_PATH, FileAccess.WRITE)
	if f2 == null:
		return false
	f2.store_string(JSON.stringify(data))
	f2.close()
	return true


static func _load_session() -> Dictionary:
	for p in [SESSION_PATH, FALLBACK_SESSION_PATH]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			return parsed as Dictionary
	return {}


static func _save_session(s: Dictionary) -> void:
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(s))
		f.close()
		CloudSync.schedule_push()
		return
	DirAccess.make_dir_recursive_absolute("res://saves")
	var f2 := FileAccess.open(FALLBACK_SESSION_PATH, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(JSON.stringify(s))
		f2.close()


static func has_valid_session() -> bool:
	var s := _load_session()
	if s.is_empty() or int(s.get("expires", 0)) <= int(Time.get_unix_time_from_system()):
		return false
	var user := str(s.get("username", ""))
	return not user.is_empty() and _load_accounts().get("accounts", {}).has(user)


static func session_username() -> String:
	if not has_valid_session():
		return ""
	return str(_load_session().get("username", ""))


static func session_pid() -> String:
	if not has_valid_session():
		return ""
	return str(_load_session().get("pid", ""))


static func last_username() -> String:
	return str(_load_accounts().get("last_user", ""))


static func sign_out() -> void:
	var s := _load_session()
	if not s.is_empty():
		UserScope.set_active("guest")
		PlayerPrefs.reload()
		RankSystem.reload()
		HeroBuildStore.reload()
		var cfg := PlayerPrefs.cloud_cfg()
		cfg["pid"] = ""
		cfg["token"] = ""
		PlayerPrefs.set_cloud_cfg(cfg)
	_save_session({})


## 登录本机账号；成功后自动尝试从云端下载段位/对战纪录。
static func login(tree: SceneTree, username: String, password: String, cb: Callable) -> void:
	var u := username.strip_edges()
	if u.length() < 2:
		_cb(cb, false, "用户名至少 2 个字符")
		return
	if password.length() < 4:
		_cb(cb, false, "密码至少 4 位")
		return
	var data := _load_accounts()
	var accounts: Dictionary = data.get("accounts", {})
	if not accounts.has(u):
		# 新设备：本机没有该账号 → 按用户名从云端找回
		CloudSync.fetch_account(tree, u, func(ok: bool, _code: int, rec: Dictionary) -> void:
			if not ok or rec.is_empty():
				_cb(cb, false, "账号不存在，请先新建账号")
				return
			if _hash(password, str(rec.get("salt", ""))) != str(rec.get("hash", "")):
				_cb(cb, false, "密码错误")
				return
			var acc2 := {
				"salt": str(rec.get("salt", "")), "hash": str(rec.get("hash", "")),
				"pid": str(rec.get("pid", "")), "created": int(Time.get_unix_time_from_system()), "token": "",
			}
			var d2 := _load_accounts()
			var a2: Dictionary = d2.get("accounts", {})
			a2[u] = acc2
			d2["accounts"] = a2
			d2["last_user"] = u
			_save_accounts(d2)
			_finish_login(tree, u, acc2, cb))
		return
	var acc: Dictionary = accounts[u]
	if _hash(password, str(acc.get("salt", ""))) != str(acc.get("hash", "")):
		_cb(cb, false, "密码错误")
		return
	data["last_user"] = u
	_save_accounts(data)
	CloudSync.push_account(tree, u, str(acc.get("salt", "")), str(acc.get("hash", "")), str(acc.get("pid", "")))
	_finish_login(tree, u, acc, cb)


## 新建本机账号并直接登录；成功后同样尝试拉取云端数据。
static func register(tree: SceneTree, username: String, password: String, cb: Callable) -> void:
	var u := username.strip_edges()
	if u.length() < 2:
		_cb(cb, false, "用户名至少 2 个字符")
		return
	if password.length() < 4:
		_cb(cb, false, "密码至少 4 位")
		return
	var data := _load_accounts()
	var accounts: Dictionary = data.get("accounts", {})
	if accounts.has(u):
		_cb(cb, false, "该账号已存在，请直接登录")
		return
	# 云端已存在同名账号（换设备/重装）→ 引导直接登录，避免覆盖云端身份
	CloudSync.fetch_account(tree, u, func(ok: bool, _code: int, rec: Dictionary) -> void:
		if ok and not rec.is_empty():
			_cb(cb, false, "该账号已存在，请直接登录")
			return
		_register_local(tree, u, password, cb))
	return


static func _register_local(tree: SceneTree, u: String, password: String, cb: Callable) -> void:
	var data := _load_accounts()
	var accounts: Dictionary = data.get("accounts", {})
	var salt := str(randi()) + str(Time.get_ticks_usec())
	var now := int(Time.get_unix_time_from_system())
	var pid := "hk_%s_%d" % [u.md5_text().left(8), now]
	var acc := {
		"salt": salt,
		"hash": _hash(password, salt),
		"pid": pid,
		"created": now,
		"token": "",
	}
	accounts[u] = acc
	data["accounts"] = accounts
	data["last_user"] = u
	if not _save_accounts(data):
		_cb(cb, false, "账号保存失败，请检查存储权限")
		return
	CloudSync.push_account(tree, u, salt, str(acc.get("hash", "")), pid)
	_finish_login(tree, u, acc, cb)


static func _finish_login(tree: SceneTree, username: String, acc: Dictionary, cb: Callable) -> void:
	var now := int(Time.get_unix_time_from_system())
	var pid := str(acc.get("pid", ""))
	var token := str(acc.get("token", ""))
	# 切换本地数据目录到该账号；新账号目录为空 → 不会继承上一个账号的数据
	UserScope.set_active(pid)
	PlayerPrefs.reload()
	RankSystem.reload()
	HeroBuildStore.reload()
	CloudSync.ensure_defaults()
	var cfg := PlayerPrefs.cloud_cfg()
	cfg["pid"] = pid
	cfg["token"] = token
	cfg["username"] = username
	PlayerPrefs.set_cloud_cfg(cfg)
	_save_session({
		"username": username, "pid": pid, "token": token,
		"expires": now + SESSION_SECONDS,
	})
	if not CloudSync.is_configured():
		_cb(cb, true, "登录成功（本机账号）")
		return
	CloudSync.download(tree, func(ok: bool, code: int, msg: String) -> void:
		if ok:
			_cb(cb, true, "登录成功，云端数据已同步")
		else:
			_cb(cb, true, "登录成功（云端同步失败：%s）" % msg.left(40)))


static func _hash(password: String, salt: String) -> String:
	return (salt + "::" + password).sha256_text()


static func _cb(cb: Callable, ok: bool, msg: String) -> void:
	if cb.is_valid():
		cb.call(ok, msg)






