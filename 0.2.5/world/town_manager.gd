class_name TownManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var town_count: int = 4
@export var min_town_radius: int = 10
@export var max_town_radius: int = 16
@export var min_separation: float = 220.0

signal town_registered(town: Dictionary)

var world: InfiniteNoiseWorld
var _rng: RandomNumberGenerator
var _ready_done := false


func _enter_tree() -> void:
	add_to_group("town_manager")


func _ready() -> void:
	world = get_tree().get_first_node_in_group("world")
	_rng = RandomNumberGenerator.new()


func generate() -> void:
	if world == null:
		world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_rng.seed = world.world_seed + 44001
	_place_towns()
	_ready_done = true


func _place_towns() -> void:
	var placed: Array[Vector2i] = []
	for _attempt in town_count * 40:
		if placed.size() >= town_count:
			break
		var half := float(_WorldBorder.PLAYABLE_HALF_X) * 0.72
		var wx := int(_rng.randf_range(-half, half))
		var wz := int(_rng.randf_range(-half, half))
		if not _WorldBorder.is_playable(float(wx), float(wz)):
			continue
		if not _is_valid_town_site(wx, wz):
			continue
		var too_close := false
		for p in placed:
			if Vector2(wx, wz).distance_to(Vector2(p)) < min_separation:
				too_close = true
				break
		if too_close:
			continue

		var radius := _rng.randi_range(min_town_radius, max_town_radius)
		var town_name := "Settlement %d" % (placed.size() + 1)
		_FeatureRegistry.register_town(Vector2i(wx, wz), radius, town_name)
		_stamp_town_ground(wx, wz, radius)
		placed.append(Vector2i(wx, wz))
		var town_data: Dictionary = _FeatureRegistry.get_towns().back()
		town_registered.emit(town_data)


func _is_valid_town_site(wx: int, wz: int) -> bool:
	if world == null:
		return false
	var tile := world.get_tile_type(float(wx), float(wz))
	if tile == VoxelTypes.RIVER or tile == VoxelTypes.WATER:
		return false
	if tile == VoxelTypes.STONE or tile == VoxelTypes.STONE2:
		return false
	var biome: Dictionary = world.get_biome(float(wx), 0.0, float(wz))
	var name: String = biome.get("name", "")
	if name == "marsh" or name == "ocean" or name == "border_mountain":
		return false
	var surf := world.get_surface_height(float(wx), float(wz))
	if surf < 36.0 or surf > 95.0:
		return false
	for ox in [-2, 0, 2]:
		for oz in [-2, 0, 2]:
			var nh := world.get_surface_height(float(wx + ox), float(wz + oz))
			if absf(nh - surf) > 2.5:
				return false
	return true


func _stamp_town_ground(cx: int, cz: int, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var dist := Vector2(dx, dz).length()
			if dist > float(radius):
				continue
			var wx := cx + dx
			var wz := cz + dz
			if dist < float(radius) * 0.35:
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.TOWN_PATH)
			elif _rng.randf() < 0.12:
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.FARMLAND)