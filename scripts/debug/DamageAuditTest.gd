extends Node
## 单机伤害公式自检：godot --headless --path . res://scripts/debug/damage_audit_test.tscn
## 覆盖物理/法术/固定穿甲/百分比穿甲/护盾/真伤；只验证单机 take_damage 公式。

var bm: BattleManager = null
var src: Hero = null
var _fails: int = 0
var _t: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())


func _process(_d: float) -> void:
	_t += 1
	if _t < 45:
		get_tree().paused = false
	if _t == 45:
		Config.player_team = Config.Team.PLAYER
		Config._team_rolled = true
		bm = get_tree().get_first_node_in_group("battle_manager")
		bm._start_game_body("后羿", "flash")
	elif _t == 130:
		_run()
		print("[DAMAGE_TEST] %s" % ("ALL PASS" if _fails == 0 else "%d FAIL" % _fails))
		get_tree().quit(1 if _fails > 0 else 0)


func _dummy(armor: float, mr: float, shield: float = 0.0, hp: float = 5000.0) -> GameEntity:
	var e := GameEntity.new()
	e.setup({"name": "伤害木桩", "team": Config.Team.ENEMY, "max_health": hp,
		"armor": armor, "magic_resist": mr})
	bm.add_child(e)
	e.shield_remaining = shield
	return e


func _loss(t: GameEntity, amount: float, magic := false, skill := 99, pen := 0.0) -> float:
	var before := t.health
	t.take_damage(amount, src, magic, skill, pen)
	return before - t.health


func _check(name: String, got: float, want: float, tol := 1.0) -> void:
	var ok: bool = absf(got - want) <= tol
	if not ok:
		_fails += 1
	print("[DAMAGE_TEST] %s %s got=%.2f want=%.2f" % ["PASS" if ok else "FAIL", name, got, want])


func _run() -> void:
	for e in get_tree().get_nodes_in_group("heroes"):
		if e is Hero and int(e.team) == Config.Team.PLAYER:
			src = e
			break
	if src == null:
		_fails += 1
		print("[DAMAGE_TEST] FAIL no player hero")
		return
	src.flat_phys_pen = 0.0
	src.flat_magic_pen = 0.0
	# 1 物理：1000 vs 602 护甲 → 500
	_check("物理602甲", _loss(_dummy(602, 0), 1000.0), 500.0)
	# 2 法术：1000 vs 602 魔抗 → 500
	_check("法术602抗", _loss(_dummy(0, 602), 1000.0, true), 500.0)
	# 3 固定穿甲：100 → 300甲；1000*(1-200/802)
	src.flat_phys_pen = 100.0
	_check("固定穿甲100", _loss(_dummy(300, 0), 1000.0), 1000.0 * (1.0 - 200.0 / 802.0))
	src.flat_phys_pen = 0.0
	# 4 百分比穿甲：50% → 602甲变301；1000*(1-301/903)
	_check("百分比穿甲50%", _loss(_dummy(602, 0), 1000.0, false, 99, 0.5), 1000.0 * (1.0 - 301.0 / 903.0))
	# 5 护盾足量：1500盾吃1000 → 不掉血，盾余500
	var sh := _dummy(0, 0, 1500.0)
	var sh_loss := _loss(sh, 1000.0)
	_check("护盾吸收", sh_loss, 0.0)
	_check("护盾余量", sh.shield_remaining, 500.0)
	# 6 真伤：1000 vs 602甲+300盾 → 掉1000血，盾不掉
	var tr := _dummy(602, 0, 300.0)
	var tr_before := tr.health
	tr.take_true_damage(1000.0, src, false, 99)
	_check("真伤掉血", tr_before - tr.health, 1000.0)
	_check("真伤不破盾", tr.shield_remaining, 300.0)
