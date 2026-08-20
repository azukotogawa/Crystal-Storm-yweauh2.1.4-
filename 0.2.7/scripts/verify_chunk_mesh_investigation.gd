extends SceneTree
## Gating: chunk mesh investigation artifacts contain all eleven per-rebuild metrics.


const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")

const REQUIRED: Array[String] = [
	"voxels_examined",
	"quads_emitted",
	"ramps_emitted",
	"concave_pieces_emitted",
	"greedy_merge_ratio",
	"triangles_generated",
	"mesh_upload_time_ms",
	"worker_queue_wait_ms",
	"mesh_generation_time_ms",
	"serialization_time_ms",
	"main_thread_apply_time_ms",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		push_error("CRYSTALSTORM_SCRATCH not set")
		quit(1)
		return
	var telemetry_path := "%s/chunk_rebuild_telemetry.jsonl" % scratch
	var report_path := "%s/chunk_mesh_investigation_report.md" % scratch
	if not FileAccess.file_exists(telemetry_path):
		push_error("missing %s" % telemetry_path)
		quit(1)
		return
	if not FileAccess.file_exists(report_path):
		push_error("missing %s" % report_path)
		quit(1)
		return

	var lines := _read_lines(telemetry_path)
	if lines.is_empty():
		push_error("telemetry empty")
		quit(1)
		return

	for line in lines:
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("invalid jsonl row")
			quit(1)
			return
		for key in REQUIRED:
			if not parsed.has(key):
				push_error("row missing %s" % key)
				quit(1)
				return

	var report := FileAccess.get_file_as_string(report_path)
	for heading in [
		"Are entire chunks rebuilt",
		"How many chunks rebuild from one dig",
		"How many chunks rebuild from one crystal",
		"Are neighboring chunks rebuilding",
		"Are uploads happening every frame",
		"Is mesh data recreated",
		"Are arrays constantly allocated",
		"Top 10 optimization opportunities",
	]:
		if heading not in report:
			push_error("report missing section: %s" % heading)
			quit(1)
			return

	var opp_count := report.split("optimization opportunities", true, 1)[1].count("\n1. **")
	if opp_count < 1:
		push_error("report missing ranked opportunities")
		quit(1)
		return

	print("OK chunk mesh investigation artifacts valid (%d rows)" % lines.size())
	quit(0)


static func _read_lines(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if not line.is_empty():
			out.append(line)
	f.close()
	return out