extends SceneTree

const _CombatHitbox = preload("res://systems/combat_hitbox.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")
const _RangedAim = preload("res://weapons/ranged_aim.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _run() -> void:
	var dir := Vector3(-0.5, -0.7, -0.5).normalized()
	var from := Vector3(0, 1, 0)
	var sword := _ItemTypes.get_def("wooden_sword")
	var reach: float = float(sword.range) * load("res://config/world_settings.gd").get_active().voxel_scale
	var near_origin := Vector3(reach * 0.5, 1, 0) - dir * 30.0
	var far_origin := Vector3(reach * 2.0, 1, 0) - dir * 30.0
	if not _CombatHitbox.cursor_in_reach(near_origin, dir, from, reach):
		_fail("cursor in range was refused")
	if _CombatHitbox.cursor_in_reach(far_origin, dir, from, reach):
		_fail("cursor beyond range was accepted")

	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	w.inventory = _Inventory.new()
	w.inventory.set_slot(0, "wooden_sword", 1)
	await process_frame
	w._refuse_use("Out of range")
	if w.refused_count != 1 or w._cooldown_timer != 0.0 or w._playback != null:
		_fail("a refusal must not start a cooldown or an animation")

	w.inventory.set_slot(0, "shortbow", 1)
	w.inventory.set_slot(1, "arrow", 5)
	w._drawing = true
	w._draw_item = "shortbow"
	w._draw_sec = 0.0
	w._tick_draw(1.0)
	if w._cooldown_timer <= 0.0 or w._playback == null:
		_fail("a bow release with the cursor far away must still fire")
	if _RangedAim.cancels(1.0):
		_fail("full charge cancelled")

	if _failed == 0:
		print("All use refusal checks OK")
		quit(0)
	else:
		quit(1)
