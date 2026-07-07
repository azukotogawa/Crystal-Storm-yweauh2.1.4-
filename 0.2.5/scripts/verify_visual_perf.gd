extends SceneTree

func _init() -> void:
	var failed := false
	for path in [
		"res://config/performance_quality_config.gd",
		"res://systems/performance_service.gd",
		"res://systems/combat_visual_feedback.gd",
		"res://systems/crystal_texture_generator.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null:
			push_error("FAIL load " + path)
			failed = true
			continue
		if scr.reload() != OK:
			push_error("FAIL compile " + path)
			failed = true
		else:
			print("OK ", path)

	var gen = load("res://systems/crystal_texture_generator.gd").new()
	var bundle: Dictionary = gen.generate_combat_ui_bundle()
	for key in ["damage_number", "hit_flash", "shatter", "spawn_boss", "victory_glow"]:
		if not bundle.has(key) or bundle[key] == null:
			push_error("missing texture " + key)
			failed = true
		else:
			print("OK texture ", key)

	var perf = load("res://config/performance_quality_config.gd").apply_preset(0)
	if perf.render_distance > 2 or perf.caves_enabled:
		push_error("LOW preset too heavy (dist/caves)")
		failed = true
	else:
		print("OK LOW preset render_distance=", perf.render_distance, " caves=", perf.caves_enabled)

	if failed:
		quit(1)
	print("All visual/perf tests OK")
	quit(0)