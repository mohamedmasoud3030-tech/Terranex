"""artext.py — محرك تشكيل النص العربي لـ TerraNex.

المشكلة: عجلة Pillow على PyPI مبنية بدون libraqm (ولا يوجد libraqm/fribidi في
النظام، ولا وصول لapt). بدون raqm، الرسم بـImageDraw.text(direction='rtl')
بيفشل، والرسم العادي بيطلّع حروف عربية مقطّعة.

الحل: نفس الحزمة اللي raqm ملفوف حواليها بالظبط:
  • python-bidi  → ترتيب اتجاهي (يحل محل fribidi)
  • uharfbuzz    → تشكيل GSUB/GPOS كامل (ligatures/kerning/contextual forms)
  • freetype-py  → راسترايز للـglyph IDs الناتجة (libfreetype مدموجة في العجلة)

النتيجة: تشكيل عربي احترافي مطابق لأي مصمم جاد — بدون أي مكتبة نظام خارجية.

الواجهة (تُستخدم عبر brand.py، مش مباشرة):
  render(img, xy, s, font_path, px, fill, anchor, stroke, stroke_fill, direction)
  measure(s, font_path, px, direction) -> float

لا شبكة، لا أسرار، لا كتابة على القرص.
"""
from __future__ import annotations

from functools import lru_cache

import numpy as np
from PIL import Image, ImageFilter

import uharfbuzz as hb
import freetype
from bidi.algorithm import get_display

_AR = "\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF"


def _has_arabic(s: str) -> bool:
    return any(c.isalpha() and any(a <= c <= b for a, b in
               (("\u0600", "\u06FF"), ("\u0750", "\u077F"),
                ("\uFB50", "\uFDFF"), ("\uFE70", "\uFEFF"))) for c in s)


# ---------- وجوه open ---------- #
@lru_cache(maxsize=32)
def _hb_face(path: str):
    with open(path, "rb") as f:
        face = hb.Face(f.read())
    font = hb.Font(face)
    font.scale = (face.upem, face.upem)
    return face, font


@lru_cache(maxsize=32)
def _ft_face(path: str, px: int):
    face = freetype.Face(path)
    face.set_pixel_sizes(0, px)
    return face


# ---------- تشكيل ---------- #
@lru_cache(maxsize=4096)
def _shape(s: str, path: str, px: int, direction: str):
    """يعيد قائمة glyphs: (gid, x_adv, x_off, y_off) بوحدات البكسل."""
    rtl = direction != "ltr"
    if rtl or _has_arabic(s):
        order = get_display(s, base_dir="R" if rtl else "L")
    else:
        order = s
    face, font = _hb_face(path)
    buf = hb.Buffer()
    buf.add_str(order)
    buf.direction = "ltr"            # bidi اتطبق فوق — التدفق بقي بصري LTR
    buf.script = "arab" if _has_arabic(s) else "latn"
    buf.language = "ar" if _has_arabic(s) else "en"
    hb.shape(font, buf, {"kern": True, "liga": True, "calt": True})
    k = px / face.upem
    out = []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        out.append((info.codepoint,
                    pos.x_advance * k,
                    pos.x_offset * k,
                    pos.y_offset * k))
    return tuple(out)


@lru_cache(maxsize=8192)
def _raster_glyph(path: str, px: int, gid: int):
    """يعيد (mask:PIL L, left, top) لـglyph واحد."""
    face = _ft_face(path, px)
    face.load_glyph(gid, freetype.FT_LOAD_DEFAULT)
    slot = face.glyph
    slot.render(freetype.FT_RENDER_MODE_NORMAL)
    bmp = slot.bitmap
    if bmp.rows and bmp.width:
        arr = np.frombuffer(bytes(bmp.buffer), dtype=np.uint8)
        arr = arr[: bmp.rows * bmp.pitch].reshape(bmp.rows, bmp.pitch)[:, : bmp.width]
        mask = Image.fromarray(arr, mode="L")
    else:
        mask = Image.new("L", (max(1, bmp.width), max(1, bmp.rows)), 0)
    return mask, slot.bitmap_left, slot.bitmap_top


# ---------- قياس ---------- #
def measure(s: str, font_path: str, px: int, direction: str = "rtl") -> float:
    if not s:
        return 0.0
    return sum(g[1] for g in _shape(s, font_path, px, direction))


# ---------- بناء قناع الحبر ---------- #
@lru_cache(maxsize=2048)
def _ink_mask(s: str, path: str, px: int, direction: str):
    """يعيد (mask, pos, size, advance):
       pos = موضع لصق القناع لما يكون pen origin = (0, 0) و baseline = y0."""
    glyphs = _shape(s, path, px, direction)
    if not glyphs:
        return Image.new("L", (1, 1), 0), (0, 0), (1, 1), 0.0
    pen_x = 0.0
    runs = []
    min_x, min_y, max_x, max_y = 0.0, 0.0, 0.0, 0.0
    for gid, adv, xo, yo in glyphs:
        mask, left, top = _raster_glyph(path, px, gid)
        gx, gy = pen_x + xo + left, -top + yo
        runs.append((mask, gx, gy))
        min_x, min_y = min(min_x, gx), min(min_y, gy)
        max_x, max_y = max(max_x, gx + mask.width), max(max_y, gy + mask.height)
        pen_x += adv
    w = max(1, int(round(max_x - min_x)))
    h = max(1, int(round(max_y - min_y)))
    canvas = Image.new("L", (w, h), 0)
    for mask, gx, gy in runs:
        canvas.paste(mask, (int(round(gx - min_x)), int(round(gy - min_y))), mask)
    # pos بالنسبة لـ(0,0): الحبر شمال القلم بمقدار min_x، وفوق البيسلاين بمقدار -min_y
    return canvas, (int(round(min_x)), int(round(min_y))), (w, h), pen_x


# ---------- رسم ---------- #
def render(img: Image.Image, xy, s: str, font_path: str, px: int, fill,
           anchor: str = "mm", stroke: int = 0, stroke_fill=None,
           direction: str = "rtl") -> None:
    """يرسم على صورة PIL (RGB أو RGBA). anchor بنمط Pillow: l/m/r + a/m/s/d."""
    if not s:
        return
    mask, (ox, oy), (w, h), _adv = _ink_mask(s, font_path, px, direction)

    def _norm(c, default):
        if c is None:
            return default
        if isinstance(c, str):
            h = c.lstrip("#")
            c = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
        return tuple(c)

    fill = _norm(fill, (255, 255, 255, 255))
    stroke_fill = _norm(stroke_fill, None)

    # القناع يبدأ بالفعل من حدود الحبر الدقيقة، فموضع اللصق P يتحدد مباشرة من الـanchor.
    # (0,0) في القناع = نقطة (ox, oy) بالنسبة لأصل القلم — يُستخدم في 's' (البيسلاين).
    x, y = xy
    ha, va = anchor[0], (anchor[1] if len(anchor) > 1 else "m")
    if ha == "l":
        x0 = x
    elif ha == "r":
        x0 = x - w
    else:  # 'm' — منتصف الحبر الفعلي
        x0 = x - w / 2
    if va == "a":      # أعلى الحبر
        y0 = y
    elif va == "s":    # سطر الأساس
        y0 = y + oy
    elif va == "d":    # أسفل الحبر
        y0 = y - h
    else:              # 'm' — منتصف الحبر الفعلي
        y0 = y - h / 2
    px0, py0 = int(round(x0)), int(round(y0))

    rgba = tuple(fill) + (255,) if len(fill) == 3 else tuple(fill)
    alpha = rgba[3] if len(rgba) == 4 else 255

    if stroke and stroke > 0:
        sf = tuple(stroke_fill) + (255,) if stroke_fill and len(stroke_fill) == 3 \
            else (tuple(stroke_fill) if stroke_fill else (0, 0, 0, 255))
        smask = mask.filter(ImageFilter.MaxFilter(2 * stroke + 1))
        # موضع قناع الحدود يتحرك بمقدار stroke في الاتجاهات كلها
        s_off = stroke
        layer = Image.new("RGBA", (smask.width, smask.height), sf[:3] + (0,))
        a = smask
        if sf[3] < 255:
            a = smask.point(lambda v: v * sf[3] // 255)
        img.paste(Image.new("RGBA", smask.size, sf), (px0 - s_off, py0 - s_off), a)

    if alpha < 255:
        mask = mask.point(lambda v: v * alpha // 255)
    img.paste(Image.new("RGBA", mask.size, rgba[:3] + (255,)), (px0, py0), mask)
