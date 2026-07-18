#!/usr/bin/env python3
"""Draw the DMG background (arrow guiding "app → Applications") in code.

No AI image generation, no external art files — just PIL primitives. Re-run
this whenever the layout constants here or in package-release.sh change.

Coordinate system: the layout constants below (WINDOW_*, ICON_*, POINT
coordinates) MUST match the `set bounds` / `set position of item` values in
package-release.sh's DMG-styling AppleScript. This file is the single
source of truth for the pixel math; package-release.sh's comments point
back here.
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# --- Window layout, in Finder points (must match package-release.sh) ---
WINDOW_W_PT = 660
WINDOW_H_PT = 400
ICON_SIZE_PT = 128
APP_CENTER_PT = (180, 180)
APPLICATIONS_CENTER_PT = (480, 180)

# --- Rendering ---
SCALE = 2  # @2x for Retina; DPI is set to 144 to tell Finder "this is 2x".
DPI = 144
CANVAS_W = WINDOW_W_PT * SCALE
CANVAS_H = WINDOW_H_PT * SCALE

BG_COLOR = (250, 250, 248)
VIGNETTE_COLOR = (225, 225, 220)
ARROW_COLOR = (64, 64, 64)
ACCENT_COLOR = (196, 240, 42)  # matches AppIcon.png lime green
SHADOW_COLOR = (0, 0, 0)

OUT_PATH = "../Resources/dmg-background.png"


def to_px(pt):
    return int(round(pt * SCALE))


def draw_arrow_mask(size, x1, x2, cy, shaft_half_h, head_len, head_half_h):
    """Return an 'L' mode mask with a rounded-shaft right-pointing arrow."""
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    shaft_x2 = x2 - head_len
    # Rounded shaft.
    d.rounded_rectangle(
        [x1, cy - shaft_half_h, shaft_x2 + shaft_half_h, cy + shaft_half_h],
        radius=shaft_half_h,
        fill=255,
    )
    # Triangular head.
    d.polygon(
        [
            (shaft_x2, cy - head_half_h),
            (x2, cy),
            (shaft_x2, cy + head_half_h),
        ],
        fill=255,
    )
    return mask


def main():
    canvas = Image.new("RGB", (CANVAS_W, CANVAS_H), BG_COLOR)

    # Subtle radial vignette for a bit of depth (kept very soft).
    vignette = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    vd = ImageDraw.Draw(vignette)
    max_r = math.hypot(CANVAS_W / 2, CANVAS_H / 2)
    steps = 48
    for i in range(steps, 0, -1):
        r = max_r * i / steps
        alpha = int(70 * (i / steps) ** 3)
        vd.ellipse(
            [CANVAS_W / 2 - r, CANVAS_H / 2 - r, CANVAS_W / 2 + r, CANVAS_H / 2 + r],
            fill=alpha,
        )
    vignette_layer = Image.new("RGB", (CANVAS_W, CANVAS_H), VIGNETTE_COLOR)
    canvas = Image.composite(canvas, vignette_layer, vignette)

    # Arrow geometry sits in the empty gap between the two icon slots.
    app_cx, app_cy = to_px(APP_CENTER_PT[0]), to_px(APP_CENTER_PT[1])
    apps_cx, apps_cy = to_px(APPLICATIONS_CENTER_PT[0]), to_px(APPLICATIONS_CENTER_PT[1])
    icon_r = to_px(ICON_SIZE_PT) // 2
    gap_x1 = app_cx + icon_r + to_px(14)
    gap_x2 = apps_cx - icon_r - to_px(14)
    cy = (app_cy + apps_cy) // 2

    shaft_half_h = to_px(6)
    head_len = int((gap_x2 - gap_x1) * 0.32)
    head_half_h = to_px(20)

    shape_mask = draw_arrow_mask(
        (CANVAS_W, CANVAS_H), gap_x1, gap_x2, cy, shaft_half_h, head_len, head_half_h
    )

    # Soft drop shadow, offset down, blurred, lower opacity.
    shadow_mask = shape_mask.point(lambda v: int(v * 0.35))
    shadow_mask = ImageChops.offset(shadow_mask, 0, to_px(4))
    shadow_mask = shadow_mask.filter(ImageFilter.GaussianBlur(to_px(3)))
    shadow_layer = Image.new("RGB", (CANVAS_W, CANVAS_H), SHADOW_COLOR)
    canvas = Image.composite(shadow_layer, canvas, shadow_mask)

    # Base arrow fill.
    arrow_layer = Image.new("RGB", (CANVAS_W, CANVAS_H), ARROW_COLOR)
    canvas = Image.composite(arrow_layer, canvas, shape_mask)

    # Lime accent highlight along the top edge (gradient fade downward).
    highlight_gradient = Image.new("L", (CANVAS_W, CANVAS_H), 0)
    hg = ImageDraw.Draw(highlight_gradient)
    fade_h = shaft_half_h + head_half_h
    top_y = cy - head_half_h
    for i in range(fade_h):
        alpha = int(200 * max(0, 1 - i / (fade_h * 0.6)))
        hg.line([(0, top_y + i), (CANVAS_W, top_y + i)], fill=alpha)
    highlight_mask = ImageChops.multiply(shape_mask, highlight_gradient)
    accent_layer = Image.new("RGB", (CANVAS_W, CANVAS_H), ACCENT_COLOR)
    canvas = Image.composite(accent_layer, canvas, highlight_mask)

    canvas.save(OUT_PATH, dpi=(DPI, DPI))
    print(f"Wrote {OUT_PATH} ({CANVAS_W}x{CANVAS_H}px @ {DPI}dpi)")


if __name__ == "__main__":
    main()
