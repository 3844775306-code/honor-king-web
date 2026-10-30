class_name LoadingScreen
extends CanvasLayer
## 对局加载界面（仿王者荣耀）：上下两排、每人一张动态皮肤卡（3D 立绘 + 光扫），
## 卡片底部显示玩家称号 / 英雄名 / 皮肤名；中央 VS + 进度条 + 百分比 + 提示。
## 用法：
##   var ld := LoadingScreen.new()
##   ld.setup([{name="吕布", role="战士", team=0}, ...], "对局加载中", "王者峡谷 · 5v5")
##   add_child(ld)
## setup 也可在 add_child 之后调用（会重建卡片）。
## 进度走满后淡出，发出 finished 信号并自动 queue_free。

signal finished

const ROLE_COLORS := {
	"战士": Color(0.85, 0.3, 0.2),
	"法师": Color(0.3, 0.5, 1.0),
	"刺客": Color(0.6, 0.2, 0.9),
	"射手": Color(0.9, 0.55, 0.1),
	"辅助": Color(0.1, 0.8, 0.65),
	"坦克": Color(0.45, 0.6, 0.75),
}

## 英雄皮肤名（立绘用模型为通用底模，皮肤名仅作展示文案）
const HERO_SKIN := {
	"吕布": "天魔缭乱", "亚瑟": "狮心王", "铠": "曙光守护者", "东皇太一": "龙渊", "夏侯惇": "不羁之风",
	"英睿": "铁血战将", "马超": "神威天将", "李白": "凤求凰", "兰陵王": "暗影猎手", "孙悟空": "齐天大圣",
	"不知火舞": "花蝶扇", "甄姬": "游园惊梦", "沈梦溪": "汐月物语", "安琪拉": "心灵骇客", "妲己": "女仆咖啡",
	"小乔": "缤纷独角兽", "王昭君": "凤凰于飞", "狄仁杰": "超时空战士", "孙尚香": "末日机甲",
	"马可波罗": "逐梦之星", "鲁班七号": "星空梦想", "后羿": "精灵王", "李元芳": "特工魅影",
	"元流之子": "源·初", "太乙真人": "饕餮", "张飞": "乱世虎臣", "大禹": "龙腾四海", "刘禅": "天才门将",
}

const RANKS := [
	"荣耀王者 · 50★", "最强王者 · 30★", "至尊星耀 · Ⅰ", "永恒钻石 · Ⅱ", "尊贵铂金 · Ⅰ",
]

var _heroes: Array = []
var _title := "对局加载中"
var _subtitle := ""
var _duration := 2.6
var _t := 0.0
var _fade := -1.0
var _tip_t := 0.0
var _root: Control
var _ally_row: HBoxContainer
var _foe_row: HBoxContainer
var _fill: ColorRect
var _bar_bg: Panel
var _pct: Label
var _tip: Label
var _title_lab: Label
var _sub_lab: Label
var _cards: Array = []
const TIPS := [
	"小提示：击败小兵与野怪可以获得金币，补刀最后一击金币更多",
	"小提示：回城时站在泉水范围内可以更快恢复状态",
	"小提示：与队友分享兵线金币时，人数越多每人分到的越少",
	"小提示：击杀暴君与主宰能为全队带来增益",
]


# 旋转加载环
class SpinRing extends Control:
	var t := 0.0
	var accent: Color = Color(1.0, 0.84, 0.35)

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := maxf(6.0, minf(size.x, size.y) * 0.5 - 4.0)
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 4.0, true)
		draw_arc(c, r, t * 3.0, t * 3.0 + 1.9, 24, accent, 4.0, true)


func _ready() -> void:
	layer = UiKit.LAYER_LOADING
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.016, 0.022, 0.042, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	UiKit.make_backdrop(_root, UiKit.C_TEAM0, 0.85)
	_root.move_child(bg, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	_root.add_child(margin)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 8)
	margin.add_child(center)

	_title_lab = _mk_label(_title, int(round(UiKit.FS_HUGE * 1.1 * UiKit.scale())), UiKit.C_GOLD)
	_title_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_title_lab)
	_sub_lab = _mk_label(_subtitle, int(round(UiKit.FS_SM * UiKit.scale())), UiKit.C_TEXT_DIM)
	_sub_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_sub_lab)

	_ally_row = HBoxContainer.new()
	_ally_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ally_row.add_theme_constant_override("separation", 20)
	center.add_child(_ally_row)

	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 40)
	mid.custom_minimum_size = Vector2(0, 190)
	center.add_child(mid)
	var vs := _mk_label("VS", int(round(UiKit.FS_HUGE * 1.9 * UiKit.scale())), UiKit.C_GOLD)
	mid.add_child(vs)
	var mid_col := VBoxContainer.new()
	mid_col.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_col.add_theme_constant_override("separation", 8)
	mid_col.custom_minimum_size = Vector2(520, 0)
	mid.add_child(mid_col)
	_bar_bg = Panel.new()
	_bar_bg.custom_minimum_size = Vector2(520, 18)
	_bar_bg.add_theme_stylebox_override("panel", UiKit.flat(1.0, 9, 1, UiKit.C_PANEL_EDGE, Color(0.03, 0.04, 0.07, 1.0), 0.0))
	mid_col.add_child(_bar_bg)
	_fill = ColorRect.new()
	_fill.color = UiKit.C_GOLD
	_fill.position = Vector2(2, 2)
	_fill.size = Vector2(0, 14)
	_bar_bg.add_child(_fill)
	_pct = _mk_label("0%", int(round(UiKit.FS_MD * UiKit.scale())), UiKit.C_TEXT)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid_col.add_child(_pct)
	var spin := SpinRing.new()
	spin.custom_minimum_size = Vector2(44, 44)
	spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid_col.add_child(spin)

	_foe_row = HBoxContainer.new()
	_foe_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_foe_row.add_theme_constant_override("separation", 20)
	center.add_child(_foe_row)

	_tip = _mk_label(TIPS[0], int(round(UiKit.FS_SM * UiKit.scale())), Color(1, 1, 1, 0.45))
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_tip)

	_rebuild_cards()
	set_process(true)


func _mk_label(text: String, fs: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	return l


func setup(heroes: Array, title := "对局加载中", subtitle := "", duration := 2.6) -> void:
	_heroes = heroes.duplicate()
	_title = title
	_subtitle = subtitle
	_duration = maxf(1.6, duration)
	if _title_lab != null:
		_title_lab.text = _title
		_sub_lab.text = _subtitle
		_rebuild_cards()


func _hero_entry(i: int, ally: bool) -> Dictionary:
	var team_id := 0 if ally else 1
	var pool: Array = []
	for h in _heroes:
		if h is Dictionary and int(h.get("team", team_id)) == team_id:
			pool.append(h)
	if pool.is_empty():
		var start := 0 if ally else maxi(0, _heroes.size() - 5)
		var end := mini(_heroes.size(), start + 5)
		for k in range(start, end):
			if _heroes[k] is Dictionary:
				pool.append(_heroes[k])
	if i < pool.size():
		return pool[i]
	return {}


func _rebuild_cards() -> void:
	if _ally_row == null:
		return
	for box in [_ally_row, _foe_row]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_cards.clear()
	for i in 5:
		_ally_row.add_child(_mk_card(_hero_entry(i, true), true, i))
	for i in 5:
		_foe_row.add_child(_mk_card(_hero_entry(i, false), false, i))


func _mk_card(entry: Dictionary, ally: bool, idx: int) -> Control:
	var team_color: Color = UiKit.C_TEAM0 if ally else UiKit.C_TEAM1
	var hero_name := str(entry.get("name", "—"))
	var role := str(entry.get("role", ""))
	var role_color: Color = ROLE_COLORS.get(role, team_color)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(452, 470)
	var csty := UiKit.skin_card(team_color, false, 0.90)
	csty.content_margin_left = 0
	csty.content_margin_right = 0
	csty.content_margin_top = 0
	csty.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", csty)
	var body := Control.new()
	body.custom_minimum_size = Vector2(452, 470)
	card.add_child(body)

	# ── 立绘区（3D 动态皮肤卡）─────────────────────────────────
	var art := Control.new()
	art.size = Vector2(452, 360)
	art.clip_contents = true
	body.add_child(art)
	if hero_name != "" and hero_name != "—":
		var pv := HeroPreview.new()
		pv.render_size = Vector2i(452, 360)
		pv.lightweight = true
		pv.size = Vector2(452, 360)
		pv.position = Vector2.ZERO
		art.add_child(pv)
		pv.set_accent(role_color)
		pv.set_hero(hero_name)
	else:
		var disc := Panel.new()
		disc.size = Vector2(140, 140)
		disc.position = Vector2(156, 110)
		disc.add_theme_stylebox_override("panel", UiKit.flat(1.0, 70, 2, role_color.lightened(0.25), role_color.darkened(0.5), 0.0))
		var q := _mk_label("?", int(round(UiKit.FS_HUGE * UiKit.scale())), UiKit.C_TEXT_DIM)
		q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		disc.add_child(q)
		art.add_child(disc)

	# 底部渐隐（立绘与信息条过渡）
	var fade_tex := GradientTexture2D.new()
	fade_tex.width = 8
	fade_tex.height = 96
	fade_tex.fill_from = Vector2(0, 0)
	fade_tex.fill_to = Vector2(0, 1)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.016, 0.022, 0.042, 0.0), Color(0.016, 0.022, 0.042, 0.94)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	fade_tex.gradient = grad
	var fade := TextureRect.new()
	fade.texture = fade_tex
	fade.position = Vector2(0, 264)
	fade.size = Vector2(452, 96)
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(fade)

	# 光扫（动态质感）
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.055)
	shine.size = Vector2(70, 620)
	shine.position = Vector2(-120, -60)
	shine.rotation = -0.34
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(shine)
	_cards.append({"card": card, "shine": shine, "idx": idx})

	# 左上角阵营标（我方/敌方）
	var badge := PanelContainer.new()
	badge.position = Vector2(10, 10)
	badge.add_theme_stylebox_override("panel", UiKit.skin_tag(team_color))
	var bl := _mk_label("我方" if ally else "敌方", int(round(UiKit.FS_XS * UiKit.scale())), team_color.lightened(0.45))
	badge.add_child(bl)
	body.add_child(badge)

	# 信息条：玩家称号 / 英雄名 / 皮肤名
	var info := PanelContainer.new()
	info.position = Vector2(0, 340)
	info.size = Vector2(452, 130)
	var isty := UiKit.flat(0.96, 0, 1, team_color.darkened(0.2), Color(0.035, 0.048, 0.078, 0.98), 0.0)
	info.add_theme_stylebox_override("panel", isty)
	var im := MarginContainer.new()
	im.add_theme_constant_override("margin_left", 16)
	im.add_theme_constant_override("margin_right", 16)
	im.add_theme_constant_override("margin_top", 8)
	im.add_theme_constant_override("margin_bottom", 8)
	info.add_child(im)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	im.add_child(vb)
	var rank_lab := _mk_label(_rank_for(hero_name, idx), int(round(UiKit.FS_XS * UiKit.scale())), UiKit.C_GOLD)
	rank_lab.add_theme_color_override("font_color", UiKit.C_GOLD.darkened(0.05))
	vb.add_child(rank_lab)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	vb.add_child(name_row)
	var nm := _mk_label(hero_name if hero_name != "" else "—", int(round(UiKit.FS_LG * UiKit.scale())), UiKit.C_GOLD)
	nm.add_theme_color_override("font_color", UiKit.C_GOLD)
	name_row.add_child(nm)
	var skin := _mk_label("「%s」" % _skin_for(hero_name), int(round(UiKit.FS_XS * UiKit.scale())), UiKit.C_TEXT_DIM)
	skin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(skin)
	var role_lab := _mk_label(role if role != "" else ("我方 %d 号位" % (idx + 1)), int(round(UiKit.FS_XS * UiKit.scale())), role_color.lightened(0.3))
	vb.add_child(role_lab)
	body.add_child(info)

	# 进场淡入（错峰）
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.05 * idx)
	tw.tween_property(card, "modulate:a", 1.0, 0.42)
	return card


func _rank_for(hero_name: String, idx: int) -> String:
	if hero_name == "" or hero_name == "—":
		return "未定级"
	return RANKS[absi(hash(hero_name + str(idx))) % RANKS.size()]


func _skin_for(hero_name: String) -> String:
	if hero_name == "" or hero_name == "—":
		return "—"
	return str(HERO_SKIN.get(hero_name, "经典皮肤"))


func _process(delta: float) -> void:
	_t += delta
	_tip_t += delta
	var p := clampf(_t / _duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - p, 1.6)
	if _fill != null:
		_fill.size = Vector2(maxf(0.0, (_bar_bg.size.x - 4.0) * eased), 14)
	if _pct != null:
		_pct.text = "%d%%" % int(round(eased * 100.0))
	if _tip != null and _tip_t > 1.6:
		_tip_t = 0.0
		_tip.text = TIPS[randi() % TIPS.size()]
	for c in _cards:
		var shine: ColorRect = c.get("shine")
		if shine == null or not is_instance_valid(shine):
			continue
		var i: int = int(c.get("idx", 0))
		var k := fmod(_t * 0.55 + i * 0.11, 1.0)
		shine.position = Vector2(lerpf(-180.0, 520.0, k), -60.0)
		shine.color.a = 0.045 * sin(k * PI)
	if _fade >= 0.0:
		_fade += delta
		_root.modulate.a = clampf(1.0 - _fade / 0.35, 0.0, 1.0)
		if _fade >= 0.35:
			finished.emit()
			queue_free()
	elif p >= 1.0:
		_fade = 0.0
