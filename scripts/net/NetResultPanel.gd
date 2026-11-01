class_name NetResultPanel
extends ResultsPanel
## 联机客户端 / 回放结算页：不再单独实现一套版式，
## 直接把 broadcast/录像里的统计行包成 HeroStatView，交给单机同款 ResultsPanel 渲染。
## 对外接口保持不变：defer / _on_result(payload) / show_deferred()

const HeroStatViewScript = preload("res://scripts/ui/HeroStatView.gd")

var defer := false          # true=先播终局演出，播完再显示结算页（由联机/回放控制）
var _payload: Dictionary = {}


func _ready() -> void:
	visible = false
	process_mode = PROCESS_MODE_ALWAYS
	# 联机：结算广播到达时先暂存，等终局演出播完再显示（与旧实现同语义）
	if not NetSession.net_game_over.is_connected(_on_result):
		NetSession.net_game_over.connect(_on_result)


## payload: {winner, dur, player_team, rows[], rank?, replay?}
func _on_result(p: Dictionary) -> void:
	_payload = p
	if defer:
		return
	var rows: Array = p.get("rows", []) if p.get("rows", []) is Array else []
	var pteam := int(p.get("player_team", Config.player_team))
	var heroes: Array = []
	var mine = null
	# 联机结算行来自 host，所有真人行的 mine 都是 true；不能按行里的 mine 取最后一个人。
	# 本机接管英雄名由 NetSession.current_manifest() 提供，优先精确匹配自己。
	var local_name := str(NetSession.current_manifest().get("hero_name", ""))
	for r in rows:
		if not (r is Dictionary):
			continue
		var rd: Dictionary = r
		var v = HeroStatViewScript.from_row(rd)
		heroes.append(v)
		if mine == null:
			mine = v
		if local_name != "" and str(rd.get("name", "")) == local_name:
			mine = v
		elif local_name == "" and bool(rd.get("mine", false)):
			mine = v
	if mine == null and not heroes.is_empty():
		mine = heroes[0]
	var is_replay: bool = bool(p.get("replay", false))
	var model := {
		"heroes": heroes,
		"hero": mine,
		"player_team": pteam,
		"winner": int(p.get("winner", -1)),
		"game_time": float(p.get("dur", 0.0)),
		"rank_result": p.get("rank", {}) if p.get("rank", {}) is Dictionary else {},
		"team_gold_diff_history": p.get("gold_hist", []) if p.get("gold_hist", []) is Array else [],
		"mode": "replay" if is_replay else "net",
		# 回放没有真实排位结算，绝不能在这里写 rank.json
		"suppress_rank": is_replay,
	}
	setup_model(model)
	visible = not defer


## 终局演出播完后再显示（联机/回放调用）
func show_deferred() -> void:
	defer = false
	if _payload.is_empty():
		visible = true
		return
	# 重放一次渲染（与旧实现一致：show_deferred 会按 payload 重新出界面）
	_on_result(_payload)
	visible = true

