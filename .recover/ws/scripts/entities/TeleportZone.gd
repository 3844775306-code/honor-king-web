class_name TeleportZone
extends Area3D

var duration: float = 30.0
var heroes_inside: Array = []
var _rings: Array = []
var _ring_base_y: Array = []
var _portal_t: float = 0.0

func _ready():
	add_to_group("teleport_zones")
	# 视觉：地面漩涡符文 + 三层倾斜能量环，替代旧蓝色圆柱
	var portal := MeshFactory.create_teleport_portal(4.0)
	add_child(portal)
	_rings = portal.get_meta("rings", [])
	_ring_base_y = portal.get_meta("ring_base_y", [])

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

func _process(delta: float) -> void:
	_portal_t += delta
	for i in range(_rings.size()):
		var ring: MeshInstance3D = _rings[i]
		if not is_instance_valid(ring):
			continue
		var spin := 0.55 if i == 0 else (-0.42 if i == 1 else 0.34)
		ring.rotation.y += delta * spin
		ring.position.y = float(_ring_base_y[i]) + sin(_portal_t * 1.2 + i * 1.8) * 0.06
		var s := 1.0 + 0.015 * sin(_portal_t * 1.6 + i)
		ring.scale = Vector3(s, s, s)

func _on_body_entered(body):
	if body is Hero:
		heroes_inside.append(body)

func _on_body_exited(body):
	heroes_inside.erase(body)

func get_heroes_inside() -> Array:
	return heroes_inside
