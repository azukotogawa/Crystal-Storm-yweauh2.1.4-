import json
import os

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets", "tiles", "Cube.png")
OUT_JSON = os.path.join(ROOT, "assets", "tiles", "cube_flat_colors.json")
TILE = 32


def main():
    im = Image.open(SRC).convert("RGBA")
    cols = im.width // TILE
    rows = im.height // TILE
    tiles = []
    for row in range(rows):
        for col in range(cols):
            r = g = b = n = 0
            for y in range(row * TILE, (row + 1) * TILE):
                for x in range(col * TILE, (col + 1) * TILE):
                    pr, pg, pb, pa = im.getpixel((x, y))
                    if pa < 26:
                        continue
                    r += pr
                    g += pg
                    b += pb
                    n += 1
            if n == 0:
                continue
            tiles.append({"col": col, "row": row, "rgb": [round(r / n), round(g / n), round(b / n)]})
    data = {"format": "crystalstorm-flat-atlas-v1", "source": "res://assets/tiles/Cube.png", "tile": TILE, "grid": [cols, rows], "tiles": tiles}
    with open(OUT_JSON, "w") as f:
        json.dump(data, f, indent=1)
    print(len(tiles), "tiles")


if __name__ == "__main__":
    main()
