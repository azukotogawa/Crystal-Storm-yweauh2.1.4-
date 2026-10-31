extends SceneTree

const _FlatBlockAtlas = preload("res://helpers/flat_block_atlas.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _ChunkView = preload("res://chunks/chunk_view.gd")
const _ATLAS: Texture2D = preload("res://assets/tiles/Cube.png")

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed = true
	push_error(msg)


func _run() -> void:
	var tex := _FlatBlockAtlas.texture()
	if tex == null:
		_fail("flat atlas missing")
		quit(1)
		return
	var flat := tex.get_image()
	var src := _ATLAS.get_image()
	if src.is_compressed():
		src.decompress()
	if flat.get_size() != src.get_size():
		_fail("flat atlas size %s != %s" % [flat.get_size(), src.get_size()])
	var tile := 32
	var checked := 0
	for row in flat.get_height() / tile:
		for col in flat.get_width() / tile:
			var ox := col * tile
			var oy := row * tile
			var center := flat.get_pixel(ox + tile / 2, oy + tile / 2)
			for y in range(1, tile - 1):
				for x in range(1, tile - 1):
					if not flat.get_pixel(ox + x, oy + y).is_equal_approx(center):
						_fail("tile %d,%d not flat" % [col, row])
						break
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var n := 0
			for y in tile:
				for x in tile:
					var c := src.get_pixel(ox + x, oy + y)
					if c.a < 0.1:
						continue
					r += c.r
					g += c.g
					b += c.b
					n += 1
			if n == 0:
				continue
			var mean := Color(r / n, g / n, b / n)
			if absf(mean.r - center.r) > 0.02 or absf(mean.g - center.g) > 0.02 or absf(mean.b - center.b) > 0.02:
				_fail("tile %d,%d colour %s far from source mean %s" % [col, row, center, mean])
			checked += 1
	_PlayerSettings.flat_block_faces = true
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ChunkView.gdshader")
	_ChunkView._bind_chunk_atlas(mat)
	var bound = mat.get_shader_parameter("texture_atlas")
	_PlayerSettings.flat_block_faces = false
	var mat2 := ShaderMaterial.new()
	mat2.shader = mat.shader
	_ChunkView._bind_chunk_atlas(mat2)
	var bound2 = mat2.get_shader_parameter("texture_atlas")
	if bound != tex:
		_fail("flat setting did not bind flat atlas")
	if bound2 != _ATLAS:
		_fail("default setting did not bind Cube.png")
	if _failed:
		quit(1)
		return
	print("PASS verify_flat_block_atlas tiles=%d" % checked)
	quit(0)
