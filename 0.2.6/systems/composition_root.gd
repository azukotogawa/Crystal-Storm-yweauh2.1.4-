class_name CompositionRoot
extends Node
## Single authoritative boot / service wiring authority for production main scene.
## Stages are one-way. Critical peers are resolved via ServiceRegistry, not groups.
## Groups may still exist as discovery adapters for UI/debug.

const _ServiceRegistry = preload("res://systems/service_registry.gd")
const _RuntimeConfigResolver = preload("res://systems/runtime_config_resolver.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")

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
	if registry == null:
		registry = _ServiceRegistry.new()

	# --- Discover scene-owned services once by relative path (not groups) ---
	var game := get_parent()
	if game == null:
		return _fail("composition_root has no parent Game node")

	_register_scene_services(game)

	# --- CONFIGURED ---
	var cfg = registry.require(ID_CONFIG)
	if cfg == null:
		return _fail("missing config_service")
	# ConfigService._ready may already have run; ensure defaults applied.
	if cfg.has_method("ensure_ready_sync"):
		cfg.ensure_ready_sync()
	# Authored config fan-out via registry (not group search).
	if cfg.has_method("apply_to_registered"):
		cfg.apply_to_registered(registry, {})
	_advance(Stage.CONFIGURED)

	# --- QUALITY + resolved config ---
	var perf = registry.require(ID_PERF)
	if perf == null:
		return _fail("missing performance_service")
	# Ensure quality resource selected (env/preset may already have set quality).
	if not bool(perf.get("_applied")) if "_applied" in perf else true:
		if perf.has_method("ensure_ready"):
			var frames := 0
			while not bool(perf.get("_applied")) and frames < _default_stage_timeout_frames:
				await get_tree().process_frame
				frames += 1
			if not bool(perf.get("_applied")):
				return _fail("performance_service quality not applied (timeout)")
	_rebuild_resolved_config(cfg, perf)
	# Re-push authored config with resolved vegetation multipliers etc.
	if cfg.has_method("apply_to_registered"):
		cfg.apply_to_registered(registry, resolved_config)
	# Apply *effective* policy (quality folded with platform/debug) via registry.
	if perf.has_method("apply_to_registered"):
		perf.apply_to_registered(registry, resolved_config)
	_advance(Stage.QUALITY_APPLIED)

	# --- FEATURES (textures only first — must not wait for chunks) ---
	var features = registry.require(ID_FEATURES)
	var visreg = registry.resolve(ID_VISUAL_REG)
	if visreg and visreg.has_method("ensure_textures_ready"):
		await visreg.ensure_textures_ready()
	elif visreg and visreg.has_method("ensure_ready"):
		await visreg.ensure_ready()

	if features and features.has_method("bootstrap_with_services"):
		await features.bootstrap_with_services(registry, resolved_config)
	elif features and features.has_method("ensure_ready"):
		await features.ensure_ready()
	if features == null or not bool(features.get("bootstrap_complete")):
		# Wait for features seed if still async
		var fframes := 0
		while features and not bool(features.get("bootstrap_complete")) and fframes < _default_stage_timeout_frames:
			await get_tree().process_frame
			fframes += 1
		if features and not bool(features.get("bootstrap_complete")):
			return _fail("world_features bootstrap timeout")
	_advance(Stage.FEATURES_SEEDED)

	# --- CHUNKS ---
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

	# Explicit handoff fan-out (replaces group lookups in on_chunk_manager_ready)
	_on_chunk_manager_ready_explicit(cm)
	_advance(Stage.CHUNKS_CREATED)

	# --- INITIAL STREAM ---
	var sframes := 0
	while sframes < 90:
		if cm.chunks != null and cm.chunks.size() >= 1:
			break
		await get_tree().process_frame
		sframes += 1
	_advance(Stage.INITIAL_STREAM_READY)

	# --- VISUALS ---
	var world_visuals = registry.resolve(ID_WORLD_VISUALS)
	if world_visuals and world_visuals.has_method("post_bootstrap_refresh"):
		await world_visuals.post_bootstrap_refresh()
	elif visreg and visreg.has_method("post_bootstrap_refresh"):
		await visreg.post_bootstrap_refresh()
	_advance(Stage.VISUALS_COMMITTED)

	_advance(Stage.RUNNING)
	_boot_done = true
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
	stage = next_stage
	var name := get_stage_name()
	_stage_times_ms[name] = Time.get_ticks_msec() - _boot_started_ms
	stage_changed.emit(stage, name)
	print("[CompositionRoot] stage=%s t=%dms" % [name, int(_stage_times_ms[name])])


func _fail(reason: String) -> bool:
	_failed_reason = reason
	stage = Stage.FAILED
	var dump := get_diagnostics()
	boot_failed.emit(reason, dump)
	push_error("[CompositionRoot] BOOT FAILED: %s" % reason)
	print(JSON.stringify(dump, "\t"))
	return false


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
	for id_variant in registry.shutdown_order():
		var id: StringName = id_variant
		var inst = registry.resolve(id)
		if inst == null:
			continue
		if inst.has_method("shutdown_workers"):
			inst.shutdown_workers()
		elif inst.has_method("shutdown"):
			inst.shutdown()
	registry.clear()
