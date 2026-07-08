class_name TopographicalMapBuilder
extends RefCounted

const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")
const _ChannelRegistry = preload("res://world/channel_registry.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")

const _MARKER_TOWN_R := 2
const _MARKER_RUIN_R := 3
const _MARKER_SPAWN_R := 1


static func build_local_map(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	center_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fast_sampling: bool = true,
	internal_divisor: int = 2
) -> ImageTexture:
	var job := begin_job(world, crystal, center_cell, cfg, false, fast_sampling, internal_divisor)
	while not process_job(job, 999999, 1_000_000):
		pass
	return finalize_job(job)


static func begin_job(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	center_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fullscreen: bool = false,
	fast_sampling: bool = true,
	internal_divisor: int = 2,
	channel_overlay: bool = false
) -> Dictionary:
	var display_size: int = cfg.fullscreen_size if fullscreen else cfg.minimap_size
	var radius: int = cfg.fullscreen_half_extent_cells if fullscreen else cfg.minimap_radius_cells
	var divisor: int = maxi(internal_divisor, 1)
	var internal_size: int = maxi(32, int(ceil(float(display_size) / float(divisor))))
	var stride: int = maxi(
		cfg.sample_stride,
		maxi(1, int(ceil(float(radius * 2) / float(internal_size))))
	)
	var image := Image.create(internal_size, internal_size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.05, 0.06, 0.08, 1.0))
	var bounds := _world_bounds(center_cell, internal_size, stride)
	var job := {
		"world": world,
		"crystal": crystal,
		"center": center_cell,
		"cfg": cfg,
		"image": image,
		"display_size": display_size,
		"internal_size": internal_size,
		"size": internal_size,
		"stride": stride,
		"px": 0,
		"fullscreen": fullscreen,
		"fast_sampling": fast_sampling,
		"channel_overlay": channel_overlay,
		"column_cache": {},
		"marker_cells": {},
		"crystal_cells": {},
		"bounds": bounds,
	}
	_prepare_marker_cells(job)
	_refresh_crystal_overlay(job)
	return job


static func try_incremental_recenter(job: Dictionary, new_center: Vector2i) -> bool:
	if job.is_empty() or job.get("image") == null:
		return false
	var old_center: Vector2i = job.get("center", Vector2i.ZERO)
	if old_center == new_center:
		return true
	var stride: int = int(job.stride)
	var size: int = int(job.size)
	var dx_cells: int = new_center.x - old_center.x
	var dz_cells: int = new_center.y - old_center.y
	var dx_px: int = int(round(float(dx_cells) / float(stride)))
	var dz_px: int = int(round(float(dz_cells) / float(stride)))
	if absi(dx_px) >= size or absi(dz_px) >= size:
		return false
	if absi(dx_px) + absi(dz_px) > maxi(size / 3, 8):
		return false

	var image: Image = job.image
	var shifted := Image.create(size, size, false, Image.FORMAT_RGBA8)
	shifted.fill(Color(0.05, 0.06, 0.08, 1.0))
	for py in size:
		for px in size:
			var src_x: int = px + dx_px
			var src_y: int = py + dz_px
			if src_x < 0 or src_y < 0 or src_x >= size or src_y >= size:
				continue
			shifted.set_pixel(px, py, image.get_pixel(src_x, src_y))

	job.image = shifted
	job.center = new_center
	job.px = 0
	job.column_cache = {}
	job.bounds = _world_bounds(new_center, size, stride)
	_refresh_crystal_overlay(job)

	var dirty := _dirty_rect_after_shift(size, dx_px, dz_px)
	job.dirty_rect = dirty
	job.incremental = true
	return true


static func process_job_rows(job: Dictionary, max_rows: int) -> bool:
	var size: int = int(job.get("size", 0))
	var budget_px: int = maxi(max_rows, 1) * size
	return process_job(job, budget_px, 4_000)


static func process_job(job: Dictionary, pixel_budget: int, time_budget_us: int) -> bool:
	if job.is_empty():
		return true
	if job.get("world") == null or job.get("image") == null:
		return true
	var world: InfiniteNoiseWorld = job.world
	if not is_instance_valid(world):
		return true

	var image: Image = job.image
	var size: int = int(job.size)
	var px_start: int = int(job.get("px", 0))
	var pixels_done := 0
	var t0 := Time.get_ticks_usec()
	var dirty: Rect2i = job.get("dirty_rect", Rect2i(0, 0, size, size))
	var incremental: bool = bool(job.get("incremental", false))

	while px_start < size * size and pixels_done < pixel_budget:
		if Time.get_ticks_usec() - t0 >= time_budget_us:
			break
		var px: int = px_start % size
		var py: int = int(px_start / size)
		px_start += 1
		if incremental and not _rect_contains(dirty, px, py):
			continue

		var wx := int(job.center.x) + int((px - size / 2) * int(job.stride))
		var wz := int(job.center.y) + int((py - size / 2) * int(job.stride))
		image.set_pixel(px, py, _sample_cell_fast(world, job, wx, wz))
		pixels_done += 1

	job.px = px_start
	if px_start >= size * size:
		job.erase("dirty_rect")
		job.erase("incremental")
	return px_start >= size * size


static func finalize_job(job: Dictionary) -> ImageTexture:
	var image: Image = job.get("image")
	if image == null:
		return null
	var display_size: int = int(job.get("display_size", image.get_width()))
	if display_size > image.get_width():
		image.resize(display_size, display_size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


static func build_full_map(
	world: InfiniteNoiseWorld,
	crystal: CrystalManager,
	player_cell: Vector2i,
	cfg: _TopographicalMapConfig,
	fast_sampling: bool = true,
	internal_divisor: int = 2
) -> ImageTexture:
	return build_local_map(world, crystal, player_cell, cfg, fast_sampling, internal_divisor)


static func refresh_crystal_overlay(job: Dictionary) -> void:
	_refresh_crystal_overlay(job)


static func repaint_crystal_overlay(job: Dictionary, pixel_budget: int, time_budget_us: int) -> bool:
	if job.is_empty() or job.get("image") == null:
		return true
	var world = job.get("world")
	if world == null or not is_instance_valid(world):
		return true
	_refresh_crystal_overlay(job)
	var image: Image = job.image
	var size: int = int(job.size)
	var center: Vector2i = job.center
	var stride: int = int(job.stride)
	var queue: Array = job.get("crystal_repaint_queue", [])
	if queue.is_empty():
		for pos_variant in job.get("crystal_cells", {}).keys():
			var pos: Vector2i = pos_variant
			var px: int = int(round(float(pos.x - center.x) / float(stride))) + size / 2
			var py: int = int(round(float(pos.y - center.y) / float(stride))) + size / 2
			if px < 0 or py < 0 or px >= size or py >= size:
				continue
			queue.append(px + py * size)
		job.crystal_repaint_queue = queue
		job.crystal_repaint_idx = 0
	if queue.is_empty():
		return true

	var idx: int = int(job.get("crystal_repaint_idx", 0))
	var done := 0
	var t0 := Time.get_ticks_usec()
	while idx < queue.size() and done < pixel_budget:
		if Time.get_ticks_usec() - t0 >= time_budget_us:
			break
		var linear: int = int(queue[idx])
		idx += 1
		var px: int = linear % size
		var py: int = int(linear / size)
		var wx := int(center.x) + int((px - size / 2) * stride)
		var wz := int(center.y) + int((py - size / 2) * stride)
		image.set_pixel(px, py, _sample_cell_fast(world, job, wx, wz))
		done += 1
	job.crystal_repaint_idx = idx
	if idx >= queue.size():
		job.erase("crystal_repaint_queue")
		job.erase("crystal_repaint_idx")
		return true
	return false


static func _world_bounds(center: Vector2i, size: int, stride: int) -> Rect2i:
	var half: int = int(ceil(float(size * stride) * 0.5))
	return Rect2i(center.x - half, center.y - half, half * 2, half * 2)


static func _rect_contains(rect: Rect2i, px: int, py: int) -> bool:
	return px >= rect.position.x and py >= rect.position.y \
		and px < rect.position.x + rect.size.x and py < rect.position.y + rect.size.y


static func _dirty_rect_after_shift(size: int, dx_px: int, dz_px: int) -> Rect2i:
	if dx_px > 0:
		return Rect2i(0, 0, mini(dx_px, size), size)
	if dx_px < 0:
		return Rect2i(maxi(0, size + dx_px), 0, mini(-dx_px, size), size)
	if dz_px > 0:
		return Rect2i(0, 0, size, mini(dz_px, size))
	if dz_px < 0:
		return Rect2i(0, maxi(0, size + dz_px), size, mini(-dz_px, size))
	return Rect2i(0, 0, size, size)


static func _prepare_marker_cells(job: Dictionary) -> void:
	var markers: Dictionary = {}
	for town in _FeatureRegistry.get_towns():
		if typeof(town) != TYPE_DICTIONARY:
			continue
		_paint_disk(markers, town.get("center", Vector2i.ZERO), _MARKER_TOWN_R, 1)
	for center in _FeatureRegistry.get_ruin_centers():
		_paint_disk(markers, center, _MARKER_RUIN_R, 2)

	var crystal = job.get("crystal")
	if crystal != null and is_instance_valid(crystal) and crystal.has_method("get_active_spawns"):
		for spawn in crystal.get_active_spawns():
			if spawn == null:
				continue
			_paint_disk(markers, spawn.world_pos, _MARKER_SPAWN_R, 3 if spawn.is_boss else 4)

	job.marker_cells = markers


static func _paint_disk(markers: Dictionary, center: Vector2i, radius: int, kind: int) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2(dx, dz).length() > float(radius) + 0.25:
				continue
			markers[Vector2i(center.x + dx, center.y + dz)] = kind


static func _refresh_crystal_overlay(job: Dictionary) -> void:
	var overlay: Dictionary = {}
	var crystal = job.get("crystal")
	var bounds: Rect2i = job.get("bounds", Rect2i())
	if crystal == null or not is_instance_valid(crystal):
		job.crystal_cells = overlay
		return
	if crystal.has_method("get_depth_cells_in_rect"):
		overlay = crystal.get_depth_cells_in_rect(bounds)
	elif crystal.has_method("get_fluid_sim"):
		var sim = crystal.get_fluid_sim()
		if sim:
			var min_depth := 0.04
			if "sim_config" in crystal and crystal.sim_config:
				min_depth = float(crystal.sim_config.min_depth)
			for pos_variant in sim.depth.keys():
				var pos: Vector2i = pos_variant
				if not _rect_contains(bounds, pos.x, pos.y):
					continue
				var depth: float = float(sim.depth[pos])
				if depth >= min_depth:
					overlay[pos] = depth
	job.crystal_cells = overlay


static func clone_job_state(job: Dictionary) -> Dictionary:
	if job.is_empty():
		return {}
	var image: Image = job.get("image")
	if image == null:
		return {}
	return {
		"world": job.get("world"),
		"crystal": job.get("crystal"),
		"center": job.get("center", Vector2i.ZERO),
		"cfg": job.get("cfg"),
		"image": image.duplicate(),
		"display_size": job.get("display_size", image.get_width()),
		"internal_size": job.get("internal_size", image.get_width()),
		"size": job.get("size", image.get_width()),
		"stride": job.get("stride", 1),
		"px": image.get_width() * image.get_height(),
		"fullscreen": job.get("fullscreen", false),
		"fast_sampling": job.get("fast_sampling", true),
		"channel_overlay": job.get("channel_overlay", false),
		"column_cache": job.get("column_cache", {}).duplicate(true),
		"marker_cells": job.get("marker_cells", {}).duplicate(true),
		"crystal_cells": job.get("crystal_cells", {}).duplicate(true),
		"bounds": job.get("bounds", Rect2i()),
	}


static func _sample_cell_fast(world: InfiniteNoiseWorld, job: Dictionary, wx: int, wz: int) -> Color:
	var key := Vector2i(wx, wz)
	var markers: Dictionary = job.get("marker_cells", {})
	if markers.has(key):
		return _marker_color(int(markers[key]), job.cfg)

	var cache: Dictionary = job.column_cache
	if cache.has(key):
		var cached: Color = cache[key]
		return _apply_crystal_tint(cached, job, key)

	var cfg: _TopographicalMapConfig = job.cfg
	var tile: int = world.get_tile_type(float(wx), float(wz))
	var color: Color
	if bool(job.get("fast_sampling", true)):
		color = _tile_color(tile, cfg)
	else:
		var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
		color = _biome_color(biome.get("name", "plains"), cfg)

	var height: float = world.get_surface_height(float(wx), float(wz))
	var shade: float = clampf((height - 30.0) / 90.0, 0.0, 1.0)
	color = color.lerp(cfg.color_height_shadow, shade * 0.35)

	if _CrystalTypes.is_water_tile(tile):
		color = color.lerp(cfg.color_water, 0.75)
	elif bool(job.get("channel_overlay", false)) and _ChannelRegistry.is_channel(wx, wz):
		color = color.lerp(cfg.color_channel, 0.8)

	cache[key] = color
	job.column_cache = cache
	return _apply_crystal_tint(color, job, key)


static func _apply_crystal_tint(base: Color, job: Dictionary, key: Vector2i) -> Color:
	var crystal_cells: Dictionary = job.get("crystal_cells", {})
	if not crystal_cells.has(key):
		return base
	var cfg: _TopographicalMapConfig = job.cfg
	var depth: float = float(crystal_cells[key])
	return base.lerp(cfg.color_crystal, clampf(depth / 4.0, 0.25, 0.9))


static func _marker_color(kind: int, cfg: _TopographicalMapConfig) -> Color:
	match kind:
		1: return cfg.color_town
		2: return cfg.color_ruin
		3: return cfg.color_spawn_boss
		4: return cfg.color_spawn_miniboss
		_: return cfg.color_town


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
