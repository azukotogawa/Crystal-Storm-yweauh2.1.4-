extends SceneTree
const _ModelScript = preload("res://helpers/crystal_voxel_model.gd")
const Loader = preload("res://helpers/crystal_voxel_loader.gd")

func _init() -> void:
	var root := "res://assets/voxel/vegetation/lod/"
	var dir := DirAccess.open(root)
	if dir == null:
		push_error("no veg lod dir")
		quit(2)
		return
	var paths: Array = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			paths.append(root + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	var built_n := 0
	var cached_n := 0
	var fail_n := 0
	var t0 := Time.get_ticks_usec()
	for path_v in paths:
		var path := str(path_v)
		for variant in [0, 1, 2]:
			Loader.drop_memory()
			var probe: Dictionary = Loader.build_variant_detached(path, variant)
			if probe.is_empty():
				fail_n += 1
				continue
			if bool(probe.get("_unsaved", false)):
				Loader.store_variant(path, variant, probe)
				built_n += 1
			else:
				Loader.store_variant(path, variant, probe)
				cached_n += 1
	var us: int = Time.get_ticks_usec() - t0
	print("VEG_PRECOMPUTE models=%d built=%d already_cached=%d fail=%d total_us=%d" % [
		paths.size(), built_n, cached_n, fail_n, us])
	quit(0 if fail_n == 0 else 1)