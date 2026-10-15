extends SceneTree

const MAIN_SCENE := "res://scenes/main.tscn"
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "no main")
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
		_ProbeExit.finish_tree(self, 1, "not ready")
		return
	for _w in 8:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var found := _find(cm)
	print("DUMP_FOUND cardinal=%s corner=%s" % [str(found.cardinal), str(found.corner)])
	if found.cardinal.x != -99999:
		_dump_around(cm, found.cardinal, "CARDINAL")
	if found.corner.x != -99999:
		_dump_around(cm, found.corner, "CORNER")
	_ProbeExit.finish_tree(self, 0, "DUMP OK")


func _dump_around(cm, center: Vector2i, tag: String) -> void:
	print("--- %s neighborhood %s ---" % [tag, str(center)])
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var wx: int = center.x + dx
			var wz: int = center.y + dz
			var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, wx, wz)
			var ramp: Dictionary = snap.get("ramp", {})
			var kind := "-"
			if bool(ramp.get("approach", false)):
				kind = "approach"
			elif bool(ramp.get("corner", false)):
				kind = "corner"
			elif bool(ramp.get("concave", false)) or bool(ramp.get("side", false)):
				kind = "concave/side"
			elif bool(snap.get("has_ramp", false)):
				kind = "cardinal"
			print("  %+d,%+d cell=%s surf=%.2f walk=%.2f kind=%s dir=%s dir2=%s faces=%s geom=%s" % [
				dx, dz, str(Vector2i(wx, wz)),
				float(snap.get("surf", snap.get("surface_height", 0.0))),
				float(snap.get("walk", snap.get("walkable_height", 0.0))),
				kind,
				str(ramp.get("dir", Vector2i.ZERO)),
				str(ramp.get("dir2", Vector2i.ZERO)),
				str(snap.get("column_face_codes")),
				str(snap.get("surface_geom")),
			])


func _find(cm) -> Dictionary:
	var out := {"cardinal": Vector2i(-99999, 0), "corner": Vector2i(-99999, 0)}
	if cm == null:
		return out
	for key_v in cm.chunks.keys():
		var coord: Vector2i = key_v
		var view = cm.chunks[coord]
		if view == null or view.chunk_data == null:
			continue
		var data = view.chunk_data
		for rk in data.ramp_map.keys():
			var local: Vector2i = rk
			var entry: Dictionary = data.ramp_map[rk]
			var wx: int = coord.x * _ChunkData.SIZE + local.x
			var wz: int = coord.y * _ChunkData.SIZE + local.y
			if bool(entry.get("approach", false)):
				continue
			if bool(entry.get("corner", false)) and out.corner.x == -99999:
				out.corner = Vector2i(wx, wz)
			elif not bool(entry.get("corner", false)) and not bool(entry.get("side", false)) \
					and not bool(entry.get("concave", false)) and out.cardinal.x == -99999:
				out.cardinal = Vector2i(wx, wz)
			if out.cardinal.x != -99999 and out.corner.x != -99999:
				return out
	return out
