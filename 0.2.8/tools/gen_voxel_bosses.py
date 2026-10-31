"""Author crystalstorm-voxel-v1 bosses and the shard guard.

Base cubes are 2 cells (8 per terrain block). 1-cell cubes sit only on
silhouettes. Thick masses are hollow. Crystal mass plus the dark eye.
"""
import json
import os
import struct
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "voxel"))
OUT = os.path.join(ROOT, "entities")
CRYSTAL = 0
EYE = 1
PALETTE = [[184, 71, 255], [20, 20, 26]]
ORDER = ("body", "head", "leg_l", "leg_r", "tail")


def cube(dst, x, y, z, mat):
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                dst[(x + dx, y + dy, z + dz)] = mat


def solid(dst, x0, y0, z0, x1, y1, z1, mat):
    for z in range(z0, z1, 2):
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                cube(dst, x, y, z, mat)


def shell(dst, x0, y0, z0, x1, y1, z1, mat):
    for z in range(z0, z1, 2):
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                edge = x in (x0, x1 - 2) or y in (y0, y1 - 2) or z in (z0, z1 - 2)
                if edge:
                    cube(dst, x, y, z, mat)


def paint(dst, x0, y0, z0, x1, y1, z1, mat):
    for z in range(z0, z1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                if (x, y, z) in dst:
                    dst[(x, y, z)] = mat


def put(dst, cells, mat):
    for c in cells:
        dst[c] = mat


def guard():
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    solid(leg_l, 4, 0, 6, 8, 16, 10, CRYSTAL)
    solid(leg_r, 12, 0, 6, 16, 16, 10, CRYSTAL)
    put(leg_l, [(4, 0, 5), (5, 0, 5), (6, 0, 5), (7, 0, 5)], CRYSTAL)
    put(leg_r, [(12, 0, 5), (13, 0, 5), (14, 0, 5), (15, 0, 5)], CRYSTAL)
    shell(body, 4, 16, 4, 16, 30, 12, CRYSTAL)
    solid(body, 0, 22, 6, 4, 30, 10, CRYSTAL)
    solid(body, 16, 22, 6, 20, 30, 10, CRYSTAL)
    put(body, [(0, 30, 7), (1, 30, 8), (19, 30, 7), (18, 30, 8)], CRYSTAL)
    shell(head, 6, 30, 4, 14, 38, 12, CRYSTAL)
    paint(head, 7, 33, 4, 9, 35, 5, EYE)
    paint(head, 11, 33, 4, 13, 35, 5, EYE)
    solid(head, 8, 38, 6, 12, 40, 10, CRYSTAL)
    put(head, [(9, 40, 7), (10, 40, 8)], CRYSTAL)
    solid(tail, 8, 18, 12, 12, 34, 16, CRYSTAL)
    put(tail, [(9, 33, 16), (10, 34, 16), (9, 32, 16)], CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts


def warden():
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    solid(leg_l, 6, 0, 10, 10, 28, 14, CRYSTAL)
    solid(leg_r, 22, 0, 10, 26, 28, 14, CRYSTAL)
    put(leg_l, [(6, 0, 9), (7, 0, 9), (8, 0, 9), (9, 0, 9)], CRYSTAL)
    put(leg_r, [(22, 0, 9), (23, 0, 9), (24, 0, 9), (25, 0, 9)], CRYSTAL)
    shell(body, 8, 28, 8, 24, 50, 18, CRYSTAL)
    solid(body, 2, 36, 10, 6, 50, 14, CRYSTAL)
    solid(body, 26, 36, 10, 30, 50, 14, CRYSTAL)
    solid(body, 2, 50, 10, 6, 64, 14, CRYSTAL)
    solid(body, 26, 50, 10, 30, 64, 14, CRYSTAL)
    put(body, [(3, 64, 11), (3, 65, 11), (27, 64, 11), (27, 65, 11)], CRYSTAL)
    shell(head, 10, 50, 6, 22, 64, 16, CRYSTAL)
    paint(head, 12, 56, 6, 15, 59, 7, EYE)
    paint(head, 17, 56, 6, 20, 59, 7, EYE)
    solid(head, 14, 64, 8, 18, 70, 12, CRYSTAL)
    solid(head, 10, 64, 8, 14, 68, 12, CRYSTAL)
    solid(head, 18, 64, 8, 22, 68, 12, CRYSTAL)
    put(head, [(15, 70, 9), (16, 71, 10), (11, 68, 9), (20, 68, 10)], CRYSTAL)
    solid(tail, 12, 30, 18, 20, 56, 22, CRYSTAL)
    put(tail, [(14, 28, 19), (15, 27, 20), (16, 28, 19)], CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts


def tyrant():
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    solid(leg_l, 8, 0, 10, 12, 22, 14, CRYSTAL)
    solid(leg_r, 28, 0, 10, 32, 22, 14, CRYSTAL)
    put(leg_l, [(8, 0, 9), (9, 0, 9), (10, 0, 9), (11, 0, 9)], CRYSTAL)
    put(leg_r, [(28, 0, 9), (29, 0, 9), (30, 0, 9), (31, 0, 9)], CRYSTAL)
    shell(body, 8, 22, 6, 32, 44, 18, CRYSTAL)
    solid(body, 4, 30, 10, 8, 44, 14, CRYSTAL)
    solid(body, 32, 30, 10, 36, 44, 14, CRYSTAL)
    put(body, [(3, 43, 11), (3, 44, 11), (36, 43, 11), (36, 44, 11)], CRYSTAL)
    shell(head, 12, 44, 4, 28, 58, 14, CRYSTAL)
    paint(head, 15, 50, 4, 18, 53, 5, EYE)
    paint(head, 22, 50, 4, 25, 53, 5, EYE)
    put(head, [(15, 53, 3), (16, 53, 3), (22, 53, 3), (23, 53, 3)], CRYSTAL)
    solid(head, 8, 50, 6, 12, 64, 10, CRYSTAL)
    solid(head, 28, 50, 6, 32, 64, 10, CRYSTAL)
    put(head, [(8, 64, 7), (8, 65, 7), (31, 64, 7), (31, 65, 7)], CRYSTAL)
    solid(tail, 16, 26, 18, 24, 38, 22, CRYSTAL)
    solid(tail, 14, 18, 18, 26, 26, 22, CRYSTAL)
    put(tail, [(18, 17, 19), (19, 16, 20), (20, 17, 19)], CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts


def bounds(parts):
    xs, ys, zs = [], [], []
    for cells in parts.values():
        for x, y, z in cells:
            xs.append(x)
            ys.append(y)
            zs.append(z)
    return max(xs) + 1, max(ys) + 1, max(zs) + 1, min(xs), min(ys), min(zs)


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
            for (x, y, z), mat in cells.items():
                p = [x, y, z]
                n = p[:]
                n[axis] += 1 if sign > 0 else -1
                if tuple(n) in cells:
                    continue
                u = (axis + 1) % 3
                v = (axis + 2) % 3
                plane = p[axis] + (1 if sign > 0 else 0)
                key = (plane, mat)
                planes.setdefault(key, set()).add((p[u], p[v]))
            for mask in planes.values():
                quads += greedy_rects(mask)
    return quads


def merged(parts):
    out = {}
    for cells in parts.values():
        out.update(cells)
    return out


def audit(parts):
    overlap = 0
    seen = {}
    for part, cells in parts.items():
        for pos in cells:
            if pos in seen:
                overlap += 1
            seen[pos] = part
    detail = 0
    detail_buried = 0
    deep = 0
    neigh = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
    for cells in parts.values():
        dist = {}
        queue = []
        for (x, y, z) in cells:
            exposed = any((x + d[0], y + d[1], z + d[2]) not in cells for d in neigh)
            if exposed:
                dist[(x, y, z)] = 1
                queue.append((x, y, z))
            x0, y0, z0 = x & ~1, y & ~1, z & ~1
            full = True
            for dz in (0, 1):
                for dy in (0, 1):
                    for dx in (0, 1):
                        if (x0 + dx, y0 + dy, z0 + dz) not in cells:
                            full = False
            if not full:
                detail += 1
                if not exposed:
                    detail_buried += 1
        head = 0
        while head < len(queue):
            x, y, z = queue[head]
            head += 1
            for d in neigh:
                n = (x + d[0], y + d[1], z + d[2])
                if n in cells and n not in dist:
                    dist[n] = dist[(x, y, z)] + 1
                    queue.append(n)
        for pos in cells:
            if dist.get(pos, 99) > 2:
                deep += 1
    eyes = 0
    for cells in parts.values():
        for pos, mat in cells.items():
            if mat == EYE:
                eyes += 1
    return {"overlap": overlap, "deep": deep, "detail": detail, "detail_buried": detail_buried, "eyes": eyes}


def old_fill(parts, name, x0, y0, z0, x1, y1, z1, mat):
    dst = parts.setdefault(name, {})
    for z in range(z0, z1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                dst[(x, y, z)] = mat


def old_models():
    guard_p = {}
    old_fill(guard_p, "body", 3, 4, 3, 7, 10, 7, 1)
    old_fill(guard_p, "head", 3, 10, 3, 7, 13, 6, 1)
    old_fill(guard_p, "head", 3, 11, 5, 4, 12, 6, 2)
    old_fill(guard_p, "head", 6, 11, 5, 7, 12, 6, 2)
    old_fill(guard_p, "head", 4, 13, 4, 6, 16, 6, 1)
    old_fill(guard_p, "leg_l", 3, 0, 3, 5, 4, 5, 1)
    old_fill(guard_p, "leg_l", 3, 0, 3, 5, 1, 5, 2)
    old_fill(guard_p, "leg_r", 5, 0, 4, 7, 4, 6, 1)
    old_fill(guard_p, "leg_r", 5, 0, 4, 7, 1, 6, 2)
    old_fill(guard_p, "tail", 3, 7, 6, 4, 12, 7, 1)
    warden_p = {}
    old_fill(warden_p, "body", 2, 5, 3, 10, 11, 8, 4)
    old_fill(warden_p, "body", 3, 6, 2, 9, 10, 3, 1)
    old_fill(warden_p, "body", 5, 7, 1, 7, 9, 2, 3)
    old_fill(warden_p, "body", 1, 9, 3, 3, 13, 6, 1)
    old_fill(warden_p, "body", 9, 9, 3, 11, 13, 6, 1)
    old_fill(warden_p, "body", 0, 11, 4, 1, 15, 5, 1)
    old_fill(warden_p, "body", 11, 11, 4, 12, 15, 5, 1)
    old_fill(warden_p, "head", 4, 11, 2, 8, 14, 6, 4)
    old_fill(warden_p, "head", 4, 12, 1, 8, 13, 2, 2)
    old_fill(warden_p, "head", 4, 12, 1, 5, 13, 2, 3)
    old_fill(warden_p, "head", 7, 12, 1, 8, 13, 2, 3)
    old_fill(warden_p, "head", 5, 14, 3, 7, 17, 5, 1)
    old_fill(warden_p, "head", 4, 14, 4, 5, 16, 5, 1)
    old_fill(warden_p, "head", 7, 14, 4, 8, 16, 5, 1)
    old_fill(warden_p, "leg_l", 2, 0, 3, 5, 5, 7, 4)
    old_fill(warden_p, "leg_l", 2, 0, 2, 5, 1, 7, 2)
    old_fill(warden_p, "leg_l", 0, 4, 3, 2, 10, 6, 4)
    old_fill(warden_p, "leg_l", 0, 3, 2, 2, 5, 6, 1)
    old_fill(warden_p, "leg_r", 7, 0, 3, 10, 5, 7, 4)
    old_fill(warden_p, "leg_r", 7, 0, 2, 10, 1, 7, 2)
    old_fill(warden_p, "leg_r", 10, 4, 3, 12, 10, 6, 4)
    old_fill(warden_p, "leg_r", 10, 3, 2, 12, 5, 6, 1)
    old_fill(warden_p, "tail", 4, 8, 8, 8, 12, 9, 1)
    old_fill(warden_p, "tail", 5, 10, 9, 7, 16, 10, 1)
    old_fill(warden_p, "tail", 3, 11, 9, 4, 14, 10, 1)
    old_fill(warden_p, "tail", 8, 11, 9, 9, 14, 10, 1)
    out = {}
    for name, parts in (("shard_guard", guard_p), ("origin_warden", warden_p)):
        out[name] = {
            "voxels": sum(len(c) for c in parts.values()),
            "quads": quad_count(merged(parts)),
            "part_quads": sum(quad_count(c) for c in parts.values()),
        }
    out["shard_tyrant"] = dict(out["shard_guard"])
    out["shard_tyrant"]["note"] = "spawn elite reused the shard guard rig"
    return out


def dump(name, parts):
    sx, sy, sz, min_x, min_y, min_z = bounds(parts)
    if min_x < 0 or min_y < 0 or min_z < 0:
        raise SystemExit("%s has a negative cell" % name)
    packed = {}
    voxels = 0
    part_quads = {}
    for key in ORDER:
        cells = [[x, y, z, mat] for (x, y, z), mat in sorted(parts[key].items())]
        packed[key] = cells
        voxels += len(cells)
        part_quads[key] = quad_count(parts[key])
    pivot_x = (min_x + sx - 1) // 2
    doc = {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": [sx, sy, sz],
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": [pivot_x, 0, 0],
        "palette": PALETTE,
        "parts": packed,
    }
    path = os.path.join(OUT, name + ".json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, separators=(",", ":"))
        f.write("\n")
    info = audit(parts)
    info.update({
        "voxels": voxels,
        "quads": quad_count(merged(parts)),
        "part_quads": sum(part_quads.values()),
        "parts": {key: len(packed[key]) for key in ORDER},
        "quads_by_part": part_quads,
        "blocks_tall": round(sy / 16.0, 3),
    })
    return info


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def preview(models):
    cell = 4
    pad = 10
    names = list(models.keys())
    tiles = []
    for name in names:
        parts = models[name]
        sx, sy, sz, *_rest = bounds(parts)
        tiles.append((name, parts, sx, sy))
    tile_w = max(t[2] for t in tiles) * cell + pad * 2
    tile_h = max(t[3] for t in tiles) * cell + pad * 2
    width = tile_w * len(tiles)
    height = tile_h
    buf = bytearray([28, 32, 40]) * (width * height)
    for i, (name, parts, _sx, sy) in enumerate(tiles):
        ox = i * tile_w + pad
        oy = pad
        occ = {}
        for cells in parts.values():
            for (x, y, z), mat in cells.items():
                key = (x, y)
                if key not in occ or z < occ[key][0]:
                    occ[key] = (z, mat)
        for (x, y), (_z, mat) in occ.items():
            color = PALETTE[mat]
            for py in range(cell):
                for px in range(cell):
                    sx = ox + x * cell + px
                    sy = oy + (sy - 1 - y) * cell + py
                    if sx < 0 or sy < 0 or sx >= width or sy >= height:
                        continue
                    at = (sy * width + sx) * 3
                    buf[at] = color[0]
                    buf[at + 1] = color[1]
                    buf[at + 2] = color[2]
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw.extend(buf[y * width * 3:(y + 1) * width * 3])
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    blob = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(os.path.join(OUT, "bosses_preview.png"), "wb") as f:
        f.write(blob)


def main():
    models = {
        "shard_guard": guard(),
        "origin_warden": warden(),
        "shard_tyrant": tyrant(),
    }
    stats_path = os.path.join(OUT, "stats.json")
    with open(stats_path, encoding="utf-8") as f:
        stats = json.load(f)
    before = old_models()
    bosses = {}
    scale = {"shard_guard": 1.0, "origin_warden": 1.3, "shard_tyrant": 1.35}
    for name, parts in models.items():
        info = dump(name, parts)
        info["visual_blocks"] = round(info["blocks_tall"] * scale[name], 3)
        bosses[name] = info
        problems = []
        if info["overlap"] or info["deep"] or info["detail_buried"] or info["eyes"] < 4:
            problems.append("audit")
        if name == "shard_guard" and (info["part_quads"] > 3000 or info["quads"] > 3000):
            problems.append("budget")
        if name != "shard_guard" and (info["blocks_tall"] < 4.0 or info["blocks_tall"] > 6.0):
            problems.append("height")
        if name != "shard_guard" and info["visual_blocks"] > 6.0:
            problems.append("scaled height")
        if problems:
            raise SystemExit("%s %s %s" % (name, problems, info))
        print(name, info["voxels"], "quads", info["quads"], "part", info["part_quads"], "blocks", info["blocks_tall"], "visual", info["visual_blocks"], "audit", info["overlap"], info["deep"], info["detail"], info["detail_buried"])
    preview(models)
    stats["bosses_before"] = before
    stats["bosses"] = bosses
    stats["boss_profile"] = "authored part quads replace the procedural rig; terrain and the 10% crystal mesh are unchanged"
    with open(stats_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(stats, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
