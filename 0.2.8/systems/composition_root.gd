class_name CompositionRoot
extends Node
## Single authoritative boot / service wiring authority for production main scene.
## Stages are one-way. Critical peers are resolved via ServiceRegistry, not groups.
## Groups may still exist as discovery adapters for UI/debug.

const _ServiceRegistry = preload("res://systems/service_registry.gd")
const _RuntimeConfigResolver = preload("res://systems/runtime_config_resolver.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _StartupProfiler = preload("res://systems/startup_profiler.gd")
const _StartupTotal = preload("res://systems/startup_total_profiler.gd")

signal stage_changed(stage: int, name: String)
signal boot_failed(reason: String, dump: Dictionary)
signal boot_completed()

enum Stage {
	UNINITIALIZED = 0,
	CONFIGURED = 1,
	QUALITY_APPLIED = 2,
	FEATURES_SEEDED = 3,
	CHUNKS_CREATED = 4,
	INITIAL_STREAM_READY = 5,
	VISUALS_COMMITTED = 6,
	RUNNING = 7,
	SHUTTING_DOWN = 8,
	FAILED = 9,
}

const STAGE_NAMES := {
	Stage.UNINITIALIZED: "UNINITIALIZED",
	Stage.CONFIGURED: "CONFIGURED",
	Stage.QUALITY_APPLIED: "QUALITY_APPLIED",
	Stage.FEATURES_SEEDED: "FEATURES_SEEDED",
	Stage.CHUNKS_CREATED: "CHUNKS_CREATED",
	Stage.INITIAL_STREAM_READY: "INITIAL_STREAM_READY",
	Stage.VISUALS_COMMITTED: "VISUALS_COMMITTED",
	Stage.RUNNING: "RUNNING",
	Stage.SHUTTING_DOWN: "SHUTTING_DOWN",
	Stage.FAILED: "FAILED",
}

const ID_CONFIG := &"config_service"
const ID_PERF := &"performance_service"
const ID_VISUAL_REG := &"game_visual_registry"
const ID_WORLD := &"world"
const ID_FEATURES := &"world_features"
const ID_VOXEL := &"voxel_world"
const ID_CHUNKS := &"chunk_manager"
const ID_CRYSTAL := &"crystal_manager"
const ID_SAVE := &"save_game_service"
const ID_TERRAIN := &"terrain_editor"
const ID_PLAYER := &"player"
const ID_WORLD_VISUALS := &"world_visuals"
const ID_ENTITY := &"entity_manager"
const ID_COMBAT_VFX := &"combat_visual_feedback"
const ID_GAME_MANAGER := &"game_manager"
const ID_SPATIAL := &"spatial_query_service"

static var _active = null

var registry = null
var stage: int = Stage.UNINITIALIZED
var resolved_config: Dictionary = {}
var _stage_times_ms: Dictionary = {}  # stage name -> ms to reach
var _boot_started_ms: int = 0
var _boot_done: bool = false
var _failed_reason: String = ""
var _debug_overrides: Dictionary = {}
var _platform_overrides: Dictionary = {}
var _default_stage_timeout_frames: int = 1800
## Boot stage dwell instrumentation (measurement only — no gameplay effect).
## Each closed stage: start_ms, end_ms, duration_ms, ops[], slowest_op, slowest_ms.
var _boot_trace_enabled: bool = true
var _boot_trace_stages: Array = []  # closed stage dicts
var _boot_trace_current_name: String = ""
var _boot_trace_current_start_ms: int = 0
var _boot_trace_ops: Array = []  # {name, start_ms, end_ms, duration_ms}
var _boot_trace_op_stack: Array = []  # open op names
var _boot_trace_op_start_ms: Dictionary = {}


static func get_active():
	return _active


func _enter_tree() -> void:
	_active = self
	add_to_group("composition_root")
	if registry == null:
		registry = _ServiceRegistry.new()


func _exit_tree() -> void:
	if _active == self:
		_active = null


func set_debug_overrides(overrides: Dictionary) -> void:
	_debug_overrides = overrides.duplicate(true)


func set_platform_overrides(overrides: Dictionary) -> void:
	_platform_overrides = overrides.duplicate(true)


func get_stage_name(s: int = -1) -> String:
	if s < 0:
		s = stage
	return str(STAGE_NAMES.get(s, "UNKNOWN_%d" % s))


func is_at_least(s: int) -> bool:
	if stage == Stage.FAILED:
		return false
	return stage >= s


## Main production boot entry. Call from main.gd after children enter tree.
func boot_async() -> bool:
	_boot_started_ms = Time.get_ticks_msec()
	_boot_done = false
	_failed_reason = ""
	_boot_trace_reset()
	# Always collect StartupProfiler samples during boot for stage op attribution.
	_StartupProfiler.begin_session()
	if _StartupTotal.is_enabled() and _StartupTotal.now_us() <= 0:
		_StartupTotal.begin_session("composition_root")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("composition_root.boot_async", "synchronous_main")
		_StartupTotal.event("composition_root.boot_async.enter", {}, "composition_root")
	if registry == null:
		registry = _ServiceRegistry.new()

	# --- Discover scene-owned services once by relative path (not groups) ---
	var game := get_parent()
	if game == null:
		return _fail("composition_root has no parent Game node")

	_trace_op_begin("scene_service_registration")
	_StartupProfiler.begin("scene_service_registration")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("scene_service_registration", "synchronous_main")
	_register_scene_services(game)
	if _StartupTotal.is_enabled():
		_StartupTotal.end("scene_service_registration")
	_StartupProfiler.end("scene_service_registration")
	_trace_op_end("scene_service_registration")

	# --- CONFIGURED ---
	_trace_op_begin("load_config")
	_StartupProfiler.begin("load_config")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("load_config", "resource_loading")
	var cfg = registry.require(ID_CONFIG)
	if cfg == null:
		return _fail("missing config_service")
	# ConfigService._ready may already have run; ensure defaults applied.
	if cfg.has_method("ensure_ready_sync"):
		_trace_op_begin("ConfigService.ensure_ready_sync")
		cfg.ensure_ready_sync()
		_trace_op_end("ConfigService.ensure_ready_sync")
	# Authored config fan-out via registry (not group search).
	if cfg.has_method("apply_to_registered"):
		_trace_op_begin("ConfigService.apply_to_registered(initial)")
		cfg.apply_to_registered(registry, {})
		_trace_op_end("ConfigService.apply_to_registered(initial)")
	if _StartupTotal.is_enabled():
		_StartupTotal.end("load_config")
	_StartupProfiler.end("load_config")
	_trace_op_end("load_config")
	_advance(Stage.CONFIGURED)

	# --- QUALITY + resolved config ---
	_trace_op_begin("quality_and_perf_policy")
	_StartupProfiler.begin("quality_and_perf_policy")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("quality_and_perf_policy", "synchronous_main")
	var perf = registry.require(ID_PERF)
	if perf == null:
		return _fail("missing performance_service")
	# Env preset wins over leftover player_settings.json (quality + native distance).
	if perf.has_method("apply_env_preset_if_set"):
		perf.apply_env_preset_if_set()
	# Ensure quality resource selected (env/preset may already have set quality).
	if not bool(perf.get("_applied")) if "_applied" in perf else true:
		if perf.has_method("ensure_ready"):
			_trace_op_begin("PerformanceService.ensure_ready(wait__applied)")
			var frames := 0
			while not bool(perf.get("_applied")) and frames < _default_stage_timeout_frames:
				await get_tree().process_frame
				frames += 1
			_trace_op_end("PerformanceService.ensure_ready(wait__applied)")
			if not bool(perf.get("_applied")):
				return _fail("performance_service quality not applied (timeout)")
	_trace_op_begin("RuntimeConfigResolver._rebuild_resolved_config")
	_rebuild_resolved_config(cfg, perf)
	_trace_op_end("RuntimeConfigResolver._rebuild_resolved_config")
	# Re-push authored config with resolved vegetation multipliers etc.
	if cfg.has_method("apply_to_registered"):
		_trace_op_begin("ConfigService.apply_to_registered(resolved)")
		cfg.apply_to_registered(registry, resolved_config)
		_trace_op_end("ConfigService.apply_to_registered(resolved)")
	# Apply *effective* policy (quality folded with platform/debug) via registry.
	if perf.has_method("apply_to_registered"):
		_trace_op_begin("PerformanceService.apply_to_registered")
		perf.apply_to_registered(registry, resolved_config)
		_trace_op_end("PerformanceService.apply_to_registered")
	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	var _PlayerSettings = load("res://systems/player_settings.gd")
	if _PlayerSettings and env_preset.is_empty():
		_PlayerSettings.apply_to_performance(perf)
		_rebuild_resolved_config(cfg, perf)
		if resolved_config.has("policy") and resolved_config.policy is Dictionary:
			_PlayerSettings.write_policy(resolved_config.policy)
		if perf.has_method("apply_to_registered"):
			perf.apply_to_registered(registry, resolved_config)
	if _StartupTotal.is_enabled():
		_StartupTotal.end("quality_and_perf_policy")
	_StartupProfiler.end("quality_and_perf_policy")
	_trace_op_end("quality_and_perf_policy")
	_advance(Stage.QUALITY_APPLIED)

	# --- FEATURES (textures only first — must not wait for chunks) ---
	# Loading UI still shows QUALITY_APPLIED until FEATURES_SEEDED advances.
	var features = registry.require(ID_FEATURES)
	var visreg = registry.resolve(ID_VISUAL_REG)
	_trace_op_begin("GameVisualRegistry.ensure_textures_ready")
	_StartupProfiler.begin("shader_material_and_textures")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("shader_material_and_textures", "resource_loading")
	if visreg and visreg.has_method("ensure_textures_ready"):
		await visreg.ensure_textures_ready()
	elif visreg and visreg.has_method("ensure_ready"):
		await visreg.ensure_ready()
	if _StartupTotal.is_enabled():
		_StartupTotal.end("shader_material_and_textures")
	_StartupProfiler.end("shader_material_and_textures")
	_trace_op_end("GameVisualRegistry.ensure_textures_ready")

	_trace_op_begin("WorldFeatures.bootstrap_with_services")
	_StartupProfiler.begin("feature_seeding")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("feature_seeding", "feature_generation")
	if features and features.has_method("bootstrap_with_services"):
		await features.bootstrap_with_services(registry, resolved_config)
	elif features and features.has_method("ensure_ready"):
		await features.ensure_ready()
	if features == null or not bool(features.get("bootstrap_complete")):
		# Wait for features seed if still async
		_trace_op_begin("WorldFeatures.wait_bootstrap_complete")
		var fframes := 0
		while features and not bool(features.get("bootstrap_complete")) and fframes < _default_stage_timeout_frames:
			await get_tree().process_frame
			fframes += 1
		_trace_op_end("WorldFeatures.wait_bootstrap_complete")
		if features and not bool(features.get("bootstrap_complete")):
			return _fail("world_features bootstrap timeout")
	if _StartupTotal.is_enabled():
		_StartupTotal.end("feature_seeding")
	_StartupProfiler.end("feature_seeding")
	_trace_op_end("WorldFeatures.bootstrap_with_services")
	_advance(Stage.FEATURES_SEEDED)

	# --- CHUNKS (includes bake index load + mesh plan bind + first stream request) ---
	_trace_op_begin("VoxelWorld.create_chunk_manager_with_services")
	_StartupProfiler.begin("world_and_chunk_manager_init")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("world_and_chunk_manager_init", "bake_package_loading")
	var voxel = registry.require(ID_VOXEL)
	if voxel == null:
		return _fail("missing voxel_world")
	var cm = null
	if voxel.has_method("create_chunk_manager_with_services"):
		cm = await voxel.create_chunk_manager_with_services(registry)
	else:
		# Fallback: wait for manager property
		var cframes := 0
		while (voxel.get("manager") == null) and cframes < _default_stage_timeout_frames:
			await get_tree().process_frame
			cframes += 1
		cm = voxel.get("manager")
	if cm == null:
		return _fail("chunk_manager not created")
	registry.register(ID_CHUNKS, cm, [ID_WORLD, ID_FEATURES, ID_CONFIG, ID_PERF])
	if _StartupTotal.is_enabled():
		_StartupTotal.end("world_and_chunk_manager_init")
	_StartupProfiler.end("world_and_chunk_manager_init")
	_trace_op_end("VoxelWorld.create_chunk_manager_with_services")

	# Explicit handoff fan-out (replaces group lookups in on_chunk_manager_ready)
	_trace_op_begin("service_handoff_on_chunks")
	_StartupProfiler.begin("service_handoff_on_chunks")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("service_handoff_on_chunks", "synchronous_main")
	_on_chunk_manager_ready_explicit(cm)
	if _StartupTotal.is_enabled():
		_StartupTotal.end("service_handoff_on_chunks")
	_StartupProfiler.end("service_handoff_on_chunks")
	_trace_op_end("service_handoff_on_chunks")
	_advance(Stage.CHUNKS_CREATED)

	# --- INITIAL STREAM (first chunk(s) load + mesh upload drain window) ---
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP:
		SPP.begin_session()
		SPP.begin_window("initial_chunk_stream")
	_trace_op_begin("initial_chunk_stream_wait")
	_StartupProfiler.begin("initial_chunk_stream")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("initial_chunk_stream", "waiting_on_workers")
	var sframes := 0
	var wait_us_acc := 0
	var _GameplayInput = load("res://helpers/gameplay_input.gd")
	if _GameplayInput and _GameplayInput.has_method("set_world_loading"):
		_GameplayInput.set_world_loading(true)
	# Required start ring must be resident — one streamed chunk is not playable.
	while sframes < _default_stage_timeout_frames:
		var start_ready := false
		if cm.has_method("is_start_region_ready"):
			start_ready = bool(cm.is_start_region_ready())
		elif cm.chunks != null and cm.chunks.size() >= 1:
			start_ready = true
		if start_ready:
			break
		var tw := Time.get_ticks_usec()
		await get_tree().process_frame
		wait_us_acc += Time.get_ticks_usec() - tw
		sframes += 1
	if cm.has_method("is_start_region_ready") and not bool(cm.is_start_region_ready()):
		return _fail("start region not ready after %d frames" % sframes)
	if SPP and SPP.is_enabled():
		SPP.record("process_frame_wait", wait_us_acc)
	if _StartupTotal.is_enabled():
		_StartupTotal.end("initial_chunk_stream", {
			"frames_waited": sframes,
			"chunks_ready": cm.chunks.size() if cm.chunks != null else 0,
		})
	_StartupProfiler.end("initial_chunk_stream")
	_trace_op_end("initial_chunk_stream_wait")
	if SPP and SPP.is_enabled():
		SPP.end_window("initial_chunk_stream")
		print("ICS_FRAMES_WAITED %d chunks_ready=%d" % [
			sframes,
			cm.chunks.size() if cm.chunks != null else 0,
		])
		SPP.print_report()
		var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
		if scratch.is_empty():
			scratch = "/tmp/grok-goal-3c89103bbbb9/implementer"
		var spath := scratch.path_join("stream_phase_profile.json")
		var sf := FileAccess.open(spath, FileAccess.WRITE)
		if sf:
			var rep: Dictionary = SPP.report()
			rep["ics_frames_waited"] = sframes
			rep["chunks_ready_at_ics_end"] = cm.chunks.size() if cm.chunks != null else 0
			sf.store_string(JSON.stringify(rep, "\t"))
			sf.close()
			print("WROTE %s" % spath)
	if _StartupTotal.is_enabled():
		_StartupTotal.mark_playable("CompositionRoot.INITIAL_STREAM_READY (start region resident)")
	_advance(Stage.INITIAL_STREAM_READY)
	if get_tree() and get_tree().get_first_node_in_group("loading_screen") == null:
		var _GI = load("res://helpers/gameplay_input.gd")
		if _GI and _GI.has_method("set_world_loading"):
			_GI.set_world_loading(false)

	# --- VISUALS ---
	_trace_op_begin("visuals_commit/post_bootstrap_refresh")
	_StartupProfiler.begin("visuals_commit")
	if _StartupTotal.is_enabled():
		_StartupTotal.begin("visuals_commit", "synchronous_main")
	var world_visuals = registry.resolve(ID_WORLD_VISUALS)
	if world_visuals and world_visuals.has_method("post_bootstrap_refresh"):
		await world_visuals.post_bootstrap_refresh()
	elif visreg and visreg.has_method("post_bootstrap_refresh"):
		await visreg.post_bootstrap_refresh()
	if _StartupTotal.is_enabled():
		_StartupTotal.end("visuals_commit")
	_StartupProfiler.end("visuals_commit")
	_trace_op_end("visuals_commit/post_bootstrap_refresh")
	_advance(Stage.VISUALS_COMMITTED)

	_trace_op_begin("first_frame_after_running")
	_StartupProfiler.begin("first_frame_after_running")
	_advance(Stage.RUNNING)
	await get_tree().process_frame
	_StartupProfiler.end("first_frame_after_running")
	_trace_op_end("first_frame_after_running")
	_boot_done = true
	_close_stage_trace("RUNNING")
	if _StartupTotal.is_enabled():
		_StartupTotal.end("composition_root.boot_async")
		_StartupTotal.event("composition_root.RUNNING", {"elapsed_ms": Time.get_ticks_msec() - _boot_started_ms}, "first_playable_frame")
	_print_boot_stage_trace_report()
	if _StartupProfiler.is_enabled():
		_StartupProfiler.print_report()
		var scratch2 := OS.get_environment("CRYSTALSTORM_SCRATCH")
		var path := "user://startup_profile.json"
		if not scratch2.is_empty():
			path = scratch2.path_join("startup_profile.json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(_StartupProfiler.to_json_string())
			f.close()
			print("WROTE %s" % path)
	boot_completed.emit()
	return true


func _register_scene_services(game: Node) -> void:
	_try_register(game, "ConfigService", ID_CONFIG, [])
	_try_register(game, "PerformanceService", ID_PERF, [ID_CONFIG])
	_try_register(game, "GameVisualRegistry", ID_VISUAL_REG, [ID_PERF])
	_try_register(game, "SpatialQueryService", ID_SPATIAL, [])
	_try_register(game, "World", ID_WORLD, [ID_CONFIG])
	_try_register(game, "WorldFeatures", ID_FEATURES, [ID_CONFIG, ID_PERF, ID_VISUAL_REG, ID_WORLD])
	_try_register(game, "VoxelWorld", ID_VOXEL, [ID_FEATURES, ID_WORLD])
	_try_register(game, "CrystalManager", ID_CRYSTAL, [ID_CONFIG, ID_WORLD, ID_CHUNKS])
	_try_register(game, "SaveGameService", ID_SAVE, [ID_CONFIG, ID_WORLD, ID_CRYSTAL])
	_try_register(game, "TerrainEditor", ID_TERRAIN, [ID_WORLD, ID_CONFIG])
	_try_register(game, "Player", ID_PLAYER, [ID_WORLD, ID_CHUNKS])
	_try_register(game, "WorldVisuals", ID_WORLD_VISUALS, [ID_VISUAL_REG, ID_CHUNKS])
	_try_register(game, "GameManager", ID_GAME_MANAGER, [ID_CONFIG, ID_CRYSTAL])
	# Nested under WorldFeatures
	var features_node = game.get_node_or_null("WorldFeatures")
	if features_node:
		var em = features_node.get_node_or_null("EntityManager")
		if em:
			registry.register(ID_ENTITY, em, [ID_FEATURES, ID_CHUNKS, ID_WORLD, ID_SPATIAL])
	var combat = game.get_node_or_null("WorldVisuals/CombatVFX/CombatVisualFeedback")
	if combat:
		registry.register(ID_COMBAT_VFX, combat, [ID_VISUAL_REG])


func _try_register(game: Node, path: String, id: StringName, deps: Array) -> void:
	var n = game.get_node_or_null(path)
	if n:
		registry.register(id, n, deps)


func _rebuild_resolved_config(cfg, perf) -> void:
	var quality = perf.quality if perf and "quality" in perf else null
	var project_cfg = cfg.game_config if cfg and "game_config" in cfg else null
	resolved_config = _RuntimeConfigResolver.resolve(
		null,
		project_cfg,
		quality,
		_platform_overrides,
		_debug_overrides
	)


func _on_chunk_manager_ready_explicit(cm) -> void:
	var cfg = registry.resolve(ID_CONFIG)
	if cfg and cfg.has_method("on_chunk_manager_ready"):
		cfg.on_chunk_manager_ready(cm)
	# Also registry-push world_gen / sim after chunk exists.
	if cfg and cfg.has_method("apply_to_registered"):
		cfg.apply_to_registered(registry, resolved_config)
	var terrain = registry.resolve(ID_TERRAIN)
	if terrain and terrain.has_method("bind_chunk_manager"):
		terrain.bind_chunk_manager(cm)
	var spatial = registry.resolve(ID_SPATIAL)
	if spatial and spatial.has_method("bind_chunk_manager"):
		spatial.bind_chunk_manager(cm)
	var entity = registry.resolve(ID_ENTITY)
	if entity and entity.has_method("on_chunk_manager_ready"):
		entity.on_chunk_manager_ready(cm)
	if spatial and entity and spatial.has_method("bind_entity_manager"):
		spatial.bind_entity_manager(entity)
	var crystal = registry.resolve(ID_CRYSTAL)
	if spatial and crystal and spatial.has_method("bind_crystal_manager"):
		spatial.bind_crystal_manager(crystal)
	# WorldState active session (if available)
	if spatial and spatial.has_method("bind_world_state"):
		var WS = load("res://world/world_state.gd")
		var ws = WS.get_active() if WS and WS.has_method("get_active") else null
		if ws:
			spatial.bind_world_state(ws)
	var visreg = registry.resolve(ID_VISUAL_REG)
	if visreg and visreg.has_method("on_chunk_manager_ready"):
		visreg.on_chunk_manager_ready(cm)
	var world_visuals = registry.resolve(ID_WORLD_VISUALS)
	if world_visuals and world_visuals.has_method("on_chunk_manager_ready"):
		world_visuals.on_chunk_manager_ready(cm)
	var combat = registry.resolve(ID_COMBAT_VFX)
	if combat and combat.has_method("on_chunk_manager_ready"):
		combat.on_chunk_manager_ready(cm)
	var perf = registry.resolve(ID_PERF)
	# Effective policy (not raw quality) must reach ChunkManager.
	if perf and perf.has_method("reapply_to_chunk_manager"):
		perf.reapply_to_chunk_manager(cm, resolved_config)
	elif perf and perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, resolved_config)
	var world = registry.resolve(ID_WORLD)
	if world and world.has_method("set_caves_enabled"):
		var caves: bool = bool(_RuntimeConfigResolver.policy_get(resolved_config, "caves_enabled", false))
		world.set_caves_enabled(caves)


func _advance(next_stage: int) -> void:
	if stage == Stage.FAILED:
		return
	if next_stage < stage and next_stage != Stage.SHUTTING_DOWN and next_stage != Stage.FAILED:
		push_warning("CompositionRoot: non-forward stage %s -> %s" % [get_stage_name(), get_stage_name(next_stage)])
	# Close dwell for previous label (ops since last advance / PRE_CONFIGURED).
	if not _boot_trace_current_name.is_empty():
		_close_stage_trace(_boot_trace_current_name)
	stage = next_stage
	var name := get_stage_name()
	_stage_times_ms[name] = Time.get_ticks_msec() - _boot_started_ms
	_open_stage_trace(name)
	stage_changed.emit(stage, name)
	print("[CompositionRoot] stage=%s t=%dms" % [name, int(_stage_times_ms[name])])
	if _StartupTotal.is_enabled():
		_StartupTotal.event("stage:" + name, {"elapsed_ms": int(_stage_times_ms[name])}, "composition_root")


func _fail(reason: String) -> bool:
	_failed_reason = reason
	stage = Stage.FAILED
	_close_stage_trace("FAILED")
	_print_boot_stage_trace_report()
	var dump := get_diagnostics()
	boot_failed.emit(reason, dump)
	push_error("[CompositionRoot] BOOT FAILED: %s" % reason)
	print(JSON.stringify(dump, "\t"))
	return false


func _boot_trace_reset() -> void:
	_boot_trace_stages.clear()
	_boot_trace_current_name = "PRE_CONFIGURED"
	_boot_trace_current_start_ms = Time.get_ticks_msec()
	_boot_trace_ops.clear()
	_boot_trace_op_stack.clear()
	_boot_trace_op_start_ms.clear()


func _open_stage_trace(stage_name: String) -> void:
	if not _boot_trace_enabled:
		return
	_boot_trace_current_name = stage_name
	_boot_trace_current_start_ms = Time.get_ticks_msec()
	_boot_trace_ops.clear()


func _close_stage_trace(stage_name: String) -> void:
	if not _boot_trace_enabled:
		return
	# Flush any open ops.
	while not _boot_trace_op_stack.is_empty():
		_trace_op_end(str(_boot_trace_op_stack[_boot_trace_op_stack.size() - 1]))
	var end_ms: int = Time.get_ticks_msec()
	var start_ms: int = _boot_trace_current_start_ms
	var dur: int = maxi(end_ms - start_ms, 0)
	var slowest_name := ""
	var slowest_ms: float = 0.0
	var ops_out: Array = []
	for op_v in _boot_trace_ops:
		var op: Dictionary = op_v
		ops_out.append(op.duplicate())
		var dms: float = float(op.get("duration_ms", 0.0))
		if dms >= slowest_ms:
			slowest_ms = dms
			slowest_name = str(op.get("name", ""))
	var entry := {
		"stage": stage_name,
		"start_ms": start_ms - _boot_started_ms if _boot_started_ms > 0 else start_ms,
		"end_ms": end_ms - _boot_started_ms if _boot_started_ms > 0 else end_ms,
		"duration_ms": dur,
		"ops": ops_out,
		"slowest_op": slowest_name,
		"slowest_ms": slowest_ms,
	}
	_boot_trace_stages.append(entry)
	_boot_trace_ops.clear()


func _trace_op_begin(op_name: String) -> void:
	if not _boot_trace_enabled:
		return
	_boot_trace_op_stack.append(op_name)
	_boot_trace_op_start_ms[op_name] = Time.get_ticks_msec()
	print("[BootTrace] START %-52s @+%dms" % [
		op_name,
		Time.get_ticks_msec() - _boot_started_ms if _boot_started_ms > 0 else 0,
	])


func _trace_op_end(op_name: String) -> void:
	if not _boot_trace_enabled:
		return
	if not _boot_trace_op_start_ms.has(op_name):
		return
	var start_ms: int = int(_boot_trace_op_start_ms[op_name])
	_boot_trace_op_start_ms.erase(op_name)
	if _boot_trace_op_stack.size() > 0 and str(_boot_trace_op_stack[_boot_trace_op_stack.size() - 1]) == op_name:
		_boot_trace_op_stack.pop_back()
	else:
		# Remove nested/mismatched by name
		var idx: int = _boot_trace_op_stack.rfind(op_name)
		if idx >= 0:
			_boot_trace_op_stack.remove_at(idx)
	var end_ms: int = Time.get_ticks_msec()
	var dur: float = float(end_ms - start_ms)
	var op := {
		"name": op_name,
		"start_ms": start_ms - _boot_started_ms if _boot_started_ms > 0 else start_ms,
		"end_ms": end_ms - _boot_started_ms if _boot_started_ms > 0 else end_ms,
		"duration_ms": dur,
	}
	_boot_trace_ops.append(op)
	print("[BootTrace] END   %-52s duration=%.1fms  stage=%s" % [
		op_name, dur, _boot_trace_current_name,
	])


func get_boot_stage_trace() -> Array:
	return _boot_trace_stages.duplicate(true)


func _print_boot_stage_trace_report() -> void:
	if not _boot_trace_enabled:
		return
	# Include StartupProfiler sub-ops under feature seeding for the gap report.
	var sp_report: Dictionary = {}
	if _StartupProfiler.is_enabled():
		sp_report = _StartupProfiler.report()
	print("")
	print("========== BOOT STAGE TRACE (ranked by dwell duration) ==========")
	print("Times are wall-clock while each stage label is active (until next _advance).")
	print("Loading UI freezes at QUALITY_APPLIED while ops in that dwell run.")
	print("")
	var ranked: Array = _boot_trace_stages.duplicate()
	ranked.sort_custom(func(a, b): return float(a.get("duration_ms", 0)) > float(b.get("duration_ms", 0)))
	print("| rank | stage                      | start_ms | end_ms | duration_ms | slowest_op | slowest_ms |")
	print("|-----:|:---------------------------|--------:|------:|------------:|:-----------|----------:|")
	var rank := 1
	for e in ranked:
		print("| %4d | %-27s | %8d | %6d | %11d | %-40s | %10.1f |" % [
			rank,
			str(e.get("stage", "")),
			int(e.get("start_ms", 0)),
			int(e.get("end_ms", 0)),
			int(e.get("duration_ms", 0)),
			str(e.get("slowest_op", "")).substr(0, 40),
			float(e.get("slowest_ms", 0.0)),
		])
		rank += 1
	print("")
	# Detail each stage in boot order
	print("--- Stage detail (boot order) ---")
	for e in _boot_trace_stages:
		print("")
		print("### %s  dwell=%dms  [%d → %d ms from boot]" % [
			str(e.get("stage", "")),
			int(e.get("duration_ms", 0)),
			int(e.get("start_ms", 0)),
			int(e.get("end_ms", 0)),
		])
		print("    slowest: %s (%.1f ms)" % [str(e.get("slowest_op", "")), float(e.get("slowest_ms", 0.0))])
		var ops: Array = e.get("ops", [])
		if ops.is_empty():
			print("    (no traced ops)")
			continue
		var ops_sorted: Array = ops.duplicate()
		ops_sorted.sort_custom(func(a, b): return float(a.get("duration_ms", 0)) > float(b.get("duration_ms", 0)))
		for op in ops_sorted:
			print("    - %-52s %8.1f ms  (start +%d)" % [
				str(op.get("name", "")),
				float(op.get("duration_ms", 0.0)),
				int(op.get("start_ms", 0)),
			])
	# Explicit QUALITY → FEATURES gap analysis
	print("")
	print("--- QUALITY_APPLIED → FEATURES_SEEDED gap analysis ---")
	var qa: Dictionary = {}
	for e in _boot_trace_stages:
		if str(e.get("stage", "")) == "QUALITY_APPLIED":
			qa = e
			break
	if qa.is_empty():
		print("QUALITY_APPLIED dwell not recorded.")
	else:
		print("While loading UI shows 'Applying Graphics Settings' (QUALITY_APPLIED):")
		print("  dwell_ms = %d" % int(qa.get("duration_ms", 0)))
		print("  slowest  = %s (%.1f ms)" % [str(qa.get("slowest_op", "")), float(qa.get("slowest_ms", 0.0))])
		var ops2: Array = qa.get("ops", [])
		var sum_ops: float = 0.0
		for op in ops2:
			sum_ops += float(op.get("duration_ms", 0.0))
		print("  sum(traced ops) = %.1f ms  residual(dwell - sum) = %.1f ms" % [
			sum_ops, float(qa.get("duration_ms", 0)) - sum_ops,
		])
	# StartupProfiler nested samples (feature seed internals)
	if not sp_report.is_empty():
		print("")
		print("--- StartupProfiler samples (includes WorldFeatures sub-ops) ---")
		var stages_sp: Array = sp_report.get("stages", [])
		stages_sp = stages_sp.duplicate()
		stages_sp.sort_custom(func(a, b): return float(a.get("total_us", 0)) > float(b.get("total_us", 0)))
		print("| rank | sample | total_ms | worst_ms | n |")
		print("|-----:|:-------|---------:|---------:|--:|")
		var r2 := 1
		for st in stages_sp:
			var tot_us: float = float(st.get("total_us", 0))
			if tot_us < 500.0:
				continue
			print("| %4d | %-40s | %8.1f | %8.1f | %2d |" % [
				r2,
				str(st.get("stage", "")),
				tot_us / 1000.0,
				float(st.get("worst_us", 0)) / 1000.0,
				int(st.get("n", 0)),
			])
			r2 += 1
			if r2 > 25:
				break
	print("")
	print("========== END BOOT STAGE TRACE ==========")
	print("")
	# Persist JSON for offline analysis
	var out_path := "user://boot_stage_trace.json"
	var scratch3 := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if not scratch3.is_empty():
		out_path = scratch3.path_join("boot_stage_trace.json")
	var payload := {
		"stages": _boot_trace_stages,
		"startup_profiler": sp_report,
		"boot_elapsed_ms": Time.get_ticks_msec() - _boot_started_ms if _boot_started_ms > 0 else 0,
	}
	var jf := FileAccess.open(out_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(payload, "\t"))
		jf.close()
		print("WROTE %s" % out_path)


## Wait until stage reached or timeout (frames).
func wait_for_stage(target: int, timeout_frames: int = -1) -> bool:
	if timeout_frames < 0:
		timeout_frames = _default_stage_timeout_frames
	var frames := 0
	while stage < target and stage != Stage.FAILED and frames < timeout_frames:
		await get_tree().process_frame
		frames += 1
	return stage >= target and stage != Stage.FAILED


func wait_for_service(id: StringName, timeout_frames: int = -1) -> bool:
	if timeout_frames < 0:
		timeout_frames = _default_stage_timeout_frames
	var frames := 0
	while not registry.has_service(id) and stage != Stage.FAILED and frames < timeout_frames:
		await get_tree().process_frame
		frames += 1
	return registry.has_service(id)


func get_diagnostics() -> Dictionary:
	var reg_dump: Dictionary = registry.dump() if registry else {}
	return {
		"stage": get_stage_name(),
		"stage_id": stage,
		"boot_done": _boot_done,
		"failed_reason": _failed_reason,
		"stage_times_ms": _stage_times_ms.duplicate(),
		"elapsed_ms": Time.get_ticks_msec() - _boot_started_ms if _boot_started_ms > 0 else 0,
		"registry": reg_dump,
		"resolved_config_keys": resolved_config.keys() if not resolved_config.is_empty() else [],
		"policy": resolved_config.get("policy", {}),
		"precedence": resolved_config.get("precedence", []),
	}


func get_health_report() -> Dictionary:
	var services: Dictionary = {}
	if registry:
		for id_variant in registry.all_ids():
			var id: StringName = id_variant
			var inst = registry.resolve(id)
			services[str(id)] = {
				"present": inst != null,
				"class": inst.get_class() if inst else "",
			}
	return {
		"stage": get_stage_name(),
		"running": stage == Stage.RUNNING,
		"services": services,
		"deps_ok": registry.validate_dependencies() if registry else {"ok": false},
		"cycles_ok": registry.detect_cycles() if registry else {"ok": false},
	}


## Deterministic shutdown: reverse registration order.
func shutdown() -> void:
	if stage == Stage.SHUTTING_DOWN:
		return
	_advance(Stage.SHUTTING_DOWN)
	if registry == null:
		return
	# Chunk views / pending GPU uploads must release before worker wait ends and tree free.
	var cm = registry.resolve(ID_CHUNKS)
	if cm != null and cm.has_method("release_all_chunks_for_teardown"):
		cm.release_all_chunks_for_teardown()
	for id_variant in registry.shutdown_order():
		var id: StringName = id_variant
		var inst = registry.resolve(id)
		if inst == null:
			continue
		# Chunk manager already fully released above.
		if id == ID_CHUNKS:
			continue
		if inst.has_method("shutdown_workers"):
			inst.shutdown_workers()
		elif inst.has_method("shutdown"):
			inst.shutdown()
	registry.clear()
