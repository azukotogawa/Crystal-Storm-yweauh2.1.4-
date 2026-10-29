class_name HudLayout
extends Resource

const RESOURCE_PATH := "res://config/default_hud_layout.tres"

@export var objective_origin := Vector2(24, 24)
@export var objective_size := Vector2(328, 176)
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

@export var safe_margin := 24.0
@export var region_gap := 12.0
@export var minimap_px := 160.0
@export var leave_size := Vector2(128, 28)
@export var boss_size := Vector2(340, 44)
@export var toast_size := Vector2(440, 36)
@export var toast_top_ratio := 0.3
@export var hotbar_size := Vector2(574, 52)
@export var vitals_size := Vector2(292, 106)
@export var skill_size := Vector2(328, 40)
@export var chat_height := 280.0
@export var chip_size := Vector2(268, 20)
@export var hotbar_name_h := 24.0
@export var phase_size := Vector2(420, 72)
@export var status_height := 170.0


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


func margin_for(view: Vector2) -> float:
	return safe_margin * view.y / 720.0


func safe_area(view: Vector2) -> Rect2:
	var m := margin_for(view)
	return Rect2(Vector2(m, m), view - Vector2(m, m) * 2.0)


func regions(view: Vector2, minimap_override: float = -1.0) -> Dictionary:
	var m := margin_for(view)
	var mini := minimap_px if minimap_override < 0.0 else minimap_override
	var out := {}
	out["objective"] = Rect2(Vector2(m, m), objective_size)
	out["boss"] = Rect2(Vector2((view.x - boss_size.x) * 0.5, m), boss_size)
	out["minimap"] = Rect2(Vector2(view.x - m - mini, m), Vector2(mini, mini))
	out["leave_world"] = Rect2(Vector2(view.x - m - leave_size.x, m + mini + region_gap), leave_size)
	out["toast"] = Rect2(Vector2((view.x - toast_size.x) * 0.5, view.y * toast_top_ratio), toast_size)
	var pad := backing_pad
	var hot := Rect2(
		Vector2((view.x - hotbar_size.x) * 0.5 - pad, view.y - m - hotbar_size.y - pad * 2.0),
		hotbar_size + Vector2(pad, pad) * 2.0
	)
	out["hotbar"] = hot
	var vit := Rect2(
		Vector2((view.x - vitals_size.x) * 0.5, hot.position.y - hotbar_name_h - region_gap - vitals_size.y),
		vitals_size
	)
	out["vitals"] = vit
	out["skill_bar"] = Rect2(
		Vector2(minf(vit.end.x + region_gap, view.x - m - skill_size.x), vit.end.y - skill_size.y),
		skill_size
	)
	var phase_w := clampf(view.x - m - (view.x + toast_size.x) * 0.5 - region_gap * 6.0, minf(260.0, phase_size.x), phase_size.x)
	out["phase"] = Rect2(Vector2(view.x - m - phase_w, m + mini + region_gap + leave_size.y + region_gap), Vector2(phase_w, phase_size.y))
	var left_w := maxf(hot.position.x - region_gap - m, 120.0)
	var status := Rect2(Vector2(m, view.y - m - status_height), Vector2(left_w, status_height))
	out["status"] = status
	var chat_top := maxf(status.position.y - region_gap - chat_height, m + objective_size.y + region_gap)
	out["chat"] = Rect2(Vector2(m, chat_top), Vector2(left_w, status.position.y - region_gap - chat_top))
	var chip_x := hot.end.x + region_gap
	if view.x - m - chip_x >= chip_size.x:
		out["chip"] = Rect2(Vector2(chip_x, view.y - m - chip_size.y), Vector2(view.x - m - chip_x, chip_size.y))
	else:
		var sk: Rect2 = out["skill_bar"]
		out["chip"] = Rect2(Vector2(view.x - m - chip_size.x, sk.position.y - region_gap - chip_size.y), chip_size)
	return out


func region(view: Vector2, id: String, minimap_override: float = -1.0) -> Rect2:
	return regions(view, minimap_override).get(id, Rect2())


static func place(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.grow_horizontal = Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_END
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


static func view_of(node: Node) -> Vector2:
	var vp := node.get_viewport() if node.is_inside_tree() else null
	if vp == null:
		return Vector2(1280, 720)
	return vp.get_visible_rect().size
