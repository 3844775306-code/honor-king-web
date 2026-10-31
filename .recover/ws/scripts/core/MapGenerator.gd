# scripts/core/MapGenerator.gd (挂载到 Map 节点)
extends Node3D

func _ready():
	# 草地
	var grass = MeshInstance3D.new()
	grass.mesh = PlaneMesh.new()
	grass.mesh.size = Vector2(60, 60)
	grass.material_override = StandardMaterial3D.new()
	grass.material_override.albedo_color = Color.DARK_GREEN
	add_child(grass)

		# 对角线河道 (沿 x=z 方向，宽度 20)
	var river = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(20, sqrt(2) * 100)  # 宽20，对角线长
	river.mesh = plane
	# 旋转平面使长边对齐对角线
	river.rotation_degrees = Vector3(0, 45, 0)
	river.position = Vector3(0, 0.01, 0)
	var river_mat = StandardMaterial3D.new()
	river_mat.albedo_color = Color.DEEP_SKY_BLUE
	river_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	river_mat.albedo_color.a = 0.5
	river.material_override = river_mat
	add_child(river)
