#!/usr/bin/env python3
"""Author assets/tiles/Cube.png as 4px voxel bricks, scout-style outlines.

Grid stays 7x10 x 32. Voxel IDs and ATLAS_COORDS are not remapped.
Also writes assets/tiles/water_surface.png for the channel fill overlay.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "tiles" / "Cube.png"
WATER = ROOT / "assets" / "tiles" / "water_surface.png"
COLS, ROWS, TW = 7, 10, 32


def clamp(c: int) -> int:
    return max(0, min(255, c))


def shade(rgb: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(clamp(int(c * t)) for c in rgb)


def paint_brick(img: Image.Image, x: int, y: int, fill: tuple[int, int, int]) -> None:
    outline = shade(fill, 0.45)
    edge = shade(fill, 0.78)
    for py in range(4):
        for px in range(4):
            c = fill
            if px == 0 or py == 0:
                c = outline
            elif px == 3 or py == 3:
                c = edge
            img.putpixel((x + px, y + py), c + (255,))


def paint_tile(img: Image.Image, col: int, row: int, a: tuple[int, int, int], b: tuple[int, int, int] | None = None) -> None:
    ox, oy = col * TW, row * TW
    alt = b if b is not None else a
    for gy in range(8):
        for gx in range(8):
            use = alt if (gx + gy) % 5 == 0 else a
            paint_brick(img, ox + gx * 4, oy + gy * 4, use)


def fill_river_tile(img: Image.Image, col: int, row: int) -> None:
    paint_tile(img, col, row, (64, 156, 196), (96, 188, 214))


def fill_marsh_grass(img: Image.Image, col: int, row: int) -> None:
    paint_tile(img, col, row, (42, 78, 36), (58, 96, 40))


def fill_sparse_grass(img: Image.Image, col: int, row: int, dry: tuple[int, int, int], tuft: tuple[int, int, int]) -> None:
    paint_tile(img, col, row, dry, tuft)


def fill_ocean(img: Image.Image, col: int, row: int, deep: bool) -> None:
    if deep:
        paint_tile(img, col, row, (16, 42, 84), (22, 58, 108))
    else:
        paint_tile(img, col, row, (28, 78, 138), (40, 102, 168))


def main() -> None:
    img = Image.new("RGBA", (COLS * TW, ROWS * TW), (0, 0, 0, 255))

    # Row 0 — water. (1,0) is the river / WATER slot and must read lighter than ocean (0,0).
    fill_ocean(img, 0, 0, True)
    fill_river_tile(img, 1, 0)
    for c in range(2, COLS):
        fill_ocean(img, c, 0, c >= 5)

    # Row 1 — beach, with the live steppe / farmland / path slots kept distinct.
    sands = [
        (214, 190, 128),
        (196, 170, 112),
        (224, 202, 142),
        (78, 70, 34),  # (3,1) GRASSLAND4 steppe — darker than plains
        (186, 154, 64),  # (4,1) FARMLAND
        (132, 118, 96),  # (5,1) TOWN_PATH
        (208, 184, 122),
    ]
    for c, base in enumerate(sands):
        if c == 3:
            fill_sparse_grass(img, c, 1, base, (148, 132, 58))
        else:
            paint_tile(img, c, 1, base, shade(base, 0.86))

    # Row 2 — grass. (0,2) marsh must stay darker than plains (2,2). (3,2) is DIRT.
    fill_marsh_grass(img, 0, 2)
    paint_tile(img, 1, 2, (72, 132, 48), (88, 150, 56))
    paint_tile(img, 2, 2, (96, 168, 62), (118, 186, 74))  # plains
    paint_tile(img, 3, 2, (118, 84, 52), (96, 68, 40))  # dirt
    fill_sparse_grass(img, 4, 2, (214, 168, 64), (186, 140, 48))  # savanna, lighter than steppe
    paint_tile(img, 5, 2, (78, 156, 52), (96, 176, 64))  # grass tuft
    paint_tile(img, 6, 2, (146, 84, 196), (176, 120, 220))  # crystal

    # Row 3 — forest / trunk / bush
    paint_tile(img, 0, 3, (46, 92, 40), (36, 74, 32))
    paint_tile(img, 1, 3, (40, 84, 36), (52, 102, 44))
    paint_tile(img, 2, 3, (102, 72, 44), (78, 54, 32))  # trunk
    paint_tile(img, 3, 3, (54, 108, 46), (42, 86, 36))
    paint_tile(img, 4, 3, (36, 78, 32), (48, 96, 40))
    paint_tile(img, 5, 3, (48, 110, 42), (32, 82, 28))  # bush
    paint_tile(img, 6, 3, (44, 88, 38), (58, 104, 46))

    # Row 4 — stone. (0,4) needs visible cracks, not one flat gray.
    stones = [
        (112, 112, 116),
        (96, 98, 102),
        (128, 126, 122),
        (84, 86, 90),
        (104, 100, 96),
        (120, 118, 114),
        (90, 94, 98),
    ]
    for c, base in enumerate(stones):
        paint_tile(img, c, 4, base, shade(base, 0.62))

    # Row 5 — snow, plus the mountain3 slot at (3,5)
    snows = [
        (232, 238, 244),
        (214, 222, 230),
        (240, 244, 248),
        (100, 104, 108),
        (220, 226, 232),
        (206, 214, 222),
        (228, 234, 240),
    ]
    for c, base in enumerate(snows):
        paint_tile(img, c, 5, base, shade(base, 0.9))

    # Row 6 — valley / dirt2
    valleys = [(108, 82, 54), (96, 72, 46), (120, 92, 62), (88, 66, 42), (114, 86, 58), (100, 76, 50), (92, 70, 44)]
    for c, base in enumerate(valleys):
        paint_tile(img, c, 6, base, shade(base, 0.8))

    # Row 7 — desert
    deserts = [(198, 164, 98), (184, 148, 86), (210, 176, 112), (176, 142, 78), (204, 168, 102), (190, 156, 92), (168, 136, 74)]
    for c, base in enumerate(deserts):
        paint_tile(img, c, 7, base, shade(base, 0.84))

    # Row 8 — tundra
    tundras = [(168, 176, 184), (154, 162, 170), (180, 186, 192), (148, 156, 164), (172, 178, 186), (160, 168, 176), (140, 148, 156)]
    for c, base in enumerate(tundras):
        paint_tile(img, c, 8, base, shade(base, 0.86))

    # Row 9 — basin
    basins = [(142, 126, 106), (128, 114, 96), (154, 138, 116), (118, 106, 90), (136, 122, 104), (148, 132, 112), (124, 110, 94)]
    for c, base in enumerate(basins):
        paint_tile(img, c, 9, base, shade(base, 0.82))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"Wrote {OUT} ({img.size[0]}x{img.size[1]})")

    water = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    paint_tile(water, 0, 0, (48, 140, 186), (88, 186, 214))
    water.save(WATER)
    print(f"Wrote {WATER}")


if __name__ == "__main__":
    main()
