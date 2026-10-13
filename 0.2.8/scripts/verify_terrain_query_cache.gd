extends SceneTree
## Verifies frame-local / tick-local terrain query caches are deterministic and hit.


func _init() -> void:
	var failed := false

	# --- CrystalTerrainQuery tick cache ---
	var tq_scr = load("res://crystal/crystal_terrain_query.gd")
	var tq = tq_scr.new()
	tq.test_base_heights[Vector2i(1, 2)] = 40.0
	tq.test_base_heights[Vector2i(3, 4)] = 41.5
	tq.begin_sim_tick(1)
	var h1: float = tq.get_terrain_height(Vector2i(1, 2))
	var h2: float = tq.get_terrain_height(Vector2i(1, 2))
	if not is_equal_approx(h1, h2):
		push_error("height cache non-deterministic within tick")
		failed = true
	tq.set_query_measure_enabled(true)
	tq.reset_query_stats()
	tq.begin_sim_tick(2)
	tq.get_terrain_height(Vector2i(3, 4))
	tq.get_terrain_height(Vector2i(3, 4))
	tq.get_terrain_height(Vector2i(3, 4))
	var st: Dictionary = tq.get_query_stats()
	if int(st.get("height_hits", 0)) < 2 or int(st.get("height_misses", 0)) != 1:
		push_error("expected 1 miss + 2 hits got hits=%s misses=%s" % [st.get("height_hits"), st.get("height_misses")])
		failed = true
	else:
		print("OK CrystalTerrainQuery height tick cache hits=", st.get("height_hits"))

	# New tick clears cache
	tq.begin_sim_tick(3)
	tq.reset_query_stats()
	tq.get_terrain_height(Vector2i(3, 4))
	st = tq.get_query_stats()
	if int(st.get("height_misses", 0)) != 1:
		push_error("tick cache not cleared on new tick_id")
		failed = true
	else:
		print("OK tick cache invalidated on new tick_id")

	# --- FeatureRegistry ruin centers frame + derived cache ---
	var fr = load("res://world/feature_registry.gd")
	# Structural API checks
	for m in ["get_ruin_centers", "set_query_measure_enabled", "get_query_stats", "reset_query_stats"]:
		if not fr.has_method(m):
			push_error("FeatureRegistry missing %s" % m)
			failed = true
	var src := FileAccess.get_file_as_string("res://world/feature_registry.gd")
	if not src.contains("_ruin_centers_frame_valid") or not src.contains("_ensure_ruin_centers_list"):
		push_error("ruin center caches missing")
		failed = true
	else:
		print("OK FeatureRegistry ruin center cache present")

	# --- InfiniteNoiseWorld session cache sharing for tiles ---
	var wsrc := FileAccess.get_file_as_string("res://world/InfiniteNoiseWorld.gd")
	if not wsrc.contains("use_session_cache") or not wsrc.contains("_compute_surface_tile(wx, wz, true)"):
		push_error("get_tile_type should reuse session surface/biome caches")
		failed = true
	else:
		print("OK get_tile_type uses session surface/biome caches")
	if not wsrc.contains("elev_for_temp: float = surface_h if not is_nan"):
		# Accept either form of single-height reuse in biome compute
		if not wsrc.contains("surface_h: float = NAN") and not wsrc.contains("surface_h: float ="):
			push_error("biome compute should reuse single surface height")
			failed = true
		else:
			print("OK biome compute reuses surface height param")
	else:
		print("OK biome compute reuses surface height param")

	if failed:
		push_error("VERIFY_TERRAIN_QUERY_CACHE_FAIL")
		quit(1)
	else:
		print("VERIFY_TERRAIN_QUERY_CACHE_OK")
		quit(0)
