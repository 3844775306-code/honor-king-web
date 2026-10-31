extends Node3D

var hero = null

func _edges(dur: float) -> int:
	var n := 0
	var prev := false
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < dur:
		await get_tree().process_frame
		var now := hero.attack_timer > 0.001
		if now and not prev:
			n += 1
		prev = now
	return n

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/battle.tscn")
	var bm: Node = ps.instantiate()
	add_child(bm)
	for i in range(6):
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	bm._start_game("吕布")
	var waited := 0.0
	while waited < 8.0 and bm.hero == null:
		await get_tree().process_frame
		waited += get_process_delta_time()
	hero = bm.hero
	if hero == null:
		print("NO HERO")
		get_tree().quit()
		return
	hero.global_position = Vector3(0.0, 2.0, 0.0)
	await get_tree().create_timer(0.1).timeout
	var fwd := Vector3(sin(hero.rotation.y), 0.0, cos(hero.rotation.y))
	var pos: Vector3 = hero.global_position + fwd * 2.0
	var enemy = bm.spawn_single_minion("melee", 1, pos, [pos], 0)
	if enemy != null:
		enemy.waypoints = [pos]
		enemy.vision_range = 0.1
	# 先开始移动，再挂锁定，避免站定分支在计时前先打一发
	Input.action_press("ui_up")
	await get_tree().create_timer(0.3).timeout
	hero.manual_target = enemy
	hero.attack_timer = 0.0
	hero._move_lock_until = 0.0
	var n1: int = await _edges(2.0)
	print("A|MOVE_ONLY(no atk key) attacks=%d" % n1)
	Input.action_press("ui_accept")
	hero.attack_timer = 0.0
	hero._move_lock_until = 0.0
	var n2: int = await _edges(2.0)
	print("B|MOVE+ATK_KEY attacks=%d" % n2)
	Input.action_release("ui_accept")
	Input.action_release("ui_up")
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(enemy):
		hero.manual_target = enemy
	hero.attack_timer = 0.0
	hero._move_lock_until = 0.0
	var n3: int = await _edges(1.6)
	print("C|STAND_AUTO(no keys) attacks=%d" % n3)
	print("PROBE_DONE")
	get_tree().quit()
