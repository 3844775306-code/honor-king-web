class_name NetKillFeed extends Control
## P3e 击杀战报带：监听 host 经 NetSession 广播的 show_kill_feed 全部战报（击杀/终结/名刀/塔/龙/出兵）。
## 复刻主机 UI_Manager 战报：顶部中央、黑底 0.6 半透明衬底、三段式（actor / desc / victim）字号 18×ui_scale。
## 每条只播 1 条，固定 2.0s（1.75s 停留 + 0.25s 淡出），多条累计进队列延迟播出（与 host 同规则）。
## 英雄头像带“原初印记等级”符文环；有助攻时第二行画助攻者头像（仅推塔时可能含小兵）。

const EntityIconArtScript = preload("res://scripts/ui/EntityIconArt.gd")

const SHOW := 1.75
const FADE := 0.25           # 合计 2.0s/条
const GAP := 10.0            # 同 host HBoxContainer separation
const BASE_Y := 154.0        # 同 host KF_TOP（原始像素，不乘 ui_scale）
const KF_W := 620.0          # 同 host KF_W
const KF_H := 64.0           # 同 host KF_H
const ASSIST_H := 44.0       # 同 host KF_ASSIST_H
const FONT_SZ := 24.0        # 同 host _apply_label_style(..., 24, ...)
const ENEMY_C := Color(1.0, 0.33, 0.264)
const CYAN_C := Color(0.0, 0.886, 1.0)
const PURPLE_C := Color(0.75, 0.5, 1.0)

var _q: Array = []            # 等待播出的战报
var _cur: Dictionary = {}     # 当前正在播的 1 条
var _f := UiKit.font()

# 同主机 UI_Manager.ui_scale()
func _us() -> float:
	return UiKit.scale()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	NetSession.net_kill_feed.connect(_on_kill_feed)

## 塔/水晶警报中性文案 → 本地阵营加「我方/敌方」；非我方警报直接丢弃（红方视角）
func _localize(desc: String, victim_team: int) -> String:
	if desc.find("正在被攻击") < 0:
		return desc
	var base := desc
	if base.begins_with("我方") or base.begins_with("敌方"):
		base = base.substr(2)
	return ("我方" if victim_team == int(Config.player_team) else "敌方") + base


func _is_foreign_warning(desc: String, victim_team: int) -> bool:
	return desc.find("正在被攻击") >= 0 and victim_team >= 0 and victim_team != int(Config.player_team)


func _on_kill_feed(actor: String, actor_team: int, desc: String, victim: String, victim_team: int,
		assists: Array, a_mark: int, v_mark: int) -> void:
	if _is_foreign_warning(desc, victim_team):
		return
	desc = _localize(desc, victim_team)
	# host 开局链经战报通道转发的纯音频（SFX:: 前缀）：剥掉本地播、不画横幅
	if desc.begins_with(SfxManager.ANN_PREFIX):
		SfxManager.play_announce(desc.trim_prefix(SfxManager.ANN_PREFIX))
		return
	SfxManager.play_feed(actor, actor_team, desc, victim, victim_team)
	push(actor, actor_team, desc, victim, victim_team, assists, a_mark, v_mark)
	_q.append({"actor": actor, "a_team": actor_team, "desc": desc, "victim": victim,
		"v_team": victim_team, "assists": assists, "a_mark": a_mark, "v_mark": v_mark})
	if _q.size() > 12:
		_q.pop_front()
	if _cur.is_empty():
		_next()

## 外部注入一条战报（回放录像使用；不依赖 NetSession 信号）
func push(actor: String, actor_team: int, desc: String, victim: String, victim_team: int,
		assists: Array = [], a_mark: int = 0, v_mark: int = 0) -> void:
	if _is_foreign_warning(desc, victim_team):
		return
	desc = _localize(desc, victim_team)
	_q.append({"actor": actor, "a_team": actor_team, "desc": desc, "victim": victim,
		"v_team": victim_team, "assists": assists, "a_mark": a_mark, "v_mark": v_mark})
	if _q.size() > 12:
		_q.pop_front()
	if _cur.is_empty():
		_next()



## 回放倒退重建：清空队列与当前条
func clear() -> void:
	_q.clear()
	_cur = {}
	queue_redraw()


func _next() -> void:
	if _q.is_empty():
		_cur = {}
		queue_redraw()
		return
	_cur = _q.pop_front()
	_cur["born"] = Time.get_ticks_msec()
	queue_redraw()

func _process(_delta: float) -> void:
	if _cur.is_empty():
		return
	var age := (Time.get_ticks_msec() - int(_cur["born"])) * 0.001
	if age >= SHOW + FADE:
		_next()
	queue_redraw()

func _seg_w(txt: String, sz: float) -> float:
	return _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x

func _draw() -> void:
	var vp := get_viewport()
	if vp == null or _cur.is_empty():
		return
	var area := vp.get_visible_rect().size
	var us := _us()
	var fs := FONT_SZ * us
	var gap := GAP * us
	var now := Time.get_ticks_msec()
	var it: Dictionary = _cur
	var a: String = str(it["actor"])
	var d: String = str(it["desc"])
	var v: String = str(it["victim"])
	var a_team: int = int(it["a_team"])
	var v_team: int = int(it["v_team"])
	var assists: Array = it.get("assists", [])
	var ac := _team_col(a_team)
	var dc := Color(1, 1, 1)
	var vc := _team_col(v_team)
	var a_sp := EntityIconArtScript.spec_for(a)
	var v_sp := EntityIconArtScript.spec_for(v)
	if not a_sp.is_empty():
		a_sp["mark"] = int(it.get("a_mark", 0))
	if not v_sp.is_empty():
		v_sp["mark"] = int(it.get("v_mark", 0))
	var icon_w := 40.0 * us
	var segs: Array = []
	if a != "":
		if not a_sp.is_empty():
			segs.append({"icon": a_sp, "col": ac})
		segs.append({"txt": EntityIconArtScript.display_name(a), "col": ac})
	segs.append({"txt": d, "col": dc})
	if v != "":
		if not v_sp.is_empty():
			segs.append({"icon": v_sp, "col": vc})
		segs.append({"txt": EntityIconArtScript.display_name(v), "col": vc})
	var total := 0.0
	for s in segs:
		total += icon_w if s.has("icon") else _seg_w(str(s["txt"]), fs)
	total += gap * (segs.size() - 1)
	var box_h := (KF_H + (ASSIST_H if not assists.is_empty() else 0.0)) * us
	var y := BASE_Y * us
	var age := (now - int(it["born"])) * 0.001
	var alpha := 1.0 if age < SHOW else clampf(1.0 - (age - SHOW) / FADE, 0.0, 1.0)
	var box_w := KF_W * us
	var box := Rect2((area.x - box_w) * 0.5, y, box_w, box_h)
	draw_style_box(_row_style(alpha), box)
	var x := area.x * 0.5 - total * 0.5
	var sh := Color(0, 0, 0, 0.5 * alpha)
	var row_h := KF_H * us
	var baseline := y + (row_h - (_f.get_ascent(fs) + _f.get_descent(fs))) * 0.5 + _f.get_ascent(fs)
	for s in segs:
		if s.has("icon"):
			EntityIconArtScript.draw(self, Vector2(x + icon_w * 0.5, y + row_h * 0.5),
				icon_w * 0.5, s["icon"], s["col"])
			x += icon_w + gap
			continue
		var txt: String = str(s["txt"])
		var col: Color = s["col"]
		col.a = alpha
		draw_string(_f, Vector2(x + 2, baseline + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
		draw_string(_f, Vector2(x, baseline), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += _seg_w(txt, fs) + gap
	# 第二行：助攻者头像（英雄带原初印记符文环；推塔时可能含小兵）
	if assists.is_empty():
		return
	var a_fs := 16.0 * us
	var a_icon := 30.0 * us
	var row2_cy := y + row_h + ASSIST_H * us * 0.5
	var aw := _seg_w("助攻", a_fs)
	var icons_w := 0.0
	for row in assists:
		var sp := EntityIconArtScript.spec_for(str(row[0]))
		if not sp.is_empty():
			icons_w += a_icon + gap
	var sx := area.x * 0.5 - (aw + gap + icons_w - gap) * 0.5
	var cap_col := Color(0.72, 0.80, 0.94, 0.9 * alpha)
	draw_string(_f, Vector2(sx, row2_cy + a_fs * 0.36), "助攻", HORIZONTAL_ALIGNMENT_LEFT, -1, a_fs, cap_col)
	sx += aw + gap
	for row in assists:
		var nm := str(row[0])
		var sp := EntityIconArtScript.spec_for(nm)
		if sp.is_empty():
			continue
		sp["mark"] = int(row[2]) if (row as Array).size() > 2 else 0
		var col2 := _team_col(int(row[1]))
		col2.a = alpha
		EntityIconArtScript.draw(self, Vector2(sx + a_icon * 0.5, row2_cy), a_icon * 0.5, sp, col2)
		sx += a_icon + gap

func _team_col(team: int) -> Color:
	# 与单机 UI_Manager._feed_team_color 同口径：按本地阵营判我方/敌方（红方客户端自动翻转）
	if team == Config.Team.PLAYER or team == Config.Team.ENEMY:
		return CYAN_C if Config.is_ally(team) else ENEMY_C
	return PURPLE_C

# 同 host _apply_panel_style(panel, 0.6)：圆角玻璃 + 投影；淡出按 0.1 档缓存样式，避免每帧分配
var _styles: Dictionary = {}
func _row_style(alpha: float) -> StyleBoxFlat:
	var k := int(round(clampf(alpha, 0.0, 1.0) * 10.0))
	if not _styles.has(k):
		var sb := UiKit.flat(0.62 * float(k) / 10.0, 12, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0), 10.0, 6.0)
		sb.shadow_color = Color(0, 0, 0, 0.45 * float(k) / 10.0)
		_styles[k] = sb
	return _styles[k]

