extends RefCounted
## Buff 专属图标：按 buff key 关键字匹配 → 程序化矢量纹样（底部 Buff 图标盘中央绘制）。
## 主 B 图标盘仍由 UI_Manager.BuffIcon 负责（底/冷却扇形/计时小字），本文件只画中央图形。

## 关键字 → 图形（按顺序匹配，先具体后通用；key 形如 "mark_123|freeze" / "hs_wukong_aa"）
const RULES := [
	["jungle_protect", "leaf"],
	["tower_dive", "tower"],
	["knockup", "knockup"],
	["suppress", "chain"],
	["silence", "mute"],
	["grievous", "broken_heart"],
	["hasten", "up_arrows"],
	["stun", "stars"],
	["froze", "snow"],
	["freeze", "snow"],
	["slow", "hourglass"],
	["shield", "shield"],
	["shadow_junlin", "bolt_violet"],
	["junlin", "bolt"],
	["storm", "cyclone"],
	["red", "flame"],
	["blue", "orb"],
	["jungle", "leaf"],
	["atk_up", "sword"],
	["ap_up", "wand"],
	["armor_up", "plate"],
	["mr_up", "diamond"],
	["as_up", "swift"],
	["ms_up", "boot"],
	["frenzy", "claw"],
	["witch", "star_moon"],
	["sage", "fist"],
	["ice", "ice_fist"],
	["thornmail", "thorn"],
	["golden", "bell"],
	["sunspire", "sun"],
	["shadow", "shadow"],
	["bloodrage", "blood"],
	["chasewind", "wind"],
	["duskflow", "moon"],
	["fierce", "flame_armor"],
	["saintsword", "sword_gold"],
	["regen", "cross"],
	["revive", "phoenix"],
	["mark_", "seal"],
	["bt", "superarmor"],
	["wd", "invincible"],
	["hs_taiyi", "life"],
	["hs_arthur", "holy"],
	["hs_liushan", "talisman"],
	["hs_wukong", "staff"],
	["hs_libai", "sword"],
	["hs_lanling", "shadow"],
	["burn", "flame"],
	["poison", "poison"],
	["slow_mark", "hourglass"],
]

static func motif_for(key: String) -> String:
	var k := key.to_lower()
	for r in RULES:
		if k.find(str(r[0])) >= 0:
			return str(r[1])
	return "star"

## 在 Buff 圆盘中央画专属图形（k 为图形半径，col 为类别色）
static func draw_buff(ci: CanvasItem, center: Vector2, radius: float, key: String, col: Color) -> void:
	_motif(ci, center, radius, motif_for(key), col)

static func _motif(ci: CanvasItem, c: Vector2, k: float, id: String, col: Color) -> void:
	var w := maxf(k * 0.17, 1.6)
	var bright := col.lightened(0.42)
	match id:
		"stars":  # 眩晕：三颗环绕星
			for i in range(3):
				var a := -PI * 0.5 + i * TAU / 3.0
				var p := c + Vector2(cos(a), sin(a)) * k * 0.62
				for j in range(4):
					var b := j * PI / 2.0
					ci.draw_line(p, p + Vector2(cos(b), sin(b)) * k * 0.26, bright, w * 0.9, true)
			ci.draw_circle(c, k * 0.16, bright)
		"knockup":  # 击飞：上抛箭头 + 地面波纹
			ci.draw_line(c + Vector2(0, 0.72 * k), c + Vector2(0, -0.56 * k), bright, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.34 * k, -0.48 * k), c + Vector2(0.34 * k, -0.48 * k),
				c + Vector2(0, -0.98 * k)]), bright)
			ci.draw_arc(c + Vector2(0, 0.76 * k), k * 0.62, PI * 0.12, PI * 0.88, 12, col, w * 0.8, true)
		"snow":  # 冰冻：六角雪花
			for i in range(3):
				var a := i * PI / 3.0
				ci.draw_line(c - Vector2(cos(a), sin(a)) * k * 0.86,
					c + Vector2(cos(a), sin(a)) * k * 0.86, bright, w, true)
				for j in range(2):
					var s := -1.0 if j == 0 else 1.0
					var p := c + Vector2(cos(a), sin(a)) * k * 0.54 * s
					ci.draw_line(p, p + Vector2(cos(a + 1.05), sin(a + 1.05)) * k * 0.24, bright, w * 0.85, true)
			ci.draw_circle(c, k * 0.12, Color(1, 1, 1, 0.92))
		"mute":  # 沉默：喇叭 + 禁符
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.72 * k, -0.20 * k), c + Vector2(-0.34 * k, -0.20 * k),
				c + Vector2(0.10 * k, -0.62 * k), c + Vector2(0.10 * k, 0.62 * k),
				c + Vector2(-0.34 * k, 0.20 * k), c + Vector2(-0.72 * k, 0.20 * k)]), col)
			ci.draw_line(c + Vector2(0.28 * k, -0.44 * k), c + Vector2(0.80 * k, 0.44 * k), bright, w * 1.3, true)
			ci.draw_line(c + Vector2(0.80 * k, -0.44 * k), c + Vector2(0.28 * k, 0.44 * k), bright, w * 1.3, true)
		"chain":  # 压制：锁链
			for i in range(2):
				var p := c + Vector2((i - 0.5) * 0.62 * k, 0.0)
				ci.draw_arc(p, k * 0.34, PI * 0.15, PI * 0.85, 10, bright, w * 1.2, true)
				ci.draw_arc(p, k * 0.34, PI * 1.15, PI * 1.85, 10, bright, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.62 * k, -0.62 * k), c + Vector2(0.62 * k, 0.62 * k), col, w * 0.6, true)
		"hourglass":  # 减速：沙漏
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.58 * k, -0.82 * k), c + Vector2(0.58 * k, -0.82 * k),
				c + Vector2(-0.58 * k, 0.82 * k), c + Vector2(0.58 * k, 0.82 * k)]), bright, w, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.30 * k, -0.62 * k), c + Vector2(0.30 * k, -0.62 * k),
				c + Vector2(0, -0.06 * k)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.30 * k, 0.62 * k), c + Vector2(0.30 * k, 0.62 * k),
				c + Vector2(0, 0.06 * k)]), col)
		"up_arrows":  # 加速：双上扬箭头
			for i in range(2):
				var x := (-0.34 + i * 0.62) * k
				ci.draw_polyline(PackedVector2Array([
					c + Vector2(x - 0.24 * k, 0.42 * k), c + Vector2(x + 0.06 * k, -0.28 * k),
					c + Vector2(x + 0.36 * k, 0.42 * k)]), bright, w * 1.1, true)
		"broken_heart":  # 重伤：裂心
			ci.draw_circle(c + Vector2(-0.26 * k, -0.20 * k), k * 0.30, col)
			ci.draw_circle(c + Vector2(0.26 * k, -0.20 * k), k * 0.30, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.52 * k, -0.06 * k), c + Vector2(0.52 * k, -0.06 * k),
				c + Vector2(0, 0.72 * k)]), col)
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(0.02 * k, -0.42 * k), c + Vector2(-0.18 * k, 0.02 * k),
				c + Vector2(0.10 * k, 0.24 * k), c + Vector2(-0.10 * k, 0.66 * k)]), bright, w, true)
		"shield":  # 护盾：盾形
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.58 * k, -0.52 * k), c + Vector2(0, -0.84 * k),
				c + Vector2(0.58 * k, -0.52 * k), c + Vector2(0.58 * k, 0.18 * k),
				c + Vector2(0, 0.90 * k), c + Vector2(-0.58 * k, 0.18 * k),
				c + Vector2(-0.58 * k, -0.52 * k)]), bright, w * 1.1, true)
			ci.draw_line(c + Vector2(0, -0.40 * k), c + Vector2(0, 0.44 * k), col, w * 0.8, true)
		"flame":  # 火焰（红/灼烧）
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.92 * k), c + Vector2(0.46 * k, -0.10 * k),
				c + Vector2(0.28 * k, 0.62 * k), c + Vector2(0, 0.86 * k),
				c + Vector2(-0.28 * k, 0.62 * k), c + Vector2(-0.46 * k, -0.10 * k)]), col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.02 * k, -0.24 * k), c + Vector2(0.24 * k, 0.28 * k),
				c + Vector2(0, 0.70 * k), c + Vector2(-0.24 * k, 0.28 * k)]), bright)
		"orb":  # 蓝 Buff：法球 + 环绕弧
			ci.draw_circle(c, k * 0.44, col)
			ci.draw_circle(c + Vector2(-0.14 * k, -0.14 * k), k * 0.16, Color(1, 1, 1, 0.85))
			for i in range(2):
				ci.draw_arc(c, k * (0.72 + i * 0.20), -PI * 0.80 + i * 0.6, PI * 0.20 + i * 0.6,
					12, Color(bright.r, bright.g, bright.b, 0.9 - i * 0.25), w * 0.85, true)
		"leaf":  # 打野/野区：叶片
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.70 * k, 0.62 * k), c + Vector2(-0.30 * k, -0.42 * k),
				c + Vector2(0.62 * k, -0.72 * k), c + Vector2(0.30 * k, 0.34 * k)]), col)
			ci.draw_line(c + Vector2(-0.62 * k, 0.56 * k), c + Vector2(0.50 * k, -0.60 * k), bright, w * 0.8, true)
		"cyclone":  # 风暴：旋风
			var pts := PackedVector2Array()
			for i in range(16):
				var t := float(i) / 15.0
				var a := t * TAU * 1.5
				pts.append(c + Vector2(cos(a), sin(a)) * k * (0.18 + 0.70 * t))
			ci.draw_polyline(pts, bright, w, true)
		"bolt":  # 君临：闪电
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.18 * k, -0.92 * k), c + Vector2(-0.46 * k, 0.14 * k),
				c + Vector2(-0.06 * k, 0.14 * k), c + Vector2(-0.26 * k, 0.92 * k),
				c + Vector2(0.48 * k, -0.18 * k), c + Vector2(0.06 * k, -0.18 * k)]), col)
		"bolt_violet":  # 暗影君临：紫电 + 双叉
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.10 * k, -0.92 * k), c + Vector2(-0.52 * k, 0.10 * k),
				c + Vector2(-0.10 * k, 0.10 * k), c + Vector2(-0.28 * k, 0.92 * k),
				c + Vector2(0.42 * k, -0.16 * k), c + Vector2(0.02 * k, -0.16 * k)]), col)
			ci.draw_line(c + Vector2(0.44 * k, -0.70 * k), c + Vector2(0.82 * k, -0.34 * k), bright, w * 0.9, true)
		"sword":  # 攻击增益：剑
			ci.draw_line(c + Vector2(-0.52 * k, 0.76 * k), c + Vector2(0.44 * k, -0.62 * k), bright, w * 1.2, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.44 * k, -0.62 * k), c + Vector2(0.72 * k, -0.86 * k),
				c + Vector2(0.62 * k, -0.44 * k)]), bright)
			ci.draw_line(c + Vector2(-0.62 * k, 0.36 * k), c + Vector2(-0.20 * k, 0.80 * k), col, w, true)
		"wand":  # 法术增益：法杖 + 星
			ci.draw_line(c + Vector2(-0.42 * k, 0.86 * k), c + Vector2(0.20 * k, -0.30 * k), bright, w * 1.2, true)
			for i in range(4):
				var a := i * PI / 2.0
				ci.draw_line(c + Vector2(0.34 * k, -0.52 * k),
					c + Vector2(0.34 * k, -0.52 * k) + Vector2(cos(a), sin(a)) * k * 0.42, col, w * 0.9, true)
		"plate":  # 护甲：甲片
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.66 * k, -0.66 * k), c + Vector2(0.66 * k, -0.66 * k),
				c + Vector2(0.66 * k, 0.34 * k), c + Vector2(0, 0.86 * k),
				c + Vector2(-0.66 * k, 0.34 * k), c + Vector2(-0.66 * k, -0.66 * k)]), bright, w * 1.1, true)
			ci.draw_line(c + Vector2(-0.40 * k, -0.10 * k), c + Vector2(0.40 * k, -0.10 * k), col, w * 0.9, true)
		"diamond":  # 魔抗：菱形护符
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(0, -0.86 * k), c + Vector2(0.62 * k, 0), c + Vector2(0, 0.86 * k),
				c + Vector2(-0.62 * k, 0), c + Vector2(0, -0.86 * k)]), bright, w * 1.1, true)
			ci.draw_circle(c, k * 0.20, col)
		"swift":  # 攻速：双速线
			for i in range(3):
				var y := (-0.42 + i * 0.42) * k
				ci.draw_line(c + Vector2(-0.72 * k, y), c + Vector2(0.32 * k, y), bright, w * 1.1, true)
				ci.draw_colored_polygon(PackedVector2Array([
					c + Vector2(0.32 * k, y - 0.20 * k), c + Vector2(0.82 * k, y),
					c + Vector2(0.32 * k, y + 0.20 * k)]), col)
		"boot":  # 移速：靴
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.30 * k, -0.86 * k), c + Vector2(-0.30 * k, 0.20 * k),
				c + Vector2(0.30 * k, 0.48 * k), c + Vector2(0.72 * k, 0.70 * k),
				c + Vector2(0.72 * k, 0.90 * k), c + Vector2(-0.62 * k, 0.90 * k),
				c + Vector2(-0.62 * k, -0.86 * k), c + Vector2(-0.30 * k, -0.86 * k)]), bright, w * 1.1, true)
			ci.draw_line(c + Vector2(-0.72 * k, -0.20 * k), c + Vector2(-0.56 * k, -0.44 * k), col, w * 0.9, true)
		"claw":  # 狂暴：爪痕
			for i in range(3):
				var x := (-0.42 + i * 0.42) * k
				ci.draw_line(c + Vector2(x - 0.16 * k, -0.72 * k), c + Vector2(x + 0.16 * k, 0.72 * k), bright, w * 1.1, true)
		"star_moon":  # 巫术：月 + 星
			ci.draw_arc(c + Vector2(-0.10 * k, 0.06 * k), k * 0.64, PI * 0.45, PI * 1.55, 16, bright, w * 1.2, true)
			for i in range(3):
				var a := i * TAU / 3.0 + 0.6
				ci.draw_line(c + Vector2(0.44 * k, -0.52 * k),
					c + Vector2(0.44 * k, -0.52 * k) + Vector2(cos(a), sin(a)) * k * 0.26, col, w * 0.8, true)
		"fist":  # 宗师：拳
			ci.draw_circle(c, k * 0.58, col)
			for i in range(3):
				ci.draw_line(c + Vector2(-0.34 * k, (-0.16 + i * 0.28) * k),
					c + Vector2(0.30 * k, (-0.16 + i * 0.28) * k), bright, w * 0.9, true)
		"ice_fist":  # 冰痕：冰晶拳
			for i in range(4):
				var a := -PI * 0.5 + i * PI * 0.5
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * k * 0.86, bright, w, true)
			ci.draw_circle(c, k * 0.22, col)
		"thorn":  # 反伤：荆棘
			ci.draw_arc(c, k * 0.56, 0, TAU, 22, bright, w, true)
			for i in range(6):
				var a := i * TAU / 6.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.56,
					c + Vector2(cos(a), sin(a)) * k * 1.0, col, w * 1.3, true)
		"bell":  # 辉月：金钟罩
			ci.draw_arc(c + Vector2(0, 0.10 * k), k * 0.62, PI * 1.02, PI * 1.98, 18, bright, w * 1.3, true)
			ci.draw_line(c + Vector2(-0.62 * k, 0.12 * k), c + Vector2(0.62 * k, 0.12 * k), bright, w * 0.9, true)
			ci.draw_circle(c + Vector2(0, 0.52 * k), k * 0.14, col)
		"sun":  # 逐日：日轮
			ci.draw_circle(c, k * 0.34, col)
			for i in range(8):
				var a := i * TAU / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.52,
					c + Vector2(cos(a), sin(a)) * k * 0.86, bright, w * 0.9, true)
		"shadow":  # 幽影：隐身剪影
			ci.draw_circle(c + Vector2(-0.04 * k, -0.20 * k), k * 0.34, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.62 * k, 0.86 * k), c + Vector2(-0.34 * k, 0.06 * k),
				c + Vector2(0.34 * k, 0.06 * k), c + Vector2(0.62 * k, 0.86 * k)]), col)
			for i in range(3):
				ci.draw_arc(c + Vector2(0, 0.10 * k), k * (0.56 + i * 0.14), PI * 1.1, PI * 1.9,
					10, Color(bright.r, bright.g, bright.b, 0.5 - i * 0.12), w * 0.6, true)
		"blood":  # 血魔：血滴
			ci.draw_circle(c + Vector2(0, 0.24 * k), k * 0.50, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.86 * k), c + Vector2(0.40 * k, -0.06 * k),
				c + Vector2(-0.40 * k, -0.06 * k)]), col)
			ci.draw_circle(c + Vector2(-0.16 * k, 0.14 * k), k * 0.12, Color(1, 1, 1, 0.8))
		"wind":  # 逐风：风纹
			for i in range(3):
				var y := (-0.36 + i * 0.36) * k
				ci.draw_arc(c + Vector2(0.10 * k, y), k * 0.52, PI * 1.10, PI * 2.05, 12, bright, w * 0.9, true)
		"moon":  # 日暮：月牙
			ci.draw_arc(c, k * 0.72, PI * 0.42, PI * 1.58, 18, bright, w * 1.3, true)
			ci.draw_circle(c + Vector2(0.30 * k, 0.02 * k), k * 0.10, col)
		"flame_armor":  # 暴烈：焰甲
			ci.draw_polyline(PackedVector2Array([
				c + Vector2(-0.62 * k, -0.50 * k), c + Vector2(0, -0.80 * k),
				c + Vector2(0.62 * k, -0.50 * k), c + Vector2(0.46 * k, 0.34 * k),
				c + Vector2(0, 0.84 * k), c + Vector2(-0.46 * k, 0.34 * k),
				c + Vector2(-0.62 * k, -0.50 * k)]), bright, w, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.28 * k), c + Vector2(0.26 * k, 0.22 * k),
				c + Vector2(0, 0.62 * k), c + Vector2(-0.26 * k, 0.22 * k)]), col)
		"sword_gold":  # 圣剑：金剑 + 光
			ci.draw_line(c + Vector2(-0.52 * k, 0.80 * k), c + Vector2(0.46 * k, -0.68 * k), bright, w * 1.3, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.46 * k, -0.68 * k), c + Vector2(0.76 * k, -0.92 * k),
				c + Vector2(0.64 * k, -0.48 * k)]), bright)
			for i in range(2):
				ci.draw_line(c + Vector2(-0.70 * k, (0.10 + i * 0.30) * k),
					c + Vector2(-0.34 * k, (0.10 + i * 0.30) * k), col, w * 0.7, true)
		"cross":  # 回复：绿十字 + 光晕
			ci.draw_arc(c, k * 0.84, 0, TAU, 24, Color(col.r, col.g, col.b, 0.55), w * 0.7, true)
			ci.draw_rect(Rect2(c.x - 0.16 * k, c.y - 0.60 * k, 0.32 * k, 1.20 * k), bright)
			ci.draw_rect(Rect2(c.x - 0.60 * k, c.y - 0.16 * k, 1.20 * k, 0.32 * k), bright)
		"phoenix":  # 复活：羽翼
			for i in range(2):
				var s := -1.0 if i == 0 else 1.0
				for j in range(3):
					ci.draw_line(c + Vector2(s * 0.10 * k, 0.16 * k),
						c + Vector2(s * (0.54 + j * 0.16) * k, -0.62 * k + j * 0.32 * k),
						bright, w * 0.9, true)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.36 * k), c + Vector2(0.20 * k, 0.04 * k),
				c + Vector2(0, 0.50 * k), c + Vector2(-0.20 * k, 0.04 * k)]), col)
		"seal":  # 印记：六芒法阵
			ci.draw_arc(c, k * 0.82, 0, TAU, 24, Color(bright.r, bright.g, bright.b, 0.85), w * 0.8, true)
			for i in range(2):
				var rot := i * PI / 3.0
				for j in range(3):
					var a := rot + j * TAU / 3.0
					var a2 := rot + ((j + 1) % 3) * TAU / 3.0
					ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.62,
						c + Vector2(cos(a2), sin(a2)) * k * 0.62, col, w * 0.8, true)
			ci.draw_circle(c, k * 0.14, bright)
		"superarmor":  # 霸体：铁壁
			ci.draw_rect(Rect2(c.x - 0.62 * k, c.y - 0.62 * k, 1.24 * k, 1.24 * k), col)
			for i in range(2):
				var y := (-0.22 + i * 0.44) * k
				ci.draw_line(c + Vector2(-0.34 * k, y), c + Vector2(0.34 * k, y), bright, w * 0.9, true)
		"invincible":  # 无敌：光环 + 星
			ci.draw_arc(c, k * 0.80, 0, TAU, 26, bright, w * 1.2, true)
			for i in range(4):
				var a := i * TAU / 4.0 + 0.4
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * k * 0.54, col, w * 1.1, true)
		"life":  # 太乙守护：生命树
			ci.draw_line(c + Vector2(0, 0.86 * k), c + Vector2(0, -0.10 * k), col, w * 1.3, true)
			ci.draw_arc(c + Vector2(0, -0.30 * k), k * 0.48, PI * 0.15, PI * 0.85, 12, bright, w, true)
			for i in range(2):
				var s := -1.0 if i == 0 else 1.0
				ci.draw_arc(c + Vector2(s * 0.46 * k, -0.30 * k), k * 0.30, 0, TAU, 14, bright, w * 0.8, true)
		"holy":  # 誓约/圣盾：圣徽
			ci.draw_circle(c, k * 0.52, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.90 * k), c + Vector2(0.22 * k, -0.24 * k),
				c + Vector2(0.90 * k, 0), c + Vector2(0.22 * k, 0.24 * k),
				c + Vector2(0, 0.90 * k), c + Vector2(-0.22 * k, 0.24 * k),
				c + Vector2(-0.90 * k, 0), c + Vector2(-0.22 * k, -0.24 * k)]), bright)
		"talisman":  # 小霸王护符：符牌
			ci.draw_style_box(UiKit.flat(0.92, int(k * 0.18), int(maxf(k * 0.14, 2.0)), bright,
				Color(0.05, 0.06, 0.10, 0.92), 0.0, 0.0),
				Rect2(c - Vector2(0.36 * k, 0.82 * k), Vector2(0.72 * k, 1.64 * k)))
			for i in range(3):
				ci.draw_line(c + Vector2(-0.18 * k, (-0.34 + i * 0.36) * k),
					c + Vector2(0.18 * k, (-0.34 + i * 0.36) * k), col, w * 0.8, true)
		"staff":  # 金箍棒
			ci.draw_line(c + Vector2(-0.30 * k, 0.86 * k), c + Vector2(0.30 * k, -0.86 * k), bright, w * 1.3, true)
			ci.draw_circle(c + Vector2(-0.30 * k, 0.86 * k), k * 0.16, col)
			ci.draw_circle(c + Vector2(0.30 * k, -0.86 * k), k * 0.16, col)
		"tower":  # 越塔
			for i in range(3):
				var ww := k * (0.82 - i * 0.18)
				var y := c.y + (0.58 - i * 0.40) * k
				ci.draw_rect(Rect2(c.x - ww * 0.5, y - 0.28 * k, ww, 0.28 * k), col)
			ci.draw_line(c + Vector2(0, -0.26 * k), c + Vector2(0, -0.68 * k), col, w, true)
			ci.draw_circle(c + Vector2(0, -0.82 * k), k * 0.16, bright)
		"poison":  # 中毒：滴 + 泡
			ci.draw_circle(c + Vector2(0, 0.26 * k), k * 0.46, col)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -0.84 * k), c + Vector2(0.36 * k, -0.06 * k),
				c + Vector2(-0.36 * k, -0.06 * k)]), col)
			ci.draw_circle(c + Vector2(-0.16 * k, 0.16 * k), k * 0.10, bright)
		_:  # 通用：四芒星
			for i in range(4):
				var a := i * PI / 2.0
				ci.draw_line(c, c + Vector2(cos(a), sin(a)) * k * 0.84, bright, w * 1.1, true)
			ci.draw_circle(c, k * 0.18, col)
