extends SceneTree
## One gameplay unit: a voxel column is layer_height() world units.
## People, creatures, and crystal cells are sized in that unit.


const _WorldSettings = preload("res://config/world_settings.gd")
const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _EnemySpawnDef = preload("res://config/enemy_spawn_def.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var person: float = ws.player_height() / layer
	var body: float = ws.player_radius() / layer
	if person < 1.5 or person > 1.8:
		push_error("player should be about 1.6 voxels tall, got %f" % person)
		failed = true
	elif body < 0.2 or body > 0.4 or body >= person:
		push_error("player radius should be a fraction of a voxel, got %f" % body)
		failed = true
	else:
		print("OK player scale height=%.2f voxels radius=%.2f voxels" % [person, body])

	var creature: float = ws.small_creature_height() / layer
	if creature < 0.4 or creature >= person:
		push_error("small creatures should be shorter than the player, got %f voxels" % creature)
		failed = true
	else:
		print("OK creature scale %.2f voxels" % creature)

	var crystal: float = _CrystalClusterMesh.natural_height() / layer
	if crystal < 0.7 or crystal > 1.15:
		push_error("crystal cell should be about one voxel tall, got %f" % crystal)
		failed = true
	else:
		print("OK crystal natural height %.2f voxels" % crystal)

	var mite := _EnemySpawnDef.new()
	var mite_h := mite.mesh_height
	var mite_r: float = mite.mesh_radius * ws.voxel_scale
	if mite_h < 0.5 or mite_h > 1.0 or mite_r < layer * 0.15:
		push_error("mite body should be voxel-scaled, height_vox=%f radius_world=%f" % [mite_h, mite_r])
		failed = true
	else:
		print("OK mite body %.2f voxels tall" % mite_h)

	var probe_src := (load("res://player/voxel_floor_probe.gd") as GDScript).source_code
	if "player_floor_probe_radius" in probe_src or "player_radius()" not in probe_src:
		push_error("floor probe radius must follow player_radius")
		failed = true
	else:
		print("OK floor probe uses player radius")

	if failed:
		quit(1)
		return
	print("All world scale tests OK")
	quit(0)
