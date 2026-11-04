extends Control

const _HudLayout = preload("res://config/hud_layout.gd")
const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _TopographicalMapBuilder = preload("res://systems/topographical_map_builder.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _WorldState = preload("res://world/world_state.gd")
const _ThemeBuilder = preload("res://ui/theme/theme_builder.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
## Fullscreen map pan and bake extent: the playable half plus a 64-cell margin.
const FULL_MAP_MARGIN := 64
const FULL_HALF_EXTENT: int = _WorldBorder.PLAYABLE_HALF_X + FULL_MAP_MARGIN
const FULL_COARSE_SIZE := 72
const FULL_FINE_SIZE := 288
const SHARED_CACHE_LIMIT := 250000


class MapCanvas:
	extends Control

	signal cell_clicked(cell: Vector2i)
	signal marker_cleared

	var texture: Texture2D
	var tex_origin := Vector2.ZERO
	var tex_span := Vector2.ONE
	var half_extent: float = float(FULL_HALF_EXTENT)
	var view_center := Vector2.ZERO
	var zoom := 0.0
	var player_cell := Vector2.ZERO
	var has_marker := false
	var marker_cell := Vector2.ZERO
	var draw_count := 0
	var textured_draws := 0
	var _dragging := false
	var _drag_moved := 0.0

	func fit_zoom() -> float:
		var side := minf(size.x, size.y)
		if side < 8.0:
			side = 512.0
		return side / (half_extent * 2.0)

	func current_zoom() -> float:
		return zoom if zoom > 0.0 else fit_zoom()

	func world_to_screen(cell: Vector2) -> Vector2:
		return size * 0.5 + (cell - view_center) * current_zoom()

	func screen_to_world(p: Vector2) -> Vector2:
		return view_center + (p - size * 0.5) / current_zoom()

	func reset_view() -> void:
		zoom = 0.0
		view_center = Vector2.ZERO
		queue_redraw()

	func zoom_by(factor: float, at: Vector2) -> void:
		var before := screen_to_world(at)
		zoom = clampf(current_zoom() * factor, fit_zoom() * 0.5, fit_zoom() * 32.0)
		view_center += before - screen_to_world(at)
		_clamp_view()
		queue_redraw()

	func pan_pixels(delta: Vector2) -> void:
		view_center -= delta / current_zoom()
		_clamp_view()
		queue_redraw()

	func _clamp_view() -> void:
		view_center = view_center.clamp(Vector2(-half_extent, -half_extent), Vector2(half_extent, half_extent))

	func _draw() -> void:
		draw_count += 1
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.06, 1.0))
		var z := current_zoom()
		if texture != null:
			textured_draws += 1
			draw_texture_rect(texture, Rect2(world_to_screen(tex_origin), tex_span * z), false)
		var edge := Vector2(_WorldBorder.PLAYABLE_HALF_X, _WorldBorder.PLAYABLE_HALF_Z)
		var a := world_to_screen(-edge)
		draw_rect(Rect2(a, edge * 2.0 * z), Color(1.0, 1.0, 1.0, 0.35), false, 1.0)
		var pp := world_to_screen(player_cell)
		draw_circle(pp, 5.0, Color(0.05, 0.05, 0.08, 1.0))
		draw_circle(pp, 3.5, Color(0.95, 0.95, 1.0, 1.0))
		if has_marker:
			var mp := world_to_screen(marker_cell)
			draw_line(mp + Vector2(-6, -6), mp + Vector2(6, 6), Color(1.0, 0.3, 0.2), 2.0)
			draw_line(mp + Vector2(-6, 6), mp + Vector2(6, -6), Color(1.0, 0.3, 0.2), 2.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					if mb.pressed:
						_dragging = true
						_drag_moved = 0.0
					else:
						if _dragging and _drag_moved < 4.0:
							var c := screen_to_world(mb.position).floor()
							marker_cell = c
							has_marker = true
							cell_clicked.emit(Vector2i(int(c.x), int(c.y)))
							queue_redraw()
						_dragging = false
				MOUSE_BUTTON_RIGHT:
					if mb.pressed and has_marker:
						has_marker = false
						marker_cleared.emit()
						queue_redraw()
				MOUSE_BUTTON_WHEEL_UP:
					if mb.pressed:
						zoom_by(1.25, mb.position)
				MOUSE_BUTTON_WHEEL_DOWN:
					if mb.pressed:
						zoom_by(0.8, mb.position)
			accept_event()
		elif event is InputEventMouseMotion:
			if _dragging:
				var mm := event as InputEventMouseMotion
				_drag_moved += mm.relative.length()
				pan_pixels(mm.relative)
			accept_event()


@export var map_config: Resource

var _minimap_rect: TextureRect
var _player_dot: ColorRect
var _map_key_hint: Label
var _fullscreen_panel: PanelContainer
var _fullscreen_rect: MapCanvas
var _map_info: Label
var _shared_columns: Dictionary = {}
var _shared_rev: int = -1
var _full_rev: int = -1
var _full_fine_done: bool = false
var _open_usec: int = 0
var open_metrics: Dictionary = {}
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
var _full_preview_due_ms: int = 0
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
	title.text = "World Map  (M close, drag pan, wheel or +/- zoom, arrows pan, C center, click mark, right-click clear)"
	vbox.add_child(title)

	_fullscreen_rect = MapCanvas.new()
	_fullscreen_rect.half_extent = float(FULL_HALF_EXTENT)
	_fullscreen_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fullscreen_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fullscreen_rect.clip_contents = true
	_fullscreen_rect.focus_mode = Control.FOCUS_NONE
	_fullscreen_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fullscreen_rect.cell_clicked.connect(_on_map_cell_clicked)
	_fullscreen_rect.marker_cleared.connect(func(): _map_info.text = "Marker cleared")
	vbox.add_child(_fullscreen_rect)

	_map_info = Label.new()
	_map_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_info.text = "Click the map for coordinates and biome"
	vbox.add_child(_map_info)

	_fullscreen_player_dot = ColorRect.new()
	_fullscreen_player_dot.color = cfg.color_player
	_fullscreen_player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_player_dot.size = Vector2(8, 8)


func _place_minimap() -> void:
	if _minimap_rect == null:
		return
	var layout := _HudLayout.load_active()
	var rect := layout.region(_HudLayout.view_of(self), "minimap", _minimap_rect.size.x)
	_minimap_rect.position = rect.position


func _apply_minimap_widget_size(side: int) -> void:
	if _minimap_rect == null:
		return
	var sz := Vector2(maxi(side, 32), maxi(side, 32))
	_minimap_rect.custom_minimum_size = sz
	_minimap_rect.size = sz
	_place_minimap()
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_place_minimap):
		get_viewport().size_changed.connect(_place_minimap)
	if _player_dot:
		_player_dot.position = sz * 0.5 - _player_dot.size * 0.5
	if _map_key_hint:
		_map_key_hint.position = Vector2(4.0, sz.y - 18.0)


func _place_fullscreen_player_dot() -> void:
	if _fullscreen_rect == null:
		return
	var c := Vector2(_player_center_cell())
	if c != _fullscreen_rect.player_cell:
		_fullscreen_rect.player_cell = c
		_fullscreen_rect.queue_redraw()
	if int(open_metrics.get("first_draw_ms_x1000", -1)) < 0 and _fullscreen_rect.textured_draws > 0:
		open_metrics["first_draw_ms_x1000"] = Time.get_ticks_usec() - _open_usec


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

	_drop_stale_map_job()
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
		if _queue_map_rebuild(_fullscreen_open and not _full_map_current(), terrain_dirty):
			_rebuild_timer = cfg.rebuild_interval_sec
			_last_center = center
	if profiler and profiler.has_method("end"):
		profiler.end("topo_map")


func _drop_stale_map_job() -> void:
	if _active_map_job.is_empty() or bool(_active_map_job.get("fullscreen", false)):
		return
	var jc: Vector2i = _active_map_job.get("center", Vector2i.ZERO)
	var limit: float = float(_map_cfg().minimap_radius_cells) * 0.5
	if jc.distance_to(_player_center_cell()) <= limit:
		return
	_map_job_queue.clear()
	_active_map_job = {}
	_rebuild_timer = 0.0


func is_fullscreen_open() -> bool:
	return _fullscreen_open


func handle_toggle_action(just_pressed: bool) -> void:
	if _GameplayInput.blocks_menus():
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
	_open_usec = Time.get_ticks_usec()
	open_metrics = {"first_draw_ms_x1000": -1, "refined_ms_x1000": -1, "cached": false, "draws_at_open": 0}
	if _fullscreen_rect:
		_fullscreen_rect.reset_view()
		_fullscreen_rect.player_cell = Vector2(_player_center_cell())
		open_metrics["draws_at_open"] = _fullscreen_rect.draw_count
	if _full_tex != null and _full_fine_done and _full_rev == _WorldState.get_active().mesh_input_revision():
		open_metrics["cached"] = true
		open_metrics["refined_ms_x1000"] = 0
		_fullscreen_rect.texture = _full_tex
		_fullscreen_rect.queue_redraw()
		if _queue_map_rebuild(false, false):
			_rebuild_timer = _map_cfg().rebuild_interval_sec
			_last_center = _player_center_cell()
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
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var want_full := include_full and _fullscreen_map_enabled
	if _player == null and not want_full:
		return false
	var center := _player_center_cell()
	var cfg = _map_cfg()
	_sync_shared_columns()
	var minimap_current := _player == null or (not force_full and _minimap_enabled and _idle_map_current(center))
	if minimap_current and not want_full:
		return true

	_map_job_queue.clear()
	_crystal_overlay_job = {}

	if want_full:
		_full_fine_done = false
		_map_job_queue.append(_begin_full_job(cfg, FULL_COARSE_SIZE))
		_map_job_queue.append(_begin_full_job(cfg, FULL_FINE_SIZE))

	if _minimap_enabled and not minimap_current:
		var minimap_job: Dictionary = {}
		var can_scroll := not force_full and not _content_revision_changed()
		if can_scroll and not _idle_minimap_job.is_empty() \
				and _TopographicalMapBuilder.try_incremental_recenter(_idle_minimap_job, center):
			minimap_job = _idle_minimap_job
		else:
			minimap_job = _TopographicalMapBuilder.begin_job(
				_world, _crystal, center, cfg, false, _fast_map_sampling, _map_internal_divisor,
					false, 0, 0, _shared_columns
			)
		minimap_job["column_cache"] = _shared_columns
		_map_job_queue.append(minimap_job)

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
	var budget_scale: float = _GameFeelConfig.active().map_open_budget_scale if _fullscreen_open else 1.0
	var done: bool = _TopographicalMapBuilder.process_job(
		_active_map_job, int(_map_pixel_budget * budget_scale), int(_map_time_budget_us * budget_scale)
	)
	if profiler and profiler.has_method("end"):
		profiler.end("map_build")
	if not done:
		if _fullscreen_open and bool(_active_map_job.get("fullscreen", false)):
			_show_full_preview(_active_map_job)
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



func _show_full_preview(job: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now < _full_preview_due_ms or _fullscreen_rect == null:
		return
	var image: Image = job.get("image")
	if image == null:
		return
	_full_preview_due_ms = now + int(_GameFeelConfig.active().map_preview_sec * 1000.0)
	_set_canvas_texture(job, ImageTexture.create_from_image(image))


func _apply_finished_map_job(job: Dictionary) -> void:
	var tex: Texture2D = _TopographicalMapBuilder.finalize_job(job)
	if tex == null:
		return
	var cfg = _map_cfg()
	if _minimap_rect == null or _fullscreen_rect == null:
		return
	if bool(job.get("fullscreen", false)):
		_full_tex = tex
		_full_rev = int(job.get("content_revision", -1))
		_set_canvas_texture(job, _full_tex)
		var fine := int(job.get("size", 0)) >= FULL_FINE_SIZE
		if fine:
			_full_fine_done = true
			if _fullscreen_open and int(open_metrics.get("refined_ms_x1000", -1)) < 0:
				open_metrics["refined_ms_x1000"] = Time.get_ticks_usec() - _open_usec
		elif _map_job_queue.size() > 1 and bool(_map_job_queue[1].get("fullscreen", false)):
			var seed: Image = job.image.duplicate()
			var fsz := int(_map_job_queue[1].size)
			seed.resize(fsz, fsz, Image.INTERPOLATE_NEAREST)
			_map_job_queue[1].image = seed
		_place_fullscreen_player_dot()
	else:
		_minimap_tex = tex
		_minimap_rect.texture = _minimap_tex
		_apply_minimap_widget_size(cfg.minimap_size)
		_idle_minimap_job = _TopographicalMapBuilder.clone_job_state(job)

func _begin_full_job(cfg, internal: int) -> Dictionary:
	return _TopographicalMapBuilder.begin_job(
		_world, _crystal, Vector2i.ZERO, cfg, true, _fast_map_sampling, _map_internal_divisor,
		false, FULL_HALF_EXTENT, internal, _shared_columns
	)


func _sync_shared_columns() -> void:
	var rev: int = _WorldState.get_active().mesh_input_revision()
	if rev != _shared_rev or _shared_columns.size() > SHARED_CACHE_LIMIT:
		_shared_columns = {}
		_shared_rev = rev


func _full_map_current() -> bool:
	return _full_tex != null and _full_fine_done and _full_rev == _WorldState.get_active().mesh_input_revision()


func shared_column_count() -> int:
	return _shared_columns.size()


func get_open_metrics() -> Dictionary:
	return open_metrics.duplicate()


func _set_canvas_texture(job: Dictionary, tex: Texture2D) -> void:
	if _fullscreen_rect == null or tex == null:
		return
	var size := float(int(job.get("size", 1)))
	var stride := float(int(job.get("stride", 1)))
	var c: Vector2i = job.get("center", Vector2i.ZERO)
	_fullscreen_rect.texture = tex
	_fullscreen_rect.tex_origin = Vector2(c) - Vector2.ONE * float(int(size) / 2) * stride
	_fullscreen_rect.tex_span = Vector2.ONE * size * stride
	_fullscreen_rect.queue_redraw()


func _on_map_cell_clicked(cell: Vector2i) -> void:
	_map_info.text = describe_cell(cell)


func describe_cell(cell: Vector2i) -> String:
	var biome := "unknown"
	var height := "?"
	if _world != null and is_instance_valid(_world):
		var h: float = _world.get_surface_height(float(cell.x), float(cell.y))
		height = str(int(round(h)))
		biome = str(_world.get_biome(float(cell.x), h, float(cell.y)).get("name", "unknown"))
	var zone_text := str(_WorldBorder.zone_info(float(cell.x), float(cell.y)).get("zone", "?"))
	return "x %d, z %d  biome %s  height %s  zone %s  (marker set)" % [cell.x, cell.y, biome, height, zone_text]


func _unhandled_input(event: InputEvent) -> void:
	if not _fullscreen_open or _fullscreen_rect == null:
		return
	if event is InputEventKey and event.pressed:
		var k := (event as InputEventKey).physical_keycode
		var mid := _fullscreen_rect.size * 0.5
		var step := 64.0
		match k:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				_fullscreen_rect.zoom_by(1.25, mid)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_fullscreen_rect.zoom_by(0.8, mid)
			KEY_LEFT:
				_fullscreen_rect.pan_pixels(Vector2(step, 0))
			KEY_RIGHT:
				_fullscreen_rect.pan_pixels(Vector2(-step, 0))
			KEY_UP:
				_fullscreen_rect.pan_pixels(Vector2(0, step))
			KEY_DOWN:
				_fullscreen_rect.pan_pixels(Vector2(0, -step))
			KEY_HOME, KEY_C:
				_fullscreen_rect.view_center = _fullscreen_rect.player_cell
				_fullscreen_rect.queue_redraw()
			_:
				return
		get_viewport().set_input_as_handled()
