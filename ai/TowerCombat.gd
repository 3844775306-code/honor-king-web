class_name TowerCombat
extends RefCounted
## 塔下目标评估：手长英雄可在塔外消耗；越塔前估算会吃几次塔伤，>2 次放弃。

static func tower_guarding(target: GameEntity) -> Turret:
	if target == null or not is_instance_valid(target):
		return null
	for e in target.get_tree().get_nodes_in_group("turrets"):
		if not (e is Turret) or (e as Turret).health <= 0 or int((e as Turret).team) == int(target.team):
			continue
		var t := e as Turret
		if target.global_position.distance_to(t.global_position) <= t.attack_range * 0.01:
			return t
	return null


static func can_attack_under_tower(hero: Hero, target: GameEntity) -> bool:
	if hero == null or target == null or not is_instance_valid(target) or target.health <= 0:
		return false
	var tower := tower_guarding(target)
	if tower == null:
		return true
	var range_world := hero.attack_range * 0.01
	# 站在塔外就能打到目标：只做远程消耗，不进塔。
	var dir := (target.global_position - tower.global_position)
	dir.y = 0.0
	if dir.length() > 0.01:
		var stand := target.global_position - dir.normalized() * minf(range_world, 4.0)
		if hero.global_position.distance_to(tower.global_position) > tower.attack_range * 0.01 \
				and hero.global_position.distance_to(target.global_position) <= range_world + 1.0:
			return true
	# 越塔估算：预计塔伤次数 >2 放弃。
	return estimated_tower_hits(hero, target, tower) <= 2


static func estimated_tower_hits(hero: Hero, target: GameEntity, tower: Turret) -> int:
	var aa := maxf(1.0, hero.actual_attack_damage)
	var target_hp := maxf(1.0, target.health + target.shield_remaining)
	var hits_to_kill := int(ceil(target_hp / aa))
	var atk_interval := 1.0 / maxf(0.2, hero.attack_speed)
	var time_in_tower := float(hits_to_kill) * atk_interval + 0.8 + 0.6   # 进场 + 撤退
	var tower_interval := 1.0 / maxf(0.2, tower.attack_speed)
	# 己方小兵在塔下时，塔第一目标可能不是英雄；但没有兵线时直接按塔伤计。
	var hits := int(ceil(time_in_tower / tower_interval))
	return maxi(1, hits)
