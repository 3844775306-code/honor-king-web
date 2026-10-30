extends Node3D

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
	var hero = bm.hero
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
	hero.manual_target = enemy
	hero.attack_timer = 0.0
	await get_tree().create_timer(0.1).timeout
	# —— 1) 只按住移动（W），不按普攻：不应出手、不应锁移动
	var fired := 0
	var locked := 0
	var p0: Vector3 = hero.global_position
	Input.action_press("ui_up")
	var t0 := Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 2.0:
		await get_tree().process_frame
		if hero.attack_timer > 0.001:
			fired += 1
		if Time.get_ticks_msec() * 0.001 < hero._move_lock_until:
			locked += 1
	var moved: float = Vector2(hero.global_position.x - p0.x, hero.global_position.z - p0.z).length()
	print("A|MOVE_ONLY attack_frames=%d lock_frames=%d moved=%.2f" % [fired, locked, moved])
	# —— 2) 同时按住移动 + 普攻：应走A（出手并短暂锁移动）
	fired = 0
	locked = 0
	var p1: Vector3 = hero.global_position
	Input.action_press("ui_accept")
	t0 = Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 2.0:
		await get_tree().process_frame
		if hero.attack_timer > 0.001:
			fired += 1
		if Time.get_ticks_msec() * 0.001 < hero._move_lock_until:
			locked += 1
	var moved2: float = Vector2(hero.global_position.x - p1.x, hero.global_position.z - p1.z).length()
	print("B|MOVE_AND_ATTACK attack_frames=%d lock_frames=%d moved=%.2f" % [fired, locked, moved2])
	Input.action_release("ui_accept")
	Input.action_release("ui_up")
	# —— 3) 站定（不按键）时锁定目标自动普攻仍生效
	await get_tree().create_timer(0.6).timeout
	hero.attack_timer = 0.0
	if is_instance_valid(enemy):
		hero.manual_target = enemy
	var stand_fired := 0
	t0 = Time.get_ticks_msec() / 1000.0
	while Time.get_ticks_msec() / 1000.0 - t0 < 1.5:
		await get_tree().process_frame
		if hero.attack_timer > 0.001:
			stand_fired += 1
	print("C|STAND_AUTO attack_frames=%d" % stand_fired)
	print("PROBE_DONE")
	get_tree().quit()
