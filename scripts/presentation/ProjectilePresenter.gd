class_name ProjectilePresenter
extends RefCounted
## 三端共享「子弹/弹体表现」：
## - host Bullet.gd：模型路径选择、缩放、后羿R 太阳火箭、防御塔能量球、英雄元素拖尾
## - 联机 NetClientBattle：按快照 kind/vkind 还原同一外形（模型档 / 定制档）
## - 回放 ReplayScreen：按录像记录的 kind/vkind 还原（旧录像无 kind 时回退发光球）
## 禁止各端再各写一份弹体模型表。

const MODEL_PATHS := {
	0: "res://model/dragon/bullet/weapon-ammo-boulder.glb",
	1: "res://model/turret/bullet/weapon-ammo-bullet.glb",
	2: "res://model/range/weapon-arrow.glb",
	3: "res://model/seige/cannon-ball.glb",
}
const HERO_VISUAL_SCALE := 3.0

const BulletVisualScript = preload("res://scripts/core/BulletVisual.gd")
const HeroProjectilesScript = preload("res://scripts/presentation/HeroProjectiles.gd")

const COL_ALLY := Color(0.0, 0.886, 1.0, 1.0)
const COL_ENEMY := Color(1.0, 0.33, 0.264, 1.0)


## host：按发射者选择弹体模型路径（''=用程序化回退视觉）
static func model_path_for(source) -> String:
	if source == null:
		return MODEL_PATHS[0]
	if source is Turret:
		return ""   # 防御塔：发光能量球（不用模型）
	if source is Hero:
		if source.attack_range > 400.0:
			return MODEL_PATHS[1]
		return MODEL_PATHS[0]
	if source is Minion:
		if source.display_name == "ranged":
			return MODEL_PATHS[2]
		if source.display_name == "siege":
			return MODEL_PATHS[3]
	return MODEL_PATHS[0]


## host：英雄/防御塔弹体放大 3 倍（原 Bullet.gd 规则）
static func source_scale(source) -> float:
	if source is Hero or source is Turret:
		return HERO_VISUAL_SCALE
	return 1.0


## 后羿R：太阳火箭（自组模型；host/联机共用）
static func houyi_ult_arrow() -> Node3D:
	var root := Node3D.new()
	root.name = "HouyiUltArrow"
	var body: MeshInstance3D = MeshFactory.create_sphere(0.4, Color(1.0, 0.65, 0.0), true)
	body.scale = Vector3(0.5, 0.5, 2.5)
	root.add_child(body)
	var ring: MeshInstance3D = MeshFactory.create_torus_ring(0.35, 0.5, Color(1.0, 0.3, 0.0), false, 1.0, true)
	ring.rotation.x = deg_to_rad(90)
	root.add_child(ring)
	var glow: MeshInstance3D = MeshFactory.create_sphere(0.55, Color(1.0, 0.5, 0.0), true, 0.25)
	root.add_child(glow)
	root.rotation.x = deg_to_rad(90)
	return root


## 防御塔能量球
static func tower_orb(radius: float) -> Node3D:
	return MeshFactory.create_energy_orb(radius * 0.6, Color(1.0, 0.88, 0.55))


## 英雄弹体元素色拖尾（host 原：Vfx.attach_trail(self, color_for_hero, 0.20, 0.30, 8)）
static func attach_hero_trail(host: Node3D, hero_name: String, accent: Color = Color(0, 0, 0, 0)) -> void:
	if host == null or hero_name == "":
		return
	var col: Color = accent if accent.a > 0.0 else Vfx.color_for_hero(hero_name)
	Vfx.attach_trail(host, col, 0.20, 0.30, 8)


## 联机/回放：kind（0..5 / 1000+vkind）→ 与 host 同形的弹体节点
static func make(kind: int, team: int = 0, vkind: int = 0, radius: float = 0.15, flags: int = 0) -> Node3D:
	var node := _make_raw(kind, team, vkind, radius)
	# kind>=1000 时原始 vkind = kind-1000（联机快照只传合成档位）；回放两者都传
	var vk := vkind
	if vk <= 0 and kind >= 1000:
		vk = kind - 1000
	_apply_flags(node, vk, flags)
	return node


static func _make_raw(kind: int, team: int, vkind: int, radius: float) -> Node3D:
	if kind >= 1000:
		return make_bespoke(kind - 1000)
	if vkind >= BulletVisualScript.VKIND_BASE and vkind < 1000:
		return BulletVisualScript.build_from_vkind(vkind)
	if kind >= 1000:
		return make_bespoke(kind - 1000)
	if kind == 4:
		return houyi_ult_arrow()
	if kind == 5:
		return tower_orb(radius)
	var path := str(MODEL_PATHS.get(kind, ""))
	if path != "" and ResourceLoader.exists(path):
		var packed = load(path)
		if packed != null:
			var m: Node3D = packed.instantiate()
			if kind <= 1:
				m.scale = Vector3.ONE * HERO_VISUAL_SCALE
			return m
	return fallback_cylinder(kind, team)


## 与 host Bullet._build_unified_visual 同步：线性技能弹 ×1.7、英雄元素拖尾、箭矢俯仰标记
static func _apply_flags(node: Node3D, vkind: int, flags: int) -> void:
	if node == null:
		return
	if (flags & 1) != 0:
		node.scale *= 1.7
	if HeroProjectilesScript.is_hero_vkind(vkind):
		if (flags & 1) != 0:
			node.scale *= 1.35
		var c1: Color = node.get_meta("c1", COL_ALLY)
		var c2: Color = node.get_meta("c2", c1.lightened(0.35))
		Vfx.attach_trail(node, c1, 0.24, 0.32, 8, c2)
		if bool(node.get_meta("pitch", false)):
			node.set_meta("pitch", true)
		return
	if vkind >= BulletVisualScript.VKIND_BASE and vkind < 1000:
		var d := BulletVisualScript.decode_vkind(vkind)
		if (flags & 2) != 0:
			var cols := BulletVisualScript.colors_for(int(d.get("palette", 0)))
			Vfx.attach_trail(node, cols[0], float(d.get("trail_size", 0.2)),
				float(d.get("trail_life", 0.3)), 8, cols[1])
		# 箭矢类需要随弹道俯仰（host _pitch_visual）
		var sh := int(d.get("shape", 0))
		if sh == BulletVisualScript.SHAPE_BOLT or sh == BulletVisualScript.SHAPE_ARROW:
			node.set_meta("pitch", true)


## 定制档（小乔Q 扇盘等，与 host 视觉一致）
static func make_bespoke(vkind: int) -> Node3D:
	if HeroProjectilesScript.is_hero_vkind(vkind):
		var hv := HeroProjectilesScript.build_from_vkind(vkind)
		if hv != null:
			return hv
	if vkind >= BulletVisualScript.VKIND_BASE and vkind < 1000:
		return BulletVisualScript.build_from_vkind(vkind)
	if vkind == 1:
		var root := Node3D.new()
		root.name = "XiaoQiaoFan"
		var disc := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 1.2
		cy.bottom_radius = 1.2
		cy.height = 0.15
		disc.mesh = cy
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.7)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.6, 0.6)
		disc.material_override = mat
		root.add_child(disc)
		return root
	return MeshFactory.create_sphere(0.3, Color(0.7, 0.2, 1.0), true)


## 模型缺失兜底（同 host：发光圆柱近似，队伍色）
static func fallback_cylinder(kind: int, team: int) -> Node3D:
	var m := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	var col := COL_ENEMY if team == 1 else COL_ALLY
	cy.top_radius = 0.08
	cy.bottom_radius = 0.08
	cy.height = 0.9
	if kind >= 2:
		col = Color(1.0, 0.55, 0.15)
		cy.top_radius = 0.14
		cy.bottom_radius = 0.14
		cy.height = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	m.mesh = cy
	m.material_override = mat
	m.rotation.x = PI * 0.5
	return m
