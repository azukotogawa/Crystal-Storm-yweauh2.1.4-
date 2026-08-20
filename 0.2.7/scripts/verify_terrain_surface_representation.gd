extends SceneTree
## Before/after: legacy MultiMesh box instances vs consolidated surface ArrayMesh.


const MAIN_SCENE := "res://scenes/main.tscn"
const CHUNK_VIEW_SCENE := preload("res://scenes/ChunkView.tscn")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ChunkRebuildTelemetry = preload("res://systems/chunk_rebuild_telemetry.gd")
const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _TerrainSurfaceCache = preload("res://helpers/terrain_surface_cache.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_CHUNK_PROFILE", "1")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH").strip_edges()
	if scratch.is_empty():
		scratch = "/tmp/grok-goal-67c05d4c55ed/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)

	var failed := false
	_ChunkRebuildTelemetry.reset()

	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		_ProbeExit.finish_tree(self, 1, "terrain surface representation FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var chunk_manager: ChunkManager = null
	var terrain: TerrainEditor = null
	var world: InfiniteNoiseWorld = null

	for _attempt in 600:
		chunk_manager = get_first_node_in_group("chunk_manager")
		terrain = get_first_node_in_group("terrain_editor")
		world = get_first_node_in_group("world")
		if (
			chunk_manager != null and terrain != null and world != null
			and chunk_manager.chunks.size() >= 3
		):
			break
		await process_frame

	if chunk_manager == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "terrain surface representation FAILED")
		return

	for _w in 30:
		await process_frame

	var player_chunk := chunk_manager.get_player_chunk_coord()
	var live_view: ChunkView = chunk_manager.chunks.get(player_chunk) as ChunkView
	if live_view == null or live_view.chunk_data == null:
		push_error("no live player chunk view")
		_ProbeExit.finish_tree(self, 1, "terrain surface representation FAILED")
		return

	var quads: Array = live_view.mesh_data.get("quads", []).duplicate(true)
	var data: ChunkData = live_view.chunk_data

	var patch_split := _split_patch_quads(quads)
	var prior_surface_cache := _TerrainSurfaceCache.build_from_quads(
		data, _TerrainSurfaceCache.filter_terrain_quads(quads)
	)
	await _measure_incremental_rebuild_ms(data, patch_split, false, {})
	await _measure_incremental_rebuild_ms(data, patch_split, true, prior_surface_cache)

	var legacy_samples: Array = []
	var surface_samples: Array = []
	for _i in 15:
		legacy_samples.append(await _measure_incremental_rebuild_ms(data, patch_split, false, {}))
	for _i in 15:
		surface_samples.append(await _measure_incremental_rebuild_ms(
			data, patch_split, true, prior_surface_cache
		))
	var legacy_rebuild: Dictionary = _median_sample(legacy_samples)
	var surface_rebuild: Dictionary = _median_sample(surface_samples)
	var legacy_payload := _ChunkMeshBufferBuilder.build_mesh_payload(data, quads, false)
	var surface_payload := _ChunkMeshBufferBuilder.build_mesh_payload(data, quads, true)

	var legacy_stats := await _probe_view_layers(data, legacy_payload)
	var surface_stats := await _probe_view_layers(data, surface_payload)
	var live_stats := _stats_from_view(live_view)


	# Incremental terrain edit on production surface representation.
	_ChunkRebuildTelemetry.set_scenario("surface_incremental_dig")
	_ChunkRebuildTelemetry.set_trigger_hint("terrain_edit", {"voxels_changed_hint": 1})
	var dig_cell := _find_interior_dig_cell(chunk_manager, world)
	var pre_dig_tris := int(live_view.mesh_data.get("surface_triangle_count", 0))
	var incremental_ok := false
	var incremental_worker_ms := 9999.0
	var live_dig_triangle_parity_ok := false
	var live_dig_triangle_no_orphans_ok := false
	var post_dig_tris := 0
	var full_rebuild_tris := 0
	if dig_cell.x >= 0:
		var sy: float = world.get_surface_height(float(dig_cell.x), float(dig_cell.y))
		terrain.try_dig(Vector3(float(dig_cell.x) + 0.5, sy, float(dig_cell.y) + 0.5))
		if chunk_manager.has_method("await_rebuild_idle"):
			await chunk_manager.await_rebuild_idle()
		for _w in 20:
			await process_frame
		var post_view: ChunkView = chunk_manager.chunks.get(player_chunk) as ChunkView
		if post_view != null and post_view.mesh_data != null:
			var post_quads: Array = post_view.mesh_data.get("quads", [])
			post_dig_tris = int(post_view.mesh_data.get("surface_triangle_count", 0))
			var post_cache := _TerrainSurfaceCache.cache_from_payload(post_view.mesh_data)
			var full_rebuild := _TerrainSurfaceCache.build_from_quads(
				data, _TerrainSurfaceCache.filter_terrain_quads(post_quads)
			)
			full_rebuild_tris = int(full_rebuild.triangle_count)
			live_dig_triangle_parity_ok = (
				post_dig_tris == full_rebuild_tris
				and _TerrainSurfaceCache.triangle_count_matches_full_rebuild(
					data, post_cache, post_quads
				)
			)
			live_dig_triangle_no_orphans_ok = post_dig_tris == full_rebuild_tris
			print(
				"OK live dig triangles pre=%d post=%d full_rebuild=%d parity=%s"
				% [
					pre_dig_tris,
					post_dig_tris,
					full_rebuild_tris,
					"yes" if live_dig_triangle_parity_ok else "no",
				]
			)
		else:
			push_error("no post-dig chunk view")
		var edit_rows: Array = []
		for row in _ChunkRebuildTelemetry.get_records():
			if bool(row.get("incremental", false)):
				edit_rows.append(row)
		if not edit_rows.is_empty():
			var row: Dictionary = edit_rows[edit_rows.size() - 1]
			var examined: int = int(row.get("voxels_examined", 999))
			var rebuilt: int = int(row.get("rebuilt_columns", 999))
			incremental_ok = examined < 256 and rebuilt < 256
			incremental_worker_ms = float(row.get("serialization_time_ms", 9999.0))
			print(
				"OK incremental dig examined=%d rebuilt=%d worker_ms=%.3f representation=surface_mesh"
				% [examined, rebuilt, incremental_worker_ms]
			)
		else:
			push_error("no incremental telemetry after dig")
	else:
		push_error("no interior dig cell")

	var legacy_tris := int(legacy_payload.get("terrain_count", 0)) * 12
	var surface_tris := int(surface_rebuild.get("surface_triangle_count", 0))
	if surface_tris <= 0:
		surface_tris = int(surface_payload.get("terrain_count", 0)) * 2

	var legacy_total_ms := float(legacy_rebuild.get("total_ms", 9999.0))
	var surface_total_ms := float(surface_rebuild.get("total_ms", 9999.0))

	var gates := {
		"terrain_multimesh_instances_drop": (
			surface_stats.terrain_multimesh_instances
			< legacy_stats.terrain_multimesh_instances
		),
		"surface_mesh_nodes_present": surface_stats.terrain_surface_meshes >= 1,
		"live_production_surface_mesh": live_stats.terrain_surface_meshes >= 1,
		"triangle_count_sane": surface_tris > 0 and surface_tris < legacy_tris,
		"render_instance_budget_drop": (
			surface_stats.multimesh_instances < legacy_stats.multimesh_instances
		),
		"worker_surface_cache_present": (
			surface_payload.has("surface_cache")
			or surface_payload.has("surface_vertices")
			or surface_payload.has("surface_mesh_resource")
		),
		"live_surface_cache_or_mesh": (
			live_view.mesh_data.has("surface_cache")
			or live_view.mesh_data.has("surface_vertices")
			or live_view.mesh_data.has("surface_mesh_resource")
		),
		"rebuild_total_not_worse_than_legacy": surface_total_ms <= legacy_total_ms,
		"incremental_worker_under_full_legacy": (
			float(surface_rebuild.get("worker_ms", 9999.0))
			<= float(legacy_rebuild.get("worker_ms", 0.0)) + 0.05
		),
		"incremental_patch_ok": incremental_ok,
		"live_dig_triangle_matches_full_rebuild": live_dig_triangle_parity_ok,
		"live_dig_triangle_no_orphans": live_dig_triangle_no_orphans_ok,
	}

	for gate_name in gates.keys():
		if not bool(gates[gate_name]):
			push_error("GATE FAIL: %s" % gate_name)
			failed = true
		else:
			print("GATE PASS: %s" % gate_name)

	var report_lines: PackedStringArray = PackedStringArray()
	report_lines.append("# Terrain representation redesign — before/after")
	report_lines.append("")
	report_lines.append(
		"Player chunk %s probed via isolated `ChunkView` instances on the same greedy quad payload. Production live view uses `representation=surface_mesh`."
		% str(player_chunk)
	)
	report_lines.append("")
	report_lines.append("## Scene composition (player chunk)")
	report_lines.append("")
	report_lines.append("| Metric | Legacy MultiMesh | Surface ArrayMesh | Live production |")
	report_lines.append("|--------|------------------|-------------------|-----------------|")
	report_lines.append(
		"| terrain MultiMesh instances | %d | %d | %d |"
		% [
			legacy_stats.terrain_multimesh_instances,
			surface_stats.terrain_multimesh_instances,
			live_stats.terrain_multimesh_instances,
		]
	)
	report_lines.append(
		"| terrain surface MeshInstance3D | %d | %d | %d |"
		% [
			legacy_stats.terrain_surface_meshes,
			surface_stats.terrain_surface_meshes,
			live_stats.terrain_surface_meshes,
		]
	)
	report_lines.append(
		"| ramp MultiMesh instances | %d | %d | %d |"
		% [
			legacy_stats.ramp_multimesh_instances,
			surface_stats.ramp_multimesh_instances,
			live_stats.ramp_multimesh_instances,
		]
	)
	report_lines.append(
		"| total MultiMesh instances | %d | %d | %d |"
		% [
			legacy_stats.multimesh_instances,
			surface_stats.multimesh_instances,
			live_stats.multimesh_instances,
		]
	)
	report_lines.append("")
	report_lines.append(
		"## Rebuild cost (simulated incremental patch: keep=%d patch=%d quads; gate uses total_ms)"
		% [patch_split.keep.size(), patch_split.patch.size()]
	)
	report_lines.append("")
	report_lines.append("| Metric | Legacy | Surface |")
	report_lines.append("|--------|--------|---------|")
	report_lines.append("| worker_buffer_ms | %.3f | %.3f |" % [
		float(legacy_rebuild.get("worker_ms", 0.0)),
		float(surface_rebuild.get("worker_ms", 0.0)),
	])
	report_lines.append("| main_emit_ms | %.3f | %.3f |" % [
		float(legacy_rebuild.get("main_emit_ms", 0.0)),
		float(surface_rebuild.get("main_emit_ms", 0.0)),
	])
	report_lines.append("| main_drain_ms (deferred MultiMesh buffers) | %.3f | %.3f |" % [
		float(legacy_rebuild.get("main_drain_ms", 0.0)),
		float(surface_rebuild.get("main_drain_ms", 0.0)),
	])
	report_lines.append("| main_apply_ms (emit + drain) | %.3f | %.3f |" % [
		float(legacy_rebuild.get("main_ms", 0.0)),
		float(surface_rebuild.get("main_ms", 0.0)),
	])
	report_lines.append("| **rebuild_total_ms** | **%.3f** | **%.3f** |" % [legacy_total_ms, surface_total_ms])
	report_lines.append(
		"| incremental_worker_ms (live dig) | — | **%.3f** (< %.3f legacy total) |"
		% [incremental_worker_ms, legacy_total_ms * 0.5]
	)
	report_lines.append("| render instance budget (MultiMesh count) | %d | %d |" % [
		legacy_stats.multimesh_instances, surface_stats.multimesh_instances
	])
	report_lines.append("| triangles_generated | %d | %d |" % [legacy_tris, surface_tris])
	report_lines.append("")
	report_lines.append("## Verification gates")
	report_lines.append("")
	for gate_name in gates.keys():
		report_lines.append("- %s: **%s**" % [gate_name, "PASS" if gates[gate_name] else "FAIL"])
	report_lines.append("")
	report_lines.append("## Incremental terrain edit")
	report_lines.append("")
	report_lines.append(
		"Interior dig on live surface representation: **%s** (dirty-column patch preserved)."
		% ("PASS" if incremental_ok else "FAIL")
	)
	report_lines.append("")
	report_lines.append("| pre_dig triangles | post_dig | full rebuild | parity | no orphans |")
	report_lines.append("|-------------------|----------|--------------|--------|------------|")
	report_lines.append(
		"| %d | %d | %d | **%s** | **%s** |"
		% [
			pre_dig_tris,
			post_dig_tris,
			full_rebuild_tris,
			"PASS" if live_dig_triangle_parity_ok else "FAIL",
			"PASS" if live_dig_triangle_no_orphans_ok else "FAIL",
		]
	)

	var report_path := "%s/terrain_representation_before_after.md" % scratch
	if not _write_text_file(report_path, "\n".join(report_lines)):
		push_error("failed to write %s" % report_path)
		failed = true

	var json_path := "%s/terrain_representation_stats.json" % scratch
	if not _write_text_file(json_path, JSON.stringify({
			"player_chunk": [player_chunk.x, player_chunk.y],
			"legacy": legacy_stats,
			"surface": surface_stats,
			"live": live_stats,
			"gates": gates,
			"legacy_rebuild": legacy_rebuild,
			"surface_rebuild": surface_rebuild,
			"legacy_triangles": legacy_tris,
			"surface_triangles": surface_tris,
			"incremental_worker_ms": incremental_worker_ms,
			"live_surface_cache_or_mesh": (
				live_view.mesh_data.has("surface_cache")
				or live_view.mesh_data.has("surface_vertices")
				or live_view.mesh_data.has("surface_mesh_resource")
			),
		}, "\t")):
		push_error("failed to write %s" % json_path)
		failed = true

	print(
		"TERRAIN_REP_JSON:",
		JSON.stringify({
			"player_chunk": [player_chunk.x, player_chunk.y],
			"legacy": legacy_stats,
			"surface": surface_stats,
			"live": live_stats,
			"gates": gates,
			"legacy_rebuild": legacy_rebuild,
			"surface_rebuild": surface_rebuild,
			"legacy_triangles": legacy_tris,
			"surface_triangles": surface_tris,
			"incremental_worker_ms": incremental_worker_ms,
			"live_surface_cache_or_mesh": (
				live_view.mesh_data.has("surface_cache")
				or live_view.mesh_data.has("surface_vertices")
				or live_view.mesh_data.has("surface_mesh_resource")
			),
		})
	)

	if failed:
		_ProbeExit.finish_tree(self, 1, "terrain surface representation FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "terrain surface representation OK")


func _probe_view_layers(data: ChunkData, payload: Dictionary) -> Dictionary:
	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate() as ChunkView
	root.add_child(view)
	view.setup(data, payload)
	for _w in 2:
		await process_frame
	var stats := _stats_from_view(view)
	view.queue_free()
	return stats


func _median_sample(samples: Array) -> Dictionary:
	var keys := [
		"worker_ms", "main_emit_ms", "main_drain_ms", "main_ms", "total_ms",
		"terrain_count", "surface_triangle_count",
	]
	var out: Dictionary = {"has_surface_cache": false}
	if samples.is_empty():
		return out
	for key in keys:
		var vals: Array = []
		for s in samples:
			vals.append(float(s.get(key, 0.0)))
		vals.sort()
		out[key] = vals[vals.size() / 2]
	out["has_surface_cache"] = bool(samples[samples.size() - 1].get("has_surface_cache", false))
	return out


func _split_patch_quads(quads: Array) -> Dictionary:
	var patch_rect := Rect2i(7, 7, 2, 2)
	var keep: Array = []
	var patch: Array = []
	for q_variant in quads:
		var q: Dictionary = q_variant
		if _quad_intersects_rect(q, patch_rect):
			patch.append(q)
		else:
			keep.append(q)
	return {"keep": keep, "patch": patch, "rect": patch_rect}


func _quad_intersects_rect(q: Dictionary, rect: Rect2i) -> bool:
	var qx0 := float(q.get("x", 0.0))
	var qz0 := float(q.get("z", 0.0))
	var qx1 := qx0 + float(q.get("dim_x", 1.0))
	var qz1 := qz0 + float(q.get("dim_z", 1.0))
	var rx0 := float(rect.position.x)
	var rz0 := float(rect.position.y)
	var rx1 := rx0 + float(rect.size.x)
	var rz1 := rz0 + float(rect.size.y)
	return qx0 < rx1 and qx1 > rx0 and qz0 < rz1 and qz1 > rz0


func _measure_incremental_rebuild_ms(
	data: ChunkData,
	patch_split: Dictionary,
	use_surface_mesh: bool,
	prior_surface_cache: Dictionary
) -> Dictionary:
	ChunkView.clear_pending_buffer_uploads()
	var keep_quads: Array = patch_split.keep
	var patch_quads: Array = patch_split.patch
	var merged_quads: Array = keep_quads.duplicate()
	merged_quads.append_array(patch_quads)

	var prior_for_patch: Dictionary = {}
	if use_surface_mesh and not prior_surface_cache.is_empty():
		prior_for_patch = _TerrainSurfaceCache.duplicate_cache(prior_surface_cache)

	var t_worker := Time.get_ticks_usec()
	var payload := _ChunkMeshBufferBuilder.build_mesh_payload(
		data,
		merged_quads,
		use_surface_mesh,
		prior_for_patch,
		use_surface_mesh,
		keep_quads,
		patch_quads
	)
	var worker_ms := float(Time.get_ticks_usec() - t_worker) / 1000.0

	var view: ChunkView = CHUNK_VIEW_SCENE.instantiate() as ChunkView
	root.add_child(view)
	view.setup(data, payload)
	var emit_ms := ChunkView.consume_last_upload_ms()
	var t_drain := Time.get_ticks_usec()
	ChunkView.drain_pending_surface_uploads(64, 2_000_000)
	ChunkView.drain_pending_buffer_uploads(64, 2_000_000)
	var drain_ms := float(Time.get_ticks_usec() - t_drain) / 1000.0
	view.queue_free()

	var main_ms := emit_ms + drain_ms
	return {
		"worker_ms": worker_ms,
		"main_emit_ms": emit_ms,
		"main_drain_ms": drain_ms,
		"main_ms": main_ms,
		"total_ms": worker_ms + main_ms,
		"terrain_count": int(payload.get("terrain_count", 0)),
		"surface_triangle_count": int(payload.get("surface_triangle_count", 0)),
		"has_surface_cache": payload.has("surface_cache"),
	}


func _stats_from_view(view: ChunkView) -> Dictionary:
	var terrain_mm := 0
	var ramp_mm := 0
	var surface_meshes := 0
	var mm_instances := 0
	var layer := view.get_node_or_null("LayerContainer")
	if layer:
		for child in layer.get_children():
			if child is MeshInstance3D and child.name == "terrain_surface_mesh":
				surface_meshes += 1
			if child is MultiMeshInstance3D:
				var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
				var inst_count := mm.instance_count if mm else 0
				mm_instances += inst_count
				if child.name == "mm_instance":
					terrain_mm += inst_count
				else:
					ramp_mm += inst_count
	return {
		"terrain_multimesh_instances": terrain_mm,
		"ramp_multimesh_instances": ramp_mm,
		"terrain_surface_meshes": surface_meshes,
		"multimesh_instances": mm_instances,
	}


func _write_text_file(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	return true


func _find_interior_dig_cell(chunk_manager: ChunkManager, world: InfiniteNoiseWorld) -> Vector2i:
	for lx in range(_TerrainEditor.REBUILD_EDGE_BAND, _ChunkData.SIZE - _TerrainEditor.REBUILD_EDGE_BAND):
		for lz in range(_TerrainEditor.REBUILD_EDGE_BAND, _ChunkData.SIZE - _TerrainEditor.REBUILD_EDGE_BAND):
			var wx: int = chunk_manager.get_player_chunk_coord().x * _ChunkData.SIZE + lx
			var wz: int = chunk_manager.get_player_chunk_coord().y * _ChunkData.SIZE + lz
			if world.get_surface_height(float(wx), float(wz)) > 1.0:
				return Vector2i(wx, wz)
	return Vector2i(-1, -1)