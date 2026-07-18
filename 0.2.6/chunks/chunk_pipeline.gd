class_name ChunkPipeline
extends RefCounted
## Explicit chunk pipeline stages. Worker jobs are stateless w.r.t. manager fields:
## frozen overlay inputs live on ChunkData; mesh scratch is job-local on the data
## instance or stack locals — never ChunkManager-shared visit/skip buffers.
##
## Stages:
##   STREAM_REQUEST — main thread selects coords (ChunkManager + ChunkStreamScheduler)
##   SNAPSHOT       — main thread freezes WorldState mesh inputs on ChunkData
##   COLUMN         — worker: height/tile maps from frozen overlays (+ Terrain V2 micro)
##   MESH           — worker: pure mesh plan/build from frozen column maps + job-local scratch
##   BUFFER         — worker: optional MultiMesh payload packing
##   APPLY          — main thread: token + WorldState mesh-stamp stale rejection, upload

const STAGE_STREAM_REQUEST := "stream_request"
const STAGE_SNAPSHOT := "snapshot"
const STAGE_COLUMN := "column"
const STAGE_MESH := "mesh"
const STAGE_BUFFER := "buffer"
const STAGE_APPLY := "apply"

const STAGES := [
	STAGE_STREAM_REQUEST,
	STAGE_SNAPSHOT,
	STAGE_COLUMN,
	STAGE_MESH,
	STAGE_BUFFER,
	STAGE_APPLY,
]


## Column stage: requires capture_worker_snapshot already done on main thread.
## Prefers immutable baked base (WorldBakeService) on full rebuild when present;
## otherwise procedural generate via host._generate_chunk. WorldState overlays
## always come from the frozen worker snapshot on ChunkData.
static func run_column_stage(
	host,
	data: ChunkData,
	full_rebuild: bool,
	dirty_local: Array
) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var examined := 0
	var column_source := "none"
	if data == null or not data.has_worker_overlay_snapshot():
		return {"examined": 0, "column_us": 0, "ok": false, "column_source": column_source}
	if full_rebuild:
		var used_bake := false
		var bake = _world_bake_active()
		if bake != null and bake.has_method("try_apply_base_to_chunk_data"):
			used_bake = bool(bake.try_apply_base_to_chunk_data(data))
		if used_bake:
			column_source = "bake"
			examined = ChunkData.SIZE * ChunkData.SIZE
			# overlay apply timed inside WorldBakeService._apply_pack_to_data
		else:
			# Full-world bake: never procedural-generate static terrain in package bounds.
			var block := false
			if bake != null and bake.has_method("should_block_procedural_generate"):
				block = bool(bake.should_block_procedural_generate(data.position))
			if block:
				if bake.has_method("record_blocked_generate"):
					bake.record_blocked_generate()
				column_source = "blocked"
				examined = 0
			else:
				var gen_t0 := Time.get_ticks_usec()
				if host != null and host.has_method("_generate_chunk"):
					host._generate_chunk(data)
				var gen_us := Time.get_ticks_usec() - gen_t0
				if bake != null and bake.has_method("record_generate_column_us"):
					bake.record_generate_column_us(gen_us)
				column_source = "generate"
				examined = ChunkData.SIZE * ChunkData.SIZE
	else:
		examined = data.update_dirty_column_maps(dirty_local)
		column_source = "dirty"
	if data.has_method("_bind_macro_surface_if_needed"):
		data._bind_macro_surface_if_needed()
	var column_us := Time.get_ticks_usec() - t0
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled() and data != null:
		SPP.record("column_stage_total", column_us, data.position)
	return {
		"examined": examined,
		"column_us": column_us,
		"ok": true,
		"stage": STAGE_COLUMN,
		"column_source": column_source,
	}


static func _world_bake_active():
	var wb = load("res://world/world_bake_service.gd")
	if wb == null:
		return null
	if wb.has_method("get_active"):
		return wb.get_active()
	return null


## Mesh stage: builds quads using host emit helpers; scratch is job-local on data.
## Prefers MeshPlanCache on full rebuild when overlays are pristine (CPU plan only).
static func run_mesh_stage(
	host,
	data: ChunkData,
	full_rebuild: bool,
	patch_rect: Rect2i
) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	if host == null or data == null:
		return {"quads": [], "count": 0, "mesh_us": 0, "ok": false, "mesh_source": "none"}
	# mesh_source values kept for existing verifies: "cache" | "generate" | "none"
	var mesh_source := "generate"
	var rebuild_reason := "other"
	var quads: Array = []
	var count := 0
	var plan_lookup_us := 0
	var rebuild_us := 0
	var plan_decision: Dictionary = {}
	var SPP = load("res://systems/stream_phase_profiler.gd")
	var coord: Vector2i = data.position if data != null else Vector2i.ZERO
	if full_rebuild:
		var t_plan := Time.get_ticks_usec()
		var plan_cache = _mesh_plan_cache_active()
		if plan_cache != null and plan_cache.has_method("try_get_plan"):
			# try_get_plan records decision + hit/miss (instrumentation inside).
			var cached: Array = plan_cache.try_get_plan(data)
			plan_decision = plan_cache.last_decision if plan_cache.last_decision is Dictionary else {}
			if not cached.is_empty():
				quads = cached
				count = quads.size()
				mesh_source = "cache"
				rebuild_reason = "hit"
			else:
				rebuild_reason = str(plan_decision.get("rebuild_reason", "other"))
		plan_lookup_us = Time.get_ticks_usec() - t_plan
		if SPP and SPP.is_enabled():
			SPP.record("mesh_plan_lookup", plan_lookup_us, coord)
	else:
		rebuild_reason = "streaming_edge_case"
		plan_decision = {
			"rebuild_reason": "streaming_edge_case",
			"detail": "incremental_dirty_not_full_rebuild",
			"coord_x": coord.x,
			"coord_z": coord.y,
		}
	if mesh_source != "cache":
		var t_rebuild := Time.get_ticks_usec()
		var result: Dictionary = (
			host._build_mesh(data)
			if full_rebuild
			else host._build_mesh_region(data, patch_rect, false)
		)
		quads = result.get("quads", [])
		count = int(result.get("count", 0))
		mesh_source = "generate"
		rebuild_us = Time.get_ticks_usec() - t_rebuild
		if SPP and SPP.is_enabled():
			SPP.record("mesh_rebuild", rebuild_us, coord)
		var plan_cache2 = _mesh_plan_cache_active()
		if plan_cache2 != null and plan_cache2.has_method("record_rebuild_time"):
			plan_cache2.record_rebuild_time(rebuild_us)
		elif plan_cache2 != null and plan_cache2.has_method("record_miss_generate_us"):
			plan_cache2.record_miss_generate_us(rebuild_us)
	elif SPP and SPP.is_enabled():
		SPP.record("mesh_rebuild", 0, coord)
	var mesh_us := Time.get_ticks_usec() - t0
	var _MPP = load("res://systems/mesh_phase_profiler.gd")
	if _MPP and _MPP.is_enabled():
		_MPP.record("mesh_plan", mesh_us)
	# Explicit decision fields for telemetry consumers.
	return {
		"quads": quads,
		"count": count,
		"mesh_us": mesh_us,
		"ok": true,
		"stage": STAGE_MESH,
		"mesh_source": mesh_source,
		"rebuild_reason": rebuild_reason,
		"plan_decision": plan_decision,
		"plan_lookup_us": plan_lookup_us,
		"rebuild_us": rebuild_us,
	}


static func _mesh_plan_cache_active():
	var mp = load("res://world/mesh_plan_cache.gd")
	if mp == null:
		return null
	if mp.has_method("get_active"):
		return mp.get_active()
	return null


## Buffer stage: optional prebuilt MultiMesh payload (pure on inputs).
static func run_buffer_stage(
	data: ChunkData,
	merged_quads: Array,
	patch_quads: Array,
	keep_quads: Array,
	full_rebuild: bool,
	prebuild_chunk_buffers: bool,
	terrain_surface_mesh: bool,
	prior_surface_cache: Dictionary
) -> Dictionary:
	const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
	var t0 := Time.get_ticks_usec()
	var quads_payload := {
		"quads": merged_quads,
		"count": merged_quads.size(),
	}
	var t_dup := Time.get_ticks_usec()
	var payload: Dictionary = quads_payload.duplicate(true)
	var duplicate_us := Time.get_ticks_usec() - t_dup
	var payload_quads: Array = payload.get("quads", [])
	var payload_duplicated: bool = not is_same(payload_quads, merged_quads)
	var buffer_us := 0
	var buffer_allocated := false
	if prebuild_chunk_buffers:
		var t_buf := Time.get_ticks_usec()
		payload = _ChunkMeshBufferBuilder.build_mesh_payload(
			data,
			merged_quads,
			terrain_surface_mesh,
			prior_surface_cache,
			not full_rebuild,
			keep_quads,
			patch_quads
		)
		buffer_us = Time.get_ticks_usec() - t_buf
		buffer_allocated = payload.has("terrain_buffer")
	var total_us := Time.get_ticks_usec() - t0
	var _MPP = load("res://systems/mesh_phase_profiler.gd")
	if _MPP and _MPP.is_enabled():
		_MPP.record("buffer_pack", buffer_us)
		# Surface array packing (vertex/index CPU build) is inside buffer_pack for surface path.
		if bool(terrain_surface_mesh):
			_MPP.record("vertex_index_build", buffer_us)
	var SPP = load("res://systems/stream_phase_profiler.gd")
	if SPP and SPP.is_enabled() and data != null:
		SPP.record("buffer_pack", buffer_us, data.position)
	return {
		"payload": payload,
		"buffer_us": buffer_us,
		"duplicate_us": duplicate_us,
		"payload_duplicated": payload_duplicated,
		"buffer_allocated": buffer_allocated,
		"stage": STAGE_BUFFER,
		"ok": true,
		"total_us": total_us,
	}


## Full worker path: column → mesh → buffer. Host must not use shared manager scratch.
static func run_worker_job(
	host,
	data: ChunkData,
	full_rebuild: bool,
	dirty_local: Array,
	patch_rect: Rect2i,
	keep_quads: Array,
	prior_surface_cache: Dictionary,
	prebuild_chunk_buffers: bool,
	terrain_surface_mesh: bool
) -> Dictionary:
	var worker_t0 := Time.get_ticks_usec()
	var col: Dictionary = run_column_stage(host, data, full_rebuild, dirty_local)
	if not bool(col.get("ok", false)):
		return {
			"ok": false,
			"payload": {},
			"mesh_us": 0,
			"buffer_us": 0,
			"worker_telemetry": {},
			"examined": 0,
		}
	var mesh: Dictionary = run_mesh_stage(host, data, full_rebuild, patch_rect)
	var patch_quads: Array = mesh.get("quads", [])
	var merged_quads: Array = keep_quads.duplicate(true)
	merged_quads.append_array(patch_quads)
	var buf: Dictionary = run_buffer_stage(
		data,
		merged_quads,
		patch_quads,
		keep_quads,
		full_rebuild,
		prebuild_chunk_buffers,
		terrain_surface_mesh,
		prior_surface_cache
	)
	var column_us: int = int(col.get("column_us", 0))
	var build_mesh_us: int = int(mesh.get("mesh_us", 0))
	var mesh_us: int = column_us + build_mesh_us
	var examined: int = int(col.get("examined", 0))
	var worker_total: int = Time.get_ticks_usec() - worker_t0
	var tracked: int = column_us + build_mesh_us + int(buf.get("buffer_us", 0))
	var untracked: int = maxi(0, worker_total - tracked)
	var _MPP = load("res://systems/mesh_phase_profiler.gd")
	if _MPP and _MPP.is_enabled():
		_MPP.record("column", column_us)
		_MPP.record("worker_total", worker_total)
		_MPP.record("untracked", untracked)
	return {
		"ok": true,
		"payload": buf.get("payload", {}),
		"mesh_us": mesh_us,
		"buffer_us": int(buf.get("buffer_us", 0)),
		"examined": examined,
		"column_us": column_us,
		"build_mesh_us": build_mesh_us,
		"duplicate_us": int(buf.get("duplicate_us", 0)),
		"payload_duplicated": bool(buf.get("payload_duplicated", false)),
		"buffer_allocated": bool(buf.get("buffer_allocated", false)),
		"patch_quads": patch_quads,
		"merged_quads": merged_quads,
		"stages": [STAGE_COLUMN, STAGE_MESH, STAGE_BUFFER],
		"column_source": str(col.get("column_source", "")),
		"mesh_source": str(mesh.get("mesh_source", "")),
		"worker_total_us": worker_total,
	}


## Allocate a fresh greedy-visited grid for one plane pass (never reuse across jobs).
static func alloc_greedy_visited(size: int = -1) -> Array:
	if size < 0:
		size = ChunkData.SIZE
	var visited: Array = []
	visited.resize(size)
	for i in size:
		visited[i] = []
		visited[i].resize(size)
		for j in size:
			visited[i][j] = false
	return visited


static func reset_greedy_visited(visited: Array) -> void:
	if visited.is_empty():
		return
	for x in visited.size():
		var row: Array = visited[x]
		for z in row.size():
			row[z] = false
