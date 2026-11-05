#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يسجّل المراجعة البصرية الفعلية لـContact Sheets ويولّد فهرسًا مرحليًا + أفضل 20 لقطة.

المراجعة أدناه ناتجة عن فتح أوراق المعاينة بالنظر (arena visual review)، وليست تخمينًا آليًا.
لا شيء يُدمج في scene-library الإنتاجية: كل المخرجات staging + merge_approved=false.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "local-real-media")
audit = json.load(open(os.path.join(BASE, "reports", "audit.json"), encoding="utf-8"))

# ---- مراجعة بصرية لكل أصل (من فتح contact-sheets/*.jpg) ----
ASSET_REVIEW = {
    "local-a01": {
        "title": "برومو الشركة الرئيسي",
        "provenance": "company-produced",
        "category": "mixed-promo",
        "notes": "ثلاث لقطات متحدّث بوجه واضح، إحداها تحمل بطاقة تعريف معلّقة؛ علامة TerraNex LLC محروقة؛ كارت ختام فيه اسم مدينة.",
        "scene_map": {
            1: dict(category="person-talking-head", animals=None, persons=True, burned=True,
                    private="بطاقة هوية غير مقروءة + وجه", consent=True, usable=False,
                    desc="رجل ببدلة يتحدث للكاميرا داخل مكتب، علامة TerraNex LLC وشريط نص محروق."),
            2: dict(category="feeding", animals="cows", persons=False, burned=True,
                    private=None, consent=False, usable=True,
                    desc="أبقار بنية وبيضاء عند حاجز التغذية، لقطة متوسطة، علامة محروقة أسفل الكادر."),
            3: dict(category="farm-crops", animals=None, persons=False, burned=True,
                    private=None, consent=False, usable=True,
                    desc="لقطة واسعة/ مرتفعة لحقل محصول أخضر ممتد وقت الغروب — أعلى حدة في المجموعة الرأسية."),
            4: dict(category="person-talking-head", animals="cows-background", persons=True, burned=True,
                    private="بطاقة تعريف معلّقة على الصدر", consent=True, usable=False,
                    desc="رجل بقميص أسود وبطاقة تعريف يتحدث، أبقار في الخلفية."),
            5: dict(category="person-talking-head", animals=None, persons=True, burned=True,
                    private=None, consent=True, usable=False,
                    desc="رجل بقميص مخطط داخل مبنى، شعار TerraNex مركّب."),
            6: dict(category="irrigation", animals=None, persons=False, burned=True,
                    private=None, consent=False, usable=True,
                    desc="رشاشات ري تسقي محصولًا ورقيًا أخضر، شعار صغير أعلى اليمين."),
            7: dict(category="feeding", animals="cows", persons=False, burned=True,
                    private=None, consent=False, usable=True,
                    desc="أبقار تأكل التبن عند الحاجز، لقطة قريبة، الحيوان كامل داخل الكادر."),
            8: dict(category="endcard-graphic", animals=None, persons=False, burned=True,
                    private=None, consent=False, usable=False,
                    desc="كارت ختام أسود/ذهبي فيه رقم واتساب واسم مدينة (الإسكندرية) — بوابة المدينة تمنع إعادة استخدامه."),
        }},
    "local-a02": {
        "title": "الأحد — 5 أسئلة قبل الاستثمار",
        "provenance": "company-derived-graphics",
        "category": "motion-graphics",
        "notes": "خلفية حيوانات مُعتَمة عمدًا (luma≈43) وفوقها دوائر ترقيم وأسئلة؛ لا تصلح كـB-roll نظيف.",
        "scene_map": {1: dict(category="motion-graphics", animals="sheep-dimmed", persons=False,
                              burned=True, private=None, consent=False, usable=False,
                              desc="غنم في حظيرة معتّمة جدًا مع نصوص أسئلة متحركة؛ المادة مشتقة لا خام.")}},
    "local-a03": {
        "title": "الثلاثاء — سؤال تفاعلي",
        "provenance": "company-produced",
        "category": "mixed-interactive",
        "notes": "شاشة مقسومة (أبقار أعلى + أغنام أسفل) وشريط سؤال أخضر؛ ثم كبش كامل الجسم في الهواء الطلق بعلامة محروقة منتصف الكادر.",
        "scene_map": {1: dict(category="animals-split-screen", animals="cows+sheep", persons=False,
                              burned=True, private=None, consent=False, usable=False,
                              desc="كادر مقسوم: أبقار عند الحاجز أعلى، قوائم/صوف غنم أسفل، وشريط سؤال أخضر في المنتصف يمنع القص النظيف.")},
        "extra_windows": [
            dict(start=8.0, end=11.7, category="animal-full-body", animals="ram", persons=False,
                 burned=True, private=None, consent=False, usable=True,
                 desc="كبش كامل الجسم واقف على أرضية خرسانية في الهواء الطلق؛ نص سؤال وعلامة TerraNex LLC محروقان — يلزم شريط إثبات.")]},
    "local-a04": {
        "title": "الأربعاء — الوزن على الطبيعة",
        "provenance": "company-field-footage",
        "category": "weight-field-activity",
        "notes": "لقطة مستمرة واحدة (0 قطعات صلبة)؛ أشرطة سوداء جانبية؛ يدا/قدما شخص تظهران؛ العلامة محروقة منتصف الكادر؛ لا تظهر منصة ميزان.",
        "scene_map": {1: dict(category="weight-field-activity", animals="sheep", persons="hands-and-feet",
                              burned=True, private=None, consent=True, usable=True,
                              desc="خروف ممدد على أرضية خرسانية ويد تمسك رأسه، ظلال قوية، علامة TerraNex LLC محروقة.")},
        "extra_windows": [
            dict(start=0.0, end=4.0, desc="بداية الوزن: الجسم كامل ويد الممسك من أعلى.", sharp=338),
            dict(start=4.0, end=8.0, desc="زاوية الرأس والحبل، تفاصيل الوجه والقرن.", sharp=213),
            dict(start=8.0, end=11.0, desc="زاوية جانبية مع ظل الشخص على الأرضية.", sharp=222),
            dict(start=11.0, end=13.5, desc="ماكرو صوف — أضعف نافذة بصريًا.", sharp=162),
            dict(start=13.5, end=19.3, desc="الشخص واقف يمسك الرأس، نباتات خضراء جانبًا.", sharp=227),
            dict(start=19.3, end=20.4, desc="ذيل اللقطة قبل كارت الختام.", sharp=233),
        ]},
    "local-a05": {
        "title": "الجمعة — محتوى قيمي",
        "provenance": "company-produced",
        "category": "religious-value-content",
        "notes": "١٧ ثانية صفحة كتاب وقلم (محتوى ديني/قيمي) ثم ثانيتان غنم في حظيرة معتمة؛ لا يصلح لإعلان استثماري.",
        "scene_map": {1: dict(category="book-page", animals=None, persons=False, burned=True,
                              private=None, consent=False, usable=False,
                              desc="صفحة كتاب مفتوحة وقلم فوقها، نص ديني مقروء — حساس وغير مناسب لحملة المتابعة.")},
        "extra_windows": [
            dict(start=18.0, end=20.6, category="animals-barn", animals="sheep", persons=False,
                 burned=True, private=None, consent=False, usable=True,
                 desc="غنم واقف في حظيرة بإضاءة خافتة، نص «جمعة مباركة» محروق — حدة منخفضة (86).")]},
    "local-a06": {
        "title": "تحضير بيتي على أصوله",
        "provenance": "company-food-footage",
        "category": "food-product",
        "notes": "مطبخ احترافي، قفازات زرقاء، لحوم مطهية وتقديم؛ لا يوجد حيوان حي — لا صلة له بحملة متابعة الحيوانات.",
        "scene_map": {i: dict(category="food-preparation", animals=None, persons="hands-in-gloves",
                              burned=(i == 8), private=None, consent=False, usable=False,
                              desc="تحضير/تقديم لحم ضاني مطهي في مطبخ؛ أيدي وقفازات فقط.") for i in range(1, 9)}},
    "local-a07": {
        "title": "الضاني مثل البلسم",
        "provenance": "company-food-footage",
        "category": "food-product",
        "notes": "لحم مطهي يُفك باليد وقفازات سوداء؛ نصوص وإيموجي محروقة أعلى الكادر؛ كارت ختام فيه اسم مدينة.",
        "scene_map": {
            1: dict(category="food-product", animals=None, persons="hands-in-gloves", burned=True,
                    private=None, consent=False, usable=False,
                    desc="صينية أرز ولحم ضاني، يدان بقفازات سوداء تفكّ اللحم؛ نص وإيموجي محروقَان."),
            2: dict(category="endcard-graphic", animals=None, persons=False, burned=True,
                    private=None, consent=False, usable=False,
                    desc="كارت ختام فيه رقم واتساب واسم مدينة (الإسكندرية).")}},
    "local-a08": {
        "title": "فيديو عرض للمالك",
        "provenance": "UNVERIFIED — يُرجَّح أنه محتوى مخزني/عام وليس تصوير المزرعة",
        "category": "owner-presentation",
        "notes": "مراعٍ خضراء وقطعان وسلالات وأرضيات جبال لا تطابق بيئة المزرعة في بقية المواد؛ يلزم إثبات ملكية/ترخيص قبل أي استخدام. أفقي 1280×720.",
        "scene_map": {
            1: dict(category="person-phone", animals=None, persons=True, burned=True,
                    private="شاشة هاتف شخص", consent=True, usable=False, desc="شخص يمسك هاتفًا ذكيًا، إضاءة منخفضة."),
            2: dict(category="pasture-herd", animals="sheep+cattle", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="قطيع مختلط يرعى في مرعى أخضر واسع، سماء زرقاء."),
            3: dict(category="pasture-flock", animals="sheep", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="قطيع أغنام في حقل تحيط به أشجار — حدة عالية جدًا (1287)."),
            4: dict(category="animal-single", animals="cow", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="بقرة سوداء وبيضاء ترعى بجانب عمود سياج."),
            5: dict(category="pasture-herd", animals="cattle", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="قطيع أبقار داكنة في مرعى جبلي."),
            6: dict(category="person-talking-head", animals=None, persons=True, burned=True,
                    private=None, consent=True, usable=False, desc="رجل بقميص مخطط يتحدث داخل مكتب."),
            7: dict(category="farm-crops", animals=None, persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="حقل محصول ورقي أخضر كثيف."),
            8: dict(category="feeding", animals="cows", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="أبقار تأكل عند حاجز، لقطة قريبة."),
            9: dict(category="pasture-herd", animals="sheep+cattle", persons=False, burned=True,
                    private=None, consent=False, usable=False, desc="مرعى أخضر بقطيع — شبه مكرر مع s02 (hamming 6)."),
            10: dict(category="endcard-graphic", animals=None, persons=False, burned=True,
                     private=None, consent=False, usable=False, desc="كارت ختام TerraNex ذهبي/أسود."),
        }},
}

scenes = {s["scene_id"]: s for s in audit["scenes"]}
for sc in audit["scenes"]:
    aid = sc["asset_id"]
    k = int(sc["scene_id"].split("-s")[1])
    rv = ASSET_REVIEW[aid]["scene_map"].get(k)
    if not rv:
        continue
    sc["visual_review"] = {
        "done": True, "reviewer": "arena-visual-review-of-contact-sheets",
        "category": rv["category"], "animals": rv["animals"], "persons_visible": rv["persons"],
        "burned_text_or_watermark": rv["burned"], "private_data": rv["private"],
        "consent_needed": rv["consent"], "notes": rv["desc"],
    }
    sc["provenance"] = ASSET_REVIEW[aid]["provenance"]
    sc["usable"] = bool(rv["usable"]) and not sc.get("near_duplicate_flag", False)

# ---- نوافذ إضافية داخل اللقطات المستمرة (من عيّنات زمنية فعلية) ----
samples = json.load(open(os.path.join(BASE, "reports", "time-samples.json"), encoding="utf-8"))["samples"]

def nearest_preview(aid, t):
    cand = [x for x in samples if x["asset_id"] == aid]
    if not cand:
        return None
    return min(cand, key=lambda x: abs(x["t"] - t))["preview"]

extra_scenes = []
for aid, ar in ASSET_REVIEW.items():
    for n, w in enumerate(ar.get("extra_windows", []), start=1):
        base_scene = next(s for s in audit["scenes"] if s["asset_id"] == aid)
        pv = nearest_preview(aid, (w["start"] + w["end"]) / 2) or base_scene["preview"]
        extra_scenes.append({
            "scene_id": f"{aid}-w{n:02d}", "source_file": base_scene["source_file"],
            "source_sha256": base_scene["source_sha256"],
            "start": w["start"], "end": w["end"], "duration": round(w["end"] - w["start"], 3),
            "width": base_scene["width"], "height": base_scene["height"], "fps": base_scene["fps"],
            "preview": "archive-intake/local-real-media/" + pv,
            "tags": [w.get("category", ar["category"])], "description": w["desc"],
            "quality": base_scene["quality_score"], "usable": bool(w.get("usable", True)),
            "burned_text": True, "persons_visible": "hands-and-feet" if aid == "local-a04" else False,
            "private_data": None, "consent_needed": aid == "local-a04",
            "provenance": ar["provenance"],
            "fit_vertical_9_16": base_scene["fit_vertical_9_16"],
            "fit_horizontal_16_9": base_scene["fit_horizontal_16_9"],
            "tagged_by": "arena-audit+visual-review", "staging": True,
            "window_of": base_scene["scene_id"],
        })

staging = {
    "schema_version": 1,
    "kind": "staging-index",
    "compatible_with": "scene-library/index.json (نفس حقول المشهد)",
    "merge_approved": False,
    "merge_into_scene_library": False,
    "generated_from": "local-real-media/reports/audit.json + مراجعة بصرية موثقة",
    "source_scope": "مواد الشركة المحلية الموجودة في المستودع — ليست أرشيف Drive",
    "scenes": [{
        "scene_id": s["scene_id"], "source_file": s["source_file"], "source_sha256": s["source_sha256"],
        "start": s["start"], "end": s["end"], "duration": s["duration"],
        "width": s["width"], "height": s["height"], "fps": s["fps"],
        "preview": "archive-intake/local-real-media/" + s["preview"],
        "tags": [t for t in [s["visual_review"].get("category"), s["visual_review"].get("animals")] if t],
        "description": s["visual_review"].get("notes"),
        "quality": s["quality_score"], "usable": s["usable"],
        "burned_text": bool(s["visual_review"].get("burned_text_or_watermark")),
        "persons_visible": s["visual_review"].get("persons_visible"),
        "private_data": s["visual_review"].get("private_data"),
        "consent_needed": s["visual_review"].get("consent_needed"),
        "provenance": s.get("provenance"),
        "fit_vertical_9_16": s["fit_vertical_9_16"], "fit_horizontal_16_9": s["fit_horizontal_16_9"],
        "tagged_by": "arena-audit+visual-review", "staging": True,
    } for s in audit["scenes"]] + extra_scenes,
}

# ---- أفضل 20 نافذة حقيقية (نوافذ مؤكدة + نوافذ معلّقة الإثبات) ----
def win(scene_id, start, end, tier, why, src=None):
    s = scenes[scene_id]
    return {"rank": None, "tier": tier, "scene_id": scene_id,
            "source_file": src or s["source_file"], "start": start, "end": end,
            "duration": round(end - start, 3), "quality_score": s["quality_score"],
            "width": s["width"], "height": s["height"],
            "category": s["visual_review"].get("category"),
            "preview": "archive-intake/local-real-media/" + s["preview"], "why": why}

TOP = [
    win("local-a01-s03", 12.267, 13.167, "A", "أعلى حدة في كل المادة الرأسية (274) وتعريض متوازن؛ حقل أخضر واسع يصلح افتتاحية «من المزرعة». عيبه قصره (0.9ث)."),
    win("local-a01-s07", 19.0, 21.033, "A", "أبقار تأكل التبن، الحيوان كامل داخل الكادر، حدة 434؛ أنظف لقطة تغذية متاحة."),
    win("local-a01-s06", 17.133, 19.0, "A", "ري بالرش على محصول ورقي؛ يوسّع معنى «المزرعة» بلا ادعاء، حركة ماء جذابة."),
    win("local-a01-s02", 10.767, 12.267, "A", "أبقار عند حاجز التغذية بلقطة أوسع؛ بديل جيد للتنويع بين لقطات التغذية."),
    win("local-a04-s01", 0.0, 4.0, "A", "الوزن الحقلي من أعلى: الجسم كامل ويد الممسك؛ أعلى حدة في مادة الوزن (338)."),
    win("local-a04-s01", 4.0, 8.0, "A", "زاوية الرأس والحبل تُظهر التعامل الهادئ مع الحيوان — أقرب مادة لمعنى «الرعاية»."),
    win("local-a04-s01", 13.5, 19.3, "A", "الشخص واقف يمسك الرأس؛ أوسع نافذة مستمرة (5.8ث) تصلح للجملة الختامية الطويلة."),
    win("local-a04-s01", 8.0, 11.0, "A", "زاوية جانبية بظل واضح؛ تنويع بصري داخل نفس النشاط دون تكرار الإطار."),
    win("local-a03-s01", 8.0, 11.7, "A", "كبش كامل الجسم واقف في الهواء الطلق — اللقطة الوحيدة التي تُظهر الحيوان واقفًا كاملًا خارج الحظيرة. تحتاج شريط إثبات للنص والعلامة."),
    win("local-a04-s01", 19.3, 20.4, "A", "ذيل لقطة الوزن قبل الكارت؛ نافذة قصيرة نظيفة نسبيًا (حدة 233)."),
    win("local-a05-s01", 18.0, 20.6, "A", "غنم في الحظيرة يضيف نوعًا ثانيًا من الحيوانات؛ لكن الإضاءة خافتة والحدة 86 ونص «جمعة مباركة» محروق."),
    win("local-a04-s01", 11.0, 13.5, "A", "ماكرو الصوف — أضعف نوافذ الوزن (حدة 162)؛ مدرجة للشفافية لأنها مستخدمة حاليًا كافتتاحية البايلوت."),
    win("local-a06-s08", 10.9, 15.6, "C", "طبق اللحم الضاني الجاهز — أعلى حدة في مادة الطعام (237) لكنه منتج غذائي مطهي: يصلح لحملة منتج منفصلة ولا يصلح إطلاقًا لحملة متابعة الحيوانات."),
    win("local-a08-s03", 10.5, 17.5, "B", "قطيع أغنام في حقل، حدة 1287 هي الأعلى في كل الجرد — لكن ملكية المادة غير مثبتة والأصل أفقي."),
    win("local-a08-s04", 17.5, 23.5, "B", "بقرة مفردة عند سياج، حدة 1278 وتكوين نظيف — معلّقة على إثبات الملكية."),
    win("local-a08-s02", 4.0, 10.5, "B", "قطيع مختلط في مرعى واسع، حدة 657 — معلّقة على إثبات الملكية."),
    win("local-a08-s07", 32.667, 34.533, "B", "حقل محصول ورقي كثيف، حدة 714 — معلّقة على إثبات الملكية."),
    win("local-a08-s08", 34.533, 36.533, "B", "أبقار عند حاجز التغذية بلقطة قريبة، حدة 453 — معلّقة على إثبات الملكية."),
    win("local-a08-s05", 23.5, 31.033, "B", "قطيع في مرعى جبلي، حركة كاميرا واضحة (102) — معلّقة على إثبات الملكية."),
    win("local-a08-s09", 36.533, 42.533, "B-dup", "شبه مكررة مع a08-s02 (hamming=6) — تُستبعد من المكتبة حتى لو ثبتت الملكية."),
]
for i, t in enumerate(TOP, start=1):
    t["rank"] = i

json.dump(staging, open(os.path.join(HERE, "staging-index.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
json.dump({"asset_review": {k: {kk: vv for kk, vv in v.items() if kk != "scene_map"}
                            for k, v in ASSET_REVIEW.items()},
           "scene_review": {s["scene_id"]: s["visual_review"] for s in audit["scenes"]},
           "top20": TOP},
          open(os.path.join(HERE, "visual-review.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

usable = [s for s in audit["scenes"] if s["usable"]]
print("staging scenes:", len(staging["scenes"]), "(=", len(audit["scenes"]), "cut-scenes +", len(extra_scenes), "extra windows ) | usable:", len(usable)+sum(1 for e in extra_scenes if e["usable"]))
print("usable ids:", [s["scene_id"] for s in usable])
cats = {}
for s in audit["scenes"]:
    c = s["visual_review"].get("category") or "unreviewed"
    cats[c] = cats.get(c, 0) + 1
print("categories:", json.dumps(cats, ensure_ascii=False))
print("persons:", sum(1 for s in audit["scenes"] if s["visual_review"].get("persons_visible") is True),
      "| consent-needed scenes:", sum(1 for s in audit["scenes"] if s["visual_review"].get("consent_needed")),
      "| burned text:", sum(1 for s in audit["scenes"] if s["visual_review"].get("burned_text_or_watermark")))
print("top20 tiers:", {t: sum(1 for x in TOP if x["tier"] == t) for t in {x["tier"] for x in TOP}})
