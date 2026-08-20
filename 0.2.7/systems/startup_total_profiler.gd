class_name StartupTotalProfiler
extends RefCounted
## Temporary wall-clock startup diagnosis. Completely inert unless
## CRYSTALSTORM_STARTUP_TOTAL_PROFILE=1|true|on.
## Measurement only — no gameplay / bake / stream behavior.

const ENV_KEY := "CRYSTALSTORM_STARTUP_TOTAL_PROFILE"

static var _checked: bool = false
static var _enabled: bool = false
static var _t0_us: int = 0
static var _engine_ms_at_session: int = 0
static var _events: Array = []
static var _phases: Dictionary = {}
static var _open: Dictionary = {}
static var _order: Array = []
static var _gauges: Dictionary = {}
static var _bake_acc: Dictionary = {}
static var _snapshot_60s: Dictionary = {}
static var _snap60_done: bool = false
static var _playable_us: int = -1
static var _playable_reason: String = ""
static var _run_label: String = ""


static func is_enabled() -> bool:
	if _checked:
		return _enabled
	_checked = true
	var raw := OS.get_environment(ENV_KEY).strip_edges().to_lower()
	_enabled = raw == "1" or raw == "true" or raw == "on"
	return _enabled


static func begin_session(run_label: String = "") -> void:
	if not is_enabled():
		return
	_run_label = run_label if not run_label.is_empty() else OS.get_environment("CRYSTALSTORM_STARTUP_RUN")
	_t0_us = Time.get_ticks_usec()
	_engine_ms_at_session = Time.get_ticks_msec()
	_events.clear()
	_phases.clear()
	_open.clear()
	_order.clear()
	_gauges.clear()
	_bake_acc = {
		"column_us": 0,
		"mesh_plan_us": 0,
		"disk_write_us": 0,
		"yield_wait_us": 0,
		"chunks_done": 0,
		"chunks_total": 0,
		"vegetation_us": 0,
		"index_load_us": 0,
		"validate_us": 0,
		"save_index_us": 0,
		"mode": "",
	}
	_snapshot_60s.clear()
	_snap60_done = false
	_playable_us = -1
	_playable_reason = ""
	event("session_begin", {
		"run": _run_label,
		"engine_ms_already": _engine_ms_at_session,
		"processor_count": OS.get_processor_count(),
		"thread_name": OS.get_thread_caller_id(),
		"executable": OS.get_executable_path(),
		"userdata": OS.get_user_data_dir(),
	}, "process_start")


static func now_us() -> int:
	if _t0_us <= 0:
		return 0
	return Time.get_ticks_usec() - _t0_us


static func event(name: String, extra: Dictionary = {}, kind: String = "") -> void:
	if not is_enabled():
		return
	_maybe_snapshot_60s()
	var row := {
		"t_us": now_us(),
		"t_ms": float(now_us()) / 1000.0,
		"name": name,
		"kind": kind,
		"thread": "main",
	}
	if not extra.is_empty():
		row["extra"] = extra.duplicate(true)
	_events.append(row)
	print("[StartupTotal] +%8.1fms  %s  %s" % [float(now_us()) / 1000.0, name, kind])


static func begin(name: String, kind: String = "unknown", extra: Dictionary = {}) -> void:
	if not is_enabled():
		return
	_maybe_snapshot_60s()
	_open[name] = {
		"start_us": now_us(),
		"kind": kind,
		"extra": extra.duplicate(true),
	}
	if name not in _order:
		_order.append(name)
	event("begin:" + name, extra, kind)


static func end(name: String, extra: Dictionary = {}) -> int:
	if not is_enabled():
		return 0
	if not _open.has(name):
		return 0
	var start: Dictionary = _open[name]
	_open.erase(name)
	var dur: int = now_us() - int(start.get("start_us", 0))
	var merged: Dictionary = (start.get("extra", {}) as Dictionary).duplicate(true)
	for k in extra.keys():
		merged[k] = extra[k]
	var rec := {
		"name": name,
		"start_us": int(start.get("start_us", 0)),
		"end_us": now_us(),
		"duration_us": dur,
		"duration_ms": float(dur) / 1000.0,
		"kind": str(start.get("kind", "unknown")),
		"thread": "main",
		"extra": merged,
	}
	if _phases.has(name):
		var prev: Dictionary = _phases[name]
		prev["duration_us"] = int(prev.get("duration_us", 0)) + dur
		prev["duration_ms"] = float(prev.get("duration_us", 0)) / 1000.0
		prev["n"] = int(prev.get("n", 1)) + 1
		prev["end_us"] = rec.end_us
		_phases[name] = prev
	else:
		rec["n"] = 1
		_phases[name] = rec
	event("end:" + name, {"duration_ms": float(dur) / 1000.0}, str(start.get("kind", "")))
	return dur


static func add_us(bucket: String, us: int) -> void:
	if not is_enabled() or us < 0:
		return
	_bake_acc[bucket] = int(_bake_acc.get(bucket, 0)) + us


static func set_gauge(key: String, value: Variant) -> void:
	if not is_enabled():
		return
	_gauges[key] = value
	_bake_acc[key] = value


static func mark_playable(reason: String) -> void:
	if not is_enabled():
		return
	if _playable_us >= 0:
		return
	_playable_us = now_us()
	_playable_reason = reason
	event("PLAYABLE", {"reason": reason, "t_ms": float(_playable_us) / 1000.0}, "playable_gate")


static func note_bake_progress(done: int, total: int) -> void:
	if not is_enabled():
		return
	_bake_acc["chunks_done"] = done
	_bake_acc["chunks_total"] = total
	_maybe_snapshot_60s()
	if done == 1 or (total > 0 and done % maxi(total / 16, 256) == 0) or done >= total:
		event("bake_chunk_progress", {
			"done": done,
			"total": total,
			"column_ms": float(_bake_acc.get("column_us", 0)) / 1000.0,
			"mesh_plan_ms": float(_bake_acc.get("mesh_plan_us", 0)) / 1000.0,
			"disk_write_ms": float(_bake_acc.get("disk_write_us", 0)) / 1000.0,
			"yield_wait_ms": float(_bake_acc.get("yield_wait_us", 0)) / 1000.0,
		}, "world_generation")


static func _maybe_snapshot_60s() -> void:
	if _snap60_done or _t0_us <= 0:
		return
	if now_us() < 60_000_000:
		return
	_snap60_done = true
	var open_names: Array = _open.keys()
	_snapshot_60s = {
		"t_us": now_us(),
		"t_ms": float(now_us()) / 1000.0,
		"open_phases": open_names,
		"gauges": _gauges.duplicate(true),
		"bake_acc": _bake_acc.duplicate(true),
		"playable_yet": _playable_us >= 0,
		"events_so_far": _events.size(),
	}
	event("SNAPSHOT_60S", _snapshot_60s, "split")


static func report() -> Dictionary:
	_maybe_snapshot_60s()
	var wall: int = now_us()
	var first_60: int = mini(wall, 60_000_000)
	var after_60: int = maxi(wall - 60_000_000, 0)
	var ranked: Array = []
	for name in _order:
		if not _phases.has(name):
			continue
		ranked.append(_phases[name].duplicate(true))
	ranked.sort_custom(func(a, b): return int(a.get("duration_us", 0)) > int(b.get("duration_us", 0)))
	var top: Array = []
	for i in mini(ranked.size(), 16):
		var r: Dictionary = ranked[i]
		r["pct_wall"] = (float(r.get("duration_us", 0)) / float(maxi(wall, 1))) * 100.0
		top.append(r)
	return {
		"run": _run_label,
		"wall_us": wall,
		"wall_ms": float(wall) / 1000.0,
		"wall_s": float(wall) / 1_000_000.0,
		"engine_ms_before_session": _engine_ms_at_session,
		"first_60s_us": first_60,
		"after_60s_us": after_60,
		"playable_us": _playable_us,
		"playable_ms": float(_playable_us) / 1000.0 if _playable_us >= 0 else -1.0,
		"playable_reason": _playable_reason,
		"snapshot_60s": _snapshot_60s.duplicate(true),
		"phases": _phases.duplicate(true),
		"phase_order": _order.duplicate(),
		"ranked": top,
		"events": _events.duplicate(true),
		"gauges": _gauges.duplicate(true),
		"bake": _bake_acc.duplicate(true),
		"open_at_end": _open.keys(),
	}


static func write_report(path: String) -> bool:
	if not is_enabled():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("StartupTotalProfiler: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify(report(), "\t"))
	f.close()
	print("[StartupTotal] WROTE %s wall_s=%.2f playable_ms=%.1f" % [
		path,
		float(now_us()) / 1_000_000.0,
		float(_playable_us) / 1000.0 if _playable_us >= 0 else -1.0,
	])
	return true
