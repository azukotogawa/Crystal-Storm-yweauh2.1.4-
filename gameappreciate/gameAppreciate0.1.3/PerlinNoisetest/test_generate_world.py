from world import World
from world_drawer import *
from config import *


class generateWorld():
    def generate_height(self, weights, random_seed, types):
        height = World(WORLD_X, WORLD_Y, random_seed, types)
        self.tile_height = height.get_tiled_map(weights)

    def generate_percipitation(self, weights, random_seed, types):
        percipitation = World(WORLD_X, WORLD_Y, random_seed, types)
        self.tile_percipitation = percipitation.get_tiled_map(weights)

    def test_generate_world(self, types, tiles, tile_map):
        world_drawer = WorldDrawer(types, tiles)
        world_drawer.draw(tile_map)

    def getHeightMap(self):
        return self.tile_height

    def getPercipitationMap(self):
        return self.tile_percipitation