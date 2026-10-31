class_name Tripod
extends GameEntity

## 大禹戍鼎：治疗就绪度用水面高度表达（不再画鼎外范围圈）；
## 治疗时鼎内水化为水流飞向英雄，鼎内水随之见底，再按冷却回涨；血条为单面片着色器绘制。

const WATER_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 water_col : source_color = vec4(0.20, 0.80, 0.85, 0.95);
uniform vec4 foam_col : source_color = vec4(0.72, 1.0, 1.0, 1.0);
uniform float fill = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float d = length(p);
	if (d > 1.0) {
		discard;
	}
	// 边缘泡沫亮圈
	float edge = smoothstep(0.70, 0.96, d) * (1.0 - smoothstep(0.96, 1.0, d));
	// 涟漪：低频同心波 + 高频细波
	float r1 = sin(d * 20.0 - TIME * 2.6 + fill * 2.0) * 0.5 + 0.5;
	float r2 = sin(d * 39.0 + TIME * 1.4) * 0.5 + 0.5;
	float ripple = mix(r1, r2, 0.35);
	vec3 col = mix(water_col.rgb * 0.60, water_col.rgb * 1.35, ripple * 0.7);
	col = mix(col, foam_col.rgb, edge * (0.40 + 0.35 * ripple));
	col += foam_col.rgb * (1.0 - smoothstep(0.0, 0.32, d)) * 0.10;
	ALBEDO = col;
	ALPHA = clamp(water_col.a * (0.55 + 0.45 * fill), 0.0, 1.0);
}
"""

var tripod_owner: Hero = null
var heal_cooldown: float = 20.0
var heal_cooldown_timer: float = 0.0
var heal_ready: bool = true
var q_level: int = 1
var heal_amount: float = 300.0
var is_r_tripod: bool = false           # 大招乾鼎（更大、不可攻击、8秒自毁）
var auto_destroy_timer: float = 8.0     # R鼎自毁倒计时

var pot_model: Node3D = null
var pot_scale: float = 3.0
var water: MeshInstance3D = null        # 鼎内水面：高度 = 治疗就绪度（冷却中水面低、就绪时满到鼎口）
var water_mat: ShaderMaterial = null
var water_fill: float = 1.0

var _t: float = 0.0

static var _water_shader: Shader = null


func _ready():
	add_to_group("tripods")
	add_to_group("entities")   # 可被选敌/普攻/射线选中
	body_radius = 1.6
	collision_layer = 1
	collision_mask = 0
	_create_visual()
	# CharacterBody3D 需要碰撞体才能被射线检测到
	var body_col = CollisionShape3D.new()
	body_col.shape = SphereShape3D.new()
	body_col.shape.radius = 2.5
	add_child(body_col)


func _create_visual():
	# 加载pot模型（戍鼎 6× = 原 3× 的 2 倍）
	var pot_scene = load("res://model/pot/pot.glb")
	pot_scale = 6.0
	if pot_scene:
		pot_model = pot_scene.instantiate()
		pot_model.scale = Vector3(pot_scale, pot_scale, pot_scale)
		add_child(pot_model)
	_build_water()


func _build_water():
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER_CODE
	water_mat = ShaderMaterial.new()
	water_mat.shader = _water_shader
	water = MeshInstance3D.new()
	water.name = "WaterSurface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	water.mesh = plane
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(water)
	_layout_water()


func _layout_water():
	if water == null:
		return
	var shrink := lerpf(0.70, 1.0, clampf(water_fill, 0.0, 1.0))
	water.scale = Vector3(0.125 * pot_scale * shrink, 1.0, 0.105 * pot_scale * shrink)
	water.position = Vector3(0, _water_y(), 0)


## 世界血条锚点：鼎口上方（HUD 用与小兵一致的世界血条绘制）
func bar_anchor_height() -> float:
	return 0.249 * pot_scale + 0.55


func _water_y() -> float:
	# 鼎高 0.252×缩放：水面从鼎底 0.03 到近鼎口 0.20（单位×pot_scale）
	return lerpf(0.03 * pot_scale, 0.20 * pot_scale, clampf(water_fill, 0.0, 1.0))


func setup_tripod(p_team: int, p_owner: Hero, p_q_level: int, bonus_hp: float, is_r: bool = false):
	team = p_team
	tripod_owner = p_owner
	q_level = p_q_level
	is_r_tripod = is_r
	if is_r:
		# 大招鼎：更大、无血条、不可攻击、8秒自毁（乾鼎 10× = 原 5× 的 2 倍）
		auto_destroy_timer = 8.0
		pot_scale = 10.0
		if pot_model:
			pot_model.scale = Vector3(pot_scale, pot_scale, pot_scale)
		water_fill = 1.0
		_layout_water()
		# 移除碰撞体（不可被选中/攻击）
		for child in get_children():
			if child is CollisionShape3D:
				child.queue_free()
		# 无需血量
		max_health = 1
		health = 1
	else:
		heal_amount = 300.0 + (q_level - 1) * 60.0 + bonus_hp * 0.06
		max_health = p_owner.actual_max_health * 0.15
		health = max_health


func _process(delta):
	_t += delta
	# 大招鼎自毁倒计时
	if is_r_tripod:
		auto_destroy_timer -= delta
		if water:
			water.position.y = _water_y() + sin(_t * 1.8) * 0.012 * pot_scale
		if auto_destroy_timer <= 0:
			if tripod_owner and is_instance_valid(tripod_owner):
				tripod_owner.dayu_tripods.erase(self)
			queue_free()
			return
		return  # R鼎不执行治疗逻辑

	# 水面高度 = 治疗就绪度：掉落（刚治疗）快速见底，冷却中缓慢回涨
	var target_fill: float = 1.0 if heal_ready else 1.0 - clampf(heal_cooldown_timer / maxf(heal_cooldown, 0.001), 0.0, 1.0)
	var rate: float = 3.2 if target_fill < water_fill else 1.8
	water_fill = lerpf(water_fill, target_fill, clampf(delta * rate, 0.0, 1.0))
	if water:
		water.position.y = _water_y() + sin(_t * 2.2) * 0.010 * pot_scale
		var shrink := lerpf(0.70, 1.0, clampf(water_fill, 0.0, 1.0))
		water.scale = Vector3(0.125 * pot_scale * shrink, 1.0, 0.105 * pot_scale * shrink)
	if water_mat:
		water_mat.set_shader_parameter("fill", water_fill)

	if not heal_ready:
		heal_cooldown_timer -= delta
		if heal_cooldown_timer <= 0:
			heal_ready = true

	# 治疗逻辑：每0.5秒检查范围内残血友方英雄
	if heal_ready:
		if not has_meta("heal_tick"):
			set_meta("heal_tick", 0.0)
		var tick_accum: float = get_meta("heal_tick") + delta
		if tick_accum >= 0.5:
			set_meta("heal_tick", 0.0)
			_heal_nearby_allies()
		else:
			set_meta("heal_tick", tick_accum)


func _heal_nearby_allies():
	if not heal_ready:
		return
	for hero in get_tree().get_nodes_in_group("heroes"):
		if hero is Hero and hero.team == team and hero.health > 0:
			if hero.health < hero.actual_max_health * 1:
				var dist = global_position.distance_to(hero.global_position)
				if dist <= 5.0:
					hero.apply_regen(heal_amount, 0, 1.0, "dayu_tripod")
					heal_ready = false
					heal_cooldown_timer = heal_cooldown
					_play_heal_flow(hero)
					return


## 治疗动画：鼎口的水化作一串水珠，沿抛物线飞向英雄，鼎内水同步见底
func _play_heal_flow(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := global_position + Vector3(0, _water_y() + 0.05, 0)
	var to: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var root := Node3D.new()
	root.name = "HealFlow"
	add_child(root)
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.55, 0.95, 1.0, 0.92)
	drop_mat.emission_enabled = true
	drop_mat.emission = Color(0.35, 0.88, 0.98)
	drop_mat.emission_energy_multiplier = 2.0
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mid: Vector3 = (from + to) * 0.5 + Vector3(0, maxf(1.2, pot_scale * 0.5), 0)
	var drops := 14
	for i in range(drops):
		var drop := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07 + 0.03 * randf()
		sm.height = sm.radius * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		drop.mesh = sm
		drop.material_override = drop_mat
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(drop)
		var delay := 0.35 * float(i) / float(drops)
		var dur := 0.55 + 0.20 * float(i) / float(drops)
		var a := from
		var b := mid
		var c := to
		var tw := drop.create_tween()
		tw.tween_interval(delay)
		tw.tween_method(func(k: float) -> void:
			drop.global_position = _quad_bezier(a, b, c, k)
			drop.scale = Vector3.ONE * (1.2 - 0.55 * k)
		, 0.0, 1.0, dur)
		tw.tween_callback(drop.queue_free)
	# 落点水花
	Vfx.hit_spark(to, Color(0.55, 0.95, 1.0), Vector3.UP, 1.1)
	var clean := create_tween()
	clean.tween_interval(1.15)
	clean.tween_callback(root.queue_free)


func _quad_bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var q := 1.0 - t
	return a * q * q + b * 2.0 * q * t + c * t * t


func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false, skill_id: int = -1, pen_percent: float = 0.0, is_crit_forced: int = -1):
	if is_r_tripod:
		return  # 大招鼎不可被攻击
	health -= amount
	if health <= 0:
		if tripod_owner and is_instance_valid(tripod_owner):
			tripod_owner.dayu_tripods.erase(self)
		_clear_attackers()
		queue_free()


## 鼎被拆掉时清掉英雄的锁定目标，避免引用已释放对象
func _clear_attackers() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		if h is Hero:
			if h.manual_target == self:
				h.manual_target = null
			if h.current_target == self:
				h.current_target = null
