class_name HeroProjectiles
extends RefCounted
## 三端共享：每个英雄专属的普攻/技能弹体模型。
## vkind 编码：2000 + 英雄序号*8 + 技能槽(0..3)*2 + 队伍(0/1)，避免与 BulletVisual 的 100..995 冲突。

const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
const MeshFactory = preload("res://scripts/entities/MeshFactory.gd")

const VKIND_HERO_BASE := 2000
const HERO_ORDER := ["吕布", "亚瑟", "马超", "铠", "不知火舞", "甄姬", "狄仁杰", "太乙真人", "东皇太一", "李白", "兰陵王", "孙尚香", "马可波罗", "张飞", "沈梦溪", "安琪拉", "妲己", "小乔", "鲁班七号", "夏侯惇", "后羿", "李元芳", "元流之子", "大禹", "王昭君", "刘禅", "孙悟空", "英睿"]
const STYLE := {	"吕布": "halberd",	"亚瑟": "sword",	"马超": "spear",	"铠": "greatsword",	"不知火舞": "fan",	"甄姬": "water",	"狄仁杰": "card",	"太乙真人": "orb",	"东皇太一": "orb",	"李白": "jian",	"兰陵王": "daggers",	"孙尚香": "rocket",	"马可波罗": "pistol",	"张飞": "axe",	"沈梦溪": "bomb",	"安琪拉": "flame",	"妲己": "heart",	"小乔": "fan",	"鲁班七号": "rocket",	"夏侯惇": "blade",	"后羿": "arrow",	"李元芳": "dart",	"元流之子": "water_arrow",	"大禹": "cauldron",	"王昭君": "ice",	"刘禅": "gear",	"孙悟空": "staff",	"英睿": "claw",}

const COLORS := {	"吕布": [Color(0.86, 0.12, 0.16), Color(0.95, 0.72, 0.28)],	"亚瑟": [Color(0.25, 0.48, 0.92), Color(1.00, 0.78, 0.28)],	"马超": [Color(0.52, 0.85, 1.00), Color(0.28, 0.18, 0.12)],	"铠": [Color(0.22, 0.72, 0.92), Color(0.08, 0.20, 0.34)],	"不知火舞": [Color(1.00, 0.32, 0.42), Color(1.00, 0.72, 0.25)],	"甄姬": [Color(0.22, 0.55, 1.00), Color(0.62, 0.95, 1.00)],	"狄仁杰": [Color(0.95, 0.72, 0.22), Color(0.28, 0.52, 1.00)],	"太乙真人": [Color(0.38, 0.90, 0.52), Color(0.92, 0.78, 0.28)],	"东皇太一": [Color(0.52, 0.28, 0.92), Color(0.88, 0.18, 0.62)],	"李白": [Color(0.82, 0.92, 1.00), Color(0.28, 0.48, 0.92)],	"兰陵王": [Color(0.42, 0.18, 0.68), Color(0.82, 0.28, 1.00)],	"孙尚香": [Color(1.00, 0.62, 0.16), Color(0.46, 0.55, 0.68)],	"马可波罗": [Color(0.32, 0.62, 1.00), Color(1.00, 0.78, 0.24)],	"张飞": [Color(0.62, 0.42, 0.24), Color(1.00, 0.28, 0.18)],	"沈梦溪": [Color(1.00, 0.52, 0.12), Color(0.68, 0.28, 0.72)],	"安琪拉": [Color(1.00, 0.32, 0.18), Color(1.00, 0.78, 0.28)],	"妲己": [Color(1.00, 0.30, 0.62), Color(0.72, 0.28, 1.00)],	"小乔": [Color(1.00, 0.52, 0.74), Color(0.32, 0.62, 1.00)],	"鲁班七号": [Color(0.38, 0.88, 0.58), Color(1.00, 0.78, 0.24)],	"夏侯惇": [Color(0.48, 0.36, 0.30), Color(0.92, 0.18, 0.12)],	"后羿": [Color(1.00, 0.68, 0.18), Color(0.66, 0.88, 1.00)],	"李元芳": [Color(0.32, 0.85, 0.46), Color(1.00, 0.78, 0.24)],	"元流之子": [Color(0.26, 0.90, 0.92), Color(0.18, 0.48, 1.00)],	"大禹": [Color(0.32, 0.68, 0.34), Color(1.00, 0.74, 0.28)],	"王昭君": [Color(0.52, 0.82, 1.00), Color(0.90, 0.98, 1.00)],	"刘禅": [Color(0.92, 0.62, 0.18), Color(0.36, 0.48, 0.66)],	"孙悟空": [Color(1.00, 0.72, 0.18), Color(0.88, 0.18, 0.12)],	"英睿": [Color(0.68, 0.78, 0.96), Color(0.28, 0.95, 1.00)],}

static func hero_index(hero_name: String) -> int:
	return HERO_ORDER.find(hero_name)


static func has_hero(hero_name: String) -> bool:
	return HERO_ORDER.has(hero_name)


static func vkind_for(hero_name: String, team: int, skill_id: int) -> int:
	var idx := hero_index(hero_name)
	if idx < 0:
		return 0
	var slot := clampi(skill_id, 0, 3)
	return VKIND_HERO_BASE + idx * 8 + slot * 2 + clampi(team, 0, 1)


static func is_hero_vkind(vk: int) -> bool:
	return vk >= VKIND_HERO_BASE and vk < VKIND_HERO_BASE + HERO_ORDER.size() * 8 + 8


static func decode(vk: int) -> Dictionary:
	var t := vk - VKIND_HERO_BASE
	if t < 0:
		return {}
	var idx: int = t / 8
	if idx < 0 or idx >= HERO_ORDER.size():
		return {}
	var rem := t % 8
	return {"name": HERO_ORDER[idx], "skill": rem / 2, "team": rem % 2}


static func build_from_vkind(vk: int) -> Node3D:
	var d := decode(vk)
	if d.is_empty():
		return null
	return build(str(d["name"]), int(d["team"]), int(d["skill"]))


static func build(hero_name: String, team: int, skill_id: int = 0) -> Node3D:
	if not has_hero(hero_name):
		return null
	var style: String = STYLE.get(hero_name, "orb")
	var cols: Array = COLORS.get(hero_name, [Color(0.6, 0.8, 1.0), Color(1.0, 1.0, 1.0)])
	var a: Color = cols[0]
	var b: Color = cols[1]
	var accent: Color = Color(1.0, 0.42, 0.28) if team == 1 else Color(0.32, 0.86, 1.0)
	var root := Node3D.new()
	root.name = "HeroBullet_" + hero_name
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	match style:
		"halberd": _weapon(spin, "halberd", a, b, 0.22)
		"sword": _weapon(spin, "sword", a, b, 0.24)
		"spear": _weapon(spin, "spear", a, b, 0.19)
		"greatsword": _weapon(spin, "greatsword", a, b, 0.15)
		"fan": _weapon(spin, "fan", a, b, 0.23, false)
		"jian": _weapon(spin, "jian", a, b, 0.22)
		"daggers": _weapon(spin, "daggers", a, b, 0.28)
		"pistol": _weapon(spin, "pistol", a, b, 0.30, false)
		"axe": _weapon(spin, "axe", a, b, 0.20)
		"staff": _weapon(spin, "staff", a, b, 0.17)
		"blade": _weapon(spin, "halberd", a, b, 0.20)
		"orb": _orb(spin, a, b, 0.27)
		"water": _water(spin, a, b)
		"card": _card(spin, a, b)
		"rocket": _rocket(spin, a, b)
		"bomb": _bomb(spin, a, b)
		"flame": _flame(spin, a, b)
		"heart": _heart(spin, a, b)
		"arrow": _arrow(spin, a, b)
		"dart": _dart(spin, a, b)
		"water_arrow": _water_arrow(spin, a, b)
		"ice": _ice(spin, a, b)
		"gear": _gear(spin, a, b)
		"claw": _claw(spin, a, b)
		"cauldron": _cauldron(spin, a, b)
		_: _orb(spin, a, b, 0.27)
	_halo(root, b, accent)
	_add_shards(spin, b, accent)
	root.set_meta("c1", b)
	root.set_meta("c2", accent)
	root.set_meta("pitch", style in ["arrow", "dart", "spear", "water_arrow"])
	root.set_meta("spin", 2.4 if style in ["orb", "card", "heart", "gear", "water"] else 1.4)
	return root


static func _weapon(spin: Node3D, style: String, a: Color, b: Color, s: float, rotate: bool = true) -> Node3D:
	var w: Node3D = HeroWeapons._build(style, a, b, s)
	if rotate:
		w.rotation_degrees.x = 90.0
	spin.add_child(w)
	return w


static func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _mat(c: Color, metal: float = 0.75, rough: float = 0.28, emis: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	return m


static func _glow(c: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	return m


static func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h if h > 0.0 else r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func _cyl(top: float, bottom: float, h: float, segs: int = 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 8
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


static func _halo(root: Node3D, c: Color, accent: Color) -> void:
	var ring := _mi(root, _torus(0.48, 0.62), _glow(c, 0.42), Vector3.ZERO, Vector3(90, 0, 0))
	ring.name = "Halo"
	_mi(root, _torus(0.66, 0.72), _glow(accent, 0.22), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(root, _sphere(0.12), _glow(accent, 0.8), Vector3(0, 0, 0.08))


static func _add_shards(spin: Node3D, c: Color, accent: Color) -> void:
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		var p := Vector3(cos(ang) * 0.42, sin(ang) * 0.42, -0.08)
		_mi(spin, _prism(Vector3(0.055, 0.20, 0.035)), _glow(accent, 0.55), p,
			Vector3(0, 0, rad_to_deg(ang)))


static func _orb(spin: Node3D, a: Color, b: Color, r: float) -> void:
	_mi(spin, _sphere(r), _mat(a, 0.15, 0.18, 1.2))
	_mi(spin, _sphere(r * 0.55), _mat(b, 0.2, 0.2, 2.0))
	_mi(spin, _torus(r * 0.95, r * 1.22), _mat(b, 0.45, 0.22, 0.8), Vector3.ZERO, Vector3(70, 20, 0))
	_mi(spin, _torus(r * 0.98, r * 1.26), _mat(b.lightened(0.25), 0.35, 0.3, 0.5), Vector3.ZERO, Vector3(20, 70, 0))


static func _water(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _sphere(0.25, 0.7), _mat(a, 0.05, 0.12, 0.7), Vector3.ZERO, Vector3.ZERO, Vector3(0.8, 1.0, 1.45))
	_mi(spin, _sphere(0.11), _mat(b, 0.05, 0.1, 1.4), Vector3(0, 0, 0.32))
	_mi(spin, _torus(0.28, 0.38), _glow(b, 0.35), Vector3.ZERO, Vector3(90, 0, 0))
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		_mi(spin, _sphere(0.06), _glow(b, 0.65), Vector3(cos(ang) * 0.34, sin(ang) * 0.34, 0.12))


static func _card(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _box(Vector3(0.34, 0.46, 0.035)), _mat(a, 0.55, 0.25, 0.15))
	_mi(spin, _box(Vector3(0.24, 0.34, 0.042)), _mat(b, 0.2, 0.3, 0.6))
	for i in range(3):
		_mi(spin, _box(Vector3(0.045, 0.30 - 0.04 * float(i), 0.05)), _glow(b, 0.75),
			Vector3(-0.09 + 0.09 * float(i), 0, 0.03))
	_mi(spin, _torus(0.24, 0.31), _glow(b, 0.35), Vector3.ZERO, Vector3(0, 0, 0))


static func _rocket(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _cyl(0.13, 0.17, 0.72), _mat(a, 0.85, 0.24), Vector3(0, 0, 0), Vector3(90, 0, 0))
	_mi(spin, _cyl(0.0, 0.13, 0.25), _mat(b, 0.4, 0.25, 0.8), Vector3(0, 0, 0.47), Vector3(90, 0, 0))
	_mi(spin, _torus(0.15, 0.22), _mat(b, 0.5, 0.22, 0.5), Vector3(0, 0, -0.05), Vector3(90, 0, 0))
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		_mi(spin, _prism(Vector3(0.05, 0.34, 0.12)), _mat(b, 0.6, 0.3, 0.2),
			Vector3(cos(ang) * 0.17, sin(ang) * 0.17, -0.28), Vector3(0, rad_to_deg(ang), 90))
	_mi(spin, _cyl(0.0, 0.11, 0.42), _glow(Color(1.0, 0.55, 0.18), 0.7), Vector3(0, 0, -0.48), Vector3(90, 0, 0))


static func _bomb(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _sphere(0.29), _mat(a, 0.7, 0.32), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.92, 1.0))
	_mi(spin, _torus(0.22, 0.32), _mat(b, 0.6, 0.25, 0.4), Vector3.ZERO, Vector3(90, 0, 0))
	_mi(spin, _cyl(0.022, 0.03, 0.20), _mat(b, 0.7, 0.3), Vector3(0, 0.31, 0))
	_mi(spin, _sphere(0.065), _glow(Color(1.0, 0.8, 0.3), 1.0), Vector3(0, 0.43, 0))
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		_mi(spin, _sphere(0.035), _glow(b, 0.75), Vector3(cos(ang) * 0.30, sin(ang) * 0.20, 0))


static func _flame(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _sphere(0.26), _glow(a, 0.75))
	_mi(spin, _sphere(0.15), _glow(b, 0.95), Vector3(0, 0, 0.14))
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		_mi(spin, _prism(Vector3(0.12, 0.42, 0.08)), _glow(a, 0.55),
			Vector3(cos(ang) * 0.16, sin(ang) * 0.16, -0.10), Vector3(0, 0, rad_to_deg(ang)))
	_mi(spin, _torus(0.28, 0.38), _glow(b, 0.35), Vector3.ZERO, Vector3(90, 0, 0))


static func _heart(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _sphere(0.16), _mat(a, 0.1, 0.2, 1.1), Vector3(-0.10, 0.07, 0))
	_mi(spin, _sphere(0.16), _mat(a, 0.1, 0.2, 1.1), Vector3(0.10, 0.07, 0))
	_mi(spin, _cyl(0.0, 0.23, 0.32, 10), _mat(a, 0.1, 0.2, 0.9), Vector3(0, -0.12, 0), Vector3(180, 0, 0))
	_mi(spin, _sphere(0.07), _glow(b, 0.9), Vector3(0, 0.08, 0.09))
	_mi(spin, _torus(0.32, 0.40), _glow(b, 0.30), Vector3.ZERO, Vector3(90, 0, 0))


static func _arrow(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _cyl(0.022, 0.028, 0.72), _mat(Color(0.45, 0.30, 0.18), 0.4, 0.55), Vector3(0, 0, 0), Vector3(90, 0, 0))
	_mi(spin, _cyl(0.0, 0.075, 0.22), _mat(a, 0.85, 0.2, 0.25), Vector3(0, 0, 0.46), Vector3(90, 0, 0))
	_mi(spin, _torus(0.04, 0.065), _mat(b, 0.8, 0.2, 0.4), Vector3(0, 0, 0.24), Vector3(90, 0, 0))
	for i in range(3):
		var ang := -28.0 + 28.0 * float(i)
		_mi(spin, _box(Vector3(0.11, 0.24, 0.012)), _glow(b, 0.55), Vector3(0, 0, -0.34), Vector3(0, ang, 0), Vector3(1, 1, 1))


static func _dart(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _box(Vector3(0.30, 0.035, 0.065)), _mat(a, 0.8, 0.25, 0.2))
	_mi(spin, _cyl(0.0, 0.09, 0.28, 4), _mat(b, 0.6, 0.25, 0.5), Vector3(0, 0, 0.22), Vector3(90, 0, 0))
	for side in [-1.0, 1.0]:
		_mi(spin, _prism(Vector3(0.12, 0.24, 0.02)), _glow(b, 0.45),
			Vector3(0.16 * float(side), 0, -0.08), Vector3(0, 0, 36.0 * float(side)))


static func _water_arrow(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _cyl(0.0, 0.08, 0.48, 6), _mat(a, 0.2, 0.15, 0.9), Vector3(0, 0, 0.28), Vector3(90, 0, 0))
	_mi(spin, _cyl(0.045, 0.055, 0.38), _mat(a, 0.15, 0.2, 0.5), Vector3(0, 0, -0.08), Vector3(90, 0, 0))
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		_mi(spin, _sphere(0.055), _glow(b, 0.75), Vector3(cos(ang) * 0.13, sin(ang) * 0.13, -0.10))
	_mi(spin, _torus(0.16, 0.24), _glow(b, 0.35), Vector3(0, 0, 0.12), Vector3(90, 0, 0))


static func _ice(spin: Node3D, a: Color, b: Color) -> void:
	for i in range(3):
		var ang := -22.0 + 22.0 * float(i)
		_mi(spin, _cyl(0.0, 0.09, 0.62, 5), _mat(a, 0.25, 0.12, 0.75),
			Vector3(0, 0, 0), Vector3(90, 0, ang))
	_mi(spin, _sphere(0.11), _glow(b, 0.8), Vector3(0, 0, 0.06))
	_mi(spin, _torus(0.22, 0.32), _glow(b, 0.30), Vector3.ZERO, Vector3(90, 0, 0))


static func _gear(spin: Node3D, a: Color, b: Color) -> void:
	var gear := MeshFactory.build_gear(0.30, 0.09, 12, 0.08, 0.10)
	_mi(spin, gear, _mat(a, 0.9, 0.22, 0.2), Vector3.ZERO, Vector3(0, 0, 0))
	_mi(spin, _sphere(0.10), _glow(b, 0.8))
	_mi(spin, _torus(0.34, 0.42), _glow(b, 0.30), Vector3.ZERO, Vector3(90, 0, 0))


static func _claw(spin: Node3D, a: Color, b: Color) -> void:
	_mi(spin, _box(Vector3(0.28, 0.20, 0.25)), _mat(a, 0.85, 0.25, 0.1))
	for i in range(3):
		_mi(spin, _cyl(0.0, 0.035, 0.34, 5), _mat(b, 0.8, 0.18, 0.35),
			Vector3(-0.09 + 0.09 * float(i), 0, 0.22), Vector3(90, 0, 0))
	_mi(spin, _torus(0.24, 0.33), _glow(b, 0.35), Vector3.ZERO, Vector3(90, 0, 0))


static func _cauldron(spin: Node3D, a: Color, b: Color) -> void:
	var pot: Node3D = null
	if ResourceLoader.exists("res://model/pot/pot.glb"):
		var packed = load("res://model/pot/pot.glb")
		if packed != null:
			pot = packed.instantiate()
	if pot != null:
		pot.scale = Vector3.ONE * 0.13
		pot.rotation_degrees = Vector3(0, 0, 0)
		spin.add_child(pot)
	else:
		_mi(spin, _cyl(0.22, 0.16, 0.30), _mat(a, 0.7, 0.3), Vector3.ZERO)
	_mi(spin, _sphere(0.10), _glow(b, 0.9), Vector3(0, 0.18, 0))
	_mi(spin, _torus(0.30, 0.38), _glow(b, 0.35), Vector3.ZERO, Vector3(90, 0, 0))
