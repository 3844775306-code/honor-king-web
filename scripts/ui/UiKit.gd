extends Node
## 全局 UI 设计令牌 + 共享工具（字体 / 尺度 / 安全区 / 层级 / 颜色 / 字号）。
## 目的：给 host、联机客户端、移动端自绘 HUD 一个统一来源，后续新 UI 不再各自硬编码。

# —— 设计画布（与 project.godot 的 2400x1400 一致）——
const DESIGN_W := 2400.0
const DESIGN_H := 1400.0
const SCALE_EXTRA := 1.35

# —— 9-slice 皮肤（assets/theme 下由脚本生成）——
const PANEL_TEX := preload("res://assets/theme/ui_panel.png")
const BTN_TEX_NORMAL := preload("res://assets/theme/ui_btn_normal.png")
const BTN_TEX_HOVER := preload("res://assets/theme/ui_btn_hover.png")
const BTN_TEX_PRESSED := preload("res://assets/theme/ui_btn_pressed.png")
const BTN_TEX_DISABLED := preload("res://assets/theme/ui_btn_disabled.png")
const ItemGlyph := preload("res://scripts/ui/ItemGlyph.gd")

# —— CanvasLayer 层级（统一收口，避免魔法数字）——
# ==== 全局 CanvasLayer 分层表（唯一口径，从低到高；新 UI 必须从这里取值，禁止硬编码）====
# 3D → 后处理 → 世界血条 → 主 HUD（主机 UI_Manager / 联机 HUD，同一画布内再用 z_index 分带）
#    → 选人 → 小地图/面板/提示 → 触控 → 飘字 → 遮罩 → 死亡回放 → 结算 → 加载
const LAYER_POSTFX := 1      # 全屏后处理：在 3D 之上、世界血条之下（不要盖住血条）
const LAYER_WORLD := 8       # 世界 UI：世界血条/英雄血条（battle.tscn 的 UI 画布）
const LAYER_HUD := 20        # 主 HUD 画布（主机 UI_Manager、联机客户端 HUD 都从 20 起）
const LAYER_PICK := 30       # 选人界面（盖住 HUD/世界血条）
const LAYER_DIM := 90        # 战斗内全屏压暗（死亡黑幕等：盖住 HUD/buff/小地图，低于触控与面板）
const LAYER_TOUCH := 100     # 触控摇杆/按键（在 HUD 面板之上，可点到）
const LAYER_POPUP := 103     # 数值/伤害飘字
const LAYER_MINIMAP := 80    # 小地图（联机 HUD 用；盖住 HUD、低于触控）
const LAYER_OVERLAY := 104   # 战斗内全屏遮罩（C/T 接管面板等）
const LAYER_RECAP := 105     # 死亡回放：盖住 HUD、buff 图标、飘字
const LAYER_RESULTS := 110   # 结算页
const LAYER_LOADING := 200   # 加载/过场（最高）

# ==== 同一画布内的 z_index 分带（不依赖 add_child 顺序，避免后建控件盖住面板）====
const Z_HUD := 10            # 常驻 HUD 控件（技能条/金币/buff 图标/目标面板/复活条）
const Z_HUD_TOP := 15        # HUD 上层（击杀播报等）
const Z_DIM := 50            # 全屏半透明遮罩（盖住 HUD，低于功能面板）
const Z_PANEL := 60          # 功能面板（商店/英雄详情/属性/队伍决策）
const Z_RECAP := 70          # 死亡回放（盖住遮罩与常驻 HUD）
const Z_TOOLTIP := 100       # 悬浮说明气泡（最上）

# —— 文本颜色 ——
const C_TEXT := Color(0.96, 0.96, 0.98)
const C_TEXT_DIM := Color(0.68, 0.72, 0.80)
const C_TEXT_DISABLED := Color(0.44, 0.47, 0.54)
const C_GOLD := Color(1.0, 0.84, 0.35)
const C_EXP := Color(0.55, 0.80, 1.0)
const C_DANGER := Color(1.0, 0.36, 0.30)
const C_HEAL := Color(0.45, 1.0, 0.55)
const C_ARMOR := Color(0.80, 0.78, 0.70)
const C_AP := Color(0.72, 0.62, 1.0)
const C_TEAM0 := Color(0.25, 0.85, 1.0)
const C_TEAM1 := Color(1.0, 0.40, 0.32)

# —— 面板 ——
const C_PANEL_BG := Color(0.055, 0.062, 0.088, 0.94)
const C_PANEL_EDGE := Color(0.52, 0.64, 0.86, 0.34)
const C_PANEL_HEADER := Color(0.085, 0.10, 0.15, 0.95)

# —— 品质色（白绿蓝紫橙红）——
const QUALITY_COLORS := [
	Color(0.86, 0.88, 0.92), Color(0.45, 0.90, 0.50), Color(0.35, 0.65, 1.0),
	Color(0.75, 0.45, 1.0), Color(1.0, 0.60, 0.20), Color(1.0, 0.30, 0.28),
]

# —— 触摸键玻璃底（P0：与面板同色系，替代原先各控件自用的中性黑）——
const C_GLASS := Color(0.075, 0.095, 0.135, 0.82)
const C_GLASS_HI := Color(0.55, 0.70, 0.95, 0.22)

# —— 阵营色三档（base / hi / glow），UI 统一从这里取 ——
const C_TEAM0_HI := Color(0.60, 0.94, 1.0)
const C_TEAM0_GLOW := Color(0.25, 0.85, 1.0, 0.35)
const C_TEAM1_HI := Color(1.0, 0.66, 0.55)
const C_TEAM1_GLOW := Color(1.0, 0.40, 0.32, 0.35)

# —— 字号（设计像素，实际使用乘 scale()）——
const FS_XS := 16
const FS_SM := 18
const FS_MD := 20
const FS_LG := 24
const FS_XL := 28
const FS_HUGE := 34

# —— 间距 ——
const SP_XS := 4
const SP_SM := 8
const SP_MD := 12
const SP_LG := 18

var _ui_theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui_theme = load("res://assets/theme/ui_theme.tres")
	# 项目 theme/custom_theme 在运行时不参与 Control 主题查找（实测 ThemeDB.get_project_theme() 为 null），
	# 因此在每个 Control 入树时显式挂主题：默认样式的 Panel/Button/Label 自动统一皮肤。
	var st := get_tree()
	if st != null and _ui_theme != null:
		st.node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Control:
		var c := node as Control
		if c.theme == null:
			c.theme = _ui_theme
		if c is Button and not c.has_meta("_uikit_feel"):
			c.set_meta("_uikit_feel", true)
			c.resized.connect(func(): c.pivot_offset = c.size * 0.5)
			c.button_down.connect(func(): punch(c))
			# 全界面统一点击音（大厅/备战/商店/结算所有按钮，含键盘激活）
			c.pressed.connect(func(): SfxManager.play_ui_sfx("ui_click"))


## 全局字体：项目已通过 [gui] theme/custom_font 设置了默认字体，
## 这里统一取默认主题字体，供 draw_string / draw_multiline_string 等自绘控件使用。
func font() -> Font:
	var f := ThemeDB.get_default_theme().default_font
	if f != null:
		return f
	return ThemeDB.fallback_font

## 自绘文字描边宽度：随字号线性增长（旧实现无论多大都只有 1px，等于没有描边）
func outline_size(font_size: float) -> int:
	return clampi(int(round(font_size * 0.14)), 2, 8)

## 自绘字符串（带描边）：3D 场景上直接画白字会糊，统一走「深色描边 + 主色字」。
## ci 为要绘制的 CanvasItem；其余参数与 draw_string 一致（align/width 可为 -1 左对齐）。
func text(ci: CanvasItem, pos: Vector2, txt: String, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if txt == "":
		return
	var f := font()
	var o := float(outline_size(font_size))
	var dark := Color(0, 0, 0, clampf(color.a, 0.55, 0.9))
	ci.draw_string_outline(f, pos, txt, align, width, font_size, int(o), dark)
	ci.draw_string(f, pos, txt, align, width, font_size, color)


## —— 圆角胶囊 / 物品图标 / 推荐装备卡：战况带、技能名条、推荐位共用的绘制原语 ——
## 圆角底 + 1px 冷边；accent 不透明时在左侧画一条竖色条（阵营/元素标识）
func chip(ci: CanvasItem, rect: Rect2, alpha := 0.86, radius := 14.0, accent := Color(0, 0, 0, 0)) -> void:
	ci.draw_style_box(flat(alpha, int(radius), 1, C_PANEL_EDGE, Color(0, 0, 0, 0), 0.0, 6.0), rect)
	if accent.a > 0.01:
		ci.draw_rect(Rect2(rect.position + Vector2(5.0, rect.size.y * 0.26),
			Vector2(3.0, rect.size.y * 0.48)), accent)

## 物品图标位：品质色圆角底 + 每件装备专属的程序化几何图案。
func item_icon(ci: CanvasItem, rect: Rect2, tier: int, item_name: String) -> void:
	var qc: Color = QUALITY_COLORS[clampi(tier, 1, 5)]
	ItemGlyph.draw(ci, rect, tier, qc, item_name)

## 推荐装备卡图标区：宽卡用满高图标；与金币等宽的窄卡收缩图标，给文字留出可读宽度
func rec_icon_rect(rect: Rect2) -> Rect2:
	var pad := 6.0
	var s: float = rect.size.y - pad * 2.0
	if rect.size.x < 300.0:
		s = minf(s, 78.0)
	return Rect2(rect.position + Vector2(pad, (rect.size.y - s) * 0.5), Vector2(s, s))

## 推荐装备卡：品质图标 + 名称 + 状态行（可买/还差/槽满/已成型）+ 装备效果一行简介 + 金币进度条
func rec_card(ci: CanvasItem, rect: Rect2, item_name: String, tier: int, cost: int, gold: int,
		maxed: bool, slot_full: bool, desc: String = "") -> void:
	var can := cost > 0 and gold >= cost
	var compact := rect.size.x < 300.0
	var accent := C_GOLD if can else (C_DANGER if slot_full else C_PANEL_EDGE)
	chip(ci, rect, 0.90, 14.0, accent)
	var pad := 6.0
	var ic := rec_icon_rect(rect)
	item_icon(ci, ic, tier, item_name)
	var tx := ic.position.x + ic.size.x + (8.0 if compact else 10.0)
	var avail := rect.position.x + rect.size.x - tx - 6.0
	var nm := item_name if item_name != "" else ("已成型" if maxed else "无推荐")
	var fs := int(rect.size.y * (0.22 if compact else 0.27))
	ci.draw_string_outline(font(), Vector2(tx, rect.position.y + rect.size.y * 0.34), nm,
		HORIZONTAL_ALIGNMENT_LEFT, avail, fs, 3, Color(0, 0, 0, 0.8))
	ci.draw_string(font(), Vector2(tx, rect.position.y + rect.size.y * 0.34), nm,
		HORIZONTAL_ALIGNMENT_LEFT, avail, fs, Color(1, 1, 1, 0.96))
	var sub := "-"
	if maxed: sub = "已成型"
	elif cost > 0:
		if compact:
			sub = "可买" if can else ("还差 %d 金" % (cost - gold))
		else:
			sub = ("%d 金 · 可买" % cost) if can else ("还差 %d 金" % (cost - gold))
	var sfs := int(rect.size.y * (0.155 if compact else 0.20))
	var sc := C_GOLD if can else (Color(1, 0.62, 0.35) if cost > 0 else Color(0.70, 0.72, 0.80))
	ci.draw_string_outline(font(), Vector2(tx, rect.position.y + rect.size.y * 0.58), sub,
		HORIZONTAL_ALIGNMENT_LEFT, avail, sfs, 2, Color(0, 0, 0, 0.8))
	ci.draw_string(font(), Vector2(tx, rect.position.y + rect.size.y * 0.58), sub,
		HORIZONTAL_ALIGNMENT_LEFT, avail, sfs, sc)
	# 效果简介：一行小字（超宽自动省略号）；槽满提示优先占这一行
	var dfs := int(rect.size.y * (0.125 if compact else 0.15))
	var line_y := rect.position.y + rect.size.y * 0.84
	if slot_full and not maxed:
		ci.draw_string(font(), Vector2(tx, line_y), "槽满·需合成",
			HORIZONTAL_ALIGNMENT_LEFT, avail, sfs, Color(1, 0.55, 0.35))
	elif desc != "":
		var dt := fit_text(font(), desc, avail, dfs)
		ci.draw_string(font(), Vector2(tx, line_y), dt,
			HORIZONTAL_ALIGNMENT_LEFT, avail, dfs, Color(0.74, 0.77, 0.85, 0.95))
	if cost > 0:
		var pr := clampf(float(gold) / float(cost), 0.0, 1.0)
		var bar := Rect2(rect.position + Vector2(pad, rect.size.y - 5.0),
			Vector2(rect.size.x - pad * 2.0, 3.0))
		ci.draw_rect(bar, Color(1, 1, 1, 0.12))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * pr, bar.size.y)),
			C_GOLD if can else Color(1, 0.55, 0.25))

## 装备效果简介：passive/active 首句；没有被动就用主要属性拼一句（小件也有东西可看）
func item_effect(item: Dictionary) -> String:
	var t := short_effect(str(item.get("passive", item.get("active", ""))))
	if t != "":
		return t
	var parts: Array = []
	for e in [["attack", "攻击"], ["magic_attack", "法强"], ["health", "生命"], ["armor", "物防"],
			["magic_resist", "法防"], ["attack_speed", "攻速%"], ["crit_chance", "暴击%"],
			["cooldown", "冷缩%"], ["speed", "移速"], ["lifesteal", "吸血%"],
			["armor_pen_percent", "物穿%"], ["magic_pen", "法穿"], ["mana", "蓝量"]]:
		var v := int(item.get(str(e[0]), 0))
		if v != 0:
			parts.append("%s+%d" % [str(e[1]), v])
		if parts.size() >= 3:
			break
	var out := ""
	for p in parts:
		out = str(p) if out == "" else out + " · " + str(p)
	return out

## 装备效果简介：取 passive（无则 active），截到第一个标点，只留一句短语
func short_effect(text: String) -> String:
	var t := text.strip_edges()
	if t == "":
		return ""
	for sep in ["，", "；", ",", ";", "。"]:
		var i := t.find(sep)
		if i > 0:
			t = t.substr(0, i)
			break
	return t.strip_edges()

## 按可用像素宽度裁剪字符串，超宽补省略号
func fit_text(f: Font, text: String, max_w: float, fs: int) -> String:
	if text == "" or max_w <= 0.0:
		return ""
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
		return text
	var t := text
	while t.length() > 1:
		t = t.substr(0, t.length() - 1)
		if f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_w:
			return t + "…"
	return ""

## 统一 9-slice 面板底板（深色渐变 + 描边 + 顶部高光）。
## alpha：整体透明度，替代原先的纯黑 StyleBoxFlat。
func panel_style(alpha: float = 0.94, pad: float = 10.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = PANEL_TEX
	sb.texture_margin_left = 16.0
	sb.texture_margin_top = 16.0
	sb.texture_margin_right = 16.0
	sb.texture_margin_bottom = 16.0
	sb.modulate_color = Color(1, 1, 1, alpha)
	sb.content_margin_left = pad
	sb.content_margin_top = pad
	sb.content_margin_right = pad
	sb.content_margin_bottom = pad
	return sb


## 统一按钮底板（normal/hover/pressed/disabled 四态，9-slice）。
func button_style(state: String = "normal", alpha: float = 1.0) -> StyleBoxTexture:
	var tex: Texture2D = BTN_TEX_NORMAL
	match state:
		"hover": tex = BTN_TEX_HOVER
		"pressed": tex = BTN_TEX_PRESSED
		"disabled": tex = BTN_TEX_DISABLED
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 16.0
	sb.texture_margin_top = 16.0
	sb.texture_margin_right = 16.0
	sb.texture_margin_bottom = 16.0
	sb.content_margin_left = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 8.0
	sb.modulate_color = Color(1, 1, 1, alpha)
	return sb


## —— 统一扁平皮肤（P0）——
## 卡片 / 芯片 / 标签 / 按钮 / 提示条一律走这里，避免各文件自建 StyleBoxFlat
## 造成圆角、描边、内高光、选中发光不一致。
func flat(alpha: float = 0.92, radius: int = 12, border: int = 1,
		edge: Color = C_PANEL_EDGE, bg: Color = Color(0, 0, 0, 0),
		pad: float = 10.0, shadow: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var base := C_PANEL_BG
	base.a = alpha
	sb.bg_color = base if bg.a <= 0.0 else bg
	sb.set_corner_radius_all(radius)
	sb.set_corner_detail(8)
	sb.set_border_width_all(border)
	sb.border_color = edge
	sb.border_blend = true
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	if shadow > 0.0:
		sb.shadow_size = int(shadow)
		sb.shadow_color = Color(0, 0, 0, 0.45)
	return sb


## 卡片：品级/角色色描边；选中态加亮 + 同色外发光。
func skin_card(accent: Color, selected: bool = false, alpha: float = 0.92) -> StyleBoxFlat:
	var edge := accent if selected else Color(accent.r, accent.g, accent.b, 0.32)
	var sb := flat(alpha, 10, 2 if selected else 1, edge)
	if selected:
		sb.bg_color = sb.bg_color.lightened(0.06)
		sb.shadow_size = 6
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.22)
	return sb


## 芯片/小面板：单个控件用的低对比底板。
func skin_chip(accent: Color = C_PANEL_EDGE, alpha: float = 0.9, radius: int = 10) -> StyleBoxFlat:
	return flat(alpha, radius, 1, accent)


## 标签/徽章：带淡色底的强调标签。
func skin_tag(accent: Color) -> StyleBoxFlat:
	var sb := flat(0.95, 8, 1, accent)
	sb.bg_color = Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.95)
	return sb


## 按钮四态（filled=true 主行动键用实心强调色）。
## 质感来自三层：底色明暗 + 外投影（hover 时为强调色辉光）+ 顶部 2px 高光位（上方 border 提亮）。
func skin_button(state: String = "normal", accent: Color = C_GOLD, filled: bool = false) -> StyleBoxFlat:
	var a := 0.95
	var edge := accent
	var lift := 0.0
	var shadow := 10.0
	match state:
		"hover":
			a = 1.0
			edge = accent.lightened(0.25)
			lift = 0.09
			shadow = 16.0
		"pressed":
			a = 0.9
			lift = -0.06
			shadow = 3.0
		"disabled":
			a = 0.5
			edge = Color(1, 1, 1, 0.16)
			shadow = 4.0
	var sb := flat(a, 10, 1, edge, Color(0, 0, 0, 0), 10.0, shadow)
	sb.shadow_offset = Vector2(0, 3)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	if state != "disabled":
		if filled:
			var base := Color(accent.r, accent.g, accent.b, a)
			sb.bg_color = base.lightened(lift)
			sb.border_color = accent.lightened(0.35 + lift)
		else:
			var base := C_PANEL_BG
			base.a = a
			sb.bg_color = base.lightened(lift)
			sb.border_color = edge
	if state == "hover":
		sb.shadow_color = Color(accent.r, accent.g, accent.b, 0.30)
		sb.expand_margin_left = 2.0
		sb.expand_margin_right = 2.0
		sb.expand_margin_top = 2.0
		sb.expand_margin_bottom = 2.0
	return sb


## 提示条 / 横幅：一侧强调色描边，用于战报、系统提示。
func skin_notice(accent: Color = C_GOLD) -> StyleBoxFlat:
	return flat(0.92, 10, 1, Color(accent.r, accent.g, accent.b, 0.55), Color(0, 0, 0, 0), 10.0, 8.0)


const BACKDROP_SCRIPT := preload("res://scripts/ui/UiBackdrop.gd")


## 给全屏 Control 铺一层程序化背景（置于最底层，自动铺满），返回背景节点。
func make_backdrop(parent: Control, accent: Color = C_TEAM0, glow: float = 1.0) -> Control:
	if parent == null:
		return null
	var bd: Control = BACKDROP_SCRIPT.new()
	bd.accent = accent
	bd.glow_strength = glow
	parent.add_child(bd)
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.move_child(bd, 0)
	return bd


## 把统一主题挂到某个 Control 上：definite 面板根节点用，子节点自动继承。
func apply_theme(control: Control) -> void:
	if control != null and _ui_theme != null and control.theme == null:
		control.theme = _ui_theme


## —— 动效 ——
## 面板打开：透明度 0→1（150ms 缓出），不改变布局与锚点。
func show_panel(control: Control, dur: float = 0.15) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.visible = true
	control.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(control, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## 面板关闭：透明度 1→0 后隐藏（120ms 缓入）。
func hide_panel(control: Control, dur: float = 0.12) -> void:
	if control == null or not is_instance_valid(control):
		return
	if not control.visible:
		return
	var tw := create_tween()
	tw.tween_property(control, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): if is_instance_valid(control): control.visible = false)


## 按钮按下反馈：0.96 缩放回弹（pivot 居中），移动端附加轻震动。
func punch(control: Control, amount: float = 0.96, dur: float = 0.10) -> void:
	if control == null or not is_instance_valid(control):
		return
	control.pivot_offset = control.size * 0.5
	var tw := create_tween()
	tw.tween_property(control, "scale", Vector2.ONE * amount, dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(control, "scale", Vector2.ONE, dur * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	haptic(10)


## 轻震动（仅移动端，毫秒）。
func haptic(ms: int = 12) -> void:
	if Config.on_mobile():
		Input.vibrate_handheld(ms)


## 圆形触控键的金属外框/落影/光晕（画在图标底盘之前；press=0..1 为按下深度）。
func touch_button_frame(ci: CanvasItem, center: Vector2, radius: float, accent: Color,
		press: float = 0.0, ring_w: float = 3.0, dim: bool = false) -> void:
	if ci == null or radius <= 0.0:
		return
	var p := clampf(press, 0.0, 1.0)
	var c := center + Vector2(0, p * 1.8)
	var r := radius * (1.0 - p * 0.014)
	var a := 0.55 if dim else 1.0
	ci.draw_circle(c + Vector2(0, 5.0 - p * 2.0), r + 8.5, Color(0, 0, 0, 0.30 * a))
	if not dim:
		ci.draw_circle(c, r + 7.0, Color(accent.r, accent.g, accent.b, 0.045 + 0.045 * p))
	ci.draw_circle(c, r + 2.5, Color(0.015, 0.020, 0.032, 0.92 * a))
	ci.draw_arc(c, r + 1.5, 0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.78 * a), ring_w, true)
	ci.draw_arc(c, r + 0.5, -PI * 0.93, -PI * 0.07, 24,
		Color(1, 1, 1, 0.24 * a), maxf(1.0, r * 0.028), true)
	ci.draw_arc(c, r + 0.5, PI * 0.12, PI * 0.88, 24,
		Color(accent.r, accent.g, accent.b, 0.18 * a), maxf(1.5, r * 0.032), true)


## 圆形触控键的玻璃主体（文字键使用；图标键由 IconArt/SkillArt 自绘底盘）。
func touch_button_glass(ci: CanvasItem, center: Vector2, radius: float, accent: Color,
		press: float = 0.0, dim: bool = false) -> void:
	if ci == null or radius <= 0.0:
		return
	var p := clampf(press, 0.0, 1.0)
	var c := center + Vector2(0, p * 1.8)
	var r := radius * (1.0 - p * 0.014)
	var a := 0.55 if dim else 1.0
	ci.draw_circle(c, r, Color(0.045, 0.058, 0.085, 0.90 * a + 0.03))
	for i in range(7):
		var t := 1.0 - float(i) / 6.0
		ci.draw_circle(c - Vector2(0, r * 0.05 * t), r * 0.94 * t,
			Color(0.18, 0.25, 0.38, 0.045 * a))
	ci.draw_circle(c + Vector2(0, r * 0.16), r * 0.78, Color(0, 0, 0, 0.10 * a))
	ci.draw_arc(c, r - 1.5, 0, TAU, 44, Color(1, 1, 1, 0.10 * a),
		maxf(1.2, r * 0.018), true)
	ci.draw_arc(c - Vector2(0, r * 0.18), r * 0.78, -PI * 0.92, -PI * 0.08, 28,
		Color(1, 1, 1, 0.18 * a), maxf(1.8, r * 0.045), true)
	ci.draw_arc(c - Vector2(0, r * 0.23), r * 0.52, -PI * 0.82, -PI * 0.18, 20,
		Color(1, 1, 1, 0.10 * a), maxf(1.4, r * 0.025), true)
	ci.draw_arc(c + Vector2(0, r * 0.14), r * 0.80, PI * 0.15, PI * 0.85, 24,
		Color(accent.r, accent.g, accent.b, 0.10 * a), maxf(1.4, r * 0.025), true)


## 虚线圆环：用于摇杆激活区/方向刻度，比一根实线圈更像仪表盘。
func touch_dash_ring(ci: CanvasItem, center: Vector2, radius: float, col: Color,
		width: float = 2.0, segments: int = 40) -> void:
	if ci == null or radius <= 0.0 or segments <= 0:
		return
	var step := TAU / float(segments)
	for i in range(segments):
		var a0 := step * float(i)
		ci.draw_arc(center, radius, a0, a0 + step * 0.52, 3, col, width, true)


## 与既有 UI_Manager.ui_scale() 完全一致的尺度（本批不改视觉，仅统一来源）。
func scale() -> float:
	var vp := get_viewport()
	if vp == null:
		return SCALE_EXTRA
	return maxf(1.0, vp.get_visible_rect().size.x / DESIGN_W) * SCALE_EXTRA


## 伤害飘字基础字号：与伤害值正相关（1 点≈16px，1000 点≈56px，封顶 80px），暴击额外 +10。
## 单机/联机/回放共用，避免三端字号档位不一致。
func damage_number_size(damage: float, is_crit: bool = false) -> int:
	var px := 16.0 + maxf(damage, 0.0) * 0.04 + (10.0 if is_crit else 0.0)
	return clampi(int(round(px)), 16, 80)


## 安全区内缩（虚拟像素，Vector4: left/top/right/bottom）。
## 仅在移动端生效；桌面返回全 0，避免 Windows 上 safe_area 是整块屏幕导致误缩。
func safe_insets() -> Vector4:
	if not Config.on_mobile():
		return Vector4.ZERO
	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.x <= 0 or sa.size.y <= 0:
		return Vector4.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector4.ZERO
	var vs := vp.get_visible_rect().size
	var sx := vs.x / float(win.x)
	var sy := vs.y / float(win.y)
	return Vector4(
		maxf(0.0, float(sa.position.x)) * sx,
		maxf(0.0, float(sa.position.y)) * sy,
		maxf(0.0, float(win.x - sa.position.x - sa.size.x)) * sx,
		maxf(0.0, float(win.y - sa.position.y - sa.size.y)) * sy
	)


func safe_top() -> float:
	return safe_insets().y


func safe_bottom() -> float:
	return safe_insets().w


func safe_left() -> float:
	return safe_insets().x


func safe_right() -> float:
	return safe_insets().z


## 顶部锚定的控件统一避让刘海/挖孔：整体下移 + 高度不变。
func apply_safe_top(control: Control, extra: float = 0.0) -> void:
	if control == null:
		return
	var inset := safe_top() + extra
	if inset <= 0.0:
		return
	control.offset_top += inset
	control.offset_bottom += inset


## 底部锚定的控件统一避让手势条。
func apply_safe_bottom(control: Control, extra: float = 0.0) -> void:
	if control == null:
		return
	var inset := safe_bottom() + extra
	if inset <= 0.0:
		return
	control.offset_top -= inset
	control.offset_bottom -= inset
