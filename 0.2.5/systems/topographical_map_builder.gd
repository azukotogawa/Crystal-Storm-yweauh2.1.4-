class_name TopographicalMapBuilder
extends RefCounted

const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")


static func build_local_map(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	center_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fast_sampling: bool = false
) -> ImageTexture:
	var size: int = cfg.minimap_size
	var radius: int = cfg.minimap_radius_cells
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	if world == null:
		return ImageTexture.create_from_image(image)

	var ctx := _make_context(fast_sampling)
	var stride: int = maxi(cfg.sample_stride, maxi(1, int(ceil(float(radius * 2) / float(size)))))
	for py in size:
		for px in size:
			var wx := center_cell.x + int((px - size / 2) * stride)
			var wz := center_cell.y + int((py - size / 2) * stride)
			image.set_pixel(px, py, _sample_cell(world, crystal, wx, wz, cfg, ctx))

	return ImageTexture.create_from_image(image)


static func begin_job(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	center_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fullscreen: bool = false,
	fast_sampling: bool = false
) -> Dictionary:
	var size: int = cfg.fullscreen_size if fullscreen else cfg.minimap_size
	var radius: int = cfg.fullscreen_half_extent_cells if fullscreen else cfg.minimap_radius_cells
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	var stride: int = maxi(cfg.sample_stride, maxi(1, int(ceil(float(radius * 2) / float(size)))))
	return {
		"world": world,
		"crystal": crystal,
		"center": center_cell,
		"cfg": cfg,
		"image": image,
		"size": size,
		"stride": stride,
		"py": 0,
		"fullscreen": fullscreen,
		"towns": _FeatureRegistry.get_towns(),
		"fast_sampling": fast_sampling,
	}


static func process_job_rows(job: Dictionary, max_rows: int) -> bool:
	if job.is_empty():
		return true
	if job.get("world") == null or job.get("image") == null:
		return true
	var world: InfiniteNoiseWorld = job.world
	if not is_instance_valid(world):
		return true
	var crystal = job.get("crystal")
	var cfg = job.get("cfg") as _TopographicalMapConfig
	if cfg == null:
		return true
	var image: Image = job.image
	var size: int = int(job.size)
	var stride: int = int(job.stride)
	var center: Vector2i = job.center
	var py: int = int(job.py)
	var rows_done := 0
	while py < size and rows_done < max_rows:
		for px in size:
			var wx := center.x + int((px - size / 2) * stride)
			var wz := center.y + int((py - size / 2) * stride)
			image.set_pixel(px, py, _sample_cell(world, crystal, wx, wz, cfg, job))
		py += 1
		rows_done += 1
	job.py = py
	return py >= size


static func finalize_job(job: Dictionary) -> ImageTexture:
	var image: Image = job.get("image")
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


static func build_full_map(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	player_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fast_sampling: bool = false
) -> ImageTexture:
	var size: int = cfg.fullscreen_size
	var half: int = cfg.fullscreen_half_extent_cells
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	if world == null:
		return ImageTexture.create_from_image(image)

	var ctx := _make_context(fast_sampling)
	var stride: int = maxi(cfg.sample_stride, maxi(1, int(ceil(float(half * 2) / float(size)))))
	for py in size:
		for px in size:
			var wx := player_cell.x + int((px - size / 2) * stride)
			var wz := player_cell.y + int((py - size / 2) * stride)
			image.set_pixel(px, py, _sample_cell(world, crystal, wx, wz, cfg, ctx))

	return ImageTexture.create_from_image(image)


static func _make_context(fast_sampling: bool) -> Dictionary:
	return {
		"towns": _FeatureRegistry.get_towns(),
		"fast_sampling": fast_sampling,
	}


static func _sample_cell(
	world: InfiniteNoiseWorld,
	crystal: Variant,
	wx: int,
	wz: int,
	cfg: _TopographicalMapConfig,
	ctx: Dictionary = {}
) -> Color:
	if world == null or not is_instance_valid(world):
		return Color(0.05, 0.06, 0.08, 1.0)

	var color: Color
	if bool(ctx.get("fast_sampling", false)):
		var tile_fast: int = world.get_tile_type(float(wx), float(wz))
		color = _tile_color(tile_fast, cfg)
	else:
		var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
		var biome_name: String = biome.get("name", "plains")
		color = _biome_color(biome_name, cfg)

	var height: float = world.get_surface_height(float(wx), float(wz))
	var shade: float = clampf((height - 30.0) / 90.0, 0.0, 1.0)
	color = color.lerp(cfg.color_height_shadow, shade * 0.35)

	var tile: int = world.get_tile_type(float(wx), float(wz))
	if _CrystalTypes.is_water_tile(tile):
		color = color.lerp(cfg.color_water, 0.75)
	if _ChannelRegistry.is_channel(wx, wz):
		color = color.lerp(cfg.color_channel, 0.8)

	if crystal != null and is_instance_valid(crystal) and crystal.has_method("get_depth_at"):
		var min_depth := 0.04
		if "sim_config" in crystal and crystal.sim_config:
			min_depth = float(crystal.sim_config.min_depth)
		var depth: float = crystal.get_depth_at(wx, wz)
		if depth >= min_depth:
			color = color.lerp(cfg.color_crystal, clampf(depth / 4.0, 0.25, 0.9))

	var towns: Array = ctx.get("towns", [])
	for town in towns:
		if typeof(town) != TYPE_DICTIONARY:
			continue
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		if Vector2(wx, wz).distance_to(Vector2(center)) <= 2.0:
			return cfg.color_town

	if crystal != null and is_instance_valid(crystal) and crystal.has_method("get_spawn_at_cell"):
		var spawn = crystal.get_spawn_at_cell(wx, wz)
		if spawn:
			if spawn.is_boss:
				return cfg.color_spawn_boss
			return cfg.color_spawn_miniboss

	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.RUIN:
		return cfg.color_ruin

	return color


static func _tile_color(tile_id: int, cfg: _TopographicalMapConfig) -> Color:
	if _CrystalTypes.is_water_tile(tile_id) or tile_id == VoxelTypes.RIVER:
		return cfg.color_water
	if tile_id in [
		VoxelTypes.GRASSLAND, VoxelTypes.GRASSLAND2, VoxelTypes.GRASSLAND3,
		VoxelTypes.GRASSLAND4, VoxelTypes.GRASSLAND5, VoxelTypes.GRASS_TUFT, VoxelTypes.FARMLAND,
	]:
		return cfg.color_plains
	if tile_id == VoxelTypes.BUSH:
		return cfg.color_steppe
	if tile_id == VoxelTypes.TREE_TRUNK:
		return cfg.color_forest
	if tile_id in [VoxelTypes.STONE, VoxelTypes.STONE2, VoxelTypes.CAVE_STONE]:
		return cfg.color_highland
	return cfg.color_plains


static func _biome_color(name: String, cfg: _TopographicalMapConfig) -> Color:
	match name:
		"plains": return cfg.color_plains
		"steppe": return cfg.color_steppe
		"forest": return cfg.color_forest
		"marsh": return cfg.color_marsh
		"highland": return cfg.color_highland
		"ocean": return cfg.color_ocean
		"border_mountain": return cfg.color_mountain
		_: return cfg.color_plains