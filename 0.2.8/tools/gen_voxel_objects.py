import json
import math
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "voxel")
OUT = os.path.join(ROOT, "objects")

WOOD_DEEP = (40, 28, 22)
WOOD = (64, 44, 32)
WOOD_MID = (92, 64, 44)
WOOD_LIGHT = (122, 88, 58)
BELT = (107, 71, 36)
STONE = (132, 134, 140)
STONE_EDGE = (176, 178, 184)
STONE_DARK = (78, 80, 86)
BLADE = (196, 200, 206)
BLADE_EDGE = (232, 234, 238)
CRYSTAL = (184, 71, 255)
CRYSTAL_CORE = (140, 46, 242)
FLAME_RED = (186, 42, 38)
FLAME_ORANGE = (230, 140, 56)
FLAME_YELLOW = (214, 176, 42)
CLOTH = (56, 107, 87)
CLOTH_DARK = (24, 52, 30)
LINEN = (214, 210, 196)
LINEN_BRIGHT = (236, 232, 220)
EYE = (20, 20, 26)
BOOT = (51, 36, 26)

DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
BUDGET = 1500


def band(a, b, axis):
    def pick(x, y, z):
        coord = (x, y, z)[axis]
        return a if ((coord // 2) % 2) == 0 else b
    return pick


def fill(occ, part, x0, y0, z0, x1, y1, z1, mat):
    for y in range(y0, y1, 2):
        for z in range(z0, z1, 2):
            for x in range(x0, x1, 2):
                color = mat(x, y, z) if callable(mat) else mat
                for dy in (0, 1):
                    for dz in (0, 1):
                        for dx in (0, 1):
                            occ[(x + dx, y + dy, z + dz)] = (part, color)


def carve(occ, x0, y0, z0, x1, y1, z1):
    for key in list(occ.keys()):
        x, y, z = key
        if x0 <= x < x1 and y0 <= y < y1 and z0 <= z < z1:
            del occ[key]


def neighbors(occ, x, y, z):
    n = 0
    for d in DIRS:
        if (x + d[0], y + d[1], z + d[2]) in occ:
            n += 1
    return n


def add_cell(occ, part, x, y, z, mat):
    if (x, y, z) in occ or x < 0 or y < 0 or z < 0:
        return False
    occ[(x, y, z)] = (part, mat)
    if neighbors(occ, x, y, z) >= 6:
        del occ[(x, y, z)]
        return False
    for d in DIRS:
        nx, ny, nz = x + d[0], y + d[1], z + d[2]
        if (nx, ny, nz) in occ and neighbors(occ, nx, ny, nz) >= 6:
            del occ[(x, y, z)]
            return False
    return True


def lip(occ, part, cells, mat):
    for x, y, z in cells:
        add_cell(occ, part, x, y, z, mat)


def ring(occ, part, x0, y0, z0, x1, y1, z1, mat):
    for y in range(y0, y1, 2):
        for z in range(z0, z1, 2):
            for x in range(x0, x1, 2):
                if x == x0 or x >= x1 - 2 or z == z0 or z >= z1 - 2:
                    fill(occ, part, x, y, z, x + 2, y + 2, z + 2, mat)
    if x1 - x0 >= 4 and z1 - z0 >= 4:
        for y in range(y0, y1):
            for x in (x0 + 1, x1 - 2):
                for z in (z0 + 1, z1 - 2):
                    occ.pop((x, y, z), None)


def sheet(occ, part, x0, y, z0, x1, z1, mat):
    for z in range(z0, z1):
        for x in range(x0, x1):
            color = mat(x, y, z) if callable(mat) else mat
            occ[(x, y, z)] = (part, color)


def model(name, occ, pivot):
    used = []
    index = {}
    parts = {}
    max_c = [0, 0, 0]
    for (x, y, z), (part, mat) in sorted(occ.items()):
        if mat not in index:
            index[mat] = len(used)
            used.append(list(mat))
        parts.setdefault(part, []).append([x, y, z, index[mat]])
        max_c[0] = max(max_c[0], x + 1)
        max_c[1] = max(max_c[1], y + 1)
        max_c[2] = max(max_c[2], z + 1)
    return {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": max_c,
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": list(pivot),
        "palette": used,
        "parts": parts,
    }


def cells_of(doc):
    out = {}
    pal = [tuple(c) for c in doc["palette"]]
    for part, cells in doc["parts"].items():
        for x, y, z, i in cells:
            out[(x, y, z)] = (part, pal[i])
    return out


def greedy_rects(mask):
    used = set()
    quads = 0
    for u, v in sorted(mask):
        if (u, v) in used:
            continue
        w = 1
        while (u + w, v) in mask and (u + w, v) not in used:
            w += 1
        h = 1
        while all((u + du, v + h) in mask and (u + du, v + h) not in used for du in range(w)):
            h += 1
        for du in range(w):
            for dv in range(h):
                used.add((u + du, v + dv))
        quads += 1
    return quads


def quad_count(cells):
    quads = 0
    for axis in range(3):
        for sign in (-1, 1):
            planes = {}
            for (x, y, z), (_part, mat) in cells.items():
                p = [x, y, z]
                n = p[:]
                n[axis] += sign
                if tuple(n) in cells:
                    continue
                u = (axis + 1) % 3
                v = (axis + 2) % 3
                plane = p[axis] + (1 if sign > 0 else 0)
                planes.setdefault((plane, mat), set()).add((p[u], p[v]))
            for mask in planes.values():
                quads += greedy_rects(mask)
    return quads


def audit(name, occ):
    interior = 0
    detail = 0
    buried_detail = 0
    for x, y, z in occ:
        n6 = neighbors(occ, x, y, z)
        if n6 >= 6:
            interior += 1
        origin = (x - x % 2, y - y % 2, z - z % 2)
        full = True
        for dy in (0, 1):
            for dz in (0, 1):
                for dx in (0, 1):
                    if (origin[0] + dx, origin[1] + dy, origin[2] + dz) not in occ:
                        full = False
        if not full:
            detail += 1
            if n6 >= 6:
                buried_detail += 1
    if interior or buried_detail:
        raise SystemExit("%s interior=%d buried_detail=%d" % (name, interior, buried_detail))
    return {"interior": interior, "detail": detail, "buried_detail": buried_detail}


def torch():
    occ = {}
    fill(occ, "body", 2, 0, 2, 4, 14, 4, band(WOOD, WOOD_MID, 1))
    fill(occ, "body", 0, 0, 2, 2, 2, 4, WOOD_DEEP)
    fill(occ, "body", 4, 0, 2, 6, 2, 4, WOOD_DEEP)
    lip(occ, "body", [(1, 6, 2), (4, 8, 3), (2, 10, 1), (3, 12, 4)], WOOD_DEEP)
    fill(occ, "flame", 2, 14, 2, 4, 18, 4, FLAME_ORANGE)
    lip(occ, "flame", [(2, 18, 2), (3, 18, 3), (2, 19, 2), (1, 16, 2), (4, 15, 3)], FLAME_YELLOW)
    lip(occ, "flame", [(2, 15, 1), (3, 16, 4)], FLAME_RED)
    return model("torch", occ, (3, 0, 3)), occ


def chest():
    occ = {}
    wood = band(WOOD, WOOD_MID, 0)
    ring(occ, "body", 0, 0, 0, 16, 8, 12, wood)
    sheet(occ, "lid", 0, 8, 0, 16, 12, band(WOOD_MID, WOOD_LIGHT, 0))
    lip(occ, "lid", [(x, 9, 0) for x in range(0, 16, 2)] + [(x, 9, 11) for x in range(0, 16, 2)] + [(0, 9, z) for z in range(2, 12, 2)] + [(15, 9, z) for z in range(1, 12, 2)], WOOD_DEEP)
    lip(occ, "body", [(0, 4, 0), (15, 4, 0), (0, 4, 11), (15, 4, 11)], BLADE)
    fill(occ, "body", 6, 4, 0, 10, 6, 2, BELT)
    return model("chest", occ, (8, 8, 0)), occ


def door():
    occ = {}
    fill(occ, "hinge", 0, 0, 2, 2, 32, 4, band(WOOD_DEEP, BELT, 1))
    lip(occ, "hinge", [(0, y, 1) for y in (4, 12, 20, 28)] + [(0, y, 4) for y in (6, 14, 22)], BLADE_EDGE)
    fill(occ, "leaf", 2, 0, 2, 16, 32, 4, band(WOOD, WOOD_MID, 1))
    lip(occ, "leaf", [(15, y, 2) for y in range(2, 30, 4)] + [(15, y, 3) for y in range(4, 30, 4)], WOOD_DEEP)
    lip(occ, "leaf", [(12, 14, 1), (13, 15, 1), (12, 16, 1)], BLADE)
    return model("door", occ, (1, 0, 3)), occ


def workbench():
    occ = {}
    for x, z in ((0, 0), (14, 0), (0, 14), (14, 14)):
        fill(occ, "body", x, 0, z, x + 2, 8, z + 2, WOOD_DEEP)
    sheet(occ, "body", 0, 8, 0, 16, 16, band(WOOD, WOOD_MID, 0))
    lip(occ, "body", [(x, 9, 0) for x in range(0, 16, 2)] + [(x, 9, 15) for x in range(1, 16, 2)], WOOD_LIGHT)
    lip(occ, "body", [(2, 9, 0), (3, 10, 0), (4, 9, 0), (5, 11, 0)], STONE_EDGE)
    lip(occ, "body", [(10, 9, 0), (11, 10, 0), (12, 9, 0), (13, 10, 1)], BLADE)
    return model("workbench", occ, (8, 0, 8)), occ


def furnace():
    occ = {}
    stone = band(STONE, STONE_DARK, 1)
    ring(occ, "body", 0, 0, 0, 16, 14, 16, stone)
    sheet(occ, "body", 0, 14, 0, 16, 16, STONE)
    carve(occ, 4, 2, 0, 12, 8, 2)
    fill(occ, "ember", 6, 0, 6, 8, 4, 8, FLAME_ORANGE)
    lip(occ, "ember", [(6, 4, 6), (7, 4, 7), (6, 3, 5)], FLAME_YELLOW)
    lip(occ, "body", [(4, 8, 0), (11, 8, 0), (4, 2, 0), (11, 2, 0)], STONE_EDGE)
    fill(occ, "body", 0, 15, 14, 2, 22, 16, STONE_DARK)
    lip(occ, "body", [(0, 22, 14), (1, 23, 15)], STONE_EDGE)
    return model("furnace", occ, (8, 0, 8)), occ


def crystal_node():
    occ = {}
    sheet(occ, "body", 2, 0, 2, 14, 14, band(STONE, STONE_DARK, 0))
    for x, z, h, mat in (
        (4, 4, 8, CRYSTAL),
        (10, 4, 6, CRYSTAL),
        (6, 8, 12, CRYSTAL),
        (10, 10, 7, CRYSTAL_CORE),
    ):
        fill(occ, "crystal", x, 1, z, x + 2, 1 + h, z + 2, mat)
        tip = CRYSTAL_CORE if mat == CRYSTAL else BLADE_EDGE
        lip(occ, "crystal", [(x, 1 + h, z), (x + 1, 1 + h, z + 1)], tip)
    return model("crystal_node", occ, (8, 0, 8)), occ


def bed():
    occ = {}
    fill(occ, "frame", 0, 0, 0, 16, 2, 2, WOOD_DEEP)
    fill(occ, "frame", 0, 0, 30, 16, 2, 32, WOOD_DEEP)
    fill(occ, "frame", 0, 0, 2, 2, 2, 30, WOOD_DEEP)
    fill(occ, "frame", 14, 0, 2, 16, 2, 30, WOOD)
    sheet(occ, "bedding", 2, 2, 2, 14, 28, band(CLOTH, CLOTH_DARK, 2))
    sheet(occ, "bedding", 2, 2, 28, 14, 32, LINEN)
    lip(occ, "bedding", [(3, 3, 30), (6, 3, 31), (10, 3, 30), (12, 3, 29), (4, 3, 28)], LINEN_BRIGHT)
    lip(occ, "bedding", [(2, 3, 8), (13, 3, 14), (4, 3, 20)], CLOTH_DARK)
    return model("bed", occ, (8, 0, 16)), occ


def sign():
    occ = {}
    fill(occ, "post", 6, 0, 6, 8, 26, 8, band(WOOD, WOOD_DEEP, 1))
    for y in range(18, 28):
        for x in range(0, 16):
            color = LINEN if (x // 2) % 2 == 0 else LINEN_BRIGHT
            occ[(x, y, 5)] = ("board", color)
    lip(occ, "board", [(x, 28, 5) for x in range(0, 16, 2)] + [(0, 20, 4), (15, 22, 4)], WOOD_DEEP)
    lip(occ, "board", [(2, 22, 4), (4, 22, 4), (6, 23, 4), (9, 22, 4), (11, 23, 4)], EYE)
    return model("sign", occ, (7, 0, 7)), occ


def wood_wall():
    occ = {}
    for x in (0, 4, 8, 12):
        fill(occ, "body", x, 0, 2, x + 2, 24, 4, band(WOOD, WOOD_MID, 1))
        lip(occ, "body", [(x, 24, 2), (x + 1, 25, 3)], WOOD_LIGHT)
    fill(occ, "body", 0, 8, 2, 16, 10, 4, WOOD_DEEP)
    fill(occ, "body", 0, 16, 2, 16, 18, 4, BELT)
    return model("wood_wall", occ, (8, 0, 2)), occ


def stone_wall():
    occ = {}
    stone = band(STONE, STONE_DARK, 1)
    fill(occ, "body", 0, 0, 0, 16, 22, 2, stone)
    fill(occ, "body", 0, 0, 4, 16, 22, 6, stone)
    for x in (0, 4, 8, 12):
        fill(occ, "body", x, 22, 0, x + 4, 26, 2, STONE_EDGE if x % 8 == 0 else STONE)
        fill(occ, "body", x, 22, 4, x + 4, 26, 6, STONE_EDGE if x % 8 == 0 else STONE_DARK)
        if x % 8 == 0:
            carve(occ, x + 1, 24, 0, x + 3, 26, 2)
    lip(occ, "body", [(0, 22, 0), (15, 22, 0), (0, 22, 5), (15, 22, 5)], STONE_EDGE)
    return model("stone_wall", occ, (8, 0, 3)), occ


def gate():
    occ = {}
    stone = band(STONE, STONE_DARK, 1)
    for x in (0, 12):
        fill(occ, "post", x, 0, 0, x + 4, 28, 2, stone)
        fill(occ, "post", x, 0, 4, x + 4, 28, 6, stone)
        lip(occ, "hinge", [(x + (3 if x == 0 else 0), y, 2) for y in (6, 14, 22)], BLADE)
    fill(occ, "lintel", 0, 26, 0, 16, 32, 2, STONE_EDGE)
    fill(occ, "lintel", 0, 26, 4, 16, 32, 6, STONE)
    lip(occ, "lintel", [(x, 32, 0) for x in range(0, 16, 2)] + [(x, 32, 5) for x in range(1, 16, 2)], STONE_EDGE)
    return model("gate", occ, (8, 0, 3)), occ


def bridge():
    occ = {}
    sheet(occ, "deck", 0, 2, 0, 16, 16, band(WOOD, WOOD_MID, 2))
    lip(occ, "deck", [(x, 3, 0) for x in range(2, 14, 2)] + [(x, 3, 15) for x in range(2, 14, 2)], WOOD_LIGHT)
    for x in (0, 14):
        fill(occ, "rail", x, 3, 0, x + 2, 8, 2, WOOD_DEEP)
        fill(occ, "rail", x, 3, 14, x + 2, 8, 16, WOOD_DEEP)
        fill(occ, "rail", x, 6, 2, x + 2, 8, 14, BELT)
    return model("bridge", occ, (8, 0, 8)), occ


def gable_height(x, x0, x1, wall_h, rise):
    span = max(x1 - x0 - 2, 2)
    t = (x - x0) / float(span)
    t = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    extra = int(round(math.sin(math.pi * t) * (rise / 2.0))) * 2
    return wall_h + max(extra, 0)


def town_hall():
    occ = {}
    stone = band(STONE, STONE_DARK, 1)
    wood = band(WOOD, WOOD_MID, 0)
    x0, z0, x1, z1 = 0, 0, 32, 24
    wall_h, rise = 16, 8
    for x in range(x0, x1):
        gable = gable_height(x, x0, x1, wall_h, rise)
        for z in (z0, z1 - 1):
            for y in range(gable):
                occ[(x, y, z)] = ("body", stone(x, y, z))
        for z in range(z0 + 1, z1 - 1):
            occ[(x, gable - 1, z)] = ("roof", wood(x, gable - 1, z))
    for z in range(z0 + 1, z1 - 1):
        for x in (x0, x1 - 1):
            for y in range(wall_h):
                occ[(x, y, z)] = ("body", stone(x, y, z))
    for x in range(12, 20):
        for y in range(10):
            occ.pop((x, y, z0), None)
    lip(occ, "body", [(12, y, z0) for y in range(0, 10, 2)] + [(19, y, z0) for y in range(0, 10, 2)], STONE_EDGE)
    peak = gable_height(16, x0, x1, wall_h, rise)
    fill(occ, "crystal", 16, peak, 11, 18, peak + 4, 13, CRYSTAL)
    lip(occ, "crystal", [(16, peak + 4, 11), (17, peak + 5, 12)], CRYSTAL_CORE)
    lip(occ, "roof", [(x, gable_height(x, x0, x1, wall_h, rise), z0) for x in range(0, 32, 4)], WOOD_DEEP)
    return model("town_hall", occ, (16, 0, 12)), occ


def ruin_pillar():
    occ = {}
    stone = band(STONE_DARK, STONE, 1)
    rim = [26, 18, 24, 14, 22, 16, 20, 12, 23, 15, 21, 13]
    i = 0
    for z in range(2, 10):
        for x in range(2, 10):
            edge = x in (2, 9) or z in (2, 9)
            if not edge:
                continue
            h = rim[i % len(rim)]
            i += 1
            for y in range(h):
                occ[(x, y, z)] = ("body", stone(x, y, z))
            add_cell(occ, "body", x, h, z, STONE_EDGE)
    sheet(occ, "body", 4, 0, 4, 8, 8, STONE)
    return model("ruin_pillar", occ, (6, 0, 6)), occ


def png(path, width, height, rgb):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(rgb[y * width * 3:(y + 1) * width * 3])

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(blob)


def paint(buf, width, height, ox, oy, occ, scale):
    order = sorted(occ.keys(), key=lambda p: p[0] + p[2] + p[1] * 0.01)
    for x, y, z in order:
        _part, mat = occ[(x, y, z)]
        sx = ox + int((x - z) * scale)
        sy = oy + int((x + z) * 0.5 * scale - y * scale)
        shade = 1.0 if (x + z) % 2 == 0 else 0.82
        col = (int(mat[0] * shade), int(mat[1] * shade), int(mat[2] * shade))
        for py in range(scale):
            for px in range(scale):
                px0 = sx + px
                py0 = sy + py
                if px0 < 0 or py0 < 0 or px0 >= width or py0 >= height:
                    continue
                i0 = (py0 * width + px0) * 3
                buf[i0] = col[0]
                buf[i0 + 1] = col[1]
                buf[i0 + 2] = col[2]


def preview(models):
    names = list(models.keys())
    cols = 7
    rows = 2
    tile_w = 220
    tile_h = 280
    width = cols * tile_w
    height = rows * tile_h
    buf = bytearray([28, 32, 38]) * (width * height)
    for i, name in enumerate(names):
        col = i % cols
        row = i // cols
        ox = col * tile_w + 120
        oy = row * tile_h + 200
        paint(buf, width, height, ox, oy, models[name], 3)
    png(os.path.join(OUT, "objects_preview.png"), width, height, buf)


def main():
    os.makedirs(OUT, exist_ok=True)
    built = [
        torch(),
        chest(),
        door(),
        workbench(),
        furnace(),
        crystal_node(),
        bed(),
        sign(),
        wood_wall(),
        stone_wall(),
        gate(),
        bridge(),
        town_hall(),
        ruin_pillar(),
    ]
    before = {
        "torch": 0,
        "chest": 0,
        "door": 0,
        "workbench": 0,
        "furnace": 0,
        "crystal_node": 0,
        "bed": 0,
        "sign": 0,
        "wood_wall": 12,
        "stone_wall": 12,
        "gate": 18,
        "bridge": 18,
        "town_hall": 18,
        "ruin_pillar": 18,
    }
    stats = {
        "budget_quads": BUDGET,
        "before_quads": before,
        "profile": "quads at authored occupancy; live buildings stay on authored OBJ meshes (not sprites or boxes), so the 10% crystal load profile is unchanged",
        "models": {},
    }
    painted = {}
    for doc, occ in built:
        info = audit(doc["name"], occ)
        quads = quad_count(occ)
        if quads > BUDGET:
            raise SystemExit("%s quads %d" % (doc["name"], quads))
        if len(doc["palette"]) > 16:
            raise SystemExit("%s palette" % doc["name"])
        path = os.path.join(OUT, doc["name"] + ".json")
        with open(path, "w", newline="\n") as f:
            json.dump(doc, f, separators=(",", ":"))
            f.write("\n")
        part_counts = {k: len(v) for k, v in doc["parts"].items()}
        ys = [p[1] for p in occ]
        stats["models"][doc["name"]] = {
            "voxels": len(occ),
            "quads": quads,
            "parts": part_counts,
            "palette": len(doc["palette"]),
            "pivot": doc["pivot"],
            "yspan_cells": max(ys) - min(ys) + 1,
            "detail": info["detail"],
            "before_quads": before[doc["name"]],
        }
        painted[doc["name"]] = occ
        print("OK %s voxels=%d quads=%d parts=%s" % (doc["name"], len(occ), quads, part_counts))
    with open(os.path.join(OUT, "stats.json"), "w", newline="\n") as f:
        json.dump(stats, f, indent=2)
        f.write("\n")
    preview(painted)


if __name__ == "__main__":
    main()
