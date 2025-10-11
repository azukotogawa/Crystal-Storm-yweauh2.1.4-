from perlinnoisetest2.config import ALL_TERRAIN_TYPES

TILESHEET_PATH = "PunyWorld/punyworld-overworld-tileset-perlin.png"

WINDOW_WIDTH    = 1280
WINDOW_HEIGHT   = 720
TILESIZE        = 16       # tile width/height in pixels in tilesheet
WORLD_X         = (WINDOW_WIDTH + TILESIZE - 1) // TILESIZE
WORLD_Y         = (WINDOW_HEIGHT + TILESIZE - 1) // TILESIZE


# Terrain types

LAKE3 = 0
LAKE2 = 1
LAKE = 2
VALLEY3 = 3
VALLEY2 = 4
VALLEY = 5
BEACH = 6
BEACH2 = 7
BEACH3 = 8
GRASS = 9
GRASS2 = 10
GRASS3 = 11
GRASS4 = 12
GRASS5 = 13
DESERT = 14
DESERT2 = 15
DESERT3 = 16
TUNDRA = 17
TUNDRA2 = 18
TUNDRA3 = 19
RIVER = 20
BASIN = 21
BASIN2 = 22
BASIN3 = 23
BOULDERCLUSTER = 24
HOODOO = 25
FOREST = 26
FOREST2 = 27
FOREST3 = 28
FOREST4 = 29
MOUNTAIN = 30
MOUNTAIN2 = 31
MOUNTAIN3 = 32
MOUNTAIN4 = 33
MOUNTAIN5 = 34
MOUNTAIN6 = 35
MOUNTAIN7 = 36
SNOW = 37
SNOW2 = 38
SNOW3 = 39



ALL_TERRAIN_TYPES = [LAKE3, LAKE2, LAKE, VALLEY3, VALLEY2, VALLEY, BEACH, BEACH2, BEACH3,
                     GRASS, GRASS2, GRASS3, GRASS4, GRASS5, DESERT, DESERT2, DESERT3, TUNDRA, TUNDRA2, TUNDRA3, RIVER,
                     BASIN, BASIN2, BASIN3, BOULDERCLUSTER, HOODOO, FOREST, FOREST2, FOREST3, FOREST4, MOUNTAIN, MOUNTAIN2,
                     MOUNTAIN3, MOUNTAIN4, MOUNTAIN5, MOUNTAIN6, MOUNTAIN7, SNOW, SNOW2, SNOW3]


# List of all terrain type, ordered from lower height to higher height

# All tiles in the tilesheet, for each terrain type in ALL_TERRAIN_TYPES
ALL_TERRAIN_TILES = [
    # LAKE
    [(32, 0)], [(16, 0)], [(0, 0)],
    #Valley
    [(96, 80)], [(0,96)], [(16,96)],
    #Beach
    [(0, 16)], [(16, 16)], [(32, 16)],
    #Grass
    [(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
    #Desert
    [(32, 96)], [(48, 96)], [(64, 96)],
    #TUNDRA
    [(80, 96)], [(96, 96)], [(0, 112)],
    #RIVER
    [(16, 112)],
    #BASIN
    [(80, 112)], [(96, 112)], [(0, 128)],
    #BOULDERCLUSTER
    [(16, 128)],
    #HOODOO
    [(32, 128)],
    #FOREST
    [(80, 48)], [(96, 48)], [(0, 64)], [(16, 64)],
    #MOUNTAIN
    [(32, 64)], [(48, 64)], [(64, 64)], [(80, 64)], [(96, 64)], [(0, 80)], [(16, 80)],
    #SNOW
    [(32, 80)], [(48, 80)], [(64, 80)]
    ]
'''
#LAKE
LAKE_TERRAIN_TYPES = [LAKE3, LAKE2, LAKE, BEACH, BEACH2, BEACH3, GRASS, GRASS2, GRASS3, GRASS4, GRASS5,
                      FOREST, FOREST2, FOREST3, FOREST4]
LAKE_TERRAIN_TILES = [
    [(32, 0)], [(16, 0)], [(0, 0)], [(0, 16)], [(16, 16)], [(32, 16)], [(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
    [(80, 48)], [(96, 48)], [(0, 64)], [(16, 64)]
]

#MOUNTAIN
MOUNTAIN_TERRAIN_TYPES = [FOREST, FOREST2, FOREST3, FOREST4, MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4,
                          MOUNTAIN5, MOUNTAIN6, MOUNTAIN7, SNOW, SNOW2, SNOW3, SNOW4]
MOUNTAIN_TERRAIN_TILES = [
    [(80, 48)], [(96, 48)], [(0, 64)], [(16, 64)],[(32, 64)], [(48, 64)], [(64, 64)], [(80, 64)], [(96, 64)], [(0, 80)], [(16, 80)],
    [(32, 80)], [(48, 80)], [(64, 80)], [(80, 80)]
]
#TUNDRA
TUNDRA_TERRAIN_TYPES = [TUNDRA, TUNDRA2, TUNDRA3, GRASS, GRASS2, GRASS3, GRASS4, GRASS5, VALLEY, VALLEY2, VALLEY3,
                        MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4, MOUNTAIN5]
TUNDRA_TERRAIN_TILES = [
    [(80, 96)], [(96, 96)], [(0, 112)], [(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
    [(96, 80)], [(0,96)], [(16,96)], [(32, 64)], [(48, 64)], [(64, 64)], [(80, 64)], [(96, 64)]
]
#DESERT
DESERT_TERRAIN_TYPES = [DESERT, DESERT2, DESERT3, RIVER, GRASS, GRASS2, GRASS3, GRASS4, GRASS5, BASIN, BASIN2, BASIN3,
                        LAKE, LAKE2, LAKE3]
DESERT_TERRAIN_TILES = [
[(32, 96)], [(48, 96)], [(64, 96)],[(16, 112)],[(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
[(80, 112)], [(96, 112)], [(0, 128)],[(32, 0)], [(16, 0)], [(0, 0)]
]
#GRASS
GRASS_TERRAIN_TYPES = [GRASS, GRASS2, GRASS3, GRASS4, GRASS5, RIVER, BASIN, BASIN2, BASIN3, VALLEY, VALLEY2,
                       VALLEY3, FOREST, FOREST2, FOREST3]
GRASS_TERRAIN_TILES = [
[(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],[(16, 112)], [(80, 112)], [(96, 112)], [(0, 128)],
[(96, 80)], [(0,96)], [(16,96)],[(80, 48)], [(96, 48)], [(0, 64)]
]
#VALLEY
VALLEY_TERRAIN_TYPES = [VALLEY, VALLEY2, VALLEY3, BOULDERCLUSTER, FOREST, FOREST2, FOREST3, FOREST4, DESERT, DESERT2, DESERT3,
                        TUNDRA, TUNDRA2, TUNDRA3, HOODOO]
VALLEY_TERRAIN_TILES = [
[(96, 80)], [(0,96)], [(16,96)],[(16, 128)],[(80, 48)], [(96, 48)], [(0, 64)], [(16, 64)],
[(32, 96)], [(48, 96)], [(64, 96)],[(80, 96)], [(96, 96)], [(0, 112)],[(32, 128)]
]
#FOREST
FOREST_TERRAIN_TYPES = [FOREST, FOREST2, FOREST3, FOREST4, RIVER, GRASS, GRASS2, GRASS3, GRASS4, GRASS5, BOULDERCLUSTER,
                        MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4]
FOREST_TERRAIN_TILES = [
    [(80, 48)], [(96, 48)], [(0, 64)], [(16, 64)],[(16, 112)],[(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
[(16, 128)],[(32, 64)], [(48, 64)], [(64, 64)], [(80, 64)]
]
#GRASS2
GRASS2_TERRAIN_TYPES = [GRASS, GRASS2, GRASS3, GRASS4, GRASS5, DESERT, DESERT2, DESERT3, TUNDRA, TUNDRA2, TUNDRA3,
                        VALLEY, VALLEY2, VALLEY3, HOODOO]
GRASS2_TERRAIN_TILES = [
[(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],[(32, 96)], [(48, 96)], [(64, 96)],[(80, 96)], [(96, 96)], [(0, 112)],
[(96, 80)], [(0,96)], [(16,96)],[(32, 128)]
]
#BASIN
BASIN_TERRAIN_TYPES = [BASIN, BASIN2, BASIN3, RIVER, GRASS, GRASS2, GRASS3, GRASS4, GRASS5, BEACH, BEACH2, BEACH3, LAKE, LAKE2, LAKE3]
BASIN_TERRAIN_TILES = [
[(80, 112)], [(96, 112)], [(0, 128)],[(16, 112)],[(64, 16)], [(80, 16)], [(96, 16)], [(0, 32)], [(0, 48)],
[(0, 16)], [(16, 16)], [(32, 16)],[(32, 0)], [(16, 0)], [(0, 0)]
]
'''