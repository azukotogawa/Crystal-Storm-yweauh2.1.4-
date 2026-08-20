extends SceneTree
## One intentional build pulse must not stack two height layers.
## Drives **shipped** WeaponController._process with real Input action edge/hold.


const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _BuildingRegistry = preload("res://building/building_registry.gd")
const _TerrainEditor = preload("res://world/terrain_editor.gd")
const _ChunkManager = preload("res://chunks/chunk_manager.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _GameManager = preload("res://game/game_manager.gd")
const _GameVisualRegistry = preload("res://systems/game_visual_registry.gd")
const _Player = preload("res://player/player.gd")


var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	_BuildingRegistry.ensure_builtins()
	OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")

	var layer: float = _WorldSettings.get_active().layer_height()
	var root3d := Node3D.new()
	root.add_child(root3d)

	var gm: _GameManager = _GameManager.new()
	gm.name = "GameManager"
	root3d.add_child(gm)
	gm.add_to_group("game_manager")
	gm.run_state = _GameManager.RunState.PLAYING

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 3
	world.add_to_group("world")
	root3d.add_child(world)

	var cm := _ChunkManager.new()
	cm.add_to_group("chunk_manager")
	cm.set_process(false)
	root3d.add_child(cm)
	var view := ChunkView.new()
	view.chunk_data = ChunkData.new(Vector2i(0, 0), world)
	cm.chunks[Vector2i(0, 0)] = view

	var editor := _TerrainEditor.new()
	editor.add_to_group("terrain_editor")
	root3d.add_child(editor)
	editor.world = world
	editor.bind_chunk_manager(cm)

	# Real Player needs MeshInstance3D child before _ready (@onready).
	var player: Player = _Player.new()
	player.name = "Player"
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	player.add_child(mesh)
	root3d.add_child(player)
	for _i in 45:
		await process_frame
		if player.get_node_or_null("WeaponController") != null and player.inventory != null:
			break

	var weapon: _WeaponController = player.get_node_or_null("WeaponController") as _WeaponController
	if weapon == null:
		_fail("Player missing WeaponController")
		quit(1)
		return
	weapon._terrain_editor = editor
	weapon.inventory = player.inventory
	player.inventory.add_item("wood", 40)
	player.world = world
	player.chunk_manager = cm
	# After _ready spawn, move player onto test cell for range checks.
	player.voxel_position = Vector3(7.5, 4.0, 7.5)
	if player.has_method("_sync_global_from_voxel"):
		player._sync_global_from_voxel()
	await process_frame

	# Force aim column via mock highlight
	var old_hl = player.get_node_or_null("TargetHighlight")
	if old_hl:
		player.remove_child(old_hl)
		old_hl.free()
	var mock_gs := GDScript.new()
	mock_gs.source_code = """extends Node
var col := Vector3(7.5, 1.0, 7.5)
func get_action_column() -> Vector3:
	return col
"""
	mock_gs.reload()
	var hl := Node.new()
	hl.name = "TargetHighlight"
	hl.set_script(mock_gs)
	player.add_child(hl)

	# --- API baseline ---
	var b0: float = _TerrainEdits.get_height_delta(4, 4)
	editor.try_build(Vector3(4.5, 0, 4.5), player.inventory, &"wood_wall")
	if int(round((_TerrainEdits.get_height_delta(4, 4) - b0) / layer)) != 1:
		_fail("single try_build should add exactly 1 layer")
	else:
		print("OK single try_build = 1 layer")

	# --- Ship WeaponController._process + Input edge/hold ---
	var cell := Vector2i(7, 7)
	hl.col = Vector3(float(cell.x) + 0.5, 1.0, float(cell.y) + 0.5)
	var before: float = _TerrainEdits.get_height_delta(cell.x, cell.y)

	Input.action_release("build_place")
	Input.action_release("interact")
	await process_frame
	weapon._cooldown_timer = 0.0
	weapon._build_hold_sec = 0.0

	Input.action_press("build_place")
	weapon._process(0.016)
	var layers_edge := int(round((_TerrainEdits.get_height_delta(cell.x, cell.y) - before) / layer))
	if layers_edge != 1:
		_fail("weapon edge press must place exactly 1 layer, got %d (fail=%s)" % [
			layers_edge, editor.last_fail_reason
		])
	else:
		print("OK weapon Input edge place = 1 layer")

	# Advance engine frame so is_action_just_pressed clears while button stays pressed.
	await process_frame
	await process_frame
	# Short hold: still pressed, not a new edge — accumulate < hold-start.
	var hold_accum := 0.0
	while hold_accum < weapon.TERRAIN_HOLD_REPEAT_START_SEC * 0.6:
		weapon._process(0.016)
		hold_accum += 0.016
	var layers_short := int(round((_TerrainEdits.get_height_delta(cell.x, cell.y) - before) / layer))
	if layers_short != 1:
		_fail("short hold within TERRAIN_HOLD_REPEAT_START must stay at 1 layer (got %d)" % layers_short)
	else:
		print("OK short hold still 1 layer (hold_start=%.2fs)" % weapon.TERRAIN_HOLD_REPEAT_START_SEC)

	# Long hold past repeat start with cooldown cleared for cadence.
	for _i in 20:
		weapon._cooldown_timer = 0.0
		weapon._process(0.02)
		await process_frame
	var layers_long := int(round((_TerrainEdits.get_height_delta(cell.x, cell.y) - before) / layer))
	if layers_long < 2:
		_fail("long hold should stack (got %d)" % layers_long)
	else:
		print("OK long hold stacks layers=%d" % layers_long)

	Input.action_release("build_place")
	await process_frame

	# --- Herb via shipped _try_use_consumable ---
	player.health = 40.0
	player.max_health = 100.0
	# Clear hotbar and put only herb on slot 0
	var herb_n: int = 3
	if player.inventory.has_method("set_slot"):
		player.inventory.set_slot(0, "herb", herb_n)
	else:
		# consume extras then add
		while player.inventory.count_item("herb") > 0:
			player.inventory.consume_item("herb", 1)
		player.inventory.add_item("herb", herb_n)
	weapon._active_hotbar_index = 0
	weapon._cooldown_timer = 0.0
	var herb_before: int = player.inventory.count_item("herb")
	var hp0: float = player.health
	var ok_use: bool = weapon._try_use_consumable()
	if not ok_use:
		_fail("_try_use_consumable failed with herb on hotbar")
	else:
		var herb_after: int = player.inventory.count_item("herb")
		if herb_after != herb_before - 1:
			_fail("herb not consumed by 1 (before=%d after=%d)" % [herb_before, herb_after])
		elif player.health <= hp0:
			_fail("health did not rise via consumable (%.1f→%.1f)" % [hp0, player.health])
		else:
			print("OK herb consumable path hp %.1f→%.1f herbs %d→%d" % [
				hp0, player.health, herb_before, herb_after
			])

	# --- wood_wall short cap ---
	var reg := _GameVisualRegistry.new()
	root3d.add_child(reg)
	var mi := MeshInstance3D.new()
	reg.configure_building_mesh(mi, null, Vector3(1, 1.5, 1), Color.WHITE, "wood_wall")
	if not bool(mi.get_meta("uses_authored_mesh", false)):
		_fail("wood_wall must use authored mesh")
	elif mi.scale.y > 0.7:
		_fail("wood_wall authored Y scale must be short cap (<=0.7), got %.3f" % mi.scale.y)
	else:
		print("OK wood_wall authored short-cap scale.y=%.3f (xz=%.2f)" % [mi.scale.y, mi.scale.x])
	mi.queue_free()

	# --- null player guard ---
	cm.player = null
	cm.flush_rebuild_pending()
	var pcol: Vector2 = cm._player_column_pos()
	if pcol != Vector2.ZERO:
		# Safe fallback is ZERO
		print("NOTE _player_column_pos returned %s with null player" % str(pcol))
	print("OK _player_column_pos/flush with null player (no SCRIPT ERROR)")

	Input.action_release("build_place")
	root3d.queue_free()
	if _failed == 0:
		print("All terrain input single tests OK")
		quit(0)
	else:
		push_error("verify_terrain_input_single: %d failure(s)" % _failed)
		quit(1)
