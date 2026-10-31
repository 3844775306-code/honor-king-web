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
	await get_tree().create_timer(0.2).timeout
	var hp0: float = enemy.health
	var p0: Vector3 = hero.global_position
	# —— 1) 只按移动（W），不按普攻键：应纯移动、不攻击
	Input.action_press("ui_up")
	await get_tree().create_timer(1.5).timeout
	var hp1: float = enemy.health if is_instance_valid(enemy) else hp0
	var p1: Vector3 = hero.global_position
	var moved1: float = Vector2(p1.x - p0.x, p1.z - p0.z).length()
	print("A|NO_ATTACK_KEY move=%.2f dmg=%.0f manual_target=%s dist=%.2f" % [moved1, hp0 - hp1,
		str(hero.manual_target != null),
		Vector2(enemy.global_position.x - hero.global_position.x, enemy.global_position.z - hero.global_position.z).length() if is_instance_valid(enemy) else -1.0])
	# —— 2) 继续按移动 + 按住普攻键：应走A（边移动边攻击）
	var hp2: float = enemy.health
	var p2: Vector3 = hero.global_position
	Input.action_press("ui_accept")
	await get_tree().create_timer(1.5).timeout
	var hp3: float = enemy.health if is_instance_valid(enemy) else hp2
	var p3: Vector3 = hero.global_position
	print("B|WALK_ATTACK_HELD move=%.2f dmg=%.0f" % [
		Vector2(p3.x - p2.x, p3.z - p2.z).length(), hp2 - hp3])
	Input.action_release("ui_accept")
	Input.action_release("ui_up")
	# —— 3) 停下后站定自动普攻（锁定目标）仍应生效
	await get_tree().create_timer(1.6).timeout
	var hp4: float = enemy.health if is_instance_valid(enemy) else 0.0
	print("C|STAND_AUTO dmg_after_stop=%.0f" % (hp3 - hp4))
	print("PROBE_DONE")
	get_tree().quit()
