class_name PlayerPrefs
extends RefCounted
## 本机玩家偏好（目前只有「分路」），存 user://player_prefs.json；
## 受限环境（编辑器沙箱）不可写时退回 res://saves/player_prefs.json。
## 分路取值见 HeroPickData.LANES（对抗路/打野/中路/发育路/游走）。

const SAVE_PATH := "user://player_prefs.json"
const FALLBACK_PATH := "res://saves/player_prefs.json"
const DEFAULT_LANE := "对抗路"

static var _data: Dictionary = {}
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	for p in [SAVE_PATH, FALLBACK_PATH]:
		if not FileAccess.file_exists(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed is Dictionary:
			_data = parsed
			return


static func _flush() -> void:
	var txt := JSON.stringify(_data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
		return
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
