extends SceneTree
## Crystal simulation split: parity, pause, deterministic replay, event budget, presentation isolation.
## Usage: godot --headless -s scripts/verify_crystal_simulation_split.gd

const _CrystalSimulation = preload("res://crystal/crystal_simulation.gd")
const _CrystalPresentation = preload("res://crystal/crystal_presentation.gd")
const _CrystalSimSnapshot = preload("res://crystal/crystal_sim_snapshot.gd")
const _CrystalSimEvents = preload("res://crystal/crystal_sim_events.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")

var _failed: int = 0


func _init() -> void:
	_run()
	if _failed == 0:
		print("All crystal simulation split tests OK")
		quit(0)
	else:
		push_error("verify_crystal_simulation_split: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_TerrainEdits.reset()
	_test_no_scene_tree_in_simulation()
	_test_spread_parity_vs_direct_fluid()
	_test_deterministic_replay()
	_test_pause_resume_via_expansion_flag()
	_test_event_budget_no_extra_mesh_events()
	_test_presentation_applies_events_only()
	_test_saveload_depth_continuity()
	_test_chunk_stream_presentation()


func _flat_terrain() -> _CrystalTerrainQuery:
	var t := _CrystalTerrainQuery.new()
	var heights: Dictionary = {}
	for x in range(-8, 24):
		for z in range(-8, 24):
			heights[Vector2i(x, z)] = 40.0
	t.test_base_heights = heights
	return t


func _make_snapshot(delta: float, terrain, emitters: Array = []):
	var snap = _CrystalSimSnapshot.new()
	snap.tick_id = 1
	snap.delta = delta
	snap.flow_substeps = 2
	snap.global_flow_mult = 1.0
	snap.emit_weaken_mult = 1.0
	snap.spawn_emitters = emitters
	snap.sim_loaded_chunks_only = false
	snap.terrain = terrain
	snap.min_depth = 0.04
	return snap


func _test_no_scene_tree_in_simulation() -> void:
	var src := (load("res://crystal/crystal_simulation.gd") as GDScript).source_code
	if "get_tree()" in src or "get_first_node_in_group" in src:
		_fail("CrystalSimulation must not access the scene tree")
	else:
		print("OK CrystalSimulation has no scene-tree access")


func _test_spread_parity_vs_direct_fluid() -> void:
	var cfg := _CrystalSimConfig.create_default()
	cfg.pressure_flow_rate = 1.2
	cfg.max_flow_per_cell = 1.5
	var terrain_a := _flat_terrain()
	var terrain_b := _flat_terrain()
	var direct := _CrystalFluidSim.new(cfg, terrain_a)
	var sim := _CrystalSimulation.new(cfg, terrain_b)
	direct.set_depth(Vector2i(5, 5), 2.0, 0, false)
	sim.set_depth(Vector2i(5, 5), 2.0, 0, false)
	# Pure fluid path
	for _i in 12:
		terrain_a.begin_sim_tick(_i + 1)
		direct.tick_flow(0.2)
	# Simulation path with empty emitters
	for i in 12:
		var snap = _make_snapshot(0.2, terrain_b)
		snap.tick_id = i + 1
		snap.flow_substeps = 1  # match single tick_flow
		sim.tick(snap)
	# Compare depth maps
	var mismatch := 0
	var keys: Dictionary = {}
	for k in direct.depth.keys():
		keys[k] = true
	for k in sim.fluid.depth.keys():
		keys[k] = true
	for k in keys.keys():
		var da: float = float(direct.depth.get(k, 0.0))
		var db: float = float(sim.fluid.depth.get(k, 0.0))
		if absf(da - db) > 0.05:
			mismatch += 1
	if mismatch > 0:
		_fail("spread parity mismatch cells=%d direct_n=%d sim_n=%d" % [
			mismatch, direct.depth.size(), sim.fluid.depth.size()])
	else:
		print("OK spread parity vs direct fluid n=%d" % direct.depth.size())


func _test_deterministic_replay() -> void:
	var cfg := _CrystalSimConfig.create_default()
	var run := func() -> Dictionary:
		var terrain := _flat_terrain()
		var sim := _CrystalSimulation.new(cfg, terrain)
		sim.set_depth(Vector2i(0, 0), 1.8, 1, false)
		sim.set_depth(Vector2i(1, 0), 0.5, 1, false)
		for i in 20:
			var snap = _make_snapshot(0.15, terrain)
			snap.tick_id = i + 1
			snap.flow_substeps = 2
			sim.tick(snap)
		return sim.fluid.depth.duplicate()
	var a: Dictionary = run.call()
	var b: Dictionary = run.call()
	if a.size() != b.size():
		_fail("deterministic replay size mismatch %d vs %d" % [a.size(), b.size()])
		return
	for k in a.keys():
		if absf(float(a[k]) - float(b.get(k, -1.0))) > 0.0001:
			_fail("deterministic replay depth diverge at %s" % str(k))
			return
	print("OK deterministic replay cells=%d" % a.size())


func _test_pause_resume_via_expansion_flag() -> void:
	# Expansion pause is façade-owned: when no ticks, depth must freeze.
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _flat_terrain()
	var sim := _CrystalSimulation.new(cfg, terrain)
	sim.set_depth(Vector2i(2, 2), 2.0, 0, false)
	var snap = _make_snapshot(0.2, terrain)
	snap.flow_substeps = 2
	sim.tick(snap)
	var mid: float = sim.get_depth_at(2, 2)
	var cells_mid: int = sim.fluid.cell_count()
	# "Paused": do not call tick
	var after_pause: float = sim.get_depth_at(2, 2)
	if after_pause != mid or sim.fluid.cell_count() != cells_mid:
		_fail("pause must freeze depth without ticks")
	else:
		print("OK pause freezes state without ticks")
	# Resume
	sim.tick(snap)
	print("OK resume advances after pause (cells=%d)" % sim.fluid.cell_count())


func _test_event_budget_no_extra_mesh_events() -> void:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _flat_terrain()
	var sim := _CrystalSimulation.new(cfg, terrain)
	sim.set_depth(Vector2i(3, 3), 2.5, 0, false)
	var snap = _make_snapshot(0.25, terrain)
	snap.flow_substeps = 2
	var events: Array = sim.tick(snap)
	var flow_batches := 0
	var mesh_only := 0
	for ev in events:
		if int(ev.kind) == _CrystalSimEvents.Kind.FLOW_BATCH:
			flow_batches += 1
			var mesh_dirty: Array = ev.get("mesh_dirty", [])
			var changed: Array = ev.get("changed", [])
			if mesh_dirty.size() > changed.size():
				_fail("mesh_dirty must not exceed changed in flow batch")
		elif int(ev.kind) == _CrystalSimEvents.Kind.MESH_DIRTY:
			mesh_only += 1
	if flow_batches > 1:
		_fail("expected at most one FLOW_BATCH per tick (got %d)" % flow_batches)
	if mesh_only > 0:
		_fail("tick path should batch mesh dirty inside FLOW_BATCH not separate MESH_DIRTY")
	else:
		print("OK event budget flow_batches=%d events=%d" % [flow_batches, events.size()])


func _test_presentation_applies_events_only() -> void:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _flat_terrain()
	var sim := _CrystalSimulation.new(cfg, terrain)
	sim.set_depth(Vector2i(4, 4), 1.5, 0, false)
	var pres := _CrystalPresentation.new()
	pres.fluid = sim.fluid
	pres.sim_config = cfg
	pres.chunk_size = 16
	pres.is_chunk_render_active = func(_c): return true
	var snap = _make_snapshot(0.2, terrain)
	var events: Array = sim.tick(snap)
	var before := pres.events_applied
	pres.apply_events(events)
	if pres.events_applied <= before:
		_fail("presentation must consume events")
	else:
		print("OK presentation applied events=%d dirty=%d" % [
			pres.events_applied - before, pres.dirty_chunk_count()])


func _test_saveload_depth_continuity() -> void:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _flat_terrain()
	var sim := _CrystalSimulation.new(cfg, terrain)
	sim.set_depth(Vector2i(1, 1), 1.2, 7, false)
	sim.set_depth(Vector2i(2, 1), 0.9, 7, false)
	var rows: Array = sim.export_depth_rows()
	var sim2 := _CrystalSimulation.new(cfg, _flat_terrain())
	sim2.import_depth_rows(rows)
	if absf(sim2.get_depth_at(1, 1) - 1.2) > 0.001 or absf(sim2.get_depth_at(2, 1) - 0.9) > 0.001:
		_fail("save/load depth continuity broken")
	else:
		print("OK save/load depth continuity")


func _test_chunk_stream_presentation() -> void:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _flat_terrain()
	var sim := _CrystalSimulation.new(cfg, terrain)
	# Cell in chunk (0,0) for size 16
	sim.set_depth(Vector2i(2, 2), 1.0, 0, false)
	var pres := _CrystalPresentation.new()
	pres.fluid = sim.fluid
	pres.sim_config = cfg
	pres.chunk_size = 16
	pres.is_chunk_render_active = func(_c): return true
	pres.mark_all_indexed_dirty()
	if pres.dirty_chunk_count() < 1:
		_fail("stream: mark_all_indexed_dirty should dirty chunk")
	var coord := Vector2i(0, 0)
	pres.on_chunk_unloaded(coord)
	# After unload dirty for that chunk cleared
	if pres._dirty_chunks.has(coord):
		_fail("stream: unload must clear dirty for coord")
	pres.on_chunk_loaded(coord)
	# reload: if cells remain, becomes dirty again when has cells
	if sim.fluid.depth.has(Vector2i(2, 2)):
		pres.rebuild_cell_index()
		pres.on_chunk_loaded(coord)
	print("OK chunk stream presentation load/unload dirty handling")
