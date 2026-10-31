extends SceneTree

const _Loader = preload("res://helpers/crystal_voxel_loader.gd")
const _Catalog = preload("res://helpers/vegetation_voxel_catalog.gd")

const _TREES := ["oak", "birch", "pine"]
const _PLANTS := [
	"grass_tuft_v0_s1.json",
	"tall_grass_v0_s1.json",
	"fern_v0_s1.json",
	"bush_v0_s2.json",
	"flower_red_v0_s1.json",
	"flower_yellow_v1_s1.json",
	"flower_blue_v2_s1.json",
	"flower_white_v0_s0.json",
	"reeds_v0_s1.json",
	"mushroom_v0_s1.json",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var worst_tree := 0
	var worst_plant := 0
	for species in _TREES:
		for stage in [0, 1, 2]:
			for lod in [0, 1]:
				var path := "res://assets/voxel/vegetation/lod/tree_%s_v0_s%d_lod%d.json" % [species, stage, lod]
				var quads := _quads(path)
				if quads < 0:
					failed = true
					continue
				print("VEG QUAD %s quads=%d" % [path.get_file(), quads])
				if quads > 5000:
					push_error("FAIL %s quads %d" % [path.get_file(), quads])
					failed = true
				worst_tree = maxi(worst_tree, quads)
		var mirror_path := "res://assets/voxel/vegetation/lod/tree_%s_v0_s2_lod0.json" % species
		var mirror_mesh := _Loader.mesh_variant(mirror_path, 1)
		var mirror_quads := _Loader.quad_count(mirror_mesh) if mirror_mesh != null else -1
		print("VEG QUAD %s mirror quads=%d" % [species, mirror_quads])
		if mirror_quads < 0 or mirror_quads > 5000:
			push_error("FAIL mirror %s" % species)
			failed = true
	for file_name in _PLANTS:
		var plant_path: String = "res://assets/voxel/vegetation/lod/" + str(file_name)
		var plant_quads := _quads(plant_path)
		if plant_quads < 0:
			failed = true
			continue
		print("VEG QUAD %s quads=%d" % [str(file_name), plant_quads])
		if plant_quads > 300 or plant_quads < 6:
			push_error("FAIL %s quads %d" % [str(file_name), plant_quads])
			failed = true
		worst_plant = maxi(worst_plant, plant_quads)
	var oak := _Catalog.model_path("tree", 2, 3, 5, "forest", 0)
	var far := _Catalog.model_path("tree", 2, 3, 5, "forest", 1)
	var flower := _Catalog.model_path("wildflower", 1, 8, 2, "plains", 0)
	var sapling := _Catalog.model_path("sapling", 2, 1, 1, "marsh", 0)
	if not oak.contains("tree_") or not oak.ends_with("_lod0.json"):
		push_error("FAIL catalog oak %s" % oak)
		failed = true
	if not far.ends_with("_lod1.json"):
		push_error("FAIL catalog lod1 %s" % far)
		failed = true
	if not flower.contains("/flower_"):
		push_error("FAIL catalog flower %s" % flower)
		failed = true
	if not sapling.contains("_s1_lod"):
		push_error("FAIL catalog sapling %s" % sapling)
		failed = true
	if _Catalog.mirror_variant("tree", 4, 9) < 0:
		push_error("FAIL mirror variant")
		failed = true
	var layer := FileAccess.get_file_as_string("res://world/feature_visual_layer.gd")
	if layer.find("MultiMesh") < 0 or layer.find("vegetation_billboard_distance_columns") < 0 or layer.find("visual_proximity.gd") < 0:
		push_error("FAIL feature layer instancing")
		failed = true
	else:
		print("OK chunk MultiMesh placement")
	print("VEG BEFORE box quads tree=18 bush=18 grass_tuft=24")
	print("VEG AFTER worst_tree_quads=%d worst_plant_quads=%d lod0_columns=%d" % [worst_tree, worst_plant, _Catalog.LOD0_COLUMNS])
	var holder := Node3D.new()
	root.add_child(holder)
	var shown := _Loader.mesh_for(oak)
	if shown == null:
		push_error("FAIL show mesh")
		failed = true
	else:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = shown
		multi.instance_count = 4
		for i in 4:
			multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(i * 3.0, 0, 0)))
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = multi
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(inst)
	var samples: Array[float] = []
	for _i in 45:
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var mean := 0.0
	for sample in samples:
		mean += sample
	mean /= float(maxi(samples.size(), 1))
	var fps := 1000.0 / maxf(mean, 0.001)
	print("VEG FPS mesh_sample=%.1f frame_ms=%.2f" % [fps, mean])
	if failed:
		print("VEG ART FAIL")
		quit(1)
		return
	print("VEG ART OK")
	quit(0)


func _quads(path: String) -> int:
	if not FileAccess.file_exists(path):
		push_error("FAIL missing %s" % path)
		return -1
	var rig := _Loader.rig_for(path)
	if rig.is_empty():
		push_error("FAIL load %s" % path)
		return -1
	return int(rig.get("quads", -1))
