"""TerraNex — brand tokens، مصدر الحقيقة الوحيد = context/palette.json.

‏palette.json بيتولّد آليًا من الشعار الرسمي عبر engine/derive_palette.py.
ممنوع كتابة أي hex هنا — أي لون جديد يُشتق من الشعار ويُوثَّق في palette.json.
"""
from __future__ import annotations

import json
import os
import weakref
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# artext: محرك تشكيل عربي (HarfBuzz+FreeType) — بديل libraqm الغائب من عجلات Pillow.
try:
    import artext as _ART
except Exception:  # لو التبعيات مش متثبتة — نرجع لمسار PIL (لاتيني فقط صحيح)
    _ART = None

# سجل Draw→Image: يرسم artext على الصورة نفسها، وImageDraw ما بيحتفظش بمرجع ليها.
_DR2IMG: "weakref.WeakKeyDictionary" = weakref.WeakKeyDictionary()
_IMGDRAW_DRAW = ImageDraw.Draw


def _tracked_draw(im, mode=None):
    d = _IMGDRAW_DRAW(im, mode)
    _DR2IMG[d] = im
    return d


ImageDraw.Draw = _tracked_draw
_WARNED = {"fb": False}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
LOGO_DIR = os.path.join(ROOT, "assets", "logo")
PALETTE = os.path.join(ROOT, "context", "palette.json")
LOGO_FILE = "شعار-TerraNex.jpg"

# ---------- tokens: تُقرأ ولا تُكتب ----------
with open(PALETTE, encoding="utf-8") as _f:
    _PAL = json.load(_f)

C = dict(_PAL["final"])
# أسماء متوافقة مع بقية المحركات
C["gold_page"] = _PAL.get("page_vars", {}).get("gold", C["gold_mid"])
C["cream"] = C["bg_cream"]
C["white"] = "#FFFFFF"

FONTS = {
    "black": "Tajawal-Black.ttf",
    "extrabold": "Tajawal-ExtraBold.ttf",
    "bold": "Tajawal-Bold.ttf",
    "medium": "Tajawal-Medium.ttf",
    "regular": "Tajawal-Regular.ttf",
    "light": "Tajawal-Light.ttf",
}

PHONE = "01010154221"


# ---------- fonts ----------
@lru_cache(maxsize=128)
def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    path = os.path.join(FONT_DIR, FONTS.get(weight, FONTS["regular"]))
    if not os.path.exists(path):
        path = os.path.join(FONT_DIR, "Cairo-VF.ttf")
    f = ImageFont.truetype(path, size)
    # تُستخدم من artext للتشكيل الحقيقي
    f.art_path = path  # type: ignore[attr-defined]
    f.art_px = int(size)  # type: ignore[attr-defined]
    return f


# ---------- text ----------
def _fb_notice():
    if not _WARNED["fb"]:
        print("⚠️  artext غير متاح — الرجوع لمسار PIL (العربي قد لا يتشكّل صح)."
              " ثبّت التبعيات: bash setup.sh")
        _WARNED["fb"] = True


def text(draw, xy, s, f, fill, anchor="mm", stroke=0, stroke_fill=None, direction="rtl"):
    if _ART is not None:
        im = _DR2IMG.get(draw)
        if im is not None:
            _ART.render(im, xy, s, f.art_path, getattr(f, "art_px", f.size), fill,
                        anchor=anchor, stroke=stroke, stroke_fill=stroke_fill,
                        direction=direction)
            return
    _fb_notice()
    draw.text(xy, s, font=f, fill=fill, anchor=anchor, stroke_width=stroke,
              stroke_fill=stroke_fill)


def measure(s, f, direction="rtl") -> float:
    if _ART is not None:
        return _ART.measure(s, f.art_path, getattr(f, "art_px", f.size), direction)
    _fb_notice()
    return f.getlength(s)


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
# قاعده 19/10 (طلب المالك): الشعار يُقصّ من فراغه الأسود ويُعرض كبيرًا ومتناسقًا،
# والعلامة المائية موحّدة المكان والحجم في كل المحتوى. ممنوع اللوجو الصغير الطافي.
LOGO_MIN_LOCKUP_W = 300   # أقل عرض مقبول لقفل الشعار الكامل (كلمة TERRANEX مقروءة)
LOGO_MIN_EMBLEM = 96      # أقل قطر للرمز وحده (brand-kit §8)

# منطقة الإعلان المؤسسي: لا ذكر لمدينة. (B9 — محفور 19/10)
CITY_BAN = ("الإسكندرية", "الاسكندرية", "اسكندريه", "اسكندرية", "Alexandria", "ALEXANDRIA")


@lru_cache(maxsize=64)
def _logo_raw() -> Image.Image:
    p = os.path.join(LOGO_DIR, LOGO_FILE)
    if not os.path.exists(p):
        raise FileNotFoundError(f"الشعار الرسمي غير موجود: {p}")
    im = Image.open(p).convert("RGBA")
    import numpy as np
    a = np.asarray(im).astype(int)
    lum = a[..., :3].sum(2)
    alpha = np.clip((lum - 26) * 6, 0, 255).astype("uint8")
    im.putalpha(Image.fromarray(alpha))
    return im


@lru_cache(maxsize=64)
def logo(size: int = 400, part: str = "full") -> Image.Image:
    """يرجّع الشعار مقصوصًا من الفراغ (trim) ومقاسه مضبوط.

    part="full"   → الرمز + كلمة TERRANEX + سطر الوصف (للعرض الكبير)
    part="emblem" → الرمز الدائري فقط (للعلامة المائية والأحجام الصغيرة)
    size: العرض المطلوب (full) أو القطر (emblem) بالبكسل.
    """
    im = _logo_raw().copy()
    bbox = im.getchannel("A").getbbox()
    if bbox:
        im = im.crop(bbox)

    if part == "emblem":
        # نقتطع عند أول فراغ أفقي حقيقي بين الرمز وكلمة TERRANEX (مش نسبة تقريبية)
        import numpy as np
        rows = (np.asarray(im.getchannel("A")) > 12).sum(1)
        h = im.height
        gap_end = None
        for y in range(int(h * 0.42), int(h * 0.80)):
            if rows[y] == 0:
                run = 0
                y2 = y
                while y2 < h and rows[y2] == 0:
                    run += 1; y2 += 1
                if run >= 4:
                    gap_end = y
                    break
        cut = gap_end if gap_end else int(h * 0.66)
        im = im.crop((0, 0, im.width, cut))
        bb = im.getchannel("A").getbbox()
        if bb:
            im = im.crop(bb)
        target = max(int(size), LOGO_MIN_EMBLEM)
        im.thumbnail((target, target), Image.LANCZOS)
        return im

    target_w = max(int(size), LOGO_MIN_LOCKUP_W)
    if im.width < target_w:
        # نُكبّر من الأصل بجودة عالية بدل عرض الشعار صغيرًا
        scale = target_w / im.width
        im = im.resize((target_w, int(im.height * scale)), Image.LANCZOS)
    else:
        im.thumbnail((target_w, target_w * 2), Image.LANCZOS)
    return im


def place_logo(canvas: Image.Image, cx: int, cy: int, size: int = 400,
               part: str = "full", anchor: str = "mm") -> Image.Image:
    """يضع الشعار بحجم كبير في مكانه الصحيح ويرجّع حدود القفل (للتصميم التالي تحته)."""
    lg = logo(size, part)
    x = {"mm": cx - lg.width // 2, "lm": cx, "rm": cx - lg.width,
         "lt": cx, "rt": cx - lg.width}.get(anchor, cx - lg.width // 2)
    y = {"mm": cy - lg.height // 2, "lm": cy - lg.height // 2, "rm": cy - lg.height // 2,
         "lt": cy, "rt": cy}.get(anchor, cy - lg.height // 2)
    canvas.alpha_composite(lg, (int(x), int(y)))
    return (int(x), int(y), int(x) + lg.width, int(y) + lg.height)


def hairline(draw, x0, x1, y, color=None, w=2, alpha=255):
    draw.line([x0, y, x1, y], fill=hex2rgb(color or C["gold"]) + (alpha,), width=w)


def hairline(draw, x0, x1, y, color=None, w=2, alpha=255):
    draw.line([x0, y, x1, y], fill=hex2rgb(color or C["gold"]) + (alpha,), width=w)


def watermark(img: Image.Image, pos: str = "br", theme: str = "dark",
              alpha: int = 150, with_emblem: bool = True) -> Image.Image:
    """العلامة المائية الرسمية — مكان وحجم ثابتان في كل تصدير (بديل «TerraNex LLC»).

    مواصفات ثابتة (19/10): مقاس الكلمة 30px، الرمز 44px، هامش 44px من الحافة،
    شفافية 150/255 على الداكن، وتُوضع دائمًا داخل المنطقة الآمنة.
    """
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    color = C["cream"] if theme == "dark" else C["ink"]
    f = font("black", 30)
    label = "TerraNex"
    tw = int(measure(label, f, direction="ltr"))
    m = 44
    emb = logo(44, "emblem") if with_emblem else None
    gap = 14 if emb else 0
    total_w = (emb.width if emb else 0) + gap + tw
    total_h = max(emb.height if emb else 0, int(f.size * 1.2))

    if pos in ("br", "tr"):
        x0 = img.width - m - total_w
    else:
        x0 = m
    y0 = img.height - m - total_h if pos in ("br", "bl") else m

    if emb:
        lay.alpha_composite(emb, (int(x0), int(y0 + (total_h - emb.height) / 2)))
    tx = x0 + (emb.width + gap if emb else 0)
    text(d, (tx, y0 + total_h / 2), label, f, hex2rgb(color) + (alpha,),
         anchor="lm", direction="ltr")
    img.alpha_composite(lay)
    return img


def cover_patch(img: Image.Image, boxes, feather: int = 26) -> Image.Image:
    """يُخفي علامة محروقة في الفوتاج (زي «TerraNex LLC») بتمويه ناعم من الصورة نفسها.

    blur محلي + حواف متلاشية = غير ملحوظ على خلفية بسيطة (بدلة/قماش/سماء).
    """
    if not boxes:
        return img
    from PIL import ImageFilter
    rgb = img.convert("RGB")
    for (x0, y0, x1, y1) in boxes:
        x0, y0 = max(0, int(x0)), max(0, int(y0))
        x1, y1 = min(img.width, int(x1)), min(img.height, int(y1))
        if x1 <= x0 or y1 <= y0:
            continue
        patch = rgb.crop((x0, y0, x1, y1))
        strength = max(6, min(patch.width, patch.height) // 5)
        patch = patch.filter(ImageFilter.GaussianBlur(strength))
        mask = Image.new("L", patch.size, 255)
        md = ImageDraw.Draw(mask)
        for i in range(feather):
            v = int(255 * (i / feather))
            md.rectangle([i, i, patch.width - 1 - i, patch.height - 1 - i], outline=v)
        rgb.paste(patch, (x0, y0), mask)
    img.paste(rgb, (0, 0))
    return img
