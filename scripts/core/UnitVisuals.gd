class_name UnitVisuals
extends RefCounted
## 角色可读性（英雄 rim/接地阴影）+ 全单位受击闪白/轻压扁。
## 全部通过 material_overlay / 独立子节点实现，不改原材质与战斗逻辑。
## Host（Hero）与联机客户端（纯 Node3D 视图节点）通用，缺失属性一律容错。

const RIM_SHADER := preload("res://scripts/core/unit_rim.gdshader")
const BLOB_SHADER := preload("res://scripts/core/blob_shadow.gdshader")

const RIM_TEAM0 := Color(0.25, 0.85, 1.0)   # team 0：青
const RIM_TEAM1 := Color(1.0, 0.4, 0.32)    # team 1：红
const RIM_STRENGTH := 0.8
const HIT_TIME := 0.18
# 接地阴影贴地高度（需高于地图所有地面装饰层，见 attach_hero 内注释）
const BLOB_Y := 0.36


## 给一个单位挂上英雄视觉增强。可重复调用（已挂过则跳过）。
## unit：承载节点（Hero / 客户端视图 Node3D）；team：0/1；model_root：英雄模型根（递归找 MeshInstance3D）。
static func attach_hero(unit: Node3D, team: int, model_root: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if model_root == null or not is_instance_valid(model_root):
		return
	if unit.has_meta("_fx_rim_mats"):
		return   # 已挂载（避免重复 overlay / 重复 BlobShadow）

	# —— rim 边缘光：每个 MeshInstance3D 一份独立 ShaderMaterial 叠在 material_overlay ——
	var rim_col := RIM_TEAM1 if team == 1 else RIM_TEAM0
	var meshes: Array = []
	_collect_meshes(model_root, meshes)
	var mats: Array = []
	for m in meshes:
		if not is_instance_valid(m):
			continue
		var mat := ShaderMaterial.new()
		mat.shader = RIM_SHADER
		mat.set_shader_parameter("rim_color", rim_col)
		mat.set_shader_parameter("rim_strength", RIM_STRENGTH)
		mat.set_shader_parameter("hit", 0.0)
		mat.set_shader_parameter("hit_color", Color.WHITE)
		m.material_overlay = mat
		m.set_meta("_fx_rim", true)
		mats.append(mat)
	unit.set_meta("_fx_rim_mats", mats)

	# —— 接地软阴影：独立子节点，PlaneMesh 默认水平（法线 +Y），不再绕 X 旋转 ——
	var radius := 0.9
	if "body_radius" in unit:
		var br = unit.get("body_radius")
		if br != null and (typeof(br) == TYPE_FLOAT or typeof(br) == TYPE_INT) and float(br) > 0.0:
			radius = float(br)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var blob_mat := ShaderMaterial.new()
	blob_mat.shader = BLOB_SHADER
	blob_mat.set_shader_parameter("shadow_strength", 0.30)
	var shadow := MeshInstance3D.new()
	shadow.name = "BlobShadow"
	shadow.mesh = plane
	shadow.material_override = blob_mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# 贴地高度：地图分路面 y=0.05、高地扇形 y≈0.25、野区顶点起伏最高 y≈0.26、
	# 泉水盘 y≈0.33 —— 贴地平面必须高于所有地面装饰层，否则会被地面遮住整片阴影。
	shadow.position = Vector3(0.0, BLOB_Y, 0.0)
	shadow.scale = Vector3.ONE * (radius * 2.4)
	unit.add_child(shadow)
	unit.set_meta("_fx_blob", shadow)

	var follower := BlobFollower.new()
	follower.name = "BlobFollower"
	follower.setup(unit, shadow)
	unit.add_child(follower)


## 受击闪白：rim 材质 hit 1 → 0.18s 回 0。对无 rim 材质的实体是空操作。
static func flash(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var mats: Array = unit.get_meta("_fx_rim_mats", [])
	if mats.is_empty():
		return
	for m in mats:
		if is_instance_valid(m):
			m.set_shader_parameter("hit", 1.0)
	# 连续受击：杀掉旧 tween，重新从 1 起表（无 tween 冲突）
	if unit.has_meta("_fx_hit_tween"):
		var old = unit.get_meta("_fx_hit_tween")
		if old is Tween and old.is_valid():
			old.kill()
	if not unit.is_inside_tree():
		for m in mats:
			if is_instance_valid(m):
				m.set_shader_parameter("hit", 0.0)
		return
	var tw := unit.create_tween()
	tw.set_parallel(true)
	for m in mats:
		if is_instance_valid(m):
			tw.tween_property(m, "shader_parameter/hit", 0.0, HIT_TIME)
	unit.set_meta("_fx_hit_tween", tw)


## 非英雄受击闪光：单份 additive material_overlay，一次性淡出；不覆盖已有 overlay。
static func hit_flash(root: Node3D) -> void:
	if root == null or not is_instance_valid(root):
		return
	var mat: StandardMaterial3D = root.get_meta("_fx_hit_flash_mat", null) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.96, 0.86, 0.0)
		var meshes: Array = []
		_collect_meshes(root, meshes)
		for m in meshes:
			if is_instance_valid(m) and (m as MeshInstance3D).material_overlay == null:
				(m as MeshInstance3D).material_overlay = mat
		root.set_meta("_fx_hit_flash_mat", mat)
	mat.albedo_color = Color(1.0, 0.96, 0.86, 0.58)
	var old = root.get_meta("_fx_hit_flash_tween", null)
	if old is Tween and old.is_valid():
		old.kill()
	if not root.is_inside_tree():
		mat.albedo_color.a = 0.0
		return
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color", Color(1.0, 0.96, 0.86, 0.0), 0.16)
	root.set_meta("_fx_hit_flash_tween", tw)

## 受击轻压扁：只动可视根 scale，不碰实体位移/碰撞；WalkFeel 也不写 scale。
static func hit_pulse(root: Node3D) -> void:
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return
	var base: Vector3 = root.get_meta("_fx_hit_scale", root.scale) as Vector3
	root.set_meta("_fx_hit_scale", base)
	var old = root.get_meta("_fx_hit_pulse_tween", null)
	if old is Tween and old.is_valid():
		old.kill()
	var tw := root.create_tween()
	tw.tween_property(root, "scale", base * Vector3(1.04, 0.955, 1.04), 0.055)
	tw.tween_property(root, "scale", base, 0.13)
	root.set_meta("_fx_hit_pulse_tween", tw)

static func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


## 小兵/防御塔队伍染色：给模型递归套上按队伍色相乘的材质覆盖。
## 用材质缓存（同模型+同队共用一份），不改 GLB 原资源；ShaderMaterial（塔基融合光）跳过。
static var _tint_cache: Dictionary = {}

static func tint_team(root: Node3D, team: int, strength: float = 0.5) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root.has_meta("_fx_team_tint"):
		return
	root.set_meta("_fx_team_tint", true)
	var tint := RIM_TEAM1 if team == 1 else RIM_TEAM0
	var meshes: Array = []
	_collect_meshes(root, meshes)
	for m in meshes:
		if not is_instance_valid(m):
			continue
		# 程序化材质（防御塔石身等）：直接替换 override
		if m.material_override != null:
			var om := _tint_material(m.material_override, tint, strength)
			if om != null:
				m.material_override = om
			continue
		var mesh: Mesh = m.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var base: Material = m.get_active_material(i)
			if base == null:
				continue
			var tm := _tint_material(base, tint, strength)
			if tm != null:
				m.set_surface_override_material(i, tm)

static func _tint_material(mat: Material, tint: Color, strength: float) -> Material:
	if mat == null or not (mat is BaseMaterial3D):
		return null
	var key := "%d:%s:%.2f" % [mat.get_instance_id(), tint.to_html(), strength]
	var cached: Material = _tint_cache.get(key)
	if cached != null:
		return cached
	var dup := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
	dup.albedo_color = dup.albedo_color.lerp(tint, strength)
	# 轻微自发光：远处/阴影里也能一眼分敌我
	dup.emission_enabled = true
	dup.emission = tint * 0.10
	dup.emission_energy_multiplier = 0.6
	_tint_cache[key] = dup
	return dup


## 每帧同步接地阴影显隐：单位不可见 / 兰陵王隐身 / 阵亡 → 隐藏。
class BlobFollower extends Node3D:
	var _unit: Node3D
	var _shadow: MeshInstance3D

	func setup(unit: Node3D, shadow: MeshInstance3D) -> void:
		_unit = unit
		_shadow = shadow

	func _process(_delta: float) -> void:
		if not is_instance_valid(_unit) or not is_instance_valid(_shadow):
			queue_free()
			return
		var vis := _unit.is_inside_tree() and _unit.is_visible_in_tree()
		if vis and "is_dead" in _unit and bool(_unit.get("is_dead")):
			vis = false
		if vis and "display_name" in _unit and str(_unit.get("display_name")) == "兰陵王" \
				and "lanling_stealth_active" in _unit and bool(_unit.get("lanling_stealth_active")):
			vis = false
		_shadow.visible = vis
