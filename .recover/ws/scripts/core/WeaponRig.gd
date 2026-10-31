extends Node3D
## 武器动作绑定：普攻挥砍/突刺/射击/施法抬手 + 待机轻摆。
## 由 HeroWeapons 在挂武器时创建并 setup(style)，Hero 在出手/放技能时 trigger("attack"/"cast")。

var _base_pos := Vector3.ZERO
var _base_rot := Vector3.ZERO
var _base_set := false
var _t := 1.0
var _dur := 0.26
var _kind := ""
var _style := "slash"
var _phase := 0.0
var _spin := 0.0
var _off_scale := 1.0

func _ready() -> void:
	if get_parent() is BoneAttachment3D:
		call_deferred("_snap_to_hand")

## 把武器对准手臂骨末端（手掌位置）：按模型半宽与手臂骨长度推算，抵消模型 3 倍放大
func _snap_to_hand() -> void:
	var ba := get_parent() as BoneAttachment3D
	if ba == null:
		return
	var skel := ba.get_parent() as Skeleton3D
	if skel == null:
		return
	var visual: Node3D = skel
	for i in range(6):
		if visual.get_parent() is Node3D:
			visual = visual.get_parent()
		if visual.name == "HeroModel":
			break
	var bi: int = ba.bone_idx
	if bi < 0:
		return
	var pose := skel.get_bone_global_pose(bi)
	var origin: Vector3 = skel.global_transform * pose.origin
	# 手掌位置优先用模型顶点反推（最外侧、手臂高度范围内的顶点；兼容各模型骨骼朝向差异）
	var half := _half_width(visual)
	# 手掌位置：模型侧缘 + 手臂骨高度，在英雄本地坐标系里算（随英雄朝向旋转）
	var box := _model_aabb(visual)
	var hh := maxf(box.size.y, 0.5)
	var bone_local: Vector3 = visual.global_transform.affine_inverse() * origin
	var sx := -1.0
	if absf(bone_local.x) > 0.05:
		sx = 1.0 if bone_local.x >= 0.0 else -1.0
	var hand_y := clampf(bone_local.y - hh * 0.16, hh * 0.16, hh * 0.5)
	var hand := visual.global_transform * Vector3(sx * (half - 0.06), hand_y, 0.0)
	if hand == Vector3.INF:
		# 兜底：按骨骼轴水平分量推算
		var gb := skel.global_transform.basis * pose.basis
		var arm_dir := Vector3.ZERO
		var arm_score := -1.0
		for v in [gb.x, gb.y, gb.z]:
			var hv := Vector3(v.x, 0.0, v.z)
			if hv.length() > arm_score:
				arm_score = hv.length()
				arm_dir = hv.normalized()
		var rel_h := Vector3(origin.x - visual.global_position.x, 0.0, origin.z - visual.global_position.z)
		if arm_dir.dot(rel_h) < 0.0:
			arm_dir = -arm_dir
		var arm_len := clampf(half - rel_h.length(), 0.26, 1.1)
		hand = origin + arm_dir * arm_len
	var bs := visual.global_transform.basis.orthonormalized() * Basis.from_euler(_base_rot)
	_off_scale = 1.0 / maxf(ba.global_transform.basis.get_scale().x, 0.001)
	global_transform = Transform3D(bs, hand)
	_base_pos = position
	_base_rot = rotation
	_base_set = true

## 从模型顶点反推手掌：模型最外侧、且高度在手臂范围内的顶点（同侧）
func _hand_from_meshes(visual: Node3D, side_vec: Vector3) -> Vector3:
	var box := _model_aabb(visual)
	var h := maxf(box.size.y, 0.2)
	var lo_y := visual.global_position.y + h * 0.18
	var hi_y := visual.global_position.y + h * 0.80
	var dir := side_vec.normalized() if side_vec.length() > 0.01 else Vector3.RIGHT
	var best := Vector3.INF
	var best_d := -1.0
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if self.is_ancestor_of(n):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		if arr == null or arr.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		for v in verts:
			var wp: Vector3 = xf * v
			if wp.y < lo_y or wp.y > hi_y:
				continue
			var rel := Vector3(wp.x - visual.global_position.x, 0.0, wp.z - visual.global_position.z)
			var d := rel.dot(dir)
			if d > best_d:
				best_d = d
				best = wp
	return best

func _model_aabb(visual: Node3D) -> AABB:
	var out := AABB()
	var has := false
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if self.is_ancestor_of(n):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		out = b if not has else out.merge(b)
		has = true
	return out
## 模型半宽（排除武器自身网格）
func _half_width(visual: Node3D) -> float:
	var lo := 0.0
	var hi := 0.0
	var first := true
	for n in visual.find_children("*", "MeshInstance3D", true, false):
		if self.is_ancestor_of(n):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			lo = b.position.x
			hi = b.end.x
			first = false
		else:
			lo = minf(lo, b.position.x)
			hi = maxf(hi, b.end.x)
	if first:
		return 0.9
	return maxf((hi - lo) * 0.5, 0.3)

func setup(style: String) -> void:
	_style = style
	_base_pos = position
	_base_rot = rotation
	_base_set = true

func trigger(kind: String) -> void:
	_kind = kind
	_t = 0.0
	_dur = 0.46 if kind == "cast" else 0.26
	_spin = 0.0

func _process(dt: float) -> void:
	if not _base_set:
		_base_pos = position
		_base_rot = rotation
		_base_set = true
	_phase += dt
	var off_rot := Vector3.ZERO
	var off_pos := Vector3.ZERO
	# 待机：极轻的呼吸摆动
	off_rot.z = sin(_phase * 1.7) * 0.035
	off_rot.x = sin(_phase * 1.1 + 1.0) * 0.022
	if _t < 1.0:
		_t = minf(1.0, _t + dt / maxf(_dur, 0.05))
		var k: float = sin(PI * _t)
		if _kind == "cast":
			off_rot.x -= 1.25 * k
			off_rot.z += 0.30 * k
			off_pos.y += 0.12 * k
		elif _style == "thrust":
			off_rot.x -= 0.55 * k
			off_pos.z -= 0.26 * k
		elif _style == "shoot":
			off_rot.x += 0.40 * k
			off_pos.z += 0.05 * k
		elif _style == "punch":
			off_pos.z -= 0.18 * k
			off_rot.x -= 0.35 * k
		elif _style == "spin":
			off_rot.y = TAU * _t
			off_rot.z += 0.45 * k
		else:
			off_rot.x -= 1.15 * k
			off_rot.z += 0.45 * k
	rotation = _base_rot + off_rot
	position = _base_pos + off_pos * _off_scale
