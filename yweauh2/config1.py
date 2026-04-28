# config1.py — FULLY CONVERGED: 54 BIOMES, 40 TILES, 8+ FACTORS
import os, sys
from appdirs import user_data_dir
import hashlib  # for seed → folder name

APP_NAME   = "yweauh2"
APP_AUTHOR = "corrow"           # your handle/username

SAVE_DIR      = os.path.join(user_data_dir(APP_NAME, APP_AUTHOR), "saves")
CHUNK_SAVE_DIR = os.path.join(user_data_dir(APP_NAME, APP_AUTHOR), "chunks")

os.makedirs(SAVE_DIR, exist_ok=True)
os.makedirs(CHUNK_SAVE_DIR, exist_ok=True)

APP_DATA_DIR = user_data_dir("yweauh2", "corrow")

CHUNK_BASE_DIR = os.path.join(user_data_dir("yweauh2", "corrow"), "chunks")

def get_seed_folder(seed):
    """Return a unique folder for each seed"""
    if seed is None:
        seed = 0
    # Use a strong hash to create unique folder name
    seed_str = str(seed)
    seed_hash = hashlib.md5(seed_str.encode('utf-8')).hexdigest()[:16]
    folder_name = f"seed_{seed_hash}"
    return os.path.join(CHUNK_BASE_DIR, folder_name)

def get_chunk_path(cx, cy, seed):
    """Return full path to chunk file for this seed"""
    folder = get_seed_folder(seed)
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, f"{cx}_{cy}.chunk")

# Player save (also seed-aware, optional)
PLAYER_SAVE_FILE = os.path.join(APP_DATA_DIR, "saves", "player.json")

def resource_path(relative_path):
    try: base_path = sys._MEIPASS
    except Exception: base_path = os.path.abspath("")
    return os.path.join(base_path, relative_path)

TILESHEET_PATH = resource_path("files/voxelsnew1.png")

# === WINDOW & SETTINGS ===
WINDOW_WIDTH = 960
WINDOW_HEIGHT = 540
TILESIZE = 64
CHUNK_SIZE = 32
CHUNK_PRELOAD_DIST = 1
CHUNK_UNLOAD_DIST = 2
CHUNK_VIEW_RADIUS = 2
MOVEMENT_PREDICTION = True

SHOW_CHUNK_DEBUG = True
BLEND_WIDTH = 8
BLEND_STRENGTH = 0.7

# === SEED ===
world_seed = 12349

# === WORLD FACTORS ===
FACTOR_HEIGHT   = "height"
FACTOR_PRECIP   = "precip"
FACTOR_TEMP     = "temp"
FACTOR_HUMIDITY = "humidity"
FACTOR_EROSION  = "erosion"
FACTOR_TECTONIC = "tectonic"
FACTOR_WIND     = "wind"
FACTOR_MAGIC    = "magic"

ALL_FACTORS = [FACTOR_HEIGHT, FACTOR_PRECIP, FACTOR_TEMP, FACTOR_HUMIDITY,
               FACTOR_EROSION, FACTOR_TECTONIC, FACTOR_WIND, FACTOR_MAGIC]

# === BIOME IDs (0–53) ===
LAKE, LAKE2, LAKE3, BEACH, BEACH2, BEACH3, \
GRASS, GRASS2, GRASS3, GRASS4, GRASS5, DESERT, DESERT2, DESERT3, \
TUNDRA, TUNDRA2, TUNDRA3, RIVER, BASIN, BASIN2, BASIN3, VALLEY3, VALLEY2, VALLEY, \
FOREST, FOREST2, FOREST3, FOREST4, MOUNTAIN, MOUNTAIN2, MOUNTAIN3, MOUNTAIN4, \
MOUNTAIN5, MOUNTAIN6, MOUNTAIN7, SNOW, SNOW2, SNOW3 = range(38)
'''CORAL, MANGROVE, VOLCANO, GLACIER, CANYON, FLOATING, DUNES, CRYSTAL,
JUNGLE, SAVANNA, PLATEAU, OASIS, ISLAND, SWAMP, TROPICAL, ARCTIC'''

# === EXTREME-BIASED (0 & 39 = 300, middle = 50) ===
# === OPTIMAL WEIGHTS — 0–39 FULLY USED ===
BIOME_WEIGHTS_HEIGHT = [
    300, 250, 200, 180, 160, 140, 120, 100, 90, 90,   # 0–9  (deep basins)
    90,  90,  85,  70,  60,  50,  50,  55,  60,  70,   # 10–19 (plains)
    80,  90, 100, 120, 140, 160, 180, 90, 90, 90,   # 20–29 (mountains)
    100, 100, 10, 100, 150, 160, 170, 200, 250, 300    # 30–39 (snowy peaks)
]

BIOME_WEIGHTS_PRECIP = [
    400, 350, 300, 180, 160, 140, 120, 100, 90, 90,   # 0–9  (deep basins)
    90,  90,  85,  70,  60,  50,  50,  55,  60,  70,   # 10–19 (plains)
    80,  90, 100, 120, 140, 160, 180, 90, 90, 90,   # 20–29 (mountains)
    100, 100, 10, 100, 150, 160, 170, 200, 250, 300    # 30–39 (snowy peaks)
]

# === BIOME MAPS (40 tiles) ===
LAKE_MAP = [LAKE] + [LAKE2]*2 + [LAKE3]*2 + [BEACH]*2 + [BEACH2]*2 + [BEACH3] + \
           [GRASS]*2 + [GRASS2]*2 + [RIVER] * 2 + [GRASS3]*2 + [GRASS4] + [GRASS5]

DRY_MAP = [BASIN3] + [BASIN2]*2 + [BASIN]*2 + [VALLEY]*2 + [VALLEY2]*2 + [VALLEY3] + \
          [DESERT]*2 + [DESERT2]*2 + [DESERT3] + [TUNDRA]*2 + [TUNDRA2]*2 + [TUNDRA3]

HIGH_MAP = [GRASS3] + [GRASS4] + [GRASS5] + [FOREST] + [FOREST2]*2 + [RIVER] + [FOREST3]*2 + [FOREST4] + \
           [MOUNTAIN] + [MOUNTAIN2] + [MOUNTAIN3] + [MOUNTAIN4] + \
            [MOUNTAIN5] + [MOUNTAIN6] + [MOUNTAIN7] + [SNOW] + [SNOW2] + [SNOW3]

# === SPECIAL BIOME MAPS (use existing tiles) ===
VOLCANO_MAP = [MOUNTAIN5]*20
GLACIER_MAP = [SNOW3]*20
CORAL_MAP = [BEACH3]*20
MANGROVE_MAP = [FOREST4]*20
CANYON_MAP = [VALLEY3]*20
FLOATING_MAP = [GRASS5]*20
DUNES_MAP = [DESERT2]*20
CRYSTAL_MAP = [SNOW]*20
JUNGLE_MAP = [FOREST4]*10 + [GRASS5]*6 + [LAKE]*4
SAVANNA_MAP = [GRASS]*8 + [DESERT]*8 + [RIVER]*4
PLATEAU_MAP = [MOUNTAIN7]*20
OASIS_MAP = [DESERT]*16 + [LAKE]*2 + [GRASS5]*2
ISLAND_MAP = [LAKE3]*16 + [BEACH]*2 + [GRASS]*2
SWAMP_MAP = [BASIN]*10 + [LAKE]*6 + [GRASS5]*4
TROPICAL_MAP = [GRASS5]*8 + [FOREST4]*8 + [RIVER]*4
ARCTIC_MAP = [SNOW3]*12 + [TUNDRA3]*8

# === TERRAIN TILES — 40 base tiles with 4 height variants ===
# Format: [low, medium-low, medium, high] for each base tile

ALL_TERRAIN_TILES = [
    # 0-2: Lakes
    [(0, 0),   (0, 64),   (0, 128),   (0, 192)],
    [(64, 0),  (64, 64),  (64, 128),  (64, 192)],
    [(128, 0), (128, 64), (128, 128), (128, 192)],

    # 6-8: Beaches
    [(192, 0),   (192, 64),   (92, 128),   (192, 192)],
    [(256, 0),  (256, 64),  (256, 128),  (256, 192)],
    [(320, 0), (320, 64), (320, 128), (320, 192)],

    # 9-13: Grass
    [(384, 0), (384, 64), (384, 128), (384, 192)],
    [(448, 0), (448, 64), (448, 128), (448, 192)],
    [(512, 0), (512, 64), (512, 128), (512, 192)],
    [(576, 0), (576, 64), (576, 128), (576, 192)],
    [(640, 0), (640, 64), (640, 128),  (640, 192)],

    # 14-16: Desert
    [(1792, 0), (1792, 64), (1792, 128), (1792, 192)],
    [(1856, 0), (1856, 64), (1856, 128), (1856, 192)],
    [(1920, 0), (1920, 64), (1920, 128), (1920, 192)],

    # 17-19: Tundra
    [(1984, 0), (1984, 64), (1984, 128), (1984, 192)],
    [(2048, 0), (2048, 64), (2048, 128), (2048, 192)],
    [(2112, 0), (2112, 64), (2112, 128), (2112, 192)],

    # 20: River
    [(2368, 0), (2368, 64), (2368, 128), (2368, 192)],

    # 21-23: Basin
    [(2304, 0), (2304, 64), (2304, 128), (2304, 192)],
    [(2240, 0), (2240, 64), (2240, 128), (2240, 192)],
    [(2176, 0), (2176, 64), (2176, 128), (2176, 192)],

    # 3-5: Valleys
    [(1728, 0), (1728, 64), (1728, 128), (1728, 192)],
    [(1664, 0), (1664, 64), (1664, 128),  (1664, 192)],   # note: if image is only 256 tall, adjust
    [(1600, 0), (1600, 64), (1600, 128),  (1600, 192)],

    # 26-29: Forest
    [(704, 0), (704, 64), (704, 128), (704, 192)],
    [(768, 0), (768, 64), (768, 128), (768, 192)],
    [(832, 0),   (832, 64),   (832, 128),   (832, 192)],
    [(896, 0),  (896, 64),  (896, 128),  (896, 192)],

    # 30-36: Mountains
    [(960, 0), (960, 64), (960, 128), (960, 192)],
    [(1024, 0), (1024, 64), (1024, 128), (1024, 192)],
    [(1088, 0), (1088, 64), (1088, 128), (1088, 192)],
    [(1152, 0), (1152, 64), (1152, 128), (1152, 192)],
    [(1216, 0), (1216, 64), (1216, 128), (1216, 192)],
    [(1280, 0),  (1280, 64),  (1280, 128),   (1280, 192)],
    [(1344, 0),  (1344, 64),  (1344, 128),   (1344, 192)],

    # 37-39: Snow
    [(1408, 0), (1408, 64), (1408, 128), (1408, 192)],
    [(1472, 0), (1472, 64), (1472, 128), (1472, 192)],
    [(1536, 0), (1536, 64), (1536, 128), (1536, 192)],
]

# === BIOME NAMES (for debug) ===
BIOME_NAMES = {
    LAKE: "Deep Ocean", LAKE2: "Ocean", LAKE3: "Shallow Sea",
    BEACH: "Beach", BEACH2: "Sandy Beach", BEACH3: "Coral Reef",
    GRASS: "Grass", GRASS2: "Meadow", GRASS3: "Plains", GRASS4: "Steppe", GRASS5: "Savanna",
    DESERT: "Desert", DESERT2: "Dunes", DESERT3: "Badlands",
    TUNDRA: "Tundra", TUNDRA2: "Frozen Plains", TUNDRA3: "Permafrost",
    RIVER: "River", BASIN: "Basin", BASIN2: "Dry Lake", BASIN3: "Salt Flat",
    VALLEY3: "Ravine", VALLEY2: "Canyon", VALLEY: "Valley",
    FOREST: "Forest", FOREST2: "Dense Forest", FOREST3: "Pine Forest", FOREST4: "Jungle",
    MOUNTAIN: "Mountain", MOUNTAIN2: "Ridge", MOUNTAIN3: "Peak", MOUNTAIN4: "Cliff",
    MOUNTAIN5: "Volcano", MOUNTAIN6: "Canyon", MOUNTAIN7: "Plateau",
    SNOW: "Snow", SNOW2: "Ice Field", SNOW3: "Glacier"
    '''CORAL: "Coral Reef", MANGROVE: "Mangrove", VOLCANO: "Active Volcano",
    GLACIER: "Glacier", CANYON: "Grand Canyon", FLOATING: "Floating Island",
    DUNES: "Sand Dunes", CRYSTAL: "Crystal Cave", JUNGLE: "Rainforest",
    SAVANNA: "Savanna", PLATEAU: "High Plateau", OASIS: "Oasis",
    ISLAND: "Island", SWAMP: "Swamp", TROPICAL: "Tropical", ARCTIC: "Arctic"'''
}


# === SETTINGS ===
class GameSettings:
    blend_strength = 0.7
    blend_width = 8

settings = GameSettings()

# Add this somewhere (e.g. in config1.py or a new minimap.py)
BIOME_COLORS = {
    # Water / lakes
    LAKE3: (0, 30, 80),     # deep ocean
    LAKE2: (0, 60, 120),
    LAKE: (0, 90, 160),
    BEACH: (200, 180, 120), # sand
    BEACH2: (210, 190, 130),
    BEACH3: (230, 210, 150),

    # Grass / forests
    GRASS: (40, 140, 40),
    GRASS2: (60, 180, 60),
    GRASS3: (80, 200, 80),
    GRASS4: (100, 220, 100),
    GRASS5: (120, 255, 120),
    FOREST: (20, 100, 20),
    FOREST2: (10, 80, 10),
    FOREST3: (0, 120, 0),
    FOREST4: (0, 140, 0),

    # Dry / desert
    DESERT: (220, 180, 100),
    DESERT2: (240, 200, 120),
    DESERT3: (255, 220, 140),
    BASIN: (140, 80, 40),
    BASIN2: (160, 100, 60),
    BASIN3: (180, 120, 80),

    # Mountains / snow
    MOUNTAIN: (140, 140, 140),
    MOUNTAIN2: (160, 160, 160),
    MOUNTAIN3: (180, 180, 180),
    MOUNTAIN4: (200, 200, 200),
    MOUNTAIN5: (220, 220, 220),
    MOUNTAIN6: (240, 240, 240),
    MOUNTAIN7: (255, 255, 255),
    SNOW: (240, 240, 255),
    SNOW2: (250, 250, 255),
    SNOW3: (255, 255, 255),

    # Fallback
    0: (50, 50, 50),  # unknown / default
}