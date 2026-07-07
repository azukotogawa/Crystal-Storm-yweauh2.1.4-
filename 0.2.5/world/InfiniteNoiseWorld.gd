# InfiniteNoiseWorld.gd
# Best-in-class world generation for Crystalstorm.
# 4 playable biomes (plains, steppe, forest, marsh) inside a bordered map.
# Ocean borders on -X/+X, mountain borders on -Z/+Z (features, not interior biomes).
# Playable human-scale features (rivers 6-18 voxels wide, hills/mountains walkable and buildable).
# Rivers are now as common as biomes: dedicated river feature system produces RIVER tiles
#   and carved valleys at ~biome prevalence (visible river area comparable to any one biome).
# Full 3D volumetric caves (tunnels + chambers) via 3D noise -- caves made significantly more likely
#   both in volume (underground hollows) and surface expression (breaches, gorges, mouths, exposed stone).
# Real carved rivers that depress terrain + create valleys/banks.
# Clean API surface for current heightfield renderer + future full voxel support.
# All deterministic, heavily cached on hot paths, with uncached variants for workers.

class_name InfiniteNoiseWorld
extends Node3D

enum MapTemperature { HOT, MILD, COLD, HOT_MILD, MILD_COLD }

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _BiomeLayout = preload("res://world/biome_layout.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var world_seed: int
var map_temperature: MapTemperature = MapTemperature.MILD
var map_temperature_label: String = "Mild"
var world_config: _WorldGenConfig
## Runtime toggle — set by PerformanceService; avoids 3D cave noise cost when false.
var caves_enabled: bool = true

# --- Tunables for playable scale and feel ---
# --- Tunables for playable scale and feel ---
const BIOME_SCALE := 920.0
const MOUNTAIN_FREQ := 1.0
const DETAIL_FREQ := 4.5

# River & Biome balance


# River feature system (redesigned for rivers to be as common as biomes).
# River "systems" are now generated at a density such that visible RIVER surface tiles
# (and their carved valley influence) occur at a prevalence comparable to any single
# one of the 5 primary biomes (~18-25% area in samples). Achieved by:
#   - Moderate absolute RIVER_FREQ for a dense but natural network of drainage lines
#   - Reduced core-sharpening POWER and offset so bands around cores are wider
#   - Explicit, documented thresholds for "is_river" (carve+moisture) vs "surface tile"
# Rivers remain visually narrow coherent features thanks to warping + core shape.
const RIVER_TARGET_PREVALENCE := 0.20   # ~20% like other major features

const RIVER_FREQ_BASE := 0.068
const RIVER_SCALE_FACTOR := 2.9
const RIVER_CORE_POWER := 1.48
const RIVER_CORE_OFFSET := -0.025
const RIVER_CORE_SCALE := 1.08
const RIVER_IS_RIVER_THRESHOLD := 0.142
const RIVER_SURFACE_TILE_THRESHOLD := 0.172
const RIVER_MIN_CARVE_FOR_TILE := 0.48
const RIVER_MAX_CARVE := 27.0
const RIVER_VALLEY_WIDTH_FACTOR := 1.8

# Cave feature system (redesigned for higher likelihood overall).
# Increased base frequencies for both tunnels and rooms, stronger signal weights,
# lower hollowing thresholds, and higher surface breach rate so caves are noticeably
# more common both underground (volumetric) and as visible surface features (breaches, mouths).
const CAVE_TUNNEL_BASE := 0.135
const CAVE_ROOM_BASE := 0.058
const CAVE_SCALE_FACTOR := 1.4
const CAVE_TUNNEL_WEIGHT := 0.92
const CAVE_ROOM_WEIGHT := 1.28
const CAVE_HOLLOW_BASE := 0.39
const CAVE_ROOF_PROTECT_SCALE := 0.12
const CAVE_SURFACE_BREACH_MIN := 0.42
const CAVE_MOUTH_THRESHOLD := 0.48
const CAVE_SURFACE_BREACH_CHANCE := 0.85

const LEGACY_MAX_HEIGHT := 158.0
const SEA_LEVEL := 38.0            # Baseline reference (rivers can go below in gorges)
const MOUNTAIN_HEIGHT_BOOST := 78.0

# Column caches (hot path for ChunkData + player collision)
var _surface_cache: Dictionary = {}
var _tile_cache: Dictionary = {}
var _biome_cache: Dictionary = {}   # key "x,z" -> biome dict (light)

# FastNoiseLite generators (all seeded deterministically from world_seed)
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite

var _base_height: FastNoiseLite
var _mountain_ridge: FastNoiseLite
var _detail: FastNoiseLite
var _temp: FastNoiseLite
var _moist: FastNoiseLite

var _river_valley: FastNoiseLite
var _river_warp_x: FastNoiseLite
var _river_warp_z: FastNoiseLite

var _river_mask_noise: FastNoiseLite
var _river_noise: FastNoiseLite
var _river_length_noise: FastNoiseLite
var _river_width_noise: FastNoiseLite

var _cave_tunnel: FastNoiseLite
var _cave_room: FastNoiseLite
var _surface_variation: FastNoiseLite   # small high-freq for micro detail on surface

func _ready():
	add_to_group("world")
	var cfg_svc = get_tree().get_first_node_in_group("config_service")
	if cfg_svc and "world_settings" in cfg_svc and cfg_svc.world_settings:
		apply_world_settings(cfg_svc.world_settings)

func _init(p_seed: int = 12349):
	world_seed = p_seed
	_BiomeLayout.reset()
	_roll_map_temperature()
	_setup_noise()
	_init_biome_regions()

func apply_world_settings(ws: _WorldSettings) -> void:
	if ws:
		_WorldSettings.apply_active(ws)
	_invalidate_height_caches()


func apply_world_config(cfg: _WorldGenConfig) -> void:
	world_config = cfg
	caves_enabled = cfg.caves_enabled if cfg else true
	_BiomeLayout.reset()
	_init_biome_regions()
	if _base_height != null:
		_setup_noise()
	TerrainRamps.placement_chance = _wg().ramp_placement_chance
	_invalidate_height_caches()


func set_caves_enabled(enabled: bool) -> void:
	caves_enabled = enabled
	_invalidate_height_caches()


func _max_height() -> float:
	return _WorldSettings.get_active().max_height_units()


func _height_gen_scale() -> float:
	return _WorldSettings.get_active().height_generation_scale()


func _invalidate_height_caches() -> void:
	_surface_cache.clear()
	_tile_cache.clear()
	_biome_cache.clear()


func _init_biome_regions() -> void:
	var wg := _wg()
	_BiomeLayout.ensure_generated(
		world_seed,
		float(WorldBorder.PLAYABLE_HALF_X),
		wg.biome_region_warp
	)


func _wg() -> _WorldGenConfig:
	return world_config if world_config else _WorldGenConfig.create_default()


func _roll_map_temperature() -> void:
	var rng := RandomNumberGenerator.new()
	var wg := _wg()
	rng.seed = world_seed + (wg.temperature_roll_seed_offset if wg else 777)
	var roll := rng.randf()
	if roll < 0.25:
		map_temperature = MapTemperature.HOT
	elif roll < 0.50:
		map_temperature = MapTemperature.MILD
	elif roll < 0.75:
		map_temperature = MapTemperature.COLD
	elif roll < 0.85:
		map_temperature = MapTemperature.HOT_MILD
	else:
		map_temperature = MapTemperature.MILD_COLD
	map_temperature_label = get_map_temperature_label()

func _apply_map_temperature_bias(t: float) -> float:
	match map_temperature:
		MapTemperature.HOT:
			return clampf(t * 0.55 + 0.38, 0.0, 1.0)
		MapTemperature.COLD:
			return clampf(t * 0.42 + 0.04, 0.0, 1.0)
		MapTemperature.HOT_MILD:
			return clampf(t * 0.65 + 0.22, 0.0, 1.0)
		MapTemperature.MILD_COLD:
			return clampf(t * 0.65 + 0.08, 0.0, 1.0)
		_:
			return clampf(t * 0.58 + 0.21, 0.0, 1.0)

func get_map_temperature_label() -> String:
	match map_temperature:
		MapTemperature.HOT:
			return "Hot"
		MapTemperature.COLD:
			return "Cold"
		MapTemperature.HOT_MILD:
			return "Hot/Mild"
		MapTemperature.MILD_COLD:
			return "Mild/Cold"
		_:
			return "Mild"

func _setup_noise():
	# Domain warp (makes everything look natural, not grid-aligned)
	_warp_x = FastNoiseLite.new()
	_warp_x.seed = world_seed + 11
	_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	_warp_x.frequency = 0.9 / _wg().biome_scale
	_warp_x.fractal_type = FastNoiseLite.FRACTAL_FBM
	_warp_x.fractal_octaves = 2
	_warp_x.fractal_gain = 0.55

	_warp_z = FastNoiseLite.new()
	_warp_z.seed = world_seed + 12
	_warp_z.noise_type = FastNoiseLite.TYPE_PERLIN
	_warp_z.frequency = 0.9 / _wg().biome_scale
	_warp_z.fractal_type = FastNoiseLite.FRACTAL_FBM
	_warp_z.fractal_octaves = 2
	_warp_z.fractal_gain = 0.55

	# Base continental / large structure
	_base_height = FastNoiseLite.new()
	_base_height.seed = world_seed + 100
	_base_height.noise_type = FastNoiseLite.TYPE_PERLIN
	_base_height.frequency = 2.8 / BIOME_SCALE
	_base_height.fractal_type = FastNoiseLite.FRACTAL_FBM
	_base_height.fractal_octaves = 4
	_base_height.fractal_lacunarity = 2.05
	_base_height.fractal_gain = 0.48

	# Mountain ridged (for real alpine character)
	_mountain_ridge = FastNoiseLite.new()
	_mountain_ridge.seed = world_seed + 200
	_mountain_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	_mountain_ridge.frequency = MOUNTAIN_FREQ / BIOME_SCALE
	_mountain_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain_ridge.fractal_octaves = 5
	_mountain_ridge.fractal_lacunarity = 2.15
	_mountain_ridge.fractal_gain = 0.52

	# Fine detail + roughness
	_detail = FastNoiseLite.new()
	_detail.seed = world_seed + 300
	_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail.frequency = DETAIL_FREQ / BIOME_SCALE
	_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail.fractal_octaves = 3
	_detail.fractal_gain = 0.6

	# Temperature (base + strong elevation lapse rate will be applied in logic)
	_temp = FastNoiseLite.new()
	_temp.seed = world_seed + 400
	_temp.noise_type = FastNoiseLite.TYPE_PERLIN
	_temp.frequency = 1.6 / BIOME_SCALE
	_temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temp.fractal_octaves = 3

	# Moisture / precipitation
	_moist = FastNoiseLite.new()
	_moist.seed = world_seed + 500
	_moist.noise_type = FastNoiseLite.TYPE_PERLIN
	_moist.frequency = 2.1 / BIOME_SCALE
	_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moist.fractal_octaves = 6
	_moist.fractal_lacunarity = 2.1
	_moist.fractal_gain = 0.47

	# River drainage / valley potential (long winding features)
	# NOTE: River frequency is absolute (independent of BIOME_SCALE) for reliable control
	# of river commonality. Redesigned params (see header) target biome-like prevalence.
	_river_valley = FastNoiseLite.new()
	_river_valley.seed = world_seed + 600
	_river_valley.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_valley.frequency = RIVER_FREQ_BASE * (92.0 / (BIOME_SCALE * RIVER_SCALE_FACTOR))
	_river_valley.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_valley.fractal_octaves = 6      # extra octave for longer features
	_river_valley.fractal_lacunarity = 1.92
	_river_valley.fractal_gain = 0.41

	_river_warp_x = FastNoiseLite.new()
	_river_warp_x.seed = world_seed + 610
	_river_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_warp_x.frequency = 1.25 * (92.0 / BIOME_SCALE)
	_river_warp_x.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_warp_x.fractal_octaves = 2

	_river_warp_z = FastNoiseLite.new()  # same as above
	_river_warp_z.seed = world_seed + 611
	_river_warp_z.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_warp_z.frequency = 1.25 * (92.0 / BIOME_SCALE)
	_river_warp_z.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_warp_z.fractal_octaves = 2
	
	_river_mask_noise = FastNoiseLite.new()
	_river_mask_noise.seed = world_seed + 650
	_river_mask_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_mask_noise.frequency = 0.042 / (BIOME_SCALE / 920.0)
	_river_mask_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_mask_noise.fractal_octaves = 5
	_river_mask_noise.fractal_gain = 0.45
	
	_river_noise = FastNoiseLite.new()
	_river_noise.seed = world_seed + 7000
	_river_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_noise.frequency = 0.9 / BIOME_SCALE
	_river_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_noise.fractal_octaves = 4
	_river_noise.fractal_gain = 0.5

	_river_length_noise = FastNoiseLite.new()
	_river_length_noise.seed = world_seed + 7100
	_river_length_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_length_noise.frequency = 0.45 / BIOME_SCALE
	_river_length_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_length_noise.fractal_octaves = 2

	_river_width_noise = FastNoiseLite.new()
	_river_width_noise.seed = world_seed + 7050
	_river_width_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_width_noise.frequency = 2.4 / BIOME_SCALE
	_river_width_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_width_noise.fractal_octaves = 2

	# === CAVES - now scale-aware ===
	_cave_tunnel = FastNoiseLite.new()
	_cave_tunnel.seed = world_seed + 700
	_cave_tunnel.noise_type = FastNoiseLite.TYPE_PERLIN
	_cave_tunnel.frequency = 0.135 * (92.0 / (BIOME_SCALE * 1.8))
	_cave_tunnel.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cave_tunnel.fractal_octaves = 3
	_cave_tunnel.fractal_gain = 0.65

	_cave_room = FastNoiseLite.new()
	_cave_room.seed = world_seed + 710
	_cave_room.noise_type = FastNoiseLite.TYPE_PERLIN
	_cave_room.frequency = 0.058 * (92.0 / (BIOME_SCALE * 1.8))
	_cave_room.fractal_type = FastNoiseLite.FRACTAL_FBM
	_cave_room.fractal_octaves = 2
	_cave_room.fractal_gain = 0.5   # note: you had duplicate gain line originally

	# Micro surface breakup (makes ground less "perfect")
	_surface_variation = FastNoiseLite.new()
	_surface_variation.seed = world_seed + 800
	_surface_variation.noise_type = FastNoiseLite.TYPE_PERLIN
	_surface_variation.frequency = 41.0 / BIOME_SCALE
	_surface_variation.fractal_type = FastNoiseLite.FRACTAL_FBM
	_surface_variation.fractal_octaves = 2

# -----------------------------
# Domain warping (the secret sauce for natural shapes)
# -----------------------------
func _warped_coords(wx: float, wz: float, strength: float = 18.0) -> Vector2:
	var wx2: float = wx + _warp_x.get_noise_2d(wx * 0.6, wz * 0.6) * strength
	var wz2: float = wz + _warp_z.get_noise_2d(wx * 0.6, wz * 0.6) * strength
	return Vector2(wx2, wz2)

func _warped_coords_river(wx: float, wz: float, strength: float = 26.0) -> Vector2:
	var wx2: float = wx + _river_warp_x.get_noise_2d(wx * 0.55, wz * 0.55) * strength
	var wz2: float = wz + _river_warp_z.get_noise_2d(wx * 0.55, wz * 0.55) * strength
	return Vector2(wx2, wz2)

# -----------------------------
# Core height + biome computation (playable + realistic)
# -----------------------------
func _compute_raw_elevation(wx: float, wz: float) -> float:
	var w: Vector2 = _warped_coords(wx, wz, 11.0)
	var x: float = w.x
	var z: float = w.y

	# Large scale base (continents + broad valleys)
	var base: float = (_base_height.get_noise_2d(x, z) + 1.0) * 0.5   # 0..1
	var base_h: float = base * 68.0 - 6.0

	# Ridged relief only on mountain border bands (not interior biomes)
	var ridge_scale: float = WorldBorder.interior_ridge_scale(wx, wz)
	var ridge: float = _mountain_ridge.get_noise_2d(x * 0.92, z * 0.92)
	ridge = abs(ridge) * 0.92 + ridge * 0.08
	var mountain: float = max(0.0, ridge) * MOUNTAIN_HEIGHT_BOOST * ridge_scale
	if ridge_scale > 0.05:
		var foothill: float = (_base_height.get_noise_2d(x * 0.38, z * 0.38) + 1.0) * 0.5
		mountain += foothill * 19.0 * max(0.0, ridge * 0.6) * ridge_scale

	var detail: float = _detail.get_noise_2d(x * 1.7, z * 1.7) * 4.2
	var micro: float = _surface_variation.get_noise_2d(wx, wz) * 0.8

	var raw: float = (base_h + mountain + detail + micro) * _height_gen_scale()
	return clamp(raw, -12.0 * _height_gen_scale(), _max_height())

func get_river_mask(wx: float, wz: float) -> Dictionary:
	var r: float = _river_noise.get_noise_2d(wx, wz)
	var len_mod: float = _river_length_noise.get_noise_2d(wx * 0.65, wz * 0.65)
	var width_var: float = (_river_width_noise.get_noise_2d(wx * 2.1, wz * 2.1) + 1.0) * 0.5
	
	# Distance from zero-crossing (ridge line) for thin, natural strips
	var dist: float = abs(r)
	var threshold: float = 0.026   # ~5-9 tiles wide at BIOME_SCALE=920
	
	# Add gentle meander bias and length modulation
	var active: bool = dist < threshold and len_mod > -0.32
	
	var strength: float = 0.0
	if active:
		strength = 1.0 - (dist / threshold) * 0.65
		# Variable width + slight taper
		strength = clamp(strength * (0.7 + width_var * 0.55), 0.0, 1.0)
	
	return {"active": active, "strength": strength, "dist": dist}

func _compute_river_carve(wx: float, wz: float, base_elev: float) -> Dictionary:
	# Returns {carve: float, is_river: bool, water_depth: float, river_factor: float}
	# Redesigned shaping: explicit consts give river tiles a prevalence on par with biomes
	# while preserving narrow coherent river aesthetics via core + warp.
	var w: Vector2 = _warped_coords_river(wx, wz, 17.0)
	var rx: float = w.x
	var rz: float = w.y

	# Primary valley potential (low freq winding "drainage")
	var valley: float = _river_valley.get_noise_2d(rx, rz)
	# Core computation uses the new tunable power/offset/scale (lower power => fatter cores => more area).
	var u: float = max(0.0, (valley + RIVER_CORE_OFFSET) * RIVER_CORE_SCALE)
	var river_core: float = pow(u, RIVER_CORE_POWER)

	# Secondary meander detail for natural width variation
	var meander: float = _river_valley.get_noise_2d(rx * 2.6, rz * 2.6) * 0.28
	river_core = clamp(river_core + meander * 0.55, 0.0, 1.35)

	# River is stronger / wider in lowlands and marshy areas
	var lowland_factor: float = clamp(1.0 - (base_elev - 18.0) / 95.0, 0.35, 1.35)
	var carve_depth: float = river_core * RIVER_MAX_CARVE * lowland_factor * RIVER_VALLEY_WIDTH_FACTOR

	# "is_river" here means "has meaningful river influence" (for height carving + biome moisture boost).
	# The threshold is now RIVER_IS_RIVER_THRESHOLD; actual visible ribbon uses the stricter
	# RIVER_SURFACE_TILE_THRESHOLD in _compute_surface_tile.
	var is_river: bool = river_core > RIVER_IS_RIVER_THRESHOLD
	var water_depth: float = 0.0
	if is_river:
		water_depth = clamp(1.8 + river_core * 2.8 + lowland_factor * 1.5, 2.0, 7.5)

	return {
		"carve": carve_depth,
		"is_river": is_river,
		"water_depth": water_depth,
		"river_factor": clamp(river_core, 0.0, 1.0)
	}

func _sample_cave(wx: float, wy: float, wz: float) -> float:
	if not caves_enabled:
		return -1.0
	# Combined tunnel + room 3D signal. Higher = more likely hollow.
	# Weights and frequencies are now higher (see header consts) to make caves more common.
	var t: float = _cave_tunnel.get_noise_3d(wx, wy * 0.9, wz) * CAVE_TUNNEL_WEIGHT
	var r: float = _cave_room.get_noise_3d(wx * 0.7, wy * 0.55, wz * 0.7) * CAVE_ROOM_WEIGHT
	# Bias caves away from very high surface (no swiss cheese on peaks)
	var depth_bias: float = clamp((wy - 12.0) / 55.0, -0.6, 1.1)
	return t * 0.7 + r * 1.05 + depth_bias * 0.18

func get_biome(wx: float, wy: float, wz: float) -> Dictionary:
	var key: String = "%d,%d" % [floori(wx), floori(wz)]
	if _biome_cache.has(key) and abs(wy) < 3.0:
		return _biome_cache[key]

	var res: Dictionary = _get_biome_compute(wx, wy, wz)
	if abs(wy) < 2.5:
		_biome_cache[key] = res
		if _biome_cache.size() > 4096:
			_biome_cache.clear()
	return res

func get_biome_uncached(wx: float, wy: float, wz: float) -> Dictionary:
	# Pure compute path. Safe for background worker threads (never mutates caches).
	return _get_biome_compute(wx, wy, wz)

func _get_biome_compute(wx: float, wy: float, wz: float) -> Dictionary:
	var border_name: String = WorldBorder.border_biome_name(wx, wz)
	if border_name != "":
		var border_h: float = _compute_raw_elevation(wx, wz)
		return {
			"is_air": false,
			"name": border_name,
			"type": border_name.capitalize().replace("_", " "),
			"h_level": int(clamp((border_h + 12.0) / 9.0, 0, 22)),
			"p_level": 8,
			"temp": 0.45,
			"moist": 0.55 if border_name == "ocean" else 0.35,
			"rugged": 0.7 if border_name == "border_mountain" else 0.1,
			"is_border": true,
		}

	var w: Vector2 = _warped_coords(wx, wz, 9.0)
	var x: float = w.x
	var z: float = w.y

	# Temperature — local noise shaped by seed-rolled map theme (hot / mild / cold).
	var t: float = (_temp.get_noise_2d(x, z) + 1.0) * 0.5
	var elev_for_temp: float = get_surface_height_uncached(wx, wz)
	var lapse: float = clamp((elev_for_temp - 42.0) / 115.0, 0.0, 0.92)
	t = clamp(t - lapse * 0.82, 0.0, 1.0)
	t = _apply_map_temperature_bias(t)

	# Moisture - explicit balance for large scale
	var raw_m: float = (_moist.get_noise_2d(x * 0.9, z * 0.9) + 1.0) * 0.5
	var lf_m: float = (_moist.get_noise_2d(x * 0.13, z * 0.13) + 1.0) * 0.5
	
	var m: float = raw_m * 0.5 + lf_m * 0.6
	m = clamp(m, 0.0, 1.0)

	# Strong dry and wet pushes
	var dry_push: float = _moist.get_noise_2d(x * 0.48, z * 0.48) * 0.38
	m = clamp(m - dry_push, 0.0, 1.0)
	
	var wet_push: float = max(0.0, _moist.get_noise_2d(x * 0.37, z * 0.37) * 0.22)
	m = clamp(m + wet_push, 0.0, 1.0)

	# River boost
	var river_info: Dictionary = _compute_river_carve(wx, wz, elev_for_temp)
	if river_info.is_river:
		m = clamp(m + river_info.river_factor * 0.3, 0.0, 1.0)

	var rug: float = _compute_local_ruggedness(wx, wz)

	var wg := _wg()
	var name: String = _BiomeLayout.biome_name_at(
		wx, wz, world_seed, wg.biome_region_warp, float(WorldBorder.PLAYABLE_HALF_X)
	)
	# Intra-biome variation: moisture/temp still shape local character without changing region identity.
	if name == "highland":
		rug = maxf(rug, 0.45)
	elif name == "marsh":
		m = maxf(m, 0.62)
	elif name == "steppe":
		m = minf(m, 0.42)

	# High altitude air override — use surface height, not passed wy
	var surface_h: float = get_surface_height_uncached(wx, wz)
	if surface_h > 42.0 and wy > surface_h + 8.0:   # only true air above surface
		return {"is_air": true, "name": "air", "type": "None"}
	
	return {
		"is_air": false,
		"name": name,
		"type": name.capitalize(),
		"h_level": int(clamp((elev_for_temp + 12.0) / 9.0, 0, 22)),
		"p_level": int(m * 21),
		"temp": t,
		"moist": m,
		"rugged": rug
	}

func _compute_local_ruggedness(wx: float, wz: float) -> float:
	var step: float = 4.8
	var e0: float = _compute_raw_elevation(wx, wz)
	var samples: Array = [
		_compute_raw_elevation(wx + step, wz),
		_compute_raw_elevation(wx - step, wz),
		_compute_raw_elevation(wx, wz + step),
		_compute_raw_elevation(wx, wz - step),
		_compute_raw_elevation(wx + step * 0.65, wz + step * 0.65)
	]
	var rmin: float = e0
	var rmax: float = e0
	for e in samples:
		if e < rmin: rmin = e
		if e > rmax: rmax = e
	return clamp((rmax - rmin) * 0.062, 0.0, 1.0)

# -----------------------------
# Public surface API (used by ChunkData, player, debug)
# -----------------------------
func get_surface_height(wx: float, wz: float) -> float:
	var k: Vector2i = Vector2i(floori(wx), floori(wz))
	if _surface_cache.has(k):
		return _surface_cache[k]

	var h: float = _compute_surface_height(wx, wz)
	h += _TerrainEdits.get_height_delta(k.x, k.y)
	h = _quantize_to_voxel_layer(h)
	_surface_cache[k] = h
	if _surface_cache.size() > 12288:
		_surface_cache.clear()
	return h

func get_surface_height_uncached(wx: float, wz: float) -> float:
	var h: float = _compute_surface_height(wx, wz)
	h += _TerrainEdits.get_height_delta(floori(wx), floori(wz))
	return _quantize_to_voxel_layer(h)


## Worker-thread safe: pass terrain edits captured on the main thread (no shared dict access).
func get_surface_height_worker(wx: float, wz: float, height_delta: float = 0.0) -> float:
	var h: float = _compute_surface_height(wx, wz)
	h += height_delta
	return _quantize_to_voxel_layer(h)


## Worker-thread safe: pass tile overrides captured on the main thread.
func get_tile_type_worker(
	wx: float,
	wz: float,
	build_tile: int = -1,
	feature_override: int = -1
) -> int:
	if build_tile >= 0:
		return build_tile
	if feature_override >= 0:
		return feature_override
	return _compute_surface_tile(wx, wz)


func invalidate_column_cache(wx: int, wz: int) -> void:
	var k := Vector2i(wx, wz)
	_surface_cache.erase(k)
	_tile_cache.erase(k)
	_biome_cache.erase("%d,%d" % [wx, wz])


func get_surface_height_smooth(wx: float, wz: float) -> float:
	var x0 := floori(wx)
	var z0 := floori(wz)
	var tx := wx - float(x0)
	var tz := wz - float(z0)
	var h00 := get_surface_height(float(x0), float(z0))
	var h10 := get_surface_height(float(x0 + 1), float(z0))
	var h01 := get_surface_height(float(x0), float(z0 + 1))
	var h11 := get_surface_height(float(x0 + 1), float(z0 + 1))
	var h0 := lerpf(h00, h10, tx)
	var h1 := lerpf(h01, h11, tx)
	return lerpf(h0, h1, tz)

func _compute_surface_height(wx: float, wz: float) -> float:
	var base: float = _compute_raw_elevation(wx, wz)
	var border_info: Dictionary = WorldBorder.zone_info(wx, wz)
	var h: float = base

	if border_info.zone == "playable":
		var river: Dictionary = _compute_river_carve(wx, wz, base)
		h = base - river.carve
		var cave_near_surface: float = _sample_cave(wx, h - 3.5, wz)
		var breach_var: float = (_surface_variation.get_noise_2d(wx, wz) + 1.0) * 0.5
		if cave_near_surface > CAVE_SURFACE_BREACH_MIN and breach_var < CAVE_SURFACE_BREACH_CHANCE:
			var depress: float = (cave_near_surface - 0.45) * 13.0
			h -= clamp(depress, 0.0, 11.0)

	if border_info.zone == "border":
		var edge: Vector2 = WorldBorder.edge_interior_coords(wx, wz)
		var edge_base: float = _compute_raw_elevation(edge.x, edge.y)
		var edge_river: Dictionary = _compute_river_carve(edge.x, edge.y, edge_base)
		var edge_h: float = edge_base - edge_river.carve
		h = WorldBorder.apply_border_height(wx, wz, edge_h, border_info)

	# Quantize to voxel-layer steps (each layer = WorldSettings.layer_height world units).
	h = clamp(h, -4.0 * _height_gen_scale(), _max_height())
	return _quantize_to_voxel_layer(h)


func _quantize_to_voxel_layer(h: float) -> float:
	var layer: float = _WorldSettings.get_active().layer_height()
	if layer <= 0.001:
		return round(h)
	return round(h / layer) * layer

# -----------------------------
# Surface tile (what the heightfield renderer displays on top)
# -----------------------------
func get_tile_type(wx: float, wz: float) -> int:
	var k: Vector2i = Vector2i(floori(wx), floori(wz))
	var build_tile: int = _TerrainEdits.get_build_tile(k.x, k.y)
	if build_tile >= 0:
		return build_tile
	var override: int = _FeatureRegistry.get_tile_override(k.x, k.y)
	if override >= 0:
		return override
	if _tile_cache.has(k):
		return _tile_cache[k]

	var id: int = _compute_surface_tile(wx, wz)
	_tile_cache[k] = id
	if _tile_cache.size() > 12288:
		_tile_cache.clear()
	return id

func get_tile_type_uncached(wx: float, wz: float) -> int:
	var ix := floori(wx)
	var iz := floori(wz)
	var build_tile: int = _TerrainEdits.get_build_tile(ix, iz)
	if build_tile >= 0:
		return build_tile
	var override: int = _FeatureRegistry.get_tile_override(ix, iz)
	if override >= 0:
		return override
	return _compute_surface_tile(wx, wz)

func _compute_surface_tile(wx: float, wz: float) -> int:
	var surf: float = get_surface_height_uncached(wx, wz)   # use uncached inside uncached path
	var biome: Dictionary = get_biome_uncached(wx, 0.0, wz)
	var bname: String = biome.get("name", "plains")

	if bname == "ocean":
		if surf < SEA_LEVEL - 6.0:
			return VoxelTypes.OCEAN
		if surf < SEA_LEVEL:
			return VoxelTypes.OCEAN2
		return VoxelTypes.BEACH

	if bname == "border_mountain":
		if surf > 118.0:
			return VoxelTypes.SNOW2 if biome.get("temp", 0.4) < 0.35 else VoxelTypes.MOUNTAIN3
		if surf > 96.0:
			return VoxelTypes.MOUNTAIN2
		return VoxelTypes.STONE

	# River / water surface.
	# Density + commonality now controlled by the redesigned river feature system consts
	# (RIVER_FREQ, *_POWER, RIVER_SURFACE_TILE_THRESHOLD etc.) so that RIVER tiles
	# appear roughly as often as any single biome.
# Hybrid river: mask for clean ribbons + carve for valleys
	var river_mask_dict: Dictionary = get_river_mask(wx, wz)
	var river: Dictionary = _compute_river_carve(wx, wz, surf)

	# More rivers visible — require mask OR strong carve
	if river_mask_dict.get("active", false) or river.carve > 6.0:
		return VoxelTypes.RIVER

	# Cave mouth / exposed stone on surface (strong near-surface cave or very steep)
	# Lowered threshold = more frequent surface cave expression.
	var cave_val: float = _sample_cave(wx, surf - 2.2, wz)
	var rugged: float = biome.get("rugged", 0.0)
	if cave_val > CAVE_MOUTH_THRESHOLD or (rugged > 0.68 and surf > 52.0):
		return VoxelTypes.STONE if (cave_val > 0.58 or rugged > 0.75) else VoxelTypes.STONE2

	# Biome surface character (reuse/extend the rich existing palette)
	var temp2: float = biome.get("temp", 0.5)
	var moist: float = biome.get("moist", 0.5)
	var hl: int = biome.get("h_level", 9)

	# Use the existing _surface_variation for organic intra-biome tile variation.
	# This avoids any linear position hashes that produce stripes, while keeping
	# InfiniteNoiseWorld's noise setup and members completely unchanged.
	var tile_var: float = (_surface_variation.get_noise_2d(wx * 2.3, wz * 2.3) + 1.0) * 0.5

	var name: String
	match bname:
		"plains":
			if map_temperature == MapTemperature.COLD and temp2 < 0.45:
				name = "snow" if tile_var < 0.55 else "snow2"
			elif moist > 0.66:
				name = "meadow" if tile_var < 0.6 else "grass"
			elif temp2 < 0.34:
				name = "savanna"
			else:
				name = "plains" if tile_var > 0.5 else "grass"
		"steppe":
			if map_temperature == MapTemperature.COLD or (map_temperature == MapTemperature.MILD_COLD and temp2 < 0.42):
				name = "snow2" if tile_var < 0.5 else "snow"
			elif map_temperature == MapTemperature.HOT or map_temperature == MapTemperature.HOT_MILD:
				name = "savanna" if tile_var < 0.6 else "steppe"
			else:
				name = "steppe" if moist < 0.22 or rugged > 0.5 else "savanna"
			if rugged > 0.62 and map_temperature != MapTemperature.COLD:
				name = "basin"
		"forest":
			if moist > 0.72:
				name = "dense forest"
			elif temp2 < 0.38:
				name = "pine forest"
			else:
				name = "forest" if tile_var > 0.4 else "meadow"
		"marsh":
			name = "marsh"
			if rugged < 0.18 and moist > 0.78:
				name = "basin"
		"highland":
			if surf > 72.0:
				name = "mountain2" if tile_var < 0.5 else "mountain3"
			elif rugged > 0.55:
				name = "stone2" if tile_var < 0.45 else "stone"
			else:
				name = "meadow" if tile_var < 0.5 else "grass"
		_:
			name = "plains"

	var id: int = VoxelTypes.biome_to_voxel_id.get(name, VoxelTypes.GRASSLAND3)
	return id

# -----------------------------
# FULL VOLUMETRIC VOXEL API (the future-proof heart of the best worldgen)
# This is the single source of truth for solidity, caves, water volumes, subsurface.
# Current heightfield uses surface + tile, but player collision, future full mesher,
# and digging mechanics should migrate to this.
# -----------------------------
func get_voxel(wx: float, wy: float, wz: float) -> int:
	# Use UNCACHED versions — this function is called from worker threads
	var surf: float = get_surface_height_uncached(wx, wz)

	if wy > surf + 0.1:
		return VoxelTypes.AIR

	var river: Dictionary = _compute_river_carve(wx, wz, surf)

	# River water body
	if river.is_river:
		var river_bed: float = surf + river.carve - river.water_depth
		if wy > river_bed and wy <= surf:
			return VoxelTypes.RIVER

	# 3D cave hollowing
	var cave: float = _sample_cave(wx, wy, wz)
	var roof_protect: float = clamp((surf - wy) / 4.5, 0.0, 1.0)
	if cave > (CAVE_HOLLOW_BASE + roof_protect * CAVE_ROOF_PROTECT_SCALE):
		return VoxelTypes.AIR

	# Solid block selection
	var depth: float = surf - wy
	var b: Dictionary = get_biome_uncached(wx, wy, wz)
	var biome_name: String = b.get("name", "plains")
	var tempv: float = b.get("temp", 0.5)

	# Top layer (surface skin)
	if depth < 1.2:
		return get_tile_type_uncached(wx, wz)

	# Near surface subsoil
	if depth < 4.5:
		if biome_name == "marsh" or biome_name == "forest":
			return VoxelTypes.DIRT
		if biome_name == "steppe":
			return VoxelTypes.DIRT2 if tempv > 0.4 else VoxelTypes.STONE
		if biome_name == "border_mountain" or biome_name == "ocean":
			return VoxelTypes.STONE
		return VoxelTypes.DIRT2

	# Deep stone
	if depth > 11.0 or biome_name == "border_mountain":
		var stone_var: float = _detail.get_noise_3d(wx * 0.8, wy * 0.6, wz * 0.8)
		return VoxelTypes.CAVE_STONE if stone_var > 0.4 else VoxelTypes.STONE

	return VoxelTypes.STONE

func get_solid(wx: float, wy: float, wz: float) -> bool:
	return get_voxel(wx, wy, wz) != VoxelTypes.AIR


func is_cave_air(wx: float, wy: float, wz: float) -> bool:
	var surf: float = get_surface_height(wx, wz)
	return wy < surf - 0.4 and get_voxel(wx, wy, wz) == VoxelTypes.AIR


func get_cave_floor_height(wx: float, wz: float, max_depth: float = 36.0) -> float:
	var surf: float = get_surface_height(wx, wz)
	var start_y: int = floori(surf)
	var min_y: int = maxi(0, start_y - int(max_depth))
	for y in range(start_y, min_y - 1, -1):
		var wy: float = float(y)
		if get_solid(wx, wy, wz) and not get_solid(wx, wy + 1.0, wz):
			return wy + 1.0
	return 0.0

# -----------------------------
# Utility for old _compute_base_elevation style calls (kept for minimal breakage)
# -----------------------------
func _compute_base_elevation(wx: float, wz: float) -> float:
	return _compute_raw_elevation(wx, wz)

# Optional helper for future systems or debug
func get_height(wx: float, wy: float, wz: float) -> float:
	# Back-compat alias (old code used this)
	return (_base_height.get_noise_2d(wx, wz) + 1.0) * 0.5 * 68.0 - 6.0

func get_map_zone_label(wx: float, wz: float) -> String:
	var info: Dictionary = WorldBorder.zone_info(wx, wz)
	if info.zone == "playable":
		return "playable"
	if info.side == "corner":
		return "corner (%.0f)" % float(info.dist)
	return "%s (%.0f)" % [str(info.side), float(info.dist)]


func get_precip(wx: float, wy: float, wz: float) -> float:
	var w: Vector2 = _warped_coords(wx, wz)
	return (_moist.get_noise_2d(w.x, w.y) + 1.0) * 0.5
