"""Author crystalstorm-voxel-v1 player and crystal mite models.

Base cubes are 2 cells (8 per terrain block). 1-cell cubes sit only on
silhouettes. Interiors of the thick masses are empty. One shared palette,
no per-voxel colour noise.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "voxel" / "entities"

SKIN = 0
HAIR = 1
TUNIC = 2
BELT = 3
BOOT = 4
EYE = 5
CRYSTAL = 0
DARK = 1

PLAYER_PALETTE = [
    [219, 158, 107],
    [71, 41, 26],
    [56, 107, 87],
    [107, 71, 36],
    [51, 36, 26],
    [20, 20, 26],
]
MITE_PALETTE = [
    [184, 71, 255],
    [20, 20, 26],
]


def fill_base(part, x0, y0, z0, x1, y1, z1, mat):
    for z in range(z0, z1, 2):
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                for dz in (0, 1):
                    for dy in (0, 1):
                        for dx in (0, 1):
                            part[(x + dx, y + dy, z + dz)] = mat


def hollow_base(part):
    bases = {}
    for (x, y, z), mat in part.items():
        bases.setdefault((x // 2, y // 2, z // 2), mat)
    keep = set()
    for bx, by, bz in bases:
        exposed = False
        for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            if (bx + dx, by + dy, bz + dz) not in bases:
                exposed = True
                break
        if exposed:
            keep.add((bx, by, bz))
    out = {}
    for (x, y, z), mat in part.items():
        if (x // 2, y // 2, z // 2) in keep:
            out[(x, y, z)] = mat
    return out


def put(part, x, y, z, mat):
    part[(x, y, z)] = mat


def greedy_quads(cells):
    if not cells:
        return 0
    occ = set(cells)
    quads = 0
    for axis in range(3):
        for sign in (-1, 1):
            faces = {}
            for x, y, z in occ:
                coord = [x, y, z]
                coord[axis] += sign
                if tuple(coord) in occ:
                    continue
                w = (x, y, z)[axis]
                u = (x, y, z)[(axis + 1) % 3]
                v = (x, y, z)[(axis + 2) % 3]
                faces.setdefault(w, {})[(u, v)] = cells[(x, y, z)]
            for mask in faces.values():
                pending = dict(mask)
                while pending:
                    (u, v), mat = next(iter(pending.items()))
                    wu = 1
                    while (u + wu, v) in pending and pending[(u + wu, v)] == mat:
                        wu += 1
                    wv = 1
                    while True:
                        if not all((u + k, v + wv) in pending and pending[(u + k, v + wv)] == mat for k in range(wu)):
                            break
                        wv += 1
                    for dv in range(wv):
                        for du in range(wu):
                            del pending[(u + du, v + dv)]
                    quads += 1
    return quads


def pack(name, size, pivot, palette, parts):
    listed = {}
    total = 0
    quads = 0
    part_quads = {}
    for key, cells in parts.items():
        rows = [[x, y, z, mat] for (x, y, z), mat in sorted(cells.items())]
        listed[key] = rows
        total += len(rows)
        part_quads[key] = greedy_quads(cells)
        quads += part_quads[key]
    doc = {
        "format": "crystalstorm-voxel-v1",
        "name": name,
        "size": list(size),
        "vpb": 16,
        "base_cell": 2,
        "scale": "terrain_block",
        "pivot": list(pivot),
        "palette": palette,
        "parts": listed,
    }
    return doc, total, quads, part_quads


def build_player():
    torso = {}
    head = {}
    arm_l = {}
    fore_l = {}
    arm_r = {}
    fore_r = {}
    leg_l = {}
    leg_r = {}
    fill_base(torso, 2, 14, 0, 14, 24, 8, TUNIC)
    fill_base(torso, 2, 12, 0, 14, 14, 8, BELT)
    for z in range(0, 8):
        torso.pop((2, 22, z), None)
        torso.pop((2, 23, z), None)
        torso.pop((13, 22, z), None)
        torso.pop((13, 23, z), None)
    fill_base(head, 4, 24, 0, 12, 30, 8, SKIN)
    fill_base(head, 4, 30, 0, 12, 34, 8, HAIR)
    put(head, 6, 28, 7, EYE)
    put(head, 9, 28, 7, EYE)
    put(head, 7, 33, 7, HAIR)
    put(head, 8, 33, 6, HAIR)
    for x in (4, 11):
        head.pop((x, 33, 0), None)
    fill_base(arm_l, 0, 18, 2, 2, 24, 8, TUNIC)
    fill_base(fore_l, 0, 12, 2, 2, 18, 8, SKIN)
    fill_base(arm_r, 14, 18, 2, 16, 24, 8, TUNIC)
    fill_base(fore_r, 14, 12, 2, 16, 18, 8, SKIN)
    fill_base(leg_l, 4, 4, 2, 8, 12, 8, TUNIC)
    fill_base(leg_l, 4, 0, 2, 8, 4, 8, BOOT)
    fill_base(leg_r, 10, 4, 2, 14, 12, 8, TUNIC)
    fill_base(leg_r, 10, 0, 2, 14, 4, 8, BOOT)
    parts = {
        "torso": torso,
        "head": head,
        "upper_arm_l": arm_l,
        "lower_arm_l": fore_l,
        "upper_arm_r": arm_r,
        "lower_arm_r": fore_r,
        "leg_l": leg_l,
        "leg_r": leg_r,
    }
    return pack("player", (16, 34, 8), (8, 0, 4), PLAYER_PALETTE, parts)


def mite_hopper():
    body = {}
    head = {}
    leg_l = {}
    leg_r = {}
    tail = {}
    fill_base(body, 2, 2, 4, 10, 8, 12, CRYSTAL)
    body = hollow_base(body)
    for y, z in ((4, 6), (5, 6), (4, 7), (5, 8)):
        put(body, 0, y, z, CRYSTAL)
        put(body, 11, y, z, CRYSTAL)
    put(body, 1, 6, 7, CRYSTAL)
    put(body, 10, 6, 8, CRYSTAL)
    fill_base(head, 4, 6, 0, 10, 10, 4, CRYSTAL)
    head = hollow_base(head)
    put(head, 5, 8, 0, DARK)
    put(head, 8, 8, 0, DARK)
    put(head, 6, 7, 0, DARK)
    for x in (4, 8):
        put(head, x, 10, 1, CRYSTAL)
        put(head, x, 11, 1, CRYSTAL)
        put(head, x, 11, 2, CRYSTAL)
    for x in (2, 3):
        for z in (6, 9):
            put(leg_l, x, 0, z, CRYSTAL)
            put(leg_l, x, 1, z, CRYSTAL)
        put(leg_l, x, 0, 5, CRYSTAL)
    for x in (8, 9):
        for z in (6, 9):
            put(leg_r, x, 0, z, CRYSTAL)
            put(leg_r, x, 1, z, CRYSTAL)
        put(leg_r, x, 0, 5, CRYSTAL)
    fill_base(tail, 4, 3, 12, 8, 5, 14, CRYSTAL)
    put(tail, 5, 4, 14, CRYSTAL)
    put(tail, 6, 4, 15, CRYSTAL)
    put(tail, 6, 5, 14, CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return pack("crystal_mite", (12, 12, 16), (6, 0, 4), MITE_PALETTE, parts)


def mite_spike():
    body = {}
    head = {}
    leg_l = {}
    leg_r = {}
    tail = {}
    fill_base(body, 2, 2, 4, 10, 6, 12, CRYSTAL)
    body = hollow_base(body)
    for z in (5, 7, 9):
        put(body, 5, 6, z, CRYSTAL)
        put(body, 6, 7, z, CRYSTAL)
        put(body, 6, 8, z, CRYSTAL)
        put(body, 6, 9, z, CRYSTAL)
        put(body, 6, 10, z, CRYSTAL)
        put(body, 6, 11, z + 1, CRYSTAL)
    put(body, 0, 4, 7, CRYSTAL)
    put(body, 0, 5, 8, CRYSTAL)
    put(body, 11, 4, 7, CRYSTAL)
    put(body, 11, 5, 8, CRYSTAL)
    fill_base(head, 4, 4, 0, 8, 8, 4, CRYSTAL)
    head = hollow_base(head)
    put(head, 5, 6, 0, DARK)
    put(head, 7, 6, 0, DARK)
    put(head, 6, 8, 1, CRYSTAL)
    put(head, 6, 9, 1, CRYSTAL)
    put(head, 6, 10, 2, CRYSTAL)
    put(head, 6, 11, 2, CRYSTAL)
    for x, z in ((1, 6), (2, 6), (1, 9), (2, 9)):
        put(leg_l, x, 0, z, CRYSTAL)
        put(leg_l, x, 1, z, CRYSTAL)
    for x, z in ((8, 6), (9, 6), (8, 9), (9, 9)):
        put(leg_r, x, 0, z, CRYSTAL)
        put(leg_r, x, 1, z, CRYSTAL)
    put(tail, 5, 3, 12, CRYSTAL)
    put(tail, 6, 3, 12, CRYSTAL)
    put(tail, 5, 4, 13, CRYSTAL)
    put(tail, 6, 3, 14, CRYSTAL)
    put(tail, 6, 4, 15, CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return pack("crystal_mite_spike", (12, 12, 16), (6, 0, 4), MITE_PALETTE, parts)


def mite_shard():
    body = {}
    head = {}
    leg_l = {}
    leg_r = {}
    tail = {}
    fill_base(body, 2, 2, 4, 12, 6, 10, CRYSTAL)
    body = hollow_base(body)
    for x in range(3, 11):
        put(body, x, 6, 6, CRYSTAL)
        put(body, x, 6, 7, CRYSTAL)
    for x in range(4, 10):
        put(body, x, 7, 6, CRYSTAL)
        put(body, x, 7, 7, CRYSTAL)
    for x in (5, 6, 7, 8):
        put(body, x, 8, 6, CRYSTAL)
        put(body, x, 9, 7, CRYSTAL)
    put(body, 6, 10, 7, CRYSTAL)
    put(body, 7, 10, 6, CRYSTAL)
    put(body, 6, 11, 7, CRYSTAL)
    put(body, 0, 4, 6, CRYSTAL)
    put(body, 0, 5, 7, CRYSTAL)
    put(body, 1, 6, 8, CRYSTAL)
    fill_base(head, 4, 4, 0, 10, 8, 4, CRYSTAL)
    head = hollow_base(head)
    put(head, 5, 6, 0, DARK)
    put(head, 8, 6, 0, DARK)
    put(head, 6, 5, 0, DARK)
    put(head, 3, 7, 1, CRYSTAL)
    put(head, 10, 7, 1, CRYSTAL)
    put(head, 2, 6, 1, CRYSTAL)
    put(head, 11, 6, 1, CRYSTAL)
    for x, z in ((3, 5), (4, 5), (3, 8), (4, 8)):
        put(leg_l, x, 0, z, CRYSTAL)
        put(leg_l, x, 1, z, CRYSTAL)
    for x, z in ((8, 5), (9, 5), (8, 8), (9, 8)):
        put(leg_r, x, 0, z, CRYSTAL)
        put(leg_r, x, 1, z, CRYSTAL)
    fill_base(tail, 4, 3, 10, 8, 5, 12, CRYSTAL)
    put(tail, 5, 4, 12, CRYSTAL)
    put(tail, 6, 4, 13, CRYSTAL)
    put(tail, 6, 5, 14, CRYSTAL)
    put(tail, 6, 4, 15, CRYSTAL)
    parts = {"body": body, "head": head, "leg_l": leg_l, "leg_r": leg_r, "tail": tail}
    return pack("crystal_mite_shard", (14, 12, 16), (6, 0, 4), MITE_PALETTE, parts)


def old_player_quads():
    def box(part, x0, y0, z0, x1, y1, z1, mat):
        for z in range(z0, z1):
            for y in range(y0, y1):
                for x in range(x0, x1):
                    part[(x, y, z)] = mat
    torso, head, arm_l, arm_r, fore_l, fore_r, leg_l, leg_r = {}, {}, {}, {}, {}, {}, {}, {}
    box(torso, 1, 7, 0, 7, 12, 4, 1)
    box(torso, 1, 6, 0, 7, 7, 4, 2)
    box(head, 2, 15, 0, 6, 17, 4, 3)
    box(head, 2, 13, 0, 6, 15, 4, 4)
    box(head, 3, 14, 3, 5, 15, 4, 5)
    box(arm_l, 0, 9, 1, 2, 12, 3, 1)
    box(arm_r, 6, 9, 1, 8, 12, 3, 1)
    box(fore_l, 0, 7, 1, 2, 9, 3, 4)
    box(fore_r, 6, 7, 1, 8, 9, 3, 4)
    box(leg_l, 1, 2, 1, 3, 6, 3, 1)
    box(leg_l, 1, 0, 1, 3, 2, 3, 6)
    box(leg_r, 5, 2, 1, 7, 6, 3, 1)
    box(leg_r, 5, 0, 1, 7, 2, 3, 6)
    parts = [torso, head, arm_l, fore_l, arm_r, fore_r, leg_l, leg_r]
    return sum(greedy_quads(p) for p in parts), sum(len(p) for p in parts)


def old_mite_quads():
    def box(part, x0, y0, z0, x1, y1, z1):
        for z in range(z0, z1):
            for y in range(y0, y1):
                for x in range(x0, x1):
                    part[(x, y, z)] = 1
    body, head, leg_l, leg_r, tail = {}, {}, {}, {}, {}
    box(body, 1, 1, 2, 5, 3, 7)
    box(body, 0, 2, 4, 1, 5, 5)
    box(body, 5, 2, 4, 6, 5, 5)
    box(body, 2, 3, 3, 3, 7, 4)
    box(body, 3, 3, 5, 4, 6, 6)
    box(head, 2, 3, 0, 4, 5, 3)
    box(head, 1, 3, 0, 2, 4, 2)
    box(head, 4, 3, 0, 5, 4, 2)
    box(head, 2, 5, 1, 3, 8, 2)
    box(head, 3, 5, 1, 4, 8, 2)
    box(leg_l, 1, 0, 3, 2, 1, 4)
    box(leg_l, 1, 0, 5, 2, 1, 6)
    box(leg_r, 4, 0, 3, 5, 1, 4)
    box(leg_r, 4, 0, 5, 5, 1, 6)
    box(tail, 2, 2, 7, 4, 3, 9)
    box(tail, 2, 3, 8, 3, 6, 9)
    box(tail, 3, 2, 9, 4, 4, 12)
    parts = [body, head, leg_l, leg_r, tail]
    return sum(greedy_quads(p) for p in parts), sum(len(p) for p in parts)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    models = [build_player(), mite_hopper(), mite_spike(), mite_shard()]
    stats = {"before": {}, "models": {}}
    old_q, old_v = old_player_quads()
    mite_q, mite_v = old_mite_quads()
    stats["before"] = {
        "player": {"voxels": old_v, "quads": old_q},
        "crystal_mite": {"voxels": mite_v, "quads": mite_q},
    }
    for doc, voxels, quads, part_quads in models:
        path = OUT / ("%s.json" % doc["name"])
        path.write_text(json.dumps(doc, separators=(",", ":")), encoding="utf-8")
        stats["models"][doc["name"]] = {
            "voxels": voxels,
            "quads": quads,
            "parts": part_quads,
            "blocks_tall": round(doc["size"][1] / 16.0, 3),
        }
        print("%s voxels=%d quads=%d" % (doc["name"], voxels, quads))
    (OUT / "stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")
    player = stats["models"]["player"]
    assert player["quads"] <= 3000, player
    for name, row in stats["models"].items():
        assert row["quads"] <= 3000, name
    print("before player", stats["before"]["player"], "mite", stats["before"]["crystal_mite"])


if __name__ == "__main__":
    main()
