extends RefCounted
## 程序化墙体 / 草丛模型（替换 model/wall/wall.glb、model/grass/grass-large.glb）。
## 全部为运行时生成的 ArrayMesh + 自定义 shader：无贴图、无外部资源；host 与 LAN 客户端共用，
## 保证两端看到的是同一个模型。顶点数控制在千级以内（单次 draw call）。

static var _rock_mat: ShaderMaterial = null
static var _leaf_mat: ShaderMaterial = null
static var _rock_mesh: SphereMesh = null
static var _blob_mesh: SphereMesh = null
static var _blade_mesh: CylinderMesh = null
static var _wall_mesh_cache: ArrayMesh = null
static var _wall_variants: Array = []
static var _bush_variants: Array = []
static var _outer_wall_cache: Dictionary = {}
static var _pillar_mesh: ArrayMesh = null

# ==================== 材质 ====================

## 石头材质：世界坐标噪声分色 + 顶部苔藓 + 底部泥土 + 细颗粒
static func rock_material() -> ShaderMaterial:
	if _rock_mat != null:
		return _rock_mat
	var sh := Shader.new()
	sh.code = _ROCK_CODE.replace("__NOISE__", _NOISE_GLSL)
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = sh
	return _rock_mat

## 叶片材质：噪声深浅分色 + 顶部亮尖 + 随风摆动（GPU 顶点位移）
static func leaf_material() -> ShaderMaterial:
	if _leaf_mat != null:
		return _leaf_mat
	var sh := Shader.new()
	sh.code = _LEAF_CODE.replace("__NOISE__", _NOISE_GLSL)
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = sh
	return _leaf_mat

const _NOISE_GLSL := """
float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}
"""

const _ROCK_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 rock_a : source_color = vec4(0.47, 0.44, 0.39, 1.0);
uniform vec4 rock_b : source_color = vec4(0.21, 0.20, 0.18, 1.0);
uniform vec4 moss_col : source_color = vec4(0.19, 0.33, 0.12, 1.0);
uniform vec4 dirt_col : source_color = vec4(0.14, 0.12, 0.09, 1.0);
uniform float moss_band = 1.45;

varying vec3 wp;
varying vec3 wn;

__NOISE__

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float n = vnoise(wp * 2.4);
	float n2 = vnoise(wp * 9.5);
	float grains = vnoise(wp * 31.0);
	vec3 base = mix(rock_b.rgb, rock_a.rgb, smoothstep(0.28, 0.78, n * 0.72 + n2 * 0.38));
	base *= 0.82 + 0.38 * grains;
	// 苔藓：靠近地面的朝上表面
	float up = clamp(wn.y, 0.0, 1.0);
	float moss = smoothstep(moss_band, 0.30, wp.y) * smoothstep(0.10, 0.72, up);
	moss *= 0.55 + 0.80 * smoothstep(0.32, 0.78, vnoise(wp * 4.6 + vec3(7.0)));
	base = mix(base, moss_col.rgb * (0.72 + 0.62 * n2), clamp(moss, 0.0, 1.0));
	// 底部泥土
	float dirt = smoothstep(0.45, 0.05, wp.y);
	base = mix(base, dirt_col.rgb, dirt * 0.6);
	// 接地暗部（假 AO）：墙脚往地面过渡的一圈压暗，避免墙像“切”在地面上
	float contact = (1.0 - smoothstep(0.03, 0.58, wp.y)) * (0.72 + 0.28 * vnoise(wp * 7.0));
	base *= 1.0 - contact * 0.22;
	// 竖直面湿痕：墙脚 0~0.9m 压暗 + 微苔绿（近水面/近地面都像被水汽浸过，不再生硬切入）
	float vert = 1.0 - smoothstep(0.45, 0.92, up);
	float wet = (1.0 - smoothstep(0.55, 1.15, wp.y)) * vert;
	wet *= 0.65 + 0.55 * vnoise(wp * 6.2 + vec3(3.0));
	base *= 1.0 - clamp(wet, 0.0, 1.0) * 0.26;
	base = mix(base, moss_col.rgb * 0.85, clamp(wet, 0.0, 1.0) * 0.16 * smoothstep(0.62, 0.12, wp.y));
	// 水线湿光：贴地约 0.05~0.18m 一道微亮的湿石反光，暗示墙与水/地面接触的潮湿带
	float waterline = (1.0 - smoothstep(0.04, 0.20, abs(wp.y - 0.075))) * vert;
	base = mix(base, vec3(0.33, 0.39, 0.37), clamp(waterline, 0.0, 1.0) * 0.34);
	ALBEDO = base;
	ROUGHNESS = clamp(0.95 - 0.12 * moss - 0.30 * clamp(wet, 0.0, 1.0), 0.35, 0.98);
	SPECULAR = 0.14 + 0.42 * clamp(waterline, 0.0, 1.0);
}
"""

const _LEAF_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec4 leaf_dark : source_color = vec4(0.055, 0.16, 0.065, 1.0);
uniform vec4 leaf_mid : source_color = vec4(0.15, 0.33, 0.115, 1.0);
uniform vec4 leaf_lit : source_color = vec4(0.40, 0.60, 0.20, 1.0);
uniform float sway = 0.13;
uniform float sway_speed = 1.15;

varying vec3 wp;
varying float vh;

__NOISE__

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vh = clamp(VERTEX.y, 0.0, 3.0);
	// 每个草丛按世界位置取相位，避免整片同步摆动
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ph = origin.x * 0.42 + origin.z * 0.33;
	float t = TIME * sway_speed;
	float gust = sin(t + ph) * 0.65 + sin(t * 1.63 + ph * 1.7) * 0.35;
	float w = sway * vh * vh * 0.25;
	VERTEX.x += gust * w;
	VERTEX.z += gust * w * 0.55;
}

void fragment() {
	float n = vnoise(wp * 4.2);
	float n2 = vnoise(wp * 12.0 + vec3(4.0));
	vec3 base = mix(leaf_dark.rgb, leaf_mid.rgb, smoothstep(0.22, 0.72, n));
	base = mix(base, leaf_lit.rgb, smoothstep(0.45, 0.95, n2) * 0.78);
	base = mix(base, leaf_lit.rgb, clamp(vh * 0.26, 0.0, 1.0) * 0.55);
	ALBEDO = base;
	ROUGHNESS = 0.72;
	SPECULAR = 0.18;
	BACKLIGHT = base * 0.55;
}
"""

# ==================== 墙体 ====================

## 墙段视觉基线高度：分路/高地台面会埋掉墙脚，视觉根节点按地面抬升。
## 只影响视觉，不影响碰撞/寻路；host 与联机客户端共用。
static func wall_ground_y(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	if q.distance_to(Vector2(-60.0, 60.0)) <= 35.6 or q.distance_to(Vector2(60.0, -60.0)) <= 35.6:
		return 0.18
	# 最外圈城墙在路基之外，保持草地基准
	if absf(p.x) > 61.0 or absf(p.z) > 61.0:
		return -0.02
	if absf(p.x + p.z) * 0.70710678 <= 8.0:
		return 0.12
	if absf(absf(p.x) - 55.0) <= 8.2 or absf(absf(p.z) - 55.0) <= 8.2:
		return 0.12
	return -0.02

## 石砌立柱/岩壁：5 层错缝巨石 + 基底碎石 + 苔藓土盘（高度 ≈ 3.0，与碰撞盒一致）
static func wall_visual(seed_val: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "WallVisual"
	var slot: int = absi(seed_val) % 8
	while _wall_variants.size() <= slot:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 + _wall_variants.size() * 104729
		_wall_variants.append(_build_wall_mesh(rng))
	var mi := MeshInstance3D.new()
	mi.mesh = _wall_variants[slot]
	mi.material_override = rock_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root

## 共享石墙网格（MultiMesh 河道石岸用；固定种子，所有实例一致）
static func wall_mesh() -> ArrayMesh:
	if _wall_mesh_cache == null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20261030
		_wall_mesh_cache = _build_wall_mesh(rng)
	return _wall_mesh_cache

static func _build_wall_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock := _rock_sphere()
	# [中心高度, 水平半径, 竖向比例, 石块数]
	var layers := [
		[0.36, 0.50, 0.50, 2],
		[1.04, 0.44, 0.42, 2],
		[1.68, 0.37, 0.35, 1],
		[2.22, 0.31, 0.30, 1],
		[2.68, 0.25, 0.25, 1],
	]
	for l in layers:
		var y: float = float(l[0])
		var rp: float = float(l[1])
		var ry: float = float(l[2])
		var count: int = int(l[3])
		for i in range(count):
			var ang: float = rng.randf_range(0.0, TAU) + float(i) * PI / float(count)
			var off: float = rp * rng.randf_range(0.05, 0.22)
			var p := Vector3(cos(ang) * off, y + rng.randf_range(-0.05, 0.05), sin(ang) * off)
			var sc := Vector3(rp * rng.randf_range(0.82, 1.16), ry * rng.randf_range(0.88, 1.22), rp * rng.randf_range(0.78, 1.06))
			_append(st, rock, p, sc, Vector3(rng.randf_range(-0.28, 0.28), rng.randf_range(0.0, TAU), rng.randf_range(-0.28, 0.28)))
	# 基底碎石（破掉"一根柱子直接插在地上"）
	for i in range(4):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(0.36, 0.62)
		var rr: float = rng.randf_range(0.08, 0.15)
		_append(st, rock, Vector3(cos(a) * d, rr * 0.55, sin(a) * d), Vector3(rr, rr * 0.72, rr),
			Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0))
	# 墙脚外扩的苔藓/碎石裙，让墙根从石墙自然过渡到草地
	_append_ground_apron(st, 0.82, rng, 10)
	st.append_from(_disc(1.06, 0.05, 14), 0, Transform3D(Basis(), Vector3(0.0, 0.025, 0.0)))
	return st.commit()

# ==================== 草丛 ====================

## 灌木丛：16 个蓬松叶团 + 18 根外围草叶 + 苔藓土盘（直径 ≈ 2.4，与 2×2 碰撞/区域一致）
static func bush_visual(seed_val: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "BushVisual"
	var slot: int = absi(seed_val) % 10
	while _bush_variants.size() <= slot:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3571 + _bush_variants.size() * 15485863
		_bush_variants.append(_build_bush_mesh(rng))
	var mi := MeshInstance3D.new()
	mi.mesh = _bush_variants[slot]
	mi.material_override = leaf_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root

static func _build_bush_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blob := _leaf_blob()
	for i in range(12):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = sqrt(rng.randf()) * 0.60
		var y: float = rng.randf_range(0.28, 1.32) * (1.0 - d * 0.38)
		var rr: float = rng.randf_range(0.30, 0.56) * (1.06 - y * 0.24)
		var p := Vector3(cos(a) * d, y + rr * 0.38, sin(a) * d)
		_append(st, blob, p, Vector3(rr, rr * rng.randf_range(0.78, 1.15), rr),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, TAU), rng.randf_range(-0.3, 0.3)))
	# 外围草叶：三棱尖锥，向外倾斜，让轮廓不整齐
	var blade := _blade_cone()
	for i in range(18):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(0.50, 0.92)
		var h: float = rng.randf_range(0.55, 1.45)
		var tilt: float = rng.randf_range(0.12, 0.55)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, tilt)
		var p := Vector3(cos(a) * d, h * 0.5, sin(a) * d)
		st.append_from(blade, 0, Transform3D(basis.scaled(Vector3(1.0, h, 1.0)), p))
	# 苔藓土盘
	st.append_from(_disc(0.95, 0.05, 12), 0, Transform3D(Basis(), Vector3(0.0, 0.02, 0.0)))
	return st.commit()

# ==================== 环境草簇（MultiMesh 用） ====================

## 9 根草叶组成的草簇；高度 ≈ 1.15，由 MapVisuals._make_cluster 统一缩放到目标高度
static func grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade := _blade_cone()
	for i in range(9):
		var a: float = TAU * float(i) / 9.0 + 0.4 * sin(float(i) * 2.1)
		var d: float = 0.05 + 0.10 * float(i % 3)
		var h: float = 0.70 + 0.45 * fmod(float(i) * 0.37, 1.0)
		var tilt: float = 0.10 + 0.32 * fmod(float(i) * 0.23, 1.0)
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, tilt)
		st.append_from(blade, 0, Transform3D(basis.scaled(Vector3(1.0, h, 1.0)), Vector3(cos(a) * d, h * 0.5, sin(a) * d)))
	return st.commit()


static var _hq_variants: Array = []

## 高地外周墙：更高规格的石墙（双层基座 + 8 层错缝方石 + 檐口压顶 + 边柱）
static func wall_visual_hq(seed_val: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "WallVisualHQ"
	var slot: int = absi(seed_val) % 4
	while _hq_variants.size() <= slot:
		var rng := RandomNumberGenerator.new()
		rng.seed = 31337 + _hq_variants.size() * 2654435
		_hq_variants.append(_build_wall_mesh_hq(rng))
	var mi := MeshInstance3D.new()
	mi.mesh = _hq_variants[slot]
	mi.material_override = rock_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root

static func _build_wall_mesh_hq(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	# 双层基座（外挑，压住地面）
	_append(st, box, Vector3(0, 0.16, 0), Vector3(1.42, 0.32, 1.06), Vector3(0, rng.randf_range(-0.05, 0.05), 0))
	_append(st, box, Vector3(0, 0.44, 0), Vector3(1.26, 0.24, 0.96), Vector3(0, rng.randf_range(-0.04, 0.04), 0))
	# 8 层错缝方石
	var y: float = 0.56
	for course in range(8):
		var n: int = 3 if course % 2 == 0 else 2
		var h: float = 0.25
		var seg: float = 1.12 / float(n)
		for i in range(n):
			var xoff: float = (float(i) - float(n - 1) * 0.5) * seg
			var w: float = seg * rng.randf_range(0.90, 1.02)
			_append(st, box, Vector3(xoff + rng.randf_range(-0.015, 0.015), y + h * 0.5, rng.randf_range(-0.02, 0.02)),
				Vector3(w, h * rng.randf_range(0.95, 1.02), 0.88 + rng.randf_range(-0.04, 0.04)),
				Vector3(0, rng.randf_range(-0.02, 0.02), 0))
		y += h
	# 檐口压顶（两级外挑）
	_append(st, box, Vector3(0, y + 0.10, 0), Vector3(1.34, 0.20, 1.04), Vector3.ZERO)
	_append(st, box, Vector3(0, y + 0.27, 0), Vector3(1.12, 0.14, 0.88), Vector3.ZERO)
	y += 0.34
	# 两侧边柱（竖向石条，增加层次）
	for sx in [-1.0, 1.0]:
		_append(st, box, Vector3(sx * 0.50, y * 0.46, 0.0), Vector3(0.20, y * 0.88, 0.99), Vector3.ZERO)
	# 基底碎石 + 苔藓土盘
	var rock := _rock_sphere()
	for i in range(4):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(0.44, 0.72)
		var rr: float = rng.randf_range(0.09, 0.16)
		_append(st, rock, Vector3(cos(a) * d, rr * 0.5, sin(a) * d), Vector3(rr, rr * 0.7, rr),
			Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0))
	_append_ground_apron(st, 0.86, rng, 10)
	st.append_from(_disc(1.10, 0.05, 14), 0, Transform3D(Basis(), Vector3(0.0, 0.025, 0.0)))
	return st.commit()

# ==================== 外周连续城墙 ====================

## 外周墙段：长度与 2m 落点完全一致，端面平齐；墙体/压顶/垛口/错缝条石共用同一网格，
## 相邻墙段在端面无缝相接。石材质感由世界坐标噪声着色，跨墙段自然连续。
static func outer_wall_visual(length: float = 2.0) -> Node3D:
	var key := int(round(length * 100.0))
	if not _outer_wall_cache.has(key):
		_outer_wall_cache[key] = _build_outer_wall_mesh(length)
	var root := Node3D.new()
	root.name = "OuterWallVisual"
	var mi := MeshInstance3D.new()
	mi.mesh = _outer_wall_cache[key]
	mi.material_override = rock_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root


static func _build_outer_wall_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var h := length * 0.5
	# 基座与连续墙芯：墙芯端面正好落在墙段边界，和左右墙段贴合
	_append(st, box, Vector3(0.0, 0.14, 0.0), Vector3(length, 0.28, 1.20), Vector3.ZERO)
	_append(st, box, Vector3(0.0, 1.26, 0.0), Vector3(length, 2.00, 0.90), Vector3.ZERO)
	# 正反两面错缝条石：只做浅浮雕，不切断墙芯，避免从缝里透光
	var courses := 7
	var per_course := 3
	for c in range(courses):
		var y: float = 0.38 + float(c) * 0.26
		for i in range(per_course):
			var x: float = -h + (float(i) + 0.5) * length / float(per_course)
			var w: float = length / float(per_course) - 0.028
			for side in [-1.0, 1.0]:
				_append(st, box, Vector3(x, y, side * 0.47), Vector3(w, 0.225, 0.10), Vector3.ZERO)
	# 中柱：压住每段中缝的单调感
	for side in [-1.0, 1.0]:
		_append(st, box, Vector3(0.0, 1.27, side * 0.49), Vector3(0.20, 1.90, 0.10), Vector3.ZERO)
	# 双层压顶 + 三个垛口
	_append(st, box, Vector3(0.0, 2.34, 0.0), Vector3(length, 0.18, 1.14), Vector3.ZERO)
	_append(st, box, Vector3(0.0, 2.49, 0.0), Vector3(length, 0.12, 1.02), Vector3.ZERO)
	var merlons := 3 if length > 1.8 else 2
	var mw := length / float(merlons) * 0.58
	for i in range(merlons):
		var x: float = -h + (float(i) + 0.5) * length / float(merlons)
		_append(st, box, Vector3(x, 2.72, 0.0), Vector3(mw, 0.36, 1.00), Vector3.ZERO)
	# 基部碎石（完全收在段内，不越过端面）
	var rock := _rock_sphere()
	for i in range(4):
		var sx: float = (-0.72 + 0.48 * float(i)) * h
		var sz: float = 0.56 if i % 2 == 0 else -0.56
		var rr: float = 0.075 + 0.025 * float(i % 2)
		_append(st, rock, Vector3(sx, rr * 0.55, sz), Vector3(rr, rr * 0.62, rr),
			Vector3(float(i) * 1.7, float(i) * 2.1, 0.0))
	# 连续城墙的墙脚碎石/苔藓带：沿两侧铺低矮扁石，打破 1.2m 基座的直线切口
	var apron_rng := RandomNumberGenerator.new()
	apron_rng.seed = int(round(length * 1000.0)) + 913
	_append_ground_apron(st, h, apron_rng, maxi(6, int(round(length * 4.0))), 0.66)
	return st.commit()

## 墙端小柱：连续墙两端收口（基座 + 柱身 + 柱头 + 顶饰），与墙体同一石材质感
static func pillar_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "WallPillar"
	if _pillar_mesh == null:
		_pillar_mesh = _build_pillar_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _pillar_mesh
	mi.material_override = rock_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root

static func _build_pillar_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_append(st, box, Vector3(0.0, 0.13, 0.0), Vector3(0.66, 0.26, 0.66), Vector3.ZERO)   # 基座
	_append(st, box, Vector3(0.0, 1.15, 0.0), Vector3(0.44, 1.80, 0.44), Vector3.ZERO)   # 柱身
	_append(st, box, Vector3(0.0, 2.13, 0.0), Vector3(0.58, 0.16, 0.58), Vector3.ZERO)   # 柱头
	_append(st, box, Vector3(0.0, 2.31, 0.0), Vector3(0.34, 0.20, 0.34), Vector3.ZERO)   # 顶饰
	# 柱脚碎石裙 + 苔藓土盘
	var rock := _rock_sphere()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	for i in range(6):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = rng.randf_range(0.38, 0.66)
		var rr: float = rng.randf_range(0.08, 0.16)
		_append(st, rock, Vector3(cos(a) * d, rr * 0.5, sin(a) * d), Vector3(rr, rr * 0.65, rr),
			Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), 0.0))
	st.append_from(_disc(0.92, 0.05, 12), 0, Transform3D(Basis(), Vector3(0.0, 0.025, 0.0)))
	return st.commit()

# ==================== 内部工具 ====================

static func _append(st: SurfaceTool, mesh: Mesh, pos: Vector3, sc: Vector3, rot: Vector3) -> void:
	var b := Basis.from_euler(rot).scaled(sc)
	st.append_from(mesh, 0, Transform3D(b, pos))

static func _rock_sphere() -> SphereMesh:
	if _rock_mesh == null:
		_rock_mesh = SphereMesh.new()
		_rock_mesh.radius = 1.0
		_rock_mesh.height = 2.0
		_rock_mesh.radial_segments = 5
		_rock_mesh.rings = 3
	return _rock_mesh

static func _leaf_blob() -> SphereMesh:
	if _blob_mesh == null:
		_blob_mesh = SphereMesh.new()
		_blob_mesh.radius = 1.0
		_blob_mesh.height = 2.0
		_blob_mesh.radial_segments = 6
		_blob_mesh.rings = 3
	return _blob_mesh

static func _blade_cone() -> CylinderMesh:
	if _blade_mesh == null:
		_blade_mesh = CylinderMesh.new()
		_blade_mesh.top_radius = 0.0
		_blade_mesh.bottom_radius = 0.05
		_blade_mesh.height = 1.0
		_blade_mesh.radial_segments = 3
		_blade_mesh.rings = 1
	return _blade_mesh

static func _disc(radius: float, height: float, segs: int) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.08
	cm.height = height
	cm.radial_segments = segs
	return cm


## 墙脚裙：在墙体基线外圈铺低矮、压扁的不规则碎石/土块，打断直墙与地面的硬切口。
## 复用墙体材质，低处会被岩石 shader 自动染成苔藓/泥土。
static func _append_ground_apron(st: SurfaceTool, half_len: float, rng: RandomNumberGenerator,
		count: int, side_z: float = 0.0) -> void:
	var rock := _rock_sphere()
	for i in range(count):
		var x: float = rng.randf_range(-half_len, half_len)
		var side: float = -1.0 if (i % 2 == 1) else 1.0
		var z: float = side * (side_z if side_z > 0.0 else rng.randf_range(0.46, 0.82))
		var rr: float = rng.randf_range(0.10, 0.24)
		var sc := Vector3(rr * rng.randf_range(1.35, 2.15), rr * rng.randf_range(0.32, 0.58),
			rr * rng.randf_range(0.95, 1.55))
		_append(st, rock, Vector3(x, sc.y * 0.38, z), sc,
			Vector3(rng.randf_range(-0.18, 0.18), rng.randf_range(0.0, TAU), rng.randf_range(-0.18, 0.18)))

# ==================== 青砖铺装（防御塔外周地面） ====================
# 单块薄圆盘 + 世界坐标画砖缝的 shader：不同塔/相邻塔的砖纹能自然接上，且只有 1 个 draw call。
const _BRICK_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 brick_a : source_color = vec4(0.34, 0.43, 0.45, 1.0);
uniform vec4 brick_b : source_color = vec4(0.25, 0.33, 0.35, 1.0);
uniform vec4 mortar_col : source_color = vec4(0.14, 0.17, 0.18, 1.0);
uniform vec4 moss_col : source_color = vec4(0.20, 0.30, 0.18, 1.0);
uniform float brick_w = 0.86;
uniform float brick_h = 0.42;

varying vec3 wp;

__NOISE__

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x, wp.z) / vec2(brick_w, brick_h);
	p.x += mod(floor(p.y), 2.0) * 0.5;
	vec2 id = floor(p);
	vec2 f = fract(p);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float mortar = 1.0 - smoothstep(0.02, 0.085, edge);
	float h = hash13(vec3(id.x, id.y, 3.0));
	vec3 col = mix(brick_a.rgb, brick_b.rgb, h);
	col *= 0.86 + 0.26 * hash13(vec3(id.x * 1.7, id.y * 2.3, 11.0));
	col = mix(col, moss_col.rgb, step(0.88, h) * 0.6);
	col = mix(col, mortar_col.rgb, mortar * 0.92);
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.96, mortar);
	SPECULAR = 0.30;
}
"""

static var _pave_mat: ShaderMaterial = null
static var _pave_meshes: Dictionary = {}

static func brick_material() -> ShaderMaterial:
	if _pave_mat != null:
		return _pave_mat
	var sh := Shader.new()
	sh.code = _BRICK_CODE.replace("__NOISE__", _NOISE_GLSL)
	_pave_mat = ShaderMaterial.new()
	_pave_mat.shader = sh
	return _pave_mat

## 防御塔外周的青砖圆台（很薄，贴着地面，避免和接地暗影/地形打架）
static func pave_visual(radius: float) -> Node3D:
	var key := int(round(radius * 10.0))
	if not _pave_meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius * 1.02
		cm.height = 0.05
		cm.radial_segments = 56
		_pave_meshes[key] = cm
	var root := Node3D.new()
	root.name = "TurretPave"
	var mi := MeshInstance3D.new()
	mi.mesh = _pave_meshes[key]
	mi.material_override = brick_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

## 防御塔底座的「圆环状砖」：以塔心为圆心的同心环砖薄环（中间留出塔基洞），
## 贴地 5cm 厚；顶面高度由调用方给（路面 0.152 / 高地砖面 0.177）。
static var _pave_ring_meshes: Dictionary = {}

static func turret_ring_pave(center: Vector3, inner_r: float, outer_r: float, top_y: float) -> Node3D:
	var key := "%d_%d" % [int(round(inner_r * 10.0)), int(round(outer_r * 10.0))]
	if not _pave_ring_meshes.has(key):
		_pave_ring_meshes[key] = _build_ring_slab(inner_r, outer_r, 0.05, 84)
	var root := Node3D.new()
	root.name = "TurretRingPave"
	var mi := MeshInstance3D.new()
	mi.mesh = _pave_ring_meshes[key]
	# 同心环砖（与高地/兵线擂台同一套极坐标砖纹），中心徽半径设为 0 → 环上无徽记
	mi.material_override = _ring_brick_double_sided(center, outer_r)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(center.x, top_y, center.z)
	root.add_child(mi)
	return root

## 圆环薄板：顶面 + 底面 + 内外侧壁（双面材质，绕序不影响可见性）
static func _build_ring_slab(inner_r: float, outer_r: float, thickness: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := 0.0
	var bot := -thickness
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		# 顶面（法线朝上）
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(c0.x * inner_r, top, c0.y * inner_r))
		st.add_vertex(Vector3(c1.x * inner_r, top, c1.y * inner_r))
		st.add_vertex(Vector3(c0.x * outer_r, top, c0.y * outer_r))
		st.add_vertex(Vector3(c1.x * inner_r, top, c1.y * inner_r))
		st.add_vertex(Vector3(c1.x * outer_r, top, c1.y * outer_r))
		st.add_vertex(Vector3(c0.x * outer_r, top, c0.y * outer_r))
		# 底面（法线朝下）
		st.set_normal(Vector3.DOWN)
		st.add_vertex(Vector3(c0.x * inner_r, bot, c0.y * inner_r))
		st.add_vertex(Vector3(c0.x * outer_r, bot, c0.y * outer_r))
		st.add_vertex(Vector3(c1.x * inner_r, bot, c1.y * inner_r))
		st.add_vertex(Vector3(c1.x * inner_r, bot, c1.y * inner_r))
		st.add_vertex(Vector3(c0.x * outer_r, bot, c0.y * outer_r))
		st.add_vertex(Vector3(c1.x * outer_r, bot, c1.y * outer_r))
		# 外侧壁（法线朝外）/ 内侧壁（法线朝内）
		for r in [outer_r, inner_r]:
			var nr: float = 1.0 if r == outer_r else -1.0
			st.set_normal(Vector3(c0.x * nr, 0.0, c0.y * nr))
			st.add_vertex(Vector3(c0.x * r, bot, c0.y * r))
			st.add_vertex(Vector3(c0.x * r, top, c0.y * r))
			st.add_vertex(Vector3(c1.x * r, bot, c1.y * r))
			st.add_vertex(Vector3(c1.x * r, bot, c1.y * r))
			st.add_vertex(Vector3(c0.x * r, top, c0.y * r))
			st.add_vertex(Vector3(c1.x * r, top, c1.y * r))
	st.index()
	return st.commit()

static func _ring_brick_double_sided(center: Vector3, radius: float) -> ShaderMaterial:
	var mat := ring_brick_material(center, radius, 0.62, 0.0)
	var sh := (mat.shader as Shader).duplicate() as Shader
	sh.code = sh.code.replace("render_mode diffuse_burley, specular_schlick_ggx;",
		"render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;")
	mat.shader = sh
	return mat

# ==================== 兵线交汇圆形擂台（青砖） ====================
# 极坐标砖纹：同心环 + 错缝径向砖 + 中心圆徽 + 外圈石沿，单塔只 1 个 draw call。
const _ARENA_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 arena_center = vec2(0.0, 0.0);
uniform float arena_radius = 7.2;
uniform vec4 brick_a : source_color = vec4(0.34, 0.43, 0.45, 1.0);
uniform vec4 brick_b : source_color = vec4(0.25, 0.33, 0.35, 1.0);
uniform vec4 mortar_col : source_color = vec4(0.14, 0.17, 0.18, 1.0);
uniform vec4 moss_col : source_color = vec4(0.20, 0.30, 0.18, 1.0);
uniform vec4 rim_col : source_color = vec4(0.36, 0.34, 0.31, 1.0);
uniform float ring_w = 0.62;
uniform float medal_r = 1.52;
uniform float medal_strength = 0.75;

varying vec3 wp;

__NOISE__

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 d = vec2(wp.x - arena_center.x, wp.z - arena_center.y);
	float r = max(length(d), 0.02);
	float ridx = floor(r / ring_w);
	float rt = fract(r / ring_w);
	float circ = max(6.0, floor(6.2831853 * max(r, 0.6) / 0.90));
	float ang = atan(d.y, d.x) / 6.2831853;
	float shift = 0.5 * mod(ridx, 2.0);
	float at = fract(ang * circ + shift);
	float arc = 6.2831853 * max(r, 0.6) / circ;
	float edge = min(min(rt, 1.0 - rt) * ring_w, min(at, 1.0 - at) * arc);
	float mortar = 1.0 - smoothstep(0.015, 0.075, edge);
	float h = hash13(vec3(ridx, floor(ang * circ + shift), 9.0));
	vec3 col = mix(brick_a.rgb, brick_b.rgb, h);
	col *= 0.87 + 0.24 * hash13(vec3(ridx * 2.1, 3.0, h * 17.0));
	col = mix(col, moss_col.rgb, step(0.92, h) * 0.45);
	col = mix(col, mortar_col.rgb, mortar * 0.88);
	// 中心圆徽
	float med = 1.0 - smoothstep(medal_r, medal_r + 0.14, r);
	col = mix(col, mortar_col.rgb * 0.85, med * medal_strength);
	// 外圈石沿（擂台边）
	float rim = smoothstep(arena_radius - 0.90, arena_radius - 0.55, r);
	float rim_tone = 0.82 + 0.30 * hash13(vec3(floor(ang * 48.0), 2.0, 4.0));
	col = mix(col, rim_col.rgb * rim_tone, rim);
	ALBEDO = col;
	ROUGHNESS = mix(0.60, 0.95, max(mortar, rim));
	SPECULAR = 0.32;
}
"""

static var _arena_meshes: Dictionary = {}

## 极坐标青砖材质：以 center 为圆心的同心环砖（radius 只用于画最外圈石沿）
static func ring_brick_material(center: Vector3, radius: float, ring_w: float = 0.62,
		medal_r: float = 1.52) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = _ARENA_CODE.replace("__NOISE__", _NOISE_GLSL)
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("arena_center", Vector2(center.x, center.z))
	mat.set_shader_parameter("arena_radius", radius)
	mat.set_shader_parameter("ring_w", ring_w)
	mat.set_shader_parameter("medal_r", medal_r)
	return mat

## 高地青砖：整体呈以水晶为圆心的同心圆环（去掉外圈石沿与中心徽的强对比）
static func hq_ring_brick_material(crystal_pos: Vector3) -> ShaderMaterial:
	var mat := ring_brick_material(crystal_pos, 999.0, 1.05, 4.2)
	mat.set_shader_parameter("medal_strength", 0.35)
	return mat

## 兵线交汇处的圆形青砖擂台：薄圆台压住分路路面与河道，顶面略带高差
static func arena_visual(center: Vector3, radius: float) -> Node3D:
	var root := Node3D.new()
	root.name = "LaneArena"
	var key := int(round(radius * 10.0))
	if not _arena_meshes.has(key):
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius * 1.015
		cm.height = 0.26
		cm.radial_segments = 64
		_arena_meshes[key] = cm
	var mi := MeshInstance3D.new()
	mi.mesh = _arena_meshes[key]
	mi.material_override = ring_brick_material(center, radius)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.07      # 顶面 ≈ 0.20：压住分路路面(0.14)和河道(0.02)
	root.add_child(mi)
	return root

# ==================== 草丛小花 ====================
static var _flower_mat: StandardMaterial3D = null
static var _flower_variants: Array = []

static func flower_material() -> StandardMaterial3D:
	if _flower_mat != null:
		return _flower_mat
	_flower_mat = StandardMaterial3D.new()
	_flower_mat.vertex_color_use_as_albedo = true
	_flower_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flower_mat.roughness = 0.65
	_flower_mat.emission_enabled = true
	_flower_mat.emission = Color(0.40, 0.32, 0.34)
	_flower_mat.emission_energy_multiplier = 0.35
	return _flower_mat

## 草丛里的小花：几朵低面数花朵（顶点色），整丛共用一份网格，1 个 draw call
static func flower_visual(seed_val: int = 0) -> Node3D:
	var slot: int = absi(seed_val) % 4
	while _flower_variants.size() <= slot:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9173 + _flower_variants.size() * 15486071
		_flower_variants.append(_build_flower_mesh(rng))
	var root := Node3D.new()
	root.name = "BushFlowers"
	var mi := MeshInstance3D.new()
	mi.mesh = _flower_variants[slot]
	mi.material_override = flower_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

static func _build_flower_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette := [
		Color(0.95, 0.62, 0.78), Color(0.96, 0.94, 0.88),
		Color(0.84, 0.72, 0.98), Color(0.99, 0.86, 0.45),
	]
	for i in range(9):
		var a: float = rng.randf_range(0.0, TAU)
		var d: float = sqrt(rng.randf()) * 0.62
		var y: float = rng.randf_range(0.62, 1.22)
		var c := Vector3(cos(a) * d, y, sin(a) * d)
		var size := rng.randf_range(0.17, 0.27)
		_add_flat_quad(st, c, size, rng.randf_range(0.0, TAU), rng.randf_range(-0.30, 0.30), palette[i % palette.size()])
		_add_flat_quad(st, c + Vector3(0.0, 0.025, 0.0), size * 0.55,
			rng.randf_range(0.0, TAU), rng.randf_range(-0.35, 0.35), Color(0.99, 0.92, 0.48))
	return st.commit()

## 水平小四边形（两面可见）：花瓣/花心用
static func _add_flat_quad(st: SurfaceTool, c: Vector3, size: float, rot_y: float, tilt: float, col: Color) -> void:
	var basis := Basis(Vector3.UP, rot_y) * Basis(Vector3.RIGHT, tilt)
	var n := (basis * Vector3.UP).normalized()
	var h := size * 0.5
	var corners := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(basis * corners[idx] + c)

# ==================== 墙体装饰（常春藤垂挂 + 顶部苔草） ====================
static var _wall_decor_variants: Array = []

## 连续墙上的绿色装饰：垂下来的常春藤团 + 压顶苔草，与墙同叶材质、随风摆动
static func wall_decor_visual(seed_val: int = 0) -> Node3D:
	var slot: int = absi(seed_val) % 3
	while _wall_decor_variants.size() <= slot:
		var rng := RandomNumberGenerator.new()
		rng.seed = 6011 + _wall_decor_variants.size() * 7717
		_wall_decor_variants.append(_build_wall_decor_mesh(rng))
	var root := Node3D.new()
	root.name = "WallDecor"
	var mi := MeshInstance3D.new()
	mi.mesh = _wall_decor_variants[slot]
	mi.material_override = leaf_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return root

static func _build_wall_decor_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blob := _leaf_blob()
	# 墙面垂藤：贴着正/反墙面，从上往下越来越小
	for i in range(6):
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var x: float = rng.randf_range(-0.78, 0.78)
		var y: float = rng.randf_range(0.95, 2.20)
		var rr: float = rng.randf_range(0.15, 0.28)
		_append(st, blob, Vector3(x, y, side * 0.46),
			Vector3(rr, rr * rng.randf_range(0.75, 1.25), rr * 0.65),
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(0.0, TAU), rng.randf_range(-0.4, 0.4)))
	# 压顶苔草
	for i in range(4):
		var x2: float = rng.randf_range(-0.80, 0.80)
		var rr2: float = rng.randf_range(0.12, 0.22)
		_append(st, blob, Vector3(x2, 2.52, rng.randf_range(-0.30, 0.30)),
			Vector3(rr2, rr2 * 0.55, rr2), Vector3(0.0, rng.randf_range(0.0, TAU), 0.0))
	return st.commit()
