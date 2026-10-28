class_name ActionTargeting
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _FacePick = preload("res://player/face_pick.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")

static var last_pick_cell := Vector3i.ZERO
static var last_pick_normal := Vector3i.ZERO


static func reach() -> float:
	return _GameFeelConfig.active().brush_reach
## Slack as a fraction of voxel_scale. Just under half a column, so a ray through
## a cell center is not stolen by a neighbor.
const PICK_TOLERANCE_SCALE := 0.45
static var last_pick_face: int = 0
static var last_pick_exact: bool = false
static var _event_pos := Vector2.ZERO
static var _event_ok := false
static var _aabb_t: float = 0.0
static var _aabb_face: int = 0
static var _box_min: Vector3 = Vector3.ZERO
static var _box_max: Vector3 = Vector3.ZERO


static func _camera_yaw_degrees(player: Node3D) -> float:
	if player == null:
		return 45.0
	var cam = player.get("camera")
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "orbit_yaw_deg" in cam:
		return float(cam.orbit_yaw_deg)
	if cam != null and "orbit_rotation" in cam:
		return 45.0 + float(cam.orbit_rotation) * 90.0
	return 45.0


static func _rotate_input_to_world(input: Vector2, yaw_degrees: float) -> Vector2:
	var rad := deg_to_rad(yaw_degrees)
	var ca := cos(rad)
	var sa := sin(rad)
	return Vector2(input.x * ca + input.y * sa, input.y * ca - input.x * sa)


static func attack_forward(player: Node3D) -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var cam: Camera3D = player.get("camera") as Camera3D
	if cam:
		var flat := -cam.global_transform.basis.z
		flat.y = 0.0
		if flat.length_squared() > 0.0001:
			return flat.normalized()
	var yaw := _camera_yaw_degrees(player)
	var fwd2 := _rotate_input_to_world(Vector2(0.0, -1.0), yaw)
	return Vector3(fwd2.x, 0.0, fwd2.y).normalized()


static func _player_world(player: Node3D) -> InfiniteNoiseWorld:
	if player != null and "world" in player:
		return player.world as InfiniteNoiseWorld
	return null


static func _column_in_range(player: Node3D, wx: int, wz: int, range_v: float) -> bool:
	if player == null:
		return false
	var px: float
	var pz: float
	if player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		px = v.x
		pz = v.z
	elif "voxel_position" in player:
		px = float(player.voxel_position.x)
		pz = float(player.voxel_position.z)
	else:
		var ws = _WorldSettings.get_active()
		px = ws.world_to_column(player.global_position.x)
		pz = ws.world_to_column(player.global_position.z)
	var player_xz := Vector2(px, pz)
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
	if not chunk_manager.has_method("is_world_cell_loaded"):
		return true
	# Empty streamer (or unit probes): do not treat the world as unloaded for targeting.
	if "chunks" in chunk_manager and chunk_manager.chunks is Dictionary:
		if (chunk_manager.chunks as Dictionary).is_empty():
			return true
	return chunk_manager.is_world_cell_loaded(wx, wz)


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
	if _is_fluid_tile(tile) or _ChannelRegistry.has_fluid(wx, wz, _ChannelRegistry.FLUID_WATER):
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
	var wx: int = floori(col_x)
	var wz: int = floori(col_z)
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if bool(feat.get("is_bridge", false)) or str(feat.get("build_id", "")) == "bridge":
		var ws = _WorldSettings.get_active()
		var surf: float = world.get_surface_height(float(wx), float(wz))
		var delta: float = _TerrainEdits.get_height_delta(wx, wz)
		var deck: float = surf - delta if delta < -0.01 else surf
		return deck + ws.layer_height()
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
	# Spatial index stores world-space positions (voxel_scale); probe must match.
	var probe := Vector3(
		ws.column_to_world(float(wx) + 0.5),
		0.0,
		ws.column_to_world(float(wz) + 0.5)
	)
	var world_radius: float = 1.5 * ws.voxel_scale
	var svc = player.get_tree().get_first_node_in_group("spatial_query_service")
	if svc and svc.has_method("query_combat_candidates"):
		var hits: Array = svc.query_combat_candidates(probe, world_radius)
		for h in hits:
			var node = h.get("payload")
			if not is_instance_valid(node):
				continue
			if node.has_method("is_combat_alive") and not node.is_combat_alive():
				continue
			var pos: Vector3 = node.global_position if "global_position" in node else h.pos
			var ecx: float = ws.world_to_column(pos.x)
			var ecz: float = ws.world_to_column(pos.z)
			if Vector2(ecx, ecz).distance_to(col) <= 0.85:
				if _column_in_range(player, wx, wz, range_v):
					return true
		# Do not early-return empty: fall through to group scan if index is cold.
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
	if forward.length_squared() < 0.0001:
		forward = Vector3(1.0, 0.0, 0.0)
	var stand := Vector2i(floori(player.voxel_position.x), floori(player.voxel_position.z))
	var dist := 0.0
	var last_in_range := Vector3.ZERO
	while dist <= range_v + 0.01:
		var probe: Vector3 = player.voxel_position + forward * dist
		var wx := floori(probe.x)
		var wz := floori(probe.z)
		if wx == stand.x and wz == stand.y:
			dist += 0.35
			continue
		if _column_in_range(player, wx, wz, range_v):
			last_in_range = Vector3(float(wx) + 0.5, player.voxel_position.y, float(wz) + 0.5)
			if _is_solid_column(world, chunk_manager, wx, wz):
				return last_in_range
		dist += 0.35
	if last_in_range != Vector3.ZERO:
		return last_in_range
	var fallback: Vector3 = player.voxel_position + forward * minf(range_v, 1.25)
	return Vector3(float(floori(fallback.x)) + 0.5, player.voxel_position.y, float(floori(fallback.z)) + 0.5)


static func _pick_column_from_mouse(
	player: Node3D,
	range_v: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	require_in_range: bool = true
) -> Vector3:
	if player == null or _GameplayInput.free_look:
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	var vp: Viewport = player.get_viewport()
	if cam == null or vp == null:
		return Vector3.ZERO
	var ws = _WorldSettings.get_active()
	var mouse := pointer_in(vp)
	var rect := vp.get_visible_rect()
	if rect.size.x > 4.0 and rect.size.y > 4.0:
		if mouse.x < rect.position.x - 2.0 or mouse.y < rect.position.y - 2.0 \
				or mouse.x > rect.end.x + 2.0 or mouse.y > rect.end.y + 2.0:
			return Vector3.ZERO
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.length_squared() < 0.00001:
		return Vector3.ZERO
	dir = dir.normalized()
	if absf(dir.y) < 0.00001:
		return Vector3.ZERO

	var reach: float = range_v if require_in_range else INF
	var hit: Dictionary = _FacePick.pick(world, origin, dir, _FacePick.eye(player), reach)
	last_pick_face = 0
	last_pick_exact = false
	var block_t: float = float(hit.get("t", INF)) if bool(hit.get("hit", false)) else INF
	var body = _hitbox_under_ray(player, origin, dir, block_t)
	if body != null:
		var bx := floori(ws.world_to_column(body.global_position.x))
		var bz := floori(ws.world_to_column(body.global_position.z))
		if require_in_range and not _column_in_range(player, bx, bz, range_v):
			return Vector3.ZERO
		return Vector3(float(bx) + 0.5, player.voxel_position.y, float(bz) + 0.5)
	if not bool(hit.get("hit", false)):
		return Vector3.ZERO
	var cell: Vector3i = hit.cell
	var normal: Vector3i = hit.normal
	last_pick_face = _FacePick.face_code(normal)
	last_pick_exact = true
	last_pick_cell = cell
	last_pick_normal = normal
	var col := Vector2i(cell.x, cell.z)
	var building := Input.is_action_pressed("interact") or Input.is_action_pressed("build_place")
	if normal.y == 0 and _weapon_mode_from_player(player, building) == &"build":
		col += Vector2i(normal.x, normal.z)
	return Vector3(float(col.x) + 0.5, player.voxel_position.y, float(col.y) + 0.5)


static func _hitbox_under_ray(player: Node3D, origin: Vector3, dir: Vector3, max_t: float) -> Node3D:
	if not player.is_inside_tree():
		return null
	var ws = _WorldSettings.get_active()
	var half: float = 0.4 * ws.voxel_scale
	var height: float = Player.get_player_height()
	var best: Node3D = null
	var best_t := max_t
	for group_name in ["world_entity", "crystal_enemy"]:
		for node in player.get_tree().get_nodes_in_group(group_name):
			if not (node is Node3D) or not is_instance_valid(node) or node == player:
				continue
			if node.has_method("is_combat_alive") and not node.is_combat_alive():
				continue
			var p: Vector3 = node.global_position
			var box := AABB(Vector3(p.x - half, p.y, p.z - half), Vector3(half * 2.0, height, half * 2.0))
			var t := _ray_box_t(origin, dir, box)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = node
	return best


static func _ray_box_t(origin: Vector3, dir: Vector3, box: AABB) -> float:
	var t0 := -INF
	var t1 := INF
	for a in 3:
		if absf(dir[a]) < 0.0000001:
			if origin[a] < box.position[a] or origin[a] > box.end[a]:
				return -1.0
			continue
		var ta: float = (box.position[a] - origin[a]) / dir[a]
		var tb: float = (box.end[a] - origin[a]) / dir[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 < maxf(t0, 0.0):
		return -1.0
	return maxf(t0, 0.0)


static func pick_along_ray(
	origin: Vector3,
	dir: Vector3,
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float,
	require_in_range: bool = true
) -> Dictionary:
	last_pick_face = 0
	last_pick_exact = false
	var miss := {"column": Vector3.ZERO, "face": 0, "hit": false, "exact": false}
	if world == null or dir.length_squared() < 0.0000001:
		return miss
	dir = dir.normalized()
	var ws = _WorldSettings.get_active()
	var scale: float = maxf(ws.voxel_scale, 0.001)
	var tol: float = scale * PICK_TOLERANCE_SCALE
	var max_dist: float = minf((range_v + 6.0) * scale * 4.0, 180.0)
	var cx: int = floori(ws.world_to_column(origin.x))
	var cz: int = floori(ws.world_to_column(origin.z))
	var step_x: int = 1 if dir.x >= 0.0 else -1
	var step_z: int = 1 if dir.z >= 0.0 else -1
	var huge := 1.0e20
	var t_delta_x: float = huge if absf(dir.x) < 0.0000001 else absf(scale / dir.x)
	var t_delta_z: float = huge if absf(dir.z) < 0.0000001 else absf(scale / dir.z)
	var next_x: float = ws.column_to_world(float(cx + (1 if step_x > 0 else 0)))
	var next_z: float = ws.column_to_world(float(cz + (1 if step_z > 0 else 0)))
	var t_max_x: float = huge if absf(dir.x) < 0.0000001 else (next_x - origin.x) / dir.x
	var t_max_z: float = huge if absf(dir.z) < 0.0000001 else (next_z - origin.z) / dir.z
	var near_d := tol
	var near_cell := Vector2i(cx, cz)
	var near_face := 0
	var found_near := false
	for _step in 48:
		var exact: Dictionary = _exact_cell(origin, dir, cx, cz, player, world, chunk_manager, range_v, require_in_range, max_dist)
		if bool(exact.get("reject", false)):
			# The ray hit something past interaction range. Do not pull that cell inward.
			break
		if bool(exact.get("hit", false)):
			return exact
		_consider_near(origin, dir, cx, cz, player, world, chunk_manager, range_v, require_in_range, max_dist, tol)
		if _near_found and _near_dist < near_d:
			near_d = _near_dist
			near_cell = _near_cell
			near_face = _near_face
			found_near = true
		_consider_near(origin, dir, cx + 1, cz, player, world, chunk_manager, range_v, require_in_range, max_dist, tol)
		if _near_found and _near_dist < near_d:
			near_d = _near_dist
			near_cell = _near_cell
			near_face = _near_face
			found_near = true
		_consider_near(origin, dir, cx - 1, cz, player, world, chunk_manager, range_v, require_in_range, max_dist, tol)
		if _near_found and _near_dist < near_d:
			near_d = _near_dist
			near_cell = _near_cell
			near_face = _near_face
			found_near = true
		_consider_near(origin, dir, cx, cz + 1, player, world, chunk_manager, range_v, require_in_range, max_dist, tol)
		if _near_found and _near_dist < near_d:
			near_d = _near_dist
			near_cell = _near_cell
			near_face = _near_face
			found_near = true
		_consider_near(origin, dir, cx, cz - 1, player, world, chunk_manager, range_v, require_in_range, max_dist, tol)
		if _near_found and _near_dist < near_d:
			near_d = _near_dist
			near_cell = _near_cell
			near_face = _near_face
			found_near = true
		if t_max_x < t_max_z:
			if t_max_x > max_dist:
				break
			cx += step_x
			t_max_x += t_delta_x
		else:
			if t_max_z > max_dist:
				break
			cz += step_z
			t_max_z += t_delta_z
	if found_near:
		return _finish_pick(near_cell.x, near_cell.y, near_face, false, player)
	return miss


static func _exact_cell(
	origin: Vector3,
	dir: Vector3,
	wx: int,
	wz: int,
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float,
	require_in_range: bool,
	max_dist: float
) -> Dictionary:
	_set_column_box(world, chunk_manager, wx, wz)
	if not _ray_aabb(origin, dir, _box_min, _box_max):
		return {"hit": false, "reject": false}
	if _aabb_t < 0.0 or _aabb_t > max_dist:
		return {"hit": false, "reject": false}
	if require_in_range and player != null and not _column_in_range(player, wx, wz, range_v):
		return {"hit": false, "reject": true}
	return _finish_pick(wx, wz, _aabb_face, true, player)


static func _consider_near(
	origin: Vector3,
	dir: Vector3,
	wx: int,
	wz: int,
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float,
	require_in_range: bool,
	max_dist: float,
	tol: float
) -> void:
	_near_found = false
	if require_in_range and player != null and not _column_in_range(player, wx, wz, range_v):
		return
	_set_column_box(world, chunk_manager, wx, wz)
	var dist: float = _ray_box_distance(origin, dir, _box_min, _box_max, max_dist)
	if dist <= 0.001 or dist >= tol:
		return
	_near_found = true
	_near_dist = dist
	_near_cell = Vector2i(wx, wz)
	_near_face = _nearest_face(origin, dir, _box_min, _box_max, max_dist)


static var _near_dist: float = INF
static var _near_cell: Vector2i = Vector2i.ZERO
static var _near_face: int = 0
static var _near_found: bool = false


static func _finish_pick(wx: int, wz: int, face: int, exact: bool, _player: Node3D) -> Dictionary:
	last_pick_face = face
	last_pick_exact = exact
	var col := Vector3(float(wx) + 0.5, 0.0, float(wz) + 0.5)
	if _player != null and "voxel_position" in _player:
		col.y = float(_player.voxel_position.y)
	return {"column": col, "face": face, "hit": true, "exact": exact, "reject": false}


static func _snap_near_miss(
	origin: Vector3,
	dir: Vector3,
	plane_col: Vector3,
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float,
	require_in_range: bool
) -> Vector3:
	if world == null:
		last_pick_face = 0
		last_pick_exact = false
		return plane_col
	var nd := dir.normalized() if dir.length_squared() > 0.0000001 else Vector3.DOWN
	var wx := floori(plane_col.x)
	var wz := floori(plane_col.z)
	var exact: Dictionary = _exact_cell(origin, nd, wx, wz, player, world, chunk_manager, range_v, false, 400.0)
	if bool(exact.get("hit", false)):
		return plane_col
	var ws = _WorldSettings.get_active()
	var tol: float = ws.voxel_scale * PICK_TOLERANCE_SCALE
	var best_d := tol
	var best := Vector2i(wx, wz)
	var best_face := 0
	var found := false
	var best_exact_t := INF
	var exact_col := plane_col
	var exact_face := 0
	var found_exact := false
	for ox in range(-1, 2):
		for oz in range(-1, 2):
			var cx: int = wx + ox
			var cz: int = wz + oz
			if cx == wx and cz == wz:
				continue
			if require_in_range and player != null and not _column_in_range(player, cx, cz, range_v):
				continue
			_set_column_box(world, chunk_manager, cx, cz)
			if _ray_aabb(origin, nd, _box_min, _box_max) and _aabb_t >= 0.0 and _aabb_t < best_exact_t and _aabb_t <= 400.0:
				best_exact_t = _aabb_t
				exact_face = _aabb_face
				exact_col = Vector3(float(cx) + 0.5, plane_col.y, float(cz) + 0.5)
				found_exact = true
				continue
			var dist: float = _ray_box_distance(origin, nd, _box_min, _box_max, 400.0)
			if dist < best_d:
				best_d = dist
				best = Vector2i(cx, cz)
				best_face = _nearest_face(origin, nd, _box_min, _box_max, 400.0)
				found = true
	if found_exact:
		last_pick_face = exact_face
		last_pick_exact = true
		return exact_col
	if found and (best.x != wx or best.y != wz):
		last_pick_face = best_face
		last_pick_exact = false
		return Vector3(float(best.x) + 0.5, plane_col.y, float(best.y) + 0.5)
	last_pick_face = 0
	last_pick_exact = false
	return plane_col


static func _set_column_box(world: InfiniteNoiseWorld, chunk_manager: ChunkManager, wx: int, wz: int) -> void:
	var ws = _WorldSettings.get_active()
	var slab: Vector2 = _surface_slab_bounds(world, chunk_manager, wx, wz)
	_box_min = Vector3(ws.column_to_world(float(wx)), slab.x, ws.column_to_world(float(wz)))
	_box_max = Vector3(ws.column_to_world(float(wx + 1)), slab.y, ws.column_to_world(float(wz + 1)))


static func _face_code(axis: int, sign: float) -> int:
	if axis == 1:
		return 0 if sign > 0.0 else 1
	if axis == 0:
		return 2 if sign > 0.0 else 3
	return 4 if sign > 0.0 else 5


static func _ray_aabb(origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3) -> bool:
	var tmin := -1.0e20
	var tmax := 1.0e20
	var enter_axis := 1
	var enter_sign := 1.0
	for axis in 3:
		var o: float = origin[axis]
		var d: float = dir[axis]
		var mn: float = bmin[axis]
		var mx: float = bmax[axis]
		if absf(d) < 0.0000001:
			if o < mn or o > mx:
				return false
			continue
		var inv: float = 1.0 / d
		var t1: float = (mn - o) * inv
		var t2: float = (mx - o) * inv
		var hit_min := true
		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap
			hit_min = false
		if t1 > tmin:
			tmin = t1
			enter_axis = axis
			enter_sign = -1.0 if hit_min else 1.0
		if t2 < tmax:
			tmax = t2
		if tmin > tmax:
			return false
	if tmax < 0.0:
		return false
	_aabb_t = tmin if tmin >= 0.0 else 0.0
	_aabb_face = _face_code(enter_axis, enter_sign)
	return true


static func _ray_box_distance(origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3, max_dist: float) -> float:
	var center := (bmin + bmax) * 0.5
	var t: float = clampf(dir.dot(center - origin), 0.0, max_dist)
	var p: Vector3 = origin + dir * t
	var c := Vector3(
		clampf(p.x, bmin.x, bmax.x),
		clampf(p.y, bmin.y, bmax.y),
		clampf(p.z, bmin.z, bmax.z)
	)
	return p.distance_to(c)


static func _nearest_face(origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3, max_dist: float) -> int:
	var center := (bmin + bmax) * 0.5
	var t: float = clampf(dir.dot(center - origin), 0.0, max_dist)
	var p: Vector3 = origin + dir * t
	var c := Vector3(
		clampf(p.x, bmin.x, bmax.x),
		clampf(p.y, bmin.y, bmax.y),
		clampf(p.z, bmin.z, bmax.z)
	)
	var delta := p - c
	var ax := absf(delta.x)
	var ay := absf(delta.y)
	var az := absf(delta.z)
	if ay >= ax and ay >= az:
		return 0 if delta.y >= 0.0 else 1
	if ax >= az:
		return 2 if delta.x >= 0.0 else 3
	return 4 if delta.z >= 0.0 else 5


static func pick_hover_column(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float = 8.0
) -> Vector3:
	return _pick_column_from_mouse(player, range_v, world, chunk_manager, false)


static func note_event_mouse(at: Vector2, view: Vector2) -> void:
	if at.x < 0.0 or at.y < 0.0 or at.x > view.x or at.y > view.y:
		return
	_event_pos = at
	_event_ok = true


static func pointer_in(vp: Viewport) -> Vector2:
	if vp == null:
		return Vector2.ZERO
	var mouse := vp.get_mouse_position()
	if not _event_ok:
		return mouse
	if mouse.distance_squared_to(_event_pos) <= 4.0:
		return mouse
	var size := vp.get_visible_rect().size
	if _event_pos.x >= 0.0 and _event_pos.y >= 0.0 and _event_pos.x <= size.x and _event_pos.y <= size.y:
		return _event_pos
	return mouse


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


static func cursor_cell_under_mouse(player: Node3D, range_v: float) -> Vector3:
	if player == null or not player.is_inside_tree():
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	var vp: Viewport = player.get_viewport()
	if cam == null or vp == null:
		return Vector3.ZERO
	var mouse := pointer_in(vp)
	var rect := vp.get_visible_rect()
	if rect.size.x > 4.0 and rect.size.y > 4.0:
		if mouse.x < rect.position.x - 2.0 or mouse.y < rect.position.y - 2.0 \
				or mouse.x > rect.end.x + 2.0 or mouse.y > rect.end.y + 2.0:
			return Vector3.ZERO
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.length_squared() < 0.0000001 or absf(dir.y) < 0.00001:
		return Vector3.ZERO
	dir = dir.normalized()
	var world := _player_world(player)
	var chunk_manager: ChunkManager = player.get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	var ws = _WorldSettings.get_active()
	var plane_y: float = player.global_position.y
	var seed_x := 0
	var seed_z := 0
	var seeded := false
	for _refine in 5:
		var t_plane: float = (plane_y - origin.y) / dir.y
		if t_plane < 0.0:
			break
		var hit: Vector3 = origin + dir * t_plane
		seed_x = floori(ws.world_to_column(hit.x))
		seed_z = floori(ws.world_to_column(hit.z))
		seeded = true
		if world == null:
			break
		var next_y: float = _walkable_top(world, chunk_manager, float(seed_x) + 0.5, float(seed_z) + 0.5)
		if absf(next_y - plane_y) < 0.02:
			break
		plane_y = next_y
	if not seeded or not _column_in_range(player, seed_x, seed_z, range_v):
		return Vector3.ZERO
	var py := 0.0
	if "voxel_position" in player:
		py = float(player.voxel_position.y)
	return Vector3(float(seed_x) + 0.5, py, float(seed_z) + 0.5)


static func cursor_aim(player: Node3D, range_v: float = reach()) -> Vector3:
	if player == null:
		return Vector3.FORWARD
	var col := _cursor_column(player, maxf(range_v, reach()))
	if col != Vector3.ZERO and "voxel_position" in player:
		var origin_x := float(player.voxel_position.x)
		var origin_z := float(player.voxel_position.z)
		var offset := Vector3(col.x - origin_x, 0.0, col.z - origin_z)
		if offset.length_squared() > 0.04:
			return offset.normalized()
	return attack_forward(player)


static func _cursor_column(player: Node3D, range_v: float) -> Vector3:
	if player.is_inside_tree():
		var hl = player.get_node_or_null("TargetHighlight")
		if hl != null and hl.has_method("get_action_column"):
			var shared: Vector3 = hl.get_action_column()
			if shared != Vector3.ZERO:
				var sx := floori(shared.x)
				var sz := floori(shared.z)
				if _column_in_range(player, sx, sz, range_v):
					return Vector3(float(sx) + 0.5, shared.y, float(sz) + 0.5)
	var world := _player_world(player)
	var chunk_manager: ChunkManager = null
	if player.is_inside_tree():
		chunk_manager = player.get_tree().get_first_node_in_group("chunk_manager") as ChunkManager
	var mouse_col := _pick_column_from_mouse(player, range_v, world, chunk_manager, true)
	if mouse_col != Vector3.ZERO:
		return mouse_col
	return Vector3.ZERO


static func attack_toward_column(player: Node3D, range_v: float = 2.0) -> Vector3:
	return cursor_aim(player, range_v)


static func column_toward_cursor(player: Node3D, hit_range: float) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var col := _cursor_column(player, maxf(hit_range, reach()))
	if col == Vector3.ZERO or not ("voxel_position" in player):
		var world := _player_world(player)
		var chunk_manager: ChunkManager = player.get_tree().get_first_node_in_group("chunk_manager") if player.is_inside_tree() else null
		return _target_column_forward(player, hit_range, world, chunk_manager)
	var origin := Vector2(float(player.voxel_position.x), float(player.voxel_position.z))
	var center := Vector2(col.x, col.z)
	var delta := center - origin
	var dist := delta.length()
	if dist <= hit_range + 0.01 or dist < 0.001:
		return col
	var pulled := origin + delta / dist * hit_range
	return Vector3(float(floori(pulled.x)) + 0.5, col.y, float(floori(pulled.y)) + 0.5)


static func target_column(player: Node3D, range_v: float = 2.0) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var world := _player_world(player)
	var chunk_manager: ChunkManager = player.get_tree().get_first_node_in_group("chunk_manager") if player.is_inside_tree() else null
	if player.is_inside_tree():
		var hl = player.get_node_or_null("TargetHighlight")
		if hl != null and hl.has_method("get_action_column"):
			var shared: Vector3 = hl.get_action_column()
			if shared != Vector3.ZERO:
				var sx := floori(shared.x)
				var sz := floori(shared.z)
				if _column_in_range(player, sx, sz, range_v):
					return Vector3(float(sx) + 0.5, shared.y, float(sz) + 0.5)
				return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	if cam != null and player.is_inside_tree():
		return _pick_column_from_mouse(player, range_v, world, chunk_manager, true)
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


static func _weapon_mode_from_player(player: Node3D, force_build: bool = false) -> StringName:
	if player == null:
		return &"none"
	var inv = player.get("inventory") if "inventory" in player else null
	var has_build_mat: bool = false
	if inv != null and inv.has_method("count_item"):
		has_build_mat = int(inv.count_item("stone")) > 0 or int(inv.count_item("wood")) > 0
	var mode: StringName = &"none"
	var held_id := ""
	var weapon := player.get_node_or_null("WeaponController")
	if weapon and weapon.has_method("get_active_item"):
		var slot = weapon.get_active_item()
		if slot != null:
			held_id = str(slot.id)
			var def := _ItemTypes.get_def(held_id)
			if not def.is_empty():
				var category := int(def.get("category", -1))
				var kind := int(def.get("weapon_kind", _ItemTypes.WeaponKind.MELEE))
				if _ItemTypes.breaks_blocks(held_id):
					mode = &"dig"
				elif category == _ItemTypes.Category.WEAPON:
					mode = &"attack" if kind == _ItemTypes.WeaponKind.MELEE else &"ranged"
				elif _ItemTypes.is_placeable_block(held_id) and int(slot.get("count", 0)) > 0:
					mode = &"build"
	if _ItemTypes.has_right_click_ability(held_id):
		return mode
	if force_build and has_build_mat:
		return &"build"
	return mode


static func _cell_top_center(cell: Vector3i) -> Vector3:
	var ws = _WorldSettings.get_active()
	return Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		float(cell.y + 1) * ws.voxel_scale,
		ws.column_to_world(float(cell.z) + 0.5)
	)


static func resolve_action(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float = 2.0,
	simulate_interact: bool = false,
	force_mode: StringName = &"",
	override_column: Vector3 = Vector3(INF, INF, INF)
) -> Dictionary:
	var col: Vector3
	if override_column.x < 1.0e20:
		col = override_column
	else:
		col = target_column(player, range_v)
	if col == Vector3.ZERO:
		return {
			"column": Vector3.ZERO,
			"cell": Vector2i.ZERO,
			"surface_y": 0.0,
			"world_pos": Vector3.ZERO,
			"mode": &"none",
			"valid": false,
			"blocked": false,
			"in_range": false,
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
	var want_build: bool = simulate_interact \
		or Input.is_action_pressed("interact") \
		or Input.is_action_pressed("build_place")
	var mode: StringName = _weapon_mode_from_player(player, want_build)
	if force_mode != &"":
		mode = force_mode
	var in_range: bool = _column_in_range(player, wx, wz, range_v)
	var valid := mode != &"none" and in_range \
		and _is_action_valid(world, chunk_manager, wx, wz, mode, player, range_v)
	var blocked := mode != &"none" and not valid
	var highlight_y: float = walk_top
	if mode in [&"attack", &"ranged"] and not _is_solid_column(world, chunk_manager, wx, wz):
		highlight_y = walk_top + layer_h * 0.35
	var world_pos := Vector3(
		ws.column_to_world(col.x),
		highlight_y,
		ws.column_to_world(col.z)
	)
	var place_pos := world_pos + Vector3(0.0, layer_h, 0.0)
	var place_cell := last_pick_cell + last_pick_normal
	if last_pick_exact and (Vector2i(last_pick_cell.x, last_pick_cell.z) == Vector2i(wx, wz) \
			or Vector2i(place_cell.x, place_cell.z) == Vector2i(wx, wz)):
		world_pos = _cell_top_center(last_pick_cell)
		place_pos = _cell_top_center(place_cell)
	return {
		"column": col,
		"cell": Vector2i(wx, wz),
		"surface_y": surf,
		"walk_top": walk_top,
		"world_pos": world_pos,
		"place_pos": place_pos,
		"mode": mode,
		"valid": valid,
		"blocked": blocked,
		"in_range": in_range,
		"range": range_v,
	}