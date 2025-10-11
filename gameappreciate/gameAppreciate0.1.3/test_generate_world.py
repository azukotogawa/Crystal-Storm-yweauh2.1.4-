from world import World
from world_drawer import *
from config import *
from random import randint

class generateWorld():
    def generate_height(self, weights, random_seed, types):
        height = World(WORLD_X, WORLD_Y, random_seed, types)
        self.tile_height = height.get_tiled_map(weights)
        self.tile_map = height.get_tiled_map(weights)

    def generate_percipitation(self, weights, random_seed, types):
        percipitation = World(WORLD_X, WORLD_Y, random_seed, types)
        self.tile_percipitation = percipitation.get_tiled_map(weights)

    def getHeightMap(self):
        return self.tile_height

    def getPercipitationMap(self):
        return self.tile_percipitation

    def getTileTypeandHeight(self, x, y):
        return self.tile_map[y][x]

class WorldLoad():

    def __init__(self, target_pos):
        self.target_pos = target_pos
        # The order of weight values for each terrain type:
        # WEIGHTS = [WEIGHT_OCEAN3, WEIGHT_OCEAN2, WEIGHT_OCEAN1, WEIGHT_BEACH, WEIGHT_GRASS, WEIGHT_MOUNTAIN, WEIGHT_SNOW]
        #WEIGHTS1 = [70, 20, 20, 12, 35, 30, 0]  # Islands
        #WEIGHTS2 = [35, 20, 20, 15, 30, 30, 25]  #
        WEIGHTS3 = [15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
                    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
                    15, 15, 15, 15, 15, 15, 15, 15, 15, 15]  # Lakes

        self.types = []
        for k in range(40):
            self.types.append(k)
        actualTypes = []

        self.newWorld = generateWorld()
        for i in range(40):
            WEIGHTS3[i] = randint(1, 9) * 5
        self.newWorld.generate_height(WEIGHTS3, randint(0, 100), self.types)
        for i in range(40):
            WEIGHTS3[i] = randint(1, 9) * 5
        self.newWorld.generate_percipitation(WEIGHTS3, randint(0, 100), self.types)
        print(self.newWorld.getHeightMap())
        print(self.newWorld.getPercipitationMap())
        height = self.newWorld.getHeightMap()
        percipitation = self.newWorld.getPercipitationMap()

        self.map = []
        for i in range(WORLD_Y + 1):
            row = []
            for j in range(WORLD_X + 1):
                # Lake
                if percipitation[i][j] >= 20:
                    if height[i][j] <= 1:
                        row.append(LAKE3)
                    if height[i][j] == 2:
                        row.append(LAKE2)
                    if height[i][j] == 3:
                        row.append(LAKE2)
                    if height[i][j] == 4:
                        row.append(LAKE)
                    if height[i][j] == 5:
                        row.append(LAKE)
                        # Beach
                    if height[i][j] == 6:
                        row.append(BEACH)
                    if height[i][j] == 7:
                        row.append(BEACH)
                    if height[i][j] == 8:
                        row.append(BEACH2)
                    if height[i][j] == 9:
                        row.append(BEACH2)
                    if height[i][j] == 10:
                        row.append(BEACH3)
                    if height[i][j] == 11:
                        row.append(BEACH3)
                    # Grass
                    if height[i][j] == 12:
                        row.append(GRASS)
                    if height[i][j] == 13:
                        row.append(GRASS)
                    if height[i][j] == 14:
                        row.append(GRASS2)
                    if height[i][j] == 15:
                        row.append(GRASS2)
                    if height[i][j] == 16:
                        row.append(GRASS3)
                    if height[i][j] == 17:
                        row.append(GRASS3)
                    if height[i][j] == 18:
                        row.append(GRASS4)
                    if height[i][j] == 19:
                        row.append(GRASS4)
                    if height[i][j] == 20:
                        row.append(GRASS5)
                    if height[i][j] == 21:
                        row.append(GRASS5)
                    if height[i][j] == 22:
                        row.append(RIVER)
                    if height[i][j] == 23:
                        row.append(RIVER)
                if percipitation[i][j] <= 19:
                    # Basin
                    if height[i][j] <= 1:
                        row.append(BASIN3)
                    if height[i][j] == 2:
                        row.append(BASIN2)
                    if height[i][j] == 3:
                        row.append(BASIN2)
                    if height[i][j] == 4:
                        row.append(BASIN)
                    if height[i][j] == 5:
                        row.append(BASIN)
                    # Valley
                    if height[i][j] == 6:
                        row.append(VALLEY)
                    if height[i][j] == 7:
                        row.append(VALLEY)
                    if height[i][j] == 8:
                        row.append(VALLEY2)
                    if height[i][j] == 9:
                        row.append(VALLEY2)
                    if height[i][j] == 10:
                        row.append(VALLEY3)
                    if height[i][j] == 11:
                        row.append(VALLEY3)

                    # Desert
                    if height[i][j] == 12:
                        row.append(DESERT)
                    if height[i][j] == 13:
                        row.append(DESERT)
                    if height[i][j] == 14:
                        row.append(DESERT2)
                    if height[i][j] == 15:
                        row.append(DESERT2)
                    if height[i][j] == 16:
                        row.append(DESERT3)
                    if height[i][j] == 17:
                        row.append(DESERT3)
                    # Tundra
                    if height[i][j] == 18:
                        row.append(TUNDRA)
                    if height[i][j] == 19:
                        row.append(TUNDRA)
                    if height[i][j] == 20:
                        row.append(TUNDRA2)
                    if height[i][j] == 21:
                        row.append(TUNDRA2)
                    if height[i][j] == 22:
                        row.append(TUNDRA3)
                    if height[i][j] == 23:
                        row.append(TUNDRA3)
                # Forest
                if height[i][j] == 24:
                    row.append(FOREST)
                if height[i][j] == 25:
                    row.append(FOREST)
                if height[i][j] == 26:
                    row.append(FOREST)
                if height[i][j] == 27:
                    row.append(FOREST2)
                if height[i][j] == 28:
                    row.append(FOREST3)
                if height[i][j] == 29:
                    row.append(FOREST4)
                if height[i][j] == 30:
                    row.append(MOUNTAIN)
                if height[i][j] == 31:
                    row.append(MOUNTAIN2)
                if height[i][j] == 32:
                    row.append(MOUNTAIN3)
                if height[i][j] == 33:
                    row.append(MOUNTAIN4)
                if height[i][j] == 34:
                    row.append(MOUNTAIN5)
                if height[i][j] == 35:
                    row.append(MOUNTAIN6)
                if height[i][j] == 36:
                    row.append(MOUNTAIN7)
                if height[i][j] == 37:
                    row.append(SNOW)
                if height[i][j] == 38:
                    row.append(SNOW2)
                if height[i][j] == 39:
                    row.append(SNOW3)
            self.map.append(row)

    def draw(self, target_pos):
        world_drawer = WorldDrawer(self.types, ALL_TERRAIN_TILES)
        world_drawer.draw(target_pos, self.map)

    def returnWorld(self):
        return self.newWorld