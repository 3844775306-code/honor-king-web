class_name Turret
extends GameEntity
const TurretMesh = preload("res://scripts/entities/TurretMesh.gd")
const DecorMesh = preload("res://scripts/entities/DecorMesh.gd")
# 攻击范围预览环
var range_preview: MeshInstance3D
var preview_material: ShaderMaterial
var range_ring_state: int = 2   # 0=红(正在打玩家) 1=绿(敌方兵线近) 2=黄(默认)；供联机快照广播给客户端复刻
var search_timer: float = 0.0
var consecutive_hits: int = 0          # 连续攻击同一目标次数
var last_target: GameEntity = null      # 上一个攻击目标
var tower_type: String = "outer"        # outer/inner/high
var _crystal_pivot: Node3D = null          # 塔顶晶核（自转/悬浮动画用）
var _crystal_t: float = 0.0
var _tower_shield_vis: Node3D = null      # 塔盾实物模型
var _tower_shield_t: float = 0.0
var _lock_beam: Node3D = null             # 锁定光束（芯+辉光+命中点）：一直连到当前目标，直到目标死亡
var _lock_send_t: float = 0.0           # 联机同步节拍
var _lock_net_on: bool = false
var interfere_timer: float = 0.0
var storm_interfere_done: bool = false   # 风暴先锋塔干扰：每座塔仅一次
var dying_visual: bool = false           # 倒塌动画中（快照仍广播，客户端据此复刻坍塌）
var interfere_max: float = 1.2   # 干扰总时长（用于血条上方的干扰条显示）
var tower_shield: float = 0.0
var tower_shield_active: bool = false
var shield_stage_75: bool = false
var shield_stage_50: bool = false
var shield_stage_25: bool = false
var shield_protected_no_minion: bool = false   # 塔下无敌方小兵：英雄对其伤害×0.45（供血条盾图标）
var under_attack_timer: float = 0.0   # 近 1.5s 内持续被攻击（供小地图警告圈检测，见 Minimap.gd）
const UNDER_ATTACK_WINDOW: float = 1.5
const HERO_AGGRO_WINDOW: float = 2.0   # 敌方英雄在塔内打我方英雄后的仇恨记忆
var _anchor := Vector3.ZERO          # 塔出生点：免疫击退/位移用，就地回正
var _anchor_set := false
var _body_vis: Node3D = null         # 受击闪光/轻抖只动塔身，不带范围环
var _body_vis_base := Vector3.ZERO
var _hit_tween: Tween = null
func _ready():
	_anchor = global_position
	_anchor_set = true
	_create_visual()
	_create_range_preview()
	add_to_group("terrains")

	add_to_group("turrets")
	body_radius =1.5
	collision_layer = 1
	collision_mask = 0
func _create_range_preview():
	# 贴地范围圈（柔化环带 + 磨损斑驳，随野区起伏贴地），不再是纯色 Torus 环
	var r: float = attack_range * 0.01 + body_radius
	range_preview = MeshFactory.create_ground_ring(r, Color(1.0, 0.9, 0.35, 0.5))
	range_preview.name = "RangeRing"
	range_preview.visible = false   # 只在玩家靠近（≤11m）时才显示
	preview_material = range_preview.material_override as ShaderMaterial
	add_child(range_preview)
func _update_range_preview():
	if not range_preview: return
	
	var player_hero = _get_player_hero()
	var enemy_minion_near = _has_enemy_minion_near()
	shield_protected_no_minion = not enemy_minion_near

	# 敌方防御塔的攻击范围圈：玩家本人进到 11 米内才出现（否则满屏圆环糊住战场）
	var near_player: bool = player_hero != null and player_hero.team != team \
		and global_position.distance_to(player_hero.global_position) <= 11.0
	range_preview.visible = near_player
	if not near_player:
		return

	if player_hero and self.current_target == player_hero:
		# 正在被玩家英雄攻击 → 红色
		MeshFactory.set_ground_ring_color(range_preview, Color(1.0, 0.28, 0.24, 0.55))
		range_ring_state = 0
	elif enemy_minion_near:
		# 有敌方兵线在附近 → 绿色
		MeshFactory.set_ground_ring_color(range_preview, Color(0.45, 1.0, 0.45, 0.5))
		range_ring_state = 1
	else:
		# 默认黄色
		MeshFactory.set_ground_ring_color(range_preview, Color(1.0, 0.9, 0.35, 0.45))
		range_ring_state = 2

func _get_player_hero() -> Hero:
	for entity in get_tree().get_nodes_in_group("heroes"):
		if entity is Hero and Config.is_ally(entity.team):
			return entity
	return null


func _create_visual():
	# 塔型缩放：外塔/二塔/高地统一为高地尺寸，仅水晶更大
	var f := 2.0
	match display_name:
		"crystal": f = 2.5
	# 程序化石塔模型（替代原 Turret.glb）：八角石身 + 队伍色发光刻纹，与石墙同一套材质
	var vis := TurretMesh.visual(str(display_name), team)
	add_child(vis)
	_body_vis = vis
	_body_vis_base = vis.position
	_crystal_pivot = vis.get_node_or_null("CrystalPivot") as Node3D
	# 塔外周青砖铺装已移到 BattleManager（塔被摧毁后砖要留下，不能挂在塔节点下）
	_add_base_blend(f)   # 石台 + 接地暗影：让塔"长"进地面，消除与地形的硬切边
	var col = CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	col.shape.radius = 0.8
	add_child(col)

# 底座融合层（所有塔共用同一份材质/着色器，只按塔型缩放）
static var _stone_a: StandardMaterial3D = null
static var _stone_b: StandardMaterial3D = null
static var _blend_mat: ShaderMaterial = null

static func _ensure_mats() -> void:
	if _stone_a != null:
		return
	_stone_a = StandardMaterial3D.new()
	_stone_a.albedo_color = Color(0.21, 0.20, 0.185)
	_stone_a.roughness = 0.95
	_stone_b = StandardMaterial3D.new()
	_stone_b.albedo_color = Color(0.13, 0.125, 0.12)
	_stone_b.roughness = 1.0
	var shd := Shader.new()
	shd.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float r = clamp(length(lp.xz) / 4.5, 0.0, 1.0);
	ALBEDO = vec3(0.02, 0.02, 0.025);
	ALPHA = pow(1.0 - r, 2.2) * 0.6;
}"""
	_blend_mat = ShaderMaterial.new()
	_blend_mat.shader = shd

func _add_base_blend(f: float) -> void:
	_ensure_mats()
	var k := f / 1.5 * 0.8   # 底座尺寸按旧 1.5 基准归一后，再缩到原来的 80%
	# 外圈低矮过渡台（颜色更深，视觉上"长"进地里）
	var s1 := MeshInstance3D.new()
	var c1 := CylinderMesh.new()
	c1.top_radius = 1.68
	c1.bottom_radius = 1.96
	c1.height = 0.14
	c1.radial_segments = 32
	s1.mesh = c1
	s1.material_override = _stone_b
	s1.scale = Vector3(k, k, k)
	s1.position.y = 0.05 * k
	add_child(s1)
	# 内圈石台（承接模型底部）
	var s2 := MeshInstance3D.new()
	var c2 := CylinderMesh.new()
	c2.top_radius = 1.24
	c2.bottom_radius = 1.44
	c2.height = 0.30
	c2.radial_segments = 32
	s2.mesh = c2
	s2.material_override = _stone_a
	s2.scale = Vector3(k, k, k)
	s2.position.y = 0.15 * k
	add_child(s2)
	# 接地暗影（径向渐隐，假 AO，压住地面硬边）
	var sh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.3, 5.3)
	sh.mesh = pm
	sh.material_override = _blend_mat
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.scale = Vector3(k, 1.0, k)
	sh.position.y = 0.02
	add_child(sh)

# —— 被摧毁的倒塌动画（主机与客户端共用同一份，保证两端表现一致）——
# 把所有可视子节点收进一个 pivot 再倾斜/下沉/压扁，实体自身（含快照位置）不受影响。
static func play_collapse(root: Node3D, sf: float, fx_parent: Node = null) -> void:
	if root == null or not is_instance_valid(root):
		return
	_ensure_mats()
	# 水晶：中心朝天打出光柱 → 晶核与碎石四散爆裂（塔保持原来的倾斜倒塌）
	if str(root.get("display_name")) == "crystal":
		_play_crystal_blast(root, sf, fx_parent)
		return
	var pivot := Node3D.new()
	pivot.name = "CollapsePivot"
	root.add_child(pivot)
	var kids: Array = []
	for c in root.get_children():
		if c != pivot and c is Node3D and not (c is CollisionShape3D):
			kids.append(c)
	for c in kids:
		c.reparent(pivot)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(pivot, "rotation:z", 0.40, 1.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "rotation:x", -0.24, 1.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "position:y", -1.35 * sf, 2.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(pivot, "scale", Vector3(0.85, 0.55, 0.85), 2.05)
	# 碎石：从塔身飞出、落地后自毁
	var host := fx_parent if fx_parent != null and is_instance_valid(fx_parent) else root
	for i in range(9):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.25, 0.55), randf_range(0.22, 0.45), randf_range(0.25, 0.55)) * sf
		mi.mesh = bm
		mi.material_override = _stone_a
		var start := root.global_position + Vector3(randf_range(-0.7, 0.7) * sf, randf_range(1.0, 3.0) * sf, randf_range(-0.7, 0.7) * sf)
		mi.global_position = start
		host.add_child(mi)
		var d := randf_range(0.6, 1.0)
		var t2 := mi.create_tween()
		t2.set_parallel(true)
		t2.tween_property(mi, "global_position", Vector3(start.x + randf_range(-2.4, 2.4) * sf, 0.12, start.z + randf_range(-2.4, 2.4) * sf), d).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t2.tween_property(mi, "rotation", Vector3(randf() * 6.0, randf() * 6.0, randf() * 6.0), d)
		t2.chain().tween_callback(mi.queue_free)


# —— 水晶爆炸（host 与联机客户端共用）：蓄能 → 朝天光柱 → 晶核/碎石爆裂 ——
static func _play_crystal_blast(root: Node3D, sf: float, fx_parent: Node = null) -> void:
	var host: Node = fx_parent if fx_parent != null and is_instance_valid(fx_parent) else root
	var tree := root.get_tree()
	var base: Vector3 = root.global_position
	var center: Vector3 = base + Vector3(0.0, 2.1 * sf, 0.0)
	var cold := Color(0.84, 0.94, 1.0)
	var warm := Color(1.0, 0.86, 0.46)

	# 把所有可视子节点收进 pivot：蓄能时整体微胀，爆裂时整块塌缩
	var pivot := Node3D.new()
	pivot.name = "CrystalBlastPivot"
	root.add_child(pivot)
	var kids: Array = []
	for c in root.get_children():
		if c != pivot and c is Node3D and not (c is CollisionShape3D):
			kids.append(c)
	for c in kids:
		c.reparent(pivot)

	# 1) 蓄能：地面吸能环 + 晶核轻微膨胀
	Vfx.shockwave(base + Vector3.UP * 0.25, 2.6 * sf, cold, 0.9)
	var tw0 := root.create_tween()
	tw0.set_parallel(true)
	tw0.tween_property(pivot, "scale", Vector3(1.05, 1.12, 1.05), 0.45).set_ease(Tween.EASE_OUT)
	tw0.tween_property(pivot, "rotation:y", 1.2, 0.45).set_ease(Tween.EASE_OUT)

	if tree == null:
		pivot.queue_free()
		return

	# 2) 光柱：0.14s 起，从水晶中心直冲天空（细亮芯 + 冷白主束 + 金色外辉光）
	tree.create_timer(0.55, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(root):
			return
		var c2: Vector3 = root.global_position + Vector3(0.0, 2.1 * sf, 0.0)
		Vfx.beam(c2, c2 + Vector3.UP * 90.0, cold, 0.55 * sf, 2.7)
		Vfx.beam(c2, c2 + Vector3.UP * 90.0, Color(1.0, 0.99, 0.95), 0.20 * sf, 2.2)
		Vfx.beam(c2, c2 + Vector3.UP * 72.0, warm, 1.35 * sf, 3.0)
		Vfx.hit_spark(c2, cold, Vector3.UP, 3.6)
		_spawn_beam_embers(c2, host, cold)
		Vfx.camera_shake(0.42, 0.85)
		Vfx.screen_flash(Color(0.86, 0.94, 1.0), 0.22))

	# 3) 爆裂：0.26s 时晶核塌缩 + 碎片向外上方炸开、受重力落回地面
	tree.create_timer(1.0, true, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(root):
			return
		var b2: Vector3 = root.global_position
		Vfx.shockwave(b2 + Vector3.UP * 0.3, 7.0 * sf, cold, 1.5)
		Vfx.shockwave(b2 + Vector3.UP * 0.3, 4.4 * sf, warm, 1.2)
		Vfx.hit_spark(b2 + Vector3.UP * 2.0 * sf, warm, Vector3.UP, 4.2)
		var twk := root.create_tween()
		twk.set_parallel(true)
		twk.tween_property(pivot, "scale", Vector3(0.04, 0.04, 0.04), 0.5).set_ease(Tween.EASE_IN)
		twk.tween_property(pivot, "position:y", 0.55 * sf, 0.5).set_ease(Tween.EASE_OUT)
		twk.tween_property(pivot, "rotation:y", randf_range(-4.0, 4.0), 0.55)
		_spawn_crystal_shards(root, sf, host))


# 爆裂的光柱余烬：沿光柱向上飘的火星
static func _spawn_beam_embers(center: Vector3, host: Node, col: Color) -> void:
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 2.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.position = center
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.5 * 1.0
	p.emission_ring_height = 0.5
	p.direction = Vector3.UP
	p.spread = 16.0
	p.gravity = Vector3(0.0, 5.0, 0.0)
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 1.1
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.r, col.g, col.b, 0.95)
	p.material_override = m
	host.add_child(p)
	p.emitting = true
	var tree := host.get_tree()
	if tree != null:
		tree.create_timer(3.2, true, false, true).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free())


# 碎裂的晶体/碎石：向外抛出 → 受重力落回地面 → 淡出
static func _spawn_crystal_shards(root: Node3D, sf: float, host: Node) -> void:
	var base: Vector3 = root.global_position
	var center: Vector3 = base + Vector3(0.0, 2.0 * sf, 0.0)
	var cold := Color(0.72, 0.90, 1.0)
	var warm := Color(1.0, 0.88, 0.55)
	for i in range(24):
		var mi := MeshInstance3D.new()
		var sz: Vector3 = Vector3(randf_range(0.16, 0.46), randf_range(0.26, 0.95), randf_range(0.16, 0.46)) * sf
		if i % 3 == 0:
			var pm := PrismMesh.new()
			pm.size = sz
			mi.mesh = pm
		else:
			var bm := BoxMesh.new()
			bm.size = sz
			mi.mesh = bm
		var col: Color = cold.lerp(warm, randf())
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = randf_range(0.9, 2.4)
		mat.roughness = 0.22
		mat.metallic = 0.15
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ang: float = randf() * TAU
		var out: Vector3 = Vector3(cos(ang), 0.0, sin(ang)) * randf_range(0.8, 2.6) * sf
		var start: Vector3 = center + Vector3(0.0, randf_range(-1.2, 1.6) * sf, 0.0)
		mi.global_position = start
		mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		host.add_child(mi)
		var peak: Vector3 = start + out + Vector3(0.0, randf_range(1.8, 4.5) * sf, 0.0)
		var land: Vector3 = Vector3(peak.x * 1.15 + randf_range(-1.0, 1.0) * sf, 0.12,
			peak.z * 1.15 + randf_range(-1.0, 1.0) * sf)
		var up_dur: float = randf_range(0.50, 0.70)
		var down_dur: float = randf_range(0.85, 1.15)
		var tw := mi.create_tween()
		tw.tween_property(mi, "global_position", peak, up_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "global_position", land, down_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(mi, "rotation",
			mi.rotation + Vector3(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0)),
			up_dur + down_dur)
		tw.parallel().tween_property(mat, "albedo_color:a", 0.0, down_dur * 0.9)
		tw.chain().tween_callback(mi.queue_free)


# 主机侧倒塌：几何动画 + 尘环/火花（客户端复用 play_collapse 并放同样的 VFX）
func _play_destruction() -> void:
	dying_visual = true
	var sf := 1.9 if display_name == "crystal" else 1.6
	play_collapse(self, sf, get_parent())
	Vfx.shockwave(global_position + Vector3(0, 0.25, 0), 3.2 * sf, Color(0.74, 0.70, 0.64), 0.8)
	Vfx.hit_spark(global_position + Vector3.UP * 1.4 * sf, Color(1.0, 0.76, 0.42), Vector3.UP, 1.8)

# 防御塔免疫全部控制效果：
# - 受控计时（击飞/眩晕/冰冻/压制/沉默）每帧清空后再走基类 _process，杜绝上抛/冻结表现
# - 击退/位移（外力直接挪 global_position）在 _physics_process 就地回正到出生点
# - 控制类减速/减攻速由 _is_speed_cc_immune 拦截（见基类 _push_or_refresh_speed_buff）
func _process(delta: float) -> void:
	stun_timer = 0.0
	knockup_timer = 0.0
	froze_timer = 0.0
	suppress_timer = 0.0
	silence_timer = 0.0
	super._process(delta)
	# 塔顶晶核：持续自转 + 上下浮动（普通塔与水晶共用）
	if _crystal_pivot != null and is_instance_valid(_crystal_pivot):
		_crystal_t += delta
		_crystal_pivot.rotation.y += delta * (0.85 if display_name != "crystal" else 0.52)
		_crystal_pivot.position.y = sin(_crystal_t * 1.6) * 0.07
	_update_tower_shield_visual(delta)
	_update_lock_beam(delta)

## 塔盾实物模型：tower_shield_active 期间显示，随护盾消失/时间结束自动移除
func _update_tower_shield_visual(delta: float) -> void:
	var active: bool = tower_shield_active and tower_shield > 0.0 and health > 0.0
	if active:
		if _tower_shield_vis == null or not is_instance_valid(_tower_shield_vis):
			_tower_shield_vis = TurretMesh.tower_shield_visual(team, display_name == "crystal")
			add_child(_tower_shield_vis)
			_tower_shield_t = 0.0
		_tower_shield_t += delta
		_tower_shield_vis.visible = true
		_tower_shield_vis.rotation.y += delta * 0.22
		var grow: float = minf(1.0, _tower_shield_t * 6.0)
		var pulse: float = 1.0 + sin(_tower_shield_t * 2.4) * 0.012
		var s: float = lerpf(0.80, 1.0, grow) * pulse
		_tower_shield_vis.scale = Vector3(s, s, s)
	elif _tower_shield_vis != null and is_instance_valid(_tower_shield_vis):
		_tower_shield_vis.queue_free()
		_tower_shield_vis = null

# 锁定光束：只要 current_target 活着就一直从塔顶连到目标（不再是只在开火瞬间闪一下）
func _update_lock_beam(delta: float) -> void:
	var tgt = current_target
	var alive: bool = health > 0 and tgt != null and is_instance_valid(tgt) and tgt.health > 0
	if not alive:
		if _lock_beam != null and is_instance_valid(_lock_beam) and _lock_beam.visible:
			_lock_beam.visible = false
		if _lock_net_on:
			_lock_net_on = false
			NetSession.push_tower_lock(global_position, global_position, team, false)
		return
	if _lock_beam == null or not is_instance_valid(_lock_beam):
		_lock_beam = Vfx.make_lock_beam(Vfx.team_color(team))
		add_child(_lock_beam)
	var from: Vector3 = global_position + Vector3(0, 3.45 if display_name != "crystal" else 3.30, 0)
	var to: Vector3 = tgt.global_position + Vector3.UP * 1.0
	Vfx.aim_lock_beam(_lock_beam, from, to, Time.get_ticks_msec() * 0.001)
	_lock_send_t -= delta
	if not _lock_net_on or _lock_send_t <= 0.0:
		_lock_net_on = true
		_lock_send_t = 0.15
		NetSession.push_tower_lock(from, to, team, true)


func _is_speed_cc_immune() -> bool:
	return true

func _physics_process(delta):
	if health <= 0: return
	# 免疫击退/位移：塔从不移动，任何被外力挪动都在物理帧内回正
	if _anchor_set and global_position.distance_to(_anchor) > 0.01:
		global_position = _anchor
	if under_attack_timer > 0.0:
		under_attack_timer = maxf(under_attack_timer - delta, 0.0)
	if interfere_timer > 0:
		interfere_max = max(interfere_max, interfere_timer)
		interfere_timer -= delta
		return
	if attack_timer > 0: attack_timer -= delta

	search_timer -= delta
	if search_timer <= 0:
		search_timer = 0.5
		_find_target()
		if display_name == "crystal":
			if not _has_enemy_minion_near():
				_apply_healing(28)
		# 护盾每秒衰减2%最大生命值
	if tower_shield_active:
		tower_shield -= max_health * 0.02 * delta
		if tower_shield <= 0:
			tower_shield = 0
			tower_shield_active = false

	# 4分钟后清除所有护盾状态
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if battle and battle.game_time >= 240.0:
		tower_shield = 0
		tower_shield_active = false
		shield_stage_75 = false
		shield_stage_50 = false
		shield_stage_25 = false
	if current_target and is_instance_valid(current_target) and current_target.health>0:
		var dist = global_position.distance_to(current_target.global_position) 
		if dist <= attack_range*0.01:
			if attack_timer <= 0:
				# 计算连续攻击增伤（只对英雄生效）
				var multiplier = 1.0
				var ignore = false
				if current_target is Hero:
					if current_target == last_target:
						consecutive_hits += 1
					else:
						consecutive_hits = 1
						last_target = current_target
					multiplier = min(1.0 + 0.6 * (consecutive_hits - 1), 4.0)
					ignore = true   # 防御塔伤害无视英雄护甲
				else:
					consecutive_hits = 0
					last_target = null
					ignore = false
					# 对炮车/龙兵伤害减半
					if current_target is Minion and current_target.display_name in ["siege", "dragon", "shadow_dragon", "storm"]:
						multiplier = 0.5
					

				var actual_damage = attack * multiplier

				# 激光攻击：常驻细锁定光束 + 能量球沿同一束光飞行，到达目标才结算伤害
				var tgt := current_target
				var from := global_position + Vector3(0, 3.45 if display_name != "crystal" else 3.30, 0)
				var to := tgt.global_position + Vector3.UP * 1.0
				var dst := from.distance_to(to)
				var fly_t := clampf(dst / 26.0, 0.22, 0.85)   # 能量球飞行时间（伤害在到达时结算）
				var orb := Bullet.new()
				orb.speed = dst / fly_t          # 让弹体正好用 fly_t 秒飞完
				orb.damage = actual_damage
				orb.team = team
				orb.target = tgt
				orb.source = self
				orb.is_magic = false
				orb.pen_percent = 1.0 if ignore else 0.0
				orb.target_offset = Vector3.UP   # 与常驻锁定光束同一个命中点
				get_parent().add_child(orb)
				orb.global_position = from
				# 塔开火音：按塔档位 + 阵营定制（仅本地英雄在附近时）
				SfxManager.try_tower_attack_sfx(team, display_name, global_position)

				attack_timer = 1.0 / attack_speed
		else:
			current_target = null
			last_target = null
			consecutive_hits = 0
	else:
		current_target = null
		last_target = null
		consecutive_hits = 0

	# 更新范围预览颜色（保留原有逻辑）
	_update_range_preview()
func _find_nearest_health_pack() -> HealthPack:
	var packs = get_tree().get_nodes_in_group("health_packs")  # 给 HealthPack 加入该组
	var best: HealthPack = null
	var best_dist = 6
	for p in packs:
		if  p.team == team:
			var dist = global_position.distance_to(p.global_position)
			if dist < best_dist:
				best_dist = dist
				best = p
	return best
func die(killer):
	if _lock_beam != null and is_instance_valid(_lock_beam):
		_lock_beam.visible = false
	if _lock_net_on:
		_lock_net_on = false
		NetSession.push_tower_lock(global_position, global_position, team, false)
	var p = _find_nearest_health_pack()
	if p:
		p.queue_free()
	var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if display_name.contains("high"):
		var lane = ""
		var s = global_position.x + global_position.z
		if s > 0:
			lane = "farm"
		elif s < 0:
			lane = "clash"
		else:
			lane = "mid"
		if bm and lane != "":
			bm.high_tower_destroyed[team][lane] = true
			# 超级兵出动播报：仅在高地塔被摧毁时随后播 1 次，不再每波小兵重复
			if bm.ui:
				bm.ui.show_kill_feed("超级兵", team, "出动！")
	# 己方边路二塔被摧毁：60 秒后于原位置生成视野之灵
	if display_name == "inner" and bm and team == Config.player_team:
		var lane2 := ""
		var sx := global_position.x + global_position.z
		if sx > 0:
			lane2 = "farm"
		elif sx < 0:
			lane2 = "clash"
		if lane2 != "":
			bm.schedule_vision_spirit(global_position, lane2)
	if display_name == "crystal":
		if bm:
			bm.crystal_destroyed(team)
	# 残骸减速带：水晶被毁即终局，不需要；其余塔摧毁后留减速区
	elif bm:
		var slow_pct: float = {"outer": 0.3, "inner": 0.6, "high": 0.9}.get(display_name, 0.9)
		bm.spawn_tower_wreck(team, global_position, slow_pct)
	# 塔摧毁爆炸音（本地英雄附近才响；塔被摧毁瞬间位置仍有效）+ 倒塌提示音（敌我音色不同）
	SfxManager.try_tower_sfx("boom", global_position)
	SfxManager.try_tower_destroyed_sfx(team, global_position)
	death_delay_override = 2.25   # 等倒塌动画播完再 queue_free（动画 ~2.05s）
	_play_destruction()
	super.die(killer)
func _has_enemy_minion_near() -> bool:
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Minion and entity.team != team and entity.health > 0:
			if global_position.distance_to(entity.global_position) < 8.9:
				return true
	return false
func _find_target():
	var reach := attack_range * 0.01
	# 1. 只认「敌方英雄在塔的攻击范围内实际打到我方英雄」这一事件。
	#    不使用 enemy.current_target（那只是 AI/玩家的上次目标，可能并未出手，也可能在塔外打人）。
	var now := Time.get_ticks_msec() * 0.001
	for victim in get_tree().get_nodes_in_group("heroes"):
		if not (victim is Hero) or victim.team != team or victim.health <= 0.0:
			continue
		var attacker: Hero = victim.last_hero_attacker
		if attacker == null or not is_instance_valid(attacker) or attacker.health <= 0.0:
			continue
		if attacker.team == team:
			continue
		if now - victim.last_hero_attacker_at > HERO_AGGRO_WINDOW:
			continue
		# 命中发生时，双方都必须处于本塔攻击范围内；之后攻击者仍在范围内才锁
		if global_position.distance_to(victim.last_hero_attacked_at) > reach + victim.body_radius:
			continue
		if global_position.distance_to(victim.last_hero_attacked_from) > reach + attacker.body_radius:
			continue
		if global_position.distance_to(attacker.global_position) > reach + attacker.body_radius:
			continue
		if attacker.collision_layer == 0 or attacker.is_invisible_to_enemy():
			continue
		current_target = attacker
		return
	if current_target and current_target.health >0:return
	# 2. 其次攻击小兵
	var best_minion: Minion = null
	var best_minion_dist = reach + 1.0
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity is Minion and entity.team != team and entity.health > 0 and entity.collision_layer != 0:
			var dist = global_position.distance_to(entity.global_position) 
			if dist <= reach and dist < best_minion_dist:
				best_minion_dist = dist
				best_minion = entity
	if best_minion:
		current_target = best_minion
		return

	# 3. 攻击戍鼎
	var best_tripod: Tripod = null
	var best_tripod_dist = reach + 1.0
	for entity in get_tree().get_nodes_in_group("tripods"):
		if entity is Tripod and entity.team != team and entity.health > 0:
			var dist = global_position.distance_to(entity.global_position)
			if dist <= reach and dist < best_tripod_dist:
				best_tripod_dist = dist
				best_tripod = entity
	if best_tripod:
		current_target = best_tripod
		return

	# 不再兜底攻击「只是站在塔里的敌方英雄」：没有塔内打我方英雄的事件就不锁英雄
	current_target = null
func get_hit_flash_root() -> Node3D:
	return _body_vis if _body_vis != null and is_instance_valid(_body_vis) else self

# 塔身受击不再抖动（用户要求）：受击反馈只保留闪白（GameEntity/UnitVisuals.hit_flash）
func play_hit_react() -> void:
	pass

var _recently_reported
func _clear_recently_reported() -> void:
	_recently_reported = false

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false,skill_id:int=0,pen: float = 0.0, is_crit_forced: int = -1):
	# 无兵线减伤：仅对英雄伤害生效，且塔附近没有攻击方的小兵
	if not _recently_reported and Config.is_ally(team):
		var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		# 按塔类型出差异化警报文案（高地塔/水晶），战报 desc 直接给到 SfxManager 选对应语音
		var warn_desc := "我方防御塔正在被攻击"
		if display_name == "high":
			warn_desc = "我方高地防御塔正在被攻击"
		elif display_name == "crystal":
			warn_desc = "我方水晶正在被攻击"
		battle.ui.show_kill_feed("", Config.Team.NEUTRAL, warn_desc, display_name, team)
		_recently_reported = true
		# 不能用 await：take_damage 会挂起 25 秒，首次命中（例如第一只小兵）等于白打
		get_tree().create_timer(25.0).timeout.connect(_clear_recently_reported)
	if source and (source.display_name in ["siege", "super", "shadow_dragon"]):
		amount *= 2.0
	if source and source.display_name in ["dragon", "storm"]:
		amount *= 1.2
	# 暗影之径：整条分路上的友方单位对建筑增伤10%
	if source:
		var bm = get_tree().get_first_node_in_group("battle_manager") as BattleManager
		if bm and bm.is_on_shadow_path(source.team, source.global_position):
			amount *= 1.1
	# 风暴先锋塔干扰：首击沉默防御塔3秒
	if source and source.display_name == "storm" and not storm_interfere_done:
		storm_interfere_done = true
		interfere_timer = max(interfere_timer, 3.0)
	if source and source is Hero:
		# 塔免疫英雄技能：普攻(skill_id==0)与刘禅技能放行；李元芳Q暗印爆炸(-80)同样放行——
		# Q允许锁塔、普攻可叠印、血条有爆炸预判，爆炸若被吞则Q对塔完全无伤害
		if skill_id != 0 and source.display_name != "刘禅" and not (source.display_name == "李元芳" and skill_id == -80):
			return
		var attacker_team = source.team
		var has_minion_near = false
		for entity in get_tree().get_nodes_in_group("entities"):
			if entity is Minion and entity.team == attacker_team and entity.health > 0:
				if global_position.distance_to(entity.global_position) < 8.9:
					has_minion_near = true
					break
		if not has_minion_near:
			amount *= 0.45   # 只能造成45%伤害
	# 我方塔被攻击：真实伤害判定通过后打"被攻击"窗口标记（塔盾吸收命中也算被攻击）
	if health > 0.0:
		under_attack_timer = UNDER_ATTACK_WINDOW
	# 塔盾吸收
	if tower_shield > 0:
		UnitVisuals.hit_flash(get_hit_flash_root())
		play_hit_react()
		if tower_shield >= amount:
			tower_shield -= amount
			_check_tower_shield_triggers()
			return
		else:
			# 护盾被击穿：剩余溢出伤害继续落到塔身上（原实现直接清零 → 这一击完全免疫）
			amount -= tower_shield
			tower_shield = 0
	if source:
		super.take_damage(amount, source, is_magic,skill_id,pen, is_crit_forced) 
	_check_tower_shield_triggers()

func _check_tower_shield_triggers():
	var battle = get_tree().get_first_node_in_group("battle_manager") as BattleManager
	if not battle or battle.game_time > 240.0: return

	var hp_ratio = health / max_health
	if hp_ratio <= 0.75 and not shield_stage_75:
		_activate_tower_shield(0.75)
		shield_stage_75 = true
	elif hp_ratio <= 0.5 and not shield_stage_50:
		_activate_tower_shield(0.5)
		shield_stage_50 = true
	elif hp_ratio <= 0.25 and not shield_stage_25:
		_activate_tower_shield(0.25)
		shield_stage_25 = true

func _activate_tower_shield(stage: float):
	var lost_health = max_health - health
	tower_shield = lost_health
	tower_shield_active = true

const TOTAL_PER_SIDE: int = 10   # 每方 9 塔 + 1 水晶（对战纪录统计用）
