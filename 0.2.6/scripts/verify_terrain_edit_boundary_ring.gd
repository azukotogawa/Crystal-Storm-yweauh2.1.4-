extends SceneTree
## P0 contract: terrain edits use ring=0 interior, ring=1 near chunk edges (ramp lip halo).


const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var terrain_src := (load("res://world/terrain_editor.gd") as GDScript).source_code
	if "rebuild_ring_for_cell" not in terrain_src:
		push_error("terrain_editor must expose rebuild_ring_for_cell")
		failed = true
	elif "rebuild_region_at_world(float(wx), float(wz), ring)" not in terrain_src:
		push_error("terrain_editor must pass adaptive ring to rebuild_region_at_world")
		failed = true
	else:
		print("OK terrain_editor uses adaptive rebuild ring")

	var cm_src := (load("res://chunks/chunk_manager.gd") as GDScript).source_code
	if "_rebuild_high_priority" not in cm_src:
		push_error("chunk_manager must deprioritize far-chunk rebuilds")
		failed = true
	else:
		print("OK chunk rebuild priority adapts to player distance")

	var interior := Vector2i(8, 8)
	var edge_x := Vector2i(0, 8)
	var edge_z := Vector2i(8, 1)
	var far_edge := Vector2i(_ChunkData.SIZE - 1, 8)
	var neg_edge := Vector2i(-1, 8)

	if _TerrainEditor.rebuild_ring_for_cell(interior.x, interior.y) != 0:
		push_error("interior (%d,%d) must use ring=0" % [interior.x, interior.y])
		failed = true
	else:
		print("OK interior cell ring=0")

	for cell in [edge_x, edge_z, far_edge, neg_edge]:
		if _TerrainEditor.rebuild_ring_for_cell(cell.x, cell.y) != 1:
			push_error("edge (%d,%d) must use ring=1" % [cell.x, cell.y])
			failed = true
	if not failed:
		print("OK edge-band cells ring=1 (band=%d)" % _TerrainEditor.REBUILD_EDGE_BAND)

	if failed:
		quit(1)
		return
	print("All terrain edit boundary ring tests OK")
	quit(0)