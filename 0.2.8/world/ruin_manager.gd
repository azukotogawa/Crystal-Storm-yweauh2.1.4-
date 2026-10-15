class_name RuinManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")
const _RelicRegistry = preload("res://relics/relic_registry.gd")

const WORLD_DENSITY := true

const LORE_LINES := [
	"Treasure hunters broke this seal and the crystal woke.",
	"A hunter's note: we opened the chest. The crystal followed.",
	"Hunters packed these relics. One crystal was already loose.",
	"Treasure hunters opened the chest. The crystal escaped with them.",
	"Scratched by a hunter: leave the crystal shut.",
	"The last hunter wrote: the crystal is out. Take what remains.",
]

@export var ruin_count: int = 6
@export var min_distance_from_origin: float = 48.0
@export var max_distance_from_origin: float = 280.0
@export var min_separation: float = 100.0

signal ruin_registered(ruin: Dictionary)

var world: InfiniteNoiseWorld
var _rng: RandomNumberGenerator
var ruins: Array[Dictionary] = []


func _enter_tree() -> void:
	add_to_group("ruin_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	_rng = RandomNumberGenerator.new()


func generate() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_rng.seed = world.world_seed + 55077
	ruins.clear()
	_place_ruins()


func get_ruin_positions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ruin in ruins:
		out.append(ruin.get("center", Vector2i.ZERO))
	return out


func _place_ruins() -> void:
	var placed: Array[Vector2i] = []
	for _attempt in ruin_count * 50:
		if placed.size() >= ruin_count:
			break
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(min_distance_from_origin, max_distance_from_origin)
		var wx := int(round(cos(angle) * dist))
		var wz := int(round(sin(angle) * dist))
		if not _WorldBorder.is_playable(float(wx), float(wz)):
			continue
		if not _is_valid_ruin_site(wx, wz):
			continue
		var too_close := false
		for p in placed:
			if Vector2(wx, wz).distance_to(Vector2(p)) < min_separation:
				too_close = true
				break
		if too_close:
			continue

		var center := Vector2i(wx, wz)
		var ruin_data := _site_record(placed.size(), center)
		ruins.append(ruin_data)
		placed.append(center)
		install_site(ruin_data, WORLD_DENSITY)
		ruin_registered.emit(ruin_data)


func _is_valid_ruin_site(wx: int, wz: int) -> bool:
	if world == null:
		return false
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	if biome.get("name", "") in ["ocean", "border_mountain", "marsh"]:
		return false
	return true


func _site_record(site_index: int, center: Vector2i) -> Dictionary:
	if WORLD_DENSITY:
		return treasure_site(site_index, center)
	return {
		"center": center,
		"name": "Ruin %d" % (site_index + 1),
		"radius": 5,
	}


static func treasure_site(site_index: int, center: Vector2i) -> Dictionary:
	var pool: Array[StringName] = _RelicRegistry.ruin_loot_pool()
	var relic: StringName = &""
	if not pool.is_empty():
		relic = pool[posmod(site_index, pool.size())]
	var h: int = absi(hash(center) + site_index * 17)
	var lore: String = LORE_LINES[posmod(site_index, LORE_LINES.size())]
	return {
		"center": center,
		"name": "Treasure Site %d" % (site_index + 1),
		"radius": 5,
		"treasure_site": true,
		"lore": lore,
		"chest": {
			"relics": [relic],
			"resources": {
				"stone": 4 + (h % 5),
				"herb": 1 + (int(h / 5) % 3),
				"wood": 2 + (int(h / 11) % 4),
			},
		},
	}


static func feature_payload(site: Dictionary, density_on: bool) -> Dictionary:
	var center: Vector2i = site.get("center", Vector2i.ZERO)
	if not density_on:
		return {
			"center": center,
			"name": str(site.get("name", "Forgotten Ruin")),
			"is_spawn_point": true,
		}
	var chest: Dictionary = site.get("chest", {})
	return {
		"center": center,
		"name": str(site.get("name", "Treasure Site")),
		"is_spawn_point": false,
		"treasure_site": true,
		"lore": str(site.get("lore", "")),
		"chest": chest.duplicate(true),
	}


func install_site(site: Dictionary, density_on: bool = WORLD_DENSITY) -> void:
	var center: Vector2i = site.get("center", Vector2i.ZERO)
	_stamp_payload(center, feature_payload(site, density_on))


func _stamp_payload(center: Vector2i, payload: Dictionary) -> void:
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			if Vector2(dx, dz).length() > 5.0:
				continue
			var wx := center.x + dx
			var wz := center.y + dz
			var cell: Dictionary = payload.duplicate(true)
			if dx != 0 or dz != 0:
				cell.erase("chest")
			_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.RUIN, cell)
			if absi(dx) <= 1 and absi(dz) <= 1:
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.STONE2, true)