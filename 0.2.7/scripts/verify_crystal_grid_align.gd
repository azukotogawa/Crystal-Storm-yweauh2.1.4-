extends SceneTree
## Regression: crystal fluid voxels align with terrain column_to_world scale.


const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var ws = _WorldSettings.get_active()
	if is_equal_approx(ws.voxel_scale, 1.0):
		push_error("test expects voxel_scale > 1 (default 2.0)")
		failed = true

	var layer_script: GDScript = load("res://crystal/crystal_chunk_layer.gd") as GDScript
	layer_script.reload()
	var layer: Node3D = layer_script.new()
	var root3d := Node3D.new()
	root.add_child(root3d)
	root3d.add_child(layer)
	layer.setup(Vector2i(1, -2), null)
	await process_frame

	var expected_chunk_x: float = ws.column_to_world(float(ChunkData.SIZE))
	var expected_chunk_z: float = ws.column_to_world(float(-2 * ChunkData.SIZE))
	if not is_equal_approx(layer.position.x, expected_chunk_x):
		push_error("chunk layer X anchor got=%s expected=%s" % [layer.position.x, expected_chunk_x])
		failed = true
	elif not is_equal_approx(layer.position.z, expected_chunk_z):
		push_error("chunk layer Z anchor got=%s expected=%s" % [layer.position.z, expected_chunk_z])
		failed = true
	else:
		print("OK crystal chunk anchor uses column_to_world")

	var cell := _CrystalCell.new(Vector2i(5, 7), 10.0, 1.2, 0)
	layer.rebuild([cell])
	await process_frame

	var mm: MultiMeshInstance3D = layer.get_node_or_null("CrystalFluid") as MultiMeshInstance3D
	if mm == null or mm.multimesh == null or mm.multimesh.instance_count < 1:
		push_error("crystal layer missing multimesh")
		failed = true
	else:
		print("OK crystal multimesh instances=%d" % mm.multimesh.instance_count)

	var layer_src := layer_script.source_code
	if "column_to_world" not in layer_src or "voxel_s" not in layer_src:
		push_error("crystal_chunk_layer must scale fluid cells with column_to_world + voxel_scale")
		failed = true
	else:
		print("OK crystal_chunk_layer source has scaled grid math")

	root3d.queue_free()
	if failed:
		print("Crystal grid align tests FAILED")
		quit(1)
		return
	print("All crystal grid align tests OK")
	quit(0)