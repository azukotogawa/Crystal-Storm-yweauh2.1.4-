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
## 0 = unlimited. When set, only a rotating subset of cells is simulated per tick.
var max_cells_per_tick: int = 0
var _flow_tick_offset: int = 0


func _init(p_config: _CrystalSimConfig, p_terrain: _CrystalTerrainQuery) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	terrain = p_terrain


func clear() -> void:
	depth.clear()
	spawn_id_by_cell.clear()


func get_depth_at(wx: int, wz: int) -> float:
	return float(depth.get(Vector2i(wx, wz), 0.0))


func has_crystal_at(wx: int, wz: int) -> bool:
	return get_depth_at(wx, wz) >= config.min_depth


func _surface_level(pos: Vector2i) -> float:
	return terrain.get_terrain_height(pos) + float(depth.get(pos, 0.0))


func set_depth(pos: Vector2i, new_depth: float, spawn_id: int = -1) -> void:
	new_depth = clampf(new_depth, 0.0, config.max_depth)
	if new_depth < config.min_depth:
		if depth.has(pos):
			depth.erase(pos)
			spawn_id_by_cell.erase(pos)
			depth_cleared.emit(pos)
			depth_changed.emit(pos)
		return

	var changed: bool = not depth.has(pos) or absf(float(depth[pos]) - new_depth) > 0.02
	depth[pos] = new_depth
	if spawn_id >= 0:
		spawn_id_by_cell[pos] = spawn_id
	if changed:
		depth_changed.emit(pos)


func tick_emitters(spawn_points: Array, delta: float, emit_weaken_mult: float = 1.0) -> void:
	var mult: float = maxf(emit_weaken_mult, 0.05)
	for spawn in spawn_points:
		if not spawn.active:
			continue
		var pos: Vector2i = spawn.world_pos
		var current: float = float(depth.get(pos, 0.0))
		var added: float = spawn.emit_rate * mult * delta
		var room := config.max_depth - current
		if room <= 0.0:
			continue
		set_depth(pos, current + minf(added, room), spawn.id)


func tick_flow(delta: float) -> void:
	if depth.is_empty():
		return

	var cells: Array = depth.keys()
	if max_cells_per_tick > 0 and cells.size() > max_cells_per_tick:
		var start: int = _flow_tick_offset % cells.size()
		_flow_tick_offset += max_cells_per_tick
		var subset: Array = []
		for i in max_cells_per_tick:
			subset.append(cells[(start + i) % cells.size()])
		cells = subset

	var deltas: Dictionary = {}

	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		var amount: float = float(depth.get(pos, 0.0))
		if amount < config.min_depth:
			continue

		var my_surface: float = _surface_level(pos)
		var my_tile := terrain.get_tile(pos)

		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = pos + dir
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
				pressure * config.pressure_flow_rate * conduct * delta,
				amount * config.max_outflow_ratio,
				config.max_flow_per_cell * delta,
				pressure * 0.5
			)
			if transfer < config.min_depth * 0.2:
				continue

			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			_assign_spawn_on_flow(neighbor, pos)

		if config.lateral_spread_bias > 0.0:
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				var neighbor: Vector2i = pos + dir
				if _cliff_blocked(pos, neighbor):
					continue
				var n_tile := terrain.get_tile(neighbor)
				var conduct: float = _flow_conductivity(my_tile, n_tile, pos, neighbor) * config.lateral_spread_bias
				var spread: float = min(amount * conduct * delta, config.max_flow_per_cell * delta * 0.35)
				if spread < config.min_depth * 0.15:
					continue
				deltas[pos] = float(deltas.get(pos, 0.0)) - spread
				deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + spread
				_assign_spawn_on_flow(neighbor, pos)

	for pos_variant in deltas.keys():
		var pos: Vector2i = pos_variant
		var new_depth: float = float(depth.get(pos, 0.0)) + float(deltas[pos])
		var spawn_id: int = int(spawn_id_by_cell.get(pos, -1))
		set_depth(pos, new_depth, spawn_id)


func _flow_conductivity(from_tile: int, to_tile: int, from_pos: Vector2i, to_pos: Vector2i) -> float:
	var out_factor: float = terrain.get_flow_factor_at(from_pos, from_tile)
	var in_factor: float = terrain.get_flow_factor_at(to_pos, to_tile)
	var combined: float = sqrt(out_factor * in_factor)
	combined *= terrain.get_channel_flow_mult(from_pos, to_pos)

	if terrain.is_water_tile(to_tile) or to_tile == _VoxelTypes.RIVER:
		combined *= config.water_build_over_rate
	if terrain.is_water_tile(from_tile) and terrain.is_water_tile(to_tile):
		combined *= config.river_flow_factor

	return combined * global_flow_mult


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