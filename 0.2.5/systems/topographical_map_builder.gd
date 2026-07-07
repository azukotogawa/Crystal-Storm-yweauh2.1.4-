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
	cfg: _TopographicalMapConfig
) -> ImageTexture:
	var size: int = cfg.minimap_size
	var radius: int = cfg.minimap_radius_cells
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	if world == null:
		return ImageTexture.create_from_image(image)

	var stride: int = maxi(cfg.sample_stride, maxi(1, int(ceil(float(radius * 2) / float(size)))))
	for py in size:
		for px in size:
			var wx := center_cell.x + int((px - size / 2) * stride)
			var wz := center_cell.y + int((py - size / 2) * stride)
			image.set_pixel(px, py, _sample_cell(world, crystal, wx, wz, cfg))

	return ImageTexture.create_from_image(image)


static func build_full_map(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	player_cell: Vector2i,
	cfg: _TopographicalMapConfig
) -> ImageTexture:
	var size: int = cfg.fullscreen_size
	var half: int = cfg.fullscreen_half_extent_cells
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	if world == null:
		return ImageTexture.create_from_image(image)

	var stride: int = maxi(cfg.sample_stride, maxi(1, int(ceil(float(half * 2) / float(size)))))
	for py in size:
		for px in size:
			var wx := player_cell.x + int((px - size / 2) * stride)
			var wz := player_cell.y + int((py - size / 2) * stride)
			image.set_pixel(px, py, _sample_cell(world, crystal, wx, wz, cfg))

	return ImageTexture.create_from_image(image)


static func _sample_cell(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	wx: int,
	wz: int,
	cfg: _TopographicalMapConfig
) -> Color:
	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var biome_name: String = biome.get("name", "plains")
	var color := _biome_color(biome_name, cfg)

	var height: float = world.get_surface_height(float(wx), float(wz))
	var shade: float = clampf((height - 30.0) / 90.0, 0.0, 1.0)
	color = color.lerp(cfg.color_height_shadow, shade * 0.35)

	var tile: int = world.get_tile_type(float(wx), float(wz))
	if _CrystalTypes.is_water_tile(tile):
		color = color.lerp(cfg.color_water, 0.75)
	if _ChannelRegistry.is_channel(wx, wz):
		color = color.lerp(cfg.color_channel, 0.8)

	if crystal and crystal.has_method("get_depth_at"):
		var depth: float = crystal.get_depth_at(wx, wz)
		if depth >= crystal.sim_config.min_depth if crystal.sim_config else 0.04:
			color = color.lerp(cfg.color_crystal, clampf(depth / 4.0, 0.25, 0.9))

	for town in _FeatureRegistry.get_towns():
		var center: Vector2i = town.get("center", Vector2i.ZERO)
		if Vector2(wx, wz).distance_to(Vector2(center)) <= 2.0:
			return cfg.color_town

	if crystal and crystal.has_method("get_spawn_at_cell"):
		var spawn = crystal.get_spawn_at_cell(wx, wz)
		if spawn:
			if spawn.is_boss:
				return cfg.color_spawn_boss
			return cfg.color_spawn_miniboss

	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.has("kind") and int(feat.kind) == _WorldFeatureTypes.FeatureKind.RUIN:
		return cfg.color_ruin

	return color


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