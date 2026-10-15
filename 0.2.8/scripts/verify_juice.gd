extends SceneTree


const _Juice = preload("res://systems/juice.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _VfxPool = preload("res://systems/vfx_pool.gd")
const _AudioManifest = preload("res://config/audio_manifest.gd")
const _RelicChoicePanel = preload("res://ui/relic_choice_panel.gd")
const _GameplayInput = preload("res://helpers/gameplay_input.gd")

const _TEST_PATH := "user://verify_juice_settings.json"

var _failed := false


class _RelicBag extends RefCounted:
	var got: Array[StringName] = []

	func equip(relic_id: StringName) -> bool:
		got.append(relic_id)
		return true


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _run() -> void:
	await process_frame
	var old_path := _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _TEST_PATH
	_delete_test_file()
	_check_settings()
	_check_gates()
	await _check_hit_stop()
	_check_flash()
	await _check_pool()
	_check_audio()
	Engine.time_scale = 1.0
	_Juice.clear_shake()
	_PlayerSettings.hit_stop_enabled = true
	_PlayerSettings.screen_shake_enabled = true
	_PlayerSettings.flash_effects_enabled = true
	_delete_test_file()
	_PlayerSettings.settings_path = old_path
	_PlayerSettings.load_settings()
	if _failed:
		quit(1)
	else:
		print("All juice checks OK")
		quit(0)


func _check_settings() -> void:
	var data := _PlayerSettings.load_settings()
	data["screen_shake_enabled"] = false
	data["hit_stop_enabled"] = false
	data["flash_effects_enabled"] = false
	data["volume_sfx"] = 0.4
	if not _PlayerSettings.save_settings(data):
		_fail("settings save failed")
		return
	var loaded := _PlayerSettings.load_settings()
	if bool(loaded.get("screen_shake_enabled", true)) or _PlayerSettings.screen_shake_enabled:
		_fail("screen_shake_enabled did not persist off")
	if bool(loaded.get("hit_stop_enabled", true)) or _PlayerSettings.hit_stop_enabled:
		_fail("hit_stop_enabled did not persist off")
	if bool(loaded.get("flash_effects_enabled", true)) or _PlayerSettings.flash_effects_enabled:
		_fail("flash_effects_enabled did not persist off")
	if absf(float(loaded.get("volume_sfx", 1.0)) - 0.4) > 0.02:
		_fail("volume_sfx did not persist")
	if absf(_PlayerSettings.volume_master - 1.0) > 0.02:
		_fail("volume save changed master")


func _check_gates() -> void:
	Engine.time_scale = 1.0
	_Juice.clear_shake()
	if _Juice.request_hit_stop(0.04, self, true):
		_fail("hit-stop ran while disabled")
	if absf(Engine.time_scale - 1.0) > 0.001:
		_fail("disabled hit-stop changed time_scale")
		Engine.time_scale = 1.0
	_Juice.request_shake(1.0, true)
	if _Juice.shake_offset(0.0).length() > 0.0001:
		_fail("shake offset while disabled")
	_Juice.clear_shake()


func _check_hit_stop() -> void:
	_PlayerSettings.hit_stop_enabled = true
	_PlayerSettings.screen_shake_enabled = true
	_check_headless_skips_hit_stop()
	Engine.time_scale = 0.05
	if _Juice.request_hit_stop(0.04, self, true):
		_fail("hit-stop stole a non-1 time_scale")
	if absf(Engine.time_scale - 0.05) > 0.001:
		_fail("relic-scale guard changed time_scale")
	Engine.time_scale = 1.0
	if not _Juice.request_hit_stop(0.04, self, true):
		_fail("hit-stop refused while enabled")
		return
	if absf(Engine.time_scale - 0.02) > 0.004:
		_fail("hit-stop did not dip time_scale to 0.02")
	var t0 := Time.get_ticks_msec()
	while absf(Engine.time_scale - 1.0) > 0.01 and Time.get_ticks_msec() - t0 < 800:
		await process_frame
	if absf(Engine.time_scale - 1.0) > 0.01:
		_fail("hit-stop did not restore time_scale (now %.3f)" % Engine.time_scale)
		Engine.time_scale = 1.0
	_Juice.request_shake(0.45, true)
	var offset := _Juice.shake_offset(0.0)
	if offset.length() < 0.05:
		_fail("enabled shake produced no offset")
	_PlayerSettings.screen_shake_enabled = false
	if _Juice.shake_offset(0.016).length() > 0.0001:
		_fail("turning shake off left an offset")
	_Juice.clear_shake()
	_PlayerSettings.screen_shake_enabled = true
	await _check_relic_during_hit_stop()


func _check_headless_skips_hit_stop() -> void:
	if DisplayServer.get_name() != "headless":
		_fail("expected a headless display server, got %s" % DisplayServer.get_name())
		return
	Engine.time_scale = 1.0
	if _Juice.request_hit_stop(0.04, self):
		_fail("non-forced hit-stop ran under headless")
	if absf(Engine.time_scale - 1.0) > 0.001:
		_fail("non-forced headless hit-stop changed time_scale to %.3f" % Engine.time_scale)
		Engine.time_scale = 1.0


func _check_relic_during_hit_stop() -> void:
	Engine.time_scale = 1.0
	_GameplayInput.pause_open = false
	var overlay := Control.new()
	overlay.name = "JuiceRelicOverlay"
	overlay.add_to_group("game_overlay")
	root.add_child(overlay)
	if not _Juice.request_hit_stop(0.08, self, true):
		_fail("forced hit-stop did not start before the relic offer")
		overlay.free()
		Engine.time_scale = 1.0
		return
	if absf(Engine.time_scale - 0.02) > 0.004:
		_fail("hit-stop was not active before the relic offer (%.3f)" % Engine.time_scale)
	var bag := _RelicBag.new()
	_RelicChoicePanel.open(self, bag, [&"mason_glove", &"flow_anchor", &"crystal_ward"], "Hit-stop relic")
	var panel := _live_relic_panel(overlay)
	if panel == null or not _press_relic(panel, "offer", "mason_glove"):
		_fail("could not finish the relic offer opened during hit-stop")
	elif absf(Engine.time_scale - 1.0) > 0.01:
		_fail("relic offer closed onto %.3f, want 1.0" % Engine.time_scale)
	else:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 800:
			await process_frame
			if absf(Engine.time_scale - 1.0) > 0.01:
				_fail("expired hit-stop timer changed time_scale to %.3f" % Engine.time_scale)
				break
	Engine.time_scale = 1.0
	_GameplayInput.pause_open = false
	overlay.free()


func _live_relic_panel(host: Node) -> RelicChoicePanel:
	for child in host.get_children():
		if child is RelicChoicePanel and not (child as Node).is_queued_for_deletion():
			return child as RelicChoicePanel
	return null


func _press_relic(panel: Node, role: String, relic_id: String) -> bool:
	for node in _walk(panel):
		if node is Button and str(node.get_meta("relic_role", "")) == role and str(node.get_meta("relic_id", "")) == relic_id:
			(node as Button).pressed.emit()
			return true
	return false


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


func _check_flash() -> void:
	var mesh := MeshInstance3D.new()
	root.add_child(mesh)
	_PlayerSettings.flash_effects_enabled = false
	_Juice.set_flash(mesh, 1.0)
	if float(mesh.get_instance_shader_parameter("flash_amount")) > 0.01:
		_fail("flash stayed on while disabled")
	_PlayerSettings.flash_effects_enabled = true
	_Juice.set_flash(mesh, 1.0)
	if absf(float(mesh.get_instance_shader_parameter("flash_amount")) - 1.0) > 0.01:
		_fail("flash did not reach 1 while enabled")
	var shared := _Juice.flash_material()
	if shared != null and mesh.material_overlay != shared:
		_fail("flash did not attach the shared overlay")
	_Juice.set_flash(mesh, 0.0)
	if absf(float(mesh.get_instance_shader_parameter("flash_amount"))) > 0.01:
		_fail("flash_amount did not return to 0")
	if mesh.material_overlay != null:
		_fail("flash overlay stayed attached after the hit")
	mesh.queue_free()


func _check_pool() -> void:
	var low: Dictionary = _VfxPool.caps_for(0)
	var mid: Dictionary = _VfxPool.caps_for(1)
	var high: Dictionary = _VfxPool.caps_for(2)
	var safe: Dictionary = _VfxPool.caps_for(3)
	if int(low.emitters) >= int(mid.emitters) or int(mid.emitters) >= int(high.emitters):
		_fail("preset emitter caps are not low < medium < high")
	if int(safe.emitters) > int(low.emitters):
		_fail("SAFE emitter cap is above LOW")
	if int(low.swings) > int(high.swings):
		_fail("LOW swing cap exceeds HIGH")
	var pool := _VfxPool.new()
	root.add_child(pool)
	await process_frame
	pool.configure_preset(0)
	if pool.emitter_cap() != int(low.emitters):
		_fail("LOW configure_preset cap mismatch")
	var first := pool.burst(_VfxPool.Kind.CORRUPT, Vector3.ZERO, Color(0.6, 0.2, 0.9))
	var second := pool.burst(_VfxPool.Kind.CORRUPT, Vector3.ZERO, Color(0.6, 0.2, 0.9))
	if not first:
		_fail("first corruption burst was dropped")
	if second:
		_fail("corruption burst was not rate-limited")
	var pink := Color(0.95, 0.3, 0.7)
	var green := Color(0.3, 0.9, 0.4)
	if not pool.burst(_VfxPool.Kind.SHATTER, Vector3(1.0, 0.0, 0.0), pink):
		_fail("first shatter burst was dropped")
	if not pool.burst(_VfxPool.Kind.SHATTER, Vector3(2.0, 0.0, 0.0), green):
		_fail("second shatter burst was dropped")
	var pink_p: CPUParticles3D = null
	var green_p: CPUParticles3D = null
	for child in pool.get_children():
		if not (child is CPUParticles3D):
			continue
		var particles := child as CPUParticles3D
		if _color_near(particles.color, pink):
			pink_p = particles
		elif _color_near(particles.color, green):
			green_p = particles
	if pink_p == null or green_p == null:
		_fail("shatter bursts did not keep their own colors")
	elif pink_p.material_override != green_p.material_override:
		_fail("same-kind bursts did not share one material")
	else:
		var shared_mat := pink_p.material_override as StandardMaterial3D
		if shared_mat == null or not _albedo_is_white(shared_mat.albedo_color):
			_fail("shared particle material albedo is not fixed white")
	for i in 20:
		pool.burst(_VfxPool.Kind.DUST, Vector3(float(i), 1.0, 0.0), Color(0.7, 0.5, 0.3))
	if pool.emitter_count() > pool.emitter_cap():
		_fail("particle pool grew past the cap (%d > %d)" % [pool.emitter_count(), pool.emitter_cap()])
	pool.show_swing("wooden_sword", Vector3.ZERO, Vector3(0, 0, 1))
	pool.show_swing("spear", Vector3.ZERO, Vector3(1, 0, 0))
	var swings := 0
	for child in pool.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("SwingArc"):
			swings += 1
	if swings > int(low.swings):
		_fail("swing meshes exceeded the LOW cap")
	pool.queue_free()


func _check_audio() -> void:
	for bus_name in ["Master", "Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			_fail("missing audio bus %s" % bus_name)
	for bus_name in ["Music", "SFX", "UI"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0 and str(AudioServer.get_bus_send(idx)) != "Master":
			_fail("%s bus does not send to Master" % bus_name)
	var ids := _AudioManifest.ids()
	if ids.is_empty():
		_fail("audio manifest is empty")
	for id in ids:
		var path := _AudioManifest.path_of(id)
		if not path.begins_with("res://assets/audio/"):
			_fail("manifest path for %s is outside assets/audio" % id)
		if _AudioManifest.bus_of(id) == "":
			_fail("manifest bus missing for %s" % id)
	var audio := root.get_node_or_null("AudioManager")
	if audio == null or not audio.has_method("play_sfx"):
		_fail("AudioManager autoload missing")
		return
	audio.play_sfx("not_a_real_id", Vector3.ZERO)
	audio.play_sfx("not_a_real_id")
	audio.play_ui("not_a_real_ui")
	audio.play_ui("not_a_real_ui")
	if int(audio.missing_log_count("not_a_real_id")) != 1:
		_fail("missing sfx id was not logged once")
	if int(audio.missing_log_count("not_a_real_ui")) != 1:
		_fail("missing ui id was not logged once")
	audio.set_music_state("maze")
	audio.set_music_state("maze")
	if str(audio.music_state()) != "maze":
		_fail("music state did not stick")
	audio.set_music_state("assault")
	if str(audio.music_state()) != "assault":
		_fail("music state did not switch to assault")
	_PlayerSettings.screen_shake_enabled = false
	_PlayerSettings.hit_stop_enabled = false
	_PlayerSettings.flash_effects_enabled = false
	var kept := _PlayerSettings.load_settings()
	kept["screen_shake_enabled"] = false
	kept["hit_stop_enabled"] = false
	kept["flash_effects_enabled"] = false
	_PlayerSettings.save_settings(kept)
	audio.set_bus_linear("SFX", 0.25, true)
	var after := _PlayerSettings.load_settings()
	if absf(float(after.get("volume_sfx", 1.0)) - 0.25) > 0.02:
		_fail("set_bus_linear did not persist SFX volume")
	if bool(after.get("screen_shake_enabled", true)) or bool(after.get("hit_stop_enabled", true)):
		_fail("volume save wiped juice toggles")
	if bool(after.get("flash_effects_enabled", true)):
		_fail("volume save wiped flash toggle")
	var db := float(audio.get_bus_db("SFX"))
	if db > -6.0:
		_fail("SFX bus db did not drop with linear 0.25 (%.2f)" % db)


func _albedo_is_white(color: Color) -> bool:
	return absf(color.r - 1.0) < 0.01 and absf(color.g - 1.0) < 0.01 and absf(color.b - 1.0) < 0.01 and absf(color.a - 0.9) < 0.02


func _color_near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _delete_test_file() -> void:
	if not FileAccess.file_exists(_TEST_PATH):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_PATH))
