extends RefCounted
const WeaponRigScript = preload("res://scripts/core/WeaponRig.gd")
## 英雄专属武器：程序化建模（无美术资源），按英雄名给每个英雄一套独立武器造型。
## 挂载点 = 英雄模型根节点下的 Weapon 节点（按模型包围盒推算右手高度），主机与联机客户端共用。
## 设计原则：造型一眼可辨（长剑/巨剑/细剑/长枪/画戟/双匕首/折扇/法珠/法杖/重炮/双枪/炸弹/机关臂/拳套/弓/斧/弩/琵琶…），
## 尺寸按英雄身高比例缩放，避免遮挡血条或插地。

# 武器配方：type / 主色 / 副色 / 长度系数（1.0 = 标准）
const RECIPE := {
	"吕布":     {"t": "halberd", "a": Color(0.85, 0.62, 0.18), "b": Color(0.45, 0.30, 0.10), "l": 1.15},
	"亚瑟":     {"t": "greatsword", "a": Color(0.78, 0.84, 0.92), "b": Color(0.35, 0.45, 0.62), "l": 1.0},
	"马超":     {"t": "spear", "a": Color(0.85, 0.88, 0.95), "b": Color(0.55, 0.35, 0.22), "l": 1.2},
	"铠":       {"t": "greatsword", "a": Color(0.72, 0.20, 0.20), "b": Color(0.20, 0.06, 0.08), "l": 1.05},
	"不知火舞": {"t": "fan", "a": Color(0.92, 0.22, 0.30), "b": Color(0.30, 0.05, 0.08), "l": 0.8},
	"甄姬":     {"t": "orb", "a": Color(0.45, 0.80, 1.0), "b": Color(0.10, 0.35, 0.65), "l": 0.9},
	"狄仁杰":   {"t": "pistol", "a": Color(0.90, 0.76, 0.30), "b": Color(0.25, 0.20, 0.12), "l": 0.7},
	"太乙真人": {"t": "staff", "a": Color(0.35, 0.92, 0.66), "b": Color(0.12, 0.30, 0.22), "l": 1.0},
	"东皇太一": {"t": "orb", "a": Color(0.68, 0.38, 1.0), "b": Color(0.16, 0.08, 0.30), "l": 1.0},
	"李白":     {"t": "jian", "a": Color(0.80, 0.94, 1.0), "b": Color(0.20, 0.45, 0.55), "l": 1.0},
	"兰陵王":   {"t": "daggers", "a": Color(0.70, 0.48, 0.98), "b": Color(0.18, 0.10, 0.30), "l": 0.75},
	"孙尚香":   {"t": "cannon", "a": Color(1.0, 0.55, 0.22), "b": Color(0.32, 0.20, 0.12), "l": 0.9},
	"马可波罗": {"t": "pistols", "a": Color(0.92, 0.78, 0.32), "b": Color(0.28, 0.24, 0.16), "l": 0.75},
	"张飞":     {"t": "spear", "a": Color(0.90, 0.26, 0.22), "b": Color(0.30, 0.10, 0.10), "l": 1.25},
	"沈梦溪":   {"t": "bomb", "a": Color(1.0, 0.58, 0.18), "b": Color(0.25, 0.22, 0.18), "l": 0.8},
	"刘禅":     {"t": "mecharm", "a": Color(0.78, 0.55, 0.28), "b": Color(0.30, 0.22, 0.14), "l": 0.95},
	"孙悟空":   {"t": "staff", "a": Color(0.95, 0.78, 0.28), "b": Color(0.55, 0.16, 0.12), "l": 1.25},
	"英睿":     {"t": "gauntlet", "a": Color(0.88, 0.92, 1.0), "b": Color(0.28, 0.34, 0.45), "l": 0.8},
	"安琪拉":   {"t": "staff", "a": Color(1.0, 0.50, 0.22), "b": Color(0.35, 0.12, 0.05), "l": 0.95},
	"妲己":     {"t": "staff", "a": Color(1.0, 0.55, 0.85), "b": Color(0.40, 0.10, 0.30), "l": 0.9},
	"王昭君":   {"t": "staff", "a": Color(0.55, 0.86, 1.0), "b": Color(0.20, 0.40, 0.60), "l": 0.95},
	"小乔":     {"t": "fan", "a": Color(1.0, 0.62, 0.85), "b": Color(0.35, 0.12, 0.28), "l": 0.75},
	"后羿":     {"t": "bow", "a": Color(0.92, 0.62, 0.22), "b": Color(0.55, 0.20, 0.12), "l": 1.0},
	"大禹":     {"t": "axe", "a": Color(0.55, 0.68, 0.62), "b": Color(0.30, 0.24, 0.18), "l": 1.05},
	"李元芳":   {"t": "crossbow", "a": Color(0.95, 0.82, 0.30), "b": Color(0.35, 0.26, 0.12), "l": 0.8},
	"元流之子": {"t": "jian", "a": Color(0.45, 1.0, 0.95), "b": Color(0.10, 0.35, 0.45), "l": 1.0},
	"杨玉环":   {"t": "lute", "a": Color(0.95, 0.62, 0.80), "b": Color(0.40, 0.18, 0.25), "l": 0.85},
}

# 近战英雄普攻距离(米)，随武器长度体现：与 BattleManager.hero_configs 对齐，
# 联机客户端拿不到 config 时用它算武器长度（主机直接传真实 attack_range*0.01）
const HERO_REACH := {
	"吕布": 4.75, "夏侯惇": 4.75,
	"亚瑟": 3.25, "马超": 3.25, "铠": 3.25, "不知火舞": 3.25, "李白": 3.25,
	"兰陵王": 3.25, "张飞": 3.25, "刘禅": 3.25, "孙悟空": 3.25, "英睿": 3.25,
	"大禹": 3.5, "太乙真人": 3.5,
}

# ---------------- 轮椅英雄模型合成 ----------------
# 原先这三个英雄直接拿轮椅 glb 当本体（只看得见一把椅子）。改为：角色本体（含骨骼动画）+ 座椅道具，
# 本体按「髋部落在座面」的实测偏移上抬，并把非轮椅类动画全部替换成坐姿（站位动画会让本体浮在半空）。
# 偏移/坐姿数据来自 GLB 实测：座面 y≈0.2026、wheelchair-sit 髋部 y≈0.0263（模型单位）。
const WHEELCHAIR_BODY := {
	"狄仁杰": "res://model/hero/character-male-c.glb",
	"马可波罗": "res://model/hero/character-male-d.glb",
	"太乙真人": "res://model/hero/character-male-f.glb",
}
const WHEELCHAIR_PROP := {
	"狄仁杰": "res://model/hero/wheelchair.glb",
	"马可波罗": "res://model/hero/wheelchair-power.glb",
	"太乙真人": "res://model/hero/wheelchair-deluxe.glb",
}
const WC_SEAT_LIFT := 0.1763   # 本体上抬量（模型单位，乘模型放大倍数）
const WC_SEAT_Z := -0.045      # 本体后移量：髋部对准座面中心
# 动画替换：站立类 → 坐姿类（含死亡，避免本体从座面「站起来又摔倒」）
const WC_ANIM_MAP := {
	"walk": "wheelchair-move-forward",
	"sprint": "wheelchair-move-forward",
	"drive": "wheelchair-move-forward",
}
const WC_ANIM_SIT := "wheelchair-sit"

static func is_wheelchair_hero(hero_name: String) -> bool:
	return WHEELCHAIR_PROP.has(hero_name)

# root：模型根（未放大）；body：角色本体实例（已按 s 放大）；s：本体放大倍数
static func mount_wheelchair(root: Node3D, body: Node3D, hero_name: String, s: float) -> void:
	if root == null or body == null or not is_instance_valid(body):
		return
	var path := str(WHEELCHAIR_PROP.get(hero_name, ""))
	if path == "":
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var chair: Node3D = packed.instantiate()
	chair.name = "Wheelchair"
	chair.scale = Vector3.ONE * s
	root.add_child(chair)
	body.position = Vector3(0.0, WC_SEAT_LIFT * s, WC_SEAT_Z * s)
	force_seated_anims(_find_ap(body))

# 把本体 AnimationPlayer 里所有站立/攻击类 clip 换成坐姿 clip（保留原时长），
# 让 idle/walk/attack/die 等既有调用点都自然呈现「坐在轮椅上」的姿态。
static func force_seated_anims(ap: AnimationPlayer) -> void:
	if ap == null or not is_instance_valid(ap):
		return
	# glb 动画在默认动画库里（AnimationPlayer 本身没有 remove/add，得走 AnimationLibrary）
	var lib: AnimationLibrary = ap.get_animation_library(&"")
	if lib == null:
		var libs := ap.get_animation_library_list()
		if libs.is_empty():
			return
		lib = ap.get_animation_library(libs[0])
	if lib == null:
		return
	var seat: Animation = lib.get_animation(WC_ANIM_SIT)
	if seat == null:
		seat = lib.get_animation("sit")
	if seat == null:
		return
	var names: Array = []
	for nm in lib.get_animation_list():
		names.append(str(nm))
	for key in names:
		if key.begins_with("wheelchair"):
			continue
		var src: Animation = seat
		var mapped := str(WC_ANIM_MAP.get(key, ""))
		if mapped != "" and lib.has_animation(mapped):
			src = lib.get_animation(mapped)
		var old: Animation = lib.get_animation(key)
		var old_len := old.length if old != null else 0.25
		var dup: Animation = src.duplicate()
		dup.length = maxf(old_len, 0.05)   # 保留原 clip 时长：死亡延迟/动作窗按长度计算
		lib.remove_animation(key)
		lib.add_animation(key, dup)

static func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r != null:
			return r
	return null

static func attach(instance: Node3D, hero_name: String, reach_m: float = -1.0) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	if instance.has_meta("_hero_weapon"):
		return
	instance.set_meta("_hero_weapon", true)
	var parent: Node3D = instance.get_parent() if instance.get_parent() is Node3D else instance
	# 英雄模型统一放大 3 倍、实际身高约 2.1m：武器按固定身高比例建模（构建期模型还没进树，包围盒不可靠）
	var h := 2.1
	var s: float = h / 1.8
	var rp: Dictionary = RECIPE.get(hero_name, {"t": "jian", "a": Color(0.85, 0.88, 0.95),
		"b": Color(0.3, 0.35, 0.45), "l": 1.0})
	var holder: Node3D = WeaponRigScript.new()
	holder.name = "Weapon"
	var node := _build(str(rp["t"]), rp["a"], rp["b"], s * float(rp["l"]))
	# 长兵器按普攻距离加长：武器越长，普攻够得着的距离越远（握把在原点，只沿武器长轴拉伸）
	if reach_m <= 0.0:
		reach_m = float(HERO_REACH.get(hero_name, 0.0))
	if reach_m > 0.0:
		var top := _local_top(node)
		if top > 0.35:
			var want := clampf(reach_m - 1.25, 0.9, 6.5)
			var mult := clampf(want / top, 1.0, 2.2)
			node.scale = Vector3(1.0, mult, 1.0)
			node.set_meta("reach_scale", mult)
	holder.add_child(node)
	# 优先绑到手臂骨（握在手中，随手臂动画摆动）
	var skel := _find_skeleton(instance)
	var bone: int = -1
	if skel != null:
		bone = skel.find_bone("arm-right")
		if bone < 0:
			bone = skel.find_bone("arm-left")
	if skel != null and bone >= 0 and instance.get_parent() != null and str(instance.get_parent().name) == "HeroModel":
		var ba := BoneAttachment3D.new()
		ba.name = "WeaponHand"
		ba.bone_idx = bone
		skel.add_child(ba)
		ba.add_child(holder)
		holder.scale = Vector3.ONE / maxf(instance.scale.x, 0.001)
		holder.rotation_degrees = _hold_rot(str(rp["t"]))
		holder.setup(_style_of(str(rp["t"])))
		parent.set_meta("weapon_rig", holder)
		return
	# 兜底：无骨骼模型按固定握持点挂（右手侧、腰胸之间）
	var grip := Vector3(h * 0.14, h * 0.55, h * 0.05)
	var hp: Node3D = parent
	if hp == instance:
		# 模型还没挂进场景（联机端先造模型后归位）：挂在模型下并抵消模型放大
		var inv: float = 1.0 / maxf(maxf(instance.scale.x, instance.scale.y), 0.001)
		holder.scale = Vector3.ONE * inv
		hp.add_child(holder)
		holder.position = grip * inv
	else:
		hp.add_child(holder)
		holder.position = grip
	holder.rotation_degrees = _hold_rot(str(rp["t"]))
	holder.setup(_style_of(str(rp["t"])))
	parent.set_meta("weapon_rig", holder)

## 马超落地标枪：主机与联机共用的地面标记（枪身+枪头+团队色枪缨+地面光环）。
## 返回根节点带 mats 元数据，联机 FX 淡出时可直接复用。
static func spear_marker(team: int) -> Node3D:
	var root := Node3D.new()
	root.name = "MachaoSpear"
	var accent := Color(1.0, 0.42, 0.24) if team == 1 else Color(0.32, 0.82, 1.0)
	var spear := _build("spear", Color(0.88, 0.93, 1.0), Color(0.30, 0.20, 0.13), 1.35)
	spear.rotation_degrees = Vector3(-4.0, 0.0, 7.0)
	root.add_child(spear)
	# 地面团队色光环：远看也能认出是马超的枪
	var ring := MeshInstance3D.new()
	ring.mesh = _torus(0.30, 0.46)
	ring.rotation.x = PI * 0.5
	ring.position.y = 0.05
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.albedo_color = Color(accent.r, accent.g, accent.b, 0.55)
	rmat.emission_enabled = true
	rmat.emission = accent
	rmat.emission_energy_multiplier = 1.4
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# 枪缨：三缕短飘带，避免像一根光秃秃的棍子
	for i in range(3):
		_add(root, _box(Vector3(0.030, 0.30, 0.015)), _mat(accent, 0.1, 0.55, 1.0),
			Vector3(-0.058 + 0.058 * float(i), 1.50, 0.03), Vector3(0, 0, -24.0 + 24.0 * float(i)))
	var mats: Array = []
	_collect_mats(root, mats)
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm != null:
			sm.set_meta("base_a", sm.albedo_color.a)
	root.set_meta("mats", mats)
	return root

static func _collect_mats(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is StandardMaterial3D:
		out.append((node as MeshInstance3D).material_override)
	for c in node.get_children():
		_collect_mats(c, out)


# 武器从握把(原点)沿 +Y 的最远长度（构建单位≈米），用于按普攻距离决定加长倍率
static func _local_top(node: Node, xf: Transform3D = Transform3D.IDENTITY) -> float:
	var top := 0.0
	if node is Node3D:
		xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
		top = maxf(top, box.end.y)
	for c in node.get_children():
		top = maxf(top, _local_top(c, xf))
	return top

static func _style_of(t: String) -> String:
	match t:
		"spear", "halberd":
			return "thrust"
		"cannon", "pistol", "pistols", "crossbow", "bow":
			return "shoot"
		"orb", "lute", "bomb", "staff":
			return "cast"
		"gauntlet", "mecharm":
			return "punch"
		"fan":
			return "spin"
	return "slash"

## 由 Hero 调用：node = 英雄模型根（visual_mesh）或模型实例
static func play(node: Node, kind: String) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rig = node.get_meta("weapon_rig", null)
	if rig == null:
		rig = node.find_child("Weapon", true, false)
	if rig != null and rig.has_method("trigger"):
		rig.trigger(kind)

static func _hold_rot(t: String) -> Vector3:
	match t:
		"spear", "halberd", "staff", "jian", "greatsword":
			return Vector3(14.0, 0.0, -16.0)
		"bow", "crossbow":
			return Vector3(0.0, 0.0, -8.0)
		"cannon", "pistol", "pistols":
			return Vector3(-8.0, 0.0, 6.0)
		"orb":
			return Vector3(0.0, 0.0, 10.0)
		"fan", "bomb", "gauntlet", "mecharm", "lute":
			return Vector3(0.0, 0.0, -6.0)
		"daggers":
			return Vector3(10.0, 0.0, -10.0)
		"axe":
			return Vector3(6.0, 0.0, -14.0)
	return Vector3.ZERO

static func _find_skeleton(root: Node) -> Skeleton3D:
	var stack: Array = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

static func _world_aabb(root: Node3D) -> AABB:
	# 逐级累乘相对变换（模型构建时可能还没进场景树，不能用 global_transform）
	var out := AABB()
	var has := false
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while stack.size() > 0:
		var pair: Array = stack.pop_back()
		var n: Node3D = pair[0]
		var xf: Transform3D = pair[1]
		if n is MeshInstance3D and n.mesh != null:
			var box: AABB = xf * n.get_aabb()
			out = box if not has else out.merge(box)
			has = true
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	if not has:
		return AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
	return out

# ---------------- 建模基础 ----------------
static func _mat(col: Color, metallic: float = 0.7, rough: float = 0.35, emis: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	return m

static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _cyl(top: float, bottom: float, height: float, segs: int = 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segs
	return m

static func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if h > 0.0 else r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return m

static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 16
	m.ring_segments = 6
	return m

static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m

static func _tip(size: Vector3) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = size.x * 0.5
	m.height = size.y
	m.radial_segments = 8
	return m

# ---------------- 各武器造型 ----------------
static func _build(t: String, a: Color, b: Color, s: float) -> Node3D:
	var n := Node3D.new()
	n.name = "WeaponMesh"
	var ma := _mat(a, 0.78, 0.30)
	var mb := _mat(b, 0.35, 0.65)
	var gold := _mat(Color(0.95, 0.78, 0.32), 0.85, 0.25)
	match t:
		"sword":
			_add(n, _cyl(0.030 * s, 0.034 * s, 0.22 * s), mb, Vector3(0, 0.11 * s, 0))
			_add(n, _sphere(0.045 * s), gold, Vector3(0, 0, 0))
			_add(n, _box(Vector3(0.26 * s, 0.045 * s, 0.055 * s)), gold, Vector3(0, 0.23 * s, 0))
			_add(n, _box(Vector3(0.085 * s, 0.80 * s, 0.028 * s)), ma, Vector3(0, 0.66 * s, 0))
			_add(n, _tip(Vector3(0.085 * s, 0.14 * s, 0)), ma, Vector3(0, 1.12 * s, 0))
		"greatsword":
			_add(n, _cyl(0.036 * s, 0.040 * s, 0.30 * s), mb, Vector3(0, 0.15 * s, 0))
			_add(n, _sphere(0.06 * s), gold, Vector3(0, -0.01 * s, 0))
			_add(n, _box(Vector3(0.40 * s, 0.07 * s, 0.08 * s)), gold, Vector3(0, 0.31 * s, 0))
			_add(n, _box(Vector3(0.20 * s, 1.05 * s, 0.05 * s)), ma, Vector3(0, 0.84 * s, 0))
			_add(n, _box(Vector3(0.055 * s, 1.02 * s, 0.062 * s)), mb, Vector3(0, 0.84 * s, 0))
			_add(n, _tip(Vector3(0.20 * s, 0.22 * s, 0)), ma, Vector3(0, 1.44 * s, 0))
		"jian":
			_add(n, _cyl(0.026 * s, 0.030 * s, 0.20 * s), mb, Vector3(0, 0.10 * s, 0))
			_add(n, _torus(0.045 * s, 0.075 * s), gold, Vector3(0, 0.21 * s, 0), Vector3(90, 0, 0))
			_add(n, _box(Vector3(0.055 * s, 0.92 * s, 0.020 * s)), ma, Vector3(0, 0.68 * s, 0))
			_add(n, _tip(Vector3(0.055 * s, 0.16 * s, 0)), ma, Vector3(0, 1.20 * s, 0))
			_add(n, _box(Vector3(0.03 * s, 0.16 * s, 0.012 * s)), _mat(a, 0.2, 0.5, 0.6), Vector3(0, -0.04 * s, 0))
		"spear":
			_add(n, _cyl(0.030 * s, 0.038 * s, 1.62 * s), mb, Vector3(0, 0.81 * s, 0))
			_add(n, _tip(Vector3(0.055 * s, 0.10 * s, 0)), ma, Vector3(0, 0.02 * s, 0), Vector3(180, 0, 0))
			_add(n, _torus(0.038 * s, 0.062 * s), gold, Vector3(0, 1.44 * s, 0), Vector3(90, 0, 0))
			_add(n, _torus(0.034 * s, 0.055 * s), gold, Vector3(0, 1.51 * s, 0), Vector3(90, 0, 0))
			_add(n, _tip(Vector3(0.11 * s, 0.38 * s, 0)), ma, Vector3(0, 1.74 * s, 0))
			_add(n, _box(Vector3(0.016 * s, 0.30 * s, 0.018 * s)), _mat(a.lightened(0.25), 0.2, 0.3),
				Vector3(0, 1.73 * s, 0.012 * s))
			for i in range(2):
				_add(n, _box(Vector3(0.095 * s, 0.12 * s, 0.016 * s)), ma,
					Vector3((float(i) - 0.5) * 0.16 * s, 1.55 * s, 0.0), Vector3(0, 0, -28.0 + 56.0 * float(i)))
			for i in range(3):
				_add(n, _box(Vector3(0.022 * s, 0.28 * s, 0.013 * s)), _mat(a, 0.2, 0.5),
					Vector3(-0.055 * s + 0.055 * s * float(i), 1.36 * s, 0.02 * s), Vector3(0, 0, -18.0 + 18.0 * float(i)))
		"halberd":
			_add(n, _cyl(0.030 * s, 0.036 * s, 1.50 * s), mb, Vector3(0, 0.75 * s, 0))
			_add(n, _box(Vector3(0.09 * s, 0.60 * s, 0.032 * s)), ma, Vector3(0, 1.58 * s, 0))
			_add(n, _tip(Vector3(0.09 * s, 0.18 * s, 0)), ma, Vector3(0, 1.92 * s, 0))
			_add(n, _prism(Vector3(0.14 * s, 0.44 * s, 0.03 * s)), ma, Vector3(0.20 * s, 1.68 * s, 0), Vector3(0, 0, 90))
			_add(n, _sphere(0.05 * s), gold, Vector3(0, 1.40 * s, 0))
			_add(n, _tip(Vector3(0.07 * s, 0.16 * s, 0)), ma, Vector3(0, 0.06 * s, 0), Vector3(180, 0, 0))
		"daggers":
			for side in [-1.0, 1.0]:
				var ox: float = 0.11 * s * float(side)
				_add(n, _cyl(0.020 * s, 0.024 * s, 0.16 * s), mb, Vector3(ox, 0.08 * s, 0))
				_add(n, _box(Vector3(0.075 * s, 0.34 * s, 0.018 * s)), ma, Vector3(ox, 0.32 * s, 0), Vector3(0, 0, 6.0 * float(side)))
				_add(n, _tip(Vector3(0.075 * s, 0.12 * s, 0)), ma, Vector3(ox, 0.55 * s, 0), Vector3(0, 0, 6.0 * float(side)))
		"fan":
			_add(n, _cyl(0.022 * s, 0.026 * s, 0.20 * s), mb, Vector3(0, 0.10 * s, 0))
			var pivot := Node3D.new()
			pivot.position = Vector3(0, 0.20 * s, 0)
			n.add_child(pivot)
			for i in range(7):
				var ang: float = -54.0 + 18.0 * float(i)
				var rib := Node3D.new()
				rib.rotation_degrees = Vector3(0, 0, ang)
				pivot.add_child(rib)
				_add(rib, _box(Vector3(0.018 * s, 0.46 * s, 0.012 * s)), ma, Vector3(0, 0.23 * s, 0))
				_add(rib, _box(Vector3(0.062 * s, 0.30 * s, 0.008 * s)), _mat(a.lightened(0.25), 0.2, 0.7),
					Vector3(0, 0.34 * s, 0))
			_add(n, _sphere(0.036 * s), gold, Vector3(0, 0.20 * s, 0))
		"orb":
			_add(n, _cyl(0.10 * s, 0.12 * s, 0.06 * s), mb, Vector3(0, 0.03 * s, 0))
			_add(n, _cyl(0.022 * s, 0.026 * s, 0.26 * s), mb, Vector3(0, 0.18 * s, 0))
			_add(n, _sphere(0.20 * s), _mat(a, 0.1, 0.25, 1.1), Vector3(0, 0.52 * s, 0))
			_add(n, _torus(0.22 * s, 0.26 * s), _mat(a.lightened(0.3), 0.4, 0.3, 0.5), Vector3(0, 0.52 * s, 0), Vector3(70, 20, 0))
			_add(n, _torus(0.24 * s, 0.27 * s), _mat(a.lightened(0.2), 0.4, 0.3, 0.4), Vector3(0, 0.52 * s, 0), Vector3(20, 70, 0))
			for i in range(3):
				var aa: float = TAU * float(i) / 3.0
				_add(n, _sphere(0.045 * s), _mat(a, 0.2, 0.4, 0.7),
					Vector3(cos(aa) * 0.30 * s, 0.52 * s + sin(aa) * 0.22 * s, sin(aa) * 0.10 * s))
		"staff":
			_add(n, _cyl(0.030 * s, 0.036 * s, 1.45 * s), mb, Vector3(0, 0.72 * s, 0))
			_add(n, _torus(0.10 * s, 0.14 * s), gold, Vector3(0, 1.50 * s, 0), Vector3(90, 0, 0))
			_add(n, _sphere(0.115 * s), _mat(a, 0.15, 0.25, 1.2), Vector3(0, 1.52 * s, 0))
			for i in range(3):
				var ang2: float = TAU * float(i) / 3.0 + 0.5
				_add(n, _box(Vector3(0.022 * s, 0.20 * s, 0.018 * s)), gold,
					Vector3(cos(ang2) * 0.20 * s, 1.62 * s, sin(ang2) * 0.20 * s), Vector3(0, 0, 24.0))
			_add(n, _sphere(0.05 * s), gold, Vector3(0, -0.01 * s, 0))
		"cannon":
			_add(n, _box(Vector3(0.16 * s, 0.20 * s, 0.30 * s)), mb, Vector3(0, 0.16 * s, -0.06 * s))
			_add(n, _cyl(0.105 * s, 0.125 * s, 0.78 * s), ma, Vector3(0, 0.30 * s, 0.16 * s), Vector3(90, 0, 0))
			_add(n, _torus(0.10 * s, 0.14 * s), gold, Vector3(0, 0.30 * s, 0.55 * s), Vector3(90, 0, 0))
			_add(n, _torus(0.13 * s, 0.17 * s), mb, Vector3(0, 0.16 * s, -0.02 * s), Vector3(90, 0, 0))
			_add(n, _sphere(0.055 * s), _mat(a, 0.2, 0.3, 0.9), Vector3(0, 0.30 * s, 0.58 * s))
			_add(n, _box(Vector3(0.10 * s, 0.16 * s, 0.10 * s)), mb, Vector3(0, 0.05 * s, -0.10 * s))
		"pistol", "pistols":
			var count: int = 2 if t == "pistols" else 1
			for i in range(count):
				var ox2: float = (0.0 if count == 1 else (-0.10 * s + 0.20 * s * float(i)))
				_add(n, _box(Vector3(0.075 * s, 0.11 * s, 0.26 * s)), mb, Vector3(ox2, 0.18 * s, 0.05 * s))
				_add(n, _cyl(0.040 * s, 0.046 * s, 0.30 * s), ma, Vector3(ox2, 0.20 * s, 0.26 * s), Vector3(90, 0, 0))
				_add(n, _torus(0.042 * s, 0.056 * s), gold, Vector3(ox2, 0.20 * s, 0.40 * s), Vector3(90, 0, 0))
				_add(n, _box(Vector3(0.055 * s, 0.16 * s, 0.07 * s)), ma, Vector3(ox2, 0.09 * s, -0.05 * s), Vector3(-16, 0, 0))
				_add(n, _sphere(0.022 * s), _mat(a, 0.2, 0.3, 1.0), Vector3(ox2, 0.20 * s, 0.42 * s))
		"bomb":
			_add(n, _sphere(0.20 * s), _mat(b, 0.5, 0.45), Vector3(0, 0.28 * s, 0))
			_add(n, _torus(0.19 * s, 0.22 * s), gold, Vector3(0, 0.28 * s, 0), Vector3(90, 0, 0))
			_add(n, _cyl(0.012 * s, 0.014 * s, 0.16 * s), mb, Vector3(0, 0.50 * s, 0))
			_add(n, _sphere(0.045 * s), _mat(Color(1.0, 0.85, 0.3), 0.1, 0.2, 1.5), Vector3(0, 0.60 * s, 0))
			_add(n, _cyl(0.03 * s, 0.03 * s, 0.10 * s), gold, Vector3(0, 0.42 * s, 0))
		"mecharm":
			_add(n, _box(Vector3(0.17 * s, 0.34 * s, 0.17 * s)), mb, Vector3(0, 0.24 * s, 0))
			_add(n, _cyl(0.05 * s, 0.06 * s, 0.30 * s), ma, Vector3(0.11 * s, 0.24 * s, 0), Vector3(0, 0, 90))
			_add(n, _box(Vector3(0.20 * s, 0.16 * s, 0.20 * s)), ma, Vector3(0, 0.48 * s, 0))
			_add(n, _box(Vector3(0.06 * s, 0.05 * s, 0.22 * s)), _mat(a, 0.2, 0.3, 0.9), Vector3(0, 0.33 * s, 0.10 * s))
			for i in range(3):
				_add(n, _prism(Vector3(0.05 * s, 0.09 * s, 0.04 * s)), gold,
					Vector3(-0.07 * s + 0.07 * s * float(i), 0.57 * s, 0.06 * s))
		"gauntlet":
			_add(n, _box(Vector3(0.15 * s, 0.22 * s, 0.15 * s)), mb, Vector3(0, 0.16 * s, 0))
			_add(n, _box(Vector3(0.17 * s, 0.10 * s, 0.12 * s)), ma, Vector3(0, 0.30 * s, 0.02 * s))
			for i in range(4):
				_add(n, _prism(Vector3(0.035 * s, 0.10 * s, 0.03 * s)), ma,
					Vector3(-0.06 * s + 0.04 * s * float(i), 0.38 * s, 0.04 * s))
			_add(n, _box(Vector3(0.10 * s, 0.03 * s, 0.10 * s)), _mat(a, 0.2, 0.3, 0.8), Vector3(0, 0.24 * s, 0.07 * s))
		"bow":
			for i in range(7):
				var t2: float = -1.0 + 2.0 * float(i) / 6.0
				var y2: float = 0.16 * s + (t2 * 0.52 * s)
				var xoff: float = -0.12 * s * (1.0 - t2 * t2)
				_add(n, _box(Vector3(0.035 * s, 0.20 * s, 0.028 * s)), _mat(a, 0.5, 0.4),
					Vector3(xoff, y2, 0), Vector3(0, 0, -36.0 * t2))
			_add(n, _box(Vector3(0.010 * s, 1.02 * s, 0.008 * s)), _mat(Color(0.9, 0.92, 1.0), 0.1, 0.6),
				Vector3(-0.20 * s, 0.16 * s + 0.0, 0))
			_add(n, _cyl(0.030 * s, 0.034 * s, 0.20 * s), mb, Vector3(0, 0.16 * s, 0))
			_add(n, _torus(0.045 * s, 0.070 * s), gold, Vector3(0, 0.16 * s, 0), Vector3(90, 0, 0))
		"axe":
			_add(n, _cyl(0.032 * s, 0.038 * s, 1.05 * s), mb, Vector3(0, 0.52 * s, 0))
			_add(n, _prism(Vector3(0.20 * s, 0.46 * s, 0.035 * s)), ma, Vector3(0.20 * s, 1.02 * s, 0), Vector3(0, 0, 90))
			_add(n, _prism(Vector3(0.12 * s, 0.26 * s, 0.03 * s)), ma, Vector3(-0.14 * s, 1.02 * s, 0), Vector3(0, 0, -90))
			_add(n, _torus(0.045 * s, 0.070 * s), gold, Vector3(0, 0.94 * s, 0), Vector3(90, 0, 0))
		"crossbow":
			_add(n, _box(Vector3(0.08 * s, 0.60 * s, 0.10 * s)), mb, Vector3(0, 0.30 * s, 0))
			for side2 in [-1.0, 1.0]:
				_add(n, _box(Vector3(0.032 * s, 0.34 * s, 0.026 * s)), ma,
					Vector3(0.16 * s * float(side2), 0.52 * s, 0), Vector3(0, 0, 52.0 * float(side2)))
			_add(n, _box(Vector3(0.42 * s, 0.008 * s, 0.008 * s)), _mat(Color(0.92, 0.94, 1.0), 0.1, 0.6), Vector3(0, 0.66 * s, 0))
			_add(n, _cyl(0.026 * s, 0.030 * s, 0.10 * s), gold, Vector3(0, 0.10 * s, 0), Vector3(90, 0, 0))
			_add(n, _tip(Vector3(0.045 * s, 0.16 * s, 0)), ma, Vector3(0, 0.70 * s, 0))
		"lute":
			_add(n, _sphere(0.24 * s), _mat(a, 0.2, 0.55), Vector3(0, 0.26 * s, 0), Vector3.ZERO, Vector3(1.0, 1.25, 0.45))
			_add(n, _torus(0.20 * s, 0.24 * s), gold, Vector3(0, 0.26 * s, 0.06 * s), Vector3(90, 0, 0))
			_add(n, _box(Vector3(0.055 * s, 0.52 * s, 0.04 * s)), mb, Vector3(0, 0.64 * s, 0))
			_add(n, _prism(Vector3(0.09 * s, 0.12 * s, 0.045 * s)), gold, Vector3(0, 0.90 * s, 0))
			for i in range(4):
				_add(n, _box(Vector3(0.006 * s, 0.62 * s, 0.004 * s)), _mat(Color(0.95, 0.95, 0.9), 0.1, 0.4),
					Vector3(-0.03 * s + 0.02 * s * float(i), 0.56 * s, 0.095 * s))
		_:
			_add(n, _cyl(0.030 * s, 0.034 * s, 0.22 * s), mb, Vector3(0, 0.11 * s, 0))
			_add(n, _box(Vector3(0.08 * s, 0.85 * s, 0.03 * s)), ma, Vector3(0, 0.66 * s, 0))
	return n
