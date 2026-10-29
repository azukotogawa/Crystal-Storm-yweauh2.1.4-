class_name WildlifeDensity
extends RefCounted

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _Voxels = preload("res://helpers/voxel_types.gd")

static var ENABLED: bool = true

const HERD_SIZE := 4
const HERD_MIN := 3
const HERD_RADIUS := 2
const SEED_SALT := 66003
const NEAR_HALF := 128

const KIND_KEYS: Array[String] = ["deer", "boar", "goat", "rabbit", "bird", "fox", "duck"]

const BIOME_BUDGET := {
	"plains": {"deer": 2, "boar": 0, "goat": 0, "rabbit": 10, "bird": 8, "fox": 2, "duck": 2},
	"steppe": {"deer": 0, "boar": 2, "goat": 1, "rabbit": 9, "bird": 7, "fox": 0, "duck": 0},
	"forest": {"deer": 4, "boar": 3, "goat": 0, "rabbit": 5, "bird": 5, "fox": 3, "duck": 0},
	"marsh": {"deer": 0, "boar": 1, "goat": 0, "rabbit": 4, "bird": 5, "fox": 0, "duck": 6},
	"highland": {"deer": 1, "boar": 0, "goat": 2, "rabbit": 3, "bird": 6, "fox": 0, "duck": 0},
}

const _OFFSETS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(2, 0),
	Vector2i(-2, 0),
	Vector2i(0, 2),
	Vector2i(0, -2),
	Vector2i(2, 1),
	Vector2i(-1, -2),
	Vector2i(1, 2),
]


static func canonical_biome(name: String) -> String:
	match name:
		"dense forest", "pine forest", "jungle":
			return "forest"
		"mountain", "border_mountain":
			return "highland"
		_:
			return name


static func budget_for(biome_name: String) -> Dictionary:
	var key := canonical_biome(biome_name)
	if not BIOME_BUDGET.has(key):
		return {}
	return (BIOME_BUDGET[key] as Dictionary).duplicate()


static func wake_limit(per_chunk: int) -> int:
	if per_chunk <= 0:
		return 0
	return maxi(per_chunk, HERD_SIZE)


static func plan(world, attempts: int, half: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if world == null:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = int(world.world_seed) + SEED_SALT
	var counts: Dictionary = {}
	var occupied: Dictionary = {}
	var loops := maxi(attempts, 220)
	var span := maxi(half, 64)
	for i in loops:
		if _budgets_met(counts):
			break
		var band := span
		if i % 3 == 0:
			band = mini(span, NEAR_HALF)
		var wx := rng.randi_range(-band, band)
		var wz := rng.randi_range(-band, band)
		if not _cell_open(world, wx, wz, occupied):
			continue
		var biome := canonical_biome(str(world.get_biome(float(wx), 0.0, float(wz)).get("name", "")))
		if budget_for(biome).is_empty():
			continue
		var herd_kind := _next_kind(biome, counts, rng, true)
		if herd_kind >= 0:
			var members := _cluster(world, wx, wz, herd_kind, biome, occupied)
			if members.size() >= HERD_MIN:
				for member in members:
					out.append(member)
					occupied[Vector2i(int(member.get("wx", 0)), int(member.get("wz", 0)))] = true
				_bump(counts, biome, _kind_key(herd_kind))
				continue
		var ambient := _next_kind(biome, counts, rng, false)
		if ambient < 0:
			continue
		if not _cell_open(world, wx, wz, occupied):
			continue
		out.append({
			"wx": wx,
			"wz": wz,
			"animal_kind": ambient,
			"biome": biome,
		})
		occupied[Vector2i(wx, wz)] = true
		_bump(counts, biome, _kind_key(ambient))
	return out


static func place(world, attempts: int, half: int) -> int:
	if not ENABLED or world == null:
		return 0
	var planned := plan(world, attempts, half)
	for spot in planned:
		var wx := int(spot.get("wx", 0))
		var wz := int(spot.get("wz", 0))
		_FeatureRegistry.register_entity_spawn(
			wx,
			wz,
			_WorldFeatureTypes.FeatureKind.ANIMAL_SPAWN,
			int(spot.get("animal_kind", _WorldFeatureTypes.AnimalKind.RABBIT))
		)
		if not spot.has("herd_home"):
			continue
		var spawns: Array = _FeatureRegistry.get_entity_spawns()
		if spawns.is_empty():
			continue
		spawns[spawns.size() - 1]["herd_home"] = spot.get("herd_home", Vector2i(wx, wz))
	return planned.size()


static func _budgets_met(counts: Dictionary) -> bool:
	for biome in BIOME_BUDGET.keys():
		var row: Dictionary = BIOME_BUDGET[biome]
		var got: Dictionary = counts.get(biome, {})
		for key in KIND_KEYS:
			if int(got.get(key, 0)) < int(row.get(key, 0)):
				return false
	return true


static func _bump(counts: Dictionary, biome: String, key: String) -> void:
	if key.is_empty():
		return
	var row: Dictionary = counts.get(biome, {})
	row[key] = int(row.get(key, 0)) + 1
	counts[biome] = row


static func _kind_key(animal_kind: int) -> String:
	match animal_kind:
		_WorldFeatureTypes.AnimalKind.DEER:
			return "deer"
		_WorldFeatureTypes.AnimalKind.BOAR:
			return "boar"
		_WorldFeatureTypes.AnimalKind.BIRD:
			return "bird"
		_WorldFeatureTypes.AnimalKind.RABBIT:
			return "rabbit"
		_WorldFeatureTypes.AnimalKind.FOX:
			return "fox"
		_WorldFeatureTypes.AnimalKind.GOAT:
			return "goat"
		_WorldFeatureTypes.AnimalKind.DUCK:
			return "duck"
		_:
			return ""


static func _next_kind(biome: String, counts: Dictionary, rng: RandomNumberGenerator, herds: bool) -> int:
	var row := budget_for(biome)
	if row.is_empty():
		return -1
	var got: Dictionary = counts.get(biome, {})
	var options: Array[int] = []
	if herds:
		if int(got.get("deer", 0)) < int(row.get("deer", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.DEER)
		if int(got.get("boar", 0)) < int(row.get("boar", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.BOAR)
		if int(got.get("goat", 0)) < int(row.get("goat", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.GOAT)
	else:
		if int(got.get("rabbit", 0)) < int(row.get("rabbit", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.RABBIT)
		if int(got.get("bird", 0)) < int(row.get("bird", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.BIRD)
		if int(got.get("fox", 0)) < int(row.get("fox", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.FOX)
		if int(got.get("duck", 0)) < int(row.get("duck", 0)):
			options.append(_WorldFeatureTypes.AnimalKind.DUCK)
	if options.is_empty():
		return -1
	return options[rng.randi() % options.size()]


static func _cluster(
	world,
	wx: int,
	wz: int,
	animal_kind: int,
	biome: String,
	occupied: Dictionary
) -> Array[Dictionary]:
	var home := Vector2i(wx, wz)
	var members: Array[Dictionary] = []
	for offset in _OFFSETS:
		if members.size() >= HERD_SIZE:
			break
		var cell := home + offset
		if absi(offset.x) > HERD_RADIUS or absi(offset.y) > HERD_RADIUS:
			continue
		if not _cell_open(world, cell.x, cell.y, occupied):
			continue
		members.append({
			"wx": cell.x,
			"wz": cell.y,
			"animal_kind": animal_kind,
			"biome": biome,
			"herd_home": home,
		})
	if members.size() < HERD_MIN:
		return []
	return members


static func _cell_open(world, wx: int, wz: int, occupied: Dictionary) -> bool:
	var key := Vector2i(wx, wz)
	if occupied.has(key):
		return false
	var tile := int(world.get_tile_type(float(wx), float(wz)))
	if tile == _Voxels.RIVER or tile == _Voxels.WATER:
		return false
	var feat: Dictionary = _FeatureRegistry.get_feature(wx, wz)
	if feat.has("kind") and int(feat.get("kind", 0)) == _WorldFeatureTypes.FeatureKind.TOWN:
		return false
	return true
