class_name ActionTargeting
extends RefCounted

const _ItemTypes = preload("res://helpers/item_types.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


static func _camera_yaw_degrees(player: Node3D) -> float:
	if player == null:
		return 45.0
	if bool(player.get("is_input_locked")):
		if "locked_yaw_degrees" in player:
			return float(player.get("locked_yaw_degrees"))
		return 45.0 + float(int(player.get("locked_rotation"))) * 90.0
	var cam = player.get("camera")
	if cam != null and "yaw_degrees" in cam:
		return float(cam.yaw_degrees)
	if cam != null and "orbit_yaw_deg" in cam:
		return float(cam.orbit_yaw_deg)
	if cam != null and "orbit_rotation" in cam:
		return 45.0 + float(cam.orbit_rotation) * 90.0
	return 45.0


## Match player movement: screen-up (W / ui_up) maps to world forward via camera yaw.
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
	var dist := 0.0
	var last_in_range := Vector3.ZERO
	while dist <= range_v + 0.01:
		var probe: Vector3 = player.voxel_position + forward * dist
		var wx := floori(probe.x)
		var wz := floori(probe.z)
		if _column_in_range(player, wx, wz, range_v):
			last_in_range = Vector3(float(wx) + 0.5, player.voxel_position.y, float(wz) + 0.5)
			if _is_solid_column(world, chunk_manager, wx, wz):
				return last_in_range
		dist += 0.35
	# Prefer a facing column even while streaming/solid checks are cold so dig never no-ops.
	if last_in_range != Vector3.ZERO:
		return last_in_range
	var fallback: Vector3 = player.voxel_position + forward * minf(range_v, 1.25)
	return Vector3(float(floori(fallback.x)) + 0.5, player.voxel_position.y, float(floori(fallback.z)) + 0.5)


## Stable ortho pick: iterative plane intersect refined by walkable surface height.
## When require_in_range is false, follows the mouse even outside dig/build range (cursor fidelity).
static func _pick_column_from_mouse(
	player: Node3D,
	range_v: float,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	require_in_range: bool = true
) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	var vp: Viewport = player.get_viewport()
	if cam == null or vp == null:
		return Vector3.ZERO
	var ws = _WorldSettings.get_active()
	var mouse := vp.get_mouse_position()
	var rect := vp.get_visible_rect()
	# Off-screen mouse (probes / warp away): fall back to facing. Skip when viewport has no size (headless).
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

	# Iterative plane pick (stable, no step-ray jitter between neighboring columns).
	var plane_y: float = player.global_position.y
	var best := Vector3.ZERO
	var max_abs_t: float = 400.0
	for _refine in 5:
		var t_plane: float = (plane_y - origin.y) / dir.y
		if t_plane < 0.0 or t_plane > max_abs_t:
			break
		var hit: Vector3 = origin + dir * t_plane
		var wx: int = floori(ws.world_to_column(hit.x))
		var wz: int = floori(ws.world_to_column(hit.z))
		var col_x: float = float(wx) + 0.5
		var col_z: float = float(wz) + 0.5
		var in_range: bool = _column_in_range(player, wx, wz, range_v)
		if require_in_range and not in_range:
			# Still refine height from nearest guess so cursor settles smoothly when re-entering range.
			if world != null:
				plane_y = _walkable_top(world, chunk_manager, col_x, col_z)
			continue
		# Always lock the column under the mouse when in range — solid checks must not
		# discard the pick (missed digs/placements). try_dig/try_build validate later.
		best = Vector3(col_x, player.voxel_position.y, col_z)
		if world != null:
			var next_y: float = _walkable_top(world, chunk_manager, col_x, col_z)
			if absf(next_y - plane_y) < 0.02:
				break
			plane_y = next_y
		else:
			break
	if best != Vector3.ZERO:
		return best

	# Fallback: denser ray march within range (entities / odd slabs).
	if world != null:
		var step: float = ws.voxel_scale * 0.15
		var max_dist: float = minf((range_v + 3.0) * ws.voxel_scale * 3.5, 120.0)
		var t: float = 0.0
		var best_t: float = INF
		while t <= max_dist:
			var p: Vector3 = origin + dir * t
			var wxm: int = floori(ws.world_to_column(p.x))
			var wzm: int = floori(ws.world_to_column(p.z))
			var in_r: bool = _column_in_range(player, wxm, wzm, range_v)
			if not require_in_range or in_r:
				var hits_slab := _ray_y_hits_surface_slab(world, chunk_manager, wxm, wzm, p.y)
				var hits_entity := _entity_column_near(player, wxm, wzm, range_v)
				if (hits_slab and _is_solid_column(world, chunk_manager, wxm, wzm)) or hits_entity:
					if t < best_t:
						best_t = t
						best = Vector3(float(wxm) + 0.5, player.voxel_position.y, float(wzm) + 0.5)
			t += step
	return best


## Mouse hover column for cursor UI (ignores dig range so the box follows the pointer).
static func pick_hover_column(
	player: Node3D,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float = 8.0
) -> Vector3:
	return _pick_column_from_mouse(player, range_v, world, chunk_manager, false)


## Predicted next column past hover along the camera ray (for dig/build trail feel).
static func predict_next_column(
	player: Node3D,
	from_col: Vector3,
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	range_v: float
) -> Vector3:
	if player == null or from_col == Vector3.ZERO:
		return Vector3.ZERO
	var cam: Camera3D = player.get("camera") as Camera3D
	var vp: Viewport = player.get_viewport() if player.is_inside_tree() else null
	if cam == null or vp == null:
		return Vector3.ZERO
	var ws = _WorldSettings.get_active()
	var mouse := vp.get_mouse_position()
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.length_squared() < 0.00001:
		return Vector3.ZERO
	dir = dir.normalized()
	# Horizontal ray direction in column space.
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.00001:
		flat = attack_forward(player)
	flat = flat.normalized()
	var step_x: int = 0
	var step_z: int = 0
	if absf(flat.x) >= absf(flat.z):
		step_x = 1 if flat.x >= 0.0 else -1
	else:
		step_z = 1 if flat.z >= 0.0 else -1
	var wx: int = floori(from_col.x) + step_x
	var wz: int = floori(from_col.z) + step_z
	if not _column_in_range(player, wx, wz, range_v + 1.0):
		return Vector3.ZERO
	if world != null and not _is_solid_column(world, chunk_manager, wx, wz) \
			and not _entity_column_near(player, wx, wz, range_v + 1.0):
		return Vector3.ZERO
	return Vector3(float(wx) + 0.5, from_col.y, float(wz) + 0.5)


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
	# Prefer the same column the highlight is showing (zero missed digs vs cursor).
	if player.is_inside_tree():
		var hl = player.get_node_or_null("TargetHighlight")
		if hl != null and hl.has_method("get_action_column"):
			var shared: Vector3 = hl.get_action_column()
			if shared != Vector3.ZERO:
				var sx := floori(shared.x)
				var sz := floori(shared.z)
				# Return highlighted cell only when in range; out-of-range is ZERO so callers fail clear.
				if _column_in_range(player, sx, sz, range_v):
					return Vector3(float(sx) + 0.5, shared.y, float(sz) + 0.5)
				return Vector3.ZERO
	# Actions only accept in-range picks (require_in_range=true).
	var mouse_col := _pick_column_from_mouse(player, range_v, world, chunk_manager, true)
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


## Resolve hotbar/tool mode. When force_build (simulate_interact / RMB held), prefer build if materials.
static func _weapon_mode_from_player(player: Node3D, force_build: bool = false) -> StringName:
	if player == null:
		return &"none"
	var inv = player.get("inventory") if "inventory" in player else null
	var has_build_mat: bool = false
	if inv != null and inv.has_method("count_item"):
		has_build_mat = int(inv.count_item("stone")) > 0 or int(inv.count_item("wood")) > 0
	var mode: StringName = &"none"
	var weapon := player.get_node_or_null("WeaponController")
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
				elif str(slot.id) == "wood" and int(slot.get("count", 0)) > 0:
					mode = &"build"
	if force_build and has_build_mat:
		return &"build"
	if mode == &"none" and force_build and has_build_mat:
		return &"build"
	return mode


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
	# walk_top = feet / top face of the column (dig highlight anchors here).
	var walk_top: float = surf + ws.layer_height()
	if world:
		walk_top = _walkable_top(world, chunk_manager, col.x, col.z)
	var layer_h: float = ws.layer_height()
	var built_layers: int = maxi(0, int(round(_TerrainEdits.get_height_delta(wx, wz) / layer_h)))
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
	# Keep mode when blocked so the player still sees a red/orange preview (not a blank cursor).
	# Dig: box sits on walk_top (column top face) — not buried mid-slab.
	var highlight_y: float = walk_top
	if mode == &"dig":
		highlight_y = walk_top
	elif mode == &"build":
		# Placement top face of the next stacked layer.
		highlight_y = walk_top + layer_h * float(built_layers + 1)
	elif mode in [&"attack", &"ranged"] and not _is_solid_column(world, chunk_manager, wx, wz):
		highlight_y = walk_top + layer_h * 0.35
	elif mode in [&"attack", &"ranged"]:
		highlight_y = walk_top
	var world_pos := Vector3(
		ws.column_to_world(col.x),
		highlight_y,
		ws.column_to_world(col.z)
	)
	return {
		"column": col,
		"cell": Vector2i(wx, wz),
		"surface_y": surf,
		"walk_top": walk_top,
		"world_pos": world_pos,
		"mode": mode,
		"valid": valid,
		"blocked": blocked,
		"in_range": in_range,
		"range": range_v,
	}