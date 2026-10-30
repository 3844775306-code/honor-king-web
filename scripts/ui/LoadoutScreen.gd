class_name LoadoutScreen
extends Control
## 备战界面：为任意英雄设计 6 件自定义出装方案，命名保存/载入/删除。
## 数据：HeroBuildStore（user://hero_builds.json，不可写时回退 res://saves/）。
## 版式：2400×1400 全屏，深色底 + UiKit 程序化背景 + 三栏玻璃卡片。

const SLOT_COUNT := 6
const ROLE_ALL := "全部"
const TIP_W := 460.0
const TIP_DELAY := 0.15

# 悬停浮层属性行：[字段, 中文, 单位后缀]
const ATTR_ORDER := [
	["attack", "攻击", ""],
	["ability_power", "法强", ""],
	["health", "生命", ""],
	["mana", "法力", ""],
	["armor", "护甲", ""],
	["magic_resist", "魔抗", ""],
	["attack_speed", "攻速", "%"],
	["crit_chance", "暴击", "%"],
	["crit_damage", "暴击伤害", "%"],
	["lifesteal", "吸血", "%"],
	["spell_vamp", "法术吸血", "%"],
	["cooldown", "冷却缩减", "%"],
	["speed", "移速", ""],
	["per_speed", "移速", "%"],
	["magic_pen", "法穿", ""],
	["magic_pen_percent", "法穿", "%"],
	["armor_pen_percent", "穿透", "%"],
	["per_ability_power", "法强", "%"],
	["toughness", "韧性", ""],
	["hp_regen", "生命回复", ""],
	["mana_regen", "法力回复", ""],
]
const TIER_CN := {1: "小件", 2: "中件", 3: "大件", 4: "终极"}
const CLASS_CN := {
	"attack": "物理", "attack_speed": "物理", "magic": "法术", "defense": "防御",
	"boots": "靴子", "jungle": "打野", "support": "游走", "survival": "保命",
}

# 装备库分类：class -> tab（attack/attack_speed 合并为「物理」）
const CATEGORIES := [
	{"label": "物理", "classes": ["attack", "attack_speed"]},
	{"label": "法术", "classes": ["magic"]},
	{"label": "防御", "classes": ["defense"]},
	{"label": "靴子", "classes": ["boots"]},
	{"label": "打野", "classes": ["jungle"]},
	{"label": "游走", "classes": ["support"]},
	{"label": "保命", "classes": ["survival"]},
]

var _heroes: Array = []
var _item_ids_by_cat: Dictionary = {}
var _hero_name := ""
var _role_filter := ROLE_ALL
var _cat_label := "物理"
var _slot_ids: Array = ["", "", "", "", "", ""]
var _selected_slot := -1

var _role_btns: Dictionary = {}
var _cat_btns: Dictionary = {}
var _hero_btns: Dictionary = {}
var _item_btns: Dictionary = {}
var _hero_grid: GridContainer
var _item_grid: GridContainer
var _slot_row: HBoxContainer
var _slot_btns: Array = []
var _sel_hero_lab: Label
var _name_edit: LineEdit
var _save_btn: Button
var _return_btn: Button
var _build_count_lab: Label
var _build_list: VBoxContainer
var _build_actions: Array = []
var _toast: PanelContainer
var _toast_lab: Label
var _toast_tw: Tween
var _tip: PanelContainer
var _tip_id := ""
var _tip_mode := "simple"
var _tip_btns: Dictionary = {}
var _hover_id := ""
var _hover_t := 0.0


## 装备槽按钮：负责拖拽取数/放置，实际交换交给 _swap_slots。
class SlotButton extends Button:
	var screen: LoadoutScreen
	var slot_index := 0
	var item_id := ""

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if item_id == "" or screen == null:
			return null
		screen._hide_tip()
		var preview := PanelContainer.new()
		preview.add_theme_stylebox_override("panel",
			UiKit.flat(0.95, 10, 1, UiKit.C_GOLD, UiKit.C_PANEL_BG, 10.0, 6.0))
		var lab := Label.new()
		lab.text = str(ItemDatabase.get_item(item_id).get("name", item_id))
		lab.add_theme_font_size_override("font_size", int(round(UiKit.FS_SM * UiKit.scale())))
		lab.add_theme_color_override("font_color", UiKit.C_TEXT)
		preview.add_child(lab)
		set_drag_preview(preview)
		return {"from_slot": slot_index}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("from_slot")

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if screen == null or not (data is Dictionary) or not data.has("from_slot"):
			return
		screen._swap_slots(int(data.get("from_slot", -1)), slot_index)


func _ready() -> void:
	_build_data()
	_build_ui()
	_refresh_role_tabs()
	_refresh_cat_tabs()
	_refresh_tip_mode_tabs()
	_refresh_hero_grid()
	_refresh_item_grid()
	if not _heroes.is_empty():
		_select_hero(str(_heroes[0]))
	SfxManager.start_menu_music()


# ==================== 数据 ====================

func _build_data() -> void:
	_heroes = HeroPickData.HERO_ROLE.keys()
	_heroes.sort_custom(func(a, b):
		var ia: int = HeroPickData.ROLES_ORDER.find(str(HeroPickData.HERO_ROLE.get(a, "")))
		var ib: int = HeroPickData.ROLES_ORDER.find(str(HeroPickData.HERO_ROLE.get(b, "")))
		if ia == ib:
			return str(a) < str(b)
		return ia < ib)
	for cat in CATEGORIES:
		var classes: Array = cat["classes"]
		var ids: Array = []
		for id in ItemDatabase.items.keys():
			var info: Dictionary = ItemDatabase.items[id]
			if classes.has(str(info.get("class", ""))):
				ids.append(str(id))
		ids.sort_custom(func(a, b):
			var ia: Dictionary = ItemDatabase.get_item(a)
			var ib: Dictionary = ItemDatabase.get_item(b)
			var ta := int(ia.get("tier", 1))
			var tb := int(ib.get("tier", 1))
			if ta != tb:
				return ta < tb
			var ca := int(ia.get("cost", 0))
			var cb := int(ib.get("cost", 0))
			if ca != cb:
				return ca < cb
			return str(ia.get("name", a)) < str(ib.get("name", b)))
		_item_ids_by_cat[str(cat["label"])] = ids


func _fs(tier: int) -> int:
	return int(round(tier * UiKit.scale()))


# ==================== 通用控件 ====================

func _mk_label(txt: String, tier: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", _fs(tier))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("outline_size", 1)
	return l


func _no_style() -> StyleBoxFlat:
	return UiKit.flat(0.0, 0, 0, Color.TRANSPARENT, Color(0, 0, 0, 0), 0.0)


func _style_btn(b: Button, accent: Color, filled: bool, text_color: Color) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))
	b.add_theme_stylebox_override("focus", _no_style())
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color if filled else text_color.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", UiKit.C_TEXT_DISABLED)


func _mk_button(txt: String, accent: Color, filled: bool, min_size: Vector2,
		tier := UiKit.FS_SM, text_color := UiKit.C_TEXT) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", _fs(tier))
	_style_btn(b, accent, filled, text_color)
	return b


func _style_tab(b: Button, selected: bool, accent: Color) -> void:
	_style_btn(b, accent, selected, Color(0.12, 0.07, 0.02) if selected else UiKit.C_TEXT)


func _mk_panel(alpha := 0.62, pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",
		UiKit.flat(alpha, 14, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0), float(pad)))
	return p


func _clear_children(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()


# ==================== 界面搭建 ====================

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.026, 0.045, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	UiKit.make_backdrop(self, UiKit.C_TEAM0, 1.0)
	move_child(bg, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root_v := VBoxContainer.new()
	root_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_theme_constant_override("separation", 12)
	margin.add_child(root_v)

	root_v.add_child(_build_top_bar())

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(_build_left())
	main.add_child(_build_middle())
	main.add_child(_build_right())
	root_v.add_child(main)

	_build_toast()
	_build_tip()


func _build_top_bar() -> Control:
	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 84)
	top.add_theme_constant_override("separation", 16)

	var titles := VBoxContainer.new()
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override("separation", 2)
	titles.add_child(_mk_label("备战", UiKit.FS_HUGE, UiKit.C_GOLD))
	titles.add_child(_mk_label("为英雄自定义出装方案 · 选人页可设为本局推荐", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	top.add_child(titles)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	top.add_child(_build_tip_mode_segment())

	_return_btn = _mk_button("返回大厅", UiKit.C_DANGER, false, Vector2(200, 64), UiKit.FS_LG)
	_return_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_return_btn.pressed.connect(_on_back)
	top.add_child(_return_btn)
	return top


func _build_left() -> Control:
	var panel := _mk_panel(0.62, 10)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	var roles: Array = [ROLE_ALL]
	roles.append_array(HeroPickData.ROLES_ORDER)
	for role in roles:
		var b := _mk_button(str(role), UiKit.C_GOLD, str(role) == _role_filter, Vector2(96, 48), UiKit.FS_SM)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_role_filter.bind(str(role)))
		tab_row.add_child(b)
		_role_btns[str(role)] = b
	v.add_child(tab_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_hero_grid = GridContainer.new()
	_hero_grid.columns = 2
	_hero_grid.add_theme_constant_override("h_separation", 8)
	_hero_grid.add_theme_constant_override("v_separation", 8)
	_hero_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_hero_grid)
	return panel


func _build_middle() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)

	# —— 当前方案（6 槽）——
	var build_panel := _mk_panel(0.62, 12)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	build_panel.add_child(bv)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_mk_label("当前方案", UiKit.FS_MD, UiKit.C_TEXT))
	_sel_hero_lab = _mk_label("未选择英雄", UiKit.FS_SM, UiKit.C_GOLD)
	_sel_hero_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_sel_hero_lab)
	var hsp := Control.new()
	hsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hsp)
	var clear_btn := _mk_button("清空槽位", UiKit.C_DANGER, false, Vector2(140, 48), UiKit.FS_SM)
	clear_btn.pressed.connect(_on_clear_slots)
	head.add_child(clear_btn)
	bv.add_child(head)

	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 8)
	bv.add_child(_slot_row)
	v.add_child(build_panel)

	# —— 装备库 ——
	var lib_panel := _mk_panel(0.62, 12)
	lib_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	lib_panel.add_child(lv)

	var lhead := HBoxContainer.new()
	lhead.add_theme_constant_override("separation", 12)
	lhead.add_child(_mk_label("装备库", UiKit.FS_MD, UiKit.C_TEXT))
	var lhint := _mk_label("点击装备加入当前方案（先点槽位可指定替换）", UiKit.FS_XS, UiKit.C_TEXT_DIM)
	lhint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lhead.add_child(lhint)
	lv.add_child(lhead)

	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 6)
	for cat in CATEGORIES:
		var label := str(cat["label"])
		var cb := _mk_button(label, UiKit.C_GOLD, label == _cat_label, Vector2(96, 46), UiKit.FS_SM)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.pressed.connect(_on_cat.bind(label))
		cat_row.add_child(cb)
		_cat_btns[label] = cb
	lv.add_child(cat_row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)

	_item_grid = GridContainer.new()
	_item_grid.columns = 3
	_item_grid.add_theme_constant_override("h_separation", 8)
	_item_grid.add_theme_constant_override("v_separation", 8)
	_item_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_grid)
	v.add_child(lib_panel)
	return v


func _build_right() -> Control:
	var panel := _mk_panel(0.62, 10)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(_mk_label("方案名", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(400, 48)
	_name_edit.placeholder_text = "给这套出装起个名字"
	_name_edit.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
	_name_edit.add_theme_color_override("font_color", UiKit.C_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", UiKit.C_TEXT_DISABLED)
	_name_edit.add_theme_stylebox_override("normal",
		UiKit.flat(0.9, 10, 1, UiKit.C_PANEL_EDGE, UiKit.C_GLASS, 12.0))
	_name_edit.add_theme_stylebox_override("focus",
		UiKit.flat(0.95, 10, 2, UiKit.C_GOLD, UiKit.C_GLASS, 12.0))
	v.add_child(_name_edit)

	_save_btn = _mk_button("保存方案", UiKit.C_GOLD, true, Vector2(360, 64),
		UiKit.FS_LG, Color(0.12, 0.07, 0.02))
	_save_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_save_btn.pressed.connect(_on_save)
	v.add_child(_save_btn)

	_build_count_lab = _mk_label("方案列表（0）", UiKit.FS_MD, UiKit.C_TEXT)
	v.add_child(_build_count_lab)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	_build_list = VBoxContainer.new()
	_build_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_build_list)

	var hint := _mk_label("保存到 user://hero_builds.json · 选人页『出装』标签可选用",
		UiKit.FS_XS, UiKit.C_TEXT_DISABLED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	return panel


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -240
	_toast.offset_right = 240
	_toast.offset_top = 100
	_toast.offset_bottom = 160
	_toast.visible = false
	add_child(_toast)
	_toast_lab = _mk_label("", UiKit.FS_MD, UiKit.C_TEXT)
	_toast_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_lab)


# ==================== 刷新 ====================

func _refresh_role_tabs() -> void:
	for role in _role_btns:
		_style_tab(_role_btns[role], str(role) == _role_filter, UiKit.C_GOLD)


func _refresh_cat_tabs() -> void:
	for label in _cat_btns:
		_style_tab(_cat_btns[label], str(label) == _cat_label, UiKit.C_GOLD)


func _refresh_hero_grid() -> void:
	_clear_children(_hero_grid)
	_hero_btns.clear()
	for hero in _heroes:
		var name := str(hero)
		var role := str(HeroPickData.HERO_ROLE.get(name, ""))
		if _role_filter != ROLE_ALL and role != _role_filter:
			continue
		var b := _mk_hero_btn(name, role)
		_hero_grid.add_child(b)
		_hero_btns[name] = b


func _mk_hero_btn(hero: String, role: String) -> Button:
	var col: Color = HeroPickData.ROLE_COLORS.get(role, UiKit.C_TEAM0)
	var b := Button.new()
	b.text = hero
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(190, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	_style_hero_btn(b, hero, role)
	b.pressed.connect(_select_hero.bind(hero))

	var role_lab := _mk_label(role, UiKit.FS_XS, col.lightened(0.3))
	role_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_lab.anchor_left = 1.0
	role_lab.anchor_right = 1.0
	role_lab.anchor_top = 0.5
	role_lab.anchor_bottom = 0.5
	role_lab.offset_left = -86
	role_lab.offset_right = -12
	role_lab.offset_top = -12
	role_lab.offset_bottom = 12
	b.add_child(role_lab)
	return b


func _style_hero_btn(b: Button, hero: String, role: String) -> void:
	var col: Color = HeroPickData.ROLE_COLORS.get(role, UiKit.C_TEAM0)
	var selected := hero == _hero_name
	b.add_theme_stylebox_override("normal", UiKit.skin_card(col, selected, 0.66))
	b.add_theme_stylebox_override("hover", UiKit.skin_card(col, true, 0.80))
	b.add_theme_stylebox_override("pressed", UiKit.skin_card(col, true, 0.92))
	b.add_theme_stylebox_override("focus", _no_style())
	b.add_theme_color_override("font_color", UiKit.C_TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


func _refresh_slots() -> void:
	_hide_tip()
	_clear_children(_slot_row)
	_slot_btns.clear()
	for i in range(SLOT_COUNT):
		var b := _mk_slot_btn(i)
		_slot_row.add_child(b)
		_slot_btns.append(b)
	var shown := 0
	for i in range(SLOT_COUNT):
		if str(_slot_ids[i]) != "":
			shown += 1
	if _hero_name != "":
		var role := str(HeroPickData.HERO_ROLE.get(_hero_name, ""))
		_sel_hero_lab.text = "当前：%s（%s） · 已装备 %d/%d" % [_hero_name, role, shown, SLOT_COUNT]


func _mk_slot_btn(i: int) -> SlotButton:
	var id := str(_slot_ids[i])
	var selected := i == _selected_slot
	var b := SlotButton.new()
	b.screen = self
	b.slot_index = i
	b.item_id = id
	b.custom_minimum_size = Vector2(156, 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_slot_clicked.bind(i))
	_style_slot(b, selected)

	if id == "":
		var empty_v := VBoxContainer.new()
		empty_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		empty_v.offset_left = 8
		empty_v.offset_right = -8
		empty_v.offset_top = 8
		empty_v.offset_bottom = -8
		empty_v.alignment = BoxContainer.ALIGNMENT_CENTER
		empty_v.add_theme_constant_override("separation", 2)
		empty_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var idx_lab := _mk_label("槽 %d" % (i + 1), UiKit.FS_XS, UiKit.C_TEXT_DISABLED)
		idx_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idx_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_v.add_child(idx_lab)
		var empty_lab := _mk_label("空", UiKit.FS_SM, UiKit.C_TEXT_DIM)
		empty_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty_v.add_child(empty_lab)
		b.add_child(empty_v)
		return b

	var info: Dictionary = ItemDatabase.get_item(id)
	var item_name := str(info.get("name", id))
	var tier := int(info.get("tier", 1))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 16
	v.offset_bottom = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lab := _mk_label(item_name, UiKit.FS_SM, UiKit.C_TEXT)
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_lab)
	var price_lab := _mk_label("%d 金" % int(info.get("cost", 0)), UiKit.FS_XS, UiKit.C_GOLD)
	price_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(price_lab)
	var tier_lab := _mk_label("T%d" % tier, UiKit.FS_XS, UiKit.C_TEXT_DISABLED)
	tier_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tier_lab)
	b.add_child(v)

	var del := _mk_button("×", UiKit.C_DANGER, false, Vector2(30, 30), UiKit.FS_XS)
	del.anchor_left = 1.0
	del.anchor_right = 1.0
	del.offset_left = -36
	del.offset_right = -6
	del.offset_top = 6
	del.offset_bottom = 36
	del.pressed.connect(_on_slot_clear.bind(i))
	b.add_child(del)
	b.mouse_entered.connect(_on_hover_item.bind(id))
	b.mouse_exited.connect(_on_hover_out)
	return b


func _style_slot(b: Button, selected: bool) -> void:
	if selected:
		var s := UiKit.flat(0.96, 12, 2, UiKit.C_GOLD, UiKit.C_PANEL_BG, 10.0, 8.0)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
	else:
		b.add_theme_stylebox_override("normal", UiKit.skin_chip(UiKit.C_PANEL_EDGE, 0.90, 12))
		b.add_theme_stylebox_override("hover", UiKit.skin_chip(UiKit.C_GOLD, 0.95, 12))
		b.add_theme_stylebox_override("pressed", UiKit.skin_chip(UiKit.C_GOLD, 0.95, 12))
	b.add_theme_stylebox_override("focus", _no_style())


func _refresh_item_grid() -> void:
	_hide_tip()
	_clear_children(_item_grid)
	_item_btns.clear()
	var ids: Array = _item_ids_by_cat.get(_cat_label, [])
	for id in ids:
		var b := _mk_item_btn(str(id))
		_item_grid.add_child(b)
		_item_btns[str(id)] = b


func _mk_item_btn(id: String) -> Button:
	var info: Dictionary = ItemDatabase.get_item(id)
	var tier := int(info.get("tier", 1))
	var qc: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)]
	var b := Button.new()
	b.text = ""
	b.custom_minimum_size = Vector2(220, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_item_clicked.bind(id))
	_style_item_btn(b, info)
	b.set_meta("item_tier", tier)
	b.set_meta("item_id", id)
	b.mouse_entered.connect(_on_hover_item.bind(id))
	b.mouse_exited.connect(_on_hover_out)
	# 左侧品质色条
	var stripe := ColorRect.new()
	stripe.color = qc
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.anchor_left = 0.0
	stripe.anchor_right = 0.0
	stripe.anchor_top = 0.0
	stripe.anchor_bottom = 1.0
	stripe.offset_left = 4
	stripe.offset_right = 8
	stripe.offset_top = 10
	stripe.offset_bottom = -10
	b.add_child(stripe)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -10
	row.offset_top = 4
	row.offset_bottom = -4
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	var name_lab := _mk_label(str(info.get("name", id)), UiKit.FS_SM, UiKit.C_TEXT)
	name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lab)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 0)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var price_lab := _mk_label("%d" % int(info.get("cost", 0)), UiKit.FS_XS, UiKit.C_GOLD)
	price_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(price_lab)
	var tier_lab := _mk_label("T%d" % tier, UiKit.FS_XS, qc)
	tier_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tier_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(tier_lab)
	row.add_child(right)
	b.add_child(row)
	return b


func _style_item_btn(b: Button, info: Dictionary) -> void:
	var tier := int(info.get("tier", 1))
	var qc: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)]
	var normal := UiKit.flat(0.86, 10, 1, Color(qc.r, qc.g, qc.b, 0.35), Color(0, 0, 0, 0), 0.0)
	var hover := UiKit.flat(0.96, 10, 2, qc, Color(0, 0, 0, 0), 0.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", _no_style())


func _refresh_build_list() -> void:
	_clear_children(_build_list)
	_build_actions.clear()
	var builds := HeroBuildStore.get_builds(_hero_name)
	_build_count_lab.text = "方案列表（%d）" % builds.size()
	if builds.is_empty():
		var empty := _mk_label("该英雄还没有方案，配好装备后点「保存方案」", UiKit.FS_XS, UiKit.C_TEXT_DISABLED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_build_list.add_child(empty)
		return
	for b in builds:
		var build_name := str(b.get("name", ""))
		var items: Array = b.get("items", [])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lab := _mk_label(build_name, UiKit.FS_SM, UiKit.C_TEXT)
		name_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lab.tooltip_text = "%s（%d 件）" % [build_name, items.size()]
		row.add_child(name_lab)
		var load_btn := _mk_button("载入", UiKit.C_TEAM0, false, Vector2(96, 44), UiKit.FS_SM)
		load_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		load_btn.pressed.connect(_on_load_build.bind(build_name))
		row.add_child(load_btn)
		var del_btn := _mk_button("删除", UiKit.C_DANGER, false, Vector2(96, 44), UiKit.FS_SM)
		del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		del_btn.pressed.connect(_on_delete_build.bind(build_name))
		row.add_child(del_btn)
		_build_list.add_child(row)
		_build_actions.append({"name": build_name, "load": load_btn, "del": del_btn})


# ==================== 交互 ====================

func _select_hero(hero: String) -> void:
	if hero == "" or not HeroPickData.HERO_ROLE.has(hero):
		return
	_hero_name = hero
	for name in _hero_btns:
		var b: Button = _hero_btns[name]
		_style_hero_btn(b, str(name), str(HeroPickData.HERO_ROLE.get(name, "")))

	_selected_slot = -1
	for i in range(SLOT_COUNT):
		_slot_ids[i] = ""
	var builds := HeroBuildStore.get_builds(hero)
	if builds.is_empty():
		_name_edit.text = ""
	else:
		var first: Dictionary = builds[0]
		_apply_build_items(first.get("items", []))
		_name_edit.text = str(first.get("name", ""))
	_refresh_slots()
	_refresh_build_list()


func _apply_build_items(items: Array) -> void:
	for i in range(SLOT_COUNT):
		_slot_ids[i] = str(items[i]) if i < items.size() else ""


func _on_role_filter(role: String) -> void:
	_role_filter = role
	_refresh_role_tabs()
	_refresh_hero_grid()


func _on_cat(label: String) -> void:
	_cat_label = label
	_refresh_cat_tabs()
	_refresh_item_grid()


func _on_slot_clicked(i: int) -> void:
	_selected_slot = -1 if _selected_slot == i else i
	_refresh_slots()


func _on_slot_clear(i: int) -> void:
	_slot_ids[i] = ""
	if _selected_slot == i:
		_selected_slot = -1
	_refresh_slots()


func _on_clear_slots() -> void:
	for i in range(SLOT_COUNT):
		_slot_ids[i] = ""
	_selected_slot = -1
	_refresh_slots()
	_show_toast("已清空槽位", true)


func _on_item_clicked(id: String) -> void:
	if _selected_slot >= 0:
		_slot_ids[_selected_slot] = id
		_selected_slot = -1
		_refresh_slots()
		return
	if _slot_ids.has(id):
		_show_toast("该装备已在方案中", false)
		return
	for i in range(SLOT_COUNT):
		if str(_slot_ids[i]) == "":
			_slot_ids[i] = id
			_refresh_slots()
			return
	_show_toast("6 个槽已满，先替换或删除", false)


func _on_save() -> void:
	var build_name := _name_edit.text.strip_edges()
	var items: Array = []
	for i in range(SLOT_COUNT):
		var id := str(_slot_ids[i])
		if id != "":
			items.append(id)
	var err := HeroBuildStore.save_build(_hero_name, build_name, items)
	if err != "":
		_show_toast(err, false)
		return
	_name_edit.text = build_name
	_refresh_build_list()
	_show_toast("已保存「%s」" % build_name, true)


func _on_load_build(build_name: String) -> void:
	for b in HeroBuildStore.get_builds(_hero_name):
		if str(b.get("name", "")) == build_name:
			_apply_build_items(b.get("items", []))
			_selected_slot = -1
			_name_edit.text = build_name
			_refresh_slots()
			_show_toast("已载入「%s」" % build_name, true)
			return


func _on_delete_build(build_name: String) -> void:
	HeroBuildStore.delete_build(_hero_name, build_name)
	if _name_edit.text == build_name:
		_name_edit.text = ""
	_refresh_build_list()
	_show_toast("已删除「%s」" % build_name, true)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _show_toast(msg: String, ok: bool) -> void:
	if _toast == null:
		return
	var accent := UiKit.C_HEAL if ok else UiKit.C_DANGER
	_toast_lab.text = msg
	_toast_lab.add_theme_color_override("font_color", accent)
	_toast.add_theme_stylebox_override("panel", UiKit.skin_notice(accent))
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tw != null and _toast_tw.is_valid():
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.1)
	_toast_tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tw.tween_callback(func(): if is_instance_valid(_toast): _toast.visible = false)


# ==================== 装备悬停浮层 ====================

func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.custom_minimum_size = Vector2(TIP_W, 0)
	_tip.z_index = 200
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	add_child(_tip)


func _build_tip_mode_segment() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 0)
	for mode in ["simple", "detail"]:
		var label := "简略" if mode == "simple" else "详细"
		var b := _mk_button(label, UiKit.C_GOLD, mode == _tip_mode, Vector2(96, 48), UiKit.FS_SM)
		b.pressed.connect(_on_tip_mode.bind(str(mode)))
		row.add_child(b)
		_tip_btns[str(mode)] = b
	return row


func _on_tip_mode(mode: String) -> void:
	if mode == _tip_mode:
		return
	_tip_mode = mode
	_refresh_tip_mode_tabs()
	if _tip.visible and _tip_id != "":
		_show_item_tip(_tip_id, get_global_mouse_position())


func _refresh_tip_mode_tabs() -> void:
	for mode in _tip_btns:
		_style_tab(_tip_btns[mode], str(mode) == _tip_mode, UiKit.C_GOLD)


func _process(delta: float) -> void:
	if _hover_id == "":
		return
	if not _tip.visible:
		_hover_t += delta
		if _hover_t >= TIP_DELAY:
			_show_item_tip(_hover_id, get_global_mouse_position())
	else:
		_place_tip(get_global_mouse_position())


func _on_hover_item(id: String) -> void:
	if id == "":
		return
	_hover_id = id
	_hover_t = 0.0
	if _tip.visible:
		_show_item_tip(id, get_global_mouse_position())


func _on_hover_out() -> void:
	_hover_id = ""
	_hover_t = 0.0
	_hide_tip()


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false
	_tip_id = ""
	_hover_id = ""
	_hover_t = 0.0


func _show_item_tip(id: String, pos: Vector2) -> void:
	if id == "" or not ItemDatabase.items.has(id):
		return
	_tip_id = id
	_build_tip_content(id)
	_tip.visible = true
	_tip.reset_size()
	if _tip.size.x < TIP_W:
		_tip.size = Vector2(TIP_W, _tip.size.y)
	_place_tip(pos)


func _place_tip(pos: Vector2) -> void:
	if _tip == null or not _tip.visible:
		return
	var sz := _tip.size
	var p := pos + Vector2(18, 18)
	if p.x + sz.x > UiKit.DESIGN_W - 8.0:
		p.x = pos.x - sz.x - 18.0
	if p.y + sz.y > UiKit.DESIGN_H - 8.0:
		p.y = pos.y - sz.y - 18.0
	p.x = clampf(p.x, 8.0, UiKit.DESIGN_W - sz.x - 8.0)
	p.y = clampf(p.y, 8.0, UiKit.DESIGN_H - sz.y - 8.0)
	_tip.position = p


func _build_tip_content(id: String) -> void:
	_clear_children(_tip)
	var info: Dictionary = ItemDatabase.get_item(id)
	var tier := int(info.get("tier", 1))
	_tip.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_GOLD, false, 0.96))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	_tip.add_child(v)

	v.add_child(_tip_line(str(info.get("name", id)), UiKit.FS_MD, UiKit.C_GOLD))
	var sub := "%d 金 · %s · %s" % [int(info.get("cost", 0)), _tier_cn(tier),
		_class_cn(str(info.get("class", "")))]
	v.add_child(_tip_line(sub, UiKit.FS_XS, UiKit.C_TEXT_DIM))

	if _tip_mode == "simple":
		var lines := _attr_lines(info, 3)
		if lines.is_empty():
			lines.append("无属性加成")
		v.add_child(_tip_line("\n".join(PackedStringArray(lines)), UiKit.FS_SM, UiKit.C_TEXT))
		return

	for line in _attr_lines(info, -1):
		v.add_child(_tip_line(str(line), UiKit.FS_SM, UiKit.C_TEXT))
	if _attr_lines(info, -1).is_empty():
		v.add_child(_tip_line("无属性加成", UiKit.FS_SM, UiKit.C_TEXT_DIM))

	var passive := str(info.get("passive", ""))
	if passive != "":
		v.add_child(_tip_line("被动", UiKit.FS_XS, UiKit.C_TEAM0))
		v.add_child(_tip_line(_wrap_text(passive, _fs(UiKit.FS_XS), TIP_W - 30.0),
			UiKit.FS_XS, UiKit.C_TEXT_DIM))
	var active := str(info.get("active", ""))
	if active != "":
		v.add_child(_tip_line("主动", UiKit.FS_XS, UiKit.C_GOLD))
		v.add_child(_tip_line(_wrap_text(active, _fs(UiKit.FS_XS), TIP_W - 30.0),
			UiKit.FS_XS, UiKit.C_TEXT_DIM))

	var req: Array = info.get("requires", [])
	if req.is_empty():
		v.add_child(_tip_line("合成来源：基础装备", UiKit.FS_XS, UiKit.C_TEXT_DISABLED))
	else:
		var names: Array = []
		var total := 0
		for rid in req:
			var ri: Dictionary = ItemDatabase.get_item(str(rid))
			names.append(str(ri.get("name", rid)))
			total += int(ri.get("cost", 0))
		var txt := "合成来源：%s（合计 %d 金）" % [" + ".join(PackedStringArray(names)), total]
		v.add_child(_tip_line(_wrap_text(txt, _fs(UiKit.FS_XS), TIP_W - 30.0),
			UiKit.FS_XS, UiKit.C_TEXT_DISABLED))


func _tip_line(txt: String, tier: int, color: Color) -> Label:
	var l := _mk_label(txt, tier, color)
	l.custom_minimum_size = Vector2(TIP_W - 20.0, 0)
	return l


func _tier_cn(tier: int) -> String:
	return str(TIER_CN.get(tier, "小件"))


func _class_cn(cls: String) -> String:
	return str(CLASS_CN.get(cls, cls))


func _attr_lines(info: Dictionary, limit: int) -> Array:
	var out: Array = []
	for entry in ATTR_ORDER:
		var val = info.get(str(entry[0]), null)
		if val == null:
			continue
		var num := float(val)
		if is_zero_approx(num):
			continue
		out.append("%s +%s%s" % [str(entry[1]), _fmt_num(num), str(entry[2])])
		if limit > 0 and out.size() >= limit:
			break
	return out


func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(snappedf(v, 0.1))


func _wrap_text(txt: String, font_size: int, max_w: float) -> String:
	var f := UiKit.font()
	if f == null:
		return txt
	var out := ""
	var line := ""
	for ch in txt:
		if ch == "\n":
			out += line + "\n"
			line = ""
			continue
		var cand := line + ch
		if line != "" and f.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_w:
			out += line + "\n"
			line = ch
		else:
			line = cand
	return out + line


# ==================== 拖动调整槽位顺序 ====================

func _swap_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= SLOT_COUNT or b >= SLOT_COUNT or a == b:
		return
	var tmp := str(_slot_ids[a])
	_slot_ids[a] = str(_slot_ids[b])
	_slot_ids[b] = tmp
	_selected_slot = -1
	_refresh_slots()
	_show_toast("已调整出装顺序", true)
