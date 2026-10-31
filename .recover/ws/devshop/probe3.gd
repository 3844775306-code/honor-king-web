extends Node
var t := 0
var bm: BattleManager = null
func _ready() -> void:
	var scn: PackedScene = load("res://scenes/battle.tscn")
	if scn != null:
		add_child(scn.instantiate())
func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null: bm._start_game("亚瑟")
	elif t == 300:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm == null or bm.hero == null:
			print("P no hero"); get_tree().quit(); return
		bm.hero.gold = 30000
		print("P blocks_closed=", UiManager.blocks_gameplay_input())
		UiManager._open_shop()
		print("P blocks_open=", UiManager.blocks_gameplay_input())
		UiManager._on_category_selected("物理")
		var ids: Array = UiManager.shop_grid_ids
		UiManager._on_shop_item_selected(str(ids[0]))
		var g0: int = bm.hero.gold
		UiManager._on_shop_buy_sell()
		print("P buy ", g0, "->", bm.hero.gold, " slots=", bm.hero.equipment_slots.size())
		print("P sel_after_buy=", UiManager.shop_selected_item, " grid=", UiManager.shop_grid_ids.size())
		UiManager._close_shop()
		print("P blocks_closed2=", UiManager.blocks_gameplay_input())
		get_tree().quit()
