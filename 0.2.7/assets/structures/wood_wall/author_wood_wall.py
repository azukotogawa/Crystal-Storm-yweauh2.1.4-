#!/usr/bin/env python3
"""Author the Crystal Storm wood_wall palisade mesh + albedo atlas.

Mesh is in voxel-column units (width ≈ 1 column, Y up from ground).
Runtime bind multiplies by WorldSettings.voxel_scale.

This is a real authored asset (cylinders, cones, lashings, earth collar),
not a runtime multi-box silhouette.
"""

from __future__ import annotations

import math
import os
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

HERE = Path(__file__).resolve().parent
SESSION_IMAGES = Path(
    "/home/kuroe/.grok/sessions/"
    "%2Fhome%2Fkuroe%2Fai-workspace%2Fcrystalstorm/"
    "019ff853-afea-7d93-a638-6f393e4b1271/images"
)

# Atlas UV regions (u0, v0, u1, v1) in OpenGL (v=0 bottom).
# Written PNG has v=0 at top; UVs below are Godot/OpenGL (v up).
UV_BARK = (0.02, 0.02, 0.48, 0.98)
UV_END = (0.52, 0.52, 0.98, 0.98)
UV_ROPE = (0.52, 0.27, 0.98, 0.48)
UV_DIRT = (0.52, 0.02, 0.98, 0.23)


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _remap_uv(u: float, v: float, region: tuple[float, float, float, float]) -> tuple[float, float]:
    u0, v0, u1, v1 = region
    return _lerp(u0, u1, u), _lerp(v0, v1, v)


def _make_seamless(im: Image.Image, blend: int = 24) -> Image.Image:
    im = im.convert("RGBA")
    w, h = im.size
    canvas = Image.new("RGBA", (w, h))
    canvas.paste(im, (0, 0))
    # Wrap-blend left/right and top/bottom so cylinder/disk UVs don't seam.
    left = im.crop((0, 0, blend, h))
    right = im.crop((w - blend, 0, w, h))
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    overlay.paste(right, (0, 0))
    mask = Image.new("L", (w, h), 0)
    for x in range(blend):
        a = int(255 * (1.0 - x / float(blend)))
        for y in range(h):
            mask.putpixel((x, y), a)
    canvas = Image.composite(overlay, canvas, mask)
    top = canvas.crop((0, 0, w, blend))
    bot = canvas.crop((0, h - blend, w, h))
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    overlay.paste(bot, (0, 0))
    mask = Image.new("L", (w, h), 0)
    for y in range(blend):
        a = int(255 * (1.0 - y / float(blend)))
        for x in range(w):
            mask.putpixel((x, y), a)
    return Image.composite(overlay, canvas, mask)


def _load_src(name: str, fallback_index: int) -> Image.Image:
    local = HERE / "src" / name
    if local.exists():
        return Image.open(local).convert("RGBA")
    src = SESSION_IMAGES / f"{fallback_index}.jpg"
    im = Image.open(src).convert("RGBA")
    local.parent.mkdir(parents=True, exist_ok=True)
    im.convert("RGB").save(local, quality=92)
    return im


def build_albedo(path: Path, size: int = 256) -> None:
    bark = _make_seamless(_load_src("bark.jpg", 1).resize((size, size), Image.Resampling.LANCZOS))
    end = _make_seamless(_load_src("endgrain.jpg", 2).resize((size, size), Image.Resampling.LANCZOS))
    # Crop the heart motif: use a corner ring field.
    end = end.crop((0, 0, size * 2 // 3, size * 2 // 3)).resize((size, size), Image.Resampling.LANCZOS)
    end = _make_seamless(end, 16)
    rope = _make_seamless(_load_src("rope.jpg", 3).resize((size, size), Image.Resampling.LANCZOS))
    dirt = _make_seamless(_load_src("dirt.jpg", 4).resize((size, size), Image.Resampling.LANCZOS))

    # Slight warmth so it sits with Crystal Storm dirt voxels.
    bark = ImageEnhance.Color(bark).enhance(1.05)
    bark = ImageEnhance.Contrast(bark).enhance(1.08)

    atlas = Image.new("RGBA", (size, size), (40, 28, 18, 255))
    half = size // 2
    q = size // 4
    atlas.paste(bark.resize((half, size), Image.Resampling.LANCZOS), (0, 0))
    atlas.paste(end.resize((half, half), Image.Resampling.LANCZOS), (half, 0))
    atlas.paste(rope.resize((half, q), Image.Resampling.LANCZOS), (half, half))
    atlas.paste(dirt.resize((half, q), Image.Resampling.LANCZOS), (half, half + q))
    # Soft pixel-game read: very light sharpen, no blur mush.
    atlas = atlas.filter(ImageFilter.UnsharpMask(radius=0.6, percent=80, threshold=2))
    atlas.save(path)
    print(f"wrote albedo {path} {atlas.size}")


class MeshBuilder:
    def __init__(self) -> None:
        self.v: list[tuple[float, float, float]] = []
        self.vt: list[tuple[float, float]] = []
        self.vn: list[tuple[float, float, float]] = []
        self.f: list[tuple[int, int, int]] = []  # 1-based into parallel v/vt/vn

    def add_tri(
        self,
        p0: tuple[float, float, float],
        p1: tuple[float, float, float],
        p2: tuple[float, float, float],
        uv0: tuple[float, float],
        uv1: tuple[float, float],
        uv2: tuple[float, float],
        n: tuple[float, float, float] | None = None,
    ) -> None:
        if n is None:
            ax, ay, az = p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2]
            bx, by, bz = p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2]
            nx = ay * bz - az * by
            ny = az * bx - ax * bz
            nz = ax * by - ay * bx
            ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            n = (nx / ln, ny / ln, nz / ln)
        i0 = len(self.v) + 1
        for p, uv in ((p0, uv0), (p1, uv1), (p2, uv2)):
            self.v.append(p)
            self.vt.append(uv)
            self.vn.append(n)
        self.f.append((i0, i0 + 1, i0 + 2))

    def add_quad(
        self,
        p00: tuple[float, float, float],
        p10: tuple[float, float, float],
        p11: tuple[float, float, float],
        p01: tuple[float, float, float],
        uv00: tuple[float, float],
        uv10: tuple[float, float],
        uv11: tuple[float, float],
        uv01: tuple[float, float],
    ) -> None:
        self.add_tri(p00, p10, p11, uv00, uv10, uv11)
        self.add_tri(p00, p11, p01, uv00, uv11, uv01)


def _rot_y(p: tuple[float, float, float], yaw: float) -> tuple[float, float, float]:
    c, s = math.cos(yaw), math.sin(yaw)
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


def add_log(
    mb: MeshBuilder,
    x: float,
    z: float,
    radius: float,
    height: float,
    tip: float,
    lean_x: float = 0.0,
    lean_z: float = 0.0,
    sides: int = 10,
    rings: int = 5,
) -> None:
    """Tapered stake: wider at soil, pointed tip. Bark sides + end-grain tip."""
    r_bot = radius
    r_top = radius * 0.72
    shaft = height
    total = height + tip

    def center_at(y: float) -> tuple[float, float, float]:
        t = y / total
        return (x + lean_x * t, y, z + lean_z * t)

    def radius_at(y: float) -> float:
        if y <= shaft:
            t = y / shaft
            return _lerp(r_bot, r_top, t)
        # cone
        t = (y - shaft) / max(tip, 1e-4)
        return _lerp(r_top, 0.008, t)

    # Shaft + cone rings
    ys = [shaft * i / (rings - 1) for i in range(rings)]
    ys.append(shaft + tip * 0.45)
    ys.append(shaft + tip)
    ring_pts: list[list[tuple[float, float, float]]] = []
    for y in ys:
        c = center_at(y)
        r = radius_at(y)
        ring = []
        for s in range(sides):
            a = (s / sides) * math.tau
            ring.append((c[0] + math.cos(a) * r, c[1], c[2] + math.sin(a) * r))
        ring_pts.append(ring)

    for ri in range(len(ring_pts) - 1):
        y0, y1 = ys[ri], ys[ri + 1]
        region = UV_BARK if y1 <= shaft + tip * 0.2 else UV_END
        v0 = y0 / total
        v1 = y1 / total
        for s in range(sides):
            s1 = (s + 1) % sides
            u0 = s / sides
            u1 = (s + 1) / sides
            mb.add_quad(
                ring_pts[ri][s],
                ring_pts[ri][s1],
                ring_pts[ri + 1][s1],
                ring_pts[ri + 1][s],
                _remap_uv(u0, v0, region),
                _remap_uv(u1, v0, region),
                _remap_uv(u1, v1, region),
                _remap_uv(u0, v1, region),
            )

    # Bottom cap (end grain) so raised-terrain contact is not a hole.
    c0 = center_at(0.0)
    for s in range(sides):
        s1 = (s + 1) % sides
        uv0 = _remap_uv(0.5 + 0.45 * math.cos(s / sides * math.tau), 0.5 + 0.45 * math.sin(s / sides * math.tau), UV_END)
        uv1 = _remap_uv(0.5 + 0.45 * math.cos(s1 / sides * math.tau), 0.5 + 0.45 * math.sin(s1 / sides * math.tau), UV_END)
        uvc = _remap_uv(0.5, 0.5, UV_END)
        # Downward facing: reverse winding
        mb.add_tri(c0, ring_pts[0][s1], ring_pts[0][s], uvc, uv1, uv0)


def add_lashing(
    mb: MeshBuilder,
    y: float,
    x0: float,
    x1: float,
    z: float,
    radius: float,
    segs: int = 16,
    sides: int = 7,
) -> None:
    """Horizontal hemp wrap across the stake row."""
    length = x1 - x0
    for i in range(segs):
        t0 = i / segs
        t1 = (i + 1) / segs
        cx0 = _lerp(x0, x1, t0)
        cx1 = _lerp(x0, x1, t1)
        # Slight sag
        sag0 = 0.012 * math.sin(t0 * math.pi)
        sag1 = 0.012 * math.sin(t1 * math.pi)
        for s in range(sides):
            a0 = s / sides * math.tau
            a1 = (s + 1) / sides * math.tau
            def ring(cx: float, sag: float, a: float) -> tuple[float, float, float]:
                return (
                    cx,
                    y - sag + math.sin(a) * radius,
                    z + math.cos(a) * radius,
                )
            p00 = ring(cx0, sag0, a0)
            p10 = ring(cx1, sag1, a0)
            p11 = ring(cx1, sag1, a1)
            p01 = ring(cx0, sag0, a1)
            mb.add_quad(
                p00, p10, p11, p01,
                _remap_uv(t0, s / sides, UV_ROPE),
                _remap_uv(t1, s / sides, UV_ROPE),
                _remap_uv(t1, (s + 1) / sides, UV_ROPE),
                _remap_uv(t0, (s + 1) / sides, UV_ROPE),
            )


def add_rail(mb: MeshBuilder, y: float, z: float, radius: float) -> None:
    x0, x1 = -0.46, 0.46
    segs, sides = 12, 8
    for i in range(segs):
        t0 = i / segs
        t1 = (i + 1) / segs
        cx0 = _lerp(x0, x1, t0)
        cx1 = _lerp(x0, x1, t1)
        for s in range(sides):
            a0 = s / sides * math.tau
            a1 = (s + 1) / sides * math.tau
            def pt(cx: float, a: float) -> tuple[float, float, float]:
                return (cx, y + math.sin(a) * radius, z + math.cos(a) * radius)
            mb.add_quad(
                pt(cx0, a0), pt(cx1, a0), pt(cx1, a1), pt(cx0, a1),
                _remap_uv(t0, 0.1, UV_BARK),
                _remap_uv(t1, 0.1, UV_BARK),
                _remap_uv(t1, 0.35, UV_BARK),
                _remap_uv(t0, 0.35, UV_BARK),
            )
    # End caps
    for cx, flip in ((x0, True), (x1, False)):
        center = (cx, y, z)
        for s in range(sides):
            a0 = s / sides * math.tau
            a1 = (s + 1) / sides * math.tau
            p0 = (cx, y + math.sin(a0) * radius, z + math.cos(a0) * radius)
            p1 = (cx, y + math.sin(a1) * radius, z + math.cos(a1) * radius)
            uv0 = _remap_uv(0.5 + 0.4 * math.cos(a0), 0.5 + 0.4 * math.sin(a0), UV_END)
            uv1 = _remap_uv(0.5 + 0.4 * math.cos(a1), 0.5 + 0.4 * math.sin(a1), UV_END)
            uvc = _remap_uv(0.5, 0.5, UV_END)
            if flip:
                mb.add_tri(center, p1, p0, uvc, uv1, uv0)
            else:
                mb.add_tri(center, p0, p1, uvc, uv0, uv1)


def add_earth_collar(mb: MeshBuilder) -> None:
    """Low mossy berm the stakes sit in — matches the reference mound, stays short
    so it does not double the raised voxel bulk."""
    rings = 4
    segs = 16
    radii = [0.12, 0.26, 0.38, 0.48]
    heights = [0.11, 0.09, 0.055, 0.0]
    pts: list[list[tuple[float, float, float]]] = []
    for r, h in zip(radii, heights):
        ring = []
        for s in range(segs):
            a = s / segs * math.tau
            # Slightly elliptical along the palisade
            rx = r * 1.05
            rz = r * 0.72
            jitter = 0.012 * math.sin(a * 3.0 + r * 8.0)
            ring.append((math.cos(a) * (rx + jitter), h, math.sin(a) * (rz + jitter * 0.5)))
        pts.append(ring)
    for ri in range(len(pts) - 1):
        v0 = ri / (len(pts) - 1)
        v1 = (ri + 1) / (len(pts) - 1)
        for s in range(segs):
            s1 = (s + 1) % segs
            u0 = s / segs
            u1 = (s + 1) / segs
            mb.add_quad(
                pts[ri][s], pts[ri][s1], pts[ri + 1][s1], pts[ri + 1][s],
                _remap_uv(u0, v0, UV_DIRT),
                _remap_uv(u1, v0, UV_DIRT),
                _remap_uv(u1, v1, UV_DIRT),
                _remap_uv(u0, v1, UV_DIRT),
            )
    # Fill disk
    center = (0.0, heights[0], 0.0)
    for s in range(segs):
        s1 = (s + 1) % segs
        mb.add_tri(
            center, pts[0][s], pts[0][s1],
            _remap_uv(0.5, 0.5, UV_DIRT),
            _remap_uv(0.5 + 0.4 * math.cos(s / segs * math.tau), 0.5 + 0.4 * math.sin(s / segs * math.tau), UV_DIRT),
            _remap_uv(0.5 + 0.4 * math.cos(s1 / segs * math.tau), 0.5 + 0.4 * math.sin(s1 / segs * math.tau), UV_DIRT),
        )


def build_mesh() -> MeshBuilder:
    mb = MeshBuilder()
    # Front rank — the readable palisade face from the iso camera.
    front = [
        # x, z, r, shaft, tip, lean_x, lean_z
        (-0.42,  0.00, 0.078, 0.98, 0.16,  0.010, -0.006),
        (-0.28, -0.035, 0.086, 1.12, 0.20, -0.008,  0.010),
        (-0.14,  0.025, 0.074, 0.92, 0.14,  0.004,  0.004),
        ( 0.00, -0.018, 0.090, 1.18, 0.22,  0.000, -0.004),
        ( 0.15,  0.030, 0.080, 1.04, 0.17, -0.010,  0.008),
        ( 0.29, -0.028, 0.084, 1.10, 0.19,  0.006,  0.002),
        ( 0.42,  0.008, 0.076, 0.96, 0.15, -0.006, -0.008),
    ]
    # Rear rank — depth so a line and a corner both read as a stake wall, not a card.
    rear = [
        (-0.34, 0.11, 0.068, 0.86, 0.12, 0.004, 0.006),
        (-0.12, 0.13, 0.064, 0.80, 0.11, -0.004, 0.002),
        ( 0.10, 0.12, 0.070, 0.88, 0.13, 0.002, 0.004),
        ( 0.33, 0.105, 0.066, 0.84, 0.12, -0.002, 0.006),
    ]
    for spec in front + rear:
        add_log(mb, *spec, sides=10, rings=5)
    add_earth_collar(mb)
    add_lashing(mb, 0.28, -0.46, 0.46, 0.01, 0.018)
    add_lashing(mb, 0.52, -0.46, 0.46, 0.00, 0.016)
    add_rail(mb, 0.40, 0.07, 0.032)
    return mb


def write_obj(mb: MeshBuilder, obj_path: Path, mtl_name: str) -> None:
    mtl_path = obj_path.with_suffix(".mtl")
    mtl_path.write_text(
        "newmtl wood_wall_mat\n"
        "Kd 1.00 1.00 1.00\n"
        "map_Kd wood_wall_albedo.png\n",
        encoding="utf-8",
    )
    lines = [
        "# Crystal Storm authored wood_wall palisade",
        f"mtllib {mtl_path.name}",
        "usemtl wood_wall_mat",
        "o WoodWall",
        "g wood_wall",
    ]
    for x, y, z in mb.v:
        lines.append(f"v {x:.6f} {y:.6f} {z:.6f}")
    for u, v in mb.vt:
        lines.append(f"vt {u:.6f} {v:.6f}")
    for x, y, z in mb.vn:
        lines.append(f"vn {x:.6f} {y:.6f} {z:.6f}")
    for a, b, c in mb.f:
        lines.append(f"f {a}/{a}/{a} {b}/{b}/{b} {c}/{c}/{c}")
    obj_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    xs = [p[0] for p in mb.v]
    ys = [p[1] for p in mb.v]
    zs = [p[2] for p in mb.v]
    print(
        f"wrote {obj_path} verts={len(mb.v)} tris={len(mb.f)} "
        f"aabb=({min(xs):.3f},{min(ys):.3f},{min(zs):.3f})-"
        f"({max(xs):.3f},{max(ys):.3f},{max(zs):.3f})"
    )


def main() -> None:
    build_albedo(HERE / "wood_wall_albedo.png", size=256)
    mb = build_mesh()
    write_obj(mb, HERE / "wood_wall.obj", "wood_wall_mat")


if __name__ == "__main__":
    main()
