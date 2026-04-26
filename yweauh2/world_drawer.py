# world_drawer.py
import pygame
from config1 import TILESHEET_PATH
# world_drawer.py — SAFE TILE MAPPING
class WorldDrawer:
    def __init__(self, types, tiles):
        self.tilesheet = pygame.image.load(TILESHEET_PATH).convert()
        self.terrain_tiles = []
        for i in range(40):
            x, y = tiles[i][0]
            tile = self.tilesheet.subsurface((x, y, 64, 64)).convert()
            self.terrain_tiles.append([tile])
        self.display_surface = pygame.display.get_surface()

    def get_tile(self, biome_id):
        if biome_id < 40:
            return self.terrain_tiles[biome_id][0]
        mapping = {
            40: 8, 41: 29, 42: 34, 43: 39, 44: 5, 45: 13, 46: 15, 47: 37,
            48: 29, 49: 12, 50: 36, 51: 14, 52: 9, 53: 21, 54: 8, 55: 7
        }
        tile_idx = mapping.get(biome_id, 9)  # default GRASS
        return self.terrain_tiles[tile_idx][0]