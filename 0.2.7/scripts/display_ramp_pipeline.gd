extends SceneTree
## Gameplay-camera proof of four cardinal wedges after resident remesh.

const MAIN_SCENE := "res://scenes/main.tscn"
const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _LiveWorldQuery = preload("res://helpers/live_world_query.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _ValidationYard = preload("res://world/validation_yard.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")


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
	for _w in 8:
		await process_frame
	var cm = get_first_node_in_group("chunk_manager")
	var world = get_first_node_in_group("world")
	var origin := _find_dry_origin(world, cm)
	var cells := {
		"ramp_east": origin + Vector2i(4, 0),
		"ramp_west": origin + Vector2i(7, 0),
		"ramp_south": origin + Vector2i(10, 0),
		"ramp_north": origin + Vector2i(13, 0),
	}
	_ValidationYard.apply_generated_ramps(self, cells)
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(120)
	for key in cells.keys():
		var c: Vector2i = cells[key]
		cm.remesh_resident_maps_at_world(float(c.x), float(c.y))
	if cm and cm.has_method("await_rebuild_idle"):
		await cm.await_rebuild_idle(90)
	for _w2 in 4:
		await process_frame
	var insp = game.get_node_or_null("LiveWorldInspector")
	if insp:
		insp.panel_open = true
	var snaps: Dictionary = {}
	for key in ["ramp_east", "ramp_west", "ramp_south", "ramp_north"]:
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
			"faces": snap.get("column_face_codes", []),
			"chunk_ramp_count": snap.get("chunk_ramp_count", 0),
			"surface": snap.get("surface_height", 0.0),
			"walk": snap.get("walkable_height", 0.0),
			"disc": snap.get("discrepancies", []),
			"mesh_source": (cm.chunks.get(Vector2i(int(floor(float(c.x) / 16.0)), int(floor(float(c.y) / 16.0)))) as Node).mesh_data.get("mesh_source", "") if cm.chunks.has(Vector2i(int(floor(float(c.x) / 16.0)), int(floor(float(c.y) / 16.0)))) else "",
			"column_source": "",
		}
		var ck := Vector2i(int(floor(float(c.x) / 16.0)), int(floor(float(c.y) / 16.0)))
		if cm.chunks.has(ck):
			var md: Dictionary = cm.chunks[ck].mesh_data
			snaps[key]["mesh_source"] = str(md.get("mesh_source", ""))
			snaps[key]["column_source"] = str(md.get("column_source", ""))
			snaps[key]["ramp_count"] = int(md.get("ramp_count", 0))
		_shot(scratch, "ramp_%s_%d_%d" % [key, c.x, c.y])
	var f := FileAccess.open(scratch.path_join("ramp_pipeline_live.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"origin": [origin.x, origin.y], "cells": snaps}, "\t"))
		f.close()
	print("RAMP_PIPELINE_LIVE %s" % str(snaps.keys()))
	_ProbeExit.finish_tree(self, 0, "RAMP PIPELINE LIVE OK")


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
		cam.zoom_level = 14.0
		cam.size = 14.0


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
