extends SceneTree


const _Types = preload("res://helpers/voxel_types.gd")
const _Border = preload("res://helpers/world_border.gd")
const _Edits = preload("res://world/terrain_edits.gd")

const _ATLAS := "res://assets/tiles/Cube.png"
const _SHADER := "res://shaders/ChunkView.gdshader"
const _WORLD_SCRIPT := "res://world/InfiniteNoiseWorld.gd"


var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_Edits.reset()
	_load_assets()
	_faces_and_luma()
	_rim_mesh()
	if _failed == 0:
		print("WORLD BORDER ART OK")
		quit(0)
	else:
		push_error("verify_world_border_art: %d failure(s)" % _failed)
		quit(1)


func _load_assets() -> void:
	for path in [_ATLAS, _SHADER, _WORLD_SCRIPT, "res://helpers/world_border.gd"]:
		if not ResourceLoader.exists(path):
			_fail("missing %s" % path)
			continue
		var res = ResourceLoader.load(path)
		if res == null:
			_fail("import failed %s" % path)
		else:
			print("OK import %s type=%s" % [path, res.get_class()])


func _faces_and_luma() -> void:
	var tex: Texture2D = load(_ATLAS)
	if tex == null:
		_fail("atlas texture did not load")
		return
	var img := tex.get_image()
	if img == null or img.get_width() < 7 or img.get_height() < 10:
		_fail("atlas image missing")
		return
	var cols := _Types.ATLAS_GRID_COLUMNS
	var rows := _Types.ATLAS_GRID_ROWS
	var tw := img.get_width() / cols
	var th := img.get_height() / rows
	print("ATLAS size=%dx%d grid=%dx%d cell=%dx%d" % [img.get_width(), img.get_height(), cols, rows, tw, th])
	if img.get_width() != cols * _Types.ATLAS_TILE_PIXELS or img.get_height() != rows * _Types.ATLAS_TILE_PIXELS:
		_fail("atlas is not %dpx cells" % _Types.ATLAS_TILE_PIXELS)
	var ocean_top := _Types.face_atlas(_Types.OCEAN, 0, 4, -12)
	var ocean_side := _Types.face_atlas(_Types.OCEAN, 3, 4, -12)
	var peak_top := _Types.face_atlas(_Types.MOUNTAIN3, 0, 4, 900)
	var peak_side := _Types.face_atlas(_Types.MOUNTAIN3, 4, 4, 900)
	var grass_top := _Types.face_atlas(_Types.GRASSLAND, 0, 4, 3)
	print(
		"FACES ocean_top=%s ocean_side=%s peak_top=%s peak_side=%s grass_top=%s"
		% [ocean_top, ocean_side, peak_top, peak_side, grass_top]
	)
	if not _in_set(ocean_top, _Types.OCEAN_VARIANTS) or not _in_set(ocean_side, _Types.OCEAN_VARIANTS):
		_fail("ocean faces left the ocean atlas set")
	if not _in_set(peak_top, _Types.STONE_VARIANTS) or not _in_set(peak_side, _Types.STONE_VARIANTS):
		_fail("mountain faces left the stone atlas set")
	if ocean_top == peak_top and ocean_side == peak_side:
		_fail("ocean and mountain faces share both atlas cells")
	var ocean_l := _luma(img, ocean_top, tw, th)
	var peak_l := _luma(img, peak_top, tw, th)
	var grass_l := _luma(img, grass_top, tw, th)
	var spread_peak := absf(ocean_l - peak_l)
	var spread_grass := absf(ocean_l - grass_l)
	print(
		"LUMA ocean=%.3f mountain=%.3f grass=%.3f spread_ocean_mountain=%.3f spread_ocean_grass=%.3f"
		% [ocean_l, peak_l, grass_l, spread_peak, spread_grass]
	)
	if spread_peak < 0.04:
		_fail("ocean and mountain atlas cells are too close in luminance (%.3f)" % spread_peak)
	if spread_grass < 0.04:
		_fail("ocean and grass atlas cells are too close in luminance (%.3f)" % spread_grass)


func _in_set(cell: Vector2i, cells: Array) -> bool:
	return cell in cells


func _luma(img: Image, cell: Vector2i, tw: int, th: int) -> float:
	var ox := cell.x * tw
	var oy := cell.y * th
	var sum := 0.0
	var n := 0
	for y in range(1, th - 1):
		for x in range(1, tw - 1):
			sum += img.get_pixel(ox + x, oy + y).get_luminance()
			n += 1
	if n == 0:
		return 0.0
	return sum / float(n)


func _rim_mesh() -> void:
	var world := InfiniteNoiseWorld.new()
	world.apply_seed(12349)
	root.add_child(world)
	var half := float(_Border.PLAYABLE_HALF_X)
	var pts: Array[Vector3] = []
	for i in 24:
		var z := -180.0 + float(i) * 16.0
		var edge := Vector2(half, z)
		var inland := Vector2(half - 8.0, z)
		var he := world.get_surface_height_uncached(edge.x, edge.y)
		var hi := world.get_surface_height_uncached(inland.x, inland.y)
		pts.append(Vector3(edge.x, he, edge.y))
		pts.append(Vector3(inland.x, hi, inland.y))
	var z_edge := half
	var crest := world.get_surface_height_uncached(40.0, z_edge)
	var foot := world.get_surface_height_uncached(40.0, z_edge - 6.0)
	var sea := world.get_surface_height_uncached(half, 40.0)
	var shore := world.get_surface_height_uncached(half - 10.0, 40.0)
	print(
		"HEIGHTS seed=12349 ocean_edge=%.2f shore=%.2f mountain_edge=%.2f foothill=%.2f cliff=%.2f"
		% [sea, shore, crest, foot, crest - foot]
	)
	if sea > _Border.OCEAN_EDGE_MAX:
		_fail("art ocean edge height %.2f" % sea)
	if crest < _Border.MOUNTAIN_EDGE_MIN:
		_fail("art mountain edge height %.2f" % crest)
	if crest - foot < 12.0:
		_fail("art cliff %.2f is shorter than a jump" % (crest - foot))
	pts.append(Vector3(40.0, crest, z_edge))
	pts.append(Vector3(40.0, foot, z_edge - 6.0))
	pts.append(Vector3(half, sea, 40.0))
	pts.append(Vector3(half - 10.0, shore, 40.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, pts.size() - 2, 2):
		st.set_color(Color(0.15, 0.35, 0.55))
		st.add_vertex(pts[i])
		st.add_vertex(pts[i + 1])
		st.add_vertex(pts[i + 2])
	var mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.name = "RimStrip"
	inst.mesh = mesh
	root.add_child(inst)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var aabb := mesh.get_aabb()
	print(
		"MESH vertices=%d surfaces=%d aabb_y=%.2f nodes=%d"
		% [verts.size(), mesh.get_surface_count(), aabb.size.y, root.get_child_count()]
	)
	if verts.size() < 12:
		_fail("rim mesh has too few vertices")
	if aabb.size.y < 12.0:
		_fail("rim mesh is flat (height span %.2f)" % aabb.size.y)
	world.queue_free()
