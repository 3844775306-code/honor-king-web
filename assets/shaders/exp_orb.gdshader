shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

// 经验球外层光晕：菲涅尔边缘发光 + 沿球面流动的能量带
uniform vec4 orb_color : source_color = vec4(0.20, 1.0, 0.42, 1.0);
uniform vec4 core_color : source_color = vec4(0.78, 1.0, 0.82, 1.0);
uniform float intensity = 1.0;

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float t = TIME;
	float bands = 0.5 + 0.5 * sin(UV.y * 22.0 - t * 5.0 + UV.x * 7.0);
	float pulse = 0.82 + 0.18 * sin(t * 5.0 + UV.y * 4.0);

	float a = (0.14 + fres * 0.82) * pulse;
	a += bands * fres * 0.22;
	a = clamp(a * intensity, 0.0, 1.0);

	vec3 col = mix(orb_color.rgb, core_color.rgb, clamp(fres + bands * 0.18, 0.0, 1.0));
	ALBEDO = col * (1.0 + a * 0.9);
	ALPHA = a;
}
