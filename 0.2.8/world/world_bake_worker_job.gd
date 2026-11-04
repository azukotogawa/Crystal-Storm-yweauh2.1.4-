class_name WorldBakeWorkerJob
extends RefCounted
## Must not touch Nodes, scene tree, live WorldState overlays, crystal, or water.

const CELLS := 16
const CELLS2 := CELLS * CELLS


static func execute(coord: Vector2i, world, mesh_host, veg: Array, writer) -> Dictionary:
	var t_all := Time.get_ticks_usec()
	var out := {
		"ok": false,
		"bytes": 0,
		"plan_qn": 0,
		"coord": coord,
		"sample_us": 0,
		"mesh_us": 0,
		"write_us": 0,
		"total_us": 0,
		"main_thread": OS.get_thread_caller_id() == OS.get_main_thread_id(),
	}
	if world == null or mesh_host == null or not mesh_host.has_method("_build_mesh") or writer == null:
		return out
	if not writer.has_method("_apply_pack_to_data") or not writer.has_method("_write_chunk_package"):
		return out
	var surface := PackedFloat32Array()
	var tiles := PackedInt32Array()
	surface.resize(CELLS2)
	tiles.resize(CELLS2)
	var t_sample := Time.get_ticks_usec()
	var i := 0
	for lz in CELLS:
		for lx in CELLS:
			var wx := float(coord.x * CELLS + lx)
			var wz := float(coord.y * CELLS + lz)
			surface[i] = float(world.get_surface_height_worker(wx, wz, 0.0))
			tiles[i] = int(world.get_tile_type_worker(wx, wz, -1, -1))
			i += 1
	out["sample_us"] = Time.get_ticks_usec() - t_sample
	# v123+: no mesh plan at bake time; it is built at load by build_plan().
	var plan: Array = []
	var t_write := Time.get_ticks_usec()
	var wbytes: int = int(writer._write_chunk_package(coord, surface, tiles, plan, veg))
	out["write_us"] = Time.get_ticks_usec() - t_write
	out["ok"] = wbytes > 0
	out["bytes"] = wbytes
	out["plan_qn"] = plan.size()
	out["total_us"] = Time.get_ticks_usec() - t_all
	out["main_thread"] = OS.get_thread_caller_id() == OS.get_main_thread_id()
	return out


## Mesh plan for one chunk from its stored columns. Same inputs the bake used
## when plans were stored (v122): base-only world snapshot, baked vegetation
## feature tiles, surface and tiles applied through the writer.
static func build_plan(coord: Vector2i, world, mesh_host, surface: PackedFloat32Array, tiles: PackedInt32Array, veg: Array, writer) -> Array:
	var _ChunkData = load("res://chunks/chunk_data.gd")
	var data = _ChunkData.new(coord, world)
	if data.has_method("capture_base_only_snapshot"):
		data.capture_base_only_snapshot()
	else:
		data.capture_worker_snapshot()
	for item_v in veg:
		if not item_v is Dictionary:
			continue
		var item: Dictionary = item_v
		var lx2: int = int(item.get("lx", -1))
		var lz2: int = int(item.get("lz", -1))
		var tile_id: int = int(item.get("tile", -1))
		if tile_id >= 0 and data.has_method("set_worker_feature_tile"):
			data.set_worker_feature_tile(lx2, lz2, tile_id, true)
	writer._apply_pack_to_data(data, surface, tiles)
	if data.has_method("_bind_macro_surface_if_needed"):
		data._bind_macro_surface_if_needed()
	var built: Dictionary = mesh_host._build_mesh(data)
	var quads: Array = built.get("quads", [])
	var plan: Array = []
	plan.resize(quads.size())
	for qi in quads.size():
		plan[qi] = (quads[qi] as Dictionary).duplicate(true)
	return plan
