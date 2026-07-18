class_name StreamPhaseProfiler
extends RefCounted
## Fine-grained initial_chunk_stream / chunk-load phase timings.
## Enable: CRYSTALSTORM_STREAM_PHASE_PROFILE=1
## Auto-on while StartupProfiler session is active if CRYSTALSTORM_STARTUP_PROFILE=1
## (still records only when is_enabled()).

static var _enabled: bool = false
static var _checked: bool = false
static var _session: bool = false
static var _t0_us: int = 0
static var _window_open: bool = false
static var _window_t0: int = 0
static var _window_us: int = 0

## stage -> total us (sum across all samples)
static var _totals: Dictionary = {}
## stage -> PackedInt64Array of per-event us
static var _samples: Dictionary = {}
## order of first-seen stages
static var _order: Array = []
## per-chunk: Array of {coord_x, coord_z, stages: {name: us}, wall_us}
static var _chunks: Array = []
static var _chunk_open: Dictionary = {}  # "cx,cz" -> {stages, t0}


static func enabled_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_STREAM_PHASE_PROFILE").strip_edges().to_lower()
	if raw == "1" or raw == "true" or raw == "on":
		return true
	# Piggyback startup profile sessions.
	var sp := OS.get_environment("CRYSTALSTORM_STARTUP_PROFILE").strip_edges().to_lower()
	if sp == "1" or sp == "true" or sp == "on":
		return true
	return _session


static func is_enabled() -> bool:
	if not _checked:
		_checked = true
		_enabled = enabled_from_env()
	return _enabled or _session


static func begin_session() -> void:
	_session = true
	_enabled = true
	_checked = true
	reset()
	_t0_us = Time.get_ticks_usec()


static func end_session() -> void:
	_session = false
	_window_open = false


static func reset() -> void:
	_totals.clear()
	_samples.clear()
	_order.clear()
	_chunks.clear()
	_chunk_open.clear()
	_window_us = 0
	_window_open = false
	_window_t0 = 0
	_t0_us = Time.get_ticks_usec()


## Mark the composition_root initial_chunk_stream wall window.
static func begin_window(name: String = "initial_chunk_stream") -> void:
	if not is_enabled():
		return
	_window_open = true
	_window_t0 = Time.get_ticks_usec()
	record("window_open_marker", 0)


static func end_window(name: String = "initial_chunk_stream") -> int:
	if not is_enabled() or not _window_open:
		return 0
	_window_us = Time.get_ticks_usec() - _window_t0
	_window_open = false
	record("window_wall", _window_us)
	return _window_us


static func record(stage: String, us: int, coord: Vector2i = Vector2i(999999, 999999)) -> void:
	if not is_enabled() or us < 0:
		return
	if not _totals.has(stage):
		_totals[stage] = 0
		_samples[stage] = PackedInt64Array()
		_order.append(stage)
	_totals[stage] = int(_totals[stage]) + us
	var arr: PackedInt64Array = _samples[stage]
	arr.append(us)
	_samples[stage] = arr
	if coord.x != 999999:
		_note_chunk_stage(coord, stage, us)


static func begin_chunk(coord: Vector2i) -> void:
	if not is_enabled():
		return
	var key := "%d,%d" % [coord.x, coord.y]
	_chunk_open[key] = {
		"coord_x": coord.x,
		"coord_z": coord.y,
		"stages": {},
		"t0": Time.get_ticks_usec(),
	}


static func end_chunk(coord: Vector2i) -> void:
	if not is_enabled():
		return
	var key := "%d,%d" % [coord.x, coord.y]
	if not _chunk_open.has(key):
		return
	var rec: Dictionary = _chunk_open[key]
	rec["wall_us"] = Time.get_ticks_usec() - int(rec.get("t0", 0))
	_chunks.append(rec)
	_chunk_open.erase(key)


static func _note_chunk_stage(coord: Vector2i, stage: String, us: int) -> void:
	var key := "%d,%d" % [coord.x, coord.y]
	if not _chunk_open.has(key):
		begin_chunk(coord)
	var rec: Dictionary = _chunk_open[key]
	var stages: Dictionary = rec.get("stages", {})
	stages[stage] = int(stages.get(stage, 0)) + us
	rec["stages"] = stages
	_chunk_open[key] = rec


static func _stats(arr: PackedInt64Array) -> Dictionary:
	var n: int = arr.size()
	if n == 0:
		return {"n": 0, "avg_us": 0.0, "worst_us": 0, "total_us": 0}
	var total: int = 0
	var worst: int = 0
	for v in arr:
		var iv: int = int(v)
		total += iv
		if iv > worst:
			worst = iv
	return {
		"n": n,
		"avg_us": float(total) / float(n),
		"worst_us": worst,
		"total_us": total,
	}


static func report() -> Dictionary:
	var stages: Array = []
	var sum_work: int = 0
	for s in _order:
		if str(s).begins_with("window_"):
			continue
		var st: Dictionary = _stats(_samples.get(s, PackedInt64Array()))
		st["stage"] = s
		stages.append(st)
		sum_work += int(st.get("total_us", 0))
	var wall: int = _window_us if _window_us > 0 else (
		Time.get_ticks_usec() - _t0_us if _t0_us > 0 else sum_work
	)
	var denom: float = float(maxi(wall, 1))
	for st in stages:
		st["pct_window"] = (float(st.get("total_us", 0)) / denom) * 100.0
	# Sort by total descending for ranking
	stages.sort_custom(func(a, b): return int(a.get("total_us", 0)) > int(b.get("total_us", 0)))
	var dominant := ""
	var dominant_us := 0
	if stages.size() > 0:
		dominant = str(stages[0].get("stage", ""))
		dominant_us = int(stages[0].get("total_us", 0))
	var residual: int = maxi(0, wall - sum_work)
	return {
		"window_us": wall,
		"window_ms": float(wall) / 1000.0,
		"sum_measured_us": sum_work,
		"sum_measured_ms": float(sum_work) / 1000.0,
		"residual_unattributed_us": residual,
		"residual_unattributed_ms": float(residual) / 1000.0,
		"residual_pct": (float(residual) / denom) * 100.0,
		"stages": stages,
		"dominant_stage": dominant,
		"dominant_us": dominant_us,
		"dominant_pct": (float(dominant_us) / denom) * 100.0,
		"chunks": _chunks.duplicate(true),
		"chunk_count": _chunks.size(),
	}


static func to_json_string() -> String:
	return JSON.stringify(report(), "\t")


static func print_report() -> void:
	var r: Dictionary = report()
	print("STREAM_PHASE_PROFILE window_ms=%.2f measured_ms=%.2f residual_ms=%.2f (%.1f%%) dominant=%s (%.1f%%)" % [
		float(r.get("window_ms", 0.0)),
		float(r.get("sum_measured_ms", 0.0)),
		float(r.get("residual_unattributed_ms", 0.0)),
		float(r.get("residual_pct", 0.0)),
		str(r.get("dominant_stage", "")),
		float(r.get("dominant_pct", 0.0)),
	])
	print("stage\tn\tavg_us\tworst_us\ttotal_us\ttotal_ms\tpct_window")
	for st in r.get("stages", []):
		print("%s\t%d\t%.1f\t%d\t%d\t%.2f\t%.1f" % [
			str(st.get("stage", "")),
			int(st.get("n", 0)),
			float(st.get("avg_us", 0.0)),
			int(st.get("worst_us", 0)),
			int(st.get("total_us", 0)),
			float(st.get("total_us", 0)) / 1000.0,
			float(st.get("pct_window", 0.0)),
		])
	print("chunks_completed_in_window=%d" % int(r.get("chunk_count", 0)))
	for ch in r.get("chunks", []):
		print("  chunk (%d,%d) wall_us=%d stages=%s" % [
			int(ch.get("coord_x", 0)),
			int(ch.get("coord_z", 0)),
			int(ch.get("wall_us", 0)),
			str(ch.get("stages", {})),
		])
	print("STREAM_PHASE_PROFILE_OK")
