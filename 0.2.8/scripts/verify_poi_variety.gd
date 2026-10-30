extends SceneTree

const _Variety = preload("res://world/poi_variety.gd")
const _Relics = preload("res://relics/relic_registry.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _WorldState = preload("res://world/world_state.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _Blueprints = preload("res://helpers/structure_blueprints.gd")

const SEEDS: Array[int] = [44021, 918337, 12349, 7]

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_kinds()
	for seed_value in SEEDS:
		_check_seed(seed_value)
	_check_install(44021)
	if _failed == 0:
		print("POI VARIETY OK")
		quit(0)
	else:
		push_error("verify_poi_variety: %d failure(s)" % _failed)
		quit(1)


func _check_kinds() -> void:
	if _Variety.KINDS.size() < 2:
		_fail("need at least two poi kinds")
		return
	if "cave_mouth" not in _Variety.KINDS or "ruined_watchtower" not in _Variety.KINDS:
		_fail("missing cave mouth or ruined watchtower")
		return
	if _Variety.MIN_SEPARATION < 100.0:
		_fail("separation is under 100")
		return
	var pool: Array[StringName] = _Relics.cave_loot_pool()
	if pool.is_empty():
		_fail("cave loot pool is empty")
		return
	var ruin: Array[StringName] = _Relics.ruin_loot_pool()
	if pool == ruin:
		_fail("cave loot pool must sit beside the ruin pool, not copy it")
		return
	if not _Blueprints.LARGE_STRUCTURES:
		_fail("structure blueprints are off")
		return
	var cave: Array[Dictionary] = _Variety.layout("cave_mouth")
	if not _covers_ground(cave, _Blueprints.STAIRS, "stone_wall"):
		_fail("cave mouth did not reuse the stairs blueprint")
		return
	var tower: Array[Dictionary] = _Variety.layout("ruined_watchtower")
	if not _covers_ground(tower, _Blueprints.SMALL_TOWER, "ruin_pillar"):
		_fail("watchtower did not reuse the small tower blueprint")
		return
	print("OK poi variety kinds separation=%.0f cave_pool=%d" % [_Variety.MIN_SEPARATION, pool.size()])


func _check_seed(seed_value: int) -> void:
	var world = _World.new(seed_value)
	var t0 := Time.get_ticks_msec()
	var first: Array[Dictionary] = _Variety.plan(world, false)
	var again: Array[Dictionary] = _Variety.plan(world, false)
	var ms := Time.get_ticks_msec() - t0
	if first.is_empty():
		_fail("seed %d planned nothing" % seed_value)
		world.free()
		return
	if _signature(first) != _signature(again):
		_fail("seed %d is not deterministic" % seed_value)
		world.free()
		return
	var counts := {}
	for i in first.size():
		var spot: Dictionary = first[i]
		var kind := str(spot.get("poi_kind", ""))
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		if not _Variety.owns(kind):
			_fail("seed %d unknown kind %s" % [seed_value, kind])
			world.free()
			return
		counts[kind] = int(counts.get(kind, 0)) + 1
		if not _Variety.reachable(world, center):
			_fail("seed %d %s at %s is not reachable from spawn %s" % [seed_value, kind, center, _Variety.spawn_for(seed_value)])
			world.free()
			return
		var dist := Vector2(center).distance_to(Vector2(_Variety.spawn_for(seed_value)))
		if dist < _Variety.MIN_FROM_SPAWN or dist > _Variety.MAX_FROM_SPAWN + 1.0:
			_fail("seed %d %s at %s dist %.1f outside the spawn ring" % [seed_value, kind, center, dist])
			world.free()
			return
		for j in i:
			var other: Vector2i = first[j].get("center", Vector2i.ZERO)
			var gap := Vector2(center).distance_to(Vector2(other))
			if gap < _Variety.MIN_SEPARATION:
				_fail("seed %d spacing %.1f under %.0f (%s to %s)" % [seed_value, gap, _Variety.MIN_SEPARATION, center, other])
				world.free()
				return
	for kind in _Variety.KINDS:
		if int(counts.get(kind, 0)) < 1:
			_fail("seed %d never placed %s (counts %s)" % [seed_value, kind, str(counts)])
			world.free()
			return
		if int(counts.get(kind, 0)) != _Variety.PER_KIND:
			_fail("seed %d %s count %d wanted %d" % [seed_value, kind, int(counts.get(kind, 0)), _Variety.PER_KIND])
			world.free()
			return
	print("OK poi variety seed=%d count=%d walk_ms=%d spawn=%s" % [seed_value, first.size(), ms, str(_Variety.spawn_for(seed_value))])
	world.free()


func _check_install(seed_value: int) -> void:
	_WorldState.replace_active()
	_FeatureRegistry.reset()
	var world = _World.new(seed_value)
	var spots: Array[Dictionary] = _Variety.plan(world, false)
	var placed := _Variety.install(spots)
	if placed != spots.size():
		_fail("install placed %d of %d" % [placed, spots.size()])
		world.free()
		_WorldState.replace_active()
		return
	var pool: Array[StringName] = _Relics.cave_loot_pool()
	var saw_chest := false
	var saw_sentry := false
	for spot in spots:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		var kind := str(spot.get("poi_kind", ""))
		var feat: Dictionary = _FeatureRegistry.get_feature(center.x, center.y)
		if int(feat.get("kind", -1)) != _WorldFeatureTypes.FeatureKind.POI:
			_fail("installed %s is not a poi feature" % kind)
			world.free()
			_WorldState.replace_active()
			return
		if kind == "cave_mouth":
			if str(feat.get("loot_entity", "")) != _Variety.LOOT_ID:
				_fail("cave mouth is missing the loot entity")
				world.free()
				_WorldState.replace_active()
				return
			var chest: Dictionary = feat.get("chest", {})
			var relics: Array = chest.get("relics", [])
			if relics.is_empty() or not (StringName(str(relics[0])) in pool):
				_fail("cave chest relic %s is outside the cave pool" % str(relics))
				world.free()
				_WorldState.replace_active()
				return
			var resources: Dictionary = chest.get("resources", {})
			if int(resources.get("stone", 0)) < 1:
				_fail("cave chest has no stone")
				world.free()
				_WorldState.replace_active()
				return
			var node := _Variety.build_visual(kind)
			if node.get_node_or_null("LootChest") == null or str(node.get_node("LootChest").get_meta("loot_entity")) != _Variety.LOOT_ID:
				_fail("cave visual is missing LootChest")
				node.free()
				world.free()
				_WorldState.replace_active()
				return
			node.free()
			saw_chest = true
		else:
			if str(feat.get("encounter_entity", "")) != _Variety.ENCOUNTER_ID:
				_fail("watchtower is missing the encounter entity")
				world.free()
				_WorldState.replace_active()
				return
			var node := _Variety.build_visual(kind)
			if node.get_node_or_null("EncounterMarker") == null:
				_fail("watchtower visual is missing EncounterMarker")
				node.free()
				world.free()
				_WorldState.replace_active()
				return
			node.free()
			saw_sentry = true
	var spawned := false
	for row in _FeatureRegistry.get_entity_spawns():
		if str(row.get("encounter_entity", "")) == _Variety.ENCOUNTER_ID:
			spawned = true
			if int(row.get("kind", -1)) != _WorldFeatureTypes.FeatureKind.ENCOUNTER:
				_fail("sentry spawn is not an encounter feature")
				world.free()
				_WorldState.replace_active()
				return
	if not saw_chest or not saw_sentry or not spawned:
		_fail("loot or sentry missing after install chest=%s sentry=%s spawn=%s" % [saw_chest, saw_sentry, spawned])
		world.free()
		_WorldState.replace_active()
		return
	if _Variety.install(spots) != 0:
		_fail("second install wrote over occupied cells")
		world.free()
		_WorldState.replace_active()
		return
	world.free()
	_WorldState.replace_active()
	print("OK poi variety install loot=%s encounter=%s" % [_Variety.LOOT_ID, _Variety.ENCOUNTER_ID])


func _covers_ground(pieces: Array[Dictionary], blueprint_id: StringName, structure_id: String) -> bool:
	var bp: Dictionary = _Blueprints.get_blueprint(blueprint_id)
	var need: Dictionary = {}
	for cell_v in bp.get("cells", []):
		var cell: Dictionary = cell_v
		if int(cell.get("y", 0)) != 0:
			continue
		need[Vector2i(int(cell.get("x", 0)), int(cell.get("z", 0)))] = true
	if need.is_empty():
		return false
	for piece in pieces:
		var off: Vector2i = piece.get("offset", Vector2i.ZERO)
		if not bool(need.get(off, false)):
			continue
		if str(piece.get("structure", "")) != structure_id:
			continue
		need.erase(off)
	return need.is_empty()


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for spot in spots:
		var center: Vector2i = spot.get("center", Vector2i.ZERO)
		parts.append("%d,%d:%s" % [center.x, center.y, str(spot.get("poi_kind", ""))])
	return "|".join(parts)
