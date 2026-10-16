extends Node

signal sound_hook(cue_id: String)

const CONFIG_PATH := "res://config/default_game_feel.tres"
const _Config = preload("res://config/game_feel_config.gd")
const _Juice = preload("res://systems/juice.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

const FLASH_SEC := 0.12
const ZOOM_MIN := 8.0

var config

var _emphasis_token: int = 0
var _saved_scale: float = 1.0
var _emphasis_dip: float = 1.0
var _flash_rect: ColorRect
var _flash_left: float = 0.0
var _flash_amount: float = 0.0
var _zoom_token: int = 0
var _zoom_cam: Camera3D
var _zoom_from: float = 0.0
var _zoom_to: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	config = _load_config()


func _process(delta: float) -> void:
	if _flash_rect == null:
		set_process(false)
		return
	var step := delta
	if Engine.time_scale > 0.001:
		step = delta / Engine.time_scale
	_flash_left -= step
	if _flash_left <= 0.0:
		_flash_left = 0.0
		_flash_amount = 0.0
		_flash_rect.visible = false
		set_process(false)
		return
	var fade := clampf(_flash_left / FLASH_SEC, 0.0, 1.0)
	_flash_rect.color = Color(1.0, 1.0, 1.0, _flash_amount * 0.35 * fade)
	_flash_rect.visible = true


static func safe_slow_scale(scale: float) -> float:
	return clampf(scale, _Config.SLOW_MO_FLOOR, 1.0)


func banner_seconds(beat_id: String = "") -> float:
	if config == null:
		return 2.5
	if beat_id != "":
		var row: Dictionary = config.beat(beat_id)
		if not row.is_empty():
			return float(row["banner_sec"])
	return config.banner_sec


func enemy_telegraph(id: String) -> float:
	if config == null:
		return 0.0
	var row: Dictionary = config.enemy(id)
	if row.is_empty():
		return 0.0
	return float(row["telegraph_sec"])


func play_action(id: String, flash_target: Node = null) -> void:
	if config == null:
		return
	var row: Dictionary = config.action(id)
	if row.is_empty():
		return
	play_hit_stop(float(row["hit_stop_sec"]))
	play_shake(float(row["shake"]))
	if flash_target != null:
		_Juice.set_flash(flash_target, float(row["flash"]))
	play_screen_flash(float(row["flash"]))
	sound_hook.emit(id)


func play_beat(id: String) -> void:
	if config == null:
		return
	var row: Dictionary = config.beat(id)
	if row.is_empty():
		return
	sound_hook.emit(id)
	play_shake(float(row["camera_shake"]))
	play_screen_flash(float(row["flash"]))
	_apply_zoom(float(row["camera_zoom"]), float(row["slow_mo_sec"]))
	_begin_emphasis(safe_slow_scale(float(row["slow_mo_scale"])), float(row["slow_mo_sec"]))


func play_hit_stop(seconds: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var dur := clampf(seconds, _Config.HIT_STOP_MIN, _Config.HIT_STOP_MAX)
	_Juice.request_hit_stop(dur, tree)


func play_shake(amount: float) -> void:
	_Juice.request_shake(amount)


func play_screen_flash(amount: float) -> void:
	if amount <= 0.0:
		return
	if _PlayerSettings.reduce_motion or not _PlayerSettings.flash_effects_enabled:
		return
	if DisplayServer.get_name() == "headless":
		return
	_ensure_flash()
	_flash_amount = maxf(_flash_amount, clampf(amount, 0.0, 1.0))
	_flash_left = FLASH_SEC
	set_process(true)


func _load_config():
	if ResourceLoader.exists(CONFIG_PATH):
		var loaded = load(CONFIG_PATH)
		if loaded is _Config:
			return loaded
	return _Config.create_default()


func _begin_emphasis(scale: float, seconds: float) -> void:
	if seconds <= 0.0 or scale >= 0.999:
		return
	if DisplayServer.get_name() == "headless":
		return
	if _PlayerSettings.reduce_motion:
		return
	var tree := get_tree()
	if tree == null or tree.paused:
		return
	var holding := _emphasis_token > 0 and absf(Engine.time_scale - _emphasis_dip) <= 0.02
	if not holding and absf(Engine.time_scale - 1.0) > 0.02:
		return
	_emphasis_token += 1
	var token := _emphasis_token
	if not holding:
		_saved_scale = Engine.time_scale
	_emphasis_dip = scale
	Engine.time_scale = scale
	var timer := tree.create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		_end_emphasis(token)
	)


func _end_emphasis(token: int) -> void:
	if token != _emphasis_token:
		return
	if absf(Engine.time_scale - _emphasis_dip) <= 0.02:
		Engine.time_scale = _saved_scale


func _apply_zoom(amount: float, seconds: float) -> void:
	if amount <= 0.0 or seconds <= 0.0:
		return
	if DisplayServer.get_name() == "headless":
		return
	if _PlayerSettings.reduce_motion:
		return
	var tree := get_tree()
	if tree == null:
		return
	var cam := tree.get_first_node_in_group("camera") as Camera3D
	if cam == null:
		return
	_end_zoom(_zoom_token)
	_zoom_token += 1
	var token := _zoom_token
	_zoom_cam = cam
	_zoom_from = cam.size
	_zoom_to = maxf(cam.size - amount, ZOOM_MIN)
	cam.size = _zoom_to
	var timer := tree.create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void:
		_end_zoom(token)
	)


func _end_zoom(token: int) -> void:
	if token != _zoom_token:
		return
	if is_instance_valid(_zoom_cam) and absf(_zoom_cam.size - _zoom_to) <= 0.05:
		_zoom_cam.size = _zoom_from
	_zoom_cam = null
	_zoom_token += 1


func _ensure_flash() -> void:
	if _flash_rect != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 1.0, 1.0, 0.0)
	rect.visible = false
	layer.add_child(rect)
	_flash_rect = rect
