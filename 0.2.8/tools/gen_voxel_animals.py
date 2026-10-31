import json
import os
import struct
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "assets", "voxel"))
OUT = os.path.join(ROOT, "entities")
EYE = [20, 20, 26]
CRYSTAL = [184, 71, 255]
DEER = [[184, 133, 97], [219, 184, 138], [82, 51, 31], EYE]
STAG = [[184, 133, 97], [219, 184, 138], CRYSTAL, EYE]
BOAR = [[122, 92, 82], [168, 128, 107], [56, 36, 31], EYE]
BEAST = [[122, 92, 82], [168, 128, 107], [56, 36, 31], EYE, CRYSTAL]
RABBIT = [[184, 148, 107], [235, 219, 189], [219, 158, 148], EYE]
BIRD = [[115, 148, 199], [199, 219, 240], [230, 140, 56], EYE]
WISP = [CRYSTAL, EYE, [230, 140, 56]]


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


def shell(dst, x0, y0, z0, x1, y1, z1, mat, belly=None):
    for z in range(z0, z1, 2):
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                edge = x in (x0, x1 - 2) or y in (y0, y1 - 2) or z in (z0, z1 - 2)
                if not edge:
                    continue
                use = belly if belly is not None and y == y0 else mat
                cube(dst, x, y, z, use)


def paint(dst, x0, y0, z0, x1, y1, z1, mat):
    for z in range(z0, z1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                if (x, y, z) in dst:
                    dst[(x, y, z)] = mat


def deer(crystal):
    hide, belly, accent, eye = 0, 1, 2, 3
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    shell(body, 4, 8, 12, 16, 16, 26, hide, belly)
    shell(head, 4, 14, 2, 14, 22, 10, hide)
    solid(head, 8, 14, 8, 12, 18, 12, hide)
    solid(head, 8, 14, 0, 12, 18, 4, hide)
    solid(head, 4, 22, 4, 6, 28, 6, hide)
    solid(head, 12, 22, 4, 14, 28, 6, hide)
    head[(4, 28, 4)] = hide
    head[(5, 28, 5)] = hide
    head[(12, 28, 4)] = hide
    head[(13, 28, 5)] = hide
    solid(head, 6, 22, 4, 8, 30, 6, accent)
    solid(head, 4, 26, 4, 6, 28, 6, accent)
    solid(head, 10, 22, 4, 12, 30, 6, accent)
    solid(head, 12, 26, 4, 14, 28, 6, accent)
    head[(7, 30, 5)] = accent
    head[(5, 28, 3)] = accent
    head[(10, 30, 5)] = accent
    head[(13, 28, 3)] = accent
    paint(head, 5, 18, 2, 7, 20, 3, eye)
    paint(head, 11, 18, 2, 13, 20, 3, eye)
    solid(leg_l, 4, 0, 12, 6, 8, 14, hide)
    solid(leg_l, 4, 0, 22, 6, 8, 24, hide)
    solid(leg_r, 12, 0, 12, 14, 8, 14, hide)
    solid(leg_r, 12, 0, 22, 14, 8, 24, hide)
    paint(leg_l, 4, 0, 12, 6, 2, 14, accent if not crystal else hide)
    paint(leg_l, 4, 0, 22, 6, 2, 24, accent if not crystal else hide)
    paint(leg_r, 12, 0, 12, 14, 2, 14, accent if not crystal else hide)
    paint(leg_r, 12, 0, 22, 14, 2, 24, accent if not crystal else hide)
    leg_l[(4, 0, 11)] = accent if not crystal else hide
    leg_l[(5, 0, 11)] = accent if not crystal else hide
    leg_l[(4, 0, 24)] = accent if not crystal else hide
    leg_l[(5, 0, 24)] = accent if not crystal else hide
    leg_r[(12, 0, 11)] = accent if not crystal else hide
    leg_r[(13, 0, 11)] = accent if not crystal else hide
    leg_r[(12, 0, 24)] = accent if not crystal else hide
    leg_r[(13, 0, 24)] = accent if not crystal else hide
    solid(tail, 8, 12, 26, 12, 16, 30, belly)
    tail[(9, 14, 30)] = belly
    tail[(10, 14, 30)] = belly
    tail[(9, 15, 30)] = belly
    if crystal:
        paint(body, 8, 14, 14, 12, 16, 24, accent)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts, (STAG if crystal else DEER)


def boar(crystal):
    hide, belly, dark, eye = 0, 1, 2, 3
    tusk = 4 if crystal else dark
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    shell(body, 2, 6, 10, 16, 14, 24, hide, belly)
    shell(head, 2, 6, 2, 16, 14, 10, hide)
    solid(head, 4, 6, 0, 14, 10, 4, dark)
    solid(head, 2, 12, 4, 4, 16, 6, hide)
    solid(head, 14, 12, 4, 16, 16, 6, hide)
    solid(head, 4, 4, 0, 6, 6, 2, tusk)
    solid(head, 12, 4, 0, 14, 6, 2, tusk)
    head[(4, 3, 0)] = tusk
    head[(5, 3, 0)] = tusk
    head[(12, 3, 0)] = tusk
    head[(13, 3, 0)] = tusk
    paint(head, 3, 10, 2, 5, 12, 3, eye)
    paint(head, 13, 10, 2, 15, 12, 3, eye)
    solid(leg_l, 2, 0, 10, 4, 6, 12, hide)
    solid(leg_l, 2, 0, 20, 4, 6, 22, hide)
    solid(leg_r, 12, 0, 10, 14, 6, 12, hide)
    solid(leg_r, 12, 0, 20, 14, 6, 22, hide)
    paint(leg_l, 2, 0, 10, 4, 2, 12, dark)
    paint(leg_l, 2, 0, 20, 4, 2, 22, dark)
    paint(leg_r, 12, 0, 10, 14, 2, 12, dark)
    paint(leg_r, 12, 0, 20, 14, 2, 22, dark)
    solid(tail, 8, 10, 24, 10, 12, 28, hide)
    tail[(8, 12, 27)] = hide
    tail[(9, 12, 27)] = hide
    if crystal:
        paint(body, 6, 12, 12, 12, 14, 22, tusk)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts, (BEAST if crystal else BOAR)


def rabbit():
    hide, belly, ear, eye = 0, 1, 2, 3
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    shell(body, 4, 6, 8, 12, 12, 16, hide, belly)
    shell(head, 4, 8, 2, 12, 14, 8, hide)
    solid(head, 4, 14, 4, 6, 22, 6, ear)
    solid(head, 10, 14, 4, 12, 22, 6, ear)
    head[(4, 22, 4)] = ear
    head[(5, 22, 5)] = ear
    head[(10, 22, 4)] = ear
    head[(11, 22, 5)] = ear
    solid(head, 6, 8, 0, 10, 10, 2, hide)
    paint(head, 4, 10, 2, 6, 12, 3, eye)
    paint(head, 10, 10, 2, 12, 12, 3, eye)
    solid(leg_l, 4, 0, 8, 6, 6, 10, hide)
    solid(leg_l, 2, 0, 12, 6, 6, 16, hide)
    solid(leg_r, 10, 0, 8, 12, 6, 10, hide)
    solid(leg_r, 10, 0, 12, 14, 6, 16, hide)
    solid(tail, 6, 8, 16, 10, 12, 20, belly)
    tail[(7, 10, 20)] = belly
    tail[(8, 10, 20)] = belly
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return parts, RABBIT


def bird(wisp):
    body_c, belly, beak, eye = 0, 1, 2, 3
    body, head, leg_l, leg_r, wing_l, wing_r, tail = {}, {}, {}, {}, {}, {}, {}
    shell(body, 8, 4, 8, 16, 10, 14, body_c, belly)
    shell(head, 8, 8, 2, 16, 14, 8, body_c)
    solid(head, 10, 8, 0, 14, 12, 2, beak)
    head[(11, 9, 0)] = beak
    head[(12, 10, 0)] = beak
    paint(head, 8, 10, 2, 10, 12, 3, eye)
    paint(head, 14, 10, 2, 16, 12, 3, eye)
    solid(wing_l, 2, 6, 6, 8, 8, 12, belly)
    solid(wing_r, 16, 6, 6, 22, 8, 12, belly)
    for z in (6, 8, 10):
        wing_l[(0, 6, z)] = belly
        wing_l[(0, 7, z)] = belly
        wing_l[(1, 7, z + 1)] = belly
        wing_r[(22, 6, z)] = belly
        wing_r[(23, 7, z)] = belly
        wing_r[(22, 7, z + 1)] = belly
    solid(tail, 10, 6, 14, 14, 8, 18, belly)
    tail[(8, 7, 18)] = belly
    tail[(15, 7, 18)] = belly
    tail[(10, 6, 19)] = belly
    tail[(13, 6, 19)] = belly
    solid(leg_l, 8, 0, 8, 10, 4, 10, beak)
    solid(leg_r, 14, 0, 8, 16, 4, 10, beak)
    leg_l[(8, 0, 7)] = beak
    leg_l[(9, 0, 7)] = beak
    leg_r[(14, 0, 7)] = beak
    leg_r[(15, 0, 7)] = beak
    if wisp:
        crystal, pupil, foot = 0, 1, 2
        merged = {}
        for src in (body, tail):
            for pos in src:
                merged[pos] = crystal
        head_c = {}
        for pos, mat in head.items():
            head_c[pos] = pupil if mat == eye else crystal
        wings_l = {pos: crystal for pos in wing_l}
        wings_r = {pos: crystal for pos in wing_r}
        legs_l = {pos: foot for pos in leg_l}
        legs_r = {pos: foot for pos in leg_r}
        parts = {
            "body": merged,
            "head": head_c,
            "leg_l": legs_l,
            "leg_r": legs_r,
            "wing_l": wings_l,
            "wing_r": wings_r,
        }
        return parts, WISP
    parts = {
        "body": body,
        "head": head,
        "leg_l": leg_l,
        "leg_r": leg_r,
        "wing_l": wing_l,
        "wing_r": wing_r,
        "tail": tail,
    }
    return parts, BIRD


def bounds(parts):
    xs, ys, zs = [], [], []
    for cells in parts.values():
        for x, y, z in cells:
            xs.append(x)
            ys.append(y)
            zs.append(z)
    return max(xs) + 1, max(ys) + 1, max(zs) + 1, min(xs)


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
                n[axis] += sign if sign < 0 else 1
                if sign < 0:
                    n[axis] = p[axis] - 1
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


def audit(name, parts):
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
    for part, cells in parts.items():
        dist = {}
        queue = []
        for (x, y, z) in cells:
            exposed = False
            for d in neigh:
                if (x + d[0], y + d[1], z + d[2]) not in cells:
                    exposed = True
                    break
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
    return {"overlap": overlap, "deep": deep, "detail": detail, "detail_buried": detail_buried}


def dump(name, parts, palette):
    sx, sy, sz, min_x = bounds(parts)
    order = [k for k in ("body", "head", "leg_l", "leg_r", "wing_l", "wing_r", "tail") if k in parts]
    packed = {}
    voxels = 0
    for key in order:
        cells = []
        for (x, y, z), mat in sorted(parts[key].items()):
            cells.append([x, y, z, mat])
        packed[key] = cells
        voxels += len(cells)
    pivot_x = (min_x + sx - 1) // 2
    doc = {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": [sx, sy, sz],
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": [pivot_x, 0, 0],
        "palette": palette,
        "parts": packed,
    }
    path = os.path.join(OUT, name + ".json")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, separators=(",", ":"))
        f.write("\n")
    part_quads = {key: quad_count(parts[key]) for key in order}
    full = quad_count(merged(parts))
    info = {
        "voxels": voxels,
        "quads": full,
        "part_quads": sum(part_quads.values()),
        "parts": {key: len(packed[key]) for key in order},
        "quads_by_part": part_quads,
        "blocks_tall": round(sy / 16.0, 3),
        "audit": audit(name, parts),
    }
    return info


def old_fill(parts, name, x0, y0, z0, x1, y1, z1, mat):
    dst = parts.setdefault(name, {})
    for z in range(z0, z1):
        for y in range(y0, y1):
            for x in range(x0, x1):
                dst[(x, y, z)] = mat


def old_models():
    out = {}
    deer_p = {}
    old_fill(deer_p, "body", 3, 5, 5, 7, 9, 12, 1)
    old_fill(deer_p, "body", 3, 5, 6, 7, 6, 11, 2)
    old_fill(deer_p, "head", 3, 8, 1, 7, 12, 5, 1)
    old_fill(deer_p, "head", 4, 8, 0, 6, 10, 2, 1)
    old_fill(deer_p, "head", 3, 10, 1, 4, 11, 2, 4)
    old_fill(deer_p, "head", 6, 10, 1, 7, 11, 2, 4)
    old_fill(deer_p, "head", 3, 12, 2, 4, 15, 3, 3)
    old_fill(deer_p, "head", 6, 12, 2, 7, 15, 3, 3)
    old_fill(deer_p, "leg_l", 2, 1, 5, 4, 5, 7, 1)
    old_fill(deer_p, "leg_l", 2, 0, 5, 4, 1, 7, 3)
    old_fill(deer_p, "leg_l", 2, 1, 9, 4, 5, 11, 1)
    old_fill(deer_p, "leg_l", 2, 0, 9, 4, 1, 11, 3)
    old_fill(deer_p, "leg_r", 6, 1, 5, 8, 5, 7, 1)
    old_fill(deer_p, "leg_r", 6, 0, 5, 8, 1, 7, 3)
    old_fill(deer_p, "leg_r", 6, 1, 9, 8, 5, 11, 1)
    old_fill(deer_p, "leg_r", 6, 0, 9, 8, 1, 11, 3)
    old_fill(deer_p, "tail", 4, 8, 12, 6, 9, 14, 2)
    out["deer"] = deer_p
    boar_p = {}
    old_fill(boar_p, "body", 2, 3, 4, 8, 7, 11, 1)
    old_fill(boar_p, "body", 3, 3, 5, 7, 4, 10, 2)
    old_fill(boar_p, "head", 3, 4, 0, 7, 7, 4, 1)
    old_fill(boar_p, "head", 4, 4, 0, 6, 5, 2, 3)
    old_fill(boar_p, "head", 3, 6, 1, 4, 7, 2, 4)
    old_fill(boar_p, "head", 6, 6, 1, 7, 7, 2, 4)
    old_fill(boar_p, "leg_l", 1, 1, 4, 3, 3, 6, 1)
    old_fill(boar_p, "leg_l", 1, 0, 4, 3, 1, 6, 3)
    old_fill(boar_p, "leg_l", 1, 1, 8, 3, 3, 10, 1)
    old_fill(boar_p, "leg_l", 1, 0, 8, 3, 1, 10, 3)
    old_fill(boar_p, "leg_r", 7, 1, 4, 9, 3, 6, 1)
    old_fill(boar_p, "leg_r", 7, 0, 4, 9, 1, 6, 3)
    old_fill(boar_p, "leg_r", 7, 1, 8, 9, 3, 10, 1)
    old_fill(boar_p, "leg_r", 7, 0, 8, 9, 1, 10, 3)
    old_fill(boar_p, "tail", 4, 6, 11, 6, 7, 14, 1)
    out["boar"] = boar_p
    rabbit_p = {}
    old_fill(rabbit_p, "body", 3, 2, 4, 7, 5, 9, 1)
    old_fill(rabbit_p, "body", 3, 2, 5, 7, 3, 8, 2)
    old_fill(rabbit_p, "head", 3, 4, 1, 7, 7, 4, 1)
    old_fill(rabbit_p, "head", 3, 7, 2, 4, 11, 3, 3)
    old_fill(rabbit_p, "head", 6, 7, 2, 7, 11, 3, 3)
    old_fill(rabbit_p, "head", 3, 5, 1, 4, 6, 2, 4)
    old_fill(rabbit_p, "head", 6, 5, 1, 7, 6, 2, 4)
    old_fill(rabbit_p, "leg_l", 2, 0, 4, 4, 2, 6, 1)
    old_fill(rabbit_p, "leg_l", 2, 0, 7, 4, 2, 9, 1)
    old_fill(rabbit_p, "leg_r", 6, 0, 4, 8, 2, 6, 1)
    old_fill(rabbit_p, "leg_r", 6, 0, 7, 8, 2, 9, 1)
    old_fill(rabbit_p, "tail", 4, 4, 9, 6, 6, 11, 2)
    out["rabbit"] = rabbit_p
    bird_p = {}
    old_fill(bird_p, "body", 4, 2, 4, 7, 5, 9, 1)
    old_fill(bird_p, "body", 4, 2, 5, 7, 3, 8, 2)
    old_fill(bird_p, "head", 4, 4, 1, 7, 7, 4, 1)
    old_fill(bird_p, "head", 5, 4, 0, 6, 5, 1, 3)
    old_fill(bird_p, "head", 4, 5, 1, 5, 6, 2, 4)
    old_fill(bird_p, "head", 6, 5, 1, 7, 6, 2, 4)
    old_fill(bird_p, "leg_l", 4, 0, 5, 5, 2, 6, 3)
    old_fill(bird_p, "leg_l", 4, 0, 7, 5, 2, 8, 3)
    old_fill(bird_p, "leg_r", 6, 0, 5, 7, 2, 6, 3)
    old_fill(bird_p, "leg_r", 6, 0, 7, 7, 2, 8, 3)
    old_fill(bird_p, "wing_l", 0, 3, 4, 4, 4, 8, 2)
    old_fill(bird_p, "wing_r", 7, 3, 4, 11, 4, 8, 2)
    old_fill(bird_p, "tail", 5, 3, 9, 6, 4, 12, 2)
    out["bird"] = bird_p
    out["crystal_stag"] = deer_p
    out["corrupted_beast"] = boar_p
    wisp = {}
    old_fill(wisp, "body", 3, 2, 3, 7, 5, 8, 1)
    old_fill(wisp, "head", 3, 5, 1, 7, 8, 4, 1)
    old_fill(wisp, "head", 3, 6, 1, 4, 7, 2, 2)
    old_fill(wisp, "head", 6, 6, 1, 7, 7, 2, 2)
    old_fill(wisp, "head", 4, 5, 0, 6, 6, 1, 2)
    old_fill(wisp, "leg_l", 3, 0, 4, 4, 2, 6, 1)
    old_fill(wisp, "leg_l", 3, 0, 6, 4, 2, 8, 1)
    old_fill(wisp, "leg_r", 6, 0, 4, 7, 2, 6, 1)
    old_fill(wisp, "leg_r", 6, 0, 6, 7, 2, 8, 1)
    old_fill(wisp, "wing_l", 0, 4, 3, 3, 5, 7, 1)
    old_fill(wisp, "wing_r", 7, 4, 3, 10, 5, 7, 1)
    out["crystal_wisp"] = wisp
    before = {}
    for name, parts in out.items():
        before[name] = {
            "voxels": sum(len(c) for c in parts.values()),
            "quads": quad_count(merged(parts)),
            "part_quads": sum(quad_count(c) for c in parts.values()),
        }
    return before


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


def preview(models):
    cell = 3
    pad = 8
    cols = 4
    rows = 2
    mw = 28
    mh = 36
    tile_w = mw * cell + pad * 2
    tile_h = mh * cell + pad * 2
    width = cols * tile_w
    height = rows * tile_h
    buf = bytearray([32, 36, 42]) * (width * height)
    names = list(models.keys())
    for i, name in enumerate(names):
        parts, palette = models[name]
        col = i % cols
        row = i // cols
        ox = col * tile_w + pad
        oy = row * tile_h + pad
        occ = {}
        for cells in parts.values():
            for (x, y, z), mat in cells.items():
                key = (x, y)
                if key not in occ or z < occ[key][0]:
                    occ[key] = (z, mat)
        for (x, y), (_z, mat) in occ.items():
            color = palette[mat]
            for py in range(cell):
                for px in range(cell):
                    sx = ox + x * cell + px
                    sy = oy + (mh - 1 - y) * cell + py
                    if sx < 0 or sy < 0 or sx >= width or sy >= height:
                        continue
                    i0 = (sy * width + sx) * 3
                    buf[i0] = color[0]
                    buf[i0 + 1] = color[1]
                    buf[i0 + 2] = color[2]
    png(os.path.join(OUT, "animals_preview.png"), width, height, buf)


def main():
    models = {
        "deer": deer(False),
        "crystal_stag": deer(True),
        "boar": boar(False),
        "corrupted_beast": boar(True),
        "rabbit": rabbit(),
        "bird": bird(False),
        "crystal_wisp": bird(True),
    }
    before = old_models()
    stats_path = os.path.join(OUT, "stats.json")
    with open(stats_path, encoding="utf-8") as f:
        stats = json.load(f)
    report = {}
    failed = False
    for name, (parts, palette) in models.items():
        info = dump(name, parts, palette)
        report[name] = info
        flag = "OK"
        if info["part_quads"] > 3000 or info["quads"] > 3000 or info["audit"]["overlap"] or info["audit"]["deep"] or info["audit"]["detail_buried"]:
            flag = "FAIL"
            failed = True
        if len(palette) > 16:
            flag = "FAIL"
            failed = True
        print(
            "%s %s voxels=%d quads=%d part_quads=%d before_quads=%d %s"
            % (flag, name, info["voxels"], info["quads"], info["part_quads"], before[name]["part_quads"], info["audit"])
        )
    stats["animals_before"] = before
    stats["animals"] = {k: {kk: vv for kk, vv in info.items() if kk != "quads_by_part"} for k, info in report.items()}
    stats["profile"] = "quads at authored occupancy; crystal load unchanged (no extra terrain or per-voxel nodes)"
    with open(stats_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(stats, f, indent=2)
        f.write("\n")
    preview(models)
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
