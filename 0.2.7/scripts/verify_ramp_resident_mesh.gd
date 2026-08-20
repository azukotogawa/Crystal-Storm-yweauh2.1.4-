extends SceneTree
## Live resident path: stamped step survives remesh/flush and FACE_RAMP is on ChunkView.mesh_data.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")


const FACE_RAMP := 7


var _failed: int = 0


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	print("RAMP_RESIDENT_START")
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	var compose = game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _w in 8:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	if cm == null or world == null:
		_fail("missing world/chunk_manager")
		_finish()
		return
	var origin := _find_dry_origin(world, cm)
	var cells := {
		"ramp_east": origin + Vector2i(4, 0),
		"ramp_west": origin + Vector2i(7, 0),
		"ramp_south": origin + Vector2i(10, 0),
		"ramp_north": origin + Vector2i(13, 0),
	}
	var dirs := {
		"ramp_east": Vector2i(1, 0),
		"ramp_west": Vector2i(-1, 0),
		"ramp_south": Vector2i(0, 1),
		"ramp_north": Vector2i(0, -1),
	}
	_ValidationYard.apply_generated_ramps(self, cells)
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(120)
	for _w2 in 6:
		await process_frame
	var dumps_before: Dictionary = {}
	for key in cells.keys():
		dumps_before[key] = _dump_cell(cm, world, cells[key], dirs[key])
		_check_cell(key, dumps_before[key], "after_stamp")
	# Rebuild must not drop the wedge (same preserve remesh, then idle).
	for key in cells.keys():
		var c: Vector2i = cells[key]
		cm.remesh_resident_maps_at_world(float(c.x), float(c.y))
		cm.remesh_resident_maps_at_world(float((c + dirs[key]).x), float((c + dirs[key]).y))
	if cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(120)
	for _w3 in 4:
		await process_frame
	var dumps_after: Dictionary = {}
	for key in cells.keys():
		dumps_after[key] = _dump_cell(cm, world, cells[key], dirs[key])
		_check_cell(key, dumps_after[key], "after_rebuild")
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	if scratch.is_empty():
		scratch = "C:/Users/cwith/AppData/Local/Temp/grok-goal-58b4c9b1d20d/implementer"
	DirAccess.make_dir_recursive_absolute(scratch)
	var f := FileAccess.open(scratch.path_join("ramp_resident_dump.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"origin": [origin.x, origin.y],
			"after_stamp": dumps_before,
			"after_rebuild": dumps_after,
		}, "\t"))
		f.close()
	print("RAMP_RESIDENT origin=%s failed=%d" % [str(origin), _failed])
	_TerrainRamps.placement_chance = _TerrainRamps.PLACEMENT_CHANCE
	_finish()


func _check_cell(key: String, d: Dictionary, phase: String) -> void:
	if not bool(d.get("has_ramp", false)):
		_fail("%s %s ramp_map empty" % [phase, key])
	if int(d.get("face_ramp_quads", 0)) < 1:
		_fail("%s %s no FACE_RAMP in mesh_data.quads (faces=%s source=%s/%s)" % [
			phase, key, str(d.get("faces", [])),
			str(d.get("column_source", "")), str(d.get("mesh_source", ""))
		])
	var layer: float = _WorldSettings.get_active().layer_height()
	var surf: float = float(d.get("surface", 0.0))
	var walk: float = float(d.get("walk", 0.0))
	if absf(walk - (surf + layer * 0.5)) > layer * 0.35:
		_fail("%s %s walk %.2f not sloped vs surface %.2f" % [phase, key, walk, surf])
	else:
		print("OK %s %s ramp faces=%s walk=%.2f surf=%.2f col=%s mesh=%s" % [
			phase, key, str(d.get("faces")), walk, surf,
			str(d.get("column_source")), str(d.get("mesh_source"))
		])


func _dump_cell(cm, world, landing: Vector2i, toward_low: Vector2i) -> Dictionary:
	var SIZE := 16
	var chunk := Vector2i(
		int(floor(float(landing.x) / float(SIZE))),
		int(floor(float(landing.y) / float(SIZE)))
	)
	var lx: int = landing.x - chunk.x * SIZE
	var lz: int = landing.y - chunk.y * SIZE
	var approach: Vector2i = landing + toward_low
	var out := {
		"landing": [landing.x, landing.y],
		"approach": [approach.x, approach.y],
		"dir": [toward_low.x, toward_low.y],
		"chunk": [chunk.x, chunk.y],
		"local": [lx, lz],
	}
	if cm == null or not cm.chunks.has(chunk):
		out["error"] = "chunk_missing"
		return out
	var view = cm.chunks[chunk]
	var data = view.chunk_data if view else null
	if data == null:
		out["error"] = "no_data"
		return out
	var layer: float = _WorldSettings.get_active().layer_height()
	var land_h: float = float(data.surface_map[lx][lz])
	var ap_coord := Vector2i(
		int(floor(float(approach.x) / float(SIZE))),
		int(floor(float(approach.y) / float(SIZE)))
	)
	var ap_h := -1.0
	if cm.chunks.has(ap_coord):
		var ad = cm.chunks[ap_coord].chunk_data
		if ad:
			var alx: int = approach.x - ap_coord.x * SIZE
			var alz: int = approach.y - ap_coord.y * SIZE
			if alx >= 0 and alz >= 0 and alx < SIZE and alz < SIZE:
				ap_h = float(ad.surface_map[alx][alz])
	var entry: Dictionary = data.get_ramp_entry(lx, lz)
	var md: Dictionary = view.mesh_data if view else {}
	var faces: Array = []
	var ramp_n := 0
	for q_v in md.get("quads", []):
		var q: Dictionary = q_v
		if int(floor(float(q.get("x", -99.0)))) != lx or int(floor(float(q.get("z", -99.0)))) != lz:
			continue
		var fc: int = int(q.get("face_code", -1))
		faces.append(fc)
		if fc == FACE_RAMP:
			ramp_n += 1
	var walk := land_h + layer
	var rdir: Vector2i = entry.get("dir", toward_low) if not entry.is_empty() else toward_low
	if rdir != Vector2i.ZERO:
		walk = _TerrainRamps.surface_height_on_ramp(
			float(landing.x) + 0.5, float(landing.y) + 0.5, land_h, rdir
		)
	var neighbors := {}
	for nd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nwx: int = landing.x + nd.x
		var nwz: int = landing.y + nd.y
		var nck := Vector2i(int(floor(float(nwx) / float(SIZE))), int(floor(float(nwz) / float(SIZE))))
		var nh := -1.0
		if cm.chunks.has(nck):
			var ndata = cm.chunks[nck].chunk_data
			if ndata:
				var nlx: int = nwx - nck.x * SIZE
				var nlz: int = nwz - nck.y * SIZE
				if nlx >= 0 and nlz >= 0 and nlx < SIZE and nlz < SIZE:
					nh = float(ndata.surface_map[nlx][nlz])
		neighbors["%d,%d" % [nd.x, nd.y]] = nh
	out.merge({
		"surface": land_h,
		"approach_surface": ap_h,
		"neighbors": neighbors,
		"tile": int(data.tile_map[lx][lz]) if data.tile_map.size() > lx else -1,
		"has_ramp": data.has_ramp(lx, lz),
		"ramp_entry": entry.duplicate(true) if not entry.is_empty() else {},
		"faces": faces,
		"face_ramp_quads": ramp_n,
		"ramp_count": int(md.get("ramp_count", 0)),
		"column_source": str(md.get("column_source", "")),
		"mesh_source": str(md.get("mesh_source", "")),
		"quad_count": (md.get("quads", []) as Array).size(),
		"walk": walk,
		"preserve": bool(data.preserve_column_maps),
		"skip_cache": bool(data.skip_mesh_plan_cache),
	})
	return out


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 40, 4):
		for ox in range(8, 40, 4):
			var wet := false
			for dx in range(0, 16):
				for dz in range(0, 4):
					var tile: int = int(world.get_tile_type(float(ox + dx), float(oz + dz)))
					if tile in [_VoxelTypes.OCEAN, _VoxelTypes.OCEAN2, _VoxelTypes.OCEAN3, _VoxelTypes.RIVER, _VoxelTypes.WATER]:
						wet = true
						break
					if cm and not _ActionTargeting._is_solid_column(world, cm, ox + dx, oz + dz):
						wet = true
						break
				if wet:
					break
			if not wet:
				return Vector2i(ox, oz)
	return Vector2i(8, 8)


func _finish() -> void:
	if _failed == 0:
		print("All ramp resident mesh tests OK")
		_ProbeExit.finish_tree(self, 0, "All ramp resident mesh tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "Ramp resident mesh FAILED")
