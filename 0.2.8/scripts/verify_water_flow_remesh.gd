extends SceneTree

const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")

var RIVER := Vector2i(2, 2)
var BLOCK := Vector2i(3, 2)

var _failed := 0
var world: InfiniteNoiseWorld
var editor: TerrainEditor
var svc: VoxelFluidService
var cm: ChunkManager


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	print("FAIL " + msg)
	_failed += 1


func _run() -> void:
	world = _InfiniteNoiseWorld.new()
	world.world_seed = 7
	root.add_child(world)
	cm = _ChunkManager.new()
	cm.world = world
	editor = _TerrainEditor.new()
	root.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)
	svc = _VoxelFluidService.new()
	root.add_child(svc)
	svc.world = world
	svc.chunk_manager = null
	await process_frame
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_ChannelRegistry.reset()
	var layer: float = _WorldSettings.get_active().layer_height()
	_FeatureRegistry.set_tile_override(RIVER.x, RIVER.y, _VoxelTypes.RIVER)
	_FeatureRegistry.set_tile_override(BLOCK.x, BLOCK.y, _VoxelTypes.GRASSLAND)
	var hr: float = world.get_surface_height(float(RIVER.x), float(RIVER.y))
	var hb: float = world.get_surface_height(float(BLOCK.x), float(BLOCK.y))
	var delta: int = int(round((hr - hb) / layer))
	if delta != 0:
		_WorldState.get_active().height_delta[BLOCK] = delta
		world.invalidate_column_cache(BLOCK.x, BLOCK.y)
	var coord: Vector2i = _TerrainEdits.chunk_for_column(BLOCK.x, BLOCK.y)
	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	if not editor.try_dig(Vector3(BLOCK.x + 0.5, 0.0, BLOCK.y + 0.5)):
		_fail("dig failed: %s" % editor.last_fail_reason)
	for _i in 6:
		svc._tick_water(0.1)
	if not _ChannelRegistry.has_fluid(BLOCK.x, BLOCK.y, _ChannelRegistry.FLUID_WATER):
		_fail("SIM: water did not enter the hole")
	var local := BLOCK - coord * _ChunkData.SIZE
	data.refresh_worker_snapshot_for_cells([local])
	var water_quads := 0
	for q in cm._build_mesh(data).get("quads", []):
		if int(q.get("x", -1)) == local.x and int(q.get("z", -1)) == local.y and int(q.get("type", -1)) == _VoxelTypes.WATER:
			water_quads += 1
	print("INFO patch remesh water_quads=%d" % water_quads)
	if water_quads == 0:
		_fail("RENDER: patch remesh after flow has no water quad in the hole")
	if _failed == 0:
		print("All water flow remesh tests OK")
		quit(0)
	else:
		push_error("verify_water_flow_remesh: %d failure(s)" % _failed)
		quit(1)
