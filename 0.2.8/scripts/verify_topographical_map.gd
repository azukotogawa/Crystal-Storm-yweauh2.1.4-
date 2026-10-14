extends SceneTree

const _TopographicalMapBuilder = preload("res://systems/topographical_map_builder.gd")
const _TopographicalMapConfig = preload("res://config/topographical_map_config.gd")

func _init() -> void:
	var failed := false

	var scr: GDScript = load("res://systems/topographical_map_builder.gd") as GDScript
	if scr == null or scr.reload() != OK:
		push_error("FAIL topographical_map_builder compile")
		failed = true
	else:
		print("OK topographical_map_builder compiles")

	var map_scr: GDScript = load("res://ui/topographical_map.gd") as GDScript
	if map_scr == null or map_scr.reload() != OK:
		push_error("FAIL topographical_map compile")
		failed = true
	else:
		print("OK topographical_map compiles")

	var cfg := _TopographicalMapConfig.create_default()
	var tex = _TopographicalMapBuilder.build_local_map(null, null, Vector2i.ZERO, cfg, true)
	if tex == null:
		push_error("null world should still return texture")
		failed = true
	else:
		print("OK build_local_map null world")

	var plains: Color = _TopographicalMapBuilder._tile_color(VoxelTypes.GRASSLAND, cfg)
	var forest: Color = _TopographicalMapBuilder._tile_color(VoxelTypes.TREE_TRUNK, cfg)
	if plains == forest:
		push_error("tile colors should differ for grassland vs tree")
		failed = true
	else:
		print("OK _tile_color grassland vs tree")

	var job: Dictionary = _TopographicalMapBuilder.begin_job(null, null, Vector2i(4, 4), cfg, false, true)
	if not job.has("fast_sampling") or not bool(job.fast_sampling):
		push_error("begin_job fast_sampling missing")
		failed = true
	else:
		print("OK begin_job fast_sampling")

	var safe = load("res://config/performance_quality_config.gd").apply_safe_mode()
	if safe.minimap_enabled:
		push_error("SAFE should disable minimap")
		failed = true
	else:
		print("OK SAFE minimap disabled")

	var low = load("res://config/performance_quality_config.gd").apply_preset(0)
	if low.minimap_enabled:
		push_error("LOW should disable minimap")
		failed = true
	else:
		print("OK LOW minimap disabled")

	var job2: Dictionary = _TopographicalMapBuilder.begin_job(null, null, Vector2i(10, 10), cfg, false, true, 2)
	var done: bool = _TopographicalMapBuilder.process_job(job2, 64, 2000)
	if not done:
		push_error("null world job should finish immediately")
		failed = true
	else:
		print("OK process_job budgeted")

	var scroll_cfg := _TopographicalMapConfig.create_default()
	scroll_cfg.minimap_size = 64
	scroll_cfg.minimap_radius_cells = 32
	scroll_cfg.sample_stride = 1
	var scroll: Dictionary = _TopographicalMapBuilder.begin_job(null, null, Vector2i.ZERO, scroll_cfg, false, true, 1)
	var scroll_size: int = int(scroll.size)
	var scroll_image: Image = scroll.image
	scroll_image.fill(Color(0, 0, 0, 1))
	scroll_image.set_pixel(scroll_size / 2, scroll_size / 2, Color(1, 0, 0, 1))
	var scroll_stride: int = int(scroll.stride)
	if not _TopographicalMapBuilder.try_incremental_recenter(scroll, Vector2i(scroll_stride, scroll_stride)):
		push_error("diagonal recenter should succeed")
		failed = true
	else:
		var shifted: Image = scroll.image
		var moved_px: Color = shifted.get_pixel(scroll_size / 2 - 1, scroll_size / 2 - 1)
		if moved_px.r < 0.9:
			push_error("recenter should scroll the world opposite player movement")
			failed = true
		else:
			print("OK incremental recenter scroll")
		var lead: Color = shifted.get_pixel(scroll_size - 1, scroll_size - 1)
		if lead.r < 0.04 or lead.r > 0.08:
			push_error("leading corner should stay the unpainted fill, got %s" % lead)
			failed = true
		elif not _TopographicalMapBuilder._pixel_in_dirty(scroll, scroll_size - 1, int(scroll_size / 2), scroll_size):
			push_error("walking +x must dirty the east edge")
			failed = true
		elif not _TopographicalMapBuilder._pixel_in_dirty(scroll, int(scroll_size / 2), scroll_size - 1, scroll_size):
			push_error("walking +z must dirty the south edge")
			failed = true
		elif _TopographicalMapBuilder._pixel_in_dirty(scroll, 0, int(scroll_size / 2), scroll_size):
			push_error("walking +x must leave the west edge clean")
			failed = true
		elif _TopographicalMapBuilder._pixel_in_dirty(scroll, int(scroll_size / 2), 0, scroll_size):
			push_error("walking +z must leave the north edge clean")
			failed = true
		else:
			print("OK leading-edge dirty rects")

	var west_cfg := _TopographicalMapConfig.create_default()
	west_cfg.minimap_size = 64
	west_cfg.minimap_radius_cells = 32
	west_cfg.sample_stride = 1
	var west: Dictionary = _TopographicalMapBuilder.begin_job(null, null, Vector2i.ZERO, west_cfg, false, true, 1)
	var west_size: int = int(west.size)
	var west_image: Image = west.image
	west_image.fill(Color(0, 0, 0, 1))
	west_image.set_pixel(west_size / 2, west_size / 2, Color(1, 0, 0, 1))
	var west_stride: int = int(west.stride)
	if not _TopographicalMapBuilder.try_incremental_recenter(west, Vector2i(-west_stride, 0)):
		push_error("west recenter should succeed")
		failed = true
	else:
		var west_moved: Color = (west.image as Image).get_pixel(west_size / 2 + 1, west_size / 2)
		if west_moved.r < 0.9:
			push_error("walking west should scroll the marker east on the image")
			failed = true
		elif not _TopographicalMapBuilder._pixel_in_dirty(west, 0, int(west_size / 2), west_size):
			push_error("walking west must dirty the west edge")
			failed = true
		elif _TopographicalMapBuilder._pixel_in_dirty(west, west_size - 1, int(west_size / 2), west_size):
			push_error("walking west must leave the east edge clean")
			failed = true
		else:
			print("OK west leading edge")

	var internal_w: int = (scroll.image as Image).get_width()
	scroll.display_size = internal_w * 2
	var upscaled: ImageTexture = _TopographicalMapBuilder.finalize_job(scroll)
	if (scroll.image as Image).get_width() != internal_w:
		push_error("finalize_job must not resize the working image")
		failed = true
	elif upscaled == null or upscaled.get_width() != internal_w * 2:
		push_error("finalize_job should upscale a copy for display")
		failed = true
	else:
		print("OK finalize keeps internal image")

	(scroll.image as Image).resize(internal_w * 2, internal_w * 2, Image.INTERPOLATE_NEAREST)
	if _TopographicalMapBuilder.try_incremental_recenter(scroll, Vector2i(80, 0)):
		push_error("upscaled working image must not incremental-scroll")
		failed = true
	else:
		print("OK reject scroll of display-sized image")

	var stamped: Dictionary = _TopographicalMapBuilder.begin_job(null, null, Vector2i(3, 3), scroll_cfg, false, true, 1)
	var state = load("res://world/world_state.gd").get_active()
	if int(stamped.get("content_revision", -2)) != state.mesh_input_revision():
		push_error("map job should stamp the live terrain and feature revision")
		failed = true
	else:
		var previous_terrain: int = state.terrain_revision
		state.terrain_revision += 1
		if int(stamped.content_revision) == state.mesh_input_revision():
			push_error("a dig must stale the map stamp")
			failed = true
		else:
			var cloned: Dictionary = _TopographicalMapBuilder.clone_job_state(stamped)
			if int(cloned.get("content_revision", -3)) != int(stamped.content_revision):
				push_error("clone_job_state dropped content_revision")
				failed = true
			else:
				print("OK content revision stamps a dig")
		state.terrain_revision = previous_terrain

	if failed:
		quit(1)
	print("All topographical map tests OK")
	quit(0)