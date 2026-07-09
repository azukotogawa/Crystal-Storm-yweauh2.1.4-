extends SceneTree
## Regression: LOW/MEDIUM/HIGH perf presets apply without invalid config.


const _Perf = preload("res://config/performance_quality_config.gd")


func _init() -> void:
	var failed := false
	for preset_id in [0, 1, 2]:
		var cfg = _Perf.apply_preset(preset_id)
		if cfg == null:
			push_error("preset %d returned null" % preset_id)
			failed = true
			continue
		if cfg.render_distance < 1 or cfg.max_chunks_per_frame < 1:
			push_error("preset %d invalid chunk streaming" % preset_id)
			failed = true
			continue
		if cfg.max_crystal_new_cells_per_tick < 1:
			push_error("preset %d invalid crystal cap" % preset_id)
			failed = true
			continue
		print("OK preset=%d dist=%d crystal_cap=%d veg_voxel_dist=%d" % [
			preset_id,
			cfg.render_distance,
			cfg.max_crystal_new_cells_per_tick,
			cfg.vegetation_billboard_distance_columns,
		])

	if failed:
		quit(1)
	print("All perf preset config tests OK")
	quit(0)