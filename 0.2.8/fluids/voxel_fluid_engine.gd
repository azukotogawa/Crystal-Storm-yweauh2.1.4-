class_name VoxelFluidEngine
extends RefCounted

const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidTypeDef = preload("res://config/fluid_type_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const SOURCE_LEVEL := 8
const FALL_LEVEL := 7
const FALL_STEP := 0.5

var config: _CrystalSimConfig
var terrain: _CrystalTerrainQuery
var fluid_def: _FluidTypeDef

var depth: Dictionary = {}
var sources: Dictionary = {}
var max_cells_per_tick: int = 0
var last_processed: int = 0
var leftover: Array = []
var is_cell_active: Callable = Callable()

var _work: Array = []


func _init(
	p_config: _CrystalSimConfig,
	p_terrain: _CrystalTerrainQuery,
	p_fluid_def: _FluidTypeDef = null
) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	terrain = p_terrain
	fluid_def = p_fluid_def


func clear() -> void:
	depth.clear()
	sources.clear()
	leftover = []
	last_processed = 0
	_work.clear()


func set_subset_cells(cells: Array) -> void:
	_work = cells.duplicate()


func level_at(pos: Vector2i) -> int:
	if sources.has(pos):
		return SOURCE_LEVEL
	return int(depth.get(pos, 0))


func get_depth_at(wx: int, wz: int) -> float:
	return float(level_at(Vector2i(wx, wz)))


func has_fluid_at(wx: int, wz: int) -> bool:
	return level_at(Vector2i(wx, wz)) > 0


func cell_count() -> int:
	return depth.size() + sources.size()


func set_level(pos: Vector2i, level: int) -> void:
	if level <= 0:
		depth.erase(pos)
		return
	depth[pos] = mini(level, SOURCE_LEVEL)


func _layer() -> float:
	return _WorldSettings.get_active().layer_height()


func bed_at(pos: Vector2i) -> float:
	var h: float = terrain.get_terrain_height(pos)
	if sources.has(pos):
		return h - _layer()
	return h


func surface_at(pos: Vector2i) -> float:
	var level := level_at(pos)
	if level <= 0:
		return terrain.get_terrain_height(pos)
	return bed_at(pos) + float(level) / float(SOURCE_LEVEL) * _layer()


func _cell_active(pos: Vector2i) -> bool:
	if is_cell_active.is_valid():
		return bool(is_cell_active.call(pos))
	return true


func tick_flow(_delta: float) -> Array:
	var cap := max_cells_per_tick if max_cells_per_tick > 0 else _work.size()
	var batch: Array = _work.slice(0, cap)
	leftover = _work.slice(cap)
	_work = []
	last_processed = batch.size()
	var layer := _layer()
	var changed: Array = []
	var seen: Dictionary = {}
	for pos_variant in batch:
		var pos: Vector2i = pos_variant
		if seen.has(pos):
			continue
		seen[pos] = true
		var level := level_at(pos)
		if level <= 0 or not _cell_active(pos):
			continue
		var surface := surface_at(pos)
		var bed := bed_at(pos)
		var falls: Array = []
		var spreads: Array = []
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = pos + dir
			if sources.has(n) or not _cell_active(n):
				continue
			var floor_y: float = terrain.get_terrain_height(n)
			if floor_y <= bed - layer * FALL_STEP:
				falls.append(n)
			elif floor_y < surface - 0.001:
				spreads.append(n)
		if not falls.is_empty():
			for n in falls:
				_raise(n, FALL_LEVEL, changed)
		elif level > 1:
			for n in spreads:
				_raise(n, level - 1, changed)
	return changed


func _raise(pos: Vector2i, level: int, changed: Array) -> void:
	if level_at(pos) >= level:
		return
	depth[pos] = level
	changed.append(pos)
