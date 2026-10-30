extends Node
## Vfx — 统一法术/命中视觉工厂（autoload，双端共用）。
## 所有技能、普攻、受击、护盾的粒子/拖尾/冲击环/光束/闪光都从这里生成：
##   1) 风格统一：按元素取色（火/冰/水/雷/暗影/圣光/刀刃/风/大地/奥术）；
##   2) 可降级：quality 0=全关、1=低、2=中、3=高；并发超预算时低优先级特效自动丢弃；
##   3) 双端一致：host/client 本地各自生成，同一份元素与参数；判定仍在 host。
## P0：粒子/拖尾/冲击环/光束/闪光/命中火花/屏幕反馈入口；P1 起接 SpellFxTable 逐技能参数。

const MAX_ACTIVE := 32          # 并发粒子系统上限（移动端预算；命中火花多，优先保手感）
const MAX_TRAILS := 18          # 并发拖尾上限（连射技能多，单独计数，不挤占爆发特效预算）
const MAX_LIGHTS := 2           # 同时存在的临时点光上限
const GROUP_FX := "vfx_fx"
const GROUP_TRAIL := "vfx_trail"
const GROUP_LIGHT := "vfx_light"
const GROUP_PROP := "vfx_prop"
const GROUP_STEP := "vfx_step"   # 脚步扬尘独立预算（技能特效打满时仍能出脚感）
const MAX_STEPS := 10
const MAX_PROPS := 8             # 实体道具独立预算，不挤占爆发特效
const PROP_RANGE := 30.0         # 距本地英雄超过该距离不生成（离屏 AI 技能省预算）

var quality: int = 2            # 0 关 / 1 低 / 2 中 / 3 高（P3 接设置开关）

# 李元芳·暗印飞镖环绕（Q）：target_id -> {target, root, darts[], ring, angle, life, color}
var _lyf_orbits: Dictionary = {}
const LYF_DART_COL := Color(1.0, 0.52, 0.16)
const LYF_DART_COL2 := Color(1.0, 0.88, 0.55)

# 元素配色与手感参数：c=主色 c2=亮色 light=临时光色 size=粒子尺寸 gravity=重力
var ELEMENTS := {
	"fire":      {"c": Color(1.0, 0.42, 0.10), "c2": Color(1.0, 0.86, 0.35), "light": Color(1.0, 0.55, 0.20), "size": 0.75, "gravity": 4.0, "speed": 7.0},
	"ice":       {"c": Color(0.45, 0.82, 1.0), "c2": Color(0.86, 0.97, 1.0), "light": Color(0.55, 0.85, 1.0), "size": 0.60, "gravity": 7.0, "speed": 6.0},
	"water":     {"c": Color(0.18, 0.52, 0.98), "c2": Color(0.55, 0.85, 1.0), "light": Color(0.30, 0.65, 1.0), "size": 0.70, "gravity": 9.0, "speed": 6.5},
	"lightning": {"c": Color(0.66, 0.55, 1.0), "c2": Color(0.95, 0.92, 1.0), "light": Color(0.75, 0.65, 1.0), "size": 0.45, "gravity": 0.0, "speed": 12.0},
	"shadow":    {"c": Color(0.48, 0.18, 0.72), "c2": Color(0.80, 0.45, 1.0), "light": Color(0.55, 0.25, 0.85), "size": 0.85, "gravity": -1.5, "speed": 4.0},
	"holy":      {"c": Color(1.0, 0.80, 0.30), "c2": Color(1.0, 0.96, 0.75), "light": Color(1.0, 0.85, 0.45), "size": 0.65, "gravity": -2.0, "speed": 5.0},
	"blade":     {"c": Color(0.82, 0.90, 1.0), "c2": Color(1.0, 1.0, 1.0), "light": Color(0.75, 0.86, 1.0), "size": 0.45, "gravity": 2.0, "speed": 10.0},
	"wind":      {"c": Color(1.0, 0.55, 0.75), "c2": Color(1.0, 0.85, 0.92), "light": Color(1.0, 0.65, 0.85), "size": 0.70, "gravity": 0.5, "speed": 6.0},
	"earth":     {"c": Color(0.78, 0.58, 0.32), "c2": Color(0.95, 0.82, 0.55), "light": Color(0.85, 0.68, 0.40), "size": 0.90, "gravity": 6.0, "speed": 5.0},
	"arcane":    {"c": Color(0.55, 0.75, 1.0), "c2": Color(0.90, 0.97, 1.0), "light": Color(0.60, 0.80, 1.0), "size": 0.55, "gravity": 0.0, "speed": 8.0},
}

# 英雄 → 元素（P0 先给默认映射，P1 起由 SpellFxTable 按技能细分）
const HERO_ELEMENT := {
	"狄仁杰": "blade", "马可波罗": "fire", "孙尚香": "fire", "马超": "blade",
	"鲁班七号": "fire", "后羿": "fire", "李元芳": "shadow", "元流之子": "water",
	"安琪拉": "fire", "妲己": "shadow", "小乔": "wind", "甄姬": "water",
	"沈梦溪": "fire", "不知火舞": "fire", "王昭君": "ice", "太乙真人": "holy",
	"东皇太一": "shadow", "张飞": "earth", "吕布": "shadow", "铠": "shadow",
	"亚瑟": "holy", "夏侯惇": "blade", "刘禅": "fire", "大禹": "earth",
	"孙悟空": "holy", "英睿": "holy", "李白": "blade", "兰陵王": "shadow",
}

var _soft_tex: Texture2D
var _spark_tex: Texture2D
var _particle_quad_soft: QuadMesh
var _particle_quad_spark: QuadMesh
var _particle_ramp_tex: GradientTexture1D
var _crescent_mesh_cache: Dictionary = {}
var _beam_shader: Shader
var _glow_shader: Shader
var _last_shake_msec: int = 0

const SPELL_FX = preload("res://scripts/core/SpellFxTable.gd")

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_soft_tex = _make_radial_texture(64, 0.42)
	_spark_tex = _make_radial_texture(32, 0.18)
	_beam_shader = load("res://shaders/fx_beam.gdshader")
	_glow_shader = load("res://shaders/fx_glow.gdshader")

# ---------------- 查询 ----------------
func element_of(hero_name: String) -> String:
	return HERO_ELEMENT.get(hero_name, "arcane")

func element_data(el: String) -> Dictionary:
	return ELEMENTS.get(el, ELEMENTS["arcane"])

func color_for_hero(hero_name: String) -> Color:
	return element_data(element_of(hero_name))["c"]

func color2_for_hero(hero_name: String) -> Color:
	return element_data(element_of(hero_name))["c2"]

func team_color(team: int) -> Color:
	return Color(1.0, 0.36, 0.28) if team == 1 else Color(0.0, 0.886, 1.0)

# ---------------- 生成入口 ----------------
# 技能/普攻出手爆发：在施法者手口位置炸出一簇元素粒子 + 地面小型冲击环 + 瞬时点光
func cast_burst(hero_name: String, pos: Vector3, dir: Vector3 = Vector3.ZERO, scale_f: float = 1.0) -> void:
	var el := element_data(element_of(hero_name))
	var d := dir if dir.length() > 0.01 else Vector3.UP
	_burst(el["c"], el["c2"], pos, int(14.0 * scale_f), 0.55, el["size"] * scale_f, el["speed"], d, 55.0, el["gravity"])
	_ring(Vector3(pos.x, 0.15, pos.z), 0.9 * scale_f, el["c"], 0.30, scale_f)
	_light(pos, el["light"], 2.2 * scale_f, 0.14)

## 命中火花：任何子弹/技能命中的统一反馈（P0 全技能生效）
func hit_spark(pos: Vector3, color: Color, dir: Vector3 = Vector3.UP, scale_f: float = 1.0) -> void:
	if quality <= 0 or _near_limit(1):
		return
	_burst(color, Color(1, 1, 1), pos, int(7.0 * scale_f), 0.30, 0.32 * scale_f, 6.5, dir, 70.0, 9.0, true)

## 分层命中反馈：受击方 kind = hero/minion/tower/crystal/monster；
## 进攻方 kind = hero/minion/siege/turret/monster。小兵/塔的普攻也走这里。
func hit_impact(pos: Vector3, dir: Vector3, c1: Color, c2: Color, scale_f: float = 1.0,
		target_kind: String = "hero", source_kind: String = "hero", crit: bool = false) -> void:
	if quality <= 0 or get_tree() == null:
		return
	var near := _near_local(pos, 30.0)
	# 只做本地玩家视野内的命中特效（远处对射看不到，省移动端粒子预算）
	if not near:
		return
	if _near_limit(1):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var sf := maxf(0.45, scale_f)
	# 小兵互殴：只出一个小火花，避免吃满并发预算
	if source_kind in ["minion", "siege"] and target_kind == "minion":
		_burst(c1, c2, pos, 3, 0.24, 0.24 * sf, 4.0, d, 60.0, 8.0, true)
		return
	# 塔/炮车打小兵：单发能量着弹 + 近场小环（别再叠受击方尘土，控制节点数）
	if source_kind in ["turret", "siege"] and target_kind == "minion":
		_burst(c1, c2, pos, int(5.0 * sf), 0.28, 0.28 * sf, 6.0, d, 65.0, 6.0, true)
		if near:
			_ring(Vector3(pos.x, 0.10, pos.z), 1.1 * sf, c1, 0.24, 1.5)
		return
	# 小兵/炮车拆塔：只要金属火花，别叠闪光/环（拆塔时攻击频率最高）
	if source_kind in ["minion", "siege"] and target_kind in ["tower", "crystal"]:
		_burst(c1, Color(1.0, 0.96, 0.86), pos, int(4.0 * sf), 0.26, 0.26 * sf, 5.5, d, 65.0, 9.0, true)
		return
	match target_kind:
		"tower", "crystal":
			# 金属着弹：高抛白热火花 + 短促闪光 + 微型环
			_burst(c1, Color(1.0, 0.98, 0.9), pos, int(9.0 * sf), 0.32, 0.30 * sf, 7.5, d, 65.0, 10.0, true)
			_impact_flash(pos, c2, 0.42 * sf, 0.12)
			_ring(Vector3(pos.x, maxf(0.05, pos.y - 0.7), pos.z), 0.9 * sf, c1, 0.22, 1.5)
			if near:
				_light(pos, c1, 1.6 * sf, 0.10)
		"minion":
			# 血肉/纸甲：小火花 + 尘土
			_burst(c1, Color(0.85, 0.8, 0.68), pos, int(4.0 * sf), 0.26, 0.26 * sf, 4.6, d, 60.0, 8.0, true)
			_burst(Color(0.55, 0.5, 0.4), Color(0.72, 0.66, 0.55), pos, 2, 0.34, 0.30 * sf, 1.2, Vector3.UP, 40.0, -1.0)
		"monster":
			_burst(c1, c2, pos, int(5.0 * sf), 0.28, 0.30 * sf, 5.5, d, 60.0, 9.0, true)
			_burst(Color(0.42, 0.35, 0.24), Color(0.55, 0.48, 0.34), pos, 2, 0.36, 0.32 * sf, 1.4, Vector3.UP, 45.0, -0.8)
		_:
			# 英雄：元素火花 + 白色着弹闪光（暴击加量）
			_burst(c1, c2, pos, int((7.5 if crit else 5.5) * sf), 0.28, 0.28 * sf, 6.8, d, 70.0, 8.0, true)
			_impact_flash(pos, c2, 0.28 * sf, 0.10)
	# 进攻方特征加码
	match source_kind:
		"turret":
			# 塔的激光弹：能量炸裂 + 地面能量环
			_burst(c1, Color(1, 1, 1), pos, int(7.0 * sf), 0.40, 0.26 * sf, 9.0, Vector3.UP, 78.0, 6.0, true)
			_ring(Vector3(pos.x, 0.10, pos.z), 1.6 * sf, c1, 0.28, 1.8)
			if near:
				_light(pos, c1, 2.2, 0.12)
		"siege":
			# 攻城车/龙兵炮弹：小冲击环 + 碎屑
			_ring(Vector3(pos.x, 0.10, pos.z), 1.15 * sf, c1, 0.25, 1.6)
			_burst(c1, Color(0.9, 0.86, 0.72), pos, 3, 0.30, 0.30 * sf, 3.5, Vector3.UP, 55.0, 4.0, true)
		"monster":
			_burst(c1, Color(0.95, 0.85, 0.6), pos, 3, 0.30, 0.32 * sf, 4.5, d, 60.0, 7.0, true)
		_:
			if crit:
				_burst(Color(1.0, 0.95, 0.7), Color(1, 1, 1), pos, 6, 0.26, 0.34 * sf, 8.0, d, 80.0, 7.0, true)

## 短促白热着弹闪光（ADD 球，快速放大淡出）
func _impact_flash(pos: Vector3, color: Color, size: float, dur: float) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 1.8
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.95)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.add_to_group(GROUP_FX)
	_add_root(mi)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.9, 1.9, 1.9), dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)

## 是否在本地玩家附近（命中特效预算：小兵/塔对射只做近场）
func _near_local(pos: Vector3, max_dist: float) -> bool:
	if get_tree() == null:
		return false
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm == null or bm.hero == null or not is_instance_valid(bm.hero):
		return true
	if bm.hero.health <= 0:
		return true
	return pos.distance_to(bm.hero.global_position) <= max_dist

## 枪口闪光（普攻出手；限英雄 + 近距 + quality≥2，避免小兵对射吃满预算）
func muzzle(pos: Vector3, dir: Vector3, color: Color, color2: Color) -> void:
	if quality < 2 or _near_limit(1):
		return
	var bm := get_tree().get_first_node_in_group("battle_manager") if get_tree() != null else null
	if bm != null and bm.hero != null and pos.distance_to(bm.hero.global_position) > 22.0:
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	_burst(color, color2, pos + d * 0.35, 4, 0.10, 0.24, 5.0, d, 35.0, 0.0, false)

## 脚步/停步扬尘（独立预算 GROUP_STEP，最多 14 个；限近距 + quality≥2）
func footstep(pos: Vector3, color: Color = Color(0.70, 0.64, 0.54), size: float = 0.22, strength: float = 1.0) -> void:
	if quality < 2 or get_tree() == null:
		return
	if get_tree().get_nodes_in_group(GROUP_STEP).size() >= MAX_STEPS:
		return
	var bm := get_tree().get_first_node_in_group("battle_manager")
	if bm != null and bm.hero != null and pos.distance_to(bm.hero.global_position) > 18.0:
		return
	var amt := int(2.0 + 2.0 * strength)
	var p := _particles(amt, 0.26, color, size * (0.7 + 0.35 * strength), 1.2, 0.9, Vector3.UP, 0.25, true, _soft_tex)
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.add_to_group(GROUP_STEP)
	_add_root(p)
	var tw := p.create_tween()
	tw.tween_interval(0.38)
	tw.tween_callback(p.queue_free)

## 施法者身上/脚下的蓄力光（持续类技能用）
func cast_glow(pos: Vector3, color: Color, radius: float = 1.0, dur: float = 0.5) -> void:
	if quality <= 0 or _near_limit(0):
		return
	_ring(pos, radius, color, dur, 1.0, 0.35)
	_burst(color, Color(1, 1, 1), pos + Vector3.UP * 0.4, 8, dur, 0.40, 2.2, Vector3.UP, 25.0, -2.0, true)

## 施法前摇蓄力（替代"只有一个圈"）：地面三旋法阵 + 内吸能量 + 上升光尘
## + 手中聚能球 + 中段旋环 + 元素点缀 + 朝向能量线。slot≥2（大招）整体放大加长。
func cast_charge(hero_name: String, pos: Vector3, facing: Vector3 = Vector3.ZERO,
		target_pos: Vector3 = Vector3.ZERO, slot: int = 0, duration: float = 0.0) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var el_name: String = element_of(hero_name)
	var el: Dictionary = element_data(el_name)
	var col: Color = el["c"]
	var col2: Color = el["c2"]
	var big: bool = slot >= 2
	var sf: float = 1.35 if big else 1.0
	# duration>0：按真实前摇对齐（Hero 传 maxf(windup, 0.24/0.40)）；否则沿用旧档位
	var dur: float = duration if duration > 0.0 else (0.40 if big else 0.28)
	var base := Vector3(pos.x, 0.05, pos.z)
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.position = base
	_add_root(root)
	# 1) 地面软光斑法阵
	var disc := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.6, 4.6) * sf
	disc.mesh = plane
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dmat := ShaderMaterial.new()
	dmat.shader = _glow_shader
	dmat.set_shader_parameter("glow_color", col)
	dmat.set_shader_parameter("intensity", 1.35)
	dmat.set_shader_parameter("softness", 0.58)
	dmat.set_shader_parameter("ring_width", 0.10)
	dmat.set_shader_parameter("pulse_speed", 8.0)
	disc.material_override = dmat
	root.add_child(disc)
	# 2) 三圈反向旋转法阵
	var rings: Array[MeshInstance3D] = []
	var mats: Array[StandardMaterial3D] = []
	var radii: Array[float] = [1.62, 1.16, 0.72]
	for i in range(3):
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var rr: float = radii[i] * sf
		torus.inner_radius = rr * 0.90
		torus.outer_radius = rr
		torus.rings = 24
		torus.ring_segments = 8
		mi.mesh = torus
		mi.position = Vector3(0, 0.02 + 0.012 * float(i), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(col.r, col.g, col.b, 0.85 if i == 0 else 0.55)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.4
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		root.add_child(mi)
		rings.append(mi)
		mats.append(mat)
	# 3) 内吸能量粒子（环形发射 + 负径向加速度 → 汇向脚下）
	var p_in := _charge_particles(16, dur, col2, 0.16, sf)
	p_in.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p_in.emission_ring_axis = Vector3.UP
	p_in.emission_ring_radius = 1.9 * sf
	p_in.emission_ring_inner_radius = 1.15 * sf
	p_in.emission_ring_height = 0.12
	p_in.radial_accel_min = -8.0
	p_in.radial_accel_max = -4.0
	p_in.initial_velocity_min = 0.0
	p_in.initial_velocity_max = 0.35
	p_in.gravity = Vector3(0, 0.9, 0)
	p_in.position = Vector3(0, 0.25, 0)
	root.add_child(p_in)
	p_in.emitting = true
	# 4) 上升光尘
	var p_up := _charge_particles(10, dur * 1.15, col2, 0.11, sf)
	p_up.emission_sphere_radius = 0.55 * sf
	p_up.direction = Vector3.UP
	p_up.spread = 22.0
	p_up.initial_velocity_min = 1.1
	p_up.initial_velocity_max = 2.4
	p_up.gravity = Vector3(0, 1.2, 0)
	p_up.position = Vector3(0, 0.3, 0)
	root.add_child(p_up)
	p_up.emitting = true
	# 5) 手中聚能球（由小到大 + 上浮）
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.19 * sf
	sph.height = 0.38 * sf
	sph.radial_segments = 12
	sph.rings = 6
	orb.mesh = sph
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var omat := _add_mat(col2, 0.90, 3.0)
	orb.material_override = omat
	orb.position = Vector3(0, 1.15, 0)
	orb.scale = Vector3(0.35, 0.35, 0.35)
	root.add_child(orb)
	# 6) 中段能量旋环（微倾，读出"能量上涌"）
	var swirl := MeshInstance3D.new()
	var tsw := TorusMesh.new()
	tsw.inner_radius = 0.50 * sf
	tsw.outer_radius = 0.60 * sf
	tsw.rings = 20
	tsw.ring_segments = 8
	swirl.mesh = tsw
	swirl.position = Vector3(0, 0.85, 0)
	swirl.rotation = Vector3(0.32, 0.0, 0.0)
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := _add_mat(col, 0.55, 1.8)
	swirl.material_override = smat
	root.add_child(swirl)
	# 7) 元素点缀
	_element_flourish(el_name, col, col2, base, facing, sf, dur, root)
	# 8) 朝向能量线（有朝向时：地面一道指向施法方向的能量束）
	if facing.length() > 0.01:
		var fdir := facing.normalized()
		var streak := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.045 * sf
		cyl.bottom_radius = 0.075 * sf
		cyl.height = 3.2 * sf
		cyl.radial_segments = 6
		cyl.rings = 1
		streak.mesh = cyl
		streak.position = Vector3(fdir.x * 1.7 * sf, 0.10, fdir.z * 1.7 * sf)
		streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var axis := Vector3.UP.cross(fdir)
		if axis.length() > 0.001:
			streak.rotate(axis.normalized(), Vector3.UP.angle_to(fdir))
		else:
			streak.rotate(Vector3.RIGHT, PI * 0.5)
		var tmat := _add_mat(col2, 0.45, 2.2)
		streak.material_override = tmat
		root.add_child(streak)
		var tw2 := root.create_tween()
		tw2.tween_property(tmat, "albedo_color:a", 0.0, dur * 0.7).set_ease(Tween.EASE_OUT)
	# 9) 临时点光
	_light(pos + Vector3.UP * 1.1, el["light"], 2.6 * sf, dur * 0.9)
	# 10) 动画：环反向旋转、光球长成、整体渐熄
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rings[0], "rotation:y", TAU * 1.1, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(rings[1], "rotation:y", -TAU * 0.9, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(rings[2], "rotation:y", TAU * 1.5, dur).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(swirl, "rotation:y", -TAU * 1.6, dur)
	tw.tween_property(orb, "scale", Vector3(1.45, 1.45, 1.45) * sf, dur * 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(orb, "position:y", 1.32, dur)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.tween_property(smat, "albedo_color:a", 0.0, dur)
	tw.tween_property(omat, "albedo_color:a", 0.0, dur * 1.03)
	tw.tween_property(dmat, "shader_parameter/intensity", 0.0, dur)
	tw.chain().tween_callback(root.queue_free)

## 前摇 / 落点预警法阵（原来"只有一个圈"的升级版）：
## 软光斑 + 内外反向双环 + 向心汇聚粒子 + 竖直微光柱，末段炸开一圈
func telegraph(pos: Vector3, radius: float, color: Color, dur: float = 0.65) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var base := Vector3(pos.x, 0.06, pos.z)
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.position = base
	_add_root(root)
	sigil(base, color, radius, dur)
	# 外框 + 内框反向旋转环（比 sigil 的双环更"机关"）
	var rings: Array[MeshInstance3D] = []
	var mats: Array[StandardMaterial3D] = []
	for i in range(2):
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var rr: float = radius * (1.0 if i == 0 else 0.66)
		torus.inner_radius = rr * 0.94
		torus.outer_radius = rr
		torus.rings = 24
		torus.ring_segments = 8
		mi.mesh = torus
		mi.position = Vector3(0, 0.05 + 0.02 * float(i), 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _add_mat(color, 0.8 if i == 0 else 0.5, 2.6)
		mi.material_override = mat
		root.add_child(mi)
		rings.append(mi)
		mats.append(mat)
	# 向心汇聚粒子（读作"正在充能"）
	var p_in := _charge_particles(12, dur * 0.9, color, 0.16, 1.0)
	p_in.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p_in.emission_ring_axis = Vector3.UP
	p_in.emission_ring_radius = radius
	p_in.emission_ring_inner_radius = radius * 0.65
	p_in.emission_ring_height = 0.1
	p_in.radial_accel_min = -6.5
	p_in.radial_accel_max = -3.0
	p_in.initial_velocity_min = 0.0
	p_in.initial_velocity_max = 0.3
	p_in.gravity = Vector3(0, 0.5, 0)
	p_in.position = Vector3(0, 0.25, 0)
	root.add_child(p_in)
	p_in.emitting = true
	# 落点竖直微光柱
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.30
	cyl.bottom_radius = radius * 0.55
	cyl.height = 3.2
	cyl.radial_segments = 10
	cyl.cap_top = false
	cyl.cap_bottom = false
	shaft.mesh = cyl
	shaft.position = Vector3(0, 1.6, 0)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := _add_mat(color, 0.16, 1.5)
	shaft.material_override = smat
	root.add_child(shaft)
	_light(base + Vector3.UP * 1.0, color, 2.4, dur * 0.8)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rings[0], "rotation:y", TAU * 0.9, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(rings[1], "rotation:y", -TAU * 1.4, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(shaft, "scale", Vector3(1.0, 1.25, 1.0), dur)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.tween_property(smat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(root.queue_free)
	# 末段炸开
	_delayed_ring(base, radius, color, dur * 0.85, 0.45)
	_delayed_ring(base, radius * 0.6, color.lerp(Color.WHITE, 0.3), dur * 0.95, 0.35)

## 加色发光材质（前摇特效专用，免去每处重复写 StandardMaterial3D）
func _add_mat(color: Color, alpha: float, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = emission
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## 前摇粒子（软光斑 billboard 四边形 + 加色混合）
func _charge_particles(amount: int, lifetime: float, color: Color, size: float, sf: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = maxi(6, int(float(amount) * (1.0 if quality >= 2 else 0.6)))
	p.lifetime = maxf(0.12, lifetime)
	p.one_shot = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	var q := QuadMesh.new()
	q.size = Vector2(size, size) * (2.7 if sf > 1.0 else 2.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _soft_tex
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	p.color = Color(color.r, color.g, color.b, 0.9)
	p.color_ramp = null
	p.scale_amount_min = 0.55
	p.scale_amount_max = 1.0
	return p

## 前摇的元素差异点缀：火=上升火星/冰=冰晶碎片/雷=侧向电弧/圣=竖直光带/
## 刃=交叉刃光/暗=暗雾/水=水珠/其余=扩散气环
func _element_flourish(el_name: String, col: Color, col2: Color, base: Vector3,
		facing: Vector3, sf: float, dur: float, root: Node3D) -> void:
	match el_name:
		"fire":
			_burst(col, col2, base + Vector3.UP * 0.5, 12, dur * 0.95, 0.55 * sf, 4.2, Vector3.UP, 24.0, 3.0)
		"ice":
			for i in range(5):
				var sh := MeshInstance3D.new()
				var qm := QuadMesh.new()
				qm.size = Vector2(0.16, 0.46) * sf
				sh.mesh = qm
				sh.material_override = _add_mat(col2, 0.75, 2.0)
				var ang: float = TAU * float(i) / 5.0
				sh.position = Vector3(cos(ang) * 1.15 * sf, 0.55, sin(ang) * 1.15 * sf)
				sh.rotation = Vector3(0.6, ang, 0.35)
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(sh)
				var tw := root.create_tween()
				tw.set_parallel(true)
				tw.tween_property(sh, "position:y", 2.1 * sf, dur * 0.95).set_ease(Tween.EASE_OUT)
				tw.tween_property(sh, "rotation:y", sh.rotation.y + 3.0, dur * 0.95)
		"lightning":
			for i in range(2):
				var a := TAU * float(i) / 2.0 + 0.4
				var from := base + Vector3(cos(a) * 1.5 * sf, 0.25, sin(a) * 1.5 * sf)
				beam(from, base + Vector3.UP * 1.15, col2, 0.055, dur * 0.45)
		"holy":
			var band := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.30 * sf
			cyl.bottom_radius = 0.55 * sf
			cyl.height = 3.6
			cyl.radial_segments = 12
			cyl.cap_top = false
			cyl.cap_bottom = false
			band.mesh = cyl
			band.position = Vector3(0, 1.8, 0)
			band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			band.material_override = _add_mat(col2, 0.22, 1.6)
			root.add_child(band)
		"blade":
			for i in range(2):
				var bl := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.05, 1.5, 0.05) * sf
				bl.mesh = box
				bl.material_override = _add_mat(col2, 0.7, 2.4)
				bl.position = Vector3(0, 1.0, 0)
				bl.rotation = Vector3(0.0, 0.6 + PI * float(i) * 0.5, 0.5 if i == 0 else -0.5)
				bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(bl)
				var tw2 := root.create_tween()
				tw2.set_parallel(true)
				tw2.tween_property(bl, "rotation:y", bl.rotation.y + TAU * 0.8, dur)
				tw2.tween_property(bl, "position:y", 1.9, dur * 0.9)
		"shadow":
			var mist := _charge_particles(14, dur * 1.2, col, 0.34, sf)
			mist.emission_sphere_radius = 1.25 * sf
			mist.direction = Vector3.UP
			mist.spread = 55.0
			mist.initial_velocity_min = 0.5
			mist.initial_velocity_max = 1.3
			mist.gravity = Vector3(0, 0.6, 0)
			mist.position = Vector3(0, 0.45, 0)
			root.add_child(mist)
			mist.emitting = true
		"water":
			_burst(col, col2, base + Vector3.UP * 0.4, 10, dur * 0.9, 0.5 * sf, 3.4, Vector3.UP, 30.0, 1.6)
		_:
			_delayed_ring(base, 2.2 * sf, col, 0.04, dur * 0.85)

## 扩散冲击环（技能落点/爆炸用）
func shockwave(pos: Vector3, radius: float, color: Color, dur: float = 0.45) -> void:
	if quality <= 0:
		return
	_ring(pos, radius, color, dur, 1.0, 0.55)
	_ring(pos, radius * 0.62, color.lerp(Color.WHITE, 0.35), dur * 0.75, 1.0, 0.3)
	_light(pos + Vector3.UP * 1.0, color, 3.0, 0.18)

## 光束（引导类技能：安琪拉R、后羿R弹道等）
# ---------- 持续锁定光束（防御塔用：细光束一直连到当前目标） ----------

func make_beam_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 6
	cm.rings = 1
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 1.5
	return mi

# 锁定光束（三层：亮芯 + 外辉光 + 命中亮点）——防御塔常驻锁定用，细线更清楚
func make_lock_beam(color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "LockBeam"
	var core := make_beam_mesh()
	core.name = "Core"
	core.material_override.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	core.material_override.albedo_color = Color(minf(color.r * 1.35 + 0.35, 1.0), minf(color.g * 1.35 + 0.35, 1.0), minf(color.b * 1.35 + 0.35, 1.0), 1.0)
	root.add_child(core)
	var glow := make_beam_mesh()
	glow.name = "Glow"
	glow.material_override.albedo_color = Color(color.r, color.g, color.b, 0.24)
	root.add_child(glow)
	var tip := MeshInstance3D.new()
	tip.name = "Tip"
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	tip.mesh = sm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.albedo_color = Color(color.r, color.g, color.b, 0.5)
	tip.material_override = tm
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tip)
	return root


func aim_lock_beam(root: Node3D, a: Vector3, b: Vector3, t: float) -> void:
	if root == null or not is_instance_valid(root):
		return
	var d: Vector3 = b - a
	var ln: float = d.length()
	if ln < 0.02:
		root.visible = false
		return
	root.visible = true
	var dir: Vector3 = d / ln
	var bz := Basis(Quaternion(Vector3.UP, dir))
	var mid: Vector3 = (a + b) * 0.5
	var pulse: float = 0.88 + 0.12 * sin(t * 7.5)
	var core: MeshInstance3D = root.get_node_or_null("Core")
	if core != null:
		core.global_transform = Transform3D(bz * Basis.from_scale(Vector3(0.026 * pulse, ln, 0.026 * pulse)), mid)
	var glow: MeshInstance3D = root.get_node_or_null("Glow")
	if glow != null:
		glow.global_transform = Transform3D(bz * Basis.from_scale(Vector3(0.078 * pulse, ln, 0.078 * pulse)), mid)
	var tip: MeshInstance3D = root.get_node_or_null("Tip")
	if tip != null:
		tip.global_position = b
		tip.scale = Vector3.ONE * (0.85 + 0.25 * sin(t * 11.0))

func aim_beam(mi: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var d: Vector3 = b - a
	var ln: float = d.length()
	if ln < 0.02:
		mi.visible = false
		return
	mi.visible = true
	var bz := Basis(Quaternion(Vector3.UP, d / ln)) * Basis.from_scale(Vector3(radius, ln, radius))
	mi.global_transform = Transform3D(bz, (a + b) * 0.5)

func beam(from: Vector3, to: Vector3, color: Color, width: float = 0.3, dur: float = 0.35) -> void:
	if quality <= 0 or _near_limit(2):
		return
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	_add_root(root)
	var dist := from.distance_to(to)
	if dist < 0.05:
		root.queue_free()
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = width
	cyl.bottom_radius = width * 1.25
	cyl.height = dist
	cyl.radial_segments = 8
	cyl.rings = 1
	mi.mesh = cyl
	mi.position = (from + to) * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := (to - from).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.001:
		mi.rotate(axis.normalized(), Vector3.UP.angle_to(dir))
	var mat := ShaderMaterial.new()
	mat.shader = _beam_shader
	mat.set_shader_parameter("beam_color", color)
	mat.set_shader_parameter("intensity", 2.4)
	mi.material_override = mat
	root.add_child(mi)
	var tw := root.create_tween()
	tw.tween_property(mat, "shader_parameter/intensity", 0.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)

## 拖尾：挂在子弹/英雄节点上，随节点移动留下粒子（local_coords=false）
func attach_trail(node: Node3D, color: Color, size: float = 0.22, lifetime: float = 0.32, amount: int = 8, color2: Color = Color(0, 0, 0, 0)):
	if quality <= 0 or node == null or not is_instance_valid(node):
		return null
	if get_tree() == null or get_tree().get_nodes_in_group(GROUP_TRAIL).size() >= MAX_TRAILS:
		return null
	# 拖尾只保留最低可读密度：新特效常叠两层拖尾，默认质量下统一压到 8 粒子
	amount = mini(amount, 10 if quality >= 3 else 8)
	var p := _particles(amount, lifetime, color, size, 1.0, 0.6, Vector3.ZERO, 0.05, false)
	# 双色流光：main → 亮色 → 透明（普攻弹道用；不传 color2 时保持原单色行为）
	if color2.a > 0.0:
		var pm := p.process_material as ParticleProcessMaterial
		if pm != null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
			g.colors = PackedColorArray([color, Color(color2.r, color2.g, color2.b, 0.6), Color(color.r, color.g, color.b, 0.0)])
			var gt := GradientTexture1D.new()
			gt.gradient = g
			pm.color = Color.WHITE
			pm.color_ramp = gt
	p.name = "VfxTrail"
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.remove_from_group(GROUP_FX)
	p.add_to_group(GROUP_TRAIL)
	node.add_child(p)
	p.emitting = true
	return p

## 瞬时点光（受 MAX_LIGHTS 限制，移动端友好）
func _light(pos: Vector3, color: Color, energy: float, dur: float) -> void:
	if quality <= 0 or get_tree() == null:
		return
	if get_tree().get_nodes_in_group(GROUP_LIGHT).size() >= MAX_LIGHTS:
		return
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 6.5
	light.shadow_enabled = false
	light.position = pos
	light.add_to_group(GROUP_LIGHT)
	_add_root(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, dur)
	tw.tween_callback(light.queue_free)

# ---------------- 屏幕/镜头反馈（转发给 BattleManager / UI_Manager） ----------------
func camera_shake(amp: float = 0.12, dur: float = 0.22) -> void:
	var bm = _bm()
	if bm and bm.has_method("camera_shake"):
		bm.camera_shake(amp, dur)

func camera_punch(amount: float = 2.5, dur: float = 0.35) -> void:
	var bm = _bm()
	if bm and bm.has_method("fov_punch"):
		bm.fov_punch(amount, dur)

func hitstop(dur: float = 0.035) -> void:
	var bm = _bm()
	if bm and bm.has_method("hitstop"):
		bm.hitstop(dur)

func screen_flash(color: Color, dur: float = 0.18) -> void:
	if get_tree() == null:
		return
	var ui = get_tree().get_first_node_in_group("ui")
	if ui and ui.has_method("flash_screen"):
		ui.flash_screen(color, dur)

# ---------------- P1 逐技能签名表现 ----------------
## 技能出手统一入口：签名大招走 SpellFxTable，其余走通用元素爆发。
## slot: 0/1/2（对应 1/2/3 技能）；caster_pos 为手口位置（只用 x/z 定位地面法阵）。
func play_spell(hero_name: String, slot: int, caster_pos: Vector3, target_pos: Vector3,
		skill, facing: Vector3, _is_local: bool) -> void:
	if quality <= 0 or get_tree() == null:
		return
	if slot != 2 or not SPELL_FX.has_ult(hero_name):
		# P2：非签名技能按「技能类型 + 元素」自动分档，50+ 技能无需逐个手写
		var s_el: Dictionary = element_data(element_of(hero_name))
		var s_col: Color = s_el["c"]
		var s_col2: Color = s_el["c2"]
		var scp := Vector3(caster_pos.x, 0.08, caster_pos.z)
		var sgy := Vector3(target_pos.x, 0.08, target_pos.z)
		var sfdir: Vector3 = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
		_burst(s_col, s_col2, caster_pos, 10 if slot < 2 else 14, 0.5, s_el["size"], s_el["speed"], sfdir, 55.0, s_el["gravity"])
		var shape := SPELL_FX.get_skill_shape(skill)
		match shape:
			"zone":
				var zr := clampf(float(skill.radius) if skill != null else 2.5, 1.4, 6.5)
				telegraph(sgy, zr, s_col, 0.60)
				# 长引导区域技能：脚下持续蓄力光，避免只有一次法阵
				if skill != null and skill.is_channeling and float(skill.duration) >= 1.5:
					cast_glow(scp, s_col, 1.5, clampf(float(skill.duration), 0.8, 2.5))
			"line":
				if caster_pos.distance_to(target_pos) < 16.0:
					beam(caster_pos + sfdir * 0.4, target_pos + Vector3.UP * 0.8, s_col, 0.20, 0.30)
				hit_spark(target_pos + Vector3.UP, s_col, Vector3.UP, 0.9)
			"dash":
				dash_fx(scp, sgy, s_col, _is_local, float(skill.self_displacement) if skill != null else -1.0)
			"aura":
				cast_glow(scp, s_col, 1.3, 0.7)
			"channel":
				cast_glow(scp, s_col, 1.4, float(skill.duration) if skill != null else 0.8)
			_:
				if caster_pos.distance_to(target_pos) < 16.0:
					beam(caster_pos + sfdir * 0.4, target_pos + Vector3.UP * 0.9, s_col, 0.16, 0.26)
				hit_spark(target_pos + Vector3.UP, s_col, Vector3.UP, 0.8)
		_spawn_skill_prop(hero_name, slot, caster_pos, target_pos, s_col)
		return
	var entry: Dictionary = SPELL_FX.get_ult(hero_name)
	var el: Dictionary = element_data(str(entry.get("el", element_of(hero_name))))
	var col: Color = el["c"]
	var col2: Color = el["c2"]
	var cp := Vector3(caster_pos.x, 0.08, caster_pos.z)
	var gy := Vector3(target_pos.x, 0.08, target_pos.z)
	var fdir: Vector3 = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	_burst(col, col2, caster_pos, 18, 0.6, el["size"], el["speed"], fdir, 55.0, el["gravity"])
	sigil(cp, col, 2.2, 0.55)
	_light(caster_pos, el["light"], 3.0, 0.22)
	match str(entry.get("shape", "nova")):
		"self_stamp":
			pillar(cp, col, 1.8, 7.0, 0.75)
			nova(cp, col, 3.2)
		"target_big":
			sigil(gy, col, 3.6, 0.95)
			pillar(gy, col, 2.2, 9.0, 0.85)
			nova(gy, col, 3.8)
			_delayed_pillar(gy, col, 0.18)
		"target_zone":
			telegraph(gy, 4.2, col, 0.85)
			_delayed_ring(gy, 4.2, col, 0.15, 0.55)
			_delayed_ring(gy, 2.8, col, 0.30, 0.50)
			_burst(col, col2, Vector3(gy.x, 2.0, gy.z), 16, 0.7, el["size"] * 1.2, 4.0, Vector3.UP, 30.0, -1.0)
		"self_zone":
			sigil(cp, col, 4.2, 0.95)
			_delayed_ring(cp, 4.2, col, 0.12, 0.60)
			_burst(col, col2, Vector3(cp.x, 3.0, cp.z), 22, 0.9, el["size"], 2.0, Vector3.DOWN, 25.0, 3.0)
		"beam":
			var bstart: Vector3 = caster_pos + fdir * 0.4
			var bdur := 0.55
			if skill != null and skill.is_channeling:
				bdur = clampf(float(skill.duration), 0.6, 2.0)
			beam(bstart, target_pos + Vector3.UP * 1.0, col, 0.36, bdur)
			shockwave(gy, 2.2, col, 0.45)
			hit_spark(target_pos + Vector3.UP, col, Vector3.UP, 1.4)
		"nova":
			nova(cp, col, 3.4)
			_burst(col, col2, caster_pos, 20, 0.8, el["size"], 5.0, Vector3.UP, 60.0, -1.5)
		"slash":
			slash_fx(caster_pos, target_pos, col)
		"dash":
			dash_fx(cp, gy, col)
	_spawn_skill_prop(hero_name, slot, caster_pos, target_pos, col)

## 地面法阵：径向光斑 + 两圈反向旋转的环，用于大招落点/区域技能
func sigil(pos: Vector3, color: Color, radius: float = 3.0, dur: float = 0.9) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.position = pos
	_add_root(root)
	var disc := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	disc.mesh = plane
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dmat := ShaderMaterial.new()
	dmat.shader = _glow_shader
	dmat.set_shader_parameter("glow_color", color)
	dmat.set_shader_parameter("intensity", 1.5)
	dmat.set_shader_parameter("softness", 0.62)
	dmat.set_shader_parameter("ring_width", 0.14)
	dmat.set_shader_parameter("pulse_speed", 5.0)
	disc.material_override = dmat
	root.add_child(disc)
	var rings: Array[MeshInstance3D] = []
	var mats: Array[StandardMaterial3D] = []
	for i in range(2):
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var r := radius * (0.92 if i == 0 else 0.62)
		torus.inner_radius = r * 0.93
		torus.outer_radius = r
		torus.rings = 24
		torus.ring_segments = 8
		mi.mesh = torus
		mi.position = Vector3(0, 0.03, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.2
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		root.add_child(mi)
		rings.append(mi)
		mats.append(mat)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(rings[0], "rotation:y", TAU, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(rings[1], "rotation:y", -TAU, dur).set_ease(Tween.EASE_OUT)
	for mat in mats:
		tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_property(dmat, "shader_parameter/intensity", 0.0, dur * 1.15)
	tw.tween_property(disc, "scale", Vector3(1.25, 1.0, 1.25), dur).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(root.queue_free)

## 光柱：大招落地/变身用的竖直能量柱
func pillar(pos: Vector3, color: Color, radius: float = 2.0, height: float = 8.0, dur: float = 0.8) -> void:
	if quality <= 0 or get_tree() == null:
		return
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.position = pos
	_add_root(root)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.55
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	cyl.rings = 1
	mi.mesh = cyl
	mi.position = Vector3(0, height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.45, 1.0, 1.45), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, dur)
	tw.chain().tween_callback(root.queue_free)

## 环形爆发：双圈冲击波 + 上冲粒子
func nova(pos: Vector3, color: Color, radius: float = 3.4) -> void:
	shockwave(pos, radius, color, 0.55)
	shockwave(pos, radius * 0.68, color.lerp(Color.WHITE, 0.35), 0.42)
	_burst(color, Color.WHITE, pos + Vector3.UP * 0.9, 16, 0.7, 0.6, 5.0, Vector3.UP, 55.0, -1.0)

## 连斩：三道扇形刀光 + 落点火花
func slash_fx(from: Vector3, to: Vector3, color: Color) -> void:
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.5:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var base: Vector3 = from + Vector3.UP * 1.1
	for i in range(3):
		var d := dir.rotated(Vector3.UP, (float(i) - 1.0) * 0.42)
		beam(base, base + d * 3.4, color, 0.09, 0.30)
		beam(base, base + d * 3.4, color.lerp(Color.WHITE, 0.5), 0.05, 0.24)
	hit_spark(to + Vector3.UP, color, Vector3.UP, 1.2)

## 突进：起点爆发 + 沿途残影粒子
## 位移类技能特效：蹬地冲击环 + 贯穿全程的加色拖尾光带 + 沿途速度线 + 落点冲击
## dist > 0 时用真实位移距离（self_displacement），否则按起点→瞄准点估算
func dash_fx(from: Vector3, to: Vector3, color: Color, is_local: bool = false, dist: float = -1.0) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var dir := to - from
	dir.y = 0.0
	if dir.length() < 0.3:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var start := Vector3(from.x, 0.08, from.z)
	var len := dist
	if len <= 0.0:
		len = Vector3(to.x - from.x, 0.0, to.z - from.z).length()
	len = clampf(len, 1.5, 16.0)
	var end := start + dir * len
	# 起手：蹬地冲击环 + 后向扬尘
	_ring(start, 1.05, color, 0.28, 2.0, 0.24)
	_burst(color, Color.WHITE, start + Vector3.UP * 0.45, 8, 0.32, 0.4, 3.2, -dir, 70.0, 0.9)
	# 拖尾：整条路径的加色光带（原来只有起点附近几簇粒子，看不出"冲过去"）
	_streak(start, end, color)
	# 速度线：沿路径三段前向粒子，连成连续流
	for i in range(3):
		var f := float(i + 1) / 4.0
		_burst(color, Color.WHITE, start + dir * (len * f) + Vector3.UP * 1.0, 4, 0.26, 0.3, 2.2, dir, 25.0, 0.2)
	# 落点：冲击环 + 光斑 + 前向碎光
	_ring(end, 1.30, color, 0.36, 1.7, 0.26)
	cast_glow(end, color, 1.1, 0.30)
	_burst(color, Color.WHITE, end + Vector3.UP * 0.5, 12, 0.38, 0.45, 4.6, dir, 45.0, 0.7)
	# 手感：本地玩家位移给一点镜头反馈（AI/远处不抖）
	if is_local and quality >= 2:
		camera_shake(0.07, 0.14)

## 位移拖尾：沿位移方向的加色光带 + 白色细芯，短促淡出
func _streak(a: Vector3, b: Vector3, color: Color) -> void:
	var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var len := flat.length()
	if len < 0.3:
		return
	var dir := flat / len
	var root := Node3D.new()
	root.position = (a + b) * 0.5 + Vector3.UP * 1.0
	root.rotation.y = atan2(dir.x, dir.z)
	root.add_to_group(GROUP_FX)
	for i in range(2):
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.62, 0.62, len) if i == 0 else Vector3(0.20, 0.20, len)
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.albedo_color = Color(color.r, color.g, color.b, 0.30) if i == 0 else Color(1.0, 1.0, 1.0, 0.50)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var tw := mi.create_tween()
		tw.tween_property(m, "albedo_color:a", 0.0, 0.34 if i == 0 else 0.26)
	_add_root(root)
	var tw2 := root.create_tween()
	tw2.tween_interval(0.45)
	tw2.tween_callback(root.queue_free)

func _delayed_ring(pos: Vector3, radius: float, color: Color, delay: float, dur: float) -> void:
	if get_tree() == null:
		return
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func(): _ring(pos, radius, color, dur, 1.8, 0.4))

func _delayed_pillar(pos: Vector3, color: Color, delay: float) -> void:
	if get_tree() == null:
		return
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func(): pillar(pos, color, 2.0, 8.0, 0.7))

# ---------------- P2.5 法术道具（实体网格：扇/旋风/冰柱/冰晶/飞剑/法球/太阳） ----------------
## 道具统一材质：无光照 + 自发光 + 双面，保证移动端也读得出轮廓
func _prop_mat(color: Color, alpha: float = 0.9, emission: float = 1.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = emission
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m

## 程序化扇形网格（扇面在 XY 平面、朝 +Z），带轻微弧度
func _fan_mesh(radius: float, span_deg: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := deg_to_rad(span_deg)
	var half := span * 0.5
	for i in range(segs):
		var a0 := -half + span * float(i) / float(segs)
		var a1 := -half + span * float(i + 1) / float(segs)
		var p0 := Vector3(sin(a0) * radius, cos(a0) * radius, -cos(a0) * 0.12)
		var p1 := Vector3(sin(a1) * radius, cos(a1) * radius, -cos(a1) * 0.12)
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.5 + sin(a0) * 0.5, 0.5 + cos(a0) * 0.5))
		st.add_vertex(p0)
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.5 + sin(a1) * 0.5, 0.5 + cos(a1) * 0.5))
		st.add_vertex(p1)
	return st.commit()

## 半月形波刃网格（宽沿 X、高沿 Y、+Z 为前进方向，中心前凸；两端收尖）
func _crescent_mesh(width: float, height: float, bow: float, segs: int = 28) -> ArrayMesh:
	var key := "%.2f|%.2f|%.2f|%d" % [width, height, bow, segs]
	var cached: ArrayMesh = _crescent_mesh_cache.get(key)
	if cached != null:
		return cached
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segs):
		var t0 := -1.0 + 2.0 * float(i) / float(segs)
		var t1 := -1.0 + 2.0 * float(i + 1) / float(segs)
		var x0 := t0 * width * 0.5
		var x1 := t1 * width * 0.5
		var z0 := bow * (1.0 - t0 * t0)
		var z1 := bow * (1.0 - t1 * t1)
		var h0 := height * (1.0 - pow(absf(t0), 1.6) * 0.72)
		var h1 := height * (1.0 - pow(absf(t1), 1.6) * 0.72)
		var a := Vector3(x0, 0.0, z0)
		var b := Vector3(x1, 0.0, z1)
		var c := Vector3(x1, h1, z1)
		var d := Vector3(x0, h0, z0)
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_uv(Vector2(1.0, 0.0))
		st.add_vertex(b)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(a)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(c)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(d)
	var mesh := st.commit()
	_crescent_mesh_cache[key] = mesh
	return mesh

## 妲己·灵魂冲击：半月形波刃挂在子弹上随之飞行（外层柔光 + 内层白热亮芯 + 拖尾）
func crescent_wave(bullet: Node3D, dir: Vector3, color: Color, width: float = 5.0) -> void:
	if quality <= 0 or bullet == null or not is_instance_valid(bullet):
		return
	var s := maxf(bullet.scale.x, 0.01)
	var w := width / s
	var h := 1.15 / s
	var bow := 1.25 / s
	var root := Node3D.new()
	root.name = "DajiCrescent"
	root.rotation.y = atan2(dir.x, dir.z)
	bullet.add_child(root)
	var outer_mat := _prop_mat(color, 0.40, 1.8)
	outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var outer := MeshInstance3D.new()
	outer.mesh = _crescent_mesh(w, h * 1.28, bow * 1.15, 20)
	outer.material_override = outer_mat
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(outer)
	var core_mat := _prop_mat(color.lerp(Color.WHITE, 0.75), 0.95, 2.8)
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := MeshInstance3D.new()
	core.mesh = _crescent_mesh(w * 0.93, h * 0.56, bow * 0.92, 14)
	core.position = Vector3(0, h * 0.30, -0.02 / s)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	# 只保留一层外层拖尾：内层亮芯本身已在同一网格里，不再叠第二套粒子
	attach_trail(root, color, 0.36, 0.30, 8, Color(1.0, 0.9, 1.0, 0.55))

## 按英雄/槽位生成道具；离本地英雄太远或特效已满时跳过
func _spawn_skill_prop(hero_name: String, slot: int, caster_pos: Vector3, target_pos: Vector3, color: Color) -> void:
	if quality <= 0 or get_tree() == null:
		return
	var prop := SPELL_FX.get_prop(hero_name, slot)
	if prop == "":
		return
	if get_tree().get_nodes_in_group(GROUP_PROP).size() >= MAX_PROPS:
		return
	var bm = _bm()
	if bm and bm.hero and is_instance_valid(bm.hero):
		if ((caster_pos + target_pos) * 0.5).distance_to(bm.hero.global_position) > PROP_RANGE:
			return
	match prop:
		"fan":
			fan_fx(caster_pos, target_pos, color)
		"tornado":
			tornado_fx(target_pos, color)
		"ice_pillars":
			ice_pillars_fx(target_pos, color)
		"ice_crystal":
			ice_crystal_fx(caster_pos, color)
		"swords":
			swords_fx(caster_pos, target_pos, color)
		"orbs":
			orbs_fx(caster_pos, color)
		"sun_orb":
			sun_orb_fx(caster_pos, color)

## 小乔·扇子：实体扇面 + 5 根扇骨，旋转飞向目标
func fan_fx(caster_pos: Vector3, target_pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = caster_pos + Vector3.UP * 1.1
	_add_root(root)
	var mat := _prop_mat(color.lerp(Color.WHITE, 0.35), 0.94, 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = _fan_mesh(0.95, 132.0, 16)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var rib_mat := _prop_mat(color.lerp(Color.WHITE, 0.7), 0.9, 0.6)
	for i in range(5):
		var ang := deg_to_rad(-62.0 + 31.0 * float(i))
		var rib := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.9, 0.025)
		rib.mesh = bm
		rib.material_override = rib_mat
		rib.position = Vector3(sin(ang), cos(ang), 0.01) * 0.45
		rib.rotation.z = -ang
		root.add_child(rib)
	attach_trail(root, color, 0.18, 0.25, 6)
	var dest := Vector3(target_pos.x, 0.9, target_pos.z)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "position", dest, 0.42).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "rotation:y", TAU * 1.5, 0.42)
	tw.tween_property(root, "scale", Vector3(1.35, 1.35, 1.35), 0.42)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.30).set_delay(0.30)
	tw.tween_property(rib_mat, "albedo_color:a", 0.0, 0.30).set_delay(0.30)
	tw.chain().tween_callback(root.queue_free)
	hit_spark(dest, color, Vector3.UP, 0.9)

## 小乔·旋风：三层旋转环 + 上升气流粒子
func tornado_fx(pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = Vector3(pos.x, 0.0, pos.z)
	_add_root(root)
	var mats: Array[StandardMaterial3D] = []
	for i in range(3):
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var base_r := 1.05 - 0.22 * float(i)
		torus.inner_radius = base_r * 0.72
		torus.outer_radius = base_r
		mi.mesh = torus
		mi.position.y = 0.28 + 0.5 * float(i)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _prop_mat(color.lerp(Color.WHITE, 0.2 + 0.16 * float(i)), 0.42, 1.8)
		mi.material_override = mat
		root.add_child(mi)
		mats.append(mat)
		var spin := mi.create_tween()
		spin.set_loops()
		spin.tween_property(mi, "rotation:y", TAU, 0.55 - 0.08 * float(i))
	_ring(Vector3(pos.x, 0.06, pos.z), 1.0, color, 0.55, 1.7, 0.4)
	_burst(color, color.lerp(Color.WHITE, 0.4), root.position + Vector3.UP * 0.4, 22, 0.9, 0.55, 3.0, Vector3.UP, 35.0, -3.0)
	var tw := root.create_tween()
	tw.tween_interval(1.4)
	for mat in mats:
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(root.queue_free)

## 冰柱用的多棱水晶网格：底粗、腰部鼓、顶部收尖，切面有轻微不规则。
func _crystal_mesh(rad: float, h: float, sides: int = 6, twist: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ys: Array[float] = [0.0, h * 0.20, h * 0.48, h * 0.74]
	var rs: Array[float] = [rad * 0.72, rad, rad * 0.72, rad * 0.38]
	var rings: Array = []
	var rot := 0.0
	for ri in range(ys.size()):
		var ring: Array[Vector3] = []
		for i in range(sides):
			var a := TAU * float(i) / float(sides) + rot
			var rr := rs[ri] * (1.0 + 0.075 * sin(float(i) * 2.7 + float(ri) * 1.6))
			ring.append(Vector3(cos(a) * rr, ys[ri], sin(a) * rr))
		rings.append(ring)
		rot += twist
	var tip := Vector3(cos(twist * 1.7) * rad * 0.12, h, sin(twist * 1.7) * rad * 0.12)
	for ri in range(rings.size() - 1):
		var lo: Array = rings[ri]
		var hi: Array = rings[ri + 1]
		for i in range(sides):
			var j := (i + 1) % sides
			_tri(st, lo[i], hi[j], lo[j])
			_tri(st, lo[i], hi[i], hi[j])
	var last: Array = rings[rings.size() - 1]
	for i in range(sides):
		var j := (i + 1) % sides
		_tri(st, last[i], tip, last[j])
	var base: Array = rings[0]
	for i in range(sides):
		var j := (i + 1) % sides
		_tri(st, base[i], base[j], Vector3.ZERO)
	return st.commit()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)

## 冰晶材质：保留受光切面（不是纯 unshaded 平板），外壳半透 + 冷色自发光。
func _ice_crystal_mat(color: Color, alpha: float, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.metallic = 0.12
	m.roughness = 0.16
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = emission
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m

## 甄姬·冰柱：中心冰核 + 环形六棱冰锥错峰升起；外壳半透 + 内核高光 + 地面霜裂纹 + 碎冰
func ice_pillars_fx(pos: Vector3, color: Color, count: int = 6, radius: float = 2.4) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = Vector3(pos.x, 0.0, pos.z)
	_add_root(root)
	var mats: Array[StandardMaterial3D] = []
	# 布局：1 根中心主冰柱 + 环形副冰柱；中低画质先减数量，保留冰阵轮廓
	var total := count
	if quality <= 1:
		total = 3
	elif quality <= 2:
		total = 4
	var slots: Array[Vector2] = [Vector2.ZERO]
	var ring_n := maxi(total - 1, 1)
	for i in range(ring_n):
		var a := TAU * float(i) / float(ring_n) + randf_range(-0.18, 0.18)
		var d := radius * randf_range(0.55, 0.95)
		slots.append(Vector2(cos(a) * d, sin(a) * d))
	for i in slots.size():
		var off := slots[i]
		var is_core := i == 0
		var h := randf_range(1.7, 2.7) if is_core else randf_range(1.0, 2.0)
		var rad := randf_range(0.40, 0.52) if is_core else randf_range(0.22, 0.36)
		var node := Node3D.new()
		node.position = Vector3(off.x, 0.0, off.y)
		node.rotation.y = randf() * TAU
		root.add_child(node)
		# 外层多棱冰晶：底粗、腰部微鼓、上端收尖，切面受光（不再是平板圆锥）
		var shell := MeshInstance3D.new()
		shell.mesh = _crystal_mesh(rad, h, 6, 0.11)
		shell.position.y = -0.04
		shell.rotation.z = randf_range(-0.10, 0.10)
		shell.rotation.x = randf_range(-0.08, 0.08)
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var smat := _ice_crystal_mat(color.lerp(Color.WHITE, 0.58), 0.44, 1.35)
		shell.material_override = smat
		mats.append(smat)
		node.add_child(shell)
		# 内层冰芯：更亮更细的多棱结晶
		var core := MeshInstance3D.new()
		core.mesh = _crystal_mesh(rad * 0.42, h * 0.80, 5, 0.22)
		core.position.y = h * 0.06
		var cmat := _ice_crystal_mat(Color(0.86, 0.97, 1.0), 0.92, 3.2)
		cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		core.material_override = cmat
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(core)
		mats.append(cmat)
		if quality >= 2:
			var spin := core.create_tween()
			spin.set_loops()
			spin.tween_property(core, "rotation:y", TAU, 2.8 + randf_range(0.4, 1.2))
		# 主冰柱底部加几片斜插碎冰，打破"一根光锥"的单调轮廓
		if is_core and quality >= 2:
			for si in range(3):
				var sa := TAU * float(si) / 3.0 + randf_range(-0.25, 0.25)
				var shard := MeshInstance3D.new()
				shard.mesh = _crystal_mesh(rad * randf_range(0.22, 0.30), h * randf_range(0.20, 0.30), 5, 0.4)
				shard.material_override = smat
				shard.position = Vector3(cos(sa) * rad * 0.92, 0.0, sin(sa) * rad * 0.92)
				shard.rotation = Vector3(deg_to_rad(randf_range(10.0, 20.0)), -sa, deg_to_rad(randf_range(10.0, 20.0)))
				shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(shard)
		# 地面霜座
		var base := MeshInstance3D.new()
		var bcyl := CylinderMesh.new()
		bcyl.top_radius = rad * 1.30
		bcyl.bottom_radius = rad * 1.55
		bcyl.height = 0.10
		bcyl.radial_segments = 6
		base.mesh = bcyl
		base.position.y = 0.05
		var bmat := _prop_mat(color.lerp(Color.WHITE, 0.30), 0.62, 1.1)
		base.material_override = bmat
		base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(base)
		mats.append(bmat)
		# 错峰破土：纵向回弹生长
		node.scale = Vector3(1.0, 0.01, 1.0)
		var grow := node.create_tween()
		grow.tween_interval(0.045 * float(i))
		grow.tween_property(node, "scale:y", 1.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 地面放射霜裂纹
	var crack_mat := _prop_mat(color.lerp(Color.WHITE, 0.65), 0.42, 1.6)
	var crack_n := 5 if quality <= 2 else 8
	for i in range(crack_n):
		var a := TAU * float(i) / float(crack_n) + randf_range(-0.22, 0.22)
		var ln := radius * randf_range(0.65, 1.25)
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.02, ln)
		seg.mesh = bm
		seg.material_override = crack_mat
		seg.position = Vector3(cos(a) * ln * 0.5, 0.045, sin(a) * ln * 0.5)
		seg.rotation.y = -a + PI * 0.5
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(seg)
	mats.append(crack_mat)
	sigil(root.position, color, radius * 1.25, 0.9)
	cast_glow(Vector3(pos.x, 0.25, pos.z), color, radius * 1.05, 0.35)
	_burst(color.lerp(Color.WHITE, 0.6), color, root.position + Vector3.UP * 0.35, 26, 0.9, 0.5, 2.2, Vector3.UP, 55.0, 2.0)
	# 到期：先淡出，再炸一圈碎冰后回收
	for mat in mats:
		var ft := root.create_tween()
		ft.tween_interval(1.55)
		ft.tween_property(mat, "albedo_color:a", 0.0, 0.30)
	var tw := root.create_tween()
	tw.tween_interval(1.88)
	tw.tween_callback(_ice_shatter.bind(pos, color, radius, root))


## 冰柱到期碎裂：碎冰四散 + 霜环
func _ice_shatter(pos: Vector3, color: Color, radius: float, root: Node3D) -> void:
	_burst(color.lerp(Color.WHITE, 0.4), color, Vector3(pos.x, 0.7, pos.z), 18, 0.5, 0.34, 3.2, Vector3.UP, 70.0, 7.0)
	_ring(Vector3(pos.x, 0.08, pos.z), radius * 0.9, color, 0.32, 1.5, 0.26)
	if is_instance_valid(root):
		root.queue_free()

## 王昭君/甄姬·冰晶：双锥棱晶悬浮旋转 + 冷光 + 雪雾
func ice_crystal_fx(pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = Vector3(pos.x, 1.4, pos.z)
	_add_root(root)
	var mat := _prop_mat(color.lerp(Color.WHITE, 0.6), 0.92, 1.7)
	for k in range(2):
		var mi := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.34
		cone.height = 0.85
		cone.radial_segments = 6
		mi.mesh = cone
		mi.material_override = mat
		mi.position.y = 0.42 if k == 0 else -0.42
		if k == 1:
			mi.rotation.x = PI
		root.add_child(mi)
	var spin := root.create_tween()
	spin.set_loops()
	spin.tween_property(root, "rotation:y", TAU, 1.6)
	var bob := root.create_tween()
	bob.set_loops()
	bob.tween_property(root, "position:y", root.position.y + 0.25, 0.8).set_trans(Tween.TRANS_SINE)
	bob.tween_property(root, "position:y", root.position.y, 0.8).set_trans(Tween.TRANS_SINE)
	_light(root.position, color, 2.2, 0.3)
	_burst(color, Color.WHITE, root.position, 12, 1.0, 0.5, 1.6, Vector3.DOWN, 30.0, 1.5)
	var tw := root.create_tween()
	tw.tween_interval(1.3)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(root.queue_free)

## 李白·飞剑：4 柄实体剑从四周刺向目标 + 落点火花
func swords_fx(caster_pos: Vector3, target_pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = Vector3(target_pos.x, 0.0, target_pos.z)
	_add_root(root)
	var mat := _prop_mat(color.lerp(Color.WHITE, 0.5), 0.92, 1.6)
	for i in range(4):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 1.1, 0.18)
		mi.mesh = bm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / 4.0
		mi.position = Vector3(cos(ang) * 3.0, 1.0 + float(i % 2) * 0.4, sin(ang) * 3.0)
		mi.rotation = Vector3(0, -ang, 0)
		root.add_child(mi)
		var fly := mi.create_tween()
		fly.set_parallel(true)
		fly.tween_property(mi, "position", Vector3(0, 0.9, 0), 0.30).set_delay(0.06 * float(i)).set_ease(Tween.EASE_IN)
		fly.tween_property(mi, "rotation:y", -ang + TAU, 0.30).set_delay(0.06 * float(i))
	hit_spark(target_pos + Vector3.UP, color, Vector3.UP, 1.1)
	var tw := root.create_tween()
	tw.tween_interval(0.72)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.30)
	tw.tween_callback(root.queue_free)

## 安琪拉/妲己·法球：3 颗实体光球绕施法者旋转
func orbs_fx(caster_pos: Vector3, color: Color, count: int = 3) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = caster_pos + Vector3.UP * 1.3
	_add_root(root)
	var mat := _prop_mat(color.lerp(Color.WHITE, 0.35), 0.95, 1.8)
	for i in range(count):
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		sm.radial_segments = 10
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / float(count)
		mi.position = Vector3(cos(ang) * 0.65, sin(float(i) * 2.0) * 0.15, sin(ang) * 0.65)
		root.add_child(mi)
	var tw := root.create_tween()
	tw.set_loops(2)
	tw.tween_property(root, "rotation:y", TAU, 0.7)
	_light(root.position, color, 2.0, 0.3)
	var tw2 := root.create_tween()
	tw2.tween_interval(1.3)
	tw2.tween_property(mat, "albedo_color:a", 0.0, 0.30)
	tw2.tween_callback(root.queue_free)

## 后羿·太阳：发光球体 + 8 道旋转光芒
func sun_orb_fx(pos: Vector3, color: Color) -> void:
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.add_to_group(GROUP_PROP)
	root.position = pos + Vector3.UP * 2.2
	_add_root(root)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	sm.radial_segments = 16
	sm.rings = 8
	core.mesh = sm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := _prop_mat(color.lerp(Color.WHITE, 0.45), 0.95, 2.6)
	core.material_override = cmat
	root.add_child(core)
	var ray_mat := _prop_mat(color, 0.8, 1.8)
	for i in range(8):
		var ray := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.02, 0.9)
		ray.mesh = bm
		ray.material_override = ray_mat
		ray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang := TAU * float(i) / 8.0
		ray.position = Vector3(cos(ang) * 0.95, 0.0, sin(ang) * 0.95)
		ray.rotation.y = -ang
		root.add_child(ray)
	var spin := root.create_tween()
	spin.set_loops()
	spin.tween_property(root, "rotation:y", TAU, 2.4)
	var pulse := root.create_tween()
	pulse.set_loops()
	pulse.tween_property(core, "scale", Vector3(1.15, 1.15, 1.15), 0.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(core, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_SINE)
	_light(root.position, color, 3.0, 0.4)
	var tw := root.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(cmat, "albedo_color:a", 0.0, 0.30)
	tw.tween_property(ray_mat, "albedo_color:a", 0.0, 0.30)
	tw.tween_callback(root.queue_free)

# ---------------- 内部 ----------------
func _bm():
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("battle_manager")

func _add_root(n: Node) -> void:
	if get_tree() == null or get_tree().current_scene == null:
		if is_inside_tree():
			get_tree().root.add_child(n)
		return
	get_tree().current_scene.add_child(n)

func _near_limit(priority: int) -> bool:
	if get_tree() == null:
		return true
	var n := get_tree().get_nodes_in_group(GROUP_FX).size()
	var cap := MAX_ACTIVE
	if quality <= 1:
		cap = int(MAX_ACTIVE * 0.5)
	elif quality >= 3:
		cap = int(MAX_ACTIVE * 1.5)
	return n >= cap and priority < 2

func _scaled_amount(base: int) -> int:
	if quality <= 0:
		return 0
	if quality == 1:
		return maxi(2, int(base * 0.5))
	if quality >= 3:
		return int(base * 1.5)
	return base

func _burst(color: Color, color2: Color, pos: Vector3, amount: int, lifetime: float, size: float,
		speed: float, dir: Vector3, spread: float, gravity: float, spark: bool = false) -> void:
	if quality <= 0 or _near_limit(1):
		return
	amount = _scaled_amount(amount)
	if amount <= 0:
		return
	var tex: Texture2D = _spark_tex if spark else _soft_tex
	var p := _particles(amount, lifetime, color, size, speed, 0.5, dir, 0.25, true, tex)
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	_add_root(p)
	var tw := p.create_tween()
	tw.tween_interval(lifetime + 0.2)
	tw.tween_callback(p.queue_free)
	# 副色爆点只给中大型爆发；命中火花/枪口不再额外建第二套粒子系统
	if amount >= 14 and quality >= 2:
		var p2 := _particles(maxi(2, amount / 3), lifetime * 0.7, color2, size * 0.55, speed * 1.3, 0.3, dir, 0.2, true, _spark_tex)
		p2.position = pos
		p2.emitting = true
		p2.one_shot = true
		p2.explosiveness = 1.0
		_add_root(p2)
		var tw2 := p2.create_tween()
		tw2.tween_interval(lifetime * 0.7 + 0.2)
		tw2.tween_callback(p2.queue_free)

func _ring(pos: Vector3, radius: float, color: Color, dur: float, scale_up: float = 1.6, width: float = 0.28) -> void:
	if quality <= 0 or get_tree() == null or _near_limit(1):
		return
	var root := Node3D.new()
	root.add_to_group(GROUP_FX)
	root.position = pos
	_add_root(root)
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * (1.0 - width)
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 8
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(scale_up, 1.0, scale_up), dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, dur)
	tw.chain().tween_callback(root.queue_free)

func _particles(amount: int, lifetime: float, color: Color, size: float, speed: float,
		spread_min: float, dir: Vector3, gravity_scale: float, one_shot: bool,
		tex: Texture2D = null) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = maxf(0.1, lifetime)
	p.one_shot = one_shot
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 16, 24))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(0.08, size * 0.4)
	pm.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	pm.spread = 180.0 if dir.length() < 0.01 else 75.0
	pm.initial_velocity_min = speed * 0.35
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0.0, -9.8 * gravity_scale, 0.0)
	pm.damping_min = 0.6
	pm.damping_max = 1.6
	pm.scale_min = size * 0.55
	pm.scale_max = size
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.color = color
	pm.color_ramp = _get_particle_ramp()
	p.process_material = pm
	p.draw_pass_1 = _get_particle_quad(tex == _spark_tex)
	p.add_to_group(GROUP_FX)
	return p


func _get_particle_ramp() -> GradientTexture1D:
	if _particle_ramp_tex == null:
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		_particle_ramp_tex = GradientTexture1D.new()
		_particle_ramp_tex.gradient = ramp
	return _particle_ramp_tex


func _get_particle_quad(spark: bool) -> QuadMesh:
	if spark:
		if _particle_quad_spark == null:
			_particle_quad_spark = _make_particle_quad(_spark_tex)
		return _particle_quad_spark
	if _particle_quad_soft == null:
		_particle_quad_soft = _make_particle_quad(_soft_tex)
	return _particle_quad_soft


func _make_particle_quad(tex: Texture2D) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex if tex != null else _soft_tex
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	return quad

func _make_radial_texture(size: int, soft: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, soft, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


# ---------------- 李元芳·暗印飞镖环绕（Q 专属表现）----------------
# 暗印挂在目标身上时，飞镖实体绕着目标旋转；层数=飞镖数（1~3，满4层直接引爆）。
# 全部本地表现，不参与结算；目标死亡/失效/计时结束自动回收。
func lyf_dart_sync(target: Node3D, darts: int, life: float, color: Color = LYF_DART_COL) -> void:
	if quality <= 0 or get_tree() == null or target == null or not is_instance_valid(target):
		return
	var tid := target.get_instance_id()
	var entry: Dictionary = _lyf_orbits.get(tid, {})
	if entry.is_empty():
		# 同屏最多 3 个暗印目标；超出的目标只保留伤害标记，不再生成飞镖/拖尾
		if _lyf_orbits.size() >= (3 if quality >= 2 else 2):
			return
		var root := Node3D.new()
		root.name = "LyfDartOrbit"
		target.add_child(root)
		# 脚下暗印环：一眼看出"被挂印记"
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.42
		tor.outer_radius = 0.54
		tor.rings = 20
		tor.ring_segments = 6
		ring.mesh = tor
		ring.material_override = _add_mat(color, 0.55, 2.0)
		ring.position = Vector3(0, 0.07, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		entry = {"target": target, "root": root, "darts": [], "ring": ring,
				"angle": 0.0, "life": 0.0, "color": color}
		_lyf_orbits[tid] = entry
	entry["target"] = target
	entry["life"] = maxf(life, 0.2)
	var want := clampi(darts, 1, 3)
	var arr: Array = entry["darts"]
	while arr.size() < want:
		var d := _lyf_make_dart(color)
		(entry["root"] as Node3D).add_child(d)
		arr.append(d)
	while arr.size() > want:
		var last = arr.pop_back()
		if is_instance_valid(last):
			last.queue_free()


func lyf_dart_clear(target: Node3D, burst_fx: bool = true) -> void:
	if target == null or not is_instance_valid(target):
		return
	var tid := target.get_instance_id()
	if not _lyf_orbits.has(tid):
		return
	var entry: Dictionary = _lyf_orbits[tid]
	_lyf_orbits.erase(tid)
	_lyf_orbit_free(entry, burst_fx)


func _lyf_make_dart(color: Color) -> Node3D:
	var node := Node3D.new()
	node.name = "LyfDart"
	var mat := _add_mat(color, 0.95, 2.4)
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var blade := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.055
	cone.height = 0.36
	cone.radial_segments = 6
	cone.rings = 1
	blade.mesh = cone
	blade.material_override = mat
	blade.position = Vector3(0, 0.14, 0)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(blade)
	attach_trail(node, color, 0.09, 0.12, 2, Color(1.0, 1.0, 1.0, 0.35))
	return node


func _lyf_orbit_free(entry: Dictionary, burst_fx: bool) -> void:
	var t = entry.get("target")
	var pos := Vector3.ZERO
	if t != null and is_instance_valid(t) and t is Node3D:
		pos = (t as Node3D).global_position + Vector3.UP * 1.05
	if burst_fx and quality >= 1 and get_tree() != null:
		_burst(LYF_DART_COL, LYF_DART_COL2, pos, 10, 0.38, 0.18, 4.6, Vector3.UP, 60.0, -2.0)
		_ring(Vector3(pos.x, 0.08, pos.z), 1.15, LYF_DART_COL, 0.30, 1.7, 0.22)
	var root = entry.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()


func _process(delta: float) -> void:
	if _lyf_orbits.is_empty():
		return
	for tid in _lyf_orbits.keys():
		var entry: Dictionary = _lyf_orbits[tid]
		var t = entry.get("target")
		if t == null or not is_instance_valid(t) or t.get("is_dead") == true:
			_lyf_orbits.erase(tid)
			_lyf_orbit_free(entry, true)
			continue
		entry["life"] = float(entry["life"]) - delta
		if float(entry["life"]) <= 0.0:
			_lyf_orbits.erase(tid)
			_lyf_orbit_free(entry, true)
			continue
		var root = entry.get("root")
		if root == null or not is_instance_valid(root):
			_lyf_orbits.erase(tid)
			continue
		entry["angle"] = float(entry["angle"]) + delta * 2.7
		var arr: Array = entry["darts"]
		var n := maxf(1.0, float(arr.size()))
		for i in arr.size():
			var d = arr[i]
			if d == null or not is_instance_valid(d):
				continue
			var ang: float = float(entry["angle"]) + TAU * float(i) / n
			(d as Node3D).position = Vector3(cos(ang) * 0.78, 1.02 + sin(ang * 2.0 + float(i)) * 0.07, sin(ang) * 0.78)
			(d as Node3D).rotation = Vector3(PI * 0.42, -ang + PI * 0.5, sin(float(Time.get_ticks_msec()) * 0.009 + float(i)) * 0.22)
		var ring = entry.get("ring")
		if ring != null and is_instance_valid(ring):
			(ring as Node3D).rotation.y += delta * 1.6
			var pulse: float = 1.0 + sin(float(Time.get_ticks_msec()) * 0.01) * 0.06
			(ring as Node3D).scale = Vector3(pulse, 1.0, pulse)


# ---------------- 手雷弹体（孙尚香2 红莲爆弹 / 鲁班1 河豚手雷） ----------------
## 把手雷外观挂到飞行中的 Bullet 上：隐藏默认弹体 + 自旋 + 引信闪烁 + 拖尾
func grenade_attach(bullet: Node3D, color: Color, kind: String = "puffer") -> void:
	if quality <= 0 or bullet == null or not is_instance_valid(bullet) or not bullet.is_inside_tree():
		return
	if get_tree() == null or get_tree().get_nodes_in_group(GROUP_PROP).size() >= MAX_PROPS:
		return
	var old = bullet.get("visual_mesh")
	if old != null and is_instance_valid(old):
		old.visible = false
	var s := maxf(bullet.scale.x, 0.01)
	var r := 0.30 / s
	var root := Node3D.new()
	root.name = "Grenade"
	root.add_to_group(GROUP_PROP)
	bullet.add_child(root)
	var body_mat := _prop_mat(color, 0.96, 1.7)
	var body := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 1.8
	sph.radial_segments = 10
	sph.rings = 6
	body.mesh = sph
	body.material_override = body_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	if kind == "puffer":
		# 河豚：一圈尖刺 + 两只眼睛
		var spike_mat := _prop_mat(color.lerp(Color.WHITE, 0.38), 0.92, 1.3)
		var spike_n := 6 if quality <= 2 else 10
		for i in range(spike_n):
			var a := TAU * float(i) / float(spike_n)
			var band := (float(i % 2) - 0.5) * 1.1
			var dv := Vector3(cos(a) * cos(band), sin(band), sin(a) * cos(band))
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = r * 0.19
			cone.height = r * 0.55
			cone.radial_segments = 5
			cone.rings = 1
			spike.mesh = cone
			spike.material_override = spike_mat
			spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			spike.position = dv * r * 1.0
			spike.look_at_from_position(dv * r * 1.0, dv * r * 2.0, Vector3.UP if absf(dv.y) < 0.95 else Vector3.RIGHT)
			root.add_child(spike)
		for i in range(2):
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = r * 0.19
			es.height = r * 0.3
			es.radial_segments = 10
			es.rings = 5
			eye.mesh = es
			eye.material_override = _prop_mat(Color(1.0, 1.0, 0.92), 0.95, 0.3)
			eye.position = Vector3((float(i) - 0.5) * r * 0.58, r * 0.36, r * 0.84)
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(eye)
	else:
		# 红莲爆弹：两道发光束带 + 四片莲瓣
		var band_mat := _prop_mat(color.lerp(Color.WHITE, 0.65), 0.92, 2.6)
		band_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		for i in range(1 if quality <= 2 else 2):
			var ring := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = r * 0.94
			tor.outer_radius = r * 1.10
			tor.rings = 16
			tor.ring_segments = 6
			ring.mesh = tor
			ring.material_override = band_mat
			ring.rotation.x = PI * 0.5 if i == 0 else 0.0
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(ring)
		var petal_mat := _prop_mat(color.lerp(Color.WHITE, 0.30), 0.88, 1.9)
		var petal_n := 3 if quality <= 2 else 4
		for i in range(petal_n):
			var a := TAU * float(i) / float(petal_n)
			var petal := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = r * 0.24
			cone.height = r * 0.52
			cone.radial_segments = 4
			cone.rings = 1
			petal.mesh = cone
			petal.material_override = petal_mat
			petal.position = Vector3(cos(a) * r * 0.86, 0.0, sin(a) * r * 0.86)
			petal.rotation.z = -a
			petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(petal)
	# 引信火花：闪烁 + 自旋
	var spark_mat := _prop_mat(Color(1.0, 0.96, 0.62), 0.96, 3.2)
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var spark := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = r * 0.24
	ss.height = r * 0.38
	ss.radial_segments = 10
	ss.rings = 5
	spark.mesh = ss
	spark.material_override = spark_mat
	spark.position = Vector3(0, r * 1.05, 0)
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spark)
	var blink := root.create_tween()
	blink.set_loops()
	blink.tween_property(spark_mat, "albedo_color:a", 0.25, 0.18)
	blink.tween_property(spark_mat, "albedo_color:a", 1.0, 0.18)
	var spin := root.create_tween()
	spin.set_loops()
	spin.tween_property(root, "rotation:y", TAU, 1.2)
	# 抛物线观感：按落点距离估算飞行时间，弹体视觉先抬升再落下（不改判定）
	var gpos = bullet.get("goal")
	var travel := 0.6
	if gpos is Vector3 and (gpos as Vector3) != Vector3.ZERO:
		travel = clampf(bullet.global_position.distance_to(gpos) / maxf(1.0, float(bullet.get("speed"))), 0.35, 1.2)
	var arc := root.create_tween()
	arc.tween_property(root, "position:y", 0.85, travel * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	arc.tween_property(root, "position:y", 0.0, travel * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if bullet.get_node_or_null("VfxTrail") == null:
		attach_trail(bullet, color, 0.34, 0.32, 8, color.lerp(Color.WHITE, 0.5))
	bullet.set_meta("grenade_col", color)
	bullet.set_meta("grenade_kind", kind)


## 手雷落地爆炸：水花（河豚）/ 红莲火（爆弹）+ 冲击环 + 贴地焦痕
func grenade_impact(pos: Vector3, color: Color, kind: String = "puffer") -> void:
	if quality <= 0 or get_tree() == null:
		return
	var p := Vector3(pos.x, 0.08, pos.z)
	if kind == "puffer":
		shockwave(p, 2.7, color, 0.42)
		cast_glow(Vector3(pos.x, 0.35, pos.z), Color(0.45, 0.9, 0.85), 1.7, 0.35)
		_burst(color, Color(0.85, 1.0, 0.95), Vector3(pos.x, 0.5, pos.z), 16, 0.7, 0.46, 4.2, Vector3.UP, 80.0, 9.0)
		_burst(Color(0.15, 0.55, 0.7), Color(0.5, 0.85, 0.9), Vector3(pos.x, 0.3, pos.z), 10, 0.95, 0.62, 1.5, Vector3.UP, 45.0, -1.4)
	else:
		shockwave(p, 3.0, color, 0.45)
		cast_glow(Vector3(pos.x, 0.4, pos.z), color, 2.1, 0.4)
		_burst(color, Color(1.0, 0.9, 0.5), Vector3(pos.x, 0.6, pos.z), 16, 0.7, 0.55, 5.2, Vector3.UP, 85.0, 8.0)
		_burst(Color(1.0, 0.35, 0.1), Color(1.0, 0.75, 0.3), Vector3(pos.x, 0.3, pos.z), 10, 0.5, 0.4, 2.6, Vector3.UP, 60.0, 3.0)
	# 贴地焦痕：圆盘渐隐
	var scorch := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var rr := 1.7 if kind == "puffer" else 2.0
	cyl.top_radius = rr
	cyl.bottom_radius = rr
	cyl.height = 0.03
	cyl.radial_segments = 24
	scorch.mesh = cyl
	scorch.position = Vector3(pos.x, 0.03, pos.z)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.18, 0.07, 0.03, 0.7) if kind != "puffer" else Color(0.06, 0.14, 0.16, 0.65)
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	scorch.material_override = smat
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_root(scorch)
	var stw := scorch.create_tween()
	stw.tween_property(smat, "albedo_color:a", 0.0, 1.3)
	stw.tween_callback(scorch.queue_free)


# ---------------- 安琪拉·炽热光辉：多层能量光束 ----------------
## 返回光束根节点（origin 为枪口世界坐标、本地 +Z 为方向）；SkillDataBase 每 tick 只更新 position
func angela_beam(origin: Vector3, dir: Vector3, length: float, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "AngelaBeam"
	root.position = origin
	root.rotation.y = atan2(dir.x, dir.z)
	root.add_to_group(GROUP_FX)
	_add_root(root)
	# 外层柔光柱
	var glow_mat := _prop_mat(Color(1.0, 0.50, 0.12), 0.30, 1.4)
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var glow := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = radius * 1.35
	gc.bottom_radius = radius * 1.35
	gc.height = length
	gc.radial_segments = 10
	glow.mesh = gc
	glow.rotation.x = PI * 0.5
	glow.position = Vector3(0, 0, length * 0.5)
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	# 白热内核
	var core_mat := _prop_mat(Color(1.0, 0.92, 0.65), 0.95, 3.4)
	core_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var core := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = radius * 0.42
	cc.bottom_radius = radius * 0.42
	cc.height = length
	cc.radial_segments = 8
	core.mesh = cc
	core.rotation.x = PI * 0.5
	core.position = Vector3(0, 0, length * 0.5)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	# 螺旋能量带：两根细长光条绕轴旋转
	var rib_mat := _prop_mat(Color(1.0, 0.74, 0.28), 0.55, 2.0)
	rib_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var spin := Node3D.new()
	root.add_child(spin)
	for i in range(1 if quality <= 2 else 2):
		var rib := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, radius * 0.55, length * 0.96)
		rib.mesh = bm
		rib.material_override = rib_mat
		rib.position = Vector3(cos(PI * float(i)) * radius * 0.62, sin(PI * float(i)) * radius * 0.62, length * 0.5)
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spin.add_child(rib)
	var stw := spin.create_tween()
	stw.set_loops()
	stw.tween_property(spin, "rotation:z", TAU, 0.55)
	# 端头：脉动光球
	var tip := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = radius * 1.15
	ts.height = radius * 2.0
	ts.radial_segments = 12
	ts.rings = 6
	tip.mesh = ts
	var tip_mat := _prop_mat(Color(1.0, 0.78, 0.38), 0.62, 2.6)
	tip_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tip.material_override = tip_mat
	tip.position = Vector3(0, 0, length)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(tip)
	var ttw := tip.create_tween()
	ttw.set_loops()
	ttw.tween_property(tip, "scale", Vector3(1.28, 1.28, 1.28), 0.16)
	ttw.tween_property(tip, "scale", Vector3.ONE, 0.16)
	# 枪口光
	var muzzle := MeshInstance3D.new()
	var ms := SphereMesh.new()
	ms.radius = radius * 0.9
	ms.height = radius * 1.7
	ms.radial_segments = 10
	ms.rings = 5
	muzzle.mesh = ms
	var mmat := _prop_mat(Color(1.0, 0.82, 0.45), 0.75, 2.8)
	mmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	muzzle.material_override = mmat
	muzzle.position = Vector3(0, 0, radius * 0.3)
	muzzle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(muzzle)
	_light(origin, Color(1.0, 0.62, 0.28), 2.6, 3.2)
	return root


## 光束/道具淡出后释放（逐材质 alpha → 0）
func fade_out(node: Node3D, dur: float = 0.3) -> void:
	if node == null or not is_instance_valid(node):
		return
	var mats: Array[StandardMaterial3D] = []
	for ch in node.get_children():
		if ch is MeshInstance3D and ch.material_override is StandardMaterial3D:
			mats.append(ch.material_override)
	for m in mats:
		var mt := node.create_tween()
		mt.tween_property(m, "albedo_color:a", 0.0, dur)
	var nt := node.create_tween()
	nt.tween_interval(dur)
	nt.tween_callback(node.queue_free)

