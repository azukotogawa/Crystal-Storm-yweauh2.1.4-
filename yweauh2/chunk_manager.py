# chunk_manager.py — cleaned & fixed 2025 version
import os
import pickle
import threading, queue
from queue import Queue
import pygame
from concurrent.futures import ThreadPoolExecutor
from multiprocessing import Pool, cpu_count
from config1 import *  # CHUNK_SIZE, TILESIZE, WINDOW_WIDTH, WINDOW_HEIGHT, get_chunk_path
from world import InfiniteNoiseWorld

def generate_chunk_tile_ids(args):
    """Top-level picklable worker function for multiprocessing"""
    cx, cy, seed = args
    world = InfiniteNoiseWorld(seed)           # recreate — no shared state
    chunk = Chunk(cx, cy, world, terrain_tiles=None)  # no surface, no terrain_tiles yet
    return (cx, cy, chunk.tile_ids)


class Chunk:
    def __init__(self, cx, cy, world, terrain_tiles):
        self.cx = cx
        self.cy = cy
        self.world = world
        self.terrain_tiles = terrain_tiles
        self.tile_ids = [[0] * CHUNK_SIZE for _ in range(CHUNK_SIZE)]
        self.surface = None

        # === VISUAL HEIGHT CONTROL ===
        self.visual_height_scale = 90  # ← Change this number to tune drama (45 = subtle, 90 = very tall)

        # Generate tile IDs
        for ly in range(CHUNK_SIZE):
            for lx in range(CHUNK_SIZE):
                wx = cx * CHUNK_SIZE + lx + 0.5
                wy = cy * CHUNK_SIZE + ly + 0.5
                biome_result = world.get_biome(wx, wy)
                self.tile_ids[ly][lx] = biome_result[0]

        self._cached_surface = None   # optional internal cache

    def render_surface(self, drawer):
        """Legacy method - kept for compatibility but no longer used"""
        if self.surface is None:
            self.surface = pygame.Surface((CHUNK_SIZE * TILESIZE, CHUNK_SIZE * TILESIZE), pygame.SRCALPHA)
        return self.surface

class ChunkManager:
    def __init__(self, world, drawer=None):
        self.world = world
        self.drawer = drawer               # needed for tile → image lookup
        self.chunks = {}                   # (cx,cy) → Chunk
        self.chunks_lock = threading.Lock()
        self.queued = set()
        self.load_queue = Queue()

        self.executor = ThreadPoolExecutor(max_workers=8)  # for background rendering

        # Single background loader thread
        self.worker = threading.Thread(target=self._background_worker, daemon=True)
        self.worker.start()

        print(f"[ChunkManager] Started with {self.executor._max_workers} render workers")

        self.last_player_pos = None
        self.player_velocity = (0, 0)

        self._shutdown = False

    def _sync_request_chunks_around(self, center_x, center_y, radius=3):
        pcx = int(center_x) // CHUNK_SIZE
        pcy = int(center_y) // CHUNK_SIZE
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                cx, cy = pcx + dx, pcy + dy
                key = (cx, cy)
                if key in self.chunks:
                    continue
                print(f"[SYNC LOAD] {cx},{cy}")
                chunk = self._load_or_generate(cx, cy)
                if chunk:
                    if chunk.surface is None and self.drawer:
                        chunk.render_surface(self.drawer)
                    with self.chunks_lock:
                        self.chunks[key] = chunk

    def request_chunks_around(self, center_x, center_y, radius=3):
        """Request chunks in a square around player/center"""
        pcx = int(center_x) // CHUNK_SIZE
        pcy = int(center_y) // CHUNK_SIZE

        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                cx, cy = pcx + dx, pcy + dy
                key = (cx, cy)
                if key in self.chunks or key in self.queued:
                    continue
                if len(self.queued) > 80:  # prevent queue explosion
                    return
                self.queued.add(key)
                self.load_queue.put(key)

    def request_chunk(self, cx, cy):
        key = (cx, cy)
        if key in self.chunks or key in self.queued:
            return

        if len(self.queued) > 6:  # very low queue limit
            return

        self.queued.add(key)
        self.load_queue.put(key)

    def _background_worker(self):
        print("[Worker] Background thread started")
        while True:
            try:
                item = self.load_queue.get(timeout=5.0)
            except queue.Empty:
                continue

            try:
                if item == "STOP":
                    self.load_queue.task_done()
                    break

                cx, cy = item
                key = (cx, cy)

                chunk = self._load_or_generate(cx, cy)
                if chunk:
                    # Render surface using the correct method name
                    if chunk.surface is None and self.drawer:
                        chunk.surface = chunk.render_surface(self.drawer)

                    with self.chunks_lock:
                        self.chunks[key] = chunk

                self.queued.discard(key)
                self.load_queue.task_done()

            except Exception as e:
                print(f"[Worker ERROR] chunk ({cx},{cy}): {e}")
                self.queued.discard(key)
                self.load_queue.task_done()

    def shutdown(self):
        print("[ChunkManager] Shutting down...")
        self._shutdown = True  # ← add this flag

        if hasattr(self, 'load_queue'):
            self.load_queue.put("STOP")
            try:
                self.load_queue.join(timeout=3.0)
            except:
                pass

        if hasattr(self, 'executor'):
            try:
                self.executor.shutdown(wait=True, cancel_futures=True)
            except:
                pass

        print("[ChunkManager] Shutdown complete")

    def _render_in_background(self, chunk):
        if chunk.surface is None:
            chunk.surface = chunk.render_surface(self.drawer)
        return chunk

    def _load_or_generate(self, cx, cy):
        path = get_chunk_path(cx, cy, self.world.seed)

        if os.path.exists(path):
            try:
                with open(path, "rb") as f:
                    chunk = pickle.load(f)
                chunk.world = self.world
                chunk.terrain_tiles = None
                return chunk
            except Exception as e:
                print(f"[Load] Corrupt/old file {path}: {e}")
                try:
                    os.remove(path)
                except:
                    pass

        print("[Load] Generating new chunk")
        chunk = Chunk(cx, cy, self.world, terrain_tiles=None)
        print("[Load] Chunk object created, saving...")
        self._save_to_disk(chunk, cx, cy)
        return chunk

    def _save_to_disk(self, chunk, cx, cy):
        path = get_chunk_path(cx, cy, self.world.seed)
        backup_surf = chunk.surface
        chunk.surface = None  # Surfaces are not picklable

        try:
            tmp = path + ".tmp"
            with open(tmp, "wb") as f:
                pickle.dump(chunk, f, protocol=pickle.HIGHEST_PROTOCOL)
            os.replace(tmp, path)
        except Exception as e:
            print(f"[Save failed] {path}: {e}")
        finally:
            chunk.surface = backup_surf

    def update(self, player_tile_x, player_tile_y, target_pos, dt):
        pcx = player_tile_x // CHUNK_SIZE
        pcy = player_tile_y // CHUNK_SIZE

        # Velocity tracking
        if hasattr(self, 'last_player_pos') and self.last_player_pos is not None:
            dx = target_pos[0] - self.last_player_pos[0]
            dy = target_pos[1] - self.last_player_pos[1]
            self.player_velocity = (dx / dt if dt > 0 else 0, dy / dt if dt > 0 else 0)
        else:
            self.player_velocity = (0, 0)

        self.last_player_pos = target_pos

        # === EXTREMELY CONSERVATIVE LOADING ===
        load_radius = 2  # only load a small area around player
        loaded_this_frame = 0

        for dx in range(-load_radius, load_radius + 1):
            for dy in range(-load_radius, load_radius + 1):
                cx = pcx + dx
                cy = pcy + dy
                key = (cx, cy)

                if key not in self.chunks and key not in self.queued:
                    self.request_chunk(cx, cy)
                    loaded_this_frame += 1
                    if loaded_this_frame >= 3:  # max 3 new chunks per frame
                        break
            if loaded_this_frame >= 3:
                break

        # === VERY AGGRESSIVE UNLOAD ===
        unload_radius = 5  # unload anything outside this small radius
        to_remove = []
        with self.chunks_lock:
            for key in list(self.chunks.keys()):
                cx, cy = key
                dist = max(abs(cx - pcx), abs(cy - pcy))
                if dist > unload_radius:
                    to_remove.append(key)

        for key in to_remove:
            if key in self.chunks:
                chunk = self.chunks.pop(key)
                if chunk.surface is not None:
                    chunk.surface = None

    def reset(self):
        """Fully reset for new seed"""
        print("[ChunkManager] Full reset for new seed")
        with self.chunks_lock:
            self.chunks.clear()
        self.queued.clear()
        self.load_queue = Queue()  # new queue

    def __del__(self):
        if hasattr(self, 'surface') and self.surface is not None:
            self.surface = None

    def draw(self, camera_pos, drawer):
        if drawer is None:
            return

        target_surface = pygame.display.get_surface()
        left = camera_pos[0] - WINDOW_WIDTH // 2
        top = camera_pos[1] - WINDOW_HEIGHT // 2

        start_cx = int(left // (CHUNK_SIZE * TILESIZE)) - 1
        start_cy = int(top // (CHUNK_SIZE * TILESIZE)) - 2
        end_cx = start_cx + (WINDOW_WIDTH // (CHUNK_SIZE * TILESIZE)) + 3
        end_cy = start_cy + (WINDOW_HEIGHT // (CHUNK_SIZE * TILESIZE)) + 5

        for cy in range(start_cy, end_cy + 1):
            for cx in range(start_cx, end_cx + 1):
                key = (cx, cy)
                chunk = self.chunks.get(key)
                if not chunk:
                    continue

                if chunk.surface is None:
                    chunk.surface = chunk.render_surface(drawer)

                sx = cx * CHUNK_SIZE * TILESIZE - int(left)
                sy = cy * CHUNK_SIZE * TILESIZE - int(top) - 620  # bigger padding

                target_surface.blit(chunk.surface, (sx, sy))

    def get_current_chunk(self, tx, ty):
        return int(tx) // CHUNK_SIZE, int(ty) // CHUNK_SIZE

    def get_stats(self):
        """
        Returns values used by the debug overlay.
        Order: loaded, expected, queued_count, queue_size
        """
        loaded = len(self.chunks)
        expected = 25  # or dynamic calculation
        queued_count = len(self.queued)
        queue_size = self.load_queue.qsize()
        return loaded, expected, queued_count, queue_size

    def get_tile_id(self, world_x, world_y):
        cx = int(world_x) // CHUNK_SIZE
        cy = int(world_y) // CHUNK_SIZE
        key = (cx, cy)
        if key not in self.chunks:
            return 0  # fallback — do NOT request here!
        chunk = self.chunks[key]
        lx = int(world_x) % CHUNK_SIZE
        ly = int(world_y) % CHUNK_SIZE
        return chunk.tile_ids[ly][lx]

    def get_tile_at(self, world_x, world_y):
        return self.get_tile_id(world_x, world_y)  # alias if needed

    def unload_distant_chunks(self, center_x, center_y, max_distance=10):
        pcx = int(center_x) // CHUNK_SIZE
        pcy = int(center_y) // CHUNK_SIZE
        to_remove = []
        for (cx, cy) in list(self.chunks.keys()):
            dist = max(abs(cx - pcx), abs(cy - pcy))
            if dist > max_distance:
                to_remove.append((cx, cy))
        for key in to_remove:
            del self.chunks[key]

    # Compatibility aliases (add this at the very end of the ChunkManager class)
    get_tile_at = get_tile_id               # keep old name working if used elsewhere