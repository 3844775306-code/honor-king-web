class_name ResultsPanel
extends CanvasLayer

const MatchResultScript = preload("res://scripts/core/MatchResult.gd")

# ==================== 常量 ====================
# 阵营/强调色统一取 UiKit 色板（保留原变量名，避免各处引用改动）
var BLUE_TEAM: Color = UiKit.C_TEAM0
var RED_TEAM: Color = UiKit.C_TEAM1
var GOLD_COLOR: Color = UiKit.C_GOLD
const ROW_H = 50  # 数据页每行高度（对齐用）

# ==================== 引用 ====================
var bm = null
## 数据模型（联机/回放用）：非空时优先于 bm，实现单机与联机/回放共用同一套结算 UI
var _model: Dictionary = {}
var all_heroes: Array = []
var team_player_heroes: Array = []
var team_enemy_heroes: Array = []
var current_tab: int = 0
var _rank_result: Dictionary = {}
var _self_is_mvp := false
var _gauges: Array = []

# ==================== Tab 控件 ====================
var tab_buttons: Array = []
var content_container: Control
var overview_panel: Control
var data_panel: Control
var replay_panel: Control

# ==================== 样式辅助 ====================
# 结算页沿用原 1.7 尺度（版面按此调过，改回 UiKit.scale 会整体缩小 20%）
func _ui_scale() -> float:
	return clampf(get_viewport().get_visible_rect().size.x / 2400.0, 1.0, 1.2) * 1.7

# 字号统一走 UiKit 档位（FS_XS..FS_HUGE）× 全局 scale
func _fs(tier: int) -> int:
	return int(round(tier * _ui_scale()))

func _apply_label_style(label: Label, font_size: int = 16, color: Color = UiKit.C_TEXT):
	label.add_theme_font_size_override("font_size", int(round(font_size * _ui_scale())))
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 1)

func _apply_panel_style(panel: Panel, alpha: float = 0.8):
	panel.add_theme_stylebox_override("panel",
		UiKit.flat(alpha, 0, 0, Color.TRANSPARENT, Color(0, 0, 0, alpha), 0.0))

# 统一按钮质感：三态走 UiKit.skin_button（投影/hover 辉光/pressed 下沉）
func _skin_btn(btn: Button, accent: Color, filled: bool, font_size: int, min_size: Vector2) -> void:
	btn.custom_minimum_size = min_size
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", _fs(font_size))
	btn.add_theme_color_override("font_color", Color(0.08, 0.05, 0.0) if filled else UiKit.C_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.0) if filled else Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.0) if filled else UiKit.C_TEXT_DIM)
	btn.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	btn.add_theme_constant_override("outline_size", 0)
	for st in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(st, UiKit.skin_button(st, accent, filled))

func _format_gold(g: int) -> String:
	if g >= 1000: return "%.1fk" % (g / 1000.0)
	return str(g)

# 把子控件填满父控件并留出四边内边距（Panel 自身不参与布局，手动锚定最可靠）
func _fill(node: Control, parent: Control, l: float = 0.0, t: float = 0.0, r: float = 0.0, b: float = 0.0) -> Control:
	parent.add_child(node)
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 1.0
	node.anchor_bottom = 1.0
	node.offset_left = l
	node.offset_top = t
	node.offset_right = -r
	node.offset_bottom = -b
	return node

func _box_style(bg: Color, border: Color, border_w: int = 0, radius: int = -1) -> StyleBoxFlat:
	var r := maxi(1, int(radius if radius >= 0 else 10 * _ui_scale()))
	return UiKit.flat(bg.a, r, border_w, border, bg, 0.0)

func _role_style(role: String) -> Array:
	match role:
		"刺客": return ["刺", Color(0.95, 0.4, 0.95)]
		"法师": return ["法", Color(0.45, 0.62, 1.0)]
		"射手": return ["射", Color(0.95, 0.55, 0.25)]
		"战士": return ["战", Color(0.98, 0.72, 0.3)]
		"辅助": return ["辅", Color(0.3, 0.92, 0.6)]
		_: return ["?", Color.WHITE]

func _tier_color(tier: int) -> Color:
	match tier:
		2: return Color(0.5, 0.95, 0.55)
		3: return Color(0.45, 0.7, 1.0)
		4: return Color(0.9, 0.5, 1.0)
		_: return Color(0.78, 0.78, 0.85)

# ==================== 初始化 ====================
## 单机入口：直接用 BattleManager
func setup(battle):
	_model = {}
	bm = battle
	process_mode = PROCESS_MODE_ALWAYS
	all_heroes.clear()
	team_player_heroes.clear()
	team_enemy_heroes.clear()
	for entity in get_tree().get_nodes_in_group("heroes"):
		if is_instance_valid(entity) and entity is Hero:
			all_heroes.append(entity)
			if Config.is_ally(entity.team):
				team_player_heroes.append(entity)
			else:
				team_enemy_heroes.append(entity)
		team_player_heroes.sort_custom(func(a, b): return a.total_gold_earned > b.total_gold_earned)
		team_enemy_heroes.sort_custom(func(a, b): return a.total_gold_earned > b.total_gold_earned)
		_prepare_rank()
		_create_ui()


## 联机/回放入口：传数据模型（heroes 可以是 Hero 或 HeroStatView）
## model: {heroes, hero, player_team, winner, game_time, rank_result, team_gold_diff_history, mode}
func setup_model(model: Dictionary) -> void:
	_model = model
	bm = null
	process_mode = PROCESS_MODE_ALWAYS
	all_heroes.clear()
	team_player_heroes.clear()
	team_enemy_heroes.clear()
	var pteam := int(model.get("player_team", Config.player_team))
	for h in (model.get("heroes", []) as Array):
		if h == null:
			continue
		all_heroes.append(h)
		if int(h.team) == pteam:
			team_player_heroes.append(h)
		else:
			team_enemy_heroes.append(h)
	team_player_heroes.sort_custom(func(a, b): return a.total_gold_earned > b.total_gold_earned)
	team_enemy_heroes.sort_custom(func(a, b): return a.total_gold_earned > b.total_gold_earned)
	_prepare_rank()
	_create_ui()


# 段位结算：优先用已算好的结果；没有才按 MatchResult 兜底（不重复加减星）
func _prepare_rank() -> void:
	var ph = _m_hero()
	var mp0 = _find_mvp(team_player_heroes)
	_self_is_mvp = mp0 != null and ph != null and mp0 == ph
	var rr = _m_rank_result()
	if rr is Dictionary and not (rr as Dictionary).is_empty():
		_rank_result = rr
	elif bool(_model.get("suppress_rank", false)):
		_rank_result = {}
	elif _rank_result.is_empty():
		var rating := _calculate_rating(ph) if ph != null else 0.0
		var medal := _medal_index(ph) if ph != null else -1
		var bonus := MatchResultScript.rank_bonus(medal, rating)
		_rank_result = RankSystem.apply_result(Config.is_ally(_m_winner()), _self_is_mvp, bonus)
		_rank_result["medal"] = medal
		_rank_result["medal_bonus"] = MatchResultScript.medal_bonus(medal)
		_rank_result["top_bonus"] = MatchResultScript.top_bonus(rating)


# —— 模型/单机取值统一入口 ——
func _m_hero():
	if not _model.is_empty():
		return _model.get("hero", null)
	return bm.hero if bm != null else null

func _m_winner() -> int:
	if not _model.is_empty():
		return int(_model.get("winner", -1))
	return int(bm.winner) if bm != null else -1

func _m_game_time() -> float:
	if not _model.is_empty():
		return float(_model.get("game_time", 0.0))
	return float(bm.game_time) if bm != null else 0.0

func _m_rank_result() -> Dictionary:
	if not _model.is_empty():
		var r = _model.get("rank_result", {})
		return r if r is Dictionary else {}
	return bm.rank_result if bm != null and bm.rank_result is Dictionary else {}

func _m_gold_hist() -> Array:
	if not _model.is_empty():
		var g = _model.get("team_gold_diff_history", [])
		return g if g is Array else []
	return bm.team_gold_diff_history if bm != null else []

func _create_ui():
	# 结算页独占最上层：盖住 HUD(layer 2)/PostFX(layer 1)，避免战斗控件压在结算内容上
	layer = UiKit.LAYER_RESULTS
	var is_win = Config.is_ally(_m_winner())
	var result_color = BLUE_TEAM if is_win else RED_TEAM

	# 全屏程序化背景（渐变+辉光+网格+粒子+暗角）+ 薄暗幕保证文字可读
	var bg_layer = Control.new()
	bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_layer)
	bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.make_backdrop(bg_layer, result_color, 0.8)
	var dim = Panel.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_theme_stylebox_override("panel",
		UiKit.flat(0.34, 0, 0, Color.TRANSPARENT, Color(0.02, 0.025, 0.045, 0.34), 0.0))
	bg_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 主布局：铺满安全边距 32
	var main_vbox = VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.offset_top = 24
	main_vbox.offset_bottom = -24
	main_vbox.offset_left = 24
	main_vbox.offset_right = -24
	add_child(main_vbox)

	# ---------------- 顶部标题区 ----------------
	var top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	main_vbox.add_child(top_bar)

	# 胜负徽章
	var badge = RoleDisc.new()
	badge.glyph = "胜" if is_win else "负"
	badge.ring = result_color
	badge.glyph_color = result_color
	badge.custom_minimum_size = Vector2(70, 70)
	badge.glyph_scale = 0.62
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_bar.add_child(badge)

	# 标题 + 副标题
	var title_col = VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 2)
	var title = Label.new()
	title.text = "对局胜利" if is_win else "对局失败"
	_apply_label_style(title, UiKit.FS_HUGE, result_color)
	title_col.add_child(title)
	var sub = Label.new()
	var tk_p = _team_kills(team_player_heroes)
	var tk_e = _team_kills(team_enemy_heroes)
	sub.text = "时长 %02d:%02d  ·  我方击杀 %d : %d  ·  本场总经济 %s" % [
		int(_m_game_time()) / 60, int(_m_game_time()) % 60,
		tk_p, tk_e, _format_gold(_team_gold(team_player_heroes) + _team_gold(team_enemy_heroes))
	]
	_apply_label_style(sub, UiKit.FS_SM, UiKit.C_TEXT_DIM)
	title_col.add_child(sub)
	top_bar.add_child(title_col)

	# 右侧按钮区
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var back_btn = Button.new()
	back_btn.text = "返回大厅"
	_skin_btn(back_btn, UiKit.C_PANEL_EDGE, false, UiKit.FS_MD, Vector2(176, 66))
	back_btn.pressed.connect(_on_back_lobby)
	top_bar.add_child(back_btn)

	var play_again_btn = Button.new()
	play_again_btn.text = "再来一局"
	_skin_btn(play_again_btn, GOLD_COLOR, true, UiKit.FS_MD, Vector2(196, 66))
	play_again_btn.pressed.connect(_on_play_again)
	top_bar.add_child(play_again_btn)

	var return_btn = Button.new()
	return_btn.text = "退出游戏"
	_skin_btn(return_btn, UiKit.C_PANEL_EDGE, false, UiKit.FS_MD, Vector2(176, 66))
	return_btn.pressed.connect(_on_return)
	top_bar.add_child(return_btn)

	# ---------------- Tab 按钮行：居中但整体拉满，三个 tab 等分 ----------------
	main_vbox.add_child(_build_reward_band())

	var tab_bar = HBoxContainer.new()
	tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_bar.add_theme_constant_override("separation", 16)
	tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tab_names = ["总览", "数据", "复盘"]
	for i in range(tab_names.size()):
		var btn = Button.new()
		btn.text = tab_names[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_skin_btn(btn, GOLD_COLOR, false, UiKit.FS_MD, Vector2(180, 64))
		btn.pressed.connect(_on_tab_clicked.bind(i))
		tab_bar.add_child(btn)
		tab_buttons.append(btn)

	main_vbox.add_child(tab_bar)

	# 内容区
	content_container = Control.new()
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_container)

	_create_overview_tab()
	_create_data_tab()
	_create_replay_tab()

	_switch_tab(0)

# ==================== Tab 切换 ====================
func _on_tab_clicked(index: int):
	_switch_tab(index)

func _switch_tab(index: int):
	current_tab = index
	for i in range(tab_buttons.size()):
		var btn: Button = tab_buttons[i]
		if i == index:
			btn.add_theme_color_override("font_color", Color(0.08, 0.05, 0.0))
			btn.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.0))
			btn.add_theme_color_override("font_pressed_color", Color(0.08, 0.05, 0.0))
			for st in ["normal", "hover", "pressed"]:
				btn.add_theme_stylebox_override(st, UiKit.skin_button(st, GOLD_COLOR, true))
		else:
			btn.add_theme_color_override("font_color", UiKit.C_TEXT)
			btn.add_theme_color_override("font_hover_color", Color.WHITE)
			btn.add_theme_color_override("font_pressed_color", UiKit.C_TEXT_DIM)
			for st in ["normal", "hover", "pressed"]:
				btn.add_theme_stylebox_override(st, UiKit.skin_button(st, UiKit.C_PANEL_EDGE, false))

	overview_panel.visible = (index == 0)
	data_panel.visible = (index == 1)
	replay_panel.visible = (index == 2)

func _on_play_again():
	queue_free()
	get_tree().paused = false
	# 延迟到下一帧重载场景，确保当前帧所有 queue_free 完成
	get_tree().reload_current_scene.call_deferred()

func _on_return():
	queue_free()
	get_tree().quit()

## 返回大厅（主菜单）：解除暂停后切换场景
func _on_back_lobby():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

# ==================== 小队汇总 ====================
func _team_kills(heroes: Array) -> int:
	var k = 0
	for h in heroes:
		if h != null: k += h.kills
	return k

func _team_gold(heroes: Array) -> int:
	var g = 0
	for h in heroes:
		if h != null: g += h.total_gold_earned
	return g

# ==================== Tab 1: 总览（我方 | 中央 | 敌方）====================
func _create_overview_tab():
	overview_panel = Control.new()
	overview_panel.anchor_right = 1.0; overview_panel.anchor_bottom = 1.0
	content_container.add_child(overview_panel)

	var scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	overview_panel.add_child(scroll)

	# 内容不足一屏时垂直居中，超高时从顶部开始（避免首行卡片被切）
	var vwrap = VBoxContainer.new()
	vwrap.alignment = BoxContainer.ALIGNMENT_BEGIN
	vwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vwrap)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vwrap.add_child(hbox)

	var mvp_player = _find_mvp(team_player_heroes)
	var mvp_enemy = _find_mvp(team_enemy_heroes)

	# ---- 我方列（占满左半区，卡片随之横向拉伸）----
	var blue_col = VBoxContainer.new()
	blue_col.add_theme_constant_override("separation", 6)
	blue_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blue_col.add_child(_make_team_header("我方", BLUE_TEAM, team_player_heroes, false))
	for hero in team_player_heroes:
		blue_col.add_child(_create_hero_card(hero, hero == mvp_player, false))
	hbox.add_child(blue_col)

	# ---- 中央 VS 列 ----
	hbox.add_child(_build_vs_column(mvp_player, mvp_enemy))

	# ---- 敌方列 ----
	var red_col = VBoxContainer.new()
	red_col.add_theme_constant_override("separation", 6)
	red_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_col.add_child(_make_team_header("敌方", RED_TEAM, team_enemy_heroes, true))
	for hero in team_enemy_heroes:
		red_col.add_child(_create_hero_card(hero, hero == mvp_enemy, true))
	hbox.add_child(red_col)

func _make_team_header(text: String, color: Color, heroes: Array, is_enemy: bool) -> Control:
	var strip = Panel.new()
	strip.custom_minimum_size = Vector2(480, 60)
	var st = _box_style(
		Color(0.08, 0.13, 0.28, 0.85) if not is_enemy else Color(0.28, 0.08, 0.08, 0.85),
		color.darkened(0.1), 1, 10)
	strip.add_theme_stylebox_override("panel", st)

	var hb = _fill(HBoxContainer.new(), strip, 16, 0, 16, 0)
	var dot = Panel.new()
	dot.custom_minimum_size = Vector2(18, 18)
	dot.add_theme_stylebox_override("panel", _box_style(color, Color.WHITE, 0, 7))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(dot)

	var title_lbl = Label.new()
	title_lbl.text = text
	title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(title_lbl, UiKit.FS_LG, UiKit.C_TEXT)
	hb.add_child(title_lbl)

	var kills_lbl = Label.new()
	kills_lbl.text = "总击杀 %d" % _team_kills(heroes)
	kills_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(kills_lbl, UiKit.FS_XS, color.lightened(0.3))
	hb.add_child(kills_lbl)

	var gsp = Control.new()
	gsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(gsp)

	var eco_lbl = Label.new()
	eco_lbl.text = "团队经济 %s" % _format_gold(_team_gold(heroes))
	eco_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(eco_lbl, UiKit.FS_XS, GOLD_COLOR)
	hb.add_child(eco_lbl)

	return strip

# ---- 中央 VS 列 ----
func _build_vs_column(mvp_player, mvp_enemy) -> Control:
	var col = VBoxContainer.new()
	col.custom_minimum_size = Vector2(350, 0)
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var is_win = Config.is_ally(_m_winner())
	var top_sp = Control.new(); top_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(top_sp)

	# VS 徽章
	var badge = RoleDisc.new()
	badge.glyph = "VS"
	badge.ring = GOLD_COLOR if is_win else Color(0.6, 0.65, 0.75)
	badge.glyph_color = GOLD_COLOR if is_win else Color.WHITE
	badge.custom_minimum_size = Vector2(120, 120)
	badge.glyph_scale = 0.5
	badge.draw_ring_width = 4.0
	var bw = HBoxContainer.new(); bw.alignment = BoxContainer.ALIGNMENT_CENTER
	bw.add_child(badge)
	col.add_child(bw)

	# 击杀比分
	var score_row = HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 14)
	var tk_p = _team_kills(team_player_heroes)
	var tk_e = _team_kills(team_enemy_heroes)
	var sc_blue = Label.new(); sc_blue.text = str(tk_p)
	sc_blue.custom_minimum_size = Vector2(96, 0)
	sc_blue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_label_style(sc_blue, UiKit.FS_HUGE, BLUE_TEAM)
	score_row.add_child(sc_blue)
	var colon = Label.new(); colon.text = ":"; _apply_label_style(colon, UiKit.FS_HUGE, Color(0.6, 0.65, 0.75))
	score_row.add_child(colon)
	var sc_red = Label.new(); sc_red.text = str(tk_e)
	sc_red.custom_minimum_size = Vector2(96, 0)
	sc_red.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_label_style(sc_red, UiKit.FS_HUGE, RED_TEAM)
	score_row.add_child(sc_red)
	col.add_child(score_row)

	var v_tip = Label.new()
	v_tip.text = "小队击杀比" if mvp_player == null or mvp_enemy == null else ("我方略占上风" if tk_p >= tk_e else "敌方暂时领先")
	v_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(v_tip, UiKit.FS_XS, Color(0.65, 0.7, 0.8))
	col.add_child(v_tip)

	var mv_rule = Panel.new()
	mv_rule.custom_minimum_size = Vector2(300, 3)
	var rv = _box_style(Color(1, 1, 1, 0.12), Color.TRANSPARENT, 0, 1)
	mv_rule.add_theme_stylebox_override("panel", rv)
	var rw = HBoxContainer.new(); rw.alignment = BoxContainer.ALIGNMENT_CENTER
	rw.add_child(mv_rule)
	col.add_child(rw)

	# 双方 MVP
	var mv_title = Label.new()
	mv_title.text = "MVP"
	mv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(mv_title, UiKit.FS_MD, GOLD_COLOR)
	col.add_child(mv_title)

	var mv_col = VBoxContainer.new()
	mv_col.alignment = BoxContainer.ALIGNMENT_CENTER
	mv_col.add_theme_constant_override("separation", 8)
	mv_col.add_child(_create_mvp_mini(mvp_player, false, 300))
	mv_col.add_child(_create_mvp_mini(mvp_enemy, true, 300))
	col.add_child(mv_col)

	var bot_sp = Control.new(); bot_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(bot_sp)
	return col

func _create_mvp_mini(mvp, is_enemy: bool, wide: int = 190) -> Control:
	var box = Panel.new()
	box.custom_minimum_size = Vector2(wide, int(52 * _ui_scale()))
	var team_color = RED_TEAM if is_enemy else BLUE_TEAM
	var style = _box_style(
		Color(0.05, 0.1, 0.22, 0.9) if not is_enemy else Color(0.24, 0.06, 0.06, 0.9),
		team_color.darkened(0.15), 1, 10)
	if mvp == null:
		style.bg_color = Color(0.1, 0.11, 0.16, 0.9)
	style.border_width_top = 2
	style.border_color = GOLD_COLOR
	box.add_theme_stylebox_override("panel", style)

	if mvp == null:
		var nl = _fill(Label.new(), box, 8, 0, 8, 0)
		nl.text = "无数据"
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_apply_label_style(nl, UiKit.FS_XS, Color.DIM_GRAY)
		return box

	var hb = _fill(HBoxContainer.new(), box, 10, 0, 10, 0)
	var face = HeroFace.new()
	face.custom_minimum_size = Vector2(54, 54)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.hero_name = str(mvp.display_name)
	face.ring = team_color
	hb.add_child(face)

	var vcol = VBoxContainer.new()
	vcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vcol.alignment = BoxContainer.ALIGNMENT_CENTER
	vcol.add_theme_constant_override("separation", 2)
	var nrow = HBoxContainer.new()
	var nm = Label.new()
	nm.text = mvp.display_name
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_label_style(nm, UiKit.FS_SM, UiKit.C_TEXT)
	nrow.add_child(nm)
	var st = Label.new()
	st.text = "%.1f分" % _calculate_rating(mvp)
	_apply_label_style(st, UiKit.FS_SM, GOLD_COLOR)
	nrow.add_child(st)
	vcol.add_child(nrow)
	var info = Label.new()
	info.text = "%s · Lv.%d" % [mvp.role, mvp.level]
	_apply_label_style(info, UiKit.FS_XS, Color(0.7, 0.75, 0.85))
	vcol.add_child(info)
	var mi2 := _medal_index(mvp)
	if mi2 >= 0:
		var mrow = HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 4)
		mrow.add_child(_medal_chip(mi2))
		vcol.add_child(mrow)
	hb.add_child(vcol)
	return box

# ---- 英雄卡片 ----
func _create_hero_card(hero, is_mvp: bool, is_enemy: bool) -> Panel:
	var team_color = RED_TEAM if is_enemy else BLUE_TEAM
	var card = Panel.new()
	# 高度随整体字号缩放；136 基准保证三行（头像/KDA/装备）都完整落在卡片内
	card.custom_minimum_size = Vector2(480, int(136 * _ui_scale()))

	var style = _box_style(
		Color(0.05, 0.08, 0.16, 0.72) if not is_enemy else Color(0.2, 0.05, 0.06, 0.72),
		team_color.darkened(0.2), 1, 10)
	style.border_width_left = 3
	if is_mvp:
		style.border_width_top = 2
		style.border_color = GOLD_COLOR
	card.add_theme_stylebox_override("panel", style)

	var inner = VBoxContainer.new()
	inner = _fill(inner, card, 18, 12, 18, 12)
	inner.add_theme_constant_override("separation", 7)

	# ---- 第一行：角色圆盘 + 信息 + 评分 ----
	var row1 = HBoxContainer.new()
	# ---- 第一行：英雄头像 + 信息 + 评分 ----

	var face = HeroFace.new()
	face.custom_minimum_size = Vector2(54, 54)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.hero_name = str(hero.display_name)
	face.ring = team_color
	face.dead = hero.health <= 0.0
	row1.add_child(face)

	var info_col = VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_col.add_theme_constant_override("separation", 3)

	var nm_row = HBoxContainer.new()
	nm_row.add_theme_constant_override("separation", 8)
	var name_lbl = Label.new()
	name_lbl.text = hero.display_name
	_apply_label_style(name_lbl, UiKit.FS_MD, GOLD_COLOR if is_mvp else UiKit.C_TEXT)
	nm_row.add_child(name_lbl)
	if is_mvp:
		nm_row.add_child(_tag_label("MVP", GOLD_COLOR, Color(0.15, 0.1, 0.0)))
	var who_mark = ""
	if hero == _m_hero():
		who_mark = "玩家"
	elif hero.is_ai:
		who_mark = "AI"
	if who_mark != "":
		if who_mark == "玩家":
			nm_row.add_child(_tag_label(who_mark, Color(0.12, 0.42, 0.8, 0.95), Color(0.92, 0.98, 1.0), 0, true))
		else:
			nm_row.add_child(_tag_label(who_mark, Color(0.32, 0.35, 0.44, 0.95), Color(0.88, 0.9, 0.95), 0, true))
	var role_lbl = Label.new()
	role_lbl.text = "%s  ·  Lv.%d" % [hero.role, hero.level]
	role_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(role_lbl, UiKit.FS_XS, Color(0.68, 0.74, 0.85))
	nm_row.add_child(role_lbl)
	info_col.add_child(nm_row)

	var kda_line = Label.new()
	var kd = float(hero.kills + hero.assists) / max(1.0, float(hero.deaths))
	kda_line.text = "KDA %.2f" % kd if kd < 10 else "KDA %.1f" % kd
	_apply_label_style(kda_line, UiKit.FS_XS, Color(0.45, 0.95, 0.6))
	info_col.add_child(kda_line)

	row1.add_child(info_col)

	# 评分块
	var score = _calculate_rating(hero)
	var score_col = VBoxContainer.new()
	score_col.custom_minimum_size = Vector2(122, 0)
	score_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_col.add_theme_constant_override("separation", 2)
	var score_num = Label.new()
	score_num.text = "%.1f" % score
	score_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(score_num, UiKit.FS_XL, GOLD_COLOR)
	score_col.add_child(score_num)
	var score_tag = Label.new()
	score_tag.text = _rating_grade(score)
	score_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(score_tag, UiKit.FS_XS, _rating_grade_color(score))
	score_col.add_child(score_tag)
	# 奖牌放进名字行：原来叠在评分块下方会把第三行装备栏挤出卡片
	var mi := _medal_index(hero)
	if mi >= 0:
		var medal_chip = _medal_chip(mi)
		medal_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nm_row.add_child(medal_chip)
	row1.add_child(score_col)

	inner.add_child(row1)

	# ---- 第二行：数据条（击杀/阵亡/助攻 · 输出 · 承伤 · 经济）----
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_child(_make_stat_chip("击", Color(1.0, 0.42, 0.36), str(hero.kills)))
	row2.add_child(_make_stat_chip("亡", Color(0.65, 0.68, 0.78), str(hero.deaths)))
	row2.add_child(_make_stat_chip("助", Color(0.42, 0.85, 1.0), str(hero.assists)))
	row2.add_child(_make_stat_chip("伤", Color(1.0, 0.62, 0.24), _format_gold(int(hero.damage_dealt_to_heroes))))
	row2.add_child(_make_stat_chip("抗", Color(0.75, 0.6, 1.0), _format_gold(int(hero.damage_taken_from_heroes))))
	row2.add_child(_make_stat_chip("金", GOLD_COLOR, _format_gold(hero.total_gold_earned)))
	inner.add_child(row2)

	# ---- 第三行：装备槽位 ----
	var eq_row = HBoxContainer.new()
	eq_row.add_theme_constant_override("separation", 7)
	var eq_hint = Label.new()
	eq_hint.text = "装"
	eq_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(eq_hint, UiKit.FS_XS, Color(0.6, 0.64, 0.74))
	eq_row.add_child(eq_hint)
	for item_id in hero.equipment_slots:
		eq_row.add_child(_make_equip_slot(item_id))
	for _i in range(hero.equipment_slots.size(), Hero.MAX_EQUIPMENT_SLOTS):
		eq_row.add_child(_make_equip_slot(""))
	inner.add_child(eq_row)

	return card

## 奖牌小胶囊：金/银/铜亮色底 + 深色文字 + 白描边，任何背景上都醒目
func _medal_chip(i: int) -> Panel:
	var col := _medal_color(i)
	var txt := _medal_name(i)
	var fs := _fs(UiKit.FS_SM)
	var pill = Panel.new()
	pill.custom_minimum_size = Vector2(maxi(76, txt.length() * fs + int(18 * _ui_scale())),
		fs + int(12 * _ui_scale()))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel",
		_box_style(col, Color(1, 1, 1, 0.8), 1, int(7 * _ui_scale())))
	var lbl = _fill(Label.new(), pill, 4, 0, 4, 0)
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", Color(0.13, 0.09, 0.02))
	lbl.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.55))
	lbl.add_theme_constant_override("outline_size", 1)
	return pill


func _tag_label(text: String, bg: Color, fg: Color, wide: int = 0, accent: bool = false) -> Panel:
	var pill = Panel.new()
	var tw = _fs(UiKit.FS_XS)
	pill.custom_minimum_size = Vector2(maxi(wide, text.length() * tw + int(10 * _ui_scale())), _fs(UiKit.FS_XS) + int(round(UiKit.SP_SM * _ui_scale())))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel",
		UiKit.skin_tag(bg) if accent else _box_style(bg, bg.lightened(0.35), 0, int(6 * _ui_scale())))
	var lbl = _fill(Label.new(), pill, 4, 0, 4, 0)
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
	lbl.add_theme_color_override("font_color", fg)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("outline_size", 1)
	return pill

func _make_stat_chip(glyph: String, tint: Color, value: String) -> Control:
	var box = HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon = MiniBox.new()
	icon.glyph = glyph
	icon.tint = tint
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var val = Label.new()
	val.text = value
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
	val.add_theme_color_override("font_color", Color.WHITE)
	val.add_theme_color_override("font_outline_color", Color.BLACK)
	val.add_theme_constant_override("outline_size", 1)
	box.add_child(val)
	return box

func _make_equip_slot(item_id: String) -> Control:
	var slot = Panel.new()
	slot.custom_minimum_size = Vector2(42, 42)
	var info = ItemDatabase.get_item(item_id) if item_id != "" else {}
	var has = not info.is_empty()
	var tier = int(info.get("tier", 1)) if has else 1
	if has:
		slot.add_theme_stylebox_override("panel", _box_style(
			Color(0.9, 0.88, 0.6, 0.15) if tier >= 3 else Color(1, 1, 1, 0.09),
			_tier_color(tier), 1, 7))
		var ic = ItemSlotIcon.new()
		ic.item_name = str(info.get("name", item_id))
		ic.tier = tier
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.tooltip_text = str(info.get("name", item_id))
		_fill(ic, slot, 3, 3, 3, 3)
	else:
		slot.add_theme_stylebox_override("panel", _box_style(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.16), 1, 7))
	return slot

func _rating_grade(score: float) -> String:
	if score >= 90: return "超神"
	if score >= 80: return "MVP"
	if score >= 70: return "优秀"
	if score >= 60: return "良好"
	if score >= 50: return "一般"
	return "低迷"

func _rating_grade_color(score: float) -> Color:
	if score >= 90: return Color(1.0, 0.5, 0.4)
	if score >= 80: return GOLD_COLOR
	if score >= 70: return Color(0.6, 0.9, 0.5)
	if score >= 60: return Color(0.5, 0.8, 0.9)
	return Color(0.7, 0.72, 0.8)

# ==================== 奖牌（按对战评分，与局内结算一致） ====================
# 0=金牌 1=银牌 2=铜牌 -1=无奖牌；门槛与 BattleManager._pm_medal_by_rating 保持一致
func _medal_index(hero) -> int:
	if hero == null or not is_instance_valid(hero):
		return -1
	var s := _calculate_rating(hero)
	return MatchResultScript.medal_by_rating(s)

func _medal_name(i: int) -> String:
	return MatchResultScript.medal_name(i)

func _medal_color(i: int) -> Color:
	return MatchResultScript.medal_color(i)


# ==================== Tab 2: 数据 ====================
# 每行统计：图标字形 / 主题色 / 名称
var STAT_META = [
	["伤", Color(1.0, 0.42, 0.36), "对英雄伤害"],
	["抗", Color(0.72, 0.58, 1.0), "承受伤害"],
	["金", GOLD_COLOR, "总经济"],
	["团", Color(0.5, 0.85, 1.0), "参团率"],
	["转", Color(1.0, 0.72, 0.3), "伤害转化比"],
	["死", Color(0.8, 0.5, 0.9), "每死承伤"],
	["野", Color(0.55, 0.9, 0.5), "野怪经济"],
	["刀", Color(0.95, 0.8, 0.45), "补刀数"],
	["控", Color(0.9, 0.9, 0.35), "控制时长"],
	["疗", Color(0.5, 0.95, 0.6), "治疗量"],
	["塔", Color(1.0, 0.5, 0.35), "对塔伤害"],
]

func _create_data_tab():
	data_panel = Control.new()
	data_panel.visible = false
	data_panel.anchor_right = 1.0; data_panel.anchor_bottom = 1.0
	content_container.add_child(data_panel)

	var root = VBoxContainer.new()
	root = _fill(root, data_panel, 0, 4, 0, 0)
	root.add_theme_constant_override("separation", 10)

	var head = HBoxContainer.new()
	var ht = Label.new()
	ht.text = "战后数据"
	_apply_label_style(ht, UiKit.FS_XL, UiKit.C_TEXT)
	head.add_child(ht)
	var hs = Label.new()
	hs.text = "  进度条按全场最高归一化，蓝红两方同台可对比；金色为队内最高。"
	hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(hs, UiKit.FS_XS, Color(0.6, 0.65, 0.75))
	head.add_child(hs)
	root.add_child(head)
	root.add_child(_build_gauge_row())

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	# 表格不足一屏时垂直居中，超高时自动滚动
	var vwrap = VBoxContainer.new()
	vwrap.alignment = BoxContainer.ALIGNMENT_CENTER
	vwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vwrap)

	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 30)
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vwrap.add_child(main_hbox)

	# 全局最大值（跨两队），保证两端条形可比
	var global_maxes = {}
	for arr in [team_player_heroes, team_enemy_heroes]:
		var m = _calc_team_maxes(arr)
		for k in m.keys():
			global_maxes[k] = max(global_maxes.get(k, 0.0), m[k])

	main_hbox.add_child(_create_team_data_column(team_player_heroes, false, global_maxes))
	main_hbox.add_child(VSeparator.new())
	main_hbox.add_child(_create_team_data_column(team_enemy_heroes, true, global_maxes))

func _create_team_data_column(heroes: Array, is_enemy: bool, global_maxes: Dictionary) -> Control:
	var team_color = RED_TEAM if is_enemy else BLUE_TEAM
	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.custom_minimum_size = Vector2(480, 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header = Label.new()
	header.text = "敌方" if is_enemy else "我方"
	header.add_theme_font_size_override("font_size", _fs(UiKit.FS_MD))
	header.add_theme_color_override("font_color", team_color)
	container.add_child(header)

	# 队内最高（金色标记）：每队算一次，整列共享
	var team_best = {}
	for i in range(STAT_META.size()):
		var sn: String = STAT_META[i][2]
		var best_val = -1.0
		for h in heroes:
			if h != null:
				best_val = max(best_val, float(_get_hero_stats(h)[i]))
		team_best[sn] = best_val

	# 行式网格：上方是英雄名表头；下面每行一条统计 = 左列「图标+名称」+ 各英雄列「数值(上)/进度条(下)」。
	# 同一行内所有列等宽、等固定行高，图标与对应进度条整行对齐、不再错行。
	var grid = VBoxContainer.new()
	grid.add_theme_constant_override("separation", 2)

	var head_row = HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 8)
	head_row.custom_minimum_size = Vector2(0, 40)
	var name_head = Control.new()
	name_head.custom_minimum_size = Vector2(150, 40)
	head_row.add_child(name_head)
	for hero in heroes:
		var name_lbl = Label.new()
		name_lbl.text = hero.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.custom_minimum_size = Vector2(112, 40)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		name_lbl.add_theme_constant_override("outline_size", 1)
		head_row.add_child(name_lbl)
	grid.add_child(head_row)

	for i in range(STAT_META.size()):
		var meta = STAT_META[i]
		var sn: String = meta[2]
		var gmax = global_maxes.get(sn, 1.0)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.custom_minimum_size = Vector2(0, ROW_H)
		var seg = HBoxContainer.new()
		seg.custom_minimum_size = Vector2(150, 0)
		seg.add_theme_constant_override("separation", 6)
		var ic = MiniBox.new()
		ic.glyph = meta[0]
		ic.tint = meta[1]
		ic.custom_minimum_size = Vector2(24, 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_END
		seg.add_child(ic)
		var nm = Label.new()
		nm.text = meta[2]
		nm.size_flags_vertical = Control.SIZE_SHRINK_END
		nm.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
		nm.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
		nm.add_theme_constant_override("outline_size", 1)
		nm.add_theme_color_override("font_outline_color", Color.BLACK)
		seg.add_child(nm)
		row.add_child(seg)
		for hero in heroes:
			row.add_child(_create_stat_bar_cell(hero, i, sn, team_color, gmax, team_best))
		grid.add_child(row)

	container.add_child(grid)
	return container

func _create_stat_bar_cell(hero, stat_index: int, sn: String, team_color: Color, gmax: float, team_best: Dictionary) -> Control:
	# 单个英雄的一条统计格：上方数值（队内最高金色）+ 下方圆角进度条。
	# 数值区与进度条区用绝对锚点钉在固定行高 ROW_H 的固定 y 上，行高不随字体伸缩，
	# 配合行式网格，图标与进度条逐行对齐。
	var value = _get_hero_stats(hero)[stat_index]
	var is_best = absf(float(value) - team_best[sn]) < 0.001
	var cell := Control.new()
	cell.custom_minimum_size = Vector2(112, ROW_H)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var val_lbl = Label.new()
	val_lbl.text = _fmt_stat(sn, value)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	val_lbl.offset_bottom = ROW_H - 16
	val_lbl.add_theme_font_size_override("font_size", _fs(UiKit.FS_XS))
	val_lbl.add_theme_color_override("font_color", GOLD_COLOR if is_best else Color.WHITE)
	val_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	val_lbl.add_theme_constant_override("outline_size", 1)
	cell.add_child(val_lbl)

	var bar = ProgressBar.new()
	bar.max_value = 100.0
	bar.value = (float(value) / max(1.0, float(gmax))) * 100.0
	bar.show_percentage = false
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = ROW_H - 13
	bar.offset_bottom = ROW_H - 3
	var bg_style := UiKit.flat(0.9, 4, 0, Color.TRANSPARENT, Color(0.14, 0.15, 0.2, 0.9), 0.0)
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_col := Color(team_color.r * 0.5, team_color.g * 0.5, team_color.b, 1.0) if is_best else team_color
	bar.add_theme_stylebox_override("fill", UiKit.flat(fill_col.a, 4, 0, Color.TRANSPARENT, fill_col, 0.0))
	cell.add_child(bar)
	return cell

func _calc_team_maxes(heroes: Array) -> Dictionary:
	var maxes = {}
	var team_total_kills = 0
	var team_total_damage = 0.0
	var team_total_gold = 0
	for h in heroes:
		if h != null:
			team_total_kills += h.kills
			team_total_damage += h.damage_dealt_to_heroes + h.turret_damage
			team_total_gold += h.total_gold_earned
	for h in heroes:
		if h != null:
			var participation = (float(h.kills + h.assists) / max(1, team_total_kills)) * 100.0
			var damage_pct = ((h.damage_dealt_to_heroes + h.turret_damage) / max(1.0, team_total_damage)) * 100.0
			var gold_pct = (float(h.total_gold_earned) / max(1, team_total_gold)) * 100.0
			var conversion = damage_pct / max(0.01, gold_pct)

			maxes["对英雄伤害"] = max(maxes.get("对英雄伤害", 1.0), h.damage_dealt_to_heroes)
			maxes["承受伤害"] = max(maxes.get("承受伤害", 1.0), h.damage_taken_from_heroes)
			maxes["总经济"] = max(maxes.get("总经济", 1.0), float(h.total_gold_earned))
			maxes["参团率"] = max(maxes.get("参团率", 1.0), participation)
			maxes["伤害转化比"] = max(maxes.get("伤害转化比", 0.1), conversion)
			maxes["每死承伤"] = max(maxes.get("每死承伤", 1.0), h.damage_taken_from_heroes / max(1.0, float(h.deaths)))
			maxes["野怪经济"] = max(maxes.get("野怪经济", 1.0), float(h.jungle_gold))
			maxes["补刀数"] = max(maxes.get("补刀数", 1), h.last_hits)
			maxes["控制时长"] = max(maxes.get("控制时长", 0.1), h.cc_duration_dealt)
			maxes["治疗量"] = max(maxes.get("治疗量", 1.0), h.healing_done)
			maxes["对塔伤害"] = max(maxes.get("对塔伤害", 1.0), h.turret_damage)
	return maxes

func _get_hero_stats(hero) -> Array:
	var team_heroes = team_player_heroes if Config.is_ally(hero.team) else team_enemy_heroes
	var team_total_kills = 0
	var team_total_damage = 0.0
	var team_total_gold = 0
	for h in team_heroes:
		if h != null:
			team_total_kills += h.kills
			team_total_damage += h.damage_dealt_to_heroes + h.turret_damage
			team_total_gold += h.total_gold_earned

	var participation = (float(hero.kills + hero.assists) / max(1, team_total_kills)) * 100.0
	var damage_pct = ((hero.damage_dealt_to_heroes + hero.turret_damage) / max(1.0, team_total_damage)) * 100.0
	var gold_pct = (float(hero.total_gold_earned) / max(1, team_total_gold)) * 100.0
	var conversion = damage_pct / max(0.01, gold_pct)
	var damage_per_death = hero.damage_taken_from_heroes / max(1.0, float(hero.deaths))

	return [
		hero.damage_dealt_to_heroes,
		hero.damage_taken_from_heroes,
		float(hero.total_gold_earned),
		participation,
		conversion,
		damage_per_death,
		float(hero.jungle_gold),
		hero.last_hits,
		hero.cc_duration_dealt,
		hero.healing_done,
		hero.turret_damage
	]

func _fmt_stat(stat_name: String, value) -> String:
	match stat_name:
		"参团率": return "%.1f%%" % value
		"伤害转化比": return "%.2f" % value
		"控制时长": return "%.1fs" % value
		"每死承伤", "对英雄伤害", "承受伤害", "总经济", "野怪经济", "治疗量", "对塔伤害":
			return _format_gold(int(value)) if value >= 1000 else str(int(value))
		"补刀数":
			return str(value)
	return str(int(value))

# ==================== Tab 3: 复盘 ====================
func _create_replay_tab():
	replay_panel = Control.new()
	replay_panel.visible = false
	replay_panel.anchor_right = 1.0; replay_panel.anchor_bottom = 1.0
	content_container.add_child(replay_panel)

	var root = VBoxContainer.new()
	root = _fill(root, replay_panel, 0, 4, 0, 4)
	root.add_theme_constant_override("separation", 10)

	# 图例行
	var legend = HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	var lt = Label.new()
	lt.text = "经济差走势"
	lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(lt, UiKit.FS_LG, UiKit.C_TEXT)
	legend.add_child(lt)
	var ls = Label.new()
	ls.text = "（我方为正、敌方为负）"
	ls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(ls, UiKit.FS_XS, Color(0.6, 0.65, 0.75))
	legend.add_child(ls)
	var lsp = Control.new()
	lsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(lsp)
	legend.add_child(_tag_label("我方领先", BLUE_TEAM, BLUE_TEAM.lightened(0.35), 76, true))
	legend.add_child(_tag_label("敌方领先", RED_TEAM, RED_TEAM.lightened(0.35), 76, true))
	root.add_child(legend)

	# 折线图区
	var chart_wrap = Control.new()
	chart_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart_wrap.custom_minimum_size = Vector2(0, 260)
	root.add_child(chart_wrap)

	var chart = GoldChart.new()
	_fill(chart, chart_wrap, 0, 0, 0, 0)
	chart.data = _m_gold_hist()
	chart.game_duration = _m_game_time()
	chart.queue_redraw()

	# 底部双 MVP 卡
	var mvp_row = HBoxContainer.new()
	mvp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mvp_row.add_theme_constant_override("separation", 24)
	var mvp_player = _find_mvp(team_player_heroes)
	var mvp_enemy = _find_mvp(team_enemy_heroes)
	mvp_row.add_child(_create_mvp_mini(mvp_player, false, 480))
	mvp_row.add_child(_create_mvp_mini(mvp_enemy, true, 480))
	root.add_child(mvp_row)

# ==================== MVP / 评分计算 ====================
func _find_mvp(heroes: Array):
	var best = null
	var best_score = -1.0
	for h in heroes:
		if h != null:
			var s = _calculate_rating(h)
			if s > best_score:
				best_score = s
				best = h
	return best

func _calculate_rating(hero) -> float:
	# 三端统一口径：MatchResult（与局内结算/联机/回放同一公式）
	var team: Array = team_player_heroes if team_player_heroes.has(hero) else team_enemy_heroes
	return MatchResultScript.rating(hero, team)
# ==================== 内部类：英雄头像（程序化立绘）====================
class HeroFace extends Control:
	var hero_name: String = ""
	var ring: Color = Color.WHITE
	var dead := false
	var ring_width: float = 3.0

	func _draw():
		var r = min(size.x, size.y) * 0.5
		if r <= 2: return
		var c = size * 0.5
		var art = preload("res://scripts/ui/HeroArt.gd")
		art.draw_portrait(self, c, maxf(1.0, r - ring_width * 0.5), hero_name, ring, dead)
		draw_arc(c, r - ring_width * 0.5, 0.0, TAU, 48, ring, ring_width)

# ==================== 内部类：装备图标 ====================
class ItemSlotIcon extends Control:
	var item_name: String = ""
	var tier: int = 1

	func _draw():
		var s: float = minf(size.x, size.y)
		if s <= 2.0: return
		UiKit.item_icon(self, Rect2(Vector2.ZERO, Vector2(s, s)), tier, item_name)

# ==================== 内部类：角色/符号圆盘 ====================
class RoleDisc extends Control:
	var glyph: String = ""
	var ring: Color = Color.WHITE
	var glyph_color: Color = Color.WHITE
	var glyph_scale: float = 0.62
	var draw_ring_width: float = 3.0
	var bg_tint: Color = Color(0.06, 0.07, 0.11, 0.95)

	func _draw():
		var r = min(size.x, size.y) * 0.5
		var c = size * 0.5
		if r <= 1: return
		draw_circle(c, r, bg_tint)
		# 细内描边，增强立体
		draw_arc(c, r - draw_ring_width * 0.5, 0.0, TAU, 48, ring, draw_ring_width)
		if glyph == "": return
		var font: Font = UiKit.font()
		var px = int(r * 2.0 * glyph_scale)
		if px <= 4: return
		var ascent = font.get_ascent(px)
		var descent = font.get_descent(px)
		var width = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
		var x = (size.x - width) * 0.5
		var y = c.y - (ascent + descent) * 0.5 + ascent
		draw_string(font, Vector2(x, y), glyph, HORIZONTAL_ALIGNMENT_CENTER, width, px, glyph_color)

# ==================== 内部类：小型方块图标 ====================
class MiniBox extends Control:
	var glyph: String = ""
	var tint: Color = Color.WHITE
	var bg: Color = Color(0, 0, 0, 0.28)

	func _draw():
		var style := UiKit.flat(1.0, maxi(2, int(min(size.x, size.y) * 0.28)), 1,
				Color(tint.r, tint.g, tint.b, 0.55), Color(tint.r, tint.g, tint.b, 0.16), 0.0)
		draw_style_box(style, Rect2(Vector2.ZERO, size))
		if glyph == "": return
		var font: Font = UiKit.font()
		var px = int(size.y * 0.62)
		if px <= 4: return
		var ascent = font.get_ascent(px)
		var descent = font.get_descent(px)
		var w = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_CENTER, -1, px).x
		var x = (size.x - w) * 0.5
		var y = size.y * 0.5 - (ascent + descent) * 0.5 + ascent
		draw_string(font, Vector2(x, y), glyph, HORIZONTAL_ALIGNMENT_CENTER, w, px, tint.lightened(0.25))

# ==================== 内部类：经济差折线图 ====================
class GoldChart extends Control:
	var data: Array = [0]
	var game_duration: float = 0.0

	const MARGIN_LEFT: float = 100.0
	const MARGIN_RIGHT: float = 42.0
	const MARGIN_TOP: float = 74.0
	const MARGIN_BOTTOM: float = 74.0
	const LABEL_COLOR = Color.WHITE
	const BLUE_FILL = Color(0.0, 0.4, 0.9, 0.3)
	const RED_FILL = Color(0.9, 0.1, 0.1, 0.3)
	const LINE_BLUE = Color(0.0, 0.7, 1.0, 1.0)
	const LINE_RED = Color(1.0, 0.2, 0.2, 1.0)
	const MID_LINE = Color(1.0, 0.84, 0.0, 0.8)

	func _draw():
		var chart_w = size.x - MARGIN_LEFT - MARGIN_RIGHT
		var chart_h = size.y - MARGIN_TOP - MARGIN_BOTTOM
		if chart_w <= 0 or chart_h <= 0: return

		var zero_y = MARGIN_TOP + chart_h / 2.0

		# 计算Y轴范围
		var max_abs = 1.0
		for v in data:
			max_abs = max(max_abs, abs(float(v)))
		max_abs = max(max_abs, 2000.0)  # 至少±2000
		max_abs = ceil(max_abs / 2000.0) * 2000.0

		# 绘制上半部分蓝色底色
		draw_rect(Rect2(MARGIN_LEFT, MARGIN_TOP, chart_w, chart_h / 2.0), BLUE_FILL)
		# 绘制下半部分红色底色
		draw_rect(Rect2(MARGIN_LEFT, zero_y, chart_w, chart_h / 2.0), RED_FILL)

		# Y轴刻度线
		var step = max_abs / 4.0
		var font = UiKit.font()
		for i in range(-4, 5):
			var y_val = i * step
			var y_pos = zero_y - (y_val / max_abs) * (chart_h / 2.0)
			if y_pos < MARGIN_TOP or y_pos > MARGIN_TOP + chart_h: continue

			# 网格线
			var grid_color = Color.WHITE
			grid_color.a = 0.15 if i != 0 else 0.4
			draw_line(Vector2(MARGIN_LEFT, y_pos), Vector2(MARGIN_LEFT + chart_w, y_pos), grid_color, 1.0)

			# Y轴标签
			var label_text = _format_y_label(y_val)
			draw_string(font, Vector2(8, y_pos + 9), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, LABEL_COLOR)

		# X轴标签
		var total_minutes = max(1, int(game_duration / 60.0))
		var x_data_count = data.size()
		for m in range(0, total_minutes + 1):
			if m >= x_data_count: break
			var x_pos = MARGIN_LEFT + (float(m) / max(1, total_minutes - 1)) * chart_w if total_minutes > 1 else MARGIN_LEFT + chart_w / 2.0
			draw_string(font, Vector2(x_pos - 12, MARGIN_TOP + chart_h + 16), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

		# 折线和填充
		if data.size() < 2: return

		var points = PackedVector2Array()
		for i in range(data.size()):
			var x = MARGIN_LEFT + (float(i) / max(1, data.size() - 1)) * chart_w
			var y = zero_y - (float(data[i]) / max_abs) * (chart_h / 2.0)
			y = clamp(y, MARGIN_TOP, MARGIN_TOP + chart_h)
			points.append(Vector2(x, y))

		# 填充区域 (正值为蓝, 负值为红)
		for i in range(points.size() - 1):
			var p0 = points[i]
			var p1 = points[i + 1]
			var base0 = Vector2(p0.x, zero_y)
			var base1 = Vector2(p1.x, zero_y)

			var fill_color = BLUE_FILL if float(data[i]) >= 0 else RED_FILL
			var fill_poly = PackedVector2Array([p0, p1, base1, base0])
			draw_polygon(fill_poly, [fill_color])

		# 绘制折线
		for i in range(points.size() - 1):
			var line_color = LINE_BLUE if float(data[i]) >= 0 else LINE_RED
			draw_line(points[i], points[i + 1], line_color, 2.5)

		# 绘制0线
		draw_line(Vector2(MARGIN_LEFT, zero_y), Vector2(MARGIN_LEFT + chart_w, zero_y), Color.WHITE, 1.5)

		# 4分钟竖线
		self._draw_milestone_line(4.0, total_minutes, chart_w, MARGIN_TOP, chart_h, zero_y, "中期", font)
		# 10分钟竖线
		self._draw_milestone_line(10.0, total_minutes, chart_w, MARGIN_TOP, chart_h, zero_y, "后期", font)

		# 峰值/谷值标注
		var best_idx = 0
		var worst_idx = 0
		for i in range(1, data.size()):
			if float(data[i]) > float(data[best_idx]): best_idx = i
			if float(data[i]) < float(data[worst_idx]): worst_idx = i
		if data.size() >= 2:
			var px_b = points[best_idx]
			var px_w = points[worst_idx]
			if absf(float(data[best_idx])) > 1.0:
				draw_arc(px_b, 6.0, 0.0, TAU, 24, Color(1.0, 0.84, 0.0, 1.0), 2.0)
				draw_circle(px_b, 3.0, Color(1.0, 0.84, 0.0, 1.0))
				var lb = _format_y_label(float(data[best_idx]))
				draw_string(font, Vector2(clamp(px_b.x - 26, MARGIN_LEFT, MARGIN_LEFT + chart_w - 100), px_b.y - 18), "+" + lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.84, 0.0, 1.0))
			if absf(float(data[worst_idx])) > 1.0:
				draw_arc(px_w, 6.0, 0.0, TAU, 24, Color(1.0, 0.5, 0.4, 1.0), 2.0)
				draw_circle(px_w, 3.0, Color(1.0, 0.5, 0.4, 1.0))
				var lw = _format_y_label(float(data[worst_idx]))
				draw_string(font, Vector2(clamp(px_w.x - 26, MARGIN_LEFT, MARGIN_LEFT + chart_w - 100), px_w.y - 18), lw, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.6, 0.55))

	func _draw_milestone_line(minute: float, total_minutes: int, chart_w: float, top: float, chart_h: float, zero_y: float, label: String, font: Font):
		if minute > total_minutes: return
		var x = MARGIN_LEFT + (minute / max(1, total_minutes)) * chart_w
		# 虚线效果：画多段短线
		var dash_len = 8.0
		var dash_gap = 6.0
		var cur_y = top
		while cur_y < top + chart_h:
			var end_y = min(cur_y + dash_len, top + chart_h)
			draw_line(Vector2(x, cur_y), Vector2(x, end_y), MID_LINE, 2.0)
			cur_y += dash_len + dash_gap
		# 标签
		draw_string(font, Vector2(x + 7, top + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MID_LINE)

	func _format_y_label(val: float) -> String:
		var abs_val = abs(val)
		if abs_val >= 1000:
			return ("%.1fk" % (val / 1000.0)) if val >= 0 else ("-%.1fk" % (abs_val / 1000.0))
		return str(int(val))


# ==================== 战利品结算带（段位/星条/积分 + 本局评价 + 灵宝点评） ====================

const LingbaoStoreScript = preload("res://scripts/core/LingbaoStore.gd")

func _build_reward_band() -> Control:
	var is_win: bool = Config.is_ally(_m_winner())
	var rs: Dictionary = _rank_result.get("new_state", RankSystem.state()) if not _rank_result.is_empty() else RankSystem.state()
	var old_state: Dictionary = _rank_result.get("old_state", rs) if not _rank_result.is_empty() else rs
	var tier: int = clampi(int(rs.get("tier", 0)), 0, RankSystem.KING_INDEX)
	var tcol: Color = RankSystem.tier_color(rs)

	var band := Panel.new()
	band.name = "RewardBand"
	band.custom_minimum_size = Vector2(0, 80)
	band.add_theme_stylebox_override("panel",
		_box_style(Color(0.06, 0.075, 0.12, 0.9), Color(tcol.r, tcol.g, tcol.b, 0.42), 1, 12))
	var hb := HBoxContainer.new()
	_fill(hb, band, 18, 6, 18, 6)
	hb.add_theme_constant_override("separation", 24)

	# 1) 段位 + 星条
	var c1 := VBoxContainer.new()
	c1.add_theme_constant_override("separation", 2)
	c1.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hb.add_child(c1)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	c1.add_child(r1)
	var cap := Label.new()
	cap.text = "排位"
	_apply_label_style(cap, UiKit.FS_XS, UiKit.C_TEXT_DIM)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(cap)
	var rn := Label.new()
	rn.text = str(_rank_result.get("new_label", RankSystem.label(rs)))
	_apply_label_style(rn, UiKit.FS_MD, tcol.lightened(0.22))
	rn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(rn)
	var stars_now: int = int(rs.get("stars", 0))
	var stars_old: int = int(old_state.get("stars", 0))
	if tier >= RankSystem.KING_INDEX:
		var kl := Label.new()
		kl.text = "★ ×%d" % stars_now
		_apply_label_style(kl, UiKit.FS_SM, UiKit.C_GOLD)
		kl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r1.add_child(kl)
	else:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 1)
		r1.add_child(srow)
		for i in range(mini(int(RankSystem.TIER_STARS[tier]), 8)):
			var lit: bool = i < stars_now
			var s := Label.new()
			s.text = "★"
			_apply_label_style(s, UiKit.FS_SM, UiKit.C_GOLD if lit else Color(0.34, 0.37, 0.44))
			s.add_theme_constant_override("outline_size", 0)
			if lit and i >= stars_old:
				s.modulate.a = 0.0
				var t0 := create_tween()
				t0.tween_interval(0.35 + 0.10 * float(i))
				t0.tween_property(s, "modulate:a", 1.0, 0.26)
			srow.add_child(s)
	var delta_txt := ""
	var sc := int(_rank_result.get("star_change", 0))
	if bool(_rank_result.get("promoted", false)):
		delta_txt = "晋升"
	elif bool(_rank_result.get("demoted", false)):
		delta_txt = "降级"
	elif bool(_rank_result.get("protected", false)):
		delta_txt = "保星"
	elif bool(_rank_result.get("floor_protected", false)):
		delta_txt = "段位保护"
	elif sc > 0:
		delta_txt = "+%d★" % sc
	elif sc < 0:
		delta_txt = "%d★" % sc
	if delta_txt != "":
		var dl := Label.new()
		dl.text = delta_txt
		_apply_label_style(dl, UiKit.FS_SM, UiKit.C_GOLD if sc >= 0 else UiKit.C_DANGER)
		dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r1.add_child(dl)
	var p_old: int = int(old_state.get("points", 0))
	var p_new: int = int(rs.get("points", 0))
	var p_delta: int = int(_rank_result.get("point_change", 0))
	var pl := Label.new()
	pl.text = "排位积分 %d/%d · 本局 %+d" % [p_new, RankSystem.STAR_POINTS, p_delta]
	_apply_label_style(pl, UiKit.FS_XS, UiKit.C_TEXT_DIM)
	c1.add_child(pl)

	# 2) 积分条（旧值 → 新值填充）
	var c2 := VBoxContainer.new()
	c2.add_theme_constant_override("separation", 6)
	c2.custom_minimum_size = Vector2(300, 0)
	c2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(c2)
	var pcap := Label.new()
	pcap.text = "积分进度 · 每星 100 分"
	_apply_label_style(pcap, UiKit.FS_XS, UiKit.C_TEXT_DIM)
	c2.add_child(pcap)
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(0, 16)
	bar_bg.add_theme_stylebox_override("panel",
		_box_style(Color(0.10, 0.12, 0.18, 0.95), Color(1, 1, 1, 0.08), 1, 8))
	c2.add_child(bar_bg)
	var bar_fill := Panel.new()
	bar_fill.add_theme_stylebox_override("panel",
		_box_style(UiKit.C_GOLD, UiKit.C_GOLD.lightened(0.25), 0, 8))
	bar_fill.anchor_top = 0.0
	bar_fill.anchor_bottom = 1.0
	bar_fill.offset_top = 2.0
	bar_fill.offset_bottom = -2.0
	bar_fill.offset_left = 2.0
	bar_fill.anchor_right = clampf(float(p_old) / float(RankSystem.STAR_POINTS), 0.0, 1.0)
	bar_bg.add_child(bar_fill)
	var tw := create_tween()
	tw.tween_interval(0.40)
	tw.tween_property(bar_fill, "anchor_right",
		clampf(float(p_new) / float(RankSystem.STAR_POINTS), 0.0, 1.0), 0.7)

	# 3) 本局结算 + 成就
	var hero = _m_hero()
	var c3 := HBoxContainer.new()
	c3.add_theme_constant_override("separation", 8)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c3.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(c3)
	var grade := "—"
	var grade_col: Color = UiKit.C_TEXT_DIM
	if hero != null:
		c3.add_child(_make_stat_chip("金", GOLD_COLOR, _format_gold(int(hero.total_gold_earned))))
		c3.add_child(_make_stat_chip("级", Color(0.55, 0.80, 1.0), "Lv.%d" % int(hero.level)))
		var score := _calculate_rating(hero)
		grade = _rating_grade(score)
		grade_col = _rating_grade_color(score)
	var gl := Label.new()
	gl.text = "评价"
	_apply_label_style(gl, UiKit.FS_XS, UiKit.C_TEXT_DIM)
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c3.add_child(gl)
	var gv := Label.new()
	gv.text = grade
	_apply_label_style(gv, UiKit.FS_LG, grade_col)
	gv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c3.add_child(gv)
	# 本局奖牌：优先用局内结算算出的奖牌（含积分加成），没算过就按评分兜底
	var pm_medal := -1
	if not _rank_result.is_empty():
		pm_medal = int(_rank_result.get("medal", -1))
	if pm_medal < 0 and hero != null:
		pm_medal = _medal_index(hero)
	if pm_medal >= 0:
		c3.add_child(_medal_chip(pm_medal))
	for a in _achievements():
		c3.add_child(_achievement_tag(str(a)))

	# 4) 灵宝点评（单行，超长省略）
	var c4 := HBoxContainer.new()
	c4.add_theme_constant_override("separation", 8)
	c4.custom_minimum_size = Vector2(430, 0)
	c4.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(c4)
	var lbn := Label.new()
	lbn.text = "%s：" % LingbaoStoreScript.name()
	_apply_label_style(lbn, UiKit.FS_SM, Color(0.72, 0.84, 1.0))
	lbn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c4.add_child(lbn)
	var lbt := Label.new()
	lbt.text = _lingbao_line(is_win, _self_is_mvp, grade)
	lbt.clip_text = true
	lbt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_apply_label_style(lbt, UiKit.FS_SM, Color(0.88, 0.93, 1.0))
	c4.add_child(lbt)

	band.modulate.a = 0.0
	var tw2 := create_tween()
	tw2.tween_property(band, "modulate:a", 1.0, 0.35)
	return band


## 成就称号胶囊：深底 + 金描边 + 亮金大字（比原灰金小标签清晰得多）
func _achievement_tag(txt: String) -> Panel:
	var fs := _fs(UiKit.FS_SM)
	var pill = Panel.new()
	pill.custom_minimum_size = Vector2(maxi(84, txt.length() * fs + int(20 * _ui_scale())),
		fs + int(14 * _ui_scale()))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_theme_stylebox_override("panel",
		_box_style(Color(0.13, 0.10, 0.03, 0.95), Color(1.0, 0.82, 0.35, 0.92), 1, int(8 * _ui_scale())))
	var lbl = _fill(Label.new(), pill, 6, 0, 6, 0)
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", fs)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	return pill


func _achievements() -> Array:
	var out: Array = []
	var h = _m_hero()
	if h == null:
		return out
	if int(h.kills) >= 10:
		out.append("超神")
	if int(h.deaths) == 0:
		out.append("零死")
	if int(h.assists) >= 15:
		out.append("团队核心")
	if float(h.turret_damage) >= 8000.0:
		out.append("推塔机器")
	if float(h.damage_dealt_to_heroes) >= 30000.0:
		out.append("团战核心")
	if float(h.healing_done) >= 8000.0:
		out.append("团队奶妈")
	return out


func _lingbao_line(win: bool, mvp: bool, grade: String) -> String:
	if win and mvp:
		return "带飞全场！我就知道你能行～"
	if win and (grade == "S" or grade == "A"):
		return "这局打得漂亮，我在旁边都看呆了！"
	if win:
		return "赢啦赢啦，下一把继续冲～"
	if mvp:
		return "你已经尽力了，输了不怪你～"
	if grade == "S" or grade == "A":
		return "数据这么好还输，队友拖累了吧…"
	return "这把对面太肥了，咱们下把赢回来！"


# ==================== 仪表盘（对位双环） ====================

func _team_agg(heroes: Array) -> Dictionary:
	var k := 0
	var d := 0
	var asst := 0
	var gold := 0
	var dmg := 0.0
	var taken := 0.0
	var tower := 0.0
	for h in heroes:
		if not is_instance_valid(h):
			continue
		k += int(h.kills)
		d += int(h.deaths)
		asst += int(h.assists)
		gold += int(h.total_gold_earned)
		dmg += float(h.damage_dealt_to_heroes)
		taken += float(h.damage_taken_from_heroes)
		tower += float(h.turret_damage)
	var mins := maxf(0.5, float(_m_game_time()) / 60.0)
	return {
		"kills": k, "deaths": d, "assists": asst, "gold": gold,
		"gpm": float(gold) / mins, "dmg": dmg, "taken": taken, "tower": tower,
		"kda": float(k + asst) / maxf(1.0, float(d)),
	}


func _fmt_short(v: float) -> String:
	if v >= 10000.0:
		return "%.1f万" % (v / 10000.0)
	if v >= 100.0:
		return "%d" % int(round(v))
	return "%.1f" % v


func _build_gauge_row() -> Control:
	var a := _team_agg(team_player_heroes)
	var b := _team_agg(team_enemy_heroes)
	var defs := [
		["总击杀", float(a["kills"]), float(b["kills"])],
		["经济/分", float(a["gpm"]), float(b["gpm"])],
		["对英雄输出", float(a["dmg"]), float(b["dmg"])],
		["承受伤害", float(a["taken"]), float(b["taken"])],
		["推塔伤害", float(a["tower"]), float(b["tower"])],
		["团队KDA", float(a["kda"]), float(b["kda"])],
	]
	var row := HBoxContainer.new()
	row.name = "GaugeRow"
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gauges.clear()
	for i in range(defs.size()):
		var dd: Array = defs[i]
		var va := float(dd[1])
		var vb := float(dd[2])
		var mx := maxf(va, vb)
		var g := RingGauge.new()
		g.label = str(dd[0])
		g.txt_a = _fmt_short(va)
		g.txt_b = _fmt_short(vb)
		g.val_a = 0.0 if mx <= 0.0 else va / mx
		g.val_b = 0.0 if mx <= 0.0 else vb / mx
		g.delay = 0.20 + 0.06 * float(i)
		row.add_child(g)
		_gauges.append(g)
	return row


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_on_play_again()
	elif k == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_return()


class RingGauge extends Control:
	var label := ""
	var txt_a := ""
	var txt_b := ""
	var val_a := 0.0
	var val_b := 0.0
	var delay := 0.0
	var col_a: Color = Color(0.25, 0.85, 1.0)
	var col_b: Color = Color(1.0, 0.40, 0.32)
	var t := 0.0

	func _usc() -> float:
		return clampf(get_viewport().get_visible_rect().size.x / 2400.0, 1.0, 1.2) * 1.7

	func _ready() -> void:
		custom_minimum_size = Vector2(196, 196)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_method(_on_t, 0.0, 1.0, 0.7)

	func _on_t(v: float) -> void:
		t = v
		queue_redraw()

	func _draw() -> void:
		var f: float = minf(size.x, size.y)
		var c := size * 0.5
		var r_out := f * 0.40
		var r_in := r_out * 0.72
		var w := f * 0.075
		draw_arc(c, r_out, 0.0, TAU, 56, Color(1, 1, 1, 0.07), w, true)
		draw_arc(c, r_in, 0.0, TAU, 56, Color(1, 1, 1, 0.05), w * 0.85, true)
		if val_a > 0.001:
			draw_arc(c, r_out, -PI * 0.5, -PI * 0.5 + TAU * clampf(val_a * t, 0.0, 1.0), 56, col_a, w, true)
		if val_b > 0.001:
			draw_arc(c, r_in, -PI * 0.5, -PI * 0.5 + TAU * clampf(val_b * t, 0.0, 1.0), 56, col_b, w * 0.85, true)
		var s1 := int(round(22.0 * _usc()))
		var s2 := int(round(11.0 * _usc()))
		UiKit.text(self, c + Vector2(-size.x * 0.5, s1 * 0.36), txt_a, s1, Color(0.97, 0.98, 1.0),
			HORIZONTAL_ALIGNMENT_CENTER, size.x)
		UiKit.text(self, c + Vector2(-size.x * 0.5, s1 * 0.36 + s2 * 1.5), label, s2,
			Color(0.70, 0.78, 0.92), HORIZONTAL_ALIGNMENT_CENTER, size.x)
		UiKit.text(self, c + Vector2(-size.x * 0.5, s1 * 0.36 + s2 * 2.9), "敌 " + txt_b, s2,
			Color(col_b.r, col_b.g, col_b.b, 0.92), HORIZONTAL_ALIGNMENT_CENTER, size.x)







