extends SceneTree
## Headless LOW-preset sustained traversal probe (≥20s) for Epic 2 criterion 2.
## Must produce real stream churn — press/release patterns that never leave the start chunk are invalid.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkStreamingTelemetry = preload("res://systems/chunk_streaming_telemetry.gd")

const PROBE_SECONDS := 25.0
const MIN_CHUNKS_CROSSED := 2
const MIN_STREAM_PASS := 3
const STALL_THRESHOLD_MS := 33.0
const SPIKE_THRESHOLD_MS := 100.0

const PHASE1_P95_MS := 15.661
const PHASE1_WORST_MS := 200.590
const PHASE1_SPIKES := 18


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "low")
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-10619a925a26/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var env_preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	if env_preset not in ["low", "0"]:
		push_error("low traversal probe requires CRYSTALSTORM_PERF_PRESET=low (got %s)" % env_preset)
		_ProbeExit.finish_tree(self, 1, "streaming low traversal probe FAILED")
		return

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "streaming low traversal probe FAILED")
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
			and chunk_manager.chunks.size() >= 3
		):
			break
		await process_frame

	if chunk_manager == null or player == null:
		_ProbeExit.finish_tree(self, 1, "streaming low traversal probe FAILED")
		return

	if int(chunk_manager.RENDER_DISTANCE) != 1 or int(chunk_manager.MAX_INFLIGHT_CHUNKS) != 2:
		push_error(
			"low preset not applied: dist=%d inflight=%d"
			% [chunk_manager.RENDER_DISTANCE, chunk_manager.MAX_INFLIGHT_CHUNKS]
		)
		_ProbeExit.finish_tree(self, 1, "streaming low traversal probe FAILED")
		return

	print(
		"LOW_PROBE_PRESET_ENV=%s RENDER_DISTANCE=%d MAX_INFLIGHT=%d"
		% [env_preset, chunk_manager.RENDER_DISTANCE, chunk_manager.MAX_INFLIGHT_CHUNKS]
	)

	for _w in 45:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	_ChunkStreamingTelemetry.reset()
	_ChunkStreamingTelemetry.set_scenario("low_traversal_probe")
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context("movement", {})

	var frame_times: Array[float] = []
	var start_chunk := chunk_manager.get_player_chunk_coord()
	var stream_pass_before := _count_stream_pass_events()

	Input.action_press("ui_right")
	var end_ms := Time.get_ticks_msec() + int(PROBE_SECONDS * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < end_ms:
		await process_frame
		frames += 1
		if profiler and profiler.has_method("get_snapshot"):
			var snap: Dictionary = profiler.get_snapshot()
			frame_times.append(float(snap.get("frame_ms", 0.0)))
	Input.action_release("ui_right")

	for _idle in 60:
		await process_frame

	var end_chunk := chunk_manager.get_player_chunk_coord()
	var chunks_crossed := absi(end_chunk.x - start_chunk.x) + absi(end_chunk.y - start_chunk.y)
	var stream_pass_events := _count_stream_pass_events() - stream_pass_before
	var lifecycles := _filter_stream_lifecycles(_ChunkStreamingTelemetry.get_lifecycle_summaries())

	var stats := {
		"preset": "low",
		"frames": frames,
		"render_distance": chunk_manager.RENDER_DISTANCE,
		"max_inflight": chunk_manager.MAX_INFLIGHT_CHUNKS,
		"start_chunk": start_chunk,
		"end_chunk": end_chunk,
		"chunks_crossed": chunks_crossed,
		"stream_pass_events": stream_pass_events,
		"lifecycles_completed": lifecycles.size(),
		"avg_frame_ms": _mean(frame_times),
		"p95_frame_ms": _percentile(frame_times, 0.95),
		"p99_frame_ms": _percentile(frame_times, 0.99),
		"worst_frame_ms": _max(frame_times),
		"fps_1pct_low": 1000.0 / maxf(_percentile(frame_times, 0.99), 0.001),
		"stall_frames_gt_33ms": _count_gt(frame_times, STALL_THRESHOLD_MS),
		"spike_frames_gt_100ms": _count_gt(frame_times, SPIKE_THRESHOLD_MS),
	}

	var churn_ok := (
		chunks_crossed >= MIN_CHUNKS_CROSSED
		and stream_pass_events >= MIN_STREAM_PASS
		and lifecycles.size() >= 20
	)
	var pacing_ok := (
		float(stats.get("p95_frame_ms", 999.0)) <= PHASE1_P95_MS
		and float(stats.get("worst_frame_ms", 999.0)) <= PHASE1_WORST_MS
		and int(stats.get("spike_frames_gt_100ms", 999)) <= PHASE1_SPIKES
	)

	var run_tag := OS.get_environment("LOW_PROBE_RUN").strip_edges()
	if run_tag.is_empty():
		run_tag = "run1"
	var summary_path := "%s/streaming_low_traversal_%s.md" % [scratch, run_tag]
	_write_summary(summary_path, stats, churn_ok, pacing_ok)
	print(_format_line(stats))
	print("CHURN_GATE=%s (crossed=%d pass=%d lc=%d)" % [
		"PASS" if churn_ok else "FAIL",
		chunks_crossed,
		stream_pass_events,
		lifecycles.size(),
	])
	print("PACING_GATE=%s (p95=%.3f worst=%.3f spikes=%d vs ref %.3f/%.3f/%d)" % [
		"PASS" if pacing_ok else "FAIL",
		float(stats.get("p95_frame_ms", 0.0)),
		float(stats.get("worst_frame_ms", 0.0)),
		int(stats.get("spike_frames_gt_100ms", 0)),
		PHASE1_P95_MS,
		PHASE1_WORST_MS,
		PHASE1_SPIKES,
	])
	print("LOW_TRAVERSAL_SUMMARY=%s" % summary_path)

	if not churn_ok:
		push_error("low traversal probe: insufficient stream churn (crossed=%d pass=%d lc=%d)" % [
			chunks_crossed, stream_pass_events, lifecycles.size(),
		])
		_ProbeExit.finish_tree(self, 1, "streaming low traversal probe FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "streaming low traversal probe OK")


func _count_stream_pass_events() -> int:
	var n := 0
	for ev in _ChunkStreamingTelemetry.get_events():
		if str(ev.get("event", "")) == "stream_pass":
			n += 1
	return n


func _filter_stream_lifecycles(lifecycles: Array) -> Array:
	var out: Array = []
	for lc in lifecycles:
		var trigger := str(lc.get("trigger", ""))
		if trigger in ["stream", "movement"] and int(lc.get("active_us", 0)) > 0:
			out.append(lc)
	return out


static func _format_line(stats: Dictionary) -> String:
	return (
		"LOW_TRAVERSAL preset=%s crossed=%d pass=%d lc=%d frames=%d avg=%.3f p95=%.3f p99=%.3f worst=%.3f 1pct_low_fps=%.1f spikes=%d"
		% [
			str(stats.get("preset", "")),
			int(stats.get("chunks_crossed", 0)),
			int(stats.get("stream_pass_events", 0)),
			int(stats.get("lifecycles_completed", 0)),
			int(stats.get("frames", 0)),
			float(stats.get("avg_frame_ms", 0.0)),
			float(stats.get("p95_frame_ms", 0.0)),
			float(stats.get("p99_frame_ms", 0.0)),
			float(stats.get("worst_frame_ms", 0.0)),
			float(stats.get("fps_1pct_low", 0.0)),
			int(stats.get("spike_frames_gt_100ms", 0)),
		]
	)


static func _write_summary(path: String, stats: Dictionary, churn_ok: bool, pacing_ok: bool) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# LOW preset traversal probe")
	lines.append("")
	lines.append("| Metric | Value |")
	lines.append("|--------|-------|")
	lines.append("| Preset | %s |" % stats.get("preset", ""))
	lines.append("| RENDER_DISTANCE | %d |" % int(stats.get("render_distance", 0)))
	lines.append("| MAX_INFLIGHT | %d |" % int(stats.get("max_inflight", 0)))
	lines.append("| Frames | %d |" % int(stats.get("frames", 0)))
	lines.append("| Chunks crossed | %d |" % int(stats.get("chunks_crossed", 0)))
	lines.append("| Stream pass events | %d |" % int(stats.get("stream_pass_events", 0)))
	lines.append("| Lifecycles completed | %d |" % int(stats.get("lifecycles_completed", 0)))
	lines.append("| Avg frame (ms) | %.3f |" % float(stats.get("avg_frame_ms", 0.0)))
	lines.append("| P95 frame (ms) | %.3f |" % float(stats.get("p95_frame_ms", 0.0)))
	lines.append("| P99 frame (ms) | %.3f |" % float(stats.get("p99_frame_ms", 0.0)))
	lines.append("| Worst frame (ms) | %.3f |" % float(stats.get("worst_frame_ms", 0.0)))
	lines.append("| 1%% low FPS | %.1f |" % float(stats.get("fps_1pct_low", 0.0)))
	lines.append("| Stalls >33ms | %d |" % int(stats.get("stall_frames_gt_33ms", 0)))
	lines.append("| Spikes >100ms | %d |" % int(stats.get("spike_frames_gt_100ms", 0)))
	lines.append("")
	lines.append("| Churn gate | %s |" % ("PASS" if churn_ok else "FAIL"))
	lines.append("| Pacing gate vs Phase1 | %s |" % ("PASS" if pacing_ok else "FAIL"))
	lines.append("")
	lines.append("Phase 1 reference: P95=%.3f worst=%.3f spikes=%d" % [
		PHASE1_P95_MS, PHASE1_WORST_MS, PHASE1_SPIKES,
	])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()


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