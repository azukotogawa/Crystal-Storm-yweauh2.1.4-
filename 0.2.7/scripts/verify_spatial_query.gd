extends SceneTree
## Spatial Query Layer unit contracts: insert/remove/move, radius/nearest/AABB/ray,
## deterministic ordering, chunk stream index, rebuild, perf vs linear scan.
## Usage: godot --headless -s scripts/verify_spatial_query.gd

const _SpatialQueryLayer = preload("res://systems/spatial_query_layer.gd")
const _SpatialQueryService = preload("res://systems/spatial_query_service.gd")
const _CombatHitResolver = preload("res://systems/combat_hit_resolver.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _run_and_quit() -> void:
	await _run()
	if _failed == 0:
		print("All spatial query unit tests OK")
		quit(0)
	else:
		push_error("verify_spatial_query: %d failure(s)" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)


func _run() -> void:
	_test_insert_remove_move()
	_test_radius_nearest_order()
	_test_aabb_ray_region()
	_test_chunk_streaming_index()
	_test_rebuild_saveload()
	_test_perf_not_full_scan()
	_test_consumer_combat_via_layer()
	# Flush deferred queue_free so production spawn sees a clean spatial service group.
	await process_frame
	_test_production_enemy_spawn_order()


func _test_insert_remove_move() -> void:
	var L = _SpatialQueryLayer.new()
	var id_a: int = L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(1, 0, 1), 0.3, "A", true, "a")
	var id_b: int = L.insert(_SpatialQueryLayer.CAT_AI, Vector3(100, 0, 100), 0.3, "B", true, "b")
	if L.count() != 2:
		_fail("insert should yield 2 entries")
	var near: Array = L.query_radius(Vector3(1, 0, 1), 2.0, _SpatialQueryLayer.CAT_ENTITY)
	if near.size() != 1 or str(near[0].payload) != "A":
		_fail("radius should find A only")
	if not L.remove(id_b):
		_fail("remove B failed")
	if L.count() != 1:
		_fail("after remove count should be 1")
	# Move A far away
	L.move(id_a, Vector3(50, 0, 50))
	var old_cell: Array = L.query_radius(Vector3(1, 0, 1), 2.0)
	if old_cell.size() != 0:
		_fail("old cell must not report moved object")
	var new_cell: Array = L.query_radius(Vector3(50, 0, 50), 2.0)
	if new_cell.size() != 1 or int(new_cell[0].id) != id_a:
		_fail("new cell must report moved object")
	print("OK insert/remove/move")


func _test_radius_nearest_order() -> void:
	var L = _SpatialQueryLayer.new()
	# Equal distance from origin: (1,0) and (0,1) both dist=1 — order by stable_key
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(1, 0, 0), 0.1, "z", true, "key_z")
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(0, 0, 1), 0.1, "a", true, "key_a")
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(3, 0, 0), 0.1, "far", true, "key_far")
	var radius_hits: Array = L.query_radius(Vector3.ZERO, 1.5, _SpatialQueryLayer.CAT_ENTITY)
	if radius_hits.size() != 2:
		_fail("radius 1.5 should hit 2 (got %d)" % radius_hits.size())
	if str(radius_hits[0].stable_key) != "key_a" or str(radius_hits[1].stable_key) != "key_z":
		_fail("deterministic order by stable_key on equal distance failed: %s %s" % [
			str(radius_hits[0].stable_key), str(radius_hits[1].stable_key)])
	var nearest: Array = L.query_nearest(Vector3.ZERO, _SpatialQueryLayer.CAT_ENTITY, 2)
	if nearest.size() != 2:
		_fail("nearest 2 should return 2")
	if str(nearest[0].stable_key) != "key_a":
		_fail("nearest first should be key_a")
	print("OK radius/nearest deterministic order")


func _test_aabb_ray_region() -> void:
	var L = _SpatialQueryLayer.new()
	L.insert(_SpatialQueryLayer.CAT_STRUCTURE, Vector3(5, 1, 5), 0.5, "s1", false, "s1")
	L.insert(_SpatialQueryLayer.CAT_STRUCTURE, Vector3(50, 1, 50), 0.5, "s2", false, "s2")
	var aabb: Array = L.query_aabb(Vector3(0, 0, 0), Vector3(10, 2, 10), _SpatialQueryLayer.CAT_STRUCTURE)
	if aabb.size() != 1 or str(aabb[0].payload) != "s1":
		_fail("AABB should hit s1 only")
	var ray: Array = L.query_ray(Vector3(0, 1, 5), Vector3(1, 0, 0), 20.0, _SpatialQueryLayer.CAT_STRUCTURE)
	if ray.is_empty() or str(ray[0].payload) != "s1":
		_fail("ray should hit s1")
	var reg: Array = L.iter_region(Vector2i(0, 0), Vector2i(1, 1), _SpatialQueryLayer.CAT_STRUCTURE)
	if reg.is_empty():
		_fail("region iter should find structure in cells")
	print("OK aabb/ray/region")


func _test_chunk_streaming_index() -> void:
	var L = _SpatialQueryLayer.new()
	L.chunk_size = 16
	var c0 := Vector2i(0, 0)
	var c1 := Vector2i(1, 0)
	L.mark_chunk_loaded(c0)
	L.insert(_SpatialQueryLayer.CAT_TERRAIN, Vector3(8, 0, 8), 8.0, {"chunk": c0}, false, "t0", c0)
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(2, 0, 2), 0.3, "e0", true, "e0", c0)
	if not L.is_chunk_loaded(c0):
		_fail("chunk 0 should be loaded")
	var neigh: Array = L.iter_chunk_neighborhood(c0, 0)
	if neigh.size() < 2:
		_fail("chunk neighborhood should list terrain+entity")
	# Unload removes objects when requested
	L.mark_chunk_unloaded(c0, true)
	if L.is_chunk_loaded(c0):
		_fail("chunk should be unloaded")
	if L.count() != 0:
		_fail("unload with remove_objects should clear chunk entries (got %d)" % L.count())
	# Service-style: load without wiping dynamics later
	L.mark_chunk_loaded(c1)
	L.insert(_SpatialQueryLayer.CAT_TERRAIN, Vector3(24, 0, 8), 8.0, {"chunk": c1}, false, "t1", c1)
	if L.loaded_chunk_count() != 1:
		_fail("one loaded chunk expected")
	print("OK chunk streaming index")


func _test_rebuild_saveload() -> void:
	var L = _SpatialQueryLayer.new()
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(1, 0, 1), 0.3, "pre", true, "pre")
	L.rebuild_begin()
	if L.count() != 0:
		_fail("rebuild_begin must clear")
	L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(2, 0, 2), 0.3, "post", true, "post")
	L.insert(_SpatialQueryLayer.CAT_AI, Vector3(3, 0, 3), 0.3, "ai", true, "ai")
	L.rebuild_end()
	var hits: Array = L.query_radius(Vector3(2.5, 0, 2.5), 5.0)
	if hits.size() != 2:
		_fail("after rebuild radius should see 2")
	# Service rebuild path
	var svc = _SpatialQueryService.new()
	if svc.layer == null:
		svc.layer = _SpatialQueryLayer.new()
	root.add_child(svc)
	svc.layer.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(10, 0, 10), 0.3, "x", true, "x")
	if svc.layer.count() != 1:
		_fail("pre-rebuild count")
	svc.rebuild_from_runtime()  # clear + rebind empty sources
	if svc.layer.count() != 0:
		_fail("rebuild_from_runtime with no sources should leave empty (got %d)" % svc.layer.count())
	# Re-insert after rebuild simulates save restore
	svc.layer.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(4, 0, 4), 0.3, "restored", true, "restored")
	var after: Array = svc.layer.query_radius(Vector3(4, 0, 4), 1.0)
	if after.size() != 1 or str(after[0].payload) != "restored":
		_fail("post-rebuild query membership")
	print("OK save/load rebuild API")
	_free_node(svc)


func _test_perf_not_full_scan() -> void:
	var L = _SpatialQueryLayer.new()
	L.cell_size = 8.0
	var n := 2000
	for i in n:
		# Spread across a large area so a small radius only hits few cells
		var x := float((i % 100) * 20)
		var z := float((i / 100) * 20)
		L.insert(_SpatialQueryLayer.CAT_ENTITY, Vector3(x, 0, z), 0.2, i, true, "e%04d" % i)
	var center := Vector3(0, 0, 0)
	var radius := 25.0
	var grid_hits: Array = L.query_radius(center, radius)
	var grid_examined: int = L.entries_examined
	var linear_hits: Array = L.query_radius_linear_scan(center, radius)
	var linear_examined: int = L.entries_examined
	if grid_hits.size() != linear_hits.size():
		_fail("grid and linear membership size mismatch %d vs %d" % [grid_hits.size(), linear_hits.size()])
	if grid_examined >= n:
		_fail("grid radius must examine fewer than N=%d entries (examined %d)" % [n, grid_examined])
	if linear_examined != n:
		_fail("linear scan control must examine all N")
	print("OK perf regression: grid examined %d < N=%d (linear %d); hits=%d" % [
		grid_examined, n, linear_examined, grid_hits.size()])


func _test_consumer_combat_via_layer() -> void:
	# Fixed fixture: SpatialQueryService + two combat nodes; melee must use layer.
	var svc = _SpatialQueryService.new()
	if svc.layer == null:
		svc.layer = _SpatialQueryLayer.new()
	root.add_child(svc)

	var e1 := _make_stub_combatant("c_near", 0.35)
	var e2 := _make_stub_combatant("c_far", 0.35)
	root.add_child(e1)
	root.add_child(e2)
	e1.global_position = Vector3(1, 0, 0)
	e2.global_position = Vector3(50, 0, 0)
	svc.register_combatant(e1, _SpatialQueryLayer.CAT_ENTITY)
	svc.register_combatant(e2, _SpatialQueryLayer.CAT_ENTITY)

	var hits: Array = svc.query_combat_candidates(Vector3.ZERO, 5.0)
	if hits.size() != 1:
		_fail("consumer combat candidates in r=5 should be 1 (got %d)" % hits.size())
	elif hits[0].payload != e1:
		_fail("consumer should return near entity")

	# CombatHitResolver path (production consumer)
	var melee: Array = _CombatHitResolver.query_melee(root, Vector3.ZERO, Vector3(1, 0, 0), 4.0)
	if melee.size() != 1 or melee[0] != e1:
		_fail("CombatHitResolver.query_melee must resolve via spatial layer (got %d)" % melee.size())
	else:
		print("OK consumer combat via Spatial Query Layer")

	_free_node(e1)
	_free_node(e2)
	_free_node(svc)


func _make_stub_combatant(stable: String, radius: float) -> Node3D:
	var n = load("res://scripts/spatial_combat_stub.gd").new()
	n.name = stable
	n.set_meta("combat_radius", radius)
	return n


func _free_node(n: Node) -> void:
	if n == null:
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.free()


## Production path: CrystalEnemySpawner order is add_child → global_position → setup.
## Index must not remain at origin after that sequence.
func _test_production_enemy_spawn_order() -> void:
	var svc = _SpatialQueryService.new()
	if svc.layer == null:
		svc.layer = _SpatialQueryLayer.new()
	root.add_child(svc)
	# Ensure group discovery resolves to this service (production uses group lookup).
	var discovered = get_first_node_in_group("spatial_query_service")
	if discovered != svc:
		_fail("spatial_query_service group did not resolve to test service")

	var enemy_script = load("res://entities/crystal_enemy.gd")
	var enemy = enemy_script.new()
	var spawn_pos := Vector3(42.5, 3.0, -17.25)
	# Exact production order from CrystalEnemySpawner._spawn_enemy / import_enemies
	root.add_child(enemy)
	enemy.global_position = spawn_pos
	# Minimal setup without full world (setup calls sync_spatial_index)
	if enemy.has_method("setup"):
		enemy.setup(&"crystal_mite", null, null, Vector2i.ZERO)
	if enemy.has_method("sync_spatial_index"):
		enemy.sync_spatial_index()

	# Origin must NOT report the enemy
	var at_origin: Array = svc.query_combat_candidates(Vector3.ZERO, 2.0)
	for h in at_origin:
		if h.get("payload") == enemy:
			_fail("production spawn order left enemy indexed at origin")
			_free_node(enemy)
			_free_node(svc)
			return
	# Spawn position must report the enemy
	var at_spawn: Array = svc.query_combat_candidates(spawn_pos, 2.0)
	var found := false
	for h in at_spawn:
		if h.get("payload") == enemy:
			found = true
			var p: Vector3 = h.pos
			if p.distance_to(spawn_pos) > 0.5:
				_fail("indexed pos far from spawn (got %s want %s)" % [str(p), str(spawn_pos)])
	if not found:
		_fail("query_combat_candidates missed enemy at production spawn position (count=%d layer=%d)" % [
			at_spawn.size(), svc.layer.count() if svc.layer else -1])
	else:
		print("OK production CrystalEnemy spawn order indexes final position")

	# import_enemies order mirror
	var enemy2 = enemy_script.new()
	var import_pos := Vector3(-8.0, 1.5, 33.0)
	root.add_child(enemy2)
	enemy2.global_position = import_pos
	enemy2.setup(&"crystal_mite", null, null, Vector2i.ZERO)
	if enemy2.has_method("sync_spatial_index"):
		enemy2.sync_spatial_index()
	var at_import: Array = svc.query_combat_candidates(import_pos, 1.5)
	var found2 := false
	for h in at_import:
		if h.get("payload") == enemy2:
			found2 = true
	if not found2:
		_fail("import path did not index enemy at import position")
	else:
		print("OK production import_enemies order indexes final position")

	_free_node(enemy)
	_free_node(enemy2)
	_free_node(svc)
