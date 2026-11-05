#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""تحقّق فعلي من المعاينة الصامتة: هل الكابشن ظاهر داخل نافذته وغائب في الفواصل؟

يقيس عدد البكسلات البيضاء (نص الكابشن أبيض بضربة خضراء) في شريط الكابشن حول CAP_CY=0.70،
ويستخرج إطارات مراجعةscaled. لا يعدّل الفيديو ولا المشروع.
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, "engine")
import imageio_ffmpeg  # noqa: E402

FF = imageio_ffmpeg.get_ffmpeg_exe()
VIDEO = ("/home/user/Terranex/التسويق-والإدارة/تسويق/فيديوهات-المنتجة/"
         "creative-director/cd-followup-20s-voiced/preview-silent-v2.mp4")
HERE = os.path.dirname(os.path.abspath(__file__))
FRAMES = os.path.join(HERE, "preview-frames")
os.makedirs(FRAMES, exist_ok=True)
W, H = 1080, 1920
CY = int(H * 0.70)
BAND = (CY - 90, CY + 90)

SAMPLES = [
    (1.00, "hook-title-no-caption", False),
    (3.50, "L1-بنتابع-التغذية", True),
    (4.75, "gap-1", False),
    (6.50, "L2-على-أرض-الواقع", True),
    (8.25, "gap-2", False),
    (10.00, "L3-من-الحظيرة-وللمزرعة", True),
    (11.75, "gap-3", False),
    (14.00, "L4-متابعة-وتوثيق", True),
    (16.80, "gap-4", False),
    (18.50, "endcard-no-caption", False),
]


def frame(t):
    p = subprocess.run([FF, "-v", "error", "-ss", f"{t:.2f}", "-i", VIDEO,
                        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                       capture_output=True)
    if p.returncode != 0 or len(p.stdout) < W * H * 3:
        raise SystemExit(f"frame extraction failed at {t}: {p.stderr[-300:]}")
    return Image.frombytes("RGB", (W, H), p.stdout[:W * H * 3])


rows, ok = [], True
for t, label, expect in SAMPLES:
    img = frame(t)
    a = np.asarray(img.crop((0, BAND[0], W, BAND[1]))).astype(np.int16)
    # نص أبيض شبه خالص: كل القنوات عالية ومتقاربة
    white = int(((a.min(axis=2) > 225) & (a.max(axis=2) - a.min(axis=2) < 22)).sum())
    present = white > 1500
    good = (present == expect)
    ok = ok and good
    rows.append({"t": t, "label": label, "expect_caption": expect,
                 "white_text_pixels": white, "caption_detected": present, "as_expected": good})
    if expect or label.startswith("endcard") or label.startswith("hook"):
        img.resize((720, 1280), Image.LANCZOS).save(
            os.path.join(FRAMES, f"t{t:05.2f}-{label.split('-')[0]}.jpg"), quality=88)

report = {
    "video": os.path.relpath(VIDEO, "/home/user/Terranex"),
    "band_y": list(BAND),
    "method": "count of near-white pixels (caption glyphs) inside the caption band",
    "threshold_pixels": 1500,
    "all_as_expected": ok,
    "samples": rows,
    "note": ("الكابشن الخامس (17.20–19.70) يقع على كارت الخاتمة، ومحرك الرندر لا يرسم كابشن "
             "فوق الكارت؛ لذلك يُتوقع غياب أي كابشن عند 18.50 وهذا سلوك المحرك لا خطأ في المعاينة."),
}
with open(os.path.join(HERE, "preview-caption-check.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
    f.write("\n")
for r in rows:
    print(f"t={r['t']:>5.2f} white={r['white_text_pixels']:>6} detected={str(r['caption_detected']):>5} "
          f"expected={str(r['expect_caption']):>5} {'OK' if r['as_expected'] else 'MISMATCH'}  {r['label']}")
print("ALL AS EXPECTED:", ok)
print("frames:", sorted(os.listdir(FRAMES)))
