extends SceneTree
## Regression: sword/bow LMB must never dig or remove terrain/buildings (INPUT_CONTRACT).

const _Inventory = preload("res://inventory/inventory.gd")
const _WeaponController = preload("res://weapons/weapon_controller.gd")
const _PlaceableCatalog = preload("res://helpers/placeable_catalog.gd")
const _Capture = preload("res://helpers/probe_capture.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	var src := (_WeaponController as GDScript).source_code
	if "_is_active_combat_weapon" not in src:
		push_error("weapon_controller must define _is_active_combat_weapon")
		failed = true
	elif "if not _is_active_combat_weapon()" not in src:
		push_error("LMB terrain subtract must be gated by _is_active_combat_weapon")
		failed = true
	else:
		print("OK combat-weapon gate wraps LMB subtract")

	if not _PlaceableCatalog.is_terrain_edit("fill"):
		push_error("default place id fill must count as terrain_edit (reproduces bug preconditions)")
		failed = true
	else:
		print("OK place_index 0 (fill) is terrain_edit")

	var weapon := _WeaponController.new()
	var inv := _Inventory.new()
	weapon.inventory = inv
	weapon._active_hotbar_index = 0
	weapon.place_index = 0

	inv.set_slot(0, "wooden_sword", 1)
	if not weapon._is_active_combat_weapon():
		push_error("wooden_sword must be active combat weapon")
		failed = true
	elif weapon._is_active_dig_tool():
		push_error("wooden_sword must not be dig tool")
		failed = true
	else:
		print("OK wooden_sword is combat weapon, not dig tool")

	inv.set_slot(0, "shortbow", 1)
	if not weapon._is_active_combat_weapon():
		push_error("shortbow must be active combat weapon")
		failed = true
	else:
		print("OK shortbow is combat weapon")

	inv.set_slot(0, "stone_pick", 1)
	if weapon._is_active_combat_weapon():
		push_error("stone_pick must not be combat weapon")
		failed = true
	elif not weapon._is_active_dig_tool():
		push_error("stone_pick must be dig tool")
		failed = true
	else:
		print("OK stone_pick is dig tool, not combat weapon")

	inv.set_slot(0, "stone", 1)
	if weapon._is_active_combat_weapon() or weapon._is_active_dig_tool():
		push_error("stone material must be neither combat weapon nor dig tool")
		failed = true
	else:
		print("OK stone is neither a combat weapon nor a dig tool")

	weapon.free()
	await _Capture.capture_step("dig-sword-guard")
	if failed:
		quit(1)
		return
	print("All sword-no-terrain-subtract tests OK")
	quit(0)
