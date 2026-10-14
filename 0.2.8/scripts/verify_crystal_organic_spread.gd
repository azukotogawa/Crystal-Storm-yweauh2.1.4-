extends SceneTree
## Crystal growth fills as one connected pool, like water, instead of a checkerboard.
## Usage: godot --headless -s scripts/verify_crystal_organic_spread.gd

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")


func _init() -> void:
	var failed := false
	_TerrainEdits.reset()

	var scr: GDScript = load("res://crystal/crystal_fluid_sim.gd") as GDScript
	if scr == null or scr.reload() != OK:
		push_error("FAIL crystal_fluid_sim compile")
		quit(1)
		return

	var stats := _spread_blob(4, 40, 7)
	if stats.grew < 12:
		push_error("organic spread too small grew=%d cells=%d" % [stats.grew, stats.cells])
		failed = true
	elif stats.isolated > 0:
		push_error("checkerboard isolates=%d cells=%d" % [stats.isolated, stats.cells])
		failed = true
	elif stats.component != stats.cells:
		push_error("spread is not one pool component=%d cells=%d" % [stats.component, stats.cells])
		failed = true
	elif stats.holes > 0:
		push_error("notch left unfilled holes=%d cells=%d" % [stats.holes, stats.cells])
		failed = true
	elif stats.minority * 2 < stats.majority:
		push_error(
			"parity split minority=%d majority=%d (checkerboard)"
			% [stats.minority, stats.majority]
		)
		failed = true
	elif not stats.seed_kept:
		push_error("flow erased a seed cell")
		failed = true
	elif stats.spawn_miss > 0:
		push_error("spawn id did not follow the pool miss=%d" % stats.spawn_miss)
		failed = true
	elif stats.over_cap > 0:
		push_error("new cells exceeded cap ticks=%d" % stats.over_cap)
		failed = true
	else:
		print(
			"OK organic pool cells=%d holes=%d even=%d odd=%d"
			% [stats.cells, stats.holes, stats.even, stats.odd]
		)

	var again := _spread_blob(4, 40, 7)
	if again.cells != stats.cells or absf(again.volume - stats.volume) > 0.001:
		push_error(
			"organic spread diverged cells %d/%d volume %.3f/%.3f"
			% [stats.cells, again.cells, stats.volume, again.volume]
		)
		failed = true
	else:
		print("OK organic spread is stable across runs")

	if failed:
		quit(1)
	print("All crystal organic spread tests OK")
	quit(0)


func _spread_blob(cap: int, ticks: int, spawn_id: int) -> Dictionary:
	var cfg := _CrystalSimConfig.create_default()
	var terrain := _CrystalTerrainQuery.new()
	var sim := _CrystalFluidSim.new(cfg, terrain)
	sim.max_new_cells_per_tick = cap
	sim.empty_cell_inflow_cap = 0.10
	var origin := Vector2i(20, 20)
	var seed: Array = []
	for x in 3:
		for z in 3:
			var pos := Vector2i(origin.x + x, origin.y + z)
			seed.append(pos)
			sim.set_depth(pos, cfg.initial_spawn_depth, spawn_id, false)
	var before: int = sim.cell_count()
	var over_cap := 0
	for _t in ticks:
		sim.tick_flow(0.2)
		if sim.last_new_cells > cap:
			over_cap += 1
	return _measure(sim, seed, before, spawn_id, over_cap)


func _measure(sim, seed: Array, before: int, spawn_id: int, over_cap: int) -> Dictionary:
	var min_d: float = sim.config.min_depth
	var even := 0
	var odd := 0
	var isolated := 0
	var spawn_miss := 0
	var volume := 0.0
	var min_x := 100000
	var max_x := -100000
	var min_z := 100000
	var max_z := -100000
	for key_variant in sim.depth.keys():
		var pos: Vector2i = key_variant
		var d: float = float(sim.depth[pos])
		if d < min_d:
			continue
		volume += d
		if (pos.x + pos.y) % 2 == 0:
			even += 1
		else:
			odd += 1
		var touches := 0
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = pos + dir
			if float(sim.depth.get(n, 0.0)) >= min_d:
				touches += 1
		if touches == 0:
			isolated += 1
		if int(sim.spawn_id_by_cell.get(pos, -1)) != spawn_id:
			spawn_miss += 1
		min_x = mini(min_x, pos.x)
		max_x = maxi(max_x, pos.x)
		min_z = mini(min_z, pos.y)
		max_z = maxi(max_z, pos.y)
	var holes := 0
	if min_x < 100000:
		for x in range(min_x - 1, max_x + 2):
			for z in range(min_z - 1, max_z + 2):
				var pos := Vector2i(x, z)
				if float(sim.depth.get(pos, 0.0)) >= min_d:
					continue
				var filled_neighbors := 0
				for dir in _CrystalTypes.NEIGHBOR_DIRS:
					var n: Vector2i = pos + dir
					if float(sim.depth.get(n, 0.0)) >= min_d:
						filled_neighbors += 1
				if filled_neighbors >= 3:
					holes += 1
	var seed_kept := true
	for pos_variant in seed:
		var pos: Vector2i = pos_variant
		if float(sim.depth.get(pos, 0.0)) < min_d:
			seed_kept = false
			break
	var start: Vector2i = seed[0]
	var component := _component_size(sim, start, min_d)
	var cells: int = even + odd
	return {
		"cells": cells,
		"grew": cells - before,
		"holes": holes,
		"isolated": isolated,
		"component": component,
		"even": even,
		"odd": odd,
		"minority": mini(even, odd),
		"majority": maxi(even, odd),
		"seed_kept": seed_kept,
		"spawn_miss": spawn_miss,
		"over_cap": over_cap,
		"volume": volume,
	}


func _component_size(sim, start: Vector2i, min_d: float) -> int:
	if float(sim.depth.get(start, 0.0)) < min_d:
		return 0
	var seen := {}
	var q: Array = [start]
	seen[start] = true
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		for dir in _CrystalTypes.NEIGHBOR_DIRS:
			var n: Vector2i = cur + dir
			if seen.has(n):
				continue
			if float(sim.depth.get(n, 0.0)) < min_d:
				continue
			seen[n] = true
			q.append(n)
	return seen.size()
