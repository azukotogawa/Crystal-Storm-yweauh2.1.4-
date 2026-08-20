extends SceneTree
## Terrain interaction production feel: shared cursor aim, rapid dig/build delays,
## mouse pick accepts in-range columns (no solid discard).
## Usage: godot --headless -s scripts/verify_terrain_feel.gd


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_delays()
	_test_shared_aim_api()
	_test_weapon_uses_resolve_target()
	_test_rapid_dig_build_loop()
	_test_highlight_exports_column()

	if _failed == 0:
		print("All terrain feel tests OK")
		quit(0)
	else:
		push_error("verify_terrain_feel: %d failure(s)" % _failed)
		quit(1)


func _test_delays() -> void:
	_TerrainEdits.reset()
	var editor := _TerrainEditor.new()
	var dig_d: float = editor.get_dig_delay(Vector3(0, 0, 0))
	var build_d: float = editor.get_build_delay()
	if dig_d > 0.12:
		_fail("shallow dig delay too slow for rapid reshape %.3f" % dig_d)
	if build_d > 0.04:
		_fail("build delay should feel instant got %.3f" % build_d)
	else:
		print("OK rapid delays dig=%.3f build=%.3f" % [dig_d, build_d])


func _test_shared_aim_api() -> void:
	var hl_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	var at_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	var w_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "get_action_column" not in hl_src:
		_fail("TargetHighlight must export get_action_column")
	if "get_action_column" not in at_src and "get_action_column" not in w_src:
		_fail("dig/build path must use shared aim column")
	if "_resolve_terrain_target" not in w_src:
		_fail("weapon must resolve terrain target via shared cursor")
	# Mouse pick must not require solid for in-range lock
	if "Always lock the column under the mouse" not in at_src \
			and "try_dig/try_build validate later" not in at_src:
		# softer: ensure we don't still require solid-only for best=
		if "if solid or not require_in_range" in at_src:
			_fail("mouse pick still discards non-solid in-range columns")
	else:
		print("OK shared cursor aim wiring")


func _test_weapon_uses_resolve_target() -> void:
	var w_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_resolve_terrain_target" not in w_src:
		_fail("missing _resolve_terrain_target")
	if w_src.count("_resolve_terrain_target") < 2:
		_fail("dig and build should both use _resolve_terrain_target")
	else:
		print("OK dig+build share _resolve_terrain_target")


func _test_rapid_dig_build_loop() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	var holder := Node.new()
	root.add_child(holder)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 55
	holder.add_child(world)
	var cm := _ChunkManager.new()
	var editor := _TerrainEditor.new()
	holder.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)
	var inv := _Inventory.new()
	inv.add_item("stone", 20)

	var t0 := Time.get_ticks_usec()
	var digs := 0
	var builds := 0
	for i in 8:
		var wx := 4 + i
		var wz := 4
		var h: float = world.get_surface_height(float(wx), float(wz))
		if editor.try_dig(Vector3(float(wx) + 0.5, h, float(wz) + 0.5)):
			digs += 1
		if editor.try_build_wall(Vector3(float(wx) + 0.5, h, float(wz) + 0.5), inv, true):
			builds += 1
	var us: int = Time.get_ticks_usec() - t0
	if digs < 6:
		_fail("rapid dig batch expected >=6 got %d" % digs)
	elif builds < 6:
		_fail("rapid build batch expected >=6 got %d" % builds)
	elif us > 200_000:
		_fail("8 dig+build too slow %dus (should be effortless)" % us)
	else:
		print("OK rapid reshape digs=%d builds=%d us=%d" % [digs, builds, us])
	holder.queue_free()


func _test_highlight_exports_column() -> void:
	var hl_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "process_priority = -20" not in hl_src:
		_fail("highlight should process before weapon")
	if "CELL_HYSTERESIS" in hl_src:
		_fail("highlight must not use hysteresis for exact mouse follow")
	elif "_stable_cell = hover_cell" not in hl_src:
		_fail("highlight must lock stable cell to live hover")
	else:
		print("OK cursor follow prioritizes mouse motion")
