# world_sampler.gd
class_name WorldSampler
extends Resource

var seed: int

var height_noise: FastNoiseLite
var biome_noise: FastNoiseLite

func _init(p_seed: int):
	seed = p_seed
	_setup_noise()


func _setup_noise():
	height_noise = FastNoiseLite.new()
	height_noise.seed = seed
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 0.01

	biome_noise = FastNoiseLite.new()
	biome_noise.seed = seed + 999
	biome_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	biome_noise.frequency = 0.005


func get_height(wx: int, wy: int) -> int:
	var h = height_noise.get_noise_2d(wx, wy)
	return int(remap(h, -1.0, 1.0, 5, 40))


func get_voxel(wx: int, wy: int, wz: int) -> int:
	var h = get_height(wx, wy)

	if wz > h:
		return 0 # AIR

	return 1 # SOLID (replace with biome logic later)
