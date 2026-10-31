class_name HeroPassive
extends Node
# 英雄被动组件 — 管理每个英雄的每帧被动效果
# 作为 Hero 的子节点附加，通过 hero 引用访问英雄状态变量

var hero: Hero

func _ready() -> void:
	if get_parent() is Hero:
		hero = get_parent() as Hero

# 从 Hero._physics_process 提取的英雄每帧被动处理
func process_passive(delta: float) -> void:
	if not hero: return

	# 吕布：被动计时器
	if hero.display_name == "吕布":
		if hero.shield_remaining:
			hero._apply_healing(0.125*hero.shield_remaining)
			hero.shield_remaining*=0.75
		if hero.stat_timer > 0:
			hero.stat_timer -= delta
			if hero.stat_timer <= 0:
				hero.stat = 0
		elif hero.stat != 0:
			hero.stat_timer = 8.0

	# 狄仁杰：被动层数衰减
	if hero.display_name == "狄仁杰":
		if hero.stat_timer > 0:
			hero.stat_timer -= delta
			if hero.stat_timer <= 0:
				var _d_had := hero.stat > 0
				hero.stat = max(0, hero.stat - 1); hero.stat_timer = 0.5
				if _d_had:
					hero._recalculate_attributes()   # 掉层 → 同步叠层被动 buff

	# 沈梦溪：炸弹充能
	if hero.display_name == "沈梦溪":
		if hero.stat_timer >= 0:
			hero.stat_timer -= delta
			if hero.stat_timer < 0: hero.stat = min(10, hero.stat + 1); hero.stat_timer = 4.16 - hero.skill_levels[0] * 0.16
		# 疾跑强化计时：4.5秒后失效（否则stat2永久为1，1技能一直走强化分支）
		if hero.stat2_timer > 0:
			hero.stat2_timer -= delta
			if hero.stat2_timer <= 0:
				hero.stat2 = 0
		# 沈梦溪W引燃窗口到期：自然引爆（窗口由 Hero 冷却递减归零，与按钮青色扇形同口径）
		if hero.shen_fuse_active and hero.skill_window_timers.size() > 1 and hero.skill_window_timers[1] <= 0.0:
			_shen_w_explode()
		# 刘禅Q：强化普攻定时器
	if hero.liushan_q_active:
		hero.liushan_q_timer -= delta
		if hero.liushan_q_timer <= 0: hero.liushan_q_active = false

	# 亚瑟：被动回复 + Q强化 + W圣盾旋转
	if hero.display_name == "亚瑟":
		hero._arthur_heal_tick -= delta
		if hero._arthur_heal_tick <= 0:
			hero._arthur_heal_tick = 2.0
			var heal_amt = 93 + 7 * hero.level + hero.bonus_health * 0.025
			if hero.slow_amount > 0: heal_amt *= 2.0
			hero._apply_healing(heal_amt)
		if hero.arthur_q_active:
			hero.arthur_q_timer -= delta
			if hero.arthur_q_timer <= 0: hero.arthur_q_active = false
		if hero.arthur_w_active:
			hero.arthur_w_angle += delta * PI * 2 / 3.0
			while hero.arthur_w_shields.size() < 3:
				# 圣盾：核心+外壳+双光环+粒子+点光的分层球体（原来是单个纯金色球）
				var sm: Node3D = Vfx.make_orb(Color(0.98, 0.86, 0.36), 0.52, "holy")
				hero.get_parent().add_child(sm)
				hero.arthur_w_shields.append(sm)
			for _i in range(3):
				var ang_w2 = hero.arthur_w_angle + _i * PI * 2 / 3.0
				var shield_pos2 = hero.global_position + Vector3(cos(ang_w2) * 3.5, 1.0, sin(ang_w2) * 3.5)
				if _i < hero.arthur_w_shields.size() and is_instance_valid(hero.arthur_w_shields[_i]):
					hero.arthur_w_shields[_i].position = shield_pos2
					Vfx.spin_orb(hero.arthur_w_shields[_i], hero.arthur_w_angle * 3.0 + float(_i))
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if shield_pos2.distance_to(ent.global_position) <= 2.0:
							var ek = "arthur_" + str(ent.get_instance_id())
							var lh = hero.arthur_w_hit_cd.get(ek, 0.0)
							var nw = Time.get_ticks_msec() / 1000.0
							if nw - lh > 0.5:
								hero.arthur_w_hit_cd[ek] = nw
								var wb = 127 + hero.skill_levels[1] * 18
								var wd2 = wb + hero.actual_attack_damage * 0.8
								ent.take_damage(wd2, hero, false, 2, 0)
			hero.arthur_w_timer -= delta
			if hero.arthur_w_timer <= 0:
				hero.arthur_w_active = false
				while hero.arthur_w_shields.size() > 0:
					var old_s3 = hero.arthur_w_shields.pop_back()
					if is_instance_valid(old_s3): old_s3.queue_free()

	# 东皇太一：能量体旋转碰撞
	if hero.display_name == "东皇太一" and hero.donghuang_orbs > 0:
		var orb_speed = (PI * 2 / 3.0) * (1.0 + hero.donghuang_speed_boost)
		hero.donghuang_orb_angle += delta * orb_speed
		while hero.donghuang_orb_meshes.size() < hero.donghuang_orbs:
			# 能量球：暗紫分层球体（核心+外壳+双光环+粒子+点光），替掉原来的纯色球
			var om: Node3D = Vfx.make_orb(Color(0.62, 0.32, 1.0), 0.62, "void")
			hero.get_parent().add_child(om)
			hero.donghuang_orb_meshes.append(om)
		while hero.donghuang_orb_meshes.size() > hero.donghuang_orbs:
			var old_m2 = hero.donghuang_orb_meshes.pop_back()
			if is_instance_valid(old_m2): old_m2.queue_free()
		for _j in range(min(hero.donghuang_orbs, hero.donghuang_orb_meshes.size())):
			var ang = hero.donghuang_orb_angle + _j * PI * 2 / max(hero.donghuang_orbs, 1)
			var orb_pos = hero.global_position + Vector3(cos(ang) * 2.5, 1.0, sin(ang) * 2.5)
			if _j < hero.donghuang_orb_meshes.size() and is_instance_valid(hero.donghuang_orb_meshes[_j]):
				hero.donghuang_orb_meshes[_j].position = orb_pos
				Vfx.spin_orb(hero.donghuang_orb_meshes[_j], hero.donghuang_orb_angle * 2.5 + float(_j) * 1.7)
			for ent in hero.get_tree().get_nodes_in_group("entities"):
				if ent != hero and ent.health > 0 and ent.team != hero.team:
					if orb_pos.distance_to(ent.global_position) <= 1.5:
						var ek2 = str(ent.get_instance_id())
						var lh2 = hero.donghuang_orb_hit_cd.get(ek2, 0.0)
						var nw2 = Time.get_ticks_msec() / 1000.0
						if nw2 - lh2 > 0.5:
							hero.donghuang_orb_hit_cd[ek2] = nw2
							var od = 100 + hero.actual_ability_power * 0.5 + ent.max_health * 0.03
							ent.take_damage(od, hero, true, -45, 0)
							var hp = 0.03 if ent is Hero else 0.01
							hero._apply_healing(80 + hero.skill_levels[0] * 20 + hero.actual_ability_power * 0.4 + hero.actual_max_health * hp)
	if hero.display_name == "马超":
			if hero.stat_timer >0:
				hero.stat_timer -= delta
	# 东皇太一R：压制结束检测
	if hero.donghuang_suppress_target and (not is_instance_valid(hero.donghuang_suppress_target) or hero.suppress_timer <= 0):
		hero.donghuang_suppress_target = null; hero.donghuang_speed_boost = 0.0
		# 铠被动：非战斗状态回复
	if hero.display_name == "铠":
		if hero.kai_combat_timer > 0:
			hero.kai_combat_timer -= delta
		else:
			hero._apply_healing(hero.actual_max_health * 0.01 * delta)
			hero.mana = min(hero.mana + hero.actual_mana_max * 0.01 * delta, hero.actual_mana_max)
	if hero.display_name == "不知火舞":
			if hero.stat_timer < 5:
				hero.stat_timer += delta
	# 王昭君：脱战护盾（脱战5秒→获盾，破盾后3秒冷却，每3秒最多回一次）
	if hero.display_name == "王昭君":
		if hero.wangzhaojun_combat_timer > 0:
			hero.wangzhaojun_combat_timer -= delta
		
			
		elif hero.shield_remaining <= 0:
			var shield_lv = 1 if hero.level < 8 else 2
			var shield_val = (450 * shield_lv) + hero.actual_ability_power * 0.58
			hero.shield_remaining = shield_val
			hero.wangzhaojun_shield_was_active = true

	# 李白：剑气、侠客行、W计时
	if hero.display_name == "李白":
		if hero.libai_sword_timer > 0: hero.libai_sword_timer -= delta
		if hero.libai_sword_timer <= 0 and hero.libai_sword_auras > 0: hero.libai_sword_auras -= 1
		if hero.libai_xia_active:
			hero.libai_xia_timer -= delta
			if hero.libai_xia_timer <= 0:
				hero.libai_xia_active = false
				hero._recalculate_attributes()   # 侠客行结束 → 移除 +30 攻击 buff
		if hero.libai_w_active: hero.libai_w_timer -= delta
		if hero.libai_w_timer <= 0: hero.libai_w_active = false

	# 张飞：Q矛旋转、变身计时、法力同步
	if hero.display_name == "张飞":
		if hero.zhangfei_q_active:
			hero.zhangfei_q_timer -= delta; hero.zhangfei_q_elapsed += delta
			var cur_progress = hero.zhangfei_q_elapsed / 0.5
			var cur_ang = hero.zhangfei_q_angle - cur_progress * deg_to_rad(120)
			var spear_tip = hero.global_position + Vector3(cos(cur_ang) * 3, 1.0, -sin(cur_ang) * 3)
			var spear_mid = (hero.global_position + spear_tip) / 2
			if hero.zhangfei_q_mesh and is_instance_valid(hero.zhangfei_q_mesh):
				hero.zhangfei_q_mesh.position = spear_mid
				hero.zhangfei_q_mesh.look_at(spear_tip, Vector3.UP)
				hero.zhangfei_q_mesh.rotation.x -= PI / 2
			for ent in hero.get_tree().get_nodes_in_group("entities"):
				if ent != hero and ent.health > 0 and ent.team != hero.team:
					if not ent.has_meta("zhangfei_q_hit") or ent.get_meta("zhangfei_q_hit") != hero.zhangfei_q_elapsed:
						if spear_tip.distance_to(ent.global_position) <= 2.0:
							ent.take_damage(hero.zhangfei_q_dmg, hero, false, 1, 0)
							var kb = (ent.global_position - hero.global_position).normalized()
							# 防御塔免疫击退：张飞二技能扇形挥击不推塔
							if not (ent is Turret):
								ent.global_position += kb * 1.5
							ent.set_meta("zhangfei_q_hit", hero.zhangfei_q_elapsed)
			if hero.zhangfei_q_timer <= 0:
				hero.zhangfei_q_active = false
				if hero.zhangfei_q_mesh and is_instance_valid(hero.zhangfei_q_mesh):
					hero.zhangfei_q_mesh.queue_free()
					hero.zhangfei_q_mesh = null
		if hero.zhangfei_transformed:
			hero.zhangfei_transform_timer -= delta
			if hero.zhangfei_transform_timer <= 0:
				hero.zhangfei_transformed = false
				hero.clear_zhangfei_form_visual()   # 变身结束：恢复体型并移除脚下光环
		hero.mana = hero.zhangfei_mana

	# 兰陵王：隐身、解隐攻速buff
	if hero.display_name == "兰陵王":
		if hero.lanling_stealth_cd > 0: hero.lanling_stealth_cd -= delta
		if hero.lanling_stealth_active:
			hero.lanling_stealth_timer -= delta
			if hero.lanling_stealth_timer <= 0:
				hero.lanling_stealth_active = false; hero.visible = true; hero.collision_layer = 1
				hero.lanling_as_buff_timer = 5.0; hero._recalculate_attributes()  # 立即烘焙解隐攻速并移除隐身移速
		if hero.lanling_as_buff_timer > 0:
			hero.lanling_as_buff_timer -= delta
			if hero.lanling_as_buff_timer <= 0: hero._recalculate_attributes()

	# 太乙真人：Q充能自动引爆
	if hero.display_name == "太乙真人" and hero.taiyi_q_channeling:
		hero.taiyi_q_timer += delta
		if hero.taiyi_q_timer >= 5.0:
			_taiyi_q_explode()
	# 夏侯惇：噬目被动计时
	if hero.display_name == "夏侯惇":
		if hero.xiahou_passive_cd > 0:
			hero.xiahou_passive_cd -= delta
		if hero.xiahou_passive_active:
			hero.xiahou_passive_timer -= delta
			if hero.xiahou_passive_timer <= 0 :
				hero.xiahou_passive_active = false
	# 后羿：被动层数衰减 + Q强化计时
	if hero.display_name == "后羿":
		# 被动层数衰减
		if hero.stat_timer > 0:
			hero.stat_timer -= delta
			if hero.stat_timer <= 0:
				hero.stat = max(0, hero.stat - 1)
				hero.stat_timer = 0.5 if hero.stat > 0 else 0.0
				hero._recalculate_attributes()   # 掉层 → 同步叠层被动 buff
		# Q强化普攻计时
		if hero.houyi_q_timer > 0:
			hero.houyi_q_timer -= delta
			if hero.houyi_q_timer <= 0:
				hero.houyi_q_active = false
	# 大禹：W强化普攻计时
	if hero.display_name == "大禹":
		if hero.dayu_w_enhanced:
			hero.dayu_w_enhanced_timer -= delta
			if hero.dayu_w_enhanced_timer <= 0:
				hero.dayu_w_enhanced = false
				hero.dayu_w_used_enhanced = false

	# 孙悟空1技能：格挡窗口计时
	if hero.sunwukong_1_block_timer > 0:
		hero.sunwukong_1_block_timer -= delta
		if hero.sunwukong_1_block_timer <= 0:
			hero.sunwukong_1_block_active = false
# 太乙真人 Q 技能引爆
func _taiyi_q_explode() -> void:
	# 防重入：立即清除channeling状态，避免await期间每帧重复调用
	if not hero.taiyi_q_channeling:
		return
	hero.taiyi_q_channeling = false
	hero.skill_window_timers[0] = 0
	var q_dur = min(hero.taiyi_q_timer, 5.0)
	hero.taiyi_q_timer = 0.0
	var q_dmg = 105 + hero.skill_levels[0] * 4 + (32 + hero.skill_levels[0] * 1.6) * q_dur + (0.55 + 0.22 * q_dur) * hero.actual_ability_power
	var q_stun = 0.5 + (0.03 + hero.skill_levels[0] * 0.013) * q_dur
	var preview = hero.skillapply.create_preview(4.0, hero.global_position, hero.team)
	preview.visible = true; hero.get_parent().add_child(preview)
	await hero.get_tree().create_timer(0.2).timeout
	preview.queue_free()
	for ent in hero.get_tree().get_nodes_in_group("entities"):
		if ent != hero and ent.health > 0 and ent.team != hero.team:
			if hero.global_position.distance_to(ent.global_position) <= 4.0:
				ent.take_damage(q_dmg, hero, true, 1, 0)
				ent.stun_timer = q_stun
	hero.skill_cooldowns[0] = hero.skills[0].cooldown - hero.skills[0].cd_bonus * (hero.skill_levels[0] - 1)


# 沈梦溪 W 疾跑引爆（手动/自然共用）：范围法术伤害 + 击飞周围敌人 + 自身短暂浮空（与太乙Q引爆同模板）
func _shen_w_explode() -> void:
	if not hero.shen_fuse_active:
		return
	hero.shen_fuse_active = false
	if hero.skill_window_timers.size() > 1:
		hero.skill_window_timers[1] = 0.0
	if not is_instance_valid(hero) or hero.health <= 0:
		return
	var w_dmg := 360.0 + 90.0 * float(hero.skill_levels[1]) + 0.9 * hero.actual_ability_power
	var preview = hero.skillapply.create_preview(3.5, hero.global_position, hero.team)
	preview.visible = true
	hero.get_parent().add_child(preview)
	await hero.get_tree().create_timer(0.2).timeout
	if is_instance_valid(preview):
		preview.queue_free()
	if not is_instance_valid(hero) or hero.health <= 0:
		return
	for ent in hero.get_tree().get_nodes_in_group("entities"):
		if ent != hero and ent.health > 0 and ent.team != hero.team:
			if hero.global_position.distance_to(ent.global_position) <= 3.5:
				ent.take_damage(w_dmg, hero, true, 2, 0)
				ent.knockup_timer = maxf(ent.knockup_timer, 1.0)
	# 自身短暂浮空（击飞自身0.5秒）
	hero.knockup_timer = maxf(hero.knockup_timer, 0.5)
	# 冷却从引爆起算（与太乙Q引爆一致：满CD重设）
	hero.skill_cooldowns[1] = hero.skills[1].cooldown - hero.skills[1].cd_bonus * (hero.skill_levels[1] - 1)
