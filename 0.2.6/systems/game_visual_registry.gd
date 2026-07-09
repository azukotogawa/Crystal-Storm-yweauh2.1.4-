class_name GameVisualRegistry
extends Node

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _GeneratorScript = preload("res://systems/crystal_texture_generator.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

## Small lift above walkable surface to avoid z-fighting with voxel tops.
const SURFACE_LIFT: float = 0.12
## World units per texture pixel (= voxel_scale * factor in 0.025–0.04 band).
const SPRITE_PIXEL_SCALE: float = 0.026

signal visuals_ready
signal post_bootstrap_refreshed

var entity_sprites_enabled: bool = true
var entity_voxel_models_enabled: bool = true
var feature_billboards_enabled: bool = true
var vegetation_voxel_models_enabled: bool = true
var vegetation_billboard_distance_columns: int = 72
var spawn_marker_textures_enabled: bool = true
var max_feature_billboards_per_chunk: int = 48

var chunk_manager: ChunkManager
var _cache: Dictionary = {}
var _gen: Node
var _initialized: bool = false
var _visuals_committed: bool = false
var _post_bootstrap_done: bool = false



func _enter_tree() -> void:
	add_to_group("game_visual_registry")


func _ready() -> void:
	call_deferred("_initialize")


func _initialize() -> void:
	if _initialized:
		return
	_ensure_gen()
	var perf = get_tree().get_first_node_in_group("performance_service")
	if perf and perf.has_method("ensure_ready"):
		await perf.ensure_ready()
	if perf and perf.quality:
		apply_performance_config(perf.quality)
	preload_game_bundle()
	_initialized = true
	# Textures only here — ChunkManager is created after world_features bootstrap (VoxelWorld).
	var existing_cm: ChunkManager = get_tree().get_first_node_in_group("chunk_manager")
	if existing_cm:
		on_chunk_manager_ready(existing_cm)


## Wait for procedural texture bundle only (safe during world_features bootstrap).
func ensure_textures_ready() -> void:
	while not _initialized:
		await get_tree().process_frame


## Back-compat alias — do not block on ChunkManager (avoids VoxelWorld deadlock).
func ensure_ready() -> void:
	await ensure_textures_ready()


func ensure_visuals_committed() -> void:
	await ensure_textures_ready()
	while not _visuals_committed and is_inside_tree():
		await get_tree().process_frame


func is_ready() -> bool:
	return _initialized and _visuals_committed


func textures_ready() -> bool:
	return _initialized


func on_chunk_manager_ready(cm: ChunkManager) -> void:
	if cm == null:
		return
	chunk_manager = cm
	_bind_chunk_streaming()
	if _initialized:
		_commit_visual_refresh()


func refresh_all_visuals() -> void:
	if not is_inside_tree():
		return
	if not _initialized:
		return
	preload_game_bundle()
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_refresh_scene_visuals()


## Public alias used by debug tooling and legacy callers.
func refresh_all() -> void:
	refresh_all_visuals()


## One-time refresh after ChunkManager + WorldVisuals exist and initial chunks are loaded.
func post_bootstrap_refresh() -> void:
	if _post_bootstrap_done:
		return
	await ensure_textures_ready()
	if not is_inside_tree():
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null:
		return
	await _await_initial_chunks()
	if not is_inside_tree():
		return
	var world_visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if world_visuals == null:
		await get_tree().process_frame
		world_visuals = get_tree().get_first_node_in_group("world_visuals_root")
	if not _visuals_committed:
		_commit_visual_refresh()
	else:
		refresh_all()
	_post_bootstrap_done = true
	post_bootstrap_refreshed.emit()


func generate_game_visual_bundle() -> Dictionary:
	_ensure_gen()
	if _gen == null or not _gen.has_method("generate_game_visual_bundle"):
		push_warning("[GameVisualRegistry] generate_game_visual_bundle unavailable on texture generator")
		return {}
	var bundle: Dictionary = _gen.generate_game_visual_bundle()
	for key in bundle.keys():
		var tex: Texture2D = bundle[key]
		if tex != null:
			_cache[str(key)] = tex
	return bundle


func apply_performance_config(cfg: _PerformanceQualityConfig) -> void:
	if cfg == null:
		return
	if "entity_sprites_enabled" in cfg:
		entity_sprites_enabled = bool(cfg.entity_sprites_enabled)
	else:
		entity_sprites_enabled = bool(cfg.combat_visuals_enabled)
	if "entity_voxel_models_enabled" in cfg:
		entity_voxel_models_enabled = bool(cfg.entity_voxel_models_enabled)
	if "feature_billboards_enabled" in cfg:
		feature_billboards_enabled = bool(cfg.feature_billboards_enabled)
	if "vegetation_voxel_models_enabled" in cfg:
		vegetation_voxel_models_enabled = bool(cfg.vegetation_voxel_models_enabled)
	if "vegetation_billboard_distance_columns" in cfg:
		vegetation_billboard_distance_columns = maxi(int(cfg.vegetation_billboard_distance_columns), 16)
	if "spawn_marker_textures_enabled" in cfg:
		spawn_marker_textures_enabled = bool(cfg.spawn_marker_textures_enabled)
	if "max_feature_billboards_per_chunk" in cfg:
		max_feature_billboards_per_chunk = maxi(int(cfg.max_feature_billboards_per_chunk), 0)


func clear_cache() -> void:
	_cache.clear()


func preload_game_bundle() -> void:
	generate_game_visual_bundle()


func get_entity_texture(entity_id: StringName) -> Texture2D:
	return _get_or_fallback("entity_%s" % entity_id, _category_entity(), entity_id)


func get_enemy_texture(enemy_id: StringName) -> Texture2D:
	return _get_or_fallback("entity_%s" % enemy_id, _category_entity(), enemy_id)


func get_vegetation_texture(plant_id: StringName, stage: int) -> Texture2D:
	var variant := StringName("%s_s%d" % [plant_id, stage])
	var key := "veg_%s" % variant
	return _get_or_fallback(key, _category_vegetation(), variant)


func get_building_texture(building_id: StringName) -> Texture2D:
	return _get_or_fallback("building_%s" % building_id, _category_building(), building_id)


func get_item_texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null
	return _get_or_fallback("item_%s" % item_id, _category_particle(), StringName(item_id))


func get_combat_texture(variant_id: StringName) -> Texture2D:
	return _get_or_fallback(str(variant_id), _category_particle(), variant_id)


func get_spawn_texture(is_boss: bool) -> Texture2D:
	if not spawn_marker_textures_enabled:
		return null
	return get_combat_texture(&"spawn_boss" if is_boss else &"spawn_miniboss")


## Unified entity/enemy sprite lookup. Accepts "rabbit" or "entity_rabbit".
func get_sprite_texture(sprite_id: String) -> Texture2D:
	if not entity_sprites_enabled:
		return null
	var id := str(sprite_id).strip_edges()
	if id.is_empty():
		return null
	if id.begins_with("entity_"):
		return get_entity_texture(StringName(id.substr(7)))
	return get_entity_texture(StringName(id))


## Unified vegetation/building billboard lookup.
## Accepts "tree_s2", "tree" with stage, "building_town_hall", or "town_hall".
func get_billboard_texture(billboard_id: String, stage: int = -1) -> Texture2D:
	if not feature_billboards_enabled:
		return null
	var id := str(billboard_id).strip_edges()
	if id.is_empty():
		return null
	if id.begins_with("building_"):
		return get_building_texture(StringName(id.substr(9)))
	if id.begins_with("veg_"):
		return _texture_from_veg_key(id)
	if stage >= 0:
		return get_vegetation_texture(StringName(id), stage)
	var plant_stage := _parse_plant_stage_id(id)
	if not plant_stage.is_empty():
		return get_vegetation_texture(plant_stage.plant, plant_stage.stage)
	var building_tex := get_building_texture(StringName(id))
	if building_tex != null:
		return building_tex
	return get_vegetation_texture(StringName(id), 0)


func sprite_pixel_size() -> float:
	return SPRITE_PIXEL_SCALE * _WorldSettings.get_active().voxel_scale


func sprite_half_height(tex: Texture2D, pixel_size: float = -1.0) -> float:
	if pixel_size < 0.0:
		pixel_size = sprite_pixel_size()
	if tex == null:
		return 0.4 * _WorldSettings.get_active().voxel_scale
	var tex_h := float(tex.get_height())
	if tex_h <= 0.0:
		tex_h = 40.0
	return tex_h * pixel_size * 0.5


func entity_anchor_height_offset(tex: Texture2D) -> float:
	return sprite_half_height(tex)


func vegetation_anchor_height_offset(tex: Texture2D, plant_id: StringName, stage: int) -> float:
	var half := sprite_half_height(tex)
	var vs: float = _WorldSettings.get_active().voxel_scale
	var growth := float(stage + 1) / 3.0
	match str(plant_id):
		"grass_tuft", "grass":
			return half + 0.04 * vs
		"tall_grass":
			return half + 0.1 * vs * growth
		"wildflower":
			return half + 0.06 * vs
		"fern":
			return half + 0.08 * vs * growth
		"bush":
			return half + 0.08 * vs * growth
		_:
			return half + 0.12 * vs * growth


func apply_to_sprite3d(sprite: Sprite3D, tex: Texture2D, tint: Color = Color.WHITE, pixel_size: float = -1.0) -> void:
	configure_sprite3d(sprite, tex, tint, pixel_size)


func configure_building_mesh(
	mesh_inst: MeshInstance3D,
	tex: Texture2D,
	size: Vector3,
	tint: Color = Color.WHITE
) -> void:
	if mesh_inst == null:
		return
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.position.y = size.y * 0.5
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tex == null:
		mesh_inst.material_override = null
		mesh_inst.visible = false
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.roughness = 0.9
	mat.metallic = 0.0
	mesh_inst.material_override = mat
	mesh_inst.visible = true


func anchor_sprite_y(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	column_x: float,
	column_z: float,
	height_offset: float = 0.0
) -> float:
	var surface := _EntityNavigation.walkable_y_light(world, chunk_manager, crystal_manager, column_x, column_z)
	return surface + height_offset + SURFACE_LIFT


func column_sprite_position(
	world: InfiniteNoiseWorld,
	chunk_manager: ChunkManager,
	crystal_manager,
	column_x: float,
	column_z: float,
	height_offset: float = 0.0
) -> Vector3:
	var y := anchor_sprite_y(world, chunk_manager, crystal_manager, column_x, column_z, height_offset)
	return _WorldVisualCoords.column_to_world_pos(column_x, y, column_z)


func configure_sprite3d(sprite: Sprite3D, tex: Texture2D, tint: Color = Color.WHITE, pixel_size: float = -1.0) -> void:
	if sprite == null:
		return
	if pixel_size < 0.0:
		pixel_size = sprite_pixel_size()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.centered = true
	sprite.pixel_size = pixel_size
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.alpha_scissor_threshold = 0.05
	sprite.shaded = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.render_priority = 3
	sprite.sorting_offset = 1.0
	if tex == null:
		sprite.texture = null
		sprite.material_override = null
		sprite.visible = false
		return
	sprite.texture = tex
	sprite.modulate = Color.WHITE
	var mat := _make_billboard_material(tex, tint)
	mat.render_priority = 2
	sprite.material_override = mat
	sprite.visible = true


func _make_billboard_material(tex: Texture2D, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.albedo_texture = tex
	mat.albedo_color = tint
	return mat


func _get_or_fallback(cache_key: String, category: int, variant_id: StringName) -> Texture2D:
	if _cache.has(cache_key):
		return _cache[cache_key]
	var tex := _generate(category, variant_id)
	if tex != null:
		_cache[cache_key] = tex
		return tex
	var alt_key := cache_key
	if _cache.has(alt_key):
		return _cache[alt_key]
	return null


func _generate(category: int, variant_id: StringName) -> Texture2D:
	_ensure_gen()
	if _gen == null or not _gen.has_method("generate_texture"):
		return null
	return _gen.generate_texture(category, variant_id, _texture_size_for(category, variant_id))


func _texture_size_for(category: int, variant_id: StringName) -> int:
	if category == _category_vegetation():
		return 40
	if category == _category_particle():
		match variant_id:
			&"hit_flash":
				return 16
			&"shatter":
				return 24
			&"spawn_miniboss":
				return 32
			&"spawn_boss", &"victory_glow":
				return 48 if variant_id == &"spawn_boss" else 64
			_:
				return 32
	return 48


func _parse_plant_stage_id(id: String) -> Dictionary:
	var idx := id.rfind("_s")
	if idx < 0:
		return {}
	var plant_part := id.substr(0, idx)
	var stage_part := id.substr(idx + 2)
	if not stage_part.is_valid_int():
		return {}
	return {"plant": StringName(plant_part), "stage": int(stage_part)}


func _texture_from_veg_key(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var body := key.substr(4) if key.begins_with("veg_") else key
	var plant_stage := _parse_plant_stage_id(body)
	if not plant_stage.is_empty():
		return get_vegetation_texture(plant_stage.plant, plant_stage.stage)
	return _get_or_fallback(key, _category_vegetation(), StringName(body))


func _ensure_gen() -> void:
	if _gen != null:
		return
	var autoload: Node = get_node_or_null("/root/CrystalTextureGenerator")
	if autoload == null and is_inside_tree():
		autoload = get_tree().root.get_node_or_null("CrystalTextureGenerator")
	if autoload != null:
		_gen = autoload
		return
	push_warning("[GameVisualRegistry] CrystalTextureGenerator autoload missing")
	_gen = _GeneratorScript.new()
	if is_inside_tree():
		_gen.name = "CrystalTextureGenerator_Fallback"
		add_child(_gen)


func _category_entity() -> int:
	_ensure_gen()
	return _gen.Category.ENTITY


func _category_vegetation() -> int:
	_ensure_gen()
	return _gen.Category.VEGETATION


func _category_building() -> int:
	_ensure_gen()
	return _gen.Category.BUILDING


func _category_particle() -> int:
	_ensure_gen()
	return _gen.Category.PARTICLE


func _await_initial_chunks(max_frames: int = 900) -> void:
	if chunk_manager == null:
		return
	var frames := 0
	while chunk_manager.chunks.is_empty() and frames < max_frames and is_inside_tree():
		await get_tree().process_frame
		frames += 1
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not chunk_manager.has_method("spawn_area_ready"):
		return
	frames = 0
	var col: Vector3 = player.get_voxel_position() if player.has_method("get_voxel_position") else player.global_position
	var cx := floori(col.x / float(ChunkData.SIZE))
	var cz := floori(col.z / float(ChunkData.SIZE))
	while not chunk_manager.spawn_area_ready(cx, cz) and frames < max_frames and is_inside_tree():
		await get_tree().process_frame
		frames += 1


func _bind_chunk_streaming() -> void:
	if chunk_manager == null:
		return
	if chunk_manager.has_signal("chunk_ready") \
			and not chunk_manager.chunk_ready.is_connected(_on_chunk_ready_refresh):
		chunk_manager.chunk_ready.connect(_on_chunk_ready_refresh)


func _on_chunk_ready_refresh(_coord: Vector2i, _data: ChunkData) -> void:
	if not _initialized or chunk_manager == null:
		return
	call_deferred("_refresh_scene_visuals")


func _commit_visual_refresh() -> void:
	if not is_inside_tree():
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	if chunk_manager == null:
		return
	_refresh_scene_visuals()
	if not _visuals_committed:
		_visuals_committed = true
		visuals_ready.emit()


func _refresh_scene_visuals() -> void:
	if not is_inside_tree():
		return
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	for entity in get_tree().get_nodes_in_group("world_entity"):
		if is_instance_valid(entity) and entity.has_method("refresh_visual"):
			entity.refresh_visual()
	for enemy in get_tree().get_nodes_in_group("crystal_enemy"):
		if is_instance_valid(enemy) and enemy.has_method("refresh_visual"):
			enemy.refresh_visual()
	var crystal = get_tree().get_first_node_in_group("crystal_manager")
	if crystal and crystal.has_method("refresh_spawn_marker_textures"):
		crystal.refresh_spawn_marker_textures()
	var feat = get_tree().get_first_node_in_group("feature_visual_layer")
	if feat and feat.has_method("repopulate_all") and chunk_manager != null:
		feat.repopulate_all()
	var combat = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat and combat.has_method("reload_textures"):
		combat.reload_textures()