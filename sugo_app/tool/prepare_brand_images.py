"""Turns the brand artwork into the files the app actually uses.

Run from `sugo_app/` whenever the icon or splash artwork changes:

    python tool/prepare_brand_images.py
    dart run flutter_launcher_icons

Needs Pillow, NumPy and SciPy (`pip install pillow numpy scipy`).

## The sources (2026-09-29 brand)

Both live in `assets/source/`, which pubspec.yaml does not declare: they are
kept in the repository but never bundled into the app. At about 1.3 MB each
they would otherwise ride along in every APK beside the small files cut from
them. (That folder also keeps the retired artwork - the paper-plane icon, the
old splash and the login/register banners - for the record.)

* `assets/source/icon 2.png` - the app icon: a house with a wrench, a swoosh
  and a service van over the SUGO wordmark and tagline, on a navy rounded
  square. It replaced the paper-plane icon, which read as Telegram's.
* `assets/source/splash 2.png` - the splash poster, with a "Get Started"
  button drawn into the picture.

## Why neither can be used as it is

The icon has no transparency: the area outside its rounded square is flat
white, drawn into the pixels. Handed to the launcher-icon generator it would
put white corners on the icon on every phone. So this script finds the navy
rounded square, throws the white away, and writes:

* `assets/icon/app_icon_rounded.png` - the rounded square on real
  transparency. Android before 8.0, the web favicon and PWA icons, Windows
  and macOS.
* `assets/icon/app_icon_full.png` - the artwork filling the whole square,
  corners painted in with the neighbouring navy. iOS rejects icons with
  transparency and cuts its own corners, so it needs something opaque under
  the corner it cuts away.
* `assets/icon/app_icon_adaptive.png` - the Android 8+ foreground. The
  launcher crops it to a circle, squircle or teardrop of its choosing, and
  only the centre 66 of its 108 units is guaranteed to survive every shape.
  The tagline runs nearly edge to edge, so the artwork is shrunk into that
  circle and the navy painted outward around it.
* `assets/images/brand_emblem.png` - the emblem alone (house, wrench, swoosh,
  van) centred on the icon's navy, wordmark painted out. The app's small
  logo mark and the disc at the centre of the matching screen.
* `assets/images/brand_header.jpg` - the whole lockup, the login header.

The splash's button is a picture of a button: it cannot be pressed, cannot
show that the app is still loading, and cannot be hidden for someone already
signed in. So the script paints it out:

* `assets/images/splash_art.jpg` - the poster with the drawn button removed.
  Every column of the band the button occupied is rebuilt by blending
  straight down from the row above the button's glow to the row below it;
  the backdrop there is a smooth vertical gradient, so the blend is
  invisible. The app draws a real "Get started" button in that space, after
  a loading animation.
* `assets/images/banner_technician.jpg` - the technician from the poster,
  for the home screen's "Need a tech fix?" banner.

`assets/icon/` is deliberately *not* an asset folder in pubspec.yaml: the icon
files are inputs to the generator, not something the app loads.
"""

from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
IMAGES = ROOT / "assets" / "images"
SOURCES = ROOT / "assets" / "source"
ICON_SOURCE = SOURCES / "icon 2.png"
SPLASH_SOURCE = SOURCES / "splash 2.png"

ICON_DIR = ROOT / "assets" / "icon"
EMBLEM = IMAGES / "brand_emblem.png"
HEADER = IMAGES / "brand_header.jpg"
SPLASH_ART = IMAGES / "splash_art.jpg"
BANNER = IMAGES / "banner_technician.jpg"

# Retired outputs, removed so they cannot be loaded by mistake: the
# paper-plane brand's matching disc, and the profile cover - drawn in code
# since 2026-09-29, because the emblem behind the avatar fought with it.
RETIRED = (IMAGES / "matching_plane.png", IMAGES / "profile_cover.png")

# The poster's drawn button, glow included, in its 941x1672 pixels: every row
# from BUTTON_TOP to BUTTON_BOTTOM is rebuilt. Measured by scanning for the
# button's cyan: rows 1492-1600 carry it, the rows around them are backdrop.
BUTTON_TOP = 1488
BUTTON_BOTTOM = 1606

# The technician in the poster, cap to toolbox, as a square in its pixels.
BANNER_BOX = (160, 1042, 598, 1480)

# Trimmed off every side of the header: the outermost 2% of the icon is the
# lighter bevel of the rounded square, which reads as a stripe down each edge
# of a full-width header.
HEADER_TRIM = 0.02

# Where the emblem sits in the icon square, as fractions of its side: its
# centre, and the radius of a circle that holds the roof, the swoosh's ends
# and the van with a little air. Everything below EMBLEM_CUT - the wordmark
# and tagline - is repainted with the surrounding navy first.
EMBLEM_CENTRE = (0.526, 0.345)
EMBLEM_RADIUS = 0.40
EMBLEM_CUT = 0.585

ICON_SIZE = 1024

# Share of the adaptive foreground's 108 units the artwork may fill. The
# furthest-out ink is the tagline's last letters, at about 73% of the
# square's half width and 66% of its half height; at 0.62 that corner sits
# 32.9 units from the centre, inside the 33-unit safe circle.
ADAPTIVE_ARTWORK_SHARE = 0.62


def paint_outward(rgb: np.ndarray, known: np.ndarray) -> np.ndarray:
    """Fills every pixel outside `known` with the navy nearest to it.

    Each unknown pixel copies the colour of the closest known pixel, then
    that fill alone is blurred so it has no streaks. The known pixels - the
    artwork itself - are returned untouched.
    """
    _, (iy, ix) = ndimage.distance_transform_edt(~known, return_indices=True)
    nearest = rgb[iy, ix]
    smooth = np.stack(
        [ndimage.gaussian_filter(nearest[..., c], sigma=24) for c in range(3)],
        axis=2,
    )
    return np.where(known[..., None], rgb, smooth).clip(0, 255).astype(np.uint8)


def rounded_square_mask(rgb: np.ndarray) -> np.ndarray:
    """True inside the navy rounded square, False on the white around it.

    The white is unsaturated (max channel minus min channel is small); the
    navy square is strongly saturated. The white wordmark is unsaturated too,
    which is why this takes only the pale regions that touch the border of the
    image - a flood fill from the outside - rather than every pale pixel.
    """
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    pale = saturation < 40
    labels, _ = ndimage.label(pale)
    edge_labels = np.unique(
        np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])
    )
    outside = np.isin(labels, edge_labels[edge_labels != 0])
    inside = ~outside
    # Drop the fringe where white and navy were blended by the export's
    # anti-aliasing; left in, it reads as a light outline.
    return ndimage.binary_erosion(inside, iterations=3)


def paint_out_band(rgb: np.ndarray, top: int, bottom: int) -> np.ndarray:
    """Rebuilds rows top..bottom of every column from the rows around them.

    Each column blends linearly from the average of the four rows above `top`
    to the average of the four rows below `bottom`. A light horizontal blur
    over the band alone then removes any per-column banding.
    """
    out = rgb.copy()
    above = rgb[top - 4 : top].mean(axis=0)
    below = rgb[bottom : bottom + 4].mean(axis=0)
    rows = bottom - top
    t = np.linspace(0, 1, rows)[:, None, None]
    band = above[None] * (1 - t) + below[None] * t
    band = np.stack(
        [ndimage.gaussian_filter1d(band[..., c], sigma=3, axis=1) for c in range(3)],
        axis=2,
    )
    out[top:bottom] = band
    return out


def icon_outputs() -> list[Path]:
    rgb = np.asarray(Image.open(ICON_SOURCE).convert("RGB")).astype(np.float32)
    inside = rounded_square_mask(rgb)

    rows = np.where(inside.any(axis=1))[0]
    cols = np.where(inside.any(axis=0))[0]
    top, bottom, left, right = rows[0], rows[-1] + 1, cols[0], cols[-1] + 1
    # Square the box up so nothing is stretched when it is resized.
    side = max(bottom - top, right - left)
    box = (left, top, left + side, top + side)
    print(f"icon square: {box}")

    # ---- rounded, on transparency
    alpha = ndimage.gaussian_filter(inside.astype(np.float32), sigma=0.8)
    rgba = np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)
    rounded = Image.fromarray(rgba, "RGBA").crop(box)
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    rounded.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).save(
        ICON_DIR / "app_icon_rounded.png", optimize=True
    )

    # ---- full bleed: only the four corners change
    full_img = Image.fromarray(paint_outward(rgb, inside), "RGB").crop(box)
    full_img.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).save(
        ICON_DIR / "app_icon_full.png", optimize=True
    )

    # ---- Android adaptive foreground: artwork shrunk into the safe circle
    square_rgb = rgb[top : top + side, left : left + side]
    square_known = inside[top : top + side, left : left + side]
    pad = round(side * (1 / ADAPTIVE_ARTWORK_SHARE - 1) / 2)
    padded_rgb = np.pad(square_rgb, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
    padded_known = np.pad(square_known, pad, constant_values=False)
    adaptive = Image.fromarray(paint_outward(padded_rgb, padded_known), "RGB")
    adaptive.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS).save(
        ICON_DIR / "app_icon_adaptive.png", optimize=True
    )

    w, h = full_img.size

    # ---- the emblem alone, wordmark painted out, padded so a circle round
    # it never runs off the image
    emblem_known = square_known.copy()
    emblem_known[int(side * EMBLEM_CUT) :, :] = False
    radius = int(side * EMBLEM_RADIUS)
    pad2 = radius
    painted = paint_outward(
        np.pad(square_rgb, ((pad2, pad2), (pad2, pad2), (0, 0)), mode="edge"),
        np.pad(emblem_known, pad2, constant_values=False),
    )
    cx = int(side * EMBLEM_CENTRE[0]) + pad2
    cy = int(side * EMBLEM_CENTRE[1]) + pad2
    emblem = Image.fromarray(painted, "RGB").crop(
        (cx - radius, cy - radius, cx + radius, cy + radius)
    )
    emblem.resize((512, 512), Image.LANCZOS).save(EMBLEM, optimize=True)

    # ---- the login header: the full lockup, bevel trimmed
    t = int(w * HEADER_TRIM)
    header = full_img.crop((t, t, w - t, h - t)).resize((900, 900), Image.LANCZOS)
    header.save(HEADER, quality=88, optimize=True, progressive=True)

    return [
        ICON_DIR / "app_icon_rounded.png",
        ICON_DIR / "app_icon_full.png",
        ICON_DIR / "app_icon_adaptive.png",
        EMBLEM,
        HEADER,
    ]


def splash_outputs() -> list[Path]:
    poster = np.asarray(Image.open(SPLASH_SOURCE).convert("RGB")).astype(np.float32)
    clean = paint_out_band(poster, BUTTON_TOP, BUTTON_BOTTOM)
    art = Image.fromarray(clean.clip(0, 255).astype(np.uint8), "RGB")
    art.save(SPLASH_ART, quality=90, optimize=True, progressive=True)

    technician = Image.fromarray(poster.clip(0, 255).astype(np.uint8), "RGB")
    technician.crop(BANNER_BOX).resize((520, 520), Image.LANCZOS).save(
        BANNER, quality=88, optimize=True, progressive=True
    )
    return [SPLASH_ART, BANNER]


def main() -> None:
    written = icon_outputs() + splash_outputs()
    for path in RETIRED:
        if path.exists():
            path.unlink()
            print(f"removed {path.relative_to(ROOT)}")
    for path in written:
        print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
