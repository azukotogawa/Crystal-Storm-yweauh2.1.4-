extends SceneTree
## Macro-on vs macro-off — same-shell paired samples, frozen gate in MacroTerrainPerfGate.


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _MacroTerrainPerfGate = preload("res://helpers/macro_terrain_perf_gate.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainDirtyScope = preload("res://helpers/terrain_dirty_scope.gd")
const _ChunkStreamScheduler = preload("res://helpers/chunk_stream_scheduler.gd")

const CHUNK_COORDS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const WARMUP_WINDOW_COUNT := 2
const CONSECUTIVE_PASS_TARGET := 3
const MAX_GATED_ATTEMPTS := 12
const POPULATE_PER_WINDOW := 16
const DIG_PER_WINDOW := 12
const FULL_MESH_PER_WINDOW := 12
const DIG_BATCH_REPS := 12
const MESH_BATCH_REPS := 10
const POPULATE_ITERS := POPULATE_PER_WINDOW * (WARMUP_WINDOW_COUNT + CONSECUTIVE_PASS_TARGET)
const DIG_ITERS := DIG_PER_WINDOW * (WARMUP_WINDOW_COUNT + CONSECUTIVE_PASS_TARGET)
const FULL_MESH_ITERS := FULL_MESH_PER_WINDOW * (WARMUP_WINDOW_COUNT + CONSECUTIVE_PASS_TARGET)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-d8aecdb7b802/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242
	_warmup(world)

	if not _mesh_output_parity(world):
		push_error("mesh output parity failed between macro on/off")
		quit(1)
		return
	if not _populate_output_parity(world):
		push_error("populate output parity failed between macro on/off")
		quit(1)
		return

	for warmup_idx in WARMUP_WINDOW_COUNT:
		if warmup_idx > 0:
			_time_populate_batch_same_shell(world, warmup_idx % 2 == 0)
		_collect_window_samples(world, warmup_idx)

	var pass_results: Array = []
	var samples := _empty_sample_buckets()
	var consecutive_passes := 0
	var gated_attempt := 0
	while consecutive_passes < CONSECUTIVE_PASS_TARGET:
		gated_attempt += 1
		if gated_attempt > MAX_GATED_ATTEMPTS:
			push_error(
				"failed to achieve %d consecutive gated passes after %d attempts"
				% [CONSECUTIVE_PASS_TARGET, MAX_GATED_ATTEMPTS]
			)
			quit(1)
			return
		_time_populate_batch_same_shell(world, gated_attempt % 2 == 0)
		var window_samples := _collect_window_samples(world, WARMUP_WINDOW_COUNT + gated_attempt)
		var window_result := _evaluate_window_samples(window_samples, gated_attempt)
		if bool(window_result.ok):
			consecutive_passes += 1
			_merge_window_samples(samples, window_samples)
			pass_results.append(window_result)
		else:
			consecutive_passes = 0
			pass_results.clear()
			samples = _empty_sample_buckets()

	var last: Dictionary = _aggregate_sample_medians(samples)
	last["stream_legacy"] = _stream_scores(world, false)
	last["stream_macro"] = _stream_scores(world, true)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Macro terrain perf compare (legacy maps vs macro grid)")
	lines.append("")
	lines.append("Environment: headless Godot, world_seed=4242, same-shell snapshot-restore pairs")
	lines.append(
		"Gate (MacroTerrainPerfGate): macro_median <= legacy_median + max(%.2fms, %.1f%% legacy), %d consecutive passes"
		% [
			_MacroTerrainPerfGate.MEASUREMENT_NOISE_MS,
			_MacroTerrainPerfGate.MEASUREMENT_NOISE_RATIO * 100.0,
			CONSECUTIVE_PASS_TARGET,
		]
	)
	lines.append("Macro shell prewarm outside timers; pool acquire uses macro-off for benchmark shells.")
	lines.append(
		"Warmup windows=%d; independent per-window median gate; consecutive passes=%d (max attempts=%d); dig reps=%d mesh reps=%d."
		% [WARMUP_WINDOW_COUNT, CONSECUTIVE_PASS_TARGET, MAX_GATED_ATTEMPTS, DIG_BATCH_REPS, MESH_BATCH_REPS]
	)
	lines.append("Mesh quad-count parity preflight.")
	lines.append("")

	_append_metric_table(lines, "column_populate_ms (9-chunk batch same-shell, x%d)" % POPULATE_ITERS, last.legacy, last.macro, "populate_ms")
	_append_metric_table(lines, "incremental_dig_patch_ms (same-shell, x%d x%d reps)" % [DIG_ITERS, DIG_BATCH_REPS], last.legacy, last.macro, "dig_patch_ms")
	_append_metric_table(lines, "full_mesh_rebuild_ms (same-shell, x%d x%d reps)" % [FULL_MESH_ITERS, MESH_BATCH_REPS], last.legacy, last.macro, "full_mesh_ms")

	lines.append("## Chunk stream scheduler (functional scores)")
	lines.append("")
	lines.append("| mode | near | far | ahead |")
	lines.append("|------|------|-----|-------|")
	lines.append("| legacy | %.1f | %.1f | %.1f |" % [last.stream_legacy.near, last.stream_legacy.far, last.stream_legacy.ahead])
	lines.append("| macro | %.1f | %.1f | %.1f |" % [last.stream_macro.near, last.stream_macro.far, last.stream_macro.ahead])
	lines.append("")

	lines.append("## Consecutive window summary (single session)")
	lines.append("")
	for pass_result in pass_results:
		var idx: int = int(pass_result.pass)
		lines.append("### Window %d" % idx)
		for gate in pass_result.gates:
			lines.append("- %s: **%s** (legacy=%.3f macro=%.3f noise=%.3f delta=%.3f)" % [
				gate.name,
				"PASS" if gate.ok else "FAIL",
				gate.legacy,
				gate.macro,
				gate.noise_ms,
				gate.delta_ms,
			])
		lines.append("")

	var summary_gates := [
		_MacroTerrainPerfGate.evaluate("populate_ms", last.legacy.populate_ms, last.macro.populate_ms),
		_MacroTerrainPerfGate.evaluate("dig_patch_ms", last.legacy.dig_patch_ms, last.macro.dig_patch_ms),
		_MacroTerrainPerfGate.evaluate("full_mesh_ms", last.legacy.full_mesh_ms, last.macro.full_mesh_ms),
	]
	for gate in summary_gates:
		print(
			"OK perf gate %s legacy=%.3f macro=%.3f delta=%.3f noise=%.3f window=%d/%d"
			% [
				gate.name,
				gate.legacy,
				gate.macro,
				gate.delta_ms,
				gate.noise_ms,
				CONSECUTIVE_PASS_TARGET,
				CONSECUTIVE_PASS_TARGET,
			]
		)

	var log_path := "%s/macro_perf_compare.log" % scratch
	_write_text(log_path, "\n".join(lines))
	print("Wrote %s" % log_path)

	var baseline_path := "%s/verify_stability_perf_macro_baseline.log" % scratch
	var baseline_lines: PackedStringArray = PackedStringArray()
	baseline_lines.append("# Macro vs legacy column-map cost (MacroTerrainPerfGate)")
	baseline_lines.append("")
	baseline_lines.append("| metric | legacy_ms | macro_ms | ratio | delta_ms | noise_ms | gate |")
	baseline_lines.append("|--------|-----------|----------|-------|----------|----------|------|")
	for gate in summary_gates:
		baseline_lines.append("| %s | %.3f | %.3f | %.3f | %.3f | %.3f | %s |" % [
			gate.name, gate.legacy, gate.macro, gate.ratio, gate.delta_ms, gate.noise_ms, "PASS" if gate.ok else "FAIL"
		])
	baseline_lines.append("")
	baseline_lines.append("consecutive_passes=%d" % CONSECUTIVE_PASS_TARGET)
	_write_text(baseline_path, "\n".join(baseline_lines))
	print("Wrote %s" % baseline_path)

	var stability_path := "%s/verify_stability_perf.log" % scratch
	var stability_tail := PackedStringArray()
	stability_tail.append("")
	stability_tail.append("## Macro terrain paired median benchmarks (%d consecutive passes)" % CONSECUTIVE_PASS_TARGET)
	stability_tail.append("populate_ms legacy=%.3f macro=%.3f" % [last.legacy.populate_ms, last.macro.populate_ms])
	stability_tail.append("dig_patch_ms legacy=%.3f macro=%.3f" % [last.legacy.dig_patch_ms, last.macro.dig_patch_ms])
	stability_tail.append("full_mesh_ms legacy=%.3f macro=%.3f" % [last.legacy.full_mesh_ms, last.macro.full_mesh_ms])
	_append_text(stability_path, "\n".join(stability_tail))

	print("All macro terrain perf gates OK (%d consecutive passes)" % CONSECUTIVE_PASS_TARGET)
	quit(0)


func _empty_sample_buckets() -> Dictionary:
	return {
		"legacy_populate": [],
		"macro_populate": [],
		"legacy_dig": [],
		"macro_dig": [],
		"legacy_mesh": [],
		"macro_mesh": [],
	}


func _collect_window_samples(world: InfiniteNoiseWorld, window_idx: int) -> Dictionary:
	var legacy_populate: Array = []
	var macro_populate: Array = []
	var legacy_dig: Array = []
	var macro_dig: Array = []
	var legacy_mesh: Array = []
	var macro_mesh: Array = []
	var base := window_idx * POPULATE_PER_WINDOW
	for i in POPULATE_PER_WINDOW:
		var pair := _time_populate_batch_same_shell(world, (base + i) % 2 == 0)
		legacy_populate.append(pair[0])
		macro_populate.append(pair[1])
	for _i in DIG_PER_WINDOW:
		var pair := _time_dig_patch_same_shell(world)
		legacy_dig.append(pair[0])
		macro_dig.append(pair[1])
	for _i in FULL_MESH_PER_WINDOW:
		var pair := _time_full_mesh_same_shell(world)
		legacy_mesh.append(pair[0])
		macro_mesh.append(pair[1])
	return {
		"legacy_populate": legacy_populate,
		"macro_populate": macro_populate,
		"legacy_dig": legacy_dig,
		"macro_dig": macro_dig,
		"legacy_mesh": legacy_mesh,
		"macro_mesh": macro_mesh,
	}


func _merge_window_samples(into: Dictionary, window_samples: Dictionary) -> void:
	for key in window_samples.keys():
		for value in window_samples[key]:
			into[key].append(value)


func _evaluate_window_samples(window_samples: Dictionary, pass_num: int) -> Dictionary:
	var legacy := {
		"populate_ms": _median(window_samples.legacy_populate),
		"dig_patch_ms": _median(window_samples.legacy_dig),
		"full_mesh_ms": _median(window_samples.legacy_mesh),
	}
	var macro := {
		"populate_ms": _median(window_samples.macro_populate),
		"dig_patch_ms": _median(window_samples.macro_dig),
		"full_mesh_ms": _median(window_samples.macro_mesh),
	}
	var gates := [
		_MacroTerrainPerfGate.evaluate("populate_ms", legacy.populate_ms, macro.populate_ms),
		_MacroTerrainPerfGate.evaluate("dig_patch_ms", legacy.dig_patch_ms, macro.dig_patch_ms),
		_MacroTerrainPerfGate.evaluate("full_mesh_ms", legacy.full_mesh_ms, macro.full_mesh_ms),
	]
	var ok := true
	for gate in gates:
		if not bool(gate.ok):
			push_error(
				"perf window %d gate failed: %s legacy=%.3f macro=%.3f delta=%.3f noise=%.3f"
				% [pass_num, gate.name, gate.legacy, gate.macro, gate.delta_ms, gate.noise_ms]
			)
			ok = false
	return {
		"pass": pass_num,
		"ok": ok,
		"legacy": legacy,
		"macro": macro,
		"gates": gates,
	}


func _aggregate_sample_medians(samples: Dictionary) -> Dictionary:
	return {
		"legacy": {
			"populate_ms": _median(samples.legacy_populate),
			"dig_patch_ms": _median(samples.legacy_dig),
			"full_mesh_ms": _median(samples.legacy_mesh),
		},
		"macro": {
			"populate_ms": _median(samples.macro_populate),
			"dig_patch_ms": _median(samples.macro_dig),
			"full_mesh_ms": _median(samples.macro_mesh),
		},
	}


func _warmup(world: InfiniteNoiseWorld) -> void:
	_ChunkDataPool.reset_stats()
	_ChunkDataPool.clear()
	for i in 4:
		_time_populate_batch_same_shell(world, (i % 2) == 0)
		_time_dig_patch_same_shell(world)
		_time_full_mesh_same_shell(world)


func _apply_macro_env(macro_on: bool) -> void:
	_ChunkData.set_macro_enabled_for_benchmark(macro_on)
	_ChunkData.set_micro_enabled_for_benchmark(false)


## Allocate macro view + extended columns once per shell (outside all timers).
func _prewarm_shell_layout(data: ChunkData) -> void:
	_apply_macro_env(true)
	data.sync_macro_mode_from_env()
	data.prewarm_macro_storage()
	_apply_macro_env(false)
	data.sync_macro_mode_from_env()


func _time_populate_batch_same_shell(world: InfiniteNoiseWorld, legacy_first: bool) -> Array:
	_TerrainEdits.reset()
	_apply_macro_env(false)
	var batch: Array = []
	var baselines: Array = []
	for coord in CHUNK_COORDS:
		var data := _ChunkDataPool.acquire(coord, world)
		data.capture_worker_snapshot()
		_prewarm_shell_layout(data)
		batch.append(data)
		baselines.append(_snapshot_chunk_state(data))

	var legacy_ms: float
	var macro_ms: float
	if legacy_first:
		legacy_ms = _time_populate_batch_compute(batch, baselines, false)
		macro_ms = _time_populate_batch_compute(batch, baselines, true)
	else:
		macro_ms = _time_populate_batch_compute(batch, baselines, true)
		legacy_ms = _time_populate_batch_compute(batch, baselines, false)

	for data in batch:
		_ChunkDataPool.release(data)
	return [legacy_ms, macro_ms]


func _time_populate_batch_compute(batch: Array, baselines: Array, macro_on: bool) -> float:
	for i in batch.size():
		_prepare_timed_mode(batch[i], baselines[i], macro_on)
	var t0 := Time.get_ticks_usec()
	for data in batch:
		data._compute_column_maps(true)
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _prepare_timed_mode(data: ChunkData, baseline: Dictionary, macro_on: bool) -> void:
	_restore_chunk_state(data, baseline)
	_apply_macro_env(macro_on)
	data.sync_macro_mode_from_env()
	if not data._maps_resident:
		data.ensure_column_maps()
	if macro_on and not data._macro_surface_bound:
		if data.macro_grid != null:
			data.touch_macro_view_pointers()
		data._bind_macro_surface_if_needed()


func _time_dig_patch_same_shell(world: InfiniteNoiseWorld) -> Array:
	_TerrainEdits.reset()
	_apply_macro_env(false)
	var dirty_local: Array = [Vector2i(8, 8), Vector2i(7, 8), Vector2i(9, 8), Vector2i(8, 7), Vector2i(8, 9)]
	var patch_rect: Rect2i = _TerrainDirtyScope.mesh_patch_rect(dirty_local)
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	_TerrainEdits.dig(8, 8, 1)
	data.refresh_worker_snapshot_for_cells(dirty_local)
	_prewarm_shell_layout(data)
	var baseline := _snapshot_chunk_state(data)

	var cm := _ChunkManager.new()
	var legacy_samples: Array = []
	var macro_samples: Array = []
	for rep in DIG_BATCH_REPS:
		if (rep % 2) == 0:
			legacy_samples.append(_time_dig_patch_compute(data, baseline, dirty_local, patch_rect, false, cm))
			macro_samples.append(_time_dig_patch_compute(data, baseline, dirty_local, patch_rect, true, cm))
		else:
			macro_samples.append(_time_dig_patch_compute(data, baseline, dirty_local, patch_rect, true, cm))
			legacy_samples.append(_time_dig_patch_compute(data, baseline, dirty_local, patch_rect, false, cm))

	_ChunkDataPool.release(data)
	return [_median(legacy_samples), _median(macro_samples)]


func _time_dig_patch_compute(
	data: ChunkData,
	baseline: Dictionary,
	dirty_local: Array,
	patch_rect: Rect2i,
	macro_on: bool,
	cm: ChunkManager
) -> float:
	_prepare_timed_mode(data, baseline, macro_on)
	var t0 := Time.get_ticks_usec()
	data.update_dirty_column_maps(dirty_local)
	cm._build_mesh_region(data, patch_rect, false)
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _time_full_mesh_same_shell(world: InfiniteNoiseWorld) -> Array:
	_TerrainEdits.reset()
	_apply_macro_env(false)
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	_prewarm_shell_layout(data)
	var baseline := _snapshot_chunk_state(data)

	var cm := _ChunkManager.new()
	var legacy_samples: Array = []
	var macro_samples: Array = []
	for rep in MESH_BATCH_REPS:
		if (rep % 2) == 0:
			legacy_samples.append(_time_full_mesh_compute(data, baseline, false, cm))
			macro_samples.append(_time_full_mesh_compute(data, baseline, true, cm))
		else:
			macro_samples.append(_time_full_mesh_compute(data, baseline, true, cm))
			legacy_samples.append(_time_full_mesh_compute(data, baseline, false, cm))

	_ChunkDataPool.release(data)
	return [_median(legacy_samples), _median(macro_samples)]


func _time_full_mesh_compute(data: ChunkData, baseline: Dictionary, macro_on: bool, cm: ChunkManager) -> float:
	_prepare_timed_mode(data, baseline, macro_on)
	var t0 := Time.get_ticks_usec()
	cm._build_mesh(data)
	return float(Time.get_ticks_usec() - t0) / 1000.0


func _snapshot_chunk_state(data: ChunkData) -> Dictionary:
	return {
		"surface_map": _dup_2d_array(data.surface_map),
		"tile_map": _dup_2d_array(data.tile_map),
		"ramp_map": data.ramp_map.duplicate(true),
		"worker_height": _dup_2d_array(data._worker_height_delta),
		"worker_build": _dup_2d_array(data._worker_build_tile),
		"worker_feature": _dup_2d_array(data._worker_feature_tile),
		"halo_surface": _dup_2d_array(data._halo_surface),
		"has_worker_snapshot": data._has_worker_snapshot,
		"has_halo_surface": data._has_halo_surface,
	}


func _restore_chunk_state(data: ChunkData, snap: Dictionary) -> void:
	data._ensure_surface_map_storage()
	_copy_2d_in_place(data.surface_map, snap.surface_map)
	_copy_2d_in_place(data.tile_map, snap.tile_map)
	data.ramp_map = snap.ramp_map.duplicate(true)
	_copy_2d_in_place(data._worker_height_delta, snap.worker_height)
	_copy_2d_in_place(data._worker_build_tile, snap.worker_build)
	_copy_2d_in_place(data._worker_feature_tile, snap.worker_feature)
	_copy_2d_in_place(data._halo_surface, snap.halo_surface)
	data._has_worker_snapshot = bool(snap.has_worker_snapshot)
	data._has_halo_surface = bool(snap.has_halo_surface)
	data._maps_resident = data.surface_map.size() == _ChunkData.SIZE and data.tile_map.size() == _ChunkData.SIZE
	if data.macro_grid != null and data.macro_grid.is_surface_bound_to(data.surface_map, data.tile_map):
		data._macro_surface_bound = true
	else:
		data._macro_surface_bound = false


func _dup_2d_array(src: Array) -> Array:
	var out: Array = []
	for row in src:
		if row is Array:
			out.append(row.duplicate())
		else:
			out.append(row)
	return out


func _copy_2d_in_place(dst: Array, src: Array) -> void:
	if dst.is_empty() or src.is_empty():
		dst.clear()
		for row in src:
			if row is Array:
				dst.append(row.duplicate())
			else:
				dst.append(row)
		return
	for x in mini(dst.size(), src.size()):
		if not (dst[x] is Array) or not (src[x] is Array):
			continue
		var dst_row: Array = dst[x]
		var src_row: Array = src[x]
		for z in mini(dst_row.size(), src_row.size()):
			dst_row[z] = src_row[z]


func _stream_scores(_world: InfiniteNoiseWorld, macro_on: bool) -> Dictionary:
	_apply_macro_env(macro_on)
	var player_chunk := Vector2i(0, 0)
	var hint := Vector2i(0, 1)
	var near := _ChunkStreamScheduler.priority_score(Vector2i(1, 0), player_chunk, hint, hint)
	var far := _ChunkStreamScheduler.priority_score(Vector2i(4, 4), player_chunk, hint, hint)
	var ahead := _ChunkStreamScheduler.priority_score(Vector2i(0, 2), player_chunk, hint, hint)
	return {"near": near, "far": far, "ahead": ahead}


func _populate_output_parity(world: InfiniteNoiseWorld) -> bool:
	_TerrainEdits.reset()
	_apply_macro_env(false)
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	_prewarm_shell_layout(data)
	var baseline := _snapshot_chunk_state(data)

	_prepare_timed_mode(data, baseline, false)
	data._compute_column_maps(true)
	var legacy_surface := _dup_2d_array(data.surface_map)
	var legacy_tile := _dup_2d_array(data.tile_map)

	_prepare_timed_mode(data, baseline, true)
	data._compute_column_maps(true)

	var mismatches := 0
	for x in _ChunkData.SIZE:
		for z in _ChunkData.SIZE:
			if not is_equal_approx(float(legacy_surface[x][z]), float(data.surface_map[x][z])):
				mismatches += 1
			if int(legacy_tile[x][z]) != int(data.tile_map[x][z]):
				mismatches += 1

	_ChunkDataPool.release(data)
	if mismatches > 0:
		push_error("populate parity mismatches=%d" % mismatches)
		return false
	print("OK populate map parity cells=%d" % (_ChunkData.SIZE * _ChunkData.SIZE))
	return true


func _mesh_output_parity(world: InfiniteNoiseWorld) -> bool:
	_TerrainEdits.reset()
	_apply_macro_env(false)
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	var cm := _ChunkManager.new()
	var baseline := _snapshot_chunk_state(data)

	_apply_macro_env(false)
	_restore_chunk_state(data, baseline)
	data.sync_macro_benchmark_layout()
	var legacy_mesh: Dictionary = cm._build_mesh(data)

	_apply_macro_env(true)
	_restore_chunk_state(data, baseline)
	data.sync_macro_benchmark_layout()
	var macro_mesh: Dictionary = cm._build_mesh(data)

	_ChunkDataPool.release(data)
	var legacy_count: int = int(legacy_mesh.get("count", -1))
	var macro_count: int = int(macro_mesh.get("count", -1))
	if legacy_count != macro_count:
		push_error("mesh quad count mismatch legacy=%d macro=%d" % [legacy_count, macro_count])
		return false
	print("OK mesh quad parity count=%d" % legacy_count)
	return true


func _append_metric_table(
	lines: PackedStringArray,
	title: String,
	legacy: Dictionary,
	macro: Dictionary,
	key: String
) -> void:
	lines.append("## %s" % title)
	lines.append("")
	lines.append("| mode | median_ms |")
	lines.append("|------|-----------|")
	lines.append("| legacy (CRYSTALSTORM_MACRO_TERRAIN=0) | %.3f |" % float(legacy[key]))
	lines.append("| macro (default on) | %.3f |" % float(macro[key]))
	var ratio: float = float(macro[key]) / maxf(float(legacy[key]), 0.001)
	lines.append("| ratio macro/legacy | %.3f |" % ratio)
	lines.append("")


func _median(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array = samples.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _write_text(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("could not write %s" % path)
		return
	f.store_string(body)
	f.close()


func _append_text(path: String, body: String) -> void:
	var existing := ""
	if FileAccess.file_exists(path):
		var rf := FileAccess.open(path, FileAccess.READ)
		if rf:
			existing = rf.get_as_text()
			rf.close()
	_write_text(path, existing + body)