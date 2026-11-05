extends SceneTree
## One-shot: pack loose .chk into regions for BENCH_SEED (default 12349).
func _init() -> void:
	call_deferred("_go")
func _go() -> void:
	var seed := 12349
	if OS.get_environment("BENCH_SEED") != "":
		seed = int(OS.get_environment("BENCH_SEED"))
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	var S = load("res://world/world_bake_service.gd")
	var bake = S.ensure_active()
	if not bake.load_bake_for_seed(seed, true):
		bake.world_seed = seed
		bake.full_world = true
		bake.streamed = true
		var b: Dictionary = S.full_world_chunk_bounds()
		bake.min_cx = int(b.min_cx); bake.max_cx = int(b.max_cx)
		bake.min_cz = int(b.min_cz); bake.max_cz = int(b.max_cz)
		bake.package_dir = bake.bake_dir_for(seed, -1, true)
		bake._inventory_existing_packages()
		print("PACK no_index pkgs=%d dir=%s" % [bake._packages_known.size(), ProjectSettings.globalize_path(str(bake.package_dir))])
	else:
		print("PACK loaded pkgs=%d dir=%s" % [bake.chunk_count(), ProjectSettings.globalize_path(str(bake.package_dir))])
	var RP = load("res://world/region_pack.gd")
	var cdir: String = str(bake.package_dir).path_join("chunks")
	var t0 := Time.get_ticks_msec()
	var st: Dictionary = RP.pack_dir(cdir, bake.regions_dir())
	print("PACK RESULT ok=%s regions=%d chunks=%d ms=%d dir=%s" % [str(st.get("ok")), int(st.get("regions",0)), int(st.get("chunks",0)), Time.get_ticks_msec()-t0, ProjectSettings.globalize_path(bake.regions_dir())])
	quit(0 if bool(st.get("ok")) else 1)