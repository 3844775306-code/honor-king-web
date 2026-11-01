class_name WukongCloud
extends RefCounted
## 孙悟空筋斗云：脚下云团 + 拖尾 + 起落爆发（host/回放/联机可共用同一构建）
## 云团为半透明发光球簇（青白），随飞行速度前倾、上下浮动；起飞/落地各一次爆发。

const PUFFS: Array = [
	Vector3(0.0, 0.0, 0.0), Vector3(0.85, 0.02, -0.15), Vector3(-0.85, 0.02, 0.1),
	Vector3(0.45, 0.05, 0.7), Vector3(-0.5, 0.04, -0.65), Vector3(0.0, 0.08, -0.9),
	Vector3(0.0, 0.06, 0.95),
]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "WukongCloud"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.95, 1.0, 0.46)
	mat.emission_enabled = true
	mat.emission = Color(0.70, 0.90, 1.0)
	mat.emission_energy_multiplier = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(PUFFS.size()):
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var k: float = 1.0 if i == 0 else (0.72 if i < 4 else 0.56)
		sm.radius = 0.62 * k
		sm.height = 0.90 * k
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = (PUFFS[i] as Vector3) * 1.15 + Vector3(0, 0.10, 0)
		mi.scale = Vector3(1.0, 0.55, 1.0)
		root.add_child(mi)
	# 拖尾：飞行时向后飘散的云絮
	var trail := CPUParticles3D.new()
	trail.name = "Trail"
	trail.emitting = false
	trail.amount = 26
	trail.lifetime = 0.65
	trail.local_coords = false
	trail.direction = Vector3(0, 0.15, 1)
	trail.spread = 35.0
	trail.initial_velocity_min = 1.2
	trail.initial_velocity_max = 2.8
	trail.gravity = Vector3(0, 0.4, 0)
	trail.scale_amount_min = 0.18
	trail.scale_amount_max = 0.38
	trail.color = Color(0.82, 0.96, 1.0, 0.55)
	trail.position = Vector3(0.0, 0.06, 0.65)
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.albedo_color = Color(0.82, 0.96, 1.0, 0.55)
	tmat.emission_enabled = true
	tmat.emission = Color(0.72, 0.92, 1.0)
	var tmesh := SphereMesh.new()
	tmesh.radius = 0.35
	tmesh.height = 0.7
	trail.mesh = tmesh
	trail.material_override = tmat
	root.add_child(trail)
	return root


## 每帧：浮动 + 朝向 + 随速度拉长（dir 为飞行方向，speed 单位 m/s）
static func tick(root: Node3D, dir: Vector3, speed: float, t: float, flying: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	var bob := sin(t * 7.0) * 0.06 + sin(t * 13.0) * 0.02
	root.position.y = 0.16 + bob
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() > 0.01:
		root.rotation.y = atan2(flat.x, flat.z)
	var lean := clampf(speed / 12.0, 0.0, 1.0) * 0.18
	root.rotation.x = -lean
	var stretch := 1.0 + clampf(speed / 14.0, 0.0, 1.0) * 0.30
	root.scale = Vector3(1.0, 0.85 + sin(t * 9.0) * 0.06, stretch)
	var tr := root.get_node_or_null("Trail")
	if tr is CPUParticles3D:
		(tr as CPUParticles3D).emitting = flying


static func burst(pos: Vector3, color: Color = Color(0.82, 0.96, 1.0)) -> void:
	Vfx.shockwave(pos + Vector3.UP * 0.2, 2.0, color, 0.45)
	Vfx.hit_spark(pos + Vector3.UP * 0.35, color, Vector3.UP, 2.2)
	Vfx.nova(pos + Vector3.UP * 0.4, color, 1.4)
