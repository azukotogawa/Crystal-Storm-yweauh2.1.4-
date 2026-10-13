class_name VoxelFluidEngine
extends RefCounted

const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidTypeDef = preload("res://config/fluid_type_def.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

signal depth_changed(pos: Vector2i)
signal depth_cleared(pos: Vector2i)

var config: _CrystalSimConfig
var terrain: _CrystalTerrainQuery
var fluid_def: _FluidTypeDef
var global_flow_mult: float = 1.0

var depth: Dictionary = {}
var max_cells_per_tick: int = 0
var max_new_cells_per_tick: int = 0
var spread_damping_start_cells: int = 600
var spread_damping_full_cells: int = 3000
var spread_damping_min_mult: float = 0.35
var empty_cell_inflow_cap: float = 0.018
var depth_write_epsilon: float = 0.03
var mesh_depth_epsilon: float = 0.20

var last_new_cells: int = 0
var last_changed_cells: int = 0
var last_mesh_dirty_cells: int = 0

var _interior_flow_offset: int = 0
var _frontier_new_offset: int = 0
var is_cell_active: Callable = Callable()
var _subset_cells: Array = []
var _last_mesh_dirty: Array = []


func _init(
	p_config: _CrystalSimConfig,
	p_terrain: _CrystalTerrainQuery,
	p_fluid_def: _FluidTypeDef = null
) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	terrain = p_terrain
	fluid_def = p_fluid_def


func _min_depth() -> float:
	return fluid_def.min_depth if fluid_def else config.min_depth


func _max_depth() -> float:
	return fluid_def.max_depth if fluid_def else config.max_depth


func _flow_model() -> int:
	if fluid_def:
		return int(fluid_def.flow_model)
	return _FluidTypeDef.FlowModel.PRESSURE_POOL


func clear() -> void:
	depth.clear()
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	_subset_cells.clear()


func get_depth_at(wx: int, wz: int) -> float:
	return float(depth.get(Vector2i(wx, wz), 0.0))


func has_fluid_at(wx: int, wz: int) -> bool:
	return get_depth_at(wx, wz) >= _min_depth()


func cell_count() -> int:
	return depth.size()


func set_subset_cells(cells: Array) -> void:
	_subset_cells = cells.duplicate()


func clear_subset_cells() -> void:
	_subset_cells.clear()


func _surface_level(pos: Vector2i) -> float:
	return terrain.get_terrain_height(pos) + float(depth.get(pos, 0.0))


func _spread_pressure_mult() -> float:
	var n: int = depth.size()
	if spread_damping_start_cells <= 0 or n < spread_damping_start_cells:
		return 1.0
	var span: int = maxi(spread_damping_full_cells - spread_damping_start_cells, 1)
	var t: float = clampf(float(n - spread_damping_start_cells) / float(span), 0.0, 1.0)
	t = t * t
	return lerpf(1.0, spread_damping_min_mult, t)


func _effective_flow_cap() -> int:
	if max_cells_per_tick <= 0:
		return 0
	var n: int = depth.size()
	if n <= 180:
		return max_cells_per_tick
	var scale: float = clampf(220.0 / float(n), 0.30, 1.0)
	return maxi(48, int(round(float(max_cells_per_tick) * scale)))


func _has_empty_neighbor(pos: Vector2i) -> bool:
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		if float(depth.get(pos + dir, 0.0)) < _min_depth():
			return true
	return false


func _select_flow_cells(cells: Array) -> Array:
	var cap: int = _effective_flow_cap()
	if cap <= 0 or cells.size() <= cap:
		return cells
	var frontier: Array = []
	var interior: Array = []
	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		if _has_empty_neighbor(pos):
			frontier.append(pos)
		else:
			interior.append(pos)
	var subset: Array = []
	for pos_variant in frontier:
		if subset.size() >= cap:
			break
		subset.append(pos_variant)
	if subset.size() < cap and not interior.is_empty():
		var start: int = _interior_flow_offset % interior.size()
		_interior_flow_offset += maxi(cap - subset.size(), 1)
		var remaining: int = cap - subset.size()
		for i in remaining:
			subset.append(interior[(start + i) % interior.size()])
	return subset


func _is_empty_neighbor(amount: float) -> bool:
	return amount < _min_depth()


func _cap_transfer_to_empty(transfer: float) -> float:
	transfer = minf(transfer, empty_cell_inflow_cap)
	if transfer < _min_depth() * 0.15:
		return 0.0
	return transfer


func set_depth(pos: Vector2i, new_depth: float, _spawn_id: int = -1, emit: bool = true) -> void:
	new_depth = clampf(new_depth, 0.0, _max_depth())
	if new_depth < _min_depth():
		if depth.has(pos):
			depth.erase(pos)
			if emit:
				depth_cleared.emit(pos)
				depth_changed.emit(pos)
		return
	var changed: bool = not depth.has(pos) or absf(float(depth[pos]) - new_depth) > 0.02
	depth[pos] = new_depth
	if changed and emit:
		depth_changed.emit(pos)


func _cell_active(pos: Vector2i) -> bool:
	if is_cell_active.is_valid():
		return bool(is_cell_active.call(pos))
	return true


func tick_flow(delta: float) -> Array:
	if _flow_model() == _FluidTypeDef.FlowModel.GRAVITY_CHANNEL:
		return _tick_flow_gravity(delta)
	return _tick_flow_pressure(delta)


func _active_cell_list() -> Array:
	if not _subset_cells.is_empty():
		var out: Array = []
		for pos_variant in _subset_cells:
			var pos: Vector2i = pos_variant
			if depth.has(pos) and float(depth[pos]) >= _min_depth() and _cell_active(pos):
				out.append(pos)
		return out
	var active_cells: Array = []
	for pos_variant in depth.keys():
		var pos: Vector2i = pos_variant
		if _cell_active(pos):
			active_cells.append(pos)
	return active_cells


func _tick_flow_gravity(delta: float) -> Array:
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	if depth.is_empty():
		return []

	var spread: float = fluid_def.spread_speed if fluid_def else 2.0
	var viscosity: float = maxf(fluid_def.viscosity if fluid_def else 0.2, 0.05)
	var gravity: float = clampf(fluid_def.gravity_preference if fluid_def else 1.0, 0.0, 1.0)
	var rate: float = spread / viscosity * delta * global_flow_mult * gravity
	var cliff_h: float = fluid_def.max_flow_distance if fluid_def else config.cliff_height
	var min_diff: float = config.min_flow_diff
	var uphill: float = fluid_def.uphill_capability if fluid_def else 0.0

	var cells: Array = _active_cell_list()
	var deltas: Dictionary = {}

	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		var amount: float = float(depth.get(pos, 0.0))
		if amount < _min_depth():
			continue
		var my_surface: float = _surface_level(pos)
		var remaining: float = amount

		var neighbors: Array = []
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = pos + dir
			if not _cell_active(neighbor):
				continue
			var n_amount: float = float(depth.get(neighbor, 0.0))
			var n_surface: float = terrain.get_terrain_height(neighbor) + n_amount
			var drop: float = my_surface - n_surface
			if drop <= min_diff * 0.5:
				if uphill > 0.0 and drop < 0.0 and absf(drop) <= cliff_h * uphill:
					neighbors.append({"pos": neighbor, "drop": drop, "surface": n_surface, "uphill": true})
				continue
			neighbors.append({"pos": neighbor, "drop": drop, "surface": n_surface, "uphill": false})

		neighbors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a.uphill != b.uphill:
				return not a.uphill
			return float(a.drop) > float(b.drop)
		)

		for entry in neighbors:
			if remaining <= _min_depth() * 0.2:
				break
			var neighbor: Vector2i = entry.pos
			var drop: float = float(entry.drop)
			var cliff_mult: float = 1.0
			if not entry.uphill and drop >= cliff_h:
				cliff_mult = 2.8
			var bias: float = terrain.get_channel_flow_mult(pos, neighbor)
			var transfer: float = minf(
				remaining,
				minf(
					remaining * 0.5 * rate * cliff_mult * bias,
					drop * spread * delta * 0.65 * cliff_mult * gravity
				)
			)
			if _is_empty_neighbor(float(depth.get(neighbor, 0.0))):
				transfer = _cap_transfer_to_empty(transfer)
			if entry.uphill:
				transfer *= uphill
			if transfer < _min_depth() * 0.15:
				continue
			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			remaining -= transfer

	return _apply_deltas(deltas)


func _tick_flow_pressure(delta: float) -> Array:
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	if depth.is_empty():
		return []

	var gravity: float = clampf(fluid_def.gravity_preference if fluid_def else 0.35, 0.0, 1.0)
	var spread_mult: float = _spread_pressure_mult() * global_flow_mult * lerpf(0.55, 1.0, gravity)
	var lateral_mult: float = spread_mult * lerpf(1.0, 0.65, gravity)
	if spread_mult < 0.99:
		lateral_mult = spread_mult * spread_mult
	var allow_lateral: bool = config.lateral_spread_bias > 0.0 and spread_mult >= 0.55
	var cells: Array = _select_flow_cells(_active_cell_list())
	var deltas: Dictionary = {}

	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		if not _cell_active(pos):
			continue
		var amount: float = float(depth.get(pos, 0.0))
		if amount < _min_depth():
			continue
		var my_surface: float = _surface_level(pos)
		var my_tile := terrain.get_tile(pos)

		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = pos + dir
			if not _cell_active(neighbor):
				continue
			if _cliff_blocked(pos, neighbor):
				continue
			var n_tile := terrain.get_tile(neighbor)
			var n_amount: float = float(depth.get(neighbor, 0.0))
			var n_surface: float = terrain.get_terrain_height(neighbor) + n_amount
			var pressure: float = my_surface - n_surface
			if pressure <= config.min_flow_diff:
				continue
			if n_surface > my_surface + config.min_flow_diff * 0.5:
				if _is_empty_neighbor(n_amount):
					continue
				pressure *= config.uphill_flow_penalty
			elif my_surface > n_surface + config.min_flow_diff:
				var drop: float = my_surface - n_surface
				pressure *= 1.0 + clampf(drop * config.downhill_flow_bonus * gravity, 0.0, 0.85)
			var conduct: float = _flow_conductivity(my_tile, n_tile, pos, neighbor)
			if conduct <= 0.001:
				continue
			var transfer: float = min(
				pressure * config.pressure_flow_rate * conduct * delta * spread_mult,
				amount * config.max_outflow_ratio,
				config.max_flow_per_cell * delta,
				pressure * 0.35
			)
			if _is_empty_neighbor(n_amount):
				transfer = _cap_transfer_to_empty(transfer)
				if transfer <= 0.0:
					continue
			if transfer < _min_depth() * 0.2:
				continue
			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			_on_fluid_transfer(pos, neighbor)

		if allow_lateral:
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				var neighbor: Vector2i = pos + dir
				if not _cell_active(neighbor):
					continue
				if _cliff_blocked(pos, neighbor):
					continue
				var n_tile := terrain.get_tile(neighbor)
				var n_amount: float = float(depth.get(neighbor, 0.0))
				var conduct: float = (
					_flow_conductivity(my_tile, n_tile, pos, neighbor)
					* config.lateral_spread_bias
					* lateral_mult
				)
				var spread_amt: float = min(amount * conduct * delta, config.max_flow_per_cell * delta * 0.35)
				if _is_empty_neighbor(n_amount):
					spread_amt = _cap_transfer_to_empty(spread_amt)
					if spread_amt <= 0.0:
						continue
				if spread_amt < _min_depth() * 0.15:
					continue
				deltas[pos] = float(deltas.get(pos, 0.0)) - spread_amt
				deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + spread_amt
				_on_fluid_transfer(pos, neighbor)

	return _apply_deltas(deltas)


func _on_fluid_transfer(_from: Vector2i, _to: Vector2i) -> void:
	pass


func _apply_deltas(deltas: Dictionary) -> Array:
	var changed: Array = []
	var mesh_dirty: Array = []
	var pending_new: Array = []

	for pos_variant in deltas.keys():
		var pos: Vector2i = pos_variant
		var old_depth: float = float(depth.get(pos, 0.0))
		var new_depth: float = old_depth + float(deltas[pos])
		var was_empty: bool = old_depth < _min_depth()

		if new_depth < _min_depth():
			if depth.has(pos):
				depth.erase(pos)
				changed.append(pos)
				mesh_dirty.append(pos)
			continue

		if was_empty and new_depth >= _min_depth():
			pending_new.append({"pos": pos, "depth": new_depth, "magnitude": absf(float(deltas[pos]))})
			continue

		if absf(old_depth - new_depth) > depth_write_epsilon:
			depth[pos] = new_depth
			changed.append(pos)
			if absf(old_depth - new_depth) >= mesh_depth_epsilon:
				mesh_dirty.append(pos)

	if not pending_new.is_empty():
		pending_new.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.magnitude) > float(b.magnitude)
		)
		var allow: int = pending_new.size()
		if max_new_cells_per_tick > 0:
			allow = mini(allow, max_new_cells_per_tick)
		for i in mini(allow, pending_new.size()):
			var entry: Dictionary = pending_new[i]
			var pos: Vector2i = entry.pos
			depth[pos] = float(entry.depth)
			changed.append(pos)
			mesh_dirty.append(pos)
			last_new_cells += 1

	last_changed_cells = changed.size()
	last_mesh_dirty_cells = mesh_dirty.size()
	_last_mesh_dirty = mesh_dirty
	return changed


func get_last_mesh_dirty() -> Array:
	return _last_mesh_dirty


func _flow_conductivity(from_tile: int, to_tile: int, from_pos: Vector2i, to_pos: Vector2i) -> float:
	var out_factor: float = terrain.get_flow_factor_at(from_pos, from_tile)
	var in_factor: float = terrain.get_flow_factor_at(to_pos, to_tile)
	var combined: float = sqrt(out_factor * in_factor)
	combined *= terrain.get_channel_flow_mult(from_pos, to_pos)
	if terrain.is_water_tile(to_tile) or to_tile == _VoxelTypes.RIVER:
		combined *= config.water_build_over_rate
	if terrain.is_water_tile(from_tile) and terrain.is_water_tile(to_tile):
		var to_depth: float = float(depth.get(to_pos, 0.0))
		var from_depth: float = float(depth.get(from_pos, 0.0))
		if to_depth >= _min_depth() and from_depth >= _min_depth():
			combined *= config.river_flow_factor
		elif from_depth >= _min_depth():
			combined *= maxf(config.river_flow_factor, 0.32)
	return combined


func _cliff_blocked(from: Vector2i, to: Vector2i) -> bool:
	var from_terrain: float = terrain.get_terrain_height(from)
	var to_terrain: float = terrain.get_terrain_height(to)
	var cliff_h: float = fluid_def.max_flow_distance if fluid_def else config.cliff_height
	if to_terrain <= from_terrain + cliff_h:
		return false
	var my_top: float = from_terrain + float(depth.get(from, 0.0))
	return my_top <= to_terrain + config.min_flow_diff


func recalc_volume() -> Dictionary:
	var total := 0.0
	for pos_variant in depth.keys():
		total += float(depth[pos_variant])
	return {"volume": total, "cells": depth.size()}