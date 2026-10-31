class_name RankSystem
extends RefCounted
## 本机排位段位：大段位 → 小段位 → 星星，胜 +1 星、负 -1 星；
## 满星晋级、0 星掉段/掉星，青铜 III 为最低保护；勇者积分满 100 时负场保星。
## 数据存 user://rank.json，受限环境退回 res://saves/rank.json。

const SAVE_PATH := "user://rank.json"
const FALLBACK_PATH := "res://saves/rank.json"

const KING_INDEX := 6
const MAX_POINTS := 100

const TIER_NAMES := [
	"倔强青铜", "秩序白银", "荣耀黄金", "尊贵铂金", "永恒钻石", "至尊星耀", "最强王者",
]
# 小段位从低到高；王者没有小段位
const TIER_SUBS := [
	["Ⅲ", "Ⅱ", "Ⅰ"],
	["Ⅲ", "Ⅱ", "Ⅰ"],
	["Ⅳ", "Ⅲ", "Ⅱ", "Ⅰ"],
	["Ⅳ", "Ⅲ", "Ⅱ", "Ⅰ"],
	["Ⅴ", "Ⅳ", "Ⅲ", "Ⅱ", "Ⅰ"],
	["Ⅴ", "Ⅳ", "Ⅲ", "Ⅱ", "Ⅰ"],
	[],
]
# 每个小段位需要的星星数；王者不封顶
const TIER_STARS := [3, 4, 4, 5, 5, 5, 999]

static var _data: Dictionary = {}
static var _loaded := false


static func _default_state() -> Dictionary:
	return {
		"tier": 0, "sub": 0, "stars": 0, "points": 0,
		"wins": 0, "losses": 0, "streak": 0,
	}


static func _normalize(src: Dictionary) -> Dictionary:
	var d := _default_state()
	var t := clampi(int(src.get("tier", 0)), 0, KING_INDEX)
	d["tier"] = t
	var subs: Array = TIER_SUBS[t]
	if subs.is_empty():
		d["sub"] = 0
		d["stars"] = clampi(int(src.get("stars", 0)), 0, 999)
	else:
		d["sub"] = clampi(int(src.get("sub", 0)), 0, subs.size() - 1)
		d["stars"] = clampi(int(src.get("stars", 0)), 0, int(TIER_STARS[t]) - 1)
	d["points"] = clampi(int(src.get("points", 0)), 0, MAX_POINTS)
	d["wins"] = maxi(0, int(src.get("wins", 0)))
	d["losses"] = maxi(0, int(src.get("losses", 0)))
	d["streak"] = maxi(0, int(src.get("streak", 0)))
	return d


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
			_data = _normalize(parsed)
			return
	_data = _default_state()


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


static func state() -> Dictionary:
	_ensure_loaded()
	_data = _normalize(_data)
	return _data.duplicate(true)


static func label(st: Dictionary = {}) -> String:
	var d: Dictionary = state() if st.is_empty() else _normalize(st)
	var t := int(d.get("tier", 0))
	if t == KING_INDEX:
		var stars := int(d.get("stars", 0))
		var king_name := "最强王者"
		if stars >= 100:
			king_name = "传奇王者"
		elif stars >= 50:
			king_name = "荣耀王者"
		elif stars >= 25:
			king_name = "无双王者"
		return "%s · %d★" % [king_name, stars]
	var subs: Array = TIER_SUBS[t]
	var sub := str(subs[clampi(int(d.get("sub", 0)), 0, subs.size() - 1)])
	return "%s %s · %d★" % [TIER_NAMES[t], sub, int(d.get("stars", 0))]


static func star_text(st: Dictionary = {}) -> String:
	var d: Dictionary = state() if st.is_empty() else _normalize(st)
	var t := int(d.get("tier", 0))
	if t == KING_INDEX:
		return "%d★" % int(d.get("stars", 0))
	var full := int(d.get("stars", 0))
	var mx := int(TIER_STARS[t])
	var s := ""
	for i in mx:
		s += "★" if i < full else "☆"
	return s


static func tier_color(st: Dictionary = {}) -> Color:
	var d: Dictionary = state() if st.is_empty() else _normalize(st)
	match int(d.get("tier", 0)):
		0: return Color(0.76, 0.52, 0.34)
		1: return Color(0.78, 0.82, 0.88)
		2: return Color(0.98, 0.78, 0.30)
		3: return Color(0.42, 0.86, 0.76)
		4: return Color(0.55, 0.72, 1.0)
		5: return Color(0.80, 0.55, 1.0)
		_: return Color(1.0, 0.78, 0.30)


# 供加载界面 AI 卡使用：以 AI 难度对应的大段位为中心上下浮动，做出一局匹配的五人段位分布
static func ai_label(seed_text: String, center_tier: int = -1) -> String:
	var p := state()
	var h := absi(hash(seed_text))
	var center := int(p.get("tier", 0)) if center_tier < 0 else clampi(center_tier, 0, KING_INDEX)
	var t := clampi(center + (h % 3) - 1, 0, KING_INDEX)
	var d := _default_state()
	d["tier"] = t
	if t == KING_INDEX:
		var base_stars := int(p.get("stars", 0)) if int(p.get("tier", 0)) == KING_INDEX else 0
		d["stars"] = clampi(base_stars + (h % 61) - 30, 0, 300)
	else:
		var subs: Array = TIER_SUBS[t]
		d["sub"] = h % subs.size()
		d["stars"] = h % int(TIER_STARS[t])
	return label(d)


# 单场结算：胜利 +1 星，失败 -1 星；勇者积分满时失败保星。
# 返回 old/new 段位和升/降级标记，供结算页展示。
static func apply_result(win: bool, mvp: bool = false) -> Dictionary:
	_ensure_loaded()
	var d := _normalize(_data)
	var old_state := d.duplicate(true)
	var old_label := label(d)
	var promoted := false
	var demoted := false
	var protected := false
	var floor_protected := false
	var star_change := 0

	if win:
		d["wins"] = int(d.get("wins", 0)) + 1
		d["streak"] = int(d.get("streak", 0)) + 1
		var t := int(d.get("tier", 0))
		d["stars"] = int(d.get("stars", 0)) + 1
		star_change = 1
		if t < KING_INDEX and int(d["stars"]) >= int(TIER_STARS[t]):
			d["stars"] = 0
			if int(d.get("sub", 0)) < TIER_SUBS[t].size() - 1:
				d["sub"] = int(d.get("sub", 0)) + 1
			else:
				d["tier"] = t + 1
				d["sub"] = 0
			promoted = true
		d["points"] = mini(MAX_POINTS, int(d.get("points", 0)) + 20
			+ (10 if mvp else 0) + mini(int(d.get("streak", 0)), 5) * 2)
	else:
		d["losses"] = int(d.get("losses", 0)) + 1
		d["streak"] = 0
		if int(d.get("points", 0)) >= MAX_POINTS:
			d["points"] = int(d.get("points", 0)) - MAX_POINTS
			protected = true
		else:
			star_change = -1
			var t := int(d.get("tier", 0))
			if t == KING_INDEX:
				if int(d.get("stars", 0)) > 0:
					d["stars"] = int(d.get("stars", 0)) - 1
				else:
					d["tier"] = KING_INDEX - 1
					d["sub"] = TIER_SUBS[KING_INDEX - 1].size() - 1
					d["stars"] = int(TIER_STARS[KING_INDEX - 1]) - 1
					demoted = true
			elif int(d.get("stars", 0)) > 0:
				d["stars"] = int(d.get("stars", 0)) - 1
			elif int(d.get("sub", 0)) > 0:
				d["sub"] = int(d.get("sub", 0)) - 1
				d["stars"] = int(TIER_STARS[t]) - 1
				demoted = true
			elif t > 0:
				d["tier"] = t - 1
				d["sub"] = TIER_SUBS[t - 1].size() - 1
				d["stars"] = int(TIER_STARS[t - 1]) - 1
				demoted = true
			else:
				d["stars"] = 0
				star_change = 0
				floor_protected = true
			d["points"] = mini(MAX_POINTS, int(d.get("points", 0)) + 10)

	_data = _normalize(d)
	_flush()
	return {
		"old_state": old_state, "new_state": _data.duplicate(true),
		"old_label": old_label, "new_label": label(_data),
		"star_change": star_change, "promoted": promoted,
		"demoted": demoted, "protected": protected,
		"floor_protected": floor_protected,
	}


# 测试/重置用
static func reset() -> void:
	_data = _default_state()
	_loaded = true
	_flush()
