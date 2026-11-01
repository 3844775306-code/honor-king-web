class_name SharedHeroBar
extends RefCounted
## 三端共享的「英雄世界血条」绘制（数据驱动，像素级复刻 host HeroInfoControl 的版面）：
## 名字/昵称、等级经验环、280×28 血条（投影/队伍边框/5 段渐变/1000 血刻度/护盾斜纹/残血拖尾/
## 受伤闪橙/低血脉冲）、MVP 王冠、草丛隐藏徽章、标记图标行、AI 决策胶囊、法力条、状态条。
## 调用方只需准备数据字典：
##   name/pname/level/hp/maxhp/hp_col/team/shield/mana/maxmana/exp/exp_to_next/hidden/mvp/
##   lyf/status/markers([[name,count]])/ai_chip({label,r,g,b})/lag/flash_ratio/flash_amt
## host 由 HeroInfoControl 适配、联机由 NetHud 快照适配、回放共用同一份绘制。

const MarkerIconScript = preload("res://scripts/ui/MarkerIcon.gd")


static func draw(ci: CanvasItem, f: Font, r: Dictionary) -> void:
	var cx := float(r.cx)
	# 主机 HUD：position = 锚点屏幕位 - custom_minimum_size/2（HeroInfoControl 高 320 → /2=160）
	var top := float(r.cy) - 160.0
	# —— 纵向版式与单机 HeroInfoControl._draw 完全同公式 ——
	#   y=24 起：图标/状态行（有则占 44）→ 名字 → AI 决策胶囊（有则占 21）→ 血条
	var _mks: Array = r.get("markers", [])
	var _sts: Array = r.get("status", [])
	var _icon_h := 0.0
	if not _mks.is_empty() or not _sts.is_empty() or bool(r.get("hidden", false)):
		_icon_h = 44.0
	var top2 := top + 24.0 + _icon_h
	# 血条上方同时显示英雄名称与玩家/AI 昵称
	var disp_name := str(r.get("name", ""))
	var nick_name := str(r.get("pname", ""))
	if nick_name != "" and nick_name != disp_name:
		disp_name = (disp_name + " · " + nick_name) if disp_name != "" else nick_name
	if disp_name == "":
		disp_name = "?"
	# 与 host HeroInfoControl 一致：名称 28（超宽降 22 并省略），血条上方只显示名字，不显示血量数字
	var name_fs := 28.0
	# 与单机一致：控件净宽 520-8 才降号字（此前 272 让客户端过早缩字）
	if f.get_string_size(disp_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x > 512.0:
		name_fs = 22.0
	var _nw := f.get_string_size(disp_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(name_fs)).x
	var _name_base := top2 + f.get_ascent(int(name_fs))
	ci.draw_string_outline(f, Vector2(cx - _nw * 0.5, _name_base), disp_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(name_fs), 4, Color(0, 0, 0, 0.9))
	ci.draw_string(f, Vector2(cx - _nw * 0.5, _name_base), disp_name,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(name_fs), Color.WHITE)
	# 血条 280×28（几何/配色/分层同主机 HeroInfoControl：双层投影 + 队伍色外框 + 上亮下暗空槽 + 5 段渐变 + 玻璃高光 + 残血拖尾）
	var by := _name_base + f.get_descent(int(name_fs)) + 1.0
	# AI 决策胶囊：单机画在「名字与血条之间」占 21px，此处同样让位，避免血条贴住名字
	var _ai0: Dictionary = r.get("ai_chip", {})
	if not _ai0.is_empty() and str(_ai0.get("label", "")) != "":
		by += 21.0
	by += 2.0
	var bw := 280.0
	var bh := 28.0
	var mhp := maxf(float(r.maxhp), 1.0)
	var hp_now := clampf(float(r.hp), 0.0, mhp)
	var ratio := hp_now / mhp
	var hp_col: Color = r.get("hp_col", Color(1.0, 1.0, 1.0))
	var bx := cx - bw / 2.0
	var hpx := bw * ratio
	var shield := clampf(float(r.get("shield", 0.0)), 0.0, mhp)
	# 经验等级圈：血条左端（放大后与血条同高居中，同主机 HeroInfoControl）
	var e2n := float(r.get("exp_to_next", 0.0))
	var exp_ratio := 1.0
	if e2n > 0.0:
		exp_ratio = clampf(float(r.get("exp", 0.0)) / e2n, 0.0, 1.0)
	_sh_level_ring(ci, f, Vector2(bx - 10.0 - 24.0, by + bh * 0.5), 24.0, str(r.get("level", 1)), exp_ratio)
	# 草丛隐藏标记：血条上方中央（主机 hidden_in_bush）
	if bool(r.get("hidden", false)):
		_sh_hidden_badge(ci, Vector2(cx, by - 13.0), 11.0)

	# 标记图标行（同 host HeroInfoControl._draw_icon_strip：名字上方一排专属图标+层数）
	if not _mks.is_empty():
		var _mk_rows: Array = []
		for _m in _mks:
			if _m is Array and (_m as Array).size() >= 2 and int(_m[1]) > 0:
				_mk_rows.append({"name": str(_m[0]), "count": int(_m[1]), "type": ""})
		if not _mk_rows.is_empty():
			MarkerIconScript.draw_row(ci, cx, top + 24.0 + 22.0, _mk_rows, 15.0)
	# AI 决策胶囊（同 host：分路·状态·野区阶段·目标，一行限宽）
	var _ai: Dictionary = r.get("ai_chip", {})
	if not _ai.is_empty() and str(_ai.get("label", "")) != "":
		var _atxt := str(_ai["label"])
		var _acol := Color(float(_ai.get("r", 0.52)), float(_ai.get("g", 0.78)), float(_ai.get("b", 1.0)))
		var _afs := 15
		var _atw := f.get_string_size(_atxt, HORIZONTAL_ALIGNMENT_LEFT, -1, _afs).x
		var _chip_w := minf(320.0, _atw + 26.0)
		var _chip_y := _name_base + f.get_descent(int(name_fs)) + 1.0
		var _cx0 := cx - _chip_w * 0.5
		ci.draw_rect(Rect2(_cx0, _chip_y, _chip_w, 20.0), Color(0.035, 0.05, 0.085, 0.86))
		ci.draw_rect(Rect2(_cx0, _chip_y, _chip_w, 20.0), Color(_acol.r, _acol.g, _acol.b, 0.45), false, 1.0)
		ci.draw_circle(Vector2(_cx0 + 9.0, _chip_y + 10.0), 2.6, _acol)
		ci.draw_string(f, Vector2(_cx0 + 15.0, _chip_y + 14.0), _atxt,
			HORIZONTAL_ALIGNMENT_LEFT, _chip_w - 18.0, _afs, Color(0.92, 0.95, 1.0))
	# 投影（两层）
	ci.draw_rect(Rect2(bx + 3.0, by + 5.0, bw, bh), Color(0, 0, 0, 0.22))
	ci.draw_rect(Rect2(bx + 1.5, by + 2.5, bw, bh), Color(0, 0, 0, 0.34))
	# 外框：深底 + 队伍色细边
	ci.draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0), Color(0.02, 0.03, 0.06, 0.96))
	ci.draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0), Color(hp_col.r, hp_col.g, hp_col.b, 0.55), false, 1.5)
	# 空槽（上亮下暗）
	ci.draw_rect(Rect2(bx, by, bw, bh), Color(0.10, 0.11, 0.15, 0.97))
	ci.draw_rect(Rect2(bx, by, bw, bh * 0.5), Color(0.17, 0.18, 0.22, 0.9))
	# 残血拖尾（掉血后浅色回落，同 host _hp_lag：lerp(delta×4)）
	var lag := float(r.get("lag", hp_now))
	if lag > hp_now + 0.5:
		var lagw := (lag / mhp) * bw
		ci.draw_rect(Rect2(bx + hpx, by, lagw - hpx, bh), Color(1.0, 0.93, 0.82, 0.34))
		ci.draw_rect(Rect2(bx + lagw - 2.0, by, 2.0, bh), Color(1.0, 0.9, 0.75, 0.85))
	# 渐变填充（5 段 lerp）+ 顶部玻璃高光 / 次高光带 / 底部暗边
	if hpx > 0.5:
		var bands := 5
		var c_top := hp_col.lightened(0.35)
		var c_bot := hp_col.darkened(0.42)
		for bi in range(bands):
			var q := float(bi) / float(bands - 1)
			ci.draw_rect(Rect2(bx, by + bh * float(bi) / float(bands), hpx, bh / float(bands) + 1.0),
					c_top.lerp(c_bot, q))
		ci.draw_rect(Rect2(bx, by, hpx, maxf(2.0, bh * 0.18)), Color(1, 1, 1, 0.50))
		ci.draw_rect(Rect2(bx, by + maxf(2.0, bh * 0.18), hpx, 1.5), Color(1, 1, 1, 0.14))
		ci.draw_rect(Rect2(bx, by + bh - 1.5, hpx, 1.5), Color(0, 0, 0, 0.35))
	# 李元芳暗印预判：爆炸前将造成的实际伤害 → 当前血条右端相应段染黄（扣盾、封顶当前血）
	var lyf_rows: Array = r.get("lyf", [])
	var lyf_pred := 0.0
	for m in lyf_rows:
		if m.size() >= 3:
			lyf_pred += float(m[2])
	if lyf_pred > 0.0:
		var doom := clampf(lyf_pred - shield, 0.0, hp_now)
		var doom_w := (doom / mhp) * bw
		if doom_w > 0.5:
			ci.draw_rect(Rect2(bx + hpx - doom_w, by, doom_w, bh), Color(1.0, 0.88, 0.18, 0.9))
	# 护盾段（淡蓝 + 斜纹 + 白色左隔线，同 host）
	var sw := minf((shield / mhp) * bw, bw - hpx)
	if sw > 0.5:
		ci.draw_rect(Rect2(bx + hpx, by, sw, bh), Color(0.62, 0.84, 1.0, 0.95))
		var hatch := int(sw / 7.0)
		for hi in range(hatch):
			var hx := bx + hpx + 2.0 + float(hi) * 7.0
			ci.draw_line(Vector2(hx, by + bh), Vector2(hx + 5.0, by), Color(1, 1, 1, 0.30), 1.0)
		ci.draw_rect(Rect2(bx + hpx, by, sw, 2.0), Color(1, 1, 1, 0.42))
		ci.draw_rect(Rect2(bx + hpx, by, 1.5, bh), Color(1, 1, 1, 0.9))
	# 受伤闪橙：血量右端 0.5s 衰减（同 host HeroInfoControl；比率由 adapter 预计算）
	var _fr_h := float(r.get("flash_ratio", 0.0))
	if _fr_h > 0.0:
		var _fw_h := (float(r.get("flash_amt", 0.0)) / mhp) * bw * _fr_h
		if _fw_h > 0.5:
			ci.draw_rect(Rect2(bx + hpx, by, _fw_h, bh), Color.ORANGE)
	# 刻度：每 1000 血一条（暗线 + 右侧微高光，与 host HeroInfoControl 完全一致）
	var _segs_h: int = int(floor(mhp / 1000.0))
	for _si in range(1, _segs_h + 1):
		var _sx: float = bx + (1000.0 * float(_si) / mhp) * bw
		ci.draw_line(Vector2(_sx, by + 1.0), Vector2(_sx, by + bh - 1.0), Color(0, 0, 0, 0.55), 1.0)
		ci.draw_line(Vector2(_sx + 1.0, by + 1.0), Vector2(_sx + 1.0, by + bh - 1.0), Color(1, 1, 1, 0.22), 1.0)
	# 低血警示脉冲 + 顶部白线压边（同 host HeroInfoControl）
	if ratio < 0.3 and ratio > 0.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		ci.draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0),
				Color(1.0, 0.25, 0.18, 0.30 + 0.45 * pulse), false, 2.0)
	ci.draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0), Color(1, 1, 1, 0.16), false, 1.0)
	# MVP 王冠（host：血条右侧金色王冠徽章，半径 = bar_height×0.66）
	if bool(r.get("mvp", false)):
		_sh_mvp_badge(ci, Vector2(bx + bw + 12.0 + bh * 0.66, by + bh * 0.5), bh * 0.66)
	# 法力条（同 host：半高、3 段蓝渐变 + 蓝边框）
	var mana_max := float(r.get("maxmana", 0.0))
	if mana_max > 0.0:
		var mby := by + bh + 3.0
		var mh := bh * 0.5
		var mw := clampf(float(r.get("mana", 0.0)) / mana_max, 0.0, 1.0) * bw
		ci.draw_rect(Rect2(bx, mby, bw, mh), Color(0.06, 0.08, 0.14, 0.95))
		if mw > 0.5:
			for mi in range(3):
				var mq := float(mi) / 2.0
				ci.draw_rect(Rect2(bx, mby + mh * float(mi) / 3.0, mw, mh / 3.0 + 1.0),
						Color(0.16, 0.42, 0.95).lerp(Color(0.05, 0.16, 0.55), mq))
			ci.draw_rect(Rect2(bx, mby, mw, 1.5), Color(1, 1, 1, 0.45))
		ci.draw_rect(Rect2(bx, mby, bw, mh), Color(0.35, 0.62, 1.0, 0.5), false, 1.0)
	# 状态条（附魔/枪意/炸弹/剑意/回城/传送…）：与 host HeroInfoControl 同款 13px 行 + 1.5px 间隔
	if not _sts.is_empty():
		var sy := by + bh + 3.0
		if mana_max > 0.0:
			sy += bh * 0.5 + 3.0
		sy += 2.0
		# 行底色块先铺（与 host 一样雷达血条+法条+状态条共用一个深色底板观感）
		var _rows_h: float = _sts.size() * 13.0 + (_sts.size() - 1) * 1.5
		ci.draw_rect(Rect2(bx - 2.0, sy - 2.0, bw + 4.0, _rows_h + 4.0), Color(0.02, 0.03, 0.06, 0.96))
		for st in _sts:
			if not (st is Array) or (st as Array).size() < 6:
				continue
			var lb := str(st[0])
			var rt := clampf(float(st[1]), 0.0, 1.0)
			var scol := Color(float(st[2]), float(st[3]), float(st[4]), 1.0)
			var val := str(st[5])
			var pulse2: bool = int(st[6]) == 1 if (st as Array).size() > 6 else false
			ci.draw_rect(Rect2(bx, sy, bw, 13.0), Color(0.07, 0.08, 0.12, 0.9))
			if rt > 0.0:
				ci.draw_rect(Rect2(bx, sy, bw * rt, 13.0), Color(scol.r, scol.g, scol.b, 0.66))
				ci.draw_rect(Rect2(bx, sy, bw * rt, 3.0), Color(1, 1, 1, 0.16))
			ci.draw_rect(Rect2(bx, sy, bw, 13.0), Color(0.35, 0.62, 1.0, 0.18), false, 1.0)
			ci.draw_string(f, Vector2(bx + 7.0, sy + 10.0), lb, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.96, 1.0))
			ci.draw_string(f, Vector2(bx, sy + 10.0), val, HORIZONTAL_ALIGNMENT_RIGHT, bw - 7.0, 13, Color(0.88, 0.93, 1.0))
			if pulse2:
				var pp := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
				ci.draw_rect(Rect2(bx - 1.0, sy - 1.0, bw + 2.0, 15.0), Color(scol.r, scol.g, scol.b, 0.30 + 0.35 * pp), false, 1.4)
			sy += 14.5
	# 暗印层数文字（黄，最顶行；对齐主机 HeroInfoControl 标记行位置：内容顶 y0 基线）
	var ltxt := ""
	for m in lyf_rows:
		if m.size() >= 3:
			var _s2 := ("%d层" % int(m[1])) if int(m[1]) > 0 else ""
			ltxt += ("%s·暗印%s " % [str(m[0]), _s2])
	if ltxt != "":
		var _lw := f.get_string_size(ltxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		ci.draw_string(f, Vector2(cx - _lw / 2.0, top + 2.0), ltxt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 22.0, Color.YELLOW)

# 客户端世界血条 → 单机 WorldBarPainter 行格式：
# 名称/血量/护盾/刻度/残血拖尾/受伤闪橙/标记全部交给同一绘制器，质感与单机完全一致。


static func _sh_level_ring(ci: CanvasItem, f: Font, c: Vector2, r: float, level_text: String, exp_ratio: float) -> void:
	ci.draw_circle(c, r + 2.0, Color(0, 0, 0, 0.92))
	ci.draw_circle(c, r - 1.0, Color(0.07, 0.08, 0.12, 0.95))
	ci.draw_arc(c, r, 0.0, TAU, 32, Color.DIM_GRAY, 2.6)
	ci.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * exp_ratio, 32, Color(1.0, 0.84, 0.0), 3.2)
	ci.draw_arc(c, r - 2.6, PI * 1.12, PI * 1.84, 20, Color(1, 1, 1, 0.22), 1.2)
	var fs := int(round(r * 0.82))
	var tw := f.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), level_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

# 草丛隐藏图标（同主机 HeroInfoControl._draw_hidden_badge）

static func _sh_hidden_badge(ci: CanvasItem, c: Vector2, s: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	ci.draw_circle(c, s * (1.18 + 0.06 * pulse), Color(0.30, 0.86, 1.0, 0.10 + 0.06 * pulse))
	ci.draw_circle(c, s, Color(0.06, 0.09, 0.13, 0.90))
	ci.draw_arc(c, s - 0.8, 0.0, TAU, 28, Color(0.55, 0.86, 0.98, 0.90), 1.6)
	var eye_col := Color(0.86, 0.96, 1.0, 0.95)
	var ew := s * 0.62
	var eh := s * 0.40
	var pts := PackedVector2Array()
	for i in range(13):
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a) * ew, -sin(a) * eh))
	for i in range(13):
		var a2 := PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a2) * ew, sin(a2) * eh))
	pts.append(pts[0])
	ci.draw_polyline(pts, eye_col, 1.8)
	ci.draw_circle(c, s * 0.20, eye_col)
	ci.draw_line(c + Vector2(-ew * 1.15, eh * 1.5), c + Vector2(ew * 1.15, -eh * 1.5), Color(1.0, 0.40, 0.34, 0.95), 2.2)

# MVP 王冠（复刻 host HeroInfoControl._draw_mvp_badge，尺寸随血条高度）

static func _sh_mvp_badge(ci: CanvasItem, c: Vector2, r: float) -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = 0.5 + 0.5 * sin(t * 2.1)
	ci.draw_circle(c, r * (1.46 + 0.08 * pulse), Color(1.0, 0.78, 0.30, 0.08 + 0.05 * pulse))
	ci.draw_circle(c, r * 1.14, Color(1.0, 0.70, 0.22, 0.18))
	ci.draw_circle(c, r, Color(0.11, 0.07, 0.02, 0.97))
	ci.draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1.0, 0.80, 0.34, 0.95), 2.4)
	ci.draw_arc(c, r * 0.84, 0.0, TAU, 40, Color(1.0, 0.72, 0.24, 0.45), 1.1)
	ci.draw_arc(c, r - 1.8, PI * 1.12, PI * 1.86, 24, Color(1.0, 0.96, 0.82, 0.85), 1.5)
	var s: float = r * 0.76
	var pts := PackedVector2Array([
		c + Vector2(-0.62, 0.26) * s, c + Vector2(-0.62, -0.18) * s,
		c + Vector2(-0.31, 0.04) * s, c + Vector2(0.0, -0.48) * s,
		c + Vector2(0.31, 0.04) * s, c + Vector2(0.62, -0.18) * s,
		c + Vector2(0.62, 0.26) * s,
	])
	ci.draw_colored_polygon(pts, Color(1.0, 0.84, 0.38, 0.98))
	ci.draw_rect(Rect2(c + Vector2(-0.62, 0.27) * s, Vector2(1.24, 0.17) * s), Color(1.0, 0.68, 0.16, 0.98))
	for i in range(3):
		var gx: float = -0.34 + 0.34 * i
		ci.draw_circle(c + Vector2(gx, 0.355) * s, s * 0.08, Color(0.26, 0.09, 0.02, 0.95))
	for pp in [Vector2(-0.62, -0.18), Vector2(0.0, -0.48), Vector2(0.62, -0.18)]:
		ci.draw_circle(c + pp * s, s * 0.085, Color(1.0, 0.97, 0.86, 0.95))
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.36, 0.19, 0.02, 0.85), 1.4)

# 无兵线保护盾形图标（复刻 host WorldBarPainter._draw_shield_icon）


