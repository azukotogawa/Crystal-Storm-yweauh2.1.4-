extends SceneTree
## v123 chunk packages: raw columns (surface, tiles, vegetation) in one ZSTD
## block, no stored mesh plan. Older packages and bake folders are refused with
## "rebake needed" and left on disk.

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 990823
const RADIUS := 0

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", str(RADIUS))
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("OK %s" % msg)
	else:
		_failed += 1
		push_error(msg)
		print("FAIL: %s" % msg)


func _run() -> void:
	var ver: int = _WorldBakeService.BAKE_VERSION
	_check(ver >= 123, "BAKE_VERSION %d >= 123" % ver)
	_check(_WorldBakeService.RAW_COLUMNS_VERSION == 123, "raw columns start at v123")

	# Round trip of the columns block.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var surface := PackedFloat32Array()
	var tiles := PackedInt32Array()
	for i in _WorldBakeService.CELLS2:
		surface.append(snappedf(rng.randf_range(-20.0, 60.0), 0.25))
		tiles.append(rng.randi_range(0, 40))
	var veg: Array = [{"lx": 3, "lz": 5, "tile": 17, "kind": "tree"}, {"lx": 0, "lz": 15, "tile": 2}]
	var block: PackedByteArray = _WorldBakeService.encode_columns(surface, tiles, veg)
	var back: Dictionary = _WorldBakeService.decode_columns(block)
	_check(not back.is_empty(), "decode_columns returns data")
	_check(back.get("surface", PackedFloat32Array()) == surface, "surface round trip")
	_check(back.get("tiles", PackedInt32Array()) == tiles, "tiles round trip")
	_check(var_to_str(back.get("vegetation", [])) == var_to_str(veg), "vegetation round trip")
	_check(block.decode_u32(4) < block.decode_u32(0), "block is compressed raw=%d comp=%d" % [block.decode_u32(0), block.decode_u32(4)])
	var bad := block.duplicate()
	bad[bad.size() - 3] = bad[bad.size() - 3] ^ 0x5A
	var bad_back: Dictionary = _WorldBakeService.decode_columns(bad)
	_check(bad_back.is_empty() or bad_back.get("surface") != surface or var_to_str(bad_back.get("vegetation")) != var_to_str(veg) or bad_back.get("tiles") != tiles, "damaged block does not decode to the same data")

	# Real bake of one chunk.
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)
	var built: Dictionary = bake.bake_world(world, RADIUS, host)
	_check(bool(built.get("ok", false)), "bake_world radius 0")
	bake.save_bake()
	var path := bake.chunk_package_path(Vector2i.ZERO)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	_check(bytes.size() > 24, "package written bytes=%d" % bytes.size())
	_check(bytes.slice(0, 4).get_string_from_utf8() == "CSCH", "package magic CSCH")
	_check(bytes.decode_u32(4) == ver, "package version %d" % bytes.decode_u32(4))
	_check(bytes.decode_u32(24) & _WorldBakeService.CHUNK_FLAG_RAW_COLUMNS != 0, "raw columns flag set")
	print("SIZE v%d chunk package bytes=%d" % [ver, bytes.size()])

	_WorldBakeService.clear_active()
	var loaded: _WorldBakeService = _WorldBakeService.ensure_active()
	_check(loaded.load_bake(SEED, RADIUS), "load_bake v%d: %s" % [ver, loaded.last_error])
	var pack: Dictionary = loaded._read_chunk_package(Vector2i.ZERO)
	_check(not pack.is_empty(), "read package: %s" % loaded.last_error)
	_check((pack.get("surface", PackedFloat32Array()) as PackedFloat32Array).size() == _WorldBakeService.CELLS2, "surface has %d cells" % _WorldBakeService.CELLS2)
	_check((pack.get("plan", [1]) as Array).is_empty(), "no stored plan in package")
	var cols: Dictionary = loaded._read_chunk_package_columns_only(Vector2i.ZERO)
	_check(cols.get("tiles") == pack.get("tiles"), "columns-only read matches full read")
	var val: Dictionary = loaded.validate_loaded_bake(SEED, false)
	_check(bool(val.get("ok", false)), "validate_loaded_bake ok without stored plans: %s" % str(val.get("reasons")))
	_check(not loaded.packages_need_mesh_plan_fill(), "no plan fill needed")
	loaded.ensure_mesh_plans(host, world)
	var plan: Array = loaded.get_mesh_plan(Vector2i.ZERO)
	_check(plan.size() > 0, "mesh plan built at load quads=%d" % plan.size())
	_check(FileAccess.get_file_as_bytes(path) == bytes, "building the plan at load does not rewrite the package")

	# Corruption: damage the compressed block and the checksum.
	var mid: PackedByteArray = bytes.duplicate()
	mid[40] = mid[40] ^ 0xFF
	_write(path, mid)
	loaded._resident.erase(Vector2i.ZERO)
	loaded._surface_resident.erase(Vector2i.ZERO)
	_check(loaded._read_chunk_package(Vector2i.ZERO).is_empty(), "damaged block refused: %s" % loaded.last_error)
	_write(path, bytes)
	_check(loaded.corrupt_chunk_package(Vector2i.ZERO), "corrupt checksum")
	_check(loaded._read_chunk_package(Vector2i.ZERO).is_empty(), "bad checksum refused: %s" % loaded.last_error)
	_check(loaded.last_error.contains("checksum"), "checksum error message")

	# v122 package: refused with rebake needed.
	var old: PackedByteArray = bytes.duplicate()
	old.encode_u32(4, 122)
	_write(path, old)
	_check(loaded._read_chunk_package(Vector2i.ZERO).is_empty(), "v122 package refused")
	_check(loaded.last_error.contains("rebake needed"), "v122 package message: %s" % loaded.last_error)
	_check(loaded._read_chunk_package_columns_only(Vector2i.ZERO).is_empty(), "v122 columns-only read refused")
	loaded.delete_bake(SEED, RADIUS)

	# Old full bake folder: reported, refused, left on disk.
	var half: int = int(_WorldBakeService.full_world_chunk_bounds().get("span_x", 0))
	var old_dir := "user://world_bakes/v122_s%d_h1024_full" % SEED
	var old_abs := ProjectSettings.globalize_path(old_dir)
	DirAccess.make_dir_recursive_absolute(old_abs.path_join("chunks"))
	_write(old_dir.path_join("world.index"), "CSWI".to_utf8_buffer())
	_write(old_dir.path_join("chunks/0_0.chk"), old)
	var older: Array = _WorldBakeService.older_bakes_for_seed(SEED)
	_check(older.has("v122_s%d_h1024_full" % SEED), "older bake listed: %s" % str(older))
	var st: Dictionary = _WorldBakeService.inspect_disk_status(SEED)
	_check(bool(st.get("rebake_needed", false)), "inspect_disk_status rebake_needed")
	_check(not bool(st.get("has_index", true)), "no current-version index (span %d)" % half)
	_WorldBakeService.clear_active()
	var fresh: _WorldBakeService = _WorldBakeService.ensure_active()
	_check(not fresh.load_bake_for_seed(SEED, true), "old full bake not loaded")
	_check(fresh.last_error.contains("rebake needed"), "load message: %s" % fresh.last_error)
	_check(FileAccess.file_exists(old_dir.path_join("chunks/0_0.chk")), "old folder left untouched")
	fresh._rm_tree(old_abs)
	_check(not DirAccess.dir_exists_absolute(old_abs), "test folder cleaned")

	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "BAKE_V123_FORMAT FAIL %d" % _failed)
	else:
		_ProbeExit.finish_tree(self, 0, "BAKE_V123_FORMAT PASS")


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(data)
		f.close()
