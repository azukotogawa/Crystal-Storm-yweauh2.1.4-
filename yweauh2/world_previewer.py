# world_previewer.py — 54 BIOMES, 40 TILES, NO ERRORS
import pygame
import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from world import InfiniteNoiseWorld
from world_drawer import WorldDrawer
from config1 import *

# === SETUP ===
pygame.init()
PREVIEW_WIDTH = 1600
PREVIEW_HEIGHT = 900
SCREEN = pygame.display.set_mode((PREVIEW_WIDTH, PREVIEW_HEIGHT))
pygame.display.set_caption("WORLD PREVIEWER — 54 BIOMES")
clock = pygame.time.Clock()

# === BIOME & CLUSTER SCALE ===
BIOME_SCALE = 860.0    # Smaller = tighter biomes
CLUSTER_SCALE = 2000.0 # Smaller = tighter continents

world = InfiniteNoiseWorld(world_seed)
world_drawer = WorldDrawer(list(range(40)), ALL_TERRAIN_TILES)

# === CAMERA & ZOOM ===
ZOOM = 1.0
MIN_ZOOM = 0.25/32
MAX_ZOOM = 32.0
camera_x = -1000
camera_y = -1000
move_speed = 64 * ZOOM

# === MAIN LOOP ===
running = True
while running:
    dt = clock.tick(60) / 1000.0

    keys = pygame.key.get_pressed()
    if keys[pygame.K_LEFT]:  camera_x += move_speed
    if keys[pygame.K_RIGHT]: camera_x -= move_speed
    if keys[pygame.K_UP]:    camera_y += move_speed
    if keys[pygame.K_DOWN]:  camera_y -= move_speed

    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_EQUALS or event.key == pygame.K_PLUS:
                ZOOM = min(MAX_ZOOM, ZOOM * 1.25)
                move_speed = 64 * ZOOM
            elif event.key == pygame.K_MINUS:
                ZOOM = max(MIN_ZOOM, ZOOM / 1.25)
                move_speed = 64 * ZOOM

    SCREEN.fill((0, 0, 50))

    tile_size = int(TILESIZE * ZOOM)
    start_x = int(camera_x // tile_size)
    start_y = int(camera_y // tile_size)
    end_x = start_x + (PREVIEW_WIDTH // tile_size) + 2
    end_y = start_y + (PREVIEW_HEIGHT // tile_size) + 2

    mx, my = pygame.mouse.get_pos()
    tile_x = int((camera_x + mx) // (TILESIZE * ZOOM))
    tile_y = int((camera_y + my) // (TILESIZE * ZOOM))
    biome_id = world.get_biome(tile_x, tile_y)

    for wy in range(start_y, end_y):
        for wx in range(start_x, end_x):
            tile_id = world.get_biome(wx, wy)[0]
            tile_img = world_drawer.get_tile(tile_id)  # ← SAFE
            scaled_img = pygame.transform.scale(tile_img, (tile_size, tile_size))
            screen_x = wx * tile_size - camera_x
            screen_y = wy * tile_size - camera_y
            SCREEN.blit(scaled_img, (screen_x, screen_y))

    font = pygame.font.Font(None, 36)
    text = font.render(f"SEED: {world_seed} | ZOOM: {ZOOM:.2f}x | FPS: {int(clock.get_fps())}", True, (255, 255, 255))
    SCREEN.blit(text, (10, 10))

    big_font = pygame.font.Font(None, 42)
    small_font = pygame.font.Font(None, 30)

    gui_bg = pygame.Surface((500, 100))
    gui_bg.fill((0, 0, 0, 200))
    SCREEN.blit(gui_bg, (10, PREVIEW_HEIGHT - 110))

    lines = [
        f"TILE: X={tile_x:,}  Y={tile_y:,}",
        f"BIOME ID: {biome_id} → {BIOME_NAMES.get(biome_id, '???')}",
        f"ZOOM: {ZOOM:.2f}x | ARROWS: MOVE | +/-: ZOOM"
    ]

    for i, line in enumerate(lines):
        color = (255, 255, 0) if i == 0 else (200, 200, 255)
        text = small_font.render(line, True, color)
        SCREEN.blit(text, (20, PREVIEW_HEIGHT - 100 + i * 26))

    pygame.display.flip()

pygame.quit()