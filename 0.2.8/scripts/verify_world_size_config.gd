extends SceneTree
## Item 8: world size comes from WorldBorder. Checks bake path, bake bounds,
## save header and map extent, including a world with a different half size.
## Run: godot --headless --path 0.2.8 -s res://scripts/verify_world_size_config.gd

const _WorldBorder = preload("res://helpers/world_border.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _SaveSchema = preload("res://systems/save_schema.gd")
const _MapConfig = preload("res://config/topographical_map_config.gd")
const TEST_SEED := 990817
const TEST_ROOT := "user://world_bakes"

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("OK " + msg)
	else:
		_failed += 1
		print("FAIL " + msg)


func _run() -> void:
	var half: int = _WorldBorder.PLAYABLE_HALF_X
	_check(half == 1024 and _WorldBorder.PLAYABLE_HALF_Z == 1024, "default world stays 2048x2048")

	# Bounds for the default and for other sizes.
	var b: Dictionary = _WorldBakeService.full_world_chunk_bounds()
	_check(int(b.chunks) == 16384 and int(b.span_x) == 128, "default bounds 128x128 = 16384 chunks")
	_check(_WorldBakeService.chunk_bounds_for_half(half, half) == b, "chunk_bounds_for_half(default) equals full_world_chunk_bounds")
	var b512: Dictionary = _WorldBakeService.chunk_bounds_for_half(512, 512)
	_check(int(b512.span_x) == 64 and int(b512.chunks) == 4096 and int(b512.min_cx) == -32 and int(b512.max_cx) == 31, "half 512 -> 64x64 chunks")
	var b2048: Dictionary = _WorldBakeService.chunk_bounds_for_half(2048, 2048)
	_check(int(b2048.span_x) == 256 and int(b2048.chunks) == 65536, "half 2048 -> 256x256 chunks")
	_check(_WorldBakeService.production_chunk_side() == int(b.span_x), "production_chunk_side from bounds")

	# Bake folder name carries the half extent.
	var ver: int = _WorldBakeService.BAKE_VERSION
	_check(_WorldBakeService.full_bake_dir(ver, 7, 512) == "user://world_bakes/v%d_s7_h512_full" % ver, "full bake dir for half 512")
	var svc = _WorldBakeService.new()
	var dir_default: String = svc.bake_dir_for(7, -1, true)
	_check(dir_default == "user://world_bakes/v%d_s7_h%d_full" % [ver, half], "bake_dir_for(full) includes h%d: %s" % [half, dir_default])
	_check(svc.bake_dir_for(7, 2, false) == "user://world_bakes/v%d_s7_r2" % ver, "radius bake dir unchanged")

	# Bounds mismatch is reported.
	_check(_WorldBakeService.bounds_mismatch_reason(b, b) == "", "same bounds -> no mismatch")
	_check(_WorldBakeService.bounds_mismatch_reason(b512, b) != "", "half 512 bake vs half 1024 world -> mismatch")
	_check(_WorldBakeService.bounds_mismatch_reason(b2048, b) != "", "half 2048 bake vs half 1024 world -> mismatch")

	# On disk: a full index with half-512 bounds must be refused.
	var bad_dir: String = TEST_ROOT.path_join("item8_test_h512")
	_write_index(bad_dir, TEST_SEED, b512)
	var svc2 = _WorldBakeService.new()
	var loaded: bool = svc2.load_index(bad_dir, TEST_SEED)
	_check(not loaded and str(svc2.last_error).find("bounds") >= 0, "load_index refuses half-512 bake: %s" % svc2.last_error)
	var good_dir: String = TEST_ROOT.path_join("item8_test_h1024")
	_write_index(good_dir, TEST_SEED, b)
	var svc3 = _WorldBakeService.new()
	_check(svc3.load_index(good_dir, TEST_SEED), "load_index accepts matching bake: %s" % svc3.last_error)

	# Old folder name (no _h) is renamed once for the default size.
	var legacy_dir: String = "user://world_bakes/v%d_s%d_full" % [ver, TEST_SEED]
	var new_dir: String = _WorldBakeService.full_bake_dir(ver, TEST_SEED, half)
	_rm(new_dir)
	_write_index(legacy_dir, TEST_SEED, b)
	var got: String = _WorldBakeService.full_bake_dir_for_seed(TEST_SEED)
	_check(got == new_dir and FileAccess.file_exists(new_dir.path_join("world.index")), "legacy full bake moved to %s" % got)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(legacy_dir)), "legacy folder gone after move")
	var st: Dictionary = _WorldBakeService.inspect_disk_status(TEST_SEED)
	_check(bool(st.get("has_index", false)) and int(st.get("expected", 0)) == int(b.chunks), "inspect_disk_status sees moved bake")

	# Save header.
	var hdr: Dictionary = _SaveSchema.world_size_header()
	_check(int(hdr.get("playable_half", 0)) == half, "save header playable_half = %d" % half)
	_check(bool(_SaveSchema.check_world_size({"world": {"seed": 1}}, half).get("ok", false)), "old save without playable_half loads as 2048 world")
	_check(bool(_SaveSchema.check_world_size({"world": {"playable_half": half}}, half).get("ok", false)), "matching playable_half ok")
	var mm: Dictionary = _SaveSchema.check_world_size({"world": {"playable_half": 512}}, half)
	_check(not bool(mm.get("ok", true)) and str(mm.get("reason", "")) == "world_size_mismatch", "playable_half 512 into 1024 world refused")
	_check(not bool(_SaveSchema.check_world_size({"world": {}}, 512).get("ok", true)), "old save refused in a half-512 world")
	var payload := {"schema_version": _SaveSchema.CURRENT_VERSION, "world": {"seed": 1, "playable_half": 512}, "world_state": {"height_delta": {}}}
	var v: Dictionary = _SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(payload))
	_check(not bool(v.get("ok", true)) and str(v.get("reason", "")) == "world_size_mismatch", "validate_and_migrate refuses size mismatch")
	payload.world.playable_half = half
	_check(bool(_SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(payload)).get("ok", false)), "validate_and_migrate accepts matching size")
	payload.world.erase("playable_half")
	_check(bool(_SaveSchema.validate_and_migrate(_SaveSchema.attach_integrity(payload)).get("ok", false)), "validate_and_migrate accepts old save")

	# Map extent and stride.
	var map_script = load("res://ui/topographical_map.gd")
	_check(int(map_script.FULL_HALF_EXTENT) == half + 64, "map FULL_HALF_EXTENT = half + 64 (%d)" % int(map_script.FULL_HALF_EXTENT))
	_check(_MapConfig.stride_for_extent(1088, 288, 2) == 8, "stride for 1088/288 = 8 (unchanged)")
	_check(_MapConfig.stride_for_extent(1088, 72, 2) == 31, "stride for 1088/72 = 31 (unchanged)")
	_check(_MapConfig.stride_for_extent(2048 + 64, 288, 2) == 15, "stride grows with a 4096 world")
	_check(_MapConfig.stride_for_extent(10, 288, 2) == 2, "stride never below the configured minimum")

	# Chunk manager mirrors read WorldBorder.
	var cm = load("res://chunks/chunk_manager.gd")
	_check(int(cm._WB_PLAYABLE_HALF_X) == half and int(cm._WB_PLAYABLE_HALF_Z) == _WorldBorder.PLAYABLE_HALF_Z, "chunk_manager half from WorldBorder")
	_check(is_equal_approx(float(cm._WB_TRANSITION), _WorldBorder.TRANSITION_WIDTH), "chunk_manager transition from WorldBorder")

	_rm(bad_dir)
	_rm(good_dir)
	_rm(new_dir)
	_rm(legacy_dir)
	if _failed == 0:
		print("WORLD_SIZE_CONFIG PASS")
	else:
		print("WORLD_SIZE_CONFIG FAIL %d" % _failed)
	quit(0 if _failed == 0 else 1)


func _write_index(dir: String, seed: int, bounds: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir.path_join("world.index"), FileAccess.WRITE)
	var ver: int = _WorldBakeService.BAKE_VERSION
	var mn_x: int = int(bounds.min_cx)
	var mx_x: int = int(bounds.max_cx)
	var mn_z: int = int(bounds.min_cz)
	var mx_z: int = int(bounds.max_cz)
	var flags: int = _WorldBakeService.FLAG_STREAMED | _WorldBakeService.FLAG_FULL_WORLD | _WorldBakeService.FLAG_VEGETATION
	var count: int = int(bounds.chunks)
	f.store_buffer(_WorldBakeService.INDEX_MAGIC.to_utf8_buffer())
	f.store_32(ver)
	f.store_64(seed)
	f.store_64(mn_x)
	f.store_64(mx_x)
	f.store_64(mn_z)
	f.store_64(mx_z)
	f.store_32(flags)
	f.store_32(count)
	f.store_32((ver ^ seed ^ mn_x ^ mx_x ^ mn_z ^ mx_z ^ flags ^ count) & 0xFFFFFFFF)
	f.close()


func _rm(dir: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for fn in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(fn))
	for sub in DirAccess.get_directories_at(abs_dir):
		_rm(dir.path_join(sub))
	DirAccess.remove_absolute(abs_dir)
