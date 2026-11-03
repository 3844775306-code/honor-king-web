class_name  SkillApplier
extends Node

const HeroWeapons = preload("res://scripts/core/HeroWeapons.gd")

var skills: Dictionary = {}
var bpos:Vector3 = Vector3.ZERO
var bpos_valid: bool = false
func _ready():
	_init_skills()
func apply_skills(hero:Hero,skill_id: int,pos):
	# 所有技能效果统一抬到地面以上（野区起伏/分路/高地/泉水），预览与实体落点一致
	if pos is Vector3 and pos != Vector3.ZERO:
		pos = Vfx.ground_pos(pos)
	var level = hero.skill_levels[skill_id-1]
	match hero.display_name:
		"狄仁杰":match  skill_id:
			1:for i in range (6):
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				ang = ang -deg_to_rad(50)+i*deg_to_rad(20)
				var dir = Vector3(cos(ang),0,-sin(ang))
				var as_aa := i % 3 == 0   # 每3发(方向)视作1次普攻 → 触发普攻类装备特效
				var is_blue = randf() <0.5
				var bullet = create_bullet(96,0.18,0,24*level,false,hero,dir,1)
				if as_aa:
					bullet.counts_as_aa = true
				bullet.set_linear(dir,11)
				bullet.pierce = true
				hero.get_parent().add_child(bullet)
				var bullet1 = create_bullet(80+0.25*hero.bonus_attack,0,0,20*level,true,hero,dir,1)
				if as_aa:
					bullet1.counts_as_aa = true
				bullet1.set_linear(dir,11)
				bullet1.pierce = true
				if is_blue:
					bullet1.slow_per=0.12+0.03*level
					bullet1.slow_dur=1
					bullet1.damage *=0.5
				hero.get_parent().add_child(bullet1)
			2:	
				hero._cleanse()
				hero.apply_move_pct_buff("ms_haste", 1, 0.20 + level * 0.05)
				for i in range (8):
				
				
					var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					ang = ang +i*deg_to_rad(45)
					var dir = Vector3(cos(ang),0,-sin(ang))
					var as_aa := i % 3 == 0   # 每3发(方向)视作1次普攻 → 触发普攻类装备特效
					var is_blue = randf() <0.5
					var bullet = create_bullet(96,0.18,0,24*level,false,hero,dir,2)
					if as_aa:
						bullet.counts_as_aa = true
					bullet.set_linear(dir,11)
					bullet.pierce = true
					hero.get_parent().add_child(bullet)
					var bullet1 = create_bullet(80+0.25*hero.bonus_attack,0,0,20*level,true,hero,dir,2)
					if as_aa:
						bullet1.counts_as_aa = true
					bullet1.set_linear(dir,11)
					bullet1.pierce = true
					if is_blue:
						bullet1.slow_per=0.12+0.03*level
						bullet1.slow_dur=1
						bullet1.damage *=0.5
					hero.get_parent().add_child(bullet1)
			3:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(225+1.2*hero.bonus_attack,0,0.6,75*level,false,hero,dir,3)
				bullet.stun_dur =1
				bullet.armor_drop_per=-0.5
				bullet.drop_dur = 5
				bullet.magic_resist_drop_per = -0.5
				hero.get_parent().add_child(bullet)
				var bullet1 = create_bullet(225+1.2*hero.bonus_attack,0,0.6,75*level,true,hero,dir,3)
				
				hero.get_parent().add_child(bullet1)
		"马可波罗":match  skill_id:
			1:
				hero.apply_move_pct_buff("ms_haste", 2, 0.1)
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					
				var dir = Vector3(cos(ang),0,-sin(ang))
				for i in range (4+level):
					# Every 3rd bullet counts as a normal attack (procs on-hit items)
					var bid = 0 if i%3==0 else 1
					await hero.get_tree().create_timer(0.3).timeout
					var bullet = create_bullet(76,0.24,0,19*level,false,hero,dir,bid)
					if bid == 0:
						bullet.counts_as_aa = true    # 视作一次普攻 → 命中触发普攻类装备特效
					hero.get_parent().add_child(bullet)
				
			2:
				pass
				# Passive is handled per-frame in Hero._physics_process
				# Dash is handled by skill type 4
				
			3:
				# Fire interval scales with attack speed
				var fire_interval = 0.35 / hero.attack_speed
				for i in range (9+3*level):
					# Every 3rd barrage counts as a normal attack (procs on-hit items)
					var bid = 0 if i%3==0 else 3
					await hero.get_tree().create_timer(fire_interval).timeout
					for j in range(4):
						var ang = j * deg_to_rad(90)+i*20
						var dir = Vector3(cos(ang),0,-sin(ang))
						var bullet = create_bullet(65,0.25,0,65*level,false,hero,dir,bid)
						if bid == 0:
							bullet.counts_as_aa = true    # 该轮视作一次普攻 → 命中触发普攻类装备特效
						bullet.set_linear(dir,3)
						hero.get_parent().add_child(bullet)
		"李元芳":match  skill_id:
			1:
				_lyf_q(hero, level, pos)
			2:
				_lyf_w(hero, level, pos)
			3:
				_lyf_r(hero, level, pos)
		"元流之子":match  skill_id:
			1:
				_yuanliu_q(hero, level, pos)
			2:
				_yuanliu_w(hero, level, pos)
			3:
				_yuanliu_r(hero, level, pos)
		"孙尚香":match  skill_id:
			1:
				hero.stat = 1
				hero.stat_timer = 5.0   # 强普就绪窗口：5秒内未出手则过期（Hero 逐帧递减）
				if hero._get_nearest_enemy_in_range(5.0):
					hero.apply_move_pct_buff("ms_haste", 2, 0.8)

			2:
				var preview = create_preview(3.0,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.5).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(304+int(1.2*hero.bonus_attack),0,0,76*level,false,hero,dir,2)
				bullet.damage_range=3.0
				bullet.slow_dur = 1
				bullet.slow_per = 0.9
				bullet.drop_dur =5.0
				bullet.armor_drop_per = -0.1
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				# 视觉：红莲爆弹（手雷弹体 + 自旋 + 引信 + 拖尾）+ 落点预警
				var gcol := Color(1.0, 0.36, 0.14)
				Vfx.grenade_attach(bullet, gcol, "lotus")
				Vfx.telegraph(pos, 3.0, gcol, 0.6)
				await hero.get_tree().create_timer(0.5).timeout
				preview.queue_free()
			3:
				var preview = create_preview(2.0,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.5).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(420+int(2.5*hero.bonus_attack),0,0,420*level,false,hero,dir,3)
				bullet.damage_range = 2.0
				bullet.aoe_mult = 0.75
				
				hero.get_parent().add_child(bullet)	
				await hero.get_tree().create_timer(0.5).timeout
				preview.queue_free()
		"马超":match  skill_id:
			1:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(256+1.1*hero.bonus_attack,0,0,64*level,false,hero,dir,1)
				bullet.set_linear(dir,5)
				hero.get_parent().add_child(bullet)
				bpos_valid = false
				for i in range(3):
					await hero.get_tree().create_timer(0.4).timeout
					if bpos_valid:
						break
				var gun = create_machao_spear(bpos + dir, hero.team)
				#gun.global_position.y = 1
				hero.objs.append(gun)
				gun.visible = true
				hero.get_parent().add_child(gun)
				# #43 网络 FX：马超Q 枪落地（10s 地标）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_MACHAO_SPEAR, Vector3(bpos.x + dir.x, 0.0, bpos.z + dir.z), hero.team, 1.0, 10.0)
				await hero.get_tree().create_timer(10).timeout
				if gun:
					hero.objs.erase(gun)
					gun.queue_free()
					hero.mana +=1
			2:
				var preview = create_preview(2.0,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(192+0.9*hero.bonus_attack,0,0,48*level,false,hero,dir,2)
				bullet.damage_range=2.0
				
				bullet.slow_dur = 2
				bullet.slow_per = 0.15
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.5).timeout
				preview.queue_free()
				
					
				var gun = create_machao_spear(pos, hero.team)
				hero.objs.append(gun)
				gun.visible = true
				hero.get_parent().add_child(gun)
				# #43 网络 FX：马超W 枪落地（10s 地标）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_MACHAO_SPEAR, Vector3(pos.x, 0.0, pos.z), hero.team, 1.0, 10.0)
				await hero.get_tree().create_timer(10).timeout
				if gun:
					hero.objs.erase(gun)
					gun.queue_free()
					hero.mana +=1
				
			3:
				var best_dist = 12
				var gun = null
				for guns in hero.objs:
					if not is_instance_valid(guns):
						continue
					var dist = hero.global_position.distance_to(guns.global_position)
					if dist<best_dist:
						best_dist = dist
						gun = guns as Node3D
				if gun:
					pos = gun.global_position
					hero.objs.erase(gun)
					gun.queue_free()
					hero.mana +=1
					var ang = PI+atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					
					var dir = Vector3(cos(ang),0,-sin(ang))
					
					var bullet = create_bullet(120+0.63*hero.bonus_attack,0,0,120*level,false,hero,dir,3)
					bullet.pierce = true
					bullet.damage_range = 1.2
					bullet.position = pos 
					bullet.set_goal(hero.global_position)
					hero.get_parent().add_child(bullet)	
					hero.stat_timer = min(hero.stat_timer+4.0, 8.0)
				# 马超拾枪：直接按数值 +5 移速（5秒）——固定数值型移速 buff
					hero._apply_healing((7*hero.level+94+0.02*hero.bonus_health)*0.5)
				
		"吕布":match  skill_id:
			1:
				# 方天画斩：以自身为中心，只命中面前120°扇形区域
				var preview = create_preview(3.0, hero.global_position, hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.5).timeout
				var hero_flat := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
				var aim_flat := Vector3(pos.x, 0.0, pos.z)
				var to_aim := aim_flat - hero_flat
				var fwd: Vector3
				if to_aim.length() > 0.5:
					fwd = to_aim.normalized()
					hero.rotation.y = atan2(fwd.x, fwd.z)   # 面向瞄准方向再挥砍
				else:
					fwd = Vector3(sin(hero.rotation.y), 0.0, cos(hero.rotation.y)).normalized()
				if fwd.length() < 0.01:
					fwd = Vector3.FORWARD
				var bonus_ad = hero.bonus_attack
				var q_dmg := int(600 + 2.0 * bonus_ad)
				var half_cos := cos(deg_to_rad(60.0))   # 120°扇形 = 左右各60°
				var q_radius := 3.0
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent == hero or ent.health <= 0.0 or ent.team == hero.team:
						continue
					if ent is Turret:
						continue
					var to_ent := Vector3(ent.global_position.x - hero_flat.x, 0.0, ent.global_position.z - hero_flat.z)
					var d := to_ent.length()
					if d < 0.01 or d > q_radius + float(ent.body_radius):
						continue
					if fwd.dot(to_ent / d) < half_cos:
						continue
					var pen := 0.0
					if hero.stat >= 1:
						pen = 1.0
						hero.stat = 1
						hero.stat_timer = 8.0
						var _bhp = hero.actual_max_health - hero.max_health
						hero._apply_healing(int(104 + 26 * level + 0.025 * _bhp))
					else:
						pen = 0.35
					ent.take_damage(float(q_dmg), hero, false, 1, pen)
				# 刀光：从自身向面前扇形中心扫出
				Vfx.slash_fx(hero.global_position, hero.global_position + fwd * q_radius, Color(0.85, 0.2, 0.22))
				preview.queue_free()
			2:
				var preview = create_preview(3.0,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.5).timeout
				if pos:
					var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					var dir = Vector3(cos(ang),0,-sin(ang))
					var bonus_ad = hero.bonus_attack
					var bullet = create_bullet(int(100 + 0.35*bonus_ad),0,0,20*level,false,hero,dir,2)
					bullet.damage_range=3.0
					bullet.slow_dur = 3
					bullet.slow_per = 0.12+level*0.03
					bullet.set_goal(pos)
					hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.5).timeout
				preview.queue_free()
			3:  # 魔神降世：落地斩击+法阵边缘伤害
				# 大招范围预览圈
				var r_preview = create_preview(5.0, pos, hero.team)
				r_preview.visible = true
				hero.get_parent().add_child(r_preview)
				# 地面法阵（暗影魔神法阵：柔光底盘+旋转符文环+黑刺/火星）
				var r_disc = create_spell(5.0, hero.team, "吕布", 6.0)
				r_disc.position = pos
				hero.get_parent().add_child(r_disc)
				# #43 网络 FX：吕布R 魔神法阵（联机客户端同款暗影法阵）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_SPELL, Vector3(pos.x, 0.0, pos.z), hero.team, 5.0, 6.0, "吕布")
				# 跳跃动画
				await hero.get_tree().create_timer(1.0).timeout
				hero.fly = 3
				hero.fly_timer = 0.5
				hero.global_position = pos
				# 更新法阵视觉位置
				if is_instance_valid(r_disc): r_disc.position = pos
				await hero.get_tree().create_timer(0.5).timeout
				if is_instance_valid(r_preview): r_preview.queue_free()
				# 落地双抗
				hero._apply_df_buff(75 + 75*level, 0, 5, false)
				hero._apply_df_buff(75 + 75*level, 0, 5, true)
				# 落地斩击（额外AD加成，附魔在Bullet.on_hit中触发）
				var bonus_ad = hero.bonus_attack
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(int(650 + 2.4*bonus_ad), 0, 0, 325*level, false, hero, dir, 3)
				bullet.damage_range = 5.0
				bullet.knock_dur = 1.0
				bullet.slow_dur = 2
				bullet.slow_per = 0.15 + level*0.15
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				# 法阵边缘伤害循环：5秒内检测敌人触碰边缘，每敌人只触发1次
				var r_edge_hit = {}
				var r_center = pos
				for _edge_tick in range(16):
					await hero.get_tree().create_timer(0.3).timeout
					if hero.health <= 0: break
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
						if ent is Turret: continue
						var eid = str(ent.get_instance_id())
						if r_edge_hit.has(eid): continue
						var dist = ent.global_position.distance_to(r_center)
						if dist >= 4.2 and dist <= 5.8:
							r_edge_hit[eid] = true
							var edge_dmg = int(150 + 75*level + 0.75*bonus_ad)
							ent.take_damage(edge_dmg, hero, false, -3, 0)
							ent.apply_move_pct_buff("ms_slow", 2.0, -(0.15 + level*0.15), true)
							# 边缘命中回血
							var _bhp = hero.actual_max_health - hero.max_health
							hero._apply_healing(int(65 + 65*level + 0.025*_bhp))
				# 清理法阵视觉
				if is_instance_valid(r_preview): r_preview.queue_free()
				if is_instance_valid(r_disc): r_disc.queue_free()
		"沈梦溪":match  skill_id:
			1:
				# 猫咪炸弹（按住技能轮盘连续投掷）：按下即开始、0.75秒一发、实时跟随轮盘方向；
				# 松开轮盘 / 弹药用尽 / 连发满5枚即停。AI 无轮盘，同样按 0.75 秒节奏投完。
				# 防重入：一轮连发未结束时再次施放直接忽略，避免两条协程并发 → 同一时刻多枚炸弹叠在同一目标上
				if hero.shen_barrage_active:
					return
				hero.shen_barrage_active = true
				hero.apply_flat_move_buff("shenmengxi_boost", float(min(5, hero.stat)), 48 + 12 * level)
				var shen_shots: int = mini(5, int(hero.stat))
				var shen_fired: int = 0
				var shen_preview: Node3D = null
				while shen_fired < shen_shots and hero.stat > 0.0:
					if shen_fired > 0:
						# 每0.75秒一发（AI 与玩家同一节奏，不能一帧内把整轮炸弹全砸出去）
						if not is_instance_valid(hero) or hero.health <= 0:
							break
						if not hero.is_ai and not (TouchController.get_skill_held(0) or Input.is_action_pressed("skill_0")):
							break   # 松开技能轮盘/键盘即停止连发（已发保留、剩余炸弹不消耗）
						await hero.get_tree().create_timer(0.75).timeout
						if not is_instance_valid(hero) or hero.health <= 0:
							break
						# 松开发生在等待期间：补一次判定，避免松手后仍多发一枚
						if not hero.is_ai and not (TouchController.get_skill_held(0) or Input.is_action_pressed("skill_0")):
							break
					if not is_instance_valid(hero) or hero.health <= 0:
						break
					# 每发重新跟随最新的轮盘拖动指示（按住技能键拖到哪，本发就朝哪打）
					var aim := hero.barrage_live_aim(0, pos)
					if shen_preview and is_instance_valid(shen_preview):
						shen_preview.queue_free()
					hero.stat -= 1
					shen_preview = create_preview(3.0, aim, hero.team)
					shen_preview.visible = true
					hero.get_parent().add_child(shen_preview)
					var ang = atan2((-aim.z + hero.global_position.z),(aim.x - hero.global_position.x))
					var dir = Vector3(cos(ang),0,-sin(ang))
					var bullet = create_bullet(180,0,0.45,45*level,true,hero,dir,1)
					bullet.damage_range=3.0
					if hero.stat2:
						bullet = create_bullet(100,0,0.25,25*level,true,hero,dir,2)
						bullet.damage_range=3.0   # 强化炸弹同样AOE
					bullet.set_goal(aim)
					hero.get_parent().add_child(bullet)
					shen_fired += 1
				if is_instance_valid(hero):
					hero.shen_barrage_active = false
				if is_instance_valid(hero) and is_instance_valid(shen_preview):
					await hero.get_tree().create_timer(0.7).timeout
					if is_instance_valid(shen_preview):
						shen_preview.queue_free()
			2:
				# 点燃引信：消耗1枚炸弹形成4秒引爆窗口；期间移速提升，可再次点击引爆或4秒后自然引爆
				if hero.stat >= 1.0:
					hero.stat -= 1
					hero.apply_flat_move_buff("shenmengxi_boost", 4.0, 36 + 9 * level)
					hero.shen_fuse_active = true
					hero.skill_window_timers[1] = 4.0

			3:
				var preview = create_preview(4.5,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.75).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(200,0,0.8,200*level,true,hero,dir,3)
				bullet.damage_range=4.5
				
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.25).timeout
				preview.queue_free()
				var base_pos = pos
				var base_ang = ang
				var previews = []
				for i in range(2+level):
					ang = base_ang +i*deg_to_rad(360/(2+level))
					dir = Vector3(cos(ang),0,-sin(ang))
					pos = base_pos + dir *5
					var preview2 = create_preview(2.5,pos,hero.team)
					preview2.visible = true
					hero.get_parent().add_child(preview2)
					previews.append(preview2)
				await hero.get_tree().create_timer(0.25).timeout
				for i in range(2+level):
					ang = base_ang +i*deg_to_rad(360/(2+level))
					dir = Vector3(cos(ang),0,-sin(ang))
					pos = base_pos + dir *3
					bullet = create_bullet(100,0,0.4,100*level,true,hero,dir,3)
					bullet.damage_range=2.5
					
					bullet.set_goal(pos)
					hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.75).timeout
				for preview3 in previews:
					preview3.queue_free()
		"不知火舞":match  skill_id:
			1:
				
					
					var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					
					var dir = Vector3(cos(ang),0,-sin(ang))
					
						
					var bullet = create_bullet(480,0,0.73,70*level,true,hero,dir,1)
					bullet.knock_dur = 0.75
					bullet.set_linear(dir,4)
					hero.get_parent().add_child(bullet)
					await hero.get_tree().create_timer(0.5).timeout
					hero.global_position = pos
					hero.fly = 3.0
					hero.fly_timer = 0.75
					hero.mana +=25
					

			2:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				
				var bullet = create_bullet(360,0,0.9,90*level,true,hero,dir,2)
				bullet.slow_dur =0.5
				bullet.slow_per=0.9
				bullet.drop_dur = 3
				bullet.magic_resist_drop_flat = -30-20*level
				bullet.transfer = 1
				hero.get_parent().add_child(bullet)
				

			3:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(600,0,1.1,200*level,true,hero,dir,3)
				bullet.repel = true
				bullet.pierce =true
				bullet.set_linear(dir,6)
				hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.5).timeout
				hero.global_position = pos
				
		"甄姬":match  skill_id:
			1:
				var preview = create_preview(2.5,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.75).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))	
				var bullet = create_bullet(360,0,0.85,90*level,true,hero,dir,1)
				bullet.damage_range=2.5
				bullet.knock_dur = 1
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				await hero.get_tree().create_timer(0.25).timeout
				preview.queue_free()
				if hero.global_position.distance_to(pos)<=2.5:
					hero.wd_timer = 3.0
					await hero.get_tree().create_timer(3.0).timeout
					var bullet2 = create_bullet(120,0,0.35,30*level,true,hero,dir,1)
					bullet2.damage_range=2.5
					bullet2.slow_dur = 3
					bullet2.slow_per =0.08+0.02*level
					bullet2.set_goal(pos)
					hero.get_parent().add_child(bullet2)
					bullet2 = create_bullet(120,0,0.35,30*level,true,hero,dir,1)
					bullet2.damage_range=0.5
					bullet2.set_goal(pos)
					hero.get_parent().add_child(bullet2)
				else:
					for i in range(10):
						
						var	bullet2 = create_bullet(0,0,0,0,true,hero,dir,1)
						bullet2.damage_range=3.5
						bullet2.slow_dur = 1.2
						bullet2.slow_per =0.1
						bullet2.position = pos
						bullet2.set_goal(pos)
						hero.get_parent().add_child(bullet2)
						await hero.get_tree().create_timer(1.0).timeout
					
					

			2:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(184,0,0.45,46*level,true,hero,dir,2)
				bullet.transfer = 4+floor((level-1)/2)
				# 水球外观由 BulletVisual 统一构建（SHAPE_WATER，host/client 同源）
				hero.get_parent().add_child(bullet)

			3:
				# 大招范围预览圈（仿吕布大招）
				var r_preview = create_preview(3.0, pos, hero.team)
				r_preview.visible = true
				hero.get_parent().add_child(r_preview)
				await hero.get_tree().create_timer(0.3).timeout
				r_preview.queue_free()
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				bpos_valid = false
				var bullet = create_bullet(150,0,0.65,150*level,true,hero,dir,3)
				bullet.repel =true
				# 水球外观由 BulletVisual 统一构建（SHAPE_WATER，host/client 同源）
				hero.get_parent().add_child(bullet)
				for i in range(5):
					await hero.get_tree().create_timer(0.4).timeout
					if bpos_valid:
						break
				# 创建水区域
				var water_zone = _create_water_zone(hero.get_parent(), bpos, 4.0)
				for i in range(5):
					# 脉冲波浪效果
					_create_water_pulse(hero.get_parent(), bpos, 4.0, hero)
					var bullet2 = create_bullet(75,0,0.32,75*level,true,hero,Vector3.ZERO,3)
					bullet2.damage_range=4
					bullet2.slow_dur = 1.5
					bullet2.slow_per = 0.125+0.125*level
					bullet2.position=bpos
					bullet2.set_goal(bpos)
					hero.get_parent().add_child(bullet2)
					await hero.get_tree().create_timer(1).timeout
				water_zone.queue_free()
		"铠":match  skill_id:
			1:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bonus_ad = hero.bonus_attack
				var bullet = create_bullet(int(224 + 0.85 * bonus_ad), 0, 0, 56*level, false, hero, dir, 1)
				bullet.transfer = 3
				bullet.slow_dur = 2
				bullet.slow_per = 0.15
				hero.get_parent().add_child(bullet)

			2:
				if pos:
					var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					var dir = Vector3(cos(ang),0,-sin(ang))
					var bonus_ad = hero.bonus_attack
					# 空放判定：挥砍方向(默认8m)上是否有会被这一刀砍中的敌人（防御塔不会被W命中，故排除）
					var kai_w_reach := 6.0
					var kai_w_empty := true
					var kai_w_dir = (pos - hero.global_position)
					kai_w_dir.y = 0.0
					if kai_w_dir.length_squared() < 0.09:
						kai_w_dir = Vector3(sin(hero.rotation.y), 0, cos(hero.rotation.y))
					kai_w_dir = kai_w_dir.normalized()
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent == hero or not is_instance_valid(ent) or ent.health <= 0 or ent.team == hero.team: continue
						if not (ent is Hero or ent is Minion or ent is JungleMonster): continue
						var to_ent = ent.global_position - hero.global_position
						to_ent.y = 0.0
						var along = to_ent.dot(kai_w_dir)
						if along < 0.0 or along > kai_w_reach: continue
						if (to_ent - kai_w_dir * along).length() <= 1.2 + ent.body_radius:
							kai_w_empty = false
							break
					# 空放：未砍中任何敌人时，第二段挥砍朝指定方向位移 4 米
					if kai_w_empty:
						hero.global_position += kai_w_dir * 2.5
						hero.global_position.y = 0.5
					else:
						var bullet = create_bullet(int(120 + 0.55 * bonus_ad), 0, 0, 30*level, false, hero, dir, 2)
						bullet.damage_range = 1.2
						hero.get_parent().add_child(bullet)
						await hero.get_tree().create_timer(1/hero.attack_speed/hero.attack_speed_timer).timeout

						bullet = create_bullet(int(120 + 0.55 * bonus_ad), 0, 0, 30*level, false, hero, dir, 2)
						bullet.knock_dur = 1
						hero.get_parent().add_child(bullet)
				hero.stat = 1
			3:
				# 铠大招范围圈：挂到自身节点下，持续跟随铠移动
				var preview = create_preview(3.0, hero.global_position, hero.team)
				preview.name = "KaiUltRing"
				preview.visible = true
				preview.position = Vector3(0.0, 0.02, 0.0)
				hero.add_child(preview)
				await hero.get_tree().create_timer(1).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bonus_ad = hero.bonus_attack
				var bullet = create_bullet(int(125 + 0.25 * bonus_ad), 0, 0, 125*level, true, hero, dir, 3)
				bullet.damage_range = 3.0
			
				hero.parry = 27.5+27.5*level
				hero._apply_healing(250+250*level)
				bullet.set_goal(pos)
				hero.get_parent().add_child(bullet)
				hero._apply_ak_buff(50+50*level,0,8,false)
				# 铠大招：固定数值 +50 移速（8秒）——固定数值型移速 buff
				hero.apply_flat_move_buff("kai_r_speed", 8.0, 50.0)
				await hero.get_tree().create_timer(0.5).timeout
				for i in range(16):
					await hero.get_tree().create_timer(0.5).timeout
					if hero.health <= 0: break
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if hero.global_position.distance_to(ent.global_position) <= 3.0:
								var tick_dmg = int(25 + 0.16 * bonus_ad) + 25 * level
								ent.take_damage(tick_dmg, hero, true, 3, 0)
				hero.parry = 0
				preview.queue_free()
				

		"亚瑟":match  skill_id:
			1:
				# 获得30%移速+强化普攻标记
				hero.arthur_q_active = true; hero.arthur_q_timer = 3.0
				hero.apply_move_pct_buff("ms_haste", 3.0, 0.3)
			2:
				# 召唤圣盾：3.5米半径5圈，每圈145-235+80%AD物伤
				hero.arthur_w_active = true; hero.arthur_w_timer = 5.0
			3:
				# 位移+击飞+16~24%最大生命法伤；随后落点形成圣印圈(5秒)
				
				var r_dmg = hero.max_health * (0.12 + level * 0.04)
				hero.global_position = pos
				var preview = create_preview(3.0,pos,hero.team)
				preview.visible = true
				hero.get_parent().add_child(preview)
				await hero.get_tree().create_timer(0.5).timeout
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 3.5:
							ent.knockup_timer = 0.5
							ent.take_damage(r_dmg, hero, true, 3, 0)

				preview.queue_free()
				# 圣印圈：金色圣印环+半透明地盘，持续5秒，每秒对圈内非防御塔敌人造成法术伤害
				var seal_disc = create_spell(3.5, hero.team, "亚瑟", 5.5)
				seal_disc.position = pos + Vector3(0, 0.08, 0)
				hero.get_parent().add_child(seal_disc)
				var seal_ring = MeshFactory.create_torus_ring(3.4, 3.6, Color(1.0, 0.85, 0.25), true, 0.95, true)
				seal_ring.position = pos + Vector3(0, 0.15, 0)
				hero.get_parent().add_child(seal_ring)
				# #43 网络 FX：亚瑟R 圣印伤害圈（5s 持续地面区）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_SPELL, Vector3(pos.x, 0.0, pos.z), hero.team, 3.5, 5.0, "亚瑟")
				var seal_tree = hero.get_tree()
				var seal_dmg = 130.0 + 8.0 * hero.level
				for _s in range(5):
					await seal_tree.create_timer(1.0).timeout
					if not is_instance_valid(hero) or hero.health <= 0:
						break
					for ent in seal_tree.get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team and not (ent is Turret):
							if pos.distance_to(ent.global_position) <= 3.5:
								ent.take_damage(seal_dmg, hero, true, 3, 0)
				if is_instance_valid(seal_disc): seal_disc.queue_free()
				if is_instance_valid(seal_ring): seal_ring.queue_free()
		"太乙真人":match  skill_id:
			1:
				hero.taiyi_q_channeling = true; hero.taiyi_q_timer = 0.0
				hero.apply_move_pct_buff("ms_haste", 5.0, 0.2)
				hero.shield_remaining += 250.0 + level * 50.0
				hero.shield_timer = 5.0
				hero.skill_window_timers[0] = 5.0
			2:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(400,0,0.8,50*level,true,hero,dir,2)
				bullet.stun_dur = 0.5
				hero.get_parent().add_child(bullet)
				
			3:
				var lowest_ally = null; var lowest_hp = 99999.0
				for ent in hero.get_tree().get_nodes_in_group("heroes"):
					if ent != hero and ent.team == hero.team and ent.health > 0:
						if hero.global_position.distance_to(ent.global_position) <= 8.0:
							if ent.health < lowest_hp: lowest_hp = ent.health; lowest_ally = ent
				if lowest_ally: lowest_ally.taiyi_protected = true; lowest_ally.taiyi_protect_timer = 3.0;lowest_ally.revive_hp = 850 + level * 750 + hero.actual_ability_power * 2.0
				hero.taiyi_protected = true; hero.taiyi_protect_timer = 3.0
				hero.revive_hp = 850 + level * 750 + hero.actual_ability_power * 2.0
				
		"东皇太一":match  skill_id:
			1:
				var prev_q = create_preview(3.5, hero.global_position, hero.team)
				prev_q.visible = true; hero.get_parent().add_child(prev_q)
				await hero.get_tree().create_timer(0.5).timeout; prev_q.queue_free()
				# 创建能量体 + AoE伤害
				if hero.donghuang_orbs < 3: hero.donghuang_orbs += 1
				var q_dmg = 240 + level * 15 + hero.actual_ability_power * 0.4
				var hit_any = false
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 3.5:
							ent.take_damage(q_dmg, hero, true, 1, 0); hit_any = true
				if hit_any: hero.mana = min(hero.mana + 20, hero.actual_mana_max); hero.skill_cooldowns[0] *= 0.5
				if hero.donghuang_orbs >= 3: hero._apply_healing(120 + level * 30 + hero.actual_ability_power * 0.6)
			2:
				hero.apply_move_pct_buff("ms_haste", 1.0, 0.20 + hero.donghuang_orbs * 0.10)
				# 发射全部能量体：第0发落在瞄准点，后一发的落点在前一发身后1.5米
				# （沿瞄准方向逐发向施法者回缩排成一条线）。施放前已按此规则生成等量预览圈。
				var total = hero.donghuang_orbs
				if total > 0:
					var fwd = pos - hero.global_position
					fwd.y = 0.0
					if fwd.length() < 0.5:
						fwd = Vector3(sin(hero.rotation.y), 0, cos(hero.rotation.y))
					fwd = fwd.normalized()
					for i in range(total):
						var landing = pos - fwd * (1.5 * i)
						var preview = create_preview(3.0, landing, hero.team)
						preview.visible = true
						hero.get_parent().add_child(preview)
						await hero.get_tree().create_timer(1.0).timeout
						var ang = atan2((-landing.z + hero.global_position.z),(landing.x - hero.global_position.x))
						var dir = Vector3(cos(ang),0,-sin(ang))
						var bullet = create_bullet(400,0,0.6,100*level,true,hero,dir,2)
						bullet.damage_range = 3.0
						if i == 0: bullet.slow_dur = 2.0; bullet.slow_per = 0.24 + level * 0.06
						elif i == 1: bullet.slow_dur = 2.0; bullet.slow_per = 0.9
						elif i == 2: bullet.stun_dur = 1.0
						bullet.set_goal(landing)
						hero.get_parent().add_child(bullet)
						await hero.get_tree().create_timer(0.5).timeout
						preview.queue_free()
						hero.donghuang_orbs -= 1
				while hero.donghuang_orb_meshes.size() > 0: var m2 = hero.donghuang_orb_meshes.pop_back(); if is_instance_valid(m2): m2.queue_free()
			3:
				var prev_r = create_preview(3.5, hero.global_position, hero.team)
				prev_r.visible = true; hero.get_parent().add_child(prev_r)
				await hero.get_tree().create_timer(0.3).timeout; prev_r.queue_free()
				hero.donghuang_orbs = 3
				var target = hero._get_nearest_enemy_in_range(3.5)
				if target and target is Hero:
					target.suppress_timer = 2.0; hero.suppress_timer = 2.0
					hero.donghuang_suppress_target = target
				hero.donghuang_speed_boost = 0.25 + min(hero.actual_ability_power / 50.0 * 0.05, 0.75)
		
		"李白":match  skill_id:
			1:
				# Q: 3段位移(2秒窗口)
				hero.skill_uses[0] += 1
				if hero.skill_uses[0] == 1: hero.libai_q_origin = hero.global_position
				hero.skill_window_timers[0] = 5.0
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				if hero.skill_uses[0] <= 2:
					var old_pos = hero.global_position
					hero.global_position += dir * 2.5
					var new_pos = hero.global_position
					var line_vec = new_pos - old_pos
					var qd = 305 + 45 * level + hero.bonus_attack * 1.1
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							var t = clamp((ent.global_position - old_pos).dot(line_vec) / line_vec.length_squared(), 0, 1)
							var closest = old_pos + line_vec * t
							if closest.distance_to(ent.global_position) <= 2.0:
								ent.take_damage(qd, hero, false, 1, 0)
								ent.stun_timer = 0.5
				else:
					hero.global_position = hero.libai_q_origin; hero.skill_uses[0] = 0; hero.skill_window_timers[0] = 0.0
				# 积累剑气
				hero.libai_sword_auras = min(hero.libai_sword_auras + 1, 4); hero.libai_sword_timer = 3.0
			2:
				# W: 剑阵+净化+无法选中
				hero._cleanse(); hero.wd_timer = 3.0; hero.libai_w_active = true; hero.libai_w_timer = 3.0
				var preview = create_preview(3.5, hero.global_position, hero.team)
				preview.visible = true; hero.get_parent().add_child(preview); hero.libai_w_ring = preview
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						var dist = hero.global_position.distance_to(ent.global_position)
						if dist <= 3.5:
							var wd = 160 + 40 * level + hero.bonus_attack * 0.6
							if dist >= 2.8:
								wd = 256 + 64 * level + hero.bonus_attack * 1.0
								ent.apply_move_pct_buff("ms_slow", 1.0, -0.9, true)
							ent.take_damage(wd, hero, false, 2, 0)
							ent._apply_df_buff(-(120.0 + 30.0 * level), 0.0, 3.0, false)   # 神来之笔：命中削减护甲(120+30·Lv)点·3秒（数值同图标 armred 行）
				await hero.get_tree().create_timer(3.0).timeout; preview.queue_free()
			3:
				# R: 5次穿梭(仅侠客行可用)
				if not hero.libai_xia_active: return
				hero.wd_timer = 2.5
				var targets = []
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 5.0:
							targets.append(ent)
				var hit_set = []
				for _i in range(5):
					if targets.size() > 0:
						var t = targets[_i % targets.size()]
						if not t in hit_set: hit_set.append(t)
						var rd = (155 + level * 55 + hero.bonus_attack * 0.6) * max(0.7, 1.15 - 0.15 * hit_set.size())
						if t:
							t.take_damage(rd, hero, false, 3, 0)
							hero.global_position = t.global_position + Vector3(randf_range(-2,2), 0, randf_range(-2,2))
					await hero.get_tree().create_timer(0.5).timeout
				hero.libai_xia_active = false; hero.libai_xia_timer = 0.0; hero._recalculate_attributes()
		"兰陵王":match  skill_id:
			1:
				var targets = []
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 3.0:
							targets.append(ent)
				targets.sort_custom(func(a,b): return a.health < b.health)
				var count = min(2, targets.size())
				for _k in range(count):
					var qd = 260 + 65 * level + hero.bonus_attack * 1.25
					targets[_k].take_damage(qd, hero, false, 1, 0)
					if count == 1 :
						await hero.get_tree().create_timer(0.5).timeout
						if targets[_k]:
							targets[_k].take_damage(qd, hero, false, 1, 0)
	
			2:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var bullet = create_bullet(160+0.9*hero.bonus_attack,0,0,40*level,false,hero,dir,2)
				bullet.pierce = true
				bullet.slow_dur = 1.5; bullet.slow_per = 0.9
				bullet.lanling_mark_dmg = 112 + level * 28 + (hero.actual_max_health-hero.health) * (0.12 + int(hero.bonus_attack/50)*0.01)
				bullet.lanling_mark = true
				hero.get_parent().add_child(bullet)
			3:
				hero.lanling_stealth_active = false; hero.visible = true; hero.collision_layer = 1; hero._recalculate_attributes()  # 立即移除隐身移速
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var old_pos = hero.global_position
				hero.global_position += dir * 3.5
				var rd = 350 + 350 * level + hero.bonus_attack * 2.5
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						var t2 = clamp((ent.global_position - old_pos).dot(dir) / 3.5, 0, 1)
						var closest = old_pos + dir * 3.5 * t2
						if closest.distance_to(ent.global_position) <= 2.0:
							ent.take_damage(rd, hero, false, 3, 0)
			4:
				# 秘技·隐匿: 1.5秒准备后隐身30秒
				await hero.get_tree().create_timer(1.5).timeout
				hero.lanling_stealth_active = true; hero.lanling_stealth_timer = 30.0; hero._recalculate_attributes()  # 立即烘焙隐身移速(+15%+1%/级)
				# 显隐由 Hero 每帧处理（己方透明/敌方隐藏）；collision_layer 保持原值 → 隐身仍参与碰撞、仅不可被锁定
		"张飞":match  skill_id:
			1:
				if hero.zhangfei_transformed:
					# 狂兽真身·1技能：对3米内敌人造成等量伤害并击飞0.5秒
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if hero.global_position.distance_to(ent.global_position) <= 3.0:
								ent.take_damage(464 + 116 * level + hero.bonus_attack * 1.45, hero, false, 1, 0)
								ent.knockup_timer = maxf(ent.knockup_timer, 0.5)
					hero.zhangfei_mana = min(hero.zhangfei_mana + 3, 100); hero.mana = hero.zhangfei_mana
				else:
					hero.zhangfei_q_active = true; hero.zhangfei_q_angle = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
					hero.zhangfei_q_timer = 0.5; hero.zhangfei_q_elapsed = 0.0
					hero.zhangfei_q_dmg = 464 + 116 * level + hero.bonus_attack * 1.45
					# 横扫长枪：加色发光枪身 + 枪尖锥 + 双层光带（替代灰色柱）
					hero.zhangfei_q_mesh = MeshInstance3D.new(); hero.zhangfei_q_mesh.mesh = CylinderMesh.new()
					hero.zhangfei_q_mesh.mesh.top_radius = 0.16; hero.zhangfei_q_mesh.mesh.bottom_radius = 0.16
					hero.zhangfei_q_mesh.mesh.height = 3.0
					hero.zhangfei_q_mesh.mesh.radial_segments = 12
					var qmat = StandardMaterial3D.new()
					qmat.albedo_color = Color(1.0, 0.78, 0.45)
					qmat.emission_enabled = true; qmat.emission = Color(1.0, 0.55, 0.18)
					qmat.emission_energy_multiplier = 1.8
					qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					qmat.albedo_color.a = 0.85
					qmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					hero.zhangfei_q_mesh.material_override = qmat
					# 枪尖
					var q_tip = MeshInstance3D.new()
					var q_cone = CylinderMesh.new()
					q_cone.top_radius = 0.0; q_cone.bottom_radius = 0.26; q_cone.height = 0.7
					q_cone.radial_segments = 12
					q_tip.mesh = q_cone
					q_tip.position.y = 1.85
					var q_tip_mat = StandardMaterial3D.new()
					q_tip_mat.albedo_color = Color(1.0, 0.95, 0.75)
					q_tip_mat.emission_enabled = true; q_tip_mat.emission = Color(1.0, 0.85, 0.45)
					q_tip_mat.emission_energy_multiplier = 2.6
					q_tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					q_tip_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					q_tip.material_override = q_tip_mat
					hero.zhangfei_q_mesh.add_child(q_tip)
					# 中段环绕光带
					for qi in range(2):
						var q_ring := MeshFactory.create_torus_ring(0.26, 0.34, Color(1.0, 0.8, 0.4, 0.7), true, 0.7, true)
						q_ring.position.y = -0.9 + 1.2 * float(qi)
						hero.zhangfei_q_mesh.add_child(q_ring)
					hero.get_parent().add_child(hero.zhangfei_q_mesh)
					Vfx.attach_trail(hero.zhangfei_q_mesh, Color(1.0, 0.62, 0.22), 0.26, 0.22, 8)
					Vfx.hit_spark(hero.global_position + Vector3.UP * 1.2, Color(1.0, 0.7, 0.35), Vector3.UP, 1.1)
					hero.zhangfei_mana = min(hero.zhangfei_mana + 3, 100); hero.mana = hero.zhangfei_mana
			2:
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				hero.global_position += dir * 3.0
				if hero.zhangfei_transformed:
					# 狂兽真身·2技能：落地后对2.5米内敌人造成物理伤害并击飞0.51秒
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if hero.global_position.distance_to(ent.global_position) <= 2.5:
								ent.take_damage(384 + 96 * level + hero.bonus_attack * 1.2, hero, false, 2, 0)
								ent.knockup_timer = maxf(ent.knockup_timer, 0.51)
					hero.zhangfei_mana = min(hero.zhangfei_mana + 3, 100); hero.mana = hero.zhangfei_mana
				else:
					var shield_amt = 480 + 120 * level + hero.bonus_health * 0.12
					hero.shield_remaining = max(hero.shield_remaining, shield_amt); hero.shield_timer = 5.0
					var ally_count = 0
					for ent in hero.get_tree().get_nodes_in_group("heroes"):
						if ent != hero and ent.team == hero.team and ent.health > 0:
							if hero.global_position.distance_to(ent.global_position) <= 5.0:
								ent.shield_remaining = max(ent.shield_remaining, shield_amt)
								ent.shield_timer = 5.0; ally_count += 1
					hero.zhangfei_mana = min(hero.zhangfei_mana + 3 + ally_count, 100); hero.mana = hero.zhangfei_mana
			3:
				hero.zhangfei_transformed = true; hero.zhangfei_transform_timer = 15.0
				hero.apply_zhangfei_form_visual()   # 变身：模型放大+脚下金色Buff光环
				# 变身爆发：金色天降光柱 + 地纹 + 双层冲击环 + 上升金尘（替代纯色圆柱）
				var tf_col := Color(1.0, 0.84, 0.32)
				var tf_ground := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
				Vfx.pillar(tf_ground, tf_col, 1.9, 8.5, 0.8)
				Vfx.sigil(tf_ground, tf_col, 3.4, 1.1)
				Vfx.shockwave(tf_ground, 3.6, tf_col, 0.55)
				Vfx.shockwave(tf_ground, 2.0, Color(1.0, 0.97, 0.8), 0.4)
				Vfx.nova(tf_ground, tf_col, 3.6)
				Vfx.cast_glow(hero.global_position + Vector3.UP * 1.2, tf_col, 1.7, 0.8)
				hero.wd_timer = 1.25
				var r_shield = 850 + 850 * level + hero.bonus_health * 0.35
				hero.shield_remaining = max(hero.shield_remaining, r_shield); hero.shield_timer = 15.0
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				# 咆哮冲击：三层扩散青蓝声波环沿朝向推进（替代纯色半透明长方体）
				var wz_col := Color.CORNFLOWER_BLUE.lerp(Color.WHITE, 0.25)
				for _wi in range(3):
					Vfx._delayed_ring(hero.global_position + dir * (3.0 + 5.0 * float(_wi)), 3.0, wz_col, 0.08 + 0.14 * float(_wi), 0.5)
				Vfx.dash_fx(hero.global_position, hero.global_position + dir * 16.0, wz_col, false, 16.0)
				Vfx.slash_fx(hero.global_position, hero.global_position + dir * 16.0, wz_col)
				var perp = Vector3(-dir.z, 0, dir.x)
				var hit_entities: Array = []  # 防止同一实体被多个网格点击中
				for _j in range(3):
					for _k in range(6):
						var wp = hero.global_position + dir * (_k + 1) * 1.0 + perp * (_j - 1) * 3.0
						for ent in hero.get_tree().get_nodes_in_group("entities"):
							if ent != hero and ent.health > 0 and ent.team != hero.team:
								if ent in hit_entities:
									continue
								if wp.distance_to(ent.global_position) <= 1.5:
									hit_entities.append(ent)
									var rd = 300 + 300 * level + hero.bonus_attack * 1.5
									ent.take_damage(rd, hero, false, 3, 0)
									var kb = (ent.global_position - hero.global_position).normalized()
									ent.global_position += kb * 5.0
									if _j == 0 or _j == 2 or _k == 0 or _k == 5:
										ent.stun_timer = 1.5

		# ==================== 安琪拉 ====================
		"安琪拉":match  skill_id:
			1:  # 五球汇聚：自目标点身后7米出发，相邻轨迹15°；穿过目标点后各自再沿自身方向飞3米（终点散开、各爆一点）
				var a1_center = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				for _i in range(5):
					# 起点=pos身后7米，绕竖轴背向瞄准偏转(i-2)*15°；每颗goal终点=pos沿自身来向再延3米
					var a1_ang = a1_center + PI + (_i - 2) * deg_to_rad(15)
					var a1_dir = Vector3(cos(a1_ang), 0, -sin(a1_ang))
					var a1_bullet = create_bullet(230, 0, 0.3, 40*level, true, hero, a1_dir, 1)
					a1_bullet.path_hit = true     # 沿途判伤（goal 模式默认只飞不判伤 → 五球穿身过不伤人）
					a1_bullet.radius = 1.0        # 命中判定半径（原 0.4，比通用技能弹 0.8 还小 → 容易擦身而过）
					a1_bullet.damage_range = 1.2   # 落点爆炸范围（原 0.6，贴近技能指示圈半径 1.0 的 1.2 倍）
					a1_bullet.global_position = Vector3(pos.x + a1_dir.x * 7.0, pos.y, pos.z + a1_dir.z * 7.0) + Vector3.UP * 0.8
					# 穿过目标点后再沿自身飞行方向飞3米：终点各自散开，在各自终点爆发
					a1_bullet.set_goal(pos - a1_dir * 3.0)
					hero.get_parent().add_child(a1_bullet)
			2:  # 混沌火种
				var a2_ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var a2_dir = Vector3(cos(a2_ang), 0, -sin(a2_ang))
				var a2_bullet = create_bullet(100, 0, 0.2, 25*level, true, hero, a2_dir, 2)
				a2_bullet.set_linear(a2_dir, 6)
				a2_bullet.speed = 10.0
				a2_bullet.angela_w = true
				a2_bullet.angela_w_level = level
				a2_bullet.angela_w_timer = 3.0
				a2_bullet.life_time = 10.0
				# 火焰视觉效果
				var a2_vis = MeshInstance3D.new()
				a2_vis.mesh = SphereMesh.new()
				a2_vis.mesh.radius = 1.2
				a2_vis.mesh.height = 1.0
				a2_vis.mesh.radial_segments = 10
				a2_vis.mesh.rings = 5
				var a2_mat = StandardMaterial3D.new()
				a2_mat.albedo_color = Color(1.0, 0.3, 0.0)
				a2_mat.emission_enabled = true
				a2_mat.emission = Color(1.0, 0.2, 0.0)
				a2_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				a2_vis.material_override = a2_mat
				a2_bullet.add_child(a2_vis)
				hero.get_parent().add_child(a2_bullet)
			3:  # 炽热光辉
				var a3_ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var a3_dir = Vector3(cos(a3_ang), 0, -sin(a3_ang))
				# 护盾+霸体
				var a3_shield = 400 + 450*level + hero.actual_ability_power * 0.88
				hero.shield_remaining = max(hero.shield_remaining, a3_shield)
				hero.shield_timer = 3.0
				hero.bt_timer = 3.0
				# 视觉：多层能量光束（外层柔光 + 白热内核 + 螺旋光带 + 脉动端头 + 枪口光）
				var a3_beam: Node3D = Vfx.angela_beam(hero.global_position + Vector3.UP * 1.0, a3_dir, 10.0, 1.2)
				# 每0.25秒造成伤害，持续3秒
				for _tick in range(12):
					await hero.get_tree().create_timer(0.25).timeout
					if hero.health <= 0: break
					var b_origin = hero.global_position + Vector3.UP * 1.0
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							var to_ent = ent.global_position + Vector3.UP * 1.0 - b_origin
							var proj = to_ent.dot(a3_dir)
							if proj > 0 and proj < 10.0:
								var perp = (to_ent - a3_dir * proj).length()
								if perp < 1.2:
									var a3_dmg = 110 + 40*level + hero.actual_ability_power * 0.21
									ent.take_damage(a3_dmg, hero, true, 3, 0)
					# 更新光束位置（跟随英雄移动；方向在施法时锁定）
					a3_beam.position = hero.global_position + Vector3.UP * 1.0
				Vfx.fade_out(a3_beam, 0.25)
		# ==================== 妲己 ====================
		"妲己":match  skill_id:
			1:  # 灵魂冲击波：5米宽冲击波，飞行10米
				var d1_ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var d1_dir = Vector3(cos(d1_ang), 0, -sin(d1_ang))
				var d1_bullet = create_bullet(505, 0, 1.2, 65*level, true, hero, d1_dir, 1)
				
				d1_bullet.damage_range = 2.5
				d1_bullet.pierce = true
				d1_bullet.set_linear(d1_dir,10.0)
				# 视觉：半月形波刃 + 双层拖尾（外层柔光/内层亮芯，宽度对齐 damage_range）
				hero.get_parent().add_child(d1_bullet)
				Vfx.crescent_wave(d1_bullet, d1_dir, Color(1.0, 0.42, 0.62), 5.0)
			2:  # 魅惑爱心：锁定敌人，晕眩1.5秒
				var d2_target = hero._get_nearest_enemy_in_range(7.0)
				if d2_target:
					var d2_dir = (d2_target.global_position - hero.global_position).normalized()
					var d2_bullet = create_bullet(250, 0, 0.66, 35*level, true, hero, d2_dir, 2)
					d2_bullet.target = d2_target
					d2_bullet.speed = 8.0
					d2_bullet.stun_dur = 1.5
					d2_bullet.life_time = 5.0
					# 爱心视觉
					var d2_vis = MeshInstance3D.new()
					d2_vis.mesh = SphereMesh.new()
					d2_vis.mesh.radius = 0.6
					d2_vis.mesh.height = 1.2
					d2_vis.mesh.radial_segments = 10
					d2_vis.mesh.rings = 5
					var d2_mat = StandardMaterial3D.new()
					d2_mat.albedo_color = Color(1.0, 0.2, 0.5)
					d2_mat.emission_enabled = true
					d2_mat.emission = Color(1.0, 0.1, 0.4)
					d2_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					d2_vis.material_override = d2_mat
					d2_bullet.add_child(d2_vis)
					hero.get_parent().add_child(d2_bullet)
				else:
					hero.skill_cooldowns[1] = 0  # 无目标时返还冷却
			3:  # 狐火：5团狐火，间隔0.3秒，随机攻击7米内敌人
				var d3_targets = []
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team and not (ent is Turret):
						if hero.global_position.distance_to(ent.global_position) <= 7.0:
							d3_targets.append(ent)
				for _i in range(5):
					if d3_targets.is_empty(): break
					var d3_t = d3_targets[randi() % d3_targets.size()]
					if not d3_t:continue
					var d3_dir = (d3_t.global_position - hero.global_position).normalized()
					var d3_bullet = create_bullet(245, 0, 0.75, 80*level, true, hero, d3_dir, 3)
					d3_bullet.target = d3_t
					d3_bullet.speed = 12.0
					d3_bullet.life_time = 10.0
					# 狐火视觉（紫色小球）
					var d3_vis = MeshInstance3D.new()
					d3_vis.mesh = SphereMesh.new()
					d3_vis.mesh.radius = 0.35
					d3_vis.mesh.height = 0.7
					d3_vis.mesh.radial_segments = 10
					d3_vis.mesh.rings = 5
					var d3_mat = StandardMaterial3D.new()
					d3_mat.albedo_color = Color(0.7, 0.2, 1.0)
					d3_mat.emission_enabled = true
					d3_mat.emission = Color(0.6, 0.1, 0.9)
					d3_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					d3_vis.material_override = d3_mat
					d3_bullet.add_child(d3_vis)
					hero.get_parent().add_child(d3_bullet)
					await hero.get_tree().create_timer(0.3).timeout
		# ==================== 小乔 ====================
		"小乔":match skill_id:
			1:  # 绽放之舞：回旋扇子，飞去飞回，每命中伤害衰减20%（最低50%）
				var x1_ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var x1_dir = Vector3(cos(x1_ang), 0, -sin(x1_ang))
				# 扇子飞出
				var x1_bullet = create_bullet(585, 0, 0.8, 50*level, true, hero, x1_dir, 1)
				x1_bullet.damage_range = 1.0
				x1_bullet.pierce = true
				x1_bullet.set_linear(x1_dir, 7.5)
				# 视觉：扇面由 BulletVisual 统一构建（SHAPE_FAN，host/client 同源，绕轴自转）
				hero.get_parent().add_child(x1_bullet)
				# 等待扇子飞到最远处后返回
				await hero.get_tree().create_timer(7.5 / x1_bullet.speed).timeout
				if hero.health > 0:
					var x1_endpoint = hero.global_position + x1_dir * 7.5
					var return_dir = (hero.global_position - x1_endpoint).normalized()
					var x1_return = create_bullet(585, 0, 0.8, 50*level, true, hero, return_dir, 1)
					x1_return.damage_range = 1.0
					x1_return.global_position = x1_endpoint
					x1_return.pierce = true
					x1_return.set_linear(return_dir, x1_endpoint.distance_to(hero.global_position))
					hero.get_parent().add_child(x1_return)
			2:  # 甜蜜恋风：0.7秒后直接击飞，无弹道
				# 前摇：落点风场法阵（柔光斑 + 双反向环 + 向心汇聚粒子），替代原来的纯色圆盘
				var x2_col := Color(1.0, 0.52, 0.74)
				Vfx.telegraph(pos, 2.0, x2_col, 0.7)
				await hero.get_tree().create_timer(0.7).timeout
				# 直接范围伤害+击飞（无弹道）
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if pos.distance_to(ent.global_position) <= 2.0:
							var x2_dmg = 300 + hero.actual_ability_power * 0.5 + 40 * level
							ent.take_damage(x2_dmg, hero, true, 2, 0)
							ent.knockup_timer = 1.5
							if ent is Hero:
								hero.cc_duration_dealt += 1.5
				# 视觉：粉色旋风（中央风柱 + 三层螺旋环 + 上升气流，host 与客户端同款）
				Vfx.tornado_fx(pos, x2_col)
				Vfx.nova(pos, Color(1.0, 0.62, 0.82), 2.4)
				Vfx.hit_spark(pos + Vector3.UP * 1.1, Color(1.0, 0.68, 0.86), Vector3.UP, 1.3)
				# #43 FX：粉色旋风（客户端同款 tornado）
				NetSession.push_net_fx(NetSession.FX_XQ_WHIRL, pos + Vector3(0.0, 1.5, 0.0), -1, 1.8, 1.0)
			3:  # 星华缭乱：6秒内每0.75秒降下流星，每目标最多4颗，重复命中50%伤害
				hero.apply_move_pct_buff("ms_haste", 6.0, 0.25)
				# 大招范围预览圈（7.0半径，持续6秒
				var r_preview = create_preview(7.0, hero.global_position, hero.team)
				r_preview.visible = true
				hero.get_parent().add_child(r_preview)
				var r_hit_count = {}
				for wave in range(8):
					# 更新预览圈位置跟随英雄
					if is_instance_valid(r_preview): r_preview.global_position = hero.global_position
					await hero.get_tree().create_timer(0.75).timeout
					if hero.health <= 0: break
					var x3_targets = []
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team and not (ent is Turret):
							if hero.global_position.distance_to(ent.global_position) <= 7.0:
								x3_targets.append(ent)
					if x3_targets.is_empty(): continue
					x3_targets.shuffle()
					var spawned = 0
					for x3_t in x3_targets:
						if spawned >= 2: break
						var eid = str(x3_t.get_instance_id())
						var hits = r_hit_count.get(eid, 0)
						if hits >= 4: continue
						# 落点=目标脚下，出膛点=目标正上方 → 流星垂直砸下
						var x3_ground := Vector3(x3_t.global_position.x, 0.0, x3_t.global_position.z)
						var x3_bullet = create_bullet(400, 0, 1.0, 100*level, true, hero, Vector3.DOWN, 3)
						x3_bullet.target = x3_t
						x3_bullet.set_goal(x3_ground)
						x3_bullet.drop_mode = true
						x3_bullet.speed = 22.0
						if hits > 0: x3_bullet.damage *= 0.5
						x3_bullet.life_time = 1.5
						r_hit_count[eid] = hits + 1
						spawned += 1
						# 视觉：紫色流星（发光核心 + 白金内核 + 拖尾）
						var x3_vis = MeshInstance3D.new()
						var x3_sphere := SphereMesh.new()
						x3_sphere.radius = 0.34
						x3_sphere.height = 0.68
						x3_sphere.radial_segments = 16
						x3_sphere.rings = 8
						x3_vis.mesh = x3_sphere
						var x3_mat = StandardMaterial3D.new()
						x3_mat.albedo_color = Color(0.72, 0.32, 1.0, 0.9)
						x3_mat.emission_enabled = true
						x3_mat.emission = Color(0.55, 0.18, 1.0)
						x3_mat.emission_energy_multiplier = 2.6
						x3_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						x3_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						x3_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						x3_vis.material_override = x3_mat
						x3_bullet.add_child(x3_vis)
						var x3_core = MeshInstance3D.new()
						var x3_cs := SphereMesh.new()
						x3_cs.radius = 0.15
						x3_cs.height = 0.3
						x3_cs.radial_segments = 10
						x3_cs.rings = 5
						x3_core.mesh = x3_cs
						var x3_cmat = StandardMaterial3D.new()
						x3_cmat.albedo_color = Color(1.0, 0.95, 1.0)
						x3_cmat.emission_enabled = true
						x3_cmat.emission = Color(1.0, 0.85, 1.0)
						x3_cmat.emission_energy_multiplier = 3.4
						x3_cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						x3_cmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						x3_core.material_override = x3_cmat
						x3_vis.add_child(x3_core)
						hero.get_parent().add_child(x3_bullet)
						x3_bullet.global_position = x3_ground + Vector3(randf_range(-0.3, 0.3), 9.5, randf_range(-0.3, 0.3))
						Vfx.attach_trail(x3_bullet, Color(0.62, 0.26, 1.0), 0.34, 0.3, 10, Color(1.0, 0.75, 1.0, 0.6))
				# 预览圈清理
				if is_instance_valid(r_preview): r_preview.queue_free()

		"鲁班七号":match  skill_id:
			1:
				var q_level = hero.skill_levels[0]
				var q_dir = (pos - hero.global_position).normalized()
				var q_dmg = 520 + (q_level - 1) * 104 + hero.bonus_attack * 1.5
				var q_slow = 0.25 + (q_level - 1) * 0.05
				var q_bullet = create_bullet(q_dmg, 0, 0, 0, false, hero, q_dir, 1)
				q_bullet.set_goal(pos)
				q_bullet.damage_range = 3.0
				q_bullet.slow_dur = 2.0
				q_bullet.slow_per = q_slow
				hero.get_parent().add_child(q_bullet)
				# 视觉：河豚手雷（尖刺弹体 + 自旋 + 引信 + 拖尾）+ 落点预警
				var q_gcol := Color(0.35, 0.85, 0.62)
				Vfx.grenade_attach(q_bullet, q_gcol, "puffer")
				Vfx.telegraph(pos, 3.0, q_gcol, 0.5)
				hero.luban_skill_enhanced = true
			2:
				var w_level = hero.skill_levels[1]
				var w_dir = (pos - hero.global_position).normalized()
				var w_phys_dmg = 450 + (w_level - 1) * 90 + hero.bonus_attack * 1.25
				var w_missing_pct = 0.05 + (w_level - 1) * 0.01
				var w_bullet = create_bullet(w_phys_dmg, 0, 0, 0, false, hero, w_dir, 2)
				w_bullet.set_linear(w_dir, 160.0)  # 全图射程
				w_bullet.speed = 35.0  # 极快弹速
				w_bullet.luban_w_knockback = true  # 仅击退近身目标
				w_bullet.luban_w_missing_hp_pct = w_missing_pct
				w_bullet.pierce = false
				hero.get_parent().add_child(w_bullet)
				hero.luban_skill_enhanced = true
			3:
				if hero.luban_r_active: return
				hero.luban_r_active = true
				var r_level = hero.skill_levels[2]
				var r_slow = 0.25 + (r_level - 1) * 0.125
				var r_dir = (pos - hero.global_position).normalized()
				if r_dir.length() < 0.1: r_dir = Vector3.FORWARD
				# 地面范围预览圈（持续14秒）
				var r_preview = create_preview(5.0, pos, hero.team)
				r_preview.visible = true
				hero.get_parent().add_child(r_preview)
				# 飞艇视觉模型：金属机身 + 发光舷窗 + 侧旋桨 + 探照灯锥（替代灰色纯色盒子）
				var r_airship = MeshInstance3D.new()
				var hull := BoxMesh.new()
				hull.size = Vector3(3, 0.9, 1.5)
				r_airship.mesh = hull
				var r_mat = StandardMaterial3D.new()
				r_mat.albedo_color = Color(0.62, 0.66, 0.72)
				r_mat.emission_enabled = true
				r_mat.emission = Color(0.35, 0.45, 0.6)
				r_mat.emission_energy_multiplier = 0.6
				r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				r_airship.material_override = r_mat
				r_airship.global_position = Vector3(pos.x, pos.y + 8, pos.z)
				hero.get_parent().add_child(r_airship)
				# 气囊
				var balloon = MeshInstance3D.new()
				var bs := SphereMesh.new()
				bs.radius = 0.9; bs.height = 1.5
				bs.radial_segments = 14; bs.rings = 7
				balloon.mesh = bs
				balloon.scale = Vector3(1.5, 1.0, 1.0)
				balloon.position = Vector3(0, 0.85, 0)
				var balloon_mat = StandardMaterial3D.new()
				balloon_mat.albedo_color = Color(0.85, 0.88, 0.95, 0.85)
				balloon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				balloon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				balloon_mat.emission_enabled = true
				balloon_mat.emission = Color(0.4, 0.55, 0.85)
				balloon_mat.emission_energy_multiplier = 0.5
				balloon.material_override = balloon_mat
				r_airship.add_child(balloon)
				# 两侧旋桨（持续自转）
				for _si in range(2):
					var rotor := MeshInstance3D.new()
					var rot := BoxMesh.new()
					rot.size = Vector3(0.12, 0.05, 1.1)
					rotor.mesh = rot
					var rotor_mat = StandardMaterial3D.new()
					rotor_mat.albedo_color = Color(0.9, 0.92, 1.0, 0.7)
					rotor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					rotor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					rotor_mat.emission_enabled = true
					rotor_mat.emission = Color(0.6, 0.8, 1.0)
					rotor_mat.emission_energy_multiplier = 1.2
					rotor.material_override = rotor_mat
					rotor.position = Vector3(-1.5 if _si == 0 else 1.5, 0.1, 0)
					r_airship.add_child(rotor)
					var rotor_spin := rotor.create_tween()
					rotor_spin.set_loops()
					rotor_spin.tween_property(rotor, "rotation:z", TAU, 0.35)
				# 探照灯锥（指向轰炸区域）
				var lamp := MeshInstance3D.new()
				var lamp_mesh := CylinderMesh.new()
				lamp_mesh.top_radius = 0.18; lamp_mesh.bottom_radius = 1.6; lamp_mesh.height = 8.0
				lamp_mesh.cap_top = false; lamp_mesh.cap_bottom = false
				lamp.mesh = lamp_mesh
				lamp.position = Vector3(0, -4.0, 0)
				var lamp_mat = StandardMaterial3D.new()
				lamp_mat.albedo_color = Color(1.0, 0.95, 0.7, 0.10)
				lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				lamp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				lamp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				lamp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				lamp_mat.emission_enabled = true
				lamp_mat.emission = Color(1.0, 0.92, 0.6)
				lamp_mat.emission_energy_multiplier = 1.4
				lamp.material_override = lamp_mat
				r_airship.add_child(lamp)
				Vfx.attach_trail(r_airship, Color(0.6, 0.8, 1.0), 0.4, 0.5, 10)
				var r_center = pos  # 轰炸区域中心，随飞艇缓慢移动
				for _r_i in range(14):
					await hero.get_tree().create_timer(1.0).timeout
					r_center += r_dir * 1.0  # 缓慢沿释放方向移动
					r_airship.global_position = Vector3(r_center.x, r_airship.global_position.y, r_center.z)
					r_preview.position = Vector3(r_center.x, r_preview.position.y, r_center.z)
					var r_bomb_dmg = 520 + (r_level - 1) * 260 + hero.bonus_attack * 1.5
					var r_candidates: Array = []
					for r_ent in hero.get_tree().get_nodes_in_group("entities"):
						if r_ent != hero and r_ent.health > 0 and r_ent.team != hero.team and not  r_ent is Turret:
							if r_center.distance_to(r_ent.global_position) <= 5.0:
								r_candidates.append(r_ent)
					if r_candidates.size() > 0:
						var r_target = r_candidates[randi() % r_candidates.size()]
						r_target.take_damage(r_bomb_dmg, hero, false, 3, 0)
						r_target.apply_move_pct_buff("ms_slow", 1.0, -r_slow, true)
				r_airship.queue_free()
				r_preview.queue_free()
				hero.luban_r_active = false


		"夏侯惇":match  skill_id:
			1:
				var q_level = hero.skill_levels[0]
				var q_dir = (pos - hero.global_position).normalized()
				if q_dir.length() < 0.1: q_dir = Vector3.FORWARD
				if hero.skill_window_timers[0] > 0:
					# 第二段：地面重击+群体击飞
					hero.skill_window_timers[0] = 0
					var q2_dmg = 400 + (q_level - 1) * 80 + hero.bonus_attack * 1.3
					var q2_preview = create_preview(3.0, pos, hero.team)
					q2_preview.visible = true; hero.get_parent().add_child(q2_preview)
					await hero.get_tree().create_timer(0.2).timeout
					q2_preview.queue_free()
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if pos.distance_to(ent.global_position) <= 3.0:
								ent.take_damage(q2_dmg, hero, false, 1, 0)
								ent.knockup_timer = 1.0
								if hero.xiahou_passive_active:
									var q2_heal = 220 + hero.bonus_health * 0.06
									hero._apply_healing(q2_heal)
				else:
					# 第一段：发射刃风+减速
					var q_dmg = 400 + (q_level - 1) * 80 + hero.bonus_attack * 1.3
					var q_slow = 0.25 + (q_level - 1) * 0.05
					var q1_preview = create_preview(2.0, pos, hero.team)
					q1_preview.visible = true; hero.get_parent().add_child(q1_preview)
					await hero.get_tree().create_timer(0.15).timeout
					q1_preview.queue_free()
					var q_bullet = create_bullet(q_dmg, 0, 0, 0, false, hero, q_dir, 1)
					q_bullet.set_linear(q_dir, 8.0)
					q_bullet.slow_dur = 2.0
					q_bullet.slow_per = q_slow
					hero.get_parent().add_child(q_bullet)
					hero.skill_window_timers[0] = 3.0
			2:
				var w_level = hero.skill_levels[1]
				var w_dmg = 300 + (w_level - 1) * 60 + hero.bonus_attack * 1.0
				var w_preview = create_preview(3.5, hero.global_position, hero.team)
				w_preview.visible = true; hero.get_parent().add_child(w_preview)
				await hero.get_tree().create_timer(0.15).timeout
				w_preview.queue_free()
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 3.5:
							ent.take_damage(w_dmg, hero, true, 2, 0)
							if hero.xiahou_passive_active:
								var w_heal = 220 + hero.bonus_health * 0.06
								hero._apply_healing(w_heal)
				var w_shield = 500 + (w_level - 1) * 100 + hero.bonus_health * 0.12
				hero.shield_remaining = max(hero.shield_remaining, w_shield)
				hero.shield_timer = 5.0
				hero.xiahou_enhanced_attacks = 3
			3:
				var r_level = hero.skill_levels[2]
				var r_dir = (pos - hero.global_position).normalized()
				if r_dir.length() < 0.1: r_dir = Vector3.FORWARD
				var r_max_dist = min(hero.global_position.distance_to(pos), 8.0)
				var r_dmg = 400 + (r_level - 1) * 200 + hero.bonus_health * 0.1
				var r_bullet = create_bullet(int(r_dmg), 0, 0, 0, false, hero, r_dir, 3)
				r_bullet.set_linear(r_dir, r_max_dist)
				r_bullet.speed = 25.0
				r_bullet.stun_dur = 1.0
				r_bullet.xiahou_r_dash = true
				r_bullet.damage_range = 2.0
				hero.get_parent().add_child(r_bullet)
		"后羿":match  skill_id:
			1:
				hero.houyi_q_active = true
				hero.houyi_q_timer = 4.0
			2:
				var w_level = hero.skill_levels[1]
				var w_dmg = 480 + (w_level - 1) * 96 + hero.bonus_attack * 1.1
				var w_slow = 0.25 + (w_level - 1) * 0.05
				var w_preview = create_preview(2.5, pos, hero.team)
				w_preview.visible = true; hero.get_parent().add_child(w_preview)
				await hero.get_tree().create_timer(0.3).timeout
				w_preview.queue_free()
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						var dist = pos.distance_to(ent.global_position)
						if dist <= 2.5:
							var edge_factor = 1.0 if dist <= 1.5 else 0.5
							ent.take_damage(int(w_dmg * edge_factor), hero, true, 2, 0)
							ent.apply_move_pct_buff("ms_slow", 2.0, -(w_slow * edge_factor), true)
			3:
				var r_level = hero.skill_levels[2]
				var r_dir = (pos - hero.global_position).normalized()
				if r_dir.length() < 0.1: r_dir = Vector3.FORWARD
				var r_dmg = 800 + (r_level - 1) * 400 + hero.bonus_attack * 1.5
				var r_speed_boost = 0.1 + (r_level - 1) * 0.05
				var r_slow_pct = 0.3 + (r_level - 1) * 0.15
				hero.apply_move_pct_buff("ms_haste", 5.0, r_speed_boost)
				var r_bullet = create_bullet(int(r_dmg), 0, 0, 0, false, hero, r_dir, 3)
				r_bullet.set_linear(r_dir, 160.0)
				r_bullet.speed = 20.0
				r_bullet.houyi_r = true
				r_bullet.houyi_r_origin = hero.global_position
				r_bullet.damage_range = 3.0
				r_bullet.slow_dur = 1.0
				r_bullet.slow_per = r_slow_pct
				r_bullet.is_houyi_ult = true
				# 后羿R发射特效：扩散金环+火焰粒子
				var launch_ring = MeshFactory.create_torus_ring(0.3, 1.5, Color(1.0, 0.55, 0.0), false, 0.4, true)
				launch_ring.position = hero.global_position + Vector3.UP * 1.0
				launch_ring.rotation.x = deg_to_rad(90)
				hero.get_parent().add_child(launch_ring)
				var lr_tw = hero.create_tween()
				lr_tw.tween_property(launch_ring, "scale", Vector3(3.0, 3.0, 3.0), 0.5)
				lr_tw.parallel().tween_property(launch_ring.material_override, "albedo_color:a", 0.0, 0.5)
				lr_tw.tween_callback(launch_ring.queue_free)
				# #43 网络 FX：后羿R 起手扩散金环（0.5s 一次性闪光）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_HOUYI_EXPLODE, Vector3(hero.global_position.x, 0.0, hero.global_position.z), hero.team, 2.0, 0.5)
				for _i in range(12):
					var fp = MeshFactory.create_sphere(0.15, Color(1.0, 0.4, 0.0, 0.8), true, 0.3)
					var angle = _i * PI * 2 / 12.0
					fp.position = hero.global_position + Vector3(cos(angle) * 0.5, 1.0, sin(angle) * 0.5)
					hero.get_parent().add_child(fp)
					var fpt = hero.create_tween()
					fpt.tween_property(fp, "position", fp.position + Vector3(cos(angle) * 3.0, 1.5, sin(angle) * 3.0), 0.5)
					fpt.parallel().tween_property(fp, "scale", Vector3(0.05, 0.05, 0.05), 0.5)
					fpt.parallel().tween_property(fp.material_override, "albedo_color:a", 0.0, 0.5)
					fpt.tween_callback(fp.queue_free)
				hero.get_parent().add_child(r_bullet)
		"大禹":match  skill_id:
			1:
				var q_level = hero.skill_levels[0]
				# 鼎上限检查：超出上限则移除最远的鼎
				while hero.dayu_tripods.size() >= hero.dayu_tripod_max:
					var furthest = null; var max_d = -1.0
					for t in hero.dayu_tripods:
						if is_instance_valid(t):
							var d = hero.global_position.distance_to(t.global_position)
							if d > max_d: max_d = d; furthest = t
					if furthest:
						hero.dayu_tripods.erase(furthest)
						furthest.queue_free()
					else:
						hero.dayu_tripods.clear()
				# 如果与已存在鼎重叠则销毁老鼎
				for t in hero.dayu_tripods:
					if is_instance_valid(t) and pos.distance_to(t.global_position) < 1.5:
						hero.dayu_tripods.erase(t)
						t.queue_free()
						break
				# 创建戍鼎
				var tripod = preload("res://scripts/entities/Tripod.gd").new()
				tripod.position = pos
				hero.get_parent().add_child(tripod)
				tripod.setup_tripod(hero.team, hero, q_level, hero.bonus_health)
				hero.dayu_tripods.append(tripod)
				# 鼎落位：金色地纹 + 绿柱 + 冲击环（替代纯色圆盘观感）
				var q_col := Color(0.42, 1.0, 0.62)
				Vfx.sigil(Vector3(pos.x, 0.0, pos.z), q_col, 3.0, 0.7)
				Vfx.pillar(Vector3(pos.x, 0.0, pos.z), q_col, 1.1, 4.2, 0.55)
				Vfx.shockwave(Vector3(pos.x, 0.0, pos.z), 2.6, q_col.lerp(Color.WHITE, 0.3), 0.4)
				Vfx.hit_spark(pos + Vector3.UP * 0.6, q_col, Vector3.UP, 1.2)
				# Q预览圈
				var q_preview = create_preview(3.0, pos, hero.team)
				q_preview.visible = true; hero.get_parent().add_child(q_preview)
				await hero.get_tree().create_timer(0.3).timeout
				q_preview.queue_free()
				# 自身加速75%衰减2.5秒
				hero.apply_flat_move_buff("ms_haste", 2.5, 60+15*level)
			2:
				var w_level = hero.skill_levels[1]
				var w_dir = (pos - hero.global_position).normalized()
				if w_dir.length() < 0.1: w_dir = Vector3.FORWARD
				var w_dmg = 400 + (w_level - 1) * 80 + hero.bonus_attack * 1.2
				var w_bullet = create_bullet(int(w_dmg), 0, 0, 0, false, hero, w_dir, 2)
				w_bullet.set_linear(w_dir, 9.0)
				w_bullet.speed = 12.0
				w_bullet.pierce = true
				w_bullet.dayu_w = true
				hero.get_parent().add_child(w_bullet)
				# 近身击退
				await hero.get_tree().create_timer(0.15).timeout
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if hero.global_position.distance_to(ent.global_position) <= 2.0:
							var kb_dir = (ent.global_position - hero.global_position).normalized()
							kb_dir.y = 0
							ent.global_position += kb_dir * 2.0
							ent.knockup_timer = 0.75
				# 开启强化普攻（4秒内1次）
				hero.dayu_w_enhanced = true
				hero.dayu_w_enhanced_timer = 4.0
				hero.dayu_w_used_enhanced = false
			3:
				var r_level = hero.skill_levels[2]
				var r_dir = (pos - hero.global_position).normalized()
				if r_dir.length() < 0.1: r_dir = Vector3.FORWARD
				if hero.skill_window_timers[2] > 0:
					# 第二段：霸体传送 + 爆发加速 + 震荡波减速
					hero.skill_window_timers[2] = 0
					var r2_target = hero.dayu_r_landing_pos
					var r2_dist = hero.global_position.distance_to(r2_target)
					var r2_travel_time = max(0.5, r2_dist / 30.0)
					# 霸体传送
					hero.bt_timer = r2_travel_time + 0.5
					var r2_from: Vector3 = hero.global_position
					hero.global_position = r2_target
					Vfx.dash_fx(r2_from, r2_target, Color(0.55, 0.85, 1.0), not hero.is_ai, r2_dist)
					Vfx.cast_glow(r2_from, Color(0.55, 0.85, 1.0), 1.6, 0.4)
					# 爆发加速（速度*5，持续1秒）
					hero.apply_move_pct_buff("ms_haste", 1.0, 4.0)
					await hero.get_tree().create_timer(r2_travel_time).timeout
					# 震荡波AoE伤害+减速
					var r2_dmg = 100 + (r_level - 1) * 20 + hero.bonus_attack * 0.3
					var r2_slow = 0.15 + (r_level - 1) * 0.05
					var r2_preview = create_preview(4.0, r2_target, hero.team)
					r2_preview.visible = true; hero.get_parent().add_child(r2_preview)
					await hero.get_tree().create_timer(0.2).timeout
					r2_preview.queue_free()
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if r2_target.distance_to(ent.global_position) <= 4.0:
								ent.take_damage(int(r2_dmg), hero, false, 3, 0)
								ent.apply_move_pct_buff("ms_slow", 1.0, -r2_slow, true)
					# 第二段特效：传送落点震波 + 水色地面域 + 双层冲击环
					var r2_col := Color(0.55, 0.85, 1.0)
					Vfx.shockwave(r2_target, 4.0, r2_col, 0.5)
					Vfx.shockwave(r2_target, 2.4, r2_col.lerp(Color.WHITE, 0.45), 0.35)
					Vfx.nova(r2_target, r2_col, 4.4)
					var r2_zone = Vfx.ground_zone(4.0, hero.team, "大禹", 1.2)
					hero.get_parent().add_child(r2_zone)
					r2_zone.global_position = Vector3(r2_target.x, 0.0, r2_target.z)
					var _r2_zt = r2_zone.create_tween()
					_r2_zt.tween_interval(1.3)
					_r2_zt.tween_callback(r2_zone.queue_free)
					Vfx._delayed_ring(r2_target, 4.6, r2_col, 0.18, 0.5)
					Vfx.hit_spark(r2_target + Vector3.UP * 0.8, r2_col, Vector3.UP, 1.6)
				else:
					# 第一段：AoE乾鼎击飞
					var r1_dmg = 500 + (r_level - 1) * 125 + hero.bonus_attack * 1.45
					hero.dayu_r_landing_pos = pos
					var r1_preview = create_preview(3.0, pos, hero.team)
					r1_preview.visible = true; hero.get_parent().add_child(r1_preview)
					await hero.get_tree().create_timer(0.3).timeout
					r1_preview.queue_free()
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if pos.distance_to(ent.global_position) <= 3.0:
								ent.take_damage(int(r1_dmg), hero, false, 3, 0)
								ent.knockup_timer = 1.0
								var kb = (ent.global_position - pos).normalized()
								ent.global_position += kb * 1.5
					# 在落点创建乾鼎（大招鼎），用于R2传送
					# 鼎上限检查：超出上限则移除最远的鼎
					while hero.dayu_tripods.size() >= hero.dayu_tripod_max:
						var furthest = null; var max_d = -1.0
						for t in hero.dayu_tripods:
							if is_instance_valid(t):
								var d = hero.global_position.distance_to(t.global_position)
								if d > max_d: max_d = d; furthest = t
						if furthest:
							hero.dayu_tripods.erase(furthest)
							furthest.queue_free()
						else:
							hero.dayu_tripods.clear()
					# 如果与已存在鼎重叠则销毁老鼎
					for t in hero.dayu_tripods:
						if is_instance_valid(t) and pos.distance_to(t.global_position) < 1.5:
							hero.dayu_tripods.erase(t)
							t.queue_free()
							break
					# 创建乾鼎
					var r_tripod = preload("res://scripts/entities/Tripod.gd").new()
					r_tripod.position = pos
					hero.get_parent().add_child(r_tripod)
					r_tripod.setup_tripod(hero.team, hero, r_level, hero.bonus_health, true)
					hero.dayu_tripods.append(r_tripod)
					# 乾鼎降临特效：金色天降光柱 + 落地冲击环 + 地纹 + 碎石火花
					var r1_col := Color(1.0, 0.82, 0.35)
					Vfx.pillar(Vector3(pos.x, 0.0, pos.z), r1_col, 2.0, 9.0, 0.7)
					Vfx.shockwave(Vector3(pos.x, 0.0, pos.z), 3.4, r1_col, 0.55)
					Vfx.shockwave(Vector3(pos.x, 0.0, pos.z), 2.0, Color(1.0, 0.95, 0.7), 0.35)
					Vfx.sigil(Vector3(pos.x, 0.0, pos.z), r1_col, 3.4, 1.0)
					Vfx.nova(Vector3(pos.x, 0.0, pos.z), r1_col, 3.8)
					Vfx.hit_spark(pos + Vector3.UP * 0.7, r1_col, Vector3.UP, 1.8)
					# 开启重施窗口
					hero.skill_window_timers[2] = 3.0
		"王昭君":match  skill_id:
			1:  # 凋零冰晶：AoE + 冰冷 + 视野
				var w1_preview = create_preview(2.0, pos, hero.team)
				w1_preview.visible = true
				hero.get_parent().add_child(w1_preview)
				await hero.get_tree().create_timer(0.3).timeout
				# 伤害 + 冰冷
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if pos.distance_to(ent.global_position) <= 2.0:
							var w1_dmg = 280 + 70 * level + hero.actual_ability_power * 0.7
							ent.take_damage(w1_dmg, hero, true, 1, 0)
							_apply_freezing(ent,level)
				# 视野标记（2秒可见）
				var w1_vision = create_spell(2.0, hero.team, "王昭君", 2.4)
				w1_vision.position = pos
				hero.get_parent().add_child(w1_vision)
				# #43 网络 FX：王昭君1 冰晶视野圈（2s）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_SPELL, Vector3(pos.x, 0.0, pos.z), hero.team, 2.0, 2.0, "王昭君")
				await hero.get_tree().create_timer(2.0).timeout
				w1_vision.queue_free()
				w1_preview.queue_free()

			2:  # 禁锢寒霜：延迟AoE + 冰冻 + 对冰冷目标额外伤害
				var w2_preview = create_preview(2.0, pos, hero.team)
				w2_preview.visible = true
				hero.get_parent().add_child(w2_preview)
				await hero.get_tree().create_timer(0.75).timeout
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent != hero and ent.health > 0 and ent.team != hero.team:
						if pos.distance_to(ent.global_position) <= 2.0:
							var w2_dmg = 200 + 50 * level + hero.actual_ability_power * 0.5
							# 冰冷目标额外伤害（移速/攻速任一净减速即视为受冰冷影响）
							if ent.slow_amount > 0 or ent.bonus_attack_speed_pct < 0:
								w2_dmg += 120 + 30 * level + hero.actual_ability_power * 0.2
							ent.take_damage(w2_dmg, hero, true, 2, 0)
							ent.froze_timer = 2.5  # 冰冻硬控（仅阻止移动）
				w2_preview.queue_free()

			3:  # 凛冬已至：刷新护盾 + 5秒持续暴风雪
				# 刷新被动护盾
				var w3_shield_lv = hero.skill_levels[0] if hero.skill_levels.size() > 0 else 1
				var w3_shield = (450 * w3_shield_lv) + hero.actual_ability_power * 0.58
				hero.shield_remaining = max(hero.shield_remaining, w3_shield)
				hero.wangzhaojun_shield_was_active = true
				# 持续暴风雪
				var w3_zone = create_spell(5.0, hero.team, "王昭君", 5.6)
				w3_zone.position = pos
				hero.get_parent().add_child(w3_zone)
				# #43 网络 FX：王昭君R 暴风雪持续区（5s）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_SPELL, Vector3(pos.x, 0.0, pos.z), hero.team, 5.0, 6.0, "王昭君")
				for _tick in range(10):
					await hero.get_tree().create_timer(0.5).timeout
					if hero.health <= 0: break
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent != hero and ent.health > 0 and ent.team != hero.team:
							if pos.distance_to(ent.global_position) <= 5.0:
								var w3_dmg = 100 + 100 * level + hero.actual_ability_power * 0.35
								ent.take_damage(w3_dmg, hero, true, 3, 0)
								_apply_freezing(ent,hero.skill_levels[0])
				w3_zone.queue_free()

		"刘禅":match  skill_id:
			1:  # 小霸王护盾：护盾+加速+强化普攻
				var _bonus_hp = hero.actual_max_health - hero.max_health
				var _shield_amt = int(520 + 130*level + 0.14*_bonus_hp)
				hero.shield_remaining = max(hero.shield_remaining, _shield_amt)
				hero.shield_timer = 3.0
				var _speed_boost = 0.4 + 0.1*level
				hero.apply_move_pct_buff("ms_haste", 3.0, _speed_boost)
				hero.liushan_q_active = true
				hero.liushan_q_timer = 3.0
			2:  # 机关魔爪：AoE伤害+眩晕
				var w2_preview = create_preview(2.0, pos, hero.team)
				w2_preview.visible = true
				hero.get_parent().add_child(w2_preview)
				await hero.get_tree().create_timer(0.35).timeout
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var w2_bullet = create_bullet(int(100+25*level+0.35*hero.bonus_attack),0.0,0,0,false,hero,dir,2)
				w2_bullet.damage_range = 2.0
				w2_bullet.stun_dur = 1.0
				w2_bullet.speed = 15.0
				w2_bullet.set_goal(pos)
				hero.get_parent().add_child(w2_bullet)
				await hero.get_tree().create_timer(0.5).timeout
				if is_instance_valid(w2_preview): w2_preview.queue_free()
			3:  # 暴走熊猫：3秒旋转AoE+减速
				# === 视觉1：持续地面范围环（4.0半径）→ 实体齿轮盘（金属 + 发光齿）
				var ls_ground_ring := MeshInstance3D.new()
				ls_ground_ring.mesh = MeshFactory.build_gear(3.88, 0.12, 30, 0.16, 3.05)
				ls_ground_ring.material_override = MeshFactory.metal_pbr(Color(0.26, 0.24, 0.22), 0.30, Color(1.0, 0.46, 0.10))
				ls_ground_ring.rotation.x = -PI * 0.5
				ls_ground_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ls_ground_ring.position = hero.global_position + Vector3(0, 0.05, 0)
				var ls_gtw := ls_ground_ring.create_tween()
				ls_gtw.set_loops()
				ls_gtw.tween_property(ls_ground_ring, "rotation:y", TAU, 2.4).as_relative()
				hero.get_parent().add_child(ls_ground_ring)
				# #43 网络 FX：刘禅R 旋转地面环（3s 橙区，随英雄起手位）
				if NetSession.mode == NetSession.Mode.HOST:
					NetSession.push_net_fx(NetSession.FX_LYF_STORM, Vector3(hero.global_position.x, 0.0, hero.global_position.z), hero.team, 4.0, 3.0, "李元芳")
				# === 视觉2：腰部旋转齿轮环（金属 PBR + 接缝发光）
				var ls_waist_ring := MeshInstance3D.new()
				ls_waist_ring.mesh = MeshFactory.build_gear(0.78, 0.10, 14, 0.10, 0.30)
				ls_waist_ring.material_override = MeshFactory.metal_pbr(Color(0.52, 0.55, 0.62), 0.26, Color(1.0, 0.52, 0.15))
				ls_waist_ring.rotation.x = -PI * 0.5
				ls_waist_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ls_waist_ring.position = hero.global_position + Vector3(0, 1.0, 0)
				hero.get_parent().add_child(ls_waist_ring)
				var ls_waist_tw = hero.create_tween()
				ls_waist_tw.set_loops()
				ls_waist_tw.tween_property(ls_waist_ring, "rotation:y", deg_to_rad(360), 1.0).as_relative()
				for _tick in range(6):
					# 持续效果跟随英雄移动
					if is_instance_valid(ls_ground_ring):
						ls_ground_ring.global_position = hero.global_position + Vector3(0, 0.05, 0)
					if is_instance_valid(ls_waist_ring):
						ls_waist_ring.global_position = hero.global_position + Vector3(0, 1.0, 0)
					# === 视觉3：脚底蒸汽 + 金属飞屑（不再用纯色小球）===
					if _tick == 0:
						var ls_steam := Vfx._charge_particles(22, 0.9, Color(0.88, 0.92, 0.98), 0.22, 0.9)
						ls_steam.emitting = true
						ls_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
						ls_steam.emission_ring_radius = 3.2
						ls_steam.emission_ring_inner_radius = 1.1
						ls_steam.emission_ring_height = 0.2
						ls_steam.direction = Vector3(0, 1, 0)
						ls_steam.spread = 55.0
						ls_steam.gravity = Vector3(0, 2.0, 0)
						ls_steam.initial_velocity_min = 0.6
						ls_steam.initial_velocity_max = 1.8
						ls_steam.position = hero.global_position + Vector3(0, 0.2, 0)
						hero.get_parent().add_child(ls_steam)
						var ls_stw := hero.create_tween()
						ls_stw.tween_interval(2.6)
						ls_stw.tween_property(ls_steam, "emitting", false, 0.1)
						ls_stw.tween_callback(ls_steam.queue_free)
					for _d in range(2):
						var ls_angle2 := randf() * TAU
						var ls_shard := MeshInstance3D.new()
						var shm := BoxMesh.new()
						shm.size = Vector3(0.18, 0.05, 0.05)
						ls_shard.mesh = shm
						ls_shard.material_override = MeshFactory.metal_pbr(Color(0.62, 0.66, 0.74), 0.28, Color(1.0, 0.5, 0.14))
						ls_shard.position = hero.global_position + Vector3(cos(ls_angle2) * 0.6, 0.12, sin(ls_angle2) * 0.6)
						ls_shard.rotation = Vector3(randf() * TAU, ls_angle2, randf() * TAU)
						ls_shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						hero.get_parent().add_child(ls_shard)
						var ls_dt := hero.create_tween()
						ls_dt.set_parallel(true)
						ls_dt.tween_property(ls_shard, "position", ls_shard.position + Vector3(cos(ls_angle2), 0.9, sin(ls_angle2)) * 1.8, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
						ls_dt.tween_property(ls_shard, "rotation:x", ls_shard.rotation.x + 8.0, 0.45)
						ls_dt.tween_property(ls_shard, "transparency", 1.0, 0.45).set_delay(0.15)
						ls_dt.tween_callback(ls_shard.queue_free)
					# === 视觉4：扩散冲击齿轮环（每tick一次，从中心扩散至边缘）===
					var ls_wave := MeshInstance3D.new()
					ls_wave.mesh = MeshFactory.build_gear(0.42, 0.06, 12, 0.12, 0.20)
					ls_wave.material_override = MeshFactory.metal_pbr(Color(0.78, 0.52, 0.24), 0.26, Color(1.0, 0.5, 0.12))
					ls_wave.rotation.x = -PI * 0.5
					ls_wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					ls_wave.position = hero.global_position + Vector3(0, 0.12, 0)
					# #43 网络 FX：刘禅R 每tick扩散冲击波（0.7s 一次性环）
					if NetSession.mode == NetSession.Mode.HOST:
						NetSession.push_net_fx(NetSession.FX_WAVE_RING, Vector3(hero.global_position.x, 0.0, hero.global_position.z), hero.team, 4.0, 0.7)
					ls_wave.scale = Vector3(0.5, 1.0, 0.5)
					hero.get_parent().add_child(ls_wave)
					var ls_sw := ls_wave.create_tween()
					ls_sw.set_parallel(true)
					ls_sw.tween_property(ls_wave, "scale", Vector3(9.4, 1.0, 9.4), 0.7)
					ls_sw.tween_property(ls_wave, "rotation:y", TAU * 1.5, 0.7)
					ls_sw.tween_property(ls_wave, "transparency", 1.0, 0.7).set_delay(0.15)
					ls_sw.tween_callback(ls_wave.queue_free)
					# === 视觉5：地面火花（细锥拖出的火星，而非纯色小球）===
					for _sp in range(3):
						var ls_spa := randf() * TAU
						var ls_sr := randf() * 3.2
						var ls_spark := MeshInstance3D.new()
						var spm := CylinderMesh.new()
						spm.top_radius = 0.0
						spm.bottom_radius = 0.06
						spm.height = 0.5
						spm.radial_segments = 6
						ls_spark.mesh = spm
						var smat := StandardMaterial3D.new()
						smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
						smat.albedo_color = Color(1.0, 0.72, 0.26, 0.9)
						smat.emission_enabled = true
						smat.emission = Color(1.0, 0.58, 0.18)
						smat.emission_energy_multiplier = 2.6
						ls_spark.material_override = smat
						ls_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						var sbase := hero.global_position + Vector3(cos(ls_spa) * ls_sr, 0.06, sin(ls_spa) * ls_sr)
						ls_spark.position = sbase + Vector3(0, 0.25, 0)
						ls_spark.rotation = Vector3(randf_range(-0.5, 0.5), ls_spa, randf_range(-0.5, 0.5))
						hero.get_parent().add_child(ls_spark)
						var ls_spt := ls_spark.create_tween()
						ls_spt.set_parallel(true)
						ls_spt.tween_property(ls_spark, "position", sbase + Vector3(0, 1.15, 0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
						ls_spt.tween_property(ls_spark, "scale", Vector3(0.35, 1.9, 0.35), 0.4)
						ls_spt.tween_property(ls_spark, "transparency", 1.0, 0.4).set_delay(0.12)
						ls_spt.tween_callback(ls_spark.queue_free)
					await hero.get_tree().create_timer(0.5).timeout
					if hero.health <= 0: break
					var _bonus_ad = hero.bonus_attack
					var _tick_dmg = int(190 + 190*level + 1.1*_bonus_ad)
					var _slow_pct = 0.075 + 0.075*level
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
						var _dist = hero.global_position.distance_to(ent.global_position)
						if _dist <= 4.0:
							if ent is Turret:
								ent.take_damage(_tick_dmg, hero, false, -3, 0)
								ent.interfere_timer = max(ent.interfere_timer, 1.2)
								hero._apply_healing(225+15*hero.level+0.045*hero.bonus_health)
							else:
								ent.take_damage(_tick_dmg, hero, false, 3, 0)
							ent.apply_move_pct_buff("ms_slow", 0.5, -_slow_pct, true)
				# 清理持续视觉
				if is_instance_valid(ls_ground_ring): ls_ground_ring.queue_free()
				if is_instance_valid(ls_waist_ring):
					ls_waist_tw.kill()
					ls_waist_ring.queue_free()


		"孙悟空":match  skill_id:
			1:  # 护身咒法：加速40% 1秒 + 格挡窗口1.5秒
				hero.apply_move_pct_buff("ms_haste", 1.0, 0.4)
				hero.sunwukong_1_block_active = true
				hero.sunwukong_1_block_timer = 1.5
				hero.sunwukong_enhanced_aa = true
			2:  # 斗战冲锋：冲刺+碰撞伤害+斩杀
				var ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))
				var dir = Vector3(cos(ang),0,-sin(ang))
				var old_pos = hero.global_position
				hero.global_position += dir * 4.0
				hero.global_position.y = 0.5
				var new_pos = hero.global_position
				var line_vec = new_pos - old_pos
				var w_dmg = int(320 + 64*(level-1) + hero.bonus_attack * 1.0)
				var hit_enemy = false
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
					var t = clamp((ent.global_position - old_pos).dot(line_vec) / line_vec.length_squared(), 0, 1)
					var closest = old_pos + line_vec * t
					if closest.distance_to(ent.global_position) <= 2.0:
						hit_enemy = true
						# 斩杀：小兵/非史诗野怪低于15%HP → 99999真实伤害
						if (ent is Minion) or (ent is JungleMonster and ent.display_name not in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]):
							if ent.health < ent.max_health * 0.15:
								ent.take_damage(99999, hero, false, 2, 1.0)
								continue
						# 史诗野怪：25%→50%额外伤害
						if ent is JungleMonster and ent.display_name in ["tyrant", "dragon", "shadow_tyrant", "shadow_dragon", "storm_dragon"]:
							var bonus = 0.25 + 0.05*(level-1)
							ent.take_damage(int(w_dmg * (1.0 + bonus)), hero, false, 2, 0)
						else:
							ent.take_damage(w_dmg, hero, false, 2, 0)
				if hit_enemy:
					hero.apply_move_pct_buff("ms_haste", 1.0, 0.9)
				hero.sunwukong_enhanced_aa = true
			3:  # 如意金箍：预览圈+延时 → AoE 4.0 击飞1秒 + 3层印记6秒
				var r_preview = create_preview(4.0, hero.global_position, hero.team)
				r_preview.visible = true
				hero.get_parent().add_child(r_preview)
				await hero.get_tree().create_timer(0.3).timeout
				var r_dmg = int(250 + 125*(level-1) + hero.bonus_attack * 0.8)
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
					var dist = hero.global_position.distance_to(ent.global_position)
					if dist <= 4.0:
						ent.take_damage(r_dmg, hero, false, 3, 0)
						ent.knockup_timer = max(ent.knockup_timer, 1.0)
						for _j in range(3):
							ent.markers.append({"timer": 6.0, "source": hero, "type": "sunwukong_r"})
				if is_instance_valid(r_preview): r_preview.queue_free()
				hero.sunwukong_enhanced_aa = true

		"英睿":match  skill_id:
			1:  # 冰红茶：两段式——0.5s伤害 + 1.0s巧乐兹击飞0.75s
				var q_preview = create_preview(1.8, pos, hero.team)
				q_preview.visible = true
				hero.get_parent().add_child(q_preview)
				# 泼洒视觉：茶色水流束 + 落点茶花四溅（替代原来的纯色细柱）
				var tea_col := Color(0.78, 0.48, 0.16)
				var tea_from: Vector3 = hero.global_position + Vector3(0, 1.0, 0)
				var tea_to: Vector3 = pos + Vector3(0, 0.6, 0)
				Vfx.beam(tea_from, tea_to, tea_col, 0.30, 0.45)
				Vfx.beam(tea_from, tea_to, tea_col.lerp(Color.WHITE, 0.5), 0.12, 0.32)
				Vfx.cast_glow(tea_from, tea_col, 0.9, 0.35)
				Vfx.nova(pos, tea_col.lerp(Color.WHITE, 0.3), 1.9)
				Vfx._delayed_ring(pos, 1.9, tea_col, 0.22, 0.45)
				await hero.get_tree().create_timer(0.5).timeout
				# —— 第一段：冰红茶伤害 ——
				var q_dmg = int(340 + 40 * (level - 1) + hero.bonus_attack * 1.2)
				var q_hit = false
				for ent in hero.get_tree().get_nodes_in_group("entities"):
					if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
					if ent.global_position.distance_to(pos) <= 1.8:
						ent.take_damage(q_dmg, hero, false, 1, 0)
						q_hit = true
						if ent is Hero:
							hero.yingrui_add_stack()
				await hero.get_tree().create_timer(0.5).timeout
				# —— 第二段：仅冰红茶命中时，巧乐兹造成同等伤害+击飞0.75s ——
				if q_hit:
					# 巧乐兹：奶油色冰柱 + 冰霜环 + 击飞火花（替代纯色短柱）
					var bar_col := Color(0.95, 0.9, 0.72)
					Vfx.pillar(pos, bar_col, 0.85, 3.4, 0.55)
					Vfx.shockwave(pos, 1.9, bar_col.lerp(Color(0.7, 0.9, 1.0), 0.5), 0.35)
					Vfx.nova(pos, Color(0.8, 0.94, 1.0), 2.0)
					Vfx.hit_spark(pos + Vector3.UP * 1.2, bar_col, Vector3.UP, 1.3)
					for ent in hero.get_tree().get_nodes_in_group("entities"):
						if ent == hero or ent.health <= 0 or ent.team == hero.team: continue
						if ent.global_position.distance_to(pos) <= 1.8:
							ent.take_damage(q_dmg, hero, false, 1, 0)
							ent.knockup_timer = max(ent.knockup_timer, 0.75)
				await hero.get_tree().create_timer(0.5).timeout
				if is_instance_valid(q_preview): q_preview.queue_free()
			2:  # 肘击：3段，每段一次肘击（同原2技能效果）
				hero.yingrui_elbow(pos)
				var w_stage = hero.yingrui_w_stage + 1
				if w_stage >= 3:
					# 第3段打完：关闭窗口，进入完整CD
					hero.yingrui_w_stage = 0
					hero.skill_window_timers[1] = 0
				else:
					hero.yingrui_w_stage = w_stage
					hero.skill_window_timers[1] = 3.0
			3:  # 变身LabiB：高额双抗12秒 + 变身普攻附加伤害
				var r_lv = maxi(level, 1)
				hero.yingrui_transformed = true
				hero.yingrui_transform_timer = 14.0
				hero.scale = Vector3(1.15, 1.15, 1.15)
				hero._apply_df_buff(160 + 50 * r_lv, 0, 14.0, false)
				hero._apply_df_buff(100 + 40 * r_lv, 0, 14.0, true)
				# 视觉：变身金光（天降光柱 + 地纹 + 冲击环 + 上升金尘，替代纯色圆柱）
				var r_col := Color(1.0, 0.8, 0.28)
				var r_ground := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
				Vfx.pillar(r_ground, r_col, 1.7, 8.0, 0.9)
				Vfx.sigil(r_ground, r_col, 3.2, 1.2)
				Vfx.shockwave(r_ground, 3.0, r_col, 0.5)
				Vfx.nova(r_ground, r_col, 3.2)
				Vfx.cast_glow(hero.global_position + Vector3.UP * 1.2, r_col, 1.6, 0.8)
				Vfx.hit_spark(hero.global_position + Vector3.UP * 1.4, r_col, Vector3.UP, 1.8)


# 技能图标内的伤害预览。把 apply_skills 里每英雄每个技能「主要命中段」的单次伤害转录到这里：
# 数值 = 未计护甲/魔抗减伤的一段伤害，随当前技能等级与当前出装/加成实时变化；
# magic 决定主段着色（false=物理→橙，true=法术→紫）。多段技能只取代表性主段（连射/波次取单发）。
# 若每段同时附带第二类型伤害（如狄仁杰同 token 双发物理+法术），额外返回 dmg2/magic2：
#   图标与详情把两段并排显示（主段在前，附段在后，各自着色），共用弹数“×N”。
# 纯增益/护盾/位移等无直接伤害的技能返回 valid=false → 图标不显示数值。
func get_skill_icon_damage(hero: Hero, i: int) -> Dictionary:
	var res := {"valid": false, "dmg": 0, "magic": false, "dmg2": 0, "magic2": false}
	if hero == null or i < 0 or i > 2:
		return res
	if i >= hero.skill_levels.size():
		return res
	var lv := int(hero.skill_levels[i])
	if lv <= 0:
		return res
	var ad := float(hero.bonus_attack)          # 额外物攻
	var aad := float(hero.actual_attack_damage) # 总物攻（含基础）
	var ap := float(hero.actual_ability_power)  # 法强
	var mhp := float(hero.actual_max_health)           # 生命上限
	match str(hero.display_name):
		"狄仁杰":
			# 每段令牌同时命中物理+法术两份伤害（apply_skills 里同 token 双发 bullet/bullet1）：
			# dmg=物理主段（橙）；dmg2=法术附段（紫），二者并排显示、共用弹数“×N”
			if i == 2:
				return {"valid": true, "dmg": int(round(225.0 + 1.2 * ad + 0.6 * ap + 75.0 * lv)), "magic": false,
					"dmg2": int(round(225.0 + 1.2 * aad + 0.6 * ap + 75.0 * lv)), "magic2": true}
			return {"valid": true, "dmg": int(round(96.0 + 0.18 * aad + 24.0 * lv)), "magic": false,
				"dmg2": int(round(72.0 + 0.18 * aad + 18.0 * lv)), "magic2": true}
		"马可波罗":
			if i == 0:
				return _icon_dmg(false, 76.0 + 0.24 * aad + 19.0 * lv)
			if i == 2:
				return _icon_dmg(false, 65.0 + 0.25 * aad + 65.0 * lv)
		"孙尚香":
			if i == 1:
				return _icon_dmg(false, 304.0 + int(1.2 * ad) + 76.0 * lv)
			if i == 2:
				return _icon_dmg(false, 420.0 + int(2.5 * ad) + 420.0 * lv)
		"马超":
			if i == 0:
				return _icon_dmg(false, 256.0 + 1.1 * ad + 64.0 * lv+hero.bonus_move_speed)
			if i == 1:
				return _icon_dmg(false, 192.0 + 0.9 * ad + 48.0 * lv+hero.bonus_move_speed)
			return _icon_dmg(false, 120.0 + 0.63 * ad + 120.0 * lv+0.045*(mhp-hero.health)+hero.bonus_move_speed)
		"吕布":
			if i == 0:
				return _icon_dmg(false, int(600.0 + 2.0 * ad) + 120.0 * lv)
			if i == 1:
				return _icon_dmg(false, int(100.0 + 0.35 * ad) + 20.0 * lv)
			return _icon_dmg(false, int(650.0 + 2.4 * ad) + 325.0 * lv)
		"沈梦溪":
			if i == 0:
				return _icon_dmg(true, 180.0 + 0.45 * ap + 45.0 * lv)
			if i == 1:
				return _icon_dmg(true, 360.0 + 0.9 * ap + 90.0 * lv)
			if i == 2:
				return _icon_dmg(true, 200.0 + 0.8 * ap + 200.0 * lv)
		"不知火舞":
			if i == 0:
				return _icon_dmg(true, 480.0 + 0.73 * ap + 70.0 * lv)
			if i == 1:
				return _icon_dmg(true, 360.0 + 0.9 * ap + 90.0 * lv)
			return _icon_dmg(true, 600.0 + 1.1 * ap + 200.0 * lv)
		"甄姬":
			if i == 0:
				return _icon_dmg(true, 360.0 + 0.85 * ap + 90.0 * lv)
			if i == 1:
				return _icon_dmg(true, 184.0 + 0.45 * ap + 46.0 * lv)
			return _icon_dmg(true, 75.0 + 0.32 * ap + 75.0 * lv)
		"铠":
			if i == 0:
				return _icon_dmg(false, int(224.0 + 0.85 * ad) + 56.0 * lv)
			if i == 1:
				return _icon_dmg(false, int(120.0 + 0.55 * ad) + 30.0 * lv)
			return _icon_dmg(true, int(125.0 + 0.25 * ad) + 125.0 * lv)
		"亚瑟":
			if i == 1:
				return _icon_dmg(false, 127.0 + 18.0*lv + 0.8 * aad)
			if i == 2:
				return _icon_dmg(true, mhp * (0.12 + 0.04 * lv))
		"太乙真人":
			var q_dur = min(hero.taiyi_q_timer, 5.0)
			if i == 0:
				return _icon_dmg(true, 105 + hero.skill_levels[0] * 4 + (32 + hero.skill_levels[0] * 1.6) * q_dur + (0.55 + 0.22 * q_dur) * hero.actual_ability_power)
			if i == 1:
				return _icon_dmg(true, 400.0 + 0.8 * ap + 50.0 * lv)
		"东皇太一":
			if i == 0:
				return _icon_dmg(true, 240.0 + 15.0 * lv + 0.4 * ap)
			if i == 1:
				if hero.donghuang_orbs <= 0:
					return {}   # 无能量体时不发射子弹：不给伤害/发数预览（与预览环 0 颗全隐藏一致）
				return _icon_dmg(true, 400.0 + 0.6 * ap + 100.0 * lv)
		"李白":
			if i == 0:
				return _icon_dmg(false, 305.0 + 45.0 * lv + 1.1 * ad)
			if i == 1:
				return _icon_dmg(false, 256.0 + 64.0 * lv + 1.0 * ad)
			return _icon_dmg(false, 155.0 + 55.0 * lv + 0.6 * ad)
		"兰陵王":
			if i == 0:
				return _icon_dmg(false, 260.0 + 65.0 * lv + 1.25 * ad)
			if i == 1:
				return {"valid": true, "dmg": int(round(160.0 + 0.9 * ad + 40.0 * lv)), "magic": false,
				"dmg2": int(round(112 + lv * 28 + (hero.actual_max_health-hero.health) * (0.12 + int(hero.bonus_attack/50)*0.01))), "magic2": false}
			return _icon_dmg(false, 350.0 + 350.0 * lv + 2.5 * ad)
		"张飞":
			if i == 0:
				return _icon_dmg(false, 464.0 + 116.0 * lv + 1.45 * ad)
			if i == 2:
				return _icon_dmg(false, 300.0 + 300.0 * lv + 1.5 * ad)
		"安琪拉":
			if i == 0:
				return _icon_dmg(true, 230.0 + 0.3 * ap + 40.0 * lv)
			if i == 1:
				return _icon_dmg(true, 100.0 + 0.2 * ap + 25.0 * lv)
			return _icon_dmg(true, 110.0 + 40.0 * lv + 0.21 * ap)
		"妲己":
			if i == 0:
				return _icon_dmg(true, 505.0 + 1.2 * ap + 65.0 * lv)
			if i == 1:
				return _icon_dmg(true, 250.0 + 0.66 * ap + 35.0 * lv)
			return _icon_dmg(true, 245.0 + 0.75 * ap + 80.0 * lv)
		"小乔":
			if i == 0:
				return _icon_dmg(true, 585.0 + 0.8 * ap + 50.0 * lv)
			if i == 1:
				return _icon_dmg(true, 300.0 + 0.5 * ap + 40.0 * lv)
			return _icon_dmg(true, 400.0 + 1.0 * ap + 100.0 * lv)
		"鲁班七号":
			if i == 0:
				return _icon_dmg(false, 520.0 + (lv - 1) * 104.0 + 1.5 * ad)
			if i == 1:
				return _icon_dmg(false, 450.0 + (lv - 1) * 90.0 + 1.25 * ad)
			return _icon_dmg(false, 520.0 + (lv - 1) * 260.0 + 1.5 * ad)
		"夏侯惇":
			if i == 0:
				return _icon_dmg(false, 400.0 + (lv - 1) * 80.0 + 1.3 * ad)
			if i == 1:
				return _icon_dmg(true, 300.0 + (lv - 1) * 60.0 + 1.0 * ad)
			return _icon_dmg(false, 400.0 + (lv - 1) * 200.0 + 0.1 * float(hero.bonus_health))
		"后羿":
			if i == 1:
				return _icon_dmg(true, 480.0 + (lv - 1) * 96.0 + 1.1 * ad)
			if i == 2:
				return _icon_dmg(false, 800.0 + (lv - 1) * 400.0 + 1.5 * ad)
		"大禹":
			if i == 1:
				return _icon_dmg(false, 400.0 + (lv - 1) * 80.0 + 1.2 * ad)
			if i == 2:
				return _icon_dmg(false, 500.0 + (lv - 1) * 125.0 + 1.45 * ad)
		"王昭君":
			if i == 0:
				return _icon_dmg(true, 280.0 + 70.0 * lv + 0.7 * ap)
			if i == 1:
				return _icon_dmg(true, 200.0 + 50.0 * lv + 0.5 * ap)
			return _icon_dmg(true, 100.0 + 100.0 * lv + 0.35 * ap)
		"刘禅":
			if i == 1:
				return _icon_dmg(false, int(100.0 + 25.0 * lv) + 0.35 * ad)
			if i == 2:
				return _icon_dmg(false, int(190.0 + 190.0 * lv + 1.1 * ad))
		"孙悟空":
			if i == 1:
				return _icon_dmg(false, int(320.0 + 64.0 * (lv - 1) + 1.0 * ad))
			if i == 2:
				return _icon_dmg(false, int(250.0 + 125.0 * (lv - 1) + 0.8 * ad))
		"李元芳":
			if i == 0:
				return _icon_dmg(false, int(220.0 + 44.0 * (lv - 1) + 0.7 * ad))
			if i == 1:
				return _icon_dmg(false, int(260.0 + 52.0 * (lv - 1) + 0.8 * ad))
			return _icon_dmg(false, int(320.0 + 160.0 * (lv - 1) + 1.0 * ad))
		"元流之子":
			if i == 0:
				return _icon_dmg(false, int(100.0 + 20.0 * (lv - 1) + 0.25 * ad))
			if i == 1:
				return _icon_dmg(false, int(480.0 + 96.0 * (lv - 1) + 1.2 * ad))
			return _icon_dmg(false, int(50.0 + 25.0 * (lv - 1) + 0.24 * aad))
		"英睿":
			if i == 0:
				return _icon_dmg(false, int(340.0 + 40.0 * (lv - 1) + 1.2 * ad))
			if i == 1:
				return _icon_dmg(false, int(420.0 + 45.0 * (lv - 1) + 1.4 * ad))
	return res

# 组装图标伤害结果：dmg=取整后的单段伤害，magic=false 物理(橙)/true 法术(紫)
func _icon_dmg(magic: bool, amount: float) -> Dictionary:
	return {"valid": true, "dmg": int(round(amount)), "magic": magic}


# 返回单个技能的“弹数/段数 + 效果”展示数据（与 get_skill_icon_damage 配套，供详情面板与图标“×N”使用）：
#   count : 多发/多段数量（<=1 表示单发，图标与伤害行不标“×N”）
#   unit  : 数量单位（发/段/波/跳/团…）
#   fx    : 带数值的效果条目标签，逐条渲染成“圆底汉字图标+数字”：
#            {"t":类型,"v":主值,"d":持续秒}；t ∈ slow/selfspeed/stun/knockup/freeze/suppress/bt/shield/heal
#            及属性增减 defup/defdn(双抗) armup/armdn(护甲) mrup/mrdn(魔抗) asup/asdn(攻速)
#            （v 为数值：属性增益类=扁平值+d 时长，增减百分比类=d 为时长）
#   texts : 无法用单个图标概括的效果补充说明（放在面板数值行之后）
# 数值均已按 apply_skills / Hero 每帧逻辑中的真实公式转录；未学习(lv<=0)返回空。
func get_skill_fx(hero: Hero, i: int) -> Dictionary:
	var res := {"count": 0, "unit": "", "fx": [], "texts": []}
	if hero == null or i < 0 or i > 2:
		return res
	if i >= hero.skill_levels.size():
		return res
	var lv := int(hero.skill_levels[i])
	if lv <= 0:
		return res
	var ad := float(hero.bonus_attack)
	var aad := float(hero.actual_attack_damage)
	var ap := float(hero.actual_ability_power)
	var bh := float(hero.bonus_health)
	var fx: Array = []
	var texts: Array = []
	var count := 0
	var unit := ""
	match str(hero.display_name):
		"狄仁杰":
			if i == 0:
				count = 6; unit = "发"
			elif i == 1:
				count = 8; unit = "发"
				fx.append({"t": "cleanse"})   # 二技能核心特效：净化自身（解除减速/眩晕/击飞等控制）
				fx.append({"t": "selfspeed", "v": 20.0 + 5.0 * lv, "d": 1.0})
				texts.append("净化自身控制并提升移速；向四周掷出8张令牌")
			else:
				fx.append({"t": "stun", "v": 1.0})
				fx.append({"t": "defdn", "v": 50.0, "d": 5.0})   # 双防-50% · 5秒
		"马可波罗":
			if i == 0:
				fx.append({"t": "selfspeed", "v": 10.0, "d": 1.0})
				count = 4 + lv; unit = "发"
			elif i == 1:
				texts.append("位移冲刺（每3发子弹的普攻触发装备效果）")
			else:
				count = 9 + lv*3; unit = "轮"
				texts.append("向四周持续扫射多轮（每轮8发）")
		"孙尚香":
			if i == 0:
				texts.append("翻滚位移并强化下一次普攻（射程/伤害提升）")
			elif i == 1:
				fx.append({"t": "slow", "v": 90.0, "d": 1.0})
				fx.append({"t": "armdn", "v": 10.0, "d": 5.0})   # 护甲-10% · 5秒
			else:
				texts.append("巨炮范围命中；外圈伤害为75%")
		"马超":
			if i == 0:
				texts.append("掷枪落地可拾取（拾枪强化后续冲刺并回蓝）")
			elif i == 1:
				fx.append({"t": "slow", "v": 15.0, "d": 2.0})
				texts.append("命中区域同时留下一杆枪")
			else:
				texts.append("向身边最近的枪冲刺，沿途贯穿伤害并回复少量生命")
		"吕布":
			if i == 0:
				texts.append("以自身为中心，对面前120°扇形区域内的敌人造成物理伤害")
			elif i == 1:
				fx.append({"t": "slow", "v": 12.0 + 3.0 * lv, "d": 3.0})
			elif i == 2:
				fx.append({"t": "knockup", "v": 1.0})
				fx.append({"t": "slow", "v": 15.0 + 15.0 * lv, "d": 2.0})
				fx.append({"t": "defup", "v": 75.0 + 75.0 * lv, "d": 5.0})   # 落地双抗各+75+75Lv · 5秒（引擎 _apply_df_buff 同式）
				texts.append("落地后法阵边缘持续法伤+回血")
		"沈梦溪":
			if i == 0:
				texts.append("每0.75秒投掷一枚炸弹（可连续，最多5枚）")
				fx.append({"t": "msup", "v": 48.0 + 12.0 * lv, "d": float(min(5, hero.stat))})   # 投掷期间自身移速+48+12Lv（固定数值型加速，与施放buff同式）
			elif i == 1:
				fx.append({"t": "knockup", "v": 1.0})
				fx.append({"t": "msup", "v": 36.0 + 9.0 * lv, "d": 4.0})   # 引燃4秒窗口内自身移速+36+9Lv（固定数值型加速，与施放buff同式）
				texts.append("消耗1枚炸弹点燃引信4秒：期间移速提升；再次点击或到期自动引爆——对周围敌人造成伤害并击飞，自身短暂浮空")
			else:
				count = 3 + lv; unit = "发(小弹50%)"
				texts.append("轰出主炸弹，另分裂出多枚小炸弹轰炸周围")
		"不知火舞":
			if i == 0:
				fx.append({"t": "knockup", "v": 0.75})
				texts.append("向前冲拳并小位移")
			elif i == 1:
				fx.append({"t": "slow", "v": 90.0, "d": 0.5})
				fx.append({"t": "mrdn", "v": 30.0 + 20.0 * lv, "d": 3.0})   # 魔抗-（30+20·Lv）点数值削减 · 3秒（数值类，区别于百分比）
			else:
				fx.append({"t": "atkdn", "v": 15.0 + 5.0 * lv, "d": 2.5})   # 攻击-（15+5Lv）% · 2.5秒
				texts.append("向前突进横扫，击退并推进沿途敌人；命中削减敌人攻击力")
		"甄姬":
			if i == 0:
				fx.append({"t": "knockup", "v": 1.0})
				texts.append("自身位于圈内会获得强化（额外法术范围伤害）")
			elif i == 1:
				count = 4 + int(floor((lv - 1.0) / 2.0)); unit = "跳"
				texts.append("水球命中后弹跳至附近敌人（同目标不重复）")
			else:
				count = 5; unit = "波"
				fx.append({"t": "slow", "v": 12.5 + 12.5 * lv, "d": 1.5})
				texts.append("水球直接命中另有高额直接伤害；水区持续造成范围法伤")
		"铠":
			if i == 0:
				fx.append({"t": "slow", "v": 90.0, "d": 2.0})
			elif i == 1:
				count = 2; unit = "段"
				fx.append({"t": "knockup", "v": 1.0})
				texts.append("第二段挥砍额外击飞1秒")
			else:
				fx.append({"t": "asup", "v": 50.0 + 50.0 * lv, "d": 8.0})   # 大招期间攻速+50+50Lv%
				fx.append({"t": "msup", "v": 50.0, "d": 8.0})   # 大招期间自身移速+50（固定数值型加速，与施放buff同式）
				texts.append("挥出范围魔刃；随后8秒每0.5秒灼烧身边敌人并回复自身")
		"亚瑟":
			if i == 0:
				fx.append({"t": "selfspeed", "v": 30.0, "d": 3.0})
				texts.append("强化下一次普攻（额外物理伤害）")
			elif i == 1:
				texts.append("圣盾环绕，每0.5秒对身边敌人造成一次物理伤害")
			else:
				fx.append({"t": "knockup", "v": 0.5})
				texts.append("位移至目标身旁并击飞周围敌人；落点留下圣印圈持续5秒，每秒对圈内敌人造成法术伤害（防御塔除外）")
		"太乙真人":
			var q_dur = min(hero.taiyi_q_timer, 5.0)
			if i == 0:
				fx.append({"t": "selfspeed", "v": 20.0, "d": 5.0})
				fx.append({"t": "shield", "v": 250.0 + 50.0 * lv})
				fx.append({"t": "stun", "v": 0.5 + (0.03 + hero.skill_levels[0] * 0.013) * q_dur})
				texts.append("引导蓄力期间自身提速20%，命中额外范围爆炸（引导可被拖拽调整）")
			elif i == 1:
				fx.append({"t": "stun", "v": 0.5})
			else:
				fx.append({"t": "heal", "v": 850.0 + 750.0 * lv + 2.0 * ap})   # 保护3秒内阵亡原地复活回复850+750Lv+2AP（数值同施放式）
				texts.append("3秒内自身与范围内血量最低队友阵亡将原地复活（回复850+750Lv+2AP生命）")
		"东皇太一":
			if i == 0:
				texts.append("命中敌人积累能量体并回复法力；拥有3颗时回血120+30Lv+0.6AP")
				if hero.donghuang_orbs >= 3:
					fx.append({"t": "heal", "v": 120.0 + 30.0 * lv + 0.6 * ap})   # 满3球：Q命中回血（数值同施放式）
			elif i == 1:
				fx.append({"t": "selfspeed", "v": 20.0+10.0*hero.donghuang_orbs, "d": 1.0})
				count = hero.donghuang_orbs; unit = "发"   # 发数=当前能量体数（每颗能量体发射一发，与子弹数/预览环同步）
				texts.append("发射当前全部能量体（1-3发）；第1发减速、第2发强减速、第3发眩晕1秒")
			else:
				fx.append({"t": "suppress", "v": 2.0})
				texts.append("压制目标英雄期间双方均无法行动；自身大幅提速")
		"李白":
			if i == 0:
				count = 2; unit = "剑"
				fx.append({"t": "stun", "v": 0.5})
				texts.append("向目标方向连续突刺3段（可重按，命中眩晕0.5秒），积累剑气")
			elif i == 1:
				fx.append({"t": "armred", "v": 120.0 + 30.0 * lv, "d": 3.0})   # 剑阵命中削减护甲(120+30·Lv)点·3秒（数值同施放式 _apply_df_buff）
				fx.append({"t": "slow", "v": 90.0, "d": 1.0})
				fx.append({"t": "unsel", "v": 3.0})   # 剑阵期间无法选中/免伤免控（wd_timer=3秒）
				fx.append({"t": "cleanse"})   # 施放瞬间净化自身
				texts.append("施放瞬间净化自身并进入无法选中3秒；剑阵命中削减物理防御、外圈全额伤害并减速90%")
			else:
				count = 5; unit = "段"
				fx.append({"t": "unsel", "v": 2.5})   # 青莲剑歌穿梭期间无法选中/免伤免控（wd_timer=2.5秒）
				texts.append("需4层剑气解锁；对范围内敌人连续穿梭5次（期间无法选中/免伤免控），重复命中伤害递减")
		"兰陵王":
			if i == 0:
				count = 2; unit = "发"
				texts.append("对身边最近2名敌人分别造成伤害；仅命中1人时该伤害翻倍")
			elif i == 1:
				fx.append({"t": "slow", "v": 90.0, "d": 1.5})
				texts.append("飞镖穿透并附加印记：下一次命中追加额外伤害")
			else:
				texts.append("向前冲刺3.5米，沿途贯穿敌人造成巨额伤害")
		"张飞":
			if i == 0:
				texts.append("蓄力后向前方锥形范围挥击")
			elif i == 1:
				fx.append({"t": "shield", "v": 480.0 + 120.0 * lv + 0.12 * bh})
				texts.append("跃向目标点，为自身与附近友军附加护盾（持续5秒）")
			else:
				fx.append({"t": "shield", "v": 850.0 + 850.0 * lv + 0.35 * bh})
				texts.append("变身15秒；向面前锥形区域咆哮，命中击退5米并眩晕1.5秒")
		"安琪拉":
			if i == 0:
				count = 5; unit = "发"
				texts.append("5颗火球向目标点汇聚")
			elif i == 1:
				fx.append({"t": "stun", "v": 1.0})
				fx.append({"t": "slow", "v": 30.0 + 6.0 * (lv - 1), "d": 1.5})
				texts.append("火焰持续灼烧路径上的敌人（约3秒）")
			else:
				fx.append({"t": "shield", "v": 400.0 + 450.0 * lv + 0.88 * ap})
				fx.append({"t": "bt", "v": 3.0})
				texts.append("持续光束3秒（每0.25秒一段伤害）")
		"妲己":
			if i == 0:
				texts.append("宽5米、射程10米的冲击波贯穿直线敌人")
			elif i == 1:
				fx.append({"t": "stun", "v": 1.5})
				texts.append("锁定最近敌人，命中眩晕1.5秒")
			else:
				count = 5; unit = "团"
				texts.append("5团狐火自动飞向周围敌人（0.3秒间隔，可集火同一目标）")
		"小乔":
			if i == 0:
				count = 2; unit = "段"
				texts.append("扇子飞出再飞回，多次命中伤害逐次衰减（最低50%）")
			elif i == 1:
				fx.append({"t": "knockup", "v": 1.5})
			else:
				count = 8; unit = "波"
				texts.append("6秒内降下8波流星（每波至多2颗）；同目标重复命中-50%，最多4颗")
		"鲁班七号":
			if i == 0:
				fx.append({"t": "slow", "v": 25.0 + 5.0 * (lv - 1), "d": 2.0})
			elif i == 1:
				texts.append("全图超远狙击，命中击退近身目标；目标损失生命越多伤害越高")
			else:
				fx.append({"t": "slow", "v": 25 + 12.5 * (lv - 1), "d": 1.0})
				texts.append("飞艇持续轰炸14秒（每秒1次，范围随指示移动），命中减速")
		"夏侯惇":
			if i == 0:
				fx.append({"t": "slow", "v": 25.0 + 5.0 * (lv - 1), "d": 2.0})
				count = 2; unit = "段"
				fx.append({"t": "knockup", "v": 1.0})
				texts.append("第一段刃风减速（25+5Lv%）·2秒；窗口内重按触发第二段重击并击飞")
			elif i == 1:
				fx.append({"t": "shield", "v": 500.0 + (lv - 1) * 100.0 + 0.12 * bh})
				texts.append("范围法伤并附加护盾（5秒）；强化之后3次普攻附带回血")
			else:
				fx.append({"t": "stun", "v": 1.0})
				count = 2; unit = "段"
				texts.append("向目标方向冲刺并眩晕命中的第一个敌人")
		"后羿":
			if i == 0:
				texts.append("强化下一次普攻：分裂射出多支箭")
			elif i == 1:
				fx.append({"t": "slow", "v": 25.0 + 5.0 * (lv - 1), "d": 2.0})
				texts.append("范围爆炸：中心1.5米全额伤害，外圈伤害减半")
			else:
				fx.append({"t": "slow", "v": 30.0 + 15.0 * (lv - 1), "d": 1.0})
				fx.append({"t": "selfspeed", "v": 10.0 + 5.0 * lv, "d": 5.0})   # 命中后自身移速+10+5Lv%·5秒
				texts.append("全图神箭；命中距离越远眩晕时间越长")
		"大禹":
			if i == 0:
				texts.append("放置一座戍鼎自动攻击周围敌人（可同时3座）；自身加速75%（2.5秒衰减）")
			elif i == 1:
				fx.append({"t": "knockup", "v": 0.75})
				texts.append("直线贯穿水刃；命中近身敌人击退2米；强化下一次普攻")
			else:
				fx.append({"t": "knockup", "v": 1.0})
				texts.append("第一段落地AoE击飞并留下乾鼎；可再按第二段霸体传送到鼎处并震荡减速")
		"王昭君":
			if i == 0:
				fx.append({"t": "slow", "v": int(18.3 + 1.8 * hero.level), "d": 2.0})
				fx.append({"t": "asdn", "v": int(18.3 + 1.8 * hero.level), "d": 2.0})   # 冰冷削减攻速20+5Lv% ·2秒（配合二技能冰冻可触发额外伤害）
			elif i == 1:
				fx.append({"t": "freeze", "v": 2.5})
				texts.append("冰冻仅阻止移动；对受冰冷影响的目标额外造成120+30Lv+0.2AP伤害")
			else:
				fx.append({"t": "slow", "v": int(18.3 + 1.8 * hero.level), "d": 2.0})
				fx.append({"t": "asdn", "v": int(18.3 + 1.8 * hero.level), "d": 2.0})   # 冰冷削减攻速20+5Lv% ·2秒（配合二技能冰冻可触发额外伤害）
				fx.append({"t": "shield", "v": 450.0 + hero.level* 30.0 + 0.58 * ap})
				texts.append("持续暴风雪5秒（每0.5秒一段·共10段）；并刷新被动护盾(450·一技能等级+0.58AP)")
		"刘禅":
			if i == 0:
				fx.append({"t": "shield", "v": 520.0 + 130.0 * lv + 0.14 * bh})
				fx.append({"t": "selfspeed", "v": 40.0 + 10.0 * lv, "d": 3.0})
				texts.append("并获得一次强化普攻")
			elif i == 1:
				fx.append({"t": "stun", "v": 1.0})
			else:
				fx.append({"t": "slow", "v": 7.5 + 7.5 * lv, "d": 0.5})
				texts.append("持续旋转3秒（每0.5秒一段伤害）；对防御塔也造成伤害并使其短暂失效")
		"孙悟空":
			if i == 0:
				fx.append({"t": "selfspeed", "v": 40.0, "d": 1.0})
				texts.append("开启1.5秒格挡窗口（格挡一次伤害/攻击）并获得强化普攻")
			elif i == 1:
				texts.append("位移冲锋；对血量低于15%的小兵/野怪直接斩杀")
			else:
				fx.append({"t": "knockup", "v": 1.0})
				texts.append("范围击飞并附加3层印记（6秒）")
		"李元芳":
			if i == 0:
				fx.append({"t": "asup", "v": 35.0 + 7.0 * (lv - 1), "d": 4.0})   # 施放即刻攻速+（35+7·Lv）% · 4秒，并+50攻击距离
				texts.append("标记目标：普攻/大招风暴可叠暗印（至多4层），4秒后或满4层爆炸造成范围伤害，每层伤害相等")
			elif i == 1:
				fx.append({"t": "slow", "v": 15.0 + 3.0 * (lv - 1), "d": 2.0})
				fx.append({"t": "unsel", "v": 0.7})
				texts.append("掷出飞轮并遁地（期间无法选中/免伤免控）；飞轮沿位移轨迹与前方贯通，对路径上所有敌人造成首段伤害+减速；位移全程（起点至终点）留下燃痕持续伤害+减速")
			else:
				fx.append({"t": "slow", "v": 25.0 + 12.5 * (lv - 1), "d": 0.8})
				texts.append("掷出巨型飞刃自英雄滑向释放方向，对滑行路径上所有敌人造成伤害+减速；到点后于落点形成风暴（5.4秒/每0.54秒一跳）；内圈伤害翻倍并可叠暗印")
		"元流之子":
			if i == 0:
				texts.append("汇流为一：以自身为中心，对周围敌人造成物理伤害并将其击退（约1.5米/短击飞），回复自身生命；附近每名友方英雄/友方小兵使回复+25%且「流」额外+1（至多4名）；获得基础5层「流」（上限9），破釜/万箭剩余冷却时间减少50%。「流」不使用会流失：闲置5秒后先失1层，之后每秒1层，用流（普攻或技能）即重置5秒")
			elif i == 1:
				texts.append("破釜之箭：锁敌型单体必中——施放时朝摇杆方向位移2.5米，巨型弩箭自动追踪锁定目标（无目标则空放短箭）；命中全额伤害，仅对非英雄单位击退约1.5米（短击飞）；拥有4层「流」可连续施放（参连/凌空）")
			else:
				count = 7 + 3 * (lv - 1); unit = "支"
				fx.append({"t": "selfspeed", "v": 20.0 + 10.0 * (lv - 1), "d": 2.0})
				texts.append("万箭齐发：从自身向指定区域连续射出追踪箭，每3支箭视作1次普攻，可触发普攻类装备效果（闪电匕首/末世等）；释放获得移速提升，拥有5层「流」可立即再施放一次")
		"英睿":
			if i == 0:
				count = 2; unit = "段"
				fx.append({"t": "knockup", "v": 0.75})
				texts.append("第一段命中敌人后才追加第二段巧乐兹（同等伤害并击飞）")
			elif i == 1:
				count = 3; unit = "段"
				texts.append("3段肘击（可连续重按重施）；贴身距离伤害最高+40%")
			else:
				fx.append({"t": "armup", "v": 160.0 + 50.0 * lv, "d": 14.0})   # 变身护甲+160+50Lv ·14秒
				fx.append({"t": "mrup", "v": 100.0 + 40.0 * lv, "d": 14.0})   # 变身魔抗+100+40Lv ·14秒
				texts.append("变身14秒：双抗提升，普攻附加额外伤害")
	res["count"] = count
	res["unit"] = unit
	res["fx"] = fx
	res["texts"] = texts
	return res


# 该技能槽施放后是否附带“强化普攻”效果（用于移动端技能键上在读数最前加一枚金色普攻小剑，
# 区别于纯直接伤害技能）。口径与 apply_skills 中实际写入的强化普攻标记一致：
# 亚瑟Q / 刘禅Q / 孙尚香Q / 后羿Q（槽0）；铠W / 夏侯惇W / 大禹W（槽1）；孙悟空三个技能都附加
func skill_grants_enhanced_aa(hero_name: String, i: int) -> bool:
	match hero_name:
		"亚瑟", "刘禅", "孙尚香", "后羿":
			return i == 0
		"孙悟空":
			return i >= 0 and i <= 2
		"铠", "夏侯惇", "大禹":
			return i == 1
	return false


# 冰冷效果：同时削减移速和攻速
func _apply_freezing(target: GameEntity,level:int):
	target.apply_move_pct_buff("ms_slow", 2.0, -0.25, true)     # 25%减速
	target.apply_attack_pct_buff("as_slow", 2.0, -(0.20+0.05*level), true)  # 25%攻速削减

func get_pos(hero:Hero,range):
	var target_pos = hero.global_position + Vector3.FORWARD * 5.0
	var cam = hero.get_viewport().get_camera_3d()
	if cam:
		var mouse_pos = hero.get_viewport().get_mouse_position()
		var from = cam.project_ray_origin(mouse_pos)
		var to = from + cam.project_ray_normal(mouse_pos) * 100
		var space_state = hero.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 2
		var result = space_state.intersect_ray(query)
		if result: target_pos = result.position

	# 限制施法距离
	if hero.global_position.distance_to(target_pos) > range:
		var dir = (target_pos - hero.global_position).normalized()
		target_pos = hero.global_position + dir * range
	return  target_pos
func create_bullet(base_dmg,phy_bonus_ratio,mag_bonus_ratio,level_bonus,is_magic,hero:Hero,dir,skill_id)-> Bullet:
	var phy_dmg = hero.actual_attack_damage
	var mag_dmg = hero.actual_ability_power
	var is_crit = randf() < hero.actual_crit_chance
	if is_crit:
		phy_dmg *= hero.actual_crit_damage
		mag_dmg *= hero.actual_crit_damage
	var bullet = Bullet.new()
	bullet.skill_id = skill_id
	bullet.speed = 10.0
	bullet.radius = 0.8
	bullet.scale = Vector3(1.5, 1.5, 1.5)
	bullet.damage = base_dmg+phy_bonus_ratio*phy_dmg+mag_bonus_ratio*mag_dmg+level_bonus
	if hero.display_name == "马超":
		bullet.damage+=hero.bonus_move_speed
		if skill_id == 3:
			bullet.damage+=0.045*(hero.max_health-hero.health)
	bullet.team = hero.team
	bullet.source = hero
	bullet.is_magic = is_magic
	bullet.global_position = hero.global_position + Vector3.UP * 1.0
	# 设置线性飞行参数（需要扩展 Bullet）
	bullet.set_linear(dir, 8)
	return bullet
func create_spell(radius,team,hero_name := "",dur := 0.0)->Node3D:
	# 持续地面区域：交给 Vfx 统一法阵（柔光底盘+旋转符文环+元素装饰），host/client 同一套观感
	return Vfx.ground_zone(float(radius), int(team), str(hero_name), float(dur))
func create_preview(radius,pos,team)->Node3D:
	# 圆形范围预览：柔光圆底 + 亮环 + 呼吸（替代旧纯色 torus）
	var area_preview: Node3D = Vfx.preview_ring(float(radius), int(team))
	area_preview.position = Vfx.ground_pos(pos) + Vector3(0, 0.02, 0)
	return area_preview
func create_machao_spear(pos: Vector3, team: int) -> Node3D:
	var spear: Node3D = HeroWeapons.spear_marker(team)
	spear.position = Vfx.ground_pos(pos)
	spear.add_to_group("terrains")
	return spear

func create_terrain(shape_id,radius,pos,team)->Node3D:
	if shape_id == 1:
		var terrain = Node3D.new()
		terrain.position = pos
		var mesh = MeshInstance3D.new()
		mesh.mesh = CylinderMesh.new()
		mesh.mesh.top_radius = 0.2*radius
		mesh.mesh.bottom_radius = radius
		mesh.mesh.height = 3*radius
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		terrain.add_child(mesh)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color.RED if team == 1 else Color.BLUE
		mat.albedo_color.a = 0.3
		mesh.set_surface_override_material(0, mat)
		var col = CollisionShape3D.new()
		col.shape = SphereShape3D.new()
		col.shape.radius = 0.6*radius
		terrain.add_child(col)
		terrain.add_to_group("terrains")
		
		return terrain
	else:
		return null

# 创建水花溅射效果（甄姬2技能弹射用）
func _create_water_splash(parent: Node, pos: Vector3):
	var splash_root = Node3D.new()
	splash_root.position = pos + Vector3.UP * 0.5
	parent.add_child(splash_root)
	# 扩展水环
	var ring = MeshFactory.create_torus_ring(0.3, 0.8, Color(0.2, 0.5, 1.0, 0.8), true, 0.7, true)
	ring.position = Vector3(0, 0.5, 0)
	splash_root.add_child(ring)
	var tw = splash_root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(2.5, 2.5, 2.5), 0.35)
	tw.tween_property(ring.material_override, "albedo_color:a", 0.0, 0.35)
	# 飞溅水滴
	for i in range(8):
		var angle = deg_to_rad(i * 45.0)
		var droplet = MeshFactory.create_sphere(0.12, Color(0.3, 0.6, 1.0, 0.8), true)
		droplet.position = Vector3(0, 0.5, 0)
		splash_root.add_child(droplet)
		var dx = cos(angle) * (1.0 + randf() * 1.5)
		var dz = sin(angle) * (1.0 + randf() * 1.5)
		var dt = splash_root.create_tween()
		dt.set_parallel(true)
		dt.tween_property(droplet, "position:x", droplet.position.x + dx, 0.35)
		dt.tween_property(droplet, "position:z", droplet.position.z + dz, 0.35)
		dt.tween_property(droplet, "position:y", droplet.position.y + 1.5 + randf(), 0.35)
		dt.tween_property(droplet.material_override, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(splash_root.queue_free).set_delay(0.35)
	# #43 网络 FX：水花闪（0.35s 一次性，固定水系蓝）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.push_net_fx(NetSession.FX_WATER_SPLASH, Vector3(pos.x, 0.0, pos.z), -1, 2.0, 0.35)

# 创建水区域（甄姬大招用）
# 创建水区域（甄姬大招用）
func _create_water_zone(parent: Node, pos: Vector3, radius: float) -> Node3D:
	var zone_root = Node3D.new()
	zone_root.position = pos
	# 水面圆盘（抬高到地面之上并加亮：原先贴地且颜色与河道同色，完全不可见）
	var pool = MeshInstance3D.new()
	pool.mesh = CylinderMesh.new()
	pool.mesh.top_radius = radius
	pool.mesh.bottom_radius = radius
	pool.mesh.height = 0.3
	pool.position.y = 0.2
	var pool_mat = StandardMaterial3D.new()
	pool_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.6)
	pool_mat.emission_enabled = true
	pool_mat.emission = Color(0.3, 0.65, 1.0, 0.6)
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.material_override = pool_mat
	zone_root.add_child(pool)
	# 边缘亮环（不透明发光，俯视下勾勒水区轮廓）
	var rim = MeshFactory.create_torus_ring(radius - 0.2, radius, Color(0.6, 0.9, 1.0), true, 1.0, true)
	rim.position.y = 0.3
	zone_root.add_child(rim)
	# 冰晶环（加粗加高：原先半径仅0.06-0.12，俯视角度几乎不可见）
	for i in range(10):
		var angle = deg_to_rad(i * 36.0)
		var crystal = MeshFactory.create_cylinder(0.15, 0.3, 1.6, Color(0.7, 0.9, 1.0), 1.0)
		crystal.position = Vector3(cos(angle) * (radius - 0.3), 0.8, sin(angle) * (radius - 0.3))
		zone_root.add_child(crystal)
	# 中央漩涡环（旋转）
	var vortex = MeshFactory.create_torus_ring(0.2, 0.6, Color(0.6, 0.9, 1.0), true, 1.0, true)
	vortex.position.y = 0.5
	zone_root.add_child(vortex)
	var vt = create_tween()
	vt.tween_property(vortex, "rotation_degrees:y", 720.0, 5.0).as_relative()
	parent.add_child(zone_root)
	# #43 网络 FX：水域地面盘（persist ~4s，固定水系蓝，颜色与阵营无关）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.push_net_fx(NetSession.FX_WATER_ZONE, Vector3(pos.x, 0.0, pos.z), -1, radius, 4.0, "甄姬")
	return zone_root
func _create_water_pulse(parent: Node, pos: Vector3, radius: float, caster = null):
	# 扩展冲击波
	var wave = MeshFactory.create_torus_ring(0.2, 0.5, Color(0.3, 0.6, 1.0, 0.7), true, 0.6, true)
	wave.position = pos + Vector3.UP * 0.3
	parent.add_child(wave)
	var wt = create_tween()
	wt.set_parallel(true)
	wt.tween_property(wave, "scale", Vector3(radius / 0.5, radius / 0.5, radius / 0.5), 0.5)
	wt.tween_property(wave.material_override, "albedo_color:a", 0.0, 0.5)
	wt.tween_callback(wave.queue_free).set_delay(0.5)
	# 水柱喷发
	var spout = MeshFactory.create_cylinder(0.3, 0.6, 0.5, Color(0.25, 0.55, 0.9, 0.7))
	spout.position = pos + Vector3.UP * 0.25
	parent.add_child(spout)
	var st = create_tween()
	st.set_parallel(true)
	st.tween_property(spout, "scale", Vector3(0.2, 6.0, 0.2), 0.25)
	st.tween_property(spout.material_override, "albedo_color:a", 0.0, 0.35).set_delay(0.1)
	st.tween_callback(spout.queue_free).set_delay(0.5)
	# #43 网络 FX：扩散水圈（0.5s 一次性，固定水系蓝）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.push_net_fx(NetSession.FX_WATER_PULSE, Vector3(pos.x, 0.0, pos.z), -1, radius, 0.5)
	# 溅射粒子
	for i in range(12):
		var angle = deg_to_rad(i * 30.0)
		var drop = MeshFactory.create_sphere(0.1, Color(0.3, 0.6, 1.0, 0.8), true)
		drop.position = pos + Vector3.UP * 0.5
		parent.add_child(drop)
		var dx = cos(angle) * (1.5 + randf() * 2.5)
		var dz = sin(angle) * (1.5 + randf() * 2.5)
		var dt = create_tween()
		dt.set_parallel(true)
		dt.tween_property(drop, "position:x", drop.position.x + dx, 0.4)
		dt.tween_property(drop, "position:z", drop.position.z + dz, 0.4)
		dt.tween_property(drop, "position:y", drop.position.y + 2.0 + randf() * 2.0, 0.4)
		dt.tween_property(drop.material_override, "albedo_color:a", 0.0, 0.4)
		dt.tween_callback(drop.queue_free).set_delay(0.4)
		# 冰冻染色：对区域内敌人短暂变色（通过froze_timer利用现有渲染）
		if caster:
			var all_entities = parent.get_tree().get_nodes_in_group("entities")
			for entity in all_entities:
				if entity is Hero and entity.team != caster.team:
					if entity.global_position.distance_to(pos) <= radius:
						entity.froze_timer = max(entity.froze_timer, 0.3)
# ================ 李元芳 技能效果（谍影重重 / 刃遁 / 无间刃风） ================
# lv 现算：Q/W 6级成长（0.4/级CD、等差伤害），R 3级成长（3.0/级CD、等差伤害）。
# 攻速为attack_pct buff、攻距走 bonus_attack_range buff（派生进 attack_range），均4秒；
# 遁地模型由 Hero.gd 每帧处理；暗印储存/叠加/爆炸在 GameEntity.gd。
func _lyf_q(hero, lv: int, pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	# 施放即刻：攻速+35%+7%·Lv；攻击距离buff +50（bonus_attack_range 聚合，可作用于防御塔）
	var as_pct := 0.35 + 0.07 * (lv - 1)
	hero.apply_attack_pct_buff("as_haste", 4.0, as_pct)
	hero.apply_attack_range_buff("lyf_range", 4.0, 50.0)
	if pos == Vector3.ZERO:
		return
	# 种暗印：优先吃瞄准阶段已锁定的实体（拖动轮盘/悬停锁定/联机C_CAST传入，含防御塔）
	var tgt = null
	var plock = hero.pending_skill_target_entity
	if plock != null and is_instance_valid(plock) and plock.health > 0.0 and plock.team != hero.team:
		var pd: float = Vector3(plock.global_position.x, 0.0, plock.global_position.z) \
				.distance_to(Vector3(pos.x, 0.0, pos.z))
		if pd <= 1.8:
			tgt = plock
	# 无锁定：取目标点半径1.2内的最近敌人（兜底，规则同智能施法）
	if tgt == null:
		var best := 1.2
		for e in hero.get_tree().get_nodes_in_group("entities"):
			if e == hero or e.health <= 0.0 or e.team == hero.team:
				continue
			var p0 := Vector3(e.global_position.x, 0.0, e.global_position.z)
			var p1 := Vector3(pos.x, 0.0, pos.z)
			var dd: float = p0.distance_to(p1)
			if dd < best:
				best = dd
				tgt = e
	if tgt != null:
		tgt.lyf_cast_mark(hero)
		# 视觉：真实飞镖本体自李元芳手中飞向目标（随后由暗印环绕表现接管）
		var qcol := Color(1.0, 0.52, 0.16)
		var hpos: Vector3 = hero.global_position + Vector3(0, 1.1, 0)
		var tpos: Vector3 = tgt.global_position + Vector3(0, 1.1, 0)
		Vfx.lyf_throw_dart(hpos, tpos, qcol)
		Vfx.hit_spark(tpos, qcol, Vector3.UP, 1.1)


func _lyf_w(hero, lv: int, _pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	# 位移轨迹 = 本次施放起点(已记录) → 当前落点
	var start: Vector3 = hero.dash_from
	start.y = 0.0
	var end: Vector3 = hero.global_position
	end.y = 0.0
	var seg: Vector3 = end - start
	if seg.length() < 0.1:
		var fwd: Vector3 = -hero.global_transform.basis.z
		seg = Vector3(fwd.x, 0.0, fwd.z).normalized() * 4.5
		end = start + seg
	var nd: Vector3 = seg.normalized()
	# 飞轮（贯通弹）：自位移起点沿方向直线贯穿（至多8米），对路径上所有敌人造成首段伤害+减速15%+3%·Lv · 2秒
	var fly := int(260.0 + 52.0 * (lv - 1) + float(hero.bonus_attack) * 0.8)
	var slow_p := 0.15 + 0.03 * (lv - 1)
	var wheel = create_bullet(fly, 0.0, 0.0, 0, false, hero, nd, 2)
	wheel.slow_per = slow_p
	wheel.slow_dur = 2.0
	wheel.pierce = true
	wheel.global_position = start + Vector3.UP * 1.0   # 从位移起点飞出，覆盖翻滚经过与前方的全部敌人
	hero.get_parent().add_child(wheel)
	# 视觉（刃遁）：刀轮拖尾 + 位移烟尘/速度线 + 出土冲击（纯表现，不改结算）
	var vcol := Color(1.0, 0.52, 0.16)
	var _lyf_bm = hero.get_tree().get_first_node_in_group("battle_manager")
	var _lyf_local: bool = (_lyf_bm != null and _lyf_bm.hero == hero)
	Vfx.attach_trail(wheel, vcol, 0.26, 0.26, 10, Color(1.0, 1.0, 1.0, 0.45))
	Vfx.dash_fx(start, end, vcol, _lyf_local, maxf(start.distance_to(end), 0.6) + 0.8)
	Vfx.cast_burst("李元芳", start, nd)
	Vfx.shockwave(end, 1.35, vcol, 0.34)
	Vfx.hit_spark(end + Vector3.UP * 0.5, vcol, Vector3.UP, 1.1)
	# 遁地：0.7秒无法选中/免伤免控（模型隐藏由 Hero 每帧处理）
	hero.wd_timer = maxf(hero.wd_timer, 0.7)
	hero._lyf_burrow = maxf(hero._lyf_burrow, 0.7)
	# 燃痕：位移全程(起点→终点)灼烧2.9秒，每0.25秒一跳；长边沿轨迹方向，宽0.7
	var trail_len := maxf(start.distance_to(end), 0.3)
	var tick := int(110.0 + 22.0 * (lv - 1) + float(hero.bonus_attack) * 0.3)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# 长轴放在本地 Z（look_at 使 -Z 指向轨迹方向），避免横向摆错角度
	bm.size = Vector3(0.7, 0.06, trail_len)
	box.mesh = bm
	box.position = (start + end) * 0.5 + Vector3(0.0, 0.08, 0.0)
	box.look_at(end + Vector3(0.0, 0.08, 0.0), Vector3.UP)
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(1.0, 0.32, 0.08, 0.55)
	mb.emission_enabled = true
	mb.emission = Color(1.0, 0.35, 0.05, 0.55)
	mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material_override = mb
	hero.get_parent().add_child(box)
	# 双层燃痕：贴地暗焦底 + 加色光带；光带随灼烧时长渐隐，避免"一条粗黑棒"
	mb.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mb.albedo_color = Color(1.0, 0.45, 0.12, 0.62)
	mb.emission = Color(1.0, 0.55, 0.18)
	mb.emission_energy_multiplier = 1.6
	var scorch := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.95, 0.04, trail_len)
	scorch.mesh = sbox
	scorch.position = box.position + Vector3(0.0, 0.01, 0.0)
	scorch.look_at(end + Vector3(0.0, 0.09, 0.0), Vector3.UP)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.16, 0.06, 0.02, 0.75)
	scorch.material_override = sm
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hero.get_parent().add_child(scorch)
	var fade := box.create_tween()
	fade.tween_property(mb, "albedo_color:a", 0.04, 2.9)
	var fade2 := scorch.create_tween()
	fade2.tween_property(sm, "albedo_color:a", 0.18, 2.9)
	var n_tick := int(2.9 / 0.25)
	for i in n_tick:
		if not is_instance_valid(hero) or hero.health <= 0.0:
			box.queue_free()
			scorch.queue_free()
			return
		await hero.get_tree().create_timer(0.25).timeout
		for e in hero.get_tree().get_nodes_in_group("entities"):
			if e == hero or e.health <= 0.0 or e.team == hero.team:
				continue
			if hero._dist_point_segment_h(e.global_position, start, end) <= 0.6:
				e.take_damage(float(tick), hero, false, -82, 0)
				e.apply_move_pct_buff("ms_slow", 1.0, -slow_p, true)
		# 燃痕余烬：沿轨迹随机跳火星，强化"刃风灼烧"的可读性
		if i % 2 == 0:
			var tp: Vector3 = start.lerp(end, float(i + 1) / float(n_tick)) + Vector3.UP * 0.25
			Vfx.hit_spark(tp, vcol, Vector3.UP, 0.55)
	box.queue_free()
	scorch.queue_free()


func _lyf_r(hero, lv: int, pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var start := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	var fwd: Vector3 = -hero.global_transform.basis.z
	var fwd_h := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var aim := pos
	if aim == Vector3.ZERO:
		aim = start + fwd_h * 7.5
	var seg := Vector3(aim.x, 0.0, aim.z) - start
	var L := minf(seg.length(), 8.0)
	if L < 0.5:
		aim = start + fwd_h * 7.5
		seg = Vector3(aim.x, 0.0, aim.z) - start
		L = seg.length()
	var nd := seg.normalized()
	# 巨型飞刃：自英雄沿方向滑向落点（20米/秒，至多0.4秒），滑行沿途每经过一个敌人结算一次首段伤害（判定宽1米、减速0.5秒）
	var hit := int(320.0 + 160.0 * (lv - 1) + float(hero.bonus_attack) * 1.0)
	var slow_p := 0.25 + 0.125 * (lv - 1)
	var ep0 := start + nd * L
	var slide_v := 20.0
	var slide_t := L / slide_v
	var hit_ents: Array = []
	var hit_ts: Array = []
	for e in hero.get_tree().get_nodes_in_group("entities"):
		if e == hero or e.health <= 0.0 or e.team == hero.team:
			continue
		var to := Vector3(e.global_position.x, 0.0, e.global_position.z) - start
		var tt: float = to.dot(nd)
		if tt < 0.0 or tt > L:
			continue
		if (to - nd * tt).length() <= 1.0:
			hit_ents.append(e)
			hit_ts.append(tt)
	var blade = _lyf_slide_blade(hero.get_parent(), start, ep0, slide_t)
	var tree = hero.get_tree()
	for k in hit_ents.size():
		var ent = hit_ents[k]
		var dtime: float = float(hit_ts[k]) / slide_v
		if dtime <= 0.0:
			_lyf_slide_hit(hero, ent, hit, slow_p)
		else:
			tree.create_timer(dtime).timeout.connect(_lyf_slide_hit.bind(hero, ent, hit, slow_p))
	# 等飞刃滑到落点后，才展开落点风暴（原 5.4秒/10跳/内圈翻倍/叠暗印 语义不变）
	await tree.create_timer(slide_t).timeout
	if blade != null and is_instance_valid(blade):
		blade.queue_free()
	if not is_instance_valid(hero) or hero.health <= 0.0:
		return
	var dot := int(140.0 + 70.0 * (lv - 1) + float(hero.bonus_attack) * 0.4)
	var zone = _lyf_storm_visual(hero.get_parent(), ep0, 3.0)
	for i in 10:
		if not is_instance_valid(hero) or hero.health <= 0.0:
			zone.queue_free()
			return
		await tree.create_timer(0.5).timeout
		for e in tree.get_nodes_in_group("entities"):
			if e == hero or e.health <= 0.0 or e.team == hero.team:
				continue
			var d2: float = Vector3(e.global_position.x, 0.0, e.global_position.z).distance_to(ep0)
			if d2 <= 3.0:
				var amt := float(dot) * (2.0 if d2 <= 1.5 else 1.0)
				e.take_damage(amt, hero, false, -81, 0)
				e.apply_move_pct_buff("ms_slow", 0.8, -slow_p, true)
				if e.lyf_mark_stack(hero) > 0:
					e.lyf_add_mark(hero)
	zone.queue_free()


# R落点风暴的简易视觉（暗橙半透明风域 + 亮环 + 中心高亮）
func _lyf_storm_visual(parent: Node, pos: Vector3, radius: float) -> Node3D:
	var zone_root := Node3D.new()
	zone_root.position = pos
	parent.add_child(zone_root)   # 先入树：下面的 create_tween 需要节点在树内
	var pool := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.3
	pool.mesh = cyl
	pool.position.y = 0.2
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1.0, 0.38, 0.08, 0.22)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.35, 0.05, 0.22)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.material_override = pm
	zone_root.add_child(pool)
	var rim = MeshFactory.create_torus_ring(radius - 0.2, radius, Color(1.0, 0.55, 0.15), true, 1.0, true)
	rim.position.y = 0.35
	zone_root.add_child(rim)
	var core = MeshFactory.create_cylinder(radius * 0.5, radius * 0.5, 0.4, Color(1.0, 0.55, 0.2, 0.9), 1.0)
	core.position.y = 0.3
	zone_root.add_child(core)
	# 刃风本体：一圈锯齿刃盘贴着地面持续旋转，让「风域」看起来是刀刃削出来的
	var spin := Node3D.new()
	spin.name = "SawRing"
	spin.position.y = 0.42
	zone_root.add_child(spin)
	var saw := MeshInstance3D.new()
	saw.mesh = MeshFactory.build_saw_wheel(radius - 0.55, radius - 0.12, 0.05, 40, 0.14, 0, 0.0)
	saw.material_override = MeshFactory.blade_metal(Color(0.28, 0.25, 0.22), Color(1.0, 0.45, 0.10), 0.24)
	saw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(saw)
	var saw_edge := MeshInstance3D.new()
	saw_edge.mesh = saw.mesh
	var sem := StandardMaterial3D.new()
	sem.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sem.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sem.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sem.albedo_color = Color(1.0, 0.55, 0.15, 0.4)
	sem.emission_enabled = true
	sem.emission = Color(1.0, 0.45, 0.10)
	sem.emission_energy_multiplier = 2.4
	sem.cull_mode = BaseMaterial3D.CULL_DISABLED
	saw_edge.material_override = sem
	saw_edge.scale = Vector3(1.04, 1.04, 2.0)
	saw_edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(saw_edge)
	spin.rotation.x = -PI * 0.5   # 刀盘放平贴地
	var saw_tw := spin.create_tween()
	saw_tw.set_loops()
	saw_tw.tween_property(spin, "rotation:y", TAU, 1.1).from(0.0).set_trans(Tween.TRANS_LINEAR)
	# #43 网络 FX：风暴地面域（persist ~4s，固定暗橙）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.push_net_fx(NetSession.FX_LYF_STORM, Vector3(pos.x, 0.0, pos.z), -1, radius, 4.0, "李元芳")
	return zone_root


# R巨型飞刃滑行视觉：写实向锯齿刃轮 —— 金属刀盘（锯齿环 + 4 片外扩巨刃）+ 刃口加色描边
# + 双层金属轮毂 + 能量核 + 内环光带 + 地面热环，滚动方向沿滑行方向，滚动中自转。
func _lyf_slide_blade(parent: Node, a: Vector3, b: Vector3, dur: float) -> Node3D:
	var root := Node3D.new()
	root.name = "LyfSlideBlade"
	root.position = Vector3(a.x, 1.05, a.z)
	var col := Color(1.0, 0.55, 0.15)
	# 朝向：本地 +X = 滑行方向，本地 +Z = 刃轮法线（侧向），绕本地 Z 自转 = 滚轮转动
	var nd := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if nd.length() < 0.01:
		nd = Vector3.FORWARD
	nd = nd.normalized()
	root.basis = Basis(nd, Vector3.UP, Vector3(-nd.z, 0.0, nd.x))
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	# 1) 金属刀盘：锯齿外缘环 + 4 片巨刃（封闭实体壳，非纸片）
	var disc_mesh := MeshFactory.build_saw_wheel(0.92, 1.34, 0.11, 28, 0.14, 4, 0.62)
	var disc := MeshInstance3D.new()
	disc.name = "Blades"
	disc.mesh = disc_mesh
	disc.material_override = MeshFactory.blade_metal(Color(0.26, 0.24, 0.22), Color(1.0, 0.45, 0.10), 0.22)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(disc)
	# 2) 刃口加色描边（同网格微放大）
	var edge := MeshInstance3D.new()
	edge.name = "Edge"
	edge.mesh = disc_mesh
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.albedo_color = Color(1.0, 0.5, 0.12, 0.30)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.42, 0.08)
	em.emission_energy_multiplier = 2.6
	em.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge.material_override = em
	edge.scale = Vector3(1.035, 1.035, 1.8)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(edge)
	# 3) 双层金属轮毂 + 能量核
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.30
	hub_mesh.bottom_radius = 0.34
	hub_mesh.height = 0.34
	hub_mesh.radial_segments = 16
	hub.mesh = hub_mesh
	hub.material_override = MeshFactory.blade_metal(Color(0.34, 0.30, 0.24), Color(1.0, 0.5, 0.12), 0.28)
	hub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(hub)
	# 立方轴柄：轮辐感
	for k in range(4):
		var spoke := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.62, 0.055, 0.11)
		spoke.mesh = sb
		spoke.material_override = MeshFactory.blade_metal(Color(0.30, 0.26, 0.22), Color(1.0, 0.5, 0.12), 0.3)
		spoke.position = Vector3(cos(TAU * float(k) / 4.0) * 0.34, sin(TAU * float(k) / 4.0) * 0.34, 0.0)
		spoke.rotation.z = TAU * float(k) / 4.0
		spoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spin.add_child(spoke)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.24
	core_mesh.height = 0.48
	core_mesh.radial_segments = 14
	core_mesh.rings = 8
	core.mesh = core_mesh
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.albedo_color = Color(1.0, 0.72, 0.28, 0.85)
	cm.emission_enabled = true
	cm.emission = Color(1.0, 0.55, 0.15)
	cm.emission_energy_multiplier = 3.2
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spin.add_child(core)
	# 4) 内环光带（不随刀盘转，做出「能量束箍住刀轮」的层次）
	var halo := MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 1.0
	halo_mesh.outer_radius = 1.08
	halo_mesh.rings = 32
	halo_mesh.ring_segments = 8
	halo.mesh = halo_mesh
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_color = Color(1.0, 0.62, 0.22, 0.55)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.5, 0.12)
	hm.emission_energy_multiplier = 2.2
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	# 5) 地面热环（贴地，宽于刃轮直径，读得出「贴地削过」）
	var heat := MeshFactory.create_torus_ring(1.05, 1.45, Color(1.0, 0.45, 0.10), true, 0.45, true)
	heat.position = Vector3(0.0, -0.92, 0.0)
	root.add_child(heat)
	parent.add_child(root)
	if dur > 0.0:
		var tw := root.get_tree().create_tween()
		tw.set_parallel(true)
		tw.tween_property(root, "position", Vector3(b.x, 1.05, b.z), dur).set_trans(Tween.TRANS_LINEAR)
		# 自转：滚动方向与滑行一致（本地 Z 轴 = 轮轴）
		tw.tween_property(spin, "rotation:z", -TAU * 3.0, dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(halo, "rotation:z", TAU * 1.5, dur).set_trans(Tween.TRANS_LINEAR)
	return root


# R飞刃滑行沿途命中结算（每目标在飞刃到达其位置时触发一次）
func _lyf_slide_hit(hero, e, hit: int, slow_p: float) -> void:
	if hero == null or not is_instance_valid(hero) or hero.health <= 0.0:
		return
	if e == null or not is_instance_valid(e) or e.health <= 0.0 or e.team == hero.team:
		return
	e.take_damage(float(hit), hero, false, -81, 0)
	e.apply_move_pct_buff("ms_slow", 0.5, -slow_p, true)


# ================ 元流之子 技能效果（汇流为一 / 破釜之箭 / 万箭齐发） ================
func _yuanliu_flow_pool(parent: Node, pos: Vector3, radius: float) -> Node3D:
	var zone_root := Node3D.new()
	zone_root.position = pos
	var pool := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.24
	pool.mesh = cyl
	pool.position.y = 0.16
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.3, 0.8, 1.0, 0.26)
	pm.emission_enabled = true
	pm.emission = Color(0.3, 0.75, 1.0, 0.26)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool.material_override = pm
	zone_root.add_child(pool)
	var rim := MeshFactory.create_torus_ring(maxf(radius - 0.25, 0.2), radius, Color(0.35, 0.85, 1.0), true, 1.0, true)
	rim.position.y = 0.3
	zone_root.add_child(rim)
	parent.add_child(zone_root)
	# #43 网络 FX：元流区域池（persist ~3.5s，固定青色）
	if NetSession.mode == NetSession.Mode.HOST:
		NetSession.push_net_fx(NetSession.FX_YL_POOL, Vector3(pos.x, 0.0, pos.z), -1, radius, 3.5, "元流之子")
	return zone_root


func _yuanliu_q(hero, lv: int, pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	# 汇流为一：AOE 中心永远是自身（不再以瞄准点为中心）
	var c0 := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	# 范围内敌方物理伤害（100+20·(Lv-1)+25%额外AD）
	var dmg := int(100.0 + 20.0 * (lv - 1) + float(hero.bonus_attack) * 0.25)
	for e in hero.get_tree().get_nodes_in_group("entities"):
		if e == hero or e.health <= 0.0 or e.team == hero.team:
			continue
		if Vector3(e.global_position.x, 0.0, e.global_position.z).distance_to(c0) <= 3.5:
			e.take_damage(float(dmg), hero, false, -60, 0)
			# 汇流为一·击退：命中范围内全体敌人自 c0 中心弹开约1.5米 + 0.3秒短击飞（塔除外）
			if not (e is Turret):
				var push_dir := Vector3(e.global_position.x - c0.x, 0.0, e.global_position.z - c0.z)
				if push_dir.length() < 0.05:
					push_dir = Vector3(-hero.global_transform.basis.z.x, 0.0, -hero.global_transform.basis.z.z).normalized()
				var push_n := push_dir.normalized()
				e.global_position = Vector3(e.global_position.x + push_n.x * 1.5, 0.5, e.global_position.z + push_n.z * 1.5)
				e.knockup_timer = maxf(e.knockup_timer, 0.3)
				if e is Hero:
					hero.cc_duration_dealt += 0.3
	# 附近友军（自身为心，半径5可调）：每名友方英雄/友方小兵使回复 +25%、「流」额外 +1（封顶4名）
	var ally_radius := 5.0
	var allies := 0
	var hero_flat := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	for e in hero.get_tree().get_nodes_in_group("entities"):
		if e == hero or e.health <= 0.0 or e.team != hero.team:
			continue
		if not (e is Hero or e is Minion):
			continue
		if Vector3(e.global_position.x, 0.0, e.global_position.z).distance_to(hero_flat) <= ally_radius:
			allies += 1
	var ally_n := mini(allies, 4)
	# 自疗：60+12·(Lv-1)+15%额外AD，× (1+0.25·N)
	if hero.health > 0.0:
		var base_heal := 60.0 + 12.0 * (lv - 1) + float(hero.bonus_attack) * 0.15
		hero._apply_healing(int(base_heal * (1.0 + 0.25 * float(ally_n))))
	# 流 +5+N（0~9），破釜/万箭剩余冷却减半；获得「流」→ 重置 5 秒闲置窗口
	hero.yuanliu_flow = mini(hero.yuanliu_flow + 5 + ally_n, 9)
	hero.yuanliu_flow_activity()
	if hero.skill_cooldowns.size() > 2:
		hero.skill_cooldowns[1] *= 0.5
		hero.skill_cooldowns[2] *= 0.5
	# 视觉：水流漩涡扩散
	var zone = _yuanliu_flow_pool(hero.get_parent(), c0, 3.5)
	var tw: Tween = hero.get_tree().create_tween()
	tw.tween_property(zone, "scale", Vector3(1.6, 1.6, 1.6), 0.5)
	tw.parallel().tween_property(zone, "position:y", 0.5, 0.5)
	tw.tween_callback(zone.queue_free)


func _yuanliu_w(hero, lv: int, pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	# 破釜之箭为【锁敌型单体必中】技能（非直线/非贯穿）：位移已由 Hero._finish_casting
	# 沿摇杆方向滑移 2.5m 完成；此处锁定一个敌人，弩箭追踪命中造成全额伤害 + 1.5m 小击退。
	var dmg := int(480.0 + 96.0 * (lv - 1) + float(hero.bonus_attack) * 1.2)
	var origin := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	# 取锁：优先 type0 瞄准选中的实体（悬停/拖拽/C_CAST 传入）；无效则 6.5m 内最近敌方单位
	var target: GameEntity = null
	var locked = hero.pending_skill_target_entity
	if locked != null and is_instance_valid(locked) and locked.health > 0.0 and locked.team != hero.team:
		target = locked
	if target == null:
		target = hero._get_attack_target(6.5, false)
	var parent: Node = hero.get_parent()
	if target == null:
		# 无目标：向前甩出一支短箭（仅视觉，无伤害），避免空技能毫无反馈
		var fwd0: Vector3 = Vector3(-hero.global_transform.basis.z.x, 0.0, -hero.global_transform.basis.z.z).normalized()
		var whiff_aim := origin + fwd0 * 5.0
		var whiff := MeshFactory.create_sphere(0.45, Color(0.7, 0.95, 1.0), true, 0.5)
		whiff.global_position = origin + Vector3.UP * 0.5
		parent.add_child(whiff)
		var wtw: Tween = hero.get_tree().create_tween()
		wtw.tween_property(whiff, "global_position", whiff_aim + Vector3.UP * 0.5, 0.3)
		wtw.tween_callback(whiff.queue_free)
		return
	# 视觉：水色前导弩箭朝目标追踪收敛（每帧重取目标当前位置 → 必中，目标被击飞/位移也不脱靶）
	var lead := MeshFactory.create_sphere(0.55, Color(0.7, 0.95, 1.0), true, 0.6)
	lead.global_position = origin + Vector3.UP * 0.5
	parent.add_child(lead)
	for _i in range(16):
		if not is_instance_valid(hero) or hero.health <= 0.0:
			lead.queue_free()
			return
		if not is_instance_valid(target) or target.health <= 0.0 or target.team == hero.team:
			break
		var lead_pos := Vector3(target.global_position.x, 0.5, target.global_position.z)
		lead.global_position = lead.global_position.lerp(lead_pos, 0.25)
		await hero.get_tree().create_timer(0.035).timeout
	# 命中：单目标全额伤害（无贯穿/无英雄格挡）；仅非英雄单位吃 1.5m 小击退 + 0.3s 短击飞
	if is_instance_valid(target) and target.health > 0.0 and target.team != hero.team:
		target.take_damage(float(dmg), hero, false, 2, 0)
		if not (target is Turret) and not (target is Hero):
			var kb_dir := Vector3(target.global_position.x - origin.x, 0.0, target.global_position.z - origin.z)
			if kb_dir.length() < 0.05:
				kb_dir = Vector3(-hero.global_transform.basis.z.x, 0.0, -hero.global_transform.basis.z.z).normalized()
			var kb_n := kb_dir.normalized()
			target.global_position = Vector3(target.global_position.x + kb_n.x * 1.5, 0.5, target.global_position.z + kb_n.z * 1.5)
			target.knockup_timer = maxf(target.knockup_timer, 0.3)
	lead.queue_free()


func _yuanliu_r(hero, lv: int, pos: Vector3) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var hero_flat := Vector3(hero.global_position.x, 0.0, hero.global_position.z)
	var cpos := Vector3(pos.x, 0.0, pos.z)
	var max_range := 7.0
	if hero.skills.size() > 2 and hero.skills[2] != null:
		max_range = maxf(1.0, float(hero.skills[2].cast_range))
	if cpos.length() < 0.05:
		var fwd3: Vector3 = Vector3(-hero.global_transform.basis.z.x, 0.0, -hero.global_transform.basis.z.z).normalized()
		cpos = hero_flat + fwd3 * minf(6.0, max_range)
	else:
		# 防御：任何入口（含联机/回放/AI）传入的过远目标点都夹到技能施法距离内
		var to_cpos := cpos - hero_flat
		if to_cpos.length() > max_range:
			cpos = hero_flat + to_cpos.normalized() * max_range
	# 释放即刻移速 +20~40% ·2秒
	hero.apply_move_pct_buff("ms_haste", 2.0, minf(0.2 + 0.1 * (lv - 1), 0.4))
	# 7/10/13 支轻型弩箭
	var n := 7 + 3 * (lv - 1)
	var shot := int(50.0 + 25.0 * (lv - 1) + float(hero.actual_attack_damage) * 0.24)
	var interval: float = 0.3 / maxf(hero.attack_speed, 0.2)   # Hero 没有 actual_attack_speed，攻速字段是 attack_speed（次/秒）
	# 落点水圈视觉（整段施放期间缓慢收小）
	var zone = _yuanliu_flow_pool(hero.get_parent(), cpos, 3.2)
	var ztw: Tween = hero.get_tree().create_tween()
	ztw.tween_property(zone, "scale", Vector3(0.01, 0.01, 0.01), n * interval + 0.4)
	ztw.tween_callback(zone.queue_free)
	for i in range(n):
		if not is_instance_valid(hero) or hero.health <= 0.0:
			return
		await hero.get_tree().create_timer(interval).timeout
		# 落点目标：优先区域内血量最低的英雄，其次任一小兵/野怪
		var pick = null
		var best_hp := 1e9
		for e in hero.get_tree().get_nodes_in_group("entities"):
			if e == hero or e.health <= 0.0 or e.team == hero.team:
				continue
			if Vector3(e.global_position.x, 0.0, e.global_position.z).distance_to(cpos) <= 4.0:
				if e is Hero and e.health < best_hp:
					best_hp = e.health
					pick = e
				elif pick == null:
					pick = e
		if pick == null:
			continue
		var pid := 0 if i % 3 == 0 else -61   # 每3支=1次普攻判定（负id跳过普攻类 on-hit 分支）
		var arrow = create_bullet(shot, 0.0, 0.0, 0, false, hero, Vector3.DOWN, pid)
		if pid == 0:
			arrow.counts_as_aa = true    # 该箭命中视作一次普攻 → 触发普攻类装备特效（闪电匕首等）
		arrow.linear_dir = Vector3.ZERO     # 关闭直线飞行 → 追踪目标垂直下落
		arrow.target = pick
		arrow.speed = 30.0
		arrow.radius = 0.28
		arrow.skill_id = 3
		arrow.scale = Vector3(1.2, 1.2, 1.2)
		# 三技能箭矢从元流之子自身发出（不再从目标头顶落下），再追踪区域内的目标
		arrow.global_position = Vector3(hero.global_position.x + randf_range(-0.25, 0.25),
			hero.global_position.y + 1.15,
			hero.global_position.z + randf_range(-0.25, 0.25))
		hero.get_parent().add_child(arrow)


func _init_skills():
	var sk

	# ==================== 亚瑟 ====================
	sk = Skill.new()
	sk.skill_name = "誓约之盾"; sk.cooldown = 8.0; 
	sk.cd_bonus = 0.6; sk.type = 2; sk.duration = 3.0
	skills["arthur_q"] = sk

	sk = Skill.new()
	sk.skill_name = "回旋打击"; sk.cooldown = 12.0; 
	sk.cd_bonus = 0.6; sk.type = 2;  sk.duration = 5.0
	skills["arthur_w"] = sk

	sk = Skill.new()
	sk.skill_name = "圣剑裁决"; sk.cooldown = 42.0; sk.cast_range =4.0
	sk.cd_bonus = 7.0; sk.type = 1; sk.radius = 3.5; sk.duration = 5.0
	skills["arthur_r"] = sk

	# ==================== 吕布 ====================
	sk = Skill.new()
	sk.skill_name = "方天画斩"; sk.cooldown = 5.0; 
	
	sk.type = 1; sk.radius = 3; 
	skills["lvbu_q"] = sk

	sk = Skill.new()
	sk.skill_name = "贪狼之握"; sk.cooldown = 8.5; 
	sk.cd_bonus = 0.3
	sk.type = 1; sk.radius = 3; 
	skills["lvbu_w"] = sk

	sk = Skill.new()
	sk.skill_name = "魔神降世"; sk.cooldown = 50.0;sk.cast_range = 5.0;
	sk.type = 2; sk.radius = 5.0; sk.applies_slow = 30.0; sk.slow_duration = 2.0
	skills["lvbu_r"] = sk

	# ==================== 马超 ====================
	sk = Skill.new()
	sk.skill_name = "萧索之刃"; sk.cooldown = 7.5; sk.mana_cost = 1
	sk.type = 3; sk.cast_range = 5.0; sk.cd_bonus = 0.3
	skills["machao_q"] = sk

	sk = Skill.new()
	sk.skill_name = "日落孤枪"; sk.cooldown = 7.5; sk.mana_cost = 1
	sk.type = 1; sk.cast_range = 5.0; sk.cd_bonus = 0.3;sk.radius = 2.0;
	skills["machao_w"] = sk

	sk = Skill.new()
	sk.skill_name = "万刃归鞘"; sk.cooldown = 15.0; sk.mana_cost = 0
	sk.type = 2; sk.restore =1; sk.restore_bonus = 1
	sk.cd_bonus = 1.5
	# 实际效果在代码中特殊处理加速和戳刺伤害，这里用增益表示
	skills["machao_r"] = sk

	# ==================== 铠 ====================
	sk = Skill.new()
	sk.skill_name = "回旋之刃"; sk.cooldown = 9.0; sk.mana_cost = 40
	sk.type = 3; sk.cast_range = 4.0; sk.cd_bonus = 0.4
	skills["kai_q"] = sk

	sk = Skill.new()
	sk.skill_name = "极刃风暴"; sk.cooldown = 6.0; sk.mana_cost = 35
	sk.type = 1; sk.cd_bonus = 0.2;sk.radius = 1.5
	skills["kai_w"] = sk

	sk = Skill.new()
	sk.skill_name = "不灭魔躯"; sk.cooldown = 50.0; sk.mana_cost = 120
	sk.type = 2;  sk.cd_bonus = 5
	skills["kai_r"] = sk

	# ==================== 不知火舞 ====================
	sk = Skill.new()
	sk.skill_name = "飞翔龙锥"; sk.cooldown = 9.0; sk.mana_cost = 70
	sk.type = 3; sk.cast_range = 4.0
	skills["huowu_q"] = sk

	sk = Skill.new()
	sk.skill_name = "花蝶扇"; sk.cooldown = 3.5; sk.mana_cost = 35
	sk.type = 3; sk.cast_range = 5.0;sk.cd_bonus = 0.1
	skills["huowu_w"] = sk

	sk = Skill.new()
	sk.skill_name = "必杀·狂舞"; sk.cooldown = 25.0; sk.mana_cost = 100
	sk.type = 3; sk.cast_range = 6.0;sk.cd_bonus = 2.5
	skills["huowu_r"] = sk

	# ==================== 甄姬 ====================
	sk = Skill.new()
	sk.skill_name = "泪如泉涌"; sk.cooldown = 9.0; sk.mana_cost = 55
	sk.type = 1; sk.radius = 2.5; sk.cast_range = 6.0
	sk.cd_bonus = 0.4
	skills["zhenji_q"] = sk

	sk = Skill.new()
	sk.skill_name = "叹息水流"; sk.cooldown = 8.0; sk.mana_cost = 45
	sk.type = 3; sk.cast_range = 5.0;sk.cd_bonus = 0.3
	skills["zhenji_w"] = sk

	sk = Skill.new()
	sk.skill_name = "洛神降临"; sk.cooldown = 45.0; sk.mana_cost = 100
	sk.type = 3; sk.radius = 5.0;
	sk.cd_bonus = 5
	skills["zhenji_r"] = sk

	# ==================== 狄仁杰 ====================
	sk = Skill.new()
	sk.skill_name = "警戒令"; sk.cooldown = 8.0; sk.mana_cost = 60
	sk.cd_bonus = 0.4; 
	sk.type = 3; sk.cast_range = 5.0
	skills["direnjie_q"] = sk

	sk = Skill.new()
	sk.skill_name = "搜查令"; sk.cooldown = 15.0; sk.mana_cost = 70
	sk.type = 2;  # 解控，在代码中特殊处理
	sk.cd_bonus = 0.6; 
	skills["direnjie_cleanse"] = sk

	sk = Skill.new()
	sk.skill_name = "逮捕令"; sk.cooldown = 24.0; sk.mana_cost = 100
	sk.type = 3; sk.cast_range = 5.0
	sk.cd_bonus = 4; 
	skills["direnjie_r"] = sk

	# ==================== 太乙真人 ====================
	sk = Skill.new()
	sk.skill_name = "炼药"; sk.cooldown = 5.0; sk.mana_cost = 60;
	sk.type = 2; sk.radius = 3.0;  sk.duration = 5.0
	skills["taiyi_q"] = sk

	sk = Skill.new()
	sk.skill_name = "意外事故"; sk.cooldown = 9.0; sk.mana_cost = 65
	sk.cd_bonus = 0.4; sk.type = 3; sk.cast_range = 6.0
	skills["taiyi_w"] = sk

	sk = Skill.new()
	sk.skill_name = "大变活人"; sk.cooldown = 70.0; sk.mana_cost = 150
	sk.type = 6; sk.shield_amount = 1000; sk.duration = 3.0   # 简化复活为超大护盾
	skills["taiyi_r"] = sk

	# ==================== 东皇太一 ====================
	sk = Skill.new()
	sk.skill_name = "曜龙烛兆"; sk.cooldown = 5.0; sk.mana_cost = 40;sk.cast_range = 0
	sk.cd_bonus = 0.1; sk.type = 1; sk.radius = 3.5
	skills["donghuang_q"] = sk

	sk = Skill.new()
	sk.skill_name = "堕神契约"; sk.cooldown = 8.0; sk.mana_cost = 60
	sk.type = 3; sk.cast_range = 6.0
	skills["donghuang_w"] = sk

	sk = Skill.new()
	sk.skill_name = "契约·噬灭"; sk.cooldown = 60.0; sk.mana_cost = 100
	sk.type = 0;  sk.bonus_ratio = 0.5; sk.cast_range = 3.0
	# 强控2.5秒由代码实现，这里仅作伤害
	skills["donghuang_r"] = sk

	# ==================== 李白 ====================
	sk = Skill.new()
	sk.skill_name = "将进酒"; sk.cooldown = 6.0; sk.mana_cost = 50
	sk.cd_bonus = 0.2; sk.type = 3; sk.self_displacement = 2.5;
	skills["libai_q"] = sk

	sk = Skill.new()
	sk.skill_name = "神来之笔"; sk.cooldown = 12.0; sk.mana_cost = 60
	sk.cd_bonus = 0.4; sk.type = 1; sk.radius = 3.5; sk.duration = 3.0
	skills["libai_w"] = sk

	sk = Skill.new()
	sk.skill_name = "青莲剑歌"; sk.cooldown = 12.0; sk.mana_cost = 80
	sk.type = 0; sk.radius = 5.0; sk.duration = 2.0
	skills["libai_r"] = sk

	# ==================== 兰陵王 ====================
	sk = Skill.new()
	sk.skill_name = "秘技·极意"; sk.cooldown = 5.0; sk.mana_cost = 30
	sk.cd_bonus = 0.2; sk.type = 0; sk.cast_range = 3.0
	skills["lanling_q"] = sk

	sk = Skill.new()
	sk.skill_name = "秘技·影蚀"; sk.cooldown = 8.0; sk.mana_cost = 60
	sk.cd_bonus = 0.3; sk.type = 3; sk.cast_range = 6.0
	skills["lanling_w"] = sk

	sk = Skill.new()
	sk.skill_name = "秘技·暗袭"; sk.cooldown = 25.0; sk.mana_cost = 80
	sk.cd_bonus = 2.5; sk.type = 4; sk.self_displacement = 3.5
	skills["lanling_r"] = sk

	# ==================== 孙尚香 ====================
	sk = Skill.new()
	sk.skill_name = "翻滚突袭"; sk.cooldown = 5.0; sk.mana_cost = 20
	sk.type = 4; sk.self_displacement = 3.0
	sk.cd_bonus = 0.1;
	skills["sunshangxiang_q"] = sk

	sk = Skill.new()
	sk.skill_name = "红莲爆弹"; sk.cooldown = 7.5; sk.mana_cost = 40
	sk.type = 1; sk.radius = 3.0;sk.cast_range = 5.0;
	sk.cd_bonus = 0.3;
	skills["sunshangxiang_w"] = sk

	sk = Skill.new()
	sk.skill_name = "究极弩炮"; sk.cooldown = 25.0; sk.mana_cost = 70
	sk.type = 3;sk.cast_range = 8.0
	sk.cd_bonus = 5;sk.radius = 2.0;
	skills["sunshangxiang_r"] = sk

	# ==================== 马可波罗 ====================
	sk = Skill.new()
	sk.skill_name = "华丽左轮"; sk.cooldown = 5.5; sk.mana_cost = 75
	sk.type = 3; sk.cast_range = 5.0   # 简化成单发
	sk.cd_bonus = 0.2; sk.power_bonus=6
	skills["makeboluo_q"] = sk

	sk = Skill.new()
	sk.skill_name = "漫游之枪"; sk.cooldown = 6.0; sk.mana_cost = 75
	sk.type = 4; sk.self_displacement = 3.0; 
	sk.cd_bonus = 0.2; sk.power_bonus=6
	skills["makeboluo_w"] = sk

	sk = Skill.new()
	sk.skill_name = "狂热弹幕"; sk.cooldown = 50.0; sk.mana_cost = 75
	sk.type = 4; sk.self_displacement = 3.0; 
	sk.cd_bonus = 5; sk.power_bonus=15; sk.radius = 4.0; sk.duration = 3.0
	skills["makeboluo_r"] = sk

	# ==================== 张飞 ====================
	sk = Skill.new()
	sk.skill_name = "丈八蛇矛"; sk.cooldown = 6.0; sk.mana_cost = 0
	sk.cd_bonus = 0.2; sk.type = 3; sk.cast_range = 3.0
	skills["zhangfei_q"] = sk

	sk = Skill.new()
	sk.skill_name = "守护"; sk.cooldown = 12.5; sk.mana_cost = 0
	sk.type = 6
	skills["zhangfei_w"] = sk

	sk = Skill.new()
	sk.skill_name = "狂兽血性"; sk.cooldown = 40.0; sk.mana_cost = 0
	sk.type = 2; sk.duration = 8.0
	# 增加护盾和伤害在代码中处理
	skills["zhangfei_r"] = sk

	# ==================== 沈梦溪 ====================
	sk = Skill.new()
	sk.skill_name = "猫咪炸弹"; sk.cooldown = 3.5; sk.mana_cost = 1
	sk.cd_bonus = 0.14
	sk.type = 1; sk.radius = 3.0;sk.cast_range = 6.0
	skills["shenmengxi_q"] = sk

	sk = Skill.new()
	sk.skill_name = "疾跑"; sk.cooldown = 10.0; sk.mana_cost = 1
	sk.type = 2; 
	sk.cd_bonus = 0.4
	skills["shenmengxi_w"] = sk

	sk = Skill.new()
	sk.skill_name = "综合轰炸"; sk.cooldown = 30.0; sk.mana_cost = 0
	sk.type = 1; sk.radius = 4.5;sk.cast_range = 6.0
	sk.cd_bonus = 3
	sk.cast_time = 0.32   # P0-2：大招前摇（蓄力表现对齐，结算仍在 _finish_casting）
	skills["shenmengxi_r"] = sk

	sk = Skill.new()
	sk.skill_name = "恢复"
	sk.cooldown = 60.0
	sk.mana_cost = 0
	sk.type = 2
	sk.damage = 0
	sk.duration = 5.0
	sk.bonus_ratio = 0.0
	skills["recover"] = sk
	# ==================== 安琪拉 ====================
	sk = Skill.new()
	sk.skill_name = "火球术"; sk.cooldown = 5.0; sk.mana_cost = 40
	sk.cd_bonus = 0.2; sk.type = 1; sk.radius = 2.0; sk.cast_range = 6.0   # 指示圈与实际命中判定对齐（原 1.0）
	skills["angela_q"] = sk

	sk = Skill.new()
	sk.skill_name = "混沌火种"; sk.cooldown = 10.0; sk.mana_cost = 60
	sk.cd_bonus = 0.4; sk.type = 3; sk.cast_range = 6.0
	skills["angela_w"] = sk

	sk = Skill.new()
	sk.skill_name = "炽热光辉"; sk.cooldown = 20.0; sk.mana_cost = 90
	sk.type = 3; sk.duration = 3.0; sk.cast_range = 10.0
	sk.cast_time = 0.28   # P0-2：大招前摇（蓄力表现对齐，结算仍在 _finish_casting）
	skills["angela_r"] = sk
	# ==================== 妲己 ====================
	sk = Skill.new()
	sk.skill_name = "灵魂冲击波"; sk.cooldown = 5.0; sk.mana_cost = 30
	sk.cd_bonus = 0.2; sk.type = 3; sk.cast_range = 10.0
	skills["daji_q"] = sk

	sk = Skill.new()
	sk.skill_name = "魅惑爱心"; sk.cooldown = 10.0; sk.mana_cost = 70
	sk.cd_bonus = 0.4; sk.type = 0; sk.cast_range = 7.0
	skills["daji_w"] = sk

	sk = Skill.new()
	sk.skill_name = "狐火"; sk.cooldown = 15.0; sk.mana_cost = 100
	sk.cd_bonus = 0.6; sk.type = 0; sk.radius = 7.0
	skills["daji_r"] = sk

	# ==================== 小乔 ====================
	sk = Skill.new()
	sk.skill_name = "绽放之舞"; sk.cooldown = 5.0; sk.mana_cost = 30
	sk.cd_bonus = 0.2; sk.type = 3; sk.cast_range = 7.5
	skills["xiaoqiao_q"] = sk

	sk = Skill.new()
	sk.skill_name = "甜蜜恋风"; sk.cooldown = 10.0; sk.mana_cost = 70
	sk.cd_bonus = 0.4; sk.type = 1; sk.radius = 2.0; sk.cast_range = 6.0
	skills["xiaoqiao_w"] = sk

	sk = Skill.new()
	sk.skill_name = "星华缭乱"; sk.cooldown = 35.0; sk.mana_cost = 120
	sk.cd_bonus = 3.5; sk.type = 2; sk.radius = 7.0
	skills["xiaoqiao_r"] = sk

	sk = Skill.new()
	sk.skill_name = "秘技·隐匿"; sk.cooldown = 24.0; sk.mana_cost = 0
	sk.type = 2; sk.duration = 30.0
	skills["lanling_stealth"] = sk

	# ==================== 鲁班七号 ====================
	sk = Skill.new()
	sk.skill_name = "河豚手雷"; sk.cooldown = 7.5; sk.mana_cost = 40
	sk.cd_bonus = 0.3; sk.type = 1; sk.radius = 3.0; sk.cast_range = 5.0
	sk.power_bonus = 0
	skills["luban_q"] = sk

	sk = Skill.new()
	sk.skill_name = "无敌鲨嘴炮"; sk.cooldown = 12.0; sk.mana_cost = 60
	sk.cd_bonus = 0.6; sk.type = 3; sk.cast_range = 5.0
	skills["luban_w"] = sk

	sk = Skill.new()
	sk.skill_name = "空中支援"; sk.cooldown = 35.0; sk.mana_cost = 80
	sk.cd_bonus = 7.5; sk.type = 1; sk.radius = 5.0; sk.cast_range = 6.0
	sk.power_bonus = 7.5
	skills["luban_r"] = sk
	# ==================== 王昭君 ====================
	# ==================== 夏侯惇 ====================
	sk = Skill.new()
	sk.skill_name = "豪气斩"; sk.cooldown = 8.0; sk.mana_cost = 40
	sk.cd_bonus = 0.3; sk.type = 3; sk.cast_range = 8.0
	skills["xiahou_q"] = sk

	sk = Skill.new()
	sk.skill_name = "龙卷闪"; sk.cooldown = 7.0; sk.mana_cost = 35
	sk.cd_bonus = 0.3; sk.type = 1; sk.radius = 3.5
	skills["xiahou_w"] = sk

	sk = Skill.new()
	sk.skill_name = "不羁之刃"; sk.cooldown = 16.0; sk.mana_cost = 50
	sk.cd_bonus = 1.5; sk.type = 4; sk.cast_range = 8.0
	skills["xiahou_r"] = sk

	# ==================== 后羿 ====================
	sk = Skill.new()
	sk.skill_name = "多重箭矢"; sk.cooldown = 10.0; sk.mana_cost = 50
	sk.cd_bonus = 0.4; sk.type = 2
	skills["houyi_q"] = sk

	sk = Skill.new()
	sk.skill_name = "落日余晖"; sk.cooldown = 7.0; sk.mana_cost = 40
	sk.cd_bonus = 0.3; sk.type = 1; sk.radius = 2.5; sk.cast_range = 8.0
	skills["houyi_w"] = sk

	sk = Skill.new()
	sk.skill_name = "灼日之矢"; sk.cooldown = 45.0; sk.mana_cost = 130
	sk.cd_bonus = 5.0; sk.type = 3; sk.cast_range = 15.0
	sk.cast_time = 0.30   # P0-2：大招前摇（蓄力表现对齐，结算仍在 _finish_casting）
	skills["houyi_r"] = sk

	# ==================== 大禹 ====================
	sk = Skill.new()
	sk.skill_name = "力拔山兮"; sk.cooldown = 10.0; sk.mana_cost = 40
	sk.cd_bonus = 0.4; sk.type = 1; sk.radius = 3.0; sk.cast_range = 6.0
	skills["dayu_q"] = sk

	sk = Skill.new()
	sk.skill_name = "辟命狩天"; sk.cooldown = 10.0; sk.mana_cost = 50
	sk.cd_bonus = 0.4; sk.type = 3; sk.cast_range = 9.0
	skills["dayu_w"] = sk

	sk = Skill.new()
	sk.skill_name = "乾坤以同"; sk.cooldown = 60.0; sk.mana_cost = 100
	sk.cd_bonus = 4.0; sk.type = 1; sk.radius = 3.0; sk.cast_range = 10.0
	sk.cast_time = 0.36   # P0-2：大招前摇（蓄力表现对齐，结算仍在 _finish_casting）
	skills["dayu_r"] = sk

	sk = Skill.new()
	sk.skill_name = "凋零冰晶"; sk.cooldown = 5.0; sk.mana_cost = 30
	sk.type = 1; sk.radius = 2.0; sk.cast_range = 6.0
	sk.cd_bonus = 0.2; sk.power_bonus = 0
	skills["wangzhaojun_q"] = sk

	sk = Skill.new()
	sk.skill_name = "禁锢寒霜"; sk.cooldown = 9.0; sk.mana_cost = 60
	sk.type = 1; sk.radius = 2.0; sk.cast_range = 6.0
	sk.cd_bonus = 0.4; sk.power_bonus = 0
	skills["wangzhaojun_w"] = sk

	sk = Skill.new()
	sk.skill_name = "凛冬已至"; sk.cooldown = 35.0; sk.mana_cost = 100
	sk.type = 1; sk.radius = 5.0; sk.cast_range = 6.0
	sk.cd_bonus = 3.5; sk.power_bonus = 0; sk.duration = 5.0
	sk.cast_time = 0.40   # P0-2：大招前摇（蓄力表现对齐，结算仍在 _finish_casting）
	skills["wangzhaojun_r"] = sk

	# ==================== 刘禅 ====================
	sk = Skill.new()
	sk.skill_name = "小霸王护盾"; sk.cooldown = 9.0; sk.mana_cost = 50
	sk.cd_bonus = 0.4; sk.type = 2
	skills["liushan_q"] = sk

	sk = Skill.new()
	sk.skill_name = "机关魔爪"; sk.cooldown = 7.5; sk.mana_cost = 40
	sk.cd_bonus = 0.3; sk.type = 1; sk.radius = 2.0; sk.cast_range = 3.0
	skills["liushan_w"] = sk

	sk = Skill.new()
	sk.skill_name = "暴走熊猫"; sk.cooldown = 40.0; sk.mana_cost = 100
	sk.cd_bonus = 5.0; sk.type = 2; sk.radius = 4.0
	skills["liushan_r"] = sk

	# ==================== 孙悟空 ====================
	sk = Skill.new()
	sk.skill_name = "护身咒法"; sk.cooldown = 12.0; sk.mana_cost = 65
	sk.cd_bonus = 0.4; sk.type = 2
	skills["sunwukong_q"] = sk

	sk = Skill.new()
	sk.skill_name = "斗战冲锋"; sk.cooldown = 6.0; sk.mana_cost = 45
	sk.cd_bonus = 0.2; sk.type = 2
	skills["sunwukong_w"] = sk

	sk = Skill.new()
	sk.skill_name = "如意金箍"; sk.cooldown = 40.0; sk.mana_cost = 100
	sk.cd_bonus = 5.0; sk.type = 1; sk.radius = 4.0
	skills["sunwukong_r"] = sk


	# ==================== 英睿 ====================
	sk = Skill.new()
	sk.skill_name = "冰红茶"; sk.cooldown = 7.0; sk.mana_cost = 55
	sk.cd_bonus = 0.4; sk.type = 1; sk.radius = 1.8; sk.cast_range = 8.0
	sk.damage = 340
	skills["yingrui_q"] = sk

	sk = Skill.new()
	sk.skill_name = "肘击"; sk.cooldown = 6.0; sk.mana_cost = 40
	sk.cd_bonus = 0.3; sk.type = 3; sk.cast_range = 2.0; sk.bullet_range = 2.0
	sk.damage = 420
	skills["yingrui_w"] = sk

	sk = Skill.new()
	sk.skill_name = "变身LabiB"; sk.cooldown = 36.0; sk.mana_cost = 100
	sk.cd_bonus = 5.0; sk.type = 2; sk.duration = 14.0
	skills["yingrui_r"] = sk


	# ==================== 召唤师技能 ====================
	sk = Skill.new()
	sk.skill_name = "闪现"; sk.cooldown = 120.0; sk.mana_cost = 0
	sk.type = 4; sk.self_displacement = 5.0
	skills["flash"] = sk

	sk = Skill.new()
	sk.skill_name = "谍影重重"; sk.cooldown = 10.0; sk.cd_bonus = 0.4; sk.mana_cost = 60
	sk.type = 0; sk.cast_range = 6.5; sk.duration = 4.0
	sk.damage = 220.0; sk.bonus_ratio = 0.7
	skills["liyuanfang_q"] = sk

	sk = Skill.new()
	sk.skill_name = "刃遁"; sk.cooldown = 10.0; sk.cd_bonus = 0.4; sk.mana_cost = 65
	sk.type = 4; sk.cast_range = 6.0; sk.self_displacement = 4.5
	sk.damage = 260.0; sk.bonus_ratio = 0.8
	skills["liyuanfang_w"] = sk

	sk = Skill.new()
	sk.skill_name = "无间刃风"; sk.cooldown = 30.0; sk.cd_bonus = 3.0; sk.mana_cost = 110
	sk.type = 3; sk.cast_range = 7.5; sk.duration = 5.4
	sk.damage = 320.0; sk.bonus_ratio = 1.0
	skills["liyuanfang_r"] = sk

	sk = Skill.new()
	sk.skill_name = "汇流为一"; sk.cooldown = 8.0; sk.cd_bonus = 0.3; sk.mana_cost = 55
	sk.type = 1; sk.radius = 3.5
	sk.damage = 100.0; sk.bonus_ratio = 0.25
	skills["yuanliu_q"] = sk

	sk = Skill.new()
	sk.skill_name = "破釜之箭"; sk.cooldown = 7.5; sk.cd_bonus = 0.3; sk.mana_cost = 25
	sk.type = 0; sk.cast_range = 6.5; 
	sk.damage = 480.0; sk.bonus_ratio = 1.2
	skills["yuanliu_w"] = sk

	sk = Skill.new()
	sk.skill_name = "万箭齐发"; sk.cooldown = 25.0; sk.cd_bonus = 2.5; sk.mana_cost = 60
	sk.type = 1; sk.cast_range = 7.0; sk.radius = 3.5; sk.duration = 2.2
	skills["yuanliu_r"] = sk

	sk = Skill.new()
	sk.skill_name = "疾跑"; sk.cooldown = 75.0; sk.mana_cost = 0
	sk.type = 2; sk.duration = 10.0
	skills["sprint"] = sk

	sk = Skill.new()
	sk.skill_name = "传送"; sk.cooldown = 75.0; sk.mana_cost = 0
	sk.type = 2
	skills["teleport"] = sk

	sk = Skill.new()
	sk.skill_name = "治疗术"; sk.cooldown = 120.0; sk.mana_cost = 0
	sk.type = 2
	skills["heal"] = sk

	sk = Skill.new()
	sk.skill_name = "终结"; sk.cooldown = 60.0; sk.mana_cost = 0
	sk.type = 0; sk.cast_range = 5.0
	skills["execute"] = sk

	sk = Skill.new()
	sk.skill_name = "狂暴"; sk.cooldown = 75.0; sk.mana_cost = 0
	sk.type = 2; sk.duration = 7.0
	skills["frenzy"] = sk

	sk = Skill.new()
	sk.skill_name = "晕眩"; sk.cooldown = 90.0; sk.mana_cost = 0
	sk.type = 1; sk.radius = 5.0
	skills["stun"] = sk

	sk = Skill.new()
	sk.skill_name = "净化"; sk.cooldown = 120.0; sk.mana_cost = 0
	sk.type = 2
	skills["cleanse_summoner"] = sk

	sk = Skill.new()
	sk.skill_name = "弱化"; sk.cooldown = 75.0; sk.mana_cost = 0
	sk.type = 2; sk.duration = 4.0
	skills["weaken"] = sk

	sk = Skill.new()
	sk.skill_name = "惩击"; sk.cooldown = 30.0; sk.mana_cost = 0
	sk.damage = 1500.0; sk.bonus_ratio = 0.0; sk.type = 0; sk.cast_range = 3.0
	skills["smite"] = sk

func get_skill(skill_id: String) -> Skill:
	var skill = skills.get(skill_id)
	if skill:
		skill.is_channeling = true if skill.type ==1 or skill.type ==4 or skill.type ==3 else false
	return skill

## 全图弹道技能（鲁班七号2技能 / 后羿3技能这种“瞄准方向、子弹横穿全图”的技能）：
## 供小地图瞄准线、命中的敌人高亮、飞行中子弹绘制共用；返回 {} 表示该槽不是全图技。
## len=最大飞行距离；hit_r=判定半径基数（与单位 body_radius 相加）；only_hero=只命中英雄。
static func global_shot_profile(hero_name: String, slot: int) -> Dictionary:
	if hero_name == "鲁班七号" and slot == 1:
		return {"len": 160.0, "hit_r": 0.6, "only_hero": true, "speed": 35.0,
			"color": Color(0.42, 0.95, 0.72)}
	if hero_name == "后羿" and slot == 2:
		return {"len": 160.0, "hit_r": 1.2, "only_hero": true, "speed": 20.0,
			"color": Color(1.0, 0.62, 0.14)}
	return {}
