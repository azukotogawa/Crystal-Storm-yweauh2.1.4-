extends SceneTree
## P1 regression: crystal enemies and fauna use dedicated voxel props (not generic fallback).


const _VoxelPropBuilder = preload("res://helpers/voxel_prop_builder.gd")
const _EnemySpawnRegistry = preload("res://entities/enemy_spawn_registry.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


const CRYSTAL_ENEMIES: Array[String] = [
	"crystal_mite",
	"thornling",
	"shard_guard",
	"farm_bomber",
	"crystal_stag",
	"corrupted_beast",
]

const FAUNA_ENTITIES: Array[String] = ["rabbit", "deer", "bird"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var builder_src := (load("res://helpers/voxel_prop_builder.gd") as GDScript).source_code
	for enemy_id in CRYSTAL_ENEMIES:
		if '"%s"' % enemy_id not in builder_src:
			push_error("voxel_prop_builder missing dedicated mesh for %s" % enemy_id)
			failed = true
	if not failed:
		print("OK crystal enemy mesh cases present")

	_EnemySpawnRegistry.ensure_builtins()
	var vs: float = _WorldSettings.get_active().voxel_scale
	var min_heights: Dictionary = {
		"crystal_mite": vs * 1.05,
		"thornling": vs * 1.8,
		"shard_guard": vs * 2.2,
	}

	for enemy_id in CRYSTAL_ENEMIES:
		var def = _EnemySpawnRegistry.get_def(StringName(enemy_id))
		var tint: Color = def.tint if def else Color.WHITE
		var prop := _VoxelPropBuilder.build_entity(StringName(enemy_id), tint)
		var h := _VoxelPropBuilder.model_height(prop)
		var min_h: float = float(min_heights.get(enemy_id, vs * 1.8))
		if prop.get_child_count() < 3:
			push_error("%s voxel prop needs >=3 shards, got %d" % [enemy_id, prop.get_child_count()])
			failed = true
			continue
		if h < min_h:
			push_error("%s voxel height %.2f below %.2f" % [enemy_id, h, min_h])
			failed = true
			continue
		print("OK %s shards=%d height=%.2f" % [enemy_id, prop.get_child_count(), h])

	for fauna_id in FAUNA_ENTITIES:
		var prop := _VoxelPropBuilder.build_entity(StringName(fauna_id))
		if prop.get_child_count() < 2:
			push_error("%s fauna voxel prop too sparse" % fauna_id)
			failed = true
		else:
			print("OK fauna %s boxes=%d" % [fauna_id, prop.get_child_count()])

	var generic := _VoxelPropBuilder.build_entity(&"unknown_enemy_xyz")
	if generic.get_child_count() != 2:
		push_error("unknown entity should still use generic fallback")
		failed = true
	else:
		print("OK generic fallback preserved")

	var enemy_src := (load("res://entities/crystal_enemy.gd") as GDScript).source_code
	if "build_entity(enemy_id" not in enemy_src or "model_height" not in enemy_src:
		push_error("crystal_enemy must build voxel props and use model_height for combat center")
		failed = true
	else:
		print("OK crystal_enemy voxel visual path")

	if failed:
		quit(1)
	print("All entity voxel model tests OK")
	quit(0)