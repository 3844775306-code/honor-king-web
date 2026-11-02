class_name RankSystem
extends RefCounted
## 本机排位段位：大段位 → 小段位 → 星星。
## 取消勇者积分：每局按积分结算，常规胜/负基础 99~101 分，
## 奖牌额外加分，评分 >90 额外 +200；每 100 分换算 1 颗星。
## 数据存 user://rank.json，受限环境退回 res://saves/rank.json。

const SAVE_PATH := "user://rank.json"
const FALLBACK_PATH := "res://saves/rank.json"

const KING_INDEX := 6
const STAR_POINTS := 100
const MAX_POINTS := STAR_POINTS   # 兼容旧 UI 引用：现在表示「每颗星 100 分」

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
	d["points"] = clampi(int(src.get("points", 0)), 0, STAR_POINTS - 1)
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


## 云端恢复后重新从磁盘加载（清内存缓存）
static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()


static func _flush() -> void:
	var txt := JSON.stringify(_data, "\t")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()
		CloudSync.schedule_push()
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


# 奖牌额外积分：铜 +12 / 银 +33 / 金 +100（medal: 0=金 1=银 2=铜 -1=无）
static func medal_bonus(medal: int) -> int:
	match medal:
		0: return 100
		1: return 33
		2: return 12
	return 0


# 单场结算：基础胜/负 ±99~101 分，加上奖牌/顶级评价加分；
# 每 100 分换算 1 颗星，余数留在 points 里继续累计。
# bonus_points：本局额外积分（奖牌 + 评分 >90 的顶级加成）。
static func apply_result(win: bool, mvp: bool = false, bonus_points: int = 0) -> Dictionary:
	_ensure_loaded()
	var d := _normalize(_data)
	var old_state := d.duplicate(true)
	var old_label := label(d)
	var promoted := false
	var demoted := false
	var floor_protected := false
	var star_change := 0
	var base_points := randi_range(99, 101)
	var point_change := (base_points if win else -base_points) + bonus_points

	if win:
		d["wins"] = int(d.get("wins", 0)) + 1
		d["streak"] = int(d.get("streak", 0)) + 1
	else:
		d["losses"] = int(d.get("losses", 0)) + 1
		d["streak"] = 0

	# 积分 → 星星：每 100 分 1 星，多余/不足部分保留为当前星内进度
	var total := int(d.get("points", 0)) + point_change
	while total >= STAR_POINTS:
		total -= STAR_POINTS
		if _gain_star(d):
			promoted = true
		star_change += 1
	while total < 0:
		var lost := _lose_star(d)
		if bool(lost.get("lost", false)):
			total += STAR_POINTS
			star_change -= 1
			if bool(lost.get("demoted", false)):
				demoted = true
		else:
			total = 0
			floor_protected = true
			break
	d["points"] = clampi(total, 0, STAR_POINTS - 1)

	_data = _normalize(d)
	_flush()
	return {
		"old_state": old_state, "new_state": _data.duplicate(true),
		"old_label": old_label, "new_label": label(_data),
		"star_change": star_change, "point_change": point_change,
		"base_points": base_points, "bonus_points": bonus_points,
		"promoted": promoted, "demoted": demoted,
		"protected": false, "floor_protected": floor_protected,
	}


# 增加 1 颗星；返回是否因此晋级
static func _gain_star(d: Dictionary) -> bool:
	var t := int(d.get("tier", 0))
	if t >= KING_INDEX:
		d["stars"] = int(d.get("stars", 0)) + 1
		return false
	var next := int(d.get("stars", 0)) + 1
	if next < int(TIER_STARS[t]):
		d["stars"] = next
		return false
	d["stars"] = 0
	var subs: Array = TIER_SUBS[t]
	if int(d.get("sub", 0)) < subs.size() - 1:
		d["sub"] = int(d.get("sub", 0)) + 1
	else:
		d["tier"] = t + 1
		d["sub"] = 0
	return true


# 扣 1 颗星；返回 {lost, demoted}；最低段位 0 星时 lost=false
static func _lose_star(d: Dictionary) -> Dictionary:
	var t := int(d.get("tier", 0))
	if t >= KING_INDEX:
		if int(d.get("stars", 0)) > 0:
			d["stars"] = int(d.get("stars", 0)) - 1
			return {"lost": true, "demoted": false}
		d["tier"] = KING_INDEX - 1
		d["sub"] = TIER_SUBS[KING_INDEX - 1].size() - 1
		d["stars"] = int(TIER_STARS[KING_INDEX - 1]) - 1
		return {"lost": true, "demoted": true}
	if int(d.get("stars", 0)) > 0:
		d["stars"] = int(d.get("stars", 0)) - 1
		return {"lost": true, "demoted": false}
	if int(d.get("sub", 0)) > 0:
		d["sub"] = int(d.get("sub", 0)) - 1
		d["stars"] = int(TIER_STARS[t]) - 1
		return {"lost": true, "demoted": true}
	if t > 0:
		d["tier"] = t - 1
		d["sub"] = TIER_SUBS[t - 1].size() - 1
		d["stars"] = int(TIER_STARS[t - 1]) - 1
		return {"lost": true, "demoted": true}
	d["stars"] = 0
	return {"lost": false, "demoted": false}


# 测试/重置用
static func reset() -> void:
	_data = _default_state()
	_loaded = true
	_flush()


# 云端恢复：用外部存档覆盖本机段位（结构同 state()）
static func import_state(st: Dictionary) -> bool:
	if st.is_empty():
		return false
	_data = _normalize(st.duplicate(true))
	_loaded = true
	_flush()
	return true


