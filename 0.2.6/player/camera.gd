extends Camera3D

const _GameplayInput = preload("res://helpers/gameplay_input.gd")

@export var target: Node3D
@export var use_smoothing := true
@export var smooth_speed: float = 3.0
var follow_target: Vector3

@export var distance := 100.0
@export var height_offset := 101.0   # Fine-tune this for best cube look

## Edge scroll: pan look-at when the mouse sits near the screen border.
@export var edge_scroll_enabled: bool = true
@export var edge_scroll_margin_px: float = 28.0
@export var edge_scroll_speed: float = 42.0
@export var edge_scroll_max_lead: float = 48.0

var orbit_rotation := 0
var zoom_level := 24.0
const ZOOM_STEP := 2.0
const MIN_ZOOM := 8.0
const MAX_ZOOM := 140.0

var player: Player
## Soft lead offset from player (edge scroll / look-ahead).
var _scroll_lead: Vector3 = Vector3.ZERO

func _ready():
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = zoom_level
	
	target = get_tree().get_first_node_in_group("player")
	player = target
	
	if not target:
		call_deferred("_find_target")
	add_to_group("camera")
	

func _find_target():
	target = get_tree().get_first_node_in_group("player")
	player = target
	if target:
		_update_camera_transform()
	follow_target = target.global_position

func _process(delta: float):
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("camera_update")
	if not target:
		if not player:
			player = get_tree().get_first_node_in_group("player")
			target = player
		if not target:
			if profiler and profiler.has_method("end"):
				profiler.end("camera_update")
			return

	if not _GameplayInput.blocks_actions():
		_apply_edge_scroll(delta)

	var anchor: Vector3 = target.global_position + _scroll_lead
	var desired_pos = anchor + get_offset_from_rotation()

	if use_smoothing:
		follow_target = follow_target.lerp(anchor, clampf(0.10 + delta * 2.0, 0.0, 0.35))
		desired_pos = follow_target + get_offset_from_rotation()
		global_position = desired_pos
	else:
		follow_target = anchor
		global_position = desired_pos

	# Keep fixed isometric rotation
	rotation_degrees = Vector3(-35.264, 45.0 + orbit_rotation * 90.0, 0.0)
	if profiler and profiler.has_method("end"):
		profiler.end("camera_update")


func _apply_edge_scroll(delta: float) -> void:
	if not edge_scroll_enabled:
		_scroll_lead = _scroll_lead.lerp(Vector3.ZERO, clampf(delta * 4.0, 0.0, 1.0))
		return
	var vp := get_viewport()
	if vp == null:
		return
	var rect := vp.get_visible_rect()
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return
	var mouse := vp.get_mouse_position()
	var m: float = edge_scroll_margin_px
	var sx: float = 0.0
	var sy: float = 0.0
	if mouse.x <= rect.position.x + m:
		sx = -1.0 + (mouse.x - rect.position.x) / m  # -1 at edge → 0 at margin
		sx = clampf(sx, -1.0, 0.0)
	elif mouse.x >= rect.end.x - m:
		sx = (mouse.x - (rect.end.x - m)) / m  # 0 → 1
		sx = clampf(sx, 0.0, 1.0)
	if mouse.y <= rect.position.y + m:
		sy = -1.0 + (mouse.y - rect.position.y) / m
		sy = clampf(sy, -1.0, 0.0)
	elif mouse.y >= rect.end.y - m:
		sy = (mouse.y - (rect.end.y - m)) / m
		sy = clampf(sy, 0.0, 1.0)
	if is_zero_approx(sx) and is_zero_approx(sy):
		# Ease lead back to player when not edge-scrolling.
		_scroll_lead = _scroll_lead.lerp(Vector3.ZERO, clampf(delta * 3.5, 0.0, 1.0))
		return
	# Screen axes → world XZ for current isometric yaw (orbit steps of 90°).
	var yaw: float = deg_to_rad(45.0 + float(orbit_rotation) * 90.0)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()
	var forward := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	# Screen up is -forward in this iso framing; screen right is +right.
	var move: Vector3 = right * sx + forward * (-sy)
	if move.length_squared() > 0.0001:
		move = move.normalized()
	_scroll_lead += move * edge_scroll_speed * delta
	if _scroll_lead.length() > edge_scroll_max_lead:
		_scroll_lead = _scroll_lead.normalized() * edge_scroll_max_lead

func get_offset_from_rotation() -> Vector3:
	var angle = deg_to_rad(orbit_rotation * 90.0)
	var x = 0
	var z = 0
	if orbit_rotation % 2 == 0:
		x = cos(angle) * distance
		z = cos(angle) * distance
	elif orbit_rotation == 1:
		x = (sin(angle-45) * distance * 2) - 5
		z = (sin(angle-90) * distance * 2) - 10.5
	else:
		x = (sin(angle-45) * distance * 2) + 5
		z = (sin(angle-90) * distance * 2) + 10.5
	
	return Vector3(x, height_offset, z)

func _unhandled_input(event):
	if _GameplayInput.blocks_actions():
		return
	if event.is_action_pressed("rotate_left"):
		orbit_rotation = (orbit_rotation + 3) % 4
		_update_camera_transform()
	elif event.is_action_pressed("rotate_right"):
		orbit_rotation = (orbit_rotation + 1) % 4
		_update_camera_transform()

func _update_camera_transform():
	if not target:
		return
	global_position = target.global_position + _scroll_lead + get_offset_from_rotation()
	rotation_degrees = Vector3(-35.264, 45.0 + orbit_rotation * 90.0, 0.0)

func _input(event):
	if _GameplayInput.blocks_actions():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = max(zoom_level - ZOOM_STEP, MIN_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = min(zoom_level + ZOOM_STEP, MAX_ZOOM)
		size = zoom_level
