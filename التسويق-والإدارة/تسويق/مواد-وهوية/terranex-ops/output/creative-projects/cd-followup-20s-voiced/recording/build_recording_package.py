#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""أداة مراجعة لمرة واحدة: توليد ورقة التوقيت + نموذج التفريغ من خطة البايلوت.

لا تُعدّل المحرك ولا تُرفق صوتًا. تقرأ plan.json/spec.json وتكتب ملفات حزمة التسجيل.
"""
import json
import os

PROJ = "output/creative-projects/cd-followup-20s-voiced/"
REC = os.path.join(PROJ, "recording")

plan = json.load(open(PROJ + "plan.json", encoding="utf-8"))
spec = json.load(open(PROJ + "spec.json", encoding="utf-8"))
phrases = plan["schedule"]["voice_phrases"]
total = round(sum(c["end"] - c["start"] for c in spec["clips"]) + spec["endcard_sec"], 3)

# نموذج تقديري معلن للمراجعة البشرية: عدّ مقاطع صوتية باللهجة المصرية + وقفة داخلية عند "…"
SYL = [
    {"بنتابع": 3, "التغذية": 4},
    {"وبنتابعهم": 5, "على": 2, "أرض": 1, "الواقع": 3},
    {"من": 1, "الحظيرة": 4, "وللمزرعة": 5},
    {"متابعة": 4, "وتوثيق": 3, "خطوة": 2, "بخطوة": 3},
    {"كلمنا": 3, "على": 2, "واتساب": 2},
]
WINDOWS = [(2.55, 4.50), (5.00, 8.00), (8.50, 11.50), (12.00, 16.60), (17.20, 19.70)]
PICTURE = [
    "لقطة التغذية s01-08 (2.500–4.533)",
    "لقطة المتابعة/الميزان s04-02 (4.533–8.231)",
    "لقطة القطيع s01-03 ثم لقطة المزرعة s01-07 (8.231–11.598)",
    "لقطة المتابعة الختامية s04-04 (11.598–17.000)",
    "كارت الخاتمة (17.000–20.000)",
]
INTERNAL_PAUSE = [0.0, 0.0, 0.20, 0.20, 0.0]
RATES = {"extra_slow_stress": 3.6, "design_floor_calm": 4.0, "calm": 4.2, "brisk": 5.0}
DESIGN_FLOOR = "design_floor_calm"

lines = []
for i, (p, w, syl, pic, ip) in enumerate(zip(phrases, WINDOWS, SYL, PICTURE, INTERNAL_PAUSE), start=1):
    n = sum(syl.values())
    dur = round(w[1] - w[0], 3)
    est = {k: round(n / v + ip, 2) for k, v in RATES.items()}
    lines.append({
        "line": i,
        "role": p["role"],
        "text": p["text"],
        "target_from_sec": w[0],
        "target_to_sec": w[1],
        "window_sec": dur,
        "picture": pic,
        "words": len(p["text"].split()),
        "syllables_estimated": n,
        "syllable_breakdown": syl,
        "internal_pause_sec": ip,
        "estimated_speech_sec": est,
        "margin_at_design_floor_sec": round(dur - est[DESIGN_FLOOR], 2),
        "fits_design_floor": bool(dur >= est[DESIGN_FLOOR]),
        "fits_extra_slow_stress": bool(dur >= est["extra_slow_stress"]),
    })

gaps = [round(WINDOWS[i + 1][0] - WINDOWS[i][1], 3) for i in range(len(WINDOWS) - 1)]
speech = round(sum(w[1] - w[0] for w in WINDOWS), 3)
sheet = {
    "project_id": "cd-followup-20s-voiced",
    "derived_from": {"project": "cd-followup-20s", "version": 2,
                     "visuals_identical": True,
                     "reference_video": "التسويق-والإدارة/تسويق/فيديوهات-المنتجة/creative-director/cd-followup-20s/v0002.mp4"},
    "video_total_sec": total,
    "hook_title_sec": spec["hook_sec"],
    "language": "ar-EG",
    "tone": "مصري هادي واثق — بدون استعجال",
    "model": {
        "type": "syllable-rate-estimate",
        "rates_syllables_per_sec": RATES,
        "note": "تقدير مكتبي للمراجعة فقط؛ الدليل النهائي هو التسجيل البشري نفسه. لا يوجد TTS ولا ASR في هذه البيئة.",
    },
    "engine_constraints": {
        "measure_phrases_threshold_db": -38.0,
        "measure_phrases_window_sec": 0.05,
        "min_segment_sec": 0.10,
        "merge_gap_sec": 0.30,
        "required_segments": len(phrases),
        "max_audio_duration_sec": total + 0.05,
        "rules": [
            "الوقفة بين الجمل يجب أن تكون ≥ 0.50 ثانية (أكبر من حد الدمج 0.30 بهامش أمان).",
            "الوقفة داخل الجملة عند «…» يجب أن تكون < 0.30 ثانية، وإلا انقسمت الجملة ورُفض الملف.",
            "أرضية الضجيج يجب أن تكون أقل من -38 dBFS، وإلا ظهرت مقاطع وهمية.",
            "الملف يبدأ بصمت 2.55 ثانية لأن عنوان الهوك يشغل أول ثانيتين.",
            "طول الملف ≤ 20.00 ثانية — لا قصّ تلقائي للكلام في المحرك.",
        ],
    },
    "windows_are_guidance": True,
    "guidance_note": ("التوقيتات أهداف إرشادية للتسجيل فقط. التسجيل الطبيعي هو المرجع: يُقيَّم أولًا "
                      "(إيقاع/وقفات/وضوح/طبيعية الأداء) قبل أي إرفاق، ثم تُضبط الكابشنات على المواضع "
                      "المقاسة فعليًا. لا يُقصّ الكلام ولا يُمدّ لإجباره على النافذة."),
    "evaluation_before_attach": [
        "فحص سلامة الملف: صيغة/مدة/قمم/أرضية ضجيج + SHA-256.",
        "قياس مقاطع الكلام بـmeasure_phrases (يجب أن تكون 5) ومقارنة المواضع بالنوافذ الإرشادية.",
        "تقييم طبيعيّة الأداء والإيقاع البشري، وتوثيق أي انحراف عن النوافذ وأسبابه.",
        "استماع المالك وقراره الكتابي، ثم مراجعة الكلام المنطوق مقابل التفريغ وتوثيقها في approval_note.",
        "فقط بعد ذلك: attach-voice — الكابشن يُضبط على القياس الحقيقي لا على النوافذ الإرشادية.",
    ],
    "approval_state": {
        "reviewer": "",
        "approval_note": "",
        "owner_decision": "القرار بعد الاستماع — لا إرفاق ولا تغيير لهوية الصوت قبل موافقة كتابية",
        "script_proposal_v3_adopted": False,
    },
    "lines": lines,
    "gaps_between_lines_sec": gaps,
    "min_gap_sec": min(gaps),
    "leading_silence_sec": WINDOWS[0][0],
    "trailing_silence_sec": round(total - WINDOWS[-1][1], 3),
    "target_file_duration_sec": total,
    "speech_windows_total_sec": speech,
    "speech_duty_cycle": round(speech / total, 3),
    "total_syllables_estimated": sum(l["syllables_estimated"] for l in lines),
    "design_floor_rate_syllables_per_sec": RATES[DESIGN_FLOOR],
    "all_lines_fit_design_floor": all(l["fits_design_floor"] for l in lines),
    "all_lines_fit_extra_slow_stress": all(l["fits_extra_slow_stress"] for l in lines),
}
os.makedirs(REC, exist_ok=True)
with open(os.path.join(REC, "voice-timing.json"), "w", encoding="utf-8") as f:
    json.dump(sheet, f, ensure_ascii=False, indent=2)
    f.write("\n")

# نموذج التفريغ: النص مطابق للخطة، وبيانات الاعتماد فارغة عمدًا حتى يملأها المالك/المراجع.
template = {
    "verification_method": "human-reviewed",
    "reviewer": "",
    "approval_note": "",
    "ai_generated": False,
    "phrases": [{"text": p["text"]} for p in phrases],
}
with open(PROJ + "voice-transcript.json", "w", encoding="utf-8") as f:
    json.dump(template, f, ensure_ascii=False, indent=2)
    f.write("\n")

print("total video:", total, "| lines:", len(lines), "| syllables:", sheet["total_syllables_estimated"])
print("gaps:", gaps, "| min gap:", min(gaps), "| duty:", sheet["speech_duty_cycle"])
print("all lines fit design floor 4.0 syl/s:", sheet["all_lines_fit_design_floor"])
print("all lines fit extra-slow stress 3.6 syl/s:", sheet["all_lines_fit_extra_slow_stress"])
for l in lines:
    print(f"  L{l['line']} {l['target_from_sec']:>5.2f}-{l['target_to_sec']:>5.2f} "
          f"win={l['window_sec']:>4.2f} est_floor={l['estimated_speech_sec'][DESIGN_FLOOR]:>4.2f} "
          f"margin={l['margin_at_design_floor_sec']:>5.2f} | {l['text']}")
