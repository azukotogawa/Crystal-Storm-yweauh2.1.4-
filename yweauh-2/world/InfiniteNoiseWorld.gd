# infinite_noise_world.gd
class_name InfiniteNoiseWorld
extends Node                     # ← Changed to Node (this fixes the cast)

var world_seed: int
var biome_scale: float = 860
var precip_weights = []
var height_weights = []

# ==================== BIOME DATA (ported from config1.py) ====================

# Better balanced weights for FastNoiseLite
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		generate_random_weights()

func generate_random_weights():
	print("--- New Random Weights ---")
	
	# Generate random weights for Height
	for i in range(39):
		var base = randi_range(1,30)
		base = base * 10
		height_weights.append(int(base))
	
	# Generate random weights for Precipitation
	for i in range(39):
		var base = randi_range(1,30)
		base = base * 10
		precip_weights.append(int(base))
	
	# Print nicely
	print("const BIOME_WEIGHTS_HEIGHT: Array = [")
	print("    ", str(height_weights.slice(0,10)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(height_weights.slice(10,20)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(height_weights.slice(20,30)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(height_weights.slice(30,40)).replace("[","").replace("]","").replace(" ",""))
	print("]")
	
	print("\nconst BIOME_WEIGHTS_PRECIP: Array = [")
	print("    ", str(precip_weights.slice(0,10)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(precip_weights.slice(10,20)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(precip_weights.slice(20,30)).replace("[","").replace("]","").replace(" ",""), ",")
	print("    ", str(precip_weights.slice(30,40)).replace("[","").replace("]","").replace(" ",""))
	print("]")

const BIOME_WEIGHTS_HEIGHT: Array = [
	# Low (deep ocean / basins) - less common
	300, 250, 200, 180, 160, 140, 120, 100, 90, 90,   # 0–9  (deep basins)
	90,  90,  85,  70,  60,  50,  50,  55,  60,  70,   # 10–19 (plains)
	80,  90, 100, 120, 140, 160, 180, 90, 90, 90,   # 20–29 (mountains)
	100, 100, 10, 100, 150, 160, 170, 200, 250, 300 
]

const BIOME_WEIGHTS_PRECIP: Array = [
	100, 100, 100, 100,100, 150, 100, 100, 100, 100, 
	80,  90, 100, 120, 140, 160, 180, 90, 90, 90,  
	90,  90,  85,  70,  60,  50,  50,  55,  60,  70,   # 10–19 (plains)
	90, 90, 100, 120,120, 140,160,180, 600, 700
]


# Biome maps with duplicates for weighting (same idea as your Python version)
const HIGH_MAP: Array = [
"plains", "steppe", "savanna",
"forest", "dense forest", "dense forest", "river",
"pine forest", "pine forest", "jungle",
"mountain", "ridge", "peak", "volcano", "precipice",
"zenith", "plateau", "snow", "ice field", "glacier"
]
const LAKE_MAP: Array = [ 
"savanna", "steppe","plains", "plains", "river", "river", "meadow", "meadow",
"grass","grass","coral reef", "sandy beach", "sandy beach" ,"beach", "beach",
"shallow sea","shallow sea","ocean", "ocean","deep_ocean"
]
const DRY_MAP: Array = [
 "basin", "salt flat", "salt flat", "dry lake", "dry lake",
"ravine", "canyon", "canyon", "valley", "valley",
"desert", "desert", "dunes", "dunes", "badlands", 
"tundra", "tundra", "frozen plains", "frozen plains", "permafrost"
]
const FOREST_MAP: Array = [
"forest", "forest", "forest", "forest", "dense forest", "dense forest", "dense forest",
"pine forest", "pine forest", "jungle", "jungle", "tundra", "tundra",
"tundra", "tundra", "frozen plains", "frozen plains", "frozen plains", "permafrost", 
]

var h1: FastNoiseLite
var h2: FastNoiseLite
var h3: FastNoiseLite
var h4: FastNoiseLite
var p1: FastNoiseLite
var p2: FastNoiseLite
var p3: FastNoiseLite
var p4: FastNoiseLite

@export var octaves: int = 12                   # Reduced from 5
@export var lacunarity: float = 2
@export var gain: float = .5
@export var amplitude_boost: float = .4

var height_noise: FastNoiseLite
var precip_noise: FastNoiseLite

var height_cumul: Array
var precip_cumul: Array

func _init(p_seed: int = 12349):
	world_seed = p_seed
	generate_random_weights()
	height_cumul = _build_cumul(BIOME_WEIGHTS_HEIGHT)
	precip_cumul = _build_cumul(BIOME_WEIGHTS_PRECIP)
	_setup_noise()

func _build_cumul(weights: Array) -> Array:
	var total = 0.0
	for w in weights:
		total += w
	var cumul: Array = [0.0]
	for w in weights:
		cumul.append(cumul[-1] + float(w) / total)
	return cumul

func _setup_noise():
	# Configure a single, powerful native height fractal
	height_noise = FastNoiseLite.new()
	height_noise.seed = world_seed
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 3.6 / biome_scale # Bake the scale division here natively
	height_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	height_noise.fractal_octaves = 4 # Blends 4 operational layers inside C++ speeds!
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	# Configure a single, powerful native precipitation fractal
	precip_noise = FastNoiseLite.new()
	precip_noise.seed = world_seed + 1000
	precip_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	precip_noise.frequency = 3.6 / biome_scale
	precip_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	precip_noise.fractal_octaves = 4
	precip_noise.fractal_lacunarity = 2.0
	precip_noise.fractal_gain = 0.5

# Drop the multi-variable math additions completely. 
# This runs nearly 8 times faster!
func get_height(wx: float, wy: float) -> float:
	return clamp(height_noise.get_noise_2d(wx, wy) * 1.35, -1.0, 1.0)

func get_precip(wx: float, wy: float) -> float:
	return clamp(precip_noise.get_noise_2d(wx, wy) * 1.35, -1.0, 1.0)

func get_biome(wx: float, wy: float) -> Dictionary:
	var h = get_height(wx, wy)
	var p = get_precip(wx, wy)

	var h_norm = (h + 1.0) / 2.0
	var p_norm = (p + 1.0) / 2.0

	var h_level = bisect_left(height_cumul, h_norm) - 1
	var p_level = bisect_left(precip_cumul, p_norm) - 1
	
	h_level = max(0, min(39, h_level))
	p_level = max(0, min(39, p_level))
	
	var tile_name: String
	var biome_type: String
	var render_height: int
	
	# ZONE 1: Mountains & High Elevations (Height 20-39)
	if h_level >= 20:
		tile_name = HIGH_MAP[h_level - 20]
		biome_type = "High"
		render_height = h_level
		
	# ZONE 2: Low-lying Oceans/Plains (Height 0-19) 
	# Split horizontally by precipitation
	else:
		if p_level >= 20:
			# Use h_level inside your sub-logic if you want height to matter here!
			tile_name = LAKE_MAP[p_level - 20] 
			biome_type = "Lake"
			render_height = p_level
		else:
			# Normal land
			tile_name = DRY_MAP[h_level]
			biome_type = "Dry"
			render_height = h_level
	
	return {
		"name": tile_name,
		"type": biome_type,
		"h_level": h_level,
		"p_level": p_level,
		"render_height": render_height,   # This is what chunk uses for walls
		"is_lake": biome_type == "Lake"
	}
func bisect_left(arr: Array, x) -> int:
	var lo: int = 0
	var hi: int = arr.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if arr[mid] < x:
			lo = mid + 1
		else:
			hi = mid
	return lo
