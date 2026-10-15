extends SceneTree

const _ActionTargeting = preload("res://player/action_targeting.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _ok(msg: String) -> void:
	print("OK %s" % msg)


func _run() -> void:
	if absf(_ActionTargeting.INTERACTION_RANGE - 8.0) > 0.001:
		_fail("interaction range changed")
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	root.add_child(world)
	await process_frame
	var cell := _find_land(world)
	var neighbor := Vector2i(cell.x - 1, cell.y)
	var ws = _WorldSettings.get_active()
	var scale: float = ws.voxel_scale
	var layer: float = ws.layer_height()
	var surf: float = world.get_surface_height(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var top: float = surf + layer
	var player := _Dummy.new()
	player.voxel_position = Vector3(float(cell.x) + 0.5, surf, float(cell.y) + 0.5)
	root.add_child(player)

	var slab: Vector2 = _ActionTargeting._surface_slab_bounds(world, null, cell.x, cell.y)
	var center := Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		slab.x + (slab.y - slab.x) * 0.35,
		ws.column_to_world(float(cell.y) + 0.5)
	)
	var above := Vector3(center.x + scale * 0.04, slab.y + 8.0, center.z - scale * 0.03)
	var down: Dictionary = _ActionTargeting.pick_along_ray(
		above, Vector3.DOWN, player, world, null, 8.0, true
	)
	if not _is_cell(down, cell) or not bool(down.get("exact", false)) or int(down.get("face", -1)) != 0:
		_fail("exact top ray %s face %s exact %s" % [down.get("column"), down.get("face"), down.get("exact")])
	else:
		_ok("exact ray keeps the cell and the top face")

	var from_edge := Vector3(
		ws.column_to_world(float(cell.x) + 0.82),
		slab.y + 6.0,
		center.z
	)
	var kept: Dictionary = _ActionTargeting.pick_along_ray(
		from_edge, Vector3.DOWN, player, world, null, 8.0, true
	)
	if not _is_cell(kept, cell) or not bool(kept.get("exact", false)):
		_fail("exact hit was retargeted to %s exact %s" % [kept.get("column"), kept.get("exact")])
	else:
		_ok("exact hit is not retargeted")

	var skim_from := Vector3(center.x, slab.y + scale * 0.2, center.z)
	var skim: Dictionary = _ActionTargeting.pick_along_ray(
		skim_from, Vector3.UP, player, world, null, 8.0, true
	)
	if not _is_cell(skim, cell):
		_fail("vertical near-miss resolved to %s" % skim.get("column"))
	elif int(skim.get("face", -1)) != 0:
		_fail("vertical near-miss face %s want top" % int(skim.get("face", -1)))
	else:
		_ok("vertical near-miss snaps to the cell under the ray")

	if not _TerrainEdits.dig(neighbor.x, neighbor.y, 4):
		_fail("could not dig the neighbor for the side miss")
	else:
		var gap: float = scale * 0.25
		var side_from := Vector3(
			ws.column_to_world(float(cell.x)) - gap,
			center.y,
			center.z
		)
		var side: Dictionary = _ActionTargeting.pick_along_ray(
			side_from, Vector3.UP, player, world, null, 8.0, true
		)
		if not _is_cell(side, cell):
			_fail("side near-miss resolved to %s want %s" % [side.get("column"), cell])
		else:
			var face: int = int(side.get("face", -1))
			if face != 3 and face != 2:
				_fail("side near-miss face %s want an X face" % face)
			else:
				_ok("side near-miss snaps to the expected face %s" % face)

	player.voxel_position = Vector3(float(cell.x) + 24.5, surf, float(cell.y) + 0.5)
	var far_from := Vector3(
		ws.column_to_world(float(cell.x) + 0.5),
		top - 0.05,
		ws.column_to_world(float(cell.y) + 0.5)
	) + Vector3(0.0, 6.0, 0.0)
	var far: Dictionary = _ActionTargeting.pick_along_ray(
		far_from, Vector3(0.0, -1.0, 0.0), player, world, null, 8.0, true
	)
	if bool(far.get("hit", false)):
		_fail("out-of-range ray was accepted at %s" % far.get("column"))
	else:
		_ok("out-of-range ray is rejected")
	_TerrainEdits.reset()

	var hl = load("res://player/target_highlight.gd").new()
	root.add_child(hl)
	await process_frame
	var outline := hl.get_node_or_null("TargetBox/TargetOutline") as MeshInstance3D
	var face_node := hl.get_node_or_null("TargetBox/TargetFace") as MeshInstance3D
	if outline == null or outline.mesh == null:
		_fail("highlight outline mesh was not reused")
	elif outline.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("outline casts shadows")
	else:
		var omat := outline.material_override as StandardMaterial3D
		if omat == null or not omat.no_depth_test:
			_fail("outline is hidden by terrain depth")
		else:
			_ok("outline is one mesh, unshaded, no depth test")
	if face_node == null:
		_fail("highlight face marker missing")
	else:
		hl.apply_face_marker(2)
		if face_node.position.x < 0.4:
			_fail("+X face marker at %s" % face_node.position)
		hl.apply_face_marker(0)
		if face_node.position.y < 0.4:
			_fail("top face marker at %s" % face_node.position)
		elif face_node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("face marker casts shadows")
		else:
			_ok("face marker sits on the picked face")

	if _failed > 0:
		quit(1)
		return
	print("All block selection tests OK")
	quit(0)


func _is_cell(pick: Dictionary, cell: Vector2i) -> bool:
	if not bool(pick.get("hit", false)):
		return false
	var col: Vector3 = pick.get("column", Vector3.ZERO)
	return floori(col.x) == cell.x and floori(col.z) == cell.y


func _find_land(world) -> Vector2i:
	for x in range(6, 30):
		for z in range(6, 30):
			var tile: int = world.get_tile_type(float(x) + 0.5, float(z) + 0.5)
			if _ActionTargeting._is_fluid_tile(tile):
				continue
			var surf: float = world.get_surface_height(float(x) + 0.5, float(z) + 0.5)
			if world.get_solid(float(x) + 0.5, surf, float(z) + 0.5):
				return Vector2i(x, z)
	return Vector2i(8, 8)


class _Dummy extends Node3D:
	var voxel_position: Vector3 = Vector3.ZERO

	func get_voxel_position() -> Vector3:
		return voxel_position
