extends SceneTree
## Dirty-region water gather: sleep when idle, never scan the whole channel map.

const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _CrystalTerrainQuery = preload("res://crystal/crystal_terrain_query.gd")
const _FluidRegistry = preload("res://helpers/fluid_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _VoxelFluidService = preload("res://fluids/voxel_fluid_service.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_FluidRegistry.ensure_builtins()

	var svc: Node = _VoxelFluidService.new()
	root.add_child(svc)
	await process_frame
	if svc.get("_water_engine") == null:
		_fail("water engine missing after ready")
		_finish()
		return

	var heights: Dictionary = {}
	for x in 64:
		for z in 8:
			heights[Vector2i(x, z)] = 10.0
	heights[Vector2i(3, 2)] = 8.0
	var query: _CrystalTerrainQuery = svc.get("_terrain_query")
	if query:
		query.test_base_heights = heights

	for x in 500:
		_ChannelRegistry.register_channel(x, 0, Vector2i(1, 0), 0.6)

	svc.set("_dirty_cells", {})
	var t0 := Time.get_ticks_usec()
	svc.call("_tick_water", 0.1)
	var idle_us: int = Time.get_ticks_usec() - t0
	var idle_diag: Dictionary = svc.call("get_sim_diagnostics")
	if not bool(idle_diag.get("sleeping", false)):
		_fail("idle tick should sleep when dirty is empty")
	if int(idle_diag.get("subset_cells", -1)) != 0:
		_fail("idle tick must not load a subset (got %s)" % str(idle_diag.get("subset_cells")))
	if bool(idle_diag.get("loads_all_channels_each_tick", true)):
		_fail("loads_all_channels_each_tick must be false")
	if str(idle_diag.get("active_gate", "")) != "dirty_region":
		_fail("active_gate should be dirty_region")
	if idle_us > 2000:
		_fail("idle _tick_water took %d us; expected a no-scan sleep" % idle_us)
	else:
		print("OK idle sleep %d us subset=%s overlay=%s" % [
			idle_us, str(idle_diag.get("subset_cells")), str(idle_diag.get("channel_cells"))
		])

	svc.call("mark_region_dirty", 2, 2, 1)
	var dirty_n: int = int((svc.get("_dirty_cells") as Dictionary).size())
	if dirty_n <= 0 or dirty_n > 80:
		_fail("local mark_region_dirty should stay small, got %d" % dirty_n)

	t0 = Time.get_ticks_usec()
	svc.call("_tick_water", 0.1)
	var local_us: int = Time.get_ticks_usec() - t0
	var local_diag: Dictionary = svc.call("get_sim_diagnostics")
	var subset_n: int = int(local_diag.get("subset_cells", 0))
	if subset_n <= 0:
		_fail("dirty tick should load a local subset")
	if subset_n > 120:
		_fail("local subset too large (%d); gather is not region-limited" % subset_n)
	if local_us > 8000:
		_fail("local _tick_water took %d us for subset %d" % [local_us, subset_n])
	else:
		print("OK local gather subset=%d dirty=%d us=%d" % [
			subset_n, dirty_n, local_us
		])
	var phases: Dictionary = local_diag.get("phase_us", {})
	for key in ["gather", "copy", "sim", "persist", "visual", "tick_total"]:
		if not phases.has(key):
			_fail("get_sim_diagnostics missing phase_us.%s" % key)
	if int(local_diag.get("registry_reads", -1)) != subset_n:
		_fail("registry_reads should match subset, got %s subset=%d" % [
			str(local_diag.get("registry_reads")), subset_n
		])
	else:
		print("OK phases gather=%s copy=%s sim=%s persist=%s visual=%s" % [
			str(phases.get("gather")), str(phases.get("copy")), str(phases.get("sim")),
			str(phases.get("persist")), str(phases.get("visual"))
		])

	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	_ChannelRegistry.register_channel(2, 2, Vector2i(1, 0), 0.85)
	_ChannelRegistry.register_channel(3, 2, Vector2i.ZERO, 0.08)
	svc.set("_dirty_cells", {})
	svc.call("recompute_region_now", 2, 2, 2, 10)
	var dest: float = _ChannelRegistry.get_water_level(3, 2)
	var src: float = _ChannelRegistry.get_water_level(2, 2)
	if dest <= 0.12:
		_fail("recompute_region_now should move water downhill dest=%.3f src=%.3f" % [dest, src])
	else:
		print("OK local reflow dest=%.3f src=%.3f" % [dest, src])

	# A river-tile field must not become a 3000-cell dirty wave.
	_ChannelRegistry.reset()
	_TerrainEdits.reset()
	svc.world = null
	svc.set("_dirty_cells", {})
	svc.call("mark_region_dirty", 2, 2, 8)
	svc.call("_tick_water", 0.1)
	var river_diag: Dictionary = svc.call("get_sim_diagnostics")
	if int(river_diag.get("subset_cells", 0)) > 400:
		_fail("river-adjacent dirty gather exploded to subset=%s" % str(river_diag.get("subset_cells")))
	else:
		print("OK no-world river gather subset=%s dirty=%s" % [
			str(river_diag.get("subset_cells")), str(river_diag.get("dirty_cells"))
		])

	# Walking must not gather the overlay. Only edits mark dirty.
	svc.set("_dirty_cells", {})
	var dummy := Node3D.new()
	dummy.add_to_group("player")
	var vs: float = _WorldSettings.get_active().voxel_scale
	dummy.position = Vector3(2.4 * vs, 10.0, 2.1 * vs)
	root.add_child(dummy)
	await process_frame
	await process_frame
	var woke: int = int((svc.get("_dirty_cells") as Dictionary).size())
	if woke != 0:
		_fail("player motion must not mark dirty, got %d" % woke)
	else:
		print("OK player motion dirty=0 (edit-driven only)")

	_finish()


func _finish() -> void:
	if _failed == 0:
		print("All water active-region tests OK")
		quit(0)
	else:
		push_error("verify_water_active_region: %d failure(s)" % _failed)
		quit(1)
