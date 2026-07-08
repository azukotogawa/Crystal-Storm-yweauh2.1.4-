extends SceneTree

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

func _init() -> void:
	var failed := false
	for path in [
		"res://world/terrain_editor.gd",
		"res://world/terrain_edits.gd",
		"res://chunks/chunk_manager.gd",
		"res://chunks/chunk_data.gd",
		"res://helpers/terrain_ramps.gd",
		"res://player/player.gd",
		"res://player/voxel_floor_probe.gd",
		"res://weapons/weapon_controller.gd",
	]:
		var scr: GDScript = load(path) as GDScript
		if scr == null or scr.reload() != OK:
			push_error("FAIL compile %s" % path)
			failed = true
		else:
			print("OK ", path)

	_TerrainEdits.reset()
	var layer: float = _WorldSettings.get_active().layer_height()
	if not _TerrainEdits.dig(4, 6, 1):
		push_error("dig should succeed on playable cell")
		failed = true
	elif not is_equal_approx(_TerrainEdits.get_height_delta(4, 6), -layer):
		push_error("dig delta wrong got %s" % _TerrainEdits.get_height_delta(4, 6))
		failed = true
	else:
		print("OK terrain dig delta=", _TerrainEdits.get_height_delta(4, 6))

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 42
	var natural: float = world.get_surface_height_worker(4.0, 6.0, 0.0)
	var edited: float = world.get_surface_height_worker(4.0, 6.0, _TerrainEdits.get_height_delta(4, 6))
	if edited >= natural:
		push_error("edited surface should be below natural")
		failed = true
	else:
		print("OK dig lowers surface natural=", natural, " edited=", edited)

	var concave_h := TerrainRamps.walkable_height_from_entry(
		world,
		4.5,
		6.5,
		{"concave": true, "surface_h": 12.0, "dir": Vector2i(1, 0), "dir2": Vector2i(0, 1)}
	)
	if concave_h < 12.0 + layer * 0.5:
		push_error("concave walkable too low: %s" % concave_h)
		failed = true
	else:
		print("OK concave walkable=", concave_h)

	_TerrainEdits.reset()
	if failed:
		quit(1)
	print("All terrain dig tests OK")
	quit(0)