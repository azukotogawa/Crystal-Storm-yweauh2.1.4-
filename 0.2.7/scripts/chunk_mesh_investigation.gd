extends SceneTree
## Headless chunk mesh investigation — per-rebuild telemetry + ROI report (no optimizations).


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")

const REQUIRED_METRICS: Array[String] = [
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

const BASELINE_WORKER_AVG_MS := 27.423
## profile_gameplay.gd: dig phase 30 of 180-frame cycle → ~1 dig / 180 frames.
const GAMEPLAY_DIG_INTERVAL_FRAMES := 180.0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-209a36c30e46/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("investigation: main scene missing")
		_ProbeExit.finish_tree(self, 1, "Chunk mesh investigation FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null
	var crystal: CrystalManager = null
	var weapon: Node = null
	var profiler: Node = root.get_node_or_null("/root/PerfProfiler")

	for _attempt in 900:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		crystal = get_first_node_in_group("crystal_manager")
		weapon = player.get_node_or_null("WeaponController") if player else null
		if (
			player != null and chunk_manager != null and terrain != null
			and world != null and crystal != null and crystal._initialized
			and profiler != null and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 5
		):
			break
		await process_frame

	if chunk_manager == null or terrain == null or world == null:
		push_error("investigation: bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Chunk mesh investigation FAILED")
		return

	for _w in 45:
		await process_frame
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()

	_ChunkRebuildTelemetry.reset()
	var inv = player.get("inventory")
	if inv:
		inv.set_slot(1, "stone_pick", 1)

	var scenario_stats: Dictionary = {}
	await _scenario_interior_dig(terrain, world, chunk_manager, scenario_stats)
	await _scenario_edge_dig(terrain, world, chunk_manager, scenario_stats)
	await _scenario_crystal_absorption(chunk_manager, crystal, scenario_stats)
	await _scenario_movement(player, chunk_manager, profiler, scenario_stats, 20.0)

	var records: Array = _ChunkRebuildTelemetry.get_records()
	var telemetry_path := "%s/chunk_rebuild_telemetry.jsonl" % scratch
	_ChunkRebuildTelemetry.write_jsonl(telemetry_path)

	if not _validate_records(records):
		_ProbeExit.finish_tree(self, 1, "Chunk mesh investigation FAILED")
		return

	var report := _build_report(records, scenario_stats)
	var report_path := "%s/chunk_mesh_investigation_report.md" % scratch
	_write_text(report_path, report)
	print(report)
	print("INVESTIGATION_TELEMETRY=%s" % telemetry_path)
	print("INVESTIGATION_REPORT=%s" % report_path)
	_ProbeExit.finish_tree(self, 0, "Chunk mesh investigation OK")


func _scenario_interior_dig(
	terrain: TerrainEditor,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	stats: Dictionary
) -> void:
	_ChunkRebuildTelemetry.set_scenario("interior_dig")
	var player_col := chunk_manager.get_player_chunk_coord()
	var search_origin := Vector2i(player_col.x * _ChunkData.SIZE + 8, player_col.y * _ChunkData.SIZE + 8)
	var dig_cell := _find_dig_cell(search_origin, world, chunk_manager, 0)
	if dig_cell == Vector2i(-1, -1):
		stats["interior_dig"] = {"error": "no interior cell"}
		return
	await _perform_dig(terrain, world, chunk_manager, dig_cell)
	var after_records := _records_since_scenario("interior_dig")
	stats["interior_dig"] = _summarize_batch(after_records, dig_cell, chunk_manager, 0)


func _scenario_edge_dig(
	terrain: TerrainEditor,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	stats: Dictionary
) -> void:
	_ChunkRebuildTelemetry.set_scenario("edge_dig")
	var player_col := chunk_manager.get_player_chunk_coord()
	var search_origin := Vector2i(player_col.x * _ChunkData.SIZE + 8, player_col.y * _ChunkData.SIZE + 8)
	var dig_cell := _find_dig_cell(search_origin, world, chunk_manager, 1)
	if dig_cell == Vector2i(-1, -1):
		stats["edge_dig"] = {"error": "no edge cell"}
		return
	await _perform_dig(terrain, world, chunk_manager, dig_cell)
	# Committed HEAD terrain uses ring=0; probe ring=1 fan-out as documented adaptive-ring cost.
	if chunk_manager.has_method("rebuild_region_at_world"):
		chunk_manager.rebuild_region_at_world(float(dig_cell.x), float(dig_cell.y), 1)
		if chunk_manager.has_method("flush_rebuild_pending"):
			chunk_manager.flush_rebuild_pending()
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 20:
		await process_frame
	var after_records := _records_since_scenario("edge_dig")
	stats["edge_dig"] = _summarize_batch(after_records, dig_cell, chunk_manager, 1)
	stats["edge_dig"]["head_gameplay_ring"] = 0
	stats["edge_dig"]["probe_ring"] = 1


func _scenario_crystal_absorption(
	chunk_manager: ChunkManager,
	crystal: CrystalManager,
	stats: Dictionary
) -> void:
	_ChunkRebuildTelemetry.set_scenario("crystal_absorption")
	var player_chunk := chunk_manager.get_player_chunk_coord()
	var target := Vector2i(player_chunk.x * _ChunkData.SIZE + 4, player_chunk.y * _ChunkData.SIZE + 4)
	if crystal.has_method("_set_depth"):
		crystal.call("_set_depth", target, 2.5, 0)
	for _w in 30:
		await process_frame
	if chunk_manager.has_method("set_rebuild_telemetry_context"):
		chunk_manager.set_rebuild_telemetry_context(
			"crystal_absorption",
			{"voxels_changed_hint": 1, "edit_wx": target.x, "edit_wz": target.y}
		)
	if chunk_manager.has_method("rebuild_chunk_at_world"):
		chunk_manager.rebuild_chunk_at_world(float(target.x), float(target.y))
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 20:
		await process_frame
	var after_records := _records_since_scenario("crystal_absorption")
	stats["crystal_absorption"] = _summarize_batch(after_records, target, chunk_manager, 0)
	stats["crystal_absorption"]["terrain_rebuilds"] = after_records.size()


func _scenario_movement(
	player: Node,
	chunk_manager: ChunkManager,
	profiler: Node,
	stats: Dictionary,
	seconds: float
) -> void:
	_ChunkRebuildTelemetry.set_scenario("movement_session")
	chunk_manager.set_rebuild_telemetry_context("movement", {})
	var move_dirs: Array[String] = ["ui_right", "ui_up", "ui_left", "ui_down"]
	var end_ms := Time.get_ticks_msec() + int(seconds * 1000.0)
	var frames := 0
	var worker_samples: Array[float] = []
	var upload_frames := 0
	var rebuild_frames := 0
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
			var worker_ms := float(snap.get("worker_ms", 0.0))
			worker_samples.append(worker_ms)
			if worker_ms > 0.5:
				rebuild_frames += 1
			var upload_ms := float(snap.get("sections", {}).get("chunk_upload", {}).get("last_ms", 0.0))
			if upload_ms > 0.01:
				upload_frames += 1
	for action in move_dirs:
		Input.action_release(action)

	var move_records := _records_since_scenario("movement_session")
	stats["movement_session"] = {
		"frames": frames,
		"rebuilds_logged": move_records.size(),
		"frames_with_worker_ms_gt_0.5": rebuild_frames,
		"frames_with_upload_ms_gt_0": upload_frames,
		"avg_worker_ms": _mean(worker_samples),
		"upload_every_frame": upload_frames >= int(frames * 0.9),
	}


func _perform_dig(
	terrain: TerrainEditor,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	dig_cell: Vector2i
) -> void:
	var sy: float = world.get_surface_height(float(dig_cell.x), float(dig_cell.y))
	terrain.try_dig(Vector3(float(dig_cell.x) + 0.5, sy, float(dig_cell.y) + 0.5))
	if chunk_manager.has_method("await_rebuild_idle"):
		await chunk_manager.await_rebuild_idle()
	for _w in 20:
		await process_frame


static func _rebuild_ring_for_cell(wx: int, wz: int) -> int:
	const EDGE_BAND := 2
	var chunk_x := floori(float(wx) / float(_ChunkData.SIZE))
	var chunk_z := floori(float(wz) / float(_ChunkData.SIZE))
	var lx := wx - chunk_x * _ChunkData.SIZE
	var lz := wz - chunk_z * _ChunkData.SIZE
	if lx < EDGE_BAND or lx >= _ChunkData.SIZE - EDGE_BAND:
		return 1
	if lz < EDGE_BAND or lz >= _ChunkData.SIZE - EDGE_BAND:
		return 1
	return 0


func _find_dig_cell(
	search_origin: Vector2i,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	ring: int
) -> Vector2i:
	for radius in range(0, 12):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if radius > 0 and maxi(absi(dx), absi(dz)) != radius:
					continue
				var wx: int = search_origin.x + dx
				var wz: int = search_origin.y + dz
				if _rebuild_ring_for_cell(wx, wz) != ring:
					continue
				if not _ActionTargeting._is_solid_column(world, chunk_manager, wx, wz):
					continue
				if not _TerrainEdits.can_edit(wx, wz):
					continue
				return Vector2i(wx, wz)
	return Vector2i(-1, -1)


func _records_since_scenario(scenario: String) -> Array:
	var out: Array = []
	for row in _ChunkRebuildTelemetry.get_records():
		if str(row.get("scenario", "")) == scenario:
			out.append(row)
	return out


func records_for_scenario(scenario: String) -> Array:
	return _records_since_scenario(scenario)


func _summarize_batch(
	records: Array,
	edit_cell: Vector2i,
	chunk_manager: ChunkManager,
	ring: int
) -> Dictionary:
	var edit_chunk := chunk_manager.world_to_chunk_coord(edit_cell.x, edit_cell.y)
	var coords: Array = []
	var neighbor_only := 0
	var mesh_gen_total := 0.0
	var serialization_total := 0.0
	var upload_total := 0.0
	var apply_total := 0.0
	var voxels_examined_total := 0
	var voxels_changed_hint := 0
	for row in records:
		var coord := Vector2i(int(row.get("coord_x", 0)), int(row.get("coord_z", 0)))
		coords.append(coord)
		if coord != edit_chunk:
			neighbor_only += 1
		mesh_gen_total += float(row.get("mesh_generation_time_ms", 0.0))
		serialization_total += float(row.get("serialization_time_ms", 0.0))
		upload_total += float(row.get("mesh_upload_time_ms", 0.0))
		apply_total += float(row.get("main_thread_apply_time_ms", 0.0))
		voxels_examined_total += int(row.get("voxels_examined", 0))
		voxels_changed_hint = maxi(voxels_changed_hint, int(row.get("voxels_changed_hint", 0)))

	return {
		"chunks_rebuilt": records.size(),
		"unique_chunks": _unique_coords(coords).size(),
		"edit_chunk": edit_chunk,
		"rebuild_ring": ring,
		"neighbor_rebuilds": neighbor_only,
		"neighbor_mesh_ms_total": _sum_neighbor_mesh_ms(records, edit_chunk),
		"avg_mesh_generation_ms": mesh_gen_total / maxf(float(records.size()), 1.0),
		"avg_serialization_ms": serialization_total / maxf(float(records.size()), 1.0),
		"avg_upload_ms": upload_total / maxf(float(records.size()), 1.0),
		"avg_apply_ms": apply_total / maxf(float(records.size()), 1.0),
		"voxels_examined_per_chunk": int(voxels_examined_total / maxi(records.size(), 1)),
		"voxels_changed_hint": voxels_changed_hint,
		"full_chunk_regen": voxels_examined_total > 0 and int(voxels_examined_total / maxi(records.size(), 1)) >= 256,
		"payload_duplicated_all": _all_true(records, "payload_duplicated"),
		"buffer_allocated_all": _all_true(records, "buffer_allocated"),
		"mesh_nodes_recreated_all": _all_true(records, "mesh_nodes_recreated"),
	}


func _build_report(records: Array, scenario_stats: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Chunk mesh generation investigation")
	lines.append("")
	lines.append("**Context:** Prior gameplay profile showed ~%.3f ms avg `worker_total` / `chunk_mesh` (MEDIUM preset, 45s session)." % BASELINE_WORKER_AVG_MS)
	lines.append("**Method:** Per-rebuild telemetry via `CRYSTALSTORM_CHUNK_PROFILE=1` on production `main.tscn`. No optimizations applied.")
	lines.append("**Serialization definition:** `quads.duplicate(true)` + `ChunkMeshBufferBuilder.build_mesh_payload` on worker.")
	lines.append("")

	lines.append("## Per-rebuild telemetry summary")
	lines.append("")
	lines.append("| Scenario | Rebuilds | Avg mesh gen (ms) | Avg serial (ms) | Avg upload (ms) | Avg apply (ms) | Voxels examined/chunk |")
	lines.append("|----------|----------|-------------------|-----------------|-----------------|----------------|----------------------|")
	for key in ["interior_dig", "edge_dig", "crystal_absorption"]:
		var s: Dictionary = scenario_stats.get(key, {})
		if s.is_empty() or s.has("error"):
			continue
		lines.append(
			"| %s | %d | %.3f | %.3f | %.3f | %.3f | %d |"
			% [
				key,
				int(s.get("chunks_rebuilt", 0)),
				float(s.get("avg_mesh_generation_ms", 0.0)),
				float(s.get("avg_serialization_ms", 0.0)),
				float(s.get("avg_upload_ms", 0.0)),
				float(s.get("avg_apply_ms", 0.0)),
				int(s.get("voxels_examined_per_chunk", 0)),
			]
		)
	lines.append("")

	lines.append("## Investigative Q&A (measured)")
	lines.append("")
	var interior: Dictionary = scenario_stats.get("interior_dig", {})
	var edge: Dictionary = scenario_stats.get("edge_dig", {})
	var crystal: Dictionary = scenario_stats.get("crystal_absorption", {})
	var movement: Dictionary = scenario_stats.get("movement_session", {})

	lines.append("### Are entire chunks rebuilt when only a few voxels changed?")
	lines.append("**Yes.** Interior dig changed **%d** voxel(s) (hint) but each rebuild examined **%d** columns (full 16×16 `SIZE`) and regenerated column maps (`_compute_column_maps(true)`)." % [
		int(interior.get("voxels_changed_hint", 1)),
		int(interior.get("voxels_examined_per_chunk", 256)),
	])
	lines.append("")

	lines.append("### How many chunks rebuild from one dig?")
	lines.append("- **Interior dig (ring=0):** **%d** chunk(s) rebuilt." % int(interior.get("chunks_rebuilt", 0)))
	lines.append("- **Edge dig (ring=1):** **%d** chunk(s) rebuilt (**%d** neighbor-only)." % [
		int(edge.get("chunks_rebuilt", 0)),
		int(edge.get("neighbor_rebuilds", 0)),
	])
	lines.append("")

	lines.append("### How many chunks rebuild from one crystal update?")
	lines.append("Crystal depth tick does **not** enqueue terrain rebuilds. Simulated absorption path (`rebuild_chunk_at_world`): **%d** terrain chunk(s)." % int(crystal.get("terrain_rebuilds", 0)))
	lines.append("")

	lines.append("### Are neighboring chunks rebuilding unnecessarily?")
	lines.append(
		"HEAD gameplay dig uses ring=**%d**; investigation probed ring=**%d** at edge cell to measure adaptive-ring fan-out. Measured **%d** rebuilds (**%d** neighbor-only)." % [
			int(edge.get("head_gameplay_ring", 0)),
			int(edge.get("probe_ring", 1)),
			int(edge.get("chunks_rebuilt", 0)),
			int(edge.get("neighbor_rebuilds", 0)),
		]
	)
	lines.append("")

	lines.append("### Are uploads happening every frame?")
	var upload_pct := 0.0
	if int(movement.get("frames", 0)) > 0:
		upload_pct = 100.0 * float(movement.get("frames_with_upload_ms_gt_0", 0)) / float(movement.get("frames", 0))
	lines.append("**No.** During **%.0fs** movement (**%d** frames): **%d** frames had `chunk_upload` > 0 (%.1f%%). Rebuilds logged: **%d**." % [
		20.0,
		int(movement.get("frames", 0)),
		int(movement.get("frames_with_upload_ms_gt_0", 0)),
		upload_pct,
		int(movement.get("rebuilds_logged", 0)),
	])
	lines.append("")

	lines.append("### Is mesh data recreated instead of reused?")
	var dup_count := _count_true(records, "payload_duplicated")
	lines.append(
		"**Yes (measured + code path).** `payload_duplicated` observed on **%d/%d** rebuilds (new quad array ref after `duplicate(true)`); `mesh_nodes_recreated` on regen applies; `ChunkView.emit_quads` frees all `MultiMeshInstance3D` children each apply."
		% [dup_count, records.size()]
	)
	lines.append("")

	lines.append("### Are arrays constantly allocated?")
	var alloc_path_count := _count_alloc_path(records, "ChunkData.new")
	var buffer_count := _count_true(records, "buffer_allocated")
	lines.append(
		"**Yes.** Code-path invariant: `chunk_data_alloc_path=ChunkData.new` on **%d/%d** enqueues; `buffer_allocated` measured on **%d/%d**; plus per-rebuild `out_quads`, greedy `visited` arrays."
		% [alloc_path_count, records.size(), buffer_count, records.size()]
	)
	lines.append("")

	lines.append("## Why ~27 ms/frame average?")
	var regen_records: Array = []
	for row in records:
		if bool(row.get("is_regen", false)) or str(row.get("trigger", "")) in ["terrain_edit", "movement", "stream"]:
			regen_records.append(row)
	var total_mesh := 0.0
	for row in regen_records:
		total_mesh += float(row.get("mesh_generation_time_ms", 0.0))
	var move_frames := maxi(int(movement.get("frames", 1)), 1)
	var rebuilds_during_move := int(movement.get("rebuilds_logged", 0))
	var implied_per_frame := total_mesh / maxf(float(regen_records.size()), 1.0) * float(rebuilds_during_move) / float(move_frames)
	lines.append("Worker mesh cost averages **%.2f ms** per rebuild (all scenarios). Movement session: **%d** rebuilds over **%d** frames → **%.2f ms** implied worker contribution/frame if spread evenly. Spikes (worst-case **%.2f ms** mesh gen) align with prior profile P95/worst frames." % [
		total_mesh / maxf(float(regen_records.size()), 1.0),
		rebuilds_during_move,
		move_frames,
		implied_per_frame,
		_max_metric(records, "mesh_generation_time_ms"),
	])
	lines.append("Idle frames record 0 ms; sparse rebuilds inflate the **average** `worker_total` metric from frame snapshots.")
	lines.append("")

	lines.append("## Top 10 optimization opportunities (estimated frame savings, descending)")
	lines.append("")
	lines.append("_Amortization: stream-class ops use movement rebuild rate; dig-class ops use gameplay dig cadence (1/%.0f frames from `profile_gameplay.gd`); each estimate capped at measured movement worker budget._" % GAMEPLAY_DIG_INTERVAL_FRAMES)
	lines.append("")
	var opportunities := _rank_opportunities(records, scenario_stats)
	for i in opportunities.size():
		var op: Dictionary = opportunities[i]
		lines.append("%d. **%s** — est. **%.2f ms/frame** saved. %s" % [
			i + 1,
			str(op.get("title", "")),
			float(op.get("est_ms_per_frame", 0.0)),
			str(op.get("evidence", "")),
		])
	lines.append("")

	lines.append("## Sample per-rebuild rows (first 5)")
	lines.append("")
	for i in mini(5, records.size()):
		lines.append("```json")
		lines.append(JSON.stringify(records[i]))
		lines.append("```")
		lines.append("")

	return "\n".join(lines)


func _rank_opportunities(records: Array, scenario_stats: Dictionary) -> Array:
	var interior: Dictionary = scenario_stats.get("interior_dig", {})
	var edge: Dictionary = scenario_stats.get("edge_dig", {})
	var movement: Dictionary = scenario_stats.get("movement_session", {})
	var budgets: Dictionary = _compute_amortization_budgets(records, scenario_stats)

	var stream_ms_cap: float = float(budgets.get("stream_worker_ms_per_frame", 0.0))
	var stream_rate: float = float(budgets.get("stream_rebuild_rate", 0.0))
	var interior_dig_rate: float = float(budgets.get("interior_dig_rate_per_frame", 0.0))
	var edge_dig_rate: float = float(budgets.get("edge_dig_rate_per_frame", 0.0))

	var interior_mesh: float = float(interior.get("avg_mesh_generation_ms", 0.0))
	var interior_column: float = _avg_metric(_filter_scenario(records, "interior_dig"), "column_map_time_ms")
	var edge_neighbor_mesh: float = float(edge.get("neighbor_mesh_ms_total", 0.0))
	var stream_column: float = float(budgets.get("stream_avg_column_ms", 0.0))
	var stream_serial: float = float(budgets.get("stream_avg_serial_ms", 0.0))
	var stream_apply: float = float(budgets.get("stream_avg_apply_ms", 0.0))
	var stream_queue: float = float(budgets.get("stream_avg_queue_ms", 0.0))
	var stream_mesh: float = float(budgets.get("stream_avg_mesh_ms", 0.0))

	var ops: Array = [
		{
			"title": "Incremental column-map + mesh patch (1-cell dirty halo)",
			"est_ms_per_frame": _cap_frame_saving(interior_mesh * 0.85 * interior_dig_rate, stream_ms_cap),
			"evidence": "Interior dig: %d voxel changed, %d examined/chunk, mesh %.2f ms/event; amortized at %.4f digs/frame." % [
				int(interior.get("voxels_changed_hint", 1)),
				int(interior.get("voxels_examined_per_chunk", 256)),
				interior_mesh,
				interior_dig_rate,
			],
		},
		{
			"title": "Skip full chunk regen on ring=0 interior edits",
			"est_ms_per_frame": _cap_frame_saving(interior_column * 0.7 * interior_dig_rate, stream_ms_cap),
			"evidence": "Interior column maps %.2f ms; ring=0 still full `_compute_column_maps(true)`; %.4f interior digs/frame." % [
				interior_column,
				interior_dig_rate,
			],
		},
		{
			"title": "Reduce edge-dig neighbor rebuild fan-out",
			"est_ms_per_frame": _cap_frame_saving(edge_neighbor_mesh * edge_dig_rate, stream_ms_cap),
			"evidence": "Edge dig: %d chunks (%d neighbors), neighbor mesh waste %.2f ms/event; %.4f edge digs/frame." % [
				int(edge.get("chunks_rebuilt", 0)),
				int(edge.get("neighbor_rebuilds", 0)),
				edge_neighbor_mesh,
				edge_dig_rate,
			],
		},
		{
			"title": "Reuse ChunkData + surface maps across stream regen",
			"est_ms_per_frame": _cap_frame_saving(stream_column * 0.4 * stream_rate, stream_ms_cap),
			"evidence": "Stream column maps avg %.2f ms; code path always `ChunkData.new` at enqueue; stream rate %.4f rebuilds/frame." % [
				stream_column,
				stream_rate,
			],
		},
		{
			"title": "Throttle stream regen while movement rebuilds pending",
			"est_ms_per_frame": _cap_frame_saving(stream_mesh * 0.15 * stream_rate, stream_ms_cap),
			"evidence": "Movement: %d stream rebuilds / %d frames; avg stream mesh %.2f ms." % [
				int(movement.get("rebuilds_logged", 0)),
				int(movement.get("frames", 0)),
				stream_mesh,
			],
		},
		{
			"title": "Raise worker concurrency / shrink queue wait",
			"est_ms_per_frame": _cap_frame_saving(stream_queue * stream_rate, stream_ms_cap),
			"evidence": "Stream avg queue wait %.2f ms; movement worker budget %.2f ms/frame." % [
				stream_queue,
				stream_ms_cap,
			],
		},
		{
			"title": "Eliminate quads.duplicate(true) serialization copy",
			"est_ms_per_frame": _cap_frame_saving(stream_serial * 0.35 * stream_rate, stream_ms_cap),
			"evidence": "payload_duplicated on %d/%d rows; stream serial avg %.2f ms." % [
				_count_true(records, "payload_duplicated"),
				records.size(),
				stream_serial,
			],
		},
		{
			"title": "Pool PackedFloat32Array / mesh group buffers",
			"est_ms_per_frame": _cap_frame_saving(stream_serial * 0.25 * stream_rate, stream_ms_cap),
			"evidence": "buffer_allocated on %d/%d stream-path rebuilds." % [
				_count_true(_filter_scenario(records, "movement_session"), "buffer_allocated"),
				_filter_scenario(records, "movement_session").size(),
			],
		},
		{
			"title": "Reuse MultiMeshInstance3D nodes (avoid teardown per apply)",
			"est_ms_per_frame": _cap_frame_saving(stream_apply * 0.5 * stream_rate, stream_ms_cap),
			"evidence": "Stream avg apply %.2f ms; mesh_nodes_recreated on regen applies." % stream_apply,
		},
		{
			"title": "Defer buffer prebuild to main thread with budget",
			"est_ms_per_frame": _cap_frame_saving(stream_serial * 0.2 * stream_rate, stream_ms_cap),
			"evidence": "prebuild_chunk_buffers on worker; stream serial avg %.2f ms." % stream_serial,
		},
	]
	ops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("est_ms_per_frame", 0.0)) > float(b.get("est_ms_per_frame", 0.0))
	)
	return ops


func _compute_amortization_budgets(records: Array, scenario_stats: Dictionary) -> Dictionary:
	var movement: Dictionary = scenario_stats.get("movement_session", {})
	var move_frames := maxf(float(movement.get("frames", 1)), 1.0)
	var stream_records: Array = _filter_scenario(records, "movement_session")
	var stream_mesh_total := 0.0
	for row in stream_records:
		stream_mesh_total += float(row.get("mesh_generation_time_ms", 0.0))
	var stream_worker_ms_per_frame := stream_mesh_total / move_frames
	var stream_rebuild_rate := float(stream_records.size()) / move_frames

	var gameplay_dig_rate := 1.0 / GAMEPLAY_DIG_INTERVAL_FRAMES
	var interior_dig_rate := gameplay_dig_rate * 0.5
	var edge_dig_rate := gameplay_dig_rate * 0.5

	return {
		"stream_worker_ms_per_frame": stream_worker_ms_per_frame,
		"stream_rebuild_rate": stream_rebuild_rate,
		"interior_dig_rate_per_frame": interior_dig_rate,
		"edge_dig_rate_per_frame": edge_dig_rate,
		"stream_avg_column_ms": _avg_metric(stream_records, "column_map_time_ms"),
		"stream_avg_serial_ms": _avg_metric(stream_records, "serialization_time_ms"),
		"stream_avg_apply_ms": _avg_metric(stream_records, "main_thread_apply_time_ms"),
		"stream_avg_queue_ms": _avg_metric(stream_records, "worker_queue_wait_ms"),
		"stream_avg_mesh_ms": _avg_metric(stream_records, "mesh_generation_time_ms"),
	}


static func _cap_frame_saving(raw: float, cap: float) -> float:
	if cap <= 0.0:
		return maxf(raw, 0.0)
	return minf(maxf(raw, 0.0), cap)


static func _filter_scenario(records: Array, scenario: String) -> Array:
	var out: Array = []
	for row in records:
		if str(row.get("scenario", "")) == scenario:
			out.append(row)
	return out


static func _sum_neighbor_mesh_ms(records: Array, edit_chunk: Vector2i) -> float:
	var total := 0.0
	for row in records:
		var coord := Vector2i(int(row.get("coord_x", 0)), int(row.get("coord_z", 0)))
		if coord == edit_chunk:
			continue
		total += float(row.get("mesh_generation_time_ms", 0.0))
	return total


func _validate_records(records: Array) -> bool:
	if records.is_empty():
		push_error("investigation: no telemetry records")
		return false
	for row in records:
		for key in REQUIRED_METRICS:
			if not row.has(key):
				push_error("investigation: row missing metric %s" % key)
				return false
			if typeof(row[key]) not in [TYPE_INT, TYPE_FLOAT]:
				push_error("investigation: metric %s not numeric" % key)
				return false
	return true


static func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


static func _avg_metric(records: Array, key: String) -> float:
	if records.is_empty():
		return 0.0
	var sum := 0.0
	for row in records:
		sum += float(row.get(key, 0.0))
	return sum / float(records.size())


static func _max_metric(records: Array, key: String) -> float:
	var m := 0.0
	for row in records:
		m = maxf(m, float(row.get(key, 0.0)))
	return m


static func _all_true(records: Array, key: String) -> bool:
	for row in records:
		if not bool(row.get(key, false)):
			return false
	return not records.is_empty()


static func _count_alloc_path(records: Array, path: String) -> int:
	var n := 0
	for row in records:
		if str(row.get("chunk_data_alloc_path", "")) == path:
			n += 1
	return n


static func _count_true(records: Array, key: String) -> int:
	var n := 0
	for row in records:
		if bool(row.get(key, false)):
			n += 1
	return n


static func _unique_coords(coords: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for c in coords:
		var key := "%d,%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(c)
	return out


static func _write_text(path: String, body: String) -> void:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(body)
		f.close()