extends SceneTree

const _Day = preload("res://helpers/day_night.gd")
const _Sun = preload("res://helpers/terrain_lighting.gd")
const _Items = preload("res://helpers/item_types.gd")
const _Inventory = preload("res://inventory/inventory.gd")
const _Prop = preload("res://world/torch_prop.gd")
const _Clock = preload("res://world/day_night_clock.gd")
const _Field = preload("res://world/torch_field.gd")
const _Stand = preload("res://world/torch_input_stand.gd")
const _Weapon = preload("res://weapons/weapon_controller.gd")

var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_Items.reset()
	_Items.ensure_builtins()
	_Sun.ensure_globals()
	_check_curve()
	_check_art()
	await _check_input()
	if _failed == 0:
		print("DAYNIGHT TORCH OK")
		quit(0)
	else:
		print("DAYNIGHT TORCH FAIL count=%d" % _failed)
		quit(1)


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL daynight %s" % msg)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func _check_curve() -> void:
	if not is_equal_approx(_Day.DAY_LENGTH_SEC, 480.0):
		_fail("day length changed from 480")
	if not _Sun.SUN.is_equal_approx(Vector3(0.62, 0.57, 0.54)):
		_fail("locked sun moved")
	var day_f := _Day.ambient_factor(_Day.NOON_PHASE)
	var night_f := _Day.ambient_factor(_Day.MIDNIGHT_PHASE)
	var ratio := night_f / day_f
	print("ART day_length_sec=%.1f noon_phase=%.2f midnight_phase=%.2f" % [_Day.DAY_LENGTH_SEC, _Day.NOON_PHASE, _Day.MIDNIGHT_PHASE])
	print("ART ambient_factor day=%.4f night=%.4f ratio=%.4f recorded=%.4f" % [day_f, night_f, ratio, _Day.RECORDED_NIGHT_DAY_RATIO])
	print("ART sun_factor day=%.4f night=%.4f terrain_gain day=%.4f night=%.4f" % [
		_Day.sun_factor(_Day.NOON_PHASE),
		_Day.sun_factor(_Day.MIDNIGHT_PHASE),
		_Day.terrain_gain(_Day.NOON_PHASE),
		_Day.terrain_gain(_Day.MIDNIGHT_PHASE),
	])
	if not is_equal_approx(ratio, _Day.RECORDED_NIGHT_DAY_RATIO):
		_fail("night/day ambient ratio %.4f != recorded %.4f" % [ratio, _Day.RECORDED_NIGHT_DAY_RATIO])
	if not is_equal_approx(ratio, _Day.night_day_ambient_ratio()):
		_fail("recorded helper ratio drifted")
	if night_f >= day_f * 0.5:
		_fail("night ambient is not noticeably darker than day")
	if not is_equal_approx(_Day.terrain_gain(_Day.NOON_PHASE), 1.0):
		_fail("noon terrain gain must stay 1 so day shading is unchanged")
	var night_gain := _Day.terrain_gain(_Day.MIDNIGHT_PHASE)
	if night_gain < 0.28 or night_gain > 0.6:
		_fail("night terrain gain %.3f is outside the readable band" % night_gain)

	var host := Node3D.new()
	root.add_child(host)
	var env := Environment.new()
	env.ambient_light_energy = 0.22
	env.fog_light_energy = 0.28
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	host.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.light_energy = 0.58
	light.rotation = Vector3(-0.9, 0.4, 0.0)
	host.add_child(light)
	var saved_basis := light.transform.basis
	var clock := _Clock.new()
	clock.name = "DayNightClock"
	host.add_child(clock)
	clock.force_phase(_Day.NOON_PHASE)
	var day_ambient := env.ambient_light_energy
	var day_sun := light.light_energy
	clock.force_phase(_Day.MIDNIGHT_PHASE)
	var night_ambient := env.ambient_light_energy
	var night_sun := light.light_energy
	var applied_ratio := night_ambient / day_ambient
	print("ART env_ambient day=%.4f night=%.4f ratio=%.4f sun_energy day=%.4f night=%.4f" % [
		day_ambient, night_ambient, applied_ratio, day_sun, night_sun,
	])
	if not is_equal_approx(applied_ratio, _Day.RECORDED_NIGHT_DAY_RATIO):
		_fail("applied ambient ratio %.4f != %.4f" % [applied_ratio, _Day.RECORDED_NIGHT_DAY_RATIO])
	if not is_equal_approx(day_ambient, 0.22):
		_fail("noon must keep the authored ambient 0.22, got %.4f" % day_ambient)
	if not light.transform.basis.is_equal_approx(saved_basis):
		_fail("night apply rotated the sun")
	host.queue_free()


func _check_art() -> void:
	var packed := load("res://scenes/torch_prop.tscn") as PackedScene
	if packed == null:
		_fail("torch scene import failed")
		return
	var shader := load("res://shaders/ChunkSurfaceMesh.gdshader")
	if shader == null:
		_fail("terrain shader import failed")
		return
	var shade := FileAccess.get_file_as_string("res://shaders/terrain_shade.gdshaderinc")
	if shade.is_empty():
		_fail("terrain shade include missing")
		return
	if "terrain_corner_darken" not in shade or "terrain_ao_strength" not in shade:
		_fail("soft local shade was removed")
	if "cs_apply_night" not in shade:
		_fail("night gain missing from terrain shade")
	var corner_at := shade.find("clamp(terrain_corner_darken")
	var night_at := shade.rfind("return cs_apply_night")
	if corner_at < 0 or night_at < corner_at:
		_fail("night multiply must stay after corner darken")
	print("ART shader_import=ok include_chars=%d corner_use=%d night_apply=%d" % [shade.length(), corner_at, night_at])

	var prop := packed.instantiate() as Node3D
	if prop == null:
		_fail("torch scene instantiate failed")
		return
	root.add_child(prop)
	var lights := 0
	var meshes := 0
	var light: OmniLight3D = null
	for child in prop.get_children():
		if child is OmniLight3D:
			lights += 1
			light = child
		if child is MeshInstance3D:
			meshes += 1
	var height := 0.0
	if prop.has_method("mesh_height"):
		height = float(prop.mesh_height())
	var pole_luma := _luma(_Prop.POLE_COLOR)
	var flame_luma := _luma(_Prop.FLAME_COLOR)
	var spread := flame_luma - pole_luma
	print("ART torch_nodes=%d meshes=%d omni=%d height=%.3f pole_luma=%.4f flame_luma=%.4f spread=%.4f" % [
		prop.get_child_count() + 1, meshes, lights, height, pole_luma, flame_luma, spread,
	])
	print("ART texture_dims=none flat_materials=2 atlas_index=none")
	if prop.get_child_count() != 3 or meshes != 2 or lights != 1:
		_fail("torch scene node count pole+flame+light expected")
	if light == null:
		_fail("torch light missing")
	else:
		print("ART light_energy=%.3f range=%.2f shadows=%s color=%s" % [
			light.light_energy, light.omni_range, str(light.shadow_enabled), light.light_color,
		])
		if light.shadow_enabled:
			_fail("torch light must not cast shadows")
		if not is_equal_approx(light.omni_range, _Prop.RANGE):
			_fail("torch range %.2f != %.2f" % [light.omni_range, _Prop.RANGE])
		if not is_equal_approx(light.light_energy, _Prop.LIT_ENERGY):
			_fail("lit energy %.3f != %.3f" % [light.light_energy, _Prop.LIT_ENERGY])
		if light.omni_range > 8.0:
			_fail("torch range is not small")
	if height < 1.0 or height > 1.6:
		_fail("torch mesh height %.3f is not a readable prop" % height)
	if spread < 0.25:
		_fail("flame/pole luminance spread %.3f is too flat" % spread)
	if _Items.breaks_blocks("torch") or _Items.is_placeable_block("torch"):
		_fail("torch must not break or place blocks")
	if not _Items.has_right_click_ability("torch"):
		_fail("torch right click must be an ability, not a block place")
	prop.queue_free()


func _tap(action: String) -> void:
	Input.action_press(action)
	await process_frame
	Input.action_release(action)
	await process_frame


func _check_input() -> void:
	var host := Node3D.new()
	host.name = "TorchHarness"
	root.add_child(host)
	var stand := _Stand.new()
	stand.name = "PlayerStand"
	stand.add_to_group("player")
	host.add_child(stand)
	var inv := _Inventory.new()
	inv.set_slot(7, "torch", 4)
	stand.inventory = inv
	var weapon := _Weapon.new()
	weapon.name = "WeaponController"
	host.add_child(weapon)
	weapon.inventory = inv
	var field := _Field.new()
	field.name = "TorchField"
	host.add_child(field)
	await process_frame
	await _tap("hotbar_8")
	var selected = weapon.get_active_item()
	if selected == null or str(selected.id) != "torch":
		_fail("hotbar_8 did not select the torch")
		return
	var before := int(inv.count_item("torch"))
	await _tap("build_place")
	var placed := field.nearest_torch()
	if placed == null or not placed.has_method("light_energy"):
		_fail("build_place did not place a torch")
		return
	var lit_energy := float(placed.light_energy())
	print("ART input placed energy=%.3f count=%d stacks=%d" % [lit_energy, field.torch_count(), inv.count_item("torch")])
	if lit_energy <= 0.1:
		_fail("placed torch light energy is off")
	if int(inv.count_item("torch")) != before - 1:
		_fail("place did not spend one torch")
	var omni := placed.get_node_or_null("TorchLight") as OmniLight3D
	if omni == null or omni.shadow_enabled:
		_fail("placed torch is not a shadowless omni light")
	await _tap("interact")
	var out_energy := float(placed.light_energy())
	print("ART input extinguished energy=%.3f" % out_energy)
	if out_energy > 0.01:
		_fail("interact did not extinguish the torch")
	await _tap("interact")
	var relit := float(placed.light_energy())
	print("ART input relit energy=%.3f" % relit)
	if not is_equal_approx(relit, lit_energy):
		_fail("second interact did not relight, energy %.3f" % relit)
	await _tap("attack")
	await process_frame
	if field.torch_count() != 0:
		_fail("attack did not pick the torch up")
	if int(inv.count_item("torch")) != before:
		_fail("pickup did not return the torch, stacks=%d" % int(inv.count_item("torch")))
	else:
		print("ART input picked_up stacks=%d torches=%d" % [int(inv.count_item("torch")), field.torch_count()])
	inv.set_slot(7, "torch", 8)
	weapon.select_hotbar(7)
	var placed_n := 0
	for i in 9:
		stand.global_position = Vector3(float(i) * 3.0, 0.0, 0.0)
		await _tap("build_place")
		placed_n = field.torch_count()
	print("ART torch_cap placed=%d max=%d lit=%d" % [placed_n, field.MAX_TORCHES, field.lit_count()])
	if placed_n != field.MAX_TORCHES:
		_fail("torch cap placed %d, expected %d" % [placed_n, field.MAX_TORCHES])
	if field.lit_count() > field.MAX_TORCHES:
		_fail("lit torches exceeded the cap")
	for child in field.get_children():
		var node := child.get_node_or_null("TorchLight") as OmniLight3D
		if node != null and node.shadow_enabled:
			_fail("a capped torch enabled shadows")
		if node != null and node.omni_range > 8.0:
			_fail("a capped torch range is too large")
	host.queue_free()
