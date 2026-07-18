extends Control

const _WorldSettings = preload("res://config/world_settings.gd")
const _CombatLog = preload("res://systems/combat_log.gd")
const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")

@onready var label = $DebugLabel

var _update_counter := 0
var _debug_update_every := 12
var _panel_enabled := true
var _expensive_queries := false

func _enter_tree() -> void:
	add_to_group("debug_panel")


func apply_performance_config(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	_panel_enabled = bool(cfg.debug_panel_enabled)
	_debug_update_every = maxi(int(cfg.debug_update_every), 4)
	if "debug_expensive_queries" in cfg:
		_expensive_queries = bool(cfg.debug_expensive_queries)
	visible = _panel_enabled
	set_process(_panel_enabled)


func _process(_delta: float) -> void:
	if not _panel_enabled or not label:
		return
	
	_update_counter += 1
	if _update_counter % _debug_update_every != 0:
		return

	var profiler = get_node_or_null("/root/PerfProfiler")
	if profiler and profiler.has_method("begin"):
		profiler.begin("debug_panel")
	if profiler and profiler.has_method("sample_scene_stats"):
		profiler.sample_scene_stats(get_tree())

	var seed_val := "???"
	var chunks_count := 0
	var player_voxel := Vector3.ZERO
	var current_chunk := Vector2i.ZERO
	var biome_name := "???"
	var tile_name := "Unknown"
	var h := "???"
	var cam_rot := 0
	var crystal_tiles := 0
	var crystal_power := 0.0
	var crystal_tier := 0
	var crystal_volume := 0.0
	var crystal_max_depth := 0.0
	var crystal_dist := "???"
	var map_zone := "???"
	var map_temp := "???"
	var game_phase := "???"
	var player_health := "???"
	var evolution_line := "none"
	var enemies_active := 0
	var world_entities := 0
	var town_status := "—"
	var save_hint := "F5 save | F9 load | U map"
	var perf_hint := "quality=?"
	var combat_log := "—"
	var nearest_target := "—"
	var spawn_progress := "—"
	var last_spawn_kill := "—"
	var terrain_atlas := "—"
	var highlight_mode := "—"
	var highlight_cell := "—"
	var hotbar_item := "—"
	var veg_voxel := 0
	var veg_billboard := 0
	var entity_voxel := 0
	var entity_sprite := 0

	# Find main nodes safely
	var main = get_tree().root.get_node_or_null("Game")
	var player = get_tree().get_first_node_in_group("player")
	var world = get_tree().get_first_node_in_group("world")
	var camera = get_tree().get_first_node_in_group("camera")
	var chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	var crystal_manager = get_tree().get_first_node_in_group("crystal_manager")

	# Seed
	if world and "world_seed" in world:
		seed_val = str(world.world_seed)

	# Chunks
	if chunk_manager:
		if chunk_manager.has_method("get_chunk_count"):
			chunks_count = chunk_manager.get_chunk_count()
		else:
			var prop_list = chunk_manager.get_property_list()
			var has_chunks_prop := false
			for prop in prop_list:
				if prop.name == "chunks":
					has_chunks_prop = true
					break
			if has_chunks_prop:
				var chunks_prop = chunk_manager.get("chunks")
				if chunks_prop is Dictionary:
					chunks_count = chunks_prop.size()
				elif chunks_prop is Array:
					chunks_count = chunks_prop.size()

	# Player position
	if player:
		if player.has_method("get_voxel_position"):
			var col: Vector3 = player.get_voxel_position()
			var ws = _WorldSettings.get_active()
			player_voxel = Vector3(ws.column_to_world(col.x), col.y, ws.column_to_world(col.z))
		elif "voxel_position" in player:
			player_voxel = player.voxel_position
		elif "global_position" in player:
			player_voxel = player.global_position

	# Current chunk
	if player_voxel != Vector3.ZERO:
		current_chunk = Vector2i(
			floori(player_voxel.x / ChunkData.SIZE),
			floori(player_voxel.z / ChunkData.SIZE)
		)

	# Map border zone + temperature theme
	if world:
		if player_voxel != Vector3.ZERO and world.has_method("get_map_zone_label"):
			map_zone = world.get_map_zone_label(player_voxel.x, player_voxel.z)
		if "map_temperature_label" in world:
			map_temp = str(world.map_temperature_label)

	var game_manager = get_tree().get_first_node_in_group("game_manager")
	if game_manager:
		if game_manager.phase == 0:
			game_phase = "Maze"
		else:
			game_phase = "Assault"

	if player and "health" in player and "max_health" in player:
		player_health = "%.0f/%.0f" % [player.health, player.max_health]

	# Biome & Tile
	if world and player_voxel != Vector3.ZERO:
		var biome = world._get_biome_compute(player_voxel.x, 0.0, player_voxel.z)
		if biome is Dictionary:
			if "type" in biome and biome.type != null:
				biome_name = str(biome.type)
			elif "name" in biome and biome.name != null:
				biome_name = str(biome.name).capitalize()
			else:
				biome_name = "Unknown"
		else:
			biome_name = "None (invalid biome dict)"

		var raw_tile = world.get_tile_type(player_voxel.x, player_voxel.z)
		if raw_tile == 37:
			tile_name = "RIVER"
		else:
			tile_name = str(raw_tile)

	# Height
	if world and player_voxel != Vector3.ZERO:
		h = "%.1f" % TerrainRamps.walkable_height(world, player_voxel.x, player_voxel.z)

	# Camera rotation
	if camera and "rotation_degrees" in camera:
		cam_rot = int(camera.rotation_degrees.y)

	# Crystal
	if crystal_manager and crystal_manager.has_method("get_debug_stats"):
		var stats: Dictionary = crystal_manager.get_debug_stats()
		crystal_tiles = int(stats.get("tiles", 0))
		crystal_volume = float(stats.get("volume", 0.0))
		crystal_max_depth = float(stats.get("max_depth", 0.0))
		crystal_power = float(stats.get("power", 0.0))
		crystal_tier = int(stats.get("tier", 0))
		spawn_progress = "%d/%d" % [
			int(stats.get("spawns_active", 0)),
			int(stats.get("spawns_total", 0)),
		]
		var last_k := str(stats.get("last_destroyed", ""))
		if last_k != "":
			last_spawn_kill = last_k
		var weaken: float = float(stats.get("emit_weaken_mult", 1.0))
		if weaken < 0.99:
			spawn_progress += " emit x%.2f" % weaken
		if bool(stats.get("boss_active", false)):
			spawn_progress += " BOSS"
		if bool(stats.get("boss_sealed", false)):
			spawn_progress += " SEALED"
	if _expensive_queries and crystal_manager and player_voxel != Vector3.ZERO and crystal_manager.has_method("get_nearest_crystal_distance"):
		var dist: float = crystal_manager.get_nearest_crystal_distance(player_voxel)
		if dist == INF:
			crystal_dist = "none"
		else:
			crystal_dist = "%.1f" % dist
	if crystal_manager and crystal_manager.has_method("get_evolution"):
		var evo = crystal_manager.get_evolution()
		if evo:
			var summary: Dictionary = evo.get_summary()
			var unlocked: Array = summary.get("unlocked_enemies", [])
			var absorbed: Dictionary = summary.get("absorbed", {})
			var parts: PackedStringArray = []
			for key in absorbed.keys():
				parts.append("%s:%d" % [str(key), int(absorbed[key])])
			var unlock_str := ", ".join(unlocked) if unlocked.size() > 0 else "—"
			evolution_line = "%s | unlocks: %s" % [
				", ".join(parts) if parts.size() > 0 else "—",
				unlock_str,
			]
	var save_svc = get_tree().get_first_node_in_group("save_game_service")
	if save_svc and save_svc.has_method("has_save") and save_svc.has_save():
		save_hint = "F5 save | F9 load | U map | slot0 OK"
	var spawner = get_tree().get_first_node_in_group("crystal_enemy_spawner")
	if spawner and spawner.has_method("get_active_count"):
		enemies_active = spawner.get_active_count()
	var entity_mgr = get_tree().get_first_node_in_group("entity_manager")
	if entity_mgr and entity_mgr.has_method("get_active_entity_count"):
		world_entities = entity_mgr.get_active_entity_count()
	for node in get_tree().get_nodes_in_group("world_entity"):
		if node.get_node_or_null("VoxelProp") != null and node.get_node_or_null("VoxelProp").visible:
			entity_voxel += 1
		elif node.get_node_or_null("Sprite3D") != null and node.get_node_or_null("Sprite3D").visible:
			entity_sprite += 1
	for node in get_tree().get_nodes_in_group("crystal_enemy"):
		if node.get_node_or_null("VoxelProp") != null and node.get_node_or_null("VoxelProp").visible:
			entity_voxel += 1
		elif node.get_node_or_null("Sprite3D") != null and node.get_node_or_null("Sprite3D").visible:
			entity_sprite += 1
	var town_def = get_tree().get_first_node_in_group("town_defense_manager")
	if town_def and town_def.has_method("get_status_summary"):
		var towns: Array = town_def.get_status_summary()
		var parts: PackedStringArray = []
		for t in towns:
			parts.append("%s:%s" % [str(t.get("name", "?")), _town_state_label(int(t.get("state", 0)))])
		if parts.size() > 0:
			town_status = ", ".join(parts)

	combat_log = _CombatLog.get_recent(" | ")
	var perf_svc = get_tree().get_first_node_in_group("performance_service")
	if perf_svc and "quality" in perf_svc:
		var q = perf_svc.quality
		if q:
			perf_hint = "LOW" if int(q.preset) == 0 else ("MED" if int(q.preset) == 1 else "HIGH")
	if profiler and profiler.has_method("format_debug_line"):
		perf_hint = "%s | %s" % [perf_hint, profiler.format_debug_line()]
	if _expensive_queries and player and player.has_method("get_voxel_position"):
		nearest_target = _nearest_combat_target_summary(player.get_voxel_position())

	if player and world:
		var action := _ActionTargeting.resolve_action(player, world, chunk_manager, 2.0)
		var mode: String = str(action.get("mode", "none"))
		if mode != "none":
			highlight_mode = mode
			var cell: Vector2i = action.get("cell", Vector2i.ZERO)
			highlight_cell = "%d,%d" % [cell.x, cell.y]
		var weapon := player.get_node_or_null("WeaponController")
		if weapon and weapon.has_method("get_active_item"):
			var slot = weapon.get_active_item()
			if slot != null:
				hotbar_item = str(slot.id)

	var visuals_root = get_tree().get_first_node_in_group("world_visuals_root")
	if visuals_root:
		var veg_root = visuals_root.get_node_or_null("Vegetation")
		if veg_root:
			for anchor in veg_root.get_children():
				if anchor.get_node_or_null("VoxelProp") != null:
					veg_voxel += 1
				elif anchor.get_node_or_null("Billboard") != null:
					veg_billboard += 1
	if chunk_manager and chunk_manager.chunks.size() > 0:
		for coord in chunk_manager.chunks.keys():
			var view: ChunkView = chunk_manager.chunks[coord] as ChunkView
			if view == null:
				continue
			var mm: MultiMeshInstance3D = view.get_node_or_null("LayerContainer/mm_instance") as MultiMeshInstance3D
			if mm == null or not mm.material_override is ShaderMaterial:
				continue
			var mat := mm.material_override as ShaderMaterial
			var tex: Texture2D = mat.get_shader_parameter("texture_atlas") as Texture2D
			if tex != null:
				var n: int = mm.multimesh.instance_count if mm.multimesh else 0
				terrain_atlas = "%s (%d inst)" % [tex.resource_path.get_file(), n]
				break

	label.text = """Seed: %s
Map Temp: %s
Phase: %s | HP: %s
Voxel Pos: %.1f, %.1f, %.1f
Chunk: %d, %d
Chunks Loaded: %d
Terrain Atlas: %s
Tile: %s
Biome: %s
Map Zone: %s
Height: %s
Cam Rot: %d
Crystal Cells: %d
Crystal Volume: %.1f (max %.1f)
Crystal Power: %.1f (T%d)
Nearest Crystal: %s
Evolution: %s
Crystal Enemies: %d
World Entities: %d
Spawns: %s
Last Kill: %s
Towns: %s
Combat: %s
Target: %s
Highlight: %s @ %s
Hotbar: %s
Veg: %d voxel / %d bill | Ent: %d voxel / %d spr
Perf: %s
Save: %s
	FPS: %d%s""" % [
		seed_val,
		map_temp,
		game_phase, player_health,
		player_voxel.x, player_voxel.y, player_voxel.z,
		current_chunk.x, current_chunk.y,
		chunks_count,
		terrain_atlas,
		tile_name,
		biome_name,
		map_zone,
		h,
		cam_rot,
		crystal_tiles,
		crystal_volume, crystal_max_depth,
		crystal_power, crystal_tier,
		crystal_dist,
		evolution_line,
		enemies_active,
		world_entities,
		spawn_progress,
		last_spawn_kill,
		town_status,
		combat_log,
		nearest_target,
		highlight_mode, highlight_cell,
		hotbar_item,
		veg_voxel, veg_billboard, entity_voxel, entity_sprite,
		perf_hint,
		save_hint,
		Engine.get_frames_per_second(),
		_runtime_perf_block(profiler),
	]

	if profiler and profiler.has_method("end"):
		profiler.end("debug_panel")


func is_overlay_visible() -> bool:
	return visible


func set_overlay_visible(show_overlay: bool) -> void:
	visible = show_overlay
	set_process(show_overlay and _panel_enabled)


func _runtime_perf_block(profiler: Node) -> String:
	if profiler == null or not profiler.has_method("format_runtime_report"):
		return ""
	return "\n\n--- PERF ---\n%s" % profiler.format_runtime_report()


func _nearest_combat_target_summary(player_col: Vector3) -> String:
	var best_label := ""
	var best_dist := INF
	var best_hp := ""
	for group_name in ["world_entity", "crystal_enemy"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if node.has_method("is_combat_alive") and not node.is_combat_alive():
				continue
			var center: Vector3 = node.get_combat_center() if node.has_method("get_combat_center") else node.global_position
			var dist := Vector2(player_col.x - center.x, player_col.z - center.z).length()
			if dist >= best_dist:
				continue
			best_dist = dist
			if "health" in node:
				var max_hp: float = float(node.max_health) if "max_health" in node else 0.0
				if max_hp <= 0.0 and "config" in node and node.config:
					max_hp = float(node.config.max_health)
				if max_hp > 0.0:
					best_hp = "%.0f/%.0f" % [node.health, max_hp]
				else:
					best_hp = "%.0f" % node.health
			if node.has_method("get_combat_center"):
				if "entity_kind" in node:
					best_label = str(node.entity_kind)
				elif "enemy_id" in node:
					best_label = str(node.enemy_id)
				else:
					best_label = node.name
	if best_label == "":
		return "—"
	return "%s d=%.1f HP %s" % [best_label, best_dist, best_hp if best_hp != "" else "?"]


func _town_state_label(state: int) -> String:
	match state:
		1: return "ALERT"
		2: return "BESIEGED"
		3: return "FALLEN"
		_: return "SAFE"
