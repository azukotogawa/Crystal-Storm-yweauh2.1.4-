import config
from config import ALL_TERRAIN_TYPES
from test_generate_world import *
from random import randint


# The order of weight values for each terrain type:
#WEIGHTS = [WEIGHT_OCEAN3, WEIGHT_OCEAN2, WEIGHT_OCEAN1, WEIGHT_BEACH, WEIGHT_GRASS, WEIGHT_MOUNTAIN, WEIGHT_SNOW]
#WEIGHTS1 = [70, 20, 20, 12, 35, 30, 0]      # Islands
#WEIGHTS2 = [35, 20, 20, 15, 30, 30, 25]     #
WEIGHTS3 = [15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
            15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
            15, 15, 15, 15, 15, 15, 15, 15, 15, 15]    # Lakes


class PerlinNoise:
    def __init__(self):
        #setup
        pygame.init()
        self.display_surface = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT))
        pygame.display.set_caption('gameAppreciate')
        self.clock = pygame.time.Clock()
        self.running = True

        types = []
        for k in range(40):
            types.append(k)
        actualTypes = []

        newWorld = generateWorld()
        for i in range(40):
            WEIGHTS3[i] = randint(1, 9) * 5
        newWorld.generate_height(WEIGHTS3, randint(0,100), types)
        for i in range(40):
            WEIGHTS3[i] = randint(1, 9) * 5
        newWorld.generate_percipitation(WEIGHTS3, randint(0, 100), types)
        print(newWorld.getHeightMap())
        print(newWorld.getPercipitationMap())
        height = newWorld.getHeightMap()
        percipitation = newWorld.getPercipitationMap()
        map = []
        for i in range(WORLD_Y+1):
            row = []
            for j in range(WORLD_X+1):
                #Lake
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
                    #Basin
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
                    #Valley
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

                    #Desert
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
                    #Tundra
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
                #Forest
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
            map.append(row)


        newWorld.test_generate_world(types, ALL_TERRAIN_TILES, map)

        #test_generate_world(WEIGHTS3, 16, 0, 0, types, LAKE_TERRAIN_TILES)

        #test_generate_world(WEIGHTS3, 14, 1, 0, types, MOUNTAIN_TERRAIN_TILES)

        #test_generate_world(WEIGHTS3, 16, 0, 1, types, TUNDRA_TERRAIN_TILES)

        #for i in range(14):
            #WEIGHTS3[i] = randint(1, 9)*5
        #test_generate_world(WEIGHTS3, 14, 1, 1, types, DESERT_TERRAIN_TILES)

    def run(self):
        while self.running:
            # delta time
            dt = self.clock.tick() / 1000

            # event loop
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False

            # draw world

            pygame.display.update()
        pygame.quit()

if __name__ == '__main__':
    PerlinNoise = PerlinNoise()
    PerlinNoise.run()


#test_generate_world(WEIGHTS1, random_seed = 21)
#test_generate_world(WEIGHTS1, random_seed = 28)
#test_generate_world(WEIGHTS2, random_seed = 7)
#test_generate_world(WEIGHTS2, random_seed = 8)

#test_emerge(WEIGHTS1, random_seed = 21)
#test_emerge(WEIGHTS2, random_seed = 7)
    #test_emerge(WEIGHTS3, random_seed = 16)
#test_emerge(WEIGHTS1, random_seed = 28)
#test_emerge(WEIGHTS2, random_seed = 8)
    #test_emerge(WEIGHTS3, random_seed = 14)