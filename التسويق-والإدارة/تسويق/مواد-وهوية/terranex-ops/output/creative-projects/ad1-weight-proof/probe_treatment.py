#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مِسبار المعالجة: إطارات 1080×1920 حقيقية عبر سلسلة فلاتر المحرّك نفسها قبل أي مونتاج.

يجيب بالنظر لا بالتخمين على ثلاثة أسئلة:
  ١) أين يجلس شريط الكابشن الثابت دون أن يغطي الحيوان أو علامة الميزان؟
  ٢) هل القصّ المقترح يحفظ الجسم كاملًا والاتجاه صحيح بعد الدوران؟
  ٣) هل المادة القديمة الأعلى دقة تستحق مكانها في المزج؟
"""
import json
import os
import subprocess
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MARK = os.path.abspath(os.path.join(OPS, "..", ".."))
sys.path.insert(0, os.path.join(OPS, "engine"))
import reel_build as R  # noqa: E402

EV = os.path.join(HERE, "evidence")
os.makedirs(EV, exist_ok=True)
mm = json.load(open(os.path.join(HERE, "media-manifest.json"), encoding="utf-8"))
P = {a["asset_id"]: a for a in mm["assets"]}
OLD = {
    "old-s01-08": ("فيديوهات-جاهزة-للنشر/01-بومو-الشركة-الرئيسي.mp4", 20.0,
                   {"top": 0.07}, False, "أبقار عند حاجز التبن — 720×1280"),
    "old-s01-03": ("فيديوهات-جاهزة-للنشر/01-بومو-الشركة-الرئيسي.mp4", 11.5,
                   {"bottom": 0.14}, False, "أبقار عند الحاجز — 720×1280"),
    "old-s04-04": ("فيديوهات-جاهزة-للنشر/04-الأربعاء-الوزن-على-الطبيعة.mp4", 16.0,
                   {"left": 0.09, "right": 0.02}, True, "وزن حقلي قديم — 720×1280"),
    "old-s03-w01": ("فيديوهات-جاهزة-للنشر/03-الثلاثاء-سؤال-تفاعلي.mp4", 9.8,
                    {"bottom": 0.30}, False, "كبش كامل — نص سؤال محروق"),
}
NEW = [
    ("gh-a27", 2.9, {}, False, "الميزان + الكبش — اللقطة البطلة"),
    ("gh-a27", 8.3, {}, False, "الميزان — زاوية لاحقة"),
    ("gh-a25", 2.0, {}, False, "لوحة العلامة مقروءة"),
    ("gh-a25", 6.0, {}, False, "الوزن — الفعل"),
    ("gh-a43", 6.3, {}, False, "القطيع متحرك"),
    ("gh-a43", 31.7, {}, False, "القطيع — نافذة ثانية"),
    ("gh-a26", 4.8, {}, False, "كبش واقف كامل"),
    ("gh-a33", 12.0, {}, False, "كبش مرقّط — علامة محروقة أسفل"),
    ("gh-a38", 15.0, {}, False, "فحص الأسنان"),
    ("gh-a16", 2.6, {}, False, "تثبيت هادئ"),
    ("gh-a31", 1.3, {}, False, "وضع في الميزان — 2.63ث فقط"),
    ("gh-a08", None, {}, False, "صف التغذية — صورة"),
    ("gh-a02", None, {}, False, "الميزان فارغًا — صورة"),
    ("gh-a06", None, {}, False, "حيوانات نظيفة — صورة"),
]


def frame(path, t, crop, out_png):
    """يشغّل سلسلة فلاتر المحرّك نفسها على إطار واحد ويحفظه بالحجم النهائي."""
    c = {"crop": crop or {"top": 0.0}, "sharpen": False, "scale_flags": "lanczos"}
    vf = R._clip_vf(c)
    if t is None:
        cmd = [R.ff(), "-y", "-v", "error", "-i", path, "-vf", vf, "-frames:v", "1", "-q:v", "2", out_png]
    else:
        cmd = [R.ff(), "-y", "-v", "error", "-ss", str(t), "-i", path,
               "-vf", vf, "-frames:v", "1", "-q:v", "2", out_png]
    subprocess.run(cmd, check=True, capture_output=True)
    return Image.open(out_png).convert("RGB")


def sheet(tiles, out, cols, title, thumb=(270, 480)):
    pad, lab, head = 10, 44, 46
    rows = (len(tiles) + cols - 1) // cols
    W = cols * (thumb[0] + pad) + pad
    H = head + rows * (thumb[1] + lab + pad) + pad
    s = Image.new("RGB", (W, H), (18, 26, 20))
    d = ImageDraw.Draw(s)
    d.text((pad + 4, 15), title[:120], fill=(230, 215, 160))
    for i, (im, l1, l2) in enumerate(tiles):
        r, c = divmod(i, cols)
        x = pad + c * (thumb[0] + pad)
        y = head + r * (thumb[1] + lab + pad)
        t = im.copy()
        t.thumbnail(thumb, Image.LANCZOS)
        s.paste(t, (x + (thumb[0] - t.width) // 2, y))
        d.text((x + 2, y + thumb[1] + 3), l1[:40], fill=(235, 235, 235))
        d.text((x + 2, y + thumb[1] + 21), l2[:40], fill=(150, 200, 160))
    s.save(out, quality=88)
    return out


rows, tiles = [], []
for aid, t, crop, pb, note in NEW:
    a = P[aid]
    src = os.path.join(HERE, a["staged_path"])
    png = os.path.join(EV, f"probe-{aid}-{t if t is not None else 'img'}.jpg")
    im = frame(src, t, crop, png)
    geo = f'{a["display_geometry"][0]}x{a["display_geometry"][1]}'
    up = round(1920 / a["display_geometry"][1], 2) if a["kind"] == "video" else round(
        1920 / a["display_geometry"][1], 2)
    tiles.append((im, f'{aid} t={t}', f'{geo} → 1080x1920 ({up}x)'))
    rows.append({"id": aid, "t": t, "source_geometry": geo, "upscale": up, "note": note,
                 "probe": os.path.relpath(png, HERE)})
for aid, (rel, t, crop, pb, note) in OLD.items():
    src = os.path.join(MARK, rel)
    png = os.path.join(EV, f"probe-{aid}.jpg")
    im = frame(src, t, crop, png)
    tiles.append((im, f'{aid} t={t}', f'720x1280 → 1080x1920 (1.5x)'))
    rows.append({"id": aid, "t": t, "source_geometry": "720x1280", "upscale": 1.5,
                 "note": note, "probe": os.path.relpath(png, HERE), "crop": crop,
                 "proof_bar": pb})
sheet(tiles, os.path.join(EV, "PROBE-01-composition.jpg"), 6,
      "AD-1 treatment probe :: real 1080x1920, lanczos, NO artificial sharpening")

# مِسبار شريط الكابشن: نفس الإطار بأربعة مواضع للشريط الثابت
band_tiles = []
for aid, t in [("gh-a27", 2.9), ("gh-a43", 6.3), ("gh-a38", 15.0), ("gh-a26", 4.8)]:
    a = P[aid]
    base = Image.open(os.path.join(EV, f"probe-{aid}-{t}.jpg")).convert("RGBA")
    for cy in (0.70, 0.78, 0.84):
        im = base.copy()
        im.alpha_composite(R.topbar())
        im.alpha_composite(R.bottom_band())
        im.alpha_composite(R.cap_layer("الوزن قدامك… مش كلام.", cy))
        d = ImageDraw.Draw(im)
        y = int(1920 * cy)
        d.line([(0, y), (1080, y)], fill=(255, 90, 90), width=3)
        band_tiles.append((im.convert("RGB"), f'{aid} cy={cy}', "الخط الأحمر = منتصف الشريط"))
sheet(band_tiles, os.path.join(EV, "PROBE-02-caption-band.jpg"), 6,
      "Caption band placement :: does it cover the animal or the scale logo?")
json.dump(rows, open(os.path.join(EV, "probe-treatment.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("probe frames:", len(rows), "| band variants:", len(band_tiles))
