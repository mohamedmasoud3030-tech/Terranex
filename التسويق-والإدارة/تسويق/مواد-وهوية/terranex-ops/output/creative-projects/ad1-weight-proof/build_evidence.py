#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يبني أدلة AD-1 من المعاينتين المُرندَرتين فعلًا — لا من المصادر.

المخرجات: storyboard لكل نسخة، ورقة مقارنة A/B على نفس الزمن، وقياسات جودة لكل لقطة.
تسميات الأوراق باللاتينية لأن PIL الافتراضي لا يشكّل العربية (الصندوق □ ليس عطلًا في الفيديو).
"""
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(OPS, "engine"))
import reel_build as R  # noqa: E402

EV = os.path.join(HERE, "evidence")
os.makedirs(EV, exist_ok=True)


def grab(video, t, out_jpg):
    """يفكّ الإطار بلا فقد للقياس، ويحفظ JPEG خفيفًا للورقة فقط.

    القياس على JPEG مُعاد ضغطه يخفض تباين الحدة كذبًا؛ فنقيس على البايتات الخام
    ونحفظ المضغوط للعرض لا للقياس.
    """
    r = subprocess.run([R.ff(), "-v", "error", "-ss", f"{t:.3f}", "-i", video,
                        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                       check=True, capture_output=True)
    im = Image.frombytes("RGB", (R.W, R.H), r.stdout[:R.W * R.H * 3])
    im.save(out_jpg, quality=88)
    return im


def metrics(im):
    a = np.asarray(im.convert("L").resize((540, 960)), dtype=np.float32)
    gx = np.abs(np.diff(a, axis=1)).mean()
    gy = np.abs(np.diff(a, axis=0)).mean()
    lap = a[1:-1, 1:-1] * 4 - a[:-2, 1:-1] - a[2:, 1:-1] - a[1:-1, :-2] - a[1:-1, 2:]
    return {"sharpness_var": round(float(lap.var()), 2),
            "edge_mean": round(float((gx + gy) / 2), 3),
            "luma_mean": round(float(a.mean()), 2),
            "luma_std": round(float(a.std()), 2),
            "white_clip": round(float((a > 250).mean()), 4),
            "black_clip": round(float((a < 6).mean()), 4)}


def sheet(tiles, out, cols, title, thumb=(252, 448)):
    pad, lab, head = 10, 46, 48
    rows = (len(tiles) + cols - 1) // cols
    W = cols * (thumb[0] + pad) + pad
    H = head + rows * (thumb[1] + lab + pad) + pad
    s = Image.new("RGB", (W, H), (18, 26, 20))
    d = ImageDraw.Draw(s)
    d.text((pad + 4, 16), title[:130], fill=(230, 215, 160))
    for i, (im, l1, l2) in enumerate(tiles):
        r, c = divmod(i, cols)
        x = pad + c * (thumb[0] + pad)
        y = head + r * (thumb[1] + lab + pad)
        t = im.copy()
        t.thumbnail(thumb, Image.LANCZOS)
        s.paste(t, (x + (thumb[0] - t.width) // 2, y))
        d.text((x + 2, y + thumb[1] + 4), l1[:42], fill=(235, 235, 235))
        d.text((x + 2, y + thumb[1] + 23), l2[:42], fill=(150, 200, 160))
    s.save(out, quality=88)
    return out


report = {}
for v in ("a", "b"):
    spec = json.load(open(os.path.join(HERE, f"spec-{v}.json"), encoding="utf-8"))
    video = os.path.join(HERE, f"preview-{v}-silent.mp4")
    tiles, shots = [], []
    for i, c in enumerate(spec["clips"], 1):
        t0, t1 = c["_timeline"]
        mid = round((t0 + t1) / 2, 3)
        png = os.path.join(EV, f"frame-{v}-{i:02d}.jpg")
        im = grab(video, mid, png)
        m = metrics(im)
        shots.append({"shot": i, "asset": c["_asset_id"], "timeline": [t0, t1],
                      "sampled_at": mid, "source_window": [c["start"], c["end"]],
                      "source_geometry": c["_source_geometry"],
                      "rotation_degrees": c.get("_rotation", 0),
                      "upscale": c["_upscale_to_1080x1920"], "role": c["_role"],
                      "rendered_metrics": m,
                      "frame": os.path.relpath(png, HERE)})
        tiles.append((im, f'{v.upper()} #{i}  {t0:.1f}-{t1:.1f}s  {c["_asset_id"]}',
                      f'up={c["_upscale_to_1080x1920"]}x sharp={m["sharpness_var"]:.0f}'))
    # إطار الكارت الختامي
    png = os.path.join(EV, f"frame-{v}-endcard.jpg")
    im = grab(video, 18.5, png)
    tiles.append((im, f'{v.upper()} endcard 17.0-20.0s', "silent draft disclosure"))
    sheet(tiles, os.path.join(EV, f"STORYBOARD-{v.upper()}.jpg"), 5,
          ("AD-1 variant %s :: %s :: frames from the rendered preview"
         % (v.upper(), "PROOF-FIRST" if v == "a" else "ANIMAL-FIRST")))
    ms = [s["rendered_metrics"]["sharpness_var"] for s in shots]
    report[v] = {"concept": spec["_concept"], "shots": shots,
                 "content_sec": spec["_content_sec"], "total_sec": spec["_total_sec"],
                 "shot_count": len(shots),
                 "avg_shot_sec": round(spec["_content_sec"] / len(shots), 3),
                 "opening_three_shots_sec": round(shots[2]["timeline"][1], 3),
                 "scale_first_appears_at": next(
                     (s["timeline"][0] for s in shots
                      if s["asset"] in ("gh-a25", "gh-a27", "gh-a02")), None),
                 "sharpness": {"min": min(ms), "max": max(ms),
                               "mean": round(sum(ms) / len(ms), 2)},
                 "upscale": {"min": min(s["upscale"] for s in shots),
                             "max": max(s["upscale"] for s in shots)},
                 "white_clip_max": max(s["rendered_metrics"]["white_clip"] for s in shots),
                 "black_clip_max": max(s["rendered_metrics"]["black_clip"] for s in shots)}

# مقارنة على نفس الزمن: كل ثانية ونصف من النسختين جنبًا إلى جنب
grid = []
for t in [0.7, 2.2, 4.0, 5.8, 8.0, 10.0, 12.5, 14.8, 16.2, 18.5]:
    for v in ("a", "b"):
        png = os.path.join(EV, f"cmp-{v}-{t}.jpg")
        im = grab(os.path.join(HERE, f"preview-{v}-silent.mp4"), t, png)
        grid.append((im, f'{v.upper()} @ {t:.1f}s', f'mean={metrics(im)["luma_mean"]:.0f}'))
sheet(grid, os.path.join(EV, "COMPARE-A-B-timeline.jpg"), 6,
      "A (proof-first) vs B (animal-first) :: same timestamps, pairs left=A right=B", thumb=(220, 391))

json.dump(report, open(os.path.join(EV, "shot-analysis.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
for v, r in report.items():
    print(f'{v.upper()}: {r["shot_count"]} shots | avg {r["avg_shot_sec"]}s | '
          f'first3 {r["opening_three_shots_sec"]}s | scale at {r["scale_first_appears_at"]}s | '
          f'sharp mean {r["sharpness"]["mean"]} | up {r["upscale"]["min"]}-{r["upscale"]["max"]}x')
