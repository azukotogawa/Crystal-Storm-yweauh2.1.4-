# world.py — TRUE INFINITE, NO MODULO, FULL 0–39 RANGE
from perlin_noise import PerlinNoise
import bisect, random
from config1 import *

'''class InfiniteNoiseWorld:
    def __init__(self, seed):
        self.seed = seed
        self.biome_scale = 60.0  # 1 biome cycle = 1000 units = ~15.6 tiles

        self.n1 = PerlinNoise(octaves=3, seed=seed)
        self.n2 = PerlinNoise(octaves=6, seed=seed)
        self.n3 = PerlinNoise(octaves=12, seed=seed)
        self.n4 = PerlinNoise(octaves=24, seed=seed)
        self.p1 = PerlinNoise(octaves=3, seed=seed + 1000)
        self.p2 = PerlinNoise(octaves=6, seed=seed + 1000)
        self.p3 = PerlinNoise(octaves=12, seed=seed + 1000)
        self.p4 = PerlinNoise(octaves=24, seed=seed + 1000)

        self.v1 = PerlinNoise(octaves=8, seed=seed + 2000)
        self.v2 = PerlinNoise(octaves=16, seed=seed + 2000)

        # CUMULATIVES (40 values → 41 points)
        self.height_cumul = self._build_cumul(BIOME_WEIGHTS_HEIGHT)
        self.precip_cumul = self._build_cumul(BIOME_WEIGHTS_PRECIP)

        # MIN/MAX
        self.min_noise = -1.875
        self.max_noise = 1.875
        self.noise_range = self.max_noise - self.min_noise
        '''

# world.py — SPIKY NOISE + OPTIMAL WEIGHTS
# world.py — OPTIMAL NOISE: 0–39 RANGE, NATURAL BIOMES
class InfiniteNoiseWorld:
    def __init__(self, seed):
        self.seed = seed
        self.biome_scale = 850.0

        # Add a unique salt to each noise generator to guarantee different worlds
        salt = seed * 123456789 + 987654321  # large prime multiplier

        # Create completely fresh PerlinNoise objects
        self.n1 = PerlinNoise(octaves=2, seed=seed)
        self.n2 = PerlinNoise(octaves=5, seed=seed + salt)
        self.n3 = PerlinNoise(octaves=12, seed=seed + salt * 2)
        self.n4 = PerlinNoise(octaves=24, seed=seed + salt * 3)

        self.p1 = PerlinNoise(octaves=2, seed=seed + 1000)
        self.p2 = PerlinNoise(octaves=5, seed=seed + 1000 + salt)
        self.p3 = PerlinNoise(octaves=12, seed=seed + 1000 + salt * 2)
        self.p4 = PerlinNoise(octaves=24, seed=seed + 1000 + salt * 3)

        self.height_cumul = self._build_cumul(BIOME_WEIGHTS_HEIGHT)
        self.precip_cumul = self._build_cumul(BIOME_WEIGHTS_PRECIP)

        print(f"[World] Created fresh world with seed {seed} (salt applied)")

    def _build_cumul(self, weights):
        total = sum(weights)
        cumul = [0.0]
        for w in weights: cumul.append(cumul[-1] + w / total)
        return cumul

    def _generate_noise(self, wx, wy, n1, n2, n3, n4):
        x = float(wx) / self.biome_scale
        y = float(wy) / self.biome_scale
        val = n1([x, y])
        val += 0.5 * n2([x, y])
        val += 0.25 * n3([x, y])
        val += 0.125 * n4([x, y])

        #AMPLIFY EXTREMES
        val *= 1.6

        # CLAMP
        val = max(-1.0, min(1.0, val))

        return val

    def get_height(self, wx, wy):
        return self._generate_noise(wx, wy, self.n1, self.n2, self.n3, self.n4)

    def get_precip(self, wx, wy):
        return self._generate_noise(wx, wy, self.p1, self.p2, self.p3, self.p4)

    def get_biome(self, wx, wy):
        h_val = self.get_height(wx, wy)
        p_val = self.get_precip(wx, wy)

        h_norm = (h_val + 1.0) / 2.0
        p_norm = (p_val + 1.0) / 2.0

        h_level = bisect.bisect_left(self.height_cumul, h_norm)
        p_level = bisect.bisect_left(self.precip_cumul, p_norm)
        h_level = max(0, min(39, h_level))
        p_level = max(0, min(39, p_level))

        # === YOUR LOGIC: USE h_level AND p_level ===
        '''if h_level > 28 and p_level < 10:
                return VOLCANO_MAP[int(variation*len(VOLCANO_MAP))], "Volcano", (h_level, p_level)
        if h_level > 25 and p_level < 5:
                return GLACIER_MAP[int(variation*len(GLACIER_MAP))], "Glacier", (h_level, p_level)
        if h_level < 6 and p_level > 25:
                return CORAL_MAP[int(variation*len(CORAL_MAP))], "Coral", (h_level, p_level)
        if p_level > 30 and h_level < 8:
                return MANGROVE_MAP[int(variation*len(MANGROVE_MAP))], "Mangrove", (h_level, p_level)
        if h_level > 15 and h_level < 25:
            if p_level < 15:
                return CANYON_MAP[int(variation*len(CANYON_MAP))], "Canyon", (h_level, p_level)
        if h_level > 20 and h_level < 30:
            if p_level < 5:
                return FLOATING_MAP[int(variation*len(FLOATING_MAP))], "Floating", (h_level, p_level)
        if p_level < 10 and h_level < 15:
                return DUNES_MAP[int(variation*len(DUNES_MAP))], "Dunes", (h_level, p_level)
        if p_level > 35:
            return JUNGLE_MAP[int(variation*len(JUNGLE_MAP))], "Jungle", (h_level, p_level)
        if p_level > 30 and h_level > 25:
                return TROPICAL_MAP[int(variation*len(TROPICAL_MAP))], "Tropical", (h_level, p_level)
        if p_level < 5 and h_level > 20:
                return ARCTIC_MAP[int(variation*len(ARCTIC_MAP))], "Arctic", (h_level, p_level)'''
        if h_level >= 20:
            return HIGH_MAP[h_level - 20], "High", (h_level, p_level)
        if p_level >= 20:
            return LAKE_MAP[p_level - 20], "Lake", (h_level, p_level)
        else:
            return DRY_MAP[h_level], "Dry", (h_level, p_level)

    def get_variation(self, wx, wy):
        """3rd noise: 0.0 → 1.0 for variation"""
        x = float(wx) / (self.biome_scale / 4)  # 4x faster = fine detail
        y = float(wy) / (self.biome_scale / 4)
        val = self.v1([x, y])
        val += 0.5 * self.v2([x, y])
        val = (val + 1.5) / 3.0  # → 0.0 → 1.0
        return val

    def get_continent_mask(self, wx, wy):
        x = wx / self.cluster_scale
        y = wy / self.cluster_scale
        return (self.continent([x, y]) + 1) / 2  # 0.0 → 1.0

    def get_biome2(self, wx, wy):
        continent = self.get_continent_mask(wx, wy)

        h_raw = self.get_height(wx, wy)  # -1.0 → +1.0
        p_raw = self.get_precip(wx, wy)
        h = (h_raw + 1) / 2  # 0.0 → 1.0
        p = (p_raw + 1) / 2

        h_level = bisect.bisect_left(self.height_cumul, h) - 1
        p_level = bisect.bisect_left(self.precip_cumul, p) - 1
        h_level = max(0, min(39, h_level))
        p_level = max(0, min(39, p_level))

        # === CONTINENT MASK ===
        # if continent < 0.35:
        # if h_level <  LAKE3  # Ocean
        absP = abs(p_level)
        absH = abs(h_level)
        if 1.0 > continent > 0.0:
            if h_level == 0 and p_level == 0:
                return LAKE_MAP[min(abs(h_level), 23)], "Lake", (h_level, p_level)
            if -28 > h_level or h_level > 28:
                if -10 < p_level or p_level < 10:
                    return VOLCANO_MAP[min(abs(absH - 29), len(VOLCANO_MAP) - 1)], "Volcano", (h_level, p_level)
            if -25 > h_level or h_level > 25:
                if -5 < p_level or p_level < 5:
                    return GLACIER_MAP[min(abs(absH - 26), len(GLACIER_MAP) - 1)], "Glacier", (h_level, p_level)
            if -6 < h_level or h_level < 6:
                if -25 > p_level or p_level > 25:
                    return CORAL_MAP[min(abs(absP - 26), len(CORAL_MAP) - 1)], "Coral", (h_level, p_level)
            if -30 > p_level or p_level > 30:
                if -8 < h_level or h_level < 8:
                    return MANGROVE_MAP[min(abs(h_level), len(MANGROVE_MAP) - 1)], "Mangrove", (h_level, p_level)
            if -15 > h_level or h_level > 15:
                if -25 < h_level or h_level < 25 and -15 < p_level or p_level < 15:
                    return CANYON_MAP[min(abs(p_level), len(CANYON_MAP) - 1)], "Canyon", (h_level, p_level)
            if -20 > h_level or h_level > 20:
                if -30 < h_level or h_level < 30 and -5 < p_level or p_level < 5:
                    return FLOATING_MAP[min(abs(absH -  21), len(FLOATING_MAP) - 1)], "Floating", (h_level, p_level)
            if -10 < p_level or p_level < 10:
                if -15 < h_level or h_level < 15:
                    return DUNES_MAP[min(abs(h_level), len(DUNES_MAP) - 1)], "Dunes", (h_level, p_level)
            if -35 > p_level or p_level > 35:
                return JUNGLE_MAP[min(abs(absP - 36), len(JUNGLE_MAP) - 1)], "Jungle", (h_level, p_level)
            if -30 > p_level or p_level > 30:
                if -25 > h_level or h_level > 25:
                    return TROPICAL_MAP[min(abs(absP - 31), len(TROPICAL_MAP) - 1)], "Tropical", (h_level, p_level)
            if -5 < p_level or p_level < 5:
                if -20 > h_level or h_level > 20:
                    return ARCTIC_MAP[min(abs(absH - 21), len(ARCTIC_MAP) - 1)], "Arctic", (h_level, p_level)
            if -24 >= h_level or h_level >= 24:
                return HIGH_MAP[abs(absH - 24)], "High", (h_level, p_level)
            elif -20 >= p_level or p_level >= 20:
                return LAKE_MAP[min(abs(h_level), 23)], "Lake", (h_level, p_level)
            else:
                return DRY_MAP[min(abs(h_level), 23)], "Dry", (h_level, p_level)
