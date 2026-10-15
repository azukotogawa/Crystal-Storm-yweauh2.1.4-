extends SceneTree

const _Quality = preload("res://config/performance_quality_config.gd")
const _Light = preload("res://helpers/scene_lighting.gd")
const _Sun = preload("res://helpers/terrain_lighting.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	if not _Sun.SUN.is_equal_approx(Vector3(0.55, 0.82, 0.38)):
		_fail("sun vector %s" % _Sun.SUN)
	_check_preset(_Quality.Preset.LOW, false, 1, 1024)
	_check_preset(_Quality.Preset.SAFE, false, 1, 1024)
	_check_preset(_Quality.Preset.MEDIUM, true, 1, 2048)
	_check_preset(_Quality.Preset.HIGH, true, 2, 4096)
	var med = _Quality.apply_preset(_Quality.Preset.MEDIUM)
	if med.shadow_max_distance < 200.0:
		_fail("medium shadow distance %.1f misses the ortho camera" % med.shadow_max_distance)
	if med.shadow_split_1 * med.shadow_max_distance < 180.0:
		_fail("medium split 1 ends before the ground")
	if med.shadow_bias <= 0.0 or med.shadow_bias > 0.08:
		_fail("medium bias %.3f" % med.shadow_bias)
	if med.shadow_normal_bias < 0.4 or med.shadow_normal_bias > 2.0:
		_fail("medium normal bias %.3f" % med.shadow_normal_bias)
	if not med.ssao_enabled or not med.fog_enabled:
		_fail("medium left ssao or fog off")
	if absf(med.ambient_light_energy - 0.22) > 0.001 or absf(med.tonemap_exposure - 0.72) > 0.001:
		_fail("medium ambient/exposure drifted")
	var low = _Quality.apply_preset(_Quality.Preset.LOW)
	if low.scene_shadows or low.ssao_enabled or low.fog_enabled:
		_fail("LOW is not cheap")
	_check_scene_file()
	if _failed > 0:
		print("Scene lighting tests failed: %d" % _failed)
		quit(1)
		return
	print("All scene lighting tests OK")
	quit(0)


func _check_preset(which: int, shadows: bool, mode: int, atlas: int) -> void:
	var cfg = _Quality.apply_preset(which)
	var host := Node3D.new()
	root.add_child(host)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	var locked_color := Color(0.72, 0.78, 0.9, 1)
	light.light_color = locked_color
	light.light_energy = 0.58
	var locked_basis := Basis(Vector3(0.7071067, -0.6532814, 0.27059802), Vector3(0, 0.3826834, 0.92387944), Vector3(-0.7071067, -0.6532814, 0.27059802))
	light.transform = Transform3D(locked_basis, Vector3.ZERO)
	host.add_child(light)
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = Environment.new()
	host.add_child(world_env)
	_Light.apply_host(host, cfg)
	if light.shadow_enabled != shadows:
		_fail("preset %d shadows %s" % [which, light.shadow_enabled])
	if int(light.directional_shadow_mode) != mode:
		_fail("preset %d split mode %d" % [which, int(light.directional_shadow_mode)])
	if not is_equal_approx(light.shadow_bias, cfg.shadow_bias):
		_fail("preset %d bias" % which)
	if not is_equal_approx(light.directional_shadow_split_1, cfg.shadow_split_1):
		_fail("preset %d split 1" % which)
	if not is_equal_approx(light.directional_shadow_max_distance, cfg.shadow_max_distance):
		_fail("preset %d distance" % which)
	if light.light_color != locked_color or not is_equal_approx(light.light_energy, 0.58):
		_fail("preset %d moved the sun color or energy" % which)
	if not light.transform.basis.is_equal_approx(locked_basis):
		_fail("preset %d moved the sun basis" % which)
	var env := world_env.environment
	if env.ssao_enabled != cfg.ssao_enabled or env.fog_enabled != cfg.fog_enabled:
		_fail("preset %d env gate" % which)
	if env.volumetric_fog_enabled:
		_fail("preset %d volumetric fog" % which)
	if int(env.tonemap_mode) != int(Environment.TONE_MAPPER_FILMIC):
		_fail("preset %d tonemap" % which)
	if not is_equal_approx(env.tonemap_exposure, cfg.tonemap_exposure):
		_fail("preset %d exposure" % which)
	if not is_equal_approx(env.ambient_light_energy, cfg.ambient_light_energy):
		_fail("preset %d ambient" % which)
	if cfg.shadow_atlas_size != atlas:
		_fail("preset %d atlas %d" % [which, cfg.shadow_atlas_size])
	host.queue_free()


func _check_scene_file() -> void:
	var file := FileAccess.open("res://scenes/main.tscn", FileAccess.READ)
	if file == null:
		_fail("main.tscn unreadable")
		return
	var text := file.get_as_text()
	file.close()
	if "light_color = Color(0.72, 0.78, 0.9, 1)" not in text:
		_fail("scene sun color changed")
	if "Transform3D(0.7071067, -0.6532814, 0.27059802, 0, 0.3826834, 0.92387944, -0.7071067, -0.6532814, 0.27059802, 0, 0, 0)" not in text:
		_fail("scene sun direction changed")
	if "shadow_enabled = true" not in text:
		_fail("scene shadows off")
	if "ssao_enabled = true" not in text or "fog_enabled = true" not in text:
		_fail("scene environment missing ssao or fog")
	if "light_energy = 0.58" not in text:
		_fail("scene sun energy changed")
