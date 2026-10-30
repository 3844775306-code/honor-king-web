shader_type spatial;
// 英雄脚下接地软阴影：透明黑色软圆（贴地平面），与真实阴影并存，用于把模型“踩”在地上。
// PlaneMesh 默认已在 XZ 平面（法线 +Y），无需再绕 X 旋转。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float shadow_strength : hint_range(0.0, 1.0) = 0.30; // 圆内 alpha ≈0.30
uniform vec2 soft_range = vec2(0.22, 0.98);                  // 内圈实、外圈平滑到 0
uniform float noise_amt : hint_range(0.0, 0.5) = 0.10;       // 低频噪声幅度（避免死板）

float _hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float _vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = _hash(i);
	float b = _hash(i + vec2(1.0, 0.0));
	float c = _hash(i + vec2(0.0, 1.0));
	float d = _hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float a = 1.0 - smoothstep(soft_range.x, soft_range.y, d);
	// 低频噪声只做轻微扰动，中心保持最实
	float n = _vnoise(UV * 3.0) * 2.0 - 1.0;
	a *= 1.0 + n * noise_amt;
	a = clamp(a, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	ALPHA = a * shadow_strength;
}
