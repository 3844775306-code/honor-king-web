"""Fix Xiao Qiao R: add target to bullets, add range preview circle."""
import os

def read_bytes(path):
    with open(path, 'rb') as f:
        return f.read()

def write_bytes(path, data):
    with open(path, 'wb') as f:
        f.write(data)

path = os.path.join(r"C:\Users\18749\Documents\honor-king\assets", "SkillDataBase.gd")
data = read_bytes(path)

# The old R block - exact bytes from the file
old = (b'\t\t\t3:  # \xe6\x98\x9f\xe5\x8d\x8e\xe7\xbc\xad\xe4\xb9\xb1\xef\xbc\x9a6\xe7\xa7\x92\xe5\x86\x85\xe6\xaf\x8f0.75\xe7\xa7\x92\xe9\x99\x8d\xe4\xb8\x8b\xe6\xb5\x81\xe6\x98\x9f\xef\xbc\x8c\xe6\xaf\x8f\xe7\x9b\xae\xe6\xa0\x87\xe6\x9c\x80\xe5\xa4\x9a4\xe9\xa2\x97\xef\xbc\x8c\xe9\x87\x8d\xe5\xa4\x8d\xe5\x91\xbd\xe4\xb8\xad50%\xe4\xbc\xa4\xe5\xae\xb3\n'
       b'\t\t\t\thero.apply_slow(6.0, -0.25)\n'
       b'\t\t\t\tvar r_hit_count = {}\n'
       b'\t\t\t\tfor wave in range(8):\n'
       b'\t\t\t\t\tawait hero.get_tree().create_timer(0.75).timeout\n'
       b'\t\t\t\t\tif hero.health <= 0: break\n'
       b'\t\t\t\t\tvar x3_targets = []\n'
       b'\t\t\t\t\tfor ent in hero.get_tree().get_nodes_in_group("entities"):\n'
       b'\t\t\t\t\t\tif ent != hero and ent.health > 0 and ent.team != hero.team and not (ent is Turret):\n'
       b'\t\t\t\t\t\t\tif hero.global_position.distance_to(ent.global_position) <= 7.0:\n'
       b'\t\t\t\t\t\t\t\tx3_targets.append(ent)\n'
       b'\t\t\t\t\tif x3_targets.is_empty(): continue\n'
       b'\t\t\t\t\tx3_targets.shuffle()\n'
       b'\t\t\t\t\tvar spawned = 0\n'
       b'\t\t\t\t\tfor x3_t in x3_targets:\n'
       b'\t\t\t\t\t\tif spawned >= 2: break\n'
       b'\t\t\t\t\t\tvar eid = str(x3_t.get_instance_id())\n'
       b'\t\t\t\t\t\tvar hits = r_hit_count.get(eid, 0)\n'
       b'\t\t\t\t\t\tif hits >= 4: continue\n'
       b'\t\t\t\t\t\tvar x3_dir = (x3_t.global_position - hero.global_position).normalized()\n'
       b'\t\t\t\t\t\tvar x3_bullet = create_bullet(400, 0, 1.0, 100*level, true, hero, x3_dir, 3)\n'
       b'\t\t\t\t\t\tx3_bullet.set_goal(x3_t.global_position)\n'
       b'\t\t\t\t\t\tx3_bullet.speed = 12.0\n'
       b'\t\t\t\t\t\tif hits > 0: x3_bullet.damage *= 0.5\n'
       b'\t\t\t\t\t\tx3_bullet.life_time = 1.5\n'
       b'\t\t\t\t\t\tr_hit_count[eid] = hits + 1\n'
       b'\t\t\t\t\t\tspawned += 1\n'
       b'\t\t\t\t\t\t# \xe8\xa7\x86\xe8\xa7\x89\xef\xbc\x9a\xe7\xb4\xab\xe8\x89\xb2\xe6\xb5\x81\xe6\x98\x9f\n'
       b'\t\t\t\t\t\tvar x3_vis = MeshInstance3D.new()\n'
       b'\t\t\t\t\t\tx3_vis.mesh = SphereMesh.new()\n'
       b'\t\t\t\t\t\tx3_vis.mesh.radius = 0.3\n'
       b'\t\t\t\t\t\tx3_vis.mesh.height = 0.6\n'
       b'\t\t\t\t\t\tvar x3_mat = StandardMaterial3D.new()\n'
       b'\t\t\t\t\t\tx3_mat.albedo_color = Color(0.7, 0.2, 1.0)\n'
       b'\t\t\t\t\t\tx3_mat.emission_enabled = true\n'
       b'\t\t\t\t\t\tx3_mat.emission = Color(0.5, 0.1, 0.9)\n'
       b'\t\t\t\t\t\tx3_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED\n'
       b'\t\t\t\t\t\tx3_vis.material_override = x3_mat\n'
       b'\t\t\t\t\t\tx3_bullet.add_child(x3_vis)\n'
       b'\t\t\t\t\t\thero.get_parent().add_child(x3_bullet)\n')

new = (b'\t\t\t3:  # \xe6\x98\x9f\xe5\x8d\x8e\xe7\xbc\xad\xe4\xb9\xb1\xef\xbc\x9a6\xe7\xa7\x92\xe5\x86\x85\xe6\xaf\x8f0.75\xe7\xa7\x92\xe9\x99\x8d\xe4\xb8\x8b\xe6\xb5\x81\xe6\x98\x9f\xef\xbc\x8c\xe6\xaf\x8f\xe7\x9b\xae\xe6\xa0\x87\xe6\x9c\x80\xe5\xa4\x9a4\xe9\xa2\x97\xef\xbc\x8c\xe9\x87\x8d\xe5\xa4\x8d\xe5\x91\xbd\xe4\xb8\xad50%\xe4\xbc\xa4\xe5\xae\xb3\n'
       b'\t\t\t\thero.apply_slow(6.0, -0.25)\n'
       b'\t\t\t\t# \xe5\xa4\xa7\xe6\x8b\x9b\xe8\x8c\x83\xe5\x9b\xb4\xe9\xa2\x84\xe8\xa7\x88\xe5\x9c\x88\xef\xbc\x887.0\xe5\x8d\x8a\xe5\xbe\x84\xef\xbc\x8c\xe6\x8c\x81\xe7\xbb\xad6\xe7\xa7\x92\n'
       b'\t\t\t\tvar r_preview = create_preview(7.0, hero.global_position, hero.team)\n'
       b'\t\t\t\tr_preview.visible = true\n'
       b'\t\t\t\thero.get_parent().add_child(r_preview)\n'
       b'\t\t\t\tvar r_hit_count = {}\n'
       b'\t\t\t\tfor wave in range(8):\n'
       b'\t\t\t\t\t# \xe6\x9b\xb4\xe6\x96\xb0\xe9\xa2\x84\xe8\xa7\x88\xe5\x9c\x88\xe4\xbd\x8d\xe7\xbd\xae\xe8\xb7\x9f\xe9\x9a\x8f\xe8\x8b\xb1\xe9\x9b\x84\n'
       b'\t\t\t\t\tif is_instance_valid(r_preview): r_preview.global_position = hero.global_position\n'
       b'\t\t\t\t\tawait hero.get_tree().create_timer(0.75).timeout\n'
       b'\t\t\t\t\tif hero.health <= 0: break\n'
       b'\t\t\t\t\tvar x3_targets = []\n'
       b'\t\t\t\t\tfor ent in hero.get_tree().get_nodes_in_group("entities"):\n'
       b'\t\t\t\t\t\tif ent != hero and ent.health > 0 and ent.team != hero.team and not (ent is Turret):\n'
       b'\t\t\t\t\t\t\tif hero.global_position.distance_to(ent.global_position) <= 7.0:\n'
       b'\t\t\t\t\t\t\t\tx3_targets.append(ent)\n'
       b'\t\t\t\t\tif x3_targets.is_empty(): continue\n'
       b'\t\t\t\t\tx3_targets.shuffle()\n'
       b'\t\t\t\t\tvar spawned = 0\n'
       b'\t\t\t\t\tfor x3_t in x3_targets:\n'
       b'\t\t\t\t\t\tif spawned >= 2: break\n'
       b'\t\t\t\t\t\tvar eid = str(x3_t.get_instance_id())\n'
       b'\t\t\t\t\t\tvar hits = r_hit_count.get(eid, 0)\n'
       b'\t\t\t\t\t\tif hits >= 4: continue\n'
       b'\t\t\t\t\t\tvar x3_dir = (x3_t.global_position - hero.global_position).normalized()\n'
       b'\t\t\t\t\t\tvar x3_bullet = create_bullet(400, 0, 1.0, 100*level, true, hero, x3_dir, 3)\n'
       b'\t\t\t\t\t\tx3_bullet.target = x3_t\n'
       b'\t\t\t\t\t\tx3_bullet.set_goal(x3_t.global_position)\n'
       b'\t\t\t\t\t\tx3_bullet.speed = 12.0\n'
       b'\t\t\t\t\t\tif hits > 0: x3_bullet.damage *= 0.5\n'
       b'\t\t\t\t\t\tx3_bullet.life_time = 1.5\n'
       b'\t\t\t\t\t\tr_hit_count[eid] = hits + 1\n'
       b'\t\t\t\t\t\tspawned += 1\n'
       b'\t\t\t\t\t\t# \xe8\xa7\x86\xe8\xa7\x89\xef\xbc\x9a\xe7\xb4\xab\xe8\x89\xb2\xe6\xb5\x81\xe6\x98\x9f\n'
       b'\t\t\t\t\t\tvar x3_vis = MeshInstance3D.new()\n'
       b'\t\t\t\t\t\tx3_vis.mesh = SphereMesh.new()\n'
       b'\t\t\t\t\t\tx3_vis.mesh.radius = 0.3\n'
       b'\t\t\t\t\t\tx3_vis.mesh.height = 0.6\n'
       b'\t\t\t\t\t\tvar x3_mat = StandardMaterial3D.new()\n'
       b'\t\t\t\t\t\tx3_mat.albedo_color = Color(0.7, 0.2, 1.0)\n'
       b'\t\t\t\t\t\tx3_mat.emission_enabled = true\n'
       b'\t\t\t\t\t\tx3_mat.emission = Color(0.5, 0.1, 0.9)\n'
       b'\t\t\t\t\t\tx3_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED\n'
       b'\t\t\t\t\t\tx3_vis.material_override = x3_mat\n'
       b'\t\t\t\t\t\tx3_bullet.add_child(x3_vis)\n'
       b'\t\t\t\t\t\thero.get_parent().add_child(x3_bullet)\n'
       b'\t\t\t\t# \xe9\xa2\x84\xe8\xa7\x88\xe5\x9c\x88\xe6\xb8\x85\xe7\x90\x86\n'
       b'\t\t\t\tif is_instance_valid(r_preview): r_preview.queue_free()\n')

if old in data:
    data = data.replace(old, new, 1)
    write_bytes(path, data)
    print("[OK] Xiao Qiao R: target set + range preview added")
else:
    print("[FAIL] Pattern not found")
    idx = data.find(b'\xe5\xb0\x8f\xe4\xb9\x94')
    if idx >= 0:
        section = data[idx:idx+3000]
        case3 = section.find(b'\t\t\t3:')
        if case3 >= 0:
            print(f"Found case 3 at offset {idx+case3}, showing bytes:")
            print(repr(section[case3:case3+500]))
