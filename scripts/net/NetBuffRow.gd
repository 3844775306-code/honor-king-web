class_name NetBuffRow
extends Control
## P3b：接管客户端的「buff 图标行」——复刻主机 UI_Manager 的 buff 行（collect_buff_rows /
## BuffIcon / BuffInfo 详情弹层）同款几何与绘制：两行水平居中（上排=减益/控制/敌方印记，
## 下排=增益/己方印记），复用 UI_Manager.BuffIcon（CELL 132×136/R52 的 2× 规格）。
## 数据源 = host own.buffs（NetSession._pack_buff_rows，与主机 collect_buff_rows 同源，
## 一行 cfg 展为 [key,glyph,[r,g,b],name,desc,remaining,total,steady,sub]）。
## 只读复刻：不参与任何模拟，绝不回写 host。挂在 CanvasLayer 60（HUD 20 上、小地图 80 下）。

const CELL_W := 132.0
const CELL_H := 136.0
const BUFF_ROW_Y := 980.0       # 同主机 UI_Manager.gd：下排图标格顶边 y
const ROW_GAP := 6.0
const INFO_W := 460.0           # 同主机 BUFF_INFO_W

var _nodes: Dictionary = {}     # key -> BuffIcon（跨帧复用池）
var _info: Panel
var _info_title: Label
var _info_desc: Label
var _sel_key := ""
var built := false


# 同主机 UI_Manager.ui_scale()：字号统一 × 该系数（几何仍用原始像素）。
func _us() -> float:
	return UiKit.scale()

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var us := _us()
	# 详情弹层（同主机 BuffInfoPanel：_apply_panel_style(0.88) 纯黑半透明，标题金字 + 说明白字）
	_info = Panel.new()
	_info.name = "BuffInfoPanel"
	_info.add_theme_stylebox_override("panel", UiKit.flat(0.88, 12, 1, UiKit.C_PANEL_EDGE, Color(0, 0, 0, 0), 10.0, 6.0))   # 同 host _apply_panel_style(0.88)
	_info.visible = false
	add_child(_info)
	_info_title = Label.new()
	_info_title.position = Vector2(15, 10)
	_info_title.size = Vector2(INFO_W - 30, 0)
	_info_title.add_theme_font_size_override("font_size", int(round(18 * us)))
	_info_title.add_theme_color_override("font_color", UiKit.C_GOLD)
	_info_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	_info_title.add_theme_constant_override("outline_size", UiKit.outline_size(18 * us))
	_info.add_child(_info_title)
	_info_desc = Label.new()
	_info_desc.position = Vector2(15, 40)
	_info_desc.size = Vector2(INFO_W - 30, 0)
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.add_theme_font_size_override("font_size", int(round(14 * us)))
	_info_desc.add_theme_color_override("font_color", Color.WHITE)
	_info_desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	_info_desc.add_theme_constant_override("outline_size", UiKit.outline_size(14 * us))
	_info.add_child(_info_desc)
	built = true

func _clean_tier(cur: Dictionary, keys: Array, y: float, vw: float) -> void:
	# 一行水平居中排布（同主机 _layout_buff_row）
	if keys.size() == 0:
		return
	var row_w: float = keys.size() * CELL_W
	var x0 := (vw - row_w) * 0.5
	for i in range(keys.size()):
		var key: String = keys[i]
		var node = cur.get(key)
		if not node:
			continue
		node.size = Vector2(CELL_W, CELL_H)
		node.position = Vector2(x0 + i * CELL_W, y)
		node.visible = true
		node.selected = (key == _sel_key)

func refresh(buffs: Dictionary) -> void:
	if not built:
		_build()
	if not (buffs is Dictionary):
		buffs = {}
	var top_cfgs: Array = buffs.get("top", [])
	var bot_cfgs: Array = buffs.get("bot", [])
	var cur: Dictionary = {}
	for c in top_cfgs:
		_apply_row(c, cur)
	for c in bot_cfgs:
		_apply_row(c, cur)
	# 移除本轮未出现的图标
	for key in _nodes.keys():
		if not cur.has(key):
			var dead = _nodes[key]
			_nodes.erase(key)
			dead.visible = false
			dead.queue_free()
	# 两行水平居中：上排减益 / 下排增益（仅存在减益时也贴底排布）
	var vw := get_viewport().get_visible_rect().size.x
	var bot_keys: Array = []
	for c in bot_cfgs:
		bot_keys.append(str(c[0]))
	var top_keys: Array = []
	for c in top_cfgs:
		top_keys.append(str(c[0]))
	if bot_keys.size() > 0:
		_clean_tier(cur, bot_keys, BUFF_ROW_Y, vw)
	if top_keys.size() > 0:
		var ty: float = BUFF_ROW_Y if bot_keys.size() == 0 else (BUFF_ROW_Y - (CELL_H + ROW_GAP))
		_clean_tier(cur, top_keys, ty, vw)
	# 选中详情跟随刷新 / 消失关闭
	if _sel_key == "":
		return
	if cur.has(_sel_key):
		_update_info(cur[_sel_key], vw)
	else:
		_close_info()

func _apply_row(c: Array, cur: Dictionary) -> void:
	# c = [key, glyph, [r,g,b], name, desc, remaining, total, steady, sub]
	var key: String = str(c[0])
	var node = _nodes.get(key)
	if not node:
		node = UI_Manager.BuffIcon.new()
		node.key = key
		add_child(node)
		node.mouse_filter = Control.MOUSE_FILTER_STOP   # BuffIcon._ready 置 IGNORE，此处开启点按
		node.gui_input.connect(_on_icon_input.bind(key))
		_nodes[key] = node
	var rgb: Array = c[2]
	node.apply({
		"glyph": str(c[1]),
		"tint": Color(rgb[0], rgb[1], rgb[2]),
		"name": str(c[3]),
		"desc": str(c[4]),
		"remaining": float(c[5]),
		"total": float(c[6]),
		"steady": bool(c[7]),
		"sub": str(c[8]),
	})
	cur[key] = node

func _on_icon_input(ev: InputEvent, key: String) -> void:
	var press := (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)
	if not press:
		return
	if _sel_key == key:
		_close_info()
	else:
		_sel_key = key
		var node = _nodes.get(key)
		if node:
			_update_info(node, get_viewport().get_visible_rect().size.x)

func _close_info() -> void:
	_sel_key = ""
	if _info:
		_info.visible = false

func _update_info(node, vw: float) -> void:
	var txt: String = node.effect_desc
	if _info_desc.text != txt:
		_info_title.text = node.display_name
		_info_desc.text = txt
		# 按行数自适应高度（同主机 _resize_buff_info：标题 18、正文 14，均按 ui_scale 放大后测量）
		var font: Font = UiKit.font()
		var us := _us()
		var tfs := int(round(18 * us))
		var dfs := int(round(14 * us))
		var title_h := float(font.get_height(tfs))
		var text_w := INFO_W - 30.0
		var n := 1
		var acc := 0.0
		for i in txt.length():
			acc += font.get_char_size(txt.unicode_at(i), dfs).x
			if acc > text_w:
				n += 1
				acc = 0.0
		var desc_h := float(font.get_height(dfs)) * float(n)
		_info.size = Vector2(INFO_W, 12.0 + title_h + 4.0 + desc_h + 10.0)
		_info_title.size = Vector2(text_w, title_h)
		_info_title.position = Vector2(15, 10)
		_info_desc.size = Vector2(text_w, desc_h)
		_info_desc.position = Vector2(15, 10.0 + title_h + 4.0)
	_info.visible = true
	_position_info(node, vw)

func _position_info(node, vw: float) -> void:
	var W: float = _info.size.x
	var half := W * 0.5
	var lo := half + 10.0
	var hi := maxf(lo, vw - half - 10.0)
	var cx := clampf(float(node.position.x) + float(node.size.x) * 0.5, lo, hi)
	var py: float = float(node.position.y) - _info.size.y - 10.0
	if py < 96.0:
		py = float(node.position.y) + float(node.size.y) + 12.0
	_info.position = Vector2(cx - half, py)

