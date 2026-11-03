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


static func accent_for(hero_name: String, skin_id: String) -> Color:
	var s := get_skin(hero_name, skin_id)
	if s.is_empty():
		return Color(0.6, 0.75, 0.95)
	return s.get("accent", Color(0.6, 0.75, 0.95))


static func is_custom(hero_name: String, skin_id: String) -> bool:
	return skin_id != "" and skin_id != default_id(hero_name)


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


const SKIN_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform vec4 accent_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float tint_strength = 0.55;
uniform float metallic_base = 0.08;
uniform float roughness_base = 0.72;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec4 base = texture(base_tex, UV) * base_color;
	// 上下渐变 + 斜向流光条：保留原材质纹理，不再整身纯色
	float h = clamp(v_local.y * 0.28 + 0.5, 0.0, 1.0);
	vec3 skin = mix(tint_color.rgb, accent_color.rgb, h * 0.55);
	float stripe = smoothstep(0.55, 0.92, sin((v_local.x + v_local.z * 0.7 + v_local.y * 0.45) * 12.0) * 0.5 + 0.5);
	vec3 colored = mix(base.rgb, base.rgb * skin * 1.25 + vec3(0.025), tint_strength);
	colored = mix(colored, colored * 1.18 + vec3(0.03), stripe * 0.28);
	ALBEDO = colored;
	METALLIC = metallic_base;
	ROUGHNESS = roughness_base;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	EMISSION = accent_color.rgb * (0.035 + stripe * 0.075 + rim * 0.12);
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}
"""

static var _skin_shader: Shader = null
static var _skin_white_tex: ImageTexture = null


static func _get_skin_shader() -> Shader:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER_CODE
	return _skin_shader


static func _get_white_tex() -> ImageTexture:
	if _skin_white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_skin_white_tex = ImageTexture.create_from_image(img)
	return _skin_white_tex


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
	_add_cape(root, accent)
	_add_orbs(root, accent)


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
					var m := mat as StandardMaterial3D
					# 透明材质（翅膀/纱/特效件）保持原样，避免被不透明皮肤材质覆盖
					if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						continue
					var sm := ShaderMaterial.new()
					sm.shader = _get_skin_shader()
					sm.set_shader_parameter("base_color", m.albedo_color)
					sm.set_shader_parameter("base_tex", m.albedo_texture if m.albedo_texture != null else _get_white_tex())
					sm.set_shader_parameter("tint_color", body)
					sm.set_shader_parameter("accent_color", accent)
					sm.set_shader_parameter("tint_strength", 0.55)
					sm.set_shader_parameter("metallic_base", maxf(m.metallic, 0.06))
					sm.set_shader_parameter("roughness_base", clampf(m.roughness * 0.86, 0.24, 0.9))
					sm.set_shader_parameter("normal_tex", m.normal_texture if m.normal_texture != null else _get_white_tex())
					sm.set_shader_parameter("has_normal", m.normal_texture != null)
					mi.set_surface_override_material(si, sm)
				elif mat == null:
					var sm2 := ShaderMaterial.new()
					sm2.shader = _get_skin_shader()
					sm2.set_shader_parameter("base_color", Color.WHITE)
					sm2.set_shader_parameter("base_tex", _get_white_tex())
					sm2.set_shader_parameter("tint_color", body)
					sm2.set_shader_parameter("accent_color", accent)
					sm2.set_shader_parameter("tint_strength", 0.6)
					sm2.set_shader_parameter("metallic_base", 0.06)
					sm2.set_shader_parameter("roughness_base", 0.74)
					mi.set_surface_override_material(si, sm2)
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


static func _add_cape(root: Node3D, accent: Color) -> void:
	var old := root.get_node_or_null("SkinCape")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var cape := MeshInstance3D.new()
	cape.name = "SkinCape"
	var q := QuadMesh.new()
	q.size = Vector2(1.45, 1.9)
	cape.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 0.16),
		Color(accent.r, accent.g, accent.b, 0.58)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var gtex := GradientTexture2D.new()
	gtex.width = 16
	gtex.height = 64
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.gradient = grad
	m.albedo_texture = gtex
	m.albedo_color = Color.WHITE
	m.emission_enabled = true
	m.emission = accent
	m.emission_energy_multiplier = 0.55
	cape.material_override = m
	cape.position = Vector3(0.0, 1.15, -0.75)
	cape.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	cape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(cape)


static func _add_orbs(root: Node3D, accent: Color) -> void:
	for i in range(3):
		var old := root.get_node_or_null("SkinOrb%d" % i)
		if old != null and is_instance_valid(old):
			old.queue_free()
		var orb := MeshInstance3D.new()
		orb.name = "SkinOrb%d" % i
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		orb.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = accent
		m.emission_enabled = true
		m.emission = accent
		m.emission_energy_multiplier = 2.2
		orb.material_override = m
		var ang := TAU * float(i) / 3.0
		orb.position = Vector3(cos(ang) * 0.72, 1.55 + 0.18 * float(i), sin(ang) * 0.72)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(orb)


## 子弹/技能特效按皮肤强调色染色（只改表现，不改伤害/判定）
static func apply_fx_color(node: Node, accent: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				for si in range(mi.mesh.get_surface_count()):
					var mat: Material = mi.get_surface_override_material(si)
					if mat == null:
						mat = mi.mesh.surface_get_material(si)
					if mat is StandardMaterial3D:
						var okey := "_skin_fx_orig_%d" % si
						if not mi.has_meta(okey):
							mi.set_meta(okey, mi.get_surface_override_material(si))
						var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
						m.albedo_color = m.albedo_color.lerp(Color(accent.r, accent.g, accent.b, m.albedo_color.a), 0.75)
						m.emission_enabled = true
						m.emission = accent
						m.emission_energy_multiplier = maxf(m.emission_energy_multiplier, 1.2)
						mi.set_surface_override_material(si, m)
		apply_fx_color(child, accent)


## 清掉 apply_fx_color 造成的染色（子弹回池复用给非皮肤英雄时用）
static func clear_fx_color(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				for si in range(mi.mesh.get_surface_count()):
					var okey := "_skin_fx_orig_%d" % si
					if mi.has_meta(okey):
						mi.set_surface_override_material(si, mi.get_meta(okey))
						mi.remove_meta(okey)
		clear_fx_color(child)
