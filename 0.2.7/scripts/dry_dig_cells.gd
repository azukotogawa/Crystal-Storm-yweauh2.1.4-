extends RefCounted
## Cells where TerrainEditor.try_dig lowers the column.
## A river tile refuses the dig. A dry cell beside water is replaced with a
## water tile and the height does not change. Towns, ruins, and builds are skipped.
## Search starts at `near`, then the heart-corner river-free disk.


const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _NoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")

const NOT_FOUND := -1000001


static func is_found(cell: Vector2i) -> bool:
	return cell.x != NOT_FOUND


static func find_cell(world, near: Vector2i, radius: int = 48) -> Vector2i:
	var found := _search_cell(world, near, radius, false)
	if is_found(found):
		return found
	var disk_r := int(_NoiseWorld.SPAWN_RIVER_CLEARANCE) - 4
	return _search_cell(world, disk_anchor(world, 1), disk_r, true)


static func find_run(world, count: int, near: Vector2i, radius: int = 64) -> Array[Vector2i]:
	if count < 1:
		var empty: Array[Vector2i] = []
		return empty
	var found := _search_run(world, near, count, radius, false)
	if found.size() == count:
		return found
	var disk_r := int(_NoiseWorld.SPAWN_RIVER_CLEARANCE) - 4
	return _search_run(world, disk_anchor(world, count), count, disk_r, true)


## A column inside the heart disk, inset so a short run and its 1-cell halo
## stay inside the clearance and the playable rect.
static func disk_anchor(world, count: int) -> Vector2i:
	var seed_value := 12349
	if world != null and "world_seed" in world:
		seed_value = int(world.world_seed)
	var corner: Vector2i = _WorldBorder.origin_corner_for_seed(seed_value)
	var sx := -1 if corner.x >= 0 else 1
	var sz := -1 if corner.y >= 0 else 1
	var inset := maxi(24, count + 4)
	return Vector2i(corner.x + sx * inset, corner.y + sz * inset)


static func _search_cell(world, anchor: Vector2i, radius: int, in_disk: bool) -> Vector2i:
	if world == null:
		return Vector2i(NOT_FOUND, NOT_FOUND)
	if _cell_ok(world, anchor.x, anchor.y, in_disk):
		return anchor
	for r in range(1, radius + 1):
		for dz in range(-r, r + 1):
			var z := anchor.y + dz
			if _cell_ok(world, anchor.x - r, z, in_disk):
				return Vector2i(anchor.x - r, z)
			if _cell_ok(world, anchor.x + r, z, in_disk):
				return Vector2i(anchor.x + r, z)
		for dx in range(-(r - 1), r):
			var x := anchor.x + dx
			if _cell_ok(world, x, anchor.y - r, in_disk):
				return Vector2i(x, anchor.y - r)
			if _cell_ok(world, x, anchor.y + r, in_disk):
				return Vector2i(x, anchor.y + r)
	return Vector2i(NOT_FOUND, NOT_FOUND)


static func _search_run(world, anchor: Vector2i, count: int, radius: int, in_disk: bool) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if world == null:
		return none
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	for r in range(0, radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and maxi(absi(dx), absi(dz)) != r:
					continue
				var x0 := anchor.x + dx
				var z0 := anchor.y + dz
				for axis in axes:
					var run: Array[Vector2i] = []
					var ok := true
					for i in count:
						var x := x0 + axis.x * i
						var z := z0 + axis.y * i
						if not _cell_ok(world, x, z, in_disk):
							ok = false
							break
						run.append(Vector2i(x, z))
					if ok:
						return run
	return none


static func _cell_ok(world, x: int, z: int, in_disk: bool) -> bool:
	if in_disk and not _inside_disk(world, x, z):
		return false
	if not _TerrainEdits.can_edit(x, z):
		return false
	if _is_structure(x, z):
		return false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var nz := z + dz
			if dx == 0 and dz == 0:
				if _center_blocks(world, nx, nz):
					return false
			elif _neighbor_blocks(world, nx, nz):
				return false
	var min_h: float = -float(_WorldSettings.get_active().layer_height()) * 4.0
	if world.get_surface_height(float(x), float(z)) <= min_h:
		return false
	return true


static func _inside_disk(world, x: int, z: int) -> bool:
	var center: Vector2 = world.spawn_river_center()
	var dx := float(x) - center.x
	var dz := float(z) - center.y
	var limit := _NoiseWorld.SPAWN_RIVER_CLEARANCE - 2.0
	return dx * dx + dz * dz < limit * limit


static func _is_structure(x: int, z: int) -> bool:
	if _TerrainEdits.get_build_tile(x, z) >= 0:
		return true
	var feat: Dictionary = _FeatureRegistry.get_feature(x, z)
	if feat.is_empty():
		return false
	if str(feat.get("build_id", "")).strip_edges() != "":
		return true
	var kind := int(feat.get("kind", _WorldFeatureTypes.FeatureKind.NONE))
	return kind == _WorldFeatureTypes.FeatureKind.TOWN \
		or kind == _WorldFeatureTypes.FeatureKind.TOWN_BUILDING \
		or kind == _WorldFeatureTypes.FeatureKind.RUIN


static func _center_blocks(world, x: int, z: int) -> bool:
	var tile := int(world.get_tile_type(float(x), float(z)))
	if _is_source_tile(tile):
		return true
	return _has_channel(x, z)


static func _neighbor_blocks(world, x: int, z: int) -> bool:
	var tile := int(world.get_tile_type(float(x), float(z)))
	if tile == _VoxelTypes.RIVER or tile == _VoxelTypes.WATER \
			or tile == _VoxelTypes.OCEAN or tile == _VoxelTypes.OCEAN2:
		return true
	return _has_channel(x, z)


static func _is_source_tile(tile: int) -> bool:
	return tile == _VoxelTypes.RIVER or tile == _VoxelTypes.WATER \
		or tile == _VoxelTypes.OCEAN or tile == _VoxelTypes.OCEAN2 \
		or tile == _VoxelTypes.OCEAN3


static func _has_channel(x: int, z: int) -> bool:
	if _ChannelRegistry.is_channel(x, z):
		return true
	return _ChannelRegistry.has_fluid(x, z, _ChannelRegistry.FLUID_WATER)
