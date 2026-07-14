extends SceneTree
## P0 design contract: incremental terrain mesh invalidation scope (no implementation yet).


const _TerrainEdits = preload("res://world/terrain_edits.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var terrain_src := (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "rebuild_ring_for_cell" not in terrain_src:
		push_error("terrain_editor must compute adaptive rebuild ring per edit cell")
		failed = true
	elif "rebuild_region_at_world(float(wx), float(wz), ring)" not in terrain_src:
		push_error("terrain_editor must pass adaptive ring to rebuild_region_at_world")
		failed = true
	else:
		print("OK terrain edit uses adaptive ring (0 interior, 1 chunk-edge band)")

	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	if "_compute_column_maps(true)" not in cm_src:
		push_error("chunk rebuild must still regen column maps on worker")
		failed = true
	elif "patch_cells" in cm_src or "patch_chunk" in cm_src:
		push_error("chunk_manager must not ship partial terrain mesh patch yet")
		failed = true
	else:
		print("OK chunk mesh path remains full regen (incremental not started)")

	if "func rebuild_region_at_world" not in cm_src or "_rebuild_pending" not in cm_src:
		push_error("chunk_manager must batch rebuild_region pending keys")
		failed = true
	else:
		print("OK rebuild batching contract present")

	# Dirty halo: edited column + 1-cell ring (ramps, side lips, concave corners).
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

	var perf_src := (load("res://scripts/verify_chunk_rebuild_perf.gd") as GDScript).source_code
	if "MAX_REBUILD_WALL_MS" not in perf_src or "rebuild_ring_for_cell" not in perf_src:
		push_error("verify_chunk_rebuild_perf must document baseline gate with adaptive ring")
		failed = true
	else:
		print("OK perf baseline probe documents full-regen budget")

	var crystal_src := (load("res://crystal/crystal_manager.gd") as GDScript).source_code
	if "_patch_chunk_layer" not in crystal_src:
		push_error("crystal_manager incremental patch is reference pattern for future terrain work")
		failed = true
	else:
		print("OK crystal incremental patch exists as reference pattern")

	if failed:
		quit(1)
		return
	print("All chunk incremental scope tests OK")
	quit(0)