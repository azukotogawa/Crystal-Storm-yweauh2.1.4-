extends SceneTree
## Micro-on incremental patch vs micro-off whole-chunk remesh — frozen MicroTerrainPerfGate.


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _MicroTerrainPerfGate = preload("res://helpers/micro_terrain_perf_gate.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainDirtyScope = preload("res://helpers/terrain_dirty_scope.gd")

const CONSECUTIVE_PASS_TARGET := 3
const MAX_GATED_ATTEMPTS := 20
const SAMPLES_PER_WINDOW := 12
const DIG_BATCH_REPS := 10


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-9cfae1423a83/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242

	for i in 3:
		_time_localized_edit_pair(world)

	var pass_results: Array = []
	var samples := _empty_buckets()
	var consecutive := 0
	var attempt := 0
	while consecutive < CONSECUTIVE_PASS_TARGET:
		attempt += 1
		if attempt > MAX_GATED_ATTEMPTS:
			push_error("failed %d consecutive passes after %d attempts" % [CONSECUTIVE_PASS_TARGET, MAX_GATED_ATTEMPTS])
			quit(1)
			return
		var window := _collect_window(world)
		var result := _evaluate_window(window, attempt)
		if bool(result.ok):
			consecutive += 1
			_merge(samples, window)
			pass_results.append(result)
		else:
			consecutive = 0
			pass_results.clear()
			samples = _empty_buckets()

	var agg := _aggregate(samples)
	if agg.micro.macro_skipped < 1.0:
		push_error("micro path must defer at least one macro column per patch")
		quit(1)
		return
	if not _MicroTerrainPerfGate.passes(agg.baseline.patch_ms, agg.micro.patch_ms):
		push_error(
			"micro patch %.3fms must be within gate of whole-chunk baseline %.3fms"
			% [agg.micro.patch_ms, agg.baseline.patch_ms]
		)
		quit(1)
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Micro terrain localized edit perf compare")
	lines.append("")
	lines.append("Gate: incremental_micro_mesh_ms <= whole_chunk_remesh_ms + max(0.15ms, 0.5%% baseline)")
	lines.append("Baseline: micro-off whole-chunk `_build_mesh` (anti-pattern whole-chunk regen)")
	lines.append("Micro-on: localized `_build_mesh_region` patch + inline micro columns")
	lines.append("Timing: column-map refresh outside timer; mesh only inside timer")
	lines.append("")
	lines.append("## localized_edit_mesh_ms")
	lines.append("| mode | median_ms |")
	lines.append("|------|-----------|")
	lines.append("| micro-off whole-chunk remesh | %.3f |" % agg.baseline.patch_ms)
	lines.append("| micro-on incremental patch | %.3f |" % agg.micro.patch_ms)
	lines.append("| reduction | %.1f%% |" % (
		100.0 * (1.0 - agg.micro.patch_ms / maxf(agg.baseline.patch_ms, 0.001))
	))
	lines.append("| macro columns deferred | %.1f |" % agg.micro.macro_skipped)
	lines.append("")
	lines.append("## dirty scope")
	lines.append("| metric | baseline | micro-on |")
	lines.append("|--------|----------|----------|")
	lines.append("| columns_examined | %.1f | %.1f |" % [agg.baseline.examined, agg.micro.examined])
	lines.append("| micro_bricks | 0.0 | %.1f |" % agg.micro.bricks)
	lines.append("")
	for pr in pass_results:
		lines.append("### Window %d" % int(pr.pass))
		for gate in pr.gates:
			lines.append("- %s: **%s** (baseline=%.3f micro=%.3f noise=%.3f)" % [
				gate.name, "PASS" if gate.ok else "FAIL", gate.baseline, gate.micro, gate.noise_ms
			])
		lines.append("")

	_write_text("%s/micro_perf_compare.log" % scratch, "\n".join(lines))

	for gate in [_MicroTerrainPerfGate.evaluate("localized_edit_mesh_ms", agg.baseline.patch_ms, agg.micro.patch_ms)]:
		print("OK perf gate %s baseline=%.3f micro=%.3f delta=%.3f skipped=%.0f" % [
			gate.name, gate.baseline, gate.micro, gate.delta_ms, agg.micro.macro_skipped
		])

	print("All micro terrain perf gates OK (%d consecutive passes)" % CONSECUTIVE_PASS_TARGET)
	quit(0)


func _empty_buckets() -> Dictionary:
	return {
		"baseline_patch": [],
		"micro_patch": [],
		"baseline_examined": [],
		"micro_examined": [],
		"micro_bricks": [],
		"macro_skipped": [],
	}


func _collect_window(world: InfiniteNoiseWorld) -> Dictionary:
	var out := _empty_buckets()
	for _i in SAMPLES_PER_WINDOW:
		var pair := _time_localized_edit_pair(world)
		out.baseline_patch.append(pair[0])
		out.micro_patch.append(pair[1])
		out.baseline_examined.append(pair[2])
		out.micro_examined.append(pair[3])
		out.micro_bricks.append(pair[4])
		out.macro_skipped.append(pair[5])
	return out


func _merge(into: Dictionary, window: Dictionary) -> void:
	for key in window.keys():
		for v in window[key]:
			into[key].append(v)


func _evaluate_window(window: Dictionary, pass_num: int) -> Dictionary:
	var baseline := {
		"patch_ms": _median(window.baseline_patch),
		"examined": _median(window.baseline_examined),
	}
	var micro := {
		"patch_ms": _median(window.micro_patch),
		"examined": _median(window.micro_examined),
		"bricks": _median(window.micro_bricks),
		"macro_skipped": _median(window.macro_skipped),
	}
	var gates := [
		_MicroTerrainPerfGate.evaluate("localized_edit_mesh_ms", baseline.patch_ms, micro.patch_ms),
	]
	var ok := true
	for gate in gates:
		if not bool(gate.ok):
			push_error("perf window %d failed %s baseline=%.3f micro=%.3f" % [
				pass_num, gate.name, gate.baseline, gate.micro
			])
			ok = false
	if micro.examined > baseline.examined + 8.5:
		push_error("perf window %d scope expanded baseline=%.1f micro=%.1f" % [
			pass_num, baseline.examined, micro.examined
		])
		ok = false
	if micro.macro_skipped < 1.0:
		push_error("perf window %d macro_skipped=%.1f" % [pass_num, micro.macro_skipped])
		ok = false
	return {"pass": pass_num, "ok": ok, "gates": gates}


func _aggregate(samples: Dictionary) -> Dictionary:
	return {
		"baseline": {
			"patch_ms": _median(samples.baseline_patch),
			"examined": _median(samples.baseline_examined),
		},
		"micro": {
			"patch_ms": _median(samples.micro_patch),
			"examined": _median(samples.micro_examined),
			"bricks": _median(samples.micro_bricks),
			"macro_skipped": _median(samples.macro_skipped),
		},
	}


func _time_localized_edit_pair(world: InfiniteNoiseWorld) -> Array:
	_TerrainEdits.reset()
	var dirty_local: Array = [Vector2i(8, 8)]
	var patch_rect: Rect2i = _TerrainDirtyScope.mesh_patch_rect(dirty_local)
	var data := _ChunkDataPool.acquire(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	data.prewarm_macro_storage()
	_TerrainEdits.dig(8, 8, 1)
	data.refresh_worker_snapshot_for_cells(dirty_local)
	var baseline_snap := _snapshot(data)

	var cm := _ChunkManager.new()
	var baseline_samples: Array = []
	var micro_samples: Array = []
	var baseline_examined: Array = []
	var micro_examined: Array = []
	var micro_bricks: Array = []
	var macro_skipped: Array = []

	for rep in DIG_BATCH_REPS:
		if (rep % 2) == 0:
			var b := _time_mesh_patch(data, baseline_snap, dirty_local, patch_rect, false, cm)
			baseline_samples.append(b[0])
			baseline_examined.append(b[1])
			var m := _time_mesh_patch(data, baseline_snap, dirty_local, patch_rect, true, cm)
			micro_samples.append(m[0])
			micro_examined.append(m[1])
			micro_bricks.append(m[2])
			macro_skipped.append(m[3])
		else:
			var m2 := _time_mesh_patch(data, baseline_snap, dirty_local, patch_rect, true, cm)
			micro_samples.append(m2[0])
			micro_examined.append(m2[1])
			micro_bricks.append(m2[2])
			macro_skipped.append(m2[3])
			var b2 := _time_mesh_patch(data, baseline_snap, dirty_local, patch_rect, false, cm)
			baseline_samples.append(b2[0])
			baseline_examined.append(b2[1])

	_ChunkDataPool.release(data)
	return [
		_median(baseline_samples),
		_median(micro_samples),
		_median(baseline_examined),
		_median(micro_examined),
		_median(micro_bricks),
		_median(macro_skipped),
	]


func _time_mesh_patch(
	data: ChunkData,
	baseline: Dictionary,
	dirty_local: Array,
	patch_rect: Rect2i,
	micro_on: bool,
	cm: ChunkManager
) -> Array:
	_restore(data, baseline)
	_ChunkData.set_micro_enabled_for_benchmark(micro_on)
	if not data._maps_resident:
		data.ensure_column_maps()
	var examined: int = data.update_dirty_column_maps(dirty_local)
	var skipped: float = 0.0
	var t0 := Time.get_ticks_usec()
	if micro_on:
		skipped = float(data.micro_grid.brick_count() if data.micro_grid else 0)
		cm._build_mesh_region(data, patch_rect, false)
	else:
		cm._build_mesh(data)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var bricks: float = float(data.micro_grid.brick_count() if data.micro_grid else 0)
	return [ms, float(examined), bricks, skipped]


func _snapshot(data: ChunkData) -> Dictionary:
	return {
		"surface_map": _dup2d(data.surface_map),
		"tile_map": _dup2d(data.tile_map),
		"ramp_map": data.ramp_map.duplicate(true),
		"worker_height": _dup2d(data._worker_height_delta),
		"worker_build": _dup2d(data._worker_build_tile),
		"worker_feature": _dup2d(data._worker_feature_tile),
		"halo_surface": _dup2d(data._halo_surface),
		"has_worker_snapshot": data._has_worker_snapshot,
		"has_halo_surface": data._has_halo_surface,
	}


func _restore(data: ChunkData, snap: Dictionary) -> void:
	data._ensure_surface_map_storage()
	_copy2d(data.surface_map, snap.surface_map)
	_copy2d(data.tile_map, snap.tile_map)
	data.ramp_map = snap.ramp_map.duplicate(true)
	_copy2d(data._worker_height_delta, snap.worker_height)
	_copy2d(data._worker_build_tile, snap.worker_build)
	_copy2d(data._worker_feature_tile, snap.worker_feature)
	_copy2d(data._halo_surface, snap.halo_surface)
	data._has_worker_snapshot = bool(snap.has_worker_snapshot)
	data._has_halo_surface = bool(snap.has_halo_surface)
	data._maps_resident = data.surface_map.size() == _ChunkData.SIZE
	if data.micro_grid:
		data.micro_grid.prepare_for_reuse()
	data.last_micro_examined = 0


func _dup2d(src: Array) -> Array:
	var out: Array = []
	for row in src:
		out.append(row.duplicate() if row is Array else row)
	return out


func _copy2d(dst: Array, src: Array) -> void:
	for x in mini(dst.size(), src.size()):
		if dst[x] is Array and src[x] is Array:
			for z in mini(dst[x].size(), src[x].size()):
				dst[x][z] = src[x][z]


func _median(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: Array = samples.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _write_text(path: String, body: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(body)
		f.close()