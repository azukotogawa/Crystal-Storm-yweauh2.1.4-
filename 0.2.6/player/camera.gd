extends Camera3D

const _GameplayInput = preload("res://helpers/gameplay_input.gd")

@export var target: Node3D
@export var use_smoothing := true
@export var smooth_speed: float = 3.0
var follow_target: Vector3

@export var distance := 100.0
@export var height_offset := 101.0   # Fine-tune this for best cube look

var orbit_rotation := 0
var zoom_level := 24.0
const ZOOM_STEP := 2.0
const MIN_ZOOM := 8.0
const MAX_ZOOM := 140.0

var player: Player

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
	if not target:
		if not player:
			player = get_tree().get_first_node_in_group("player")
			target = player
		if not target:
			return
	var target_pos = target.global_position
	var desired_pos = target_pos + get_offset_from_rotation()

	if use_smoothing:
		follow_target = follow_target.lerp(
			target.global_position,
			0.10
		)

		desired_pos = follow_target + get_offset_from_rotation()
		global_position = desired_pos
	else:
		global_position = desired_pos

	# Keep fixed isometric rotation
	rotation_degrees = Vector3(-35.264, 45.0 + orbit_rotation * 90.0, 0.0)

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
	global_position = target.global_position + get_offset_from_rotation()
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
