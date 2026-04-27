# main.py - CLEANED VERSION
from config1 import *

import pygame
from groups import AllSprites
from player import Player
from world_drawer import WorldDrawer
from chunk_manager import ChunkManager
from world import InfiniteNoiseWorld
import bisect
import random
from queue import Queue
from datetime import datetime
import hashlib

from appdirs import user_data_dir
import json
import os

# Platform-specific video driver
if sys.platform == "darwin":
    os.environ['SDL_VIDEODRIVER'] = 'cocoa'

HW_FLAGS = pygame.HWSURFACE | pygame.DOUBLEBUF

# === BUILD CUMULATIVES ===
def build_cumul(weights):
    total = sum(weights)
    cumul = [0.0]
    for w in weights:
        cumul.append(cumul[-1] + w / total)
    return cumul

height_cumul = build_cumul(BIOME_WEIGHTS_HEIGHT)
precip_cumul = build_cumul(BIOME_WEIGHTS_PRECIP)

# === SEED MANIFEST ===
MANIFEST_FILE = os.path.join(user_data_dir("yweauh2", "corrow"), "saves", "seeds_manifest.json")

def load_seed_manifest():
    if os.path.exists(MANIFEST_FILE):
        try:
            with open(MANIFEST_FILE, "r") as f:
                return json.load(f)
        except:
            return {}
    return {}

def save_seed_manifest(manifest):
    os.makedirs(os.path.dirname(MANIFEST_FILE), exist_ok=True)
    with open(MANIFEST_FILE, "w") as f:
        json.dump(manifest, f, indent=2)

def get_player_save_path(seed):
    base_dir = user_data_dir("yweauh2", "corrow")
    save_dir = os.path.join(base_dir, "saves")
    os.makedirs(save_dir, exist_ok=True)
    return os.path.join(save_dir, f"player_save_seed_{seed}.json")

def save_player(player, seed):
    path = get_player_save_path(seed)
    data = {
        "center_x": float(player.rect.centerx),
        "center_y": float(player.rect.centery),
        "hitbox_center_x": float(player.hitbox_rect.centerx),
        "hitbox_center_y": float(player.hitbox_rect.centery),
    }
    try:
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        print(f"[SAVE] Player saved for seed {seed}")
    except Exception as e:
        print(f"[SAVE ERROR] {e}")

def load_player(player, seed):
    path = get_player_save_path(seed)
    if not os.path.exists(path):
        print(f"[LOAD] No save for seed {seed} → default spawn")
        return
    try:
        with open(path, "r") as f:
            data = json.load(f)
        player.rect.center = (
            data.get("center_x", player.rect.centerx),
            data.get("center_y", player.rect.centery)
        )
        player.hitbox_rect.center = player.rect.center
        print(f"[LOAD] Loaded position for seed {seed}")
    except Exception as e:
        print(f"[LOAD ERROR] seed {seed}: {e}")

class Game:
    def __init__(self):
        pygame.init()
        self.display_surface = pygame.display.set_mode((WINDOW_WIDTH, WINDOW_HEIGHT), HW_FLAGS)
        pygame.display.set_caption('yweauh2.1.5')
        self.clock = pygame.time.Clock()

        self.running = True

        # World
        self.world_seed = world_seed
        self.world = InfiniteNoiseWorld(self.world_seed)

        # Drawer
        self.world_drawer = WorldDrawer(list(range(40)), ALL_TERRAIN_TILES)

        # Chunk Manager
        self.chunk_manager = ChunkManager(self.world)
        self.chunk_manager.terrain_tiles = self.world_drawer.terrain_tiles

        # Groups & Player
        self.all_sprites = AllSprites()
        self.collision_sprites = pygame.sprite.Group()
        self.player = Player((0, 0), self.all_sprites, self.collision_sprites)
        self.all_sprites.add(self.player)

        load_player(self.player, self.world_seed)

        # Initial chunks
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                self.chunk_manager.request_chunk(dx, dy)

        # UI & State
        self.font = pygame.font.Font(None, 48)
        self.font_small = pygame.font.Font(None, 36)
        self.font_large = pygame.font.Font(None, 48)

        self.save_message_active = False
        self.save_message_frames = 0
        self.save_message_duration = 180

        self.load_message_frames = 0
        self.load_message_duration = 180

        self.frame_count = 0
        self.save_frames = 1800

        self.minimap_scale = 16
        self.minimap_size = 180
        self.minimap_surf = None
        self.minimap_frame = 0
        self.minimap_update_frames = 5

        # Seed UI
        self.seed_selection_active = False
        self.seed_list = []
        self.selected_seed_index = 0

        self.seed_input_active = False
        self.new_seed_text = ""

        self.last_player_center = None
        self.player_velocity = (0.0, 0.0)

    def run(self):
        while self.running:
            dt = self.clock.tick(60) / 1000.0
            self.frame_count += 1

            # Events
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False

                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_F4:  # F2 = change seed
                        self.seed_input_active = not self.seed_input_active
                        if self.seed_input_active:
                            self.new_seed_text = str(self.world_seed)

                    if self.seed_input_active:
                        if event.key == pygame.K_RETURN:  # Enter = apply new seed
                            try:
                                new_seed = int(self.new_seed_text)

                                #
                                save_player(self.player, self.world_seed)
                                #

                                self.change_seed(new_seed)

                                #
                                self.seed_list.append(new_seed)
                                self.refresh_seed_list()
                                #

                                self.seed_input_active = False
                            except ValueError:
                                pass  # invalid → ignore
                        elif event.key == pygame.K_BACKSPACE:
                            self.new_seed_text = self.new_seed_text[:-1]
                        elif event.unicode.isdigit():
                            self.new_seed_text += event.unicode
                    if event.key == pygame.K_F2:
                        if not self.seed_selection_active:
                            self.refresh_seed_list()
                        self.seed_selection_active = not self.seed_selection_active

                    if self.seed_selection_active:
                        if event.key == pygame.K_UP:
                            self.selected_seed_index = max(0, self.selected_seed_index - 1)
                        elif event.key == pygame.K_DOWN:
                            self.selected_seed_index = min(len(self.seed_list), self.selected_seed_index + 1)
                        elif event.key == pygame.K_RETURN:
                            if self.selected_seed_index < len(self.seed_list):
                                seed = self.seed_list[self.selected_seed_index]
                                self.change_seed(seed)
                            else:
                                new_seed = random.randint(10000, 999999999)
                                self.change_seed(new_seed)
                            self.seed_selection_active = False

            # Update
            self.all_sprites.update(dt)

            player_center = self.player.rect.center
            if self.last_player_center is not None:
                dx = player_center[0] - self.last_player_center[0]
                dy = player_center[1] - self.last_player_center[1]
                self.player_velocity = (dx / dt if dt > 0 else 0, dy / dt if dt > 0 else 0)
            self.last_player_center = player_center

            player_tile_x = int(player_center[0] // TILESIZE)
            player_tile_y = int(player_center[1] // TILESIZE)

            self.chunk_manager.update(player_tile_x, player_tile_y, player_center, dt)

            # Draw
            self.display_surface.fill('black')

            self.chunk_manager.draw(player_center, self.world_drawer)

            # Player and UI on top
            self.all_sprites.draw(player_center)

            # Debug Panel
            if SHOW_CHUNK_DEBUG:
                panel_bg = pygame.Surface((200, 360), pygame.SRCALPHA)
                panel_bg.fill((0, 0, 0, 140))
                self.display_surface.blit(panel_bg, (10, 10))

                cx, cy = self.chunk_manager.get_current_chunk(player_tile_x, player_tile_y)
                loaded, expected, queued, qsize = self.chunk_manager.get_stats()
                vx, vy = self.player_velocity
                speed = (vx ** 2 + vy ** 2) ** 0.5

                h_val = self.world.get_height(player_tile_x, player_tile_y)
                p_val = self.world.get_precip(player_tile_x, player_tile_y)

                h_norm = (h_val + 1.0) / 2.0
                p_norm = (p_val + 1.0) / 2.0

                h_level = bisect.bisect_left(self.world.height_cumul, h_norm) - 1
                p_level = bisect.bisect_left(self.world.precip_cumul, p_norm) - 1
                h_level = max(0, min(39, h_level))
                p_level = max(0, min(39, p_level))

                tile_id = self.chunk_manager.get_tile_at(player_tile_x, player_tile_y)
                terrain_name = BIOME_NAMES.get(tile_id, f"ID {tile_id}") if tile_id is not None else "???"

                lines = [
                    f"Chunk: ({cx}, {cy})",
                    f"Seed: {self.world.seed}",
                    f"Loaded: {loaded} / {expected}",
                    f"Pos: {player_center[0]:.0f}, {player_center[1]:.0f}",
                    f"FPS: {int(self.clock.get_fps())}",
                    f"Tile: ({player_tile_x}, {player_tile_y})",
                    f"Terrain: {terrain_name}",
                    f"Biome: {self.world.get_biome(player_tile_x, player_tile_y)[1]}",
                    f"h,p: {h_level}, {p_level}",
                    f"Vel: {vx:.0f},{vy:.0f} ({speed:.0f})",
                    f"Chunks: {len(self.chunk_manager.chunks)}",
                    f"Blend: {settings.blend_width}px {settings.blend_strength:.1f}",
                    f"Q:{qsize} Wait:{queued}",
                ]

                for i, txt in enumerate(lines):
                    surf = self.font_small.render(txt, True, (255, 255, 255))
                    self.display_surface.blit(surf, (20, 15 + i * 26))

            # F1 = toggle blend
            keys = pygame.key.get_pressed()
            if keys[pygame.K_F1]:
                settings.blend_strength = 0.0 if settings.blend_strength > 0 else 0.7

            # F3 = mini-map
            if keys[pygame.K_F3]:
                self.show_mini_map = not getattr(self, "show_mini_map", False)

            if getattr(self, "show_mini_map", False):
                self.draw_minimap(self.display_surface, self.world, self.player)

            if self.load_message_duration != self.load_message_frames:
                self.loaded_message = "Loaded save position!" if os.path.exists(get_player_save_path(self.world_seed)) else ""
                font = pygame.font.Font(None, 48)
                text = font.render(self.loaded_message, True, (255, 255, 255))
                self.display_surface.blit(text, (WINDOW_WIDTH // 2 - text.get_width() // 2, 100))
                self.load_message_frames += 1

                # Check if any visible chunk is missing (simple heuristic)
                missing_chunks = False
                pcx = int(player_center[0] // (CHUNK_SIZE * TILESIZE))
                pcy = int(player_center[1] // (CHUNK_SIZE * TILESIZE))
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        if (pcx + dx, pcy + dy) not in self.chunk_manager.chunks:
                            missing_chunks = True
                            break
                    if missing_chunks:
                        break

                if missing_chunks:
                    font = pygame.font.Font(None, 48)
                    text_surf = font.render("Loading terrain...", True, (200, 220, 255))
                    text_rect = text_surf.get_rect(center=(WINDOW_WIDTH // 2, WINDOW_HEIGHT - 80))

                    # Optional semi-transparent background
                    bg_surf = pygame.Surface((text_rect.width + 60, text_rect.height + 40), pygame.SRCALPHA)
                    bg_surf.fill((0, 0, 0, 180))
                    bg_rect = bg_surf.get_rect(center=text_rect.center)

                    self.display_surface.blit(bg_surf, bg_rect)
                    self.display_surface.blit(text_surf, text_rect)

            # Autosave message
            if self.save_message_active:
                alpha = int(255 * (self.save_message_frames / self.save_message_duration))
                text_surf = self.font.render("Autosaved!", True, (255, 255, 255))
                text_surf.set_alpha(alpha)
                text_rect = text_surf.get_rect(center=(WINDOW_WIDTH // 2, 60))
                bg_surf = pygame.Surface((text_rect.width + 40, text_rect.height + 20), pygame.SRCALPHA)
                bg_surf.fill((0, 0, 0, 140))
                bg_rect = bg_surf.get_rect(center=text_rect.center)
                self.display_surface.blit(bg_surf, bg_rect)
                self.display_surface.blit(text_surf, text_rect)

            if self.seed_input_active:
                # Semi-transparent input box
                input_surf = pygame.Surface((200, 50), pygame.SRCALPHA)
                input_surf.fill((0, 0, 0, 180))
                input_rect = input_surf.get_rect(center=(WINDOW_WIDTH // 2, WINDOW_HEIGHT // 2))

                font = pygame.font.Font(None, 36)
                text = font.render(f"New seed: {self.new_seed_text}", True, (255, 255, 255))

                self.display_surface.blit(input_surf, input_rect)
                self.display_surface.blit(text, (input_rect.x + 10, input_rect.y + 10))

                # Instructions
                instr = self.font_small.render("F2=Toggle | Enter=Apply", True, (200, 200, 200))
                self.display_surface.blit(instr, (input_rect.x + 10, input_rect.bottom + 5))

            # Seed Selection UI
            if self.seed_selection_active:
                self.draw_seed_selection()

            pygame.display.update()

        # Shutdown
        self.chunk_manager.shutdown()
        save_player(self.player, self.world_seed)
        pygame.quit()

    # === SEED SELECTION UI ===
    def refresh_seed_list(self):
        self.seed_list = []
        manifest = load_seed_manifest()
        for seed_str in manifest.keys():
            try:
                self.seed_list.append(int(seed_str))
            except:
                pass
        self.seed_list.sort()
        self.selected_seed_index = 0

    def draw_seed_selection(self):
        if not self.seed_selection_active:
            return

        overlay = pygame.Surface((WINDOW_WIDTH, WINDOW_HEIGHT), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 200))
        self.display_surface.blit(overlay, (0, 0))

        title = self.font_large.render("Select World", True, (255, 255, 255))
        self.display_surface.blit(title, (WINDOW_WIDTH//2 - title.get_width()//2, 80))

        for i, seed in enumerate(self.seed_list):
            color = (255, 255, 100) if i == self.selected_seed_index else (200, 200, 200)
            text = self.font_small.render(f"Seed: {seed}", True, color)
            y = 180 + i * 50
            self.display_surface.blit(text, (WINDOW_WIDTH//2 - text.get_width()//2, y))

        new_color = (255, 255, 100) if self.selected_seed_index == len(self.seed_list) else (180, 180, 180)
        new_text = self.font_small.render("→ New Random Seed", True, new_color)
        self.display_surface.blit(new_text, (WINDOW_WIDTH//2 - new_text.get_width()//2, 180 + len(self.seed_list)*50 + 40))

        instr = self.font_small.render("↑↓ Navigate  Enter Select  F2 Close", True, (150, 150, 150))
        self.display_surface.blit(instr, (WINDOW_WIDTH//2 - instr.get_width()//2, WINDOW_HEIGHT - 80))

    def change_seed(self, new_seed):
        print(f"[SEED CHANGE] Switching to seed {new_seed}...")

        # Save current player position
        save_player(self.player, self.world_seed)

        # Fully shutdown old chunk manager
        if hasattr(self, 'chunk_manager'):
            self.chunk_manager.shutdown()

        # Create new world
        self.world_seed = new_seed
        self.world = InfiniteNoiseWorld(new_seed)

        # Create a completely fresh ChunkManager
        self.chunk_manager = ChunkManager(self.world, self.world_drawer)

        # Reset player to spawn
        self.player.rect.center = (0, 0)
        self.player.hitbox_rect.center = (0, 0)
        load_player(self.player, new_seed)

        # Request initial chunks
        for dx in range(-5, 6):
            for dy in range(-5, 6):
                self.chunk_manager.request_chunk(dx, dy)

        # Save to manifest
        manifest = load_seed_manifest()
        manifest[str(new_seed)] = {"created": datetime.now().isoformat()}
        save_seed_manifest(manifest)

        print(f"✓ Successfully loaded new world with seed {new_seed}")

if __name__ == '__main__':
    Game().run()