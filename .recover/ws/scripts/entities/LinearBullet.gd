class_name LinearBullet
extends Area3D

var speed: float = 50.0
var damage: float = 0.0
var team: int = 0
var source: GameEntity = null
var direction: Vector3 = Vector3.ZERO
var max_distance: float = 10.0
var traveled: float = 0.0
var is_magic: bool = false
var hit: bool = false
var slow_dur: float = 0.0   # 命中减速时长（龙息）
var slow_per: float = 0.0   # 命中减速百分比

func _ready():
	# 视觉
	var mesh = MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.mesh.radius = 0.2
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.YELLOW if is_magic else Color.WHITE
	mesh.material_override = mat

	# 碰撞
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.3
	add_child(col)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if hit: return
	var step = direction * speed * delta
	global_position += step
	traveled += step.length()
	if traveled >= max_distance:
		queue_free()

func _on_body_entered(body):
	if body is GameEntity and body.team != team and body != source:
		_on_hit(body)

func _on_hit(target: GameEntity):
	if hit: return
	hit = true
	target.take_damage(damage, source, is_magic)
	if slow_dur > 0 and target.health > 0:
		target.apply_move_pct_buff("ms_slow", slow_dur, -slow_per, true)
	queue_free()
