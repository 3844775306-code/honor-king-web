# PathFinder.gd - Autoload
# A* pathfinding for entities navigating around walls on the XZ plane.
extends Node

const CELL_SIZE: float = 1.0   # must be exactly representable in binary (powers of 2)
const GRID_HALF: int = 65      # 130 cells × 1.0 = 130 units (> 120 map)
const CELL_MIN: int = -GRID_HALF
const CELL_MAX: int = GRID_HALF - 1
const TURRET_BASE_WEIGHT: float = 6.0   # 塔基附近代价：可通行但寻路优先绕行
const TURRET_DANGER_WEIGHT: float = 4.0  # 塔危险区域代价倍率：可通行但高代价，绕行距离过长时仍会穿过


var astar: AStarGrid2D
var initialized: bool = false
var _marked_turret_cells: Array = []
var _turret_base_weight: Dictionary = {}   # 塔基格 -> 基础权重（塔心可通行，但寻路优先绕开）
var last_marked_count: int = 0  # 最近一次标记的塔危险区域格数（调试输出用）



func _is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= CELL_MIN and cell.x <= CELL_MAX and cell.y >= CELL_MIN and cell.y <= CELL_MAX


func build_navigation_map() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(-GRID_HALF, -GRID_HALF, GRID_HALF * 2, GRID_HALF * 2)
	astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	astar.update()

	# Mark wall cells as solid (3×3 area around each wall)
	var walls = get_tree().get_nodes_in_group("walls")
	for wall in walls:
		if not is_instance_valid(wall):
			continue
		_mark_solid(wall.global_position.x, wall.global_position.z)


	# 塔基：不写死为不可通行（单位可走进来，由 CollisionSystem 推挤挡开），但给高权重让 A* 优先绕行
	_turret_base_weight.clear()
	for turret in get_tree().get_nodes_in_group("turrets"):
		if not is_instance_valid(turret):
			continue
		_mark_base_weight(turret.global_position.x, turret.global_position.z, 2.16)

	# Mark map edges as solid
	# 地图 120×120 之外必须整片不可通行：原来只封了 z=±60 一行，外侧 -61…-65 仍是“可通行”，
	# 单位被挤到 z=-60 后 _find_nearest_walkable 会挑到墙外的 -61 格 → A* 永远失败 → 小兵贴边卡死。
	var half = 60
	for i in range(CELL_MIN, CELL_MAX + 1):
		for j in range(CELL_MIN, CELL_MAX + 1):
			if absi(i) >= half or absi(j) >= half:
				astar.set_point_solid(Vector2i(i, j), true)


	initialized = true


# 临时将无己方小兵的敌方防御塔射程内网格标记为高代价（可通行但尽量避开）
func _mark_turret_danger_zones(team: int, from_pos: Vector3, to_pos: Vector3) -> void:
	_marked_turret_cells.clear()
	if not astar:
		return
	var tree := get_tree()
	if not tree:
		return
	# 搜索范围：起点到终点的区域内的敌塔
	var min_x := minf(from_pos.x, to_pos.x) - 15.0
	var max_x := maxf(from_pos.x, to_pos.x) + 15.0
	var min_z := minf(from_pos.z, to_pos.z) - 15.0
	var max_z := maxf(from_pos.z, to_pos.z) + 15.0
	for entity in tree.get_nodes_in_group("turrets"):
		if not (entity is Turret) or entity.health <= 0:
			continue
		if entity.team == team:
			continue
		var tpos = entity.global_position
		# 只处理路径附近的塔
		if tpos.x < min_x or tpos.x > max_x or tpos.z < min_z or tpos.z > max_z:
			continue
		# 检查是否有己方小兵：有则安全，跳过
		var has_ally_minion := false
		for ment in tree.get_nodes_in_group("minions"):
			if not (ment is Minion) or ment.health <= 0:
				continue
			if ment.team != team:
				continue
			if tpos.distance_to(ment.global_position) < entity.attack_range * 0.01 + 2.0:
				has_ally_minion = true
				break
		if has_ally_minion:
			continue
		# 标记塔射程内网格为高代价（可通行）
		var radius_cells := int(ceil(entity.attack_range * 0.01)) + 2
		var cx := int(floor(tpos.x / CELL_SIZE))
		var cz := int(floor(tpos.z / CELL_SIZE))
		for dx in range(-radius_cells, radius_cells + 1):
			for dz in range(-radius_cells, radius_cells + 1):
				if dx * dx + dz * dz > radius_cells * radius_cells:
					continue
				var cell := Vector2i(cx + dx, cz + dz)
				if not _is_in_bounds(cell):
					continue
				# 只标记原本可通行的网格，避免覆盖墙体
				if not astar.is_point_solid(cell):
					astar.set_point_weight_scale(cell, maxf(TURRET_DANGER_WEIGHT, float(_turret_base_weight.get(cell, 1.0))))
					_marked_turret_cells.append(cell)

	last_marked_count = _marked_turret_cells.size()
# 恢复临时标记的网格
func _unmark_turret_danger_zones() -> void:
	for cell in _marked_turret_cells:
		if _is_in_bounds(cell):
			astar.set_point_weight_scale(cell, float(_turret_base_weight.get(cell, 1.0)))
	_marked_turret_cells.clear()

# 塔基高权重（可通行）：避免 A* 把路径压进塔基被推挤区域，导致单位顶塔打转
func _mark_base_weight(wx: float, wz: float, radius: float) -> void:
	var cx := int(floor(wx / CELL_SIZE))
	var cz := int(floor(wz / CELL_SIZE))
	var rc := int(ceil(radius))
	for dx in range(-rc, rc + 1):
		for dz in range(-rc, rc + 1):
			if dx * dx + dz * dz > radius * radius:
				continue
			var cell := Vector2i(cx + dx, cz + dz)
			if _is_in_bounds(cell) and not astar.is_point_solid(cell):
				astar.set_point_weight_scale(cell, TURRET_BASE_WEIGHT)
				_turret_base_weight[cell] = TURRET_BASE_WEIGHT


func _mark_solid(wx: float, wz: float) -> void:
	var cx = int(floor(wx / CELL_SIZE))
	var cz = int(floor(wz / CELL_SIZE))
	# 墙周围 5×5 区域标记为不可通行（Hero body_radius=1.5 + wall=0.4 = 1.9m < 2.5m 安全距离）
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var cell = Vector2i(cx + dx, cz + dz)
			if _is_in_bounds(cell):
				astar.set_point_solid(cell, true)


func find_path(from: Vector3, to: Vector3, bias_dir: Vector3 = Vector3.ZERO, team: int = -1, attack_range: float = -1.0, attack_target: Vector3 = Vector3.ZERO) -> PackedVector3Array:
	if not initialized:
		return PackedVector3Array([to])

	# 对英雄寻路时临时将无己方小兵的敌塔危险区域标记为高代价
	if team >= 0:
		_mark_turret_danger_zones(team, from, to)


	var from_cell = _world_to_cell(from)
	var to_cell = _world_to_cell(to)

	# Clamp to grid bounds
	from_cell = from_cell.clamp(Vector2i(CELL_MIN, CELL_MIN), Vector2i(CELL_MAX, CELL_MAX))
	to_cell = to_cell.clamp(Vector2i(CELL_MIN, CELL_MIN), Vector2i(CELL_MAX, CELL_MAX))

	var to_was_solid = astar.is_point_solid(to_cell)
	var from_was_solid = astar.is_point_solid(from_cell)

	# Convert bias_dir to cell-space direction
	var bias_cell := Vector2i.ZERO
	if bias_dir.length() > 0.01:
		bias_cell = Vector2i(int(floor(bias_dir.x / CELL_SIZE)), int(floor(bias_dir.z / CELL_SIZE)))

	# If target/dest cell is solid, find nearest walkable neighbor
	if to_was_solid:
		to_cell = _find_nearest_walkable(to_cell, bias_cell)
	if from_was_solid:
		from_cell = _find_nearest_walkable(from_cell, bias_cell)

	var path_cells = astar.get_point_path(from_cell, to_cell)

	if path_cells.is_empty():
		# A*失败：目标不可达，尝试导航到最近可通行点
		var nearest_walkable := _find_nearest_walkable(to_cell, bias_cell)
		if nearest_walkable != to_cell:
			path_cells = astar.get_point_path(from_cell, nearest_walkable)
		if path_cells.is_empty():
			var alt_from := _find_nearest_walkable(from_cell, bias_cell)
			var alt_to := _find_nearest_walkable(to_cell, bias_cell)
			path_cells = astar.get_point_path(alt_from, alt_to)
		if path_cells.is_empty():
			if team >= 0:
				_unmark_turret_danger_zones()

			# A*彻底失败：返回空路径，让 _avoid_walls 使用贴墙滑行策略
			return PackedVector3Array()

	# Convert cells back to world positions
	var path_3d := PackedVector3Array()
	for cell in path_cells:
		path_3d.append(Vector3(cell.x * CELL_SIZE, 0, cell.y * CELL_SIZE))

	# 攻击型寻路：截断路径到首个进入攻击范围的点
	if attack_range > 0.0 and attack_target != Vector3.ZERO:
		var at_flat := Vector3(attack_target.x, 0, attack_target.z)
		var _from_flat := Vector3(from.x, 0, from.z)
		# 起点已在攻击范围内：属于走位移动而非接近目标，不截断（截断会得到一步都走不动的死路径）
		if _from_flat.distance_to(at_flat) > attack_range:
			var truncate_idx := -1
			for idx in range(path_3d.size()):
				var wp := path_3d[idx]
				wp.y = 0
				if wp.distance_to(at_flat) <= attack_range:
					truncate_idx = idx
					break
			if truncate_idx >= 0:
				# 保留 0..truncate_idx（含），丢弃后续点
				path_3d = path_3d.slice(0, truncate_idx + 1)

	# Replace first/last waypoint with actual positions
	if path_3d.size() > 0:
		path_3d[0] = from
		# 攻击型寻路：终点已在攻击范围内，不替换为原始目标
		if attack_range <= 0.0 or attack_target == Vector3.ZERO:
			path_3d[path_3d.size() - 1] = to

	# 恢复塔危险区域网格
	if team >= 0:
		_unmark_turret_danger_zones()
	return path_3d


## 世界坐标是否可站立（不在墙/地图边缘的实心格）
func is_walkable_world(pos: Vector3) -> bool:
	if not initialized or astar == null:
		return true
	var c := _world_to_cell(pos)
	if not _is_in_bounds(c):
		return false
	return not astar.is_point_solid(c)


## 找最近可站立的世界坐标（bias_dir 方向优先）
func nearest_walkable_world(pos: Vector3, bias_dir: Vector3 = Vector3.ZERO) -> Vector3:
	if not initialized or astar == null:
		return pos
	var bias_cell := Vector2i.ZERO
	if bias_dir.length() > 0.01:
		bias_cell = Vector2i(int(floor(bias_dir.x / CELL_SIZE)), int(floor(bias_dir.z / CELL_SIZE)))
	var c := _find_nearest_walkable(_world_to_cell(pos), bias_cell)
	return Vector3(c.x * CELL_SIZE, 0.0, c.y * CELL_SIZE)


## 实际寻路长度（用于判断“绕墙要绕多远”）
func path_length(from: Vector3, to: Vector3, team: int = -1) -> float:
	var path := find_path(from, to, Vector3.ZERO, team)
	if path.size() < 2:
		return 0.0
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


func _world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))


func _find_nearest_walkable(cell: Vector2i, bias: Vector2i = Vector2i.ZERO) -> Vector2i:
	# 优先搜索 bias 方向的格子，避免穿墙
	var best_cell := cell
	var best_score := 999999
	for radius in range(1, 6):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var nc = Vector2i(cell.x + dx, cell.y + dz)
				if not _is_in_bounds(nc):
					continue
				if astar.is_point_solid(nc):
					continue
				# 得分越低越好：距离小 + 偏向 bias 方向
				var dist = abs(dx) + abs(dz)
				var dot = nc.x * bias.x + nc.y * bias.y  # 与移动方向点积，正方向优先
				var score = dist * 2 - dot
				if score < best_score:
					best_score = score
					best_cell = nc
		if best_score < 999999:
			return best_cell
	return cell  # fallback
