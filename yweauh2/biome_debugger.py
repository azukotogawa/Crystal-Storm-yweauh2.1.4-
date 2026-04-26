# world_previewer.py — SHOWS h_value, p_value, h_level, p_level, MAP
import pygame
import sys
import os, bisect
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from world import InfiniteNoiseWorld
from world_drawer import WorldDrawer
from config1 import *

# === SETUP ===
pygame.init()
PREVIEW_WIDTH = 1600
PREVIEW_HEIGHT = 900
SCREEN = pygame.display.set_mode((PREVIEW_WIDTH, PREVIEW_HEIGHT))
pygame.display.set_caption("BIOME DEBUG — h_value, p_value, MAP")
clock = pygame.time.Clock()

# === WORLD ===
world = InfiniteNoiseWorld(world_seed)
world_drawer = WorldDrawer(list(range(40)), ALL_TERRAIN_TILES)

# === CAMERA & ZOOM ===
ZOOM = 1.0
MIN_ZOOM = 0.25
MAX_ZOOM = 32.0
camera_x = 0
camera_y = 0
move_speed = 64 * ZOOM

# === FONTS ===
big_font = pygame.font.Font(None, 38)
small_font = pygame.font.Font(None, 28)

# === MAIN LOOP ===
running = True
while running:
    dt = clock.tick(60) / 1000.0

    # === INPUT ===
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
                move_speed = 64 * (1/ZOOM)

    # === PLAYER TILE (MOUSE) ===
    mx, my = pygame.mouse.get_pos()
    player_x = int((camera_x + mx) // (TILESIZE * ZOOM))
    player_y = int((camera_y + my) // (TILESIZE * ZOOM))

    h_val = world.get_height(player_x, player_y)
    p_val = world.get_precip(player_x, player_y)
    h_norm = (h_val + 1.0) / 2.0  # -1.0 → +1.0 → 0.0 → 1.0
    p_norm = (p_val + 1.0) / 2.0
    h_level = bisect.bisect_left(world.height_cumul, h_norm) - 1
    p_level = bisect.bisect_left(world.precip_cumul, p_norm) - 1
    h_level = max(0, min(39, h_level))
    p_level = max(0, min(39, p_level))

    # === DRAW WORLD ===
    SCREEN.fill((0, 0, 50))

    tile_size = int(TILESIZE * ZOOM)
    start_x = int(camera_x // tile_size)
    start_y = int(camera_y // tile_size)
    end_x = start_x + (PREVIEW_WIDTH // tile_size) + 2
    end_y = start_y + (PREVIEW_HEIGHT // tile_size) + 2

    for wy in range(start_y, end_y):
        for wx in range(start_x, end_x):
            tile_id = world.get_biome(wx, wy)[0]
            tile_img = world_drawer.get_tile(tile_id)
            scaled_img = pygame.transform.scale(tile_img, (tile_size, tile_size))
            screen_x = wx * tile_size - camera_x
            screen_y = wy * tile_size - camera_y
            SCREEN.blit(scaled_img, (screen_x, screen_y))

    # === BIOME DEBUG GUI ===
    gui_bg = pygame.Surface((520, 160))
    gui_bg.fill((0, 0, 0, 200))
    SCREEN.blit(gui_bg, (10, PREVIEW_HEIGHT - 200))

    tile_id = world.get_biome(player_x, player_y)
    biometype = BIOME_NAMES.get(tile_id[0], f"ID {tile_id[0]}") if tile_id[0] is not None else "???"

    lines = [
        f"PLAYER TILE: X={player_x:,}  Y={player_y:,}",
        f"h_val: {h_val:.3f} → h_norm: {h_norm:.3f} → h_level: {h_level}",
        f"p_val: {p_val:.3f} → p_norm: {p_norm:.3f} → p_level: {p_level}",
        f"Biome: {world.get_biome(player_x, player_y)[1]}",
        f"type: {biometype} / {tile_id}",
        f"ZOOM: {ZOOM:.2f}x | ARROWS: MOVE | +/-: ZOOM"
    ]

    for i, line in enumerate(lines):
        color = (255, 255, 0) if i == 4 else (200, 200, 255)
        text = small_font.render(line, True, color)
        SCREEN.blit(text, (20, PREVIEW_HEIGHT - 200 + i*26))

    pygame.display.flip()

pygame.quit()