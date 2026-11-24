#!/usr/bin/env python3
"""Generate the iOS app icon asset catalog for ADB Helper.

Usage: python3 scripts/gen_icon.py
Requires Pillow. The icon is drawn at 4x and downsampled for crisp edges.
"""

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
K = 4  # supersampling factor


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def make_icon():
    size = S * K
    img = Image.new("RGB", (size, size), (9, 22, 38))
    px = img.load()

    # Vertical deep-navy gradient with a soft teal glow behind the terminal.
    top, bottom = (12, 30, 52), (5, 14, 27)
    for y in range(size):
        t = y / size
        color = lerp(top, bottom, t)
        for x in range(size):
            px[x, y] = color

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((size * 0.12, size * 0.18, size * 0.92, size * 0.98), fill=(38, 214, 185, 62))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.10))
    img = Image.alpha_composite(img.convert("RGBA"), glow)

    d = ImageDraw.Draw(img)

    # Subtle grid, like a terminal backdrop.
    grid = (255, 255, 255, 10)
    for i in range(1, 9):
        x = size * (0.18 + 0.64 * i / 9)
        d.line((x, size * 0.37, x, size * 0.79), fill=grid, width=1 * K)
    for i in range(1, 7):
        y = size * 0.37 + size * 0.42 * i / 7
        d.line((size * 0.18, y, size * 0.82, y), fill=grid, width=1 * K)

    # Terminal window.
    bx = (int(size * 0.16), int(size * 0.24), int(size * 0.84), int(size * 0.79))
    rounded(d, bx, radius=int(size * 0.075), fill=(9, 26, 44, 235), outline=(86, 227, 201, 150), width=3 * K)

    # Title bar separator and traffic lights.
    bar_y = int(size * 0.365)
    d.line((bx[0] + 20 * K, bar_y, bx[2] - 20 * K, bar_y), fill=(120, 180, 200, 70), width=2 * K)
    for cx, color in zip((0.235, 0.285, 0.335), [(255, 105, 105), (255, 205, 95), (92, 220, 160)]):
        r = 9 * K
        x, y = size * cx, size * 0.303
        d.ellipse((x - r, y - r, x + r, y + r), fill=color + (230,))

    # Prompt chevron ">" in mint.
    mint = (91, 237, 205, 255)
    chev_x, chev_y = size * 0.30, size * 0.51
    arm = size * 0.10
    thick = 20 * K
    d.line((chev_x, chev_y - arm, chev_x + arm * 0.82, chev_y), fill=mint, width=thick)
    d.line((chev_x + arm * 0.82, chev_y, chev_x, chev_y + arm), fill=mint, width=thick)
    # Round the joints.
    r = thick // 2
    d.ellipse((chev_x - r, chev_y - arm - r, chev_x + r, chev_y - arm + r), fill=mint)
    d.ellipse((chev_x + arm * 0.82 - r, chev_y - r, chev_x + arm * 0.82 + r, chev_y + r), fill=mint)
    d.ellipse((chev_x - r, chev_y + arm - r, chev_x + r, chev_y + arm + r), fill=mint)

    # Underscore cursor.
    uy = size * 0.68
    d.rounded_rectangle((size * 0.49, uy, size * 0.70, uy + 20 * K), radius=10 * K, fill=mint)

    # Wi-Fi arcs, hinting at wireless ADB.
    wx, wy = size * 0.70, size * 0.52
    arc_color = (255, 255, 255, 210)
    for idx, radius in enumerate((0.055, 0.095, 0.135)):
        r = size * radius
        box = (wx - r, wy - r, wx + r, wy + r)
        d.arc(box, start=205, end=335, fill=arc_color, width=10 * K)
    d.ellipse((wx - 8 * K, wy - 8 * K, wx + 8 * K, wy + 8 * K), fill=arc_color)

    out = img.convert("RGB").resize((S, S), Image.Resampling.LANCZOS)
    return out


def main():
    root = Path(__file__).resolve().parents[1]
    assets = root / "ADBHelper" / "Assets.xcassets" / "AppIcon.appiconset"
    assets.mkdir(parents=True, exist_ok=True)
    make_icon().save(assets / "icon-1024.png", optimize=True)
    contents = {
        "images": [
            {
                "filename": "icon-1024.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (assets / "Contents.json").write_text(json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {assets / 'icon-1024.png'}")


if __name__ == "__main__":
    main()
