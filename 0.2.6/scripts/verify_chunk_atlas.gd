extends SceneTree
## Regression: ChunkView material must use Cube.png 7×10 atlas; mesh buffers carry varied tile coords.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkMaterial: ShaderMaterial = preload("res://shaders/ChunkView.tres")
const _CHUNK_VIEW_SCENE: PackedScene = preload("res://scenes/ChunkView.tscn")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var atlas_tex: Texture2D = _ChunkMaterial.get_shader_parameter("texture_atlas") as Texture2D
	if atlas_tex == null:
		push_error("ChunkView.tres missing texture_atlas")
		failed = true
	elif "Cube.png" not in atlas_tex.resource_path:
		push_error("ChunkView.tres must bind Cube.png atlas, got %s" % atlas_tex.resource_path)
		failed = true
	else:
		print("OK ChunkView atlas=%s" % atlas_tex.resource_path)
	var atlas_img: Image = Image.load_from_file(_VoxelTypes.ATLAS_TEXTURE_PATH)
	if atlas_img == null or atlas_img.is_empty():
		push_error("Cube.png image unavailable for atlas detail check")
		failed = true
	else:
		var grass_colors: Dictionary = {}
		var tw: int = _VoxelTypes.ATLAS_TILE_PIXELS
		var grass_coord: Vector2i = _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND)
		for py in tw:
			for px in tw:
				var c: Color = atlas_img.get_pixel(
					grass_coord.x * tw + px,
					grass_coord.y * tw + py
				)
				grass_colors[c.to_html(false)] = true
		if grass_colors.size() < 4:
			push_error("grass atlas tile must have pixel variation, got %d colors" % grass_colors.size())
			failed = true
		elif grass_colors.size() > 24:
			push_error("grass atlas tile too noisy, got %d colors (want 4-24)" % grass_colors.size())
			failed = true
		else:
			print("OK grass tile pixel colors=%d" % grass_colors.size())

	var grid: Vector2 = _ChunkMaterial.get_shader_parameter("atlas_grid")
	if grid != _VoxelTypes.atlas_grid_vec2():
		push_error("atlas_grid mismatch: material %s vs VoxelTypes %s" % [grid, _VoxelTypes.atlas_grid_vec2()])
		failed = true
	else:
		print("OK atlas_grid=%s" % grid)

	var grass := _VoxelTypes.get_atlas_coord(_VoxelTypes.GRASSLAND)
	var stone := _VoxelTypes.get_atlas_coord(_VoxelTypes.STONE)
	var snow := _VoxelTypes.get_atlas_coord(_VoxelTypes.SNOW)
	var dirt := _VoxelTypes.get_atlas_coord(_VoxelTypes.DIRT)
	if grass == stone or grass == snow or stone == snow or dirt == grass:
		push_error("biome atlas coords must differ grass=%s stone=%s snow=%s dirt=%s" % [grass, stone, snow, dirt])
		failed = true
	else:
		print("OK biome coords grass=%s stone=%s snow=%s dirt=%s" % [grass, stone, snow, dirt])

	var grass_top := _VoxelTypes.get_atlas_coord_for_face(_VoxelTypes.GRASSLAND3, 0)
	var grass_side := _VoxelTypes.get_atlas_coord_for_face(_VoxelTypes.GRASSLAND3, 3)
	var grass_bottom := _VoxelTypes.get_atlas_coord_for_face(_VoxelTypes.GRASSLAND3, 2)
	if grass_top == grass_side or grass_top == grass_bottom:
		push_error("grass block faces must differ top=%s side=%s bottom=%s" % [grass_top, grass_side, grass_bottom])
		failed = true
	else:
		print("OK minecraft grass faces top=%s side=%s bottom=%s" % [grass_top, grass_side, grass_bottom])

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	var data := _ChunkData.new(Vector2i(0, 0), world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	data.tile_map[0][0] = _VoxelTypes.GRASSLAND3
	data.tile_map[7][7] = _VoxelTypes.MOUNTAIN2
	data.tile_map[15][15] = _VoxelTypes.SNOW

	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	var atlas_keys: Dictionary = {}
	for q in quads:
		var coord: Vector2i = _VoxelTypes.get_atlas_coord(int(q.get("type", -1)))
		atlas_keys["%d,%d" % [coord.x, coord.y]] = true
	if atlas_keys.size() < 2:
		push_error("mesh quads should use multiple atlas cells, got %d" % atlas_keys.size())
		failed = true
	else:
		print("OK mesh atlas cells=%d from %d quads" % [atlas_keys.size(), quads.size()])

	var view: ChunkView = _CHUNK_VIEW_SCENE.instantiate() as ChunkView
	var root3d := Node3D.new()
	root.add_child(root3d)
	root3d.add_child(view)
	view.setup(data, mesh)
	await process_frame
	var mm: MultiMeshInstance3D = view.get_node_or_null("LayerContainer/mm_instance") as MultiMeshInstance3D
	if mm == null or mm.multimesh == null or mm.multimesh.instance_count <= 0:
		push_error("ChunkView failed to emit textured multimesh")
		failed = true
	elif not mm.material_override is ShaderMaterial:
		push_error("terrain multimesh missing ShaderMaterial")
		failed = true
	else:
		var mat := mm.material_override as ShaderMaterial
		var bound: Texture2D = mat.get_shader_parameter("texture_atlas") as Texture2D
		if bound == null:
			push_error("runtime chunk material lost texture_atlas")
			failed = true
		else:
			print("OK ChunkView multimesh instances=%d material bound" % mm.multimesh.instance_count)

	root3d.queue_free()

	var world_gen = load("res://world/InfiniteNoiseWorld.gd").new()
	world_gen.world_seed = 12345
	var biome_tiles: Dictionary = {}
	for coord in [Vector2i(0, 0), Vector2i(3, -2), Vector2i(-2, 4), Vector2i(5, 5)]:
		var gen_data := _ChunkData.new(coord, world_gen)
		gen_data.capture_worker_snapshot()
		gen_data._compute_column_maps(true)
		for gx in _ChunkData.SIZE:
			for gz in _ChunkData.SIZE:
				var tid: int = gen_data.get_tile_type(gx, gz)
				if tid != _VoxelTypes.AIR:
					biome_tiles[tid] = true
	if biome_tiles.size() < 3:
		push_error("worldgen should scatter >=3 surface tile types across chunks, got %d" % biome_tiles.size())
		failed = true
	else:
		print("OK worldgen biome tile types=%d" % biome_tiles.size())

	if failed:
		print("Chunk atlas tests FAILED")
		quit(1)
		return
	print("All chunk atlas tests OK")
	quit(0)