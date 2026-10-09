extends SceneTree
## Wood/stone walls are WorldObjects: they block entry, enemies, and knockback,
## they do not trap or lift a body standing beside them, and they save and remove.


const _BuildingRegistry = preload("res://building/building_registry.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _CrystalCorruption = preload("res://crystal/crystal_corruption.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")


class FlatKnock:
	extends RefCounted
	func sample_knock_ground(_x: float, _z: float) -> float:
		return 4.0


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

	var holder := Node.new()
	root.add_child(holder)
	var world := InfiniteNoiseWorld.new()
	world.world_seed = 99
	holder.add_child(world)
	var probe := _VoxelFloorProbe.new()
	probe.configure(world, null, null)
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()

	_test_entry_escape_and_graze(probe, ws, layer)
	_test_enemy_and_knockback(ws)
	_test_flow_and_corruption()
	_test_place_remove_save(world)

	holder.free()
	if _failed == 0:
		print("All wall world object tests OK")
		quit(0)
	else:
		push_error("verify_wall_world_object: %d failure(s)" % _failed)
		quit(1)


func _step(probe: VoxelFloorProbe, ws, from_pos: Vector3, to_pos: Vector3) -> bool:
	return bool(probe.can_step_to(
		from_pos,
		to_pos,
		ws.player_height(),
		ws.player_radius(),
		ws.max_step_up_walk(),
		false
	))


func _register_wall(x: int, z: int, build_id: String, passage: bool = false) -> void:
	_FeatureRegistry.register_feature(x, z, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": build_id,
		"visual_id": build_id,
		"flow_resistance": 0.85 if build_id == "stone_wall" else 0.55,
		"player_built": true,
		"is_passage": passage,
		"is_bridge": false,
		"raises_terrain": false,
		"yaw": 1.570796,
	})


func _test_entry_escape_and_graze(probe: VoxelFloorProbe, ws, layer: float) -> void:
	# Tall stacked column that is also a wall. A body in the next column must
	# still walk parallel, and its feet must stay on its own ground.
	for _i in 4:
		_TerrainEdits.build_wall(30, 30, _VoxelTypes.DIRT)
	_register_wall(30, 30, "stone_wall")
	var ground := probe.walkable_height_at(29.8, 30.5)
	var feet := probe.sample_walkable_feet(29.8, 30.5)
	var feet_max := probe.sample_walkable_feet_max(29.8, 30.5)
	if absf(feet - ground) > layer * 0.2 or absf(feet_max - ground) > layer * 0.2:
		_fail("wall neighbor pulled feet ground=%.2f feet=%.2f max=%.2f" % [ground, feet, feet_max])
	elif probe.slope_excess_at(29.8, 30.5) > layer * 0.75:
		_fail("wall neighbor inflated slope excess %.2f" % probe.slope_excess_at(29.8, 30.5))
	elif not _step(probe, ws, Vector3(29.8, ground, 30.5), Vector3(29.8, ground, 31.5)):
		_fail("parallel step beside a tall wall was refused")
	elif _step(probe, ws, Vector3(29.5, ground, 30.5), Vector3(30.5, ground, 30.5)):
		_fail("step into a stone wall column was allowed")
	else:
		print("OK wall blocks entry and does not lift the neighbor")

	# WorldObject wall with no height. The body can leave and shuffle inside.
	_register_wall(52, 52, "wood_wall")
	var y := probe.walkable_height_at(52.5, 52.5)
	if not _step(probe, ws, Vector3(52.5, y, 52.5), Vector3(53.5, y, 52.5)):
		_fail("could not leave a wall column")
	elif not _step(probe, ws, Vector3(52.2, y, 52.2), Vector3(52.8, y, 52.7)):
		_fail("could not shuffle inside a wall column")
	elif _step(probe, ws, Vector3(51.5, y, 52.5), Vector3(52.5, y, 52.5)):
		_fail("could enter a wood wall from outside")
	else:
		print("OK wall escape and in-cell shuffle")

	_register_wall(60, 60, "gate", true)
	var gy := probe.walkable_height_at(59.5, 60.5)
	if not _step(probe, ws, Vector3(59.5, gy, 60.5), Vector3(60.5, gy, 60.5)):
		_fail("gate column blocked movement")
	elif _VoxelFloorProbe.blocking_build_column(60, 60):
		_fail("gate was treated as a blocking wall")
	else:
		print("OK gate stays walkable")


func _test_enemy_and_knockback(ws) -> void:
	_register_wall(40, 40, "stone_wall")
	var start := Vector3(ws.column_to_world(39.5), 2.0, ws.column_to_world(40.5))
	var next: Vector3 = _EntityNavigation.step_toward_cell(
		start, Vector2i(40, 40), 6.0, 0.05, null, null, null
	)
	var landed := _EntityNavigation.column_pos(next)
	if landed == Vector2i(40, 40):
		_fail("enemy stepped into a wall column %s" % str(landed))
	else:
		print("OK enemy step avoids wall, landed %s" % str(landed))

	var open_start := Vector3(ws.column_to_world(70.5), 2.0, ws.column_to_world(70.5))
	var open_next: Vector3 = _EntityNavigation.step_toward_cell(
		open_start, Vector2i(72, 70), 6.0, 0.2, null, null, null
	)
	if open_next.distance_squared_to(open_start) < 0.01:
		_fail("enemy did not move across open ground")
	else:
		print("OK enemy still steps on open ground")

	var knock := FlatKnock.new()
	var from := Vector3(ws.column_to_world(39.2), 4.0, ws.column_to_world(40.5))
	var blocked: Vector3 = _EntityNavigation.knockback_step(from, Vector3(1, 0, 0), 6.0, knock, null, null)
	if blocked.distance_squared_to(from) > 0.001:
		_fail("knockback entered a wall, ended at %s" % str(blocked))
	else:
		print("OK knockback into a wall stays put")

	var tunnel_from := Vector3(ws.column_to_world(38.2), 4.0, ws.column_to_world(40.5))
	var tunneled: Vector3 = _EntityNavigation.knockback_step(tunnel_from, Vector3(1, 0, 0), 8.0, knock, null, null)
	if tunneled.distance_squared_to(tunnel_from) > 0.001:
		_fail("knockback tunneled across a wall to %s" % str(tunneled))
	else:
		print("OK knockback does not tunnel a wall")

	var nudge_from := Vector3(ws.column_to_world(39.2), 4.0, ws.column_to_world(40.5))
	var nudged: Vector3 = _EntityNavigation.knockback_step(nudge_from, Vector3(-1, 0, 0), 0.4, knock, null, null)
	if nudged.distance_squared_to(nudge_from) < 0.01:
		_fail("short knockback away from a wall did not move")
	else:
		print("OK knockback away from a wall still moves")


func _test_flow_and_corruption() -> void:
	_register_wall(8, 8, "stone_wall")
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	terrain.sim_config = cfg
	var heights: Dictionary = {}
	for x in 5:
		for z in 5:
			heights[Vector2i(6 + x, 6 + z)] = 10.0
	terrain.test_base_heights = heights
	var open_f: float = terrain.get_flow_factor_at(Vector2i(7, 7), _VoxelTypes.GRASS_TUFT)
	terrain.begin_sim_tick(1)
	var wall_f: float = terrain.get_flow_factor_at(Vector2i(8, 8), _VoxelTypes.GRASS_TUFT)
	if wall_f >= open_f:
		_fail("stone wall should slow crystal open=%.3f wall=%.3f" % [open_f, wall_f])
	else:
		print("OK wall flow open=%.3f wall=%.3f" % [open_f, wall_f])

	var feat: Dictionary = _FeatureRegistry.get_feature(8, 8)
	if _CrystalCorruption.corrupt_absorbed_cell(Vector2i(8, 8), _VoxelTypes.GRASS_TUFT, feat):
		_fail("corruption rewrote a player wall")
	elif bool(_FeatureRegistry.get_feature(8, 8).get("corrupt", false)):
		_fail("wall feature gained corrupt flag")
	elif str(_FeatureRegistry.get_feature(8, 8).get("build_id", "")) != "stone_wall":
		_fail("wall build_id changed during corruption")
	else:
		print("OK corruption leaves player walls")


func _test_place_remove_save(world: InfiniteNoiseWorld) -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var editor := _TerrainEditor.new()
	editor.world = world
	editor.bind_chunk_manager(_ChunkManager.new())
	root.add_child(editor)
	var inv := _Inventory.new()
	inv.add_item("stone", 4)
	var surface: float = world.get_surface_height(12.0, 14.0)
	var pos := Vector3(12.5, surface, 14.5)
	if not editor.try_build_wall(pos, inv, true):
		_fail("wall place failed: %s" % editor.last_fail_reason)
		return
	if editor.try_build_wall(pos, inv, true):
		_fail("second wall on the same cell was accepted")
		return
	var placed: Dictionary = _FeatureRegistry.get_feature(12, 14).duplicate(true)
	if str(placed.get("build_id", "")) != "stone_wall":
		_fail("placed feature is not stone_wall")
		return
	if bool(placed.get("raises_terrain", true)):
		_fail("placed wall raises_terrain should be false")
		return
	if str(placed.get("visual_id", "")) == "":
		_fail("placed wall missing visual_id")
		return

	var bundle: Dictionary = _WorldState.get_active().export_persistence_bundle()
	var parsed = JSON.parse_string(JSON.stringify(bundle))
	if not parsed is Dictionary:
		_fail("wall bundle did not round-trip through JSON")
		return
	_FeatureRegistry.reset()
	_TerrainEdits.reset()
	_WorldState.get_active().import_persistence_bundle(parsed)
	var restored: Dictionary = _FeatureRegistry.get_feature(12, 14)
	if str(restored.get("build_id", "")) != str(placed.get("build_id", "")):
		_fail("save lost build_id %s" % str(restored))
	elif str(restored.get("visual_id", "")) != str(placed.get("visual_id", "")):
		_fail("save lost visual_id got %s" % str(restored.get("visual_id", "")))
	elif bool(restored.get("raises_terrain", true)):
		_fail("save restored raises_terrain true")
	else:
		var probe := _VoxelFloorProbe.new()
		probe.configure(world, null, null)
		var ws = _WorldSettings.get_active()
		var y := probe.walkable_height_at(11.5, 14.5)
		if _step(probe, ws, Vector3(11.5, y, 14.5), Vector3(12.5, y, 14.5)):
			_fail("reloaded wall did not block")
		else:
			print("OK wall save round-trip blocks")

	if not editor.try_remove(pos, inv):
		_fail("try_remove wall failed: %s" % editor.last_fail_reason)
	elif not _FeatureRegistry.get_feature(12, 14).is_empty():
		_fail("remove left the wall feature")
	else:
		var probe := _VoxelFloorProbe.new()
		probe.configure(world, null, null)
		var ws = _WorldSettings.get_active()
		var y := probe.walkable_height_at(11.5, 14.5)
		if not _step(probe, ws, Vector3(11.5, y, 14.5), Vector3(12.5, y, 14.5)):
			_fail("removed wall still blocks")
		elif not is_equal_approx(_TerrainEdits.get_height_delta(12, 14), 0.0):
			_fail("remove changed supporting height")
		else:
			print("OK wall remove clears the block")
	editor.free()
