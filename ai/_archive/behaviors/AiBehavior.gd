class_name AiBehavior
extends RefCounted

var hero: Hero
var perception: AiPerception
var tactics: SkillTactics


func _init(p_hero: Hero, p_perception: AiPerception, p_tactics: SkillTactics) -> void:
	hero = p_hero
	perception = p_perception
	tactics = p_tactics


func enter() -> void:
	pass


func execute(_delta: float) -> void:
	pass


func exit() -> void:
	pass
