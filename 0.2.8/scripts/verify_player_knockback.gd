extends SceneTree


const _WorldSettings = preload("res://config/world_settings.gd")

var _failed := false


func _init() -> void:
	_check_sources()
	_check_hits()
	if _failed:
		quit(1)
	else:
		print("All player knockback tests OK")
		quit(0)


func _fail(msg: String) -> void:
	push_error("FAIL " + msg)
	_failed = true


func _check_sources() -> void:
	var player := FileAccess.get_file_as_string("res://player/player.gd")
	if player.is_empty():
		_fail("player.gd unreadable")
		return
	var tick := _func_body(player, "func _tick_player_knockback")
	if not tick.contains("_try_move_delta"):
		_fail("knockback must step through the walk probe")
	var damage := _func_body(player, "func take_damage")
	if damage.find("if burst and _hit_iframes > 0.0:") > damage.find("_publish_health()"):
		_fail("iframe return publishes a hit that did not land")
	if damage.find("_begin_hit_knockback") < damage.find("_publish_health()"):
		_fail("knockback starts before the hit is published")
	if not damage.contains("else:\n\t\t_has_damage_origin = false"):
		_fail("crystal pressure must not keep the attacker origin")
	var enemy := FileAccess.get_file_as_string("res://entities/crystal_enemy.gd")
	var wildlife := FileAccess.get_file_as_string("res://entities/world_entity.gd")
	if not enemy.contains("set_damage_origin") or not wildlife.contains("set_damage_origin"):
		_fail("attackers must pass a world origin into the player")


func _check_hits() -> void:
	var player := Player.new()
	player.health = 100.0
	player.max_health = 100.0
	player.voxel_position = Vector3(10.0, 1.0, 10.0)
	player.locked_yaw_degrees = 0.0
	var ws = _WorldSettings.get_active()
	player.set_damage_origin(_world_at(ws, 8.0, 10.0))
	player.take_damage(10.0)
	if player._knock_dir_xz.x < 0.9 or absf(player._knock_dir_xz.y) > 0.1:
		_fail("hit from the west should shove east, got %s" % player._knock_dir_xz)
	if absf(player._knock_left - player.HIT_KNOCK_COLUMNS) > 0.01:
		_fail("normal shove length %.3f" % player._knock_left)
	if player.health >= 100.0:
		_fail("the hit did not reduce health")
	var locked_dir := player._knock_dir_xz
	var locked_left := player._knock_left
	var locked_hp := player.health
	player.set_damage_origin(_world_at(ws, 14.0, 10.0))
	player.take_damage(10.0)
	if player._knock_dir_xz != locked_dir or absf(player._knock_left - locked_left) > 0.001:
		_fail("i-frames replaced the shove")
	if absf(player.health - locked_hp) > 0.01:
		_fail("i-frames let a second hit land")
	player.damage_source_hint = &"crystal_field"
	player.set_damage_origin(_world_at(ws, 10.0, 6.0))
	player.take_damage(5.0)
	if player._knock_dir_xz != locked_dir or absf(player._knock_left - locked_left) > 0.001:
		_fail("crystal pressure changed the shove")
	if player._hit_iframes <= 0.0:
		_fail("crystal pressure cleared i-frames")
	if player._has_damage_origin:
		_fail("crystal pressure kept the attacker origin")
	player._hit_iframes = 0.0
	player._knock_left = 0.0
	player._knock_dir_xz = Vector2.ZERO
	player.damage_source_hint = &"crystal_field"
	player.set_damage_origin(_world_at(ws, 8.0, 10.0))
	player.take_damage(5.0)
	if player._knock_left > 0.0 or player._has_damage_origin:
		_fail("crystal pressure started a shove")
	player.damage_source_hint = &"hit"
	player.set_damage_origin(_world_at(ws, 10.0, 13.0))
	player.take_damage(4.0, &"boss")
	if player._knock_dir_xz.y > -0.9:
		_fail("boss hit from the south should shove north, got %s" % player._knock_dir_xz)
	if absf(player._knock_left - player.HIT_KNOCK_HEAVY_COLUMNS) > 0.01:
		_fail("boss shove length %.3f" % player._knock_left)
	player._hit_iframes = 0.0
	player.locked_yaw_degrees = 0.0
	player.take_damage(8.0)
	if player._knock_dir_xz.y < 0.9 or absf(player._knock_left - player.HIT_KNOCK_COLUMNS) > 0.01:
		_fail("a hit with no origin should shove backward, got %s left %.3f" % [player._knock_dir_xz, player._knock_left])
	player._tick_player_knockback(0.05, false)
	if player._knock_left > 0.0:
		_fail("a shove with no floor probe should end instead of sticking")
	player.free()
	if _failed:
		return
	print("OK player knockback direction, i-frames, and crystal pressure")


func _world_at(ws, column_x: float, column_z: float) -> Vector3:
	return Vector3(ws.column_to_world(column_x), 1.0, ws.column_to_world(column_z))


func _func_body(src: String, header: String) -> String:
	var at := src.find(header)
	if at < 0:
		_fail("missing %s" % header)
		return ""
	var nxt := src.find("\nfunc ", at + header.length())
	if nxt < 0:
		return src.substr(at)
	return src.substr(at, nxt - at)
