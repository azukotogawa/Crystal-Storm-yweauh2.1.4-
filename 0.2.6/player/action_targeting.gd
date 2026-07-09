class_name ActionTargeting
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


static func _move_yaw_deg(player: Node3D) -> float:
	if player == null:
		return 45.0
	if player.is_input_locked and "locked_move_yaw_deg" in player:
		return float(player.locked_move_yaw_deg)
	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	if cam and cam.has_method("get_move_yaw_deg"):
		return float(cam.get_move_yaw_deg())
	return 45.0


## Match player movement: screen-up (W / ui_up) maps to world forward via camera orbit.
static func _rotate_input_to_world(input: Vector2, yaw_deg: float) -> Vector2:
	var rad := deg_to_rad(yaw_deg)
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
	var fwd2 := _rotate_input_to_world(Vector2(0.0, -1.0), _move_yaw_deg(player))
	return Vector3(fwd2.x, 0.0, fwd2.y).normalized()


static func _player_world(player: Node3D) -> InfiniteNoiseWorld:
	if player != null and "world" in player:
		return player.world as InfiniteNoiseWorld
	return null


static func _column_in_range(player: Node3D, wx: int, wz: int, range_v: float) -> bool:
	var player_xz := Vector2(player.voxel_position.x, player.voxel_position.z)
	var target_xz := Vector2(float(wx) + 0.5, float(wz) + 0.5)
	var dx: float = absf(target_xz.x - player_xz.x)
	var dz: float = absf(target_xz.y - player_xz.y)
	var euclid: float = target_xz.distance_to(player_xz)
	return maxf(euclid, maxf(dx, dz)) <= range_v + 0.35


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


static func _empty_raycast() -> Dictionary:
	return {
		"hit": false,
		"cell": Vector2i.ZERO,
		"column": Vector3.ZERO,
		"surface_y": 0.0,
		"walk_top": 0.0,
		"world_pos": Vector3.ZERO,
		"face_normal": Vector3.ZERO,
		"face_pos": Vector3.ZERO,
		"entity": false,
	}


static func _weapon_mode_from_player(player: Node3D, simulate_interact: bool) -> StringName:
	var weapon := player.get_node_or_null("WeaponController") if player else null
	if weapon and weapon.has_method("get_active_item"):
		var slot = weapon.get_active_item()
		if slot != null:
			var def := _ItemTypes.get_def(str(slot.id))
			if not def.is_empty():
				var category := int(def.get("category", -1))
				var kind := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
				if category == _ItemTypes.Category.TOOL and kind == _ItemTypes.WeaponKind.DIG:
					return &"dig"
				if category == _ItemTypes.Category.WEAPON:
					return &"attack" if kind == _ItemTypes.WeaponKind.MELEE else &"ranged"
				if str(slot.id) == "stone" and int(slot.get("count", 0)) > 0:
					return &"build"
	if (simulate_interact or Input.is_action_pressed("interact")) and player:
		var inv = player.get("inventory") if "inventory" in player else null
		if inv and inv.has_method("count_item") and inv.count_item("stone") > 0:
			return &"build"
	return &"none"


static func _column_passes_ray_filter(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int,
	mode: StringName,
	player: Node3D,
	range_v: float
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
			return _is_solid_column(world, chunk_manager, wx, wz) \
				or _entity_column_near(player, wx, wz, range_v)


static func _column_world_aabb(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	wx: int,
	wz: int
) -> Dictionary:
	var ws = _WorldSettings.get_active()
	var col_x: float = float(wx) + 0.5
	var col_z: float = float(wz) + 0.5
	var surf: float = world.get_surface_height(col_x, col_z)
	var layer: float = ws.layer_height()
	var built_layers: int = maxi(0, int(round(_TerrainEdits.get_height_delta(wx, wz) / layer)))
	var stack_layers: int = maxi(1, 1 + built_layers)
	var y_min: float = surf
	var y_max: float = surf + layer * float(stack_layers)
	var walk: float = _walkable_top(world, chunk_manager, col_x, col_z)
	y_max = maxf(y_max, walk)
	var x_min: float = ws.column_to_world(float(wx))
	var x_max: float = ws.column_to_world(float(wx + 1))
	var z_min: float = ws.column_to_world(float(wz))
	var z_max: float = ws.column_to_world(float(wz + 1))
	return {
		"min": Vector3(x_min, y_min, z_min),
		"max": Vector3(x_max, y_max, z_max),
	}


static func _ray_aabb_intersect(
	origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3
) -> Dictionary:
	var tmin := -INF
	var tmax := INF
	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var mn: float = bmin[axis]
		var mx: float = bmax[axis]
		if absf(d) < 1e-8:
			if o < mn or o > mx:
				return {"hit": false}
			continue
		var inv_d: float = 1.0 / d
		var t0: float = (mn - o) * inv_d
		var t1: float = (mx - o) * inv_d
		var t_enter: float = minf(t0, t1)
		var t_exit: float = maxf(t0, t1)
		tmin = maxf(tmin, t_enter)
		tmax = minf(tmax, t_exit)
		if tmax < tmin:
			return {"hit": false}
	if tmax < 0.0:
		return {"hit": false}
	var t_hit: float = tmin if tmin >= 0.0 else tmax
	if t_hit < 0.0:
		return {"hit": false}
	var point: Vector3 = origin + dir * t_hit
	var normal := Vector3.ZERO
	const EPS := 0.0005
	if absf(point.x - bmin.x) < EPS:
		normal.x = -1.0
	elif absf(point.x - bmax.x) < EPS:
		normal.x = 1.0
	elif absf(point.y - bmin.y) < EPS:
		normal.y = -1.0
	elif absf(point.y - bmax.y) < EPS:
		normal.y = 1.0
	elif absf(point.z - bmin.z) < EPS:
		normal.z = -1.0
	else:
		normal.z = 1.0
	return {"hit": true, "t": t_hit, "normal": normal, "point": point}


static func _ray_plane_face_in_column(
	origin: Vector3,
	dir: Vector3,
	bmin: Vector3,
	bmax: Vector3,
	face_normal: Vector3
) -> Dictionary:
	var n: Vector3 = face_normal.normalized()
	var plane_coord: float
	var axis := 0
	if absf(n.x) > 0.5:
		axis = 0
		plane_coord = bmax.x if n.x > 0.0 else bmin.x
	elif absf(n.y) > 0.5:
		axis = 1
		plane_coord = bmax.y if n.y > 0.0 else bmin.y
	else:
		axis = 2
		plane_coord = bmax.z if n.z > 0.0 else bmin.z
	if absf(dir[axis]) < 1e-6:
		return {"hit": false}
	var t: float = (plane_coord - origin[axis]) / dir[axis]
	if t < 0.0:
		return {"hit": false}
	var p: Vector3 = origin + dir * t
	if p.x < bmin.x - 0.001 or p.x > bmax.x + 0.001 \
			or p.y < bmin.y - 0.001 or p.y > bmax.y + 0.001 \
			or p.z < bmin.z - 0.001 or p.z > bmax.z + 0.001:
		return {"hit": false}
	return {"hit": true, "t": t, "normal": n, "point": p}


static func _ray_column_face_pick(
	origin: Vector3,
	dir: Vector3,
	bmin: Vector3,
	bmax: Vector3,
	side_plane_fallback: bool = true
) -> Dictionary:
	var hit: Dictionary = _ray_aabb_intersect(origin, dir, bmin, bmax)
	if hit.get("hit", false):
		return hit
	var best_t: float = INF
	var best: Dictionary = {"hit": false}
	var face_normals: Array = [Vector3.UP, Vector3.DOWN]
	if side_plane_fallback:
		face_normals.append_array([
			Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.0, 1.0),
		])
	for face_n in face_normals:
		var plane_hit: Dictionary = _ray_plane_face_in_column(origin, dir, bmin, bmax, face_n)
		if not plane_hit.get("hit", false):
			continue
		var t_hit: float = float(plane_hit.t)
		if t_hit < best_t:
			best_t = t_hit
			best = plane_hit
	return best


static func _cursor_column_on_plane(
	origin: Vector3, dir: Vector3, plane_y: float, ws
) -> Vector2i:
	if absf(dir.y) < 1e-6:
		return Vector2i(-99999, -99999)
	var t: float = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return Vector2i(-99999, -99999)
	var p: Vector3 = origin + dir * t
	return Vector2i(floori(ws.world_to_column(p.x)), floori(ws.world_to_column(p.z)))


static func _ray_travel_limit(
	player: Node3D, origin: Vector3, dir: Vector3, range_v: float, ws
) -> float:
	var scale: float = ws.voxel_scale
	var toward_player: float = (player.global_position - origin).dot(dir)
	var reach: float = range_v * scale * 2.5 + scale * 8.0
	return maxf(toward_player + reach, scale * 12.0)


static func _raycast_candidate_cells(
	player: Node3D, origin: Vector3, dir: Vector3, range_v: float, _mouse_only: bool = false
) -> Array:
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var out: Array = []
	var seen: Dictionary = {}
	var push_cell := func(cell: Vector2i) -> void:
		if cell.x < -99990:
			return
		if not _column_in_range(player, cell.x, cell.y, range_v):
			return
		var key := "%d,%d" % [cell.x, cell.y]
		if seen.has(key):
			return
		seen[key] = true
		out.append(cell)
	var max_dist: float = _ray_travel_limit(player, origin, dir, range_v, ws)
	var step: float = maxf(ws.voxel_scale * 0.18, 0.12)
	var dist: float = 0.0
	while dist <= max_dist:
		var p: Vector3 = origin + dir * dist
		push_cell.call(Vector2i(floori(ws.world_to_column(p.x)), floori(ws.world_to_column(p.z))))
		dist += step
	for plane_y in [
		player.voxel_position.y + layer * 1.25,
		player.voxel_position.y + layer * 0.35,
		player.voxel_position.y,
		player.voxel_position.y - layer * 0.35,
		player.voxel_position.y - layer * 1.0,
	]:
		push_cell.call(_cursor_column_on_plane(origin, dir, plane_y, ws))
	return out


static func _face_anchor_from_aabb(bmin: Vector3, bmax: Vector3, normal: Vector3) -> Vector3:
	var c: Vector3 = (bmin + bmax) * 0.5
	if normal.x > 0.5:
		c.x = bmax.x
	elif normal.x < -0.5:
		c.x = bmin.x
	if normal.y > 0.5:
		c.y = bmax.y
	elif normal.y < -0.5:
		c.y = bmin.y
	if normal.z > 0.5:
		c.z = bmax.z
	elif normal.z < -0.5:
		c.z = bmin.z
	return c


## Mouse voxel raycast with per-face hit; optional forward fallback for combat when mouse_only=false.
static func raycast_voxel(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float = 2.0,
	mouse_only: bool = false,
	mode: StringName = &"none",
	screen_override: Vector2 = Vector2(-1.0, -1.0)
) -> Dictionary:
	if player == null or world == null:
		return _empty_raycast()

	var cam: Camera3D = player.get("camera") as Camera3D if "camera" in player else null
	var vp: Viewport = player.get_viewport() if player.is_inside_tree() else null
	if cam != null and vp != null:
		var mouse := screen_override if screen_override.x >= 0.0 else vp.get_mouse_position()
		var origin := cam.project_ray_origin(mouse)
		var dir := cam.project_ray_normal(mouse)
		if dir.length_squared() > 0.00001:
			dir = dir.normalized()
			var best_t: float = INF
			var best := _empty_raycast()
			var candidates: Array = _raycast_candidate_cells(player, origin, dir, range_v, mouse_only)
			var max_ray_t: float = _ray_travel_limit(player, origin, dir, range_v, _WorldSettings.get_active())
			for cell_v in candidates:
				var wx: int = cell_v.x
				var wz: int = cell_v.y
				if not _column_passes_ray_filter(world, chunk_manager, wx, wz, mode, player, range_v):
					continue
				var aabb: Dictionary = _column_world_aabb(world, chunk_manager, wx, wz)
				var hit: Dictionary = _ray_column_face_pick(origin, dir, aabb.min, aabb.max, true)
				if not hit.get("hit", false):
					continue
				var t_hit: float = float(hit.t)
				if t_hit > max_ray_t:
					continue
				if t_hit >= best_t:
					continue
				best_t = t_hit
				var col_x: float = float(wx) + 0.5
				var col_z: float = float(wz) + 0.5
				var surf: float = world.get_surface_height(col_x, col_z)
				var walk: float = _walkable_top(world, chunk_manager, col_x, col_z)
				var solid := _is_solid_column(world, chunk_manager, wx, wz)
				var entity := _entity_column_near(player, wx, wz, range_v)
				var face_normal: Vector3 = hit.normal
				var face_pos: Vector3 = _face_anchor_from_aabb(aabb.min, aabb.max, face_normal)
				best = {
					"hit": true,
					"cell": Vector2i(wx, wz),
					"column": Vector3(col_x, walk, col_z),
					"surface_y": surf,
					"walk_top": walk,
					"world_pos": face_pos,
					"face_normal": face_normal,
					"face_pos": face_pos,
					"entity": entity and not solid,
				}
			if best.get("hit", false):
				return best

	if mouse_only:
		return _empty_raycast()
	return _raycast_voxel_forward(player, world, chunk_manager, range_v, mode)


static func _raycast_voxel_forward(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float,
	mode: StringName = &"none"
) -> Dictionary:
	var forward := attack_forward(player)
	var dist := 0.0
	while dist <= range_v + 0.01:
		var probe: Vector3 = player.voxel_position + forward * dist
		var wx := floori(probe.x)
		var wz := floori(probe.z)
		if _column_in_range(player, wx, wz, range_v) \
				and _column_passes_ray_filter(world, chunk_manager, wx, wz, mode, player, range_v):
			var entity := _entity_column_near(player, wx, wz, range_v)
			var solid := _is_solid_column(world, chunk_manager, wx, wz)
			var ws = _WorldSettings.get_active()
			var col_x: float = float(wx) + 0.5
			var col_z: float = float(wz) + 0.5
			var surf: float = world.get_surface_height(col_x, col_z) if world else 0.0
			var walk: float = _walkable_top(world, chunk_manager, col_x, col_z)
			var layer: float = ws.layer_height()
			var face_normal := Vector3(0.0, 1.0, 0.0)
			var face_pos := Vector3(ws.column_to_world(col_x), walk, ws.column_to_world(col_z))
			if mode == &"dig":
				face_normal = Vector3(0.0, 1.0, 0.0)
				face_pos.y = walk - layer * 0.5
			return {
				"hit": true,
				"cell": Vector2i(wx, wz),
				"column": Vector3(col_x, walk, col_z),
				"surface_y": surf,
				"walk_top": walk,
				"world_pos": face_pos,
				"face_normal": face_normal,
				"face_pos": face_pos,
				"entity": entity and not solid,
			}
		dist += 0.35
	return _empty_raycast()


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


static func target_column(player: Node3D, range_v: float = 2.0, mode: StringName = &"any") -> Vector3:
	var info := resolve_action(player, _player_world(player),
		player.get_tree().get_first_node_in_group("chunk_manager") if player and player.is_inside_tree() else null,
		range_v, false, mode)
	if info.get("valid", false):
		return info.get("column", Vector3.ZERO)
	return Vector3.ZERO


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
	simulate_interact: bool = false,
	force_mode: StringName = &""
) -> Dictionary:
	var mode: StringName = _weapon_mode_from_player(player, simulate_interact)
	if force_mode != &"" and force_mode != &"any":
		mode = force_mode
	var mouse_only: bool = force_mode == &"" or force_mode == &"any"
	var hit := raycast_voxel(player, world, chunk_manager, range_v, mouse_only, mode)
	if not hit.get("hit", false):
		return {
			"column": Vector3.ZERO,
			"cell": Vector2i.ZERO,
			"surface_y": 0.0,
			"world_pos": Vector3.ZERO,
			"face_normal": Vector3.ZERO,
			"mode": &"none",
			"valid": false,
			"range": range_v,
		}
	var wx: int = hit.cell.x
	var wz: int = hit.cell.y
	var col: Vector3 = Vector3(float(wx) + 0.5, hit.walk_top, float(wz) + 0.5)
	var surf: float = float(hit.surface_y)
	var walk_top: float = float(hit.walk_top)
	var layer_h: float = _WorldSettings.get_active().layer_height()
	var entity_hit: bool = bool(hit.get("entity", false))
	var face_normal: Vector3 = hit.get("face_normal", Vector3.UP)
	var world_pos: Vector3 = hit.get("face_pos", hit.get("world_pos", Vector3.ZERO))
	if mode == &"build":
		var ws = _WorldSettings.get_active()
		var built_layers: int = maxi(0, int(round(_TerrainEdits.get_height_delta(wx, wz) / layer_h)))
		world_pos = Vector3(
			(ws.column_to_world(float(wx)) + ws.column_to_world(float(wx + 1))) * 0.5,
			walk_top + layer_h * (float(built_layers) + 0.5),
			(ws.column_to_world(float(wz)) + ws.column_to_world(float(wz + 1))) * 0.5,
		)
		face_normal = Vector3.UP
	elif mode == &"attack" and (entity_hit or not _is_solid_column(world, chunk_manager, wx, wz)):
		world_pos.y = walk_top + layer_h * 0.35
		face_normal = Vector3.UP
	var valid := mode != &"none" and _is_action_valid(world, chunk_manager, wx, wz, mode, player, range_v)
	if not valid:
		mode = &"none"
	return {
		"column": col,
		"cell": Vector2i(wx, wz),
		"surface_y": surf,
		"world_pos": world_pos,
		"face_normal": face_normal,
		"mode": mode,
		"valid": valid,
		"range": range_v,
	}