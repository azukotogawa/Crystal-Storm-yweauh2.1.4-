extends SceneTree

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
	var cells := _ValidationYard.cardinal_ramp_cells(origin)
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
		var toward: Vector2i = {
			"ramp_east": Vector2i(1, 0),
			"ramp_west": Vector2i(-1, 0),
			"ramp_south": Vector2i(0, 1),
			"ramp_north": Vector2i(0, -1),
		}[key]
		var approach: Vector2i = c + toward
		_look(approach.x, approach.y)
		await process_frame
		var ap: Dictionary = _LiveWorldQuery.inspect_cell(self, approach.x, approach.y)
		snaps[key]["approach"] = {
			"wx": approach.x, "wz": approach.y,
			"covered": ap.get("column_mesh_covered", false),
			"faces": ap.get("column_face_codes", []),
			"has_ramp": ap.get("has_ramp", false),
			"walk": ap.get("walkable_height", 0.0),
			"surf": ap.get("surface_height", 0.0),
			"disc": ap.get("discrepancies", []),
		}
		_shot(scratch, "approach_%s_%d_%d" % [key, approach.x, approach.y])
		if not bool(ap.get("column_mesh_covered", false)):
			push_error("approach floor missing for %s at %s" % [key, approach])
			_ProbeExit.finish_tree(self, 1, "RAMP PIPELINE LIVE FAILED")
			return
		print("OK approach floor %s covered faces=%s" % [key, str(ap.get("column_face_codes", []))])
	var editor = get_first_node_in_group("terrain_editor")
	var player = get_first_node_in_group("player")
	if editor and player and player.inventory:
		player.inventory.add_item("stone", 8)
		var dig_c: Vector2i = origin + Vector2i(2, 2)
		var far_c: Vector2i = origin + Vector2i(2, 8)
		var far_before: Dictionary = _LiveWorldQuery.inspect_cell(self, far_c.x, far_c.y)
		var y0: float = world.get_surface_height(float(dig_c.x), float(dig_c.y))
		editor.try_dig(Vector3(float(dig_c.x) + 0.5, y0, float(dig_c.y) + 0.5))
		if cm.has_method("await_rebuild_idle"):
			await cm.await_rebuild_idle(90)
		for _wd in 4:
			await process_frame
		_look(dig_c.x, dig_c.y)
		await process_frame
		_shot(scratch, "dig_local_%d_%d" % [dig_c.x, dig_c.y])
		_look(far_c.x, far_c.y)
		await process_frame
		_shot(scratch, "dig_far_%d_%d" % [far_c.x, far_c.y])
		var far_after: Dictionary = _LiveWorldQuery.inspect_cell(self, far_c.x, far_c.y)
		if bool(far_before.get("column_mesh_covered", false)) and not bool(far_after.get("column_mesh_covered", false)):
			push_error("dig at %s uncovered far cell %s" % [dig_c, far_c])
			_ProbeExit.finish_tree(self, 1, "RAMP PIPELINE LIVE FAILED")
			return
		print("OK interior dig did not uncover far cell %s" % str(far_c))
	var f := FileAccess.open(scratch.path_join("ramp_pipeline_live.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"origin": [origin.x, origin.y], "cells": snaps}, "\t"))
		f.close()
	print("RAMP_PIPELINE_LIVE %s" % str(snaps.keys()))
	_ProbeExit.finish_tree(self, 0, "RAMP PIPELINE LIVE OK")


func _walk_slope_gap(world, cm, landing: Vector2i, toward_low: Vector2i) -> String:
	var _TerrainRamps = load("res://helpers/terrain_ramps.gd")
	var layer: float = load("res://config/world_settings.gd").get_active().layer_height()
	var ax := float(landing.x + toward_low.x) + 0.5
	var az := float(landing.y + toward_low.y) + 0.5
	var lx := float(landing.x) + 0.5
	var lz := float(landing.y) + 0.5
	var prev := -9999.0
	for i in 11:
		var t: float = float(i) / 10.0
		var wx: float = lerpf(ax, lx, t)
		var wz: float = lerpf(az, lz, t)
		var h: float = _TerrainRamps.walkable_height(world, wx, wz)
		if cm and cm.has_method("get_ramp_entry_at_world"):
			h = _TerrainRamps.walkable_height_from_entry(world, wx, wz, cm.get_ramp_entry_at_world(wx, wz))
		if prev > -9000.0 and (prev - h) > layer * 0.55:
			return "walk gap %.2f→%.2f at t=%.1f landing=%s" % [prev, h, t, landing]
		prev = h
	print("OK slope walk %s Δh continuous" % str(landing))
	return ""


func _find_dry_origin(world, cm) -> Vector2i:
	if world == null:
		return Vector2i(8, 8)
	var anchor := Vector2i(8, 8)
	var player = get_first_node_in_group("player")
	if player != null:
		anchor = Vector2i(floori(player.voxel_position.x / 16.0) * 16 - 16, floori(player.voxel_position.z / 16.0) * 16 - 16)
	for oz in range(anchor.y, anchor.y + 32, 4):
		for ox in range(anchor.x, anchor.x + 32, 4):
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
	return anchor


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
