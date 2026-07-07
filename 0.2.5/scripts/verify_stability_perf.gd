extends SceneTree

func _init() -> void:
	var failed := false

	for path in [
		"res://config/performance_quality_config.gd",
		"res://config/world_gen_config.gd",
		"res://chunks/chunk_data.gd",
		"res://chunks/chunk_manager.gd",
		"res://chunks/chunk_view.gd",
		"res://world/InfiniteNoiseWorld.gd",
		"res://crystal/crystal_manager.gd",
		"res://crystal/crystal_fluid_sim.gd",
		"res://systems/performance_service.gd",
		"res://ui/topographical_map.gd",
		"res://entities/entity_manager.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL " + path)
			failed = true
		else:
			print("OK ", path)

	var perf = load("res://config/performance_quality_config.gd").apply_preset(0)
	if perf.render_distance > 2:
		push_error("LOW render_distance should be <= 2")
		failed = true
	if perf.caves_enabled:
		push_error("LOW caves_enabled should be false")
		failed = true
	if perf.combat_visuals_enabled:
		push_error("LOW combat_visuals_enabled should be false")
		failed = true
	if perf.max_crystal_flow_cells <= 0:
		push_error("LOW max_crystal_flow_cells should be capped")
		failed = true
	else:
		print("OK LOW preset dist=", perf.render_distance, " caves=", perf.caves_enabled)

	var cd = ChunkData.new(Vector2i.ZERO)
	if not cd.has_method("capture_worker_snapshot"):
		push_error("ChunkData missing capture_worker_snapshot")
		failed = true
	else:
		print("OK ChunkData.capture_worker_snapshot")

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.caves_enabled = false
	if world._sample_cave(0.0, 10.0, 0.0) != -1.0:
		push_error("caves disabled should short-circuit _sample_cave")
		failed = true
	else:
		print("OK caves disabled short-circuit")

	if failed:
		quit(1)
	print("All stability/perf tests OK")
	quit(0)