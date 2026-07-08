extends Node

class_name NoiseWorld

# Import the OpenSimplexNoise class for procedural generation
var noise = OpenSimplexNoise.new()

# World dimensions
var width: int
var height: int

# Terrain types
enum TileType { WATER, GRASS, FOREST, MOUNTAIN }

# 2D array to store the terrain
var terrain: PoolIntArray

func _init(w: int, h: int) -> void:
	width = w
	height = h
	terrain = PoolIntArray()
	generate_world()

func generate_world() -> void:
	# Configure noise parameters
	noise.seed = randi()
	noise.octaves = 4
	noise.period = 64.0
	noise.persistence = 0.5

	# Generate terrain
	for y in range(height):
		for x in range(width):
			var nx = float(x) / float(width) - 0.5
			var ny = float(y) / float(height) - 0.5
			var elevation = noise.get_noise_2d(nx * 10.0, ny * 10.0)

			if elevation < -0.2:
				terrain.append(TileType.WATER)
			elif elevation < 0.0:
				terrain.append(TileType.GRASS)
			elif elevation < 0.3:
				terrain.append(TileType.FOREST)
			else:
				terrain.append(TileType.MOUNTAIN)

func get_tile(x: int, y: int) -> int:
	return terrain[y * width + x]

func display_world() -> void:
	for y in range(height):
		var row = ""
		for x in range(width):
			var tile = get_tile(x, y)
			match tile:
				TileType.WATER:
					row += "~"
				TileType.GRASS:
					row += "."
				TileType.FOREST:
					row += "T"
				TileType.MOUNTAIN:
					row += "^"
			row += " "
		print(row)
