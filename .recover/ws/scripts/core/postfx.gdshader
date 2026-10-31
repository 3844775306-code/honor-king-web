shader_type canvas_item;
// 全屏后处理：轻调色 + 暗角 + 受击边缘红晕 + 死亡去饱和 + 受击色差。
// 覆盖在 3D 之上、UI 之下（PostFX CanvasLayer.layer = 0）。

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

uniform float grade_strength : hint_range(0.0, 0.6) = 0.12;
uniform float saturation : hint_range(0.6, 1.6) = 1.07;
uniform float vignette : hint_range(0.0, 1.0) = 0.38;
uniform float vignette_radius : hint_range(0.2, 1.2) = 0.72;

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform vec3 damage_color = vec3(1.0, 0.16, 0.12);

uniform float dead : hint_range(0.0, 1.0) = 0.0;
uniform float aberration : hint_range(0.0, 1.0) = 0.0;

// 低血量：0=正常，1=濒死（由 PostFX 按本地英雄血量比例驱动）
uniform float low_hp : hint_range(0.0, 1.0) = 0.0;
uniform float low_hp_pulse : hint_range(0.0, 1.0) = 0.0;   // 心跳脉冲，GDScript 每帧推进
uniform vec3 low_hp_color = vec3(0.80, 0.05, 0.03);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float r = length(centered);

	float ab = aberration * 0.0032 * (0.35 + r);
	vec3 col;
	col.r = texture(screen_tex, uv + centered * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - centered * ab).b;

	// 亮度保底的轻度对比/饱和度（避免过曝酒红）
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(luma), col, saturation);
	col = (col - vec3(0.5)) * (1.0 + grade_strength) + vec3(0.5);

	// 死亡：去饱和 + 轻微压暗
	col = mix(col, vec3(luma) * 0.9, dead);

	// 暗角
	float v = smoothstep(vignette_radius, vignette_radius + 0.42, r);
	col *= 1.0 - v * vignette;

	// 低血量：边缘血色心跳 + 视野收窄 + 轻度褪色（越濒死越重，中心保持干净不挡操作）
	if (low_hp > 0.001) {
		float breathe = 0.60 + 0.40 * low_hp_pulse;
		float rim = smoothstep(0.28, 0.96, r);
		col = mix(col, low_hp_color, clamp(low_hp * rim * breathe * 0.62, 0.0, 0.78));
		col *= 1.0 - low_hp * rim * (0.16 + 0.24 * low_hp_pulse);   // 边缘压暗 = 视野收窄
		float luma2 = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(luma2), col, 1.0 - low_hp * 0.28);           // 褪色：彩色抽离的濒死感
	}

	// 受击：屏幕边缘红晕（中间保持干净）
	float edge = smoothstep(0.34, 0.98, r);
	col = mix(col, damage_color, damage * edge * 0.55);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
