extends Camera2D

@export var target: Node2D

var zoom_level := 1.0
const ZOOM_STEP := 0.1
const MIN_ZOOM := 0.25
const MAX_ZOOM := 256.0

func _ready():
	target = get_tree().get_first_node_in_group("player")
	enabled = true
	position_smoothing_enabled = true
	position_smoothing_speed = 10.0

func _process(_delta):
	if target:
		global_position = target.global_position

func _input(event):

	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = min(zoom_level + ZOOM_STEP, MAX_ZOOM)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = max(zoom_level - ZOOM_STEP, MIN_ZOOM)

		zoom = Vector2(zoom_level, zoom_level)
		
func _unhandled_input(event):
	
	var manager = get_tree().get_first_node_in_group("chunk_manager")

	if manager == null:
		return

	if event.is_action_pressed("rotate_left"):
		IsoMath.rotation = (IsoMath.rotation + 3) % 4
		manager.rebuild_chunks()

	if event.is_action_pressed("rotate_right"):
		IsoMath.rotation = (IsoMath.rotation + 1) % 4
		manager.rebuild_chunks()
