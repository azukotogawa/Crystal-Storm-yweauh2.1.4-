class_name CrystalTextureGenConfig
extends Resource

const _Palette = preload("res://config/crystal_texture_palette.gd")

## Inspector-tunable parameters for CrystalTextureGenerator.
## Create a .tres from this resource to tune generation without editing code.

@export_group("Global")
@export var master_seed: int = 424242
@export var default_texture_size: int = 64
@export var use_mipmaps: bool = true
@export var use_linear_filter: bool = true

@export_group("Noise")
@export var noise_frequency: float = 0.08
@export var detail_frequency: float = 0.35
@export var ridge_weight: float = 0.42
@export var cellular_weight: float = 0.28
@export var warp_strength: float = 0.55

@export_group("Crystal Animation")
@export var crystal_frame_count: int = 8
@export var crystal_pulse_speed: float = 1.0
@export var particle_frame_count: int = 6

@export_group("Sprite Sheet Export")
@export var sheet_columns: int = 4
@export var sheet_padding: int = 2
@export var export_path: String = "user://generated_textures/"

@export_group("Palettes")
@export var crystal_palettes: Array = []
@export var biome_palettes: Array = []
@export var ore_palettes: Array = []
@export var ground_palettes: Array = []


func ensure_default_palettes() -> void:
	if crystal_palettes.is_empty():
		crystal_palettes = _builtin_crystal_palettes()
	if biome_palettes.is_empty():
		biome_palettes = _builtin_biome_palettes()
	if ore_palettes.is_empty():
		ore_palettes = _builtin_ore_palettes()
	if ground_palettes.is_empty():
		ground_palettes = _builtin_ground_palettes()


static func create_default():
	var cfg = load("res://config/crystal_texture_gen_config.gd").new()
	cfg.ensure_default_palettes()
	return cfg


static func _builtin_crystal_palettes() -> Array:
	return [
		_make_palette(&"amethyst", "Amethyst", Color(0.62, 0.18, 0.98), Color(0.35, 0.08, 0.72), Color(0.9, 0.6, 1.0)),
		_make_palette(&"void_shard", "Void Shard", Color(0.22, 0.05, 0.38), Color(0.08, 0.02, 0.18), Color(0.55, 0.2, 0.95)),
		_make_palette(&"solar_crystal", "Solar Crystal", Color(0.98, 0.55, 0.18), Color(0.72, 0.28, 0.08), Color(1.0, 0.85, 0.45)),
	]


static func _builtin_biome_palettes() -> Array:
	return [
		_make_palette(&"plains", "Plains", Color(0.45, 0.72, 0.32), Color(0.32, 0.55, 0.22), Color(0.62, 0.82, 0.42), 0.1, 0.05),
		_make_palette(&"forest", "Forest", Color(0.18, 0.42, 0.22), Color(0.1, 0.28, 0.14), Color(0.32, 0.55, 0.28), 0.08, 0.05),
		_make_palette(&"marsh", "Marsh", Color(0.28, 0.38, 0.22), Color(0.18, 0.28, 0.16), Color(0.42, 0.52, 0.32), 0.12, 0.08),
		_make_palette(&"highland", "Highland", Color(0.55, 0.52, 0.48), Color(0.38, 0.36, 0.34), Color(0.72, 0.68, 0.62), 0.05, 0.15),
	]


static func _builtin_ore_palettes() -> Array:
	return [
		_make_palette(&"iron", "Iron Ore", Color(0.48, 0.46, 0.44), Color(0.28, 0.26, 0.24), Color(0.72, 0.68, 0.62), 0.05, 0.55),
		_make_palette(&"copper", "Copper Ore", Color(0.62, 0.38, 0.22), Color(0.42, 0.24, 0.14), Color(0.85, 0.55, 0.28), 0.12, 0.42),
		_make_palette(&"crystal_ore", "Crystal Ore", Color(0.55, 0.22, 0.82), Color(0.32, 0.1, 0.55), Color(0.85, 0.45, 1.0), 0.55, 0.35),
	]


static func _builtin_ground_palettes() -> Array:
	return [
		_make_palette(&"dirt", "Dirt", Color(0.42, 0.28, 0.18), Color(0.28, 0.18, 0.12), Color(0.55, 0.38, 0.25), 0.02, 0.0),
		_make_palette(&"stone", "Stone", Color(0.52, 0.5, 0.48), Color(0.35, 0.34, 0.32), Color(0.68, 0.66, 0.62), 0.02, 0.12),
		_make_palette(&"sand", "Sand", Color(0.82, 0.72, 0.48), Color(0.68, 0.58, 0.38), Color(0.92, 0.85, 0.62), 0.04, 0.0),
	]


static func _make_palette(
	id: StringName,
	label: String,
	primary: Color,
	secondary: Color,
	accent: Color,
	glow: float = 0.45,
	iridescence: float = 0.35
) -> _Palette:
	var p := _Palette.new()
	p.id = id
	p.display_name = label
	p.primary = primary
	p.secondary = secondary
	p.accent = accent
	p.shadow = secondary.darkened(0.35)
	p.glow_color = accent
	p.glow_strength = glow
	p.iridescence_strength = iridescence
	return p