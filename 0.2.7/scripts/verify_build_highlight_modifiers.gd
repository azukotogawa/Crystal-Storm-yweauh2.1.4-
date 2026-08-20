extends SceneTree
## P1 regression: build highlight available while sword selected if build_place held + stone.


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")


class _FakeWeapon extends Node:
	var _slot: Variant = null

	func get_active_item() -> Variant:
		return _slot

	func set_slot(id: String) -> void:
		_slot = {"id": id, "count": 1}


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.5, 8.0, 10.5)
	var inventory
	var is_input_locked := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var targeting_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if "build_place" not in targeting_src:
		push_error("action_targeting must consider build_place for build mode")
		failed = true
	else:
		print("OK action_targeting build_place gate")

	var highlight_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "build_place" not in highlight_src or "BUILD_PREVIEW_RANGE" not in highlight_src:
		push_error("target_highlight must preview build while build_place held")
		failed = true
	else:
		print("OK target_highlight build preview path")

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	holder.add_child(world)

	var player := _FakePlayer.new()
	player.name = "Player"
	var inv = load("res://inventory/inventory.gd").new()
	inv.add_item("stone", 4)
	player.inventory = inv
	holder.add_child(player)

	var weapon := _FakeWeapon.new()
	weapon.name = "WeaponController"
	weapon.set_slot("wooden_sword")
	player.add_child(weapon)

	await process_frame

	var mode_sword := _ActionTargeting._weapon_mode_from_player(player, false)
	if mode_sword != &"attack":
		push_error("sword alone should be attack mode, got %s" % mode_sword)
		failed = true
	else:
		print("OK sword idle -> attack mode")

	var mode_build := _ActionTargeting._weapon_mode_from_player(player, true)
	if mode_build != &"build":
		push_error("simulate_interact with stone should force build mode, got %s" % mode_build)
		failed = true
	else:
		print("OK simulate_interact + stone -> build mode")

	var probe_cell := Vector2i.ZERO
	for gx in range(-24, 25):
		for gz in range(-24, 25):
			if _ActionTargeting._is_solid_column(world, null, gx, gz):
				probe_cell = Vector2i(gx, gz)
				break
		if probe_cell != Vector2i.ZERO:
			break
	if probe_cell == Vector2i.ZERO:
		push_error("no solid column for build resolve probe")
		failed = true
	else:
		player.voxel_position = Vector3(float(probe_cell.x) + 0.5, 8.0, float(probe_cell.y) + 0.5)
		var build_info := _ActionTargeting.resolve_action(
			player, world, null, 2.8, true, &"build"
		)
		if build_info.get("mode", &"") != &"build":
			push_error("forced build resolve must return build mode")
			failed = true
		elif not build_info.get("valid", false):
			push_error("build resolve must be valid at probe with stone")
			failed = true
		else:
			print("OK build resolve valid cell=%s" % build_info.get("cell"))

	holder.queue_free()
	if failed:
		print("Build highlight modifier tests FAILED")
		quit(1)
		return
	print("All build highlight modifier tests OK")
	quit(0)