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
static func run_column_stage(
	host,
	data: ChunkData,
	full_rebuild: bool,
	dirty_local: Array
) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var examined := 0
	if data == null or not data.has_worker_overlay_snapshot():
		return {"examined": 0, "column_us": 0, "ok": false}
	if full_rebuild:
		if host != null and host.has_method("_generate_chunk"):
			host._generate_chunk(data)
		examined = ChunkData.SIZE * ChunkData.SIZE
	else:
		examined = data.update_dirty_column_maps(dirty_local)
	if data.has_method("_bind_macro_surface_if_needed"):
		data._bind_macro_surface_if_needed()
	var column_us := Time.get_ticks_usec() - t0
	return {
		"examined": examined,
		"column_us": column_us,
		"ok": true,
		"stage": STAGE_COLUMN,
	}


## Mesh stage: builds quads using host emit helpers; scratch is job-local on data.
static func run_mesh_stage(
	host,
	data: ChunkData,
	full_rebuild: bool,
	patch_rect: Rect2i
) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	if host == null or data == null:
		return {"quads": [], "count": 0, "mesh_us": 0, "ok": false}
	var result: Dictionary = (
		host._build_mesh(data)
		if full_rebuild
		else host._build_mesh_region(data, patch_rect, false)
	)
	var mesh_us := Time.get_ticks_usec() - t0
	return {
		"quads": result.get("quads", []),
		"count": int(result.get("count", 0)),
		"mesh_us": mesh_us,
		"ok": true,
		"stage": STAGE_MESH,
	}


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
	return {
		"payload": payload,
		"buffer_us": buffer_us,
		"duplicate_us": duplicate_us,
		"payload_duplicated": payload_duplicated,
		"buffer_allocated": buffer_allocated,
		"stage": STAGE_BUFFER,
		"ok": true,
		"total_us": Time.get_ticks_usec() - t0,
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
