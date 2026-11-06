#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""مقترحان مختصران لتعليق صوتي مصري — نصّ فقط.

لا توليد صوت، لا تسجيل، لا اعتماد. هوية voice-00 لا تتغيّر.
النص القديم المعتمد والمقترح v3 لا يُعتمدان هنا ولا يُنسخان.
كل سطر مربوط بنافذة زمنية من نُسخته البصرية، ويُفحص ميزانية القراءة ومنع ذكر المدينة.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(OPS, "engine"))
import reel_build as R  # noqa: E402

VO1 = {
    "id": "vo-proposal-1",
    "name": "مباشر — يناسب النسخة A (إثبات أولًا)",
    "for_variant": "a",
    "tone": "هادئ واثق، جملة قصيرة ثم وقفة. مصري عامي بلا مبالغة ولا وعود رقمية.",
    "lines": [
        (0.40, 4.60, "الوزن مش كلام… الوزن قدامك."),
        (5.00, 7.00, "وبنتابع القطيع."),
        (7.40, 10.80, "تغذية… ومتابعة كل يوم."),
        (11.20, 13.90, "وفحص قبل التسليم."),
        (14.30, 16.90, "كلمنا على واتساب."),
        (17.20, 19.60, "تيرانكس… ملك حقيقي."),
    ],
}
VO2 = {
    "id": "vo-proposal-2",
    "name": "حكائي دافئ — يناسب النسخة B (الحيوان أولًا)",
    "for_variant": "b",
    "tone": "قريب من الناس، يبدأ بالحيوان وينتهي بالدليل. بلا صيغة بيع مباشرة.",
    "lines": [
        (0.40, 2.00, "ده اللي بنربيه."),
        (2.30, 4.90, "وبنتابعه يوم بيوم."),
        (5.30, 8.40, "فحص… ومتابعة."),
        (8.70, 12.80, "تغذية… وتوثيق."),
        (13.00, 16.90, "والوزن؟ قدامك على الميزان."),
        (17.20, 19.60, "تيرانكس… كلمنا."),
    ],
}

out = []
for vo in (VO1, VO2):
    rows = []
    for a, b, txt in vo["lines"]:
        R.lint_text(txt)                      # بوابة منع ذكر المدينة
        assert not any(ch.isdigit() for ch in txt), f"رقم في نص صوتي مقترح: {txt}"
        words = len(txt.split())
        rate = round(words / (b - a), 2)
        assert rate <= 2.6, f"ميزانية قراءة ضيقة: {txt} ({rate} كلمة/ث)"
        rows.append({"from": a, "to": b, "sec": round(b - a, 2), "text": txt,
                     "words": words, "words_per_sec": rate})
    out.append({**{k: v for k, v in vo.items() if k != "lines"},
                "lines": rows,
                "total_words": sum(r["words"] for r in rows),
                "speaking_sec": round(sum(r["sec"] for r in rows), 2)})

doc = {
    "status": "proposal-only",
    "generated_audio": False,
    "adopted": False,
    "voice_identity": "voice-00 — لم تتغيّر، ولم يُسجَّل أي صوت",
    "old_script_adopted": False,
    "v3_adopted": False,
    "no_numeric_weight_claim": "لا يوجد رقم وزن في أي سطر — لا قراءة رقمية ظاهرة في المادة",
    "proposals": out,
}
doc["gate"] = "بوابة الصوت مغلقة: يلزم استماع المالك + قرار هوية مكتوب + اعتماد النص قبل أي توليد"
with open(os.path.join(HERE, "vo-proposals.json"), "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
for p in out:
    print(f'{p["id"]} ({p["for_variant"]}): {p["total_words"]} words / {p["speaking_sec"]}s '
          f'| max rate {max(l["words_per_sec"] for l in p["lines"])} w/s')
