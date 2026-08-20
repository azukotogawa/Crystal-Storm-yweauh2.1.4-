class_name ValidationYard
extends RefCounted
## Deterministic yard of ramps, structures, water, crystal, and edits for camera validation.

const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _TerrainRamps = preload("res://helpers/terrain_ramps.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _StructureOrientation = preload("res://helpers/structure_orientation.gd")


static func apply(tree: SceneTree, ox: int = 24, oz: int = 24) -> Dictionary:
	_BuildingRegistry.ensure_builtins()
	_TerrainRamps.placement_chance = 100
	var editor = tree.get_first_node_in_group("terrain_editor")
	var world = tree.get_first_node_in_group("world")
	var player = tree.get_first_node_in_group("player")
	if player and "inventory" in player and player.inventory:
		player.inventory.add_item("stone", 64)
		player.inventory.add_item("wood", 64)
	var cells := {
		"flat": Vector2i(ox, oz),
		"raised": Vector2i(ox + 2, oz),
		"ramp_east": Vector2i(ox + 4, oz),
		"ramp_west": Vector2i(ox + 7, oz),
		"ramp_south": Vector2i(ox + 10, oz),
		"ramp_north": Vector2i(ox + 13, oz),
		"wood_wall": Vector2i(ox, oz + 3),
		"stone_wall": Vector2i(ox + 2, oz + 3),
		"gate": Vector2i(ox + 4, oz + 3),
		"bridge": Vector2i(ox + 6, oz + 3),
		"adj_a": Vector2i(ox + 8, oz + 3),
		"adj_b": Vector2i(ox + 9, oz + 3),
		"ns_a": Vector2i(ox + 11, oz + 3),
		"ns_b": Vector2i(ox + 11, oz + 4),
		"water": Vector2i(ox, oz + 6),
		"crystal": Vector2i(ox + 3, oz + 6),
		"dig_one": Vector2i(ox + 8, oz + 6),
		"dig_adj": Vector2i(ox + 9, oz + 6),
		"slab": Vector2i(ox + 11, oz + 6),
	}
	# Raised column (player-built wall, not a ramp).
	_TerrainEdits.build_wall(cells.raised.x, cells.raised.y, _VoxelTypes.STONE)
	# Structures via gameplay editor when available.
	var inv = player.inventory if player and "inventory" in player else null
	if editor and editor.has_method("try_build"):
		_place(editor, cells.wood_wall, inv, &"wood_wall")
		_place(editor, cells.stone_wall, inv, &"stone_wall")
		_place(editor, cells.gate, inv, &"gate")
		_TerrainEdits.dig(cells.bridge.x, cells.bridge.y, 1)
		_place(editor, cells.bridge, inv, &"bridge")
		_place(editor, cells.adj_a, inv, &"wood_wall")
		_place(editor, cells.adj_b, inv, &"wood_wall")
		_place(editor, cells.ns_a, inv, &"stone_wall")
		_place(editor, cells.ns_b, inv, &"stone_wall")
	else:
		_stamp_build(cells.wood_wall, "wood_wall", true)
		_stamp_build(cells.stone_wall, "stone_wall", true)
		_stamp_build(cells.gate, "gate", false)
		_TerrainEdits.dig(cells.bridge.x, cells.bridge.y, 1)
		_stamp_build(cells.bridge, "bridge", true)
		_stamp_build(cells.adj_a, "wood_wall", true)
		_stamp_build(cells.adj_b, "wood_wall", true)
		_stamp_build(cells.ns_a, "stone_wall", true)
		_stamp_build(cells.ns_b, "stone_wall", true)
	if editor and editor.has_method("try_channel_water"):
		var wy: float = world.get_surface_height(float(cells.water.x), float(cells.water.y)) if world else 0.0
		editor.try_channel_water(Vector3(float(cells.water.x) + 0.5, wy, float(cells.water.y) + 0.5), inv)
	else:
		_TerrainEdits.dig(cells.water.x, cells.water.y, 1)
	_seed_crystal(tree, cells.crystal)
	# Edit sequence cells (applied later by the display probe so coverage can be compared).
	if editor:
		for key in ["flat", "raised", "wood_wall", "stone_wall", "gate", "bridge", "water", "crystal", "dig_one"]:
			var c: Vector2i = cells[key]
			if editor.has_method("_invalidate_and_rebuild"):
				editor._invalidate_and_rebuild(c.x, c.y)
	# Generated ramps are applied after structure rebuilds idle — see apply_generated_ramps.
	if player and player.has_method("_sync_global_from_voxel"):
		player.voxel_position.x = float(ox) + 0.5
		player.voxel_position.z = float(oz) - 2.5
		player.call("_sync_global_from_voxel")
		if player.has_method("_snap_to_ground"):
			player.call("_snap_to_ground")
	return {"origin": Vector2i(ox, oz), "cells": cells}


static func apply_generated_ramps(tree: SceneTree, cells: Dictionary) -> void:
	_TerrainRamps.placement_chance = 100
	var remesh: Dictionary = {}
	_stamp_generated_step_maps(tree, cells.ramp_east, Vector2i(1, 0), remesh)
	_stamp_generated_step_maps(tree, cells.ramp_west, Vector2i(-1, 0), remesh)
	_stamp_generated_step_maps(tree, cells.ramp_south, Vector2i(0, 1), remesh)
	_stamp_generated_step_maps(tree, cells.ramp_north, Vector2i(0, -1), remesh)
	var cm = tree.get_first_node_in_group("chunk_manager")
	if cm:
		if "ramp_placement_chance" in cm:
			cm.ramp_placement_chance = 100
		for key_v in remesh.keys():
			var cell: Vector2i = key_v
			if cm.has_method("remesh_resident_maps_at_world"):
				cm.remesh_resident_maps_at_world(float(cell.x), float(cell.y))


static func _place(editor, cell: Vector2i, inv, build_id: StringName) -> void:
	var world = editor.world
	var y := 0.0
	if world:
		y = world.get_surface_height(float(cell.x), float(cell.y))
	editor.try_build(Vector3(float(cell.x) + 0.5, y, float(cell.y) + 0.5), inv, build_id)


static func _stamp_build(cell: Vector2i, build_id: String, raise: bool) -> void:
	if raise:
		_TerrainEdits.build_wall(cell.x, cell.y, _VoxelTypes.DIRT if build_id != "stone_wall" else _VoxelTypes.STONE)
	else:
		_TerrainEdits.set_build_tile_only(cell.x, cell.y, _VoxelTypes.DIRT)
	_FeatureRegistry.register_feature(cell.x, cell.y, _WorldFeatureTypes.FeatureKind.NONE, {
		"build_id": build_id,
		"player_built": true,
		"is_passage": build_id == "gate",
		"is_bridge": build_id == "bridge",
		"raises_terrain": raise,
	})
	_StructureOrientation.persist_yaw_neighborhood(cell.x, cell.y)


static func _stamp_generated_step_maps(
	tree: SceneTree, landing: Vector2i, toward_low: Vector2i, remesh: Dictionary
) -> void:
	var cm = tree.get_first_node_in_group("chunk_manager")
	if cm == null:
		return
	var layer: float = load("res://config/world_settings.gd").get_active().layer_height()
	var approach := landing + toward_low
	for cell in [landing, approach]:
		var coord := Vector2i(
			int(floor(float(cell.x) / float(16))),
			int(floor(float(cell.y) / float(16)))
		)
		if not cm.chunks.has(coord):
			continue
		var data = cm.chunks[coord].chunk_data
		if data == null:
			continue
		var lx: int = cell.x - coord.x * 16
		var lz: int = cell.y - coord.y * 16
		if lx < 0 or lz < 0 or lx >= 16 or lz >= 16:
			continue
		if cell == approach:
			data.surface_map[lx][lz] = float(data.surface_map[lx][lz]) - layer
		remesh[cell] = true


static func _seed_crystal(tree: SceneTree, cell: Vector2i) -> void:
	var crystal = tree.get_first_node_in_group("crystal_manager")
	if crystal == null:
		return
	if "_sim" in crystal and crystal._sim and crystal._sim.has_method("set_depth"):
		crystal._sim.set_depth(cell, 0.55, 0, true)
	if crystal.has_method("_refresh_crystal_floor_near"):
		crystal._refresh_crystal_floor_near(cell.x, cell.y, 1)
