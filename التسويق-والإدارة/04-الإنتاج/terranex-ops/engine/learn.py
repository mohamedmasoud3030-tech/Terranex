#!/usr/bin/env python3
"""learn.py — يحوّل أرقام الأسبوع إلى تعديل مؤكَّد على النظام.

  python engine/learn.py --csv data/week-01.csv            # تقرير
  python engine/learn.py --csv data/week-01.csv --append   # يضيف لـcontext/learnings.md

شكل CSV:
date,platform,title,hook,pillar,views,saves,inquiries,critic_score
2026-10-19,facebook,الوزن على الطبيعة,وزن قدامك مش كلام,proof,18400,612,27,100
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import statistics as st

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEARN = os.path.join(ROOT, "context", "learnings.md")


def load(path):
    with open(path, encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        for k in ("views", "saves", "inquiries", "critic_score"):
            r[k] = float(r.get(k) or 0)
    return rows


def analyse(rows):
    if not rows:
        return {"error": "ملف فاضي"}
    by_pillar = {}
    for r in rows:
        by_pillar.setdefault(r["pillar"], []).append(r)

    def rate(r):
        return (r["inquiries"] / r["views"] * 1000) if r["views"] else 0

    stats = []
    for p, items in by_pillar.items():
        stats.append({
            "pillar": p, "n": len(items),
            "views": st.mean(i["views"] for i in items),
            "inquiries": sum(i["inquiries"] for i in items),
            "inq_per_1k": st.mean(rate(i) for i in items),
            "saves": st.mean(i["saves"] for i in items),
        })
    stats.sort(key=lambda s: s["inq_per_1k"], reverse=True)

    ranked = sorted(rows, key=rate, reverse=True)
    best, worst = ranked[:2], ranked[-2:]
    total_inq = sum(r["inquiries"] for r in rows)

    decisions = []
    top = stats[0]
    decisions.append(f"ركّز على محور **{top['pillar']}** — أعلى استفسار لكل 1000 وصول ({top['inq_per_1k']:.2f}).")
    if len(stats) > 1:
        low = stats[-1]
        decisions.append(f"قلّل **{low['pillar']}** لمرة كل أسبوعين — ({low['inq_per_1k']:.2f} استفسار/1000).")
    bad_hooks = [w["hook"] for w in worst if rate(w) < st.mean(rate(r) for r in rows)]
    if bad_hooks:
        decisions.append("أوقف الـhooks دي 14 يوم: " + " · ".join(f"«{h}»" for h in bad_hooks[:3]))
    good = [b for b in best if rate(b) > 0]
    if good:
        decisions.append("كرر **زاوية** الـhook دي بمحتوى جديد: «%s» (%.1f استفسار/1000)." % (good[0]["hook"], rate(good[0])))
    low_score = [r for r in rows if r["critic_score"] and r["critic_score"] < 85]
    if low_score:
        decisions.append(f"{len(low_score)} بوست نُشر بدرجة أقل من 85 — راجع بوابة `critic.py` قبل النشر.")

    return {"stats": stats, "best": best, "worst": worst, "total_inq": total_inq,
            "decisions": decisions, "n": len(rows)}


def report(a):
    L = ["", "=" * 58, " تقرير التعلّم الأسبوعي", "=" * 58,
         f" بوستات: {a['n']}   |   إجمالي استفسارات الواتساب: {int(a['total_inq'])}", "",
         " المحور            عدد   متوسط وصول   استفسار/1000   حفظ",
         " " + "-" * 56]
    for s in a["stats"]:
        L.append(f" {s['pillar']:<14} {s['n']:>4}   {s['views']:>10,.0f}   {s['inq_per_1k']:>12.2f}   {s['saves']:>6,.0f}")
    L += ["", " الأفضل:"]
    for b in a["best"]:
        L.append(f"   ▲ {b['title']} — {int(b['inquiries'])} استفسار / {int(b['views']):,} وصول")
    L += ["", " الأضعف:"]
    for w in a["worst"]:
        L.append(f"   ▼ {w['title']} — {int(w['inquiries'])} استفسار / {int(w['views']):,} وصول")
    L += ["", " قرارات مقترحة (تُضاف لـ learnings.md):"]
    for i, d in enumerate(a["decisions"], 1):
        L.append(f"   {i}. {d}")
    L.append("=" * 58)
    return "\n".join(L)


def append(a, week_label):
    today = dt.date.today().isoformat()
    block = [f"\n## {week_label} — {today}\n", "| الحقيقة | الدليل | القرار |", "|---|---|---|"]
    for d in a["decisions"]:
        block.append(f"| {d} | بيانات {week_label} ({a['n']} بوست، {int(a['total_inq'])} استفسار) | يُطبّق الأسبوع القادم |")
    block.append("")
    with open(LEARN, "a", encoding="utf-8") as f:
        f.write("\n".join(block))
    return LEARN


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--append", action="store_true")
    ap.add_argument("--label", default=None)
    a = ap.parse_args()
    rows = load(a.csv)
    res = analyse(rows)
    if "error" in res:
        raise SystemExit(res["error"])
    print(report(res))
    if a.append:
        label = a.label or os.path.splitext(os.path.basename(a.csv))[0]
        p = append(res, label)
        print(f"\n✅ اتضاف لـ {p}")


if __name__ == "__main__":
    main()
