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
var _chunk_tasks := {}  # coord -> WorkerThreadPool task id for async gen
var _chunk_gen_tokens := {}  # coord -> monotonic token; stale worker results are dropped
var _mesh_completion_queue: Array = []
var _shutting_down: bool = false
## When true, streaming and stream-driven loads are frozen (transactional save load).
var stream_paused: bool = false

# Optimization: only update when player moves to new chunk
var _last_chunk_key: Vector2i = Vector2i(-99999, -99999)

# Player will be obtained via the 'player_ready' signal
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
var _stream_load_pending: Dictionary = {}  # coord -> { score, urgent }
var _stream_unload_pending: Array = []
var _lifecycle_by_coord: Dictionary = {}  # coord -> lifecycle state string
var _last_player_chunk_for_velocity: Vector2i = Vector2i(-99999, -99999)
var _player_chunk_velocity: Vector2i = Vector2i.ZERO
var _stream_budget_used_us: int = 0
var _rebuild_pending: Dictionary = {}
var _patch_pending: Dictionary = {}  # coord -> { "local": Array, "full": bool }
var _last_patch_scope: Dictionary = {}
var _telemetry_trigger: String = "stream"
var _telemetry_meta: Dictionary = {}
## When false, micro-flagged cells are meshed (micro column patch path only).
var _mesh_defer_micro_columns: bool = true
## Shared worker scratch removed: greedy visit grids and micro-skip sets are job-local
## (ChunkPipeline.alloc_greedy_visited / ChunkData._mesh_job_micro_skip).
## Process-frame rebuild flush (avoids call_deferred self-requeue flooding the message queue).
var _rebuild_flush_needed: bool = false
## Amortized stream ordering: full re-sort only when pending mutates (not every frame).
var _stream_load_order_dirty: bool = true
var _stream_unload_order_dirty: bool = true
var _stream_load_sorted: Array = []  # cached sort_load_candidates rows
## Mesh completion queue: re-sort once per drain, not on every worker push.
var _mesh_completion_order_dirty: bool = true
## Cached autoload refs (avoid get_node every _process / drain).
var _profiler_node: Node = null
var _fbs_node: Node = null
## Detached ChunkView pool — avoids instantiate + free on stream unload/reload.
const _VIEW_POOL_MAX: int = 48
var _view_pool: Array = []
## When true, _ready skips bake bootstrap; CompositionRoot awaits bootstrap_world_bake_async().
var defer_world_bake_bootstrap: bool = false

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

	# Prefer immutable baked base for streaming when present (no pipeline redesign).
	if defer_world_bake_bootstrap:
		# Composition path: await bootstrap_world_bake_async() after add_child.
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


## Composition-root path: load or cooperatively rebuild production bake (128×128).
func bootstrap_world_bake_async() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world") if get_tree() else null
	if player == null and get_tree():
		player = get_tree().get_first_node_in_group("player")
	await _bootstrap_world_bake_async()
	_bootstrap_mesh_plan_cache()
	_request_initial_stream()


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
	# Sync path (legacy / tests): may block during rebuild.
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
	# Plans are normally ensured inside WorldBakeService.bootstrap_for_world(host=self).
	# Never silently rebuild plans at startup — only load if present.
	var mp_script = load("res://world/mesh_plan_cache.gd")
	if mp_script == null:
		return
	var cache = mp_script.get_active()
	if cache != null and bool(cache.valid):
		if bool(cache.streamed_from_bake) or cache.plan_count() > 0:
			return
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bool(bake.valid) and bool(bake.streamed):
		# Streamed packages already embed plans; bind façade without baking.
		if bake.has_method("ensure_mesh_plans"):
			bake.ensure_mesh_plans(self, world)
		return
	cache = mp_script.ensure_active() if mp_script.has_method("ensure_active") else null
	if cache == null:
		return
	# Load-only fallback (no bake-on-new unless explicitly forced by env).
	var seed: int = int(world.world_seed) if "world_seed" in world else 0
	var r: int = int(bake.radius) if bake != null and "radius" in bake else 2
	if cache.has_method("load_plans") and cache.load_plans(seed, r):
		mp_script.set_active(cache)
		print("[MeshPlanCache] mode=loaded chunks=%s bytes=%s bake_ms=0" % [
			str(cache.plan_count()), str(cache.last_bytes)
		])
		return
	# Explicit env only: rebuild monolith plans (dev/migration).
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


## Join a finished (or finishing) pool task and drop its tracking entry.
## Godot requires wait_for_task_completion for each add_task id; erasing without
## wait left handles for engine teardown to free twice / UAF.
func _reap_chunk_task(coord: Vector2i) -> void:
	if not _chunk_tasks.has(coord):
		return
	var tid = _chunk_tasks[coord]
	_chunk_tasks.erase(coord)
	if tid is int:
		# Main-thread join can block until the worker finishes — attribute only.
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


## Explicit teardown while the tree is still alive (composition.shutdown / harness).
## Safe to remove_child + free views here. Must NOT be used from _exit_tree (double free).
func release_all_chunks_for_teardown() -> void:
	if has_meta("_teardown_released"):
		return
	set_meta("_teardown_released", true)
	_shutdown_trace("release_all begin views=%d is_inside_tree=%s" % [
		chunks.size(), str(is_inside_tree())
	])
	shutdown_workers()
	# Must clear uploads before freeing views (ownership: pending Multimesh refs).
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


## Called when SceneTree is already destroying this node (window close / quit).
## Children will be freed by the engine — DO NOT queue_free ChunkViews here
## (that is the double-free root cause: parent frees children twice).
func _exit_tree() -> void:
	_shutdown_trace("_exit_tree begin already_released=%s children=%d chunks=%d" % [
		str(has_meta("_teardown_released")),
		get_child_count(),
		chunks.size(),
	])
	if has_meta("_teardown_released"):
		# Explicit teardown already ran; only ensure workers stopped.
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
	# Detach ownership only — SceneTree frees ChunkView children.
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
	# Pooled views are detached (not SceneTree children) — free explicitly.
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
		# Drop pending GPU uploads that still reference this view's MultiMeshes.
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
		# View is detached: return ChunkData shell to pool immediately (view no longer owns it).
		if data_to_pool != null:
			_pool_chunk_data_after_view_free(data_to_pool)
		# Prefer ChunkView pool over free — MultiMesh/MeshInstance children stay for reuse.
		if not _try_pool_chunk_view(view):
			call_deferred("_profiled_free_chunk_view", view)
	# Release bake package only when no remaining resident/pending chunk needs it
	# as a mesh-halo neighbor (chebyshev ≤ 1). Premature release forces cold
	# ensure+deserialize on the next stream start's capture_worker_snapshot (~11ms).
	_maybe_release_bake_package(key)
	_set_lifecycle_state(key, _ChunkStreamLifecycle.UNLOADED)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.record_unload(key, "complete", {"active_chunks": chunks.size()})
	chunk_unloaded.emit(key)
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkManager::_unload_chunk_view")
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_unload")


## Drop streamed package RAM when no loaded/pending chunk still needs it for halo mesh.
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


## Park a detached ChunkView for reuse. Returns false if pool full / invalid.
func _try_pool_chunk_view(view: Node) -> bool:
	if view == null or not is_instance_valid(view) or _shutting_down:
		return false
	if _view_pool.size() >= _VIEW_POOL_MAX:
		return false
	if view is not ChunkView:
		return false
	# Detach GPU resources from free path but keep MultiMesh nodes for next setup.
	var cv := view as ChunkView
	cv.chunk_data = null
	cv.mesh_data = {}
	if cv.layer_container and is_instance_valid(cv.layer_container):
		for child in cv.layer_container.get_children():
			if child is MultiMeshInstance3D:
				var mmi := child as MultiMeshInstance3D
				# Keep MultiMesh resource; zero instance count to drop GPU buffers.
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


## Measurement-only: destroy a detached ChunkView during MessageQueue flush.
## Replaces queue_free so free cost is attributed (same frame deferred phase).
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


func _enqueue_chunk_generation(coord: Vector2i, high_priority: bool = false) -> void:
	if pending.has(coord) or _chunk_tasks.has(coord):
		return
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled():
		SPP.begin_chunk(coord)
	# Prefetch streamed bake package + halo neighbors on main thread so
	# capture_worker_snapshot stays on the hot (resident) path (~4ms vs ~11ms cold).
	var bake_pre = load("res://world/world_bake_service.gd").get_active()
	if bake_pre != null and bake_pre.valid:
		if bake_pre.has_method("coord_in_package") and bake_pre.coord_in_package(coord):
			if bake_pre.has_method("ensure_chunk_resident"):
				bake_pre.ensure_chunk_resident(coord)
			# Neighbor packages: data only (surfaces for halo); no vegetation reinstall.
			if bake_pre.has_method("ensure_package_data_resident"):
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dz == 0:
							continue
						var n := Vector2i(coord.x + dx, coord.y + dz)
						if bake_pre.coord_in_package(n):
							bake_pre.ensure_package_data_resident(n)
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
	var alloc_path := "pool_reuse" if int(pool_stats_before.get("alloc_reuse", 0)) < int(_ChunkDataPool.get_stats().get("alloc_reuse", 0)) else "ChunkData.new"
	if SPP and SPP.is_enabled():
		SPP.record("chunk_data_alloc", Time.get_ticks_usec() - t_alloc, coord)
	var t_snap := Time.get_ticks_usec()
	data.capture_worker_snapshot()
	if SPP and SPP.is_enabled():
		SPP.record("worker_snapshot_capture", Time.get_ticks_usec() - t_snap, coord)
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

	var task_id := WorkerThreadPool.add_task(
		Callable(self, "_chunk_mesh_task").bind(
			coord, data, token, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}
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
		_merge_patch_pending(coord, dirty_local, full_rebuild)
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
				if not _quad_intersects_rect(q, patch_rect):
					keep_quads.append(q)
			if terrain_surface_mesh:
				prior_surface_cache = _TerrainSurfaceCache.duplicate_cache(
					_TerrainSurfaceCache.cache_from_payload(view.mesh_data)
				)

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
		return float(data.surface_map[x][z])
	return data.get_surface_y(x, z)


func _tile_type_at(data: ChunkData, x: int, z: int) -> int:
	if x >= 0 and x < ChunkData.SIZE and z >= 0 and z < ChunkData.SIZE:
		return int(data.tile_map[x][z])
	return data.get_tile_type(x, z)


func _build_mesh(data: ChunkData) -> Dictionary:
	return _build_mesh_region(data, Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), true)


func _build_mesh_region(data: ChunkData, rect: Rect2i, full_chunk: bool = false) -> Dictionary:
	if not data._maps_resident:
		data.ensure_column_maps()
	var out_quads := []
	var x0 := rect.position.x
	var z0 := rect.position.y
	var x1 := rect.position.x + rect.size.x
	var z1 := rect.position.y + rect.size.y

	# Job-local micro skip on this ChunkData (exclusive to the in-flight worker for this data).
	data._mesh_job_micro_skip = {}
	if _mesh_defer_micro_columns and data.is_micro_terrain_enabled():
		data._mesh_job_micro_skip = _MicroTerrainMeshCompositor.build_skip_set(data, rect)

	if not full_chunk:
		_clear_ramp_map_in_rect(data, rect)

	var concave_cells := (
		_find_concave_corner_cells(data)
		if full_chunk
		else _find_concave_corner_cells_in_rect(data, rect)
	)
	if full_chunk:
		_emit_ramps(data, out_quads, concave_cells)
	else:
		_emit_ramps_in_rect(data, out_quads, concave_cells, rect)
	_emit_concave_corner_prisms(data, out_quads, concave_cells)
	_emit_dug_strata_region(data, out_quads, x0, z0, x1, z1)
	_emit_build_strata_region(data, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 1, 0), FACE_TOP, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, -1, 0), 6, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, -1, 0), 4, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(-1, 0, 0), FACE_NEG_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(1, 0, 0), FACE_POS_X, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, -1), FACE_NEG_Z, out_quads, x0, z0, x1, z1)
	_greedy_mesh_plane_region(data, Vector3i(0, 0, 1), FACE_POS_Z, out_quads, x0, z0, x1, z1)
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

func _skips_greedy_surface_cell(data: ChunkData, x: int, z: int) -> bool:
	if data != null and not data._mesh_job_micro_skip.is_empty() \
			and data._mesh_job_micro_skip.has(Vector2i(x, z)):
		return true
	if data.has_ramp(x, z):
		return true
	return _is_ramp_approach_from_landing(data, x, z)


func _build_micro_mesh_region(data: ChunkData, rect: Rect2i) -> Dictionary:
	var out_quads: Array = []
	var skip_set: Dictionary = _MicroTerrainMeshCompositor.build_skip_set(data, rect)
	var cells_meshed: int = _MicroTerrainMeshCompositor.compose(data, rect, out_quads, self, skip_set)
	return {"quads": out_quads, "count": out_quads.size(), "cells_meshed": cells_meshed}


func _emit_single_surface_top_quad(data: ChunkData, out_quads: Array, x: int, z: int) -> void:
	if _skips_greedy_surface_cell(data, x, z):
		return
	var sy: float = _surface_y_at(data, x, z)
	if sy >= float(ChunkData.HEIGHT):
		return
	var vox: int = _tile_type_at(data, x, z)
	if vox == VoxelTypes.AIR:
		return
	out_quads.append({
		"x": x,
		"y": sy,
		"z": z,
		"dim_x": 1.0,
		"dim_y": 1.0,
		"dim_z": 1.0,
		"uv_w": 1.0,
		"uv_h": 1.0,
		"type": vox,
		"face_code": FACE_TOP,
	})


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
				if sy >= float(ChunkData.HEIGHT):
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
	if surface_h >= 0.0:
		if surface_h > ramp_max_surface_height:
			return false
		if _world_border_should_force_ramp(world_x, world_z) and surface_h > ramp_mountain_cutoff_height:
			return false
	var seed_val := world_x * 73856093 ^ world_z * 19349663 ^ dir.x * 83492791 ^ dir.y * 50331653
	return int(seed_val & 0x7fffffff) % 100 < ramp_placement_chance


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


## Cardinal ramps sit on the landing (higher) column, sloping down toward the lower neighbor.
func _step_in_dirs(data: ChunkData, x: int, z: int, cell_h: float, world_x: int, world_z: int) -> Array:
	if _has_player_build_at(data, x, z):
		return []
	var out: Array = []
	for d in _RAMP_DIRS:
		var lx: int = x - d.x
		var lz: int = z - d.y
		if _has_player_build_at(data, lx, lz):
			continue
		var lh: float = _sample_height(data, lx, lz)
		var toward_low := Vector2i(-d.x, -d.y)
		if _is_step_height(cell_h - lh) and _should_place_ramp(world_x, world_z, toward_low, cell_h):
			out.append(toward_low)
	return out


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


func _append_ramp_quad(out_quads: Array, x: int, z: int, low_h: float, vox: int, entry: Dictionary) -> void:
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	var dir2: Vector2i = entry.get("dir2", Vector2i.ZERO)
	var is_corner: bool = dir2 != Vector2i.ZERO
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
		"uv_w": 1.0,
		"uv_h": 1.0,
		"type": vox,
		"face_code": FACE_RAMP_CORNER if is_corner else FACE_RAMP,
	}
	out_quads.append(quad)


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


func _find_concave_corner_cells(data: ChunkData) -> Dictionary:
	# Three solids in an L; concave cell (x,z) is the gap. Prism touches the two inner faces.
	var result: Dictionary = {}
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if result.has(cell) or _has_player_build_at(data, x, z):
				continue
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			for pat in _CONCAVE_L_PATTERNS:
				var arms: Array = pat["arms"]
				var leg_x: int = pat["leg_x"]
				var leg_z: int = pat["leg_z"]
				var h: float = _sample_height(data, x + arms[2].x, z + arms[2].y)
				if h < 0.0:
					continue
				var valid := true
				for arm in arms:
					if not is_equal_approx(_sample_height(data, x + arm.x, z + arm.y), h):
						valid = false
						break
				if not valid:
					continue
				if not _is_concave_corner_cell(data, x, z, h):
					continue
				if not TerrainRamps.should_place_concave_prism(world_x, world_z, leg_x, leg_z):
					continue
				var vox: int = _tile_type_at(data, x + arms[2].x, z + arms[2].y)
				if vox == VoxelTypes.AIR:
					vox = _tile_type_at(data, x + arms[0].x, z + arms[0].y)
				result[cell] = {
					"h": h,
					"leg_x": leg_x,
					"leg_z": leg_z,
					"vox": vox,
				}
				break
	return result


func _emit_concave_corner_prisms(data: ChunkData, out_quads: Array, concave_cells: Dictionary) -> void:
	for cell in concave_cells:
		if _skips_greedy_surface_cell(data, cell.x, cell.y):
			continue
		if _has_player_build_at(data, cell.x, cell.y):
			continue
		var entry: Dictionary = concave_cells[cell]
		var x: int = cell.x
		var z: int = cell.y
		var leg_x: int = entry["leg_x"]
		var leg_z: int = entry["leg_z"]
		var h: float = entry["h"]
		var vox: int = entry["vox"]
		data.set_concave_prism(x, z, leg_x, leg_z, h)
		var gap_h: float = _surface_y_at(data, x, z)
		var layer: float = _WorldSettings.get_active().layer_height()
		var gap_tile: int = _tile_type_at(data, x, z)
		if gap_tile == VoxelTypes.AIR:
			gap_tile = vox
		_append_voxel_face(out_quads, float(x), gap_h + layer, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, gap_tile, FACE_TOP)
		if gap_h < h - layer * 0.1:
			var fill_y: float = gap_h
			while fill_y < h - layer * 0.05:
				fill_y += layer
				_append_voxel_face(out_quads, float(x), fill_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_TOP)
				if leg_x > 0:
					_append_voxel_face(out_quads, float(x), fill_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_NEG_X)
				else:
					_append_voxel_face(out_quads, float(x), fill_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_POS_X)
				if leg_z > 0:
					_append_voxel_face(out_quads, float(x), fill_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_NEG_Z)
				else:
					_append_voxel_face(out_quads, float(x), fill_y, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_POS_Z)
		# Solid support under the diagonal prism (fills the hole + walkable collision).
		_append_voxel_face(out_quads, float(x), h, float(z), 1.0, 1.0, 1.0, 1.0, 1.0, vox, FACE_TOP)
		out_quads.append({
			"x": x,
			"y": entry["h"],
			"z": z,
			"dim_x": 1.0,
			"dim_y": 1.0,
			"dim_z": 1.0,
			"ramp_dir_x": leg_x,
			"ramp_dir_z": 0,
			"ramp_dir2_x": 0,
			"ramp_dir2_z": leg_z,
			"uv_w": 1.0,
			"uv_h": 1.0,
			"type": entry["vox"],
			"face_code": FACE_RAMP_SIDE,
		})


func _find_corner_low_cells(data: ChunkData) -> Dictionary:
	var result: Dictionary = {}
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			if _has_player_build_at(data, x, z) or _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_outs: Array = _step_out_dirs(data, x, z, low_h, world_x, world_z)
			if step_outs.size() != 2:
				continue
			var d_a: Vector2i = step_outs[0]
			var d_b: Vector2i = step_outs[1]
			if _dirs_perpendicular(d_a, d_b):
				result[Vector2i(x, z)] = [d_a, d_b]
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

			# L-shaped steps need a corner prism, not a single cardinal wedge.
			var corner_dirs: Array = _pick_corner_dirs(data, x, z, planned)
			if corner_dirs.size() == 2:
				continue

			var d: Vector2i = planned[cell]
			var approach_cell := Vector2i(x + d.x, z + d.y)
			if corner_low_cells.has(approach_cell):
				continue
			data.set_ramp_cardinal(x, z, d)
			_clear_ramp_approach_block(data, x, z, d)
			_append_ramp_quad(out_quads, x, z, low_h, vox, {
				"dir": d,
				"dir2": Vector2i.ZERO,
			})

	# Corner + side-entry ramps that blend into step faces (not only outward steps).
	for x in range(ChunkData.SIZE):
		for z in range(ChunkData.SIZE):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var corner_dirs: Array = corner_low_cells.get(cell, _pick_corner_dirs(data, x, z, planned))
			if corner_dirs.size() != 2:
				continue
			if _skips_greedy_surface_cell(data, x, z) and not corner_low_cells.has(cell):
				continue
			var d_a: Vector2i = corner_dirs[0]
			var d_b: Vector2i = corner_dirs[1]
			var vox_corner: int = _tile_type_at(data, x, z)
			data.set_ramp_corner(x, z, d_a, d_b)
			_append_ramp_quad(out_quads, x, z, low_h, vox_corner, {
				"dir": d_a,
				"dir2": d_b,
			})


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
			var world_x: int = data.position.x * ChunkData.SIZE + x
			var world_z: int = data.position.y * ChunkData.SIZE + z
			var step_outs: Array = _step_out_dirs(data, x, z, low_h, world_x, world_z)
			if step_outs.size() == 2:
				var d_a: Vector2i = step_outs[0]
				var d_b: Vector2i = step_outs[1]
				if _dirs_perpendicular(d_a, d_b):
					corner_low_cells[Vector2i(x, z)] = [d_a, d_b]

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

	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			var vox := _tile_type_at(data, x, z)
			if vox == VoxelTypes.AIR or not planned.has(cell):
				continue
			var corner_dirs: Array = _pick_corner_dirs(data, x, z, planned)
			if corner_dirs.size() == 2:
				continue
			var d: Vector2i = planned[cell]
			var approach_cell := Vector2i(x + d.x, z + d.y)
			if corner_low_cells.has(approach_cell):
				continue
			data.set_ramp_cardinal(x, z, d)
			_clear_ramp_approach_block(data, x, z, d)
			_append_ramp_quad(out_quads, x, z, low_h, vox, {
				"dir": d,
				"dir2": Vector2i.ZERO,
			})

	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for z in range(rect.position.y, rect.position.y + rect.size.y):
			var cell := Vector2i(x, z)
			if concave_cells.has(cell) or _has_player_build_at(data, x, z):
				continue
			var low_h: float = _surface_y_at(data, x, z)
			if _tile_type_at(data, x, z) == VoxelTypes.AIR:
				continue
			var corner_dirs: Array = corner_low_cells.get(cell, _pick_corner_dirs(data, x, z, planned))
			if corner_dirs.size() != 2:
				continue
			if _skips_greedy_surface_cell(data, x, z) and not corner_low_cells.has(cell):
				continue
			var d_a: Vector2i = corner_dirs[0]
			var d_b: Vector2i = corner_dirs[1]
			var vox_corner: int = _tile_type_at(data, x, z)
			data.set_ramp_corner(x, z, d_a, d_b)
			_append_ramp_quad(out_quads, x, z, low_h, vox_corner, {
				"dir": d_a,
				"dir2": d_b,
			})


func _emit_dug_strata_region(
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
		if normal_dir.y > 0 and x1 - x0 == 1 and z1 - z0 == 1:
			_emit_single_surface_top_quad(data, out_quads, x0, z0)
			return
		# Job-local visit grid — never reuse manager-owned shared scratch across workers.
		var visited: Array = _ChunkPipeline.alloc_greedy_visited(ChunkData.SIZE)

		for x in range(x0, x1):
			for z in range(z0, z1):
				if visited[x][z] or _skips_greedy_surface_cell(data, x, z):
					continue
				var sy: float = _surface_y_at(data, x, z)
				if sy >= float(ChunkData.HEIGHT):
					continue
				var vox := _tile_type_at(data, x, z)
				if vox == VoxelTypes.AIR:
					continue

				var dx := 1
				while x + dx < x1 and not visited[x + dx][z] \
						and not _skips_greedy_surface_cell(data, x + dx, z) \
						and is_equal_approx(_surface_y_at(data, x + dx, z), sy) \
						and _tile_type_at(data, x + dx, z) == vox:
					dx += 1

				var dz := 1
				while z + dz < z1:
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

	_emit_surface_side_walls_region(data, normal_dir, face_code, out_quads, x0, z0, x1, z1)


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

	if abs(dx) == 1:
		for x in range(x0, x1):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for z in range(z0, z1 + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if z < z1 and not _skips_greedy_surface_cell(data, x, z):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(-dx, 0)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
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
		for z in range(z0, z1):
			var run_start = -1
			var run_h: float = 0.0
			var run_t = 0
			for x in range(x0, x1 + 1):
				var has_wall = false
				var curr_h: float = 0.0
				var curr_t = 0
				if x < x1 and not _skips_greedy_surface_cell(data, x, z):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x
					var nz = z + dz
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(0, -dz)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
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


## Remove the approach-column box so only the landing wedge renders (no z-fight).
func _clear_ramp_approach_block(data: ChunkData, landing_x: int, landing_z: int, toward_low: Vector2i) -> void:
	var ax: int = landing_x + toward_low.x
	var az: int = landing_z + toward_low.y
	if ax < 0 or ax >= ChunkData.SIZE or az < 0 or az >= ChunkData.SIZE:
		return
	if _tile_type_at(data, ax, az) == VoxelTypes.AIR:
		return
	if data.has_ramp(ax, az):
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
	# Permanent runtime gauges (profiler only — no gameplay change).
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
	# Report chunk queues to FrameBudgetScheduler (unit caps already enforced in drains).
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

	# Sort unload only when the list was mutated (not every idle frame).
	if _stream_unload_order_dirty and not _stream_unload_pending.is_empty():
		_sort_stream_unload_pending()
		_stream_unload_order_dirty = false
	while _stream_unload_pending.size() > 0 and unloads < max_stream_unloads_per_frame:
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
		var key: Vector2i = _stream_unload_pending.pop_front()
		if chunks.has(key):
			_unload_chunk_view(key)
		unloads += 1

	var inflight := _chunk_tasks.size() + _mesh_completion_queue.size()
	if ChunkView.pending_buffer_upload_count() > 4:
		_stream_budget_used_us = Time.get_ticks_usec() - t0
		return
	var can_start := (
		inflight < MAX_INFLIGHT_CHUNKS
		and not _stream_load_pending.is_empty()
		and Time.get_ticks_usec() - t0 < budget_us
	)
	if not can_start:
		_stream_budget_used_us = Time.get_ticks_usec() - t0
		return

	# Hot path: at most one (or few) starts → O(n) best-pick, no full sort.
	# Same priority_score ordering as sort_load_candidates (deterministic ties).
	var starts_cap: int = 1 if unloads > 0 else maxi(max_stream_starts_per_frame, 1)
	var player_chunk_once := _player_chunk_coord()
	while starts < starts_cap and inflight < MAX_INFLIGHT_CHUNKS:
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
		if _stream_load_pending.is_empty():
			break
		var best: Dictionary = _ChunkStreamScheduler.pick_best_load_candidate(_stream_load_pending)
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
			# While unloads drain, only start player-adjacent ring.
			var chebyshev := maxi(
				absi(coord.x - player_chunk_once.x),
				absi(coord.y - player_chunk_once.y)
			)
			if chebyshev > 1:
				# Best overall is far; scan for best with chebyshev<=1 without full sort.
				var near_best := _pick_best_near_load(player_chunk_once, 1)
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

	_stream_budget_used_us = Time.get_ticks_usec() - t0


## O(n) scan for highest-score pending load within chebyshev radius.
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
	# Sort once per drain pass when workers have appended (not on every push).
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
			if profiler and profiler.has_method("end"):
				profiler.end("chunk_upload")
			if token != null:
				token.spend_unit()
			else:
				break  # legacy single-step handled below
	if fbs and fbs.has_method("run_budgeted"):
		fbs.run_budgeted(&"chunk_apply", drain)
	else:
		# Legacy: hard count + wall budget.
		var count_budget := maxi(MAX_CHUNKS_PER_FRAME, 1)
		var time_budget_us := maxi(chunk_upload_budget_us, 500)
		var t0 := Time.get_ticks_usec()
		while _mesh_completion_queue.size() > 0 and count_budget > 0:
			if Time.get_ticks_usec() - t0 >= time_budget_us:
				break
			var item2: Dictionary = _mesh_completion_queue.pop_front()
			var c2: Vector2i = item2.get("coord", Vector2i.ZERO)
			var tok2: int = int(item2.get("token", -1))
			if profiler and profiler.has_method("begin"):
				profiler.begin("chunk_upload")
			_on_chunk_ready(item2["data"], item2["mesh"], tok2, Time.get_ticks_usec())
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
		ChunkView.drain_pending_surface_uploads(1, budget_us)
	var remaining_us := maxi(budget_us - (Time.get_ticks_usec() - t0), 500)
	if ChunkView.pending_buffer_upload_count() > 0:
		ChunkView.drain_pending_buffer_uploads(1, remaining_us)
	if profiler and profiler.has_method("end"):
		profiler.end("chunk_upload")


func set_stream_paused(paused: bool) -> void:
	stream_paused = paused


func is_stream_paused() -> bool:
	return stream_paused


func update_stream(cx: int, cz: int) -> void:
	if stream_paused or _shutting_down:
		return
	var player_chunk := Vector2i(cx, cz)
	_update_player_velocity_hint(player_chunk)
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
	if player and player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		return Vector2(v.x, v.z)
	var ws = _WorldSettings.get_active()
	return Vector2(
		ws.world_to_column(player.global_position.x),
		ws.world_to_column(player.global_position.z)
	)


func _sample_height(data: ChunkData, lx: int, lz: int) -> float:
	var halo_h: float = data.get_halo_surface_y(lx, lz)
	if halo_h > -9000.0:
		return halo_h
	if lx >= 0 and lx < ChunkData.SIZE and lz >= 0 and lz < ChunkData.SIZE:
		return _surface_y_at(data, lx, lz)
	# Worker path: rely on halo snapshot only (see capture_worker_snapshot).
	return 0.0


func _ramp_covers_drop(data: ChunkData, low_x: int, low_z: int, toward_high: Vector2i) -> bool:
	var hx: int = low_x + toward_high.x
	var hz: int = low_z + toward_high.y
	if hx < 0 or hx >= ChunkData.SIZE or hz < 0 or hz >= ChunkData.SIZE:
		return false
	if not data.has_ramp(hx, hz):
		return false
	var entry: Dictionary = data.get_ramp_entry(hx, hz)
	return entry.get("dir", Vector2i.ZERO) == Vector2i(-toward_high.x, -toward_high.y)


func _emit_surface_side_walls(data: ChunkData, normal_dir: Vector3i, face_code: int, out_quads: Array):
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
				if z < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x + dx
					var nz = z
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(-dx, 0)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
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
				if x < ChunkData.SIZE and not _skips_greedy_surface_cell(data, x, z):
					curr_h = _surface_y_at(data, x, z)
					curr_t = _tile_type_at(data, x, z)
					var nx = x
					var nz = z + dz
					var neighbor_h: float = _sample_height(data, nx, nz)
					var diff: float = curr_h - neighbor_h
					if diff > _cliff_height():
						has_wall = true
					elif diff > 0.1:
						var toward_high := Vector2i(0, -dz)
						has_wall = not _ramp_covers_drop(data, nx, nz, toward_high)
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
	# Hitch measurement: which chunks applied this frame (no gameplay effect).
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
	if profiler and profiler.has_method("end_func"):
		profiler.end_func("ChunkView::setup")
	if profiler and profiler.has_method("record_us"):
		profiler.record_us("chunk_view_setup", Time.get_ticks_usec() - setup_t1)
	var SPP = load("res://systems/stream_phase_profiler.gd")
	var upload_us_for_profile: int = int(ChunkView.peek_last_upload_us())
	if SPP and SPP.is_enabled():
		SPP.record("mesh_upload", upload_us_for_profile, data.position)
		# No per-chunk physics bodies — player uses voxel probe collision.
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
		# Profile-only GPU sync cost (does not run when stream phase profiler off).
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
	# Already marked in unload path; still guard against double release.
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
	# Defer sort to drain time (once per frame) instead of O(M log M) per worker push.
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
	if data == null or not data._has_worker_snapshot:
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token, {})
		return
	# Rebind world if cleared (e.g. prior job edge cases) before worker stages.
	if data.world == null and world != null:
		data.world = world
	if data.world == null:
		call_deferred("_on_chunk_task_complete", coord, null, {}, 0, 0, token, {})
		return
	if _ChunkRebuildTelemetry.is_enabled():
		_ChunkRebuildTelemetry.record_worker_start(coord, token)
	if _ChunkStreamingTelemetry.is_enabled():
		_ChunkStreamingTelemetry.transition(coord, token, _ChunkStreamingTelemetry.STATE_WORKER_ACTIVE)

	# Explicit pipeline stages (column → mesh → buffer); no manager shared scratch.
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

	# Always carry stage timings for permanent PerfProfiler (even when env telemetry is off).
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
	# Pool release (ChunkDataPool.release) still clears world when the shell is recycled.
	call_deferred(
		"_on_chunk_task_complete", coord, data, payload, mesh_us, buffer_us, token, worker_telemetry
	)


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
	# Deferred MQ entry. Leaf-attribute only.
	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("chunk_task_complete")
	if profiler and profiler.has_method("begin_func"):
		profiler.begin_func("ChunkManager::_on_chunk_task_complete")
	# Reap pool task id first (wait_for_task_completion). Must not only erase.
	_reap_chunk_task(coord)
	if _shutting_down or is_mesh_job_stale(coord, data, token):
		var stamp_stale := (
			data != null
			and token >= 0
			and int(_chunk_gen_tokens.get(coord, -1)) == token
			and data.has_method("is_overlay_mesh_stamp_current")
			and not data.is_overlay_mesh_stamp_current()
		)
		if data != null and _telemetry_trigger in ["stream", "movement"]:
			_ChunkDataPool.release(data)
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
		return {}
	var data: ChunkData = chunks[chunk_coord].chunk_data
	var lx := ix - chunk_coord.x * ChunkData.SIZE
	var lz := iz - chunk_coord.y * ChunkData.SIZE
	if data.has_ramp(lx, lz):
		return data.get_ramp_entry(lx, lz)
	return {}


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
		_merge_patch_pending(coord, local_cells, full)
	_schedule_rebuild_flush()


func rebuild_region_at_world(wx: float, wz: float, _ring: int = 1) -> void:
	invalidate_columns_at_world(int(wx), int(wz))


func _merge_patch_pending(coord: Vector2i, local_cells: Array, full: bool) -> void:
	if _patch_pending.has(coord):
		var entry: Dictionary = _patch_pending[coord]
		var bucket: Array = entry.get("local", [])
		for cell_variant in local_cells:
			var cell: Vector2i = cell_variant
			if cell not in bucket:
				bucket.append(cell)
		entry["local"] = bucket
		entry["full"] = bool(entry.get("full", false)) or full
		_patch_pending[coord] = entry
	else:
		_patch_pending[coord] = {
			"local": local_cells.duplicate(),
			"full": full,
		}


func _rebuild_high_priority(coord: Vector2i) -> bool:
	var player_chunk := get_player_chunk_coord()
	var dist: int = maxi(absi(coord.x - player_chunk.x), absi(coord.y - player_chunk.y))
	return dist <= 2


func flush_rebuild_pending() -> void:
	_flush_rebuild_pending()


## Coalesce rebuild flushes onto the next _process tick (not call_deferred self-requeue).
func _schedule_rebuild_flush() -> void:
	if not is_inside_tree() or _shutting_down:
		return
	_rebuild_flush_needed = true
	set_meta("_rebuild_flush_scheduled", true)


func _flush_rebuild_pending() -> void:
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
			# Busy workers merge into _patch_pending; next process frame will retry once.
			_enqueue_chunk_mesh_work(coord, full, local_cells, _rebuild_high_priority(coord), false)
	# One next-frame retry if work remains blocked on inflight jobs (not same-queue reentry).
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
