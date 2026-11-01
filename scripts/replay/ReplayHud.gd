extends Control
## 回放 HUD：小地图（可点跳转）、全局英雄信息面板（点头像切主视角）、对战信息、
## 主视角属性面板、主视角技能按钮冷却（布局/样式对齐对局）。
## 本身只负责绘制与命中测试，鼠标事件由 ReplayScreen 统一处理（不挡镜头拖拽）。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
var st: Dictionary = {}          # 每帧状态（由 ReplayScreen 填充）

const MM_W := 236.0
const ROW_H := 54.0
const ROSTER_W := 306.0
const SKILL_SIZE := 148.0

var _s := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _minimap_rect() -> Rect2:
	_s = UiKit.scale()
	var w := MM_W * _s
	return Rect2(24.0 * _s, _vp().y - 70.0 * _s - w, w, w)


func _roster_rect() -> Rect2:
	_s = UiKit.scale()
	var w := ROSTER_W * _s
	var h := (ROW_H * 10.0 + 46.0) * _s
	var vp := _vp()
	return Rect2(vp.x - 24.0 * _s - w, vp.y * 0.5 - h * 0.5, w, h)


## 命中测试：返回 {type:"map", x, z} / {type:"hero", idx} / {}
func hit(pos: Vector2) -> Dictionary:
	var mr := _minimap_rect()
	if mr.has_point(pos):
		var half := 70.0
		var fx: float = clampf((pos.x - mr.position.x) / mr.size.x, 0.0, 1.0)
		var fz: float = clampf((pos.y - mr.position.y) / mr.size.y, 0.0, 1.0)
		return {"type": "map", "x": -half + fx * half * 2.0, "z": -half + fz * half * 2.0}
	var rr := _roster_rect()
	if rr.has_point(pos):
		var rel: float = pos.y - rr.position.y - 46.0 * _s - 6.0 * _s
		var idx := int(rel / (ROW_H * _s))
		var list: Array = st.get("heroes", [])
		if idx >= 0 and idx < list.size():
			return {"type": "hero", "idx": idx}
	return {}


func _draw() -> void:
	_s = UiKit.scale()
	_draw_info()
	_draw_minimap()
	_draw_roster()
	var follow: int = int(st.get("follow", -1))
	if follow >= 0:
		_draw_attrs(follow)
	_draw_skills(follow)


# ---------------- 对战信息 ----------------

func _draw_info() -> void:
	var vp := _vp()
	var w := 560.0 * _s
	var rect := Rect2(24.0 * _s, 22.0 * _s, w, 84.0 * _s)
	draw_style_box(UiKit.flat(0.72, 12, 1, Color(0.45, 0.62, 1.0, 0.24), Color(0.03, 0.045, 0.075, 0.92), 10.0, 8.0), rect)
	var fs := int(round(21.0 * _s))
	var x := rect.position.x + 14.0 * _s
	var y := rect.position.y + 26.0 * _s
	var kills: Array = [0, 0]
	var towers: Array = [0, 0]
	for h in st.get("heroes", []):
		var tm: int = int(h.get("team", 0))
		if tm < 2:
			kills[tm] += int(h.get("k", 0))
	for tt in st.get("turrets", []):
		var tm2: int = int(tt.get("team", 0))
		if tm2 < 2 and int(tt.get("alive", 0)) == 1:
			towers[tm2] += 1
	var tsec: float = float(st.get("t", 0.0))
	UiKit.text(self, Vector2(x, y), "%02d:%02d" % [int(tsec) / 60, int(tsec) % 60], fs, Color(0.95, 0.98, 1.0))
	var gold: Array = st.get("gold", [0, 0])
	var gd: int = int(gold[1]) - int(gold[0])
	UiKit.text(self, Vector2(x + 120.0 * _s, y), "比分 %d : %d" % [kills[0], kills[1]], fs,
		Color(0.6, 0.85, 1.0))
	UiKit.text(self, Vector2(x + 300.0 * _s, y), "塔 %d : %d" % [towers[0], towers[1]], fs,
		Color(0.85, 0.9, 1.0))
	var fs2 := int(round(17.0 * _s))
	UiKit.text(self, Vector2(x, y + 30.0 * _s), "经济差 %s%d" % ["+" if gd >= 0 else "", gd], fs2,
		Color(1.0, 0.86, 0.45) if gd >= 0 else Color(1.0, 0.52, 0.45))
	var mode := str(st.get("mode", ""))
	UiKit.text(self, Vector2(x + 220.0 * _s, y + 30.0 * _s), "%s · %s" % [mode, str(st.get("hero", ""))], fs2,
		Color(0.62, 0.7, 0.85))


# ---------------- 小地图 ----------------

func _draw_minimap() -> void:
	var rect := _minimap_rect()
	draw_style_box(UiKit.flat(0.75, 12, 1, Color(0.45, 0.62, 1.0, 0.3), Color(0.02, 0.035, 0.06, 0.94), 8.0, 8.0), rect)
	var inner := Rect2(rect.position + Vector2(8, 8) * _s, rect.size - Vector2(16, 16) * _s)
	draw_rect(inner, Color(0.07, 0.10, 0.09, 0.96))
	# 三条分路
	var p := inner.position
	var sz := inner.size
	var lane_col := Color(0.20, 0.28, 0.24, 0.95)
	var lw := maxf(2.0, 3.0 * _s)
	draw_line(p, p + sz, lane_col, lw)
	draw_line(Vector2(p.x, p.y + sz.y), Vector2(p.x + sz.x, p.y), lane_col, lw)
	draw_line(Vector2(p.x, p.y + sz.y * 0.5), Vector2(p.x + sz.x, p.y + sz.y * 0.5), lane_col, lw)
	# 河道
	draw_line(Vector2(p.x, p.y + sz.y * 0.5 - 10.0 * _s), Vector2(p.x + sz.x, p.y + sz.y * 0.5 + 10.0 * _s),
		Color(0.16, 0.34, 0.55, 0.85), 6.0 * _s)
	var to_world := func(wx: float, wz: float) -> Vector2:
		var fx: float = clampf((wx + 70.0) / 140.0, 0.0, 1.0)
		var fz: float = clampf((wz + 70.0) / 140.0, 0.0, 1.0)
		return p + Vector2(fx * sz.x, fz * sz.y)
	# 塔
	for tt in st.get("turrets", []):
		if int(tt.get("alive", 1)) != 1:
			continue
		var tp: Vector2 = to_world.call(float(tt.get("wx", 0.0)), float(tt.get("wz", 0.0)))
		var tc: Color = Color(0.0, 0.886, 1.0) if Config.is_ally(int(tt.get("team", 0))) else Color(1.0, 0.33, 0.264)
		var tr := (4.2 if str(tt.get("type", "")) == "crystal" else 3.0) * _s
		draw_circle(tp, tr, tc)
	# 英雄
	var follow: int = int(st.get("follow", -1))
	var heroes: Array = st.get("heroes", [])
	for i in range(heroes.size()):
		var h: Dictionary = heroes[i]
		if int(h.get("alive", 0)) != 1:
			continue
		var hp: Vector2 = to_world.call(float(h.get("wx", 0.0)), float(h.get("wz", 0.0)))
		var col: Color = Color(0.35, 0.95, 0.5) if Config.is_ally(int(h.get("team", 0))) else Color(1.0, 0.42, 0.36)
		if i == follow:
			draw_circle(hp, 7.5 * _s, Color(1.0, 0.9, 0.4, 0.35))
			draw_arc(hp, 7.5 * _s, 0.0, TAU, 20, Color(1.0, 0.9, 0.4), 1.8 * _s, true)
		draw_circle(hp, 4.6 * _s, col)
		if int(h.get("is_me", 0)) == 1:
			draw_arc(hp, 6.2 * _s, 0.0, TAU, 16, Color(1, 1, 1, 0.85), 1.2 * _s, true)
	UiKit.text(self, Vector2(rect.position.x + 10.0 * _s, rect.position.y + 20.0 * _s), "小地图（点击跳转）",
		int(round(14.0 * _s)), Color(0.72, 0.82, 0.95))


# ---------------- 全局英雄信息面板 ----------------

func _draw_roster() -> void:
	var rect := _roster_rect()
	draw_style_box(UiKit.flat(0.75, 12, 1, Color(0.45, 0.62, 1.0, 0.26), Color(0.03, 0.045, 0.075, 0.92), 8.0, 8.0), rect)
	UiKit.text(self, Vector2(rect.position.x + 12.0 * _s, rect.position.y + 26.0 * _s),
		"英雄信息（点击头像切主视角）", int(round(15.0 * _s)), Color(0.75, 0.85, 0.98))
	var heroes: Array = st.get("heroes", [])
	var follow: int = int(st.get("follow", -1))
	for i in range(heroes.size()):
		var h: Dictionary = heroes[i]
		var row := Rect2(rect.position.x + 6.0 * _s, rect.position.y + (46.0 + ROW_H * float(i)) * _s + 6.0 * _s,
			rect.size.x - 12.0 * _s, (ROW_H - 4.0) * _s)
		var team: int = int(h.get("team", 0))
		var tcol: Color = Color(0.35, 0.85, 1.0) if Config.is_ally(team) else Color(1.0, 0.42, 0.36)
		if i == follow:
			draw_style_box(UiKit.flat(0.85, 8, 1, Color(1.0, 0.86, 0.4, 0.75), Color(0.10, 0.09, 0.05, 0.9), 6.0, 4.0), row)
		else:
			draw_style_box(UiKit.flat(0.55, 8, 1, Color(tcol.r, tcol.g, tcol.b, 0.3), Color(0.05, 0.07, 0.11, 0.8), 6.0, 4.0), row)
		# 头像
		var pc := row.position + Vector2(26.0 * _s, row.size.y * 0.5)
		var pr: float = minf(row.size.y * 0.42, 20.0 * _s)
		if HeroArt != null:
			HeroArt.draw_portrait(self, pc, pr, str(h.get("name", "")), tcol, int(h.get("alive", 1)) == 0)
		# 名字/等级/KDA
		var fs := int(round(16.0 * _s))
		UiKit.text(self, Vector2(row.position.x + 52.0 * _s, row.position.y + 20.0 * _s),
			"Lv.%d %s" % [int(h.get("lvl", 1)), str(h.get("name", ""))], fs,
			Color(0.95, 0.97, 1.0))
		var kda := "K/D/A %d/%d/%d" % [int(h.get("k", 0)), int(h.get("d", 0)), int(h.get("a", 0))]
		UiKit.text(self, Vector2(row.position.x + 190.0 * _s, row.position.y + 20.0 * _s), kda,
			int(round(13.0 * _s)), Color(0.78, 0.84, 0.94))
		# 血条
		var bw: float = row.size.x - 58.0 * _s
		var bh: float = 9.0 * _s
		var bp := Vector2(row.position.x + 52.0 * _s, row.position.y + 26.0 * _s)
		var ratio: float = clampf(float(h.get("hp", 0)) / maxf(1.0, float(h.get("mx", 1))), 0.0, 1.0)
		draw_rect(Rect2(bp, Vector2(bw, bh)), Color(0.10, 0.11, 0.15))
		draw_rect(Rect2(bp, Vector2(bw * ratio, bh)), Color(0.35, 0.95, 0.5) if ratio > 0.55 else (Color(1.0, 0.82, 0.35) if ratio > 0.28 else Color(1.0, 0.38, 0.33)))
		var mp: float = clampf(float(h.get("mana", 0)) / maxf(1.0, float(h.get("mmax", 1))), 0.0, 1.0)
		draw_rect(Rect2(bp + Vector2(0, bh + 1.0 * _s), Vector2(bw, 5.0 * _s)), Color(0.10, 0.11, 0.15))
		draw_rect(Rect2(bp + Vector2(0, bh + 1.0 * _s), Vector2(bw * mp, 5.0 * _s)), Color(0.35, 0.62, 1.0))


# ---------------- 主视角：属性面板 ----------------

func _draw_attrs(idx: int) -> void:
	var heroes: Array = st.get("heroes", [])
	if idx < 0 or idx >= heroes.size():
		return
	var h: Dictionary = heroes[idx]
	var rect := Rect2(24.0 * _s, 118.0 * _s, 300.0 * _s, 214.0 * _s)
	draw_style_box(UiKit.flat(0.72, 12, 1, Color(0.45, 0.62, 1.0, 0.26), Color(0.03, 0.045, 0.075, 0.92), 8.0, 8.0), rect)
	var fs := int(round(16.0 * _s))
	var cap := "主视角 · %s（Esc 回自由镜头）" % str(h.get("name", ""))
	UiKit.text(self, Vector2(rect.position.x + 12.0 * _s, rect.position.y + 24.0 * _s), cap,
		int(round(15.0 * _s)), Color(1.0, 0.9, 0.55))
	var rows := [
		["物理攻击", "%d" % int(h.get("ad", 0))],
		["法术强度", "%d" % int(h.get("ap", 0))],
		["护甲", "%d" % int(h.get("armor", 0))],
		["魔抗", "%d" % int(h.get("mr", 0))],
		["移速", "%.0f" % (float(h.get("ms", 0)) / 10.0)],
		["攻速", "%d%%" % int(h.get("as", 0))],
	]
	var y := rect.position.y + 52.0 * _s
	for r in rows:
		UiKit.text(self, Vector2(rect.position.x + 16.0 * _s, y), str(r[0]), fs, Color(0.72, 0.8, 0.92))
		UiKit.text(self, Vector2(rect.position.x + 150.0 * _s, y), str(r[1]), fs, Color(0.96, 0.98, 1.0))
		y += 26.0 * _s


# ---------------- 主视角：技能按钮冷却 ----------------

func _draw_skills(follow: int) -> void:
	if follow < 0:
		return
	var heroes: Array = st.get("heroes", [])
	if follow >= heroes.size():
		return
	var h: Dictionary = heroes[follow]
	var cds: Array = h.get("cds", [])
	var totals: Array = h.get("cd_total", [])
	var levels: Array = h.get("slevels", [])
	var vp := _vp()
	var s := SKILL_SIZE * _s
	var gap := 12.0 * _s
	var base := Vector2(vp.x - 24.0 * _s - s * 2.0 - gap, vp.y - 24.0 * _s - s * 2.0 - gap)
	var labels := ["1", "2", "3", "召"]
	for i in range(4):
		var col := i % 2
		var row := i / 2
		var c := base + Vector2(col * (s + gap) + s * 0.5, (1 - row) * (s + gap) + s * 0.5)
		var r := s * 0.44
		draw_circle(c, r + 4.0 * _s, Color(0.02, 0.035, 0.06, 0.9))
		draw_circle(c, r, Color(0.10, 0.14, 0.22, 0.95))
		var cd: float = float(cds[i]) if i < cds.size() else 0.0
		var tot: float = maxf(0.001, float(totals[i]) if i < totals.size() else 1.0)
		var ratio: float = clampf(cd / tot, 0.0, 1.0)
		if ratio > 0.001:
			var pts := PackedVector2Array()
			pts.append(c)
			var steps := 32
			var a1 := -PI * 0.5 + TAU * ratio
			for k in range(steps + 1):
				var a := lerpf(-PI * 0.5, a1, float(k) / float(steps))
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
		var lv: int = int(levels[i]) if i < levels.size() else 0
		draw_arc(c, r, 0.0, TAU, 40, Color(0.45, 0.7, 1.0, 0.5), 2.0 * _s, true)
		if ratio <= 0.001:
			draw_arc(c, r + 3.0 * _s, 0.0, TAU, 40, Color(1.0, 0.86, 0.4, 0.75), 2.2 * _s, true)
		UiKit.text(self, c + Vector2(-r, 7.0 * _s), labels[i], int(round(22.0 * _s)), Color(0.95, 0.97, 1.0),
			HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		if ratio > 0.001:
			UiKit.text(self, c + Vector2(-r, 28.0 * _s), "%.1f" % cd, int(round(20.0 * _s)),
				Color(1.0, 0.93, 0.8), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		else:
			UiKit.text(self, c + Vector2(-r, 30.0 * _s), "就绪", int(round(14.0 * _s)),
				Color(0.6, 0.95, 0.7), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0)
		if lv > 0:
			UiKit.text(self, c + Vector2(r * 0.35, -r * 0.35), "Lv%d" % lv, int(round(12.0 * _s)),
				Color(1.0, 0.88, 0.5))
