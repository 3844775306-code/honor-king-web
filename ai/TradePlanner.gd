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
	if hero == null or not is_instance_valid(hero) or hero.is_dead:
		deaths += 1
		_finish(false)
		return
	if _should_exit():
		_finish(false)
		safe_pos = threat.safe_position()
		exit_timer = 1.1
		cooldown = EXIT_COOLDOWN


## 被攻击时判断是否主动换血：已锁定该目标，或当前没有换血且该目标会被选为换血对象
func should_trade_with(target: Hero) -> bool:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return false
	if active_target == target:
		return true
	if active_target != null:
		return false
	if cooldown > 0.0 or exit_timer > 0.0:
		return false
	return _pick_target() == target


## 反击：无视换血冷却/血量/目标筛选等限制，直接强制与指定敌人对拼
func force_engage(target: Hero) -> void:
	if target == null or not is_instance_valid(target) or target.health <= 0.0:
		return
	exit_timer = 0.0
	cooldown = 0.0
	active_target = target
	_start_trade(target)


func evaluate() -> Dictionary:
	if active_target != null:
		if not is_instance_valid(active_target) or active_target.health <= 0.0:
			_finish(true)
			return {}
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


func _should_exit() -> bool:
	if active_time > TRADE_MAX_TIME:
		return true
	if hero.health <= hero.actual_max_health * 0.38:
		return true
	if active_target == null or not is_instance_valid(active_target):
		return true
	var dist := hero.global_position.distance_to(active_target.global_position)
	if dist > MAX_TRADE_RANGE + 2.0:
		return true
	if _is_under_enemy_tower(active_target) and not AiConfig.should_engage_tower_hero(hero, active_target):
		return true
	# 对方恢复健康且我方没有血量优势：不继续纠缠
	var my_ratio := hero.health / maxf(1.0, hero.actual_max_health)
	var t_ratio := active_target.health / maxf(1.0, active_target.actual_max_health)
	if t_ratio > my_ratio + 0.08 and active_time > 0.8:
		return true
	# 敌方增援导致威胁明显恶化
	if threat.threat_balance() < -0.8:
		return true
	# 本次换血已打出正向交换且目标不是残血可收：主动收手，避免追进危险区
	var cur_out := hero.damage_dealt_to_heroes - _start_damage_out
	var cur_in := hero.damage_taken_from_heroes - _start_damage_in
	if active_time > 0.9 and cur_out > cur_in + 300.0 and t_ratio > 0.22:
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
		if _is_under_enemy_tower(target) and not AiConfig.should_engage_tower_hero(hero, target):
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



