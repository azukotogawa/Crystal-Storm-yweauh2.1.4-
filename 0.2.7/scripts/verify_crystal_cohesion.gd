extends SceneTree
## Cohesive crystal mesh is centered and swells with depth.
## Dig shards and hit markers land in world space.


const _CrystalClusterMesh = preload("res://helpers/crystal_cluster_mesh.gd")
const _CrystalChunkLayer = preload("res://crystal/crystal_chunk_layer.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _Quality = preload("res://config/performance_quality_config.gd")


class _FakeTarget extends Node3D:
	func get_combat_center() -> Vector3:
		return Vector3(8.0, 4.0, 6.0)

	func get_combat_radius() -> float:
		return 0.7


func _init() -> void:
	OS.set_environment("CRYSTALSTORM_CRYSTAL_RENDERER", "procedural")
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var ws = _WorldSettings.get_active()
	var s: float = ws.voxel_scale
	var mesh := _CrystalClusterMesh.get_mesh()
	var aabb := mesh.get_aabb()
	var center := aabb.get_center()
	if absf(center.x) > s * 0.15 or absf(center.z) > s * 0.15:
		push_error("crystal mesh should sit on the cell center, center=%s" % str(center))
		failed = true
	elif aabb.position.y >= 0.0 or aabb.position.y + aabb.size.y <= 0.0:
		push_error("crystal mesh should straddle the origin vertically, aabb=%s" % str(aabb))
		failed = true
	elif aabb.size.x < s * 0.7:
		push_error("crystal body should fill most of a cell, size.x=%f" % aabb.size.x)
		failed = true
	elif mesh.get_faces().size() != 90:
		push_error("full crystal mesh should stay 30 tris, faces=%d" % mesh.get_faces().size())
		failed = true
	else:
		print("OK cohesive crystal mesh center=%s size=%s" % [str(center), str(aabb.size)])

	var layer := _CrystalChunkLayer.new()
	layer.setup(Vector2i(0, 0), StandardMaterial3D.new())
	var shallow := CrystalCell.new(Vector2i(2, 2), 10.0, 0.15, 0)
	layer.rebuild([shallow], _CrystalClusterMesh.LOD_FULL)
	var mm: MultiMesh = (layer.get_node("CrystalFluid") as MultiMeshInstance3D).multimesh
	var shallow_scale := mm.get_instance_transform(0).basis.get_scale().x
	var deep := CrystalCell.new(Vector2i(2, 2), 10.0, ws.layer_height(), 0)
	layer.rebuild([deep], _CrystalClusterMesh.LOD_FULL)
	var deep_scale := mm.get_instance_transform(0).basis.get_scale().x
	if shallow_scale >= 0.7 or deep_scale <= 0.95 or deep_scale < shallow_scale * 1.5:
		push_error("crystal should swell with depth, shallow=%f deep=%f" % [shallow_scale, deep_scale])
		failed = true
	else:
		print("OK liquid swell shallow=%f deep=%f" % [shallow_scale, deep_scale])

	var frontier := CrystalCell.new(Vector2i(2, 2), 10.0, ws.layer_height(), 0)
	frontier.is_frontier = true
	frontier.neighbor_mask = 2
	layer.rebuild([frontier], _CrystalClusterMesh.LOD_FULL)
	var front_scale := mm.get_instance_transform(0).basis.get_scale().x
	if front_scale <= deep_scale:
		push_error("frontier cell should read wider than an interior-less mature cell")
		failed = true
	else:
		print("OK frontier footprint %f > mature %f" % [front_scale, deep_scale])

	var vfx := CombatVisualFeedback.new()
	root.add_child(vfx)
	var cfg := _Quality.create_default()
	cfg.max_burst_sprites = 16
	vfx.apply_performance_config(cfg)
	vfx.show_place_flash(Vector3(4.0, 8.0, 4.0), &"dig")
	var shards := 0
	for b in vfx._bursts:
		if bool(b.get("break_shard", false)):
			shards += 1
	if shards < 3:
		push_error("dig should spawn break shards, got %d" % shards)
		failed = true
	else:
		print("OK dig break shards=%d" % shards)

	vfx._bursts.clear()
	vfx.show_hit_marker(Vector3(2.0, 3.0, 4.0), Color(1.0, 0.4, 0.3), 0.8)
	var saw_marker := false
	var marker_ok := false
	for b in vfx._bursts:
		if not bool(b.get("hit_marker", false)):
			continue
		saw_marker = true
		var marker_mesh: MeshInstance3D = b.get("mesh")
		var torus := marker_mesh.mesh as TorusMesh
		var anchor: Node3D = b.get("anchor")
		if torus == null or not is_equal_approx(torus.outer_radius, 0.8):
			push_error("hit marker radius should match the hitbox")
			failed = true
		elif absf(anchor.global_position.x - 2.0) > 0.05 or absf(anchor.global_position.z - 4.0) > 0.05:
			push_error("hit marker should stay in world space, at %s" % str(anchor.global_position))
			failed = true
		else:
			marker_ok = true
	if not saw_marker:
		push_error("show_hit_marker did not create a world-space ring")
		failed = true
	elif marker_ok:
		print("OK hit marker ring")

	var target := _FakeTarget.new()
	root.add_child(target)
	vfx._on_entity_hit(target, 12.0, "sword")
	var label_ok := false
	for label in vfx._label_pool:
		if not label.visible:
			continue
		if absf(label.global_position.x - 8.0) < 0.05 and absf(label.global_position.y - 4.6) < 0.05:
			label_ok = true
	if not label_ok:
		push_error("entity damage number should sit on the world-space combat center")
		failed = true
	else:
		print("OK entity damage number on combat center")

	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "column_to_world(target_col.x)" not in weapon_src or "forward * _range_world(range_v)" not in weapon_src:
		push_error("weapon hit_pos must be world space for melee and ranged")
		failed = true
	else:
		print("OK weapon hit_pos is world space")

	if failed:
		quit(1)
		return
	print("All crystal cohesion tests OK")
	quit(0)
