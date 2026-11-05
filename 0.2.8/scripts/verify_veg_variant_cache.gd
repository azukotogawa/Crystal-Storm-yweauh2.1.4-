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
	print("VEG_CACHE models=%d" % paths.size())

	var sample: Array = []
	for p in paths:
		var ps := str(p)
		if ps.find("tree_oak_v0_s2") >= 0 or ps.find("tree_pine_v0_s2") >= 0 or ps.find("bush_v0_s2") >= 0:
			sample.append(ps)
	if sample.is_empty():
		for p2 in paths:
			if str(p2).find("tree_") >= 0 and str(p2).find("_s2_") >= 0:
				sample.append(str(p2))
				if sample.size() >= 2:
					break
	if sample.is_empty() and paths.size() > 0:
		sample.append(str(paths[0]))
	print("VEG_CACHE sample=%s" % str(sample))

	_wipe_cache()
	Loader.drop_memory()

	var bad := 0
	var checked := 0
	var cold_us_total := 0
	var warm_us_total := 0
	for path_v in sample:
		var path := str(path_v)
		for variant in [0, 1, 2]:
			Loader.drop_memory()
			_wipe_cache_for(path, variant)
			var t0 := Time.get_ticks_usec()
			var built: Dictionary = Loader.build_variant_detached(path, variant)
			var cold_us: int = Time.get_ticks_usec() - t0
			if built.is_empty() or built.get("mesh", null) == null:
				print("VEG_CACHE BUILD_FAIL path=%s v=%d" % [path.get_file(), variant])
				bad += 1
				continue
			var fresh_mesh: ArrayMesh = built["mesh"]
			var fresh_quads: int = int(built.get("quads", -1))
			var fresh_sig := _mesh_sig(fresh_mesh)
			built["_unsaved"] = true
			Loader.store_variant(path, variant, built)
			Loader.drop_memory()
			var t1 := Time.get_ticks_usec()
			var reloaded: Dictionary = Loader.build_variant_detached(path, variant)
			var warm_us: int = Time.get_ticks_usec() - t1
			if reloaded.is_empty() or reloaded.get("mesh", null) == null:
				print("VEG_CACHE RELOAD_FAIL path=%s v=%d" % [path.get_file(), variant])
				bad += 1
				continue
			var warm_mesh: ArrayMesh = reloaded["mesh"]
			var warm_quads: int = int(reloaded.get("quads", -1))
			var warm_sig := _mesh_sig(warm_mesh)
			checked += 1
			cold_us_total += cold_us
			warm_us_total += warm_us
			if fresh_quads != warm_quads or fresh_sig != warm_sig:
				bad += 1
				print("VEG_CACHE MISMATCH path=%s v=%d fresh_q=%d warm_q=%d fresh_sig=%s warm_sig=%s" % [
					path.get_file(), variant, fresh_quads, warm_quads, fresh_sig, warm_sig])
			else:
				print("VEG_CACHE OK path=%s v=%d quads=%d cold_us=%d warm_us=%d speedup=%.1fx" % [
					path.get_file(), variant, fresh_quads, cold_us, warm_us,
					float(cold_us) / maxf(float(warm_us), 1.0)])

	print("VEG_CACHE summary checked=%d bad=%d cold_us=%d warm_us=%d speedup=%.1fx" % [
		checked, bad, cold_us_total, warm_us_total,
		float(cold_us_total) / maxf(float(warm_us_total), 1.0)])
	quit(0 if bad == 0 and checked > 0 else 1)

func _mesh_sig(mesh: ArrayMesh) -> String:
	if mesh == null or mesh.get_surface_count() < 1:
		return "empty"
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var aabb := mesh.get_aabb()
	return "v%d_i%d_aabb(%.3f,%.3f,%.3f,%.3f,%.3f,%.3f)" % [
		verts.size(), idx.size(),
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.size.x, aabb.size.y, aabb.size.z]

func _wipe_cache() -> void:
	var abs_path := ProjectSettings.globalize_path(Loader.CACHE_ROOT)
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".res"):
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()

func _wipe_cache_for(path: String, variant: int) -> void:
	var full: String = Loader.cache_file(path, "", variant)
	if FileAccess.file_exists(full):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(full))
	var abs_root := ProjectSettings.globalize_path(Loader.CACHE_ROOT)
	var d := DirAccess.open(abs_root)
	if d == null:
		return
	var md5 := FileAccess.get_md5(path)
	var vtag := "" if variant <= 0 else ("_m%d" % variant)
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.find(md5) >= 0 and n.ends_with("_r3.res"):
			if variant <= 0 and n.find("_m") >= 0:
				n = d.get_next()
				continue
			if variant > 0 and n.find(vtag) < 0:
				n = d.get_next()
				continue
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()