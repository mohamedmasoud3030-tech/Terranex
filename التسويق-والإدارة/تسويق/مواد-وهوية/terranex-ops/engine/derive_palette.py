#!/usr/bin/env python3
"""derive_palette.py — مصدر الحقيقة الوحيد للوحة الألوان.

يستخرج الألوان المهيمنة من **الشعار الرسمي** بالتجميع (k-means)، ثم يقارنها
بمتغيرات صفحة العرض الرسمية. عند التعارض يُعتمد الشعار (الأصل الرسمي) ويُوثَّق
القرار والسبب.

  python engine/derive_palette.py            # يكتب context/palette.json
  python engine/derive_palette.py --print    # يطبع فقط

لا شبكة، لا أسرار، كتابة ملف واحد فقط.
"""
from __future__ import annotations

import argparse
import json
import os
import re

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "assets", "logo", "شعار-TerraNex.jpg")
PAGE = os.path.join(os.path.dirname(ROOT), "صفحة-العرض-التفاعلية.html")
OUT = os.path.join(ROOT, "context", "palette.json")

# عتبة التعارض: مسافة إقليدية في RGB (0-441)
CONFLICT_DELTA = 42.0


def hex2rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=float)


def rgb2hex(c):
    return "#%02X%02X%02X" % tuple(int(round(max(0, min(255, v)))) for v in c)


def dist(a, b):
    return float(np.linalg.norm(np.asarray(a, float) - np.asarray(b, float)))


def kmeans(px, k, iters=40, seed=7):
    rng = np.random.default_rng(seed)
    idx = rng.choice(len(px), size=k, replace=False)
    cent = px[idx].copy()
    for _ in range(iters):
        d = ((px[:, None, :] - cent[None, :, :]) ** 2).sum(2)
        lab = d.argmin(1)
        new = cent.copy()
        for j in range(k):
            m = lab == j
            if m.any():
                new[j] = px[m].mean(0)
        if np.allclose(new, cent, atol=0.4):
            cent = new
            break
        cent = new
    d = ((px[:, None, :] - cent[None, :, :]) ** 2).sum(2)
    lab = d.argmin(1)
    counts = np.array([(lab == j).sum() for j in range(k)], dtype=float)
    order = counts.argsort()[::-1]
    return cent[order], counts[order] / counts.sum()


def logo_clusters(k=6, max_px=60000):
    im = Image.open(LOGO).convert("RGB")
    a = np.asarray(im).reshape(-1, 3).astype(float)
    lum = a.sum(1)
    # استبعاد الخلفية السوداء والبيضاء فقط (نبقي على الذهبي الغامق)
    keep = (lum > 105) & (lum < 735)
    px = a[keep]
    if len(px) > max_px:
        step = len(px) // max_px
        px = px[::step][:max_px]
    return kmeans(px, k)


def classify(colors, weights):
    """يرشّح الكلاسترز لأدوار: ذهبي (فاتح/أساسي/غامق) وأخضر."""
    rows = []
    for c, w in zip(colors, weights):
        r, g, b = c
        mx, mn = max(c), min(c)
        sat = (mx - mn) / mx if mx else 0
        is_gold = r >= g > b and sat > 0.25 and r > 90
        is_green = g > r * 1.12 and g > b * 1.12
        rows.append({"hex": rgb2hex(c), "rgb": [round(v, 1) for v in c],
                     "weight": round(float(w), 4), "lum": round(float(c.mean()), 1),
                     "gold": bool(is_gold), "green": bool(is_green)})
    golds = sorted([x for x in rows if x["gold"]], key=lambda x: x["lum"])
    greens = sorted([x for x in rows if x["green"]], key=lambda x: -x["weight"])
    out = {}
    if golds:
        out["gold_deep"] = golds[0]["hex"]
        out["gold_hi"] = golds[-1]["hex"]
        out["gold"] = max(golds, key=lambda x: x["weight"])["hex"]
        # ذهبي "متوسط" لقراءة أفضل على الخلفيات الغامقة (كلاستر أوسط الوزن)
        mid = [g for g in golds if g["hex"] not in (golds[0]["hex"], golds[-1]["hex"], out["gold"])]
        out["gold_mid"] = max(mid, key=lambda x: x["weight"])["hex"] if mid else out["gold"]
    if greens:
        out["green_logo"] = greens[0]["hex"]
        out["green_deep"] = greens[-1]["hex"] if len(greens) > 1 else greens[0]["hex"]
    return out, rows


def page_vars():
    if not os.path.exists(PAGE):
        return {}
    html = open(PAGE, encoding="utf-8").read()
    found = {}
    for name in ("green", "green2", "green3", "gold", "gold2", "cream", "ink", "muted"):
        m = re.search(rf"--{name}\s*:\s*(#[0-9A-Fa-f]{{6}})", html)
        if m:
            found[name] = m.group(1).upper()
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--print", action="store_true")
    a = ap.parse_args()

    colors, weights = logo_clusters(a.k)
    roles, rows = classify(colors, weights)
    page = page_vars()

    conflicts = []
    comparisons = []

    def cmp(label, logo_hex, page_hex):
        if not page_hex:
            return
        d = dist(hex2rgb(logo_hex), hex2rgb(page_hex))
        verdict = "logo" if d > CONFLICT_DELTA else "match"
        comparisons.append({"role": label, "logo": logo_hex, "page": page_hex,
                            "distance": round(d, 1), "decision": verdict})
        if verdict == "logo":
            conflicts.append(f"{label}: الشعار {logo_hex} ≠ الصفحة {page_hex} "
                             f"(Δ={d:.0f}) → اعتُمد الشعار")

    cmp("gold", roles.get("gold", ""), page.get("gold"))
    cmp("gold_hi", roles.get("gold_hi", ""), page.get("gold2"))
    cmp("green_logo", roles.get("green_logo", ""), page.get("green"))
    cmp("green_deep", roles.get("green_deep", ""), page.get("green2"))

    palette = {
        "_meta": {
            "single_source_of_truth": "assets/logo/شعار-TerraNex.jpg",
            "method": "k-means (k=%d) على بكسلات الشعار بعد استبعاد الخلفية السوداء/البيضاء" % a.k,
            "conflict_rule": "عند التعارض يُعتمد الشعار لأن الصفحة مشتقة منه وليست الأصل",
            "conflict_threshold_rgb": CONFLICT_DELTA,
            "generated_by": "engine/derive_palette.py",
        },
        "logo_roles": roles,
        "clusters": rows,
        "page_vars": page,
        "comparisons": comparisons,
        "conflicts": conflicts,
        "shades": {},
        "final": {},
    }

    # ---- اشتقاق درجات الخلفية من أخضر الشعار (رياضي وموثّق) ----
    g = hex2rgb(roles.get("green_logo", "#2F562F"))
    shades, shade_doc = {}, []
    for name, target in (("green_deep", 44), ("bg_dark", 21), ("bg_mid", 33)):
        f = 1.0
        for _ in range(200):
            v = g * f
            if v.mean() <= target:
                break
            f -= 0.01
        shades[name] = rgb2hex(v)
        shade_doc.append(f"{name} = أخضر الشعار × {f:.2f} (سطوع مستهدف {target})")
    palette["shades"] = {"derived": shades, "rule": shade_doc,
                         "note": "الشعار لا يحتوي إلا درجة خضراء واحدة، فتُشتق درجات الخلفية بتظليل خطي موثّق."}

    palette["final"] = {
        "gold_hi": roles.get("gold_hi", "#EFDB9B"),
        "gold": roles.get("gold", "#E9C46A"),
        "gold_mid": roles.get("gold_mid", "#C5933C"),
        "gold_deep": roles.get("gold_deep", "#936F36"),
        "green": roles.get("green_logo", "#2F562F"),
        "green_deep": shades["green_deep"],
        "bg_dark": shades["bg_dark"],
        "bg_mid": shades["bg_mid"],
        "bg_cream": page.get("cream", "#FBF7EC"),
        "ink": page.get("ink", "#17352B"),
        "muted": page.get("muted", "#5E7268"),
    }

    if a.print:
        print(json.dumps(palette, ensure_ascii=False, indent=2))
        return

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(palette, f, ensure_ascii=False, indent=2)
    print(f"OK {OUT}")
    for k, v in palette["final"].items():
        print(f"  {k:<11} {v}")
    if conflicts:
        print("\nتعارضات مع صفحة العرض:")
        for c in conflicts:
            print("  • " + c)


if __name__ == "__main__":
    main()
