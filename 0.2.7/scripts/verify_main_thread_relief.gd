extends SceneTree

const _CrystalFluidSim = preload("res://crystal/crystal_fluid_sim.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _CrystalSimConfig = preload("res://config/crystal_sim_config.gd")

func _init() -> void:
	var failed := false

	for path in [
		"res://systems/perf_profiler.gd",
		"res://systems/performance_service.gd",
		"res://world/world_features.gd",
		"res://world/vegetation_manager.gd",
		"res://crystal/crystal_fluid_sim.gd",
		"res://systems/topographical_map_builder.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL " + path)
			failed = true
		else:
			print("OK ", path)

	var sim := _CrystalFluidSim.new(_CrystalSimConfig.create_default(), _CrystalTerrainQuery.new())
	sim.set_depth(Vector2i(0, 0), 1.0, 0, true)
	var changed: Array = sim.tick_flow(0.1)
	if typeof(changed) != TYPE_ARRAY:
		push_error("tick_flow should return Array")
		failed = true
	else:
		print("OK tick_flow returns array size=", changed.size())

	var safe = load("res://config/performance_quality_config.gd").apply_safe_mode()
	if safe.chunk_upload_budget_us <= 0:
		push_error("SAFE upload budget invalid")
		failed = true
	else:
		print("OK SAFE upload_budget=", safe.chunk_upload_budget_us)

	var perf_svc = load("res://systems/performance_service.gd").new()
	if not perf_svc.has_method("apply_safe_mode") or not perf_svc.has_method("is_safe_mode"):
		push_error("PerformanceService missing safe mode API")
		failed = true
	else:
		print("OK PerformanceService safe mode API")

	if failed:
		quit(1)
	print("All main-thread relief tests OK")
	quit(0)