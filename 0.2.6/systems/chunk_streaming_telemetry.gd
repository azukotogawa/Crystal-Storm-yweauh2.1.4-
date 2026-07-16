class_name ChunkStreamingTelemetry
extends RefCounted
## Env-gated chunk streaming lifecycle telemetry (CRYSTALSTORM_CHUNK_PROFILE=1). Investigation only.


const STATE_UNLOADED := "UNLOADED"
const STATE_REQUESTED := "REQUESTED"
const STATE_ALLOCATED := "ALLOCATED"
const STATE_WORKER_QUEUED := "WORKER_QUEUED"
const STATE_WORKER_ACTIVE := "WORKER_ACTIVE"
const STATE_HEIGHT_GENERATED := "HEIGHT_GENERATED"
const STATE_MESH_GENERATED := "MESH_GENERATED"
const STATE_QUEUED_FOR_UPLOAD := "QUEUED_FOR_UPLOAD"
const STATE_UPLOADING := "UPLOADING"
const STATE_UPLOADED := "UPLOADED"
const STATE_ACTIVE := "ACTIVE"
const STATE_UNLOADING := "UNLOADING"
const STATE_IDLE := "IDLE"

static var _enabled: bool = false
static var _checked_env: bool = false
static var _events: Array = []
static var _frame_samples: Array = []
static var _lifecycles: Dictionary = {}
static var _unload_events: Array = []
static var _scenario: String = ""
static var _sample_every_n_frames: int = 1
static var _frame_counter: int = 0


static func is_enabled() -> bool:
	if not _checked_env:
		_checked_env = true
		_enabled = OS.get_environment("CRYSTALSTORM_CHUNK_PROFILE") == "1"
	return _enabled


static func reset() -> void:
	_events.clear()
	_frame_samples.clear()
	_lifecycles.clear()
	_unload_events.clear()
	_budget_samples.clear()
	_scenario = ""
	_frame_counter = 0


static func set_scenario(name: String) -> void:
	_scenario = name


static func get_events() -> Array:
	return _events.duplicate(true)


static func get_frame_samples() -> Array:
	return _frame_samples.duplicate(true)


static func get_lifecycle_summaries() -> Array:
	var out: Array = []
	for key in _lifecycles.keys():
		out.append(_lifecycles[key].duplicate(true))
	return out


static func begin_lifecycle(
	coord: Vector2i,
	token: int,
	trigger: String,
	meta: Dictionary = {}
) -> void:
	if not is_enabled():
		return
	var key := _lifecycle_key(coord, token)
	var now_us := Time.get_ticks_usec()
	_lifecycles[key] = {
		"coord_x": coord.x,
		"coord_z": coord.y,
		"token": token,
		"trigger": trigger,
		"scenario": _scenario,
		"state": STATE_REQUESTED,
		"requested_us": now_us,
		"allocated_us": 0,
		"worker_queued_us": 0,
		"worker_active_us": 0,
		"height_generated_us": 0,
		"mesh_generated_us": 0,
		"upload_queued_us": 0,
		"uploading_us": 0,
		"uploaded_us": 0,
		"active_us": 0,
		"meta": meta.duplicate(),
		"alloc_path": str(meta.get("alloc_path", "")),
		"high_priority": bool(meta.get("high_priority", false)),
	}
	_append_event("lifecycle_begin", coord, token, {
		"trigger": trigger,
		"state": STATE_REQUESTED,
	})


static func transition(
	coord: Vector2i,
	token: int,
	state: String,
	meta: Dictionary = {}
) -> void:
	if not is_enabled():
		return
	var key := _lifecycle_key(coord, token)
	var lc: Dictionary = _lifecycles.get(key, {})
	if lc.is_empty():
		return
	var now_us := Time.get_ticks_usec()
	lc["state"] = state
	match state:
		STATE_ALLOCATED:
			lc["allocated_us"] = now_us
		STATE_WORKER_QUEUED:
			lc["worker_queued_us"] = now_us
		STATE_WORKER_ACTIVE:
			lc["worker_active_us"] = now_us
		STATE_HEIGHT_GENERATED:
			lc["height_generated_us"] = now_us
		STATE_MESH_GENERATED:
			lc["mesh_generated_us"] = now_us
		STATE_QUEUED_FOR_UPLOAD:
			lc["upload_queued_us"] = now_us
		STATE_UPLOADING:
			lc["uploading_us"] = now_us
		STATE_UPLOADED:
			lc["uploaded_us"] = now_us
		STATE_ACTIVE:
			lc["active_us"] = now_us
	for mk in meta.keys():
		var merged: Dictionary = lc.get("meta", {})
		merged[mk] = meta[mk]
		lc["meta"] = merged
	_lifecycles[key] = lc
	_append_event("state_%s" % state.to_lower(), coord, token, meta)


static func record_event(
	event_type: String,
	coord: Vector2i,
	token: int,
	meta: Dictionary = {}
) -> void:
	if not is_enabled():
		return
	_append_event(event_type, coord, token, meta)


static func record_unload(coord: Vector2i, phase: String, meta: Dictionary = {}) -> void:
	if not is_enabled():
		return
	var row: Dictionary = {
		"event": "unload_%s" % phase,
		"coord_x": coord.x,
		"coord_z": coord.y,
		"token": -1,
		"scenario": _scenario,
		"frame": Engine.get_process_frames(),
		"time_us": Time.get_ticks_usec(),
		"meta": meta.duplicate(),
	}
	_unload_events.append(row)
	_events.append(row)


static var _budget_samples: Array = []


static func record_budget_sample(budget_used_us: int, pool_stats: Dictionary = {}) -> void:
	if not is_enabled():
		return
	_budget_samples.append({
		"frame": Engine.get_process_frames(),
		"streaming_budget_used_us": budget_used_us,
		"pool_alloc_new": int(pool_stats.get("alloc_new", 0)),
		"pool_alloc_reuse": int(pool_stats.get("alloc_reuse", 0)),
		"pool_size": int(pool_stats.get("pool_size", 0)),
	})


static func get_budget_samples() -> Array:
	return _budget_samples.duplicate(true)


static func sample_frame(
	manager: Node,
	frame_us: int = 0,
	worker_us: int = 0,
	upload_us: int = 0
) -> void:
	if not is_enabled():
		return
	_frame_counter += 1
	if _sample_every_n_frames > 1 and (_frame_counter % _sample_every_n_frames) != 0:
		return
	var pending_n := 0
	var tasks_n := 0
	var mesh_q_n := 0
	var active_n := 0
	var inflight_n := 0
	if manager != null:
		if "pending" in manager:
			pending_n = (manager.pending as Dictionary).size()
		if "_chunk_tasks" in manager:
			tasks_n = (manager._chunk_tasks as Dictionary).size()
		if "_mesh_completion_queue" in manager:
			mesh_q_n = (manager._mesh_completion_queue as Array).size()
		if "chunks" in manager:
			active_n = (manager.chunks as Dictionary).size()
		inflight_n = tasks_n + mesh_q_n
	_frame_samples.append({
		"frame": Engine.get_process_frames(),
		"time_us": Time.get_ticks_usec(),
		"frame_us": frame_us,
		"worker_us": worker_us,
		"upload_us": upload_us,
		"pending_chunks": pending_n,
		"worker_tasks": tasks_n,
		"mesh_queue_depth": mesh_q_n,
		"active_chunks": active_n,
		"inflight_total": inflight_n,
		"worker_idle": tasks_n == 0 and mesh_q_n == 0 and pending_n == 0,
		"scenario": _scenario,
	})


static func sample_stream_pass(
	manager: Node,
	player_chunk: Vector2i,
	requested: int,
	unloaded: int,
	meta: Dictionary = {}
) -> void:
	if not is_enabled():
		return
	var pending_n := 0
	var tasks_n := 0
	var mesh_q_n := 0
	if manager != null:
		if "pending" in manager:
			pending_n = (manager.pending as Dictionary).size()
		if "_chunk_tasks" in manager:
			tasks_n = (manager._chunk_tasks as Dictionary).size()
		if "_mesh_completion_queue" in manager:
			mesh_q_n = (manager._mesh_completion_queue as Array).size()
	var stream_meta: Dictionary = {
		"player_chunk_x": player_chunk.x,
		"player_chunk_z": player_chunk.y,
		"chunks_requested": requested,
		"chunks_unloaded": unloaded,
		"pending_chunks": pending_n,
		"worker_tasks": tasks_n,
		"mesh_queue_depth": mesh_q_n,
		"inflight_total": tasks_n + mesh_q_n,
	}
	stream_meta.merge(meta)
	_append_event("stream_pass", player_chunk, -1, stream_meta)


static func finalize_lifecycle(coord: Vector2i, token: int) -> void:
	if not is_enabled():
		return
	var key := _lifecycle_key(coord, token)
	var lc: Dictionary = _lifecycles.get(key, {})
	if lc.is_empty():
		return
	var req_us: int = int(lc.get("requested_us", 0))
	var active_us: int = int(lc.get("active_us", 0))
	if req_us > 0 and active_us > req_us:
		lc["activation_latency_ms"] = float(active_us - req_us) / 1000.0
	lc["queue_wait_ms"] = _delta_ms(lc, "requested_us", "worker_active_us")
	lc["generation_latency_ms"] = _delta_ms(lc, "worker_active_us", "mesh_generated_us")
	lc["upload_latency_ms"] = _delta_ms(lc, "upload_queued_us", "uploaded_us")
	lc["upload_queue_wait_ms"] = _delta_ms(lc, "mesh_generated_us", "uploading_us")
	_lifecycles[key] = lc
	_append_event("lifecycle_complete", coord, token, {
		"activation_latency_ms": lc.get("activation_latency_ms", 0.0),
	})


static func write_jsonl(path: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChunkStreamingTelemetry: cannot write %s" % path)
		return
	for row in _events:
		f.store_line(JSON.stringify(row))
	for row in _frame_samples:
		var tagged: Dictionary = row.duplicate()
		tagged["record_kind"] = "frame_sample"
		f.store_line(JSON.stringify(tagged))
	for row in _lifecycles.values():
		var tagged_lc: Dictionary = row.duplicate(true)
		tagged_lc["record_kind"] = "lifecycle_summary"
		f.store_line(JSON.stringify(tagged_lc))
	for row in _unload_events:
		f.store_line(JSON.stringify(row))
	for row in _budget_samples:
		var tagged_budget: Dictionary = row.duplicate()
		tagged_budget["record_kind"] = "budget_sample"
		f.store_line(JSON.stringify(tagged_budget))
	f.close()


static func _append_event(
	event_type: String,
	coord: Vector2i,
	token: int,
	meta: Dictionary = {}
) -> void:
	_events.append({
		"event": event_type,
		"coord_x": coord.x,
		"coord_z": coord.y,
		"token": token,
		"scenario": _scenario,
		"frame": Engine.get_process_frames(),
		"time_us": Time.get_ticks_usec(),
		"meta": meta.duplicate(),
	})


static func _lifecycle_key(coord: Vector2i, token: int) -> String:
	return "%d,%d,%d" % [coord.x, coord.y, token]


static func _delta_ms(lc: Dictionary, start_key: String, end_key: String) -> float:
	var start_us: int = int(lc.get(start_key, 0))
	var end_us: int = int(lc.get(end_key, 0))
	if start_us <= 0 or end_us <= 0 or end_us < start_us:
		return 0.0
	return float(end_us - start_us) / 1000.0