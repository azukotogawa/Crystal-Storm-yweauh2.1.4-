extends SceneTree

const _FeelCast = preload("res://player/skill_feel_cast.gd")
const _Skills = preload("res://systems/skill_service.gd")
const _Progression = preload("res://systems/progression_service.gd")

const _PROBES: Array[Dictionary] = [
	{"id": "dash", "wind": 0.19, "linger": 0.61},
	{"id": "ground_slam", "wind": 0.33, "linger": 0.84},
	{"id": "crystal_pulse", "wind": 0.27, "linger": 1.21},
	{"id": "quick_wall", "wind": 0.21, "linger": 0.73},
]

var _failed: int = 0
var _saved_wind: PackedFloat32Array = PackedFloat32Array()
var _saved_linger: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error("FAIL " + msg)


func _run() -> void:
	var feel := root.get_node_or_null("GameFeel")
	if feel == null or feel.config == null:
		_fail("GameFeel config missing")
		_finish()
		return
	_saved_wind = feel.config.telegraph_sec.duplicate()
	_saved_linger = feel.config.linger_sec.duplicate()
	for probe in _PROBES:
		_check_skill(feel, str(probe["id"]), float(probe["wind"]), float(probe["linger"]))
	_check_dash_chain(feel)
	_restore(feel)
	_finish()


func _finish() -> void:
	if _failed == 0:
		print("All skill feel tests OK")
		quit(0)
	else:
		push_error("verify_skill_feel: %d failure(s)" % _failed)
		quit(1)


func _check_skill(feel, id: String, wind: float, linger: float) -> void:
	var index := int(feel.config.action_ids.find(id))
	if index < 0:
		_fail("%s missing from game feel config" % id)
		return
	var file_row: Dictionary = feel.config.action(id)
	if file_row.is_empty() or float(file_row["telegraph_sec"]) <= 0.0 or float(file_row["linger_sec"]) <= 0.0:
		_fail("%s file telegraph or linger is zero" % id)
		return
	feel.config.telegraph_sec[index] = wind
	feel.config.linger_sec[index] = linger
	var host := Node3D.new()
	root.add_child(host)
	var cast := _FeelCast.new()
	if not cast.begin(host, 0, id, Vector2(0.0, 1.0), Vector2(0.0, -1.0)):
		_fail("%s telegraph did not start" % id)
		host.free()
		_restore_one(feel, index)
		return
	if absf(cast.wind_sec - wind) > 0.001 or absf(cast.linger_sec - linger) > 0.001:
		_fail("%s read wind %.3f linger %.3f, config %.3f %.3f" % [id, cast.wind_sec, cast.linger_sec, wind, linger])
	if cast.wind_sec <= 0.0 or cast.linger_sec <= 0.0:
		_fail("%s telegraph or linger is zero" % id)
	var marker := host.get_node_or_null("SkillTelegraph")
	if marker == null or not marker.visible:
		_fail("%s telegraph is not visible" % id)
	if cast.begin(host, 1, "dash" if id != "dash" else "ground_slam", Vector2.ZERO, Vector2.ZERO):
		_fail("%s chained a second skill in the same frame" % id)
	if cast.skill_id != id or cast.state != _FeelCast.STATE_WIND:
		_fail("%s left its wind-up" % id)
	host.free()
	_restore_one(feel, index)
	print("OK skill feel %s" % id)


func _check_dash_chain(feel) -> void:
	var prog := _Progression.new()
	root.add_child(prog)
	prog.skill_points = 2
	var skills := _Skills.new()
	root.add_child(skills)
	if not skills.unlock(&"dash") or not skills.unlock(&"ground_slam"):
		_fail("dash chain could not unlock")
		prog.free()
		skills.free()
		return
	skills.equip(0, &"dash")
	skills.equip(1, &"ground_slam")
	var player := Player.new()
	var body := MeshInstance3D.new()
	body.name = "MeshInstance3D"
	player.add_child(body)
	player._wish_xz = Vector2(0.0, 1.0)
	root.add_child(player)
	player._bind_dash()
	var heard: Array[String] = []
	if feel.has_signal("sound_hook"):
		feel.sound_hook.connect(func(cue: String) -> void:
			heard.append(cue)
		)
	if not skills.try_activate(0):
		_fail("dash chain did not start")
		_drop_chain(player, skills, prog)
		return
	if player._dash_left > 0.0:
		_fail("dash landed inside the telegraph frame")
	if not skills.try_activate(1):
		_fail("slam input was ignored before the handler")
	if skills.cooldown_left(1) > 0.001:
		_fail("a chained slam kept its cooldown")
	if player._skill_feel.skill_id != "dash":
		_fail("the chain replaced the dash wind-up")
	var wind := float(player._skill_feel.wind_sec)
	player._skill_feel.advance(player, maxf(wind - 0.02, 0.0))
	if player._dash_left > 0.0:
		_fail("dash landed early")
	player._skill_feel.advance(player, 0.03)
	if player._dash_left <= 0.0:
		_fail("dash did not land after the telegraph")
	if heard.is_empty() or heard[0] != "dash":
		_fail("dash impact did not emit the sound hook, got %s" % str(heard))
	var sparks := player.get_node_or_null("SkillLinger")
	if sparks == null:
		_fail("dash impact left no linger particles")
	if player._skill_feel.linger_left <= 0.0:
		_fail("dash linger was zero at impact")
	if absf(player._skill_feel.linger_left - player._skill_feel.linger_sec) > 0.001:
		_fail("dash linger did not start from the config value")
	if player._skill_feel.accepts():
		_fail("recovery was already open on the impact frame")
	if player._skill_feel.begin(player, 1, "ground_slam", Vector2.ZERO, Vector2.ZERO):
		_fail("ground slam started during dash recovery")
	player.finish_skill_feel()
	if not player._skill_feel.accepts():
		_fail("recovery did not end")
	_drop_chain(player, skills, prog)
	if _failed == 0:
		print("OK skill feel dash chain")


func _drop_chain(player: Player, skills: Node, prog: Node) -> void:
	if skills.skill_activated.is_connected(player._on_skill_activated):
		skills.skill_activated.disconnect(player._on_skill_activated)
	if skills.skill_unlocked.is_connected(player._on_skill_unlocked):
		skills.skill_unlocked.disconnect(player._on_skill_unlocked)
	player.free()
	skills.free()
	prog.free()


func _restore_one(feel, index: int) -> void:
	if index < 0 or index >= _saved_wind.size() or index >= _saved_linger.size():
		return
	feel.config.telegraph_sec[index] = _saved_wind[index]
	feel.config.linger_sec[index] = _saved_linger[index]


func _restore(feel) -> void:
	if feel == null or feel.config == null:
		return
	feel.config.telegraph_sec = _saved_wind.duplicate()
	feel.config.linger_sec = _saved_linger.duplicate()
