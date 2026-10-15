extends SceneTree


const MAIN_SCENE := "res://scenes/main.tscn"
const _Inventory = preload("res://inventory/inventory.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")
const _Settings = preload("res://config/world_settings.gd")
const _Registry = preload("res://systems/game_visual_registry.gd")

const STONE_MESH := "res://assets/structures/stone_wall/stone_wall.obj"
const GATE_MESH := "res://assets/structures/gate/gate.obj"
const TOWER_MESH := "res://assets/structures/ruin_pillar/ruin_pillar.obj"

var _failed: int = 0


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL " + msg)


func _run() -> void:
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("LARGE_STRUCTURES must stay on")
		_finish()
		return
	_test_authored_bindings()
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("missing main scene")
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	var editor = null
	var feat = null
	var world = null
	var player = null
	for _i in 240:
		await process_frame
		editor = get_first_node_in_group("terrain_editor")
		feat = get_first_node_in_group("feature_visual_layer")
		world = get_first_node_in_group("world")
		player = get_first_node_in_group("player")
		var cm = get_first_node_in_group("chunk_manager")
		if editor and feat and world and player and cm and cm.chunks.size() > 0:
			break
	await process_frame
	if editor == null or feat == null or world == null or player == null:
		_fail("boot missing editor, visuals, world, or player")
		_finish()
		return
	var probe = player.get("_floor_probe")
	if probe == null or not probe.has_method("can_step_to"):
		_fail("player floor probe missing")
		_finish()
		return
	if feat.has_method("_bind_terrain_placement_refresh"):
		feat._bind_terrain_placement_refresh()
	var inv := _Inventory.new()
	inv.add_item("stone", 80)
	inv.add_item("wood", 40)
	await _check_segment(editor, feat, world, player, probe, inv)
	await _check_corner(editor, feat, world, player, probe, inv)
	await _check_gate(editor, feat, world, player, probe, inv)
	await _check_stairs(editor, feat, world, player, probe, inv)
	await _check_tower(editor, feat, world, player, probe, inv)
	_finish()


func _test_authored_bindings() -> void:
	var reg := _Registry.new()
	var specs := {
		"stone_wall": STONE_MESH,
		"gate": GATE_MESH,
		"stairs": STONE_MESH,
		"small_tower": TOWER_MESH,
	}
	for visual in specs.keys():
		var want: String = specs[visual]
		if not reg.has_authored_building_mesh(visual) or reg.authored_building_mesh_path(visual) != want:
			_fail("%s authored path is not %s" % [visual, want])
			continue
		var mi := MeshInstance3D.new()
		reg.configure_building_mesh(mi, null, Vector3(1, 2, 1), Color.WHITE, visual)
		if not bool(mi.get_meta("uses_authored_mesh", false)):
			_fail("%s did not bind an authored mesh" % visual)
		elif str(mi.get_meta("authored_resource_path", "")) != want or mi.mesh == null:
			_fail("%s authored mesh missing after configure" % visual)
		mi.free()
	reg.free()
	if _failed == 0:
		print("OK authored meshes for stone wall, gate, stairs, and small tower")


func _check_segment(editor, feat, world, player, probe, inv) -> void:
	var at := _find_pad(world, player, 3, 1)
	if at.x < -100000:
		_fail("no flat pad for the wall segment")
		return
	var before := _layers_at(at.x, at.y)
	var beside := _layers_at(at.x + 3, at.y)
	if not _place(editor, inv, at, _Blueprints.WALL_SEGMENT):
		return
	await process_frame
	var rose := true
	for x in 3:
		var col := Vector2i(at.x + x, at.y)
		if _layers_at(col.x, col.y) != before + 2:
			rose = false
		_expect_mesh(feat, col, "stone_wall", STONE_MESH)
		if _can_enter(probe, Vector2i(col.x, col.y - 1), col):
			_fail("wall segment column %s does not block" % str(col))
	if _layers_at(at.x + 3, at.y) != beside:
		rose = false
	if _can_enter(probe, Vector2i(at.x - 1, at.y), at):
		_fail("wall segment face does not block")
	if not rose:
		_fail("wall segment must raise only its three columns by two")
		return
	print("OK wall segment authored live place collision")


func _check_corner(editor, feat, world, player, probe, inv) -> void:
	var at := _find_pad(world, player, 2, 2)
	if at.x < -100000:
		_fail("no flat pad for the wall corner")
		return
	var before := _layers_at(at.x, at.y)
	var inner := Vector2i(at.x + 1, at.y + 1)
	var inner_before := _layers_at(inner.x, inner.y)
	if not _place(editor, inv, at, _Blueprints.WALL_CORNER):
		return
	await process_frame
	var solid := [Vector2i(at.x, at.y), Vector2i(at.x + 1, at.y), Vector2i(at.x, at.y + 1)]
	var rose := true
	for col in solid:
		if _layers_at(col.x, col.y) != before + 2:
			rose = false
		_expect_mesh(feat, col, "stone_wall", STONE_MESH)
		var front := Vector2i(col.x, col.y - 1) if col.y == at.y else Vector2i(col.x - 1, col.y)
		if _can_enter(probe, front, col):
			_fail("wall corner column %s does not block" % str(col))
	if _layers_at(inner.x, inner.y) != inner_before:
		rose = false
	if not _can_enter(probe, Vector2i(inner.x + 1, inner.y), inner):
		_fail("wall corner inner column blocks")
	if not rose:
		_fail("wall corner must raise the L and leave the inner column")
		return
	print("OK wall corner authored live place collision")


func _check_gate(editor, feat, world, player, probe, inv) -> void:
	var at := _find_pad(world, player, 3, 1)
	if at.x < -100000:
		_fail("no flat pad for the gate")
		return
	var before := _layers_at(at.x, at.y)
	var open := Vector2i(at.x + 1, at.y)
	var open_before := _layers_at(open.x, open.y)
	if not _place(editor, inv, at, _Blueprints.GATE):
		return
	await process_frame
	if _layers_at(at.x, at.y) != before + 2 or _layers_at(at.x + 2, at.y) != before + 2:
		_fail("gate posts did not rise two layers")
	if _layers_at(open.x, open.y) != open_before:
		_fail("gate opening changed the ground")
	_expect_mesh(feat, at, "stone_wall", STONE_MESH)
	_expect_mesh(feat, Vector2i(at.x + 2, at.y), "stone_wall", STONE_MESH)
	_expect_mesh(feat, open, "gate", GATE_MESH)
	if _can_enter(probe, Vector2i(at.x, at.y - 1), at):
		_fail("gate post does not block")
	if not _can_enter(probe, Vector2i(open.x, open.y - 1), open):
		_fail("gate opening blocks")
	print("OK gate authored live place collision")


func _check_stairs(editor, feat, world, player, probe, inv) -> void:
	var at := _find_pad(world, player, 3, 1)
	if at.x < -100000:
		_fail("no flat pad for the stairs")
		return
	var before := _layers_at(at.x, at.y)
	if not _place(editor, inv, at, _Blueprints.STAIRS):
		return
	await process_frame
	var low := Vector2i(at.x, at.y)
	var mid := Vector2i(at.x + 1, at.y)
	var high := Vector2i(at.x + 2, at.y)
	if _layers_at(low.x, low.y) != before + 1 or _layers_at(mid.x, mid.y) != before + 2 or _layers_at(high.x, high.y) != before + 3:
		_fail("stairs did not rise 1, 2, 3")
	_expect_mesh(feat, low, "stairs", STONE_MESH)
	_expect_mesh(feat, mid, "stairs", STONE_MESH)
	_expect_mesh(feat, high, "stairs", STONE_MESH)
	if not _can_enter(probe, Vector2i(low.x, low.y - 1), low):
		_fail("first stair does not accept a step")
	if not _can_enter(probe, low, mid) or not _can_enter(probe, mid, high):
		_fail("stairs do not step up one layer at a time")
	if _can_enter(probe, Vector2i(high.x, high.y - 1), high):
		_fail("top stair can be entered from the ground")
	print("OK stairs authored live place collision")


func _check_tower(editor, feat, world, player, probe, inv) -> void:
	var at := _find_pad(world, player, 2, 2)
	if at.x < -100000:
		_fail("no flat pad for the small tower")
		return
	var before := _layers_at(at.x, at.y)
	if not _place(editor, inv, at, _Blueprints.SMALL_TOWER):
		return
	await process_frame
	var cols := [
		Vector2i(at.x, at.y),
		Vector2i(at.x + 1, at.y),
		Vector2i(at.x, at.y + 1),
		Vector2i(at.x + 1, at.y + 1),
	]
	var rose := true
	for col in cols:
		if _layers_at(col.x, col.y) != before + 3:
			rose = false
		_expect_mesh(feat, col, "small_tower", TOWER_MESH)
		var outside := Vector2i(col.x - 1, col.y) if col.x == at.x else Vector2i(col.x + 1, col.y)
		if _can_enter(probe, outside, col):
			_fail("tower column %s does not block" % str(col))
	if not rose:
		_fail("small tower must raise every column by three")
		return
	print("OK small tower authored live place collision")


func _place(editor, inv, at: Vector2i, piece: StringName) -> bool:
	inv.add_item("stone", 40)
	inv.add_item("wood", 12)
	var pos := Vector3(float(at.x) + 0.5, 0.0, float(at.y) + 0.5)
	if editor.try_place_blueprint(pos, inv, piece, 0):
		return true
	_fail("live %s: %s" % [String(piece), editor.last_fail_reason])
	return false


func _expect_mesh(feat, cell: Vector2i, visual: String, path: String) -> void:
	var anchor: Node3D = feat._nodes_by_cell.get(cell)
	if anchor == null:
		_fail("no live anchor at %s for %s" % [str(cell), visual])
		return
	if str(anchor.get_meta("building_visual_id", "")) != visual:
		_fail("live %s visual is %s" % [visual, anchor.get_meta("building_visual_id", "")])
		return
	var mesh: MeshInstance3D = anchor.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or not bool(mesh.get_meta("uses_authored_mesh", false)):
		_fail("live %s is not authored" % visual)
		return
	if str(mesh.get_meta("authored_resource_path", "")) != path:
		_fail("live %s path %s" % [visual, mesh.get_meta("authored_resource_path", "")])


func _can_enter(probe, frm: Vector2i, to: Vector2i) -> bool:
	var ws = _Settings.get_active()
	var feet: float = float(probe.walkable_height_at(float(frm.x) + 0.5, float(frm.y) + 0.5))
	var from_pos := Vector3(float(frm.x) + 0.5, feet, float(frm.y) + 0.5)
	var to_pos := Vector3(float(to.x) + 0.5, feet, float(to.y) + 0.5)
	return bool(probe.can_step_to(
		from_pos, to_pos, ws.player_height(), ws.player_radius(), ws.max_step_up_walk(), false
	))


func _find_pad(world, player, w: int, d: int) -> Vector2i:
	var origin: Vector3 = player.get_voxel_position()
	var px := int(floor(origin.x))
	var pz := int(floor(origin.z))
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			if absi(dx) < 3 and absi(dz) < 3:
				continue
			var ax := px + dx
			var az := pz + dz
			if _pad_clear(world, ax, az, w, d):
				return Vector2i(ax, az)
	return Vector2i(-1000000, 0)


func _pad_clear(world, ax: int, az: int, w: int, d: int) -> bool:
	var height: float = world.get_surface_height(float(ax), float(az))
	for x in range(-1, w + 1):
		for z in range(-1, d + 1):
			var wx := ax + x
			var wz := az + z
			if not _TerrainEdits.can_edit(wx, wz):
				return false
			if absf(world.get_surface_height(float(wx), float(wz)) - height) > 0.01:
				return false
			if _TerrainEdits.get_build_tile(wx, wz) >= 0:
				return false
			if not _FeatureRegistry.get_feature(wx, wz).is_empty():
				return false
	return true


func _layers_at(x: int, z: int) -> int:
	var layer: float = _Settings.get_active().layer_height()
	return int(round(_TerrainEdits.get_height_delta(x, z) / maxf(layer, 0.001)))


func _finish() -> void:
	if _failed == 0:
		_ProbeExit.finish_tree(self, 0, "All structure piece tests OK")
	else:
		_ProbeExit.finish_tree(self, 1, "STRUCTURE PIECES FAILED")
