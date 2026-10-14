extends SceneTree
## Creatures must idle, walk, and attack from the physics step, on the boxes
## the window draws. _apply_walk_bob only scales the visual parent, and only
## when Juice.creature_bob_allowed is true, so a child-box read stays a statue.
## Attack also misses a player who is actually beside them: the branch runs
## column_pos on a voxel_position that is already in columns, then compares
## the creature's world position to those column numbers.
## This check stands a rabbit and a mite on that real player position and
## ticks _physics_process. It does not call a pose setter.
## Usage: godot --headless --path 0.2.8 -s res://scripts/verify_creature_locomotion.gd

const _Registry = preload("res://systems/game_visual_registry.gd")
const _WorldEntity = preload("res://entities/world_entity.gd")
const _CrystalEnemy = preload("res://entities/crystal_enemy.gd")
const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Settings = preload("res://config/world_settings.gd")

const DT := 1.0 / 60.0

var _failed: int = 0


class _Player extends Node3D:
	var voxel_position := Vector3.ZERO
	var hits: int = 0

	func get_voxel_position() -> Vector3:
		return voxel_position

	func set_damage_origin(_origin: Vector3) -> void:
		pass

	func take_damage(_amount: float, _source: StringName = &"") -> void:
		hits += 1


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	_Brains.reset()
	_Brains.ensure_builtins()
	var holder := Node.new()
	root.add_child(holder)
	var registry := _Registry.new()
	registry.entity_voxel_models_enabled = true
	registry.entity_sprites_enabled = false
	holder.add_child(registry)
	var player := _Player.new()
	player.name = "Player"
	player.add_to_group("player")
	holder.add_child(player)

	var ws = _Settings.get_active()
	var home := Vector2i(12, 9)
	player.voxel_position = Vector3(80.5, 4.0, 80.5)
	player.global_position = Vector3(ws.column_to_world(80.5), 4.0, ws.column_to_world(80.5))

	var rabbit := _spawn_animal(holder, &"rabbit", home)
	var prop := _prop(rabbit)
	if prop == null:
		_fail("rabbit has no voxel prop")
	else:
		var rest := _corners(prop)
		_tick(rabbit, 36)
		var idle := _corners(prop)
		var idle_shift := _max_delta(rest, idle)
		var idle_pose := str(rabbit.get("locomotion_pose"))
		if idle_pose != "idle":
			_fail("standing rabbit reported %s, want idle" % idle_pose)
		elif idle_shift < 0.12:
			_fail("idle moved a box only %.3f m. Parent scale is not a breath." % idle_shift)
		elif prop.scale.distance_to(Vector3.ONE) > 0.04:
			_fail("idle scaled the whole prop %s" % prop.scale)
		else:
			print("OK idle shift %.3f pose %s" % [idle_shift, idle_pose])

		var start := rabbit.global_position
		var walked := 0.0
		var walk_shift := 0.0
		var walk_pose := ""
		for _i in 160:
			_tick(rabbit, 1)
			walked = rabbit.global_position.distance_to(start)
			walk_shift = maxf(walk_shift, _max_delta(idle, _corners(prop)))
			walk_pose = str(rabbit.get("locomotion_pose"))
			if walked > 1.2 and walk_pose == "walk" and walk_shift >= 0.45:
				break
		if walked < 1.2:
			_fail("rabbit brain did not walk (%.2f m)" % walked)
		elif walk_pose != "walk":
			_fail("moving rabbit stayed on pose %s" % walk_pose)
		elif walk_shift < 0.45:
			_fail("walk moved a box only %.3f m. The step is still a parent bob." % walk_shift)
		elif prop.scale.distance_to(Vector3.ONE) > 0.04:
			_fail("walk scaled the whole prop %s" % prop.scale)
		else:
			print("OK walk %.2f m box %.3f pose %s" % [walked, walk_shift, walk_pose])

	# A herbivore beside the player must not play an attack.
	player.voxel_position = Vector3(float(home.x) + 0.5, rabbit.global_position.y, float(home.y) + 0.5)
	player.global_position = Vector3(
		ws.column_to_world(player.voxel_position.x),
		rabbit.global_position.y,
		ws.column_to_world(player.voxel_position.z)
	)
	_tick(rabbit, 8)
	if str(rabbit.get("locomotion_pose")) == "attack":
		_fail("rabbit played an attack")
	else:
		print("OK rabbit has no attack")

	var mite := _spawn_animal(holder, &"crystal_mite", home)
	player.voxel_position = Vector3(float(home.x) + 0.5, mite.global_position.y, float(home.y) + 0.5)
	player.global_position = Vector3(
		ws.column_to_world(player.voxel_position.x),
		mite.global_position.y,
		ws.column_to_world(player.voxel_position.z)
	)
	var mite_prop := _prop(mite)
	if mite_prop == null:
		_fail("mite has no voxel prop")
	else:
		var before := _corners(mite_prop)
		var saw := false
		var lunged := 0.0
		for _j in 8:
			_tick(mite, 1)
			if str(mite.get("locomotion_pose")) == "attack":
				saw = true
				lunged = maxf(lunged, _max_delta(before, _corners(mite_prop)))
		if not saw:
			_fail("mite beside the player never posed attack (hits %d)" % player.hits)
		elif lunged < 0.40:
			_fail("attack moved a box only %.3f m" % lunged)
		else:
			print("OK mite attack lunge %.3f hits %d" % [lunged, player.hits])

	var enemy := _CrystalEnemy.new()
	enemy.enemy_id = &"shard_guard"
	holder.add_child(enemy)
	var guard_cell := Vector2i(14, 9)
	enemy.global_position = Vector3(
		ws.column_to_world(float(guard_cell.x) + 0.5),
		mite.global_position.y,
		ws.column_to_world(float(guard_cell.y) + 0.5)
	)
	player.voxel_position = Vector3(float(guard_cell.x) + 0.5, enemy.global_position.y, float(guard_cell.y) + 0.5)
	player.global_position = Vector3(
		ws.column_to_world(player.voxel_position.x),
		enemy.global_position.y,
		ws.column_to_world(player.voxel_position.z)
	)
	enemy.set_physics_process(false)
	enemy.setup(&"shard_guard", player)
	var guard_prop := _prop(enemy)
	if guard_prop == null:
		_fail("shard guard has no voxel prop")
	else:
		var before_g := _corners(guard_prop)
		var saw_g := false
		var lunged_g := 0.0
		for _k in 8:
			enemy._physics_process(DT)
			if str(enemy.get("locomotion_pose")) == "attack":
				saw_g = true
				lunged_g = maxf(lunged_g, _max_delta(before_g, _corners(guard_prop)))
		if not saw_g:
			_fail("shard guard beside the player never posed attack")
		elif lunged_g < 0.40:
			_fail("guard attack moved a box only %.3f m" % lunged_g)
		else:
			print("OK guard attack lunge %.3f" % lunged_g)

	holder.free()
	if _failed == 0:
		print("All creature locomotion tests OK")
		quit(0)
	else:
		push_error("verify_creature_locomotion: %d failure(s)" % _failed)
		quit(1)


func _spawn_animal(holder: Node, id: StringName, cell: Vector2i) -> WorldEntity:
	var cfg = _Brains.get_def(id)
	var entity := _WorldEntity.new()
	holder.add_child(entity)
	entity.set_physics_process(false)
	entity.setup(cfg, cell, null, null, null)
	return entity


func _tick(entity: WorldEntity, frames: int) -> void:
	for _i in frames:
		entity._physics_process(DT)


func _prop(body: Node) -> Node3D:
	var prop := body.get_node_or_null("VoxelProp") as Node3D
	if prop == null or not prop.visible:
		return null
	return prop


func _corners(root: Node3D) -> Dictionary:
	var out := {}
	for child in root.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		var mesh := mi.mesh as BoxMesh
		var half := mesh.size * 0.5 if mesh else Vector3(0.2, 0.2, 0.2)
		var corner: Vector3 = mi.transform * Vector3(half.x, -half.y, half.z)
		out[str(mi.name)] = corner
	return out


func _max_delta(before: Dictionary, after: Dictionary) -> float:
	var best := 0.0
	for key in before.keys():
		if not after.has(key):
			continue
		best = maxf(best, (before[key] as Vector3).distance_to(after[key]))
	return best
