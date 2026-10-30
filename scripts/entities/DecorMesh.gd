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
	ALBEDO = base;
	ROUGHNESS = 0.95 - 0.12 * moss;
	SPECULAR = 0.14;
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
	# 苔藓土盘
	st.append_from(_disc(0.86, 0.06, 12), 0, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)))
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
	st.append_from(_disc(0.92, 0.06, 12), 0, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)))
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
