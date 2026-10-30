class_name NetKillFeed extends Control
## P3e 击杀战报带：监听 host 经 NetSession 广播的 show_kill_feed 全部战报（击杀/终结/名刀/塔/龙/出兵）。
## 复刻主机 UI_Manager._create_kill_feed_panel：顶部中央（自顶向下 y=100×ui_scale 起）、黑底 0.6 半透明衬底、
## 三段式（actor / desc / victim）字号 16×ui_scale，配色与主机一致：actor 敌橙/其余青，
## victim 己青/敌橙/中立紫；1.0s 停留 + 0.5s 淡出。

const SHOW := 1.0
const FADE := 0.5
const GAP := 4.0              # 同 host HBoxContainer 默认 separation
const BASE_Y := 100.0         # 同 host panel.position = Vector2(-100, 100) * ui_scale
const FONT_SZ := 16.0         # 同 host _apply_label_style(..., 16, ...)
const ENEMY_C := Color(1.0, 0.33, 0.264)
const CYAN_C := Color(0.0, 0.886, 1.0)
const PURPLE_C := Color(0.75, 0.5, 1.0)

var _items: Array = []   # [{actor:String, a_team:int, desc:String, victim:String, v_team:int, born:int(msec)}]
var _f := UiKit.font()

# 同主机 UI_Manager.ui_scale()
func _us() -> float:
	return UiKit.scale()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	NetSession.net_kill_feed.connect(_on_kill_feed)

func _on_kill_feed(actor: String, actor_team: int, desc: String, victim: String, victim_team: int) -> void:
	# host 开局链经战报通道转发的纯音频（SFX:: 前缀）：剥掉本地播、不画横幅
	if desc.begins_with(SfxManager.ANN_PREFIX):
		SfxManager.play_announce(desc.trim_prefix(SfxManager.ANN_PREFIX))
		return
	SfxManager.play_feed(actor, actor_team, desc, victim, victim_team)
	_items.push_back({"actor": actor, "a_team": actor_team, "desc": desc,
			"victim": victim, "v_team": victim_team, "born": Time.get_ticks_msec()})
	if _items.size() > 5:
		_items.remove_at(0)
	queue_redraw()

func _seg_w(txt: String, sz: float) -> float:
	return _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x

func _draw() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var area := vp.get_visible_rect().size
	var us := _us()
	var fs := FONT_SZ * us
	var gap := GAP * us
	var line_h := fs * 1.55
	var now := Time.get_ticks_msec()
	var rows: Array = []
	for it in _items:
		var age := (now - int(it["born"])) * 0.001
		if age < SHOW + FADE:
			rows.append(it)
	_items = rows
	if rows.is_empty():
		return
	# 单行文本总宽（actor [desc] victim 三段式），逐行自顶向下铺开
	for ri in range(rows.size()):
		var it: Dictionary = rows[ri]
		var a: String = str(it["actor"])
		var d: String = str(it["desc"])
		var v: String = str(it["victim"])
		var a_team: int = int(it["a_team"])
		var v_team: int = int(it["v_team"])
		var ac := ENEMY_C if a_team == Config.Team.ENEMY else CYAN_C
		var dc := Color(1, 1, 1)
		var vc := CYAN_C if v_team == Config.Team.PLAYER else (ENEMY_C if v_team == Config.Team.ENEMY else PURPLE_C)
		var segs: Array = []
		if a != "":
			segs.append([a, ac])
		segs.append([d, dc])
		if v != "":
			segs.append([v, vc])
		var total := 0.0
		for s in segs:
			total += _seg_w(str(s[0]), fs)
		total += gap * (segs.size() - 1)
		var x := (area.x - total) * 0.5
		var y := BASE_Y * us + ri * line_h
		var age := (now - int(it["born"])) * 0.001
		var alpha := 1.0 if age < SHOW else clampf(1.0 - (age - SHOW) / FADE, 0.0, 1.0)
		# 衬底（同 host _apply_panel_style(panel, 0.6)）
		draw_rect(Rect2(x - 10.0 * us, y - fs * 0.92, total + 20.0 * us, fs * 1.62),
				Color(0, 0, 0, 0.6 * alpha))
		var sh := Color(0, 0, 0, 0.5 * alpha)
		var baseline := y + fs * 0.86
		for s in segs:
			var txt: String = str(s[0])
			var col: Color = s[1]
			col.a = alpha
			draw_string(_f, Vector2(x + 2, baseline + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, sh)
			draw_string(_f, Vector2(x, baseline), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += _seg_w(txt, fs) + gap

