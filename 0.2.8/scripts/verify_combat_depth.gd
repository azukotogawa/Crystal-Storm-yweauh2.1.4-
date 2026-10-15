extends SceneTree


const _ItemTypes = preload("res://helpers/item_types.gd")
const _WeaponStrike = preload("res://weapons/weapon_strike.gd")
const _Projectile = preload("res://weapons/projectile.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _EntityNavigation = preload("res://entities/entity_navigation.gd")
const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")


class _Body extends Node3D:
	var hits: int = 0

	func is_combat_alive() -> bool:
		return true

	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 0.4


class _CrystalBook extends RefCounted:
	var cells: Array[Vector2i] = []
	var height_at_center: float = 5.0

	func damage_crystal_at(cell: Vector2i, _amount: float) -> Dictionary:
		cells.append(cell)
		return {"hit": true}

	func damage_spawn_at_world(_cell, _amount, _radius) -> void:
		pass

	func set_voxel(_a = null, _b = null, _c = null) -> void:
		height_at_center = -1.0

	func try_dig(_a = null) -> void:
		height_at_center = -1.0

	func try_remove(_a = null) -> void:
		height_at_center = -1.0


class _FlatWorld extends RefCounted:
	var surface: float = 1.0
	var writes: int = 0

	func get_surface_height(_x, _z) -> float:
		return surface

	func set_voxel(_a = null, _b = null, _c = null) -> void:
		writes += 1

	func try_dig(_a = null) -> void:
		writes += 1

	func try_remove(_a = null) -> void:
		writes += 1


class _KnockWorld extends RefCounted:
	func sample_knock_ground(x: float, _z: float) -> float:
		if x > 3.0:
			return 12.0
		return 0.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_ItemTypes.ensure_builtins()
	if not _spear():
		failed = true
	if not _hammer():
		failed = true
	if not _bomb():
		failed = true
	if not _armor_and_iframes():
		failed = true
	if not _knockback():
		failed = true
	if failed:
		push_error("Combat depth tests FAILED")
		quit(1)
		return
	print("All combat depth OK")
	quit(0)


func _spear() -> bool:
	var def := _ItemTypes.get_def("spear")
	if int(def.get("pierce", 0)) != 2 or float(def.get("range", 0.0)) < 2.5:
		push_error("spear must pierce 2 and reach at least 2.5 columns")
		return false
	if float(def.get("cooldown", 0.0)) <= float(_ItemTypes.get_def("wooden_sword").get("cooldown", 1.0)):
		push_error("spear should be slower than the sword")
		return false
	var parent := Node3D.new()
	root.add_child(parent)
	var near := _Body.new()
	var mid := _Body.new()
	var far := _Body.new()
	var side := _Body.new()
	parent.add_child(near)
	parent.add_child(mid)
	parent.add_child(far)
	parent.add_child(side)
	near.position = Vector3(0, 1, 2)
	mid.position = Vector3(0, 1, 4)
	far.position = Vector3(0, 1, 5.5)
	side.position = Vector3(4, 1, 2)
	var range_w := 3.0 * 2.0
	var hit := _WeaponStrike.thrust_targets(Vector3(0, 1, 0), Vector3(0, 0, 1), range_w, [near, mid, far, side], 2)
	if hit.size() != 2 or hit[0] != near or hit[1] != mid:
		push_error("spear should pierce the first two bodies on the line, got %d" % hit.size())
		return false
	if side in hit or far in hit:
		push_error("spear hit a side body or a third body")
		return false
	print("OK spear reach and pierce")
	return true


func _hammer() -> bool:
	var def := _ItemTypes.get_def("crystal_hammer")
	if float(def.get("crystal_damage", 0.0)) < 4.0 or int(def.get("splash", 0)) != 1:
		push_error("hammer needs high crystal damage and a 3x3 splash")
		return false
	if float(def.get("entity_damage", 99.0)) >= float(_ItemTypes.get_def("wooden_sword").get("entity_damage", 0.0)):
		push_error("hammer entity damage should stay below the sword")
		return false
	var src := (load("res://weapons/weapon_controller.gd") as GDScript).source_code
	var body := _slice(src, "func _do_hammer_attack", "func _throw_bomb")
	if body == "" or _touches_terrain(body):
		push_error("hammer attack must not dig or edit terrain")
		return false
	var book := _CrystalBook.new()
	var before := book.height_at_center
	var cells := _WeaponStrike.splash_cells(Vector2i(4, 7), 1)
	if cells.size() != 9:
		push_error("splash 1 should be 9 cells, got %d" % cells.size())
		return false
	var hits := _WeaponStrike.apply_crystal_cells(book, cells, float(def.get("crystal_damage", 0.0)))
	if hits != 9 or book.height_at_center != before:
		push_error("hammer splash changed height or missed cells")
		return false
	print("OK hammer crystal splash leaves terrain height")
	return true


func _bomb() -> bool:
	var def := _ItemTypes.get_def("crystal_bomb")
	if float(def.get("blast_radius", 0.0)) < 2.0 or not bool(def.get("throwable", false)):
		push_error("crystal bomb must be a throwable with a radius")
		return false
	var src := (load("res://weapons/projectile.gd") as GDScript).source_code
	var body := _slice(src, "func _explode", "func _stick_at")
	if body == "" or _touches_terrain(body):
		push_error("bomb explode must not dig or edit terrain")
		return false
	var disk := _WeaponStrike.blast_cells(Vector2i(0, 0), 2.5)
	var has_edge := false
	var has_far := false
	for cell in disk:
		if cell == Vector2i(2, 0):
			has_edge = true
		if absi(cell.x) >= 3 or absi(cell.y) >= 3:
			has_far = true
	if not has_edge or has_far:
		push_error("bomb radius 2.5 should reach 2 columns and not 3")
		return false
	var book := _CrystalBook.new()
	var world := _FlatWorld.new()
	var parent := Node3D.new()
	root.add_child(parent)
	if not _Projectile.launch(parent, {
		"origin": Vector3(1, 4, 1),
		"velocity": Vector3.ZERO,
		"gravity": 40.0,
		"kind": "bomb",
		"ttl": 2.0,
		"damage": 22.0,
		"crystal_damage": 3.2,
		"blast_radius": 2.5,
		"crystal": book,
		"world": world,
	}):
		push_error("bomb launch failed")
		return false
	var bomb := parent.get_child(parent.get_child_count() - 1) as Projectile
	var state := "fly"
	for _i in 8:
		state = bomb.integrate(0.2, [])
		if state != "fly":
			break
	if state != "blast" and state != "terrain" and state != "crystal":
		push_error("bomb should detonate on the ground, got %s" % state)
		return false
	if book.cells.size() < 5 or book.height_at_center != 5.0 or world.writes != 0:
		push_error("bomb clear missed crystal or wrote terrain (cells=%d writes=%d)" % [book.cells.size(), world.writes])
		return false
	print("OK bomb clears a crystal radius without a height change")
	return true


func _armor_and_iframes() -> bool:
	var inv := _Inventory.new()
	if inv.add_item("stone_plate", 1) != 0 or not inv.equip_armor("stone_plate"):
		push_error("stone plate failed to equip")
		return false
	if absf(inv.armor_damage_multiplier() - 0.72) > 0.001:
		push_error("stone plate should reduce damage to 72%%")
		return false
	if absf(inv.armor_speed_multiplier() - 0.86) > 0.001:
		push_error("stone plate should slow movement to 86%%")
		return false
	var saved: Dictionary = inv.to_dict()
	if str(saved.get("armor", "")) != "stone_plate":
		push_error("armor must save with the inventory")
		return false
	var other := _Inventory.new()
	other.armor_id = "leather_armor"
	other.load_from_dict({"slots": saved.get("slots", [])})
	if other.armor_id != "leather_armor":
		push_error("a save without an armor key must keep the worn piece")
		return false
	other.load_from_dict(saved)
	if other.armor_id != "stone_plate":
		push_error("armor failed to load")
		return false

	var player := Player.new()
	player.inventory = inv
	player.health = 100.0
	player.max_health = 100.0
	player.player_mesh = MeshInstance3D.new()
	player.player_mesh.visible = true
	if player.HIT_IFRAMES < 0.5 or player.HIT_IFRAMES > 0.7:
		push_error("player i-frames should be about 0.6s")
		return false
	player.take_damage(25.0)
	var after_hit := player.health
	if after_hit >= 100.0 or absf(after_hit - 82.0) > 0.2:
		push_error("armored hit should deal 18, health %.2f" % after_hit)
		return false
	player.take_damage(25.0)
	if absf(player.health - after_hit) > 0.01:
		push_error("second hit landed during i-frames")
		return false
	var blinked := false
	var was_visible := player.player_mesh.visible
	for _i in 12:
		player._tick_hit_iframes(0.04)
		if player.player_mesh.visible != was_visible:
			blinked = true
			break
	if not blinked:
		push_error("i-frames should blink the player mesh")
		return false
	player._hit_iframes = 0.0
	player.inventory.armor_id = ""
	player.health = 100.0
	player.damage_source_hint = &"crystal_field"
	player.take_damage(10.0)
	player.damage_source_hint = &"crystal_field"
	player.take_damage(10.0)
	if absf(player.health - 80.0) > 0.2 or player._hit_iframes > 0.0:
		push_error("crystal field must ignore i-frames")
		return false

	var enemy := _CrystalEnemy.new()
	enemy.health = 40.0
	enemy.max_health = 40.0
	enemy.take_damage(6.0, &"spear")
	var locked := enemy.health
	enemy.take_damage(6.0, &"spear")
	if absf(enemy.health - locked) > 0.01 or locked >= 40.0:
		push_error("enemy hurt lock should block a second hit")
		return false
	print("OK armor reduction, i-frames, and enemy hurt lock")
	return true


func _knockback() -> bool:
	var world := _KnockWorld.new()
	var blocked := _EntityNavigation.knockback_step(Vector3(0, 0, 0), Vector3(1, 0, 0), 5.0, world, null, null)
	if blocked.distance_squared_to(Vector3.ZERO) > 0.01:
		push_error("knockback tunneled into a tall step")
		return false
	var moved := _EntityNavigation.knockback_step(Vector3(0, 0, 0), Vector3(1, 0, 0), 1.5, world, null, null)
	if moved.x < 1.0:
		push_error("knockback should cross flat ground")
		return false
	var enemy := _CrystalEnemy.new()
	enemy.apply_knockback(Vector3(1, 0, 0), 3.2 * 2.0)
	if enemy._knock_left < 6.0:
		push_error("hammer-sized shove was not stored")
		return false
	print("OK knockback respects a wall and stores the shove")
	return true


func _slice(src: String, start: String, end: String) -> String:
	var a := src.find(start)
	if a < 0:
		return ""
	var b := src.find(end, a + start.length())
	if b < 0:
		return src.substr(a)
	return src.substr(a, b - a)


func _touches_terrain(body: String) -> bool:
	return body.contains("try_dig") or body.contains("try_remove") or body.contains("set_voxel")
