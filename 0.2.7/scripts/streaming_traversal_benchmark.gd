extends SceneTree
## Canonical churn-gated streaming traversal benchmark (Epic 2 criterion 2 / plan step 3).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkStreamingTelemetry = preload("res://systems/chunk_streaming_telemetry.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")

const WALK_SECONDS := 20.0
const MIN_CHUNKS_CROSSED := 2
const MIN_STREAM_PASS := 3
const MIN_LIFECYCLES := 20

const PHASE1_P95_MS := 15.661
const PHASE1_WORST_MS := 200.590
const PHASE1_SPIKES := 18


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

	var preset := OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().to_lower()
	var run_tag := OS.get_environment("BENCHMARK_RUN").strip_edges()
	if run_tag.is_empty():
		run_tag = "1"

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "streaming traversal benchmark FAILED")
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
		_ProbeExit.finish_tree(self, 1, "streaming traversal benchmark FAILED")
		return

	if not _verify_perf_preset(chunk_manager, preset):
		_ProbeExit.finish_tree(self, 1, "streaming traversal benchmark FAILED")
		return

	for _w in 45:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	_ChunkStreamingTelemetry.reset()
	_ChunkDataPool.reset_stats()
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context("movement", {})
	_ChunkStreamingTelemetry.set_scenario("traversal_benchmark")

	var start_chunk := chunk_manager.get_player_chunk_coord()
	var frame_times: Array[float] = []
	var stream_pass_before := _count_stream_pass_events()

	Input.action_press("ui_right")
	var end_ms := Time.get_ticks_msec() + int(WALK_SECONDS * 1000.0)
	var frames := 0
	while Time.get_ticks_msec() < end_ms:
		await process_frame
		frames += 1
		if profiler and profiler.has_method("get_snapshot"):
			var snap: Dictionary = profiler.get_snapshot()
			frame_times.append(float(snap.get("frame_ms", 0.0)))
	Input.action_release("ui_right")

	for _idle in 90:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	var end_chunk := chunk_manager.get_player_chunk_coord()
	var chunks_crossed := absi(end_chunk.x - start_chunk.x) + absi(end_chunk.y - start_chunk.y)
	var stream_pass_events := _count_stream_pass_events() - stream_pass_before
	var lifecycles := _filter_stream_lifecycles(_ChunkStreamingTelemetry.get_lifecycle_summaries())
	var pool_stats := _ChunkDataPool.get_stats()

	var stats := {
		"preset": preset,
		"run": run_tag,
		"render_distance": chunk_manager.RENDER_DISTANCE,
		"max_inflight": chunk_manager.MAX_INFLIGHT_CHUNKS,
		"frames": frames,
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
		"stall_frames_gt_33ms": _count_gt(frame_times, 33.0),
		"spike_frames_gt_100ms": _count_gt(frame_times, 100.0),
		"pool_alloc_new": int(pool_stats.get("alloc_new", 0)),
		"pool_alloc_reuse": int(pool_stats.get("alloc_reuse", 0)),
		"activation_avg_ms": _mean_activation_ms(lifecycles),
	}

	var churn_ok := (
		chunks_crossed >= MIN_CHUNKS_CROSSED
		and stream_pass_events >= MIN_STREAM_PASS
		and lifecycles.size() >= MIN_LIFECYCLES
	)
	var pacing_ok := (
		float(stats.get("p95_frame_ms", 999.0)) <= PHASE1_P95_MS
		and float(stats.get("worst_frame_ms", 999.0)) <= PHASE1_WORST_MS
		and int(stats.get("spike_frames_gt_100ms", 999)) <= PHASE1_SPIKES
	)

	var md_path := "%s/streaming_traversal_benchmark_%s_run%s.md" % [scratch, preset, run_tag]
	var jsonl_path := "%s/streaming_traversal_benchmark_%s_run%s.jsonl" % [scratch, preset, run_tag]
	_write_markdown(md_path, stats, churn_ok, pacing_ok)
	_ChunkStreamingTelemetry.write_jsonl(jsonl_path)

	print(_summary_line(stats))
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
	print("BENCHMARK_MD=%s" % md_path)
	print("BENCHMARK_JSONL=%s" % jsonl_path)

	if not churn_ok:
		_ProbeExit.finish_tree(self, 1, "streaming traversal benchmark FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "streaming traversal benchmark OK")


func _verify_perf_preset(chunk_manager: ChunkManager, preset: String) -> bool:
	var expected_dist := 2
	var expected_inflight := 2
	if preset in ["low", "0"]:
		expected_dist = 1
		expected_inflight = 2
	elif preset in ["high", "2"]:
		expected_dist = 3
		expected_inflight = 6
	print(
		"BENCHMARK_PRESET_ENV=%s RENDER_DISTANCE=%d MAX_INFLIGHT=%d expect dist=%d inflight=%d"
		% [preset, chunk_manager.RENDER_DISTANCE, chunk_manager.MAX_INFLIGHT_CHUNKS, expected_dist, expected_inflight]
	)
	if int(chunk_manager.RENDER_DISTANCE) != expected_dist or int(chunk_manager.MAX_INFLIGHT_CHUNKS) != expected_inflight:
		push_error("benchmark: perf preset mismatch")
		return false
	return true


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


func _mean_activation_ms(lifecycles: Array) -> float:
	var vals: Array[float] = []
	for lc in lifecycles:
		var v := float(lc.get("activation_latency_ms", 0.0))
		if v > 0.0:
			vals.append(v)
	return _mean(vals)


func _summary_line(stats: Dictionary) -> String:
	return (
		"BENCHMARK preset=%s run=%s crossed=%d pass=%d lc=%d avg=%.3f p95=%.3f worst=%.3f spikes=%d pool_reuse=%d"
		% [
			str(stats.get("preset", "")),
			str(stats.get("run", "")),
			int(stats.get("chunks_crossed", 0)),
			int(stats.get("stream_pass_events", 0)),
			int(stats.get("lifecycles_completed", 0)),
			float(stats.get("avg_frame_ms", 0.0)),
			float(stats.get("p95_frame_ms", 0.0)),
			float(stats.get("worst_frame_ms", 0.0)),
			int(stats.get("spike_frames_gt_100ms", 0)),
			int(stats.get("pool_alloc_reuse", 0)),
		]
	)


func _write_markdown(path: String, stats: Dictionary, churn_ok: bool, pacing_ok: bool) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Streaming traversal benchmark")
	lines.append("")
	lines.append("| Metric | Value |")
	lines.append("|--------|-------|")
	for key in [
		"preset", "run", "render_distance", "max_inflight", "frames",
		"chunks_crossed", "stream_pass_events", "lifecycles_completed",
		"avg_frame_ms", "p95_frame_ms", "p99_frame_ms", "worst_frame_ms",
		"fps_1pct_low", "stall_frames_gt_33ms", "spike_frames_gt_100ms",
		"pool_alloc_new", "pool_alloc_reuse", "activation_avg_ms",
	]:
		lines.append("| %s | %s |" % [key, str(stats.get(key, ""))])
	lines.append("")
	lines.append("| churn_gate | %s |" % ("PASS" if churn_ok else "FAIL"))
	lines.append("| pacing_gate vs Phase1 | %s |" % ("PASS" if pacing_ok else "FAIL"))
	lines.append("")
	lines.append("Phase 1 reference (investigation sustained_movement, 88 lifecycles): P95=%.3f worst=%.3f spikes=%d" % [
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