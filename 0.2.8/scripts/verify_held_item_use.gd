extends SceneTree
## Use poses have to play when attack is pressed, on the mesh the window draws.
## verify_item_animations called HeldItemView.apply_playback and measured the
## grip position. A sword that only slides, a bow whose string stays put, and
## a pick that never chops all passed. This check selects the hotbar slot and
## presses attack through WeaponController._process.
## Hammer impact stays 0.62 of the 1.1 s swing: the hit is not allowed early.
## Usage: godot --path 0.2.8 -s res://scripts/verify_held_item_use.gd

const _GameplayInput = preload("res://helpers/gameplay_input.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

const STEP := 1.0 / 60.0

var _failed: int = 0
var _clock_t: float = 0.0
var _hit_at: float = -1.0
var _raised_y: float = 0.0
var _raised_ang: float = 0.0
var _saw_ratio: float = -1.0
var _saw_duration: float = -1.0


class _Host extends Player:
	func _ready() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)
	print("FAIL " + msg)


func _run() -> void:
	_GameplayInput.world_loading = false
	_GameplayInput.pause_open = false
	_GameplayInput.map_open = false
	_GameplayInput.dev_chat_open = false
	var ws = _WorldSettings.get_active()
	var vs: float = ws.voxel_scale
	var player := _Host.new()
	player.name = "Player"
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	player.set_process(false)
	player.set_physics_process(false)
	var inv := Inventory.new()
	var items: Array[String] = ["wooden_sword", "stone_pick", "crystal_hammer", "shortbow"]
	for i in items.size():
		inv.set_slot(i, items[i], 1)
	player.inventory = inv
	player.voxel_position = Vector3(20.5, 8.0, 20.5)
	root.add_child(player)
	player.global_position = Vector3(ws.column_to_world(20.5), 8.0, ws.column_to_world(20.5))
	var weapon := WeaponController.new()
	weapon.name = "WeaponController"
	weapon.set_process(false)
	player.add_child(weapon)
	await process_frame
	await process_frame
	var view := player.get_node_or_null("HeldItemView") as Node3D
	if view == null:
		_fail("WeaponController did not attach HeldItemView")
		_finish()
		return
	await _check_sword(weapon, view)
	await _check_pick(weapon, view)
	await _check_hammer(weapon, view, vs)
	await _check_bow(weapon, view, vs)
	_finish()


## action_press stays just_pressed until the engine ticks a frame.
## A loop of WeaponController._process never clears it, so the next item
## would swing on its own. One idle frame is the real click.
func _idle_input() -> void:
	Input.action_release("attack")
	await process_frame


func _select(weapon: WeaponController, index: int) -> void:
	await _idle_input()
	weapon._cancel_pending_strike()
	weapon._cooldown_timer = 0.0
	weapon.set_active_hotbar_index(index)
	weapon._process(STEP)


func _press_attack(weapon: WeaponController, seconds: float, on_step: Callable = Callable()) -> void:
	await _idle_input()
	Input.action_press("attack")
	_clock_t = STEP
	weapon._process(STEP)
	if on_step.is_valid():
		on_step.call(STEP)
	await process_frame
	Input.action_release("attack")
	await process_frame
	var t := STEP
	while t < seconds - 0.0001:
		t += STEP
		_clock_t = t
		weapon._process(STEP)
		if on_step.is_valid():
			on_step.call(t)


func _angle(a: Basis, b: Basis) -> float:
	return a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion())


func _check_sword(weapon: WeaponController, view: Node3D) -> void:
	await _select(weapon, 0)
	var held := view.get_node_or_null("HeldItem") as Node3D
	if held == null:
		_fail("sword has no HeldItem on the attack path")
		return
	var ready := held.transform.basis
	await _press_attack(weapon, 0.22)
	var swung := _angle(ready, held.transform.basis)
	if swung < 0.7:
		_fail("sword mesh did not swing on attack (rotation %.2f rad). The old check moved the grip with apply_playback and never pressed attack." % swung)
	else:
		print("OK sword swing on attack %.2f rad" % swung)


func _check_pick(weapon: WeaponController, view: Node3D) -> void:
	await _select(weapon, 1)
	var held := view.get_node_or_null("HeldItem") as Node3D
	if held == null:
		_fail("pick has no HeldItem on the attack path")
		return
	var ready := held.transform.basis
	# Impact is 0.45 of the 0.26 s dig. Sample on that chop, not after it recovers.
	await _press_attack(weapon, 0.13)
	var chopped := _angle(ready, held.transform.basis)
	if chopped < 0.7:
		_fail("pick mesh did not chop on attack (rotation %.2f rad)" % chopped)
	else:
		print("OK pick dig on attack %.2f rad" % chopped)


func _check_hammer(weapon: WeaponController, view: Node3D, vs: float) -> void:
	await _select(weapon, 2)
	var held := view.get_node_or_null("HeldItem") as Node3D
	if held == null:
		_fail("hammer has no HeldItem on the attack path")
		return
	var spec_ratio := 0.62
	var spec_dur := 1.1
	var ready_y: float = held.position.y
	var ready := held.transform.basis
	_hit_at = -1.0
	_raised_y = ready_y
	_raised_ang = 0.0
	_saw_ratio = -1.0
	_saw_duration = -1.0
	if not weapon.attacked.is_connected(_note_hammer_hit):
		weapon.attacked.connect(_note_hammer_hit)
	await _press_attack(weapon, 0.85, func(t: float) -> void:
		if weapon._playback != null and _saw_ratio < 0.0:
			_saw_ratio = float(weapon._playback.impact_ratio)
			_saw_duration = float(weapon._playback.duration)
		if t >= 0.30 and t <= 0.50:
			_raised_y = held.position.y
			_raised_ang = _angle(ready, held.transform.basis)
	)
	var impact := spec_dur * spec_ratio
	if _saw_ratio >= 0.0 and not is_equal_approx(_saw_ratio, spec_ratio):
		_fail("hammer impact_ratio moved off 0.62")
	elif _saw_duration >= 0.0 and not is_equal_approx(_saw_duration, spec_dur):
		_fail("hammer duration moved off 1.1")
	elif _raised_y < ready_y + vs * 0.7:
		_fail("hammer did not wind up before the hit (y %.2f ready %.2f)" % [_raised_y, ready_y])
	elif _raised_ang < 0.5:
		_fail("hammer head did not rise during the wind-up (rotation %.2f rad)" % _raised_ang)
	elif _hit_at < 0.0:
		_fail("hammer attack never landed")
	elif _hit_at < impact - STEP:
		_fail("hammer hit at %.3f s, before the 0.62 s wind-up" % _hit_at)
	elif held.position.y > _raised_y - vs * 0.5:
		_fail("hammer did not come down after the wind-up")
	else:
		print("OK hammer wind-up hit at %.3f s (impact %.3f)" % [_hit_at, impact])


func _note_hammer_hit(_id: String, _pos: Vector3) -> void:
	if _hit_at < 0.0:
		_hit_at = _clock_t


func _bow_string(held: Node3D) -> Node3D:
	var best: Node3D = null
	var best_h := 0.0
	for child in held.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := mi.mesh as BoxMesh
		if box == null:
			continue
		if box.size.y > best_h and box.size.x < box.size.y * 0.25:
			best = mi
			best_h = box.size.y
	return best


func _check_bow(weapon: WeaponController, view: Node3D, vs: float) -> void:
	await _select(weapon, 3)
	var held := view.get_node_or_null("HeldItem") as Node3D
	if held == null:
		_fail("bow has no HeldItem on the attack path")
		return
	var string := _bow_string(held)
	if string == null:
		_fail("bow has no string mesh")
		return
	var ready_z: float = string.position.z
	# Release is 0.70 of 0.8 s. Sample the draw before the shot recovers.
	await _press_attack(weapon, 0.50)
	var pulled: float = string.position.z - ready_z
	if pulled < vs * 0.35:
		_fail("bow string did not draw on attack (local z %+.2f). Sliding the whole bow still passed the grip check." % pulled)
	else:
		print("OK bow draw on attack %+.2f" % pulled)


func _finish() -> void:
	if _failed == 0:
		print("All held item use tests OK")
		quit(0)
	else:
		quit(1)
