#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يولّد لوحة storyboard بصرية من spec مشتق من المكتبة — كل التوقيتات من الفهرس.

التشغيل: python3 scene-library/storyboard/make_visual.py
يقرأ spec-library.json + index.json ويرتّب معاينات المشاهد مع scene_id والتوقيت والكابشن.
يستخدم artext (HarfBuzz+FreeType) لتشكيل العربي الصحيح (بديل libraqm الغائب).
"""
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.dirname(HERE)
ROOT = os.path.dirname(LIB)
sys.path.insert(0, os.path.join(ROOT, "engine"))
import scene_library as SL  # noqa: E402
import artext as ART  # noqa: E402

FONT = os.path.join(ROOT, "assets", "fonts", "Tajawal-Bold.ttf")
if not os.path.isfile(FONT):
    FONT = os.path.join(ROOT, "assets", "fonts", "Cairo-Bold.ttf")


def main():
    spec = json.load(open(os.path.join(HERE, "spec-library.json"), encoding="utf-8"))
    idx = SL.load_index()
    by_id = {s["scene_id"]: s for s in idx["scenes"]}
    caps = {round(c["from"], 3): c["text"] for c in spec["captions"]}

    tw, th, lab = 320, 569, 104
    cols = 2
    n = len(spec["clips"])
    rows = (n + cols - 1) // cols
    header, footer = 130, 80
    W = cols * tw + 30
    H = header + rows * (th + lab) + footer
    canvas = Image.new("RGB", (W, H), (11, 18, 32))
    d = ImageDraw.Draw(canvas)

    def txt(x, y, s, px, fill, anchor="rt"):
        ART.render(canvas, (x, y), s, FONT, px, fill, anchor=anchor, direction="rtl")

    txt(W - 20, 26, "09c وزن الخروف — Storyboard من المكتبة", 25, (250, 204, 21))
    txt(W - 20, 64, "كل التوقيتات من الفهرس عبر scene_id — لا توقيتات يدوية", 18, (148, 163, 184))

    cursor = spec.get("hook_sec", 0.0)
    for i, clip in enumerate(spec["clips"]):
        s = by_id[clip["scene_id"]]
        r, c = divmod(i, cols)
        x, y = 15 + c * tw, header + r * (th + lab)
        prev = Image.open(os.path.join(SL.REPO, s["preview"])).convert("RGB").resize((tw - 10, th))
        canvas.paste(prev, (x, y))
        d.rectangle([x, y + th, x + tw - 10, y + th + lab], fill=(15, 23, 42))
        rx = x + tw - 16
        txt(rx, y + th + 8, f"{i + 1}. {s['scene_id']}  [{s['start']}–{s['end']}s]", 19, (250, 204, 21))
        cap = caps.get(round(cursor, 3), "")
        txt(rx, y + th + 40, f"المشهد: {cursor:.2f}–{cursor + (s['end'] - s['start']):.2f}s", 17, (226, 232, 240))
        txt(rx, y + th + 68, cap, 17, (134, 239, 172))
        cursor += s["end"] - s["start"]

    fy = header + rows * (th + lab) + 16
    total = cursor + spec["endcard_sec"]
    txt(W - 20, fy, f"+ إطار ختام {spec['endcard_sec']}s ← الإجمالي {total:.2f}s · المصدر: 01 + 04 (حقيقي، متتبع في git)", 18, (148, 163, 184))
    txt(W - 20, fy + 32, "المعاينات تعرض المصدر الخام (علامة LLC ظاهرة) — الرندر النهائي يخفيها بشريط الإثبات", 15, (100, 116, 139))
    out = os.path.join(HERE, "09c-storyboard-visual.png")
    canvas.save(out)
    print("saved", out, canvas.size)


if __name__ == "__main__":
    main()
