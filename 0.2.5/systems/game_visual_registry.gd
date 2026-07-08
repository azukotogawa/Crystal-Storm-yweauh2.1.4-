class_name GameVisualRegistry
extends Node

const _PerformanceQualityConfig = preload("res://config/performance_quality_config.gd")
const _GeneratorScript = preload("res://systems/crystal_texture_generator.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _WorldVisualCoords = preload("res://helpers/world_visual_coords.gd")

## Small lift above walkable surface to avoid z-fighting with voxel tops.
const SURFACE_LIFT: float = 0.08

signal visuals_ready

var entity_sprites_enabled: bool = true
var feature_billboards_enabled: bool = true
var spawn_marker_textures_enabled: bool = true
var max_feature_billboards_per_chunk: int = 48

var _cache: Dictionary = {}
var _gen: Node
var _initialized: bool = false



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
	_refresh_scene_visuals()
	visuals_ready.emit()


func ensure_ready() -> void:
	while not _initialized:
		await get_tree().process_frame


func is_ready() -> bool:
	return _initialized


func refresh_all_visuals() -> void:
	_refresh_scene_visuals()


## Public alias used by debug tooling and legacy callers.
func refresh_all() -> void:
	refresh_all_visuals()


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
	if "feature_billboards_enabled" in cfg:
		feature_billboards_enabled = bool(cfg.feature_billboards_enabled)
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


func apply_to_sprite3d(sprite: Sprite3D, tex: Texture2D, tint: Color = Color.WHITE, pixel_size: float = 0.009) -> void:
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	mat.albedo_color = tint
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


func configure_sprite3d(sprite: Sprite3D, tex: Texture2D, tint: Color = Color.WHITE, pixel_size: float = 0.009) -> void:
	if sprite == null:
		return
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.centered = true
	sprite.pixel_size = pixel_size
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.alpha_scissor_threshold = 0.05
	sprite.shaded = false
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.render_priority = 2
	sprite.sorting_offset = 0.5
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
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
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
	if is_inside_tree():
		var autoload := get_tree().root.get_node_or_null("CrystalTextureGenerator")
		if autoload != null:
			_gen = autoload
	if _gen == null:
		_gen = _GeneratorScript.new()


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


func _refresh_scene_visuals() -> void:
	if not is_inside_tree():
		return
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
	if feat and feat.has_method("repopulate_all"):
		feat.repopulate_all()
	var combat = get_tree().get_first_node_in_group("combat_visual_feedback")
	if combat and combat.has_method("reload_textures"):
		combat.reload_textures()