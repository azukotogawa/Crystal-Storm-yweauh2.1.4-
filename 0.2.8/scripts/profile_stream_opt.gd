extends SceneTree
## Stream optimization baseline / after probe.
## Writes {SCRATCH}/stream_opt_{TAG}.json (+ .md) with schedule/apply/queue metrics.
## Usage:
##   CRYSTALSTORM_SCRATCH=... CRYSTALSTORM_STREAM_OPT_TAG=baseline \
##     godot --headless -s scripts/profile_stream_opt.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	# Stream probe uses a small radius bake (not production 128²) so boot stays
	# sub-minute and comparisons stay stable. Production bake path is unchanged.
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-34386f538cf1/implementer")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	DirAccess.make_dir_recursive_absolute(scratch)
	var tag := OS.get_environment("CRYSTALSTORM_STREAM_OPT_TAG").strip_edges()
	if tag.is_empty():
		tag = "run"
	var session_sec: float = float(OS.get_environment("CRYSTALSTORM_STREAM_OPT_SEC"))
	if session_sec <= 0.0:
		session_sec = 25.0

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "STREAM_OPT_FAIL_no_main")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var w := 0
	while compose and not bool(compose.get("_boot_done")) and w < 3600:
		await process_frame
		w += 1
	for _i in 20:
		await process_frame

	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var player: Node = get_first_node_in_group("player")
	var cm = get_first_node_in_group("chunk_manager")
	if profiler == null or player == null or cm == null:
		_ProbeExit.finish_tree(self, 1, "STREAM_OPT_FAIL_boot")
		return
	profiler.enabled = true

	var bake = load("res://world/world_bake_service.gd").get_active()
	var min_cx := -2
	var max_cx := 2
	var min_cz := -2
	var max_cz := 2
	if bake != null and bake.valid:
		min_cx = int(bake.min_cx)
		max_cx = int(bake.max_cx)
		min_cz = int(bake.min_cz)
		max_cz = int(bake.max_cz)
	# Bound walk to a local ring for headless speed while still streaming.
	min_cx = maxi(min_cx, -3)
	max_cx = mini(max_cx, 3)
	min_cz = maxi(min_cz, -3)
	max_cz = mini(max_cz, 3)

	var path: Array = []
	for cz in range(min_cz, max_cz + 1):
		var xs: Array = range(min_cx, max_cx + 1)
		if (cz - min_cz) % 2 == 1:
			xs.reverse()
		for cx in xs:
			path.append(Vector2i(cx, cz))
	var base: Array = path.duplicate()
	while path.size() < 200:
		path.append_array(base)

	var schedule_samples: PackedFloat32Array = PackedFloat32Array()
	var upload_samples: PackedFloat32Array = PackedFloat32Array()
	var apply_samples: PackedFloat32Array = PackedFloat32Array()  # chunk_apply exclusive
	var cm_func_samples: PackedFloat32Array = PackedFloat32Array()
	var load_pending_max := 0
	var mesh_q_max := 0
	var inflight_max := 0
	var chunks_vis_max := 0
	var frame_n := 0
	var path_i := 0
	var last_move := Time.get_ticks_msec()
	var t0 := Time.get_ticks_msec()
	var apply_count_sum := 0  # chunks_streamed_applied frame counter sum

	print("STREAM_OPT begin tag=%s sec=%.0f" % [tag, session_sec])
	while Time.get_ticks_msec() - t0 < int(session_sec * 1000.0):
		if Time.get_ticks_msec() - last_move >= 280 and path_i < path.size():
			var tgt: Vector2i = path[path_i]
			path_i += 1
			last_move = Time.get_ticks_msec()
			if player:
				player.global_position = Vector3(
					float(tgt.x * 16) + 8.0, player.global_position.y, float(tgt.y * 16) + 8.0
				)
			if cm.has_method("update_stream"):
				cm.update_stream(tgt.x, tgt.y)
		await process_frame
		frame_n += 1
		if not profiler.has_method("get_snapshot"):
			continue
		var snap: Dictionary = profiler.get_snapshot()
		var secs: Dictionary = snap.get("sections", {})
		var funcs: Dictionary = snap.get("funcs", {})
		schedule_samples.append(float(secs.get("stream_schedule", {}).get("last_ms", 0.0)))
		upload_samples.append(float(secs.get("chunk_upload", {}).get("last_ms", 0.0)))
		apply_samples.append(float(secs.get("chunk_apply", {}).get("last_ms", 0.0)))
		# Prefer exclusive section if present
		var sch_ex: float = float(secs.get("stream_schedule", {}).get("exclusive_ms", -1.0))
		if sch_ex >= 0.0:
			schedule_samples[schedule_samples.size() - 1] = sch_ex
		var up_ex: float = float(secs.get("chunk_upload", {}).get("exclusive_ms", -1.0))
		if up_ex >= 0.0:
			upload_samples[upload_samples.size() - 1] = up_ex
		var ap_ex: float = float(secs.get("chunk_apply", {}).get("exclusive_ms", -1.0))
		if ap_ex >= 0.0:
			apply_samples[apply_samples.size() - 1] = ap_ex
		cm_func_samples.append(float(funcs.get("ChunkManager::_process", {}).get("last_ms", 0.0)))
		var gauges: Dictionary = snap.get("gauges", {})
		load_pending_max = maxi(load_pending_max, int(gauges.get("stream_queue_depth", 0.0)))
		mesh_q_max = maxi(mesh_q_max, int(gauges.get("mesh_queue_depth", 0.0)))
		inflight_max = maxi(inflight_max, int(gauges.get("chunk_tasks_inflight", 0.0)))
		chunks_vis_max = maxi(chunks_vis_max, int(gauges.get("chunks_visible", 0.0)))
		var fc: Dictionary = snap.get("frame_counters", {})
		apply_count_sum += int(fc.get("chunks_streamed_applied", 0))

	var report := {
		"tag": tag,
		"session_sec": session_sec,
		"frames": frame_n,
		"stream_schedule_avg_ms": _mean(schedule_samples),
		"stream_schedule_max_ms": _maxa(schedule_samples),
		"stream_schedule_p95_ms": _pct(schedule_samples, 0.95),
		"chunk_upload_avg_ms": _mean(upload_samples),
		"chunk_upload_max_ms": _maxa(upload_samples),
		"chunk_apply_avg_ms": _mean(apply_samples),
		"chunk_apply_max_ms": _maxa(apply_samples),
		"cm_process_avg_ms": _mean(cm_func_samples),
		"cm_process_max_ms": _maxa(cm_func_samples),
		"cm_process_p95_ms": _pct(cm_func_samples, 0.95),
		"load_pending_max": load_pending_max,
		"mesh_queue_max": mesh_q_max,
		"inflight_max": inflight_max,
		"chunks_visible_max": chunks_vis_max,
		"chunks_applied_sum": apply_count_sum,
		"path_steps": path_i,
	}
	var jp := scratch.path_join("stream_opt_%s.json" % tag)
	var mp := scratch.path_join("stream_opt_%s.md" % tag)
	var jf := FileAccess.open(jp, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify(report, "\t"))
		jf.close()
	var md := _md(report)
	var mf := FileAccess.open(mp, FileAccess.WRITE)
	if mf:
		mf.store_string(md)
		mf.close()
	print(md)
	print("STREAM_OPT_OK tag=%s schedule_avg=%.3f schedule_max=%.3f cm_max=%.3f" % [
		tag, float(report.stream_schedule_avg_ms), float(report.stream_schedule_max_ms),
		float(report.cm_process_max_ms),
	])
	print("WROTE %s" % jp)
	_ProbeExit.finish_tree(self, 0, "STREAM_OPT_OK")


func _md(r: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Stream opt probe (%s)" % str(r.get("tag", "")))
	lines.append("")
	lines.append("| Metric | Value |")
	lines.append("|--------|------:|")
	for k in [
		"session_sec", "frames", "path_steps",
		"stream_schedule_avg_ms", "stream_schedule_p95_ms", "stream_schedule_max_ms",
		"chunk_apply_avg_ms", "chunk_apply_max_ms",
		"chunk_upload_avg_ms", "chunk_upload_max_ms",
		"cm_process_avg_ms", "cm_process_p95_ms", "cm_process_max_ms",
		"load_pending_max", "mesh_queue_max", "inflight_max", "chunks_visible_max",
		"chunks_applied_sum",
	]:
		var v = r.get(k, 0)
		if typeof(v) == TYPE_FLOAT:
			lines.append("| %s | %.4f |" % [k, float(v)])
		else:
			lines.append("| %s | %s |" % [k, str(v)])
	lines.append("")
	return "\n".join(lines)


func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())


func _maxa(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		if v > m:
			m = v
	return m


func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var arr: Array = []
	for v in a:
		arr.append(v)
	arr.sort()
	var i: int = clampi(int(floor(float(arr.size() - 1) * p)), 0, arr.size() - 1)
	return float(arr[i])
