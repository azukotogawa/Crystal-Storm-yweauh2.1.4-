@tool
extends VBoxContainer

const _GenConfig = preload("res://config/crystal_texture_gen_config.gd")
const _GeneratorScript = preload("res://systems/crystal_texture_generator.gd")

@onready var _config_path: LineEdit = %ConfigPath
@onready var _variant_count: SpinBox = %VariantCount
@onready var _status: Label = %StatusLabel
@onready var _preview: TextureRect = %PreviewRect

var _generator  # CrystalTextureGenerator autoload or script instance
var _config: _GenConfig


func _ready() -> void:
	_generator = get_node_or_null("/root/CrystalTextureGenerator")
	if _generator == null:
		_generator = _GeneratorScript.new()
	_config = _GenConfig.create_default()
	_generator.set_config(_config)
	if _config_path:
		_config_path.text = "res://config/default_texture_gen.tres"


func _on_generate_crystal_variants_pressed() -> void:
	_set_status("Generating crystal variants…")
	var count := int(_variant_count.value) if _variant_count else 4
	var textures: Array = _generator.generate_crystal_variants(count)
	if not textures.is_empty() and _preview:
		_preview.texture = textures[0]
	_set_status("Generated %d crystal textures." % textures.size())


func _on_export_sprite_sheet_pressed() -> void:
	_set_status("Exporting sprite sheet…")
	var path: String = _generator.export_sprite_sheet(&"", int(_variant_count.value))
	_set_status("Exported: %s" % path)


func _on_export_game_visuals_pressed() -> void:
	_set_status("Exporting full game visual bundle…")
	if not _generator.has_method("export_game_visual_bundle"):
		_set_status("Generator missing export_game_visual_bundle")
		return
	var path: String = _generator.export_game_visual_bundle()
	_set_status("Exported game visuals: %s" % path)
	if _preview:
		var tex: Texture2D = _generator.generate_texture(_GeneratorScript.Category.CRYSTAL, &"amethyst")
		_preview.texture = tex


func _on_export_palettes_json_pressed() -> void:
	var path := "user://texture_palettes.json"
	var err: Error = _generator.export_all_palettes_json(path)
	_set_status("Palette JSON export: %s (err %d)" % [path, err])


func _on_import_palettes_json_pressed() -> void:
	var path := "user://texture_palettes.json"
	if _generator.import_palettes_json(path):
		_set_status("Imported palettes from %s" % path)
	else:
		_set_status("Import failed — check %s" % path)


func _on_preview_biome_pressed() -> void:
	if _preview:
		_preview.texture = _generator.generate_texture(_GeneratorScript.Category.BIOME, &"forest")


func _on_preview_ore_pressed() -> void:
	if _preview:
		_preview.texture = _generator.generate_texture(_GeneratorScript.Category.ORE, &"crystal_ore")


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
	print("[CrystalTextureTools] ", text)
