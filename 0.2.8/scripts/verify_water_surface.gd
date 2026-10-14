extends SceneTree
## Water tops must draw with the wave shader on the chunk mesh, and water_time
## on that material must move when VoxelFluidService._process runs (including
## the sleep path). A shader file that nothing draws does not count.
## Usage: godot --headless -s scripts/verify_water_surface.gd

const _Builder = preload("res://helpers/chunk_surface_mesh_builder.gd")
const _WaterSurface = preload("res://helpers/water_surface.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _FluidService = preload("res://fluids/voxel_fluid_service.gd")
const _CHUNK_VIEW_SCENE: PackedScene = preload("res://scenes/ChunkView.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var shader := load("res://shaders/water_surface.gdshader") as Shader
	if shader == null:
		push_error("water surface shader failed to load")
		quit(1)
		return
	var src := shader.code
	if "sin(along * 1.5 + water_time * 2.5)" not in src or "crest * 0.12" not in src:
		push_error("water shader does not wave from water_time")
		failed = true
	elif "UV2" not in src or "flow_dir" not in src:
		push_error("water shader does not read flow")
		failed = true
	else:
		print("OK water shader waves and reads flow")

	_ChannelRegistry.reset()
	# Column (4, 7) flows south. (2, 2) has no channel, so its UV2 stays zero.
	_ChannelRegistry.register_channel(4, 7, Vector2i(0, 1), 1.0)

	var data := ChunkData.new(Vector2i(0, 0), null)
	var quads: Array = [
		{"x": 1, "y": 4.0, "z": 1, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "uv_w": 1.0, "uv_h": 1.0, "type": _VoxelTypes.GRASSLAND, "face_code": 0},
		{"x": 4, "y": 3.0, "z": 7, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "uv_w": 1.0, "uv_h": 1.0, "type": _VoxelTypes.WATER, "face_code": 0},
		{"x": 4, "y": 2.0, "z": 7, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "uv_w": 1.0, "uv_h": 1.0, "type": _VoxelTypes.WATER, "face_code": 3},
		{"x": 2, "y": 3.0, "z": 2, "dim_x": 1.0, "dim_y": 1.0, "dim_z": 1.0, "uv_w": 1.0, "uv_h": 1.0, "type": _VoxelTypes.RIVER, "face_code": 0},
	]
	var built := _Builder.build_surface_arrays(data, quads)
	var mesh := _Builder.build_array_mesh(built)
	if mesh.get_surface_count() < 1:
		push_error("surface builder did not emit a mesh")
		quit(1)
		return

	var prebuilt := _mount_view({
		"count": 4,
		"representation": "surface_mesh",
		"surface_mesh_resource": mesh,
	})
	if not _assert_drawn(prebuilt, "prebuilt"):
		failed = true

	var drained := _mount_view({
		"count": 4,
		"representation": "surface_mesh",
		"surface_cache": {
			"materialized": true,
			"vertices": built.vertices,
			"normals": built.normals,
			"uvs": built.uvs,
			"colors": built.colors,
			"indices": built.indices,
			"triangle_count": built.triangle_count,
		},
	})
	ChunkView.drain_pending_surface_uploads(8, 2_000_000)
	if not _assert_drawn(drained, "drain"):
		failed = true

	var water_mi := drained.get_node_or_null("LayerContainer/water_surface_mesh") as MeshInstance3D
	var drawn := water_mi.material_override as ShaderMaterial if water_mi != null else null
	if drawn == null:
		push_error("drain path did not bind a water material")
		failed = true
	else:
		var svc := _FluidService.new()
		svc.set_process(false)
		root.add_child(svc)
		await process_frame
		if svc._water_engine == null:
			push_error("fluid service did not start")
			failed = true
		else:
			var before: float = float(drawn.get_shader_parameter("water_time"))
			# No dirty cells: the sim sleeps. The drawn material must still advance.
			svc._process(0.5)
			var after: float = float((water_mi.material_override as ShaderMaterial).get_shader_parameter("water_time"))
			if after < before + 0.45:
				push_error("water_time on the drawn material did not advance (%s -> %s)" % [before, after])
				failed = true
			else:
				print("OK water_time bound on drawn material (%s -> %s)" % [before, after])
		svc.queue_free()

	if failed:
		quit(1)
		return
	print("All water surface tests OK")
	quit(0)


func _mount_view(mesh_data: Dictionary) -> ChunkView:
	var view := _CHUNK_VIEW_SCENE.instantiate() as ChunkView
	root.add_child(view)
	view.setup(ChunkData.new(Vector2i(0, 0), null), mesh_data)
	return view


func _assert_drawn(view: ChunkView, label: String) -> bool:
	var water_mi := view.get_node_or_null("LayerContainer/water_surface_mesh") as MeshInstance3D
	if water_mi == null or water_mi.mesh == null:
		push_error("%s did not draw a water mesh" % label)
		return false
	var drawn := water_mi.material_override as ShaderMaterial
	if drawn == null or drawn != _WaterSurface.shared_material():
		push_error("%s water material is not the shared surface material" % label)
		return false
	if drawn.shader == null or drawn.shader.resource_path != "res://shaders/water_surface.gdshader":
		push_error("%s shader is not water_surface" % label)
		return false
	var terrain := view.get_node_or_null("LayerContainer/terrain_surface_mesh") as MeshInstance3D
	if terrain == null or terrain.material_override == drawn:
		push_error("%s terrain is using the water material" % label)
		return false
	if _count_water_tops(terrain.mesh as ArrayMesh) != 0:
		push_error("%s still draws water tops on the terrain mesh" % label)
		return false
	var arrays: Array = (water_mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	if verts.size() != 8 or uv2.size() != 8:
		push_error("%s water mesh has %d verts / %d flow uvs" % [label, verts.size(), uv2.size()])
		return false
	var flowed := 0
	var still := 0
	for i in verts.size():
		if verts[i].x > 7.0:
			if absf(uv2[i].x) > 0.01 or absf(uv2[i].y - 1.0) > 0.01:
				push_error("%s flow uv %s at %s" % [label, uv2[i], verts[i]])
				return false
			flowed += 1
		else:
			if uv2[i].length_squared() > 0.0001:
				push_error("%s invented flow %s where the sim has none" % [label, uv2[i]])
				return false
			still += 1
	if flowed != 4 or still != 4:
		push_error("%s split flowed=%d still=%d" % [label, flowed, still])
		return false
	print("OK %s mesh uses water_surface (flow south, still cell has no flow)" % label)
	return true


func _count_water_tops(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() < 1:
		return 0
	var arrays: Array = mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := 0
	var i := 0
	while i < indices.size():
		var vi := int(indices[i])
		var ax := int(round(colors[vi].r * 255.0))
		var ay := int(round(colors[vi].g * 255.0))
		if normals[vi].y > 0.9 and ((ax == 0 and ay == 0) or (ax == 1 and ay == 0)):
			n += 1
		i += 3
	return n
