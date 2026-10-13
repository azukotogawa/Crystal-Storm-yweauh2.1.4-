extends SceneTree
## Shipped StructureOrientation + WorldObject yaw contract (EW=0, NS=π/2).

const _BuildingRegistry = preload("res://building/building_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _StructureOrientation = preload("res://helpers/structure_orientation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldObject = preload("res://world/world_object.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(m: String) -> void:
	_failed += 1
	push_error(m)


func _stamp(wx: int, wz: int, id: String) -> void:
	_TerrainEdits.build_wall(wx, wz, _VoxelTypes.STONE)
	_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": id,
		"player_built": true,
		"is_passage": id == "gate",
		"is_bridge": id == "bridge",
		"raises_terrain": id != "gate",
	})


func _run() -> void:
	_BuildingRegistry.ensure_builtins()
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	_stamp(4, 4, "wood_wall")
	_stamp(5, 4, "wood_wall")
	_StructureOrientation.persist_yaw_neighborhood(4, 4)
	var ew: float = _StructureOrientation.yaw_for(4, 4, "wood_wall")
	if absf(ew) > 0.01:
		_fail("EW pair should yaw 0, got %s" % ew)
	else:
		print("OK EW yaw=0")
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	_stamp(8, 8, "stone_wall")
	_stamp(8, 9, "stone_wall")
	_StructureOrientation.persist_yaw_neighborhood(8, 8)
	var ns: float = _StructureOrientation.yaw_for(8, 8, "stone_wall")
	if absf(ns - PI * 0.5) > 0.01:
		_fail("NS pair should yaw PI/2, got %s" % ns)
	else:
		print("OK NS yaw=PI/2")
	var world = load("res://world/InfiniteNoiseWorld.gd").new(3)
	root.add_child(world)
	var obj: Node3D = _WorldObject.new()
	root.add_child(obj)
	await process_frame
	var feat: Dictionary = _FeatureRegistry.get_feature(8, 8)
	obj.bind(8, 8, "stone_wall", feat, world, null, null, null, Vector3(2, 2, 2), 0.0)
	var mesh: MeshInstance3D = obj.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or absf(mesh.rotation.y - ns) > 0.01:
		_fail("WorldObject mesh yaw must match persist, mesh=%s want=%s" % [
			str(mesh.rotation.y if mesh else -1.0), str(ns)
		])
	else:
		print("OK WorldObject mesh yaw=%.3f" % mesh.rotation.y)
	if _failed == 0:
		print("All building orientation tests OK")
		quit(0)
	else:
		push_error("verify_building_orientation: %d failure(s)" % _failed)
		quit(1)
