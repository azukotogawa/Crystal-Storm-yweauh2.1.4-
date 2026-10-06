#!/usr/bin/env python3
"""Scout-style 4px voxel art for entities, plants, items, combat, and crystal.

Writes PNGs under assets/art/. The texture generator loads these at play time.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets" / "art"

SKIN = (219, 158, 107)
HAIR = (71, 41, 26)
TUNIC = (56, 107, 87)
BOOT = (51, 36, 26)
WOOD = (133, 87, 46)
WOOD_DK = (92, 58, 32)
STONE = (168, 168, 172)
STONE_DK = (96, 98, 104)
LEAF = (78, 156, 58)
LEAF_DK = (42, 96, 38)
PURPLE = (168, 92, 214)
PURPLE_DK = (96, 42, 140)
GOLD = (232, 196, 84)
WHITE = (236, 232, 224)
EYE = (20, 18, 16)


def new(size: int) -> Image.Image:
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def brick(img: Image.Image, x: int, y: int, rgb: tuple[int, int, int], n: int = 4) -> None:
    outline = tuple(max(0, int(c * 0.38)) for c in rgb)
    edge = tuple(max(0, int(c * 0.74)) for c in rgb)
    w, h = img.size
    for py in range(n):
        for px in range(n):
            xx, yy = x + px, y + py
            if xx < 0 or yy < 0 or xx >= w or yy >= h:
                continue
            c = rgb
            if px == 0 or py == 0:
                c = outline
            elif px == n - 1 or py == n - 1:
                c = edge
            img.putpixel((xx, yy), c + (255,))


def stamp(img: Image.Image, cells: list[tuple[int, int, tuple[int, int, int]]], ox: int = 0, oy: int = 0) -> None:
    for gx, gy, rgb in cells:
        brick(img, ox + gx * 4, oy + gy * 4, rgb)


def save(img: Image.Image, folder: str, name: str) -> None:
    path = ART / folder
    path.mkdir(parents=True, exist_ok=True)
    img.save(path / f"{name}.png")


def figure(cells: list[tuple[int, int, tuple[int, int, int]]], size: int = 48) -> Image.Image:
    img = new(size)
    # Center a figure whose coords are in a 12-wide mental grid.
    span = size // 4
    xs = [c[0] for c in cells]
    ys = [c[1] for c in cells]
    ox = max(0, (span - (max(xs) - min(xs) + 1)) // 2 - min(xs))
    oy = max(0, (span - (max(ys) - min(ys) + 1)) // 2 - min(ys))
    stamp(img, cells, ox * 4, oy * 4)
    return img


def entities() -> None:
    brown = (150, 96, 58)
    tan = (196, 156, 108)
    deer = (168, 118, 72)
    boar = (92, 58, 42)
    bird = (72, 124, 168)
    militia_helm = (120, 124, 132)
    specs = {
        "rabbit": [
            (2, 0, brown), (3, 0, brown),
            (2, 1, tan), (3, 1, SKIN),
            (1, 2, brown), (2, 2, tan), (3, 2, tan), (4, 2, brown),
            (2, 3, brown), (3, 3, brown),
            (1, 4, BOOT), (4, 4, BOOT),
        ],
        "deer": [
            (2, 0, WOOD_DK), (4, 0, WOOD_DK),
            (2, 1, deer), (3, 1, deer), (4, 1, deer),
            (3, 2, tan),
            (1, 3, deer), (2, 3, deer), (3, 3, deer), (4, 3, deer), (5, 3, deer),
            (2, 4, BOOT), (4, 4, BOOT),
        ],
        "boar": [
            (1, 2, boar), (2, 2, boar), (3, 2, tan), (4, 2, boar),
            (0, 3, WHITE), (1, 3, boar), (2, 3, boar), (3, 3, boar), (4, 3, boar), (5, 3, boar),
            (1, 4, BOOT), (4, 4, BOOT),
        ],
        "bird": [
            (2, 1, bird), (3, 1, GOLD),
            (1, 2, bird), (2, 2, bird), (3, 2, WHITE), (4, 2, bird),
            (2, 3, WOOD), (3, 3, WOOD),
        ],
        "town_militia": [
            (2, 0, militia_helm), (3, 0, militia_helm),
            (2, 1, SKIN), (3, 1, SKIN),
            (1, 2, STONE), (2, 2, TUNIC), (3, 2, TUNIC), (4, 2, STONE),
            (2, 3, TUNIC), (3, 3, WOOD),
            (2, 4, BOOT), (3, 4, BOOT),
        ],
        "crystal_mite": [
            (2, 0, PURPLE),
            (1, 1, PURPLE), (2, 1, WHITE), (3, 1, PURPLE),
            (1, 2, PURPLE_DK), (2, 2, PURPLE), (3, 2, PURPLE_DK),
            (2, 3, PURPLE_DK),
        ],
        "farm_bomber": [
            (2, 0, LEAF), (3, 0, LEAF_DK),
            (1, 1, WOOD), (2, 1, LEAF), (3, 1, LEAF), (4, 1, WOOD),
            (2, 2, SKIN), (3, 2, SKIN),
            (2, 3, BOOT), (3, 3, BOOT),
        ],
        "crystal_stag": [
            (1, 0, PURPLE), (4, 0, PURPLE),
            (2, 1, deer), (3, 1, PURPLE), (4, 1, deer),
            (1, 2, deer), (2, 2, deer), (3, 2, deer), (4, 2, deer), (5, 2, deer),
            (2, 3, BOOT), (4, 3, BOOT),
        ],
        "thornling": [
            (1, 0, LEAF_DK), (3, 0, LEAF_DK),
            (2, 1, LEAF), (3, 1, LEAF),
            (1, 2, LEAF), (2, 2, LEAF_DK), (3, 2, LEAF), (4, 2, LEAF),
            (2, 3, WOOD_DK), (3, 3, WOOD_DK),
        ],
        "corrupted_beast": [
            (1, 1, PURPLE_DK), (2, 1, PURPLE), (3, 1, EYE), (4, 1, PURPLE_DK),
            (0, 2, PURPLE_DK), (1, 2, PURPLE), (2, 2, PURPLE_DK), (3, 2, PURPLE), (4, 2, PURPLE_DK), (5, 2, PURPLE),
            (1, 3, BOOT), (4, 3, BOOT),
        ],
        "shard_guard": [
            (2, 0, PURPLE), (3, 0, WHITE),
            (1, 1, PURPLE_DK), (2, 1, PURPLE), (3, 1, PURPLE), (4, 1, PURPLE_DK),
            (2, 2, STONE), (3, 2, PURPLE),
            (2, 3, STONE_DK), (3, 3, STONE_DK),
        ],
    }
    for name, cells in specs.items():
        save(figure(cells, 48), "entity", name)


def plant(stage_cells: list[list[tuple[int, int, tuple[int, int, int]]]]) -> None:
    return


def vegetation() -> None:
    flower = (214, 92, 120)
    specs = {
        "grass_tuft_s0": [(1, 2, LEAF_DK), (2, 2, LEAF)],
        "grass_tuft_s1": [(0, 1, LEAF), (1, 2, LEAF_DK), (2, 1, LEAF), (2, 2, LEAF_DK)],
        "tall_grass_s0": [(1, 1, LEAF), (1, 2, LEAF_DK), (2, 2, LEAF)],
        "tall_grass_s1": [(1, 0, LEAF), (1, 1, LEAF_DK), (2, 1, LEAF), (2, 2, LEAF_DK), (0, 2, LEAF)],
        "wildflower_s0": [(1, 1, flower), (1, 2, LEAF_DK)],
        "wildflower_s1": [(1, 0, flower), (0, 1, flower), (1, 1, GOLD), (2, 1, flower), (1, 2, LEAF)],
        "fern_s0": [(1, 2, LEAF_DK), (2, 1, LEAF), (2, 2, LEAF)],
        "fern_s1": [(0, 1, LEAF), (1, 2, LEAF_DK), (2, 0, LEAF), (2, 1, LEAF), (2, 2, LEAF_DK), (3, 1, LEAF)],
        "bush_s0": [(1, 2, LEAF_DK), (2, 2, LEAF)],
        "bush_s1": [(1, 1, LEAF), (2, 1, LEAF_DK), (0, 2, LEAF), (1, 2, LEAF_DK), (2, 2, LEAF), (3, 2, LEAF_DK)],
        "bush_s2": [(1, 0, LEAF), (2, 0, flower), (0, 1, LEAF_DK), (1, 1, LEAF), (2, 1, LEAF), (3, 1, LEAF_DK),
                    (1, 2, WOOD_DK), (2, 2, WOOD_DK)],
        "tree_s0": [(1, 2, LEAF), (1, 3, WOOD)],
        "tree_s1": [(1, 0, LEAF), (0, 1, LEAF_DK), (1, 1, LEAF), (2, 1, LEAF_DK), (1, 2, WOOD), (1, 3, WOOD_DK)],
        "tree_s2": [(1, 0, LEAF), (2, 0, LEAF_DK), (0, 1, LEAF), (1, 1, LEAF_DK), (2, 1, LEAF), (3, 1, LEAF),
                    (1, 2, LEAF_DK), (2, 2, LEAF), (1, 3, WOOD), (2, 3, WOOD), (1, 4, WOOD_DK), (2, 4, WOOD_DK)],
    }
    for name, cells in specs.items():
        save(figure(cells, 40), "vegetation", name)


def items() -> None:
    specs = {
        "wooden_sword": [
            (5, 1, WHITE), (5, 2, WHITE), (4, 3, WHITE),
            (3, 4, WOOD), (2, 5, WOOD_DK), (1, 6, WOOD),
        ],
        "stone_pick": [
            (1, 1, STONE), (2, 1, STONE_DK), (3, 1, STONE),
            (4, 2, STONE), (3, 3, WOOD), (2, 4, WOOD), (1, 5, WOOD_DK),
        ],
        "shortbow": [
            (2, 1, WOOD), (1, 2, WOOD_DK), (1, 3, WOOD), (1, 4, WOOD_DK), (2, 5, WOOD),
            (3, 2, WHITE), (3, 3, WHITE), (3, 4, WHITE),
        ],
        "wood": [
            (2, 2, WOOD), (3, 2, WOOD_DK), (4, 2, WOOD),
            (2, 3, WOOD_DK), (3, 3, WOOD), (4, 3, WOOD_DK),
            (2, 4, WOOD), (3, 4, WOOD_DK), (4, 4, WOOD),
        ],
        "stone": [
            (2, 2, STONE), (3, 2, STONE_DK), (4, 2, STONE),
            (2, 3, STONE_DK), (3, 3, WHITE), (4, 3, STONE),
            (2, 4, STONE), (3, 4, STONE_DK), (4, 4, STONE),
        ],
        "herb": [
            (3, 1, LEAF), (2, 2, LEAF_DK), (4, 2, LEAF),
            (3, 3, LEAF), (3, 4, WOOD), (3, 5, WOOD_DK),
        ],
    }
    for name, cells in specs.items():
        save(figure(cells, 32), "items", name)


def particles() -> None:
    save(figure([(1, 1, GOLD), (2, 1, WHITE), (1, 2, WHITE), (2, 2, GOLD)], 32), "particle", "damage_number")
    save(figure([(1, 0, GOLD), (0, 1, WHITE), (1, 1, GOLD), (2, 1, WHITE), (1, 2, GOLD)], 16), "particle", "hit_flash")
    save(figure([
        (1, 1, PURPLE), (3, 0, WHITE), (4, 2, PURPLE_DK), (2, 3, PURPLE), (0, 4, STONE),
    ], 24), "particle", "shatter")
    save(figure([
        (2, 0, PURPLE), (1, 1, PURPLE_DK), (2, 1, WHITE), (3, 1, PURPLE),
        (0, 2, PURPLE), (1, 2, PURPLE), (2, 2, PURPLE_DK), (3, 2, PURPLE), (4, 2, PURPLE),
        (2, 3, GOLD),
    ], 48), "particle", "spawn_boss")
    save(figure([
        (1, 0, PURPLE), (0, 1, PURPLE_DK), (1, 1, WHITE), (2, 1, PURPLE), (1, 2, PURPLE_DK),
    ], 32), "particle", "spawn_miniboss")
    glow = []
    for i, rgb in enumerate([GOLD, WHITE, GOLD, (255, 220, 120), GOLD, WHITE]):
        glow.append((2 + (i % 3), 1 + i // 3, rgb))
    glow += [(1, 3, GOLD), (5, 3, GOLD), (3, 0, WHITE), (3, 5, GOLD)]
    save(figure(glow, 64), "particle", "victory_glow")


def buildings() -> None:
    specs = {
        "wood_wall": [(0, 1, WOOD), (1, 1, WOOD_DK), (2, 1, WOOD), (0, 2, WOOD_DK), (1, 2, WOOD), (2, 2, WOOD_DK),
                      (0, 3, WOOD), (1, 3, WOOD_DK), (2, 3, WOOD)],
        "stone_wall": [(0, 1, STONE), (1, 1, STONE_DK), (2, 1, STONE), (0, 2, STONE_DK), (1, 2, STONE), (2, 2, STONE_DK),
                       (0, 3, STONE), (1, 3, STONE_DK), (2, 3, STONE)],
        "town_hall": [(1, 0, WOOD_DK), (2, 0, WOOD), (0, 1, STONE), (1, 1, TUNIC), (2, 1, GOLD), (3, 1, STONE),
                      (0, 2, STONE_DK), (1, 2, STONE), (2, 2, STONE), (3, 2, STONE_DK)],
        "ruin_pillar": [(1, 0, STONE), (1, 1, STONE_DK), (1, 2, STONE), (1, 3, STONE_DK), (0, 4, STONE), (1, 4, STONE), (2, 4, STONE)],
        "gate": [(0, 1, WOOD), (3, 1, WOOD), (0, 2, WOOD_DK), (1, 2, WOOD), (2, 2, WOOD), (3, 2, WOOD_DK),
                 (0, 3, WOOD), (3, 3, WOOD)],
        "bridge": [(0, 2, WOOD), (1, 2, WOOD_DK), (2, 2, WOOD), (3, 2, WOOD_DK), (4, 2, WOOD),
                   (0, 3, WOOD_DK), (4, 3, WOOD_DK)],
    }
    for name, cells in specs.items():
        save(figure(cells, 48), "building", name)


def surfaces() -> None:
    brick_img = new(16)
    brick(brick_img, 0, 0, (214, 208, 198))
    brick(brick_img, 4, 0, (186, 180, 170))
    brick(brick_img, 0, 4, (176, 170, 160))
    brick(brick_img, 4, 4, (200, 194, 184))
    brick(brick_img, 8, 0, (168, 162, 154))
    brick(brick_img, 12, 0, (210, 204, 194))
    brick(brick_img, 8, 4, (190, 184, 174))
    brick(brick_img, 12, 4, (160, 154, 146))
    brick(brick_img, 0, 8, (204, 198, 188))
    brick(brick_img, 4, 8, (172, 166, 156))
    brick(brick_img, 8, 8, (196, 190, 180))
    brick(brick_img, 12, 8, (180, 174, 164))
    brick(brick_img, 0, 12, (188, 182, 172))
    brick(brick_img, 4, 12, (208, 202, 192))
    brick(brick_img, 8, 12, (164, 158, 150))
    brick(brick_img, 12, 12, (198, 192, 182))
    ART.mkdir(parents=True, exist_ok=True)
    brick_img.save(ART / "voxel_brick.png")

    facet = new(32)
    cols = [PURPLE, PURPLE_DK, (210, 160, 240), WHITE, PURPLE, PURPLE_DK, (186, 120, 220), PURPLE]
    for gy in range(8):
        for gx in range(8):
            brick(facet, gx * 4, gy * 4, cols[(gx + gy * 3) % len(cols)])
    save(facet, "crystal", "facet")


def main() -> None:
    entities()
    vegetation()
    items()
    particles()
    buildings()
    surfaces()
    print(f"Wrote scout art under {ART}")


if __name__ == "__main__":
    main()
