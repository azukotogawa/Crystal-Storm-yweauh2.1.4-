extends Node
## Release crystal-stress fps probe. Env: CS_SEED, CS_STRESS_CELLS (800), CS_STRESS_SEC (8), CS_WARM_SEC (3).

const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Worlds = preload("res://systems/world_manager.gd")

func _init() -> void:
	if OS.get_environment("CS_SEED") != "":
		_Worlds.start_fresh_run(int(OS.get_environment("CS_SEED")))
	else:
		_Worlds.start_fresh_run(77123)

func _ready() -> void:
	call_deferred("_run")

func _envf(k: String, d: float) -> float:
	var r := OS.get_environment(k)
	return float(r) if r.is_valid_float() else d

func _envi(k: String, d: int) -> int:
	var r := OS.get_environment(k)
	return int(r) if r.is_valid_int() else d

func _run() -> void:
	print("CSTRESS start")
	var compose = null
	var frames := 0
	while frames < 200000:
		await get_tree().process_frame
		frames += 1
		if compose == null:
			compose = get_tree().get_first_node_in_group("composition_root")
		var st := int(compose.stage) if compose != null else -1
		if st >= 9:
			_ProbeExit.finish_tree(get_tree(), 1, "CSTRESS FAIL stage=failed")
			return
		if st >= 5:
			var gi = load("res://helpers/gameplay_input.gd")
			if gi != null and gi.has_method("blocks_actions") and not gi.blocks_actions():
				break
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal == null:
		_ProbeExit.finish_tree(get_tree(), 1, "CSTRESS FAIL no crystal")
		return
	print("CSTRESS playable_ms=%d" % Time.get_ticks_msec())
	if "expansion_enabled" in crystal:
		crystal.expansion_enabled = true
	if "_stream_pause_frames" in crystal:
		crystal._stream_pause_frames = 0
	if "_expansion_soft_ticks_left" in crystal:
		crystal._expansion_soft_ticks_left = 0
	var fluid = _find_fluid(crystal)
	print("CSTRESS fluid=%s covered=%s" % [str(fluid != null), str(crystal.get("covered_cells") if "covered_cells" in crystal else -1)])
	# Uncapped sim cost (matches profile_crystal_sim_only) so we measure the
	# real data-oriented target, not the perf budget that already caps work.
	if fluid != null:
		fluid.flow_budget_us = 0
		if "max_cells_per_tick" in fluid:
			fluid.max_cells_per_tick = 0
	if "_simulation" in crystal and crystal._simulation != null:
		crystal._simulation.flow_budget_us = 0
	if "_perf_flow_budget_us" in crystal:
		crystal._perf_flow_budget_us = 0
	print("CSTRESS budgets_zeroed=1")
	await _sample("WARM", _envf("CS_WARM_SEC", 3.0), crystal, fluid)
	var n: int = _envi("CS_STRESS_CELLS", 800)
	_seed(fluid, n)
	if fluid != null and "covered_cells" in crystal and "depth" in fluid:
		crystal.covered_cells = int(fluid.depth.size())
	var depth_after: int = -1
	if fluid != null and "depth" in fluid:
		depth_after = int(fluid.depth.size())
	print("CSTRESS seeded n=%d depth_size=%d" % [n, depth_after])
	await _sample("STRESS", _envf("CS_STRESS_SEC", 8.0), crystal, fluid)
	_ProbeExit.finish_tree(get_tree(), 0, "CSTRESS DONE total_ms=%d" % Time.get_ticks_msec())

func _find_fluid(crystal):
	if crystal == null:
		return null
	if "_simulation" in crystal and crystal._simulation != null:
		var sim = crystal._simulation
		if "fluid" in sim:
			return sim.fluid
		if "_fluid" in sim:
			return sim._fluid
		if sim.has_method("get_fluid"):
			return sim.get_fluid()
	for k in ["_fluid", "fluid", "_sim"]:
		if k in crystal and crystal.get(k) != null:
			var v = crystal.get(k)
			if typeof(v) == TYPE_OBJECT and ("depth" in v or v.has_method("set_depth")):
				return v
	return null

func _seed(fluid, n: int) -> void:
	if fluid == null or not fluid.has_method("set_depth"):
		print("CSTRESS seed skip")
		return
	var placed := 0
	var r := 0
	while placed < n and r < 80:
		for z in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(z)) != r:
					continue
				fluid.set_depth(Vector2i(x, z), 0.7, 0, false)
				placed += 1
				if placed >= n:
					return
		r += 1

func _sample(tag: String, sec: float, crystal, fluid) -> void:
	var dts := PackedFloat64Array()
	var t0 := Time.get_ticks_usec()
	var last: int = t0
	while float(Time.get_ticks_usec() - t0) < sec * 1000000.0:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		dts.append(float(now - last) / 1000.0)
		last = now
	var s := dts.duplicate()
	s.sort()
	var n: int = s.size()
	var sum: float = 0.0
	var over33: int = 0
	var over50: int = 0
	for d in s:
		var dv: float = float(d)
		sum += dv
		if dv > 33.3:
			over33 += 1
		if dv > 50.0:
			over50 += 1
	var avg: float = sum / maxf(float(n), 1.0)
	var fps: float = 1000.0 / maxf(avg, 0.001)
	var covered: int = -1
	if crystal != null and "covered_cells" in crystal:
		covered = int(crystal.get("covered_cells"))
	var depth_n: int = -1
	if fluid != null and "depth" in fluid:
		depth_n = int(fluid.depth.size())
	var p50: float = 0.0
	var p95: float = 0.0
	var p99: float = 0.0
	var mx: float = 0.0
	if n > 0:
		p50 = float(s[n / 2])
		p95 = float(s[mini(n - 1, int(n * 0.95))])
		p99 = float(s[mini(n - 1, int(n * 0.99))])
		mx = float(s[n - 1])
	print("%s n=%d sec=%.1f avg_ms=%.2f fps=%.1f p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f max_ms=%.2f over33=%d over50=%d covered=%d depth=%d" % [
		tag, n, sec, avg, fps, p50, p95, p99, mx, over33, over50, covered, depth_n])