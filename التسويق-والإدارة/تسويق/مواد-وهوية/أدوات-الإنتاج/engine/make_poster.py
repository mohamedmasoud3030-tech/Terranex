#!/usr/bin/env python3
"""بوستر TerraNex — 1080x1350 (فيد) أو 1080x1920 (ستوري).
الاستخدام:
  python engine/make_poster.py --headline "الوزن على الطبيعة" --stat 50 --unit "كجم" \
      --sub "الخروف قدامك على الميزان، مش كلام في بوست" --out output/poster.png
"""
from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brand as B  # noqa: E402

SIZES = {"feed": (1080, 1350), "story": (1080, 1920), "square": (1080, 1080)}


def build(headline, sub="", stat=None, unit="", kicker="استثمار حيواني · الإسكندرية",
          size="feed", theme="dark", phone=B.PHONE):
    """Layout مبني على قياس فعلي للنص، مش إحداثيات ثابتة."""
    W, H = SIZES[size]
    if theme == "light":
        base = B.vgradient((W, H), [(0.0, B.C["green_100"]), (1.0, B.C["cream"])]).convert("RGBA")
        ink, muted, accent = B.C["ink"], B.C["muted"], B.C["green_700"]
    else:
        base = B.vgradient((W, H), [(0.0, B.C["green_900"]), (0.55, B.C["green_800"]),
                                    (1.0, B.C["green_700"])]).convert("RGBA")
        ink, muted, accent = B.C["cream"], "#D9E6DF", B.C["gold"]

    if theme == "dark":
        base = B.glow(base, (int(W * 0.82), int(H * 0.12)), int(W * 0.62), B.C["gold"], alpha=38)
    base = B.vignette(base, 118 if theme == "dark" else 55)

    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    pad = int(W * 0.09)

    # ---------- header ----------
    hy = int(H * 0.095)
    B.place_logo(base, W // 2, hy - 4, 176)

    f_k = B.font("medium", 30)
    B.text(d, (W // 2, hy + 116), kicker, f_k, accent if theme == "dark" else B.C["gold_page"], anchor="mm")
    B.hairline(d, int(W * 0.36), int(W * 0.64), hy + 158, B.C["gold"], 2, 170)

    # ---------- measure middle block ----------
    fh = B.font("black", 100 if len(headline) <= 18 else 84)
    hlines = B.wrap(headline, fh, W - 2 * pad, max_lines=2)
    h_h = len(hlines) * int(fh.size * 1.16)

    stat_h = unit_h = 0
    fs = None
    if stat:
        fs = B.font("black", 250 if size != "square" else 210)
        stat_h = int(fs.size * 0.86)

    fsub = B.font("regular", 44)
    slines = B.wrap(sub, fsub, W - 2 * pad - 40, max_lines=3) if sub else []
    s_h = len(slines) * int(fsub.size * 1.5)

    k = 1.55 if size == "story" else 1.0
    gap1, gap2 = int(H * 0.042 * k), int(H * 0.038 * k)
    total = h_h + (gap1 + stat_h if stat else 0) + (gap2 + s_h if slines else 0)
    top_limit = int(H * 0.255)
    bot_limit = int(H * 0.795) if size != "story" else int(H * 0.775)
    y = top_limit + max(0, ((bot_limit - top_limit) - total) // 2)

    # ---------- headline ----------
    for ln in hlines:
        B.text(d, (W // 2, y + int(fh.size * 0.58)), ln, fh, ink, anchor="mm")
        y += int(fh.size * 1.16)

    # ---------- stat ----------
    if stat:
        y += gap1
        num = str(stat)
        wn = B.measure(num, fs, "ltr")
        wu = B.measure(unit, B.font("bold", 72)) if unit else 0
        block = wn + (wu + 28 if unit else 0)
        x_num = W // 2 + int(block / 2) - int(wn / 2)
        # soft glow behind the number (alpha-composited, لا يمسح ما قبله)
        gl = Image.new("L", (W, H), 0)
        ImageDraw.Draw(gl).ellipse([x_num - wn * 0.62, y + stat_h * 0.08,
                                    x_num + wn * 0.62, y + stat_h * 0.92], fill=58)
        gl = gl.filter(ImageFilter.GaussianBlur(58))
        halo = Image.new("RGBA", (W, H), B.hex2rgb(B.C["gold"]) + (0,))
        halo.putalpha(gl)
        lay.alpha_composite(halo)
        B.text(d, (x_num, y + stat_h * 0.52), num, fs, accent, anchor="mm", direction="ltr")
        if unit:
            fu = B.font("bold", 72)
            B.text(d, (x_num + wn / 2 + 28 + wu / 2, y + stat_h * 0.56), unit, fu, ink, anchor="mm")
        y += stat_h

    # ---------- sub ----------
    if slines:
        y += gap2
        for ln in slines:
            B.text(d, (W // 2, y + int(fsub.size * 0.6)), ln, fsub, muted, anchor="mm")
            y += int(fsub.size * 1.5)

    # ---------- footer ----------
    B.hairline(d, pad, W - pad, int(H * 0.878), B.C["gold"], 2, 85)
    f_foot = B.font("bold", 35)
    B.text(d, (W // 2, int(H * 0.912)), f"واتساب  {phone}", f_foot, ink, anchor="mm")
    f_small = B.font("regular", 26)
    B.text(d, (W // 2, int(H * 0.944)), "الإسكندرية · متابعة بالصور والوزن داخل الدورة", f_small, muted, anchor="mm")

    out = Image.alpha_composite(base, lay)
    B.watermark(out, label="TerraNex", pos="tl", alpha=110,
                color=B.C["cream"] if theme == "dark" else B.C["ink"])
    return out.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--headline", required=True)
    ap.add_argument("--sub", default="")
    ap.add_argument("--stat", default=None)
    ap.add_argument("--unit", default="")
    ap.add_argument("--kicker", default="استثمار حيواني · الإسكندرية")
    ap.add_argument("--size", default="feed", choices=list(SIZES))
    ap.add_argument("--theme", default="dark", choices=["dark", "light"])
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    img = build(a.headline, a.sub, a.stat, a.unit, a.kicker, a.size, a.theme)
    img.save(a.out, quality=95)
    print(f"OK {a.out} {img.size} {os.path.getsize(a.out)//1024}KB")


if __name__ == "__main__":
    main()
