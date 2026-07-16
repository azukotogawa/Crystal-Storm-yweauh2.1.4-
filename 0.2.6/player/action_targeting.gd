class_name ActionTargeting
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


static func _orbit_index(player: Node3D) -> int:
	if player == null:
		return 0
	if player.is_input_locked:
		return int(player.locked_rotation)
	if player.camera:
		return int(player.camera.orbit_rotation)
	return 0


## Match player movement: screen-up (W / ui_up) maps to world forward via camera orbit.
static func _rotate_input_to_world(input: Vector2, rot: int) -> Vector2:
	var angle := float(rot) * 90.0 + 45.0
	var rad := deg_to_rad(angle)
	var ca := cos(rad)
	var sa := sin(rad)
	return Vector2(input.x * ca + input.y * sa, input.y * ca - input.x * sa)


static func attack_forward(player: Node3D) -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	if cam:
		var flat := -cam.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			return flat.normalized()
	var rot := _orbit_index(player)
	var fwd2 := _rotate_input_to_world(Vector2(0.0, -1.0), rot)
	return Vector3(fwd2.x, 0.0, fwd2.y).normalized()


static func _player_world(player: Node3D) -> InfiniteNoiseWorld:
	if player != null and "world" in player:
		return player.world as InfiniteNoiseWorld
	return null


static func _column_in_range(player: Node3D, wx: int, wz: int, range_v: float) -> bool:
	var player_xz := Vector2(player.voxel_position.x, player.voxel_position.z)
	var target_xz := Vector2(float(wx) + 0.5, float(wz) + 0.5)
	return target_xz.distance_to(player_xz) <= range_v + 0.01


static func _is_fluid_tile(tile: int) -> bool:
	return tile in [
		_VoxelTypes.AIR,
		_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3,
		_VoxelTypes.RIVER, _VoxelTypes.WATER,
	]


static func _is_column_loaded(chunk_manager: ChunkManager, wx: int, wz: int) -> bool:
	if chunk_manager == null:
		return true
	if chunk_manager.has_method("is_world_cell_loaded"):
		return chunk_manager.is_world_cell_loaded(wx, wz)
	return true


static func _is_solid_column(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int
) -> bool:
	if not _TerrainEdits.can_edit(wx, wz):
		return false
	if not _is_column_loaded(chunk_manager, wx, wz):
		return false
	if world == null:
		return true
	var tile: int = world.get_tile_type(float(wx), float(wz))
	if _is_fluid_tile(tile):
		return false
	var surf: float = world.get_surface_height(float(wx), float(wz))
	return world.get_solid(float(wx), surf, float(wz))


static func _can_dig_column(world: InfiniteNoiseWorld, chunk_manager: ChunkManager, wx: int, wz: int) -> bool:
	if not _is_solid_column(world, chunk_manager, wx, wz):
		return false
	var min_h: float = -_WorldSettings.get_active().layer_height() * 4.0
	return world.get_surface_height(float(wx), float(wz)) > min_h + 0.01


static func _walkable_top(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	col_x: float,
	col_z: float
) -> float:
	if world == null:
		return _WorldSettings.get_active().layer_height()
	var entry: Dictionary = {}
	if chunk_manager and chunk_manager.has_method("get_ramp_entry_at_world"):
		entry = chunk_manager.get_ramp_entry_at_world(col_x, col_z)
	return _TerrainRamps.walkable_height_from_entry(world, col_x, col_z, entry)


static func _segment_hits_y_band(y0: float, y1: float, band_min: float, band_max: float) -> bool:
	var lo: float = minf(y0, y1)
	var hi: float = maxf(y0, y1)
	return hi >= band_min and lo <= band_max


static func _surface_slab_bounds(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int
) -> Vector2:
	var ws = _WorldSettings.get_active()
	var col_x: float = float(wx) + 0.5
	var col_z: float = float(wz) + 0.5
	var walk: float = _walkable_top(world, chunk_manager, col_x, col_z)
	var layer: float = ws.layer_height()
	var built_layers: int = maxi(0, int(round(_TerrainEdits.get_height_delta(wx, wz) / layer)))
	var layers: int = maxi(1, 1 + built_layers)
	return Vector2(walk - layer * 0.08, walk + layer * float(layers) + layer * 0.12)


static func _ray_y_hits_surface_slab(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int,
	ray_y: float
) -> bool:
	var slab := _surface_slab_bounds(world, chunk_manager, wx, wz)
	return ray_y >= slab.x and ray_y <= slab.y


static func _entity_column_near(player: Node3D, wx: int, wz: int, range_v: float) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	var ws = _WorldSettings.get_active()
	var col := Vector2(float(wx) + 0.5, float(wz) + 0.5)
	for group_name in ["world_entity", "crystal_enemy"]:
		for node in player.get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if node.has_method("is_combat_alive") and not node.is_combat_alive():
				continue
			var pos: Vector3 = node.global_position
			var ecx: float = ws.world_to_column(pos.x)
			var ecz: float = ws.world_to_column(pos.z)
			if Vector2(ecx, ecz).distance_to(col) <= 0.85:
				if _column_in_range(player, wx, wz, range_v):
					return true
	return false


static func _can_build_column(world: InfiniteNoiseWorld, chunk_manager: ChunkManager, wx: int, wz: int) -> bool:
	if not _is_solid_column(world, chunk_manager, wx, wz):
		return false
	var ws = _WorldSettings.get_active()
	var built_layers: int = int(round(_TerrainEdits.get_height_delta(wx, wz) / ws.layer_height()))
	return built_layers < 8


static func _is_action_valid(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int,
	mode: StringName,
	player: Node3D = null,
	range_v: float = 2.0
) -> bool:
	match mode:
		&"dig":
			return _can_dig_column(world, chunk_manager, wx, wz)
		&"build":
			return _can_build_column(world, chunk_manager, wx, wz)
		&"attack", &"ranged":
			return _is_solid_column(world, chunk_manager, wx, wz) \
				or _entity_column_near(player, wx, wz, range_v)
		_:
			return false


static func _target_column_forward(
	player: Node3D,
	range_v: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager
) -> Vector3:
	var forward := attack_forward(player)
	var dist := 0.0
	while dist <= range_v + 0.01:
		var probe: Vector3 = player.voxel_position + forward * dist
		var wx := floori(probe.x)
		var wz := floori(probe.z)
		if _column_in_range(player, wx, wz, range_v) \
				and _is_solid_column(world, chunk_manager, wx, wz):
			return Vector3(float(wx) + 0.5, player.voxel_position.y, float(wz) + 0.5)
		dist += 0.35
	return Vector3.ZERO


static func _pick_column_from_mouse(
	player: Node3D,
	range_v: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager
) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	var vp: Viewport = player.get_viewport()
	if cam == null or vp == null:
		return Vector3.ZERO
	var ws = _WorldSettings.get_active()
	var mouse := vp.get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.length_squared() < 0.00001:
		return Vector3.ZERO
	dir = dir.normalized()

	if world != null:
		var step: float = ws.voxel_scale * 0.25
		var max_dist: float = minf((range_v + 1.0) * ws.voxel_scale * 2.5, 72.0)
		var prev: Vector3 = origin
		var t: float = 0.0
		var best_t: float = INF
		var best_col := Vector3.ZERO
		while t <= max_dist:
			var p: Vector3 = origin + dir * t
			var wx := floori(ws.world_to_column(p.x))
			var wz := floori(ws.world_to_column(p.z))
			if _column_in_range(player, wx, wz, range_v):
				var col_x: float = float(wx) + 0.5
				var col_z: float = float(wz) + 0.5
				var hits_slab := _ray_y_hits_surface_slab(world, chunk_manager, wx, wz, p.y)
				var hits_entity := _entity_column_near(player, wx, wz, range_v)
				if hits_slab and _is_solid_column(world, chunk_manager, wx, wz):
					if t < best_t:
						best_t = t
						best_col = Vector3(col_x, player.voxel_position.y, col_z)
				elif hits_entity and t < best_t:
					best_t = t
					best_col = Vector3(col_x, player.voxel_position.y, col_z)
			prev = p
			t += step
		if best_col != Vector3.ZERO:
			return best_col

	return Vector3.ZERO


## Screen position for a column center (probes / warp_mouse).
static func screen_pos_for_column(
	player: Node3D,
	world: InfiniteNoiseWorld,
	col_x: float,
	col_z: float
) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	if cam == null:
		return Vector2.ZERO
	var ws = _WorldSettings.get_active()
	var surf: float = world.get_surface_height(col_x, col_z) if world else player.voxel_position.y
	var y: float = surf + ws.layer_height()
	if world:
		var cm: ChunkManager = player.get_tree().get_first_node_in_group("chunk_manager") if player.is_inside_tree() else null
		y = _walkable_top(world, cm, col_x, col_z)
	var world_pos := Vector3(ws.column_to_world(col_x), y, ws.column_to_world(col_z))
	return cam.unproject_position(world_pos)


static func warp_mouse_to_column(
	player: Node3D,
	world: InfiniteNoiseWorld,
	col_x: float,
	col_z: float
) -> void:
	if player == null:
		return
	var vp: Viewport = player.get_viewport()
	if vp == null:
		return
	var screen := screen_pos_for_column(player, world, col_x, col_z)
	if screen.x >= 0.0 and screen.y >= 0.0:
		vp.warp_mouse(screen)


## Flat XZ direction from player toward mouse/forward target column (melee swing facing).
static func attack_toward_column(player: Node3D, range_v: float = 2.0) -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var col := target_column(player, range_v)
	var offset := Vector3(col.x - player.voxel_position.x, 0.0, col.z - player.voxel_position.z)
	if offset.length_squared() > 0.0001:
		return offset.normalized()
	return attack_forward(player)


static func target_column(player: Node3D, range_v: float = 2.0) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var world := _player_world(player)
	var chunk_manager: ChunkManager = player.get_tree().get_first_node_in_group("chunk_manager") if player.is_inside_tree() else null
	var mouse_col := _pick_column_from_mouse(player, range_v, world, chunk_manager)
	if mouse_col != Vector3.ZERO:
		return mouse_col
	return _target_column_forward(player, range_v, world, chunk_manager)


static func attack_origin_world(player: Node3D, chest_ratio: float = 0.5) -> Vector3:
	if player == null:
		return Vector3.ZERO
	return player.global_position + Vector3(0.0, Player.get_player_height() * chest_ratio, 0.0)


static func attack_forward_world(player: Node3D) -> Vector3:
	return attack_forward(player)


static func cell_column(target_col: Vector3) -> Vector2i:
	return Vector2i(floori(target_col.x), floori(target_col.z))


static func target_cell(player: Node3D, range_v: float = 2.0) -> Vector2i:
	return cell_column(target_column(player, range_v))


static func resolve_action(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float = 2.0,
	simulate_interact: bool = false
) -> Dictionary:
	var col := target_column(player, range_v)
	if col == Vector3.ZERO:
		return {
			"column": Vector3.ZERO,
			"cell": Vector2i.ZERO,
			"surface_y": 0.0,
			"world_pos": Vector3.ZERO,
			"mode": &"none",
			"valid": false,
			"range": range_v,
		}
	var wx := floori(col.x)
	var wz := floori(col.z)
	col = Vector3(float(wx) + 0.5, col.y, float(wz) + 0.5)
	var surf: float = world.get_surface_height(col.x, col.z) if world else col.y
	var ws = _WorldSettings.get_active()
	var walk_top: float = surf + ws.layer_height()
	if world:
		walk_top = _walkable_top(world, chunk_manager, col.x, col.z)
	var layer_h: float = ws.layer_height()
	var built_layers: int = maxi(0, int(round(_TerrainEdits.get_height_delta(wx, wz) / layer_h)))
	var mode := &"none"
	var weapon := player.get_node_or_null("WeaponController") if player else null
	if weapon and weapon.has_method("get_active_item"):
		var slot = weapon.get_active_item()
		if slot != null:
			var def := _ItemTypes.get_def(str(slot.id))
			if not def.is_empty():
				var category := int(def.get("category", -1))
				var kind := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
				if category == _ItemTypes.Category.TOOL and kind == _ItemTypes.WeaponKind.DIG:
					mode = &"dig"
				elif category == _ItemTypes.Category.WEAPON:
					mode = &"attack" if kind == _ItemTypes.WeaponKind.MELEE else &"ranged"
				elif str(slot.id) == "stone" and int(slot.get("count", 0)) > 0:
					mode = &"build"
	if (simulate_interact or Input.is_action_pressed("interact")) and mode == &"none":
		var inv = player.get("inventory") if player else null
		if inv and inv.has_method("count_item") and inv.count_item("stone") > 0:
			mode = &"build"
	var valid := mode != &"none" and _is_action_valid(world, chunk_manager, wx, wz, mode, player, range_v)
	if not valid:
		mode = &"none"
	var highlight_y: float = walk_top - layer_h * 0.5
	if mode == &"build":
		highlight_y = walk_top + layer_h * (float(built_layers) + 0.5)
	elif mode in [&"attack", &"ranged"] and not _is_solid_column(world, chunk_manager, wx, wz):
		highlight_y = walk_top + layer_h * 0.35
	var world_pos := Vector3(
		ws.column_to_world(col.x),
		highlight_y,
		ws.column_to_world(col.z)
	)
	return {
		"column": col,
		"cell": Vector2i(wx, wz),
		"surface_y": surf,
		"world_pos": world_pos,
		"mode": mode,
		"valid": valid,
		"range": range_v,
	}