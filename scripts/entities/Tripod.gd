class_name Tripod
extends GameEntity

var tripod_owner: Hero = null
var heal_cooldown: float = 20.0
var heal_cooldown_timer: float = 0.0
var heal_ready: bool = true
var q_level: int = 1
var heal_amount: float = 300.0
var is_r_tripod: bool = false           # 大招乾鼎（更大、不可攻击、8秒自毁）
var auto_destroy_timer: float = 8.0     # R鼎自毁倒计时
var r_range_preview: MeshInstance3D = null  # R鼎范围预览圈

var pot_model: Node3D = null
var green_disc: MeshInstance3D = null
var hp_bar_bg: MeshInstance3D = null
var hp_bar_fg: MeshInstance3D = null

func _ready():
	add_to_group("tripods")
	body_radius = 1.0
	collision_layer = 1
	collision_mask = 0
	_create_visual()
	# CharacterBody3D 需要碰撞体才能被射线检测到
	var body_col = CollisionShape3D.new()
	body_col.shape = SphereShape3D.new()
	body_col.shape.radius = 2.5
	add_child(body_col)

func _create_visual():
	# 加载pot模型
	var pot_scene = load("res://model/pot/pot.glb")
	if pot_scene:
		pot_model = pot_scene.instantiate()
		pot_model.scale = Vector3(3.0, 3.0, 3.0)
		add_child(pot_model)

	# 绿色圆片 — 治疗冷却好时显示
	green_disc = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.height = 0.05
	green_disc.mesh = cyl
	green_disc.position = Vector3(0, 0.02, 0)
	var green_mat = StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.4, 1.0, 0.5, 0.6)  # 浅绿色
	green_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green_disc.material_override = green_mat
	green_disc.visible = true
	add_child(green_disc)

	# 血条背景（红色）
	hp_bar_bg = MeshInstance3D.new()
	var bg_box = BoxMesh.new()
	bg_box.size = Vector3(2.0, 0.2, 0.1)
	hp_bar_bg.mesh = bg_box
	hp_bar_bg.position = Vector3(0, 3.5, 0)
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.6, 0.1, 0.1)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar_bg.material_override = bg_mat
	add_child(hp_bar_bg)

	# 血条前景（绿色）
	hp_bar_fg = MeshInstance3D.new()
	var fg_box = BoxMesh.new()
	fg_box.size = Vector3(2.0, 0.2, 0.15)
	hp_bar_fg.mesh = fg_box
	hp_bar_fg.position = Vector3(0, 3.5, 0.05)
	var fg_mat = StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.2, 0.8, 0.2)
	fg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_bar_fg.material_override = fg_mat
	add_child(hp_bar_fg)

func setup_tripod(p_team: int, p_owner: Hero, p_q_level: int, bonus_hp: float, is_r: bool = false):
	team = p_team
	tripod_owner = p_owner
	q_level = p_q_level
	is_r_tripod = is_r
	if is_r:
		# 大招鼎：更大、无血条、不可攻击、8秒自毁、范围预览
		auto_destroy_timer = 8.0
		# 放大模型
		if pot_model:
			pot_model.scale = Vector3(5.0, 5.0, 5.0)
		# 放大绿盘
		if green_disc:
			green_disc.scale = Vector3(1.8, 1.8, 1.8)
			green_disc.visible = true
		# 隐藏血条（不可被攻击）
		if hp_bar_bg:
			hp_bar_bg.visible = false
		if hp_bar_fg:
			hp_bar_fg.visible = false
		# 移除碰撞体（不可被选中/攻击）
		for child in get_children():
			if child is CollisionShape3D:
				child.queue_free()
		# 添加R范围预览圈（4.0半径）
		r_range_preview = MeshInstance3D.new()
		var r_ring = TorusMesh.new()
		r_ring.inner_radius = 3.85
		r_ring.outer_radius = 4.15
		r_range_preview.mesh = r_ring
		r_range_preview.position = Vector3(0, 0.1, 0)
		r_range_preview.rotation.x = deg_to_rad(90)
		var r_ring_mat = StandardMaterial3D.new()
		r_ring_mat.albedo_color = Color(0.3, 0.9, 0.5, 0.5)
		r_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_range_preview.material_override = r_ring_mat
		add_child(r_range_preview)
		# 无需血量
		max_health = 1
		health = 1
	else:
		heal_amount = 300.0 + (q_level - 1) * 60.0 + bonus_hp * 0.06
		max_health = p_owner.actual_max_health * 0.15
		health = max_health

func _process(delta):
	# 大招鼎自毁倒计时
	if is_r_tripod:
		auto_destroy_timer -= delta
		if auto_destroy_timer <= 0:
			if tripod_owner and is_instance_valid(tripod_owner):
				tripod_owner.dayu_tripods.erase(self)
			queue_free()
			return
		return  # R鼎不执行治疗逻辑
	# 更新血条
	if hp_bar_fg and max_health > 0:
		var hp_pct = clamp(health / max_health, 0.0, 1.0)
		hp_bar_fg.scale.x = hp_pct
		hp_bar_fg.position.x = -(1.0 - hp_pct) * 1.0  # 左对齐收缩

	if not heal_ready:
		heal_cooldown_timer -= delta
		if heal_cooldown_timer <= 0:
			heal_ready = true
			if green_disc:
				green_disc.visible = true

	# 治疗逻辑：每0.5秒检查范围内残血友方英雄
	if heal_ready:
		var tick_accum = 0.0
		if not has_meta("heal_tick"):
			set_meta("heal_tick", 0.0)
		tick_accum = get_meta("heal_tick") + delta
		if tick_accum >= 0.5:
			set_meta("heal_tick", 0.0)
			_heal_nearby_allies()
		else:
			set_meta("heal_tick", tick_accum)
func _heal_nearby_allies():
	if not heal_ready: return
	for hero in get_tree().get_nodes_in_group("heroes"):
		if hero is Hero and hero.team == team and hero.health > 0:
			if hero.health < hero.actual_max_health * 1:
				var dist = global_position.distance_to(hero.global_position)
				if dist <= 5.0:
					hero.apply_regen(heal_amount, 0, 1.0, "dayu_tripod")
					heal_ready = false
					heal_cooldown_timer = heal_cooldown
					if green_disc:
						green_disc.visible = false
					return

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false, skill_id: int = -1, pen_percent: float = 0.0, is_crit_forced: int = -1):
	if is_r_tripod: return  # 大招鼎不可被攻击
	health -= amount
	if health <= 0:
		if tripod_owner and is_instance_valid(tripod_owner):
			tripod_owner.dayu_tripods.erase(self)
		queue_free()
