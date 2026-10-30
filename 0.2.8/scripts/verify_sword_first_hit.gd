extends SceneTree

const _Gate = preload("res://player/action_resolve_gate.gd")
const _Items = preload("res://helpers/item_types.gd")
const _Aim = preload("res://player/action_targeting.gd")
const _WorldSettings = preload("res://config/world_settings.gd")
const _Input = preload("res://helpers/gameplay_input.gd")

const STEP := 1.0 / 60.0

var _failed := 0
var _saved_linger := PackedFloat32Array()
var _saved_recover := PackedFloat32Array()


class _Foe extends Node3D:
	var hits := 0
	var health := 80.0

	func is_combat_alive() -> bool:
		return health > 0.0

	func get_combat_center() -> Vector3:
		return global_position

	func get_combat_radius() -> float:
		return 0.45

	func take_damage(amount: float, _source: StringName = &"") -> void:
		if amount <= 0.0:
			return
		hits += 1
		health = maxf(health - amount, 0.0)


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	var feel := root.get_node_or_null("GameFeel")
	if feel == null or feel.config == null:
		_fail("GameFeel config missing")
		_finish(feel)
		return
	var index := int(feel.config.action_ids.find("sword_swing"))
	var row: Dictionary = feel.config.action("sword_swing")
	if index < 0 or row.is_empty():
		_fail("sword_swing missing from game feel config")
		_finish(feel)
		return
	_saved_linger = feel.config.linger_sec.duplicate()
	_saved_recover = feel.config.recovery_sec.duplicate()
	feel.config.linger_sec[index] = 0.40
	feel.config.recovery_sec[index] = 0.08
	_Input.world_loading = false
	_Input.pause_open = false
	_Input.modal_open = false
	_Input.map_open = false
	_Input.skill_tree_open = false
	_Input.dev_chat_open = false
	_Gate.reset()
	var player := _host()
	if player == null:
		_finish(feel)
		return
	var weapon := player.get_node("WeaponController") as WeaponController
	var first := _foe(player)
	_plant(player, first)
	if not _begin(weapon):
		_fail("sword swing did not start")
		player.free()
		_finish(feel)
		return
	if absf(weapon._tool_feel.linger_sec - float(feel.config.linger_sec[index])) > 0.001:
		_fail("sword linger %.3f did not follow game feel %.3f" % [weapon._tool_feel.linger_sec, float(feel.config.linger_sec[index])])
	if absf(weapon._tool_feel.recover_sec - float(feel.config.recovery_sec[index])) > 0.001:
		_fail("sword recovery %.3f did not follow game feel %.3f" % [weapon._tool_feel.recover_sec, float(feel.config.recovery_sec[index])])
	if not _until_live(weapon):
		_fail("sword swing never reached the live window")
		player.free()
		_finish(feel)
		return
	if first.hits != 1:
		_fail("first overlap dealt %d hits, want 1" % first.hits)
	var hold_frames := int(maxf(weapon._tool_feel.linger_sec - 0.14, 0.05) / STEP)
	for _i in hold_frames:
		weapon.advance_tool_feel(STEP)
	if first.hits != 1:
		_fail("same target took %d hits during one swing" % first.hits)
	if weapon._tool_feel.state != weapon._tool_feel.STATE_LIVE:
		_fail("swing ended before the config linger")
	var second := _foe(player)
	first.global_position = Vector3(800.0, 0.0, 800.0)
	_plant(player, second)
	for _i in 4:
		weapon.advance_tool_feel(STEP)
	if second.hits != 1:
		_fail("second target during the same swing took %d hits, want 1" % second.hits)
	if first.hits != 1:
		_fail("first target was hit again after leaving the arc (%d)" % first.hits)
	for _i in 2:
		weapon.advance_tool_feel(STEP)
	if second.hits != 1:
		_fail("second target took %d hits from later ticks of the same swing" % second.hits)
	if not _until_idle(weapon):
		_fail("sword swing did not finish")
	_plant(player, first)
	second.global_position = Vector3(-800.0, 0.0, -800.0)
	if not _begin(weapon):
		_fail("second swing did not start")
	elif not _until_live(weapon):
		_fail("second swing never went live")
	elif first.hits != 2:
		_fail("a new swing dealt hit %d on the first target, want 2" % first.hits)
	elif second.hits != 1:
		_fail("the new swing also hit the foe outside the arc (%d)" % second.hits)
	else:
		print("OK sword one hit per target per swing")
	player.free()
	_finish(feel)


func _finish(feel) -> void:
	if feel != null and feel.config != null and not _saved_linger.is_empty():
		feel.config.linger_sec = _saved_linger
		feel.config.recovery_sec = _saved_recover
	if _failed == 0:
		print("All sword first hit tests OK")
		quit(0)
	else:
		push_error("verify_sword_first_hit: %d failure(s)" % _failed)
		quit(1)


func _host() -> Player:
	var player := Player.new()
	player.set_process(false)
	player.set_physics_process(false)
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	root.add_child(player)
	var weapon := player.get_node_or_null("WeaponController") as WeaponController
	if weapon == null:
		_fail("weapon missing")
		player.free()
		return null
	weapon.set_process(false)
	weapon.set_physics_process(false)
	var ws = _WorldSettings.get_active()
	var col := Vector3(20.5, 8.0, 20.5)
	player.voxel_position = col
	player.global_position = Vector3(ws.column_to_world(col.x), col.y, ws.column_to_world(col.z))
	return player


func _foe(player: Player) -> _Foe:
	var foe := _Foe.new()
	foe.add_to_group("world_entity")
	player.get_parent().add_child(foe)
	return foe


func _plant(player: Player, foe: _Foe) -> void:
	var ws = _WorldSettings.get_active()
	var forward := _Aim.attack_forward(player)
	var origin := _Aim.attack_origin_world(player, 0.5)
	foe.global_position = origin + forward * (ws.voxel_scale * 0.8)


func _begin(weapon: WeaponController) -> bool:
	weapon._cooldown_timer = 0.0
	weapon._feel_item = "wooden_sword"
	weapon._feel_def = _Items.get_def("wooden_sword")
	weapon._swing_open = false
	weapon._swing_hit.clear()
	return weapon._tool_feel.try_begin(weapon, "sword_swing")


func _until_live(weapon: WeaponController) -> bool:
	var guard := 0
	while weapon._tool_feel.state == weapon._tool_feel.STATE_WIND and guard < 180:
		weapon.advance_tool_feel(STEP)
		guard += 1
	return weapon._tool_feel.state == weapon._tool_feel.STATE_LIVE


func _until_idle(weapon: WeaponController) -> bool:
	var guard := 0
	while weapon._tool_feel.state != weapon._tool_feel.STATE_IDLE and guard < 600:
		weapon.advance_tool_feel(STEP)
		guard += 1
	return weapon._tool_feel.state == weapon._tool_feel.STATE_IDLE
