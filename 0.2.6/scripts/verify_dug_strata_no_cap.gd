extends SceneTree
## Regression: 1-layer dig mesh must not place a horizontal cap at pre-dig natural height.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const FACE_TOP := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_TerrainEdits.reset()

	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 4242

	var dig_wx := 3
	var dig_wz := 5
	var natural_h: float = world.get_surface_height_worker(float(dig_wx), float(dig_wz), 0.0)
	if not _TerrainEdits.dig(dig_wx, dig_wz, 1):
		push_error("dig failed at (%d,%d)" % [dig_wx, dig_wz])
		quit(1)
		return

	var layer: float = _WorldSettings.get_active().layer_height()
	var edited_h: float = world.get_surface_height_worker(
		float(dig_wx), float(dig_wz), _TerrainEdits.get_height_delta(dig_wx, dig_wz)
	)
	if edited_h >= natural_h - layer * 0.05:
		push_error("dig should lower surface natural=%.2f edited=%.2f" % [natural_h, edited_h])
		failed = true

	var coord := Vector2i(
		floori(float(dig_wx) / float(_ChunkData.SIZE)),
		floori(float(dig_wz) / float(_ChunkData.SIZE))
	)
	var lx := dig_wx - coord.x * _ChunkData.SIZE
	var lz := dig_wz - coord.y * _ChunkData.SIZE

	var data := _ChunkData.new(coord, world)
	data.capture_worker_snapshot()
	data._compute_column_maps(true)

	var cm := _ChunkManager.new()
	var mesh: Dictionary = cm._build_mesh(data)
	var quads: Array = mesh.get("quads", [])
	var cap_at_natural := false
	var top_at_edited := false
	for q in quads:
		if int(q.get("face_code", -1)) != FACE_TOP:
			continue
		var qx: float = float(q.get("x", 0.0))
		var qz: float = float(q.get("z", 0.0))
		var qy: float = float(q.get("y", -999.0))
		var dim_x: float = float(q.get("dim_x", 1.0))
		var dim_z: float = float(q.get("dim_z", 1.0))
		var covers_dig := float(lx) >= qx and float(lx) < qx + dim_x \
				and float(lz) >= qz and float(lz) < qz + dim_z
		if not covers_dig:
			continue
		if is_equal_approx(qy, natural_h):
			cap_at_natural = true
		if is_equal_approx(qy, edited_h):
			top_at_edited = true

	if cap_at_natural:
		push_error("dug column still has FACE_TOP cap at natural_h=%.2f" % natural_h)
		failed = true
	elif not top_at_edited:
		push_error("dug column missing FACE_TOP at edited_h=%.2f" % edited_h)
		failed = true
	else:
		print("OK dug mesh top at edited=%.2f (natural was %.2f)" % [edited_h, natural_h])

	world = null
	cm = null
	_TerrainEdits.reset()

	if failed:
		quit(1)
	print("OK dug strata no natural cap")
	quit(0)