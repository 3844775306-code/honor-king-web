class_name NetResultPanel extends Control
## P3f 结算页：host game_over 翻转广播一次（winner + 全英雄 rows）。复刻主机 ResultsPanel（scripts/ui/ResultsPanel.gd）
## 的版式尺度：全屏程序化背景（UiKit.make_backdrop，按胜负取 accent）+ 薄暗幕，
## 面板铺满视口（左右各留 32，两列均分、中央 350 VS 列），
## 胜负徽章 70×70 + 「对局胜利/对局失败」40×rs 大字 + 双方列头（23×rs 队名 / 16×rs 总击杀·团队经济）+
## 英雄卡（20×rs 名字 / 16×rs 定位·等级 / KDA 16×rs / 27×rs 评分金 / 16×rs 数据条 / 42 装备格）。
## rs 复刻 ResultsPanel._ui_scale() = clampf(视口宽/2400, 1.0, 1.2) * 1.7。
## Esc/点击遮罩关闭（回到观战态）。

const PANEL_W := 1860.0     # 面板宽下限（窄屏兜底），正常按视口铺满
const COL_W := 740.0        # 列宽兜底，实际由 _panel_rect 均分计算
const BLUE_TEAM := Color(0.0, 0.886, 1.0, 1.0)
const RED_TEAM := Color(1.0, 0.33, 0.264, 1.0)
const GOLD_COLOR := Color(1.0, 0.84, 0.0, 1.0)

var _payload := {}
var _f := UiKit.font()
# 铺满自适应：面板宽按视口取（下限同 host 版心），两侧列宽随之均分
var _pw: float = PANEL_W
var _cw: float = COL_W
var _backdrop: Control = null

# 同 host ResultsPanel._ui_scale()
func _rs() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.7
	return clampf(vp.get_visible_rect().size.x / 2400.0, 1.0, 1.2) * 1.7

# 每行英雄卡高（host card.custom_minimum_size.y = 122 × _ui_scale）；小屏时压缩以整屏可见
func _row_h() -> float:
	var h := 122.0 * _rs()
	var vp := get_viewport()
	if vp != null:
		var avail := vp.get_visible_rect().size.y - 64.0 - 280.0
		h = minf(h, maxf(84.0, avail / 5.0))
	return h

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 全屏程序化背景，置于自绘层之下（z_index=-1 画在本节点 _draw 之前）
	_backdrop = UiKit.make_backdrop(self, BLUE_TEAM, 0.8)
	_backdrop.z_index = -1
	visible = false
	NetSession.net_game_over.connect(_on_result)

func _on_result(p: Dictionary) -> void:
	_payload = p
	# 胜负语音：接管方/观战视角本方恒为蓝方 PLAYER
	var win := int(p.get("winner", -1)) == Config.Team.PLAYER
	if _backdrop != null:
		_backdrop.set("accent", BLUE_TEAM if win else RED_TEAM)
	UiKit.show_panel(self, 0.20)
	SfxManager.play_announce("victory" if win else "defeat")
	queue_redraw()

func _text(pos: Vector2, txt: String, sz: int, col: Color) -> void:
	draw_string(_f, pos + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.55))
	draw_string(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _team_sums(rows: Array, team: int) -> Dictionary:
	var kills := 0
	var gold := 0
	for r in rows:
		if int(r["team"]) == team:
			kills += int(r["k"])
			gold += int(r["gold"])
	return {"kills": kills, "gold": gold}

func _panel_rect(area: Vector2, n_rows: int) -> Rect2:
	# 面板铺满（左右各留 32），两列均分；中央 VS 列固定 350
	_pw = maxf(1200.0, area.x - 64.0)
	_cw = maxf(380.0, (_pw - 406.0) * 0.5)
	var ph := 220.0 + float(n_rows) * _row_h() + 60.0
	return Rect2((area.x - _pw) * 0.5, (area.y - ph) * 0.5, _pw, ph)

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	var rs := _rs()
	# 暗幕降透明度，让程序化背景透出
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.035, 0.04, 0.08, 0.32))
	var rows: Array = _payload.get("rows", [])
	var win: int = int(_payload.get("winner", -1))
	var is_win := win == Config.Team.PLAYER
	var my_rows: Array = []
	var en_rows: Array = []
	for r in rows:
		if int(r["team"]) == Config.Team.PLAYER:
			my_rows.append(r)
		else:
			en_rows.append(r)
	var n_rows := maxi(my_rows.size(), en_rows.size())
	var panel := _panel_rect(area, n_rows)
	# 面板略透，透出背景渐变/粒子
	draw_rect(panel, Color(0.015, 0.035, 0.08, 0.90))
	var accent := Color(0.3, 0.95, 0.85, 0.9) if is_win else Color(0.95, 0.32, 0.3, 0.9)
	draw_rect(panel, accent, false, 4.0)
	var result_color := BLUE_TEAM if is_win else RED_TEAM
	# 胜负徽章（同 host RoleDisc 70×70：圆盘 + 队色环 + 单字「胜/负」）
	var badge_c := panel.position + Vector2(20.0 + 35.0, 24.0 + 35.0)
	draw_circle(badge_c, 35.0, Color(0.06, 0.07, 0.11, 0.95))
	draw_arc(badge_c, 33.5, 0.0, TAU, 48, result_color, 3.0)
	var bg_fs := int(round(43.0))
	var bg_w := _f.get_string_size("胜" if is_win else "负", HORIZONTAL_ALIGNMENT_CENTER, -1, bg_fs).x
	_text(Vector2(badge_c.x - bg_w * 0.5, badge_c.y + bg_fs * 0.36), "胜" if is_win else "负", bg_fs, result_color)
	# 标题 + 副标题（同 host：40×rs 队色标题、17×rs 灰蓝副标题）
	var title_x := panel.position.x + 126.0
	var title_fs := int(round(40.0 * rs))
	_text(Vector2(title_x, panel.position.y + 24.0 + 40.0 * rs * 0.72), "对局胜利" if is_win else "对局失败", title_fs, result_color)
	var my_sum := _team_sums(rows, Config.Team.PLAYER)
	var en_sum := _team_sums(rows, Config.Team.ENEMY)
	_text(Vector2(title_x, panel.position.y + 24.0 + 40.0 * rs * 0.72 + 36.0 * rs),
			"我方击杀 %d : %d  ·  本场总经济 %s" % [int(my_sum["kills"]), int(en_sum["kills"]),
			_fmt_gold(int(my_sum["gold"]) + int(en_sum["gold"]))],
			int(round(17.0 * rs)), Color(0.75, 0.8, 0.9))
	# 两列列头（同 host _make_team_header：740×60 队色底 + 队名 23×rs + 总击杀/团队经济 16×rs）
	var lx := panel.position.x + 10.0
	var rx := panel.position.x + _pw - 10.0 - _cw
	var hy := panel.position.y + 150.0
	_draw_team_header(Rect2(lx, hy, _cw, 60.0), "我方", BLUE_TEAM, int(my_sum["kills"]), int(my_sum["gold"]), false, rs)
	_draw_team_header(Rect2(rx, hy, _cw, 60.0), "敌方", RED_TEAM, int(en_sum["kills"]), int(en_sum["gold"]), true, rs)
	# 中央 VS（同 host 350 宽中央列：VS 徽章 + 44×rs 双方比分 + 16×rs 提示）
	var cx := panel.position.x + _pw * 0.5
	draw_circle(Vector2(cx, hy + 24.0), 24.0, Color(0.06, 0.07, 0.11, 0.95))
	draw_arc(Vector2(cx, hy + 24.0), 22.5, 0.0, TAU, 40, GOLD_COLOR if is_win else Color(0.6, 0.65, 0.75), 4.0)
	var vs_fs := int(round(18.0))
	var vs_w := _f.get_string_size("VS", HORIZONTAL_ALIGNMENT_CENTER, -1, vs_fs).x
	_text(Vector2(cx - vs_w * 0.5, hy + 24.0 + vs_fs * 0.36), "VS", vs_fs, GOLD_COLOR if is_win else Color.WHITE)
	var sc_fs := int(round(44.0 * rs * 0.6))
	var sc_txt := "%d : %d" % [int(my_sum["kills"]), int(en_sum["kills"])]
	var sc_w := _f.get_string_size(sc_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, sc_fs).x
	_text(Vector2(cx - sc_w * 0.5, hy + 70.0), sc_txt, sc_fs, BLUE_TEAM)
	# 英雄卡两列
	var y0 := panel.position.y + 220.0
	for i in range(n_rows):
		var py := y0 + float(i) * _row_h()
		if i < my_rows.size():
			_draw_row(Vector2(lx, py), my_rows[i], true, rs)
		if i < en_rows.size():
			_draw_row(Vector2(rx, py), en_rows[i], false, rs)
	# 底部提示
	var tail := panel.position.y + panel.size.y - 26.0
	var tip := "对局结束 · 按 Esc 返回"
	var tw := _f.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(16.0 * rs))).x
	_text(Vector2(panel.position.x + (_pw - tw) * 0.5, tail), tip, int(round(16.0 * rs)), Color(1, 1, 1, 0.6))

# 列头条（同 host _make_team_header）
func _draw_team_header(r: Rect2, title: String, team_color: Color, kills: int, gold: int, is_enemy: bool, rs: float) -> void:
	var bg := Color(0.28, 0.08, 0.08, 0.85) if is_enemy else Color(0.08, 0.13, 0.28, 0.85)
	draw_rect(r, bg)
	draw_rect(r, team_color.darkened(0.1), false, 1.0)
	var dot_c := Vector2(r.position.x + 25.0, r.position.y + r.size.y * 0.5)
	draw_circle(dot_c, 9.0, team_color)
	_text(Vector2(r.position.x + 44.0, r.position.y + r.size.y * 0.5 + 23.0 * rs * 0.36), title,
			int(round(23.0 * rs)), Color.WHITE)
	var sub_fs := int(round(16.0 * rs))
	_text(Vector2(r.position.x + 150.0, r.position.y + r.size.y * 0.5 + sub_fs * 0.36),
			"总击杀 %d" % kills, sub_fs, team_color.lightened(0.3))
	var eco := "团队经济 %s" % _fmt_gold(gold)
	var ew := _f.get_string_size(eco, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_fs).x
	_text(Vector2(r.position.x + r.size.x - 16.0 - ew, r.position.y + r.size.y * 0.5 + sub_fs * 0.36),
			eco, sub_fs, GOLD_COLOR)

func _fmt_gold(g: int) -> String:
	if g >= 1000:
		return "%.1fk" % (g / 1000.0)
	return str(g)

# 英雄卡（同 host _create_hero_card 的字号/配色：740×122×rs、队色底与左描边）
func _draw_row(p: Vector2, r: Dictionary, mine: bool, rs: float) -> void:
	var name := str(r["name"])
	var lv := int(r["lv"])
	var k := int(r["k"]); var d := int(r["d"]); var a := int(r["a"])
	var gold := int(r["gold"])
	var eq: Array = r.get("equip", [])
	var team_color := BLUE_TEAM if mine else RED_TEAM
	var ncol := Color(0.35, 0.95, 1.0) if mine else Color(1.0, 0.45, 0.38)
	var card := Rect2(p, Vector2(_cw, _row_h() - 8.0))
	draw_rect(card, Color(0.2, 0.05, 0.06, 0.72) if not mine else Color(0.05, 0.08, 0.16, 0.72))
	draw_rect(card, team_color.darkened(0.2), false, 1.0)
	draw_rect(Rect2(p, Vector2(3.0, card.size.y)), team_color.darkened(0.2))   # 左侧 3px 队色条
	# 第一行：名字 + 等级（host 20×rs）
	_text(p + Vector2(18.0, 24.0 + 20.0 * rs * 0.72), "%s  Lv.%d" % [name, lv], int(round(20.0 * rs)), ncol)
	# 第二行：KDA（host 16×rs 绿）+ 经济（host 16×rs 金）
	var kda_fs := int(round(16.0 * rs))
	_text(p + Vector2(18.0, 24.0 + 20.0 * rs * 0.72 + 30.0 * rs),
			"KDA %.2f  ·  %d/%d/%d" % [float(k + a) / maxf(1.0, float(d)), k, d, a], kda_fs, Color(0.45, 0.95, 0.6))
	var gold_txt := "%d 金" % gold
	var gw := _f.get_string_size(gold_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(27.0 * rs))).x
	_text(p + Vector2(_cw - 18.0 - gw, 24.0 + 27.0 * rs * 0.72), gold_txt, int(round(27.0 * rs)), GOLD_COLOR)
	# 第三行：装备槽（同 host 42×42 方格，已购金色）
	for s in range(6):
		var filled := s < eq.size() and str(eq[s]) != ""
		var slot := Rect2(p + Vector2(18.0 + s * 50.0, card.size.y - 54.0), Vector2(42.0, 42.0))
		draw_rect(slot, Color(0.9, 0.88, 0.6, 0.15) if filled else Color(1, 1, 1, 0.04))
		draw_rect(slot, GOLD_COLOR if filled else Color(1, 1, 1, 0.16), false, 1.0)

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo):
		return
	if (ev as InputEventKey).keycode == KEY_ESCAPE and visible:
		UiKit.hide_panel(self, 0.12)
		queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if not press:
		return
	var p: Vector2 = (ev as InputEventMouseButton).position
	var rows: Array = _payload.get("rows", [])
	var my := 0; var en := 0
	for r in rows:
		if int(r["team"]) == Config.Team.PLAYER: my += 1
		else: en += 1
	var n_rows := maxi(my, en)
	var vp := get_viewport()
	var area := vp.get_visible_rect().size
	var panel := _panel_rect(area, n_rows)
	if not panel.has_point(p):
		visible = false
		queue_redraw()
