extends Node

var t := 0
var bm = null
var foe = null
var last_hp := 0.0
var hits := 0
var frame_hits := {}
var cur_frame := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	cur_frame = t
	get_tree().paused = false
	if t == 20:
		Config.player_team = Config.Team.PLAYER
		Config._team_rolled = true
		bm = get_tree().get_first_node_in_group("battle_manager")
		bm._start_game_body("沈梦溪", "flash")
	elif t == 80:
		var h = bm.hero
		h.stat = 10
		for e in get_tree().get_nodes_in_group("heroes"):
			if e.team != h.team and e != h:
				foe = e
				break
		foe.global_position = h.global_position + Vector3(6, 0, 0)
		last_hp = foe.health
		print("L hero=", h.display_name, " is_ai=", h.is_ai, " foe_hp=", "%.0f" % foe.health, " dist=", "%.1f" % h.global_position.distance_to(foe.global_position))
		SkillDatabase.apply_skills(h, 1, foe.global_position)
	elif t > 80 and t < 460:
		if foe and is_instance_valid(foe):
			var hp: float = foe.health
			if absf(hp - last_hp) > 0.5:
				hits += 1
				frame_hits[t] = frame_hits.get(t, [])
				frame_hits[t].append(snappedf(last_hp - hp, 0.1))
				last_hp = hp
		var bullets := 0
		for n in get_tree().get_nodes_in_group("entities"):
			if n is Bullet:
				bullets += 1
		print("L f=", t, " bullets=", bullets)
	elif t == 460:
		print("L hit_frames=", frame_hits.keys())
		for k in frame_hits.keys():
			print("L frame ", k, " deltas=", frame_hits[k])
		get_tree().quit()
