extends SceneTree
## Regression: entity died signal must not error when connected to EntityManager.


const _WorldEntity = preload("res://entities/world_entity.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _EntityManager = preload("res://entities/entity_manager.gd")
const _WorldVisuals = preload("res://world/world_visuals.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_EntityBrainRegistry.ensure_builtins()

	var holder := Node3D.new()
	root.add_child(holder)
	var world_visuals := _WorldVisuals.new()
	holder.add_child(world_visuals)
	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.add_to_group("world")
	holder.add_child(world)
	var em := _EntityManager.new()
	holder.add_child(em)
	await process_frame

	var entity: _WorldEntity = _WorldEntity.new()
	entity.died.connect(em._on_entity_died)
	em._entity_parent().add_child(entity)
	entity.setup(_EntityBrainRegistry.get_def(&"rabbit"), Vector2i(8, 9), world, null, null)
	em._entities.append(entity)
	em._spawned_cells[Vector2i(8, 9)] = true
	await process_frame

	entity.take_damage(999.0, &"player")
	for _i in 5:
		await process_frame

	if em._spawned_cells.has(Vector2i(8, 9)):
		push_error("spawned_cells should clear on death")
		failed = true
	elif not is_instance_valid(entity):
		print("OK entity death signal clean")
	else:
		push_error("entity should be freed")
		failed = true

	holder.queue_free()
	if failed:
		quit(1)
	print("All entity death signal tests OK")
	quit(0)