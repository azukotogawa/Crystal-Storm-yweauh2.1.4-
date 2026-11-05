class_name CrystalFluidSim
extends RefCounted

const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _GameConfig = preload("res://config/game_config.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _Pulse = preload("res://player/crystal_pulse_skill.gd")

signal depth_changed(pos: Vector2i)
signal depth_cleared(pos: Vector2i)

var config: _CrystalSimConfig
var terrain: _CrystalTerrainQuery
var global_flow_mult: float = 1.0

var depth: Dictionary = {}
## Parallel SoA depth store (item6 milestone): seq-indexed floats. Dictionary
## `depth` remains the public sparse map; hot reads prefer depth_soa when the
## cell has a seq. Opt in with CRYSTALSTORM_CRYSTAL_DEPTH_SOA=1 (default ON).
var depth_soa: PackedFloat64Array = PackedFloat64Array()
var _soa_hot: bool = true
var spawn_id_by_cell: Dictionary = {}
var max_cells_per_tick: int = 0
var max_new_cells_per_tick: int = 0
var spread_damping_start_cells: int = 600
var spread_damping_full_cells: int = 3000
var spread_damping_min_mult: float = 0.35
var empty_cell_inflow_cap: float = 0.10
var depth_write_epsilon: float = 0.03
var mesh_depth_epsilon: float = 0.20

var last_new_cells: int = 0
var last_changed_cells: int = 0
var last_mesh_dirty_cells: int = 0
var last_flow_active_cells: int = 0
var last_flow_selected_cells: int = 0

var _interior_flow_offset: int = 0
var _frontier_new_offset: int = 0
var is_cell_active: Callable = Callable()
var chunk_gate: Callable = Callable()
var chunk_gate_size: int = 16
var _gate_memo: Dictionary = {}
var flow_budget_us: int = 0
var last_flow_complete: bool = true
var _flow_job: Dictionary = {}

var _prof_enabled: bool = false
var _prof_phase_us: Dictionary = {}
var _prof_phase_max_us: Dictionary = {}
var _prof_active_cells_sum: int = 0
var _prof_selected_cells_sum: int = 0
var _prof_depth_cells_sum: int = 0
var _prof_ticks: int = 0
var _prof_flow_calls: int = 0
var _prof_cells_processed: int = 0
var _prof_neighbor_evals: int = 0
var _prof_cliff_checks: int = 0
var _prof_conductivity_calls: int = 0
var _prof_flow_transfers: int = 0
var _prof_terrain_height: int = 0
var _prof_terrain_tile: int = 0
var _prof_chunk_crossings: int = 0
var _prof_frontier_classifies: int = 0
var _prof_empty_neighbor_tests: int = 0
var _prof_delta_applies: int = 0
var _CHUNK: int = 16
var _seq: Dictionary = {}
var _next_seq: int = 0
var _order: Array = []
var _order_valid: bool = true
var _frontier: Dictionary = {}
var _frontier_list: Array = []
var _frontier_seq: PackedInt64Array = PackedInt64Array()
var _chunk_cells: Dictionary = {}
var _chunk_cells_total: int = 0
var _interior: Array = []
var _interior_seq: PackedInt64Array = PackedInt64Array()
var _volume: float = 0.0
var _index_valid: bool = true
var index_full_scan_max: int = 2048
const _INTERIOR_WALK_MAX: int = 4096


func _init(p_config: _CrystalSimConfig, p_terrain: _CrystalTerrainQuery) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	terrain = p_terrain
	_refresh_soa_hot()


func depth_soa_enabled() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_CRYSTAL_DEPTH_SOA").strip_edges().to_lower()
	if raw == "0" or raw == "false" or raw == "off" or raw == "no":
		return false
	return true


func _refresh_soa_hot() -> void:
	_soa_hot = depth_soa_enabled()


## Hot-path depth read: seq-indexed PackedFloat64Array when SoA is on.
func _depth_of(pos: Vector2i) -> float:
	if _soa_hot:
		if _seq.has(pos):
			var sq: int = int(_seq[pos])
			if sq >= 0 and sq < depth_soa.size():
				return float(depth_soa[sq])
	return float(depth.get(pos, 0.0))


func clear() -> void:
	depth.clear()
	depth_soa = PackedFloat64Array()
	_refresh_soa_hot()
	spawn_id_by_cell.clear()
	_seq.clear()
	_next_seq = 0
	_order.clear()
	_order_valid = true
	_frontier.clear()
	_frontier_list.clear()
	_frontier_seq = PackedInt64Array()
	_interior.clear()
	_interior_seq = PackedInt64Array()
	_chunk_cells.clear()
	_chunk_cells_total = 0
	_volume = 0.0
	_index_valid = false
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	_frontier_new_offset = 0
	_flow_job.clear()
	last_flow_complete = true


func has_pending_flow() -> bool:
	return not _flow_job.is_empty()


func set_sim_profile_enabled(enabled: bool) -> void:
	_prof_enabled = enabled


func reset_sim_profile() -> void:
	_prof_phase_us.clear()
	_prof_phase_max_us.clear()
	_prof_active_cells_sum = 0
	_prof_selected_cells_sum = 0
	_prof_depth_cells_sum = 0
	_prof_ticks = 0
	_prof_flow_calls = 0
	_prof_cells_processed = 0
	_prof_neighbor_evals = 0
	_prof_cliff_checks = 0
	_prof_conductivity_calls = 0
	_prof_flow_transfers = 0
	_prof_terrain_height = 0
	_prof_terrain_tile = 0
	_prof_chunk_crossings = 0
	_prof_frontier_classifies = 0
	_prof_empty_neighbor_tests = 0
	_prof_delta_applies = 0


func get_sim_profile() -> Dictionary:
	var phases: Array = []
	for k in _prof_phase_us.keys():
		phases.append({
			"phase": k,
			"total_us": int(_prof_phase_us[k]),
			"max_us": int(_prof_phase_max_us.get(k, 0)),
			"total_ms": float(_prof_phase_us[k]) / 1000.0,
		})
	phases.sort_custom(func(a, b): return int(a.total_us) > int(b.total_us))
	var ticks := maxi(_prof_ticks, 1)
	var flow_calls := maxi(_prof_flow_calls, 1)
	return {
		"ticks_completed": _prof_ticks,
		"flow_calls": _prof_flow_calls,
		"avg_depth_cells": float(_prof_depth_cells_sum) / float(ticks),
		"avg_active_cells": float(_prof_active_cells_sum) / float(ticks),
		"avg_selected_cells": float(_prof_selected_cells_sum) / float(ticks),
		"cells_processed": _prof_cells_processed,
		"neighbor_evals": _prof_neighbor_evals,
		"cliff_checks": _prof_cliff_checks,
		"conductivity_calls": _prof_conductivity_calls,
		"flow_transfers": _prof_flow_transfers,
		"terrain_height_queries": _prof_terrain_height,
		"terrain_tile_queries": _prof_terrain_tile,
		"terrain_queries_total": _prof_terrain_height + _prof_terrain_tile,
		"chunk_crossings": _prof_chunk_crossings,
		"frontier_classifies": _prof_frontier_classifies,
		"empty_neighbor_tests": _prof_empty_neighbor_tests,
		"delta_applies": _prof_delta_applies,
		"per_selected_cell": {
			"neighbor_evals": float(_prof_neighbor_evals) / float(maxi(_prof_cells_processed, 1)),
			"terrain_queries": float(_prof_terrain_height + _prof_terrain_tile) / float(maxi(_prof_cells_processed, 1)),
			"conductivity": float(_prof_conductivity_calls) / float(maxi(_prof_cells_processed, 1)),
			"transfers": float(_prof_flow_transfers) / float(maxi(_prof_cells_processed, 1)),
		},
		"phases": phases,
	}


func _prof_add_phase(name: String, us: int) -> void:
	if not _prof_enabled:
		return
	_prof_phase_us[name] = int(_prof_phase_us.get(name, 0)) + us
	_prof_phase_max_us[name] = maxi(int(_prof_phase_max_us.get(name, 0)), us)


func _prof_is_chunk_cross(a: Vector2i, b: Vector2i) -> bool:
	return floori(float(a.x) / float(_CHUNK)) != floori(float(b.x) / float(_CHUNK)) \
		or floori(float(a.y) / float(_CHUNK)) != floori(float(b.y) / float(_CHUNK))


func get_depth_at(wx: int, wz: int) -> float:
	return _depth_of(Vector2i(wx, wz))


func has_crystal_at(wx: int, wz: int) -> bool:
	return get_depth_at(wx, wz) >= config.min_depth


func cell_count() -> int:
	return depth.size()


func get_last_flow_scan_stats() -> Dictionary:
	return {
		"active_cells": last_flow_active_cells,
		"selected_cells": last_flow_selected_cells,
	}


func _surface_level(pos: Vector2i) -> float:
	if _prof_enabled:
		_prof_terrain_height += 1
	return terrain.get_terrain_height(pos) + _depth_of(pos)


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
	if _prof_enabled:
		_prof_empty_neighbor_tests += 1
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var neighbor: Vector2i = pos + dir
		if _depth_of(neighbor) < config.min_depth:
			return true
	return false


func _select_flow_cells(cells: Array) -> Array:
	var cap: int = _effective_flow_cap()
	if cap <= 0 or cells.size() <= cap:
		return cells

	var t0 := Time.get_ticks_usec() if _prof_enabled else 0
	var frontier: Array = []
	var interior: Array = []
	for pos_variant in cells:
		var pos: Vector2i = pos_variant
		if _prof_enabled:
			_prof_frontier_classifies += 1
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

	if _prof_enabled:
		_prof_add_phase("select_flow_cells", Time.get_ticks_usec() - t0)
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
		if _depth_of(neighbor) >= config.min_depth:
			touches += 1
	return touches


func _new_cell_priority(pos: Vector2i, magnitude: float) -> float:
	var touches: int = _new_cell_touch_count(pos)
	var hole_bonus := 0
	for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
		var a: Vector2i = pos + axis
		var b: Vector2i = pos - axis
		if _depth_of(a) >= config.min_depth and _depth_of(b) >= config.min_depth:
			hole_bonus += 4
	return float(touches) * 12.0 + float(hole_bonus) + magnitude


func _frontier_jitter(pos: Vector2i) -> float:
	var h: int = pos.x * 73856093 ^ pos.y * 19349663
	if h < 0:
		h = -h
	return float(h % 997) / 997.0


func _frontier_diagonal_touches(pos: Vector2i) -> int:
	var n := 0
	for dir in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		if _depth_of(pos + dir) >= config.min_depth:
			n += 1
	return n


func _empty_neighbor_score(neighbor: Vector2i, transfer: float, pressure: float) -> float:
	return (
		_new_cell_priority(neighbor, transfer)
		+ pressure
		+ float(_frontier_diagonal_touches(neighbor)) * 2.0
		+ _frontier_jitter(neighbor) * 0.5
	)


func _frontier_birth_depth() -> float:
	return minf(empty_cell_inflow_cap, maxf(config.min_depth, config.min_flow_diff + config.min_depth))


func depth_cap(pos: Vector2i) -> float:
	var cap := config.max_depth
	if terrain != null and terrain.has_method("reserve_depth_mult"):
		cap *= maxf(terrain.reserve_depth_mult(pos), 0.25)
	return cap


func set_depth(pos: Vector2i, new_depth: float, spawn_id: int = -1, emit: bool = true) -> void:
	new_depth = clampf(new_depth, 0.0, depth_cap(pos))
	if new_depth < config.min_depth:
		if depth.has(pos):
			_erase_cell(pos)
			spawn_id_by_cell.erase(pos)
			if emit:
				depth_cleared.emit(pos)
				depth_changed.emit(pos)
		return

	var changed: bool = not depth.has(pos) or absf(_depth_of(pos) - new_depth) > 0.02
	_write_cell(pos, new_depth)
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
	var sources: Array = spawn_points
	if _GameConfig.SINGLE_CRYSTAL:
		sources = _single_emitter(spawn_points)
		if sources.is_empty():
			return
		mult *= _single_pressure_scale(sources[0])
	for spawn in sources:
		if not spawn.active:
			continue
		var pos: Vector2i = spawn.world_pos
		if not _cell_active(pos):
			continue
		var current: float = _depth_of(pos)
		var added: float = spawn.emit_rate * GameFeelConfig.pace() * mult * delta
		var room := depth_cap(pos) - current
		if room <= 0.0:
			continue
		set_depth(pos, current + minf(added, room), spawn.id)


func _single_emitter(spawn_points: Array) -> Array:
	var fallback = null
	for spawn in spawn_points:
		if not spawn.active:
			continue
		if fallback == null:
			fallback = spawn
		if _cell_active(spawn.world_pos):
			return [spawn]
	if fallback == null:
		return []
	return [fallback]


func _legacy_emit_pressure() -> float:
	var ruins := 2
	var arts := 1
	if config != null:
		ruins = maxi(int(config.ruin_spawn_count), 0)
		arts = maxi(int(config.artifact_spawn_count), 0)
	return (
		_CrystalTypes.emit_rate_for(_CrystalTypes.SpawnKind.ORIGIN)
		+ _CrystalTypes.emit_rate_for(_CrystalTypes.SpawnKind.RUIN) * float(ruins)
		+ _CrystalTypes.emit_rate_for(_CrystalTypes.SpawnKind.ARTIFACT) * float(arts)
	)


func _single_pressure_scale(spawn) -> float:
	var rate: float = float(spawn.emit_rate)
	if rate <= 0.001:
		return 1.0
	return _legacy_emit_pressure() / rate


func tick_flow(delta: float) -> Array:
	if not _flow_job.is_empty():
		return _flow_job_continue()
	return _flow_job_begin(delta)


func _flow_job_begin(delta: float) -> Array:
	last_new_cells = 0
	last_changed_cells = 0
	last_mesh_dirty_cells = 0
	last_flow_active_cells = 0
	last_flow_selected_cells = 0
	last_flow_complete = true
	_flow_job.clear()
	# Keep _soa_hot sticky for the instance lifetime (set in _init/clear).
	if depth.is_empty():
		return []

	var t_begin := Time.get_ticks_usec() if _prof_enabled else 0
	var spread_mult: float = _spread_pressure_mult() * global_flow_mult
	var lateral_mult: float = spread_mult
	if spread_mult < 0.99:
		lateral_mult = spread_mult * spread_mult
	var allow_lateral: bool = config.lateral_spread_bias > 0.0 and spread_mult >= 0.55

	var t_scan := Time.get_ticks_usec() if _prof_enabled else 0
	var cells: Array = []
	var active_count: int = 0
	var cap: int = _effective_flow_cap()
	if cap <= 0 or depth.size() <= index_full_scan_max:
		var active_cells: Array = []
		for pos_variant in depth.keys():
			var pos: Vector2i = pos_variant
			if _cell_active(pos):
				active_cells.append(pos)
		if _prof_enabled:
			_prof_add_phase("scan_active_cells", Time.get_ticks_usec() - t_scan)
		cells = _select_flow_cells(active_cells)
		active_count = active_cells.size()
	else:
		cells = _select_indexed_flow_cells(cap)
		active_count = depth.size()
		if _prof_enabled:
			_prof_add_phase("select_indexed", Time.get_ticks_usec() - t_scan)
	last_flow_active_cells = active_count
	last_flow_selected_cells = cells.size()
	if _prof_enabled:
		_prof_depth_cells_sum += depth.size()
		_prof_active_cells_sum += active_count
		_prof_selected_cells_sum += cells.size()
		_prof_ticks += 1
		_prof_add_phase("flow_job_begin", Time.get_ticks_usec() - t_begin)

	_flow_job = {
		"delta": delta,
		"cells": cells,
		"idx": 0,
		"deltas": {},
		"frontier": {},
		"spread_mult": spread_mult,
		"lateral_mult": lateral_mult,
		"allow_lateral": allow_lateral,
	}
	last_flow_complete = false
	return _flow_job_continue()


func _flow_job_continue() -> Array:
	if _flow_job.is_empty():
		last_flow_complete = true
		return []
	var cells: Array = _flow_job["cells"]
	var idx: int = int(_flow_job["idx"])
	var deltas: Dictionary = _flow_job["deltas"]
	var frontier: Dictionary = _flow_job["frontier"]
	var delta: float = float(_flow_job["delta"])
	var spread_mult: float = float(_flow_job["spread_mult"])
	var lateral_mult: float = float(_flow_job["lateral_mult"])
	var allow_lateral: bool = bool(_flow_job["allow_lateral"])
	var budget: int = flow_budget_us
	var t0 := Time.get_ticks_usec()
	var n: int = cells.size()
	if _prof_enabled:
		_prof_flow_calls += 1

	while idx < n:
		if budget > 0 and idx > int(_flow_job["idx"]) and (Time.get_ticks_usec() - t0) >= budget:
			_flow_job["idx"] = idx
			_flow_job["deltas"] = deltas
			_flow_job["frontier"] = frontier
			last_flow_complete = false
			if _prof_enabled:
				_prof_add_phase("process_selected_cells", Time.get_ticks_usec() - t0)
			return []
		var pos: Vector2i = cells[idx]
		idx += 1
		if not _cell_active(pos):
			continue
		var amount: float = _depth_of(pos)
		if amount < config.min_depth:
			continue
		if _prof_enabled:
			_prof_cells_processed += 1

		var my_surface: float = _surface_level(pos)
		if _prof_enabled:
			_prof_terrain_tile += 1
		var my_tile := terrain.get_tile(pos)
		var settle: Dictionary = {}
		var best_score := -1.0e20
		var best_neighbor := Vector2i.ZERO
		var best_transfer := 0.0
		var best_conduct := 0.0
		var has_best := false

		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var neighbor: Vector2i = pos + dir
			if _prof_enabled:
				_prof_neighbor_evals += 1
				if _prof_is_chunk_cross(pos, neighbor):
					_prof_chunk_crossings += 1
			if not _cell_active(neighbor):
				continue
			if _cliff_blocked(pos, neighbor):
				continue

			if _prof_enabled:
				_prof_terrain_tile += 1
			var n_tile := terrain.get_tile(neighbor)
			var n_amount: float = _depth_of(neighbor)
			if _prof_enabled:
				_prof_terrain_height += 1
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
				if transfer <= 0.0 and conduct < 0.25:
					continue
				if transfer < config.min_depth * 0.2 and conduct < 0.25:
					continue
				var score: float = _empty_neighbor_score(neighbor, transfer, pressure)
				if not has_best or score > best_score:
					has_best = true
					best_score = score
					best_neighbor = neighbor
					best_transfer = transfer
					best_conduct = conduct
			else:
				if transfer < config.min_depth * 0.2:
					continue
				settle[neighbor] = float(settle.get(neighbor, 0.0)) + transfer

		var from_pressure := has_best
		if allow_lateral:
			for dir in _CrystalTypes.NEIGHBOR_DIRS:
				var neighbor: Vector2i = pos + dir
				if _prof_enabled:
					_prof_neighbor_evals += 1
					if _prof_is_chunk_cross(pos, neighbor):
						_prof_chunk_crossings += 1
				if not _cell_active(neighbor):
					continue
				if _cliff_blocked(pos, neighbor):
					continue
				if _prof_enabled:
					_prof_terrain_tile += 1
				var n_tile := terrain.get_tile(neighbor)
				var n_amount: float = _depth_of(neighbor)
				var raw_conduct: float = _flow_conductivity(my_tile, n_tile, pos, neighbor)
				var conduct: float = raw_conduct * config.lateral_spread_bias * lateral_mult
				var spread: float = min(amount * conduct * delta, config.max_flow_per_cell * delta * 0.35)
				if _is_empty_neighbor(n_amount):
					if from_pressure:
						if neighbor == best_neighbor:
							spread = _cap_transfer_to_empty(spread)
							if spread >= config.min_depth * 0.15:
								best_transfer += spread
						continue
					spread = _cap_transfer_to_empty(spread)
					if spread <= 0.0 and raw_conduct < 0.25:
						continue
					var score: float = _empty_neighbor_score(neighbor, maxf(spread, config.min_depth), 0.0)
					if not has_best or score > best_score:
						has_best = true
						best_score = score
						best_neighbor = neighbor
						best_transfer = spread
						best_conduct = raw_conduct
					continue
				if spread < config.min_depth * 0.15:
					continue
				settle[neighbor] = float(settle.get(neighbor, 0.0)) + spread

		var settle_total := 0.0
		for key in settle.keys():
			settle_total += float(settle[key])
		var spare: float = maxf(amount - config.min_depth, 0.0)
		var settle_budget: float = minf(amount * config.max_outflow_ratio, spare)
		var settle_scale := 1.0
		if settle_total > settle_budget and settle_total > 0.0:
			settle_scale = settle_budget / settle_total
		var spent := 0.0
		for key in settle.keys():
			var neighbor: Vector2i = key
			var transfer: float = float(settle[key]) * settle_scale
			if transfer < config.min_depth * 0.15:
				continue
			deltas[pos] = float(deltas.get(pos, 0.0)) - transfer
			deltas[neighbor] = float(deltas.get(neighbor, 0.0)) + transfer
			spent += transfer
			if _prof_enabled:
				_prof_flow_transfers += 1

		if has_best:
			var birth: float = _frontier_birth_depth() * spread_mult * _Pulse.spread_scale(pos, best_neighbor)
			var gain: float = minf(best_transfer, empty_cell_inflow_cap)
			if gain < config.min_depth and best_conduct >= 0.25 and birth >= config.min_depth:
				gain = birth
			if gain >= config.min_depth:
				var pay: float = minf(gain, maxf(spare - spent, 0.0))
				var entry: Dictionary = frontier.get(best_neighbor, {})
				if entry.is_empty():
					entry = {"gain": 0.0, "score": -1.0e20, "pays": []}
				entry["gain"] = float(entry["gain"]) + gain
				entry["score"] = maxf(float(entry["score"]), best_score)
				var pays: Array = entry["pays"]
				pays.append({"donor": pos, "pay": pay})
				entry["pays"] = pays
				frontier[best_neighbor] = entry
				_assign_spawn_on_flow(best_neighbor, pos)
				if _prof_enabled:
					_prof_flow_transfers += 1

	if _prof_enabled:
		_prof_add_phase("process_selected_cells", Time.get_ticks_usec() - t0)

	var t_apply := Time.get_ticks_usec() if _prof_enabled else 0
	var changed: Array = _apply_flow_deltas(deltas, frontier)
	if _prof_enabled:
		_prof_add_phase("apply_flow_deltas", Time.get_ticks_usec() - t_apply)
		_prof_delta_applies += deltas.size()
	_flow_job.clear()
	last_flow_complete = true
	last_changed_cells = changed.size()
	last_mesh_dirty_cells = _last_mesh_dirty.size()
	return changed


func _apply_flow_deltas(deltas: Dictionary, frontier: Dictionary = {}) -> Array:
	var changed: Array = []
	var mesh_dirty: Array = []
	var pending_new: Array = []
	last_new_cells = 0

	for pos_variant in deltas.keys():
		var pos: Vector2i = pos_variant
		var old_depth: float = _depth_of(pos)
		var new_depth: float = old_depth + float(deltas[pos])
		var was_empty: bool = old_depth < config.min_depth
		var spawn_id: int = int(spawn_id_by_cell.get(pos, -1))

		# Flow never deletes a cell. Over-outflow used to erase the donor and
		# leave its mass on the opposite parity — the checkerboard blink.
		if not was_empty and new_depth < config.min_depth:
			new_depth = config.min_depth

		if new_depth < config.min_depth:
			if depth.has(pos):
				_erase_cell(pos)
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
			_write_cell(pos, new_depth)
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
		var allow_settle: int = pending_new.size()
		if max_new_cells_per_tick > 0:
			allow_settle = mini(allow_settle, max_new_cells_per_tick)
		for i in allow_settle:
			var entry: Dictionary = pending_new[i]
			var pos: Vector2i = entry.pos
			if _new_cell_touch_count(pos) < 1:
				continue
			_write_cell(pos, float(entry.depth))
			var spawn_id: int = int(entry.spawn_id)
			if spawn_id >= 0:
				spawn_id_by_cell[pos] = spawn_id
			changed.append(pos)
			mesh_dirty.append(pos)
			last_new_cells += 1

	if not frontier.is_empty():
		var ranked: Array = []
		for pos_variant in frontier.keys():
			var entry: Dictionary = frontier[pos_variant]
			ranked.append({
				"pos": pos_variant,
				"gain": float(entry.get("gain", 0.0)),
				"score": float(entry.get("score", 0.0)),
				"pays": entry.get("pays", []),
			})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.score) == float(b.score):
				var pa: Vector2i = a.pos
				var pb: Vector2i = b.pos
				if pa.x == pb.x:
					return pa.y < pb.y
				return pa.x < pb.x
			return float(a.score) > float(b.score)
		)
		var allow: int = ranked.size()
		var room: int = allow
		if max_new_cells_per_tick > 0:
			room = maxi(max_new_cells_per_tick - last_new_cells, 0)
			allow = mini(allow, room)
		for i in allow:
			var entry: Dictionary = ranked[i]
			var pos: Vector2i = entry.pos
			if _depth_of(pos) >= config.min_depth:
				continue
			if _new_cell_touch_count(pos) < 1:
				continue
			var gain: float = float(entry.gain)
			if gain < config.min_depth:
				continue
			var applied: float = minf(gain, empty_cell_inflow_cap)
			if applied < config.min_depth:
				continue
			var pays: Array = entry.pays
			var pay_sum := 0.0
			for pay_variant in pays:
				var summed: Dictionary = pay_variant
				pay_sum += float(summed.get("pay", 0.0))
			var pay_scale := 1.0
			if pay_sum > applied and pay_sum > 0.0:
				pay_scale = applied / pay_sum
			for pay_variant in pays:
				var pay_entry: Dictionary = pay_variant
				var donor: Vector2i = pay_entry.donor
				if not depth.has(donor):
					continue
				var paid: float = float(pay_entry.pay) * pay_scale
				var donor_old: float = _depth_of(donor)
				var donor_depth: float = maxf(donor_old - paid, config.min_depth)
				if absf(donor_depth - donor_old) > depth_write_epsilon:
					_write_cell(donor, donor_depth)
					changed.append(donor)
					if paid >= mesh_depth_epsilon:
						mesh_dirty.append(donor)
			var born: float = minf(_depth_of(pos) + applied, depth_cap(pos))
			if born < config.min_depth:
				continue
			_write_cell(pos, born)
			var spawn_id: int = int(spawn_id_by_cell.get(pos, -1))
			if spawn_id >= 0:
				spawn_id_by_cell[pos] = spawn_id
			changed.append(pos)
			mesh_dirty.append(pos)
			last_new_cells += 1
		_frontier_new_offset += 1

	_last_mesh_dirty = mesh_dirty
	return changed


var _last_mesh_dirty: Array = []


func get_last_mesh_dirty() -> Array:
	return _last_mesh_dirty


func _flow_conductivity(from_tile: int, to_tile: int, from_pos: Vector2i, to_pos: Vector2i) -> float:
	if _prof_enabled:
		_prof_conductivity_calls += 1
	if CrystalCorruption.has_scar(to_pos):
		return 0.0
	var out_factor: float = terrain.get_flow_factor_at(from_pos, from_tile)
	var in_factor: float = terrain.get_flow_factor_at(to_pos, to_tile)
	var combined: float = sqrt(out_factor * in_factor)
	combined *= terrain.get_channel_flow_mult(from_pos, to_pos)

	if terrain.is_water_tile(to_tile) or to_tile == _VoxelTypes.RIVER:
		combined *= config.water_build_over_rate
	if terrain.is_water_tile(from_tile) and terrain.is_water_tile(to_tile):
		var to_depth: float = _depth_of(to_pos)
		var from_depth: float = _depth_of(from_pos)
		if to_depth >= config.min_depth and from_depth >= config.min_depth:
			combined *= config.river_flow_factor
		elif from_depth >= config.min_depth:
			combined *= maxf(config.river_flow_factor, 0.32)

	return combined * _Pulse.spread_scale(from_pos, to_pos)


func _cliff_blocked(from: Vector2i, to: Vector2i) -> bool:
	if _prof_enabled:
		_prof_cliff_checks += 1
		_prof_terrain_height += 2
	var from_terrain: float = terrain.get_terrain_height(from)
	var to_terrain: float = terrain.get_terrain_height(to)
	if to_terrain <= from_terrain + config.cliff_height:
		return false
	var my_top: float = from_terrain + _depth_of(from)
	return my_top <= to_terrain + config.min_flow_diff


func _assign_spawn_on_flow(to: Vector2i, from: Vector2i) -> void:
	if spawn_id_by_cell.has(to):
		return
	if spawn_id_by_cell.has(from):
		spawn_id_by_cell[to] = spawn_id_by_cell[from]


func recalc_volume() -> Dictionary:
	return {"volume": _volume, "cells": depth.size()}


func ordered_keys() -> Array:
	if not _order_valid:
		_order = depth.keys()
		_order_valid = true
	return _order


func cell_seq(pos: Vector2i) -> int:
	_ensure_index()
	return int(_seq.get(pos, -1))


func _ensure_index() -> void:
	if _index_valid:
		return
	_seq.clear()
	_frontier.clear()
	_frontier_list.clear()
	_frontier_seq = PackedInt64Array()
	_interior.clear()
	_interior_seq = PackedInt64Array()
	_next_seq = 0
	for pos_variant in depth.keys():
		_seq[pos_variant] = _next_seq
		if _has_empty_neighbor_raw(pos_variant):
			_frontier[pos_variant] = true
			_frontier_list.append(pos_variant)
			_frontier_seq.append(_next_seq)
		else:
			_interior.append(pos_variant)
			_interior_seq.append(_next_seq)
		_next_seq += 1
	_index_valid = true


func _write_cell(pos: Vector2i, value: float) -> void:
	if depth.has(pos):
		_volume += value - float(depth[pos])
		depth[pos] = value
		if _soa_hot and _seq.has(pos):
			var sq_u: int = int(_seq[pos])
			if sq_u >= depth_soa.size():
				depth_soa.resize(sq_u + 1)
			depth_soa[sq_u] = value
		return
	depth[pos] = value
	_volume += value
	_chunk_cells_add(pos)
	if _order_valid:
		_order.append(pos)
	if not _index_valid:
		return
	_seq[pos] = _next_seq
	if _soa_hot:
		if _next_seq >= depth_soa.size():
			depth_soa.resize(_next_seq + 1)
		depth_soa[_next_seq] = value
	_next_seq += 1
	if _has_empty_neighbor_raw(pos):
		_frontier_add(pos)
	else:
		_interior_add(pos)
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = pos + dir
		if _frontier.has(n) and not _has_empty_neighbor_raw(n):
			_frontier_remove(n)
			_interior_add(n)


func _erase_cell(pos: Vector2i) -> void:
	if not depth.has(pos):
		return
	_volume -= float(depth[pos])
	depth.erase(pos)
	_chunk_cells_remove(pos)
	_order_valid = false
	_order = []
	if not _index_valid:
		return
	if _frontier.has(pos):
		_frontier_remove(pos)
	else:
		_interior_remove(pos)
	_seq.erase(pos)
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		var n: Vector2i = pos + dir
		if depth.has(n) and not _frontier.has(n):
			_interior_remove(n)
			_frontier_add(n)


func _has_empty_neighbor_raw(pos: Vector2i) -> bool:
	for dir in _CrystalTypes.NEIGHBOR_DIRS:
		if not depth.has(pos + dir):
			return true
	return false


func _interior_add(pos: Vector2i) -> void:
	var sq: int = int(_seq[pos])
	var i: int = _interior_seq.bsearch(sq)
	_interior.insert(i, pos)
	_interior_seq.insert(i, sq)


func _interior_remove(pos: Vector2i) -> void:
	if not _seq.has(pos):
		return
	var sq: int = int(_seq[pos])
	var i: int = _interior_seq.bsearch(sq)
	if i < _interior_seq.size() and _interior_seq[i] == sq:
		_interior.remove_at(i)
		_interior_seq.remove_at(i)


func _sorted_frontier() -> Array:
	return _frontier_list


func _frontier_add(pos: Vector2i) -> void:
	_frontier[pos] = true
	var sq: int = int(_seq[pos])
	var i: int = _frontier_seq.bsearch(sq)
	_frontier_list.insert(i, pos)
	_frontier_seq.insert(i, sq)


func _frontier_remove(pos: Vector2i) -> void:
	_frontier.erase(pos)
	var sq: int = int(_seq[pos])
	var i: int = _frontier_seq.bsearch(sq)
	if i < _frontier_seq.size() and _frontier_seq[i] == sq:
		_frontier_list.remove_at(i)
		_frontier_seq.remove_at(i)


func _chunk_cells_add(pos: Vector2i) -> void:
	var c := Vector2i(floori(float(pos.x) / float(_CHUNK)), floori(float(pos.y) / float(_CHUNK)))
	var bucket: Dictionary = _chunk_cells.get(c, {})
	if bucket.is_empty():
		_chunk_cells[c] = bucket
	bucket[pos] = true
	_chunk_cells_total += 1


func _chunk_cells_remove(pos: Vector2i) -> void:
	var c := Vector2i(floori(float(pos.x) / float(_CHUNK)), floori(float(pos.y) / float(_CHUNK)))
	var bucket: Dictionary = _chunk_cells.get(c, {})
	if bucket.erase(pos):
		_chunk_cells_total -= 1
		if bucket.is_empty():
			_chunk_cells.erase(c)


func _ensure_chunk_cells() -> void:
	if _chunk_cells_total != depth.size():
		_chunk_cells.clear()
		_chunk_cells_total = 0
		for pos_variant in depth.keys():
			_chunk_cells_add(pos_variant)


func chunks_in_rect(bounds: Rect2i) -> Array:
	_ensure_chunk_cells()
	var out: Array = []
	var x0: int = bounds.position.x
	var y0: int = bounds.position.y
	var x1: int = x0 + bounds.size.x
	var y1: int = y0 + bounds.size.y
	if x1 <= x0 or y1 <= y0:
		return out
	for cy in range(floori(float(y0) / float(_CHUNK)), floori(float(y1 - 1) / float(_CHUNK)) + 1):
		for cx in range(floori(float(x0) / float(_CHUNK)), floori(float(x1 - 1) / float(_CHUNK)) + 1):
			var c := Vector2i(cx, cy)
			if _chunk_cells.has(c):
				out.append(c)
	return out


func chunk_cells(chunk: Vector2i) -> Dictionary:
	return _chunk_cells.get(chunk, {})


func cells_in_rect(bounds: Rect2i) -> Array:
	_ensure_chunk_cells()
	var out: Array = []
	var x0: int = bounds.position.x
	var y0: int = bounds.position.y
	var x1: int = x0 + bounds.size.x
	var y1: int = y0 + bounds.size.y
	if x1 <= x0 or y1 <= y0:
		return out
	var cx0: int = floori(float(x0) / float(_CHUNK))
	var cy0: int = floori(float(y0) / float(_CHUNK))
	var cx1: int = floori(float(x1 - 1) / float(_CHUNK))
	var cy1: int = floori(float(y1 - 1) / float(_CHUNK))
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var bucket = _chunk_cells.get(Vector2i(cx, cy))
			if bucket == null:
				continue
			var edge: bool = cx * _CHUNK < x0 or cy * _CHUNK < y0 or (cx + 1) * _CHUNK > x1 or (cy + 1) * _CHUNK > y1
			for pos_variant in bucket:
				if edge:
					var p: Vector2i = pos_variant
					if p.x < x0 or p.y < y0 or p.x >= x1 or p.y >= y1:
						continue
				out.append(pos_variant)
	return out


func _select_indexed_flow_cells(cap: int) -> Array:
	_ensure_index()
	_gate_memo.clear()
	var subset: Array = _select_indexed_flow_cells_scoped(cap)
	_gate_memo.clear()
	return subset


func _gated_cell_active(pos: Vector2i) -> bool:
	if chunk_gate.is_valid():
		var ck := Vector2i(floori(float(pos.x) / float(chunk_gate_size)), floori(float(pos.y) / float(chunk_gate_size)))
		var open = _gate_memo.get(ck)
		if open == null:
			open = bool(chunk_gate.call(ck))
			_gate_memo[ck] = open
		if not open:
			return false
	return _cell_active(pos)


func _select_indexed_flow_cells_scoped(cap: int) -> Array:
	var subset: Array = []
	var gated := chunk_gate.is_valid() and chunk_gate_size == 16
	var last_ck := Vector2i(2147483647, 2147483647)
	var last_open := true
	for pos_variant in _sorted_frontier():
		if subset.size() >= cap:
			break
		if gated:
			var p: Vector2i = pos_variant
			var ck := Vector2i(p.x >> 4, p.y >> 4)
			if ck != last_ck:
				last_ck = ck
				var open = _gate_memo.get(ck)
				if open == null:
					open = bool(chunk_gate.call(ck))
					_gate_memo[ck] = open
				last_open = open
			if not last_open:
				continue
			if _cell_active(p):
				subset.append(p)
		elif _gated_cell_active(pos_variant):
			subset.append(pos_variant)
	var n: int = _interior.size()
	if subset.size() < cap and n > 0:
		var start: int = _interior_flow_offset % n
		_interior_flow_offset += maxi(cap - subset.size(), 1)
		var walked: int = 0
		var limit: int = mini(n, _INTERIOR_WALK_MAX)
		while subset.size() < cap and walked < limit:
			var pos: Vector2i = _interior[(start + walked) % n]
			walked += 1
			if _gated_cell_active(pos):
				subset.append(pos)
	return subset