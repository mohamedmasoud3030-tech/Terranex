#!/usr/bin/env python3
"""gen_calendar.py — يولّد تقويم محتوى 30 يوم كامل، قابل للتنفيذ، من قاعدة واحدة.

  python engine/gen_calendar.py --days 30 --out output/calendar.md

المبادئ:
  • 5 محاور بالتناوب، مفيش محور مرتين ورا بعض.
  • مفيش hook متكرر داخل نفس الشهر.
  • كل يوم معلوم عليه مصدر الفوتاج المتاح (01–06) — لو مفيش، مكتوب «تصوير مطلوب».
  • أوقات النشر من product-marketing.md §5.
"""
from __future__ import annotations

import argparse
import datetime as dt
import random

PILLARS = ["proof", "teach", "behind", "ask", "value"]
PILLAR_AR = {"proof": "دليل", "teach": "تعليم", "behind": "كواليس", "ask": "تفاعل", "value": "قيمة"}

# مكتبة hooks — كل عنصر (نص/ بديل) مصنّف بالمحور
HOOKS = {
    "proof": [
        ("الخروف ده على الميزان النهارده", "وزن قدامك، مش كلام"),
        ("مش هنقولك… هنوريك", "شوف بعينك"),
        ("الوزن اتغير تاني", "الرقم مش ثابت… وده اللي بيهم"),
        ("الشهادة البيطرية موجودة", "الورق جنب الرأس"),
        ("الفحص اليومي مش دعاية", "ده روتين عندنا"),
    ],
    "teach": [
        ("قبل ما تحط فلوسك… 5 أسئلة", "اسأل أي حد قبل ما تستثمر"),
        ("الفرق بين العائد والنمو", "حاجتين مختلفين خالص"),
        ("إزاي تعرف الرأس اللي يستاهل؟", "3 علامات بسيطة"),
        ("التكلفة الحقيقية مش سعر الرأس", "في حاجات بتنسى تحسبها"),
        ("ليه الوزن بيفرق في قيمة الرأس؟", "الفرق مش بسيط"),
    ],
    "behind": [
        ("في المزرعة الساعة ٦ الصبح", "قبل ما حد يصحى"),
        ("اللي بيحصل قبل ما الفيديو يتصور", "مش دايماً جميل… بس حقيقي"),
        ("مين اللي بيتابع الرأس؟", "له اسم ووش"),
        ("التغذية بالتفصيل", "اللي بنحطه فين؟"),
        ("أول ما الرأس وصل المزرعة", "من أول يوم"),
    ],
    "ask": [
        ("أ ولا ب؟", "اختار وأكتب في التعليقات"),
        ("إيه اللي بيوقفك؟", "جاوب بصراحة"),
        ("سؤال لكل مستثمر", "الفلوس ولا المتابعة؟"),
        ("تحب تشوف إيه الأسبوع الجاي؟", "قرارك"),
        ("لو مكانك… تعمل إيه؟", "أ/ب/ج"),
    ],
    "value": [
        ("الرزق مش بالسرعة", "بالبركة والمتابعة"),
        ("الفلوس اللي بتتعب فيها", "محتاجة تفكير مش اندفاع"),
        ("حد يبيعك حلم؟", "اسأل عن الورق الأول"),
        ("الصبر ده استثمار", "مش انتظار"),
        ("الجمعة مباركة 🌾", "من أرض TerraNex"),
    ],
}

SOURCES = {
    "proof": ["04 الوزن", "تصوير مطلوب (ميزان + شهادة)"],
    "teach": ["02 الأسئلة الخمسة", "03 سؤال تفاعلي"],
    "behind": ["06 تحضير بيتي", "تصوير مطلوب (يوم في المزرعة)"],
    "ask": ["03 سؤال تفاعلي"],
    "value": ["05 محتوى قيمي"],
}
TIMES = {"sat": "19:00", "sun": "19:30", "mon": "19:00", "tue": "20:00",
         "wed": "19:00", "thu": "19:30", "fri": "13:30"}
AR_DAY = {"sat": "السبت", "sun": "الأحد", "mon": "الإثنين", "tue": "الثلاثاء",
          "wed": "الأربعاء", "thu": "الخميس", "fri": "الجمعة"}
KEY = {5: "sat", 6: "sun", 0: "mon", 1: "tue", 2: "wed", 3: "thu", 4: "fri"}  # python weekday()


def build(days=30, start=None, seed=11):
    rnd = random.Random(seed)
    start = start or dt.date(2026, 10, 19)  # السبت القادم
    rows = []
    used = {p: set() for p in PILLARS}
    prev = None
    d = start
    while len(rows) < days:
        k = KEY[d.weekday()]
        # توزيع المحاور: الاثنين والأربعاء دليل، الأحد تعليم، الثلاثاء تفاعل، الجمعة قيمة
        order = {"sat": ["behind", "proof", "value"],
                 "sun": ["teach", "proof", "value"],
                 "mon": ["proof", "behind", "teach"],
                 "tue": ["ask", "ask", "teach"],
                 "wed": ["proof", "teach", "behind"],
                 "thu": ["behind", "value", "proof"],
                 "fri": ["value", "value", "behind"]}[k]
        pillar = next((p for p in order if p != prev and len(used[p]) < len(HOOKS[p])), order[0])
        pool = [h for i, h in enumerate(HOOKS[pillar]) if i not in used[pillar]] or list(HOOKS[pillar])
        h = pool[rnd.randrange(len(pool))]
        used[pillar].add(HOOKS[pillar].index(h))
        src = SOURCES[pillar][0] if rnd.random() > 0.25 else SOURCES[pillar][-1]
        rows.append({
            "date": d, "day": k, "pillar": pillar, "hook": h[0], "sub": h[1],
            "source": src, "time": TIMES[k],
            "format": "ريل 20–35ث" if pillar in ("proof", "behind", "value") else "ريل + تعليق مثبّت",
        })
        prev = pillar
        d += dt.timedelta(days=1)
    return rows


def to_md(rows, title="تقويم TerraNex — 30 يوم"):
    out = [f"# {title}", "",
           f"مولّد آليًا من `engine/gen_calendar.py`. الأوقات من `context/product-marketing.md §5`.",
           "", "| # | التاريخ | اليوم | المحور | Hook | مصدر الفوتاج | الوقت | الفورمات |",
           "|---|---|---|---|---|---|---|---|"]
    for i, r in enumerate(rows, 1):
        out.append(f"| {i} | {r['date']} | {AR_DAY[r['day']]} | {PILLAR_AR[r['pillar']]} "
                   f"| {r['hook']} | {r['source']} | {r['time']} | {r['format']} |")
    # تغطية
    from collections import Counter
    c = Counter(r["pillar"] for r in rows)
    out += ["", "## التغطية", ""]
    for p in PILLARS:
        out.append(f"- {PILLAR_AR[p]}: **{c[p]}** يوم")
    need = [r for r in rows if "تصوير مطلوب" in r["source"]]
    out += ["", f"## تصوير مطلوب: **{len(need)}** يوم", ""]
    for r in need[:12]:
        out.append(f"- {r['date']} ({AR_DAY[r['day']]}) — {r['hook']} → {r['source']}")
    out += ["", "> **قاعدة:** أي يوم مكتوب عليه «تصوير مطلوب» ما ينشرش بلقطة قديمة معادة. "
                "استخدم فيديو من 01–06 أو صوّر جديد."]
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=30)
    ap.add_argument("--start", default=None, help="YYYY-MM-DD")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    start = dt.date.fromisoformat(a.start) if a.start else None
    rows = build(a.days, start, a.seed)
    open(a.out, "w", encoding="utf-8").write(to_md(rows))
    print(f"OK {a.out} — {len(rows)} يوم")


if __name__ == "__main__":
    main()
