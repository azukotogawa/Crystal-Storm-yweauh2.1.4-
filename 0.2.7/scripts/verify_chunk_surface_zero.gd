extends SceneTree
## Regression: lowest surface columns must receive a top/ramp surface quad (not culled).


const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")

const FACE_TOP := 0
const FACE_RAMP := 7
const FACE_RAMP_CORNER := 8


func _init() -> void:
	call_deferred("_run")


func _quad_covers_cell(q: Dictionary, lx: int, lz: int, sy: float) -> bool:
	var fc: int = int(q.get("face_code", -1))
	if fc != FACE_TOP and fc != FACE_RAMP and fc != FACE_RAMP_CORNER:
		return false
	if int(q.get("x", -1)) != lx or int(q.get("z", -1)) != lz:
		return false
	return is_equal_approx(float(q.get("y", -1.0)), sy)


func _run() -> void:
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = 77

	var min_h := INF
	var candidates: Array = []
	for wx in range(-128, 128):
		for wz in range(-128, 128):
			var h: float = world.get_surface_height(float(wx), float(wz))
			if h < min_h - 0.001:
				min_h = h
				candidates = [Vector2i(wx, wz)]
			elif is_equal_approx(h, min_h):
				candidates.append(Vector2i(wx, wz))

	var cm := _ChunkManager.new()
	var found := Vector2i.ZERO
	var found_h := min_h
	var has_surface := false
	var quads: Array = []

	for cand_variant in candidates:
		var cand: Vector2i = cand_variant
		var coord := Vector2i(
			floori(float(cand.x) / float(_ChunkData.SIZE)),
			floori(float(cand.y) / float(_ChunkData.SIZE))
		)
		var lx := cand.x - coord.x * _ChunkData.SIZE
		var lz := cand.y - coord.y * _ChunkData.SIZE

		var data := _ChunkData.new(coord, world)
		data.capture_worker_snapshot()
		data._compute_column_maps(true)
		var sy: float = data.get_surface_y(lx, lz)
		if not is_equal_approx(sy, min_h):
			continue

		var mesh: Dictionary = cm._build_mesh(data)
		quads = mesh.get("quads", [])
		for q in quads:
			if _quad_covers_cell(q, lx, lz, sy):
				has_surface = true
				found = cand
				found_h = sy
				break
		if has_surface:
			break

	if not has_surface:
		push_error(
			"no surface quad at lowest surface_y=%.2f among %d columns"
			% [min_h, candidates.size()]
		)
		quit(1)
		return

	print(
		"OK chunk meshes lowest surface_y=%.2f at %s (quad count=%d)"
		% [found_h, found, quads.size()]
	)
	quit(0)