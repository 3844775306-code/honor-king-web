extends Node

var t := 0
var bm: BattleManager = null
var made: Array = []

func _ready() -> void:
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null:
			bm._start_game("亚瑟")
	elif t == 90:
		var types: Array = ["pig", "wolf", "lizard", "monkey", "bird", "worm", "red_buff", "blue_buff", "spatial_spirit", "river_spirit", "tyrant", "storm_dragon"]
		for i in range(types.size()):
			var m := JungleMonster.new()
			m.setup({"name": types[i], "team": 2, "max_health": 1000, "attack": 1})
			m.position = Vector3(-20.0 + float(i) * 3.5, 0.0, 25.0)
			add_child(m)
			made.append([types[i], m])
	elif t == 140:
		var ok := 0
		for e in made:
			var m: JungleMonster = e[1]
			var vis := m.get_node_or_null("MonsterVisual")
			var ttc: float = float(m.get("_visual_top_cache"))
			print("V ", e[0], " visual=", vis != null, " top_cache=", "%.2f" % ttc)
			if vis != null:
				ok += 1
		print("V ok=", ok, "/", made.size())
	elif t == 160:
		get_tree().quit()
