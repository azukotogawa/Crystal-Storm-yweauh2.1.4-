class_name CrystalManager
extends Node3D

const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalEvolution = preload("res://crystal/crystal_evolution.gd")
const _CrystalSimulation = preload("res://crystal/crystal_simulation.gd")
const _CrystalPresentation = preload("res://crystal/crystal_presentation.gd")
const _CrystalSimSnapshot = preload("res://crystal/crystal_sim_snapshot.gd")
const _CrystalSimEvents = preload("res://crystal/crystal_sim_events.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _SpawnPointRegistry = preload("res://config/spawn_point_registry.gd")
const _SpawnPointDef = preload("res://config/spawn_point_def.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _SpawnPointController = preload("res://crystal/spawn_point_controller.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")


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

## Fluid sim (compat): owned by CrystalSimulation; exposed for existing callers.
var _sim: _CrystalFluidSim
var _terrain_query: _CrystalTerrainQuery
## Simulation / presentation split (CrystalGameplayFacade = this class).
var _simulation: _CrystalSimulation
var _presentation: _CrystalPresentation
var _absorption: Dictionary = {}  # mirrored from simulation for save export
var _ruin_absorption: Dictionary = {}
var _absorbed_ruin_centers: Dictionary = {}
var evolution: _CrystalEvolution
var _spawn_points: Array[CrystalSpawnPoint] = []
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
var _sim_tick_id: int = 0
var _perf_mesh_budget_us: int = 2500
var _absorption_scan_offset: int = 0
var _absorption_cells_per_tick: int = 64
## Hold fluid expansion until CompositionRoot reaches INITIAL_STREAM_READY (stage 5).
## Avoids crystal tick_flow competing with boot stream / loading screen.
const _BOOT_STAGE_STREAM_READY: int = 5
## After large player chunk jumps (teleport), pause expansion briefly so stream apply wins.
const _TELEPORT_PAUSE_FRAMES: int = 24
const _STREAM_PENDING_PAUSE_THRESHOLD: int = 8
var _stream_pause_frames: int = 0
var _last_tracked_player_chunk: Vector2i = Vector2i(999999, 999999)
## Soft-start after gates clear so the first expansion ticks cannot spike one frame.
const _EXPANSION_SOFT_START_TICKS: int = 8
var _expansion_soft_ticks_left: int = _EXPANSION_SOFT_START_TICKS
## Hitch measurement (session counters).
var _last_process_us: int = 0
var _last_tick_us: int = 0
var _last_sim_steps: int = 0
var _process_max_us: int = 0
var _process_sum_us: int = 0
var _process_n: int = 0
var _expansion_skipped_frames: int = 0
## Frame-budgeted sim event dispatch (Phase 3). Critical events flush immediately.
var _dispatch_queue: Array = []  # {ev: Dictionary, enqueued_frame: int, enqueued_us: int}
var _dispatch_queue_age_max: int = 0
## Chunk rebuilds from absorption are deferred (one per frame) — immediate rebuild
## inside dispatch/drain was the multi-hundred-ms hitch source.
var _pending_absorption_rebuilds: Dictionary = {}  # Vector2i world cell -> true
var _perf_spread_damping_start: int = 600
var _perf_spread_damping_full: int = 3000
var _perf_mesh_rebuilds_when_large: int = 1
var _perf_mesh_depth_epsilon: float = 0.20
var _last_crystal_new_cells: int = 0
var _sim_loaded_chunks_only: bool = true
var _last_player_chunk: Vector2i = Vector2i(-99999, -99999)
## Diagnostics: last tick event count (no extra rebuilds checks).
var _last_sim_event_count: int = 0

## Single complete-tick fan-out trace (CRYSTALSTORM_CRYSTAL_TICK_TRACE=1).
var _tick_trace_armed: bool = false
var _tick_trace_active: bool = false
var _tick_trace_done: bool = false
var _tick_trace: Dictionary = {}

## Measurement-only (CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE=1): first N process frames after init.
const _MEASURE_FRAMES: int = 300
var _measure_init_ms: int = 0
var _measure_frame_i: int = 0
var _measure_rows: Array = []
var _measure_first_tick_logged: bool = false


func _crystal_measure_enabled() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on"


func _measure_record_frame(delta: float, sim_steps: int, tick_us_acc: int, process_us: int) -> void:
	if not _crystal_measure_enabled():
		return
	if _measure_frame_i == 0 and not _measure_first_tick_logged:
		_measure_first_tick_logged = true
		print("[CrystalStartupMeasure] FIRST _process AFTER INIT frame=%d t_ms=%d delta=%.4f expansion=%s cells=%d" % [
			Engine.get_process_frames(),
			Time.get_ticks_msec(),
			delta,
			str(expansion_enabled),
			_sim.cell_count() if _sim else 0,
		])
	var br: Dictionary = {}
	if _simulation and _simulation.has_method("consume_last_tick_breakdown"):
		br = _simulation.consume_last_tick_breakdown()
	var row := {
		"i": _measure_frame_i,
		"engine_frame": Engine.get_process_frames(),
		"t_ms": Time.get_ticks_msec() - _measure_init_ms,
		"delta": delta,
		"sim_steps": sim_steps,
		"process_us": process_us,
		"tick_us": tick_us_acc,
		"cells": _sim.cell_count() if _sim else 0,
		"new_cells": _last_crystal_new_cells,
		"events": _last_sim_event_count,
		"dispatch_q": _dispatch_queue.size(),
		"dirty_chunks": _presentation.dirty_chunk_count() if _presentation else 0,
		"breakdown": br,
	}
	_measure_rows.append(row)
	_measure_frame_i += 1
	if _measure_frame_i >= _MEASURE_FRAMES:
		_measure_print_report()


func _measure_print_report() -> void:
	if _measure_rows.is_empty():
		return
	var sum_process := 0
	var sum_tick := 0
	var sum_flow := 0
	var sum_emit := 0
	var sum_abs := 0
	var sum_animal := 0
	var sum_ruin := 0
	var sum_stats := 0
	var sum_active_cells := 0
	var sum_selected_cells := 0
	var sum_events := 0
	var sum_new := 0
	var max_process := 0
	var max_tick := 0
	var max_cells := 0
	for r_v in _measure_rows:
		var r: Dictionary = r_v
		sum_process += int(r.get("process_us", 0))
		sum_tick += int(r.get("tick_us", 0))
		sum_events += int(r.get("events", 0))
		sum_new += int(r.get("new_cells", 0))
		max_process = maxi(max_process, int(r.get("process_us", 0)))
		max_tick = maxi(max_tick, int(r.get("tick_us", 0)))
		max_cells = maxi(max_cells, int(r.get("cells", 0)))
		var br: Dictionary = r.get("breakdown", {})
		sum_flow += int(br.get("flow_us", 0))
		sum_emit += int(br.get("emitters_us", 0))
		sum_abs += int(br.get("absorption_us", 0))
		sum_animal += int(br.get("animal_us", 0))
		sum_ruin += int(br.get("ruin_us", 0))
		sum_stats += int(br.get("stats_us", 0))
		sum_active_cells += int(br.get("active_cells", 0))
		sum_selected_cells += int(br.get("selected_cells", 0))
	var n: int = _measure_rows.size()
	var first: Dictionary = _measure_rows[0]
	var last: Dictionary = _measure_rows[n - 1]
	print("")
	print("========== CRYSTAL STARTUP MEASURE (first %d frames after init) ==========" % n)
	print("started_by: CrystalManager._ready → call_deferred(_bootstrap_when_ready)")
	print("first_process_after_init: engine_frame=%s t_since_init_ms=%s cells=%s" % [
		str(first.get("engine_frame")), str(first.get("t_ms")), str(first.get("cells")),
	])
	print("cells first→last: %d → %d (max=%d)  new_cells_sum=%d  events_sum=%d" % [
		int(first.get("cells", 0)), int(last.get("cells", 0)), max_cells, sum_new, sum_events,
	])
	print("CrystalManager::_process  avg=%.2fms  max=%.2fms  total=%.1fms" % [
		float(sum_process) / float(n) / 1000.0, float(max_process) / 1000.0, float(sum_process) / 1000.0,
	])
	print("  of which sim ticks (sum steps) avg=%.2fms max=%.2fms total=%.1fms" % [
		float(sum_tick) / float(n) / 1000.0, float(max_tick) / 1000.0, float(sum_tick) / 1000.0,
	])
	print("CrystalSimulation.tick breakdown (sum over frames, us→ms):")
	var parts := [
		["flow_substeps (fluid.tick_flow × N)", sum_flow],
		["emitters", sum_emit],
		["absorption_scan", sum_abs],
		["animal_absorption", sum_animal],
		["ruin_absorption", sum_ruin],
		["recalc_volume/stats", sum_stats],
	]
	parts.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	var br_total: int = sum_flow + sum_emit + sum_abs + sum_animal + sum_ruin + sum_stats
	for p in parts:
		var pct: float = (float(p[1]) / float(maxi(br_total, 1))) * 100.0
		print("  %-40s total=%.1fms  avg/frame=%.2fms  (%.1f%% of measured tick parts)" % [
			str(p[0]), float(p[1]) / 1000.0, float(p[1]) / float(n) / 1000.0, pct,
		])
	print("flow cell scans: avg_active=%.1f avg_selected=%.1f per frame (sum of substeps)" % [
		float(sum_active_cells) / float(n), float(sum_selected_cells) / float(n),
	])
	# Classify work
	var cell0: int = int(first.get("cells", 0))
	var cell_growth: int = int(last.get("cells", 0)) - cell0
	var kind := "normal_simulation"
	if cell0 > 0 and float(sum_new) / float(maxi(n, 1)) > 0.5:
		kind = "normal_simulation_spreading"
	elif cell0 > 0 and abs(cell_growth) < maxi(cell0 / 20, 2):
		kind = "steady_state_sim_on_seeded_cells"
	if cell0 <= 16 and sum_new > 0:
		kind = "initialization_seed_plus_early_spread"
	print("work_class_estimate: %s" % kind)
	print("notes: ticks run every _process once _initialized; not gated on CompositionRoot RUNNING.")
	print("notes: spawn seeding (_initialize_spawns) plants initial emitter depths before first tick.")
	# Write JSON
	var out_path := "user://crystal_startup_measure.json"
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if not scratch.is_empty():
		out_path = scratch.path_join("crystal_startup_measure.json")
	var payload := {
		"frames": n,
		"first": first,
		"last": last,
		"sum_process_us": sum_process,
		"sum_tick_us": sum_tick,
		"sum_flow_us": sum_flow,
		"sum_emit_us": sum_emit,
		"sum_absorption_us": sum_abs,
		"sum_animal_us": sum_animal,
		"sum_ruin_us": sum_ruin,
		"sum_stats_us": sum_stats,
		"sum_new_cells": sum_new,
		"sum_events": sum_events,
		"max_cells": max_cells,
		"work_class": kind,
		"rows_sample": _measure_rows.slice(0, mini(10, n)),
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()
		print("WROTE %s" % out_path)
	print("========== END CRYSTAL STARTUP MEASURE ==========")
	print("")


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
	if _crystal_measure_enabled():
		print("[CrystalStartupMeasure] CrystalManager._ready → call_deferred(_bootstrap_when_ready) t_ms=%d process_enabled=%s" % [
			Time.get_ticks_msec(), str(is_processing()),
		])
	call_deferred("_bootstrap_when_ready")


func ensure_ready() -> void:
	while not _initialized:
		await get_tree().process_frame


func _bootstrap_when_ready() -> void:
	var t_boot0 := Time.get_ticks_msec()
	if _crystal_measure_enabled():
		print("[CrystalStartupMeasure] _bootstrap_when_ready ENTER t_ms=%d (started by CrystalManager._ready call_deferred)" % t_boot0)
	while world == null:
		world = get_tree().get_first_node_in_group("world")
		await get_tree().process_frame
	while chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
		await get_tree().process_frame
	if _crystal_measure_enabled():
		print("[CrystalStartupMeasure] waiting spawn_area_ready(0,0) t_ms=%d" % Time.get_ticks_msec())
	while not chunk_manager.spawn_area_ready(0, 0):
		await get_tree().process_frame
	if _crystal_measure_enabled():
		print("[CrystalStartupMeasure] spawn_area_ready OK t_ms=%d" % Time.get_ticks_msec())

	var features = get_tree().get_first_node_in_group("world_features")
	if features and features.has_method("ensure_ready"):
		await features.ensure_ready()

	evolution = _CrystalEvolution.new()
	configure_evolution()
	_init_sim()
	if _crystal_measure_enabled():
		print("[CrystalStartupMeasure] _init_sim done t_ms=%d" % Time.get_ticks_msec())
	_initialize_spawns()
	if _crystal_measure_enabled():
		var cell_n := _sim.cell_count() if _sim else 0
		print("[CrystalStartupMeasure] _initialize_spawns done cells=%d spawns=%d t_ms=%d" % [
			cell_n, _spawn_points.size() if _spawn_points else 0, Time.get_ticks_msec(),
		])
	_rebuild_cell_index()
	_bind_chunk_stream()
	_initialized = true
	if _crystal_measure_enabled():
		_measure_init_ms = Time.get_ticks_msec()
		_measure_frame_i = 0
		_measure_rows.clear()
		print("[CrystalStartupMeasure] _initialized=true FIRST_TICK_ELIGIBLE t_ms=%d bootstrap_ms=%d expansion_enabled=%s sim_hz=%.1f" % [
			_measure_init_ms, _measure_init_ms - t_boot0, str(expansion_enabled), _perf_sim_hz,
		])
		print("[CrystalStartupMeasure] NOTE: _process was registered from Node entry; ticks begin once _initialized is true.")


func configure_evolution() -> void:
	if evolution == null:
		return
	var table: Array = []
	var cfg_svc = get_tree().get_first_node_in_group("config_service") if is_inside_tree() else null
	if cfg_svc and cfg_svc.game_config and cfg_svc.game_config.absorption_unlocks.size() > 0:
		table = cfg_svc.game_config.absorption_unlocks
	evolution.configure(table)
	# Vertical slice: crystal_mite family is available at run start so combat pressure exists.
	if not evolution.is_unlocked(&"crystal_mite"):
		evolution.unlocked_enemies.append(&"crystal_mite")
	if evolution.has_signal("enemy_unlocked") and not evolution.enemy_unlocked.is_connected(_on_enemy_unlocked_grant_relic):
		evolution.enemy_unlocked.connect(_on_enemy_unlocked_grant_relic)


## Map absorption enemy unlocks → starter relics for progression feedback.
static func relic_for_enemy_unlock(enemy_id: StringName) -> StringName:
	match enemy_id:
		&"crystal_mite":
			return &"mason_glove"
		&"thornling":
			return &"flow_anchor"
		&"farm_bomber":
			return &"crystal_ward"
		_:
			return &""


func _on_enemy_unlocked_grant_relic(enemy_id: StringName) -> void:
	_grant_relic_for_unlock(enemy_id)


func _grant_relic_for_unlock(enemy_id: StringName) -> StringName:
	var relic_id: StringName = relic_for_enemy_unlock(enemy_id)
	if relic_id == &"":
		return &""
	var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player == null:
		return &""
	var relic_mgr = player.get_node_or_null("RelicManager")
	if relic_mgr == null:
		relic_mgr = get_tree().get_first_node_in_group("relic_manager") if is_inside_tree() else null
	if relic_mgr and relic_mgr.has_method("equip"):
		if relic_mgr.equip(relic_id):
			return relic_id
	return &""


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
	if _simulation:
		_simulation.set_config(cfg)
	if _sim:
		_sim.config = cfg
	if _presentation:
		_presentation.sim_config = cfg
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
	_simulation = _CrystalSimulation.new(sim_config, _terrain_query)
	_sim = _simulation.fluid
	_sim.is_cell_active = Callable(self, "_is_cell_sim_active")
	# Re-apply last quality caps (perf may have run before sim existed).
	_reapply_stored_flow_caps()
	# Presentation: mesh scheduling only; receives events from simulation.
	_presentation = _CrystalPresentation.new()
	_presentation.fluid = _sim
	_presentation.sim_config = sim_config
	_presentation.layer_root = _layer_root
	_presentation.crystal_material = _crystal_material
	_presentation.chunk_size = ChunkData.SIZE
	_presentation.crystal_floor_at = Callable(self, "_crystal_floor_at")
	_presentation.is_chunk_render_active = Callable(self, "_is_chunk_render_active")
	_presentation.player_chunk_coord = Callable(self, "_player_chunk_coord")
	_presentation.make_layer = Callable(self, "_make_chunk_layer")
	_presentation.max_rebuilds_per_frame = _perf_max_rebuilds_per_frame
	_presentation.mesh_budget_us = _perf_mesh_budget_us
	_presentation.spread_damping_start = _perf_spread_damping_start
	_presentation.spread_damping_full = _perf_spread_damping_full
	_presentation.mesh_rebuilds_when_large = _perf_mesh_rebuilds_when_large


func _make_chunk_layer(coord: Vector2i) -> CrystalChunkLayer:
	var layer := CrystalChunkLayer.new()
	layer.name = "CrystalChunk_%d_%d" % [coord.x, coord.y]
	_layer_root.add_child(layer)
	layer.setup(coord, _crystal_material)
	return layer


func _on_sim_depth_changed(pos: Vector2i) -> void:
	# Compat path for direct fluid signals (if any); prefer event batch from simulation.
	if _presentation:
		_presentation.apply_events([
			_CrystalSimEvents.depth_changed(pos),
			_CrystalSimEvents.mesh_dirty([pos]),
		])
	_stats_dirty = true
	fluid_changed.emit(pos)


func _on_sim_depth_cleared(pos: Vector2i) -> void:
	if _presentation:
		_presentation.apply_events([
			_CrystalSimEvents.depth_cleared(pos),
			_CrystalSimEvents.mesh_dirty([pos]),
		])
	_stats_dirty = true
	fluid_changed.emit(pos)


func _rebuild_cell_index() -> void:
	if _presentation:
		_presentation.rebuild_cell_index()


func get_fluid_sim() -> _CrystalFluidSim:
	return _sim


func get_simulation():
	return _simulation


func get_presentation():
	return _presentation


func _setup_materials() -> void:
	_crystal_material = StandardMaterial3D.new()
	_crystal_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_crystal_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crystal_material.albedo_color = Color(0.58, 0.22, 0.95, 0.78)
	_crystal_material.emission_enabled = true
	_crystal_material.emission = Color(0.38, 0.12, 0.78)
	_crystal_material.emission_energy_multiplier = 1.35
	_crystal_material.roughness = 0.18
	_crystal_material.metallic = 0.25

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
	var origin_pos := _resolve_origin_spawn_position()
	var origin := CrystalSpawnPoint.from_def(_alloc_spawn_id(), origin_pos, origin_def)
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


func pick_origin_spawn_cell() -> Vector2i:
	return _resolve_origin_spawn_position()


func _resolve_origin_spawn_position() -> Vector2i:
	var preferred := Vector2i.ZERO
	if _origin_cell_unsuitable(preferred):
		var land := _pick_nearest_land_spawn(preferred)
		if land != preferred:
			print("[Crystal] Origin relocated %s → %s (avoid water at map center)" % [preferred, land])
		return land
	return preferred


func _origin_cell_unsuitable(pos: Vector2i) -> bool:
	if world == null:
		return false
	if CrystalTypes.is_water_tile(_tile_at(pos)):
		return true
	var surface := _terrain_at(pos)
	return not _is_origin_land_surface(surface)


func _origin_surface_bounds() -> Vector2:
	# Valley grass near rivers can sit well below SEA_LEVEL; still walkable/buildable.
	return Vector2(4.0, 138.0)


func _is_origin_land_surface(surface: float) -> bool:
	var bounds := _origin_surface_bounds()
	return surface >= bounds.x and surface <= bounds.y


func _pick_nearest_land_spawn(around: Vector2i) -> Vector2i:
	if world == null:
		return around
	var bounds := _origin_surface_bounds()
	for radius in 128:
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var pos := Vector2i(around.x + dx, around.y + dz)
				if not _WorldBorder.is_playable(float(pos.x), float(pos.y)):
					continue
				if CrystalTypes.is_water_tile(_tile_at(pos)):
					continue
				var surface := _terrain_at(pos)
				if surface < bounds.x or surface > bounds.y:
					continue
				return pos
	push_warning("[Crystal] No dry land near %s — using fallback (12, 0)" % around)
	return Vector2i(12, 0)


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


## Last performance config (re-applied after late _init_sim).
var _stored_perf_cfg = null
## Soft wall for tick_flow cell processing (us). 0 = unlimited.
var _perf_flow_budget_us: int = 2500
## Cached loaded-chunk set for snapshots (rebuilt when chunk count changes).
var _loaded_chunks_cache: Dictionary = {}
var _loaded_chunks_cache_n: int = -1
## True while CrystalSimulation has an incomplete budgeted tick.
var _sim_tick_pending: bool = false


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	_stored_perf_cfg = cfg
	_perf_crystal_skip_frames = int(cfg.crystal_sim_skip_frames)
	_perf_max_rebuilds_per_frame = int(cfg.max_crystal_chunk_rebuilds_per_frame)
	_perf_sim_hz = maxf(float(cfg.crystal_sim_hz), 4.0)
	expansion_enabled = bool(cfg.crystal_sim_enabled)
	if cfg.flow_substeps > 0:
		flow_substeps = cfg.flow_substeps
		if sim_config:
			sim_config.flow_substeps = cfg.flow_substeps
	# ~1/3 of main-thread budget for fluid processing; clamps worst frame.
	if "main_thread_budget_us" in cfg:
		_perf_flow_budget_us = maxi(int(cfg.main_thread_budget_us) / 3, 1200)
	elif "chunk_upload_budget_us" in cfg:
		_perf_flow_budget_us = maxi(int(cfg.chunk_upload_budget_us), 1200)
	if _simulation:
		_simulation.flow_budget_us = _perf_flow_budget_us
	if _sim:
		_sim.max_cells_per_tick = int(cfg.max_crystal_flow_cells)
		_sim.flow_budget_us = _perf_flow_budget_us
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
	if _presentation:
		_presentation.max_rebuilds_per_frame = _perf_max_rebuilds_per_frame
		_presentation.mesh_budget_us = _perf_mesh_budget_us
		_presentation.spread_damping_start = _perf_spread_damping_start
		_presentation.spread_damping_full = _perf_spread_damping_full
		_presentation.mesh_rebuilds_when_large = _perf_mesh_rebuilds_when_large


func _reapply_stored_flow_caps() -> void:
	if _stored_perf_cfg != null:
		apply_performance_config(_stored_perf_cfg)
		return
	# Fallback from performance service if config was applied before this node existed.
	if not is_inside_tree():
		return
	var perf = get_tree().get_first_node_in_group("performance_service")
	if perf and "quality" in perf and perf.quality:
		apply_performance_config(perf.quality)


func _tick_trace_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_CRYSTAL_TICK_TRACE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on"


func begin_tick_trace_arm() -> void:
	_tick_trace_armed = true
	_tick_trace_active = false
	_tick_trace_done = false
	_tick_trace.clear()


func is_tick_trace_done() -> bool:
	return _tick_trace_done


func get_tick_trace() -> Dictionary:
	return _tick_trace.duplicate(true)


func _tick_trace_start(reason: String) -> void:
	if not _tick_trace_armed or _tick_trace_active or _tick_trace_done:
		return
	_tick_trace_active = true
	_tick_trace = {
		"reason": reason,
		"t0_us": Time.get_ticks_usec(),
		"engine_frame": Engine.get_process_frames(),
		"sim_tick_id": _sim_tick_id,
		"cells_before": _sim.cell_count() if _sim else 0,
		"events_from_sim": 0,
		"events_by_kind": {},
		"critical_applies": 0,
		"deferred_enqueued": 0,
		"flow_batch_splits": 0,
		"apply_one_sim_event": 0,
		"apply_by_kind": {},
		"dispatch_queue_depth_after_dispatch": 0,
		"drain_applies_same_frame": 0,
		"complete_absorption_calls": 0,
		"clear_feature_calls": 0,
		"clear_tile_calls": 0,
		"rebuild_chunk_calls": 0,
		"presentation_apply_events": 0,
		"worldstate_bumps": 0,
		"spatial_ws_changed": 0,
		"spatial_reindex_chunks": 0,
		"gvr_refresh": {},
		"phases_us": {},
	}
	var ws = load("res://world/world_state.gd")
	if ws and ws.has_method("reset_trace_counters"):
		ws.reset_trace_counters()
	if is_inside_tree():
		var sq = get_tree().get_first_node_in_group("spatial_query_service")
		if sq and sq.has_method("reset_trace_counters"):
			sq.reset_trace_counters()
		var gvr = get_tree().get_first_node_in_group("game_visual_registry")
		if gvr and gvr.has_method("reset_trace_counters"):
			gvr.reset_trace_counters()


func _tick_trace_phase(name: String, t0: int) -> void:
	if not _tick_trace_active:
		return
	var phases: Dictionary = _tick_trace.get("phases_us", {})
	phases[name] = int(phases.get(name, 0)) + (Time.get_ticks_usec() - t0)
	_tick_trace["phases_us"] = phases


func _tick_trace_kind(map_key: String, kind: int) -> void:
	if not _tick_trace_active:
		return
	var m: Dictionary = _tick_trace.get(map_key, {})
	var k := str(kind)
	m[k] = int(m.get(k, 0)) + 1
	_tick_trace[map_key] = m


func _tick_trace_finish() -> void:
	if not _tick_trace_active or _tick_trace_done:
		return
	var ws = load("res://world/world_state.gd")
	if ws and ws.has_method("get_trace_bump_count"):
		_tick_trace["worldstate_bumps"] = int(ws.get_trace_bump_count())
		_tick_trace["worldstate_bump_domains"] = ws.get_trace_bump_domains() if ws.has_method("get_trace_bump_domains") else []
		ws.stop_trace_counters()
	if is_inside_tree():
		var sq = get_tree().get_first_node_in_group("spatial_query_service")
		if sq and sq.has_method("get_trace_ws_changed_count"):
			_tick_trace["spatial_ws_changed"] = int(sq.get_trace_ws_changed_count())
			_tick_trace["spatial_reindex_chunks"] = int(sq.get_trace_ws_reindex_chunks()) if sq.has_method("get_trace_ws_reindex_chunks") else 0
			if sq.has_method("stop_trace_counters"):
				sq.stop_trace_counters()
		var gvr = get_tree().get_first_node_in_group("game_visual_registry")
		if gvr and gvr.has_method("get_trace_refresh_counts"):
			_tick_trace["gvr_refresh"] = gvr.get_trace_refresh_counts()
			if gvr.has_method("stop_trace_counters"):
				gvr.stop_trace_counters()
	_tick_trace["cells_after"] = _sim.cell_count() if _sim else 0
	_tick_trace["total_us"] = Time.get_ticks_usec() - int(_tick_trace.get("t0_us", 0))
	_tick_trace["dispatch_queue_remaining"] = _dispatch_queue.size()
	_tick_trace_active = false
	_tick_trace_done = true
	_tick_trace_armed = false
	print("\n========== CRYSTAL SINGLE-TICK TRACE ==========")
	print(JSON.stringify(_tick_trace, "\t"))
	print("========== END SINGLE-TICK TRACE ==========\n")


func _process(delta: float) -> void:
	if not _initialized:
		return
	if _tick_trace_env() and not _tick_trace_armed and not _tick_trace_done:
		begin_tick_trace_arm()
	var measure := _crystal_measure_enabled() and _measure_frame_i < _MEASURE_FRAMES
	var proc_t0 := Time.get_ticks_usec()
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_manager")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("CrystalManager::_process")

	_update_stream_pause_state()
	var run_expansion := _should_run_expansion()
	var sim_steps := 0
	var tick_us_acc := 0
	# Always finish an in-progress budgeted tick first (preserves logical tick results).
	if _sim_tick_pending and _simulation:
		var tt0 := Time.get_ticks_usec()
		_continue_crystal_sim()
		tick_us_acc += Time.get_ticks_usec() - tt0
		if not _sim_tick_pending:
			sim_steps = 1
	elif run_expansion:
		_sim_accum += delta
		var step_dt := 1.0 / _perf_sim_hz
		# Soft-start + stream pressure: at most one sim step/frame until warm.
		var max_steps := 1
		if _expansion_soft_ticks_left <= 0 and not _stream_pressure_active():
			max_steps = 2
		# Soft-start spreads the first expansion ticks across frames (skip odd frames).
		var allow_tick := true
		if _expansion_soft_ticks_left > 0:
			allow_tick = (_process_n % 2) == 0
		while allow_tick and _sim_accum >= step_dt and sim_steps < max_steps:
			var tt0 := Time.get_ticks_usec()
			_tick_crystal_sim(step_dt)
			tick_us_acc += Time.get_ticks_usec() - tt0
			_sim_accum -= step_dt
			sim_steps += 1
			if _expansion_soft_ticks_left > 0:
				_expansion_soft_ticks_left -= 1
			if _sim_tick_pending:
				break
		# Drop excess accumulator after pause so resume does not multi-tick.
		if _sim_accum > step_dt * 2.0:
			_sim_accum = step_dt
		# Absorption is advanced inside CrystalSimulation.tick via snapshot; side effects applied from events.
		var power_t0 := Time.get_ticks_usec()
		_tick_power(delta)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("CrystalManager::_tick_power", Time.get_ticks_usec() - power_t0)
		_check_player_contact()
	else:
		_expansion_skipped_frames += 1
		# Prevent catch-up burst when expansion resumes after boot/teleport/stream.
		if not _sim_tick_pending:
			_sim_accum = 0.0
		# Re-arm soft-start so resume after long stream/teleport is gentle.
		if _stream_pause_frames > 0 or not _boot_stream_ready():
			_expansion_soft_ticks_left = maxi(_expansion_soft_ticks_left, _EXPANSION_SOFT_START_TICKS)

	_sync_spawn_marker_visibility()
	if _presentation:
		var lod_t0 := Time.get_ticks_usec()
		_last_player_chunk = _presentation.refresh_lod_if_player_moved(_last_player_chunk)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("CrystalPresentation::refresh_lod", Time.get_ticks_usec() - lod_t0)
	if run_expansion or (_presentation and _presentation.dirty_chunk_count() > 0):
		_flush_dirty_chunks()

	# Drain deferred sim events under FrameBudgetScheduler (cannot monopolize frame).
	var drain_t0 := Time.get_ticks_usec() if _tick_trace_active else 0
	var applies_before := int(_tick_trace.get("apply_one_sim_event", 0)) if _tick_trace_active else 0
	_drain_dispatch_queue_budgeted()
	_drain_one_absorption_rebuild()
	if _tick_trace_active:
		_tick_trace["drain_applies_same_frame"] = int(_tick_trace.get("apply_one_sim_event", 0)) - applies_before
		_tick_trace_phase("drain_dispatch_queue", drain_t0)
		# Finish once first complete logical tick has been dispatched this frame
		# (queue may still hold deferred FLOW_BATCH slices for later frames).
		if int(_tick_trace.get("events_from_sim", 0)) > 0 and not _sim_tick_pending:
			_tick_trace_finish()

	if profiler and profiler.has_method("end_func"):
		profiler.end_func("CrystalManager::_process")
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_manager")

	var proc_us := Time.get_ticks_usec() - proc_t0
	_last_process_us = proc_us
	_last_tick_us = tick_us_acc
	_last_sim_steps = sim_steps
	_process_max_us = maxi(_process_max_us, proc_us)
	_process_sum_us += proc_us
	_process_n += 1
	if _stream_wake_enabled:
		_process_frames_total += 1
		_process_sim_steps_total += sim_steps
		if sim_steps > 0:
			_process_frames_with_sim += 1
		if _stream_pressure_active():
			_process_frames_with_stream_pressure += 1

	if measure:
		_measure_record_frame(delta, sim_steps, tick_us_acc, proc_us)


## True when fluid expansion may run (export on + boot/stream gates clear).
func _should_run_expansion() -> bool:
	if not expansion_enabled:
		return false
	if not _boot_stream_ready():
		return false
	if _stream_pause_frames > 0:
		return false
	if _stream_pressure_active():
		return false
	return true


func _boot_stream_ready() -> bool:
	if not is_inside_tree():
		return true
	var root = get_tree().get_first_node_in_group("composition_root")
	if root == null or not ("stage" in root):
		return true
	return int(root.stage) >= _BOOT_STAGE_STREAM_READY


func _stream_pressure_active() -> bool:
	if chunk_manager == null:
		return false
	if "_stream_load_pending" in chunk_manager:
		if int(chunk_manager._stream_load_pending.size()) >= _STREAM_PENDING_PAUSE_THRESHOLD:
			return true
	if "pending" in chunk_manager and int(chunk_manager.pending.size()) > 12:
		return true
	return false


func _update_stream_pause_state() -> void:
	if _stream_pause_frames > 0:
		_stream_pause_frames -= 1
	var pc := _player_chunk_coord()
	if pc == _PLAYER_CHUNK_MISSING:
		return
	if _last_tracked_player_chunk.x > 900000:
		_last_tracked_player_chunk = pc
		return
	var manhattan := absi(pc.x - _last_tracked_player_chunk.x) + absi(pc.y - _last_tracked_player_chunk.y)
	if manhattan >= 3:
		# Teleport / large stream jump — yield frames to chunk activation.
		_stream_pause_frames = maxi(_stream_pause_frames, _TELEPORT_PAUSE_FRAMES)
		_sim_accum = 0.0
	_last_tracked_player_chunk = pc


func get_last_process_us() -> int:
	return _last_process_us


func get_last_tick_us() -> int:
	return _last_tick_us


func get_last_sim_steps() -> int:
	return _last_sim_steps


func get_hitch_counters() -> Dictionary:
	return {
		"crystal_process_max_us": _process_max_us,
		"crystal_process_avg_us": int(float(_process_sum_us) / float(maxi(_process_n, 1))),
		"crystal_process_n": _process_n,
		"expansion_skipped_frames": _expansion_skipped_frames,
		"stream_pause_frames": _stream_pause_frames,
		"last_process_us": _last_process_us,
		"last_tick_us": _last_tick_us,
		"last_sim_steps": _last_sim_steps,
		"crystal_cells": covered_cells,
		"expansion_enabled": expansion_enabled,
	}


func _build_sim_snapshot(delta: float):
	var snap = _CrystalSimSnapshot.new()
	snap.tick_id = _sim_tick_id
	snap.delta = delta
	snap.flow_substeps = maxi(sim_config.flow_substeps if sim_config else flow_substeps, 1)
	snap.global_flow_mult = _relic_flow_mult()
	snap.emit_weaken_mult = _spawn_ctrl.emit_weaken_mult if _spawn_ctrl else 1.0
	snap.spawn_emitters = _spawn_points
	snap.sim_loaded_chunks_only = _sim_loaded_chunks_only
	snap.chunk_size = ChunkData.SIZE
	snap.terrain = _terrain_query
	snap.absorption_scan_cells = _absorption_cells_per_tick
	snap.absorption_scan_offset = _absorption_scan_offset
	if sim_config:
		snap.grass_absorb_rate = sim_config.grass_absorb_rate
		snap.bush_absorb_rate = sim_config.bush_absorb_rate
		snap.tree_absorb_rate = sim_config.tree_absorb_rate
		snap.farmland_absorb_rate = sim_config.farmland_absorb_rate
		snap.min_depth = sim_config.min_depth
	snap.ruin_centers = _FeatureRegistry.get_ruin_centers()
	snap.feature_at = Callable(self, "_feature_at_for_snapshot")
	snap.tile_at = Callable(self, "_tile_at")
	# Loaded chunk set from ChunkManager (façade gathers; sim never touches the tree).
	snap.loaded_chunks = _get_loaded_chunks_snapshot()
	# Spatial query (optional read-only discovery handle).
	if is_inside_tree():
		var sq = get_tree().get_first_node_in_group("spatial_query_service")
		if sq:
			snap.spatial_query = sq
	return snap


func _get_loaded_chunks_snapshot() -> Dictionary:
	if chunk_manager == null or not ("chunks" in chunk_manager):
		return {}
	var n: int = int(chunk_manager.chunks.size())
	if n == _loaded_chunks_cache_n and not _loaded_chunks_cache.is_empty():
		return _loaded_chunks_cache
	var out: Dictionary = {}
	for coord in chunk_manager.chunks.keys():
		out[coord] = true
	_loaded_chunks_cache = out
	_loaded_chunks_cache_n = n
	return out


func _feature_at_for_snapshot(wx: int, wz: int) -> Dictionary:
	return _FeatureRegistry.get_feature(wx, wz)


func _tick_crystal_sim(delta: float) -> void:
	if _perf_crystal_skip_frames > 0 and not _sim_tick_pending:
		_perf_skip_counter = (_perf_skip_counter + 1) % (_perf_crystal_skip_frames + 1)
		if _perf_skip_counter != 0:
			return
		delta *= float(_perf_crystal_skip_frames + 1)

	_sim_tick_id += 1
	if _tick_trace_armed and not _tick_trace_active and not _tick_trace_done:
		_tick_trace_start("tick_crystal_sim")
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_sim")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("CrystalManager::_tick_crystal_sim")
	if _simulation:
		_simulation.flow_budget_us = _perf_flow_budget_us
		if _sim:
			_sim.flow_budget_us = _perf_flow_budget_us
		var snap_t0 := Time.get_ticks_usec()
		var snap = _build_sim_snapshot(delta)
		_tick_trace_phase("build_sim_snapshot", snap_t0)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("CrystalManager::_build_sim_snapshot", Time.get_ticks_usec() - snap_t0)
		var tick_t0 := Time.get_ticks_usec()
		var events: Array = _simulation.tick(snap)
		_tick_trace_phase("simulation_tick", tick_t0)
		if profiler and profiler.has_method("record_func"):
			profiler.record_func("CrystalSimulation::tick", Time.get_ticks_usec() - tick_t0)
		if not _simulation.last_tick_complete:
			_sim_tick_pending = true
			if profiler and profiler.has_method("end_func"):
				profiler.end_func("CrystalManager::_tick_crystal_sim")
			if profiler and profiler.has_method("end"):
				profiler.end("crystal_sim")
			return
		_sim_tick_pending = false
		_finish_tick_side_effects(events, profiler)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("CrystalManager::_tick_crystal_sim")
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_sim")


func _continue_crystal_sim() -> void:
	if _simulation == null:
		_sim_tick_pending = false
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("crystal_sim")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("CrystalManager::_tick_crystal_sim")
	_simulation.flow_budget_us = _perf_flow_budget_us
	if _sim:
		_sim.flow_budget_us = _perf_flow_budget_us
	var tick_t0 := Time.get_ticks_usec()
	var events: Array = _simulation.tick(null)
	_tick_trace_phase("simulation_tick_resume", tick_t0)
	if not _simulation.last_tick_complete:
		_sim_tick_pending = true
	else:
		_sim_tick_pending = false
		_finish_tick_side_effects(events, profiler)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("CrystalManager::_tick_crystal_sim")
	if profiler and profiler.has_method("end"):
		profiler.end("crystal_sim")


func _finish_tick_side_effects(events: Array, profiler = null) -> void:
	_last_sim_event_count = events.size()
	if _tick_trace_active:
		_tick_trace["events_from_sim"] = events.size()
		for ev_v in events:
			if ev_v is Dictionary:
				_tick_trace_kind("events_by_kind", int(ev_v.get("kind", 0)))
				if int(ev_v.get("kind", 0)) == _CrystalSimEvents.Kind.FLOW_BATCH:
					_tick_trace["flow_batch_changed_n"] = int(ev_v.get("changed", []).size()) if ev_v.get("changed") is Array else 0
					_tick_trace["flow_batch_mesh_dirty_n"] = int(ev_v.get("mesh_dirty", []).size()) if ev_v.get("mesh_dirty") is Array else 0
					_tick_trace["flow_batch_new_cells"] = int(ev_v.get("new_cells", 0))
	var disp_t0 := Time.get_ticks_usec()
	_dispatch_sim_events(events)
	_tick_trace_phase("dispatch_sim_events", disp_t0)
	if profiler and profiler.has_method("record_func"):
		profiler.record_func("CrystalManager::_dispatch_sim_events", Time.get_ticks_usec() - disp_t0)
	_last_crystal_new_cells = _simulation.last_new_cells if _simulation else 0
	covered_cells = _sim.cell_count() if _sim else 0
	_absorption_scan_offset += _absorption_cells_per_tick
	if _simulation:
		_absorption = _simulation.absorption
		_ruin_absorption = _simulation.ruin_absorption
		_absorbed_ruin_centers = _simulation.absorbed_ruin_centers
	if profiler and profiler.has_method("set_gauge"):
		profiler.set_gauge("crystal_cells", float(covered_cells))
		profiler.set_gauge("crystal_new_cells", float(_last_crystal_new_cells))
		if _simulation:
			profiler.set_gauge("crystal_changed_cells", float(_simulation.last_mesh_dirty_count))


func _dispatch_sim_events(events: Array) -> void:
	## Split critical vs deferred. Simulation algorithms unchanged — only when side-effects run.
	var frame_id := 0
	var sched = get_node_or_null("/root/FrameBudgetScheduler")
	if sched and sched.has_method("get_frame_id"):
		frame_id = int(sched.get_frame_id())
	var now_us := Time.get_ticks_usec()
	for ev_v in events:
		if not ev_v is Dictionary:
			continue
		var ev: Dictionary = ev_v
		if _is_critical_sim_event(ev):
			if _tick_trace_active:
				_tick_trace["critical_applies"] = int(_tick_trace.get("critical_applies", 0)) + 1
			_apply_one_sim_event(ev)
			continue
		# Split large FLOW_BATCH so one unit cannot monopolize a frame.
		if int(ev.get("kind", 0)) == _CrystalSimEvents.Kind.FLOW_BATCH:
			var q0 := _dispatch_queue.size()
			_enqueue_flow_batch_units(ev, frame_id, now_us)
			if _tick_trace_active:
				var added := _dispatch_queue.size() - q0
				_tick_trace["flow_batch_splits"] = int(_tick_trace.get("flow_batch_splits", 0)) + added
				_tick_trace["deferred_enqueued"] = int(_tick_trace.get("deferred_enqueued", 0)) + added
			continue
		_dispatch_queue.append({
			"ev": ev,
			"enqueued_frame": frame_id,
			"enqueued_us": now_us,
		})
		if _tick_trace_active:
			_tick_trace["deferred_enqueued"] = int(_tick_trace.get("deferred_enqueued", 0)) + 1
	if _tick_trace_active:
		_tick_trace["dispatch_queue_depth_after_dispatch"] = _dispatch_queue.size()
	_report_dispatch_queue()


const _FLOW_DIRTY_CHUNK: int = 32


func _enqueue_flow_batch_units(ev: Dictionary, frame_id: int, now_us: int) -> void:
	# Split both changed + mesh_dirty so a single budget unit stays small.
	var changed: Array = ev.get("changed", [])
	var mesh_dirty: Array = ev.get("mesh_dirty", [])
	var new_cells_left: int = int(ev.get("new_cells", 0))
	var ci := 0
	if changed.is_empty() and mesh_dirty.is_empty():
		_dispatch_queue.append({
			"ev": {
				"kind": _CrystalSimEvents.Kind.FLOW_BATCH,
				"changed": [],
				"mesh_dirty": [],
				"new_cells": new_cells_left,
			},
			"enqueued_frame": frame_id,
			"enqueued_us": now_us,
		})
		return
	while ci < changed.size():
		var cslice: Array = changed.slice(ci, mini(ci + _FLOW_DIRTY_CHUNK, changed.size()))
		var nc := 0
		if ci == 0:
			nc = new_cells_left
		_dispatch_queue.append({
			"ev": {
				"kind": _CrystalSimEvents.Kind.FLOW_BATCH,
				"changed": cslice,
				"mesh_dirty": [],
				"new_cells": nc,
			},
			"enqueued_frame": frame_id,
			"enqueued_us": now_us,
		})
		ci += _FLOW_DIRTY_CHUNK
	var mi := 0
	while mi < mesh_dirty.size():
		var mslice: Array = mesh_dirty.slice(mi, mini(mi + _FLOW_DIRTY_CHUNK, mesh_dirty.size()))
		_dispatch_queue.append({
			"ev": {
				"kind": _CrystalSimEvents.Kind.FLOW_BATCH,
				"changed": [],
				"mesh_dirty": mslice,
				"new_cells": 0,
			},
			"enqueued_frame": frame_id,
			"enqueued_us": now_us,
		})
		mi += _FLOW_DIRTY_CHUNK


func _is_critical_sim_event(ev: Dictionary) -> bool:
	## Immediate only for cheap/UI-critical stats. Absorption completes do WorldState.bump
	## ×2 + SpatialQuery full reindex + chunk rebuild — applying many as critical caused
	## multi-hundred-ms hitches in _dispatch_sim_events. They use the budgeted queue.
	var kind: int = int(ev.get("kind", 0))
	return kind in [
		_CrystalSimEvents.Kind.POWER_DELTA,
		_CrystalSimEvents.Kind.STATS,
	]


func _apply_one_sim_event(ev: Dictionary) -> void:
	# Presentation + gameplay for a single event (unit of budgeted work).
	if _tick_trace_active:
		_tick_trace["apply_one_sim_event"] = int(_tick_trace.get("apply_one_sim_event", 0)) + 1
		_tick_trace_kind("apply_by_kind", int(ev.get("kind", 0)))
	if _presentation:
		if _tick_trace_active:
			_tick_trace["presentation_apply_events"] = int(_tick_trace.get("presentation_apply_events", 0)) + 1
		_presentation.apply_events([ev])
	var kind: int = int(ev.get("kind", 0))
	match kind:
		_CrystalSimEvents.Kind.DEPTH_CHANGED, _CrystalSimEvents.Kind.DEPTH_CLEARED:
			_stats_dirty = true
			fluid_changed.emit(ev.pos)
		_CrystalSimEvents.Kind.FLOW_BATCH:
			_stats_dirty = true
		_CrystalSimEvents.Kind.MESH_DIRTY:
			pass
		_CrystalSimEvents.Kind.STATS:
			total_volume = float(ev.get("volume", total_volume))
			covered_cells = int(ev.get("cells", covered_cells))
			_stats_dirty = false
		_CrystalSimEvents.Kind.POWER_DELTA:
			_add_power(float(ev.get("amount", 0.0)))
		_CrystalSimEvents.Kind.ABSORPTION_READY:
			if _tick_trace_active:
				_tick_trace["complete_absorption_calls"] = int(_tick_trace.get("complete_absorption_calls", 0)) + 1
			_complete_absorption(ev.pos)
		_CrystalSimEvents.Kind.RUIN_ABSORPTION_READY:
			_apply_ruin_absorption_side_effects(ev.center)
		_:
			pass


func _drain_dispatch_queue_budgeted() -> void:
	var sched = get_node_or_null("/root/FrameBudgetScheduler")
	if _dispatch_queue.is_empty():
		_report_dispatch_queue()
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("CrystalManager::_drain_dispatch_queue")
	if sched and sched.has_method("run_budgeted"):
		sched.run_budgeted(&"crystal_dispatch", func(token):
			while token.can_continue() and not _dispatch_queue.is_empty():
				var item: Dictionary = _dispatch_queue.pop_front()
				var wait_us: int = Time.get_ticks_usec() - int(item.get("enqueued_us", Time.get_ticks_usec()))
				if sched.has_method("report_item_latency"):
					sched.report_item_latency(&"crystal_dispatch", wait_us)
				_apply_one_sim_event(item.get("ev", {}))
				token.spend_unit()
		)
	else:
		# Fallback: hard unit cap without scheduler autoload.
		var n := mini(_dispatch_queue.size(), 48)
		for _i in n:
			var item2: Dictionary = _dispatch_queue.pop_front()
			_apply_one_sim_event(item2.get("ev", {}))
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("CrystalManager::_drain_dispatch_queue")
	_report_dispatch_queue()


func _report_dispatch_queue() -> void:
	var sched = get_node_or_null("/root/FrameBudgetScheduler")
	if sched == null or not sched.has_method("report_queue_depth"):
		return
	var oldest := 0
	var frame_id := int(sched.get_frame_id()) if sched.has_method("get_frame_id") else 0
	if not _dispatch_queue.is_empty():
		var first: Dictionary = _dispatch_queue[0]
		oldest = maxi(frame_id - int(first.get("enqueued_frame", frame_id)), 0)
	_dispatch_queue_age_max = oldest
	sched.report_queue_depth(&"crystal_dispatch", _dispatch_queue.size(), oldest)


func get_dispatch_queue_depth() -> int:
	return _dispatch_queue.size()


## Emergency: flush all deferred events (save / win-lose critical paths).
func flush_dispatch_queue() -> void:
	var sched = get_node_or_null("/root/FrameBudgetScheduler")
	if sched and sched.has_method("note_emergency_flush"):
		sched.note_emergency_flush(&"crystal_dispatch")
	while not _dispatch_queue.is_empty():
		var item: Dictionary = _dispatch_queue.pop_front()
		_apply_one_sim_event(item.get("ev", {}))
	# Save/export must apply pending absorption mesh rebuilds for consistency.
	while not _pending_absorption_rebuilds.is_empty():
		_drain_one_absorption_rebuild()
	_report_dispatch_queue()


func _apply_ruin_absorption_side_effects(center: Vector2i) -> void:
	_add_power(18.0)
	if evolution:
		var unlock: Dictionary = evolution.record_absorption(&"ruin")
		if unlock.has("bonus_power"):
			_add_power(float(unlock.bonus_power))
	absorption_completed.emit(&"ruin", center)
	_clear_ruin_at(center)


func _set_depth(pos: Vector2i, depth: float, spawn_id: int = -1) -> void:
	if _simulation:
		var events: Array = _simulation.set_depth(pos, depth, spawn_id, true)
		_dispatch_sim_events(events)
	elif _sim:
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


func _crystal_floor_at(pos: Vector2i) -> float:
	if world == null:
		return 0.0
	var col_x := float(pos.x) + 0.5
	var col_z := float(pos.y) + 0.5
	var entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		entry = chunk_manager.get_ramp_entry_at_world(col_x, col_z)
	return TerrainRamps.walkable_height_from_entry(world, col_x, col_z, entry)


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
	if _presentation:
		_presentation.apply_events([_CrystalSimEvents.mesh_dirty([pos])])


## Stream wake counters (CRYSTALSTORM_STREAM_WAKE_TRACE=1).
var _stream_wake_enabled: bool = false
var _stream_chunk_loaded_n: int = 0
var _stream_chunk_unloaded_n: int = 0
var _stream_chunk_loaded_us: int = 0
var _stream_chunk_loaded_max_us: int = 0
var _stream_dirty_marked_n: int = 0
var _process_sim_steps_total: int = 0
var _process_frames_total: int = 0
var _process_frames_with_stream_pressure: int = 0
var _process_frames_with_sim: int = 0


func set_stream_wake_trace(enabled: bool) -> void:
	_stream_wake_enabled = enabled
	_stream_chunk_loaded_n = 0
	_stream_chunk_unloaded_n = 0
	_stream_chunk_loaded_us = 0
	_stream_chunk_loaded_max_us = 0
	_stream_dirty_marked_n = 0
	_process_sim_steps_total = 0
	_process_frames_total = 0
	_process_frames_with_stream_pressure = 0
	_process_frames_with_sim = 0


func get_stream_wake_trace() -> Dictionary:
	return {
		"chunk_loaded_n": _stream_chunk_loaded_n,
		"chunk_unloaded_n": _stream_chunk_unloaded_n,
		"chunk_loaded_us": _stream_chunk_loaded_us,
		"chunk_loaded_max_us": _stream_chunk_loaded_max_us,
		"dirty_marked_n": _stream_dirty_marked_n,
		"process_frames": _process_frames_total,
		"process_frames_with_sim": _process_frames_with_sim,
		"process_sim_steps_total": _process_sim_steps_total,
		"process_frames_stream_pressure": _process_frames_with_stream_pressure,
		"note": "CrystalSimulation.tick is driven by Node._process accumulator, NOT by chunk_ready. chunk_ready only dirties presentation layers.",
	}


func _on_chunk_loaded(coord: Vector2i, _data: ChunkData) -> void:
	var t0 := Time.get_ticks_usec() if _stream_wake_enabled else 0
	var marked := false
	if _presentation:
		var had := _presentation.dirty_chunk_count()
		_presentation.on_chunk_loaded(coord)
		if _stream_wake_enabled and _presentation.dirty_chunk_count() > had:
			_stream_dirty_marked_n += 1
			marked = true
	_sync_spawn_marker_visibility()
	if _stream_wake_enabled:
		var dt := Time.get_ticks_usec() - t0
		_stream_chunk_loaded_n += 1
		_stream_chunk_loaded_us += dt
		_stream_chunk_loaded_max_us = maxi(_stream_chunk_loaded_max_us, dt)
		# Invalidate loaded-chunk snapshot cache so next sim tick rebuilds set.
		_loaded_chunks_cache_n = -1


func _on_chunk_unloaded(coord: Vector2i) -> void:
	if _stream_wake_enabled:
		_stream_chunk_unloaded_n += 1
	if _presentation:
		_presentation.on_chunk_unloaded(coord)
	_sync_spawn_marker_visibility()
	if _stream_wake_enabled:
		_loaded_chunks_cache_n = -1


func _sync_spawn_marker_visibility() -> void:
	for spawn in _spawn_points:
		var marker = _spawn_markers.get(spawn.id)
		if marker == null or not is_instance_valid(marker):
			continue
		marker.visible = spawn.active


const _PLAYER_CHUNK_MISSING := Vector2i(-99999, -99999)


func _player_chunk_coord() -> Vector2i:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return _PLAYER_CHUNK_MISSING
	if player.has_method("get_voxel_position"):
		var col: Vector3 = player.get_voxel_position()
		return Vector2i(
			floori(col.x / float(ChunkData.SIZE)),
			floori(col.z / float(ChunkData.SIZE))
		)
	var ws = _WorldSettings.get_active()
	return Vector2i(
		floori(ws.world_to_column(player.global_position.x) / float(ChunkData.SIZE)),
		floori(ws.world_to_column(player.global_position.z) / float(ChunkData.SIZE))
	)


func _flush_dirty_chunks() -> void:
	if _presentation == null:
		return
	_presentation.max_rebuilds_per_frame = _perf_max_rebuilds_per_frame
	_presentation.mesh_budget_us = _perf_mesh_budget_us
	_presentation.spread_damping_start = _perf_spread_damping_start
	_presentation.spread_damping_full = _perf_spread_damping_full
	_presentation.mesh_rebuilds_when_large = _perf_mesh_rebuilds_when_large
	var profiler = get_node_or_null("/root/PerfProfiler")
	_presentation.flush(profiler)


func refresh_spawn_marker_textures() -> void:
	# Textures are session-cached; preload is a no-op when already generated.
	var vis = get_tree().get_first_node_in_group("game_visual_registry") if is_inside_tree() else null
	if vis and vis.has_method("preload_game_bundle"):
		vis.preload_game_bundle(false, "CrystalManager.refresh_spawn_marker_textures")
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
		var marker_size: float = 2.4 if spawn.is_boss else 1.6

		var anchor := Node3D.new()
		anchor.name = "SpawnMarker_%d" % spawn.id

		var marker := Sprite3D.new()
		marker.name = "Sprite"
		marker.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		marker.pixel_size = 0.022 if spawn.is_boss else 0.028
		marker.modulate = Color(1.0, 0.92, 1.0, 0.95) if spawn.is_boss else Color(0.88, 0.78, 1.0, 0.88)
		var vis = get_tree().get_first_node_in_group("game_visual_registry")
		if vis and vis.spawn_marker_textures_enabled:
			var tex: Texture2D = vis.get_spawn_texture(spawn.is_boss)
			if tex != null:
				if vis.has_method("apply_to_sprite3d"):
					vis.apply_to_sprite3d(marker, tex, marker.modulate, marker.pixel_size)
				else:
					marker.texture = tex
		elif _marker_material:
			var mat: StandardMaterial3D = _marker_material.duplicate()
			marker.material_override = mat
		anchor.add_child(marker)

		var col_x := float(spawn.world_pos.x) + 0.5
		var col_z := float(spawn.world_pos.y) + 0.5
		var walkable := TerrainRamps.walkable_height(world, col_x, col_z) if world else _terrain_at(spawn.world_pos)
		anchor.position = _WorldVisualCoords.column_to_world_pos(
			col_x,
			walkable + marker_size * 0.5 + 0.12,
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
	return _crystal_floor_at(key) + depth


func get_walkable_height(wx: float, wz: float) -> float:
	var ramp_entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		ramp_entry = chunk_manager.get_ramp_entry_at_world(wx, wz)
	var base := TerrainRamps.walkable_height_from_entry(world, wx, wz, ramp_entry) if world else 1.0
	var depth := get_depth_at(floori(wx), floori(wz))
	if depth >= sim_config.min_depth:
		return maxf(base, _crystal_floor_at(Vector2i(floori(wx), floori(wz))) + depth + 0.05)
	return base


func get_active_spawns() -> Array[CrystalSpawnPoint]:
	if _spawn_ctrl:
		return _spawn_ctrl.get_active_spawns()
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
	if _tick_trace_active:
		_tick_trace["clear_tile_calls"] = int(_tick_trace.get("clear_tile_calls", 0)) + 1
		_tick_trace["clear_feature_calls"] = int(_tick_trace.get("clear_feature_calls", 0)) + 1
	# Batch tile+feature clears so SpatialQuery sees one WorldState.changed, not two.
	var ws = _WorldState.get_active() if _WorldState else null
	if ws and ws.has_method("begin_batch"):
		ws.begin_batch()
	_FeatureRegistry.clear_tile_override(pos.x, pos.y)
	_FeatureRegistry.clear_feature(pos.x, pos.y)
	if ws and ws.has_method("end_batch"):
		ws.end_batch()
	_add_power(_absorption_power_boost(tile_id))
	var source_id := _absorption_source_for(tile_id, feat)
	if evolution:
		var unlock: Dictionary = evolution.record_absorption(source_id)
		if unlock.has("bonus_power"):
			_add_power(float(unlock.bonus_power))
		# enemy_unlocked signal grants relic via _on_enemy_unlocked_grant_relic
	absorption_completed.emit(source_id, pos)
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(pos.x, pos.y)
	# Defer mesh rebuild — immediate rebuild_chunk_at_world was the dominant hitch
	# when many absorptions drained in one frame (or even a single dense rebuild).
	_pending_absorption_rebuilds[pos] = true
	if _tick_trace_active:
		_tick_trace["rebuild_chunk_calls"] = int(_tick_trace.get("rebuild_chunk_calls", 0)) + 1


func _drain_one_absorption_rebuild() -> void:
	if _pending_absorption_rebuilds.is_empty():
		return
	if chunk_manager == null or not chunk_manager.has_method("rebuild_chunk_at_world"):
		_pending_absorption_rebuilds.clear()
		return
	# One world cell rebuild per frame (chunk-level rebuild is the heavy part).
	var pos: Vector2i = _pending_absorption_rebuilds.keys()[0]
	_pending_absorption_rebuilds.erase(pos)
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
	var ws = _WorldState.get_active() if _WorldState else null
	if ws and ws.has_method("begin_batch"):
		ws.begin_batch()
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			if Vector2(dx, dz).length() > 5.0:
				continue
			var wx := center.x + dx
			var wz := center.y + dz
			_FeatureRegistry.clear_tile_override(wx, wz)
			_FeatureRegistry.clear_feature(wx, wz)
	if ws and ws.has_method("end_batch"):
		ws.end_batch()
	if world and world.has_method("invalidate_column_cache"):
		world.invalidate_column_cache(center.x, center.y)
	_pending_absorption_rebuilds[center] = true


func get_coverage_ratio() -> float:
	var playable_cells: float = float(_WorldBorder.PLAYABLE_HALF_X * 2 * _WorldBorder.PLAYABLE_HALF_Z * 2)
	if playable_cells <= 1.0:
		return 0.0
	return float(covered_cells) / playable_cells


func export_state() -> Dictionary:
	# Ensure deferred presentation/gameplay events are applied before snapshot export.
	flush_dispatch_queue()
	var depth_rows: Array = []
	if _simulation:
		depth_rows = _simulation.export_depth_rows()
	elif _sim:
		for pos_variant in _sim.depth.keys():
			var pos: Vector2i = pos_variant
			depth_rows.append([
				pos.x, pos.y,
				float(_sim.depth[pos]),
				int(_sim.spawn_id_by_cell.get(pos, -1)),
			])
	var spawn_rows: Array = _spawn_ctrl.export_spawn_rows()
	var absorption_rows: Array = []
	var abs_map: Dictionary = _simulation.absorption if _simulation else _absorption
	for pos_variant in abs_map.keys():
		var pos: Vector2i = pos_variant
		absorption_rows.append([pos.x, pos.y, float(abs_map[pos])])
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

	if _simulation:
		_simulation.clear()
		_simulation.import_depth_rows(data.get("depth", []))
		_sim = _simulation.fluid
		if _presentation:
			_presentation.fluid = _sim
	else:
		_sim.clear()
		for row in data.get("depth", []):
			if row is Array and row.size() >= 3:
				var pos := Vector2i(int(row[0]), int(row[1]))
				var spawn_id: int = int(row[3]) if row.size() >= 4 else -1
				_sim.set_depth(pos, float(row[2]), spawn_id)

	_absorption.clear()
	if _simulation:
		_simulation.absorption.clear()
	for row in data.get("absorption_progress", []):
		if row is Array and row.size() >= 3:
			var p := Vector2i(int(row[0]), int(row[1]))
			var v := float(row[2])
			_absorption[p] = v
			if _simulation:
				_simulation.absorption[p] = v

	if evolution:
		var evo: Dictionary = data.get("evolution", {})
		evolution.absorbed_counts.clear()
		for key in evo.get("absorbed", {}).keys():
			evolution.absorbed_counts[StringName(str(key))] = int(evo.absorbed[key])
		evolution.unlocked_enemies.clear()
		for entry in evo.get("unlocked_enemies", []):
			evolution.unlocked_enemies.append(StringName(str(entry)))

	# Only replace spawn points when the save explicitly carries a spawns list.
	# Missing key must not wipe live win targets (empty {} import used to clear all).
	if data.has("spawns"):
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
	if _presentation:
		_presentation.fluid = _sim
		_presentation.mark_all_indexed_dirty()
	else:
		_rebuild_cell_index()
	refresh_spawn_marker_textures()
	_flush_dirty_chunks()
	_log_spawn_status("restored")


func get_spawn_marker(spawn_id: int) -> Node3D:
	var anchor: Node3D = _spawn_markers.get(spawn_id) as Node3D
	if anchor == null:
		return null
	var sprite: Node3D = anchor.get_node_or_null("Sprite") as Node3D
	if sprite != null:
		return sprite
	return anchor.get_node_or_null("Mesh") as Node3D


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
