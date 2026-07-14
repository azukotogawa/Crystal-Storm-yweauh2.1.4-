extends SceneTree
## P1 regression: all builtin plants have multi-part voxel props on MEDIUM+.


const _VoxelPropBuilder = preload("res://helpers/voxel_prop_builder.gd")
const _PlantableRegistry = preload("res://world/plantable_registry.gd")
const _PerfConfig = preload("res://config/performance_quality_config.gd")
const PLANT_IDS: Array[String] = [
	"grass_tuft",
	"tall_grass",
	"wildflower",
	"fern",
	"bush",
	"tree",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var med = _PerfConfig.apply_preset(1)
	if not med.vegetation_voxel_models_enabled:
		push_error("MEDIUM must enable vegetation_voxel_models")
		failed = true
	else:
		print("OK MEDIUM vegetation_voxel_models_enabled")

	var layer_src := (load("res://world/feature_visual_layer.gd") as GDScript).source_code
	if "vegetation_voxel_models_enabled" not in layer_src:
		push_error("feature_visual_layer must read vegetation_voxel_models_enabled")
		failed = true
	else:
		print("OK feature_visual_layer voxel gate")

	_PlantableRegistry.ensure_builtins()
	var vs: float = load("res://config/world_settings.gd").get_active().voxel_scale
	var min_tree_h := vs * 3.0

	for plant_id in PLANT_IDS:
		var prop := _VoxelPropBuilder.build_plant(plant_id, 2)
		var boxes := prop.get_child_count()
		var min_boxes := 3 if plant_id != "wildflower" else 3
		var h := _VoxelPropBuilder.model_height(prop)
		if boxes < min_boxes:
			push_error("%s needs >=%d voxel boxes, got %d" % [plant_id, min_boxes, boxes])
			failed = true
			continue
		if plant_id == "tree" and h < min_tree_h:
			push_error("tree height %.2f below %.2f" % [h, min_tree_h])
			failed = true
			continue
		print("OK %s boxes=%d height=%.2f" % [plant_id, boxes, h])

	if failed:
		quit(1)
	print("All vegetation voxel model tests OK")
	quit(0)