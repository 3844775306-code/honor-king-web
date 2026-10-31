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
	var fwd := Vector3(sin(hero.rotation.y), 0.0, cos(hero.rotation.y))
	var pos: Vector3 = hero.global_position + fwd * 3.0
	var enemy = bm.spawn_single_minion("melee", 1, pos, [pos], 0)
	if enemy != null:
		enemy.waypoints = [pos]
		enemy.vision_range = 0.1
	hero.manual_target = enemy
	hero.attack_timer = 0.0
	await get_tree().create_timer(0.2).timeout
	# 1) 有锁定目标、但没按普攻键：连续 3 帧「移动中就绪」都不应出手
	var hp0: float = enemy.health if is_instance_valid(enemy) else -1.0
	var lock0: float = hero._move_lock_until
	var anim0: float = hero._aa_anim_until
	for k in range(3):
		hero.attack_timer = 0.0
		hero._try_walk_attack()
	var hp1: float = enemy.health if is_instance_valid(enemy) else hp0
	print("A|NO_KEY dmg=%.0f lock_delta=%.4f anim_delta=%.4f attack_timer=%.3f" % [
		hp0 - hp1, hero._move_lock_until - lock0, hero._aa_anim_until - anim0, hero.attack_timer])
	# 2) 按住普攻键：同一帧条件应立即出手（走A）
	var hp2: float = enemy.health if is_instance_valid(enemy) else 0.0
	hero.attack_timer = 0.0
	Input.action_press("ui_accept")
	hero._try_walk_attack()
	Input.action_release("ui_accept")
	var hp3: float = enemy.health if is_instance_valid(enemy) else 0.0
	print("B|HELD dmg=%.0f lock_set=%s attack_timer=%.3f" % [hp2 - hp3,
		str(hero._move_lock_until > lock0), hero.attack_timer])
	print("PROBE_DONE")
	get_tree().quit()
