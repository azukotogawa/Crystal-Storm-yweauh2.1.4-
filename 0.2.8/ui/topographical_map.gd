extends Control

const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _TopographicalMapBuilder = preload("res://systems/topographical_map_builder.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _WorldState = preload("res://world/world_state.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")

@export var map_config: Resource

var _minimap_rect: TextureRect
var _player_dot: ColorRect
var _map_key_hint: Label
var _fullscreen_panel: PanelContainer
var _fullscreen_rect: TextureRect
var _fullscreen_player_dot: ColorRect

var _world: InfiniteNoiseWorld
var _crystal: CrystalManager
var _player: Node3D
var _fullscreen_open: bool = false
var _rebuild_timer: float = 0.0
var _crystal_overlay_timer: float = 0.0
var _last_center := Vector2i.ZERO
var _minimap_tex: ImageTexture
var _full_tex: ImageTexture
var _minimap_enabled: bool = true
var _fullscreen_map_enabled: bool = true
var _map_pixel_budget: int = 256
var _map_time_budget_us: int = 2500
var _map_internal_divisor: int = 2
var _fast_map_sampling: bool = true
var _crystal_overlay_interval_sec: float = 1.0
var _map_job_queue: Array = []
var _active_map_job: Dictionary = {}
var _idle_minimap_job: Dictionary = {}
var _crystal_overlay_job: Dictionary = {}


func _map_cfg():
	if map_config == null or not map_config is _TopographicalMapConfig:
		map_config = _TopographicalMapConfig.create_default()
	return map_config


func _enter_tree() -> void:
	add_to_group("topographical_map")


func _exit_tree() -> void:
	if _fullscreen_open:
		_GameplayInput.map_open = false
		_fullscreen_open = false


func get_minimap_screen_rect() -> Rect2:
	if _minimap_rect == null or not _minimap_rect.visible:
		return Rect2()
	if _minimap_rect.size.x < 1.0 or _minimap_rect.size.y < 1.0:
		_apply_minimap_widget_size(_map_cfg().minimap_size)
	return _minimap_rect.get_global_rect()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	set_process(true)
	call_deferred("_bind_scene")


## voxel_position X/Z are already column indexes. Do not pass them through world_to_column.
static func column_cell_from_voxel(voxel_position: Vector3) -> Vector2i:
	return Vector2i(floori(voxel_position.x), floori(voxel_position.z))


func _bind_scene() -> void:
	_world = get_tree().get_first_node_in_group("world")
	_crystal = get_tree().get_first_node_in_group("crystal_manager")
	_player = get_tree().get_first_node_in_group("player")


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	_minimap_enabled = bool(cfg.minimap_enabled)
	_fullscreen_map_enabled = bool(cfg.map_fullscreen_enabled)
	_map_pixel_budget = maxi(int(cfg.map_pixels_per_frame), 32)
	_map_time_budget_us = maxi(int(cfg.map_time_budget_us), 500)
	_map_internal_divisor = clampi(int(cfg.map_internal_divisor), 1, 4)
	if "fast_map_sampling" in cfg:
		_fast_map_sampling = bool(cfg.fast_map_sampling)
	if "map_crystal_overlay_interval_sec" in cfg:
		_crystal_overlay_interval_sec = maxf(float(cfg.map_crystal_overlay_interval_sec), 0.25)
	var mc = _map_cfg()
	mc.rebuild_interval_sec = float(cfg.map_rebuild_interval_sec)
	mc.minimap_size = int(cfg.minimap_pixel_size)
	mc.sample_stride = int(cfg.map_sample_stride)
	if _minimap_rect:
		_minimap_rect.visible = _minimap_enabled
		_apply_minimap_widget_size(mc.minimap_size)
	if _fullscreen_open and (not _minimap_enabled or not _fullscreen_map_enabled):
		_set_fullscreen_open(false)
	if not _minimap_enabled:
		_map_job_queue.clear()
		_active_map_job = {}
		_crystal_overlay_job = {}


func _build_ui() -> void:
	var cfg = _map_cfg()
	_minimap_rect = TextureRect.new()
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_rect.position = Vector2(12, 12)
	_apply_minimap_widget_size(cfg.minimap_size)
	add_child(_minimap_rect)

	_player_dot = ColorRect.new()
	_player_dot.color = cfg.color_player
	_player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_dot.size = Vector2(5, 5)
	_player_dot.position = Vector2(cfg.minimap_size * 0.5 - 2, cfg.minimap_size * 0.5 - 2)
	_minimap_rect.add_child(_player_dot)

	_map_key_hint = Label.new()
	_map_key_hint.text = "M"
	_map_key_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_rect.add_child(_map_key_hint)
	_apply_minimap_widget_size(cfg.minimap_size)

	_fullscreen_panel = PanelContainer.new()
	_fullscreen_panel.visible = false
	_fullscreen_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ThemeBuilder.apply(_fullscreen_panel)
	_fullscreen_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fullscreen_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_fullscreen_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vbox)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "Topographical Map (M to close)"
	vbox.add_child(title)

	_fullscreen_rect = TextureRect.new()
	_fullscreen_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fullscreen_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fullscreen_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fullscreen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_fullscreen_rect)

	_fullscreen_player_dot = ColorRect.new()
	_fullscreen_player_dot.color = cfg.color_player
	_fullscreen_player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_player_dot.size = Vector2(8, 8)
	_fullscreen_rect.add_child(_fullscreen_player_dot)


func _apply_minimap_widget_size(side: int) -> void:
	if _minimap_rect == null:
		return
	var sz := Vector2(maxi(side, 32), maxi(side, 32))
	_minimap_rect.custom_minimum_size = sz
	_minimap_rect.size = sz
	if _player_dot:
		_player_dot.position = sz * 0.5 - _player_dot.size * 0.5
	if _map_key_hint:
		_map_key_hint.position = Vector2(4.0, sz.y - 18.0)


func _place_fullscreen_player_dot() -> void:
	if _fullscreen_rect == null or _fullscreen_player_dot == null:
		return
	var sz := _fullscreen_rect.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	_fullscreen_player_dot.position = sz * 0.5 - _fullscreen_player_dot.size * 0.5


func _process(delta: float) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("topo_map")
	handle_toggle_action(Input.is_action_just_pressed("toggle_map"))

	if _world == null or not is_instance_valid(_world):
		_bind_scene()
		if _world == null:
			if profiler and profiler.has_method("end"):
				profiler.end("topo_map")
			return

	if not _active_map_job.is_empty():
		_step_map_job()
	elif not _crystal_overlay_job.is_empty():
		_step_crystal_overlay_job()

	if not _minimap_enabled and not _fullscreen_open:
		if profiler and profiler.has_method("end"):
			profiler.end("topo_map")
		return

	if _fullscreen_open:
		_place_fullscreen_player_dot()

	_crystal_overlay_timer -= delta
	if _crystal_overlay_timer <= 0.0 and _minimap_enabled and _active_map_job.is_empty() and _crystal_overlay_job.is_empty():
		_crystal_overlay_timer = _crystal_overlay_interval_sec
		_queue_crystal_overlay_refresh()

	_rebuild_timer -= delta
	var center := _player_center_cell()
	var cfg = _map_cfg()
	var moved := center.distance_to(_last_center) >= float(cfg.rebuild_move_threshold_cells)
	var due := _rebuild_timer <= 0.0
	var terrain_dirty := _content_revision_changed()
	if due or moved or terrain_dirty:
		# A job still in flight must not consume the movement. Retry next frame.
		if _queue_map_rebuild(_fullscreen_open, due or terrain_dirty):
			_rebuild_timer = cfg.rebuild_interval_sec
			_last_center = center
	if profiler and profiler.has_method("end"):
		profiler.end("topo_map")


func is_fullscreen_open() -> bool:
	return _fullscreen_open


func handle_toggle_action(just_pressed: bool) -> void:
	if _GameplayInput.dev_chat_open or _GameplayInput.world_loading or _GameplayInput.pause_open:
		if _fullscreen_open:
			_set_fullscreen_open(false)
		return
	if just_pressed:
		toggle_fullscreen_map()


func toggle_fullscreen_map() -> bool:
	if not _fullscreen_map_enabled:
		if _fullscreen_open:
			_set_fullscreen_open(false)
		return false
	_set_fullscreen_open(not _fullscreen_open)
	return _fullscreen_open


func _set_fullscreen_open(open: bool) -> void:
	_fullscreen_open = open
	_GameplayInput.map_open = open
	if _fullscreen_panel:
		_fullscreen_panel.visible = open
		_fullscreen_panel.mouse_filter = (
			Control.MOUSE_FILTER_STOP if open else Control.MOUSE_FILTER_IGNORE
		)
	z_index = 20 if open else 0
	if not open:
		return
	if _queue_map_rebuild(true, true):
		_rebuild_timer = _map_cfg().rebuild_interval_sec
		_last_center = _player_center_cell()
	else:
		_rebuild_timer = 0.0


func _player_center_cell() -> Vector2i:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if _player == null:
		return Vector2i.ZERO
	if _player.has_method("get_voxel_position"):
		return column_cell_from_voxel(_player.get_voxel_position())
	return _EntityNavigation.column_pos(_player.global_position)


func _content_revision_changed() -> bool:
	if _idle_minimap_job.is_empty():
		return false
	return int(_idle_minimap_job.get("content_revision", -1)) != _WorldState.get_active().mesh_input_revision()


func _idle_map_current(center: Vector2i) -> bool:
	if _idle_minimap_job.is_empty():
		return false
	if _idle_minimap_job.get("center", Vector2i(2147483647, 0)) != center:
		return false
	if _content_revision_changed():
		return false
	var image: Image = _idle_minimap_job.get("image")
	if image == null:
		return false
	var size: int = int(_idle_minimap_job.get("size", 0))
	return size > 0 and image.get_width() == size and image.get_height() == size


func _queue_map_rebuild(include_full: bool, force_full: bool) -> bool:
	if not _active_map_job.is_empty():
		return false
	if _world == null or not is_instance_valid(_world):
		return false
	var center := _player_center_cell()
	var cfg = _map_cfg()
	var minimap_current := not force_full and _minimap_enabled and _idle_map_current(center)
	var want_full := include_full and _fullscreen_map_enabled
	if minimap_current and not want_full:
		return true

	_map_job_queue.clear()
	_crystal_overlay_job = {}

	if _minimap_enabled and not minimap_current:
		var minimap_job: Dictionary = {}
		var can_scroll := not force_full and not _content_revision_changed()
		if can_scroll and not _idle_minimap_job.is_empty() \
				and _TopographicalMapBuilder.try_incremental_recenter(_idle_minimap_job, center):
			minimap_job = _idle_minimap_job
		else:
			minimap_job = _TopographicalMapBuilder.begin_job(
				_world, _crystal, center, cfg, false, _fast_map_sampling, _map_internal_divisor
			)
		_map_job_queue.append(minimap_job)

	if want_full:
		_map_job_queue.append(
			_TopographicalMapBuilder.begin_job(
				_world, _crystal, center, cfg, true, _fast_map_sampling, _map_internal_divisor
			)
		)
	if _map_job_queue.is_empty():
		return true
	_active_map_job = _map_job_queue[0]
	return true


func _queue_crystal_overlay_refresh() -> void:
	if not _minimap_enabled or _world == null or not is_instance_valid(_world):
		return
	if not _active_map_job.is_empty() or not _crystal_overlay_job.is_empty():
		return
	if _idle_minimap_job.is_empty():
		return
	_crystal_overlay_job = _TopographicalMapBuilder.clone_job_state(_idle_minimap_job)


func _step_map_job() -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("map_build")
	var done: bool = _TopographicalMapBuilder.process_job(
		_active_map_job, _map_pixel_budget, _map_time_budget_us
	)
	if profiler and profiler.has_method("end"):
		profiler.end("map_build")
	if not done:
		return
	_apply_finished_map_job(_active_map_job)
	_map_job_queue.pop_front()
	if _map_job_queue.is_empty():
		_active_map_job = {}
	else:
		_active_map_job = _map_job_queue[0]


func _step_crystal_overlay_job() -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("map_crystal")
	var done: bool = _TopographicalMapBuilder.repaint_crystal_overlay(
		_crystal_overlay_job, _map_pixel_budget, _map_time_budget_us
	)
	if profiler and profiler.has_method("end"):
		profiler.end("map_crystal")
	if not done:
		return
	var tex: Texture2D = _TopographicalMapBuilder.finalize_job(_crystal_overlay_job)
	if tex != null and _minimap_rect != null:
		_minimap_tex = tex
		_minimap_rect.texture = _minimap_tex
	_idle_minimap_job = _TopographicalMapBuilder.clone_job_state(_crystal_overlay_job)
	_crystal_overlay_job = {}


func _apply_finished_map_job(job: Dictionary) -> void:
	var tex: Texture2D = _TopographicalMapBuilder.finalize_job(job)
	if tex == null:
		return
	var cfg = _map_cfg()
	if _minimap_rect == null or _fullscreen_rect == null:
		return
	if bool(job.get("fullscreen", false)):
		_full_tex = tex
		_fullscreen_rect.texture = _full_tex
		_place_fullscreen_player_dot()
	else:
		_minimap_tex = tex
		_minimap_rect.texture = _minimap_tex
		_apply_minimap_widget_size(cfg.minimap_size)
		_idle_minimap_job = _TopographicalMapBuilder.clone_job_state(job)
