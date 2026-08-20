extends SceneTree
## Regression: build_wall raises terrain, sets build tile, and terrain_editor places with inventory.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const FACE_TOP := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var layer: float = _WorldSettings.get_active().layer_height()

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()

	if not _TerrainEdits.build_wall(12, 14, _VoxelTypes.STONE):
		push_error("build_wall should succeed on playable cell")
		failed = true
	elif not is_equal_approx(_TerrainEdits.get_height_delta(12, 14), layer):
		push_error("build height delta wrong got %s" % _TerrainEdits.get_height_delta(12, 14))
		failed = true
	elif _TerrainEdits.get_build_tile(12, 14) != _VoxelTypes.STONE:
		push_error("build tile not recorded")
		failed = true
	else:
		print("OK terrain build delta=%s tile=%s" % [_TerrainEdits.get_height_delta(12, 14), _TerrainEdits.get_build_tile(12, 14)])

	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 77
	holder.add_child(world)

	var cm := _ChunkManager.new()
	var editor := _TerrainEditor.new()
	holder.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var inv := _Inventory.new()
	inv.add_item("stone", 4)

	var natural: float = world.get_surface_height(20.0, 22.0)
	var target := Vector3(20.5, natural, 22.5)
	if not editor.try_build_wall(target, inv, true):
		push_error("terrain_editor.try_build_wall failed with stone in inventory")
		failed = true
	elif not is_equal_approx(_TerrainEdits.get_height_delta(20, 22), layer):
		push_error("editor build delta wrong")
		failed = true
	elif _TerrainEdits.get_build_tile(20, 22) != _VoxelTypes.STONE:
		push_error("editor build tile wrong")
		failed = true
	elif inv.count_item("stone") != 3:
		push_error("stone not consumed, count=%d" % inv.count_item("stone"))
		failed = true
	else:
		print("OK terrain_editor build placed stone wall")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_TerrainEdits.build_wall(30, 30, _VoxelTypes.STONE)
	_TerrainEdits.build_wall(30, 30, _VoxelTypes.STONE)
	var stacked_data := _ChunkData.new(Vector2i(1, 1), world)
	stacked_data.capture_worker_snapshot()
	stacked_data._compute_column_maps(true)
	var cm_mesh := _ChunkManager.new()
	var stacked_mesh: Dictionary = cm_mesh._build_mesh(stacked_data)
	var top_quads := 0
	for q in stacked_mesh.get("quads", []):
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		if int(q.get("x", -1)) == 14 and int(q.get("z", -1)) == 14:
			top_quads += 1
	if top_quads < 2:
		push_error("stacked build needs >=2 top quads in column, got %d" % top_quads)
		failed = true
	else:
		print("OK stacked build mesh tops=%d" % top_quads)

	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_ActionTargeting.target_column" not in weapon_src:
		push_error("weapon_controller must use ActionTargeting for build column")
		failed = true
	else:
		print("OK weapon build uses ActionTargeting")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_TerrainEdits.build_wall(8, 8, _VoxelTypes.STONE)
	var built_data := _ChunkData.new(Vector2i(0, 0), world)
	built_data.capture_worker_snapshot()
	built_data._compute_column_maps(true)
	var cm_ramp := _ChunkManager.new()
	cm_ramp.ramp_placement_chance = 100
	var built_mesh: Dictionary = cm_ramp._build_mesh(built_data)
	var ramp_on_build := 0
	for q in built_mesh.get("quads", []):
		var fc := int(q.get("face_code", -1))
		if fc in [7, 8, 9] and int(q.get("x", -1)) == 8 and int(q.get("z", -1)) == 8:
			ramp_on_build += 1
	if ramp_on_build > 0:
		push_error("player-built column must not emit ramps, got %d" % ramp_on_build)
		failed = true
	else:
		print("OK no ramps on player-built column")

	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	holder.queue_free()
	await process_frame
	if failed:
		print("Terrain build tests FAILED")
		quit(1)
		return
	print("All terrain build tests OK")
	quit(0)