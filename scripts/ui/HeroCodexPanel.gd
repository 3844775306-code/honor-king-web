class_name HeroCodexPanel
extends Control
## 大厅「英雄」模块：左侧英雄列表 → 中央 3D 模型（可拖拽转视角）+ 右侧 属性 / 技能 / 玩法 / 出装 四页，
## 底部可一键跳到该英雄的备战界面配置出装（LoadoutScreen.open_hero）。

const SelectArt = preload("res://scripts/ui/SelectArt.gd")

const ATTR_ROWS: Array = [
	["max_health", "生命", ""],
	["max_mana", "法力", ""],
	["attack", "攻击", ""],
	["attack_range", "攻击距离", ""],
	["move_speed", "移速", ""],
	["hp_reg", "每秒回血", ""],
]

const ROLE_TIPS := {
	"战士": "前排开团位：先手顶到对方后排，用控制技能打断输出，血量过半就撤等队友跟进。别一个人越塔，兵线进塔再压。",
	"法师": "中路核心：站在队伍后方，先手控住关键目标再交出爆发连招；蓝量吃紧时先清线回城，别为了补刀被刺客抓。",
	"刺客": "打野节奏位：三级开始抓边，优先抓没有闪现的一路；团战时绕后切入对方输出，技能交完立刻撤出战场。",
	"射手": "发育路输出：前十分钟以补刀发育为主，团战躲在坦克身后，用位移技能保命而不是进场，血少时优先撤退。",
	"辅助": "游走保护位：控住对方突击手保护射手，视野放在河道与对方野区路口，团战先手控制再保护核心。",
}

var _s := 1.0
var _cfgs: Dictionary = {}
var _heroes: Array = []
var _hero := ""
var _role_filter := "全部"
var _tab := "属性"

var _grid: GridContainer
var _preview = null
var _name_row: HBoxContainer = null
var _name_avatar = null
var _title_hero: Label
var _sub_hero: Label
var _tabs: Dictionary = {}
var _content: VBoxContainer
var _content_scroll: ScrollContainer
var _item_tip: PanelContainer = null   # 出装图标悬浮详情卡


func _ready() -> void:
	_s = UiKit.scale()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_cfgs = _load_cfgs()
	_heroes = HeroPickData.HERO_ROLE.keys()
	_heroes.sort_custom(func(a, b):
		var ia: int = HeroPickData.ROLES_ORDER.find(str(HeroPickData.HERO_ROLE.get(a, "")))
		var ib: int = HeroPickData.ROLES_ORDER.find(str(HeroPickData.HERO_ROLE.get(b, "")))
		if ia == ib:
			return str(a) < str(b)
		return ia < ib)

	var bd: Control = UiKit.make_backdrop(self, UiKit.C_GOLD, 0.8)
	if bd != null:
		bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := ColorRect.new()
	scrim.color = Color(0.02, 0.025, 0.05, 0.74)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := _fs(24)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, pad)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _fs(12))
	margin.add_child(col)

	# ---- 顶部标题 ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _fs(12))
	col.add_child(head)
	head.add_child(_lab("英雄图鉴", UiKit.FS_HUGE, UiKit.C_GOLD))
	head.add_child(_lab("共 %d 名 · 拖拽中央模型可转视角" % _heroes.size(), UiKit.FS_SM, UiKit.C_TEXT_DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var close_btn := _btn("×  关闭", UiKit.C_DANGER)
	close_btn.pressed.connect(func(): queue_free())
	head.add_child(close_btn)

	# ---- 主体三栏 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", _fs(14))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	body.add_child(_build_left())
	body.add_child(_build_preview())
	body.add_child(_build_info())

	# ---- 底部：跳转备战 ----
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", _fs(12))
	col.add_child(foot)
	foot.add_child(_lab("想直接改出装？点右侧按钮进入该英雄的备战界面。", UiKit.FS_SM, UiKit.C_TEXT_DIM))
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fsp)
	var go := _btn("⚙  去备战配置出装", UiKit.C_GOLD, true)
	go.custom_minimum_size = Vector2(_fs(360), _fs(56))
	go.pressed.connect(_goto_loadout)
	foot.add_child(go)

	_select_hero(str(_heroes[0]) if not _heroes.is_empty() else "")


# ---------- 左：英雄列表 ----------
func _build_left() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_fs(330), 0)
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_TEAM0, false, 0.72))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _fs(8))
	panel.add_child(v)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", _fs(4))
	v.add_child(tabs)
	var roles: Array = ["全部"] + HeroPickData.ROLES_ORDER
	for r in roles:
		var b := _btn(str(r), HeroPickData.ROLE_COLORS.get(r, UiKit.C_GOLD), r == _role_filter)
		b.custom_minimum_size = Vector2(0, _fs(40))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", _fs(UiKit.FS_SM))
		b.pressed.connect(_on_role.bind(str(r)))
		tabs.add_child(b)
		b.set_meta("role", str(r))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", _fs(8))
	_grid.add_theme_constant_override("v_separation", _fs(8))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	_refresh_grid()
	return panel


func _refresh_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for h in _heroes:
		var role := str(HeroPickData.HERO_ROLE.get(h, ""))
		if _role_filter != "全部" and role != _role_filter:
			continue
		var col: Color = HeroPickData.ROLE_COLORS.get(role, UiKit.C_GOLD)
		var sel := str(h) == _hero
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.skin_card(col, sel, 0.9))
		card.custom_minimum_size = Vector2(0, _fs(56))
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", _fs(8))
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)
		hb.add_child(SelectArt.Avatar.new(str(h), col, _fs(40)))
		var nm := _lab(str(h), UiKit.FS_MD, Color.WHITE if sel else UiKit.C_TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(nm)
		hb.add_child(_lab(role, UiKit.FS_XS, col))
		var hover_style: StyleBoxFlat = UiKit.skin_card(col, true, 0.98)
		card.mouse_entered.connect(func() -> void:
			card.add_theme_stylebox_override("panel", hover_style)
		)
		card.mouse_exited.connect(func() -> void:
			card.add_theme_stylebox_override("panel", UiKit.skin_card(col, sel, 0.9))
		)
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_select_hero(str(h))
		)
		_grid.add_child(card)


func _on_role(role: String) -> void:
	_role_filter = role
	_refresh_grid()


# ---------- 中：3D 模型 ----------
func _build_preview() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_TEAM0, false, 0.55))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, _fs(760))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(holder)

	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	_preview = preload("res://scripts/ui/HeroPreview.gd").new()
	holder.add_child(_preview)
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.set_orbit_enabled(true)
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP   # 滑动旋转：由 HeroPreview 接管拖拽
	var orbit_hint := _lab("↔ 按住拖动可旋转查看模型", UiKit.FS_SM, Color(1, 1, 1, 0.55))
	orbit_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	orbit_hint.offset_top = _fs(14)
	orbit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	orbit_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(orbit_hint)

	# 底部姓名/定位条
	var info := VBoxContainer.new()
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_top = -_fs(120)
	info.offset_bottom = -_fs(16)
	info.offset_left = _fs(20)
	info.offset_right = -_fs(20)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.alignment = BoxContainer.ALIGNMENT_END
	holder.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", _fs(10))
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_row)
	_name_row = name_row
	_name_avatar = SelectArt.Avatar.new("", UiKit.C_GOLD, _fs(64))
	name_row.add_child(_name_avatar)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 0)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_col)
	_title_hero = _lab("", UiKit.FS_HUGE, UiKit.C_GOLD)
	_title_hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_col.add_child(_title_hero)
	_sub_hero = _lab("", UiKit.FS_SM, UiKit.C_TEXT_DIM)
	_sub_hero.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_col.add_child(_sub_hero)
	return panel


# ---------- 右：信息四页 ----------
func _build_info() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(_fs(760), 0)
	panel.add_theme_stylebox_override("panel", UiKit.skin_card(UiKit.C_TEAM0, false, 0.72))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _fs(8))
	panel.add_child(v)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", _fs(6))
	v.add_child(tab_row)
	for t in ["属性", "技能", "玩法", "出装"]:
		var b := _btn(str(t), UiKit.C_GOLD, t == _tab)
		b.custom_minimum_size = Vector2(0, _fs(46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
		b.pressed.connect(_on_tab.bind(str(t)))
		tab_row.add_child(b)
		_tabs[str(t)] = b

	_content_scroll = ScrollContainer.new()
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_content_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", _fs(8))
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.add_child(_content)
	return panel


func _on_tab(tab: String) -> void:
	_tab = tab
	_fill_content()


func _select_hero(hero: String) -> void:
	if hero == "":
		return
	_hero = hero
	_refresh_grid()
	if _preview != null:
		_preview.set_hero(hero)
	var role := str(HeroPickData.HERO_ROLE.get(hero, ""))
	var cfg: Dictionary = _cfgs.get(hero, {})
	if _name_row != null:
		if _name_avatar != null and is_instance_valid(_name_avatar):
			_name_row.remove_child(_name_avatar)
			_name_avatar.queue_free()
		var col2: Color = HeroPickData.ROLE_COLORS.get(role, UiKit.C_GOLD)
		_name_avatar = SelectArt.Avatar.new(hero, col2, _fs(64))
		_name_row.add_child(_name_avatar)
		_name_row.move_child(_name_avatar, 0)
	if _title_hero != null:
		_title_hero.text = hero
	if _sub_hero != null:
		var lane := HeroPickData.role_lane(role)
		_sub_hero.text = "%s · %s · 推荐召唤师 %s" % [role, lane, _summoner_name(HeroPickData.recommended_summoner(hero))]
	_fill_content()


func _fill_content() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	if _hero == "":
		return
	var role := str(HeroPickData.HERO_ROLE.get(_hero, ""))
	match _tab:
		"属性":
			_fill_attr(role)
		"技能":
			_fill_skills()
		"玩法":
			_fill_guide(role)
		"出装":
			_fill_build()


func _fill_attr(role: String) -> void:
	var cfg: Dictionary = _cfgs.get(_hero, {})
	var col: Color = HeroPickData.ROLE_COLORS.get(role, UiKit.C_GOLD)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", _fs(14))
	_content.add_child(head)
	head.add_child(SelectArt.Avatar.new(_hero, col, _fs(96)))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", _fs(2))
	head.add_child(hv)
	hv.add_child(_lab(_hero, UiKit.FS_HUGE, col.lightened(0.25)))
	hv.add_child(_lab("%s · 推荐分路 %s" % [role, HeroPickData.role_lane(role)], UiKit.FS_MD, UiKit.C_TEXT))
	hv.add_child(_lab("推荐召唤师：%s" % _summoner_name(HeroPickData.recommended_summoner(_hero)), UiKit.FS_SM, UiKit.C_GOLD))
	_content.add_child(_section("基础属性"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", _fs(18))
	grid.add_theme_constant_override("v_separation", _fs(4))
	_content.add_child(grid)
	for row in ATTR_ROWS:
		var val := int(cfg.get(str(row[0]), 0))
		grid.add_child(_lab(str(row[1]), UiKit.FS_SM, UiKit.C_TEXT_DIM))
		grid.add_child(_lab(_num(val), UiKit.FS_MD, UiKit.C_TEXT))
	# 英雄定位
	var lane := HeroPickData.role_lane(role)
	var extra := VBoxContainer.new()
	extra.add_theme_constant_override("separation", _fs(2))
	_content.add_child(extra)
	extra.add_child(_lab("定位：%s · 推荐分路：%s" % [role, lane], UiKit.FS_MD, HeroPickData.ROLE_COLORS.get(role, UiKit.C_GOLD)))
	extra.add_child(_lab("推荐召唤师技能：%s" % _summoner_name(HeroPickData.recommended_summoner(_hero)), UiKit.FS_SM, UiKit.C_GOLD))
	var skills: Array = cfg.get("skills", [])
	if not skills.is_empty():
		# 主加点建议：1 技能优先，其次 2，有大点大
		extra.add_child(_lab("加点建议：有大招点大招，常规主 1 副 2（%d 级前把 3 技能点满）。" % Hero.SKILL_MAX_LEVEL, UiKit.FS_SM, UiKit.C_TEXT_DIM))
	if _cfgs.has(_hero) == false:
		extra.add_child(_lab("（该英雄暂无基础数值配置）", UiKit.FS_SM, UiKit.C_TEXT_DIM))


func _fill_skills() -> void:
	var cfg: Dictionary = _cfgs.get(_hero, {})
	var skills: Array = cfg.get("skills", [])
	_content.add_child(_section("技能介绍"))
	if skills.is_empty():
		_content.add_child(_lab("暂无技能数据", UiKit.FS_MD, UiKit.C_TEXT_DIM))
		return
	for i in skills.size():
		var sid := str(skills[i])
		var sk: Skill = SkillDatabase.get_skill(sid)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_TEAM0, 0.5, _fs(10)))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", _fs(10))
		card.add_child(h)
		h.add_child(SelectArt.SkillGlyph.new(_hero, sk, i, _fs(52)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", _fs(2))
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(_lab("%d  %s" % [i + 1, str(sk.skill_name) if sk != null else sid], UiKit.FS_LG, UiKit.C_GOLD))
		if sk != null:
			var meta := "%s · 冷却 %.1fs" % [_skill_kind(int(sk.type)), float(sk.cooldown)]
			if sk.mana_cost > 0:
				meta += " · 法力 %d" % int(sk.mana_cost)
			if sk.cast_range > 0.0:
				meta += " · 距离 %.0fm" % float(sk.cast_range)
			v.add_child(_lab(meta, UiKit.FS_SM, UiKit.C_TEXT_DIM))
			var detail := _skill_detail(sk)
			if detail != "":
				var dl := _lab(detail, UiKit.FS_SM, UiKit.C_TEXT)
				dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				dl.custom_minimum_size = Vector2(_fs(640), 0)
				v.add_child(dl)
		_content.add_child(card)


func _fill_guide(role: String) -> void:
	_content.add_child(_section("玩法教程"))
	var tips := str(ROLE_TIPS.get(role, "先熟悉技能范围与冷却，再决定进攻或撤退。"))
	var t := _lab(tips, UiKit.FS_MD, UiKit.C_TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(_fs(700), 0)
	_content.add_child(t)

	var cfg: Dictionary = _cfgs.get(_hero, {})
	var skills: Array = cfg.get("skills", [])
	if not skills.is_empty():
		_content.add_child(_section("基础连招"))
		var names: Array = []
		for sid in skills:
			var sk: Skill = SkillDatabase.get_skill(str(sid))
			names.append(str(sk.skill_name) if sk != null else str(sid))
		var combo := ""
		for i in names.size():
			combo += str(names[i])
			if i < names.size() - 1:
				combo += " → "
		var cl := _lab(combo + "：先用控制/减速技能贴上去，再用伤害技能收尾；位移留作追击或保命。", UiKit.FS_MD, UiKit.C_GOLD)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.custom_minimum_size = Vector2(_fs(700), 0)
		_content.add_child(cl)

	_content.add_child(_section("对线思路"))
	var lane := HeroPickData.role_lane(role)
	var lane_tip := ""
	match role:
		"战士":
			lane_tip = "%s：先推线压塔，利用兵线换血，注意打野位置，被越塔时用控制技能拖时间。" % lane
		"法师":
			lane_tip = "%s：控线在塔前，用技能消耗对方血量，蓝量过半就回城补状态，别压线太深。" % lane
		"刺客":
			lane_tip = "%s：清完自家野区直接抓人，优先抓没有位移的边路，抓完顺路吃兵线。" % lane
		"射手":
			lane_tip = "%s：打钱优先，能不打架就不打架，注意辅助位置，塔下补刀最安全。" % lane
		"辅助":
			lane_tip = "%s：跟着射手保护，同时把视野做到河道口，对面打野消失立刻报点。" % lane
		_:
			lane_tip = "%s：跟着队伍节奏走。" % lane
	var ll := _lab(lane_tip, UiKit.FS_MD, UiKit.C_TEXT)
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ll.custom_minimum_size = Vector2(_fs(700), 0)
	_content.add_child(ll)

	_content.add_child(_section("上手小贴士"))
	var tips2 := _lab("· 记得带对应的召唤师技能（可在备战界面改出装与方案）。\n· 技能等级压制时优先升级主打技能，蓝量不足就别硬拼。\n· 团战先看小地图，站位比操作更重要。",
		UiKit.FS_SM, UiKit.C_TEXT_DIM)
	tips2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tips2.custom_minimum_size = Vector2(_fs(700), 0)
	_content.add_child(tips2)


func _fill_build() -> void:
	_content.add_child(_section("推荐出装（3 套）"))
	var variants: Array = ItemDatabase.get_recommended_variants(_hero)
	if variants.is_empty():
		_content.add_child(_lab("暂无该英雄的推荐出装", UiKit.FS_MD, UiKit.C_TEXT_DIM))
		return
	for i in variants.size():
		var ids: Array = variants[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiKit.skin_chip(UiKit.C_GOLD if i == 0 else UiKit.C_TEAM0, 0.5, _fs(10)))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", _fs(4))
		card.add_child(v)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", _fs(10))
		v.add_child(h)
		h.add_child(_lab("方案 %d" % (i + 1), UiKit.FS_LG, UiKit.C_GOLD))
		var total := 0
		var names: Array = []
		for id in ids:
			var it: Dictionary = ItemDatabase.get_item(str(id))
			if it.is_empty():
				continue
			names.append(str(it.get("name", id)))
			total += int(it.get("cost", 0))
		var spc := Control.new()
		spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(spc)
		h.add_child(_lab("总价约 %d 金" % total, UiKit.FS_SM, UiKit.C_TEXT_DIM))
		# 装备图标行（悬浮弹详情：属性 / 被动 / 合成 / 价格）
		var icon_row := HBoxContainer.new()
		icon_row.add_theme_constant_override("separation", _fs(6))
		v.add_child(icon_row)
		for id in ids:
			var it: Dictionary = ItemDatabase.get_item(str(id))
			if it.is_empty():
				continue
			var wrap := Control.new()
			wrap.custom_minimum_size = Vector2(_fs(60), _fs(60))
			wrap.mouse_filter = Control.MOUSE_FILTER_STOP
			wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var ic := SelectArt.ItemIcon.new(str(it.get("name", id)), int(it.get("tier", 1)), _fs(56))
			ic.position = Vector2(_fs(2), _fs(2))
			wrap.add_child(ic)
			wrap.mouse_entered.connect(_show_item_tip.bind(str(id), wrap))
			wrap.mouse_exited.connect(_hide_item_tip)
			icon_row.add_child(wrap)
		var nl := _lab(_join(names, " → "), UiKit.FS_SM, UiKit.C_TEXT_DIM)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.custom_minimum_size = Vector2(_fs(700), 0)
		v.add_child(nl)
		_content.add_child(card)
	var hint := _lab("想改出装：底部「去备战配置出装」会直接打开该英雄的备战界面。", UiKit.FS_SM, UiKit.C_TEXT_DIM)
	_content.add_child(hint)


# ---------- 跳转 ----------
func _goto_loadout() -> void:
	if _hero == "":
		return
	LoadoutScreen.open_hero = _hero
	get_tree().call_deferred("change_scene_to_file", "res://scenes/loadout.tscn")


# ---------- 工具 ----------
func _load_cfgs() -> Dictionary:
	var bm: Node = BattleManager.new()
	var out: Dictionary = {}
	if bm != null:
		out = bm.hero_configs
		bm.free()
	return out


func _summoner_name(sid: String) -> String:
	var sk: Skill = SkillDatabase.get_skill(sid)
	return str(sk.skill_name) if sk != null else sid


func _skill_kind(t: int) -> String:
	match t:
		0: return "指向"
		1: return "范围"
		2: return "增益"
		3: return "线性"
		4: return "位移"
		5: return "多段"
		6: return "护盾"
	return "技能"


# 详细技能说明：伤害构成与加成、作用范围、控制/增益效果、施法与类型说明
func _skill_detail(sk: Skill) -> String:
	var lines: Array = []
	var dmg_parts: Array = []
	if sk.phy_damage > 0.0:
		dmg_parts.append("物理 %d" % int(round(sk.phy_damage)))
	if sk.mag_damage > 0.0:
		dmg_parts.append("法术 %d" % int(round(sk.mag_damage)))
	if sk.damage > 0.0:
		dmg_parts.append("基础 %d" % int(round(sk.damage)))
	if not dmg_parts.is_empty():
		var t := "伤害：" + _join(dmg_parts, " / ")
		var ratios: Array = []
		if sk.phy_bonus_ratio > 0.0:
			ratios.append("+%d%% 物理加成" % int(round(sk.phy_bonus_ratio * 100.0)))
		if sk.mag_bonus_ratio > 0.0:
			ratios.append("+%d%% 法术加成" % int(round(sk.mag_bonus_ratio * 100.0)))
		if sk.bonus_ratio > 0.0:
			ratios.append("+%d%% 额外加成" % int(round(sk.bonus_ratio * 100.0)))
		if not ratios.is_empty():
			t += "（" + _join(ratios, " · ") + "）"
		lines.append(t)
	var area: Array = []
	if sk.cast_range > 0.0:
		area.append("施法距离 %.0fm" % sk.cast_range)
	if sk.radius > 0.0:
		area.append("范围半径 %.0fm" % sk.radius)
	if sk.bullet_range > 0.0:
		area.append("最远飞行 %.0fm" % sk.bullet_range)
	if sk.self_displacement > 0.0:
		area.append("自身位移 %.0fm" % sk.self_displacement)
	if not area.is_empty():
		lines.append("作用范围：" + _join(area, " · "))
	var fx: Array = []
	if sk.applies_stun > 0.0:
		fx.append("眩晕 %.1fs" % sk.applies_stun)
	if sk.applies_knockup > 0.0:
		fx.append("击飞 %.1fs" % sk.applies_knockup)
	if sk.applies_slow > 0.0:
		var slow_pct := sk.applies_slow * (100.0 if sk.applies_slow <= 1.0 else 1.0)
		fx.append("减速 %d%% / %.1fs" % [int(round(slow_pct)), sk.slow_duration])
	if sk.shield_amount > 0.0:
		fx.append("护盾 %d" % int(round(sk.shield_amount)))
	if sk.duration > 0.0:
		fx.append("持续 %.1fs" % sk.duration)
	if sk.restore > 0:
		fx.append("可充能 %d 层" % sk.restore)
	if sk.is_channeling:
		fx.append("引导施法")
	if not fx.is_empty():
		lines.append("控制 / 增益：" + _join(fx, " · "))
	var cast: Array = []
	cast.append("冷却 %.1fs" % sk.cooldown)
	if sk.mana_cost > 0:
		cast.append("法力 %d" % sk.mana_cost)
	if sk.cast_time > 0.0:
		cast.append("前摇 %.2fs" % sk.cast_time)
	if sk.projectile_speed > 0.0 and sk.bullet_range > 0.0:
		cast.append("弹速 %.0f" % sk.projectile_speed)
	lines.append("施法：" + _join(cast, " · "))
	if sk.cd_bonus > 0.0:
		lines.append("成长：每级冷却 -%.1fs" % sk.cd_bonus)
	if dmg_parts.is_empty():
		lines.append("伤害：基础值随技能等级与物理/法术加成成长")
	lines.append("说明：" + _skill_kind_detail(int(sk.type)))
	lines.append("实战：" + _skill_tip(int(sk.type)))
	return _join(lines, "\n")


func _skill_tip(t: int) -> String:
	match t:
		0: return "等对方交完位移/净化再锁，别对着免控目标空放。"
		1: return "预判对方走位封路，团战里丢进人堆收益最高。"
		2: return "开打前先开增益，持续时间过了再撤，别提前交。"
		3: return "对着敌人移动方向预判，贴脸时更不容易被躲。"
		4: return "留作追击或逃命，穿墙可以绕开视野。"
		5: return "窗口内尽快打完连段，断连会浪费冷却。"
		6: return "预判对方爆发前开，护盾可以挡掉关键伤害。"
	return "熟悉范围与冷却后再决定出手时机。"


func _skill_kind_detail(t: int) -> String:
	match t:
		0: return "指向性技能，锁定单个目标；对方免控或不可选中时会失效。"
		1: return "范围技能，指定区域落地，可同时命中区域内多个目标。"
		2: return "增益技能，强化自身属性或下一次普攻，注意持续时间。"
		3: return "线性技能，朝方向发射，命中路径上所有敌人。"
		4: return "位移技能，向指定方向位移，可用来追击、撤退或穿墙。"
		5: return "多段技能，可在重施窗口内连续释放多段。"
		6: return "护盾技能，为自身或友方提供护盾抵挡伤害。"
	return "通用技能。"


# 装备图标悬浮详情：品质名 + 价格/部位 + 属性 + 被动 + 合成
func _show_item_tip(item_id: String, ctrl: Control) -> void:
	_hide_item_tip()
	var it: Dictionary = ItemDatabase.get_item(item_id)
	if it.is_empty() or ctrl == null:
		return
	var tier := int(it.get("tier", 1))
	var qcol: Color = UiKit.QUALITY_COLORS[clampi(tier, 1, 5)]
	var tip := PanelContainer.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.z_index = 300
	tip.custom_minimum_size = Vector2(_fs(420), 0)
	tip.add_theme_stylebox_override("panel", UiKit.skin_card(qcol, true, 0.97))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _fs(3))
	tip.add_child(v)
	v.add_child(_lab(str(it.get("name", item_id)), UiKit.FS_LG, qcol.lightened(0.25)))
	var cls_map := {"attack": "物理", "magic": "法术", "defense": "防御", "boots": "鞋子",
		"jungle": "打野", "support": "游走", "survival": "保命", "attack_speed": "攻速"}
	var cls := str(it.get("class", ""))
	var meta := "T%d · %d 金" % [tier, int(it.get("cost", 0))]
	if cls != "":
		meta += " · " + str(cls_map.get(cls, cls))
	v.add_child(_lab(meta, UiKit.FS_SM, UiKit.C_TEXT_DIM))
	var stat_names := {"attack": "攻击", "magic_attack": "法强", "health": "生命", "armor": "物防",
		"magic_resist": "法防", "attack_speed": "攻速%", "crit_chance": "暴击%", "cooldown": "冷缩%",
		"speed": "移速", "lifesteal": "吸血%", "mana": "蓝量", "hp_regen": "回血",
		"armor_pen_percent": "物穿%", "magic_pen": "法穿"}
	var parts: Array = []
	for k in stat_names:
		var val := int(it.get(str(k), 0))
		if val != 0:
			parts.append("%s+%d" % [str(stat_names[k]), val])
	if not parts.is_empty():
		var sl := _lab("属性：" + _join(parts, " · "), UiKit.FS_SM, UiKit.C_TEXT)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size = Vector2(_fs(390), 0)
		v.add_child(sl)
	var passive := str(it.get("passive", ""))
	if passive != "":
		var pl := _lab("被动：" + passive, UiKit.FS_SM, UiKit.C_GOLD)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pl.custom_minimum_size = Vector2(_fs(390), 0)
		v.add_child(pl)
	var reqs: Array = it.get("requires", [])
	if not reqs.is_empty():
		var names: Array = []
		for rid in reqs:
			names.append(str(ItemDatabase.get_item(str(rid)).get("name", rid)))
		v.add_child(_lab("合成：" + _join(names, " + "), UiKit.FS_SM, UiKit.C_TEXT_DIM))
	add_child(tip)
	tip.size = tip.get_combined_minimum_size()
	var r: Rect2 = ctrl.get_global_rect()
	var vp := get_viewport_rect().size
	var pos := Vector2(r.position.x, r.end.y + _fs(8))
	if pos.y + tip.size.y > vp.y - _fs(8):
		pos.y = r.position.y - tip.size.y - _fs(8)
	pos.x = clampf(pos.x, _fs(8), maxf(_fs(8), vp.x - tip.size.x - _fs(8)))
	tip.global_position = pos
	_item_tip = tip


func _hide_item_tip() -> void:
	if _item_tip != null and is_instance_valid(_item_tip):
		_item_tip.queue_free()
	_item_tip = null


func _skill_desc(sk: Skill) -> String:
	var parts: Array = []
	var dmg := sk.damage + sk.phy_damage + sk.mag_damage
	if dmg > 0.0:
		parts.append("伤害 %d" % int(round(dmg)))
	if sk.radius > 0.0:
		parts.append("范围 %.0fm" % sk.radius)
	if sk.duration > 0.0:
		parts.append("持续 %.1fs" % sk.duration)
	if sk.shield_amount > 0.0:
		parts.append("护盾 %d" % int(round(sk.shield_amount)))
	if sk.applies_stun > 0.0:
		parts.append("眩晕 %.1fs" % sk.applies_stun)
	if sk.applies_knockup > 0.0:
		parts.append("击飞 %.1fs" % sk.applies_knockup)
	if sk.applies_slow > 0.0:
		parts.append("减速 %d%%" % int(round(sk.applies_slow * 100.0)))
	return _join(parts, " · ")


func _join(items: Array, sep: String) -> String:
	var out := ""
	for it in items:
		out = str(it) if out == "" else out + sep + str(it)
	return out


func _section(title: String) -> Label:
	return _lab("— " + title + " —", UiKit.FS_MD, UiKit.C_GOLD)


func _num(v: int) -> String:
	return str(v)


func _fs(tier: int) -> int:
	return int(round(float(tier) * _s))


func _lab(txt: String, tier: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", _fs(tier))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _btn(txt: String, accent: Color, filled := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	b.custom_minimum_size = Vector2(0, _fs(52))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))
	b.add_theme_color_override("font_color", Color(0.08, 0.05, 0.0) if filled else UiKit.C_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.0) if filled else Color.WHITE)
	return b
