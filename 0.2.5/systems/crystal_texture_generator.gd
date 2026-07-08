extends Node
## Procedural texture & sprite generator for Crystal Storm.
##
## Usage:
##   CrystalTextureGenerator.generate_texture(Category.CRYSTAL, &"amethyst")
##   CrystalTextureGenerator.generate_crystal_sprite_frames(&"void_shard")
##   CrystalTextureGenerator.export_sprite_sheet(&"amethyst", 4)
##
## Tune via CrystalTextureGenConfig (.tres) or JSON palettes (TexturePaletteJsonIO).

## Autoload singleton — access globally as CrystalTextureGenerator.
## Intentionally no class_name (would collide with autoload registration).

const _GenConfig = preload("res://config/crystal_texture_gen_config.gd")
const _Palette = preload("res://config/crystal_texture_palette.gd")
const _PaletteJsonIO = preload("res://systems/texture_palette_json_io.gd")

enum Category {
	CRYSTAL,
	BIOME,
	ORE,
	GROUND,
	PARTICLE,
	ENTITY,
	VEGETATION,
	BUILDING,
}

signal texture_generated(category: int, variant_id: StringName, texture: Texture2D)
signal sprite_sheet_exported(path: String, metadata: Dictionary)

var config: _GenConfig = _GenConfig.create_default()

var _noise_cache: Dictionary = {}  # String -> FastNoiseLite


func _ready() -> void:
	config.ensure_default_palettes()


func set_config(new_config: _GenConfig) -> void:
	if new_config == null:
		return
	config = new_config
	config.ensure_default_palettes()
	_noise_cache.clear()


func get_config() -> _GenConfig:
	return config


# ---------------------------------------------------------------------------
# Public API — textures
# ---------------------------------------------------------------------------

func generate_texture(
	category: Category,
	variant_id: StringName = &"default",
	size: int = -1,
	seed_offset: int = 0
) -> ImageTexture:
	var image := generate_image(category, variant_id, size, seed_offset)
	var tex := ImageTexture.create_from_image(image)
	tex.set_meta("category", category)
	tex.set_meta("variant_id", variant_id)
	tex.set_meta("seed", config.master_seed + seed_offset)
	texture_generated.emit(category, variant_id, tex)
	return tex


func generate_image(
	category: Category,
	variant_id: StringName = &"default",
	size: int = -1,
	seed_offset: int = 0
) -> Image:
	var dim := size if size > 0 else config.default_texture_size
	var palette := _resolve_palette(category, variant_id)
	var seed_val := config.master_seed + seed_offset + _category_seed_bias(category)
	var image := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	image.fill(palette.shadow)

	match category:
		Category.CRYSTAL:
			_fill_crystal(image, palette, seed_val, 0.0)
		Category.BIOME:
			_fill_biome_ground(image, palette, seed_val, false)
		Category.GROUND:
			_fill_biome_ground(image, palette, seed_val, true)
		Category.ORE:
			_fill_ore(image, palette, seed_val)
		Category.PARTICLE:
			match variant_id:
				&"damage_number":
					_fill_damage_number(image, palette, seed_val)
				&"hit_flash":
					_fill_hit_flash(image, palette, seed_val)
				&"shatter":
					_fill_shatter_particle(image, palette, seed_val)
				&"spawn_boss", &"spawn_miniboss":
					_fill_spawn_indicator(image, palette, seed_val, variant_id == &"spawn_boss")
				&"victory_glow":
					_fill_victory_glow(image, palette, seed_val)
				_:
					_fill_particle(image, palette, seed_val, 0.0)
		Category.ENTITY:
			_fill_entity_sprite(image, palette, seed_val, variant_id)
		Category.VEGETATION:
			_fill_vegetation_sprite(image, palette, seed_val, variant_id)
		Category.BUILDING:
			_fill_building_sprite(image, palette, seed_val, variant_id)

	return image


func generate_combat_ui_bundle() -> Dictionary:
	return {
		"damage_number": generate_texture(Category.PARTICLE, &"damage_number", 32),
		"hit_flash": generate_texture(Category.PARTICLE, &"hit_flash", 16),
		"shatter": generate_texture(Category.PARTICLE, &"shatter", 24),
		"spawn_boss": generate_texture(Category.PARTICLE, &"spawn_boss", 48),
		"spawn_miniboss": generate_texture(Category.PARTICLE, &"spawn_miniboss", 32),
		"victory_glow": generate_texture(Category.PARTICLE, &"victory_glow", 64),
	}


func generate_game_visual_bundle() -> Dictionary:
	var bundle := generate_combat_ui_bundle()
	var entity_ids: Array[StringName] = [
		&"rabbit", &"deer", &"boar", &"bird", &"town_militia",
		&"crystal_mite", &"farm_bomber", &"crystal_stag", &"thornling",
		&"corrupted_beast", &"shard_guard",
	]
	for id in entity_ids:
		bundle["entity_%s" % id] = generate_texture(Category.ENTITY, id, 48)
	for plant_stage in ["grass_tuft_s0", "grass_tuft_s1", "bush_s0", "bush_s1", "bush_s2", "tree_s0", "tree_s1", "tree_s2"]:
		bundle["veg_%s" % plant_stage] = generate_texture(Category.VEGETATION, StringName(plant_stage), 40)
	for bid in [&"stone_wall", &"wood_wall", &"town_hall", &"ruin_pillar"]:
		bundle["building_%s" % bid] = generate_texture(Category.BUILDING, bid, 48)
	return bundle


func export_game_visual_bundle(export_dir: String = "") -> String:
	var dir := export_dir if not export_dir.is_empty() else config.export_path.path_join("game_visuals")
	DirAccess.make_dir_recursive_absolute(dir)
	var bundle := generate_game_visual_bundle()
	for key in bundle.keys():
		var tex: Texture2D = bundle[key]
		if tex == null:
			continue
		tex.get_image().save_png(dir.path_join("%s.png" % key))
	var meta_path := dir.path_join("manifest.json")
	_PaletteJsonIO.write_json(meta_path, {"keys": bundle.keys(), "count": bundle.size()})
	sprite_sheet_exported.emit(dir, {"manifest": meta_path})
	return dir


func generate_entity_sprite_frames(entity_id: StringName, frame_count: int = 4, fps: float = 6.0) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var anim_name := str(entity_id)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)
	for i in frame_count:
		var img := generate_image(Category.ENTITY, entity_id, 48, i * 131)
		frames.add_frame(anim_name, ImageTexture.create_from_image(img))
	return frames


func generate_crystal_variants(count: int = 4, palette_id: StringName = &"") -> Array[ImageTexture]:
	var out: Array[ImageTexture] = []
	var palettes := config.crystal_palettes
	if palette_id != &"":
		palettes = [_resolve_palette(Category.CRYSTAL, palette_id)]
	for i in count:
		var pal: _Palette = palettes[i % palettes.size()]
		out.append(generate_texture(Category.CRYSTAL, pal.id, -1, i * 9973))
	return out


# ---------------------------------------------------------------------------
# Public API — animation / sprite sheets
# ---------------------------------------------------------------------------

func generate_crystal_sprite_frames(
	variant_id: StringName = &"amethyst",
	frame_count: int = -1,
	fps: float = 8.0
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var anim_name := str(variant_id)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)

	var count := frame_count if frame_count > 0 else config.crystal_frame_count
	var palette := _resolve_palette(Category.CRYSTAL, variant_id)
	var dim := config.default_texture_size

	for i in count:
		var image := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var phase := float(i) / float(maxi(count, 1))
		_fill_crystal(image, palette, config.master_seed + i * 313, phase)
		var tex := ImageTexture.create_from_image(image)
		frames.add_frame(anim_name, tex)

	return frames


func generate_particle_sprite_frames(
	variant_id: StringName = &"amethyst",
	frame_count: int = -1,
	fps: float = 12.0
) -> SpriteFrames:
	var frames := SpriteFrames.new()
	var anim_name := "particle_%s" % variant_id
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)

	var count := frame_count if frame_count > 0 else config.particle_frame_count
	var palette := _resolve_palette(Category.CRYSTAL, variant_id)
	var dim := maxi(16, config.default_texture_size / 2)

	for i in count:
		var image := Image.create(dim, dim, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var phase := float(i) / float(maxi(count, 1))
		_fill_particle(image, palette, config.master_seed + i * 191, phase)
		frames.add_frame(anim_name, ImageTexture.create_from_image(image))

	return frames


func generate_sprite_sheet(
	category: Category,
	variant_ids: Array[StringName] = [],
	columns: int = -1
) -> Dictionary:
	var ids: Array[StringName] = variant_ids
	if ids.is_empty():
		ids = _default_variant_ids(category)

	var cols := columns if columns > 0 else config.sheet_columns
	var pad := config.sheet_padding
	var cell := config.default_texture_size
	var rows := int(ceil(float(ids.size()) / float(cols)))
	var sheet_w := cols * (cell + pad) - pad
	var sheet_h := rows * (cell + pad) - pad
	var sheet := Image.create(sheet_w, sheet_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))

	var metadata := {
		"category": category,
		"cell_size": cell,
		"columns": cols,
		"padding": pad,
		"frames": [],
	}

	for i in ids.size():
		var col := i % cols
		var row := i / cols
		var ox := col * (cell + pad)
		var oy := row * (cell + pad)
		var img := generate_image(category, ids[i], cell, i * 5551)
		sheet.blit_rect(img, Rect2i(0, 0, cell, cell), Vector2i(ox, oy))
		metadata.frames.append({
			"variant_id": str(ids[i]),
			"rect": [ox, oy, cell, cell],
		})

	return {"image": sheet, "metadata": metadata}


func export_sprite_sheet(
	variant_id: StringName = &"amethyst",
	variant_count: int = 4,
	category: Category = Category.CRYSTAL
) -> String:
	var ids: Array[StringName] = []
	var palettes := _palettes_for(category)
	for i in variant_count:
		if variant_id != &"":
			ids.append(variant_id)
		else:
			ids.append(palettes[i % palettes.size()].id)

	var result := generate_sprite_sheet(category, ids)
	var dir := config.export_path
	DirAccess.make_dir_recursive_absolute(dir)

	var base_name := "%s_sheet_%d" % [_category_name(category), config.master_seed]
	var png_path := dir.path_join("%s.png" % base_name)
	var meta_path := dir.path_join("%s.json" % base_name)

	result.image.save_png(png_path)
	_PaletteJsonIO.write_json(meta_path, result.metadata)
	sprite_sheet_exported.emit(png_path, result.metadata)
	return png_path


func export_all_palettes_json(path: String = "user://texture_palettes.json") -> Error:
	return _PaletteJsonIO.export_palettes(config, path)


func import_palettes_json(path: String) -> bool:
	var imported: _GenConfig = _PaletteJsonIO.import_palettes(path)
	if imported == null:
		return false
	config = imported
	config.ensure_default_palettes()
	_noise_cache.clear()
	return true


# ---------------------------------------------------------------------------
# Material helpers — swap procedural textures into existing materials later
# ---------------------------------------------------------------------------

func apply_to_standard_material(
	tex: Texture2D,
	material: StandardMaterial3D,
	palette: _Palette = null
) -> void:
	if material == null or tex == null:
		return
	material.albedo_texture = tex
	if palette:
		material.emission_enabled = palette.glow_strength > 0.01
		material.emission = palette.glow_color
		material.emission_energy_multiplier = palette.glow_strength * 2.0
		material.roughness = palette.roughness_hint
		material.metallic = palette.metallic_hint


# ---------------------------------------------------------------------------
# Generation kernels
# ---------------------------------------------------------------------------

func _fill_crystal(image: Image, palette: _Palette, seed_val: int, phase: float) -> void:
	var dim := image.get_width()
	var base_noise := _get_noise("crystal_base", seed_val, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, config.noise_frequency)
	var ridge_noise := _get_noise("crystal_ridge", seed_val + 11, FastNoiseLite.TYPE_SIMPLEX, config.detail_frequency)
	var cell_noise := _get_noise("crystal_cell", seed_val + 29, FastNoiseLite.TYPE_CELLULAR, config.noise_frequency * 1.6)
	var warp_noise := _get_noise("crystal_warp", seed_val + 47, FastNoiseLite.TYPE_SIMPLEX, config.noise_frequency * 0.5)

	for y in dim:
		for x in dim:
			var uv := Vector2(float(x) / float(dim), float(y) / float(dim))
			var warp := warp_noise.get_noise_2d(uv.x * 4.0, uv.y * 4.0) * config.warp_strength
			var nx := uv.x + warp * 0.08
			var ny := uv.y + warp * 0.08

			var n := base_noise.get_noise_2d(nx * dim, ny * dim) * 0.5 + 0.5
			var ridge := absf(ridge_noise.get_noise_2d(nx * dim * 1.4, ny * dim * 1.4))
			var cell := cell_noise.get_noise_2d(nx * dim, ny * dim) * 0.5 + 0.5

			var facet := clampf(n * 0.55 + ridge * config.ridge_weight + cell * config.cellular_weight, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin((facet + phase) * TAU * config.crystal_pulse_speed)
			var color := palette.primary.lerp(palette.secondary, facet)
			color = color.lerp(palette.accent, ridge * 0.35)

			# Iridescence — hue shift from noise + radial view fake
			var irid := palette.iridescence_strength * sin((nx + ny + facet) * TAU + phase * TAU)
			color = color.lerp(_shift_hue(palette.accent, irid * palette.iridescence_hue_shift), absf(irid))

			# Inner glow peaks
			var glow_mask := smoothstep(0.55, 0.95, facet) * palette.glow_strength
			glow_mask *= 0.65 + 0.35 * pulse
			color = color.lerp(palette.glow_color, glow_mask)

			color = _apply_grade(color, palette)
			image.set_pixel(x, y, color)


func _fill_biome_ground(image: Image, palette: _Palette, seed_val: int, high_detail: bool) -> void:
	var dim := image.get_width()
	var base := _get_noise("ground_base", seed_val, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, config.noise_frequency * 0.7)
	var detail := _get_noise("ground_detail", seed_val + 3, FastNoiseLite.TYPE_SIMPLEX, config.detail_frequency)

	for y in dim:
		for x in dim:
			var uv := Vector2(float(x) / float(dim), float(y) / float(dim))
			var n := base.get_noise_2d(uv.x * dim, uv.y * dim) * 0.5 + 0.5
			var d := detail.get_noise_2d(uv.x * dim * 2.0, uv.y * dim * 2.0) * 0.5 + 0.5
			var blend := clampf(n * 0.75 + d * 0.25, 0.0, 1.0)
			if high_detail:
				blend = clampf(blend + d * 0.15, 0.0, 1.0)
			var color := palette.secondary.lerp(palette.primary, blend)
			color = color.lerp(palette.accent, d * palette.noise_tint_strength)
			color = _apply_grade(color, palette)
			image.set_pixel(x, y, color)


func _fill_ore(image: Image, palette: _Palette, seed_val: int) -> void:
	var dim := image.get_width()
	var base := _get_noise("ore_base", seed_val, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, config.noise_frequency)
	var vein := _get_noise("ore_vein", seed_val + 9, FastNoiseLite.TYPE_SIMPLEX, config.detail_frequency * 1.2)
	var sparkle := _get_noise("ore_spark", seed_val + 17, FastNoiseLite.TYPE_CELLULAR, config.detail_frequency * 2.0)

	for y in dim:
		for x in dim:
			var uv := Vector2(float(x) / float(dim), float(y) / float(dim))
			var rock := base.get_noise_2d(uv.x * dim, uv.y * dim) * 0.5 + 0.5
			var v := absf(vein.get_noise_2d(uv.x * dim * 1.8, uv.y * dim * 1.8))
			v = pow(v, 2.2)
			var color := palette.shadow.lerp(palette.secondary, rock)
			color = color.lerp(palette.primary, v * 0.85)
			var spark := sparkle.get_noise_2d(uv.x * dim * 3.0, uv.y * dim * 3.0)
			if spark > 0.62:
				color = color.lerp(palette.accent, (spark - 0.62) * 2.5)
			color = _apply_grade(color, palette)
			image.set_pixel(x, y, color)


func _fill_damage_number(image: Image, palette: _Palette, _seed_val: int) -> void:
	var dim := image.get_width()
	image.fill(Color(0, 0, 0, 0))
	for y in dim:
		for x in dim:
			var u := float(x) / float(dim)
			var v := float(y) / float(dim)
			if u < 0.08 or u > 0.92 or v < 0.2 or v > 0.88:
				continue
			var edge := minf(minf(u, 1.0 - u), minf(v - 0.2, 0.88 - v))
			var a := smoothstep(0.0, 0.12, edge)
			image.set_pixel(x, y, Color(palette.glow_color.r, palette.glow_color.g, palette.glow_color.b, a * 0.55))


func _fill_hit_flash(image: Image, palette: _Palette, _seed_val: int) -> void:
	var dim := image.get_width()
	var cx := float(dim) * 0.5
	var cy := float(dim) * 0.5
	image.fill(Color(0, 0, 0, 0))
	for y in dim:
		for x in dim:
			var d := Vector2(float(x) - cx, float(y) - cy).length() / (float(dim) * 0.5)
			if d > 1.0:
				continue
			var a := (1.0 - d) * 0.9
			image.set_pixel(x, y, Color(1.0, 0.85, 0.95, a))


func _fill_shatter_particle(image: Image, palette: _Palette, seed_val: int) -> void:
	var dim := image.get_width()
	var shard := _get_noise("shatter", seed_val, FastNoiseLite.TYPE_SIMPLEX, 0.25)
	image.fill(Color(0, 0, 0, 0))
	for y in dim:
		for x in dim:
			var n := shard.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			if n < 0.42:
				continue
			var c := palette.accent.lerp(palette.glow_color, n)
			c.a = (n - 0.42) * 1.8
			image.set_pixel(x, y, c)


func _fill_spawn_indicator(image: Image, palette: _Palette, seed_val: int, is_boss: bool) -> void:
	var dim := image.get_width()
	var cx := float(dim) * 0.5
	var cy := float(dim) * 0.5
	var ring_r := 0.38 if is_boss else 0.32
	image.fill(Color(0, 0, 0, 0))
	for y in dim:
		for x in dim:
			var uv := Vector2(float(x) / float(dim), float(y) / float(dim))
			var d := Vector2(uv.x - 0.5, uv.y - 0.5).length()
			var ring := absf(d - ring_r)
			if ring > 0.06:
				continue
			var pulse := 0.5 + 0.5 * sin((uv.x + uv.y + float(seed_val)) * TAU)
			var c := palette.glow_color.lerp(palette.accent, pulse)
			c.a = (1.0 - ring / 0.06) * (0.85 if is_boss else 0.65)
			image.set_pixel(x, y, c)
			if is_boss and d < 0.12:
				image.set_pixel(x, y, Color(1.0, 0.5, 0.95, 0.9))


func _fill_victory_glow(image: Image, palette: _Palette, seed_val: int) -> void:
	var dim := image.get_width()
	var rays := _get_noise("victory", seed_val, FastNoiseLite.TYPE_SIMPLEX, 0.12)
	image.fill(Color(0, 0, 0, 0))
	for y in dim:
		for x in dim:
			var u := float(x) / float(dim)
			var v := float(y) / float(dim)
			var n := rays.get_noise_2d(u * dim, v * dim) * 0.5 + 0.5
			var horiz := smoothstep(0.35, 0.5, v) * (1.0 - smoothstep(0.55, 0.75, v))
			var a := horiz * (0.45 + n * 0.55)
			var c := palette.glow_color.lerp(Color(1.0, 0.92, 0.45), u)
			c.a = a
			image.set_pixel(x, y, c)


func _fill_entity_sprite(image: Image, palette: _Palette, seed_val: int, variant_id: StringName) -> void:
	var dim := image.get_width()
	image.fill(Color(0, 0, 0, 0))
	var id_str := str(variant_id)
	var body_scale := 0.34
	var is_crystal := id_str.begins_with("crystal") or id_str in ["thornling", "shard_guard", "corrupted_beast", "farm_bomber"]
	var is_militia := id_str == "town_militia"
	var is_bird := id_str == "bird"
	var cx := float(dim) * 0.5
	var cy := float(dim) * 0.58

	for y in dim:
		for x in dim:
			var u := float(x) / float(dim)
			var v := float(y) / float(dim)
			var dx := u - 0.5
			var dy := v - 0.58
			var body := Vector2(dx / body_scale, dy / (body_scale * 1.15)).length()
			if body > 1.0:
				continue
			var c := palette.primary.lerp(palette.secondary, body)
			if is_crystal:
				var spike := absf(sin((u + v) * 18.0 + float(seed_val))) * 0.35
				c = c.lerp(palette.accent, spike)
				c.a = 1.0 - smoothstep(0.75, 1.0, body)
			elif is_militia and v < 0.42:
				c = palette.secondary.lerp(palette.shadow, 0.5)
			elif is_bird and dy < -0.05:
				c = palette.accent
			c.a = 1.0 - smoothstep(0.82, 1.0, body)
			image.set_pixel(x, y, c)

	# Ears / horns / crest
	if id_str in ["rabbit", "deer", "boar"]:
		for y in dim:
			for x in dim:
				var u := float(x) / float(dim)
				var v := float(y) / float(dim)
				for ear_x in [0.36, 0.64]:
					var d := Vector2(u - ear_x, v - 0.28).length()
					if d < 0.07:
						var a := 1.0 - d / 0.07
						var existing: Color = image.get_pixel(x, y)
						if existing.a < 0.1:
							image.set_pixel(x, y, Color(palette.secondary.r, palette.secondary.g, palette.secondary.b, a * 0.9))
	if is_crystal:
		for y in dim:
			for x in dim:
				var u := float(x) / float(dim)
				var v := float(y) / float(dim)
				if v > 0.35:
					continue
				var crest := absf(u - 0.5) < 0.08 and v < 0.32
				if crest:
					var crest_c := palette.glow_color.lerp(palette.accent, 0.4)
					crest_c.a = 0.85
					image.set_pixel(x, y, crest_c)


func _fill_vegetation_sprite(image: Image, palette: _Palette, seed_val: int, variant_id: StringName) -> void:
	var dim := image.get_width()
	image.fill(Color(0, 0, 0, 0))
	var parts := str(variant_id).split("_s")
	var plant_id := parts[0] if parts.size() > 0 else str(variant_id)
	var stage := int(parts[1]) if parts.size() > 1 else 0
	var growth := float(stage + 1) / 3.0

	for y in dim:
		for x in dim:
			var u := float(x) / float(dim)
			var v := float(y) / float(dim)
			if plant_id == "grass_tuft" or plant_id == "grass":
				if v < 0.55 or v > 0.55 + growth * 0.35:
					continue
				var blade := absf(sin(u * TAU * (3.0 + growth * 4.0) + float(seed_val) * 0.01))
				if blade < 0.55:
					continue
				var h := (v - 0.55) / maxf(growth * 0.35, 0.01)
				var c := palette.primary.lerp(palette.accent, h)
				c.a = (1.0 - h) * 0.9
				image.set_pixel(x, y, c)
			elif plant_id == "bush":
				var d := Vector2(u - 0.5, v - 0.52).length()
				var radius := 0.14 + growth * 0.16
				if d > radius:
					continue
				var c := palette.primary.lerp(palette.secondary, d / radius)
				c.a = 1.0 - smoothstep(radius * 0.7, radius, d)
				image.set_pixel(x, y, c)
			else:
				if v > 0.72:
					continue
				var trunk_w := 0.06 + growth * 0.02
				if absf(u - 0.5) < trunk_w and v > 0.42:
					image.set_pixel(x, y, Color(palette.shadow.r, palette.shadow.g, palette.shadow.b, 0.95))
					continue
				var canopy_r := 0.12 + growth * 0.2
				var d := Vector2(u - 0.5, v - 0.38).length()
				if d < canopy_r:
					var c := palette.primary.lerp(palette.accent, d / canopy_r)
					c.a = 1.0 - smoothstep(canopy_r * 0.65, canopy_r, d)
					image.set_pixel(x, y, c)


func _fill_building_sprite(image: Image, palette: _Palette, seed_val: int, variant_id: StringName) -> void:
	var dim := image.get_width()
	image.fill(Color(0, 0, 0, 0))
	var id_str := str(variant_id)
	var is_ruin := id_str.contains("ruin")
	var is_wood := id_str.contains("wood")

	for y in dim:
		for x in dim:
			var u := float(x) / float(dim)
			var v := float(y) / float(dim)
			if v < 0.28 or v > 0.92 or u < 0.18 or u > 0.82:
				continue
			var c := palette.secondary.lerp(palette.primary, v)
			if is_wood:
				c = c.lerp(palette.accent, absf(sin(v * 22.0)) * 0.15)
			if is_ruin:
				c = c.lerp(palette.shadow, absf(sin(u * 31.0 + float(seed_val))) * 0.35)
			if id_str == "town_hall" and v < 0.42 and absf(u - 0.5) < 0.22:
				c = palette.accent
			c.a = 0.95
			image.set_pixel(x, y, c)


func _fill_particle(image: Image, palette: _Palette, seed_val: int, phase: float) -> void:
	var dim := image.get_width()
	var cx := float(dim) * 0.5
	var cy := float(dim) * 0.5
	var radius := float(dim) * 0.42

	for y in dim:
		for x in dim:
			var dx := float(x) - cx
			var dy := float(y) - cy
			var dist := sqrt(dx * dx + dy * dy) / radius
			if dist > 1.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var falloff := 1.0 - smoothstep(0.2, 1.0, dist)
			var twinkle := 0.5 + 0.5 * sin((dist * 8.0 + phase) * TAU)
			var color := palette.glow_color.lerp(palette.accent, twinkle * 0.5)
			color.a = falloff * (0.55 + 0.45 * palette.glow_strength)
			image.set_pixel(x, y, color)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _resolve_palette(category: Category, variant_id: StringName) -> _Palette:
	if category == Category.ENTITY:
		return _entity_palette(variant_id)
	if category == Category.VEGETATION:
		return _vegetation_palette(variant_id)
	if category == Category.BUILDING:
		return _building_palette(variant_id)
	var list := _palettes_for(category)
	for p in list:
		if p.id == variant_id:
			return p
	if not list.is_empty():
		return list[0]
	var fallback := _Palette.new()
	fallback.id = &"fallback"
	fallback.display_name = "Fallback"
	fallback.primary = Color.MAGENTA
	fallback.secondary = Color.PURPLE
	fallback.accent = Color.VIOLET
	return fallback


func _entity_palette(variant_id: StringName) -> _Palette:
	var p := _Palette.new()
	p.id = variant_id
	p.glow_strength = 0.35
	match str(variant_id):
		"rabbit":
			p.primary = Color(0.78, 0.72, 0.62)
			p.secondary = Color(0.62, 0.55, 0.45)
			p.accent = Color(0.92, 0.88, 0.75)
		"deer":
			p.primary = Color(0.72, 0.55, 0.38)
			p.secondary = Color(0.52, 0.38, 0.28)
			p.accent = Color(0.85, 0.68, 0.45)
		"boar":
			p.primary = Color(0.45, 0.35, 0.32)
			p.secondary = Color(0.32, 0.25, 0.22)
			p.accent = Color(0.62, 0.48, 0.42)
		"bird":
			p.primary = Color(0.55, 0.62, 0.78)
			p.secondary = Color(0.35, 0.42, 0.58)
			p.accent = Color(0.85, 0.92, 1.0)
		"town_militia":
			p.primary = Color(0.58, 0.6, 0.72)
			p.secondary = Color(0.38, 0.4, 0.52)
			p.accent = Color(0.78, 0.82, 0.95)
		_:
			p.primary = Color(0.68, 0.28, 0.92)
			p.secondary = Color(0.42, 0.12, 0.62)
			p.accent = Color(0.92, 0.55, 1.0)
			p.glow_strength = 0.65
			p.glow_color = Color(0.85, 0.35, 1.0)
	p.shadow = p.secondary.darkened(0.3)
	return p


func _vegetation_palette(variant_id: StringName) -> _Palette:
	var p := _Palette.new()
	p.id = variant_id
	var id_str := str(variant_id)
	if id_str.begins_with("bush"):
		p.primary = Color(0.28, 0.52, 0.28)
		p.secondary = Color(0.18, 0.38, 0.18)
		p.accent = Color(0.42, 0.68, 0.35)
	elif id_str.begins_with("tree"):
		p.primary = Color(0.22, 0.48, 0.25)
		p.secondary = Color(0.35, 0.22, 0.14)
		p.accent = Color(0.38, 0.62, 0.32)
	else:
		p.primary = Color(0.48, 0.75, 0.35)
		p.secondary = Color(0.32, 0.58, 0.25)
		p.accent = Color(0.62, 0.88, 0.42)
	p.shadow = p.secondary.darkened(0.25)
	return p


func _building_palette(variant_id: StringName) -> _Palette:
	var p := _Palette.new()
	p.id = variant_id
	match str(variant_id):
		"wood_wall":
			p.primary = Color(0.55, 0.38, 0.22)
			p.secondary = Color(0.38, 0.26, 0.15)
			p.accent = Color(0.72, 0.52, 0.32)
		"town_hall":
			p.primary = Color(0.62, 0.58, 0.52)
			p.secondary = Color(0.45, 0.4, 0.36)
			p.accent = Color(0.92, 0.78, 0.42)
		"ruin_pillar":
			p.primary = Color(0.52, 0.48, 0.44)
			p.secondary = Color(0.35, 0.32, 0.3)
			p.accent = Color(0.72, 0.55, 0.38)
		_:
			p.primary = Color(0.58, 0.56, 0.54)
			p.secondary = Color(0.4, 0.38, 0.36)
			p.accent = Color(0.75, 0.72, 0.68)
	p.shadow = p.secondary.darkened(0.35)
	return p


func _palettes_for(category: Category) -> Array:
	match category:
		Category.CRYSTAL, Category.PARTICLE:
			return config.crystal_palettes
		Category.BIOME:
			return config.biome_palettes
		Category.ORE:
			return config.ore_palettes
		Category.GROUND:
			return config.ground_palettes
		_:
			return config.crystal_palettes


func _default_variant_ids(category: Category) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in _palettes_for(category):
		out.append(p.id)
	return out


func _category_seed_bias(category: Category) -> int:
	match category:
		Category.CRYSTAL: return 101
		Category.BIOME: return 202
		Category.ORE: return 303
		Category.GROUND: return 404
		Category.PARTICLE: return 505
		Category.ENTITY: return 606
		Category.VEGETATION: return 707
		Category.BUILDING: return 808
		_: return 0


func _category_name(category: Category) -> String:
	match category:
		Category.CRYSTAL: return "crystal"
		Category.BIOME: return "biome"
		Category.ORE: return "ore"
		Category.GROUND: return "ground"
		Category.PARTICLE: return "particle"
		Category.ENTITY: return "entity"
		Category.VEGETATION: return "vegetation"
		Category.BUILDING: return "building"
		_: return "texture"


func _get_noise(key: String, seed_val: int, noise_type: FastNoiseLite.NoiseType, freq: float) -> FastNoiseLite:
	var cache_key := "%s_%d_%.4f" % [key, seed_val, freq]
	if _noise_cache.has(cache_key):
		return _noise_cache[cache_key]
	var n := FastNoiseLite.new()
	n.seed = seed_val
	n.noise_type = noise_type
	n.frequency = freq
	if noise_type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2
	_noise_cache[cache_key] = n
	return n


func _apply_grade(color: Color, palette: _Palette) -> Color:
	var c := color
	c = c.lerp(c.darkened(0.5), 1.0 - palette.contrast * 0.5)
	var gray := c.get_luminance()
	c = Color.from_hsv(
		c.h,
		clampf(c.s * palette.saturation, 0.0, 1.0),
		clampf(gray + (c.v - gray) * palette.contrast, 0.0, 1.0),
		c.a
	)
	return c


func _shift_hue(color: Color, amount: float) -> Color:
	return Color.from_hsv(fposmod(color.h + amount, 1.0), color.s, color.v, color.a)


static func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)