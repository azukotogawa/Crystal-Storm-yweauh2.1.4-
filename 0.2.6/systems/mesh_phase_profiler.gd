class_name MeshPhaseProfiler
extends RefCounted
## Lightweight multi-sample phase timing for chunk mesh/apply path.
## Enable with CRYSTALSTORM_MESH_PHASE_PROFILE=1 or begin_session().

const PHASES := [
	"column",
	"mesh_plan",
	"buffer_pack",
	"mesh_object_create",
	"vertex_index_build",
	"multimesh_populate",
	"gpu_upload",
	"scenetree_insert",
	"material_assign",
	"apply_clear_children",
	"apply_total",
	"worker_total",
	"untracked",
]

static var _enabled: bool = false
static var _samples: Dictionary = {}  # phase -> PackedInt64Array of us
static var _session_active: bool = false


static func enabled_from_env() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_MESH_PHASE_PROFILE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on" or _session_active


static func begin_session() -> void:
	_session_active = true
	_enabled = true
	_samples.clear()
	for p in PHASES:
		_samples[p] = PackedInt64Array()


static func end_session() -> void:
	_session_active = false
	_enabled = false


static func is_enabled() -> bool:
	return _enabled or enabled_from_env()


static func record(phase: String, us: int) -> void:
	if not is_enabled():
		return
	if us < 0:
		us = 0
	if not _samples.has(phase):
		_samples[phase] = PackedInt64Array()
	var arr: PackedInt64Array = _samples[phase]
	arr.append(us)
	_samples[phase] = arr


static func sample_count(phase: String = "mesh_plan") -> int:
	if not _samples.has(phase):
		return 0
	return (_samples[phase] as PackedInt64Array).size()


static func _sorted_copy(arr: PackedInt64Array) -> PackedInt64Array:
	var tmp: Array = []
	for v in arr:
		tmp.append(int(v))
	tmp.sort()
	var out := PackedInt64Array()
	out.resize(tmp.size())
	for i in tmp.size():
		out[i] = int(tmp[i])
	return out


static func stats_for(phase: String) -> Dictionary:
	if not _samples.has(phase):
		return {"phase": phase, "n": 0, "avg_us": 0.0, "p95_us": 0, "worst_us": 0, "total_us": 0}
	var arr: PackedInt64Array = _samples[phase]
	var n: int = arr.size()
	if n == 0:
		return {"phase": phase, "n": 0, "avg_us": 0.0, "p95_us": 0, "worst_us": 0, "total_us": 0}
	var total: int = 0
	var worst: int = 0
	for v in arr:
		var iv: int = int(v)
		total += iv
		if iv > worst:
			worst = iv
	var sorted := _sorted_copy(arr)
	var p95_idx: int = mini(n - 1, int(floor(float(n - 1) * 0.95)))
	return {
		"phase": phase,
		"n": n,
		"avg_us": float(total) / float(n),
		"p95_us": int(sorted[p95_idx]),
		"worst_us": worst,
		"total_us": total,
	}


static func report() -> Dictionary:
	var phases: Array = []
	var dominant := ""
	var dominant_avg := -1.0
	for p in PHASES:
		var s: Dictionary = stats_for(p)
		phases.append(s)
		# Decision uses worker-side mesh construction phases + apply-side upload/create.
		if p in ["mesh_plan", "buffer_pack", "vertex_index_build", "gpu_upload",
				"mesh_object_create", "scenetree_insert", "material_assign", "multimesh_populate"]:
			var a: float = float(s.get("avg_us", 0.0))
			if a > dominant_avg and int(s.get("n", 0)) > 0:
				dominant_avg = a
				dominant = p
	return {
		"phases": phases,
		"dominant_phase": dominant,
		"dominant_avg_us": dominant_avg,
		"sample_chunks": sample_count("worker_total"),
	}


static func to_json_string() -> String:
	return JSON.stringify(report(), "\t")
