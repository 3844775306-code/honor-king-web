shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// 软光斑/地面法阵：径向渐隐 + 可选环带 + 呼吸，用于地面贴花与蓄力圈
uniform vec4 glow_color : source_color = vec4(0.6, 0.8, 1.0, 0.7);
uniform float intensity = 1.6;
uniform float softness = 0.55;
uniform float ring_width : hint_range(0.0, 0.5) = 0.18;
uniform float pulse_speed = 0.0;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, d);
	float edge = smoothstep(1.0, 1.0 - softness, d);
	float ring = 1.0 - smoothstep(0.0, ring_width, abs(d - (1.0 - ring_width)));
	float pulse = 1.0;
	if (pulse_speed > 0.0) {
		pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);
	}
	ALBEDO = glow_color.rgb * intensity * pulse;
	ALPHA = clamp((core * edge * 0.65 + ring * 0.55) * glow_color.a, 0.0, 1.0);
}
