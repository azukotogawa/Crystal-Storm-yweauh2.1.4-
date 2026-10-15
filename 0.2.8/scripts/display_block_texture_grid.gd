extends SceneTree
## Windowed terrain shot at the game camera (ortho 16, iso pitch).


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const CLEAR := Color(1.0, 0.0, 1.0)
const CELLS := 6


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		push_error("display grid probe needs a window")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(640, 480))
	DisplayServer.window_set_title("Crystal Storm block texture grid")
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = CLEAR
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)

	var scale: float = _WorldSettings.get_active().voxel_scale
	var atlas := load(_VoxelTypes.ATLAS_TEXTURE_PATH) as Texture2D
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ChunkSurfaceMesh.gdshader")
	mat.set_shader_parameter("texture_atlas", atlas)
	mat.set_shader_parameter("atlas_grid", Vector2(_VoxelTypes.ATLAS_GRID_COLUMNS, _VoxelTypes.ATLAS_GRID_ROWS))

	var grass := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND)
	var mesh := _top_grid(scale, grass)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = mat
	root.add_child(body)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.current = true
	var center := Vector3(scale * float(CELLS) * 0.5, 0.0, scale * float(CELLS) * 0.5)
	var yaw := deg_to_rad(45.0)
	var hdist := 100.0 * sqrt(2.0)
	cam.position = center + Vector3(sin(yaw) * hdist, 101.0, cos(yaw) * hdist)
	cam.rotation_degrees = Vector3(-35.264, 45.0, 0.0)
	root.add_child(cam)

	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot: Image = root.get_texture().get_image()
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "D:/csmerge/verify-scratch/grid-probe"
	DirAccess.make_dir_recursive_absolute(scratch)
	var path := scratch.path_join("block_texture_grid.png")
	shot.save_png(path)
	var seams := _count_fallback(shot)
	print(
		"SHOT %s size %dx%d terrain %d fallback %d"
		% [path, shot.get_width(), shot.get_height(), seams.terrain, seams.fallback]
	)
	if seams.terrain < 1000 or float(seams.fallback) / float(seams.terrain) > 0.08:
		push_error("visible block grid fallback=%d terrain=%d" % [seams.fallback, seams.terrain])
		quit(1)
		return
	print("Block texture grid render OK")
	quit(0)


func _top_grid(scale: float, atlas: Vector2i) -> ArrayMesh:
	var n := CELLS * CELLS
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(n * 4)
	norms.resize(n * 4)
	uvs.resize(n * 4)
	colors.resize(n * 4)
	indices.resize(n * 6)
	var tint := Color(float(atlas.x) / 255.0, float(atlas.y) / 255.0, 0.96, 1.0)
	var q := 0
	for z in CELLS:
		for x in CELLS:
			var ox := float(x) * scale
			var oz := float(z) * scale
			var vi := q * 4
			var ii := q * 6
			verts[vi + 0] = Vector3(ox, 0.0, oz)
			verts[vi + 1] = Vector3(ox + scale, 0.0, oz)
			verts[vi + 2] = Vector3(ox + scale, 0.0, oz + scale)
			verts[vi + 3] = Vector3(ox, 0.0, oz + scale)
			for k in 4:
				norms[vi + k] = Vector3.UP
				colors[vi + k] = tint
			uvs[vi + 0] = Vector2(0.0, 0.0)
			uvs[vi + 1] = Vector2(1.0, 0.0)
			uvs[vi + 2] = Vector2(1.0, 1.0)
			uvs[vi + 3] = Vector2(0.0, 1.0)
			indices[ii + 0] = vi
			indices[ii + 1] = vi + 1
			indices[ii + 2] = vi + 2
			indices[ii + 3] = vi
			indices[ii + 4] = vi + 2
			indices[ii + 5] = vi + 3
			q += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _count_fallback(img: Image) -> Dictionary:
	var terrain := 0
	var fallback := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.r > 0.85 and p.b > 0.85 and p.g < 0.25:
				continue
			terrain += 1
			if absf(p.r - 0x9e / 255.0) < 0.04 and absf(p.g - 0xab / 255.0) < 0.04 and absf(p.b - 0x7f / 255.0) < 0.04:
				fallback += 1
	return {"terrain": terrain, "fallback": fallback}
