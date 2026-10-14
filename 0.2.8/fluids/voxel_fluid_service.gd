class_name VoxelFluidService
extends Node
## Runtime water: dirty-region flood from persistent RIVER/WATER/OCEAN sources.
## Overlay water_level stays 0–1; body surface_y is derived. Crystal is separate.

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

signal channel_fluid_changed(pos: Vector2i)

var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()

var _water_engine: _VoxelFluidEngine
var _terrain_query: _CrystalTerrainQuery
var _dirty_cells: Dictionary = {}
var _tick_accum: float = 0.0
var _sim_tick_id: int = 0
## Natural river/water tiles injected as sources this tick (not force-persisted as channels).
var _river_source_cells: Dictionary = {}
var _sleeping: bool = true
var _last_tick_us: int = 0
var _last_load_us: int = 0
var _last_subset_size: int = 0
var _last_changed_count: int = 0
var _last_gather_us: int = 0
var _last_copy_us: int = 0
var _last_sim_us: int = 0
var _last_persist_us: int = 0
var _last_visual_us: int = 0
var _last_process_us: int = 0
var _last_tile_samples: int = 0
var _last_registry_reads: int = 0
var _last_offscreen_in_subset: int = 0
var _last_signal_emits: int = 0
var _last_body_surface_y: float = 0.0
var _last_wet_count: int = 0
var _last_source_count: int = 0


func _ready() -> void:
	var _STP = load("res://systems/startup_total_profiler.gd")
	if _STP and _STP.is_enabled():
		_STP.begin("VoxelFluidService._ready", "synchronous_main")
	add_to_group("voxel_fluid_service")
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_FluidRegistry.ensure_builtins()
	_init_water_engine()
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.crystal_sim:
		apply_sim_config(cfg_svc.crystal_sim)
	if _STP and _STP.is_enabled():
		_STP.end("VoxelFluidService._ready")


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg == null:
		return
	sim_config = cfg
	_FluidRegistry.apply_crystal_config(cfg)
	if _water_engine:
		_water_engine.config = cfg
		_water_engine.fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)


func _init_water_engine() -> void:
	_terrain_query = _CrystalTerrainQuery.new()
	_terrain_query.world = world
	_terrain_query.chunk_manager = chunk_manager
	_water_engine = _VoxelFluidEngine.new(
		sim_config, _terrain_query, _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	)
	_water_engine.is_cell_active = Callable(self, "_is_cell_active")
	_water_engine.max_cells_per_tick = 96
	_water_engine.empty_cell_inflow_cap = 0.25


const _EMPTY_WALK_CAP := 96


func mark_region_dirty(wx: int, wz: int, radius: int = 1) -> void:
	# Only registered water expands to neighbors. Natural river tiles are visual
	# sources and must not pull a whole marsh into the gather.
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cell := Vector2i(wx + dx, wz + dz)
			_dirty_cells[cell] = true
			if _ChannelRegistry.has_fluid(cell.x, cell.y, _ChannelRegistry.FLUID_WATER):
				for dir in _CrystalTypes.NEIGHBOR_DIRS:
					_dirty_cells[cell + dir] = true


## Edit opened a column or turned it into water. Queue that cell and its
## orthogonal neighbours, then take one local step. Already-wet neighbours
## stay in the queue so the body keeps moving into connected empty cells
## instead of stopping on the first one. Open cells at the waterline or
## below also fill on later ticks without another neighbour break.
## Same-height solid ground is not wetted.
func requeue_neighbors_on_edit(wx: int, wz: int) -> void:
	var origin := Vector2i(wx, wz)
	_queue_cell_and_neighbors(origin)
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = origin + dir
		if _ChannelRegistry.has_fluid(n.x, n.y, _ChannelRegistry.FLUID_WATER) or _is_natural_water_cell(n):
			_queue_cell_and_neighbors(n)
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz if fluid_def else 10.0, 1.0)
	var prev_cap: int = 0
	if _water_engine:
		prev_cap = int(_water_engine.max_cells_per_tick)
		# One bounded step. The rest of a long trench continues on _process.
		_water_engine.max_cells_per_tick = mini(maxi(prev_cap, 1), 32)
	_interactive_local_center = origin
	_interactive_local_radius = 3
	_interactive_local_mode = true
	_tick_water(step_dt)
	_interactive_local_mode = false
	if _water_engine:
		_water_engine.max_cells_per_tick = prev_cap


func _queue_cell_and_neighbors(pos: Vector2i) -> void:
	_dirty_cells[pos] = true
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		_dirty_cells[pos + dir] = true


func recompute_region_now(wx: int, wz: int, radius: int = 1, steps: int = 6) -> void:
	mark_region_dirty(wx, wz, radius)
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz if fluid_def else 10.0, 1.0)
	# Cap work during interactive reflow so dig/channel do not freeze the main thread.
	var prev_cap: int = 0
	if _water_engine:
		prev_cap = int(_water_engine.max_cells_per_tick)
		_water_engine.max_cells_per_tick = mini(maxi(prev_cap, 1), 64)
	# Local-only subset: do not scan every fluid cell in the world on each dig.
	_interactive_local_center = Vector2i(wx, wz)
	_interactive_local_radius = maxi(radius + 3, 4)
	_interactive_local_mode = true
	for _i in steps:
		_tick_water(step_dt)
	_interactive_local_mode = false
	if _water_engine:
		_water_engine.max_cells_per_tick = prev_cap


var _interactive_local_mode: bool = false
var _interactive_local_center: Vector2i = Vector2i.ZERO
var _interactive_local_radius: int = 4


func _process(delta: float) -> void:
	var t_proc := Time.get_ticks_usec()
	if _water_engine == null:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("voxel_fluid")
	if GameplayInput.world_loading:
		_sleeping = true
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if _terrain_query:
		_terrain_query.world = world
		_terrain_query.chunk_manager = chunk_manager
	var fluid_def = _FluidRegistry.get_def(_ChannelRegistry.FLUID_WATER)
	if fluid_def == null:
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	if _dirty_cells.is_empty():
		_sleeping = true
		_tick_accum = 0.0
		_last_process_us = Time.get_ticks_usec() - t_proc
		if profiler and profiler.has_method("end"):
			profiler.end("voxel_fluid")
		return
	_tick_accum += delta
	var step_dt := 1.0 / maxf(fluid_def.update_rate_hz, 1.0)
	# One gravity step per frame. Extra catch-up was multiplying the gather.
	if _tick_accum >= step_dt:
		var t0 := Time.get_ticks_usec()
		_tick_water(step_dt)
		_last_tick_us = Time.get_ticks_usec() - t0
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("VoxelFluidService::_tick_water", _last_tick_us)
		_tick_accum = 0.0
	_last_process_us = Time.get_ticks_usec() - t_proc
	if profiler and profiler.has_method("end"):
		profiler.end("voxel_fluid")


func _tick_water(_delta: float) -> void:
	if _dirty_cells.is_empty() and not _interactive_local_mode:
		_sleeping = true
		_last_subset_size = 0
		_last_registry_reads = 0
		return
	_sleeping = false
	_sim_tick_id += 1
	if _terrain_query:
		_terrain_query.world = world
		_terrain_query.chunk_manager = chunk_manager
		_terrain_query.begin_sim_tick(_sim_tick_id)
	var t_load := Time.get_ticks_usec()
	var subset: Dictionary = _collect_active_region()
	_last_subset_size = subset.size()
	_last_registry_reads = subset.size()
	_last_gather_us = Time.get_ticks_usec() - t_load
	_last_load_us = _last_gather_us
	var t_copy := Time.get_ticks_usec()
	var sources: Dictionary = _sources_in_subset(subset)
	_last_source_count = sources.size()
	_last_tile_samples = sources.size()
	_last_copy_us = Time.get_ticks_usec() - t_copy
	var t_sim := Time.get_ticks_usec()
	var result: Dictionary = _flood_body(subset, sources)
	_last_sim_us = Time.get_ticks_usec() - t_sim
	var t_persist := Time.get_ticks_usec()
	var changed: Array = _persist_body(subset, sources, result)
	_last_changed_count = changed.size()
	_last_wet_count = int(result.get("wet_count", 0))
	_last_body_surface_y = float(result.get("surface_y", 0.0))
	_advance_dirty_from_changes(changed)
	_last_persist_us = Time.get_ticks_usec() - t_persist
	_sync_engine_debug(result)
	_river_source_cells.clear()


func _advance_dirty_from_changes(changed: Array) -> void:
	var next_dirty: Dictionary = {}
	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		next_dirty[pos] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			next_dirty[pos + dir] = true
	_dirty_cells = next_dirty


func _collect_active_region() -> Dictionary:
	var cells: Dictionary = {}
	if _interactive_local_mode:
		var r: int = _interactive_local_radius
		var c0: Vector2i = _interactive_local_center
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				cells[Vector2i(c0.x + dx, c0.y + dz)] = true
	for key_variant in _dirty_cells.keys():
		var key: Vector2i = key_variant
		cells[key] = true
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			cells[key + dir] = true
	# A far dig only dirties its own neighbourhood. Walk the open columns
	# (dug cells) from there to the water, one step onto the source, so the
	# basin and a side pocket fill without breaking another neighbour.
	_include_connected_empty(cells)
	return cells


func _is_empty_column(pos: Vector2i) -> bool:
	return _TerrainEdits.get_height_delta(pos.x, pos.y) < -0.001


## Open column at the same level as the waterline or lower. A solid top that
## only meets the line is ground, not an empty cell.
func _accepts_flow(pos: Vector2i, surface_y: float) -> bool:
	var top := _visual_top(pos)
	if top > surface_y + 0.001:
		return false
	if top >= surface_y - 0.001:
		return _is_empty_column(pos)
	return true


func _include_connected_empty(cells: Dictionary) -> void:
	var q: Array = []
	var seen: Dictionary = {}
	for key_variant in _dirty_cells.keys():
		var pos: Vector2i = key_variant
		if _is_empty_column(pos):
			q.append(pos)
	var walked := 0
	while not q.is_empty() and walked < _EMPTY_WALK_CAP:
		var cur: Vector2i = q.pop_back()
		if seen.has(cur):
			continue
		seen[cur] = true
		cells[cur] = true
		walked += 1
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = cur + dir
			if seen.has(n):
				continue
			if _is_natural_water_cell(n) or _ChannelRegistry.has_fluid(n.x, n.y, _ChannelRegistry.FLUID_WATER):
				cells[n] = true
				seen[n] = true
				continue
			if _is_empty_column(n):
				q.append(n)


func _layer() -> float:
	return _WorldSettings.get_active().layer_height()


func _visual_bed(pos: Vector2i) -> float:
	if _terrain_query:
		return _terrain_query.get_terrain_height(pos)
	return 0.0


func _visual_top(pos: Vector2i) -> float:
	return _visual_bed(pos) + _layer()


func _is_natural_water_cell(pos: Vector2i) -> bool:
	var tile: int = VoxelTypes.AIR
	if _terrain_query:
		tile = _terrain_query.get_tile(pos)
	elif world != null:
		tile = world.get_tile_type(float(pos.x), float(pos.y))
	return _CrystalTypes.is_water_tile(tile)


func _sources_in_subset(subset: Dictionary) -> Dictionary:
	var sources: Dictionary = {}
	_last_offscreen_in_subset = 0
	for key_variant in subset.keys():
		var key: Vector2i = key_variant
		if not _is_cell_active(key):
			_last_offscreen_in_subset += 1
			continue
		if _is_natural_water_cell(key):
			sources[key] = true
	return sources


func _flood_body(subset: Dictionary, sources: Dictionary) -> Dictionary:
	var empty := {"wet": {}, "surface_y": 0.0, "wet_count": 0}
	# Waterline is the source visual top (top of the river voxel), not an extra
	# layer above ground. Indentations are columns whose visual top is below that.
	# When the river has left the dirty set, overlay still in the subset carries
	# the same waterline forward. It is not a natural source and is not stripped.
	# A tick that still sees the river starts from the river only, so a puddle
	# that is no longer connected can dry.
	var surface_y := -1.0e9
	var origins: Dictionary = {}
	for key_variant in sources.keys():
		var s: Vector2i = key_variant
		origins[s] = true
		surface_y = maxf(surface_y, _visual_top(s))
	if origins.is_empty():
		for key_variant in subset.keys():
			var pos: Vector2i = key_variant
			if not _is_cell_active(pos):
				continue
			if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				continue
			var stored: float = _ChannelRegistry.get_runtime_surface_y(pos.x, pos.y)
			if stored <= 0.01 or _visual_top(pos) >= stored - 0.001:
				continue
			origins[pos] = true
			surface_y = maxf(surface_y, stored)
	if origins.is_empty() or surface_y < -1.0e8:
		return empty
	var cap: int = 64
	if _water_engine:
		cap = maxi(int(_water_engine.max_cells_per_tick), 16)
	var wet: Dictionary = {}
	var q: Array = []
	for key_variant in origins.keys():
		var s: Vector2i = key_variant
		wet[s] = true
		q.append(s)
	var qi := 0
	var new_cells := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = cur + dir
			if wet.has(n):
				continue
			if not subset.has(n):
				continue
			if not _is_cell_active(n):
				continue
			if not _accepts_flow(n, surface_y):
				continue
			# Already-full cells must not spend the new-cell budget, or the
			# wave stops on the first empty column past a pool.
			var already: bool = _ChannelRegistry.has_fluid(n.x, n.y, _ChannelRegistry.FLUID_WATER)
			wet[n] = true
			q.append(n)
			if sources.has(n) or already:
				continue
			new_cells += 1
			if new_cells >= cap:
				qi = q.size()
				break
	return {"wet": wet, "surface_y": surface_y, "wet_count": wet.size()}


func _persist_body(subset: Dictionary, sources: Dictionary, result: Dictionary) -> Array:
	var wet: Dictionary = result.get("wet", {})
	var surface_y: float = float(result.get("surface_y", 0.0))
	var layer: float = maxf(_layer(), 0.001)
	var changed: Array = []
	var emits := 0
	var vis_us := 0
	for key_variant in subset.keys():
		var pos: Vector2i = key_variant
		var is_source: bool = sources.has(pos)
		var is_wet: bool = wet.has(pos)
		if is_source:
			# Natural (or tile-stamped) river stays a source. Overlay occupancy
			# on a source would make a flooded cell look permanent — strip it.
			if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
				_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
				changed.append(pos)
				_emit_water_visual(pos)
				emits += 1
			continue
		if is_wet:
			var fill: float = clampf((surface_y - _visual_bed(pos)) / layer, 0.05, 1.0)
			var had: bool = _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			var old_sy: float = _ChannelRegistry.get_runtime_surface_y(pos.x, pos.y) if had else 0.0
			var old_lv: float = _ChannelRegistry.get_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER) if had else 0.0
			if not had:
				_ChannelRegistry.register_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, Vector2i.ZERO, fill)
			elif absf(old_lv - fill) > 0.02:
				_ChannelRegistry.set_fluid_level(pos.x, pos.y, _ChannelRegistry.FLUID_WATER, fill)
			if absf(old_sy - surface_y) > 0.02 or not had:
				_ChannelRegistry.set_runtime_surface_y(pos.x, pos.y, surface_y)
			if not had or absf(old_lv - fill) > 0.02 or absf(old_sy - surface_y) > 0.02:
				changed.append(pos)
				var tv := Time.get_ticks_usec()
				_emit_water_visual(pos)
				vis_us += Time.get_ticks_usec() - tv
				emits += 1
			continue
		if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			var stored_sy: float = _ChannelRegistry.get_runtime_surface_y(pos.x, pos.y)
			var filled_above: bool = stored_sy > 0.01 and _visual_top(pos) >= stored_sy - 0.001
			if sources.is_empty() and not filled_above:
				continue
			_ChannelRegistry.unregister_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER)
			changed.append(pos)
			var tv2 := Time.get_ticks_usec()
			_emit_water_visual(pos)
			vis_us += Time.get_ticks_usec() - tv2
			emits += 1
	_last_visual_us = vis_us
	_last_signal_emits = emits
	if emits > 0 and chunk_manager and chunk_manager.has_method("flush_rebuild_pending"):
		chunk_manager.flush_rebuild_pending()
	return changed


func _emit_water_visual(pos: Vector2i) -> void:
	channel_fluid_changed.emit(pos)
	if chunk_manager and chunk_manager.has_method("invalidate_columns_at_world"):
		chunk_manager.invalidate_columns_at_world(pos.x, pos.y)


func _sync_engine_debug(result: Dictionary) -> void:
	if _water_engine == null:
		return
	_water_engine.clear()
	var wet: Dictionary = result.get("wet", {})
	for key_variant in wet.keys():
		var key: Vector2i = key_variant
		_water_engine.depth[key] = 0.95
	_water_engine.set_subset_cells(wet.keys())


func is_persistent_source(wx: int, wz: int) -> bool:
	return _is_natural_water_cell(Vector2i(wx, wz))


func is_wet_column(wx: int, wz: int) -> bool:
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return true
	return _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER)


func get_body_surface_y(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		var sy: float = _ChannelRegistry.get_runtime_surface_y(wx, wz)
		if sy > 0.01:
			return sy
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return _visual_top(Vector2i(wx, wz))
	return 0.0


func _is_cell_active(pos: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_world_cell_loaded"):
		return chunk_manager.is_world_cell_loaded(pos.x, pos.y)
	return true


func get_water_engine() -> _VoxelFluidEngine:
	return _water_engine


func get_sim_diagnostics() -> Dictionary:
	var overlay_n := 0
	var ws = load("res://world/world_state.gd").get_active()
	if ws != null and "channels" in ws:
		overlay_n = int((ws.channels as Dictionary).size())
	var depth_n := 0
	if _water_engine:
		depth_n = _water_engine.cell_count()
	return {
		"channel_cells": overlay_n,
		"loaded_channel_cells": _last_subset_size,
		"offscreen_channel_cells": maxi(overlay_n - _last_subset_size, 0),
		"subset_cells": _last_subset_size,
		"engine_depth_cells": depth_n,
		"dirty_cells": _dirty_cells.size(),
		"max_cells_per_tick": int(_water_engine.max_cells_per_tick) if _water_engine else 0,
		"active_gate": "dirty_region",
		"loads_all_channels_each_tick": false,
		"sleeping": _sleeping,
		"last_tick_us": _last_tick_us,
		"last_load_us": _last_load_us,
		"last_changed_cells": _last_changed_count,
		"phase_us": {
			"process": _last_process_us,
			"gather": _last_gather_us,
			"copy": _last_copy_us,
			"sim": _last_sim_us,
			"persist": maxi(_last_persist_us - _last_visual_us, 0),
			"visual": _last_visual_us,
			"tick_total": _last_tick_us,
		},
		"tile_samples": _last_tile_samples,
		"registry_reads": _last_registry_reads,
		"offscreen_in_subset": _last_offscreen_in_subset,
		"signal_emits": _last_signal_emits,
		"signal_listeners": channel_fluid_changed.get_connections().size(),
		"body_surface_y": _last_body_surface_y,
		"wet_count": _last_wet_count,
		"source_count": _last_source_count,
	}


## Channel fill is the flood body's surface_y. The chunk mesher draws the lid.
## A second water mesh would draw the same cell twice.
func show_channel_level(pos: Vector2i, level: float, surface_y: float) -> void:
	if level < 0.05:
		if _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
			_ChannelRegistry.unregister_channel(pos.x, pos.y)
		_emit_water_visual(pos)
		return
	if not _ChannelRegistry.has_fluid(pos.x, pos.y, _ChannelRegistry.FLUID_WATER):
		_ChannelRegistry.register_channel(pos.x, pos.y, Vector2i.ZERO, level)
	else:
		_ChannelRegistry.set_water_level(pos.x, pos.y, level)
	var layer: float = _WorldSettings.get_active().layer_height()
	var waterline: float = surface_y + clampf(level, 0.0, 1.0) * layer
	_ChannelRegistry.set_runtime_surface_y(pos.x, pos.y, waterline)
	_emit_water_visual(pos)


func get_water_level_at(wx: int, wz: int) -> float:
	if _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
		return _ChannelRegistry.get_fluid_level(wx, wz, _ChannelRegistry.FLUID_WATER)
	if _is_natural_water_cell(Vector2i(wx, wz)):
		return 1.0
	return 0.0
