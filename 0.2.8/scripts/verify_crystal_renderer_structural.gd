extends SceneTree

const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_CRYSTAL_RENDERER", "procedural")
	call_deferred("_run")


func _run() -> void:
	var failed := false

	if _CrystalClusterMesh.use_legacy_renderer():
		push_error("procedural renderer env not active")
		failed = true

	var far_tris := _CrystalClusterMesh.triangle_count_for_lod(_CrystalClusterMesh.LOD_FAR)
	var mid_tris := _CrystalClusterMesh.triangle_count_for_lod(_CrystalClusterMesh.LOD_MID)
	var near_tris := _CrystalClusterMesh.triangle_count_for_lod(_CrystalClusterMesh.LOD_NEAR)
	var full_tris := _CrystalClusterMesh.triangle_count_for_lod(_CrystalClusterMesh.LOD_FULL)
	var far_tier := _CrystalClusterMesh.lod_tier_for_chunk_distance(3)
	var near_tier := _CrystalClusterMesh.lod_tier_for_chunk_distance(0)
	if far_tier != _CrystalClusterMesh.LOD_FAR or near_tier != _CrystalClusterMesh.LOD_NEAR:
		push_error("unexpected LOD tier mapping far=%d near=%d" % [far_tier, near_tier])
		failed = true
	if far_tris != 6 or mid_tris != 12 or near_tris != 12 or full_tris != 30:
		push_error("unexpected LOD tri counts: %d %d %d %d" % [far_tris, mid_tris, near_tris, full_tris])
		failed = true
	else:
		print("OK LOD tri counts far=%d mid=%d near=%d full=%d" % [far_tris, mid_tris, near_tris, full_tris])

	var far_mesh := _CrystalClusterMesh.get_mesh_for_lod(_CrystalClusterMesh.LOD_FAR)
	if far_mesh == null or far_mesh.get_surface_count() <= 0:
		push_error("LOD far mesh missing")
		failed = true
	else:
		print("OK procedural cluster mesh built")

	var layer := _CrystalChunkLayer.new()
	layer.setup(Vector2i(0, 0), StandardMaterial3D.new())
	var cells: Array = []
	var cell := CrystalCell.new(Vector2i(3, 4), 10.0, 0.6, 0)
	cell.neighbor_mask = 2
	cells.append(cell)
	layer.rebuild(cells, _CrystalClusterMesh.LOD_NEAR)
	var mm_node: MultiMeshInstance3D = layer.get_node_or_null("CrystalFluid") as MultiMeshInstance3D
	if mm_node == null:
		push_error("CrystalFluid MultiMeshInstance3D missing")
		failed = true
	elif not layer.uses_procedural_mesh():
		push_error("layer should use procedural mesh")
		failed = true
	elif mm_node.multimesh == null or mm_node.multimesh.mesh is BoxMesh:
		push_error("production layer still uses BoxMesh")
		failed = true
	else:
		print("OK CrystalChunkLayer uses procedural cluster instancing")

	if failed:
		_ProbeExit.finish_tree(self, 1, "Crystal renderer structural tests FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All crystal renderer structural tests OK")