extends Camera3D

const _GameplayInput = preload("res://helpers/gameplay_input.gd")

@export var target: Node3D
@export var use_smoothing := true
@export var smooth_speed: float = 3.0
@export var rotation_speed_deg: float = 480.0

var follow_target: Vector3

@export var distance := 100.0
@export var height_offset := 101.0

## Animated orbit offset from base isometric yaw (0, 90, 180, 270).
var orbit_yaw_deg: float = 0.0
var _orbit_target_deg: float = 0.0

var zoom_level := 24.0
const ZOOM_STEP := 2.0
const MIN_ZOOM := 8.0
const MAX_ZOOM := 140.0

var player: Player


var orbit_rotation: int:
	get:
		return int(roundi(fmod(orbit_yaw_deg, 360.0) / 90.0)) % 4


func get_move_yaw_deg() -> float:
	return 45.0 + orbit_yaw_deg


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = zoom_level

	target = get_tree().get_first_node_in_group("player")
	player = target

	if not target:
		call_deferred("_find_target")
	add_to_group("camera")


func _find_target() -> void:
	target = get_tree().get_first_node_in_group("player")
	player = target
	if target:
		_sync_camera_transform()
	follow_target = target.global_position


func _process(delta: float) -> void:
	if not target:
		if not player:
			player = get_tree().get_first_node_in_group("player")
			target = player
		if not target:
			return

	_advance_orbit_yaw(delta)

	var target_pos := target.global_position
	var desired_pos := target_pos + get_offset_from_rotation()

	if use_smoothing:
		follow_target = follow_target.lerp(target.global_position, 0.10)
		desired_pos = follow_target + get_offset_from_rotation()
		global_position = desired_pos
	else:
		global_position = desired_pos

	_apply_orbit_rotation()


func _corner_offset(idx: int) -> Vector3:
	var angle := deg_to_rad(float(idx) * 90.0)
	var x := 0.0
	var z := 0.0
	if idx % 2 == 0:
		x = cos(angle) * distance
		z = cos(angle) * distance
	elif idx == 1:
		x = (sin(angle - 45.0) * distance * 2.0) - 5.0
		z = (sin(angle - 90.0) * distance * 2.0) - 10.5
	else:
		x = (sin(angle - 45.0) * distance * 2.0) + 5.0
		z = (sin(angle - 90.0) * distance * 2.0) + 10.5
	return Vector3(x, height_offset, z)


func get_offset_from_rotation() -> Vector3:
	var t: float = fmod(orbit_yaw_deg, 360.0) / 90.0
	if t < 0.0:
		t += 4.0
	var i0: int = int(floor(t)) % 4
	var i1: int = (i0 + 1) % 4
	var frac: float = smoothstep(0.0, 1.0, t - floor(t))
	return _corner_offset(i0).lerp(_corner_offset(i1), frac)


func _apply_orbit_rotation() -> void:
	var t: float = fmod(orbit_yaw_deg, 360.0) / 90.0
	if t < 0.0:
		t += 4.0
	var i0: int = int(floor(t)) % 4
	var i1: int = (i0 + 1) % 4
	var frac: float = smoothstep(0.0, 1.0, t - floor(t))
	var yaw0: float = 45.0 + float(i0) * 90.0
	var yaw1: float = 45.0 + float(i1) * 90.0
	var yaw: float = rad_to_deg(lerp_angle(deg_to_rad(yaw0), deg_to_rad(yaw1), frac))
	rotation_degrees = Vector3(-35.264, yaw, 0.0)


func _advance_orbit_yaw(delta: float) -> void:
	var diff: float = _orbit_target_deg - orbit_yaw_deg
	diff = fmod(diff + 180.0, 360.0) - 180.0
	if absf(diff) < 0.05:
		orbit_yaw_deg = _orbit_target_deg
		return
	var step: float = rotation_speed_deg * delta
	if absf(diff) <= step:
		orbit_yaw_deg = _orbit_target_deg
	else:
		orbit_yaw_deg += signf(diff) * step


func _step_orbit_target(delta_steps: int) -> void:
	_orbit_target_deg += float(delta_steps) * 90.0
	var diff: float = _orbit_target_deg - orbit_yaw_deg
	if diff > 180.0:
		orbit_yaw_deg += 360.0
	elif diff < -180.0:
		orbit_yaw_deg -= 360.0


func _unhandled_input(event: InputEvent) -> void:
	if _GameplayInput.blocks_actions():
		return
	if event.is_action_pressed("rotate_left"):
		_step_orbit_target(-1)
	elif event.is_action_pressed("rotate_right"):
		_step_orbit_target(1)


func _sync_camera_transform() -> void:
	if not target:
		return
	global_position = target.global_position + get_offset_from_rotation()
	_apply_orbit_rotation()


func _input(event: InputEvent) -> void:
	if _GameplayInput.blocks_actions():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = maxf(zoom_level - ZOOM_STEP, MIN_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = minf(zoom_level + ZOOM_STEP, MAX_ZOOM)
		size = zoom_level