class_name CrystalFluidSim
extends RefCounted

const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

signal depth_changed(pos: Vector2i)
signal depth_cleared(pos: Vector2i)

var config: _CrystalSimConfig
var terrain: _CrystalTerrainQuery
var global_flow_mult: float = 1.0

var depth: Dictionary = {}
var spawn_id_by_cell: Dictionary = {}
## 0 = unlimited. Rotating subset of existing cells simulated per tick.
var max_cells_per_tick: int = 0
## 0 = unlimited. Hard cap on brand-new frontier cells created per tick.
var max_new_cells_per_tick: int = 0
var spread_damping_start_cells: int = 600
var spread_damping_full_cells: int = 3000
var spread_damping_min_mult: float = 0.35
## Max depth that can flow into an empty neighbor per tick (gradual frontier).
var empty_cell_inflow_cap: float = 0.10
## Sim writes depth when delta exceeds this; smaller changes are ignored.
var depth_write_epsilon: float = 0.03
## Mesh/visual updates only when depth delta exceeds this (reduces rebuild churn).
var mesh_depth_epsilon: float = 0.20

var last_new_cells: int = 0
var last_changed_cells: int = 0
var last_mesh_dirty_cells: int = 0

var _interior_flow_offset: int = 0
var _frontier_new_offset: int = 0
## When set, flow/emitters only affect cells where this returns true (loaded chunks).
var is_cell_active: Callable = Callable()


func _init(p_config: _CrystalSimConfig, p_terrain: _CrystalTerrainQuery) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	terrain = p_terrain


func clear() -> void:
	depth.clear()
	spawn_id_by_cell.clear()
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0


func get_depth_at(wx: int, wz: int) -> float:
	return float(depth.get(Vector2i(wx, wz), 0.0))


func has_crystal_at(wx: int, wz: int) -> bool:
	return get_depth_at(wx, wz) >= config.min_depth


func cell_count() -> int:
	return depth.size()


func _surface_level(pos: Vector2i) -> float:
	return terrain.get_terrain_height(pos) + float(depth.get(pos, 0.0))


func _spread_pressure_mult() -> float:
	var n: int = depth.size()
	if spread_damping_start_cells <= 0 or n < spread_damping_start_cells:
		return 1.0
	var span: int = maxi(spread_damping_full_cells - spread_damping_start_cells, 1)
	var t: float = clampf(float(n - spread_damping_start_cells) / float(span), 0.0, 1.0)
	# Ease-in so damping ramps before the nominal start threshold.
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
		var neighbor: Vector2i = pos + dir
		if float(depth.get(neighbor, 0.0)) < config.min_depth:
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
	return amount < config.min_depth


func _cap_transfer_to_empty(transfer: float, _new_budget: int = 0) -> float:
	transfer = minf(transfer, empty_cell_inflow_cap)
	if transfer < config.min_depth * 0.15:
		return 0.0
	return transfer


func _new_cell_touch_count(pos: Vector2i) -> int:
	var touches := 0
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var neighbor: Vector2i = pos + dir
		if float(depth.get(neighbor, 0.0)) >= config.min_depth:
			touches += 1
	return touches


func _new_cell_priority(pos: Vector2i, magnitude: float) -> float:
	var touches: int = _new_cell_touch_count(pos)
	var hole_bonus := 0
	for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
		var a: Vector2i = pos + axis
		var b: Vector2i = pos - axis
		if float(depth.get(a, 0.0)) >= config.min_depth and float(depth.get(b, 0.0)) >= config.min_depth:
			hole_bonus += 4
	return float(touches) * 12.0 + float(hole_bonus) + magnitude


func set_depth(pos: Vector2i, new_depth: float, spawn_id: int = -1, emit: bool = true) -> void:
	new_depth = clampf(new_depth, 0.0, config.max_depth)
	if new_depth < config.min_depth:
		if depth.has(pos):
			depth.erase(pos)
			spawn_id_by_cell.erase(pos)
			if emit:
				depth_cleared.emit(pos)
				depth_changed.emit(pos)
		return

	var changed: bool = not depth.has(pos) or absf(float(depth[pos]) - new_depth) > 0.02
	depth[pos] = new_depth
	if spawn_id >= 0:
		spawn_id_by_cell[pos] = spawn_id
	if changed and emit:
		depth_changed.emit(pos)


func _cell_active(pos: Vector2i) -> bool:
	if is_cell_active.is_valid():
		return bool(is_cell_active.call(pos))
	return true


func tick_emitters(spawn_points: Array, delta: float, emit_weaken_mult: float = 1.0) -> void:
	var mult: float = maxf(emit_weaken_mult, 0.05) * _spread_pressure_mult()
	for spawn in spawn_points:
		if not spawn.active:
			continue
		var pos: Vector2i = spawn.world_pos
		if not _cell_active(pos):
			continue
		var current: float = float(depth.get(pos, 0.0))
		var added: float = spawn.emit_rate * mult * delta
		var room := config.max_depth - current
		if room <= 0.0:
			continue
		set_depth(pos, current + minf(added, room), spawn.id)


## Returns cells whose depth changed (batched — no per-cell signals during flow).
## Mesh rebuilds should use get_last_mesh_dirty_cells() / mesh_dirty subset only.
func tick_flow(delta: float) -> Array:
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	if depth.is_empty():
		return []

	var spread_mult: float = _spread_pressure_mult() * global_flow_mult
	var lateral_mult: float = spread_mult
	if spread_mult < 0.99:
		lateral_mult = spread_mult * spread_mult
	var allow_lateral: bool = config.lateral_spread_bias > 0.0 and spread_mult >= 0.55

	var active_cells: Array = []
	for pos_variant in depth.keys():
		var pos: Vector2i = pos_variant
		if _cell_active(pos):
			active_cells.append(pos)
	var cells: Array = _select_flow_cells(active_cells)

	var deltas: Dictionary = {}

	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		if not _cell_active(pos):
			continue
		var amount: float = float(depth.get(pos, 0.0))
		if amount < config.min_depth:
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

			var conduct: float = _flow_conductivity(my_tile, n_tile, pos, neighbor)
			if conduct <= 0.001:
				continue

			var transfer: float = min(
				pressure * config.pressure_flow_rate * conduct * delta * spread_mult,
				amount * config.max_outflow_ratio,
				config.max_flow_per_cell * delta,
				pressure * 0.5
			)
			if _is_empty_neighbor(n_amount):
				transfer = _cap_transfer_to_empty(transfer)
				if transfer <= 0.0:
					continue
			if transfer < config.min_depth * 0.2:
				continue

			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			_assign_spawn_on_flow(neighbor, pos)

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
				var spread: float = min(amount * conduct * delta, config.max_flow_per_cell * delta * 0.35)
				if _is_empty_neighbor(n_amount):
					spread = _cap_transfer_to_empty(spread)
					if spread <= 0.0:
						continue
				if spread < config.min_depth * 0.15:
					continue
				deltas[pos] = float(deltas.get(pos, 0.0)) - spread
				deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + spread
				_assign_spawn_on_flow(neighbor, pos)

	var changed: Array = []
	var mesh_dirty: Array = []
	var pending_new: Array = []

	for pos_variant in deltas.keys():
		var pos: Vector2i = pos_variant
		var old_depth: float = float(depth.get(pos, 0.0))
		var new_depth: float = old_depth + float(deltas[pos])
		var was_empty: bool = old_depth < config.min_depth
		var spawn_id: int = int(spawn_id_by_cell.get(pos, -1))

		if new_depth < config.min_depth:
			if depth.has(pos):
				depth.erase(pos)
				spawn_id_by_cell.erase(pos)
				changed.append(pos)
				mesh_dirty.append(pos)
			continue

		if was_empty and new_depth >= config.min_depth:
			pending_new.append({
				"pos": pos,
				"depth": new_depth,
				"spawn_id": spawn_id,
				"magnitude": absf(float(deltas[pos])),
			})
			continue

		if absf(old_depth - new_depth) > depth_write_epsilon:
			depth[pos] = new_depth
			if spawn_id >= 0:
				spawn_id_by_cell[pos] = spawn_id
			changed.append(pos)
			if absf(old_depth - new_depth) >= mesh_depth_epsilon:
				mesh_dirty.append(pos)

	if not pending_new.is_empty():
		pending_new.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var score_a: float = _new_cell_priority(a.pos, float(a.magnitude))
			var score_b: float = _new_cell_priority(b.pos, float(b.magnitude))
			return score_a > score_b
		)
		var allow: int = pending_new.size()
		if max_new_cells_per_tick > 0:
			allow = mini(allow, max_new_cells_per_tick)
		if allow < pending_new.size():
			var rotated: Array = []
			var start: int = _frontier_new_offset % pending_new.size()
			for i in pending_new.size():
				rotated.append(pending_new[(start + i) % pending_new.size()])
			pending_new = rotated
			_frontier_new_offset += allow
		for i in allow:
			var entry: Dictionary = pending_new[i]
			var pos: Vector2i = entry.pos
			depth[pos] = float(entry.depth)
			var spawn_id: int = int(entry.spawn_id)
			if spawn_id >= 0:
				spawn_id_by_cell[pos] = spawn_id
			changed.append(pos)
			mesh_dirty.append(pos)
			last_new_cells += 1

	last_changed_cells = changed.size()
	last_mesh_dirty_cells = mesh_dirty.size()
	_last_mesh_dirty = mesh_dirty
	return changed


var _last_mesh_dirty: Array = []


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
		if to_depth >= config.min_depth and from_depth >= config.min_depth:
			combined *= config.river_flow_factor
		elif from_depth >= config.min_depth:
			# Frontier spread into empty river/water — slow but not frozen.
			combined *= maxf(config.river_flow_factor, 0.32)

	return combined


func _cliff_blocked(from: Vector2i, to: Vector2i) -> bool:
	var from_terrain: float = terrain.get_terrain_height(from)
	var to_terrain: float = terrain.get_terrain_height(to)
	if to_terrain <= from_terrain + config.cliff_height:
		return false
	var my_top: float = from_terrain + float(depth.get(from, 0.0))
	return my_top <= to_terrain + config.min_flow_diff


func _assign_spawn_on_flow(to: Vector2i, from: Vector2i) -> void:
	if spawn_id_by_cell.has(to):
		return
	if spawn_id_by_cell.has(from):
		spawn_id_by_cell[to] = spawn_id_by_cell[from]


func recalc_volume() -> Dictionary:
	var total := 0.0
	var count := depth.size()
	for pos_variant in depth.keys():
		total += float(depth[pos_variant])
	return {"volume": total, "cells": count}