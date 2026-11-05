class_name TextureSet
extends RefCounted

const _PlayerSettings = preload("res://systems/player_settings.gd")
const _VoxelTypes = preload("res://helpers/voxel_types.gd")

const ORIGINAL := "original"
const BATCH1 := "batch1"
const ART_PREFIX := "res://assets/art/"
const BATCH_PREFIX := "res://assets/art_batch1/"

static var _cache: Dictionary = {}


static func face_tile(tile_type: int, face_code: int, world_x: int, world_z: int) -> Vector2i:
	return _VoxelTypes.face_atlas(tile_type, face_code, world_x, world_z)


static func current() -> String:
	return BATCH1 if _PlayerSettings.texture_set == BATCH1 else ORIGINAL


static func is_batch1() -> bool:
	return current() == BATCH1


static func batch_path(path: String) -> String:
	if not path.begins_with(ART_PREFIX):
		return ""
	return BATCH_PREFIX + path.substr(ART_PREFIX.length())


static func resolved_path(path: String) -> String:
	if not is_batch1():
		return path
	var alt := batch_path(path)
	if alt.is_empty() or not _exists(alt):
		return path
	return alt


static func resolve(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var chosen := resolved_path(path)
	var tex: Texture2D = _cache.get(chosen) as Texture2D
	if tex == null:
		tex = _load_path(chosen)
		if tex == null and chosen != path:
			tex = _load_path(path)
			chosen = path
		if tex == null:
			return null
		_cache[chosen] = tex
	tex.set_meta("cs_art_path", chosen)
	tex.set_meta("cs_texture_set", current())
	return tex


static func clear_cache() -> void:
	_cache.clear()


static func refresh_live(tree: SceneTree) -> void:
	if tree == null:
		return
	var saved_blueprint := _PlayerSettings.texture_blueprint
	var bp := tree.root.get_node_or_null("TextureBlueprint")
	var was_on := bp != null and bool(bp.get("enabled"))
	if was_on and bp.has_method("set_enabled"):
		bp.set_enabled(false)
	_PlayerSettings.texture_blueprint = saved_blueprint
	clear_cache()
	var registry := tree.get_first_node_in_group("game_visual_registry")
	if registry != null and registry.has_method("reload_texture_set"):
		registry.reload_texture_set()
	for node in tree.get_nodes_in_group("world_entity"):
		if node.has_method("refresh_visual"):
			node.refresh_visual()
	var layer := tree.get_first_node_in_group("feature_visual_layer")
	if layer != null and layer.has_method("refresh_texture_set"):
		layer.refresh_texture_set()
	var hotbar := tree.root.find_child("Hotbar", true, false)
	if hotbar != null and hotbar.has_method("_refresh"):
		hotbar._refresh()
	var bag := tree.root.find_child("InventoryPanel", true, false)
	if bag != null and bag.has_method("_refresh"):
		bag._refresh()
	for node in tree.get_nodes_in_group("texture_set_sprite"):
		_rebind_request(node)
	if saved_blueprint and bp != null and bp.has_method("set_enabled"):
		bp.set_enabled(true)
	_PlayerSettings.texture_blueprint = saved_blueprint


static func _rebind_request(node: Node) -> void:
	if node == null or not node.has_meta("cs_texture_request"):
		return
	var tex := resolve(str(node.get_meta("cs_texture_request")))
	if tex == null or not ("texture" in node):
		return
	node.set("texture", tex)


static func _exists(path: String) -> bool:
	if ResourceLoader.exists(path):
		return true
	return FileAccess.file_exists(ProjectSettings.globalize_path(path))


static func _load_path(path: String) -> Texture2D:
	if path.is_empty() or not _exists(path):
		return null
	if ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		if loaded != null:
			return loaded
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	var tex := ImageTexture.create_from_image(image)
	tex.resource_path = path
	return tex
