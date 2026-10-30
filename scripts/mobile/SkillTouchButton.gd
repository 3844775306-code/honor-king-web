class_name SkillTouchButton
extends Control
## 移动端技能按钮：按下进入瞄准，拖动更新拖拽向量，松开施放
## 拖拽方向（屏幕坐标偏移）由 TouchController 暴露给 Hero 做瞄准

const SkillArt = preload("res://scripts/ui/SkillArt.gd")
const IconArt = preload("res://scripts/ui/IconArt.gd")

signal pressed_changed(index: int, pressed: bool)
# 王者荣耀式松开施放：final_drag=松开时的拖拽向量；cancelled=「拖出去又拖回按钮」→ 取消施放
# release_global=松开位置（画布全局坐标），用于检测是否落在「取消施法」按钮上
signal released(index: int, final_drag: Vector2, cancelled: bool, release_global: Vector2)

const SIZE_V := 110.0
const TAP_THRESHOLD := 30.0      # 超过此拖拽距离才算“拖出去”
const CANCEL_RADIUS := 40.0      # 松手位置距按下起点小于此值且拖出去过 → 视为拖回按钮，取消

var skill_index := 0
var display_name := ""
# true：技能名画在按钮下方、按钮中央留空（英雄 1/2/3 技能）；false：技能名画在按钮中央（召唤师）
var name_below := false
# 技能图标数据（由 TouchController 推送）：英雄名决定元素配色，skill 决定纹样
var icon_kind := ""       # 非空时画功能图标（回城/恢复/召唤师），颜色固定不走英雄色
var art_hero := ""
var art_skill: Skill = null
var color := Color(0.2, 0.55, 1.0, 0.85)
# 按钮内下方的小字说明（由 TouchController 每帧推送，如惩击的伤害数值）
var sub_text := ""
# 技能图标中央偏上的伤害预览（由 TouchController 每帧推送）：icon_dmg<0 不显示；
# 颜色按伤害类型：icon_dmg_magic=true 法术(紫)，false 物理(橙)；
# icon_count>1 时把伤害与弹数合并显示成“伤害×N”（如“260×6”），表示每段伤害与总弹/段数
var icon_dmg := -1
var icon_dmg_magic := false
# 第二段伤害（与 icon_dmg 并排显示的另一类伤害，如狄仁杰每段同时命中物理+法术）：
# icon_dmg2>0 时按 icon_dmg2_magic 着色并排显示在物理伤害右侧，二者共用弹数“×N”
var icon_dmg2 := 0
var icon_dmg2_magic := false
var icon_count := 0
# 附加效果小字（由 TouchController 每帧推送）：每项 {k:效果类型, col:颜色, txt:数值+时长}，
# 与 icon_dmg 一起画在按钮上（伤害下方逐行，矢量小图标+小字；绿=自身增益/蓝=对敌负面）
var icon_fx: Array = []
# 技能施放后附带“强化普攻”效果（由 TouchController 每帧推送，如亚瑟Q/铠W）：
# 在按钮读数最前/伤害数值前加一枚金色普攻小剑，区别于纯直接伤害技能
var icon_aa := false

var _active := false
var _active_touch := -1
var _origin := Vector2.ZERO      # 按下起点（局部坐标）
var _drag := Vector2.ZERO        # 当前拖拽偏移
var _max_drag := 0.0             # 本次手势的最大拖拽距离
var _press := 0.0

# 每帧由 TouchController 更新，用于绘制冷却/蓝量状态
var cd_ratio := 0.0              # 0..1 剩余冷却占比
var cd_total := 30.0             # 技能总冷却（秒），冷却遮罩上显示真实剩余秒数
var mana_ok := true
# 多段/重施窗口状态（每帧由 TouchController 更新）：
var in_window := false          # 当前处于可重施窗口（如李白Q二/三段、夏侯惇Q二段）
var win_left := 0.0             # 窗口剩余时间（秒）
var win_total := 1.0            # 窗口总时长（秒），青色扇形按此比例收拢
var segments_left := 0          # 剩余可施放段数（>0 时在按钮内底部画实心圆点）
# 存储型技能（restore>0，可存多层/多段，如马超大招）：已存层数 / 上限（上限>0 表示这是存储型技能）。
# 每帧由 TouchController 推送；层数>0 时即便在回充下一层的 CD 中也可施放，不画满冷却遮罩。
var charge_now := 0
var charge_max := 0
# 施放前置条件不满足（如马超大招需身边有枪才能召回）→ 按钮置灰并显示 block_cue 提示
var blocked := false
var block_cue := ""
# 等级金环：外圈按技能最大等级均分小段，亮段数 = 当前技能等级（max_level=0 不绘制）
var skill_level := 0
var max_level := 0

func _ready():
	mouse_filter = MOUSE_FILTER_STOP
	# 尺寸由调用方通过 _anchor_br 显式指定（技能 260 / 召唤师·恢复 220）；
	# 仅当未显式设置时回退默认 110。
	if size.x <= 0.0:
		custom_minimum_size = Vector2(SIZE_V, SIZE_V)
		size = Vector2(SIZE_V, SIZE_V)
	set_process(true)

func _process(delta: float) -> void:
	var target := 1.0 if _active else 0.0
	if absf(_press - target) < 0.003:
		return
	_press = move_toward(_press, target, delta * 14.0)
	queue_redraw()

func is_held() -> bool:
	return _active

func get_drag() -> Vector2:
	return _drag if _active else Vector2.ZERO

# 当前手指所在位置（画布全局坐标），供取消施法按钮做「拖到其上」高亮检测
func get_touch_global() -> Vector2:
	if _active:
		return get_global_position() + _origin + _drag
	return Vector2.ZERO

func _gui_input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if _active_touch == -1:
				_active_touch = event.index
				_active = true
				_press = 1.0
				_origin = event.position
				_drag = Vector2.ZERO
				_max_drag = 0.0
				UiKit.haptic(5)
				pressed_changed.emit(skill_index, true)
				queue_redraw()
				accept_event()
		else:
			if event.index == _active_touch:
				# 记录松开时的最终拖拽与「拖回按钮取消」判定
				var final_drag: Vector2 = event.position - _origin
				var cancelled: bool = _max_drag > TAP_THRESHOLD and final_drag.length() < CANCEL_RADIUS
				var release_global: Vector2 = get_global_position() + event.position
				_active_touch = -1
				_active = false
				_drag = Vector2.ZERO
				_max_drag = 0.0
				pressed_changed.emit(skill_index, false)
				released.emit(skill_index, final_drag, cancelled, release_global)
				queue_redraw()
				accept_event()
	elif event is InputEventScreenDrag:
		if event.index == _active_touch:
			_drag = event.position - _origin
			_max_drag = maxf(_max_drag, _drag.length())
			queue_redraw()
			accept_event()
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		# 移动端 emulate_mouse_from_touch 会产生合成鼠标事件，吞掉防止漏到世界输入
		accept_event()

func _draw():
	var p := clampf(_press, 0.0, 1.0)
	var center := size * 0.5 + Vector2(0, p * 1.8)
	var radius := minf(size.x, size.y) * 0.45 * (1.0 - p * 0.022)
	# 字号/描边/金环等内部固定像素随按钮尺寸等比放大（设计基准 SIZE_V=110）
	var k := maxf(1.0, minf(size.x, size.y) / SIZE_V)
	# ---- 可用性/颜色：亮=可用，青=多段重施窗口，灰=不可用(未学/冷却/蓝不足)，红=前置不满足(无枪等) ----
	var unlearned := max_level > 0 and skill_level <= 0
	# 存储型技能：只要还有已存层数就视为可放（此时即便正在回充下一层也不画满冷却遮罩）；
	# 层数用尽后的回充则照常按冷却显示
	var charge_skill := charge_max > 0 and skill_level > 0
	var has_charge := charge_skill and charge_now > 0
	var on_cd := (not in_window) and cd_ratio > 0.001 and not has_charge
	var need_mana := (not in_window) and (not on_cd) and max_level > 0 and not mana_ok
	var usable := not unlearned and not on_cd and not need_mana and not blocked
	var ring_col: Color
	if _active:
		ring_col = color.lightened(0.3)
	elif in_window:
		ring_col = Color(0.35, 0.95, 1.0, 0.98)
	elif usable:
		ring_col = color.lightened(0.12)
	elif blocked:
		ring_col = Color(0.9, 0.38, 0.32, 0.95)
	else:
		ring_col = Color(0.42, 0.42, 0.46, 0.9)
	# 外圈：统一金属框 + 落影 + 顶部高光
	UiKit.touch_button_frame(self, center, radius, ring_col, p, 3.0, false)
	# 主体：功能图标（回城/恢复/召唤师 → 固定色，见 IconArt）；英雄技能 → 英雄元素色（SkillArt）
	if icon_kind != "":
		IconArt.draw_icon(self, center, radius, icon_kind, not usable)
	else:
		SkillArt.draw_bg(self, center, radius, art_hero, art_skill, skill_index, not unlearned, usable)
	# 技能名：英雄 1/2/3 技能 name_below=true → 内嵌按钮底部圆角条（元素色色条 + 字数多自动缩字号）；
	# 召唤师 / 恢复按钮 name_below=false → 名字居中画在按钮上
	if name_below:
		if display_name != "":
			var band_h := 30.0 * k
			var band := Rect2(center.x - radius * 0.92, center.y + radius - band_h + 2.0 * k,
				radius * 1.84, band_h)
			var acc: Color = Vfx.color_for_hero(art_hero) if art_hero != "" else color
			UiKit.chip(self, band, 0.72, 7.0 * k, acc)
			var cfs := int(18.0 * k)
			var inner_w := band.size.x - 14.0 * k
			while cfs > int(12.0 * k) and UiKit.font().get_string_size(
					display_name, HORIZONTAL_ALIGNMENT_CENTER, -1, cfs).x > inner_w:
				cfs -= 1
			_draw_txt(Vector2(band.position.x + 7.0 * k, band.position.y + band.size.y * 0.5 + cfs * 0.36),
				display_name, HORIZONTAL_ALIGNMENT_CENTER, inner_w, cfs,
				Color.WHITE if usable else Color(0.78, 0.80, 0.86))
	else:
		var label := ("" if icon_kind != "" else str(skill_index + 1)) if display_name == "" else display_name
		if label != "":
			var label_fs := int((24.0 if label.length() > 2 else 30.0) * k)
			_draw_txt(center + Vector2(-radius * 0.75, 6), label, HORIZONTAL_ALIGNMENT_CENTER, radius * 1.5, label_fs, Color.WHITE)
	# 拖动瞄准：摇杆头样式小圆（像移动轮盘一样），随拖拽方向移动
	if _active and _drag.length() > 12.0:
		var knob := center + _drag.normalized() * radius * 0.82
		var kr := maxf(18.0, 24.0 * k)
		draw_circle(knob + Vector2(0, 3), kr * 1.05, Color(0, 0, 0, 0.28))
		draw_circle(knob, kr + 2, Color(0.02, 0.025, 0.04, 0.9))
		draw_circle(knob, kr, Color(0.30, 0.37, 0.48, 0.94))
		draw_circle(knob - Vector2(0, kr * 0.12), kr * 0.86, Color(1, 1, 1, 0.24))
		draw_arc(knob, kr, 0, TAU, 32, Color(1, 1, 1, 0.78), maxf(2.0, kr * 0.1), true)
		draw_arc(knob - Vector2(0, kr * 0.18), kr * 0.74, -PI * 0.9, -PI * 0.1, 18,
			Color(1, 1, 1, 0.30), maxf(1.5, kr * 0.08), true)
	# 等级金环：贴外圈，按最大等级切成小段，已点亮段数 = 当前技能等级
	if max_level > 0:
		_draw_level_ring(center, radius, k)
	# 冷却/重施窗口叠层：多段重施窗口(青色扇形=窗口剩余比例) 与 完整冷却(暗色扇形) 二选一
	if in_window:
		var wr := clampf(win_left / maxf(win_total, 0.001), 0.0, 1.0)
		_draw_cd_sector(center, radius, wr, Color(0.3, 0.92, 1.0, 0.5), Color(1.0, 1.0, 1.0, 0.55))
		var ws := "%.1f" % win_left
		_draw_txt(center + Vector2(-radius * 0.55, 6), ws,
					HORIZONTAL_ALIGNMENT_CENTER, radius * 1.1, int(27.0 * k), Color(1.0, 1.0, 1.0))
		# 剩余段数：底部一排实心小圆点（剩余几段=几个点）
		if segments_left > 0:
			var n := segments_left
			var pw := maxf(3.0, radius * 0.1)
			var gap := pw * 2.1
			var x0 := center.x - (n - 1) * gap * 0.5
			var py := center.y + radius * 0.52
			for s in range(n):
				var pc := Vector2(x0 + s * gap, py)
				draw_circle(pc, pw, Color(0.95, 1.0, 1.0))
				draw_arc(pc, pw, 0, TAU, 10, Color(0.1, 0.35, 0.4, 0.6), 1.2, true)
	elif on_cd:
		_draw_cd_sector(center, radius, cd_ratio)
		var secs := ceili(cd_ratio * cd_total)
		_draw_txt(center + Vector2(-radius * 0.5, 6), "%d" % secs, HORIZONTAL_ALIGNMENT_CENTER, radius, int(26.0 * k), Color(1, 0.85, 0.3))
	# 存储型技能：已存层数>0 时画一圈细弧表示“下一层回充进度”（不做满遮罩、不盖住技能读数）
	if has_charge and cd_ratio > 0.001:
		var a_end := -PI * 0.5 + clampf(cd_ratio, 0.0, 1.0) * TAU
		draw_arc(center, radius - 1.0, -PI * 0.5, a_end, 20, Color(0.5, 0.85, 1.0, 0.55), 2.0, true)
	# 存储型技能：底部画充能层数点（实心=已有层数，空心=空位；最高层数/已存层数一目了然）
	if charge_skill:
		_draw_charge_pips(center, radius, k)
	# 前置状态门槛不可用（李白大招侠客 / 沈梦溪1、2炸弹 / 马超R枪 / 东皇2能量 / 兰陵王大招隐身）：
	# 非冷却/重施窗口期间在按钮中央斜切一道红色禁用斜杠（下方 block_cue 小字仍叠在斜杠上层）
	if blocked and not in_window and not on_cd:
		var sd := radius * 0.74
		var sa := center + Vector2(-sd, -sd)
		var sb := center + Vector2(sd, sd)
		var slw := maxf(6.0, radius * 0.12) * k
		draw_line(sa, sb, Color(0, 0, 0, 0.5), slw + 3.0 * k)
		draw_line(sa, sb, Color(1.0, 0.5, 0.45, 0.96), slw)

	# 前置不满足提示（如马超身边无枪）→ 无冷却遮罩期间显示在按钮中下方
	if blocked and not in_window and not on_cd and block_cue != "":
		_draw_txt(center + Vector2(-radius * 0.8, radius * 0.28), block_cue,
			HORIZONTAL_ALIGNMENT_CENTER, radius * 1.6, int(16.0 * k), Color(1.0, 0.5, 0.42))
	# 下方小字说明（惩击伤害等，不受冷却遮罩影响）
	if sub_text != "":
		_draw_txt(center + Vector2(-radius * 0.7, radius * 0.7), sub_text,
			HORIZONTAL_ALIGNMENT_CENTER, radius * 1.4, int(16.0 * k), Color(1.0, 0.85, 0.3))
	# 技能伤害 + 附加效果读数：英雄技能(名在下方、中央留空)已学且非瞄准/冷却/重施期间时，
	# 在中央偏上写“伤害×弹数”（物伤橙/法伤紫），其下逐行画效果小图标+数值/时长（绿=自身增益/蓝=对敌负面）
	if name_below and max_level > 0 and skill_level > 0 \
			and not _active and not in_window and not on_cd and not blocked:
		_draw_skill_readout(center, radius, k)

# 统一带描边文字（draw_string 无描边，3D 场景上纯白字会糊；参数顺序同 draw_string）
func _draw_txt(pos: Vector2, txt: String, align: int, width: float, fs: int, col: Color) -> void:
	UiKit.text(self, pos, txt, fs, col, align, width)

# 冷却/窗口扇形：从按钮正上方顺时针铺开的半透明扇形，覆盖面积 = 剩余占比；
# 完整冷却=暗色(金色弧光)，多段重施窗口=青色(白弧光)，随剩余时间缩短而收拢
func _draw_cd_sector(center: Vector2, radius: float, ratio: float,
		fill := Color(0, 0, 0, 0.6), edge := Color(1.0, 0.85, 0.32, 0.4)):
	var a0 := -PI * 0.5
	var a1 := a0 + clampf(ratio, 0.0, 1.0) * TAU
	var pts := PackedVector2Array()
	pts.append(center)
	var steps := 32
	for k in range(steps + 1):
		var a := lerpf(a0, a1, float(k) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(pts, fill)
	draw_arc(center, radius, a0, a1, 16, edge, 2.0, true)

# 存储型技能的充能层数点：底部一排小圆点，实心=当前已存层数，空心=待回充的空位。
# 当技能被“无枪”等前置卡住时整排置灰，明确告诉玩家层数在、但暂时放不出去。
func _draw_charge_pips(c: Vector2, R: float, k: float):
	var n := charge_max
	if n <= 0: return
	var cur := clampi(charge_now, 0, n)
	var pw := maxf(2.6, R * 0.055)
	var gap := pw * 2.6
	var x0 := c.x - (n - 1) * gap * 0.5
	var py := c.y + R * 0.66
	for i in range(n):
		var pc := Vector2(x0 + i * gap, py)
		if i < cur:
			var col := Color(0.62, 0.4, 0.95, 0.95) if blocked else Color(1.0, 0.85, 0.3, 1.0)
			draw_circle(pc, pw, col)
			draw_arc(pc, pw, 0, TAU, 10, Color(1, 1, 1, 0.3), 0.8, true)
		else:
			draw_arc(pc, pw, 0, TAU, 10, Color(1, 1, 1, 0.45), 1.4, true)

# 把“伤害×弹数 + 附加效果”读数叠画在按钮上：伤害大字放中央偏上，
# 效果小字（矢量图标 + 数值/时长）逐行排在下方；行数/宽度超界时自动缩字号、整体收拢进圆
func _draw_skill_readout(c: Vector2, R: float, k: float):
	var n := icon_fx.size()
	var has_dmg := icon_dmg > 0
	var has_aa := icon_aa
	if not has_dmg and n == 0 and not has_aa:
		return
	# 伤害文字：拆成若干彩色段并排（通常一段；双类型伤害——如狄仁杰每段同时命中物理+法术——
	# 拆成两段并排，各自按类型着色（物理橙在前/法术紫在后），共用同一弹数后缀“×N”）
	var dmg_segs: Array = []
	if has_dmg:
		var seg_txt := str(icon_dmg)
		if icon_count > 1:
			seg_txt += "×" + str(icon_count)
		var seg_col := Color(0.82, 0.55, 1.0) if icon_dmg_magic else Color(1.0, 0.6, 0.3)
		dmg_segs.append({"txt": seg_txt, "col": seg_col})
		if icon_dmg2 > 0:
			var seg2_txt := str(icon_dmg2)
			if icon_count > 1:
				seg2_txt += "×" + str(icon_count)
			var seg2_col := Color(0.82, 0.55, 1.0) if icon_dmg2_magic else Color(1.0, 0.6, 0.3)
			dmg_segs.append({"txt": seg2_txt, "col": seg2_col})
	# 伤害大字 / 效果小字（更小），越界整体缩小
	var dmg_gap := 6.0 * k
	var dmg_fs := int(24.0 * k)
	while has_dmg and dmg_fs > int(14.0 * k):
		var dmg_w := 0.0
		for sgm in dmg_segs:
			dmg_w += UiKit.font().get_string_size(
				String(sgm.get("txt", "")), HORIZONTAL_ALIGNMENT_CENTER, -1, dmg_fs).x
		dmg_w += dmg_gap * float(dmg_segs.size() - 1)
		# 附带强化普攻时，伤害数值最前面还要留出小剑宽度，故一并计入收拢判断
		var need := dmg_w + (dmg_fs * 1.15 + 5.0 * k) if has_aa else dmg_w
		if need <= R * 1.5:
			break
		dmg_fs -= int(2.0 * k)
	var fx_fs := int(15.0 * k)
	while n > 0 and fx_fs > int(9.0 * k):
		var ic_dd := maxf(9.0 * k, fx_fs * 1.15)
		var widest := 0.0
		for it in icon_fx:
			var w: float = UiKit.font().get_string_size(
				String(it.get("txt", "")), HORIZONTAL_ALIGNMENT_CENTER, -1, fx_fs).x
			widest = maxf(widest, w)
		if widest + ic_dd + 6.0 * k <= R * 1.8:
			break
		fx_fs -= int(1.0 * k)
	# 行高与纵向布局：内容中心放在中央偏上，多行时整体上移确保落在圆内。
	# 先按“最宽一行”缩字号（宽），再按“效果行数总高”整体收拢（高）：
	# 效果行多 → 先缩效果小字；仍超高 → 伤害大字也一起缩，保证全部落进圆
	var min_dmg_fs := int(14.0 * k)
	var min_fx_fs := int(9.0 * k)
	var ic_d := maxf(9.0 * k, fx_fs * 1.15)        # 效果图标直径（略大于小字字高）
	var dmg_h := float(dmg_fs) * 1.1 if has_dmg else 0.0
	var fx_h := maxf(ic_d, fx_fs * 1.1)
	# 强化普攻小剑：无直接伤害数字时占一行（画在效果行之上，位于读数最前）
	var aa_h := fx_h if (has_aa and not has_dmg) else 0.0
	var content_h := aa_h + dmg_h + fx_h * float(n)
	var max_h := R * 1.25
	while content_h > max_h and (fx_fs > min_fx_fs or dmg_fs > min_dmg_fs):
		if fx_fs > min_fx_fs:
			fx_fs -= int(1.0 * k)
		elif dmg_fs > min_dmg_fs:
			dmg_fs -= int(1.0 * k)
		ic_d = maxf(9.0 * k, fx_fs * 1.15)
		dmg_h = float(dmg_fs) * 1.1 if has_dmg else 0.0
		fx_h = maxf(ic_d, fx_fs * 1.1)
		aa_h = fx_h if (has_aa and not has_dmg) else 0.0
		content_h = aa_h + dmg_h + fx_h * float(n)
	var y_center := c.y - R * 0.26 if has_dmg else (c.y if has_aa else c.y + R * 0.06)
	var y0 := y_center - content_h * 0.5
	if y0 + content_h > c.y + R * 0.45:
		y0 = c.y + R * 0.45 - content_h
	y0 = maxf(y0, c.y - R * 0.85)
	# 强化普攻小剑：无直接伤害时为首行（居中，金色），起到“前面放一个普攻图标”的作用
	var y := y0
	if has_aa and not has_dmg:
		var sword_r := aa_h * (0.62 if n == 0 else 0.46)
		_draw_fx_glyph("aa", Vector2(c.x, y + aa_h * 0.5), sword_r, Color(1.0, 0.85, 0.3))
		y += aa_h
	# 伤害大字：一段或（双类型）两段并排，按各自颜色绘制（物理橙/法术紫）；
	# 附带强化普攻时数字最前再放一枚金色小剑作前置标识
	if has_dmg:
		var row_cy := y + dmg_h * 0.5
		var bl := row_cy + dmg_fs * 0.36
		# 整块伤害文字宽度（含分段间隙），用于整体水平居中
		var total_w := 0.0
		for sgm in dmg_segs:
			total_w += UiKit.font().get_string_size(
				String(sgm.get("txt", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, dmg_fs).x
		total_w += dmg_gap * float(dmg_segs.size() - 1)
		var x_left := c.x - total_w * 0.5
		if has_aa:
			var gd := maxf(8.0 * k, dmg_fs * 1.15)   # 小剑直径（与大字匹配）
			var gap := 5.0 * k
			x_left = c.x - (total_w + gd + gap) * 0.5
			_draw_fx_glyph("aa", Vector2(x_left + gd * 0.5, row_cy), gd * 0.5 * 0.92,
				Color(1.0, 0.85, 0.3))
			x_left += gd + gap
		var x := x_left
		for sgm in dmg_segs:
			var seg_txt := String(sgm.get("txt", ""))
			var seg_w := UiKit.font().get_string_size(
				seg_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, dmg_fs).x
			_draw_txt(Vector2(x, bl), seg_txt,
				HORIZONTAL_ALIGNMENT_LEFT, seg_w, dmg_fs, sgm.get("col", Color.WHITE))
			x += seg_w + dmg_gap
		y += dmg_h
	# 效果行：矢量小图标 + 数值/时长小字（icon 与文字同色：绿=自身增益 / 蓝=对敌负面）
	for it in icon_fx:
		var row_cy := y + fx_h * 0.5
		var kind := String(it.get("k", ""))
		var col: Color = it.get("col", Color.WHITE)
		var txt := String(it.get("txt", ""))
		var tw := UiKit.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fx_fs).x
		var x0 := c.x - (ic_d + 5.0 * k + tw) * 0.5
		_draw_fx_glyph(kind, Vector2(x0 + ic_d * 0.5, row_cy), ic_d * 0.5, col)
		_draw_txt(Vector2(x0 + ic_d + 5.0 * k, row_cy + fx_fs * 0.36), txt,
			HORIZONTAL_ALIGNMENT_LEFT, tw, fx_fs, col)
		y += fx_h

# 效果类型矢量小图标（小尺寸几何绘制，替代汉字节省按钮内宽度）
func _draw_fx_glyph(kind: String, pc: Vector2, r: float, col: Color):
	var lw := maxf(1.3, r * 0.18)
	match kind:
		"slow":   # 减速：下降箭头
			draw_line(pc + Vector2(0, -r), pc + Vector2(0, r * 0.42), col, lw)
			draw_line(pc + Vector2(-r * 0.72, r * 0.06), pc + Vector2(0, r * 0.5), col, lw)
			draw_line(pc + Vector2(r * 0.72, r * 0.06), pc + Vector2(0, r * 0.5), col, lw)
		"selfspeed", "msup":   # 自身加速：向右双“>”风线
			draw_line(pc + Vector2(-r * 0.85, -r * 0.45), pc + Vector2(0, 0), col, lw)
			draw_line(pc + Vector2(-r * 0.85, r * 0.45), pc + Vector2(0, 0), col, lw)
			draw_line(pc + Vector2(-r * 0.12, -r * 0.45), pc + Vector2(r * 0.75, 0), col, lw)
			draw_line(pc + Vector2(-r * 0.12, r * 0.45), pc + Vector2(r * 0.75, 0), col, lw)
		"stun":   # 眩晕：四芒星
			var sp := PackedVector2Array()
			for i in range(8):
				var ang := PI * 0.25 * float(i)
				var rad := r if i % 2 == 0 else r * 0.28
				sp.append(pc + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(sp, Color(col.r, col.g, col.b, 0.92))
		"knockup":   # 击飞：上升箭头
			draw_line(pc + Vector2(0, r), pc + Vector2(0, -r * 0.42), col, lw)
			draw_line(pc + Vector2(-r * 0.72, -r * 0.08), pc + Vector2(0, -r * 0.52), col, lw)
			draw_line(pc + Vector2(r * 0.72, -r * 0.08), pc + Vector2(0, -r * 0.52), col, lw)
		"freeze":   # 冰冻：菱形冰晶
			var ice: Array = [pc + Vector2(0, -r), pc + Vector2(r * 0.62, 0),
				pc + Vector2(0, r), pc + Vector2(-r * 0.62, 0)]
			for i in range(4):
				draw_line(ice[i], ice[(i + 1) % 4], col, lw)
			draw_line(pc + Vector2(0, -r), pc + Vector2(0, r), col, lw * 0.8)
		"suppress":   # 压制：双环锁链
			draw_arc(pc + Vector2(-r * 0.5, 0), r * 0.42, 0, TAU, 16, col, lw, true)
			draw_arc(pc + Vector2(r * 0.5, 0), r * 0.42, 0, TAU, 16, col, lw, true)
			draw_line(pc + Vector2(-r * 0.36, 0), pc + Vector2(r * 0.36, 0), col, lw)
		"bt":   # 霸体：六边形
			var hex := PackedVector2Array()
			for i in range(6):
				var ang := -PI * 0.5 + TAU / 6.0 * float(i)
				hex.append(pc + Vector2(cos(ang), sin(ang)) * r)
			for i in range(6):
				draw_line(hex[i], hex[(i + 1) % 6], col, lw)
		"shield":   # 护盾：盾形轮廓（顶平 + 下尖）
			var sh := PackedVector2Array([
				pc + Vector2(-r * 0.8, -r * 0.62), pc + Vector2(r * 0.8, -r * 0.62),
				pc + Vector2(r * 0.55, r * 0.12), pc + Vector2(0, r), pc + Vector2(-r * 0.55, r * 0.12)])
			draw_colored_polygon(sh, Color(col.r, col.g, col.b, 0.5))
			for i in range(4):
				draw_line(sh[i], sh[i + 1], col, lw)
		"heal":   # 治疗：圆环十字
			draw_arc(pc, r * 0.78, 0, TAU, 16, col, lw, true)
			draw_line(pc + Vector2(0, -r * 0.55), pc + Vector2(0, r * 0.55), col, lw)
			draw_line(pc + Vector2(-r * 0.55, 0), pc + Vector2(r * 0.55, 0), col, lw)
		"aa":   # 普攻（强化普攻前置标识）：上指小剑（剑身 + 护手 + 剑柄），金色
			var aa_tip := pc + Vector2(0, -r * 0.95)
			var aa_gy := r * 0.16
			var aa_blade := PackedVector2Array([
				aa_tip, pc + Vector2(r * 0.17, r * 0.1), pc + Vector2(r * 0.12, aa_gy),
				pc + Vector2(-r * 0.12, aa_gy), pc + Vector2(-r * 0.17, r * 0.1)])
			draw_colored_polygon(aa_blade, Color(col.r, col.g, col.b, 0.9))
			draw_line(pc + Vector2(0, -r * 0.62), pc + Vector2(0, aa_gy), col, lw * 0.8)  # 剑脊
			draw_line(pc + Vector2(-r * 0.62, aa_gy), pc + Vector2(r * 0.62, aa_gy), col, lw * 1.2)  # 护手
			draw_line(pc + Vector2(0, aa_gy + r * 0.08), pc + Vector2(0, r * 0.72), col, lw)  # 剑柄
			draw_circle(pc + Vector2(0, r * 0.8), maxf(lw, r * 0.09), col)  # 柄端圆珠
		"atkdn":   # 攻击力削减：下指“减攻”剑（与上方强化普攻剑互为上下镜像；蓝=对敌减益）
			var dn_tip := pc + Vector2(0, r * 0.95)
			var dn_gy := r * 0.16
			var dn_blade := PackedVector2Array([
				dn_tip, pc + Vector2(r * 0.17, -r * 0.1), pc + Vector2(r * 0.12, -dn_gy),
				pc + Vector2(-r * 0.12, -dn_gy), pc + Vector2(-r * 0.17, -r * 0.1)])
			draw_colored_polygon(dn_blade, Color(col.r, col.g, col.b, 0.9))
			draw_line(pc + Vector2(0, r * 0.62), pc + Vector2(0, -dn_gy), col, lw * 0.8)  # 剑脊
			draw_line(pc + Vector2(-r * 0.62, -dn_gy), pc + Vector2(r * 0.62, -dn_gy), col, lw * 1.2)  # 护手
			draw_line(pc + Vector2(0, -dn_gy - r * 0.08), pc + Vector2(0, -r * 0.72), col, lw)  # 剑柄
			draw_circle(pc + Vector2(0, -r * 0.8), maxf(lw, r * 0.09), col)  # 柄端圆珠
		"defup", "defdn":   # 双抗：双层护甲片（上方铆钉窄条 + 下宽甲），中心竖筋
			var dp := PackedVector2Array([
				pc + Vector2(-r * 0.9, -r * 0.4), pc + Vector2(r * 0.9, -r * 0.4),
				pc + Vector2(r * 0.95, r * 0.12), pc + Vector2(r * 0.55, r * 0.5),
				pc + Vector2(0, r * 0.72), pc + Vector2(-r * 0.55, r * 0.5),
				pc + Vector2(-r * 0.95, r * 0.12)])
			draw_colored_polygon(dp, Color(col.r, col.g, col.b, 0.35))
			for i in range(6):
				draw_line(dp[i], dp[(i + 1) % 6], col, lw)
			draw_line(pc + Vector2(-r * 0.85, -r * 0.06), pc + Vector2(r * 0.85, -r * 0.06), col, lw)   # 双层分界
			draw_circle(pc + Vector2(-r * 0.62, -r * 0.46), lw * 0.9, col)                              # 上排铆钉
			draw_circle(pc + Vector2(r * 0.62, -r * 0.46), lw * 0.9, col)
		"armup", "armdn", "armred":   # 护甲/护甲数值削减：单层甲片（与双抗区别：无分界横线/铆钉，含中心竖筋）
			var ap := PackedVector2Array([
				pc + Vector2(-r * 0.9, -r * 0.42), pc + Vector2(r * 0.9, -r * 0.42),
				pc + Vector2(r * 0.6, r * 0.42), pc + Vector2(0, r * 0.78),
				pc + Vector2(-r * 0.6, r * 0.42)])
			draw_colored_polygon(ap, Color(col.r, col.g, col.b, 0.35))
			for i in range(4):
				draw_line(ap[i], ap[i + 1], col, lw)
			draw_line(pc + Vector2(0, -r * 0.2), pc + Vector2(0, r * 0.52), col, lw)
		"mrup", "mrdn":   # 魔抗：菱形宝石（与冰冻区分：内部斜切面 + 下填充色块）
			var g := PackedVector2Array([
				pc + Vector2(0, -r * 0.9), pc + Vector2(r * 0.62, 0),
				pc + Vector2(0, r * 0.42), pc + Vector2(-r * 0.62, 0)])
			draw_colored_polygon(g, Color(col.r, col.g, col.b, 0.42))
			for i in range(4):
				draw_line(g[i], g[(i + 1) % 4], col, lw)
			draw_line(pc + Vector2(-r * 0.62, 0), pc + Vector2(r * 0.62, 0), col, lw * 0.8)   # 腰线
			draw_line(pc + Vector2(-r * 0.3, -r * 0.42), pc + Vector2(r * 0.3, -r * 0.42), col, lw * 0.8)   # 上切面
		"asup", "asdn":   # 攻速：钟表（外圆 + 时针与分针刻度），表走快=攻速快
			draw_arc(pc, r * 0.72, 0, TAU, 14, col, lw, true)
			draw_line(pc, pc + Vector2(-r * 0.28, -r * 0.48), col, lw)    # 时针
			draw_line(pc, pc + Vector2(r * 0.34, -r * 0.12), col, lw * 0.8)  # 分针
			draw_line(pc + Vector2(0, -r * 0.72), pc + Vector2(0, -r * 0.48), col, lw * 0.7)  # 12点刻度
		"cleanse":   # 净化/解除控制：斜向四射星芒 + 中心小环（净水涤荡感）
			for i in range(4):
				var a4 := -PI * 0.25 + float(i) * PI * 0.5
				var d4 := Vector2(cos(a4), sin(a4))
				draw_line(pc + d4 * r * 0.28, pc + d4 * r, col, lw)
			draw_arc(pc, r * 0.16, 0, TAU, 10, col, lw, true)
		"unsel":   # 无法选中/免伤免控：外圈 + 斜杠（不可命中之感）
			draw_arc(pc, r * 0.8, 0, TAU, 14, col, lw, true)
			draw_line(pc + Vector2(-r * 0.55, -r * 0.55), pc + Vector2(r * 0.55, r * 0.55), col, lw)
		_:   # 未知效果：空心圆
			draw_arc(pc, r * 0.55, 0, TAU, 12, col, lw, true)

# 外圈金环：等分成 max_level 段小弧，前 skill_level 段点金，其余暗灰
func _draw_level_ring(center: Vector2, radius: float, k: float = 1.0):
	var lit := clampi(skill_level, 0, max_level)
	var span := TAU / float(max_level)
	var gap := deg_to_rad(2.0)          # 段与段之间的缝隙
	var rr := radius + 6.0 + 3.0 * k    # 环半径（略在黑色外圈外侧，呈“镶边”效果）
	var th := maxf(5.0, 6.0 * k)
	for s in range(max_level):
		var a0 := -PI * 0.5 + span * s + gap * 0.5
		var a1 := -PI * 0.5 + span * (s + 1) - gap * 0.5
		if a1 <= a0:
			continue
		var col: Color
		if s < lit:
			col = Color(1.0, 0.85, 0.32, 1.0)     # 已学的亮金
		else:
			col = Color(0.42, 0.4, 0.36, 0.6)      # 未学的暗段
		draw_arc(center, rr, a0, a1, 10, col, th, true)
