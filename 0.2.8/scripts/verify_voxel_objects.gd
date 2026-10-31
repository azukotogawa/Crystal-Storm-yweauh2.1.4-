extends SceneTree

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Catalog = preload("res://helpers/object_voxel_catalog.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")

const _NEED_PART := {
	"torch": "flame",
	"chest": "lid",
	"door": "hinge",
	"furnace": "ember",
	"crystal_node": "crystal",
}

var _failed := false
var _allowed := {}


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed = true
	print("FAIL %s" % msg)


func _run() -> void:
	_load_palette()
	var quads_line := ""
	var worst := 0
	for name in _Catalog.MODELS:
		var path: String = _Catalog.path_for(name)
		var model: CrystalVoxelModel = _Loader.load_model(path)
		if model == null:
			_fail("load %s" % name)
			continue
		if model.vpb != 16 or model.base_cell != 2 or model.scale_mode != "terrain_block":
			_fail("%s grid" % name)
		if model.palette.size() > 16 or model.palette.is_empty():
			_fail("%s palette size" % name)
		for col in model.palette:
			var key := "%d,%d,%d" % [int(round(col.r * 255.0)), int(round(col.g * 255.0)), int(round(col.b * 255.0))]
			if not _allowed.has(key):
				_fail("%s color %s" % [name, key])
		var cells: Array = model.cells_for("")
		var occ := {}
		for cell in cells:
			var c: Vector4i = cell
			if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= model.size.x or c.y >= model.size.y or c.z >= model.size.z:
				_fail("%s cell outside size" % name)
			occ[Vector3i(c.x, c.y, c.z)] = true
		var interior := 0
		for at_key in occ.keys():
			var at: Vector3i = at_key
			var n6 := 0
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if occ.has(at + d):
					n6 += 1
			if n6 == 6:
				interior += 1
		if interior > 0:
			_fail("%s interior %d" % [name, interior])
		if _NEED_PART.has(name) and not model.part_cells.has(_NEED_PART[name]):
			_fail("%s missing %s" % [name, _NEED_PART[name]])
		if name == "chest":
			_check_lid(model)
		if name == "door":
			_check_hinge(model)
		var built := _Loader.rig_for(path)
		var quads := int(built.get("quads", 0))
		var mesh: ArrayMesh = built.get("mesh", null)
		if mesh == null or mesh.get_surface_count() != 1:
			_fail("%s mesh surfaces" % name)
		elif quads > _Catalog.BUDGET:
			_fail("%s quads %d" % [name, quads])
		worst = maxi(worst, quads)
		quads_line += "%s=%d " % [name, quads]
		print("QUAD %s voxels=%d quads=%d" % [name, cells.size(), quads])
		_check_node(name)
	print("QUADS %s" % quads_line.strip_edges())
	print("QUAD_MAX %d" % worst)
	_check_buildings_stay_authored()
	if _failed:
		print("VOXEL OBJECTS FAIL")
		quit(1)
		return
	print("VOXEL OBJECTS OK")
	quit(0)


func _check_lid(model: CrystalVoxelModel) -> void:
	var lid: Array = model.part_cells.get("lid", [])
	if lid.is_empty():
		_fail("chest lid empty")
		return
	var min_y := 9999
	var min_z := 9999
	for cell in lid:
		var c: Vector4i = cell
		min_y = mini(min_y, c.y)
		min_z = mini(min_z, c.z)
	if int(model.pivot.y) != min_y or int(model.pivot.z) != min_z:
		_fail("chest pivot %s is not the lid hinge" % model.pivot)


func _check_hinge(model: CrystalVoxelModel) -> void:
	var hinge: Array = model.part_cells.get("hinge", [])
	var on_axis := false
	for cell in hinge:
		var c: Vector4i = cell
		if c.x == int(model.pivot.x) and c.z == int(model.pivot.z):
			on_axis = true
			break
	if not on_axis:
		_fail("door hinge misses pivot %s" % model.pivot)


func _check_node(name: String) -> void:
	var node := _Catalog.build(name)
	var meshes := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			meshes += 1
			if child.get_child_count() != 0:
				_fail("%s nested nodes under %s" % [name, child.name])
			if _Catalog.emits(child.name):
				var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
				if mat == null or not mat.emission_enabled:
					_fail("%s %s is not emissive" % [name, child.name])
	var expect := 1
	if name in ["torch", "chest", "door", "furnace", "crystal_node"]:
		expect = 2
	if meshes != expect:
		_fail("%s mesh instances %d" % [name, meshes])
	node.free()


func _check_buildings_stay_authored() -> void:
	for id in ["wood_wall", "stone_wall", "gate", "bridge", "town_hall", "ruin_pillar"]:
		var mesh_path := str(_Registry.AUTHORED_BUILDING_MESH_PATHS.get(id, ""))
		if not mesh_path.ends_with(".obj"):
			_fail("%s left the authored obj path" % id)
		elif not FileAccess.file_exists(mesh_path):
			_fail("%s obj missing" % id)
	print("OK building props stay on authored OBJ meshes")


func _load_palette() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/voxel/palette.json"))
	for entry in parsed.get("colors", []):
		var rgb = entry.get("rgb", [])
		_allowed["%d,%d,%d" % [int(rgb[0]), int(rgb[1]), int(rgb[2])]] = true
