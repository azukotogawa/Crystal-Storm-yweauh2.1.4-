extends SceneTree

const _Enemy = preload("res://entities/crystal_enemy.gd")
const _Brains = preload("res://entities/entity_brain_registry.gd")
const _Boss = preload("res://entities/boss_brain.gd")
const _Game = preload("res://game/game_manager.gd")
const _Settings = preload("res://systems/player_settings.gd")

const _MITE := 0.37
const _BOSS := 0.71
const _BURN := 0.53

var _failed: int = 0
var _saved: PackedFloat32Array = PackedFloat32Array()


class _Dummy extends Node3D:
	var hits: Array[float] = []
	var damage_source_hint: StringName = &""

	func take_damage(amount: float, _source: StringName = &"") -> void:
		hits.append(amount)


class _Pool extends RefCounted:
	var depth: float = 1.0

	func get_depth_at(_x: int, _z: int) -> float:
		return depth


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	var feel := root.get_node_or_null("GameFeel")
	if feel == null or feel.config == null:
		_fail("GameFeel config missing")
		_finish(feel)
		return
	_saved = feel.config.enemy_telegraph_sec.duplicate()
	for id in ["mite", "boss", "burn_pool"]:
		var row: Dictionary = feel.config.enemy(id)
		if row.is_empty() or float(row["telegraph_sec"]) <= 0.0:
			_fail("%s file telegraph is zero" % id)
	_set_wind(feel, "mite", _MITE)
	_set_wind(feel, "boss", _BOSS)
	_set_wind(feel, "burn_pool", _BURN)
	_Settings.flash_effects_enabled = true
	_Brains.ensure_builtins()
	_check_mite(feel)
	_check_boss_actions(feel)
	_check_warden_body()
	_check_warden_bite()
	_check_burn(feel)
	if not is_equal_approx(Engine.time_scale, 1.0) or paused:
		_fail("telegraph froze the tree")
	_finish(feel)


func _finish(feel) -> void:
	if feel != null and feel.config != null and not _saved.is_empty():
		feel.config.enemy_telegraph_sec = _saved.duplicate()
	if _failed == 0:
		print("All enemy telegraph tests OK")
		quit(0)
	else:
		push_error("verify_enemy_telegraph: %d failure(s)" % _failed)
		quit(1)


func _set_wind(feel, id: String, seconds: float) -> void:
	var index := int(feel.config.enemy_ids.find(id))
	if index < 0:
		_fail("%s missing from game feel config" % id)
		return
	feel.config.enemy_telegraph_sec[index] = seconds


func _stand(body: Node3D) -> _Dummy:
	var player := _Dummy.new()
	root.add_child(player)
	player.global_position = body.global_position
	return player


func _check_mite(_feel) -> void:
	var enemy := _Enemy.new()
	root.add_child(enemy)
	enemy.global_position = Vector3(8.0, 1.0, 8.0)
	enemy.setup(&"crystal_mite", null)
	var player := _stand(enemy)
	enemy._target = player
	var hp := enemy.health
	var dmg := enemy.contact_damage
	var cd := enemy.brain.config.attack_cooldown
	var cell := Vector2i.ZERO
	if not enemy._resolve_contact(0.05, true, cell, cell):
		pass
	if not player.hits.is_empty():
		_fail("mite damaged on the telegraph frame")
	if enemy._contact_left <= 0.0 or absf(enemy._contact_left - _MITE) > 0.001:
		_fail("mite wind %.3f, config %.3f" % [enemy._contact_left, _MITE])
	if enemy.locomotion_pose != "attack":
		_fail("mite wind-up pose missing")
	var marker := enemy.get_node_or_null("StrikeTelegraph")
	if marker == null or not marker.visible:
		_fail("mite ground marker hidden")
	if not _flashing(enemy):
		_fail("mite wind-up flash missing")
	while enemy._contact_left > 0.05:
		enemy._resolve_contact(0.05, true, cell, cell)
		if not player.hits.is_empty():
			_fail("mite damaged inside the telegraph")
			break
	if player.hits.is_empty():
		enemy._resolve_contact(enemy._contact_left, true, cell, cell)
	if player.hits.size() != 1 or not is_equal_approx(player.hits[0], dmg):
		_fail("mite hit %s, damage %.1f" % [player.hits, dmg])
	if not is_equal_approx(enemy.health, hp) or not is_equal_approx(enemy.contact_damage, dmg):
		_fail("mite health or damage changed")
	if not is_equal_approx(enemy.brain.config.attack_cooldown, cd):
		_fail("mite cooldown changed")
	var dodger := _Enemy.new()
	root.add_child(dodger)
	dodger.global_position = enemy.global_position
	dodger.setup(&"crystal_mite", null)
	dodger._target = player
	dodger._resolve_contact(0.05, true, cell, cell)
	while dodger._contact_left > 0.0:
		dodger._resolve_contact(minf(0.05, dodger._contact_left), false, cell, cell)
	if not player.hits.is_empty() and player.hits.size() != 1:
		_fail("mite hit a player who left the marker")
	enemy.free()
	dodger.free()
	player.free()


func _check_boss_actions(feel) -> void:
	_drive_boss(&"slam", 1.0, false)
	_drive_boss(&"charge", 10.0, false)
	_drive_boss(&"burst", 1.0, true)
	if absf(float(feel.enemy_telegraph("boss")) - _BOSS) > 0.001:
		_fail("boss telegraph was not the config row")


func _drive_boss(expect: String, dist: float, phase2: bool) -> void:
	var brain := _Boss.new()
	if phase2:
		brain.notify_hp_ratio(0.5)
	var consumed := 0.0
	var saw := false
	var impacted := false
	var act := ""
	for _i in 80:
		var prev := brain.windup
		var row: Dictionary = brain.tick(0.02, dist)
		act = str(row.get("action", act))
		if prev > 0.0:
			consumed += minf(0.02, prev)
		var telegraph := bool(row.get("telegraph", false)) and not bool(row.get("impact", false))
		if telegraph:
			saw = true
		if bool(row.get("impact", false)):
			impacted = true
			if not saw:
				_fail("%s impacted with no telegraph" % expect)
			if consumed + 0.001 < _BOSS:
				_fail("%s impact at %.3f before %.3f" % [expect, consumed, _BOSS])
			break
	if not impacted or act != expect:
		_fail("%s did not resolve (saw %s)" % [expect, act])
	elif absf(brain.telegraph_sec - _BOSS) > 0.001:
		_fail("%s used wind %.3f not config %.3f" % [expect, brain.telegraph_sec, _BOSS])


func _check_warden_body() -> void:
	var enemy := _Enemy.new()
	root.add_child(enemy)
	enemy.global_position = Vector3(4.0, 1.0, 4.0)
	enemy.setup(&"origin_warden", null)
	var player := _stand(enemy)
	enemy._target = player
	var dmg := enemy.contact_damage
	var hp := enemy.max_health
	var guard := 0
	while player.hits.is_empty() and guard < 80:
		enemy._tick_special(0.05)
		guard += 1
		if player.hits.is_empty() and enemy._special != null and enemy._special.windup > 0.0:
			var ring := enemy.get_node_or_null("TelegraphRing")
			if ring == null or not ring.visible:
				_fail("warden ring hidden during wind-up")
				break
			if enemy.locomotion_pose != "attack":
				_fail("warden wind-up pose missing")
				break
	if player.hits.size() != 1 or not is_equal_approx(player.hits[0], dmg):
		_fail("warden slam hit %s, contact %.1f" % [player.hits, dmg])
	if not is_equal_approx(enemy.max_health, hp):
		_fail("warden health changed")
	enemy.free()
	player.free()


func _check_warden_bite() -> void:
	var enemy := _Enemy.new()
	root.add_child(enemy)
	enemy.global_position = Vector3(6.0, 1.0, 6.0)
	enemy.setup(&"origin_warden", null)
	var player := _stand(enemy)
	enemy._target = player
	var dmg := enemy.contact_damage
	var cell := Vector2i.ZERO
	enemy._resolve_contact(0.05, true, cell, cell)
	if not player.hits.is_empty():
		_fail("warden bite landed on the telegraph frame")
	if absf(enemy._contact_left - _BOSS) > 0.001:
		_fail("warden bite wind %.3f, config %.3f" % [enemy._contact_left, _BOSS])
	var marker := enemy.get_node_or_null("StrikeTelegraph")
	if marker == null or not marker.visible or enemy.locomotion_pose != "attack":
		_fail("warden bite telegraph hidden")
	while enemy._contact_left > 0.0 and player.hits.is_empty():
		enemy._resolve_contact(minf(0.05, enemy._contact_left), true, cell, cell)
	if player.hits.size() != 1 or not is_equal_approx(player.hits[0], dmg):
		_fail("warden bite hit %s, contact %.1f" % [player.hits, dmg])
	enemy.free()
	player.free()


func _check_burn(feel) -> void:
	var gm := _Game.new()
	root.add_child(gm)
	var player := _Dummy.new()
	root.add_child(player)
	player.global_position = Vector3(2.0, 1.0, 2.0)
	gm._player = player
	gm._crystal = _Pool.new()
	gm.phase = _Game.Phase.ASSAULT
	var rate := gm.crystal_damage_per_second
	gm._apply_crystal_damage(0.05)
	if not player.hits.is_empty():
		_fail("burn pool damaged on the warning frame")
	if absf(gm._burn_left - _BURN) > 0.001:
		_fail("burn wind %.3f, config %.3f" % [gm._burn_left, _BURN])
	var glow := gm.get_node_or_null("BurnWarn")
	if glow == null or not glow.visible:
		_fail("burn warning glow hidden")
	while gm._burn_left > 0.05:
		gm._apply_crystal_damage(0.05)
		if not player.hits.is_empty():
			_fail("burn pool damaged inside the warning")
			break
	var step := gm._burn_left
	gm._apply_crystal_damage(step)
	var expect := rate * 1.0 * step
	if player.hits.size() != 1 or not is_equal_approx(player.hits[0], expect):
		_fail("burn hit %s, expected %.4f" % [player.hits, expect])
	if str(player.damage_source_hint) != "crystal_field":
		_fail("burn pool was tagged as a hit")
	if not is_equal_approx(gm.crystal_damage_per_second, rate):
		_fail("burn damage rate changed")
	if absf(float(feel.enemy_telegraph("burn_pool")) - _BURN) > 0.001:
		_fail("burn telegraph left the config")
	gm._crystal.depth = 0.0
	gm._apply_crystal_damage(0.05)
	if player.hits.size() != 1:
		_fail("burn kept ticking off the pool")
	if glow.visible:
		_fail("burn glow stayed after leaving the pool")
	gm.free()
	player.free()


func _flashing(node: Node) -> bool:
	if node is GeometryInstance3D:
		var amount = (node as GeometryInstance3D).get_instance_shader_parameter("flash_amount")
		if amount is float and float(amount) > 0.4:
			return true
	for child in node.get_children():
		if _flashing(child):
			return true
	return false
