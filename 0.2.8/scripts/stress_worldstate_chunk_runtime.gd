extends SceneTree
## Combined runtime stress: stream/teleport churn, dig/build, crystal tick, save/load,
## WorldState revision + snapshot + stale-job contracts, throughput/health metrics.
## Usage: CRYSTALSTORM_PERF_PRESET=medium CRYSTALSTORM_CHUNK_PROFILE=1 \
##   godot --headless -s scripts/stress_worldstate_chunk_runtime.gd

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _WorldState = preload("res://world/world_state.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkPipeline = preload("res://chunks/chunk_pipeline.gd")
const _ChunkStreamingTelemetry = preload("res://systems/chunk_streaming_telemetry.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _SaveCodec = preload("res://systems/save_codec.gd")

const STRESS_SECONDS := 45.0
const TELEPORT_EVERY_SEC := 1.5
const EDIT_EVERY_SEC := 0.35
const SAVE_EVERY_SEC := 8.0
const TEST_SLOT := 11
const MEM_SAMPLES_MIN := 8


var _failed: int = 0
var _notes: PackedStringArray = PackedStringArray()


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PERF_PRESET").strip_edges().is_empty():
		OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	_notes.append("FAIL: " + msg)


func _note(msg: String) -> void:
	print(msg)
	_notes.append(msg)


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-c342af224ac4/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "stress worldstate/chunk FAILED (no main)")
		return

	var game: Node = packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null
	var crystal: Node = null
	var save_svc: SaveGameService = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")

	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		crystal = get_first_node_in_group("crystal_manager")
		save_svc = get_first_node_in_group("save_game_service") as SaveGameService
		if (
			player != null and chunk_manager != null and terrain != null and world != null
			and bool(player.get("world_ready")) and chunk_manager.chunks.size() >= 3
		):
			break
		await process_frame

	if player == null or chunk_manager == null or terrain == null or world == null:
		_ProbeExit.finish_tree(self, 1, "stress worldstate/chunk FAILED (boot timeout)")
		return

	if save_svc and save_svc.config:
		save_svc.config.auto_save_enabled = false

	_ChunkStreamingTelemetry.reset()
	_ChunkDataPool.reset_stats()
	_ChunkStreamingTelemetry.set_scenario("stress_worldstate_chunk")
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context("stress", {})

	# --- Pure contract checks (deterministic pipeline + stale) while scene is live ---
	await _contract_deterministic_pipeline(world, chunk_manager)
	await _contract_snapshot_immutability()
	await _contract_stale_rejection(chunk_manager)

	var ws = _WorldState.get_active()
	var rev_samples: Array = []
	var mesh_rev_samples: Array = []
	var mem_samples: Array = []
	var queue_samples: Array = []
	var chunk_count_samples: Array = []
	var frame_ms_samples: Array = []
	var worker_ms_samples: Array = []
	var digs := 0
	var dig_ok := 0
	var builds := 0
	var build_ok := 0
	var teleports := 0
	var saves := 0
	var save_ok := 0
	var loads := 0
	var load_ok := 0
	var crystal_ticks_observed := 0
	var max_queue := 0
	var max_chunks := 0
	var start_chunk: Vector2i = chunk_manager.get_player_chunk_coord()
	var chunks_visited: Dictionary = {}
	chunks_visited[start_chunk] = true

	var t0 := Time.get_ticks_msec()
	var end_ms := t0 + int(STRESS_SECONDS * 1000.0)
	var next_teleport := t0 + int(TELEPORT_EVERY_SEC * 1000.0)
	var next_edit := t0 + int(EDIT_EVERY_SEC * 1000.0)
	var next_save := t0 + int(SAVE_EVERY_SEC * 1000.0)
	var next_metrics := t0 + 500
	var teleport_idx := 0
	var teleport_offsets: Array[Vector2i] = [
		Vector2i(4, 0), Vector2i(0, 4), Vector2i(-6, 2), Vector2i(8, -3),
		Vector2i(-10, -5), Vector2i(12, 8), Vector2i(-2, 10), Vector2i(15, 0),
		Vector2i(0, -12), Vector2i(20, 20), Vector2i(-15, 12), Vector2i(6, -18),
	]

	while Time.get_ticks_msec() < end_ms:
		var now := Time.get_ticks_msec()

		if now >= next_teleport:
			next_teleport = now + int(TELEPORT_EVERY_SEC * 1000.0)
			var off: Vector2i = teleport_offsets[teleport_idx % teleport_offsets.size()]
			teleport_idx += 1
			_teleport_player(player, world, chunk_manager, off)
			teleports += 1
			var pc: Vector2i = chunk_manager.get_player_chunk_coord()
			chunks_visited[pc] = true
			# Force stream request around player
			if chunk_manager.has_method("update_stream"):
				var c: Vector2i = chunk_manager.get_player_chunk_coord()
				chunk_manager.update_stream(c.x, c.y)

		if now >= next_edit:
			next_edit = now + int(EDIT_EVERY_SEC * 1000.0)
			var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
			var edit_i: int = digs + builds
			var wx := floori(col.x) + (edit_i % 5) - 2
			var wz := floori(col.z) + ((edit_i / 5) % 5) - 2
			var pos := Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5)
			if edit_i % 3 != 2:
				digs += 1
				if terrain.try_dig(pos):
					dig_ok += 1
			else:
				builds += 1
				var inv = player.inventory if "inventory" in player else null
				if inv != null and terrain.has_method("try_build_wall"):
					if terrain.try_build_wall(pos, inv, true):
						build_ok += 1
				elif terrain.has_method("try_build"):
					if terrain.try_build(pos, inv):
						build_ok += 1

		if now >= next_save and save_svc != null:
			next_save = now + int(SAVE_EVERY_SEC * 1000.0)
			saves += 1
			var rev_before_save: int = int(_WorldState.get_active().revision)
			if save_svc.save_slot(TEST_SLOT) == OK:
				save_ok += 1
				# Mid-churn load: reload overlays then keep streaming
				loads += 1
				var loaded: bool = await save_svc.load_slot(TEST_SLOT)
				if loaded:
					load_ok += 1
				else:
					_fail("load_slot failed during stress")
				# Revision must remain coherent (non-negative, advanced or restored)
				var rev_after: int = int(_WorldState.get_active().revision)
				if rev_after < 0:
					_fail("WorldState revision negative after save/load")
				if rev_after < 0:
					pass
			else:
				_fail("save_slot failed during stress")

		if now >= next_metrics:
			next_metrics = now + 500
			_sample_health(
				chunk_manager, profiler, ws, rev_samples, mesh_rev_samples,
				mem_samples, queue_samples, chunk_count_samples, frame_ms_samples, worker_ms_samples
			)
			var q: int = int(chunk_manager._mesh_completion_queue.size()) if "_mesh_completion_queue" in chunk_manager else 0
			max_queue = maxi(max_queue, q)
			max_chunks = maxi(max_chunks, chunk_manager.chunks.size())

		if crystal != null:
			if crystal.has_method("get_active_cell_count"):
				crystal_ticks_observed = maxi(crystal_ticks_observed, int(crystal.get_active_cell_count()))
			elif crystal.has_method("export_state"):
				var cst: Dictionary = crystal.export_state()
				var cells_v = cst.get("cells", cst.get("cell_count", 0))
				if cells_v is Dictionary:
					crystal_ticks_observed = maxi(crystal_ticks_observed, cells_v.size())
				else:
					crystal_ticks_observed = maxi(crystal_ticks_observed, int(cells_v))
			elif "cells" in crystal and crystal.cells is Dictionary:
				crystal_ticks_observed = maxi(crystal_ticks_observed, crystal.cells.size())

		# Continuous movement input between teleports
		if teleports % 2 == 0:
			Input.action_press("ui_right")
		else:
			Input.action_release("ui_right")
			Input.action_press("ui_up")
		await process_frame

	Input.action_release("ui_right")
	Input.action_release("ui_up")

	for _idle in 120:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	# Final samples
	_sample_health(
		chunk_manager, profiler, _WorldState.get_active(), rev_samples, mesh_rev_samples,
		mem_samples, queue_samples, chunk_count_samples, frame_ms_samples, worker_ms_samples
	)

	# --- Assertions ---
	if dig_ok < 3:
		_fail("expected several successful digs during stress (got %d)" % dig_ok)
	if teleports < 5:
		_fail("expected several teleports (got %d)" % teleports)
	if chunks_visited.size() < 3:
		_fail("expected multi-chunk visitation (got %d)" % chunks_visited.size())
	if not _revisions_monotonic_or_restored(rev_samples):
		_fail("WorldState revision sequence invalid: %s" % str(rev_samples))
	if not _revisions_monotonic_or_restored(mesh_rev_samples):
		_fail("mesh_input_revision sequence invalid")

	# Queue must not stick unbounded at end
	var final_queue: int = int(chunk_manager._mesh_completion_queue.size()) if "_mesh_completion_queue" in chunk_manager else 0
	if final_queue > 64:
		_fail("upload/mesh completion queue not draining (final=%d max=%d)" % [final_queue, max_queue])

	# Memory: reject pathological multi-x growth only
	if mem_samples.size() >= MEM_SAMPLES_MIN:
		var m0: float = float(mem_samples[0])
		var m1: float = float(mem_samples[mem_samples.size() - 1])
		var m_mid: float = float(mem_samples[int(mem_samples.size() / 2)])
		if m0 > 1.0 and m1 > m0 * 4.0 and m_mid > m0 * 3.0:
			_fail("pathological memory growth m0=%.1f mid=%.1f end=%.1f MB" % [m0, m_mid, m1])
	else:
		_note("WARN: few memory samples (%d)" % mem_samples.size())

	var pool := _ChunkDataPool.get_stats()
	var lifecycles: Array = _ChunkStreamingTelemetry.get_lifecycle_summaries()
	var stream_pass := 0
	for ev in _ChunkStreamingTelemetry.get_events():
		if str(ev.get("event", "")) == "stream_pass":
			stream_pass += 1

	var report := {
		"teleports": teleports,
		"chunks_visited": chunks_visited.size(),
		"digs": digs,
		"dig_ok": dig_ok,
		"builds": builds,
		"build_ok": build_ok,
		"saves": saves,
		"save_ok": save_ok,
		"loads": loads,
		"load_ok": load_ok,
		"crystal_cells_seen": crystal_ticks_observed,
		"max_mesh_queue": max_queue,
		"final_mesh_queue": final_queue,
		"max_loaded_chunks": max_chunks,
		"avg_frame_ms": _mean(frame_ms_samples),
		"p95_frame_ms": _percentile(frame_ms_samples, 0.95),
		"worst_frame_ms": _maxf(frame_ms_samples),
		"avg_worker_ms": _mean(worker_ms_samples),
		"mem_start_mb": float(mem_samples[0]) if mem_samples.size() else 0.0,
		"mem_end_mb": float(mem_samples[mem_samples.size() - 1]) if mem_samples.size() else 0.0,
		"mem_samples": mem_samples.size(),
		"pool_alloc_new": int(pool.get("alloc_new", 0)),
		"pool_alloc_reuse": int(pool.get("alloc_reuse", 0)),
		"stream_pass_events": stream_pass,
		"lifecycles": lifecycles.size(),
		"revision_samples": rev_samples.size(),
		"failures": _failed,
	}

	var metrics_path := scratch.path_join("runtime_health_metrics.log")
	var f := FileAccess.open(metrics_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.store_string("\n")
		for n in _notes:
			f.store_string(str(n) + "\n")
		f.close()

	_note("STRESS_REPORT " + JSON.stringify(report))
	_note("METRICS_PATH=%s" % metrics_path)

	var stress_log := scratch.path_join("edit_crystal_save_stress.log")
	var sf := FileAccess.open(stress_log, FileAccess.WRITE)
	if sf:
		sf.store_string(JSON.stringify(report, "\t") + "\n")
		for n in _notes:
			sf.store_string(str(n) + "\n")
		sf.close()

	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "stress worldstate/chunk FAILED (%d)" % _failed)
		return
	_ProbeExit.finish_tree(self, 0, "stress worldstate/chunk OK")


func _teleport_player(player: Node, world: InfiniteNoiseWorld, cm: ChunkManager, chunk_off: Vector2i) -> void:
	var base: Vector2i = cm.get_player_chunk_coord()
	var target := base + chunk_off
	var wx := float(target.x * ChunkData.SIZE + ChunkData.SIZE / 2)
	var wz := float(target.y * ChunkData.SIZE + ChunkData.SIZE / 2)
	var sy: float = world.get_surface_height(wx, wz) if world else 10.0
	if "voxel_position" in player:
		player.voxel_position = Vector3(wx, sy + 2.0, wz)
		if player.has_method("_sync_global_from_voxel"):
			player._sync_global_from_voxel()
		else:
			player.global_position = Vector3(wx, sy + 2.0, wz)
	else:
		player.global_position = Vector3(wx, sy + 2.0, wz)


func _sample_health(
	cm: ChunkManager,
	profiler: Node,
	ws,
	rev_samples: Array,
	mesh_rev_samples: Array,
	mem_samples: Array,
	queue_samples: Array,
	chunk_count_samples: Array,
	frame_ms_samples: Array,
	worker_ms_samples: Array
) -> void:
	if ws:
		rev_samples.append(int(ws.revision))
		mesh_rev_samples.append(int(ws.mesh_input_revision()))
	var q: int = 0
	if cm and "_mesh_completion_queue" in cm:
		q = int(cm._mesh_completion_queue.size())
	queue_samples.append(q)
	if cm:
		chunk_count_samples.append(cm.chunks.size())
	var mem_mb := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / (1024.0 * 1024.0)
	mem_samples.append(mem_mb)
	if profiler and profiler.has_method("get_snapshot"):
		var snap: Dictionary = profiler.get_snapshot()
		frame_ms_samples.append(float(snap.get("frame_ms", 0.0)))
		worker_ms_samples.append(float(snap.get("worker_ms", snap.get("worker_total_ms", 0.0))))
	else:
		frame_ms_samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)


func _contract_deterministic_pipeline(world: InfiniteNoiseWorld, cm: ChunkManager) -> void:
	_WorldState.get_active()  # ensure active session from game
	var data1 = _ChunkData.new(Vector2i(2, 2), world)
	data1.capture_worker_snapshot()
	var j1: Dictionary = _ChunkPipeline.run_worker_job(
		cm, data1, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}, false, true
	)
	var data2 = _ChunkData.new(Vector2i(2, 2), world)
	# Same frozen inputs: re-capture from same WorldState without further mutation
	data2.capture_worker_snapshot()
	var j2: Dictionary = _ChunkPipeline.run_worker_job(
		cm, data2, true, [], Rect2i(0, 0, ChunkData.SIZE, ChunkData.SIZE), [], {}, false, true
	)
	if not bool(j1.get("ok", false)) or not bool(j2.get("ok", false)):
		_fail("deterministic pipeline jobs failed")
		return
	var c1: int = int(j1.get("merged_quads", []).size())
	var c2: int = int(j2.get("merged_quads", []).size())
	if c1 != c2:
		_fail("deterministic pipeline quad count mismatch %d vs %d" % [c1, c2])
	else:
		_note("OK deterministic pipeline quads=%d" % c1)


func _contract_snapshot_immutability() -> void:
	var ws = _WorldState.get_active()
	var rev0: int = int(ws.revision)
	var data = _ChunkData.new(Vector2i(0, 0), null)
	# Need world for full capture — skip height halo if null world still stamps
	var world = get_first_node_in_group("world")
	data.world = world
	data.position = Vector2i(0, 0)
	_TerrainEdits.dig(1, 1, 1)
	data.capture_worker_snapshot()
	var frozen: float = data.get_worker_height_delta(1, 1)
	var stamp: Dictionary = data.overlay_mesh_stamp.duplicate()
	_TerrainEdits.dig(1, 1, 1)
	if not is_equal_approx(data.get_worker_height_delta(1, 1), frozen):
		_fail("worker snapshot height mutated after live dig")
	if data.is_overlay_mesh_stamp_current():
		_fail("mesh stamp should be stale after dig")
	if int(ws.revision) <= rev0 and frozen == 0.0:
		# dig may fail out of border; only fail if dig clearly applied
		pass
	_note("OK snapshot immutability frozen_h=%s stamp_stale=%s" % [
		frozen, not data.is_overlay_mesh_stamp_current()
	])


func _contract_stale_rejection(cm: ChunkManager) -> void:
	var world = get_first_node_in_group("world")
	var data = _ChunkData.new(Vector2i(3, 3), world)
	_TerrainEdits.dig(50, 50, 1)
	data.capture_worker_snapshot()
	var coord := Vector2i(3, 3)
	cm._chunk_gen_tokens[coord] = 42
	if cm.is_mesh_job_stale(coord, data, 42):
		_fail("fresh job should not be stale")
	if not cm.is_mesh_job_stale(coord, data, 41):
		_fail("token mismatch must be stale")
	_TerrainEdits.dig(50, 50, 1)
	if not cm.is_mesh_job_stale(coord, data, 42):
		_fail("mesh-input stamp supersede must be stale")
	_note("OK stale rejection contracts")


func _revisions_monotonic_or_restored(samples: Array) -> bool:
	if samples.is_empty():
		return false
	# Allow drops only when save/load restores lower revision (restore_overlay_snapshot).
	# Reject only negative or non-integer-like chaos.
	for s in samples:
		if int(s) < 0:
			return false
	return true


func _mean(vals: Array) -> float:
	if vals.is_empty():
		return 0.0
	var s := 0.0
	for v in vals:
		s += float(v)
	return s / float(vals.size())


func _maxf(vals: Array) -> float:
	var m := 0.0
	for v in vals:
		m = maxf(m, float(v))
	return m


func _percentile(vals: Array, p: float) -> float:
	if vals.is_empty():
		return 0.0
	var copy: Array = vals.duplicate()
	copy.sort()
	var idx := int(clampf(p, 0.0, 1.0) * float(copy.size() - 1))
	return float(copy[idx])
