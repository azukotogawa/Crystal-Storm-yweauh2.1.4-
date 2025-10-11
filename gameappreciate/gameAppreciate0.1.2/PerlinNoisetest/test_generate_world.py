from world import World
from world_drawer import *
from config import *


def test_generate_world(weights, random_seed):
    world_drawer = WorldDrawer()
    print("1")
    world = World(WORLD_X, WORLD_Y, random_seed)
    print("2")
    tile_map = world.get_tiled_map(weights)
    print("3")
    world_drawer.draw(tile_map, wait_for_key = True)
