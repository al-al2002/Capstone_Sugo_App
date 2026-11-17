"""The SUGO logo: one geometry, every file (2026-11-16).

Run from `sugo_app/` whenever the logo changes:

    python tool/make_logo.py
    dart run flutter_launcher_icons

Needs Pillow and NumPy (`pip install pillow numpy`).

## The mark

A white **S drawn as a road** - a dashed centre line running down it - that
starts at a cyan dot and ends at an **orange map pin**, on a navy tile.

* *Sugo* is Bisaya for an errand, for sending someone to do something. The
  mark is exactly that: a trip from where the technician sets off to the pin
  on your door - the route every booking in the app is drawn as.
* The S is the initial, so the icon still says the name at 48px, where the
  previous emblem (a house, a wrench, a swoosh and a van) turned to mush.
* The colours are the app's own (`lib/core/constants/app_colors.dart`): the
  navy-to-blue gradient of every hero, cyan for the start, and the orange of
  the stroke on the wordmark's "O" for the pin - so the mark and the wordmark
  read as one lockup.

## Why a script draws it

The geometry lives here once, and everything is written from it: the SVG the
admin panel shows, the app icon PNGs `flutter_launcher_icons` reads, the
emblem `SugoLogoMark` draws in the app, and the admin's favicon and e-mail
logo. Drawn at 4x and scaled down, so the edges are smooth. No design file to
lose, and the app and the admin can never show two different logos.

This replaces the icon half of `prepare_brand_images.py`, which now refuses to
write icon files so it cannot put the old emblem back.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ADMIN_PUBLIC = ROOT / "sugo-admin" / "public"

SVG_SOURCE = ROOT / "assets" / "source" / "sugo_logo.svg"
ICON_DIR = ROOT / "assets" / "icon"
EMBLEM = ROOT / "assets" / "images" / "brand_emblem.png"
ADMIN_SVG = ADMIN_PUBLIC / "images" / "sugo-logo.svg"
ADMIN_PNG = ADMIN_PUBLIC / "images" / "brand-emblem.png"
ADMIN_FAVICON = ADMIN_PUBLIC / "favicon.ico"

# ------------------------------------------------------------------ palette
NAVY = (0x03, 0x1F, 0x44)
NAVY_LIFT = (0x0C, 0x4C, 0x9C)
ACCENT = (0xF5, 0x9E, 0x0B)
CYAN = (0x11, 0xC5, 0xE8)
WHITE = (0xFF, 0xFF, 0xFF)
DASH = NAVY_LIFT

# ----------------------------------------------------------------- geometry
# Everything in a 1024 square.
SIZE = 1024
TILE_RADIUS = 228

# The S: two circles stacked. The road runs anticlockwise round the top one,
# from its upper right, and clockwise round the bottom one, to its lower left.
# The whole glyph is nudged so its bounding box (pin included) is centred.
OX, OY = -9.0, 18.0
R = 135.0
C1 = (512.0 + OX, 392.0 + OY)
C2 = (512.0 + OX, 662.0 + OY)
SWEEP = 240.0
TOP_END_DEG = -30.0  # on C1
ROAD = 112.0

DASH_W = 13.0
DASH_ON = 36.0
DASH_OFF = 28.0
DASH_SKIP_START = 34.0  # keeps the line clear of the pin
DASH_SKIP_END = 46.0  # and of the start dot

PIN_R = 70.0
PIN_DROP = 128.0  # from the tip up to the centre of the head
PIN_TIP_NUDGE = (10.0, -6.0)  # the tip sits just past the road's end
PIN_DOT_R = 27.0

START_DOT_R = 27.0

# Adaptive icons are masked to a shape the launcher picks; only the middle
# 66% is guaranteed to show, so the glyph is scaled into it.
ADAPTIVE_SCALE = 0.66

SS = 4  # supersampling


def _deg(a: float) -> float:
    return math.radians(a)


def top_end() -> tuple[float, float]:
    return (C1[0] + R * math.cos(_deg(TOP_END_DEG)),
            C1[1] + R * math.sin(_deg(TOP_END_DEG)))


def bottom_end() -> tuple[float, float]:
    a = -90.0 + SWEEP
    return (C2[0] + R * math.cos(_deg(a)), C2[1] + R * math.sin(_deg(a)))


def road_points(step: float = 0.5) -> list[tuple[float, float, float]]:
    """(x, y, distance from the top end) along the S."""
    pts: list[tuple[float, float, float]] = []
    arc = R * _deg(SWEEP)
    n = int(arc / step)
    for i in range(n + 1):
        t = i / n
        a = TOP_END_DEG - SWEEP * t  # anticlockwise round C1
        pts.append((C1[0] + R * math.cos(_deg(a)),
                    C1[1] + R * math.sin(_deg(a)), arc * t))
    for i in range(1, n + 1):
        t = i / n
        a = -90.0 + SWEEP * t  # clockwise round C2
        pts.append((C2[0] + R * math.cos(_deg(a)),
                    C2[1] + R * math.sin(_deg(a)), arc + arc * t))
    return pts


def pin_geometry() -> tuple[tuple[float, float], tuple[float, float], float, float]:
    tx, ty = top_end()
    tip = (tx + PIN_TIP_NUDGE[0], ty + PIN_TIP_NUDGE[1])
    head = (tip[0], tip[1] - PIN_DROP)
    # Where the straight sides meet the head: perpendicular to the radius.
    beta = math.acos(PIN_R / PIN_DROP)
    side = (PIN_R * math.sin(beta), PIN_R * math.cos(beta))
    return tip, head, side[0], side[1]


# -------------------------------------------------------------------- raster
def gradient(size: int) -> Image.Image:
    """The navy-to-blue tile with a soft light in its upper left."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / (size - 1)
    t = (xs + ys) / 2.0
    top = np.array(NAVY_LIFT, dtype=np.float32)
    bottom = np.array(NAVY, dtype=np.float32)
    rgb = top * (1 - t[..., None]) + bottom * t[..., None]
    d = np.hypot(xs - 0.28, ys - 0.22) / 0.75
    glow = np.clip(1 - d, 0, 1) ** 2 * 0.12
    rgb = rgb * (1 - glow[..., None]) + 255.0 * glow[..., None]
    return Image.fromarray(rgb.clip(0, 255).astype(np.uint8), "RGB")


def glyph(size: int) -> Image.Image:
    """The road, the dashes, the start dot and the pin, on transparency."""
    k = size / SIZE
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def dot(x: float, y: float, r: float, colour: tuple[int, int, int]) -> None:
        draw.ellipse([(x - r) * k, (y - r) * k, (x + r) * k, (y + r) * k],
                     fill=colour + (255,))

    points = road_points()
    for x, y, _ in points:
        dot(x, y, ROAD / 2, WHITE)

    total = points[-1][2]
    period = DASH_ON + DASH_OFF
    for x, y, s in points:
        if DASH_SKIP_START <= s <= total - DASH_SKIP_END:
            if (s - DASH_SKIP_START) % period < DASH_ON:
                dot(x, y, DASH_W / 2, DASH)

    bx, by = bottom_end()
    dot(bx, by, START_DOT_R, CYAN)

    tip, head, sx, sy = pin_geometry()
    draw.polygon([((head[0] - sx) * k, (head[1] + sy) * k),
                  ((head[0] + sx) * k, (head[1] + sy) * k),
                  (tip[0] * k, tip[1] * k)], fill=ACCENT + (255,))
    dot(head[0], head[1], PIN_R, ACCENT)
    dot(head[0], head[1], PIN_DOT_R, WHITE)
    return img


def tile_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=TILE_RADIUS * size / SIZE, fill=255)
    return mask


def render(scale: float = 1.0, rounded: bool = False) -> Image.Image:
    """The full logo at 1024, the glyph scaled about the centre by [scale]."""
    big = SIZE * SS
    base = gradient(big).convert("RGBA")
    g = glyph(big)
    if scale != 1.0:
        side = round(big * scale)
        g = g.resize((side, side), Image.LANCZOS)
        layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
        layer.paste(g, ((big - side) // 2, (big - side) // 2), g)
        g = layer
    base.alpha_composite(g)
    if rounded:
        base.putalpha(tile_mask(big))
    return base.resize((SIZE, SIZE), Image.LANCZOS)


# ----------------------------------------------------------------------- svg
def svg() -> str:
    tx, ty = top_end()
    bx, by = bottom_end()
    mid = (C1[0], C1[1] + R)  # where the two circles meet
    tip, head, sx, sy = pin_geometry()
    f = lambda v: f"{v:.1f}"  # noqa: E731
    road = (f"M {f(tx)} {f(ty)} "
            f"A {f(R)} {f(R)} 0 1 0 {f(mid[0])} {f(mid[1])} "
            f"A {f(R)} {f(R)} 0 1 1 {f(bx)} {f(by)}")
    hexc = lambda c: "#%02X%02X%02X" % c  # noqa: E731
    # The centre line is its own, shorter path - trimmed clear of the pin and
    # the start dot - rather than a dash pattern with blank ends: with round
    # caps, a zero-length dash still paints a dot.
    a0 = TOP_END_DEG - math.degrees(DASH_SKIP_START / R)
    a1 = -90.0 + SWEEP - math.degrees(DASH_SKIP_END / R)
    d0 = (C1[0] + R * math.cos(_deg(a0)), C1[1] + R * math.sin(_deg(a0)))
    d1 = (C2[0] + R * math.cos(_deg(a1)), C2[1] + R * math.sin(_deg(a1)))
    centre = (f"M {f(d0[0])} {f(d0[1])} "
              f"A {f(R)} {f(R)} 0 1 0 {f(mid[0])} {f(mid[1])} "
              f"A {f(R)} {f(R)} 0 1 1 {f(d1[0])} {f(d1[1])}")
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" role="img" aria-label="SUGO">
  <!-- Generated by sugo_app/tool/make_logo.py - edit the script, not this file. -->
  <defs>
    <linearGradient id="sugo-tile" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{hexc(NAVY_LIFT)}"/>
      <stop offset="1" stop-color="{hexc(NAVY)}"/>
    </linearGradient>
    <radialGradient id="sugo-light" cx="0.28" cy="0.22" r="0.75">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.12"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="{SIZE}" height="{SIZE}" rx="{TILE_RADIUS}" fill="url(#sugo-tile)"/>
  <rect width="{SIZE}" height="{SIZE}" rx="{TILE_RADIUS}" fill="url(#sugo-light)"/>
  <path d="{road}" fill="none" stroke="#FFFFFF" stroke-width="{f(ROAD)}" stroke-linecap="round"/>
  <path d="{centre}" fill="none" stroke="{hexc(DASH)}" stroke-width="{f(DASH_W)}" stroke-linecap="round" stroke-dasharray="{f(DASH_ON)} {f(DASH_OFF)}"/>
  <circle cx="{f(bx)}" cy="{f(by)}" r="{f(START_DOT_R)}" fill="{hexc(CYAN)}"/>
  <path d="M {f(tip[0])} {f(tip[1])} L {f(head[0] - sx)} {f(head[1] + sy)} A {f(PIN_R)} {f(PIN_R)} 0 1 1 {f(head[0] + sx)} {f(head[1] + sy)} Z" fill="{hexc(ACCENT)}"/>
  <circle cx="{f(head[0])}" cy="{f(head[1])}" r="{f(PIN_DOT_R)}" fill="#FFFFFF"/>
</svg>
"""


# ---------------------------------------------------------------------- main
def main() -> None:
    written: list[Path] = []

    def save(img: Image.Image, path: Path, size: int | None = None) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        out = img if size is None else img.resize((size, size), Image.LANCZOS)
        out.save(path, optimize=True)
        written.append(path)

    full = render()
    rounded = render(rounded=True)
    adaptive = render(scale=ADAPTIVE_SCALE)

    # iOS rejects alpha and rounds the corners itself: the full square.
    save(full.convert("RGB"), ICON_DIR / "app_icon_full.png")
    # Android before 8, web, Windows, macOS: the rounded tile on transparency.
    save(rounded, ICON_DIR / "app_icon_rounded.png")
    # Android 8+: the glyph inside the safe circle, the tile colour to the
    # edge (the launcher masks it).
    save(adaptive.convert("RGB"), ICON_DIR / "app_icon_adaptive.png")
    # The in-app emblem. Full bleed: SugoLogoMark clips it to its own corners.
    save(full.convert("RGB"), EMBLEM, 512)

    # The admin panel: the SVG for the page, a PNG for e-mail (clients do not
    # show SVG), and the favicon.
    text = svg()
    for path in (SVG_SOURCE, ADMIN_SVG):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        written.append(path)
    save(rounded, ADMIN_PNG, 256)
    rounded.save(ADMIN_FAVICON, sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    written.append(ADMIN_FAVICON)

    for path in written:
        print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
