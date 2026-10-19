#!/usr/bin/env python3
"""package_post.py — تجهيز منشور للنشر: فحص جودة + التزام + قيد في جدول النشر.

  python engine/package_post.py --video "../فيديوهات-جاهزة-للنشر/04-….mp4" \\
      --caption output/captions/04.txt --platforms "facebook,instagram" \\
      --date 2026-10-22 --time 20:00

البنود المنفذة (مطابقة لـcommands/review.md):
  1. qa_video (بروفايل reels أو deck) — الفشل يوقف الحزمة.
  2. critic.py على الكابشن — أي Hard Ban يوقف الحزمة.
  3. نسخة الكابشن تُحفظ بجوار الفيديو في output/captions/.
  4. سطر في output/queue.csv بحالة «بانتظار-موافقة» — يُلزم رقم المنصة والوقت.
  5. --variants: يولّد نسخ المنصات (reels/feed45/square) عبر make_variants.

بوابة بشرية دائمة: لا نشر آلي ولا حالة «منشور» من هنا أبدًا — التحويل يتم يدويًا
بعد نشر المستخدم فعليًا. لا شبكة، لا أسرار.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import critic  # noqa: E402
import qa_video  # noqa: E402
import make_variants  # noqa: E402

ROOT = os.environ.get("TX_OPS_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# TX_OUT_DIR: يستخدمها selfcheck لعزل الاختبار في مجلد مؤقت
OUT = os.environ.get("TX_OUT_DIR", os.path.join(ROOT, "output"))
QUEUE = os.path.join(OUT, "queue.csv")
Q_FIELDS = ["date", "time", "platform", "title", "hook", "source_clip",
            "critic_score", "qa", "status", "variants"]


def read_queue() -> list[dict]:
    if not os.path.exists(QUEUE):
        return []
    with open(QUEUE, encoding="utf-8") as f:
        return list(csv.DictReader(f))


def write_queue(rows: list[dict]) -> None:
    os.makedirs(OUT, exist_ok=True)
    with open(QUEUE, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=Q_FIELDS)
        w.writeheader()
        w.writerows(rows)


def package(video: str, caption_path: str, platforms: list[str], date: str, time_: str,
            profile: str = "reels", variants: bool = False, title: str | None = None) -> dict:
    stem = os.path.splitext(os.path.basename(video))[0]
    rep: dict = {"video": video, "ok": False, "steps": []}

    qa = qa_video.qa(video, profile)
    rep["steps"].append(("qa_video", qa["pass"], qa["fails"] + qa["warns"]))
    if not qa["pass"]:
        rep["reason"] = "فشل فحص الجودة"
        return rep

    caption = open(caption_path, encoding="utf-8").read()
    cr = critic.check(caption, platforms[0] if platforms else "facebook")
    rep["steps"].append(("critic", not cr["hard"], [h["msg"] for h in cr["hard"]] + [h["msg"] for h in cr["soft"]]))
    if cr["hard"]:
        rep["reason"] = "Hard Ban في الكابشن"
        return rep
    if cr["decision"] == "ارفض":
        rep["reason"] = f"درجة critic منخفضة ({cr['score']})"
        return rep

    cap_dir = os.path.join(OUT, "captions")
    os.makedirs(cap_dir, exist_ok=True)
    cap_dest = os.path.join(cap_dir, f"{stem}.txt")
    shutil.copyfile(caption_path, cap_dest)

    var_list = "-"
    if variants:
        vdir = os.path.join(OUT, "variants", stem)
        made = make_variants.build(video, vdir)
        var_list = "+".join(m["variant"] for m in made)
        rep["steps"].append(("variants", True, [os.path.basename(m["path"]) for m in made]))

    rows = read_queue()
    hook = caption.strip().splitlines()[0][:80] if caption.strip() else ""
    for p in platforms:
        rows.append({"date": date, "time": time_, "platform": p,
                     "title": title or stem, "hook": hook, "source_clip": video,
                     "critic_score": cr["score"], "qa": "ok",
                     "status": "بانتظار-موافقة", "variants": var_list})
    write_queue(rows)

    rep["ok"] = True
    rep["critic_score"] = cr["score"]
    rep["queued"] = len(platforms)
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--caption", required=True)
    ap.add_argument("--platforms", default="facebook,instagram")
    ap.add_argument("--date", default=dt.date.today().isoformat())
    ap.add_argument("--time", default="20:00")
    ap.add_argument("--profile", choices=["reels", "deck", "any"], default="reels")
    ap.add_argument("--variants", action="store_true")
    ap.add_argument("--title", default=None)
    a = ap.parse_args()

    rep = package(a.video, a.caption, [p.strip() for p in a.platforms.split(",") if p.strip()],
                  a.date, a.time, a.profile, a.variants, a.title)
    print(f"\n📦 تجهيز منشور: {os.path.basename(a.video)}")
    for name, ok, notes in rep["steps"]:
        print(f"   {'✅' if ok else '⛔'} {name}" + (f" — {'؛ '.join(notes)}" if notes and not ok else ""))
    if rep["ok"]:
        print(f"\n   ✅ جاهز: critic={rep['critic_score']} · اتقيد في queue.csv "
              f"({rep['queued']} منصة · {a.date} {a.time}) · الحالة: بانتظار-موافقة")
        print("   البوابة البشرية: النشر الفعلي يتم يدويًا، وبعده حوّل الحالة إلى «منشور» في output/queue.csv")
    else:
        print(f"\n   ⛔ مرفوض: {rep.get('reason')}")
    print()
    sys.exit(0 if rep["ok"] else 1)


if __name__ == "__main__":
    main()
