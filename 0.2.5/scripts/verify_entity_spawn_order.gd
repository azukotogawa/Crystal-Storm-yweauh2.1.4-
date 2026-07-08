extends SceneTree

const _WorldEntity = preload("res://entities/world_entity.gd")
const _EntityBrainRegistry = preload("res://entities/entity_brain_registry.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_EntityBrainRegistry.ensure_builtins()
	var brain_cfg = _EntityBrainRegistry.get_def(&"rabbit")
	if brain_cfg == null:
		push_error("missing rabbit brain config")
		quit(1)
		return

	var scene_root := Node3D.new()
	scene_root.name = "SpawnOrderTestRoot"
	root.add_child(scene_root)

	var entity: _WorldEntity = _WorldEntity.new()
	scene_root.add_child(entity)
	await process_frame
	if not entity.is_inside_tree():
		push_error("entity should be inside tree after add_child")
		failed = true
	entity.setup(brain_cfg, Vector2i(4, 6), null, null, null, Vector2i.ZERO, Color.WHITE)
	await process_frame
	var ws = _WorldSettings.get_active()
	var expected_x: float = ws.column_to_world(4.5)
	var expected_z: float = ws.column_to_world(6.5)
	if entity.global_position == Vector3.ZERO:
		push_error("entity global_position unset after in-tree setup")
		failed = true
	elif not is_equal_approx(entity.global_position.x, expected_x) or not is_equal_approx(entity.global_position.z, expected_z):
		push_error("entity spawn should use scaled world coords: got %s" % entity.global_position)
		failed = true
	else:
		print("OK world entity spawn position ", entity.global_position)

	var enemy_scr = load("res://entities/crystal_enemy.gd")
	var enemy = enemy_scr.new()
	scene_root.add_child(enemy)
	enemy.global_position = Vector3(10.5, 1.0, 12.5)
	await process_frame
	enemy.setup(&"crystal_mite", null, null)
	if not enemy.is_inside_tree():
		push_error("enemy should be inside tree after add_child")
		failed = true
	else:
		print("OK crystal enemy in-tree setup")

	scene_root.queue_free()
	if failed:
		quit(1)
	print("All entity spawn order tests OK")
	quit(0)