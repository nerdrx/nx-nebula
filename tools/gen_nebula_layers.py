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

# The aurora curtain: a rare deep-night event, not part of the resting
# composition (and so absent from the composite and the screenshot). Sharp
# lower edge in the accent cyan feathering upward into the brand violet --
# the NX palette happens to be an aurora palette.
AURORA_W, AURORA_H = 1600, 800
AURORA_TOP = "#7700ff"
AURORA_BOTTOM = "#00e5ff"
AURORA_OPACITY = 0.14  # QML peak opacity; printed in the contract below

# The celestial bodies (1.6.0). The moon ships as a 16-frame phase sheet the
# QML picks from with sourceClipRect; the rest are single sprites for the
# Milky Way veil, the rare comet, and the evening star.
MOON_FRAME = 384
MOON_FRAMES = 16
MOON_LIT = "#e9e3f7"
MOON_DARK = "#241c3c"

MW_W, MW_H = 1600, 900

COMET_W, COMET_H = 1024, 256

VENUS_SIZE = 128

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
# aurora
# --------------------------------------------------------------------------


def build_aurora() -> tuple[Image.Image, dict]:
    """The aurora curtain sprite.

    Real aurora structure in miniature: vertical rays whose intensity is a
    banded 1-D noise along the ribbon, hanging from a wavy lower border that
    is sharp below and feathers far upward. Alpha is normalised to the full
    8-bit range like every other sprite; QML restores the (very low) real
    amplitude through item opacity.
    """
    rng = np.random.default_rng(SEED ^ 0xA07A)
    w, h = AURORA_W, AURORA_H
    x = ((np.arange(w, dtype=np.float32) + 0.5) / w).reshape(1, w)
    y = ((np.arange(h, dtype=np.float32) + 0.5) / h).reshape(h, 1)

    def snoise(components: int, fmin: float, fmax: float, power: float) -> np.ndarray:
        """Smooth seeded 1-D noise along x, normalised to 0..1."""
        v = np.zeros(w, dtype=np.float32)
        for _ in range(components):
            f = rng.uniform(fmin, fmax)
            p = rng.uniform(0.0, 1.0)
            v += (1.0 / f**power) * np.sin(2.0 * math.pi * (f * x[0] + p)).astype(
                np.float32
            )
        v -= v.min()
        return v / max(float(v.max()), 1e-6)

    # Banded ray intensity; the exponent deepens the gaps between rays.
    rays = snoise(10, 3.0, 30.0, 0.7) ** 1.9
    # The ribbon dissolves before it reaches its own canvas ends.
    rays *= smoothstep(x[0] / 0.14) * smoothstep((1.0 - x[0]) / 0.14)

    # A wavy lower border around 74% height: sharp 3% falloff below it,
    # a long 30% feather above it.
    edge = (0.74 + 0.07 * (snoise(4, 1.0, 4.0, 1.0) * 2.0 - 1.0)).reshape(1, w)
    above = np.clip(edge - y, 0.0, None)
    below = np.clip(y - edge, 0.0, None)
    v = np.where(y <= edge, np.exp(-above / 0.30), np.exp(-below / 0.03)).astype(
        np.float32
    )
    v *= smoothstep(y[:, 0] / 0.10).reshape(h, 1)  # nothing touches the top...
    v *= smoothstep((1.0 - y[:, 0]) / 0.06).reshape(h, 1)  # ...or the bottom

    alpha = rays.reshape(1, w) * v
    alpha /= max(float(alpha.max()), 1e-6)

    # Cyan at the border, violet up the feather.
    t = np.clip(above / 0.45, 0.0, 1.0)
    bottom, top = hex_rgb(AURORA_BOTTOM), hex_rgb(AURORA_TOP)
    rgb = bottom.reshape(1, 1, 3) + (top - bottom).reshape(1, 1, 3) * t[:, :, None]

    out = np.empty((h, w, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(rgb * 255.0), 0, 255).astype(np.uint8)
    out[:, :, 3] = np.clip(np.rint(alpha * 255.0), 0, 255).astype(np.uint8)

    meta = {
        "file": "aurora.png",
        "width": w,
        "height": h,
        "opacity": AURORA_OPACITY,
    }
    return Image.fromarray(out, mode="RGBA"), meta


# --------------------------------------------------------------------------
# celestial bodies
# --------------------------------------------------------------------------


def _smooth_noise(rng, w: int, h: int, octaves) -> np.ndarray:
    """Band-limited noise 0..1: random grids upsampled and summed."""
    total = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    for cells in octaves:
        grid = rng.random((max(2, cells), max(2, cells * 2))).astype(np.float32)
        layer = np.asarray(
            Image.fromarray((grid * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC),
            dtype=np.float32,
        ) / 255.0
        total += layer * amp
        amp *= 0.55
    total -= total.min()
    return total / max(float(total.max()), 1e-6)


def build_moon() -> tuple[Image.Image, dict]:
    """A 16-frame lunar phase sheet, new moon first, waxing on the right.

    Proper sphere lighting: sun direction swings around the moon with the
    phase, the terminator is feathered, and the dark side keeps a whisper of
    presence so a crescent still reads as a full disc the way the real one
    does against a clear sky.
    """
    size = MOON_FRAME
    r = size * 0.42
    axis = (np.arange(size, dtype=np.float32) + 0.5) - size / 2
    u = axis.reshape(1, size) / r
    v = axis.reshape(size, 1) / r
    rho = np.sqrt(u * u + v * v)
    inside = np.clip((1.0 - rho) * r / 1.5, 0.0, 1.0)
    z = np.sqrt(np.clip(1.0 - rho * rho, 0.0, None))

    lit_rgb, dark_rgb = hex_rgb(MOON_LIT), hex_rgb(MOON_DARK)
    sheet = np.zeros((size, size * MOON_FRAMES, 4), dtype=np.uint8)
    for i in range(MOON_FRAMES):
        a = 2.0 * math.pi * i / MOON_FRAMES
        d = u * math.sin(a) - z * math.cos(a)
        lit = np.clip(d / 0.10 + 0.5, 0.0, 1.0) * (0.85 + 0.15 * z)
        alpha = inside * np.clip(lit + 0.16, 0.0, 1.0)
        rgb = dark_rgb.reshape(1, 1, 3) + (lit_rgb - dark_rgb).reshape(1, 1, 3) * lit[:, :, None]
        sheet[:, i * size:(i + 1) * size, :3] = np.clip(np.rint(rgb * 255.0), 0, 255)
        sheet[:, i * size:(i + 1) * size, 3] = np.clip(np.rint(alpha * 255.0), 0, 255)

    meta = {"file": "moon.png", "frame": size, "frames": MOON_FRAMES, "opacity": 0.85}
    return Image.fromarray(sheet, mode="RGBA"), meta


def build_milkyway() -> tuple[Image.Image, dict]:
    """A faint horizontal galactic band; QML tilts and drifts it.

    A gaussian envelope across the band and smooth-noise structure along it,
    with the ends dissolved so no edge can ever show. Alpha is normalised;
    the QML opacity is a few percent on the deepest nights only.
    """
    rng = np.random.default_rng(SEED ^ 0x314159)
    w, h = MW_W, MW_H
    y = ((np.arange(h, dtype=np.float32) + 0.5) / h).reshape(h, 1)
    x = ((np.arange(w, dtype=np.float32) + 0.5) / w).reshape(1, w)

    envelope = np.exp(-((y - 0.5) / 0.16) ** 2).astype(np.float32) \
        * (smoothstep(x / 0.18) * smoothstep((1.0 - x) / 0.18))

    texture = _smooth_noise(rng, w, h, (6, 12, 24, 48)) ** 1.7
    # A dark dust lane wandering along the middle, like the real one.
    lane = 0.5 + 0.08 * np.sin(2.0 * math.pi * (x * 1.7 + 0.2))
    dust = 1.0 - 0.55 * np.exp(-(((y - lane) / 0.045) ** 2)).astype(np.float32)

    alpha = envelope * (0.30 + 0.70 * texture) * dust
    alpha /= max(float(alpha.max()), 1e-6)

    tint = hex_rgb("#cfc4ee")
    out = np.empty((h, w, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(tint.reshape(1, 1, 3) * np.ones((h, w, 3)) * 255.0), 0, 255)
    out[:, :, 3] = np.clip(np.rint(alpha * 255.0), 0, 255)

    meta = {"file": "milkyway.png", "width": w, "height": h, "opacity": 0.07}
    return Image.fromarray(out, mode="RGBA"), meta


def build_comet() -> tuple[Image.Image, dict]:
    """The comet: bright head at the right, tail dissolving to the left,
    violet fading to cyan down its length — the NX gradient at astronomical
    scale. Baked pointing +x, like the meteor, so rotation aims it."""
    rng = np.random.default_rng(SEED ^ 0xC03E7)
    w, h = COMET_W, COMET_H
    y = ((np.arange(h, dtype=np.float32) + 0.5) / h).reshape(h, 1)
    x = ((np.arange(w, dtype=np.float32) + 0.5) / w).reshape(1, w)

    head_x, head_y = 0.86, 0.5
    # Tail: exponential fade leftward from the head, width growing with
    # distance, centreline bending gently upward.
    dist = np.clip(head_x - x, 0.0, None)
    centre = head_y - 0.22 * dist * dist
    width = 0.035 + 0.30 * dist
    tail = np.exp(-dist / 0.34) * np.exp(-(((y - centre) / width) ** 2))
    tail *= 0.55 + 0.45 * _smooth_noise(rng, w, h, (3, 9, 27))
    tail *= smoothstep(x[0] / 0.06)

    head = np.exp(-(((x - head_x) / 0.018) ** 2 + ((y - head_y) / 0.07) ** 2)) * 1.6
    glow = np.exp(-(((x - head_x) / 0.06) ** 2 + ((y - head_y) / 0.22) ** 2)) * 0.5

    alpha = np.clip(tail * 0.8 + head + glow, 0.0, None).astype(np.float32)
    alpha /= max(float(alpha.max()), 1e-6)

    # Violet at the head through cyan down the tail, white-hot at the core.
    t = np.clip(dist / 0.6, 0.0, 1.0)
    violet, cyan, white = hex_rgb("#a06bff"), hex_rgb("#00e5ff"), hex_rgb("#f6f2ff")
    rgb = violet.reshape(1, 1, 3) + (cyan - violet).reshape(1, 1, 3) * t[:, :, None]
    core = np.clip(head, 0.0, 1.0)[:, :, None]
    rgb = rgb * (1.0 - core) + white.reshape(1, 1, 3) * core

    out = np.empty((h, w, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(rgb * 255.0), 0, 255)
    out[:, :, 3] = np.clip(np.rint(alpha * 255.0), 0, 255)

    meta = {"file": "comet.png", "width": w, "height": h, "opacity": 0.8}
    return Image.fromarray(out, mode="RGBA"), meta


def build_venus() -> tuple[Image.Image, dict]:
    """The evening star: a small steady glow with the faintest diffraction
    cross. Steady on purpose — planets do not twinkle."""
    s = VENUS_SIZE
    axis = ((np.arange(s, dtype=np.float32) + 0.5) - s / 2) / (s / 2)
    x = axis.reshape(1, s)
    y = axis.reshape(s, 1)
    r2 = x * x + y * y
    core = np.exp(-r2 / 0.018)
    halo = np.exp(-r2 / 0.28) * 0.25
    spikes = (np.exp(-(x / 0.03) ** 2) + np.exp(-(y / 0.03) ** 2)) * np.exp(-r2 / 0.5) * 0.18
    alpha = np.clip(core + halo + spikes, 0.0, 1.0)

    tint = hex_rgb("#f6f2ff")
    out = np.empty((s, s, 4), dtype=np.uint8)
    out[:, :, :3] = np.clip(np.rint(tint.reshape(1, 1, 3) * np.ones((s, s, 3)) * 255.0), 0, 255)
    out[:, :, 3] = np.clip(np.rint(alpha * 255.0), 0, 255)

    meta = {"file": "star-bright.png", "size": s, "opacity": 0.9}
    return Image.fromarray(out, mode="RGBA"), meta


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

    sprite, entry = build_aurora()
    size = save_png(sprite, os.path.join(root, IMAGES_DIR, entry["file"]))
    total += size
    meta["aurora"] = entry
    print(
        f"  {entry['file']:<20} {AURORA_W}x{AURORA_H}  {human(size):>9}  "
        f"opacity={entry['opacity']:.2f} (event peak)"
    )

    for key, builder in (
        ("moon", build_moon),
        ("milkyway", build_milkyway),
        ("comet", build_comet),
        ("venus", build_venus),
    ):
        sprite, entry = builder()
        size = save_png(sprite, os.path.join(root, IMAGES_DIR, entry["file"]))
        total += size
        meta[key] = entry
        print(f"  {entry['file']:<20} {sprite.width}x{sprite.height}  {human(size):>9}")

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
    if "aurora" in meta:
        expected.append((meta["aurora"]["file"], (AURORA_W, AURORA_H)))
    if "moon" in meta:
        expected.append((meta["moon"]["file"], (MOON_FRAME * MOON_FRAMES, MOON_FRAME)))
    if "milkyway" in meta:
        expected.append((meta["milkyway"]["file"], (MW_W, MW_H)))
    if "comet" in meta:
        expected.append((meta["comet"]["file"], (COMET_W, COMET_H)))
    if "venus" in meta:
        expected.append((meta["venus"]["file"], (VENUS_SIZE, VENUS_SIZE)))

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
