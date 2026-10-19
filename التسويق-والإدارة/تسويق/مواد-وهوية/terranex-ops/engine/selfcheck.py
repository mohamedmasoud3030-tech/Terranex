#!/usr/bin/env python3
"""selfcheck.py — فحص صحة شامل لنظام terranex-ops (شغّله أولًا في أي جلسة جديدة).

  python engine/selfcheck.py          # فحص كامل؛ خروج 0 = الكل سليم
  python engine/selfcheck.py --quick  # بدون اختبارات الفيديو (أسرع)

يختبر فعليًا (مش افتراض): التبعيات، الخطوط، اللوحة، تشكيل العربي،
بوستر كامل، فيديو كامل بصوت، فحص الجودة، الالتزام، التقويم، استلام الفوتاج،
وتجهيز المنشور — كلها في مجلد مؤقت معزول (لا يكتب أي شيء في المشروع).

أي FAIL ليه إصلاح مقترح يُطبع تحته. أول إصلاح أولًا: bash setup.sh
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

ENGINE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(ENGINE)
sys.path.insert(0, ENGINE)

RESULTS: list[tuple[str, bool, str]] = []


def record(name: str, ok: bool, note: str = "") -> None:
    RESULTS.append((name, bool(ok), note))


def run(cmd: list[str], env: dict | None = None, cwd: str | None = None) -> subprocess.CompletedProcess:
    e = dict(os.environ)
    if env:
        e.update(env)
    return subprocess.run(cmd, capture_output=True, text=True, timeout=900, cwd=cwd or ROOT, env=e)


def check_deps() -> None:
    missing = []
    for mod in ["PIL", "numpy", "imageio_ffmpeg", "uharfbuzz", "bidi", "freetype"]:
        try:
            __import__(mod)
        except Exception as ex:
            missing.append(f"{mod} ({ex.__class__.__name__})")
    record("التبعيات (pillow/numpy/ffmpeg/uharfbuzz/bidi/freetype)", not missing,
           ("ناقص: " + "، ".join(missing) + " → bash setup.sh") if missing else "")
    if missing:
        raise SystemExit(_report())


def check_fonts() -> None:
    import brand as B
    missing = [n for n in B.FONTS.values()
               if not os.path.exists(os.path.join(B.FONT_DIR, n))]
    try:
        f = B.font("black", 48)
        ok = f is not None and getattr(f, "art_path", "").endswith(".ttf")
    except Exception as ex:
        ok = False
        missing.append(str(ex))
    record("الخطوط (Tajawal/Cairo موجودة وتُحمّل)", ok and not missing,
           "، ".join(missing))


def check_palette() -> None:
    try:
        with open(os.path.join(ROOT, "context", "palette.json"), encoding="utf-8") as f:
            pal = json.load(f)
        need = ["gold", "gold_hi", "gold_mid", "gold_deep", "green", "bg_dark", "bg_mid", "bg_cream"]
        missing = [k for k in need if k not in pal.get("final", {})]
        record("اللوحة (palette.json من الشعار)", not missing, "ناقص: " + "، ".join(missing))
    except Exception as ex:
        record("اللوحة (palette.json من الشعار)", False, f"{ex} → python engine/derive_palette.py")


def check_arabic() -> None:
    import artext
    import brand as B
    f_title = B.font("black", 96)
    f_reg = B.font("regular", 40)
    try:
        s = "بينك وبين رأسك… خيط واحد 50"
        w1 = artext.measure(s, f_title.art_path, 96)
        _, pos, size, adv = artext._ink_mask(s, f_reg.art_path, 40, "rtl")
        # إثبات التشكيل الحقيقي: «لا» حرفان ← لازم يطلعوا glyph واحد (رابطة lam‑alef)
        lig = len(artext._shape("لا", f_reg.art_path, 40, "rtl"))
        ok = w1 > 0 and size[0] > 0 and lig == 1
        note = "" if ok else f"القياس/القناع/الروابط معطوبة (w={w1:.0f}, size={size}, لا→{lig} glyphs)"
    except Exception as ex:
        ok, note = False, str(ex)
    record("تشكيل العربي (HarfBuzz/FreeType بديل raqm)", ok, note)


def check_poster(tmp: str) -> str | None:
    out = os.path.join(tmp, "poster.png")
    p = run([sys.executable, "engine/make_poster.py", "--headline", "تجربة صحّة",
             "--stat", "50", "--unit", "كجم", "--sub", "فحص ذاتي للمحرك",
             "--out", out])
    ok = p.returncode == 0 and os.path.exists(out)
    size_ok = False
    if ok:
        from PIL import Image
        size_ok = Image.open(out).size == (1080, 1350)
    record("إنتاج بوستر 1080×1350", ok and size_ok, (p.stderr or p.stdout)[-300:] if not ok else "")
    return out if ok else None


def check_video(tmp: str) -> str | None:
    script = os.path.join(tmp, "script.json")
    voice = os.path.join(tmp, "tone.m4a")
    reel = os.path.join(tmp, "reel.mp4")
    with open(script, "w", encoding="utf-8") as f:
        json.dump({"title": "فحص", "duration": 3.2,
                   "scenes": [{"from": 0, "to": 3.2, "headline": "فحص ذاتي", "sub": "سلامة المحرك"}]}, f)
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    p0 = run([ff, "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3.2",
              "-c:a", "aac", voice])
    if p0.returncode != 0:
        record("إنتاج ريل 9:16 بصوت", False, "تعذّر توليد صوت الاختبار من ffmpeg")
        return None
    p = run([sys.executable, "engine/make_video.py", "--script", script,
             "--voice", voice, "--out", reel])
    ok = p.returncode == 0 and os.path.exists(reel)
    record("إنتاج ريل 9:16 بصوت", ok, (p.stderr or p.stdout)[-300:] if not ok else "")
    return reel if ok else None


def check_qa(reel: str | None) -> None:
    import qa_video
    if not reel:
        record("فحص الجودة qa_video", False, "لا يوجد ريل اختبار")
        return
    r = qa_video.qa(reel, "reels")
    record("فحص الجودة qa_video (على الريل المولّد)", r["pass"],
           "؛ ".join(r["fails"]) if not r["pass"] else "")


def check_critic() -> None:
    import critic
    clean = "الوزن على الطبيعة… زي ما هو ⚖️\nشوف بنفسك على الميزان.\n#TerraNex #استثمار_حيواني #الإسكندرية"
    bad = "عائد مضمون 30% بدون مخاطر"
    r1 = critic.check(clean)
    r2 = critic.check(bad)
    ok = r1["score"] >= 85 and not r1["hard"] and len(r2["hard"]) >= 2
    record("بوابة الالتزام critic (نظيف يعدّي / مخالف يُرفض)", ok,
           f"clean={r1['score']}/hard={len(r2['hard'])}")


def check_calendar(tmp: str) -> None:
    out = os.path.join(tmp, "cal.md")
    p = run([sys.executable, "engine/gen_calendar.py", "--days", "14", "--out", out])
    ok = p.returncode == 0 and os.path.exists(out)
    capped = False
    if ok:
        txt = open(out, encoding="utf-8").read()
        capped = txt.count("تصوير مطلوب") >= 1 and txt.count("جاهز للمونتاج") <= 7
    record("مولّد التقويم (سقف المادة الحقيقية 7)", ok and capped,
           (p.stderr or "")[-300:] if not ok else ("السقف غير مطبق" if ok else ""))


def check_ingest(tmp: str, reel: str | None) -> None:
    if not reel:
        record("استلام الفوتاج ingest (معزول)", False, "لا يوجد فيديو اختبار")
        return
    raw = os.path.join(tmp, "raw")
    inbox = os.path.join(raw, "وارد")
    os.makedirs(inbox, exist_ok=True)
    fake = os.path.join(inbox, "لقطة-اختبار.mp4")
    import shutil
    shutil.copyfile(reel, fake)
    p1 = run([sys.executable, "engine/ingest_footage.py"], env={"TX_RAW_DIR": raw})
    ledger = os.path.join(raw, "سجل-المواد-الخام.csv")
    ok = p1.returncode == 0 and os.path.exists(ledger) and "لقطة-اختبار" in open(ledger, encoding="utf-8").read()
    # المكرر يُرفض
    shutil.copyfile(reel, os.path.join(inbox, "نسخة-مكررة.mp4"))
    p2 = run([sys.executable, "engine/ingest_footage.py"], env={"TX_RAW_DIR": raw})
    dup_ok = os.path.exists(os.path.join(raw, "مكررات", "نسخة-مكررة.mp4"))
    record("استلام الفوتاج ingest (تنظيم + رفض مكرر)", ok and dup_ok,
           (p1.stderr or p2.stderr)[-300:] if not (ok and dup_ok) else "")


def check_package(tmp: str, reel: str | None) -> None:
    if not reel:
        record("تجهيز المنشور package_post (معزول)", False, "لا يوجد فيديو اختبار")
        return
    cap = os.path.join(tmp, "cap.txt")
    with open(cap, "w", encoding="utf-8") as f:
        f.write("الوزن على الطبيعة… زي ما هو ⚖️\nشوف بنفسك على الميزان.\n#TerraNex #استثمار_حيواني #الإسكندرية")
    out_dir = os.path.join(tmp, "out")
    p = run([sys.executable, "engine/package_post.py", "--video", reel, "--caption", cap,
             "--platforms", "facebook", "--date", "2026-10-20", "--time", "20:00",
             "--variants"], env={"TX_OUT_DIR": out_dir})
    queue = os.path.join(out_dir, "queue.csv")
    ok = p.returncode == 0 and os.path.exists(queue) and "بانتظار-موافقة" in open(queue, encoding="utf-8").read()
    vars_ok = os.path.exists(os.path.join(out_dir, "variants"))
    record("تجهيز المنشور package_post (فحص+قيد+نسخ منصات)", ok and vars_ok,
           (p.stderr or p.stdout)[-300:] if not ok else "")


def check_pauses(tmp: str) -> None:
    """مقطع كلام فيه وقفة — يجب قصّها: 2ث نغمة + 1.5ث صمت + 2ث نغمة → ≈4ث."""
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    src = os.path.join(tmp, "talk.mp4")
    p0 = run([ff, "-y", "-f", "lavfi", "-i", "color=c=0x102018:s=540x960:d=5.5:r=25",
              "-f", "lavfi", "-i", "sine=frequency=330:duration=2",
              "-f", "lavfi", "-t", "1.5", "-i", "anullsrc=r=48000:cl=mono",
              "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
              "-filter_complex", "[1:a][2:a][3:a]concat=n=3:v=0:a=1[a]",
              "-map", "0:v", "-map", "[a]", "-c:v", "libx264", "-pix_fmt", "yuv420p",
              "-c:a", "aac", src])
    out = os.path.join(tmp, "talk-cut.mp4")
    p1 = run([sys.executable, "engine/fix_pauses.py", "--in", src, "--out", out,
              "--min-pause", "0.5"])
    ok = p0.returncode == 0 and p1.returncode == 0 and os.path.exists(out)
    dur_ok = False
    if ok:
        import qa_video
        d = qa_video.probe(out).get("duration", 0)
        dur_ok = 3.2 <= d <= 4.6
    record("قصّ الوقفات fix_pauses (تنفيذ محلي بديل auto-editor)", ok and dur_ok,
           (p0.stderr or p1.stderr)[-300:] if not ok else "المدة بعد القص خارج المتوقع")


def check_montage(tmp: str, reel: str | None) -> None:
    """تركيب لقطتين عبر MoviePy — قصّ كل واحدة إلى ~1ث."""
    if not reel:
        record("المونتاج المتقاطع make_montage (MoviePy)", False, "لا يوجد ريل اختبار")
        return
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    c2 = os.path.join(tmp, "c2.mp4")
    run([ff, "-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=1080x1920:rate=25",
         "-f", "lavfi", "-i", "sine=frequency=500:duration=2",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", c2])
    out = os.path.join(tmp, "montage.mp4")
    p = run([sys.executable, "engine/make_montage.py", "--clips", reel, c2,
             "--trims", "0:1,0:1", "--out", out])
    ok = p.returncode == 0 and os.path.exists(out)
    dur_ok = False
    if ok:
        import qa_video
        d = qa_video.probe(out).get("duration", 0)
        dur_ok = abs(d - 2.0) < 0.35
    record("المونتاج المتقاطع make_montage (MoviePy/MIT)", ok and dur_ok,
           (p.stderr or "")[-300:] if not ok else "مدة المونتاج ≠ 2ث تقريبًا")


def _report() -> int:
    print("\n🩺 الفحص الذاتي — terranex-ops\n")
    fails = 0
    for name, ok, note in RESULTS:
        print(f"  {'✅' if ok else '⛔'} {name}")
        if note and not ok:
            print(f"      ← {note}")
        fails += 0 if ok else 1
    print(f"\nالنتيجة: {len(RESULTS) - fails}/{len(RESULTS)} سليم"
          + (" — النظام جاهز للعمل ✅" if fails == 0 else " — صلّح البنود المتعطلة (غالبًا: bash setup.sh)" ))
    print()
    return 0 if fails == 0 else 1


def main():
    quick = "--quick" in sys.argv
    check_deps()
    check_fonts()
    check_palette()
    check_arabic()
    check_critic()
    with tempfile.TemporaryDirectory(prefix="tx-ops-check-") as tmp:
        poster = check_poster(tmp)
        if poster is None and RESULTS[-1][1] is False and "setup.sh" in (RESULTS[-1][2] or ""):
            pass
        reel = None
        if not quick:
            reel = check_video(tmp)
            check_qa(reel)
            check_ingest(tmp, reel)
            check_package(tmp, reel)
            check_pauses(tmp)
            check_montage(tmp, reel)
        check_calendar(tmp)
    sys.exit(_report())


if __name__ == "__main__":
    main()
