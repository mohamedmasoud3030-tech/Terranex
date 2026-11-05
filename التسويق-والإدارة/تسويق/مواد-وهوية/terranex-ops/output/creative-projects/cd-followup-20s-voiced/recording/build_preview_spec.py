#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يبني spec معاينة صامتة من مشروع البايلوت دون تعديل أي ملف رسمی في المشروع.

- يقرأ spec.json الخاص بالبايلوت (كما هو) وvoice-timing.json (النوافذ الإرشادية المقترحة).
- يستبدل الكابشنات فقط بنوافذ التزامن المقترحة، ويصلح المسارات النسبية لمستوى أعمق.
- يكتب recording/preview-spec.json ليُرندر عبر محرك الرندر الموجود:
    .venv/bin/python engine/reel_build.py --spec <preview-spec> --out <preview.mp4>
لا يولّد صوتًا، ولا يمرّر --voice، ولا يلمس plan/spec/memory/transcript.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)

spec = json.load(open(os.path.join(PROJ, "spec.json"), encoding="utf-8"))
timing = json.load(open(os.path.join(HERE, "voice-timing.json"), encoding="utf-8"))
plan = json.load(open(os.path.join(PROJ, "plan.json"), encoding="utf-8"))

# الكابشنات الحالية في الخطة هي المرجع النصي — لا يُستخدم أي نص مقترح غير معتمد.
plan_texts = [p["text"] for p in plan["schedule"]["voice_phrases"]]
assert [c["text"] for c in spec["captions"]] == plan_texts, "نص الكابشن لا يطابق الخطة"
assert [l["text"] for l in timing["lines"]] == plan_texts, "نص ورقة التوقيت لا يطابق الخطة"

preview = json.loads(json.dumps(spec))
for c in preview["clips"]:
    if not os.path.isabs(c["path"]):
        c["path"] = "../" + c["path"]          # المعاينة على مستوى أعمق من مجلد المشروع
preview["captions"] = [
    {"from": l["target_from_sec"], "to": l["target_to_sec"], "text": l["text"]}
    for l in timing["lines"]
]
preview["_caption_timing_source"] = "proposed-guidance-windows-not-approved"
preview["_preview"] = {
    "purpose": "معاينة بصرية صامتة لمراجعة التزامن المقترح قبل اختيار المعلّق",
    "source_project": "cd-followup-20s-voiced",
    "source_version": 2,
    "visuals_unchanged": True,
    "captions_text_source": "plan.json (الجمل الخمس الحالية)",
    "timing_source": "recording/voice-timing.json (نوافذ إرشادية)",
    "audio": "none — لا يوجد مسار صوت في الملف المُخرَج",
    "approved": False,
    "voice_identity_unchanged": "ar-eg-calm-confident / voice-00 كما هي في personas.json",
    "note": "الكابشن الخامس يقع على كارت الخاتمة، ومحرك الرندر لا يرسم كابشن فوق الكارت؛ لذلك الجملة الخامسة منطوقة فقط والرقم مكتوب على الكارت.",
}
assert preview["visual_draft"] is True
assert preview["endcard"]["disclosure"] == spec["endcard"]["disclosure"]

out = os.path.join(HERE, "preview-spec.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(preview, f, ensure_ascii=False, indent=2)
    f.write("\n")

# تحقّق أن مسارات اللقطات تُفكّ إلى نفس الملفات الحقيقية المستخدمة في spec المشروع
base_proj = os.path.abspath(PROJ)
base_prev = os.path.abspath(HERE)
for a, b in zip(spec["clips"], preview["clips"]):
    ra = os.path.realpath(os.path.join(base_proj, a["path"]))
    rb = os.path.realpath(os.path.join(base_prev, b["path"]))
    assert ra == rb and os.path.isfile(rb), (ra, rb)
    assert (a["start"], a["end"]) == (b["start"], b["end"])

print("preview spec:", out)
print("clips:", len(preview["clips"]), "| identical sources/windows: True")
print("captions (proposed guidance windows):")
for c in preview["captions"]:
    print(f"  {c['from']:>5.2f} → {c['to']:>5.2f}  {c['text']}")
total = sum(c["end"] - c["start"] for c in preview["clips"]) + preview["endcard_sec"]
print("total:", round(total, 3), "| visual_draft:", preview["visual_draft"], "| audio: none")
