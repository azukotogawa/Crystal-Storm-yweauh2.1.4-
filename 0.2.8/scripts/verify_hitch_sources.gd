extends SceneTree
## Verifies visual bundle is generated once and full-world refresh is not wired to chunk_ready.
## Drives shipped GameVisualRegistry / WorldVisuals / CrystalManager APIs.


func _init() -> void:
	var failed := false

	# --- Registry: generate once, preload no-ops, refresh does not regen ---
	var reg_scr = load("res://systems/game_visual_registry.gd")
	var reg = reg_scr.new()
	var b1: Dictionary = reg.generate_game_visual_bundle()
	if b1.size() < 20:
		push_error("bundle too small: %d" % b1.size())
		failed = true
	var gen1 := int(reg._bundle_gen_count)
	reg.preload_game_bundle()
	reg.preload_game_bundle()
	var gen2 := int(reg._bundle_gen_count)
	if gen2 != gen1:
		push_error("preload_game_bundle regenerated textures (gen %d → %d)" % [gen1, gen2])
		failed = true
	else:
		print("OK preload no-op after first generate (gen_count=%d)" % gen1)

	# Force regen path still works
	reg.preload_game_bundle(true)
	if int(reg._bundle_gen_count) != gen1 + 1:
		push_error("force preload did not regenerate")
		failed = true
	else:
		print("OK force preload regenerates once")

	# clear_cache allows regen
	reg.clear_cache()
	if bool(reg._bundle_ready):
		push_error("clear_cache left bundle_ready true")
		failed = true
	reg.preload_game_bundle()
	if int(reg._bundle_gen_count) < gen1 + 2:
		push_error("preload after clear_cache did not regenerate")
		failed = true
	else:
		print("OK clear_cache then preload regenerates")

	if not reg.has_method("get_hitch_counters"):
		push_error("missing get_hitch_counters")
		failed = true
	else:
		var c: Dictionary = reg.get_hitch_counters()
		if int(c.get("bundle_gen_count", 0)) < 1:
			push_error("hitch counters missing gens")
			failed = true
		else:
			print("OK hitch counters ", c)

	# --- WorldVisuals: chunk_ready must not call full refresh ---
	var wv_src: String = FileAccess.get_file_as_string("res://world/world_visuals.gd")
	if wv_src.contains("call_deferred(\"_refresh_all_layers\")"):
		push_error("WorldVisuals still defers _refresh_all_layers on chunk path")
		failed = true
	else:
		print("OK WorldVisuals does not defer full refresh on chunk_ready")
	if not wv_src.contains("_refresh_all_layers"):
		push_error("WorldVisuals lost _refresh_all_layers (needed for bootstrap)")
		failed = true

	# --- Registry: chunk_ready handler is no-op / disconnected ---
	var reg_src: String = FileAccess.get_file_as_string("res://systems/game_visual_registry.gd")
	if reg_src.contains("call_deferred(\"_refresh_scene_visuals\")"):
		push_error("GameVisualRegistry still defers full scene refresh on chunk_ready")
		failed = true
	else:
		print("OK GameVisualRegistry no deferred full refresh on chunk_ready")
	if not reg_src.contains("_bundle_ready"):
		push_error("bundle_ready guard missing")
		failed = true

	# --- CrystalManager: expansion gated ---
	var cm_src: String = FileAccess.get_file_as_string("res://crystal/crystal_manager.gd")
	for needle in ["_should_run_expansion", "_stream_pressure_active", "_boot_stream_ready", "get_hitch_counters"]:
		if not cm_src.contains(needle):
			push_error("CrystalManager missing %s" % needle)
			failed = true
	if not failed:
		print("OK CrystalManager expansion gates present")

	if failed:
		push_error("VERIFY_HITCH_SOURCES_FAIL")
		quit(1)
	else:
		print("VERIFY_HITCH_SOURCES_OK")
		quit(0)
