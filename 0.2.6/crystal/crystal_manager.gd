class_name CrystalManager
extends Node3D

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _SpawnPointRegistry = preload("res://config/spawn_point_registry.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _SpawnPointController = preload("res://crystal/spawn_point_controller.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


signal fluid_changed(world_pos: Vector2i)
signal power_changed(power: float, tier: int)
signal spawn_destroyed(spawn: CrystalSpawnPoint)
signal spawn_damaged(spawn: CrystalSpawnPoint, amount: float)
signal all_spawns_destroyed
signal crystal_touched_player
signal absorption_completed(source_id: StringName, world_pos: Vector2i)

@export var expansion_enabled: bool = true
@export var flow_substeps: int = 2
@export var ruin_spawn_count: int = 2
@export var ruin_min_distance: float = 72.0
@export var ruin_max_distance: float = 180.0
@export var player_contact_defeat_enabled: bool = false
@export var player_defeat_depth: float = 0.35
@export var player_defeat_min_tier: int = 2

var sim_config: _CrystalSimConfig = _CrystalSimConfig.create_default()
var world: InfiniteNoiseWorld
var chunk_manager: ChunkManager
var power: float = 0.0
var strength_tier: int = 0
var total_volume: float = 0.0
var covered_cells: int = 0

var _sim: _CrystalFluidSim
var _terrain_query: _CrystalTerrainQuery
var _absorption: Dictionary = {}
var _ruin_absorption: Dictionary = {}
var _absorbed_ruin_centers: Dictionary = {}
var evolution: _CrystalEvolution
var _spawn_points: Array[CrystalSpawnPoint] = []
var _chunk_layers: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _spawn_markers: Dictionary = {}
var _next_spawn_id: int = 0
var _rng: RandomNumberGenerator
var _crystal_material: StandardMaterial3D
var _marker_material: StandardMaterial3D
var _layer_root: Node3D
var _marker_root: Node3D
var _initialized: bool = false
var _spawn_ctrl: _SpawnPointController
var _perf_skip_counter: int = 0
var _perf_max_rebuilds_per_frame: int = 5
var _perf_crystal_skip_frames: int = 0
var _perf_sim_hz: float = 20.0
var _sim_accum: float = 0.0
var _stats_dirty: bool = true
var _cells_by_chunk: Dictionary = {}
var _sim_tick_id: int = 0
var _perf_mesh_budget_us: int = 2500
var _absorption_scan_offset: int = 0
var _absorption_cells_per_tick: int = 64
var _perf_spread_damping_start: int = 600
var _perf_spread_damping_full: int = 3000
var _perf_mesh_rebuilds_when_large: int = 1
var _perf_mesh_depth_epsilon: float = 0.20
var _last_crystal_new_cells: int = 0
var _patch_dirty_by_chunk: Dictionary = {}
var _chunk_needs_full_rebuild: Dictionary = {}
var _sim_loaded_chunks_only: bool = true


func _enter_tree() -> void:
	add_to_group("crystal_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_rng = RandomNumberGenerator.new()
	if world:
		_rng.seed = world.world_seed + 9001

	_layer_root = Node3D.new()
	_layer_root.name = "CrystalLayers"
	add_child(_layer_root)

	_bind_marker_root()

	_setup_materials()
	_spawn_ctrl = _SpawnPointController.new()
	_spawn_ctrl.spawn_destroyed.connect(_on_spawn_destroyed)
	_spawn_ctrl.spawn_damaged.connect(_on_spawn_damaged)
	_spawn_ctrl.all_spawns_destroyed.connect(_on_all_spawns_destroyed)
	call_deferred("_bootstrap_when_ready")


func ensure_ready() -> void:
	while not _initialized:
		await get_tree().process_frame


func _bootstrap_when_ready() -> void:
	while world == null:
		world = get_tree().get_first_node_in_group("world")
		await get_tree().process_frame
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame

	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()

	evolution = _CrystalEvolution.new()
	configure_evolution()
	_init_sim()
	_initialize_spawns()
	_rebuild_cell_index()
	_bind_chunk_stream()
	_initialized = true


func configure_evolution() -> void:
	if evolution == null:
		return
	var table: Array = []
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.game_config and cfg_svc.game_config.absorption_unlocks.size() > 0:
		table = cfg_svc.game_config.absorption_unlocks
	evolution.configure(table)


func apply_sim_config(cfg: _CrystalSimConfig) -> void:
	if cfg == null:
		return
	sim_config = cfg
	flow_substeps = cfg.flow_substeps
	ruin_spawn_count = cfg.ruin_spawn_count
	ruin_min_distance = cfg.ruin_min_distance
	ruin_max_distance = cfg.ruin_max_distance
	player_contact_defeat_enabled = cfg.player_contact_defeat_enabled
	player_defeat_depth = cfg.player_defeat_depth
	player_defeat_min_tier = cfg.player_defeat_min_tier
	if _sim:
		_sim.config = cfg
	if _terrain_query:
		_terrain_query.apply_sim_config(cfg)
	var terrain_editor = get_tree().get_first_node_in_group("terrain_editor")
	if terrain_editor and terrain_editor.has_method("apply_sim_config"):
		terrain_editor.apply_sim_config(cfg)
	var growth_mgr = get_tree().get_first_node_in_group("vegetation_growth_manager")
	if growth_mgr and growth_mgr.has_method("apply_sim_config"):
		growth_mgr.apply_sim_config(cfg)


func _init_sim() -> void:
	_terrain_query = _CrystalTerrainQuery.new()
	_terrain_query.world = world
	_terrain_query.chunk_manager = chunk_manager
	_sim = _CrystalFluidSim.new(sim_config, _terrain_query)
	_sim.is_cell_active = Callable(self, "_is_cell_sim_active")
	if not _sim.depth_changed.is_connected(_on_sim_depth_changed):
		_sim.depth_changed.connect(_on_sim_depth_changed)
	if not _sim.depth_cleared.is_connected(_on_sim_depth_cleared):
		_sim.depth_cleared.connect(_on_sim_depth_cleared)


func _on_sim_depth_changed(pos: Vector2i) -> void:
	_index_crystal_cell(pos)
	_mark_chunk_dirty(pos)
	_stats_dirty = true
	fluid_changed.emit(pos)


func _on_sim_depth_cleared(pos: Vector2i) -> void:
	_unindex_crystal_cell(pos)
	_mark_chunk_dirty(pos)
	_stats_dirty = true
	fluid_changed.emit(pos)


func _index_crystal_cell(pos: Vector2i) -> void:
	if _sim == null or not _sim.depth.has(pos):
		_unindex_crystal_cell(pos)
		return
	var coord := _chunk_coord_for(pos)
	if not _cells_by_chunk.has(coord):
		_cells_by_chunk[coord] = []
	var bucket: Array = _cells_by_chunk[coord]
	if pos not in bucket:
		bucket.append(pos)


func _unindex_crystal_cell(pos: Vector2i) -> void:
	var coord := _chunk_coord_for(pos)
	if not _cells_by_chunk.has(coord):
		return
	var bucket: Array = _cells_by_chunk[coord]
	bucket.erase(pos)
	if bucket.is_empty():
		_cells_by_chunk.erase(coord)


func _rebuild_cell_index() -> void:
	_cells_by_chunk.clear()
	if _sim == null:
		return
	for pos_variant in _sim.depth.keys():
		_index_crystal_cell(pos_variant)


func get_fluid_sim() -> _CrystalFluidSim:
	return _sim


func _setup_materials() -> void:
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_crystal_material.albedo_color = Color(0.62, 0.18, 0.98, 1.0)
	_crystal_material.emission_enabled = true
	_crystal_material.emission = Color(0.42, 0.08, 0.82)
	_crystal_material.emission_energy_multiplier = 2.2
	_crystal_material.roughness = 0.1
	_crystal_material.metallic = 0.4

	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.albedo_color = Color(1.0, 0.35, 0.9, 0.85)
	_marker_material.emission_enabled = true
	_marker_material.emission = Color(1.0, 0.2, 0.8)
	_marker_material.emission_energy_multiplier = 2.5
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _initialize_spawns() -> void:
	if _sim:
		_sim.clear()
	_spawn_points.clear()
	_next_spawn_id = 0
	_spawn_ctrl.emit_weaken_mult = 1.0
	_spawn_ctrl.last_destroyed_label = ""
	_SpawnPointRegistry.ensure_builtins()

	var origin_def := _spawn_def_for_kind(CrystalTypes.SpawnKind.ORIGIN)
	var origin := CrystalSpawnPoint.from_def(_alloc_spawn_id(), Vector2i.ZERO, origin_def)
	_spawn_points.append(origin)
	_seed_emitter(origin)

	_add_feature_ruin_spawns()
	var procedural := maxi(0, ruin_spawn_count - _count_ruin_spawns())
	for _i in procedural:
		var ruin_pos := _pick_ruin_spawn_position()
		_add_ruin_spawn_at(ruin_pos)

	_add_artifact_spawns()
	_sync_spawn_controller()
	_recalc_stats()
	call_deferred("refresh_spawn_marker_textures")
	_flush_dirty_chunks()
	_log_spawn_status("initialized")


func _alloc_spawn_id() -> int:
	var id := _next_spawn_id
	_next_spawn_id += 1
	return id


func _seed_emitter(spawn: CrystalSpawnPoint) -> void:
	_set_depth(spawn.world_pos, sim_config.initial_spawn_depth, spawn.id)


func get_evolution() -> _CrystalEvolution:
	return evolution


func _add_feature_ruin_spawns() -> void:
	for center in _FeatureRegistry.get_ruin_centers():
		_add_ruin_spawn_at(center)


func _count_ruin_spawns() -> int:
	var n := 0
	for spawn in _spawn_points:
		if spawn.kind == CrystalTypes.SpawnKind.RUIN:
			n += 1
	return n


func _add_ruin_spawn_at(ruin_pos: Vector2i) -> void:
	for existing in _spawn_points:
		if existing.world_pos == ruin_pos:
			return
	var ruin_def := _spawn_def_for_kind(CrystalTypes.SpawnKind.RUIN)
	var ruin := CrystalSpawnPoint.from_def(_alloc_spawn_id(), ruin_pos, ruin_def)
	_spawn_points.append(ruin)
	_seed_emitter(ruin)


func _spawn_def_for_kind(kind: int) -> _SpawnPointDef:
	var def := _SpawnPointRegistry.get_def_for_kind(kind)
	if def:
		return def
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and cfg_svc.game_config:
		for entry in cfg_svc.game_config.spawn_points:
			if entry is _SpawnPointDef and entry.spawn_kind == kind:
				return entry
	return _SpawnPointRegistry.get_def(&"ruin_miniboss")


func _sync_spawn_controller() -> void:
	_spawn_ctrl.set_spawns(_spawn_points)


func _add_artifact_spawns() -> void:
	var count: int = sim_config.artifact_spawn_count if "artifact_spawn_count" in sim_config else 1
	for _i in count:
		var pos := _pick_artifact_spawn_position()
		_add_artifact_spawn_at(pos)


func _add_artifact_spawn_at(pos: Vector2i) -> void:
	for existing in _spawn_points:
		if existing.world_pos == pos:
			return
	var art_def := _SpawnPointRegistry.get_def(&"artifact_node")
	if art_def == null:
		art_def = _spawn_def_for_kind(CrystalTypes.SpawnKind.ARTIFACT)
	var artifact := CrystalSpawnPoint.from_def(_alloc_spawn_id(), pos, art_def)
	_spawn_points.append(artifact)
	_seed_emitter(artifact)


func _pick_artifact_spawn_position() -> Vector2i:
	var best := Vector2i(48, -48)
	var best_score := -1.0
	for _attempt in 32:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(ruin_min_distance * 0.6, ruin_max_distance * 0.85)
		var wx := int(round(cos(angle) * dist))
		var wz := int(round(sin(angle) * dist))
		var pos := Vector2i(wx, wz)
		if absf(float(pos.x)) > float(_WorldBorder.PLAYABLE_HALF_X) \
				or absf(float(pos.y)) > float(_WorldBorder.PLAYABLE_HALF_Z):
			continue
		if CrystalTypes.is_water_tile(_tile_at(pos)):
			continue
		var occupied := false
		for existing in _spawn_points:
			if existing.world_pos == pos:
				occupied = true
				break
		if occupied:
			continue
		var score := Vector2(pos).length() + _rng.randf_range(0.0, 12.0)
		if score > best_score:
			best_score = score
			best = pos
	return best


func _pick_ruin_spawn_position() -> Vector2i:
	var best := Vector2i(64, 64)
	var best_score := -1.0
	for _attempt in 48:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(ruin_min_distance, ruin_max_distance)
		var wx := int(round(cos(angle) * dist))
		var wz := int(round(sin(angle) * dist))
		var pos := Vector2i(wx, wz)
		if absf(float(pos.x)) > float(_WorldBorder.PLAYABLE_HALF_X) \
				or absf(float(pos.y)) > float(_WorldBorder.PLAYABLE_HALF_Z):
			continue
		if CrystalTypes.is_water_tile(_tile_at(pos)):
			continue
		var surface := _terrain_at(pos)
		if surface < 34.0 or surface > 130.0:
			continue
		var separation_penalty := 0.0
		for existing in _spawn_points:
			separation_penalty += 48.0 / maxf(Vector2(pos).distance_to(Vector2(existing.world_pos)), 1.0)
		var score := Vector2(pos).length() * 0.35 + separation_penalty + _rng.randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best = pos
	return best


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	_perf_crystal_skip_frames = int(cfg.crystal_sim_skip_frames)
	_perf_max_rebuilds_per_frame = int(cfg.max_crystal_chunk_rebuilds_per_frame)
	_perf_sim_hz = maxf(float(cfg.crystal_sim_hz), 4.0)
	expansion_enabled = bool(cfg.crystal_sim_enabled)
	if cfg.flow_substeps > 0:
		flow_substeps = cfg.flow_substeps
		if sim_config:
			sim_config.flow_substeps = cfg.flow_substeps
	if _sim:
		_sim.max_cells_per_tick = int(cfg.max_crystal_flow_cells)
		if "max_crystal_new_cells_per_tick" in cfg:
			_sim.max_new_cells_per_tick = int(cfg.max_crystal_new_cells_per_tick)
		if "crystal_empty_cell_inflow_cap" in cfg:
			_sim.empty_cell_inflow_cap = float(cfg.crystal_empty_cell_inflow_cap)
		if "crystal_spread_damping_start" in cfg:
			_sim.spread_damping_start_cells = int(cfg.crystal_spread_damping_start)
			_perf_spread_damping_start = int(cfg.crystal_spread_damping_start)
		if "crystal_spread_damping_full" in cfg:
			_sim.spread_damping_full_cells = int(cfg.crystal_spread_damping_full)
			_perf_spread_damping_full = int(cfg.crystal_spread_damping_full)
		if "crystal_spread_damping_min" in cfg:
			_sim.spread_damping_min_mult = float(cfg.crystal_spread_damping_min)
		if "crystal_mesh_rebuilds_when_large" in cfg:
			_perf_mesh_rebuilds_when_large = maxi(int(cfg.crystal_mesh_rebuilds_when_large), 1)
		if "crystal_mesh_depth_epsilon" in cfg:
			_perf_mesh_depth_epsilon = maxf(float(cfg.crystal_mesh_depth_epsilon), 0.05)
			_sim.mesh_depth_epsilon = _perf_mesh_depth_epsilon
	if _terrain_query:
		_terrain_query.use_fast_terrain_height = bool(cfg.use_fast_terrain_for_crystal)
	if "main_thread_budget_us" in cfg:
		_perf_mesh_budget_us = maxi(int(cfg.main_thread_budget_us) / 3, 800)
	if "max_absorption_cells_per_tick" in cfg:
		_absorption_cells_per_tick = maxi(int(cfg.max_absorption_cells_per_tick), 8)
	if "crystal_sim_loaded_chunks_only" in cfg:
		_sim_loaded_chunks_only = bool(cfg.crystal_sim_loaded_chunks_only)


func _process(delta: float) -> void:
	if not _initialized:
		return

	if expansion_enabled:
		_sim_accum += delta
		var step_dt := 1.0 / _perf_sim_hz
		var sim_steps := 0
		while _sim_accum >= step_dt and sim_steps < 2:
			_tick_crystal_sim(step_dt)
			_sim_accum -= step_dt
			sim_steps += 1
		_tick_absorption(delta)
		_tick_animal_absorption(delta)
		_tick_ruin_absorption(delta)
		_tick_power(delta)
		_check_player_contact()

	_sync_spawn_marker_visibility()
	if expansion_enabled or not _dirty_chunks.is_empty():
		_flush_dirty_chunks()


func _tick_crystal_sim(delta: float) -> void:
	if _perf_crystal_skip_frames > 0:
		_perf_skip_counter = (_perf_skip_counter + 1) % (_perf_crystal_skip_frames + 1)
		if _perf_skip_counter != 0:
			return
		delta *= float(_perf_crystal_skip_frames + 1)

	_sim_tick_id += 1
	if _terrain_query:
		_terrain_query.begin_sim_tick(_sim_tick_id)

	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_sim")
	if _sim:
		_sim.global_flow_mult = _relic_flow_mult()
		_sim.tick_emitters(_spawn_points, delta, _spawn_ctrl.emit_weaken_mult)
		var sub_delta := delta / float(max(sim_config.flow_substeps, 1))
		for _i in sim_config.flow_substeps:
			var changed: Array = _sim.tick_flow(sub_delta)
			_apply_batched_flow_changes(changed)
		_last_crystal_new_cells = _sim.last_new_cells
		covered_cells = _sim.cell_count()
		if profiler and profiler.has_method("set_gauge"):
			profiler.set_gauge("crystal_cells", float(covered_cells))
			profiler.set_gauge("crystal_new_cells", float(_last_crystal_new_cells))
			profiler.set_gauge("crystal_changed_cells", float(_sim.last_mesh_dirty_cells))
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_sim")


func _set_depth(pos: Vector2i, depth: float, spawn_id: int = -1) -> void:
	if _sim:
		_sim.set_depth(pos, depth, spawn_id)


func _tick_power(delta: float) -> void:
	if _stats_dirty:
		_recalc_stats()
		_stats_dirty = false
	if total_volume <= 0.0:
		return
	_add_power(total_volume * sim_config.power_per_volume * delta)


func grant_feed_power(amount: float) -> void:
	_add_power(amount)


func _add_power(amount: float) -> void:
	if amount <= 0.0:
		return
	power += amount
	var new_tier: int = sim_config.tier_from_power(power)
	if new_tier != strength_tier:
		strength_tier = new_tier
	power_changed.emit(power, strength_tier)


func _recalc_stats() -> void:
	if _sim == null:
		return
	var stats: Dictionary = _sim.recalc_volume()
	total_volume = float(stats.get("volume", 0.0))
	covered_cells = int(stats.get("cells", 0))


func _terrain_at(pos: Vector2i) -> float:
	if world == null:
		return 0.0
	if world.has_method("get_surface_height_smooth"):
		return world.get_surface_height_smooth(float(pos.x), float(pos.y))
	return world.get_surface_height(float(pos.x), float(pos.y))


func _tile_at(pos: Vector2i) -> int:
	if world == null:
		return VoxelTypes.AIR
	return world.get_tile_type(float(pos.x), float(pos.y))


func _chunk_coord_for(pos: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(pos.x) / float(ChunkData.SIZE)),
		floori(float(pos.y) / float(ChunkData.SIZE))
	)


func _bind_chunk_stream() -> void:
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null:
		return
	if chunk_manager.has_signal("chunk_ready") and not chunk_manager.chunk_ready.is_connected(_on_chunk_loaded):
		chunk_manager.chunk_ready.connect(_on_chunk_loaded)
	if chunk_manager.has_signal("chunk_unloaded") and not chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
		chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)


func _is_cell_sim_active(pos: Vector2i) -> bool:
	if not _sim_loaded_chunks_only or chunk_manager == null:
		return true
	if chunk_manager.has_method("is_world_cell_loaded"):
		return chunk_manager.is_world_cell_loaded(pos.x, pos.y)
	return chunk_manager.chunks.has(_chunk_coord_for(pos))


func _is_chunk_render_active(coord: Vector2i) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_chunk_loaded"):
		return chunk_manager.is_chunk_loaded(coord)
	return chunk_manager.chunks.has(coord)


func _mark_chunk_dirty(pos: Vector2i) -> void:
	var coord := _chunk_coord_for(pos)
	if not _is_chunk_render_active(coord):
		return
	_dirty_chunks[coord] = true


func _on_chunk_loaded(coord: Vector2i, _data: ChunkData) -> void:
	if _cells_by_chunk.has(coord):
		_dirty_chunks[coord] = true
	_sync_spawn_marker_visibility()


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if _chunk_layers.has(coord):
		var layer = _chunk_layers[coord]
		if is_instance_valid(layer):
			layer.queue_free()
		_chunk_layers.erase(coord)
	_dirty_chunks.erase(coord)
	_patch_dirty_by_chunk.erase(coord)
	_chunk_needs_full_rebuild.erase(coord)
	_sync_spawn_marker_visibility()


func _sync_spawn_marker_visibility() -> void:
	for spawn in _spawn_points:
		var marker = _spawn_markers.get(spawn.id)
		if marker == null or not is_instance_valid(marker):
			continue
		marker.visible = spawn.active


func _apply_batched_flow_changes(changed: Array) -> void:
	if changed.is_empty():
		return
	_stats_dirty = true
	var mesh_dirty: Array = _sim.get_last_mesh_dirty() if _sim else []
	if mesh_dirty.is_empty():
		for pos_variant in changed:
			var pos: Vector2i = pos_variant
			if _sim and _sim.depth.has(pos):
				_index_crystal_cell(pos)
			else:
				_unindex_crystal_cell(pos)
		return

	for pos_variant in changed:
		var pos: Vector2i = pos_variant
		if _sim and _sim.depth.has(pos):
			_index_crystal_cell(pos)
		else:
			_unindex_crystal_cell(pos)

	for pos_variant in mesh_dirty:
		var pos: Vector2i = pos_variant
		var coord := _chunk_coord_for(pos)
		if not _is_chunk_render_active(coord):
			continue
		if not _sim or not _sim.depth.has(pos):
			_chunk_needs_full_rebuild[coord] = true
			_dirty_chunks[coord] = true
			continue
		var layer = _chunk_layers.get(coord)
		if layer == null or not layer.has_cell(pos):
			_chunk_needs_full_rebuild[coord] = true
			_dirty_chunks[coord] = true
			continue
		if _chunk_needs_full_rebuild.has(coord):
			_dirty_chunks[coord] = true
			continue
		if not _patch_dirty_by_chunk.has(coord):
			_patch_dirty_by_chunk[coord] = []
		var bucket: Array = _patch_dirty_by_chunk[coord]
		if pos not in bucket:
			bucket.append(pos)
		_dirty_chunks[coord] = true


func _player_chunk_coord() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return Vector2i.ZERO
	var col: Vector3 = (
		player.get_voxel_position() if player.has_method("get_voxel_position")
		else player.global_position
	)
	return Vector2i(
		floori(col.x / float(ChunkData.SIZE)),
		floori(col.y / float(ChunkData.SIZE))
	)


func _chunk_manhattan_dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _effective_mesh_rebuild_budget() -> int:
	var budget: int = _perf_max_rebuilds_per_frame
	var cells: int = _sim.cell_count() if _sim else covered_cells
	if cells >= _perf_spread_damping_full:
		return mini(budget, _perf_mesh_rebuilds_when_large)
	if cells >= maxi(_perf_spread_damping_start - 120, 200):
		return maxi(1, mini(budget, _perf_mesh_rebuilds_when_large))
	if cells >= _perf_spread_damping_start:
		return maxi(1, mini(budget, int(ceil(float(budget) * 0.5))))
	return budget


func _flush_dirty_chunks() -> void:
	if _dirty_chunks.is_empty():
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_mesh")
	var t0 := Time.get_ticks_usec()
	var rebuilt := 0
	var keys: Array = _dirty_chunks.keys()
	var player_chunk := _player_chunk_coord()
	if player_chunk != Vector2i.ZERO:
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _chunk_manhattan_dist(a, player_chunk) < _chunk_manhattan_dist(b, player_chunk)
		)
	var rebuild_budget: int = _effective_mesh_rebuild_budget()
	for coord_variant in keys:
		var coord: Vector2i = coord_variant
		if not _is_chunk_render_active(coord):
			_dirty_chunks.erase(coord)
			continue
		if _chunk_needs_full_rebuild.has(coord):
			_rebuild_chunk_layer(coord)
			_chunk_needs_full_rebuild.erase(coord)
			_patch_dirty_by_chunk.erase(coord)
		else:
			_patch_chunk_layer(coord)
			_patch_dirty_by_chunk.erase(coord)
		_dirty_chunks.erase(coord)
		rebuilt += 1
		if rebuilt >= rebuild_budget:
			break
		if Time.get_ticks_usec() - t0 >= _perf_mesh_budget_us:
			break
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_mesh")


func _rebuild_chunk_layer(coord: Vector2i) -> void:
	if not _is_chunk_render_active(coord):
		return
	var cells: Array = []
	var min_x := coord.x * ChunkData.SIZE
	var min_z := coord.y * ChunkData.SIZE
	var max_x := min_x + ChunkData.SIZE
	var max_z := min_z + ChunkData.SIZE

	var positions: Array = _cells_by_chunk.get(coord, [])
	for pos_variant in positions:
		var pos: Vector2i = pos_variant
		if not _sim.depth.has(pos):
			continue
		var depth: float = float(_sim.depth[pos])
		if depth < sim_config.min_depth:
			continue
		cells.append(CrystalCell.new(
			pos,
			_terrain_at(pos),
			depth,
			int(_sim.spawn_id_by_cell.get(pos, -1))
		))

	var layer: CrystalChunkLayer
	if _chunk_layers.has(coord):
		layer = _chunk_layers[coord]
	else:
		layer = CrystalChunkLayer.new()
		layer.name = "CrystalChunk_%d_%d" % [coord.x, coord.y]
		_layer_root.add_child(layer)
		layer.setup(coord, _crystal_material)
		_chunk_layers[coord] = layer

	layer.rebuild(cells)


func _patch_chunk_layer(coord: Vector2i) -> void:
	var positions: Array = _patch_dirty_by_chunk.get(coord, [])
	if positions.is_empty():
		_rebuild_chunk_layer(coord)
		return
	if not _chunk_layers.has(coord):
		_rebuild_chunk_layer(coord)
		return

	var cells: Array = []
	var needs_full := false
	for pos_variant in positions:
		var pos: Vector2i = pos_variant
		if not _sim.depth.has(pos):
			needs_full = true
			break
		cells.append(CrystalCell.new(
			pos,
			_terrain_at(pos),
			float(_sim.depth[pos]),
			int(_sim.spawn_id_by_cell.get(pos, -1))
		))

	var layer: CrystalChunkLayer = _chunk_layers[coord]
	if needs_full or not layer.patch_cells(cells):
		_rebuild_chunk_layer(coord)


func refresh_spawn_marker_textures() -> void:
	var vis = get_tree().get_first_node_in_group("game_visual_registry") if is_inside_tree() else null
	if vis and vis.has_method("preload_game_bundle"):
		vis.preload_game_bundle()
	_refresh_spawn_markers()


func _bind_marker_root() -> void:
	var visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if visuals and visuals.has_method("get_spawn_markers_root"):
		_marker_root = visuals.get_spawn_markers_root()
	if _marker_root == null:
		_marker_root = Node3D.new()
		_marker_root.name = "SpawnMarkers"
		if visuals:
			visuals.add_child(_marker_root)
		else:
			add_child(_marker_root)


func _refresh_spawn_markers() -> void:
	if _marker_root == null:
		_bind_marker_root()
	for child in _marker_root.get_children():
		child.queue_free()
	_spawn_markers.clear()

	for spawn in _spawn_points:
		if not spawn.active:
			continue
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.55 if spawn.is_boss else 0.35
		mesh.bottom_radius = 0.7 if spawn.is_boss else 0.45
		mesh.height = 3.5 if spawn.is_boss else 2.2

		var anchor := Node3D.new()
		anchor.name = "SpawnMarker_%d" % spawn.id

		var marker := MeshInstance3D.new()
		marker.name = "Mesh"
		marker.mesh = mesh
		var mat: StandardMaterial3D = _marker_material.duplicate()
		var vis = get_tree().get_first_node_in_group("game_visual_registry")
		if vis and vis.spawn_marker_textures_enabled:
			mat.albedo_texture = vis.get_spawn_texture(spawn.is_boss)
			mat.emission_enabled = true
			mat.emission = Color(0.85, 0.3, 0.95) if spawn.is_boss else Color(0.55, 0.25, 0.82)
			mat.emission_energy_multiplier = 1.4 if spawn.is_boss else 0.9
		marker.material_override = mat
		anchor.add_child(marker)

		var col_x := float(spawn.world_pos.x) + 0.5
		var col_z := float(spawn.world_pos.y) + 0.5
		var walkable := TerrainRamps.walkable_height(world, col_x, col_z) if world else _terrain_at(spawn.world_pos)
		anchor.position = _WorldVisualCoords.column_to_world_pos(
			col_x,
			walkable + mesh.height * 0.5 + 0.08,
			col_z
		)
		_marker_root.add_child(anchor)
		_spawn_markers[spawn.id] = anchor


func _check_player_contact() -> void:
	if not player_contact_defeat_enabled or strength_tier < player_defeat_min_tier:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
	var key := Vector2i(floori(col.x), floori(col.z))
	var depth: float = get_depth_at(key.x, key.y)
	if depth >= player_defeat_depth:
		crystal_touched_player.emit()


func get_depth_at(wx: int, wz: int) -> float:
	return _sim.get_depth_at(wx, wz) if _sim else 0.0


func get_depth_cells_in_rect(bounds: Rect2i) -> Dictionary:
	var overlay: Dictionary = {}
	if _sim == null:
		return overlay
	var min_depth: float = sim_config.min_depth if sim_config else 0.04
	var x0: int = bounds.position.x
	var y0: int = bounds.position.y
	var x1: int = bounds.position.x + bounds.size.x
	var y1: int = bounds.position.y + bounds.size.y
	for pos_variant in _sim.depth.keys():
		var pos: Vector2i = pos_variant
		if pos.x < x0 or pos.y < y0 or pos.x >= x1 or pos.y >= y1:
			continue
		var depth: float = float(_sim.depth[pos])
		if depth >= min_depth:
			overlay[pos] = depth
	return overlay


func has_crystal_at(wx: int, wz: int) -> bool:
	return _sim.has_crystal_at(wx, wz) if _sim else false


func get_crystal_top(wx: float, wz: float) -> float:
	var key := Vector2i(floori(wx), floori(wz))
	var depth: float = get_depth_at(key.x, key.y)
	if depth < sim_config.min_depth:
		return -INF
	return _terrain_at(key) + depth


func get_walkable_height(wx: float, wz: float) -> float:
	var ramp_entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		ramp_entry = chunk_manager.get_ramp_entry_at_world(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, ramp_entry) if world else 1.0
	var depth := get_depth_at(floori(wx), floori(wz))
	if depth >= sim_config.min_depth:
		return maxf(base, _terrain_at(Vector2i(floori(wx), floori(wz))) + depth + 0.05)
	return base


func get_active_spawns() -> Array[CrystalSpawnPoint]:
	var active: Array[CrystalSpawnPoint] = []
	for spawn in _spawn_points:
		if spawn.active:
			active.append(spawn)
	return active


func get_spawn_at_cell(wx: int, wz: int) -> CrystalSpawnPoint:
	return _spawn_ctrl.get_spawn_at_cell(wx, wz)


func get_spawn_progress() -> Dictionary:
	return _spawn_ctrl.get_progress()


## Headless test entry — wires spawns through the same controller path as runtime.
func harness_setup_spawns(spawns: Array) -> void:
	_spawn_points.clear()
	for s in spawns:
		if s is CrystalSpawnPoint:
			_spawn_points.append(s)
	if _spawn_ctrl == null:
		_spawn_ctrl = _SpawnPointController.new()
		_spawn_ctrl.spawn_destroyed.connect(_on_spawn_destroyed)
		_spawn_ctrl.all_spawns_destroyed.connect(_on_all_spawns_destroyed)
	_sync_spawn_controller()


func _log_spawn_status(reason: String) -> void:
	var prog := get_spawn_progress()
	print("[Crystal] Spawns %s: %d/%d active (emit x%.2f)" % [
		reason,
		prog.active,
		prog.total,
		_spawn_ctrl.emit_weaken_mult,
	])


func damage_spawn(spawn_id: int, amount: float) -> bool:
	return _spawn_ctrl.damage_spawn(spawn_id, amount)


func damage_spawn_at_world(pos: Vector2i, amount: float, radius: float = 2.5) -> bool:
	return _spawn_ctrl.damage_spawn_at_world(pos, amount, radius)


func _on_spawn_damaged(spawn: CrystalSpawnPoint, amount: float) -> void:
	spawn_damaged.emit(spawn, amount)


func _on_spawn_destroyed(spawn: CrystalSpawnPoint) -> void:
	spawn_destroyed.emit(spawn)
	var marker = _spawn_markers.get(spawn.id)
	if marker:
		marker.queue_free()
		_spawn_markers.erase(spawn.id)
	if spawn.power_drain > 0.0:
		power = maxf(power - spawn.power_drain, 0.0)
		strength_tier = sim_config.tier_from_power(power)
		power_changed.emit(power, strength_tier)


func _on_all_spawns_destroyed() -> void:
	all_spawns_destroyed.emit()


func get_nearest_crystal_distance(from_pos: Vector3) -> float:
	if _sim == null or _sim.depth.is_empty():
		return INF
	var best := INF
	var px := int(floor(from_pos.x))
	var pz := int(floor(from_pos.z))
	for dx in range(-32, 33):
		for dz in range(-32, 33):
			var key := Vector2i(px + dx, pz + dz)
			if get_depth_at(key.x, key.y) < sim_config.min_depth:
				continue
			var dist := Vector2(from_pos.x, from_pos.z).distance_to(
				Vector2(float(key.x) + 0.5, float(key.y) + 0.5)
			)
			best = minf(best, dist)
	if best == INF:
		for spawn in _spawn_points:
			if spawn.active:
				best = minf(best, Vector2(from_pos.x, from_pos.z).distance_to(Vector2(spawn.world_pos)))
	return best


func _tick_absorption(delta: float) -> void:
	if _sim == null or _sim.depth.is_empty():
		return
	var cells: Array = _sim.depth.keys()
	if cells.is_empty():
		return
	var completed: Array[Vector2i] = []
	var scanned := 0
	var start := _absorption_scan_offset % cells.size()
	while scanned < _absorption_cells_per_tick and scanned < cells.size():
		var pos: Vector2i = cells[(start + scanned) % cells.size()]
		scanned += 1
		if not _is_cell_sim_active(pos):
			continue
		var depth: float = float(_sim.depth.get(pos, 0.0))
		if depth < sim_config.min_depth:
			continue
		var tile_id := _tile_at(pos)
		if not _is_absorbable_tile(tile_id):
			continue
		var rate: float = _absorption_rate_for(pos, tile_id)
		var progress: float = float(_absorption.get(pos, 0.0)) + delta * rate * depth
		if progress >= 1.0:
			completed.append(pos)
		else:
			_absorption[pos] = progress
	_absorption_scan_offset += scanned
	for pos in completed:
		_complete_absorption(pos)


func _is_absorbable_tile(tile_id: int) -> bool:
	return tile_id in [
		VoxelTypes.GRASS_TUFT,
		VoxelTypes.BUSH,
		VoxelTypes.TREE_TRUNK,
		VoxelTypes.FARMLAND,
	]


func _absorption_rate_for(pos: Vector2i, tile_id: int) -> float:
	var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
	if feat.has("plant_id"):
		var def = _PlantableRegistry.get_def(StringName(str(feat.plant_id))) as _PlantableDef
		if def:
			var stage: int = int(feat.get("growth_stage", def.mature_stage()))
			return def.absorb_rate_for_stage(stage)
	return _absorption_rate(tile_id)


func _absorption_rate(tile_id: int) -> float:
	match tile_id:
		VoxelTypes.GRASS_TUFT:
			return sim_config.grass_absorb_rate
		VoxelTypes.BUSH:
			return sim_config.bush_absorb_rate
		VoxelTypes.TREE_TRUNK:
			return sim_config.tree_absorb_rate
		VoxelTypes.FARMLAND:
			return sim_config.farmland_absorb_rate
		_:
			return 0.08


func _relic_flow_mult() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return 1.0
	var relic_mgr = player.get_node_or_null("RelicManager")
	if relic_mgr == null:
		relic_mgr = get_tree().get_first_node_in_group("relic_manager")
	if relic_mgr and relic_mgr.has_method("get_crystal_flow_mult"):
		return maxf(relic_mgr.get_crystal_flow_mult(), 0.05)
	return 1.0


func _absorption_power_boost(tile_id: int) -> float:
	match tile_id:
		VoxelTypes.TREE_TRUNK:
			return sim_config.tree_absorb_power
		VoxelTypes.FARMLAND:
			return sim_config.farmland_absorb_power
		VoxelTypes.BUSH:
			return sim_config.bush_absorb_power
		_:
			return sim_config.grass_absorb_power


func _complete_absorption(pos: Vector2i) -> void:
	var tile_id := _tile_at(pos)
	var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
	_absorption.erase(pos)
	_FeatureRegistry.clear_tile_override(pos.x, pos.y)
	_FeatureRegistry.clear_feature(pos.x, pos.y)
	_add_power(_absorption_power_boost(tile_id))
	var source_id := _absorption_source_for(tile_id, feat)
	if evolution:
		var unlock: Dictionary = evolution.record_absorption(source_id)
		if unlock.has("bonus_power"):
			_add_power(float(unlock.bonus_power))
	absorption_completed.emit(source_id, pos)
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(pos.x, pos.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(pos.x), float(pos.y))


func _absorption_source_for(tile_id: int, feat: Dictionary) -> StringName:
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.RUIN:
		return &"ruin"
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
		return &"animal"
	match tile_id:
		VoxelTypes.FARMLAND:
			return &"farmland"
		VoxelTypes.TREE_TRUNK:
			return &"tree"
		VoxelTypes.BUSH:
			return &"bush"
		_:
			return &"grass"


func _tick_animal_absorption(delta: float) -> void:
	if _sim == null or _sim.depth.is_empty():
		return
	var cells: Array = _sim.depth.keys()
	var scanned := 0
	var start := _absorption_scan_offset % maxi(cells.size(), 1)
	while scanned < _absorption_cells_per_tick and scanned < cells.size():
		var pos: Vector2i = cells[(start + scanned) % cells.size()]
		scanned += 1
		if not _is_cell_sim_active(pos):
			continue
		if float(_sim.depth.get(pos, 0.0)) < sim_config.min_depth:
			continue
		var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
		if not feat.has("kind") or int(feat.kind) != _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
			continue
		var progress: float = float(_absorption.get(pos, 0.0)) + delta * 0.25
		if progress >= 1.0:
			_complete_absorption(pos)
		else:
			_absorption[pos] = progress


func _tick_ruin_absorption(delta: float) -> void:
	if _sim == null:
		return
	for center in _FeatureRegistry.get_ruin_centers():
		if _absorbed_ruin_centers.has(center):
			continue
		if not _is_cell_sim_active(center):
			continue
		if float(_sim.depth.get(center, 0.0)) < sim_config.min_depth:
			continue
		var progress: float = float(_ruin_absorption.get(center, 0.0)) + delta * 0.12
		if progress >= 1.0:
			_absorbed_ruin_centers[center] = true
			_ruin_absorption.erase(center)
			_add_power(18.0)
			if evolution:
				var unlock: Dictionary = evolution.record_absorption(&"ruin")
				if unlock.has("bonus_power"):
					_add_power(float(unlock.bonus_power))
			absorption_completed.emit(&"ruin", center)
			_clear_ruin_at(center)
		else:
			_ruin_absorption[center] = progress


func _clear_ruin_at(center: Vector2i) -> void:
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			if Vector2(dx, dz).length() > 5.0:
				continue
			var wx := center.x + dx
			var wz := center.y + dz
			_FeatureRegistry.clear_tile_override(wx, wz)
			_FeatureRegistry.clear_feature(wx, wz)
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(center.x, center.y)
	if chunk_manager and chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(center.x), float(center.y))


func get_coverage_ratio() -> float:
	var playable_cells: float = float(_WorldBorder.PLAYABLE_HALF_X * 2 * _WorldBorder.PLAYABLE_HALF_Z * 2)
	if playable_cells <= 1.0:
		return 0.0
	return float(covered_cells) / playable_cells


func export_state() -> Dictionary:
	var depth_rows: Array = []
	if _sim:
		for pos_variant in _sim.depth.keys():
			var pos: Vector2i = pos_variant
			depth_rows.append([
				pos.x, pos.y,
				float(_sim.depth[pos]),
				int(_sim.spawn_id_by_cell.get(pos, -1)),
			])
	var spawn_rows: Array = _spawn_ctrl.export_spawn_rows()
	var absorption_rows: Array = []
	for pos_variant in _absorption.keys():
		var pos: Vector2i = pos_variant
		absorption_rows.append([pos.x, pos.y, float(_absorption[pos])])
	var evo_data := evolution.get_summary() if evolution else {}
	return {
		"power": power,
		"strength_tier": strength_tier,
		"expansion_enabled": expansion_enabled,
		"emit_weaken_mult": _spawn_ctrl.emit_weaken_mult,
		"last_destroyed_label": _spawn_ctrl.last_destroyed_label,
		"depth": depth_rows,
		"spawns": spawn_rows,
		"evolution": evo_data,
		"absorption_progress": absorption_rows,
	}


func import_state(data: Dictionary) -> void:
	if not _initialized or _sim == null:
		return
	power = float(data.get("power", power))
	strength_tier = int(data.get("strength_tier", strength_tier))
	expansion_enabled = bool(data.get("expansion_enabled", expansion_enabled))
	_spawn_ctrl.import_meta({
		"emit_weaken_mult": data.get("emit_weaken_mult", _spawn_ctrl.emit_weaken_mult),
		"last_destroyed_label": data.get("last_destroyed_label", _spawn_ctrl.last_destroyed_label),
	})

	_sim.clear()
	_absorption.clear()
	for row in data.get("depth", []):
		if row is Array and row.size() >= 3:
			var pos := Vector2i(int(row[0]), int(row[1]))
			var spawn_id: int = int(row[3]) if row.size() >= 4 else -1
			_sim.set_depth(pos, float(row[2]), spawn_id)

	for row in data.get("absorption_progress", []):
		if row is Array and row.size() >= 3:
			_absorption[Vector2i(int(row[0]), int(row[1]))] = float(row[2])

	if evolution:
		var evo: Dictionary = data.get("evolution", {})
		evolution.absorbed_counts.clear()
		for key in evo.get("absorbed", {}).keys():
			evolution.absorbed_counts[StringName(str(key))] = int(evo.absorbed[key])
		evolution.unlocked_enemies.clear()
		for entry in evo.get("unlocked_enemies", []):
			evolution.unlocked_enemies.append(StringName(str(entry)))

	_spawn_points.clear()
	_SpawnPointRegistry.ensure_builtins()
	for row in data.get("spawns", []):
		if not row is Dictionary:
			continue
		var def_id: StringName = StringName(str(row.get("def_id", "")))
		var def: _SpawnPointDef = _SpawnPointRegistry.get_def(def_id) if def_id != &"" else null
		var spawn: CrystalSpawnPoint
		if def:
			spawn = CrystalSpawnPoint.from_def(
				int(row.get("id", 0)),
				Vector2i(int(row.get("x", 0)), int(row.get("z", 0))),
				def
			)
		else:
			spawn = CrystalSpawnPoint.new(
				int(row.get("id", 0)),
				Vector2i(int(row.get("x", 0)), int(row.get("z", 0))),
				int(row.get("kind", CrystalTypes.SpawnKind.RUIN)),
				float(row.get("max_health", 100.0)),
				bool(row.get("is_boss", false))
			)
			spawn.display_name = str(row.get("display_name", spawn.display_name))
			spawn.emit_rate = float(row.get("emit_rate", spawn.emit_rate))
			spawn.weaken_factor = float(row.get("weaken_factor", spawn.weaken_factor))
			spawn.power_drain = float(row.get("power_drain", spawn.power_drain))
		spawn.health = float(row.get("health", spawn.max_health))
		spawn.active = bool(row.get("active", true))
		spawn.max_health = float(row.get("max_health", spawn.max_health))
		_spawn_points.append(spawn)
		_next_spawn_id = maxi(_next_spawn_id, spawn.id + 1)

	_sync_spawn_controller()
	_recalc_stats()
	_rebuild_cell_index()
	refresh_spawn_marker_textures()
	_flush_dirty_chunks()
	_log_spawn_status("restored")


func get_spawn_marker(spawn_id: int) -> MeshInstance3D:
	var anchor: Node3D = _spawn_markers.get(spawn_id) as Node3D
	if anchor == null:
		return null
	return anchor.get_node_or_null("Mesh") as MeshInstance3D


func get_spawn_marker_ids() -> Array:
	return _spawn_markers.keys()


func get_debug_stats() -> Dictionary:
	var max_depth := 0.0
	if _sim:
		for pos_variant in _sim.depth.keys():
			max_depth = maxf(max_depth, float(_sim.depth[pos_variant]))
	var prog := get_spawn_progress()
	return {
		"tiles": covered_cells,
		"new_cells_last_tick": _last_crystal_new_cells,
		"volume": total_volume,
		"max_depth": max_depth,
		"power": power,
		"tier": strength_tier,
		"spawns_active": prog.active,
		"spawns_total": prog.total,
		"spawns_destroyed": prog.destroyed,
		"last_destroyed": prog.last_destroyed,
		"emit_weaken_mult": prog.emit_weaken_mult,
		"boss_active": prog.boss_active,
		"boss_sealed": prog.get("boss_sealed", false),
	}
