extends SceneTree
## Headless: every moving body swims in deep water and wades on a river tile.
## Dry ground, a cliff, and border ocean stay on the old step.
## Usage: godot --headless --path 0.2.8 -s res://scripts/verify_swim.gd

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Water = preload("res://helpers/water_locomotion.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")

const PAD_SURFACE := 10.0

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_TerrainEdits.reset()
	_ChannelRegistry.reset()
	_EntityNavigation.use_lightweight_nav = true
	var world := InfiniteNoiseWorld.new()
	world.world_seed = 99
	var layer: float = _WorldSettings.get_active().layer_height()
	var waterline := PAD_SURFACE + layer

	_pad(world, 16, 28, 18, 22)
	for x in range(20, 24):
		_drop_layers(x, 20, 3)
		_ChannelRegistry.register_channel(x, 20, Vector2i.ZERO, 0.85)
		_ChannelRegistry.set_runtime_surface_y(x, 20, waterline)
	# Walls around the trench, taller than a swim step, so the body cannot walk around.
	for x in range(20, 28):
		_drop_layers(x, 19, -5)
		_drop_layers(x, 21, -5)
	for z in range(19, 22):
		_drop_layers(24, z, -5)

	_pad(world, 48, 56, 48, 52)
	_pad(world, 60, 66, 60, 62)
	for x in range(60, 67):
		_TerrainEdits.set_build_tile_only(x, 60, _VoxelTypes.RIVER)
	_pad(world, 70, 76, 70, 72)
	for x in range(70, 77):
		_TerrainEdits.set_build_tile_only(x, 70, _VoxelTypes.OCEAN)

	_test_sample(world, layer, waterline)
	_test_entities(world, layer, waterline)
	_test_player(world, layer, waterline)
	_test_player_input(world, layer, waterline)
	_test_callers()
	world.free()

	_TerrainEdits.reset()
	_ChannelRegistry.reset()
	if _failed == 0:
		print("All swim tests OK")
		quit(0)
	else:
		push_error("verify_swim: %d failure(s)" % _failed)
		quit(1)


func _pad(world, x0: int, x1: int, z0: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			_set_surface(world, x, z, PAD_SURFACE)
			if not _TerrainEdits.set_build_tile_only(x, z, _VoxelTypes.GRASSLAND):
				_fail("could not mark column %d,%d grassland" % [x, z])


func _set_surface(world, x: int, z: int, surface: float) -> void:
	var layer: float = _WorldSettings.get_active().layer_height()
	var current: float = world.get_surface_height(float(x) + 0.5, float(z) + 0.5)
	var natural: float = current - _TerrainEdits.get_height_delta(x, z)
	var layers := int(round((surface - natural) / layer))
	var state = _WorldState.get_active()
	var key := Vector2i(x, z)
	if layers == 0:
		state.height_delta.erase(key)
	else:
		state.height_delta[key] = layers


func _drop_layers(x: int, z: int, layers: int) -> void:
	var state = _WorldState.get_active()
	var key := Vector2i(x, z)
	var next: int = int(state.height_delta.get(key, 0)) - layers
	state.height_delta[key] = next


func _feet(world, x: float, z: float) -> float:
	return _EntityNavigation.walkable_y_light(world, null, null, x, z)


func _at(col_x: float, y: float, col_z: float) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(ws.column_to_world(col_x), y, ws.column_to_world(col_z))


func _test_sample(world, layer: float, waterline: float) -> void:
	var bed := _feet(world, 20.5, 20.5)
	var info: Dictionary = _Water.sample(world, 20, 20, bed, bed)
	if not bool(info.get("submerged", false)):
		_fail("pool bed should be submerged, depth %.2f" % (waterline - bed))
		return
	if float(info.get("float_y", -1.0)) <= bed + layer * 0.4:
		_fail("creature float line sits on the bed %.2f" % float(info.get("float_y", -1.0)))
	elif float(info.get("speed_mult", 1.0)) > 0.5:
		_fail("swim speed should be under half, got %.2f" % float(info.get("speed_mult", 1.0)))
	else:
		print("OK pool sample float=%.2f bed=%.2f" % [float(info.float_y), bed])

	var tall: Dictionary = _Water.sample(world, 20, 20, bed, bed, layer * 1.6)
	if float(tall.get("float_y", 99.0)) >= float(info.get("float_y", 0.0)):
		_fail("player-height body should sit deeper than a creature")
	else:
		print("OK taller body floats lower %.2f" % float(tall.float_y))

	var river_bed := _feet(world, 60.5, 60.5)
	var wade: Dictionary = _Water.sample(world, 60, 60, river_bed, river_bed)
	if bool(wade.get("submerged", false)) or not bool(wade.get("wading", false)):
		_fail("river tile should wade, not swim: %s" % str(wade))
	else:
		print("OK river wade speed=%.2f" % float(wade.speed_mult))

	var ocean: Dictionary = _Water.sample(world, 70, 70, _feet(world, 70.5, 70.5), _feet(world, 70.5, 70.5))
	if bool(ocean.get("in_water", false)):
		_fail("border ocean must not count as a swim")
	else:
		print("OK ocean stays dry")


func _test_entities(world, layer: float, waterline: float) -> void:
	var bed := _feet(world, 20.5, 20.5)
	var pos := _at(20.5, bed, 20.5)
	for _i in 14:
		pos = _EntityNavigation.step_toward_cell(pos, Vector2i(23, 20), 8.0, 0.05, world, null, null)
	var col := _EntityNavigation.column_pos(pos)
	if col.x <= 20:
		_fail("entity did not cross the pool, stayed at %s y=%.2f" % [str(col), pos.y])
	elif pos.y < bed + layer * 0.8:
		_fail("entity stayed on the bed y=%.2f bed=%.2f" % [pos.y, bed])
	elif pos.y > waterline + 0.05:
		_fail("entity climbed out of the water y=%.2f line=%.2f" % [pos.y, waterline])
	else:
		print("OK entity swam to %s y=%.2f" % [str(col), pos.y])

	var cliff := _feet(world, 24.5, 20.5)
	var floater := _at(23.5, waterline - layer * 0.5, 20.5)
	var stuck := floater
	for _i in 8:
		stuck = _EntityNavigation.step_toward_cell(stuck, Vector2i(26, 20), 8.0, 0.05, world, null, null)
	if _EntityNavigation.column_pos(stuck).x >= 24:
		_fail("entity climbed a cliff out of the pool onto y=%.2f ended %s" % [cliff, str(stuck)])
	elif stuck.y > waterline + 0.2:
		_fail("entity left the waterline while blocked y=%.2f" % stuck.y)
	else:
		print("OK pool cliff still blocks")

	var dry_y := _feet(world, 50.5, 50.5)
	var dry_from := _at(50.5, dry_y, 50.5)
	var dry_to := _EntityNavigation.step_toward_cell(dry_from, Vector2i(55, 50), 8.0, 0.05, world, null, null)
	var dry_step := dry_to.distance_to(dry_from)
	if dry_step < 0.32:
		_fail("dry step too short %.3f" % dry_step)
	elif absf(dry_to.y - dry_y) > layer * 0.2:
		_fail("dry step left the ground y %.2f -> %.2f" % [dry_y, dry_to.y])
	else:
		print("OK dry step %.3f" % dry_step)

	var river_y := _feet(world, 60.5, 60.5)
	var river_from := _at(60.5, river_y, 60.5)
	var river_to := _EntityNavigation.step_toward_cell(river_from, Vector2i(65, 60), 8.0, 0.05, world, null, null)
	var river_step := river_to.distance_to(river_from)
	if river_step > dry_step * 0.85 or river_step < dry_step * 0.45:
		_fail("wade step %.3f should be slower than dry %.3f" % [river_step, dry_step])
	else:
		print("OK wade step %.3f" % river_step)

	var sea_y := _feet(world, 70.5, 70.5)
	var sea_from := _at(70.5, sea_y, 70.5)
	var sea_to := _EntityNavigation.step_toward_cell(sea_from, Vector2i(75, 70), 8.0, 0.05, world, null, null)
	if sea_to.distance_to(sea_from) < dry_step * 0.85:
		_fail("ocean slowed the step like a swim")
	else:
		print("OK ocean step stays full speed")

	var shove_from := _at(21.2, bed, 20.5)
	var shoved := _EntityNavigation.knockback_step(shove_from, Vector3(1, 0, 0), 0.5, world, null, null)
	if shoved.distance_squared_to(shove_from) < 0.04:
		_fail("knockback in the pool did not move")
	elif shoved.y < bed + 0.15:
		_fail("knockback pinned the body to the bed y=%.2f" % shoved.y)
	else:
		print("OK knockback slides in water y=%.2f" % shoved.y)


func _test_player(world, layer: float, waterline: float) -> void:
	var probe := _VoxelFloorProbe.new()
	var chunks := ChunkManager.new()
	chunks.world = world
	probe.configure(world, chunks, null)
	var player := Player.new()
	player.world = world
	player.chunk_manager = chunks
	player._floor_probe = probe

	var bed := probe.sample_walkable_feet(20.5, 20.5)
	player.voxel_position = Vector3(20.5, bed, 20.5)
	player._soft_follow_ground(0.25)
	if player.voxel_position.y < bed + layer * 0.8:
		_fail("player stayed on the pool bed y=%.2f" % player.voxel_position.y)
	elif player.voxel_position.y > waterline - layer * 0.2:
		_fail("player float is too high y=%.2f line=%.2f" % [player.voxel_position.y, waterline])
	elif not player._can_initiate_jump(false):
		_fail("floating player could not hop")
	else:
		print("OK player floats at %.2f" % player.voxel_position.y)

	player.voxel_position = Vector3(21.5, waterline + 4.0, 20.5)
	player.velocity = Vector3(0, -30, 0)
	player.current_state = player.State.FALLING
	if not player._float_if_submerged(0.05, bed):
		_fail("fall into the pool was not caught")
	elif player.voxel_position.y > waterline or absf(player.velocity.y) > 0.01:
		_fail("fall did not settle onto the float line y=%.2f vy=%.2f" % [player.voxel_position.y, player.velocity.y])
	else:
		print("OK fall caught at %.2f" % player.voxel_position.y)

	var dry := probe.sample_walkable_feet(50.5, 50.5)
	player.voxel_position = Vector3(50.5, dry + 6.0, 50.5)
	if player._can_initiate_jump(false):
		_fail("air above dry ground allowed a jump")
	else:
		player.voxel_position.y = dry + 0.45
		player._soft_follow_ground(0.25)
		if absf(player.voxel_position.y - dry) > 0.08:
			_fail("dry ground follow missed the feet y=%.2f feet=%.2f" % [player.voxel_position.y, dry])
		else:
			player.voxel_position.y = dry
			if not player._can_initiate_jump(false):
				_fail("standing on dry ground could not jump")
			else:
				print("OK dry ground follow and jump")
	player.free()
	chunks.free()


## The old check called _soft_follow_ground and _can_initiate_jump directly.
## In the game, Space is a land jump, so the body leaves the water in one tick.
class _SwimDriver extends Player:
	func _ready() -> void:
		pass


func _test_player_input(world, layer: float, waterline: float) -> void:
	var probe := _VoxelFloorProbe.new()
	var chunks := ChunkManager.new()
	chunks.world = world
	probe.configure(world, chunks, null)
	var player := _SwimDriver.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.world = world
	player.chunk_manager = chunks
	player._floor_probe = probe
	player.world_ready = true
	# move_right at yaw 0 walks +X along the trench, the same axis as the D key.
	player.locked_yaw_degrees = 0.0
	player.set_physics_process(false)
	player.set_process(false)
	root.add_child(player)

	var bed := probe.sample_walkable_feet(20.5, 20.5)
	player.voxel_position = Vector3(20.5, bed, 20.5)
	player.current_state = player.State.IDLE
	player._soft_follow_ground(0.5)
	var float_y := player.voxel_position.y
	var start_x := player.voxel_position.x
	Input.action_press("move_right")
	for _i in 27:
		player._process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	var moved := player.voxel_position.x - start_x
	var drifted := absf(player.voxel_position.y - float_y)
	if moved < 0.7:
		_fail("move key in the pool only covered %.2f columns" % moved)
	elif drifted > 0.85:
		_fail("move key left the float line y=%.2f float=%.2f" % [player.voxel_position.y, float_y])
	elif player.voxel_position.y > waterline + 0.15:
		_fail("move key climbed out of the water y=%.2f" % player.voxel_position.y)
	else:
		print("OK move key swam %.2f columns at y=%.2f" % [moved, player.voxel_position.y])

	player.voxel_position = Vector3(21.5, float_y, 20.5)
	player.velocity = Vector3.ZERO
	player._move_vel_xz = Vector2.ZERO
	player.current_state = player.State.IDLE
	player._jump_latched = false
	player._jump_edge = false
	player._jump_buffer = 0.0
	Input.action_press("jump")
	var y0 := player.voxel_position.y
	var ymax := y0
	for _j in 18:
		player._process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
		ymax = maxf(ymax, player.voxel_position.y)
	Input.action_release("jump")
	# A land jump clears the waterline by several layers. A swim stroke stays in the pool.
	if ymax < y0 + 0.45:
		_fail("jump in water did not swim up (%.2f -> %.2f)" % [y0, ymax])
	elif ymax > waterline + layer * 0.5:
		_fail("jump in water was a land jump, rose to %.2f (line %.2f)" % [ymax, waterline])
	elif player.current_state == player.State.JUMPING or player.current_state == player.State.FALLING:
		_fail("jump in water left the swim state %s" % player.current_state)
	else:
		print("OK jump swims up %.2f -> %.2f (line %.2f)" % [y0, ymax, waterline])
	player.free()
	chunks.free()


func _test_callers() -> void:
	var enemy := FileAccess.get_file_as_string("res://entities/crystal_enemy.gd")
	var wildlife := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if enemy.count("step_toward_cell") < 1 or wildlife.count("step_toward_cell") < 1:
		_fail("an entity moves without the shared swim step")
	elif not enemy.contains("knockback_step") or not wildlife.contains("knockback_step"):
		_fail("an entity shove skips the swim step")
	else:
		print("OK wildlife and crystal enemies share the swim step")
