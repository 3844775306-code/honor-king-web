class_name BulletVisual
extends RefCounted
## 弹体统一视觉：三层程序化能量弹（核心 + 光晕 + 拖尾），不依赖 GLB 模型。
## host：Bullet.gd 直接 build()；client：vkind 解码后 build_from_vkind()，两端同一份构建逻辑保证形状一致。
## 覆盖：普攻弹（skill_id==0）、防御塔/小兵弹道、以及除后羿R 外的全部英雄技能弹。

const SHAPE_ORB := 1        # 法球（默认）
const SHAPE_ARROW := 2      # 箭矢：后羿 / 远程小兵
const SHAPE_PELLET := 3     # 弹丸：马可波罗
const SHAPE_SHELL := 4      # 炮弹：孙尚香 / 沈梦溪 / 攻城兵
const SHAPE_CARD := 5       # 令牌：狄仁杰
const SHAPE_WATER := 6      # 水珠：甄姬
const SHAPE_BLADE := 7      # 刃光：吕布
const SHAPE_TOWER := 8      # 防御塔能量球
const SHAPE_SIEGE := 9      # 攻城炮弹（带外环）
const SHAPE_FAN := 10       # 回旋扇面：小乔
const SHAPE_FLAME := 11     # 火焰弹：安琪拉 / 妲己 / 不知火舞
const SHAPE_SPEAR := 12     # 枪芒：马超
const SHAPE_BOLT := 13      # 实体箭矢：弓兵普攻（木杆+钢镞+队伍色箭羽）。raw 13 落在技能码位 20 之前，不占技能段

const PALETTE_ALLY := 10
const PALETTE_ENEMY := 11
const PALETTE_ALLY_SMALL := 12    # 远程小兵（0.8 尺寸）
const PALETTE_ENEMY_SMALL := 13
const PALETTE_ALLY_SIEGE := 14    # 攻城兵（0.95 尺寸）
const PALETTE_ENEMY_SIEGE := 15
# 狄仁杰令牌专用调色板：只在 SHAPE_CARD 上解释，不影响小兵/塔的阵营色。
const PALETTE_CARD_RED := 10
const PALETTE_CARD_BLUE := 11
const PALETTE_CARD_GOLD := 12
const PALETTE_CARD_WHITE := 13

## vkind = VKIND_BASE + raw*VKIND_SHAPE_MUL + palette，palette 恒在低 4 位（0-15）不冲突。
## raw 取值范围 1..55 → vkind ≤ 995（客户端 NetClientBattle 仅认 vkind < 1000 的定制档）。
##   · 普攻/塔/兵（skill_id==0）：raw = shape（1..12），与旧编码完全一致；
##   · 技能弹（skill_id 1/2/3 = Q/W/R，即 slot 0/1/2）：
##       raw = SKILL_SHAPE_OFFSET + slot*SKILL_SLOT_STRIDE + (shape-1)  ∈ [20, 55]
##     即 slot0 = 20..31、slot1 = 32..43、slot2 = 44..55；解出 shape = raw%12+1。
const VKIND_BASE := 100
const VKIND_SHAPE_MUL := 16
const VKIND_MAX := 1000          # 客制档上限（NetClientBattle 只处理 vkind < 1000）
const SHAPE_COUNT := 12          # SHAPE_* 常量个数（1..12），技能码位步长依赖此值
const SKILL_SHAPE_OFFSET := 20   # 技能弹 raw 起点
const SKILL_SLOT_STRIDE := 12    # 每个技能槽位占用的 raw 码位数（= SHAPE_COUNT）
const SKILL_SLOT_COUNT := 3      # Q/W/R 三槽
const SKILL_SIZE := 1.45         # 技能弹基础放大（原值）
const SKILL_ULT_SIZE := 1.25     # 大招（slot2）在 1.45 基础上再放大

## 同英雄 Q/W/R 三槽形状族（按基础形状分族；三槽形状互不相同，slot2 大招最大）。
const SKILL_SHAPES := {
	SHAPE_ORB: [SHAPE_ORB, SHAPE_PELLET, SHAPE_SHELL],
	SHAPE_ARROW: [SHAPE_ARROW, SHAPE_PELLET, SHAPE_SHELL],
	SHAPE_PELLET: [SHAPE_PELLET, SHAPE_ORB, SHAPE_SHELL],
	SHAPE_SHELL: [SHAPE_SHELL, SHAPE_PELLET, SHAPE_ORB],
	SHAPE_CARD: [SHAPE_CARD, SHAPE_ORB, SHAPE_SHELL],
	SHAPE_WATER: [SHAPE_WATER, SHAPE_SPEAR, SHAPE_ORB],
	SHAPE_BLADE: [SHAPE_BLADE, SHAPE_SPEAR, SHAPE_FAN],
	SHAPE_FAN: [SHAPE_FAN, SHAPE_ORB, SHAPE_SPEAR],
	SHAPE_FLAME: [SHAPE_FLAME, SHAPE_ORB, SHAPE_SHELL],
	SHAPE_SPEAR: [SHAPE_SPEAR, SHAPE_ARROW, SHAPE_SHELL],
}

const ELEMENT_ORDER := ["fire", "ice", "water", "lightning", "shadow", "holy", "blade", "wind", "earth", "arcane"]

const HERO_SHAPE := {
	"后羿": SHAPE_ARROW, "狄仁杰": SHAPE_CARD, "马可波罗": SHAPE_PELLET,
	"孙尚香": SHAPE_SHELL, "沈梦溪": SHAPE_SHELL, "甄姬": SHAPE_WATER,
	"东皇太一": SHAPE_ORB, "吕布": SHAPE_BLADE, "小乔": SHAPE_FAN,
	"安琪拉": SHAPE_FLAME, "妲己": SHAPE_FLAME, "不知火舞": SHAPE_FLAME,
	"马超": SHAPE_SPEAR, "铠": SHAPE_BLADE, "夏侯惇": SHAPE_BLADE, "兰陵王": SHAPE_BLADE,
	"鲁班七号": SHAPE_SHELL,
}

const HeroProjectilesScript = preload("res://scripts/presentation/HeroProjectiles.gd")
static var _mat_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}


## 该弹体是否走统一程序化视觉；返回 vkind（0 = 保持旧视觉）。
## 技能弹除「后羿R 太阳箭」外，全部按英雄形状表走统一视觉（安琪拉火球 / 小乔扇面等）。
static func vkind_for(bl) -> int:
	if bl == null:
		return 0
	if bool(bl.is_houyi_ult):
		return 0
	var src = bl.source
	if src == null or not is_instance_valid(src):
		return 0
	if not (src is Hero or src is Minion or src is Turret):
		return 0
	if src is Hero and int(bl.skill_id) == 0 and float(src.attack_range) <= 400.0:
		return 0                        # 近战英雄普攻不出弹
	if src is Hero:
		var hvk: int = HeroProjectilesScript.vkind_for(str(src.display_name), int(bl.team), int(bl.skill_id))
		if hvk > 0:
			return hvk
	return int(spec_for(bl).get("vk", 0))


## 由弹体推导视觉规格：形状 / 调色板 / 双色 / 尺寸 / 拖尾参数。
static func spec_for(bl) -> Dictionary:
	var src = bl.source
	var shape := SHAPE_ORB
	var palette := PALETTE_ALLY if int(bl.team) == 0 else PALETTE_ENEMY
	var is_skill := int(bl.skill_id) != 0
	if src is Turret:
		shape = SHAPE_TOWER
	elif src is Minion:
		var enemy := int(bl.team) != 0
		if str(src.display_name) == "ranged":
			shape = SHAPE_BOLT        # 弓兵：实体箭矢（木杆+铁镞+队伍色箭羽），不再是发光假箭
			palette = PALETTE_ENEMY_SMALL if enemy else PALETTE_ALLY_SMALL
		elif str(src.display_name) == "siege":
			shape = SHAPE_BOLT        # 攻城车：放大版实体弩箭（1.35 档 ≈1.7m，与车上那支同尺寸）
			palette = PALETTE_ENEMY_SIEGE if enemy else PALETTE_ALLY_SIEGE
	elif src is Hero:
		shape = int(HERO_SHAPE.get(str(src.display_name), SHAPE_ORB))
		var idx := ELEMENT_ORDER.find(str(Vfx.element_of(str(src.display_name))))
		palette = idx if idx >= 0 else 0

	var diren: bool = src is Hero and str(src.display_name) == "狄仁杰"
	var diren_enhanced: bool = diren and int(bl.skill_id) == 0 \
		and (bl.linear_dir.length() > 0.01 or bool(bl.pierce))
	# 狄仁杰：普攻/强化普攻/1/2技能都是令牌，大招是黄牌；颜色写进 palette，
	# 客户端 decode_vkind 后由 SHAPE_CARD 专用色表还原同一套红蓝/黄牌。
	if diren:
		shape = SHAPE_CARD
		if int(bl.skill_id) == 3:
			palette = PALETTE_CARD_GOLD
		elif int(bl.skill_id) in [1, 2] or diren_enhanced:
			palette = PALETTE_CARD_RED if (int(src.stat2) + int(bl.skill_id)) % 2 == 0 else PALETTE_CARD_BLUE
		else:
			palette = PALETTE_CARD_WHITE

	var cols := card_colors_for(palette) if diren else colors_for(palette)
	var size_mult := _size_for_palette(palette)
	var raw_shape := shape
	var slot := -1
	var trail := _trail_params(shape)
	if is_skill:
		# skill_id 1/2/3 即 Q/W/R（SkillDataBase.create_bullet 传参 1-based），映射到 slot 0/1/2。
		slot = clampi(int(bl.skill_id) - 1, 0, SKILL_SLOT_COUNT - 1)
		# 狄仁杰三技能都保持令牌形状；其余英雄仍按英雄形状族换 Q/W/R 造型。
		if not diren:
			shape = _skill_shape(shape, slot)
		trail = _trail_params(shape)
		size_mult *= SKILL_SIZE * (SKILL_ULT_SIZE if slot >= 2 else 1.0)
		if slot >= 2:
			trail = [float(trail[0]) * 2.0, float(trail[1]) * 2.1]   # 大招：拖尾明显更长
		else:
			trail = [float(trail[0]) * 1.5, float(trail[1]) * 1.4]
		raw_shape = SKILL_SHAPE_OFFSET + slot * SKILL_SLOT_STRIDE + (shape - 1)
	return {
		"vk": VKIND_BASE + raw_shape * VKIND_SHAPE_MUL + palette,
		"shape": shape,
		"palette": palette,
		"slot": slot,
		"c1": cols[0],
		"c2": cols[1],
		"size_mult": size_mult,
		"trail_size": trail[0],
		"trail_life": trail[1],
	}


## 基础形状 → 该英雄技能槽（0/1/2）对应的形状（三槽互不相同，见 SKILL_SHAPES）。
static func _skill_shape(base_shape: int, slot: int) -> int:
	var triple: Array = SKILL_SHAPES.get(base_shape, SKILL_SHAPES[SHAPE_ORB])
	return int(triple[clampi(slot, 0, SKILL_SLOT_COUNT - 1)])


## 调色板 → [主色, 亮色]。0-9 = 元素，10-15 = 阵营色（10/12/14 友方，11/13/15 敌方）。
static func colors_for(palette: int) -> Array:
	if palette == PALETTE_ALLY or palette == PALETTE_ALLY_SMALL or palette == PALETTE_ALLY_SIEGE:
		return [Color(0.32, 0.82, 1.0), Color(0.85, 0.98, 1.0)]
	if palette == PALETTE_ENEMY or palette == PALETTE_ENEMY_SMALL or palette == PALETTE_ENEMY_SIEGE:
		return [Color(1.0, 0.42, 0.24), Color(1.0, 0.85, 0.55)]
	var key: String = ELEMENT_ORDER[clampi(palette, 0, ELEMENT_ORDER.size() - 1)]
	var d: Dictionary = Vfx.ELEMENTS.get(key, Vfx.ELEMENTS["arcane"])
	return [d["c"], d["c2"]]


## 令牌专用色：红/蓝/黄/白四档（只在 SHAPE_CARD 上使用，不污染小兵阵营色）。
static func card_colors_for(palette: int) -> Array:
	match palette:
		PALETTE_CARD_RED:
			return [Color(1.0, 0.22, 0.18), Color(0.24, 0.52, 1.0)]
		PALETTE_CARD_BLUE:
			return [Color(0.20, 0.52, 1.0), Color(1.0, 0.28, 0.22)]
		PALETTE_CARD_GOLD:
			return [Color(1.0, 0.78, 0.16), Color(1.0, 0.96, 0.62)]
		_:
			return [Color(0.72, 0.90, 1.0), Color(1.0, 0.98, 0.90)]


## 调色板自带尺寸档（小兵/攻城兵比英雄弹小，双端一致）。
static func _size_for_palette(palette: int) -> float:
	if palette == PALETTE_ALLY_SMALL or palette == PALETTE_ENEMY_SMALL:
		return 1.0   # 远程兵：小兵模型是 2 倍放大（~2.6m 高），箭矢按 1.0 才和手里的箭同尺寸
	if palette == PALETTE_ALLY_SIEGE or palette == PALETTE_ENEMY_SIEGE:
		return 1.5    # 攻城车：弩炮巨型箭，1.5×1.28m ≈ 1.92m，与车上那支（0.96×模型缩放2.0）等长
	return 1.0


## 客户端：按 vkind 解码形状/尺寸/槽位（与 spec_for 对称，普攻/技能同一套公式）。
static func decode_vkind(vk: int) -> Dictionary:
	var t := vk - VKIND_BASE
	var raw_shape: int = t / VKIND_SHAPE_MUL
	var palette: int = t % VKIND_SHAPE_MUL
	var shape := raw_shape
	var slot := -1
	var size := _size_for_palette(palette)
	if raw_shape >= SKILL_SHAPE_OFFSET:
		var code := raw_shape - SKILL_SHAPE_OFFSET
		slot = clampi(code / SKILL_SLOT_STRIDE, 0, SKILL_SLOT_COUNT - 1)
		shape = code % SKILL_SLOT_STRIDE + 1
		size *= SKILL_SIZE * (SKILL_ULT_SIZE if slot >= 2 else 1.0)
	return {
		"shape": shape,
		"palette": palette,
		"slot": slot,
		"is_skill": slot >= 0,
		"size": size,
	}


## 客户端：按 vkind 还原同一形状与尺寸（宿主/客户端同源构建器）。
static func build_from_vkind(vk: int) -> Node3D:
	var d := decode_vkind(vk)
	var shape := int(d["shape"])
	var palette := int(d["palette"])
	var cols := card_colors_for(palette) if shape == SHAPE_CARD else colors_for(palette)
	return build(shape, cols[0], cols[1], float(d["size"]))


## 构建弹体视觉根节点（所有形状沿 +Z 朝向，宿主/客户端都用 rotation.y 追向速度）。
static func build(shape: int, c1: Color, c2: Color, size_mult: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "BulletVisual"
	match shape:
		SHAPE_ARROW:
			_add(root, _sphere(), _glow(c1, 0.42), Vector3(0.34, 0.34, 1.0))
			_add(root, _sphere(), _core(c2), Vector3(0.14, 0.14, 0.6))
		SHAPE_PELLET:
			_add(root, _sphere(), _glow(c1, 0.45), Vector3(0.55, 0.55, 0.95))
			_add(root, _sphere(), _core(c2), Vector3(0.2, 0.2, 0.4))
		SHAPE_SHELL:
			_add(root, _sphere(), _glow(c1, 0.3), Vector3(0.9, 0.9, 0.9))
			_add(root, _sphere(), _core(c2), Vector3(0.42, 0.42, 0.5))
			_add(root, _torus(), _glow(c1, 0.55), Vector3(0.85, 0.85, 0.85), Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))
		SHAPE_CARD:
			# 令牌：红/蓝（或金黄）两张并排薄牌 + 中央亮点，飞行时朝向速度方向。
			_add(root, _quad(), _glow_billboard(c1, 0.9), Vector3(0.46, 0.72, 1.0), Vector3(-0.18, 0.0, 0.0))
			_add(root, _quad(), _glow_billboard(c2, 0.82), Vector3(0.46, 0.72, 1.0), Vector3(0.18, 0.0, 0.0))
			_add(root, _sphere(), _core(Color(1.0, 0.96, 0.82)), Vector3(0.1, 0.1, 0.1), Vector3(0.0, 0.0, 0.03))
		SHAPE_WATER:
			_add(root, _sphere(), _glow(c1, 0.32), Vector3(0.7, 0.8, 1.05))
			_add(root, _sphere(), _core(c2), Vector3(0.3, 0.4, 0.6))
		SHAPE_BLADE:
			_add(root, _quad(), _glow_billboard(c1, 0.9), Vector3(1.2, 0.22, 1.0))
			_add(root, _sphere(), _core(c2), Vector3(0.18, 0.18, 0.3))
		SHAPE_TOWER:
			_add(root, _sphere(), _glow(c1, 0.3), Vector3(0.95, 0.95, 0.95))
			_add(root, _sphere(), _core(c2), Vector3(0.44, 0.44, 0.44))
		SHAPE_SIEGE:
			_add(root, _sphere(), _glow(c1, 0.28), Vector3(1.0, 1.0, 1.0))
			_add(root, _sphere(), _core(c2), Vector3(0.5, 0.5, 0.5))
			_add(root, _torus(), _glow(c1, 0.4), Vector3(1.0, 1.0, 1.0), Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))
		SHAPE_FAN:
			# 回旋扇面：扇叶（扇形面）+ 加色描边 + 扇骨 + 轴心；整片绕竖轴自转
			var spin := Node3D.new()
			spin.name = "Spin"
			root.add_child(spin)
			_add(spin, _fan_mesh(), _fan_mat(c2), Vector3.ONE)
			_add(spin, _fan_mesh(), _glow(c1, 0.5), Vector3.ONE * 1.06)
			var rib_n := 2 if Vfx.quality <= 2 else 3
			for i in range(rib_n):
				var a := deg_to_rad(-42.0 + 42.0 * float(i))
				var p := Vector3(sin(a) * 0.46, 0.015, cos(a) * 0.46)
				_add(spin, _quad(), _glow(c2, 0.9), Vector3(0.045, 0.52, 1.0), p, Vector3(-PI * 0.5, a, 0.0))
			_add(spin, _sphere(), _core(c1), Vector3(0.19, 0.19, 0.19))
			root.set_meta("spin", 5.0)
		SHAPE_FLAME:
			# 火焰弹：亮核 + 外层火色光晕 + 舌状火苗（中低质量减少火苗层数）
			_add(root, _sphere(), _glow(c1, 0.42), Vector3(1.05, 1.05, 1.3))
			_add(root, _sphere(), _core(c2), Vector3(0.46, 0.46, 0.58))
			var flame_n := 1 if Vfx.quality <= 1 else (2 if Vfx.quality <= 2 else 3)
			for i in range(flame_n):
				_add(root, _quad(), _glow_billboard(c1, 0.55), Vector3(0.5, 0.85, 1.0),
					Vector3(0.0, 0.06, -0.22 - 0.1 * float(i)), Vector3(0.0, 0.0, randf() * TAU))
		SHAPE_SPEAR:
			# 枪芒：细长光柱 + 枪尖锥 + 亮核
			_add(root, _sphere(), _glow(c1, 0.55), Vector3(0.32, 0.32, 1.9))
			_add(root, _sphere(), _core(c2), Vector3(0.11, 0.11, 1.35))
			_add(root, _cone(), _core(c2), Vector3(0.26, 0.55, 0.26), Vector3(0.0, 0.0, 1.0), Vector3(PI * 0.5, 0.0, 0.0))
		SHAPE_BOLT:
			# 实体箭矢（弓兵普攻）：淡队伍色气流 + 木箭杆 + 钢箭镞 + 三片队伍色箭羽 + 深色箭尾
			# 全长 ~1.12m（与弓兵手里 1.26m 的箭同尺寸），+Z 为箭头方向
			_add(root, _sphere(), _glow(c1, 0.14), Vector3(0.10, 0.10, 1.25))
			_add(root, _shaft(), _mat_solid(Color(0.46, 0.31, 0.16), 0.05, 0.72),
				Vector3(1.0, 0.90, 1.0), Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))
			_add(root, _cone(), _mat_solid(Color(0.66, 0.70, 0.76), 0.80, 0.28, 0.12),
				Vector3(0.075, 0.22, 0.075), Vector3(0.0, 0.0, 0.56), Vector3(PI * 0.5, 0.0, 0.0))
			_add(root, _shaft(), _mat_solid(Color(0.10, 0.10, 0.12), 0.1, 0.6),
				Vector3(0.9, 0.05, 0.9), Vector3(0.0, 0.0, -0.44), Vector3(PI * 0.5, 0.0, 0.0))
			for i in range(3):
				var feather := Node3D.new()
				feather.rotation.z = TAU * float(i) / 3.0
				root.add_child(feather)
				_add(feather, _quad(), _fan_mat(c1), Vector3(0.06, 0.26, 1.0),
					Vector3(0.0, 0.0, -0.36), Vector3(0.0, PI * 0.5, 0.0))
		_:  # SHAPE_ORB
			_add(root, _sphere(), _glow(c1, 0.32), Vector3(0.95, 0.95, 0.95))
			_add(root, _sphere(), _core(c2), Vector3(0.34, 0.34, 0.34))
			_add(root, _torus(), _glow(c1, 0.55), Vector3(0.9, 0.9, 0.9), Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))
	root.scale = Vector3.ONE * size_mult
	return root


# ---------- 内部：共享网格 / 材质缓存（同屏多弹体共用资源，控制 draw call） ----------

static func _sphere() -> Mesh:
	if _mesh_cache.has("sphere"):
		return _mesh_cache["sphere"]
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 12
	m.rings = 6
	_mesh_cache["sphere"] = m
	return m


static func _torus() -> Mesh:
	if _mesh_cache.has("torus"):
		return _mesh_cache["torus"]
	var m := TorusMesh.new()
	m.inner_radius = 0.34
	m.outer_radius = 0.5
	m.rings = 16
	m.ring_segments = 8
	_mesh_cache["torus"] = m
	return m


static func _quad() -> Mesh:
	if _mesh_cache.has("quad"):
		return _mesh_cache["quad"]
	var m := QuadMesh.new()
	m.size = Vector2.ONE
	_mesh_cache["quad"] = m
	return m


## 扇面：扇形三角面（半角 65°，半径 1.0，平铺在 XZ 平面，绕原点展开）
static func _fan_mesh() -> Mesh:
	if _mesh_cache.has("fan"):
		return _mesh_cache["fan"]
	var seg := 14
	var half := deg_to_rad(65.0)
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for i in range(seg + 1):
		var a := -half + 2.0 * half * float(i) / float(seg)
		verts.append(Vector3(sin(a), 0.0, cos(a)))
	for i in range(seg):
		idx.append(0)
		idx.append(i + 1)
		idx.append(i + 2)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache["fan"] = m
	return m


static func _cone() -> Mesh:
	if _mesh_cache.has("cone"):
		return _mesh_cache["cone"]
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.5
	m.height = 1.0
	m.radial_segments = 8
	m.rings = 1
	_mesh_cache["cone"] = m
	return m


## 细圆柱（箭杆/箭尾）：半径 0.5、高 1.0，绕 X 旋转 90° 后可当沿 +Z 的杆件
static func _shaft() -> Mesh:
	if _mesh_cache.has("shaft"):
		return _mesh_cache["shaft"]
	var m := CylinderMesh.new()
	m.top_radius = 0.035
	m.bottom_radius = 0.035
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 1
	_mesh_cache["shaft"] = m
	return m


## 扇面材质：半透明自发光（双面，贴图无光照也能看清轮廓）
static func _fan_mat(c: Color) -> StandardMaterial3D:
	var key := "f" + c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(c.r, c.g, c.b, 0.88)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.8
	_mat_cache[key] = m
	return m


static func _glow(c: Color, alpha: float) -> StandardMaterial3D:
	var key := "g%s%.2f" % [c.to_html(), alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	_mat_cache[key] = m
	return m


static func _glow_billboard(c: Color, alpha: float) -> StandardMaterial3D:
	var key := "b%s%.2f" % [c.to_html(), alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := _glow(c, alpha).duplicate() as StandardMaterial3D
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_cache[key] = m
	return m


static func _core(c: Color) -> StandardMaterial3D:
	var key := "c" + c.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(minf(1.0, c.r + 0.15), minf(1.0, c.g + 0.15), minf(1.0, c.b + 0.15), 1.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.6
	m.disable_receive_shadows = true
	_mat_cache[key] = m
	return m


## 实体材质（箭杆/箭镞等需要受光的部件）：与自发光弹体区分，靠光照读出体积
static func _mat_solid(c: Color, metal: float, rough: float, emis: float = 0.0) -> StandardMaterial3D:
	var key := "s%s%.2f%.2f%.2f" % [c.to_html(), metal, rough, emis]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.disable_receive_shadows = true
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	_mat_cache[key] = m
	return m


static func _add(root: Node3D, mesh: Mesh, mat: Material, scl: Vector3,
		pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.scale = scl
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _trail_params(shape: int) -> Array:
	match shape:
		SHAPE_ARROW: return [0.16, 0.22]
		SHAPE_BOLT: return [0.12, 0.18]
		SHAPE_PELLET: return [0.13, 0.16]
		SHAPE_SHELL: return [0.26, 0.4]
		SHAPE_CARD: return [0.16, 0.24]
		SHAPE_WATER: return [0.2, 0.3]
		SHAPE_BLADE: return [0.18, 0.26]
		SHAPE_TOWER: return [0.18, 0.26]
		SHAPE_SIEGE: return [0.24, 0.34]
		SHAPE_FAN: return [0.3, 0.46]
		SHAPE_FLAME: return [0.28, 0.4]
		SHAPE_SPEAR: return [0.2, 0.3]
		_: return [0.2, 0.3]
