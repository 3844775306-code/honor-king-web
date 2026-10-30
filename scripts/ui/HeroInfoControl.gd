# scripts/ui/HeroInfoControl.gd
class_name HeroInfoControl
extends Control
const MarkerIconScript = preload("res://scripts/ui/MarkerIcon.gd")


var hero: Hero = null

var bar_width: float = 280.0
var bar_height: float = 28.0
var ring_radius: float = 15.0





var _font_bold: FontVariation = null

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

func _draw():
	if not hero: return
	var font = UiKit.font()  # 使用默认字体
	var center_x = size.x / 2.0
	var y_offset = 0.0
	# ---- 标记图标（血条上方：每种标记一个专属图标，右上角数字=层数） ----
	var mk_entries: Array = []
	for source in hero.get_marker_sources():
		mk_entries.append({"name": str(source.display_name), "count": hero.count_markers(source), "type": ""})
	for lm in hero.lyf_mark_summary():
		var lsrc = lm["source"]
		if lsrc == null or not is_instance_valid(lsrc):
			continue
		mk_entries.append({"name": str(lsrc.display_name), "count": int(lm["stacks"]), "type": "lyf"})
	if not mk_entries.is_empty():
		y_offset = MarkerIconScript.draw_row(self, center_x, y_offset, mk_entries, 18.0)
	var status_texts = []
	if hero.stun_timer > 0:
		status_texts.append("[眩晕]")
	if hero.knockup_timer > 0:
		status_texts.append("[击飞]")
	if hero.bt_timer > 0:
		status_texts.append("[霸体]")
	if hero.wd_timer > 0:
		status_texts.append("[无法选中]")
	if hero.slow_timer > 0:
		if hero.slow_amount>0:
			status_texts.append("[减速]")
		else:
			status_texts.append("[加速]")
	if hero.froze_timer > 0:
		status_texts.append("[冰冻]")
	if hero.suppress_timer > 0:
		status_texts.append("[压制]")
	if hero.silence_timer > 0:
		status_texts.append("[沉默]")
	if hero.taiyi_protected and hero.taiyi_protect_timer > 0:
		status_texts.append("[太乙保护]")  # 护盾同时有进度条，文字作为辅助

	var status_str = " ".join(status_texts)
	if status_str != "":
		var status_size = 22
		var text_width = len(status_str) * 16  # 近似宽度
		_draw_text_shadow(_bold(), Vector2(center_x - text_width/2, y_offset), status_str,
					HORIZONTAL_ALIGNMENT_LEFT, -1, status_size, Color.YELLOW, 4)
		y_offset += 16
		# 复活倒计时条
	if hero.is_reviving and hero.revive_timer > 0:
		var rv_w = 120.0; var rv_h = 4.0
		var rv_x = center_x - rv_w / 2
		var rv_ratio = 1.0 - hero.revive_timer / 2.0
		draw_rect(Rect2(rv_x, y_offset, rv_w, rv_h), Color.BLACK)
		draw_rect(Rect2(rv_x, y_offset, rv_w * rv_ratio, rv_h), Color.GREEN)
		y_offset += rv_h + 4
	
	# ---- 等级圆环（黑色底） ----
	var ring_center = Vector2(center_x, y_offset + ring_radius + 2)
	draw_circle(ring_center, ring_radius + 2, Color.BLACK)  # 黑色底色
	var exp_ratio = float(hero.exp) / float(hero.exp_to_next) if hero.exp_to_next > 0 else 1.0
	exp_ratio = clamp(exp_ratio, 0.0, 1.0)
	draw_arc(ring_center, ring_radius, 0, 2*PI, 16, Color.DIM_GRAY, 2.0)
	var end_angle = -PI/2 + 2*PI * exp_ratio
	draw_arc(ring_center, ring_radius, -PI/2, end_angle, 16, UiKit.C_GOLD, 2.5)
	_draw_text_shadow(font, ring_center + Vector2(-6, 5), str(hero.level), HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color.WHITE, 3)
	# 名字字号×2（34）后需加大环底→名字基线间距，避免首行被圆环压住
	y_offset = ring_center.y + ring_radius + 34

	

	# ---- 名称 ----
	var name_str = hero.display_name   # 默认不显示具体血量数值
		# AI 决策信息追加
	if hero.is_ai:
		var ai = null
		for child in hero.get_children():
			if child is HeroAI:
				ai = child
				break
		if ai:
			var state_name = ""
			match ai.state:
				0: state_name = "推线"
				1: state_name = "打野"
				2: state_name = "撤退"
				5: state_name = "回城"
				4: state_name = "防守"
				
			var lane_name = ""
			match ai.lane:
				AiConfig.Lane.FARM: lane_name = "发育"
				AiConfig.Lane.MID: lane_name = "中"
				AiConfig.Lane.CLASH: lane_name = "对抗"
				AiConfig.Lane.JUNGLE: lane_name = "野"
			var target_text = ""
			if  hero.manual_target and is_instance_valid(hero.manual_target):
				target_text = " → " + hero.manual_target.display_name
			name_str += "\n[%s] %s %s" % [lane_name, state_name,  target_text]
			if ai.state == 1 :
				match ai.jungle_strategy.current_phase:
					0:name_str += "发育路野区"
					1:name_str += "对抗路野区"
					2:name_str += "蹭线"
	# 血条上方文字整体×2：名字/血量 17→34，行距按实际多行文本高度推进
	var _max_line := 0
	for _ln in name_str.split("\n"):
		_max_line = max(_max_line, len(_ln))
	_draw_text_shadow(_bold(), Vector2(center_x - _max_line * 8.0, y_offset), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE, 5)
	y_offset += font.get_multiline_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).y + 10

	# ---- MVP标识：当前全场MVP的血条左侧显示金色角标 ----
	if hero.is_mvp:
		var _tag_font_size := 24
		var _ts := font.get_string_size("MVP", HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size)
		var _tag_w := _ts.x + 12.0
		var _tag_h := bar_height + 2.0
		var _tag_x: float = center_x - bar_width / 2.0 - 8.0 - _tag_w
		var _tag_y: float = y_offset - 1.0
		draw_rect(Rect2(_tag_x, _tag_y, _tag_w, _tag_h), Color(0.98, 0.82, 0.2, 0.95))
		draw_rect(Rect2(_tag_x, _tag_y, _tag_w, _tag_h), Color(0.4, 0.28, 0.0, 1.0), false, 1.5)
		draw_string(font, Vector2(_tag_x + 6.0, _tag_y + _tag_h * 0.5 + _tag_font_size * 0.36), "MVP",
				HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_font_size, Color(0.1, 0.06, 0.0))

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

	# 投影（两层）
	draw_rect(Rect2(bx + 3.0, y_offset + 5.0, bar_width, bh), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(bx + 1.5, y_offset + 2.5, bar_width, bh), Color(0, 0, 0, 0.34))
	# 外框：深底 + 队伍色细边
	draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, bh + 4.0), Color(0.02, 0.03, 0.06, 0.96))
	draw_rect(Rect2(bx - 2.0, y_offset - 2.0, bar_width + 4.0, bh + 4.0), Color(tc.r, tc.g, tc.b, 0.55), false, 1.5)
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
	# ---- 血条下方状态条：统一玻璃槽 + 渐变填充 + 描边 + 标签/数值 ----
	y_offset += bar_height * 0.5 + 4.0
	_draw_status_bars(center_x, y_offset)



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
	var out: Array = []
	if not hero:
		return out
	match hero.display_name:
		"吕布":
			if hero.stat_timer > 0.0:
				out.append(_status_entry("附魔", hero.stat_timer / 8.0, Color(0.74, 0.38, 1.0), 0, "%.1fs" % hero.stat_timer, true))
		"王昭君":
			if hero.wangzhaojun_combat_timer > 0.0:
				out.append(_status_entry("冰霜", hero.wangzhaojun_combat_timer / 5.0, Color(0.42, 0.80, 1.0), 0, "%.1fs" % hero.wangzhaojun_combat_timer, true))
		"马超":
			if hero.stat_timer > 0.0:
				out.append(_status_entry("枪意", hero.stat_timer / 8.0, Color(0.72, 0.94, 1.0), 0, "%.1fs" % hero.stat_timer, true))
		"不知火舞":
			if hero.stat_timer > 0.0:
				out.append(_status_entry("忍锋", hero.stat_timer / 5.0, Color(1.0, 0.52, 0.28), 0, "%.1fs" % hero.stat_timer, true))
		"沈梦溪":
			if hero.stat > 0.0:
				out.append(_status_entry("炸弹", hero.stat / 10.0, Color(1.0, 0.66, 0.18), 10, "%d/10" % int(round(hero.stat)), false))
		"狄仁杰":
			if hero.stat > 0.0:
				out.append(_status_entry("被动", hero.stat / 5.0, Color(1.0, 0.78, 0.30), 5, "%d/5" % int(round(hero.stat)), false))
		"元流之子":
			if hero.yuanliu_flow > 0:
				out.append(_status_entry("流", hero.yuanliu_flow / 9.0, Color(0.30, 0.94, 0.82), 9, "%d/9" % hero.yuanliu_flow, false))
		"英睿":
			if hero.yingrui_aa_count > 0:
				out.append(_status_entry("冰爽", hero.yingrui_aa_count / 3.0, Color(0.62, 0.86, 1.0), 3, "%d/3" % hero.yingrui_aa_count, false))
		"后羿":
			if hero.stat > 0.0:
				out.append(_status_entry("惩戒", hero.stat / 3.0, Color(1.0, 0.56, 0.18), 3, "%d/3" % int(round(hero.stat)), false))
		"鲁班七号":
			if hero.luban_passive_stacks > 0:
				out.append(_status_entry("扫射", hero.luban_passive_stacks / 5.0, Color(1.0, 0.70, 0.24), 5, "%d/5" % hero.luban_passive_stacks, false))
		"李白":
			if hero.libai_xia_active:
				if hero.libai_xia_timer > 0.0:
					out.append(_status_entry("侠客行", hero.libai_xia_timer / 5.0, Color(0.78, 0.92, 1.0), 0, "%.1fs" % hero.libai_xia_timer, true))
			elif hero.libai_sword_auras > 0:
				out.append(_status_entry("剑意", hero.libai_sword_auras / 4.0, Color(0.62, 0.88, 1.0), 4, "%d/4" % hero.libai_sword_auras, false))
		"太乙真人":
			if hero.taiyi_q_channeling and hero.taiyi_q_timer > 0.0:
				out.append(_status_entry("引爆", hero.taiyi_q_timer / 5.0, Color(0.80, 0.50, 1.0), 0, "%.1fs" % hero.taiyi_q_timer, true))
	if hero.is_teleporting:
		var tr := clampf(hero.teleport_progress / 3.0, 0.0, 1.0)
		out.append(_status_entry("传送", tr, Color(0.34, 0.72, 1.0), 0, "%d%%" % int(tr * 100.0), true))
	if hero.is_recalling:
		var rr := clampf(1.0 - hero.recall_timer / Hero.RECALL_DURATION, 0.0, 1.0)
		out.append(_status_entry("回城", rr, Color(0.50, 0.96, 0.72), 0, "%.1fs" % hero.recall_timer, true))
	return out

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

func _draw_status_bar(cx: float, y: float, sh: float, e: Dictionary) -> void:
	var w := bar_width
	var bx := cx - w * 0.5
	var col: Color = e["color"]
	var ratio: float = e["ratio"]
	var fillw := w * ratio
	var frame := _status_style(Color(0.015, 0.022, 0.04, 0.94), Color(col.r, col.g, col.b, 0.42), 1, 5)
	var track := _status_style(Color(0.055, 0.068, 0.10, 0.96), Color(col.r, col.g, col.b, 0.20), 1, 4)
	draw_style_box(frame, Rect2(bx - 1.5, y - 1.5, w + 3.0, sh + 3.0))
	draw_style_box(track, Rect2(bx, y, w, sh))
	if fillw > 0.5:
		var fill := _status_style(Color(col.r * 0.52, col.g * 0.52, col.b * 0.52, 0.98), col.lightened(0.25), 1, 4, col)
		draw_style_box(fill, Rect2(bx, y, fillw, sh))
		draw_rect(Rect2(bx + 2.0, y + 1.5, maxf(fillw - 4.0, 0.0), sh * 0.34), Color(1, 1, 1, 0.18))
		draw_rect(Rect2(bx + 2.0, y + sh - 2.5, maxf(fillw - 4.0, 0.0), 1.5), Color(0, 0, 0, 0.24))
		if fillw > 3.0:
			var cap_a := 0.62
			if e["pulse"]:
				cap_a = 0.48 + 0.34 * (0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.006))
			draw_rect(Rect2(bx + fillw - 2.0, y + 2.0, 2.0, sh - 4.0), Color(1, 1, 1, cap_a))
			draw_rect(Rect2(bx + fillw - 5.0, y + 2.0, 3.0, sh - 4.0), Color(col.r, col.g, col.b, 0.22))
	var segs: int = e["segments"]
	if segs > 1:
		for i in range(1, segs):
			var sx := bx + w * float(i) / float(segs)
			draw_line(Vector2(sx, y + 2.0), Vector2(sx, y + sh - 2.0), Color(0, 0, 0, 0.56), 1.0)
			draw_line(Vector2(sx + 1.0, y + 2.0), Vector2(sx + 1.0, y + sh - 2.0), Color(1, 1, 1, 0.09), 1.0)
	if e["pulse"]:
		var pulse_sb := _status_style(Color(0, 0, 0, 0), Color(col.r, col.g, col.b, 0.34), 1, 5)
		draw_style_box(pulse_sb, Rect2(bx - 2.5, y - 2.5, w + 5.0, sh + 5.0))
	var fs := 11
	_draw_text_shadow(_bold(), Vector2(bx + 7.0, y + sh - 2.5), str(e["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.92, 0.96, 1.0, 0.96), 3)
	_draw_text_shadow(_bold(), Vector2(bx + 6.0, y + sh - 2.5), str(e["value"]), HORIZONTAL_ALIGNMENT_RIGHT, w - 12.0, fs, Color(0.88, 0.93, 1.0, 0.92), 3)

func _draw_status_bars(cx: float, top: float) -> void:
	var entries := _status_entries()
	if entries.is_empty():
		return
	var sh := 12.0
	var gap := 4.0
	for i in range(entries.size()):
		_draw_status_bar(cx, top + float(i) * (sh + gap), sh, entries[i])

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



	
