class_name NetModels
extends RefCounted
const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")
const HeroYingrui = preload("res://scripts/core/HeroYingrui.gd")
# 联机客户端只读模型库：镜像 host 各实体脚本里的 glb 路径与缩放规则。
# 仅用于视觉呈现，不含任何逻辑；host 快照发来的名字在模型映射查不到时返回 null，
# 由调用方退回基础几何体（见 NetClientBattle._make_view 的 fallback）。

const HERO_MODEL_MAP = {
	# ---- 女英雄 ----
	"甄姬":     "res://model/hero/character-female-a.glb",
	"安琪拉":   "res://model/hero/character-female-b.glb",
	"妲己":     "res://model/hero/character-female-c.glb",
	"不知火舞": "res://model/hero/character-female-d.glb",
	"孙尚香":   "res://model/hero/character-female-e.glb",
	"沈梦溪":   "res://model/hero/character-female-f.glb",
	"小乔":     "res://model/hero/character-female-a.glb",
	"王昭君":   "res://model/hero/character-female-a.glb",
	# ---- 男英雄 ----
	"吕布":     "res://model/hero/character-male-a.glb",
	"亚瑟":     "res://model/hero/character-male-b.glb",
	"铠":       "res://model/hero/character-male-c.glb",
	"李白":     "res://model/hero/character-male-d.glb",
	"兰陵王":   "res://model/hero/character-male-e.glb",
	"张飞":     "res://model/hero/character-male-f.glb",
	# ---- 特殊英雄（复用底座 + 配件）----
	"东皇太一": "res://model/hero/character-male-a.glb",
	"马超":     "res://model/hero/character-male-b.glb",
	"狄仁杰":   "res://model/hero/character-male-c.glb",
	"马可波罗": "res://model/hero/character-male-d.glb",
	"太乙真人": "res://model/hero/character-male-f.glb",
	"鲁班七号": "res://model/hero/character-male-a.glb",
	"夏侯惇":   "res://model/hero/character-male-a.glb",
	"后羿":     "res://model/hero/character-male-a.glb",
	"大禹":     "res://model/hero/character-male-a.glb",
	"孙悟空":   "res://model/hero/character-male-a.glb",
	"刘禅":     "res://model/hero/character-male-b.glb",
	"英睿":     "res://model/hero/character-male-d.glb",   # 与主机 Hero.HERO_MODEL_MAP 对齐（底座男战士 + 签名道具）
}

const MINION_MODEL_MAP = {
	"melee":  "res://model/melee/soldier.glb",
	"ranged": "res://model/range/archer.glb",
	"siege":  "res://model/seige/cannon-mobile.glb",
	"super":  "res://model/super/character-orc.glb",
	"dragon": "res://model/dragon/DragonBaby.glb",
	"storm":  "res://model/dragon/DragonBaby.glb",
	"shadow_dragon": "res://model/dragon/DragonBaby.glb",
}

const JUNGLE_MODEL_MAP = {
	"red_buff":       "res://model/monster/animal-tiger.glb",
	"blue_buff":      "res://model/monster/animal-polar.glb",
	"bird":           "res://model/monster/animal-parrot.glb",
	"wolf":           "res://model/monster/animal-fox.glb",
	"lizard":         "res://model/monster/animal-crab.glb",
	"lizard_big":     "res://model/monster/animal-crab.glb",
	"pig":            "res://model/monster/animal-pig.glb",
	"pig_small":      "res://model/monster/animal-pig.glb",
	"worm":           "res://model/monster/animal-caterpillar.glb",
	"monkey":         "res://model/monster/animal-monkey.glb",
	"spatial_spirit": "res://model/monster/animal-koala.glb",
	"river_spirit":   "res://model/monster/animal-fish.glb",
	"tyrant":         "res://model/dragon/DragonBaby.glb",
	"dragon":         "res://model/dragon/DragonBaby.glb",
	"shadow_tyrant":  "res://model/dragon/DragonBaby.glb",
	"shadow_dragon":  "res://model/dragon/DragonBaby.glb",
	"storm_dragon":   "res://model/dragon/DragonBaby.glb",
}

const TURRET_GLB := "res://model/turret/Turret.glb"
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
const MonsterMesh = preload("res://scripts/entities/MonsterMesh.gd")
const TurretMesh = preload("res://scripts/entities/TurretMesh.gd")
static var _viz_seed: int = 17
const WALL_GLB := "res://model/wall/wall.glb"
const BUSH_GLB := "res://model/grass/grass-large.glb"

# 模型实例缩放必须与 host 对应脚本一致（Hero ×2.0 等）。
const HERO_SCALE := 2.0
const EPIC_JUNGLE := ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]

static func is_epic_jungle(n: String) -> bool:
	return n in EPIC_JUNGLE

static var _scene_cache: Dictionary = {}

static func _scene(path: String):
	if _scene_cache.has(path):
		return _scene_cache[path]
	var packed = load(path)
	_scene_cache[path] = packed
	return packed


static func _spawn(path: String, scale: Vector3) -> Node3D:
	var packed = _scene(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	inst.scale = scale
	return inst


static func hero(name: String) -> Node3D:
	var path: String = HERO_MODEL_MAP.get(name, "")
	if path == "":
		return null
	var inst = _spawn(path, Vector3.ONE * HERO_SCALE)
	# 与主机同源：英雄专属武器
	HeroWeapons.attach(inst, name, float(HeroWeapons.HERO_REACH.get(name, -1.0)))
	# 英睿签名道具：父节点是已放大 HERO_SCALE 的模型，道具容器按 1/HERO_SCALE 换算回米制
	if name == "英睿":
		HeroYingrui.attach_props(inst, 1.0 / HERO_SCALE)
	# 轮椅英雄：与主机同源合成（角色本体坐姿 + 座椅道具），不再只显示一把椅子
	if HeroWeapons.is_wheelchair_hero(name):
		var root := Node3D.new()
		root.name = name
		root.add_child(inst)
		HeroWeapons.mount_wheelchair(root, inst, name, HERO_SCALE)
		return root
	return inst


# 兵线体型归一化（主机 Minion.gd 与本文件共用同一套目标高度）：
# 近战/远程/攻城车统一约 1.30m 高；超级兵/主宰先锋/暗影先锋 = 其他兵种的 1.5 倍（1.95m）。
const MINION_RAW_H := {
	"melee": 0.84, "ranged": 0.82, "super": 0.78,
	"siege": 1.38, "dragon": 2.86, "storm": 2.86, "shadow_dragon": 2.86,
}
const MINION_TARGET_H := 1.30
const MINION_BIG := ["super", "dragon", "storm", "shadow_dragon"]
const MINION_BIG_MUL := 1.5
const MINION_VISUAL_SCALE := 2.0   # 与 MinionModel.VISUAL_SCALE 同步：模型放大2倍

# 按「目标高度 / 模型原始高度」反算缩放，保证各兵种视觉高度一致
static func minion_scale(sub_type: String) -> float:
	var raw: float = float(MINION_RAW_H.get(sub_type, 0.84))
	var target := MINION_TARGET_H * (MINION_BIG_MUL if sub_type in MINION_BIG else 1.0)
	return target / maxf(raw, 0.01) * MINION_VISUAL_SCALE


static func minion(sub_type: String, team: int = 0) -> Node3D:
	# 已接入的程序化兵种与主机同源；龙形先锋暂走旧 GLB
	if MinionModel.is_applied(sub_type):
		return MinionModel.build(sub_type, team)
	var path: String = MINION_MODEL_MAP.get(sub_type, "")
	if path == "":
		return null
	return _spawn(path, Vector3.ONE * minion_scale(sub_type))


static func jungle(type_name: String) -> Node3D:
	# 与主机同源：程序化野怪模型（体型由 builder 内部按类型给定）
	return MonsterMesh.visual(type_name)


static func turret(tier: String, team: int = 0) -> Node3D:
	# 与主机一致：程序化石塔模型（同一套构建函数），队伍色由 builder 内部处理
	return TurretMesh.visual(tier, team)


static func tower_shield(team: int, crystal: bool = false) -> Node3D:
	return TurretMesh.tower_shield_visual(team, crystal)


static func wall(hq: bool = false, outer: bool = false, outer_len: float = 2.0) -> Node3D:
	# 与主机 Wall.gd 完全同源：程序化石墙（不再加载 wall.glb）
	_viz_seed += 37
	if outer:
		return DecorMesh.outer_wall_visual(outer_len)
	return DecorMesh.wall_visual_hq(_viz_seed) if hq else DecorMesh.wall_visual(_viz_seed)


static func bush() -> Node3D:
	# 与主机 Bush.gd 完全同源：程序化灌木（不再加载 grass-large.glb）
	_viz_seed += 91
	return DecorMesh.bush_visual(_viz_seed)


# 子弹模型映射（与 host Bullet.gd _ready 同源：kind 0→弹石，1→弹丸，2→弓箭，3→炮弹，4→后羿R 自组）
static func bullet(kind: int) -> Node3D:
	const PATHS := {
		0: "res://model/dragon/bullet/weapon-ammo-boulder.glb",
		1: "res://model/turret/bullet/weapon-ammo-bullet.glb",
		2: "res://model/range/weapon-arrow.glb",
		3: "res://model/seige/cannon-ball.glb",
	}
	if not PATHS.has(kind):
		return null
	var path = PATHS[kind]
	# 英雄/塔普攻子弹（kind 0/1）放大 3 倍（同 host Bullet.gd 规则）
	var sc := 3.0 if kind <= 1 else 1.0
	return _spawn(path, Vector3.ONE * sc)
