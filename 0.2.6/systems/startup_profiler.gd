class_name StartupProfiler
extends RefCounted
## Fine-grained startup stage timing (mirrors runtime phase profiling style).
## Enable with CRYSTALSTORM_STARTUP_PROFILE=1 or begin_session().

static var _enabled: bool = false
static var _session: bool = false
static var _t0_us: int = 0
static var _open: Dictionary = {}  # stage -> start_us
static var _samples: Dictionary = {}  # stage -> PackedInt64Array of durations us
static var _order: Array = []  # first-seen stage names for report order


static func enabled_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_STARTUP_PROFILE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on" or _session


static func begin_session() -> void:
	_session = true
	_enabled = true
	_samples.clear()
	_open.clear()
	_order.clear()
	_t0_us = Time.get_ticks_usec()


static func end_session() -> void:
	_session = false
	_enabled = false
	_open.clear()


static func is_enabled() -> bool:
	return _enabled or enabled_from_env()


static func begin(stage: String) -> void:
	if not is_enabled():
		return
	_open[stage] = Time.get_ticks_usec()
	if stage not in _order:
		_order.append(stage)


static func end(stage: String) -> int:
	if not is_enabled():
		return 0
	if not _open.has(stage):
		return 0
	var us: int = Time.get_ticks_usec() - int(_open[stage])
	_open.erase(stage)
	if not _samples.has(stage):
		_samples[stage] = PackedInt64Array()
	var arr: PackedInt64Array = _samples[stage]
	arr.append(us)
	_samples[stage] = arr
	if stage not in _order:
		_order.append(stage)
	return us


static func mark(stage: String, us: int) -> void:
	if not is_enabled() or us < 0:
		return
	if not _samples.has(stage):
		_samples[stage] = PackedInt64Array()
	var arr: PackedInt64Array = _samples[stage]
	arr.append(us)
	_samples[stage] = arr
	if stage not in _order:
		_order.append(stage)


static func total_us() -> int:
	if _t0_us <= 0:
		return 0
	return Time.get_ticks_usec() - _t0_us


static func _stats(arr: PackedInt64Array) -> Dictionary:
	var n: int = arr.size()
	if n == 0:
		return {"n": 0, "avg_us": 0.0, "p95_us": 0.0, "worst_us": 0, "total_us": 0}
	var total: int = 0
	var worst: int = 0
	var sorted: Array = []
	for v in arr:
		var iv: int = int(v)
		total += iv
		if iv > worst:
			worst = iv
		sorted.append(iv)
	sorted.sort()
	# Nearest-rank p95 (inclusive).
	var p95_i: int = clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)
	var p95_us: float = float(sorted[p95_i])
	return {
		"n": n,
		"avg_us": float(total) / float(n),
		"p95_us": p95_us,
		"worst_us": worst,
		"total_us": total,
	}


static func report() -> Dictionary:
	var stages: Array = []
	var sum_totals: int = 0
	for s in _order:
		var st: Dictionary = _stats(_samples.get(s, PackedInt64Array()))
		st["stage"] = s
		stages.append(st)
		sum_totals += int(st.get("total_us", 0))
	var wall: int = total_us()
	# Prefer wall clock for % if available; else sum of stages.
	var denom: float = float(wall) if wall > 0 else float(maxi(sum_totals, 1))
	for st in stages:
		var tot: float = float(st.get("total_us", 0))
		st["pct_total"] = (tot / denom) * 100.0
	# Dominant by total contribution (first sample set / avg for single-shot stages).
	var dominant := ""
	var dominant_us := -1.0
	for st in stages:
		var a: float = float(st.get("avg_us", 0.0))
		if a > dominant_us and int(st.get("n", 0)) > 0:
			dominant_us = a
			dominant = str(st.get("stage", ""))
	return {
		"wall_us": wall,
		"wall_ms": float(wall) / 1000.0,
		"stages": stages,
		"dominant_stage": dominant,
		"dominant_avg_us": dominant_us,
		"sum_stage_us": sum_totals,
	}


static func to_json_string() -> String:
	return JSON.stringify(report(), "\t")


static func print_report() -> void:
	var r: Dictionary = report()
	print("STARTUP_PROFILE wall_ms=%.2f dominant=%s avg_us=%.1f" % [
		float(r.get("wall_ms", 0.0)),
		str(r.get("dominant_stage", "")),
		float(r.get("dominant_avg_us", 0.0)),
	])
	print("stage\tn\tavg_us\tp95_us\tworst_us\ttotal_us\tpct")
	for st in r.get("stages", []):
		print(
			"%s\t%d\t%.1f\t%.1f\t%d\t%d\t%.1f"
			% [
				str(st.get("stage", "")),
				int(st.get("n", 0)),
				float(st.get("avg_us", 0.0)),
				float(st.get("p95_us", 0.0)),
				int(st.get("worst_us", 0)),
				int(st.get("total_us", 0)),
				float(st.get("pct_total", 0.0)),
			]
		)
	print("STARTUP_PROFILE_OK")


## Report only stages whose names start with prefix; pct is of that group wall (sum of stage avgs or of parent_us).
static func report_prefix(prefix: String, parent_us: float = -1.0) -> Dictionary:
	var stages: Array = []
	var sum_avg: float = 0.0
	var sum_total: int = 0
	for s in _order:
		if not str(s).begins_with(prefix):
			continue
		var st: Dictionary = _stats(_samples.get(s, PackedInt64Array()))
		st["stage"] = s
		stages.append(st)
		sum_avg += float(st.get("avg_us", 0.0))
		sum_total += int(st.get("total_us", 0))
	var denom: float = parent_us if parent_us > 0.0 else maxf(sum_avg, 1.0)
	for st in stages:
		st["pct_parent"] = (float(st.get("avg_us", 0.0)) / denom) * 100.0
	return {
		"prefix": prefix,
		"parent_us": parent_us,
		"sum_avg_us": sum_avg,
		"sum_total_us": sum_total,
		"stages": stages,
	}
