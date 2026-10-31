shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 线性/位移技能预览：贴地能量带 + 两侧导轨 + 向上流动的刻度 + 实心箭镞。
// 网格为 1×1 的水平面片，沿局部 +Z 方向拉伸；v_pos.y=-1 为起点，+1 为终点。
uniform vec4 tint : source_color = vec4(0.24, 0.68, 1.0, 1.0);
uniform vec4 hot : source_color = vec4(0.82, 0.97, 1.0, 1.0);
uniform float intensity = 1.0;

varying vec2 v_pos;

float band(float v, float target, float width) {
	return 1.0 - smoothstep(0.0, width, abs(v - target));
}

void vertex() {
	v_pos = vec2(VERTEX.x * 2.0, VERTEX.z * 2.0);
}

void fragment() {
	float x = v_pos.x;
	float y = v_pos.y;
	float t = TIME;
	float ax = abs(x);

	// 主能量带：边缘柔化，靠近箭镞处收窄
	float body = (1.0 - smoothstep(0.28, 0.82, ax)) * (1.0 - smoothstep(0.38, 0.64, y));
	float center = (1.0 - smoothstep(0.0, 0.16, ax)) * (1.0 - smoothstep(0.20, 0.58, y));
	// 两侧导轨
	float rails = band(ax, 0.82, 0.035) * (1.0 - smoothstep(0.28, 0.56, y));
	// 沿长度流动的短刻度
	float flow = sin((y * 0.5 + 0.5) * 26.0 - t * 8.0 + ax * 1.6) * 0.5 + 0.5;
	float flow_marks = smoothstep(0.62, 1.0, flow) * (1.0 - smoothstep(0.0, 0.74, ax)) * (1.0 - smoothstep(0.32, 0.58, y)) * 0.22;

	// 箭镞：从 y=0.36 张开到 y=1.0 收尖
	float ht = clamp((y - 0.36) / 0.64, 0.0, 1.0);
	float half_w = 0.92 * (1.0 - ht);
	float head = (1.0 - smoothstep(half_w - 0.025, half_w + 0.025, ax)) * step(0.36, y) * 0.88;
	float edge = (1.0 - smoothstep(0.025, 0.085, abs(ax - half_w))) * step(0.38, y) * step(ax, half_w + 0.04) * 0.75;
	// 尾端柔光
	float tail = (1.0 - smoothstep(0.0, 0.28, abs(y + 1.0))) * (1.0 - smoothstep(0.0, 0.86, ax)) * 0.18;

	float a = body * 0.22 + center * 0.40 + rails * 0.60 + flow_marks + head * 0.20 + edge * 0.80 + tail;
	a *= 1.0 - smoothstep(0.985, 1.0, y);
	a = clamp(a * intensity, 0.0, 1.0);

	vec3 col = mix(tint.rgb, hot.rgb, clamp(a * 1.25, 0.0, 1.0));
	ALBEDO = col * (1.0 + a * 0.8);
	ALPHA = a;
}
