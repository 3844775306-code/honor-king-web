class_name MatchResult
extends RefCounted
## 三端（单机 / 联机客户端 / 回放）共用的赛后数据口径：
## 统计归一 → 对战评分 → 奖牌 → 奖牌积分加成 → 铭牌/个人详情数据。
## 任何一端要展示"评分/奖牌/加成"，都必须调用这里，不准再各写一份公式。

# —— 奖牌门槛（评分制）：金牌 ≥78 / 银牌 ≥64 / 铜牌 ≥52，其余无奖牌 ——
const MEDAL_GOLD := 78.0
const MEDAL_SILVER := 64.0
const MEDAL_BRONZE := 52.0
# —— 顶级评价额外积分：评分 >90 再 +200（与奖牌加成叠加） ——
const TOP_BONUS_RATING := 90.0
const TOP_BONUS_POINTS := 200

const ROW_KEYS := ["name", "team", "k", "d", "a", "dmg", "taken", "gold", "heal", "last_hits", "turret", "cc", "jungle"]


## 把 Hero 节点或回放/联机的统计字典统一成同一份统计字典
static func stats_of(u) -> Dictionary:
	if u == null:
		return {}
	if u is Hero:
		var h: Hero = u
		return {
			"name": str(h.display_name), "team": int(h.team),
			"k": int(h.kills), "d": int(h.deaths), "a": int(h.assists),
			"dmg": float(h.damage_dealt_to_heroes), "taken": float(h.damage_taken_from_heroes),
			"gold": int(h.total_gold_earned), "heal": float(h.healing_done),
			"last_hits": int(h.last_hits), "turret": float(h.turret_damage),
			"cc": float(h.cc_duration_dealt), "jungle": int(h.jungle_gold),
		}
	if u is Dictionary:
		var r: Dictionary = u
		return {
			"name": str(r.get("name", "")), "team": int(r.get("team", -1)),
			"k": int(r.get("k", 0)), "d": int(r.get("d", 0)), "a": int(r.get("a", 0)),
			"dmg": float(r.get("dmg", 0.0)), "taken": float(r.get("taken", 0.0)),
			"gold": int(r.get("gold", 0)), "heal": float(r.get("heal", 0.0)),
			"last_hits": int(r.get("last_hits", 0)), "turret": float(r.get("turret", 0.0)),
			"cc": float(r.get("cc", 0.0)), "jungle": int(r.get("jungle", 0)),
		}
	return {}


## 队伍内归一化评分（0~100）：击杀 .15 / 助攻 .10 / 死亡 .05 / 经济 .15 / 输出 .25 / 承伤 .10 / 参团 .20
static func rating(row, team_rows: Array) -> float:
	var me: Dictionary = stats_of(row)
	if me.is_empty():
		return 0.0
	var mx_k := 1
	var mx_dmg := 1.0
	var mx_gold := 1
	var mx_taken := 1.0
	var tot_k := 0
	var mx_d := 1
	for o in team_rows:
		var s: Dictionary = stats_of(o)
		if s.is_empty():
			continue
		mx_k = maxi(mx_k, int(s["k"]))
		mx_dmg = maxf(mx_dmg, float(s["dmg"]))
		mx_gold = maxi(mx_gold, int(s["gold"]))
		mx_taken = maxf(mx_taken, float(s["taken"]))
		tot_k += int(s["k"])
		mx_d = maxi(mx_d, int(s["d"]))
	var kill_score := float(me["k"]) / float(mx_k) * 100.0
	var assist_score := float(me["a"]) / float(maxi(1, tot_k)) * 100.0
	var death_score := maxf(0.0, 1.0 - float(me["d"]) / float(maxi(1, mx_d))) * 100.0
	var gold_score := float(me["gold"]) / float(mx_gold) * 100.0
	var dmg_score := float(me["dmg"]) / mx_dmg * 100.0
	var taken_score := float(me["taken"]) / mx_taken * 100.0
	var part := float(int(me["k"]) + int(me["a"])) / float(maxi(1, tot_k)) * 100.0
	return clampf(kill_score * 0.15 + assist_score * 0.10 + death_score * 0.05
		+ gold_score * 0.15 + dmg_score * 0.25 + taken_score * 0.10 + part * 0.20, 0.0, 100.0)


## 评分 → 奖牌：0 金 / 1 银 / 2 铜 / -1 无
static func medal_by_rating(r: float) -> int:
	if r >= MEDAL_GOLD:
		return 0
	if r >= MEDAL_SILVER:
		return 1
	if r >= MEDAL_BRONZE:
		return 2
	return -1


static func medal_name(i: int) -> String:
	match i:
		0: return "金牌"
		1: return "银牌"
		2: return "铜牌"
	return ""


static func medal_color(i: int) -> Color:
	match i:
		0: return Color(1.0, 0.84, 0.32)
		1: return Color(0.86, 0.91, 1.0)
		2: return Color(0.92, 0.64, 0.38)
	return Color(0.7, 0.74, 0.84)


## 奖牌积分加成（不含顶级评价）
static func medal_bonus(medal: int) -> int:
	return RankSystem.medal_bonus(medal)


## 顶级评价加成（评分 >90）
static func top_bonus(r: float) -> int:
	return TOP_BONUS_POINTS if r > TOP_BONUS_RATING else 0


## 本局总加成 = 奖牌 + 顶级评价
static func rank_bonus(medal: int, r: float) -> int:
	return medal_bonus(medal) + top_bonus(r)


## 队伍 MVP：评分最高者（返回原对象，Hero 或字典）
static func mvp_of(units: Array):
	var team_rows: Array = []
	for u in units:
		team_rows.append(u)
	var best = null
	var best_r := -1.0
	for u in units:
		var r: float = rating(u, team_rows)
		if r > best_r:
			best_r = r
			best = u
	return best


## 个人详情里的段位/积分行（三端一致）
static func rank_lines(rank_result: Dictionary, duration: float) -> Array:
	var out: Array = []
	if not rank_result.is_empty():
		var rr: Dictionary = rank_result
		var old_s: Dictionary = rr.get("old_state", {})
		var new_s: Dictionary = rr.get("new_state", {})
		var pts: int = int(rr.get("point_change", int(new_s.get("points", 0)) - int(old_s.get("points", 0))))
		out.append("本局积分 %+d" % pts)
		var mb: int = int(rr.get("medal_bonus", 0))
		if mb > 0:
			out.append("奖牌加成 %+d 积分" % mb)
		var tb: int = int(rr.get("top_bonus", 0))
		if tb > 0:
			out.append("顶级评价 %+d 积分" % tb)
		out.append("本局星数 %+d★" % int(rr.get("star_change", 0)))
		out.append("段位 %s → %s" % [str(rr.get("old_label", "")), str(rr.get("new_label", ""))])
		if bool(rr.get("promoted", false)):
			out.append("↑ 晋升")
		elif bool(rr.get("demoted", false)):
			out.append("↓ 降级")
		elif bool(rr.get("floor_protected", false)):
			out.append("最低段位保护")
	else:
		out.append("本局不计排位星")
	out.append("对局时长 %02d:%02d" % [int(duration) / 60, int(duration) % 60])
	return out
