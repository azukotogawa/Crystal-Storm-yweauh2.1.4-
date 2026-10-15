extends SceneTree

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	var bp := root.get_node_or_null("TextureBlueprint")
	if bp == null or not bp.has_method("set_enabled"):
		_fail("TextureBlueprint autoload missing")
		quit(1)
		return
	bp.set_enabled(false)
	var made := _build()
	bp.set_enabled(true)
	await process_frame
	await process_frame
	_check_on(bp, made)
	bp.set_enabled(false)
	_check_off(made)
	_check_distinct(bp)
	if _failed > 0:
		print("Texture blueprint tests failed: %d" % _failed)
		quit(1)
		return
	print("All texture blueprint tests OK")
	quit(0)


func _build() -> Dictionary:
	var holder := Node3D.new()
	holder.name = "BlueprintProbe"
	root.add_child(holder)
	var flat := Node2D.new()
	flat.name = "BlueprintProbe2D"
	root.add_child(flat)
	var terrain := Sprite3D.new()
	terrain.name = "TerrainSprite"
	var terrain_tex := _tex(32, 32, Color.MAGENTA)
	terrain.texture = terrain_tex
	holder.add_child(terrain)
	var veg := Sprite2D.new()
	veg.name = "VegetationSprite"
	var veg_tex := _tex(40, 40, Color.CYAN)
	veg.texture = veg_tex
	flat.add_child(veg)
	var mob := Sprite3D.new()
	mob.name = "MobSprite"
	var mob_tex := _tex(48, 48, Color.YELLOW)
	mob.texture = mob_tex
	holder.add_child(mob)
	var item := TextureRect.new()
	item.name = "ItemIcon"
	var item_tex := _tex(32, 32, Color.GREEN)
	item.texture = item_tex
	root.add_child(item)
	var button := Button.new()
	button.name = "UIButton"
	var ui_tex := _tex(32, 32, Color.BLUE)
	button.icon = ui_tex
	root.add_child(button)
	var patch := NinePatchRect.new()
	patch.name = "UIPatch"
	var patch_tex := _tex(48, 24, Color.WHITE)
	patch.texture = patch_tex
	root.add_child(patch)
	var dust := CPUParticles2D.new()
	dust.name = "EffectDust"
	var dust_tex := _tex(16, 16, Color.ORANGE)
	dust.texture = dust_tex
	flat.add_child(dust)
	var spark := CPUParticles3D.new()
	spark.name = "EffectSpark"
	var spark_tex := _tex(24, 24, Color.PURPLE)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_texture = spark_tex
	spark.material_override = spark_mat
	spark.mesh = QuadMesh.new()
	holder.add_child(spark)
	var frames := SpriteFrames.new()
	frames.add_animation("walk")
	var frame_a := _tex(32, 32, Color.RED)
	var frame_b := _tex(24, 24, Color.RED)
	frames.add_frame("walk", frame_a, 0.4)
	frames.add_frame("walk", frame_b, 0.35)
	var anim := AnimatedSprite2D.new()
	anim.name = "MobFrames"
	anim.sprite_frames = frames
	flat.add_child(anim)
	var theme := Theme.new()
	var theme_tex := _tex(20, 20, Color.BLACK)
	theme.set_icon("bp_probe", "Button", theme_tex)
	var style_tex := _tex(32, 16, Color.BLACK)
	var style := StyleBoxTexture.new()
	style.texture = style_tex
	theme.set_stylebox("panel", "Panel", style)
	var themed := Control.new()
	themed.name = "UITheme"
	themed.theme = theme
	root.add_child(themed)
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded;\nuniform sampler2D texture_atlas : source_color;\nuniform vec2 atlas_grid = vec2(2.0, 1.0);\nvoid fragment() { ALBEDO = texture(texture_atlas, UV).rgb; }\n"
	var atlas_tex := _tex(64, 32, Color(0.2, 0.3, 0.4))
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("texture_atlas", atlas_tex)
	mat.set_shader_parameter("atlas_grid", Vector2(2, 1))
	var atlas := MeshInstance3D.new()
	atlas.name = "TerrainAtlas"
	atlas.mesh = QuadMesh.new()
	atlas.material_override = mat
	holder.add_child(atlas)
	return {
		"terrain": terrain, "terrain_tex": terrain_tex,
		"veg": veg, "veg_tex": veg_tex,
		"mob": mob, "mob_tex": mob_tex,
		"item": item, "item_tex": item_tex,
		"button": button, "ui_tex": ui_tex,
		"patch": patch, "patch_tex": patch_tex,
		"dust": dust, "dust_tex": dust_tex,
		"spark_mat": spark_mat, "spark_tex": spark_tex,
		"frames": frames, "frame_a": frame_a, "frame_b": frame_b,
		"theme": theme, "theme_tex": theme_tex, "style": style, "style_tex": style_tex,
		"mat": mat, "atlas_tex": atlas_tex,
	}


func _check_on(bp: Node, made: Dictionary) -> void:
	_expect_swap(bp, "terrain", made.terrain.texture, made.terrain_tex)
	_expect_swap(bp, "vegetation", made.veg.texture, made.veg_tex)
	_expect_swap(bp, "mobs", made.mob.texture, made.mob_tex)
	_expect_swap(bp, "items", made.item.texture, made.item_tex)
	_expect_swap(bp, "ui", made.button.icon, made.ui_tex)
	_expect_swap(bp, "ui", made.patch.texture, made.patch_tex)
	_expect_swap(bp, "effects", made.dust.texture, made.dust_tex)
	_expect_swap(bp, "effects", made.spark_mat.albedo_texture, made.spark_tex)
	_expect_swap(bp, "mobs", made.frames.get_frame_texture("walk", 0), made.frame_a)
	_expect_swap(bp, "mobs", made.frames.get_frame_texture("walk", 1), made.frame_b)
	if absf(made.frames.get_frame_duration("walk", 0) - 0.4) > 0.001:
		_fail("frame duration changed")
	_expect_swap(bp, "ui", made.theme.get_icon("bp_probe", "Button"), made.theme_tex)
	_expect_swap(bp, "ui", made.style.texture, made.style_tex)
	var atlas_now: Texture2D = made.mat.get_shader_parameter("texture_atlas")
	_expect_swap(bp, "terrain", atlas_now, made.atlas_tex)


func _check_off(made: Dictionary) -> void:
	if made.terrain.texture != made.terrain_tex:
		_fail("terrain texture was not restored")
	if made.veg.texture != made.veg_tex:
		_fail("vegetation texture was not restored")
	if made.mob.texture != made.mob_tex:
		_fail("mob texture was not restored")
	if made.item.texture != made.item_tex:
		_fail("item texture was not restored")
	if made.button.icon != made.ui_tex:
		_fail("button icon was not restored")
	if made.patch.texture != made.patch_tex:
		_fail("ninepatch was not restored")
	if made.dust.texture != made.dust_tex:
		_fail("particle texture was not restored")
	if made.spark_mat.albedo_texture != made.spark_tex:
		_fail("particle material was not restored")
	if made.frames.get_frame_texture("walk", 0) != made.frame_a:
		_fail("frame 0 was not restored")
	if made.frames.get_frame_texture("walk", 1) != made.frame_b:
		_fail("frame 1 was not restored")
	if made.theme.get_icon("bp_probe", "Button") != made.theme_tex:
		_fail("theme icon was not restored")
	if made.style.texture != made.style_tex:
		_fail("style texture was not restored")
	if made.mat.get_shader_parameter("texture_atlas") != made.atlas_tex:
		_fail("atlas texture was not restored")


func _expect_swap(bp: Node, category: String, now: Texture2D, original: Texture2D) -> void:
	if now == null or original == null:
		_fail("%s texture missing" % category)
		return
	if now == original:
		_fail("%s texture was not swapped" % category)
		return
	if now.get_width() != original.get_width() or now.get_height() != original.get_height():
		_fail("%s size %dx%d vs %dx%d" % [
			category, now.get_width(), now.get_height(), original.get_width(), original.get_height()
		])
	if not now.has_meta("cs_blueprint"):
		_fail("%s placeholder missing meta" % category)
	var img := now.get_image()
	if img == null:
		_fail("%s placeholder has no image" % category)
		return
	var got := img.get_pixel(3, 3)
	var want: Color = bp.CATEGORY_COLOR[category]
	if not _near(got, want):
		_fail("%s pixel %s wanted %s" % [category, got, want])


func _check_distinct(bp: Node) -> void:
	var cols: Array = bp.CATEGORY_COLOR.values()
	for i in cols.size():
		for j in range(i + 1, cols.size()):
			if _near(cols[i], cols[j]):
				_fail("category colours collide %s %s" % [cols[i], cols[j]])


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.03 and absf(a.g - b.g) < 0.03 and absf(a.b - b.b) < 0.03


func _tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
