class_name RuinManager
extends Node

const _WorldBorder = preload("res://helpers/world_border.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _WorldFeatureTypes = preload("res://helpers/world_feature_types.gd")

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
		var ruin_data := {
			"center": center,
			"name": "Ruin %d" % (placed.size() + 1),
			"radius": 5,
		}
		ruins.append(ruin_data)
		placed.append(center)
		_stamp_ruin(center, str(ruin_data.name))
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


func _stamp_ruin(center: Vector2i, ruin_name: String = "Forgotten Ruin") -> void:
	for dx in range(-5, 6):
		for dz in range(-5, 6):
			if Vector2(dx, dz).length() > 5.0:
				continue
			var wx := center.x + dx
			var wz := center.y + dz
			_FeatureRegistry.register_feature(wx, wz, _WorldFeatureTypes.FeatureKind.RUIN, {
				"center": center,
				"name": ruin_name,
				"is_spawn_point": true,
			})
			if absi(dx) <= 1 and absi(dz) <= 1:
				_FeatureRegistry.set_tile_override(wx, wz, VoxelTypes.STONE2, true)