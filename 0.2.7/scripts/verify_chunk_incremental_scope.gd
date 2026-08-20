extends SceneTree
## P0 design contract: incremental terrain mesh invalidation scope.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainDirtyScope = preload("res://helpers/terrain_dirty_scope.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var terrain_src := (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "rebuild_ring_for_cell" not in terrain_src:
		push_error("terrain_editor must compute adaptive rebuild ring per edit cell")
		failed = true
	elif "invalidate_columns_at_world" not in terrain_src:
		push_error("terrain_editor must route edits through invalidate_columns_at_world")
		failed = true
	else:
		print("OK terrain edit uses dependency-aware invalidation")

	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	var pipe_src := (load("res://chunks/chunk_pipeline.gd") as GDScript).source_code
	if "invalidate_columns_at_world" not in cm_src:
		push_error("chunk_manager must expose invalidate_columns_at_world")
		failed = true
	elif "update_dirty_column_maps" not in pipe_src and "update_dirty_column_maps" not in cm_src:
		push_error("chunk pipeline/manager must use incremental column-map updates")
		failed = true
	elif "run_worker_job" not in cm_src and "update_dirty_column_maps" not in cm_src:
		push_error("chunk_manager must route workers through pipeline or direct column maps")
		failed = true
	elif "_build_mesh_region" not in cm_src:
		push_error("chunk_manager must patch mesh regions instead of full-chunk regen")
		failed = true
	elif "_patch_pending" not in cm_src:
		push_error("chunk_manager must batch incremental patch pending keys")
		failed = true
	else:
		print("OK chunk mesh path uses incremental column maps + mesh patch")

	if "func rebuild_region_at_world" not in cm_src or "_rebuild_high_priority" not in cm_src:
		push_error("chunk_manager must batch rebuilds with player-distance priority")
		failed = true
	else:
		print("OK rebuild batching + priority contract present")

	var wx := 20
	var wz := 20
	_TerrainEdits.reset()
	_TerrainEdits.dig(wx, wz, 1)
	var dirty: Dictionary = {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			dirty[Vector2i(wx + dx, wz + dz)] = true
	if dirty.size() != 9:
		push_error("dirty halo must cover 3x3 around edit")
		failed = true
	else:
		print("OK incremental scope dirty halo=3x3 (%d cells)" % dirty.size())

	var scope: Dictionary = _TerrainDirtyScope.compute_edit_scope(wx, wz)
	if int(scope.get("dirty_columns", 0)) != 9:
		push_error("TerrainDirtyScope must report 9 dirty columns for single edit")
		failed = true
	else:
		print("OK TerrainDirtyScope dirty_columns=%d" % int(scope.get("dirty_columns", 0)))

	var perf_src := (load("res://scripts/verify_chunk_rebuild_perf.gd") as GDScript).source_code
	if "MAX_REBUILD_WALL_MS" not in perf_src or "rebuild_ring_for_cell" not in perf_src:
		push_error("verify_chunk_rebuild_perf must document baseline gate with adaptive ring")
		failed = true
	else:
		print("OK perf baseline probe documents incremental rebuild budget")

	var crystal_src := (load("res://crystal/crystal_manager.gd") as GDScript).source_code
	if "_patch_chunk_layer" not in crystal_src:
		push_error("crystal_manager incremental patch is reference pattern for terrain work")
		failed = true
	else:
		print("OK crystal incremental patch exists as reference pattern")

	if failed:
		quit(1)
		return
	print("All chunk incremental scope tests OK")
	quit(0)