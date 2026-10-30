class_name NetTargetPanel
extends Control
## P3a：接管客户端的「攻击目标信息框」——复刻主机 UI_Manager._create_target_detail_panel
## （scripts/ui/UI_Manager.gd:291）的 DOM 几何与 _update（同文件 2714 段）逐字节一致：
## 位置基底 2400×1400（横屏 stretch 画布，含 expand），框体/子件尺寸 ×rs(=ui_scale)。
## 数据源=host own 块 tgt 摘要（NetSession._pack_target：[] 或 [nid,team,name,lvl,hp,maxhp,atk,ap,armor,mr]）。
## 只读复刻：本控件不含任何模拟，绝不回写 host。


var _panel: Panel
var _accent: ColorRect
var _team_dot: ColorRect
var _hp_fill: StyleBoxFlat
var _labels: Dictionary = {}
var _attrs := ["攻击", "法强", "护甲", "魔抗"]
var _tints := {
	"攻击": Color(1.0, 0.58, 0.2),
	"法强": Color(0.82, 0.5, 1.0),
	"护甲": Color(1.0, 0.8, 0.32),
	"魔抗": Color(0.4, 0.88, 1.0),
}

func ui_scale() -> float:
	return UiKit.scale()

func _styl(lab: Label, font_size: int, col: Color) -> void:
	# 同主机 _apply_label_style：字号 × ui_scale()，并加黑色 1px 描边
	lab.add_theme_font_size_override("font_size", int(round(font_size * ui_scale())))
	lab.add_theme_color_override("font_color", col)
	lab.add_theme_color_override("font_outline_color", Color.BLACK)
	lab.add_theme_constant_override("outline_size", 1)

func _build() -> void:
	var rs := ui_scale()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = Panel.new()
	# 位置基底不乘 rs（同主机）；刘海/挖孔避让（桌面 safe_* 为 0）
	_panel.position = Vector2(40 + UiKit.safe_left(), 370 + UiKit.safe_top())
	_panel.size = Vector2(330 * rs, 170 * rs)
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(0.94, 8.0))
	_panel.visible = false
	add_child(_panel)

	# 顶部阵营色强调条 + 姓名前同色小方块（颜色随目标阵营刷新）
	_accent = ColorRect.new()
	_accent.position = Vector2.ZERO
	_accent.size = Vector2(330, 5) * rs
	_panel.add_child(_accent)
	_team_dot = ColorRect.new()
	_team_dot.position = Vector2(16, 13) * rs
	_team_dot.size = Vector2(10, 10) * rs
	_panel.add_child(_team_dot)

	var name_label := Label.new()
	name_label.position = Vector2(32, 8) * rs
	name_label.size = Vector2(180, 26) * rs
	_styl(name_label, 17, Color.WHITE)
	_panel.add_child(name_label)
	_labels["name"] = name_label

	var lv_label := Label.new()
	lv_label.position = Vector2(224, 10) * rs
	lv_label.size = Vector2(92, 22) * rs
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_styl(lv_label, 14, Color(1.0, 0.82, 0.35))
	_panel.add_child(lv_label)
	_labels["level"] = lv_label

	var hp_bar := ProgressBar.new()
	hp_bar.position = Vector2(16, 44) * rs
	hp_bar.size = Vector2(298, 17) * rs
	hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0, 0, 0, 0.6)
	hp_bg.set_corner_radius_all(8)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.2, 0.9, 1.0)
	_hp_fill.set_corner_radius_all(8)
	hp_bar.add_theme_stylebox_override("fill", _hp_fill)
	_panel.add_child(hp_bar)
	_labels["hp_bar"] = hp_bar

	var hp_text := Label.new()
	hp_text.position = Vector2(16, 44) * rs
	hp_text.size = Vector2(298, 17) * rs
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_styl(hp_text, 11, Color(1, 1, 1, 0.92))
	_panel.add_child(hp_text)
	_labels["hp"] = hp_text

	# 属性区 2×2：彩色圆徽章（复用主机 StatIcon）+ 属性色数值
	var cols: Array[float] = [16.0, 168.0]
	for i in range(4):
		var attr: String = _attrs[i]
		var col_x: float = cols[i % 2]
		var row_y: float = 82.0 if i < 2 else 118.0
		var icon := UI_Manager.StatIcon.new()
		icon.shape = {"攻击": "sword", "法强": "spark", "护甲": "shield", "魔抗": "gem"}.get(attr, "")
		icon.tint = _tints[attr]
		icon.position = Vector2(col_x, row_y) * rs
		icon.size = Vector2(26, 26) * rs
		_panel.add_child(icon)
		var lab := Label.new()
		lab.position = Vector2(col_x + 35, row_y) * rs
		lab.size = Vector2(118, 28) * rs
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_styl(lab, 18, _tints[attr])
		_panel.add_child(lab)
		_labels[attr] = lab

	built = true

var built := false

func refresh(a: Array) -> void:
	if not built:
		_build()
	if a.is_empty():
		UiKit.hide_panel(_panel, 0.10)
		return
	# a = [nid, team, name, lvl, hp, maxhp, atk, ap, armor, mr]
	var team := int(a[1])
	var tcol := Color(1.0, 0.45, 0.2)     # 默认敌方橙红
	if team == 0:                          # Config.Team.PLAYER
		tcol = Color(0.2, 0.9, 1.0)
	elif team == 2:                        # Config.Team.NEUTRAL
		tcol = Color(1.0, 0.8, 0.35)
	_accent.color = tcol
	_team_dot.color = tcol
	_hp_fill.bg_color = tcol
	if not _panel.visible:
		UiKit.show_panel(_panel, 0.12)
	else:
		_panel.visible = true

	var name_lab: Label = _labels["name"]
	name_lab.text = str(a[2])
	name_lab.add_theme_color_override("font_color", tcol.lightened(0.3))
	var lv_lab: Label = _labels["level"]
	var lvl := int(a[3])
	lv_lab.text = "Lv.%d" % lvl if lvl > 0 else ""
	var hp_bar: ProgressBar = _labels["hp_bar"]
	var maxhp := maxf(1.0, float(a[5]))
	hp_bar.max_value = maxhp
	hp_bar.value = clampf(float(a[4]), 0.0, maxhp)
	_labels["hp"].text = "%d / %d" % [int(a[4]), int(a[5])]
	_labels["攻击"].text = "%d" % int(a[6])
	_labels["法强"].text = "%d" % int(a[7])
	_labels["护甲"].text = "%d" % int(a[8])
	_labels["魔抗"].text = "%d" % int(a[9])
