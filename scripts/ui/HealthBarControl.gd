class_name HealthBarControl
extends Control

var max_value: float = 100.0
var current_value: float = 100.0
var team_color: Color = Color.WHITE
var always_show: bool = false

# 护盾值
var shield_value: float = 0.0
var interfere_value: float = 0.0   # 干扰条剩余比例(0-1)，防御塔被干扰时显示在血条上方

# 史诗怪物（暴君/主宰/风暴龙王）：大号紫色分格血条，每格 7000 点生命
var epic_mode: bool = false
const EPIC_HP_PER_CELL: float = 7000.0

# 血条前/旁的金色护盾图标（原初羁绊减伤、防御塔无兵线保护时点亮）
var show_shield_icon: bool = false

# 受伤闪橙
var damage_flash_amount: float = 0.0
var damage_flash_timer: float = 0.0

# 回血渐深
var heal_amount: float = 0.0
var heal_timer: float = 0.0

# 上一帧血量（用于检测变化）
var previous_health: float = 100.0

# 关联的实体（用于标记绘制等）
var entity: GameEntity = null

func _ready():
	custom_minimum_size = Vector2(60, 10)
	previous_health = current_value
	set_process(true)

func _process(delta):
	if damage_flash_timer > 0:
		damage_flash_timer -= delta
		if damage_flash_timer < 0: damage_flash_timer = 0
	if heal_timer > 0:
		heal_timer -= delta
		if heal_timer < 0: heal_timer = 0
	queue_redraw()

func update_bar(health, max_health, team, shield = 0.0, always_show = false, epic = false):
	# 检测血量变化
	if health < previous_health:
		damage_flash_amount = previous_health - health
		damage_flash_timer = 0.5
		heal_amount = 0.0
		heal_timer = 0.0
	elif health > previous_health:
		heal_amount = health - previous_health
		heal_timer = 0.5
		damage_flash_amount = 0.0
		damage_flash_timer = 0.0
	previous_health = health

	max_value = max_health
	current_value = health

	# 根据队伍设置颜色（敌友相对：友方蓝 / 敌方红）
	match team:
		0, 1: team_color = Color(0.0, 0.886, 1.0, 1.0) if Config.is_ally(int(team)) else Color(1.0, 0.33, 0.264, 1.0)
		2: team_color = Color(0.0, 0.886, 0.431, 1.0)        # 中立（野怪等）
		_: team_color = Color(0.945, 0.925, 0.251, 1.0)      # 默认黄色

	shield_value = shield
	self.always_show = always_show
	epic_mode = epic
	queue_redraw()

func _draw():
	if current_value <= 0 and shield_value <= 0 and not always_show:
		return

	var w = size.x
	var h = size.y

	if epic_mode:
		_draw_epic_bar(w, h)
		if show_shield_icon:
			_draw_shield_icon(-18.0, h * 0.5, minf(h * 0.44, 14.0), Color(1.0, 0.78, 0.3, 0.98))
		_draw_markers(h)
		return

	# 干扰条：防御塔被干扰时，血条上方显示灰色剩余时间条
	if interfere_value > 0:
		var iw = w * clampf(interfere_value, 0.0, 1.0)
		draw_rect(Rect2(0, -7, w, 4), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(0, -7, iw, 4), Color(0.55, 0.55, 0.55))
	var total_width = min((current_value + shield_value) / max_value, 1.0) * w
	var health_width = (current_value / max_value) * w

	# 背景
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.4))

	# 护盾部分（灰白色，位于血量右侧）
	if shield_value > 0:
		var shield_width = min(shield_value / max_value * w, total_width - health_width)
		draw_rect(Rect2(health_width, 0, shield_width, h), Color(0.8, 0.8, 0.8))

	# 血量部分（上下分层）
	draw_rect(Rect2(0, 0, health_width, h / 2), team_color.lightened(0.2))
	draw_rect(Rect2(0, h / 2, health_width, h / 2), team_color.darkened(0.2))

	# 李元芳暗印预判：爆炸前将造成的实际伤害 → 当前血条右端相应段染黄（表示这部分血将被引爆掉）
	if entity and entity.has_method("lyf_mark_summary"):
		var doom_w := _lyf_doom_width(w)
		if doom_w > 0.5:
			draw_rect(Rect2(health_width - doom_w, 0, doom_w, h), Color(1.0, 0.88, 0.18, 0.9))

	# 受伤闪橙
	if damage_flash_timer > 0:
		var ratio = damage_flash_timer / 0.5
		var flash_width = (damage_flash_amount / max_value) * w * ratio
		draw_rect(Rect2(health_width, 0, flash_width, h), Color.ORANGE)

	# 回血深色叠加
	if heal_timer > 0:
		var ratio = heal_timer / 0.5
		var heal_width = (heal_amount / max_value) * w
		var color = Color(team_color.r * 0.6, team_color.g * 0.6, team_color.b * 0.6, ratio)
		draw_rect(Rect2(health_width - heal_width, 0, heal_width, h), color)

	# 边框
	draw_rect(Rect2(Vector2.ZERO, size), Color(team_color.r, team_color.g, team_color.b, 0.5), false, 1.0)

	_draw_markers(h)
	if show_shield_icon:
		# 防御塔盾图标：更大，且用塔所在队伍的颜色（与血条同色）
		var s := minf(h * 0.72, 19.0)
		_draw_shield_icon(-(s + 9.0), h * 0.5, s, team_color)

# ---------- 史诗怪物大号紫色分格血条（每格 = 1000 点生命） ----------
func _draw_epic_bar(w: float, h: float) -> void:
	var seg_count := maxi(1, int(ceil(max_value / EPIC_HP_PER_CELL)))
	var seg_total := float(seg_count) * EPIC_HP_PER_CELL
	var seg_w := w / float(seg_count)
	var to_w := w / seg_total
	var fill_w := clampf(current_value, 0.0, max_value) * to_w
	var sh_w := clampf(shield_value, 0.0, seg_total - current_value) * to_w

	var margin := 1.2
	var inset_y := 2.0
	var avail_h := h - inset_y * 2.0
	var cell_top := Color(0.14, 0.06, 0.24, 0.98)
	var cell_bot := Color(0.075, 0.028, 0.135, 0.98)
	var top_col := Color(0.94, 0.54, 1.0)
	var mid_col := Color(0.68, 0.29, 0.96)
	var bot_col := Color(0.34, 0.08, 0.56)
	draw_rect(Rect2(1, 2, w, h), Color(0, 0, 0, 0.26))
	draw_rect(Rect2(-2, -2, w + 4, h + 4), Color(0.045, 0.015, 0.075, 0.98))

	for i in seg_count:
		var x0: float = i * seg_w
		var x1: float = minf((i + 1.0) * seg_w, w)
		if x1 - x0 <= margin * 2.0:
			continue
		var cell := Rect2(x0 + margin, inset_y, x1 - x0 - margin * 2.0, avail_h)
		draw_rect(cell, cell_top)
		draw_rect(Rect2(cell.position + Vector2(0, cell.size.y * 0.55), Vector2(cell.size.x, cell.size.y * 0.45)), cell_bot)
		draw_rect(Rect2(cell.position + Vector2(0, 1.0), Vector2(cell.size.x, maxf(1.0, cell.size.y * 0.22))), Color(1.0, 0.55, 1.0, 0.035))
		var filled := clampf(fill_w - cell.position.x, 0.0, cell.size.x)
		if filled > 0.0:
			draw_rect(Rect2(cell.position, Vector2(filled, avail_h * 0.34)), top_col)
			draw_rect(Rect2(cell.position + Vector2(0, avail_h * 0.34), Vector2(filled, avail_h * 0.34)), mid_col)
			draw_rect(Rect2(cell.position + Vector2(0, avail_h * 0.68), Vector2(filled, avail_h * 0.32)), bot_col)
			draw_rect(Rect2(cell.position, Vector2(filled, 1.5)), Color(1, 1, 1, 0.42))
		draw_line(cell.position + Vector2(cell.size.x, 0), cell.position + Vector2(cell.size.x, cell.size.y), Color(0, 0, 0, 0.55), 1.6)
		draw_line(cell.position + Vector2(cell.size.x - 1.0, 1.0), cell.position + Vector2(cell.size.x - 1.0, cell.size.y - 1.0), Color(0.72, 0.38, 1.0, 0.22), 1.0)

	if sh_w > 0.0:
		var sh_x := clampf(fill_w, 0.0, w)
		var sh_use := clampf(sh_w, 0.0, w - sh_x)
		if sh_use > 0.0:
			draw_rect(Rect2(sh_x, inset_y, sh_use, avail_h), Color(0.9, 0.9, 0.95, 0.95))
			draw_rect(Rect2(sh_x, inset_y, sh_use, 2.0), Color(1, 1, 1, 0.6))

	if damage_flash_timer > 0.0:
		var ratio := damage_flash_timer / 0.5
		var fw := damage_flash_amount * to_w * ratio
		if fw > 0.0:
			draw_rect(Rect2(fill_w, inset_y, minf(fw, w - fill_w), avail_h), Color(1.0, 0.55, 0.1, 0.9))

	if heal_timer > 0.0:
		var ratio := heal_timer / 0.5
		var hw2 := heal_amount * to_w
		if hw2 > 0.0:
			var col := Color(top_col.r * 0.55, top_col.g * 0.55, top_col.b * 0.55, ratio * 0.6)
			draw_rect(Rect2(maxf(fill_w - hw2, 0.0), inset_y, hw2, avail_h), col)

	var doom := _lyf_doom_amount()
	if doom > 0.0:
		var dw := doom * to_w
		if dw > 0.5:
			draw_rect(Rect2(maxf(fill_w - dw, 0.0), inset_y, dw, avail_h), Color(1.0, 0.88, 0.18, 0.7))

	if fill_w > 0.5 and current_value > 0.0:
		draw_rect(Rect2(fill_w - 1.5, inset_y, 2.0, avail_h), Color(1, 0.95, 1, 0.78))
		draw_rect(Rect2(fill_w - 3.5, inset_y, 5.0, avail_h), Color(0.72, 0.34, 1.0, 0.16))
	draw_rect(Rect2(0, 0, w, h), Color(0.82, 0.56, 1.0, 0.58), false, 1.5)
	draw_line(Vector2(0, 0), Vector2(w, 0), Color(1, 1, 1, 0.26), 1.0)
	draw_line(Vector2(0, h), Vector2(w, h), Color(0.04, 0.01, 0.08, 0.85), 1.0)

# ---------- 李元芳暗印预判：黄色段（当前血条右尾被引爆的部分） ----------
func _lyf_doom_amount() -> float:
	if not (entity and entity.has_method("lyf_mark_summary")):
		return 0.0
	var lsum = entity.lyf_mark_summary()
	if lsum.size() == 0:
		return 0.0
	var pred_total := 0.0
	for lm in lsum:
		pred_total += float(lm["pred"])
	return clampf(pred_total - shield_value, 0.0, current_value)
func _lyf_doom_width(w: float) -> float:
	return (_lyf_doom_amount() / max_value) * w  # 调用侧以显式 : float 声明承接（防 := 推断歧义）

# ---------- 血条下方的英雄标记文字 ----------
func _draw_markers(h: float) -> void:
	if not (entity and (entity.has_method("get_marker_sources") or entity.has_method("lyf_mark_summary"))):
		return
	var font = UiKit.font()
	var marker_strs = []
	if entity.has_method("get_marker_sources"):
		var sources = entity.get_marker_sources()
		for src in sources:
			var count = entity.count_markers(src)
			if count > 0:
				marker_strs.append("%s %d层" % [src.display_name, count])
	if entity.has_method("lyf_mark_summary"):
		for lm in entity.lyf_mark_summary():
			var src = lm["source"]
			var _suff := ("%d层" % int(lm["stacks"])) if int(lm["stacks"]) > 0 else ""
			marker_strs.append("%s·暗印%s" % [src.display_name, _suff])
	if marker_strs.size() == 0:
		return
	var marker_str = " ".join(marker_strs)
	var marker_size = 20
	UiKit.text(self, Vector2(0, h - 25), marker_str, marker_size, Color.YELLOW,
		HORIZONTAL_ALIGNMENT_CENTER, -1.0)

# ---------- 金色盾形小图标 ----------
func _draw_shield_icon(cx: float, cy: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-0.55 * s, -0.85 * s))
	pts.append(Vector2(0.55 * s, -0.85 * s))
	pts.append(Vector2(0.62 * s, 0.0))
	pts.append(Vector2(0.3 * s, 0.68 * s))
	pts.append(Vector2(0.0, 1.0 * s))
	pts.append(Vector2(-0.3 * s, 0.68 * s))
	pts.append(Vector2(-0.62 * s, 0.0))
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(p + Vector2(cx, cy))
	draw_colored_polygon(poly, col)
	var outline := poly.duplicate()
	outline.append(poly[0])
	draw_polyline(outline, Color(0.12, 0.03, 0.05, 0.85), 1.5)
	draw_line(Vector2(cx - 0.5 * s, cy - 0.05 * s), Vector2(cx + 0.5 * s, cy - 0.05 * s),
				Color(1.0, 1.0, 1.0, 0.55), maxf(s * 0.16, 1.0))
