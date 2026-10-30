#!/usr/bin/env python3
"""Thin reference trees to the vegetation quad budget and author small plants."""

import json
import os
from collections import Counter, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
VEG = os.path.join(ROOT, "assets", "voxel", "vegetation")
OUT = os.path.join(VEG, "lod")
SRC = {
    "oak": os.path.join(VEG, "tree_oak.json"),
    "birch": os.path.join(VEG, "tree_birch.json"),
    "pine": os.path.join(VEG, "tree_pine.json"),
}
PALETTE_PATH = os.path.join(ROOT, "assets", "voxel", "palette.json")
TREE_BUDGET = 4800
PLANT_BUDGET = 280
NEIGH = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))
DIRS = (
    (0, 1, (1, 0, 0)),
    (0, -1, (-1, 0, 0)),
    (1, 1, (0, 1, 0)),
    (1, -1, (0, -1, 0)),
    (2, 1, (0, 0, 1)),
    (2, -1, (0, 0, -1)),
)


def load_palette():
    data = json.load(open(PALETTE_PATH, encoding="utf-8"))
    named = {}
    for entry in data["colors"]:
        named[entry["name"]] = tuple(entry["rgb"])
    return named


def quads_for(cells):
    if not cells:
        return 0
    occ = set(cells)
    groups = defaultdict(list)
    for (x, y, z), mat in cells.items():
        for axis, sign, (dx, dy, dz) in DIRS:
            if (x + dx, y + dy, z + dz) in occ:
                continue
            if axis == 0:
                w, u, v = x, y, z
            elif axis == 1:
                w, u, v = y, z, x
            else:
                w, u, v = z, x, y
            groups[(axis, sign, w, mat)].append((u, v))
    total = 0
    for pts in groups.values():
        total += _greedy(pts)
    return total


def _greedy(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    du = maxx - minx + 1
    dv = maxy - miny + 1
    mask = [0] * (du * dv)
    for u, v in pts:
        mask[(u - minx) + du * (v - miny)] = 1
    count = 0
    v = 0
    while v < dv:
        u = 0
        while u < du:
            if mask[u + du * v] == 0:
                u += 1
                continue
            wu = 1
            while u + wu < du and mask[u + wu + du * v] == 1:
                wu += 1
            wv = 1
            while v + wv < dv:
                row = v + wv
                if any(mask[u + k + du * row] != 1 for k in range(wu)):
                    break
                wv += 1
            for yy in range(wv):
                base = du * (v + yy)
                for xx in range(wu):
                    mask[u + xx + base] = 0
            count += 1
            u += wu
        v += 1
    return count


def self_test():
    one = {(0, 0, 0): 1}
    pair = {(0, 0, 0): 1, (1, 0, 0): 1}
    block = {(x, y, z): 1 for x in range(2) for y in range(2) for z in range(2)}
    split = {(0, 0, 0): 1, (1, 0, 0): 2}
    assert quads_for(one) == 6, quads_for(one)
    assert quads_for(pair) == 6, quads_for(pair)
    assert quads_for(block) == 6, quads_for(block)
    assert quads_for(split) == 10, quads_for(split)


def load_tree(path):
    data = json.load(open(path, encoding="utf-8"))
    cells = {}
    for part, arr in data["parts"].items():
        for x, y, z, idx in arr:
            cells[(int(x), int(y), int(z))] = (str(part), int(idx))
    return data, cells


def base_cells(cells):
    grouped = defaultdict(list)
    for p, payload in cells.items():
        origin = (p[0] // 2 * 2, p[1] // 2 * 2, p[2] // 2 * 2)
        grouped[origin].append(p)
    kept = {}
    for origin, members in grouped.items():
        if len(members) < 4:
            continue
        votes = Counter(cells[p] for p in members)
        maj = votes.most_common(1)[0][0]
        ox, oy, oz = origin
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    kept[(ox + dx, oy + dy, oz + dz)] = maj
    return kept


BIN_NEIGH = ((2, 0, 0), (-2, 0, 0), (0, 2, 0), (0, -2, 0), (0, 0, 2), (0, 0, -2))


def _band_mat(part, y, lo, span, palette_len):
    if part == "trunk":
        mat = 3 if y < lo + span * 0.5 else 1
    else:
        t = (y - lo) / span
        mat = 4 if t < 0.33 else (6 if t < 0.66 else 8)
    if mat >= palette_len:
        mat = min(4, palette_len - 1)
    return mat


def simplify_shell(cells, palette_len):
    base = base_cells(cells)
    bins = {}
    for p, payload in base.items():
        origin = (p[0] // 2 * 2, p[1] // 2 * 2, p[2] // 2 * 2)
        bins.setdefault(origin, payload)
    occupied = set(bins)

    def neighbors(origin, group):
        return sum((origin[0] + d[0], origin[1] + d[1], origin[2] + d[2]) in group for d in BIN_NEIGH)

    keep = {origin for origin in occupied if bins[origin][0] == "trunk" or neighbors(origin, occupied) >= 3}
    keep = {origin for origin in keep if bins[origin][0] == "trunk" or neighbors(origin, keep) >= 2}
    heights = [origin[1] for origin in keep if bins[origin][0] != "trunk"]
    if not heights:
        heights = [0]
    lo = min(heights)
    span = max(1, max(heights) - lo)
    shell = {}
    for origin in keep:
        part, _idx = bins[origin]
        mat = _band_mat(part, origin[1], lo, span, palette_len)
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    shell[(origin[0] + dx, origin[1] + dy, origin[2] + dz)] = (part, mat)
    return shell


def exposed_score(p, occ):
    return sum(1 for d in NEIGH if (p[0] + d[0], p[1] + d[1], p[2] + d[2]) not in occ)


def add_edge_detail(original, shell, palette_len):
    base_quads = quads_for({p: payload[1] for p, payload in shell.items()})
    if base_quads >= TREE_BUDGET - 24:
        return dict(shell), base_quads
    occ = set(shell)
    accent = 11 if palette_len > 11 else min(8, palette_len - 1)
    cand = []
    for p, payload in original.items():
        if p in shell or payload[0] != "canopy":
            continue
        if not any((p[0] + d[0], p[1] + d[1], p[2] + d[2]) in occ for d in NEIGH):
            continue
        score = exposed_score(p, occ)
        if score < 4:
            continue
        cand.append((score, p))
    cand.sort(key=lambda item: (-item[0], item[1]))
    take = min(len(cand), max(0, (TREE_BUDGET - base_quads) // 5))
    merged = dict(shell)
    for _score, p in cand[:take]:
        merged[p] = ("canopy", accent)
    q = quads_for({p: payload[1] for p, payload in merged.items()})
    detail_keys = [p for _score, p in cand[:take]]
    while q > TREE_BUDGET and detail_keys:
        drop = detail_keys[: max(1, len(detail_keys) // 2)]
        detail_keys = detail_keys[len(drop):]
        for key in drop:
            merged.pop(key, None)
        q = quads_for({p: payload[1] for p, payload in merged.items()})
    return merged, q


def crop_stage(cells, stage):
    if stage >= 2 or not cells:
        return dict(cells)
    ymax = max(p[1] for p in cells)
    frac = 0.40 if stage == 0 else 0.68
    limit = max(8, int(ymax * frac))
    out = {p: payload for p, payload in cells.items() if p[1] <= limit}
    if not any(payload[0] == "trunk" for payload in out.values()):
        trunks = [p for p, payload in cells.items() if payload[0] == "trunk"]
        trunks.sort(key=lambda p: p[1])
        for p in trunks[:24]:
            out[p] = cells[p]
    if not any(payload[0] == "canopy" for payload in out.values()):
        tops = [p for p in out if out[p][0] == "trunk"]
        tops.sort(key=lambda p: -p[1])
        leaf = 4
        for src in cells.values():
            if src[0] == "canopy":
                leaf = src[1]
                break
        for p in tops[:12]:
            cap = (p[0], p[1] + 2, p[2])
            if cap not in out:
                out[cap] = ("canopy", leaf)
    return out


def mirror_axis(cells, size, pivot, axis):
    span = int(size[axis]) - 1
    out = {}
    for p, payload in cells.items():
        q = [p[0], p[1], p[2]]
        q[axis] = span - q[axis]
        out[tuple(q)] = payload
    new_pivot = [pivot[0], pivot[1], pivot[2]]
    new_pivot[axis] = span - pivot[axis]
    return out, new_pivot


def write_model(path, name, size, pivot, palette, cells):
    parts = {"trunk": [], "canopy": []} if any(v[0] in ("trunk", "canopy") for v in cells.values()) else {"body": []}
    for (x, y, z), (part, idx) in cells.items():
        key = part if part in parts else "body"
        if key not in parts:
            parts[key] = []
        parts[key].append([int(x), int(y), int(z), int(idx)])
    for key in list(parts.keys()):
        parts[key].sort()
        if not parts[key]:
            parts.pop(key)
    if "trunk" in parts and "canopy" not in parts:
        parts["canopy"] = [parts["trunk"][0][:]]
    if "canopy" in parts and "trunk" not in parts:
        parts["trunk"] = [parts["canopy"][0][:]]
    payload = {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": [int(size[0]), int(size[1]), int(size[2])],
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": [float(pivot[0]), float(pivot[1]), float(pivot[2])],
        "palette": palette,
        "parts": parts,
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))
    return {key: len(items) for key, items in parts.items()}


def bounds_of(cells, fallback):
    if not cells:
        return fallback
    maxes = [0, 0, 0]
    for p in cells:
        for axis in range(3):
            maxes[axis] = max(maxes[axis], p[axis] + 1)
    return maxes


def build_trees():
    stats = []
    for species, path in SRC.items():
        data, cells = load_tree(path)
        palette = data["palette"]
        shell = simplify_shell(cells, len(palette))
        lod1_q = quads_for({p: payload[1] for p, payload in shell.items()})
        lod0, lod0_q = add_edge_detail(cells, shell, len(palette))
        print(
            "TREE %s src=%d shell_voxels=%d lod0_voxels=%d lod0_quads=%d lod1_quads=%d"
            % (species, len(cells), len(shell), len(lod0), lod0_q, lod1_q)
        )
        if lod0_q > 5000 or lod1_q > 5000:
            raise SystemExit("tree %s over budget lod0=%d lod1=%d" % (species, lod0_q, lod1_q))
        size = data["size"]
        pivot = data["pivot"]
        for lod, mesh_cells, q in ((0, lod0, lod0_q), (1, shell, lod1_q)):
            for stage in (0, 1, 2):
                staged = crop_stage(mesh_cells, stage)
                variants = [(0, staged, pivot)]
                stage_q = q if stage >= 2 else quads_for({p: payload[1] for p, payload in staged.items()})
                if stage_q > 5000:
                    raise SystemExit("tree %s stage %d lod %d quads %d" % (species, stage, lod, stage_q))
                for variant, vcells, vpivot in variants:
                    name = "tree_%s_v%d_s%d_lod%d" % (species, variant, stage, lod)
                    file_name = name + ".json"
                    write_model(
                        os.path.join(OUT, file_name),
                        name,
                        size,
                        vpivot,
                        palette,
                        vcells,
                    )
                    stats.append({
                        "file": "lod/" + file_name,
                        "name": name,
                        "kind": "tree",
                        "species": species,
                        "variant": variant,
                        "stage": stage,
                        "lod": lod,
                        "voxels": len(vcells),
                        "quads": stage_q if variant == 0 else stage_q,
                    })
                print("  stage %d lod %d voxels=%d quads=%d" % (stage, lod, len(staged), stage_q))
    return stats


def cube(cells, x, y, z, mat):
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                cells[(x + dx, y + dy, z + dz)] = ("body", mat)


def plant_model(name, cells, palette):
    size = bounds_of(cells, [2, 2, 2])
    for axis in range(3):
        size[axis] = max(size[axis], 2)
    q = quads_for({p: payload[1] for p, payload in cells.items()})
    if q > PLANT_BUDGET:
        raise SystemExit("plant %s quads %d" % (name, q))
    pivot = [size[0] // 2, 0, size[2] // 2]
    path = os.path.join(OUT, name + ".json")
    write_model(path, name, size, pivot, palette, cells)
    return {"file": "lod/" + name + ".json", "name": name, "kind": "plant", "voxels": len(cells), "quads": q, "lod": 0}


def shift_cells(cells, dx, dy, dz):
    return {(p[0] + dx, p[1] + dy, p[2] + dz): v for p, v in cells.items()}


def grass_cells(blades, height, lean):
    cells = {}
    for i, (ox, oz) in enumerate(blades):
        mat = 1 if i == 1 else (2 if i == 2 else 0)
        for step in range(height):
            y = step * 2
            x = ox + (lean if step > height // 2 else 0)
            cube(cells, x, y, oz, mat)
    return shift_cells(cells, 8, 0, 8)


def fern_cells(reach, lift):
    cells = {}
    arms = ((2, 0, 0), (-2, 0, 0), (0, 0, 2), (0, 0, -2))
    for i, (dx, _dy, dz) in enumerate(arms):
        mat = i % 3
        x, z = 0, 0
        for step in range(reach):
            x += dx
            z += dz
            y = step * 2 + lift
            cube(cells, x, y, z, mat)
            if step == reach - 1:
                cube(cells, x + (1 if dx >= 0 else -1), y + 2, z, 3)
    return shift_cells(cells, 16, 0, 16)


def bush_cells(radius):
    cells = {}
    r2 = radius * radius
    inner = max(0, radius - 2)
    inner2 = inner * inner
    for y in range(0, radius + 1):
        for x in range(-radius, radius + 1):
            for z in range(-radius, radius + 1):
                if (x % 2) or (y % 2) or (z % 2):
                    continue
                cy = y - radius // 3
                d2 = x * x + cy * cy + z * z
                if d2 > r2 or d2 < inner2:
                    continue
                mat = 1 if y > radius // 2 else 0
                cube(cells, x, y, z, mat)
    for x, z, mat in ((radius, 0, 2), (-radius, 1, 2), (0, radius, 3), (1, -radius, 3)):
        cells[(x, radius, z)] = ("body", mat)
    return shift_cells(cells, radius + 2, 0, radius + 2)


def flower_cells(spread, bud):
    cells = {}
    stem_h = 3 if bud else 6
    for step in range(stem_h):
        cube(cells, 0, step * 2, 0, 0)
    top = stem_h * 2
    if bud:
        cube(cells, 0, top, 0, 1)
    else:
        petals = ((spread, 0), (-spread, 0), (0, spread), (0, -spread))
        for px, pz in petals:
            cells[(px, top + 1, pz)] = ("body", 1)
            if spread > 2:
                cells[(px // 2, top, pz // 2)] = ("body", 1)
        cube(cells, -1, top, -1, 2)
    return shift_cells(cells, 8, 0, 8)


def reed_cells(stalks):
    cells = {}
    spots = ((0, 0), (4, 2), (-4, -2), (2, -4))
    for i in range(stalks):
        ox, oz = spots[i]
        height = 8 + (i % 2)
        for step in range(height):
            cube(cells, ox, step * 2, oz, 0 if i != 1 else 1)
        cube(cells, ox, height * 2, oz, 2)
    return shift_cells(cells, 8, 0, 8)


def mushroom_cells(cap_r, spots):
    cells = {}
    for step in range(4):
        cube(cells, 0, step * 2, 0, 0)
    top = 8
    for x in range(-cap_r, cap_r + 1):
        for z in range(-cap_r, cap_r + 1):
            if (x % 2) or (z % 2):
                continue
            if x * x + z * z > cap_r * cap_r:
                continue
            cube(cells, x, top, z, 1)
            if x * x + z * z > (cap_r - 2) * (cap_r - 2):
                cells[(x + cap_r, top + 3, z)] = ("body", 1)
    for sx, sz in spots:
        cells[(sx, top + 3, sz)] = ("body", 2)
    return shift_cells(cells, cap_r + 2, 0, cap_r + 2)


def build_plants(named):
    leaf = [list(named["oak_leaf_4"]), list(named["oak_leaf_6"]), list(named["oak_leaf_8"]), list(named["oak_leaf_10"])]
    stem = [list(named["oak_leaf_5"]), list(named["oak_bark_1"]), list(named["birch_bark_1"])]
    stats = []
    layouts = {
        0: [(-4, 0), (2, 2), (0, -4)],
        1: [(-2, 2), (4, 0), (-2, -2)],
        2: [(0, 2), (4, -2), (-4, -2)],
    }
    for variant, blades in layouts.items():
        for stage, height in ((0, 3), (1, 5)):
            cells = grass_cells(blades, height, 2 if variant != 2 else -2)
            stats.append(plant_model("grass_tuft_v%d_s%d" % (variant, stage), cells, leaf))
            tall = grass_cells(blades, height + 3, 2 if variant == 0 else -2)
            stats.append(plant_model("tall_grass_v%d_s%d" % (variant, stage), tall, leaf))
    for variant, reach in ((0, 4), (1, 5), (2, 3)):
        for stage, lift in ((0, 0), (1, 2)):
            cells = fern_cells(reach if stage == 1 else max(2, reach - 2), 0 if stage == 1 else 0)
            stats.append(plant_model("fern_v%d_s%d" % (variant, stage), cells, leaf))
    for variant, radius in ((0, 6), (1, 7), (2, 5)):
        for stage, scale in ((0, 0), (1, 1), (2, 2)):
            used = max(3, radius - (2 - scale))
            cells = bush_cells(used)
            stats.append(plant_model("bush_v%d_s%d" % (variant, stage), cells, leaf))
    petals = {
        "red": [list(named["oak_leaf_5"]), list(named["flower_red"]), list(named["oak_leaf_12"])],
        "yellow": [list(named["oak_leaf_5"]), list(named["flower_yellow"]), list(named["oak_bark_1"])],
        "blue": [list(named["oak_leaf_5"]), list(named["flower_blue"]), list(named["oak_leaf_12"])],
        "white": [list(named["oak_leaf_5"]), list(named["birch_bark_1"]), list(named["oak_leaf_12"])],
    }
    for color, palette in petals.items():
        for variant, spread in ((0, 3), (1, 4), (2, 2)):
            for stage in (0, 1):
                cells = flower_cells(spread, stage == 0)
                stats.append(plant_model("flower_%s_v%d_s%d" % (color, variant, stage), cells, palette))
    for variant, stalks in ((0, 3), (1, 4), (2, 2)):
        for stage in (0, 1):
            cells = reed_cells(stalks if stage == 1 else max(2, stalks - 1))
            if stage == 0:
                cells = {p: v for p, v in cells.items() if p[1] <= 10}
            stats.append(plant_model("reeds_v%d_s%d" % (variant, stage), cells, stem))
    cap = [list(named["birch_bark_3"]), list(named["flower_red"]), list(named["birch_bark_1"])]
    for variant, (radius, spots) in enumerate((
        (4, ((1, 0), (-2, 2))),
        (5, ((2, 1), (0, -2), (-2, 0))),
        (3, ((1, 1),)),
    )):
        for stage in (0, 1):
            used = radius if stage == 1 else max(2, radius - 2)
            cells = mushroom_cells(used, spots if stage == 1 else spots[:1])
            stats.append(plant_model("mushroom_v%d_s%d" % (variant, stage), cells, cap))
    return stats


def main():
    self_test()
    os.makedirs(OUT, exist_ok=True)
    named = load_palette()
    stats = build_trees()
    stats.extend(build_plants(named))
    worst_tree = max((row["quads"] for row in stats if row["kind"] == "tree"), default=0)
    worst_plant = max((row["quads"] for row in stats if row["kind"] == "plant"), default=0)
    report = {
        "budget_tree_lod0": 5000,
        "budget_plant": 300,
        "python_quads": True,
        "before_box_quads": {"tree": 18, "bush": 18, "grass_tuft": 24},
        "worst_tree_quads": worst_tree,
        "worst_plant_quads": worst_plant,
        "models": stats,
    }
    with open(os.path.join(VEG, "stats.json"), "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
    print("WROTE models=%d worst_tree=%d worst_plant=%d" % (len(stats), worst_tree, worst_plant))


if __name__ == "__main__":
    main()
