extends Node
var t := 0
var bm: BattleManager = null
func _ready() -> void:
	var scn: PackedScene = load("res://scenes/battle.tscn")
	if scn != null:
		add_child(scn.instantiate())
func _card_price(idx: int) -> String:
	if UiManager.shop_item_grid == null: return ""
	var cards: Array = []
	for ch in UiManager.shop_item_grid.get_children():
		if ch is Button: cards.append(ch)
	if idx >= cards.size(): return ""
	for c in cards[idx].get_children():
		if c is Label:
			var s: String = str(c.text)
			if s.contains("金"): return s
	return ""
func _process(_d: float) -> void:
	t += 1
	if t == 20:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm != null: bm._start_game("亚瑟")
	elif t == 300:
		bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm == null or bm.hero == null:
			print("Q no hero"); get_tree().quit(); return
		bm.hero.gold = 30000
		UiManager._open_shop()
		UiManager._on_category_selected("物理")
		print("Q open grid=", UiManager.shop_grid_ids.size())
	elif t == 320:
		var hero = bm.hero
		var ids: Array = UiManager.shop_grid_ids
		var t0: String = UiManager.shop_title_label.text
		var c0: String = _card_price(0)
		UiManager._on_shop_item_selected(str(ids[0]))
		var t0b: String = UiManager.shop_title_label.text
		UiManager._on_shop_buy_sell()
		print("Q detailbuy title[", t0, "] -> [", t0b, "] -> [", UiManager.shop_title_label.text, "]")
		print("Q detailbuy card0 [", c0, "] -> [", _card_price(0), "] gold=", hero.gold, " slots=", hero.equipment_slots.size())
		# 选中高亮跟随（选择 ids[3] 后 selected 应变）
		var ids2: Array = UiManager.shop_grid_ids
		if ids2.size() > 3:
			UiManager._on_shop_item_selected(str(ids2[3]))
			print("Q select3 = ", UiManager.shop_selected_item, " expect=", str(ids2[3]))
		# 卖未拥有：不应加金币
		var g0: int = hero.gold
		UiManager._on_shop_item_selected("purify")
		if not hero.equipment_slots.has("purify"):
			UiManager._on_shop_sell()
			print("Q sell_nonowned ", g0, "->", hero.gold)
		# 卖已拥有：金币增、栏位减、标题刷新
		if hero.equipment_slots.size() > 0:
			var own: String = str(hero.equipment_slots[0])
			var g1: int = hero.gold
			var s1: int = hero.equipment_slots.size()
			UiManager._on_shop_item_selected(own)
			UiManager._on_shop_sell()
			print("Q sell_owned gold ", g1, "->", hero.gold, " slots ", s1, "->", hero.equipment_slots.size(), " title=[", UiManager.shop_title_label.text, "]")
		# 键盘选择后无异常
		UiManager._shop_move_sel(1)
		print("Q move_sel sel=", UiManager.shop_selected_item)
		get_tree().quit()
