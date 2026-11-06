#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""يفحص النسختين المؤلَّفتين ضد قرارات المالك — يعمل في جلسة جديدة بلا وسائط.

يقرأ الـspec فقط، فلا يحتاج الفيديوهات الخام؛ هذا يجعل الامتثال قابلًا لإعادة التحقق
في أي وقت حتى قبل استعادة المواد.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OPS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
G = os.path.join(OPS, "archive-intake", "github-branches")
vr = json.load(open(os.path.join(G, "visual-review.json"), encoding="utf-8"))["assets"]
stg = json.load(open(os.path.join(G, "staging-index.json"), encoding="utf-8"))
QUAR = set(stg["quarantine"]["ids"])
CCTV = {"gh-a03", "gh-a04"}
FACES = {k for k, v in vr.items() if v.get("persons") in ("face", "face+body", "two-persons")}
CITY_BAN = ("الإسكندرية",)

checks, failures = [], []


def chk(name, ok, detail=""):
    checks.append({"check": name, "pass": bool(ok), "detail": detail})
    if not ok:
        failures.append(f"{name}: {detail}")


for v in ("a", "b"):
    sp = json.load(open(os.path.join(HERE, f"spec-{v}.json"), encoding="utf-8"))
    ids = [c["_asset_id"] for c in sp["clips"]]
    chk(f"{v}: لا أصل محجور", not (set(ids) & QUAR), str(set(ids) & QUAR))
    chk(f"{v}: لا كاميرات مراقبة", not (set(ids) & CCTV), str(set(ids) & CCTV))
    chk(f"{v}: لا وجه بلا موافقة", not (set(ids) & FACES), str(set(ids) & FACES))
    chk(f"{v}: لا أشخاص معلنون بلا إذن",
        not sp["on_screen_persons"] or sp["consent_persons"], "")
    chk(f"{v}: المدة 20.0", abs(sp["_total_sec"] - 20.0) < 1e-6, str(sp["_total_sec"]))
    chk(f"{v}: محتوى 17.0 + كارت 3.0",
        abs(sp["_content_sec"] - 17.0) < 1e-6 and sp["endcard_sec"] == 3.0, "")
    chk(f"{v}: بلا حدّة صناعية", all(c.get("sharpen") is False for c in sp["clips"]), "")
    chk(f"{v}: تحجيم lanczos", all(c.get("scale_flags") == "lanczos" for c in sp["clips"]), "")
    chk(f"{v}: شريط كابشن واحد ثابت", sp.get("caption_cy") == 0.84, str(sp.get("caption_cy")))
    chk(f"{v}: بلا صندوق hook يغطي العلامة", not sp.get("hook"), "")
    chk(f"{v}: لا رقم وزن في الكابشن",
        not any(re.search(r"\d", c["text"]) for c in sp["captions"]), "")
    chk(f"{v}: لا ذكر مدينة",
        not any(b in c["text"] for c in sp["captions"] for b in CITY_BAN), "")
    chk(f"{v}: كل النوافذ داخل المصدر",
        all(0 <= c["start"] < c["end"] <= (vr[c["_asset_id"]]["duration"] or 1e9)
            for c in sp["clips"] if c["_asset_id"] in vr), "")
    chk(f"{v}: التكبير ≤ 2.3×",
        max(c["_upscale_to_1080x1920"] for c in sp["clips"]) <= 2.3, "")
    chk(f"{v}: مزج مادة أعلى دقة",
        any(c["_asset_id"].startswith("old-") for c in sp["clips"]), "")
    chk(f"{v}: غير مصرح بالنشر", sp.get("publish_approved") is False, "")
    chk(f"{v}: مسودة بصرية", sp.get("visual_draft") is True, "")
    chk(f"{v}: إفصاح صامت على الكارت",
        "بدون تعليق صوتي" in sp["endcard"]["disclosure"], "")
    chk(f"{v}: كل لقطة موثقة ببصمة",
        all(c.get("_source_sha256") or c["_asset_id"].startswith("old-") for c in sp["clips"]), "")

vo = json.load(open(os.path.join(HERE, "vo-proposals.json"), encoding="utf-8"))
chk("vo: لا صوت مولَّد", vo["generated_audio"] is False, "")
chk("vo: غير معتمد", vo["adopted"] is False, "")
chk("vo: النص القديم غير معتمد", vo["old_script_adopted"] is False, "")
chk("vo: v3 غير معتمد", vo["v3_adopted"] is False, "")
chk("vo: مقترحان", len(vo["proposals"]) == 2, str(len(vo["proposals"])))
chk("vo: لا رقم وزن",
    not any(re.search(r"\d", ln["text"]) for p in vo["proposals"] for ln in p["lines"]), "")

mm = json.load(open(os.path.join(HERE, "media-manifest.json"), encoding="utf-8"))
chk("media: خام خارج Git", mm["raw_media_in_git"] is False, "")
chk("media: أوامر استعادة موجودة", len(mm["restore_in_new_session"]) >= 4, "")
chk("media: كل أصل له blob وsha",
    all(a["git_blob_sha"] and a["sha256"] for a in mm["assets"]), "")

res = {"total": len(checks), "passed": sum(c["pass"] for c in checks),
       "failed": failures, "checks": checks}
with open(os.path.join(HERE, "evidence", "compliance.json"), "w", encoding="utf-8") as f:
    json.dump(res, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f'compliance: {res["passed"]}/{res["total"]} passed')
for fl in failures:
    print("  FAIL", fl)
sys.exit(1 if failures else 0)
