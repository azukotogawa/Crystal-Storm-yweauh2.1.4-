extends SceneTree
## Structural: chunk mesh uses unified mesh_groups (no overlay ramp buffer split).


const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
const _VoxelGeometryKind = preload("res://helpers/voxel_geometry_kind.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var view_src := (load("res://chunks/chunk_view.gd") as GDScript).source_code
	var builder_src := (load("res://chunks/chunk_mesh_buffer_builder.gd") as GDScript).source_code

	if "terrain_buffer" in builder_src or "ramp_buffer" in builder_src:
		push_error("chunk_mesh_buffer_builder must not split overlay ramp buffers")
		failed = true
	else:
		print("OK builder has no overlay buffer keys")

	if "_emit_ramp_multimesh" in view_src or "_shared_ramp_material" in view_src:
		push_error("chunk_view must not use overlay ramp multimesh path")
		failed = true
	else:
		print("OK chunk_view has no overlay ramp path")

	if "mesh_groups" not in builder_src or "_upload_mesh_groups" not in view_src:
		push_error("unified mesh_groups upload path missing")
		failed = true
	else:
		print("OK unified mesh_groups path present")

	var data := ChunkData.new(Vector2i(0, 0))
	var payload: Dictionary = _ChunkMeshBufferBuilder.build_mesh_payload(data, [])
	if not payload.has("mesh_groups"):
		push_error("payload missing mesh_groups")
		failed = true
	elif payload.get("mesh_groups", []).size() != 0:
		push_error("empty quads should yield empty mesh_groups")
		failed = true
	else:
		print("OK empty payload mesh_groups")

	if failed:
		quit(1)
	print("All voxel geometry path tests OK")
	quit(0)