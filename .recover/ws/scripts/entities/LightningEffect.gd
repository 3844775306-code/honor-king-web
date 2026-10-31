class_name LightningEffect
extends Node3D
# 闪电链视觉：两点之间的锯齿状光束 + 落点闪光，短暂存在后淡出自毁
# 用于君临/暗影君临闪电链（GameEntity.take_damage 命中时触发）

const SEGMENTS := 7        # 折线分段数
const RADIUS := 0.06       # 光束粗细
const LIFETIME := 0.3      # 默认存活时长

var total_life: float = LIFETIME
var lifetime: float = LIFETIME
var mat: StandardMaterial3D = null   # 共享材质，统一淡出


static func spawn(parent: Node, from: Vector3, to: Vector3, color: Color, lifetime: float = LIFETIME) -> void:
	var fx := LightningEffect.new()
	fx.total_life = lifetime
	fx.lifetime = lifetime
	fx._build(from, to, color)
	parent.add_child(fx)


func _build(from: Vector3, to: Vector3, color: Color):
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true

	var dir := to - from
	if dir.length() < 0.01:
		queue_free()
		return
	# 抖动方向：与路径轴垂直（路径近水平时用世界Y叉乘）
	var axis := dir.normalized()
	var jitter := axis.cross(Vector3.UP)
	if jitter.length() < 0.01:
		jitter = axis.cross(Vector3.RIGHT)
	jitter = jitter.normalized()
	var amp = clamp(dir.length() * 0.18, 0.15, 0.9)

	var pts := PackedVector3Array()
	pts.append(from)
	for i in range(1, SEGMENTS):
		var t := float(i) / float(SEGMENTS)
		var p := from + dir * t
		# 中段抖动大、两端收敛到端点
		p += jitter * (randf() * 2.0 - 1.0) * amp * (1.0 - abs(t - 0.5) * 2.0)
		pts.append(p)
	pts.append(to)
	for i in range(pts.size() - 1):
		_add_segment(pts[i], pts[i + 1])

	# 落点闪光
	var flash := MeshFactory.create_sphere(0.35, color, true, 0.8)
	flash.position = to
	flash.material_override = mat
	add_child(flash)


func _add_segment(a: Vector3, b: Vector3):
	var seg := b - a
	var length := seg.length()
	if length < 0.001:
		return
	var mi := MeshFactory.create_cylinder(RADIUS, RADIUS, length, Color.WHITE)
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	# 圆柱默认沿Y轴：旋转使 +Y 对齐分段方向
	var n := seg.normalized()
	var rot_axis := Vector3.UP.cross(n)
	if rot_axis.length() > 0.001:
		mi.rotate(rot_axis.normalized(), Vector3.UP.angle_to(n))
	add_child(mi)


func _process(delta: float):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	var a = clamp(lifetime / total_life, 0.0, 1.0)
	if mat:
		mat.albedo_color.a = a
		mat.emission_energy_multiplier = 2.5 * a
