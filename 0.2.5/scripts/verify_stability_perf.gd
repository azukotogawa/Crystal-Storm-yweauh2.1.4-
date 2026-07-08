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
		"res://systems/perf_profiler.gd",
		"res://systems/topographical_map_builder.gd",
		"res://ui/topographical_map.gd",
		"res://crystal/crystal_terrain_query.gd",
		"res://chunks/chunk_mesh_buffer_builder.gd",
		"res://entities/entity_navigation.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL " + path)
			failed = true
		else:
			print("OK ", path)

	var perf_default = load("res://config/performance_quality_config.gd").create_default()
	if int(perf_default.preset) != 1:
		push_error("default preset should be MEDIUM")
		failed = true
	else:
		print("OK default preset MEDIUM")

	var perf_low = load("res://config/performance_quality_config.gd").apply_preset(0)
	if perf_low.render_distance > 2 or perf_low.caves_enabled:
		push_error("LOW preset too heavy")
		failed = true
	elif perf_low.max_crystal_flow_cells <= 0:
		push_error("LOW max_crystal_flow_cells should be capped")
		failed = true
	else:
		print("OK LOW preset dist=", perf_low.render_distance)

	var perf_high = load("res://config/performance_quality_config.gd").apply_preset(2)
	if perf_high.crystal_sim_hz < 16.0:
		push_error("HIGH crystal_sim_hz too low")
		failed = true
	else:
		print("OK HIGH crystal_sim_hz=", perf_high.crystal_sim_hz)

	var perf_med = load("res://config/performance_quality_config.gd").apply_preset(1)
	if perf_med.render_distance > 2 or not perf_med.prebuild_chunk_buffers:
		push_error("MEDIUM preset not tuned for 60fps")
		failed = true
	else:
		print("OK MEDIUM render_distance=", perf_med.render_distance)

	var perf_safe = load("res://config/performance_quality_config.gd").apply_safe_mode()
	if perf_safe.crystal_sim_enabled or perf_safe.minimap_enabled:
		push_error("SAFE mode should disable crystal sim and minimap")
		failed = true
	else:
		print("OK SAFE mode crystal=off map=off")

	var perf_cfg = load("res://config/performance_quality_config.gd")
	if not perf_cfg.has_method("apply_safe_mode"):
		push_error("missing apply_safe_mode")
		failed = true

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