extends SceneTree

const _Body = preload("res://player/player_body_mesh.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFloorProbe = preload("res://player/voxel_floor_probe.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")

const PAD_SURFACE := 10.0
const DT := 1.0 / 60.0

var _failed: int = 0


class _Driver extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_TerrainEdits.reset()
	var world := InfiniteNoiseWorld.new()
	world.world_seed = 99
	_pad(world, 16, 40, 16, 24)
	var player := _make_player(world)
	var rest: PackedVector3Array = _verts(player.player_mesh)
	var boot_i := _boot_index(rest)
	var chest_i := _chest_index(rest)
	var rest_boot: Vector3 = rest[boot_i]
	var rest_chest: Vector3 = rest[chest_i]
	var rest_span := _span_y(rest)

	_tick(player, 45)
	var idle: PackedVector3Array = _verts(player.player_mesh)
	var idle_foot := idle[boot_i].distance_to(rest_boot)
	var idle_chest := idle[chest_i].distance_to(rest_chest)
	var idle_pose := str(player.get("locomotion_pose"))
	if idle_pose != "idle":
		_fail("standing still reported pose %s, want idle" % idle_pose)
	elif idle_chest < 0.08:
		_fail("idle did not move the chest (%.3f m). The mesh is still a statue." % idle_chest)
	elif idle_foot > 0.12:
		_fail("idle swung a boot by %.3f m" % idle_foot)
	else:
		print("OK idle chest %.3f boot %.3f pose %s" % [idle_chest, idle_foot, idle_pose])

	var start_x := player.voxel_position.x
	Input.action_press("move_right")
	var walk_peak := 0.0
	var walk_pose := ""
	for _i in 50:
		_tick(player, 1)
		var posed: PackedVector3Array = _verts(player.player_mesh)
		walk_peak = maxf(walk_peak, posed[boot_i].distance_to(rest_boot))
		walk_pose = str(player.get("locomotion_pose"))
	Input.action_release("move_right")
	var walked := player.voxel_position.x - start_x
	if walked < 0.6:
		_fail("move_right did not walk (%.2f columns)" % walked)
	elif walk_pose != "walk":
		_fail("move_right left pose %s, want walk" % walk_pose)
	elif walk_peak < 0.45:
		_fail("walk moved a boot only %.3f m. Node scale is not a step." % walk_peak)
	else:
		print("OK walk %.2f cols boot %.3f pose %s" % [walked, walk_peak, walk_pose])

	_tick(player, 20)
	Input.action_press("move_right")
	Input.action_press("sprint")
	var run_peak := 0.0
	var run_pose := ""
	for _i in 50:
		_tick(player, 1)
		var posed: PackedVector3Array = _verts(player.player_mesh)
		run_peak = maxf(run_peak, posed[boot_i].distance_to(rest_boot))
		run_pose = str(player.get("locomotion_pose"))
	Input.action_release("sprint")
	Input.action_release("move_right")
	if run_pose != "run":
		_fail("sprint left pose %s, want run" % run_pose)
	elif run_peak < walk_peak * 1.2:
		_fail("run boot %.3f is not past the walk %.3f" % [run_peak, walk_peak])
	else:
		print("OK run boot %.3f vs walk %.3f" % [run_peak, walk_peak])

	_tick(player, 25)
	player._jump_latched = false
	player._jump_edge = false
	player._jump_buffer = 0.0
	Input.action_press("jump")
	var saw_jump := false
	var jump_lift := -1.0
	var saw_fall := false
	var fall_z := 0.0
	var fall_y := 999.0
	var saw_land := false
	var land_span := rest_span
	for _j in 180:
		player._process(DT)
		player._physics_process(DT)
		var posed: PackedVector3Array = _verts(player.player_mesh)
		var pose := str(player.get("locomotion_pose"))
		var boot: Vector3 = posed[boot_i]
		if pose == "jump":
			saw_jump = true
			jump_lift = maxf(jump_lift, boot.y - rest_boot.y)
		elif pose == "fall":
			saw_fall = true
			fall_z = maxf(fall_z, absf(boot.z - rest_boot.z))
			fall_y = minf(fall_y, absf(boot.y - rest_boot.y))
		elif pose == "land":
			saw_land = true
			land_span = minf(land_span, _span_y(posed))
		if saw_land and pose != "land" and pose != "jump":
			break
	Input.action_release("jump")
	if not saw_jump:
		_fail("jump key never posed jump (state %s)" % player.current_state)
	elif jump_lift < 0.35:
		_fail("jump tucked the boot only %.3f m" % jump_lift)
	elif not saw_fall:
		_fail("jump never posed a fall")
	elif fall_z < 0.25 or fall_y > 0.2:
		_fail("fall boot stayed tucked or still (dz %.3f dy %.3f)" % [fall_z, fall_y])
	elif not saw_land:
		_fail("landing never squashed")
	elif land_span > rest_span * 0.82:
		_fail("landing height %.3f stayed near the rest %.3f" % [land_span, rest_span])
	else:
		print("OK jump lift %.3f fall dz %.3f land span %.3f / %.3f" % [jump_lift, fall_z, land_span, rest_span])

	Input.action_release("move_right")
	Input.action_release("sprint")
	Input.action_release("jump")
	var chunks: ChunkManager = player.get_meta("locomotion_chunks")
	player.free()
	chunks.free()
	world.free()
	_TerrainEdits.reset()
	if _failed == 0:
		print("All player locomotion tests OK")
		quit(0)
	else:
		push_error("verify_player_locomotion: %d failure(s)" % _failed)
		quit(1)


func _make_player(world) -> Player:
	var probe := _VoxelFloorProbe.new()
	var chunks := ChunkManager.new()
	chunks.world = world
	probe.configure(world, chunks, null)
	var player := _Driver.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	player.player_mesh = mesh
	var ws = _WorldSettings.get_active()
	_Body.apply_to(mesh, ws.player_height(), ws.player_radius())
	player.world = world
	player.chunk_manager = chunks
	player._floor_probe = probe
	player.world_ready = true
	player.locked_yaw_degrees = 0.0
	player.set_physics_process(false)
	player.set_process(false)
	root.add_child(player)
	var feet := probe.sample_walkable_feet(20.5, 20.5)
	player.voxel_position = Vector3(20.5, feet, 20.5)
	player.current_state = player.State.IDLE
	player.set_meta("locomotion_chunks", chunks)
	return player


func _tick(player: Player, frames: int) -> void:
	for _i in frames:
		player._process(DT)
		player._physics_process(DT)


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var mesh := mi.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() < 1:
		return PackedVector3Array()
	var arrays: Array = mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


func _boot_index(verts: PackedVector3Array) -> int:
	var best_i := 0
	var best_y := 1.0e9
	for i in verts.size():
		var p: Vector3 = verts[i]
		if p.x > 0.02 and p.y < best_y:
			best_y = p.y
			best_i = i
	return best_i


func _chest_index(verts: PackedVector3Array) -> int:
	var best_i := 0
	var best_y := -1.0e9
	for i in verts.size():
		var p: Vector3 = verts[i]
		if absf(p.x) < 0.2 and p.y > best_y:
			best_y = p.y
			best_i = i
	return best_i


func _span_y(verts: PackedVector3Array) -> float:
	var lo := 1.0e9
	var hi := -1.0e9
	for p in verts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


func _pad(world, x0: int, x1: int, z0: int, z1: int) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			_set_surface(world, x, z, PAD_SURFACE)
			_TerrainEdits.set_build_tile_only(x, z, _VoxelTypes.GRASSLAND)


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
