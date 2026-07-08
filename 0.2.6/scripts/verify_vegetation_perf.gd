extends SceneTree

const _FeatureRegistry = preload("res://world/feature_registry.gd")

func _init() -> void:
	var failed := false
	for path in [
		"res://world/vegetation_growth_manager.gd",
		"res://world/feature_registry.gd",
		"res://crystal/crystal_terrain_query.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL " + path)
			failed = true
		else:
			print("OK ", path)

	_FeatureRegistry.reset()
	_FeatureRegistry.register_feature(10, 10, 0, {
		"plant_id": "oak_sapling",
		"growth_stage": 2,
		"growth_progress": 0.0,
	})
	_FeatureRegistry.set_plant_growth_state(10, 10, 2, 0.5)
	var mult: float = _FeatureRegistry.get_denial_mult_at(10, 10, 0.6)
	if mult < 0.0 or mult > 1.0:
		push_error("denial mult out of range")
		failed = true
	else:
		print("OK denial mult=", mult)

	var keys1: Array = _FeatureRegistry.get_plant_keys()
	var keys2: Array = _FeatureRegistry.get_plant_keys()
	if keys1.size() != keys2.size():
		push_error("plant key cache unstable")
		failed = true
	else:
		print("OK plant key cache size=", keys1.size())

	var perf = load("res://config/performance_quality_config.gd").apply_preset(1)
	if perf.vegetation_plants_per_tick > 24:
		push_error("MEDIUM plants_per_tick too high")
		failed = true
	else:
		print("OK MEDIUM plants_per_tick=", perf.vegetation_plants_per_tick)

	if failed:
		quit(1)
	print("All vegetation perf tests OK")
	quit(0)