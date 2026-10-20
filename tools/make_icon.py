"""Draws the app icon (road-sign triangle with a check mark).

Usage: python tools/make_icon.py <out_dir>
Writes icon.png (full icon) and icon_foreground.png (Android adaptive foreground).
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersampling factor


def triangle_points(cx, cy, size):
    h = size * math.sqrt(3) / 2
    return [(cx, cy - h * 2 / 3), (cx + size / 2, cy + h / 3), (cx - size / 2, cy + h / 3)]


def rounded_polygon(draw, pts, radius, fill):
    # Draw a polygon with rounded corners by unioning a shrunk polygon and circles.
    cx = sum(p[0] for p in pts) / 3
    cy = sum(p[1] for p in pts) / 3
    inner = []
    for x, y in pts:
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        k = (d - radius * 2) / d
        inner.append((cx + dx * k, cy + dy * k))
    for i in range(3):
        a, b = inner[i], inner[(i + 1) % 3]
        draw.line([a, b], fill=fill, width=int(radius * 2))
    draw.polygon(inner, fill=fill)
    for x, y in inner:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


def sign(size_px, scale):
    img = Image.new("RGBA", (size_px, size_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size_px / 2
    tri = scale * size_px
    cy = c + tri * 0.06
    rounded_polygon(d, triangle_points(c, cy, tri), tri * 0.06, (211, 47, 47, 255))
    rounded_polygon(d, triangle_points(c, cy + tri * 0.035, tri * 0.68), tri * 0.035, (255, 255, 255, 255))
    # check mark
    w = tri * 0.07
    p1 = (c - tri * 0.135, cy + tri * 0.075)
    p2 = (c - tri * 0.04, cy + tri * 0.165)
    p3 = (c + tri * 0.125, cy - tri * 0.035)
    d.line([p1, p2, p3], fill=(30, 58, 138, 255), width=int(w), joint="curve")
    for p in (p1, p3):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=(30, 58, 138, 255))
    return img


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    big = S * SS

    bg = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    grad = Image.new("RGBA", (big, big))
    gd = ImageDraw.Draw(grad)
    top, bottom = (37, 99, 235), (30, 58, 138)
    for y in range(big):
        t = y / big
        col = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        gd.line([(0, y), (big, y)], fill=col)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.22), fill=255)
    bg.paste(grad, (0, 0), mask)

    s = sign(big, 0.78)
    shadow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (0, int(big * 0.012)), s)
    shadow = shadow.filter(ImageFilter.GaussianBlur(big * 0.012))
    icon = Image.alpha_composite(bg, shadow)
    icon = Image.alpha_composite(icon, s)
    icon.resize((S, S), Image.LANCZOS).save(out / "icon.png")

    fg = sign(big, 0.52)
    fg.resize((S, S), Image.LANCZOS).save(out / "icon_foreground.png")


if __name__ == "__main__":
    main()
