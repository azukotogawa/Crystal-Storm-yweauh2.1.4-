extends SceneTree
## Main-scene probe: toggling the texture set swaps live icons and restores them.

const MAIN_SCENE := "res://scenes/main.tscn"
const _ProbeExit = preload("res://scripts/probe_exit.gd")
const _TextureSet = preload("res://helpers/texture_set.gd")
const _PlayerSettings = preload("res://systems/player_settings.gd")

const _TEST_PATH := "user://verify_texture_batch_live.json"
const _HERB := "res://assets/art/items/herb.png"

var _failed: int = 0
var _game: Node = null
var _old_settings_path: String = ""


func _init() -> void:
	if OS.get_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT").is_empty():
		OS.set_environment("CRYSTALSTORM_PROBE_ABRUPT_EXIT", "1")
	if OS.get_environment("CRYSTALSTORM_BAKE_RADIUS").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_RADIUS", "2")
	if OS.get_environment("CRYSTALSTORM_FULL_WORLD_BAKE").is_empty():
		OS.set_environment("CRYSTALSTORM_FULL_WORLD_BAKE", "0")
	if OS.get_environment("CRYSTALSTORM_BAKE_ON_NEW").is_empty():
		OS.set_environment("CRYSTALSTORM_BAKE_ON_NEW", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failed += 1
	push_error(msg)
	print("FAIL %s" % msg)


func _run() -> void:
	_old_settings_path = _PlayerSettings.settings_path
	_PlayerSettings.settings_path = _TEST_PATH
	_PlayerSettings.save_settings(_PlayerSettings.defaults())
	_PlayerSettings.tutorial_completed = true
	var packed: PackedScene = load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("no main scene")
		_finish()
		return
	_game = packed.instantiate()
	root.add_child(_game)
	var compose = _game.get_node_or_null("CompositionRoot")
	var frames := 0
	while frames < 3600:
		_PlayerSettings.tutorial_completed = true
		if compose != null and int(compose.stage) >= compose.Stage.INITIAL_STREAM_READY:
			break
		await process_frame
		frames += 1
	if compose == null or int(compose.stage) < compose.Stage.INITIAL_STREAM_READY:
		_fail("start region not ready")
		_finish()
		return
	for _settle in 30:
		await process_frame
		_PlayerSettings.tutorial_completed = true
	_hide_tutorial()
	var icon := await _wait_icon()
	if icon == null or icon.texture == null:
		_fail("hotbar icon missing")
		_finish()
		return
	var original_path := str(icon.texture.get_meta("cs_art_path", ""))
	var original_sig := _sig(icon.texture)
	if not original_path.begins_with("res://assets/art/"):
		_fail("hotbar did not start on original art (%s)" % original_path)
	var probe := Sprite3D.new()
	probe.name = "TextureSetProbe"
	probe.add_to_group("texture_set_sprite")
	probe.set_meta("cs_texture_request", _HERB)
	probe.texture = _TextureSet.resolve(_HERB)
	probe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(probe)
	var herb_original := str(probe.texture.get_meta("cs_art_path", "")) if probe.texture else ""
	_PlayerSettings.texture_set = "batch1"
	_TextureSet.refresh_live(self)
	for _i in 4:
		await process_frame
	var batch_path := str(icon.texture.get_meta("cs_art_path", "")) if icon.texture else ""
	var batch_sig := _sig(icon.texture)
	if not batch_path.begins_with("res://assets/art_batch1/"):
		_fail("hotbar did not swap to batch1 (%s)" % batch_path)
	if batch_sig == original_sig:
		_fail("hotbar image did not change")
	var herb_batch := str(probe.texture.get_meta("cs_art_path", "")) if probe.texture else ""
	if not herb_batch.begins_with("res://assets/art_batch1/"):
		_fail("probe sprite did not swap (%s)" % herb_batch)
	_PlayerSettings.texture_set = "original"
	_TextureSet.refresh_live(self)
	for _j in 4:
		await process_frame
	var restored_path := str(icon.texture.get_meta("cs_art_path", "")) if icon.texture else ""
	var restored_sig := _sig(icon.texture)
	if restored_path != original_path or restored_sig != original_sig:
		_fail("hotbar did not restore (%s)" % restored_path)
	var herb_restored := str(probe.texture.get_meta("cs_art_path", "")) if probe.texture else ""
	if herb_restored != herb_original:
		_fail("probe sprite did not restore (%s)" % herb_restored)
	if _failed == 0:
		print("live swap %s -> %s -> %s" % [original_path, batch_path, restored_path])
	_finish()


func _wait_icon() -> TextureRect:
	var icon: TextureRect = null
	for _i in 180:
		icon = _hotbar_icon()
		if icon != null and icon.texture != null and icon.texture.has_meta("cs_art_path"):
			return icon
		await process_frame
	return icon


func _hotbar_icon() -> TextureRect:
	var hotbar := root.find_child("Hotbar", true, false)
	if hotbar == null:
		return null
	var icons = hotbar.get("_icon_nodes")
	if icons is Array and not (icons as Array).is_empty():
		return (icons as Array)[0] as TextureRect
	return hotbar.find_child("Icon", true, false) as TextureRect


func _hide_tutorial() -> void:
	_PlayerSettings.tutorial_completed = true
	if ClassDB.class_exists("TutorialOverlay"):
		TutorialOverlay.dismiss()
	for node in get_nodes_in_group("loading_screen"):
		if node is CanvasItem:
			(node as CanvasItem).visible = false


func _sig(tex: Texture2D) -> String:
	if tex == null:
		return ""
	var image := tex.get_image()
	if image == null:
		return ""
	var opaque := 0
	var acc := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			opaque += 1
			acc = (acc * 33 + int(c.r * 255.0) + int(c.g * 255.0) * 3 + int(c.b * 255.0) * 7) & 0x7fffffff
	return "%d:%d" % [opaque, acc]


func _finish() -> void:
	_PlayerSettings.texture_set = "original"
	_PlayerSettings.texture_blueprint = false
	_TextureSet.clear_cache()
	_PlayerSettings.settings_path = _old_settings_path
	if _failed > 0:
		print("Texture batch live tests failed: %d" % _failed)
		quit(1)
		return
	_ProbeExit.finish_tree(self, 0, "All texture batch live tests OK")
