extends SceneTree
## Runtime health: load production main.tscn, audit chunk atlas + spawn markers + script-clean boot.


const MAIN_SCENE := "res://scenes/main.tscn"
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _ProbeExit = preload("res://scripts/probe_exit.gd")


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_PERF_PRESET", "medium")
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var main_packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_packed == null:
		push_error("could not load main scene")
		quit(1)
		return

	var game: Node = main_packed.instantiate()
	root.add_child(game)

	var player: Node = null
	var chunk_manager: ChunkManager = null
	var crystal: CrystalManager = null
	var registry = null

	for _attempt in 800:
		player = get_first_node_in_group("player")
		chunk_manager = get_first_node_in_group("chunk_manager")
		crystal = get_first_node_in_group("crystal_manager")
		registry = get_first_node_in_group("game_visual_registry")
		if (
			player != null and chunk_manager != null and crystal != null
			and registry != null
			and bool(player.get("world_ready"))
			and chunk_manager.chunks.size() >= 3
			and (not registry.has_method("is_ready") or registry.is_ready())
		):
			break
		await process_frame

	if crystal and crystal.has_method("refresh_spawn_marker_textures"):
		crystal.refresh_spawn_marker_textures()
	for _w in 60:
		await process_frame

	if chunk_manager == null or chunk_manager.chunks.is_empty():
		push_error("chunk_manager failed to load chunks")
		failed = true
	else:
		print("OK chunks loaded=%d" % chunk_manager.chunks.size())

	var atlas_ok := false
	var atlas_cells: Dictionary = {}
	var instances_checked := 0
	for coord in chunk_manager.chunks.keys():
		var view: ChunkView = chunk_manager.chunks[coord] as ChunkView
		if view == null:
			continue
		var mm: MultiMeshInstance3D = view.get_node_or_null("LayerContainer/mm_instance") as MultiMeshInstance3D
		if mm == null or mm.multimesh == null or mm.multimesh.instance_count <= 0:
			continue
		instances_checked += 1
		if not mm.material_override is ShaderMaterial:
			push_error("chunk %s terrain missing ShaderMaterial" % coord)
			failed = true
			continue
		var mat := mm.material_override as ShaderMaterial
		var bound: Texture2D = mat.get_shader_parameter("texture_atlas") as Texture2D
		if bound == null:
			push_error("chunk %s texture_atlas null" % coord)
			failed = true
			continue
		if "Cube.png" not in bound.resource_path:
			push_error("chunk %s atlas path wrong: %s" % [coord, bound.resource_path])
			failed = true
			continue
		atlas_ok = true
		if chunk_manager.has_method("_build_mesh") and view.chunk_data != null:
			var mesh: Dictionary = chunk_manager._build_mesh(view.chunk_data)
			for q in mesh.get("quads", []):
				var c: Vector2i = _VoxelTypes.get_atlas_coord(int(q.get("type", -1)))
				atlas_cells["%d,%d" % [c.x, c.y]] = true
		if instances_checked >= 2:
			break

	if not atlas_ok:
		push_error("no chunk multimesh with bound Cube.png atlas")
		failed = true
	elif atlas_cells.size() < 2:
		push_error("runtime mesh needs >=2 atlas cells, got %d" % atlas_cells.size())
		failed = true
	else:
		print("OK runtime atlas bound instances=%d cells=%d" % [instances_checked, atlas_cells.size()])

	var spawn_sprite_ok := false
	if crystal != null:
		for sid in crystal.get_spawn_marker_ids():
			var marker: Node3D = crystal.get_spawn_marker(sid)
			if marker is Sprite3D:
				spawn_sprite_ok = true
				break
	if not spawn_sprite_ok:
		push_error("spawn markers missing Sprite3D nodes")
		failed = true
	else:
		print("OK spawn markers use Sprite3D")

	if crystal and crystal.has_method("get_spawn_progress"):
		var prog: Dictionary = crystal.get_spawn_progress()
		var total: int = int(prog.get("total", 0))
		var active: int = int(prog.get("active", 0))
		if total < 3 or active < 3:
			push_error("full game expects >=3 spawns, got %d/%d active" % [active, total])
			failed = true
		else:
			var boss_pos := Vector2i.ZERO
			for spawn in crystal.get_active_spawns():
				if spawn.is_boss:
					boss_pos = spawn.world_pos
					break
			if boss_pos != Vector2i.ZERO and crystal.has_method("_tile_at") \
					and _CrystalTypes.is_water_tile(crystal._tile_at(boss_pos)):
				push_error("origin boss spawn %s is on water" % boss_pos)
				failed = true
			else:
				print("OK spawns active=%d total=%d boss_at=%s" % [active, total, boss_pos])

	var entity_voxel := 0
	for _w in 200:
		entity_voxel = 0
		for entity in get_nodes_in_group("world_entity"):
			if entity.get_node_or_null("VoxelProp") != null:
				entity_voxel += 1
		if entity_voxel >= 1:
			break
		await process_frame
	if entity_voxel < 1:
		var entity_mgr = get_first_node_in_group("entity_manager")
		var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
		if entity_mgr and entity_mgr.has_method("_spawn_world_entity") and brain_cfg and player:
			var col: Vector3 = player.get("voxel_position") if "voxel_position" in player else Vector3.ZERO
			var cell := Vector2i(floori(col.x), floori(col.z))
			entity_mgr.call("_spawn_world_entity", cell.x, cell.y, brain_cfg, cell, Color(0.72, 0.58, 0.42))
			if registry and registry.has_method("refresh_all"):
				registry.refresh_all()
			for _w in 40:
				await process_frame
				for entity in get_nodes_in_group("world_entity"):
					if entity.get_node_or_null("VoxelProp") != null:
						entity_voxel += 1
	if entity_voxel < 1:
		push_error("expected >=1 world_entity VoxelProp in loaded world (got %d)" % entity_voxel)
		failed = true
	else:
		print("OK world_entity voxel props=%d" % entity_voxel)

	if failed:
		_ProbeExit.finish_tree(self, 1, "Main runtime health FAILED")
	else:
		_ProbeExit.finish_tree(self, 0, "All main runtime health tests OK")