class_name Bullet
extends Area3D
const HeroSkinTable = preload("res://scripts/core/HeroSkins.gd")
const HeroProjectilesScript = preload("res://scripts/presentation/HeroProjectiles.gd")
var _skin_fx_accent := Color(0, 0, 0, 0)
var attacked:Array=[]
var speed: float = 20.0
var damage: float = 0.0
var team: int = 0
var source: GameEntity = null
var is_magic: bool = false
var life_time: float = 10.0
var radius: float = 0.2
# 线性技能子弹：命中判定半径（线性技能专用，>=radius；<=0 表示沿用 radius）
var hit_radius: float = -1.0
var pierce:bool =false
# 元流之子·万物为流贯穿强普：逐目标额外伤害（80+20%额外AD，每次命中衰减至70%）与已命中计数
var yuanliu_strong: bool = false
var yuanliu_strong_extra: float = 0.0
var yuanliu_hits: int = 0
# 跟踪目标模式
var target: GameEntity = null
var target_offset: Vector3 = Vector3.ZERO   # 防御塔：瞄准目标+1m，与锁定光束同一条线
var damage_range: float=0.0
var is_crit: bool = false
# 线性模式
var linear_dir: Vector3 = Vector3.ZERO
var max_distance: float = 10.0
var lock_on: bool = false   # 显式锁敌技能弹（妲己W/R、小乔R、元流R）；不能仅因命中后 target 被赋值就跳过寿命/距离
var traveled: float = 0.0
var pen_percent: float = 0.0
var visual_mesh: Node3D
var _spin_node: Node3D = null      # 扇面等自转件（视觉子节点，只转视觉）
var _spin_speed: float = 0.0
var slow_per: float=0.0
var slow_dur: float = 0.0
var stun_dur: float=0.0
var armor_drop_per: float = 0.0
var armor_drop_flat: float = 0.0
var magic_resist_drop_per: float = 0.0
var magic_resist_drop_flat: float = 0.0
var drop_dur: float = 0.0
var knock_dur :float = 0.0
var goal: Vector3=Vector3.ZERO
var path_hit: bool = false   # goal 模式是否沿途判伤（默认只到落点爆炸；安琪拉1技能开启）
var drop_mode: bool = false  # 垂直落体（小乔R流星等）：落点判定用三维距离，避免高空水平重合就爆炸
var fire_damage:float = 0.0
var timer:float=0.0
var skill_id: int = 0
var counts_as_aa: bool = false   # 该命中视作一次普攻 → 命中触发普攻类装备特效（闪电匕首等）
var aa_proc_done: bool = false   # 穿刺型只对首个目标触发一次
var lanling_mark: bool = false
var lanling_mark_dmg: float = 0.0
var transfer: int = 0
var repel: bool = false
var luban_w_knockback: bool = false   # 鲁班W：仅击退近身目标
var hit :bool = false
var _pitch_visual: bool = false   # 箭矢类弹体：视觉俯仰跟随弹道（球体光效不需要）
# 安琪拉2技能
var angela_w: bool = false
var angela_w_level: int = 0
var angela_w_timer: float = 0.0
var angela_w_hit: bool = false
var angela_w_last_tick: int = -1   # 安琪拉W：上一个已触发的tick值，防止连续物理帧重复AoE伤害
var angela_w_speed: float = 10.0   # 安琪拉W：命中后用于衰减的移速
var xiaoqiao_q_hits: int = 0
var aoe_mult: float = 1.0
var luban_w_missing_hp_pct: float = 0.0   # 鲁班七号W：已损生命百分比法伤
var xiahou_r_dash: bool = false           # 夏侯惇R：命中后拉拽英雄
var houyi_r: bool = false                   # 后羿R：全图火焰箭
var houyi_r_origin: Vector3 = Vector3.ZERO  # 后羿R：发射位置
var _reveal_tick := 0.0                      # 鲁班2/后羿R：飞行路径侦察节拍
var is_houyi_ult: bool = false              # 后羿R：使用太阳火箭视觉
var dayu_w: bool = false          # 大禹W子弹标记
var dayu_r1: bool = false         # 大禹R1乾鼎标记
var transferring: bool = false              # 防重入：弹射协程运行时阻止重复触发
func _ready():
	add_to_group("projectiles")
	if source is Hero and source.has_method("skin_is_custom") and source.skin_is_custom():
		_skin_fx_accent = source.skin_accent_color()
	# 普攻/塔/兵弹道统一走程序化能量弹（双端同源）；技能弹保留原有定制视觉
	var _vk := BulletVisual.vkind_for(self)
	if HeroProjectilesScript.is_hero_vkind(_vk):
		_build_hero_projectile_visual(_vk)
		return
	if _vk > 0:
		_build_unified_visual()
		return
	# 根据发射源选择弹道模型
	# 根据发射源选择弹体模型（三端共享：ProjectilePresenter）
	var model_path: String = ProjectilePresenter.model_path_for(source)
	var model = load(model_path) if model_path != "" else null
	if model:
		visual_mesh = model.instantiate()
		_recursive_set_shadow(visual_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		add_child(visual_mesh)
	else:
		if source is Turret:
			# 防御塔能量球：核心亮球 + 两层加色光晕（unshaded 下 emission 不生效，亮度靠加色叠层）
			visual_mesh = ProjectilePresenter.tower_orb(radius)
			_recursive_set_shadow(visual_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			add_child(visual_mesh)
		else:
			# 回退：球体
			visual_mesh = MeshInstance3D.new()
			var mesh = SphereMesh.new()
			mesh.radius = radius
			mesh.height = radius * 2.0
			visual_mesh.mesh = mesh
			visual_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(visual_mesh)
			var mat = StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.33, 0.264, 1.0) if team == 1 else Color(0.0, 0.886, 1.0, 1.0)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			visual_mesh.material_override = mat

	# 英雄和防御塔普攻子弹放大2倍
	if (source is Hero ) or (source is Turret):
		if visual_mesh:
			visual_mesh.scale = Vector3.ONE * ProjectilePresenter.source_scale(source)

		# 后羿R：自定义太阳火箭模型
		if is_houyi_ult:
			if visual_mesh:
				visual_mesh.queue_free()
			# 三端共享：后羿R 太阳火箭
			visual_mesh = ProjectilePresenter.houyi_ult_arrow()
			add_child(visual_mesh)
	# P0：英雄来源弹道统一挂元素色拖尾（移动端 8 粒子，超并发预算时 Vfx 内部自动丢弃）
	if source is Hero and visual_mesh:
		if _skin_fx_accent.a > 0.0:
			HeroSkinTable.apply_fx_color(visual_mesh, _skin_fx_accent)
		ProjectilePresenter.attach_hero_trail(self, str(source.display_name), _skin_fx_accent)
	# 线性技能弹（模型路径）：整体放大，判定见 hit_radius
	if linear_dir != Vector3.ZERO and int(skill_id) != 0 and visual_mesh and is_instance_valid(visual_mesh):
		visual_mesh.scale *= 1.5
	# 不添加碰撞体，使用手动距离检测

## 英雄专属弹体：高细节程序化武器/法球模型（三端同源 vkind）
func _build_hero_projectile_visual(vk: int) -> void:
	visual_mesh = HeroProjectilesScript.build_from_vkind(vk)
	if visual_mesh == null:
		visual_mesh = MeshFactory.create_sphere(0.25, Color(0.8, 0.9, 1.0), true, 0.9)
	var base := 1.0
	if linear_dir != Vector3.ZERO and int(skill_id) != 0:
		base = 1.35
	# 英雄普攻弹体额外放大2倍（技能弹保持原尺寸）
	var aa_size := 2.0 if int(skill_id) == 0 else 1.0
	_pitch_visual = bool(visual_mesh.get_meta("pitch", false))
	visual_mesh.scale = Vector3.ONE * base * 0.82 * aa_size
	_recursive_set_shadow(visual_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	add_child(visual_mesh)
	var spn := visual_mesh.get_node_or_null("Spin")
	if spn is Node3D:
		_spin_node = spn
		_spin_speed = float(visual_mesh.get_meta("spin", 1.2))
	if source is Hero:
		if _skin_fx_accent.a > 0.0:
			HeroSkinTable.apply_fx_color(visual_mesh, _skin_fx_accent)
		var c1: Color = visual_mesh.get_meta("c1", Vfx.color_for_hero(str(source.display_name)))
		var c2: Color = visual_mesh.get_meta("c2", c1.lightened(0.35))
		Vfx.attach_trail(self, c1, 0.24, 0.32, 8, c2)
		Vfx.muzzle(global_position, _aim_dir(), c1, c2)
	var tw := create_tween()
	tw.tween_property(visual_mesh, "scale", Vector3.ONE * base * 1.10 * aa_size, 0.06)
	tw.tween_property(visual_mesh, "scale", Vector3.ONE * base * aa_size, 0.06)


## 统一程序化弹体：核心形态 + 双色光晕 + 元素拖尾 + 出手弹跳（判定/速度完全不变）
func _build_unified_visual() -> void:
	var spec := BulletVisual.spec_for(self)
	var base: float = float(spec.get("size_mult", 1.0))
	# 线性技能弹：视觉整体放大（判定同步放大，见 set_linear/hit_radius）
	if linear_dir != Vector3.ZERO and int(skill_id) != 0:
		base *= 1.7
	# 箭矢类（弓兵实体箭 / 后羿箭）需要俯仰跟随弹道，球体光效不需要
	var shape := int(spec["shape"])
	_pitch_visual = shape == BulletVisual.SHAPE_BOLT or shape == BulletVisual.SHAPE_ARROW
	var _c1: Color = spec["c1"]
	var _c2: Color = spec["c2"]
	if _skin_fx_accent.a > 0.0:
		_c1 = _skin_fx_accent
		_c2 = _skin_fx_accent.lightened(0.35)
	visual_mesh = BulletVisual.build(shape, _c1, _c2, base)
	_recursive_set_shadow(visual_mesh, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	add_child(visual_mesh)
	var spn := visual_mesh.get_node_or_null("Spin")
	if spn is Node3D:
		_spin_node = spn
		_spin_speed = float(visual_mesh.get_meta("spin", 0.0))
	if source is Hero:
		# 技能弹只在「真弹道」（直线飞行 + 有伤害）挂拖尾；原地爆炸载体不挂，防刷爆预算
		var is_skill := int(skill_id) != 0
		if not is_skill or (linear_dir != Vector3.ZERO and float(damage) > 0.0):
			Vfx.attach_trail(self, _c1, float(spec["trail_size"]), float(spec["trail_life"]), 8, _c2)
		Vfx.muzzle(global_position, _aim_dir(), _c1, _c2)
	# 出手弹跳：0.7 → 1.08 → 1.0（缩放只作用于视觉根，不影响碰撞）
	visual_mesh.scale = Vector3.ONE * base * 0.7
	var tw := create_tween()
	tw.tween_property(visual_mesh, "scale", Vector3.ONE * base * 1.08, 0.06)
	tw.tween_property(visual_mesh, "scale", Vector3.ONE * base, 0.05)


## 当前飞行朝向（用于枪口/命中特效定向；无目标时回退直线方向）
func _aim_dir() -> Vector3:
	if target != null and is_instance_valid(target):
		var d := target.global_position + target_offset - global_position
		if d.length() > 0.01:
			return d.normalized()
	if goal != Vector3.ZERO:
		var g := goal - global_position
		if g.length() > 0.01:
			return g.normalized()
	if linear_dir != Vector3.ZERO:
		return linear_dir
	return Vector3.FORWARD

func set_linear(dir: Vector3, distance: float):
	linear_dir = dir.normalized()
	max_distance = distance
	traveled = 0.0
	# 线性技能弹判定半径放大：直线技能更好命中（视觉同步在 _ready 放大；AoE 半径仍用 radius）
	hit_radius = maxf(radius * 2.6, 0.55)
func set_goal(pos):
	goal = pos

# 鲁班七号2技能：只命中英雄；小兵/野怪/塔一律穿过（全图炮只打英雄）。
## 鲁班2/后羿R 的侦察视野：命中点周围敌方单位强制可见 2 秒
func _reveal_enemies_around(center: Vector3, radius: float) -> void:
	if source == null or not is_instance_valid(source):
		return
	for ent in get_tree().get_nodes_in_group("entities"):
		if ent == source or not is_instance_valid(ent):
			continue
		if int(ent.team) == int(team) or ent.health <= 0:
			continue
		if ent is Turret:
			continue
		if center.distance_to(ent.global_position) > radius:
			continue
		ent.vision_expose_timer = maxf(float(ent.vision_expose_timer), 2.0)
		ent.skill_reveal_timer = maxf(float(ent.skill_reveal_timer), 2.0)
		ent.skill_reveal_team = int(team)
	var bm = get_tree().get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("add_skill_reveal_zone"):
		bm.call("add_skill_reveal_zone", int(team), center, radius, 2.0)


func _luban_w_can_hit(entity) -> bool:
	if not luban_w_knockback:
		return true
	# 鲁班2（W）：只打英雄，小兵/野怪/塔全部穿过
	return entity is Hero
# 弹体朝向：偏航跟随飞行方向；箭矢类（BOLT/ARROW）再加俯仰，箭头才不会平飞
func _aim_visual(dir: Vector3) -> void:
	if visual_mesh == null or not is_instance_valid(visual_mesh):
		return
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() > 0.000001:
		visual_mesh.rotation.y = atan2(dir.x, dir.z)
	if _pitch_visual:
		var d := dir.normalized()
		visual_mesh.rotation.x = -asin(clampf(d.y, -1.0, 1.0))
func _physics_process(delta):
	# 发射源已释放（英雄/塔死亡1秒后被queue_free）：子弹立即销毁
	# 否则用已释放对象作为 source 调用 take_damage 会触发类型检查错误
	if source and not is_instance_valid(source):
		queue_free()
		return
	# 锁敌类技能弹（妲己W/R、小乔R、元流之子R等，target + 正技能id）：
	# 不再按 life_time / max_distance 销毁，必须追到并命中目标后由命中逻辑销毁。
	var _lock_on_target: bool = lock_on and target != null and is_instance_valid(target) 		and target.health > 0.0
	if not _lock_on_target:
		life_time -= delta
		if life_time <= 0 :
			queue_free()
			return
	# 扇面等视觉件自转（只转 Spin 子节点，不影响弹道朝向与判定）
	if _spin_node != null and is_instance_valid(_spin_node):
		_spin_node.rotate_y(_spin_speed * delta)
	# 安琪拉2技能：命中后缓慢移动+范围伤害
	if angela_w and angela_w_hit:
		angela_w_timer -= delta
		if angela_w_timer <= 0:
			queue_free()
			return
		# 每0.5秒AoE伤害
		var tick = int(angela_w_timer * 10)
		
		if tick % 5 == 0 and tick != angela_w_last_tick and source:
			angela_w_last_tick = tick
			var w_dmg = 100 + 25*angela_w_level + source.actual_ability_power * 0.2
			for ent in get_tree().get_nodes_in_group("entities"):
				if ent != source and ent.health > 0 and ent.team != team:
					if global_position.distance_to(ent.global_position) <= 1.8:
						ent.take_damage(w_dmg, source, true, 2, 0)
						ent.apply_move_pct_buff("ms_slow", 1.0, -(0.24 + 0.06*angela_w_level), true)
						
		# 命中后移速从10逐渐衰减至停止，火种滑行后滞留
		angela_w_speed = 1.0
		if linear_dir != Vector3.ZERO:
			global_position += linear_dir * angela_w_speed * delta
		return

	# 线性模式
	if goal != Vector3.ZERO:
		var dir = (goal - global_position).normalized()
		global_position += dir * speed * delta

		# 朝向（箭矢类同时俯仰贴弹道）
		_aim_visual(dir)

		# goal 型子弹默认只到落点结算；安琪拉1技能是例外（path_hit=true）：
		# 沿途碰到目标立即结算并消耗，否则五球会穿身而过。
		if path_hit and source:
			for entity in get_tree().get_nodes_in_group("entities"):
				if entity == source or not is_instance_valid(entity): continue
				if entity.team == team or entity.health <= 0: continue
				if entity in attacked: continue
				if global_position.distance_to(entity.global_position) - radius - entity.body_radius <= 0.4:
					target = entity
					on_hit()
					queue_free()
					return

		# 距离检测命中（到达落点：未命中沿途目标就在终点爆一点，on_hit 内按 damage_range 结算范围伤害）
		# 只比水平距离：地面落点 goal.y 通常为 0，而弹体出生在 y=1，三维距离会让落点永远差 1 米而不爆炸
		var _goal_gap := Vector2(global_position.x - goal.x, global_position.z - goal.z).length()
		if drop_mode:
			# 垂直落体：必须真的落到落点高度才爆，否则在目标正上方就会误判命中
			_goal_gap = global_position.distance_to(goal)
		if _goal_gap < 0.45 and source:
			on_hit()
			queue_free()
			
		return
	if linear_dir != Vector3.ZERO:
		var step = speed * delta
		global_position += linear_dir * step
		traveled += step
		# 鲁班2/后羿R：飞行路径周围 3 米持续侦察，敌人被照出 2 秒
		if is_houyi_ult or luban_w_knockback:
			_reveal_tick -= delta
			if _reveal_tick <= 0.0:
				_reveal_tick = 0.12
				_reveal_enemies_around(global_position, 3.0)
		# 后羿R：太阳火箭拖尾和旋转火环
		if is_houyi_ult and visual_mesh:
			# 旋转火环
			if visual_mesh.get_child_count() > 1:
				var fire_ring = visual_mesh.get_child(1)
				if fire_ring:
					fire_ring.rotation.z += delta * 8.0
			# 拖尾粒子
			if randi() % 2 == 0:
				var trail = MeshFactory.create_sphere(0.15, Color(1.0, 0.5, 0.0, 0.6), true, 0.4)
				trail.position = global_position - linear_dir * 0.8
				get_parent().add_child(trail)
				var tt = get_tree().create_tween()
				tt.tween_property(trail, "scale", Vector3(0.1, 0.1, 0.1), 0.4)
				tt.parallel().tween_property(trail.material_override, "albedo_color:a", 0.0, 0.4)
				tt.tween_callback(trail.queue_free)

		# 朝向飞行方向（箭矢类同时俯仰贴弹道）
		_aim_visual(linear_dir)

		# 手动检测碰撞：检查周围所有实体
		var all_entities = get_tree().get_nodes_in_group("entities")
		for entity in all_entities:
			if entity == source or not is_instance_valid(entity): continue
			if entity.team == team: continue
			if entity in attacked:continue
			# 后羿R：仅命中英雄，穿过后排小兵/野怪/塔
			if is_houyi_ult and not (entity is Hero):continue
			# 鲁班W：只打英雄，小兵/野怪/塔穿过
			if not _luban_w_can_hit(entity):continue
			var hr: float = radius if hit_radius <= 0.0 else hit_radius
			var dist = global_position.distance_to(entity.global_position) - hr - entity.body_radius
			if dist <= 0.4:
				damage_range=radius
				target = entity
				# 全图技能命中英雄 → 给小地图打命中反馈时间戳（Minimap 画扩散冲击环）
				if (houyi_r or luban_w_knockback) and entity is Hero:
					entity.set_meta("mm_shot_hit_ms", Time.get_ticks_msec())
					entity.set_meta("mm_shot_hit_kind", "houyi" if houyi_r else "luban")
				# 鲁班2 / 后羿R：命中落点也补一次 3 米侦察（非命中路径的主要判定在飞行中）
				if is_houyi_ult or luban_w_knockback:
					_reveal_enemies_around(global_position, 3.0)
				if source.display_name == "铠" and skill_id == 1:
					target.apply_move_pct_buff("ms_slow", 1, -0.9, true)
					var kai_q_level = source.skill_levels[0]
					source._apply_healing(280 + 70 * kai_q_level + 0.07 * source.bonus_health)
					var kai_q_buff = 0.12 + 0.03 * kai_q_level
					source.apply_attack_pct_buff("as_haste", 3, kai_q_buff)
					source.apply_move_pct_buff("ms_haste", 3, kai_q_buff)
					source.skill_cooldowns[0] *= 0.7
				if source.display_name == "不知火舞" and skill_id == 3:
					target._apply_ak_buff(0,-0.15-0.05*source.skill_levels[2],2.5,false)
					source.mana+=25
				
				if not transferring:
					on_hit()
				
				if transfer>0:
					break
			# 安琪拉2技能首次命中不销毁
				if angela_w:
					break
				if not pierce :
					queue_free()
					return
				

		if traveled >= max_distance and not _lock_on_target:
			if source.display_name == "马超" and skill_id == 1 :
				
				source.skillapply.bpos = global_position
				source.skillapply.bpos_valid = true
			# 甄姬大招：子弹未命中任何目标时，水区仍出现在弹道终点（否则bpos停留旧值/原点）
			if source.display_name == "甄姬" and skill_id == 3 and not source.skillapply.bpos_valid:
				source.skillapply.bpos = Vector3(global_position.x, 0, global_position.z)  # 压到地面
				source.skillapply.bpos_valid = true
			# 夏侯惇R：拉拽英雄至弹着点
			if xiahou_r_dash and source and is_instance_valid(source):
				source.global_position = Vector3(global_position.x, 0.5, global_position.z)
				# 夏侯惇R第二段：延迟0.5秒落点AoE伤害
				if source and source is Hero and source.display_name == "夏侯惇" and source.skill_levels.size() > 2:
					var r2_level = source.skill_levels[2]
					var r2_dmg = 400 + (r2_level - 1) * 200 + source.bonus_health * 0.1
					var _src = source
					var _pos = source.global_position
					var _dmg = int(r2_dmg)
					var _tree = get_tree()
					_tree.create_timer(0.5).timeout.connect(
						func():
							if is_instance_valid(_src) and _src.health > 0:
								for _ent in _src.get_tree().get_nodes_in_group("entities"):
									if _ent != _src and _ent.health > 0 and _ent.team != _src.team:
										if _pos.distance_to(_ent.global_position) <= 3.0:
											_ent.take_damage(_dmg, _src, false, 3, 0)
					)
				
			queue_free()
		return

	# 跟踪模式
	if target and is_instance_valid(target):
		var aim: Vector3 = target.global_position + target_offset
		var dir = (aim - global_position).normalized()
		var step = speed * delta
		var dist_before = global_position.distance_to(aim)
		# 塔能量球瞄准的是光束末端（目标+1m），命中距离按末端收窄，别在半路提前结算
		var hit_dist = 0.3 + radius + (target.body_radius if target_offset == Vector3.ZERO else 0.15)
		global_position += dir * step
		var dist_after = global_position.distance_to(aim)

		# 朝向（箭矢类同时俯仰贴弹道）
		_aim_visual(dir)

		# 距离检测命中
		if (dist_after <= hit_dist or dist_before <= step) and target and source:
			if transfer>0:
				if not attacked.is_empty() and (attacked.count(target)>1 or attacked.back()== target):
					if not transferring:
						check_transfer()
					return
			if not transferring:
				on_hit()							
				# 弹射子弹命中后立即寻找下一目标，防止下一帧重复命中
				if transfer > 0 and not transferring:
					check_transfer()
					return
				# 弹射耗尽或非穿透子弹命中后销毁
				if transfer <= 0 and not pierce:
					queue_free()
					return
	else:
		
		queue_free()
func check_transfer():
	#if transferring:
		#return
	if transfer <=0  and not pierce:
		queue_free()
	elif not pierce:
		transferring = true
		linear_dir=Vector3.ZERO
		life_time = min(life_time, 3.0)
		var found_new = false
		for i in range(6):
			#print(i)
			await source.get_tree().create_timer(0.2).timeout
			if not target: queue_free(); return
			global_position = target.global_position
			if source is Hero and source.display_name == "不知火舞":
				damage *= 0.5
			# 甄姬2技能弹射水花溅射
			if source is Hero and source.display_name == "甄姬" and skill_id == 2:
				if source.skillapply:
					source.skillapply._create_water_splash(get_parent(), global_position)
			var all_entities = get_tree().get_nodes_in_group("entities")
			for entity in all_entities:
				if entity == target:continue
				if entity == source or not is_instance_valid(entity): continue
				if entity.team == team: continue
				var dist = global_position.distance_to(entity.global_position) - radius - entity.body_radius
				if dist <= 4.0:
					if entity is Turret and skill_id >=0:
						continue
					if attacked.count(entity)>1 or attacked.back() == entity:continue
					target = entity
					on_hit()
					transfer-=1
					found_new = true
					i=6
					break
		if not found_new:
			queue_free()
			return
		transferring = false
func on_hit():
	# 手雷（孙尚香2/鲁班1）：落地专属爆炸表现
	if has_meta("grenade_kind"):
		var gcol: Color = get_meta("grenade_col")
		Vfx.grenade_impact(global_position, gcol, str(get_meta("grenade_kind")))
	# —— 命中特效：按「进攻方 × 受击方」分层（英雄/小兵/攻城车/防御塔/野怪）——
	# 英雄打英雄的火花由 GameEntity._damage_feedback 统一出，这里不再叠加，避免双重火花
	var _src_kind := "hero"
	if source is Turret:
		_src_kind = "turret"
	elif source is Minion:
		_src_kind = "siege" if source.display_name in ["siege", "dragon", "storm", "shadow_dragon", "super"] else "minion"
	elif source is JungleMonster:
		_src_kind = "monster"
	var _tgt_kind := "hero"
	if target is Turret:
		_tgt_kind = "crystal" if target.display_name == "crystal" else "tower"
	elif target is Minion:
		_tgt_kind = "minion"
	elif target is JungleMonster:
		_tgt_kind = "monster"
	if not (source is Hero and target is Hero) and (target != null or _src_kind != "hero"):
		var _ic1: Color = Vfx.color_for_hero(source.display_name) if source is Hero else Vfx.team_color(team)
		var _ic2: Color = Vfx.color2_for_hero(source.display_name) if source is Hero else Color(1.0, 0.95, 0.85)
		if _src_kind == "monster":
			_ic1 = Color(0.82, 0.66, 0.36)
			_ic2 = Color(1.0, 0.9, 0.65)
		var _isf := 1.0
		if _src_kind == "turret":
			_isf = 1.4
		elif _src_kind == "siege":
			_isf = 1.15
		elif _src_kind == "minion":
			_isf = 0.75
		Vfx.hit_impact(global_position, _aim_dir() if target != null else Vector3.UP, _ic1, _ic2, _isf, _tgt_kind, _src_kind, is_crit)
	if target:
		if target is Turret and skill_id >0:
			if source.display_name == "刘禅":
				# 被动：技能对防御塔等量伤害+干扰+回血
				target.take_damage(damage, source, is_magic, skill_id, pen_percent)
				if stun_dur > 0 or knock_dur > 0:
					target.interfere_timer = max(target.interfere_timer, 1.2)
				source._apply_healing(225+15*source.level+0.045*source.bonus_health)
				if slow_dur > 0: target.apply_move_pct_buff("ms_slow", slow_dur, -slow_per, true)
				check_transfer()
				return
			pass
		else:
			if source.display_name == "刘禅" and skill_id>0 and skill_id <3:
				if target is Hero:
					damage += target.actual_max_health * 0.1
				else:
					damage += source.actual_max_health * 0.1
			if not attacked.is_empty() and (attacked.count(target)>1 or attacked.back()== target):return
			attacked.append(target)
			# 小乔1技能：每命中一个目标伤害衰减20%（最低50%）
			if source.display_name == "小乔" and skill_id == 1:
				xiaoqiao_q_hits += 1
				damage *= max(0.5, 1.0 - xiaoqiao_q_hits * 0.2)
			# 安琪拉2技能：首次命中晕眩+持续
			if angela_w and not angela_w_hit:
				angela_w_hit = true
				target.stun_timer = max(target.stun_timer, 1.0)
				target.take_damage(damage, source, is_magic, skill_id, pen_percent)
				return
			
			if source.display_name == "孙尚香":
				# Check if target has skill 2 mark (5s duration)
				var has_mark = false
				for m in target.markers:
					if m.get("type") == "sunshangxiang_w" and m.get("source") == source:
						has_mark = true
						m.timer = 5.0  # Refresh duration
						break
				if has_mark:
					damage += 96+24*source.skill_levels[1]+int(0.36*source.bonus_attack)
					if target is Minion or target is JungleMonster:
						damage += 96+24*source.skill_levels[1]+int(0.36*source.bonus_attack)
			if source.display_name == "吕布":
				if source.stat >= 1:
					if  skill_id>0:
						if skill_id == 2:
							var _lv = source.skill_levels[1]
							var _bhp = source.actual_max_health - source.max_health
							source.shield_remaining += int(280 + 70*_lv + 0.07*_bhp)
							source.shield_remaining = min(source.shield_remaining, 3*int(280 + 70*_lv + 0.07*_bhp))
							
						else:
							pen_percent = 1
							source.stat = 1
							source.stat_timer = 8.0
							if skill_id == 1:
								var _lv2 = source.skill_levels[0]
								var _bhp2 = source.actual_max_health - source.max_health
								source._apply_healing(int(104 + 26*_lv2 + 0.025*_bhp2)) 
							else:
								var _lv3 = source.skill_levels[2]
								var _bhp3 = source.actual_max_health - source.max_health
								source._apply_healing(int(65 + 65*_lv3 + 0.025*_bhp3)) 
					else:

						pen_percent = 1
						var _bhp4 = source.actual_max_health - source.max_health
						source._apply_healing( int(65 + 0.0125*_bhp4))
				else:	
					pen_percent+=0.35
					
			target.take_damage(damage, source, is_magic,skill_id, pen_percent, 1 if is_crit else 0)   # 普攻暴击判定随子弹传入 take_damage
			# 技能视作普攻：本发命中视作一次普攻 → 触发普攻类装备特效（只对首段目标一次，穿刺后续不重复）
			if counts_as_aa and not aa_proc_done and is_instance_valid(source) and source is Hero and source.health > 0.0:
				aa_proc_done = true
				source.proc_aa_item_effects(target)
			# 元流之子·万物为流：贯穿强普逐目标追加 80+20%额外AD（0.7^已命中数衰减；负id避免再吃普攻判定）
			if yuanliu_strong and source and source is Hero and source.display_name == "元流之子":
				var _yl_extra = int(yuanliu_strong_extra * pow(0.7, yuanliu_hits))
				if _yl_extra > 0:
					target.take_damage(_yl_extra, source, false, -90, 0, 0)
				yuanliu_hits += 1
			# 夏侯惇被动回血（技能命中）
			if source and source is Hero and source.display_name == "夏侯惇" and source.xiahou_passive_active and skill_id > 0:
				var xh_heal = 220 + source.bonus_health * 0.06
				source._apply_healing(xh_heal)
			if luban_w_missing_hp_pct > 0 and target and source:
				var missing_hp_dmg = (target.max_health - target.health) * luban_w_missing_hp_pct
				if missing_hp_dmg > 0:
					target.take_damage(missing_hp_dmg, source, true, 2, 0)
			# Apply skill 2 mark to primary target (5s duration)
			if source.display_name == "孙尚香" and skill_id == 2:
				target.markers.append({"timer": 5.0, "source": source, "type": "sunshangxiang_w"})
			if lanling_mark and source:
				target.lanling_hited = false
				target.markers.append({"timer": 3.0, "source": source, "lanling_mark_dmg": lanling_mark_dmg})
			# 太乙W: 命中后位移
			if source.display_name == "太乙真人" and skill_id == 2:
				source.global_position = target.global_position 
			# 夏侯惇R：拉拽英雄至弹着点
			if xiahou_r_dash and source and is_instance_valid(source):
				source.global_position = Vector3(global_position.x, 0.5, global_position.z)
				# 夏侯惇R第二段：延迟0.5秒落点AoE伤害
				if source and source is Hero and source.display_name == "夏侯惇" and source.skill_levels.size() > 2:
					var r2_level = source.skill_levels[2]
					var r2_dmg = 400 + (r2_level - 1) * 200 + source.bonus_health * 0.1
					var _src = source
					var _pos = source.global_position
					var _dmg = int(r2_dmg)
					var _tree = get_tree()
					_tree.create_timer(0.5).timeout.connect(
						func():
							if is_instance_valid(_src) and _src.health > 0:
								for _ent in _src.get_tree().get_nodes_in_group("entities"):
									if _ent != _src and _ent.health > 0 and _ent.team != _src.team:
										if _pos.distance_to(_ent.global_position) <= 3.0:
											_ent.take_damage(_dmg, _src, false, 3, 0)
					)
			# 后羿R：距离缩放眩晕1-3秒（仅主目标，AoE不眩晕）
			if houyi_r and houyi_r_origin != Vector3.ZERO:
				var dist_traveled = houyi_r_origin.distance_to(global_position)
				var r_stun = clamp(1.0 + dist_traveled / 50.0 * 2.0, 1.0, 3.0)
				target.stun_timer = r_stun
				if source is Hero:
					source.cc_duration_dealt += r_stun
			# 后羿R命中爆炸：扩散冲击波+火焰爆发
			if is_houyi_ult:
				# #43 网络 FX：后羿R 命中爆炸（一次性闪光，橙色与阵营无关 → team=-1）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_HOUYI_EXPLODE, Vector3(global_position.x, 0.0, global_position.z), -1, 2.0, 0.5)
				var exp_ring = MeshFactory.create_torus_ring(0.3, 1.0, Color(1.0, 0.5, 0.0), false, 0.5, true)
				exp_ring.position = global_position + Vector3.UP * 0.5
				exp_ring.rotation.x = deg_to_rad(90)
				get_parent().add_child(exp_ring)
				var er_tw = get_tree().create_tween()
				er_tw.tween_property(exp_ring, "scale", Vector3(1.5, 1.5, 1.5), 0.4)
				er_tw.parallel().tween_property(exp_ring.material_override, "albedo_color:a", 0.0, 0.4)
				er_tw.tween_callback(exp_ring.queue_free)
				var exp_glow = MeshFactory.create_sphere(1.0, Color(1.0, 0.6, 0.0, 0.7), true, 0.4)
				exp_glow.position = global_position + Vector3.UP * 0.5
				get_parent().add_child(exp_glow)
				var eg_tw = get_tree().create_tween()
				eg_tw.tween_property(exp_glow, "scale", Vector3(1.2, 1.2, 1.2), 0.3)
				eg_tw.parallel().tween_property(exp_glow.material_override, "albedo_color:a", 0.0, 0.3)
				eg_tw.tween_callback(exp_glow.queue_free)
				for _j in range(16):
					var spark = MeshFactory.create_sphere(0.12, Color(1.0, 0.4, 0.0, 0.9), true, 0.2)
					var s_angle = _j * PI * 2 / 16.0
					var s_elev = randf_range(-0.3, 0.6)
					spark.position = global_position + Vector3(cos(s_angle) * 0.3, 0.5 + s_elev, sin(s_angle) * 0.3)
					get_parent().add_child(spark)
					var st = get_tree().create_tween()
					st.tween_property(spark, "position", spark.position + Vector3(cos(s_angle) * 1.5, 1.0, sin(s_angle) * 1.5), 0.5)
					st.parallel().tween_property(spark, "scale", Vector3(0.03, 0.03, 0.03), 0.5)
					st.parallel().tween_property(spark.material_override, "albedo_color:a", 0.0, 0.5)
					st.tween_callback(spark.queue_free)
			
			if slow_dur > 0: target.apply_move_pct_buff("ms_slow", slow_dur, -slow_per, true)
			target._apply_df_buff(armor_drop_flat,armor_drop_per,drop_dur,false)
			target._apply_df_buff(magic_resist_drop_flat,magic_resist_drop_per,drop_dur,true)
			if knock_dur !=0:
				target.knockup_timer=knock_dur
				if source is Hero:
						source.cc_duration_dealt += knock_dur
			if target is Hero:
				
				if stun_dur !=0:
					target.stun_timer=stun_dur
				if source is Hero:
						source.cc_duration_dealt += stun_dur
			if repel and not (target is Turret):
				target.global_position += (target.global_position - global_position).normalized()*2.5
			if luban_w_knockback and source and not (target is Turret):
				var dist_to_source = source.global_position.distance_to(target.global_position)
				if dist_to_source <= 4.0:
					target.global_position += (target.global_position - source.global_position).normalized() * 4.0
			if fire_damage:
				
				target.take_damage(fire_damage, source, is_magic,-2, 1)
			if source.display_name == "甄姬" and skill_id == 3:
				source.skillapply.bpos = target.global_position 
				source.skillapply.bpos_valid = true
			if source.display_name == "马超" and skill_id == 1 :
				if target.health<=0:
					pierce = true
					damage*=1.5
				else:
					pierce = false
					source.skillapply.bpos = target.global_position
					source.skillapply.bpos_valid = true
					
	if damage_range>0 and transfer ==0:
		
		var all_entities = get_tree().get_nodes_in_group("entities")
		for entity in all_entities:
			if entity == target:continue
			if entity == source or not is_instance_valid(entity): continue
			if entity.team == team: continue
			if entity in attacked: continue
			# 鲁班W的溅射同样只命中英雄
			if not _luban_w_can_hit(entity): continue
			var dist = global_position.distance_to(entity.global_position) - radius - entity.body_radius
			if dist <= damage_range:
				if entity is Turret and skill_id >=0:
					continue
				if source.display_name == "吕布":
					if  skill_id>0:
						if skill_id == 2:
							var _lv = source.skill_levels[1]
							var _bhp = source.actual_max_health - source.max_health
							source.shield_remaining += int(280 + 70*_lv + 0.07*_bhp)
							source.shield_remaining = min(source.shield_remaining, 3*int(280 + 70*_lv + 0.07*_bhp))
							source._apply_healing(0.125*source.shield_remaining)
							source.shield_remaining*=0.75
						else:
							pen_percent = 1
							source.stat = 1
							source.stat_timer = 8.0
							if skill_id == 1:
								var _lv2 = source.skill_levels[0]
								var _bhp2 = source.actual_max_health - source.max_health
								source._apply_healing(int(104 + 26*_lv2 + 0.025*_bhp2))
							else:
								var _lv3 = source.skill_levels[2]
								var _bhp3 = source.actual_max_health - source.max_health
								source._apply_healing(int(65 + 65*_lv3 + 0.025*_bhp3))
					else:
						if source.stat >= 1:
							pen_percent = 1
							var _bhp4 = source.actual_max_health - source.max_health
							source._apply_healing(int(65 + 0.0125*_bhp4))
						else:	
							pen_percent+=0.35
						
				entity.take_damage(damage*aoe_mult, source, is_magic,skill_id, pen_percent, 1 if is_crit else 0)   # 溅射暴击判定随子弹传入 take_damage
				# 夏侯惇被动回血（技能AoE命中）
				if source and source is Hero and source.display_name == "夏侯惇" and source.xiahou_passive_active and skill_id > 0:
					var xh_aoe_heal = 220 + source.bonus_health * 0.06
					source._apply_healing(xh_aoe_heal)
				if luban_w_missing_hp_pct > 0 and entity and source:
					var aoe_missing_hp_dmg = (entity.max_health - entity.health) * luban_w_missing_hp_pct
					if aoe_missing_hp_dmg > 0:
						entity.take_damage(aoe_missing_hp_dmg, source, true, 2, 0)
				if slow_dur > 0: entity.apply_move_pct_buff("ms_slow", slow_dur, -slow_per, true)
				if source.display_name == "孙尚香" and skill_id == 2:
					# Mark AoE targets with skill 2 mark (5s)
					entity.markers.append({"timer": 5.0, "source": source, "type": "sunshangxiang_w"})
				if repel and not (entity is Turret):
					entity.global_position += (entity.global_position - global_position).normalized()*2.5
				if luban_w_knockback and source and not (entity is Turret):
					var aoe_dist_to_source = source.global_position.distance_to(entity.global_position)
					if aoe_dist_to_source <= 4.0:
						entity.global_position += (entity.global_position - source.global_position).normalized() * 4.0
				if entity is Hero:
					if stun_dur !=0:
						entity.stun_timer=stun_dur
					if source is Hero:
						source.cc_duration_dealt += stun_dur
						if source is Hero:
								source.cc_duration_dealt += stun_dur
				if source is Hero:
						source.cc_duration_dealt += knock_dur
				if knock_dur !=0:
					entity.knockup_timer=knock_dur
				if source is Hero:
						source.cc_duration_dealt += knock_dur
				entity._apply_df_buff(armor_drop_flat,armor_drop_per,drop_dur,false)
				entity._apply_df_buff(magic_resist_drop_flat,magic_resist_drop_per,drop_dur,-2)
	if target:
		source.current_target = target
	if source.display_name == "铠" and (skill_id == 2 or skill_id == 0):
		if attacked.size() == 1:
			for tar in attacked:
				tar.take_damage(damage*0.5, source, is_magic,-1, pen_percent)	
	check_transfer()	
	

# 递归设置节点树的阴影投射模式（model.instantiate() 返回 Node3D，需递归处理子网格）
func _recursive_set_shadow(node: Node, mode: int):
	if node is GeometryInstance3D:
		node.cast_shadow = mode
	for child in node.get_children():
		_recursive_set_shadow(child, mode)
