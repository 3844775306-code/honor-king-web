shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 施法落点预览：mode=0 范围填充（柔光底 + 外环 + 内环 + 准星 + 扫描扇区）；
// mode=1 目标锁定准星（四段括号弧 + 十字线 + 中心点）。
uniform vec4 tint : source_color = vec4(0.24, 0.68, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(0.82, 0.97, 1.0, 1.0);
uniform float intensity = 1.0;
uniform float mode = 0.0;

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
	float pulse = 0.88 + 0.12 * sin(t * 2.6);
	float a = 0.0;

	if (mode < 0.5) {
		float fill = (1.0 - smoothstep(0.04, 0.94, r)) * 0.075 * pulse;
		float halo = band(r, 0.945, 0.10) * 0.085;
		float rim = band(r, 0.966, 0.010) * 0.88 * pulse;
		float inner = band(r, 0.655, 0.006) * 0.24;
		// 准星：横向/纵向细线，限制在中心区域
		float cross_x = (1.0 - smoothstep(0.0, 0.008, abs(p.x))) * (1.0 - smoothstep(0.52, 0.76, r)) * 0.20;
		float cross_y = (1.0 - smoothstep(0.0, 0.008, abs(p.y))) * (1.0 - smoothstep(0.52, 0.76, r)) * 0.20;
		float center = (1.0 - smoothstep(0.0, 0.085, r)) * 0.22;
		// 缓慢旋转的扫描扇区
		float sweep = smoothstep(0.70, 1.0, sin(ang - t * 1.15) * 0.5 + 0.5);
		float wedge = smoothstep(0.0, 0.10, r) * (1.0 - smoothstep(0.86, 0.94, r)) * sweep * 0.055;
		a = fill + halo + rim + inner + cross_x + cross_y + center + wedge;
		a *= 1.0 - smoothstep(0.976, 1.0, r);
	} else {
		// 目标锁定：四段外括号 + 细外环 + 中心十字 + 心跳点
		float outer = band(r, 0.88, 0.006) * 0.30;
		float brackets = smoothstep(0.42, 0.82, sin(ang * 4.0 + 0.8) * 0.5 + 0.5);
		float bracket = band(r, 0.72, 0.030) * brackets * 0.92 * pulse;
		float inner = band(r, 0.46, 0.0045) * 0.20;
		float cross_x = (1.0 - smoothstep(0.0, 0.010, abs(p.x))) * (1.0 - smoothstep(0.52, 0.64, abs(p.y))) * 0.26;
		float cross_y = (1.0 - smoothstep(0.0, 0.010, abs(p.y))) * (1.0 - smoothstep(0.52, 0.64, abs(p.x))) * 0.26;
		float center = (1.0 - smoothstep(0.0, 0.085, r)) * 0.45 * pulse;
		a = outer + bracket + inner + cross_x + cross_y + center;
		a *= 1.0 - smoothstep(0.97, 1.0, r);
	}

	a = clamp(a * intensity, 0.0, 1.0);
	vec3 col = mix(tint.rgb, hot.rgb, clamp(a * 1.4, 0.0, 1.0));
	ALBEDO = col * (1.0 + a * 0.75);
	ALPHA = a;
}
