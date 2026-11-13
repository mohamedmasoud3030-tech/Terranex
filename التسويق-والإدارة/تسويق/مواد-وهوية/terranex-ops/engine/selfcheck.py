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
    # This is an AV transport test using a sine tone, not a narrator or a
    # voice-00 identity sample. Keep production narration guards intact.
    silent = os.path.join(tmp, "silent.mp4")
    p = run([sys.executable, "engine/make_video.py", "--script", script,
             "--out", silent])
    if p.returncode == 0:
        p = run([ff, "-y", "-v", "error", "-i", silent, "-i", voice,
                 "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy",
                 "-c:a", "aac", "-t", "3.2", "-movflags", "+faststart", reel])
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
    clean = "الوزن على الطبيعة… زي ما هو ⚖️\nشوف بنفسك على الميزان.\n#TerraNex #استثمار_حيواني #ثروة_حيوانية"
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
        f.write("الوزن على الطبيعة… زي ما هو ⚖️\nشوف بنفسك على الميزان.\n#TerraNex #استثمار_حيواني #ثروة_حيوانية")
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


def check_campaign(tmp: str) -> None:
    """منسّق الحملة: فيكستشر 3.5ث + كابشن نظيف → تشغيل كامل ثم تنظيف."""
    import imageio_ffmpeg
    import shutil
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    vid = os.path.join(tmp, "camp-fix.mp4")
    cap = os.path.join(tmp, "camp-cap.txt")
    brief = os.path.join(tmp, "camp-brief.json")
    p0 = run([ff, "-y", "-f", "lavfi", "-i", "testsrc2=duration=3.5:size=1080x1920:rate=30",
              "-f", "lavfi", "-i", "sine=frequency=440:duration=3.5",
              "-af", "loudnorm=I=-15:TP=-1.5:LRA=11", "-c:v", "libx264",
              "-pix_fmt", "yuv420p", "-c:a", "aac", vid])
    with open(cap, "w", encoding="utf-8") as f:
        f.write("لقطة حقيقية من المزرعة النهارده\nوزن وفحص قبل التصوير — شوف بنفسك.\n#TerraNex #استثمار_حيواني #ثروة_حيوانية\n")
    import json as _json
    with open(brief, "w", encoding="utf-8") as f:
        _json.dump({"name": "فحص-ذاتي-حملة", "start": "2026-10-26",
                    "platforms": ["facebook", "instagram"],
                    "posts": [{"video": vid, "caption": cap, "title": "فحص-ذاتي-منشور"}]},
                   f, ensure_ascii=False)
    p1 = run([sys.executable, "engine/campaign_run.py", "--brief", brief])
    cdir = os.path.join(ROOT, "output", "campaigns", "فحص-ذاتي-حملة")
    q_ok = p1.returncode == 0 and os.path.isfile(os.path.join(cdir, "queue-campaign.csv"))
    files_ok = q_ok and len([x for x in os.listdir(cdir)]) >= 5
    if os.path.isdir(cdir):
        shutil.rmtree(cdir)
    record("منسّق الحملة campaign_run (بوابة ← تجهيز ← جدول+قالب قياس)",
           files_ok, (p0.stderr or p1.stderr or p1.stdout)[-300:] if not files_ok else "")


def check_measure(tmp: str) -> None:
    """القياس: قالب للفريق + تحليل النموذج المرجعي ينتج تقريرًا ثم يُنظّف."""
    t = os.path.join(tmp, "قالب-قياس.csv")
    p0 = run([sys.executable, "engine/measure.py", "--template", t])
    p1 = run([sys.executable, "engine/measure.py", "--csv", "data/week-00-نموذج.csv"])
    reports_dir = os.path.abspath(os.path.join(ROOT, "..", "..", "..", "إدارة", "تقارير-ومتابعة"))
    import datetime as _dt
    rep = os.path.join(reports_dir, f"قياس-الحملة-week-00-نموذج-{_dt.date.today().isoformat()}.md")
    ok = p0.returncode == 0 and p1.returncode == 0 and os.path.isfile(rep) and os.path.getsize(rep) > 200
    if ok:
        os.remove(rep)
    record("قياس الحملة measure (قالب فريق ← تحليل ← تقرير)",
           ok, (p0.stderr or p1.stderr)[-300:] if not ok else "")



def check_identity_rules() -> None:
    """فحص B9 الافتراضي واستثناء الحملة المحلية، ثم B10/B11."""
    import brand as B
    import critic
    import reel_build as R

    ok_b9 = len(critic.lint_city("إحنا في الإسكندرية")) > 0 and not critic.lint_city("استثمار حيواني")
    b9_hard = any(h["code"] == "B9" for h in critic.check("محتوى فيه الإسكندرية")["hard"])
    local = critic.check(
        "فتح الحجز لمحافظة الإسكندرية\n#TerraNex #خروف_برقي #ضاني_برقي",
        allow_delivery_city=True,
        campaign_scope="campaign_local",
        delivery_city_approval_note="طلب صريح من المالك",
        track="meat_orders",
        owner_approval={
            "decision_id": "SELF-CHECK-B9-LOCAL-001",
            "status": "approved",
            "approved_by": "owner",
            "approved_at": "2026-11-06",
            "source": "selfcheck-fixture",
            "scope": "campaign_local",
            "track": "meat_orders",
            "approved_claim": "city_mention",
        },
    )
    b9_local_allowed = not any(h["code"] == "B9" for h in local["hard"])

    owner_blocked = False
    try:
        R.require_consent({"clips": [], "on_screen_persons": ["owner"]})
    except SystemExit:
        owner_blocked = True
    owner_allowed = True
    try:
        R.require_consent({"clips": [], "on_screen_persons": ["owner"],
                           "consent_persons": ["owner"]})
    except SystemExit:
        owner_allowed = False

    # العلامة المائية: تُرسم فعلًا وتحتوي شعارًا (طبقة غير فارغة)
    from PIL import Image
    canvas = Image.new("RGB", (1080, 1350), (16, 30, 16)).convert("RGBA")
    before = canvas.tobytes()
    B.watermark(canvas, pos="bl", theme="dark")
    wm_drawn = canvas.tobytes() != before

    # الشعار الكبير: الحد الأدنى مفروض في القفل الكامل
    lg = B.logo(120, "full")
    logo_ok = lg.width >= B.LOGO_MIN_LOCKUP_W

    ok = ok_b9 and b9_hard and b9_local_allowed and owner_blocked and owner_allowed and wm_drawn and logo_ok
    detail = (f"B9={ok_b9 and b9_hard} · B9-local={b9_local_allowed} · B10={owner_blocked and owner_allowed} · "
              f"watermark={wm_drawn} · logo={lg.width}px")
    record("قواعد الهوية B9/B10/B11 (مدينة · إذن المالك · علامة مائية)", ok, detail)


# ملفات مسموح لها ذكر المدينة لأنها **تُعرِّف القاعدة** أو تختبرها فقط
CITY_ALLOWED_FILES = {"critic.py", "brand.py", "selfcheck.py", "reel_build.py"}


def check_no_city_in_engines() -> None:
    """حارس B9: لا مراجع مدينة صلبة في محركات الإنتاج خارج بوابات القاعدة.

    يمنع رجوع القاعدة (حصل فعلًا في make_reel_from_footage قبل التصحيح).
    """
    import glob
    import brand as B
    engine_dir = os.path.dirname(os.path.abspath(__file__))
    offenders = []
    for p in sorted(glob.glob(os.path.join(engine_dir, "*.py"))):
        name = os.path.basename(p)
        if name in CITY_ALLOWED_FILES:
            continue
        txt = open(p, encoding="utf-8").read()
        for c in B.CITY_BAN:
            if c in txt:
                offenders.append(f"{name}:{c}")
                break
    record("حارس B9 — لا اسم مدينة صلب خارج بوابات الاستثناء",
           not offenders, "؛ ".join(offenders))


def check_reel_tests() -> None:
    """اختبارات reel_build (قصّ آمن/إخفاء علامة/تزامن/أمان مسارات/توافق قوالب)."""
    r = run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"])
    tail = (r.stderr or "").strip().splitlines()
    note = tail[-1] if tail else ""
    record("اختبارات reel_build (قصّ/علامة/تزامن/مسارات/توافق)", r.returncode == 0, note)


def main():
    quick = "--quick" in sys.argv
    check_deps()
    check_fonts()
    check_palette()
    check_arabic()
    check_critic()
    check_identity_rules()
    check_no_city_in_engines()
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
            check_campaign(tmp)
            check_measure(tmp)
            check_reel_tests()
        check_calendar(tmp)
    sys.exit(_report())


if __name__ == "__main__":
    main()
