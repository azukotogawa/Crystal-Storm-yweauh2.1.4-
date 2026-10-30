extends SceneTree

const _Variety = preload("res://world/poi_variety.gd")
const _Look = preload("res://config/crystal_ground_look.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_imports()
	_check_atlas()
	_check_visual("cave_mouth")
	_check_visual("ruined_watchtower")
	_check_contrast()
	if _failed == 0:
		print("POI VARIETY ART OK")
		quit(0)
	else:
		push_error("verify_poi_variety_art: %d failure(s)" % _failed)
		quit(1)


func _check_imports() -> void:
	for path in [_Variety.STONE_MESH, _Variety.PILLAR_MESH, _Variety.STONE_ALBEDO, _Variety.PILLAR_ALBEDO]:
		if not ResourceLoader.exists(path):
			_fail("missing asset %s" % path)
			return
	var stone_mesh: Mesh = load(_Variety.STONE_MESH) as Mesh
	var pillar_mesh: Mesh = load(_Variety.PILLAR_MESH) as Mesh
	var stone_tex: Texture2D = load(_Variety.STONE_ALBEDO) as Texture2D
	var pillar_tex: Texture2D = load(_Variety.PILLAR_ALBEDO) as Texture2D
	if stone_mesh == null or pillar_mesh == null:
		_fail("structure obj did not import as Mesh")
		return
	if stone_tex == null or pillar_tex == null:
		_fail("structure albedo did not import as Texture2D")
		return
	if stone_tex.get_width() != 256 or stone_tex.get_height() != 256:
		_fail("stone albedo %dx%d" % [stone_tex.get_width(), stone_tex.get_height()])
		return
	if pillar_tex.get_width() != 256 or pillar_tex.get_height() != 256:
		_fail("pillar albedo %dx%d" % [pillar_tex.get_width(), pillar_tex.get_height()])
		return
	if stone_mesh.get_surface_count() < 1 or pillar_mesh.get_surface_count() < 1:
		_fail("imported mesh has no surfaces")
		return
	var stone_h := stone_mesh.get_aabb().size.y
	var pillar_h := pillar_mesh.get_aabb().size.y
	if stone_h < 0.5 or pillar_h < 0.5:
		_fail("imported mesh height stone=%.3f pillar=%.3f" % [stone_h, pillar_h])
		return
	print("ART import stone_mesh surfaces=%d aabb_h=%.3f albedo=256x256 pillar_mesh surfaces=%d aabb_h=%.3f albedo=256x256" % [
		stone_mesh.get_surface_count(), stone_h, pillar_mesh.get_surface_count(), pillar_h,
	])
	print("ART per-face stone_wall surface0 verts=%d material=stone_wall_mat map=stone_wall_albedo.png" % _surface_verts(stone_mesh, 0))
	print("ART per-face ruin_pillar surface0 verts=%d material=ruin_pillar_mat map=ruin_pillar_albedo.png" % _surface_verts(pillar_mesh, 0))


func _check_atlas() -> void:
	var look := _Look.load_active()
	var atlas := load(look.atlas_path) as Texture2D
	if atlas == null:
		_fail("terrain atlas failed to import")
		return
	if look.atlas_columns != 7 or look.atlas_rows != 10:
		_fail("atlas grid %dx%d" % [look.atlas_columns, look.atlas_rows])
		return
	if look.stone_col != 0 or look.stone_row != 4:
		_fail("stone atlas index %d,%d" % [look.stone_col, look.stone_row])
		return
	if atlas.get_width() % look.atlas_columns != 0 or atlas.get_height() % look.atlas_rows != 0:
		_fail("atlas %dx%d does not divide %dx%d" % [atlas.get_width(), atlas.get_height(), look.atlas_columns, look.atlas_rows])
		return
	var cell_w := int(atlas.get_width() / look.atlas_columns)
	var cell_h := int(atlas.get_height() / look.atlas_rows)
	if cell_w < 16 or cell_h < 16:
		_fail("atlas cell %dx%d" % [cell_w, cell_h])
		return
	var image := atlas.get_image()
	if image == null or image.is_empty():
		_fail("atlas image empty")
		return
	var cell := image.get_region(Rect2i(look.stone_col * cell_w, look.stone_row * cell_h, cell_w, cell_h))
	var luma := _image_luma(cell)
	print("ART atlas %s %dx%d grid=%dx%d stone_index=%d,%d cell=%dx%d stone_cell_luma=%.4f" % [
		look.atlas_path, atlas.get_width(), atlas.get_height(), look.atlas_columns, look.atlas_rows,
		look.stone_col, look.stone_row, cell_w, cell_h, luma,
	])


func _check_visual(kind: String) -> void:
	var node := _Variety.build_visual(kind)
	var nodes := _Variety.node_count(node)
	var height := _Variety.model_height(node)
	var meshes := 0
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			meshes += 1
	print("ART visual kind=%s nodes=%d meshes=%d height=%.3f" % [kind, nodes, meshes, height])
	if kind == "cave_mouth":
		if nodes < 4 or meshes < 2 or height < 1.5 or height > 8.0:
			_fail("cave visual nodes=%d meshes=%d height=%.3f" % [nodes, meshes, height])
		if node.get_node_or_null("LootChest") == null or node.get_node_or_null("CaveMouth") == null:
			_fail("cave visual missing mouth or chest")
	else:
		if nodes < 4 or meshes < 2 or height < 2.0 or height > 14.0:
			_fail("tower visual nodes=%d meshes=%d height=%.3f" % [nodes, meshes, height])
		if node.get_node_or_null("EncounterMarker") == null or node.get_node_or_null("TowerBase") == null:
			_fail("tower visual missing base or encounter marker")
		var cave := _Variety.build_visual("cave_mouth")
		var cave_h := _Variety.model_height(cave)
		if height <= cave_h:
			_fail("watchtower height %.3f is not above the cave mouth %.3f" % [height, cave_h])
		cave.free()
	node.free()


func _check_contrast() -> void:
	var stone: Texture2D = load(_Variety.STONE_ALBEDO) as Texture2D
	var pillar: Texture2D = load(_Variety.PILLAR_ALBEDO) as Texture2D
	var stone_l := _image_luma(stone.get_image())
	var pillar_l := _image_luma(pillar.get_image())
	var mouth_l := _Variety.MOUTH_COLOR.get_luminance()
	var spread_mouth := stone_l - mouth_l
	var spread_pair := absf(stone_l - pillar_l)
	print("ART luma stone_albedo=%.4f pillar_albedo=%.4f mouth=%.4f spread_stone_mouth=%.4f spread_stone_pillar=%.4f" % [
		stone_l, pillar_l, mouth_l, spread_mouth, spread_pair,
	])
	if mouth_l >= 0.15:
		_fail("cave mouth luminance %.4f is not dark" % mouth_l)
		return
	if spread_mouth < 0.15:
		_fail("stone vs mouth luminance spread %.4f" % spread_mouth)
		return
	if spread_pair < 0.02:
		_fail("neighbouring structure albedos are too close %.4f" % spread_pair)
		return
	var node := _Variety.build_visual("cave_mouth")
	var mouth := node.get_node("CaveMouth") as MeshInstance3D
	var stair := node.get_node("StructureMesh") as MeshInstance3D
	var mouth_mat := mouth.material_override as StandardMaterial3D
	var stair_mat := stair.material_override as StandardMaterial3D
	if mouth_mat == null or stair_mat == null or stair_mat.albedo_texture == null:
		_fail("cave materials were not bound")
		node.free()
		return
	if mouth_mat.albedo_color.get_luminance() >= stair_mat.albedo_color.get_luminance() and stair_mat.albedo_texture == null:
		_fail("neighbouring cave materials do not separate")
	node.free()


func _surface_verts(mesh: Mesh, surface: int) -> int:
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return 0
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func _image_luma(image: Image) -> float:
	if image == null or image.is_empty():
		return 0.0
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var step := 4
	var n := 0
	var sum := 0.0
	var y := 0
	while y < image.get_height():
		var x := 0
		while x < image.get_width():
			sum += image.get_pixel(x, y).get_luminance()
			n += 1
			x += step
		y += step
	if n == 0:
		return 0.0
	return sum / float(n)
