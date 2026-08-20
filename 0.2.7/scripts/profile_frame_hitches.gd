extends SceneTree
## Measure frame-time spikes while walking a baked world.
## Measurement only — no optimizations.
##
## Usage:
##   CRYSTALSTORM_HITCH_SEC=60 CRYSTALSTORM_SCRATCH=... \
##     godot --headless -s scripts/profile_frame_hitches.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const THRESHOLDS_MS: Array = [8.0, 12.0, 16.0, 25.0, 33.0, 50.0]

## Map user-facing subsystem labels → PerfProfiler section keys / sources.
const SUBSYSTEM_MAP: Array = [
	{"label": "ChunkManager.process", "section": "stream_schedule", "func": "ChunkManager::_process"},
	{"label": "ChunkView_uploads", "section": "chunk_upload"},
	{"label": "chunk_apply", "section": "chunk_apply"},
	{"label": "RenderingServer_calls", "section": "chunk_upload"},  # buffer set attributed here
	{"label": "MultiMesh_updates", "counter": "multimesh_buffer_sets"},
	{"label": "WorldState", "section": "world_state"},
	{"label": "Crystal_update", "section": "crystal_sim"},
	{"label": "Crystal_mesh", "section": "crystal_mesh"},
	{"label": "AI", "section": "entity_physics"},
	{"label": "LivingWorld", "section": "living_world"},
	{"label": "Navigation", "section": "entity_navigation"},
	{"label": "Physics", "engine": "physics"},
	{"label": "SceneTree_process", "engine": "process"},
	{"label": "SceneTree_physics", "engine": "physics"},
	{"label": "Garbage_collection", "special": "mem_delta"},
	{"label": "Resource_loading", "section": "package_file_read"},
	{"label": "Worker_synchronization", "section": "worker_total", "worker": true},
	{"label": "Main_thread_waiting", "special": "untracked"},
	{"label": "chunk_column_worker", "section": "chunk_column", "worker": true},
	{"label": "chunk_mesh_worker", "section": "chunk_mesh", "worker": true},
	{"label": "player_physics", "section": "player_physics"},
	{"label": "entity_combat", "section": "entity_combat"},
	{"label": "vegetation_growth", "section": "vegetation_growth"},
	{"label": "ui_overlay", "section": "ui_overlay"},
]


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_MESH_PLAN_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_STARTUP_PROFILE", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "/tmp/grok-goal-3c89103bbbb9/implementer")
	call_deferred("_run")


func _run() -> void:
	var session_sec: float = float(OS.get_environment("CRYSTALSTORM_HITCH_SEC"))
	if session_sec <= 0.0:
		session_sec = 60.0
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("main missing")
		_ProbeExit.finish_tree(self, 1, "HITCH_PROFILE FAILED")
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	var compose = game.get_node_or_null("CompositionRoot")
	var frames_wait := 0
	while compose and not bool(compose.get("_boot_done")) and frames_wait < 3600:
		await process_frame
		frames_wait += 1
	# Extra settle frames after boot
	for _i in 30:
		await process_frame

	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")
	var player: Node = get_first_node_in_group("player")
	var cm = get_first_node_in_group("chunk_manager")
	if profiler == null or player == null:
		push_error("profiler or player missing")
		_ProbeExit.finish_tree(self, 1, "HITCH_PROFILE FAILED")
		return
	if profiler.has_method("set") and "enabled" in profiler:
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

	# Snake path through baked package coords (repeat for full session).
	var path: Array = []
	for cz in range(min_cz, max_cz + 1):
		var xs: Array = range(min_cx, max_cx + 1)
		if (cz - min_cz) % 2 == 1:
			xs.reverse()
		for cx in xs:
			path.append(Vector2i(cx, cz))
	var base: Array = path.duplicate()
	while path.size() < 400:
		path.append_array(base)

	var hitches: Array = []  # all frames over 8ms
	var bucket_counts: Dictionary = {}
	for t in THRESHOLDS_MS:
		bucket_counts[str(t)] = 0
	var cause_totals: Dictionary = {}  # label -> {sum_ms, max_ms, hitch_frames, as_primary}
	var all_frame_ms: PackedFloat32Array = PackedFloat32Array()

	var path_i := 0
	var last_move_ms := Time.get_ticks_msec()
	var t0 := Time.get_ticks_msec()
	var frame_n := 0
	var prev_draw_calls := 0
	var prev_nodes := 0
	var prev_mem_mb := 0.0
	var prev_mm_nodes := 0
	var prev_mm_inst := 0

	# Baseline
	if profiler.has_method("sample_scene_stats"):
		profiler.sample_scene_stats(self)
	var snap0: Dictionary = profiler.get_snapshot() if profiler.has_method("get_snapshot") else {}
	prev_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	prev_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	prev_mem_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	var ss0: Dictionary = snap0.get("scene_stats", {})
	prev_mm_nodes = int(ss0.get("multimesh_nodes", 0))
	prev_mm_inst = int(ss0.get("multimesh_instances", 0))

	print("HITCH_PROFILE begin session_sec=%.0f bake=[%d..%d]x[%d..%d]" % [
		session_sec, min_cx, max_cx, min_cz, max_cz
	])

	while Time.get_ticks_msec() - t0 < int(session_sec * 1000.0):
		# Move every ~300ms along path
		if Time.get_ticks_msec() - last_move_ms >= 300 and path_i < path.size():
			var target: Vector2i = path[path_i]
			path_i += 1
			last_move_ms = Time.get_ticks_msec()
			var wx: float = float(target.x * 16) + 8.0
			var wz: float = float(target.y * 16) + 8.0
			if player:
				var py: float = player.global_position.y
				player.global_position = Vector3(wx, py, wz)
			if cm and cm.has_method("update_stream"):
				cm.update_stream(target.x, target.y)

		await process_frame
		frame_n += 1

		# Sample scene stats every frame on hitches; every 5 frames otherwise (cheaper).
		var snap: Dictionary = profiler.get_snapshot() if profiler.has_method("get_snapshot") else {}
		var frame_ms: float = float(snap.get("frame_ms", 0.0))
		# Prefer engine TIME_PROCESS as alternate wall if larger
		var eng_proc: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		var eng_phys: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		if eng_proc > frame_ms:
			frame_ms = eng_proc
		all_frame_ms.append(frame_ms)

		var is_hitch: bool = frame_ms >= 8.0
		if is_hitch or frame_n % 5 == 0:
			if profiler.has_method("sample_scene_stats"):
				profiler.sample_scene_stats(self)
			snap = profiler.get_snapshot() if profiler.has_method("get_snapshot") else {}

		if not is_hitch:
			prev_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prev_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			prev_mem_mb = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
			continue

		for t in THRESHOLDS_MS:
			if frame_ms >= float(t):
				bucket_counts[str(t)] = int(bucket_counts[str(t)]) + 1

		var secs: Dictionary = snap.get("sections", {})
		var funcs: Dictionary = snap.get("funcs", {})
		var gauges: Dictionary = snap.get("gauges", {})
		var counters: Dictionary = snap.get("frame_counters", {})
		var scene: Dictionary = snap.get("scene_stats", {})

		var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var nodes_now := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var mem_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
		var mm_nodes := int(scene.get("multimesh_nodes", 0))
		var mm_inst := int(scene.get("multimesh_instances", 0))

		var subsystems: Dictionary = {}
		var primary := "unknown"
		var primary_ms := -1.0

		for entry in SUBSYSTEM_MAP:
			var label: String = str(entry.label)
			var ms := 0.0
			if entry.has("special"):
				var sp: String = str(entry.special)
				if sp == "untracked":
					ms = float(snap.get("untracked_ms", 0.0))
				elif sp == "mem_delta":
					# Proxy: static memory growth this frame (MB→not ms). Store as 0 ms but note delta.
					ms = 0.0
			elif entry.has("engine"):
				if str(entry.engine) == "process":
					ms = eng_proc
				else:
					ms = eng_phys
			elif entry.has("func") and funcs.has(str(entry.func)):
				ms = float(funcs[str(entry.func)].get("last_ms", 0.0))
			elif entry.has("section") and secs.has(str(entry.section)):
				ms = float(secs[str(entry.section)].get("last_ms", 0.0))
			elif entry.has("counter"):
				# Count-only; not milliseconds
				ms = 0.0
			subsystems[label] = ms
			# Primary cause: largest main-thread section (skip pure engine wall which equals frame)
			if not entry.get("worker", false) and str(entry.get("engine", "")) == "":
				if ms > primary_ms and label not in ["SceneTree_process", "SceneTree_physics", "Physics"]:
					primary_ms = ms
					primary = label

		# If untracked dominates, name it
		var untracked: float = float(snap.get("untracked_ms", 0.0))
		if untracked > primary_ms and untracked > frame_ms * 0.35:
			primary = "Main_thread_waiting_untracked"
			primary_ms = untracked

		# Ranked causes for this frame
		var ranked: Array = []
		for k in subsystems.keys():
			ranked.append({"name": k, "ms": float(subsystems[k])})
		ranked.sort_custom(func(a, b): return float(a.ms) > float(b.ms))

		# Accumulate cause totals among hitches
		for row in ranked:
			var nm: String = str(row.name)
			if not cause_totals.has(nm):
				cause_totals[nm] = {"sum_ms": 0.0, "max_ms": 0.0, "hitch_frames": 0, "as_primary": 0}
			var ct: Dictionary = cause_totals[nm]
			var rms: float = float(row.ms)
			if rms > 0.01:
				ct["sum_ms"] = float(ct.sum_ms) + rms
				ct["max_ms"] = maxf(float(ct.max_ms), rms)
				ct["hitch_frames"] = int(ct.hitch_frames) + 1
			cause_totals[nm] = ct
		if cause_totals.has(primary):
			cause_totals[primary]["as_primary"] = int(cause_totals[primary].get("as_primary", 0)) + 1
		else:
			cause_totals[primary] = {"sum_ms": primary_ms, "max_ms": primary_ms, "hitch_frames": 1, "as_primary": 1}

		var streamed_cx := int(gauges.get("last_streamed_cx", 99999))
		var streamed_cz := int(gauges.get("last_streamed_cz", 99999))
		var streamed_frame := int(gauges.get("last_streamed_frame", -1))
		var chunk_streamed := ""
		if streamed_frame == Engine.get_process_frames() or int(counters.get("chunks_streamed_applied", 0)) > 0:
			chunk_streamed = "(%d,%d)" % [streamed_cx, streamed_cz]
		elif int(counters.get("chunks_streamed_applied", 0)) > 0:
			chunk_streamed = "(%d,%d)" % [streamed_cx, streamed_cz]

		var hitch := {
			"frame": frame_n,
			"engine_frame": Engine.get_process_frames(),
			"frame_ms": frame_ms,
			"thresholds": _threshold_tags(frame_ms),
			"primary_cause": primary,
			"primary_ms": primary_ms,
			"subsystems_ms": subsystems,
			"top_funcs": _top_funcs(funcs, 8),
			"chunk_streamed": chunk_streamed,
			"chunks_applied": int(counters.get("chunks_streamed_applied", 0)),
			"multimesh_buffer_sets": int(counters.get("multimesh_buffer_sets", 0)),
			"multimesh_instances_uploaded": int(counters.get("multimesh_instances_uploaded", 0)),
			"buffers_recreated": int(counters.get("buffers_recreated", 0)),
			"draw_calls": draw_calls,
			"draw_calls_delta": draw_calls - prev_draw_calls,
			"multimesh_nodes": mm_nodes,
			"multimesh_nodes_delta": mm_nodes - prev_mm_nodes,
			"multimesh_instances": mm_inst,
			"multimesh_instances_delta": mm_inst - prev_mm_inst,
			"nodes": nodes_now,
			"nodes_delta": nodes_now - prev_nodes,
			"mem_mb": mem_mb,
			"mem_delta_mb": mem_mb - prev_mem_mb,
			"worker_ms": float(snap.get("worker_ms", 0.0)),
			"untracked_ms": untracked,
			"engine_process_ms": eng_proc,
			"engine_physics_ms": eng_phys,
			"stream_queue": int(gauges.get("stream_queue_depth", 0)),
			"mesh_queue": int(gauges.get("mesh_queue_depth", 0)),
			"inflight": int(gauges.get("chunk_tasks_inflight", 0)),
			"ranked": ranked.slice(0, mini(10, ranked.size())),
		}
		hitches.append(hitch)

		prev_draw_calls = draw_calls
		prev_nodes = nodes_now
		prev_mem_mb = mem_mb
		prev_mm_nodes = mm_nodes
		prev_mm_inst = mm_inst

	# --- Report ---
	var report := _build_report(
		session_sec, frame_n, all_frame_ms, hitches, bucket_counts, cause_totals,
		min_cx, max_cx, min_cz, max_cz
	)
	var md_path := scratch.path_join("frame_hitch_report.md")
	var json_path := scratch.path_join("frame_hitch_report.json")
	_write(md_path, report)
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf:
		jf.store_string(JSON.stringify({
			"session_sec": session_sec,
			"frames": frame_n,
			"hitch_count": hitches.size(),
			"bucket_counts": bucket_counts,
			"cause_totals": cause_totals,
			"hitches": hitches,
			"frame_stats": {
				"avg_ms": _mean(all_frame_ms),
				"p95_ms": _pct(all_frame_ms, 0.95),
				"worst_ms": _maxa(all_frame_ms),
			},
		}, "\t"))
		jf.close()
	print(report)
	print("WROTE %s" % md_path)
	print("WROTE %s" % json_path)
	_ProbeExit.finish_tree(self, 0, "HITCH_PROFILE_OK")


func _threshold_tags(frame_ms: float) -> Array:
	var tags: Array = []
	for t in THRESHOLDS_MS:
		if frame_ms >= float(t):
			tags.append(">=%.0fms" % float(t))
	return tags


func _top_funcs(funcs: Dictionary, n: int) -> Array:
	var rows: Array = []
	for k in funcs.keys():
		rows.append({
			"name": str(k),
			"ms": float(funcs[k].get("last_ms", 0.0)),
			"calls": int(funcs[k].get("calls", 0)),
		})
	rows.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
	return rows.slice(0, mini(n, rows.size()))


func _build_report(
	session_sec: float,
	frames: int,
	all_ms: PackedFloat32Array,
	hitches: Array,
	buckets: Dictionary,
	causes: Dictionary,
	min_cx: int, max_cx: int, min_cz: int, max_cz: int
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Frame hitch profile (baked world walk)")
	lines.append("")
	lines.append("**Measurement only — no optimizations.**")
	lines.append("")
	lines.append("| Field | Value |")
	lines.append("|-------|------:|")
	lines.append("| Session | %.0f s |" % session_sec)
	lines.append("| Frames | %d |" % frames)
	lines.append("| Bake bounds | [%d..%d]×[%d..%d] |" % [min_cx, max_cx, min_cz, max_cz])
	lines.append("| Avg frame | %.3f ms |" % _mean(all_ms))
	lines.append("| P95 frame | %.3f ms |" % _pct(all_ms, 0.95))
	lines.append("| Worst frame | %.3f ms |" % _maxa(all_ms))
	lines.append("| Hitches (≥8 ms) | %d (%.1f%%) |" % [
		hitches.size(), 100.0 * float(hitches.size()) / float(maxi(frames, 1))
	])
	lines.append("")
	lines.append("## Hitch buckets (count of frames at or above threshold)")
	lines.append("")
	lines.append("| Threshold | Count | % of frames |")
	lines.append("|----------:|------:|------------:|")
	for t in THRESHOLDS_MS:
		var c: int = int(buckets.get(str(t), 0))
		lines.append("| ≥ %.0f ms | %d | %.2f%% |" % [
			float(t), c, 100.0 * float(c) / float(maxi(frames, 1))
		])
	lines.append("")

	# Ranked hitch causes by sum ms on hitch frames + primary count
	var ranked_causes: Array = []
	for k in causes.keys():
		var ct: Dictionary = causes[k]
		ranked_causes.append({
			"name": k,
			"sum_ms": float(ct.get("sum_ms", 0.0)),
			"max_ms": float(ct.get("max_ms", 0.0)),
			"hitch_frames": int(ct.get("hitch_frames", 0)),
			"as_primary": int(ct.get("as_primary", 0)),
			"avg_when_present": float(ct.get("sum_ms", 0.0)) / float(maxi(int(ct.get("hitch_frames", 1)), 1)),
		})
	ranked_causes.sort_custom(func(a, b): return int(a.as_primary) > int(b.as_primary))
	lines.append("## Ranked hitch causes (by # of frames as primary)")
	lines.append("")
	lines.append("| Rank | Cause | Primary # | Hitch frames present | Sum ms | Max ms | Avg when present |")
	lines.append("|-----:|-------|----------:|---------------------:|-------:|-------:|-----------------:|")
	var rnk := 0
	for row in ranked_causes:
		if int(row.as_primary) <= 0 and float(row.sum_ms) < 1.0:
			continue
		rnk += 1
		lines.append("| %d | %s | %d | %d | %.2f | %.2f | %.2f |" % [
			rnk, str(row.name), int(row.as_primary), int(row.hitch_frames),
			float(row.sum_ms), float(row.max_ms), float(row.avg_when_present),
		])
		if rnk >= 20:
			break
	lines.append("")

	ranked_causes.sort_custom(func(a, b): return float(a.sum_ms) > float(b.sum_ms))
	lines.append("## Ranked hitch causes (by sum ms on hitch frames)")
	lines.append("")
	lines.append("| Rank | Cause | Sum ms | Max ms | Hitch frames |")
	lines.append("|-----:|-------|-------:|-------:|-------------:|")
	rnk = 0
	for row in ranked_causes:
		if float(row.sum_ms) < 0.5:
			continue
		rnk += 1
		lines.append("| %d | %s | %.2f | %.2f | %d |" % [
			rnk, str(row.name), float(row.sum_ms), float(row.max_ms), int(row.hitch_frames),
		])
		if rnk >= 15:
			break
	lines.append("")

	# Top worst hitch frames detail
	var worst: Array = hitches.duplicate()
	worst.sort_custom(func(a, b): return float(a.frame_ms) > float(b.frame_ms))
	lines.append("## Worst hitch frames (top 25)")
	lines.append("")
	lines.append("| Frame | ms | Tags | Primary | Prim ms | Chunk | MM sets | Inst up | DrawΔ | NodesΔ | MemΔ MB | Worker | Untracked | Queue |")
	lines.append("|------:|---:|------|---------|--------:|-------|--------:|--------:|------:|-------:|--------:|-------:|----------:|------:|")
	var show_n := mini(25, worst.size())
	for i in show_n:
		var h: Dictionary = worst[i]
		var qinfo := "s%d/m%d/i%d" % [
			int(h.get("stream_queue", 0)),
			int(h.get("mesh_queue", 0)),
			int(h.get("inflight", 0)),
		]
		lines.append("| %d | %.2f | %s | %s | %.2f | %s | %d | %d | %d | %d | %.3f | %.2f | %.2f | %s |" % [
			int(h.frame),
			float(h.frame_ms),
			",".join(PackedStringArray(h.get("thresholds", []))),
			str(h.primary_cause),
			float(h.primary_ms),
			str(h.get("chunk_streamed", "")),
			int(h.get("multimesh_buffer_sets", 0)),
			int(h.get("multimesh_instances_uploaded", 0)),
			int(h.get("draw_calls_delta", 0)),
			int(h.get("nodes_delta", 0)),
			float(h.get("mem_delta_mb", 0.0)),
			float(h.get("worker_ms", 0.0)),
			float(h.get("untracked_ms", 0.0)),
			qinfo,
		])
	lines.append("")

	# Detailed breakdown of top 10 worst
	lines.append("## Detailed subsystem breakdown (top 10 worst frames)")
	lines.append("")
	for i in mini(10, worst.size()):
		var h2: Dictionary = worst[i]
		lines.append("### Frame %d — %.2f ms — primary **%s** (%.2f ms)" % [
			int(h2.frame), float(h2.frame_ms), str(h2.primary_cause), float(h2.primary_ms)
		])
		lines.append("")
		lines.append("| Subsystem | ms |")
		lines.append("|-----------|---:|")
		var subs: Dictionary = h2.get("subsystems_ms", {})
		var srows: Array = []
		for k in subs.keys():
			srows.append({"n": k, "ms": float(subs[k])})
		srows.sort_custom(func(a, b): return float(a.ms) > float(b.ms))
		for sr in srows:
			if float(sr.ms) < 0.05:
				continue
			lines.append("| %s | %.3f |" % [str(sr.n), float(sr.ms)])
		lines.append("")
		lines.append("- Chunk streamed: `%s` (applied=%d)" % [
			str(h2.get("chunk_streamed", "")), int(h2.get("chunks_applied", 0))
		])
		lines.append("- MultiMesh buffer sets: %d | instances uploaded: %d | buffers recreated: %d" % [
			int(h2.get("multimesh_buffer_sets", 0)),
			int(h2.get("multimesh_instances_uploaded", 0)),
			int(h2.get("buffers_recreated", 0)),
		])
		lines.append("- Draw calls: %d (Δ %+d) | MultiMesh nodes: %d (Δ %+d) | instances: %d (Δ %+d)" % [
			int(h2.get("draw_calls", 0)), int(h2.get("draw_calls_delta", 0)),
			int(h2.get("multimesh_nodes", 0)), int(h2.get("multimesh_nodes_delta", 0)),
			int(h2.get("multimesh_instances", 0)), int(h2.get("multimesh_instances_delta", 0)),
		])
		lines.append("- Nodes: %d (Δ %+d) | Mem: %.2f MB (Δ %+.3f)" % [
			int(h2.get("nodes", 0)), int(h2.get("nodes_delta", 0)),
			float(h2.get("mem_mb", 0.0)), float(h2.get("mem_delta_mb", 0.0)),
		])
		lines.append("- Engine process/physics: %.2f / %.2f ms | Worker: %.2f | Untracked: %.2f" % [
			float(h2.get("engine_process_ms", 0.0)), float(h2.get("engine_physics_ms", 0.0)),
			float(h2.get("worker_ms", 0.0)), float(h2.get("untracked_ms", 0.0)),
		])
		var tfs: Array = h2.get("top_funcs", [])
		if not tfs.is_empty():
			lines.append("- Top functions:")
			for tf in tfs:
				if float(tf.get("ms", 0.0)) < 0.05:
					continue
				lines.append("  - `%s`: %.3f ms (calls=%d)" % [
					str(tf.get("name", "")), float(tf.get("ms", 0.0)), int(tf.get("calls", 0))
				])
		lines.append("")

	lines.append("## Interpretation notes")
	lines.append("")
	lines.append("- `Main_thread_waiting_untracked` = frame wall not covered by named PerfProfiler sections.")
	lines.append("- `SceneTree_process` / engine process ≈ full frame wall (includes everything).")
	lines.append("- Worker stages (`chunk_mesh`, `chunk_column`) run off-main; they do not block the frame unless the main thread waits.")
	lines.append("- `chunk_apply` + `chunk_upload` are main-thread stream apply/GPU buffer path.")
	lines.append("- Outside-package regenerates may still appear if stream ring extends past bake bounds.")
	lines.append("")
	lines.append("HITCH_PROFILE_OK")
	return "\n".join(lines)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _mean(arr: PackedFloat32Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += float(v)
	return s / float(arr.size())


func _maxa(arr: PackedFloat32Array) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, float(v))
	return m


func _pct(arr: PackedFloat32Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var a: Array = []
	for v in arr:
		a.append(float(v))
	a.sort()
	var i: int = clampi(int(ceil(float(a.size()) * p)) - 1, 0, a.size() - 1)
	return float(a[i])
