extends Node
var t := 0
var bm: BattleManager = null
func _ready() -> void:
	var scn: PackedScene = load("res://scenes/battle.tscn")
	if scn == null:
		print("S no scene"); return
	add_child(scn.instantiate())
func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		print("S bm=", bm != null)
		if bm != null: bm._start_game("亚瑟")
	elif t == 300:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm == null or bm.hero == null:
			print("S no hero"); get_tree().quit(); return
		var hero = bm.hero
		hero.gold = 30000
		print("S hero gold=", hero.gold)
		UiManager._open_shop()
		print("S open visible=", UiManager.shop_ui.visible)
		var cats: Array = ["推荐"]
		for k in UiManager._shop_categories().keys():
			cats.append(str(k))
		for c in cats:
			UiManager._on_category_selected(str(c))
			print("S cat=", c, " grid=", UiManager.shop_grid_ids.size())
		UiManager._on_category_selected("物理")
	elif t == 340:
		var img: Image = get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("res://devshop/shot.png")
			print("S shot saved ", img.get_width(), "x", img.get_height())
	elif t == 360:
		var hero = bm.hero
		var ids: Array = UiManager.shop_grid_ids
		if ids.size() > 0:
			var first: String = str(ids[0])
			var g0: int = hero.gold
			UiManager._on_shop_item_selected(first)
			UiManager._shop_quick_buy(first)
			print("S buy gold ", g0, "->", hero.gold, " slots=", hero.equipment_slots.size())
			UiManager._on_shop_buy_sell()
			print("S buy_sell gold=", hero.gold, " slots=", hero.equipment_slots.size())
			UiManager._shop_move_sel(1)
			var ev := InputEventKey.new()
			ev.keycode = KEY_ENTER
			print("S enter=", UiManager._shop_handle_key(ev), " sel=", UiManager.shop_selected_item)
			UiManager._on_shop_sell()
			print("S sell gold=", hero.gold, " slots=", hero.equipment_slots.size())
			UiManager._shop_buy_missing(first)
			print("S buy_missing gold=", hero.gold)
		UiManager._on_shop_item_selected("")
		UiManager._update_shop_detail()
		print("S empty detail ok")
		UiManager._close_shop()
		UiManager.toggle_shop()
		print("S toggle1 visible=", UiManager.shop_ui.visible)
		UiManager.toggle_shop()
		print("S toggle2 visible=", UiManager.shop_ui.visible)
		get_tree().quit()
