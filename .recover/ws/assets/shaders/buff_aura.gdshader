shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 红/蓝 Buff 拥有者地面光环：主环 + 旋转符文 + 反向弧 + 元素流动
uniform vec4 aura_color : source_color = vec4(1.0, 0.28, 0.05, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.30, 1.0);
uniform float ring_radius = 0.72;
uniform float mode = 0.0;          // 0=红 Buff 火焰；1=蓝 Buff 霜雾
uniform float intensity = 1.0;

varying vec2 v_local;

float ring_mask(float r, float target, float width) {
	return 1.0 - smoothstep(0.0, width, abs(r - target));
}

void vertex() {
	v_local = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(v_local);
	float ang = atan(v_local.y, v_local.x);
	float t = TIME;
	float blue = step(0.5, mode);

	float pulse = 0.82 + 0.18 * sin(t * mix(2.8, 1.7, blue) + blue * 1.6);
	float a = (1.0 - smoothstep(0.15, 1.0, r)) * 0.045;

	// 主环 + 内外细环
	a += ring_mask(r, ring_radius, 0.020) * 0.85 * pulse;
	a += ring_mask(r, ring_radius + 0.065, 0.011) * 0.30;
	a += ring_mask(r, ring_radius - 0.070, 0.009) * 0.22;

	// 12 段旋转符文刻线
	float dashes = smoothstep(0.30, 0.95, sin(ang * 12.0 + t * mix(1.5, 0.9, blue)) * 0.5 + 0.5);
	a += ring_mask(r, ring_radius, 0.034) * dashes * 0.45;

	// 反向旋转的三段弧
	float arcs = smoothstep(0.55, 0.98, sin(ang * 3.0 - t * mix(0.65, 0.42, blue) + blue * 1.3) * 0.5 + 0.5);
	a += ring_mask(r, ring_radius + 0.115, 0.014) * arcs * 0.55;

	// 环外元素流动：红=火星，蓝=霜雾
	float ripple = sin(ang * mix(9.0, 5.0, blue) + r * mix(26.0, 15.0, blue) - t * mix(2.6, 1.4, blue));
	float band = smoothstep(ring_radius + 0.02, ring_radius + 0.08, r) * (1.0 - smoothstep(ring_radius + 0.20, ring_radius + 0.44, r));
	a += smoothstep(0.55, 1.0, ripple) * band * (0.16 + 0.07 * sin(t * 3.0 + ang * 4.0));

	// 中心元素微光
	float core = 1.0 - smoothstep(0.0, ring_radius - 0.12, r);
	a += core * (0.06 + 0.025 * sin(t * 2.0 + blue * 1.1));

	// 方形贴图边缘淡出
	a *= 1.0 - smoothstep(0.86, 1.0, r);
	a = clamp(a * intensity, 0.0, 1.0);

	vec3 col = mix(aura_color.rgb, core_color.rgb, clamp(a * 1.4, 0.0, 1.0));
	ALBEDO = col * (1.0 + a * 0.8);
	ALPHA = a;
}
