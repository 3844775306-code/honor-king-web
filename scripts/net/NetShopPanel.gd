class_name NetShopPanel extends Control
## P3d 商店：O 开/关，B 推荐购买；点装备卡选中，右侧详情列购买/出售（与 host 交互一致）。
## 版式/几何/配色/字号逐项复刻 host UI_Manager._open_shop（scripts/ui/UI_Manager.gd:919 起）：
## 居中 2000 宽满高抽屉 + 标题金币 + 分类按钮 + 左 2 列装备卡 + 右详情列 + 底部已拥有条。
## 坐标基底 2400×1400 stretch 画布（canvas_items + expand），rs = ui_scale() = maxf(1.0, 视口宽/2400) × 1.35。
## 数据全部来自 host own 快照（gold/equip/rec），购买/出售统一走 C_BUY/C_SELL 由 host 校验。

const PANEL_W_MAX := 2280.0   # host drawer 宽 = min(2280, 视口宽-48)（原始像素，不乘 rs）
const PANEL_PAD := 48.0
const GRID_L := 0.02          # host 商店左网格锚点
const GRID_R := 0.56
const DETAIL_L := 0.60        # host 右侧详情列锚点
const DETAIL_R := 0.98
const CARD_H := 76.0          # host 装备卡 custom_minimum_size
const BADGE := 54.0
const CLOSE_W := 50.0
const CLOSE_MARGIN := 6.0

# host _shop_categories()：分类 = 显式装备 ID 表（与 items["class"] 字段无关，两端同源）
const CATS := {
	"物理": ["iron_sword", "vampire_scythe", "storm_sword", "swift_spear", "thundercry_blade", "corona", "meteorite", "speedy_strike_spear", "bloodsoul_blade", "bramble_gauntlets", "bloodthirster", "infinity_edge", "sage_power", "battle_axe", "breaker", "star_shatterer", "blade_of_sanction", "world_end", "purify", "demon_bane_blade", "frost_assault", "knife", "battle_fist", "enchanted_feather", "furious_dual_blades", "forged_steel_blade", "piercing_cloud_bow", "lightning_knife", "shadow_blade", "sunspire_bow", "dawn", "chase_wind", "shadow_dart", "swift_day"],
	"法术": ["magic_book", "blue_diamond", "secert_spell", "crystal_flow", "big_bang", "saint_spell", "spell_vamp_book", "spell_stone", "cloud_wood", "phantom_mask", "echo_staff", "nightmare", "rabadon", "void_staff", "golden_body", "pain_mask", "dusk_flow", "fire_dominate", "gold_saint_sword", "saint_cup", "godslayer_book", "witch_staff", "prophecy_of_time", "break_cocoon_cloth", "sky_book", "frost_breath", "moon_god"],
	"防御": ["cloth_armor", "cloth_magic_armor", "red_diamond", "regen_crystal", "swift_armor", "strength_belt", "tarnkappe", "snow_shield", "guardian_armor", "agate_breastplate_mirror", "sky_earth_stone", "thornmail", "omen", "mage_robe", "dragon_shield", "red_cloak", "heavy_armor", "eye_of_the_phoenix", "ice_storm", "fierce_armor", "night_guardian", "ice_fist", "ice_shock", "rising_sun"],
	"靴子": ["boots", "armor_boots", "resist_boots", "cd_boots", "swift_boots", "spell_boots", "run_boots"],
	"打野": ["hunter_knife", "guerrilla_blade", "chase_blade", "patrol_axe", "rune_blade", "greed_blade", "giant_grasp"],
	"游走": ["ancient_coin", "wind_blessing", "guardian_glory", "extreme_shadow", "redeemer_guard", "star_spring_guard", "galloping_wolf_guard", "revealing_light_guard", "redeemer_shadow", "star_spring_shadow", "galloping_wolf_shadow", "revealing_light_shadow"],
	"辅助": ["ancient_coin", "wind_blessing", "guardian_glory", "extreme_shadow", "redeemer_guard", "star_spring_guard", "galloping_wolf_guard", "revealing_light_guard", "redeemer_shadow", "star_spring_shadow", "galloping_wolf_shadow", "revealing_light_shadow"],
	"保命": ["blood_rage", "famous_blade", "revive", "primal_pearl", "immovable_firmament", "rage_ghost", "sereve_winter"],
}

# host _update_shop_detail 的 numeric_attrs 表（顺序/文案/单位同源）
const ATTR_ROWS := [
	["attack", "攻击力"], ["ability_power", "法术强度"], ["attack_speed", "攻击速度", "%"],
	["crit_chance", "暴击率", "%"], ["crit_damage", "暴击伤害", "%"],
	["armor", "物理防御"], ["magic_resist", "法术防御"], ["phys_pen", "固定物穿"], ["magic_pen", "固定法穿"],
	["armor_pen_percent", "物理穿透", "%"], ["magic_pen_percent", "法术穿透", "%"], ["lifesteal", "物理吸血", "%"],
	["spell_vamp", "法术吸血", "%"], ["speed", "移动速度"], ["per_speed", "移速", "%"],
	["cooldown", "冷却缩减", "%"], ["health", "生命值"],
	["mana", "最大法力"], ["hp_regen", "生命回复"], ["mana_regen", "法力回复"],
	["toughness", "韧性", "%"], ["per_ability_power", "法术强度", "%"],
]

# host 总装备加成行：客户端按已购装备属性累加（host 用 hero.bonus_*）
const TOTAL_ROWS := [
	["攻击力", "attack"], ["法术强度", "ability_power"], ["生命值", "health"], ["护甲", "armor"],
	["魔抗", "magic_resist"], ["移速", "speed"], ["百分比移速", "per_speed"], ["攻速%", "attack_speed"],
	["暴击率", "crit_chance"], ["暴击伤害", "crit_damage"], ["冷却缩减", "cooldown"], ["物理吸血", "lifesteal"],
	["法术吸血", "spell_vamp"], ["物穿", "armor_pen_percent"], ["法穿", "magic_pen_percent"], ["韧性", "toughness"],
]

var _gold := 0
var _hero_name := ""
var _equip: Array = []      # 已购 id 序（槽位=索引）
var _rec := ""              # host 同款 B 决策（_get_best_recommended_item）
var _bs: Array = []         # host own.bs：「总装备加成」逐行 [text, Color]（host 烘焙，文本已含 "  xx: +N"）
var _tab := 0
var _scroll := 0            # 装备卡滚动行号（2 列/行）
var _sel := ""              # 当前选中装备 id（右侧详情列）
var _dscroll := 0.0         # 详情列滚动体偏移
var _dbody_h := 0.0         # 详情列内容高（上一帧测得）
var _dview_h := 0.0         # 详情列可视高（上一帧测得）
var _f := UiKit.font()
var _hot: Array = []        # 每帧 draw 时收集的命中区 [{r:Rect2, k:String, a:Variant}]
var _tab_labels := ["物理", "法术", "防御", "靴子", "打野", "游走", "保命", "辅助"]
var _plan_cache: Array = []
var _plan_for := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _us() -> float:
	return UiKit.scale()

# 与 host 商店共用纵向分区：分类栏固定高、内容从分类栏下方开始、底部已购条独占左列
func _tab_top() -> float:
	return 56.0

func _content_top(rs: float) -> float:
	return _tab_top() + 42.0 * rs + 12.0

func _owned_slot(rs: float) -> float:
	return clampf(108.0 * rs, 72.0, 138.0)

func _owned_h(rs: float) -> float:
	return _owned_slot(rs) + 18.0

func _pw() -> float:
	var area := get_viewport().get_visible_rect().size
	return minf(PANEL_W_MAX, area.x - PANEL_PAD)

func _panel_rect() -> Rect2:
	var area := get_viewport().get_visible_rect().size
	var pw := _pw()
	return Rect2((area.x - pw) * 0.5, 0.0, pw, area.y)

func _text(pos: Vector2, txt: String, sz: float, col: Color) -> void:
	draw_string_outline(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 1, Color(0, 0, 0, 0.85))
	draw_string(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _text_c(cx: float, baseline: float, txt: String, sz: float, col: Color) -> void:
	var w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(Vector2(cx - w * 0.5, baseline), txt, sz, col)

func _text_r(right_x: float, baseline: float, txt: String, sz: float, col: Color) -> void:
	var w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(Vector2(right_x - w, baseline), txt, sz, col)

# host _apply_panel_style / _item_card_style / _cat_button_style 的等效绘制
func _box(r: Rect2, bg: Color, bord := Color(0, 0, 0, 0), bw := 0, radius := 0, bw_bottom := 0) -> void:
	var sb := UiKit.flat(clampf(bg.a, 0.2, 1.0), radius, bw, bord, bg, 0.0)
	if bw_bottom > 0:
		sb.border_width_bottom = bw_bottom
	draw_style_box(sb, r)

# host BadgeBox：圆角图标块 + 品级色边框 + 类别色顶带 + 中央单字
func _badge(pos: Vector2, sz: float, glyph: String, tint: Color, border: Color, glyph_sz: float) -> void:
	_box(Rect2(pos, Vector2(sz, sz)), Color(0.03, 0.05, 0.08, 0.72), border, 2, int(maxf(4.0, sz * 0.14)))
	draw_rect(Rect2(pos.x, pos.y, sz, 3.0), tint, true)
	if glyph != "":
		draw_string(_f, Vector2(pos.x, pos.y + sz * 0.5 + glyph_sz * 0.18), glyph, HORIZONTAL_ALIGNMENT_CENTER, sz, glyph_sz, tint.lightened(0.35))

# host 默认主题 Button 的等效绘制（购买/出售/关闭/推荐）；gold=主购买按钮，fs=覆盖字号
func _button(r: Rect2, label: String, enabled: bool, danger := false, gold := false, fs := 0.0) -> void:
	var bg := Color(0.24, 0.27, 0.33, 0.95) if enabled else Color(0.14, 0.15, 0.19, 0.9)
	var bc := Color(1, 1, 1, 0.22) if enabled else Color(1, 1, 1, 0.08)
	var col := Color(1, 1, 1, 0.95) if enabled else Color(1, 1, 1, 0.38)
	if gold and enabled:
		bg = Color(0.98, 0.80, 0.28, 0.98)
		bc = Color(1.0, 0.93, 0.62, 0.95)
		col = Color(0.08, 0.07, 0.04)
	elif danger and enabled:
		bg = Color(0.32, 0.13, 0.13, 0.95)
		bc = Color(1.0, 0.35, 0.35, 0.55)
		col = Color(1.0, 0.42, 0.42)
	elif danger:
		bg = Color(0.30, 0.15, 0.15, 0.9)
		bc = Color(1.0, 0.4, 0.4, 0.3)
		col = Color(1.0, 0.5, 0.45, 0.65)
	_box(r, bg, bc, 1, 5)
	var fsz := fs if fs > 0.0 else 14.0 * _us()
	_text_c(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5 + fsz * 0.36, label, fsz, col)

# host card.modulate 的逐色等效（买不起整卡压暗）
func _dim(c: Color, m: Color) -> Color:
	return Color(c.r * m.r, c.g * m.g, c.b * m.b, c.a)

func _sep(x0: float, x1: float, y: float) -> void:
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.16), 1.0, true)

# 中文按字符宽度折行（host Label 无 autowrap 会溢出，复刻时收进详情列宽）
func _wrap(txt: String, max_w: float, sz: float) -> Array:
	var out := []
	var cur := ""
	var cur_w := 0.0
	for i in range(txt.length()):
		var ch := txt[i]
		var w := _f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		if cur != "" and cur_w + w > max_w:
			out.append(cur)
			cur = ch
			cur_w = w
		else:
			cur += ch
			cur_w += w
	if cur != "":
		out.append(cur)
	return out

# ---------- host 商店视觉表 ----------

func _tier_color(tier: int) -> Color:
	match tier:
		1: return Color(0.72, 0.76, 0.82)
		2: return Color(0.3, 0.7, 1.0)
		3: return Color(0.8, 0.48, 1.0)
		4: return Color(1.0, 0.78, 0.2)
		_: return Color(0.85, 0.85, 0.85)

func _tier_name(tier: int) -> String:
	match tier:
		1: return "基础"
		2: return "中级"
		3: return "终极大件"
		4: return "终极神装"
		_: return ""

func _cat_style(cat: String) -> Array:
	match cat:
		"物理": return ["刃", Color(1.0, 0.52, 0.22)]
		"法术": return ["杖", Color(0.72, 0.5, 1.0)]
		"防御": return ["盾", Color(0.4, 0.72, 1.0)]
		"靴子": return ["鞋", Color(0.95, 0.75, 0.42)]
		"打野": return ["猎", Color(0.45, 0.85, 0.42)]
		"游走": return ["辅", Color(0.25, 0.85, 0.85)]
		"辅助": return ["助", Color(0.95, 0.86, 0.3)]
		"保命": return ["护", Color(1.0, 0.42, 0.42)]
		_: return ["装", Color(0.85, 0.85, 0.85)]

func _cat_of(id: String) -> String:
	for cat in _tab_labels:
		if id in CATS.get(cat, []):
			return cat
	return ""

func _cat_tint(cat: String) -> Color:
	if cat == "推荐":
		return UiKit.C_GOLD
	var c: Color = _cat_style(cat)[1]
	return c

# host _attr_tint / _attr_glyph：物理橙 / 法术紫 / 其余绿；glyph 用单字代替 host StatIcon 形状
func _attr_tint(key: String) -> Color:
	if key in ["attack", "armor", "armor_pen_percent", "lifesteal", "crit_chance", "crit_damage", "attack_speed", "phys_pen", "speed", "per_speed", "hp_regen"]:
		return Color(1.0, 0.62, 0.28)
	if key in ["ability_power", "magic_resist", "magic_pen_percent", "spell_vamp", "per_ability_power", "mana", "mana_regen", "cooldown"]:
		return Color(0.72, 0.55, 1.0)
	return Color(0.45, 0.95, 0.62)

func _attr_glyph(key: String) -> String:
	match key:
		"attack", "phys_pen", "per_speed": return "刃"
		"armor_pen_percent", "magic_pen_percent": return "穿"
		"crit_chance", "crit_damage", "hp_regen": return "暴"
		"attack_speed": return "速"
		"lifesteal", "spell_vamp", "health": return "血"
		"armor", "magic_resist", "toughness": return "盾"
		"ability_power", "per_ability_power", "mana", "mana_regen", "cooldown": return "法"
		"speed": return "移"
	return "属"

# 客户端自有推荐数据（hero 名→职责→ItemDatabase role 方案）；未知英雄不伪造
func _rec_ready() -> bool:
	return _hero_name != "" and HeroPickData.HERO_ROLE.has(_hero_name) and not _plan().is_empty()

func _tabs() -> Array:
	var out: Array = []
	if _rec_ready():
		out.append("推荐")
	out.append_array(_tab_labels)
	return out

# host _shop_affordable_count：只统计当前买得起的（已成型大件已下架）
func _afford_count(cat: String) -> int:
	var n := 0
	var ids: Array = _plan() if cat == "推荐" else CATS.get(cat, [])
	for id in ids:
		var it: Dictionary = ItemDatabase.get_item(str(id))
		if it.is_empty():
			continue
		if _slot_of(str(id)) >= 0 and int(it.get("tier", 1)) >= 3:
			continue
		if _gold >= _need_cost(str(id)):
			n += 1
	return n

func feed(o: Dictionary) -> void:
	_gold = int(o.get("gold", 0))
	var nm := str(o.get("name", ""))
	if nm != _hero_name:
		_hero_name = nm
		_plan_for = ""
	var e = o.get("equip", [])
	_equip = (e.duplicate() if e is Array else [])
	_rec = str(o.get("rec", ""))
	var b = o.get("bs", [])
	_bs = (b.duplicate() if b is Array else [])
	queue_redraw()

func _items_of_tab(t: int) -> Array:
	var out: Array = []
	var tabs := _tabs()
	var cat := str(tabs[clampi(t, 0, tabs.size() - 1)])
	var ids: Array = _plan() if cat == "推荐" else CATS.get(cat, [])
	for id: String in ids:
		var it: Dictionary = ItemDatabase.get_item(id)
		if it.is_empty():
			continue
		# host：已成型大件不再上架（3 阶及以上且已拥有）
		if _slot_of(id) >= 0 and int(it.get("tier", 1)) >= 3:
			continue
		out.append(id)
	# host：tier 高→低，同 tier 价格高→低
	out.sort_custom(func(a, b): return _sort_rank(a) > _sort_rank(b))
	return out

func _sort_rank(id: String) -> float:
	var it: Dictionary = ItemDatabase.get_item(id)
	return float(int(it.get("tier", 1)) * 100000) + float(int(it.get("cost", 0)))

func _slot_of(id: String) -> int:
	return _equip.find(id)

func _has_component(id: String) -> bool:
	for rid: String in ItemDatabase.get_item(id).get("requires", []):
		if _slot_of(rid) >= 0:
			return true
	return false

func _afford(id: String) -> bool:
	return _gold >= _need_cost(id)

func _bonus_totals() -> Dictionary:
	var out := {}
	for id in _equip:
		var it: Dictionary = ItemDatabase.get_item(str(id))
		for tr in TOTAL_ROWS:
			var k := str(tr[1])
			if it.has(k):
				out[k] = float(out.get(k, 0.0)) + float(it[k])
	return out

func buy(id: String) -> void:
	NetSession.send_command([NetSession.C_BUY, id])

func sell_slot(slot: int) -> void:
	NetSession.send_command([NetSession.C_SELL, slot])

func quick_buy() -> void:
	if _rec != "":
		NetSession.send_command([NetSession.C_BUY, _rec])

func toggle() -> void:
	if visible:
		UiKit.hide_panel(self, 0.10)
		return
	# host 每次 _open_shop 都新建抽屉：滚动归零，选中项保留（不存在时由网格回退首件可买）
	_scroll = 0
	_dscroll = 0.0
	UiKit.show_panel(self, 0.14)
	queue_redraw()

func hide_panel() -> void:
	UiKit.hide_panel(self, 0.10)

# ---------- 绘制（几何/配色/字号 = host UI_Manager._open_shop 同源） ----------

func _draw() -> void:
	_hot.clear()
	var vp := get_viewport()
	if vp == null:
		return
	var rs := _us()
	var area := vp.get_visible_rect().size
	var tn := _tabs().size()
	_tab = clampi(_tab, 0, maxi(tn - 1, 0))
	# host：dim ColorRect(0,0,0,0.4) + drawer Panel(_apply_panel_style 0.90、直角、无边框)
	draw_rect(Rect2(Vector2.ZERO, area), Color(0, 0, 0, 0.4))
	var panel := _panel_rect()
	draw_rect(panel, Color(0, 0, 0, 0.90))
	_draw_header(panel, rs)
	_draw_tabs(panel, rs)
	_draw_grid(panel, rs)
	_draw_owned(panel, rs)
	_draw_detail(panel, rs)
	_draw_action_bar(panel, rs)
	_draw_close(panel, rs)

func _draw_header(panel: Rect2, rs: float) -> void:
	# host 标题：商店 + 金币 + 可买件数（P0）
	var fs := 20.0 * rs
	var n := 0
	for cat in _tab_labels:
		n += _afford_count(str(cat))
	_text(Vector2(panel.position.x + 20.0 * rs, panel.position.y + 10.0 + fs * 0.82),
		"商店  |  金币: %d  |  可买 %d 件" % [_gold, n], fs, Color(1.0, 0.84, 0.0))
func _draw_close(panel: Rect2, rs: float) -> void:
	# host close_btn：锚右上，offset(-56, 6, -6, 56)，font 26*rs
	var r := Rect2(panel.position.x + _pw() - CLOSE_MARGIN - CLOSE_W, panel.position.y + CLOSE_MARGIN, CLOSE_W, CLOSE_W)
	_hot.append({"r": r, "k": "close", "a": 0})
	_box(r, Color(0.24, 0.27, 0.33, 0.95), Color(1, 1, 1, 0.22), 1, 5)
	var fs := 26.0 * rs
	_text_c(r.position.x + CLOSE_W * 0.5, r.position.y + CLOSE_W * 0.5 + fs * 0.36, "×", fs, Color(1, 1, 1, 0.92))

func _draw_tabs(panel: Rect2, rs: float) -> void:
	var fs := 14.0 * rs
	var th := 42.0 * rs
	var gap := 6.0 * rs
	var tabs := _tabs()
	var x0 := panel.position.x + 20.0 * rs
	var avail := panel.size.x - 40.0 * rs
	var tw := maxf(70.0, (avail - gap * float(maxi(tabs.size() - 1, 0))) / float(maxi(tabs.size(), 1)))
	var y0 := panel.position.y + _tab_top()
	for i in range(tabs.size()):
		var cat := str(tabs[i])
		var r := Rect2(x0 + i * (tw + gap), y0, tw, th)
		_hot.append({"r": r, "k": "tab", "a": i})
		var tint: Color = _cat_tint(cat)
		var sel := i == _tab
		var bg := Color(0.18, 0.2, 0.26, 0.95) if sel else Color(0.05, 0.07, 0.11, 0.88)
		var bc := tint if sel else Color(1, 1, 1, 0.14)
		_box(r, bg, bc, 1, 9, 4 if sel else 0)
		var tc := Color(1.0, 0.92, 0.4) if sel else tint.lightened(0.55)
		_text_c(r.position.x + tw * 0.5, r.position.y + th * 0.5 + fs * 0.36, cat, fs, tc)
		# 可买件数角标（host 分类按钮文本后缀的徽章化）
		var cnt := _afford_count(cat)
		if cnt > 0:
			var br := Rect2(r.end.x - 24.0, r.position.y + 2.0, 21.0, 15.0)
			_box(br, tint.darkened(0.55), tint, 1, 7)
			_text_c(br.position.x + br.size.x * 0.5, br.position.y + br.size.y * 0.5 + 10.0 * rs * 0.36,
				str(cnt), 10.0 * rs, tint.lightened(0.55))
func _draw_grid(panel: Rect2, rs: float) -> void:
	var gx0 := panel.position.x + _pw() * GRID_L
	var gx1 := panel.position.x + _pw() * GRID_R
	var gy0 := panel.position.y + _content_top(rs)
	var gy1 := panel.end.y - _owned_h(rs) - 24.0
	var list := _items_of_tab(_tab)
	# 选择记忆：仍存在则保留，否则回退到第一件买得起
	var keep := false
	for k_id in list:
		if str(k_id) == _sel:
			keep = true
	if not keep:
		var pick := ""
		for a_id in list:
			if _afford(str(a_id)):
				pick = str(a_id)
				break
		if pick == "" and not list.is_empty():
			pick = str(list[0])
		_sel = pick
	var gap := 6.0 * rs
	var row_gap := 4.0 * rs
	var card_w := ((gx1 - gx0) - gap) * 0.5
	var rows_vis := maxi(1, int((gy1 - gy0 + row_gap) / (CARD_H + row_gap)))
	var max_scroll := maxi(0, ceili(float(list.size()) / 2.0) - rows_vis)
	_scroll = clampi(_scroll, 0, max_scroll)
	var start := _scroll * 2
	for n in range(start, mini(list.size(), start + rows_vis * 2)):
		var id: String = str(list[n])
		var col := (n - start) % 2
		var row := int((n - start) * 0.5)
		var r := Rect2(gx0 + col * (card_w + gap), gy0 + row * (CARD_H + row_gap), card_w, CARD_H)
		_draw_card(r, id, rs)
func _draw_card(r: Rect2, id: String, rs: float) -> void:
	_hot.append({"r": r, "k": "item", "a": id})
	var it: Dictionary = ItemDatabase.get_item(id)
	var tier: int = int(it.get("tier", 1))
	var tcol: Color = _tier_color(tier)
	var owned: bool = _slot_of(id) >= 0
	var can: bool = _afford(id)
	var sel: bool = id == _sel
	var pay: int = _need_cost(id)
	var cost: int = int(it.get("cost", 0))
	var diff: bool = pay < cost
	var rec: bool = _rec_ready() and (id in _plan() or id == _rec)
	# 买不起：整卡 ~0.64 压暗（host card.modulate）
	var dm := Color(0.64, 0.66, 0.72) if not can else Color.WHITE
	var bg := Color(0.1, 0.12, 0.2, 0.96) if sel else Color(0.04, 0.06, 0.1, 0.9)
	var bc := tcol if sel else Color(tcol.r, tcol.g, tcol.b, 0.35)
	_box(r, _dim(bg, dm), _dim(bc, dm), 1, 8)
	# 图标：品质色 item_icon（与 host / 推荐装 / 装备栏统一）
	var ir := Rect2(r.position + Vector2(8.0, (CARD_H - BADGE) * 0.5), Vector2(BADGE, BADGE))
	_draw_item_icon(ir, id)
	if not can:
		_box(ir, Color(0, 0, 0, 0.30), Color(0, 0, 0, 0), 0, 0)
	var fs_name := 16.0 * rs
	var fs_price := 13.0 * rs
	var fs_tag := 11.0 * rs
	var top := r.position.y + 8.0
	var bx := r.position.x + 8.0 + BADGE + 10.0
	_text(Vector2(bx, top + fs_name * 0.95), str(it.get("name", id)), fs_name, _dim(Color.WHITE, dm))
	var pc := Color(1.0, 0.82, 0.3) if can else Color(1.0, 0.45, 0.40)
	var ptxt := ("差价 %d 金" % pay) if diff else ("%d 金币" % cost)
	_text(Vector2(bx, top + fs_name * 1.25 + fs_price * 0.95), ptxt, fs_price, _dim(pc, dm))
	# 状态：★推荐 > 可合成 > 已拥有 > 金币不足
	var tag := ""
	var tagc := Color(0.62, 0.72, 0.86)
	if rec:
		tag = "★推荐"
		tagc = Color(1.0, 0.84, 0.38)
	elif diff:
		tag = "可合成"
		tagc = Color(0.45, 1.0, 0.5)
	elif owned:
		tag = "已拥有"
		tagc = Color(0.45, 1.0, 0.5)
	elif not can:
		tag = "金币不足"
		tagc = Color(1.0, 0.5, 0.42)
	if tag != "":
		_text(Vector2(bx, top + fs_name * 1.25 + fs_price * 1.35 + fs_tag * 1.1), tag, fs_tag, _dim(tagc, dm))
	# 内嵌「买」按钮（买不起显示差额），点买不改选中
	var bw := 62.0 * rs
	var bh := 26.0 * rs
	var br := Rect2(r.end.x - bw - 8.0, r.position.y + (CARD_H - bh) * 0.5, bw, bh)
	if can:
		_hot.append({"r": br, "k": "buy", "a": id})
		_box(br, Color(0.85, 0.68, 0.16, 0.95), Color(1.0, 0.9, 0.4, 0.9), 1, 6)
		_text_c(br.position.x + bw * 0.5, br.position.y + bh * 0.5 + 12.0 * rs * 0.36, "买", 12.0 * rs, Color(0.08, 0.07, 0.04))
	else:
		_box(br, _dim(Color(0.18, 0.20, 0.26, 0.95), dm), _dim(Color(1, 1, 1, 0.14), dm), 1, 6)
		_text_c(br.position.x + bw * 0.5, br.position.y + bh * 0.5 + 11.0 * rs * 0.36, "差%d" % (pay - _gold), 10.0 * rs, _dim(Color(0.75, 0.78, 0.85), dm))
	# 品级（右侧）
	_text_r(r.end.x - bw - 14.0, top + 12.0 * rs * 0.95, "[" + _tier_name(tier) + "]", 12.0 * rs, _dim(tcol, dm))
func _draw_owned(panel: Rect2, rs: float) -> void:
	# 6 个大图标槽 + 独立底板，只占左列，避免与右侧购买条/详情重叠
	var sz := _owned_slot(rs)
	var area_h := _owned_h(rs)
	var gap := 8.0 * rs
	var area := Rect2(panel.position.x + _pw() * GRID_L, panel.end.y - area_h - 8.0,
		_pw() * (GRID_R - GRID_L), area_h)
	_box(area, Color(0.02, 0.03, 0.05, 0.72), Color(1, 1, 1, 0.10), 1, 10)
	var cap_w := 78.0 * rs
	var oy := area.position.y + (area_h - sz) * 0.5
	var x0 := area.position.x + 12.0 * rs
	_text(Vector2(x0, oy + sz * 0.5 + 13.0 * rs * 0.36), "已购装备", 13.0 * rs, Color(0.74, 0.80, 0.90))
	x0 += cap_w
	for i in range(6):
		var r := Rect2(x0 + i * (sz + gap), oy, sz, sz)
		if i < _equip.size():
			var id := str(_equip[i])
			var bc := Color(1.0, 0.84, 0.3, 0.9) if id == _sel else Color(1, 1, 1, 0.18)
			_box(r.grow(1.0), Color(0.16, 0.19, 0.24, 0.95), bc, 1, 6)
			_hot.append({"r": r, "k": "owned", "a": i})
			_draw_item_icon(r, id)
		else:
			_box(r, Color(0.10, 0.12, 0.16, 0.9), Color(1, 1, 1, 0.12), 1, 6)
			_text_c(r.position.x + sz * 0.5, r.position.y + sz * 0.5 + 12.0 * rs * 0.36, "空", 12.0 * rs, Color(0.42, 0.48, 0.58))
func _draw_detail(panel: Rect2, rs: float) -> void:
	var it: Dictionary = ItemDatabase.get_item(_sel)
	if it.is_empty():
		return
	var dx := panel.position.x + _pw() * DETAIL_L
	var dw := _pw() * (DETAIL_R - DETAIL_L)
	var dy := panel.position.y + _content_top(rs)
	var bar_h := 46.0 * rs
	var dby := panel.end.y - 42.0 - bar_h - 6.0
	var tier := int(it.get("tier", 1))
	var tcol := _tier_color(tier)
	var cost := int(it.get("cost", 0))
	var pay := _need_cost(_sel)
	var comp := maxi(cost - pay, 0)
	var fs12 := 12.0 * rs
	var fs13 := 13.0 * rs
	var fs14 := 14.0 * rs
	var fs15 := 15.0 * rs
	var fs24 := 24.0 * rs
	var head_h := 96.0
	var body_top := dy + head_h
	var body_bot := dby
	var y := body_top + 4.0 - _dscroll

	# 滚动体：合成路径（品质图标 + 已合成/+N金）
	if it.has("requires"):
		if y + fs14 > body_top and y + fs14 < body_bot:
			_text(Vector2(dx, y + fs14), "合成路径", fs14, Color(0.78, 0.86, 1.0))
		y += fs14 * 1.5
		var icon := 40.0
		var x := dx
		var row_y := y
		for rid in it["requires"]:
			var sid := str(rid)
			var ritem: Dictionary = ItemDatabase.get_item(sid)
			var rhas := _slot_of(sid) >= 0
			var ltxt := "已合成" if rhas else "+%d金" % int(ritem.get("cost", 0))
			var lw := _f.get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs12).x
			var ew := icon + 4.0 + lw
			if x > dx and x + ew > dx + dw - 8.0:
				x = dx
				row_y += icon + 6.0
			if row_y + icon > body_top and row_y < body_bot:
				var irect := Rect2(x, row_y, icon, icon)
				_draw_item_icon(irect, sid)
				if not rhas:
					_box(irect, Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 0)
				_text(Vector2(x + icon + 4.0, row_y + icon * 0.5 + fs12 * 0.36), ltxt, fs12,
					Color(0.45, 1.0, 0.5) if rhas else Color(1.0, 0.5, 0.42))
			x += ew + 14.0
		y = row_y + icon + 6.0
		if ItemDatabase.can_build(_sel, _equip):
			if y + fs13 > body_top and y + fs13 < body_bot:
				_text(Vector2(dx, y + fs13), "可立即合成（仍需补 %d 金）" % ItemDatabase.get_synthesis_cost(_sel, _equip),
					fs13, Color(0.45, 1.0, 0.5))
			y += fs13 * 1.5

	# 装备属性：图标 + 数值 chip（物理橙 / 法术紫 / 其余绿），自动换行
	var attrs: Array = []
	for a in ATTR_ROWS:
		var key := str(a[0])
		if it.has(key) and int(it[key]) != 0:
			attrs.append([str(a[1]), int(it[key]), str(a[2]) if a.size() > 2 else "", _attr_tint(key), key])
	if not attrs.is_empty():
		if y > body_top and y < body_bot:
			_sep(dx, dx + dw - 8.0, y)
		y += 10.0
		if y + fs14 > body_top and y + fs14 < body_bot:
			_text(Vector2(dx, y + fs14), "装备属性", fs14, Color(0.78, 0.86, 1.0))
		y += fs14 * 1.5
		var ax := dx
		for a in attrs:
			var txt := "+%d%s %s" % [int(a[1]), str(a[2]), str(a[0])]
			var tw := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs13).x
			var cw := 20.0 + 4.0 + tw
			if ax > dx and ax + cw > dx + dw - 8.0:
				ax = dx
				y += 24.0
			if y + 20.0 > body_top and y < body_bot:
				var tint: Color = a[3]
				_box(Rect2(ax, y + 1.0, 18.0, 18.0), Color(tint.r, tint.g, tint.b, 0.18), tint, 1, 4)
				_text_c(ax + 9.0, y + 10.0 + 9.0 * rs * 0.36, _attr_glyph(str(a[4])), 9.0 * rs, tint.lightened(0.35))
				_text(Vector2(ax + 23.0, y + 15.0), txt, fs13, tint.lightened(0.35))
			ax += cw + 18.0
		y += 26.0

	# 被动 / 主动（黄色，超宽折行收进详情列宽）
	for pk in ["passive", "active"]:
		if it.has(pk):
			if y > body_top and y < body_bot:
				_sep(dx, dx + dw - 8.0, y)
			y += 10.0
			var lines := _wrap("[%s] %s" % [("被动" if pk == "passive" else "主动"), str(it[pk])], dw - 12.0, fs13)
			for ln: String in lines:
				if y + fs13 > body_top and y + fs13 < body_bot:
					_text(Vector2(dx, y + fs13), ln, fs13, Color.YELLOW)
				y += fs13 * 1.35
			y += 4.0

	# 总装备加成：优先 host 烘焙 bs；缺失时按已购件累加近似
	if y > body_top and y < body_bot:
		_sep(dx, dx + dw - 8.0, y)
	y += 10.0
	if y + fs15 > body_top and y + fs15 < body_bot:
		_text(Vector2(dx, y + fs15), "── 总装备加成 ──", fs15, Color.WHITE)
	y += fs15 + 10.0
	var fs_tot := 12.0 * rs
	if not _bs.is_empty():
		for row in _bs:
			if not (row is Array) or row.is_empty():
				continue
			if y + fs_tot > body_top and y < body_bot:
				var txt := str(row[0])
				var tc := Color.LIGHT_GREEN
				if row.size() > 1 and row[1] is Color:
					tc = row[1]
				_text(Vector2(dx, y), txt, fs_tot, tc)
			y += fs_tot * 1.35 + 2.0
	else:
		var tot := _bonus_totals()
		for tr in TOTAL_ROWS:
			var k := str(tr[1])
			var val := float(tot.get(k, 0.0))
			if absf(val) < 0.01:
				continue
			if y + fs_tot > body_top and y < body_bot:
				var nm := str(tr[0])
				var tc2 := Color.LIGHT_GREEN
				if nm in ["攻击力", "护甲", "物穿", "物理吸血", "暴击率", "暴击伤害"]:
					tc2 = Color.ORANGE
				elif nm in ["法术强度", "魔抗", "法穿", "法术吸血"]:
					tc2 = Color(0.7, 0.4, 1.0)
				_text(Vector2(dx, y), "  %s: +%d" % [nm, int(round(val))], fs_tot, tc2)
			y += fs_tot * 1.35 + 2.0

	# 联机补充：B 推荐 + 出装路线（数据来自 feed(rec) 与 ItemDatabase，可随详情体滚动）
	var nxt := _rec
	if nxt == "":
		nxt = _plan_next(_plan())
	if nxt != "":
		if y > body_top and y < body_bot:
			_sep(dx, dx + dw - 8.0, y)
		y += 14.0
		if y + 13.0 * rs > body_top and y + 13.0 * rs < body_bot:
			_text(Vector2(dx, y + 13.0 * rs), "推荐出装：", 13.0 * rs, Color(1.0, 0.92, 0.4))
		y += 13.0 * rs * 1.6
		y = _draw_plan_line(dx, y, dw - 12.0, rs, body_bot)
		var need := _need_cost(nxt)
		var rr := Rect2(dx, y, 430.0, 36.0)
		if rr.position.y >= body_top and rr.end.y <= body_bot:
			_hot.append({"r": rr, "k": "plannext", "a": nxt})
			var ok := _gold >= need
			_box(rr, Color(0.25, 0.4, 0.2, 0.95) if ok else Color(0.16, 0.17, 0.22, 0.95), Color(0.6, 1.0, 0.5, 0.9) if ok else Color(1, 1, 1, 0.18), 1, 6)
			var nm2 := str(ItemDatabase.get_item(nxt).get("name", nxt))
			var txt := "推荐: %s · %d金 · 点击购买 / B" % [nm2, need]
			_text_c(rr.position.x + rr.size.x * 0.5, rr.position.y + rr.size.y * 0.5 + 13.0 * rs * 0.36, txt, 13.0 * rs, Color(0.85, 1.0, 0.8) if ok else Color(1, 1, 1, 0.6))
		y += 40.0

	# 记录内容高，供滚轮 clamp（下一帧生效）
	_dview_h = maxf(0.0, body_bot - body_top)
	_dbody_h = maxf(0.0, y - body_top + _dscroll)
	_dscroll = clampf(_dscroll, 0.0, maxf(0.0, _dbody_h - _dview_h))

	# 固定头部（覆盖滚动体上沿）：物品图标 + 品级/类别 + 名称 + 总价/素材抵扣/实付
	draw_rect(Rect2(dx - 6.0, dy - 4.0, dw + 4.0, head_h + 4.0), Color(0, 0, 0, 0.92), true)
	UiKit.item_icon(self, Rect2(dx, dy + 12.0, 72.0, 72.0), tier, str(it.get("name", _sel)))
	var ix := dx + 88.0
	_text(Vector2(ix, dy + fs13 + 10.0), "[" + _tier_name(tier) + "]  " + _cat_of(_sel), fs13, tcol)
	_text(Vector2(ix, dy + fs13 + 10.0 + fs24 + 2.0), str(it.get("name", _sel)), fs24, Color.WHITE)
	var ptxt := "总价 %d 金" % cost
	if comp > 0:
		ptxt = "总价 %d 金  ·  素材抵扣 %d  ·  实付 %d 金" % [cost, comp, pay]
	_text(Vector2(ix, dy + fs13 + 10.0 + fs24 + 2.0 + fs15 + 4.0), ptxt, fs15, Color(1.0, 0.82, 0.3))

# 出装路线一行（已购绿 / 下一件金 / 其余白，超宽折行；bot=滚动体下沿裁剪）
func _draw_plan_line(x0: float, y0: float, max_w: float, rs: float, bot := 99999.0) -> float:
	var plan := _plan()
	var fs := 12.0 * rs
	if plan.is_empty():
		_text(Vector2(x0, y0 + fs), "暂无推荐方案", fs, Color(1, 1, 1, 0.45))
		return y0 + fs * 1.6
	var nxt := _rec
	if nxt == "":
		nxt = _plan_next(plan)
	var x := x0
	var y := y0
	for i in range(plan.size()):
		var id := str(plan[i])
		var nm := str(ItemDatabase.get_item(id).get("name", id))
		var col := Color(1, 1, 1, 0.85)
		if _owned_n(id) > 0:
			col = Color(0.5, 1.0, 0.58)
		elif id == nxt:
			col = Color(1.0, 0.88, 0.38)
		var w := _f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if x > x0 and x + w > x0 + max_w:
			x = x0
			y += fs * 1.4
		if y + fs <= bot:
			_text(Vector2(x, y + fs), nm, fs, col)
		x += w
		if i < plan.size() - 1:
			var arrow := " → "
			var aw := _f.get_string_size(arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if x > x0 and x + aw > x0 + max_w:
				x = x0
				y += fs * 1.4
			if y + fs <= bot:
				_text(Vector2(x, y + fs), arrow, fs, Color(1, 1, 1, 0.3))
			x += aw
	return y + fs * 1.8

# —— 出装推进（与主机 UI_Manager._get_best_recommended_item 同源：plan 确定性角色方案，逐步购齐）——
func _plan() -> Array:
	# host 用 hero.role 调用（命中 role_pools 兜底，不随机）；客户端按 hero_name 反查同一 role
	var role: String = str(HeroPickData.HERO_ROLE.get(_hero_name, "战士"))
	if _plan_for != role or _plan_cache.is_empty():
		_plan_for = role
		var p = ItemDatabase.get_recommended_items(role)
		_plan_cache = p if p is Array else []
	return _plan_cache

func _owned_n(id: String) -> int:
	var n := 0
	for o in _equip:
		if str(o) == id:
			n += 1
	return n

# 最深一层缺失的素材件（主机 _find_missing_basic 镜像）
func _missing_basic(target_id: String) -> String:
	var target := ItemDatabase.get_item(target_id)
	if target.is_empty() or not target.has("requires"):
		return target_id
	for req_id: String in target.get("requires", []):
		var need := 0
		for r in target["requires"]:
			if str(r) == req_id:
				need += 1
		if _owned_n(req_id) < need:
			return _missing_basic(req_id)
	return target_id

# 下一件（推荐买的第一个：素材齐→合成大件；否则→最底层素材；槽满→补差价合成/升级已有件）
func _plan_next(plan: Array) -> String:
	if _equip.size() >= 6:
		# 1. 推荐列表里能补差价合成的（至少持有一件素材）
		for id in plan:
			if _owned_n(id) > 0:
				continue
			for req_id: String in ItemDatabase.get_item(id).get("requires", []):
				if _owned_n(req_id) > 0:
					return id
		# 2. 升级已有低级装（2 阶→合大件 / 1 阶→先合中阶）
		for owned_id in _equip:
			var ot := int(ItemDatabase.get_item(str(owned_id)).get("tier", 1))
			if ot >= 3:
				continue
			if ot == 2:
				for rid in plan:
					if _owned_n(rid) > 0:
						continue
					if str(owned_id) in ItemDatabase.get_item(rid).get("requires", []):
						return rid
			else:
				for rid in plan:
					if _owned_n(rid) > 0:
						continue
					for mid_id: String in ItemDatabase.get_item(rid).get("requires", []):
						if _owned_n(mid_id) > 0:
							continue
						if str(owned_id) in ItemDatabase.get_item(mid_id).get("requires", []):
							return mid_id
		# 3. 兜底第一个未拥有
		for id in plan:
			if _owned_n(id) == 0:
				return id
		return str(plan[0]) if not plan.is_empty() else ""
	# 未满槽：素材齐→合成大件；否则最底层缺失件
	for id in plan:
		if _owned_n(id) > 0:
			continue
		if ItemDatabase.can_build(id, _equip):
			return id
	for id in plan:
		if _owned_n(id) > 0:
			continue
		var miss := _missing_basic(id)
		if miss != "":
			return miss
	return ""

# 现在补多少钱能到手（总价 - 已拥有素材折价）
func _need_cost(id: String) -> int:
	var it := ItemDatabase.get_item(id)
	if it.is_empty():
		return 0
	var cost := int(it.get("cost", 0))
	for req_id: String in it.get("requires", []):
		var need := 0
		for r in it["requires"]:
			if str(r) == req_id:
				need += 1
		var own := mini(_owned_n(req_id), need)
		if own > 0:
			cost -= own * int(ItemDatabase.get_item(req_id).get("cost", 0))
	return maxi(cost, 0)

# ---------- 输入 ----------

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo):
		return
	match (ev as InputEventKey).keycode:
		KEY_O:
			toggle()
		KEY_B:
			if visible:
				quick_buy()
		KEY_ESCAPE:
			if visible:
				hide_panel()

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# 滚轮：指针在详情列滚详情体，否则滚装备卡（host ScrollContainer 等效）
		if visible:
			var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			var pr := _panel_rect()
			var ddx := pr.position.x + _pw() * DETAIL_L
			if pr.has_point(mb.position) and mb.position.x >= ddx:
				_dscroll = clampf(_dscroll + dir * 48.0, 0.0, maxf(0.0, _dbody_h - _dview_h))
			else:
				_scroll = maxi(_scroll + int(dir), 0)
			queue_redraw()
			accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p := mb.position
	var panel := _panel_rect()
	if not panel.has_point(p):
		# host：点遮罩（抽屉外）关闭
		hide_panel()
		return
	# 后绘制者在上，命中从 _hot 末尾向前找（与绘制层序一致）
	var hit: Dictionary = {}
	for i in range(_hot.size() - 1, -1, -1):
		var hr: Rect2 = _hot[i]["r"]
		if hr.has_point(p):
			hit = _hot[i]
			break
	if hit.is_empty():
		return
	match str(hit["k"]):
		"close":
			hide_panel()
		"tab":
			var nt := int(hit["a"])
			if nt != _tab:
				_tab = nt
				_scroll = 0
				_dscroll = 0.0
				_sel = ""   # 交给 _draw_grid 回退第一件可买
				queue_redraw()
		"item":
			# host：点装备卡 = 选中并刷新右侧详情（购买/出售在详情按钮上）
			_sel = str(hit["a"])
			_dscroll = 0.0
			queue_redraw()
		"owned":
			var s := int(hit["a"])
			if s >= 0 and s < _equip.size():
				_sel = str(_equip[s])
				_dscroll = 0.0
				queue_redraw()
		"buy":
			var id := str(hit["a"])
			if _afford(id) and (_equip.size() < 6 or _has_component(id)):
				buy(id)
			queue_redraw()
		"sell":
			sell_slot(int(hit["a"]))
			queue_redraw()
		"plannext":
			# 出装路线「推荐购买」：按 host 同款 B 决策购买，host 侧再校验合成/金币
			var pn := str(hit["a"])
			if pn != "" and _gold >= _need_cost(pn):
				buy(pn)
			queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

# 品质色装备图标（与 host UiKit.item_icon 同源）
func _draw_item_icon(r: Rect2, id: String) -> void:
	var it: Dictionary = ItemDatabase.get_item(str(id))
	UiKit.item_icon(self, r, int(it.get("tier", 1)), str(it.get("name", id)))

# 固定底部操作条：购买（金）/ 还差 N 金（红，禁用）/ 已拥有 + 出售
func _draw_action_bar(panel: Rect2, rs: float) -> void:
	if _sel == "":
		return
	var it: Dictionary = ItemDatabase.get_item(_sel)
	if it.is_empty():
		return
	var slot := _slot_of(_sel)
	var owned := slot >= 0
	var tier := int(it.get("tier", 1))
	var dx := panel.position.x + _pw() * DETAIL_L
	var dw := _pw() * (DETAIL_R - DETAIL_L)
	var bh := 46.0 * rs
	var by := panel.end.y - 42.0 - bh
	var can_more := not owned or tier < 3
	var pay := _need_cost(_sel)
	var br := Rect2(dx, by, dw * (0.62 if owned else 1.0), bh)
	if not can_more:
		_box(br, Color(0.20, 0.22, 0.28, 0.95), Color(1, 1, 1, 0.14), 1, 8)
		_text_c(br.position.x + br.size.x * 0.5, br.position.y + bh * 0.5 + 15.0 * rs * 0.36, "已拥有", 15.0 * rs, Color(0.8, 0.84, 0.9))
	elif _gold >= pay and (_equip.size() < 6 or _has_component(_sel)):
		_hot.append({"r": br, "k": "buy", "a": _sel})
		_box(br, Color(0.88, 0.72, 0.16, 0.98), Color(1.0, 0.9, 0.45, 0.95), 1, 8)
		_text_c(br.position.x + br.size.x * 0.5, br.position.y + bh * 0.5 + 15.0 * rs * 0.36, "购买 %d 金" % pay, 15.0 * rs, Color(0.08, 0.07, 0.04))
	else:
		_box(br, Color(0.42, 0.20, 0.20, 0.95), Color(1.0, 0.45, 0.4, 0.7), 1, 8)
		var msg := ("还差 %d 金" % maxi(pay - _gold, 0)) if _gold < pay else "装备栏已满"
		_text_c(br.position.x + br.size.x * 0.5, br.position.y + bh * 0.5 + 14.0 * rs * 0.36, msg, 14.0 * rs, Color(1.0, 0.6, 0.55))
	if owned:
		var sr := Rect2(dx + dw * 0.64, by, dw * 0.36, bh)
		_hot.append({"r": sr, "k": "sell", "a": slot})
		_box(sr, Color(0.20, 0.30, 0.44, 0.95), Color(0.55, 0.75, 0.95, 0.8), 1, 8)
		_text_c(sr.position.x + sr.size.x * 0.5, sr.position.y + bh * 0.5 + 14.0 * rs * 0.36, "出售 +%d" % int(int(it.get("cost", 0)) * 0.7), 14.0 * rs, Color(0.75, 0.88, 1.0))

