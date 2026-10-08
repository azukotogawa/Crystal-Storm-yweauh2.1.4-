class_name Juice
extends RefCounted
## Hit-stop, screen shake, hit flash, and walk-bob distances.
## Gameplay hit-stop and shake no-op when DisplayServer.get_name() == "headless"
## (Godot 4.7 --headless does not set the "headless" feature) so probe timers stay in sync.
## verify_juice passes force=true to run the dip anyway. The player settings still gate it.

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _FLASH_SHADER := "res://shaders/entity_hit_flash.gdshader"

static var bob_columns: float = 22.0
static var _amp: float = 0.0
static var _hit_token: int = 0
static var _hit_active: bool = false
static var _saved_scale: float = 1.0
static var _dipped: float = 1.0
static var _flash_mat: ShaderMaterial
static var _cam: Camera3D
static var _cam_check_msec: int = -100000


static func set_preset(preset: int) -> void:
	# LOW keeps bob only for creatures near the player. SAFE skips creature bob.
	match preset:
		0:
			bob_columns = 8.0
		2:
			bob_columns = 36.0
		3:
			bob_columns = 0.0
		_:
			bob_columns = 22.0


static func seconds_for_weight(weight: float) -> float:
	return lerpf(0.04, 0.08, clampf(weight, 0.0, 1.0))


static func weight_for_item(item_id: String, damage: float) -> float:
	match item_id:
		"crystal_hammer", "crystal_bomb":
			return 1.0
		"spear":
			return 0.45
		_:
			if damage >= 18.0:
				return 1.0
			return 0.0


## Dip Engine.time_scale, then restore the previous scale on a real-time timer.
## The setting always gates this. `force` only skips the headless no-op so
## verify_juice can dip and restore. A scale that is already off 1 (relic modal
## uses 0.05) is left alone unless a hit-stop this call owns is already active.
static func request_hit_stop(seconds: float, tree: SceneTree, force: bool = false) -> bool:
	if tree == null:
		return false
	if _PlayerSettings.reduce_motion or not _PlayerSettings.hit_stop_enabled:
		return false
	if not force and DisplayServer.get_name() == "headless":
		return false
	var dur := clampf(seconds, 0.04, 0.08)
	if not _hit_active:
		if absf(Engine.time_scale - 1.0) > 0.02:
			return false
		_saved_scale = Engine.time_scale
	_hit_token += 1
	var token := _hit_token
	_hit_active = true
	_dipped = 0.02
	Engine.time_scale = _dipped
	var timer := tree.create_timer(dur, true, false, true)
	timer.timeout.connect(func() -> void:
		_end_hit_stop(token)
	)
	return true


static func _end_hit_stop(token: int) -> void:
	if token != _hit_token:
		return
	_hit_active = false
	if absf(Engine.time_scale - _dipped) <= 0.008:
		Engine.time_scale = _saved_scale


## End a live hit-stop now. The pending timer becomes a no-op.
## Returns the pre-dip scale when a stop was active, otherwise the current scale.
static func cancel_hit_stop() -> float:
	if not _hit_active:
		return Engine.time_scale
	var base := _saved_scale
	_hit_token += 1
	_hit_active = false
	if absf(Engine.time_scale - _dipped) <= 0.008:
		Engine.time_scale = base
	return base


static func request_shake(amount: float, force: bool = false) -> void:
	if amount <= 0.0:
		return
	if _PlayerSettings.reduce_motion or not _PlayerSettings.screen_shake_enabled:
		return
	if not force and DisplayServer.get_name() == "headless":
		return
	_amp = maxf(_amp, amount)


static func shake_offset(delta: float) -> Vector3:
	if _PlayerSettings.reduce_motion or not _PlayerSettings.screen_shake_enabled or _amp <= 0.0001:
		_amp = 0.0
		return Vector3.ZERO
	_amp *= exp(-maxf(delta, 0.0) * 16.0)
	if _amp < 0.004:
		_amp = 0.0
		return Vector3.ZERO
	var t := float(Time.get_ticks_msec()) * 0.031
	return Vector3(sin(t * 1.7) * _amp, cos(t * 2.3) * _amp * 0.45, sin(t * 1.1) * _amp * 0.25)


static func clear_shake() -> void:
	_amp = 0.0


static func walk_bob_allowed() -> bool:
	return not _PlayerSettings.reduce_motion


static func creature_bob_allowed(body: Node3D, player: Node3D) -> bool:
	if _PlayerSettings.reduce_motion:
		return false
	if bob_columns <= 0.0 or body == null or player == null or not is_instance_valid(player):
		return false
	var limit := bob_columns * 2.0
	if body.global_position.distance_squared_to(player.global_position) > limit * limit:
		return false
	var cam := _camera(body)
	if cam != null and not cam.is_position_in_frustum(body.global_position):
		return false
	return true


static func _camera(body: Node3D) -> Camera3D:
	if is_instance_valid(_cam):
		return _cam
	var now := Time.get_ticks_msec()
	if now - _cam_check_msec < 1000:
		return null
	_cam_check_msec = now
	var tree := body.get_tree()
	if tree == null:
		return null
	_cam = tree.get_first_node_in_group("camera") as Camera3D
	return _cam


static func flash_material() -> ShaderMaterial:
	if _flash_mat != null:
		return _flash_mat
	var shader := load(_FLASH_SHADER) as Shader
	if shader == null:
		return null
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = shader
	return _flash_mat


## White flash via one shared overlay shader. No material is allocated per hit.
static func set_flash(node: Node, amount: float) -> void:
	if node == null or not is_instance_valid(node):
		return
	var shown := amount
	if not _PlayerSettings.flash_effects_enabled:
		shown = 0.0
	if node is GeometryInstance3D:
		_flash_one(node as GeometryInstance3D, shown)
	for child in node.get_children():
		if child is GeometryInstance3D:
			_flash_one(child as GeometryInstance3D, shown)


static func _flash_one(gi: GeometryInstance3D, amount: float) -> void:
	var mat := flash_material()
	# Drop the overlay once the flash is gone so hit enemies do not keep an extra pass.
	if amount > 0.02:
		if mat != null and gi.material_overlay != mat:
			gi.material_overlay = mat
	elif mat != null and gi.material_overlay == mat:
		gi.material_overlay = null
	gi.set_instance_shader_parameter("flash_amount", amount)
	var override := gi.material_override
	if not (override is StandardMaterial3D):
		return
	var sm := override as StandardMaterial3D
	if not gi.has_meta(&"juice_em0"):
		gi.set_meta(&"juice_em0", sm.emission_energy_multiplier)
		gi.set_meta(&"juice_em_on", sm.emission_enabled)
		gi.set_meta(&"juice_em_col", sm.emission)
	if amount > 0.02:
		sm.emission_enabled = true
		sm.emission = Color.WHITE
		sm.emission_energy_multiplier = 2.6
	else:
		sm.emission_enabled = bool(gi.get_meta(&"juice_em_on"))
		sm.emission = gi.get_meta(&"juice_em_col")
		sm.emission_energy_multiplier = float(gi.get_meta(&"juice_em0"))
