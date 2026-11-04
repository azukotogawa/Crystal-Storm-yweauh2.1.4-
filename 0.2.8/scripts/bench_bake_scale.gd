extends SceneTree
## Scratch bench for the item 11 full-scale retest (not committed).
## BENCH = sample | full | pack | load | hash | corrupt | upgrade | delete
## BENCH_SEED (default 424242). Prints BENCH lines.

const SAMPLE_EVERY := 100

var S = null
var seed := 424242


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("BENCH_SEED") != "":
		seed = int(OS.get_environment("BENCH_SEED"))
	call_deferred("_run")


static func plan_hash(plan: Array) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for q_variant in plan:
		var q: Dictionary = q_variant
		var keys: Array = q.keys()
		keys.sort()
		var parts := PackedStringArray()
		for k in keys:
			parts.append("%s=%s" % [str(k), var_to_str(q[k])])
		ctx.update(("|".join(parts) + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


func _dir_stats(dir: String) -> Dictionary:
	var files := 0
	var bytes := 0
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return {"files": 0, "bytes": 0}
	for f in DirAccess.get_files_at(abs_dir):
		files += 1
		var fa := FileAccess.open(abs_dir.path_join(f), FileAccess.READ)
		if fa:
			bytes += fa.get_length()
			fa.close()
	for d in DirAccess.get_directories_at(abs_dir):
		var sub := _dir_stats(abs_dir.path_join(d))
		files += int(sub.files)
		bytes += int(sub.bytes)
	return {"files": files, "bytes": bytes}


func _rm_tree(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for f in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	for d in DirAccess.get_directories_at(abs_dir):
		_rm_tree(abs_dir.path_join(d))
	DirAccess.remove_absolute(abs_dir)


func _mem() -> String:
	return "static_mb=%.1f peak_mb=%.1f" % [OS.get_static_memory_usage() / 1048576.0, OS.get_static_memory_peak_usage() / 1048576.0]


func _all_coords(b) -> Array:
	var out: Array = []
	for cz in range(int(b.min_cz), int(b.max_cz) + 1):
		for cx in range(int(b.min_cx), int(b.max_cx) + 1):
			out.append(Vector2i(cx, cz))
	return out


func _run() -> void:
	S = load("res://world/world_bake_service.gd")
	load("res://world/world_state.gd").replace_active()
	S.clear_active()
	var world = load("res://world/InfiniteNoiseWorld.gd").new(seed)
	var host = load("res://chunks/chunk_manager.gd").new()
	var mode := OS.get_environment("BENCH")
	print("BENCH mode=%s seed=%d version=%d region_env=%s" % [mode, seed, int(S.BAKE_VERSION), OS.get_environment("CRYSTALSTORM_BAKE_REGION")])
	var bake = S.ensure_active()
	var dir: String = S.full_bake_dir_for_seed(seed)
	print("BENCH dir=%s" % ProjectSettings.globalize_path(dir))
	match mode:
		"sample":
			bake.delete_bake(seed, -1)
			var b: Dictionary = S.full_world_chunk_bounds()
			bake.world_seed = seed
			bake.full_world = true
			bake.streamed = true
			bake.min_cx = int(b.min_cx); bake.max_cx = int(b.max_cx)
			bake.min_cz = int(b.min_cz); bake.max_cz = int(b.max_cz)
			bake.package_dir = dir
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir.path_join("chunks")))
			var coords := _all_coords(b)
			var t0 := Time.get_ticks_msec()
			var n := 0
			var bytes := 0
			var i := 0
			while i < coords.size():
				var one: Dictionary = bake._bake_one_chunk(coords[i], world, host, [])
				if bool(one.get("ok", false)):
					n += 1
				i += SAMPLE_EVERY
			var st := _dir_stats(dir)
			bytes = int(st.bytes)
			var avg := float(bytes) / maxf(n, 1)
			print("BENCH SAMPLE chunks=%d of %d avg_bytes=%.0f est_total_mb=%.1f ms=%d" % [n, coords.size(), avg, avg * coords.size() / 1048576.0, Time.get_ticks_msec() - t0])
			_rm_tree(ProjectSettings.globalize_path(dir))
		"full":
			bake.delete_bake(seed, -1)
			var t0 := Time.get_ticks_msec()
			var built: Dictionary = bake.bake_world(world, -1, host)
			var bake_ms := Time.get_ticks_msec() - t0
			var t1 := Time.get_ticks_msec()
			var saved: Dictionary = bake.save_bake()
			var st := _dir_stats(bake.package_dir)
			print("BENCH FULL ok=%s chunks=%d bake_ms=%d save_ms=%d files=%d bytes=%d mb=%.1f %s err=%s save_ok=%s" % [
				str(built.get("ok")), int(bake.expected_chunk_count()), bake_ms, Time.get_ticks_msec() - t1,
				int(st.files), int(st.bytes), int(st.bytes) / 1048576.0, _mem(), bake.last_error, str(saved.get("ok"))])
		"pack":
			if not bake.load_bake_for_seed(seed, true):
				print("BENCH PACK FAIL load %s" % bake.last_error)
			else:
				var RP = load("res://world/region_pack.gd")
				var cdir: String = bake.package_dir.path_join("chunks")
				var t0 := Time.get_ticks_msec()
				var st: Dictionary = RP.pack_dir(cdir, bake.regions_dir())
				var pack_ms := Time.get_ticks_msec() - t0
				var all := _dir_stats(bake.package_dir)
				var reg := _dir_stats(bake.regions_dir())
				print("BENCH PACK ok=%s regions=%d chunks=%d pack_ms=%d region_files=%d region_bytes=%d total_files=%d total_bytes=%d mb=%.1f (loose chunks kept for the loose runs)" % [
					str(st.get("ok")), int(st.get("regions", 0)), int(st.get("chunks", 0)), pack_ms, int(reg.files), int(reg.bytes), int(all.files), int(all.bytes), int(all.bytes) / 1048576.0])
		"load":
			var t0 := Time.get_ticks_usec()
			var ok: bool = bake.load_bake_for_seed(seed, true)
			var idx_us := Time.get_ticks_usec() - t0
			var v = bake.validate_loaded_bake(seed, false) if ok else {}
			var val_us := Time.get_ticks_usec() - t0 - idx_us
			var t1 := Time.get_ticks_usec()
			var em: Dictionary = bake.ensure_mesh_plans(host, world) if ok else {}
			var em_us := Time.get_ticks_usec() - t1
			print("BENCH LOAD ok=%s index_ms=%.1f validate_ms=%.1f validate=%s ensure_plans_ms=%.1f mode=%s err=%s" % [str(ok), idx_us / 1000.0, val_us / 1000.0, str(v.get("ok", v)) if v is Dictionary else str(v), em_us / 1000.0, str(em.get("mode", "")), bake.last_error])
			if ok:
				var coords := _all_coords({"min_cx": bake.min_cx, "max_cx": bake.max_cx, "min_cz": bake.min_cz, "max_cz": bake.max_cz})
				var bad := 0
				var t2 := Time.get_ticks_usec()
				for c in coords:
					if bake._read_chunk_package(c).is_empty():
						bad += 1
				var all_us := Time.get_ticks_usec() - t2
				print("BENCH READALL chunks=%d bad=%d total_ms=%.1f per_chunk_us=%.1f %s" % [coords.size(), bad, all_us / 1000.0, float(all_us) / maxf(coords.size(), 1), _mem()])
				# 81 chunks around spawn: read + mesh (what a start region costs)
				var t3 := Time.get_ticks_usec()
				var qn := 0
				for dz in range(-4, 5):
					for dx in range(-4, 5):
						var p: Array = bake.get_mesh_plan(Vector2i(dx, dz))
						qn += p.size()
				print("BENCH START81 read_plus_plan_ms=%.1f quads=%d plans_built=%s" % [(Time.get_ticks_usec() - t3) / 1000.0, qn, str(bake.get("stats_plan_built_at_load"))])
				if OS.get_environment("BENCH_CENSUS") == "1":
					var MC = load("res://scripts/mem_census.gd")
					var mc = MC.new()
					var acc := {}
					mc.fields_into(bake, "bake.", acc)
					print("BENCH " + MC.monitors_line("load_after_start81"))
					for ln in MC.table_lines("load", acc, 25):
						print("BENCH " + ln)
		"hash":
			if not bake.load_bake_for_seed(seed, true):
				print("BENCH HASH FAIL load %s" % bake.last_error)
			else:
				bake.ensure_mesh_plans(host, world)
				var rng := RandomNumberGenerator.new()
				rng.seed = 11
				for k in 32:
					var c := Vector2i(rng.randi_range(bake.min_cx, bake.max_cx), rng.randi_range(bake.min_cz, bake.max_cz))
					var p: Array = bake.get_mesh_plan(c)
					print("HASH %d,%d %d %s" % [c.x, c.y, p.size(), plan_hash(p)])
		"corrupt":
			if not bake.load_bake_for_seed(seed, true):
				print("BENCH CORRUPT FAIL load %s" % bake.last_error)
			else:
				var c := Vector2i(3, 5)
				var region := OS.get_environment("CRYSTALSTORM_BAKE_REGION") == "1"
				var path: String
				if region:
					var RP = load("res://world/region_pack.gd")
					path = RP.region_path(bake.regions_dir(), RP.region_of(c))
				else:
					path = bake.chunk_package_path(c)
				var bytes := FileAccess.get_file_as_bytes(path)
				var cut := bytes.slice(0, bytes.size() / 2) if not region else bytes.slice(0, bytes.size() - 64)
				var f := FileAccess.open(path, FileAccess.WRITE)
				f.store_buffer(cut)
				f.close()
				if region:
					load("res://world/region_pack.gd").clear_cache()
				# A chunk in the damaged region whose blob is now cut short.
				var probe := c
				if region:
					var RP2 = load("res://world/region_pack.gd")
					var r: Vector2i = RP2.region_of(c)
					probe = Vector2i(r.x * 8 + 7, r.y * 8 + 7)
				var d: Dictionary = bake._read_chunk_package(probe)
				print("BENCH CORRUPT region=%s path=%s truncated %d->%d read_empty=%s err=%s" % [str(region), path.get_file(), bytes.size(), cut.size(), str(d.is_empty()), bake.last_error])
				var res: bool = bake.ensure_chunk_resident(probe)
				print("BENCH CORRUPT resident=%s err=%s (no crash)" % [str(res), bake.last_error])
		"upgrade":
			var older: Array = S.older_bakes_for_seed(seed) if S.has_method("older_bakes_for_seed") else []
			var st: Dictionary = S.inspect_disk_status(seed)
			var ok: bool = bake.load_bake_for_seed(seed, true)
			print("BENCH UPGRADE older=%s rebake_needed=%s has_index=%s load_ok=%s err=%s" % [str(older), str(st.get("rebake_needed")), str(st.get("has_index")), str(ok), bake.last_error])
		"delete":
			_rm_tree(ProjectSettings.globalize_path(dir))
			print("BENCH DELETED %s exists=%s" % [dir, str(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)))])
	host.free()
	S.clear_active()
	for _i in 3:
		await process_frame
	print("BENCH END")
	quit(0)
