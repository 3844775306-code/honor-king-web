class_name HeroStatView
extends RefCounted
## 结算面板的"英雄数据适配器"：把联机/回放的统计行字典包装成与 Hero 同名属性，
## 让 ResultsPanel 只写一套 UI 就能同时渲染 单机 Hero / 联机结算行 / 回放行。

var display_name := ""
var player_name := ""
var role := ""
var team := 0
var level := 1
var kills := 0
var deaths := 0
var assists := 0
var damage_dealt_to_heroes := 0.0
var damage_taken_from_heroes := 0.0
var healing_done := 0.0
var total_gold_earned := 0
var last_hits := 0
var turret_damage := 0.0
var cc_duration_dealt := 0.0
var jungle_gold := 0
var equipment_slots: Array = []
var health := 1.0
var is_ai := true
var is_mvp := false
var max_health := 1.0


## row 字段与联机结算 / 回放 / 对战纪录共用：name/role/team/k/d/a/dmg/taken/heal/gold/lh/turret/cc/jungle/mvp/ai/nick
static func from_row(r: Dictionary) -> HeroStatView:
	var v := HeroStatView.new()
	v.display_name = str(r.get("name", ""))
	v.player_name = str(r.get("nick", r.get("pname", "")))
	v.role = str(r.get("role", ""))
	v.team = int(r.get("team", 0))
	v.level = int(r.get("level", r.get("lvl", 1)))
	v.kills = int(r.get("k", 0))
	v.deaths = int(r.get("d", 0))
	v.assists = int(r.get("a", 0))
	v.damage_dealt_to_heroes = float(r.get("dmg", 0.0))
	v.damage_taken_from_heroes = float(r.get("taken", 0.0))
	v.healing_done = float(r.get("heal", 0.0))
	v.total_gold_earned = int(r.get("tgold", r.get("gold", 0)))
	v.last_hits = int(r.get("lh", r.get("last_hits", 0)))
	v.turret_damage = float(r.get("turret", 0.0))
	v.cc_duration_dealt = float(r.get("cc", 0.0)) / 10.0 if float(r.get("cc", 0.0)) > 20.0 else float(r.get("cc", 0.0))
	v.jungle_gold = int(r.get("jungle", 0))
	v.health = float(r.get("hp", 1.0))
	v.max_health = float(r.get("maxhp", 1.0))
	v.is_ai = bool(r.get("ai", true))
	v.is_mvp = bool(r.get("mvp", false))
	# 单机/联机/回放三种行字段名历史上分别为 items/equips/equip，统一兼容
	var items = r.get("items", r.get("equips", r.get("equip", [])))
	if items is Array:
		v.equipment_slots = items.duplicate()
	return v
