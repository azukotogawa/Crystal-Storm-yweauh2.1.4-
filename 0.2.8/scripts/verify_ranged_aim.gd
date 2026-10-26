extends SceneTree

const _RangedAim = preload("res://weapons/ranged_aim.gd")
const _GameFeelConfig = preload("res://config/game_feel_config.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _ItemTypes = preload("res://helpers/item_types.gd")

const _Projectile = preload("res://weapons/projectile.gd")

var _failed := 0


class FakeEnemy:
	extends Node3D
	var hits := 0

	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 1.0

	func is_combat_alive() -> bool:
		return true

	func take_damage(_amount: float, _source: StringName) -> void:
		hits += 1


class FakeWorld:
	extends Node

	func get_surface_height(col_x: float, _col_z: float) -> float:
		return 8.0 if col_x >= 10.0 else 0.0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _run() -> void:
	var cfg = _GameFeelConfig.active()
	var bow := _ItemTypes.get_def("shortbow")
	var item_speed := float(bow.get("projectile_speed", 32.0))
	var last := -1.0
	for c in [0.2, 0.4, 0.6, 0.8, 1.0]:
		var v := _RangedAim.speed_for(c, item_speed)
		var want: float = lerpf(cfg.draw_min_speed, cfg.draw_max_speed, pow(c, cfg.draw_curve)) * item_speed / 32.0
		if v <= last:
			_fail("speed not increasing at charge %.1f" % c)
		if absf(v - want) > want * 0.01:
			_fail("speed %.2f want %.2f" % [v, want])
		last = v

	var ray_dir := Vector3(-0.5, -0.7, -0.5).normalized()
	var muzzles := [Vector3(0, 2, 0), Vector3(5, 2, -3), Vector3(0, 8, 0), Vector3(-4, 12, 6), Vector3(10, 1, 10), Vector3(2, 20, 2)]
	var offsets := [Vector3(6, 0, 0), Vector3(0, 0, 9), Vector3(-7, 0, -4), Vector3(3, 0, 3), Vector3(12, 0, -2), Vector3(-2, 0, 11)]
	for i in 6:
		var m: Vector3 = muzzles[i]
		var ray_origin: Vector3 = m + offsets[i] - ray_dir * 40.0
		var dir := _RangedAim.launch_direction(m, ray_origin, ray_dir)
		var point := _RangedAim.cursor_point(ray_origin, ray_dir, m.y)
		var on_ray := (point - ray_origin).normalized().angle_to(ray_dir)
		var aimed := dir.angle_to((point - m).normalized())
		if on_ray > 0.001 or absf(point.y - m.y) > 0.01:
			_fail("cursor point %d is off the cursor ray" % i)
		if rad_to_deg(aimed) > 2.0:
			_fail("launch direction %d is %.2f degrees off" % [i, rad_to_deg(aimed)])
	var flat := _RangedAim.launch_direction(Vector3(0, 2, 0), Vector3(8, 40, 8), ray_dir)
	if absf(flat.y) > 0.01:
		_fail("muzzle-height plane should give a level launch")

	var dir := Vector3(1, 0.25, 0).normalized()
	var g := float(bow.get("projectile_gravity", 12.0))
	var full := _RangedAim.simulate_range(_RangedAim.speed_for(1.0, item_speed), dir, g)
	var half := _RangedAim.simulate_range(_RangedAim.speed_for(0.5, item_speed), dir, g)
	var least := _RangedAim.simulate_range(_RangedAim.speed_for(cfg.draw_min_charge, item_speed), dir, g)
	if not (full > half and half > least):
		_fail("range full %.1f half %.1f min %.1f" % [full, half, least])

	var w := Node.new()
	w.set_script(load("res://weapons/weapon_controller.gd"))
	root.add_child(w)
	w.inventory = _Inventory.new()
	w.inventory.set_slot(0, "sling", 1)
	w.inventory.set_slot(1, "stone", 5)
	await process_frame
	w._drawing = true
	w._draw_item = "sling"
	w._draw_sec = 0.0
	w._tick_draw(0.05)
	if w._drawing or w._cooldown_timer != 0.0 or w.inventory.count_item("stone") != 5:
		_fail("short draw must cancel and keep ammo and cooldown")
	w._drawing = true
	w._draw_sec = 0.0
	w._tick_draw(1.0)
	if w._cooldown_timer <= 0.0 or w._draw_charge < 0.99:
		_fail("full draw must start the shot")

	_check_contacts()

	if _failed == 0:
		print("All ranged aim checks OK")
		quit(0)
	else:
		quit(1)


func _fly(kind: String, origin: Vector3, vel: Vector3, enemy: Node3D) -> Projectile:
	var world := FakeWorld.new()
	root.add_child(world)
	var proj := _Projectile.new()
	root.add_child(proj)
	proj._activate({"origin": origin, "velocity": vel, "gravity": 0.0, "kind": kind, "damage": 5.0, "world": world, "blast_radius": 1.0, "ttl": 5.0})
	var nodes: Array = [enemy] if enemy != null else []
	for _i in 200:
		var result := proj.integrate(0.02, nodes)
		if result != "fly":
			break
	return proj


func _check_contacts() -> void:
	var enemy := FakeEnemy.new()
	root.add_child(enemy)
	enemy.global_position = Vector3(6.0, 3.0, 0.0)
	var radius := 0.65
	for kind in ["arrow", "stone", "bomb"]:
		enemy.hits = 0
		var proj := _fly(kind, Vector3(0.0, 3.0, 0.0), Vector3(20.0, 0.0, 0.0), enemy)
		var hit: Dictionary = proj.last_hit
		if str(hit.get("kind", "")) != "entity":
			_fail("%s did not hit the hitbox" % kind)
			continue
		var off := absf(Vector3(hit.pos).distance_to(enemy.global_position) - (radius + proj.hit_radius))
		if off > 0.1:
			_fail("%s contact is %.2f off the hitbox surface" % [kind, off])
		if enemy.hits < 1:
			_fail("%s did not damage" % kind)
		if kind == "arrow" and not proj.stuck:
			_fail("arrow did not stick at the contact point")
		if kind == "stone" and (proj.velocity != Vector3.ZERO or proj.stuck):
			_fail("stone did not drop at the contact point")
		proj.queue_free()
	var miss := _fly("arrow", Vector3(0.0, 3.0, 1.2), Vector3(20.0, 0.0, 0.0), enemy)
	if not miss.last_hit.is_empty() and str(miss.last_hit.get("kind", "")) == "entity":
		_fail("a shot passing beside the hitbox recorded a hit")
	var wall := _fly("arrow", Vector3(0.0, 2.0, 0.0), Vector3(20.0, 0.0, 0.0), null)
	var scale: float = load("res://config/world_settings.gd").get_active().voxel_scale
	if str(wall.last_hit.get("kind", "")) != "terrain" or not wall.stuck:
		_fail("arrow did not stick in the wall")
	elif absf(Vector3(wall.last_hit.pos).x - 10.0 * scale) > 0.1:
		_fail("arrow stuck at x %.2f, wall face is %.2f" % [Vector3(wall.last_hit.pos).x, 10.0 * scale])
	var bomb := _fly("bomb", Vector3(0.0, 2.0, 0.0), Vector3(20.0, 0.0, 0.0), null)
	if str(bomb.last_hit.get("kind", "")) != "terrain" or absf(Vector3(bomb.last_hit.pos).x - 10.0 * scale) > 0.1:
		_fail("bomb did not explode at the wall face")
