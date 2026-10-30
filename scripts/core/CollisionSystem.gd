# CollisionSystem.gd - Autoload
extends Node

# 墙体空间网格：避免每帧 实体 × 全部墙体（700+）全量距离检测
const WALL_CELL := 4.0

var _wall_count := -1
var _wall_pts: PackedVector3Array = PackedVector3Array()   # 墙体世界坐标（x/z 有效）
var _wall_grid: Dictionary = {}                            # Vector2i 单元格 -> PackedInt32Array 墙索引

func _cell_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / WALL_CELL)), int(floor(z / WALL_CELL)))

func _rebuild_wall_grid() -> void:
	var walls := get_tree().get_nodes_in_group("walls")
	_wall_count = walls.size()
	_wall_pts.resize(walls.size())
	_wall_grid.clear()
	for i in range(walls.size()):
		var w = walls[i]
		if not is_instance_valid(w):
			continue
		var p: Vector3 = w.global_position
		_wall_pts[i] = p
		var key := _cell_key(p.x, p.z)
		var arr: PackedInt32Array = _wall_grid.get(key, PackedInt32Array())
		arr.append(i)
		_wall_grid[key] = arr

func apply_collision_pushback(entities: Array, delta: float):
	# ---- 实体之间的碰撞推离 ----
	# 原逻辑：塔不参与、任一为英雄不参与 → 先筛出「可推动的非英雄非塔」实体，再做两两检测
	var mob: Array = []
	var mob_pos: Array = []
	var mob_rad: Array = []
	for a in entities:
		if not is_instance_valid(a) or a.health <= 0 or not a.get("can_move"): continue
		if a is Turret or a is Hero: continue
		mob.append(a)
		mob_pos.append(a.global_position)
		mob_rad.append(a.body_radius)
	var mn := mob.size()
	for i in range(mn):
		for j in range(i + 1, mn):
			var dist: float = mob_pos[i].distance_to(mob_pos[j]) - mob_rad[i] - mob_rad[j]
			if dist >= 0:
				continue
			var push_dir: Vector3 = (mob_pos[i] - mob_pos[j]).normalized()
			if push_dir.length() < 0.01:
				push_dir = Vector3.RIGHT
			var overlap: float = -dist
			var np_i: Vector3 = mob_pos[i] + push_dir * overlap * 0.4
			var np_j: Vector3 = mob_pos[j] - push_dir * overlap * 0.4
			var half: float = Config.MAP_SIZE / 2.0
			np_i.x = clampf(np_i.x, -half, half)
			np_i.z = clampf(np_i.z, -half, half)
			mob_pos[i] = np_i
			mob_pos[j] = np_j
			mob[i].global_position = np_i
			mob[j].global_position = np_j

	# ---- 实体与墙体的碰撞推离（空间网格：只查周围 3×3 格）----
	if get_tree() == null:
		return
	if _wall_count != get_tree().get_nodes_in_group("walls").size():
		_rebuild_wall_grid()
	if _wall_pts.is_empty():
		return
	var half_map: float = Config.MAP_SIZE / 2.0
	for ent in entities:
		if not is_instance_valid(ent) or ent.health <= 0 or not ent.get("can_move"): continue
		if ent.collision_layer == 0: continue   # 隐身/筋斗云等无碰撞状态不参与墙体推离
		var ep: Vector3 = ent.global_position
		var min_dist: float = ent.body_radius + 0.4
		var ck := _cell_key(ep.x, ep.z)
		for ox in range(-1, 2):
			for oz in range(-1, 2):
				var arr: PackedInt32Array = _wall_grid.get(Vector2i(ck.x + ox, ck.y + oz), PackedInt32Array())
				for idx in arr:
					var wp := _wall_pts[idx]
					var dx: float = ep.x - wp.x
					var dz: float = ep.z - wp.z
					var dist2: float = dx * dx + dz * dz
					if dist2 >= min_dist * min_dist or dist2 < 0.000001:
						continue
					var dist: float = sqrt(dist2)
					var push_x: float = dx / dist * (min_dist - dist)
					var push_z: float = dz / dist * (min_dist - dist)
					ep.x = clampf(ep.x + push_x, -half_map, half_map)
					ep.z = clampf(ep.z + push_z, -half_map, half_map)
		ent.global_position = ep
