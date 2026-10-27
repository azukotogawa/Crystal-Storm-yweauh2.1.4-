class_name WaterLocomotion
extends RefCounted

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _VoxelFluidEngine = preload("res://fluids/voxel_fluid_engine.gd")
const _WorldState = preload("res://world/world_state.gd")

const SWIM_SPEED_MULT := 0.42
const WADE_SPEED_MULT := 0.68
const SWIM_ACCEL_MULT := 0.5
const SWIM_FRICTION_MULT := 1.45
const BUOYANCY_RATE := 6.0
const SWIM_DEPTH_LAYERS := 0.5


static func dry(ground_y: float) -> Dictionary:
	return {
		"in_water": false,
		"deep": false,
		"submerged": false,
		"wading": false,
		"surface_y": 0.0,
		"float_y": ground_y,
		"ground_y": ground_y,
		"speed_mult": 1.0,
	}


static func column_has_water(world, col_x: int, col_z: int) -> bool:
	if _channel_level(col_x, col_z) >= 0.05:
		return true
	return _is_inland_water_tile(world, col_x, col_z)


static func sample(
	world,
	col_x: int,
	col_z: int,
	feet_y: float,
	ground_y: float,
	body_height: float = -1.0
) -> Dictionary:
	var layer: float = _WorldSettings.get_active().layer_height()
	var cell := _cell_water(world, col_x, col_z, ground_y, layer)
	if cell.is_empty():
		return dry(ground_y)
	var surface: float = cell.surface
	var deep := surface - float(cell.bed) >= layer * SWIM_DEPTH_LAYERS - 0.001
	var submerged := deep and feet_y <= surface + layer * 0.04
	var wading := false
	if not submerged and absf(feet_y - ground_y) <= layer * 0.85:
		wading = true
	if not submerged and not wading:
		return dry(ground_y)
	var float_y := ground_y
	if deep:
		var sink := layer * 0.5
		if body_height > layer:
			sink = clampf(body_height * 0.55, layer * 0.45, body_height * 0.8)
		float_y = maxf(ground_y, surface - sink)
	return {
		"in_water": true,
		"deep": deep,
		"submerged": submerged,
		"wading": wading and not submerged,
		"surface_y": surface,
		"float_y": float_y,
		"ground_y": ground_y,
		"speed_mult": SWIM_SPEED_MULT if submerged else WADE_SPEED_MULT,
	}


static func visual_drop(info: Dictionary, feet_y: float, body_height: float, depth: float) -> float:
	if not bool(info.get("submerged", false)):
		return 0.0
	var surface := float(info.get("surface_y", feet_y))
	return maxf(0.0, feet_y - (surface - body_height * depth))


static func settle_y(current_y: float, info: Dictionary, delta: float) -> float:
	if not bool(info.get("submerged", false)):
		return float(info.get("ground_y", current_y))
	var target: float = float(info.get("float_y", current_y))
	var k: float = clampf(BUOYANCY_RATE * delta, 0.0, 1.0)
	return lerpf(current_y, target, k)


static func _cell_water(world, col_x: int, col_z: int, ground_y: float, layer: float) -> Dictionary:
	var level := _channel_level(col_x, col_z)
	if level >= 0.05:
		var sy: float = _ChannelRegistry.get_runtime_surface_y(col_x, col_z)
		if sy <= 0.01:
			sy = ground_y + layer * clampf(level, 0.35, 1.0)
		return {"surface": sy, "bed": ground_y}
	if _is_inland_water_tile(world, col_x, col_z):
		return {"surface": ground_y, "bed": ground_y - float(_VoxelFluidEngine.SOURCE_DEPTH_LAYERS) * layer}
	return {}


static func _channel_level(col_x: int, col_z: int) -> float:
	# Do not create a session just to discover there is no water.
	if _WorldState._active == null:
		return 0.0
	if not _ChannelRegistry.has_fluid(col_x, col_z, _ChannelRegistry.FLUID_WATER):
		return 0.0
	return _ChannelRegistry.get_water_level(col_x, col_z)


static func _is_inland_water_tile(world, col_x: int, col_z: int) -> bool:
	if world == null or not world.has_method("get_tile_type"):
		return false
	var tile: int = int(world.get_tile_type(float(col_x) + 0.5, float(col_z) + 0.5))
	# Border ocean stays a wall. WorldBorder blocks the step; swimming must not carry a body along it.
	if _WorldBorder.is_ocean_tile(tile):
		return false
	return _CrystalTypes.is_water_tile(tile)
