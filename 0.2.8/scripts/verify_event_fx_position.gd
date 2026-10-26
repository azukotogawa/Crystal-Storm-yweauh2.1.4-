extends SceneTree

const _VfxPool = preload("res://systems/vfx_pool.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

class FakeWorld:
	extends Node
	func get_surface_height(_x, _z) -> float:
		return 14.0

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _run() -> void:
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	var fake := FakeWorld.new()
	root.add_child(fake)
	await process_frame
	var cell := Vector2i(6, -3)
	var point: Vector3 = w._surface_point(float(cell.x) + 0.5, float(cell.y) + 0.5, 0.0, fake)
	var cell_center := Vector3(ws.column_to_world(cell.x + 0.5), 14.0, ws.column_to_world(cell.y + 0.5))
	if point.distance_to(cell_center) > 0.01:
		_fail("surface point %s is not the cell surface %s" % [point, cell_center])
	var player := Vector3(0.0, 40.0, 0.0)
	var pool := _VfxPool.new()
	root.add_child(pool)
	pool.configure_preset(1)
	await process_frame
	for style in ["wooden_sword", "spear", "crystal_hammer", "stone_pick"]:
		pool.show_swing(style, point, point - player)
		var found := false
		for mesh in pool._swings:
			if mesh.visible:
				found = true
				var flat := Vector2(mesh.global_position.x - point.x, mesh.global_position.z - point.z)
				var up := absf(mesh.global_position.y - point.y)
				print("%s swing offset %.2f blocks, %.2f up" % [style, flat.length() / vs, up / vs])
				if flat.length() > 0.5 * vs or up > 0.8 * vs:
					_fail("%s swing drawn %.2f blocks from the event" % [style, flat.length() / vs])
				mesh.visible = false
		if not found:
			_fail("%s drew no swing" % style)
		for i in pool._swing_life.size():
			pool._swing_life[i] = 0.0
		pool._swing_busy = 0
	var src := FileAccess.get_file_as_string("res://weapons/weapon_controller.gd")
	if src.contains("player.voxel_position.y if player else 0.0,\n\t\t\t_"):
		_fail("unexpected feet height emit")
	if _failed == 0:
		print("All event fx position checks OK")
		quit(0)
	else:
		quit(1)
