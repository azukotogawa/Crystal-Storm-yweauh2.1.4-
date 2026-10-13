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

	if failed:
		quit(1)
	print("All topographical map tests OK")
	quit(0)