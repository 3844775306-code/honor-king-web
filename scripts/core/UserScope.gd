class_name UserScope
extends RefCounted
## 本地用户数据按账号隔离：user://accounts/<pid>/ 下存该账号的存档/录像。
## 全局文件（账号表 accounts.json、会话 account_session.json、active_account.txt）不隔离。
## 首次运行会把旧的 user:// 根目录存档迁移到当前账号目录。

const ACTIVE_PATH := "user://active_account.txt"
const GLOBAL_FILES := ["accounts.json", "account_session.json"]
const LEGACY_FILES := ["player_prefs.json", "profile.cfg", "rank.json", "battle_history.json",
	"hero_builds.json", "lingbao.cfg", "ai_chat.cfg", "paired_devices.cfg", "cloud_sync_meta.json"]

static var _ensured := false


static func ensure() -> void:
	if _ensured:
		return
	_ensured = true
	_make_dir(dir())
	_migrate_legacy()


## 当前账号 pid：active_account.txt → 会话 pid → guest
static func active_pid() -> String:
	if FileAccess.file_exists(ACTIVE_PATH):
		var s := FileAccess.get_file_as_string(ACTIVE_PATH).strip_edges()
		if s != "":
			return s
	var gp := "user://account_session.json"
	if FileAccess.file_exists(gp):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gp))
		if parsed is Dictionary:
			var pid: String = str((parsed as Dictionary).get("pid", ""))
			if pid != "":
				return pid
	# 会话过期/未登录：用账号表里最后一次登录的账号 pid，保证旧存档迁到正确账号
	var ap := "user://accounts.json"
	if FileAccess.file_exists(ap):
		var ad: Variant = JSON.parse_string(FileAccess.get_file_as_string(ap))
		if ad is Dictionary:
			var last := str((ad as Dictionary).get("last_user", ""))
			var accs: Variant = (ad as Dictionary).get("accounts", {})
			if accs is Dictionary and (accs as Dictionary).has(last):
				var apid := str(((accs as Dictionary)[last] as Dictionary).get("pid", ""))
				if apid != "":
					return apid
	return "guest"


static func set_active(pid: String) -> void:
	var p := pid.strip_edges()
	if p == "":
		p = "guest"
	var f := FileAccess.open(ACTIVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(p)
		f.close()
	_make_dir(dir())
	_ensured = true


static func dir() -> String:
	return "user://accounts/%s/" % active_pid()


## 账号隔离文件路径（players_prefs/rank/...）
static func path(name: String) -> String:
	ensure()
	return dir() + name


static func replays_dir() -> String:
	ensure()
	return dir() + "replays/"


static func is_global(name: String) -> bool:
	return name in GLOBAL_FILES


static func _make_dir(p: String) -> void:
	var abs := ProjectSettings.globalize_path(p)
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)


## 旧版本所有数据在 user:// 根：首次运行迁移到当前账号目录
static func _migrate_legacy() -> void:
	var d := dir()
	_make_dir(d)
	for n in LEGACY_FILES:
		var src: String = "user://" + str(n)
		var dst: String = d + str(n)
		if FileAccess.file_exists(src) and not FileAccess.file_exists(dst):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst))
	# 录像目录
	var src_dir: String = "user://replays"
	var dst_dir: String = d + "replays"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(src_dir)) \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dst_dir)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(src_dir), ProjectSettings.globalize_path(dst_dir))


