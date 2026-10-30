class_name Minion
extends GameEntity

const NetModels = preload("res://scripts/net/NetModels.gd")   # 兵线体型归一化常量（与客户端共用）
const MinionModelScript = preload("res://scripts/entities/MinionModel.gd")

var waypoints: Array = []
var waypoint_index: int = 0
var line: int = 0
var auto_search_timer: float = 0.0
var minion_type: String = "melee"
var visual: Node3D = null   # 模型实例（攻城车等无骨骼动画的兵种靠程序化后坐表现攻击）
var _proc_visual: bool = false
var _death_anim_started: bool = false

func _ready():
	add_to_group("minions")
	
	_create_visual()
	collision_layer = 1
	collision_mask = 1
	can_move = true
	vision_range = 8.0
	#print(line)

func _create_visual():
	# 已确认的兵种用程序化甲士模型；龙形先锋仍走旧 GLB（待确认后切 is_applied）
	if MinionModelScript.is_applied(display_name):
		var instance: Node3D = MinionModelScript.build(display_name, team)
		add_child(instance)
		visual = instance
		_proc_visual = true
		var strength := float(instance.get_meta("tint_strength", 0.30))
		UnitVisuals.tint_team(instance, team, strength)
		WalkFeel.attach(self, instance, _walk_opts())
	else:
		# 根据兵种加载对应模型
		var model_map = {
			"melee":  "res://model/melee/soldier.glb",
			"ranged": "res://model/range/archer.glb",
			"siege":  "res://model/seige/cannon-mobile.glb",
			"super":  "res://model/super/character-orc.glb",
			"dragon": "res://model/dragon/DragonBaby.glb",
			"storm": "res://model/dragon/DragonBaby.glb",
			"shadow_dragon": "res://model/dragon/DragonBaby.glb",
		}
		var path = model_map.get(display_name, "")
		if path != "":
			var model = load(path)
			if model:
				var instance = model.instantiate()
				# 体型归一化：缩放由「目标高度/原始高度」算出，与客户端同一套常量
				var sc: float = NetModels.minion_scale(display_name)
				instance.scale = Vector3(sc, sc, sc)
				add_child(instance)
				visual = instance
				# 队伍色染模型（继承模型材质的贴图/明暗，只做色相偏移）
				UnitVisuals.tint_team(instance, team)
				# 行走质感：小兵步频起伏 + 轻微摆动（去尘量小、限频）
				WalkFeel.attach(self, instance, _walk_opts())
				anim_player = _find_anim_player(instance)
				if anim_player:
					_play_anim("idle")
	if not has_node("CollisionShape3D"):
		var col = CollisionShape3D.new()
		col.shape = SphereShape3D.new()
		# 暗影先锋视觉模型1.5倍缩放，碰撞半径同步放大
		col.shape.radius = body_radius * 1.5 if display_name == "shadow_dragon" else body_radius
		add_child(col)


func get_hit_flash_root() -> Node3D:
	return visual if visual != null and is_instance_valid(visual) else self

# 行走质感按体型调整：龙兵步幅更大、起伏更明显
func _walk_opts() -> Dictionary:
	if display_name in ["dragon", "storm", "shadow_dragon"]:
		return {"stride": 1.7, "bob": 0.055, "sway": 0.028, "lean": 0.03, "dust": false}
	if display_name == "siege":
		return {"stride": 1.3, "bob": 0.022, "sway": 0.03, "lean": 0.02, "dust_size": 0.16}
	# 甲士：双腿绕髋关节前后摆 + 步频起伏，避免“贴地滑行”
	var swing := 0.52 if display_name == "super" else 0.62
	return {"stride": 1.06, "bob": 0.045, "sway": 0.032, "lean": 0.06, "dust_size": 0.18,
		"legs": [visual.get_node_or_null("ModelPivot/LegL"), visual.get_node_or_null("ModelPivot/LegR")],
		"leg_swing": swing}


# 无骨骼模型的普攻前刺（有 AnimationPlayer 的兵种仍用原动画）
func _model_lunge() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var pivot: Node3D = visual.get_node_or_null("ModelPivot")
	if pivot == null:
		return
	var base := pivot.position
	var tw := create_tween()
	tw.tween_property(pivot, "position:z", base.z + 0.16, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", -0.10, 0.10)
	tw.tween_interval(0.03)
	tw.tween_property(pivot, "position:z", base.z, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(pivot, "rotation:x", 0.0, 0.20)


# 无骨骼模型死亡：停掉行走起伏，侧倒/坠地
func _proc_death() -> void:
	if not _proc_visual or visual == null or not is_instance_valid(visual) or _death_anim_started:
		return
	_death_anim_started = true
	var walker := get_node_or_null("WalkFeel")
	if walker:
		walker.set_process(false)
	var base := visual.position
	var tw := create_tween()
	tw.set_parallel(true)
	if display_name in ["dragon", "storm", "shadow_dragon"]:
		tw.tween_property(visual, "rotation:x", 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "position:y", base.y - 0.55, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		var dir := 1.0 if (get_instance_id() % 2 == 0) else -1.0
		tw.tween_property(visual, "rotation:z", dir * 1.35, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(visual, "position:y", base.y - 0.12, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# 为特定兵种映射动画名称（主宰先锋使用 DragonBaby 模型的动画名）
func _play_anim(anim_name: String):
	# 联机：小兵攻击动作推给客户端（非 HOST 由 net_action 直接忽略；
	# 「附近有己方英雄」的闸门在 NetSession.push_net_action 里，不会刷远端小兵战）
	if anim_name == "attack-melee-left":
		NetSession.net_action(self, 0)
	if display_name in ["dragon", "storm", "shadow_dragon"]:
		match anim_name:
			"idle": super._play_anim("CharacterArmature|Flying_Idle")
			"walk": super._play_anim("CharacterArmature|Flying_Idle")
			"attack-melee-left": super._play_anim("CharacterArmature|Punch")
			"die": super._play_anim("CharacterArmature|Death")
			_: super._play_anim(anim_name)
	else:
		super._play_anim(anim_name)

# 攻城车开炮后坐：模型沿本地 -Z 后坐再回位 + 炮口闪光（该模型没有 AnimationPlayer）
func _siege_recoil() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var recoil_node: Node3D = visual.get_node_or_null("ModelPivot")
	var dist := 0.45
	if recoil_node != null:
		dist = 0.20
	else:
		recoil_node = visual
	var base := recoil_node.position
	var tw := create_tween()
	tw.tween_property(recoil_node, "position:z", base.z - dist, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(recoil_node, "position:z", base.z, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	Vfx.cast_glow(global_position + Vector3.UP * 0.8 + fwd * 0.7, Color(1.0, 0.72, 0.35), 0.5, 0.18)

func _physics_process(delta):
	if health <= 0: return
	# 攻击冷却
	if attack_timer > 0:
		attack_timer -= delta
	if froze_timer>0:return
	# 每0.5秒搜索敌人
	auto_search_timer -= delta
	if current_target:
		
		var dist = global_position.distance_to(current_target.global_position) 
		if current_target.health <=0 or dist > vision_range:
			current_target = null
	if auto_search_timer <= 0 and not current_target:
		auto_search_timer = 0.5
		_find_target()

	# 如果有目标且在视野内，追击或攻击
	if current_target and is_instance_valid(current_target) and current_target.health > 0:
		var dist = global_position.distance_to(current_target.global_position) 
		if dist <= attack_range*0.01:
			# 进入攻击范围：始终面向目标（近战/远程/攻城车一致，不再只朝移动方向）
			var to_t: Vector3 = current_target.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(to_t.x, to_t.z), clampf(delta * 10.0, 0.0, 1.0))
			# 攻击范围内 → 攻击，停止移动
			if attack_timer <= 0:
				if attack_range*0.01 > 1.0:
					var bullet = Bullet.new()
					bullet.speed = 10.0
					bullet.damage = attack
					if display_name in ["dragon", "storm"]:
						bullet.damage_range = 2.0
						bullet.scale = Vector3(3.0, 3.0, 3.0)
					elif display_name == "shadow_dragon":
						bullet.damage_range = 2.5
						bullet.scale = Vector3(3.5, 3.5, 3.5)
					bullet.team = team
					bullet.target = current_target
					bullet.source = self
					bullet.global_position = global_position + Vector3(0, 0.5, 0)
					get_parent().add_child(bullet)
				else:
					var tp := current_target.global_position   # 先取坐标：这一击可能击杀目标，之后 current_target 变 null
					rotation.y = atan2((tp - global_position).normalized().x, (tp - global_position).normalized().z)
					var _mtgt := current_target
					current_target.take_damage(attack, self)
					# 近战兵/超级兵命中特效（远程兵/攻城车走 Bullet.on_hit）
					var _tk := "hero"
					if _mtgt is Minion:
						_tk = "minion"
					elif _mtgt is Turret:
						_tk = "crystal" if _mtgt.display_name == "crystal" else "tower"
					elif _mtgt is JungleMonster:
						_tk = "monster"
					Vfx.hit_impact(tp + Vector3.UP * 0.6, (tp - global_position).normalized(),
						Vfx.team_color(team), Color(1.0, 0.95, 0.85), 0.6 if display_name != "super" else 0.85, _tk, "minion")
				attack_timer = 1.0 / attack_speed
				# 兵种攻击音（近战/远程/炮车/超级兵/龙兵各不同，仅本地英雄附近）
				SfxManager.try_minion_attack_sfx(display_name, global_position)
				_play_anim("attack-melee-left")
				if display_name == "siege":
					_siege_recoil()   # 攻城车模型无骨骼动画 → 程序化开炮后坐
				elif _proc_visual:
					_model_lunge()    # 程序化甲士模型无骨骼动画 → 普攻前刺
			# 停步
			return
		elif ( _is_on_lane_or_high_ground(current_target.global_position)):

			# 在视野内但攻击范围外 → 向目标移动
			var dir = (current_target.global_position - global_position).normalized()
			dir = _avoid_walls(dir, delta, current_target.global_position)
			global_position += dir * move_speed * delta*0.01
			rotation.y = atan2(dir.x, dir.z)
			_play_anim("walk")
			var half = Config.MAP_SIZE / 2.0
			
			global_position.x = clamp(global_position.x, -half, half)
			global_position.z = clamp(global_position.z, -half, half)
			return
		else:
			current_target = null
	else:
		current_target = null
		

	# 无有效目标 → 沿路点移动
	if waypoint_index < waypoints.size():
		var target_pos = waypoints[waypoint_index]
		var dir = (target_pos - global_position).normalized()
		dir = _avoid_walls(dir, delta, target_pos)
		global_position += dir * move_speed*0.01 * delta
		rotation.y = atan2(dir.x, dir.z)
		_play_anim("walk")
		if global_position.distance_to(target_pos) < 1.0:
			waypoint_index += 1
	var half = Config.MAP_SIZE / 2.0
	global_position.x = clamp(global_position.x, -half, half)
	global_position.z = clamp(global_position.z, -half, half)
	

func _find_target():
	var best: GameEntity = null
	var best_dist = vision_range
	for entity in get_tree().get_nodes_in_group("entities"):
		if entity == self or entity.health <= 0: continue
		if entity is JungleMonster:continue
		if entity.collision_layer == 0: continue  # 隐身不可锁定
		if entity is Hero and entity.hidden_in_bush: continue
		if entity is Hero and entity.wd_timer>0:continue
		if entity is Hero and (entity as Hero).is_invisible_to_enemy(): continue  # 兰陵王隐身(保留碰撞)但不可锁定
		if entity is Hero and not _is_on_lane_or_high_ground(entity.global_position): continue
		if entity.team == team: continue
		var dist = global_position.distance_to(entity.global_position) 
		if dist < best_dist:
			best_dist = dist
			best = entity
	current_target = best

func _is_on_lane_or_high_ground(pos: Vector3) -> bool:
	# 轴对齐分路平面
	if pos.x >= -63 and pos.x <= -47 and pos.z >= -40 and pos.z <= 40: return true
	if pos.x >= 47 and pos.x <= 63 and pos.z >= -40 and pos.z <= 40: return true
	if pos.x >= -40 and pos.x <= 40 and pos.z >= 47 and pos.z <= 63: return true
	if pos.x >= -40 and pos.x <= 40 and pos.z >= -63 and pos.z <= -47: return true
	# 中路（旋转-45度）— 将点反向旋转+45度后再判断
	var mid_centers = [Vector3(-30, 0, 30), Vector3(30, 0, -30)]
	for mc in mid_centers:
		var local = pos - mc
		var angle = deg_to_rad(45)
		var rx = local.x * cos(angle) - local.z * sin(angle)
		var rz = local.x * sin(angle) + local.z * cos(angle)
		if rx >= -40 and rx <= 40 and rz >= -8 and rz <= 8: return true
	# 高地扇形（以地图顶点为圆心）
	var high_centers = [Vector3(-60, 0, 60), Vector3(60, 0, -60)]
	var high_radius = 35.0
	for hc in high_centers:
		var dx = pos.x - hc.x; var dz = pos.z - hc.z
		if dx * dx + dz * dz > high_radius * high_radius: continue
		var ang = rad_to_deg(atan2(dz, dx))
		if hc.x < 0:
			if ang >= -90 and ang <= 0: return true
		else:
			if ang >= 90 and ang <= 180: return true
	# 河道（对角线 z = -x，宽度 ~20，|x+z| ≤ 15）abs(wx - wz) / sqrt(2.0)
	if abs(pos.x - pos.z) <= 15.0:
		return true
	return false

func take_damage(amount: float, source: GameEntity = null, is_magic: bool = false,skill_id:int=0,pen: float = 0.0, is_crit_forced: int = -1):
	if source:
		if source is Minion:
			amount*= 1.25
			if source.display_name == "super" or source.display_name == "siege":
				amount *= 1.2
			if source.display_name == "dragon":
				amount *= 1.6
		super.take_damage(amount, source, is_magic,skill_id,pen, is_crit_forced) 

func die(killer):
	# 主宰先锋/风暴先锋/暗影先锋被击杀：本地玩家附近才响（敌我音色不同）
	if not is_dead and display_name in ["dragon", "storm", "shadow_dragon"]:
		SfxManager.try_vanguard_down_sfx(team, global_position)
	if not is_dead:
		_proc_death()
	super.die(killer)
