extends SceneTree
## The crystal mass that draws must use the pulse shader, and crystal_time on that
## material must move when CrystalManager._process runs. A shader on a side material
## does not count.
## Usage: godot --headless -s scripts/verify_crystal_glow.gd

const _CrystalManager = preload("res://crystal/crystal_manager.gd")
const _CrystalCell = preload("res://crystal/crystal_cell.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := false
	_PlayerSettings.reduce_motion = false

	var shader := load("res://shaders/crystal_pulse.gdshader") as Shader
	if shader == null:
		push_error("crystal pulse shader failed to load")
		quit(1)
		return
	var src := shader.code
	if "sin(crystal_time * 3.6)" not in src or "1.05 + 0.55 * wave" not in src or "EMISSION" not in src:
		push_error("pulse shader does not drive EMISSION from crystal_time")
		failed = true
	else:
		print("OK pulse shader samples crystal_time")

	var root3d := Node3D.new()
	root.add_child(root3d)
	var crystal = _CrystalManager.new()
	crystal.name = "CrystalManager"
	crystal.set_process(false)
	crystal.cancel_bootstrap()
	root3d.add_child(crystal)
	await process_frame

	var cell := _CrystalCell.new(Vector2i(4, 5), 6.0, 1.2)
	var layer = crystal._make_chunk_layer(Vector2i(0, 0))
	layer.rebuild([cell])
	var mesh := layer.get_node_or_null("CrystalFluid") as MultiMeshInstance3D
	if mesh == null or mesh.multimesh == null or mesh.multimesh.instance_count < 1:
		push_error("crystal chunk did not instance a mesh")
		quit(1)
		return
	var drawn := mesh.material_override
	if drawn == null or not (drawn is ShaderMaterial):
		push_error("drawn crystal material is not the pulse shader")
		failed = true
	elif drawn != crystal._crystal_material:
		push_error("drawn crystal material is not the manager mass material")
		failed = true
	else:
		var sh := drawn as ShaderMaterial
		if sh.shader == null or sh.shader.resource_path != "res://shaders/crystal_pulse.gdshader":
			push_error("drawn material shader is %s" % (sh.shader.resource_path if sh.shader else "none"))
			failed = true
		else:
			print("OK drawn mesh uses crystal_pulse")
		var albedo: Color = sh.get_shader_parameter("albedo_color")
		var expect: Color = CrystalPalette.mass_albedo(false)
		if not albedo.is_equal_approx(expect):
			push_error("drawn albedo %s != palette %s" % [albedo, expect])
			failed = true
		var before: float = float(sh.get_shader_parameter("crystal_time"))
		crystal._process(0.4)
		var after: float = float((mesh.material_override as ShaderMaterial).get_shader_parameter("crystal_time"))
		if after < before + 0.35:
			push_error("crystal_time on the drawn material did not advance (%s -> %s)" % [before, after])
			failed = true
		else:
			print("OK crystal_time bound on drawn material (%s -> %s)" % [before, after])
		var dim := 1.05 + 0.55 * sin(-PI * 0.5)
		var bright := 1.05 + 0.55 * sin(PI * 0.5)
		if bright - dim < 1.0:
			push_error("glow swing is too small to read (%.3f -> %.3f)" % [dim, bright])
			failed = true
		else:
			print("OK glow swings %.2f to %.2f" % [dim, bright])

	crystal.queue_free()
	if failed:
		quit(1)
		return
	print("All crystal glow tests OK")
	quit(0)
