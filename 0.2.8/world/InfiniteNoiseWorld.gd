
class_name InfiniteNoiseWorld
extends Node3D


func _exit_tree() -> void:
	# Bake jobs sample this node on the thread pool. Join them before the
	# node is freed or engine shutdown hits a dead noise object.
	var bake = load("res://world/world_bake_service.gd").get_active()
	if bake != null and bake.has_method("_clear_job_queue"):
		bake._clear_job_queue()

enum MapTemperature { HOT, MILD, COLD, HOT_MILD, MILD_COLD }

const _FeatureRegistry = preload("res://world/feature_registry.gd")
const _TerrainEdits = preload("res://world/terrain_edits.gd")
const _WorldGenConfig = preload("res://config/world_gen_config.gd")
const _BiomeLayout = preload("res://world/biome_layout.gd")
const _WorldSettings = preload("res://config/world_settings.gd")

var world_seed: int
var _spawn_river_cx: float = 0.0
var _spawn_river_cz: float = 0.0
var _spawn_river_seed: int = 0
var _spawn_river_ready: bool = false
var map_temperature: MapTemperature = MapTemperature.MILD
var map_temperature_label: String = "Mild"
var world_config: _WorldGenConfig
var caves_enabled: bool = true

const BIOME_SCALE := 920.0
const SPAWN_RIVER_CLEARANCE := 96.0
const MOUNTAIN_FREQ := 1.0
const DETAIL_FREQ := 4.5



const RIVER_TARGET_PREVALENCE := 0.20

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
const SEA_LEVEL := 38.0
const MOUNTAIN_HEIGHT_BOOST := 78.0

var _surface_cache: Dictionary = {}
var _tile_cache: Dictionary = {}
var _biome_cache: Dictionary = {}
var _query_measure_enabled: bool = false
var _query_ops: Dictionary = {}
var _query_surface_hits: int = 0
var _query_surface_misses: int = 0
var _query_biome_hits: int = 0
var _query_biome_misses: int = 0
var _query_tile_hits: int = 0
var _query_tile_misses: int = 0
var _query_frame_seen_surface: Dictionary = {}
var _query_frame_seen_biome: Dictionary = {}
var _query_frame_id: int = -1
var _query_surface_dups: int = 0
var _query_biome_dups: int = 0
var _query_tile_dups: int = 0

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

var _river_noise: FastNoiseLite
var _river_length_noise: FastNoiseLite
var _river_width_noise: FastNoiseLite

var _cave_tunnel: FastNoiseLite
var _cave_room: FastNoiseLite
var _surface_variation: FastNoiseLite

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


func apply_seed(p_seed: int) -> void:
	world_seed = int(p_seed)
	_BiomeLayout.reset()
	_roll_map_temperature()
	_setup_noise()
	_init_biome_regions()
	_invalidate_height_caches()

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

	_base_height = FastNoiseLite.new()
	_base_height.seed = world_seed + 100
	_base_height.noise_type = FastNoiseLite.TYPE_PERLIN
	_base_height.frequency = 2.8 / BIOME_SCALE
	_base_height.fractal_type = FastNoiseLite.FRACTAL_FBM
	_base_height.fractal_octaves = 4
	_base_height.fractal_lacunarity = 2.05
	_base_height.fractal_gain = 0.48

	_mountain_ridge = FastNoiseLite.new()
	_mountain_ridge.seed = world_seed + 200
	_mountain_ridge.noise_type = FastNoiseLite.TYPE_PERLIN
	_mountain_ridge.frequency = MOUNTAIN_FREQ / BIOME_SCALE
	_mountain_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain_ridge.fractal_octaves = 5
	_mountain_ridge.fractal_lacunarity = 2.15
	_mountain_ridge.fractal_gain = 0.52

	_detail = FastNoiseLite.new()
	_detail.seed = world_seed + 300
	_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	_detail.frequency = DETAIL_FREQ / BIOME_SCALE
	_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_detail.fractal_octaves = 3
	_detail.fractal_gain = 0.6

	_temp = FastNoiseLite.new()
	_temp.seed = world_seed + 400
	_temp.noise_type = FastNoiseLite.TYPE_PERLIN
	_temp.frequency = 1.6 / BIOME_SCALE
	_temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_temp.fractal_octaves = 3

	_moist = FastNoiseLite.new()
	_moist.seed = world_seed + 500
	_moist.noise_type = FastNoiseLite.TYPE_PERLIN
	_moist.frequency = 2.1 / BIOME_SCALE
	_moist.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moist.fractal_octaves = 6
	_moist.fractal_lacunarity = 2.1
	_moist.fractal_gain = 0.47

	_river_valley = FastNoiseLite.new()
	_river_valley.seed = world_seed + 600
	_river_valley.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_valley.frequency = RIVER_FREQ_BASE * (92.0 / (BIOME_SCALE * RIVER_SCALE_FACTOR))
	_river_valley.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_valley.fractal_octaves = 6
	_river_valley.fractal_lacunarity = 1.92
	_river_valley.fractal_gain = 0.41

	_river_warp_x = FastNoiseLite.new()
	_river_warp_x.seed = world_seed + 610
	_river_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_warp_x.frequency = 1.25 * (92.0 / BIOME_SCALE)
	_river_warp_x.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_warp_x.fractal_octaves = 2

	_river_warp_z = FastNoiseLite.new()
	_river_warp_z.seed = world_seed + 611
	_river_warp_z.noise_type = FastNoiseLite.TYPE_PERLIN
	_river_warp_z.frequency = 1.25 * (92.0 / BIOME_SCALE)
	_river_warp_z.fractal_type = FastNoiseLite.FRACTAL_FBM
	_river_warp_z.fractal_octaves = 2
	
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
	_cave_room.fractal_gain = 0.5

	_surface_variation = FastNoiseLite.new()
	_surface_variation.seed = world_seed + 800
	_surface_variation.noise_type = FastNoiseLite.TYPE_PERLIN
	_surface_variation.frequency = 41.0 / BIOME_SCALE
	_surface_variation.fractal_type = FastNoiseLite.FRACTAL_FBM
	_surface_variation.fractal_octaves = 2

func _warped_coords(wx: float, wz: float, strength: float = 18.0) -> Vector2:
	var wx2: float = wx + _warp_x.get_noise_2d(wx * 0.6, wz * 0.6) * strength
	var wz2: float = wz + _warp_z.get_noise_2d(wx * 0.6, wz * 0.6) * strength
	return Vector2(wx2, wz2)

func _warped_coords_river(wx: float, wz: float, strength: float = 26.0) -> Vector2:
	var wx2: float = wx + _river_warp_x.get_noise_2d(wx * 0.55, wz * 0.55) * strength
	var wz2: float = wz + _river_warp_z.get_noise_2d(wx * 0.55, wz * 0.55) * strength
	return Vector2(wx2, wz2)

func _compute_raw_elevation(wx: float, wz: float) -> float:
	var w: Vector2 = _warped_coords(wx, wz, 11.0)
	var x: float = w.x
	var z: float = w.y

	var base: float = (_base_height.get_noise_2d(x, z) + 1.0) * 0.5
	var base_h: float = base * 68.0 - 6.0

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

func river_mask_formula(wx: float, wz: float) -> Dictionary:
	var r: float = _river_noise.get_noise_2d(wx, wz)
	var len_mod: float = _river_length_noise.get_noise_2d(wx * 0.65, wz * 0.65)
	var width_var: float = (_river_width_noise.get_noise_2d(wx * 2.1, wz * 2.1) + 1.0) * 0.5
	var dist: float = abs(r)
	var threshold: float = 0.026
	var active: bool = dist < threshold and len_mod > -0.32
	var strength: float = 0.0
	if active:
		strength = 1.0 - (dist / threshold) * 0.65
		strength = clamp(strength * (0.7 + width_var * 0.55), 0.0, 1.0)
	return {"active": active, "strength": strength, "dist": dist}


func spawn_river_center() -> Vector2:
	if not _spawn_river_ready or _spawn_river_seed != world_seed:
		var corner: Vector2i = WorldBorder.origin_corner_for_seed(world_seed)
		_spawn_river_cx = float(corner.x)
		_spawn_river_cz = float(corner.y)
		_spawn_river_seed = world_seed
		_spawn_river_ready = true
	return Vector2(_spawn_river_cx, _spawn_river_cz)


func _inside_spawn_river_clearance(wx: float, wz: float) -> bool:
	var center := spawn_river_center()
	var dx := wx - center.x
	var dz := wz - center.y
	var clearance := SPAWN_RIVER_CLEARANCE
	return dx * dx + dz * dz < clearance * clearance


func get_river_mask(wx: float, wz: float) -> Dictionary:
	var raw := river_mask_formula(wx, wz)
	var center := spawn_river_center()
	var dx := wx - center.x
	var dz := wz - center.y
	var dist2 := dx * dx + dz * dz
	var clearance := SPAWN_RIVER_CLEARANCE
	if dist2 >= clearance * clearance:
		return raw
	var dist := sqrt(dist2)
	var t := dist / clearance
	var fade := t * t * (3.0 - 2.0 * t)
	raw["active"] = false
	raw["strength"] = float(raw["strength"]) * fade
	return raw

func _compute_river_carve(wx: float, wz: float, base_elev: float) -> Dictionary:
	var w: Vector2 = _warped_coords_river(wx, wz, 17.0)
	var rx: float = w.x
	var rz: float = w.y

	var valley: float = _river_valley.get_noise_2d(rx, rz)
	var u: float = max(0.0, (valley + RIVER_CORE_OFFSET) * RIVER_CORE_SCALE)
	var river_core: float = pow(u, RIVER_CORE_POWER)

	var meander: float = _river_valley.get_noise_2d(rx * 2.6, rz * 2.6) * 0.28
	river_core = clamp(river_core + meander * 0.55, 0.0, 1.35)

	var lowland_factor: float = clamp(1.0 - (base_elev - 18.0) / 95.0, 0.35, 1.35)
	var carve_depth: float = river_core * RIVER_MAX_CARVE * lowland_factor * RIVER_VALLEY_WIDTH_FACTOR

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
	var t: float = _cave_tunnel.get_noise_3d(wx, wy * 0.9, wz) * CAVE_TUNNEL_WEIGHT
	var r: float = _cave_room.get_noise_3d(wx * 0.7, wy * 0.55, wz * 0.7) * CAVE_ROOM_WEIGHT
	var depth_bias: float = clamp((wy - 12.0) / 55.0, -0.6, 1.1)
	return t * 0.7 + r * 1.05 + depth_bias * 0.18

func get_biome(wx: float, wy: float, wz: float) -> Dictionary:
	var key: String = "%d,%d" % [floori(wx), floori(wz)]
	if _biome_cache.has(key) and abs(wy) < 3.0:
		if _query_measure_enabled:
			_query_biome_hits += 1
			_note_frame_dup_biome(key)
		return _biome_cache[key]

	var t0 := Time.get_ticks_usec() if _query_measure_enabled else 0
	var surface_h: float = get_surface_height(wx, wz)
	var res: Dictionary = _get_biome_compute(wx, wy, wz, surface_h)
	if abs(wy) < 2.5:
		_biome_cache[key] = res
		if _biome_cache.size() > 4096:
			_biome_cache.clear()
	if _query_measure_enabled:
		_query_biome_misses += 1
		_note_frame_dup_biome(key)
		_record_query_op("get_biome", t0)
	return res

func get_biome_uncached(wx: float, wy: float, wz: float) -> Dictionary:
	# Pure compute path. Safe for background worker threads (never mutates caches).
	var t0 := Time.get_ticks_usec() if _query_measure_enabled else 0
	var elev: float = get_surface_height_uncached(wx, wz)
	var res: Dictionary = _get_biome_compute(wx, wy, wz, elev)
	if _query_measure_enabled:
		_record_query_op("get_biome_uncached", t0)
	return res

func _get_biome_compute(wx: float, wy: float, wz: float, surface_h: float = NAN) -> Dictionary:
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

	var t: float = (_temp.get_noise_2d(x, z) + 1.0) * 0.5
	var elev_for_temp: float = surface_h if not is_nan(surface_h) else get_surface_height_uncached(wx, wz)
	var lapse: float = clamp((elev_for_temp - 42.0) / 115.0, 0.0, 0.92)
	t = clamp(t - lapse * 0.82, 0.0, 1.0)
	t = _apply_map_temperature_bias(t)

	var raw_m: float = (_moist.get_noise_2d(x * 0.9, z * 0.9) + 1.0) * 0.5
	var lf_m: float = (_moist.get_noise_2d(x * 0.13, z * 0.13) + 1.0) * 0.5
	
	var m: float = raw_m * 0.5 + lf_m * 0.6
	m = clamp(m, 0.0, 1.0)

	var dry_push: float = _moist.get_noise_2d(x * 0.48, z * 0.48) * 0.38
	m = clamp(m - dry_push, 0.0, 1.0)
	
	var wet_push: float = max(0.0, _moist.get_noise_2d(x * 0.37, z * 0.37) * 0.22)
	m = clamp(m + wet_push, 0.0, 1.0)

	var river_info: Dictionary = _compute_river_carve(wx, wz, elev_for_temp)
	if river_info.is_river:
		m = clamp(m + river_info.river_factor * 0.3, 0.0, 1.0)

	var rug: float = _compute_local_ruggedness(wx, wz)

	var wg := _wg()
	var name: String = _BiomeLayout.biome_name_at(
		wx, wz, world_seed, wg.biome_region_warp, float(WorldBorder.PLAYABLE_HALF_X)
	)
	if name == "highland":
		rug = maxf(rug, 0.45)
	elif name == "marsh":
		m = maxf(m, 0.62)
	elif name == "steppe":
		m = minf(m, 0.42)

	if elev_for_temp > 42.0 and wy > elev_for_temp + 8.0:
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

func get_surface_height(wx: float, wz: float) -> float:
	var k: Vector2i = Vector2i(floori(wx), floori(wz))
	var t0 := Time.get_ticks_usec() if _query_measure_enabled else 0
	var natural: float
	if _surface_cache.has(k):
		if _query_measure_enabled:
			_query_surface_hits += 1
			_note_frame_dup_surface(k)
		natural = float(_surface_cache[k])
	else:
		natural = _quantize_to_voxel_layer(_compute_surface_height(wx, wz))
		_surface_cache[k] = natural
		if _surface_cache.size() > 12288:
			_surface_cache.clear()
		if _query_measure_enabled:
			_query_surface_misses += 1
			_note_frame_dup_surface(k)
			_record_query_op("get_surface_height", t0)
	return natural + _TerrainEdits.get_height_delta(k.x, k.y)

func get_surface_height_uncached(wx: float, wz: float) -> float:
	var t0 := Time.get_ticks_usec() if _query_measure_enabled else 0
	var h: float = _quantize_to_voxel_layer(_compute_surface_height(wx, wz))
	h += _TerrainEdits.get_height_delta(floori(wx), floori(wz))
	if _query_measure_enabled:
		_record_query_op("get_surface_height_uncached", t0)
	return h


func set_query_measure_enabled(enabled: bool) -> void:
	_query_measure_enabled = enabled


func reset_query_stats() -> void:
	_query_ops.clear()
	_query_surface_hits = 0
	_query_surface_misses = 0
	_query_biome_hits = 0
	_query_biome_misses = 0
	_query_tile_hits = 0
	_query_tile_misses = 0
	_query_surface_dups = 0
	_query_biome_dups = 0
	_query_tile_dups = 0
	_query_frame_seen_surface.clear()
	_query_frame_seen_biome.clear()
	_query_frame_id = -1


func get_query_stats() -> Dictionary:
	var s_n := _query_surface_hits + _query_surface_misses
	var b_n := _query_biome_hits + _query_biome_misses
	var t_n := _query_tile_hits + _query_tile_misses
	return {
		"ops": _query_ops.duplicate(true),
		"surface_hits": _query_surface_hits,
		"surface_misses": _query_surface_misses,
		"surface_dups": _query_surface_dups,
		"surface_hit_rate": float(_query_surface_hits) / float(maxi(s_n, 1)),
		"biome_hits": _query_biome_hits,
		"biome_misses": _query_biome_misses,
		"biome_dups": _query_biome_dups,
		"biome_hit_rate": float(_query_biome_hits) / float(maxi(b_n, 1)),
		"tile_hits": _query_tile_hits,
		"tile_misses": _query_tile_misses,
		"tile_dups": _query_tile_dups,
		"tile_hit_rate": float(_query_tile_hits) / float(maxi(t_n, 1)),
	}


func _record_query_op(op: String, t0_us: int) -> void:
	if not _query_measure_enabled:
		return
	var dt := Time.get_ticks_usec() - t0_us
	if not _query_ops.has(op):
		_query_ops[op] = {"n": 0, "total_us": 0, "max_us": 0}
	var row: Dictionary = _query_ops[op]
	row["n"] = int(row["n"]) + 1
	row["total_us"] = int(row["total_us"]) + dt
	row["max_us"] = maxi(int(row["max_us"]), dt)


func _sync_query_frame() -> void:
	var f := Engine.get_process_frames()
	if f == _query_frame_id:
		return
	_query_frame_id = f
	_query_frame_seen_surface.clear()
	_query_frame_seen_biome.clear()


func _note_frame_dup_surface(k: Vector2i) -> void:
	_sync_query_frame()
	if _query_frame_seen_surface.has(k):
		_query_surface_dups += 1
	else:
		_query_frame_seen_surface[k] = true


func _note_frame_dup_biome(key: String) -> void:
	_sync_query_frame()
	if _query_frame_seen_biome.has(key):
		_query_biome_dups += 1
	else:
		_query_frame_seen_biome[key] = true


## Worker-thread safe: pass terrain edits captured on the main thread (no shared dict access).
func get_surface_height_worker(wx: float, wz: float, height_delta: float = 0.0) -> float:
	# Isolation counter: in a complete baked world this must stay 0 for package cells.
	var bake = null
	var wb = load("res://world/world_bake_service.gd")
	if wb != null and wb.has_method("get_active"):
		bake = wb.get_active()
	if OS.get_thread_caller_id() == OS.get_main_thread_id() \
			and bake != null and bake.has_method("should_count_runtime_noise_height") \
			and bool(bake.should_count_runtime_noise_height(wx, wz)):
		if bake.has_method("note_runtime_noise_height_call"):
			bake.note_runtime_noise_height_call()
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

func get_tile_type(wx: float, wz: float) -> int:
	var k: Vector2i = Vector2i(floori(wx), floori(wz))
	var build_tile: int = _TerrainEdits.get_build_tile(k.x, k.y)
	if build_tile >= 0:
		return build_tile
	var override: int = _FeatureRegistry.get_tile_override(k.x, k.y)
	if override >= 0:
		return override
	if _tile_cache.has(k):
		if _query_measure_enabled:
			_query_tile_hits += 1
		return _tile_cache[k]

	var t0 := Time.get_ticks_usec() if _query_measure_enabled else 0
	var id: int = _compute_surface_tile(wx, wz, true)
	_tile_cache[k] = id
	if _tile_cache.size() > 12288:
		_tile_cache.clear()
	if _query_measure_enabled:
		_query_tile_misses += 1
		_record_query_op("get_tile_type", t0)
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
	return _compute_surface_tile(wx, wz, false)

func _compute_surface_tile(wx: float, wz: float, use_session_cache: bool = false) -> int:
	var surf: float
	var biome: Dictionary
	if use_session_cache:
		surf = get_surface_height(wx, wz)
		biome = get_biome(wx, 0.0, wz)
	else:
		surf = get_surface_height_uncached(wx, wz)
		biome = get_biome_uncached(wx, 0.0, wz)
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

	var river_mask_dict: Dictionary = get_river_mask(wx, wz)
	var river: Dictionary = _compute_river_carve(wx, wz, surf)

	var in_spawn_clearance := _inside_spawn_river_clearance(wx, wz)
	if river_mask_dict.get("active", false) or (not in_spawn_clearance and float(river.get("carve", 0.0)) > 6.0):
		return VoxelTypes.RIVER

	var cave_val: float = _sample_cave(wx, surf - 2.2, wz)
	var rugged: float = biome.get("rugged", 0.0)
	if cave_val > CAVE_MOUTH_THRESHOLD or (rugged > 0.68 and surf > 52.0):
		return VoxelTypes.STONE if (cave_val > 0.58 or rugged > 0.75) else VoxelTypes.STONE2

	var temp2: float = biome.get("temp", 0.5)
	var moist: float = biome.get("moist", 0.5)
	var hl: int = biome.get("h_level", 9)

	var tile_var: float = (_surface_variation.get_noise_2d(wx * 2.3, wz * 2.3) + 1.0) * 0.5
	var patch_var: float = (_surface_variation.get_noise_2d(wx * 0.71 + 17.0, wz * 0.71 - 9.0) + 1.0) * 0.5
	var micro_var: float = (_detail.get_noise_2d(wx * 5.1, wz * 5.1) + 1.0) * 0.5

	var name: String
	match bname:
		"plains":
			if map_temperature == MapTemperature.COLD and temp2 < 0.45:
				name = "snow" if tile_var < 0.55 else "snow2"
			elif moist > 0.66:
				if patch_var < 0.22:
					name = "meadow"
				elif patch_var < 0.48:
					name = "grass"
				elif patch_var < 0.72:
					name = "plains"
				else:
					name = "savanna" if micro_var > 0.5 else "meadow"
			elif temp2 < 0.34:
				name = "savanna" if patch_var > 0.35 else "steppe"
			else:
				if patch_var < 0.3:
					name = "grass"
				elif patch_var < 0.55:
					name = "plains"
				elif patch_var < 0.78:
					name = "meadow"
				else:
					name = "steppe" if micro_var > 0.55 else "grass"
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
				name = "dense forest" if patch_var > 0.4 else "jungle"
			elif temp2 < 0.38:
				name = "pine forest" if patch_var > 0.35 else "forest"
			else:
				if patch_var < 0.35:
					name = "meadow"
				elif patch_var < 0.65:
					name = "forest"
				else:
					name = "dense forest"
		"marsh":
			if patch_var < 0.4:
				name = "marsh"
			elif patch_var < 0.7:
				name = "meadow"
			else:
				name = "basin"
			if rugged < 0.18 and moist > 0.78 and patch_var < 0.55:
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

func get_voxel(wx: float, wy: float, wz: float) -> int:
	var surf: float = get_surface_height_uncached(wx, wz)

	if wy > surf + 0.1:
		return VoxelTypes.AIR

	var river: Dictionary = _compute_river_carve(wx, wz, surf)

	if river.is_river:
		var river_bed: float = surf + river.carve - river.water_depth
		if wy > river_bed and wy <= surf:
			return VoxelTypes.RIVER

	var cave: float = _sample_cave(wx, wy, wz)
	var roof_protect: float = clamp((surf - wy) / 4.5, 0.0, 1.0)
	if cave > (CAVE_HOLLOW_BASE + roof_protect * CAVE_ROOF_PROTECT_SCALE):
		return VoxelTypes.AIR

	var depth: float = surf - wy
	var b: Dictionary = get_biome_uncached(wx, wy, wz)
	var biome_name: String = b.get("name", "plains")
	var tempv: float = b.get("temp", 0.5)

	if depth < 1.2:
		return get_tile_type_uncached(wx, wz)

	if depth < 4.5:
		if biome_name == "marsh" or biome_name == "forest":
			return VoxelTypes.DIRT
		if biome_name == "steppe":
			return VoxelTypes.DIRT2 if tempv > 0.4 else VoxelTypes.STONE
		if biome_name == "border_mountain" or biome_name == "ocean":
			return VoxelTypes.STONE
		return VoxelTypes.DIRT2

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
	var layer: float = _WorldSettings.get_active().layer_height()
	var start_y: int = floori(surf - layer)
	var min_y: int = maxi(0, floori(surf) - int(max_depth))
	for y in range(start_y, min_y - 1, -1):
		var wy: float = float(y)
		var stand: float = wy + 1.0
		if stand >= surf - layer * 0.25:
			continue
		if get_solid(wx, wy, wz) and not get_solid(wx, stand, wz):
			return stand
	return 0.0

func _compute_base_elevation(wx: float, wz: float) -> float:
	return _compute_raw_elevation(wx, wz)

func get_height(wx: float, wy: float, wz: float) -> float:
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
