shader_type spatial;
// 暗影之径：分路上的暗影能量覆盖层
// 紫色暗雾（靠路缘更浓）+ 双发光路缘线 + 沿路流动的能量脉络 + 横向推进波 + 心跳脉冲
// 用法：作为分路平面的子节点平铺一张同尺寸 PlaneMesh，用 intensity 做淡入淡出。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 shadow_tint : source_color = vec4(0.34, 0.16, 0.72, 1.0);
uniform vec4 vein_tint : source_color = vec4(0.74, 0.46, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.5) = 1.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.24;
uniform float edge_alpha : hint_range(0.0, 1.5) = 0.80;
uniform float vein_alpha : hint_range(0.0, 1.5) = 0.55;
uniform float flow_speed = 1.8;
uniform float edge_pos : hint_range(0.5, 1.0) = 0.93;
uniform float edge_width : hint_range(0.004, 0.12) = 0.030;

void fragment() {
	vec2 uv = UV;
	float across = abs(uv.x - 0.5) * 2.0;      // 0=路中心，1=路缘
	// 1) 基底暗雾：路中心薄、靠边浓（暗影像从两侧渗上来）
	float base = mix(0.30, 1.0, smoothstep(0.04, 1.0, across));
	// 2) 双发光路缘：贴外侧的细亮线，给出清晰的"路径"边界
	float edge = 1.0 - smoothstep(0.0, edge_width, abs(across - edge_pos));
	// 3) 沿路流动的能量脉络：两层错相正弦（一层快、一层慢带横向调制）
	float flow = TIME * flow_speed;
	float s1 = sin(uv.y * 46.0 - flow) * 0.5 + 0.5;
	float s2 = sin(uv.y * 19.0 + flow * 1.7 + across * 4.0) * 0.5 + 0.5;
	float vein = smoothstep(0.62, 0.99, s1 * 0.55 + s2 * 0.45);
	// 4) 横向推进波：暗影像在路面上向前涌动
	float sweep = smoothstep(0.55, 1.0, sin(uv.y * 7.0 - TIME * 0.9) * 0.5 + 0.5) * (1.0 - across * 0.55);
	// 5) 心跳脉冲：整体亮度缓慢起伏
	float pulse = 0.85 + 0.15 * sin(TIME * 2.0);

	vec3 col = mix(shadow_tint.rgb, vein_tint.rgb, clamp(vein + sweep * 0.35, 0.0, 1.0));
	ALBEDO = col * pulse;
	ALPHA = clamp((base * base_alpha + edge * edge_alpha + vein * vein_alpha) * intensity, 0.0, 1.0);
}
