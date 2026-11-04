class_name MapVisuals
extends RefCounted

## 王者峡谷地面视觉层（不改任何 gameplay 逻辑，只换材质/光照/装饰）
## 1. 程序化「布局贴图」：草地/土路/高地砖石/河道一次画好，所有地面平面共用同一张图、
##    按世界坐标采样 → 平面之间没有硬接缝（原先是纯色 PlaneMesh 拼硬边）
## 2. 噪声细节贴图 + 法线贴图：近看有材质层次，不再像塑料板
## 3. 环境：天空盒 + 天空环境光 + ACES 色调映射 + 深度雾 + 暖阳光/冷补光
## 4. 装饰：现成 glb（草/墙/罐）用 MultiMesh 批量铺，移动端友好
## 5. 河道水面 shader：波高场解析法线 + 菲涅尔天空反射 + 顺流闪点 + 贴岸泡沫；
##    两岸另有湿沙滩、半浸礁石、芦苇、睡莲（MultiMesh）
## 注意：project.godot 用 rendering_method="mobile"，SSAO/SSIL/体积雾不可用。

const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const MAP_HALF := 60.0
const LAYOUT_SIZE := 1024
const ISLAND_RADIUS := 105.0

static var _layout_tex: ImageTexture
static var _detail_tex: NoiseTexture2D
static var _normal_tex: NoiseTexture2D
static var _ground_shader: Shader
static var _brick_shader: Shader
static var _water_shader: Shader
static var _water_normal_tex: NoiseTexture2D
static var _sun_light: DirectionalLight3D
static var _fill_light: DirectionalLight3D

# 逆光参数：太阳放在相机正前方的低空，光线朝相机方向打 → 角色边缘轮廓光、地面长投影；
# 补光放在相机后上方，只轻轻提亮朝向镜头的一面，避免正面死黑。
const SUN_ELEVATION_DEG := 38.0
const FILL_ELEVATION_DEG := 22.0

# ================= 环境 / 光照 =================

static func setup_environment(parent: Node3D) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.33, 0.63)
	sky_mat.sky_horizon_color = Color(0.80, 0.78, 0.70)
	sky_mat.sky_curve = 0.13
	# 浮空岛：地平线以下不再是草地，而是远天/云海，让岛外一眼看到天空
	sky_mat.ground_bottom_color = Color(0.10, 0.22, 0.42)
	sky_mat.ground_horizon_color = Color(0.52, 0.68, 0.86)
	sky_mat.sun_angle_max = 16.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.46
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# 只保留中高频光晕，避免整个画面发灰（层级 1..7）
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.0)
	env.set_glow_level(2, 0.55)
	env.set_glow_level(3, 0.85)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.3)
	env.set_glow_level(6, 0.0)
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.73, 0.76)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0085
	env.fog_sun_scatter = 0.20
	env.fog_sky_affect = 0.45
	env.fog_depth_begin = 6.0
	env.fog_depth_end = 130.0
	env.fog_depth_curve = 1.35
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	# 暖色主光（软阴影）：默认相机朝 -Z，太阳放正前方（+180°），开局即逆光
	var sun := DirectionalLight3D.new()
	sun.name = "SunBacklight"
	sun.rotation_degrees = Vector3(-SUN_ELEVATION_DEG, 180.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 2.35
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	# 2 级级联 + 60m 视距：同性能下阴影更锐利（4 级级联在 90m 上摊薄了纹素）
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	parent.add_child(sun)

	# 冷色补光（无阴影）：从相机后上方补正面，压住逆光造成的死黑
	var fill := DirectionalLight3D.new()
	fill.name = "CameraFill"
	fill.rotation_degrees = Vector3(-FILL_ELEVATION_DEG, 0.0, 0.0)
	fill.light_color = Color(0.58, 0.68, 0.95)
	fill.light_energy = 0.58
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	parent.add_child(fill)

	_sun_light = sun
	_fill_light = fill

# 每帧把主光锁在相机正前方（水平方向），形成真正的相机逆光；补光锁在相机后方。
static func update_backlight_for_camera(cam: Camera3D) -> void:
	if cam == null or _sun_light == null or not is_instance_valid(_sun_light):
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.000001:
		return
	fwd = fwd.normalized()
	# 相机水平朝向：Godot 里 yaw 旋转的 forward = (-sin yaw, 0, -cos yaw)
	var yaw := rad_to_deg(atan2(-fwd.x, -fwd.z))
	_sun_light.rotation_degrees = Vector3(-SUN_ELEVATION_DEG, yaw + 180.0, 0.0)
	if _fill_light != null and is_instance_valid(_fill_light):
		_fill_light.rotation_degrees = Vector3(-FILL_ELEVATION_DEG, yaw, 0.0)

# ================= 地面材质 =================

static func ground_material(bump: float = 0.0) -> ShaderMaterial:
	if _ground_shader == null:
		_ground_shader = _build_ground_shader()
	if _layout_tex == null:
		_layout_tex = ImageTexture.create_from_image(_paint_layout())
	if _detail_tex == null:
		var dn := FastNoiseLite.new()
		dn.seed = 11
		dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		dn.frequency = 0.055
		var dt := NoiseTexture2D.new()
		dt.noise = dn
		dt.width = 512
		dt.height = 512
		dt.seamless = true
		_detail_tex = dt
	if _normal_tex == null:
		var nn := FastNoiseLite.new()
		nn.seed = 23
		nn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nn.frequency = 0.09
		var nt := NoiseTexture2D.new()
		nt.noise = nn
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 8.0
		_normal_tex = nt
	var mat := ShaderMaterial.new()
	mat.shader = _ground_shader
	mat.set_shader_parameter("layout_tex", _layout_tex)
	mat.set_shader_parameter("detail_tex", _detail_tex)
	mat.set_shader_parameter("normal_tex", _normal_tex)
	mat.set_shader_parameter("tint", Color(1, 1, 1, 1))
	mat.set_shader_parameter("map_half", MAP_HALF)
	mat.set_shader_parameter("bump_amount", bump)
	return mat


## 浮空岛顶面：沿用同一张地面布局图，只额外把圆岛外的片元丢弃，露出天空。
static func island_ground_material() -> ShaderMaterial:
	var mat := ground_material(0.28)
	mat.set_shader_parameter("island_edge", 1.0)
	mat.set_shader_parameter("island_radius", ISLAND_RADIUS)
	return mat

# 高地/基地台座：石砖铺装（错缝砖块 + 灰缝 + 苔痕），与其他石质建筑同族
static func high_ground_material() -> ShaderMaterial:
	if _brick_shader == null:
		_brick_shader = Shader.new()
		_brick_shader.code = _BRICK_CODE
	if _detail_tex == null:
		var dn := FastNoiseLite.new()
		dn.seed = 11
		dn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		dn.frequency = 0.055
		var dt := NoiseTexture2D.new()
		dt.noise = dn
		dt.width = 256
		dt.height = 256
		dt.seamless = true
		_detail_tex = dt
	if _normal_tex == null:
		var nn := FastNoiseLite.new()
		nn.seed = 23
		nn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nn.frequency = 0.09
		var nt := NoiseTexture2D.new()
		nt.noise = nn
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		_normal_tex = nt
	var mat := ShaderMaterial.new()
	mat.shader = _brick_shader
	mat.set_shader_parameter("detail_tex", _detail_tex)
	mat.set_shader_parameter("normal_tex", _normal_tex)
	mat.set_shader_parameter("map_half", MAP_HALF)
	return mat

const _BRICK_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D detail_tex : filter_linear, repeat_enable;
uniform sampler2D normal_tex : filter_linear, repeat_enable;
uniform float map_half = 60.0;
uniform vec3 brick_a : source_color = vec3(0.455, 0.415, 0.355);
uniform vec3 brick_b : source_color = vec3(0.545, 0.495, 0.425);
uniform vec3 brick_c : source_color = vec3(0.360, 0.335, 0.300);
uniform vec3 mortar : source_color = vec3(0.180, 0.172, 0.158);
uniform vec3 moss : source_color = vec3(0.215, 0.265, 0.170);
uniform float brick_len = 0.78;
uniform float brick_wid = 0.40;
uniform float joint = 0.045;

varying vec3 wp;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 错缝砖：按世界 XZ 坐标铺砖，行间半砖错位
	float row = floor(wp.z / brick_wid);
	float shift = mod(row, 2.0) * 0.5 * brick_len;
	vec2 cell = vec2(floor((wp.x + shift) / brick_len), row);
	vec2 f = vec2(fract((wp.x + shift) / brick_len), fract(wp.z / brick_wid));
	// 到灰缝的距离（米）
	vec2 dst = min(f, vec2(1.0) - f) * vec2(brick_len, brick_wid);
	float edge = min(dst.x, dst.y);
	float face = smoothstep(joint * 0.55, joint * 1.35, edge);
	float h1 = hash21(cell);
	float h2 = hash21(cell + vec2(11.3, 7.7));
	// 砖面色：三种石色随机 + 逐砖明暗抖动
	vec3 bc = mix(brick_a, brick_b, step(0.55, h1));
	bc = mix(bc, brick_c, step(0.86, h1));
	bc *= 0.90 + 0.20 * h2;
	// 砖面细噪 + 磨损（局部变暗）
	vec2 uv = wp.xz * 0.42;
	float n = texture(detail_tex, uv).r;
	float wear = texture(detail_tex, wp.xz * 0.11).r;
	bc *= 0.82 + 0.30 * n;
	// 边缘磨圆：靠近灰缝处压暗，砖有厚度感
	float round_dark = mix(0.72, 1.0, smoothstep(0.0, joint * 2.2, edge));
	bc *= round_dark;
	// 灰缝里长苔：越靠缝越绿，且用低频噪声决定哪里长
	float mossmask = (1.0 - face) * smoothstep(0.35, 0.72, wear);
	vec3 mc = mix(mortar, moss, mossmask * 0.85);
	ALBEDO = mix(mc, bc, face);
	ROUGHNESS = mix(0.96, 0.80, face);
	SPECULAR = 0.18;
	// 砖面凹凸（细节法线）
	vec3 nn2 = texture(normal_tex, wp.xz * 0.55).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nn2, mix(0.25, 0.85, face));
	NORMAL_MAP_DEPTH = 0.85;
	// 让砖缝有一点自阴影
	AO = mix(0.55, 1.0, smoothstep(0.0, joint * 2.6, edge));
	AO_LIGHT_AFFECT = 0.35;
}
"""

static func water_material() -> ShaderMaterial:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = _WATER_CODE
	if _water_normal_tex == null:
		var wn := FastNoiseLite.new()
		wn.seed = 73
		wn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		wn.frequency = 0.19
		var wt := NoiseTexture2D.new()
		wt.noise = wn
		wt.width = 512
		wt.height = 512
		wt.seamless = true
		wt.as_normal_map = true
		wt.bump_strength = 4.0
		_water_normal_tex = wt
	var mat := ShaderMaterial.new()
	mat.shader = _water_shader
	mat.set_shader_parameter("map_half", MAP_HALF)
	mat.set_shader_parameter("water_normal_tex", _water_normal_tex)
	return mat

static func _build_ground_shader() -> Shader:
	var sh := Shader.new()
	sh.code = _GROUND_CODE
	return sh

const _GROUND_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform sampler2D layout_tex : filter_linear, repeat_disable;
uniform sampler2D detail_tex : filter_linear, repeat_enable;
uniform sampler2D normal_tex : filter_linear, repeat_enable, hint_normal;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform float detail_scale = 14.0;
uniform float map_half = 60.0;
uniform float island_edge = 0.0;
uniform float island_radius = 105.0;
uniform float normal_strength = 0.35;
uniform float ground_roughness = 0.95;
uniform float bump_amount = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 野区微地形起伏（只动野区，分路/河道/高地保持平）；纯视觉，实体仍踩 y=0
	if (bump_amount > 0.001) {
		float lane_d = min(min(abs(abs(wp.x) - 55.0), abs(abs(wp.z) - 55.0)), abs(wp.x + wp.z) * 0.7071068);
		float lane_m = 1.0 - smoothstep(7.0, 13.0, lane_d);
		float river_m = 1.0 - smoothstep(10.0, 15.0, abs(wp.x - wp.z) * 0.7071068);
		float hg_m = 1.0 - smoothstep(30.0, 38.0, min(length(wp.xz + vec2(60.0, -60.0)), length(wp.xz - vec2(60.0, -60.0))));
		float edge_m = 1.0 - smoothstep(56.0, 70.0, max(abs(wp.x), abs(wp.z)));
		float jungle_m = clamp(1.0 - lane_m - river_m - hg_m, 0.0, 1.0) * edge_m;
		float n = sin(wp.x * 0.34) * cos(wp.z * 0.29) * 0.65 + sin(wp.x * 0.81 + 1.7) * cos(wp.z * 0.67 - 0.9) * 0.35;
		VERTEX.y += n * bump_amount * jungle_m;
	}
}

void fragment() {
	// 浮空岛：顶面平面仍是一整块，岛外直接丢弃，露出天空盒与岛缘岩壁
	if (island_edge > 0.5 && length(wp.xz) > island_radius) {
		discard;
	}
	// 世界坐标采样布局图：所有地面平面共用一张图，平面之间天然无缝
	vec2 luv = clamp((wp.xz + vec2(map_half)) / vec2(map_half * 2.0), vec2(0.0), vec2(1.0));
	vec2 duv = wp.xz * (detail_scale / (map_half * 2.0));
	// 运行时生成的贴图没有 sRGB 标记，手动转线性，避免整片发白
	vec3 base = pow(texture(layout_tex, luv).rgb, vec3(2.2));
	vec3 det = texture(detail_tex, duv).rgb;
	vec3 det2 = texture(detail_tex, duv * 3.7 + vec2(0.17, 0.41)).rgb;
	// 中档质感：大尺度色斑 + 两套细节，压掉均匀草地/泥地的“纯色塑料感”
	vec3 macro = texture(detail_tex, wp.xz * 0.0105 + vec2(0.23, 0.61)).rgb;
	base *= mix(vec3(1.0), macro, 0.30);
	base *= mix(vec3(1.0), det, 0.52);
	base *= mix(vec3(1.0), det2, 0.18);
	// 野区草地色相轻微偏移：阳光照射处偏暖、低洼处偏冷
	float green_var = texture(detail_tex, wp.xz * 0.045 + vec2(0.7, 0.2)).g;
	base *= mix(vec3(0.93, 1.04, 0.91), vec3(1.03, 1.01, 0.94), green_var);
	// 岛内布局图只覆盖 ±60；城墙外的大片岛面用程序化草甸延续，避免采样到边缘黑边
	if (island_edge > 0.5) {
		float rr = length(wp.xz);
		float outer = smoothstep(58.0, 67.0, rr);
		vec3 meadow = mix(vec3(0.13, 0.24, 0.11), vec3(0.29, 0.43, 0.19), det.r);
		base = mix(base, meadow, outer);
		base *= mix(1.0, 0.82, smoothstep(96.0, 105.0, rr));
	}
	ALBEDO = base * tint.rgb;
	NORMAL_MAP = texture(normal_tex, duv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = ground_roughness;
	SPECULAR = 0.25;
	EMISSION = emission_color.rgb * emission_strength;
}
"""

const _WATER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// 不透明水面（见 water_material 注释）：用「波高场 → 有限差分法线 + 菲涅尔天空反射 +
// 岸边泡沫 + 顺流闪点」伪造真实水面，比纯色 + 正弦好很多，且不开透明、不破坏贴地特效排序。
uniform vec3 shallow_color : source_color = vec3(0.24, 0.56, 0.57);
uniform vec3 deep_color : source_color = vec3(0.035, 0.125, 0.185);
uniform vec3 foam_color : source_color = vec3(0.88, 0.95, 0.93);
uniform vec3 sky_color : source_color = vec3(0.42, 0.60, 0.80);
uniform sampler2D water_normal_tex : filter_linear, repeat_enable, hint_normal;
uniform float map_half = 60.0;
uniform float wave_strength = 0.040;

varying vec3 wp;

// 四组不同方向/频率的波叠加；沿河方向 (1,1)/√2 有整体推移感
float waves(vec2 p, float t) {
	float a = sin(dot(p, vec2(0.80, -0.60)) * 1.35 + t * 0.95);
	a += 0.55 * sin(dot(p, vec2(-0.62, -0.78)) * 2.40 - t * 1.30);
	a += 0.28 * sin(dot(p, vec2(0.97, 0.24)) * 4.60 + t * 2.00);
	a += 0.14 * sin(dot(p, vec2(-0.36, 0.93)) * 8.20 - t * 2.80);
	return a * 0.55;
}

// 波高场解析梯度（省两次采样，移动端更省；用于算水面法线）
vec2 waves_grad(vec2 p, float t) {
	vec2 d1 = vec2(0.80, -0.60);
	vec2 d2 = vec2(-0.62, -0.78);
	vec2 d3 = vec2(0.97, 0.24);
	vec2 d4 = vec2(-0.36, 0.93);
	vec2 g = cos(dot(p, d1) * 1.35 + t * 0.95) * d1 * 1.35;
	g += 0.55 * cos(dot(p, d2) * 2.40 - t * 1.30) * d2 * 2.40;
	g += 0.28 * cos(dot(p, d3) * 4.60 + t * 2.00) * d3 * 4.60;
	g += 0.14 * cos(dot(p, d4) * 8.20 - t * 2.80) * d4 * 8.20;
	return g * 0.55;
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 只向上起伏：水面不会被地面吞掉（水面本身只比地面高 0.02）
	VERTEX.y += (waves(wp.xz, TIME) * 0.5 + 0.5) * wave_strength;
}

void fragment() {
	vec2 p = wp.xz;
	float t = TIME;
	// 河道沿 (-60,-60)→(60,60) 对角线：d=垂直河心距离(0..10)，along=顺流坐标
	float d = abs(p.x - p.y) * 0.70710678;
	float along = (p.x + p.y) * 0.70710678;

	// 法线：波高场解析梯度（世界空间 → 视图空间），让高光/天空反射随波起伏
	float h0 = waves(p, t);
	vec2 grad = waves_grad(p, t);
	// 两套滚动法线：一套慢速主水流，一套高频细波；避免整条河只有规则正弦波
	vec2 nuv1 = p * 0.085 + vec2(t * 0.024, -t * 0.036);
	vec2 nuv2 = p * 0.21 - vec2(t * 0.018, t * 0.027);
	vec3 n1 = texture(water_normal_tex, nuv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_normal_tex, nuv2).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3(-grad.x * 0.45 + (n1.x + n2.x) * 0.22,
		1.0,
		-grad.y * 0.45 + (n1.y + n2.y) * 0.22));
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	NORMAL = n_view;

	// 顺流闪点：高频细纹被慢波调制，形成水光粼粼
	float sparkle = sin(along * 6.0 - t * 2.1 + sin(d * 5.0 + t * 0.8) * 2.0) * 0.5 + 0.5;
	sparkle = smoothstep(0.80, 1.0, sparkle);

	// 深浅：河心深、近岸浅，叠顺流明暗带
	float center = 1.0 - smoothstep(3.0, 9.2, d);
	float streak = sin(along * 3.4 - t * 1.5 + sin(d * 2.3) * 1.4) * 0.5 + 0.5;
	vec3 col = mix(shallow_color, deep_color, center * 0.95);
	col *= 0.86 + 0.20 * streak;

	// 岸边过渡：先往湿沙色过渡（避免水面边缘与河滩形成一条硬线），再叠泡沫与水线
	float shore_col = smoothstep(7.6, 9.9, d);
	col = mix(col, vec3(0.30, 0.31, 0.26), shore_col * 0.42);
	// 岸边泡沫：贴岸窄带上随波推进的泡沫 + 湿沙高光（只占岸边一条，别糊满水面）
	float foam_wave = sin(d * 5.4 - t * 2.4 + sin(along * 1.1 + t * 0.6) * 1.6) * 0.5 + 0.5;
	float shore = smoothstep(7.2, 8.8, d) * (1.0 - smoothstep(9.55, 10.1, d));
	float foam = smoothstep(0.48, 0.92, foam_wave) * shore;
	// 第二层碎泡：用细节法线纹理做噪声，打散规则泡沫带
	float foam_noise = texture(water_normal_tex, p * 0.34 + vec2(t * 0.018, -t * 0.012)).r;
	float foam_break = smoothstep(0.52, 0.86, foam_noise);
	float foam2 = smoothstep(0.66, 0.94, foam_noise) * shore;
	float wet_line = smoothstep(8.7, 9.45, d) * (1.0 - smoothstep(9.6, 10.15, d));
	col = mix(col, foam_color, clamp(foam * 0.58 * (0.55 + 0.65 * foam_break), 0.0, 1.0));
	col = mix(col, foam_color, foam2 * 0.20);
	col = mix(col, foam_color, wet_line * 0.34);
	// 最贴岸的一线湿光：稍稍提亮，让水/沙/石交界有一道自然的水线
	float lip = smoothstep(9.55, 9.95, d) * (1.0 - smoothstep(9.95, 10.1, d));
	col += vec3(0.10, 0.12, 0.11) * lip * (0.6 + 0.4 * sin(along * 2.2 + t * 1.8));
	col += vec3(0.09, 0.13, 0.14) * sparkle;

	// 菲涅尔：掠射角染天空色，像真实水面反射天光（强度收敛，别把水面洗成天空色）
	float fres = pow(1.0 - clamp(dot(n_view, VIEW), 0.0, 1.0), 5.0);
	col = mix(col, sky_color, clamp(fres * 0.42, 0.0, 0.42));

	ALBEDO = col;
	ROUGHNESS = mix(0.035, 0.20, smoothstep(0.15, 1.0, h0 * 0.5 + 0.5));
	SPECULAR = 0.78;
	METALLIC = 0.0;
	EMISSION = vec3(0.02, 0.09, 0.10) * (0.35 + 0.45 * center);
}
"""


# ================= 河道两岸装饰 =================
## 湿沙河滩 + 半浸礁石 + 芦苇 + 睡莲（纯视觉，无碰撞；MultiMesh 批量，移动端友好）
static func spawn_river_banks(parent: Node3D) -> void:
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251030
	# 垂直河心方向（世界）= (1,0,-1)/√2；顺流方向 = (1,0,1)/√2
	var perp := Vector3(0.70710678, 0.0, -0.70710678)

	# 1) 河滩：干沙（外） + 湿沙（内，压到水面边缘下方），两层叠出潮湿过渡带
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.30, 0.27, 0.215)
	sand_mat.roughness = 0.97
	# 湿沙：更深、更亮（潮湿反光），内沿压到 d≈9.4，与水面泡沫线交叠，消除岸边硬切
	var wet_sand_mat := StandardMaterial3D.new()
	wet_sand_mat.albedo_color = Color(0.215, 0.205, 0.165)
	wet_sand_mat.roughness = 0.55
	wet_sand_mat.metallic = 0.05
	for side in [-1.0, 1.0]:
		var bank := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(3.4, 132.0)
		bank.mesh = pm
		bank.material_override = sand_mat
		bank.rotation_degrees = Vector3(0, 45, 0)
		bank.position = Vector3(0.0, 0.0125, 0.0) + perp * (side * 12.15)
		parent.add_child(bank)
		# 湿沙内层：宽 1.6，内沿到 d≈9.4（水面到 d=10，重叠 0.6m，被水面盖住一部分）
		var wet := MeshInstance3D.new()
		var wpm := PlaneMesh.new()
		wpm.size = Vector2(1.6, 132.0)
		wet.mesh = wpm
		wet.material_override = wet_sand_mat
		wet.rotation_degrees = Vector3(0, 45, 0)
		wet.position = Vector3(0.0, 0.010, 0.0) + perp * (side * 10.2)   # 低于水面最低点(0.02)，避免 z-fighting
		parent.add_child(wet)

	# 2) 半浸礁石：扁球体，靠岸散落，部分压在水线下
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.5
	rock_mesh.height = 0.62
	rock_mesh.radial_segments = 10
	rock_mesh.rings = 5
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.19, 0.21, 0.215)
	rock_mat.roughness = 0.55
	rock_mat.metallic = 0.18
	var rocks := MultiMesh.new()
	rocks.transform_format = MultiMesh.TRANSFORM_3D
	rocks.mesh = rock_mesh
	rocks.instance_count = 96
	for i in rocks.instance_count:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var off := side * rng.randf_range(9.2, 14.6)
		var along := rng.randf_range(-62.0, 62.0)
		if absf(along) < 7.0:
			along += (14.0 if along >= 0.0 else -14.0)
		var b := Basis().scaled(Vector3(rng.randf_range(0.5, 1.5), rng.randf_range(0.35, 0.95), rng.randf_range(0.5, 1.5)))
		var pos := perp * off + Vector3(0.70710678, 0.0, 0.70710678) * along
		pos.y = rng.randf_range(-0.08, 0.16)
		rocks.set_instance_transform(i, Transform3D(b, pos))
	var rock_node := MultiMeshInstance3D.new()
	rock_node.multimesh = rocks
	rock_node.material_override = rock_mat
	parent.add_child(rock_node)

	# 3) 芦苇：细柱，岸边成片，略倾斜
	var reed_mesh := CylinderMesh.new()
	reed_mesh.top_radius = 0.012
	reed_mesh.bottom_radius = 0.03
	reed_mesh.height = 1.05
	reed_mesh.radial_segments = 5
	var reed_mat := StandardMaterial3D.new()
	reed_mat.albedo_color = Color(0.27, 0.34, 0.17)
	reed_mat.roughness = 0.9
	var reeds := MultiMesh.new()
	reeds.transform_format = MultiMesh.TRANSFORM_3D
	reeds.mesh = reed_mesh
	reeds.instance_count = 180
	for i in reeds.instance_count:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var off := side * rng.randf_range(10.4, 13.2)
		var along := rng.randf_range(-60.0, 60.0)
		if absf(along) < 7.0:
			along += (14.0 if along >= 0.0 else -14.0)
		var tilt := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.04, 0.20))
		var b := tilt * Basis().scaled(Vector3(rng.randf_range(0.7, 1.4), rng.randf_range(0.8, 1.5), rng.randf_range(0.7, 1.4)))
		var pos := perp * off + Vector3(0.70710678, 0.0, 0.70710678) * along
		pos.y = 0.5
		reeds.set_instance_transform(i, Transform3D(b, pos))
	var reed_node := MultiMeshInstance3D.new()
	reed_node.multimesh = reeds
	reed_node.material_override = reed_mat
	parent.add_child(reed_node)

	# 4) 睡莲：贴水面的扁圆盘，靠岸浅水处
	var lily_mesh := CylinderMesh.new()
	lily_mesh.top_radius = 0.46
	lily_mesh.bottom_radius = 0.46
	lily_mesh.height = 0.03
	lily_mesh.radial_segments = 12
	var lily_mat := StandardMaterial3D.new()
	lily_mat.albedo_color = Color(0.20, 0.36, 0.21)
	lily_mat.roughness = 0.62
	var lilies := MultiMesh.new()
	lilies.transform_format = MultiMesh.TRANSFORM_3D
	lilies.mesh = lily_mesh
	lilies.instance_count = 34
	for i in lilies.instance_count:
		var side := -1.0 if (i % 2 == 0) else 1.0
		var off := side * rng.randf_range(6.8, 9.4)
		var along := rng.randf_range(-56.0, 56.0)
		if absf(along) < 7.0:
			along += (14.0 if along >= 0.0 else -14.0)
		var b := Basis().scaled(Vector3(rng.randf_range(0.7, 1.25), 1.0, rng.randf_range(0.7, 1.25)))
		var pos := perp * off + Vector3(0.70710678, 0.0, 0.70710678) * along
		pos.y = 0.055
		lilies.set_instance_transform(i, Transform3D(b, pos))
	var lily_node := MultiMeshInstance3D.new()
	lily_node.multimesh = lilies
	lily_node.material_override = lily_mat
	parent.add_child(lily_node)


# ================= 浮空岛背景 =================
## 整张地图是一块悬在天空中的圆岛：岛缘岩壁 + 下方倒锥岩体 + 墙外树林/草坡/碎石/浮岩。
## 纯视觉、无碰撞；host 与 LAN 客户端共用，随机种子固定，两端一致。
static func spawn_floating_island(parent: Node3D) -> void:
	if parent == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	_build_island_rim(parent, rng)
	_build_island_underside(parent, rng)
	_spawn_island_grass(parent, rng)
	_spawn_island_trees(parent, rng)
	_spawn_island_rocks(parent, rng)
	_spawn_sky_chunks(parent, rng)


static func _island_rock_material() -> ShaderMaterial:
	# 岛缘是程序化环带，顶点绕序在移动端不同驱动下容易翻面；直接做双面岩石材质
	var base := DecorMesh.rock_material()
	var sh := (base.shader as Shader).duplicate() as Shader
	sh.code = sh.code.replace(
		"render_mode diffuse_burley, specular_schlick_ggx;",
		"render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


static func _build_island_rim(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var seg := 128
	var levels := [
		{"r": 104.6, "y": -0.04},
		{"r": 107.0, "y": -1.4},
		{"r": 104.0, "y": -4.8},
		{"r": 99.0, "y": -9.2},
		{"r": 91.0, "y": -13.8},
		{"r": 82.0, "y": -17.8},
	]
	var rings: Array = []
	for li in levels.size():
		var lv: Dictionary = levels[li]
		var ring: Array[Vector3] = []
		for i in seg:
			var a := TAU * float(i) / float(seg)
			var n := sin(a * 7.0 + float(li) * 1.7) * 1.8 + sin(a * 13.0 - 0.8 + float(li)) * 1.1
			var r: float = float(lv["r"]) + (n if li > 0 else 0.0)
			var y: float = float(lv["y"]) + (sin(a * 5.0 + float(li) * 2.1) * 0.35 if li > 0 else 0.0)
			ring.append(Vector3(cos(a) * r, y, sin(a) * r))
		rings.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l in range(rings.size() - 1):
		var top: Array = rings[l]
		var bot: Array = rings[l + 1]
		for i in seg:
			var j := (i + 1) % seg
			var a0: Vector3 = top[i]
			var a1: Vector3 = top[j]
			var b0: Vector3 = bot[i]
			var b1: Vector3 = bot[j]
			st.add_vertex(a0); st.add_vertex(a1); st.add_vertex(b0)
			st.add_vertex(a1); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "IslandCliff"
	mi.mesh = st.commit()
	mi.material_override = _island_rock_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


static func _build_island_underside(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var cone := MeshInstance3D.new()
	cone.name = "IslandUnderside"
	var cm := CylinderMesh.new()
	cm.top_radius = 84.0
	cm.bottom_radius = 0.0
	cm.height = 28.0
	cm.radial_segments = 48
	cone.mesh = cm
	cone.position.y = -31.5
	cone.material_override = DecorMesh.rock_material()
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(cone)
	# 岛底倒挂岩柱：长短不一，远看像被撕开后悬空的岩层
	for i in 7:
		var a := TAU * float(i) / 7.0 + rng.randf_range(-0.18, 0.18)
		var rr := rng.randf_range(38.0, 70.0)
		var h := rng.randf_range(10.0, 24.0)
		var spike := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = rng.randf_range(5.0, 10.0)
		sm.bottom_radius = rng.randf_range(0.2, 1.2)
		sm.height = h
		sm.radial_segments = 9
		spike.mesh = sm
		spike.position = Vector3(cos(a) * rr, -20.0 - h * 0.5, sin(a) * rr)
		spike.rotation.z = rng.randf_range(-0.12, 0.12)
		spike.material_override = DecorMesh.rock_material()
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(spike)


static func _spawn_island_grass(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var xforms: Array[Transform3D] = []
	for i in 240:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(66.0, 100.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var s := rng.randf_range(0.75, 1.45)
		xforms.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s)), p))
	var grass := _make_cluster("", xforms, 1.05, false, DecorMesh.grass_mesh(), DecorMesh.leaf_material())
	if grass != null:
		grass.name = "IslandGrass"
		parent.add_child(grass)


static func _spawn_island_trees(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# 沿四边墙外成排，再在外圈补一圈，形成“城墙外是树林”的包边
	for side in 4:
		for k in range(-5, 6):
			var t := float(k) * 10.5 + rng.randf_range(-2.0, 2.0)
			var off := rng.randf_range(67.0, 79.0)
			var p: Vector3
			match side:
				0: p = Vector3(off, 0.0, t)
				1: p = Vector3(-off, 0.0, t)
				2: p = Vector3(t, 0.0, off)
				_: p = Vector3(t, 0.0, -off)
			_spawn_tree(parent, p, rng.randf_range(0.9, 1.55), rng)
	for i in 16:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(82.0, 99.0)
		_spawn_tree(parent, Vector3(cos(a) * r, 0.0, sin(a) * r), rng.randf_range(1.0, 1.8), rng)


static func _spawn_tree(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(root)

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.25, 0.17, 0.10)
	trunk_mat.roughness = 0.96
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.10 * s
	tm.bottom_radius = 0.24 * s
	tm.height = 3.0 * s
	tm.radial_segments = 8
	trunk.mesh = tm
	trunk.position.y = 1.5 * s
	trunk.material_override = trunk_mat
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(trunk)

	var leaf := DecorMesh.leaf_material()
	if rng.randf() < 0.32:
		# 针叶树：三层锥冠
		for i in 3:
			var cone := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03 * s
			cm.bottom_radius = (1.35 - float(i) * 0.26) * s
			cm.height = (1.9 - float(i) * 0.18) * s
			cm.radial_segments = 10
			cone.mesh = cm
			cone.position.y = (3.0 + float(i) * 1.05) * s
			cone.material_override = leaf
			cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(cone)
	else:
		# 阔叶树：三团错位树冠，头重脚轻但轮廓自然
		for i in 3:
			var ball := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = (1.1 - float(i) * 0.10) * s
			sm.height = (1.5 - float(i) * 0.12) * s
			sm.radial_segments = 12
			sm.rings = 6
			ball.mesh = sm
			var ang := float(i) * 2.2
			ball.position = Vector3(cos(ang) * 0.55 * s, (3.5 + float(i) * 0.42) * s, sin(ang) * 0.55 * s)
			ball.scale = Vector3(1.0, 0.78, 1.0)
			ball.material_override = leaf
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(ball)


static func _spawn_island_rocks(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 1.25
	rock_mesh.radial_segments = 9
	rock_mesh.rings = 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock_mesh
	mm.instance_count = 30
	for i in mm.instance_count:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(66.0, 101.0)
		var sx := rng.randf_range(0.55, 2.1)
		var sy := rng.randf_range(0.32, 0.95)
		var b := Basis().scaled(Vector3(sx, sy, sx * rng.randf_range(0.75, 1.25)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(cos(a) * r, sy * 0.35, sin(a) * r)))
	var node := MultiMeshInstance3D.new()
	node.name = "IslandRocks"
	node.multimesh = mm
	node.material_override = DecorMesh.rock_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _spawn_sky_chunks(parent: Node3D, rng: RandomNumberGenerator) -> void:
	# 主岛外漂浮的小岩块：给“空岛”里的天空增加层次，不需要碰撞
	for i in 8:
		var a := TAU * float(i) / 8.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(118.0, 148.0)
		var chunk := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 1.0
		sm.radial_segments = 7
		sm.rings = 4
		chunk.mesh = sm
		chunk.position = Vector3(cos(a) * r, rng.randf_range(-30.0, -4.0), sin(a) * r)
		chunk.scale = Vector3(rng.randf_range(4.0, 10.0), rng.randf_range(1.5, 4.0), rng.randf_range(4.0, 10.0))
		chunk.rotation.y = rng.randf_range(0.0, TAU)
		chunk.material_override = DecorMesh.rock_material()
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(chunk)


# ================= 布局贴图绘制 =================

static func _paint_layout() -> Image:
	var size := LAYOUT_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGB8)
	var grass := FastNoiseLite.new()
	grass.seed = 7
	grass.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grass.frequency = 0.045
	var patch := FastNoiseLite.new()
	patch.seed = 31
	patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch.frequency = 0.016
	for py in size:
		for px in size:
			var x: float = (float(px) + 0.5) / float(size) * MAP_HALF * 2.0 - MAP_HALF
			var z: float = (float(py) + 0.5) / float(size) * MAP_HALF * 2.0 - MAP_HALF
			var n: float = grass.get_noise_2d(x, z) * 0.5 + 0.5          # 0..1 细噪声
			var pt: float = patch.get_noise_2d(x, z) * 0.5 + 0.5         # 0..1 大斑块

			# 1) 野区草地基底（深浅变化 + 大块阴影）
			var col := Color(0.17, 0.31, 0.14).lerp(Color(0.33, 0.48, 0.21), n)
			col = col.lerp(Color(0.11, 0.20, 0.11), pt * 0.45)

			# 2) 河道河床（沿 x-z=0 对角线与中路垂直；比草地暗、偏青灰）
			var river_d: float = absf(x - z) * 0.70710678
			col = col.lerp(Color(0.22, 0.28, 0.29).lerp(Color(0.30, 0.36, 0.34), n), _inside(river_d, 13.0, 3.0))

			# 3) 三路（土黄石路，双色噪声 + 路缘更深）
			var lane: float = _lane_mask(x, z)
			if lane > 0.001:
				var dirt := Color(0.44, 0.40, 0.30).lerp(Color(0.56, 0.51, 0.38), n)
				col = col.lerp(dirt, lane)
				var rim: float = _lane_rim(x, z)
				if rim > 0.001:
					col = col.lerp(Color(0.25, 0.24, 0.19), rim * 0.55)

			# 4) 高地 / 基地台座（石砖，最后绘制盖住河道与路）
			var hg: float = _high_ground_mask(x, z)
			if hg > 0.001:
				var stone := Color(0.40, 0.42, 0.36).lerp(Color(0.55, 0.56, 0.48), n)
				col = col.lerp(stone, hg * 0.92)

			# 5) 地图边缘变暗（远景承接雾色，避免看到"断崖"）
			var edge_d: float = maxf(absf(x), absf(z))
			col = col.darkened(clampf((edge_d - 48.0) / 14.0, 0.0, 0.4))
			img.set_pixel(px, py, col)
	return img

# 距离场软边：d 在 half±feather 之间平滑过渡
static func _inside(d: float, half: float, feather: float) -> float:
	return 1.0 - smoothstep(half - feather, half + feather, d)

# 三路覆盖度（0..1，软边）：四边路 + 中路对角线（x+z=0 方向，与 _is_on_lane 一致）
static func _lane_mask(x: float, z: float) -> float:
	var m := 0.0
	# 边路贴图一直铺到外墙（±63），与加长后的分路平面一致
	var along_z: float = _inside(absf(z), 61.0, 2.0)
	var along_x: float = _inside(absf(x), 61.0, 2.0)
	m = maxf(m, _inside(absf(absf(x) - 55.0), 8.0, 3.0) * along_z)
	m = maxf(m, _inside(absf(absf(z) - 55.0), 8.0, 3.0) * along_x)
	m = maxf(m, _inside(absf(x + z) * 0.70710678, 7.5, 2.5))
	return m

# 路缘（路两侧 1.5 单位内的暗边）
static func _lane_rim(x: float, z: float) -> float:
	var m := 0.0
	var along_z: float = _inside(absf(z), 61.0, 2.0)
	var along_x: float = _inside(absf(x), 61.0, 2.0)
	m = maxf(m, _inside(absf(absf(absf(x) - 55.0) - 9.5), 1.6, 1.2) * along_z)
	m = maxf(m, _inside(absf(absf(absf(z) - 55.0) - 9.5), 1.6, 1.2) * along_x)
	m = maxf(m, _inside(absf(absf(x + z) * 0.70710678 - 9.0), 1.6, 1.2))
	return m

# 高地/基地石材区域：以 (-60,60) 与 (60,-60) 为圆心、半径 35 的扇形范围
static func _high_ground_mask(x: float, z: float) -> float:
	var d1: float = Vector2(x + 60.0, z - 60.0).length()
	var d2: float = Vector2(x - 60.0, z + 60.0).length()
	var m: float = maxf(_inside(d1, 34.0, 4.0), _inside(d2, 34.0, 4.0))
	return m

# ================= 装饰物散布（MultiMesh） =================

static func scatter_decorations(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029

	# --- 草丛：野区内成片铺，避开路面/河道/高地 ---
	var grass_xf: Array[Transform3D] = []
	var attempts := 0
	while grass_xf.size() < 360 and attempts < 2400:
		attempts += 1
		var gx: float = rng.randf_range(-56.0, 56.0)
		var gz: float = rng.randf_range(-56.0, 56.0)
		if not _open_ground(gx, gz):
			continue
		var rot: float = rng.randf_range(0.0, TAU)
		var basis := Basis(Vector3.UP, rot)
		grass_xf.append(Transform3D(basis, Vector3(gx, 0.0, gz)))
	var grass := _make_cluster("res://model/grass/grass-large.glb", grass_xf, 1.1, false, DecorMesh.grass_mesh(), DecorMesh.leaf_material())
	if grass != null:
		grass.name = "GrassDecor"
		parent.add_child(grass)

	# --- 近景草叶：程序化草簇 + 风摆，补足远景 GLB 草的空洞感 ---
	var near_xf: Array[Transform3D] = []
	var near_attempts := 0
	while near_xf.size() < 780 and near_attempts < 6500:
		near_attempts += 1
		var nx: float = rng.randf_range(-56.0, 56.0)
		var nz: float = rng.randf_range(-56.0, 56.0)
		if not _open_ground(nx, nz, 0.4):
			continue
		var ns: float = rng.randf_range(0.62, 1.12)
		var nb := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(ns, ns, ns))
		near_xf.append(Transform3D(nb, Vector3(nx, 0.0, nz)))
	var near_grass := _make_cluster("", near_xf, 0.58, false, DecorMesh.grass_mesh(), DecorMesh.leaf_material())
	if near_grass != null:
		near_grass.name = "GrassNear"
		parent.add_child(near_grass)
	# 假 AO：移动端没有 SSAO，用少量贴地暗斑压住草根/石根，增加接触感
	var ao_mesh := PlaneMesh.new()
	ao_mesh.size = Vector2(1.05, 1.05)
	var ao_mm := MultiMesh.new()
	ao_mm.transform_format = MultiMesh.TRANSFORM_3D
	ao_mm.mesh = ao_mesh
	ao_mm.instance_count = near_xf.size()
	for i in near_xf.size():
		var op: Vector3 = near_xf[i].origin + Vector3(0.0, 0.022, 0.0)
		ao_mm.set_instance_transform(i, Transform3D(Basis(), op))
	var ao_mat := StandardMaterial3D.new()
	ao_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ao_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ao_mat.albedo_color = Color(0.02, 0.045, 0.025, 0.15)
	ao_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ao_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ao_node := MultiMeshInstance3D.new()
	ao_node.name = "GrassContactAO"
	ao_node.multimesh = ao_mm
	ao_node.material_override = ao_mat
	ao_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ao_node)

	# --- 河道两岸石墙：河道沿 x-z=0，两岸在 x-z=±15（垂直距约 10.6），朝向与河道一致 ---
	var wall_xf: Array[Transform3D] = []
	for i in range(-40, 41, 7):
		var s: float = float(i)
		for side in [-1.0, 1.0]:
			var wx: float = s + 7.5 * side
			var wz: float = s - 7.5 * side
			if absf(wx) > 55.0 or absf(wz) > 55.0:
				continue
			# 中路桥面两侧不放墙
			if _lane_mask(wx, wz) > 0.05 or _high_ground_mask(wx, wz) > 0.05:
				continue
			wall_xf.append(Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3(wx, 0.0, wz)))
	var walls := _make_cluster("res://model/wall/wall.glb", wall_xf, 1.5, true, DecorMesh.wall_mesh(), DecorMesh.rock_material())
	if walls != null:
		walls.name = "RiverWallDecor"
		parent.add_child(walls)

	# --- 陶罐点缀（基地附近） ---
	var pot_xf: Array[Transform3D] = []
	var pot_spots := [
		Vector3(-46, 0, 46), Vector3(-42, 0, 52), Vector3(-52, 0, 40),
		Vector3(46, 0, -46), Vector3(42, 0, -52), Vector3(52, 0, -40),
		Vector3(-50, 0, -30), Vector3(30, 0, 50), Vector3(50, 0, 30), Vector3(-30, 0, -50),
	]
	for p in pot_spots:
		if not _open_ground(p.x, p.z, 3.0):
			continue
		pot_xf.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), Vector3(p.x, 0.0, p.z)))
	var pots := _make_cluster("res://model/pot/pot.glb", pot_xf, 0.9, true)
	if pots != null:
		pots.name = "PotDecor"
		parent.add_child(pots)

# 是否是可摆放装饰的开阔地（野区，不在路面/河道/高地/外围）
static func _open_ground(x: float, z: float, extra: float = 0.0) -> bool:
	if absf(x) > 57.0 or absf(z) > 57.0:
		return false
	if _lane_mask(x, z) > 0.05:
		return false
	if absf(x - z) * 0.70710678 < 12.5 + extra:   # 河道（x-z=0 对角线两侧）
		return false
	if _high_ground_mask(x, z) > 0.05:
		return false
	return true

static func _make_cluster(path: String, xforms: Array[Transform3D], target_height: float, cast_shadow: bool, mesh_override: Mesh = null, mat: Material = null) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mesh: Mesh = mesh_override if mesh_override != null else _load_first_mesh(path)
	if mesh == null:
		return null
	var aabb := mesh.get_aabb()
	var scale_f: float = target_height / maxf(aabb.size.y, 0.001)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		var t: Transform3D = xforms[i]
		mm.set_instance_transform(i, Transform3D(t.basis.scaled(Vector3.ONE * scale_f), t.origin))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat != null:
		mmi.material_override = mat
	return mmi

static func _load_first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res == null or not (res is PackedScene):
		return null
	var inst: Node = (res as PackedScene).instantiate()
	var mesh := _find_mesh(inst)
	inst.free()
	return mesh

static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
