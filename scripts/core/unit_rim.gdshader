shader_type spatial;
// 英雄可读性：边缘 rim 光 + 受击闪白。
// 通过 MeshInstance3D.material_overlay 叠加在原始材质之上（不覆盖 base 贴图），
// 单层加法混合，仅提升轮廓亮度与受击反馈，开销很小（无第二份网格）。
render_mode blend_add, unshaded, cull_back, depth_draw_never;

uniform vec4 rim_color : source_color = vec4(0.25, 0.85, 1.0, 1.0); // 队伍色（青/红）
uniform float rim_power : hint_range(0.5, 8.0) = 2.2;
uniform float rim_strength : hint_range(0.0, 3.0) = 0.75;
uniform float hit : hint_range(0.0, 1.0) = 0.0;                     // 受击闪白 0..1
uniform vec4 hit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = mix(rim_color.rgb * rim_strength, hit_color.rgb, clamp(hit, 0.0, 1.0)) * f
		+ hit_color.rgb * hit * 0.22;
	ALPHA = 1.0;
}
