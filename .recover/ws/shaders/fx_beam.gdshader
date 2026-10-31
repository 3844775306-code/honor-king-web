shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 光束：沿轴向流动的条纹 + 视角边缘柔化，用于引导类技能（安琪拉R/后羿R等）
uniform vec4 beam_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float intensity = 2.4;
uniform float flow_speed = 7.0;
uniform float flow_density = 42.0;

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.55);
	float flow = 0.62 + 0.38 * sin(UV.y * flow_density - TIME * flow_speed);
	ALBEDO = beam_color.rgb * intensity * flow;
	ALPHA = clamp(beam_color.a * (0.35 + 0.65 * edge), 0.0, 1.0);
}
