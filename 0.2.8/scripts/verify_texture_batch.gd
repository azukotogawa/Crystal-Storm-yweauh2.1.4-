extends SceneTree
## Headless checks for texture batch 1: sizes, palette, outline, resolver, settings, corruption.

const _TextureSet = preload("res://helpers/texture_set.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")
const _SettingsMenu = preload("res://ui/settings_menu.gd")
const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _FeatureLayer = preload("res://world/feature_visual_layer.gd")
const _FeatureKinds = preload("res://helpers/world_feature_types.gd")

const _TEST_PATH := "user://verify_texture_batch.json"
const _ART := "res://assets/art/"
const _BATCH := "res://assets/art_batch1/"
const _MAX_COLORS := 24

var _failed: int = 0
var _old_settings_path: String = ""


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	_old_settings_path = _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _TEST_PATH
	_PlayerSettings.save_settings(_PlayerSettings.defaults())
	_check_manifest_art()
	_check_corrupted_variants()
	_check_crystals()
	_check_resolver()
	await _check_settings()
	_check_corruption_hook()
	await _check_blueprint_on_batch()
	_restore_settings()
	if _failed > 0:
		print("Texture batch tests failed: %d" % _failed)
		quit(1)
		return
	print("All texture batch tests OK")
	quit(0)


func _check_manifest_art() -> void:
	var doc := _read_manifest()
	var slots: Array = doc.get("slots", [])
	var checked := 0
	var skipped := 0
	for slot in slots:
		if not (slot is Dictionary):
			continue
		var category := str(slot.get("category", ""))
		if category != "items" and category != "vegetation" and category != "mobs":
			continue
		var path := str(slot.get("path", ""))
		if path.begins_with(_BATCH):
			continue
		if not path.begins_with(_ART):
			skipped += 1
			continue
		checked += 1
		var size: Array = slot.get("expected_size", [])
		if size.size() != 2:
			_fail("expected size missing %s" % path)
			continue
		var want_w := int(size[0])
		var want_h := int(size[1])
		var mirror := _BATCH + path.substr(_ART.length())
		var image := _load_res(mirror)
		if image == null:
			_fail("batch1 missing %s" % mirror)
			continue
		if image.get_width() != want_w or image.get_height() != want_h:
			_fail("batch1 size %s is %dx%d want %dx%d" % [mirror, image.get_width(), image.get_height(), want_w, want_h])
		var audit := _audit(image, false)
		if not audit.is_empty():
			_fail("%s: %s" % [mirror, audit])
		var batch = slot.get("batch1", null)
		if batch is Dictionary:
			if str(batch.get("status", "")) != "present":
				_fail("manifest batch1 absent for %s" % path)
			var bsize: Array = batch.get("size", [])
			if bsize.size() == 2 and (int(bsize[0]) != want_w or int(bsize[1]) != want_h):
				_fail("manifest batch1 size mismatch %s" % path)
	if checked < 47:
		_fail("expected at least 47 assets/art item/vegetation/mob slots, saw %d" % checked)
	print("batch art slots=%d skipped_non_art=%d" % [checked, skipped])


func _check_corrupted_variants() -> void:
	var doc := _read_manifest()
	var kinds := {}
	var saw := 0
	for slot in doc.get("slots", []):
		if not (slot is Dictionary):
			continue
		var path := str(slot.get("path", ""))
		if not path.begins_with(_ART + "vegetation/") or not path.ends_with(".png"):
			continue
		var file := path.get_file()
		var mirror := _BATCH + "vegetation/corrupted_" + file
		var image := _load_res(mirror)
		if image == null:
			_fail("corrupted variant missing %s" % mirror)
			continue
		var size: Array = slot.get("expected_size", [])
		if size.size() == 2 and (image.get_width() != int(size[0]) or image.get_height() != int(size[1])):
			_fail("corrupted size %s" % mirror)
		var audit := _audit(image, true)
		if not audit.is_empty():
			_fail("%s: %s" % [mirror, audit])
		saw += 1
		kinds[file.get_basename().trim_suffix(_stage_suffix(file.get_basename()))] = true
	if saw < 22:
		_fail("corrupted vegetation count %d" % saw)
	for kind in ["bush", "grass_tuft", "fern", "tall_grass", "tree", "wildflower", "crystal_bush", "crystal_grass", "shard_tree"]:
		if not kinds.has(kind):
			_fail("no corrupted variant for %s" % kind)
	print("corrupted vegetation=%d kinds=%d" % [saw, kinds.size()])


func _stage_suffix(base: String) -> String:
	var idx := base.rfind("_s")
	if idx > 0 and base.substr(idx + 2).is_valid_int():
		return base.substr(idx)
	return ""


func _check_crystals() -> void:
	for id in ["amethyst", "void_shard", "solar_crystal"]:
		var path := "res://assets/art/crystal/%s.png" % id
		var image := _load_res(path)
		if image == null:
			_fail("crystal missing %s" % path)
			continue
		if image.get_width() != 64 or image.get_height() != 64:
			_fail("crystal size %s is %dx%d" % [id, image.get_width(), image.get_height()])
		var tex := _TextureSet.resolve(path)
		if tex == null:
			_fail("crystal resolve failed %s" % id)
			continue
		if tex.get_width() != 64 or tex.get_height() != 64:
			_fail("crystal texture size %s" % id)
	print("crystals=3")


func _check_resolver() -> void:
	var sword := "res://assets/art/items/wooden_sword.png"
	var batch := "res://assets/art_batch1/items/wooden_sword.png"
	var facet := "res://assets/art/crystal/facet.png"
	var player := "res://assets/player/player.png"
	_PlayerSettings.texture_set = "original"
	_TextureSet.clear_cache()
	if _TextureSet.resolved_path(sword) != sword:
		_fail("original set remapped the sword")
	if _TextureSet.is_batch1():
		_fail("original set reported batch1")
	var original_tex := _TextureSet.resolve(sword)
	if original_tex == null or str(original_tex.get_meta("cs_art_path", "")) != sword:
		_fail("original resolve path")
	if str(original_tex.get_meta("cs_texture_set", "")) != "original":
		_fail("original resolve set meta")
	_PlayerSettings.texture_set = "batch1"
	_TextureSet.clear_cache()
	if _TextureSet.resolved_path(sword) != batch:
		_fail("batch resolve path want %s got %s" % [batch, _TextureSet.resolved_path(sword)])
	var batch_tex := _TextureSet.resolve(sword)
	var again := _TextureSet.resolve(sword)
	if batch_tex == null or again != batch_tex:
		_fail("resolver cache miss")
	if str(batch_tex.get_meta("cs_art_path", "")) != batch:
		_fail("batch meta path %s" % str(batch_tex.get_meta("cs_art_path", "")))
	if str(batch_tex.get_meta("cs_texture_set", "")) != "batch1":
		_fail("batch meta set")
	if _TextureSet.resolved_path(facet) != facet:
		_fail("missing batch file did not fall back to facet.png")
	var facet_tex := _TextureSet.resolve(facet)
	if facet_tex == null or str(facet_tex.get_meta("cs_art_path", "")) != facet:
		_fail("facet fallback texture")
	if _TextureSet.resolved_path(player) != player:
		_fail("non-art path was remapped")
	if _TextureSet.resolve("res://assets/art/items/%s.png" % "not_a_real_item") != null:
		_fail("missing art path returned a texture")
	_PlayerSettings.texture_set = "original"
	_TextureSet.clear_cache()
	print("resolver ok")


func _check_settings() -> void:
	_PlayerSettings.save_settings(_PlayerSettings.defaults())
	var loaded: Dictionary = _PlayerSettings.load_settings()
	if str(loaded.get("texture_set", "")) != "original" or _PlayerSettings.texture_set != "original":
		_fail("default texture set is not original")
	var data := _PlayerSettings.load_settings()
	data["texture_set"] = "batch1"
	if not _PlayerSettings.save_settings(data):
		_fail("save batch1 failed")
	loaded = _PlayerSettings.load_settings()
	if _PlayerSettings.texture_set != "batch1" or str(loaded.get("texture_set", "")) != "batch1":
		_fail("batch1 did not round-trip")
	data = _PlayerSettings.load_settings()
	data["texture_set"] = "nope"
	_PlayerSettings.save_settings(data)
	loaded = _PlayerSettings.load_settings()
	if _PlayerSettings.texture_set != "original":
		_fail("invalid texture set was kept")
	data = loaded
	data["texture_set"] = "original"
	_PlayerSettings.save_settings(data)
	_PlayerSettings.runtime_applied = true
	var menu := _SettingsMenu.new()
	root.add_child(menu)
	await process_frame
	var option := menu.find_child("TextureSet", true, false) as OptionButton
	if option == null:
		_fail("settings texture set control missing")
		return
	if option.get_item_text(0) != "Original" or option.get_item_text(1) != "Batch 1":
		_fail("texture set labels")
	if option.selected != 0:
		_fail("settings opened off Original")
	option.select(1)
	menu._persist()
	if _PlayerSettings.texture_set != "batch1":
		_fail("settings did not persist batch1")
	var written = JSON.parse_string(FileAccess.get_file_as_string(_TEST_PATH))
	if not (written is Dictionary) or str(written.get("texture_set", "")) != "batch1":
		_fail("settings file missing batch1")
	option.select(0)
	menu._persist()
	if _PlayerSettings.texture_set != "original":
		_fail("settings did not restore original")
	menu.queue_free()
	print("settings round-trip ok")


func _check_corruption_hook() -> void:
	var wx := 8400
	var wz := 8401
	_FeatureRegistry.clear_feature(wx, wz)
	_FeatureRegistry.register_feature(wx, wz, int(_FeatureKinds.FeatureKind.BUSH), {
		"plant_id": "crystal_bush",
		"original_plant": "bush",
		"original_stage": 1,
		"growth_stage": 0,
		"corrupt": true,
	})
	var layer: Node = _FeatureLayer.new()
	_PlayerSettings.texture_set = "original"
	_TextureSet.clear_cache()
	var hidden: Texture2D = layer._corrupted_texture(wx, wz, &"crystal_bush", 0)
	if hidden != null:
		_fail("original set returned a corrupted texture")
	_PlayerSettings.texture_set = "batch1"
	_TextureSet.clear_cache()
	var shown: Texture2D = layer._corrupted_texture(wx, wz, &"crystal_bush", 0)
	if shown == null or not str(shown.get_meta("cs_art_path", "")).ends_with("corrupted_bush_s1.png"):
		_fail("batch1 corrupt cell did not use corrupted_bush_s1")
	_FeatureRegistry.register_feature(wx, wz, int(_FeatureKinds.FeatureKind.BUSH), {
		"plant_id": "bush",
		"growth_stage": 1,
		"corrupt": false,
	})
	var healthy: Texture2D = layer._corrupted_texture(wx, wz, &"bush", 1)
	if healthy != null:
		_fail("healthy cell returned a corrupted texture")
	_FeatureRegistry.clear_feature(wx, wz)
	_PlayerSettings.texture_set = "original"
	_TextureSet.clear_cache()
	layer.free()
	print("corruption hook ok")


func _check_blueprint_on_batch() -> void:
	var bp := root.get_node_or_null("TextureBlueprint")
	if bp == null or not bp.has_method("set_enabled"):
		_fail("TextureBlueprint autoload missing")
		return
	_PlayerSettings.texture_set = "batch1"
	_TextureSet.clear_cache()
	bp.set_enabled(false)
	var source := _TextureSet.resolve("res://assets/art/items/herb.png")
	if source == null:
		_fail("herb batch texture missing")
		return
	var sprite := Sprite2D.new()
	sprite.name = "BatchBlueprintSprite"
	sprite.texture = source
	root.add_child(sprite)
	var before_w := source.get_width()
	var before_path := str(source.get_meta("cs_art_path", ""))
	bp.set_enabled(true)
	await process_frame
	var swapped: Texture2D = sprite.texture
	if swapped == null or not swapped.has_meta("cs_blueprint"):
		_fail("blueprint did not cover the batch texture")
	elif swapped.get_width() != before_w or swapped.get_height() != source.get_height():
		_fail("blueprint size drifted")
	bp.set_enabled(false)
	var restored: Texture2D = sprite.texture
	if restored == null or str(restored.get_meta("cs_art_path", "")) != before_path:
		_fail("blueprint restore lost the batch texture")
	elif bool(restored.has_meta("cs_blueprint")):
		_fail("blueprint flag left on the restored texture")
	sprite.queue_free()
	_PlayerSettings.texture_set = "original"
	_TextureSet.clear_cache()
	print("blueprint on batch ok")


func _restore_settings() -> void:
	_PlayerSettings.texture_set = "original"
	_PlayerSettings.texture_blueprint = false
	_TextureSet.clear_cache()
	var bp := root.get_node_or_null("TextureBlueprint")
	if bp != null and bp.has_method("set_enabled"):
		bp.set_enabled(false)
	_PlayerSettings.settings_path = _old_settings_path
	_PlayerSettings.load_settings()


func _read_manifest() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://docs/texture_manifest.json"))
	if parsed is Dictionary:
		return parsed
	_fail("manifest json did not parse")
	return {}


func _load_res(res_path: String) -> Image:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var image := Image.load_from_file(abs_path)
	if image == null or image.is_empty():
		return null
	return image


func _audit(image: Image, want_magenta: bool) -> String:
	var w := image.get_width()
	var h := image.get_height()
	var colors := {}
	var opaque := 0
	var edge_dark := 0
	var partial := 0
	var magenta := 0
	for y in h:
		for x in w:
			var c := image.get_pixel(x, y)
			if c.a > 0.04 and c.a < 0.96:
				partial += 1
			if c.a < 0.5:
				continue
			opaque += 1
			var r8 := int(round(c.r * 255.0))
			var g8 := int(round(c.g * 255.0))
			var b8 := int(round(c.b * 255.0))
			colors["%d,%d,%d" % [r8, g8, b8]] = true
			if r8 >= 240 and g8 <= 80 and b8 >= 160:
				magenta += 1
			var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			if lum > 0.25:
				continue
			var clear_n := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + int(d.x)
				var ny: int = y + int(d.y)
				if nx < 0 or ny < 0 or nx >= w or ny >= h or image.get_pixel(nx, ny).a < 0.5:
					clear_n = true
					break
			if clear_n:
				edge_dark += 1
	if opaque < 40:
		return "opaque %d" % opaque
	if colors.size() > _MAX_COLORS:
		return "palette %d" % colors.size()
	if partial > 0:
		return "partial alpha"
	if edge_dark < 8:
		return "outline %d" % edge_dark
	if image.get_pixel(0, 0).a > 0.1 or image.get_pixel(w - 1, 0).a > 0.1:
		return "corner"
	if image.get_pixel(0, h - 1).a > 0.1 or image.get_pixel(w - 1, h - 1).a > 0.1:
		return "corner"
	if want_magenta and magenta < 1:
		return "no magenta glow"
	return ""
