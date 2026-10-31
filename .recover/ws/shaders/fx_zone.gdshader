shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// 地面持续区域法阵（王昭君暴风雪 / 吕布魔神降世 等）：柔和底盘 + 双层亮环 + 旋转符文齿 +
// 元素纹理（0=冰霜六角晶格 1=暗影裂纹 2=通用）+ 外扩涟漪 + 雾噪，全部程序化，无贴图开销。

uniform vec4 color_a : source_color = vec4(0.45, 0.82, 1.0, 0.85);
uniform vec4 color_b : source_color = vec4(0.86, 0.97, 1.0, 1.0);
uniform float intensity = 2.1;
uniform float style = 2.0;          // 0=冰霜 1=暗影 2=通用
uniform float spin_speed = 0.35;
uniform float pulse_speed = 2.4;
uniform float opacity = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	float ang = atan(p.y, p.x);
	float t = TIME;
	float spin = t * spin_speed;

	// 底盘：中心微亮、向边缘柔和衰减
	float fill = smoothstep(1.0, 0.05, d) * 0.14;

	// 双亮环（主 0.965 / 次 0.760）
	float rim = smoothstep(0.045, 0.0, abs(d - 0.965));
	float rim2 = smoothstep(0.030, 0.0, abs(d - 0.760)) * 0.45;

	// 旋转符文齿（外带 28 段刻痕）
	float seg_ang = fract((ang / TAU) * 28.0 + spin * 0.5);
	float tooth = (1.0 - smoothstep(0.42, 0.55, seg_ang)) * smoothstep(0.30, 0.0, abs(d - 0.895));
	float rune_band = smoothstep(0.055, 0.0, abs(d - 0.895)) * 0.22;

	// 内圈辐条（8 条，反向旋转）
	float spoke_ang = fract((ang / TAU) * 8.0 - spin * 0.35);
	float spoke = (1.0 - smoothstep(0.0, 0.12, spoke_ang)) * smoothstep(0.80, 0.15, d)
			* smoothstep(0.10, 0.25, d) * 0.16;

	// 向外流动的涟漪（3 道）
	float ripple = pow(max(0.0, sin((d * 6.0 - t * 0.9) * PI)), 6.0) * smoothstep(1.0, 0.2, d) * 0.10;

	// 元素纹理
	float lat = 0.0;
	if (style < 0.5) {
		// 冰霜：斜向六角晶格 + 中心雪花放射线
		vec2 q = p * 9.0;
		float l1 = smoothstep(0.05, 0.0, abs(fract((q.x + q.y * 0.577) * 0.5) - 0.5));
		float l2 = smoothstep(0.05, 0.0, abs(fract((q.x * 0.866 - q.y * 0.5)) - 0.5));
		lat = (l1 + l2) * 0.09 * smoothstep(0.95, 0.10, d);
		float snow_ang = fract((ang / TAU) * 12.0 + 0.5);
		lat += (1.0 - smoothstep(0.0, 0.03, snow_ang)) * smoothstep(0.55, 0.0, d) * 0.18;
	} else if (style < 1.5) {
		// 暗影：破碎裂纹 + 中心暗核
		float n = vnoise(p * 7.0 + vec2(t * 0.06, -t * 0.05));
		lat = smoothstep(0.62, 0.70, n) * smoothstep(0.95, 0.10, d) * 0.35;
		lat += (1.0 - smoothstep(0.0, 0.45, d)) * 0.10;
	}

	// 雾噪（缓慢旋转）
	float mist = vnoise(p * 4.0 + vec2(spin * 0.6, -spin * 0.4)) * smoothstep(1.0, 0.05, d) * 0.10;

	float pulse = 0.82 + 0.18 * sin(t * pulse_speed);
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(rune_band * 0.5 + tooth * 0.8 + rim, 0.0, 1.0));
	ALBEDO = col * intensity * pulse;
	ALPHA = clamp(fill + rim + rim2 + tooth * 0.7 + rune_band + spoke + ripple + lat + mist, 0.0, 1.0)
			* color_a.a * opacity;
}
