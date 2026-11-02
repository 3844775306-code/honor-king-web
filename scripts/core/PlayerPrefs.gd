class_name PlayerPrefs
extends RefCounted
## 本机玩家偏好（目前只有「分路」），存 user://player_prefs.json；
## 受限环境（编辑器沙箱）不可写时退回 res://saves/player_prefs.json。
## 分路取值见 HeroPickData.LANES（对抗路/打野/中路/发育路/游走）。

static func _save_path() -> String:
	return UserScope.path("player_prefs.json")
const FALLBACK_PATH := "res://saves/player_prefs.json"
const DEFAULT_LANE := "对抗路"

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# user:// 为主、res://saves 兜底：两边各取所需（受限环境 user:// 写失败时靠后者续命）
	for p in [_save_path()]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			for k in parsed.keys():
				if not _data.has(k):
					_data[k] = parsed[k]


## 云端恢复后重新从磁盘加载（清内存缓存）
static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


static func _flush() -> void:
	var txt := JSON.stringify(_data, "\t")
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
		CloudSync.schedule_push()
		return
	# user:// 不可写的受限环境才写 res://saves 兜底（读取时两边合并，主文件优先）
	DirAccess.make_dir_recursive_absolute("res://saves")
	var f2 := FileAccess.open(FALLBACK_PATH, FileAccess.WRITE)
	if f2 != null:
		f2.store_string(txt)
		f2.close()


## 当前分路（中文，见 HeroPickData.LANES）
static func get_lane() -> String:
	_ensure_loaded()
	var lane := str(_data.get("lane", DEFAULT_LANE))
	if not HeroPickData.LANES.has(lane):
		return DEFAULT_LANE
	return lane


static func set_lane(lane: String) -> void:
	if not HeroPickData.LANES.has(lane):
		return
	_ensure_loaded()
	_data["lane"] = lane
	_flush()


## 分路对应的职责（战士/刺客/法师/射手/辅助）
static func get_lane_role() -> String:
	return HeroPickData.lane_role(get_lane())


## AI 难度（0=青铜 … 5=王者，默认黄金）；进对局时由 BattleManager 应用到 AiConfig
static func get_ai_difficulty() -> int:
	_ensure_loaded()
	return clampi(int(_data.get("ai_difficulty", AiConfig.Difficulty.GOLD)), 0, AiConfig.DIFF_TABLE.size() - 1)


static func set_ai_difficulty(d: int) -> void:
	_ensure_loaded()
	_data["ai_difficulty"] = clampi(d, 0, AiConfig.DIFF_TABLE.size() - 1)
	_flush()


# ===== 操作设置（主菜单「操作设置」页写入，局内只读） =====
# 键：siege_keys 小兵/推塔键；target_prio 0=百分比血 1=绝对血 2=最近；auto_chase 0=标准(射程+3m) 1=近(+1m) 2=关
#     lock_portrait 锁敌头像；flash_dir 0=跟随移动方向 1=智能寻敌；skill_sens / cam_sens 灵敏度倍率
#     move_preview 位移预览（含墙体修正）；auto_atk 自动普攻
static func opt_bool(key: String, def: bool) -> bool:
	_ensure_loaded()
	return bool(_data.get("op_" + key, def))


static func opt_int(key: String, def: int) -> int:
	_ensure_loaded()
	return int(_data.get("op_" + key, def))


static func opt_float(key: String, def: float) -> float:
	_ensure_loaded()
	return float(_data.get("op_" + key, def))


static func set_opt(key: String, v) -> void:
	_ensure_loaded()
	_data["op_" + key] = v
	_flush()


# ===== 局内按键自定义布局（局内「设置 → 自定义键位布局」写入，进对局自动套用）=====
# 结构：{ "skill_1": {"x": -30.0, "y": 12.0, "s": 1.15}, ... }
# x/y = 相对默认位置的像素偏移；s = 相对默认尺寸的缩放倍率
static func get_btn_layout() -> Dictionary:
	_ensure_loaded()
	var raw = _data.get("btn_layout", {})
	if raw is Dictionary:
		return raw
	return {}


static func set_btn_layout(layout: Dictionary) -> void:
	_ensure_loaded()
	_data["btn_layout"] = layout
	_flush()


# ===== 云端存档配置（主菜单「云端存档」页写入；{url, token, pid, auto}）=====
static func cloud_cfg() -> Dictionary:
	_ensure_loaded()
	var raw = _data.get("cloud", {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


static func set_cloud_cfg(cfg: Dictionary) -> void:
	_ensure_loaded()
	_data["cloud"] = cfg.duplicate(true)
	_flush()


static func clear_btn_layout() -> void:
	_ensure_loaded()
	_data.erase("btn_layout")
	_flush()





