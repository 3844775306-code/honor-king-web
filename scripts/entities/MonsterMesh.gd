extends RefCounted
## 程序化野怪模型（替换 model/monster/*.glb 与 DragonBaby.glb）
## 风格：粗粝兽皮 + 石质角/背刺 + 发光眼，与地图的石墙/石砖/苔藓同族。
## 每只野怪合并为 2 个网格（躯体 + 发光部件），主机与联机客户端共用。

static var _hide_shader: Shader = null
static var _hide_mats: Dictionary = {}
static var _glow_mats: Dictionary = {}

static func hide_material(c: Color) -> ShaderMaterial:
	var key := "%d_%d_%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
	if _hide_mats.has(key):
		return _hide_mats[key]
	if _hide_shader == null:
		_hide_shader = Shader.new()
		_hide_shader.code = _HIDE_CODE
	var m := ShaderMaterial.new()
	m.shader = _hide_shader
	m.set_shader_parameter("body_color", c)
	m.set_shader_parameter("belly_color", c.lightened(0.22))
	m.set_shader_parameter("dark_color", c.darkened(0.35))
	_hide_mats[key] = m
	return m

static func glow_material(c: Color) -> StandardMaterial3D:
	var key := "%d_%d_%d" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
	if _glow_mats.has(key):
		return _glow_mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 1.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0
	m.roughness = 0.3
	_glow_mats[key] = m
	return m

# ==================== 对外入口 ====================

static func visual(type_name: String) -> Node3D:
	var basic := type_name.replace("_small", "").replace("_big", "")
	var root := Node3D.new()
	root.name = "MonsterVisual"
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glow := SurfaceTool.new()
	glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hide_c := Color(0.42, 0.36, 0.30)
	var glow_c := Color(0.0, 0.0, 0.0)
	var glow_amt := 0.0
	var sc := 1.0
	match basic:
		"pig":
			hide_c = Color(0.45, 0.38, 0.31)
			_quadruped(body, glow, {
				"leg": 0.30, "bw": 0.88, "bh": 0.64, "bl": 1.06, "head": 0.40,
				"snout": 0.26, "tusks": 2, "tail": 0.30, "hump": true, "eye": 0.055,
			})
		"wolf":
			hide_c = Color(0.34, 0.33, 0.32)
			glow_c = Color(1.0, 0.72, 0.25)
			glow_amt = 1.0
			_quadruped(body, glow, {
				"leg": 0.44, "bw": 0.64, "bh": 0.52, "bl": 1.10, "head": 0.30,
				"snout": 0.22, "ears": 2, "tail": 0.62, "eye": 0.055,
			})
		"lizard":
			hide_c = Color(0.33, 0.40, 0.27)
			glow_c = Color(0.55, 0.95, 0.45)
			glow_amt = 1.0
			_quadruped(body, glow, {
				"leg": 0.22, "bw": 1.02, "bh": 0.42, "bl": 0.96, "head": 0.34,
				"snout": 0.20, "spikes": 4, "tail": 0.78, "splay": true, "eye": 0.05,
			})
		"monkey":
			hide_c = Color(0.36, 0.29, 0.23)
			glow_c = Color(1.0, 0.62, 0.20)
			glow_amt = 1.0
			_quadruped(body, glow, {
				"leg": 0.30, "bw": 0.58, "bh": 0.66, "bl": 0.72, "head": 0.30,
				"snout": 0.12, "ears": 2, "tail": 0.70, "arms": true, "eye": 0.052,
			})
		"red_buff":
			hide_c = Color(0.55, 0.27, 0.15)
			glow_c = Color(1.0, 0.45, 0.12)
			glow_amt = 1.0
			sc = 1.0
			_quadruped(body, glow, {
				"leg": 0.40, "bw": 0.98, "bh": 0.74, "bl": 1.46, "head": 0.44,
				"snout": 0.26, "ears": 2, "tusks": 2, "tail": 0.86, "hump": true, "eye": 0.07,
			})
		"blue_buff":
			hide_c = Color(0.33, 0.44, 0.56)
			glow_c = Color(0.35, 0.85, 1.0)
			glow_amt = 1.0
			sc = 1.0
			_quadruped(body, glow, {
				"leg": 0.40, "bw": 0.98, "bh": 0.74, "bl": 1.46, "head": 0.44,
				"snout": 0.26, "ears": 2, "horns": 2, "tail": 0.86, "hump": true, "eye": 0.07,
			})
		"bird":
			hide_c = Color(0.28, 0.45, 0.30)
			glow_c = Color(1.0, 0.70, 0.18)
			glow_amt = 1.0
			sc = 1.05
			_bird(body, glow, glow_c)
		"worm":
			hide_c = Color(0.47, 0.41, 0.28)
			_worm(body, glow)
		"spatial_spirit":
			hide_c = Color(0.42, 0.46, 0.52)
			glow_c = Color(0.62, 0.90, 1.0)
			glow_amt = 1.0
			_spirit(body, glow, 1.0)
		"river_spirit":
			hide_c = Color(0.34, 0.46, 0.52)
			glow_c = Color(0.35, 0.85, 0.95)
			glow_amt = 1.0
			_spirit(body, glow, 0.86)
		"tyrant", "dragon":
			hide_c = Color(0.33, 0.29, 0.34)
			glow_c = Color(0.85, 0.35, 1.0)
			glow_amt = 1.0
			sc = 0.72
			_dragon(body, glow)
		"shadow_tyrant", "shadow_dragon":
			hide_c = Color(0.20, 0.18, 0.24)
			glow_c = Color(1.0, 0.25, 0.55)
			glow_amt = 1.0
			sc = 0.72
			_dragon(body, glow)
		"storm_dragon":
			hide_c = Color(0.26, 0.32, 0.42)
			glow_c = Color(0.45, 1.0, 0.95)
			glow_amt = 1.0
			sc = 0.72
			_dragon(body, glow)
		_:
			hide_c = Color(0.42, 0.36, 0.30)
			_quadruped(body, glow, {"leg": 0.32, "bw": 0.78, "bh": 0.58, "bl": 0.98, "head": 0.34, "snout": 0.16, "tail": 0.4, "eye": 0.05})
	# 普通野怪体型收一点：与兵线/英雄比例协调（史诗龙单独缩小过）
	if basic in ["pig", "wolf", "lizard", "monkey", "worm"]:
		sc = 0.8
	elif basic == "bird":
		sc = 0.85
	# 动画挂点：内外分离，外层交给 WalkFeel 步态，内层做 idle/move/attack/die
	var anim := Node3D.new()
	anim.name = "Anim"
	root.add_child(anim)
	var bm := MeshInstance3D.new()
	bm.name = "Body"
	bm.mesh = body.commit()
	bm.material_override = hide_material(hide_c)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	bm.scale = Vector3.ONE * sc
	anim.add_child(bm)
	var gm := MeshInstance3D.new()
	gm.name = "Glow"
	gm.mesh = glow.commit()
	gm.material_override = glow_material(glow_c if glow_amt > 0.0 else Color(0.9, 0.9, 0.9))
	gm.scale = Vector3.ONE * sc
	anim.add_child(gm)
	return root

# ==================== 四足兽（猪/狼/蜥/猴/虎/熊） ====================

static func _quadruped(st: SurfaceTool, glow: SurfaceTool, p: Dictionary) -> void:
	var leg: float = float(p["leg"])
	var bw: float = float(p["bw"])
	var bh: float = float(p["bh"])
	var bl: float = float(p["bl"])
	var head: float = float(p["head"])
	var hy: float = leg + bh * 0.55
	var splay: bool = bool(p.get("splay", false))
	_put(st, _sph(), Vector3(0.0, hy, 0.0), Vector3(bw, bh, bl) * 0.5)
	if bool(p.get("hump", false)):
		_put(st, _sph(), Vector3(0.0, hy + bh * 0.30, bl * 0.14), Vector3(bw * 0.80, bh * 0.66, bl * 0.52))
	var hz: float = bl * 0.5 + head * 0.62
	var hyy: float = hy + bh * 0.16
	# 脖子：向前上方的短柱
	_put(st, _cap(), Vector3(0.0, hy + bh * 0.18, bl * 0.30), Vector3(head * 1.0, head * 1.5, head * 1.0), 0.0, 0.55)
	# 头
	_put(st, _sph(), Vector3(0.0, hyy + head * 0.52, hz), Vector3(head, head * 0.88, head * 1.12))
	# 吻部
	var sn: float = float(p.get("snout", 0.0))
	if sn > 0.01:
		_put(st, _cone(), Vector3(0.0, hyy + head * 0.38, hz + head * 0.95), Vector3(head * 0.44, sn, head * 0.40), 0.0, PI * 0.5)
	# 耳/角
	var ears: int = int(p.get("ears", 0))
	for i: int in range(ears):
		var sx: float = -1.0 if i == 0 else 1.0
		_put(st, _cone(), Vector3(sx * head * 0.42, hyy + head * 1.14, hz - head * 0.18), Vector3(head * 0.20, head * 0.52, head * 0.16), 0.0, 0.10)
	var horns: int = int(p.get("horns", 0))
	for i: int in range(horns):
		var sx2: float = -1.0 if i == 0 else 1.0
		_put(st, _cone(), Vector3(sx2 * head * 0.40, hyy + head * 1.05, hz + head * 0.22), Vector3(head * 0.16, head * 1.05, head * 0.16), 0.0, -0.45)
	# 獠牙（象牙色：放进发光网格但用低亮）
	var tusks: int = int(p.get("tusks", 0))
	for i: int in range(tusks):
		var sx3: float = -1.0 if i == 0 else 1.0
		_put(glow, _cone(), Vector3(sx3 * head * 0.28, hyy + head * 0.20, hz + head * 0.90), Vector3(head * 0.07, head * 0.42, head * 0.07), 0.0, -0.9)
	# 背刺
	var spikes: int = int(p.get("spikes", 0))
	for i: int in range(spikes):
		var t: float = float(i) / float(maxi(spikes - 1, 1))
		var zz: float = lerpf(-bl * 0.34, bl * 0.30, t)
		var ss: float = 0.30 + 0.22 * sin(t * PI)
		_put(st, _cone(), Vector3(0.0, hy + bh * 0.46, zz), Vector3(bw * 0.13, bh * ss, bw * 0.13), 0.0, 0.0)
	# 四肢
	var ly: float = leg * 0.52
	for i: int in range(4):
		var sx4: float = -1.0 if (i % 2 == 0) else 1.0
		var sz4: float = -1.0 if i < 2 else 1.0
		var lx: float = sx4 * bw * (0.40 if not splay else 0.50)
		var lz: float = sz4 * bl * (0.30 if not splay else 0.34)
		_put(st, _cap(), Vector3(lx, ly, lz), Vector3(bw * 0.26, leg, bw * 0.26), 0.0, 0.0)
		_put(st, _sph(), Vector3(lx + sx4 * bw * 0.04, bw * 0.10, lz), Vector3(bw * 0.17, bw * 0.10, bw * 0.22))
	# 前肢（猴子式长臂）
	if bool(p.get("arms", false)):
		for i: int in range(2):
			var sx5: float = -1.0 if i == 0 else 1.0
			_put(st, _cap(), Vector3(sx5 * bw * 0.46, hy * 0.94, bl * 0.28), Vector3(bw * 0.20, hy * 1.05, bw * 0.20), 0.0, -0.12)
	# 尾巴
	var tail: float = float(p.get("tail", 0.0))
	if tail > 0.02:
		for i: int in range(3):
			var t2: float = float(i) / 2.0
			var tr: float = lerpf(bw * 0.13, bw * 0.05, t2)
			_put(st, _cap(), Vector3(0.0, hy - bh * 0.06 + tail * 0.30 * t2 * t2, -bl * (0.50 + 0.30 * t2)), Vector3(tr, tail * 0.52, tr), 0.0, 1.15 - 0.5 * t2)
	# 发光眼
	var er: float = float(p.get("eye", 0.055))
	for i: int in range(2):
		var sx6: float = -1.0 if i == 0 else 1.0
		_put(glow, _sph(), Vector3(sx6 * head * 0.36, hyy + head * 0.66, hz + head * 0.62), Vector3(er, er, er))

# ==================== 巨鸟 ====================

static func _bird(st: SurfaceTool, glow: SurfaceTool, gc: Color) -> void:
	var hy: float = 0.52
	_put(st, _sph(), Vector3(0.0, hy, 0.0), Vector3(0.34, 0.30, 0.46))
	_put(st, _sph(), Vector3(0.0, hy + 0.30, 0.24), Vector3(0.20, 0.19, 0.21))
	_put(st, _cone(), Vector3(0.0, hy + 0.28, 0.46), Vector3(0.075, 0.26, 0.06), 0.0, PI * 0.5)
	# 冠
	_put(st, _cone(), Vector3(0.0, hy + 0.52, 0.16), Vector3(0.045, 0.20, 0.03), 0.0, -0.35)
	# 双翼（后掠宽板）
	for i: int in range(2):
		var sx: float = -1.0 if i == 0 else 1.0
		_put(st, _box(), Vector3(sx * 0.40, hy + 0.10, -0.04), Vector3(0.52, 0.05, 0.34), sx * 0.30, 0.0, sx * 0.34)
		_put(st, _box(), Vector3(sx * 0.62, hy + 0.06, -0.24), Vector3(0.34, 0.04, 0.26), sx * 0.55, 0.0, sx * 0.22)
	# 尾羽
	for i: int in range(3):
		var a: float = (float(i) - 1.0) * 0.35
		_put(st, _box(), Vector3(sin(a) * 0.16, hy - 0.02, -0.42), Vector3(0.13, 0.035, 0.40), a, 0.22, 0.0)
	# 腿
	for i: int in range(2):
		var sx2: float = -1.0 if i == 0 else 1.0
		_put(st, _cap(), Vector3(sx2 * 0.14, 0.20, 0.02), Vector3(0.055, 0.44, 0.055))
		_put(st, _box(), Vector3(sx2 * 0.14, 0.015, 0.09), Vector3(0.11, 0.03, 0.20))
	for i: int in range(2):
		var sx3: float = -1.0 if i == 0 else 1.0
		_put(glow, _sph(), Vector3(sx3 * 0.10, hy + 0.34, 0.42), Vector3(0.04, 0.04, 0.04))
	# 羽冠发光点
	_put(glow, _sph(), Vector3(0.0, hy + 0.62, 0.12), Vector3(0.05, 0.05, 0.05))

# ==================== 沙虫/爬虫 ====================

static func _worm(st: SurfaceTool, glow: SurfaceTool) -> void:
	var n: int = 5
	for i: int in range(n):
		var t: float = float(i) / float(n - 1)
		var r: float = lerpf(0.34, 0.16, t)
		var zz: float = lerpf(0.52, -0.62, t)
		var yy: float = lerpf(0.30, 0.20, t) + 0.04 * sin(t * PI)
		_put(st, _sph(), Vector3(0.0, yy, zz), Vector3(r, r * 0.86, r * 1.15))
		# 环节背刺
		_put(st, _cone(), Vector3(0.0, yy + r * 0.82, zz), Vector3(r * 0.22, r * 0.62, r * 0.22))
		# 节间环
		if i < n - 1:
			_put(st, _cyl(), Vector3(0.0, yy, zz - r * 0.95), Vector3(r * 0.92, r * 0.22, r * 0.92))
	# 头部
	_put(st, _sph(), Vector3(0.0, 0.34, 0.72), Vector3(0.30, 0.26, 0.32))
	for i: int in range(2):
		var sx: float = -1.0 if i == 0 else 1.0
		_put(glow, _sph(), Vector3(sx * 0.15, 0.42, 0.92), Vector3(0.055, 0.055, 0.055))
		_put(st, _cone(), Vector3(sx * 0.18, 0.30, 1.02), Vector3(0.05, 0.22, 0.05), 0.0, PI * 0.5)

# ==================== 漂浮灵体 ====================

static func _spirit(st: SurfaceTool, glow: SurfaceTool, s: float) -> void:
	# 石质底座（一小截石台，贴合地图石雕风）
	_put(st, _cyl(), Vector3(0.0, 0.10 * s, 0.0), Vector3(0.52 * s, 0.20 * s, 0.52 * s))
	_put(st, _cyl(), Vector3(0.0, 0.26 * s, 0.0), Vector3(0.36 * s, 0.14 * s, 0.36 * s))
	# 主体灵核（发光八面体感：两个锥体拼合）
	_put(glow, _cone(), Vector3(0.0, 1.28 * s, 0.0), Vector3(0.30 * s, 0.56 * s, 0.30 * s), 0.0, 0.0)
	_put(glow, _cone(), Vector3(0.0, 0.72 * s, 0.0), Vector3(0.30 * s, 0.56 * s, 0.30 * s), 0.0, PI)
	# 环绕晶屑
	for i: int in range(3):
		var a: float = TAU * float(i) / 3.0
		_put(glow, _cone(), Vector3(cos(a) * 0.52 * s, 1.10 * s + 0.10 * s * float(i), sin(a) * 0.52 * s),
			Vector3(0.07 * s, 0.24 * s, 0.07 * s), a, 0.6)
	# 石环
	_put(st, _torus(), Vector3(0.0, 0.50 * s, 0.0), Vector3(0.62 * s, 0.62 * s, 0.62 * s))
	# 悬浮碎石
	for i: int in range(4):
		var a2: float = TAU * float(i) / 4.0 + 0.5
		_put(st, _sph(), Vector3(cos(a2) * 0.34 * s, 0.62 * s, sin(a2) * 0.34 * s), Vector3(0.09 * s, 0.07 * s, 0.09 * s))

# ==================== 史诗巨龙 ====================

static func _dragon(st: SurfaceTool, glow: SurfaceTool) -> void:
	var hy: float = 2.05
	var bl: float = 3.30
	var bw: float = 1.55
	var bh: float = 1.30
	# 躯干
	_put(st, _sph(), Vector3(0.0, hy, 0.0), Vector3(bw, bh, bl) * 0.5)
	# 背脊
	for i: int in range(6):
		var t: float = float(i) / 5.0
		var zz: float = lerpf(-bl * 0.40, bl * 0.34, t)
		var ss: float = 0.42 + 0.30 * sin(t * PI)
		_put(st, _cone(), Vector3(0.0, hy + bh * 0.48, zz), Vector3(bw * 0.10, bh * ss, bw * 0.10))
	# 颈（三节上扬）
	var neck_pts: Array = [Vector3(0.0, hy + 0.34, bl * 0.42), Vector3(0.0, hy + 0.98, bl * 0.62), Vector3(0.0, hy + 1.62, bl * 0.78)]
	var neck_r: Array = [0.46, 0.36, 0.28]
	for i: int in range(3):
		var pv: Vector3 = neck_pts[i]
		var rr: float = float(neck_r[i])
		_put(st, _sph(), pv, Vector3(rr, rr, rr * 1.12))
	# 头
	_put(st, _sph(), Vector3(0.0, hy + 1.96, bl * 0.94), Vector3(0.46, 0.38, 0.62))
	_put(st, _cone(), Vector3(0.0, hy + 1.86, bl * 1.18), Vector3(0.26, 0.46, 0.24), 0.0, PI * 0.5)
	# 双角
	for i: int in range(2):
		var sx: float = -1.0 if i == 0 else 1.0
		_put(st, _cone(), Vector3(sx * 0.30, hy + 2.24, bl * 0.86), Vector3(0.11, 1.00, 0.11), sx * 0.22, -0.55)
	# 双翼（肩部后掠翼板 + 翼膜）
	for i: int in range(2):
		var sx2: float = -1.0 if i == 0 else 1.0
		_put(st, _box(), Vector3(sx2 * 1.05, hy + 0.62, bl * 0.16), Vector3(1.85, 0.10, 0.72), sx2 * 0.30, 0.0, sx2 * 0.30)
		_put(st, _box(), Vector3(sx2 * 1.95, hy + 0.42, bl * 0.02), Vector3(1.35, 0.07, 0.52), sx2 * 0.60, 0.0, sx2 * 0.20)
		_put(st, _box(), Vector3(sx2 * 2.55, hy + 0.28, -bl * 0.10), Vector3(0.55, 0.06, 0.30), sx2 * 0.85, 0.0, sx2 * 0.12)
	# 四腿
	for i: int in range(4):
		var sx3: float = -1.0 if (i % 2 == 0) else 1.0
		var sz3: float = -0.80 if i < 2 else 0.72
		_put(st, _cap(), Vector3(sx3 * bw * 0.42, 0.85, sz3), Vector3(bw * 0.26, 1.70, bw * 0.26))
		_put(st, _sph(), Vector3(sx3 * bw * 0.44, 0.14, sz3 + 0.10), Vector3(bw * 0.20, 0.13, bw * 0.26))
	# 尾（四节，末端带刃）
	for i: int in range(4):
		var t2: float = float(i) / 3.0
		var tr: float = lerpf(0.34, 0.09, t2)
		_put(st, _sph(), Vector3(0.0, hy - 0.08 - 0.16 * t2, -bl * (0.52 + 0.52 * t2)), Vector3(tr, tr * 0.92, tr * 1.5))
	_put(st, _cone(), Vector3(0.0, hy - 0.62, -bl * 1.28), Vector3(0.16, 0.52, 0.10), 0.0, -PI * 0.5)
	# 发光眼 + 胸口核心
	for i: int in range(2):
		var sx4: float = -1.0 if i == 0 else 1.0
		_put(glow, _sph(), Vector3(sx4 * 0.22, hy + 2.06, bl * 1.02), Vector3(0.085, 0.085, 0.085))
	_put(glow, _sph(), Vector3(0.0, hy + 0.26, bl * 0.30), Vector3(0.24, 0.24, 0.16))

# ==================== 网格工具 ====================

static var _m_sph: SphereMesh
static var _m_cap: CapsuleMesh
static var _m_cone: CylinderMesh
static var _m_box: BoxMesh
static var _m_cyl: CylinderMesh
static var _m_tor: TorusMesh

static func _sph() -> SphereMesh:
	if _m_sph == null:
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 10
		m.rings = 5
		_m_sph = m
	return _m_sph

static func _cap() -> CapsuleMesh:
	if _m_cap == null:
		var m := CapsuleMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.radial_segments = 8
		m.rings = 2
		_m_cap = m
	return _m_cap

static func _cone() -> CylinderMesh:
	if _m_cone == null:
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 8
		m.rings = 1
		_m_cone = m
	return _m_cone

static func _box() -> BoxMesh:
	if _m_box == null:
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		_m_box = m
	return _m_box

static func _cyl() -> CylinderMesh:
	if _m_cyl == null:
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 10
		_m_cyl = m
	return _m_cyl

static func _torus() -> TorusMesh:
	if _m_tor == null:
		var m := TorusMesh.new()
		m.inner_radius = 0.7
		m.outer_radius = 1.0
		m.rings = 16
		m.ring_segments = 6
		_m_tor = m
	return _m_tor

## 基础网格都是半径0.5/高度1（即单位立方体包络），用 scale 直接给最终尺寸
static func _put(st: SurfaceTool, mesh: Mesh, pos: Vector3, scl: Vector3 = Vector3.ONE,
		yaw: float = 0.0, pitch: float = 0.0, roll: float = 0.0) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	b = b.scaled(scl)
	st.append_from(mesh, 0, Transform3D(b, pos))

const _HIDE_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

uniform vec3 body_color : source_color = vec3(0.42, 0.36, 0.30);
uniform vec3 belly_color : source_color = vec3(0.58, 0.50, 0.42);
uniform vec3 dark_color : source_color = vec3(0.20, 0.17, 0.14);

varying vec3 lp;

float hash31(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.13, 0.37));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash31(i + vec3(0, 0, 0)), hash31(i + vec3(1, 0, 0)), f.x),
	               mix(hash31(i + vec3(0, 1, 0)), hash31(i + vec3(1, 1, 0)), f.x), f.y),
	           mix(mix(hash31(i + vec3(0, 0, 1)), hash31(i + vec3(1, 0, 1)), f.x),
	               mix(hash31(i + vec3(0, 1, 1)), hash31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	// 腹部浅、背部深
	vec3 c = mix(dark_color, body_color, smoothstep(-0.55, 0.10, lp.y));
	c = mix(c, belly_color, smoothstep(0.10, -0.45, lp.y) * 0.75);
	// 皮毛/鳞片斑驳
	float n = vnoise(lp * 7.0) * 0.6 + vnoise(lp * 21.0) * 0.4;
	c *= 0.82 + 0.36 * n;
	// 背脊暗纹
	float stripe = smoothstep(0.52, 0.78, vnoise(vec3(lp.x * 3.5, lp.y * 9.0, lp.z * 3.5)));
	c = mix(c, c * 0.66, stripe * 0.55);
	// 落脚处带一点泥色
	float mud = smoothstep(0.28, 0.0, lp.y);
	c = mix(c, c * vec3(0.78, 0.72, 0.62), mud * 0.7);
	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.22;
}
"""
