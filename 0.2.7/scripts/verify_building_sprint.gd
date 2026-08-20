extends SceneTree
## Building sprint: instant walls, gates (walk-through + crystal baffle), bridges.
## Usage: godot --headless -s scripts/verify_building_sprint.gd


const _BuildingRegistry = preload("res://building/building_registry.gd")
const _BuildableDef = preload("res://config/buildable_def.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.reset()
	_BuildingRegistry.ensure_builtins()

	_test_builtins()
	_test_instant_wall()
	_test_gate()
	_test_bridge()
	_test_crystal_baffle()
	_test_weapon_paths()

	if _failed == 0:
		print("All building sprint tests OK")
		quit(0)
	else:
		push_error("verify_building_sprint: %d failure(s)" % _failed)
		quit(1)


func _test_builtins() -> void:
	for id in [&"stone_wall", &"wood_wall", &"gate", &"bridge"]:
		var def = _BuildingRegistry.get_def(id)
		if def == null:
			_fail("missing buildable %s" % str(id))
			return
	var gate = _BuildingRegistry.get_def(&"gate")
	if gate.raises_terrain or not gate.is_passage:
		_fail("gate must be passage without raising terrain")
	var bridge = _BuildingRegistry.get_def(&"bridge")
	if not bridge.raises_terrain or not bridge.is_bridge:
		_fail("bridge must raise terrain and be marked is_bridge")
	else:
		print("OK buildable builtins wall/gate/bridge")


func _test_instant_wall() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var holder := Node.new()
	root.add_child(holder)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 99
	holder.add_child(world)
	var cm := _ChunkManager.new()
	var editor := _TerrainEditor.new()
	holder.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var delay: float = editor.get_build_delay(Vector3.ZERO)
	if delay > 0.05:
		_fail("build delay should be instant (<=0.05) got %.3f" % delay)

	var inv := _Inventory.new()
	inv.add_item("stone", 6)
	var t0 := Time.get_ticks_usec()
	var natural: float = world.get_surface_height(10.0, 12.0)
	var target := Vector3(10.5, natural, 12.5)
	if not editor.try_build_wall(target, inv, true):
		_fail("instant wall place failed")
	else:
		var us: int = Time.get_ticks_usec() - t0
		var layer: float = _WorldSettings.get_active().layer_height()
		if not is_equal_approx(_TerrainEdits.get_height_delta(10, 12), layer):
			_fail("wall height not applied")
		elif us > 50_000:
			_fail("wall place took too long %dus (not instant)" % us)
		elif inv.count_item("stone") != 5:
			_fail("stone not consumed")
		else:
			print("OK instant wall place us=%d delay=%.3f" % [us, delay])
	holder.queue_free()


func _test_gate() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var holder := Node.new()
	root.add_child(holder)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 99
	holder.add_child(world)
	var cm := _ChunkManager.new()
	var editor := _TerrainEditor.new()
	holder.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var inv := _Inventory.new()
	inv.add_item("wood", 4)
	var h_before: float = world.get_surface_height(5.0, 6.0)
	var delta_before: float = _TerrainEdits.get_height_delta(5, 6)
	if not editor.try_build_gate(Vector3(5.5, h_before, 6.5), inv):
		_fail("gate place failed: %s" % editor.last_fail_reason)
	else:
		var delta_after: float = _TerrainEdits.get_height_delta(5, 6)
		if not is_equal_approx(delta_after, delta_before):
			_fail("gate must not raise height_delta before=%.3f after=%.3f" % [delta_before, delta_after])
		var feat: Dictionary = _FeatureRegistry.get_feature(5, 6)
		if not bool(feat.get("is_passage", false)):
			_fail("gate feature missing is_passage")
		elif not bool(feat.get("player_built", false)):
			_fail("gate missing player_built")
		elif float(feat.get("flow_resistance", 0.0)) < 0.2:
			_fail("gate should baffle crystal")
		elif _TerrainEdits.get_build_tile(5, 6) < 0:
			_fail("gate should mark build_tile")
		else:
			print("OK gate walk-through baffle resist=%.2f" % float(feat.flow_resistance))

	# Cannot place gate on stacked wall
	_TerrainEdits.build_wall(7, 7, _VoxelTypes.STONE)
	if editor.try_build_gate(Vector3(7.5, 0.0, 7.5), inv):
		_fail("gate on wall should fail")
	else:
		print("OK gate blocked on stacked wall")
	holder.queue_free()


func _test_bridge() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var holder := Node.new()
	root.add_child(holder)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 99
	holder.add_child(world)
	var cm := _ChunkManager.new()
	var editor := _TerrainEditor.new()
	holder.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	var inv := _Inventory.new()
	inv.add_item("wood", 4)
	# Dig then bridge spans the depression
	_TerrainEdits.dig(8, 8, 1)
	var dug_delta: float = _TerrainEdits.get_height_delta(8, 8)
	if not editor.try_build_bridge(Vector3(8.5, 0.0, 8.5), inv):
		_fail("bridge place failed: %s" % editor.last_fail_reason)
	else:
		var after: float = _TerrainEdits.get_height_delta(8, 8)
		var layer: float = _WorldSettings.get_active().layer_height()
		if after < dug_delta + layer * 0.5:
			_fail("bridge should raise height after dig dug=%.3f after=%.3f" % [dug_delta, after])
		var feat: Dictionary = _FeatureRegistry.get_feature(8, 8)
		if not bool(feat.get("is_bridge", false)):
			_fail("bridge feature missing is_bridge")
		else:
			print("OK bridge spans dig delta %.3f→%.3f" % [dug_delta, after])
	holder.queue_free()


func _test_crystal_baffle() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.sim_config = cfg
	var heights: Dictionary = {}
	for x in 5:
		for z in 5:
			heights[Vector2i(x, z)] = 10.0
	terrain.test_base_heights = heights

	var open_f: float = terrain.get_flow_factor_at(Vector2i(2, 2), _VoxelTypes.GRASS_TUFT)

	_FeatureRegistry.register_feature(2, 2, 0, {
		"build_id": "gate",
		"player_built": true,
		"is_passage": true,
		"flow_resistance": 0.72,
	})
	_TerrainEdits.set_build_tile_only(2, 2, _VoxelTypes.DIRT)
	terrain.begin_sim_tick(1)
	var gate_f: float = terrain.get_flow_factor_at(Vector2i(2, 2), _VoxelTypes.GRASS_TUFT)
	# open grass ~0.55, gate factor = 1 - 0.72 = 0.28
	if gate_f >= open_f - 0.15:
		_fail("gate should slow crystal open=%.3f gate=%.3f" % [open_f, gate_f])
	else:
		print("OK crystal baffle open=%.3f gate=%.3f" % [open_f, gate_f])


func _test_weapon_paths() -> void:
	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_resolve_buildable_id" not in weapon_src:
		_fail("weapon must resolve gate/bridge buildables")
	if "get_build_delay" not in weapon_src:
		_fail("weapon must use get_build_delay for instant place")
	if "try_build_gate" not in weapon_src or "try_build_bridge" not in weapon_src:
		_fail("weapon must call try_build_gate/bridge")
	if "structure_built" not in weapon_src:
		_fail("weapon must emit structure_built for feedback")
	else:
		print("OK weapon build paths gate/bridge/instant")
