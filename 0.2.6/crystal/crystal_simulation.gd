class_name CrystalSimulation
extends RefCounted
## Pure crystal state update. No scene-tree access.
## Consumes CrystalSimSnapshot; emits typed CrystalSimEvents dictionaries only.

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalSimEvents = preload("res://crystal/crystal_sim_events.gd")
const _CrystalSimSnapshot = preload("res://crystal/crystal_sim_snapshot.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PlantableDef = preload("res://config/plantable_def.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

var config: _CrystalSimConfig
var fluid: _CrystalFluidSim
var absorption: Dictionary = {}  # Vector2i -> progress
var ruin_absorption: Dictionary = {}
var absorbed_ruin_centers: Dictionary = {}
var last_events: Array = []
var last_new_cells: int = 0
var last_mesh_dirty_count: int = 0
var event_count: int = 0
var tick_count: int = 0
## False when flow is mid-budget resume; façade should call tick again next frame.
var last_tick_complete: bool = true
## Soft wall for fluid.tick_flow cell processing (0 = unlimited).
var flow_budget_us: int = 0
## Last tick breakdown (us) when CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE is on.
var last_tick_breakdown: Dictionary = {}
## Snapshot held while a budgeted flow job is in progress.
var _pending_snapshot = null
var _pending_sub_delta: float = 0.0
var _pending_substep_i: int = 0
var _pending_substeps: int = 1
var _pending_all_changed: Array = []
var _pending_all_mesh: Array = []
var _pending_emitters_done: bool = false


func _init(p_config: _CrystalSimConfig = null, p_terrain = null) -> void:
	config = p_config if p_config else _CrystalSimConfig.create_default()
	fluid = _CrystalFluidSim.new(config, p_terrain)


func bind_terrain(terrain) -> void:
	if fluid:
		fluid.terrain = terrain


func set_config(cfg: _CrystalSimConfig) -> void:
	if cfg == null:
		return
	config = cfg
	if fluid:
		fluid.config = cfg


func clear() -> void:
	if fluid:
		fluid.clear()
	absorption.clear()
	ruin_absorption.clear()
	absorbed_ruin_centers.clear()
	last_events.clear()
	last_new_cells = 0
	last_mesh_dirty_count = 0
	last_tick_complete = true
	_clear_pending_tick()


func has_pending_tick() -> bool:
	return _pending_snapshot != null or (fluid != null and fluid.has_pending_flow())


func _clear_pending_tick() -> void:
	_pending_snapshot = null
	_pending_sub_delta = 0.0
	_pending_substep_i = 0
	_pending_substeps = 1
	_pending_all_changed.clear()
	_pending_all_mesh.clear()
	_pending_emitters_done = false


func get_depth_at(wx: int, wz: int) -> float:
	return fluid.get_depth_at(wx, wz) if fluid else 0.0


func has_crystal_at(wx: int, wz: int) -> bool:
	return fluid.has_crystal_at(wx, wz) if fluid else false


func set_depth(pos: Vector2i, depth: float, spawn_id: int = -1, emit: bool = true) -> Array:
	if fluid == null:
		return []
	var before_keys: int = fluid.depth.size()
	fluid.set_depth(pos, depth, spawn_id, false)
	var events: Array = []
	if emit:
		if fluid.depth.has(pos):
			events.append(_CrystalSimEvents.depth_changed(pos))
			events.append(_CrystalSimEvents.mesh_dirty([pos]))
		elif before_keys != fluid.depth.size() or not fluid.depth.has(pos):
			events.append(_CrystalSimEvents.depth_cleared(pos))
			events.append(_CrystalSimEvents.mesh_dirty([pos]))
	event_count += events.size()
	return events


## Primary tick entry: snapshot in → events out. No get_tree / Node access.
## When flow_budget_us > 0, may return [] with last_tick_complete=false until the
## logical tick finishes (same final state as a single unbounded tick).
func tick(snapshot) -> Array:
	last_events.clear()
	last_tick_breakdown = {}
	last_tick_complete = true
	if fluid == null:
		return last_events
	# Resume path: snapshot may be null; use pending.
	var resuming := has_pending_tick()
	if resuming:
		snapshot = _pending_snapshot
	if snapshot == null:
		return last_events

	var measure := _measure_enabled()
	if snapshot.terrain:
		fluid.terrain = snapshot.terrain
		if snapshot.terrain.has_method("begin_sim_tick"):
			snapshot.terrain.begin_sim_tick(snapshot.tick_id)
	fluid.is_cell_active = Callable(snapshot, "is_cell_active")
	fluid.global_flow_mult = snapshot.global_flow_mult
	fluid.flow_budget_us = flow_budget_us

	if not resuming:
		tick_count += 1
		_pending_snapshot = snapshot
		_pending_substeps = maxi(snapshot.flow_substeps, 1)
		_pending_sub_delta = snapshot.delta / float(_pending_substeps)
		_pending_substep_i = 0
		_pending_all_changed.clear()
		_pending_all_mesh.clear()
		_pending_emitters_done = false

	# Emitters once at start of logical tick.
	var t0 := Time.get_ticks_usec() if measure else 0
	if not _pending_emitters_done:
		_tick_emitters_from_snapshot(snapshot)
		_pending_emitters_done = true
		if measure:
			last_tick_breakdown["emitters_us"] = Time.get_ticks_usec() - t0

	var flow_us := 0
	var active_acc := 0
	var selected_acc := 0
	t0 = Time.get_ticks_usec() if measure else 0
	while _pending_substep_i < _pending_substeps:
		var changed: Array = fluid.tick_flow(_pending_sub_delta)
		if measure and fluid.has_method("get_last_flow_scan_stats"):
			var st: Dictionary = fluid.get_last_flow_scan_stats()
			active_acc += int(st.get("active_cells", 0))
			selected_acc += int(st.get("selected_cells", 0))
		if not fluid.last_flow_complete:
			if measure:
				last_tick_breakdown["flow_us"] = Time.get_ticks_usec() - t0
				last_tick_breakdown["active_cells"] = active_acc
				last_tick_breakdown["selected_cells"] = selected_acc
				last_tick_breakdown["flow_substeps"] = _pending_substeps
				last_tick_breakdown["budget_partial"] = 1
			last_tick_complete = false
			return last_events
		var mesh_dirty: Array = fluid.get_last_mesh_dirty() if fluid.has_method("get_last_mesh_dirty") else changed
		for p in changed:
			if p not in _pending_all_changed:
				_pending_all_changed.append(p)
		for p in mesh_dirty:
			if p not in _pending_all_mesh:
				_pending_all_mesh.append(p)
		_pending_substep_i += 1
	if measure:
		flow_us = Time.get_ticks_usec() - t0
		last_tick_breakdown["flow_us"] = flow_us
		last_tick_breakdown["active_cells"] = active_acc
		last_tick_breakdown["selected_cells"] = selected_acc
		last_tick_breakdown["flow_substeps"] = _pending_substeps

	var all_changed: Array = _pending_all_changed
	var all_mesh: Array = _pending_all_mesh
	last_new_cells = fluid.last_new_cells
	last_mesh_dirty_count = all_mesh.size()
	if not all_changed.is_empty():
		last_events.append(_CrystalSimEvents.flow_batch(all_changed, all_mesh, last_new_cells))

	# Absorption progress (side-effect-free); completion as events for façade.
	t0 = Time.get_ticks_usec() if measure else 0
	_tick_absorption_progress(snapshot)
	if measure:
		last_tick_breakdown["absorption_us"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec() if measure else 0
	_tick_animal_absorption_progress(snapshot)
	if measure:
		last_tick_breakdown["animal_us"] = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec() if measure else 0
	_tick_ruin_absorption_progress(snapshot)
	if measure:
		last_tick_breakdown["ruin_us"] = Time.get_ticks_usec() - t0

	if fluid:
		t0 = Time.get_ticks_usec() if measure else 0
		var stats: Dictionary = fluid.recalc_volume()
		if measure:
			last_tick_breakdown["stats_us"] = Time.get_ticks_usec() - t0
		last_events.append(_CrystalSimEvents.stats(
			float(stats.get("volume", 0.0)),
			int(stats.get("cells", 0))
		))

	event_count += last_events.size()
	_clear_pending_tick()
	last_tick_complete = true
	return last_events


func _measure_enabled() -> bool:
	var raw := OS.get_environment("CRYSTALSTORM_CRYSTAL_STARTUP_MEASURE").strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "on"


func consume_last_tick_breakdown() -> Dictionary:
	var d: Dictionary = last_tick_breakdown.duplicate()
	last_tick_breakdown = {}
	return d


func _tick_emitters_from_snapshot(snapshot) -> void:
	var mult: float = maxf(snapshot.emit_weaken_mult, 0.05)
	# Mirror fluid.tick_emitters but from plain dict rows.
	var rows: Array = snapshot.spawn_emitters
	if rows.is_empty():
		return
	# Prefer fluid path when rows look like spawn objects.
	var as_objects: Array = []
	var use_objects := true
	for row in rows:
		if row is Object and "world_pos" in row and "emit_rate" in row:
			as_objects.append(row)
		else:
			use_objects = false
			break
	if use_objects and not as_objects.is_empty():
		fluid.tick_emitters(as_objects, snapshot.delta, snapshot.emit_weaken_mult)
		return
	for row_v in rows:
		if not row_v is Dictionary:
			continue
		var row: Dictionary = row_v
		if not bool(row.get("active", true)):
			continue
		var pos: Vector2i = row.get("world_pos", Vector2i.ZERO)
		if not snapshot.is_cell_active(pos):
			continue
		var emit_rate: float = float(row.get("emit_rate", 0.0))
		var spawn_id: int = int(row.get("id", -1))
		var current: float = float(fluid.depth.get(pos, 0.0))
		var added: float = emit_rate * mult * snapshot.delta
		var room: float = config.max_depth - current
		if room <= 0.0 or added <= 0.0:
			continue
		fluid.set_depth(pos, current + minf(added, room), spawn_id, false)


func _tick_absorption_progress(snapshot) -> void:
	if fluid == null or fluid.depth.is_empty():
		return
	var cells: Array = fluid.depth.keys()
	if cells.is_empty():
		return
	var scanned := 0
	var start: int = snapshot.absorption_scan_offset % cells.size()
	var budget: int = maxi(snapshot.absorption_scan_cells, 8)
	while scanned < budget and scanned < cells.size():
		var pos: Vector2i = cells[(start + scanned) % cells.size()]
		scanned += 1
		if not snapshot.is_cell_active(pos):
			continue
		var depth: float = float(fluid.depth.get(pos, 0.0))
		if depth < snapshot.min_depth:
			continue
		var tile_id: int = snapshot.get_tile(pos)
		if not _is_absorbable_tile(tile_id):
			continue
		var rate: float = _absorption_rate_for(snapshot, pos, tile_id)
		var progress: float = float(absorption.get(pos, 0.0)) + snapshot.delta * rate * depth
		if progress >= 1.0:
			absorption.erase(pos)
			var feat: Dictionary = snapshot.get_feature(pos.x, pos.y)
			last_events.append(_CrystalSimEvents.absorption_ready(pos, tile_id, feat))
		else:
			absorption[pos] = progress


func _tick_animal_absorption_progress(snapshot) -> void:
	if fluid == null or fluid.depth.is_empty():
		return
	var cells: Array = fluid.depth.keys()
	var scanned := 0
	var start: int = snapshot.absorption_scan_offset % maxi(cells.size(), 1)
	var budget: int = maxi(snapshot.absorption_scan_cells, 8)
	while scanned < budget and scanned < cells.size():
		var pos: Vector2i = cells[(start + scanned) % cells.size()]
		scanned += 1
		if not snapshot.is_cell_active(pos):
			continue
		if float(fluid.depth.get(pos, 0.0)) < snapshot.min_depth:
			continue
		var feat: Dictionary = snapshot.get_feature(pos.x, pos.y)
		if not feat.has("kind") or int(feat.kind) != _WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN:
			continue
		var progress: float = float(absorption.get(pos, 0.0)) + snapshot.delta * 0.25
		if progress >= 1.0:
			absorption.erase(pos)
			last_events.append(_CrystalSimEvents.absorption_ready(pos, snapshot.get_tile(pos), feat))
		else:
			absorption[pos] = progress


func _tick_ruin_absorption_progress(snapshot) -> void:
	if fluid == null:
		return
	for center_v in snapshot.ruin_centers:
		var center: Vector2i = center_v
		if absorbed_ruin_centers.has(center):
			continue
		if not snapshot.is_cell_active(center):
			continue
		if float(fluid.depth.get(center, 0.0)) < snapshot.min_depth:
			continue
		var progress: float = float(ruin_absorption.get(center, 0.0)) + snapshot.delta * 0.12
		if progress >= 1.0:
			absorbed_ruin_centers[center] = true
			ruin_absorption.erase(center)
			last_events.append(_CrystalSimEvents.ruin_absorption_ready(center))
		else:
			ruin_absorption[center] = progress


func _is_absorbable_tile(tile_id: int) -> bool:
	return tile_id in [
		_VoxelTypes.GRASS_TUFT,
		_VoxelTypes.BUSH,
		_VoxelTypes.TREE_TRUNK,
		_VoxelTypes.FARMLAND,
	]


func _absorption_rate_for(snapshot, pos: Vector2i, tile_id: int) -> float:
	var feat: Dictionary = snapshot.get_feature(pos.x, pos.y)
	if feat.has("plant_id"):
		var def = _PlantableRegistry.get_def(StringName(str(feat.plant_id))) as _PlantableDef
		if def:
			var stage: int = int(feat.get("growth_stage", def.mature_stage()))
			return def.absorb_rate_for_stage(stage)
	match tile_id:
		_VoxelTypes.GRASS_TUFT:
			return snapshot.grass_absorb_rate
		_VoxelTypes.BUSH:
			return snapshot.bush_absorb_rate
		_VoxelTypes.TREE_TRUNK:
			return snapshot.tree_absorb_rate
		_VoxelTypes.FARMLAND:
			return snapshot.farmland_absorb_rate
		_:
			return 0.08


func export_depth_rows() -> Array:
	var depth_rows: Array = []
	if fluid == null:
		return depth_rows
	for pos_variant in fluid.depth.keys():
		var pos: Vector2i = pos_variant
		depth_rows.append([
			pos.x, pos.y,
			float(fluid.depth[pos]),
			int(fluid.spawn_id_by_cell.get(pos, -1)),
		])
	return depth_rows


func import_depth_rows(rows: Array) -> void:
	if fluid == null:
		return
	fluid.clear()
	for row in rows:
		if row is Array and row.size() >= 3:
			var pos := Vector2i(int(row[0]), int(row[1]))
			var spawn_id: int = int(row[3]) if row.size() >= 4 else -1
			fluid.set_depth(pos, float(row[2]), spawn_id, false)


func diagnostics() -> Dictionary:
	return {
		"tick_count": tick_count,
		"event_count": event_count,
		"last_new_cells": last_new_cells,
		"last_mesh_dirty": last_mesh_dirty_count,
		"cell_count": fluid.cell_count() if fluid else 0,
		"absorption_entries": absorption.size(),
	}
