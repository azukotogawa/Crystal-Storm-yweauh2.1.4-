class_name HudLayout
extends Resource

const RESOURCE_PATH := "res://config/default_hud_layout.tres"

@export var objective_origin := Vector2(12, 12)
@export var objective_size := Vector2(328, 164)
@export var clearance := 18.0

@export var chapter_margin_right := 16.0
@export var chapter_top := 56.0
@export var chapter_width := 420.0
@export var chapter_height := 40.0

@export var clock_left := 16.0
@export var clock_gap := 22.0

@export var debug_width := 460.0
@export var debug_height := 168.0

@export var backing := Color(0.02, 0.025, 0.04, 0.62)
@export var backing_pad := 10.0

@export var vitals_left := -146.0
@export var vitals_right := 146.0
@export var vitals_top := -176.0
@export var vitals_bottom := -70.0


static func load_active() -> HudLayout:
	var script: Script = load("res://config/hud_layout.gd")
	if ResourceLoader.exists(RESOURCE_PATH):
		var loaded: Resource = load(RESOURCE_PATH)
		if loaded != null and loaded.get_script() == script:
			return loaded as HudLayout
	return script.new() as HudLayout


func objective_rect() -> Rect2:
	return Rect2(objective_origin, objective_size)


func clock_position() -> Vector2:
	var rect := objective_rect()
	return Vector2(clock_left, rect.end.y + clock_gap)


func debug_position() -> Vector2:
	var rect := objective_rect()
	return Vector2(rect.end.x + clearance, rect.position.y)


func chapter_rect(viewport_size: Vector2) -> Rect2:
	var obj := objective_rect()
	var width := chapter_width
	var top := chapter_top
	var left := viewport_size.x - chapter_margin_right - width
	if left < obj.end.x + clearance:
		top = obj.end.y + clock_gap + chapter_height
		var room := viewport_size.x - chapter_margin_right - (obj.end.x + clearance)
		width = minf(width, maxf(120.0, room))
		left = viewport_size.x - chapter_margin_right - width
	return Rect2(left, top, width, chapter_height)


func misses_objective(rect: Rect2) -> bool:
	return not objective_rect().intersects(rect)
