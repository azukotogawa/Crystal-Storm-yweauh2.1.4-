extends SceneTree
## Macro/Micro + save contract:
## - generation fills macro authority
## - dig allocates sparse micro bricks (not stored in saves)
## - v1→v2 migrate preserves height_delta; load re-derives micro
## Usage: godot --headless -s scripts/verify_macro_micro_save_migrate.gd


const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ChunkDataPool = preload("res://helpers/chunk_data_pool.gd")
const _MacroLayerGrid = preload("res://helpers/macro_layer_grid.gd")
const _MicroLayerGrid = preload("res://helpers/micro_layer_grid.gd")
const _SaveSchema = preload("res://systems/save_schema.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldState = preload("res://world/world_state.gd")


var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_MACRO_TERRAIN", "1")
	OS.set_environment("CRYSTALSTORM_MICRO_TERRAIN", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	if not _MacroLayerGrid.enabled() or not _MicroLayerGrid.enabled():
		_fail("macro and micro must be enabled for this verify")
		_finish()
		return

	_test_gen_macro_no_micro()
	_test_dig_micro_not_in_export()
	_test_v1_migrate_rederive_micro()
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("All macro/micro save migrate tests OK")
		quit(0)
	else:
		push_error("verify_macro_micro_save_migrate: %d failure(s)" % _failed)
		quit(1)


func _make_chunk(seed: int, coord: Vector2i = Vector2i(0, 0)) -> ChunkData:
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = seed
	var data: ChunkData = _ChunkDataPool.acquire(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)
	data.prewarm_macro_storage()
	return data


func _test_gen_macro_no_micro() -> void:
	_TerrainEdits.reset()
	var data := _make_chunk(4242)
	if data.macro_grid == null or not data.macro_grid.is_ready():
		_fail("generation must bind ready macro grid")
	elif data.micro_grid != null and data.micro_grid.brick_count() > 0:
		_fail("pristine generation must not allocate micro bricks")
	else:
		# Sample façade vs macro authority on a few columns
		var ok := true
		for cell in [Vector2i(0, 0), Vector2i(7, 7), Vector2i(15, 15)]:
			if not is_equal_approx(
				data.get_surface_y(cell.x, cell.y),
				data.macro_grid.get_surface_y(cell.x, cell.y)
			):
				ok = false
				_fail("façade surface_y must read macro at %s" % cell)
		if ok:
			print("OK generation uses macro authority (no micro on pristine)")
	_ChunkDataPool.release(data)


func _test_dig_micro_not_in_export() -> void:
	_TerrainEdits.reset()
	var wx := 4
	var wz := 4
	if not _TerrainEdits.dig(wx, wz, 1):
		_fail("dig failed")
		return

	var data := _make_chunk(4242)
	data.refresh_worker_snapshot_for_cells([Vector2i(wx, wz)])
	data.update_dirty_column_maps([Vector2i(wx, wz)])
	if not data.has_micro_brick(wx, wz):
		_fail("dig must allocate micro brick")
	elif data.macro_grid == null or not data.macro_grid.has_micro_flag(wx, wz):
		_fail("FLAG_MICRO_PRESENT required after dig")
	else:
		print("OK dig allocates micro brick + FLAG_MICRO_PRESENT")

	var bundle: Dictionary = _WorldState.get_active().export_persistence_bundle()
	var encoded := JSON.stringify(bundle)
	for banned in ["micro_brick", "micro_grid", "bricks", "FLAG_MICRO"]:
		if encoded.find(banned) >= 0:
			_fail("persistence bundle must not serialize %s" % banned)
	if not bundle.has("height_delta"):
		_fail("export must store height_delta")
	else:
		var hd: Dictionary = bundle.get("height_delta", {})
		var key := "%d,%d" % [wx, wz]
		# Codec may use "4,4" string keys
		var found := false
		for k in hd.keys():
			if str(k) == key or (k is Vector2i and k == Vector2i(wx, wz)):
				found = true
				if int(hd[k]) >= 0:
					_fail("height_delta for dig must be negative layers")
				break
		if not found:
			# try vec2i key directly
			if int(hd.get(Vector2i(wx, wz), 0)) >= 0 and not hd.has(Vector2i(wx, wz)):
				_fail("height_delta missing dug column %s keys=%s" % [key, str(hd.keys())])
			elif hd.has(Vector2i(wx, wz)) and int(hd[Vector2i(wx, wz)]) < 0:
				found = true
		if found or (hd.has(Vector2i(wx, wz)) and int(hd[Vector2i(wx, wz)]) < 0):
			print("OK save stores height_delta only (no micro bricks)")

	_ChunkDataPool.release(data)


func _test_v1_migrate_rederive_micro() -> void:
	_TerrainEdits.reset()
	# Legacy v1 save: one dug column at world (6, 8)
	var v1 := {
		"version": 1,
		"world_seed": 4242,
		"terrain_edits": {
			"height_delta": {"6,8": -2},
			"build_tile": {},
		},
		"features": {
			"tile_overrides": {},
			"feature_cells": {},
		},
		"channels": {"channels": {}},
	}
	var mig: Dictionary = _SaveSchema.validate_and_migrate(v1)
	if not bool(mig.get("ok", false)):
		_fail("v1 migrate failed: %s" % str(mig.get("reason")))
		return
	var data_mig: Dictionary = mig.get("data", {})
	if int(data_mig.get("schema_version", 0)) != _SaveSchema.CURRENT_VERSION:
		_fail("migrated schema_version wrong")
		return
	var ws_block: Dictionary = data_mig.get("world_state", {})
	if not ws_block.has("height_delta"):
		_fail("migrated world_state missing height_delta")
		return

	# Apply migrated world_state as production load does
	_WorldState.get_active().import_persistence_bundle(ws_block)
	var layers: int = int(_WorldState.get_active().height_delta.get(Vector2i(6, 8), 0))
	if layers != -2:
		_fail("import after migrate height_delta want -2 got %d" % layers)
		return
	print("OK v1→v2 migrate + import height_delta=-2 at (6,8)")

	# Chunk rebuild path re-derives micro from overlays (same as generate_chunk)
	var data := _make_chunk(4242)
	data.derive_micro_from_terrain_edits()
	var lx := 6
	var lz := 8
	if not data.has_micro_brick(lx, lz):
		_fail("load rebuild must re-derive micro brick from height_delta")
	elif data.macro_grid == null or not data.macro_grid.has_micro_flag(lx, lz):
		_fail("re-derived micro must set FLAG_MICRO_PRESENT")
	else:
		var brick = data.micro_grid.get_brick(lx, lz)
		if brick == null or int(brick.dug_layers) < 1:
			_fail("re-derived brick should record dig layers")
		else:
			print(
				"OK load re-derives micro brick dug_layers=%d at local (%d,%d)"
				% [int(brick.dug_layers), lx, lz]
			)

	# Untouched column stays macro-only
	if data.has_micro_brick(1, 1):
		_fail("non-edited column must not gain micro after migrate re-derive")
	else:
		print("OK micro remains sparse after save restore")

	_ChunkDataPool.release(data)
	_TerrainEdits.reset()
