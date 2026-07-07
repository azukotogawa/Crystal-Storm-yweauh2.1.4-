class_name TownManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

@export var small_town_count: int = 2
@export var large_port_count: int = 1
@export var small_town_radius_min: int = 10
@export var small_town_radius_max: int = 14
@export var port_radius_min: int = 18
@export var port_radius_max: int = 24
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


func apply_world_config(cfg) -> void:
	if cfg == null:
		return
	small_town_count = int(cfg.small_town_count)
	large_port_count = int(cfg.large_port_count)
	small_town_radius_min = int(cfg.small_town_radius_min)
	small_town_radius_max = int(cfg.small_town_radius_max)
	port_radius_min = int(cfg.port_radius_min)
	port_radius_max = int(cfg.port_radius_max)
	min_separation = float(cfg.town_min_separation)


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
	var plan: Array = []
	for _i in small_town_count:
		plan.append({"kind": "town", "name_prefix": "Settlement"})
	for _i in large_port_count:
		plan.append({"kind": "port", "name_prefix": "Port"})

	for entry in plan:
		var pos := _find_town_site(placed)
		if pos == Vector2i.ZERO:
			continue
		var radius: int
		var town_name: String
		if entry.kind == "port":
			radius = _rng.randi_range(port_radius_min, port_radius_max)
			town_name = "%s %s" % [entry.name_prefix, String.chr(65 + placed.size())]
		else:
			radius = _rng.randi_range(small_town_radius_min, small_town_radius_max)
			town_name = "%s %d" % [entry.name_prefix, placed.size() + 1]
		_FeatureRegistry.register_town(pos, radius, town_name)
		_stamp_town_ground(pos.x, pos.y, radius, entry.kind == "port")
		placed.append(pos)
		town_registered.emit(_FeatureRegistry.get_towns().back())


func _find_town_site(placed: Array[Vector2i]) -> Vector2i:
	for _attempt in 120:
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
		return Vector2i(wx, wz)
	return Vector2i.ZERO


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
	if name in ["marsh", "ocean", "border_mountain", "highland"]:
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


func _stamp_town_ground(cx: int, cz: int, radius: int, is_port: bool) -> void:
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var dist := Vector2(dx, dz).length()
			if dist > float(radius):
				continue
			var wx := cx + dx
			var wz := cz + dz
			if dist < float(radius) * (0.4 if is_port else 0.35):
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.TOWN_PATH)
			elif is_port and dist < float(radius) * 0.7 and _rng.randf() < 0.08:
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.WATER)
			elif _rng.randf() < (0.18 if is_port else 0.12):
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.FARMLAND)