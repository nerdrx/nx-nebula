#!/usr/bin/env python3
"""Render the transparent layer sprites for the LIVE NX Nebula wallpaper.

The static package (`tools/gen_wallpaper.py`) bakes DESIGN.md §3 into flat
RGB frames. The live Plasma wallpaper cannot do that: it has to *move*. So
the same composition is sliced into independent RGBA sprites that QML stacks
and animates with transform + opacity only -- no shaders, no Canvas, no
per-frame CPU work.

    field      QML Rectangle gradient  #0a0714 -> #12091f  (not rendered here)
    blob-*     one sprite per nebula body, axis-aligned in its own local
               frame; QML rotates/positions/drifts them
    stars-*    two sparse point layers for parallax
    vignette   black-with-alpha falloff, stretched to any aspect
    grain      256px tileable +0/+1 LSB dither, kills gradient banding

Colours, blob geometry, vignette and star statistics are imported from
`gen_wallpaper` so the live wallpaper and the static one are the same
picture. Do not fork those constants.

    python3 tools/gen_nebula_layers.py             # write the package
    python3 tools/gen_nebula_layers.py --check     # verify what was written
    python3 tools/gen_nebula_layers.py --composite out.png [W H]
                                                   # emulate the QML stack

Requires: numpy, Pillow.

--- The alpha contract ------------------------------------------------------

Qt composites an Image with normal source-over blending:

    out = dst * (1 - A*O) + C * (A*O)          A = texel alpha, O = item opacity

The static generator screen-blends instead:

    out = dst + k*C - dst*k*C

Over a near-black field (dst ~ 0.05) the two differ by k*dst*(1-C) <= 0.006,
i.e. under two 8-bit codes, so plain alpha compositing reproduces the screen
blend. Each sprite therefore stores its alpha ramp normalised to a full 0..255
range and hands the tiny real amplitude to QML as `opacity`. That keeps eight
full bits of precision on a ramp whose peak is only 11% -- storing the true
amplitude in the alpha channel would leave ~29 usable levels and band.

The QML `opacity` value for each sprite is printed by this script and must
match the numbers hard-coded in contents/ui/NebulaLayer.qml.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from gen_wallpaper import (  # noqa: E402
        BG_BOTTOM,
        BG_TOP,
        BLOBS_LANDSCAPE,
        REF_SCALE,
        SEED,
        STAR_COUNT,
        VIGNETTE_CENTER,
        VIGNETTE_POWER,
        VIGNETTE_STRENGTH,
        hex_rgb,
        smoothstep,
        star_palette,
        star_positions,
        vignette_mask,
    )
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        f"cannot import tools/gen_wallpaper.py ({exc}) -- the live wallpaper "
        "reuses its palette and blob geometry for visual continuity"
    )


# --------------------------------------------------------------------------
# package layout
# --------------------------------------------------------------------------

PKG_DIR = "com.nerdrx.nx.nebula"
IMAGES_DIR = os.path.join(PKG_DIR, "contents", "images")

# The reference frame the composition was authored in. Sub-blob offsets are
# frozen at this aspect so the violet mass keeps its shape on a 32:9 monitor
# instead of shearing apart.
REF_W, REF_H = 1920, 1080

# Sprite raster sizes. Every blob is a smooth gradient, so a 2.2x upscale on
# screen costs nothing visually and saves several megabytes.
BLOB_PIXELS = {"violet": 2200, "cyan": 1800, "magenta": 1600}

# How far out the sprite canvas reaches, in units of the blob's own major
# sigma. At 3.25 sigma a super-gaussian is at ~2% of peak; the taper below
# fades that remainder to nothing so there is no circular seam.
BLOB_REACH = 3.25
TAPER_START = 0.82  # fraction of the canvas radius where the fade begins

STARS_W, STARS_H = 3200, 1800  # 16:9 -- the aspect the composition was tuned in
STARS_FAR = 700
STARS_NEAR = 160
STAR_VIGNETTE_RESIST = 0.55  # matches gen_wallpaper.add_starfield

# Twinkling stars are split across three sparse layers rather than one.
# A single layer can only fade as a unit, which reads as the sky flickering;
# three layers on mutually unrelated periods, one of them counter-phased,
# read as individual stars breathing. Three opacity interpolators total.
# The total star count across every layer stays near gen_wallpaper's 900.
TWINKLE_LAYERS = (
    # name, star count, seed salt, period (ms), direction
    ("a", 60, 0x711C, 4300, 1),
    ("b", 55, 0x712C, 6700, -1),
    ("c", 45, 0x713C, 8900, 1),
)
TWINKLE_GAIN = 1.20  # twinklers sit a little above the static field
TWINKLE_BASE = 0.78  # resting opacity; the animation swings +/- 0.22 around it
TWINKLE_SWING = 0.22

VIGNETTE_W, VIGNETTE_H = 1600, 900
GRAIN = 256

SCREENSHOT = (640, 360)

# The composition is authored around the four static blobs. Violet and
# violet-soft travel together as one mass (soft is the hot core inside the
# main cloud), so they share a sprite and drift as one body.
BLOB_GROUPS = (
    ("violet", (BLOBS_LANDSCAPE[0], BLOBS_LANDSCAPE[1])),
    ("cyan", (BLOBS_LANDSCAPE[2],)),
    ("magenta", (BLOBS_LANDSCAPE[3],)),
)


# --------------------------------------------------------------------------
# geometry helpers
# --------------------------------------------------------------------------


def to_units(blob) -> tuple[float, float]:
    """Blob centre in scale-units (sqrt(W*H)) at the reference aspect."""
    return (blob.cx * REF_W / REF_SCALE, blob.cy * REF_H / REF_SCALE)


def rotate_into_local(dx: float, dy: float, angle_deg: float) -> tuple[float, float]:
    """Screen-space offset -> the primary blob's local frame.

    Mirrors gen_wallpaper.add_nebula's (u, v) rotation exactly, so a sub-blob
    placed here lands where the static renderer would have put it.
    """
    a = math.radians(angle_deg)
    return (dx * math.cos(a) - dy * math.sin(a), dx * math.sin(a) + dy * math.cos(a))


def blob_field(blob, lx: np.ndarray, ly: np.ndarray, cx: float, cy: float, angle: float):
    """Super-gaussian falloff of one blob over a local coordinate grid."""
    dx = lx - cx
    dy = ly - cy
    a = math.radians(angle)
    cos_a, sin_a = math.cos(a), math.sin(a)
    u = (dx * cos_a - dy * sin_a) / blob.stretch
    v = dx * sin_a + dy * cos_a
    q = (u * u + v * v) / (2.0 * blob.sigma * blob.sigma)
    return np.exp(-np.power(q + 1e-9, blob.falloff, dtype=np.float32))


# --------------------------------------------------------------------------
# blob sprites
# --------------------------------------------------------------------------


def build_blob(name: str, group, size: int) -> tuple[Image.Image, dict]:
    """One nebula body as a premultiply-safe RGBA sprite.

    Returns the image plus the placement contract QML needs: relative centre,
    span in scale-units, screen rotation, and the opacity that restores the
    real (very low) amplitude.
    """
    primary = group[0]
    p_units = to_units(primary)

    locals_ = []
    reach = 0.0
    for blob in group:
        units = to_units(blob)
        lcx, lcy = rotate_into_local(
            units[0] - p_units[0], units[1] - p_units[1], primary.angle
        )
        locals_.append((blob, lcx, lcy, blob.angle - primary.angle))
        major = blob.sigma * max(blob.stretch, 1.0)
        reach = max(reach, math.hypot(lcx, lcy) + BLOB_REACH * major)

    radius = reach
    axis = (np.arange(size, dtype=np.float32) + 0.5) / size * (2.0 * radius) - radius
    lx = axis.reshape(1, size)
    ly = axis.reshape(size, 1)

    alpha = np.zeros((size, size), dtype=np.float32)
    premult = np.zeros((size, size, 3), dtype=np.float32)
    for blob, lcx, lcy, local_angle in locals_:
        g = blob_field(blob, lx, ly, lcx, lcy, local_angle) * blob.amp
        alpha += g
        premult += g[:, :, None] * hex_rgb(blob.color).reshape(1, 1, 3)

    peak = float(alpha.max())

    # Fade the last 18% of the canvas radius to zero. Without it the sprite
    # ends on a ~2%-of-peak step and you can see a faint circle.
    r = np.sqrt(lx * lx + ly * ly)
    alpha *= smoothstep((radius - r) / (radius * (1.0 - TAPER_START)))

    safe = np.maximum(alpha, 1e-7)
    rgb = premult / safe[:, :, None]
    # Where nothing contributes, park the colour on the primary so bilinear
    # taps near the rim never drag an undefined hue in.
    empty = alpha < 1e-6
    rgb[empty] = hex_rgb(primary.color)

    out = np.empty((size, size, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(np.rint(alpha / peak * 255.0), 0, 255).astype(np.uint8)

    meta = {
        "name": name,
        "file": f"blob-{name}.png",
        "pixels": size,
        "relX": round(primary.cx, 4),
        "relY": round(primary.cy, 4),
        # QML rotation is clockwise on a y-down screen; gen_wallpaper's angle
        # is the opposite sense, hence the negation.
        "rotation": round(-primary.angle, 3),
        "spanUnits": round(2.0 * radius, 5),
        "opacity": round(peak, 5),
    }
    return Image.fromarray(out, mode="RGBA"), meta


# --------------------------------------------------------------------------
# starfields
# --------------------------------------------------------------------------


def build_stars(count: int, seed: int, gain: float = 1.0) -> Image.Image:
    """Sparse points on transparency, pre-compensated for the vignette.

    QML stacks the vignette *above* the stars, so each star is brightened by
    1/vignette here; the result after compositing matches the static
    wallpaper, where stars only partly submit to the falloff.
    """
    rng = np.random.default_rng(seed)
    pos = star_positions(rng, count)
    tints = star_palette(rng, count)

    scale = math.sqrt(STARS_W * STARS_H) / REF_SCALE
    roll = rng.random(count).astype(np.float32)
    core = np.where(roll < 0.72, 0.40, np.where(roll < 0.965, 0.56, 0.78)) * scale
    bright = np.where(roll < 0.72, 0.40, np.where(roll < 0.965, 0.58, 0.98))
    bright = bright * (0.50 + 0.50 * rng.random(count).astype(np.float32))
    haloed = roll >= 0.965

    vig = vignette_mask(STARS_W, STARS_H)
    alpha = np.zeros((STARS_H, STARS_W), dtype=np.float32)
    premult = np.zeros((STARS_H, STARS_W, 3), dtype=np.float32)

    for i in range(count):
        px = float(pos[i, 0]) * STARS_W
        py = float(pos[i, 1]) * STARS_H
        vx = min(STARS_W - 1, max(0, int(px)))
        vy = min(STARS_H - 1, max(0, int(py)))
        v = float(vig[vy, vx])
        amp = float(bright[i]) * gain * (1.0 - STAR_VIGNETTE_RESIST * (1.0 - v)) / max(v, 0.2)
        amp = min(amp, 1.0)
        _splat_rgba(alpha, premult, px, py, float(core[i]), tints[i], amp)
        if haloed[i]:
            _splat_rgba(alpha, premult, px, py, float(core[i]) * 3.4, tints[i], amp * 0.10)

    np.clip(alpha, 0.0, 1.0, out=alpha)
    safe = np.maximum(alpha, 1e-7)
    rgb = np.clip(premult / safe[:, :, None], 0.0, 1.0)
    rgb[alpha < 1e-6] = 0.0

    out = np.empty((STARS_H, STARS_W, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(np.rint(alpha * 255.0), 0, 255).astype(np.uint8)
    return Image.fromarray(out, mode="RGBA")


def _splat_rgba(alpha, premult, px, py, sigma, tint, amp) -> None:
    if amp <= 0.0:
        return
    h, w = alpha.shape
    reach = max(1, int(math.ceil(sigma * 3.0)))
    x0 = max(0, int(math.floor(px)) - reach)
    x1 = min(w, int(math.floor(px)) + reach + 1)
    y0 = max(0, int(math.floor(py)) - reach)
    y1 = min(h, int(math.floor(py)) + reach + 1)
    if x0 >= x1 or y0 >= y1:
        return
    gx = (np.arange(x0, x1, dtype=np.float32) + 0.5) - px
    gy = (np.arange(y0, y1, dtype=np.float32) + 0.5) - py
    d2 = (gx * gx).reshape(1, -1) + (gy * gy).reshape(-1, 1)
    g = np.exp(-d2 / (2.0 * sigma * sigma)) * amp
    alpha[y0:y1, x0:x1] += g
    premult[y0:y1, x0:x1] += g[:, :, None] * tint.reshape(1, 1, 3)


# --------------------------------------------------------------------------
# vignette + grain
# --------------------------------------------------------------------------


def build_vignette() -> Image.Image:
    """Black with a radial alpha ramp. Multiplying by (1-a) *is* the mask."""
    vig = vignette_mask(VIGNETTE_W, VIGNETTE_H)
    alpha = np.clip(1.0 - vig, 0.0, 1.0)
    out = np.zeros((VIGNETTE_H, VIGNETTE_W, 4), dtype=np.uint8)
    out[:, :, 3] = np.rint(alpha * 255.0).astype(np.uint8)
    return Image.fromarray(out, mode="RGBA")


def build_grain() -> Image.Image:
    """A tileable +0/+1 LSB dither.

    The field gradient crosses an 8-bit code roughly every 90 rows, and Qt
    Quick does not dither its own gradients, so without this the desktop is a
    staircase. One uniform bit of additive noise decorrelates it, the same
    trick gen_wallpaper.quantize plays on the static frames.
    """
    rng = np.random.default_rng(SEED ^ 0x5EED)
    out = np.zeros((GRAIN, GRAIN, 4), dtype=np.uint8)
    out[:, :, :3] = 255
    out[:, :, 3] = rng.integers(0, 2, size=(GRAIN, GRAIN), dtype=np.uint8)
    return Image.fromarray(out, mode="RGBA")


# --------------------------------------------------------------------------
# composite -- an exact stand-in for what QML will draw
# --------------------------------------------------------------------------


def field_rgb(width: int, height: int) -> np.ndarray:
    top, bottom = hex_rgb(BG_TOP), hex_rgb(BG_BOTTOM)
    t = ((np.arange(height, dtype=np.float32) + 0.5) / height).reshape(height, 1, 1)
    t = t ** 1.15
    return np.ascontiguousarray(
        np.broadcast_to(
            top.reshape(1, 1, 3) + (bottom - top).reshape(1, 1, 3) * t,
            (height, width, 3),
        ).astype(np.float32)
    )


def _over(base: np.ndarray, src: Image.Image, opacity: float = 1.0) -> None:
    """Source-over an RGBA PIL image onto a float32 RGB buffer, in place."""
    arr = np.asarray(src, dtype=np.float32) / 255.0
    a = (arr[:, :, 3] * opacity)[:, :, None]
    np.add(base * (1.0 - a), arr[:, :, :3] * a, out=base)


def composite(root: str, width: int, height: int) -> Image.Image:
    """Stack the shipped PNGs the way contents/ui/NebulaLayer.qml stacks them."""
    meta = load_meta(root)
    unit = math.sqrt(width * height)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    base = field_rgb(width, height)

    for entry in meta["blobs"]:
        sprite = Image.open(os.path.join(root, IMAGES_DIR, entry["file"])).convert("RGBA")
        span = int(round(entry["spanUnits"] * unit))
        sprite = sprite.resize((span, span), Image.BILINEAR)
        # PIL rotates counter-clockwise; QML's rotation is clockwise.
        sprite = sprite.rotate(-entry["rotation"], resample=Image.BICUBIC, expand=True)
        layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        layer.paste(
            sprite,
            (
                int(round(entry["relX"] * width - sprite.width / 2)),
                int(round(entry["relY"] * height - sprite.height / 2)),
            ),
        )
        _over(base, layer, entry["opacity"])

    for entry in meta["stars"] + meta.get("twinkle", []):
        stars = Image.open(os.path.join(root, IMAGES_DIR, entry["file"])).convert("RGBA")
        _over(base, _cover(stars, width, height, entry["overscan"]), entry["opacity"])

    vig = Image.open(os.path.join(root, IMAGES_DIR, "vignette.png")).convert("RGBA")
    _over(base, vig.resize((width, height), Image.BILINEAR))

    grain = Image.open(os.path.join(root, IMAGES_DIR, "grain.png")).convert("RGBA")
    tiled = Image.new("RGBA", (width, height))
    for y in range(0, height, GRAIN):
        for x in range(0, width, GRAIN):
            tiled.paste(grain, (x, y))
    _over(base, tiled)

    canvas = Image.fromarray(
        np.clip(np.rint(base * 255.0), 0, 255).astype(np.uint8), mode="RGB"
    )
    return canvas


def _cover(src: Image.Image, width: int, height: int, overscan: float) -> Image.Image:
    """PreserveAspectCrop into a box `overscan` larger than the frame."""
    bw, bh = width * overscan, height * overscan
    ratio = max(bw / src.width, bh / src.height)
    scaled = src.resize(
        (max(1, int(round(src.width * ratio))), max(1, int(round(src.height * ratio)))),
        Image.LANCZOS,
    )
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out.paste(scaled, ((width - scaled.width) // 2, (height - scaled.height) // 2))
    return out


# --------------------------------------------------------------------------
# build / check
# --------------------------------------------------------------------------


def meta_path(root: str) -> str:
    return os.path.join(root, IMAGES_DIR, "layers.json")


def load_meta(root: str) -> dict:
    with open(meta_path(root), encoding="utf-8") as fh:
        return json.load(fh)


def save_png(image: Image.Image, path: str) -> int:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)
    return os.path.getsize(path)


def human(n: int) -> str:
    return f"{n / 1024:.0f} KB" if n < 1024 * 1024 else f"{n / (1024 * 1024):.2f} MB"


def build(root: str) -> None:
    total = 0
    meta: dict = {"blobs": [], "stars": [], "twinkle": []}

    for name, group in BLOB_GROUPS:
        sprite, entry = build_blob(name, group, BLOB_PIXELS[name])
        size = save_png(sprite, os.path.join(root, IMAGES_DIR, entry["file"]))
        total += size
        meta["blobs"].append(entry)
        print(
            f"  {entry['file']:<20} {entry['pixels']}px  {human(size):>9}  "
            f"span={entry['spanUnits']:.4f}u  rot={entry['rotation']:+.1f}  "
            f"opacity={entry['opacity']:.5f}"
        )

    for name, count, seed, opacity, overscan in (
        ("far", STARS_FAR, SEED, 0.85, 1.05),
        ("near", STARS_NEAR, SEED ^ 0xA5A5, 1.0, 1.05),
    ):
        stars = build_stars(count, seed)
        entry = {
            "file": f"stars-{name}.png",
            "count": count,
            "opacity": opacity,
            "overscan": overscan,
        }
        size = save_png(stars, os.path.join(root, IMAGES_DIR, entry["file"]))
        total += size
        meta["stars"].append(entry)
        print(f"  {entry['file']:<20} {STARS_W}x{STARS_H}  {human(size):>9}  {count} stars")

    for name, count, salt, period, direction in TWINKLE_LAYERS:
        stars = build_stars(count, SEED ^ salt, gain=TWINKLE_GAIN)
        entry = {
            "file": f"stars-twinkle-{name}.png",
            "count": count,
            # The resting value. QML swings TWINKLE_SWING either side of it,
            # so a frozen wallpaper shows exactly what this composite shows.
            "opacity": TWINKLE_BASE,
            "overscan": 1.05,
            "period": period,
            "direction": direction,
        }
        size = save_png(stars, os.path.join(root, IMAGES_DIR, entry["file"]))
        total += size
        meta["twinkle"].append(entry)
        print(
            f"  {entry['file']:<20} {STARS_W}x{STARS_H}  {human(size):>9}  "
            f"{count} stars  {period / 1000:.1f}s dir={direction:+d}"
        )

    size = save_png(build_vignette(), os.path.join(root, IMAGES_DIR, "vignette.png"))
    total += size
    print(f"  {'vignette.png':<20} {VIGNETTE_W}x{VIGNETTE_H}  {human(size):>9}")

    size = save_png(build_grain(), os.path.join(root, IMAGES_DIR, "grain.png"))
    total += size
    print(f"  {'grain.png':<20} {GRAIN}x{GRAIN}   {human(size):>9}")

    meta["starCount"] = STARS_FAR + STARS_NEAR + sum(t[1] for t in TWINKLE_LAYERS)
    meta["referenceStarCount"] = STAR_COUNT
    meta["twinkleSwing"] = TWINKLE_SWING
    with open(meta_path(root), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
        fh.write("\n")
    total += os.path.getsize(meta_path(root))

    shot = composite(root, 1920, 1080).resize(SCREENSHOT, Image.LANCZOS)
    size = save_png(shot, os.path.join(root, PKG_DIR, "contents", "screenshot.png"))
    total += size
    print(f"  {'screenshot.png':<20} {SCREENSHOT[0]}x{SCREENSHOT[1]}   {human(size):>9}")

    print(f"  {'total':<20} {human(total):>24}")
    print()
    print("  QML contract (must match contents/ui/NebulaLayer.qml):")
    for entry in meta["blobs"]:
        print(
            f"    {entry['name']:<8} relX={entry['relX']} relY={entry['relY']} "
            f"span={entry['spanUnits']:.4f} rotation={entry['rotation']:+.1f} "
            f"opacity={entry['opacity']:.5f}"
        )


def check(root: str) -> int:
    problems = []
    total = 0
    meta = load_meta(root)
    expected = [(e["file"], (e["pixels"], e["pixels"])) for e in meta["blobs"]]
    expected += [
        (e["file"], (STARS_W, STARS_H)) for e in meta["stars"] + meta.get("twinkle", [])
    ]
    expected += [
        ("vignette.png", (VIGNETTE_W, VIGNETTE_H)),
        ("grain.png", (GRAIN, GRAIN)),
    ]

    for name, size in expected:
        path = os.path.join(root, IMAGES_DIR, name)
        if not os.path.exists(path):
            problems.append(f"missing {path}")
            continue
        with Image.open(path) as im:
            if im.size != size:
                problems.append(f"{name}: got {im.size}, want {size}")
            if im.mode != "RGBA":
                problems.append(f"{name}: mode {im.mode}, want RGBA")
        total += os.path.getsize(path)
        print(f"  ok {name:<20} {human(os.path.getsize(path)):>9}")

    shot = os.path.join(root, PKG_DIR, "contents", "screenshot.png")
    if not os.path.exists(shot):
        problems.append(f"missing {shot}")
    else:
        total += os.path.getsize(shot)
        print(f"  ok {'screenshot.png':<20} {human(os.path.getsize(shot)):>9}")

    print(f"  total {human(total)}")
    if total > 6 * 1024 * 1024:
        problems.append(f"package images total {human(total)} -- budget is 6 MB")
    for line in problems:
        print(f"  FAIL {line}", file=sys.stderr)
    return 1 if problems else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--composite", metavar="OUT")
    parser.add_argument("--size", nargs=2, type=int, default=(1920, 1080))
    parser.add_argument(
        "--root",
        default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    )
    args = parser.parse_args()

    if args.check:
        return check(args.root)
    if args.composite:
        img = composite(args.root, args.size[0], args.size[1])
        img.save(args.composite)
        print(f"  wrote {args.composite} {img.size}")
        return 0
    build(args.root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
