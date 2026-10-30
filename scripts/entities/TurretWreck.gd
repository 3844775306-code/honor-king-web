class_name TurretWreck
extends Node3D
# 防御塔被摧毁后留下的“残骸减速带”：敌方小兵进入塔原攻击范围被大幅减速。
# slow_pct：1塔30% / 2塔60% / 高地塔90%；减速带整体只存在3秒（ZONE_LIFE），
# 期间环内敌方小兵持续减速，减速 buff 时长随剩余寿命收敛，离开环或寿命耗尽后自然消除
var team: int = Config.Team.NEUTRAL
var radius: float = 8.9
var slow_pct: float = 0.3
var tick: float = 0.0
# 减速带整体只存在 3 秒：塔倒后 ZONE_LIFE 计时结束自动消失（残骸环一并移除）
const ZONE_LIFE: float = 3.0
var life: float = ZONE_LIFE
const TICK_INTERVAL: float = 0.3
const SLOW_DURATION: float = 3.0

func _ready():
	# 残骸视觉：灰色半透明环，象征已毁塔的减速地带
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.15
	torus.outer_radius = radius + 0.15
	ring.mesh = torus
	ring.rotation_degrees = Vector3(0, 0, 0)
	ring.position = Vector3(0, 0.05, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.45, 0.5, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	add_child(ring)

func _physics_process(delta):
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	tick += delta
	if tick < TICK_INTERVAL:
		return
	tick = 0.0
	for m in get_tree().get_nodes_in_group("minions"):
		if m is Minion and m.team != team and m.health > 0:
			if global_position.distance_to(m.global_position) <= radius:
				# 单次减速持续 ≤ 剩余寿命：随减速带 3 秒终结而同步消失
				m.apply_move_pct_buff("tower_wreck", minf(SLOW_DURATION, life), -slow_pct, true)
