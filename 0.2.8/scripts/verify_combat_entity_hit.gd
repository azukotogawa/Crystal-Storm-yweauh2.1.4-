extends SceneTree
## Regression: melee hit resolver uses world-space origin matching entity global_position.


const _CombatHitResolver = preload("res://systems/combat_hit_resolver.gd")
const _CombatDef = preload("res://config/combat_def.gd")
const _ActionTargeting = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")


class _FakeEntity extends Node3D:
	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 0.35

	func is_combat_alive() -> bool:
		return true

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var ws = _WorldSettings.get_active()
	var origin_col := Vector3(10.5, 12.0, 10.5)
	var origin_world := Vector3(
		ws.column_to_world(origin_col.x),
		origin_col.y + 0.8,
		ws.column_to_world(origin_col.z)
	)
	var forward := Vector3(1.0, 0.0, 0.0)

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var entity := _FakeEntity.new()
	entity.add_to_group("world_entity")
	holder.add_child(entity)
	entity.global_position = origin_world + Vector3(ws.voxel_scale * 0.6, 0.0, 0.0)
	await process_frame

	var hits_wrong: Array = _CombatHitResolver.query_melee(
		holder, origin_col + Vector3(0.0, 0.8, 0.0), forward, 3.0, _CombatDef.create_default(), 90.0
	)
	var hits_right: Array = _CombatHitResolver.query_melee(
		holder, origin_world, forward, 3.0, _CombatDef.create_default(), 90.0
	)

	if hits_wrong.size() > 0:
		push_error("column-space origin must not hit world-space entity")
		failed = true
	elif hits_right.size() != 1:
		push_error("world-space origin should hit adjacent entity, got %d" % hits_right.size())
		failed = true
	else:
		print("OK combat world-space hit count=%d" % hits_right.size())

	var weapon_src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	if "_ActionTargeting.attack_origin_world" not in weapon_src:
		push_error("weapon_controller must use attack_origin_world")
		failed = true
	else:
		print("OK weapon uses attack_origin_world")

	var vfx_src := (load("res://systems/combat_visual_feedback.gd") as GDScript).source_code
	if "_on_weapon_attacked" not in vfx_src or "attacked.connect" not in vfx_src:
		push_error("combat_visual_feedback must connect weapon.attacked for swing VFX")
		failed = true
	else:
		print("OK combat swing VFX on attacked signal")
	if "_crystal_target_cell" not in weapon_src or "floori(hit_pos" in weapon_src:
		push_error("weapon_controller must use _crystal_target_cell for crystal damage")
		failed = true
	else:
		print("OK weapon uses column crystal targeting")

	holder.queue_free()
	if failed:
		quit(1)
	print("All combat entity hit tests OK")
	quit(0)