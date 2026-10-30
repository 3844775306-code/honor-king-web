shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 施法范围预览：双层光环 + 刻度虚线 + 缓慢流转的符文弧，替代原来的细圆环。
uniform vec4 tint : source_color = vec4(0.24, 0.68, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(0.82, 0.97, 1.0, 1.0);
uniform float intensity = 1.0;

varying vec2 v_uv;

float band(float r, float target, float width) {
	return 1.0 - smoothstep(0.0, width, abs(r - target));
}

void vertex() {
	v_uv = UV * 2.0 - 1.0;
}

void fragment() {
	vec2 p = v_uv;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME;

	float fill = (1.0 - smoothstep(0.0, 0.95, r)) * 0.032;
	float halo = band(r, 0.968, 0.10) * 0.11;
	float rim = band(r, 0.975, 0.0080) * 0.95;
	float inner = band(r, 0.905, 0.0045) * 0.30;

	// 24 段刻度虚线（缓慢旋转）
	float dashes = smoothstep(0.18, 0.94, sin(ang * 24.0 - t * 0.75) * 0.5 + 0.5);
	float ticks = band(r, 0.842, 0.0095) * dashes * 0.34;

	// 内圈三段流转弧
	float slow = smoothstep(0.48, 0.98, sin(ang * 3.0 - t * 0.52 + 1.2) * 0.5 + 0.5);
	float arcs = band(r, 0.805, 0.0065) * slow * 0.26;

	// 一道扫过边缘的能量弧
	float sweep = smoothstep(0.88, 1.0, sin(ang - t * 1.55) * 0.5 + 0.5);
	float sweep_band = band(r, 0.966, 0.024) * sweep * 0.30;

	float pulse = 0.88 + 0.12 * sin(t * 2.2);
	float a = (fill + halo + rim * pulse + inner + ticks + arcs + sweep_band) * intensity;
	a *= 1.0 - smoothstep(0.986, 1.0, r);
	a = clamp(a, 0.0, 1.0);

	vec3 col = mix(tint.rgb, hot.rgb, clamp(a * 1.35, 0.0, 1.0));
	ALBEDO = col * (1.0 + a * 0.85);
	ALPHA = a;
}
