#!/usr/bin/env python3
"""ingest_footage.py — تنظيم المواد الخام (الفوتاج) الواردة من التصوير.

  python engine/ingest_footage.py            # يلتقط كل ما في الوارد وينظمه
  python engine/ingest_footage.py --dry      # تقرير بدون نقل

آلية العمل:
  • يمسح تسويق/مواد-خام/وارد/ (المستخدم يحط اللقطات هنا — شغله اليدوي الوحيد).
  • بصمة md5 لكل ملف ← يمنع التكرار (قاعدة «مصدر واحد لكل منشور» تبدأ من هنا).
  • فحص بالـffmpeg: مدة/أبعاد/fps/صوت.
  • ينقل الصالح إلى مواد-خام/أرشيف/YYYY-MM/ باسم موحّد: التاريخ-الاسم.
  • يحدّث سجل المواد: مواد-خام/سجل-المواد-الخام.csv (مصدر الحقيقة لأي لقطة).
الحالات: متاح (جاهز للمونتاج) · مكرر (مرفوض، md5 موجود من قبل) · مش-فيديو (يتجاهل).
لا شبكة · لا حذف لملفات الوارد المكررة (تُنقل إلى مكررات/ للمراجعة البشرية).
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_video  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARKETING = os.path.dirname(os.path.dirname(ROOT))          # .../تسويق
# TX_RAW_DIR: يستخدمها selfcheck لعزل الاختبار في مجلد مؤقت
RAW = os.environ.get("TX_RAW_DIR", os.path.join(MARKETING, "مواد-خام"))
INBOX = os.path.join(RAW, "وارد")
ARCHIVE = os.path.join(RAW, "أرشيف")
DUPES = os.path.join(RAW, "مكررات")
LEDGER = os.path.join(RAW, "سجل-المواد-الخام.csv")

EXT = {".mp4", ".mov", ".m4v", ".webm", ".mkv", ".3gp", ".jpg", ".jpeg", ".png", ".heic", ".m4a", ".aac", ".wav"}
FIELDS = ["معرف", "الاسم_الأصلي", "الملف_الحالي", "md5", "تاريخ_الاستلام", "النوع",
          "المدة_ث", "الأبعاد", "fps", "صوت", "الحالة", "استُخدم_في", "ملاحظة"]


def md5(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_ledger() -> list[dict]:
    if not os.path.exists(LEDGER):
        return []
    with open(LEDGER, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def save_ledger(rows: list[dict]) -> None:
    os.makedirs(os.path.dirname(LEDGER), exist_ok=True)
    with open(LEDGER, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)


def describe(path: str) -> dict:
    """وصف سريع عبر qa_video.probe — يرجع مدة/أبعاد/fps/وجود صوت."""
    try:
        m = qa_video.probe(path)
    except Exception:
        return {}
    return {
        "مدة": round(m.get("duration") or 0, 2),
        "أبعاد": f"{m.get('width') or 0}x{m.get('height') or 0}",
        "fps": int(m.get("fps") or 0),
        "صوت": "نعم" if m.get("has_audio") else "لا",
    }


def run(dry: bool = False) -> dict:
    os.makedirs(INBOX, exist_ok=True)
    rows = load_ledger()
    seen = {r["md5"]: r for r in rows}
    results = {"accepted": [], "dupes": [], "skipped": []}

    files = sorted(os.listdir(INBOX))
    today = dt.date.today()
    bucket = os.path.join(ARCHIVE, today.strftime("%Y-%m"))

    nxt = max([int(r["معرف"].lstrip("FX") or 0) for r in rows if r["معرف"].startswith("FX")] or [0]) + 1
    for name in files:
        src = os.path.join(INBOX, name)
        if not os.path.isfile(src):
            continue
        ext = os.path.splitext(name)[1].lower()
        if ext not in EXT:
            results["skipped"].append(f"{name} (صيغة غير معروفة — تُرك في الوارد)")
            continue
        digest = md5(src)
        if digest in seen:
            results["dupes"].append(f"{name} (مكرر لـ{seen[digest]['الملف_الحالي']})")
            if not dry:
                os.makedirs(DUPES, exist_ok=True)
                shutil.move(src, os.path.join(DUPES, name))
            continue
        info = describe(src)
        kind = ("فيديو" if info.get("fps") else ("صوت" if info.get("مدة") and ext not in (".jpg", ".jpeg", ".png", ".heic") else "صورة"))
        fid = f"FX{nxt:03d}"
        nxt += 1
        safe = name.replace(" ", "-")
        dest_rel = os.path.join("مواد-خام/أرشيف", today.strftime("%Y-%m"), f"{today.isoformat()}-{safe}")
        if not dry:
            os.makedirs(bucket, exist_ok=True)
            shutil.move(src, os.path.join(bucket, f"{today.isoformat()}-{safe}"))
        rows.append({
            "معرف": fid, "الاسم_الأصلي": name, "الملف_الحالي": dest_rel,
            "md5": digest, "تاريخ_الاستلام": today.isoformat(), "النوع": kind,
            "المدة_ث": info.get("مدة", ""), "الأبعاد": info.get("أبعاد", ""),
            "fps": info.get("fps", ""), "صوت": info.get("صوت", ""),
            "الحالة": "متاح", "استُخدم_في": "", "ملاحظة": "",
        })
        seen[digest] = rows[-1]
        results["accepted"].append(f"{fid}: {name} → {dest_rel} ({info.get('أبعاد','?')} · {info.get('مدة','?')}ث)")

    if not dry and (files or not os.path.exists(LEDGER)):
        save_ledger(rows)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry", action="store_true", help="تقرير فقط بدون نقل/تسجيل")
    a = ap.parse_args()
    r = run(a.dry)
    tag = " (تجربة — بدون تغيير)" if a.dry else ""
    print(f"\n📥 استلام المواد الخام{tag}")
    print(f"   ✅ اتقبل منظّم: {len(r['accepted'])}")
    for x in r["accepted"]:
        print(f"      {x}")
    print(f"   ♻️  مكرر مرفوض: {len(r['dupes'])}")
    for x in r["dupes"]:
        print(f"      {x}")
    for x in r["skipped"]:
        print(f"   ⏭️  {x}")
    if not r["accepted"] and not r["dupes"] and not r["skipped"]:
        print("   الوارد فاضي — حط اللقطات الجديدة في مواد-خام/وارد/")
    print()


if __name__ == "__main__":
    main()
