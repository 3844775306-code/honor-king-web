shader_type spatial;
// 地面范围圈（塔攻击范围/玩家攻击范围/野怪活动范围）：
// 1) 顶点阶段复用地面 shader 的野区起伏位移 → 圈跟着地形起伏走，不再插进土里或浮空；
// 2) 片元阶段用「柔化环带 + 极淡内填充 + 细刻度 + 低频磨损斑驳」→ 像染在地面上，而不是贴纸/塑料环。
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 ring_color : source_color = vec4(0.55, 0.85, 1.0, 0.5);
uniform float intensity = 1.0;
uniform float ring_pos : hint_range(0.4, 1.0) = 0.94;      // 环带归一化半径（相对贴片半径）
uniform float edge_width : hint_range(0.004, 0.14) = 0.032; // 环带柔化宽度（归一化）
uniform float rim_strength : hint_range(0.0, 1.5) = 0.55;   // 内缘细亮边（给出清晰边界）
uniform float fill_alpha : hint_range(0.0, 0.4) = 0.06;     // 圈内极淡填充
uniform float dash_count = 72.0;                            // 刻度数量（0=关）
uniform float dash_strength : hint_range(0.0, 1.0) = 0.5;   // 刻度对环带的调制强度
uniform float spin_speed = 0.04;                            // 刻度缓慢转动
uniform float bump_amount = 0.28;                           // 与 MapVisuals.ground_material(0.28) 对齐
uniform float wear : hint_range(0.0, 1.0) = 0.3;            // 磨损/斑驳强度

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// 与 MapVisuals._GROUND_CODE 完全一致的野区微地形（分路/河道/高地自动保持平面）
	if (bump_amount > 0.001) {
		float lane_d = min(min(abs(abs(wp.x) - 55.0), abs(abs(wp.z) - 55.0)), abs(wp.x + wp.z) * 0.7071068);
		float lane_m = 1.0 - smoothstep(7.0, 13.0, lane_d);
		float river_m = 1.0 - smoothstep(10.0, 15.0, abs(wp.x - wp.z) * 0.7071068);
		float hg_m = 1.0 - smoothstep(30.0, 38.0, min(length(wp.xz + vec2(60.0, -60.0)), length(wp.xz - vec2(60.0, -60.0))));
		float edge_m = 1.0 - smoothstep(56.0, 70.0, max(abs(wp.x), abs(wp.z)));
		float jungle_m = clamp(1.0 - lane_m - river_m - hg_m, 0.0, 1.0) * edge_m;
		float n = sin(wp.x * 0.34) * cos(wp.z * 0.29) * 0.65 + sin(wp.x * 0.81 + 1.7) * cos(wp.z * 0.67 - 0.9) * 0.35;
		VERTEX.y += n * bump_amount * jungle_m;
	}
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	float ang = atan(p.y, p.x);

	// 主环带：内外两侧都柔化，避免硬边"塑料环"
	float band = 1.0 - smoothstep(0.0, edge_width, abs(d - ring_pos));
	// 内缘细亮边：给出可读的准确射程边界
	float rim = 1.0 - smoothstep(0.0, edge_width * 0.45, abs(d - ring_pos + edge_width * 0.35));
	// 细刻度：分段虚线，随 TIME 缓慢转动
	float dash_k = 1.0;
	if (dash_count > 0.5) {
		float seg = fract(ang / 6.2831853 * dash_count + TIME * spin_speed);
		dash_k = mix(1.0, 0.45 + 0.55 * step(0.5, seg), dash_strength * smoothstep(0.0, edge_width * 3.0, abs(d - ring_pos)));
	}
	// 圈内极淡填充：中心最淡、靠近环带渐强，让圈"有体积"但不遮挡地面
	float fill = smoothstep(ring_pos * 1.02, ring_pos * 0.1, d);
	// 低频磨损：与地面纹理同尺度的斑驳，避免大片纯色
	float grain = sin(wp.x * 0.73 + 1.3) * cos(wp.z * 0.61 - 0.7) * 0.5
		+ sin(wp.x * 1.7 - wp.z * 1.1 + 0.6) * 0.32;
	float wear_k = 1.0 - wear * clamp(0.45 + 0.55 * grain, 0.0, 1.0);

	float a = band * dash_k * wear_k + rim * rim_strength * wear_k + fill * fill_alpha;
	ALBEDO = ring_color.rgb * intensity;
	ALPHA = clamp(a * ring_color.a, 0.0, 1.0);
}
