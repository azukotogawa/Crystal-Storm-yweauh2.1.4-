class_name LivingForce
extends RefCounted
## Living-force reactions and the heightfield dig brush.
## Terrain is one height per column, so the brush is a cylinder in plan:
## a disk of columns whose surface lies inside the vertical radius.
## Radius 1 is the old single-column dig. Cole can retune every static var.
## See docs/LIVING_FORCE_ALIGNMENT.md.

const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldState = preload("res://world/world_state.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

const BRUSH_RADIUS_DEFAULT := 1
const BRUSH_RADIUS_MAX := 3
## Added to the equipped tool's dig_radius. [ / ] adjust this while a dig tool is held.
static var session_radius_bias: int = 0

## Unsupported dug rims slump one layer. Natural noise cliffs are left alone
## (the test is height_delta, not world noise). No cascade past the dug cells.
static var settle_enabled: bool = true
static var settle_trigger_layers: int = 2
static var settle_max_cells: int = 4

## A dug column below an adjacent natural waterline is handed to VoxelFluidService.
static var water_inflow_enabled: bool = true

## Existing crystal near a dig or a new wall gains a little depth. Never seeds a new cell.
static var crystal_react_enabled: bool = true
static var crystal_react_radius: int = 2
static var crystal_dig_pressure: float = 0.06
static var crystal_build_pressure: float = 0.10
static var crystal_pressure_cells_per_stroke: int = 4

## Crystal sitting on a player build accumulates push, then consumes one build.
## One break per tick. Progress is stored on the feature (`crystal_push`) so saves keep it.
static var pushback_enabled: bool = true
static var pushback_depth: float = 0.75
static var pushback_step: float = 0.34
static var pushback_break: float = 1.0
static var pushback_max_per_tick: int = 1
static var pushback_checks_per_tick: int = 8
static var pushback_interval: float = 0.5
static var push_watch: Dictionary = {}


static func reset_session() -> void:
	session_radius_bias = 0
	push_watch.clear()


static func radius_for_item(item_id: String) -> int:
	var base := BRUSH_RADIUS_DEFAULT
	var raw: Dictionary = _ItemTypes.ITEMS.get(item_id, {})
	if raw.has("dig_radius"):
		base = int(raw["dig_radius"])
	else:
		var looked := _ItemTypes.get_def(item_id)
		base = int(looked.get("dig_radius", BRUSH_RADIUS_DEFAULT))
	return clampi(base + session_radius_bias, 1, BRUSH_RADIUS_MAX)


static func adjust_session_bias(delta: int, item_id: String) -> int:
	var base := BRUSH_RADIUS_DEFAULT
	var raw: Dictionary = _ItemTypes.ITEMS.get(item_id, {})
	if raw.has("dig_radius"):
		base = int(raw["dig_radius"])
	session_radius_bias += delta
	var result := clampi(base + session_radius_bias, 1, BRUSH_RADIUS_MAX)
	session_radius_bias = result - base
	return result


## Columns inside the brush. `world` may be null (every column then shares layer 0).
static func footprint(cx: int, cz: int, radius: int, world = null) -> Array:
	var r := clampi(radius, 1, BRUSH_RADIUS_MAX)
	var reach := r - 1
	var center_layers := _column_layers(world, cx, cz)
	var out: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx * dx + dz * dz > reach * reach:
				continue
			var wx := cx + dx
			var wz := cz + dz
			if absi(_column_layers(world, wx, wz) - center_layers) > r:
				continue
			out.append(Vector2i(wx, wz))
	return out


static func chunk_coord(wx: int, wz: int) -> Vector2i:
	var size := 16
	return Vector2i(floori(float(wx) / float(size)), floori(float(wz) / float(size)))


static func _column_layers(world, wx: int, wz: int) -> int:
	var layer: float = _WorldSettings.get_active().layer_height()
	if world != null and world.has_method("get_surface_height"):
		return int(round(world.get_surface_height(float(wx), float(wz)) / maxf(layer, 0.001)))
	return _delta_layers(wx, wz, layer)


static func _delta_layers(wx: int, wz: int, layer: float) -> int:
	return int(round(_TerrainEdits.get_height_delta(wx, wz) / maxf(layer, 0.001)))


static func _cmp_cell(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		return a.y < b.y
	return a.x < b.x


static func is_water_source_tile(tile: int) -> bool:
	return tile in [
		_VoxelTypes.RIVER, _VoxelTypes.WATER,
		_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3,
	]


## Towns, ruins, player structures, build tiles, and natural water are not brush targets.
## Radius-1 try_dig keeps its older single-cell rules; the brush uses this set.
static func is_protected_column(wx: int, wz: int, world = null) -> bool:
	if world != null and world.has_method("get_tile_type"):
		if is_water_source_tile(int(world.get_tile_type(float(wx), float(wz)))):
			return true
	if _TerrainEdits.get_build_tile(wx, wz) >= 0:
		return true
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.is_empty():
		return false
	var kind := int(feat.get("kind", 0))
	var player_built := bool(feat.get("player_built", false)) or bool(feat.get("player_placed", false))
	if not player_built and kind in [
		_WorldFeatureTypes.FeatureKind.TOWN,
		_WorldFeatureTypes.FeatureKind.TOWN_BUILDING,
		_WorldFeatureTypes.FeatureKind.RUIN,
		_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
	]:
		return true
	var build_id := str(feat.get("build_id", "")).strip_edges()
	if build_id in ["wood_wall", "stone_wall", "gate", "bridge", "cardinal_ramp", "corner_ramp"]:
		return true
	if player_built and build_id != "":
		return true
	return false


## Drop immediate rims that stand `settle_trigger_layers` above a dug cell. One layer, no cascade.
static func apply_settle(dug: Array, world = null) -> Array:
	if not settle_enabled or dug.is_empty():
		return []
	var layer: float = _WorldSettings.get_active().layer_height()
	var dug_set := {}
	for cell_v in dug:
		dug_set[cell_v] = true
	var ordered: Array = dug.duplicate()
	ordered.sort_custom(Callable(LivingForce, "_cmp_cell"))
	var planned: Array = []
	var planned_set := {}
	for cell_v in ordered:
		if planned.size() >= settle_max_cells:
			break
		var cell: Vector2i = cell_v
		var cl := _delta_layers(cell.x, cell.y, layer)
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			if planned.size() >= settle_max_cells:
				break
			var n: Vector2i = cell + dir
			if dug_set.has(n) or planned_set.has(n):
				continue
			if not _TerrainEdits.can_edit(n.x, n.y):
				continue
			if is_protected_column(n.x, n.y, world):
				continue
			var nl := _delta_layers(n.x, n.y, layer)
			if nl - cl < settle_trigger_layers:
				continue
			planned.append(n)
			planned_set[n] = true
	var done: Array = []
	for n_v in planned:
		var n: Vector2i = n_v
		if _TerrainEdits.dig(n.x, n.y, 1):
			done.append(n)
	return done


## Crystal cells that already have depth, sorted, capped. Does not invent cells.
static func pressure_targets(
	origin: Vector2i,
	depth_at: Callable,
	min_depth: float,
	radius: int,
	cap: int
) -> Array:
	var found: Array = []
	var r := maxi(radius, 0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var pos := Vector2i(origin.x + dx, origin.y + dz)
			if float(depth_at.call(pos.x, pos.y)) + 0.00001 < min_depth:
				continue
			found.append(pos)
	found.sort_custom(Callable(LivingForce, "_cmp_cell"))
	if cap > 0 and found.size() > cap:
		found.resize(cap)
	return found


static func arm_player_builds(origin: Vector2i, radius: int) -> void:
	var r := maxi(radius, 0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var pos := Vector2i(origin.x + dx, origin.y + dz)
			var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
			if not bool(feat.get("player_built", false)):
				continue
			push_watch[pos] = true
			if bool(feat.get("crystal_push_armed", false)):
				continue
			var copy := feat.duplicate(true)
			copy["crystal_push_armed"] = true
			_FeatureRegistry.register_feature(pos.x, pos.y, int(copy.get("kind", 0)), copy)


static func rearm_push_watch() -> void:
	push_watch.clear()
	var ws = _WorldState.get_active()
	if ws == null:
		return
	for key_v in ws.feature_cells.keys():
		var feat: Dictionary = ws.feature_cells[key_v]
		if bool(feat.get("crystal_push_armed", false)) or float(feat.get("crystal_push", 0.0)) > 0.0:
			push_watch[key_v] = true


## Returns cells whose player build was consumed this tick (at most pushback_max_per_tick).
static func tick_pushback(depth_at: Callable) -> Array:
	if not pushback_enabled or push_watch.is_empty() or not depth_at.is_valid():
		return []
	var keys: Array = push_watch.keys()
	keys.sort_custom(Callable(LivingForce, "_cmp_cell"))
	var broke: Array = []
	var checks := 0
	for key_v in keys:
		if checks >= pushback_checks_per_tick or broke.size() >= pushback_max_per_tick:
			break
		checks += 1
		var pos: Vector2i = key_v
		var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
		if not bool(feat.get("player_built", false)):
			push_watch.erase(pos)
			continue
		if _max_depth_near(pos, depth_at) + 0.00001 < pushback_depth:
			continue
		var push := float(feat.get("crystal_push", 0.0)) + pushback_step
		if push + 0.0001 < pushback_break:
			var copy := feat.duplicate(true)
			copy["crystal_push"] = push
			copy["crystal_push_armed"] = true
			_FeatureRegistry.register_feature(pos.x, pos.y, int(copy.get("kind", 0)), copy)
			continue
		if _consume_player_build(pos):
			broke.append(pos)
	return broke


static func _max_depth_near(pos: Vector2i, depth_at: Callable) -> float:
	var best := float(depth_at.call(pos.x, pos.y))
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = pos + dir
		best = maxf(best, float(depth_at.call(n.x, n.y)))
	return best


static func _consume_player_build(pos: Vector2i) -> bool:
	var feat: Dictionary = _FeatureRegistry.get_feature(pos.x, pos.y)
	if not bool(feat.get("player_built", false)):
		push_watch.erase(pos)
		return false
	var raises := bool(feat.get("raises_terrain", false))
	if raises and _TerrainEdits.get_height_delta(pos.x, pos.y) > 0.01:
		if not _TerrainEdits.unstack_build(pos.x, pos.y):
			return false
		var still := _TerrainEdits.get_height_delta(pos.x, pos.y) > 0.01 \
			and _TerrainEdits.get_build_tile(pos.x, pos.y) >= 0
		if still:
			var copy := _FeatureRegistry.get_feature(pos.x, pos.y).duplicate(true)
			copy["crystal_push"] = 0.0
			copy["crystal_push_armed"] = true
			copy["player_built"] = true
			_FeatureRegistry.register_feature(pos.x, pos.y, int(copy.get("kind", 0)), copy)
			return true
	_TerrainEdits.clear_build_tile(pos.x, pos.y)
	_FeatureRegistry.clear_feature(pos.x, pos.y)
	_FeatureRegistry.clear_tile_override(pos.x, pos.y)
	push_watch.erase(pos)
	return true
