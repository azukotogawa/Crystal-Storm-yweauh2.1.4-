extends SceneTree
## Headless streaming lifecycle investigation — lifecycle telemetry + stall timeline (no optimizations).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkStreamingTelemetry = preload("res://systems/chunk_streaming_telemetry.gd")
const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")

const BASELINE_AVG_FRAME_MS := 20.889
const BASELINE_P95_FRAME_MS := 71.4
const BASELINE_WORKER_AVG_MS := 14.656
const STALL_THRESHOLD_MS := 33.0
const SPIKE_THRESHOLD_MS := 100.0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-10619a925a26/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("streaming investigation: main scene missing")
		_ProbeExit.finish_tree(self, 1, "Streaming lifecycle investigation FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")

	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		if (
			player != null and chunk_manager != null and profiler != null
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 5
		):
			break
		await process_frame

	if chunk_manager == null or player == null:
		push_error("streaming investigation: bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Streaming lifecycle investigation FAILED")
		return

	if not _verify_perf_preset(chunk_manager):
		_ProbeExit.finish_tree(self, 1, "Streaming lifecycle investigation FAILED")
		return

	for _w in 60:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	_ChunkStreamingTelemetry.reset()
	_ChunkRebuildTelemetry.reset()

	var stats: Dictionary = {}
	await _scenario_sustained_movement(player, chunk_manager, profiler, stats, 25.0)
	_ChunkStreamingTelemetry.set_scenario("directional_crossing")
	await _scenario_directional_crossing(player, chunk_manager, profiler, stats, 20.0)

	var telemetry_path := "%s/streaming_lifecycle_telemetry.jsonl" % scratch
	_ChunkStreamingTelemetry.write_jsonl(telemetry_path)

	var frame_samples: Array = _ChunkStreamingTelemetry.get_frame_samples()
	var lifecycles: Array = _ChunkStreamingTelemetry.get_lifecycle_summaries()
	var events: Array = _ChunkStreamingTelemetry.get_events()

	if frame_samples.is_empty() and lifecycles.is_empty():
		_ProbeExit.finish_tree(self, 1, "Streaming lifecycle investigation FAILED")
		return

	var report := _build_report(frame_samples, lifecycles, events, stats)
	var report_path := "%s/streaming_lifecycle_report.md" % scratch
	_write_text(report_path, report)

	var baseline := _build_baseline_summary(frame_samples, lifecycles, events, stats)
	var after_tag := OS.get_environment("CRYSTALSTORM_STREAM_AFTER").strip_edges()
	if after_tag == "1":
		baseline = "## Post-optimization capture (Phases 2–5)\n\n" + baseline
	var baseline_path := "%s/streaming_baseline_summary.md" % scratch
	_write_text(baseline_path, baseline)

	print(report)
	print("STREAMING_TELEMETRY=%s" % telemetry_path)
	print("STREAMING_REPORT=%s" % report_path)
	print("STREAMING_BASELINE=%s" % baseline_path)
	_ProbeExit.finish_tree(self, 0, "Streaming lifecycle investigation OK")


func _verify_perf_preset(chunk_manager: ChunkManager) -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	var expected_dist := 2
	var expected_inflight := 4
	if raw in ["low", "0"]:
		expected_dist = 1
		expected_inflight = 2
	elif raw in ["high", "2"]:
		expected_dist = 3
		expected_inflight = 6
	elif raw in ["safe", "minimal"]:
		expected_dist = 1
		expected_inflight = 2
	var actual_dist: int = int(chunk_manager.RENDER_DISTANCE)
	var actual_inflight: int = int(chunk_manager.MAX_INFLIGHT_CHUNKS)
	print(
		"INVESTIGATION_PRESET_ENV=%s RENDER_DISTANCE=%d MAX_INFLIGHT=%d (expect dist=%d inflight=%d)"
		% [raw, actual_dist, actual_inflight, expected_dist, expected_inflight]
	)
	if actual_dist != expected_dist or actual_inflight != expected_inflight:
		push_error(
			"streaming investigation: perf preset not applied (env=%s dist=%d inflight=%d)"
			% [raw, actual_dist, actual_inflight]
		)
		return false
	return true


func _scenario_sustained_movement(
	player: Node,
	chunk_manager: ChunkManager,
	profiler: Node,
	stats: Dictionary,
	seconds: float
) -> void:
	_ChunkStreamingTelemetry.set_scenario("sustained_movement")
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context("movement", {})
	var move_dirs: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	var frame_times: Array[float] = []
	var worker_samples: Array[float] = []
	var upload_samples: Array[float] = []
	var stream_events := 0
	var start_chunks := chunk_manager.chunks.size()
	var start_player_chunk := chunk_manager.get_player_chunk_coord() if chunk_manager.has_method("get_player_chunk_coord") else Vector2i.ZERO
	var dir_idx := 0

	while Time.get_ticks_msec() < end_ms:
		await process_frame
		frames += 1
		var phase := frames % 90
		var move_action := move_dirs[dir_idx % move_dirs.size()]
		if phase < 45:
			Input.action_press(move_action)
		else:
			Input.action_release(move_action)
			if phase == 45:
				dir_idx += 1
		if profiler and profiler.has_method("get_snapshot"):
			var snap: Dictionary = profiler.get_snapshot()
			frame_times.append(float(snap.get("frame_ms", 0.0)))
			worker_samples.append(float(snap.get("worker_ms", 0.0)))
			upload_samples.append(float(snap.get("sections", {}).get("chunk_upload", {}).get("last_ms", 0.0)))

	for action in move_dirs:
		Input.action_release(action)

	var end_player_chunk := chunk_manager.get_player_chunk_coord() if chunk_manager.has_method("get_player_chunk_coord") else Vector2i.ZERO
	for ev in _ChunkStreamingTelemetry.get_events():
		if str(ev.get("event", "")) == "stream_pass":
			stream_events += 1

	stats["sustained_movement"] = {
		"frames": frames,
		"start_chunks": start_chunks,
		"end_chunks": chunk_manager.chunks.size(),
		"player_chunk_delta": end_player_chunk - start_player_chunk,
		"stream_pass_events": stream_events,
		"avg_frame_ms": _mean(frame_times),
		"p95_frame_ms": _percentile(frame_times, 0.95),
		"worst_frame_ms": _max(frame_times),
		"stall_frames_gt_33ms": _count_gt(frame_times, STALL_THRESHOLD_MS),
		"spike_frames_gt_100ms": _count_gt(frame_times, SPIKE_THRESHOLD_MS),
		"avg_worker_ms": _mean(worker_samples),
		"avg_upload_ms": _mean(upload_samples),
	}


func _scenario_directional_crossing(
	player: Node,
	chunk_manager: ChunkManager,
	profiler: Node,
	stats: Dictionary,
	seconds: float
) -> void:
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context("movement", {})
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	var frame_times: Array[float] = []
	var start_chunk := chunk_manager.get_player_chunk_coord() if chunk_manager.has_method("get_player_chunk_coord") else Vector2i.ZERO
	Input.action_press("ui_right")

	while Time.get_ticks_msec() < end_ms:
		await process_frame
		frames += 1
		if profiler and profiler.has_method("get_snapshot"):
			var snap: Dictionary = profiler.get_snapshot()
			frame_times.append(float(snap.get("frame_ms", 0.0)))

	Input.action_release("ui_right")
	var end_chunk := chunk_manager.get_player_chunk_coord() if chunk_manager.has_method("get_player_chunk_coord") else Vector2i.ZERO
	stats["directional_crossing"] = {
		"frames": frames,
		"start_chunk": start_chunk,
		"end_chunk": end_chunk,
		"chunks_crossed": absi(end_chunk.x - start_chunk.x) + absi(end_chunk.y - start_chunk.y),
		"avg_frame_ms": _mean(frame_times),
		"p95_frame_ms": _percentile(frame_times, 0.95),
		"worst_frame_ms": _max(frame_times),
		"stall_frames_gt_33ms": _count_gt(frame_times, STALL_THRESHOLD_MS),
	}


func _build_report(
	frame_samples: Array,
	lifecycles: Array,
	events: Array,
	stats: Dictionary
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Streaming lifecycle investigation (Phase 1)")
	lines.append("")
	lines.append("**Context:** Post-incremental baseline avg frame **%.3f ms**, P95 **%.1f ms**, worker **%.3f ms**." % [
		BASELINE_AVG_FRAME_MS, BASELINE_P95_FRAME_MS, BASELINE_WORKER_AVG_MS,
	])
	lines.append("**Method:** `CRYSTALSTORM_CHUNK_PROFILE=1` lifecycle telemetry on production `main.tscn`.")
	lines.append("")

	lines.append("## Session frame metrics")
	lines.append("")
	var sustained: Dictionary = stats.get("sustained_movement", {})
	var crossing: Dictionary = stats.get("directional_crossing", {})
	lines.append("| Scenario | Frames | Avg frame (ms) | P95 (ms) | Worst (ms) | Stalls >33ms | Spikes >100ms |")
	lines.append("|----------|--------|----------------|----------|------------|--------------|---------------|")
	lines.append("| sustained_movement | %d | %.3f | %.3f | %.3f | %d | %d |" % [
		int(sustained.get("frames", 0)),
		float(sustained.get("avg_frame_ms", 0.0)),
		float(sustained.get("p95_frame_ms", 0.0)),
		float(sustained.get("worst_frame_ms", 0.0)),
		int(sustained.get("stall_frames_gt_33ms", 0)),
		int(sustained.get("spike_frames_gt_100ms", 0)),
	])
	lines.append("| directional_crossing | %d | %.3f | %.3f | %.3f | %d | — |" % [
		int(crossing.get("frames", 0)),
		float(crossing.get("avg_frame_ms", 0.0)),
		float(crossing.get("p95_frame_ms", 0.0)),
		float(crossing.get("worst_frame_ms", 0.0)),
		int(crossing.get("stall_frames_gt_33ms", 0)),
	])
	lines.append("")

	lines.append("## Lifecycle stage latency (stream-triggered chunks)")
	lines.append("")
	var stream_lcs := _filter_stream_lifecycles(lifecycles)
	lines.append("| Stage transition | Avg (ms) | P95 (ms) | Max (ms) | Samples |")
	lines.append("|------------------|----------|----------|----------|---------|")
	for stage in [
		["request → worker active", "queue_wait_ms"],
		["worker active → height", "generation_latency_ms"],
		["mesh → upload start", "upload_queue_wait_ms"],
		["upload queued → uploaded", "upload_latency_ms"],
		["request → active", "activation_latency_ms"],
	]:
		var vals := _collect_lc_metric(stream_lcs, stage[1])
		lines.append("| %s | %.3f | %.3f | %.3f | %d |" % [
			stage[0],
			_mean(vals),
			_percentile(vals, 0.95),
			_max(vals),
			vals.size(),
		])
	lines.append("")
	lines.append("Stream lifecycles completed: **%d** (movement triggers only)." % stream_lcs.size())
	lines.append("")

	lines.append("## Worker queue occupancy")
	lines.append("")
	var queue_depths: Array[float] = []
	var inflight_depths: Array[float] = []
	var idle_frames := 0
	for sample in frame_samples:
		queue_depths.append(float(sample.get("mesh_queue_depth", 0)))
		inflight_depths.append(float(sample.get("inflight_total", 0)))
		if bool(sample.get("worker_idle", false)):
			idle_frames += 1
	lines.append("- Mesh completion queue: avg **%.2f**, max **%.0f**" % [_mean(queue_depths), _max(queue_depths)])
	lines.append("- Total inflight (tasks + mesh queue): avg **%.2f**, max **%.0f**" % [_mean(inflight_depths), _max(inflight_depths)])
	lines.append("- Worker-idle frames: **%d / %d** (%.1f%%)" % [
		idle_frames,
		frame_samples.size(),
		100.0 * float(idle_frames) / maxf(float(frame_samples.size()), 1.0),
	])
	lines.append("")

	lines.append("## Allocation path (stream loads)")
	lines.append("")
	var alloc_new := 0
	var alloc_reuse := 0
	var alloc_pool := 0
	for lc in stream_lcs:
		var path := str(lc.get("alloc_path", ""))
		if path == "ChunkData.new":
			alloc_new += 1
		elif path == "reuse":
			alloc_reuse += 1
		elif path == "pool_reuse":
			alloc_pool += 1
	lines.append("- `ChunkData.new` on stream path: **%d**" % alloc_new)
	lines.append("- `pool_reuse` on stream path: **%d**" % alloc_pool)
	lines.append("- `reuse` (terrain path) on stream rows: **%d**" % alloc_reuse)
	lines.append("")

	lines.append("## Stall timeline (worst frames)")
	lines.append("")
	var stall_rows := _build_stall_timeline(frame_samples, events, 12)
	lines.append("| Frame | Frame ms | Worker ms | Upload ms | Mesh Q | Inflight | Correlated events |")
	lines.append("|-------|----------|-----------|-----------|--------|----------|-------------------|")
	for row in stall_rows:
		lines.append("| %d | %.2f | %.2f | %.2f | %d | %d | %s |" % [
			int(row.get("frame", 0)),
			float(row.get("frame_ms", 0.0)),
			float(row.get("worker_ms", 0.0)),
			float(row.get("upload_ms", 0.0)),
			int(row.get("mesh_queue_depth", 0)),
			int(row.get("inflight_total", 0)),
			str(row.get("events_summary", "")),
		])
	lines.append("")

	lines.append("## Where streaming stalls (narrative)")
	lines.append("")
	lines.append(_stall_narrative(frame_samples, events, stream_lcs, sustained))
	lines.append("")

	lines.append("## Unload events")
	lines.append("")
	var unloads := 0
	for ev in events:
		if str(ev.get("event", "")).begins_with("unload_"):
			unloads += 1
	lines.append("Unload telemetry events: **%d**" % unloads)
	lines.append("")

	return "\n".join(lines)


func _build_baseline_summary(
	frame_samples: Array,
	lifecycles: Array,
	events: Array,
	stats: Dictionary
) -> String:
	var sustained: Dictionary = stats.get("sustained_movement", {})
	var stream_lcs := _filter_stream_lifecycles(lifecycles)
	var frame_times: Array[float] = []
	var worker_times: Array[float] = []
	for sample in frame_samples:
		frame_times.append(float(sample.get("frame_us", 0)) / 1000.0)
		worker_times.append(float(sample.get("worker_us", 0)) / 1000.0)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Streaming baseline summary (Phase 1 — pre-optimization)")
	lines.append("")
	lines.append("Captured before lifecycle redesign / priority / reuse / frame-budget changes.")
	lines.append("")
	lines.append("## Frame pacing (movement session)")
	lines.append("")
	lines.append("| Metric | Value | Post-incremental ref |")
	lines.append("|--------|-------|----------------------|")
	lines.append("| Avg frame (ms) | %.3f | %.3f |" % [
		float(sustained.get("avg_frame_ms", _mean(frame_times))),
		BASELINE_AVG_FRAME_MS,
	])
	lines.append("| P95 frame (ms) | %.3f | %.1f |" % [
		float(sustained.get("p95_frame_ms", _percentile(frame_times, 0.95))),
		BASELINE_P95_FRAME_MS,
	])
	lines.append("| Worst frame (ms) | %.3f | 684.88 (movement variance) |" % float(sustained.get("worst_frame_ms", _max(frame_times))))
	lines.append("| Avg worker (ms) | %.3f | %.3f |" % [
		float(sustained.get("avg_worker_ms", _mean(worker_times))),
		BASELINE_WORKER_AVG_MS,
	])
	lines.append("| Stall frames >33ms | %d | — |" % int(sustained.get("stall_frames_gt_33ms", 0)))
	lines.append("| Spike frames >100ms | %d | — |" % int(sustained.get("spike_frames_gt_100ms", 0)))
	lines.append("")

	lines.append("## Streaming churn")
	lines.append("")
	lines.append("- Stream pass events: **%d**" % int(sustained.get("stream_pass_events", 0)))
	lines.append("- Chunks loaded (lifecycle completes): **%d**" % stream_lcs.size())
	lines.append("- Player chunk delta (sustained): **%s**" % str(sustained.get("player_chunk_delta", Vector2i.ZERO)))
	lines.append("- Chunks crossed (directional): **%d**" % int(stats.get("directional_crossing", {}).get("chunks_crossed", 0)))
	lines.append("")

	var activation := _collect_lc_metric(stream_lcs, "activation_latency_ms")
	lines.append("## Chunk activation latency (request → ACTIVE)")
	lines.append("")
	lines.append("| Avg (ms) | P95 (ms) | Max (ms) |")
	lines.append("|----------|----------|----------|")
	lines.append("| %.3f | %.3f | %.3f |" % [_mean(activation), _percentile(activation, 0.95), _max(activation)])
	lines.append("")

	var alloc_new := 0
	var alloc_pool := 0
	for lc in stream_lcs:
		var path := str(lc.get("alloc_path", ""))
		if path == "ChunkData.new":
			alloc_new += 1
		elif path == "pool_reuse":
			alloc_pool += 1
	lines.append("## Alloc-path counts")
	lines.append("")
	lines.append("- Stream `ChunkData.new`: **%d**" % alloc_new)
	lines.append("- Stream `pool_reuse`: **%d**" % alloc_pool)
	lines.append("- Stream `reuse` (terrain rows): **%d**" % maxi(stream_lcs.size() - alloc_new - alloc_pool, 0))
	lines.append("")

	return "\n".join(lines)


func _stall_narrative(
	frame_samples: Array,
	events: Array,
	stream_lcs: Array,
	sustained: Dictionary
) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var worst_ms := float(sustained.get("worst_frame_ms", 0.0))
	var avg_activation := _mean(_collect_lc_metric(stream_lcs, "activation_latency_ms"))
	var avg_upload_wait := _mean(_collect_lc_metric(stream_lcs, "upload_queue_wait_ms"))
	var avg_queue_wait := _mean(_collect_lc_metric(stream_lcs, "queue_wait_ms"))

	parts.append("1. **Chunk crossing triggers burst requests.** `update_stream` fires when the player enters a new chunk column; `stream_pass` events enqueue up to `MAX_INFLIGHT_CHUNKS` worker tasks per pass while distant chunks are sorted by Manhattan distance (not velocity-aware).")
	parts.append("2. **Worker queue wait** averages **%.2f ms** (request → worker active). FIFO `WorkerThreadPool` scheduling means far-ring chunks can delay near chunks when inflight cap is saturated." % avg_queue_wait)
	parts.append("3. **Generation spike** is concentrated in worker `column_map + build_mesh` (see `generation_latency_ms` in lifecycle summaries). Height and mesh generation run back-to-back on the worker with no frame spreading.")
	parts.append("4. **Upload queue backlog** averages **%.2f ms** from mesh-complete to upload-start. Main-thread `_drain_mesh_queue` is capped by `MAX_CHUNKS_PER_FRAME` and `chunk_upload_budget_us`, so completed meshes can pile up in `_mesh_completion_queue`." % avg_upload_wait)
	parts.append("5. **Main-thread upload + scene attach** (`ChunkView.setup`, MultiMesh rebuild) correlates with `chunk_upload` section spikes in worst frames (**%.2f ms** worst observed this session)." % worst_ms)
	parts.append("6. **End-to-end activation** (request → ACTIVE) averages **%.2f ms** per stream chunk — the primary user-visible streaming latency." % avg_activation)
	parts.append("7. **Unload** is deferred via `_stream_unload_pending` (budgeted per frame) but can still coincide with upload drains when both budgets fire on the same frame.")
	return "\n".join(parts)


func _filter_stream_lifecycles(lifecycles: Array) -> Array:
	var out: Array = []
	for lc in lifecycles:
		var trigger := str(lc.get("trigger", ""))
		if trigger in ["stream", "movement"] and int(lc.get("active_us", 0)) > 0:
			out.append(lc)
	return out


func _collect_lc_metric(lifecycles: Array, key: String) -> Array[float]:
	var out: Array[float] = []
	for lc in lifecycles:
		var v := float(lc.get(key, 0.0))
		if v > 0.0:
			out.append(v)
	return out


func _build_stall_timeline(frame_samples: Array, events: Array, limit: int) -> Array:
	var ranked: Array = []
	for sample in frame_samples:
		var frame_ms := float(sample.get("frame_us", 0)) / 1000.0
		if frame_ms <= 0.0:
			continue
		ranked.append(sample.duplicate())
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("frame_us", 0)) > float(b.get("frame_us", 0))
	)

	var rows: Array = []
	for i in mini(limit, ranked.size()):
		var sample: Dictionary = ranked[i]
		var frame_n := int(sample.get("frame", 0))
		var nearby := _events_near_frame(events, frame_n, 2)
		rows.append({
			"frame": frame_n,
			"frame_ms": float(sample.get("frame_us", 0)) / 1000.0,
			"worker_ms": float(sample.get("worker_us", 0)) / 1000.0,
			"upload_ms": float(sample.get("upload_us", 0)) / 1000.0,
			"mesh_queue_depth": int(sample.get("mesh_queue_depth", 0)),
			"inflight_total": int(sample.get("inflight_total", 0)),
			"events_summary": _summarize_events(nearby),
		})
	return rows


func _events_near_frame(events: Array, frame: int, radius: int) -> Array:
	var out: Array = []
	for ev in events:
		var f := int(ev.get("frame", -999))
		if absi(f - frame) <= radius:
			out.append(ev)
	return out


func _summarize_events(events: Array) -> String:
	if events.is_empty():
		return "—"
	var counts: Dictionary = {}
	for ev in events:
		var name := str(ev.get("event", "?"))
		counts[name] = int(counts.get(name, 0)) + 1
	var parts: PackedStringArray = PackedStringArray()
	for key in counts.keys():
		parts.append("%s×%d" % [key, int(counts[key])])
	return ", ".join(parts)


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


static func _max(values: Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, float(v))
	return m


static func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var idx := int(floorf(float(sorted.size() - 1) * p))
	return float(sorted[idx])


static func _count_gt(values: Array, threshold: float) -> int:
	var n := 0
	for v in values:
		if float(v) > threshold:
			n += 1
	return n


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	f.store_string(text)
	f.close()