class_name NetResultPanel extends Control
## 联机结算页：与单机 ResultsPanel 同版式（总览 / 数据 / 回放 三页签 + 双列英雄卡 + 中央 VS/MVP + 数据表）。
## 数据：host game_over 广播 rows（含昵称/总经济/装备/承伤/治疗/控制/推塔/野区/补刀）。
## rs 与 host ResultsPanel._ui_scale() 同公式 = clampf(视口宽/2400, 1.0, 1.2) * 1.7。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")

const PANEL_W := 1860.0
const COL_W := 740.0
const BLUE_TEAM := Color(0.0, 0.886, 1.0, 1.0)
const RED_TEAM := Color(1.0, 0.33, 0.264, 1.0)
const GOLD_COLOR := Color(1.0, 0.84, 0.0, 1.0)

const STAT_META := [
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

var _payload := {}
var defer := false          # true=先播终局演出，播完再显示结算页（NetClientBattle 控制）
var _f := UiKit.font()
var _pw: float = PANEL_W
var _cw: float = COL_W
var _backdrop: Control = null
var _rank_result: Dictionary = {}
var _tab := 0               # 0=总览 1=数据 2=回放
var _tab_rects: Array = []
var _btn_rects: Array = []

func _rs() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.7
	return clampf(vp.get_visible_rect().size.x / 2400.0, 1.0, 1.2) * 1.7

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = UiKit.make_backdrop(self, BLUE_TEAM, 0.8)
	_backdrop.z_index = -1
	visible = false
	NetSession.net_game_over.connect(_on_result)

func _on_result(p: Dictionary) -> void:
	if defer:
		_payload = p
		return
	_payload = p
	BattleHistory.record(p, "联机")
	var win := int(p.get("winner", -1)) == Config.Team.PLAYER
	if _backdrop != null:
		_backdrop.set("accent", BLUE_TEAM if win else RED_TEAM)
	UiKit.show_panel(self, 0.20)
	SfxManager.play_announce("victory" if win else "defeat")
	if _rank_result.is_empty() and not ("--net-test" in OS.get_cmdline_user_args()):
		_rank_result = RankSystem.apply_result(win, false)
	queue_redraw()

## 终局演出播完后由 NetClientBattle 调用：解除延迟并正式显示结算页
func show_deferred() -> void:
	defer = false
	if not _payload.is_empty():
		_on_result(_payload)

func _text(pos: Vector2, txt: String, sz: int, col: Color) -> void:
	draw_string(_f, pos + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.55))
	draw_string(_f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)

func _text_r(right_x: float, y: float, txt: String, sz: int, col: Color) -> void:
	var w := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_text(Vector2(right_x - w, y), txt, sz, col)

func _fmt_gold(g: int) -> String:
	if g >= 1000:
		return "%.1fk" % (g / 1000.0)
	return str(g)

func _rows_of(p: Dictionary) -> Array:
	var r: Array = p.get("rows", [])
	return r if r is Array else []

# ---------------- 评分 / 奖牌（与 host ResultsPanel、BattleManager._pm_rating 同公式） ----------------
func _rating(r: Dictionary) -> float:
	var team := int(r.get("team", 0))
	var rows := _rows_of(_payload)
	var mx_k := 1
	var mx_dmg := 1.0
	var mx_gold := 1
	var mx_taken := 1.0
	var tot_k := 0
	var mx_d := 1
	for o in rows:
		if int((o as Dictionary).get("team", -1)) != team:
			continue
		mx_k = maxi(mx_k, int(o.get("k", 0)))
		mx_dmg = maxf(mx_dmg, float(o.get("dmg", 0)))
		mx_gold = maxi(mx_gold, int(o.get("tgold", o.get("gold", 0))))
		mx_taken = maxf(mx_taken, float(o.get("taken", 0)))
		tot_k += int(o.get("k", 0))
		mx_d = maxi(mx_d, int(o.get("d", 0)))
	var kill_score := float(r.get("k", 0)) / float(mx_k) * 100.0
	var assist_score := float(r.get("a", 0)) / float(maxi(1, tot_k)) * 100.0
	var death_score := maxf(0.0, 1.0 - float(r.get("d", 0)) / float(maxi(1, mx_d))) * 100.0
	var gold_score := float(r.get("tgold", r.get("gold", 0))) / float(mx_gold) * 100.0
	var dmg_score := float(r.get("dmg", 0)) / mx_dmg * 100.0
	var taken_score := float(r.get("taken", 0)) / mx_taken * 100.0
	var part := float(int(r.get("k", 0)) + int(r.get("a", 0))) / float(maxi(1, tot_k)) * 100.0
	return clampf(kill_score * 0.15 + assist_score * 0.10 + death_score * 0.05
		+ gold_score * 0.15 + dmg_score * 0.25 + taken_score * 0.10 + part * 0.20, 0.0, 100.0)

func _grade(score: float) -> String:
	if score >= 90.0: return "超神"
	if score >= 80.0: return "MVP"
	if score >= 70.0: return "优秀"
	if score >= 60.0: return "良好"
	if score >= 50.0: return "一般"
	return "低迷"

func _grade_color(score: float) -> Color:
	if score >= 90.0: return Color(1.0, 0.5, 0.4)
	if score >= 80.0: return GOLD_COLOR
	if score >= 70.0: return Color(0.6, 0.9, 0.5)
	if score >= 60.0: return Color(0.5, 0.8, 0.9)
	return Color(0.7, 0.72, 0.8)

func _medal(score: float) -> int:
	if score >= 78.0: return 0
	if score >= 64.0: return 1
	if score >= 52.0: return 2
	return -1

func _medal_name(i: int) -> String:
	match i:
		0: return "金牌"
		1: return "银牌"
		2: return "铜牌"
	return ""

func _medal_color(i: int) -> Color:
	match i:
		0: return Color(1.0, 0.84, 0.32)
		1: return Color(0.86, 0.91, 1.0)
		2: return Color(0.92, 0.64, 0.38)
	return Color(0.7, 0.74, 0.84)

func _team_sums(team: int) -> Dictionary:
	var kills := 0
	var gold := 0
	var rows := _rows_of(_payload)
	for r in rows:
		if int((r as Dictionary)["team"]) == team:
			kills += int(r["k"])
			gold += int(r.get("tgold", r.get("gold", 0)))
	return {"kills": kills, "gold": gold}

func _mvp_of(rows: Array) -> Dictionary:
	var best := {}
	var best_r := -1.0
	for r in rows:
		var rr := _rating(r)
		if rr > best_r:
			best_r = rr
			best = r
	return best

# ---------------- 版式 ----------------
func _panel_rect(area: Vector2, n_rows: int) -> Rect2:
	_pw = maxf(1200.0, area.x - 64.0)
	_cw = maxf(380.0, (_pw - 406.0) * 0.5)
	var ph := 250.0 + float(n_rows) * 130.0 + 60.0
	ph = minf(ph, area.y - 48.0)
	return Rect2((area.x - _pw) * 0.5, (area.y - ph) * 0.5, _pw, ph)

func _draw() -> void:
	if not visible:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	var rs := _rs()
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.035, 0.04, 0.08, 0.32))
	var rows := _rows_of(_payload)
	var win: int = int(_payload.get("winner", -1))
	var is_win := win == Config.Team.PLAYER
	var my_rows: Array = []
	var en_rows: Array = []
	for r in rows:
		if int((r as Dictionary)["team"]) == Config.Team.PLAYER:
			my_rows.append(r)
		else:
			en_rows.append(r)
	var n_rows := maxi(my_rows.size(), en_rows.size())
	var panel := _panel_rect(area, n_rows)
	draw_rect(panel, Color(0.015, 0.035, 0.08, 0.92))
	var accent := Color(0.3, 0.95, 0.85, 0.9) if is_win else Color(0.95, 0.32, 0.3, 0.9)
	draw_rect(panel, accent, false, 4.0)
	var result_color := BLUE_TEAM if is_win else RED_TEAM
	# 胜负徽章
	var badge_c := panel.position + Vector2(20.0 + 35.0, 24.0 + 35.0)
	draw_circle(badge_c, 35.0, Color(0.06, 0.07, 0.11, 0.95))
	draw_arc(badge_c, 33.5, 0.0, TAU, 48, result_color, 3.0)
	var bg_fs := 43
	var bg_w := _f.get_string_size("胜" if is_win else "负", HORIZONTAL_ALIGNMENT_CENTER, -1, bg_fs).x
	_text(Vector2(badge_c.x - bg_w * 0.5, badge_c.y + bg_fs * 0.36), "胜" if is_win else "负", bg_fs, result_color)
	# 标题 + 副标题
	var title_x := panel.position.x + 126.0
	_text(Vector2(title_x, panel.position.y + 24.0 + 40.0 * rs * 0.72), "对局胜利" if is_win else "对局失败",
		int(round(40.0 * rs)), result_color)
	var my_sum := _team_sums(Config.Team.PLAYER)
	var en_sum := _team_sums(Config.Team.ENEMY)
	_text(Vector2(title_x, panel.position.y + 24.0 + 40.0 * rs * 0.72 + 36.0 * rs),
		"我方击杀 %d : %d  ·  团队经济 我方 %s / 敌方 %s" % [int(my_sum["kills"]), int(en_sum["kills"]),
		_fmt_gold(int(my_sum["gold"])), _fmt_gold(int(en_sum["gold"]))],
		int(round(17.0 * rs)), Color(0.75, 0.8, 0.9))
	_text_r(panel.position.x + _pw - 24.0, panel.position.y + 52.0,
		"对局时长 %02d:%02d" % [int(float(_payload.get("dur", 0.0))) / 60, int(float(_payload.get("dur", 0.0))) % 60],
		int(round(18.0 * rs)), Color(0.7, 0.76, 0.9))
	if not _rank_result.is_empty():
		var rank_txt := "排位 %s" % str(_rank_result.get("new_label", ""))
		if bool(_rank_result.get("promoted", false)):
			rank_txt += "  ↑"
		elif bool(_rank_result.get("demoted", false)):
			rank_txt += "  ↓"
		elif bool(_rank_result.get("floor_protected", false)):
			rank_txt += "  段位保护"
		_text(Vector2(title_x, panel.position.y + 24.0 + 40.0 * rs * 0.72 + 36.0 * rs + 28.0 * rs),
			rank_txt, int(round(18.0 * rs)), GOLD_COLOR)
	# 页签（总览 / 数据 / 回放）
	_tab_rects.clear()
	var tab_y := panel.position.y + 112.0
	var tx := panel.position.x + 24.0
	var tab_names := ["总 览", "数 据", "回 放"]
	for i in range(3):
		var tr := Rect2(tx, tab_y, 132.0, 42.0)
		_tab_rects.append(tr)
		var on := i == _tab
		draw_rect(tr, Color(0.10, 0.14, 0.24, 0.95) if not on else Color(0.16, 0.22, 0.36, 0.98))
		draw_rect(tr, GOLD_COLOR if on else Color(1, 1, 1, 0.16), false, 2.0 if on else 1.0)
		var tw := _f.get_string_size(tab_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		_text(Vector2(tr.position.x + (tr.size.x - tw) * 0.5, tr.position.y + 28.0), tab_names[i], 20,
			Color.WHITE if on else Color(0.72, 0.78, 0.9))
		tx += 144.0
	var content_y := tab_y + 58.0
	if _tab == 0:
		_draw_overview(panel, content_y, my_rows, en_rows, is_win, rs)
	elif _tab == 1:
		_draw_data(panel, content_y, my_rows, en_rows, rs)
	else:
		_draw_replay(panel, content_y, rs)
	# 底部按钮（同 host ResultsPanel：再来一局 / 返回大厅）
	_btn_rects.clear()
	var btn_y := panel.position.y + panel.size.y - 56.0
	var bw2 := 200.0
	var bh2 := 40.0
	var bx2 := panel.position.x + _pw * 0.5 - bw2 - 12.0
	_draw_btn(Rect2(bx2, btn_y, bw2, bh2), "再来一局", GOLD_COLOR)
	_btn_rects.append(["play_again", Rect2(bx2, btn_y, bw2, bh2)])
	bx2 += bw2 + 24.0
	_draw_btn(Rect2(bx2, btn_y, bw2, bh2), "返回大厅", BLUE_TEAM)
	_btn_rects.append(["back_lobby", Rect2(bx2, btn_y, bw2, bh2)])
	_text(Vector2(panel.position.x + 24.0, panel.position.y + panel.size.y - 26.0),
		"Esc / 点击面板外关闭", int(round(15.0 * rs)), Color(1, 1, 1, 0.55))

func _draw_overview(panel: Rect2, y: float, my_rows: Array, en_rows: Array, is_win: bool, rs: float) -> void:
	var lx := panel.position.x + 12.0
	var rx := panel.position.x + _pw - 12.0 - _cw
	var hh := 52.0
	_draw_team_header(Rect2(lx, y, _cw, hh), "我方", BLUE_TEAM, int(_team_sums(Config.Team.PLAYER)["kills"]),
		int(_team_sums(Config.Team.PLAYER)["gold"]), false, rs)
	_draw_team_header(Rect2(rx, y, _cw, hh), "敌方", RED_TEAM, int(_team_sums(Config.Team.ENEMY)["kills"]),
		int(_team_sums(Config.Team.ENEMY)["gold"]), true, rs)
	# 中央 VS + MVP 头像
	var cx := panel.position.x + _pw * 0.5
	draw_circle(Vector2(cx, y + 24.0), 22.0, Color(0.06, 0.07, 0.11, 0.95))
	draw_arc(Vector2(cx, y + 24.0), 20.5, 0.0, TAU, 40, GOLD_COLOR if is_win else Color(0.6, 0.65, 0.75), 3.5)
	var vs_w := _f.get_string_size("VS", HORIZONTAL_ALIGNMENT_CENTER, -1, 17).x
	_text(Vector2(cx - vs_w * 0.5, y + 24.0 + 6.0), "VS", 17, GOLD_COLOR if is_win else Color.WHITE)
	var my_mvp := _mvp_of(my_rows)
	var en_mvp := _mvp_of(en_rows)
	if not my_mvp.is_empty():
		_draw_mvp_mini(Vector2(cx, y + 78.0), my_mvp, true, 150.0)
	if not en_mvp.is_empty():
		_draw_mvp_mini(Vector2(cx, y + 176.0), en_mvp, false, 150.0)
	# 英雄卡行
	var rows_start := y + hh + 10.0
	var row_h := minf(132.0, (panel.position.y + panel.size.y - 40.0 - rows_start) / 5.0)
	for i in range(5):
		var py := rows_start + float(i) * row_h
		if i < my_rows.size():
			_draw_hero_card(Rect2(lx, py, _cw, row_h - 8.0), my_rows[i], true, rs)
		if i < en_rows.size():
			_draw_hero_card(Rect2(rx, py, _cw, row_h - 8.0), en_rows[i], false, rs)

func _draw_team_header(r: Rect2, title: String, team_color: Color, kills: int, gold: int, is_enemy: bool, rs: float) -> void:
	var bg := Color(0.28, 0.08, 0.08, 0.85) if is_enemy else Color(0.08, 0.13, 0.28, 0.85)
	draw_rect(r, bg)
	draw_rect(r, team_color.darkened(0.1), false, 1.0)
	draw_circle(Vector2(r.position.x + 25.0, r.position.y + r.size.y * 0.5), 9.0, team_color)
	_text(Vector2(r.position.x + 44.0, r.position.y + r.size.y * 0.5 + 8.0), title, int(round(22.0 * rs)), Color.WHITE)
	var sub_fs := int(round(15.0 * rs))
	_text(Vector2(r.position.x + 150.0, r.position.y + r.size.y * 0.5 + 6.0),
		"总击杀 %d" % kills, sub_fs, team_color.lightened(0.3))
	_text_r(r.position.x + r.size.x - 16.0, r.position.y + r.size.y * 0.5 + 6.0,
		"团队经济 %s" % _fmt_gold(gold), sub_fs, GOLD_COLOR)

# MVP 小卡（头像 + 王冠 + 名字/评分）
func _draw_mvp_mini(center: Vector2, row: Dictionary, mine: bool, wide: float) -> void:
	var col := BLUE_TEAM if mine else RED_TEAM
	var w := wide
	var r := Rect2(center.x - w * 0.5, center.y - 44.0, w, 88.0)
	draw_rect(r, Color(0.10, 0.14, 0.24, 0.95))
	draw_rect(r, GOLD_COLOR, false, 1.5)
	HeroArt.draw_portrait(self, Vector2(r.position.x + 34.0, r.position.y + 44.0), 26.0, str(row.get("name", "")), col)
	var nm := str(row.get("name", ""))
	_text(Vector2(r.position.x + 68.0, r.position.y + 30.0), nm, 17, Color.WHITE)
	_text(Vector2(r.position.x + 68.0, r.position.y + 52.0), "MVP  %.0f分" % _rating(row), 15, GOLD_COLOR)
	draw_circle(Vector2(r.position.x + w - 18.0, r.position.y + 16.0), 10.0, Color(0.11, 0.07, 0.02, 0.97))
	draw_arc(Vector2(r.position.x + w - 18.0, r.position.y + 16.0), 9.0, 0.0, TAU, 24, GOLD_COLOR, 2.0)
	_text(Vector2(r.position.x + w - 24.0, r.position.y + 21.0), "M", 12, GOLD_COLOR)

# 英雄卡（头像 + 名字/昵称 + 等级 + KDA + 经济 + 评分评级 + 奖牌 + 装备图标）
func _draw_hero_card(r: Rect2, row: Dictionary, mine: bool, rs: float) -> void:
	var team_color := BLUE_TEAM if mine else RED_TEAM
	var score := _rating(row)
	draw_rect(r, Color(0.2, 0.05, 0.06, 0.72) if not mine else Color(0.05, 0.08, 0.16, 0.72))
	draw_rect(r, team_color.darkened(0.2), false, 1.0)
	draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), team_color.darkened(0.1))
	# 头像
	HeroArt.draw_portrait(self, Vector2(r.position.x + 44.0, r.position.y + r.size.y * 0.5), 30.0,
		str(row.get("name", "")), team_color)
	# 名字 + 昵称 + 等级
	var nm := str(row.get("name", ""))
	var nick := str(row.get("nick", ""))
	var label := nm if nick == "" or nick == nm else "%s · %s" % [nm, nick]
	_text(Vector2(r.position.x + 82.0, r.position.y + 26.0), label, int(round(19.0 * rs)), Color(0.35, 0.95, 1.0) if mine else Color(1.0, 0.45, 0.38))
	_text(Vector2(r.position.x + 82.0, r.position.y + 48.0), "Lv.%d" % int(row.get("lv", 1)), 15, Color(0.8, 0.85, 0.95))
	# KDA + 评分
	_text(Vector2(r.position.x + 130.0, r.position.y + 48.0),
		"KDA %.2f  %d/%d/%d" % [float(int(row.get("k", 0)) + int(row.get("a", 0))) / maxf(1.0, float(row.get("d", 0))),
		int(row.get("k", 0)), int(row.get("d", 0)), int(row.get("a", 0))], 15, Color(0.45, 0.95, 0.6))
	_text(Vector2(r.position.x + 82.0, r.position.y + 72.0),
		"%s %.0f分" % [_grade(score), score], 16, _grade_color(score))
	# 经济 + 奖牌
	_text_r(r.position.x + r.size.x - 16.0, r.position.y + 30.0, "%s 金" % _fmt_gold(int(row.get("tgold", row.get("gold", 0)))),
		int(round(21.0 * rs)), GOLD_COLOR)
	var mi := _medal(score)
	if mi >= 0:
		var mc := _medal_color(mi)
		var mr := Rect2(r.position.x + r.size.x - 92.0, r.position.y + 44.0, 76.0, 22.0)
		draw_rect(mr, Color(mc.r, mc.g, mc.b, 0.20))
		draw_rect(mr, mc, false, 1.0)
		_text(Vector2(mr.position.x + 8.0, mr.position.y + 16.0), _medal_name(mi), 13, mc)
	# 装备图标（6 格，已购显示品质色）
	var eq: Array = row.get("equip", [])
	var slot_s := 30.0
	for s in range(6):
		var sr := Rect2(r.position.x + 82.0 + s * (slot_s + 6.0), r.position.y + r.size.y - slot_s - 10.0, slot_s, slot_s)
		var item_id := str(eq[s]) if s < eq.size() else ""
		if item_id != "":
			var it := ItemDatabase.get_item(item_id)
			UiKit.item_icon(self, sr, int(it.get("tier", 1)), str(it.get("name", item_id)))
		else:
			draw_rect(sr, Color(1, 1, 1, 0.04))
			draw_rect(sr, Color(1, 1, 1, 0.14), false, 1.0)

# 数据页：左右两列，每列 5 行英雄 × 11 项数据（值文本 + 队内归一化底色）
func _draw_data(panel: Rect2, y: float, my_rows: Array, en_rows: Array, rs: float) -> void:
	var lx := panel.position.x + 12.0
	var rx := panel.position.x + _pw - 12.0 - _cw
	var label_w := 150.0
	var col_w := (_cw - label_w) / float(STAT_META.size())
	var row_h := 42.0
	_draw_data_column(Rect2(lx, y, _cw, panel.position.y + panel.size.y - 40.0 - y), my_rows, BLUE_TEAM, rs, label_w, col_w, row_h)
	_draw_data_column(Rect2(rx, y, _cw, panel.position.y + panel.size.y - 40.0 - y), en_rows, RED_TEAM, rs, label_w, col_w, row_h)

func _draw_data_column(area: Rect2, rows: Array, team_color: Color, rs: float, label_w: float, col_w: float, row_h: float) -> void:
	if rows.is_empty():
		return
	# 表头：数据名（大字图标字形）
	var hy := area.position.y + 6.0
	for i in range(STAT_META.size()):
		var cx := area.position.x + label_w + col_w * (float(i) + 0.5)
		_text(Vector2(cx - 12.0, hy + 16.0), str(STAT_META[i][0]), 17, STAT_META[i][1])
	var ry := hy + 26.0
	var vals := _stat_values(rows)
	for ri in range(rows.size()):
		var r: Dictionary = rows[ri]
		if ri >= 5:
			break
		var yy := ry + float(ri) * row_h
		draw_rect(Rect2(area.position.x, yy, area.size.x, row_h - 4.0), Color(0.05, 0.08, 0.16, 0.55) if team_color == BLUE_TEAM else Color(0.2, 0.05, 0.06, 0.55))
		# 名字
		HeroArt.draw_portrait(self, Vector2(area.position.x + 20.0, yy + row_h * 0.5), 14.0, str(r.get("name", "")), team_color)
		_text(Vector2(area.position.x + 38.0, yy + row_h * 0.5 + 5.0), str(r.get("name", "")), 15, Color.WHITE)
		# 每项数据：底色条（队内归一化）+ 数值
		for ci in range(STAT_META.size()):
			var cx2 := area.position.x + label_w + col_w * float(ci)
			var v := float(vals[ci][ri])
			var mx: float = maxf(1.0, float(vals[ci][0]))
			for o in rows:
				mx = maxf(mx, float(o["_stat"][ci]))
			var bw := col_w - 6.0
			draw_rect(Rect2(cx2 + 3.0, yy + 8.0, bw, row_h - 20.0), Color(1, 1, 1, 0.05))
			draw_rect(Rect2(cx2 + 3.0, yy + 8.0, bw * clampf(v / mx, 0.0, 1.0), row_h - 20.0),
				Color(STAT_META[ci][1].r, STAT_META[ci][1].g, STAT_META[ci][1].b, 0.35))
			_text(Vector2(cx2 + 6.0, yy + row_h * 0.5 + 4.0), _fmt_stat(ci, v), 13, Color(0.92, 0.95, 1.0))

# 每行英雄 11 项统计（与 host STAT_META 顺序一致）
func _stat_values(rows: Array) -> Array:
	var out: Array = []
	for ci in range(STAT_META.size()):
		var arr: Array = []
		for r in rows:
			if not (r as Dictionary).has("_stat"):
				(r as Dictionary)["_stat"] = _stat_array(r)
			arr.append(float((r as Dictionary)["_stat"][ci]))
		out.append(arr)
	return out

func _stat_array(r: Dictionary) -> Array:
	var k := int(r.get("k", 0))
	var d := int(r.get("d", 0))
	var a := int(r.get("a", 0))
	var dmg := float(r.get("dmg", 0))
	var gold := float(r.get("tgold", r.get("gold", 0)))
	var team_rows := _rows_of(_payload)
	var tot_k := 0
	for o in team_rows:
		if int((o as Dictionary).get("team", -1)) == int(r.get("team", 0)):
			tot_k += int(o.get("k", 0))
	var part := float(k + a) / float(maxi(1, tot_k)) * 100.0
	var conv := dmg / maxf(1.0, gold) * 100.0
	var tank_per_death := float(r.get("taken", 0)) / float(maxi(1, d))
	return [dmg, float(r.get("taken", 0)), gold, part, conv, tank_per_death,
		float(r.get("jungle", 0)), float(r.get("lh", 0)), float(r.get("cc", 0)) / 10.0,
		float(r.get("heal", 0)), float(r.get("turret", 0))]

func _fmt_stat(ci: int, v: float) -> String:
	match ci:
		2, 6, 7: return str(int(v))
		8: return "%.1fs" % v
		3, 4: return "%.0f%%" % v
	return str(int(v))

func _draw_btn(r: Rect2, label: String, accent: Color) -> void:
	draw_rect(r, Color(0.08, 0.11, 0.18, 0.95))
	draw_rect(r, Color(accent.r, accent.g, accent.b, 0.85), false, 2.0)
	var fs := 20
	var w := _f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_text(Vector2(r.position.x + (r.size.x - w) * 0.5, r.position.y + 28.0), label, fs, accent)


func _on_play_again() -> void:
	# 联机局需重新建房/加入：统一直回大厅（与返回大厅同路径，避免单方重开造成状态错乱）
	_on_back_lobby()


func _on_back_lobby() -> void:
	visible = false
	if NetSession.mode != NetSession.Mode.NONE:
		NetSession.disconnect_network()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _draw_replay(panel: Rect2, y: float, rs: float) -> void:
	var cx := panel.position.x + _pw * 0.5
	_text(Vector2(cx - 220.0, y + 60.0), "联机对局暂无回放录像", int(round(28.0 * rs)), Color(0.9, 0.94, 1.0))
	_text(Vector2(cx - 220.0, y + 100.0), "录像回放请在大厅「战绩」中查看单机/录像端保存的对局",
		int(round(17.0 * rs)), Color(0.7, 0.76, 0.9))

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo):
		return
	if (ev as InputEventKey).keycode == KEY_ESCAPE and visible:
		UiKit.hide_panel(self, 0.12)
		queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = mb.position
	for b in _btn_rects:
		if (b[1] as Rect2).has_point(p):
			if str(b[0]) == "play_again":
				_on_play_again()
			else:
				_on_back_lobby()
			return
	for i in range(_tab_rects.size()):
		if (_tab_rects[i] as Rect2).has_point(p):
			_tab = i
			queue_redraw()
			return
	var rows := _rows_of(_payload)
	var my := 0
	var en := 0
	for r in rows:
		if int((r as Dictionary)["team"]) == Config.Team.PLAYER:
			my += 1
		else:
			en += 1
	var vp := get_viewport()
	var area := vp.get_visible_rect().size
	var panel := _panel_rect(area, maxi(my, en))
	if not panel.has_point(p):
		visible = false
		queue_redraw()
