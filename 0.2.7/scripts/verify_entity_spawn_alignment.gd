extends SceneTree
## Regression: spawned world_entity global_position matches registry column_sprite_position for home_cell.


const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const MAX_XZ_WORLD_OFFSET := 0.15
const MAX_COLUMN_OFFSET := 0.08

var _probe_spawned: Node = null


func _on_probe_entity_spawned(entity: Node) -> void:
	_probe_spawned = entity
	if is_instance_valid(entity):
		entity.set_process(false)
		entity.set_physics_process(false)


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("main scene load failed")
		_ProbeExit.finish_tree(self, 1, "Entity spawn alignment FAILED")
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var chunk_manager: ChunkManager = null
	var world: InfiniteNoiseWorld = null
	var registry = null
	var crystal: CrystalManager = null
	var entity_mgr = null

	for _attempt in 600:
		chunk_manager = get_first_node_in_group("chunk_manager")
		world = get_first_node_in_group("world")
		registry = get_first_node_in_group("game_visual_registry")
		crystal = get_first_node_in_group("crystal_manager")
		entity_mgr = get_first_node_in_group("entity_manager")
		if (
			chunk_manager != null and world != null and registry != null
			and crystal != null and entity_mgr != null
			and registry.has_method("is_ready") and registry.is_ready()
		):
			break
		await process_frame

	if entity_mgr == null or registry == null:
		push_error("bootstrap timeout")
		_ProbeExit.finish_tree(self, 1, "Entity spawn alignment FAILED")
		return

	for _w in 60:
		await process_frame

	var test_cell := Vector2i(11, 11)
	var chunk_coord := chunk_manager.world_to_chunk_coord(test_cell.x, test_cell.y)
	if chunk_manager.has_method("update_stream"):
		chunk_manager.update_stream(chunk_coord.x, chunk_coord.y)
	for _w in 120:
		await process_frame
		if chunk_manager.chunks.has(chunk_coord):
			break

	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if brain_cfg == null:
		push_error("rabbit brain missing")
		failed = true
	else:
		_probe_spawned = null
		if entity_mgr.entity_spawned.is_connected(_on_probe_entity_spawned):
			entity_mgr.entity_spawned.disconnect(_on_probe_entity_spawned)
		entity_mgr.entity_spawned.connect(_on_probe_entity_spawned, CONNECT_ONE_SHOT)
		entity_mgr.call(
			"_spawn_world_entity", test_cell.x, test_cell.y, brain_cfg, test_cell, Color(0.72, 0.58, 0.42)
		)
		for _w in 30:
			await process_frame
		if registry.has_method("refresh_all"):
			registry.refresh_all()
		var spawned: Node = _probe_spawned
		if spawned == null or not is_instance_valid(spawned):
			push_error("entity_spawned did not deliver entity")
			failed = true
		elif spawned.has_method("refresh_visual"):
			spawned.refresh_visual()
			for _w in 8:
				await process_frame
			var home: Vector2i = spawned.get("home_cell")
			if home != test_cell:
				push_error("home_cell %s != spawn %s" % [home, test_cell])
				failed = true
			else:
				var ws = _WorldSettings.get_active()
				var col_x := float(home.x) + 0.5
				var col_z := float(home.y) + 0.5
				var tex = null
				if registry.has_method("get_sprite_texture"):
					tex = registry.get_sprite_texture(str(spawned.get("entity_kind")))
				var height_off: float = 0.0
				if tex != null and registry.has_method("entity_anchor_height_offset"):
					height_off = registry.entity_anchor_height_offset(tex)
				elif tex != null and registry.has_method("sprite_half_height"):
					height_off = registry.sprite_half_height(tex)
				var expected: Vector3 = registry.column_sprite_position(
					world, chunk_manager, crystal, col_x, col_z, height_off
				)
				var actual: Vector3 = spawned.global_position
				var xz_err := Vector2(actual.x - expected.x, actual.z - expected.z).length()
				var col_from_world := Vector2(
					ws.world_to_column(actual.x),
					ws.world_to_column(actual.z)
				)
				var col_err := Vector2(col_from_world.x - col_x, col_from_world.y - col_z).length()
				if xz_err > MAX_XZ_WORLD_OFFSET:
					push_error(
						"entity xz offset %.3f from registry anchor expected=%s actual=%s"
						% [xz_err, expected, actual]
					)
					failed = true
				elif col_err > MAX_COLUMN_OFFSET:
					push_error(
						"entity column offset %.3f from home center col=(%.1f,%.1f) got=(%.2f,%.2f)"
						% [col_err, col_x, col_z, col_from_world.x, col_from_world.y]
					)
					failed = true
				else:
					var combat: Vector3 = spawned.get_combat_center()
					var combat_xz := Vector2(combat.x - actual.x, combat.z - actual.z).length()
					print(
						"OK entity anchor home=%s xz_err=%.3f col_err=%.3f combat_xz=%.3f pos=%s"
						% [home, xz_err, col_err, combat_xz, actual]
					)
					if combat_xz > ws.voxel_scale * 0.6:
						push_error("combat center xz diverges from feet by %.2f" % combat_xz)
						failed = true
					else:
						print("OK combat center xz aligned with entity feet")

	if failed:
		_ProbeExit.finish_tree(self, 1, "Entity spawn alignment FAILED")
		return
	_ProbeExit.finish_tree(self, 0, "All entity spawn alignment tests OK")