#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""المراجعة البصرية الفعلية لأصول الفروع (43 ملفًا) + فهرس مرحلي + أفضل اللقطات.

مبنية على فتح أوراق المعاينة بالنظر: ALL-IMAGES-13.jpg / ALL-VIDEOS-1.jpg / ALL-VIDEOS-2.jpg
لا دمج إنتاجي: staging فقط.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from archive_audit import contact_sheet  # noqa: E402

BASE = os.path.join(HERE, "github-branches", "analysis")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
OUT = os.path.join(HERE, "github-branches")
audit = json.load(open(os.path.join(BASE, "reports", "audit.json"), encoding="utf-8"))
man = json.load(open(os.path.join(OUT, "manifest.json"), encoding="utf-8"))
meta = {os.path.basename(a["working_copy"]): a for a in man["assets"]}

# category, animals, persons, privacy_flags, ad_safe, description
R = {
 "gh-a01": ("animal-handling-market", "buffalo-calf", "face", ["وجه شخص ظاهر"], False,
            "رجل يمسك رأس جاموسة صغيرة في سوق ماشية، ميزان TerraNex الأصفر خلفه."),
 "gh-a02": ("equipment-scale", None, None, [], True,
            "قفص/ميزان الوزن الأصفر بشعار TERRANEX LLC — أصل إثبات نظيف بلا أشخاص ولا حيوانات."),
 "gh-a03": ("monitoring-cctv", "sheep-pen", None, ["لقطة كاميرا مراقبة", "طابع زمني محروق"], False,
            "لقطة شاشة كاميرا مراقبة لحظيرة أغنام مع تاريخ ووقت محروقين."),
 "gh-a04": ("monitoring-cctv-ui", "sheep-pen", None, ["واجهة تطبيق Live View", "طابع زمني"], False,
            "لقطة شاشة تطبيق مراقبة (Live View) بعناصر واجهة ظاهرة — لا تصلح كصورة إعلانية."),
 "gh-a05": ("animal-handling-market", "buffalo-calf", "face", ["وجه شخص ظاهر"], False,
            "نفس مشهد a01 بدقة أعلى (1200×1600) — مكرر بصري."),
 "gh-a06": ("animals-clean", "sheep-goats", None, [], True,
            "خروفان/ماعزان واقفان في الهواء الطلق بجانب سياج وأزهار — أنظف صورة حيوانات في الدفعة."),
 "gh-a07": ("slaughter-carcass", None, "hand", ["ذبائح معلقة", "دماء"], False,
            "ذبيحتان معلقتان على خطاطيف ويد تمسك إحداهما — محتوى حساس يمنع استخدامه إعلانيًا."),
 "gh-a08": ("feeding", "sheep", None, [], True,
            "صف أغنام تأكل من الحوض، لقطة علوية تظهر الظهور والصوف."),
 "gh-a09": ("feeding", "sheep", None, [], True,
            "نفس صف التغذية بزاوية قريبة مختلفة."),
 "gh-a10": ("raw-meat-product", None, "hand", ["لحوم نيئة"], False,
            "صينية لحوم مقطعة يحملها شخص — منتج غذائي لا علاقة له بحملة المتابعة."),
 "gh-a11": ("packaged-meat", None, None, ["لحوم معبأة"], False,
            "صواني لحوم معبأة في عرض/ثلاجة — الصورة ضبابية (حدة 45)."),
 "gh-a12": ("packaged-meat", None, None, ["لحوم معبأة"], False,
            "صواني لحوم معبأة أوضح من a11."),
 "gh-a13": ("packaged-meat", None, None, ["لحوم معبأة"], False,
            "صواني لحوم معبأة على طاولة — لقطة أفقية."),
 "gh-a14": ("slaughter-graphic", "sheep", "face+body", ["ذبح", "بركة دماء", "سكين"], False,
            "عملية ذبح فعلية ودماء على الأرض — يُحجر نهائيًا ولا يدخل أي إعلان."),
 "gh-a15": ("slaughter-graphic", "sheep", "two-persons", ["ذبح", "بركة دماء"], False,
            "عملية ذبح بشخصين ودماء غزيرة — حجر نهائي."),
 "gh-a16": ("animal-handling", "lamb", "hands", [], True,
            "يدان تمسكان رأس حمل حي أسود وأبيض في الهواء الطلق — تعامل هادئ مع الحيوان."),
 "gh-a17": ("farm-pen", "sheep", None, ["مبانٍ سكنية بالخلفية"], True,
            "أغنام في حظيرة/ساحة ترابية مع مبانٍ خلفها — سياق مزرعة حقيقي."),
 "gh-a18": ("animal-full-body", "sheep", None, [], True,
            "خروف كامل الجسم واقف على أرضية خرسانية مع حبل — لقطة جانبية نظيفة."),
 "gh-a19": ("slaughter-graphic", "sheep", "legs", ["ذبح", "دماء على بلاط"], False,
            "ذبح على أرضية بلاط ودماء وأقدام عدة أشخاص — حجر نهائي."),
 "gh-a20": ("animal-handling", "sheep", "hands", [], True,
            "يدان على ظهر خروف — فحص/تثبيت بسيط، الإطار قصير."),
 "gh-a21": ("animal-full-body", "sheep", None, [], True,
            "خروف يمشي مبتعدًا، الجسم كامل من الخلف على أرض ترابية."),
 "gh-a22": ("animal-handling", "lamb", "hands", [], True,
            "نفس محتوى a16 بدقة أقل (848×480) — مكرر بصري."),
 "gh-a23": ("weak-frame", None, "foot", ["إطار أرضية"], False,
            "الإطار الأوسط أرضية ترابية وقدم؛ يحتاج مسح نوافذ للعثور على لحظة صالحة."),
 "gh-a24": ("weighing-context", "goat", None, ["شعار الميزان ظاهر"], True,
            "ماعز أسود وأبيض بجانب ميزان TerraNex الأصفر — سياق وزن حقيقي."),
 "gh-a25": ("weighing-activity", "sheep", "hand", ["شعار TERRANEX LLC ظاهر"], True,
            "خروف عند الميزان الأصفر ويد تمسكه — نشاط وزن موثّق بعلامة الشركة."),
 "gh-a26": ("animals-clean", "sheep", None, [], True,
            "خروفان واقفان في ساحة المزرعة، أجسام كاملة وإضاءة نهارية جيدة."),
 "gh-a27": ("weighing-activity", "sheep", "torso", ["شعار الميزان ظاهر"], True,
            "رجل يقف بجانب خروف عند ميزان TerraNex — أفضل لقطة وزن عمودية."),
 "gh-a28": ("animal-full-body", "sheep", None, [], True,
            "نفس محتوى a18 بدقة أعلى (1024×576) — النسخة المفضّلة."),
 "gh-a29": ("animal-handling", "lamb", "face", ["وجه شخص ظاهر"], False,
            "رجل يحمل حملًا حيًا بين ذراعيه — لقطة قوية لكن الوجه ظاهر ويحتاج موافقة."),
 "gh-a30": ("weak-frame", None, "foot", ["إطار أرضية"], False,
            "نفس محتوى a23 بدقة أعلى؛ الإطار الأوسط أرضية — يحتاج مسح نوافذ."),
 "gh-a31": ("weighing-activity", "sheep", "body", ["شعار الميزان ظاهر"], True,
            "رجل يُدخل خروفًا في الميزان الأصفر — لحظة وزن واضحة (2.63 ث فقط)."),
 "gh-a32": ("slaughter-graphic", "sheep", None, ["ذبيحة", "بركة دماء كبيرة"], False,
            "ذبيحة ملقاة وبركة دماء كبيرة — جودة تقنية عالية لكن المحتوى محجور نهائيًا."),
 "gh-a33": ("weighing-activity", "sheep", None, ["علامة TerraNex LLC محروقة"], True,
            "خروف عند الميزان مع علامة TerraNex LLC محروقة منتصف الكادر — تحتاج شريط إثبات."),
 "gh-a34": ("slaughter-graphic", "sheep", "hands", ["ذبح", "دماء", "سكين"], False,
            "عملية ذبح قريبة ودماء — حجر نهائي رغم الجودة التقنية العالية."),
 "gh-a35": ("weighing-context", "sheep", None, ["شعار الميزان ظاهر"], True,
            "خروف بني وأبيض عند الميزان الأصفر من الخلف."),
 "gh-a36": ("animal-handling", "lamb", "face", ["وجه شخص ظاهر"], False,
            "مكرر بصري مطابق لـa29 (hamming=0) بدقة أقل."),
 "gh-a37": ("weighing-activity", "sheep", "body", [], True,
            "مكرر بصري لـa31 بدقة أقل."),
 "gh-a38": ("animal-inspection", "lamb", "torso", [], True,
            "فم الحمل يُفحص باليد (تقدير العمر/الأسنان) — أقوى مادة «رعاية وفحص» في الدفعة."),
 "gh-a39": ("animals-clean", "sheep", None, ["مبانٍ بالخلفية"], True,
            "خروفان واقفان على منصة/مقطورة حمراء والمزرعة خلفهما — تكوين نظيف."),
 "gh-a40": ("animal-inspection", "lamb", "torso", [], True,
            "مكرر بصري لـa38 بدقة أقل."),
 "gh-a41": ("farm-pen", "sheep", None, ["مبانٍ سكنية بالخلفية"], True,
            "مكرر بصري لـa17 بدقة أقل."),
 "gh-a42": ("animals-clean", "sheep", None, [], True,
            "مكرر بصري لـa39 بدقة أقل."),
 "gh-a43": ("animals-group", "lambs", "legs", [], True,
            "مجموعة حملان في حظيرة، أطول مقطع (63.45 ث) وأعلى جودة عمودية — منجم نوافذ."),
}
R["gh-a27"] = ("weighing-activity", "sheep", "torso", ["شعار الميزان ظاهر"], True,
               "رجل يقف بجانب خروف عند ميزان TerraNex — أفضل لقطة وزن عمودية.")

scenes = {s["source_file"]: s for s in audit["scenes"]}
assets = {}
for a in audit["assets"]:
    aid = a["asset_id"]
    s = scenes[a["file"]]
    m = meta[a["file"]]
    cat, ani, per, flags, safe, desc = R[aid]
    assets[aid] = {
        "asset_id": aid, "file_name": m["file_name"], "original_path": m["original_path"],
        "branches": m["branches"], "git_blob_sha": m["git_blob_sha"], "sha256": m["sha256"],
        "bytes": m["bytes"], "kind": a["kind"],
        "width": s["width"], "height": s["height"], "duration": a["probe"].get("duration"),
        "coded_width": a["probe"].get("coded_width"), "coded_height": a["probe"].get("coded_height"),
        "rotation_degrees": a["probe"].get("rotation_degrees"),
        "orientation": ("portrait" if (s["height"] or 0) > (s["width"] or 0) else "landscape"),
        "has_audio": a["probe"].get("has_audio"), "quality_score": s["quality_score"],
        "metrics": s["metrics"], "motion": s["motion"],
        "fit_vertical_9_16": s["fit_vertical_9_16"], "fit_horizontal_16_9": s["fit_horizontal_16_9"],
        "preview": os.path.relpath(os.path.join(BASE, s["preview"]), REPO),
        "category": cat, "animals": ani, "persons": per, "privacy_flags": flags,
        "ad_safe": safe, "description": desc,
        "integrity": a["integrity"],
    }

# عناقيد التكرار البصري: نُبقي النسخة الأعلى دقة/جودة
pairs = [(p["a"].split("-s")[0], p["b"].split("-s")[0], p["hamming"]) for p in audit["near_duplicates"]]
pref = {}
for x, y, h in pairs:
    ax, ay = assets[x], assets[y]
    kx = (ax["width"] * ax["height"], ax["quality_score"])
    ky = (ay["width"] * ay["height"], ay["quality_score"])
    keep, drop = (x, y) if kx >= ky else (y, x)
    pref[drop] = {"duplicate_of": keep, "hamming": h}
for aid, d in pref.items():
    assets[aid]["visual_duplicate_of"] = d["duplicate_of"]
    assets[aid]["hamming"] = d["hamming"]

eligible = [a for a in assets.values()
            if a["ad_safe"] and "visual_duplicate_of" not in a]
quarantined = [a["asset_id"] for a in assets.values() if a["category"].startswith("slaughter")]

staging = {
    "schema_version": 1, "kind": "staging-index",
    "compatible_with": "scene-library/index.json",
    "merge_approved": False, "merge_into_scene_library": False,
    "source": "فروع GitHub الأربعة — بايتات فعلية عبر git cat-file",
    "existing_library_untouched": True,
    "link_to_existing_library": {
        "existing_sources": ["src-01 (01-بومو-الشركة-الرئيسي)", "src-04 (04-الأربعاء-الوزن-على-الطبيعة)"],
        "proposed_new_source_ids": {f"gh-{a['asset_id'][3:]}": a["file_name"] for a in assets.values()},
        "note": "ربط منطقي فقط: كل مشهد مرحلي يحمل source_sha256 ليُدمج لاحقًا كمصدر جديد بعد موافقة المالك.",
    },
    "counts": {"assets": len(assets), "ad_eligible_after_dedupe": len(eligible),
               "visual_duplicate_clusters": len(pairs), "quarantined_slaughter": len(quarantined)},
    "quarantine": {"ids": quarantined, "rule": "محتوى ذبح/دماء — ممنوع في أي إعلان أو معاينة ترويجية"},
    "scenes": [{
        "scene_id": a["asset_id"] + "-s01", "source_sha256": a["sha256"],
        "source_file": a["file_name"], "git_blob_sha": a["git_blob_sha"],
        "branches": a["branches"], "kind": a["kind"],
        "start": 0.0, "end": a["duration"] or 0.0,
        "width": a["width"], "height": a["height"],
        "orientation": a["orientation"], "rotation_degrees": a["rotation_degrees"],
        "tags": [t for t in [a["category"], a["animals"]] if t],
        "description": a["description"], "quality": a["quality_score"],
        "usable": a["ad_safe"] and "visual_duplicate_of" not in a,
        "persons_visible": a["persons"], "privacy_flags": a["privacy_flags"],
        "consent_needed": a["persons"] in ("face", "face+body", "two-persons"),
        "burned_text": bool(a["privacy_flags"]),
        "preview": a["preview"], "tagged_by": "arena-visual-review",
        "staging": True, "merge_approved": False,
    } for a in assets.values()],
}
json.dump(staging, open(os.path.join(OUT, "staging-index.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
json.dump({"assets": assets, "duplicate_clusters": pref,
           "reviewer": "arena-visual-review-of-contact-sheets",
           "sheets_reviewed": ["ALL-IMAGES-13.jpg", "ALL-VIDEOS-1.jpg", "ALL-VIDEOS-2.jpg"]},
          open(os.path.join(OUT, "visual-review.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)

TOP = ["gh-a02", "gh-a06", "gh-a27", "gh-a38", "gh-a25", "gh-a43", "gh-a26", "gh-a39",
       "gh-a16", "gh-a28", "gh-a08", "gh-a21", "gh-a31", "gh-a17", "gh-a35", "gh-a24",
       "gh-a09", "gh-a33", "gh-a20", "gh-a12"]
items = []
for aid in TOP:
    a = assets[aid]
    items.append({"preview": os.path.join(REPO, a["preview"]),
                  "label": f'{aid} {a["category"][:20]}',
                  "sub": f'{a["width"]}x{a["height"]} Q={a["quality_score"]:.2f}'})
contact_sheet(items, os.path.join(BASE, "contact-sheets", "BEST-20-AD-SAFE.jpg"), cols=5,
              title="BEST 20 AD-SAFE (duplicates removed, slaughter quarantined)")

print("assets:", len(assets), "| ad-eligible after dedupe:", len(eligible))
print("quarantined slaughter:", quarantined)
print("duplicate clusters (drop -> keep):", json.dumps(pref, ensure_ascii=False))
print("eligible ids:", [a["asset_id"] for a in eligible])
