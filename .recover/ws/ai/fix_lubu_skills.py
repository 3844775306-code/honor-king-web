"""Fix SkillDataBase.gd for Lu Bu — R definition + Q/W/R apply_skills."""
import os

path = r"C:\Users\18749\Documents\honor-king\assets\SkillDataBase.gd"

with open(path, 'rb') as f:
    data = f.read()

# ================================================================
# Fix 1: R skill definition
# ================================================================
old_r_def = (b'\tsk = Skill.new()\n'
             b'\tsk.skill_name = "\xe9\xad\x94\xe7\xa5\x9e\xe9\x99\x8d\xe4\xb8\x96"; sk.cooldown = 40.0; sk.mana_cost = 0\n'
             b'\tsk.damage = 600; sk.bonus_ratio = 1.5\n'
             b'\tsk.type = 1; sk.radius = 5.0; sk.applies_slow = 30.0; sk.slow_duration = 2.0\n'
             b'\tsk.cast_time = 0.8; sk.is_channeling = true\n'
             b'\tskills["lvbu_r"] = sk\n')

new_r_def = (b'\tsk = Skill.new()\n'
             b'\tsk.skill_name = "\xe9\xad\x94\xe7\xa5\x9e\xe9\x99\x8d\xe4\xb8\x96"; sk.cooldown = 50.0; sk.mana_cost = 0\n'
             b'\tsk.type = 2; sk.radius = 5.0; sk.applies_slow = 30.0; sk.slow_duration = 2.0\n'
             b'\tsk.cast_time = 0.8\n'
             b'\tskills["lvbu_r"] = sk\n')

if old_r_def in data:
    data = data.replace(old_r_def, new_r_def, 1)
    print("[OK] R skill definition: CD 50s, type=2 (non-channeling)")
else:
    print("[FAIL] R skill definition not found")

# ================================================================
# Fix 2: Q apply_skills — bonus AD damage
# ================================================================
old_q = (b'\t\t\t1:\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tvar preview = create_preview(2.0,pos,hero.team)\n'
         b'\t\t\t\tpreview.visible = true\n'
         b'\t\t\t\thero.get_parent().add_child(preview)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tvar bullet = create_bullet(480,2,0,120*level,false,hero,dir,1)\n'
         b'\t\t\t\tbullet.damage_range=2.0\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\thero.get_parent().add_child(bullet)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tpreview.queue_free()\n'
         b'\t\t\t\t\n'
         b'\t\t\t\t\n'
         b'\t\t\t\t\n'
         b'\t\t\t\t\n'
         b'\t\t\t\t\n')

new_q = (b'\t\t\t1:\n'
         b'\t\t\t\tvar preview = create_preview(2.0,pos,hero.team)\n'
         b'\t\t\t\tpreview.visible = true\n'
         b'\t\t\t\thero.get_parent().add_child(preview)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\tvar bonus_ad = hero.bonus_attack\n'
         b'\t\t\t\tvar bullet = create_bullet(int(600 + 2.0*bonus_ad),0,0,120*level,false,hero,dir,1)\n'
         b'\t\t\t\tbullet.damage_range=2.0\n'
         b'\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\thero.get_parent().add_child(bullet)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tpreview.queue_free()\n')

if old_q in data:
    data = data.replace(old_q, new_q, 1)
    print("[OK] Q apply_skills: bonus AD damage (600+2.0*bonusAD)")
else:
    print("[FAIL] Q apply_skills not found")

# ================================================================
# Fix 3: W apply_skills — bonus AD damage
# ================================================================
old_w = (b'\t\t\t2:\n'
         b'\t\t\t\tvar preview = create_preview(3.0,pos,hero.team)\n'
         b'\t\t\t\tpreview.visible = true\n'
         b'\t\t\t\thero.get_parent().add_child(preview)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tif pos:\n'
         b'\t\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\t\t\n'
         b'\t\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\t\t\n'
         b'\t\t\t\t\tvar bullet = create_bullet(80,0.35,0,20*level,false,hero,dir,2)\n'
         b'\t\t\t\t\tbullet.damage_range=3.0\n'
         b'\t\t\t\t\tbullet.slow_dur = 3\n'
         b'\t\t\t\t\tbullet.slow_per = 0.12+level*0.03\n'
         b'\t\t\t\t\t\n'
         b'\t\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\t\thero.get_parent().add_child(bullet)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tpreview.queue_free()\n'
         b'\t\t\t\t\n')

new_w = (b'\t\t\t2:\n'
         b'\t\t\t\tvar preview = create_preview(3.0,pos,hero.team)\n'
         b'\t\t\t\tpreview.visible = true\n'
         b'\t\t\t\thero.get_parent().add_child(preview)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tif pos:\n'
         b'\t\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\t\tvar bonus_ad = hero.bonus_attack\n'
         b'\t\t\t\t\tvar bullet = create_bullet(int(100 + 0.35*bonus_ad),0,0,20*level,false,hero,dir,2)\n'
         b'\t\t\t\t\tbullet.damage_range=3.0\n'
         b'\t\t\t\t\tbullet.slow_dur = 3\n'
         b'\t\t\t\t\tbullet.slow_per = 0.12+level*0.03\n'
         b'\t\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\t\thero.get_parent().add_child(bullet)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\tpreview.queue_free()\n')

if old_w in data:
    data = data.replace(old_w, new_w, 1)
    print("[OK] W apply_skills: bonus AD damage (100+0.35*bonusAD)")
else:
    print("[FAIL] W apply_skills not found")

# ================================================================
# Fix 4: R apply_skills — complete rework
# ================================================================
old_r = (b'\t\t\t3:\n'
         b'\t\t\t\tvar preview = create_preview(5.0,pos,hero.team)\n'
         b'\t\t\t\tpreview.visible = true\n'
         b'\t\t\t\t\n'
         b'\t\t\t\thero.get_parent().add_child(preview)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(1.0).timeout\n'
         b'\t\t\t\thero.fly = 3\n'
         b'\t\t\t\thero.fly_timer = 0.5\n'
         b'\t\t\t\t\t\n'
         b'\t\t\t\thero.global_position = pos\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\t\n'
         b'\t\t\t\thero._apply_df_buff(75+75*level,0,5,false)\n'
         b'\t\t\t\thero._apply_df_buff(75+75*level,0,5,true)\n'
         b'\t\t\t\thero.stat =2\n'
         b'\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\t\n'
         b'\t\t\t\tvar bullet = create_bullet(325,2.4,0,325*level,false,hero,dir,3)\n'
         b'\t\t\t\tbullet.damage_range = 5.0\n'
         b'\t\t\t\tbullet.knock_dur = 1.0\n'
         b'\t\t\t\tbullet.slow_dur = 2\n'
         b'\t\t\t\tbullet.slow_per = 0.15+level*0.15\n'
         b'\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\thero.get_parent().add_child(bullet)\t\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(5.0).timeout\n'
         b'\t\t\t\tpreview.queue_free()\n'
         b'\t\t')

new_r = (b'\t\t\t3:  # \xe9\xad\x94\xe7\xa5\x9e\xe9\x99\x8d\xe4\xb8\x96\xef\xbc\x9a\xe8\x90\xbd\xe5\x9c\xb0\xe6\x96\xa9\xe5\x87\xbb+\xe6\xb3\x95\xe9\x98\xb5\xe8\xbe\xb9\xe7\xbc\x98\xe4\xbc\xa4\xe5\xae\xb3\n'
         b'\t\t\t\t# \xe5\xa4\xa7\xe6\x8b\x9b\xe8\x8c\x83\xe5\x9b\xb4\xe9\xa2\x84\xe8\xa7\x88\xe5\x9c\x88\n'
         b'\t\t\t\tvar r_preview = create_preview(5.0, pos, hero.team)\n'
         b'\t\t\t\tr_preview.visible = true\n'
         b'\t\t\t\thero.get_parent().add_child(r_preview)\n'
         b'\t\t\t\t# \xe5\x9c\xb0\xe9\x9d\xa2\xe6\xb3\x95\xe9\x98\xb5\xe5\x9c\x86\xe7\x9b\x98\xef\xbc\x88\xe8\xa7\x86\xe8\xa7\x89\xe6\x95\x88\xe6\x9e\x9c\xef\xbc\x89\n'
         b'\t\t\t\tvar r_disc = MeshInstance3D.new()\n'
         b'\t\t\t\tvar r_disc_mesh = CylinderMesh.new()\n'
         b'\t\t\t\tr_disc_mesh.top_radius = 5.0\n'
         b'\t\t\t\tr_disc_mesh.bottom_radius = 5.0\n'
         b'\t\t\t\tr_disc_mesh.height = 0.15\n'
         b'\t\t\t\tr_disc.mesh = r_disc_mesh\n'
         b'\t\t\t\tr_disc.position = pos + Vector3(0, 0.05, 0)\n'
         b'\t\t\t\tr_disc.rotation_degrees = Vector3(90, 0, 0)\n'
         b'\t\t\t\tvar r_disc_mat = StandardMaterial3D.new()\n'
         b'\t\t\t\tr_disc_mat.albedo_color = Color(0.9, 0.15, 0.05, 0.3) if hero.team == 1 else Color(0.05, 0.25, 0.9, 0.3)\n'
         b'\t\t\t\tr_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA\n'
         b'\t\t\t\tr_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED\n'
         b'\t\t\t\tr_disc.material_override = r_disc_mat\n'
         b'\t\t\t\tr_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n'
         b'\t\t\t\thero.get_parent().add_child(r_disc)\n'
         b'\t\t\t\t# \xe8\xb7\xb3\xe8\xb7\x83\xe5\x8a\xa8\xe7\x94\xbb\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(1.0).timeout\n'
         b'\t\t\t\thero.fly = 3\n'
         b'\t\t\t\thero.fly_timer = 0.5\n'
         b'\t\t\t\thero.global_position = pos\n'
         b'\t\t\t\t# \xe6\x9b\xb4\xe6\x96\xb0\xe6\xb3\x95\xe9\x98\xb5\xe8\xa7\x86\xe8\xa7\x89\xe4\xbd\x8d\xe7\xbd\xae\n'
         b'\t\t\t\tif is_instance_valid(r_disc): r_disc.position = pos + Vector3(0, 0.05, 0)\n'
         b'\t\t\t\tif is_instance_valid(r_preview): r_preview.position = pos + Vector3(0, 0.2, 0)\n'
         b'\t\t\t\tawait hero.get_tree().create_timer(0.5).timeout\n'
         b'\t\t\t\t# \xe8\x90\xbd\xe5\x9c\xb0\xe5\x8f\x8c\xe6\x8a\x97\n'
         b'\t\t\t\thero._apply_df_buff(75 + 75*level, 0, 5, false)\n'
         b'\t\t\t\thero._apply_df_buff(75 + 75*level, 0, 5, true)\n'
         b'\t\t\t\t# \xe8\x90\xbd\xe5\x9c\xb0\xe6\x96\xa9\xe5\x87\xbb\xef\xbc\x88\xe9\xa2\x9d\xe5\xa4\x96AD\xe5\x8a\xa0\xe6\x88\x90\xef\xbc\x8c\xe9\x99\x84\xe9\xad\x94\xe5\x9c\xa8Bullet.on_hit\xe4\xb8\xad\xe8\xa7\xa6\xe5\x8f\x91\xef\xbc\x89\n'
         b'\t\t\t\tvar bonus_ad = hero.bonus_attack\n'
         b'\t\t\t\tvar ang = atan2((-pos.z + hero.global_position.z),(pos.x - hero.global_position.x))\n'
         b'\t\t\t\tvar dir = Vector3(cos(ang),0,-sin(ang))\n'
         b'\t\t\t\tvar bullet = create_bullet(int(650 + 2.4*bonus_ad), 0, 0, 325*level, false, hero, dir, 3)\n'
         b'\t\t\t\tbullet.damage_range = 5.0\n'
         b'\t\t\t\tbullet.knock_dur = 1.0\n'
         b'\t\t\t\tbullet.slow_dur = 2\n'
         b'\t\t\t\tbullet.slow_per = 0.15 + level*0.15\n'
         b'\t\t\t\tbullet.set_goal(pos)\n'
         b'\t\t\t\thero.get_parent().add_child(bullet)\n'
         b'\t\t\t\t# \xe6\xb3\x95\xe9\x98\xb5\xe8\xbe\xb9\xe7\xbc\x98\xe4\xbc\xa4\xe5\xae\xb3\xe5\xbe\xaa\xe7\x8e\xaf\xef\xbc\x9a5\xe7\xa7\x92\xe5\x86\x85\xe6\xa3\x80\xe6\xb5\x8b\xe6\x95\x8c\xe4\xba\xba\xe8\xa7\xa6\xe7\xa2\xb0\xe8\xbe\xb9\xe7\xbc\x98\xef\xbc\x8c\xe6\xaf\x8f\xe6\x95\x8c\xe4\xba\xba\xe5\x8f\xaa\xe8\xa7\xa6\xe5\x8f\x911\xe6\xac\xa1\n'
         b'\t\t\t\tvar r_edge_hit = {}\n'
         b'\t\t\t\tvar r_center = pos\n'
         b'\t\t\t\tfor _edge_tick in range(16):\n'
         b'\t\t\t\t\tawait hero.get_tree().create_timer(0.3).timeout\n'
         b'\t\t\t\t\tif hero.health <= 0: break\n'
         b'\t\t\t\t\tfor ent in hero.get_tree().get_nodes_in_group("entities"):\n'
         b'\t\t\t\t\t\tif ent == hero or ent.health <= 0 or ent.team == hero.team: continue\n'
         b'\t\t\t\t\t\tif ent is Turret: continue\n'
         b'\t\t\t\t\t\tvar eid = str(ent.get_instance_id())\n'
         b'\t\t\t\t\t\tif r_edge_hit.has(eid): continue\n'
         b'\t\t\t\t\t\tvar dist = ent.global_position.distance_to(r_center)\n'
         b'\t\t\t\t\t\tif dist >= 4.2 and dist <= 5.8:\n'
         b'\t\t\t\t\t\t\tr_edge_hit[eid] = true\n'
         b'\t\t\t\t\t\t\tvar edge_dmg = int(150 + 75*level + 0.75*bonus_ad)\n'
         b'\t\t\t\t\t\t\tent.take_damage(edge_dmg, hero, false, -3, 0)\n'
         b'\t\t\t\t\t\t\tent.apply_slow(2.0, 0.15 + level*0.15)\n'
         b'\t\t\t\t\t\t\t# \xe8\xbe\xb9\xe7\xbc\x98\xe5\x91\xbd\xe4\xb8\xad\xe5\x9b\x9e\xe8\xa1\x80\n'
         b'\t\t\t\t\t\t\tvar _bhp = hero.actual_max_health - hero.max_health\n'
         b'\t\t\t\t\t\t\thero.health = min(hero.health + int(65 + 65*level + 0.025*_bhp), hero.actual_max_health)\n'
         b'\t\t\t\t# \xe6\xb8\x85\xe7\x90\x86\xe6\xb3\x95\xe9\x98\xb5\xe8\xa7\x86\xe8\xa7\x89\n'
         b'\t\t\t\tif is_instance_valid(r_preview): r_preview.queue_free()\n'
         b'\t\t\t\tif is_instance_valid(r_disc): r_disc.queue_free()\n'
         b'\t\t')

if old_r in data:
    data = data.replace(old_r, new_r, 1)
    print("[OK] R apply_skills: complete rework (bonus AD + arena visual + edge damage)")
else:
    print("[FAIL] R apply_skills not found")
    # Try to find it
    idx = data.find(b'"\xe5\x90\x95\xe5\xb8\x83":match  skill_id:')
    if idx >= 0:
        case3 = data.find(b'\t\t\t3:', idx)
        if case3 >= 0:
            print(f"  Case 3 at offset {case3}")
            print(f"  Context: {repr(data[case3:case3+80])}")

# Write back
with open(path, 'wb') as f:
    f.write(data)

print("\n=== SkillDataBase.gd fixes complete ===")
