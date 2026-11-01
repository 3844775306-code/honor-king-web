# scripts/ui/HeroInfoControl.gd
class_name HeroInfoControl
extends Control
const MarkerIconScript = preload("res://scripts/ui/MarkerIcon.gd")
const BuffArt = preload("res://scripts/ui/BuffArt.gd")


var hero: Hero = null

var bar_width: float = 280.0
var bar_height: float = 28.0
var ring_radius: float = 24.0   # 经验等级圈半径（已放大并画在血条左端）





var _font_bold: FontVariation = null
var _status_peak: Dictionary = {}   # 状态图标时长弧的峰值，用于剩余时间进度

func _bold() -> Font:
	if _font_bold == null:
		var fv := FontVariation.new()
		fv.base_font = UiKit.font()
		fv.variation_embolden = 0.45
		_font_bold = fv
	return _font_bold if _font_bold != null else UiKit.font()

func _draw_text_shadow(f: Font, pos: Vector2, txt: String, align: int, width: float, fs: int, col: Color, outline_px: int) -> void:
	draw_string(f, pos + Vector2(1.2, 1.6), txt, align, width, fs, Color(0, 0, 0, 0.5))
	draw_string_outline(f, pos, txt, align, width, fs, outline_px, Color(0, 0, 0, 0.92))
	draw_string(f, pos, txt, align, width, fs, col)

# 经验等级圈（血条左端）：黑色底盘 + 灰色经验底环 + 金色经验弧 + 等级数字
func _draw_level_ring(c: Vector2, r: float, level_text: String, exp_ratio: float) -> void:
	draw_circle(c, r + 2.0, Color(0, 0, 0, 0.92))
	draw_circle(c, r - 1.0, Color(0.07, 0.08, 0.12, 0.95))
	draw_arc(c, r, 0.0, TAU, 32, Color.DIM_GRAY, 2.6)
	var end_angle: float = -PI / 2.0 + TAU * exp_ratio
	draw_arc(c, r, -PI / 2.0, end_angle, 32, UiKit.C_GOLD, 3.2)
	# 左上高光弧，和血条玻璃质感对齐
	draw_arc(c, r - 2.6, PI * 1.12, PI * 1.84, 20, Color(1, 1, 1, 0.22), 1.2)
	var fs := int(round(r * 0.82))
	var w := UiKit.font().get_string_size(level_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	_draw_text_shadow(_bold(), c + Vector2(-w * 0.5, fs * 0.36), level_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE, 4)

# 草丛隐藏图标：深色圆底 + 眼睛轮廓 + 红色斜杠（表示敌方看不到自己）
func _draw_hidden_badge(c: Vector2, s: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
	draw_circle(c, s * (1.18 + 0.06 * pulse), Color(0.30, 0.86, 1.0, 0.10 + 0.06 * pulse))
	draw_circle(c, s, Color(0.06, 0.09, 0.13, 0.90))
	draw_arc(c, s - 0.8, 0.0, TAU, 28, Color(0.55, 0.86, 0.98, 0.90), 1.6)
	var eye_col := Color(0.86, 0.96, 1.0, 0.95)
	var ew: float = s * 0.62
	var eh: float = s * 0.40
	var pts := PackedVector2Array()
	for i in range(13):
		var a: float = PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * ew, -sin(a) * eh))
	for i in range(13):
		var a2: float = PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a2) * ew, sin(a2) * eh))
	pts.append(pts[0])
	draw_polyline(pts, eye_col, 1.8)
	draw_circle(c, s * 0.20, eye_col)
	draw_line(c + Vector2(-ew * 1.15, eh * 1.5), c + Vector2(ew * 1.15, -eh * 1.5), Color(1.0, 0.40, 0.34, 0.95), 2.2)

# MVP 徽章：深底金边圆盘 + 金色王冠 + 呼吸光晕（替代原“MVP”文字角标）
func _draw_mvp_badge(c: Vector2, r: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = 0.5 + 0.5 * sin(t * 2.1)
	# 外发光（两层，随呼吸涨落）
	draw_circle(c, r * (1.46 + 0.08 * pulse), Color(1.0, 0.78, 0.30, 0.08 + 0.05 * pulse))
	draw_circle(c, r * 1.14, Color(1.0, 0.70, 0.22, 0.18))
	# 底盘 + 金边
	draw_circle(c, r, Color(0.11, 0.07, 0.02, 0.97))
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1.0, 0.80, 0.34, 0.95), 2.4)
	draw_arc(c, r * 0.84, 0.0, TAU, 40, Color(1.0, 0.72, 0.24, 0.45), 1.1)
	# 左上高光弧，给圆盘一点金属感
	draw_arc(c, r - 1.8, PI * 1.12, PI * 1.86, 24, Color(1.0, 0.96, 0.82, 0.85), 1.5)
	# 王冠本体（7 点折线：冠带两端 + 两个谷 + 三个峰）
	var s: float = r * 0.76
	var pts := PackedVector2Array([
		c + Vector2(-0.62, 0.26) * s, c + Vector2(-0.62, -0.18) * s,
		c + Vector2(-0.31, 0.04) * s, c + Vector2(0.0, -0.48) * s,
		c + Vector2(0.31, 0.04) * s, c + Vector2(0.62, -0.18) * s,
		c + Vector2(0.62, 0.26) * s,
	])
	draw_colored_polygon(pts, Color(1.0, 0.84, 0.38, 0.98))
	# 冠带 + 三颗宝石
	draw_rect(Rect2(c + Vector2(-0.62, 0.27) * s, Vector2(1.24, 0.17) * s), Color(1.0, 0.68, 0.16, 0.98))
	for i in range(3):
		var gx: float = -0.34 + 0.34 * i
		draw_circle(c + Vector2(gx, 0.355) * s, s * 0.08, Color(0.26, 0.09, 0.02, 0.95))
		draw_circle(c + Vector2(gx - s * 0.02, 0.34) * s, s * 0.035, Color(1.0, 0.95, 0.75, 0.9))
	# 峰顶亮点
	for p in [Vector2(-0.62, -0.18), Vector2(0.0, -0.48), Vector2(0.62, -0.18)]:
		draw_circle(c + p * s, s * 0.085, Color(1.0, 0.97, 0.86, 0.95))
	# 深色描边，让王冠在金色底上依然清晰
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.36, 0.19, 0.02, 0.85), 1.4)
	draw_rect(Rect2(c + Vector2(-0.62, 0.27) * s, Vector2(1.24, 0.17) * s), Color(0.36, 0.19, 0.02, 0.8), false, 1.0)
	# 右上角小闪光
	var sp: Vector2 = c + Vector2(r * 0.95, -r * 0.95)
	var a: float = 0.55 + 0.4 * pulse
	draw_line(sp + Vector2(-4.0, 0.0), sp + Vector2(4.0, 0.0), Color(1.0, 0.98, 0.9, a), 1.3)
	draw_line(sp + Vector2(0.0, -4.0), sp + Vector2(0.0, 4.0), Color(1.0, 0.98, 0.9, a), 1.3)


# 单个状态徽章：深色玻璃圆盘 + 状态专属矢量图标 + 剩余时长弧
func _draw_status_badge(c: Vector2, r: float, st: Dictionary) -> void:
	var key := str(st.get("key", ""))
	var col: Color = st.get("col", Color.WHITE)
	var rem := maxf(0.0, float(st.get("rem", 0.0)))
	var peak := maxf(float(_status_peak.get(key, rem)), rem)
	_status_peak[key] = peak
	var hard := bool(st.get("hard", false))
	if hard:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		draw_circle(c, r + 4.5, Color(col.r, col.g, col.b, 0.10 + 0.07 * pulse))
	draw_circle(c + Vector2(1.0, 1.8), r, Color(0.0, 0.0, 0.0, 0.42))
	draw_circle(c, r, Color(0.025, 0.035, 0.065, 0.96))
	draw_circle(c, r - maxf(1.6, r * 0.18), Color(col.r, col.g, col.b, 0.15))
	draw_arc(c, r, 0.0, TAU, 30, Color(col.r, col.g, col.b, 0.92), maxf(1.2, r * 0.16), true)
	draw_arc(c, r - 1.6, PI * 1.08, PI * 1.62, 12, Color(1, 1, 1, 0.30), 1.0, true)
	BuffArt.draw_buff(self, c, r * 0.62, key, col.lightened(0.18))
	if rem > 0.03 and peak > 0.15:
		var ratio := clampf(rem / peak, 0.0, 1.0)
		draw_arc(c, r + 2.6, -PI * 0.5, -PI * 0.5 + TAU * ratio, 30,
			Color(col.r, col.g, col.b, 0.78), 1.5, true)

# 血条上方图标带：标记图标与状态徽章合并到同一行，按可用宽度整体缩放，避免重叠/溢出
func _draw_icon_strip(cx: float, y: float, markers: Array, statuses: Array, hidden: bool) -> float:
	var items: Array = []
	for e in markers:
		items.append({"kind": 0, "e": e})
	for st in statuses:
		items.append({"kind": 1, "e": st})
	if hidden:
		items.append({"kind": 2, "e": {}})
	var n := items.size()
	if n == 0:
		_status_peak.clear()
		return y
	var gap := 4.0
	var radii: Array = []
	var sum_d := 0.0
	for it in items:
		var kind := int(it["kind"])
		var r := 18.0 if kind == 0 else (14.0 if kind == 1 else 13.0)
		radii.append(r)
		sum_d += r * 2.0
	var avail := maxf(40.0, size.x - 8.0)
	if sum_d + gap * float(n - 1) > avail:
		var sc := maxf(0.55, (avail - gap * float(n - 1)) / sum_d)
		for i in range(n):
			radii[i] = float(radii[i]) * sc
	var max_r := 0.0
	for r in radii:
		max_r = maxf(max_r, float(r))
	var row_h := max_r * 2.0 + 6.0
	var cy := y + row_h * 0.5
	var x := 0.0
	# 重新计算缩放后的总宽
	var total := 0.0
	for r in radii:
		total += float(r) * 2.0
	total += gap * float(n - 1)
	x = cx - total * 0.5
	var active := {}
	for i in range(n):
		var it: Dictionary = items[i]
		var r := float(radii[i])
		var c := Vector2(x + r, cy)
		var kind := int(it["kind"])
		if kind == 0:
			var e: Dictionary = it["e"]
			var sp: Dictionary = MarkerIconScript.spec(str(e.get("name", "")), str(e.get("type", "")))
			MarkerIconScript._draw_badge(self, c, r, sp["c"], str(sp["plate"]),
				str(sp["sym"]), int(e.get("count", 1)))
		elif kind == 1:
			var st: Dictionary = it["e"]
			active[str(st.get("key", ""))] = true
			_draw_status_badge(c, r, st)
		else:
			_draw_hidden_badge(c, r * 0.92)
		x += r * 2.0 + gap
	for k in _status_peak.keys():
		if not active.has(k):
			_status_peak.erase(k)
	return y + row_h + 2.0

func _ellipsize(txt: String, f: Font, fs: int, maxw: float) -> String:
	if maxw <= 1.0:
		return ""
	if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= maxw:
		return txt
	var out := txt
	while out.length() > 1 and f.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw:
		out = out.substr(0, out.length() - 1)
	return out + "…"


func _draw():
	if not hero: return
	var font = UiKit.font()  # 使用默认字体
	var center_x: float = size.x / 2.0
	var y := 24.0
	# ---- 标记图标 + 状态徽章：合并成一行，宽度不够时整体缩放，绝不与名字/AI 信息重叠 ----
	var mk_entries: Array = []
	for source in hero.get_marker_sources():
		mk_entries.append({"name": str(source.display_name), "count": hero.count_markers(source), "type": ""})
	for lm in hero.lyf_mark_summary():
		var lsrc = lm["source"]
		if lsrc == null or not is_instance_valid(lsrc):
			continue
		mk_entries.append({"name": str(lsrc.display_name), "count": int(lm["stacks"]), "type": "lyf"})
	var statuses: Array = []
	if hero.stun_timer > 0:
		statuses.append({"key": "stun", "col": Color(1.0, 0.86, 0.32), "rem": hero.stun_timer, "hard": true})
	if hero.knockup_timer > 0:
		statuses.append({"key": "knockup", "col": Color(1.0, 0.60, 0.24), "rem": hero.knockup_timer, "hard": true})
	if hero.bt_timer > 0:
		statuses.append({"key": "bt", "col": Color(1.0, 0.92, 0.58), "rem": hero.bt_timer})
	if hero.wd_timer > 0:
		statuses.append({"key": "wd", "col": Color(0.72, 0.55, 1.0), "rem": hero.wd_timer})
	if hero.slow_timer > 0:
		if hero.slow_amount > 0:
			statuses.append({"key": "slow", "col": Color(0.45, 0.70, 1.0), "rem": hero.slow_timer})
		else:
			statuses.append({"key": "hasten", "col": Color(0.45, 1.0, 0.62), "rem": hero.slow_timer})
	if hero.froze_timer > 0:
		statuses.append({"key": "froze", "col": Color(0.58, 0.94, 1.0), "rem": hero.froze_timer, "hard": true})
	if hero.suppress_timer > 0:
		statuses.append({"key": "suppress", "col": Color(0.76, 0.32, 0.88), "rem": hero.suppress_timer, "hard": true})
	if hero.silence_timer > 0:
		statuses.append({"key": "silence", "col": Color(0.88, 0.55, 1.0), "rem": hero.silence_timer})
	if hero.taiyi_protected and hero.taiyi_protect_timer > 0:
		statuses.append({"key": "shield", "col": Color(0.55, 1.0, 0.95), "rem": hero.taiyi_protect_timer})
	var hidden_in_bush: bool = hero.hidden_in_bush and Config.is_ally(hero.team)
	y = _draw_icon_strip(center_x, y, mk_entries, statuses, hidden_in_bush)

	# ---- 名字：只占一行；AI 决策另起紧凑徽章，不再塞进名字多行文本 ----
	# 英雄名称 + 玩家/AI 昵称同时显示；昵称与英雄名相同（或为空）时不重复
	var name_str: String = hero.display_name
	if hero.player_name != "" and hero.player_name != hero.display_name:
		name_str += " · " + hero.player_name
	var ai_label := ""
	var ai_col := Color(0.52, 0.78, 1.0)
	if hero.is_ai:
		var ai = null
		for child in hero.get_children():
			if child is HeroAI:
				ai = child
				break
		if ai:
			var state_name := ""
			match ai.state:
				0: state_name = "推线"
				1: state_name = "打野"
				2: state_name = "撤退"
				5: state_name = "回城"
				4: state_name = "防守"
			match ai.state:
				0: ai_col = Color(0.45, 0.90, 1.0)
				1: ai_col = Color(0.72, 0.58, 1.0)
				2: ai_col = Color(1.0, 0.46, 0.38)
				4: ai_col = Color(1.0, 0.78, 0.34)
				5: ai_col = Color(0.56, 0.70, 1.0)
			var lane_name := ""
			match ai.lane:
				AiConfig.Lane.FARM: lane_name = "发育"
				AiConfig.Lane.MID: lane_name = "中"
				AiConfig.Lane.CLASH: lane_name = "对抗"
				AiConfig.Lane.JUNGLE: lane_name = "野"
			var phase_name := ""
			if ai.state == 1:
				match ai.jungle_strategy.current_phase:
					0: phase_name = "发育路野区"
					1: phase_name = "对抗路野区"
					2: phase_name = "蹭线"
			var parts: Array = []
			if lane_name != "": parts.append(lane_name)
			if state_name != "": parts.append(state_name)
			if phase_name != "": parts.append(phase_name)
			if hero.manual_target and is_instance_valid(hero.manual_target):
				parts.append("→ " + str(hero.manual_target.display_name))
			ai_label = " · ".join(parts)
	var name_fs := 28
	# 英雄名+昵称较长时缩一号字，尽量让两者都完整显示
	if font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x > size.x - 8.0:
		name_fs = 22
	var name_txt := _ellipsize(name_str, font, name_fs, size.x - 8.0)
	var name_base := y + font.get_ascent(name_fs)
	_draw_text_shadow(_bold(), Vector2(0.0, name_base), name_txt, HORIZONTAL_ALIGNMENT_CENTER,
		size.x, name_fs, Color.WHITE, 4)
	y = name_base + font.get_descent(name_fs) + 1.0

	# ---- AI 决策胶囊：单行、限宽省略，和名字/血条之间各留 1~3px ----
	if ai_label != "":
		var afs := 13
		var chip_h := 19.0
		var max_w := size.x - 10.0
		var tw := font.get_string_size(ai_label, HORIZONTAL_ALIGNMENT_LEFT, -1, afs).x
		var chip_w := minf(max_w, tw + 20.0)
		ai_label = _ellipsize(ai_label, font, afs, chip_w - 20.0)
		var cx0: float = center_x - chip_w * 0.5
		draw_style_box(UiKit.flat(0.88, 9, 1, Color(ai_col.r, ai_col.g, ai_col.b, 0.45),
			Color(0.035, 0.05, 0.085, 0.86), 0.0, 0.0), Rect2(cx0, y, chip_w, chip_h))
		draw_circle(Vector2(cx0 + 9.0, y + chip_h * 0.5), 2.6, ai_col)
		UiKit.text(self, Vector2(cx0 + 15.0, y + 13.5), ai_label, afs, Color(0.92, 0.95, 1.0),
			HORIZONTAL_ALIGNMENT_LEFT, chip_w - 18.0)
		y += chip_h + 2.0

	# ---- 复活倒计时条 ----
	if hero.is_reviving and hero.revive_timer > 0:
		var rv_w = 120.0
		var rv_h = 4.0
		var rv_x = center_x - rv_w / 2.0
		var rv_ratio = 1.0 - hero.revive_timer / 2.0
		draw_rect(Rect2(rv_x, y, rv_w, rv_h), Color.BLACK)
		draw_rect(Rect2(rv_x, y, rv_w * rv_ratio, rv_h), Color.GREEN)
		y += rv_h + 3.0

	var y_offset := y + 2.0

	# ---- MVP标识：血条右侧金色王冠徽章（右侧让位给等级圈） ----
	if hero.is_mvp:
		var _r: float = bar_height * 0.66
		_draw_mvp_badge(Vector2(center_x + bar_width / 2.0 + 12.0 + _r, y_offset + bar_height * 0.5), _r)

	# ---- 英雄血条（投影 / 双层描边 / 分段渐变 / 玻璃高光 / 护盾段 / 低血脉冲） ----
	var max_hp: float = maxf(1.0, hero.actual_max_health)
	var hp: float = clampf(hero.health, 0.0, max_hp)
	var shield: float = maxf(0.0, hero.shield_remaining)
	var bx: float = center_x - bar_width * 0.5
	var bh: float = bar_height
	var hw: float = (hp / max_hp) * bar_width
	var _bm := get_tree().get_first_node_in_group("battle_manager") as BattleManager
	var _is_self: bool = _bm != null and _bm.hero != null and is_instance_valid(_bm.hero) and _bm.hero == hero
	# 玩家自己的血条恒为绿色（与阵营无关），其余按敌友相对上色
	var tc: Color = Color(0.33, 0.95, 0.42) if _is_self else (Color(0.0, 0.886, 1.0) if Config.is_ally(hero.team) else Color(1.0, 0.33, 0.264))
	# 补刀提示（放宽）：屏幕内敌方英雄血量低于玩家一次普攻（按护甲减免）→ 血条转灰白
	if not _is_self and _bm != null and _bm.hero != null and is_instance_valid(_bm.hero) and not Config.is_ally(hero.team) and hp > 0.0:
		var _e_res: float = maxf(0.0, float(hero.armor) - float(_bm.hero.flat_phys_pen))
		var _aa: float = float(_bm.hero.actual_attack_damage) * (1.0 - _e_res / (_e_res + 602.0))
		if hp < _aa:
			tc = Color(0.90, 0.92, 0.95)

	# ---- 经验等级圈：血条左端、与血条同高居中 ----
	var _exp_ratio: float = 1.0
	if hero.exp_to_next > 0:
		_exp_ratio = clampf(float(hero.exp) / float(hero.exp_to_next), 0.0, 1.0)
	_draw_level_ring(Vector2(bx - 10.0 - ring_radius, y_offset + bh * 0.5), ring_radius, str(hero.level), _exp_ratio)

	# 投影（两层）
	draw_rect(Rect2(bx + 3.0, y_offset + 5.0, bar_width, bh), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(bx + 1.5, y_offset + 2.5, bar_width, bh), Color(0, 0, 0, 0.34))
	# 外框：深底 + 队伍色细边
	# 血条 / 法力条 / 被动状态条共用一个外框（先画整块底板，消除“割裂感”）
	var s_entries: Array = _status_entries()
	var s_h := 13.0
	var s_gap := 1.5
	var s_total: float = 0.0
	if not s_entries.is_empty():
		s_total = float(s_entries.size()) * s_h + float(s_entries.size() - 1) * s_gap
	var mana_h2: float = bh * 0.5 if hero.actual_mana_max > 0.0 else 0.0
	var block_h: float = bh + 3.0
	if mana_h2 > 0.0:
		block_h += mana_h2 + 3.0
	if s_total > 0.0:
		block_h += 2.0 + s_total
	draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, block_h + 6.0), Color(0.02, 0.03, 0.06, 0.96))
	draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, block_h + 6.0), Color(tc.r, tc.g, tc.b, 0.55), false, 1.5)
	# 空槽（上亮下暗）
	draw_rect(Rect2(bx, y_offset, bar_width, bh), Color(0.10, 0.11, 0.15, 0.97))
	draw_rect(Rect2(bx, y_offset, bar_width, bh * 0.5), Color(0.17, 0.18, 0.22, 0.9))

	# 残血拖尾（掉血后浅色回落）
	if _hp_lag > hp + 0.5:
		var lagw: float = (_hp_lag / max_hp) * bar_width
		draw_rect(Rect2(bx + hw, y_offset, lagw - hw, bh), Color(1.0, 0.93, 0.82, 0.34))
		draw_rect(Rect2(bx + lagw - 2.0, y_offset, 2.0, bh), Color(1.0, 0.9, 0.75, 0.85))

	# 渐变填充
	if hw > 0.5:
		var bands: int = 5
		var c_top: Color = tc.lightened(0.35)
		var c_bot: Color = tc.darkened(0.42)
		for bi in range(bands):
			var q: float = float(bi) / float(bands - 1)
			draw_rect(Rect2(bx, y_offset + bh * float(bi) / float(bands), hw, bh / float(bands) + 1.0),
				c_top.lerp(c_bot, q))
		# 顶部玻璃高光 + 次高光带 + 底部暗边
		draw_rect(Rect2(bx, y_offset, hw, maxf(2.0, bh * 0.18)), Color(1, 1, 1, 0.50))
		draw_rect(Rect2(bx, y_offset + maxf(2.0, bh * 0.18), hw, 1.5), Color(1, 1, 1, 0.14))
		draw_rect(Rect2(bx, y_offset + bh - 1.5, hw, 1.5), Color(0, 0, 0, 0.35))

	# 李元芳暗印预判：爆炸将造成的实际伤害 → 当前血条右端相应段染黄（扣除护盾，封顶当前血量）
	if hero.lyf_mark_summary().size() > 0:
		var lyf_pred := 0.0
		for lm in hero.lyf_mark_summary():
			lyf_pred += float(lm["pred"])
		var lyf_doom := clampf(lyf_pred - shield, 0.0, hp)
		var lyf_doom_w: float = (lyf_doom / max_hp) * bar_width
		if lyf_doom_w > 0.5:
			draw_rect(Rect2(bx + hw - lyf_doom_w, y_offset, lyf_doom_w, bh), Color(1.0, 0.88, 0.18, 0.9))

	# 护盾段（淡蓝 + 斜纹 + 白色左隔线）
	var sw: float = minf((shield / max_hp) * bar_width, bar_width - hw)
	if sw > 0.5:
		draw_rect(Rect2(bx + hw, y_offset, sw, bh), Color(0.62, 0.84, 1.0, 0.95))
		var hatch: int = int(sw / 7.0)
		for hi in range(hatch):
			var hx: float = bx + hw + 2.0 + float(hi) * 7.0
			draw_line(Vector2(hx, y_offset + bh), Vector2(hx + 5.0, y_offset), Color(1, 1, 1, 0.30), 1.0)
		draw_rect(Rect2(bx + hw, y_offset, sw, 2.0), Color(1, 1, 1, 0.42))
		draw_rect(Rect2(bx + hw, y_offset, 1.5, bh), Color(1, 1, 1, 0.9))

	# 受伤闪橙
	if damage_flash_timer > 0:
		var fr: float = damage_flash_timer / 0.5
		var flash_width: float = (damage_flash_amount / max_hp) * bar_width * fr
		draw_rect(Rect2(bx + hw, y_offset, flash_width, bh), Color(1.0, 0.62, 0.12, 0.92))
		draw_rect(Rect2(bx + hw, y_offset, flash_width, 2.0), Color(1.0, 0.95, 0.8, 0.8))

	# 回血暗色（回血时在血条内出现的暗影）
	if heal_timer > 0:
		var hr: float = heal_timer / 0.5
		var heal_width: float = (heal_amount / max_hp) * bar_width
		draw_rect(Rect2(bx + hw - heal_width, y_offset, heal_width, bh),
			Color(tc.r * 0.6, tc.g * 0.6, tc.b * 0.6, hr))

	# 刻度（每 1000 血：暗线 + 右侧微高光）
	var segs: int = int(floor(max_hp / 1000.0))
	for si in range(1, segs + 1):
		var sx: float = bx + (1000.0 * float(si) / max_hp) * bar_width
		draw_line(Vector2(sx, y_offset + 1.0), Vector2(sx, y_offset + bh - 1.0), Color(0, 0, 0, 0.55), 1.0)
		draw_line(Vector2(sx + 1.0, y_offset + 1.0), Vector2(sx + 1.0, y_offset + bh - 1.0), Color(1, 1, 1, 0.22), 1.0)

	# 低血脉冲红光
	var frac: float = hp / max_hp
	if frac < 0.3 and frac > 0.0:
		var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, bh + 4.0),
			Color(1.0, 0.25, 0.18, 0.30 + 0.45 * pulse), false, 2.0)

	# 顶部白线压边
	draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, bh + 4.0), Color(1, 1, 1, 0.16), false, 1.0)
	y_offset += bh + 3.0

	# ---- 法力条（同一质感，半高） ----
	var mana_max: float = hero.actual_mana_max
	if mana_max > 0:
		var mh: float = bh * 0.5
		var mw: float = clampf(hero.mana / mana_max, 0.0, 1.0) * bar_width
		draw_rect(Rect2(bx, y_offset, bar_width, mh), Color(0.06, 0.08, 0.14, 0.95))
		if mw > 0.5:
			var mb: int = 3
			for mi in range(mb):
				var mq: float = float(mi) / float(mb - 1)
				draw_rect(Rect2(bx, y_offset + mh * float(mi) / float(mb), mw, mh / float(mb) + 1.0),
					Color(0.16, 0.42, 0.95).lerp(Color(0.05, 0.16, 0.55), mq))
			draw_rect(Rect2(bx, y_offset, mw, 1.5), Color(1, 1, 1, 0.45))
		draw_rect(Rect2(bx, y_offset, bar_width, mh), Color(0.35, 0.62, 1.0, 0.5), false, 1.0)
		y_offset += mh + 3.0
	# ---- 被动状态条：紧贴法力条下沿 2px，与血条同一外框 ----
	_draw_status_bars(center_x, y_offset + 2.0)



# ---- 血条下方状态条：统一样式，替代原先各英雄手绘的 4px 黑条 ----
var _status_sb_cache: Dictionary = {}

func _status_entry(label: String, ratio: float, col: Color, segments: int, value: String, pulse: bool = false) -> Dictionary:
	return {
		"label": label,
		"ratio": clampf(ratio, 0.0, 1.0),
		"color": col,
		"segments": segments,
		"value": value,
		"pulse": pulse,
	}

func _status_entries() -> Array:
	return status_entries_of(hero)


## 状态条（附魔/枪意/炸弹/回城/传送等）：单机绘制与联机快照共用同一份数据
static func status_entries_of(hero) -> Array:
	var out: Array = []
	if hero == null:
		return out
	match hero.display_name:
		"吕布":
			if hero.stat_timer > 0.0:
				out.append(_status_entry_s("附魔", hero.stat_timer / 8.0, Color(0.74, 0.38, 1.0), 0, "%.1fs" % hero.stat_timer, true))
		"王昭君":
			if hero.wangzhaojun_combat_timer > 0.0:
				out.append(_status_entry_s("冰霜", hero.wangzhaojun_combat_timer / 5.0, Color(0.42, 0.80, 1.0), 0, "%.1fs" % hero.wangzhaojun_combat_timer, true))
		"马超":
			if hero.stat_timer > 0.0:
				out.append(_status_entry_s("枪意", hero.stat_timer / 8.0, Color(0.72, 0.94, 1.0), 0, "%.1fs" % hero.stat_timer, true))
		"不知火舞":
			if hero.stat_timer > 0.0:
				out.append(_status_entry_s("忍锋", hero.stat_timer / 5.0, Color(1.0, 0.52, 0.28), 0, "%.1fs" % hero.stat_timer, true))
		"沈梦溪":
			if hero.stat > 0.0:
				out.append(_status_entry_s("炸弹", hero.stat / 10.0, Color(1.0, 0.66, 0.18), 10, "%d/10" % int(round(hero.stat)), false))
		"狄仁杰":
			if hero.stat > 0.0:
				out.append(_status_entry_s("被动", hero.stat / 5.0, Color(1.0, 0.78, 0.30), 5, "%d/5" % int(round(hero.stat)), false))
		"元流之子":
			if hero.yuanliu_flow > 0:
				out.append(_status_entry_s("流", hero.yuanliu_flow / 9.0, Color(0.30, 0.94, 0.82), 9, "%d/9" % hero.yuanliu_flow, false))
		"英睿":
			if hero.yingrui_aa_count > 0:
				out.append(_status_entry_s("冰爽", hero.yingrui_aa_count / 3.0, Color(0.62, 0.86, 1.0), 3, "%d/3" % hero.yingrui_aa_count, false))
		"后羿":
			if hero.stat > 0.0:
				out.append(_status_entry_s("惩戒", hero.stat / 3.0, Color(1.0, 0.56, 0.18), 3, "%d/3" % int(round(hero.stat)), false))
		"鲁班七号":
			if hero.luban_passive_stacks > 0:
				out.append(_status_entry_s("扫射", hero.luban_passive_stacks / 5.0, Color(1.0, 0.70, 0.24), 5, "%d/5" % hero.luban_passive_stacks, false))
		"李白":
			if hero.libai_xia_active:
				if hero.libai_xia_timer > 0.0:
					out.append(_status_entry_s("侠客行", hero.libai_xia_timer / 5.0, Color(0.78, 0.92, 1.0), 0, "%.1fs" % hero.libai_xia_timer, true))
			elif hero.libai_sword_auras > 0:
				out.append(_status_entry_s("剑意", hero.libai_sword_auras / 4.0, Color(0.62, 0.88, 1.0), 4, "%d/4" % hero.libai_sword_auras, false))
		"太乙真人":
			if hero.taiyi_q_channeling and hero.taiyi_q_timer > 0.0:
				out.append(_status_entry_s("引爆", hero.taiyi_q_timer / 5.0, Color(0.80, 0.50, 1.0), 0, "%.1fs" % hero.taiyi_q_timer, true))
	if hero.is_teleporting:
		# teleport_progress 已是 0..1 的传送进度（Hero 内按 TELEPORT_DURATION 累加），
		# 不能再除一次时长，否则读条只会走到约 1/4 且看起来按回城时长算。
		var tr := clampf(hero.teleport_progress, 0.0, 1.0)
		out.append(_status_entry_s("传送", tr, Color(0.34, 0.72, 1.0), 0, "%d%%" % int(tr * 100.0), true))
	if hero.is_recalling:
		var rr := clampf(1.0 - hero.recall_timer / Hero.RECALL_DURATION, 0.0, 1.0)
		out.append(_status_entry_s("回城", rr, Color(0.50, 0.96, 0.72), 0, "%.1fs" % hero.recall_timer, true))
	return out


static func _status_entry_s(label: String, ratio: float, col: Color, segments: int, value: String, pulse: bool = false) -> Dictionary:
	return {
		"label": label,
		"ratio": clampf(ratio, 0.0, 1.0),
		"color": col,
		"segments": segments,
		"value": value,
		"pulse": pulse,
	}

func _status_style(bg: Color, border: Color, border_w: int, radius: int, glow: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%s" % [bg.to_html(true), border.to_html(true), border_w, radius, glow.to_html(true)]
	if _status_sb_cache.has(key):
		return _status_sb_cache[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 4
	sb.anti_aliasing = true
	if glow.a > 0.0:
		sb.shadow_color = Color(glow.r, glow.g, glow.b, 0.36)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2.ZERO
	_status_sb_cache[key] = sb
	return sb

func _draw_status_bar(bx: float, y: float, sh: float, e: Dictionary) -> void:
	var w := bar_width
	var col: Color = e["color"]
	var ratio: float = e["ratio"]
	var fillw := w * ratio
	# 槽（上亮下暗，与血条同一质感）
	draw_rect(Rect2(bx, y, w, sh), Color(0.055, 0.068, 0.10, 0.96))
	draw_rect(Rect2(bx, y, w, sh * 0.5), Color(0.085, 0.10, 0.14, 0.90))
	# 填充：三段渐变 + 顶部高光 + 亮端
	if fillw > 0.5:
		var bands := 3
		var c_top: Color = col.lightened(0.30)
		var c_bot: Color = Color(col.r * 0.45, col.g * 0.45, col.b * 0.45, 1.0)
		for bi in range(bands):
			var q: float = float(bi) / float(bands - 1)
			draw_rect(Rect2(bx, y + sh * float(bi) / float(bands), fillw, sh / float(bands) + 1.0), c_top.lerp(c_bot, q))
		draw_rect(Rect2(bx, y, fillw, 2.0), Color(1, 1, 1, 0.42))
		var cap_a := 0.62
		if e["pulse"]:
			cap_a = 0.48 + 0.34 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006))
		draw_rect(Rect2(bx + fillw - 2.5, y + 1.5, 2.5, sh - 3.0), Color(1, 1, 1, cap_a))
	# 分段刻度
	var segs: int = e["segments"]
	if segs > 1:
		for i in range(1, segs):
			var sx := bx + w * float(i) / float(segs)
			draw_line(Vector2(sx, y + 1.5), Vector2(sx, y + sh - 1.5), Color(0, 0, 0, 0.52), 1.0)
	# 标签 / 数值（内描边字，与血条同风格）
	var fs := 12
	_draw_text_shadow(_bold(), Vector2(bx + 7.0, y + sh - 2.5), str(e["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.96, 1.0, 0.96), 3)
	_draw_text_shadow(_bold(), Vector2(bx + 7.0, y + sh - 2.5), str(e["value"]), HORIZONTAL_ALIGNMENT_RIGHT, w - 14.0, fs, Color(0.88, 0.93, 1.0, 0.94), 3)

func _draw_status_bars(cx: float, top: float) -> void:
	var entries := _status_entries()
	if entries.is_empty():
		return
	var sh := 13.0
	var gap := 1.5
	var bx := cx - bar_width * 0.5
	for i in range(entries.size()):
		_draw_status_bar(bx, top + float(i) * (sh + gap), sh, entries[i])

# 血量过渡
var damage_flash_amount: float = 0.0
var damage_flash_timer: float = 0.0
var heal_amount: float = 0.0
var heal_timer: float = 0.0
var previous_health: float = 100.0
var _hp_lag: float = -1.0   # 残血拖尾目标值

func _ready():
	# 上方文字×2 后内容明显变高，加大高度让世界锚点仍落在血条附近（MVP 角标仍左侧留白）
	custom_minimum_size = Vector2(bar_width + 240.0, 320)
	size = custom_minimum_size  # 显式定尺寸：绘制以 size/2 为中心，与 HUD 的居中定位保持一致
	set_process(true)
	if hero: previous_health = hero.health

func _process(delta):
	if not is_instance_valid(hero): return

	# 血量变化检测
	if hero.health < previous_health:
		damage_flash_amount = previous_health - hero.health
		damage_flash_timer = 0.5
		heal_amount = 0.0; heal_timer = 0.0
	elif hero.health > previous_health:
		heal_amount = hero.health - previous_health
		heal_timer = 0.5
		damage_flash_amount = 0.0; damage_flash_timer = 0.0
	previous_health = hero.health
	if _hp_lag < 0.0: _hp_lag = hero.health
	_hp_lag = lerpf(_hp_lag, hero.health, clampf(delta * 4.0, 0.0, 1.0))

	if damage_flash_timer > 0: damage_flash_timer -= delta
	if heal_timer > 0: heal_timer -= delta
	queue_redraw()



	
