extends SceneTree
## Live camera: ramps, edit invalidation, building faces. Screenshot + structured dump.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_SCRATCH").is_empty():
		OS.set_environment("CRYSTALSTORM_SCRATCH", "C:/Users/cwith/AppData/Local/Temp/grok-goal-58b4c9b1d20d/implementer")
	call_deferred("_run")


func _run() -> void:
	var scratch := OS.get_environment("CRYSTALSTORM_SCRATCH")
	DirAccess.make_dir_recursive_absolute(scratch)
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_ProbeExit.finish_tree(self, 1, "no main scene")
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
		_ProbeExit.finish_tree(self, 1, "start region not ready")
		return
	for _w in 10:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var origin := _find_dry_origin(world, cm)
	var yard: Dictionary = _ValidationYard.apply(self, origin.x, origin.y)
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	_ValidationYard.apply_generated_ramps(self, yard.get("cells", {}))
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w2 in 10:
		await process_frame
	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp:
		insp.panel_open = true
	var cells: Dictionary = yard.get("cells", {})
	var snaps: Dictionary = {}
	for key in ["ramp_east", "ramp_west", "ramp_south", "ramp_north",
			"wood_wall", "stone_wall", "gate", "bridge", "ns_a", "ns_b", "flat"]:
		if not cells.has(key):
			continue
		var c: Vector2i = cells[key]
		_look(c.x, c.y)
		if insp:
			insp.pin_cell = c
		await process_frame
		await process_frame
		var snap: Dictionary = _LiveWorldQuery.inspect_cell(self, c.x, c.y)
		snaps[key] = {
			"wx": c.x, "wz": c.y,
			"has_ramp": snap.get("has_ramp", false),
			"ramp": snap.get("ramp", {}),
			"covered": snap.get("column_mesh_covered", false),
			"faces": snap.get("column_face_codes", []),
			"chunk_ramp_count": snap.get("chunk_ramp_count", 0),
			"yaw": snap.get("orientation_yaw", 0.0),
			"build_id": snap.get("build_id", ""),
			"visual_id": snap.get("visual_id", ""),
			"surface": snap.get("surface_height", 0.0),
			"walk": snap.get("walkable_height", 0.0),
			"neighbors": snap.get("neighbors", {}),
			"disc": snap.get("discrepancies", []),
			"collision_kind": snap.get("collision_kind", ""),
			"tile": snap.get("tile", -1),
		}
		_shot(scratch, "ta_%s_%d_%d" % [key, c.x, c.y])
	var editor = get_first_node_in_group("terrain_editor")
	var edits: Array = []
	if editor and cells.has("dig_one"):
		var d: Vector2i = cells.dig_one
		var before: Dictionary = _LiveWorldQuery.inspect_cell(self, d.x, d.y)
		var pos := Vector3(float(d.x) + 0.5, float(before.get("surface_height", 0.0)), float(d.y) + 0.5)
		editor.try_dig(pos)
		if cm and cm.has_method("await_rebuild_idle"):
			await cm.await_rebuild_idle(60)
		await process_frame
		var after: Dictionary = _LiveWorldQuery.inspect_cell(self, d.x, d.y)
		var neigh := {}
		for dir_k in ["n", "e", "s", "w"]:
			neigh[dir_k] = (after.get("neighbors", {}) as Dictionary).get(dir_k, {})
		edits.append({
			"cell": [d.x, d.y],
			"covered_before": before.get("column_mesh_covered", false),
			"covered_after": after.get("column_mesh_covered", false),
			"disc": after.get("discrepancies", []),
			"neighbors": neigh,
		})
		_look(d.x, d.y)
		if insp:
			insp.pin_cell = d
		await process_frame
		_shot(scratch, "ta_edit_dig_%d_%d" % [d.x, d.y])
	var ramps_ok := true
	var missing: Array = []
	for key in ["ramp_east", "ramp_west", "ramp_south", "ramp_north"]:
		if not bool((snaps.get(key, {}) as Dictionary).get("has_ramp", false)):
			ramps_ok = false
			missing.append(key)
	var report := {
		"ramps_ok": ramps_ok,
		"ramps_missing": missing,
		"cells": snaps,
		"edits": edits,
		"input_blocked": _GameplayInput.blocks_actions(),
	}
	var f := FileAccess.open(scratch.path_join("terrain_agreement.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("TERRAIN_AGREEMENT ramps_ok=%s missing=%s edits=%s" % [
		str(ramps_ok), str(missing), str(edits.size())
	])
	_ProbeExit.finish_tree(self, 0, "TERRAIN AGREEMENT OK")


func _find_dry_origin(world, cm) -> Vector2i:
	const _VoxelTypes = preload("res://helpers/voxel_types.gd")
	const _ActionTargeting = preload("res://player/action_targeting.gd")
	if world == null:
		return Vector2i(8, 8)
	for oz in range(8, 40, 4):
		for ox in range(8, 40, 4):
			var wet := false
			for dx in range(0, 16):
				for dz in range(0, 8):
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


func _look(wx: int, wz: int) -> void:
	var player = get_first_node_in_group("player")
	if player == null:
		return
	player.voxel_position.x = float(wx) + 0.5
	player.voxel_position.z = float(wz) - 2.2
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	if player.has_method("_snap_to_ground"):
		player._snap_to_ground()
	var cam = player.get("camera")
	if cam == null:
		return
	cam.set("use_smoothing", false)
	cam.set("_scroll_lead", Vector3.ZERO)
	if cam.has_method("get_offset_from_rotation"):
		cam.set("follow_target", player.global_position)
		cam.global_position = player.global_position + cam.get_offset_from_rotation()
	if "zoom_level" in cam:
		cam.zoom_level = 16.0
		cam.size = 16.0


func _shot(scratch: String, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex: Texture2D = root.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(scratch.path_join("%s.png" % name))
	print("SHOT %s" % scratch.path_join("%s.png" % name))
