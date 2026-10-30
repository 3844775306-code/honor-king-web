extends Node

const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
var t := 0
var bm = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load("res://scenes/battle.tscn") as PackedScene).instantiate())

func _process(_d: float) -> void:
	t += 1
	if t == 15:
		bm = get_tree().get_first_node_in_group("battle_manager")
		if bm == null:
			print("L no bm"); get_tree().quit(); return
		var su = bm.select_ui
		if su == null:
			print("L no select_ui"); get_tree().quit(); return
		var root = su.get_node_or_null("SelectRoot")
		var sscroll = root.find_child("SelectSummScroll", true, false)
		var sgrid = root.find_child("SelectSummScroll", true, false).get_child(0)
		print("L summ_scroll=", sscroll.size, " grid=", sgrid.size, " cards=", sgrid.get_child_count(), " need_scroll=", sgrid.size.y > sscroll.size.y)
		var card = sgrid.get_child(0)
		print("L summ_card=", card.size, " cols=", sgrid.columns)
		bm._on_right_tab_pressed("出装")
	elif t == 120:
		var root = bm.select_ui.get_node_or_null("SelectRoot")
		var rows = root.find_child("SelectBuildRows", true, false)
		var panel = root.find_child("SelectBuildPanel", true, false)
		print("L build_rows_type=", rows.get_class(), " count=", rows.get_child_count(), " rows_size=", rows.size, " panel=", panel.size)
		var rb = root.find_child("SelectRightBody", true, false)
		var rt = root.find_child("SelectRoot", false, false)
		var sums = root.find_child("SelectSummPanel", true, false)
		print("L right_body=", rb.size, " summ_panel=", sums.size, " build_panel=", panel.size, " root=", root.size)
		if rows.get_child_count() > 0:
			print("L first_card=", rows.get_child(0).size, " last_card=", rows.get_child(rows.get_child_count()-1).size)
		var schemes = root.find_child("SelectBuildSchemeRow", true, false)
		print("L schemes=", schemes.get_child_count(), " size=", schemes.size, " cols=", schemes.columns)
		var ids_before = bm.sel_build_ids.duplicate()
		bm._on_build_move(1, -1)
		print("L reorder=", ids_before[0] == bm.sel_build_ids[1], " count=", bm.sel_build_ids.size())
		get_tree().quit()
