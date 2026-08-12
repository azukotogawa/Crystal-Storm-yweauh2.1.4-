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

## On-disk authored structure meshes (visual id → Mesh resource). Only wood_wall is filled for now.
const AUTHORED_BUILDING_MESH_PATHS: Dictionary = {
	"wood_wall": "res://assets/structures/wood_wall/wood_wall.obj",
}
## Optional albedo overrides (nearest-filter wood texture).
const AUTHORED_BUILDING_ALBEDO_PATHS: Dictionary = {
	"wood_wall": "res://assets/structures/wood_wall/wood_wall_albedo.png",
}

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
## Procedural textures are generated once and reused for the session.
var _bundle_ready: bool = false
## Session cache of loaded authored building meshes (id → Mesh).
var _authored_building_meshes: Dictionary = {}
## Session cache of authored albedo textures (id → Texture2D).
var _authored_building_albedos: Dictionary = {}
## Hitch counters (measurement / verify).
var _bundle_gen_count: int = 0
var _refresh_all_count: int = 0
var _refresh_scene_count: int = 0
## Single-tick / teleport visual trace.
var _trace_refresh_enabled: bool = false
var _trace_refresh_all: int = 0
var _trace_refresh_scene: int = 0
var _trace_refresh_entity: int = 0
var _trace_preload_calls: int = 0
var _trace_preload_noop: int = 0
var _trace_preload_regen: int = 0
var _trace_clear_cache: int = 0
var _trace_generate_bundle: int = 0
var _trace_fallback_generate: int = 0
var _trace_refresh_callers: Array = []
var _trace_preload_callers: Array = []
var _trace_clear_callers: Array = []


func reset_trace_counters() -> void:
	_trace_refresh_all = 0
	_trace_refresh_scene = 0
	_trace_refresh_entity = 0
	_trace_preload_calls = 0
	_trace_preload_noop = 0
	_trace_preload_regen = 0
	_trace_clear_cache = 0
	_trace_generate_bundle = 0
	_trace_fallback_generate = 0
	_trace_refresh_callers.clear()
	_trace_preload_callers.clear()
	_trace_clear_callers.clear()
	_trace_refresh_enabled = true


func stop_trace_counters() -> void:
	_trace_refresh_enabled = false


func get_trace_refresh_counts() -> Dictionary:
	return {
		"refresh_all": _trace_refresh_all,
		"refresh_scene": _trace_refresh_scene,
		"refresh_entity_visual": _trace_refresh_entity,
		"preload_calls": _trace_preload_calls,
		"preload_noop": _trace_preload_noop,
		"preload_regen": _trace_preload_regen,
		"clear_cache": _trace_clear_cache,
		"generate_bundle": _trace_generate_bundle,
		"fallback_generate": _trace_fallback_generate,
		"bundle_gen_count": _bundle_gen_count,
		"bundle_ready": _bundle_ready,
		"cache_size": _cache.size(),
		"refresh_callers": _trace_refresh_callers.duplicate(),
		"preload_callers": _trace_preload_callers.duplicate(),
		"clear_callers": _trace_clear_callers.duplicate(),
	}


func _trace_note_caller(bucket: Array, label: String) -> void:
	if not _trace_refresh_enabled:
		return
	bucket.append(label)



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


func refresh_all_visuals(caller: String = "unknown") -> void:
	if not is_inside_tree():
		return
	if not _initialized:
		return
	_refresh_all_count += 1
	if _trace_refresh_enabled:
		_trace_refresh_all += 1
		_trace_note_caller(_trace_refresh_callers, caller)
	# Reuse session textures — never regenerate the full bundle on refresh.
	if not _bundle_ready or _cache.is_empty():
		preload_game_bundle(false, "refresh_all_visuals:" + caller)
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	_refresh_scene_visuals()


## Public alias used by debug tooling and legacy callers.
func refresh_all(caller: String = "unknown") -> void:
	refresh_all_visuals(caller)


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
		# Scene binding only — textures already in cache from first preload.
		refresh_all("post_bootstrap_refresh")
	_post_bootstrap_done = true
	post_bootstrap_refreshed.emit()


func generate_game_visual_bundle() -> Dictionary:
	_ensure_gen()
	if _gen == null or not _gen.has_method("generate_game_visual_bundle"):
		push_warning("[GameVisualRegistry] generate_game_visual_bundle unavailable on texture generator")
		return {}
	if _trace_refresh_enabled:
		_trace_generate_bundle += 1
	var bundle: Dictionary = _gen.generate_game_visual_bundle()
	_bundle_gen_count += 1
	for key in bundle.keys():
		var tex: Texture2D = bundle[key]
		if tex != null:
			_cache[str(key)] = tex
	_bundle_ready = not _cache.is_empty()
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


func clear_cache(caller: String = "unknown") -> void:
	if _trace_refresh_enabled:
		_trace_clear_cache += 1
		_trace_note_caller(_trace_clear_callers, caller)
	_cache.clear()
	_bundle_ready = false


## Generate procedural combat/entity/veg/item textures once per session.
## Subsequent calls are no-ops unless force=true or cache was cleared.
func preload_game_bundle(force: bool = false, caller: String = "unknown") -> void:
	if _trace_refresh_enabled:
		_trace_preload_calls += 1
		_trace_note_caller(_trace_preload_callers, caller if not force else caller + ":force")
	if _bundle_ready and not force and not _cache.is_empty():
		if _trace_refresh_enabled:
			_trace_preload_noop += 1
		return
	if _trace_refresh_enabled:
		_trace_preload_regen += 1
	generate_game_visual_bundle()


func get_hitch_counters() -> Dictionary:
	return {
		"bundle_gen_count": _bundle_gen_count,
		"refresh_all_count": _refresh_all_count,
		"refresh_scene_count": _refresh_scene_count,
		"cache_size": _cache.size(),
		"bundle_ready": _bundle_ready,
	}


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


## True when visual id has an on-disk mesh under AUTHORED_BUILDING_MESH_PATHS.
func has_authored_building_mesh(building_id: String) -> bool:
	return AUTHORED_BUILDING_MESH_PATHS.has(str(building_id))


## Resource path for authored mesh (empty if none).
func authored_building_mesh_path(building_id: String) -> String:
	return str(AUTHORED_BUILDING_MESH_PATHS.get(str(building_id), ""))


## Load (and cache) authored Mesh for a building visual id. Returns null if missing.
func get_authored_building_mesh(building_id: String) -> Mesh:
	var id := str(building_id)
	if _authored_building_meshes.has(id):
		return _authored_building_meshes[id] as Mesh
	var path := authored_building_mesh_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	var mesh: Mesh = _extract_mesh_from_resource(res)
	if mesh == null:
		return null
	# Stamp identity so verifies can prove the bind path without re-loading.
	if mesh is Resource:
		(mesh as Resource).set_meta("authored_resource_path", path)
		(mesh as Resource).set_meta("building_visual_id", id)
	_authored_building_meshes[id] = mesh
	return mesh


## Authored albedo for a building id (falls back to null → caller uses procedural).
func get_authored_building_albedo(building_id: String) -> Texture2D:
	var id := str(building_id)
	if _authored_building_albedos.has(id):
		return _authored_building_albedos[id] as Texture2D
	var path := str(AUTHORED_BUILDING_ALBEDO_PATHS.get(id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex != null:
		_authored_building_albedos[id] = tex
	return tex


func _extract_mesh_from_resource(res: Resource) -> Mesh:
	if res is Mesh:
		return res as Mesh
	if res is PackedScene:
		var inst: Node = (res as PackedScene).instantiate()
		var mesh := _find_mesh_in_node(inst)
		if inst:
			inst.queue_free()
		return mesh
	return null


func _find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			return mi.mesh
	for child in node.get_children():
		var found := _find_mesh_in_node(child)
		if found != null:
			return found
	return null


## Bind structure presentation mesh. Prefers on-disk authored mesh for ids that have one
## (currently wood_wall). Other ids use multi-box temporary silhouettes.
## Textures: authored albedo when present, else procedural `tex`.
func configure_building_mesh(
	mesh_inst: MeshInstance3D,
	tex: Texture2D,
	size: Vector3,
	tint: Color = Color.WHITE,
	building_id: String = ""
) -> void:
	if mesh_inst == null:
		return
	var id := building_id
	if id.is_empty() and mesh_inst.has_meta("building_visual_id"):
		id = str(mesh_inst.get_meta("building_visual_id"))
	mesh_inst.position = Vector3.ZERO
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.set_meta("building_visual_id", id)

	var authored: Mesh = get_authored_building_mesh(id)
	var used_authored := authored != null
	if used_authored:
		mesh_inst.mesh = authored
		mesh_inst.set_meta("uses_authored_mesh", true)
		mesh_inst.set_meta("authored_resource_path", authored_building_mesh_path(id))
		# Authored plank wall has real construction silhouette (not multi-box part count).
		mesh_inst.set_meta("structure_part_count", -1)
	else:
		var parts: Array = structure_mesh_parts(id, size)
		mesh_inst.mesh = build_structure_array_mesh(parts)
		mesh_inst.set_meta("uses_authored_mesh", false)
		mesh_inst.set_meta("authored_resource_path", "")
		mesh_inst.set_meta("structure_part_count", parts.size())

	var albedo: Texture2D = get_authored_building_albedo(id)
	if albedo == null:
		albedo = tex
	if albedo == null and mesh_inst.mesh == null:
		mesh_inst.material_override = null
		mesh_inst.visible = false
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = albedo
	mat.albedo_color = structure_material_tint(id, tint)
	mat.roughness = structure_roughness(id)
	mat.metallic = structure_metallic(id)
	if id == "gate" or id == "town_hall":
		mat.emission_enabled = true
		mat.emission = mat.albedo_color * 0.35
		mat.emission_energy_multiplier = 0.45 if id == "gate" else 0.55
	# Authored wood: keep material path explicit for verifies.
	if used_authored:
		mat.set_meta("authored_albedo_path", str(AUTHORED_BUILDING_ALBEDO_PATHS.get(id, "")))
	mesh_inst.material_override = mat
	mesh_inst.visible = true


## Public silhouette parts for verifies (center + size boxes in local ground space).
func structure_mesh_parts(building_id: String, fallback_size: Vector3 = Vector3(1, 1.5, 1)) -> Array:
	match building_id:
		"gate":
			# Open passage: two posts + lintel (clear middle).
			return [
				{"center": Vector3(-0.42, 1.0, 0.0), "size": Vector3(0.26, 2.05, 0.42)},
				{"center": Vector3(0.42, 1.0, 0.0), "size": Vector3(0.26, 2.05, 0.42)},
				{"center": Vector3(0.0, 1.95, 0.0), "size": Vector3(1.12, 0.32, 0.48)},
			]
		"bridge":
			# Flat crossing deck + side rails (low profile).
			return [
				{"center": Vector3(0.0, 0.22, 0.0), "size": Vector3(1.35, 0.28, 1.35)},
				{"center": Vector3(-0.58, 0.48, 0.0), "size": Vector3(0.14, 0.42, 1.2)},
				{"center": Vector3(0.58, 0.48, 0.0), "size": Vector3(0.14, 0.42, 1.2)},
			]
		"wood_wall":
			# Solid obstacle face (slightly thinner timber look).
			return [
				{"center": Vector3(0.0, 0.85, 0.0), "size": Vector3(0.92, 1.55, 0.92)},
				{"center": Vector3(0.0, 1.68, 0.0), "size": Vector3(1.0, 0.18, 1.0)},
			]
		"stone_wall":
			# Heavier stone block + cap.
			return [
				{"center": Vector3(0.0, 0.95, 0.0), "size": Vector3(1.05, 1.75, 1.05)},
				{"center": Vector3(0.0, 1.88, 0.0), "size": Vector3(1.12, 0.22, 1.12)},
			]
		"ruin_pillar":
			# Environmental: tall broken pillar + rubble base (not a wall slab).
			return [
				{"center": Vector3(0.0, 0.18, 0.0), "size": Vector3(1.05, 0.35, 1.05)},
				{"center": Vector3(-0.08, 1.35, 0.06), "size": Vector3(0.48, 2.35, 0.48)},
				{"center": Vector3(0.22, 2.35, -0.12), "size": Vector3(0.28, 0.45, 0.28)},
			]
		"town_hall":
			# Settlement landmark: wide hall + pitched roof mass.
			return [
				{"center": Vector3(0.0, 1.1, 0.0), "size": Vector3(2.35, 2.15, 2.15)},
				{"center": Vector3(0.0, 2.55, 0.0), "size": Vector3(2.55, 0.95, 2.35)},
				{"center": Vector3(0.0, 0.35, 1.05), "size": Vector3(0.55, 0.7, 0.2)},
			]
		_:
			var s := fallback_size
			if s.length() < 0.01:
				s = Vector3(1.0, 1.5, 1.0)
			return [{"center": Vector3(0.0, s.y * 0.5, 0.0), "size": s}]


func structure_material_tint(building_id: String, base: Color = Color.WHITE) -> Color:
	match building_id:
		"gate":
			return base * Color(1.08, 0.95, 0.72)
		"bridge":
			return base * Color(0.78, 0.88, 1.05)
		"wood_wall":
			return base * Color(1.0, 0.92, 0.8)
		"stone_wall":
			return base * Color(0.92, 0.92, 0.95)
		"ruin_pillar":
			return base * Color(0.85, 0.82, 0.78)
		"town_hall":
			return base * Color(1.05, 0.98, 0.88)
		_:
			return base


func structure_roughness(building_id: String) -> float:
	match building_id:
		"stone_wall", "ruin_pillar":
			return 0.95
		"wood_wall", "bridge", "gate":
			return 0.82
		"town_hall":
			return 0.75
		_:
			return 0.9


func structure_metallic(building_id: String) -> float:
	match building_id:
		"gate":
			return 0.12
		"stone_wall":
			return 0.05
		_:
			return 0.0


## Merge axis-aligned boxes into one ArrayMesh (temporary distinct silhouettes).
func build_structure_array_mesh(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part_v in parts:
		var part: Dictionary = part_v
		var c: Vector3 = part.get("center", Vector3.ZERO)
		var s: Vector3 = part.get("size", Vector3.ONE)
		_st_add_box(st, c, s)
	st.generate_normals()
	return st.commit()


func _st_add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var p := [
		center + Vector3(-hx, -hy, -hz),
		center + Vector3(hx, -hy, -hz),
		center + Vector3(hx, hy, -hz),
		center + Vector3(-hx, hy, -hz),
		center + Vector3(-hx, -hy, hz),
		center + Vector3(hx, -hy, hz),
		center + Vector3(hx, hy, hz),
		center + Vector3(-hx, hy, hz),
	]
	# Face quads as two triangles each (CCW outward).
	var faces: Array = [
		[0, 1, 2, 3], # -Z
		[5, 4, 7, 6], # +Z
		[4, 0, 3, 7], # -X
		[1, 5, 6, 2], # +X
		[3, 2, 6, 7], # +Y
		[4, 5, 1, 0], # -Y
	]
	var uvs: Array = [
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)
	]
	for face in faces:
		var i0: int = face[0]
		var i1: int = face[1]
		var i2: int = face[2]
		var i3: int = face[3]
		st.set_uv(uvs[0])
		st.add_vertex(p[i0])
		st.set_uv(uvs[1])
		st.add_vertex(p[i1])
		st.set_uv(uvs[2])
		st.add_vertex(p[i2])
		st.set_uv(uvs[0])
		st.add_vertex(p[i0])
		st.set_uv(uvs[2])
		st.add_vertex(p[i2])
		st.set_uv(uvs[3])
		st.add_vertex(p[i3])


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
	if _trace_refresh_enabled:
		_trace_fallback_generate += 1
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
	# Intentionally no chunk_ready → full scene refresh.
	# Per-chunk billboards/entities are owned by FeatureVisualLayer + EntityManager
	# (budgeted). Reconnecting a global refresh here regenerates work every load.
	if chunk_manager == null:
		return
	if chunk_manager.has_signal("chunk_ready") \
			and chunk_manager.chunk_ready.is_connected(_on_chunk_ready_refresh):
		chunk_manager.chunk_ready.disconnect(_on_chunk_ready_refresh)


## Legacy no-op: kept so old connects cannot reintroduce full-world refresh.
func _on_chunk_ready_refresh(_coord: Vector2i, _data: ChunkData) -> void:
	pass


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
	_refresh_scene_count += 1
	if _trace_refresh_enabled:
		_trace_refresh_scene += 1
	if chunk_manager == null:
		chunk_manager = get_tree().get_first_node_in_group("chunk_manager")
	for entity in get_tree().get_nodes_in_group("world_entity"):
		if is_instance_valid(entity) and entity.has_method("refresh_visual"):
			if _trace_refresh_enabled:
				_trace_refresh_entity += 1
			entity.refresh_visual()
	for enemy in get_tree().get_nodes_in_group("crystal_enemy"):
		if is_instance_valid(enemy) and enemy.has_method("refresh_visual"):
			if _trace_refresh_enabled:
				_trace_refresh_entity += 1
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