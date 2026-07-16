class_name ChunkRebuildTelemetry
extends RefCounted
## Env-gated per-rebuild telemetry (CRYSTALSTORM_CHUNK_PROFILE=1). Investigation only.


const FACE_TOP := 0
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8
const FACE_RAMP_SIDE := 9

const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")

static var _enabled: bool = false
static var _checked_env: bool = false
static var _records: Array = []
static var _pending: Dictionary = {}
static var _staged_worker: Dictionary = {}
static var _scenario: String = ""
static var _trigger_hint: String = ""
static var _meta_hint: Dictionary = {}


static func is_enabled() -> bool:
	if not _checked_env:
		_checked_env = true
		_enabled = OS.get_environment("CRYSTALSTORM_CHUNK_PROFILE") == "1"
	return _enabled


static func reset() -> void:
	_records.clear()
	_pending.clear()
	_staged_worker.clear()
	_scenario = ""
	_trigger_hint = ""
	_meta_hint = {}


static func set_scenario(name: String) -> void:
	_scenario = name


static func set_trigger_hint(trigger: String, meta: Dictionary = {}) -> void:
	_trigger_hint = trigger
	_meta_hint = meta.duplicate()


static func get_records() -> Array:
	return _records.duplicate(true)


static func record_enqueue(coord: Vector2i, token: int, trigger: String, meta: Dictionary = {}) -> void:
	if not is_enabled():
		return
	var key := _pending_key(coord, token)
	_pending[key] = {
		"coord": coord,
		"token": token,
		"trigger": trigger if not trigger.is_empty() else _trigger_hint,
		"scenario": _scenario,
		"meta": meta.duplicate(),
		"enqueue_us": Time.get_ticks_usec(),
		"is_regen": meta.get("is_regen", false),
		"voxels_changed_hint": int(meta.get("voxels_changed_hint", 0)),
	}


static func record_worker_start(coord: Vector2i, token: int) -> void:
	if not is_enabled():
		return
	var key := _pending_key(coord, token)
	if not _pending.has(key):
		return
	_pending[key]["worker_start_us"] = Time.get_ticks_usec()


static func stage_worker_metrics(coord: Vector2i, token: int, worker: Dictionary) -> void:
	if not is_enabled():
		return
	_staged_worker[_pending_key(coord, token)] = worker.duplicate(true)


static func finalize_record(
	coord: Vector2i,
	token: int,
	worker: Dictionary,
	apply: Dictionary = {}
) -> void:
	if not is_enabled():
		return
	var key := _pending_key(coord, token)
	var staged: Dictionary = _staged_worker.get(key, {})
	if not staged.is_empty():
		_staged_worker.erase(key)
	var worker_merged: Dictionary = staged if not staged.is_empty() else worker
	var base: Dictionary = _pending.get(key, {
		"coord": coord,
		"token": token,
		"trigger": _trigger_hint,
		"scenario": _scenario,
		"meta": {},
		"enqueue_us": 0,
	})
	_pending.erase(key)

	var enqueue_us: int = int(base.get("enqueue_us", 0))
	var worker_start_us: int = int(base.get("worker_start_us", enqueue_us))
	var queue_wait_ms := 0.0
	if worker_start_us > enqueue_us:
		queue_wait_ms = float(worker_start_us - enqueue_us) / 1000.0

	var meta: Dictionary = base.get("meta", {})
	var row: Dictionary = {
		"scenario": str(base.get("scenario", "")),
		"trigger": str(base.get("trigger", "")),
		"coord_x": coord.x,
		"coord_z": coord.y,
		"token": token,
		"is_regen": bool(base.get("is_regen", false)),
		"voxels_changed_hint": int(base.get("voxels_changed_hint", 0)),
		"voxels_examined": int(worker_merged.get("voxels_examined", 0)),
		"quads_emitted": int(worker_merged.get("quads_emitted", 0)),
		"ramps_emitted": int(worker_merged.get("ramps_emitted", 0)),
		"concave_pieces_emitted": int(worker_merged.get("concave_pieces_emitted", 0)),
		"greedy_merge_ratio": float(worker_merged.get("greedy_merge_ratio", 0.0)),
		"triangles_generated": int(worker_merged.get("triangles_generated", 0)),
		"mesh_generation_time_ms": float(worker_merged.get("mesh_generation_time_ms", 0.0)),
		"serialization_time_ms": float(worker_merged.get("serialization_time_ms", 0.0)),
		"worker_queue_wait_ms": queue_wait_ms,
		"mesh_upload_time_ms": float(apply.get("mesh_upload_time_ms", 0.0)),
		"main_thread_apply_time_ms": float(apply.get("main_thread_apply_time_ms", 0.0)),
		"payload_duplicated": bool(worker_merged.get("payload_duplicated", false)),
		"buffer_allocated": bool(worker_merged.get("buffer_allocated", false)),
		"mesh_nodes_recreated": bool(apply.get("mesh_nodes_recreated", false)),
		"chunk_data_alloc_path": str(base.get("meta", {}).get("chunk_data_alloc_path", "")),
		"prebuilt_buffers": bool(worker_merged.get("prebuilt_buffers", false)),
		"column_map_time_ms": float(worker_merged.get("column_map_time_ms", 0.0)),
		"build_mesh_time_ms": float(worker_merged.get("build_mesh_time_ms", 0.0)),
		"incremental": bool(worker_merged.get("incremental", meta.get("incremental", false))),
		"dirty_columns": int(meta.get("dirty_columns", worker_merged.get("dirty_columns", 0))),
		"rebuilt_columns": int(worker_merged.get("rebuilt_columns", meta.get("rebuilt_columns", 0))),
		"rebuilt_chunks": int(meta.get("rebuilt_chunks", 0)),
		"skipped_chunks": int(meta.get("skipped_chunks", worker_merged.get("skipped_chunks", 0))),
		"mesh_patch_size": int(meta.get("mesh_patch_size", worker_merged.get("mesh_patch_size", 0))),
		"frame": Engine.get_process_frames(),
	}
	for mk in meta.keys():
		row["meta_%s" % str(mk)] = meta[mk]
	_records.append(row)


static func collect_geometry_stats(
	data: ChunkData,
	quads: Array,
	payload: Dictionary,
	voxels_examined: int = -1
) -> Dictionary:
	var solid_surface := 0
	var top_quads := 0
	for x in ChunkData.SIZE:
		for z in ChunkData.SIZE:
			if data.get_tile_type(x, z) == VoxelTypes.AIR:
				continue
			if data.has_ramp(x, z):
				continue
			solid_surface += 1

	var ramps := 0
	var concave := 0
	for q in quads:
		var fc: int = int(q.get("face_code", -1))
		if fc == FACE_RAMP:
			ramps += 1
		elif fc == FACE_RAMP_CORNER:
			ramps += 1
		elif fc == FACE_RAMP_SIDE:
			concave += 1
		elif fc == FACE_TOP and int(q.get("geometry_kind", -1)) == _VoxelGeometryKind.Kind.DIAGONAL_RAMP:
			concave += 1
		if fc == FACE_TOP:
			top_quads += 1

	var ratio := 0.0
	if top_quads > 0:
		ratio = float(solid_surface) / float(top_quads)

	var examined := voxels_examined if voxels_examined >= 0 else ChunkData.SIZE * ChunkData.SIZE
	return {
		"voxels_examined": examined,
		"solid_surface_cells": solid_surface,
		"quads_emitted": quads.size(),
		"ramps_emitted": ramps,
		"concave_pieces_emitted": concave,
		"greedy_merge_ratio": ratio,
		"triangles_generated": _count_triangles_from_payload(payload),
	}


static func write_jsonl(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChunkRebuildTelemetry: cannot write %s" % path)
		return
	for row in _records:
		f.store_line(JSON.stringify(row))
	f.close()


static func _pending_key(coord: Vector2i, token: int) -> String:
	return "%d,%d,%d" % [coord.x, coord.y, token]


static func _count_triangles_from_payload(payload: Dictionary) -> int:
	var total := 0
	total += int(payload.get("terrain_count", 0)) * 12
	total += int(payload.get("ramp_count", 0)) * 4
	total += int(payload.get("corner_count", 0)) * 4
	total += int(payload.get("diagonal_count", 0)) * 6
	return total


static func _triangles_per_kind(kind: StringName) -> int:
	if kind == _VoxelGeometryKind.MESH_FULL_CUBE:
		return 12
	if kind == _VoxelGeometryKind.MESH_HALF_CUBE:
		return 6
	if str(kind).begins_with("ramp_"):
		return 4
	if str(kind).begins_with("corner_"):
		return 4
	if str(kind).begins_with("concave_"):
		return 6
	return 12