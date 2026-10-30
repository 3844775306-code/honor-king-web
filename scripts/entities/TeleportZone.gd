class_name TeleportZone
extends Area3D

var duration: float = 30.0
var heroes_inside: Array = []

func _ready():
	# 视觉圆圈
	add_to_group("teleport_zones")
	var ring = MeshInstance3D.new()
	ring.mesh = CylinderMesh.new()
	ring.mesh.top_radius = 4.0
	ring.mesh.bottom_radius = 4.0
	ring.mesh.height = 0.2
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.BLUE
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.4
	ring.material_override = mat
	add_child(ring)

	var col = CollisionShape3D.new()
	col.shape = CylinderShape3D.new()
	col.shape.radius = 4.0
	col.shape.height = 5.0
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 定时销毁
	await get_tree().create_timer(duration).timeout
	queue_free()

func _on_body_entered(body):
	if body is Hero:
		heroes_inside.append(body)

func _on_body_exited(body):
	heroes_inside.erase(body)

func get_heroes_inside() -> Array:
	return heroes_inside
