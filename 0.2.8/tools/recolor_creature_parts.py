import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "voxel", "entities")
CRYSTAL = [184, 71, 255]
EYE = [20, 20, 26]

LOOKS = {
    "crystal_mite": {"shell": [74, 38, 112], "limb": [40, 24, 58], "head": [128, 70, 180], "accent": [226, 168, 255]},
    "crystal_mite_spike": {"shell": [44, 70, 120], "limb": [26, 36, 64], "head": [86, 120, 190], "accent": [170, 220, 255]},
    "crystal_mite_shard": {"shell": [112, 42, 78], "limb": [58, 22, 40], "head": [176, 78, 120], "accent": [255, 176, 210]},
    "shard_guard": {"shell": [58, 72, 96], "limb": [36, 44, 60], "head": [104, 120, 150], "accent": [200, 210, 230]},
    "shard_tyrant": {"shell": [92, 40, 64], "limb": [52, 24, 38], "head": [140, 64, 92], "accent": [232, 140, 72]},
    "origin_warden": {"shell": [40, 36, 52], "limb": [26, 24, 34], "head": [70, 62, 88], "accent": [196, 150, 60]},
}

I_CRYSTAL, I_EYE, I_SHELL, I_LIMB, I_HEAD, I_ACCENT = 0, 1, 2, 3, 4, 5


def column_tops(cells):
    top = {}
    for x, y, z, _ in cells:
        k = (x, z)
        top[k] = max(top.get(k, -1), y)
    return top


def recolor(name):
    path = os.path.join(ROOT, name + ".json")
    with open(path) as f:
        data = json.load(f)
    look = LOOKS[name]
    old = data["palette"]
    eye_ids = {i for i, c in enumerate(old) if c == EYE}
    data["palette"] = [CRYSTAL, EYE, look["shell"], look["limb"], look["head"], look["accent"]]
    parts = data["parts"]
    for part, cells in parts.items():
        top = column_tops(cells)
        zs = [c[2] for c in cells]
        zmid = (min(zs) + max(zs)) / 2.0
        out = []
        for x, y, z, m in cells:
            if m in eye_ids:
                n = I_EYE
            elif part == "head":
                n = I_HEAD if y < top[(x, z)] else I_ACCENT
            elif part.startswith("leg"):
                n = I_LIMB
            elif part == "tail":
                n = I_CRYSTAL if z >= zmid else I_SHELL
            else:
                n = I_CRYSTAL if y == top[(x, z)] else I_SHELL
            out.append([x, y, z, n])
        parts[part] = out
    with open(path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    counts = {}
    for cells in parts.values():
        for c in cells:
            counts[c[3]] = counts.get(c[3], 0) + 1
    print(name, counts)


if __name__ == "__main__":
    for n in sys.argv[1:] or LOOKS.keys():
        recolor(n)
