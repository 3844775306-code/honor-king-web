extends Control
## 回放 HUD：小地图（可点跳转）、全局英雄信息面板（点头像切主视角）、对战信息、
## 主视角属性面板、主视角技能按钮冷却（布局/样式对齐对局）。
## 本身只负责绘制与命中测试，鼠标事件由 ReplayScreen 统一处理（不挡镜头拖拽）。

const HeroArt = preload("res://scripts/ui/HeroArt.gd")
const MinimapDrawScript = preload("res://scripts/ui/MinimapDraw.gd")

var st: Dictionary = {}          # 每帧状态（由 ReplayScreen 填充）
var _static_tex: ImageTexture = null   # 地形+墙体+草丛烘焙图（与对战小地图同款思路）
var _static_key := -1

const MM_W := 236.0
const ROW_H := 54.0
const ROSTER_W := 306.0
const SKILL_SIZE := 148.0

var _s := 1.0
var _f: Font = null
var _ring_hits: Array = []      # [[hero_idx, Rect2], …] 头像行命中
var _attr_head_rect := Rect2()
var attr_collapsed := false     # 属性面板折叠（同单机）

func _ready() -> void:
	_f = UiKit.font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _minimap_rect() -> Rect2:
	_s = UiKit.scale()
	return Rect2(40.0 + UiKit.safe_left(), 40.0 + UiKit.safe_top(), 450.0, 450.0)


func _roster_rect() -> Rect2:
	_s = UiKit.scale()
	var w := ROSTER_W * _s
	var vp := _vp()
	# 左侧：紧贴属性面板下方（属性面板：小地图 450 + 10 起，高 214×s），高度吃满剩余空间
	var top := 40.0 + UiKit.safe_top() + 450.0 + 10.0 + 214.0 * _s + 12.0
	var h := minf((ROW_H * 10.0 + 46.0) * _s, vp.y - top - 16.0)
	return Rect2(40.0 + UiKit.safe_left(), top, w, h)


## 命中测试：返回 {type:"map", x, z} / {type:"hero", idx} / {type:"band"} / {}
func hit(pos: Vector2) -> Dictionary:
	var W: float = size.x if size.x > 1.0 else _vp().x
	if Rect2(W - 781.0, 6.0, 410.0, 190.0).has_point(pos) or Rect2(W - 776.0, 8.0, 250.0, 44.0).has_point(pos):
		return {"type": "band"}
	# 复活/观战头像行（小地图右侧，所有人常显，可点切换主视角）
	for hrow in _ring_hits:
		if (hrow[1] as Rect2).has_point(pos):
			return {"type": "hero_ring", "idx": int(hrow[0])}
	# 属性面板标题条：展开/收起
	if _attr_head_rect.size.x > 0.0 and _attr_head_rect.has_point(pos):
		return {"type": "attr_head"}
	var mr := _minimap_rect()
	if mr.has_point(pos):
		var fx: float = clampf((pos.x - mr.position.x) / mr.size.x, 0.0, 1.0)
		var fz: float = clampf((pos.y - mr.position.y) / mr.size.y, 0.0, 1.0)
		return {"type": "map", "x": (fx - 0.5) * 120.0, "z": (fz - 0.5) * 120.0}
	var rr := _roster_rect()
	if rr.has_point(pos):
		var list0: Array = st.get("heroes", [])
		var rh0: float = (rr.size.y - 46.0 * _s - 6.0 * _s) / maxf(1.0, float(list0.size()))
		var rel: float = pos.y - rr.position.y - 46.0 * _s - 6.0 * _s
		var idx := int(rel / maxf(1.0, rh0))
		var list: Array = st.get("heroes", [])
		if idx >= 0 and idx < list.size():
			return {"type": "hero", "idx": idx}
	return {}


func _draw() -> void:
	_s = UiKit.scale()
	var _r := _minimap_rect()
	_mm_inner = Rect2(_r.position + Vector2(7, 7) * _s, _r.size - Vector2(14, 14) * _s)
	_draw_death_overlay()   # 跟随英雄阵亡：全屏压暗（同 host death overlay），HUD 仍在上层
	_draw_info()
	_draw_minimap()
	_draw_hero_rings()
	var follow: int = int(st.get("follow", -1))
	if follow >= 0:
		_draw_attrs(follow)
	# 技能键由真实操作盘（NetTouchPad，与单机同布局）负责，这里不再自绘


# ---------------- 对战信息 ----------------

# 阵亡压暗（同 host UI_Manager._create_death_overlay：全屏黑 0.5；回放由跟随英雄状态驱动）
func _draw_death_overlay() -> void:
	var fi: int = int(st.get("follow", -1))
	if fi < 0:
		return
	var heroes: Array = st.get("heroes", [])
	if fi >= heroes.size():
		return
	var hd: Dictionary = heroes[fi]
	if float(hd.get("hp", 1.0)) > 0.001:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.5))
	var f: Font = UiKit.font()
	var txt := "阵亡 · 等待复活"
	var fs := 34
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var c := size * 0.5
	draw_string_outline(f, Vector2(c.x - tw * 0.5, c.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(f, Vector2(c.x - tw * 0.5, c.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.86, 0.4))


func _draw_info() -> void:
	# 与对局顶部战况带同位置/同尺寸（host：右上 x=W-781..W-371 / y=6..196，时间条 250×44）
	var vp := _vp()
	var W: float = size.x if size.x > 1.0 else vp.x
	var left := W - 781.0
	# 与单机 UI_Manager._apply_panel_style / 客户端顶带同一套玻璃材质
	var bg := UiKit.flat(0.62, 12, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0.62), 10.0, 6.0)
	draw_style_box(bg, Rect2(left, 6.0, 410.0, 190.0))
	draw_style_box(bg, Rect2(W - 776.0, 8.0, 250.0, 44.0))
	draw_line(Vector2(left + 12.0, 8.0), Vector2(left + 398.0, 8.0), Color(0.72, 0.88, 1.0, 0.18), 1.0)
	draw_line(Vector2(W - 764.0, 9.0), Vector2(W - 538.0, 9.0), Color(0.72, 0.88, 1.0, 0.16), 1.0)
	var f: Font = UiKit.font()
	var tsec: float = float(st.get("t", 0.0))
	var gs := int(round(24.0 * _s))
	var gd := f.get_ascent(gs) + f.get_descent(gs)
	_rtxt(Vector2(W - 776.0, 8.0 + (44.0 - gd) * 0.5 + f.get_ascent(gs)),
		"%02d:%02d" % [int(tsec) / 60, int(tsec) % 60], gs, Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER, 250.0, 2)
	# FPS（同 host：时间条下方 120×24）
	var fps_now := Engine.get_frames_per_second()
	var fs := 14.0 * _s
	var fd := f.get_ascent(int(fs)) + f.get_descent(int(fs))
	var fps_col := Color(1.0, 0.42, 0.38) if fps_now < 30 else (Color(1.0, 0.82, 0.35) if fps_now < 50 else Color(0.55, 0.95, 0.65))
	_rtxt(Vector2(W - 776.0, 56.0 + (24.0 - fd) * 0.5 + f.get_ascent(int(fs))),
		"FPS %d" % fps_now, int(fs), fps_col,
		HORIZONTAL_ALIGNMENT_CENTER, 120.0, 1)
	# K / D / A：跟随英雄（无跟随则本机）
	var heroes: Array = st.get("heroes", [])
	var fi: int = int(st.get("follow", -1))
	var me: int = int((_doc_meta()).get("me", 0)) if _doc_meta().size() > 0 else 0
	var ki: int = fi if fi >= 0 and fi < heroes.size() else me
	if ki >= 0 and ki < heroes.size():
		var hk: Dictionary = heroes[ki]
		var ks := int(round(20.0 * _s))
		var kd := f.get_ascent(ks) + f.get_descent(ks)
		_rtxt(Vector2(W - 773.0, 12.0 + (36.0 - kd) * 0.5 + f.get_ascent(ks)),
			"K/D/A: %d/%d/%d" % [int(hk.get("k", 0)), int(hk.get("d", 0)), int(hk.get("a", 0))],
			ks, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, 394.0, 2)
	# 经济比分（同 host：居中于 W-576，蓝经济 / 蓝击杀 / vs / 红击杀 / 红经济）
	var kills: Array = [0, 0]
	var gold: Array = st.get("gold", [0, 0])
	for h in heroes:
		var tm: int = int(h.get("team", 0))
		if tm < 2:
			kills[tm] += int(h.get("k", 0))
	var sz := int(round(24.0 * _s))
	var segs: Array = [
		[_fmt_gold_r(int(gold[0])), Color(0.0, 0.886, 1.0)],
		["%d " % int(kills[0]), Color.WHITE],
		["vs", Color.WHITE],
		[" %d " % int(kills[1]), Color.WHITE],
		[_fmt_gold_r(int(gold[1])), Color(1.0, 0.33, 0.264)],
	]
	var total := 0.0
	for g in segs:
		total += f.get_string_size(str(g[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var bx := W - 576.0 - total * 0.5
	var base := 82.0 + f.get_ascent(sz)
	for g in segs:
		var txt: String = str(g[0])
		_rtxt(Vector2(bx, base), txt, sz, g[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
		bx += f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	# 第三行：双方剩余防御塔（对局信息带同槽位）
	var towers: Array = [0, 0]
	for tt in st.get("turrets", []):
		var tm2: int = int(tt.get("team", 0))
		if tm2 < 2 and int(tt.get("alive", 0)) == 1:
			towers[tm2] += 1
	var vs2 := int(round(20.0 * _s))
	var vd := f.get_ascent(vs2) + f.get_descent(vs2)
	_rtxt(Vector2(left, 148.0 + (38.0 - vd) * 0.5 + f.get_ascent(vs2)),
		"防御塔 我方 %d : %d 敌方" % [int(towers[0]), int(towers[1])],
		vs2, Color(0.72, 0.76, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 410.0, 2)


func _doc_meta() -> Dictionary:
	var scr = get_parent()
	while scr != null:
		if scr.get("_doc") != null:
			return scr.get("_doc").get("meta", {})
		scr = scr.get_parent()
	return {}


func _rtxt(pos: Vector2, txt: String, sz: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0,
		outline: int = 2) -> void:
	var f: Font = UiKit.font()
	if outline > 0:
		draw_string_outline(f, pos, txt, align, width, sz, outline, Color(0, 0, 0, 0.72))
	draw_string(f, pos, txt, align, width, sz, col)


func _fmt_gold_r(v: int) -> String:
	if v >= 1000:
		return "%.1fk" % (v / 1000.0)
	return str(v)


func _world_to_mm(w: Vector3, rect: Rect2) -> Vector2:
	var fx: float = clampf((w.x / 120.0) + 0.5, 0.0, 1.0)
	var fz: float = clampf((w.z / 120.0) + 0.5, 0.0, 1.0)
	return rect.position + Vector2(fx * rect.size.x, fz * rect.size.y)


func _ensure_static_tex(rect: Rect2) -> ImageTexture:
	var walls: Array = st.get("walls", [])
	var bushes: Array = st.get("bushes", [])
	var key: int = walls.size() * 1000 + bushes.size()
	if _static_tex != null and _static_key == key:
		return _static_tex
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for py in range(n):
		for px in range(n):
			var wx: float = (float(px) / float(n) - 0.5) * 120.0
			var wz: float = (float(py) / float(n) - 0.5) * 120.0
			img.set_pixel(px, py, MinimapDrawScript.world_color(wx, wz, 120.0))
	for w in walls:
		var p0 := Vector2((float(w[0]) / 120.0 + 0.5) * n, (float(w[1]) / 120.0 + 0.5) * n)
		var ang: float = float(w[2]) if w.size() > 2 else 0.0
		var ln: float = float(w[3]) if w.size() > 3 else 5.0
		for t in range(4):
			var q := p0 + Vector2(cos(ang), sin(ang)) * (ln * 120.0 / 120.0) * (float(t) / 3.0 - 0.5) * 2.0
			var ix := clampi(int(q.x), 0, n - 1)
			var iy := clampi(int(q.y), 0, n - 1)
			img.set_pixel(ix, iy, Color(0.36, 0.34, 0.30, 1.0))
	for bsh in bushes:
		var bp := Vector2((float(bsh[0]) / 120.0 + 0.5) * n, (float(bsh[1]) / 120.0 + 0.5) * n)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy > 5:
					continue
				var ix2 := clampi(int(bp.x) + dx, 0, n - 1)
				var iy2 := clampi(int(bp.y) + dy, 0, n - 1)
				img.set_pixel(ix2, iy2, Color(0.10, 0.30, 0.12, 1.0))
	_static_tex = ImageTexture.create_from_image(img)
	_static_key = key
	return _static_tex


func _draw_minimap() -> void:
	var rect := _minimap_rect()
	draw_style_box(UiKit.flat(0.78, 12, 1, Color(0.45, 0.62, 1.0, 0.3), Color(0.02, 0.035, 0.06, 0.94), 8.0, 8.0), rect)
	var inner := Rect2(rect.position + Vector2(7, 7) * _s, rect.size - Vector2(14, 14) * _s)
	draw_rect(inner, Color(0.03, 0.05, 0.04, 1.0))
	var tex := _ensure_static_tex(inner)
	if tex != null:
		draw_texture_rect(tex, inner, false)
	# 血包：有录像状态时按状态/存在性画，旧录像回退固定点位
	if bool(st.get("health_data", false)):
		for hrow in st.get("health_packs", []):
			if not (hrow is Array) or (hrow as Array).size() < 4:
				continue
			var hpp := _world_to_mm(Vector3(float(hrow[0]), 0.0, float(hrow[1])), inner)
			MinimapDrawScript.draw_health_pack(self, hpp, int(hrow[3]) == 1)
	else:
		for hp_spawn in BattleManager.HEALTH_PACK_SPAWNS:
			var hpp2 := _world_to_mm(hp_spawn[0], inner)
			MinimapDrawScript.draw_health_pack(self, hpp2, true)
	# 视野雾：以己方英雄/小兵/塔为视野源，按对局小地图同款网格压暗
	var vision: Array = []
	for h in st.get("heroes", []):
		if Config.is_ally(int(h.get("team", 0))) and int(h.get("alive", 1)) == 1:
			vision.append({"p": Vector3(float(h.get("wx", 0)), 0.0, float(h.get("wz", 0))), "r": 24.0})
	for m in st.get("minions", []):
		if Config.is_ally(int(m.get("team", 0))):
			vision.append({"p": Vector3(float(m.get("wx", 0)), 0.0, float(m.get("wz", 0))), "r": 9.0})
	for tt0 in st.get("turrets", []):
		if Config.is_ally(int(tt0.get("team", 0))) and int(tt0.get("alive", 1)) == 1:
			vision.append({"p": Vector3(float(tt0.get("wx", 0)), 0.0, float(tt0.get("wz", 0))), "r": 20.0})
	if not vision.is_empty():
		var fog := MinimapDrawScript.fog_grid(vision, 120.0, 12.0)
		draw_set_transform(inner.position, 0.0, Vector2.ONE)
		MinimapDrawScript.draw_fog(self, fog, inner.size.x, 0.26)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 防御塔（对局同款图标：外塔方/内塔带框/高地菱形/水晶六边形 + 血条）
	for tt in st.get("turrets", []):
		var tp := _world_to_mm(Vector3(float(tt.get("wx", 0.0)), 0.0, float(tt.get("wz", 0.0))), inner)
		var tcol: Color = Color(0.0, 0.886, 1.0) if Config.is_ally(int(tt.get("team", 0))) else Color(1.0, 0.33, 0.264)
		var hp_ratio: float = float(tt.get("hp", 1.0)) / maxf(1.0, float(tt.get("mx", 1.0)))
		MinimapDrawScript.draw_turret(self, tp, clampf(hp_ratio, 0.0, 1.0), tcol,
			str(tt.get("type", "outer")), int(tt.get("alive", 1)) == 1)
	# 野怪 / 史诗龙
	for j in st.get("jungle", []):
		if int(j.get("alive", 1)) != 1:
			continue
		var jp := _world_to_mm(Vector3(float(j.get("wx", 0.0)), 0.0, float(j.get("wz", 0.0))), inner)
		MinimapDrawScript.draw_jungle(self, jp, str(j.get("kind", "")), true)
	# 小兵：按绝对阵营上色（蓝方=蓝、红方=红），不跟随回放玩家的“我方/敌方”视角
	var blue_dots: Array = []
	var red_dots: Array = []
	for m in st.get("minions", []):
		var mp := _world_to_mm(Vector3(float(m.get("wx", 0.0)), 0.0, float(m.get("wz", 0.0))), inner)
		if int(m.get("team", 0)) == 0:
			blue_dots.append(mp)
		else:
			red_dots.append(mp)
	MinimapDrawScript.draw_clusters(self, MinimapDrawScript.cluster(blue_dots, 3.0), Color(0.0, 0.886, 1.0), 2.6 * _s)
	MinimapDrawScript.draw_clusters(self, MinimapDrawScript.cluster(red_dots, 3.0), Color(1.0, 0.33, 0.264), 2.6 * _s)
	# 英雄（同款头像 + 朝向箭头 + 血量环）
	var follow: int = int(st.get("follow", -1))
	var heroes: Array = st.get("heroes", [])
	for i in range(heroes.size()):
		var h: Dictionary = heroes[i]
		var hp := _world_to_mm(Vector3(float(h.get("wx", 0.0)), 0.0, float(h.get("wz", 0.0))), inner)
		var yaw: float = deg_to_rad(float(h.get("yaw", 0.0)))
		var dir := Vector2(sin(yaw), cos(yaw))
		var base_col: Color = Color(0.35, 0.95, 0.5) if Config.is_ally(int(h.get("team", 0))) else Color(1.0, 0.42, 0.36)
		var ring: Color = Color(0.30, 0.95, 0.42) if Config.is_ally(int(h.get("team", 0))) else Color(1.0, 0.42, 0.36)
		MinimapDrawScript.draw_hero(self, hp, dir, base_col,
			clampf(float(h.get("hp", 0)) / maxf(1.0, float(h.get("mx", 1))), 0.0, 1.0),
			int(h.get("is_me", 0)) == 1, int(h.get("alive", 1)) == 0, 0.0,
			str(h.get("name", "")), ring)
		if i == follow:
			draw_arc(hp, 30.0 * _s, 0.0, TAU, 32, Color(1.0, 0.9, 0.4, 0.9), 2.4 * _s, true)
	# 塔被攻击的黄色警告圈（与对局小地图一致的表现）
	for pg in st.get("pings", []):
		var pp := _world_to_mm(Vector3(float(pg.get("wx", 0)), 0.0, float(pg.get("wz", 0))), inner)
		var age: float = float(pg.get("age", 0.0))
		var f: float = clampf(age / 2.0, 0.0, 1.0)
		draw_arc(pp, 8.0 * _s + 30.0 * _s * f, 0.0, TAU, 32, Color(1.0, 0.85, 0.2, 1.0 - f), 2.4 * _s, true)
	# 击杀/阵亡事件标记
	for mk in st.get("marks", []):
		var mp2 := _world_to_mm(Vector3(float(mk.get("wx", 0)), 0.0, float(mk.get("wz", 0))), inner)
		var mage: float = float(mk.get("age", 0.0))
		var mf: float = clampf(mage / 2.5, 0.0, 1.0)
		var mcol: Color = Color(1.0, 0.35, 0.3) if int(mk.get("team", 0)) != int(st.get("me_team", 0)) else Color(0.35, 1.0, 0.45)
		draw_arc(mp2, 12.0 * _s, 0.0, TAU, 24, Color(mcol.r, mcol.g, mcol.b, 1.0 - mf), 2.0 * _s, true)
	# 野怪刷新倒计时
	for cp in st.get("camps", []):
		var cp_pos := _world_to_mm(Vector3(float(cp.get("wx", 0)), 0.0, float(cp.get("wz", 0))), inner)
		MinimapDrawScript.draw_camp_respawn(self, cp_pos, str(cp.get("kind", "")), float(cp.get("left", 0.0)),
			int(round(12.0 * _s)))
	# 当前镜头视野框（拖动小地图可移视角）
	var cam = st.get("cam")
	if cam != null and is_instance_valid(cam):
		var cb := Callable(self, "_world_to_mm_cb")
		var corners: PackedVector2Array = MinimapDrawScript.viewport_corners(cam, cb)
		if corners.size() >= 3:
			MinimapDrawScript.draw_viewport(self, corners, false)
	UiKit.text(self, Vector2(rect.position.x + 10.0 * _s, rect.position.y + 18.0 * _s),
		"小地图（拖动移视角）", int(round(13.0 * _s)), Color(0.78, 0.86, 0.98))


func _world_to_mm_cb(w: Vector3) -> Vector2:
	return _world_to_mm(w, _mm_inner)


var _mm_inner := Rect2()


# ---------------- 击杀战报（右边栏，与对局播报一致的头像+播报文字） ----------------

func _draw_feed() -> void:
	var items: Array = st.get("feed", [])
	if items.is_empty():
		return
	var vp := _vp()
	var w := 460.0 * _s
	var row_h := 44.0 * _s
	for i in range(mini(items.size(), 5)):
		var it: Dictionary = items[items.size() - 1 - i]
		var age: float = float(it.get("age", 0.0))
		var a: float = clampf(1.0 - (age - 4.8) / 1.2, 0.0, 1.0)
		if a <= 0.0:
			continue
		var r := Rect2(vp.x - 24.0 * _s - w, 118.0 * _s + float(i) * row_h, w, row_h - 5.0 * _s)
		draw_style_box(UiKit.flat(0.8, 8, 1, Color(0.45, 0.62, 1.0, 0.22),
			Color(0.03, 0.045, 0.075, 0.88 * a), 6.0, 4.0), r)
		var acol: Color = Color(0.35, 0.85, 1.0) if Config.is_ally(int(it.get("at", 0))) else Color(1.0, 0.42, 0.36)
		var fs := int(round(17.0 * _s))
		if HeroArt != null:
			HeroArt.draw_portrait(self, r.position + Vector2(22.0 * _s, r.size.y * 0.5), 14.0 * _s,
				str(it.get("a", "")), acol, false)
		UiKit.text(self, Vector2(r.position.x + 44.0 * _s, r.position.y + 20.0 * _s), str(it.get("a", "")),
			fs, Color(0.95, 0.98, 1.0, a))
		UiKit.text(self, Vector2(r.position.x + 150.0 * _s, r.position.y + 20.0 * _s), str(it.get("d", "")),
			fs, Color(1.0, 0.88, 0.55, a))
		var vname := str(it.get("v", ""))
		if vname != "":
			var vcol: Color = Color(0.35, 0.85, 1.0) if Config.is_ally(int(it.get("vt", 0))) else Color(1.0, 0.42, 0.36)
			UiKit.text(self, Vector2(r.position.x + 258.0 * _s, r.position.y + 20.0 * _s), vname,
				fs, Color(0.95, 0.98, 1.0, a))
			if HeroArt != null:
				HeroArt.draw_portrait(self, r.position + Vector2(r.size.x - 24.0 * _s, r.size.y * 0.5),
					14.0 * _s, vname, vcol, false)


# ---------------- 全局英雄信息面板 ----------------

func _draw_roster() -> void:
	var rect := _roster_rect()
	draw_style_box(UiKit.flat(0.75, 12, 1, Color(0.45, 0.62, 1.0, 0.26), Color(0.03, 0.045, 0.075, 0.92), 8.0, 8.0), rect)
	UiKit.text(self, Vector2(rect.position.x + 12.0 * _s, rect.position.y + 26.0 * _s),
		"英雄信息（点击头像切主视角）", int(round(15.0 * _s)), Color(0.75, 0.85, 0.98))
	var heroes: Array = st.get("heroes", [])
	var follow: int = int(st.get("follow", -1))
	var rh: float = (rect.size.y - 46.0 * _s - 6.0 * _s) / maxf(1.0, float(heroes.size()))
	for i in range(heroes.size()):
		var h: Dictionary = heroes[i]
		var row := Rect2(rect.position.x + 6.0 * _s, rect.position.y + 46.0 * _s + 6.0 * _s + rh * float(i),
			rect.size.x - 12.0 * _s, maxf(30.0, rh - 4.0 * _s))
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
		# 阵亡：头像上盖复活倒计时（与对局复活读秒一致）
		if int(h.get("alive", 1)) == 0:
			var rv: float = float(h.get("revive", 0.0))
			draw_circle(pc, pr + 2.0 * _s, Color(0.02, 0.03, 0.06, 0.72))
			draw_arc(pc, pr + 2.0 * _s, -PI * 0.5, -PI * 0.5 + TAU * clampf(rv / 10.0, 0.0, 1.0),
				28, Color(1.0, 0.85, 0.35, 0.95), 2.6 * _s, true)
			UiKit.text(self, pc + Vector2(-pr, 7.0 * _s), "%d" % int(ceil(rv)), int(round(22.0 * _s)),
				Color(1.0, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER, pr * 2.0)
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
	# 与单机/联机同款：18 行属性面板（基础白 / +装备绿 / +增益橙，两列 9 行，可折叠）
	var sa: Array = st.get("sa", [])
	var cfg: Array = UiManager.ATTRIBUTE_ROWS
	var n := mini(cfg.size(), int(sa.size() / 3))
	if n <= 0:
		_attr_head_rect = Rect2()
		return
	var pad := 12.0 * _s
	var head_h := 30.0 * _s
	var legend_h := 26.0 * _s
	var row_h := 28.0 * _s
	var col_w := 200.0 * _s
	var col_gap := 12.0 * _s
	var ncol := 2
	var per_col := int(ceil(float(n) / float(ncol)))
	var panel_w := pad * 2.0 + col_w * float(ncol) + col_gap * float(ncol - 1)
	var panel_h := pad * 2.0 + head_h + legend_h + row_h * float(per_col)
	if attr_collapsed:
		panel_w = minf(panel_w, 450.0)
		panel_h = pad * 2.0 + head_h
	var left := 40.0 + UiKit.safe_left()
	var top := 40.0 + UiKit.safe_top() + 460.0
	draw_style_box(UiKit.flat(0.5, 12, 1), Rect2(left, top, panel_w, panel_h))
	_attr_head_rect = Rect2(left, top, panel_w, maxf(panel_h, head_h + pad * 2.0))
	var hs := int(round(16.0 * _s))
	draw_string(_f, Vector2(left + pad, top + 2.0 * _s + (head_h - (_f.get_ascent(hs) + _f.get_descent(hs))) * 0.5 + _f.get_ascent(hs)),
		"属性  ▼" if attr_collapsed else "属性  ▲", HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(0.85, 0.9, 1.0, 0.95))
	if attr_collapsed:
		return
	var lys := int(round(13.0 * _s))
	var ly := top + pad + head_h + (_f.get_ascent(lys) + _f.get_descent(lys)) * 0.5 + _f.get_ascent(lys)
	var lx := left + pad
	for lg in [["基础", Color.WHITE], ["  +装备", ATTR_EQUIP_C], ["  +增益", ATTR_BUFF_C]]:
		var lt: String = str(lg[0])
		draw_string(_f, Vector2(lx, ly), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lys, lg[1])
		lx += _f.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lys).x
	var y0 := top + pad + head_h + legend_h
	var rfs := int(round(15.0 * _s))
	for i in range(n):
		var c: Dictionary = cfg[i]
		var col := int(i / per_col)
		var ri := i % per_col
		var x0 := left + pad + float(col) * (col_w + col_gap)
		var mult := float(c.get("mult", 1.0))
		var pct := bool(c.get("pct", false))
		var base_v := float(sa[i * 3]) * mult
		var equip_v := float(sa[i * 3 + 1]) * mult
		var buff_v := float(sa[i * 3 + 2]) * mult
		var row_y := y0 + float(ri) * row_h + row_h * 0.72
		var nm: String = str(c.get("name", "")) + "  "
		draw_string(_f, Vector2(x0, row_y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, ATTR_NAME_C)
		var tx := x0 + _f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
		var wrote := false
		for k in range(3):
			var v: float = [base_v, equip_v, buff_v][k]
			if absf(v) < 0.05:
				continue
			var t2: String = _attr_txt(v, pct)
			if k > 0 and v > 0.0:
				t2 = "+" + t2
			var ccol: Color = [ATTR_BASE_C, ATTR_EQUIP_C, ATTR_BUFF_C][k]
			draw_string(_f, Vector2(tx, row_y), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, ccol)
			tx += _f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, rfs).x
			wrote = true
		if not wrote:
			draw_string(_f, Vector2(tx, row_y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, rfs, ATTR_BASE_C)


const ATTR_BASE_C := Color(0.94, 0.96, 1.0)
const ATTR_EQUIP_C := Color(0.55, 1.0, 0.62)
const ATTR_BUFF_C := Color(1.0, 0.75, 0.4)
const ATTR_NAME_C := Color(0.74, 0.8, 0.92)


func _attr_txt(v: float, pct: bool) -> String:
	# 调用方已经乘过 cfg.mult（pct 行 mult=100），这里不能再 ×100，否则暴击/吸血会放大 100 倍
	if pct:
		var r := roundf(v * 10.0) / 10.0
		if absf(r - roundf(r)) < 0.05:
			return "%d%%" % int(roundf(r))
		return "%.1f%%" % r
	if absf(v) >= 100.0:
		return "%d" % int(round(v))
	return "%.1f" % v


## 小地图右侧「所有人」英雄头像行（我方 5 + 敌方 5，死亡也显示，可点切主视角）
func _draw_hero_rings() -> void:
	_ring_hits.clear()
	var heroes: Array = st.get("heroes", [])
	if heroes.is_empty():
		return
	var my_team := int(st.get("me_team", 0))
	var follow := int(st.get("follow", -1))
	var x0 := 500.0 + UiKit.safe_left()
	var y0 := 28.0 + UiKit.safe_top()
	var cell_w := 130.0
	var cell_h := 150.0
	var sep_x := 4.0
	var sep_y := 6.0
	var rows: Array = [[], []]
	for i in range(heroes.size()):
		var h: Dictionary = heroes[i]
		var row := 0 if int(h.get("team", 0)) == my_team else 1
		rows[row].append([i, h])
	var yy := y0
	for row in rows:
		var xx := x0
		for item in row:
			var idx: int = int(item[0])
			var h2: Dictionary = item[1]
			var cell := Rect2(xx, yy, cell_w, cell_h)
			_draw_hero_ring_cell(h2, cell, idx == follow)
			_ring_hits.append([idx, cell])
			xx += cell_w + sep_x
		yy += cell_h + sep_y


func _draw_hero_ring_cell(h: Dictionary, r: Rect2, is_follow: bool) -> void:
	var c := r.position + Vector2(r.size.x * 0.5, 70.0)
	var ring_r := 56.25
	var team := int(h.get("team", 0))
	var alive := int(h.get("alive", 1)) == 1
	var team_col := Color(0.0, 0.886, 1.0) if team == int(st.get("me_team", 0)) else Color(1.0, 0.33, 0.264)
	HeroArt.draw_portrait(self, c, ring_r, str(h.get("name", "")), team_col, not alive)
	draw_arc(c, ring_r + 3.75, 0.0, TAU, 48, Color.BLACK, 5.0)
	if is_follow:
		draw_arc(c, ring_r + 8.0, 0.0, TAU, 48, Color(1.0, 0.86, 0.4), 3.0)
	if not alive:
		var remain: float = float(h.get("revive", 0.0))
		draw_arc(c, ring_r + 3.75, -PI * 0.5, -PI * 0.5 + TAU * clampf(remain / 10.0, 0.0, 1.0), 48, Color.WHITE, 5.0)
		var fs := int(round(24.0 * _s))
		var txt := str(int(ceil(remain)))
		var tw := _f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string_outline(_f, Vector2(c.x - tw * 0.5, c.y + 9.0 * _s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.75))
		draw_string(_f, Vector2(c.x - tw * 0.5, c.y + 9.0 * _s), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	else:
		var mx: float = maxf(1.0, float(h.get("mx", 1.0)))
		var ratio: float = clampf(float(h.get("hp", 0.0)) / mx, 0.0, 1.0)
		var hcol := Color(0.25, 1.0, 0.3) if ratio > 0.5 else (Color(1.0, 0.9, 0.2) if ratio > 0.25 else Color(1.0, 0.3, 0.2))
		draw_arc(c, ring_r + 3.75, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, hcol, 5.0)
	var lv := int(h.get("lvl", 1))
	var k := int(h.get("k", 0)); var d := int(h.get("d", 0)); var a := int(h.get("a", 0))
	var fs2 := int(round(14.0 * _s))
	var label := "Lv.%d  %d/%d/%d" % [lv, k, d, a]
	var tw2 := _f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	draw_string(_f, Vector2(c.x - tw2 * 0.5, r.position.y + r.size.y - 12.0 * _s), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.9, 0.94, 1.0))



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

