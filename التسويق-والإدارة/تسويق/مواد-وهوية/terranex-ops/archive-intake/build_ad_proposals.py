#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ثلاثة مقترحات إعلانية من المواد الجديدة + مقارنة صريحة بالإعلان الحالي.

مقترحات فقط: لا إنتاج، لا صوت، لا تغيير لهوية voice-00، ولا مساس بالمشاريع القائمة.
كل نافذة هنا مرّت بمسح ثماني نقاط وقراءة بصرية فعلية للإطار الأوسط للنافذة.
كل المقترحات رأسية لأن ٢٩ من ٣٠ فيديو رأسي بعد تطبيق مصفوفة الدوران (الأفقي الوحيد gh-a20).
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "github-branches")
vr = json.load(open(os.path.join(OUT, "visual-review.json"), encoding="utf-8"))["assets"]


def shot(aid, s, e, why, kind="video", evidence=None):
    a = vr[aid]
    assert a["ad_safe"], f"{aid} ليس آمنًا إعلانيًا"
    assert "visual_duplicate_of" not in a, f"{aid} مكرر بصري"
    assert a["orientation"] == "portrait" or kind == "image", f"{aid} ليس رأسيًا"
    if kind == "video":
        assert 0 <= s < e <= a["duration"], (aid, e, a["duration"])
    return {"asset": aid, "file": a["file_name"], "kind": kind, "start": s, "end": e,
            "duration": round(e - s, 3), "native": f'{a["width"]}x{a["height"]}',
            "why": why, "visual_evidence": evidence}


A = [
    shot("gh-a27", 0.6, 5.6, "كبش كامل الجسم بجانب ميزان TerraNex بشعار ورقم الشركة — افتتاحية إثبات",
         evidence="مسح ثماني: حدة 384–548 على مدى المقطع؛ الإطار عند 2.95s يُظهر الجسم كاملًا واللوحة مقروءة"),
    shot("gh-a25", 1.0, 3.0, "خروف أمام لوحة الميزان واسم TERRANEX LLC مقروء — تعزيز العلامة",
         evidence="أفضل نقطتين 2.0s=95 و0.7s=80؛ تجنّبنا 3.3s=57"),
    shot("gh-a43", 3.0, 7.0, "القطيع يتحرك في الحظيرة — لقطة حياة ونشاط",
         evidence="6.3s=314 أعلى حدة؛ تجنّبنا 19.0s=39 (ضبابية حركة)"),
    shot("gh-a08", 0.0, 2.5, "صف التغذية من أعلى — صورة رأسية بتقريب بطيء", kind="image",
         evidence="صورة 906×1600 Q=0.865، لا أشخاص ولا نصوص محروقة"),
    shot("gh-a33", 10.5, 12.5, "كبش مرقّط كامل الجسم — تنويع بصري قبل الخاتمة",
         evidence="12.5s=137 الأعلى في المقطع؛ العلامة المحروقة أسفل الوسط تستلزم رفع التسميات"),
    shot("gh-a26", 4.0, 5.5, "كبش أبيض برأس أسود واقف بهدوء — خاتمة نظيفة قبل الكارت",
         evidence="4.3s=79 و6.0s=81؛ لقطة ثابتة بلا أشخاص"),
]
B = [
    shot("gh-a38", 12.0, 18.0, "فحص فم وأسنان الحمل لتقدير العمر — أقوى دليل رعاية جديد",
         evidence="الإطار 15.05s يُظهر اليدين تفتحان الفم بوضوح (حدة 244)"),
    shot("gh-a16", 0.8, 4.8, "تثبيت هادئ للخروف باليد وجسمه كامل — تعامل موثّق",
         evidence="2.6s=292 أفضل نافذة؛ النافذة 8–12s مرفوضة بصريًا (أرض عارية وقدم)"),
    shot("gh-a39", 6.0, 9.0, "خروفان على منصة والمزرعة خلفهما — سياق المكان",
         evidence="الإطار 7.5s=166 يُظهر المنصة والمباني"),
    shot("gh-a17", 15.5, 17.5, "سياق الحظيرة والنخيل والسماء — لقطة تأسيسية نظيفة",
         evidence="17.3s=330؛ تجنّبنا 10–12s لأن العلف الأحمر قد يُقرأ خطأً كدماء"),
]
C = [
    shot("gh-a43", 3.0, 9.0, "القطيع كاملًا — تأسيسية طويلة", evidence="6.3s=314"),
    shot("gh-a08", 0.0, 3.0, "التغذية صفًا صفًا", kind="image", evidence="906×1600 Q=0.865"),
    shot("gh-a26", 3.5, 7.5, "كبش كامل الجسم بلا أشخاص", evidence="4.3–6.0s حدة 79–81"),
    shot("gh-a27", 0.6, 5.6, "الميزان والعلامة — ذروة الإثبات", evidence="حدة 384–548"),
    shot("gh-a25", 5.5, 7.5, "لوحة العلامة مقروءة أثناء الوزن", evidence="6.0s=91"),
    shot("gh-a38", 13.0, 17.0, "فحص الأسنان — الرعاية قبل البيع", evidence="16.4s=374 في المسح الأصلي"),
    shot("gh-a33", 10.5, 13.5, "كبش مرقّط كامل الجسم مع علامة محروقة", evidence="12.5s=137"),
]

ads = []
for name, rows, ec, concept in [
    ("AD-1 الوزن قدامك", A, 3.0, "إثبات الوزن بميزان يحمل شعار الشركة"),
    ("AD-2 فحص ومتابعة", B, 3.0, "الرعاية والفحص الحقيقي قبل البيع"),
    ("AD-3 من المزرعة", C, 3.0, "فيلم علامة قصير يجمع القطيع والتغذية والوزن"),
]:
    content = round(sum(r["duration"] for r in rows), 3)
    acc = 0.0
    for r in rows:
        r["timeline_start"] = round(acc, 3)
        acc = round(acc + r["duration"], 3)
        r["timeline_end"] = acc
    ups = [round(1920 / vr[r["asset"]]["height"], 2) for r in rows if r["kind"] == "video"]
    ads.append({"name": name, "concept": concept, "orientation": "vertical",
                "delivery": "1080x1920", "content_sec": content, "endcard_sec": ec,
                "total_sec": round(content + ec, 3), "shots": rows,
                "upscale_factor_range": [min(ups), max(ups)],
                "status": "proposal-only-not-produced"})

res = {
    "status": "proposals-only", "produced": False,
    "voice": "لا صوت في هذه المقترحات؛ هوية voice-00 لم تتغيّر",
    "geometry_correction": {
        "finding": "٢٠ من ٣٠ فيديو تحمل displaymatrix ‎-90°‎؛ المقاس المُرمّز أفقي لكن العرض رأسي",
        "true_orientation": {"portrait": 29, "landscape": 1},
        "only_landscape_asset": "gh-a20",
        "consequence": "لا يمكن بناء إعلان أفقي 16:9 من هذه الدفعة؛ كل المقترحات رأسية 1080×1920",
        "fixed_in": "archive_audit.py::display_geometry + test_display_geometry.py (٨ اختبارات)",
    },
    "ads": ads,
    "comparison_with_current": {
        "current": {"project": "cd-followup-20s v2 / cd-followup-20s-voiced", "sources": 2,
                    "usable_scenes_before": 5, "total_source_seconds": 186.46,
                    "opener": "ماكرو صوف (حدة 162)", "scale_visible": False,
                    "native_resolution": "720x1280",
                    "watermark": "TerraNex LLC منتصف الكادر"},
        "new": {"assets": 43, "ad_eligible_after_dedupe": 19, "total_video_seconds": 727.04,
                "best_opener": "كبش كامل + ميزان بشعار الشركة (حدة 548)", "scale_visible": True,
                "native_resolution": "478×850 / 480×848 / 576×1024 رأسي",
                "new_capabilities": ["وزن حقيقي بميزان يحمل العلامة", "فحص أسنان/عمر",
                                     "قطيع متحرك", "تغذية صفًا صفًا"]},
        "honest_tradeoff": ("المادة الجديدة أغنى محتوى بكثير لكن دقتها أقل بسبب ضغط واتساب: "
                            "تكبير 480×848 إلى 1080×1920 = 2.26×، مقابل 1.5× للمادة القديمة 720×1280. "
                            "الأنسب مزج: الجديدة للإثبات والمحتوى، والقديمة للقطة البطلة الأعلى دقة."),
        "quarantine": "ستة أصول ذبح/دماء مستبعدة نهائيًا من كل المقترحات",
    },
    "rejected_windows": [
        {"asset": "gh-a16", "window": [8.0, 12.0], "reason": "أرض عارية وقدم وحافة رأس فقط — لا فعل"},
        {"asset": "gh-a17", "window": [10.0, 12.0], "reason": "علف بمخلفات حمراء قريبة قد تُقرأ كدماء"},
        {"asset": "gh-a24", "window": [2.0, 5.0], "reason": "ماعز يرعى بجانب الميزان لا يُوزن؛ حدة 30–68"},
        {"asset": "gh-a25", "window": [1.5, 4.5], "reason": "يمرّ بأضعف نقطة 3.3s=57 وإضاءة خلفية محروقة"},
        {"asset": "gh-a33", "window": [5.0, 8.0], "reason": "جسم الحيوان مقطوع والمؤخرة فقط في الكادر"},
    ],
    "owner_decisions_needed": [
        "اعتماد أي مقترح للإنتاج",
        "موافقة الأشخاص الظاهرين في a05/a29 إن أُريد استخدامهما",
        "توضيح ماهية العلف الأحمر في a17 قبل أي استخدام قريب له",
        "سياسة استخدام لقطات كاميرات المراقبة a03/a04",
        "هل تُفرد حملة منتج منفصلة لمواد اللحوم (a10/a12/a13)",
    ],
}
with open(os.path.join(OUT, "ad-proposals.json"), "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
    f.write("\n")
for a in ads:
    print(a["name"], "| content", a["content_sec"], "| endcard", a["endcard_sec"],
          "| total", a["total_sec"], "| upscale", a["upscale_factor_range"])
