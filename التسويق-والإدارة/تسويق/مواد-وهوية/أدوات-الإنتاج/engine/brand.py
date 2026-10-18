"""TerraNex — brand tokens v2، مستخرجة من أصول الشركة نفسها.

المصادر (كلها من المستودع):
  • الشعار: التسويق-والإدارة/تسويق/مواد-وهوية/شعار-TerraNex.jpg
  • متغيرات صفحة العرض: سوق/مواد-وهوية/صفحة-العرض-التفاعلية.html
الألوان أدناه مستخرجة بالبكسل من الشعار — مش تقدير.
"""
from __future__ import annotations

import os
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
LOGO_DIR = os.path.join(ROOT, "assets", "logo")

# ---------- tokens v2 (من الشعار + صفحة العرض) ----------
C = {
    # ‏من الشعار (عينات البكسل)
    "gold_hi":   "#F0D070",   # ذهبي فاتح — لمعة
    "gold":      "#D0A858",   # ذهبي أساسي (متوسط الشعار)
    "gold_deep": "#B08020",   # ذهبي غامق — ظل/حدود
    "green_logo":"#225C33",   # أخضر الشعار
    # ‏من صفحة العرض التفاعلية
    "green_900": "#07271E",
    "green_800": "#0B3D2E",   # --green
    "green_700": "#115E43",   # --green2
    "green_100": "#E7F2EC",   # --green3
    "gold_page": "#C9A227",   # --gold
    "gold_page2":"#F3D97B",   # --gold2
    "cream":     "#FBF7EC",   # --cream
    "ink":       "#17352B",   # --ink
    "muted":     "#5E7268",
    "white":     "#FFFFFF",
}

FONTS = {
    "black": "Tajawal-Black.ttf",
    "extrabold": "Tajawal-ExtraBold.ttf",
    "bold": "Tajawal-Bold.ttf",
    "medium": "Tajawal-Medium.ttf",
    "regular": "Tajawal-Regular.ttf",
    "light": "Tajawal-Light.ttf",
}

PHONE = "01010154221"
LOGO_FILE = "شعار-TerraNex.jpg"


# ---------- fonts ----------
@lru_cache(maxsize=128)
def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    path = os.path.join(FONT_DIR, FONTS.get(weight, FONTS["regular"]))
    if not os.path.exists(path):
        path = os.path.join(FONT_DIR, "Cairo-VF.ttf")
    return ImageFont.truetype(path, size)


# ---------- text ----------
def text(draw, xy, s, f, fill, anchor="mm", stroke=0, stroke_fill=None, direction="rtl"):
    draw.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=stroke,
              stroke_fill=stroke_fill, direction=direction, language="ar",
              features=["kern", "liga", "calt"])


def measure(s, f, direction="rtl") -> float:
    return f.getlength(s, direction=direction, language="ar")


def wrap(s, f, max_w, max_lines=3):
    words, lines, cur = s.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if measure(t, f) <= max_w or not cur:
            cur = t
        else:
            lines.append(cur); cur = w
            if len(lines) == max_lines:
                break
    if cur and len(lines) < max_lines:
        lines.append(cur)
    return lines


# ---------- colors/background ----------
def hex2rgb(x):
    x = x.lstrip("#")
    return tuple(int(x[i:i + 2], 16) for i in (0, 2, 4))


def vgradient(size, stops):
    w, h = size
    col = Image.new("RGB", (1, h)); px = col.load()
    stops = sorted([(t, hex2rgb(c) if isinstance(c, str) else c) for t, c in stops])
    for y in range(h):
        t = y / max(1, h - 1)
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]; t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                k = (t - t0) / max(1e-6, t1 - t0)
                px[0, y] = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
                break
    return col.resize((w, h), Image.BILINEAR)


def glow(base, center, radius, color, alpha=60):
    w, h = base.size
    layer = Image.new("L", (w, h), 0); d = ImageDraw.Draw(layer)
    cx, cy = center
    for i in range(18, 0, -1):
        r = radius * i / 18
        d.ellipse([cx - r, cy - r * 1.15, cx + r, cy + r * 1.15], fill=int(alpha * (1 - i / 18) ** 1.6))
    layer = layer.filter(ImageFilter.GaussianBlur(radius // 6))
    tint = Image.new("RGB", (w, h), hex2rgb(color))
    base.paste(Image.composite(tint, base, layer), (0, 0))
    return base


def vignette(img, strength=115):
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse([-w * .35, -h * .25, w * 1.35, h * 1.25], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(min(w, h) // 8))
    dark = Image.new("RGB", (w, h), (0, 0, 0))
    return Image.composite(dark, img, m.point(lambda v: int((255 - v) * strength / 255)))


# ---------- الشعار الرسمي ----------
@lru_cache(maxsize=64)
def logo(size: int, knockout_bg=True) -> Image.Image:
    """يرجّع الشعار الرسمي بخلفية شفافة (الأسود بقى alpha=0)."""
    p = os.path.join(LOGO_DIR, LOGO_FILE)
    if not os.path.exists(p):
        raise FileNotFoundError(f"الشعار الرسمي غير موجود: {p}")
    im = Image.open(p).convert("RGBA")
    if knockout_bg:
        import numpy as np
        a = np.asarray(im).astype(int)
        lum = a[..., :3].sum(2)
        alpha = np.clip((lum - 26) * 6, 0, 255).astype("uint8")
        im.putalpha(Image.fromarray(alpha))
    im.thumbnail((size, size), Image.LANCZOS)
    return im


def place_logo(canvas: Image.Image, cx: int, cy: int, size: int = 120):
    lg = logo(size)
    canvas.alpha_composite(lg, (int(cx - lg.width / 2), int(cy - lg.height / 2)))


def hairline(draw, x0, x1, y, color=None, w=2, alpha=255):
    draw.line([x0, y, x1, y], fill=hex2rgb(color or C["gold"]) + (alpha,), width=w)


def watermark(img, label="TerraNex", pos="tl", alpha=105, color=None):
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    f = font("medium", 22)
    xy = {"tl": (40, 38), "tr": (img.width - 40, 38)}.get(pos, (40, 38))
    d.text(xy, label, font=f, fill=hex2rgb(color or C["cream"]) + (alpha,), anchor="la", direction="ltr")
    img.alpha_composite(lay)
