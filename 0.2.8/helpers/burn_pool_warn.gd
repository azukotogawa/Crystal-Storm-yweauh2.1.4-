class_name BurnPoolWarn
extends RefCounted

const _Settings = preload("res://systems/player_settings.gd")

static var _stamp: Array[Vector2i] = []


static func attach(host: Node) -> Node3D:
	var found := host.get_node_or_null("BurnWarn")
	if found is Node3D:
		return found as Node3D
	var root := Node3D.new()
	root.name = "BurnWarn"
	host.add_child(root)
	return root


static func paint(root: Node3D, look: BurnPoolLook, feet: Vector3, cells: Array[Vector2i], vs: float, urgent: float) -> void:
	root.visible = true
	root.global_position = feet
	var tiles := root.get_node_or_null("Tiles") as Node3D
	if tiles == null or not _same(cells) or tiles.get_child_count() != cells.size():
		_rebuild(root, look, cells, vs)
		_stamp = cells.duplicate()
		tiles = root.get_node_or_null("Tiles") as Node3D
	if tiles == null:
		return
	var blind := _Settings.colorblind_palette
	var motion := not _Settings.reduce_motion
	_place(tiles, look, feet, cells, vs)
	_pulse(tiles, look, urgent, blind)
	_flicker(tiles, look, cells, vs, motion, blind)


static func _rebuild(root: Node3D, look: BurnPoolLook, cells: Array[Vector2i], vs: float) -> void:
	var old := root.get_node_or_null("Tiles")
	if old != null:
		root.remove_child(old)
		old.free()
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	root.add_child(tiles)
	var tile_mat := _tile_material(look, _Settings.colorblind_palette)
	var span := vs * (1.0 - clampf(look.tile_inset, 0.0, 0.45))
	var slab := BoxMesh.new()
	slab.size = Vector3(span, maxf(look.tile_thickness, 0.02), span)
	var flame := BoxMesh.new()
	var chip := maxf(look.fire_size, 0.04) * vs
	flame.size = Vector3(chip, chip, chip)
	var count := maxi(look.fire_per_tile, 0)
	for _i in cells.size():
		var tile := MeshInstance3D.new()
		tile.name = "MagmaTile"
		tile.mesh = slab
		tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tile.material_override = tile_mat
		tiles.add_child(tile)
		for _n in count:
			var fire := MeshInstance3D.new()
			fire.name = "MagmaFire"
			fire.mesh = flame
			fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fire.material_override = _fire_material()
			tile.add_child(fire)


static func _tile_material(look: BurnPoolLook, colorblind: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex := look.crack_texture(colorblind)
	mat.albedo_texture = tex
	mat.emission_texture = tex
	return mat


static func _fire_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	return mat


static func _place(tiles: Node3D, look: BurnPoolLook, feet: Vector3, cells: Array[Vector2i], vs: float) -> void:
	var lift := look.tile_thickness * 0.5 + look.ground_gap
	for i in cells.size():
		var tile := tiles.get_child(i) as MeshInstance3D
		var cell: Vector2i = cells[i]
		var cx := (float(cell.x) + 0.5) * vs
		var cz := (float(cell.y) + 0.5) * vs
		tile.position = Vector3(cx - feet.x, lift, cz - feet.z)


static func _pulse(tiles: Node3D, look: BurnPoolLook, urgent: float, colorblind: bool) -> void:
	if tiles.get_child_count() == 0:
		return
	var tile := tiles.get_child(0) as MeshInstance3D
	if not (tile.material_override is StandardMaterial3D):
		return
	var mat := tile.material_override as StandardMaterial3D
	var tex := look.crack_texture(colorblind)
	if mat.albedo_texture != tex:
		mat.albedo_texture = tex
		mat.emission_texture = tex
	var alpha := clampf(look.alpha_low + look.alpha_span * urgent, 0.0, 1.0)
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	mat.emission = look.tile_emission(colorblind)
	mat.emission_energy_multiplier = lerpf(look.emission_low, look.emission_high, urgent)


static func _flicker(tiles: Node3D, look: BurnPoolLook, cells: Array[Vector2i], vs: float, motion: bool, colorblind: bool) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	var base := look.tile_thickness * 0.5
	for i in cells.size():
		var tile := tiles.get_child(i) as MeshInstance3D
		var cell: Vector2i = cells[i]
		for n in tile.get_child_count():
			var fire := tile.get_child(n) as MeshInstance3D
			if not motion:
				fire.visible = false
				continue
			fire.visible = true
			var rise := _rise(cell, n, now, look.fire_speed)
			var side := (_unit(cell, n) - 0.5) * vs * look.fire_spread
			var forward := (_unit(cell, n + 17) - 0.5) * vs * look.fire_spread
			fire.position = Vector3(side, base + rise * look.fire_height * vs, forward)
			if fire.material_override is StandardMaterial3D:
				var mat := fire.material_override as StandardMaterial3D
				var tint := look.fire_color(colorblind, rise)
				mat.albedo_color = tint
				mat.emission = Color(tint.r, tint.g, tint.b, 1.0)
				mat.emission_energy_multiplier = lerpf(0.8, 2.2, rise)


static func _rise(cell: Vector2i, index: int, now: float, speed: float) -> float:
	return fposmod(now * speed + _unit(cell, index), 1.0)


static func _unit(cell: Vector2i, index: int) -> float:
	var n := absi(cell.x * 73856093 ^ cell.y * 19349663 ^ (index + 1) * 83492791) % 1000
	return float(n) / 999.0


static func _same(cells: Array[Vector2i]) -> bool:
	if cells.size() != _stamp.size():
		return false
	for i in cells.size():
		if cells[i] != _stamp[i]:
			return false
	return true
