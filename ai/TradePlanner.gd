class_name TradePlanner
extends RefCounted
## AI 换血决策：先算威胁/技能/血量，再决定进场、持有或退出。
## 与旧逻辑的区别：不再“有目标就一路追”，而是有明确 trade window 和撤退条件。

enum Action { NONE, ENTER, HOLD, EXIT }

const TRADE_MAX_TIME := 2.4          # 单次主动换血最长窗口
const EXIT_COOLDOWN := 2.8          # 退出后不立刻二次进场
const MAX_TRADE_RANGE := 9.0
const MIN_ENTER_SCORE := 1.35

var hero: Hero
var threat: ThreatModel
var perception: AiPerception
var active_target: Hero = null
var active_time := 0.0
var exit_timer := 0.0
var cooldown := 0.0
var safe_pos := Vector3.ZERO
var micro_retreat_timer := 0.0    # 换血时血量低于目标：远离目标 1 秒
var micro_retreat_pos := Vector3.ZERO

# 供 240 秒指标读取
var attempts := 0
var wins := 0
var damage_out := 0.0
var damage_in := 0.0
var deaths := 0
var _start_damage_out := 0.0
var _start_damage_in := 0.0
var _start_my_hp := 0.0
var _start_target_hp := 0.0


func _init(p_hero: Hero, p_threat: ThreatModel, p_perception: AiPerception) -> void:
	hero = p_hero
	threat = p_threat
	perception = p_perception


func update(delta: float, _game_time: float) -> void:
	if micro_retreat_timer > 0.0:
		micro_retreat_timer = maxf(0.0, micro_retreat_timer - delta)
	if exit_timer > 0.0:
		exit_timer = maxf(0.0, exit_timer - delta)
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)
	if active_target == null:
		return
	active_time += delta
	if not is_instance_valid(active_target) or active_target.health <= 0.0:
		_finish(true)
		return
	# 血量比目标少 → 正在远离目标的 1 秒窗口：不推翻、不提前结束换血
	if micro_retreat_timer > 0.0:
		return
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		deaths += 1
		_finish(false)
		return
	if _should_exit():
		_finish(false)
		safe_pos = threat.safe_position()
		exit_timer = 1.1
		cooldown = EXIT_COOLDOWN


func evaluate() -> Dictionary:
	if active_target != null:
		if not is_instance_valid(active_target) or active_target.health <= 0.0:
			_finish(true)
			return {}
		if micro_retreat_timer > 0.0:
			return {"action": "exit", "pos": micro_retreat_pos, "target": active_target, "micro": true}
		# 只要自己血量比换血目标少：立刻往远离目标的方向移动 1 秒；否则继续攻击
		if hero.health < active_target.health:
			_start_micro_retreat(active_target)
			return {"action": "exit", "pos": micro_retreat_pos, "target": active_target, "micro": true}
		return {"action": "hold", "target": active_target}
	if exit_timer > 0.0 or cooldown > 0.0 or hero == null or not is_instance_valid(hero) or hero.is_dead:
		if exit_timer > 0.0:
			return {"action": "exit", "pos": safe_pos}
		return {}
	var target := _pick_target()
	if target == null:
		return {}
	_start_trade(target)
	return {"action": "enter", "target": target}


func _start_trade(target: Hero) -> void:
	active_target = target
	active_time = 0.0
	_start_damage_out = hero.damage_dealt_to_heroes
	_start_damage_in = hero.damage_taken_from_heroes
	_start_my_hp = hero.health
	_start_target_hp = target.health
	attempts += 1


func _finish(win: bool) -> void:
	var cur_out := maxf(0.0, hero.damage_dealt_to_heroes - _start_damage_out)
	var cur_in := maxf(0.0, hero.damage_taken_from_heroes - _start_damage_in)
	damage_out += cur_out
	damage_in += cur_in
	var actual_win := win
	if not actual_win and active_target != null and is_instance_valid(active_target) and hero != null:
		var my_ratio := hero.health / maxf(1.0, hero.actual_max_health)
		var t_ratio := (active_target as Hero).health / maxf(1.0, (active_target as Hero).actual_max_health)
		actual_win = t_ratio < my_ratio
	if actual_win:
		wins += 1
	active_target = null
	active_time = 0.0
	cooldown = maxf(cooldown, 1.0)


## 血量低于换血目标：朝远离目标方向走 1 秒（按当前移速折算距离）
func _start_micro_retreat(target: Hero) -> void:
	var away := hero.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var step: float = maxf(3.0, hero.actual_move_speed * 1.0)
	micro_retreat_pos = hero.global_position + away.normalized() * step
	micro_retreat_timer = 1.0

func _should_exit() -> bool:
	if active_time > TRADE_MAX_TIME:
		return true
	if active_target == null or not is_instance_valid(active_target):
		return true
	var dist := hero.global_position.distance_to(active_target.global_position)
	if dist > MAX_TRADE_RANGE + 2.0:
		return true
	if _is_under_enemy_tower(active_target):
		return true
	# 血量比较改由 evaluate 的「1 秒远离」微操处理，这里不再直接退出
	# 敌方增援导致威胁明显恶化
	if threat.threat_balance() < -0.8:
		return true
	return false


func _pick_target() -> Hero:
	if hero.health <= 0.0:
		return null
	var my_ratio := hero.health / maxf(1.0, hero.actual_max_health)
	if my_ratio < 0.45:
		return null
	var my_reach := maxf(2.5, hero.attack_range * 0.01) + 1.0
	var ally_near := threat.ally_count_near(12.0)
	var enemy_near := threat.enemy_count_near(12.0)
	if enemy_near > ally_near + 1:
		return null
	var best: Hero = null
	var best_score := MIN_ENTER_SCORE
	for rec in threat.visible_enemies():
		var h = rec.get("node")
		if h == null or not is_instance_valid(h) or h.health <= 0.0:
			continue
		var target := h as Hero
		if target.is_untargetable_by_enemies() or target.is_in_own_fountain():
			continue
		var dist := hero.global_position.distance_to(target.global_position)
		if dist > MAX_TRADE_RANGE:
			continue
		if _is_under_enemy_tower(target):
			continue
		var t_ratio := target.health / maxf(1.0, target.actual_max_health)
		var score := 0.0
		if t_ratio < my_ratio - 0.12:
			score += 1.6
		if t_ratio < 0.45:
			score += 1.0
		if _has_cc(target):
			score += 1.4
		if _ready_skill_count() >= 1:
			score += 0.7
		if dist <= my_reach:
			score += 0.7
		if target.role in ["射手", "法师"]:
			score += 0.35
		# 目标周围有没有更多敌人：有队友一起打才提高多人换血分
		var cluster := 0
		for other in threat.visible_enemies():
			var node = other.get("node")
			if node != null and node != target and hero.global_position.distance_to((node as Node3D).global_position) <= 5.0:
				cluster += 1
		if cluster >= 1 and ally_near >= 1:
			score += 0.25
		if score > best_score:
			best_score = score
			best = target
	return best


func _ready_skill_count() -> int:
	var n := 0
	for i in range(mini(3, hero.skills.size())):
		if hero.skills[i] == null or i >= hero.skill_levels.size() or hero.skill_levels[i] <= 0:
			continue
		if i < hero.skill_cooldowns.size() and hero.skill_cooldowns[i] <= 0.0:
			n += 1
	return n


func _has_cc(target: Hero) -> bool:
	return target.stun_timer > 0.0 or target.knockup_timer > 0.0 \
		or target.froze_timer > 0.0 or target.suppress_timer > 0.0


func _is_under_enemy_tower(target: Hero) -> bool:
	for t in hero.get_tree().get_nodes_in_group("turrets"):
		if not (t is Turret) or t.health <= 0 or int(t.team) == int(hero.team):
			continue
		if target.global_position.distance_to((t as Turret).global_position) > AiConfig.TOWER_ATTACK_RANGE:
			continue
		# 有己方兵线掩护才允许在塔边换血
		var cover := 0.0
		for m in hero.get_tree().get_nodes_in_group("minions"):
			if m is Minion and m.health > 0 and int(m.team) == int(hero.team) \
					and (t as Turret).global_position.distance_to((m as Minion).global_position) <= AiConfig.TOWER_ATTACK_RANGE:
				cover += (m as Minion).health
		if cover < 500.0:
			return true
	return false


