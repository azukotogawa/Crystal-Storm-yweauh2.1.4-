# world_drawer.py — 4 HEIGHT VARIANTS
import pygame
from config1 import TILESHEET_PATH

class WorldDrawer:
    def __init__(self, types, tiles):
        self.tilesheet = pygame.image.load(TILESHEET_PATH).convert_alpha()
        self.terrain_tiles = []  # list of [low, med-low, med-high, high] surfaces

        for tile_data in tiles:          # each entry has 4 (x,y) tuples
            variants = []
            for x, y in tile_data:
                try:
                    tile = self.tilesheet.subsurface((x, y, 64, 64)).convert_alpha()
                except:
                    tile = pygame.Surface((64, 64))
                    tile.fill((255, 0, 0))  # red = error
                variants.append(tile)
            self.terrain_tiles.append(variants)

        print(f"[WorldDrawer] Loaded {len(self.terrain_tiles)} base tiles with 4 height variants")

    def get_tile(self, tid, variant=0):
        if tid < 0 or tid >= len(self.terrain_tiles):
            tid = 9
        variant = max(0, min(3, variant))
        return self.terrain_tiles[tid][variant]