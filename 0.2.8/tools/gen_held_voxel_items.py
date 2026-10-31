import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "voxel")
OUT = os.path.join(ROOT, "items")

WOOD = (107, 71, 36)
WOOD_MID = (92, 64, 44)
WOOD_DARK = (64, 44, 32)
WOOD_DEEP = (40, 28, 22)
STONE = (132, 134, 140)
STONE_EDGE = (176, 178, 184)
STONE_DARK = (78, 80, 86)
BLADE = (196, 200, 206)
BLADE_EDGE = (232, 234, 238)
CRYSTAL = (184, 71, 255)
CRYSTAL_CORE = (140, 46, 242)
STRING = (236, 232, 220)


def box(occ, part, x0, y0, z0, x1, y1, z1, mat, hollow=False):
    for y in range(y0, y1, 2):
        for z in range(z0, z1, 2):
            for x in range(x0, x1, 2):
                for dy in (0, 1):
                    for dz in (0, 1):
                        for dx in (0, 1):
                            xx, yy, zz = x + dx, y + dy, z + dz
                            if hollow:
                                shell = xx < x0 + 2 or xx >= x1 - 2 or yy < y0 + 2 or yy >= y1 - 2 or zz < z0 + 2 or zz >= z1 - 2
                                if not shell:
                                    continue
                            occ[(xx, yy, zz)] = (part, mat)


def cells(occ, part, triples, mat):
    for x, y, z in triples:
        occ[(x, y, z)] = (part, mat)


def ridge(occ, part, x, z, y0, y1, mat):
    for y in range(y0, y1):
        occ[(x, y, z)] = (part, mat)


def model(name, size, pivot, occ):
    used = []
    index = {}
    parts = {}
    for (x, y, z), (part, mat) in sorted(occ.items()):
        if mat not in index:
            index[mat] = len(used)
            used.append(mat)
        parts.setdefault(part, []).append([x, y, z, index[mat]])
    return {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": list(size),
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": list(pivot),
        "palette": [list(c) for c in used],
        "parts": parts,
    }


def occupied(occ):
    return set(occ.keys())


def audit(name, occ):
    pts = occupied(occ)
    interior = 0
    detail = 0
    exposed_detail = 0
    for x, y, z in pts:
        n6 = 0
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            if (x + d[0], y + d[1], z + d[2]) in pts:
                n6 += 1
        if n6 == 6:
            interior += 1
        x0, y0, z0 = x - (x % 2), y - (y % 2), z - (z % 2)
        full = True
        for dy in (0, 1):
            for dz in (0, 1):
                for dx in (0, 1):
                    if (x0 + dx, y0 + dy, z0 + dz) not in pts:
                        full = False
        if not full:
            detail += 1
            if n6 < 6:
                exposed_detail += 1
    ys = [p[1] for p in pts]
    span = max(ys) - min(ys) + 1
    buried = []
    for x, y, z in pts:
        n6 = 0
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            if (x + d[0], y + d[1], z + d[2]) in pts:
                n6 += 1
        if n6 == 6:
            buried.append((x, y, z))
    print("%s cells=%d interior=%d detail=%d exposed=%d yspan=%d buried=%s" % (name, len(pts), interior, detail, exposed_detail, span, buried[:12]))
    if interior or exposed_detail != detail:
        raise SystemExit("shell " + name)


def sword():
    occ = {}
    box(occ, "grip", 6, 0, 2, 8, 12, 4, WOOD)
    box(occ, "grip", 6, 0, 2, 8, 2, 4, WOOD_DEEP)
    box(occ, "head", 2, 12, 2, 14, 14, 4, WOOD_DARK)
    cells(occ, "head", [(1, 12, 2), (1, 13, 2), (1, 12, 3), (1, 13, 3), (14, 12, 2), (14, 13, 2), (14, 12, 3), (14, 13, 3)], WOOD_DEEP)
    cells(occ, "head", [(x, y, 1) for x in range(3, 13) if x not in (6, 7) for y in (12, 13)], WOOD_DEEP)
    cells(occ, "head", [(x, y, 4) for x in range(3, 13) if x not in (6, 7) for y in (12, 13)], WOOD_DEEP)
    box(occ, "head", 6, 14, 2, 8, 34, 4, BLADE)
    ridge(occ, "head", 5, 2, 16, 32, BLADE_EDGE)
    ridge(occ, "head", 8, 3, 16, 32, BLADE_EDGE)
    cells(occ, "head", [(6, 34, 2), (7, 34, 2), (6, 34, 3), (7, 34, 3), (6, 35, 2), (7, 35, 2), (6, 36, 2), (7, 36, 3)], BLADE_EDGE)
    return model("wooden_sword", (16, 40, 8), (7, 6, 3), occ), occ


def spear():
    occ = {}
    box(occ, "grip", 4, 0, 2, 6, 36, 4, WOOD)
    box(occ, "grip", 4, 0, 2, 6, 2, 4, WOOD_DEEP)
    box(occ, "head", 2, 34, 2, 8, 38, 4, WOOD_DARK)
    box(occ, "head", 4, 36, 2, 6, 42, 4, STONE)
    cells(occ, "head", [(3, y, 2) for y in range(38, 42)] + [(6, y, 3) for y in range(38, 42)], STONE_EDGE)
    cells(occ, "head", [(4, 42, 2), (5, 42, 2), (4, 42, 3), (5, 42, 3), (4, 43, 2), (5, 43, 3), (5, 44, 2)], STONE_EDGE)
    return model("spear", (12, 48, 8), (5, 10, 3), occ), occ


def pickaxe():
    occ = {}
    box(occ, "grip", 12, 0, 4, 14, 28, 6, WOOD)
    box(occ, "grip", 12, 0, 4, 14, 2, 6, WOOD_DEEP)
    box(occ, "head", 6, 24, 4, 22, 28, 6, STONE)
    cells(occ, "head", [(4, 25, 4), (4, 26, 4), (5, 25, 4), (5, 26, 4), (4, 25, 5), (5, 26, 5), (2, 25, 4), (3, 26, 4)], STONE_EDGE)
    cells(occ, "head", [(22, 25, 4), (22, 26, 5), (23, 25, 4), (23, 26, 4), (24, 25, 5), (24, 26, 4), (25, 26, 4)], STONE_EDGE)
    return model("pickaxe", (28, 32, 8), (13, 8, 5), occ), occ


def axe():
    occ = {}
    box(occ, "grip", 4, 0, 4, 6, 30, 6, WOOD)
    box(occ, "grip", 4, 0, 4, 6, 2, 6, WOOD_DEEP)
    box(occ, "head", 6, 20, 4, 14, 30, 6, STONE)
    cells(occ, "head", [(14, y, 4) for y in range(22, 28)] + [(15, y, 5) for y in range(23, 27)] + [(16, 24, 4), (16, 25, 5)], STONE_EDGE)
    return model("axe", (20, 32, 10), (5, 8, 5), occ), occ


def shovel():
    occ = {}
    box(occ, "grip", 6, 0, 4, 8, 30, 6, WOOD)
    box(occ, "grip", 6, 0, 4, 8, 2, 6, WOOD_DEEP)
    box(occ, "head", 4, 26, 4, 12, 30, 6, WOOD_DARK)
    box(occ, "head", 2, 30, 4, 14, 38, 6, STONE)
    for x in range(2, 14):
        cells(occ, "head", [(x, 38, 4), (x, 38, 5)], STONE_EDGE)
    for y in range(30, 38):
        cells(occ, "head", [(1, y, 4), (14, y, 5)], STONE_EDGE)
    return model("shovel", (16, 40, 10), (7, 10, 5), occ), occ


def shortbow():
    occ = {}
    box(occ, "limb", 2, 16, 2, 4, 24, 4, WOOD_DARK)
    box(occ, "limb", 2, 22, 4, 4, 30, 6, WOOD)
    box(occ, "limb", 2, 28, 6, 4, 36, 8, WOOD)
    box(occ, "limb", 2, 34, 8, 4, 40, 10, WOOD_MID)
    box(occ, "limb", 2, 10, 4, 4, 18, 6, WOOD)
    box(occ, "limb", 2, 4, 6, 4, 12, 8, WOOD)
    box(occ, "limb", 2, 0, 8, 4, 6, 10, WOOD_MID)
    for y in range(4, 36):
        occ[(3, y, 11)] = ("string", STRING)
    cells(occ, "limb", [(2, 39, 9), (3, 39, 9), (2, 0, 9), (3, 0, 9)], WOOD_DEEP)
    return model("shortbow", (8, 42, 14), (3, 20, 3), occ), occ


def sling():
    occ = {}
    box(occ, "limb", 4, 10, 2, 6, 18, 4, WOOD_DARK)
    box(occ, "limb", 4, 16, 4, 6, 26, 6, WOOD)
    box(occ, "limb", 4, 2, 4, 6, 12, 6, WOOD)
    box(occ, "limb", 4, 24, 6, 6, 28, 8, WOOD_MID)
    box(occ, "limb", 4, 0, 6, 6, 4, 8, WOOD_MID)
    for y in range(6, 22):
        occ[(5, y, 8)] = ("string", STRING)
    box(occ, "string", 2, 12, 8, 8, 16, 10, STONE_DARK)
    cells(occ, "string", [(1, 13, 8), (8, 14, 9), (3, 16, 8), (6, 16, 9)], STONE)
    return model("sling", (10, 30, 12), (5, 14, 3), occ), occ


def hammer():
    occ = {}
    box(occ, "grip", 10, 0, 4, 12, 22, 6, WOOD_DEEP)
    box(occ, "grip", 10, 0, 4, 12, 2, 6, WOOD_DARK)
    box(occ, "crystal", 4, 18, 4, 20, 28, 6, CRYSTAL)
    cells(occ, "crystal", [(3, y, 4) for y in range(20, 26)] + [(20, y, 5) for y in range(20, 26)] + [(8, 28, 4), (14, 28, 5)], CRYSTAL_CORE)
    return model("crystal_hammer", (22, 32, 12), (11, 8, 5), occ), occ


def shard():
    occ = {}
    box(occ, "crystal", 2, 0, 2, 8, 10, 4, CRYSTAL)
    box(occ, "crystal", 4, 8, 2, 6, 14, 4, CRYSTAL)
    cells(occ, "crystal", [(4, 14, 2), (5, 14, 3), (4, 15, 2), (3, 10, 2), (6, 11, 3)], CRYSTAL_CORE)
    cells(occ, "grip", [(4, 0, 2), (5, 0, 3), (4, 1, 2), (5, 1, 3)], WOOD_DEEP)
    return model("crystal_shard", (10, 16, 10), (5, 2, 5), occ), occ


def main():
    os.makedirs(OUT, exist_ok=True)
    built = [
        sword(),
        spear(),
        pickaxe(),
        axe(),
        shovel(),
        shortbow(),
        sling(),
        hammer(),
        shard(),
    ]
    before = {
        "wooden_sword": 24,
        "spear": 18,
        "pickaxe": 18,
        "axe": 0,
        "shovel": 0,
        "shortbow": 36,
        "sling": 36,
        "crystal_hammer": 18,
        "crystal_shard": 6,
    }
    stats = {"before_quads_box_parts": before, "models": {}}
    for doc, occ in built:
        audit(doc["name"], occ)
        path = os.path.join(OUT, doc["name"] + ".json")
        with open(path, "w", newline="\n") as f:
            json.dump(doc, f, separators=(",", ":"))
            f.write("\n")
        n = sum(len(v) for v in doc["parts"].values())
        stats["models"][doc["name"]] = {
            "voxels": n,
            "parts": {k: len(v) for k, v in doc["parts"].items()},
            "palette": len(doc["palette"]),
            "pivot": doc["pivot"],
            "yspan_cells": max(c[1] for p in doc["parts"].values() for c in p) - min(c[1] for p in doc["parts"].values() for c in p) + 1,
        }
    with open(os.path.join(OUT, "stats.json"), "w", newline="\n") as f:
        json.dump(stats, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
