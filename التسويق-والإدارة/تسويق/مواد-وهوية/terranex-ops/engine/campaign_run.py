#!/usr/bin/env python3
"""campaign_run.py — منسّق الحملة المتكامل: من موجز الحملة إلى حزمة نشر جاهزة.

  python engine/campaign_run.py --brief campaigns/<اسم>/موجز.json
  python engine/campaign_run.py --brief ... --dry-run     # تحقق فقط بدون كتابة
  python engine/campaign_run.py --brief ... --register    # قيد في جدول النشر العام (مع منع تكرار)

الخطوات لكل منشور: فحص جودة (qa_video) ← بوابة التزام (critic) ← تجهيز/نسخ
(اختياري نسخ منصات variants) ← تجميع تقرير حملة + جدول قيد + قالب قياس للفريق.

لا نشر فعليًّا — الحدود البشرية ثابتة (النشر والتواصل قرار إنسان). لا شبكة.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "output")
CAMPAIGNS = os.path.join(OUT, "campaigns")

import critic          # noqa: E402
import package_post    # noqa: E402
import qa_video        # noqa: E402
import gen_calendar    # noqa: E402
import make_montage    # noqa: E402


def load_brief(path: str) -> dict:
    b = json.loads(open(path, encoding="utf-8").read())
    assert b.get("name"), "الموجز يحتاج name"
    assert b.get("posts"), "الموجز يحتاج posts[]"
    return b


def stage_paths(b: dict) -> dict:
    cdir = os.path.join(CAMPAIGNS, b["name"])
    return {
        "dir": cdir,
        "captions": os.path.join(cdir, "captions"),
        "media": os.path.join(cdir, "media-ready"),
        "report": os.path.join(cdir, f"{dt.date.today().isoformat()}-تقرير-الحملة.md"),
        "queue": os.path.join(cdir, "queue-campaign.csv"),
        "metrics": os.path.join(cdir, "قياس-الحملة-يملؤه-الفريق.csv"),
    }


def run_post(idx: int, p: dict, b: dict, paths: dict, dry: bool, rep_rows: list) -> dict:
    """منشور واحد عبر البوابات. يرجع سطر تقرير."""
    title = p.get("title") or os.path.splitext(os.path.basename(p["video"]))[0]
    row = {"idx": idx + 1, "title": title, "video": p["video"], "ok": False}

    if not os.path.isfile(p["video"]):
        row["reason"] = f"الفيديو غير موجود: {p['video']}"
        rep_rows.append(row)
        return row
    if not os.path.isfile(p["caption"]):
        row["reason"] = f"الكابشن غير موجود: {p['caption']}"
        rep_rows.append(row)
        return row

    qa = qa_video.qa(p["video"], p.get("profile", "reels"))
    row["qa"] = "PASS" if qa["pass"] else "FAIL: " + "؛".join(qa["fails"] + qa["warns"])
    if not qa["pass"]:
        row["reason"] = "فشل فحص الجودة"
        rep_rows.append(row)
        return row

    caption = open(p["caption"], encoding="utf-8").read()
    cr = critic.check(caption, (b["platforms"] or ["facebook"])[0])
    row["critic"] = cr["score"]
    if cr["hard"] or cr["decision"] == "ارفض":
        row["reason"] = "مخالفة التزام (hard) — " + "؛".join(h["msg"] for h in cr["hard"][:2])
        rep_rows.append(row)
        return row

    if dry:
        row["ok"] = True
        row["reason"] = "تحقق جاف ✓"
        rep_rows.append(row)
        return row

    # تجهيز فعلي داخل مجلد الحملة (بعيدًا عن جدول queue العام)
    os.makedirs(paths["captions"], exist_ok=True)
    os.makedirs(paths["media"], exist_ok=True)
    cap_dest = os.path.join(paths["captions"], os.path.basename(p["caption"]))
    shutil.copyfile(p["caption"], cap_dest)
    vid_dest = os.path.join(paths["media"], os.path.basename(p["video"]))
    if os.path.abspath(p["video"]) != os.path.abspath(vid_dest):
        shutil.copyfile(p["video"], vid_dest)

    row["ok"] = True
    row["date"] = p.get("date", b["start"])
    row["time"] = p.get("time", b.get("time", "20:00"))
    row["hook"] = caption.strip().splitlines()[0][:80] if caption.strip() else ""
    rep_rows.append(row)
    return row


def run_extras(b: dict, paths: dict, dry: bool, rep_rows: list) -> None:
    """إضافات الحملة (مونتاج من مواد حقيقية لنفس الحملة)."""
    for ex in b.get("extras", []):
        if ex.get("type") == "montage":
            title = ex.get("title", "مونتاج-الحملة")
            row = {"idx": "★", "title": title, "ok": False}
            clips, trims = ex["clips"], ex.get("trims", "")
            out = os.path.join(paths["media"], f"{title}.mp4")
            missing = [c for c in clips if not os.path.isfile(c)]
            if missing:
                row["reason"] = "لقطات غير موجودة: " + "،".join(os.path.basename(c) for c in missing)
                rep_rows.append(row)
                continue
            if not dry:
                os.makedirs(paths["media"], exist_ok=True)
                trims_list = make_montage.parse_trims(trims or None, len(clips))
                r = make_montage.montage(clips, trims_list, out, (1080, 1920))
                if not isinstance(r, dict) or r.get("clips", 0) == 0:
                    row["reason"] = "فشل المونتاج"
                    rep_rows.append(row)
                    continue
                qa = qa_video.qa(out, "reels")
                row["qa"] = "PASS" if qa["pass"] else "FAIL: " + "؛".join(qa["fails"])
                if not qa["pass"]:
                    row["reason"] = "المونتاج فشل فحص الجودة"
                    rep_rows.append(row)
                    continue
                row["video"] = out
            row["ok"] = True
            row["critic"] = "-"
            row.setdefault("hook", ex.get("hook", ""))
            row["date"] = ex.get("date", b["start"])
            rep_rows.append(row)


def write_queue(b: dict, paths: dict, rows: list, register: bool) -> int:
    """جدول الحملة + (اختياريًا) قيد في الجدول العام مع منع التكرار."""
    ok_rows = [r for r in rows if r.get("ok") and r.get("video") and r.get("idx") != "★"]
    ok_rows += [r for r in rows if r.get("ok") and r.get("idx") == "★" and r.get("video")]
    fields = ["date", "time", "platform", "title", "hook", "source_clip", "critic_score", "qa", "status", "variants"]
    n = 0
    with open(paths["queue"], "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in ok_rows:
            for p in b["platforms"]:
                w.writerow({"date": r.get("date", b["start"]), "time": r.get("time", "20:00"),
                            "platform": p, "title": r["title"], "hook": r.get("hook", ""),
                            "source_clip": r["video"], "critic_score": r.get("critic", "-"),
                            "qa": "ok", "status": "بانتظار-موافقة", "variants": "-"})
                n += 1
    if register:
        master = package_post.read_queue()
        key = {(q["date"], q["platform"], q["title"]) for q in master}
        added = 0
        for r in ok_rows:
            for p in b["platforms"]:
                k = (r.get("date", b["start"]), p, r["title"])
                if k in key:
                    continue
                master.append({"date": k[0], "time": r.get("time", "20:00"), "platform": p,
                               "title": r["title"], "hook": r.get("hook", ""),
                               "source_clip": r["video"], "critic_score": str(r.get("critic", "-")),
                               "qa": "ok", "status": "بانتظار-موافقة", "variants": "-"})
                key.add(k)
                added += 1
        package_post.write_queue(master)
        return added
    return n


def write_metrics_template(b: dict, paths: dict, rows: list) -> None:
    """قالب قياس يملؤه الفريق من لوحات المنصات (لا واجهات API — إدخال بشري)."""
    with open(paths["metrics"], "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["date", "platform", "title", "hook", "pillar",
                                          "views", "saves", "inquiries", "critic_score"])
        w.writeheader()
        for r in rows:
            if not r.get("ok") or r.get("idx") == "★":
                continue
            for p in b["platforms"]:
                w.writerow({"date": r.get("date", b["start"]), "platform": p, "title": r["title"],
                            "hook": r.get("hook", "")[:40], "pillar": r.get("pillar", ""),
                            "views": "", "saves": "", "inquiries": "",
                            "critic_score": r.get("critic", "")})


def write_report(b: dict, paths: dict, rows: list, mm: list, queued: int, register: bool) -> str:
    ok = [r for r in rows if r.get("ok")]
    bad = [r for r in rows if not r.get("ok")]
    L = [f"# تقرير حملة: {b['name']}",
         f"التاريخ: {dt.date.today().isoformat()} · البداية المخططة: {b['start']} · "
         f"المنصات: {'، '.join(b['platforms'])}", "",
         f"**النتيجة: {len(ok)}/{len(rows)} منشور اجتاز البوابات** — "
         f"{'فشل ' + str(len(bad)) + ' (انظر الأسباب)' if bad else 'لا فشل.'}", "",
         "## المنشورات", "",
         "| # | العنوان | QA | درجة critic | التاريخ | الحالة |",
         "|---|---|---|---|---|---|"]
    for r in rows:
        L.append(f"| {r['idx']} | {r['title']} | {r.get('qa', '—')} | {r.get('critic', '—')} | "
                 f"{r.get('date', '—')} | {'✅ جاهز' if r.get('ok') else '❌ ' + r.get('reason', 'فشل')} |")
    L += ["",
          "## الجدولة",
          f"- جدول الحملة: `{os.path.relpath(paths['queue'], ROOT)}` ({queued} سطر"
          + (" [أُضيف للجدول العام]" if register else " [لم يُقيد بالجدول العام — استخدم --register]") + ")",
          f"- قالب القياس (يملؤه الفريق يدويًا بعد النشر): `{os.path.relpath(paths['metrics'], ROOT)}`",
          "",
          "## الخطوات التالية",
          "1. موافقة بشرية على الكابشنات والمونتاج (بوابة الالتزام لا تكفي وحدها).",
          "2. النشر اليدوي وفق الجدول — لا نشر آلي.",
          "3. بعد 7 أيام: الفريق يعبّئ قالب القياس من لوحات المنصات ← `measure.py --csv <ملف> --append`.",
          "",
          "## مخرجات المنسّق الوسيطة",
          f"- {mm[0]} | {mm[1]} | {mm[2]}"]
    os.makedirs(os.path.dirname(paths["report"]), exist_ok=True)
    open(paths["report"], "w", encoding="utf-8").write("\n".join(L))
    return paths["report"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--brief", required=True, help="موجز الحملة JSON")
    ap.add_argument("--dry-run", action="store_true", help="تحقق فقط بدون تجهيز أو كتابة")
    ap.add_argument("--register", action="store_true", help="قيد في جدول النشر العام (منع تكرار تلقائي)")
    a = ap.parse_args()

    b = load_brief(a.brief)
    b.setdefault("platforms", ["facebook", "instagram"])
    b.setdefault("start", dt.date.today().isoformat())
    paths = stage_paths(b)

    print(f"🚀 منسّق الحملة — {b['name']} ({len(b['posts'])} منشور + {len(b.get('extras', []))} إضافة")
    if a.dry_run:
        print("   وضع جاف: بدون تجهيز أو كتابة")

    rep_rows: list = []
    for i, p in enumerate(b["posts"]):
        r = run_post(i, p, b, paths, a.dry_run, rep_rows)
        print(f"   {'✅' if r.get('ok') else '❌'} [{r['idx']}] {r['title']} — "
              + (r.get("reason", "جاهز") if r.get("ok") is not True else "جاهز"))

    # تقويم مرجعي (يحترم سقف المادة الحقيقية)
    if not a.dry_run:
        os.makedirs(paths["dir"], exist_ok=True)
        cal = gen_calendar.enforce_cap(gen_calendar.build(days=max(7, len(b["posts"]) + 1),
                                                          start=dt.date.fromisoformat(b["start"])))
        open(os.path.join(paths["dir"], "calendar.md"), "w", encoding="utf-8").write(
            gen_calendar.to_md(cal, title=f"مرجع محاور — حملة {b['name']}"))
        shutil.copyfile(a.brief, os.path.join(paths["dir"], "موجز.json"))

    run_extras(b, paths, a.dry_run, rep_rows)

    ok = [r for r in rep_rows if r.get("ok")]
    queued = 0
    if not a.dry_run:
        queued = write_queue(b, paths, rep_rows, a.register)
        write_metrics_template(b, paths, rep_rows)
        rep = write_report(b, paths, rep_rows,
                           [os.path.relpath(paths["captions"], ROOT),
                            os.path.relpath(paths["media"], ROOT),
                            os.path.relpath(paths["queue"], ROOT)],
                           queued if not a.register else queued, a.register)
        print(f"\n📄 تقرير الحملة: {os.path.relpath(rep, ROOT)}")

    print(f"\nالنتيجة: {len(ok)}/{len(rep_rows)} اجتاز البوابات"
          + (f" · {queued} سطر جدول" if not a.dry_run else " · (جاف)"))
    if all(r.get("ok") for r in rep_rows):
        print("الحملة جاهزة لبوابة الموافقة البشرية ✅")
        return 0
    bad = [r for r in rep_rows if not r.get("ok")]
    print("⚠️ منشورات تحتاج معالجة:")
    for r in bad:
        print(f"   ❌ {r['title']}: {r.get('reason', '?')}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
