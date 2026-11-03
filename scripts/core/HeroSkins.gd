class_name HeroSkins
extends RefCounted
## 英雄皮肤表 + 程序化染色/光效。规则源：每个英雄至少 2 套（经典 + 定制）。
## 皮肤只影响表现，不改数值；联机快照/录像携带 skin id。

const SKINS := {	"吕布": [		{"id": "classic", "name": "经典·无双", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.72, 0.25)},		{"id": "tianmo", "name": "天魔缭乱", "body": Color(0.62, 0.38, 0.82), "accent": Color(1.00, 0.18, 0.50)},	],	"亚瑟": [		{"id": "classic", "name": "经典·圣殿", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.80, 0.85, 1.00)},		{"id": "death", "name": "亡者骑士", "body": Color(0.48, 0.55, 0.52), "accent": Color(0.35, 1.00, 0.55)},	],	"马超": [		{"id": "classic", "name": "经典·西凉", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.90, 0.85, 0.60)},		{"id": "shenwei", "name": "神威天将军", "body": Color(0.95, 0.80, 0.50), "accent": Color(1.00, 0.82, 0.30)},	],	"铠": [		{"id": "classic", "name": "经典·破灭", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.85, 0.25, 0.25)},		{"id": "qinglong", "name": "青龙志", "body": Color(0.45, 0.72, 0.90), "accent": Color(0.20, 1.00, 1.00)},	],	"不知火舞": [		{"id": "classic", "name": "经典·花蝶", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.35, 0.40)},		{"id": "meiyu", "name": "魅语", "body": Color(0.92, 0.48, 0.58), "accent": Color(1.00, 0.20, 0.55)},	],	"甄姬": [		{"id": "classic", "name": "经典·洛神", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.50, 0.80, 1.00)},		{"id": "youheng", "name": "幽恒", "body": Color(0.55, 0.68, 0.92), "accent": Color(0.35, 0.80, 1.00)},	],	"狄仁杰": [		{"id": "classic", "name": "经典·锦衣", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.95, 0.78, 0.30)},		{"id": "chaoshi", "name": "超时空战士", "body": Color(0.38, 0.58, 0.90), "accent": Color(0.20, 0.90, 1.00)},	],	"太乙真人": [		{"id": "classic", "name": "经典·炼金", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.40, 0.90, 0.65)},		{"id": "taotie", "name": "饕餮", "body": Color(0.60, 0.75, 0.45), "accent": Color(0.50, 1.00, 0.30)},	],	"东皇太一": [		{"id": "classic", "name": "经典·日蚀", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.70, 0.40, 1.00)},		{"id": "donghai", "name": "东海龙王", "body": Color(0.45, 0.62, 0.62), "accent": Color(0.20, 0.90, 0.75)},	],	"李白": [		{"id": "classic", "name": "经典·青莲", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.80, 0.95, 1.00)},		{"id": "fenghuang", "name": "凤求凰", "body": Color(0.95, 0.90, 0.82), "accent": Color(1.00, 0.55, 0.25)},	],	"兰陵王": [		{"id": "classic", "name": "经典·暗影", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.70, 0.50, 1.00)},		{"id": "yingren", "name": "影刃", "body": Color(0.38, 0.28, 0.48), "accent": Color(0.80, 0.20, 1.00)},	],	"孙尚香": [		{"id": "classic", "name": "经典·千金", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.55, 0.20)},		{"id": "jijia", "name": "末日机甲", "body": Color(0.90, 0.68, 0.55), "accent": Color(0.30, 1.00, 1.00)},	],	"马可波罗": [		{"id": "classic", "name": "经典·远游", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.95, 0.80, 0.35)},		{"id": "zhumeng", "name": "逐梦之星", "body": Color(0.40, 0.65, 0.92), "accent": Color(1.00, 0.80, 0.25)},	],	"张飞": [		{"id": "classic", "name": "经典·禁血", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.90, 0.28, 0.22)},		{"id": "hupo", "name": "虎魄", "body": Color(0.75, 0.52, 0.35), "accent": Color(1.00, 0.32, 0.15)},	],	"沈梦溪": [		{"id": "classic", "name": "经典·炸弹猫", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.60, 0.20)},		{"id": "xingkong", "name": "星空", "body": Color(0.48, 0.42, 0.78), "accent": Color(0.70, 0.30, 1.00)},	],	"安琪拉": [		{"id": "classic", "name": "经典·暗夜", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.55, 0.25)},		{"id": "chufang", "name": "魔法小厨娘", "body": Color(0.95, 0.68, 0.78), "accent": Color(1.00, 0.35, 0.60)},	],	"妲己": [		{"id": "classic", "name": "经典·魅力", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.58, 0.85)},		{"id": "alice", "name": "仙境爱丽丝", "body": Color(0.92, 0.58, 0.82), "accent": Color(0.60, 0.30, 1.00)},	],	"小乔": [		{"id": "classic", "name": "经典·恋风", "body": Color(1.00, 1.00, 1.00), "accent": Color(1.00, 0.65, 0.85)},		{"id": "tiane", "name": "天鹅之梦", "body": Color(0.58, 0.72, 0.96), "accent": Color(0.30, 0.80, 1.00)},	],	"鲁班七号": [		{"id": "classic", "name": "经典·木偶", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.90, 0.78, 0.40)},		{"id": "xingkong", "name": "星空梦想", "body": Color(0.48, 0.82, 0.62), "accent": Color(0.20, 1.00, 0.45)},	],	"夏侯惇": [		{"id": "classic", "name": "经典·独眼", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.90, 0.35, 0.25)},		{"id": "zhanzheng", "name": "战争骑士", "body": Color(0.52, 0.58, 0.65), "accent": Color(1.00, 0.35, 0.20)},	],	"后羿": [		{"id": "classic", "name": "经典·精灵", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.95, 0.65, 0.25)},		{"id": "huangjin", "name": "黄金射手", "body": Color(0.96, 0.86, 0.55), "accent": Color(1.00, 0.75, 0.20)},	],	"李元芳": [		{"id": "classic", "name": "经典·密探", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.95, 0.85, 0.30)},		{"id": "feiyuan", "name": "飞鸢探春", "body": Color(0.52, 0.78, 0.48), "accent": Color(0.40, 1.00, 0.30)},	],	"元流之子": [		{"id": "classic", "name": "经典·流", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.45, 1.00, 0.95)},		{"id": "xingliu", "name": "星流", "body": Color(0.48, 0.72, 0.92), "accent": Color(0.50, 1.00, 1.00)},	],	"大禹": [		{"id": "classic", "name": "经典·治水", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.55, 0.70, 0.65)},		{"id": "longyin", "name": "龙吟", "body": Color(0.42, 0.62, 0.82), "accent": Color(1.00, 0.75, 0.30)},	],	"王昭君": [		{"id": "classic", "name": "经典·冰雪", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.55, 0.88, 1.00)},		{"id": "fenghuang", "name": "凤凰于飞", "body": Color(0.86, 0.72, 0.88), "accent": Color(1.00, 0.50, 0.80)},	],	"刘禅": [		{"id": "classic", "name": "经典·暴走", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.75, 0.55, 0.30)},		{"id": "xiongmao", "name": "绅士熊喵", "body": Color(0.52, 0.68, 0.82), "accent": Color(0.95, 0.70, 0.30)},	],	"孙悟空": [		{"id": "classic", "name": "经典·大圣", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.95, 0.80, 0.30)},		{"id": "diyu", "name": "地狱火", "body": Color(0.78, 0.42, 0.28), "accent": Color(1.00, 0.30, 0.10)},	],	"英睿": [		{"id": "classic", "name": "经典·英睿", "body": Color(1.00, 1.00, 1.00), "accent": Color(0.88, 0.92, 1.00)},		{"id": "shuangren", "name": "霜刃", "body": Color(0.50, 0.72, 0.96), "accent": Color(0.20, 0.95, 1.00)},	],}

static func skins_for(hero_name: String) -> Array:
	return SKINS.get(hero_name, [])


static func default_id(hero_name: String) -> String:
	var arr := skins_for(hero_name)
	return str((arr[0] as Dictionary).get("id", "classic")) if not arr.is_empty() else ""


static func get_skin(hero_name: String, skin_id: String) -> Dictionary:
	var arr := skins_for(hero_name)
	if arr.is_empty():
		return {}
	for s in arr:
		if str((s as Dictionary).get("id", "")) == skin_id:
			return s
	return {}


static func skin_name(hero_name: String, skin_id: String) -> String:
	var s := get_skin(hero_name, skin_id)
	return str(s.get("name", "经典")) if not s.is_empty() else "经典"


static func selected_id(hero_name: String) -> String:
	var arr := skins_for(hero_name)
	if arr.is_empty():
		return ""
	var idx := clampi(PlayerPrefs.opt_int("skin_" + hero_name, 0), 0, arr.size() - 1)
	return str((arr[idx] as Dictionary).get("id", "classic"))


static func set_selected(hero_name: String, skin_id: String) -> void:
	var arr := skins_for(hero_name)
	for i in range(arr.size()):
		if str((arr[i] as Dictionary).get("id", "")) == skin_id:
			PlayerPrefs.set_opt("skin_" + hero_name, i)
			return


static func cycle(hero_name: String, current: String) -> String:
	var arr := skins_for(hero_name)
	if arr.is_empty():
		return current
	var idx := -1
	for i in range(arr.size()):
		if str((arr[i] as Dictionary).get("id", "")) == current:
			idx = i
			break
	idx = (idx + 1) % arr.size()
	return str((arr[idx] as Dictionary).get("id", "classic"))


## AI 皮肤：默认优先用非经典皮肤，保证 AI 也能展示定制皮肤；seed 稳定可复现。
static func auto_id(hero_name: String, seed: int) -> String:
	var arr := skins_for(hero_name)
	if arr.is_empty():
		return ""
	if arr.size() <= 1:
		return default_id(hero_name)
	var idx := 1 + (absi(seed) % (arr.size() - 1))
	return str((arr[idx] as Dictionary).get("id", "classic"))


## 把皮肤应用到英雄模型根（或 HeroPreview 的 PreviewModel 根）
static func apply_to(root: Node3D, hero_name: String, skin_id: String) -> void:
	if root == null or not is_instance_valid(root):
		return
	var sid := skin_id
	if sid == "":
		sid = default_id(hero_name)
	var skin := get_skin(hero_name, sid)
	if skin.is_empty():
		return
	if str(root.get_meta("_skin_id", "")) == sid:
		return
	root.set_meta("_skin_id", sid)
	var body: Color = skin.get("body", Color.WHITE)
	var accent: Color = skin.get("accent", Color.WHITE)
	# 经典皮肤：保留原始模型/武器材质，不染色
	if sid == default_id(hero_name):
		return
	_tint_meshes(root, body, accent)
	_add_aura(root, accent)


static func _tint_meshes(node: Node, body: Color, accent: Color) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			for si in range(mi.mesh.get_surface_count()):
				var mat: Material = mi.get_surface_override_material(si)
				if mat == null:
					mat = mi.mesh.surface_get_material(si)
				if mat is StandardMaterial3D:
					var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					var base := m.albedo_color
					m.albedo_color = Color(base.r * body.r, base.g * body.g, base.b * body.b, base.a)
					m.emission_enabled = true
					m.emission = accent
					m.emission_energy_multiplier = maxf(m.emission_energy_multiplier, 0.7)
					m.roughness = clampf(m.roughness * 0.92, 0.18, 0.9)
					mi.set_surface_override_material(si, m)
				elif mat == null:
					var m2 := StandardMaterial3D.new()
					m2.albedo_color = body
					m2.emission_enabled = true
					m2.emission = accent
					m2.emission_energy_multiplier = 0.7
					mi.set_surface_override_material(si, m2)
		_tint_meshes(child, body, accent)


static func _add_aura(root: Node3D, accent: Color) -> void:
	var old := root.get_node_or_null("SkinAura")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var ring := MeshInstance3D.new()
	ring.name = "SkinAura"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.22
	torus.outer_radius = 1.42
	torus.rings = 48
	torus.ring_segments = 8
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(accent.r, accent.g, accent.b, 0.55)
	m.emission_enabled = true
	m.emission = accent
	m.emission_energy_multiplier = 2.0
	ring.material_override = m
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
