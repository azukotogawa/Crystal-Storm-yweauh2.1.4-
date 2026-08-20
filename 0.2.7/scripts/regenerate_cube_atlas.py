#!/usr/bin/env python3
"""Regenerate assets/tiles/Cube.png — Minecraft-style 7x10 atlas with subtle pixel variation."""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "tiles" / "Cube.png"
COLS, ROWS, TW = 7, 10, 32
RNG = random.Random(0xC17A)


def clamp(c: int) -> int:
    return max(0, min(255, c))


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(clamp(int(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def fill_tile(img: Image.Image, col: int, row: int, base: tuple[int, int, int], accents: list[tuple[int, int, int]], density: float = 0.08) -> None:
    ox, oy = col * TW, row * TW
    for py in range(TW):
        for px in range(TW):
            img.putpixel((ox + px, oy + py), base)
    speckles = max(1, int(TW * TW * density))
    for _ in range(speckles):
        px = RNG.randrange(TW)
        py = RNG.randrange(TW)
        accent = accents[RNG.randrange(len(accents))]
        img.putpixel((ox + px, oy + py), accent)


def fill_grass_top(img: Image.Image, col: int, row: int, base: tuple[int, int, int], dark: tuple[int, int, int], light: tuple[int, int, int]) -> None:
    """Grass block top — short blade strokes, not random noise."""
    ox, oy = col * TW, row * TW
    for py in range(TW):
        for px in range(TW):
            img.putpixel((ox + px, oy + py), base)
    for _ in range(22):
        px = RNG.randrange(2, TW - 2)
        py = RNG.randrange(2, TW - 2)
        blade_h = RNG.randrange(2, 5)
        col_c = dark if RNG.random() < 0.55 else light
        for dy in range(blade_h):
            y = py - dy
            if 0 <= y < TW:
                img.putpixel((ox + px, oy + y), col_c)
                if px + 1 < TW and RNG.random() < 0.35:
                    img.putpixel((ox + px + 1, oy + y), blend(col_c, base, 0.4))


def fill_stone_tile(img: Image.Image, col: int, row: int, base: tuple[int, int, int]) -> None:
    """Stone — cracked plates with mortar gaps."""
    ox, oy = col * TW, row * TW
    mortar = blend(base, (40, 40, 40), 0.35)
    for py in range(TW):
        for px in range(TW):
            img.putpixel((ox + px, oy + py), base)
    for gy in range(0, TW, 8):
        for gx in range(0, TW):
            img.putpixel((ox + gx, oy + gy), mortar)
    for gx in range(0, TW, 10):
        for gy in range(0, TW):
            img.putpixel((ox + gx, oy + gy), mortar)
    for _ in range(14):
        x0 = RNG.randrange(1, TW - 4)
        y0 = RNG.randrange(1, TW - 4)
        crack_c = blend(base, (30, 30, 30), 0.5)
        for _s in range(RNG.randrange(3, 8)):
            img.putpixel((ox + x0, oy + y0), crack_c)
            x0 += RNG.choice([-1, 0, 1])
            y0 += RNG.choice([-1, 0, 1])


def fill_dirt_tile(img: Image.Image, col: int, row: int, base: tuple[int, int, int]) -> None:
    """Dirt — horizontal strata bands."""
    ox, oy = col * TW, row * TW
    for py in range(TW):
        band_t = (py % 6) / 6.0
        row_c = blend(base, (base[0] - 18, base[1] - 14, base[2] - 10), band_t * 0.45)
        for px in range(TW):
            img.putpixel((ox + px, oy + py), row_c)
    for _ in range(10):
        px = RNG.randrange(TW)
        py = RNG.randrange(TW)
        img.putpixel((ox + px, oy + py), blend(base, (90, 60, 38), 0.35))


def fill_grass_side(img: Image.Image, col: int, row: int, dirt: tuple[int, int, int], grass: tuple[int, int, int]) -> None:
    ox, oy = col * TW, row * TW
    for py in range(TW):
        for px in range(TW):
            c = grass if py < 4 else dirt
            img.putpixel((ox + px, oy + py), c)
    for px in range(TW):
        if RNG.random() < 0.15:
            img.putpixel((ox + px, oy + 3), blend(grass, dirt, 0.5))


def fill_ocean(img: Image.Image, col: int, row: int, shallow: bool = False) -> None:
    base = (38, 84, 138) if shallow else (18, 44, 92)
    accents = [(28, 68, 118), (48, 98, 158)] if shallow else [(12, 32, 72), (32, 58, 108)]
    fill_tile(img, col, row, base, accents, 0.05)


def main() -> None:
    img = Image.new("RGBA", (COLS * TW, ROWS * TW), (0, 0, 0, 255))

    # Row 0 — water
    for c in range(COLS):
        fill_ocean(img, c, 0, shallow=c > 0)

    # Row 1 — beach
    sands = [
        (218, 198, 140),
        (210, 186, 128),
        (226, 206, 150),
        (204, 180, 122),
        (232, 214, 158),
        (196, 172, 116),
        (214, 192, 134),
    ]
    for c, base in enumerate(sands):
        fill_tile(img, c, 1, base, [(base[0] - 18, base[1] - 16, base[2] - 10), (base[0] + 12, base[1] + 10, base[2] + 8)], 0.07)

    # Row 2 — grass biomes + dirt column
    grasses = [
        (88, 142, 48),
        (96, 150, 54),
        (104, 158, 60),
        (140, 154, 72),
        (168, 146, 64),
        (72, 128, 44),
        (118, 168, 78),
    ]
    for c, base in enumerate(grasses):
        dark = (base[0] - 16, base[1] - 20, base[2] - 10)
        light = (base[0] + 12, base[1] + 14, base[2] + 8)
        fill_grass_top(img, c, 2, base, dark, light)
    fill_grass_side(img, 3, 2, (118, 86, 52), grasses[3])

    # Row 3 — forest
    forest = [(52, 102, 44), (44, 92, 38), (60, 112, 50), (72, 118, 56), (40, 84, 34)]
    for c, base in enumerate(forest):
        fill_tile(img, c, 3, base, [(base[0] - 10, base[1] - 14, base[2] - 6), (base[0] + 8, base[1] + 10, base[2] + 4)], 0.08)
    fill_tile(img, 2, 3, (92, 68, 44), [(78, 56, 34), (104, 78, 52)], 0.06)

    # Row 4 — stone / mountain
    stones = [
        (108, 108, 108),
        (98, 98, 98),
        (118, 118, 118),
        (88, 88, 88),
        (128, 128, 128),
        (102, 102, 102),
        (112, 112, 112),
    ]
    for c, base in enumerate(stones):
        fill_stone_tile(img, c, 4, base)

    # Row 5 — snow
    snows = [(228, 236, 244), (220, 228, 238), (236, 242, 250)]
    for c, base in enumerate(snows):
        fill_tile(img, c, 5, base, [(210, 218, 228), (244, 248, 252)], 0.05)

    # Row 6 — valley / dirt
    dirts = [(108, 82, 54), (98, 74, 48), (118, 90, 60)]
    for c, base in enumerate(dirts):
        fill_dirt_tile(img, c, 6, base)

    # Row 7 — desert
    deserts = [(196, 162, 98), (186, 150, 88), (206, 172, 108)]
    for c, base in enumerate(deserts):
        fill_tile(img, c, 7, base, [(base[0] - 14, base[1] - 12, base[2] - 10), (base[0] + 12, base[1] + 10, base[2] + 8)], 0.07)

    # Row 8 — tundra
    tundras = [(168, 176, 182), (158, 166, 174), (178, 184, 190)]
    for c, base in enumerate(tundras):
        fill_tile(img, c, 8, base, [(150, 158, 166), (188, 194, 200)], 0.06)

    # Row 9 — basin
    basins = [(142, 128, 108), (132, 118, 98), (152, 138, 118)]
    for c, base in enumerate(basins):
        fill_tile(img, c, 9, base, [(base[0] - 12, base[1] - 10, base[2] - 8), (base[0] + 10, base[1] + 8, base[2] + 6)], 0.07)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"Wrote {OUT} ({img.size[0]}x{img.size[1]})")


if __name__ == "__main__":
    main()