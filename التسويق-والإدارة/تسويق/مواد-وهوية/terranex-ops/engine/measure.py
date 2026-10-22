#!/usr/bin/env python3
"""measure.py — قياس نتائج الحملات وتحويلها لقرارات محتوى.

  python engine/measure.py --template output/campaigns/x/قياس.csv      # قالب فارغ للفريق
  python engine/measure.py --csv data/week-01.csv                      # تحليل أسبوع
  python engine/measure.py --csv data/week-02.csv --prev data/week-01.csv --append

لا شبكة ولا APIs — الفريق يعبّئ CSV من لوحات المنصات يدويًا (إدخال بشري مقصود).
المقارنة الزمنية (--prev) تبرز الأثر: وصول/استفسار/حفظ لكل 1000 مشاهدة.
القرارات الناتجة تُضاف إلى context/learnings.md عبر --append (يقود gen_calendar تاليًا).
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import statistics as st
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORTS = os.path.abspath(os.path.join(ROOT, "..", "..", "..", "إدارة", "تقارير-ومتابعة"))

import learn  # noqa: E402

BENCH_INQ_PER_1K = 5.0   # هدف تشغيلي مبدئي: 5 استفسارات واتساب لكل 1000 وصول
BENCH_SAVE_PER_1K = 15.0


def load_many(paths: list[str]) -> list[dict]:
    rows = []
    for p in paths:
        rows.extend(learn.load(p))
    return rows


def per_key(rows, key):
    g = {}
    for r in rows:
        k = r.get(key) or "(فارغ)"
        v = g.setdefault(k, {"views": 0.0, "saves": 0.0, "inquiries": 0.0, "n": 0})
        v["views"] += r["views"]; v["saves"] += r["saves"]
        v["inquiries"] += r["inquiries"]; v["n"] += 1
    for k, v in g.items():
        v["inq1k"] = v["inquiries"] / v["views"] * 1000 if v["views"] else 0
        v["sav1k"] = v["saves"] / v["views"] * 1000 if v["views"] else 0
    return g


def delta(cur_rows, prev_rows):
    """فرق الكفاءة بين أسبوعين (لكل 1000 وصول — عادل رغم فرق الوصول)."""
    out = []
    pc, pp = per_key(cur_rows, "platform"), per_key(prev_rows, "platform")
    for pl in pc:
        if pl in pp and pp[pl]["views"]:
            dv = pc[pl]["inq1k"] - pp[pl]["inq1k"]
            out.append((pl, dv, pc[pl]["inq1k"], pp[pl]["inq1k"]))
    return out


def template_csv(path: str) -> str:
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("date,platform,title,hook,pillar,views,saves,inquiries,critic_score\n")
        f.write(f"{dt.date.today().isoformat()},facebook,,,,,,,\n")
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", nargs="+", help="ملف/ملفات قياس الأسبوع الحالي")
    ap.add_argument("--prev", nargs="+", help="ملف/ملفات الأسبوع المقارِن")
    ap.add_argument("--append", action="store_true", help="أضف القرارات إلى learnings.md")
    ap.add_argument("--label", default=None)
    ap.add_argument("--template", help="اكتب قالب قياس فارغ للفريق")
    a = ap.parse_args()

    if a.template:
        t = template_csv(a.template)
        print(f"OK قالب قياس للفريق: {t}")
        return 0
    if not a.csv:
        raise SystemExit("حدّد --csv أو --template")

    rows = load_many(a.csv)
    if not rows:
        raise SystemExit("ملف القياس فاضي")
    res = learn.analyse(rows)
    label = a.label or os.path.splitext(os.path.basename(a.csv[0]))[0]

    print(learn.report(res))

    by_pl = per_key(rows, "platform")
    print("\n حسب المنصة:")
    for pl, v in sorted(by_pl.items(), key=lambda x: -x[1]["inq1k"]):
        print(f"   {pl:<10} وصول {int(v['views']):>7,} · {v['inq1k']:>5.2f} استفسار/1000 · {v['sav1k']:>5.2f} حفظ/1000")

    tot_v = sum(r["views"] for r in rows)
    tot_i = sum(r["inquiries"] for r in rows)
    tot_s = sum(r["saves"] for r in rows)
    inq1k = tot_i / tot_v * 1000 if tot_v else 0
    sav1k = tot_s / tot_v * 1000 if tot_v else 0
    print(f"\n الحملة كلها: {int(tot_v):,} وصول · {inq1k:.2f} استفسار/1000 (هدف {BENCH_INQ_PER_1K})"
          f" · {sav1k:.2f} حفظ/1000 (هدف {BENCH_SAVE_PER_1K})"
          f" → {'فوق الهدف ✅' if inq1k >= BENCH_INQ_PER_1K else 'تحت الهدف ⚠️'}")

    decisions_extra = []
    if inq1k < BENCH_INQ_PER_1K:
        decisions_extra.append(f"الاستفسار/1000 ({inq1k:.2f}) تحت الهدف {BENCH_INQ_PER_1K} — راجع قوة الـhooks وسطر CTA قبل الاستثمار في توزيع أوسع.")
    if a.prev:
        prev_rows = load_many(a.prev)
        for pl, dv, cur, prv in delta(rows, prev_rows):
            s = "تحسّن" if dv >= 0 else "تراجع"
            print(f" مقارنة بالأسبوع السابق — {pl}: {s} {abs(dv):.2f} استفسار/1000 ({prv:.2f} ← {cur:.2f})")
            if dv < 0:
                decisions_extra.append(f"تراجع {pl} من {prv:.2f} إلى {cur:.2f} استفسار/1000 — افحص ما تغيّر (نوع المحور/وقت النشر/الـhook).")

    if a.append:
        res["decisions"] = res["decisions"] + decisions_extra
        path = learn.append(res, label)
        print(f"\n أُضيفت القرارات إلى {os.path.relpath(path, ROOT)}")

    os.makedirs(REPORTS, exist_ok=True)
    rp = os.path.join(REPORTS, f"قياس-الحملة-{label}-{dt.date.today().isoformat()}.md")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(f"# قياس الحملة — {label}\n\n```\n{learn.report(res)}\n```\n")
        f.write(f"\nالإجمالي: {int(tot_v):,} وصول · {int(tot_i)} استفسار · {inq1k:.2f} استفسار/1000 "
                f"({'فوق' if inq1k >= BENCH_INQ_PER_1K else 'تحت'} الهدف {BENCH_INQ_PER_1K})\n")
    print(f"\n📊 تقرير القياس: {os.path.relpath(rp, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
