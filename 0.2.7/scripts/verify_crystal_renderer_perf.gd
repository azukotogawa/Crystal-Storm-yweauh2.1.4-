extends SceneTree
## Compare legacy vs procedural using the plan's five metrics only.

const _ProbeExit = preload("res://scripts/probe_exit.gd")

const PLAN_METRICS: Array = [
	"draw_calls",
	"triangle_count",
	"gpu_memory_bytes",
	"crystal_mesh_time_ms",
	"frame_time_ms",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-d95151e877bc/implementer"

	var baseline_path := "%s/crystal_render_baseline.log" % scratch
	var after_path := "%s/crystal_render_after.log" % scratch
	var baseline := _parse_plan_metrics(baseline_path)
	var after := _parse_plan_metrics(after_path)

	if baseline.is_empty() or after.is_empty():
		push_error("missing benchmark logs baseline=%s after=%s" % [baseline_path, after_path])
		_ProbeExit.finish_tree(self, 1, "Crystal renderer perf tests FAILED")
		return

	var improved := 0
	var compare_lines: PackedStringArray = PackedStringArray()
	compare_lines.append("# Crystal render before/after (plan metrics)")
	compare_lines.append("")
	compare_lines.append(
		"Headless GPU counters read 0; draw_calls uses crystal MultiMesh node count, "
		+ "gpu_memory_bytes uses instance+vertex buffer estimate when VRAM counter is 0."
	)
	compare_lines.append("")
	compare_lines.append("| metric | before | after | delta | improved |")
	compare_lines.append("|--------|--------|-------|-------|----------|")

	for key in PLAN_METRICS:
		var b := float(baseline.get(key, 0.0))
		var a := float(after.get(key, 0.0))
		var better := a < b
		if better:
			improved += 1
		compare_lines.append(
			"| %s | %.2f | %.2f | %+.2f | %s |"
			% [key, b, a, a - b, "yes" if better else "no"]
		)

	var compare_path := "%s/crystal_render_compare.md" % scratch
	_write_text(compare_path, "\n".join(compare_lines))
	print("CRYSTAL_RENDER_COMPARE=%s" % compare_path)
	print("\n".join(compare_lines))

	if improved < 3:
		push_error(
			"expected >=3 of 5 plan metrics improved, got %d/5" % improved
		)
		_ProbeExit.finish_tree(self, 1, "Crystal renderer perf tests FAILED")
	else:
		print("OK %d/5 plan metrics improved" % improved)
		_ProbeExit.finish_tree(self, 0, "All crystal renderer perf tests OK")


func _parse_plan_metrics(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var out: Dictionary = {}
	var in_plan_section := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "## Plan metrics (5)":
			in_plan_section = true
			continue
		if in_plan_section and line.begins_with("## "):
			break
		if not in_plan_section:
			continue
		if line.begins_with("| ") and line.count("|") >= 3:
			var parts := line.split("|")
			if parts.size() >= 3:
				var key := parts[1].strip_edges()
				var val_str := parts[2].strip_edges()
				if key != "metric" and key != "--------" and val_str.is_valid_float():
					out[key] = float(val_str)
	f.close()
	return out


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()