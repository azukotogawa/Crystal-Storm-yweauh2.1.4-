extends SceneTree
## _bake_one_chunk must match bake_world package bytes for the same seed/coord.
## Usage: godot --headless -s scripts/verify_bake_one_chunk_parity.gd

const _WorldState = preload("res://world/world_state.gd")
const _InfiniteNoiseWorld = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldBakeService = preload("res://world/world_bake_service.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")

const SEED := 919191
const RADIUS := 0

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_WORLD_BAKE", "1")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL: %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	_WorldState.replace_active()
	_WorldBakeService.clear_active()
	var world = _InfiniteNoiseWorld.new(SEED)
	var host = _ChunkManager.new()
	var bake: _WorldBakeService = _WorldBakeService.ensure_active()
	bake.delete_bake(SEED, RADIUS)

	var full: Dictionary = bake.bake_world(world, RADIUS, host)
	if not bool(full.get("ok", false)):
		_fail("bake_world failed: %s" % str(full.get("error", "")))
		_finish()
		return
	if not bake.save_bake().get("ok", false) and not bake.valid:
		# bake_world sets valid when complete; packages exist either way
		pass
	var path := bake.chunk_package_path(Vector2i.ZERO)
	if not FileAccess.file_exists(path):
		# save may not have run; bake_world writes packages directly
		_fail("bake_world did not write (0,0) package")
		_finish()
		return
	var bytes_a: PackedByteArray = FileAccess.get_file_as_bytes(path)
	_ok("bake_world package bytes=%d" % bytes_a.size())

	# Remove only the package and rebuild via _bake_one_chunk.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	bake.valid = false
	if bake.has_method("_inventory_existing_packages"):
		bake._inventory_existing_packages()
	var veg: Array = []
	if bake._veg_by_chunk.has(Vector2i.ZERO):
		veg = bake._veg_by_chunk[Vector2i.ZERO]
	var one: Dictionary = bake._bake_one_chunk(Vector2i.ZERO, world, host, veg)
	if not bool(one.get("ok", false)):
		_fail("_bake_one_chunk failed")
		_finish()
		return
	var bytes_b: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes_a.size() != bytes_b.size():
		_fail("package size mismatch bake_world=%d one=%d" % [bytes_a.size(), bytes_b.size()])
	elif bytes_a != bytes_b:
		_fail("package bytes differ for (0,0)")
	else:
		_ok("package bytes identical (%d) for (0,0)" % bytes_a.size())

	# Repeat _bake_one_chunk is stable.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var one2: Dictionary = bake._bake_one_chunk(Vector2i.ZERO, world, host, veg)
	var bytes_c: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if not bool(one2.get("ok", false)) or bytes_c != bytes_b:
		_fail("second _bake_one_chunk not stable")
	else:
		_ok("second _bake_one_chunk identical")

	_finish()


func _finish() -> void:
	if _failed > 0:
		_ProbeExit.finish_tree(self, 1, "Bake one-chunk parity FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All bake one-chunk parity tests OK")
