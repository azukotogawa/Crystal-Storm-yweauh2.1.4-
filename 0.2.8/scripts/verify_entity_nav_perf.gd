extends SceneTree

const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _ChunkMeshBufferBuilder = preload("res://chunks/chunk_mesh_buffer_builder.gd")

func _init() -> void:
	var failed := false

	for path in [
		"res://entities/entity_navigation.gd",
		"res://chunks/chunk_mesh_buffer_builder.gd",
		"res://crystal/crystal_terrain_query.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL " + path)
			failed = true
		else:
			print("OK ", path)

	_EntityNavigation.use_lightweight_nav = true
	var y_light: float = _EntityNavigation.walkable_y_light(null, null, null, 0.5, 0.5)
	if y_light <= 0.0:
		push_error("walkable_y_light should return positive default")
		failed = true
	else:
		print("OK walkable_y_light=", y_light)

	_EntityNavigation.use_lightweight_nav = false
	var probe_y: float = _EntityNavigation.walkable_y(null, null, null, 0.5, 0.5)
	if probe_y <= 0.0:
		push_error("walkable_y default should be positive")
		failed = true
	else:
		print("OK walkable_y=", probe_y)

	var terrain := _CrystalTerrainQuery.new()
	terrain.begin_sim_tick(1)
	var h1: float = terrain.get_terrain_height(Vector2i(4, 4))
	var h2: float = terrain.get_terrain_height(Vector2i(4, 4))
	if h1 != h2:
		push_error("terrain height cache miss")
		failed = true
	else:
		print("OK terrain cache")

	terrain.begin_sim_tick(2)
	var h3: float = terrain.get_terrain_height(Vector2i(4, 4))
	if h3 != 0.0:
		push_error("terrain cache should reset without world")
		failed = true
	else:
		print("OK terrain cache reset")

	var perf_med = load("res://config/performance_quality_config.gd").apply_preset(1)
	if not perf_med.use_lightweight_entity_nav:
		push_error("MEDIUM should use lightweight entity nav")
		failed = true
	elif perf_med.render_distance > 2:
		push_error("MEDIUM render_distance too high for 60fps target")
		failed = true
	elif not perf_med.prebuild_chunk_buffers:
		push_error("MEDIUM should prebuild chunk buffers")
		failed = true
	else:
		print("OK MEDIUM preset dist=", perf_med.render_distance, " nav=light")

	var perf_high = load("res://config/performance_quality_config.gd").apply_preset(2)
	if perf_high.use_lightweight_entity_nav:
		push_error("HIGH should use full entity nav")
		failed = true
	else:
		print("OK HIGH preset nav=full")

	var empty_payload: Dictionary = _ChunkMeshBufferBuilder.build_mesh_payload(
		ChunkData.new(Vector2i.ZERO), []
	)
	if not empty_payload.has("terrain_buffer") or int(empty_payload.get("count", -1)) != 0:
		push_error("empty mesh payload invalid")
		failed = true
	else:
		print("OK empty mesh payload")

	if failed:
		quit(1)
	print("All entity nav / buffer perf tests OK")
	quit(0)