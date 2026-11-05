extends SceneTree

const _DungeonGraph = preload("res://world/dungeon_graph.gd")
const _EmptyPrefab = preload("res://world/prefabs/empty_room_prefab.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldState = preload("res://world/world_state.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _ChunkData = preload("res://chunks/chunk_data.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")


func _init() -> void:
	var bad := 0
	_WorldState.ensure_active()
	_TerrainEdits.reset()
	_FeatureRegistry.reset()

	# Prefab constants
	if _EmptyPrefab.ID != "empty_room" or _EmptyPrefab.DIG_LAYERS != 3:
		bad += 1
		print("FAIL empty prefab id/dig")
	else:
		print("OK empty prefab id=%s dig=%d size=%s" % [_EmptyPrefab.ID, _EmptyPrefab.DIG_LAYERS, str(_EmptyPrefab.size_cells())])
	if _EmptyPrefab.WALL_TILE != _Voxels.STONE2 or _EmptyPrefab.FLOOR_TILE != _Voxels.CAVE_STONE:
		bad += 1
		print("FAIL prefab tiles wall=%d floor=%d" % [_EmptyPrefab.WALL_TILE, _EmptyPrefab.FLOOR_TILE])
	else:
		print("OK prefab tiles STONE2/CAVE_STONE")

	var interior := _EmptyPrefab.interior_cells(Vector2i(10, 20))
	var walls := _EmptyPrefab.wall_cells(Vector2i(10, 20))
	if interior.size() != 25 or walls.size() != 24:
		bad += 1
		print("FAIL prefab cell counts interior=%d walls=%d" % [interior.size(), walls.size()])
	else:
		print("OK prefab footprint interior=25 walls=24")

	# Deterministic plan identity
	var seed_value := 424242
	var a: Dictionary = _DungeonGraph.plan_for_seed(seed_value)
	var b: Dictionary = _DungeonGraph.plan_for_seed(seed_value)
	if a.is_empty() or str(a) != str(b):
		bad += 1
		print("FAIL plan identity for seed %d" % seed_value)
	else:
		print("OK plan identity seed=%d entrance=%s room=%s" % [
			seed_value,
			str(a.get("entrance")),
			str((a.get("rooms", [{}]) as Array)[0].get("center")),
		])
	if str(a.get("prefab", {}).get("id", "")) != "empty_room":
		bad += 1
		print("FAIL plan missing empty_room prefab")
	else:
		print("OK plan hooks empty_room prefab")
	if not bool(a.has("entrance")) or not a.has("digs") or (a.get("rooms", []) as Array).is_empty():
		bad += 1
		print("FAIL plan missing entrance/digs/rooms")
	else:
		print("OK plan has surface entrance + digs + rooms")

	var other: Dictionary = _DungeonGraph.plan_for_seed(seed_value + 1)
	if str(other.get("entrance")) == str(a.get("entrance")) and str(other.get("dir")) == str(a.get("dir")):
		# Same entrance for adjacent seeds is unlikely but possible; require dig map differ or room differ
		if str(other) == str(a):
			bad += 1
			print("FAIL distinct seeds produced identical plans")
		else:
			print("OK distinct seed differs")
	else:
		print("OK distinct seed entrance/dir differs")

	# Install → WorldState height_delta + feature + tiles
	_TerrainEdits.reset()
	_FeatureRegistry.reset()
	var placed := _DungeonGraph.install(a)
	if placed != 1:
		bad += 1
		print("FAIL install returned %d" % placed)
	else:
		print("OK install placed=1")

	var entrance: Vector2i = a.get("entrance")
	var feat: Dictionary = _FeatureRegistry.get_feature(entrance.x, entrance.y)
	if feat.is_empty() or str(feat.get("poi_kind", "")) != "dungeon_entrance":
		bad += 1
		print("FAIL entrance feature poi_kind=%s" % str(feat.get("poi_kind", "")))
	else:
		print("OK entrance feature dungeon_entrance surface=%s prefab=%s" % [
			str(feat.get("surface_entrance", false)),
			str(feat.get("prefab", "")),
		])
	if not bool(feat.get("surface_entrance", false)):
		bad += 1
		print("FAIL surface_entrance flag missing")

	var layer: float = _WorldSettings.get_active().layer_height()
	var digs: Dictionary = a.get("digs", {})
	var checked := 0
	var dig_bad := 0
	for key_v in digs.keys():
		var cell: Vector2i = key_v
		var want_layers: int = int(digs[key_v])
		var got_delta: float = _TerrainEdits.get_height_delta(cell.x, cell.y)
		var want_delta: float = -float(want_layers) * layer
		if not is_equal_approx(got_delta, want_delta):
			dig_bad += 1
			if dig_bad <= 3:
				print("FAIL dig cell=%s want=%s got=%s" % [str(cell), want_delta, got_delta])
		checked += 1
	if dig_bad > 0:
		bad += 1
		print("FAIL dig mismatches=%d / %d" % [dig_bad, checked])
	else:
		print("OK digs match plan cells=%d entrance_delta=%s" % [
			checked,
			_TerrainEdits.get_height_delta(entrance.x, entrance.y),
		])

	var room: Dictionary = (a.get("rooms", [{}]) as Array)[0]
	var room_center: Vector2i = room.get("center", Vector2i.ZERO)
	var floor_tile := _FeatureRegistry.get_tile_override(room_center.x, room_center.y)
	if floor_tile != _Voxels.CAVE_STONE:
		bad += 1
		print("FAIL room floor tile=%d" % floor_tile)
	else:
		print("OK room floor CAVE_STONE at %s" % str(room_center))
	var wall_sample: Vector2i = room_center + Vector2i(_EmptyPrefab.HALF_W, 0)
	# door may occupy +dir * HALF_W; pick a side wall
	wall_sample = room_center + Vector2i(0, _EmptyPrefab.HALF_D)
	var wall_tile := _FeatureRegistry.get_tile_override(wall_sample.x, wall_sample.y)
	if wall_tile != _Voxels.STONE2:
		bad += 1
		print("FAIL room wall tile=%d at %s" % [wall_tile, str(wall_sample)])
	else:
		print("OK room wall STONE2 at %s" % str(wall_sample))

	# Bake/stream hook: chunk_data.capture_worker_snapshot sees height_delta + feature tile
	var world_scr = load("res://world/InfiniteNoiseWorld.gd")
	var world = world_scr.new()
	world.world_seed = seed_value
	var chunk_coord := Vector2i(
		int(floor(float(entrance.x) / float(_ChunkData.SIZE))),
		int(floor(float(entrance.y) / float(_ChunkData.SIZE)))
	)
	var data := _ChunkData.new(chunk_coord, world)
	data.capture_worker_snapshot()
	var lx: int = entrance.x - chunk_coord.x * _ChunkData.SIZE
	var lz: int = entrance.y - chunk_coord.y * _ChunkData.SIZE
	if lx < 0 or lz < 0 or lx >= _ChunkData.SIZE or lz >= _ChunkData.SIZE:
		bad += 1
		print("FAIL entrance local out of chunk lx=%d lz=%d" % [lx, lz])
	else:
		var worker_h: float = float(data._worker_height_delta[lx][lz])
		var expect_h: float = _TerrainEdits.get_height_delta(entrance.x, entrance.y)
		if not is_equal_approx(worker_h, expect_h):
			bad += 1
			print("FAIL worker height_delta lx=%d lz=%d want=%s got=%s" % [lx, lz, expect_h, worker_h])
		else:
			print("OK bake/stream worker height_delta=%s at chunk=%s local=(%d,%d)" % [
				worker_h, str(chunk_coord), lx, lz,
			])
		var worker_tile: int = int(data._worker_feature_tile[lx][lz])
		if worker_tile != _Voxels.STONE2:
			bad += 1
			print("FAIL worker feature_tile=%d" % worker_tile)
		else:
			print("OK bake/stream worker feature_tile=STONE2")

	# Idempotent skip when feature already present
	var again := _DungeonGraph.install(a)
	if again != 0:
		bad += 1
		print("FAIL reinstall should skip, got %d" % again)
	else:
		print("OK reinstall skipped")

	# Source contract: world_features must call DungeonGraph
	var wf_src := (load("res://world/world_features.gd") as GDScript).source_code
	if "_DungeonGraph" not in wf_src or "DungeonGraph.place" not in wf_src and "._DungeonGraph.place" not in wf_src:
		# accept either _DungeonGraph.place(world) form
		if "_DungeonGraph.place" not in wf_src:
			bad += 1
			print("FAIL world_features missing DungeonGraph.place hook")
		else:
			print("OK world_features hooks DungeonGraph.place")
	else:
		print("OK world_features hooks DungeonGraph.place")

	if bad > 0:
		print("FAIL verify_dungeon_graph bad=%d" % bad)
		quit(1)
	print("All dungeon graph tests OK bad=0")
	quit(0)