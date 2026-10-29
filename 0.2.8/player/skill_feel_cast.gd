class_name SkillFeelCast
extends RefCounted

const _Config = preload("res://config/game_feel_config.gd")
const _Gate = preload("res://player/action_resolve_gate.gd")
const _Settings = preload("res://systems/player_settings.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const STATE_IDLE := 0
const STATE_WIND := 1
const STATE_LIVE := 2

const SKILL_IDS: Array[String] = ["dash", "ground_slam", "crystal_pulse", "quick_wall"]

var state := STATE_IDLE
var skill_id := ""
var slot := -1
var wind_sec := 0.0
var linger_sec := 0.0
var recover_sec := 0.0
var wind_left := 0.0
var linger_left := 0.0
var recover_left := 0.0
var wish := Vector2.ZERO
var facing := Vector2.ZERO
var landed := false

var _marker: MeshInstance3D
var _sparks: CPUParticles3D
var _tint := Color(1, 1, 1, 0.6)


func pacing_blocks() -> bool:
	return state == STATE_WIND or recover_left > 0.0


func accepts() -> bool:
	if pacing_blocks():
		return false
	return not _Gate.blocked(self)


func busy() -> bool:
	return state != STATE_IDLE


func known(id: String) -> bool:
	return SKILL_IDS.has(id)


func begin(player: Node, slot_i: int, id: String, wish_xz: Vector2, face: Vector2) -> bool:
	if not accepts() or not known(id):
		return false
	var row: Dictionary = _row(player, id)
	if row.is_empty():
		return false
	if not _Gate.claim(self, id):
		return false
	_clear_visuals()
	state = STATE_WIND
	skill_id = id
	slot = slot_i
	wish = wish_xz
	facing = face
	landed = false
	wind_sec = _Gate.wind_for(id, float(row["telegraph_sec"]))
	linger_sec = float(row["linger_sec"])
	recover_sec = float(row["recovery_sec"])
	wind_left = wind_sec
	linger_left = 0.0
	recover_left = 0.0
	_tint = _color(id)
	_show_marker(player, 0.12)
	return true


func advance(player: Node, delta: float) -> void:
	var step := delta
	if step < 0.0:
		step = 0.0
	if state == STATE_WIND:
		if _GameplayInput.blocks_world():
			_abort(player)
			return
		wind_left = maxf(wind_left - step, 0.0)
		var span := wind_sec if wind_sec > 0.0001 else 1.0
		_show_marker(player, 1.0 - (wind_left / span))
		if wind_left <= 0.0:
			_land(player)
		return
	if state != STATE_LIVE:
		return
	if recover_left > 0.0:
		recover_left = maxf(recover_left - step, 0.0)
	if linger_left > 0.0:
		linger_left = maxf(linger_left - step, 0.0)
		_fade_linger()
	if linger_left <= 0.0 and recover_left <= 0.0:
		_clear_visuals()
		state = STATE_IDLE
		skill_id = ""


func _land(player: Node) -> void:
	state = STATE_LIVE
	wind_left = 0.0
	landed = false
	_Gate.mark(skill_id)
	if player.has_method("resolve_skill_feel"):
		landed = bool(player.resolve_skill_feel(skill_id, wish, facing))
	if landed:
		_impact(player)
		linger_left = linger_sec
		_burst(player)
	else:
		linger_left = 0.0
		_clear_visuals()
	recover_left = recover_sec


func _abort(player: Node) -> void:
	if player.has_method("release_skill_slot"):
		player.release_skill_slot(slot)
	_clear_visuals()
	state = STATE_IDLE
	skill_id = ""
	wind_left = 0.0
	linger_left = 0.0
	recover_left = 0.0
	landed = false


func _row(player: Node, id: String) -> Dictionary:
	var feel = _feel(player)
	if feel != null and "config" in feel and feel.config != null and feel.config.has_method("action"):
		return feel.config.action(id)
	if ResourceLoader.exists("res://config/default_game_feel.tres"):
		var loaded = load("res://config/default_game_feel.tres")
		if loaded != null and loaded.has_method("action"):
			return loaded.action(id)
	return _Config.create_default().action(id)


func _feel(player: Node):
	var tree: SceneTree = null
	if player != null and player.is_inside_tree():
		tree = player.get_tree()
	if tree == null and Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameFeel")


func _impact(player: Node) -> void:
	var feel = _feel(player)
	if feel == null or not feel.has_method("play_action"):
		return
	var target = player.get("player_mesh")
	feel.play_action(skill_id, target)


func _show_marker(player: Node, along: float) -> void:
	if not player is Node3D or not player.is_inside_tree():
		return
	var body := player as Node3D
	if _marker == null or not is_instance_valid(_marker):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.45
		mesh.bottom_radius = 0.45
		mesh.height = 0.06
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = _tint
		_marker = MeshInstance3D.new()
		_marker.name = "SkillTelegraph"
		_marker.mesh = mesh
		_marker.material_override = mat
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(_marker)
		_marker.position = Vector3(0.0, 0.12, 0.0)
	var grow := lerpf(0.35, 1.45, clampf(along, 0.0, 1.0))
	_marker.scale = Vector3(grow, 1.0, grow)
	var mat2 := _marker.material_override as StandardMaterial3D
	if mat2 != null:
		var color := _tint
		color.a = lerpf(0.28, 0.75, clampf(along, 0.0, 1.0))
		mat2.albedo_color = color
	_marker.visible = true


func _fade_linger() -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	var mat2 := _marker.material_override as StandardMaterial3D
	if mat2 == null:
		return
	var span := linger_sec if linger_sec > 0.0001 else 1.0
	var color := _tint
	color.a = 0.6 * clampf(linger_left / span, 0.0, 1.0)
	mat2.albedo_color = color


func _burst(player: Node) -> void:
	if _Settings.reduce_motion:
		return
	if not player is Node3D or not player.is_inside_tree():
		return
	var body := player as Node3D
	var bits := BoxMesh.new()
	bits.size = Vector3(0.1, 0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _tint
	var sparks := CPUParticles3D.new()
	sparks.name = "SkillLinger"
	sparks.mesh = bits
	sparks.material_override = mat
	sparks.one_shot = true
	sparks.explosiveness = 0.92
	sparks.amount = 16
	sparks.lifetime = maxf(linger_sec, 0.5)
	sparks.spread = 70.0
	sparks.initial_velocity_min = 1.2
	sparks.initial_velocity_max = 2.8
	sparks.gravity = Vector3(0.0, -4.0, 0.0)
	sparks.emitting = true
	body.add_child(sparks)
	sparks.position = Vector3(0.0, 0.45, 0.0)
	_sparks = sparks


func _clear_visuals() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	if _sparks != null and is_instance_valid(_sparks):
		_sparks.queue_free()
	_sparks = null


func _color(id: String) -> Color:
	match id:
		"dash":
			return Color(0.45, 0.86, 1.0, 0.6)
		"ground_slam":
			return Color(1.0, 0.52, 0.16, 0.65)
		"crystal_pulse":
			return Color(0.72, 0.36, 1.0, 0.65)
		_:
			return Color(0.78, 0.74, 0.62, 0.6)
