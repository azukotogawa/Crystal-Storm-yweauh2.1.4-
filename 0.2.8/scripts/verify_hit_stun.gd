extends SceneTree

const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Settings = preload("res://config/world_settings.gd")
const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")

const DT := 1.0 / 60.0

var _failed := 0


class _ColumnPlayer extends Node3D:
	var voxel_position := Vector3.ZERO
	var hits := 0

	func get_voxel_position() -> Vector3:
		return voxel_position

	func set_damage_origin(_origin: Vector3) -> void:
		pass

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		hits += 1


class _WorldPlayer extends Node3D:
	var hits := 0

	func set_damage_origin(_origin: Vector3) -> void:
		pass

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		hits += 1


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	print("FAIL " + msg)


func _run() -> void:
	_check_config()
	_Brains.reset()
	_Brains.ensure_builtins()
	var holder := Node.new()
	root.add_child(holder)
	_check_crystal(holder)
	_check_world(holder)
	holder.free()
	if _failed == 0:
		print("All hit stun tests OK")
		quit(0)
	else:
		quit(1)


func _check_config() -> void:
	var live = GameFeelConfig.active()
	var settings: WorldSettings = _Settings.get_active()
	var vs: float = settings.voxel_scale
	if absf(float(live.hit_stun_min_sec) - 0.25) > 0.001 or absf(float(live.hit_stun_max_sec) - 0.40) > 0.001:
		_fail("shipped hit stun %.3f..%.3f want 0.25..0.40" % [live.hit_stun_min_sec, live.hit_stun_max_sec])
		return
	if absf(float(live.hit_stun_full_knock_voxels) - 3.0) > 0.001:
		_fail("full knock stun voxels %.2f want 3" % live.hit_stun_full_knock_voxels)
		return
	var weak := float(live.hit_stun_for_distance(0.05, vs))
	var full := float(live.hit_stun_for_distance(3.0 * vs, vs))
	var over := float(live.hit_stun_for_distance(12.0 * vs, vs))
	if weak >= full - 0.01:
		_fail("weak knock stun %.3f is not shorter than a full shove %.3f" % [weak, full])
	elif absf(full - 0.40) > 0.001 or absf(over - full) > 0.001:
		_fail("full shove stun %.3f over %.3f want 0.40" % [full, over])
	else:
		print("OK stun scales %.3f -> %.3f" % [weak, full])
	var tuned = GameFeelConfig.create_default()
	tuned.hit_stun_min_sec = 0.12
	tuned.hit_stun_max_sec = 0.66
	tuned.hit_stun_full_knock_voxels = 2.0
	var mid := float(tuned.hit_stun_for_distance(vs, vs))
	if absf(mid - 0.39) > 0.001:
		_fail("tuned half shove stun %.3f want 0.390" % mid)
	else:
		print("OK tuned half shove %.3f" % mid)


func _check_crystal(holder: Node) -> void:
	var player := _ColumnPlayer.new()
	player.name = "Player"
	holder.add_child(player)
	var ws: WorldSettings = _Settings.get_active()
	var y: float = ws.layer_height()
	var home := Vector2i(30, 30)
	player.voxel_position = Vector3(float(home.x) + 0.5, y, float(home.y) + 0.5)
	var guard := _CrystalEnemy.new()
	guard.set_physics_process(false)
	holder.add_child(guard)
	guard.global_position = _at(home, y)
	guard.setup(&"shard_guard", player)
	guard.global_position = _at(home, y)
	guard.lifetime = 0.0
	if not _window(guard, player, Vector3(-1, 0, 0), 0.3, true):
		player.free()
		guard.free()
		return
	print("OK crystal stun blocks the hit and then lands")
	var chase := _CrystalEnemy.new()
	chase.set_physics_process(false)
	holder.add_child(chase)
	var origin := Vector2i(40, 40)
	chase.global_position = _at(origin, y)
	player.voxel_position = Vector3(float(origin.x) + 3.5, y, float(origin.y) + 0.5)
	chase.setup(&"shard_guard", player)
	chase.global_position = _at(origin, y)
	chase.lifetime = 0.0
	if _steers_after(chase, _at(Vector2i(origin.x + 3, origin.y), y), Vector3(-1, 0, 0)):
		print("OK crystal stun blocks steering and then chases")
	player.free()
	guard.free()
	chase.free()


func _check_world(holder: Node) -> void:
	var player := _WorldPlayer.new()
	player.name = "Player"
	player.add_to_group("player")
	holder.add_child(player)
	var ws: WorldSettings = _Settings.get_active()
	var y: float = ws.layer_height()
	var cfg = _Brains.get_def(&"ambush")
	var home := Vector2i(50, 50)
	var bandit := _WorldEntity.new()
	bandit.set_physics_process(false)
	holder.add_child(bandit)
	bandit.setup(cfg, home, null, null, null)
	player.global_position = bandit.global_position
	if not _window(bandit, player, Vector3(-1, 0, 0), 0.3, false):
		player.free()
		bandit.free()
		return
	print("OK world stun blocks the hit and then lands")
	var chaser := _WorldEntity.new()
	chaser.set_physics_process(false)
	holder.add_child(chaser)
	var origin := Vector2i(60, 60)
	chaser.setup(cfg, origin, null, null, null)
	player.global_position = _at(Vector2i(origin.x + 3, origin.y), y)
	if _steers_after(chaser, player.global_position, Vector3(-1, 0, 0)):
		print("OK world stun blocks steering and then chases")
	player.free()
	bandit.free()
	chaser.free()


func _window(body: Node3D, player: Node, dir: Vector3, distance: float, crystal: bool) -> bool:
	body.set("_knock_left", 0.0)
	body.set("_stagger_left", 0.0)
	var brain = body.get("brain")
	brain.attack_timer = 0.0
	var state0 := int(brain.state)
	var timer0 := float(brain.attack_timer)
	var target0: Vector2i = brain.target_cell
	body.apply_knockback(dir, distance)
	var stun := float(body.get("_stagger_left"))
	var want := float(GameFeelConfig.active().hit_stun_for_distance(distance, _Settings.get_active().voxel_scale))
	if absf(stun - want) > 0.001:
		_fail("stored stun %.3f want %.3f" % [stun, want])
		return false
	var hits0 := int(player.hits)
	var guarded := 0
	while float(body.get("_knock_left")) > 0.0 or float(body.get("_stagger_left")) > 0.0:
		var before := _xz(body.global_position)
		var gap := before.distance_to(_xz(_aim(player, crystal)))
		body._physics_process(DT)
		guarded += 1
		if int(player.hits) != hits0:
			_fail("hit landed during stun")
			return false
		if crystal and float(body.get("_contact_left")) > 0.0:
			_fail("attack windup started during stun")
			return false
		if int(brain.state) != state0 or absf(float(brain.attack_timer) - timer0) > 0.0001:
			_fail("brain steered during stun")
			return false
		if brain.target_cell != target0:
			_fail("steering target changed during stun")
			return false
		var next_gap := _xz(body.global_position).distance_to(_xz(_aim(player, crystal)))
		if next_gap + 0.02 < gap:
			_fail("closed on the player during stun")
			return false
		if guarded > 600:
			_fail("stun did not end")
			return false
	if float(guarded) * DT + 0.001 < stun:
		_fail("stun window %.3f shorter than %.3f" % [float(guarded) * DT, stun])
		return false
	body._physics_process(DT)
	var attacked := int(player.hits) > hits0
	if crystal:
		attacked = attacked or float(body.get("_contact_left")) > 0.0
	if not attacked:
		_fail("stun ended and the enemy still did not attack")
		return false
	if float(body.get("_stagger_left")) > 0.0 or float(body.get("_knock_left")) > 0.0:
		_fail("attack resumed while stun was still up")
		return false
	print("OK stun window %.3f s (%d frames) then attack" % [float(guarded) * DT, guarded])
	return true


func _steers_after(body: Node3D, player_world: Vector3, dir: Vector3) -> bool:
	body.set("_knock_left", 0.0)
	body.set("_stagger_left", 0.0)
	var brain = body.get("brain")
	var state0 := int(brain.state)
	var target0: Vector2i = brain.target_cell
	body.apply_knockback(dir, 0.4)
	var start_gap := _xz(body.global_position).distance_to(_xz(player_world))
	var guarded := 0
	while float(body.get("_knock_left")) > 0.0 or float(body.get("_stagger_left")) > 0.0:
		var gap := _xz(body.global_position).distance_to(_xz(player_world))
		body._physics_process(DT)
		guarded += 1
		if int(brain.state) != state0 or brain.target_cell != target0:
			_fail("chase target changed during stun")
			return false
		var next_gap := _xz(body.global_position).distance_to(_xz(player_world))
		if next_gap + 0.02 < gap:
			_fail("steered toward the player during stun")
			return false
		if guarded > 600:
			_fail("chase stun did not end")
			return false
	var idle_gap := _xz(body.global_position).distance_to(_xz(player_world))
	if idle_gap + 0.05 < start_gap:
		_fail("already closed before the stun ended")
		return false
	var closed := false
	for _i in 90:
		body._physics_process(DT)
		if _xz(body.global_position).distance_to(_xz(player_world)) + 0.35 < idle_gap:
			closed = true
			break
	if not closed:
		_fail("stun ended and the enemy did not steer (gap %.2f)" % _xz(body.global_position).distance_to(_xz(player_world)))
		return false
	return true


func _at(cell: Vector2i, y: float) -> Vector3:
	var ws = _Settings.get_active()
	return Vector3(ws.column_to_world(float(cell.x) + 0.5), y, ws.column_to_world(float(cell.y) + 0.5))


func _aim(player: Node, crystal: bool) -> Vector3:
	if crystal and player.has_method("get_voxel_position"):
		var v: Vector3 = player.get_voxel_position()
		var ws = _Settings.get_active()
		return Vector3(ws.column_to_world(v.x), v.y, ws.column_to_world(v.z))
	return player.global_position


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
