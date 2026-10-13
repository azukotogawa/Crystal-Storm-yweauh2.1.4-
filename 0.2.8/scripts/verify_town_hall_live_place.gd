extends SceneTree
## Live main.tscn: stamp TOWN_BUILDING, assert authored hall; TOWN disk has none.
## Usage: godot --path . -s scripts/verify_town_hall_live_place.gd


const MAIN_SCENE := "res://scenes/main.tscn"
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const HALL_MESH_PATH := "res://assets/structures/town_hall/town_hall.obj"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("missing main scene")
		_finish()
		return
	var game = packed.instantiate()
	root.add_child(game)
	for _i in 200:
		await process_frame
		var cm = get_first_node_in_group("chunk_manager")
		var feat = get_first_node_in_group("feature_visual_layer")
		if cm and feat and cm.chunks.size() > 0:
			break
	await process_frame
	var feat_layer = get_first_node_in_group("feature_visual_layer")
	var player = get_first_node_in_group("player")
	if feat_layer == null:
		_fail("missing feature_visual_layer")
		_finish()
		return
	var px := 8
	var pz := 8
	if player and player.has_method("get_voxel_position"):
		var pv: Vector3 = player.get_voxel_position()
		px = int(floor(pv.x)) + 4
		pz = int(floor(pv.z)) + 3
	var center := Vector2i(px, pz)
	var disk := Vector2i(px + 2, pz)
	_FeatureRegistry.register_feature(center.x, center.y, _WorldFeatureTypes.FeatureKind.TOWN_BUILDING, {
		"center": center, "name": "Live Town", "town_building": "hall"
	})
	_FeatureRegistry.register_feature(disk.x, disk.y, _WorldFeatureTypes.FeatureKind.TOWN, {
		"center": center, "name": "Live Town", "radius": 2
	})
	feat_layer.refresh_cell(center.x, center.y)
	feat_layer.refresh_cell(disk.x, disk.y)
	await process_frame
	await process_frame
	var a: Node3D = feat_layer._nodes_by_cell.get(center)
	var d: Node3D = feat_layer._nodes_by_cell.get(disk)
	if a == null:
		_fail("no hall at town center")
	elif str(a.get_meta("building_visual_id", "")) != "town_hall":
		_fail("center id %s" % a.get_meta("building_visual_id", ""))
	else:
		var m: MeshInstance3D = a.get_node_or_null("Mesh") as MeshInstance3D
		if m == null or str(m.get_meta("authored_resource_path", "")) != HALL_MESH_PATH:
			_fail("center not authored hall")
		else:
			_ok("live center uses authored town_hall")
	if d != null and str(d.get_meta("building_visual_id", "")) == "town_hall":
		_fail("TOWN disk still has a hall")
	else:
		_ok("live TOWN disk has no hall")
	var reg = get_first_node_in_group("game_visual_registry")
	if reg and reg.has_authored_building_mesh("town_hall") and reg.has_authored_building_mesh("ruin_pillar"):
		_ok("registry has authored town_hall and ruin_pillar")
	else:
		_fail("registry missing authored hall/ruin")
	_finish()


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All town_hall live place tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "TOWN HALL LIVE PLACE FAILED")
