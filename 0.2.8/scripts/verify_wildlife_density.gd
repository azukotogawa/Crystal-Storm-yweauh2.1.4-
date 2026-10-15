extends SceneTree

const _Wildlife = preload("res://world/wildlife_density.gd")
const _World = preload("res://world/InfiniteNoiseWorld.gd")
const _Features = preload("res://world/feature_registry.gd")
const _Types = preload("res://helpers/world_feature_types.gd")
const _Budget = preload("res://systems/frame_budget_scheduler.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_check_budgets()
	_check_wake_and_frame()
	_check_plan(44021)
	_check_plan(918337)
	_check_place(44021)
	_check_flag_off()
	if _failed == 0:
		print("All wildlife density tests OK")
		quit(0)
	else:
		push_error("verify_wildlife_density: %d failure(s)" % _failed)
		quit(1)


func _check_budgets() -> void:
	for biome in ["plains", "steppe", "forest", "marsh", "highland"]:
		var row: Dictionary = _Wildlife.budget_for(biome)
		if row.is_empty():
			_fail("missing budget %s" % biome)
			return
		for key in ["deer", "boar", "rabbit", "bird"]:
			if not row.has(key):
				_fail("budget %s missing %s" % [biome, key])
				return
	if int(_Wildlife.budget_for("forest").get("deer", 0)) < 1 or int(_Wildlife.budget_for("forest").get("boar", 0)) < 1:
		_fail("forest needs deer and boar herds")
		return
	if int(_Wildlife.budget_for("plains").get("rabbit", 0)) < 1 or int(_Wildlife.budget_for("plains").get("bird", 0)) < 1:
		_fail("plains needs rabbits and birds")
		return
	if _Wildlife.canonical_biome("jungle") != "forest":
		_fail("jungle should use the forest budget")
		return
	if not _Wildlife.budget_for("ocean").is_empty():
		_fail("ocean should not take a wildlife budget")
		return
	print("OK biome budgets herd=%d radius=%d" % [_Wildlife.HERD_SIZE, _Wildlife.HERD_RADIUS])


func _check_wake_and_frame() -> void:
	if _Wildlife.wake_limit(0) != 0 or _Wildlife.wake_limit(1) != _Wildlife.HERD_SIZE:
		_fail("wake limit 0=%d 1=%d" % [_Wildlife.wake_limit(0), _Wildlife.wake_limit(1)])
		return
	var units := int(_Budget.DEFAULT_MAX_UNITS[_Budget.SYS_ENTITY_SPAWN])
	var us := int(_Budget.DEFAULT_BUDGET_US[_Budget.SYS_ENTITY_SPAWN])
	if units != 2 or us != 1000:
		_fail("entity_spawn frame budget units=%d us=%d" % [units, us])
		return
	if _Wildlife.wake_limit(1) > _Wildlife.HERD_SIZE:
		_fail("a chunk wake is larger than one herd")
		return
	print("OK frame budget entity_spawn units=%d us=%d wake=%d" % [units, us, _Wildlife.wake_limit(1)])


func _check_plan(seed_value: int) -> void:
	var world = _World.new(seed_value)
	var first: Array[Dictionary] = _Wildlife.plan(world, 160, 512)
	var again: Array[Dictionary] = _Wildlife.plan(world, 160, 512)
	if _signature(first) != _signature(again):
		_fail("plan seed %d is not deterministic" % seed_value)
		return
	if first.is_empty():
		_fail("plan seed %d placed nothing" % seed_value)
		return
	var herds: Dictionary = {}
	var rabbits := 0
	var birds := 0
	var deer_herds := 0
	var boar_herds := 0
	var by_biome: Dictionary = {}
	for spot in first:
		var kind := int(spot.get("animal_kind", -1))
		var biome := str(spot.get("biome", ""))
		var row: Dictionary = by_biome.get(biome, {"deer": {}, "boar": {}, "rabbit": 0, "bird": 0})
		if kind == _Types.AnimalKind.RABBIT:
			rabbits += 1
			row["rabbit"] = int(row.get("rabbit", 0)) + 1
		elif kind == _Types.AnimalKind.BIRD:
			birds += 1
			row["bird"] = int(row.get("bird", 0)) + 1
		elif kind == _Types.AnimalKind.DEER or kind == _Types.AnimalKind.BOAR:
			if not spot.has("herd_home"):
				_fail("herd animal missing home")
				return
			var home: Vector2i = spot.get("herd_home")
			var cell := Vector2i(int(spot.get("wx", 0)), int(spot.get("wz", 0)))
			if absi(cell.x - home.x) > _Wildlife.HERD_RADIUS or absi(cell.y - home.y) > _Wildlife.HERD_RADIUS:
				_fail("herd member %s left home %s" % [cell, home])
				return
			var bucket: Dictionary = herds.get(home, {"kind": kind, "n": 0})
			if int(bucket.get("kind", -1)) != kind:
				_fail("herd %s mixed kinds" % home)
				return
			bucket["n"] = int(bucket.get("n", 0)) + 1
			bucket["kind"] = kind
			herds[home] = bucket
			var key := "deer" if kind == _Types.AnimalKind.DEER else "boar"
			var homes: Dictionary = row.get(key, {})
			homes[home] = true
			row[key] = homes
		else:
			_fail("unknown animal kind %d" % kind)
			return
		by_biome[biome] = row
	for home in herds.keys():
		var bucket: Dictionary = herds[home]
		var n := int(bucket.get("n", 0))
		if n < _Wildlife.HERD_MIN or n > _Wildlife.HERD_SIZE:
			_fail("herd %s size %d" % [home, n])
			return
		if int(bucket.get("kind", -1)) == _Types.AnimalKind.DEER:
			deer_herds += 1
		else:
			boar_herds += 1
	if deer_herds < 1 or boar_herds < 1 or rabbits < 1 or birds < 1:
		_fail("seed %d deer_herds=%d boar_herds=%d rabbits=%d birds=%d" % [seed_value, deer_herds, boar_herds, rabbits, birds])
		return
	for biome in by_biome.keys():
		var cap: Dictionary = _Wildlife.budget_for(biome)
		var got: Dictionary = by_biome[biome]
		if cap.is_empty():
			_fail("placed wildlife in %s" % biome)
			return
		var deer_n := (got.get("deer", {}) as Dictionary).size()
		var boar_n := (got.get("boar", {}) as Dictionary).size()
		if deer_n > int(cap.get("deer", 0)) or boar_n > int(cap.get("boar", 0)):
			_fail("%s herds deer=%d boar=%d over budget" % [biome, deer_n, boar_n])
			return
		if int(got.get("rabbit", 0)) > int(cap.get("rabbit", 0)) or int(got.get("bird", 0)) > int(cap.get("bird", 0)):
			_fail("%s ambient over budget" % biome)
			return
	print("OK wildlife plan seed=%d spots=%d deer_herds=%d boar_herds=%d rabbits=%d birds=%d" % [seed_value, first.size(), deer_herds, boar_herds, rabbits, birds])


func _check_place(seed_value: int) -> void:
	_Features.reset()
	var world = _World.new(seed_value)
	var placed := _Wildlife.place(world, 160, 512)
	var spawns: Array = _Features.get_entity_spawns()
	if placed < 1 or spawns.size() != placed:
		_fail("place stored %d of %d" % [spawns.size(), placed])
		return
	var herds := 0
	for spawn in spawns:
		if int(spawn.get("kind", 0)) != _Types.FeatureKind.ANIMAL_SPAWN:
			_fail("spawn kind is not an animal")
			return
		if spawn.has("herd_home"):
			herds += 1
	if herds < _Wildlife.HERD_MIN:
		_fail("placed spawns kept %d herd members" % herds)
		return
	var sample: Dictionary = {}
	for spawn in spawns:
		if spawn.has("herd_home"):
			sample = spawn
			break
	var pos: Vector2i = sample.get("world_pos", Vector2i.ZERO)
	var coord := Vector2i(floori(float(pos.x) / 16.0), floori(float(pos.y) / 16.0))
	var in_chunk: Array = _Features.get_spawns_in_chunk(coord, 16)
	var found := false
	for spawn in in_chunk:
		if spawn.has("herd_home"):
			found = true
	if not found:
		_fail("chunk query dropped herd_home")
		return
	_Features.reset()
	print("OK wildlife place seed=%d spawns=%d herd_members=%d" % [seed_value, placed, herds])


func _check_flag_off() -> void:
	var was: bool = _Wildlife.ENABLED
	_Wildlife.ENABLED = false
	_Features.reset()
	var world = _World.new(44021)
	var placed := _Wildlife.place(world, 160, 512)
	_Wildlife.ENABLED = was
	_Features.reset()
	if placed != 0 or not _Features.get_entity_spawns().is_empty():
		_fail("flag off still placed %d" % placed)
		return
	print("OK wildlife flag off places nothing")


func _signature(spots: Array[Dictionary]) -> String:
	var parts: PackedStringArray = []
	for spot in spots:
		var home: String = "-"
		if spot.has("herd_home"):
			var cell: Vector2i = spot.get("herd_home")
			home = "%d,%d" % [cell.x, cell.y]
		parts.append("%d,%d,%d,%s" % [int(spot.get("wx", 0)), int(spot.get("wz", 0)), int(spot.get("animal_kind", -1)), home])
	return "|".join(parts)
