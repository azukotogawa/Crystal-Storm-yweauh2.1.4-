extends Camera3D

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _InputBindings = preload("res://systems/input_bindings.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _Juice = preload("res://systems/juice.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _Cutaway = preload("res://helpers/camera_cutaway.gd")

const ISO_PITCH_DEG := -35.264
const ISO_YAW0_DEG := 45.0
const PITCH_MIN_DEG := -78.0
const PITCH_MAX_DEG := -18.0

@export var target: Node3D
@export var use_smoothing := true
@export var smooth_speed: float = 3.0
var follow_target: Vector3

@export var distance := 100.0
@export var height_offset := 101.0

## Disabled: mouse at the screen edge must not pan or rotate the camera. Q/E yaw.
@export var edge_scroll_enabled: bool = false
@export var edge_scroll_margin_px: float = 28.0
@export var edge_scroll_speed: float = 42.0
@export var edge_scroll_max_lead: float = 48.0

@export var yaw_speed_deg: float = 90.0
@export var yaw_smooth: float = 12.0
var yaw_target_degrees: float = ISO_YAW0_DEG
var yaw_degrees: float = ISO_YAW0_DEG

@export var pitch_speed_deg: float = 70.0
@export var pitch_smooth: float = 12.0
@export var pitch_drag_deg: float = 0.18
var pitch_target_degrees: float = ISO_PITCH_DEG
var pitch_degrees: float = ISO_PITCH_DEG
var _pitch_dragging: bool = false
var _default_zoom: float = 16.0
var pitch_save_delay: float = 0.4
var _pitch_persist_wait: float = -1.0
var _cutaway_globals_ready: bool = false
var _cutaway_pushed: bool = false
var _cutaway_enabled: float = -1.0
var _cutaway_feet: Vector3 = Vector3(1.0e9, 1.0e9, 1.0e9)
var _cutaway_cam: Vector3 = Vector3(1.0e9, 1.0e9, 1.0e9)

var orbit_rotation: int:
	set(v):
		snap_yaw_degrees(ISO_YAW0_DEG + float(posmod(int(v), 4)) * 90.0)
	get:
		return posmod(int(round((yaw_degrees - ISO_YAW0_DEG) / 90.0)), 4)

var orbit_yaw_deg: float:
	set(v):
		snap_yaw_degrees(float(v))
	get:
		return yaw_degrees

var _orbit_target_deg: float:
	set(v):
		yaw_target_degrees = float(v)
	get:
		return yaw_target_degrees

## Ortho view height. 16 is about a third closer than the old 24 (30–40% band).
var zoom_level := 16.0
const ZOOM_STEP := 2.0
const PAN_ZOOM_STEP := 0.5
const MIN_ZOOM := 8.0
const MAX_ZOOM := 140.0

var player: Player
var _scroll_lead: Vector3 = Vector3.ZERO

func _ready():
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = zoom_level
	_default_zoom = zoom_level
	# Ortho directional shadows are sized from this far plane, not shadow_max_distance.
	far = 520.0
	
	target = get_tree().get_first_node_in_group("player")
	player = target as Player
	
	if not target:
		call_deferred("_find_target")
	add_to_group("camera")
	_restore_saved_pitch()
	

func _find_target():
	target = get_tree().get_first_node_in_group("player")
	player = target as Player
	if target == null:
		return
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

	if not _GameplayInput.blocks_world():
		_apply_hold_rotate(delta)
		_apply_pitch_keys(delta)
		_apply_edge_scroll(delta)
	_smooth_yaw(delta)
	_smooth_pitch(delta)

	var anchor: Vector3 = _frame_anchor()
	var desired_pos = anchor + get_offset_from_rotation()

	if use_smoothing:
		follow_target = follow_target.lerp(anchor, clampf(0.10 + delta * 2.0, 0.0, 0.35))
		desired_pos = follow_target + get_offset_from_rotation()
		global_position = desired_pos
	else:
		follow_target = anchor
		global_position = desired_pos

	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	global_position += _Juice.shake_offset(delta)
	update_cutaway_uniforms()
	_tick_pitch_save(delta)
	if profiler and profiler.has_method("end"):
		profiler.end("camera_update")


func _apply_pitch_keys(delta: float) -> void:
	var dir := 0.0
	if InputMap.has_action("camera_pitch_up") and Input.is_action_pressed("camera_pitch_up"):
		dir += 1.0
	if InputMap.has_action("camera_pitch_down") and Input.is_action_pressed("camera_pitch_down"):
		dir -= 1.0
	if is_zero_approx(dir):
		return
	apply_pitch_input(dir * pitch_speed_deg * delta)


func apply_pitch_input(delta_deg: float) -> void:
	var next := clampf(pitch_target_degrees + delta_deg, PITCH_MIN_DEG, PITCH_MAX_DEG)
	if is_equal_approx(next, pitch_target_degrees):
		return
	pitch_target_degrees = next
	_pitch_persist_wait = pitch_save_delay


func _tick_pitch_save(delta: float) -> void:
	if _pitch_persist_wait < 0.0:
		return
	_pitch_persist_wait -= delta
	if _pitch_persist_wait <= 0.0:
		_pitch_persist_wait = 0.0
		flush_pitch_save()


func pitch_save_pending() -> bool:
	return _pitch_persist_wait >= 0.0


func flush_pitch_save() -> void:
	if _pitch_persist_wait < 0.0:
		return
	_pitch_persist_wait = -1.0
	_PlayerSettings.set_camera_pitch(pitch_target_degrees)


func _restore_saved_pitch() -> void:
	var deg := float(_PlayerSettings.camera_pitch_degrees)
	pitch_target_degrees = clampf(deg, PITCH_MIN_DEG, PITCH_MAX_DEG)
	pitch_degrees = pitch_target_degrees


func _exit_tree() -> void:
	flush_pitch_save()


func _smooth_pitch(delta: float) -> void:
	pitch_target_degrees = clampf(pitch_target_degrees, PITCH_MIN_DEG, PITCH_MAX_DEG)
	if not use_smoothing:
		pitch_degrees = pitch_target_degrees
		return
	var k: float = 1.0 - exp(-pitch_smooth * delta)
	pitch_degrees = lerpf(pitch_degrees, pitch_target_degrees, k)


func snap_pitch_degrees(deg: float) -> void:
	pitch_target_degrees = clampf(float(deg), PITCH_MIN_DEG, PITCH_MAX_DEG)
	pitch_degrees = pitch_target_degrees
	_update_camera_transform()


func _apply_hold_rotate(delta: float) -> void:
	var dir := 0.0
	if Input.is_action_pressed("rotate_left"):
		dir -= 1.0
	if Input.is_action_pressed("rotate_right"):
		dir += 1.0
	if is_zero_approx(dir):
		return
	yaw_target_degrees = _wrap_deg(yaw_target_degrees + dir * yaw_speed_deg * delta)


func reset_view() -> void:
	snap_yaw_degrees(ISO_YAW0_DEG)
	snap_pitch_degrees(ISO_PITCH_DEG)
	zoom_level = _default_zoom
	size = zoom_level


func _frame_anchor() -> Vector3:
	var anchor: Vector3 = target.global_position + _scroll_lead
	anchor.y += WorldSettings.get_active().player_height() * 0.5
	return anchor


func _smooth_yaw(delta: float) -> void:
	if not use_smoothing:
		yaw_degrees = yaw_target_degrees
		return
	var k: float = 1.0 - exp(-yaw_smooth * delta)
	yaw_degrees = rad_to_deg(lerp_angle(deg_to_rad(yaw_degrees), deg_to_rad(yaw_target_degrees), k))


func snap_yaw_degrees(deg: float) -> void:
	yaw_target_degrees = float(deg)
	yaw_degrees = float(deg)
	_update_camera_transform()


func _wrap_deg(deg: float) -> float:
	var w: float = fposmod(deg, 360.0)
	return w


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
		sx = -1.0 + (mouse.x - rect.position.x) / m
		sx = clampf(sx, -1.0, 0.0)
	elif mouse.x >= rect.end.x - m:
		sx = (mouse.x - (rect.end.x - m)) / m
		sx = clampf(sx, 0.0, 1.0)
	if mouse.y <= rect.position.y + m:
		sy = -1.0 + (mouse.y - rect.position.y) / m
		sy = clampf(sy, -1.0, 0.0)
	elif mouse.y >= rect.end.y - m:
		sy = (mouse.y - (rect.end.y - m)) / m
		sy = clampf(sy, 0.0, 1.0)
	if is_zero_approx(sx) and is_zero_approx(sy):
		_scroll_lead = _scroll_lead.lerp(Vector3.ZERO, clampf(delta * 3.5, 0.0, 1.0))
		return
	var yaw: float = deg_to_rad(yaw_degrees)
	var right := Vector3(cos(yaw), 0.0, -sin(yaw)).normalized()
	var forward := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
	var move: Vector3 = right * sx + forward * (-sy)
	if move.length_squared() > 0.0001:
		move = move.normalized()
	_scroll_lead += move * edge_scroll_speed * delta
	if _scroll_lead.length() > edge_scroll_max_lead:
		_scroll_lead = _scroll_lead.normalized() * edge_scroll_max_lead


func get_offset_from_rotation() -> Vector3:
	var yaw_rad := deg_to_rad(yaw_degrees)
	if absf(pitch_degrees - ISO_PITCH_DEG) < 0.02:
		var hdist: float = distance * sqrt(2.0)
		return Vector3(sin(yaw_rad) * hdist, height_offset, cos(yaw_rad) * hdist)
	var legacy_h: float = distance * sqrt(2.0)
	var orbit: float = sqrt(height_offset * height_offset + legacy_h * legacy_h)
	var elev: float = deg_to_rad(-pitch_degrees)
	var hdist_p: float = orbit * cos(elev)
	var y: float = orbit * sin(elev)
	return Vector3(sin(yaw_rad) * hdist_p, y, cos(yaw_rad) * hdist_p)


func _apply_orbit_rotation() -> void:
	_update_camera_transform()


func _update_camera_transform():
	if not target:
		return
	global_position = target.global_position + _scroll_lead + get_offset_from_rotation()
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0.0)
	update_cutaway_uniforms()


func update_cutaway_uniforms() -> void:
	_ensure_cutaway_globals()
	var enabled := 1.0 if _PlayerSettings.camera_cutaway_enabled else 0.0
	var feet := global_position
	if target:
		feet = target.global_position
	var cam_pos := global_position
	if _cutaway_pushed and enabled == _cutaway_enabled \
			and feet.distance_squared_to(_cutaway_feet) < 0.0004 \
			and cam_pos.distance_squared_to(_cutaway_cam) < 0.0004:
		return
	_cutaway_pushed = true
	_cutaway_enabled = enabled
	_cutaway_feet = feet
	_cutaway_cam = cam_pos
	_Cutaway.submitted_enabled = enabled
	_Cutaway.submitted_player = feet
	_Cutaway.submitted_camera = global_position
	_Cutaway.submitted_radius = _Cutaway.RADIUS_AT_PLAYER
	_Cutaway.submitted_radius_near = _Cutaway.RADIUS_AT_CAMERA
	_Cutaway.submitted_feet_clear = _Cutaway.FEET_CLEAR
	_Cutaway.submitted_past = _Cutaway.PAST_DISTANCE
	_Cutaway.submit_count += 1
	RenderingServer.global_shader_parameter_set("cutaway_enabled", enabled)
	RenderingServer.global_shader_parameter_set("cutaway_player", feet)
	RenderingServer.global_shader_parameter_set("cutaway_camera", global_position)
	RenderingServer.global_shader_parameter_set("cutaway_radius", _Cutaway.RADIUS_AT_PLAYER)
	RenderingServer.global_shader_parameter_set("cutaway_radius_near", _Cutaway.RADIUS_AT_CAMERA)
	RenderingServer.global_shader_parameter_set("cutaway_feet_clear", _Cutaway.FEET_CLEAR)
	RenderingServer.global_shader_parameter_set("cutaway_past", _Cutaway.PAST_DISTANCE)


func _ensure_cutaway_globals() -> void:
	if _cutaway_globals_ready:
		return
	_cutaway_globals_ready = true
	var have: PackedStringArray = PackedStringArray()  # get_list is editor-only; see _add_cutaway_global(
	_add_cutaway_global(have, &"cutaway_enabled", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add_cutaway_global(have, &"cutaway_player", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_add_cutaway_global(have, &"cutaway_camera", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	_add_cutaway_global(have, &"cutaway_radius", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _Cutaway.RADIUS_AT_PLAYER)
	_add_cutaway_global(have, &"cutaway_radius_near", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _Cutaway.RADIUS_AT_CAMERA)
	_add_cutaway_global(have, &"cutaway_feet_clear", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _Cutaway.FEET_CLEAR)
	_add_cutaway_global(have, &"cutaway_past", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, _Cutaway.PAST_DISTANCE)
	# Register once. Do not overwrite AO strength; quality owns that value.
	_add_cutaway_global(have, &"terrain_ao_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add_cutaway_global(have, &"terrain_sun_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3(0.62, 0.57, 0.54))
	_add_cutaway_global(have, &"terrain_detail", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	_add_cutaway_global(have, &"terrain_cave_fog", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.55)
	_add_cutaway_global(have, &"terrain_corner_darken", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.42)
	_add_cutaway_global(have, &"terrain_shadow_darken", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.45)
	_add_cutaway_global(have, &"terrain_cell_size", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 2.0)


func _add_cutaway_global(have: PackedStringArray, param: StringName, type: int, default_value: Variant) -> void:
	if have.has(String(param)) or Engine.has_meta(&"sg_" + String(param)) \
			or ProjectSettings.has_setting("shader_globals/" + String(param)):
		return
	Engine.set_meta(&"sg_" + String(param), true)  # shared registry: camera + terrain_lighting both register terrain_*
	RenderingServer.global_shader_parameter_add(param, type, default_value)


func _input(event):
	if _GameplayInput.blocks_world():
		return
	if event.is_action("camera_free_look", true) and not event is InputEventMouseMotion:
		_pitch_dragging = event.is_pressed()
		_GameplayInput.free_look = _pitch_dragging
		if not _pitch_dragging:
			flush_pitch_save()
		else:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_GameplayInput.free_look = _pitch_dragging or event.alt_pressed
	if event is InputEventMouseMotion and (_pitch_dragging or event.alt_pressed):
		var look: float = _GameFeelConfig.active().camera_look_deg
		apply_pitch_input(-event.relative.y * look)
		yaw_target_degrees = _wrap_deg(yaw_target_degrees - event.relative.x * look)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		use_touchpad()
		zoom_by((event as InputEventPanGesture).delta.y * PAN_ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if _InputBindings.is_touchpad_wheel(event):
		use_touchpad()
	if event is InputEventMagnifyGesture:
		var pinched: float = clampf(zoom_level / maxf((event as InputEventMagnifyGesture).factor, 0.1), MIN_ZOOM, MAX_ZOOM)
		zoom_level = pinched
		size = zoom_level
		return
	if not event.is_pressed() or event is InputEventMouseMotion:
		return
	if _InputBindings.matches("camera_zoom_in", event):
		zoom_by(-ZOOM_STEP * _wheel_scale(event))
	elif _InputBindings.matches("camera_zoom_out", event):
		zoom_by(ZOOM_STEP * _wheel_scale(event))
	elif _InputBindings.matches("camera_reset", event):
		reset_view()


func zoom_by(amount: float) -> void:
	zoom_level = clampf(zoom_level + amount, MIN_ZOOM, MAX_ZOOM)
	size = zoom_level



static func use_touchpad() -> void:
	if _PlayerSettings.control_profile != "laptop":
		_PlayerSettings.set_control_profile("laptop")


func _wheel_scale(event: InputEvent) -> float:
	var mb := event as InputEventMouseButton
	if mb == null or mb.factor <= 0.0:
		return 1.0
	return clampf(mb.factor, 0.1, 4.0)