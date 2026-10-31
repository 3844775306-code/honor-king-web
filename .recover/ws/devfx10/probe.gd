extends Node

var t := 0
var bm: BattleManager = null
var mm: JungleMonster = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 320:
		mm = JungleMonster.new()
		mm.setup({"name": "wolf", "team": 2, "max_health": 1000, "attack": 5})
		mm.position = Vector3(-30.0, 0.0, 30.0)
		add_child(mm)
	elif t == 340:
		print("D anim_player=", mm.get("anim_player"), " hp=", mm.health, " dead=", mm.is_dead, " state=", mm.get("_anim_state"))
		mm._play_anim("walk")
		print("D after_walk state=", mm.get("_anim_state"))
	elif t >= 341 and t <= 350:
		var ar = mm.get("_anim_root")
		print("D f", t, " state=", mm.get("_anim_state"), " atk_t=", "%.2f" % float(mm.get("_attack_anim_t")), " bob=", "%.3f" % (ar as Node3D).position.y, " hp=", mm.health, " dead=", mm.is_dead, " vis=", mm.visible)
	elif t == 360:
		mm._play_anim("attack-melee-left")
		print("D after_attack state=", mm.get("_anim_state"), " atk_t=", "%.2f" % float(mm.get("_attack_anim_t")))
	elif t >= 361 and t <= 370:
		var ar2 = mm.get("_anim_root")
		print("D f", t, " state=", mm.get("_anim_state"), " atk_t=", "%.2f" % float(mm.get("_attack_anim_t")), " lunge=", "%.2f" % (ar2 as Node3D).position.z)
	elif t == 380:
		get_tree().quit()
