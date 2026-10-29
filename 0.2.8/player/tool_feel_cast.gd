class_name ToolFeelCast
extends RefCounted

const _Config = preload("res://config/game_feel_config.gd")
const _Gate = preload("res://player/action_resolve_gate.gd")
const _Settings = preload("res://systems/player_settings.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const STATE_IDLE := 0
const STATE_WIND := 1
const STATE_LIVE := 2

const TOOL_IDS: Array[String] = [
	"multi_block_break",
	"bow_shot",
	"sword_swing",
	"building_placement",
]

var state := STATE_IDLE
var action_id := ""
var wind_sec := 0.0
var linger_sec := 0.0
var recover_sec := 0.0
var wind_left := 0.0
var linger_left := 0.0
var recover_left := 0.0
var buffer_id := ""
var landed := false

var _marker: MeshInstance3D
var _sparks: CPUParticles3D
var _tint := Color(1, 1, 1, 0.55)


func pacing_blocks() -> bool:
	return state == STATE_WIND or recover_left > 0.0


func accepts() -> bool:
	if pacing_blocks():
		return false
	return not _Gate.blocked(self)


func known(id: String) -> bool:
	return TOOL_IDS.has(id)


func remember(id: String) -> void:
	if known(id):
		buffer_id = id


func try_begin(host: Node, id: String) -> bool:
	if not accepts() or not known(id):
		return false
	var row: Dictionary = _row(host, id)
	if row.is_empty():
		return false
	if not _Gate.claim(self, id):
		return false
	_clear_visuals()
	state = STATE_WIND
	action_id = id
	buffer_id = ""
	landed = false
	var telegraph := float(row["telegraph_sec"])
	if host != null and host.has_method("tool_feel_impact_sec"):
		var impact := float(host.tool_feel_impact_sec(id))
		if impact >= 0.0:
			telegraph = impact
	wind_sec = _Gate.wind_for(id, telegraph)
	linger_sec = float(row["linger_sec"])
	recover_sec = float(row["recovery_sec"])
	wind_left = wind_sec
	linger_left = 0.0
	recover_left = 0.0
	_tint = _color(id)
	_show_marker(host, 0.12)
	return true


func advance(host: Node, delta: float) -> void:
	var step := delta
	if step < 0.0:
		step = 0.0
	if state == STATE_WIND:
		if _GameplayInput.blocks_world():
			_abort(host)
			return
		wind_left = maxf(wind_left - step, 0.0)
		var span := wind_sec if wind_sec > 0.0001 else 1.0
		_show_marker(host, 1.0 - (wind_left / span))
		if wind_left <= 0.0:
			_land(host)
		return
	if state == STATE_LIVE:
		if recover_left > 0.0:
			recover_left = maxf(recover_left - step, 0.0)
		if linger_left > 0.0:
			linger_left = maxf(linger_left - step, 0.0)
			_fade_linger()
		if linger_left <= 0.0 and recover_left <= 0.0:
			_clear_visuals()
			state = STATE_IDLE
			action_id = ""
	if state == STATE_IDLE and buffer_id != "" and accepts():
		var next := buffer_id
		buffer_id = ""
		if host != null and host.has_method("on_tool_buffer_open"):
			host.on_tool_buffer_open(next)


func abort_wind(host: Node) -> void:
	if state != STATE_WIND:
		return
	_abort(host)


func _land(host: Node) -> void:
	state = STATE_LIVE
	wind_left = 0.0
	landed = false
	_Gate.mark(action_id)
	if host != null and host.has_method("resolve_tool_feel"):
		landed = bool(host.resolve_tool_feel(action_id))
	if landed:
		_impact(host)
		linger_left = linger_sec
		_burst(host)
	else:
		linger_left = 0.0
		_clear_visuals()
	recover_left = recover_sec


func _abort(host: Node) -> void:
	if host != null and host.has_method("release_tool_feel"):
		host.release_tool_feel(action_id)
	_clear_visuals()
	state = STATE_IDLE
	action_id = ""
	wind_left = 0.0
	linger_left = 0.0
	recover_left = 0.0
	landed = false


func _row(host: Node, id: String) -> Dictionary:
	var feel = _feel(host)
	if feel != null and "config" in feel and feel.config != null and feel.config.has_method("action"):
		return feel.config.action(id)
	if ResourceLoader.exists("res://config/default_game_feel.tres"):
		var loaded = load("res://config/default_game_feel.tres")
		if loaded != null and loaded.has_method("action"):
			return loaded.action(id)
	return _Config.create_default().action(id)


func _feel(host: Node):
	var tree: SceneTree = null
	if host != null and host.is_inside_tree():
		tree = host.get_tree()
	if tree == null and Engine.get_main_loop() is SceneTree:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameFeel")


func _impact(host: Node) -> void:
	var feel = _feel(host)
	if feel == null or not feel.has_method("play_action"):
		return
	var body := _body(host)
	var target = body.get("player_mesh") if body != null else null
	feel.play_action(action_id, target, false)


func _body(host: Node) -> Node3D:
	if host is Node3D:
		return host as Node3D
	if host != null and "player" in host and host.player is Node3D:
		return host.player as Node3D
	return null


func _show_marker(host: Node, along: float) -> void:
	var body := _body(host)
	if body == null or not body.is_inside_tree():
		return
	if _marker == null or not is_instance_valid(_marker):
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.42
		mesh.height = 0.05
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = _tint
		_marker = MeshInstance3D.new()
		_marker.name = "ToolTelegraph"
		_marker.mesh = mesh
		_marker.material_override = mat
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(_marker)
		_marker.position = Vector3(0.0, 0.08, 0.0)
	var grow := lerpf(0.4, 1.35, clampf(along, 0.0, 1.0))
	_marker.scale = Vector3(grow, 1.0, grow)
	var mat2 := _marker.material_override as StandardMaterial3D
	if mat2 != null:
		var color := _tint
		color.a = lerpf(0.25, 0.72, clampf(along, 0.0, 1.0))
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
	color.a = 0.55 * clampf(linger_left / span, 0.0, 1.0)
	mat2.albedo_color = color


func _burst(host: Node) -> void:
	if _Settings.reduce_motion:
		return
	var body := _body(host)
	if body == null or not body.is_inside_tree():
		return
	var bits := BoxMesh.new()
	bits.size = Vector3(0.08, 0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = _tint
	var sparks := CPUParticles3D.new()
	sparks.name = "ToolLinger"
	sparks.mesh = bits
	sparks.material_override = mat
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.amount = 12
	sparks.lifetime = maxf(linger_sec, 0.5)
	sparks.spread = 60.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.4
	sparks.gravity = Vector3(0.0, -4.0, 0.0)
	sparks.emitting = true
	body.add_child(sparks)
	sparks.position = Vector3(0.0, 0.4, 0.0)
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
		"sword_swing":
			return Color(0.82, 0.86, 0.92, 0.6)
		"bow_shot":
			return Color(0.45, 0.78, 0.42, 0.6)
		"multi_block_break":
			return Color(0.92, 0.55, 0.22, 0.65)
		_:
			return Color(0.78, 0.72, 0.55, 0.6)
