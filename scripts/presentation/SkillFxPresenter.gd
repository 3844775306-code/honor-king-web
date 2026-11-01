class_name SkillFxPresenter
extends RefCounted
## 三端共享「技能出手视觉」：host 的 Vfx.play_spell 是唯一真源。
## - host：Hero._finish_casting 直接调 Vfx.play_spell（并广播 NET_FX_SPELL_FULL 事件，带 skill id）
## - 联机：收到 FX_SPELL_FULL → 用同一 skill id 取 SkillDatabase 原技能 → 调同一 Vfx.play_spell
## - 回放：录像 cast 事件带 skill id → 同样还原
## 三端只有一份"技能特效参数→视觉"实现，避免签名技能/元素爆发越做越偏。

const BulletVisualScript = preload("res://scripts/core/BulletVisual.gd")


## 反查 Skill 资源对应的 SkillDatabase id（manifest / 录像 / 网络事件共用）
static func skill_id_of(skill) -> String:
	if skill == null:
		return ""
	for sid in SkillDatabase.skills:
		if SkillDatabase.skills[sid] == skill:
			return str(sid)
	return ""


## 优先用 skill id 取数据库原技能；缺失时用事件里的最小参数重建（旧录像/旧 host 兼容）
static func spell_from(skill_id: String, skd: Dictionary) -> Skill:
	if skill_id != "":
		var sk: Skill = SkillDatabase.get_skill(skill_id)
		if sk != null:
			return sk
	var s := Skill.new()
	s.type = int(skd.get("type", 1))
	s.radius = float(skd.get("radius", 0.0))
	s.duration = float(skd.get("duration", 0.0))
	s.self_displacement = float(skd.get("self_displacement", -1.0))
	s.is_channeling = bool(skd.get("is_channeling", false))
	return s


## 统一播放入口：联机/回放调用后与 host 本地播放完全同源（含 ground_zone 持续区域）
static func play_spell(caster: String, slot: int, cp: Vector3, tp: Vector3, fd: Vector3,
		skill_id: String, skd: Dictionary, team: int, ground_parent: Node, is_local: bool = false) -> void:
	if caster == "":
		return
	var skill := spell_from(skill_id, skd)
	Vfx.play_spell(caster, slot, cp + Vector3.UP * 1.2 + fd * 0.65, tp, skill, fd, is_local)
	# 持续区域技能（甄姬水区/周瑜火区/王昭君暴风雪等）：与对局同一 ground_zone 复现
	if int(skill.type) != 4 and float(skill.radius) >= 2.0 and float(skill.duration) >= 0.6:
		var zn := Vfx.ground_zone(float(skill.radius), team, caster, maxf(0.8, float(skill.duration)))
		if zn != null and is_instance_valid(zn) and ground_parent != null:
			zn.position = Vector3(tp.x, 0.06, tp.z)
			ground_parent.add_child(zn)


## 通用技能视觉档（爆发/大招/位移/蓄力/光柱）→ host 同款 Vfx 原语（与单机技能特效同源）
static func spawn_kind(kind: int, p: Vector3, team: int, r: float, life: float, caster: String) -> void:
	match kind:
		27:  # FX_PILLAR
			Vfx.pillar(p, _col(caster, team), maxf(r, 0.8), maxf(r * 3.0, 4.0), maxf(life, 0.5))
		26:  # FX_SKILL_ULT
			Vfx.cast_burst(caster, p, Vector3.UP, 2.0)
			Vfx.shockwave(p, maxf(r, 2.0), _col(caster, team), maxf(life, 0.6))
			Vfx.pillar(p, _col(caster, team), maxf(r * 0.5, 0.8), maxf(r * 2.4, 4.0), maxf(life, 0.6))
		25:  # FX_SKILL_DASH
			Vfx.cast_glow(p, _col(caster, team), maxf(r, 0.8), maxf(life, 0.3))
			Vfx.shockwave(p, maxf(r, 1.0), _col(caster, team), maxf(life, 0.3))
		28:  # FX_SKILL_GLOW
			Vfx.cast_glow(p, _col(caster, team), maxf(r, 0.8), maxf(life, 0.3))
		_:   # FX_SKILL_BURST
			Vfx.cast_burst(caster, p, Vector3.UP, 1.2)
			Vfx.shockwave(p, maxf(r, 1.0), _col(caster, team), maxf(life, 0.4))


static func _col(caster: String, team: int) -> Color:
	if caster != "":
		return Vfx.color_for_hero(caster)
	return Vfx.team_color(team)
