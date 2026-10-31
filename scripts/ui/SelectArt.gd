extends RefCounted
## 选人界面复用对局内矢量图标：英雄徽记头像 / 技能图标 / 召唤师技能图标。
## 用法：SelectArt.Avatar.new(hero, team_color, 52)，再 set_hero() 刷新。

class Avatar extends Control:
	const ART = preload("res://scripts/ui/HeroArt.gd")
	var hero_name := ""
	var team_color := Color.WHITE
	var diameter := 44.0

	func _init(p_hero: String = "", p_team: Color = Color.WHITE, p_d: float = 44.0) -> void:
		hero_name = p_hero
		team_color = p_team
		diameter = p_d
		custom_minimum_size = Vector2(p_d, p_d)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_hero(value: String) -> void:
		if hero_name == value:
			return
		hero_name = value
		queue_redraw()

	func _draw() -> void:
		var d := minf(size.x, size.y)
		if d <= 2.0:
			return
		var c := size * 0.5
		var r := d * 0.5 - 1.0
		if hero_name != "":
			ART.draw_portrait(self, c, r, hero_name, team_color, false)
		else:
			draw_circle(c, r, Color(0.03, 0.045, 0.075, 0.94))
			draw_arc(c, r - 1.0, 0.0, TAU, 36, Color(team_color.r, team_color.g, team_color.b, 0.55),
				maxf(r * 0.06, 1.4), true)


class SkillGlyph extends Control:
	const ART = preload("res://scripts/ui/SkillArt.gd")
	var hero_name := ""
	var skill = null
	var slot := 0
	var diameter := 36.0

	func _init(p_hero: String, p_skill, p_slot: int, p_d: float = 36.0) -> void:
		hero_name = p_hero
		skill = p_skill
		slot = p_slot
		diameter = p_d
		custom_minimum_size = Vector2(p_d, p_d)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var d := minf(size.x, size.y)
		if d <= 2.0:
			return
		ART.draw_bg(self, size * 0.5, d * 0.5 - 1.0, hero_name, skill, slot, true, true)


class SummonerGlyph extends Control:
	const ART = preload("res://scripts/ui/IconArt.gd")
	var summoner_name := ""
	var diameter := 36.0

	func _init(p_name: String = "", p_d: float = 36.0) -> void:
		summoner_name = p_name
		diameter = p_d
		custom_minimum_size = Vector2(p_d, p_d)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_summoner(value: String) -> void:
		if summoner_name == value:
			return
		summoner_name = value
		queue_redraw()

	func _draw() -> void:
		var d := minf(size.x, size.y)
		if d <= 2.0:
			return
		ART.draw_icon(self, size * 0.5, d * 0.5 - 1.0,
			ART.kind_for_summoner(summoner_name), false)


## 装备图标（选人页出装顺序用，与对局商店同一套程序化图标）
class ItemIcon extends Control:
	const GLYPH = preload("res://scripts/ui/ItemGlyph.gd")
	var item_name := ""
	var tier := 1
	var diameter := 44.0

	func _init(p_item: String = "", p_tier: int = 1, p_d: float = 44.0) -> void:
		item_name = p_item
		tier = clampi(p_tier, 1, 5)
		diameter = p_d
		custom_minimum_size = Vector2(p_d, p_d)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var d := minf(size.x, size.y)
		if d <= 2.0:
			return
		GLYPH.draw(self, Rect2(Vector2.ZERO, Vector2(d, d)), tier, UiKit.QUALITY_COLORS[tier], item_name)
