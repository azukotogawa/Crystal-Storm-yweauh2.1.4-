extends SceneTree
## Regression: weapon crystal damage uses COLUMN cells (spawn.world_pos), not world-space floori.


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _SpawnPointController = preload("res://crystal/spawn_point_controller.gd")
const _CrystalSpawnPoint = preload("res://crystal/crystal_spawn_point.gd")
const _CrystalTypes = preload("res://helpers/crystal_types.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _CrystalManager = preload("res://crystal/crystal_manager.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var spawn_cell := Vector2i(10, 10)
	var spawn := _CrystalSpawnPoint.new(1, spawn_cell, _CrystalTypes.SpawnKind.RUIN, 80.0, false)
	var ctrl := _SpawnPointController.new()
	ctrl.set_spawns([spawn])

	var player := Player.new()
	player.voxel_position = Vector3(8.5, 12.0, 8.5)
	player.is_input_locked = true
	player.locked_rotation = 0

	var range_v: float = float(_ItemTypes.get_def("wooden_sword").get("range", 2.8))
	var target_cell := _ActionTargeting.target_cell(player, range_v)
	var origin_world := _ActionTargeting.attack_origin_world(player, 0.5)
	var hit_pos_world := origin_world + _ActionTargeting.attack_forward(player) * range_v
	var wrong_cell := Vector2i(floori(hit_pos_world.x), floori(hit_pos_world.z))

	if target_cell.distance_to(spawn_cell) > 1.5:
		push_error("target_cell %s should be near spawn %s" % [target_cell, spawn_cell])
		failed = true
	else:
		print("OK target_cell=%s near spawn=%s" % [target_cell, spawn_cell])

	if wrong_cell == spawn_cell:
		push_error("world-space floori %s must not equal column spawn %s" % [wrong_cell, spawn_cell])
		failed = true
	else:
		print("OK world-space cell %s != column spawn %s" % [wrong_cell, spawn_cell])

	var hp_before: float = spawn.health
	ctrl.damage_spawn_at_world(wrong_cell, 12.0, range_v)
	if spawn.health < hp_before - 0.01:
		push_error("world-space cell %s must not damage column spawn" % wrong_cell)
		failed = true
	else:
		print("OK world-space cell did not reduce spawn HP")

	spawn.health = 80.0
	hp_before = spawn.health
	ctrl.damage_spawn_at_world(target_cell, 12.0, range_v)
	if spawn.health >= hp_before - 0.01:
		push_error("column target_cell %s must reduce spawn HP at %s" % [target_cell, spawn_cell])
		failed = true
	else:
		print("OK column cell %s damaged spawn HP %.0f→%.0f" % [target_cell, hp_before, spawn.health])

	var holder := Node.new()
	root.add_child(holder)
	var weapon := _WeaponController.new()
	var prod_player := Player.new()
	prod_player.voxel_position = Vector3(8.5, 12.0, 8.5)
	prod_player.is_input_locked = true
	prod_player.locked_rotation = 0
	prod_player.world_ready = true
	weapon.player = prod_player
	holder.add_child(weapon)
	var cm: _CrystalManager = _CrystalManager.new()
	cm.harness_setup_spawns([_CrystalSpawnPoint.new(2, spawn_cell, _CrystalTypes.SpawnKind.RUIN, 60.0, false)])
	weapon.crystal_manager = cm

	var prod_spawn: CrystalSpawnPoint = cm.get_spawn_at_cell(spawn_cell.x, spawn_cell.y)
	var prod_hp: float = prod_spawn.health
	var sword_def: Dictionary = _ItemTypes.get_def("wooden_sword")
	weapon._do_melee_attack("wooden_sword", sword_def)
	if prod_spawn.health >= prod_hp - 0.01:
		push_error("production _do_melee_attack must damage adjacent spawn via column coords")
		failed = true
	else:
		print("OK production melee damaged spawn HP %.0f→%.0f" % [prod_hp, prod_spawn.health])

	var src := (_WeaponController as GDScript).source_code
	if "_crystal_target_cell" not in src or "floori(hit_pos" in src:
		push_error("weapon_controller must use _crystal_target_cell, not floori(hit_pos)")
		failed = true
	else:
		print("OK weapon_controller uses _crystal_target_cell")

	holder.queue_free()
	if failed:
		quit(1)
	print("All combat crystal damage tests OK")
	quit(0)