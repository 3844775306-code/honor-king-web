extends Node

var t := 0
var bm: BattleManager = null

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 400:
		print("M done frames=400 hero=", bm.hero != null, " hero_name=", bm.hero.display_name if bm.hero != null else "?")
		get_tree().quit()
