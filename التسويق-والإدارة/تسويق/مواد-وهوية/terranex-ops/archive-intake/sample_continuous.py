#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""عيّنات زمنية للمواد ذات اللقطة المستمرة (بلا قطعات صلبة).

كشف القطعات عند 0.30 لا يرى الانتقالات الناعمة/الحركة المستمرة، لذلك نأخذ عيّنة كل 2.5 ثانية
ونبني Contact Sheet للمراجعة البصرية. لا يعدّل المصادر ولا يلمس scene-library.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from archive_audit import grab_frame, frame_metrics, contact_sheet, dhash  # noqa: E402

BASE = os.path.join(HERE, "local-real-media")
STEP = 2.5
TARGETS = ["local-a02", "local-a03", "local-a04", "local-a05", "local-a07"]

audit = json.load(open(os.path.join(BASE, "reports", "audit.json"), encoding="utf-8"))
assets = {a["asset_id"]: a for a in audit["assets"]}
samples = []
for aid in TARGETS:
    a = assets[aid]
    dur = a["probe"]["duration"]
    items = []
    t = 0.5
    while t < dur - 0.2:
        img = grab_frame(a["abs_path"] if "abs_path" in a else a["file"], t, 360)
        if img is None:
            # المسار في التقرير نسبي إلى مجلد الأصل المشترك
            root = audit["intake"]["source"].get("paths")
            cand = next((p for p in (root or []) if os.path.basename(p) == os.path.basename(a["file"])), None)
            img = grab_frame(cand, t, 360) if cand else None
        if img is None:
            t += STEP
            continue
        sid = f"{aid}-t{t:05.1f}"
        pv = os.path.join(BASE, "previews", sid + ".jpg")
        img.save(pv, quality=88)
        m = frame_metrics(img)
        rec = {"sample_id": sid, "asset_id": aid, "source_file": a["file"], "t": round(t, 2),
               "preview": os.path.relpath(pv, BASE), "dhash": f"{dhash(img):016x}", "metrics": m}
        samples.append(rec)
        items.append({"preview": pv, "label": f"{sid}", "sub": f'sharp={m["sharpness_var"]:.0f} luma={m["luma_mean"]:.0f}'})
        t += STEP
    p = contact_sheet(items, os.path.join(BASE, "contact-sheets", aid + "-samples.jpg"),
                      title=f"{aid} time samples :: {os.path.basename(a['file'])[:60]}")
    print(aid, "samples:", len(items), "->", os.path.basename(p) if p else None)

json.dump({"step_sec": STEP, "samples": samples},
          open(os.path.join(BASE, "reports", "time-samples.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
print("total samples:", len(samples))
