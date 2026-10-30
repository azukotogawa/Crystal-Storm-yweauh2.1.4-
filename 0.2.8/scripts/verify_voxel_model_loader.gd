extends SceneTree

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Builder = preload("res://helpers/voxel_model_builder.gd")

const _TREES := [
	["res://assets/voxel/vegetation/tree_oak.json", "tree_oak", 54680, 6051, 48629],
	["res://assets/voxel/vegetation/tree_birch.json", "tree_birch", 27740, 3912, 23828],
	["res://assets/voxel/vegetation/tree_pine.json", "tree_pine", 42832, 4167, 38665],
]

var _failed := false
var _allowed := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_palette()
	_check_units()
	_check_vox_unit()
	var oak_quads := 0
	for spec in _TREES:
		var quads := _check_tree(str(spec[0]), str(spec[1]), int(spec[2]), int(spec[3]), int(spec[4]))
		if str(spec[1]) == "tree_oak":
			oak_quads = quads
	_check_cache("res://assets/voxel/vegetation/tree_oak.json", oak_quads)
	_check_archive_oak()
	if _failed:
		print("VOXEL MODEL LOADER FAIL")
		quit(1)
		return
	print("VOXEL MODEL LOADER OK")
	quit(0)


func _fail(msg: String) -> void:
	_failed = true
	print("FAIL %s" % msg)


func _load_palette() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voxel/palette.json"))
	if typeof(parsed) != TYPE_DICTIONARY or str(parsed.get("format", "")) != "crystalstorm-voxel-palette-v1":
		_fail("shared palette")
		return
	var colors = parsed.get("colors", [])
	if typeof(colors) != TYPE_ARRAY or colors.is_empty():
		_fail("shared palette colors")
		return
	for entry in colors:
		var rgb = entry.get("rgb", [])
		_allowed["%d,%d,%d" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = true
	print("OK shared palette colors=%d" % _allowed.size())


func _check_units() -> void:
	var single := _model([Vector4i(0, 0, 0, 0)], Vector3i(1, 1, 1), Vector3.ZERO)
	var one := _Loader.build_part(single, "")
	if int(one["voxels"]) != 1 or int(one["quads"]) != 6 or _Loader.quad_count(one["mesh"]) != 6:
		_fail("single cell voxels=%s quads=%s" % [one["voxels"], one["quads"]])
	elif (one["mesh"] as ArrayMesh).get_surface_count() != 1:
		_fail("single cell surfaces")
	else:
		print("OK single cell quads=6")
	var pair := _model([Vector4i(0, 0, 0, 0), Vector4i(1, 0, 0, 0)], Vector3i(2, 1, 1), Vector3.ZERO)
	var merged := _Loader.build_part(pair, "")
	if int(merged["quads"]) != 6:
		_fail("merged pair quads=%s" % merged["quads"])
	else:
		print("OK merged pair quads=6")
	var split := _model([Vector4i(0, 0, 0, 0), Vector4i(1, 0, 0, 1)], Vector3i(2, 1, 1), Vector3.ZERO)
	var split_mesh := _Loader.build_part(split, "")
	if int(split_mesh["quads"]) != 10:
		_fail("opaque pair quads=%s" % split_mesh["quads"])
	else:
		print("OK opaque pair quads=10")
	var cube := _WorldSettings_cell()
	var reference: ArrayMesh = _Builder.build_mesh(
		[Vector4i(0, 0, 0, 1)],
		PackedColorArray([Color(0, 0, 0, 0), Color8(255, 0, 0)]),
		cube
	)
	if _Builder.face_count(reference) != int(one["quads"]):
		_fail("builder parity")
	else:
		print("OK builder parity quads=%d" % int(one["quads"]))
	var pivoted := _model([Vector4i(4, 0, 2, 0)], Vector3i(8, 2, 4), Vector3(4, 0, 2))
	var pivoted_mesh: ArrayMesh = _Loader.build_part(pivoted, "")["mesh"]
	var box := pivoted_mesh.get_aabb()
	if absf(box.position.x) > 0.001 or absf(box.position.y) > 0.001 or absf(box.position.z) > 0.001:
		_fail("pivot aabb %s" % box)
	else:
		print("OK pivot at origin")


func _model(cells: Array, size: Vector3i, pivot: Vector3) -> CrystalVoxelModel:
	var model := CrystalVoxelModel.new()
	model.model_name = "unit"
	model.size = size
	model.vpb = 16
	model.base_cell = 2
	model.scale_mode = "terrain_block"
	model.pivot = pivot
	model.palette = PackedColorArray([Color8(255, 0, 0), Color8(0, 0, 255)])
	model.part_order = PackedStringArray(["body"])
	model.part_cells = {"body": cells}
	return model


func _WorldSettings_cell() -> float:
	return load("res://config/world_settings.gd").get_active().voxel_scale / 16.0


func _check_vox_unit() -> void:
	var path := "user://crystal_voxel_unit.vox"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("vox unit write")
		return
	var children := 24 + 20 + 1036
	f.store_buffer("VOX ".to_ascii_buffer())
	f.store_32(150)
	f.store_buffer("MAIN".to_ascii_buffer())
	f.store_32(0)
	f.store_32(children)
	f.store_buffer("SIZE".to_ascii_buffer())
	f.store_32(12)
	f.store_32(0)
	f.store_32(2)
	f.store_32(3)
	f.store_32(4)
	f.store_buffer("XYZI".to_ascii_buffer())
	f.store_32(8)
	f.store_32(0)
	f.store_32(1)
	f.store_8(1)
	f.store_8(2)
	f.store_8(3)
	f.store_8(1)
	f.store_buffer("RGBA".to_ascii_buffer())
	f.store_32(1024)
	f.store_32(0)
	f.store_8(255)
	f.store_8(0)
	f.store_8(0)
	f.store_8(255)
	for _i in 255:
		f.store_32(0)
	f.close()
	var model := _Loader.import_vox(path, "unit_vox")
	if model == null:
		_fail("vox import")
		return
	if model.size != Vector3i(2, 4, 3) or model.voxel_count() != 1:
		_fail("vox size %s voxels=%d" % [model.size, model.voxel_count()])
		return
	var got := model.color_at(1, 3, 2)
	if got.r8 != 255 or got.g8 != 0 or got.b8 != 0:
		_fail("vox color %s" % got)
		return
	var built := _Loader.build_part(model, "body")
	if int(built["quads"]) != 6:
		_fail("vox quads=%s" % built["quads"])
		return
	print("OK vox import voxels=1 quads=6")


func _check_tree(path: String, name: String, voxels: int, trunk: int, canopy: int) -> int:
	var started := Time.get_ticks_msec()
	var rig := _Loader.rig_for(path)
	var elapsed := Time.get_ticks_msec() - started
	if rig.is_empty():
		_fail("%s load" % name)
		return 0
	var model: CrystalVoxelModel = rig["model"]
	var mesh: ArrayMesh = rig["mesh"]
	var quads := int(rig["quads"])
	var parts: Dictionary = rig["parts"]
	var trunk_pack: Dictionary = parts.get("trunk", {})
	var canopy_pack: Dictionary = parts.get("canopy", {})
	print(
		"VOXEL %s voxels=%d quads=%d part trunk voxels=%d quads=%d part canopy voxels=%d quads=%d ms=%d"
		% [
			name,
			int(rig["voxels"]),
			quads,
			int(trunk_pack.get("voxels", -1)),
			int(trunk_pack.get("quads", -1)),
			int(canopy_pack.get("voxels", -1)),
			int(canopy_pack.get("quads", -1)),
			elapsed,
		]
	)
	if model == null or model.model_name != name or model.vpb != 16 or model.base_cell != 2:
		_fail("%s fields" % name)
	if model.scale_mode != "terrain_block" or model.pivot != Vector3(56, 0, 56):
		_fail("%s pivot" % name)
	if model.size != Vector3i(128, 120, 112):
		_fail("%s size" % name)
	if int(rig["voxels"]) != voxels or int(trunk_pack.get("voxels", -1)) != trunk or int(canopy_pack.get("voxels", -1)) != canopy:
		_fail("%s voxel count" % name)
	if mesh == null or mesh.get_surface_count() != 1 or quads != _Loader.quad_count(mesh):
		_fail("%s mesh" % name)
	if quads < 1000 or quads >= voxels:
		_fail("%s quad range %d" % [name, quads])
	var trunk_mesh: ArrayMesh = trunk_pack.get("mesh", null)
	var canopy_mesh: ArrayMesh = canopy_pack.get("mesh", null)
	if trunk_mesh == null or canopy_mesh == null or trunk_mesh.get_surface_count() != 1 or canopy_mesh.get_surface_count() != 1:
		_fail("%s parts" % name)
	var trunk_quads := int(trunk_pack.get("quads", 0))
	var canopy_quads := int(canopy_pack.get("quads", 0))
	if trunk_quads <= 0 or canopy_quads <= 0 or quads >= trunk_quads + canopy_quads:
		_fail("%s part quads" % name)
	if not _colors_allowed(model):
		_fail("%s palette" % name)
	var box := mesh.get_aabb()
	if absf(box.position.y) > 0.02 or box.position.x >= 0.0 or box.end.x <= 0.0 or box.size.y < 1.0:
		_fail("%s bounds %s" % [name, box])
	if not FileAccess.file_exists(_Loader.cache_file(path, "")):
		_fail("%s cache" % name)
	if not FileAccess.file_exists(_Loader.cache_file(path, "trunk")) or not FileAccess.file_exists(_Loader.cache_file(path, "canopy")):
		_fail("%s part cache" % name)
	return quads


func _colors_allowed(model: CrystalVoxelModel) -> bool:
	if model.palette.size() > 16:
		return false
	for col in model.palette:
		var key := "%d,%d,%d" % [col.r8, col.g8, col.b8]
		if not _allowed.has(key):
			return false
	return true


func _check_cache(path: String, quads: int) -> void:
	_Loader.drop_memory()
	var started := Time.get_ticks_msec()
	var rig := _Loader.rig_for(path)
	var elapsed := Time.get_ticks_msec() - started
	if rig.is_empty() or int(rig["quads"]) != quads:
		_fail("cache reload quads")
		return
	print("OK voxel cache reload quads=%d ms=%d" % [quads, elapsed])


func _check_archive_oak() -> void:
	var path := "D:/ARCHIVE/CrystalStorm/art-pass/ref/mixed2/tree_oak.vox"
	if not FileAccess.file_exists(path):
		print("SKIP vox archive")
		return
	var model := _Loader.import_vox(path, "tree_oak_vox")
	if model == null or model.voxel_count() != 54680 or model.size != Vector3i(128, 120, 112):
		_fail("archive vox count")
		return
	var got := model.color_at(14, 93, 54)
	if got.r8 != 104 or got.g8 != 150 or got.b8 != 60:
		_fail("archive vox color %s" % got)
		return
	print("OK vox archive oak voxels=54680")
