class_name TrainingDummy
extends Minion
## 训练营木偶：站桩、不移动不攻击，统计承伤（攻击时长/总伤害/分类型/分来源/DPS）。

const DeathRecap = preload("res://scripts/ui/DeathRecapView.gd")

var stats := {
	"active_time": 0.0, "total": 0.0, "phys": 0.0, "magic": 0.0, "true": 0.0,
	"groups": {}, "last_hit_ms": 0,
}
var _pending_skill_id := 0
var _pending_true := false
var base_armor_value := 500.0
var base_mr_value := 500.0
var _stats_label: Label3D = null


## 继承 Minion 以获得普攻/技能的统一可选中过滤；关闭兵线 AI/移动逻辑。
func _physics_process(_delta: float) -> void:
	pass


func _process(_delta: float) -> void:
	pass


func _ready() -> void:
	add_to_group("training_dummies")
	collision_layer = 1
	collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.0
	shape.height = 2.4
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	add_child(col)
	_build_visual()
	visible = true

func _build_visual() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.42, 0.24)
	mat.roughness = 0.9
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.55
	bm.bottom_radius = 0.85
	bm.height = 2.2
	body.mesh = bm
	body.position.y = 1.1
	body.material_override = mat
	add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.55
	hm.height = 1.1
	head.mesh = hm
	head.position.y = 2.45
	head.material_override = mat
	add_child(head)
	# 靶心环：醒目可瞄准
	for i in range(3):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.9 + i * 0.22
		tm.outer_radius = 1.02 + i * 0.22
		tm.rings = 24
		tm.ring_segments = 8
		ring.mesh = tm
		ring.position.y = 1.0 + i * 0.32
		ring.rotation.x = PI * 0.5
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(1.0, 0.55, 0.18, 0.75)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = rm
		add_child(ring)
	# 深色半透明背板，提升头顶统计可读性
	var plate := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4.6, 2.25)
	plate.mesh = quad
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.02, 0.035, 0.07, 0.78)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.no_depth_test = true
	plate.material_override = pm
	plate.position = Vector3(0, 3.25, 0)
	add_child(plate)
	var lab := Label3D.new()
	lab.text = "训练木偶"
	_stats_label = lab
	lab.font_size = 30
	lab.outline_size = 8
	lab.outline_modulate = Color(0.01, 0.02, 0.05, 0.95)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.0021
	lab.width = 760.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.position.y = 3.25
	lab.modulate = Color(1.0, 0.92, 0.62)
	add_child(lab)


func bar_anchor_height() -> float:
	return 3.9


func reset_stats() -> void:
	stats = {"active_time": 0.0, "total": 0.0, "phys": 0.0, "magic": 0.0, "true": 0.0,
		"groups": {}, "last_hit_ms": 0}
	_refresh_stats_label()


func _refresh_stats_label() -> void:
	if _stats_label == null or not is_instance_valid(_stats_label):
		return
	_stats_label.text = "训练木偶\n攻击 %.1fs  总伤害 %d\nDPS %.0f  物/法/真 %d/%d/%d" % [
		active_time(), int(stats.get("total", 0.0)), dps(),
		int(stats.get("phys", 0.0)), int(stats.get("magic", 0.0)), int(stats.get("true", 0.0))]


func set_resist(v: float) -> void:
	base_armor_value = maxf(0.0, v)
	base_mr_value = base_armor_value
	armor = base_armor_value
	magic_resist = base_mr_value
	base_armor = base_armor_value
	base_magic_resist = base_mr_value


func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false,
		skill_id: int = 0, pen_percent: float = 0.0, is_crit_forced: int = -1):
	_pending_skill_id = skill_id
	_pending_true = _next_damage_is_true
	super.take_damage(amount, source, is_magic, skill_id, pen_percent, is_crit_forced)


func _damage_feedback(actual: float, is_magic: bool) -> void:
	if actual > 0.0:
		var now := Time.get_ticks_msec()
		var last: int = int(stats.get("last_hit_ms", 0))
		if last > 0:
			var gap := float(now - last) / 1000.0
			# 两次伤害间隔在攻击窗口内：整段计入；超过 0.5s 则只结算上一段最后 0.5s
			if gap <= 0.5:
				stats.active_time = float(stats.get("active_time", 0.0)) + gap
			else:
				stats.active_time = float(stats.get("active_time", 0.0)) + 0.5
		stats["last_hit_ms"] = now
		stats["total"] = float(stats.get("total", 0.0)) + actual
		if _pending_true:
			stats["true"] = float(stats.get("true", 0.0)) + actual
		elif is_magic:
			stats["magic"] = float(stats.get("magic", 0.0)) + actual
		else:
			stats["phys"] = float(stats.get("phys", 0.0)) + actual
		var groups: Dictionary = stats.get("groups", {})
		var key := str(DeathRecap.skill_key(_pending_skill_id))
		groups[key] = float(groups.get(key, 0.0)) + actual
		stats["groups"] = groups
		_refresh_stats_label()
	super._damage_feedback(actual, is_magic)


## 攻击总时长：已结算段 + 当前最后一次伤害后 up to 0.5s（超过即暂停）
func active_time() -> float:
	var t: float = float(stats.get("active_time", 0.0))
	var last: int = int(stats.get("last_hit_ms", 0))
	if last > 0:
		t += minf(float(Time.get_ticks_msec() - last) / 1000.0, 0.5)
	return t


func dps() -> float:
	var t: float = active_time()
	return float(stats.get("total", 0.0)) / t if t > 0.01 else 0.0


func die(_killer = null) -> void:
	# 训练木偶不被击杀：血量归零后立即满血复位
	health = actual_max_health if actual_max_health > 0.0 else max_health
	is_dead = false
	visible = true
