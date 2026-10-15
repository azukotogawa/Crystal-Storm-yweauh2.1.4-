extends Camera3D

@export var target: Node3D 
@export var use_smoothing := true
@export var smooth_speed: float = 6.0

@export var camera_offset := Vector3(0.0, 0.0, 28.28)


var zoom_level := 20.0 
const ZOOM_STEP := 2.0
const MIN_ZOOM := 4.0
const MAX_ZOOM := 100.0

var player: Player
var manager: ChunkManager
var subpixel_pos: Vector3

var bypass_smoothing := false 

func _ready():
	target = get_tree().get_first_node_in_group("player")
	player = target
	manager = get_tree().get_first_node_in_group("chunk_manager")

	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = zoom_level
	
	rotation_degrees = Vector3(0.0, 0.0, 0.0) 
	
	if target:
		subpixel_pos = target.global_position + camera_offset
		global_position = subpixel_pos

func _process(delta: float):
	if target:
		var target_3d = target.global_position + camera_offset
		
		if use_smoothing and not bypass_smoothing:
			var weight = 1.0 - exp(-smooth_speed * delta)
			subpixel_pos = subpixel_pos.lerp(target_3d, weight)
			global_position = subpixel_pos
		else:
			subpixel_pos = target_3d
			global_position = target_3d
			bypass_smoothing = false

func _input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = max(zoom_level - ZOOM_STEP, MIN_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = min(zoom_level + ZOOM_STEP, MAX_ZOOM)
		size = zoom_level

func _unhandled_input(event):
	if target == null:
		target = get_tree().get_first_node_in_group("player")
	if target == null or manager == null:
		return

	if event.is_action_pressed("rotate_left"):
		IsoMath.rotation = (IsoMath.rotation + 3) % 4
		_update_after_rotation()
	elif event.is_action_pressed("rotate_right"):
		IsoMath.rotation = (IsoMath.rotation + 1) % 4
		_update_after_rotation()

func _update_after_rotation():
	bypass_smoothing = true

	if player:
		player.update_visual_position()
		
	manager.rebuild_chunks()
	
	var direct_target = target.global_position + camera_offset
	subpixel_pos = direct_target
	global_position = direct_target
