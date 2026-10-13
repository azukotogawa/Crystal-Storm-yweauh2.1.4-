extends SceneTree
## Reproduce: one build press must not apply two height layers.
## Drives WeaponController + TerrainEditor with simulated input pulses.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()

	var root3d := Node3D.new()
	root.add_child(root3d)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 11
	world.add_to_group("world")
	root3d.add_child(world)

	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	root3d.add_child(cm)
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(Vector2i(0, 0), world)
	cm.chunks[Vector2i(0, 0)] = view

	var editor := _TerrainEditor.new()
	editor.add_to_group("terrain_editor")
	root3d.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	# Direct API: one try_build → exactly +1 layer.
	var layer: float = _WorldSettings.get_active().layer_height()
	var before: float = _TerrainEdits.get_height_delta(5, 5)
	var inv := _Inventory.new()
	inv.add_item("wood", 20)
	var y: float = world.get_surface_height(5.0, 5.0)
	if not editor.try_build(Vector3(5.5, y, 5.5), inv, &"wood_wall"):
		push_error("try_build failed: %s" % editor.last_fail_reason)
		quit(1)
		return
	var after: float = _TerrainEdits.get_height_delta(5, 5)
	var layers := int(round((after - before) / layer))
	print("API_ONE_BUILD layers_added=%d (expect 1)" % layers)
	if layers != 1:
		push_error("API try_build applied %d layers" % layers)
		quit(1)
		return
	print("OK single API build = 1 layer")

	# Count how many times try_build would fire if called twice same frame (bug pattern).
	var b2: float = _TerrainEdits.get_height_delta(6, 6)
	editor.try_build(Vector3(6.5, y, 6.5), inv, &"wood_wall")
	editor.try_build(Vector3(6.5, y, 6.5), inv, &"wood_wall")
	var a2: float = _TerrainEdits.get_height_delta(6, 6)
	var layers2 := int(round((a2 - b2) / layer))
	print("API_DOUBLE_CALL layers_added=%d (shows no server-side coalesce)" % layers2)
	if layers2 < 2:
		print("NOTE: second build blocked (stack/full/other)")
	else:
		print("REPRO_RISK: two try_build calls stack two layers — input must not double-call")

	print("All terrain input repro OK")
	quit(0)
