extends SceneTree
## Regression: ActionTargeting modes + TargetHighlight wiring for dig/build/attack columns.


const _ActionTargeting = preload("res://player/action_targeting.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")
const _WorldSettings = preload("res://config/world_settings.gd")



class _FakeWeapon extends Node:
	var _slot: Variant = null

	func get_active_item() -> Variant:
		return _slot

	func set_slot(id: String) -> void:
		_slot = {"id": id, "count": 1}


class _FakePlayer extends Node3D:
	var voxel_position := Vector3(10.5, 8.0, 10.5)
	var world: InfiniteNoiseWorld
	var locked_rotation := 0
	var is_input_locked := false
	var camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false

	var player_src := (load("res://player/player.gd") as GDScript).source_code
	if "TargetHighlight" not in player_src:
		push_error("player.gd must attach TargetHighlight")
		failed = true
	else:
		print("OK player wires TargetHighlight")

	var highlight_src := (load("res://player/target_highlight.gd") as GDScript).source_code
	if "_ActionTargeting.resolve_action" not in highlight_src:
		push_error("target_highlight must call ActionTargeting.resolve_action")
		failed = true
	elif '"valid"' not in highlight_src:
		push_error("target_highlight must gate on resolve_action valid flag")
		failed = true
	elif "render_priority" not in highlight_src:
		push_error("target_highlight must set render_priority for visibility")
		failed = true
	else:
		print("OK highlight uses ActionTargeting + render_priority")

	var targeting_src := (load("res://player/action_targeting.gd") as GDScript).source_code
	if "_TerrainRamps.walkable_height" not in targeting_src:
		push_error("action_targeting must use ramp-aware walkable height")
		failed = true
	elif "_is_solid_column" not in targeting_src:
		push_error("action_targeting must filter air/fluid columns for highlight")
		failed = true
	elif "_walkable_top" not in targeting_src:
		push_error("action_targeting must use chunk ramp entries for walkable top")
		failed = true
	elif "_ray_y_hits_surface_slab" not in targeting_src:
		push_error("action_targeting must raycast against surface slabs")
		failed = true
	else:
		print("OK action_targeting ramp-aware Y + solid-column filter")

	var holder := Node.new()
	holder.name = "TestRoot"
	root.add_child(holder)

	var world = load("res://world/InfiniteNoiseWorld.gd").new()
	world.world_seed = 42
	holder.add_child(world)
	world.add_to_group("world")

	var player := _FakePlayer.new()
	player.name = "Player"
	player.world = world
	holder.add_child(player)

	player.is_input_locked = true
	player.locked_rotation = 0

	var weapon := _FakeWeapon.new()
	weapon.name = "WeaponController"
	player.add_child(weapon)

	await process_frame

	var start_cell := Vector2i.ZERO
	for gx in range(-24, 25):
		for gz in range(-24, 25):
			if _ActionTargeting._is_solid_column(world, null, gx, gz):
				start_cell = Vector2i(gx, gz)
				break
		if start_cell != Vector2i.ZERO:
			break
	if start_cell == Vector2i.ZERO:
		push_error("could not find solid column for highlight probe")
		failed = true
	else:
		player.voxel_position = Vector3(float(start_cell.x) + 0.5, 8.0, float(start_cell.y) + 0.5)
		print("OK highlight probe cell=%s" % start_cell)

	weapon.set_slot("stone_pick")
	var dig_info := _ActionTargeting.resolve_action(player, world, null, 2.0)
	if dig_info.get("mode", &"") != &"dig":
		push_error("pickaxe should resolve dig mode, got %s" % dig_info.get("mode"))
		failed = true
	elif not dig_info.get("valid", false):
		push_error("dig highlight target must be valid solid column")
		failed = true
	else:
		print("OK dig mode cell=%s valid" % dig_info.get("cell"))

	weapon.set_slot("wooden_sword")
	var atk_info := _ActionTargeting.resolve_action(player, world, null, 2.0)
	if atk_info.get("mode", &"") != &"attack":
		push_error("sword should resolve attack mode, got %s" % atk_info.get("mode"))
		failed = true
	elif not atk_info.get("valid", false):
		push_error("attack highlight target must be valid solid column")
		failed = true
	else:
		print("OK attack mode cell=%s valid" % atk_info.get("cell"))

	weapon._slot = {"id": "stone", "count": 3}
	var build_info := _ActionTargeting.resolve_action(player, world, null, 2.0)
	if build_info.get("mode", &"") != &"build":
		push_error("stone hotbar should resolve build mode, got %s" % build_info.get("mode"))
		failed = true
	elif not build_info.get("valid", false):
		push_error("build highlight target must be valid solid column")
		failed = true
	else:
		print("OK build mode from stone hotbar cell=%s valid" % build_info.get("cell"))

	var ws = _WorldSettings.get_active()
	var layer: float = ws.layer_height()
	var flat_y: float = float(dig_info.get("world_pos", Vector3.ZERO).y)
	var surf: float = float(dig_info.get("surface_y", 0.0))
	var walk_top: float = surf + layer
	if world:
		var col: Vector3 = dig_info.get("column", Vector3.ZERO)
		walk_top = _ActionTargeting._walkable_top(world, null, col.x, col.z)
	var expected_y: float = walk_top - layer * 0.5
	if absf(flat_y - expected_y) > layer * 0.75:
		push_error("dig highlight Y should center surface block, got %.2f expected~%.2f walk=%.2f" % [flat_y, expected_y, walk_top])
		failed = true
	else:
		print("OK highlight world_y=%.2f" % flat_y)

	var fluid_cell := Vector2i.ZERO
	for gx in range(-8, 9):
		for gz in range(-8, 9):
			var tid: int = world.get_tile_type(float(gx), float(gz))
			if tid == _VoxelTypes.RIVER or tid == _VoxelTypes.OCEAN2:
				fluid_cell = Vector2i(gx, gz)
				break
		if fluid_cell != Vector2i.ZERO:
			break
	if fluid_cell != Vector2i.ZERO:
		if _ActionTargeting._is_solid_column(world, null, fluid_cell.x, fluid_cell.y):
			push_error("fluid column %s must not count as solid" % fluid_cell)
			failed = true
		else:
			print("OK fluid column %s rejected" % fluid_cell)
	else:
		print("OK fluid column scan skipped (no river/ocean in probe window)")

	holder.queue_free()
	if failed:
		quit(1)
	print("All target highlight tests OK")
	quit(0)