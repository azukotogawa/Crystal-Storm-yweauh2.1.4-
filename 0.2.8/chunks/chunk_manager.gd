class_name ChunkManager
extends Node3D

const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")
const _ChunkStreamingTelemetry = preload("res://systems/chunk_streaming_telemetry.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _ChunkStreamLifecycle = preload("res://helpers/chunk_stream_lifecycle.gd")
const _ChunkStreamScheduler = preload("res://helpers/chunk_stream_scheduler.gd")
const _TerrainDirtyScope = preload("res://helpers/terrain_dirty_scope.gd")
const _TerrainSurfaceCache = preload("res://helpers/terrain_surface_cache.gd")
const _MicroTerrainMeshCompositor = preload("res://helpers/micro_terrain_mesh_compositor.gd")

signal chunk_ready(coord: Vector2i, data: ChunkData)
signal chunk_unloaded(coord: Vector2i)

@export var RENDER_DISTANCE : int = 3
@export var MESH_CAVES : bool = false
## Main-thread applies per frame (legacy path when FrameBudgetScheduler absent).
@export var MAX_CHUNKS_PER_FRAME : int = 1
@export var MAX_INFLIGHT_CHUNKS : int = 6

var chunks: Dictionary[Vector2i, ChunkView] = {}
var pending := {}
var _chunk_tasks := {}
var _chunk_gen_tokens := {}
var _mesh_completion_queue: Array = []
var _stat_mutex := Mutex.new()
var stat_worker_us: int = 0
var stat_worker_n: int = 0
var stat_main_us: int = 0
var stat_main_n: int = 0
var stat_upload_us: int = 0
var stat_upload_n: int = 0
var _shutting_down: bool = false
var stream_paused: bool = false

var _last_chunk_key: Vector2i = Vector2i(-99999, -99999)

var player: Node3D = null
var world: InfiniteNoiseWorld

const CHUNK_VIEW_SCENE = preload("res://scenes/ChunkView.tscn")

const _RAMP_DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var ramp_placement_chance: int = 28
var ramp_max_surface_height: float = 88.0
var ramp_mountain_cutoff_height: float = 72.0
var prebuild_chunk_buffers: bool = true
var terrain_surface_mesh: bool = true
var chunk_upload_budget_us: int = 3500
var streaming_budget_us: int = 2500
var max_stream_starts_per_frame: int = 1
var max_stream_unloads_per_frame: int = 2
var _stream_load_pending: Dictionary = {}
var _stream_unload_pending: Array = []
var _lifecycle_by_coord: Dictionary = {}
var _last_player_chunk_for_velocity: Vector2i = Vector2i(-99999, -99999)
var _player_chunk_velocity: Vector2i = Vector2i.ZERO
var _stream_budget_used_us: int = 0
var _rebuild_pending: Dictionary = {}
var _patch_pending: Dictionary = {}
var _last_patch_scope: Dictionary = {}
var _telemetry_trigger: String = "stream"
var _telemetry_meta: Dictionary = {}
var _mesh_defer_micro_columns: bool = true
var _rebuild_flush_needed: bool = false
var _stream_load_order_dirty: bool = true
var _stream_unload_order_dirty: bool = true
var _stream_load_sorted: Array = []
var _mesh_completion_order_dirty: bool = true
var _profiler_node: Node = null
var _fbs_node: Node = null
const _VIEW_POOL_MAX: int = 48
var _view_pool: Array = []
var defer_world_bake_bootstrap: bool = false

var _drain_measure: bool = false
var _drain_n: int = 0
var _drain_sum_us: int = 0
var _drain_max_us: int = 0
var _drain_phase: Dictionary = {}
var _drain_worst: Dictionary = {}
var _drain_enqueue_n: int = 0
var _drain_enqueue_max_us: int = 0
var _drain_enqueue_worst: Dictionary = {}

# Mirrored from WorldBorder — worker threads cannot call class_name statics reliably.
const _WB_PLAYABLE_HALF := 1024
const _WB_TRANSITION := 240.0

const FACE_TOP := 0
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9
const FACE_NEG_X := 3
const FACE_POS_X := 4
const FACE_NEG_Z := 5
const FACE_POS_Z := 6

const CAVE_MESH_DEPTH := 32

func _ready():
	add_to_group("chunk_manager")
	TerrainRamps.invalidate_mesh_cache()
	_profiler_node = get_node_or_null("/root/PerfProfiler")
	_fbs_node = get_node_or_null("/root/FrameBudgetScheduler")

	player = get_tree().get_first_node_in_group("player")
	world = get_tree().get_first_node_in_group("world")
	
	if player == null:                                                          
		print("WARNING: Player node (group 'player') not found in _ready!")
	if world == null:                                                           
		print("WARNING: World node (group 'world') not found in _ready!")

	if defer_world_bake_bootstrap:
		return
	_bootstrap_world_bake()
	_bootstrap_mesh_plan_cache()
	_request_initial_stream()


func _request_initial_stream() -> void:
	if player and world:
		var col := _player_column_pos()
		var cx = floori(col.x / float(ChunkData.SIZE))
		var cz = floori(col.y / float(ChunkData.SIZE))
		update_stream(cx, cz)


func bootstrap_world_bake_async() -> void:
	var _STP = load("res://systems/startup_total_profiler.gd")
	if _STP and _STP.is_enabled():
		_STP.begin("ChunkManager.bootstrap_world_bake_async", "bake_package_loading")
	if world == null:
		world = get_tree().get_first_node_in_group("world") if get_tree() else null
	if player == null and get_tree():
		player = get_tree().get_first_node_in_group("player")
	await _bootstrap_world_bake_async()
	if _STP and _STP.is_enabled():
		_STP.begin("ChunkManager.bootstrap_mesh_plan_cache", "bake_package_loading")
	_bootstrap_mesh_plan_cache()
	if _STP and _STP.is_enabled():
		_STP.end("ChunkManager.bootstrap_mesh_plan_cache")
		_STP.begin("ChunkManager.request_initial_stream", "chunk_streaming")
	_request_initial_stream()
	if _STP and _STP.is_enabled():
		_STP.end("ChunkManager.request_initial_stream")
		_STP.end("ChunkManager.bootstrap_world_bake_async")


func _tick_deferred_bake_fill() -> void:
	var profiler = _profiler_node
	if profiler and profiler.has_method("begin"):
		profiler.begin("world_bake_fill")
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake == null or not bool(bake.get("bake_in_progress")):
		if profiler and profiler.has_method("end"):
			profiler.end("world_bake_fill")
		return
	var meshq: int = _mesh_completion_queue.size()
	if "stream_busy" in bake:
		bake.stream_busy = _chunk_tasks.size()
	if meshq > 8 and profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame("world_bake_fill_skip_meshq")
	var fbs = _fbs_node
	if fbs != null and fbs.has_method("run_budgeted"):
		fbs.run_budgeted(&"world_bake_fill", func(_token):
			if bake.has_method("tick_background_fill"):
				bake.tick_background_fill(meshq)
		)
	elif bake.has_method("tick_background_fill"):
		bake.tick_background_fill(meshq)
	if profiler and profiler.has_method("end"):
		profiler.end("world_bake_fill")


func _WorldBakeService_is_outside(coord: Vector2i) -> bool:
	var wb = load("res://world/world_bake_service.gd")
	if wb == null or not wb.has_method("is_chunk_outside_finite_world"):
		return false
	return bool(wb.is_chunk_outside_finite_world(coord))


func _bootstrap_world_bake() -> void:
	if world == null:
		return
	var _SP = load("res://systems/startup_profiler.gd")
	if _SP and _SP.is_enabled():
		_SP.begin("load_bake_index")
	var wb_script = load("res://world/world_bake_service.gd")
	if wb_script == null:
		if _SP and _SP.is_enabled():
			_SP.end("load_bake_index")
		return
	var bake = wb_script.ensure_active() if wb_script.has_method("ensure_active") else null
	if bake == null:
		if _SP and _SP.is_enabled():
			_SP.end("load_bake_index")
		return
	var result: Dictionary = bake.bootstrap_for_world(world, false, self)
	_finish_bootstrap_world_bake_result(result, _SP)


func _bootstrap_world_bake_async() -> void:
	if world == null:
		return
	var _SP = load("res://systems/startup_profiler.gd")
	if _SP and _SP.is_enabled():
		_SP.begin("load_bake_index")
	var wb_script = load("res://world/world_bake_service.gd")
	if wb_script == null:
		if _SP and _SP.is_enabled():
			_SP.end("load_bake_index")
		return
	var bake = wb_script.ensure_active() if wb_script.has_method("ensure_active") else null
	if bake == null:
		if _SP and _SP.is_enabled():
			_SP.end("load_bake_index")
		return
	print("[CRASH_CRUMB t=%d] ChunkManager → WorldBakeService.bootstrap_for_world_async ENTER" % Time.get_ticks_msec())
	var _cf := FileAccess.open("user://startup_last_step.txt", FileAccess.WRITE)
	if _cf:
		_cf.store_string("[CRASH_CRUMB] ChunkManager → bootstrap_for_world_async ENTER\n")
		_cf.close()
	var result: Dictionary = await bake.bootstrap_for_world_async(world, false, self)
	print("[CRASH_CRUMB t=%d] ChunkManager → bootstrap_for_world_async EXIT ok=%s mode=%s" % [
		Time.get_ticks_msec(), str(result.get("ok", false)), str(result.get("mode", "")),
	])
	_cf = FileAccess.open("user://startup_last_step.txt", FileAccess.WRITE)
	if _cf:
		_cf.store_string(
			"[CRASH_CRUMB] bootstrap_for_world_async EXIT ok=%s mode=%s\n"
			% [str(result.get("ok", false)), str(result.get("mode", ""))]
		)
		_cf.close()
	_finish_bootstrap_world_bake_result(result, _SP)


func _finish_bootstrap_world_bake_result(result: Dictionary, _SP) -> void:
	if _SP and _SP.is_enabled():
		_SP.end("load_bake_index")
		var mp0: Dictionary = result.get("mesh_plan", {})
		_SP.mark("load_mesh_plan_cache", int(mp0.get("bake_ms", 0)) * 1000)
	if bool(result.get("ok", false)):
		var mode := str(result.get("mode", ""))
		if mode == "baked":
			print(
				"[WorldBake] Rebuild complete bake_ms=%s bytes=%s chunks=%s"
				% [
					str(result.get("bake_ms", 0)),
					str(result.get("bytes", 0)),
					str(result.get("chunks", "")),
				]
			)
		elif mode == "disabled" or mode == "miss":
			print("[WorldBake] mode=%s seed=%s" % [mode, str(result.get("seed", ""))])
		var mp: Dictionary = result.get("mesh_plan", {})
		if not mp.is_empty():
			var mpm := str(mp.get("mode", ""))
			if mpm != "valid" and mpm != "streamed" and mpm != "loaded":
				print(
					"[MeshPlanCache] mode=%s chunks=%s bytes=%s bake_ms=%s"
					% [
						mpm,
						str(mp.get("chunks", "")),
						str(mp.get("bytes", 0)),
						str(mp.get("bake_ms", 0)),
					]
				)


func _bootstrap_mesh_plan_cache() -> void:
	if world == null:
		return
	var mp_script = load("res://world/mesh_plan_cache.gd")
	if mp_script == null:
		return
	var cache = mp_script.get_active()
	if cache != null and bool(cache.valid):
		if bool(cache.streamed_from_bake) or cache.plan_count() > 0:
			return
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bool(bake.valid) and bool(bake.streamed):
		if bake.has_method("ensure_mesh_plans"):
			bake.ensure_mesh_plans(self, world)
		return
	cache = mp_script.ensure_active() if mp_script.has_method("ensure_active") else null
	if cache == null:
		return
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	var r: int = int(bake.radius) if bake != null and "radius" in bake else 2
	if cache.has_method("load_plans") and cache.load_plans(seed, r):
		mp_script.set_active(cache)
		print("[MeshPlanCache] mode=loaded chunks=%s bytes=%s bake_ms=0" % [
			str(cache.plan_count()), str(cache.last_bytes)
		])
		return
	var raw := OS.get_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW").strip_edges().to_lower()
	if raw == "1" or raw == "true" or raw == "on":
		var result: Dictionary = cache.bootstrap_for_world(self, world, r, true)
		if bool(result.get("ok", false)):
			print(
				"[MeshPlanCache] mode=%s chunks=%s bytes=%s bake_ms=%s (explicit rebuild)"
				% [
					str(result.get("mode", "")),
					str(result.get("chunks", "")),
					str(result.get("bytes", 0)),
					str(result.get("bake_ms", 0)),
				]
			)
	else:
		print("[MeshPlanCache] mode=miss (no streamed plans / no monolith; not rebuilding)")

func shutdown_workers() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	_mesh_completion_queue.clear()
	for coord in _chunk_tasks.keys():
		_chunk_gen_tokens[coord] = int(_chunk_gen_tokens.get(coord, 0)) + 1
	var tasks: Array = _chunk_tasks.values()
	_chunk_tasks.clear()
	for tid in tasks:
		if tid is int:
			# Required: every WorkerThreadPool task id must be waited exactly once
			# or engine shutdown corrupts heap (SIGSEGV mutex=0x1c0 / free invalid).
			WorkerThreadPool.wait_for_task_completion(tid)


## Godot requires wait_for_task_completion for each add_task id; erasing without
## wait left handles for engine teardown to free twice / UAF.
func _reap_chunk_task(coord: Vector2i) -> void:
	if not _chunk_tasks.has(coord):
		return
	var tid = _chunk_tasks[coord]
	_chunk_tasks.erase(coord)
	if tid is int:
		var profiler = get_node_or_null("/root/PerfProfiler")
		if profiler and profiler.has_method("begin"):
			profiler.begin("chunk_worker_wait")
		if profiler and profiler.has_method("begin_func"):
			profiler.begin_func("ChunkManager::_reap_chunk_task")
		WorkerThreadPool.wait_for_task_completion(tid)
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_reap_chunk_task")
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_worker_wait")


## Safe to remove_child + free views here. Must NOT be used from _exit_tree (double free).
func release_all_chunks_for_teardown() -> void:
	if has_meta("_teardown_released"):
		return
	set_meta("_teardown_released", true)
	_shutdown_trace("release_all begin views=%d is_inside_tree=%s" % [
		chunks.size(), str(is_inside_tree())
	])
	shutdown_workers()
	ChunkView.clear_pending_buffer_uploads()
	_mesh_completion_queue.clear()
	_stream_load_pending.clear()
	_stream_unload_pending.clear()
	_lifecycle_by_coord.clear()
	for coord in _chunk_gen_tokens.keys():
		_chunk_gen_tokens[coord] = int(_chunk_gen_tokens.get(coord, 0)) + 1000
	var keys := chunks.keys()
	var bake = load("res://world/world_bake_service.gd").get_active()
	for key in keys:
		var view: ChunkView = chunks[key]
		if is_instance_valid(view):
			ChunkView.cancel_pending_uploads_for_view(view)
			var data_to_pool: ChunkData = view.chunk_data
			view.chunk_data = null
			view.mesh_data = {}
			# Explicit teardown: do not pool — free views we own while tree is live.
			if data_to_pool != null:
				data_to_pool.set_meta("_pooled", true)
				data_to_pool.set_meta("_pooled_released", true)
				data_to_pool.world = null
			if view.get_parent() == self:
				remove_child(view)
			_shutdown_trace("queue_free view %s id=%d" % [str(key), view.get_instance_id()])
			view.queue_free()
		if bake != null and bake.has_method("release_chunk"):
			bake.release_chunk(key)
	chunks.clear()
	pending.clear()
	_rebuild_pending.clear()
	_patch_pending.clear()
	_ChunkDataPool.clear()
	_clear_view_pool()
	if has_meta("_rebuild_flush_scheduled"):
		remove_meta("_rebuild_flush_scheduled")
	_shutdown_trace("release_all end")


## Children will be freed by the engine — DO NOT queue_free ChunkViews here
## (that is the double-free root cause: parent frees children twice).
func _exit_tree() -> void:
	_shutdown_trace("_exit_tree begin already_released=%s children=%d chunks=%d" % [
		str(has_meta("_teardown_released")),
		get_child_count(),
		chunks.size(),
	])
	if has_meta("_teardown_released"):
		shutdown_workers()
		ChunkView.clear_pending_buffer_uploads()
		_shutdown_trace("_exit_tree skip free (already released)")
		return
	set_meta("_teardown_released", true)
	shutdown_workers()
	ChunkView.clear_pending_buffer_uploads()
	_mesh_completion_queue.clear()
	_stream_load_pending.clear()
	_stream_unload_pending.clear()
	var bake = load("res://world/world_bake_service.gd").get_active()
	for key in chunks.keys():
		var view: ChunkView = chunks[key]
		if is_instance_valid(view):
			ChunkView.cancel_pending_uploads_for_view(view)
			var data: ChunkData = view.chunk_data
			view.chunk_data = null
			view.mesh_data = {}
			if data != null:
				data.set_meta("_pooled", true)
				data.set_meta("_pooled_released", true)
				data.world = null
			# Null MultiMesh refs so RID teardown is single-owner.
			if view.has_method("_exit_tree"):
				pass
			if view.get_node_or_null("LayerContainer"):
				for child in view.get_node("LayerContainer").get_children():
					if child is MultiMeshInstance3D:
						(child as MultiMeshInstance3D).multimesh = null
		if bake != null and bake.has_method("release_chunk"):
			bake.release_chunk(key)
	chunks.clear()
	pending.clear()
	_rebuild_pending.clear()
	_patch_pending.clear()
	_ChunkDataPool.clear()
	_clear_view_pool()
	_shutdown_trace("_exit_tree end (children left for SceneTree free)")


func _shutdown_trace(msg: String) -> void:
	if OS.get_environment("CRYSTALSTORM_SHUTDOWN_TRACE") == "1":
		print("[SHUTDOWN_TRACE] ChunkManager %s" % msg)


func _unload_chunk_view(key: Vector2i) -> void:
	if not chunks.has(key):
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_unload")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_unload_chunk_view")
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.record_unload(key, "start", {"active_chunks": chunks.size()})
	_set_lifecycle_state(key, _ChunkStreamLifecycle.UNLOADING)
	var view: ChunkView = chunks[key]
	chunks.erase(key)
	if is_instance_valid(view):
		ChunkView.cancel_pending_uploads_for_view(view)
		var data_to_pool: ChunkData = view.chunk_data
		view.chunk_data = null
		view.mesh_data = {}
		if data_to_pool != null and not data_to_pool.has_meta("_pooled"):
			data_to_pool.set_meta("_pooled", true)
		if view.get_parent() == self:
			if profiler and profiler.has_method("begin"):
				profiler.begin("chunk_scenetree_remove")
			remove_child(view)
			if profiler and profiler.has_method("end"):
				profiler.end("chunk_scenetree_remove")
		if data_to_pool != null:
			_pool_chunk_data_after_view_free(data_to_pool)
		if not _try_pool_chunk_view(view):
			call_deferred("_profiled_free_chunk_view", view)
	_maybe_release_bake_package(key)
	_set_lifecycle_state(key, _ChunkStreamLifecycle.UNLOADED)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.record_unload(key, "complete", {"active_chunks": chunks.size()})
	chunk_unloaded.emit(key)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_unload_chunk_view")
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_unload")


func _maybe_release_bake_package(key: Vector2i) -> void:
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake == null or not bake.has_method("release_chunk"):
		return
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var n := Vector2i(key.x + dx, key.y + dz)
			if chunks.has(n) or pending.has(n) or _chunk_tasks.has(n) or _stream_load_pending.has(n):
				return
	bake.release_chunk(key)


func _try_pool_chunk_view(view: Node) -> bool:
	if view == null or not is_instance_valid(view) or _shutting_down:
		return false
	if _view_pool.size() >= _VIEW_POOL_MAX:
		return false
	if view is not ChunkView:
		return false
	var cv := view as ChunkView
	cv.chunk_data = null
	cv.mesh_data = {}
	if cv.layer_container and is_instance_valid(cv.layer_container):
		for child in cv.layer_container.get_children():
			if child is MultiMeshInstance3D:
				var mmi := child as MultiMeshInstance3D
				if mmi.multimesh != null:
					mmi.multimesh.instance_count = 0
			elif child is MeshInstance3D:
				(child as MeshInstance3D).mesh = null
	_view_pool.append(cv)
	var profiler = _profiler_node if _profiler_node != null else get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("inc_frame"):
		profiler.inc_frame("chunk_view_pool_puts", 1)
	if profiler and profiler.has_method("set_gauge"):
		profiler.set_gauge("chunk_view_pool_size", float(_view_pool.size()))
	return true


func _acquire_chunk_view() -> ChunkView:
	while not _view_pool.is_empty():
		var v: ChunkView = _view_pool.pop_back() as ChunkView
		if v != null and is_instance_valid(v):
			var profiler = _profiler_node if _profiler_node != null else get_node_or_null("/root/PerfProfiler")
			if profiler and profiler.has_method("inc_frame"):
				profiler.inc_frame("chunk_view_pool_gets", 1)
			if profiler and profiler.has_method("set_gauge"):
				profiler.set_gauge("chunk_view_pool_size", float(_view_pool.size()))
			return v
	return CHUNK_VIEW_SCENE.instantiate() as ChunkView


func _profiled_free_chunk_view(view: Node) -> void:
	if view == null or not is_instance_valid(view):
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_node_free")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_profiled_free_chunk_view")
	view.free()
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_profiled_free_chunk_view")
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_node_free")


func _clear_view_pool() -> void:
	for v in _view_pool:
		if v != null and is_instance_valid(v):
			(v as Node).free()
	_view_pool.clear()


func request_chunk(coord: Vector2i, high_priority: bool = false) -> void:
	if _is_chunk_resident(coord):
		return
	_queue_stream_load(coord, high_priority)


func set_drain_measure_enabled(enabled: bool) -> void:
	_drain_measure = enabled
	if enabled:
		reset_drain_measure()
	if OS.get_environment("CRYSTALSTORM_BAKE_RESIDENT_MEASURE").strip_edges().to_lower() in ["1", "true", "on"] \
			or enabled:
		var bake = load("res://world/world_bake_service.gd").get_active()
		if bake != null and bake.has_method("set_resident_measure_enabled"):
			bake.set_resident_measure_enabled(enabled)


func reset_drain_measure() -> void:
	_drain_n = 0
	_drain_sum_us = 0
	_drain_max_us = 0
	_drain_phase.clear()
	_drain_worst.clear()
	_drain_enqueue_n = 0
	_drain_enqueue_max_us = 0
	_drain_enqueue_worst.clear()


func _drain_add(phase: String, us: int) -> void:
	if not _drain_measure or us < 0:
		return
	if not _drain_phase.has(phase):
		_drain_phase[phase] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _drain_phase[phase]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + us
	row["max_us"] = maxi(int(row["max_us"]), us)


func get_drain_measure() -> Dictionary:
	var phases: Array = []
	for k in _drain_phase.keys():
		var row: Dictionary = _drain_phase[k]
		var tot: int = int(row.get("total_us", 0))
		var n: int = int(row.get("n", 0))
		phases.append({
			"phase": k,
			"n": n,
			"total_us": tot,
			"total_ms": float(tot) / 1000.0,
			"max_us": int(row.get("max_us", 0)),
			"max_ms": float(row.get("max_us", 0)) / 1000.0,
			"avg_us": float(tot) / float(maxi(n, 1)),
			"share_of_drain_sum": float(tot) / float(maxi(_drain_sum_us, 1)),
		})
	phases.sort_custom(func(a, b): return int(a.total_us) > int(b.total_us))
	var bake_m: Dictionary = {}
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bake.has_method("get_resident_measure"):
		bake_m = bake.get_resident_measure()
	var snap_m: Dictionary = ChunkData.get_snapshot_measure()
	return {
		"drain_calls": _drain_n,
		"drain_total_us": _drain_sum_us,
		"drain_total_ms": float(_drain_sum_us) / 1000.0,
		"drain_avg_us": float(_drain_sum_us) / float(maxi(_drain_n, 1)),
		"drain_max_us": _drain_max_us,
		"drain_max_ms": float(_drain_max_us) / 1000.0,
		"phases": phases,
		"worst_drain": _drain_worst.duplicate(true),
		"enqueue_calls": _drain_enqueue_n,
		"enqueue_max_us": _drain_enqueue_max_us,
		"enqueue_max_ms": float(_drain_enqueue_max_us) / 1000.0,
		"worst_enqueue": _drain_enqueue_worst.duplicate(true),
		"bake_resident": bake_m,
		"capture_worker_snapshot": snap_m,
	}


func _enqueue_chunk_generation(coord: Vector2i, high_priority: bool = false) -> void:
	if pending.has(coord) or _chunk_tasks.has(coord):
		return
	var t_enq0 := Time.get_ticks_usec() if _drain_measure else 0
	var enq_parts: Dictionary = {}
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled():
		SPP.begin_chunk(coord)
	# Always warm the ring even when the target is *outside* package bounds so
	# edge stream jobs do not cold-load packages inside sample_base.
	var bake_pre = load("res://world/world_bake_service.gd").get_active()
	if bake_pre != null and bake_pre.has_method("coord_in_package"):
		if bake_pre.has_method("ensure_package_for_stream") and bake_pre.coord_in_package(coord):
			bake_pre.ensure_package_for_stream(coord)
		var can_prefetch: bool = bool(bake_pre.valid) or (
			bake_pre.has_method("package_ready") and bool(bake_pre.package_ready(coord))
		)
		if can_prefetch and bake_pre.has_method("ensure_chunk_resident"):
			var t_ec := Time.get_ticks_usec() if _drain_measure else 0
			if bake_pre.package_ready(coord) if bake_pre.has_method("package_ready") else bake_pre.coord_in_package(coord):
				bake_pre.ensure_chunk_resident(coord)
			if _drain_measure:
				var ec_us := Time.get_ticks_usec() - t_ec
				_drain_add("ensure_chunk_resident", ec_us)
				enq_parts["ensure_chunk_resident_us"] = ec_us
		var t_halo := Time.get_ticks_usec() if _drain_measure else 0
		var halo_n := 0
		var surface_fn := "ensure_surface_data_resident" if bake_pre.has_method("ensure_surface_data_resident") \
			else "ensure_package_data_resident"
		if bake_pre.has_method(surface_fn):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0 and bake_pre.coord_in_package(coord):
						continue
					var n := Vector2i(coord.x + dx, coord.y + dz)
					var n_ready: bool = bake_pre.valid and bake_pre.coord_in_package(n)
					if bake_pre.has_method("package_ready"):
						n_ready = bool(bake_pre.package_ready(n))
					if n_ready:
						bake_pre.call(surface_fn, n)
						halo_n += 1
		if _drain_measure:
			var halo_us := Time.get_ticks_usec() - t_halo
			_drain_add("ensure_surface_halo", halo_us)
			enq_parts["ensure_surface_halo_us"] = halo_us
			enq_parts["halo_calls"] = halo_n
	if world == null:
		return

	pending[coord] = true
	var token: int = int(_chunk_gen_tokens.get(coord, 0)) + 1
	_chunk_gen_tokens[coord] = token

	var pool_stats_before: Dictionary = _ChunkDataPool.get_stats()
	var t_alloc := Time.get_ticks_usec()
	var data := _ChunkDataPool.acquire(coord, world)
	if data == null:
		pending.erase(coord)
		return
	var alloc_us := Time.get_ticks_usec() - t_alloc
	if _drain_measure:
		_drain_add("chunk_data_alloc", alloc_us)
		enq_parts["chunk_data_alloc_us"] = alloc_us
	var alloc_path := "pool_reuse" if int(pool_stats_before.get("alloc_reuse", 0)) < int(_ChunkDataPool.get_stats().get("alloc_reuse", 0)) else "ChunkData.new"
	if SPP and SPP.is_enabled():
		SPP.record("chunk_data_alloc", alloc_us, coord)
	var t_snap := Time.get_ticks_usec()
	data.capture_worker_snapshot()
	var snap_us := Time.get_ticks_usec() - t_snap
	if _drain_measure:
		_drain_add("capture_worker_snapshot", snap_us)
		enq_parts["capture_worker_snapshot_us"] = snap_us
	if SPP and SPP.is_enabled():
		SPP.record("worker_snapshot_capture", snap_us, coord)
	_set_lifecycle_state(coord, _ChunkStreamLifecycle.ALLOCATED)

	if _ChunkRebuildTelemetry.is_enabled():
		var tele_meta := _telemetry_meta.duplicate()
		tele_meta["is_regen"] = chunks.has(coord)
		tele_meta["chunk_data_alloc_path"] = alloc_path
		_ChunkRebuildTelemetry.record_enqueue(coord, token, _telemetry_trigger, tele_meta)
	var _gen_profiler = get_node_or_null("/root/PerfProfiler")
	if _gen_profiler and _gen_profiler.has_method("inc_rate"):
		_gen_profiler.inc_rate("chunks_generated", 1)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.begin_lifecycle(coord, token, _telemetry_trigger, {
			"alloc_path": alloc_path,
			"high_priority": high_priority,
			"is_regen": chunks.has(coord),
		})
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_ALLOCATED, {
			"alloc_path": alloc_path,
		})

	var t_wq := Time.get_ticks_usec() if _drain_measure else 0
	var task_id := WorkerThreadPool.add_task(
		Callable(self, "_chunk_mesh_task").bind(
			coord, data, token, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}
		),
		high_priority
	)
	_chunk_tasks[coord] = task_id
	if _drain_measure:
		var wq_us := Time.get_ticks_usec() - t_wq
		_drain_add("worker_queue_add_task", wq_us)
		enq_parts["worker_queue_add_task_us"] = wq_us
		var enq_tot := Time.get_ticks_usec() - t_enq0
		_drain_add("enqueue_chunk_generation", enq_tot)
		_drain_enqueue_n += 1
		if enq_tot >= _drain_enqueue_max_us:
			_drain_enqueue_max_us = enq_tot
			enq_parts["coord"] = [coord.x, coord.y]
			enq_parts["total_us"] = enq_tot
			enq_parts["total_ms"] = float(enq_tot) / 1000.0
			enq_parts["high_priority"] = high_priority
			_drain_enqueue_worst = enq_parts.duplicate(true)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_WORKER_QUEUED, {
			"worker_tasks": _chunk_tasks.size(),
			"mesh_queue_depth": _mesh_completion_queue.size(),
			"pending_chunks": pending.size(),
		})


func _regenerate_chunk_mesh(coord: Vector2i, high_priority: bool = true) -> void:
	if world == null or not chunks.has(coord):
		return
	_enqueue_chunk_mesh_work(coord, true, [], high_priority, false)


func _enqueue_chunk_mesh_work(
	coord: Vector2i,
	full_rebuild: bool,
	dirty_local: Array,
	high_priority: bool,
	force_new_data: bool
) -> void:
	if world == null:
		return
	if pending.has(coord) or _chunk_tasks.has(coord):
		var preserve_maps := _chunk_wants_preserved_maps(coord)
		_merge_patch_pending(coord, dirty_local, full_rebuild, preserve_maps)
		_schedule_rebuild_flush()
		return

	var data: ChunkData = null
	var keep_quads: Array = []
	var prior_surface_cache: Dictionary = {}
	var patch_rect := Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE)
	var is_regen := chunks.has(coord)

	if force_new_data or not is_regen:
		data = ChunkData.new(coord, world)
		if data == null:
			return
		data.capture_worker_snapshot()
		full_rebuild = true
	elif is_regen:
		var view: ChunkView = chunks[coord] as ChunkView
		data = view.chunk_data
		if data == null:
			return
		data.world = world
		if full_rebuild:
			data.capture_worker_snapshot()
		else:
			data.refresh_worker_snapshot_for_cells(dirty_local)
			patch_rect = _TerrainDirtyScope.mesh_patch_rect(dirty_local)
			var existing: Array = view.mesh_data.get("quads", [])
			for q_variant in existing:
				var q: Dictionary = q_variant
				var clipped: Array = _clip_quad_outside_rect(q, patch_rect)
				for keep_v in clipped:
					keep_quads.append(keep_v)
			if terrain_surface_mesh:
				prior_surface_cache = _TerrainSurfaceCache.duplicate_cache(
					_TerrainSurfaceCache.cache_from_payload(view.mesh_data)
				)
		if data.preserve_column_maps:
			_refresh_preserve_halo(data)

	pending[coord] = true
	var token: int = int(_chunk_gen_tokens.get(coord, 0)) + 1
	_chunk_gen_tokens[coord] = token

	if _ChunkRebuildTelemetry.is_enabled():
		var tele_meta := _telemetry_meta.duplicate()
		tele_meta["is_regen"] = is_regen
		tele_meta["incremental"] = not full_rebuild
		tele_meta["dirty_columns"] = int(_last_patch_scope.get("dirty_columns", dirty_local.size()))
		tele_meta["rebuilt_columns"] = dirty_local.size() if not full_rebuild else ChunkData.SIZE * ChunkData.SIZE
		tele_meta["rebuilt_chunks"] = (_last_patch_scope.get("rebuild_chunks", []) as Array).size() if _last_patch_scope.has("rebuild_chunks") else 1
		tele_meta["skipped_chunks"] = (_last_patch_scope.get("skipped_chunks", []) as Array).size()
		tele_meta["mesh_patch_size"] = _TerrainDirtyScope.patch_cells_area(patch_rect)
		tele_meta["chunk_data_alloc_path"] = "ChunkData.new" if force_new_data or not is_regen else "reuse"
		_ChunkRebuildTelemetry.record_enqueue(coord, token, _telemetry_trigger, tele_meta)
	var _mesh_profiler = get_node_or_null("/root/PerfProfiler")
	if _mesh_profiler:
		if _mesh_profiler.has_method("inc_rate"):
			if is_regen:
				_mesh_profiler.inc_rate("chunks_rebuilt", 1)
			else:
				_mesh_profiler.inc_rate("chunks_generated", 1)
		if _mesh_profiler.has_method("set_gauge"):
			_mesh_profiler.set_gauge("dirty_regions", float(dirty_local.size()))
	if _ChunkStreamingTelemetry.is_enabled():
		var alloc_path := "ChunkData.new" if force_new_data or not is_regen else "reuse"
		_ChunkStreamingTelemetry.begin_lifecycle(coord, token, _telemetry_trigger, {
			"alloc_path": alloc_path,
			"high_priority": high_priority,
			"is_regen": is_regen,
			"incremental": not full_rebuild,
		})
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_ALLOCATED, {
			"alloc_path": alloc_path,
		})

	var task_id := WorkerThreadPool.add_task(
		Callable(self, "_chunk_mesh_task").bind(
			coord, data, token, full_rebuild, dirty_local, patch_rect, keep_quads, prior_surface_cache
		),
		high_priority
	)
	_chunk_tasks[coord] = task_id
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_WORKER_QUEUED, {
			"worker_tasks": _chunk_tasks.size(),
			"mesh_queue_depth": _mesh_completion_queue.size(),
			"pending_chunks": pending.size(),
		})


func _surface_y_at(data: ChunkData, x: int, z: int) -> float:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		var sv = data.surface_map[x][z]
		if sv != null:
			return float(sv)
	return data.get_surface_y(x, z)


func _tile_type_at(data: ChunkData, x: int, z: int) -> int:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		var tv = data.tile_map[x][z]
		if tv != null:
			return int(tv)
	return data.get_tile_type(x, z)


func _build_mesh(data: ChunkData) -> Dictionary:
	if not ChunkData.USE_MICRO_BRICKS:
		return _build_macro_mesh(data)
	var built := _build_mesh_region(data, Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), true)
	sync_ramp_map_to_mesh(data, built.get("quads", []))
	return built


func _build_macro_mesh(data: ChunkData) -> Dictionary:
	var built := _build_macro_mesh_region(data, Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), true)
	sync_ramp_map_to_mesh(data, built.get("quads", []))
	return built


func _build_mesh_region(data: ChunkData, rect: Rect2i, full_chunk: bool = false) -> Dictionary:
	if not ChunkData.USE_MICRO_BRICKS:
		return _build_macro_mesh_region(data, rect, full_chunk)
	if not data._maps_resident:
		data.ensure_column_maps()
	var out_quads := []
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var z1 := rect.position.y + rect.size.y

	data._mesh_job_micro_skip = {}
	if _mesh_defer_micro_columns and data.is_micro_terrain_enabled():
		data._mesh_job_micro_skip = _MicroTerrainMeshCompositor.build_skip_set(data, rect)

	if not full_chunk:
		_clear_ramp_map_in_rect(data, rect)

	var concave_cells := {}
	if full_chunk:
		_emit_ramps(data, out_quads, concave_cells)
	else:
		_emit_ramps_in_rect(data, out_quads, concave_cells, rect)
	_emit_dug_strata_region(data, out_quads, x0, z0, x1, z1)
	_emit_build_strata_region(data, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 1, 0), FACE_TOP, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads, x0, z0, x1, z1)
	data._mesh_job_top_memo = null
	_emit_water_lids_region(data, out_quads, x0, z0, x1, z1)
	if MESH_CAVES and full_chunk:
		_emit_cave_faces(data, out_quads)
	var micro_skip: Dictionary = data._mesh_job_micro_skip
	data._mesh_job_micro_skip = {}
	if not micro_skip.is_empty():
		_MicroTerrainMeshCompositor.compose(data, rect, out_quads, self, micro_skip)

	return {
		"quads": out_quads,
		"count": out_quads.size()
	}


func _build_macro_mesh_region(data: ChunkData, rect: Rect2i, full_chunk: bool = false) -> Dictionary:
	if not data._maps_resident:
		data.ensure_column_maps()
	var out_quads := []
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var z1 := rect.position.y + rect.size.y
	data._mesh_job_micro_skip = {}
	data._mesh_job_top_memo = {} if SIDE_TOP_MEMO else null
	if not full_chunk:
		_clear_ramp_map_in_rect(data, rect)
	var concave_cells := {}
	if full_chunk:
		_emit_ramps(data, out_quads, concave_cells)
	else:
		_emit_ramps_in_rect(data, out_quads, concave_cells, rect)
	_emit_dug_strata_region(data, out_quads, x0, z0, x1, z1)
	_emit_build_strata_region(data, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 1, 0), FACE_TOP, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads, x0, z0, x1, z1)
	data._mesh_job_top_memo = null
	_emit_water_lids_region(data, out_quads, x0, z0, x1, z1)
	if MESH_CAVES and full_chunk:
		_emit_cave_faces(data, out_quads)
	return {
		"quads": out_quads,
		"count": out_quads.size()
	}

func _skips_greedy_surface_cell(data: ChunkData, x: int, z: int, for_top: bool = true) -> bool:
	if data != null and not data._mesh_job_micro_skip.is_empty() \
			and data._mesh_job_micro_skip.has(Vector2i(x, z)):
		return true
	if not data.has_ramp(x, z):
		return false
	var entry: Dictionary = data.get_ramp_entry(x, z)
	if bool(entry.get("approach", false)):
		return false
	if bool(entry.get("corner", false)):
		return false
	if bool(entry.get("concave", false)):
		return true
	return for_top


func _build_micro_mesh_region(data: ChunkData, rect: Rect2i) -> Dictionary:
	var out_quads: Array = []
	if not ChunkData.USE_MICRO_BRICKS or not data.is_micro_terrain_enabled():
		return {"quads": out_quads, "count": 0, "cells_meshed": 0}
	var skip_set: Dictionary = _MicroTerrainMeshCompositor.build_skip_set(data, rect)
	var cells_meshed: int = _MicroTerrainMeshCompositor.compose(data, rect, out_quads, self, skip_set)
	return {"quads": out_quads, "count": out_quads.size(), "cells_meshed": cells_meshed}


func _emit_single_surface_top_quad(data: ChunkData, out_quads: Array, x: int, z: int) -> void:
	_emit_waved_tops(data, out_quads, x, z, x + 1, z + 1)


func _is_ramp_approach_from_landing(data: ChunkData, x: int, z: int) -> bool:
	var entry: Dictionary = data.get_ramp_entry(x, z)
	if not entry.is_empty():
		return entry.get("approach", false)
	for d in _RAMP_DIRS:
		var lx: int = x - d.x
		var lz: int = z - d.y
		if lx < 0 or lx >= ChunkData.SIZE or lz < 0 or lz >= ChunkData.SIZE:
			continue
		if not data.has_ramp(lx, lz):
			continue
		var landing: Dictionary = data.get_ramp_entry(lx, lz)
		if landing.get("approach", false) or landing.get("corner", false):
			continue
		if landing.get("dir2", Vector2i.ZERO) != Vector2i.ZERO:
			continue
		if landing.get("dir", Vector2i.ZERO) == d:
			return true
	return false


func _greedy_mesh_plane(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
	if normal_dir.y != 0:
		var visited := []
		visited.resize(ChunkData.SIZE)
		for i in ChunkData.SIZE:
			visited[i] = []
			visited[i].resize(ChunkData.SIZE)
			for j in ChunkData.SIZE:
				visited[i][j] = false

		for x in range(ChunkData.SIZE):
			for z in range(ChunkData.SIZE):
				if visited[x][z] or _skips_greedy_surface_cell(data, x, z):
					continue
				var sy: float = _surface_y_at(data, x, z)
				if sy >= float(_WorldSettings.get_active().chunk_height_bound()):
					continue
				var vox := _tile_type_at(data, x, z)
				if vox == VoxelTypes.AIR:
					continue

				var dx := 1
				while x + dx < ChunkData.SIZE and not visited[x + dx][z] \
						and not _skips_greedy_surface_cell(data, x + dx, z) \
						and is_equal_approx(_surface_y_at(data, x + dx, z), sy) \
						and _tile_type_at(data, x + dx, z) == vox:
					dx += 1

				var dz := 1
				while z + dz < ChunkData.SIZE:
					var can := true
					for xx in range(dx):
						var cx := x + xx
						var cz := z + dz
						if visited[cx][cz] or _skips_greedy_surface_cell(data, cx, cz) \
								or not is_equal_approx(_surface_y_at(data, cx, cz), sy) \
								or _tile_type_at(data, cx, cz) != vox:
							can = false
							break
					if not can:
						break
					dz += 1

				for xx in range(dx):
					for zz in range(dz):
						visited[x + xx][z + zz] = true

				out_quads.append({
					"x": x,
					"y": sy,
					"z": z,
					"dim_x": float(dx),
					"dim_y": 1.0,
					"dim_z": float(dz),
					"uv_w": float(dx),
					"uv_h": float(dz),
					"type": vox,
					"face_code": face_code
				})
		return

	_emit_surface_side_walls(data, normal_dir, face_code, out_quads)


func _is_step_height(diff: float) -> bool:
	return TerrainRamps.is_step_height(diff)


func _cliff_height() -> float:
	return _WorldSettings.get_active().cliff_height()


func _has_player_build_at(data: ChunkData, x: int, z: int) -> bool:
	if data.get_worker_build_tile(x, z) >= 0:
		return true
	var layer_h: float = _WorldSettings.get_active().layer_height()
	var delta: float = data.get_worker_height_delta(x, z)
	return absf(delta) > layer_h * 0.08


func _should_place_ramp(world_x: int, world_z: int, dir: Vector2i, surface_h: float = -1.0) -> bool:
	if WorldBorder.in_rim_planes(float(world_x), float(world_z)):
		return false
	if surface_h >= 0.0:
		if surface_h > ramp_max_surface_height:
			return false
		if _world_border_should_force_ramp(world_x, world_z) and surface_h > ramp_mountain_cutoff_height:
			return false
	return TerrainRamps.should_place_ramp(world_x, world_z, dir)


func _should_place_corner(world_x: int, world_z: int) -> bool:
	if WorldBorder.in_rim_planes(float(world_x), float(world_z)):
		return false
	return TerrainRamps.should_place_corner(world_x, world_z)


func apply_world_gen_config(cfg) -> void:
	if cfg == null:
		return
	ramp_placement_chance = int(cfg.ramp_placement_chance)
	ramp_max_surface_height = float(cfg.ramp_max_surface_height)
	ramp_mountain_cutoff_height = float(cfg.mountain_ramp_cutoff_height)
	TerrainRamps.placement_chance = ramp_placement_chance


func apply_performance_config(cfg) -> void:
	if cfg == null:
		return
	RENDER_DISTANCE = int(cfg.render_distance)
	MAX_CHUNKS_PER_FRAME = int(cfg.max_chunks_per_frame)
	MAX_INFLIGHT_CHUNKS = int(cfg.max_inflight_chunks)
	MESH_CAVES = bool(cfg.mesh_caves)
	if "prebuild_chunk_buffers" in cfg:
		prebuild_chunk_buffers = bool(cfg.prebuild_chunk_buffers)
	if "terrain_surface_mesh" in cfg:
		terrain_surface_mesh = bool(cfg.terrain_surface_mesh)
	if "chunk_upload_budget_us" in cfg:
		chunk_upload_budget_us = maxi(int(cfg.chunk_upload_budget_us), 500)
	if "streaming_budget_us" in cfg:
		streaming_budget_us = maxi(int(cfg.streaming_budget_us), 500)
	if "max_stream_starts_per_frame" in cfg:
		max_stream_starts_per_frame = maxi(int(cfg.max_stream_starts_per_frame), 1)
	if "max_stream_unloads_per_frame" in cfg:
		max_stream_unloads_per_frame = maxi(int(cfg.max_stream_unloads_per_frame), 1)


func _world_border_should_force_ramp(world_x: int, world_z: int) -> bool:
	var ox: float = maxf(absf(float(world_x)) - float(_WB_PLAYABLE_HALF), 0.0)
	var oz: float = maxf(absf(float(world_z)) - float(_WB_PLAYABLE_HALF), 0.0)
	if ox <= 0.001 and oz <= 0.001:
		return false
	var margin := 8.0
	if ox > 0.001 and oz > 0.001:
		return sqrt(ox * ox + oz * oz) <= margin + 4.0
	return minf(ox if ox > 0.001 else 1e9, oz if oz > 0.001 else 1e9) <= margin


func _prefer_diagonal_ramp(world_x: int, world_z: int) -> bool:
	var ox: float = maxf(absf(float(world_x)) - float(_WB_PLAYABLE_HALF), 0.0)
	var oz: float = maxf(absf(float(world_z)) - float(_WB_PLAYABLE_HALF), 0.0)
	return ox > 0.001 and oz > 0.001 and sqrt(ox * ox + oz * oz) / _WB_TRANSITION < 0.85


func _dirs_perpendicular(d1: Vector2i, d2: Vector2i) -> bool:
	return d1.x * d2.x + d1.y * d2.y == 0


func _perpendicular_dirs(d: Vector2i) -> Array:
	return [Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]


func _step_out_dirs(data: ChunkData, x: int, z: int, low_h: float, world_x: int, world_z: int) -> Array:
	if _has_player_build_at(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		if _has_player_build_at(data, x + d.x, z + d.y):
			continue
		var nh: float = _sample_height(data, x + d.x, z + d.y)
		if _is_step_height(nh - low_h) and _should_place_ramp(world_x, world_z, d, low_h):
			out.append(d)
	return out


func _column_blocks_ramp(data: ChunkData, x: int, z: int) -> bool:
	if data != null and data._worker_water_lid.has(Vector2i(x, z)):
		return true
	var tile: int = _sample_tile_type(data, x, z)
	return tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER \
		or tile == VoxelTypes.OCEAN or tile == VoxelTypes.OCEAN2 or tile == VoxelTypes.OCEAN3


func _high_step_dirs(data: ChunkData, x: int, z: int, low_h: float) -> Array:
	if _has_player_build_at(data, x, z) or _column_blocks_ramp(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if _has_player_build_at(data, nx, nz) or _column_blocks_ramp(data, nx, nz):
			continue
		var in_chunk := nx >= 0 and nx < ChunkData.SIZE and nz >= 0 and nz < ChunkData.SIZE
		if in_chunk and _tile_type_at(data, nx, nz) == VoxelTypes.AIR:
			continue
		var nh: float = _sample_height(data, nx, nz)
		if _is_step_height(nh - low_h):
			out.append(d)
	return out


func _is_inner_plateau_corner(data: ChunkData, x: int, z: int, d_a: Vector2i, d_b: Vector2i) -> bool:
	if not _dirs_perpendicular(d_a, d_b):
		return false
	if _column_blocks_ramp(data, x, z) \
			or _column_blocks_ramp(data, x + d_a.x, z + d_a.y) \
			or _column_blocks_ramp(data, x + d_b.x, z + d_b.y) \
			or _column_blocks_ramp(data, x + d_a.x + d_b.x, z + d_a.y + d_b.y):
		return false
	var ha: float = _sample_height(data, x + d_a.x, z + d_a.y)
	var hb: float = _sample_height(data, x + d_b.x, z + d_b.y)
	if absf(ha - hb) > 0.15:
		return false
	var dx: int = x + d_a.x + d_b.x
	var dz: int = z + d_a.y + d_b.y
	var in_chunk := dx >= 0 and dx < ChunkData.SIZE and dz >= 0 and dz < ChunkData.SIZE
	if in_chunk and _tile_type_at(data, dx, dz) == VoxelTypes.AIR:
		return false
	return absf(_sample_height(data, dx, dz) - ha) <= 0.15


func _is_inner_corner_low_at(data: ChunkData, x: int, z: int) -> bool:
	if _has_player_build_at(data, x, z):
		return false
	var in_chunk := x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE
	if in_chunk and _tile_type_at(data, x, z) == VoxelTypes.AIR:
		return false
	var low_h: float = _sample_height(data, x, z)
	if low_h < 0.0:
		return false
	var highs: Array = _high_step_dirs(data, x, z, low_h)
	if highs.size() < 2:
		return false
	for i in highs.size():
		for j in range(i + 1, highs.size()):
			var d_a: Vector2i = highs[i]
			var d_b: Vector2i = highs[j]
			if _dirs_perpendicular(d_a, d_b) and _is_inner_plateau_corner(data, x, z, d_a, d_b):
				return true
	return false


func _cardinal_blocked_by_inner_corner(
	data: ChunkData,
	landing: Vector2i,
	toward_low: Vector2i,
	corner_low_cells: Dictionary
) -> bool:
	if corner_low_cells.has(landing) or _would_place_corner_at(data, landing.x, landing.y):
		return true
	var approach: Vector2i = landing + toward_low
	if corner_low_cells.has(approach) or _would_place_corner_at(data, approach.x, approach.y):
		return true
	if _is_inner_corner_support_cell(data, landing.x, landing.y, corner_low_cells):
		return true
	return false


func _would_place_corner_at(data: ChunkData, x: int, z: int) -> bool:
	if not _is_inner_corner_low_at(data, x, z):
		return false
	var wx: int = data.position.x * ChunkData.SIZE + x
	var wz: int = data.position.y * ChunkData.SIZE + z
	return _should_place_corner(wx, wz)


func _is_inner_corner_support_cell(
	data: ChunkData,
	x: int,
	z: int,
	corner_low_cells: Dictionary
) -> bool:
	var cell := Vector2i(x, z)
	for low_v in corner_low_cells.keys():
		var low: Vector2i = low_v
		var dirs: Array = corner_low_cells[low]
		if dirs.size() != 2:
			continue
		var da: Vector2i = dirs[0]
		var db: Vector2i = dirs[1]
		if cell == low + da or cell == low + db or cell == low + da + db:
			return true
	for d in _RAMP_DIRS:
		var lx: int = x - d.x
		var lz: int = z - d.y
		if not _would_place_corner_at(data, lx, lz):
			continue
		var low_h: float = _sample_height(data, lx, lz)
		var highs: Array = _high_step_dirs(data, lx, lz, low_h)
		for i in highs.size():
			for j in range(i + 1, highs.size()):
				var da: Vector2i = highs[i]
				var db: Vector2i = highs[j]
				if not _dirs_perpendicular(da, db):
					continue
				if not _is_inner_plateau_corner(data, lx, lz, da, db):
					continue
				if d == da or d == db:
					return true
	for ox in [-1, 1]:
		for oz in [-1, 1]:
			var lx2: int = x - ox
			var lz2: int = z - oz
			if _would_place_corner_at(data, lx2, lz2) \
					and _is_inner_plateau_corner(data, lx2, lz2, Vector2i(ox, 0), Vector2i(0, oz)):
				return true
	return false


func _apply_forced_ramps(data: ChunkData, planned: Dictionary, corner_low_cells: Dictionary) -> void:
	for key_v in data._worker_force_ramp.keys():
		var cell: Vector2i = key_v
		var e: Dictionary = data._worker_force_ramp[key_v]
		if bool(e.get("corner", false)):
			var da: Vector2i = e.get("dir", Vector2i.ZERO)
			var db: Vector2i = e.get("dir2", Vector2i.ZERO)
			if _corner_dirs_are_topologically_valid(data, cell.x, cell.y, da, db):
				corner_low_cells[cell] = [da, db]
				planned.erase(cell)
		else:
			var d: Vector2i = e.get("dir", Vector2i.ZERO)
			if _cardinal_dir_is_topologically_valid(data, cell.x, cell.y, d):
				planned[cell] = d
				corner_low_cells.erase(cell)


func _drop_opposing_cardinals(planned: Dictionary, data: ChunkData = null) -> void:
	var approach_owner := {}
	var drop: Dictionary = {}
	for cell_v in planned.keys():
		var cell: Vector2i = cell_v
		var d: Vector2i = planned[cell]
		var ap: Vector2i = cell + d
		if approach_owner.has(ap):
			drop[cell] = true
			drop[approach_owner[ap]] = true
		else:
			approach_owner[ap] = cell
		if planned.has(ap):
			var nd: Vector2i = planned[ap]
			if nd == Vector2i(-d.x, -d.y):
				drop[cell] = true
				drop[ap] = true
		var back := Vector2i(cell.x - d.x, cell.y - d.y)
		if planned.has(back):
			var bd: Vector2i = planned[back]
			if _dirs_perpendicular(d, bd):
				drop[cell] = true
				drop[back] = true
		if data != null and _has_opposing_plateau_across_valley(data, cell.x, cell.y, d):
			drop[cell] = true
	for c_v in drop.keys():
		planned.erase(c_v)
	_drop_cardinal_on_another_approach(planned)


## A cardinal's approach column is a floor. It must not also be a cardinal
## (that is the second slope immediately off the first landing).
func _drop_cardinal_on_another_approach(planned: Dictionary) -> void:
	var drop: Dictionary = {}
	for cell_v in planned.keys():
		var cell: Vector2i = cell_v
		var ap: Vector2i = cell + planned[cell]
		if planned.has(ap):
			drop[ap] = true
	for c_v in drop.keys():
		planned.erase(c_v)


func _has_opposing_plateau_across_valley(data: ChunkData, x: int, z: int, dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	var land_h: float = _surface_y_at(data, x, z)
	var seen_low := false
	for k in range(1, 9):
		var h: float = _sample_height(data, x + dir.x * k, z + dir.y * k)
		if absf(h - land_h) <= 0.15:
			return seen_low
		if h > land_h + 0.15:
			return false
		if land_h - h > 0.15:
			seen_low = true
	return false


func _is_plateau_back(data: ChunkData, x: int, z: int, toward_low: Vector2i, cell_h: float) -> bool:
	var bx: int = x - toward_low.x
	var bz: int = z - toward_low.y
	var bh: float = _sample_height(data, bx, bz)
	return bh >= cell_h - 0.15


func _cardinal_topology_dirs(data: ChunkData, x: int, z: int, cell_h: float) -> Array:
	if _has_player_build_at(data, x, z) or _column_blocks_ramp(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		var lx: int = x - d.x
		var lz: int = z - d.y
		if _has_player_build_at(data, lx, lz) or _column_blocks_ramp(data, lx, lz):
			continue
		var toward_low := Vector2i(-d.x, -d.y)
		if not _is_step_height(cell_h - _sample_height(data, lx, lz)):
			continue
		if _is_plateau_back(data, x, z, toward_low, cell_h):
			out.append(toward_low)
	return out


func _without_opposing_ramp_dirs(dirs: Array) -> Array:
	if dirs.size() >= 2:
		for i in dirs.size():
			for j in range(i + 1, dirs.size()):
				var a: Vector2i = dirs[i]
				var b: Vector2i = dirs[j]
				if a.x * b.x + a.y * b.y < 0:
					return []
	return dirs


func _cardinal_dir_is_topologically_valid(data: ChunkData, x: int, z: int, dir: Vector2i) -> bool:
	if dir == Vector2i.ZERO:
		return false
	var cell_h: float = _surface_y_at(data, x, z)
	return dir in _without_opposing_ramp_dirs(_cardinal_topology_dirs(data, x, z, cell_h))


func _corner_dirs_are_topologically_valid(
	data: ChunkData, x: int, z: int, d_a: Vector2i, d_b: Vector2i
) -> bool:
	if d_a == Vector2i.ZERO or d_b == Vector2i.ZERO or not _dirs_perpendicular(d_a, d_b):
		return false
	if _has_player_build_at(data, x, z) or _tile_type_at(data, x, z) == VoxelTypes.AIR:
		return false
	var low_h: float = _surface_y_at(data, x, z)
	var highs: Array = _high_step_dirs(data, x, z, low_h)
	return d_a in highs and d_b in highs and _is_inner_plateau_corner(data, x, z, d_a, d_b)


func _step_in_dirs(data: ChunkData, x: int, z: int, cell_h: float, world_x: int, world_z: int) -> Array:
	var out: Array = []
	for toward_low in _cardinal_topology_dirs(data, x, z, cell_h):
		if _should_place_ramp(world_x, world_z, toward_low, cell_h):
			out.append(toward_low)
	return _without_opposing_ramp_dirs(out)


func _pick_corner_dirs(data: ChunkData, x: int, z: int, planned: Dictionary) -> Array:
	var low_h: float = _surface_y_at(data, x, z)
	var world_x: int = data.position.x * ChunkData.SIZE + x
	var world_z: int = data.position.y * ChunkData.SIZE + z
	var step_outs: Array = _step_out_dirs(data, x, z, low_h, world_x, world_z)

	for i in step_outs.size():
		for j in range(i + 1, step_outs.size()):
			var d_a: Vector2i = step_outs[i]
			var d_b: Vector2i = step_outs[j]
			if _dirs_perpendicular(d_a, d_b):
				return [d_a, d_b]

	for d_out in step_outs:
		for d_in in _perpendicular_dirs(d_out):
			var from := Vector2i(x - d_in.x, z - d_in.y)
			if planned.get(from, Vector2i.ZERO) == d_in:
				return [d_out, d_in]
			var from_h: float = _sample_height(data, from.x, from.y)
			if _is_step_height(low_h - from_h):
				var from_world_x: int = data.position.x * ChunkData.SIZE + from.x
				var from_world_z: int = data.position.y * ChunkData.SIZE + from.y
				if _should_place_ramp(from_world_x, from_world_z, d_in, low_h):
					return [d_out, d_in]

	return []


func _append_ramp_quad(out_quads: Array, x: int, z: int, low_h: float, vox: int, entry: Dictionary, data: ChunkData = null) -> void:
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	var dir2: Vector2i = entry.get("dir2", Vector2i.ZERO)
	var is_corner: bool = dir2 != Vector2i.ZERO
	var flank_a := 0
	var flank_b := 0
	if not is_corner and data != null and dir != Vector2i.ZERO:
		var perp_a := Vector2i(-dir.y, dir.x)
		var perp_b := Vector2i(dir.y, -dir.x)
		flank_a = 1 if _flank_exposed(data, x, z, perp_a) else 0
		flank_b = 1 if _flank_exposed(data, x, z, perp_b) else 0
	var quad := {
		"x": x,
		"y": low_h,
		"z": z,
		"dim_x": 1.0,
		"dim_y": 1.0,
		"dim_z": 1.0,
		"ramp_dir_x": dir.x,
		"ramp_dir_z": dir.y,
		"ramp_dir2_x": dir2.x,
		"ramp_dir2_z": dir2.y,
		"flank_a": flank_a,
		"flank_b": flank_b,
		"uv_w": 1.0,
		"uv_h": 1.0,
		"type": vox,
		"face_code": FACE_RAMP_CORNER if is_corner else FACE_RAMP,
	}
	out_quads.append(quad)


func _flank_exposed(data: ChunkData, x: int, z: int, side: Vector2i) -> bool:
	var self_h: float = _surface_y_at(data, x, z)
	var nh: float = _sample_height(data, x + side.x, z + side.y)
	return self_h - nh > 0.1


func _rehydrate_ramp_map_from_quads(data: ChunkData, quads: Array) -> void:
	sync_ramp_map_to_mesh(data, quads)


func _is_concave_corner_cell(data: ChunkData, x: int, z: int, fill_h: float) -> bool:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		if _tile_type_at(data, x, z) == VoxelTypes.AIR:
			return true
		return not is_equal_approx(_surface_y_at(data, x, z), fill_h)
	var sh: float = _sample_height(data, x, z)
	return sh < 0.0 or not is_equal_approx(sh, fill_h)


func _sample_tile_type(data: ChunkData, x: int, z: int) -> int:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		return _tile_type_at(data, x, z)
	# Worker path: never touch live world/registries for halo neighbors.
	return VoxelTypes.AIR


const _CONCAVE_L_PATTERNS := [
	{"arms": [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)], "leg_x": 1, "leg_z": 1},
	{"arms": [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1)], "leg_x": -1, "leg_z": 1},
	{"arms": [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(-1, 1)], "leg_x": 1, "leg_z": -1},
	{"arms": [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], "leg_x": -1, "leg_z": -1},
]


func _find_concave_corner_cells(_data: ChunkData) -> Dictionary:
	return {}


func _emit_concave_corner_prisms(_data: ChunkData, _out_quads: Array, _concave_cells: Dictionary) -> void:
	return


func _find_corner_low_cells(data: ChunkData) -> Dictionary:
	var result: Dictionary = {}
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _has_player_build_at(data, x, z) or _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var step_outs: Array = _high_step_dirs(data, x, z, low_h)
			if step_outs.size() < 2:
				continue
			var picked: Array = []
			for i in step_outs.size():
				for j in range(i + 1, step_outs.size()):
					var d_a: Vector2i = step_outs[i]
					var d_b: Vector2i = step_outs[j]
					if not _dirs_perpendicular(d_a, d_b):
						continue
					if not _is_inner_plateau_corner(data, x, z, d_a, d_b):
						continue
					picked = [d_a, d_b]
					break
				if not picked.is_empty():
					break
			if not picked.is_empty():
				var wx: int = data.position.x * ChunkData.SIZE + x
				var wz: int = data.position.y * ChunkData.SIZE + z
				if _should_place_corner(wx, wz):
					result[Vector2i(x, z)] = picked
	return result


func _emit_ramps(data: ChunkData, out_quads: Array, concave_cells: Dictionary = {}) -> void:
	data.ramp_map.clear()
	var planned: Dictionary = {}
	var corner_low_cells: Dictionary = _find_corner_low_cells(data)

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell):
				continue
			if _has_player_build_at(data, x, z):
				continue
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var cell_h: float = _surface_y_at(data, x, z)
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_ins: Array = _step_in_dirs(data, x, z, cell_h, world_x, world_z)
			if not step_ins.is_empty():
				planned[cell] = step_ins[0]
	_drop_opposing_cardinals(planned, data)
	_apply_forced_ramps(data, planned, corner_low_cells)
	_drop_opposing_cardinals(planned, data)

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell):
				continue
			if _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var vox := _tile_type_at(data, x, z)
			if vox == VoxelTypes.AIR:
				continue

			if not planned.has(cell):
				continue

			var d: Vector2i = planned[cell]
			if _cardinal_blocked_by_inner_corner(data, cell, d, corner_low_cells):
				continue
			data.set_ramp_cardinal(x, z, d)
			_append_ramp_quad(out_quads, x, z, low_h, vox, {
				"dir": d,
				"dir2": Vector2i.ZERO,
			}, data)
			_clear_ramp_approach_block(data, x, z, d, planned)

	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			if not corner_low_cells.has(cell):
				continue
			var corner_dirs: Array = corner_low_cells[cell]
			if corner_dirs.size() != 2:
				continue
			var d_a: Vector2i = corner_dirs[0]
			var d_b: Vector2i = corner_dirs[1]
			var vox_corner: int = _tile_type_at(data, x, z)
			data.set_ramp_corner(x, z, d_a, d_b)
			_append_ramp_quad(out_quads, x, z, low_h, vox_corner, {
				"dir": d_a,
				"dir2": d_b,
			}, data)


func _quad_intersects_rect(q: Dictionary, rect: Rect2i) -> bool:
	var qx0 := float(q.get("x", 0.0))
	var qz0 := float(q.get("z", 0.0))
	var qx1 := qx0 + float(q.get("dim_x", 1.0))
	var qz1 := qz0 + float(q.get("dim_z", 1.0))
	var rx0 := float(rect.position.x)
	var rz0 := float(rect.position.y)
	var rx1 := rx0 + float(rect.size.x)
	var rz1 := rz0 + float(rect.size.y)
	return qx0 < rx1 and qx1 > rx0 and qz0 < rz1 and qz1 > rz0


func _quad_local_rect(q: Dictionary) -> Rect2i:
	var x := int(floor(float(q.get("x", 0.0))))
	var z := int(floor(float(q.get("z", 0.0))))
	var dx := maxi(1, int(round(float(q.get("dim_x", 1.0)))))
	var dz := maxi(1, int(round(float(q.get("dim_z", 1.0)))))
	return Rect2i(x, z, dx, dz)


func _copy_quad_rect(q: Dictionary, x: int, z: int, dx: int, dz: int) -> Dictionary:
	var nq: Dictionary = q.duplicate()
	nq["x"] = x
	nq["z"] = z
	nq["dim_x"] = float(dx)
	nq["dim_z"] = float(dz)
	var fc: int = int(q.get("face_code", FACE_TOP))
	if fc == FACE_TOP or fc == 2:
		nq["uv_w"] = float(dx)
		nq["uv_h"] = float(dz)
	elif fc == FACE_NEG_X or fc == FACE_POS_X:
		nq["uv_w"] = float(dz)
		nq["uv_h"] = 1.0
	else:
		nq["uv_w"] = float(dx)
		nq["uv_h"] = 1.0
	return nq


func _clip_quad_outside_rect(q: Dictionary, hole: Rect2i) -> Array:
	if not _quad_intersects_rect(q, hole):
		return [q]
	var fc: int = int(q.get("face_code", FACE_TOP))
	if fc >= FACE_RAMP:
		return []
	var qr := _quad_local_rect(q)
	var hx0 := maxi(qr.position.x, hole.position.x)
	var hz0 := maxi(qr.position.y, hole.position.y)
	var hx1 := mini(qr.position.x + qr.size.x, hole.position.x + hole.size.x)
	var hz1 := mini(qr.position.y + qr.size.y, hole.position.y + hole.size.y)
	if hx0 >= hx1 or hz0 >= hz1:
		return [q]
	if hx0 == qr.position.x and hz0 == qr.position.y \
			and hx1 == qr.position.x + qr.size.x and hz1 == qr.position.y + qr.size.y:
		return []
	var out: Array = []
	var qx0 := qr.position.x
	var qz0 := qr.position.y
	var qx1 := qr.position.x + qr.size.x
	var qz1 := qr.position.y + qr.size.y
	if qx0 < hx0:
		out.append(_copy_quad_rect(q, qx0, qz0, hx0 - qx0, qz1 - qz0))
	if hx1 < qx1:
		out.append(_copy_quad_rect(q, hx1, qz0, qx1 - hx1, qz1 - qz0))
	var mx0 := maxi(qx0, hx0)
	var mx1 := mini(qx1, hx1)
	if mx1 > mx0:
		if qz0 < hz0:
			out.append(_copy_quad_rect(q, mx0, qz0, mx1 - mx0, hz0 - qz0))
		if hz1 < qz1:
			out.append(_copy_quad_rect(q, mx0, hz1, mx1 - mx0, qz1 - hz1))
	return out


func _cell_in_rect(x: int, z: int, rect: Rect2i) -> bool:
	return x >= rect.position.x and x < rect.position.x + rect.size.x \
		and z >= rect.position.y and z < rect.position.y + rect.size.y


func _clear_ramp_map_in_rect(data: ChunkData, rect: Rect2i) -> void:
	var to_erase: Array = []
	for key_variant in data.ramp_map.keys():
		var key: Vector2i = key_variant
		if _cell_in_rect(key.x, key.y, rect):
			to_erase.append(key)
	for key_variant in to_erase:
		data.ramp_map.erase(key_variant)


func _find_concave_corner_cells_in_rect(data: ChunkData, rect: Rect2i) -> Dictionary:
	var full := _find_concave_corner_cells(data)
	var out: Dictionary = {}
	for cell_variant in full.keys():
		var cell: Vector2i = cell_variant
		if _cell_in_rect(cell.x, cell.y, rect):
			out[cell] = full[cell]
	return out


func _emit_ramps_in_rect(
	data: ChunkData,
	out_quads: Array,
	concave_cells: Dictionary,
	rect: Rect2i
) -> void:
	var planned: Dictionary = {}
	var corner_low_cells: Dictionary = {}
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			if _has_player_build_at(data, x, z) or _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var highs: Array = _high_step_dirs(data, x, z, low_h)
			if highs.size() >= 2:
				for i in highs.size():
					for j in range(i + 1, highs.size()):
						var d_a: Vector2i = highs[i]
						var d_b: Vector2i = highs[j]
						if not _dirs_perpendicular(d_a, d_b):
							continue
						if _is_inner_plateau_corner(data, x, z, d_a, d_b):
							var wx: int = data.position.x * ChunkData.SIZE + x
							var wz: int = data.position.y * ChunkData.SIZE + z
							if _should_place_corner(wx, wz):
								corner_low_cells[Vector2i(x, z)] = [d_a, d_b]
							break
					if corner_low_cells.has(Vector2i(x, z)):
						break

	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell):
				continue
			if _has_player_build_at(data, x, z):
				continue
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var cell_h: float = _surface_y_at(data, x, z)
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_ins: Array = _step_in_dirs(data, x, z, cell_h, world_x, world_z)
			if not step_ins.is_empty():
				planned[cell] = step_ins[0]
	_drop_opposing_cardinals(planned, data)
	_apply_forced_ramps(data, planned, corner_low_cells)
	_drop_opposing_cardinals(planned, data)

	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var vox := _tile_type_at(data, x, z)
			if vox == VoxelTypes.AIR or not planned.has(cell):
				continue
			var d: Vector2i = planned[cell]
			if _cardinal_blocked_by_inner_corner(data, cell, d, corner_low_cells):
				continue
			data.set_ramp_cardinal(x, z, d)
			_append_ramp_quad(out_quads, x, z, low_h, vox, {
				"dir": d,
				"dir2": Vector2i.ZERO,
			}, data)
			_clear_ramp_approach_block(data, x, z, d, planned)

	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			if not corner_low_cells.has(cell):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var corner_dirs: Array = corner_low_cells[cell]
			if corner_dirs.size() != 2:
				continue
			var d_a: Vector2i = corner_dirs[0]
			var d_b: Vector2i = corner_dirs[1]
			var vox_corner: int = _tile_type_at(data, x, z)
			data.set_ramp_corner(x, z, d_a, d_b)
			_append_ramp_quad(out_quads, x, z, low_h, vox_corner, {
				"dir": d_a,
				"dir2": d_b,
			}, data)


func _emit_water_lids_region(
	data: ChunkData,
	out_quads: Array,
	x0: int,
	z0: int,
	x1: int,
	z1: int
) -> void:
	if data == null or data._worker_water_lid.is_empty():
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	for x in range(x0, x1):
		for z in range(z0, z1):
			if not data._worker_water_lid.has(Vector2i(x, z)):
				continue
			var sy: float = float(data._worker_water_lid[Vector2i(x, z)])
			if sy <= 0.01:
				continue
			var top: float = _surface_y_at(data, x, z) + layer
			if sy <= top + 0.01:
				continue
			_append_voxel_face(
				out_quads, float(x), top, float(z),
				1.0, (sy - top) / layer, 1.0, 1.0, 1.0, VoxelTypes.WATER, FACE_TOP
			)


func _emit_dug_strata_region(
	_data: ChunkData,
	_out_quads: Array,
	_x0: int,
	_z0: int,
	_x1: int,
	_z1: int
) -> void:
	# Deep digs only lower surface_map. Do not emit leftover FACE_TOPs at
	# mid-heights — that kept the old terrain visible in the pit. The new
	# floor is the column FACE_TOP; pit walls are neighbor side faces.
	return


func _natural_surface_y(data: ChunkData, x: int, z: int) -> float:
	if data != null and data.has_method("get_natural_surface_y"):
		return float(data.get_natural_surface_y(x, z))
	if data == null or data.world == null:
		return 0.0
	var wx: int = data.position.x * ChunkData.SIZE + x
	var wz: int = data.position.y * ChunkData.SIZE + z
	return data.world.get_surface_height_worker(float(wx), float(wz), 0.0)


func _emit_build_strata_region(
	data: ChunkData,
	out_quads: Array,
	x0: int,
	z0: int,
	x1: int,
	z1: int
) -> void:
	if data.world == null:
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return
	for x in range(x0, x1):
		for z in range(z0, z1):
			if _skips_greedy_surface_cell(data, x, z):
				continue
			var delta: float = data.get_worker_height_delta(x, z)
			if delta <= layer * 0.15:
				continue
			var cur_h: float = _surface_y_at(data, x, z)
			var natural_h: float = _natural_surface_y(data, x, z)
			var layers_built: int = maxi(1, int(round(delta / layer)))
			var tile: int = data.get_worker_build_tile(x, z)
			if tile < 0:
				tile = _tile_type_at(data, x, z)
			if tile == VoxelTypes.AIR:
				continue
			for step in range(1, layers_built):
				var layer_y: float = natural_h + float(step) * layer
				if layer_y >= cur_h - layer * 0.05:
					break
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, tile, FACE_TOP)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_NEG_X)
				_append_voxel_face(out_quads, float(x) + 1.0, layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_POS_X)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_NEG_Z)
				_append_voxel_face(out_quads, float(x), layer_y, float(z) + 1.0, 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_POS_Z)


func _greedy_mesh_plane_region(
	data: ChunkData,
	normal_dir: Vector3i,
	face_code: int,
	out_quads: Array,
	x0: int,
	z0: int,
	x1: int,
	z1: int
) -> void:
	if normal_dir.y != 0:
		if normal_dir.y > 0:
			_emit_waved_tops(data, out_quads, x0, z0, x1, z1)
		return

	_emit_surface_side_walls_region(data, normal_dir, face_code, out_quads, x0, z0, x1, z1)


func _side_wall_spec(data: ChunkData, x: int, z: int, nx: int, nz: int, toward_high: Vector2i) -> Dictionary:
	if _skips_greedy_surface_cell(data, x, z, false):
		return {}
	var curr_h: float = _surface_y_at(data, x, z)
	var curr_t: int = _tile_type_at(data, x, z)
	if curr_t == VoxelTypes.AIR:
		return {}
	var neighbor_h: float = _sample_height(data, nx, nz)
	var diff: float = curr_h - neighbor_h
	var layer: float = _WorldSettings.get_active().layer_height()
	if nx >= 0 and nx < ChunkData.SIZE and nz >= 0 and nz < ChunkData.SIZE \
			and _is_ramp_landing(data, nx, nz) and absf(diff) <= 0.15:
		var rdir: Vector2i = data.get_ramp_entry(nx, nz).get("dir", Vector2i.ZERO)
		var to_ramp := Vector2i(nx - x, nz - z)
		if rdir != Vector2i.ZERO and to_ramp.x * rdir.x + to_ramp.y * rdir.y == 0 \
				and not (_is_ramp_landing(data, x, z) \
				and data.get_ramp_dir(x, z) == rdir):
			var y0s: float = neighbor_h
			var y1s: float = curr_h + layer
			if y1s - y0s > 0.05:
				return {
					"h": curr_h,
					"t": curr_t,
					"y": y0s,
					"dim_y": (y1s - y0s) / layer,
				}
	elif (nx < 0 or nx >= ChunkData.SIZE or nz < 0 or nz >= ChunkData.SIZE) \
			and absf(diff) <= 0.15:
		# is re-derived deterministically from reachable samples. Non-ramp
		# columns always fill — any far cut exposes this face, and a solid far
		# cell just buries the quad. Ramp-owned columns fill only against a
		# crossing far slope: a parallel far cardinal shares this column's
		# slope profile, so that seam must stay unfilled.
		var fill_cut := true
		if _is_ramp_landing(data, x, z):
			var far_dir := _halo_landing_dir(data, nx, nz, neighbor_h)
			fill_cut = far_dir != Vector2i.ZERO \
					and far_dir != data.get_ramp_dir(x, z)
		if fill_cut:
			var y0b: float = neighbor_h
			var y1b: float = curr_h + layer
			if y1b - y0b > 0.05:
				return {
					"h": curr_h,
					"t": curr_t,
					"y": y0b,
					"dim_y": (y1b - y0b) / layer,
				}
	if diff <= 0.1:
		return {}
	if _ramp_covers_drop(data, nx, nz, toward_high):
		return {}
	if _is_ramp_landing(data, x, z) and diff <= layer * 1.2:
		return {}
	var y0: float = neighbor_h + layer
	var y1: float = curr_h + layer
	if _is_ramp_landing(data, x, z):
		y1 = curr_h
	if y1 - y0 <= 0.05:
		return {}
	return {
		"h": curr_h,
		"t": curr_t,
		"y": y0,
		"dim_y": (y1 - y0) / layer,
	}


func _halo_landing_dir(data: ChunkData, nx: int, nz: int, n_h: float) -> Vector2i:
	if n_h <= -9000.0:
		return Vector2i.ZERO
	var layer: float = _WorldSettings.get_active().layer_height()
	if data._worker_water_lid.has(Vector2i(nx, nz)):
		return Vector2i.ZERO
	if absf(_halo_build_delta(data, nx, nz)) > layer * 0.08:
		return Vector2i.ZERO
	var wx: int = data.position.x * ChunkData.SIZE + nx
	var wz: int = data.position.y * ChunkData.SIZE + nz
	var dirs: Array = []
	for d in _RAMP_DIRS:
		var t := Vector2i(-d.x, -d.y)
		if data._worker_water_lid.has(Vector2i(nx + t.x, nz + t.y)):
			continue
		if absf(_halo_build_delta(data, nx + t.x, nz + t.y)) > layer * 0.08:
			continue
		if not _is_step_height(n_h - _sample_height(data, nx + t.x, nz + t.y)):
			continue
		if not _is_plateau_back(data, nx, nz, t, n_h):
			continue
		if not _should_place_ramp(wx, wz, t, n_h):
			continue
		dirs.append(t)
	dirs = _without_opposing_ramp_dirs(dirs)
	if dirs.is_empty():
		return Vector2i.ZERO
	return dirs[0]


func _halo_build_delta(data: ChunkData, lx: int, lz: int) -> float:
	if lx >= 0 and lx < ChunkData.SIZE and lz >= 0 and lz < ChunkData.SIZE:
		return data.get_worker_height_delta(lx, lz)
	if data._worker_halo_height_delta.is_empty():
		return 0.0
	var ix: int = lx + ChunkData.HALO
	var iz: int = lz + ChunkData.HALO
	if ix < 0 or iz < 0 or ix >= data._worker_halo_height_delta.size():
		return 0.0
	var col: Array = data._worker_halo_height_delta[ix]
	if iz < 0 or iz >= col.size():
		return 0.0
	return float(col[iz])


func _emit_surface_side_walls_region(
	data: ChunkData,
	normal_dir: Vector3i,
	face_code: int,
	out_quads: Array,
	x0: int,
	z0: int,
	x1: int,
	z1: int
) -> void:
	var dx = normal_dir.x
	var dz = normal_dir.z
	if dx == 0 and dz == 0:
		return
	if NATIVE_SIDES and _native_mesher != null and data._side_ops == null:
		data._side_ops = PackedFloat64Array()
		data._side_heights = PackedFloat64Array()
		_emit_surface_side_walls_region(data, normal_dir, face_code, out_quads, x0, z0, x1, z1)
		var ops: PackedFloat64Array = data._side_ops
		var hs: PackedFloat64Array = data._side_heights
		data._side_ops = null
		data._side_heights = null
		if not ops.is_empty():
			out_quads.append_array(_native_mesher.side_ops(ops, hs, TerrainLook.STEPS_PER_BLOCK, _WorldSettings.get_active().layer_height()))
		return
	if abs(dx) == 1:
		for x in range(x0, x1):
			for z in range(z0, z1):
				_emit_one_side(data, out_quads, x, z, x + dx, z, face_code)
	elif abs(dz) == 1:
		for z in range(z0, z1):
			for x in range(x0, x1):
				_emit_one_side(data, out_quads, x, z, x, z + dz, face_code)


func _emit_one_side(
	data: ChunkData, out_quads: Array, x: int, z: int, nx: int, nz: int, face_code: int
) -> void:
	var spec: Dictionary = _side_wall_spec(data, x, z, nx, nz, Vector2i(x - nx, z - nz))
	var inside := nx >= 0 and nx < ChunkData.SIZE and nz >= 0 and nz < ChunkData.SIZE
	var ramp_here := _is_ramp_landing(data, x, z) or (inside and _is_ramp_landing(data, nx, nz))
	if ramp_here:
		if not spec.is_empty():
			_append_side_plain(data, out_quads, x, z, spec, face_code)
		return
	var neighbor_known := inside or data.get_halo_surface_y(nx, nz) > -9000.0
	if spec.is_empty():
		if neighbor_known:
			_emit_wave_lip(data, out_quads, x, z, nx, nz, face_code)
		return
	if not neighbor_known:
		_append_side_plain(data, out_quads, x, z, spec, face_code)
		return
	_emit_side_strips(data, out_quads, x, z, nx, nz, face_code, int(spec.t))


# Native side walls: the script still decides every side cell; the quads are built
# by CsNativeMesher.side_ops in the same order. CS_NATIVE_SIDES=0 disables.
static var NATIVE_SIDES: bool = OS.get_environment("CS_NATIVE_SIDES") != "0"


func _append_side_plain(data: ChunkData, out_quads: Array, x: int, z: int, spec: Dictionary, face_code: int) -> void:
	if data._side_ops != null:
		data._side_ops.append_array([0.0, float(x), float(z), 0.0, float(face_code), float(int(spec.t)), float(spec.y), float(spec.dim_y)])
		return
	out_quads.append({
		"x": x,
		"y": float(spec.y),
		"z": z,
		"dim_x": 1.0,
		"dim_y": float(spec.dim_y),
		"dim_z": 1.0,
		"uv_w": 1.0,
		"uv_h": float(spec.dim_y),
		"type": int(spec.t),
		"face_code": face_code,
	})


func _record_side_strip_op(data: ChunkData, x: int, z: int, nx: int, nz: int, face_code: int, tile: int) -> void:
	var n: int = TerrainLook.STEPS_PER_BLOCK
	var along_x := nz != z
	var hi := PackedFloat64Array()
	var lo := PackedFloat64Array()
	hi.resize(n)
	lo.resize(n)
	var memo_rep := PackedInt32Array()
	for m in n:
		var rep := TerrainLook.wave_rep_micro(m)
		var hit := memo_rep.find(rep)
		memo_rep.append(rep)
		if hit >= 0:
			hi[m] = hi[hit]
			lo[m] = lo[hit]
			continue
		if along_x:
			hi[m] = _column_micro_top(data, x, z, m, (n - 1) if nz > z else 0)
			lo[m] = _column_micro_top(data, nx, nz, m, 0 if nz > z else (n - 1))
		else:
			hi[m] = _column_micro_top(data, x, z, (n - 1) if nx > x else 0, m)
			lo[m] = _column_micro_top(data, nx, nz, 0 if nx > x else (n - 1), m)
	data._side_ops.append_array([1.0, float(x), float(z), 1.0 if along_x else 0.0, float(face_code), float(tile), 0.0, 0.0])
	data._side_heights.append_array(hi)
	data._side_heights.append_array(lo)


func _emit_side_strips(
	data: ChunkData, out_quads: Array, x: int, z: int, nx: int, nz: int, face_code: int, tile: int
) -> void:
	if data._side_ops != null:
		_record_side_strip_op(data, x, z, nx, nz, face_code, tile)
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	var n: int = TerrainLook.STEPS_PER_BLOCK
	var along_x := nz != z
	# _column_micro_top depends on m only via wave_rep_micro(m): memo per rep.
	var memo_rep := PackedInt32Array()
	var memo_hi := PackedFloat64Array()
	var memo_lo := PackedFloat64Array()
	for m in n:
		var y_hi: float
		var y_lo: float
		var rep := TerrainLook.wave_rep_micro(m)
		var hit := memo_rep.find(rep)
		if hit >= 0:
			y_hi = memo_hi[hit]
			y_lo = memo_lo[hit]
		else:
			if along_x:
				var mz_hi := (n - 1) if nz > z else 0
				var mz_lo := 0 if nz > z else (n - 1)
				y_hi = _column_micro_top(data, x, z, m, mz_hi)
				y_lo = _column_micro_top(data, nx, nz, m, mz_lo)
			else:
				var mx_hi := (n - 1) if nx > x else 0
				var mx_lo := 0 if nx > x else (n - 1)
				y_hi = _column_micro_top(data, x, z, mx_hi, m)
				y_lo = _column_micro_top(data, nx, nz, mx_lo, m)
			memo_rep.append(rep)
			memo_hi.append(y_hi)
			memo_lo.append(y_lo)
		if y_hi - y_lo <= 0.02:
			continue
		var qx := float(x)
		var qz := float(z)
		var dw := 1.0
		var dd := 1.0
		if along_x:
			qx = float(x) + float(m) / float(n)
			dw = 1.0 / float(n)
		else:
			qz = float(z) + float(m) / float(n)
			dd = 1.0 / float(n)
		var strip := {
			"x": qx,
			"y": y_lo,
			"z": qz,
			"dim_x": dw,
			"dim_y": (y_hi - y_lo) / layer,
			"dim_z": dd,
			"uv_w": dw if along_x else dd,
			"uv_h": (y_hi - y_lo) / layer,
			"type": tile,
			"face_code": face_code,
		}
		if y_hi - y_lo <= layer * 0.5 + 0.001:
			strip["wave_riser"] = true
		out_quads.append(strip)


func _emit_wave_lip(
	data: ChunkData, out_quads: Array, x: int, z: int, nx: int, nz: int, face_code: int
) -> void:
	if _skips_greedy_surface_cell(data, x, z) or _skips_greedy_surface_cell(data, nx, nz):
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	var base_h: float = _surface_y_at(data, x, z)
	var base_n: float = _surface_y_at(data, nx, nz)
	if absf(base_h - base_n) > layer * 0.2:
		return
	if _tile_type_at(data, x, z) == VoxelTypes.AIR or _tile_type_at(data, nx, nz) == VoxelTypes.AIR:
		return
	_emit_side_strips(data, out_quads, x, z, nx, nz, face_code, _tile_type_at(data, x, z))


# The micro top depends on mx/mz only through wave_rep_micro, and column data does
# not change during one mesh job, so side walls reuse it. CS_SIDE_MEMO=0 disables.
static var SIDE_TOP_MEMO: bool = OS.get_environment("CS_SIDE_MEMO") != "0"


func _column_micro_top(data: ChunkData, col_x: int, col_z: int, mx: int, mz: int) -> float:
	var memo = data._mesh_job_top_memo
	if memo == null:
		return _column_micro_top_uncached(data, col_x, col_z, mx, mz)
	var key := Vector4i(col_x, col_z, TerrainLook.wave_rep_micro(mx), TerrainLook.wave_rep_micro(mz))
	var hit = memo.get(key)
	if hit != null:
		return hit
	var v := _column_micro_top_uncached(data, col_x, col_z, mx, mz)
	memo[key] = v
	return v


func _column_micro_top_uncached(data: ChunkData, col_x: int, col_z: int, mx: int, mz: int) -> float:
	var base: float = _sample_height(data, col_x, col_z)
	var layer: float = _WorldSettings.get_active().layer_height()
	if base < -9000.0:
		return base
	var wx := data.position.x * ChunkData.SIZE + col_x
	var wz := data.position.y * ChunkData.SIZE + col_z
	var n: float = float(TerrainLook.STEPS_PER_BLOCK)
	var px := float(wx) + (float(TerrainLook.wave_rep_micro(mx)) + 0.5) / n
	var pz := float(wz) + (float(TerrainLook.wave_rep_micro(mz)) + 0.5) / n
	var off := 0
	if TerrainLook.column_waves(_tile_type_at(data, col_x, col_z)):
		off = TerrainLook.offset_steps(px, pz) + data.rim_plane_steps(wx, wz, TerrainLook.wave_rep_micro(mx), TerrainLook.wave_rep_micro(mz), base)
	return base + layer + float(off) * (layer / n)


# Optional native mesher (GDExtension CsNativeMesher, see native/). Absent DLL or
# CS_NATIVE_MESH=0 keeps the GDScript mesher. The object holds no state.
var _native_mesher: RefCounted = _make_native_mesher()


static func _make_native_mesher() -> RefCounted:
	if OS.get_environment("CS_NATIVE_MESH") == "0":
		return null
	if not ClassDB.class_exists(&"CsNativeMesher"):
		return null
	return ClassDB.instantiate(&"CsNativeMesher") as RefCounted


func native_mesher_active() -> bool:
	return _native_mesher != null


var _native_calls_mutex := Mutex.new()
var _native_calls := 0


func native_mesher_calls() -> int:
	_native_calls_mutex.lock()
	var c := _native_calls
	_native_calls_mutex.unlock()
	return c


func _emit_waved_tops_native(data: ChunkData, out_quads: Array, x0: int, z0: int, x1: int, z1: int) -> void:
	var n: int = TerrainLook.STEPS_PER_BLOCK
	var cw := x1 - x0
	var ch := z1 - z0
	if cw <= 0 or ch <= 0 or n <= 0:
		return
	var nn := n * n
	var height_bound := float(_WorldSettings.get_active().chunk_height_bound())
	var tiles := PackedInt32Array()
	var atlas := PackedInt32Array()
	var base_keys := PackedInt32Array()
	var col_steps := PackedInt32Array()
	tiles.resize(cw * ch)
	atlas.resize(cw * ch * 2)
	base_keys.resize(cw * ch)
	col_steps.resize(cw * ch * nn)
	var reps := PackedInt32Array()
	reps.resize(n)
	var top_layer: float = _WorldSettings.get_active().layer_height()
	# Side walls reuse these column tops (same formula as _column_micro_top).
	var prefill = data._mesh_job_top_memo if NATIVE_SIDES else null
	var ureps := PackedInt32Array()
	for m in n:
		reps[m] = TerrainLook.wave_rep_micro(m)
		if ureps.find(reps[m]) < 0:
			ureps.append(reps[m])
	for lz in ch:
		for lx in cw:
			var col_x := x0 + lx
			var col_z := z0 + lz
			var ti := lz * cw + lx
			var usable := not _skips_greedy_surface_cell(data, col_x, col_z)
			var sy := _surface_y_at(data, col_x, col_z) if usable else 0.0
			var vox := _tile_type_at(data, col_x, col_z) if usable else VoxelTypes.AIR
			if (not usable) or sy >= height_bound or vox == VoxelTypes.AIR:
				tiles[ti] = -1
				continue
			tiles[ti] = vox
			var at: Vector2i = _column_face_atlas(data, col_x, col_z, vox, FACE_TOP)
			atlas[ti * 2] = at.x
			atlas[ti * 2 + 1] = at.y
			base_keys[ti] = int(round(sy * 1000.0))
			if not TerrainLook.column_waves(vox):
				continue
			var plane_wx := data.position.x * ChunkData.SIZE + col_x
			var plane_wz := data.position.y * ChunkData.SIZE + col_z
			for rz in ureps:
				for rx in ureps:
					var px := float(plane_wx) + (float(rx) + 0.5) / float(n)
					var pz := float(plane_wz) + (float(rz) + 0.5) / float(n)
					col_steps[ti * nn + rz * n + rx] = TerrainLook.offset_steps(px, pz) \
							+ data.rim_plane_steps(plane_wx, plane_wz, rx, rz, sy)
					if prefill != null and sy >= -9000.0 and col_x >= 0 and col_x < ChunkData.SIZE and col_z >= 0 and col_z < ChunkData.SIZE:
						prefill[Vector4i(col_x, col_z, rx, rz)] = sy + top_layer + float(col_steps[ti * nn + rz * n + rx]) * (top_layer / float(n))
	_native_calls_mutex.lock()
	_native_calls += 1
	_native_calls_mutex.unlock()
	out_quads.append_array(_native_mesher.waved_tops(
		x0, z0, cw, ch, n, _WorldSettings.get_active().layer_height(),
		tiles, atlas, base_keys, col_steps, reps,
		PackedInt32Array([FACE_TOP, FACE_NEG_X, FACE_POS_X, FACE_NEG_Z, FACE_POS_Z])))

func _emit_waved_tops(data: ChunkData, out_quads: Array, x0: int, z0: int, x1: int, z1: int) -> void:
	if _native_mesher != null:
		_emit_waved_tops_native(data, out_quads, x0, z0, x1, z1)
		return
	var n: int = TerrainLook.STEPS_PER_BLOCK
	var cw := x1 - x0
	var ch := z1 - z0
	if cw <= 0 or ch <= 0 or n <= 0:
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	var step: float = layer / float(n)
	var w := cw * n
	var h := ch * n
	var open := PackedByteArray()
	var steps := PackedInt32Array()
	var bases := PackedInt32Array()
	open.resize(w * h)
	steps.resize(w * h)
	bases.resize(w * h)
	var tiles: Array = []
	tiles.resize(cw * ch)
	var atlas: Array = []
	atlas.resize(cw * ch)
	# Per-column memo: wave_rep_micro() collapses the n micro indices to a few
	# representative positions, so offset/rim steps only vary by rep pair.
	var reps := PackedInt32Array()
	reps.resize(n)
	for m in n:
		reps[m] = TerrainLook.wave_rep_micro(m)
	var memo := PackedInt32Array()
	memo.resize(n * n)
	var memo_set := PackedByteArray()
	memo_set.resize(n * n)
	for lz in ch:
		for lx in cw:
			var col_x := x0 + lx
			var col_z := z0 + lz
			var ti := lz * cw + lx
			var usable := not _skips_greedy_surface_cell(data, col_x, col_z)
			var sy := _surface_y_at(data, col_x, col_z) if usable else 0.0
			var vox := _tile_type_at(data, col_x, col_z) if usable else VoxelTypes.AIR
			if (not usable) or sy >= float(_WorldSettings.get_active().chunk_height_bound()) or vox == VoxelTypes.AIR:
				tiles[ti] = -1
				atlas[ti] = Vector2i.ZERO
			else:
				tiles[ti] = vox
				atlas[ti] = _column_face_atlas(data, col_x, col_z, vox, FACE_TOP)
			var base_key := int(round(sy * 1000.0))
			var plane_wx := data.position.x * ChunkData.SIZE + col_x
			var plane_wz := data.position.y * ChunkData.SIZE + col_z
			var col_open := int(tiles[ti]) >= 0
			var col_waves := col_open and TerrainLook.column_waves(vox)
			if col_waves:
				memo_set.fill(0)
			for mz in n:
				for mx in n:
					var idx := (lz * n + mz) * w + (lx * n + mx)
					if not col_open:
						open[idx] = 0
						steps[idx] = 0
						bases[idx] = 0
					else:
						open[idx] = 1
						if col_waves:
							var rx: int = reps[mx]
							var rz: int = reps[mz]
							var mk := rz * n + rx
							if memo_set[mk] == 0:
								var px := float(plane_wx) + (float(rx) + 0.5) / float(n)
								var pz := float(plane_wz) + (float(rz) + 0.5) / float(n)
								memo[mk] = TerrainLook.offset_steps(px, pz) + data.rim_plane_steps(plane_wx, plane_wz, rx, rz, sy)
								memo_set[mk] = 1
							steps[idx] = memo[mk]
						else:
							steps[idx] = 0
						bases[idx] = base_key
	var visited := PackedByteArray()
	visited.resize(w * h)
	for iz in h:
		for ix in w:
			var idx := iz * w + ix
			if visited[idx] != 0 or open[idx] == 0:
				continue
			var col_lx := ix / n
			var col_lz := iz / n
			var ti := col_lz * cw + col_lx
			var want_step := steps[idx]
			var want_base := bases[idx]
			var want_tile := int(tiles[ti])
			var want_atlas: Vector2i = atlas[ti]
			var run_x := 1
			while ix + run_x < w:
				var j := iz * w + (ix + run_x)
				if visited[j] != 0 or open[j] == 0 or steps[j] != want_step or bases[j] != want_base:
					break
				var tix := (iz / n) * cw + ((ix + run_x) / n)
				if int(tiles[tix]) != want_tile or atlas[tix] != want_atlas:
					break
				run_x += 1
			var run_z := 1
			var growing := true
			while growing and iz + run_z < h:
				for k in run_x:
					var j2 := (iz + run_z) * w + (ix + k)
					if visited[j2] != 0 or open[j2] == 0 or steps[j2] != want_step or bases[j2] != want_base:
						growing = false
						break
					var tiz := ((iz + run_z) / n) * cw + ((ix + k) / n)
					if int(tiles[tiz]) != want_tile or atlas[tiz] != want_atlas:
						growing = false
						break
				if growing:
					run_z += 1
			for zz in run_z:
				for xx in run_x:
					visited[(iz + zz) * w + (ix + xx)] = 1
			var top_quad := {
				"x": float(x0) + float(ix) / float(n),
				"y": float(want_base) / 1000.0 + float(want_step) * step,
				"z": float(z0) + float(iz) / float(n),
				"dim_x": float(run_x) / float(n),
				"dim_y": 1.0,
				"dim_z": float(run_z) / float(n),
				"uv_w": float(run_x) / float(n),
				"uv_h": float(run_z) / float(n),
				"type": want_tile,
				"face_code": FACE_TOP,
			}
			if want_step != 0:
				top_quad["wave_step"] = int(want_step)
				top_quad["wave_base"] = float(want_base) / 1000.0
			out_quads.append(top_quad)
	_emit_wave_risers(out_quads, x0, z0, w, h, n, cw, open, steps, bases, tiles)


func _emit_wave_risers(
	out_quads: Array,
	x0: int,
	z0: int,
	w: int,
	h: int,
	n: int,
	cw: int,
	open: PackedByteArray,
	steps: PackedInt32Array,
	bases: PackedInt32Array,
	tiles: Array
) -> void:
	var layer: float = _WorldSettings.get_active().layer_height()
	var ix := 0
	while ix < w - 1:
		var iz := 0
		while iz < h:
			var a := iz * w + ix
			var b := a + 1
			if open[a] == 0 or open[b] == 0 or steps[a] == steps[b] or bases[a] != bases[b]:
				iz += 1
				continue
			var sa := int(steps[a])
			var sb := int(steps[b])
			var base_key := int(bases[a])
			var src := ix if sa > sb else ix + 1
			var tile := _wave_micro_tile(tiles, cw, n, src, iz)
			var run := 1
			while iz + run < h:
				var a2 := (iz + run) * w + ix
				var b2 := a2 + 1
				if open[a2] == 0 or open[b2] == 0 or int(steps[a2]) != sa or int(steps[b2]) != sb or int(bases[a2]) != base_key:
					break
				var src2 := ix if sa > sb else ix + 1
				if _wave_micro_tile(tiles, cw, n, src2, iz + run) != tile:
					break
				run += 1
			_append_wave_riser(out_quads, x0, z0, ix, iz, run, n, sa, sb, base_key, tile, true, layer)
			iz += run
		ix += 1
	var izb := 0
	while izb < h - 1:
		var ixb := 0
		while ixb < w:
			var a3 := izb * w + ixb
			var b3 := a3 + w
			if open[a3] == 0 or open[b3] == 0 or steps[a3] == steps[b3] or bases[a3] != bases[b3]:
				ixb += 1
				continue
			var sa3 := int(steps[a3])
			var sb3 := int(steps[b3])
			var base3 := int(bases[a3])
			var srcz := izb if sa3 > sb3 else izb + 1
			var tile3 := _wave_micro_tile(tiles, cw, n, ixb, srcz)
			var runz := 1
			while ixb + runz < w:
				var a4 := izb * w + (ixb + runz)
				var b4 := a4 + w
				if open[a4] == 0 or open[b4] == 0 or int(steps[a4]) != sa3 or int(steps[b4]) != sb3 or int(bases[a4]) != base3:
					break
				var srcz2 := izb if sa3 > sb3 else izb + 1
				if _wave_micro_tile(tiles, cw, n, ixb + runz, srcz2) != tile3:
					break
				runz += 1
			_append_wave_riser(out_quads, x0, z0, ixb, izb, runz, n, sa3, sb3, base3, tile3, false, layer)
			ixb += runz
		izb += 1


func _wave_micro_tile(tiles: Array, cw: int, n: int, ix: int, iz: int) -> int:
	var col_lx := int(ix / n)
	var col_lz := int(iz / n)
	return int(tiles[col_lz * cw + col_lx])


func _append_wave_riser(
	out_quads: Array,
	x0: int,
	z0: int,
	ix: int,
	iz: int,
	run: int,
	n: int,
	sa: int,
	sb: int,
	base_key: int,
	tile: int,
	along_z: bool,
	layer: float
) -> void:
	var n_f := float(n)
	var lo := mini(sa, sb)
	var hi := maxi(sa, sb)
	var y := float(base_key) / 1000.0 + layer + float(lo) * (layer / n_f)
	var dim_y := float(hi - lo) / n_f
	if along_z:
		var left_higher := sa > sb
		var src := ix if left_higher else ix + 1
		out_quads.append({
			"x": float(x0) + float(src) / n_f,
			"y": y,
			"z": float(z0) + float(iz) / n_f,
			"dim_x": 1.0 / n_f,
			"dim_y": dim_y,
			"dim_z": float(run) / n_f,
			"uv_w": float(run) / n_f,
			"uv_h": dim_y,
			"type": tile,
			"face_code": FACE_POS_X if left_higher else FACE_NEG_X,
			"wave_riser": true,
		})
	else:
		var near_higher := sa > sb
		var srcz := iz if near_higher else iz + 1
		out_quads.append({
			"x": float(x0) + float(ix) / n_f,
			"y": y,
			"z": float(z0) + float(srcz) / n_f,
			"dim_x": float(run) / n_f,
			"dim_y": dim_y,
			"dim_z": 1.0 / n_f,
			"uv_w": float(run) / n_f,
			"uv_h": dim_y,
			"type": tile,
			"face_code": FACE_POS_Z if near_higher else FACE_NEG_Z,
			"wave_riser": true,
		})


func _column_face_atlas(data: ChunkData, lx: int, lz: int, tile: int, face_code: int) -> Vector2i:
	return VoxelTypes.face_atlas(
		tile,
		face_code,
		data.position.x * ChunkData.SIZE + lx,
		data.position.y * ChunkData.SIZE + lz
	)


func _clear_ramp_approach_block(
	data: ChunkData,
	landing_x: int,
	landing_z: int,
	toward_low: Vector2i,
	planned: Dictionary = {}
) -> void:
	var ax: int = landing_x + toward_low.x
	var az: int = landing_z + toward_low.y
	if ax < 0 or ax >= ChunkData.SIZE or az < 0 or az >= ChunkData.SIZE:
		return
	if _tile_type_at(data, ax, az) == VoxelTypes.AIR:
		return
	if data.has_ramp(ax, az):
		return
	if planned.has(Vector2i(ax, az)):
		return
	var climb := Vector2i(-toward_low.x, -toward_low.y)
	data.set_ramp_approach(ax, az, climb)


func _strata_tile(surface_tile: int) -> int:
	match surface_tile:
		VoxelTypes.GRASSLAND, VoxelTypes.GRASSLAND2, VoxelTypes.GRASSLAND3, VoxelTypes.GRASSLAND4, VoxelTypes.GRASSLAND5:
			return VoxelTypes.DIRT
		VoxelTypes.DIRT, VoxelTypes.DIRT2:
			return VoxelTypes.DIRT2
		_:
			return VoxelTypes.STONE


func _emit_build_strata(data: ChunkData, out_quads: Array) -> void:
	if data.world == null:
		return
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _skips_greedy_surface_cell(data, x, z):
				continue
			var delta: float = data.get_worker_height_delta(x, z)
			if delta <= layer * 0.15:
				continue
			var cur_h: float = _surface_y_at(data, x, z)
			var natural_h: float = _natural_surface_y(data, x, z)
			var layers_built: int = maxi(1, int(round(delta / layer)))
			var tile: int = data.get_worker_build_tile(x, z)
			if tile < 0:
				tile = _tile_type_at(data, x, z)
			if tile == VoxelTypes.AIR:
				continue
			for step in range(1, layers_built):
				var layer_y: float = natural_h + float(step) * layer
				if layer_y >= cur_h - layer * 0.05:
					break
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, tile, FACE_TOP)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_NEG_X)
				_append_voxel_face(out_quads, float(x) + 1.0, layer_y, float(z), 0.001, 1.0, 1.0, 1.0, 1.0, tile, FACE_POS_X)
				_append_voxel_face(out_quads, float(x), layer_y, float(z), 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_NEG_Z)
				_append_voxel_face(out_quads, float(x), layer_y, float(z) + 1.0, 1.0, 1.0, 0.001, 1.0, 1.0, tile, FACE_POS_Z)


func _emit_dug_strata(data: ChunkData, out_quads: Array) -> void:
	_emit_dug_strata_region(data, out_quads, 0, 0, ChunkData.SIZE, ChunkData.SIZE)
	return
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _skips_greedy_surface_cell(data, x, z):
				continue
			var delta: float = data.get_worker_height_delta(x, z)
			if delta >= -layer * 0.15:
				continue
			var cur_h: float = _surface_y_at(data, x, z)
			var natural_h: float = _natural_surface_y(data, x, z)
			var depth_layers: int = maxi(1, int(round((natural_h - cur_h) / layer)))
			var top_tile: int = _tile_type_at(data, x, z)
			if top_tile == VoxelTypes.AIR:
				continue
			for step in range(1, depth_layers + 1):
				var layer_y: float = cur_h + float(step) * layer
				if layer_y > natural_h + 0.01:
					break
				# Do not recreate the pre-dig horizontal cap at natural_h (greedy top uses cur_h).
				if layer_y >= natural_h - layer * 0.05:
					continue
				var tile: int = _strata_tile(top_tile) if step < depth_layers else top_tile
				out_quads.append({
					"x": x,
					"y": layer_y,
					"z": z,
					"dim_x": 1.0,
					"dim_y": 1.0,
					"dim_z": 1.0,
					"uv_w": 1.0,
					"uv_h": 1.0,
					"type": tile,
					"face_code": FACE_TOP,
				})
func _is_ramp_landing(data: ChunkData, x: int, z: int) -> bool:
	if not data.has_ramp(x, z):
		return false
	var entry: Dictionary = data.get_ramp_entry(x, z)
	return (
		not entry.get("approach", false)
		and not entry.get("corner", false)
		and entry.get("dir2", Vector2i.ZERO) == Vector2i.ZERO
	)


func _append_voxel_face(
	out_quads: Array,
	lx: float, ly: float, lz: float,
	sx: float, sy: float, sz: float,
	uv_w: float, uv_h: float,
	vox: int, face_code: int
) -> void:
	out_quads.append({
		"x": lx,
		"y": ly,
		"z": lz,
		"dim_x": sx,
		"dim_y": sy,
		"dim_z": sz,
		"uv_w": uv_w,
		"uv_h": uv_h,
		"type": vox,
		"face_code": face_code,
	})


func _process(_delta):
	if _profiler_node == null or not is_instance_valid(_profiler_node):
		_profiler_node = get_node_or_null("/root/PerfProfiler")
	if _fbs_node == null or not is_instance_valid(_fbs_node):
		_fbs_node = get_node_or_null("/root/FrameBudgetScheduler")
	var profiler = _profiler_node
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_manager")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_process")
	if _rebuild_flush_needed:
		_flush_rebuild_pending()
	var frame_us := 0
	var worker_us := 0
	var upload_us := 0
	if profiler and profiler.has_method("get_snapshot"):
		var snap: Dictionary = profiler.get_snapshot()
		frame_us = int(float(snap.get("frame_ms", 0.0)) * 1000.0)
		worker_us = int(float(snap.get("worker_ms", 0.0)) * 1000.0)
		upload_us = int(float(snap.get("sections", {}).get("chunk_upload", {}).get("last_ms", 0.0)) * 1000.0)
	if profiler and profiler.has_method("set_gauge"):
		profiler.set_gauge("stream_queue_depth", float(_stream_load_pending.size()))
		profiler.set_gauge("mesh_queue_depth", float(_mesh_completion_queue.size()))
		profiler.set_gauge("chunk_tasks_inflight", float(_chunk_tasks.size()))
		profiler.set_gauge("chunks_visible", float(chunks.size()))
		profiler.set_gauge("workers_active", 1.0 if _chunk_tasks.size() > 0 else 0.0)
		var pool_stats: Dictionary = _ChunkDataPool.get_stats() if _ChunkDataPool else {}
		profiler.set_gauge("chunk_pool_free", float(pool_stats.get("free", 0)))
	if profiler and profiler.has_method("begin"):
		profiler.begin("stream_schedule")
	_drain_stream_pipeline()
	if profiler and profiler.has_method("end"):
		profiler.end("stream_schedule")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_apply")
	_drain_mesh_queue()
	_drain_deferred_mesh_buffers()
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_apply")
	var fbs = _fbs_node
	if fbs and fbs.has_method("report_queue_depth"):
		fbs.report_queue_depth(&"chunk_apply", _mesh_completion_queue.size(), 0)
		fbs.report_queue_depth(
			&"chunk_upload",
			ChunkView.pending_buffer_upload_count() + ChunkView.pending_surface_upload_count(),
			0
		)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.sample_frame(self, frame_us, worker_us, upload_us)
		_ChunkStreamingTelemetry.record_budget_sample(
			_stream_budget_used_us,
			_ChunkDataPool.get_stats()
		)
	_tick_deferred_bake_fill()

	if player == null or world == null:
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_process")
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_manager")
		return

	var col := _player_column_pos()
	var cx = floori(col.x / float(ChunkData.SIZE))
	var cz = floori(col.y / float(ChunkData.SIZE))
	var current_key := Vector2i(cx, cz)

	if not "_last_chunk_key" in self or _last_chunk_key != current_key:
		_last_chunk_key = current_key
		if profiler and profiler.has_method("begin_func"):
			profiler.begin_func("ChunkManager::update_stream")
		if profiler and profiler.has_method("begin"):
			profiler.begin("stream_update")
		update_stream(cx, cz)
		if profiler and profiler.has_method("end"):
			profiler.end("stream_update")
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::update_stream")

	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_process")
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_manager")


func _drain_stream_pipeline() -> void:
	if not _drain_measure and OS.get_environment("CRYSTALSTORM_DRAIN_STREAM_MEASURE").strip_edges().to_lower() in ["1", "true", "on"]:
		set_drain_measure_enabled(true)
	if _shutting_down:
		_stream_load_pending.clear()
		_stream_unload_pending.clear()
		_stream_load_sorted.clear()
		_stream_load_order_dirty = true
		_stream_unload_order_dirty = true
		return
	if stream_paused:
		return
	var budget_us := maxi(streaming_budget_us, 500)
	var t0 := Time.get_ticks_usec()
	var starts := 0
	var unloads := 0
	var frame_parts: Dictionary = {} if _drain_measure else {}

	if _stream_unload_order_dirty and not _stream_unload_pending.is_empty():
		var t_us := Time.get_ticks_usec() if _drain_measure else 0
		_sort_stream_unload_pending()
		_stream_unload_order_dirty = false
		if _drain_measure:
			_drain_add("unload_sort", Time.get_ticks_usec() - t_us)
	var t_unl0 := Time.get_ticks_usec() if _drain_measure else 0
	while _stream_unload_pending.size() > 0 and unloads < max_stream_unloads_per_frame:
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
		var key: Vector2i = _stream_unload_pending.pop_front()
		if chunks.has(key):
			_unload_chunk_view(key)
		unloads += 1
	if _drain_measure and unloads > 0:
		var unl_us := Time.get_ticks_usec() - t_unl0
		_drain_add("unload_loop", unl_us)
		frame_parts["unload_loop_us"] = unl_us
		frame_parts["unloads"] = unloads

	var inflight := _chunk_tasks.size() + _mesh_completion_queue.size()
	if ChunkView.pending_buffer_upload_count() > 4:
		_stream_budget_used_us = Time.get_ticks_usec() - t0
		if _drain_measure:
			_drain_finish_call(t0, frame_parts, starts, unloads, "early_upload_backpressure")
		return
	var can_start := (
		inflight < MAX_INFLIGHT_CHUNKS
		and not _stream_load_pending.is_empty()
		and Time.get_ticks_usec() - t0 < budget_us
	)
	if not can_start:
		_stream_budget_used_us = Time.get_ticks_usec() - t0
		if _drain_measure:
			_drain_finish_call(t0, frame_parts, starts, unloads, "no_start")
		return

	var starts_cap: int = 1 if unloads > 0 else maxi(max_stream_starts_per_frame, 1)
	var player_chunk_once := _player_chunk_coord()
	var pick_us_sum := 0
	while starts < starts_cap and inflight < MAX_INFLIGHT_CHUNKS:
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
		if _stream_load_pending.is_empty():
			break
		var t_pick := Time.get_ticks_usec() if _drain_measure else 0
		var best: Dictionary = _ChunkStreamScheduler.pick_best_load_candidate(_stream_load_pending)
		if _drain_measure:
			pick_us_sum += Time.get_ticks_usec() - t_pick
		if best.is_empty():
			break
		var coord: Vector2i = best.get("coord", Vector2i.ZERO)
		if not _stream_load_pending.has(coord):
			break
		if _is_chunk_resident(coord):
			_stream_load_pending.erase(coord)
			_stream_load_order_dirty = true
			continue
		if unloads > 0:
			var chebyshev := maxi(
				absi(coord.x - player_chunk_once.x),
				absi(coord.y - player_chunk_once.y)
			)
			if chebyshev > 1:
				var t_near := Time.get_ticks_usec() if _drain_measure else 0
				var near_best := _pick_best_near_load(player_chunk_once, 1)
				if _drain_measure:
					pick_us_sum += Time.get_ticks_usec() - t_near
				if near_best.is_empty():
					break
				coord = near_best.get("coord", Vector2i.ZERO)
				best = near_best
		_stream_load_pending.erase(coord)
		_stream_load_order_dirty = true
		var urgent: bool = bool(best.get("urgent", false))
		var cheb2 := maxi(
			absi(coord.x - player_chunk_once.x),
			absi(coord.y - player_chunk_once.y)
		)
		var high_priority: bool = urgent or cheb2 <= 1 or unloads > 0
		_enqueue_chunk_generation(coord, high_priority)
		starts += 1
		inflight += 1
	if _drain_measure and pick_us_sum > 0:
		_drain_add("pick_best_load", pick_us_sum)
		frame_parts["pick_best_load_us"] = pick_us_sum

	_stream_budget_used_us = Time.get_ticks_usec() - t0
	if _drain_measure:
		frame_parts["starts"] = starts
		_drain_finish_call(t0, frame_parts, starts, unloads, "ok")


func _drain_finish_call(t0: int, frame_parts: Dictionary, starts: int, unloads: int, reason: String) -> void:
	var tot := Time.get_ticks_usec() - t0
	_drain_n += 1
	_drain_sum_us += tot
	_drain_add("drain_total", tot)
	if tot >= _drain_max_us:
		_drain_max_us = tot
		frame_parts["total_us"] = tot
		frame_parts["total_ms"] = float(tot) / 1000.0
		frame_parts["starts"] = starts
		frame_parts["unloads"] = unloads
		frame_parts["reason"] = reason
		if not _drain_enqueue_worst.is_empty():
			frame_parts["worst_enqueue_so_far"] = _drain_enqueue_worst.duplicate(true)
		_drain_worst = frame_parts.duplicate(true)


func _pick_best_near_load(player_chunk: Vector2i, max_chebyshev: int) -> Dictionary:
	var best_coord := Vector2i.ZERO
	var best_score := -1.0e30
	var best_urgent := false
	var have := false
	for coord_variant in _stream_load_pending.keys():
		var coord: Vector2i = coord_variant
		var cheb := maxi(absi(coord.x - player_chunk.x), absi(coord.y - player_chunk.y))
		if cheb > max_chebyshev:
			continue
		var entry: Dictionary = _stream_load_pending[coord]
		var score: float = float(entry.get("score", 0.0))
		if not have or score > best_score or (
			is_equal_approx(score, best_score) and str(coord) < str(best_coord)
		):
			have = true
			best_coord = coord
			best_score = score
			best_urgent = bool(entry.get("urgent", false))
	if not have:
		return {}
	return {"coord": best_coord, "score": best_score, "urgent": best_urgent}


func _drain_mesh_queue() -> void:
	if _shutting_down:
		_mesh_completion_queue.clear()
		_mesh_completion_order_dirty = true
		return
	if _mesh_completion_order_dirty and _mesh_completion_queue.size() > 1:
		_sort_mesh_completion_queue()
		_mesh_completion_order_dirty = false
	var fbs = _fbs_node if _fbs_node != null else get_node_or_null("/root/FrameBudgetScheduler")
	var profiler = _profiler_node if _profiler_node != null else get_node_or_null("/root/PerfProfiler")
	var drain := func(token = null) -> void:
		while _mesh_completion_queue.size() > 0:
			if token != null and not token.can_continue():
				break
			var item: Dictionary = _mesh_completion_queue.pop_front()
			var item_coord: Vector2i = item.get("coord", Vector2i.ZERO)
			var item_token: int = int(item.get("token", -1))
			if item.get("data") == null or (item["data"] as ChunkData).position != item_coord:
				pending.erase(item_coord)
				call_deferred("request_chunk", item_coord, true)
				continue
			if _ChunkStreamingTelemetry.is_enabled() and item_token >= 0:
				_ChunkStreamingTelemetry.transition(
					item_coord,
					item_token,
					_ChunkStreamingTelemetry.STATE_UPLOADING,
					{"mesh_queue_depth": _mesh_completion_queue.size()}
				)
			var apply_t0 := Time.get_ticks_usec()
			if profiler and profiler.has_method("begin"):
				profiler.begin("chunk_upload")
			_on_chunk_ready(item["data"], item["mesh"], item_token, apply_t0)
			stat_upload_us += Time.get_ticks_usec() - apply_t0
			stat_upload_n += 1
			if profiler and profiler.has_method("end"):
				profiler.end("chunk_upload")
			if token != null:
				token.spend_unit()
			else:
				break
	if fbs and fbs.has_method("run_budgeted"):
		fbs.run_budgeted(&"chunk_apply", drain)
	else:
		var count_budget := maxi(MAX_CHUNKS_PER_FRAME, 1)
		var time_budget_us := maxi(chunk_upload_budget_us, 500)
		var t0 := Time.get_ticks_usec()
		while _mesh_completion_queue.size() > 0 and count_budget > 0:
			if Time.get_ticks_usec() - t0 >= time_budget_us:
				break
			var item2: Dictionary = _mesh_completion_queue.pop_front()
			var c2: Vector2i = item2.get("coord", Vector2i.ZERO)
			var tok2: int = int(item2.get("token", -1))
			if item2.get("data") == null or (item2["data"] as ChunkData).position != c2:
				pending.erase(c2)
				call_deferred("request_chunk", c2, true)
				continue
			if profiler and profiler.has_method("begin"):
				profiler.begin("chunk_upload")
			var up0 := Time.get_ticks_usec()
			_on_chunk_ready(item2["data"], item2["mesh"], tok2, up0)
			stat_upload_us += Time.get_ticks_usec() - up0
			stat_upload_n += 1
			if profiler and profiler.has_method("end"):
				profiler.end("chunk_upload")
			count_budget -= 1


func _drain_deferred_mesh_buffers() -> void:
	if _shutting_down:
		ChunkView.clear_pending_buffer_uploads()
		return
	if (
		ChunkView.pending_surface_upload_count() <= 0
		and ChunkView.pending_buffer_upload_count() <= 0
	):
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_upload")
	var budget_us := chunk_upload_budget_us
	var t0 := Time.get_ticks_usec()
	if ChunkView.pending_surface_upload_count() > 0:
		ChunkView.drain_pending_surface_uploads(2, budget_us)
	var remaining_us := maxi(budget_us - (Time.get_ticks_usec() - t0), 500)
	if ChunkView.pending_buffer_upload_count() > 0:
		# Terrain + ramp + corner + diagonal can queue together; 1/frame left
		# landing columns as black holes after dig/remesh.
		ChunkView.drain_pending_buffer_uploads(8, remaining_us)
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_upload")


func set_stream_paused(paused: bool) -> void:
	if stream_paused and not paused:
		_last_chunk_key = Vector2i(-99999, -99999)
	stream_paused = paused


func is_stream_paused() -> bool:
	return stream_paused


func update_stream(cx: int, cz: int) -> void:
	if stream_paused or _shutting_down:
		return
	var player_chunk := Vector2i(cx, cz)
	_update_player_velocity_hint(player_chunk)
	_wave_lod_recheck(player_chunk)
	_update_near_props(player_chunk)
	var camera_hint := _camera_forward_chunk_hint()
	var needed := {}
	var queued_count := 0
	var load_mutated := false
	var unload_mutated := false

	for z in range(cz - RENDER_DISTANCE, cz + RENDER_DISTANCE + 2):
		for x in range(cx - RENDER_DISTANCE, cx + RENDER_DISTANCE + 2):
			var key: Vector2i = Vector2i(x, z)
			# Finite world: do not stream/generate infinite terrain outside playable bounds.
			if _WorldBakeService_is_outside(key):
				continue
			needed[key] = true
			if not _is_chunk_resident(key):
				var score := _ChunkStreamScheduler.priority_score(
					key, player_chunk, _player_chunk_velocity, camera_hint
				)
				var prev: Dictionary = _stream_load_pending.get(key, {})
				var urgent: bool = bool(prev.get("urgent", false))
				var prev_score: float = float(prev.get("score", -1.0e30))
				_stream_load_pending[key] = {"score": score, "urgent": urgent}
				if not prev.has("score") or not is_equal_approx(prev_score, score):
					load_mutated = true
				if not prev.has("score"):
					_set_lifecycle_state(key, _ChunkStreamLifecycle.REQUESTED)
					queued_count += 1

	for extra_v in _start_threat_chunk_coords():
		var extra: Vector2i = extra_v
		if needed.has(extra) or _WorldBakeService_is_outside(extra):
			continue
		needed[extra] = true
		if not _is_chunk_resident(extra):
			var extra_score := _ChunkStreamScheduler.priority_score(
				extra, player_chunk, _player_chunk_velocity, camera_hint
			)
			var extra_prev: Dictionary = _stream_load_pending.get(extra, {})
			var extra_urgent: bool = bool(extra_prev.get("urgent", false))
			var extra_prev_score: float = float(extra_prev.get("score", -1.0e30))
			_stream_load_pending[extra] = {"score": extra_score, "urgent": extra_urgent}
			if not extra_prev.has("score") or not is_equal_approx(extra_prev_score, extra_score):
				load_mutated = true
			if not extra_prev.has("score"):
				_set_lifecycle_state(extra, _ChunkStreamLifecycle.REQUESTED)
				queued_count += 1

	var unload_queued := 0
	for key in chunks.keys():
		if not needed.has(key):
			if key not in _stream_unload_pending:
				_stream_unload_pending.append(key)
				unload_queued += 1
				unload_mutated = true
			if _stream_load_pending.erase(key):
				load_mutated = true

	for key in _stream_load_pending.keys():
		if not needed.has(key):
			_stream_load_pending.erase(key)
			load_mutated = true

	for key in pending.keys():
		if not needed.has(key):
			pending.erase(key)

	if load_mutated:
		_stream_load_order_dirty = true
	if unload_mutated:
		_stream_unload_order_dirty = true

	var inflight := _chunk_tasks.size() + _mesh_completion_queue.size()
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.sample_stream_pass(
			self,
			player_chunk,
			queued_count,
			unload_queued,
			{
				"render_distance": RENDER_DISTANCE,
				"max_inflight": MAX_INFLIGHT_CHUNKS,
				"inflight_at_pass": inflight,
				"load_pending": _stream_load_pending.size(),
				"unload_pending": _stream_unload_pending.size(),
			}
		)


func _player_column_pos() -> Vector2:
	if player == null or not is_instance_valid(player):
		return Vector2.ZERO
	if player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		return Vector2(v.x, v.z)
	if "global_position" in player:
		var ws = _WorldSettings.get_active()
		return Vector2(
			ws.world_to_column(player.global_position.x),
			ws.world_to_column(player.global_position.z)
		)
	return Vector2.ZERO


func _sample_height(data: ChunkData, lx: int, lz: int) -> float:
	# The halo is only the neighbor ring frozen for the worker. It must not
	# override an interior column the walk mesh was built from.
	if lx >= 0 and lx < ChunkData.SIZE and lz >= 0 and lz < ChunkData.SIZE:
		return _surface_y_at(data, lx, lz)
	var halo_h: float = data.get_halo_surface_y(lx, lz)
	if halo_h > -9000.0:
		return halo_h
	return 0.0


func _ramp_covers_drop(data: ChunkData, low_x: int, low_z: int, toward_high: Vector2i) -> bool:
	if low_x >= 0 and low_x < ChunkData.SIZE and low_z >= 0 and low_z < ChunkData.SIZE:
		var low_entry: Dictionary = data.get_ramp_entry(low_x, low_z)
		if bool(low_entry.get("corner", false)):
			var da: Vector2i = low_entry.get("dir", Vector2i.ZERO)
			var db: Vector2i = low_entry.get("dir2", Vector2i.ZERO)
			if da == toward_high or db == toward_high:
				return true
	var hx: int = low_x + toward_high.x
	var hz: int = low_z + toward_high.y
	if hx < 0 or hx >= ChunkData.SIZE or hz < 0 or hz >= ChunkData.SIZE:
		return false
	if not data.has_ramp(hx, hz):
		return false
	var entry: Dictionary = data.get_ramp_entry(hx, hz)
	if bool(entry.get("approach", false)) or bool(entry.get("corner", false)):
		return false
	return entry.get("dir", Vector2i.ZERO) == Vector2i(-toward_high.x, -toward_high.y)


func _emit_surface_side_walls(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
	_emit_surface_side_walls_region(
		data, normal_dir, face_code, out_quads, 0, 0, ChunkData.SIZE, ChunkData.SIZE
	)
	return
	var dx = normal_dir.x
	var dz = normal_dir.z
	if dx == 0 and dz == 0:
		return

	if abs(dx) == 1:
		for x in range(ChunkData.SIZE):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for z in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if z < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z, false):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					var toward_high := Vector2i(-dx, 0)
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						if _ramp_covers_drop(data, nx, nz, toward_high):
							has_wall = false
						elif _is_ramp_landing(data, x, z) and diff <= _WorldSettings.get_active().layer_height() * 1.2:
							has_wall = false
						else:
							has_wall = true
				if has_wall and (run_start == -1 or is_equal_approx(curr_h, run_h) and curr_t == run_t):
					if run_start == -1:
						run_start = z
						run_h = curr_h
						run_t = curr_t
				else:
					if run_start != -1:
						out_quads.append({
							"x": x,
							"y": run_h,
							"z": run_start,
							"dim_x": 1.0,
							"dim_y": 1.0,
							"dim_z": float(z - run_start),
							"uv_w": float(z - run_start),
							"uv_h": 1.0,
							"type": run_t,
							"face_code": face_code
						})
					run_start = -1
	elif abs(dz) == 1:
		for z in range(ChunkData.SIZE):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for x in range(ChunkData.SIZE + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if x < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z, false):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x
					var nz = z + dz
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					var toward_high := Vector2i(0, -dz)
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						if _ramp_covers_drop(data, nx, nz, toward_high):
							has_wall = false
						elif _is_ramp_landing(data, x, z) and diff <= _WorldSettings.get_active().layer_height() * 1.2:
							has_wall = false
						else:
							has_wall = true
				if has_wall and (run_start == -1 or is_equal_approx(curr_h, run_h) and curr_t == run_t):
					if run_start == -1:
						run_start = x
						run_h = curr_h
						run_t = curr_t
				else:
					if run_start != -1:
						out_quads.append({
							"x": run_start,
							"y": run_h,
							"z": z,
							"dim_x": float(x - run_start),
							"dim_y": 1.0,
							"dim_z": 1.0,
							"uv_w": float(x - run_start),
							"uv_h": 1.0,
							"type": run_t,
							"face_code": face_code
						})
					run_start = -1

func _generate_chunk(data: ChunkData) -> void:
	if data == null or not data._has_worker_snapshot or data.world == null:
		return
	var bake = null
	var wb = load("res://world/world_bake_service.gd")
	if wb != null and wb.has_method("get_active"):
		bake = wb.get_active()
	if bake != null and bake.has_method("note_generate_chunk_call"):
		bake.note_generate_chunk_call()
	data._compute_column_maps(true)
	data.derive_micro_from_terrain_edits()
					
func _emit_cave_faces(data: ChunkData, out_quads: Array) -> void:
	if data.world == null:
		return
	for lx in range(ChunkData.SIZE):
		for lz in range(ChunkData.SIZE):
			var wx: float = float(data.position.x * ChunkData.SIZE + lx)
			var wz: float = float(data.position.y * ChunkData.SIZE + lz)
			var surf: float = _surface_y_at(data, lx, lz)
			var y_min: int = maxi(0, int(surf) - CAVE_MESH_DEPTH)
			var y_max: int = int(surf) - 1
			if y_max < y_min:
				continue
			for y in range(y_min, y_max + 1):
				var wy: float = float(y)
				var vox: int = data.world.get_voxel(wx, wy, wz)
				if vox == VoxelTypes.AIR:
					continue
				if data.world.get_voxel(wx, wy + 1.0, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						1.0, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_TOP
					)
				if data.world.get_voxel(wx - 1.0, wy, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						0.001, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_NEG_X
					)
				if data.world.get_voxel(wx + 1.0, wy, wz) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx) + 1.0, wy, float(lz),
						0.001, 1.0, 1.0,
						1.0, 1.0,
						vox, FACE_POS_X
					)
				if data.world.get_voxel(wx, wy, wz - 1.0) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz),
						1.0, 1.0, 0.001,
						1.0, 1.0,
						vox, FACE_NEG_Z
					)
				if data.world.get_voxel(wx, wy, wz + 1.0) == VoxelTypes.AIR:
					_append_voxel_face(
						out_quads,
						float(lx), wy, float(lz) + 1.0,
						1.0, 1.0, 0.001,
						1.0, 1.0,
						vox, FACE_POS_Z
					)


func _on_chunk_ready(
	data: ChunkData,
	packed_quad_data: Dictionary,
	token: int = -1,
	apply_t0: int = 0
) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_on_chunk_ready")
	if profiler and data != null:
		if profiler.has_method("inc_frame"):
			profiler.inc_frame("chunks_streamed_applied", 1)
		if profiler.has_method("set_gauge"):
			profiler.set_gauge("last_streamed_cx", float(data.position.x))
			profiler.set_gauge("last_streamed_cz", float(data.position.y))
			profiler.set_gauge("last_streamed_frame", float(Engine.get_process_frames()))
	if not is_inside_tree() or _shutting_down:
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_ready")
		return
	if data == null or not pending.has(data.position):
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_ready")
		return
	pending.erase(data.position)
	if not packed_quad_data.has("count") or packed_quad_data.get("count", 0) == 0:
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_ready")
		return
	var apply_started := apply_t0 if apply_t0 > 0 else Time.get_ticks_usec()
	var mesh_nodes_recreated := false
	if chunks.has(data.position):
		var existing: ChunkView = chunks[data.position] as ChunkView
		if existing and is_instance_valid(existing):
			mesh_nodes_recreated = true
			var setup_t0 := Time.get_ticks_usec()
			if profiler and profiler.has_method("begin_func"):
				profiler.begin_func("ChunkView::setup")
			existing.setup(data, packed_quad_data)
			_clear_preserve_snapshot_after_apply(data, packed_quad_data)
			if profiler and profiler.has_method("end_func"):
				profiler.end_func("ChunkView::setup")
			if profiler and profiler.has_method("record_us"):
				profiler.record_us("chunk_view_setup", Time.get_ticks_usec() - setup_t0)
			_record_apply_telemetry(data.position, token, apply_started, mesh_nodes_recreated)
			if _ChunkStreamingTelemetry.is_enabled() and token >= 0:
				_ChunkStreamingTelemetry.transition(
					data.position,
					token,
					_ChunkStreamingTelemetry.STATE_UPLOADED,
					{"mesh_nodes_recreated": true}
				)
				_ChunkStreamingTelemetry.transition(data.position, token, _ChunkStreamingTelemetry.STATE_ACTIVE)
				_ChunkStreamingTelemetry.finalize_lifecycle(data.position, token)
			_set_lifecycle_state(data.position, _ChunkStreamLifecycle.ACTIVE)
			var sig_t0 := Time.get_ticks_usec()
			if profiler and profiler.has_method("begin"):
				profiler.begin("chunk_ready_signal")
			chunk_ready.emit(data.position, data)
			if profiler and profiler.has_method("end"):
				profiler.end("chunk_ready_signal")
			if profiler and profiler.has_method("record_us"):
				profiler.record_us("chunk_ready_signal", Time.get_ticks_usec() - sig_t0)
			_schedule_patch_flush_if_needed()
			if profiler and profiler.has_method("end_func"):
				profiler.end_func("ChunkManager::_on_chunk_ready")
			return
	var view: ChunkView = _acquire_chunk_view()
	if view == null:
		push_warning("ChunkManager: failed to instantiate ChunkView for %s" % str(data.position))
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_ready")
		return
	var setup_t1 := Time.get_ticks_usec()
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkView::setup")
	view.setup(data, packed_quad_data)
	_clear_preserve_snapshot_after_apply(data, packed_quad_data)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkView::setup")
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_view_setup", Time.get_ticks_usec() - setup_t1)
	var SPP = load("res://systems/stream_phase_profiler.gd")
	var upload_us_for_profile: int = int(ChunkView.peek_last_upload_us())
	if SPP and SPP.is_enabled():
		SPP.record("mesh_upload", upload_us_for_profile, data.position)
		SPP.record("collision_creation", 0, data.position)
		SPP.record("physics_registration", 0, data.position)
	var tree_t0 := Time.get_ticks_usec()
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::add_child_view")
	add_child(view)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::add_child_view")
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_scenetree_insert", Time.get_ticks_usec() - tree_t0)
	if SPP and SPP.is_enabled():
		SPP.record("scenetree_insert_view", Time.get_ticks_usec() - tree_t0, data.position)
		var t_sync := Time.get_ticks_usec()
		RenderingServer.force_sync()
		SPP.record("gpu_synchronization", Time.get_ticks_usec() - t_sync, data.position)
		SPP.record("main_thread_apply", Time.get_ticks_usec() - apply_started, data.position)
		SPP.end_chunk(data.position)
	chunks[data.position] = view
	_record_apply_telemetry(data.position, token, apply_started, mesh_nodes_recreated)
	if _ChunkStreamingTelemetry.is_enabled() and token >= 0:
		_ChunkStreamingTelemetry.transition(
			data.position,
			token,
			_ChunkStreamingTelemetry.STATE_UPLOADED,
			{"mesh_nodes_recreated": false}
		)
		_ChunkStreamingTelemetry.transition(data.position, token, _ChunkStreamingTelemetry.STATE_ACTIVE)
		_ChunkStreamingTelemetry.finalize_lifecycle(data.position, token)
	_set_lifecycle_state(data.position, _ChunkStreamLifecycle.ACTIVE)
	var sig_t1 := Time.get_ticks_usec()
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_ready_signal")
	chunk_ready.emit(data.position, data)
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_ready_signal")
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_ready_signal", Time.get_ticks_usec() - sig_t1)
	_schedule_patch_flush_if_needed()
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_on_chunk_ready")


func _pool_chunk_data_after_view_free(data: ChunkData) -> void:
	if data == null or _shutting_down:
		return
	if data.has_meta("_pooled_released"):
		return
	data.set_meta("_pooled_released", true)
	_ChunkDataPool.release(data)


func _is_chunk_resident(coord: Vector2i) -> bool:
	return chunks.has(coord) or pending.has(coord) or _chunk_tasks.has(coord)


func _queue_stream_load(coord: Vector2i, urgent: bool = false) -> void:
	var player_chunk := _player_chunk_coord()
	var score := _ChunkStreamScheduler.priority_score(
		coord, player_chunk, _player_chunk_velocity, _camera_forward_chunk_hint()
	)
	if urgent:
		score += 100000.0
	_stream_load_pending[coord] = {"score": score, "urgent": urgent}
	_stream_load_order_dirty = true
	_set_lifecycle_state(coord, _ChunkStreamLifecycle.REQUESTED)


func _set_lifecycle_state(coord: Vector2i, state: String) -> void:
	_lifecycle_by_coord[coord] = state


func _player_chunk_coord() -> Vector2i:
	return get_player_chunk_coord()


func _update_player_velocity_hint(current: Vector2i) -> void:
	if _last_player_chunk_for_velocity.x == -99999:
		_last_player_chunk_for_velocity = current
		return
	_player_chunk_velocity = current - _last_player_chunk_for_velocity
	_last_player_chunk_for_velocity = current


func _camera_forward_chunk_hint() -> Vector2i:
	if player == null:
		return Vector2i.ZERO
	var cam: Camera3D = player.get_node_or_null("Camera3D") as Camera3D
	if cam == null and player.get_viewport():
		cam = player.get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i.ZERO
	var fwd := -cam.global_transform.basis.z
	if absf(fwd.x) >= absf(fwd.z):
		return Vector2i(1 if fwd.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if fwd.z > 0.0 else -1)


func _sort_stream_unload_pending() -> void:
	if _stream_unload_pending.is_empty():
		return
	var player_chunk := _player_chunk_coord()
	var camera_hint := _camera_forward_chunk_hint()
	_ChunkStreamScheduler.sort_unload_candidates(
		_stream_unload_pending, player_chunk, camera_hint
	)


func _push_mesh_completion(item: Dictionary) -> void:
	_mesh_completion_queue.append(item)
	_mesh_completion_order_dirty = true


func _sort_mesh_completion_queue() -> void:
	if _mesh_completion_queue.size() <= 1:
		return
	var player_chunk := _player_chunk_coord()
	var camera_hint := _camera_forward_chunk_hint()
	var vel := _player_chunk_velocity
	_mesh_completion_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: Vector2i = a.get("coord", Vector2i.ZERO)
		var cb: Vector2i = b.get("coord", Vector2i.ZERO)
		var sa := _ChunkStreamScheduler.priority_score(ca, player_chunk, vel, camera_hint)
		var sb := _ChunkStreamScheduler.priority_score(cb, player_chunk, vel, camera_hint)
		return sa > sb
	)


func _schedule_patch_flush_if_needed() -> void:
	if _patch_pending.is_empty() or not is_inside_tree():
		return
	_schedule_rebuild_flush()


func _record_apply_telemetry(coord: Vector2i, token: int, apply_t0: int, mesh_nodes_recreated: bool) -> void:
	if not _ChunkRebuildTelemetry.is_enabled() or token < 0:
		return
	var upload_ms := float(ChunkView.consume_last_upload_ms())
	var apply_ms := float(Time.get_ticks_usec() - apply_t0) / 1000.0
	_ChunkRebuildTelemetry.finalize_record(
		coord,
		token,
		{},
		{
			"mesh_upload_time_ms": upload_ms,
			"main_thread_apply_time_ms": apply_ms,
			"mesh_nodes_recreated": mesh_nodes_recreated,
		}
	)


func _chunk_mesh_task(
	coord: Vector2i,
	data: ChunkData,
	token: int,
	full_rebuild: bool,
	dirty_local: Array,
	patch_rect: Rect2i,
	keep_quads: Array,
	prior_surface_cache: Dictionary = {}
) -> void:
	var tw0 := Time.get_ticks_usec()
	if data == null or not data._has_worker_snapshot:
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token, {})
		return
	if data.world == null and world != null:
		data.world = world
	if data.world == null:
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token, {})
		return
	if _ChunkRebuildTelemetry.is_enabled():
		_ChunkRebuildTelemetry.record_worker_start(coord, token)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_WORKER_ACTIVE)

	var job: Dictionary = _ChunkPipeline.run_worker_job(
		self,
		data,
		full_rebuild,
		dirty_local,
		patch_rect,
		keep_quads,
		prior_surface_cache,
		prebuild_chunk_buffers,
		terrain_surface_mesh
	)
	if not bool(job.get("ok", false)):
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token, {})
		return

	var examined: int = int(job.get("examined", 0))
	var column_us: int = int(job.get("column_us", 0))
	var build_mesh_us: int = int(job.get("build_mesh_us", 0))
	var mesh_us: int = int(job.get("mesh_us", 0))
	var buffer_us: int = int(job.get("buffer_us", 0))
	var payload: Dictionary = job.get("payload", {})
	var merged_quads: Array = job.get("merged_quads", [])

	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_HEIGHT_GENERATED, {
			"column_map_time_ms": float(column_us) / 1000.0,
			"full_rebuild": full_rebuild,
		})
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_MESH_GENERATED, {
			"mesh_generation_time_ms": float(mesh_us) / 1000.0,
			"build_mesh_time_ms": float(build_mesh_us) / 1000.0,
		})

	var worker_telemetry: Dictionary = {
		"column_us": column_us,
		"mesh_us": mesh_us,
		"buffer_us": buffer_us,
		"build_mesh_us": build_mesh_us,
		"mesh_generation_time_ms": float(mesh_us) / 1000.0,
		"column_map_time_ms": float(column_us) / 1000.0,
		"build_mesh_time_ms": float(build_mesh_us) / 1000.0,
	}
	if _ChunkRebuildTelemetry.is_enabled():
		var geo: Dictionary = _ChunkRebuildTelemetry.collect_geometry_stats(
			data, merged_quads, payload, examined
		)
		worker_telemetry.merge({
			"voxels_examined": geo.get("voxels_examined", examined),
			"quads_emitted": geo.get("quads_emitted", 0),
			"ramps_emitted": geo.get("ramps_emitted", 0),
			"concave_pieces_emitted": geo.get("concave_pieces_emitted", 0),
			"greedy_merge_ratio": geo.get("greedy_merge_ratio", 0.0),
			"triangles_generated": geo.get("triangles_generated", 0),
			"serialization_time_ms": float(int(job.get("duplicate_us", 0)) + buffer_us) / 1000.0,
			"payload_duplicated": bool(job.get("payload_duplicated", false)),
			"buffer_allocated": bool(job.get("buffer_allocated", false)),
			"prebuilt_buffers": prebuild_chunk_buffers,
			"incremental": not full_rebuild,
			"dirty_columns": dirty_local.size(),
			"rebuilt_columns": examined,
			"mesh_patch_size": _TerrainDirtyScope.patch_cells_area(patch_rect),
			"pipeline_stages": job.get("stages", []),
		}, true)
	# Do not null data.world here: regen reuses view.chunk_data and concurrent main-thread
	# rebuild enqueue can race a still-running or just-finished worker if world is cleared early.
	_stat_mutex.lock()
	stat_worker_us += Time.get_ticks_usec() - tw0
	stat_worker_n += 1
	_stat_mutex.unlock()
	call_deferred(
		"_on_chunk_task_complete_timed", coord, data, payload, mesh_us, buffer_us, token, worker_telemetry
	)


func _on_chunk_task_complete_timed(coord: Vector2i, data: ChunkData, payload: Dictionary, mesh_us: int, buffer_us: int, token: int, worker_telemetry: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	_on_chunk_task_complete(coord, data, payload, mesh_us, buffer_us, token, worker_telemetry)
	stat_main_us += Time.get_ticks_usec() - t0
	stat_main_n += 1


## True when a completed mesh job must not be applied (token or WorldState mesh stamp).
func is_mesh_job_stale(coord: Vector2i, data: ChunkData, token: int) -> bool:
	if token < 0 or int(_chunk_gen_tokens.get(coord, -1)) != token:
		return true
	if data != null and data.has_method("is_overlay_mesh_stamp_current") \
			and not data.is_overlay_mesh_stamp_current():
		return true
	return false


func _on_chunk_task_complete(
	coord: Vector2i,
	data: ChunkData,
	packed_quad_data: Dictionary,
	mesh_us: int = 0,
	buffer_us: int = 0,
	token: int = -1,
	worker_telemetry: Dictionary = {}
) -> void:
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_task_complete")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_on_chunk_task_complete")
	# Reap pool task id first (wait_for_task_completion). Must not only erase.
	_reap_chunk_task(coord)
	if _shutting_down or is_mesh_job_stale(coord, data, token):
		var token_stale := token >= 0 and int(_chunk_gen_tokens.get(coord, -1)) != token
		var stamp_stale := (
			data != null
			and token >= 0
			and not token_stale
			and data.has_method("is_overlay_mesh_stamp_current")
			and not data.is_overlay_mesh_stamp_current()
		)
		if data != null and _telemetry_trigger in ["stream", "movement"]:
			_ChunkDataPool.release(data)
		if token_stale and not _chunk_tasks.has(coord):
			pending.erase(coord)
		if stamp_stale and not _shutting_down:
			pending.erase(coord)
			call_deferred("rebuild_chunk", coord)
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_task_complete")
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_task_complete")
		return
	if data == null:
		pending.erase(coord)
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_task_complete")
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_task_complete")
		return
	var column_us: int = int(worker_telemetry.get("column_us", 0))
	# Worker-stage attribution only (must not count as main-thread tracked).
	if profiler and profiler.has_method("record_worker_stage"):
		if column_us > 0:
			profiler.record_worker_stage("chunk_column", column_us)
		if mesh_us > 0:
			profiler.record_worker_stage("chunk_mesh", mesh_us)
		if buffer_us > 0:
			profiler.record_worker_stage("chunk_buffer", buffer_us)
	elif profiler and profiler.has_method("record_us"):
		if column_us > 0:
			profiler.record_us("chunk_column", column_us)
		if mesh_us > 0:
			profiler.record_us("chunk_mesh", mesh_us)
		if buffer_us > 0:
			profiler.record_us("chunk_buffer", buffer_us)
	if profiler and profiler.has_method("note_worker_job_ms"):
		var job_ms: float = float(column_us + mesh_us + buffer_us) / 1000.0
		if job_ms > 0.0:
			profiler.note_worker_job_ms(job_ms)
	if not is_inside_tree() or not pending.has(coord):
		if _telemetry_trigger in ["stream", "movement"]:
			_ChunkDataPool.release(data)
		pending.erase(coord)
		if profiler and profiler.has_method("end_func"):
			profiler.end_func("ChunkManager::_on_chunk_task_complete")
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_task_complete")
		return
	if data.world == null and world != null:
		data.world = world
	if _ChunkRebuildTelemetry.is_enabled() and not worker_telemetry.is_empty():
		_ChunkRebuildTelemetry.stage_worker_metrics(coord, token, worker_telemetry)
	_push_mesh_completion({"coord": coord, "data": data, "mesh": packed_quad_data, "token": token})
	if _ChunkStreamingTelemetry.is_enabled() and token >= 0:
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_QUEUED_FOR_UPLOAD, {
			"mesh_queue_depth": _mesh_completion_queue.size(),
		})
		_set_lifecycle_state(coord, _ChunkStreamLifecycle.QUEUED_FOR_UPLOAD)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_on_chunk_task_complete")
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_task_complete")

func sync_ramp_map_to_mesh(data: ChunkData, quads: Array) -> void:
	if data == null:
		return
	var owned: Dictionary = {}
	for q_v in quads:
		var q: Dictionary = q_v
		var fc: int = int(q.get("face_code", FACE_TOP))
		if fc != FACE_RAMP and fc != FACE_RAMP_CORNER:
			continue
		var x: int = int(floor(float(q.get("x", 0.0))))
		var z: int = int(floor(float(q.get("z", 0.0))))
		if x < 0 or z < 0 or x >= ChunkData.SIZE or z >= ChunkData.SIZE:
			continue
		var dir := Vector2i(int(q.get("ramp_dir_x", 0)), int(q.get("ramp_dir_z", 0)))
		if dir == Vector2i.ZERO:
			continue
		var dir2 := Vector2i(int(q.get("ramp_dir2_x", 0)), int(q.get("ramp_dir2_z", 0)))
		var cell := Vector2i(x, z)
		if fc == FACE_RAMP_CORNER:
			if dir2 == Vector2i.ZERO:
				continue
			owned[cell] = {
				"corner": true,
				"side": false,
				"approach": false,
				"dir": dir,
				"dir2": dir2,
				"surface_h": float(q.get("y", 0.0)),
			}
		else:
			owned[cell] = {
				"corner": false,
				"side": false,
				"approach": false,
				"dir": dir,
				"dir2": Vector2i.ZERO,
				"surface_h": float(q.get("y", 0.0)),
			}
	data.ramp_map = owned
	if data.has_method("finalize_macro_metadata"):
		data.finalize_macro_metadata(true)


func get_ramp_dir_at_world(wx: float, wz: float) -> Vector2i:
	var entry := get_ramp_entry_at_world(wx, wz)
	return entry.get("dir", Vector2i.ZERO)


func get_ramp_entry_at_world(wx: float, wz: float) -> Dictionary:
	var ix := floori(wx)
	var iz := floori(wz)
	var chunk_coord := Vector2i(
		floori(float(ix) / float(ChunkData.SIZE)),
		floori(float(iz) / float(ChunkData.SIZE))
	)
	if not chunks.has(chunk_coord):
		return ChunkData.empty_ramp_entry()
	var data: ChunkData = chunks[chunk_coord].chunk_data
	var lx := ix - chunk_coord.x * ChunkData.SIZE
	var lz := iz - chunk_coord.y * ChunkData.SIZE
	if data.has_ramp(lx, lz):
		return data.get_ramp_entry(lx, lz)
	return ChunkData.empty_ramp_entry()


func get_chunk_data_at_world_pos(world_pos: Vector3) -> ChunkData:
	var chunk_x = floori(world_pos.x / float(ChunkData.SIZE))
	var chunk_z = floori(world_pos.z / float(ChunkData.SIZE))
	var chunk_coord = Vector2i(chunk_x, chunk_z)
	
	if chunks.has(chunk_coord):
		return chunks[chunk_coord].chunk_data
	return null

func rebuild_chunk_at_world(wx: float, wz: float) -> void:
	var key := Vector2i(
		floori(wx / float(ChunkData.SIZE)),
		floori(wz / float(ChunkData.SIZE))
	)
	rebuild_chunk(key)


func remesh_resident_maps_at_world(wx: float, wz: float) -> void:
	var key := Vector2i(
		floori(wx / float(ChunkData.SIZE)),
		floori(wz / float(ChunkData.SIZE))
	)
	if not chunks.has(key):
		return
	var view: ChunkView = chunks[key] as ChunkView
	if view == null or view.chunk_data == null:
		return
	view.chunk_data.preserve_column_maps = true
	view.chunk_data.skip_mesh_plan_cache = true
	view.chunk_data.snapshot_resident_maps()
	if pending.has(key) or _chunk_tasks.has(key):
		_chunk_gen_tokens[key] = int(_chunk_gen_tokens.get(key, 0)) + 1
		_merge_patch_pending(key, [], true, true)
		_schedule_rebuild_flush()
		return
	rebuild_chunk(key)


func set_rebuild_telemetry_context(trigger: String, meta: Dictionary = {}) -> void:
	_telemetry_trigger = trigger
	_telemetry_meta = meta.duplicate()


func invalidate_columns_at_world(wx: int, wz: int) -> void:
	_telemetry_trigger = "terrain_edit"
	var scope: Dictionary = _TerrainDirtyScope.compute_edit_scope(wx, wz, self)
	_last_patch_scope = scope
	_telemetry_meta = {
		"edit_wx": wx,
		"edit_wz": wz,
		"voxels_changed_hint": 1,
		"dirty_columns": int(scope.get("dirty_columns", 0)),
		"rebuilt_chunks": (scope.get("rebuild_chunks", []) as Array).size(),
		"skipped_chunks": (scope.get("skipped_chunks", []) as Array).size(),
		"neighbor_chunks": (scope.get("neighbor_chunks", []) as Array).size(),
	}
	var by_chunk: Dictionary = scope.get("by_chunk", {})
	for coord_variant in by_chunk.keys():
		var coord: Vector2i = coord_variant
		var local_cells: Array = by_chunk[coord]
		var full := _TerrainDirtyScope.should_full_rebuild(local_cells)
		if chunks.has(coord):
			var edit_view: ChunkView = chunks[coord] as ChunkView
			if edit_view and edit_view.chunk_data:
				edit_view.chunk_data.clear_preserve_map_snapshot()
				edit_view.chunk_data.preserve_column_maps = false
		_merge_patch_pending(coord, local_cells, full)
	_schedule_rebuild_flush()


func rebuild_region_at_world(wx: float, wz: float, _ring: int = 1) -> void:
	invalidate_columns_at_world(int(wx), int(wz))


func _clear_preserve_snapshot_after_apply(data: ChunkData, payload: Dictionary) -> void:
	if data == null or not data.has_preserve_map_snapshot():
		return
	if str(payload.get("column_source", "")) == "resident":
		data.clear_preserve_map_snapshot()


func _chunk_wants_preserved_maps(coord: Vector2i) -> bool:
	if not chunks.has(coord):
		return false
	var view: ChunkView = chunks[coord] as ChunkView
	if view == null or view.chunk_data == null:
		return false
	return view.chunk_data.preserve_column_maps or view.chunk_data.has_preserve_map_snapshot()


func _merge_patch_pending(coord: Vector2i, local_cells: Array, full: bool, preserve_maps: bool = false) -> void:
	if _patch_pending.has(coord):
		var entry: Dictionary = _patch_pending[coord]
		var bucket: Array = entry.get("local", [])
		for cell_variant in local_cells:
			var cell: Vector2i = cell_variant
			if cell not in bucket:
				bucket.append(cell)
		entry["local"] = bucket
		entry["full"] = bool(entry.get("full", false)) or full
		entry["preserve_maps"] = bool(entry.get("preserve_maps", false)) or preserve_maps
		_patch_pending[coord] = entry
	else:
		_patch_pending[coord] = {
			"local": local_cells.duplicate(),
			"full": full,
			"preserve_maps": preserve_maps,
		}


func _refresh_preserve_halo(data: ChunkData) -> void:
	if data == null:
		return
	data._refresh_halo_interior_from_maps()
	if not data._has_halo_surface:
		return
	var size := ChunkData.SIZE
	var halo := ChunkData.HALO
	var dim := size + halo * 2
	for ix in dim:
		for iz in dim:
			var lx := ix - halo
			var lz := iz - halo
			if lx >= 0 and lx < size and lz >= 0 and lz < size:
				continue
			var wx := data.position.x * size + lx
			var wz := data.position.y * size + lz
			var ncoord := world_to_chunk_coord(wx, wz)
			if not chunks.has(ncoord):
				continue
			var nview: ChunkView = chunks[ncoord] as ChunkView
			if nview == null or nview.chunk_data == null:
				continue
			var nd: ChunkData = nview.chunk_data
			var nlx := wx - ncoord.x * size
			var nlz := wz - ncoord.y * size
			if nlx < 0 or nlz < 0 or nlx >= size or nlz >= size:
				continue
			if nd.surface_map.size() <= nlx:
				continue
			var row_v = nd.surface_map[nlx]
			if row_v == null or not (row_v is Array) or (row_v as Array).size() <= nlz:
				continue
			var row: Array = row_v
			if ix >= data._halo_surface.size() or data._halo_surface[ix] == null:
				continue
			if iz >= data._halo_surface[ix].size():
				continue
			data._halo_surface[ix][iz] = float(row[nlz])


func _rebuild_high_priority(coord: Vector2i) -> bool:
	var player_chunk := get_player_chunk_coord()
	var dist: int = maxi(absi(coord.x - player_chunk.x), absi(coord.y - player_chunk.y))
	return dist <= 2


## Same-frame terrain edits (rapid dig/build) coalesce into one flush so we do not
## pay capture_worker_snapshot / enqueue N times for N edits in one frame.
var _flush_frame_id: int = -1


func flush_rebuild_pending() -> void:
	var frame_id: int = Engine.get_process_frames()
	if frame_id == _flush_frame_id:
		_rebuild_flush_needed = true
		return
	_flush_frame_id = frame_id
	_flush_rebuild_pending()


func _schedule_rebuild_flush() -> void:
	if not is_inside_tree() or _shutting_down:
		return
	_rebuild_flush_needed = true
	set_meta("_rebuild_flush_scheduled", true)


var edit_flush_count: int = 0
var edit_flush_chunk_count: int = 0


func _flush_rebuild_pending() -> void:
	edit_flush_count += 1
	edit_flush_chunk_count = _patch_pending.size() + _rebuild_pending.size()
	_rebuild_flush_needed = false
	if has_meta("_rebuild_flush_scheduled"):
		remove_meta("_rebuild_flush_scheduled")
	if not _rebuild_pending.is_empty():
		var legacy_keys: Array = _rebuild_pending.keys()
		_rebuild_pending.clear()
		for key_variant in legacy_keys:
			rebuild_chunk(key_variant)
	if not _patch_pending.is_empty():
		var pending_copy: Dictionary = _patch_pending.duplicate(true)
		_patch_pending.clear()
		for coord_variant in pending_copy.keys():
			var coord: Vector2i = coord_variant
			var entry: Dictionary = pending_copy.get(coord, {})
			if entry.is_empty():
				continue
			var local_cells: Array = entry.get("local", [])
			var full: bool = bool(entry.get("full", false))
			if not chunks.has(coord):
				continue
			if bool(entry.get("preserve_maps", false)):
				var pv: ChunkView = chunks[coord] as ChunkView
				if pv and pv.chunk_data:
					pv.chunk_data.preserve_column_maps = true
					pv.chunk_data.skip_mesh_plan_cache = true
			_enqueue_chunk_mesh_work(coord, full, local_cells, _rebuild_high_priority(coord), false)
	if not _patch_pending.is_empty() or not _rebuild_pending.is_empty():
		_schedule_rebuild_flush()


func await_rebuild_idle(max_frames: int = 2400) -> void:
	var frames := 0
	while (
		_rebuild_flush_needed
		or has_meta("_rebuild_flush_scheduled")
		or not _rebuild_pending.is_empty()
		or not _patch_pending.is_empty()
		or not _chunk_tasks.is_empty()
		or not pending.is_empty()
	) and frames < max_frames:
		await get_tree().process_frame
		frames += 1
	var CV = load("res://chunks/chunk_view.gd")
	while frames < max_frames and CV and (
		int(CV.pending_buffer_upload_count()) > 0
		or int(CV.pending_surface_upload_count()) > 0
	):
		CV.drain_pending_surface_uploads(8, 2_000_000)
		CV.drain_pending_buffer_uploads(16, 2_000_000)
		await get_tree().process_frame
		frames += 1
	await get_tree().process_frame


func world_to_chunk_coord(wx: int, wz: int) -> Vector2i:
	return Vector2i(
		floori(float(wx) / float(ChunkData.SIZE)),
		floori(float(wz) / float(ChunkData.SIZE))
	)


func world_to_chunk_coord_v3(world_pos: Vector3) -> Vector2i:
	return world_to_chunk_coord(floori(world_pos.x), floori(world_pos.z))


func get_chunk_count() -> int:
	return chunks.size()


func get_player_chunk_coord() -> Vector2i:
	var col := _player_column_pos()
	return Vector2i(
		floori(col.x / float(ChunkData.SIZE)),
		floori(col.y / float(ChunkData.SIZE))
	)


func is_chunk_loaded(coord: Vector2i) -> bool:
	return chunks.has(coord)


func start_stream_coords() -> Array:
	var pc := get_player_chunk_coord()
	var out: Array = []
	var seen: Dictionary = {}
	for z in range(pc.y - RENDER_DISTANCE, pc.y + RENDER_DISTANCE + 2):
		for x in range(pc.x - RENDER_DISTANCE, pc.x + RENDER_DISTANCE + 2):
			var key := Vector2i(x, z)
			if _WorldBakeService_is_outside(key):
				continue
			out.append(key)
			seen[key] = true
	for extra_v in _start_threat_chunk_coords():
		var extra: Vector2i = extra_v
		if seen.has(extra) or _WorldBakeService_is_outside(extra):
			continue
		out.append(extra)
		seen[extra] = true
	return out


func _start_threat_chunk_coords() -> Array:
	if not is_inside_tree():
		return []
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal == null or not crystal.has_method("get_origin_cell"):
		return []
	var origin: Vector2i = crystal.get_origin_cell()
	var oc := Vector2i(
		floori(float(origin.x) / float(ChunkData.SIZE)),
		floori(float(origin.y) / float(ChunkData.SIZE))
	)
	var extra: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			extra.append(oc + Vector2i(dx, dz))
	return extra


func get_stream_status() -> Dictionary:
	return {
		"resident": chunks.size(),
		"stream_queue": _stream_load_pending.size(),
		"mesh_pending": pending.size(),
		"inflight": _chunk_tasks.size(),
		"rebuild_pending": _patch_pending.size(),
		"unload_pending": _stream_unload_pending.size(),
	}


func mesh_pipeline_busy() -> bool:
	return (
		_rebuild_flush_needed
		or has_meta("_rebuild_flush_scheduled")
		or not _rebuild_pending.is_empty()
	)


func column_mesh_generation(wx: int, wz: int) -> int:
	return int(_chunk_gen_tokens.get(world_to_chunk_coord(wx, wz), 0))


func column_mesh_block_reason(wx: int, wz: int) -> String:
	var coord := world_to_chunk_coord(wx, wz)
	if coord in _stream_unload_pending:
		return "unloading"
	if _mesh_apply_queued(coord):
		return "awaiting_apply"
	var resident := chunks.has(coord)
	var inflight := pending.has(coord) or _chunk_tasks.has(coord)
	if resident and inflight:
		return "remesh_inflight"
	if _patch_pending.has(coord) or _rebuild_pending.has(coord):
		return "rebuild"
	if not resident:
		if inflight:
			return "baking"
		if _stream_load_pending.has(coord):
			return "queued"
		return "missing"
	if _resident_mesh_quad_count(coord) <= 0:
		return "empty_mesh"
	return ""


func columns_mesh_settled(cells: Array) -> bool:
	if mesh_pipeline_busy():
		return false
	for cell_v in cells:
		var cell := _column_from_variant(cell_v)
		if column_mesh_block_reason(cell.x, cell.y) != "":
			return false
	return true


func _column_from_variant(cell) -> Vector2i:
	if cell is Vector2i:
		return cell
	if cell is Vector2:
		var v: Vector2 = cell
		return Vector2i(int(v.x), int(v.y))
	return Vector2i.ZERO


func _mesh_apply_queued(coord: Vector2i) -> bool:
	for item_v in _mesh_completion_queue:
		if typeof(item_v) != TYPE_DICTIONARY:
			continue
		if (item_v as Dictionary).get("coord", null) == coord:
			return true
	return false


func _resident_mesh_quad_count(coord: Vector2i) -> int:
	var view = chunks.get(coord, null)
	if view == null or not ("mesh_data" in view):
		return 0
	var md = view.mesh_data
	if typeof(md) != TYPE_DICTIONARY:
		return 0
	var quads = (md as Dictionary).get("quads", [])
	if quads is Array:
		return (quads as Array).size()
	return 0


func get_chunk_lifecycle(coord: Vector2i) -> String:
	if chunks.has(coord):
		if coord in _stream_unload_pending:
			return "unloading"
		if _patch_pending.has(coord):
			return "rebuild"
		return "resident"
	if pending.has(coord) or _chunk_tasks.has(coord):
		return "baking"
	if _stream_load_pending.has(coord):
		return "queued"
	return "missing"


## Start gate radius in chunks around the player: 1 = 3x3, 2 = 5x5.
## CRYSTALSTORM_START_RADIUS=-1 keeps the old full render-distance gate.
static func start_gate_radius_from_env() -> int:
	var raw := OS.get_environment("CRYSTALSTORM_START_RADIUS").strip_edges()
	return int(raw) if raw.is_valid_int() else 1


func start_gate_coords() -> Array:
	var r := start_gate_radius_from_env()
	if r < 0:
		return start_stream_coords()
	var pc := get_player_chunk_coord()
	var out: Array = []
	var seen: Dictionary = {}
	for z in range(pc.y - r, pc.y + r + 1):
		for x in range(pc.x - r, pc.x + r + 1):
			var key := Vector2i(x, z)
			if _WorldBakeService_is_outside(key):
				continue
			out.append(key)
			seen[key] = true
	for extra_v in _start_threat_chunk_coords():
		var extra: Vector2i = extra_v
		if seen.has(extra) or _WorldBakeService_is_outside(extra):
			continue
		out.append(extra)
		seen[extra] = true
	return out


func start_region_status() -> Dictionary:
	var needed: Array = start_gate_coords()
	var bake = load("res://world/world_bake_service.gd").get_active()
	var stream_first: bool = bake != null and bake.has_method("stream_first_from_env") and bool(bake.stream_first_from_env())
	var packages := 0
	var resident := 0
	for c_v in needed:
		var c: Vector2i = c_v
		if stream_first:
			packages += 1
		elif bake != null and bake.has_method("package_ready") and bool(bake.package_ready(c)):
			packages += 1
		elif bake == null or not bool(bake.get("bake_in_progress")):
			packages += 1
		if chunks.has(c):
			resident += 1
	var need_n: int = needed.size()
	return {
		"needed": need_n,
		"packages": packages,
		"resident": resident,
		"ready": need_n > 0 and resident >= need_n and packages >= need_n,
	}


func start_region_missing() -> Array:
	var out: Array = []
	for c_v in start_gate_coords():
		var c: Vector2i = c_v
		if not chunks.has(c):
			var inq := false
			for it in _mesh_completion_queue:
				if it is Dictionary and it.get("coord", null) == c:
					inq = true
			out.append({"c": c, "pending": pending.has(c), "task": _chunk_tasks.has(c), "tok": _chunk_gen_tokens.get(c, -1), "meshq": inq, "pend_val": str(pending.get(c, null))})
	return out


func is_start_region_ready() -> bool:
	return bool(start_region_status().get("ready", false))


func is_world_cell_loaded(wx: int, wz: int) -> bool:
	return is_chunk_loaded(world_to_chunk_coord(wx, wz))


func is_world_pos_loaded(world_pos: Vector3) -> bool:
	return is_world_cell_loaded(floori(world_pos.x), floori(world_pos.z))


func rebuild_chunk(key: Vector2i) -> void:
	if _shutting_down:
		return
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_rebuild")
	_chunk_gen_tokens[key] = int(_chunk_gen_tokens.get(key, 0)) + 1
	if chunks.has(key):
		_regenerate_chunk_mesh(key, true)
		if profiler and profiler.has_method("end"):
			profiler.end("chunk_rebuild")
		return
	pending.erase(key)
	_reap_chunk_task(key)
	request_chunk(key, true)
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_rebuild")


func rebuild_chunks():
	for coord: Vector2i in chunks.keys():
		rebuild_chunk(coord)
		
func spawn_area_ready(center_x:int, center_z:int) -> bool:
	var r := 0
	for x in range(center_x - r, center_x + r + 1):
		for z in range(center_z - r, center_z + r + 1):
			var key = Vector2i(x, z)
			if not chunks.has(key):
				return false
	return true

var _boost_saved_chunks: int = -1
var _boost_saved_budget: int = -1
var _boost_saved_inflight: int = -1
var _boost_saved_starts: int = -1


func begin_start_region_boost() -> void:
	if _boost_saved_chunks < 0:
		_boost_saved_chunks = MAX_CHUNKS_PER_FRAME
		_boost_saved_budget = chunk_upload_budget_us
	if _boost_saved_inflight < 0:
		_boost_saved_inflight = MAX_INFLIGHT_CHUNKS
		_boost_saved_starts = max_stream_starts_per_frame
	MAX_CHUNKS_PER_FRAME = maxi(_boost_saved_chunks, 3)
	chunk_upload_budget_us = maxi(_boost_saved_budget, 8000)
	# The game is not interactive yet: use every spare core for the start area.
	MAX_INFLIGHT_CHUNKS = maxi(_boost_saved_inflight, maxi(OS.get_processor_count() - 1, 2))
	max_stream_starts_per_frame = maxi(_boost_saved_starts, 4)
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and "hold_fill" in bake:
		bake.hold_fill = true


func prioritize_start_region_packages() -> int:
	# Gate chunks jump the stream queue so the start area is built first.
	var pc := get_player_chunk_coord()
	for g_v in start_gate_coords():
		var g: Vector2i = g_v
		if _stream_load_pending.has(g):
			var e: Dictionary = _stream_load_pending[g]
			var d := float(maxi(absi(g.x - pc.x), absi(g.y - pc.y)))
			if float(e.get("score", 0.0)) < 1.0e9 - d:
				e["score"] = 1.0e9 - d
				e["urgent"] = true
				_stream_load_order_dirty = true
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake == null or not bake.has_method("prioritize_stream_coords"):
		return 0
	if bake.has_method("stream_first_from_env") and bool(bake.stream_first_from_env()):
		return 0
	return int(bake.prioritize_stream_coords(start_stream_coords()))


func end_start_region_boost() -> void:
	if _boost_saved_chunks >= 0:
		MAX_CHUNKS_PER_FRAME = _boost_saved_chunks
		chunk_upload_budget_us = _boost_saved_budget
		_boost_saved_chunks = -1
		_boost_saved_budget = -1
	if _boost_saved_inflight >= 0:
		MAX_INFLIGHT_CHUNKS = _boost_saved_inflight
		max_stream_starts_per_frame = _boost_saved_starts
		_boost_saved_inflight = -1
		_boost_saved_starts = -1
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and "hold_fill" in bake:
		bake.hold_fill = false


const _NearProps = preload("res://world/near_props.gd")
var _near_props: Node3D = null


func _wave_lod_recheck(c: Vector2i) -> void:
	var old: Vector2i = ChunkSurfaceMeshBuilder.wave_lod_center
	var had: bool = ChunkSurfaceMeshBuilder.wave_lod_on
	ChunkSurfaceMeshBuilder.wave_lod_center = c
	ChunkSurfaceMeshBuilder.wave_lod_on = true
	if not had or old == c:
		return
	var r: int = ChunkSurfaceMeshBuilder.WAVE_LOD_R
	for key: Vector2i in chunks.keys():
		var was_near: bool = maxi(absi(key.x - old.x), absi(key.y - old.y)) <= r
		var now_near: bool = maxi(absi(key.x - c.x), absi(key.y - c.y)) <= r
		if was_near != now_near:
			rebuild_chunk(key)


func _update_near_props(c: Vector2i) -> void:
	if _near_props == null:
		_near_props = _NearProps.new()
		_near_props.manager = self
		add_child(_near_props)
		chunk_unloaded.connect(_near_props.drop_chunk)
	_near_props.set_center(c)
