#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يؤلّف نسختَي AD-1 بصريًا من نفس الفكرة ببنيتين مختلفتين، ويتحقق من كل نافذة قبل الكتابة.

النسخة A «إثبات أولًا»: تبدأ بلوحة العلامة ثم الكبش على الميزان — إيقاع قصير متلاحق،
                        لا خمس ثوانٍ متصلة على الميزان (قرار المالك).
النسخة B «الحيوان أولًا»: تبدأ بالحيوان والرعاية ثم تكشف الميزان في الثلث الأخير.

قواعد مفروضة هنا برمجيًا لا بالنية:
  - كل نافذة داخل مدة المصدر فعلًا.
  - لا أصل محجور (ذبح/دماء)، ولا كاميرات مراقبة (a03/a04)، ولا وجه بلا موافقة.
  - لا رقم وزن في أي نص على الشاشة (لا قراءة رقمية ظاهرة في المادة).
  - شريط كابشن واحد ثابت عند 0.84 مُتحقَّق منه بصريًا أنه لا يغطي حيوانًا ولا علامة.
  - بلا hook layer: صندوقه عند 0.295 كان سيغطي لوحة الميزان.
"""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MARK = os.path.abspath(os.path.join(OPS, "..", ".."))
G = os.path.join(OPS, "archive-intake", "github-branches")
mm = json.load(open(os.path.join(HERE, "media-manifest.json"), encoding="utf-8"))
P = {a["asset_id"]: a for a in mm["assets"]}
vr = json.load(open(os.path.join(G, "visual-review.json"), encoding="utf-8"))["assets"]
stg = json.load(open(os.path.join(G, "staging-index.json"), encoding="utf-8"))
QUAR = set(stg["quarantine"]["ids"])
BANNED = QUAR | {"gh-a03", "gh-a04"}          # حجر الذبح + قرار المالك باستبعاد المراقبة
FACES = {k for k, v in vr.items() if v.get("persons") in ("face", "face+body", "two-persons")}

CAPTION_CY = 0.84
TREAT = {"sharpen": False, "scale_flags": "lanczos"}
OLD_SRC = "فيديوهات-جاهزة-للنشر/01-بومو-الشركة-الرئيسي.mp4"
OLD_DUR = 25.8


def clip(aid, s, e, role):
    assert aid not in BANNED, f"{aid} محظور"
    assert aid not in FACES, f"{aid} يحوي وجهًا بلا موافقة"
    a, v = P[aid], vr[aid]
    assert v["ad_safe"] and "visual_duplicate_of" not in v, f"{aid} غير صالح"
    kind = a["kind"]
    if kind == "video":
        assert 0 <= s < e <= a["duration"], (aid, e, a["duration"])
    else:
        s = 0.0
    up = round(1920 / a["display_geometry"][1], 3)
    return {"path": a["staged_path"], "start": round(s, 3), "end": round(e, 3),
            "crop": {}, **TREAT, "_asset_id": aid, "_role": role,
            "_source_sha256": a["sha256"], "_git_blob_sha": a["git_blob_sha"],
            "_source_geometry": a["display_geometry"], "_rotation": a["rotation_degrees"],
            "_upscale_to_1080x1920": up, "_staging_only": True}


def old_clip(s, e, role, crop):
    assert 0 <= s < e <= OLD_DUR
    rel = os.path.relpath(os.path.join(MARK, OLD_SRC), HERE)
    return {"path": rel,
            "start": s, "end": e, "crop": crop, **TREAT,
            "_asset_id": "old-s01-08", "_role": role,
            "_source_geometry": [720, 1280], "_upscale_to_1080x1920": 1.5,
            "_why_mixed": "أعلى دقة متاحة (720×1280، تكبير 1.5×) وإضاءة أنظف من مواد واتساب"}


A_SHOTS = [
    clip("gh-a25", 5.4, 6.9, "افتتاحية: لوحة TERRANEX LLC مقروءة بالكامل"),
    clip("gh-a27", 1.8, 3.6, "الإثبات البطل: الكبش كاملًا عند الميزان"),
    clip("gh-a25", 1.2, 2.7, "فعل التثبيت/الوزن من زاوية ثانية"),
    clip("gh-a43", 4.5, 6.9, "اتساع: القطيع في الحظيرة"),
    old_clip(19.2, 21.0, "استراحة صورة عالية الدقة: التغذية", {"top": 0.07}),
    clip("gh-a08", 0.0, 2.0, "صف التغذية من أعلى — لقطة رسومية"),
    clip("gh-a38", 13.5, 16.5, "دليل الرعاية: فحص الأسنان/العمر"),
    clip("gh-a26", 4.0, 5.5, "كبش نظيف كامل الجسم قبل الختام"),
    clip("gh-a27", 7.8, 9.3, "عودة للميزان — إغلاق الحلقة"),
]
B_SHOTS = [
    clip("gh-a26", 3.6, 5.6, "افتتاحية بالحيوان نفسه، بلا ميزان في الكادر"),
    clip("gh-a43", 4.0, 7.0, "القطيع — حياة المزرعة"),
    clip("gh-a38", 13.0, 16.5, "الرعاية أولًا: فحص الأسنان"),
    clip("gh-a16", 1.0, 3.6, "تعامل هادئ وموثّق"),
    old_clip(19.2, 21.0, "استراحة صورة عالية الدقة: التغذية", {"top": 0.07}),
    clip("gh-a27", 1.8, 3.6, "كشف الميزان — نقطة التحول"),
    clip("gh-a25", 5.4, 6.9, "العلامة مقروءة بعد الكشف"),
    clip("gh-a27", 7.8, 8.6, "ختم سريع على الميزان"),
]

# نص شاشة مسودة — ليس نص تعليق صوتي، ولا يعتمد النص القديم ولا v3
# كل سطر مربوط باللقطة التي تظهر تحته فعلًا؛ وفجوة بلا كابشن فوق صف التغذية
# لأن الحيوانات تملأ ذلك الكادر من الحافة للحافة ولا يوجد شريط فارغ آمن فيه.
A_CAPS = [
    (0.30, 4.70, "الوزن قدامك… مش كلام."),      # 0.0–4.8 الميزان والعلامة
    (5.00, 7.10, "وبنتابع القطيع."),            # 4.8–7.2 القطيع
    (7.40, 8.90, "تغذية… ومتابعة."),            # 7.2–9.0 التغذية عالية الدقة
    (11.20, 13.90, "وفحص قبل التسليم."),        # 11.0–14.0 فحص الأسنان
    (14.30, 16.90, "كلمنا على واتساب."),        # 14.0–17.0 الكبش ثم الميزان
]
# «والوزن قدامك» يبدأ عند 13.0 بالضبط مع كشف الميزان (12.9) لا قبله،
# حتى لا يَعِد النص بشيء لا يظهر في الصورة بعد. دعوة الواتساب على الكارت الختامي.
B_CAPS = [
    (0.30, 2.00, "ده اللي بنربيه."),            # 0.0–2.0 الحيوان
    (2.30, 4.90, "بنتابعه… يوم بيوم."),         # 2.0–5.0 القطيع
    (5.30, 8.40, "وفحص… ومتابعة."),             # 5.0–8.5 الفحص
    (8.70, 12.80, "تغذية… وتوثيق."),            # 8.5–12.9 التعامل والتغذية
    (13.00, 16.90, "والوزن قدامك."),            # 12.9–17.0 كشف الميزان
]
NUM = re.compile(r"\d")


def make(name, shots, caps, concept):
    dur = round(sum(c["end"] - c["start"] for c in shots), 3)
    assert abs(dur - 17.0) < 0.001, (name, dur)
    t = 0.0
    for c in shots:
        c["_timeline"] = [round(t, 3), round(t + c["end"] - c["start"], 3)]
        t = round(t + c["end"] - c["start"], 3)
    for a, b, txt in caps:
        assert 0 <= a < b <= dur, (name, a, b)
        assert not NUM.search(txt), f"رقم في نص الشاشة: {txt}"
        assert len(txt.split()) <= 6
    spec = {
        "title": f"ad1-weight-proof-{name}",
        "template": "corporate-no-face",
        "on_screen_persons": [], "consent_persons": [],
        "clips": shots,
        "captions": [{"from": a, "to": b, "text": txt} for a, b, txt in caps],
        "caption_cy": CAPTION_CY,
        "endcard_sec": 3.0,
        "endcard": {"headline": "الوزن قدامك", "subtitle": "ومتابعة بعينك",
                    "cta": "واتساب 01010154221",
                    "disclosure": "معاينة بصرية للمراجعة · بدون تعليق صوتي"},
        "visual_draft": True,
        "publish_approved": False,
        "_project": "ad1-weight-proof",
        "_variant": name,
        "_concept": concept,
        "_content_sec": dur, "_total_sec": round(dur + 3.0, 3),
        "_text_status": "نص شاشة مسودة فقط — ليس نص تعليق صوتي معتمدًا، ولا النص القديم ولا v3",
        "_voice_identity": "voice-00 لم تتغيّر — لا صوت في هذه المعاينة",
        "_caption_band": {"cy": CAPTION_CY, "verified_by": "PROBE-02-caption-band.jpg",
                          "reason": "0.70 كان يغطي أرجل الحيوان ويدي الفحص؛ 0.84 نظيف في كل اللقطات"},
        "_hook_omitted": "صندوق الـhook عند 0.295 يغطي لوحة الميزان — حُذف عمدًا",
        "_no_weight_number": "لا قراءة رقمية للوزن ظاهرة في المادة، فلا رقم في أي نص",
        "_source_policy": "مواد الفروع عبر staging فقط + لقطة واحدة أعلى دقة من المكتبة القديمة",
    }
    path = os.path.join(HERE, f"spec-{name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return path, spec


for nm, sh, cp, cc in [
    ("a", A_SHOTS, A_CAPS, "إثبات أولًا: العلامة والميزان في أول ٤٫٨ ثانية بإيقاع متلاحق"),
    ("b", B_SHOTS, B_CAPS, "الحيوان أولًا: الحيوان والرعاية ثم كشف الميزان في الثلث الأخير"),
]:
    p, s = make(nm, sh, cp, cc)
    ups = [c["_upscale_to_1080x1920"] for c in s["clips"]]
    print(f'{nm}: {len(sh)} shots | content {s["_content_sec"]}s + 3.0s = {s["_total_sec"]}s '
          f'| upscale {min(ups)}–{max(ups)}x | {os.path.basename(p)}')
