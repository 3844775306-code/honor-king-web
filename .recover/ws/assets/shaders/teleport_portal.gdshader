shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 传送阵地面：外圈刻度 + 逆向符文 + 三臂漩涡 + 向内收束的能量微粒
uniform vec4 portal_color : source_color = vec4(0.22, 0.58, 1.0, 1.0);
uniform vec4 accent_color : source_color = vec4(0.55, 0.95, 1.0, 1.0);
uniform float intensity = 1.0;

varying vec2 v_pos;

float band(float r, float target, float width) {
	return 1.0 - smoothstep(0.0, width, abs(r - target));
}

void vertex() {
	v_pos = UV * 2.0 - 1.0;
}

void fragment() {
	float r = length(v_pos);
	float ang = atan(v_pos.y, v_pos.x);
	float t = TIME;

	float a = (1.0 - smoothstep(0.0, 1.0, r)) * 0.032;

	// 外沿亮环 + 内外细环
	a += band(r, 0.962, 0.010) * 0.92;
	a += band(r, 0.905, 0.007) * 0.32;

	// 36 段旋转刻度
	float ticks = smoothstep(0.30, 0.92, sin(ang * 36.0 + t * 0.8) * 0.5 + 0.5);
	a += band(r, 0.928, 0.030) * ticks * 0.50;

	// 8 组逆向符文弧
	float runes = smoothstep(0.48, 0.94, sin(ang * 8.0 - t * 1.15) * 0.5 + 0.5);
	a += band(r, 0.785, 0.018) * runes * 0.62;

	// 三臂旋涡
	float spiral = sin(ang * 3.0 + r * 11.0 - t * 2.3);
	a += smoothstep(0.15, 1.0, spiral)
		* smoothstep(0.10, 0.68, r)
		* (1.0 - smoothstep(0.78, 0.95, r)) * 0.20;

	// 向内收束的微粒流
	float motes = sin(ang * 26.0 - r * 32.0 + t * 3.8);
	a += smoothstep(0.72, 1.0, motes)
		* smoothstep(0.16, 0.86, r)
		* (1.0 - smoothstep(0.90, 1.0, r)) * 0.16;

	// 中心漩涡微光
	float core = 1.0 - smoothstep(0.0, 0.46, r);
	a += core * (0.055 + 0.028 * sin(t * 2.5 + ang * 3.0));

	a *= 0.86 + 0.14 * sin(t * 1.9);
	a *= 1.0 - smoothstep(0.985, 1.0, r);
	a = clamp(a * intensity, 0.0, 1.0);

	vec3 col = mix(portal_color.rgb, accent_color.rgb, smoothstep(0.15, 1.0, r));
	ALBEDO = col * (1.0 + a * 0.65);
	ALPHA = a;
}
